# frozen_string_literal: true
require_relative "test_helper"
require_relative "../lib/burrow/client/audio"
require_relative "../lib/burrow/client/timeline"
require_relative "../lib/burrow/client/camera"
require_relative "../lib/burrow/client/theme"
require_relative "../lib/burrow/client/sprites"

# Behavioral contracts for launched, thrown and air-support ordnance. Controlled
# terrain makes impact, fuse and turn timing independent of generated maps.
class WeaponsMunitionsTest < Minitest::Test
  MUNITIONS = %w[rocket mortar homing grenade cluster sticky dynamite mega_bomb banana
    holy_bomb poison airstrike mine_strike napalm meteor earthquake].freeze

  class AudioRecorder < Burrow::Client::Audio
    attr_reader :heard
    def initialize = @heard = []
    def play(cue, **options) = @heard << [cue, options]
  end

  def test_charge_changes_range_but_mortar_keeps_its_fixed_launch
    %w[rocket grenade sticky mega_bomb banana holy_bomb poison homing mortar].each do |id|
      speeds = [0.05, 1.0].map do |power|
        match = arena
        shot = fire(match, id, power: power)
        Math.hypot(shot[:vx], shot[:vy])
      end
      if id == "mortar"
        assert_in_delta speeds.first, speeds.last, 0.001, id
      else
        assert_operator speeds.last, :>, speeds.first * 3, "#{id} responds to charge"
      end
    end
  end

  def test_wind_bends_rockets_but_not_thrown_bombs_or_mortar
    %w[rocket homing grenade cluster sticky mega_bomb banana holy_bomb poison mortar].each do |id|
      positions = [-2.0, 2.0].map do |wind|
        match = arena
        match.instance_variable_set(:@wind, wind)
        shot = fire(match, id, angle: -90, power: 0.5)
        match.step(12) # Before the homing motor takes over.
        shot[:x]
      end
      if %w[rocket homing].include?(id)
        assert_operator positions.last - positions.first, :>, 10, id
      else
        assert_in_delta positions.first, positions.last, 0.001, id
      end
    end
  end

  def test_homing_requires_a_valid_destination_before_spending_ammo
    match = arena
    before = match.team[:inventory]["homing"]
    [{}, {x: Float::NAN, y: 200}, {x: 900, y: -1}].each do |point|
      assert_raises(Burrow::RuleError) { match.command("p0", "fire", {weapon: "homing"}.merge(point)) }
      assert_equal before, match.team[:inventory]["homing"]
      assert_empty match.projectiles
      assert_equal "aiming", match.phase
    end
  end

  def test_homing_motor_turns_gradually_then_returns_to_ballistic_flight
    match = arena
    shot = fire(match, "homing", x: 300, y: 100, power: 0.6)
    shot.merge!(x: 900.0, y: 180.0, vx: 350.0, vy: 0.0, age: 15)
    match.step
    heading = Math.atan2(shot[:vy], shot[:vx])
    assert_operator heading, :<, 0
    assert_operator heading.abs, :<=, 0.09, "the motor cannot snap through a reversal"
    assert_operator Math.hypot(shot[:vx], shot[:vy]), :>=, 350
    assert_equal [300.0, 100.0], shot.values_at(:target_x, :target_y)
    shot.merge!(x: 900.0, y: 180.0, vx: 350.0, vy: 0.0, age: Burrow::Physics::HOMING_TICKS)
    match.step(4)
    assert_operator shot[:vy], :>, 0, "an exhausted motor no longer follows the high target"
  end

  def test_adjustable_fuses_survive_contacts_and_expire_at_the_selected_tick
    %w[grenade cluster sticky mega_bomb banana poison].each do |id|
      match = arena
      shot = fire(match, id, fuse: 1)
      shot.merge!(x: 700.0, y: 496.0, vx: 35.0, vy: 120.0)
      match.step(29)
      assert_includes match.projectiles, shot, "#{id} keeps its fuse after ground contact"
      match.step
      refute_includes match.projectiles, shot, "#{id} expires at one second"
      assert match.events.any? { |event| %w[explosion gas].include?(event[:kind]) }, id
    end
  end

  def test_heavy_bombs_rebound_less_than_fruit_and_grenades
    rises = %w[banana grenade mega_bomb holy_bomb].to_h do |id|
      match = arena
      shot = fire(match, id, fuse: 5)
      shot.merge!(x: 700.0, y: 497.0, vx: 0.0, vy: 180.0)
      match.step
      assert_operator shot[:vy], :<, 0, "#{id} rebounds off the floor"
      assert_operator shot[:vy].abs, :<, 190, "#{id} loses energy at impact"
      [id, -shot[:vy]]
    end
    assert_operator rises["banana"], :>, rises["grenade"]
    assert_operator rises["grenade"], :>, rises["mega_bomb"]
    assert_operator rises["mega_bomb"], :>, rises["holy_bomb"]
  end

  def test_sticky_bomb_releases_when_its_attached_grub_dies
    match = arena
    victim = match.worms[1]
    shot = fire(match, "sticky", fuse: 5)
    shot.merge!(x: victim[:x] - 17, y: victim[:y] - 10, vx: 200.0, vy: 0.0)
    match.step
    assert_equal victim[:id], shot[:attached_to]
    victim[:hp] = 0
    before = shot[:y]
    match.step(3)
    assert_nil shot[:attached_to]
    assert_operator shot[:y], :>, before
    assert_includes match.projectiles, shot
  end

  def test_dynamite_uses_its_fixed_fuse_and_leaves_the_owner_free_to_retreat
    match = arena(retreat_seconds: 4)
    shot = fire(match, "dynamite", fuse: 1, power: 1)
    assert_equal "retreat", match.phase
    assert_operator (shot[:x] - match.active[:x]).abs, :<, 25
    start = match.active[:x]
    3.times do
      match.command("p0", "move", direction: -1)
      match.step(10)
    end
    assert_operator match.active[:x], :<, start - 20
    assert_includes match.projectiles, shot
    assert_nil shot[:attached_to], "a placed charge must not follow its retreating owner"
    match.step(89)
    assert_includes match.projectiles, shot
    match.step
    refute_includes match.projectiles, shot
    assert match.events.any? { |event| event[:kind] == "explosion" && event[:style] == "dynamite" }
  end

  def test_dynamite_cannot_be_placed_through_a_wall_beside_the_owner
    match = arena
    wall = match.active[:x] + 10
    match.terrain.bridge(wall, 460, width: 2, height: 40)
    shot = fire(match, "dynamite")
    assert_operator shot[:x], :<, wall
    refute match.terrain.solid?(shot[:x], shot[:y])
    match.step(8)
    assert_operator shot[:x], :<, wall
    assert shot[:stuck], "the charge rests against the near face of the wall"
    assert_nil shot[:attached_to], "the owner can retreat without carrying the charge"
  end

  def test_sticky_surface_contact_takes_precedence_over_a_body_behind_the_wall
    match = arena
    match.terrain.bridge(600, 450, width: 0, height: 50)
    victim = match.worms[1]
    victim[:x] = 612.0
    shot = fire(match, "sticky", fuse: 5)
    shot.merge!(x: 598.8, y: 490.0, vx: 180.0, vy: 0.0)
    match.step
    assert shot[:stuck]
    assert_nil shot[:attached_to]
    assert_operator shot[:x], :<, 600
    assert match.terrain.solid?(shot[:support_x], shot[:support_y])
  end

  def test_choir_bomb_keeps_falling_after_its_fuse_and_sings_once_before_blasting
    match = arena
    shot = fire(match, "holy_bomb", fuse: 1)
    shot.merge!(x: 700.0, y: 300.0, vx: 0.0, vy: 50.0, age: 149, life: 1)
    match.step(3)
    assert_operator shot[:y], :>, 303, "expiry must not freeze an airborne choir bomb"
    assert_includes match.projectiles, shot
    assert_empty match.events.select { |event| event[:kind] == "explosion" }
    shot.merge!(x: 700.0, y: 498.0, vx: 0.0, vy: 0.0, stuck: true, support_x: 700, support_y: 500)
    match.step
    assert_equal "choir", shot[:stage]
    assert_equal 1, match.events.count { |event| event[:kind] == "choir" }
    match.step(8)
    assert_includes match.projectiles, shot, "the chord is a visible warning before the blast"
    match.step(20)
    refute_includes match.projectiles, shot
    assert_equal 1, match.events.count { |event| event[:kind] == "choir" }
    assert_equal 1, match.events.count { |event| event[:kind] == "explosion" && event[:style] == "holy_bomb" }
  end

  def test_choir_warning_resumes_identically_after_checkpoint_and_support_loss
    match = arena
    shot = fire(match, "holy_bomb")
    shot.merge!(x: 700.0, y: 498.0, vx: 0.0, vy: 0.0, age: 149, life: 1,
      stuck: true, support_x: 700, support_y: 500)
    match.step
    assert_equal "choir", shot[:stage]
    match.terrain.carve(700, 500, 40)
    recovered = restore(match)
    25.times { match.step; recovered.step }
    assert_same_state match, recovered
    assert_equal 1, match.events.count { |event| event[:kind] == "choir" }
    blast = match.events.find { |event| event[:kind] == "explosion" && event[:style] == "holy_bomb" }
    assert blast
    assert_operator blast[:y], :>, 498, "the warning does not pin the bomb above destroyed terrain"
  end

  def test_fragment_weapons_make_only_one_generation_and_preserve_boosted_damage
    {"mortar" => 5, "cluster" => 5, "banana" => 6}.each do |id, count|
      match = arena
      match.command("p0", "fire", weapon: "double_damage")
      parent = fire(match, id, fuse: 1)
      parent.merge!(x: 700.0, y: 200.0, vx: 120.0, vy: 0.0, life: 1)
      match.step
      fragments = match.projectiles.dup
      assert_equal count, fragments.size, id
      assert fragments.all? { |shot| shot[:fragment] && shot[:weapon] == id }, id
      assert fragments.all? { |shot| shot[:stage] == "fragment" }, "#{id} has distinct in-flight art"
      assert_operator fragments.map { |shot| shot[:vx] }.sum, :>, 0, "#{id} keeps some parent momentum"
      assert fragments.all? { |shot| shot[:damage] > (id == "banana" ? 45 : id == "mortar" ? 15 : 24) }, id
      150.times { match.step; break if match.projectiles.empty? }
      assert_empty match.projectiles, "#{id} fragments cannot fragment recursively"
      assert_equal count + 1, match.events.count { |event| event[:kind] == "explosion" && event[:style] == id }, id
    end
  end

  def test_banana_split_is_owner_only_and_does_not_spend_another_round
    match = arena
    parent = fire(match, "banana", angle: -80, power: 0.6, fuse: 5)
    ammo = match.team[:inventory]["banana"]
    match.step(8)
    assert_raises(Burrow::RuleError) { match.command("p1", "activate") }
    assert_includes match.projectiles, parent
    match.command("p0", "activate")
    recovered = restore(match)
    match.step
    recovered.step
    assert_equal ammo, match.teams.first[:inventory]["banana"]
    assert_equal 6, match.projectiles.count { |shot| shot[:fragment] }
    refute_includes match.projectiles, parent
    assert_raises(Burrow::RuleError) { match.command("p0", "activate") }
    assert_same_state match, recovered
  end

  def test_poison_canister_cloud_affects_exposed_grubs_without_carving_ground
    match = arena
    victim = match.worms[1]
    parent = fire(match, "poison", fuse: 1)
    parent.merge!(x: victim[:x], y: victim[:y] - 10, vx: 0.0, vy: 0.0, life: 1)
    checksum = match.terrain.checksum
    match.step(15)
    assert victim[:poisoned]
    assert_equal 200, victim[:hp], "poison starts a status effect rather than a blast"
    assert_equal checksum, match.terrain.checksum
    assert_equal 1, match.hazards.count { |hazard| hazard[:kind] == "gas" }
    match.step(180)
    refute match.hazards.any? { |hazard| hazard[:kind] == "gas" }
  end

  def test_strike_releases_progress_from_the_chosen_side_and_hits_across_the_target
    [-1, 1].each do |side|
      match = arena
      fire(match, "airstrike", x: 900, y: 500, direction: side)
      assert_empty match.snapshot[:projectiles], "the aircraft approaches before its first release"
      strike = match.events.find { |event| event[:kind] == "strike" }
      assert strike, "the client needs an authoritative aircraft pass"
      assert_equal side, strike[:side]
      assert_operator strike[:vx] * side, :>, 0
      releases = []
      seen = []
      150.times do
        match.step
        match.snapshot[:projectiles].each do |shot|
          next if seen.include?(shot[:id])
          seen << shot[:id]
          releases << [match.tick, shot[:x]]
        end
      end
      assert_equal 5, releases.size
      assert releases.each_cons(2).all? { |a, b| b[0] > a[0] && (b[1] - a[1]) * side > 0 },
        "releases follow the aircraft instead of appearing simultaneously"
      hits = match.events.select { |event| event[:kind] == "explosion" && event[:style] == "airstrike" }
      assert_equal 5, hits.size
      assert_in_delta 900, hits.sum { |event| event[:x] }.fdiv(hits.size), 35
      assert_operator hits.map { |event| event[:x] }.minmax.then { |a, b| b - a }, :>, 130
    end
  end

  def test_low_gravity_strikes_enter_from_beyond_the_map_and_reach_edge_targets
    [[1, 100], [-1, 1340]].each do |side, target|
      match = arena(gravity: 0.4)
      # Keep this accuracy check independent of interception by a grub.
      match.worms.each_with_index { |worm, index| worm[:x] = 450.0 + index * 140 }
      fire(match, "airstrike", x: target, y: 500, direction: side)
      assert match.projectiles.any? { |shot| shot[:x] < -80 || shot[:x] > match.world_width + 80 },
        "the bomber releases outside the map to reach this target"
      match.step(190)
      hits = match.events.select { |event| event[:kind] == "explosion" && event[:style] == "airstrike" }
      assert_equal 5, hits.size
      assert_in_delta target, hits.sum { |event| event[:x] }.fdiv(hits.size), 25
    end
  end

  def test_rain_check_mines_persist_and_only_trigger_after_their_arming_delay
    match = arena
    fire(match, "mine_strike", x: 900, y: 500, direction: -1)
    150.times { match.step; break if match.projectiles.empty? }
    mines = match.hazards.select { |hazard| hazard[:kind] == "mine" }
    assert_equal 5, mines.size
    assert_empty match.events.select { |event| event[:kind] == "explosion" }
    # Approach the newest mine while its original arming delay is still running.
    mine = mines.max_by { |hazard| hazard[:armed] }
    assert_operator mine[:armed], :>, match.tick
    victim = match.worms[1]
    victim.merge!(x: mine[:x], y: 500.0, vx: 0.0, vy: 0.0)
    match.step(mine[:armed] - match.tick - 1)
    assert_nil mine[:trigger]
    match.step
    assert_operator mine[:trigger], :>, match.tick
    recovered = restore(match)
    20.times { match.step; recovered.step }
    refute_includes match.hazards, mine
    assert match.events.any? { |event| event[:kind] == "explosion" && event[:style] == "mine" }
    assert_same_state match, recovered
  end

  def test_napalm_spills_bounded_fire_and_keeps_the_turn_until_it_burns_out
    match = arena
    turn = match.turn
    fire(match, "napalm", x: 900, y: 500)
    saw_flames = false
    450.times do
      match.step
      flames = match.hazards.count { |hazard| hazard[:kind] == "flame" }
      assert_operator flames, :<=, 60
      if flames > 0
        saw_flames = true
        assert_equal turn, match.turn, "burning napalm is still part of this action"
      end
      break if match.turn > turn
    end
    assert saw_flames
    assert_operator match.turn, :>, turn
    assert_empty match.projectiles
    refute match.hazards.any? { |hazard| hazard[:kind] == "flame" }
  end

  def test_meteors_are_staggered_seeded_and_all_reach_the_battlefield
    match = arena
    fire(match, "meteor")
    assert_equal 6, match.projectiles.size
    assert_operator match.snapshot[:projectiles].size, :<, 6
    recovered = restore(match)
    180.times { match.step; recovered.step }
    hits = match.events.select { |event| event[:kind] == "explosion" && event[:style] == "meteor" }
    assert_equal 6, hits.size
    assert hits.all? { |hit| hit[:x].between?(0, match.world_width) }
    assert_operator hits.map { |hit| hit[:x] }.minmax.then { |a, b| b - a }, :>, 150
    assert_same_state match, recovered
  end

  def test_a_meteor_aimed_near_the_edge_does_not_drift_out_before_impact
    match = arena
    match.instance_variable_set(:@rng, Burrow::RandomStream.new(1))
    fire(match, "meteor")
    match.step(180)
    hits = match.events.select { |event| event[:kind] == "explosion" && event[:style] == "meteor" }
    assert_equal 6, hits.size, "the shower must preserve its six intended impacts at the map edges"
    assert hits.all? { |hit| hit[:x].between?(0, match.world_width) }
  end

  def test_quake_respects_frozen_grubs_and_preserves_terrain
    match = arena
    frozen = match.worms.last
    frozen[:frozen] = true
    before = match.worms.to_h { |worm| [worm[:id], worm.slice(:x, :y, :hp)] }
    checksum = match.terrain.checksum
    fire(match, "earthquake")
    assert_equal [0.0, 0.0], frozen.values_at(:vx, :vy)
    assert_equal before[frozen[:id]][:hp], frozen[:hp]
    match.worms.reject { |worm| worm[:frozen] }.each do |worm|
      assert worm[:launched]
      assert_operator worm[:vy], :<, 0
      assert_operator worm[:vx].abs, :<=, 210
      assert_operator worm[:hp], :<, before[worm[:id]][:hp]
    end
    assert_equal checksum, match.terrain.checksum
    assert_equal 1, match.events.count { |event| event[:kind] == "quake" }
    recovered = restore(match)
    90.times { match.step; recovered.step }
    assert_same_state match, recovered
  end

  def test_quake_dislodges_loose_props_without_prematurely_detonating_them
    match = arena
    match.hazards << {id: "quake-mine", kind: "mine", x: 700.0, y: 500.0,
      owner: "p0", life: 100_000, armed: 0, hp: 20}
    match.hazards << {id: "quake-barrel", kind: "barrel", x: 900.0, y: 500.0,
      owner: "p0", life: 100_000, armed: 0, hp: 20}
    fire(match, "earthquake")
    match.hazards.each do |hazard|
      assert_operator hazard[:vy], :<, 0
      assert_operator hazard[:vx].abs, :<, 160
      assert_nil hazard[:trigger], "the tremor moves props without igniting them"
    end
    match.step(4)
    assert match.hazards.all? { |hazard| hazard[:y] < 495 }
    assert_empty match.events.select { |event| event[:kind] == "explosion" }
  end

  def test_every_munition_finishes_without_leaving_an_active_action_behind
    MUNITIONS.each do |id|
      match = arena
      turn = match.turn
      fire(match, id, angle: -55, power: 0.4, x: 900, y: 500)
      539.times { match.step; break if match.turn > turn || match.finished? }
      assert_operator match.turn, :>, turn, "#{id} finishes before the emergency settle timeout"
      assert_empty match.projectiles, id
      refute match.hazards.any? { |hazard| hazard[:kind] == "flame" || hazard[:trigger] }, id
    end
  end

  def test_in_flight_ordnance_and_pending_releases_restore_deterministically
    %w[rocket mortar homing grenade cluster sticky dynamite mega_bomb banana poison airstrike mine_strike napalm].each do |id|
      match = arena
      fire(match, id, angle: -65, power: 0.35)
      match.step(15)
      recovered = restore(match)
      220.times { match.step; recovered.step }
      assert_same_state match, recovered, id
    end
  end

  def test_legacy_homing_and_expired_choir_checkpoints_have_safe_defaults
    %w[homing holy_bomb].each do |id|
      match = arena
      shot = fire(match, id)
      shot.merge!(x: 700.0, y: 200.0, vx: 0.0, vy: 80.0)
      shot.merge!(age: 151, life: 1) if id == "holy_bomb"
      saved = JSON.parse(JSON.generate(match.checkpoint))
      saved["projectiles"].each { |row| %w[cruise stage choir_at].each { |field| row.delete(field) } }
      # Old histories ended at life; age and stuck were not transmitted yet.
      saved["shot_tracks"].each_value do |track|
        track.delete("fragment")
        track["samples"].each { |sample| sample.slice!(8..) }
      end
      recovered = Burrow::Match.restore(saved)
      recovered.step(3)
      assert_operator recovered.projectiles.first[:y], :>, 200, "#{id} keeps simulating a legacy save"
      400.times { recovered.step; break if recovered.projectiles.empty? }
      assert_empty recovered.projectiles, id
    end
  end

  def test_all_munition_launch_predictions_match_the_real_host_reports
    MUNITIONS.each do |id|
      match = arena
      audio = AudioRecorder.new
      state = JSON.parse(JSON.generate(match.snapshot))
      audio.local_action("fire", values: {weapon: id}, state: state,
        player: "p0", sequence: 7, match_id: "ordnance")
      cue = if id == "dynamite"
        "tick"
      elsif id == "earthquake"
        "explosion-heavy"
      elsif %w[rocket mortar homing airstrike mine_strike napalm meteor].include?(id)
        "launch"
      else
        "throw"
      end
      assert_equal [cue], audio.heard.map(&:first), id
      assert audio.heard.first.last[:immediate], id
      event_cursor = match.events.last[:id]
      fire(match, id)
      reports = match.events.select { |event| event[:id] > event_cursor && %w[fire strike quake].include?(event[:kind]) }
      receipt = {"match" => "ordnance", "player" => "p0", "seq" => 7}
      reports.each do |event|
        audio.event(JSON.parse(JSON.generate(event)).merge("input" => receipt))
      end
      assert_equal [cue], audio.heard.map(&:first), "#{id} must not repeat its predicted sound at acknowledgement"
    end
  end

  def test_banana_split_prediction_matches_activation_and_keeps_the_later_blast
    match = arena
    fire(match, "banana", angle: -80, fuse: 5)
    match.step(8)
    audio = AudioRecorder.new
    state = JSON.parse(JSON.generate(match.snapshot))
    audio.local_action("activate", values: {}, state: state,
      player: "p0", sequence: 8, match_id: "ordnance")
    assert_equal ["impact"], audio.heard.map(&:first)
    match.command("p0", "activate")
    report = JSON.parse(JSON.generate(match.events.last))
    audio.event(report.merge("input" => {"match" => "ordnance", "player" => "p0", "seq" => 8}))
    assert_equal ["impact"], audio.heard.map(&:first), "the split acknowledgement uses the same prediction"
    match.step
    explosion = match.events.find { |event| event[:kind] == "explosion" && event[:style] == "banana" }
    audio.event(JSON.parse(JSON.generate(explosion)))
    assert_equal %w[impact explosion], audio.heard.map(&:first)
  end

  def test_choir_cloud_and_mine_feedback_use_their_distinct_existing_cues
    audio = AudioRecorder.new
    [{"kind" => "choir"}, {"kind" => "explosion", "style" => "holy_bomb", "radius" => 84},
      {"kind" => "gas", "weapon" => "poison"}, {"kind" => "mine_land"}].each { |event| audio.event(event) }
    assert_equal %w[pickup explosion-heavy impact impact], audio.heard.map(&:first)
  end

  def test_fragment_identity_and_animation_age_survive_host_timeline_playback
    %w[mortar cluster banana].each do |id|
      match = arena
      parent = fire(match, id)
      parent.merge!(x: 700.0, y: 200.0, life: 1)
      match.step(9)
      timeline = Burrow::Client::Timeline.new
      timeline.accept(JSON.parse(JSON.generate(match.snapshot)), now: 10)
      view = timeline.sample(now: 10)
      fragments = view["projectiles"]
      assert_equal id == "banana" ? 6 : 5, fragments.size
      fragments.each do |shot|
        assert shot["fragment"], "#{id} must render its small secondary sprite"
        assert_equal "fragment", shot["stage"]
        assert_equal "p0", shot["owner"]
        assert_operator shot["age"], :>, 0
        assert_operator shot["age"], :<, match.projectiles.first[:age]
        assert_operator shot["from"], :>, 0
        look = Burrow::Client::Sprites.projectile(shot, timeline.tick)
        parent_look = Burrow::Client::Sprites.projectile(shot.merge("fragment" => false), timeline.tick)
        refute_equal parent_look.path, look.path, "#{id} does not recycle the parent silhouette"
        assert_operator look.width, :<, parent_look.width
        assert File.file?(look.path), look.path
      end
    end
  end

  def test_pending_strikes_do_not_appear_in_playback_before_their_release
    match = arena
    fire(match, "airstrike")
    first_release = match.projectiles.map { |shot| shot[:delay] }.min
    match.step(first_release - 1)
    timeline = Burrow::Client::Timeline.new
    timeline.accept(JSON.parse(JSON.generate(match.snapshot)), now: 10)
    assert_empty timeline.sample(now: 10)["projectiles"]
    match.step(6)
    timeline.accept(JSON.parse(JSON.generate(match.snapshot)), now: 10.2)
    view = timeline.sample(now: 10.2)
    assert_equal 1, view["projectiles"].size
    shot = view["projectiles"].first
    assert_equal first_release, shot["from"]
    assert_operator shot["age"], :<, 6, "animation starts when this bomb is released"
  end

  def test_timeline_reads_legacy_samples_and_a_checkpoint_with_mixed_sample_lengths
    match = arena
    fire(match, "grenade", angle: -85, fuse: 5)
    match.step(10)
    saved = JSON.parse(JSON.generate(match.checkpoint))
    saved["shot_tracks"].each_value do |track|
      track.delete("fragment")
      track["samples"].each { |sample| sample.slice!(8..) }
    end
    recovered = Burrow::Match.restore(saved)
    [0, 5].each do |ticks|
      match.step(ticks)
      recovered.step(ticks)
      views = [match, recovered].map do |source|
        timeline = Burrow::Client::Timeline.new
        timeline.accept(JSON.parse(JSON.generate(source.snapshot)), now: 10)
        timeline.sample(now: 10)["projectiles"].first
      end
      current, legacy = views
      assert legacy["fused"], "the old fused badge remains available"
      assert_equal "p0", legacy["owner"]
      %w[x y vx vy age life].each do |field|
        assert_in_delta current[field], legacy[field], 0.001, "legacy #{field} after #{ticks} restored ticks"
      end
    end
  end

  def test_camera_shake_is_bounded_decays_and_does_not_move_the_canonical_camera
    camera = Burrow::Client::Camera.new(4800, 1600)
    camera.navigate(2400, 900)
    canonical = [camera.x, camera.y, camera.zoom, camera.following, camera.overview?]
    20.times { camera.shake(100, duration: 100, now: 10) }
    early, late = [], []
    80.times do |index|
      camera.update_shake(now: 10 + index / 100.0)
      amplitude = Math.hypot(camera.shake_x, camera.shake_y)
      early << amplitude if index < 20
      late << amplitude if index >= 70
      assert_operator camera.shake_x.abs, :<=, 8
      assert_operator camera.shake_y.abs, :<=, 4.4
      point = camera.world(*camera.screen(2300, 850))
      assert_in_delta 2300, point[0], 0.001
      assert_in_delta 850, point[1], 0.001
    end
    assert_operator early.max, :>, 1, "the shake is visible when enabled"
    assert_operator late.max, :<, early.max / 10, "the final offsets fade away"
    camera.update_shake(now: 11)
    assert_equal [0.0, 0.0], [camera.shake_x, camera.shake_y]
    assert_equal canonical, [camera.x, camera.y, camera.zoom, camera.following, camera.overview?]
  end

  def test_reduced_motion_prevents_shake_and_cancels_an_active_envelope
    camera = Burrow::Client::Camera.new(4800, 1600)
    camera.shake(8, duration: 0.8, now: 10, motion: false)
    camera.update_shake(now: 10.05)
    assert_equal [0.0, 0.0], [camera.shake_x, camera.shake_y]
    camera.shake(8, duration: 0.8, now: 11)
    camera.update_shake(now: 11.05)
    assert_operator Math.hypot(camera.shake_x, camera.shake_y), :>, 0
    camera.update_shake(now: 11.06, motion: false)
    assert_equal [0.0, 0.0], [camera.shake_x, camera.shake_y]
    camera.update_shake(now: 11.1, motion: true)
    assert_equal [0.0, 0.0], [camera.shake_x, camera.shake_y], "reenabling motion does not revive a cancelled shake"
  end

  def test_camera_zoom_keeps_the_point_under_the_cursor_while_shaking
    camera = Burrow::Client::Camera.new(4800, 1600)
    camera.navigate(2400, 900)
    camera.shake(8, now: 10)
    camera.update_shake(now: 10.04)
    point = camera.world(950, 280)
    camera.zoom_by(1, anchor: [950, 280])
    assert_in_delta point[0], camera.world(950, 280)[0], 0.001
    assert_in_delta point[1], camera.world(950, 280)[1], 0.001
  end

  private

  def arena(**options)
    match = game({"wind" => 0, "health" => 200, "retreat_seconds" => 0,
      "fall_damage" => false}.merge(options.transform_keys(&:to_s)))
    data = "\0".b * Burrow::Terrain::SIZE
    floor = 500 / Burrow::Terrain::CELL
    data[floor * Burrow::Terrain::W..] = "\1" * ((Burrow::Terrain::H - floor) * Burrow::Terrain::W)
    match.instance_variable_set(:@terrain, Burrow::Terrain.new(seed: 1, data: data))
    match.instance_variable_set(:@water, 624.0)
    match.worms.each_with_index do |worm, index|
      worm.merge!(x: 150.0 + index * 340, y: 500.0, vx: 0.0, vy: 0.0)
    end
    match
  end

  def fire(match, id, **values)
    match.command("p0", "fire", {weapon: id, angle: -50, power: 0.5, fuse: 3,
      x: 900, y: 300, direction: 1}.merge(values))
    match.projectiles.first
  end

  def restore(match)
    Burrow::Match.restore(JSON.parse(JSON.generate(match.checkpoint)))
  end

  def assert_same_state(expected, actual, message = nil)
    assert_equal JSON.generate(expected.snapshot(terrain: true)), JSON.generate(actual.snapshot(terrain: true)), message
  end
end
