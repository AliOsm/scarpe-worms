# frozen_string_literal: true
require_relative "test_helper"
require_relative "../lib/burrow/server/reactor"
require_relative "../lib/burrow/server/certificate"
require_relative "../lib/burrow/client/connection"

class WireClient
  attr_reader :socket, :id, :token, :sequence
  def initialize(port, name: "Test team", token: nil)
    @socket = TCPSocket.new("127.0.0.1", port)
    @buffer, @pending, @sequence = +"", [], 0
    write(type: "hello", version: Burrow::PROTOCOL, name: name, token: token)
    welcome = read_type("welcome")
    @id, @token, @sequence = welcome.values_at("id", "token", "seq")
  end

  def write(value) = socket.write(Burrow::Protocol.encode(value))
  def action(type, **values)
    @sequence += 1
    write(values.merge(type: type, seq: sequence))
    receive { |m| %w[ack error].include?(m["type"]) && m["seq"] == sequence }
  end

  def read_type(type, &block) = receive { |m| m["type"] == type && (!block || block.call(m)) }
  def state(&block) = read_type("state", &block)
  def receive(seconds: 6)
    deadline = Burrow.clock + seconds
    loop do
      if (index = @pending.index { |m| yield m })
        return @pending.delete_at(index)
      end
      while (newline = @buffer.index("\n"))
        @pending << JSON.parse(@buffer.slice!(0, newline + 1))
      end
      next if @pending.any? { |m| yield m }
      remaining = deadline - Burrow.clock
      raise "Timed out waiting for server message (#{@pending.last(3)})" if remaining <= 0
      next unless IO.select([socket], nil, nil, remaining)
      @buffer << socket.read_nonblock(512 * 1024)
    end
  end

  def close = (socket.close unless socket.closed?)
end

class NetworkTest < Minitest::Test
  def setup
    @directory = Dir.mktmpdir("burrow-network-test-")
    @clients, @connections = [], []
    start_server
  end

  def teardown
    @clients.each(&:close)
    @connections.each(&:close)
    stop_server
    FileUtils.remove_entry(@directory)
  end

  def start_server(**options)
    @server = Burrow::Server::Reactor.new(port: 0, data_dir: @directory, logger: Logger.new(StringIO.new), **options)
    @thread = Thread.new { @server.run }
    @thread.report_on_exception = false
    wait_for { @server.running? || !@thread.alive? }
    @thread.value unless @thread.alive?
  end

  def stop_server
    @server&.stop
    raise "Server failed to stop" if @thread && !@thread.join(8)
    @thread&.value
  end

  def client(**options)
    WireClient.new(@server.port, **options).tap { |c| @clients << c }
  end

  def accepted(client, type, **values)
    reply = client.action(type, **values)
    assert_equal "ack", reply["type"], reply.inspect
    reply
  end

  def rejected(client, type, **values)
    reply = client.action(type, **values)
    assert_equal "error", reply["type"], reply.inspect
    reply
  end

  def test_six_players_permissions_readiness_terrain_reconnect_and_rematch
    players = 6.times.map { |i| client(name: "Team #{i + 1}") }
    host = players.first
    accepted(host, "create", name: "Six friends", config: {"mines" => 0, "barrels" => 0, "crates" => false, "retreat_seconds" => 0})
    code = host.state { |m| m["room"] }.dig("room", "code")
    players.drop(1).each { |c| accepted(c, "join", code: code) }
    seventh = client(name: "Overflow")
    assert_match(/six/, rejected(seventh, "join", code: code)["message"])
    rejected(players[1], "configure", config: {"seed" => "changed"})
    rejected(players[1], "kick", player: host.id)
    rejected(players[1], "start")
    rejected(host, "start")
    players.drop(1).each { |c| accepted(c, "ready", ready: true) }
    accepted(host, "configure", config: {"mines" => 0, "barrels" => 0, "crates" => false, "retreat_seconds" => 0})
    rejected(host, "start") # Editing rules cancels stale readiness.
    players.drop(1).each { |c| accepted(c, "ready", ready: true) }
    accepted(players[2], "chat", text: "A real six-player round!")
    assert_equal "A real six-player round!", host.state { |m| m.dig("room", "messages")&.any? }.dig("room", "messages", -1, "text")
    accepted(host, "start")
    initial = players.map { |c| c.state { |m| m["match"] } }
    checksums = initial.map { |s| Burrow::Terrain.restore(s.dig("match", "terrain")).checksum }
    assert_equal 1, checksums.uniq.size
    assert_equal 18, initial.first.dig("match", "worms").size
    rejected(players[1], "fire", weapon: "rocket", angle: 55, power: 0.5)
    accepted(host, "fire", weapon: "grenade", angle: -50, power: 0.6, fuse: 5)
    in_flight = host.state { |s| s.dig("match", "projectiles")&.any? }
    host.close
    resumed = client(token: host.token)
    resumed_state = resumed.state { |s| s["match"] }
    assert_equal host.id, resumed.id
    assert_equal code, resumed_state.dig("room", "code")
    assert_equal in_flight.dig("match", "projectiles", 0, "id"), resumed_state.dig("match", "projectiles", 0, "id")
    assert resumed_state.dig("match", "terrain"), "Resuming needs a full terrain snapshot"
    players.drop(1).each { |c| accepted(c, "surrender") }
    final = resumed.state { |s| s.dig("match", "phase") == "finished" }
    assert_equal host.id, final.dig("match", "winner")
    new_host = players.find { |c| c.id == final.dig("room", "host_id") }
    accepted(new_host, "rematch")
    lobby = resumed.state { |s| s["room"] && !s["match"] }
    assert_equal 6, lobby.dig("room", "members").size
    players.drop(1).each { |c| accepted(c, "ready", ready: true) }
    accepted(resumed, "ready", ready: true)
    accepted(new_host, "start")
    resumed.state { |s| s["match"] }
    players.drop(1).each { |c| accepted(c, "surrender") }
    resumed.state { |s| s.dig("match", "phase") == "finished" }
    wait_for { Dir[File.join(@directory, "replays/*.json")].size == 2 }
    assert_equal 2, Dir[File.join(@directory, "replays/*.json")].size, "Rematches must not overwrite match logs"
  end

  def test_password_kick_host_migration_and_session_revocation
    host, guest = client(name: "Host"), client(name: "Guest")
    accepted(host, "create", name: "Private", password: "secret")
    code = host.state { |s| s["room"] }.dig("room", "code")
    rejected(guest, "join", code: code, password: "wrong")
    accepted(guest, "join", code: code, password: "secret")
    accepted(host, "kick", player: guest.id)
    guest.state { |s| !s["room"] }
    accepted(guest, "join", code: code, password: "secret")
    accepted(host, "leave")
    assert_equal guest.id, guest.state { |s| s.dig("room", "host_id") == guest.id }.dig("room", "host_id")
    accepted(guest, "add_bot")
  end

  def test_restart_recovers_the_exact_paused_projectile_and_session
    host = client
    accepted(host, "create", name: "Recovery", bots: 1, config: {"mines" => 0, "barrels" => 0})
    accepted(host, "start")
    accepted(host, "fire", weapon: "cluster", angle: -65, power: 0.65, fuse: 5)
    host.state { |s| s.dig("match", "projectiles")&.any? }
    stop_server
    saved = JSON.parse(File.read(File.join(@directory, "server.json")))
    checkpoint = saved.fetch("rooms").first.fetch("match")
    start_server
    assert_equal 1, @server.metrics[:recovered]
    sleep 0.1
    assert_equal checkpoint.dig("state", "tick"), @server.rooms.values.first.match.tick
    returning = client(token: host.token)
    resumed = returning.state { |s| s["match"] }.fetch("match")
    assert_equal host.id, returning.id
    assert_equal checkpoint.dig("terrain", "checksum"), resumed["terrain_checksum"]
    assert_equal checkpoint.dig("projectiles", 0, "id"), resumed.dig("projectiles", 0, "id")
    assert resumed["tick"] >= checkpoint.dig("state", "tick")
  end

  def test_bad_types_frames_rate_limits_and_duplicate_sequences_do_not_break_server
    host = client
    [nil, 42, [], {}, true].each do |bad|
      rejected(host, "create", name: bad)
      rejected(host, "create", name: "Valid", config: bad == {} ? {"invalid" => 0} : bad)
      rejected(host, "join", code: bad)
    end
    accepted(host, "create", name: "Valid", bots: 1)
    accepted(host, "start")
    rejected(host, "fire", weapon: {})
    rejected(host, "move", direction: 1, lift: {})
    before = @server.rooms.values.first.match.active[:input]
    assert_equal 0, before, "Rejected movement must be atomic"
    accepted(host, "fire", weapon: "rocket", angle: -40, power: 0.5)
    host.write(type: "fire", seq: host.sequence, weapon: "rocket", angle: -40, power: 0.5)
    accepted(host, "sync")
    assert_equal 1, @server.rooms.values.first.match.inputs.count { |i| i[:type] == "fire" }
    ["[1,2]\n", "{oops}\n", "{\"type\":\"ping\",\"x\":\"" + "a" * Burrow::Protocol::MAX_CLIENT,
      "\xff\n".b, '{"type":"ping"}' + "\n"].each_with_index do |frame, i|
      socket = TCPSocket.new("127.0.0.1", @server.port)
      frame *= 100 if i == 4
      socket.write(frame)
      wait_for { @server.metrics[:rejected] >= i + 1 }
      socket.close
      assert @thread.alive?
    end
    accepted(host, "sync")
  end

  def test_data_directory_is_exclusive_and_corrupt_checkpoints_are_preserved
    error = assert_raises(Burrow::RuleError) do
      Burrow::Server::Reactor.new(port: 0, data_dir: @directory)
    end
    assert_match(/Another server/, error.message)
    stop_server
    path = File.join(@directory, "server.json")
    File.write(path, "broken state")
    assert_raises(Burrow::RuleError) { Burrow::Server::Reactor.new(port: 0, data_dir: @directory) }
    assert_equal "broken state", File.read(path)
  end

  def test_tls_pinning_and_real_client_terrain_coalescing
    stop_server
    cert, key = Burrow::Server::Certificate.ensure_pair(File.join(@directory, "tls"))
    start_server(certificate: cert, key: key)
    make = lambda do |pin|
      Burrow::Client::Connection.new(endpoint: "tls://127.0.0.1:#{@server.port}", name: "TLS tester", fingerprint: pin, reconnect: false).connect.tap { |c| @connections << c }
    end
    bad = make.call("0" * 64)
    wait_for { bad.status == "rejected" }
    assert_nil bad.token, "Credentials must not cross an unverified connection"
    untrusted = make.call("")
    wait_for { untrusted.status == "rejected" }
    assert_nil untrusted.token, "An untrusted certificate must fail before authentication"
    good = make.call(@server.fingerprint)
    wait_for { good.status == "online" }
    # A 36-grub snapshot spans TLS records and contains multibyte turn text.
    assert good.send_action("create", name: "TLS équipe", bots: 5, config: {"worms" => 6})
    wait_for { good.poll.dig(:state, "room") }
    assert good.send_action("start")
    sleep 0.75 # Deliberately let several snapshots coalesce before polling.
    state = wait_for { good.poll[:state] }
    assert state.dig("match", "terrain")
    assert_equal 36, state.dig("match", "worms").length
    assert_equal state.dig("match", "terrain_checksum"), Burrow::Terrain.restore(state.dig("match", "terrain")).checksum
  end

  def test_invalid_addresses_fail_promptly_and_ipv6_loopback_connects
    invalid = Burrow::Client::Connection.new(endpoint: "tls://bad host:4388", name: "Invalid").connect
    @connections << invalid
    wait_for { invalid.status == "rejected" }
    assert_nil invalid.token
    stop_server
    start_server(host: "::1")
    ipv6 = Burrow::Client::Connection.new(endpoint: "tcp://[::1]:#{@server.port}", name: "IPv6 player", reconnect: false).connect
    @connections << ipv6
    wait_for { ipv6.status == "online" }
    assert ipv6.id
  end

  def test_each_authenticated_reconnection_resets_the_retry_delay
    connection = Burrow::Client::Connection.new(endpoint: "tcp://127.0.0.1:#{@server.port}", name: "Returning player").connect
    @connections << connection
    wait_for { connection.status == "online" }
    identity = connection.id
    3.times do
      port = @server.port
      stop_server
      wait_for { connection.status == "reconnecting" }
      start_server(port: port)
      wait_for(seconds: 2.7) { connection.status == "online" }
      assert_equal identity, connection.id
    end
  end

  def test_truncated_tls_stream_reconnects_without_losing_the_identity
    cert, key = Burrow::Server::Certificate.ensure_pair(File.join(@directory, "interrupted-tls"))
    context = OpenSSL::SSL::SSLContext.new
    context.cert = OpenSSL::X509::Certificate.new(File.read(cert))
    context.key = OpenSSL::PKey.read(File.read(key))
    listener = TCPServer.new("127.0.0.1", 0)
    pin = Digest::SHA256.hexdigest(context.cert.to_der)
    gate, hellos = Queue.new, Queue.new
    token = SecureRandom.hex(32)
    server_thread = Thread.new do
      2.times do
        tls = OpenSSL::SSL::SSLSocket.new(listener.accept, context)
        tls.sync_close = true
        tls.accept
        hellos << JSON.parse(tls.gets)
        tls.write(Burrow::Protocol.encode(type: "welcome", version: Burrow::PROTOCOL, id: "same-player", token: token, seq: 0))
        gate.pop
        # Simulate a cable drop/process crash, without TLS close_notify.
        tls.to_io.close
      end
    ensure
      tls&.close rescue nil
    end
    server_thread.report_on_exception = false
    connection = Burrow::Client::Connection.new(endpoint: "tls://127.0.0.1:#{listener.addr[1]}", name: "TLS return", fingerprint: pin).connect
    @connections << connection
    wait_for { connection.status == "online" }
    assert_nil hellos.pop["token"]
    gate << true
    wait_for { connection.status != "online" }
    assert_equal "reconnecting", connection.status
    wait_for { connection.status == "online" }
    assert_equal token, hellos.pop["token"]
    assert_equal "same-player", connection.id
  ensure
    2.times { gate << true } if gate
    connection&.close
    listener&.close
    server_thread&.join(2) rescue nil
    server_thread&.kill if server_thread&.alive?
  end

  def test_pending_tls_write_keeps_its_bytes_when_more_frames_are_queued
    # Model OpenSSL's retry contract, including a partial byte count inside a
    # multibyte character. A growing outbox must not change the pending write.
    transport = Object.new
    attempts, delivered = [], +"".b
    transport.define_singleton_method(:write_nonblock) do |data, exception:|
      attempts << data.dup
      next :wait_writable if attempts.length == 1
      size = attempts.length == 2 ? 7 : data.bytesize
      delivered << data.byteslice(0, size)
      size
    end
    peer = Burrow::Server::Peer.new(transport, "test")
    first = Burrow::Protocol.encode(type: "écho", value: "îles " * 4000)
    second = Burrow::Protocol.encode(type: "state", value: "next")
    peer.output << first
    @server.send(:write_peer, peer)
    peer.output << second
    @server.send(:write_peer, peer)
    assert_equal attempts[0], attempts[1], "A TLS retry cannot change buffer contents or length"
    @server.send(:write_peer, peer) until peer.output.empty?
    assert_equal first + second, delivered
    assert_equal ["écho", "state"], delivered.lines.map { |line| JSON.parse(line)["type"] }
  end
end
