# frozen_string_literal: true

# Real native boot -> menu paint barrier -> Quick battle -> terrain paint barrier.
# Run through bin/scarpe, with PERF_STARTUP_OUTPUT and optional PERF_STARTUP_DATA
# (reuse the data path with PERF_STARTUP_RESUME=1 for a saved match).
# BURROW_BENCH_SOURCE selects a frozen source/assets tree. The Python runner
# supplies PERF_STARTUP_LAUNCHED using the same monotonic OS clock before spawn.
# Headless measures completed native offscreen frames, never physical scanout.
# Frame work is measured without FrameProfile or allocation tracing; GC.total_time
# deltas include GC work on all GUI threads and are not individual stop-the-world
# pause durations. Per-frame CPU uses only the GUI thread.
require_relative "perf_startup_support"
require "tmpdir"
require "scarpe"
require "scarpe/native"
marks, spans, frames = {}, {}, []
launched = Float(ENV.fetch("PERF_STARTUP_LAUNCHED") { StartupPerf.clock.to_s })
mark = ->(name) { marks[name] ||= (StartupPerf.clock - launched) * 1000 }
mark.call(:script)
_, spans[:require_game] = StartupPerf.measure do
  require File.join(StartupPerf.source, "lib/burrow")
  require File.join(StartupPerf.source, "lib/burrow/client/app")
end
directory = ENV["PERF_STARTUP_DATA"] || Dir.mktmpdir("startup-app-")
ENV["BURROW_DATA_DIR"] = directory
ENV["BURROW_MUTE"] = ENV.fetch("PERF_STARTUP_AUDIO", "0") == "1" ? "0" : "1"
ENV.delete("BURROW_AUTOPLAY")
ENV.delete("BURROW_CONNECT")
failed, tracking = false, false
last_update = nil

[[Burrow::Client::Audio, :initialize, :audio], [Burrow::Server::ProcessHost, :initialize, :host_spawn],
 [Burrow::Client::Scene, :initialize, :scene_build]].each do |klass, method, name|
  klass.prepend(Module.new do
    define_method(method) do |*args, **kwargs, &block|
      value, timing = StartupPerf.measure { super(*args, **kwargs, &block) }
      (spans[name] ||= []) << timing
      value
    end
  end)
end
Shoes::Builtins.prepend(Module.new do
  define_method(:font) do |*args|
    value, timing = StartupPerf.measure { super(*args) }
    (spans[:fonts] ||= []) << timing.merge(path: args.first)
    value
  end
end)
Burrow::Client::App.prepend(Module.new do
  define_method(:update) do
    at, cost, gc = StartupPerf.clock, StartupPerf.cpu, GC.total_time
    value = super()
    mark.call(:first_state) if state
    mark.call(:terrain_ready) if scene && scene.terrain_revision >= 0
    if tracking
      frames << [(at - launched) * 1000, (StartupPerf.clock - at) * 1000,
        (StartupPerf.cpu - cost) * 1000, (GC.total_time - gc) / 1e6,
        last_update && (at - last_update) * 1000]
    end
    last_update = at
    value
  end
end)

# Fix only Quick battle's random map seed. Session/token generation stays real.
Burrow::Client::App.prepend(Module.new do
  define_method(:play_local) do |**options|
    Thread.current[:startup_quick_seed] = true
    super(**options)
  ensure
    Thread.current[:startup_quick_seed] = false
  end
end)
SecureRandom.singleton_class.prepend(Module.new do
  def hex(n = nil)
    Thread.current[:startup_quick_seed] && n == 4 ? "517a27ed" : super
  end
end)

Scarpe::Native.after_first_heartbeat do
  begin
    service = Scarpe::Native::DisplayService.instance
    raise "Use a real clock" if service.clock.frozen?
    auto = service.automation
    client = Shoes.APPS.first.instance_variable_get(:@burrow)
    mark.call(:menu_interactive)
    auto.wait_frames
    mark.call(:menu_frame)
    menu_rss = {gui: StartupPerf.rss, native: StartupPerf.rss(service.child.pid)}
    mark.call(:quick_click)
    auto.click({text: "Quick battle"})
    mark.call(:click_returned)
    deadline = StartupPerf.clock + 30
    until client.state && client.scene && client.scene.terrain_revision >= 0
      raise "Battle timed out: #{client.instance_variable_get(:@last_notice)}" if StartupPerf.clock > deadline
      auto.advance(0.01)
    end
    auto.wait_frames
    mark.call(:battle_frame)
    auto.window_focus(true)
    GC.config(rgengc_allow_full_mark: false) if ENV["PERF_STARTUP_NO_MAJOR"] == "1"
    tracking = true
    duration = Float(ENV.fetch("PERF_STARTUP_COMBAT_SECONDS", "2"))
    if duration > 3
      auto.key_down("right")
      auto.advance(0.5)
      auto.key_up("right")
      client.action("fire", weapon: "banana", angle: -80, power: 0.9, fuse: 3)
    end
    auto.advance(duration)
    tracking = false
    art = client.scene.instance_variable_get(:@terrain_art)
    memory = {gui: StartupPerf.rss, native: StartupPerf.rss(service.child.pid),
      host: StartupPerf.rss(client.instance_variable_get(:@local_server).pid),
      terrain: StartupPerf.rss(art.instance_variable_get(:@pid))}
    raise "Expected audio" if ENV["PERF_STARTUP_AUDIO"] == "1" && !client.instance_variable_get(:@audio).available
    raise "Native callback failed" if service.instance_variable_get(:@handler_errors)&.any?
    StartupPerf.write(scenario: ENV["PERF_STARTUP_RESUME"] == "1" ? "resume" : "launch", marks_ms: marks,
      spans: spans, quick_to_battle_ms: marks[:battle_frame] - marks[:quick_click],
      menu_rss_kib: menu_rss, battle_rss_kib: memory, frames: frames,
      frame_columns: %w[at_ms wall_ms cpu_ms gc_ms interval_ms],
      frame_summary: %i[wall_ms cpu_ms gc_ms interval_ms].each_with_index.to_h { |key, i| [key, StartupPerf.stats(frames.filter_map { |r| r[i + 1] })] },
      gc_pauses_ms: StartupPerf.stats(frames.map { |r| r[3] }.select(&:positive?)),
      gc: GC.stat, audio: client.instance_variable_get(:@audio).available,
      match_id: client.room["match_id"], terrain_checksum: client.state["terrain_checksum"],
      headless: ENV["SCARPE_NATIVE_HEADLESS"] == "1", frame_measurement: "native paint barrier; not scanout")
  rescue Exception => error
    failed = true
    warn error.full_message
  ensure
    Shoes.APPS.each(&:destroy)
  end
end
at_exit do
  FileUtils.remove_entry(directory) if !ENV["PERF_STARTUP_DATA"] && File.directory?(directory)
  exit(1) if failed
end
load File.join(StartupPerf.source, "game.rb")
