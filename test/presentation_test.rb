# frozen_string_literal: true
require_relative "test_helper"
require_relative "../lib/burrow/client/timeline"
require_relative "../lib/burrow/client/camera"
require_relative "../lib/burrow/client/connection"
require_relative "../lib/burrow/client/terrain_art"

class PresentationTest < Minitest::Test
  def wire(match) = JSON.parse(JSON.generate(match.snapshot(terrain: true)))

  def test_coalesced_snapshots_keep_a_one_tick_weapon_flight_and_its_impact
    match = game
    timeline = Burrow::Client::Timeline.new
    timeline.accept(wire(match), now: 10)
    timeline.sample(now: 10)
    match.step
    match.command("p0", "fire", weapon: "rocket", angle: 90, power: 0.7)
    id = match.projectiles.first[:id]
    match.step(8)
    assert_empty match.projectiles
    # Two packets arrive while the GUI is busy: only the newest is consumed.
    connection = Burrow::Client::Connection.new(endpoint: "tcp://127.0.0.1:1", name: "Test")
    connection.send(:receive, {"type" => "state", "match" => wire(match)})
    match.step(3)
    connection.send(:receive, {"type" => "state", "match" => wire(match)})
    packet = connection.poll[:state]["match"]
    shot = packet["motion"]["shots"].find { |p| p["id"] == id }
    assert_equal 1, shot["to"] - shot["from"], "this must exercise a flight absent from ordinary snapshots"
    timeline.accept(packet, now: 10.4)
    seen, impact, ticks = [], [], []
    42.times do |i|
      state = timeline.sample(now: 10.4 + i / 60.0)
      seen << timeline.tick if state["projectiles"].any? { |p| p["id"] == id }
      impact.concat(timeline.events.select { |e| e["kind"] == "explosion" }.map { timeline.tick })
      ticks << timeline.tick
    end
    refute_empty seen, "coalescing must not erase a short flight"
    refute_empty impact
    assert_operator seen.last, :<, impact.first
    assert_equal ticks.sort, ticks
    assert_operator ticks.each_cons(2).map { |a, b| b - a }.max, :<=, 1.7
  end

  def test_camera_round_trip_zoom_pan_overview_and_far_targets
    camera = Burrow::Client::Camera.new(4800, 1600)
    camera.navigate(4000, 900)
    camera.zoom_by(-1)
    point = camera.world(*camera.screen(4230, 878))
    assert_in_delta 4230, point[0], 0.001
    assert_in_delta 878, point[1], 0.001
    camera.overview
    assert camera.overview?
    assert_operator camera.screen(0, 0)[0], :>=, 0
    assert_operator camera.screen(4800, 1600)[0], :<=, 1440
    camera.follow
    camera.update([4300, 900], dt: 1.0 / 60)
    assert camera.following
    assert_operator camera.screen(4300, 900)[0], :<, 1440
    camera.pan(-50_000, 50_000)
    refute camera.following
    assert_equal 0, camera.x
    assert_operator camera.y, :<=, 880
  end

  def moving_state(tick, shots: [], events: [])
    {"tick" => tick, "worms" => [{"id" => 1, "x" => tick * 2, "y" => 100}], "hazards" => [],
      "events" => events, "motion" => {"shots" => shots,
        "frames" => ([tick - 30, 0].max..tick).map do |t|
          {"tick" => t, "worms" => [[1, t * 2, 100, 2, 0, 100, 1]], "hazards" => []}
        end}}
  end

  def test_repeated_110ms_frames_do_not_accumulate_playback_delay
    timeline = Burrow::Client::Timeline.new
    timeline.accept(moving_state(30), now: 1)
    timeline.sample(now: 1)
    now = 1.0
    ticks = 600.times.map do |i|
      now += i.even? ? 0.110 : 1.0 / 60
      timeline.accept(moving_state((now * Burrow::TICK_RATE).floor), now: now)
      state = timeline.sample(now: now)
      assert_in_delta timeline.tick * 2, state["worms"].first["x"], 0.001
      assert_operator timeline.backlog_ms, :<, 40, "playback fell behind at #{now} s"
      timeline.tick
    end
    assert_equal ticks.sort, ticks
    assert_in_delta now * Burrow::TICK_RATE - Burrow::Client::Timeline::DELAY, ticks.last, 1
  end

  def test_recorded_mac_update_cadence_stays_within_the_motion_history
    timeline = Burrow::Client::Timeline.new
    samples = JSON.parse(File.read(File.join(__dir__, "fixtures/macos_0_2_3_cadence.json")))
    previous_host_tick = nil
    lags = samples.map do |seconds, host_tick|
      timeline.accept(moving_state(host_tick), now: seconds) unless host_tick == previous_host_tick
      previous_host_tick = host_tick
      timeline.sample(now: seconds)
      [host_tick - timeline.tick, timeline.backlog_ms]
    end
    assert_operator lags.map(&:first).max, :<, 12, "presentation escaped retained motion history"
    assert_operator lags.map(&:last).max, :<, 100
    assert_operator lags.last.first, :<, 6
  end

  def test_long_pause_resynchronizes_without_replaying_expired_impacts
    timeline = Burrow::Client::Timeline.new
    timeline.accept(moving_state(30), now: 1)
    timeline.sample(now: 1)
    # Packets continue arriving while the window is not being sampled.
    (11..35).each do |i|
      timeline.accept(moving_state(i * 3, events: [{"id" => i, "tick" => i * 3, "kind" => "explosion"}]), now: i / 10.0)
    end
    timeline.sample(now: 3.5)
    assert_in_delta 100.5, timeline.tick, 0.01
    assert_equal 1, timeline.resyncs
    assert timeline.events.all? { |event| event["tick"] >= 88.5 }
    assert_operator timeline.backlog_ms, :<, 1
  end

  def test_a_coalesced_host_jump_cannot_leave_playback_behind_pruned_history
    timeline = Burrow::Client::Timeline.new
    timeline.accept(moving_state(30), now: 1)
    timeline.sample(now: 1)
    # No long gap between accepts: catch-up snapshots suddenly expose the live
    # host after an old network backlog. Normal packet-gap reset won't run.
    timeline.accept(moving_state(150), now: 1.02)
    state = timeline.sample(now: 1.02)
    assert_operator timeline.tick, :>=, 133.5
    assert_operator timeline.backlog_ms, :<=, 400.001
    assert_equal 1, timeline.resyncs
    assert_in_delta timeline.tick * 2, state["worms"].first["x"], 0.001
  end

  def test_large_world_targeting_and_checkpoint_dimensions
    match = game({"worms" => 6}, players: 6)
    assert_equal [4800, 1600], [match.world_width, match.world_height]
    match.command("p0", "fire", weapon: "airstrike", x: 4300, y: 850)
    assert match.projectiles.all? { |p| p[:x] > 4000 }
    match.step(8)
    restored = Burrow::Match.restore(JSON.parse(JSON.generate(match.checkpoint)))
    assert_equal match.terrain.export, restored.terrain.export
    assert_equal JSON.generate(match.snapshot), JSON.generate(restored.snapshot)
  end

  def test_terrain_raster_is_isolated_and_only_changed_tiles_are_replaced
    require "chunky_png"
    terrain = Burrow::Terrain.new(seed: 291, width: 2880, height: 1280)
    worker = Burrow::Client::TerrainArt.new
    worker.request(terrain, "meadow")
    first = wait_for(seconds: 12) { worker.poll }
    x = (100...terrain.width - 100).step(12).find { |px| terrain.surface(px) < terrain.height - 200 }
    assert terrain.carve(x, terrain.surface(x) + 35, 40)
    worker.request(terrain, "meadow")
    second = wait_for(seconds: 10) { worker.poll }
    assert_equal terrain.checksum, second[:checksum]
    original = first[:tiles].to_h { |t| [t[:id], t[:path]] }
    changed = second[:tiles].count { |t| original[t[:id]] != t[:path] }
    assert_operator changed, :>, 0
    assert_operator changed, :<=, 4
    assert_operator changed, :<, second[:tiles].length
    second[:tiles].each do |tile|
      image = ChunkyPNG::Image.from_file(tile[:path])
      # The visible texture's opaque mask is exactly the collision mask.
      [5, image.height / 2, image.height - 3].each do |y|
        [5, image.width / 2, image.width - 3].each do |x|
          assert_equal terrain.solid?(tile[:x] + x * 2, tile[:y] + y * 2), ChunkyPNG::Color.a(image[x, y]) > 0
        end
      end
    end
  ensure
    directory = worker&.directory
    worker&.close
    refute File.exist?(directory) if directory
  end

  def test_critter_stage_and_fuse_labels_follow_authoritative_motion_samples
    match = game
    match.command("p0", "fire", weapon: "super_sheep")
    match.step(2)
    launch_tick = match.tick
    match.command("p0", "activate")
    match.step(5)
    timeline = Burrow::Client::Timeline.new
    timeline.accept(wire(match), now: 10.0)
    samples = 10.times.map { |i| [timeline.sample(now: 10.0 + i / 60.0), timeline.tick] }
    samples.each do |state, tick|
      p = state["projectiles"].first
      next unless p
      if tick < launch_tick + 1
        assert p["walker"]
        assert_equal "walking", p["stage"]
      else
        refute p["walker"]
        assert_equal "flying", p["stage"]
      end
    end
    match = game
    match.command("p0", "fire", weapon: "cluster", angle: -80, fuse: 1)
    match.step(30)
    shots = match.snapshot[:motion][:shots]
    assert shots.find { |p| p["weapon"] == "cluster" && p["to"] }["fused"]
    assert shots.reject { |p| p["to"] }.all? { |p| !p["fused"] }, "impact fragments must not display a grenade countdown"
  end
end
