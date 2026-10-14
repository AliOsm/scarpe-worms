# frozen_string_literal: true
# Real mixed-version host/client sessions, TCP/TLS and a userspace jitter proxy.
# Always run captures under .perf-round/bin/bench (one invocation is < 2 minutes).
# PERF_AGENT=net TMPDIR=<scratch>/tmp BURROW_NET_ROOT=<client tree> \
# BURROW_NET_HOST_ROOT=<host tree> mise exec ruby@4.0.7 -- bundle exec ruby \
#   tools/perf_net_session.rb --transport tls --remote --rounds 3 --output <capture.json>
# Remote uses the machine's non-loopback address upstream of a separate-process
# ordered TCP proxy, so the unmodified host really takes its 10 Hz remote path.
# Latency ends at Timeline presentation, not scanout. Terrain latency ends at
# worker results. Scheduling lateness includes OS/GC/GVL, not just the GVL.
require "optparse"
require "json"
require "tmpdir"
require "socket"
require "rbconfig"

options = {transport: "tcp", remote: false, rounds: 3, output: nil, child: nil, terrain: false}
OptionParser.new do |p|
  p.on("--transport VALUE") { |v| options[:transport] = v }
  p.on("--remote") { options[:remote] = true }
  p.on("--terrain") { options[:terrain] = true }
  p.on("--rounds N", Integer) { |v| options[:rounds] = v }
  p.on("--output PATH") { |v| options[:output] = v }
  p.on("--child KIND") { |v| options[:child] = v }
end.parse!

class NetChild
  attr_reader :ready, :pid
  def initialize(kind, options)
    paths = $LOAD_PATH.map(&:b).join(File::PATH_SEPARATOR)
    @io = IO.popen([RbConfig.ruby, "-EUTF-8", "-I", paths, __FILE__, "--child", kind], "r+:UTF-8")
    @io.sync = true
    @pid = @io.pid
    @io.puts(JSON.generate(options))
    raise "#{kind} startup timed out" unless IO.select([@io], nil, nil, 12)
    @ready = JSON.parse(@io.gets || "{}")
    raise "#{kind} startup failed: #{@ready}" unless @ready["port"]
  end

  def close
    return if @closed
    @closed = true
    @io&.close_write
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    while @pid && Process.waitpid(@pid, Process::WNOHANG).nil?
      if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        Process.kill("KILL", @pid)
        Process.waitpid(@pid)
        break
      end
      sleep 0.01
    end
    @io&.close
  rescue Errno::ECHILD, Errno::ESRCH, IOError
    nil
  end
end

if options[:child] == "proxy"
  STDOUT.sync = true
  config = JSON.parse(STDIN.gets)
  listener = TCPServer.new("127.0.0.1", 0)
  stopped = false
  Thread.new { STDIN.read; stopped = true }
  puts JSON.generate(port: listener.addr[1])
  sockets, destinations, queues, counts, latest = [], {}, {}, Hash.new(0), Hash.new(0)
  until stopped
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    writable = sockets.select { |s| queues[s].first && queues[s].first[0] <= now }
    readers, writers = IO.select([listener, *sockets], writable, nil, 0.002) || [[], []]
    readers.each do |socket|
      if socket == listener
        client = listener.accept
        upstream = Socket.tcp(config.fetch("host"), config.fetch("port"))
        [client, upstream].each { |s| s.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1) }
        sockets = [client, upstream]
        destinations = {client => upstream, upstream => client}
        queues = {client => [], upstream => []}
        next
      end
      data = socket.read_nonblock(64 * 1024, exception: false)
      next if data == :wait_readable
      if data.nil?
        sockets.each(&:close)
        sockets, destinations, queues = [], {}, {}
        break
      end
      to = destinations.fetch(socket)
      # 15 ms upstream; ordered downstream bursts of 0/10/35/5/55/0 ms
      # on top of 15 ms. No loss or reordering is introduced into TCP.
      delay = 0.015 + (to == sockets.first ? [0, 0.010, 0.035, 0.005, 0.055, 0][counts[to] % 6] : 0)
      counts[to] += 1
      due = [Process.clock_gettime(Process::CLOCK_MONOTONIC) + delay, latest[to]].max
      latest[to] = due
      queues[to] << [due, data]
      raise "Proxy queue exceeded bound" if queues[to].sum { |_, bytes| bytes.bytesize } > 2 * 1024 * 1024
    end
    writers.each do |socket|
      next if socket.closed? || !queues[socket]&.first
      row = queues[socket].first
      count = socket.write_nonblock(row[1], exception: false)
      next unless count.is_a?(Integer)
      count == row[1].bytesize ? queues[socket].shift : row[1] = row[1].byteslice(count..)
    end
  end
  sockets.each(&:close)
  listener.close
  exit
end

source = ENV.fetch("BURROW_NET_ROOT") { File.expand_path("..", __dir__) }
host_source = ENV.fetch("BURROW_NET_HOST_ROOT", source)
if options[:child] == "host"
  require File.join(host_source, "lib/burrow/server/reactor")
  if ENV["BURROW_NET_EXPERIMENT"] == "cadence"
    Burrow::Server::Reactor.prepend(Module.new do
      def snapshot_interval(peer, room)
        return 0 if peer.loopback && room&.match && !room.match.finished?
        super
      end
    end)
  end
  STDOUT.sync = true
  config = JSON.parse(STDIN.gets, symbolize_names: true)
  trace_path = config.delete(:trace_path)
  explosions = []
  if trace_path
    Burrow::Match.prepend(Module.new do
      define_method(:explode) do |*args, **kwargs|
        started = Burrow.clock
        super(*args, **kwargs).tap do
          explosions << {started: started, finished: Burrow.clock, tick: tick, revision: terrain.revision}
        end
      end
    end)
  end
  server = Burrow::Server::Reactor.new(**config, logger: Logger.new(File::NULL))
  Thread.new { STDIN.read; server.stop }
  puts JSON.generate(port: server.port, fingerprint: server.fingerprint)
  server.run
  File.write(trace_path, JSON.generate(explosions)) if trace_path
  exit
end

require File.join(source, "lib/burrow")
require File.join(source, "lib/burrow/client/app")
require File.join(source, "lib/burrow/server/certificate")

module NetSession
  module_function
  def cpu = Process.clock_gettime(Process::CLOCK_THREAD_CPUTIME_ID)
  def host_cpu(pid)
    return unless File.exist?("/proc/#{pid}/stat")
    fields = File.read("/proc/#{pid}/stat").split
    (fields[13].to_i + fields[14].to_i) / 100.0
  end
  def stats(values)
    a = values.sort
    return {n: 0} if a.empty?
    {n: a.size, median: a[a.size / 2], p95: a[[(a.size * 0.95).floor, a.size - 1].min],
      min: a.first, max: a.last, iqr: a[(a.size * 0.75).floor] - a[(a.size * 0.25).floor], mean: a.sum.fdiv(a.size)}
  end
end

Burrow::Protocol.singleton_class.prepend(Module.new do
  def decode(line, **options)
    cpu, wall = NetSession.cpu, Burrow.clock
    super.tap { Thread.current[:net_decode] = [line.bytesize, (NetSession.cpu - cpu) * 1000, wall, Burrow.clock] }
  end
end)

class NetConnection < Burrow::Client::Connection
  attr_reader :snapshots
  def initialize(**options)
    @snapshots = []
    super
  end

  def receive(message, **options)
    at, cpu = Burrow.clock, NetSession.cpu
    super
    if message["type"] == "state" && message["match"]
      @snapshots << [at, message["match"]["tick"], *Thread.current[:net_decode], (NetSession.cpu - cpu) * 1000]
    end
  end
end

class NetApp < Burrow::Client::App
  attr_reader :timeline, :presented, :visible, :frames, :received_events, :ack, :terrain_times
  def initialize(connection)
    @connection = connection
    @connection_status = "online"
    @audio = Object.new
    def @audio.local_action(*) = nil
    @scene = Struct.new(:terrain_revision).new(0)
    @presented, @visible, @frames, @received_events = [], [], [], []
    @terrain_times = []
  end

  def enable_terrain
    @terrain_worker = Burrow::Client::TerrainArt.new
    @terrain_packet_revision = nil
  end

  def close = @terrain_worker&.close

  def notify(message) = raise(message)

  def frame
    started, cpu = Burrow.clock, NetSession.cpu
    packet = connection.poll
    raise packet[:notices].join("; ") unless packet[:notices].empty?
    if (value = packet[:state])
      @ack = value.fetch("ack", 0)
      @pending_action = nil if @pending_action && value.fetch("ack", 0) >= @pending_action
      @room, @state = value.values_at("room", "match")
      if @state
        if @match_id != @room["match_id"]
          @timeline = Burrow::Client::Timeline.new
          @match_id = @room["match_id"]
        end
        @timeline.accept(@state)
        @received_events.concat(@state["events"].map { |e| [started, e["id"], e["kind"]] })
        if @terrain_worker && @state["terrain"] && @terrain_packet_revision != @state["terrain_revision"]
          @terrain_packet_revision = @state["terrain_revision"]
          request_cpu = NetSession.cpu
          @terrain_worker.request(@state["terrain"], @state["config"]["biome"])
          @terrain_requests ||= {}
          @terrain_requests[@terrain_packet_revision] = [started, Burrow.clock, (NetSession.cpu - request_cpu) * 1000]
        end
      end
    end
    return unless @state
    view = @timeline.sample
    @visible << [Burrow.clock, view["projectiles"].map { |s| s["id"] }] if view["projectiles"].any?
    @timeline.events.each { |event| @presented << [Burrow.clock, event["kind"], event["id"]] }
    if @terrain_worker && (result = @terrain_worker.poll)
      ready = Burrow.clock
      raise "Terrain checksum mismatch" unless result[:preview_terrain].checksum == result[:checksum]
      @terrain_times << {revision: result[:revision], ready: ready, request: @terrain_requests.fetch(result[:revision]), checksum: result[:checksum]}
    end
    raise @terrain_worker.error if @terrain_worker&.error
    @frames << [started, (Burrow.clock - started) * 1000, (NetSession.cpu - cpu) * 1000,
      @timeline.tick, @timeline.delay, @timeline.backlog_ms, @timeline.underruns, @timeline.resyncs]
  end

  def pump(seconds: nil, timeout: 15)
    at = Burrow.clock
    deadline = at + (seconds || timeout)
    loop do
      frame
      return if block_given? && yield
      break if Burrow.clock >= deadline
      at += 1.0 / 60
      sleep [at - Burrow.clock, 0].max
    end
    raise "Session timeout: #{connection.status} / #{@room && @room['code']}" unless seconds
  end
end

report = {schema: 1, source: source, host_source: host_source, ruby: RUBY_DESCRIPTION,
  protocol: Burrow::PROTOCOL, transport: options[:transport], remote: options[:remote], rounds: options[:rounds],
  experiment: ENV["BURROW_NET_EXPERIMENT"]}
Dir.mktmpdir("net-session-") do |directory|
  address = options[:remote] ? Socket.ip_address_list.find { |a| a.ipv4? && !a.ipv4_loopback? }.ip_address : "127.0.0.1"
  settings = {host: address, port: 0, data_dir: directory, allow_insecure_lan: options[:remote]}
  settings[:trace_path] = File.join(directory, "explosions.json") if options[:terrain]
  if options[:transport] == "tls"
    certificate, key = Burrow::Server::Certificate.ensure_pair(File.join(directory, "tls"))
    settings.merge!(certificate: certificate, key: key)
  end
  host = NetChild.new("host", settings)
  proxy = NetChild.new("proxy", host: address, port: host.ready["port"]) if options[:remote]
  port = proxy ? proxy.ready["port"] : host.ready["port"]
  client_options = {endpoint: "#{options[:transport]}://127.0.0.1:#{port}", name: "Net fixture", fingerprint: host.ready["fingerprint"], reconnect: false}
  connection = NetConnection.new(**client_options).connect
  app = NetApp.new(connection)
  app.pump { connection.status == "online" }
  latencies = Hash.new { |h, k| h[k] = [] }
  guards = []
  options[:rounds].times do |i|
    app.action("create", name: "Net fixture", bots: 1, config: {"seed" => "net-session-#{i}",
      "mines" => 0, "barrels" => 0, "crates" => false, "worms" => 2, "turn_seconds" => 90})
    app.pump { app.room && !app.state }
    app.action("start")
    app.pump { app.state }
    app.pump(seconds: 2.3 + i % 3 * 0.013)
    [["jump", {}, "jump"], ["fire", {weapon: "super_sheep"}, "fire"], ["activate", {}, "activate"]].each do |type, values, event|
      app.presented.clear
      app.visible.clear
      started = Burrow.clock
      type == "jump" ? app.action(type, **values) : app.submit_weapon(type, **values)
      app.pump { app.presented.any? { |_, kind, _| kind == event } }
      latencies["#{type}_event_ms"] << (app.presented.find { |_, kind, _| kind == event }[0] - started) * 1000
      if type == "fire"
        app.pump { app.visible.any? }
        latencies["fire_projectile_ms"] << (app.visible.first[0] - started) * 1000
      end
      app.pump(seconds: type == "jump" ? 0.85 : 0.15)
    end
    guards << {underruns: app.timeline.underruns, resyncs: app.timeline.resyncs}
    app.action("leave")
    app.pump { !app.room }
  end
  app.action("create", name: "Load", bots: 5, config: {"seed" => "net-session-load", "worms" => 6, "turn_seconds" => 90})
  app.pump { app.room }
  app.enable_terrain if options[:terrain]
  app.action("start")
  app.pump { app.state }
  app.pump(seconds: 2.5)
  app.frames.clear
  connection.snapshots.clear
  load_at, host_cpu = Burrow.clock, NetSession.host_cpu(host.pid)
  app.pump(seconds: 5)
  elapsed = Burrow.clock - load_at
  host_cpu_ms = host_cpu && (NetSession.host_cpu(host.pid) - host_cpu) * 1000 / elapsed
  rows = connection.snapshots.dup
  frames = app.frames.dup
  report[:latency] = latencies.transform_values { |v| NetSession.stats(v) }
  report[:latency_raw] = latencies
  report[:guards] = guards + [{underruns: app.timeline.underruns, resyncs: app.timeline.resyncs}]
  report[:load] = {bytes: NetSession.stats(rows.map { |r| r[2] }), parse_cpu_ms: NetSession.stats(rows.map { |r| r[3] }),
    host_cpu_ms_per_second: host_cpu_ms, snapshot_rate_hz: rows.size / elapsed,
    receive_cpu_ms: NetSession.stats(rows.map { |r| r[6] }), frame_cpu_ms: NetSession.stats(frames.map { |r| r[2] }),
    snapshot_intervals_ms: NetSession.stats(rows.each_cons(2).map { |a, b| (b[0] - a[0]) * 1000 }),
    frame_intervals_ms: NetSession.stats(frames.each_cons(2).map { |a, b| (b[0] - a[0]) * 1000 }),
    backlog_ms: NetSession.stats(frames.map { |r| r[5] }), delay_ticks: NetSession.stats(frames.map { |r| r[4] }),
    frames_raw: frames, snapshots_raw: rows}
  if options[:terrain]
    app.pump { app.terrain_times.any? }
    initial = app.terrain_times.last[:revision]
    app.presented.clear
    started = Burrow.clock
    app.submit_weapon("fire", weapon: "rocket", angle: 90, power: 0.7)
    app.pump { app.terrain_times.last[:revision] > initial && app.presented.any? { |_, kind, _| kind == "explosion" } }
    report[:crater] = {input_at: started, event_at: app.presented.find { |_, kind, _| kind == "explosion" }.first,
      result: app.terrain_times.last}
    app.close
  end
  # Both compatibility directions exercise full terrain, incremental history,
  # acknowledged actions, and a token-based reconnect followed by full sync.
  saved = [connection.token, connection.id, connection.sequence, app.room["code"], app.room["match_id"]]
  connection.close
  connection = NetConnection.new(**client_options, token: saved[0]).connect
  app = NetApp.new(connection)
  app.pump { app.state && app.state["terrain"] }
  raise "Reconnect changed identity" unless [connection.token, connection.id, app.room["code"], app.room["match_id"]] == [saved[0], saved[1], saved[3], saved[4]]
  raise "Reconnect lost sequence" unless connection.sequence == saved[2]
  raise "Reconnect lost terrain" unless Burrow::Terrain.restore(app.state["terrain"]).checksum == app.state["terrain_checksum"]
  raise "Reconnect lost history" unless app.state.dig("motion", "frames").size == 18
  app.action("sync")
  seq = connection.sequence
  app.pump { app.ack >= seq && app.state["terrain"] && app.state["motion"]["frames"].size == 18 }
  report[:interop] = {reconnect_identity: true, resumed_sequence: saved[2], full_terrain_checksum: app.state["terrain_checksum"],
    full_history: 18, sync_sequence: seq,
    input_events_presented: latencies.sum { |kind, samples| kind.end_with?("_event_ms") ? samples.length : 0 }}
ensure
  app&.close
  connection&.close
  proxy&.close
  host&.close
  if options[:terrain] && settings && File.exist?(settings[:trace_path])
    report[:explosions] = JSON.parse(File.read(settings[:trace_path]))
  end
end
json = JSON.pretty_generate(report) + "\n"
options[:output] ? File.write(options[:output], json) : puts(json)
