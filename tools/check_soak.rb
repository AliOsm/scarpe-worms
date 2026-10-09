# frozen_string_literal: true
# SCARPE_DISPLAY_SERVICE=native SCARPE_NATIVE_HEADLESS=1 ./bin/scarpe tools/check_soak.rb
# Real-time native exercise; optional BURROW_SOAK_SECONDS (default 300).
require "tmpdir"
require_relative "../lib/burrow"

directory = Dir.mktmpdir("burrow-native-soak-")
ENV["BURROW_DATA_DIR"] = directory
ENV["BURROW_MUTE"] = "1"
ENV.delete("BURROW_CONNECT")
ENV.delete("BURROW_AUTOPLAY")
output = File.join(Burrow::ROOT, "docs/validation")
shots = File.join(Burrow::ROOT, ".cache/soak-shots")
FileUtils.mkdir_p([output, shots])
failed = false
at_exit { FileUtils.remove_entry(directory) if File.directory?(directory); exit(1) if failed }

require_relative "../lib/burrow/client/app"
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
    raise "Expected 36 grubs" unless client.state["worms"].size == 36
    auto.snapshot(File.join(shots, "glacier-start.png"))
    started = Burrow.clock
    duration = Float(ENV.fetch("BURROW_SOAK_SECONDS", "300")).clamp(30, 3600)
    next_sample, next_resize = started, started + 30
    samples, matches, sent, retained = [], {}, {}, []
    late_inputs = []
    friend_state = nil
    finished, resizes, terrain_changes = 0, 0, 0
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
      if now >= next_resize
        resizes += 1
        auto.key("e")
        raise "Arsenal did not open" unless client.overlay?
        auto.click({text: "Close"})
        auto.resize(*(resizes.odd? ? [1440, 900] : [1080, 675]))
        wait.call { client.scene && client.scene.terrain_revision >= 0 && client.instance_variable_get(:@dimensions) == (resizes.odd? ? [1440, 900] : [1080, 675]) }
        next_resize = now + 30
        auto.snapshot(File.join(shots, "battle-#{resizes}.png"))
      end
      if now >= next_sample
        rss = lambda { |pid| File.read("/proc/#{pid}/status")[/^VmRSS:\s+(\d+)/, 1].to_i if File.exist?("/proc/#{pid}/status") }
        children_file = "/proc/#{Process.pid}/task/#{Process.pid}/children"
        child = File.exist?(children_file) && File.read(children_file).split.first
        sample = {seconds: (now - started).round(2), match: finished + 1, turn: state["turn"],
          ruby_rss_kib: rss.call(Process.pid), native_rss_kib: child && rss.call(child),
          scene_ms: client.scene.performance, nodes: auto.layout.length, threads: Thread.list.count(&:alive?),
          effects: client.scene.instance_variable_get(:@effects).length,
          terrain_files: Dir[File.join(client.scene.instance_variable_get(:@terrain_art).directory, "*.png")].length}
        samples << sample
        puts JSON.generate(sample)
        $stdout.flush
        raise "Terrain cache grew past its bound" if sample[:terrain_files] > client.scene.instance_variable_get(:@tiles).length * 3 + 3
        raise "Drawable count grew unexpectedly" if sample[:nodes] > 2400
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
    report = {platform: RUBY_PLATFORM, ruby: RUBY_VERSION, seconds: (Burrow.clock - started).round(2),
      headless: ENV["SCARPE_NATIVE_HEADLESS"] == "1", clock: "real monotonic",
      teams: 6, grubs: 36, computer_teams: 4, matches: matches.length, completed_matches: finished,
      turns: matches.values.sum, human_socket_shots: sent.length, terrain_changes: terrain_changes, resizes: resizes,
      rejected_late_inputs: late_inputs.tally, retained_after_gc: retained,
      app_update_intervals: stats.call(intervals), ruby_scene_preparation: stats.call(scene_times), samples: samples}
    File.write(File.join(output, "native-soak.json"), JSON.pretty_generate(report) + "\n")
    puts JSON.generate(report.reject { |k, _| k == :samples })
  rescue Exception => error
    failed = true
    warn "Native soak failed: #{error.full_message}"
  ensure
    friends.each(&:close)
    Shoes.APPS.each(&:destroy)
  end
end
load File.join(Burrow::ROOT, "game.rb")
