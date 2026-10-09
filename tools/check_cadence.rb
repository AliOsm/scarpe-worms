# frozen_string_literal: true
# SCARPE_DISPLAY_SERVICE=native SCARPE_NATIVE_HEADLESS=1 ./bin/scarpe tools/check_cadence.rb
# Separates normal timer delivery from the soak driver's synchronous screenshots,
# UI interactions, forced headless paints, resizes, and rematch construction.
require "tmpdir"
require_relative "../lib/burrow"
directory = Dir.mktmpdir("burrow-cadence-")
ENV["BURROW_DATA_DIR"] = directory
ENV["BURROW_MUTE"] = "1"
ENV.delete("BURROW_CONNECT")
ENV.delete("BURROW_AUTOPLAY")
require_relative "../lib/burrow/client/app"
failed = false
intervals, preparation = [], []
last_at = nil
Burrow::Client::App.prepend(Module.new do
  define_method(:update) do
    at = Burrow.clock
    intervals << (at - last_at) * 1000 if last_at
    last_at = at
    super()
  end
end)
Burrow::Client::Scene.prepend(Module.new do
  define_method(:render) do
    at = Burrow.clock
    super()
    preparation << (Burrow.clock - at) * 1000
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
        raise "Cadence setup timed out" if Burrow.clock > deadline
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
    auto.advance(20) # Normal pump; no per-frame automation requests during this span.
    stats = lambda do |values|
      ordered = values.sort
      {count: ordered.length, mean_ms: ordered.sum / ordered.length,
        p95_ms: ordered[(ordered.length * 0.95).floor], max_ms: ordered.last}
    end
    report = {ruby: RUBY_VERSION, platform: RUBY_PLATFORM, headless: ENV["SCARPE_NATIVE_HEADLESS"] == "1",
      scenario: "20 seconds of idle animations with 36 grubs, network snapshots, and an uninterrupted event loop",
      app_update_intervals: stats.call(intervals), ruby_scene_preparation: stats.call(preparation)}
    raise "Timer delivery stalled" unless intervals.length > 900 && intervals.max < 250
    raise "Native handler error" if Scarpe::Native::DisplayService.instance.instance_variable_get(:@handler_errors)&.any?
    File.write(File.join(Burrow::ROOT, "docs/validation/native-cadence.json"), JSON.pretty_generate(report) + "\n")
    puts JSON.generate(report)
  rescue Exception => error
    failed = true
    warn error.full_message
  ensure
    Shoes.APPS.each(&:destroy)
  end
end
load File.join(Burrow::ROOT, "game.rb")
