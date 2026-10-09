# frozen_string_literal: true

require "socket"
require "openssl"
require "logger"
require_relative "../../burrow"
require_relative "../protocol"
require_relative "../mac_activity"
require_relative "room"

module Burrow
  module Server
    class Peer
      attr_accessor :io, :input, :output, :session, :handshake, :last_read, :last_seq,
        :terrain_revision, :match_id, :closing, :tokens, :token_at, :chat_at, :last_snapshot, :write_chunk
      attr_reader :address, :created
      def initialize(io, address, tls: false)
        @io, @address, @created = io, address, Burrow.clock
        @input, @output = +"".b, +"".b
        @handshake = tls ? :read : false
        @last_read = @token_at = created
        @last_seq, @tokens, @terrain_revision, @chat_at, @last_snapshot = 0, 60, -1, 0, 0
      end

      def allowed?
        now = Burrow.clock
        @tokens = [60, tokens + (now - token_at) * 35].min
        @token_at = now
        return false if tokens < 1
        @tokens -= 1
        true
      end
    end

    # Socket I/O, room mutation, simulation, and checkpoint writes have one owner.
    # Slow readers are bounded; no peer can block a match or grow an unbounded queue.
    class Reactor
      MAX_PEERS = 128
      MAX_ROOMS = 16
      attr_reader :port, :rooms, :sessions, :metrics, :fingerprint, :host

      def initialize(host: "127.0.0.1", port: 4388, data_dir: nil, certificate: nil, key: nil,
        allow_insecure_lan: false, logger: Logger.new($stdout))
        if !certificate && !%w[127.0.0.1 ::1 localhost].include?(host) && !allow_insecure_lan
          raise ArgumentError, "Public listeners require TLS. Supply --cert/--key or use automatic TLS in bin/server."
        end
        @host, @data_dir, @logger = host, data_dir, logger
        @activity = MacActivity.new("Burrow Brigade live match simulation")
        @rooms, @sessions, @peers = {}, {}, {}
        @metrics = {ticks: 0, max_tick_ms: 0.0, clients: 0, rejected: 0, recovered: 0}
        @tls = tls_context(certificate, key) if certificate
        lock_data if data_dir
        restore if data_dir
        @listener = TCPServer.new(host, port)
        @port = @listener.addr[1]
        @running, @stop = false, false
      rescue StandardError
        @data_lock&.close
        raise
      end

      def run
        @running = true
        next_tick = Burrow.clock
        next_save = next_tick + 2
        @logger.info("Burrow Brigade listening on #{host}:#{port} (#{@tls ? 'TLS' : 'local TCP'})")
        until @stop
          now = Burrow.clock
          if now >= next_tick
            @activity.active = rooms.values.any? { |room| room.match && !room.match.finished? && room.members.any? { |m| !m[:bot] && m[:connected] } }
            started = Burrow.clock
            # A bounded catch-up prevents lag from becoming a spiral of late ticks.
            steps = [((now - next_tick) / DT).floor + 1, 4].min
            rooms.values.each do |room|
              room.match&.step(steps) if room.members.any? { |m| !m[:bot] && m[:connected] }
              save_replay(room) if room.match&.finished? && !room.saved_result
            end
            @metrics[:ticks] += steps
            @metrics[:max_tick_ms] = [@metrics[:max_tick_ms], (Burrow.clock - started) * 1000].max
            next_tick += steps * DT
            next_tick = now + DT if next_tick < now - 4 * DT
            broadcast if @metrics[:ticks] % 3 < steps
            expire(now)
          end
          if now >= next_save
            persist
            next_save = now + 2
          end
          readers = [@listener] + @peers.keys
          writers = @peers.values.select { |p| p.handshake == :write || (!p.handshake && !p.output.empty?) }.map { |p| p.io.to_io }
          readable, writable = IO.select(readers, writers, nil, [(next_tick - Burrow.clock), 0].max) || [[], []]
          readable.each { |socket| socket == @listener ? accept_peer : read_peer(@peers[socket]) }
          writable.each { |socket| write_peer(@peers[socket]) }
          # OpenSSL can retain decrypted bytes after the kernel socket is drained.
          @peers.values.dup.each { |p| read_peer(p) if !p.handshake && p.io.respond_to?(:pending) && p.io.pending > 0 }
        end
      ensure
        @activity.close
        @running = false
        @peers.values.dup.each { |peer| disconnect(peer) }
        persist
        @listener&.close unless @listener&.closed?
        @data_lock&.close
      end

      def running? = @running
      def stop = (@stop = true)

      private

      def lock_data
        FileUtils.mkdir_p(@data_dir, mode: 0o700)
        @data_lock = File.open(File.join(@data_dir, "server.lock"), File::RDWR | File::CREAT, 0o600)
        unless @data_lock.flock(File::LOCK_EX | File::LOCK_NB)
          raise RuleError, "Another server is using this data directory. Choose a different --data directory."
        end
      end

      def tls_context(certificate, key)
        raise ArgumentError, "Supply a key with the certificate." unless key
        OpenSSL::SSL::SSLContext.new.tap do |context|
          context.min_version = OpenSSL::SSL::TLS1_2_VERSION
          context.cert = OpenSSL::X509::Certificate.new(File.read(certificate))
          context.key = OpenSSL::PKey.read(File.read(key))
          @fingerprint = Digest::SHA256.hexdigest(context.cert.to_der)
        end
      end

      def accept_peer
        socket = @listener.accept_nonblock(exception: false)
        return if socket == :wait_readable
        address = socket.peeraddr[3]
        if @peers.size >= MAX_PEERS || @peers.values.count { |p| p.address == address } >= 24
          socket.close
          return
        end
        socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
        io = @tls ? OpenSSL::SSL::SSLSocket.new(socket, @tls).tap { |ssl| ssl.sync_close = true } : socket
        @peers[socket] = Peer.new(io, address, tls: !!@tls)
        @metrics[:clients] += 1
      rescue IOError, SystemCallError
        socket&.close
      end

      def handshake(peer)
        result = peer.io.accept_nonblock(exception: false)
        peer.handshake = {wait_readable: :read, wait_writable: :write}.fetch(result, false)
      rescue IOError, SystemCallError, OpenSSL::SSL::SSLError
        disconnect(peer)
      end

      def read_peer(peer)
        return unless peer && !peer.closing
        return handshake(peer) if peer.handshake
        bytes = peer.io.read_nonblock(16 * 1024, exception: false)
        return if [:wait_readable, :wait_writable].include?(bytes)
        return disconnect(peer) unless bytes
        peer.last_read = Burrow.clock
        peer.input << bytes
        while (newline = peer.input.index("\n"))
          line = peer.input.slice!(0, newline + 1).force_encoding(Encoding::UTF_8)
          raise RuleError, "Invalid text encoding." unless line.valid_encoding?
          raise RuleError, "Too many messages. Reconnect in a moment." unless peer.allowed?
          message = Protocol.decode(line)
          receive(peer, message)
          break if peer.closing
        end
        raise RuleError, "Message too large." if peer.input.bytesize > Protocol::MAX_CLIENT
      rescue RuleError => error
        @metrics[:rejected] += 1
        enqueue(peer, type: "fatal", message: error.message)
        peer.closing = true
      rescue IOError, SystemCallError, OpenSSL::SSL::SSLError
        disconnect(peer)
      end

      def write_peer(peer)
        return unless peer
        return handshake(peer) if peer.handshake
        return if peer.output.empty?
        # OpenSSL retries must see the same bytes even if a new snapshot was
        # enqueued while the previous write waited for socket capacity.
        peer.write_chunk ||= peer.output.byteslice(0, Protocol::WRITE_CHUNK)
        written = peer.io.write_nonblock(peer.write_chunk, exception: false)
        return unless written.is_a?(Integer)
        peer.output.slice!(0, written)
        peer.write_chunk = nil
        disconnect(peer) if peer.closing && peer.output.empty?
      rescue IOError, SystemCallError, OpenSSL::SSL::SSLError
        disconnect(peer)
      end

      def receive(peer, message)
        type = message["type"]
        if type == "ping"
          enqueue(peer, type: "pong", at: message["at"].is_a?(Numeric) ? message["at"] : 0)
          return
        end
        return hello(peer, message) unless peer.session
        seq = message["seq"]
        raise RuleError, "Invalid command sequence." unless seq.is_a?(Integer) && seq.between?(1, 2**53 - 1)
        return if seq <= peer.last_seq
        peer.last_seq = seq
        peer.session[:last_seq] = seq
        peer.session[:seen_at] = Time.now.to_i
        begin
          route(peer, type, message)
          enqueue(peer, type: "ack", seq: seq)
        rescue RuleError, KeyError => error
          enqueue(peer, type: "error", seq: seq, message: error.is_a?(KeyError) ? "Missing command parameter." : error.message)
        end
      end

      def hello(peer, message)
        raise RuleError, "Say hello before entering a room." unless message["type"] == "hello"
        raise RuleError, "This client and server use different protocol versions." unless message["version"] == PROTOCOL
        token = message["token"]
        session = token.is_a?(String) && token.bytesize == 64 ? sessions[Digest::SHA256.hexdigest(token)] : nil
        if token && !session
          raise RuleError, "Your saved session expired. Connect as a new player."
        end
        if session
          old = @peers.values.find { |p| p != peer && p.session && p.session[:id] == session[:id] }
          disconnect(old) if old
        else
          raise RuleError, "The server is busy. Try again later." if sessions.size >= 2048
          name = Protocol.name(message["name"])
          token = SecureRandom.hex(32)
          session = {id: SecureRandom.hex(8), name: name, room: nil, last_seq: 0, seen_at: Time.now.to_i}
          sessions[Digest::SHA256.hexdigest(token)] = session
        end
        peer.session = session
        peer.last_seq = session[:last_seq]
        session[:seen_at] = Time.now.to_i
        room_for(peer)&.connected(session[:id], true)
        enqueue(peer, type: "welcome", version: PROTOCOL, id: session[:id], name: session[:name], token: token, seq: peer.last_seq)
        send_state(peer, full: true)
      end

      def route(peer, type, message)
        session = peer.session
        room = room_for(peer)
        case type
        when "list"
          enqueue(peer, type: "rooms", rooms: rooms.values.map(&:summary))
        when "create"
          raise RuleError, "Leave your current room first." if room
          raise RuleError, "The server has reached its room limit." if rooms.size >= MAX_ROOMS
          code = nil
          loop do
            code = Array.new(6) { "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"[SecureRandom.random_number(32)] }.join
            break unless rooms.key?(code)
          end
          name = message.fetch("name", "#{session[:name]}'s room"[0, 24])
          bots = message.fetch("bots", 0)
          if !bots.is_a?(Integer) || !bots.between?(0, 5)
            raise RuleError, "Choose 0–5 computer teams."
          end
          room = Room.new(code: code, host: session, name: name, config: message.fetch("config", {}), password: message.fetch("password", ""))
          bots.times { room.command(session[:id], "add_bot", {}) }
          rooms[code] = room
          session[:room] = code
          send_state(peer, full: true)
        when "join"
          raise RuleError, "Leave your current room first." if room
          code = message.fetch("code")
          raise RuleError, "Room codes contain six letters or numbers." unless code.is_a?(String) && code.strip.match?(/\A[a-zA-Z0-9]{6}\z/)
          code = code.upcase.strip
          room = rooms[code]
          raise RuleError, "That room could not be found." unless room
          room.join(session, message.fetch("password", ""))
          session[:room] = code
          send_state(peer, full: true)
        when "leave"
          room&.leave(session[:id])
          session[:room] = nil
          prune_rooms
          send_state(peer, full: true)
        when "sync"
          send_state(peer, full: true)
        else
          raise RuleError, "Join a room first." unless room
          if type == "chat"
            raise RuleError, "Wait a moment before sending another message." if Burrow.clock - peer.chat_at < 0.7
            peer.chat_at = Burrow.clock
          end
          kicked = room.command(session[:id], type, message)
          if type == "kick" && kicked
            sessions.each_value { |s| s[:room] = nil if s[:id] == kicked }
            @peers.values.select { |p| p.session && p.session[:id] == kicked }.each do |p|
              enqueue(p, type: "error", message: "The host removed your team from the room.")
              send_state(p, full: true)
            end
          end
        end
      end

      def room_for(peer) = rooms[peer.session && peer.session[:room]]

      def send_state(peer, full: false)
        room = room_for(peer)
        if room
          match = room.match
          new_match = match && peer.match_id != match.object_id
          with_terrain = match && (full || new_match || peer.terrain_revision != match.terrain.revision)
          enqueue(peer, type: "state", ack: peer.last_seq, room: room.snapshot, match: match&.snapshot(terrain: with_terrain))
          if match
            peer.terrain_revision = match.terrain.revision
            peer.match_id = match.object_id
          end
        else
          enqueue(peer, type: "state", room: nil, match: nil, rooms: rooms.values.map(&:summary))
        end
      end

      def broadcast
        @peers.values.dup.each do |peer|
          next unless peer.session && !peer.closing
          # Never discard a partially written frame; bounded backlog triggers reconnect.
          next if peer.output.bytesize > 128 * 1024
          room = room_for(peer)
          frequency = room&.match && !room.match.finished? ? 0.095 : 0.35
          next if Burrow.clock - peer.last_snapshot < frequency
          peer.last_snapshot = Burrow.clock
          send_state(peer)
        end
      end

      def enqueue(peer, value)
        return unless peer
        peer.output << Protocol.encode(value)
        disconnect(peer) if peer.output.bytesize > Protocol::MAX_SERVER * 2
      end

      def disconnect(peer)
        return unless peer
        @peers.delete(peer.io.to_io)
        if peer.session
          peer.session[:seen_at] = Time.now.to_i
          room_for(peer)&.connected(peer.session[:id], false)
        end
        peer.io.close
      rescue IOError, SystemCallError
        nil
      end

      def expire(now)
        @peers.values.dup.each do |peer|
          disconnect(peer) if now - peer.last_read > 18 || (!peer.session && now - peer.created > 8)
        end
        return unless @metrics[:ticks] % 300 == 0
        online = @peers.values.filter_map { |p| p.session&.fetch(:id) }
        sessions.delete_if do |_, session|
          next false if online.include?(session[:id])
          expired = Time.now.to_i - session[:seen_at] > 24 * 60 * 60
          rooms[session[:room]]&.leave(session[:id]) if expired
          expired
        end
        prune_rooms
      end

      def prune_rooms
        rooms.delete_if { |_, room| room.human_ids.empty? }
      end

      def persist
        return unless @data_dir
        Burrow.atomic_json(File.join(@data_dir, "server.json"), {version: 1, rooms: rooms.values.map(&:checkpoint), sessions: sessions})
      rescue SystemCallError => error
        @logger.error("Checkpoint failed: #{error.class}")
      end

      def restore
        path = File.join(@data_dir, "server.json")
        return unless File.exist?(path)
        value = JSON.parse(File.read(path, encoding: Encoding::UTF_8), max_nesting: 32)
        raise RuleError, "Unsupported server checkpoint version." unless value["version"] == 1
        @sessions = value.fetch("sessions").transform_values { |s| s.transform_keys(&:to_sym) }
        value.fetch("rooms").each do |entry|
          room = Room.restore(entry)
          rooms[room.code] = room
          @metrics[:recovered] += 1
        end
      rescue JSON::ParserError, KeyError, RuleError => error
        # Never silently overwrite a damaged save with an empty server.
        raise RuleError, "Cannot recover #{path}: #{error.message}. Restore a backup or move this file aside."
      end

      def save_replay(room)
        if @data_dir
          value = {version: 1, config: room.config.to_h, teams: room.match.initial_teams, inputs: room.match.inputs,
            ticks: room.match.tick, winner: room.match.winner, terrain_checksum: room.match.terrain.checksum}
          Burrow.atomic_json(File.join(@data_dir, "replays", "#{room.code}-#{room.match_id}.json"), value)
        end
        room.saved_result = true
      rescue SystemCallError => error
        @logger.error("Replay save failed: #{error.class}")
      end
    end
  end
end
