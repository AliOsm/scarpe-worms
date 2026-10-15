# frozen_string_literal: true
require_relative "test_helper"

# Reference-driven behaviors, with geometry and timings independent of map RNG.
class VideoWeaponPhysicsTest < Minitest::Test
  def arena(water_gap: false, **options)
    match = game({"wind" => 0, "retreat_seconds" => 0, "fall_damage" => false}.merge(options.transform_keys(&:to_s)))
    data = "\0".b * Burrow::Terrain::SIZE
    row = 500 / Burrow::Terrain::CELL
    data[row * Burrow::Terrain::W..] = "\1" * ((Burrow::Terrain::H - row) * Burrow::Terrain::W)
    if water_gap
      (row...Burrow::Terrain::H).each { |y| data[y * Burrow::Terrain::W + 300, 250] = "\0" * 250 }
    end
    match.instance_variable_set(:@terrain, Burrow::Terrain.new(seed: 1, data: data))
    match.instance_variable_set(:@water, 624.0)
    match.worms.zip([200, 480, 1250, 1350]).each { |w, x| w.merge!(x: x.to_f, y: 500.0, vx: 0.0, vy: 0.0) }
    match
  end

  def launch(match, weapon = "grenade", **values)
    match.command("p0", "fire", {weapon: weapon, angle: -30, power: 0.5, fuse: 5}.merge(values))
    match.projectiles.first
  end

  def restore(match) = Burrow::Match.restore(JSON.parse(JSON.generate(match.checkpoint)))

  def test_preview_can_distinguish_new_hosts_from_protocol_four_legacy_hosts
    assert_equal 1, arena.snapshot[:physics_revision]
    assert_in_delta 157, Burrow::Physics.launch_speed("grenade", 0.05, legacy: true)
    assert_in_delta 33.5, Burrow::Physics.launch_speed("grenade", 0.05)
    assert_in_delta 670, Burrow::Physics.launch_speed("rocket", 1.0, legacy: true)
    assert_in_delta 670, Burrow::Physics.launch_speed("rocket", 1.0)
    [false, true].each { |legacy| assert_in_delta 580, Burrow::Physics.launch_speed("mortar", 0.05, legacy: legacy) }
  end

  def test_light_taps_make_short_lobs_while_full_charge_keeps_long_range
    distances = [0.05, 0.25, 1.0].map do |power|
      match = arena
      shot = launch(match, power: power, angle: -30)
      from = shot[:x]
      match.step(20)
      shot[:x] - from
    end
    assert_operator distances[0], :<, 25, "a tap can place a grenade close to the thrower"
    assert_operator distances[1], :>, distances[0] * 3
    assert_operator distances[2], :>, 300, "full charge retains its former reach"
  end

  def test_final_fuse_tick_advances_to_the_actual_airburst_position
    match = arena
    shot = launch(match, fuse: 1)
    shot.merge!(x: 700.0, y: 100.0, vx: 90.0, vy: -20.0, life: 1, age: 29)
    match.step
    explosion = match.events.find { |e| e[:kind] == "explosion" }
    assert_in_delta 703.0, explosion[:x], 0.001
    assert_in_delta 99.65, explosion[:y], 0.001
    refute_includes match.projectiles, shot
  end

  def test_floor_and_wall_rebounds_use_the_remaining_flight_time
    match = arena
    shot = launch(match)
    shot.merge!(x: 700.0, y: 499.9, vx: 120.0, vy: 300.0)
    match.step
    assert_operator shot[:y], :<, 497, "a floor bounce moves upward immediately"
    assert_in_delta 703.21, shot[:x], 0.04
    match.terrain.bridge(800, 350, width: 0, height: 100)
    shot.merge!(x: 799.8, y: 400.0, vx: 600.0, vy: 0.0)
    match.step
    assert_operator shot[:x], :<, 795, "a wall bounce moves away during the same tick"
    refute match.terrain.solid?(shot[:x], shot[:y])
  end

  def test_a_fast_bomb_can_rebound_twice_in_a_corner_without_embedding
    match = arena
    match.terrain.bridge(800, 380, width: 0, height: 90)
    match.terrain.bridge(760, 400, width: 80, height: 8)
    shot = launch(match)
    shot.merge!(x: 799.5, y: 410.5, vx: 300.0, vy: -300.0)
    match.step
    assert_operator shot[:vx], :<, 0
    assert_operator shot[:vy], :>, 0
    refute match.terrain.solid?(shot[:x], shot[:y])
    assert_operator match.events.count { |e| e[:kind] == "bounce" }, :<=, 1, "contacts share one sound per tick"
    assert_equal 149, shot[:life]
  end

  def test_a_tumbling_grub_uses_its_rebound_velocity_before_the_tick_ends
    match = arena
    victim = match.worms[1]
    victim.merge!(x: 700.0, y: 499.9, vx: 120.0, vy: 300.0, launched: true)
    match.step
    assert_operator victim[:vy], :<, 0
    assert_operator victim[:y], :<, 498, "blast victims do not freeze at the floor for a tick"
    assert_equal 100, victim[:hp]
    match.terrain.bridge(800, 350, width: 0, height: 110)
    victim.merge!(x: 793.8, y: 430.0, vx: 600.0, vy: 0.0, launched: true)
    match.step
    assert_operator victim[:vx], :<, 0
    assert_operator victim[:x], :<, 792, "the grub travels away from the wall immediately"
    assert match.send(:body_clear?, victim[:x], victim[:y])
  end

  def test_shallow_rockets_skip_in_either_direction_without_detonating
    [-1, 1].each do |direction|
      match = arena(water_gap: true)
      shot = launch(match, "rocket")
      shot.merge!(x: 800.0, y: 623.9, vx: direction * 400.0, vy: 60.0)
      speed_before = Math.hypot(shot[:vx], shot[:vy] + match.send(:gravity) * Burrow::DT)
      match.step
      assert_includes match.projectiles, shot
      assert_operator shot[:vy], :<, 0
      assert_operator shot[:y], :<, match.water
      assert_operator (shot[:x] - 800) * direction, :>, 9, "the skip preserves the remaining flight time"
      assert_operator Math.hypot(shot[:vx], shot[:vy]), :<, speed_before
      assert_equal 269, shot[:life], "a skip must not reset the lifetime"
      assert_equal 1, match.events.count { |e| e[:kind] == "splash" && e[:skim] }
      refute match.events.any? { |e| e[:kind] == "explosion" }
    end
  end

  def test_steep_or_slow_shots_sink_and_homing_keeps_its_underwater_path
    [["rocket", 400, 300], ["rocket", 120, 10], ["dynamite", 400, 10], ["sticky", 400, 10]].each do |weapon, vx, vy|
      match = arena(water_gap: true)
      shot = launch(match, weapon)
      shot.merge!(x: 800.0, y: 623.9, vx: vx.to_f, vy: vy.to_f)
      match.step
      refute_includes match.projectiles, shot, weapon
      refute match.events.any? { |e| e[:kind] == "explosion" || e[:skim] }, weapon
      assert_equal 1, match.events.count { |e| e[:kind] == "splash" }, weapon
    end
    match = arena(water_gap: true)
    shot = launch(match, "homing", x: 1000, y: 680)
    shot.merge!(x: 800.0, y: 623.9, vx: 400.0, vy: 60.0)
    match.step
    assert_includes match.projectiles, shot
    assert_operator shot[:y], :>, match.water
    refute match.events.any? { |e| e[:kind] == "splash" }
  end

  def test_skipping_grenades_keep_their_fuse_and_fragments_do_not_skip
    match = arena(water_gap: true)
    shot = launch(match, fuse: 1)
    shot.merge!(x: 800.0, y: 623.9, vx: 600.0, vy: 120.0)
    match.step
    assert_operator shot[:vy], :<, 0
    shot.merge!(x: 800.0, y: 300.0, vx: 0.0, vy: 0.0)
    match.step(28)
    assert_includes match.projectiles, shot
    match.step
    refute_includes match.projectiles, shot
    assert_equal 30, match.events.find { |e| e[:kind] == "explosion" }[:tick]
    match = arena(water_gap: true)
    shot = launch(match, "cluster")
    shot.merge!(x: 800.0, y: 623.9, vx: 400.0, vy: 60.0, fragment: true)
    match.step
    refute_includes match.projectiles, shot
    refute match.events.any? { |e| e[:skim] }
  end

  def test_skips_bounces_and_their_fuses_resume_identically_from_checkpoints
    [false, true].each do |gap|
      match = arena(water_gap: gap)
      shot = launch(match)
      shot.merge!(x: 800.0, y: gap ? 623.9 : 499.9, vx: 400.0, vy: gap ? 60.0 : 200.0)
      match.step
      recovered = restore(match)
      100.times do
        match.step
        recovered.step
        assert_equal match.checkpoint, recovered.checkpoint
      end
    end
  end

  def test_a_skipped_rocket_can_hit_the_far_bank_and_the_bot_predicts_it
    match = arena(water_gap: true)
    match.active.merge!(x: 610.0, y: 624.0)
    expected = Burrow::Bot.impact(match, 0, 1.0)
    shot = launch(match, "rocket", angle: 0, power: 1.0)
    90.times { match.step; break unless match.projectiles.include?(shot) }
    impact = match.events.find { |e| e[:kind] == "explosion" }
    assert impact, "the rocket reaches the far bank instead of disappearing in the sea"
    assert match.events.any? { |e| e[:skim] }
    assert_in_delta 1100, impact[:x], 1
    assert_in_delta impact[:x], expected[0], 8, "bot search uses the same charge and water response"
    assert_in_delta impact[:y], expected[1], 8
  end
end
