# frozen_string_literal: true
# Real ProcessHost + Connection + App input + Timeline + OpenAL submission.
# No window/device latency is claimed; Linux uses the OpenAL null mixer.
require "optparse"
require "tmpdir"
source_root = ENV.fetch("BURROW_LATENCY_ROOT") { File.expand_path("..", __dir__) }
require File.join(source_root, "lib/burrow")
require File.join(source_root, "lib/burrow/client/app")

options = {rounds: 8, output: "/tmp/burrow-latency.json"}
OptionParser.new do |parser|
  parser.on("--rounds N", Integer) { |n| options[:rounds] = n }
  parser.on("--output PATH") { |path| options[:output] = path }
end.parse!
ENV["ALSOFT_DRIVERS"] ||= "null" if RUBY_PLATFORM.include?("linux")

def stats(values)
  sorted = values.sort
  return {count: 0} if sorted.empty?
  {count: sorted.length, mean: sorted.sum.fdiv(sorted.length), p50: sorted[sorted.length / 2],
    p95: sorted[[(sorted.length * 0.95).floor, sorted.length - 1].min], max: sorted.last}
end

Burrow::Protocol.singleton_class.prepend(Module.new do
  def decode(line, **options)
    cpu = Process.clock_gettime(Process::CLOCK_THREAD_CPUTIME_ID)
    result = super
    Thread.current[:latency_decode] = [line.bytesize, (Process.clock_gettime(Process::CLOCK_THREAD_CPUTIME_ID) - cpu) * 1000]
    result
  end
end)

class MeasuredConnection < Burrow::Client::Connection
  attr_reader :snapshots
  def initialize(**options)
    @snapshots = []
    super
  end

  def receive(message)
    row = [Burrow.clock, message["match"]["tick"], *Thread.current[:latency_decode]] if message["type"] == "state" && message["match"]
    cpu = Process.clock_gettime(Process::CLOCK_THREAD_CPUTIME_ID)
    super
    @snapshots << [*row, (Process.clock_gettime(Process::CLOCK_THREAD_CPUTIME_ID) - cpu) * 1000] if row
  end
end

class MeasuredAudio < Burrow::Client::Audio
  attr_reader :heard
  def initialize(*)
    @heard = []
    super
    @submissions = []
    submissions = @submissions
    @al.singleton_class.prepend(Module.new do
      define_method(:alSourcePlay) do |source|
        super(source).tap { submissions << Burrow.clock }
      end
    end) if @al
  end

  def play(name, **options)
    before = @submissions&.length
    result = super
    @heard << [@submissions.last, name] if before && @submissions.length > before
    result
  end
end

class LatencyApp < Burrow::Client::App
  attr_reader :timeline, :presented, :visible, :backlogs, :delays
  def initialize(connection, audio)
    @connection, @audio = connection, audio
    @connection_status = "online"
    @scene = Struct.new(:terrain_revision).new(0)
    @presented, @visible, @backlogs, @delays = [], [], [], []
  end

  def notify(message) = raise(message)

  def frame
    packet = connection.poll
    raise packet[:notices].join("; ") unless packet[:notices].empty?
    if (value = packet[:state])
      @pending_action = nil if @pending_action && value.fetch("ack", 0) >= @pending_action
      @room, @state = value.values_at("room", "match")
      if @state
        if @match_id != @room["match_id"]
          @timeline = Burrow::Client::Timeline.new
          @match_id = @room["match_id"]
        end
        @timeline.accept(@state)
      end
    end
    return unless @state
    view = @timeline.sample
    now = Burrow.clock
    @visible << now if view["projectiles"].any?
    @timeline.events.each do |event|
      @presented << [now, event["kind"]]
      @audio.event(event)
    end
    @backlogs << @timeline.backlog_ms
    @delays << @timeline.delay if @timeline.respond_to?(:delay)
  end

  def pump(seconds: nil, timeout: 8)
    start = Burrow.clock
    deadline = start + (seconds || timeout)
    loop do
      frame
      return if block_given? && yield
      break if Burrow.clock >= deadline
      sleep [start + 1.0 / 60 - Burrow.clock, 0].max
      start += 1.0 / 60
    end
    raise "Latency harness timed out" unless seconds
  end
end

def host_cpu(pid)
  return unless File.exist?("/proc/#{pid}/stat")
  fields = File.read("/proc/#{pid}/stat").split
  # Linux USER_HZ is 100 on the supported x86_64/aarch64 targets.
  (fields[13].to_i + fields[14].to_i) / 100.0
end

def measure(transport, rounds)
  Dir.mktmpdir("burrow-latency-") do |directory|
    server_options = {host: "127.0.0.1", port: 0, data_dir: directory}
    if transport == "tls"
      cert, key = Burrow::Server::Certificate.ensure_pair(File.join(directory, "tls"))
      server_options.merge!(certificate: cert, key: key)
    end
    host = Burrow::Server::ProcessHost.new(**server_options)
    connection = MeasuredConnection.new(endpoint: "#{transport}://127.0.0.1:#{host.port}",
      name: "Latency", fingerprint: host.fingerprint, reconnect: false).connect
    audio = MeasuredAudio.new({"muted" => false, "music" => true, "volume" => 0.4})
    raise "OpenAL unavailable: #{audio.error}" unless audio.available
    app = LatencyApp.new(connection, audio)
    app.pump { connection.status == "online" }
    measurements = Hash.new { |h, k| h[k] = [] }
    rounds.times do |round|
      app.action("create", name: "Latency", bots: 1, config: {"seed" => "latency-#{round}",
        "mines" => 0, "barrels" => 0, "crates" => false, "worms" => 2, "turn_seconds" => 90})
      app.pump { app.room && !app.state }
      app.action("start")
      app.pump { app.state }
      app.pump(seconds: 1.1 + (round % 3) * 0.013)
      [["jump", {}, "jump", "jump"], ["fire", {weapon: "super_sheep"}, "fire", "equip"],
        ["activate", {}, "activate", "launch"]].each do |type, values, kind, cue|
        audio.heard.clear
        app.presented.clear
        app.visible.clear
        started = Burrow.clock
        type == "jump" ? app.action(type, **values) : app.submit_weapon(type, **values)
        app.pump { app.presented.any? { |_, k| k == kind } }
        measurements["#{type}_to_event_ms"] << (app.presented.find { |_, k| k == kind }.first - started) * 1000
        heard = audio.heard.find { |_, name| name == cue }
        raise "Missing #{cue} sound" unless heard
        measurements["#{type}_to_audio_ms"] << (heard.first - started) * 1000
        if type == "fire"
          app.pump { !app.visible.empty? }
          measurements["fire_to_projectile_ms"] << (app.visible.first - started) * 1000
        end
        app.pump(seconds: type == "jump" ? 0.85 : 0.15)
      end
      app.action("leave")
      app.pump { !app.room }
    end
    # Stable six-team/36-grub load, including periodic saves; no generation in CPU window.
    app.action("create", name: "Load", bots: 5, config: {"worms" => 6, "turn_seconds" => 90})
    app.pump { app.room }
    app.action("start")
    app.pump { app.state }
    app.pump(seconds: 1)
    connection.snapshots.clear
    app.backlogs.clear
    app.delays.clear
    cpu, at = host_cpu(host.pid), Burrow.clock
    app.pump(seconds: 5)
    elapsed = Burrow.clock - at
    cost = cpu && (host_cpu(host.pid) - cpu) * 1000 / elapsed
    rows = connection.snapshots.dup
    intervals = rows.each_cons(2).filter_map { |a, b| (b[0] - a[0]) * 1000 if b[1] > a[1] }
    {latency: measurements.transform_values { |v| stats(v) }, snapshot_rate_hz: rows.length / elapsed,
      arrival_ms: stats(intervals), payload_bytes: stats(rows.map { |r| r[2] }),
      parse_cpu_ms: stats(rows.map { |r| r[3] }), parse_cpu_ms_per_second: rows.sum { |r| r[3] } / elapsed,
      receive_cpu_ms: stats(rows.map { |r| r[4] }), receive_cpu_ms_per_second: rows.sum { |r| r[4] } / elapsed,
      host_cpu_ms_per_second: cost, backlog_ms: stats(app.backlogs), delay_ticks: stats(app.delays)}
  ensure
    connection&.close
    host&.stop
    audio&.close
  end
end

report = {ruby: RUBY_DESCRIPTION, platform: RUBY_PLATFORM, rounds: options[:rounds],
  weapon: "super_sheep (fire, then walking-to-flying activation)", load: "six teams, 36 grubs, one snapshot recipient; five-second CPU window",
  audio_measurement: "OpenAL source submission, not acoustic output", projectile_measurement: "Timeline sample, not pixels",
  tcp: measure("tcp", options[:rounds]), tls: measure("tls", options[:rounds])}
File.write(options[:output], JSON.pretty_generate(report) + "\n")
puts JSON.pretty_generate(report)
