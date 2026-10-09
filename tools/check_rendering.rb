# frozen_string_literal: true
# Real native-window performance journey. Run with check_rendering.py.
require "tmpdir"
require "scarpe"
require "scarpe/native"
source_root = ENV["BURROW_PACKAGE_RES"] ? File.join(ENV["BURROW_PACKAGE_RES"], "app") : File.expand_path("..", __dir__)
require File.join(source_root, "lib/burrow")
require File.join(source_root, "lib/burrow/client/app")

data = Dir.mktmpdir("burrow-rendering-")
ENV["BURROW_DATA_DIR"] = data
ENV["BURROW_MUTE"] = ENV.fetch("BURROW_BENCH_MUTE", "1")
ENV.delete("BURROW_CONNECT")
ENV.delete("BURROW_AUTOPLAY")
failed, phase, pan = false, nil, false
last_update, last_pan, last_camera = nil, nil, nil
samples, stages, shots = [], [], Set.new

Burrow::Client::App.prepend(Module.new do
  define_method(:update) do
    at = Burrow.clock
    gc_time = GC.stat(:time)
    super()
    if phase && scene
      camera = scene.camera
      visual = scene.instance_variable_get(:@state)
      moving = pan || visual["projectiles"].any? || visual["worms"].any? { |w| w["hp"] > 0 && w["vx"].abs + w["vy"].abs > 8 }
      moving ||= last_camera && Math.hypot(camera.x - last_camera[0], camera.y - last_camera[1]) > 0.1
      ui_scale = scene.instance_variable_get(:@ui_scale)
      visible_speed = (visual["worms"] + visual["projectiles"]).filter_map do |actor|
        sx, sy = camera.screen(actor["x"], actor["y"])
        next unless sx.between?(0, 1440) && sy.between?(0, 720)
        Math.hypot(actor["vx"], actor["vy"]) * camera.zoom * ui_scale
      end.max || 0
      camera_speed = last_camera && last_update ? Math.hypot(camera.x-last_camera[0], camera.y-last_camera[1]) * camera.zoom * ui_scale / [at-last_update, 0.001].max : 0
      samples << [Time.now.to_f, phase, last_update && (at - last_update) * 1000, (Burrow.clock - at) * 1000, !!moving, GC.stat(:time) - gc_time, visible_speed, camera_speed]
      last_camera = [camera.x, camera.y]
      shots.merge(scene.timeline.seen_shots)
    end
    last_update = at
  end
end)
Burrow::Client::Scene.prepend(Module.new do
  define_method(:render) do
    now = Burrow.clock
    camera.pan((now - (last_pan || now)).clamp(0, 0.05) * 450 * camera.zoom, 0) if pan && camera
    last_pan = now
    super()
  end
end)
at_exit { FileUtils.remove_entry(data) if File.directory?(data); exit(1) if failed }

Scarpe::Native.after_first_heartbeat do
  begin
    service = Scarpe::Native::DisplayService.instance
    raise "A real window and clock are required" if service.clock.frozen? || ENV["SCARPE_NATIVE_HEADLESS"] == "1"
    auto = service.automation
    client = Shoes.APPS.first.instance_variable_get(:@burrow)
    wait = lambda do |&condition|
      deadline = Burrow.clock + 20
      until condition.call
        raise "Rendering journey setup timed out" if Burrow.clock > deadline
        auto.advance(0.05)
      end
    end
    width, height = ENV.fetch("BURROW_BENCH_SIZE", "1280x800").split("x").map(&:to_i)
    auto.resize(width, height)
    auto.click({text: "Create a match"})
    wait.call { client.page == :lobby }
    client.action("configure", config: client.room["config"].merge("worms" => 6, "turn_seconds" => 90, "seed" => "little-havoc"))
    4.times { client.action("add_bot") }
    wait.call { client.room["members"].size == 6 && client.room.dig("config", "worms") == 6 }
    auto.click({text: "Start the mischief"})
    wait.call { client.scene && client.scene.terrain_revision >= 0 }
    auto.advance(1)
    # Apply only to the already-running UI thread. The renderer, network thread,
    # host and terrain worker retain their normal policies. This recreates the
    # reported wait overshoots without contaminating render/simulation timings.
    slack = ENV.fetch("BURROW_BENCH_TIMER_SLACK_NS", "0").to_i
    if slack > 0
      require "fiddle"
      prctl = Fiddle::Function.new(Fiddle::Handle::DEFAULT["prctl"],
        [Fiddle::TYPE_INT, *Array.new(4, Fiddle::TYPE_LONG)], Fiddle::TYPE_INT)
      original_slack = prctl.call(30, 0, 0, 0, 0)
      raise "Could not apply timer slack" unless prctl.call(29, slack, 0, 0, 0).zero?
    end
    stage = lambda do |name, &action|
      phase = name
      first = Time.now.to_f
      action.call
      stages << {name: name, from: first, to: Time.now.to_f}
      phase = nil
    end
    stage.call("combat") do
      auto.key_down("right")
      auto.advance(1.2)
      auto.key_up("right")
      auto.key("w")
      auto.advance(0.8)
      client.action("fire", weapon: "banana", angle: -80, power: 0.9, fuse: 3)
      auto.advance(16)
    end
    stage.call("pan") do
      client.scene.camera.navigate(720, 820)
      pan = true
      auto.advance(6)
      pan = false
    end
    stage.call("zoom") do
      client.scene.camera.overview
      auto.advance(0.8)
      4.times { client.scene.camera.zoom_by(1); auto.advance(0.8) }
      4.times { client.scene.camera.zoom_by(-1); auto.advance(0.8) }
    end
    raise "Weapons were not presented" unless shots.size >= 2 && client.scene.terrain_revision > 0
    raise "Native callback failed" if service.instance_variable_get(:@handler_errors)&.any?
    if ENV["BURROW_BENCH_SHOT"]
      client.scene.camera.follow
      auto.advance(0.3)
      auto.snapshot(ENV["BURROW_BENCH_SHOT"])
    end
    report = {version: Burrow::VERSION, ruby: RUBY_VERSION, platform: RUBY_PLATFORM,
      window: [width, height], world: client.state.values_at("world_width", "world_height"),
      grubs: client.state["worms"].length, stages: stages, samples: samples,
      sample_columns: %w[at phase update_interval_ms update_ms moving gc_ms visible_speed camera_speed],
      audio: client.instance_variable_get(:@audio).available, projectile_ids: shots.to_a,
      terrain_revision: client.scene.terrain_revision}
    File.write(ENV.fetch("BURROW_BENCH_REPORT"), JSON.pretty_generate(report) + "\n")
  rescue Exception => error
    failed = true
    warn "Rendering journey failed: #{error.full_message}"
  ensure
    prctl.call(29, original_slack, 0, 0, 0) if original_slack && original_slack >= 0
    Shoes.APPS.each(&:destroy)
  end
end

if ENV["BURROW_PACKAGE_RES"]
  load File.join(ENV["BURROW_PACKAGE_RES"], "boot.rb")
else
  load File.join(source_root, "game.rb")
end
