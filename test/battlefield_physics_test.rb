# frozen_string_literal: true
require_relative "test_helper"

# Blast impulse, tumbling grubs, loose props, burning fuel and multi-step weapons.
class BattlefieldPhysicsTest < Minitest::Test
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

  def settle(match, ticks = 240)
    ticks.times do
      match.step
      break if match.worms.all? { |w| w[:hp] <= 0 || (w[:vx].abs < 1 && w[:vy].abs < 1 && !w[:launched]) }
    end
  end

  def test_blasts_throw_grubs_away_from_the_centre_and_they_tumble_to_rest
    match = arena
    victim = match.worms[1]
    start = victim[:x]
    match.send(:explode, victim[:x] - 30, victim[:y] - 6, damage: 30, radius: 40, owner: "p0")
    assert victim[:launched], "a blast launches its victim"
    assert_operator victim[:vx], :>, 80, "pushed away from a blast on its left"
    assert_operator victim[:vy], :<, -60, "and lifted off the ground"
    hp = victim[:hp]
    settle(match)
    refute victim[:launched]
    assert_operator victim[:x], :>, start + 40, "momentum carries the grub on landing"
    assert_equal hp, victim[:hp], "a blast flight lands in a tumble without fall damage"
  end

  def test_a_blast_from_below_throws_upward_and_from_above_pins_down
    match = arena
    victim = match.worms[1]
    match.send(:explode, victim[:x], victim[:y] + 4, damage: 20, radius: 30, owner: "p0")
    assert_in_delta 0, victim[:vx], 1
    assert_operator victim[:vy], :<, -200
    above = arena
    grub = above.worms[1]
    above.send(:explode, grub[:x], grub[:y] - 40, damage: 20, radius: 30, owner: "p0")
    assert_operator grub[:vy], :>, -80, "a blast overhead adds little lift"
  end

  def test_tumbling_grubs_rebound_off_walls
    match = arena
    victim = match.worms[1]
    match.terrain.bridge(victim[:x] + 40, 380, width: 20, height: 118)
    victim.merge!(vx: 260.0, vy: -60.0, launched: true)
    6.times { match.step }
    assert_operator victim[:vx], :<, 0, "the grub bounced back off the wall"
    assert_operator victim[:x], :<, victim[:x] + 40
  end

  def test_ordinary_falls_still_hurt
    match = arena
    victim = match.worms[1]
    victim.merge!(y: 200.0, vy: 0.0)
    settle(match)
    assert_operator victim[:hp], :<, 100
  end

  def test_explosions_shove_resting_bombs_and_props
    match = arena
    match.send(:projectile, Burrow::Catalog.fetch("grenade"), x: 500, y: 498, vx: 0, vy: 0, damage: 50, bounce: true, life: 150)
    grenade = match.projectiles.last
    grenade.merge!(stuck: true, support_x: 500.0, support_y: 501.0)
    match.hazards << {id: "m1", kind: "mine", x: 515.0, y: 500.0, owner: nil, armed: 0, life: 100_000, hp: 20}
    match.send(:explode, 470, 494, damage: 40, radius: 30, owner: "p0")
    refute grenade[:stuck], "the blast dislodged the resting grenade"
    assert_operator grenade[:vx], :>, 50
    mine = match.hazards.find { |h| h[:id] == "m1" }
    assert_operator mine[:vx], :>, 20, "the mine was knocked away"
    assert_operator mine[:vy], :<, 0
  end

  def test_close_mines_and_barrels_chain_after_a_short_delay_and_barrels_spill_fire
    match = arena
    match.hazards << {id: "b1", kind: "barrel", x: 520.0, y: 500.0, owner: nil, armed: 0, life: 100_000, hp: 20}
    match.hazards << {id: "m1", kind: "mine", x: 640.0, y: 500.0, owner: nil, armed: 0, life: 100_000, hp: 20}
    match.send(:explode, 515, 492, damage: 48, radius: 44, owner: "p0")
    barrel = match.hazards.find { |h| h[:id] == "b1" }
    assert barrel[:trigger], "a point-blank barrel ruptures"
    assert_operator barrel[:trigger], :>, match.tick, "chain reactions are staggered"
    30.times { match.step }
    refute match.hazards.any? { |h| h[:id] == "b1" }
    assert_operator match.events.count { |e| e[:kind] == "explosion" }, :>=, 2
    assert match.hazards.any? { |h| h[:kind] == "flame" }, "spilled fuel burns"
  end

  def test_flames_fall_settle_scald_once_per_check_and_hold_the_turn
    match = arena
    victim = match.worms[1]
    6.times { |i| match.send(:flame, victim[:x] + i - 3, 300, "p0", vy: 0) }
    40.times { match.step }
    flames = match.hazards.select { |h| h[:kind] == "flame" }
    assert flames.all? { |h| (h[:y] - 500).abs < 3 }, "flames came to rest on the ground"
    hurt = 100 - victim[:hp]
    assert_operator hurt, :>, 0
    assert_operator hurt, :<=, 3 * 2, "six flames scald like one"
    match.send(:resolve_turn, retreat: false)
    turn = match.turn
    match.step(60)
    assert_equal turn, match.turn, "the turn waits while fire burns"
    match.step(200)
    assert_operator match.turn, :>, turn
  end

  def test_grenades_roll_down_steep_slopes_and_settle_on_level_ground
    match = arena
    # A 45-degree ramp rising to the left of the level floor.
    (0..120).step(2) { |d| match.terrain.bridge(400 - d, 500 - d, width: 4, height: d + 2) }
    grenade = launch(match, "grenade", fuse: 5)
    grenade.merge!(x: 340.0, y: 430.0, vx: 0.0, vy: 0.0, age: 10)
    match.step(90)
    assert_operator grenade[:x], :>, 380, "it rolled downhill"
    assert grenade[:stuck], "and rests on the level floor"
  end

  def test_air_strikes_approach_from_the_chosen_side_and_land_across_the_target
    [-1, 1].each do |side|
      match = arena
      target = 900
      match.command("p0", "fire", {weapon: "airstrike", x: target, y: 480, direction: side})
      bombs = match.projectiles
      assert_equal 5, bombs.size
      assert bombs.all? { |p| p[:vx] * side > 0 }, "bombers fly in from #{side}"
      landings = []
      120.times do
        before = match.projectiles.map { |p| p.values_at(:id, :x) }
        match.step
        gone = before.reject { |id, _| match.projectiles.any? { |p| p[:id] == id } }
        landings.concat(gone.map(&:last))
      end
      assert_equal 5, landings.size
      assert_in_delta target, landings.sum / landings.size, 60
    end
  end

  def test_girders_can_be_tilted_and_must_fit
    match = arena
    match.command("p0", "fire", {weapon: "girder", x: 700, y: 360, rotation: 45})
    assert match.terrain.solid?(700, 366)
    assert match.terrain.solid?(700 + 40, 366 + 40), "the beam runs diagonally"
    refute match.terrain.solid?(700 + 40, 366), "not horizontally"
    blocked = arena
    blocked.terrain.bridge(730, 388, width: 20, height: 12)
    assert_raises(Burrow::RuleError) { blocked.command("p0", "fire", {weapon: "girder", x: 700, y: 360, rotation: 45}) }
    assert_equal Burrow::Catalog.fetch("girder")[:ammo], blocked.team[:inventory]["girder"], "a refused girder is not spent"
  end

  def test_fruit_salad_splits_on_command
    match = arena(scheme: "sandbox")
    banana = launch(match, "banana", angle: -60, power: 0.6)
    assert banana[:remote]
    match.step(10)
    match.command("p0", "activate")
    match.step
    refute_includes match.projectiles, banana
    assert_equal 6, match.projectiles.count { |p| p[:fragment] && p[:weapon] == "banana" }
  end

  def test_homing_cruise_follows_launch_power_and_the_motor_burns_out
    [0.2, 1.0].map do |power|
      match = arena
      p = launch(match, "homing", power: power, x: 1300, y: 100)
      p.merge!(x: 300.0, y: 300.0, vx: 200.0, vy: 0.0, age: 20)
      match.step(90)
      Math.hypot(p[:vx], p[:vy])
    end => [slow, fast]
    assert_operator fast, :>, slow + 150
    match = arena
    p = launch(match, "homing", x: 1300, y: 100)
    p.merge!(x: 300.0, y: 200.0, vx: 300.0, vy: 0.0, age: Burrow::Physics::HOMING_TICKS + 1)
    match.step(10)
    assert_operator p[:vy], :>, 0, "after burnout the rocket falls"
  end

  def test_blasts_char_a_rim_but_tools_dig_clean_tunnels
    terrain = arena.terrain
    terrain.carve(600, 520, 30)
    refute terrain.solid?(600, 520)
    assert_equal 4, terrain.data.getbyte(((520 + 34) / 2) * terrain.cols + 300), "a charred rim below the crater"
    assert terrain.solid?(600, 554), "charred soil is still ground"
    terrain.carve(900, 560, 20, scorch: false)
    assert_equal 1, terrain.data.getbyte(((560 + 24) / 2) * terrain.cols + 450)
  end

  def test_landing_from_any_pixel_finds_the_same_ground
    terrain = arena.terrain
    terrain.bridge(700, 461, width: 6, height: 39) # a one-cell step beside the probe
    assert_equal [460, 460], [terrain.landing(706, 401, water: 624), terrain.landing(706, 400, water: 624)]
  end

  def test_cavern_crates_parachute_below_the_roof
    match = game({"terrain" => "cavern", "crates" => true})
    match.send(:drop_crate)
    crate = match.hazards.find { |h| h[:kind] == "crate" }
    assert crate[:chute]
    refute match.terrain.solid?(crate[:x], crate[:y]), "the crate starts in open air"
  end

  def test_starting_props_rest_where_placed_and_mines_start_clear_of_grubs
    %w[islands archipelago cavern].each do |terrain|
      6.times do |seed|
        match = game({"terrain" => terrain, "seed" => "props-#{seed}", "mines" => 6, "barrels" => 4}, players: 3)
        placed = match.hazards.map { |h| [h, h[:x], h[:y]] }
        placed.each do |h, x, y|
          assert match.terrain.solid?(x, y + 1), "#{terrain} #{h[:kind]} spawned without ground beneath its centre"
          next unless h[:kind] == "mine"
          assert match.worms.all? { |w| Math.hypot(w[:x] - x, w[:y] - y) >= Burrow::Physics::MINE_PROXIMITY * 2 }
        end
        150.times { match.step }
        placed.each { |h, x, y| assert_in_delta 0, Math.hypot(h[:x] - x, h[:y] - y), 1, "#{terrain} #{h[:kind]} slid off its spawn" }
        refute match.events.any? { |e| e[:kind] == "mine_trigger" }, "#{terrain}: a starting mine went off on its own"
      end
    end
  end

  def test_new_physics_state_survives_a_checkpoint
    match = arena
    victim = match.worms[1]
    match.send(:explode, victim[:x] - 30, victim[:y] - 6, damage: 30, radius: 40, owner: "p0")
    match.hazards << {id: "b1", kind: "barrel", x: 520.0, y: 500.0, owner: nil, armed: 0, life: 100_000, hp: 20}
    match.send(:explode, 515, 492, damage: 48, radius: 44, owner: "p0")
    restored = Burrow::Match.restore(JSON.parse(JSON.generate(match.checkpoint)))
    90.times { match.step; restored.step }
    assert_equal JSON.generate(match.snapshot(terrain: true)), JSON.generate(restored.snapshot(terrain: true))
  end

  def test_gravestones_fall_fly_from_blasts_and_sink_without_holding_the_turn
    match = arena
    victim = match.worms[1]
    victim[:y] = 380.0
    match.send(:kill, victim, "blast")
    45.times { match.step }
    assert_in_delta 500, victim[:y], 2, "a grave drops onto the ground below"
    assert_equal 0, victim[:hp]
    match.send(:explode, victim[:x] - 30, victim[:y] - 6, damage: 30, radius: 40, owner: "p0")
    assert_operator victim[:vx], :>, 60, "a later blast throws the grave"
    assert_operator victim[:vy], :<, 0
    assert_operator match.worms[0][:hp], :>, 0, "graves cannot be hurt again or hurt anyone"
    match.instance_variable_set(:@phase, "settling")
    match.instance_variable_set(:@settle_limit, match.tick + 1_000)
    match.instance_variable_set(:@quiet_ticks, 0)
    3.times { match.step }
    assert_operator victim[:vx].abs, :>, 4, "the grave is still flying"
    assert_equal 3, match.instance_variable_get(:@quiet_ticks), "graves never delay the next turn"

    victim.merge!(x: 760.0, y: 500.0, vx: 0.0, vy: 0.0)
    match.instance_variable_set(:@water, 494.0)
    match.step
    assert victim[:sunk], "rising water claims the grave"
    assert_equal 0, match.events.count { |event| event[:kind] == "splash" }, "a submerged resting grave makes no splash"
    assert match.worms.all? { |w| w[:id] == victim[:id] || w[:hp] > 0 }
  end

  def test_drowned_grubs_leave_no_grave
    match = arena
    victim = match.worms[1]
    victim.merge!(y: match.water + 12, vy: 120.0)
    match.step
    assert_equal 0, victim[:hp]
    assert victim[:sunk]
    assert_equal 1, match.events.count { |event| event[:kind] == "splash" && event[:worm] == victim[:id] }
    assert_equal 0, victim[:vy]
    restored = Burrow::Match.restore(JSON.parse(JSON.generate(match.checkpoint)))
    5.times { match.step; restored.step }
    assert_equal JSON.generate(match.snapshot), JSON.generate(restored.snapshot)
  end

  private

  def launch(match, id, **values)
    match.command("p0", "fire", {weapon: id, angle: -30, power: 0.5, fuse: 3}.merge(values))
    match.projectiles.first
  end
end
