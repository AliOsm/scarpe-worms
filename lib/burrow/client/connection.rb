# frozen_string_literal: true

require "socket"
require "openssl"
require "uri"
require_relative "../protocol"

module Burrow
  module Client
    class Connection
      class TrustError < RuleError; end
      attr_reader :endpoint, :token, :id, :rtt

      def initialize(endpoint:, name:, token: nil, fingerprint: nil, allow_insecure: false, reconnect: true)
        @endpoint, @name, @token = endpoint.strip, name, token
        @fingerprint = fingerprint.to_s.delete(": ").downcase
        @allow_insecure, @reconnect = allow_insecure, reconnect
        @outbox = SizedQueue.new(96)
        @lock = Mutex.new
        @status, @message = "offline", ""
        @notices, @sequence = [], 0
        @stopping = false
        @rtt = 0
      end

      def connect
        return if @thread&.alive?
        @stopping = false
        @thread = Thread.new { run }
        self
      end

      def send_action(type, **values)
        @lock.synchronize do
          return false unless @status == "online"
          @sequence += 1
          @outbox.push(values.merge(type: type, seq: @sequence), true)
        end
        true
      rescue ThreadError
        false
      end

      def poll
        @lock.synchronize do
          if @state && @state["match"] && @terrain_packet && @state["match"]["terrain_revision"] == @terrain_packet["revision"]
            @state["match"]["terrain"] = @terrain_packet
            @terrain_packet = nil
          end
          value = {state: @state, status: @status, message: @message, notices: @notices, welcome: @welcome, rtt: rtt}
          @state, @welcome, @notices = nil, nil, []
          value
        end
      end

      def status = @lock.synchronize { @status }
      def sequence = @lock.synchronize { @sequence }

      def close
        @stopping = true
        @socket&.close
        @thread&.join(1)
        set_status("offline", "Disconnected")
      rescue IOError, SystemCallError
        nil
      end

      private

      def set_status(value, message)
        @lock.synchronize { @status, @message = value, message }
      end

      def run
        attempts = 0
        until @stopping
          begin
            set_status(attempts.zero? ? "connecting" : "reconnecting", attempts.zero? ? "Connecting…" : "Connection lost. Rejoining your room…")
            @welcomed = false
            session
            break
          rescue StandardError => error
            break if @stopping
            fatal = error.is_a?(RuleError) || error.is_a?(ArgumentError) || error.is_a?(URI::Error)
            set_status(fatal ? "rejected" : "reconnecting", friendly_error(error))
            break if fatal || !@reconnect
            attempts = @welcomed ? 1 : attempts + 1
            @outbox.clear
            delay = [0.5 * 2**[attempts, 4].min, 8].min
            deadline = Burrow.clock + delay
            sleep 0.05 while !@stopping && Burrow.clock < deadline
          ensure
            @socket&.close rescue nil
          end
        end
      end

      def session
        socket = open_socket
        output = Protocol.encode(type: "hello", version: PROTOCOL, name: @name, token: token)
        write_chunk = nil
        input = +"".b
        last_message = last_ping = Burrow.clock
        until @stopping
          loop do
            output << Protocol.encode(@outbox.pop(true))
          rescue ThreadError
            break
          end
          raise IOError, "The connection is too slow. Reconnecting…" if output.bytesize > Protocol::MAX_SERVER
          if Burrow.clock - last_ping >= 3
            output << Protocol.encode(type: "ping", at: Burrow.clock)
            last_ping = Burrow.clock
          end
          raise IOError, "The server stopped responding. Reconnecting…" if Burrow.clock - last_message > 12
          readable, writable = IO.select([socket], output.empty? ? nil : [socket], nil, 0.04) || [[], []]
          if !output.empty? && !writable.empty?
            write_chunk ||= output.byteslice(0, Protocol::WRITE_CHUNK)
            written = socket.write_nonblock(write_chunk, exception: false)
            if written.is_a?(Integer)
              output.slice!(0, written)
              write_chunk = nil
            end
          end
          pending = socket.respond_to?(:pending) && socket.pending > 0
          next if readable.empty? && !pending
          bytes = socket.read_nonblock(64 * 1024, exception: false)
          next if [:wait_readable, :wait_writable].include?(bytes)
          raise IOError, "The server disconnected. Rejoining…" unless bytes
          input << bytes
          while (newline = input.index("\n"))
            line = input.slice!(0, newline + 1).force_encoding(Encoding::UTF_8)
            raise RuleError, "The server sent invalid text." unless line.valid_encoding?
            message = Protocol.decode(line, limit: Protocol::MAX_SERVER)
            last_message = Burrow.clock
            receive(message)
          end
          raise RuleError, "Server message is too large." if input.bytesize > Protocol::MAX_SERVER
        end
      end

      def open_socket
        uri = URI.parse(endpoint.include?("://") ? endpoint : "tls://#{endpoint}")
        hostname = uri.hostname
        unless %w[tcp tls].include?(uri.scheme) && hostname && uri.port && uri.port.between?(1, 65535) && !uri.userinfo && !uri.query && !uri.fragment && uri.path.to_s.empty?
          raise ArgumentError, "Use tls://host:port, or tcp://host:port on a trusted local network."
        end
        if uri.scheme == "tcp" && !%w[127.0.0.1 localhost ::1].include?(hostname) && !@allow_insecure
          raise ArgumentError, "Choose TLS for online play, or enable trusted LAN connections in settings."
        end
        tcp = Socket.tcp(hostname, uri.port, connect_timeout: 4)
        tcp.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
        @socket = tcp
        return tcp unless uri.scheme == "tls"
        raise ArgumentError, "The server fingerprint must contain 64 hexadecimal characters." unless @fingerprint.empty? || @fingerprint.match?(/\A[0-9a-f]{64}\z/)
        context = OpenSSL::SSL::SSLContext.new
        context.min_version = OpenSSL::SSL::TLS1_2_VERSION
        # Pinned self-hosted certificates are checked explicitly before any token is sent.
        context.set_params(verify_mode: @fingerprint.empty? ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE)
        ssl = OpenSSL::SSL::SSLSocket.new(tcp, context)
        ssl.sync_close = true
        ssl.hostname = hostname
        @socket = ssl
        deadline = Burrow.clock + 5
        loop do
          result = ssl.connect_nonblock(exception: false)
          break unless [:wait_readable, :wait_writable].include?(result)
          raise IOError, "TLS handshake timed out." if Burrow.clock > deadline
          raise IOError, "Connection cancelled." if @stopping
          IO.select(result == :wait_readable ? [tcp] : nil, result == :wait_writable ? [tcp] : nil, nil, 0.1)
        end
        if @fingerprint.empty?
          begin
            ssl.post_connection_check(hostname)
          rescue OpenSSL::SSL::SSLError => error
            raise TrustError, error.message
          end
        else
          actual = Digest::SHA256.hexdigest(ssl.peer_cert.to_der)
          raise TrustError, "Server fingerprint changed." unless OpenSSL.fixed_length_secure_compare(actual, @fingerprint)
        end
        ssl
      rescue OpenSSL::SSL::SSLError => error
        # Certificate failures are terminal. An interrupted TLS transport (even
        # during its handshake) is retryable, just like an interrupted TCP link.
        if ssl && @fingerprint.empty? && ssl.verify_result != OpenSSL::X509::V_OK
          raise TrustError, error.message
        end
        raise
      end

      def receive(message)
        case message["type"]
        when "welcome"
          raise RuleError, "Protocol version mismatch." unless message["version"] == PROTOCOL
          @welcomed = true
          @lock.synchronize do
            @token, @id = message.fetch("token"), message.fetch("id")
            @sequence = message.fetch("seq", 0)
            @welcome = message
            @status, @message = "online", "Connected"
          end
        when "fatal"
          raise RuleError, message.fetch("message", "Connection rejected.")
        when "error"
          @lock.synchronize { @notices = (@notices + [message.fetch("message")]).last(12) }
        when "state"
          @lock.synchronize do
            @terrain_packet = message.dig("match", "terrain") if message.dig("match", "terrain")
            @state = message
          end
        when "pong"
          at = message["at"]
          @rtt = ((Burrow.clock - at) * 1000).round if at.is_a?(Numeric)
        end
      end

      def friendly_error(error)
        case error
        when Errno::ECONNREFUSED then "Server unavailable. Check that it is running and the address is correct."
        when TrustError then "The secure connection could not be verified. Check the address and fingerprint."
        when OpenSSL::SSL::SSLError then "The secure connection was interrupted. Rejoining your room…"
        when SocketError then "That server address could not be found."
        else error.message.to_s[0, 180]
        end
      end
    end
  end
end
