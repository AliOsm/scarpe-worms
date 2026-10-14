# frozen_string_literal: true
# Network/terrain CPU and allocation fixtures; run each capture under .perf-round/bin/bench.
# PERF_AGENT=net TMPDIR=<scratch>/tmp BURROW_NET_ROOT=<source tree> \
#   mise exec ruby@4.0.7 -- bundle exec ruby tools/perf_net_work.rb --mode terrain --output <capture.json>
# Modes: decode (JSON alternatives + timed receiver/GUI heartbeat), terrain (real
# worker and identical PNG digests), playback (deterministic jitter/UI stalls),
# timeline (36-grub interpolation CPU/allocations and exact presentation digest),
# png (encoding alternatives), wire (incompatible compressed-envelope prototype).
# Both trees use this instrumentation and the same seeds. Raw samples are retained.
# Heartbeat lateness includes OS scheduling/GC: it is not a direct GVL hold probe.
require "optparse"
require "tmpdir"
require "json"

options = {mode: "decode", output: nil}
OptionParser.new do |p|
  p.on("--mode MODE") { |v| options[:mode] = v }
  p.on("--output PATH") { |v| options[:output] = v }
end.parse!
source = ENV.fetch("BURROW_NET_ROOT") { File.expand_path("..", __dir__) }
require File.join(source, "lib/burrow")
require File.join(source, "lib/burrow/client/connection")
require File.join(source, "lib/burrow/client/timeline")
if ENV["BURROW_NET_EXPERIMENT"] == "lower_buffer"
  path = File.join(source, "lib/burrow/client/timeline.rb")
  prototype = File.read(path).sub("MIN_DELAY = 1.5", "MIN_DELAY = 1.0")
    .sub("* TICK_RATE + 0.5", "* TICK_RATE + (timing[:interval] <= 0.04 ? 0.0 : 0.5)")
  %i[DELAY MIN_DELAY MAX_BACKLOG].each { |name| Burrow::Client::Timeline.send(:remove_const, name) }
  eval(prototype, TOPLEVEL_BINDING, path)
end

module NetWork
  module_function

  def cpu = Process.clock_gettime(Process::CLOCK_THREAD_CPUTIME_ID)

  def stats(values)
    a = values.sort
    return {n: 0} if a.empty?
    {n: a.size, median: a[a.size / 2], p95: a[[(a.size * 0.95).floor, a.size - 1].min],
      min: a.first, max: a.last, iqr: a[(a.size * 0.75).floor] - a[(a.size * 0.25).floor], mean: a.sum.fdiv(a.size)}
  end

  def measured
    gc, allocated, time, wall = GC.count, GC.stat(:total_allocated_objects), cpu, Burrow.clock
    result = yield
    [result, {wall_ms: (Burrow.clock - wall) * 1000, cpu_ms: (cpu - time) * 1000,
      allocations: GC.stat(:total_allocated_objects) - allocated, gc: GC.count - gc}]
  end

  def summarize(rows)
    {summary: rows.first.keys.to_h { |key| [key, stats(rows.map { |r| r[key] })] }, raw: rows}
  end

  def packet
    players = 6.times.map { |i| {id: "p#{i}", name: Burrow::TEAM_NAMES[i]} }
    match = Burrow::Match.new(players: players, config: Burrow::Config.new("seed" => "perf-net-36", "worms" => 6))
    match.step(90)
    full = {type: "state", ack: 12, room: {code: "ABCDEF", match_id: "perf-net"}, match: match.snapshot}
    incremental = full.merge(match: full[:match].merge(motion: full[:match][:motion].merge(frames: full[:match][:motion][:frames].last(2))))
    {incremental: Burrow::Protocol.encode(incremental), full: Burrow::Protocol.encode(full)}
  end

  def decode
    packets = packet
    decoders = {
      protocol: ->(line) { Burrow::Protocol.decode(line, limit: Burrow::Protocol::MAX_SERVER) },
      explicit_no_additions: ->(line) { JSON.parse(line, max_nesting: 12, allow_nan: false, create_additions: false) },
      frozen_envelopes: lambda { |line|
        value = JSON.parse(line, max_nesting: 12, allow_nan: false, freeze: true).dup
        value["match"] = value["match"].dup if value["match"]
        value
      }
    }
    results = packets.to_h do |kind, line|
      expected = JSON.parse(line)
      variants = decoders.to_h do |name, decoder|
        raise "Decoder changed data" unless decoder.call(line) == expected
        50.times { decoder.call(line) }
        rows = 500.times.map { measured { decoder.call(line) }.last }
        [name, summarize(rows)]
      end
      [kind, {bytes: line.bytesize, variants: variants}]
    end
    # A 1 kHz main-thread observer alongside a 30 Hz receiver, with the same
    # scheduler and collection overhead in the control. No window/scanout claim.
    results[:heartbeat] = [false, true].to_h do |active|
      connection = Burrow::Client::Connection.new(endpoint: "tcp://127.0.0.1:1", name: "Heartbeat")
      line = packets[:incremental]
      rows, windows = [], []
      start = Burrow.clock + 0.05
      receiver = Thread.new do
        120.times do |i|
          deadline = start + i / 30.0
          sleep [deadline - Burrow.clock, 0].max
          if active
            at = Burrow.clock
            message, work = measured { Burrow::Protocol.decode(line, limit: Burrow::Protocol::MAX_SERVER) }
            connection.send(:receive, message)
            windows << [at, Burrow.clock, work]
          end
        end
      end
      4000.times do |i|
        deadline = start + i / 1000.0
        sleep [deadline - Burrow.clock, 0].max
        rows << [deadline, Burrow.clock]
        connection.poll
      end
      receiver.join
      lateness = rows.map { |deadline, actual| (actual - deadline) * 1000 }
      overlap = rows.filter_map do |deadline, actual|
        (actual - deadline) * 1000 if windows.any? { |a, b, _| deadline >= a && deadline < b }
      end
      [active ? :decode : :control, {lateness_ms: stats(lateness), decode_overlap_lateness_ms: stats(overlap),
        lateness_raw_ms: lateness, decode_windows: windows}]
    end
    results
  end

  def tile_digests(result)
    @pixel_digests ||= {}
    pixels = lambda do |path|
      @pixel_digests[path] ||= begin
        png = ChunkyPNG::Image.from_file(path)
        Digest::SHA256.hexdigest([png.width, png.height].pack("N*") + png.pixels.pack("N*"))
      end
    end
    {tiles: result[:tiles].to_h { |t| [t[:id], Digest::SHA256.file(t[:path]).hexdigest] },
      tile_pixels: result[:tiles].to_h { |t| [t[:id], pixels.call(t[:path])] },
      overview_pixels: pixels.call(result[:overview]), overview_bytes: File.size(result[:overview]),
      overview: Digest::SHA256.file(result[:overview]).hexdigest,
      checksum: result[:checksum], revision: result[:revision]}
  end

  def terrain
    require File.join(Burrow::ROOT, "lib/burrow/client/terrain_art")
    require File.join(Burrow::ROOT, "lib/burrow/client/terrain_painter")
    terrain = Burrow::Terrain.new(seed: 291, width: 4800, height: 1600)
    collision_work = []
    Burrow::Terrain.prepend(Module.new do
      define_method(:initialize) do |**options|
        if options[:data]
          _value, cost = NetWork.measured { super(**options) }
          collision_work << cost
        else
          super(**options)
        end
      end
    end)
    worker = Burrow::Client::TerrainArt.new
    records = []
    9.times do |i|
      if i.positive?
        x = [382, 764, 1534, 2302, 3074, 3800, 4212, 4540][i - 1]
        # Find a surface even when the exact boundary column is open sea.
        x = (x...[x + 300, terrain.width - 20].min).step(2).find { |px| terrain.surface(px) < terrain.height - 100 } || 2400
        terrain.carve(x, terrain.surface(x) + 35, 48)
      end
      export, encode = measured { terrain.export }
      wall = Burrow.clock
      _, request = measured { worker.request(export, "meadow") }
      poll_rows = []
      loop do
        result, poll = measured { worker.poll }
        poll_rows << poll
        if result
          ready_ms = (Burrow.clock - wall) * 1000
          raise "Collision changed" unless result[:preview_terrain].data == terrain.data
          status = "/proc/#{worker.instance_variable_get(:@pid)}/status"
          rss = File.exist?(status) ? File.read(status)[/^VmRSS:\s+(\d+)/, 1]&.to_i : nil
          records << {revision: i, export: encode, request: request, ready_ms: ready_ms,
            worker_rss_kb: rss, polls: summarize(poll_rows), output: tile_digests(result)}
          break
        end
        raise worker.error if worker.error
        raise "Terrain worker timeout" if Burrow.clock - wall > 30
        sleep 0.001
      end
    end
    worker.close
    # Direct, same-process painter profile attributes the worker's CPU; this is
    # separate from the production process boundary measured above.
    profile = []
    Dir.mktmpdir("net-painter-") do |directory|
      painter = Burrow::Client::TerrainPainter.new(directory)
      terrain = Burrow::Terrain.new(seed: 291, width: 4800, height: 1600)
      painter.render(terrain, "meadow")
      8.times do |i|
        x = 200 + i * 570
        terrain.carve(x, terrain.surface(x) + 35, 48)
        _result, cost = measured { painter.render(terrain, "meadow") }
        profile << cost
      end
    end
    {world: [4800, 1600], worker_initial_ms: records.first[:ready_ms],
      worker_revisions_ms: stats(records.drop(1).map { |r| r[:ready_ms] }), painter: summarize(profile),
      gui_collision_validation: summarize(collision_work), raw: records}
  ensure
    worker&.close
  end

  def playback
    # Fixed virtual-time delivery, preserving TCP order, with 18 ticks of history.
    # This complements real TCP proxy sessions and the recorded 0.2.4 cadence test.
    {local: [1, [0.0, 0.001, 0.002, 0.0]],
      sparse_local_stall: [1, Array.new(59) { |i| i.even? ? 0.0 : 0.001 } + [0.054]],
      remote: [3, [0.02, 0.055, 0.0, 0.035]],
      burst: [3, [0.0, 0.12, 0.001, 0.001, 0.025]], ui_stalls: [1, [0.0, 0.002]]}.to_h do |kind, (step, jitter)|
      connection = Burrow::Client::Connection.new(endpoint: "tcp://127.0.0.1:1", name: "Replay")
      timeline = Burrow::Client::Timeline.new
      deliveries, last_at = [], 0
      (0..600).step(step) do |tick|
        at = [1 + tick / 30.0 + jitter[(tick / step) % jitter.length], last_at + 0.0001].max
        last_at = at
        frames = ([0, tick - 17].max..tick).map { |t| {"tick" => t, "worms" => [[1, t * 2, 100, 2, 0, 100, 1]], "hazards" => []} }
        state = {"tick" => tick, "worms" => [{"id" => 1, "x" => tick * 2, "y" => 100}], "hazards" => [], "events" => [],
          "motion" => {"frames" => frames, "shots" => []}}
        deliveries << [at, {"type" => "state", "room" => {"match_id" => "replay"}, "match" => state}]
      end
      now, samples = 1.0, []
      while now < 21
        while deliveries.first && deliveries.first[0] <= now
          at, packet = deliveries.shift
          connection.send(:receive, packet, now: at)
        end
        state = connection.poll[:state]
        timeline.accept(state["match"], now: now) if state
        if timeline.sample(now: now)
          samples << [now, timeline.tick, timeline.delay, timeline.backlog_ms, timeline.underruns, timeline.resyncs]
        end
        now += kind == :ui_stalls && samples.length % 61 == 0 ? 0.11 : 1.0 / 60
      end
      raise "Playback reversed" unless samples.map { |s| s[1] } == samples.map { |s| s[1] }.sort
      [kind, {underruns: timeline.underruns, resyncs: timeline.resyncs,
        backlog_ms: stats(samples.map { |s| s[3] }), delay_ticks: stats(samples.map { |s| s[2] }), raw: samples}]
    end
  end

  def timeline
    players = 6.times.map { |i| {id: "p#{i}", name: Burrow::TEAM_NAMES[i]} }
    match = Burrow::Match.new(players: players, config: Burrow::Config.new("seed" => "perf-net-timeline", "worms" => 6))
    connection = Burrow::Client::Connection.new(endpoint: "tcp://127.0.0.1:1", name: "Timeline")
    timeline = Burrow::Client::Timeline.new
    samples, receives, accepts = [], [], []
    digest = Digest::SHA256.new
    600.times do |i|
      match.command("p0", "jump") if i == 30
      match.command("p0", "fire", weapon: "rocket", angle: 90, power: 0.7) if i == 60
      match.step
      snapshot = match.snapshot
      snapshot[:motion] = snapshot[:motion].merge(frames: snapshot[:motion][:frames].last(2))
      packet = JSON.parse(Burrow::Protocol.encode(type: "state", room: {code: "ABCDEF", match_id: "timeline"}, match: snapshot))
      now = 10 + i / 30.0
      _value, cost = measured { connection.send(:receive, packet, now: now) }
      receives << cost
      _value, cost = measured { timeline.accept(connection.poll[:state]["match"], now: now) }
      accepts << cost
      2.times do |frame|
        value, cost = measured { timeline.sample(now: now + frame / 60.0) }
        samples << cost
        digest << JSON.generate(value.reject { |k, _| k == :presentation_timing })
        digest << JSON.generate(timeline.events)
      end
    end
    {sample: summarize(samples), receive: summarize(receives), accept: summarize(accepts),
      presentation_sha256: digest.hexdigest, underruns: timeline.underruns, resyncs: timeline.resyncs}
  end

  def png
    require File.join(Burrow::ROOT, "lib/burrow/client/terrain_painter")
    rows = {}
    Dir.mktmpdir("net-png-") do |directory|
      terrain = Burrow::Terrain.new(seed: 291, width: 4800, height: 1600)
      result = Burrow::Client::TerrainPainter.new(directory).render(terrain, "meadow")
      paths = [result[:overview], *result[:tiles].map { |t| t[:path] }]
      images = paths.map { |path| ChunkyPNG::Image.from_file(path) }
      {current: {fast_rgba: true}, preset: :fast_rgba,
        rgba_default_compression: {color_mode: ChunkyPNG::COLOR_TRUECOLOR_ALPHA},
        rgba_no_filter: {color_mode: ChunkyPNG::COLOR_TRUECOLOR_ALPHA, filtering: ChunkyPNG::FILTER_NONE}}.each do |name, encoding|
        samples, bytes = [], []
        images.each do |image|
          png, work = measured { image.to_blob(encoding) }
          decoded = ChunkyPNG::Image.from_blob(png)
          raise "PNG pixels changed" unless decoded == image
          samples << work
          bytes << png.bytesize
        end
        rows[name] = {cost: summarize(samples), total_bytes: bytes.sum, bytes: bytes, pixels_identical: true}
      end
    end
    rows
  end

  def wire
    # Wire-extension prototype. Existing protocol-4 clients do not decode this envelope.
    # Compression is measured on trusted fixtures; a production extension would
    # need negotiated support and bounded streaming inflate before JSON decode.
    packet.to_h do |kind, line|
      compressed, encoding = measured { Base64.strict_encode64(Zlib::Deflate.deflate(line, Zlib::BEST_SPEED)) }
      envelope = JSON.generate(type: "compressed_state", data: compressed)
      expected = Burrow::Protocol.decode(line, limit: Burrow::Protocol::MAX_SERVER)
      plain, zipped = [], []
      500.times do
        value, work = measured { Burrow::Protocol.decode(line, limit: Burrow::Protocol::MAX_SERVER) }
        plain << work
        value, work = measured do
          outer = JSON.parse(envelope)
          Burrow::Protocol.decode(Zlib::Inflate.inflate(Base64.strict_decode64(outer.fetch("data"))), limit: Burrow::Protocol::MAX_SERVER)
        end
        raise "Compression changed packet" unless value == expected
        zipped << work
      end
      [kind, {protocol4_bytes: line.bytesize, prototype_bytes: envelope.bytesize,
        encode: encoding, plain_decode: summarize(plain), prototype_decode: summarize(zipped), roundtrip_identical: true}]
    end
  end
end

report = {schema: 1, source: source, ruby: RUBY_DESCRIPTION, json: JSON::VERSION, mode: options[:mode],
  experiment: ENV["BURROW_NET_EXPERIMENT"], results: NetWork.public_send(options[:mode])}
json = JSON.pretty_generate(report) + "\n"
options[:output] ? File.write(options[:output], json) : puts(json)
