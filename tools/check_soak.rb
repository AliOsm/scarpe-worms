# frozen_string_literal: true
# SCARPE_DISPLAY_SERVICE=native SCARPE_NATIVE_HEADLESS=1 ./bin/scarpe tools/check_soak.rb
# Real-time native exercise; optional BURROW_SOAK_SECONDS (default 300).
# A windowed run can set BURROW_SOAK_AUDIO=1 and use OpenAL's null driver on Linux.
# BURROW_SOAK_OUTPUT keeps an exploratory capture out of published evidence.
# BURROW_PACKAGE_RES exercises the delivered app with check_package's environment.
require "tmpdir"
require "scarpe"
require "scarpe/native"
check_root = File.expand_path("..", __dir__)
source_root = ENV["BURROW_PACKAGE_RES"] ? File.join(ENV["BURROW_PACKAGE_RES"], "app") : check_root
require File.join(source_root, "lib/burrow")

directory = Dir.mktmpdir("burrow-native-soak-")
ENV["BURROW_DATA_DIR"] = directory
ENV["BURROW_MUTE"] = ENV["BURROW_SOAK_AUDIO"] == "1" ? "0" : "1"
ENV.delete("BURROW_CONNECT")
ENV.delete("BURROW_AUTOPLAY")
output = File.expand_path(ENV.fetch("BURROW_SOAK_OUTPUT", "docs/validation/native-soak.json"), check_root)
shots = File.join(check_root, ".cache/soak-shots")
FileUtils.mkdir_p([File.dirname(output), shots])
failed = false
at_exit { FileUtils.remove_entry(directory) if File.directory?(directory); exit(1) if failed }

require File.join(source_root, "lib/burrow/client/app")
intervals, scene_times = [], []
last_update = nil
Burrow::Client::App.prepend(Module.new do
  define_method(:update) do
    now = Burrow.clock
    intervals << (now - last_update) * 1000 if last_update
    last_update = now
    super()
  end
end)
Burrow::Client::Scene.prepend(Module.new do
  define_method(:render) do
    at = Burrow.clock
    super()
    scene_times << (Burrow.clock - at) * 1000
  end
end)

Scarpe::Native.after_first_heartbeat do
  friends = []
  begin
    service = Scarpe::Native::DisplayService.instance
    raise "Soak must use the real clock" if service.clock.frozen?
    auto = service.automation
    client = Shoes.APPS.first.instance_variable_get(:@burrow)
    if ENV["BURROW_SOAK_AUDIO"] == "1"
      raise "Audio was requested but did not initialize" unless client.instance_variable_get(:@audio).available
    end
    wait = lambda do |seconds = 20, &condition|
      deadline = Burrow.clock + seconds
      until condition.call
        raise "Soak condition timed out at #{caller_locations(1, 1).first}" if Burrow.clock > deadline
        auto.advance(0.05)
      end
    end
    auto.click({text: "Create a match"})
    wait.call { client.page == :lobby }
    config = Burrow::Config.new("seed" => "soak-0", "biome" => "glacier", "terrain" => "archipelago",
      "worms" => 6, "health" => 75, "round_limit" => 3, "water_rise" => 40,
      "turn_seconds" => 15, "retreat_seconds" => 0, "scheme" => "sandbox", "damage" => 2).to_h
    client.action("configure", config: config)
    3.times { client.action("add_bot") }
    friend = Burrow::Client::Connection.new(endpoint: client.connection.endpoint, name: "Socket scout").connect
    friends << friend
    wait.call { friend.status == "online" }
    friend.send_action("join", code: client.room["code"])
    wait.call { client.room["members"].size == 6 }
    friend.send_action("ready", ready: true)
    wait.call { client.room["members"].all? { |m| m["ready"] || m["id"] == client.my_id } }
    auto.click({text: "Start the mischief"})
    wait.call { client.scene && client.scene.terrain_revision >= 0 }
    # Xvfb has no window manager to grant activation. Exercise the native focus
    # event explicitly before using keyboard shortcuts in this windowed harness.
    auto.window_focus(true)
    wait.call { client.instance_variable_get(:@window_active) }
    raise "Expected 36 grubs" unless client.state["worms"].size == 36
    auto.snapshot(File.join(shots, "glacier-start.png"))
    started = Burrow.clock
    duration = Float(ENV.fetch("BURROW_SOAK_SECONDS", "300")).clamp(30, 3600)
    next_sample, next_resize, next_camera = started, started + 30, started + 5
    samples, matches, sent, retained = [], {}, {}, []
    late_inputs = []
    friend_state = nil
    finished, resizes, terrain_changes, camera_changes = 0, 0, 0, 0
    biomes = Set.new([config["biome"]])
    previous_revision = nil
    while Burrow.clock - started < duration
      auto.advance(0.05)
      update = friend.poll
      # A worm can die or a turn expire between receipt of a snapshot and receipt
      # of its command. Authoritative rejection is the expected wire behavior.
      update[:notices].each do |notice|
        raise "Socket client error: #{notice}" unless ["Wait for your team's turn.", "Wait for the action to settle.",
          "Only movement is available during retreat.", "The match has ended."].include?(notice)
        late_inputs << notice
      end
      friend_state = update[:state] if update[:state]
      state = client.state
      next unless state
      match_id = client.room["match_id"]
      matches[match_id] = state["turn"]
      revision = [match_id, state["terrain_revision"]]
      terrain_changes += 1 if previous_revision && revision != previous_revision
      previous_revision = revision
      raise "Effect bound exceeded" if client.scene.instance_variable_get(:@effects).length > 100
      raise "Nonfinite actor" unless state["worms"].all? { |w| w["x"].finite? && w["y"].finite? }
      if state["phase"] == "finished"
        finished += 1
        auto.snapshot(File.join(shots, "result-#{finished}.png"))
        client.hide_overlay
        client.action("rematch")
        wait.call { client.page == :lobby }
        biome = %w[glacier volcano desert meadow][finished % 4]
        biomes << biome
        config = config.merge("seed" => "soak-#{finished}", "biome" => biome)
        client.action("configure", config: config)
        wait.call { client.room.dig("config", "seed") == config["seed"] }
        friend.send_action("ready", ready: true)
        wait.call { client.room["members"].all? { |m| m["ready"] || m["id"] == client.my_id } }
        client.action("start")
        wait.call { client.page == :match && client.scene.terrain_revision >= 0 }
        GC.start
        resources = {match: finished + 1, scenes: ObjectSpace.each_object(Burrow::Client::Scene).count,
          terrain_workers: ObjectSpace.each_object(Burrow::Client::TerrainArt).count,
          live_heap_slots: GC.stat(:heap_live_slots)}
        retained << resources
        puts JSON.generate(resources)
        raise "Old battle scenes retained" if resources[:scenes] > 1 || resources[:terrain_workers] > 1
        auto.snapshot(File.join(shots, "#{biome}-start.png"))
        next
      end
      [[client.connection, {"room" => client.room, "match" => state}], [friend, friend_state]].each do |connection, packet|
        current = packet && packet["match"]
        next unless packet && packet.dig("room", "match_id") == match_id
        next unless current && current["phase"] == "aiming" && current["team"] == connection.id
        key = [packet.dig("room", "match_id"), current["turn"], current["shots_left"]]
        next if sent[key]
        actor = current["worms"].find { |w| w["id"] == current["active"] }
        target = current["worms"].select { |w| w["team"] != actor["team"] && w["hp"] > 0 }.min_by { |w| (w["x"] - actor["x"]).abs }
        next unless target
        weapon = current["shots_left"] > 0 ? "shotgun" : %w[grenade rocket cluster airstrike shotgun][current["turn"] % 5]
        angle = if weapon == "shotgun"
          Math.atan2(target["y"] - actor["y"], target["x"] - actor["x"]) * 180 / Math::PI
        else
          target["x"] < actor["x"] ? -135 : -45
        end
        sent[key] = connection.send_action("fire", weapon: weapon, angle: angle, power: 0.55,
          fuse: 1, x: target["x"], y: target["y"])
      end
      now = Burrow.clock
      if now >= next_camera
        camera_changes += 1
        camera = client.scene.camera
        case camera_changes % 4
        when 1 then auto.key("g")
        when 2 then camera.navigate(state["world_width"] * 0.75, state["world_height"] * 0.5)
        when 3 then camera.zoom_by(1, anchor: [600, 280])
        when 0 then auto.key("f")
        end
        raise "Nonfinite camera" unless [camera.x, camera.y, camera.zoom].all?(&:finite?)
        next_camera = now + 5
      end
      if now >= next_resize
        resizes += 1
        auto.window_focus(true)
        auto.key("e")
        wait.call { client.overlay? }
        auto.click({text: "Close"})
        wait.call { !client.overlay? }
        auto.resize(*(resizes.odd? ? [1440, 900] : [1080, 675]))
        wait.call { client.scene && client.scene.terrain_revision >= 0 && client.instance_variable_get(:@dimensions) == (resizes.odd? ? [1440, 900] : [1080, 675]) }
        next_resize = now + 30
        auto.snapshot(File.join(shots, "battle-#{resizes}.png"))
      end
      if now >= next_sample
        rss = lambda { |pid| File.read("/proc/#{pid}/status")[/^VmRSS:\s+(\d+)/, 1].to_i if File.exist?("/proc/#{pid}/status") }
        terrain_worker = client.scene.instance_variable_get(:@terrain_art)
        native_pid = service.child.pid
        host_pid = client.instance_variable_get(:@local_server).pid
        sample = {seconds: (now - started).round(2), match: finished + 1, turn: state["turn"],
          ruby_rss_kib: rss.call(Process.pid), native_rss_kib: rss.call(native_pid),
          host_rss_kib: rss.call(host_pid), terrain_rss_kib: rss.call(terrain_worker.instance_variable_get(:@pid)),
          scene_ms: client.scene.performance, nodes: auto.layout.length, threads: Thread.list.count(&:alive?),
          effects: client.scene.instance_variable_get(:@effects).length,
          timeline_frames: client.scene.timeline.instance_variable_get(:@frames).length,
          timeline_shots: client.scene.timeline.instance_variable_get(:@shots).length,
          terrain_files: Dir[File.join(terrain_worker.directory, "*.png")].length}
        samples << sample
        puts JSON.generate(sample)
        $stdout.flush
        raise "Terrain cache grew past its bound" if sample[:terrain_files] > client.scene.instance_variable_get(:@tiles).length * 3 + 3
        raise "Drawable count grew unexpectedly" if sample[:nodes] > 2400
        raise "Motion history grew past its bound" if sample[:timeline_frames] > 31
        # The observer must not keep the previous match's closed worker alive
        # across the rematch GC/retention assertion.
        terrain_worker = nil
        next_sample = now + 10
      end
    end
    stats = lambda do |values|
      sorted = values.sort
      {count: sorted.length, mean_ms: sorted.sum / sorted.length, p95_ms: sorted[(sorted.length * 0.95).floor], max_ms: sorted.last}
    end
    raise "No sustained turn progression" unless matches.values.sum >= 12
    raise "Terrain did not change" unless terrain_changes >= 5
    raise "Native handlers raised errors" if service.instance_variable_get(:@handler_errors)&.any?
    report = {version: Burrow::VERSION, checked_at: Time.now.utc.iso8601, platform: RUBY_PLATFORM, ruby: RUBY_VERSION, seconds: (Burrow.clock - started).round(2),
      headless: ENV["SCARPE_NATIVE_HEADLESS"] == "1", clock: "real monotonic",
      packaged: !!ENV["BURROW_PACKAGE_RES"], macos_execution: RUBY_PLATFORM.include?("darwin"),
      audio: client.instance_variable_get(:@audio).available, audio_driver: ENV["ALSOFT_DRIVERS"], biomes: biomes.to_a,
      teams: 6, grubs: 36, computer_teams: 4, matches: matches.length, completed_matches: finished,
      turns: matches.values.sum, human_socket_shots: sent.length, terrain_changes: terrain_changes, resizes: resizes, camera_changes: camera_changes,
      rejected_late_inputs: late_inputs.tally, retained_after_gc: retained,
      app_update_intervals: stats.call(intervals), ruby_scene_preparation: stats.call(scene_times), samples: samples}
    File.write(output, JSON.pretty_generate(report) + "\n")
    puts JSON.generate(report.reject { |k, _| k == :samples })
  rescue Exception => error
    failed = true
    warn "Native soak failed: #{error.full_message}"
  ensure
    friends.each(&:close)
    Shoes.APPS.each(&:destroy)
  end
end
load(ENV["BURROW_PACKAGE_RES"] ? File.join(ENV["BURROW_PACKAGE_RES"], "boot.rb") : File.join(source_root, "game.rb"))
