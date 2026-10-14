# frozen_string_literal: true

# Ten minutes of active native play, including completed matches/rematches.
# PERF_STARTUP_OUTPUT, BURROW_BENCH_SOURCE and optional PERF_STARTUP_PAUSE_FILE.
# Run with perf_startup_memory.py: it stops every workload process between short
# bench leases. Active duration excludes those pauses; no latency claims use
# this interrupted RSS/retention probe. Never force GC except at a rematch
# boundary where scene retention is checked. Native/host/worker RSS is separate.
require_relative "perf_startup_support"
require "tmpdir"
require "scarpe"
require "scarpe/native"
require File.join(StartupPerf.source, "lib/burrow")
require File.join(StartupPerf.source, "lib/burrow/client/app")
data = Dir.mktmpdir("startup-memory-")
ENV["BURROW_DATA_DIR"], ENV["BURROW_MUTE"] = data, "1"
ENV.delete("BURROW_AUTOPLAY")
ENV.delete("BURROW_CONNECT")
failed = false
at_exit { FileUtils.remove_entry(data) if File.directory?(data); exit(1) if failed }

Scarpe::Native.after_first_heartbeat do
  begin
    service = Scarpe::Native::DisplayService.instance
    auto = service.automation
    client = Shoes.APPS.first.instance_variable_get(:@burrow)
    paused = lambda do
      path = ENV["PERF_STARTUP_PAUSE_FILE"]
      path && File.exist?(path) ? JSON.parse(File.read(path)).fetch("paused_seconds", 0) : 0
    end
    wait = lambda do |&condition|
      deadline = StartupPerf.clock - paused.call + 45
      until condition.call
        raise "Memory setup timed out: #{client.instance_variable_get(:@last_notice)}" if StartupPerf.clock - paused.call > deadline
        auto.advance(0.05)
      end
    end
    auto.click({text: "Create a match"})
    wait.call { client.page == :lobby }
    config = Burrow::Config.new("seed" => "memory-0", "biome" => "glacier", "terrain" => "archipelago",
      "worms" => 6, "health" => 50, "round_limit" => 3, "water_rise" => 40, "damage" => 2,
      "turn_seconds" => 15, "retreat_seconds" => 0, "scheme" => "sandbox").to_h
    client.action("configure", config: config)
    4.times { client.action("add_bot") }
    wait.call { client.room["members"].length == 6 && client.room.dig("config", "seed") == "memory-0" }
    client.action("start")
    wait.call { client.scene && client.scene.terrain_revision >= 0 }
    auto.window_focus(true)
    started, pause_start = StartupPerf.clock, paused.call
    duration = Float(ENV.fetch("PERF_STARTUP_MEMORY_SECONDS", "600"))
    samples, retained, turns, notices = [], [], {}, []
    completed, next_sample, next_camera = 0, 0, 0
    last_action = nil
    elapsed = -> { StartupPerf.clock - started - (paused.call - pause_start) }
    while elapsed.call < duration
      # Yield only between native requests. An arbitrary SIGSTOP in #frames
      # would count the unlocked pause toward its 30-second request deadline.
      if (path = ENV["PERF_STARTUP_PAUSE_FILE"])
        lease = JSON.parse(File.read(path))
        if StartupPerf.clock >= lease.fetch("lease_deadline")
          File.write(path + ".ready", Process.pid.to_s)
          Process.kill("STOP", Process.pid)
        end
      end
      auto.advance(0.1)
      state = client.state
      next unless state
      turns[client.room["match_id"]] = state["turn"]
      if state["phase"] == "finished"
        completed += 1
        client.hide_overlay
        client.action("rematch")
        wait.call { client.page == :lobby }
        config = config.merge("seed" => "memory-#{completed}", "biome" => %w[glacier volcano desert meadow][completed % 4])
        client.action("configure", config: config)
        wait.call { client.room.dig("config", "seed") == config["seed"] }
        client.action("start")
        wait.call { client.scene && client.scene.terrain_revision >= 0 }
        GC.start
        row = {match: completed + 1, scenes: ObjectSpace.each_object(Burrow::Client::Scene).count,
          terrain_workers: ObjectSpace.each_object(Burrow::Client::TerrainArt).count, live_slots: GC.stat(:heap_live_slots)}
        retained << row
        raise "A closed scene or worker is retained" if row[:scenes] != 1 || row[:terrain_workers] != 1
        next
      end
      if state["phase"] == "aiming" && state["team"] == client.my_id
        key = [client.room["match_id"], state["turn"], state["shots_left"]]
        if key != last_action
          actor = state["worms"].find { |w| w["id"] == state["active"] }
          target = state["worms"].select { |w| w["hp"] > 0 && w["team"] != client.my_id }.min_by { |w| (w["x"] - actor["x"]).abs }
          if target
            weapon = state["shots_left"] > 0 ? "shotgun" : %w[grenade rocket cluster airstrike shotgun][state["turn"] % 5]
            angle = weapon == "shotgun" ? Math.atan2(target["y"] - actor["y"], target["x"] - actor["x"]) * 180 / Math::PI : target["x"] < actor["x"] ? -135 : -45
            client.action("fire", weapon: weapon, angle: angle, power: 0.55, fuse: 1, x: target["x"], y: target["y"])
            last_action = key
          end
        end
      end
      active = elapsed.call
      if active >= next_camera
        client.scene.camera.overview
        client.scene.camera.zoom_by(1) if (active / 10).to_i.odd?
        next_camera = active + 10
      end
      if active >= next_sample
        art = client.scene.instance_variable_get(:@terrain_art)
        row = {seconds: active, match: completed + 1, turn: state["turn"],
          gui_rss_kib: StartupPerf.rss, native_rss_kib: StartupPerf.rss(service.child.pid),
          host_rss_kib: StartupPerf.rss(client.instance_variable_get(:@local_server).pid),
          terrain_rss_kib: StartupPerf.rss(art.instance_variable_get(:@pid)),
          nodes: auto.layout.length, effects: client.scene.instance_variable_get(:@effects).length,
          timeline_frames: client.scene.timeline.instance_variable_get(:@frames).length,
          timeline_shots: client.scene.timeline.instance_variable_get(:@shots).length,
          live_slots: GC.stat(:heap_live_slots), threads: Thread.list.count(&:alive?),
          terrain_files: Dir[File.join(art.directory, "*.png")].length}
        raise "A bounded resource exceeded its cap" if row[:nodes] > 2400 || row[:effects] > 100 || row[:timeline_frames] > 31 || row[:terrain_files] > client.scene.instance_variable_get(:@tiles).length * 3 + 3
        samples << row
        art = nil # Do not retain a closed worker through the observer's local.
        next_sample = active + 10
        File.write(ENV.fetch("PERF_STARTUP_OUTPUT") + ".progress.json", JSON.generate(samples))
      end
    end
    raise "No rematch coverage" if completed.zero?
    raise "Native handler failed" if service.instance_variable_get(:@handler_errors)&.any?
    StartupPerf.write(scenario: "memory", seconds_active: elapsed.call, paused_seconds: paused.call - pause_start,
      matches: turns.length, completed_matches: completed, turns: turns.values.sum, samples: samples,
      retained: retained, gc: GC.stat, limits: "Process group suspension between bench leases; no cadence conclusions. Muted/headless.")
  rescue Exception => error
    failed = true
    File.write(ENV.fetch("PERF_STARTUP_OUTPUT") + ".failure", error.full_message)
    warn error.full_message
  ensure
    Shoes.APPS.each(&:destroy)
  end
end
load File.join(StartupPerf.source, "game.rb")
