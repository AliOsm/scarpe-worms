# frozen_string_literal: true
require_relative "test_helper"

class WeaponPhysicsTest < Minitest::Test
  # Controlled geometry exercises impacts independently of random map generation.
  def arena(**options)
    match = game({"wind" => 0, "retreat_seconds" => 0, "fall_damage" => false}.merge(options.transform_keys(&:to_s)))
    data = "\0".b * Burrow::Terrain::SIZE
    floor = 500 / Burrow::Terrain::CELL
    data[floor * Burrow::Terrain::W..] = "\1" * ((Burrow::Terrain::H - floor) * Burrow::Terrain::W)
    match.instance_variable_set(:@terrain, Burrow::Terrain.new(seed: 1, data: data))
    match.instance_variable_set(:@water, 624.0)
    match.worms.each_with_index { |w, i| w.merge!(x: 200.0 + i * 280, y: 500.0, vx: 0.0, vy: 0.0) }
    match
  end

  def launch(match, id, **values)
    match.command("p0", "fire", {weapon: id, angle: -30, power: 0.5, fuse: 3}.merge(values))
    match.projectiles.first
  end

  def test_last_shotgun_cartridge_still_has_two_shots
    match = arena(ammo: {"shotgun" => 1})
    launch(match, "shotgun", angle: 0)
    assert_equal 0, match.team[:inventory]["shotgun"]
    assert_equal 1, match.snapshot[:shots_left]
    launch(match, "shotgun", angle: -5)
    assert_equal 2, match.events.count { |e| e[:kind] == "beam" }
    assert_equal "settling", match.phase
  end

  def test_grenade_bounces_off_a_worm_without_ending_its_fuse
    match = arena
    victim = match.worms[1]
    p = launch(match, "grenade")
    p.merge!(x: victim[:x] - 17, y: victim[:y] - 10, vx: 180.0, vy: 0.0, age: 8)
    match.step
    assert_includes match.projectiles, p
    assert_operator p[:life], :>, 1
    assert_operator p[:vx], :<, 0
    assert_equal 100, victim[:hp]
  end

  def test_close_rocket_hits_the_enemy_during_its_first_tick
    match = arena
    victim = match.worms[1]
    victim[:x] = match.active[:x] + 32
    p = launch(match, "rocket", angle: 0)
    match.step
    refute_includes match.projectiles, p
    assert_operator victim[:hp], :<, 100
  end

  def test_muzzle_and_rifle_cannot_skip_a_thin_nearby_wall
    %w[rocket rifle].each do |id|
      match = arena
      match.terrain.bridge(211, 472, width: 2, height: 30)
      victim = match.worms[1]
      victim[:x] = 245
      launch(match, id, angle: 0)
      if id == "rocket"
        assert_operator match.projectiles.first[:x], :<, 210
        match.step
        assert_empty match.projectiles
      else
        assert_equal 100, victim[:hp]
        assert_operator match.events.find { |e| e[:kind] == "beam" }[:x2], :<, 215
      end
    end
  end

  def test_floor_wall_and_slope_bounces_reflect_out_of_the_ground
    match = arena
    p = launch(match, "grenade")
    p.merge!(x: 700.0, y: 497.0, vx: 90.0, vy: 120.0)
    match.step
    assert_operator p[:vy], :<, 0
    assert_operator p[:vx], :>, 0
    match.terrain.bridge(800, 410, width: 4, height: 90)
    p.merge!(x: 794.0, y: 450.0, vx: 180.0, vy: 0.0)
    match.step
    assert_operator p[:vx], :<, 0
    p.merge!(vx: 120.0, vy: 160.0)
    match.send(:reflect_projectile, p, -Math.sqrt(0.5), -Math.sqrt(0.5))
    assert_operator p[:vx] + p[:vy], :<, 0
    assert p.values_at(:vx, :vy).all?(&:finite?)
  end

  def test_resting_grenade_falls_when_its_support_is_destroyed
    match = arena
    p = launch(match, "grenade", fuse: 5)
    p.merge!(x: 700.0, y: 498.0, vx: 0.0, vy: 0.0, stuck: true, support_x: 700, support_y: 500)
    match.terrain.carve(700, 500, 45)
    match.step(5)
    assert_operator p[:y], :>, 500
    refute p[:stuck]
  end

  def test_sticky_bomb_attaches_to_a_body_and_follows_it
    match = arena
    victim = match.worms[1]
    p = launch(match, "sticky")
    p.merge!(x: victim[:x] - 17, y: 488.0, vx: 200.0, vy: 0.0)
    match.step
    assert_equal victim[:id], p[:attached_to]
    prior = p[:x]
    victim[:x] += 40
    match.step
    assert_in_delta prior + 40, p[:x], 0.01
  end

  def test_homing_turns_without_stalling_and_holds_its_locked_destination
    match = arena
    p = launch(match, "homing", x: 700, y: 100)
    p.merge!(x: 800.0, y: 200.0, vx: 300.0, vy: 0.0, age: 20)
    match.step(12)
    assert_operator Math.hypot(p[:vx], p[:vy]), :>=, 300
    assert_operator p[:vy], :<, 0
    assert_equal [700.0, 100.0], p.values_at(:target_x, :target_y)
  end

  def test_super_sheep_walks_launches_steers_and_drops_without_moving_its_owner
    match = arena
    p = launch(match, "super_sheep")
    assert_equal "walking", p[:stage]
    x = match.active[:x]
    match.step(8)
    match.command("p0", "activate")
    assert_equal "flying", p[:stage]
    assert_in_delta(-230, p[:vy])
    match.command("p0", "steer", direction: 1)
    match.step(6)
    assert_operator p[:vx], :>, 80
    assert_in_delta 230, Math.hypot(p[:vx], p[:vy]), 0.001
    assert_in_delta x, match.active[:x], 0.01
    heading = p[:heading]
    match.step(20)
    expired = p[:heading]
    match.step(3)
    assert_operator expired, :>, heading
    assert_equal expired, p[:heading], "released or lost steering must expire"
    match.command("p0", "activate")
    assert_equal "falling", p[:stage]
    refute p[:guided]
    vy = p[:vy]
    match.step
    assert_operator p[:vy], :>, vy
  end

  def test_remote_is_owned_and_remains_controllable_after_shooter_dies
    match = arena
    p = launch(match, "super_sheep")
    assert_raises(Burrow::RuleError) { match.command("p1", "activate") }
    match.active[:hp] = 0
    match.command("p0", "activate")
    match.command("p0", "steer", direction: -1)
    match.step(3)
    assert_equal "flying", p[:stage]
    assert_operator p[:vx], :<, 0
  end

  def test_mole_runs_then_dives_and_carves_before_remote_detonation
    match = arena
    p = launch(match, "mole")
    match.step(5)
    assert_equal "walking", p[:stage]
    before = match.terrain.checksum
    match.command("p0", "activate")
    assert_equal "diving", p[:stage]
    70.times { match.step; break if p[:stage] == "digging" }
    assert_equal "digging", p[:stage]
    refute_equal before, match.terrain.checksum
    match.command("p0", "activate")
    match.step
    refute_includes match.projectiles, p
    assert match.events.any? { |e| e[:kind] == "explosion" && e[:style] == "mole" }
  end

  def test_skunk_sprays_only_after_activation_and_cows_are_staggered
    match = arena
    launch(match, "skunk")
    match.step(20)
    refute match.hazards.any? { |h| h[:kind] == "gas" }
    match.command("p0", "activate")
    assert match.hazards.any? { |h| h[:kind] == "gas" }
    match = arena
    launch(match, "cow")
    assert_equal 1, match.snapshot[:projectiles].length
    match.step(24)
    assert_equal 2, match.snapshot[:projectiles].length
    match.step(24)
    assert_equal 3, match.snapshot[:projectiles].length
    assert_operator match.projectiles.map { |p| p[:x] }.max - match.projectiles.map { |p| p[:x] }.min, :>, 100
  end

  def test_rope_reels_detaches_without_spending_another_charge_and_loses_destroyed_anchor
    match = arena
    match.terrain.bridge(250, 300, width: 90)
    launch(match, "rope", x: 250, y: 300)
    initial_length = match.active[:rope][:length]
    ammo = match.team[:inventory]["rope"]
    match.command("p0", "move", direction: 1, lift: 1)
    match.step(6)
    assert_operator match.active[:rope][:length], :<, initial_length
    assert match.terrain.free_body?(match.active[:x], match.active[:y])
    match.command("p0", "activate")
    assert_nil match.active[:rope]
    assert_equal ammo, match.team[:inventory]["rope"]
    launch(match, "rope", x: 250, y: 300)
    anchor = match.active[:rope].dup
    match.terrain.carve(anchor[:x], anchor[:y], 45)
    match.step
    assert_nil match.active[:rope]
  end

  def test_jetpack_burns_fuel_only_during_thrust_and_can_land
    match = arena
    launch(match, "jetpack")
    match.step(10)
    assert_equal 120, match.active[:fuel]
    match.command("p0", "move", direction: 1, lift: 1)
    match.step(6)
    assert_equal 114, match.active[:fuel]
    assert_operator match.active[:vx], :>, 0
    assert_operator match.active[:vy], :<, 0
    match.command("p0", "activate")
    refute match.active[:jetpack]
    assert match.active[:parachute]
    assert_equal "aiming", match.phase
  end

  def test_tools_can_be_steered_stopped_and_recovered_mid_action
    match = arena
    launch(match, "blowtorch")
    match.command("p0", "steer", lift: 1)
    match.step(6)
    restored = Burrow::Match.restore(JSON.parse(JSON.generate(match.checkpoint)))
    8.times { match.step; restored.step }
    assert_equal JSON.generate(match.snapshot(terrain: true)), JSON.generate(restored.snapshot(terrain: true))
    match.command("p0", "activate")
    before = match.terrain.checksum
    match.step(10)
    assert_equal before, match.terrain.checksum
    assert_nil match.snapshot[:tool]
  end

  def test_bursts_are_timed_and_resume_without_losing_rounds
    match = arena
    launch(match, "minigun", angle: -20)
    assert_equal 1, match.events.count { |e| e[:kind] == "beam" }
    match.step(3)
    restored = Burrow::Match.restore(JSON.parse(JSON.generate(match.checkpoint)))
    20.times { match.step; restored.step }
    assert_equal 8, match.events.count { |e| e[:kind] == "beam" }
    assert_equal JSON.generate(match.snapshot(terrain: true)), JSON.generate(restored.snapshot(terrain: true))
  end

  def test_cluster_boost_applies_to_fragments_and_mortar_uses_fixed_power
    match = arena
    launch(match, "double_damage")
    launch(match, "cluster", fuse: 1)
    match.step(30)
    assert_equal 5, match.projectiles.length
    assert match.projectiles.all? { |p| p[:damage] == 48 }
    speeds = [0.05, 1].map do |power|
      m = arena
      p = launch(m, "mortar", power: power, angle: 30)
      speed = Math.hypot(p[:vx], p[:vy])
      80.times { m.step; break if m.projectiles.any? { |fragment| fragment[:fragment] } }
      assert_equal 5, m.projectiles.count { |fragment| fragment[:fragment] }
      speed
    end
    assert_in_delta speeds[0], speeds[1], 0.001
  end

  def test_frozen_grubs_are_not_knocked_back_by_guns
    match = arena
    victim = match.worms[1]
    victim[:frozen] = true
    launch(match, "rifle", angle: 0)
    assert_equal 100, victim[:hp]
    assert_equal [0.0, 0.0], victim.values_at(:vx, :vy)
  end

  def test_staged_weapons_and_delayed_launches_restore_deterministically
    %w[super_sheep mole skunk cow].each do |id|
      match = arena
      launch(match, id)
      match.step(4)
      match.command("p0", "activate") unless id == "cow"
      match.command("p0", "steer", direction: 1) if id == "super_sheep"
      match.step(5)
      restored = Burrow::Match.restore(JSON.parse(JSON.generate(match.checkpoint)))
      80.times { match.step; restored.step }
      assert_equal JSON.generate(match.snapshot(terrain: true)), JSON.generate(restored.snapshot(terrain: true)), id
    end
  end

  def test_full_speed_projectiles_cannot_tunnel_through_a_single_cell_wall
    [0.4, 1.6].each do |gravity|
      match = arena(gravity: gravity)
      match.terrain.bridge(600, 360, width: 0, height: 140)
      p = launch(match, "rocket")
      p.merge!(x: 579.0, y: 420.0, vx: 670.0, vy: 0.0)
      match.step(2)
      refute_includes match.projectiles, p
      assert_operator match.events.find { |e| e[:kind] == "explosion" }[:x], :<, 602
    end
  end

  def test_dash_motion_is_visible_across_ticks_and_hits_each_target_once
    match = arena
    victim = match.worms[1]
    victim[:x] = 265
    before = match.active[:x]
    launch(match, "dragon_punch", angle: 0)
    assert_equal before, match.active[:x]
    match.step(4)
    assert_operator match.active[:x], :>, before
    assert_operator match.active[:x], :<, before + 60
    assert_equal 58, victim[:hp]
    match.step(15)
    assert_equal 58, victim[:hp]
  end

  def test_fuse_detonation_is_timed_even_after_a_bounce_and_choir_waits_until_rest
    match = arena
    p = launch(match, "grenade", angle: 20, power: 0.05, fuse: 1)
    match.step(29)
    assert_includes match.projectiles, p
    match.step
    refute_includes match.projectiles, p
    match = arena
    p = launch(match, "holy_bomb", angle: -90)
    p.merge!(x: 700.0, y: 200.0, vx: 0.0, vy: 0.0, age: 149, life: 1)
    match.step
    assert_includes match.projectiles, p
    p.merge!(x: 700.0, y: 498.0, stuck: true, support_x: 700, support_y: 500)
    match.step
    refute_includes match.projectiles, p
  end

  def test_malformed_steering_does_not_change_motion_or_the_command_log
    match = arena
    p = launch(match, "super_sheep")
    match.command("p0", "activate")
    before = match.inputs.length
    [Float::NAN, 9, "left", {}].each do |direction|
      assert_raises(Burrow::RuleError) { match.command("p0", "steer", direction: direction) }
    end
    assert_equal before, match.inputs.length
    assert_equal 0, p[:steer]
  end
end
