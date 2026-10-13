# frozen_string_literal: true

require_relative "test_helper"

class WeaponsMobilityTest < Minitest::Test
  def arena(**options)
    match = game({"wind" => 0, "retreat_seconds" => 0, "fall_damage" => true}.merge(options.transform_keys(&:to_s)))
    data = "\0".b * Burrow::Terrain::SIZE
    floor = 500 / Burrow::Terrain::CELL
    data[floor * Burrow::Terrain::W..] = "\1" * ((Burrow::Terrain::H - floor) * Burrow::Terrain::W)
    match.instance_variable_set(:@terrain, Burrow::Terrain.new(seed: 1, data: data))
    match.instance_variable_set(:@water, 624.0)
    match.worms.each_with_index { |w, i| w.merge!(x: 200.0 + i * 280, y: 500.0, vx: 0.0, vy: 0.0) }
    match
  end

  def fire(match, id, **values)
    match.command("p0", "fire", {weapon: id, angle: -90, power: 0.5, fuse: 2}.merge(values))
  end

  def thrust(match, ticks, direction: 0, lift: 0)
    ticks.times do |i|
      match.command("p0", "move", direction: direction, lift: lift) if i % 6 == 0
      match.step
    end
  end

  def ceiling(match)
    match.terrain.bridge(250, 300, width: 180, height: 2)
  end

  def hook(match, angle: -90)
    fire(match, "rope", angle: angle)
    15.times do
      match.step
      return if match.active[:rope]&.fetch(:stage) == "attached"
    end
    flunk "grapple did not attach"
  end

  def test_hook_flies_before_attaching_to_first_solid_cell_and_spends_on_hit
    match = arena
    ceiling(match)
    match.terrain.bridge(200, 200, width: 100, height: 12)
    ammo = match.team[:inventory]["rope"]
    fire(match, "rope", x: 1100, y: 490) # cursor coordinates cannot override the aim
    assert_equal "shooting", match.active[:rope][:stage]
    assert_equal ammo, match.team[:inventory]["rope"]
    match.step
    assert_in_delta 449.67, match.active[:rope][:y], 0.1
    assert_equal "shooting", match.active[:rope][:stage]
    match.step(5)
    rope = match.active[:rope]
    assert_equal "attached", rope[:stage]
    assert_operator rope[:y], :>=, 300
    assert_operator rope[:y], :<, 304
    assert_equal ammo - 1, match.team[:inventory]["rope"]
    assert_in_delta Math.hypot(rope[:x] - match.active[:x], rope[:y] - match.active[:y] + 12), rope[:length], 0.2
  end

  def test_miss_retracts_without_ammo_and_downward_fire_is_rejected
    match = arena
    ammo = match.team[:inventory]["rope"]
    fire(match, "rope", angle: -90)
    match.step(12)
    assert_equal "retracting", match.active[:rope][:stage]
    before = match.active[:rope][:y]
    match.step
    assert_operator match.active[:rope][:y], :>, before
    match.step(12)
    assert_nil match.active[:rope]
    assert_equal ammo, match.team[:inventory]["rope"]
    assert_equal "aiming", match.phase
    assert_raises(Burrow::RuleError) { fire(match, "rope", angle: 90) }
    assert_equal ammo, match.team[:inventory]["rope"]
  end

  def test_sideways_hook_hits_a_single_cell_wall
    match = arena
    match.terrain.bridge(420, 440, width: 0, height: 58)
    hook(match, angle: 0)
    assert match.terrain.solid?(match.active[:rope][:x], match.active[:rope][:y])
    assert_in_delta 420, match.active[:rope][:x], 2
  end

  def test_reel_pump_release_and_last_cartridge_airborne_rehook
    match = arena(ammo: {"rope" => 1})
    ceiling(match)
    hook(match)
    initial = match.active[:rope][:length]
    thrust(match, 22, lift: 1)
    assert_operator match.active[:rope][:length], :<, initial - 60
    assert_operator match.active[:y], :<, 440
    thrust(match, 14, direction: 1)
    assert_operator match.active[:vx], :>, 60
    assert match.terrain.free_body?(match.active[:x], match.active[:y])
    velocity = match.active.values_at(:vx, :vy)
    match.command("p0", "jump")
    assert_nil match.active[:rope]
    assert_equal velocity, match.active.values_at(:vx, :vy)
    assert_equal 0, match.team[:inventory]["rope"]
    hook(match)
    assert_equal 0, match.team[:inventory]["rope"], "re-hook shares the last cartridge"
    velocity = match.active.values_at(:vx, :vy)
    match.command("p0", "activate")
    assert_equal velocity, match.active.values_at(:vx, :vy)
    thrust(match, 100)
    refute match.active[:rope_use], "landing closes the airborne chain"
    assert_raises(Burrow::RuleError) { fire(match, "rope") }
  end

  def test_releasing_on_ground_cannot_reuse_a_spent_rope
    match = arena(ammo: {"rope" => 1})
    ceiling(match)
    hook(match)
    assert match.grounded?(match.active)
    match.command("p0", "activate")
    refute match.active[:rope_use]
    assert_raises(Burrow::RuleError) { fire(match, "rope") }
  end

  def test_pendulum_swings_back_under_gravity_without_input
    match = arena
    ceiling(match)
    hook(match)
    thrust(match, 25, lift: 1)
    thrust(match, 14, direction: 1)
    assert_operator match.active[:vx], :>, 30
    match.command("p0", "move", direction: 0, lift: 0)
    velocities = 60.times.map { match.step; match.active[:vx] }
    assert velocities.any? { |vx| vx < -25 }, "gravity should reverse the free swing"
    assert match.active[:rope]
  end

  def test_reeling_cannot_pull_body_through_an_overhang_and_anchor_destruction_releases
    match = arena
    ceiling(match)
    hook(match)
    thrust(match, 80, lift: 1)
    assert match.terrain.free_body?(match.active[:x], match.active[:y])
    assert_operator match.active[:y], :>=, 320
    rope = match.active[:rope].dup
    match.terrain.carve(rope[:x], rope[:y], 20)
    match.step
    assert_nil match.active[:rope]
    assert match.active[:rope_use], "a destroyed anchor still allows airborne recovery"
  end

  def test_jetpack_reaches_responsive_speed_has_five_seconds_and_idle_conserves_fuel
    match = arena
    fire(match, "jetpack")
    assert_equal 150, match.active[:fuel]
    match.step(12)
    assert_equal 150, match.active[:fuel]
    refute match.active[:thrusting]
    thrust(match, 15, direction: 1, lift: 1)
    assert_in_delta(-220, match.active[:vy], 1)
    assert_operator match.active[:vx], :>, 180
    assert_operator match.active[:y], :<, 440
    assert_equal 135, match.active[:fuel]
    assert match.active[:thrusting]
    vx = match.active[:vx]
    thrust(match, 6)
    assert_equal 135, match.active[:fuel]
    assert_operator match.active[:vx], :<, vx
    refute match.active[:thrusting]
    thrust(match, 3, lift: -1)
    assert_equal 135, match.active[:fuel], "down alone does not burn upward thrust"
  end

  def test_input_lease_expires_and_fuel_exhaustion_or_stop_deploys_parachute
    match = arena
    fire(match, "jetpack")
    match.command("p0", "move", lift: 1)
    match.step(13)
    assert_equal 138, match.active[:fuel]
    refute match.active[:thrusting]
    match.active[:fuel] = 2
    thrust(match, 2, lift: 1)
    refute match.active[:jetpack]
    assert match.active[:parachute]
    assert_equal 0, match.active[:fuel]
    thrust(match, 160)
    assert_equal 100, match.active[:hp]
    refute match.active[:parachute_open]

    fire(match, "jetpack")
    thrust(match, 8, lift: 1)
    velocity = match.active.values_at(:vx, :vy)
    match.command("p0", "activate")
    assert_equal velocity, match.active.values_at(:vx, :vy)
    refute match.active[:jetpack]
    refute match.active[:thrusting]
    assert match.active[:parachute]
  end

  def test_parachute_arms_on_ground_opens_only_during_fall_and_prevents_damage
    match = arena
    fire(match, "parachute")
    match.step
    refute match.active[:parachute_open]
    ammo = match.team[:inventory]["parachute"]
    assert_raises(Burrow::RuleError) { fire(match, "parachute") }
    assert_equal ammo, match.team[:inventory]["parachute"]
    match.active.merge!(y: 180.0, vy: -20.0)
    match.step
    refute match.active[:parachute_open]
    match.active[:vy] = 360.0
    thrust(match, 50, direction: 1)
    assert match.active[:parachute_open]
    assert_operator match.active[:vx], :>, 40
    assert_in_delta 65, match.active[:vy], 0.1
    thrust(match, 150)
    assert_equal 100, match.active[:hp]
    refute match.active[:parachute_open]
  end

  def test_teleport_rejects_occupied_solid_and_submerged_landings_then_ends_turn
    match = arena
    ammo = match.team[:inventory]["teleport"]
    [[480, 450], [300, 510], [1, 450], [300, 640]].each do |x, y|
      assert_raises(Burrow::RuleError) { fire(match, "teleport", x: x, y: y) }
      assert_equal ammo, match.team[:inventory]["teleport"]
    end
    fire(match, "teleport", x: 350, y: 490)
    assert_equal [350.0, 500.0], match.active.values_at(:x, :y)
    assert match.terrain.free_body?(match.active[:x], match.active[:y])
    assert match.grounded?(match.active)
    assert_equal "settling", match.phase
    assert_equal ammo - 1, match.team[:inventory]["teleport"]
  end

  def test_tilted_girder_becomes_walkable_ground_and_rejects_overlap
    match = arena
    ammo = match.team[:inventory]["girder"]
    assert_raises(Burrow::RuleError) { fire(match, "girder", x: 240, y: 490, rotation: 22.5) }
    assert_equal ammo, match.team[:inventory]["girder"]
    fire(match, "girder", x: 700, y: 350, rotation: 22.5)
    assert_equal "settling", match.phase
    landing = match.terrain.landing(700, 300, water: match.water)
    assert landing
    match.active.merge!(x: 670.0, y: 300.0, vx: 0.0, vy: 0.0)
    match.instance_variable_set(:@phase, "aiming")
    thrust(match, 20)
    y = match.active[:y]
    assert match.grounded?(match.active)
    thrust(match, 12, direction: 1)
    assert_operator match.active[:x], :>, 685
    assert_operator match.active[:y], :>, y
    assert match.terrain.free_body?(match.active[:x], match.active[:y])
  end

  def test_mobility_tools_recover_control_after_blast_tumbling
    match = arena
    match.active.merge!(y: 350.0, vy: 150.0, launched: true)
    fire(match, "jetpack")
    thrust(match, 14, lift: 1)
    refute match.active[:launched]
    assert_operator match.active[:fuel], :<, 150
    assert_operator match.active[:vy], :<, -180

    match = arena
    match.active.merge!(y: 200.0, vy: 300.0, launched: true)
    fire(match, "parachute")
    match.step
    refute match.active[:launched]
    assert match.active[:parachute_open]
    assert_operator match.active[:vy], :<=, 65

    match = arena
    ceiling(match)
    match.active.merge!(y: 450.0, vy: 50.0, launched: true)
    hook(match)
    refute match.active[:launched]
    length = match.active[:rope][:length]
    thrust(match, 5, lift: 1)
    assert_operator match.active[:rope][:length], :<, length
  end

  def test_every_mobility_stage_restores_deterministically_and_old_ropes_restore
    %w[shooting retracting attached jetpack parachute].each do |stage|
      match = arena
      ceiling(match) unless stage == "retracting"
      if %w[shooting retracting attached].include?(stage)
        fire(match, "rope")
        match.step(12) if stage == "retracting"
        match.step(6) if stage == "attached"
        assert_equal stage, match.active[:rope][:stage]
      else
        fire(match, stage)
      end
      restored = Burrow::Match.restore(JSON.parse(JSON.generate(match.checkpoint)))
      40.times do |i|
        if i % 6 == 0
          [match, restored].each { |m| m.command("p0", "move", direction: 1, lift: 1) }
        end
        match.step
        restored.step
      end
      assert_equal JSON.generate(match.snapshot(terrain: true)), JSON.generate(restored.snapshot(terrain: true)), stage
    end
    match = arena
    ceiling(match)
    hook(match)
    saved = JSON.parse(JSON.generate(match.checkpoint))
    saved["worms"].each do |w|
      %w[rope_use rope_airborne thrusting parachute_open].each { |k| w.delete(k) }
      w["rope"]&.delete("stage")
    end
    restored = Burrow::Match.restore(saved)
    assert_equal "attached", restored.active[:rope][:stage]
    assert restored.active[:rope_use]
    restored.step
    assert restored.active[:rope]
  end
end
