# frozen_string_literal: true
# Run through tools/check_action.py for native presentation timings.
# Separates normal timer delivery from the soak driver's synchronous screenshots,
# UI interactions, forced headless paints, resizes, and rematch construction.
require "tmpdir"
require_relative "../lib/burrow"
directory = Dir.mktmpdir("burrow-action-")
ENV["BURROW_DATA_DIR"] = directory
ENV["BURROW_MUTE"] = "1"
ENV.delete("BURROW_CONNECT")
ENV.delete("BURROW_AUTOPLAY")
require_relative "../lib/burrow/client/app"
failed = false
intervals, preparation, motion_samples = [], [], []
recording = false
last_at = nil
last_work = nil
stalls = []
Burrow::Client::App.prepend(Module.new do
  define_method(:update) do
    at = Burrow.clock
    if last_at
      gap = (at - last_at) * 1000
      intervals << gap
      stalls << {at: Time.now.to_f, gap_ms: gap, previous_update_ms: last_work, tick: state && state["tick"]} if recording && gap > 30
    end
    last_at = at
    super()
    last_work = (Burrow.clock - at) * 1000
  end
end)
Burrow::Client::Scene.prepend(Module.new do
  define_method(:render) do
    at = Burrow.clock
    super()
    preparation << (Burrow.clock - at) * 1000
    if recording
      current = instance_variable_get(:@state)
      moving = current && (current["projectiles"].any? { |p| p["vx"].abs + p["vy"].abs > 8 } || current["worms"].any? { |w| w["hp"] > 0 && w["vx"].abs + w["vy"].abs > 8 })
      motion_samples << [Time.now.to_f, !!moving]
    end
  end
end)
at_exit { FileUtils.remove_entry(directory) if File.directory?(directory); exit(1) if failed }
Scarpe::Native.after_first_heartbeat do
  begin
    auto = Scarpe::Native::DisplayService.instance.automation
    client = Shoes.APPS.first.instance_variable_get(:@burrow)
    wait = lambda do |&condition|
      deadline = Burrow.clock + 15
      until condition.call
        raise "Action setup timed out" if Burrow.clock > deadline
        auto.advance(0.05)
      end
    end
    auto.click({text: "Create a match"})
    wait.call { client.page == :lobby }
    client.action("configure", config: client.room["config"].merge("worms" => 6, "turn_seconds" => 90))
    4.times { client.action("add_bot") }
    wait.call { client.room["members"].size == 6 && client.room.dig("config", "worms") == 6 }
    auto.click({text: "Start the mischief"})
    wait.call { client.scene && client.scene.terrain_revision >= 0 }
    auto.advance(2)
    intervals.clear
    preparation.clear
    recording = true
    auto.key_down("right")
    auto.advance(1.2)
    auto.key_up("right")
    auto.key("w")
    auto.advance(0.8)
    client.action("fire", weapon: "banana", angle: -80, power: 0.9, fuse: 3)
    auto.advance(16) # Normal pump during flight, cluster explosions and bot turns.
    recording = false
    stats = lambda do |values|
      ordered = values.sort
      {count: ordered.length, mean_ms: ordered.sum / ordered.length,
        p95_ms: ordered[(ordered.length * 0.95).floor], max_ms: ordered.last}
    end
    report = {ruby: RUBY_VERSION, platform: RUBY_PLATFORM, headless: ENV["SCARPE_NATIVE_HEADLESS"] == "1",
      world: [client.state["world_width"], client.state["world_height"]],
      motion_samples: motion_samples, stalls: stalls,
      presented_shots: client.scene.timeline.seen_shots.to_a, terrain_revision: client.scene.terrain_revision,
      scenario: "18 seconds of walking, jumping, cluster flight/explosions and bot turns with 36 grubs in a native window",
      app_update_intervals: stats.call(intervals), ruby_scene_preparation: stats.call(preparation)}
    raise "Timer delivery stalled" unless intervals.length > 400
    raise "Native handler error" if Scarpe::Native::DisplayService.instance.instance_variable_get(:@handler_errors)&.any?
    File.write(File.join(Burrow::ROOT, "docs/validation/native-action.json"), JSON.pretty_generate(report) + "\n")
    File.write(ENV["BURROW_ACTION_REPORT"], JSON.pretty_generate(report)) if ENV["BURROW_ACTION_REPORT"]
    puts JSON.generate(report.reject { |k, _| k == :motion_samples })
  rescue Exception => error
    failed = true
    warn error.full_message
  ensure
    Shoes.APPS.each(&:destroy)
  end
end
load File.join(Burrow::ROOT, "game.rb")
