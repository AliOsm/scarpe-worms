# frozen_string_literal: true
require_relative "test_helper"

class MatchTest < Minitest::Test
  def test_turn_ownership_and_malformed_aim_cannot_spend_ammo
    match = game
    before = match.teams.first[:inventory].dup
    assert_raises(Burrow::RuleError) { match.command("p1", "fire", weapon: "dynamite") }
    assert_raises(Burrow::RuleError) { match.command("p0", "fire", weapon: "dynamite", angle: Float::NAN) }
    assert_raises(Burrow::RuleError) { match.command("p0", "fire", weapon: "rocket", power: 4) }
    assert_equal before, match.teams.first[:inventory]
    assert_empty match.projectiles
  end

  def test_hold_movement_expires_and_stays_on_surface
    match = game
    actor = match.active
    initial = actor[:x]
    5.times do
      match.command("p0", "move", direction: 1)
      match.step(6)
    end
    assert_operator actor[:x], :>, initial + 20
    match.step(35)
    settled = actor[:x]
    match.step(20)
    assert_in_delta settled, actor[:x], 0.5
    assert match.terrain.free_body?(actor[:x], actor[:y])
  end

  def test_unused_fields_cannot_inflate_the_persisted_command_log
    match = game
    junk = "x" * 20_000
    match.command("p0", "move", direction: 1, weapon: junk, backflip: junk)
    assert_equal ["direction"], match.inputs.last[:values].keys
    assert_raises(Burrow::RuleError) { match.command("p0", "jump", backflip: junk) }
    assert_equal 1, match.inputs.length
    match.command("p0", "fire", weapon: "rocket", x: junk, y: junk)
    assert_equal ["weapon"], match.inputs.last[:values].keys
    assert_operator JSON.generate(match.inputs).bytesize, :<, 300
  end

  def test_unlimited_wind_tools_remain_bounded_and_playable
    match = game("scheme" => "sandbox")
    1_100.times { match.command("p0", "fire", weapon: "wind_control") }
    assert match.wind.finite?
    assert_operator match.wind.abs, :<=, 4
    match.command("p0", "fire", weapon: "rocket", angle: -45, power: 0.5)
    match.step(620)
    assert(match.turn > 1 || match.finished?)
  end

  def test_a_charged_shot_destroys_terrain_and_hands_over_after_settling
    match = game
    before = match.terrain.checksum
    match.command("p0", "fire", weapon: "rocket", angle: 55, power: 0.5)
    assert_equal "retreat", match.phase
    assert_raises(Burrow::RuleError) { match.command("p0", "fire", weapon: "rocket") }
    600.times { match.step; break if match.turn > 1 }
    refute_equal before, match.terrain.checksum
    assert_equal "p1", match.team[:id]
    assert match.events.any? { |event| event[:kind] == "explosion" }
  end

  def test_shotgun_gets_exactly_two_shots_and_cannot_switch_mid_cartridge
    match = game
    match.command("p0", "fire", weapon: "shotgun", angle: -45)
    assert_equal "aiming", match.phase
    assert_equal 1, match.snapshot[:shots_left]
    assert_raises(Burrow::RuleError) { match.command("p0", "fire", weapon: "rocket") }
    match.command("p0", "fire", weapon: "shotgun", angle: -50)
    assert_equal "retreat", match.phase
    assert_equal 2, match.events.count { |e| e[:kind] == "beam" }
  end

  def test_water_is_lethal_and_a_surrender_can_finish_a_match
    match = game
    victim = match.worms.find { |w| w[:team] == "p1" }
    victim[:y] = match.water + 11
    match.step
    assert_equal 0, victim[:hp]
    match.surrender("p1")
    assert match.finished?
    assert_equal "p0", match.winner
  end

  def test_invalid_bridge_teleport_and_sky_support_do_not_consume_ammo
    match = game("terrain" => "cavern")
    inventory = match.team[:inventory].dup
    assert_raises(Burrow::RuleError) { match.command("p0", "fire", weapon: "teleport", x: 700, y: 700) }
    assert_raises(Burrow::RuleError) { match.command("p0", "fire", weapon: "girder", x: 2, y: 200) }
    assert_raises(Burrow::RuleError) { match.command("p0", "fire", weapon: "airstrike", x: 600, y: 300) }
    assert_equal inventory, match.team[:inventory]
  end

  def test_checkpoint_restores_an_in_flight_match_without_drift
    match = game
    match.command("p0", "fire", weapon: "cluster", angle: -40, power: 0.6, fuse: 2)
    match.step(16)
    restored = Burrow::Match.restore(JSON.parse(JSON.generate(match.checkpoint)))
    250.times { match.step; restored.step }
    assert_equal JSON.generate(match.snapshot(terrain: true)), JSON.generate(restored.snapshot(terrain: true))
  end

  def test_computer_match_plays_to_a_winner_and_is_deterministic
    first = game({"worms" => 2, "round_limit" => 3}, players: 6, bots: true)
    second = game({"worms" => 2, "round_limit" => 3}, players: 6, bots: true)
    18_000.times do
      first.step
      second.step
      break if first.finished?
    end
    assert first.finished?, "The six-team bot match did not finish"
    assert_equal first.winner, second.winner
    assert_equal first.tick, second.tick
    assert_equal first.terrain.checksum, second.terrain.checksum
    assert first.worms.all? { |w| w[:hp] >= 0 }
  end

  def test_bot_aiming_is_incremental_and_resumes_mid_search
    match = game({"worms" => 6, "terrain" => "cavern", "ammo" => {"shotgun" => 0}}, players: 6, bots: true)
    600.times do
      match.step
      break if match.instance_variable_get(:@bot_search)
    end
    plan = match.instance_variable_get(:@bot_search)
    assert plan, "Expected an incremental ballistic search"
    prior = plan["index"]
    match.step
    assert_equal prior + 4, plan["index"]
    restored = Burrow::Match.restore(JSON.parse(JSON.generate(match.checkpoint)))
    300.times { match.step; restored.step }
    assert_equal JSON.generate(match.snapshot(terrain: true)), JSON.generate(restored.snapshot(terrain: true))
  end

  def test_every_weapon_can_be_used_and_completes_its_action
    assert_equal 48, Burrow::Catalog::WEAPONS.size
    Burrow::Catalog::WEAPONS.each do |id, weapon|
      match = game("terrain" => id == "rope" ? "cavern" : "islands", "retreat_seconds" => 2)
      actor = match.active
      actor[:hp] = 60 if id == "heal"
      target = match.worms.last
      params = {weapon: id, angle: -35, power: 0.4, fuse: 2, x: target[:x], y: 170}
      params.merge!(x: 720, y: 180) if id == "girder"
      params.merge!(x: actor[:x], y: 15) if id == "rope"
      if id == "teleport"
        destination = (60..1380).step(12).find do |x|
          feet = match.terrain.landing(x, 160, water: match.water)
          feet && match.worms.all? { |w| Math.hypot(w[:x] - x, w[:y] - feet) > 32 }
        end
        params.merge!(x: destination, y: 160)
      end
      before_ammo = match.team[:inventory][id]
      match.command("p0", "fire", params)
      assert_equal before_ammo - (before_ammo > 0 ? 1 : 0), match.teams.first[:inventory][id], id
      match.command("p0", "fire", params) if id == "shotgun"
      match.step(20)
      if match.projectiles.any? { |p| p[:remote] }
        match.command("p0", "detonate") if match.active[:hp] > 0
      end
      match.step(620)
      if Burrow::Catalog::UTILITY.include?(weapon[:kind])
        assert_equal 1, match.turn, "#{id} should leave the turn available"
      else
        assert(match.turn > 1 || match.finished?, "#{id} did not finish its action")
      end
      assert match.worms.all? { |w| w[:x].finite? && w[:y].finite? }, id
    end
  end

  def test_configs_reject_unknown_keys_excess_players_and_out_of_range_values
    [{"worms" => 99}, {"gravity" => 0}, {"wind" => "fast"}, {"ammo" => {"rocket" => -2}}, {"seed" => ""}, {"cheats" => true}].each do |options|
      assert_raises(Burrow::RuleError) { Burrow::Config.new(options) }
    end
    assert_raises(Burrow::RuleError) { game({}, players: 7) }
  end

  def test_snapshot_reports_the_authoritative_retreat_countdown
    match = game("retreat_seconds" => 4)
    assert_equal 0, match.snapshot[:retreat_seconds]
    match.command("p0", "fire", weapon: "grenade", angle: -75, power: 0.3, fuse: 5)
    assert_equal "retreat", match.phase
    assert_in_delta 4, match.snapshot[:retreat_seconds], 0.1
    match.step(Burrow::TICK_RATE)
    assert_in_delta 3, match.snapshot[:retreat_seconds], 0.1
    restored = Burrow::Match.restore(JSON.parse(JSON.generate(match.checkpoint)))
    assert_equal match.snapshot[:retreat_seconds], restored.snapshot[:retreat_seconds]
    match.step(Burrow::TICK_RATE * 3)
    refute_equal "retreat", match.phase
    assert_equal 0, match.snapshot[:retreat_seconds]
  end
end
