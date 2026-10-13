# frozen_string_literal: true

require_relative "test_helper"
require "set"
require_relative "../lib/burrow/client/match_ui"
require_relative "../lib/burrow/client/audio"
require_relative "../lib/burrow/client/theme"
require_relative "../lib/burrow/client/sprites"
require_relative "../lib/burrow/client/scene"
require "chunky_png"

class WeaponsCrittersTest < Minitest::Test
  FLOOR = 1200

  class Controls
    include Burrow::Client::MatchUI
    attr_reader :state, :keys, :actions, :connection

    def initialize(match, weapon = "super_sheep")
      @match, @actions, @keys = match, [], Set.new
      @connection = Struct.new(:sequence).new(0)
      @selected_weapon, @angle, @power, @fuse = weapon, -40.0, 0.65, 3
      @target, @page, @window_active = [700.0, 200.0], :match, true
      acknowledge
    end

    def acknowledge
      @state = JSON.parse(JSON.generate(@match.snapshot))
      @pending_action = nil
    end

    def my_id = "p0"
    def my_turn? = state["team"] == my_id
    def active_worm = state["worms"].find { |worm| worm["id"] == state["active"] }
    def my_inventory = state["teams"].find { |team| team["id"] == my_id }["inventory"]
    def overlay? = false
    def refresh_match_hud; end

    def action(type, **values)
      @connection.sequence += 1
      @actions << [type, values]
      @match.command(my_id, type, values)
    end

    def lose_focus
      @window_active = false
      cancel_controls
    end

    def regain_focus = @window_active = true
    def press_fire
      key_down(" ")
      key_up(" ")
    end
  end

  class SoundRecorder < Burrow::Client::Audio
    attr_reader :heard
    def initialize = @heard = []
    def play(name, **options) = @heard << [name, options]
  end

  class PitchMixer
    attr_reader :pitches
    def initialize = @pitches = []
    def alGetSourcei(_source, _key, pointer) = pointer.read_int = 0x1014
    def alSourceStop(*); end
    def alSourcei(*); end
    def alSource3f(*); end
    def alSourcePlay(*); end
    def alSourcef(source, key, value)
      @pitches << [source, value] if key == 0x1003
    end
  end

  class CritterImage
    attr_accessor :left, :top, :width, :height, :path
    attr_reader :rotations, :rotate_angle
    def initialize
      @rotations, @rotate_angle = [], 0
    end

    def style(**values)
      values.each { |key, value| public_send("#{key}=", value) }
    end

    def rotate(angle)
      @rotations << angle
      @rotate_angle = angle
    end
  end

  # A wide, flat course keeps stage/fuse tests independent of generated terrain,
  # other grubs, and the water. Individual tests add their own obstacles.
  def arena(gap: nil)
    match = game("wind" => 0, "retreat_seconds" => 0, "fall_damage" => false)
    width, height = 4800, 1600
    cols, rows = width / Burrow::Terrain::CELL, height / Burrow::Terrain::CELL
    ground = FLOOR / Burrow::Terrain::CELL
    data = "\0".b * (cols * ground) + "\1".b * (cols * (rows - ground))
    if gap
      left, right = gap.map { |x| x / Burrow::Terrain::CELL }
      (ground...rows).each { |y| data[y * cols + left, right - left] = "\0" * (right - left) }
    end
    terrain = Burrow::Terrain.new(seed: 1, data: data, width: width, height: height)
    match.instance_variable_set(:@terrain, terrain)
    match.instance_variable_set(:@water, 1504.0)
    match.worms.each_with_index do |worm, index|
      worm.merge!(x: index.zero? ? 400.0 : 4200.0 + index * 100, y: FLOOR.to_f,
        vx: 0.0, vy: 0.0, facing: 1)
    end
    match
  end

  def release(match, weapon)
    match.command("p0", "fire", weapon: weapon)
    match.projectiles.first
  end

  def activate(match)
    match.command("p0", "activate")
  end

  def explosion(match, weapon)
    match.events.find { |event| event[:kind] == "explosion" && event[:style] == weapon }
  end

  def step_until(match, limit: 120)
    limit.times do
      return if yield
      match.step
    end
    assert yield, "condition was not reached after #{limit} simulation ticks"
  end

  # Gain clearance, then fly circles with ordinary leased host inputs. This
  # reaches the full flight budget without hitting terrain or world bounds.
  def fly_for(match, ticks)
    ticks.times do |index|
      if index >= 30 && (index - 30) % 6 == 0
        match.command("p0", "steer", direction: 1)
      end
      match.step
    end
  end

  def restore(match)
    Burrow::Match.restore(JSON.parse(JSON.generate(match.checkpoint)))
  end

  def test_sheep_can_detonate_during_its_release_hop_or_while_running
    [1, 40].each do |ticks|
      match = arena
      sheep = release(match, "sheep")
      match.step(ticks)
      assert_operator sheep[:x], :>, 410
      assert_operator sheep[:vy], :<, 0 if ticks == 1
      assert_in_delta FLOOR - 6, sheep[:y], 2 if ticks == 40
      x, y = sheep.values_at(:x, :y)
      ammo = match.team[:inventory]["sheep"]
      activate(match)
      match.step
      refute_includes match.projectiles, sheep
      blast = explosion(match, "sheep")
      refute_nil blast
      assert_in_delta x, blast[:x], 0.01
      assert_in_delta y, blast[:y], 0.01
      assert_equal Burrow::Catalog.fetch("sheep")[:radius], blast[:radius]
      assert_equal ammo, match.team[:inventory]["sheep"]
    end
  end

  def test_sheep_auto_detonates_after_eight_seconds_and_releases_the_turn
    match = arena
    sheep = release(match, "sheep")
    match.step(8 * Burrow::TICK_RATE - 1)
    assert_includes match.projectiles, sheep
    match.step
    refute_includes match.projectiles, sheep
    refute_nil explosion(match, "sheep")
    step_until(match, limit: 90) { match.turn > 1 }
    assert_equal "aiming", match.phase
  end

  def test_sheep_hops_over_a_small_obstacle
    match = arena
    match.terrain.bridge(600, FLOOR - 24, width: 28, height: 24)
    sheep = release(match, "sheep")
    hopped = false
    step_until(match, limit: 180) do
      hopped ||= sheep[:x] > 550 && sheep[:vy] < -100
      sheep[:x] > 650
    end
    assert hopped, "a knee-high obstacle should trigger a visible hop"
    assert_includes match.projectiles, sheep
  end

  def test_sheep_hops_a_ledge_and_lands_on_the_far_side
    match = arena(gap: [600, 650])
    sheep = release(match, "sheep")
    hopped = false
    step_until(match, limit: 150) do
      hopped ||= sheep[:x].between?(570, 650) && sheep[:vy] < -100
      sheep[:x] > 700 && sheep[:vy].abs < 1
    end
    assert hopped, "the leading edge should trigger a hop before the sheep falls"
    assert_in_delta FLOOR - 6, sheep[:y], 2
    assert_includes match.projectiles, sheep
  end

  def test_sheep_turns_away_from_a_wall_it_cannot_jump
    match = arena
    match.terrain.bridge(600, FLOOR - 300, width: 20, height: 300)
    sheep = release(match, "sheep")
    step_until(match, limit: 180) { sheep[:vx] < 0 }
    wall_x = sheep[:x]
    match.step(12)
    assert_operator sheep[:x], :<, wall_x - 30
    assert_operator sheep[:x], :<, 590
    assert_includes match.projectiles, sheep
  end

  def test_captain_wool_launches_upward_and_turns_at_constant_speed
    match = arena
    sheep = release(match, "super_sheep")
    owner_x = match.active[:x]
    match.step(40)
    activate(match)
    assert_equal "flying", sheep[:stage]
    assert_in_delta 0, sheep[:vx], 0.001
    assert_in_delta(-260, sheep[:vy], 0.001)
    heading = Math.atan2(sheep[:vy], sheep[:vx])
    match.command("p0", "steer", direction: 1)
    match.step(6)
    assert_in_delta 2.7 * 6 / Burrow::TICK_RATE, sheep[:heading] - heading, 0.001
    assert_in_delta 260, Math.hypot(sheep[:vx], sheep[:vy]), 0.001
    assert_in_delta owner_x, match.active[:x], 0.001
    assert_equal 0, match.active[:input]
  end

  def test_captain_wool_stops_turning_on_zero_input_and_expired_lease
    match = arena
    sheep = release(match, "super_sheep")
    activate(match)
    match.command("p0", "steer", direction: 1)
    match.step(6)
    match.command("p0", "steer", direction: 0)
    stopped = sheep[:heading]
    match.step(4)
    assert_in_delta stopped, sheep[:heading], 0.000001
    match.command("p0", "steer", direction: -1)
    match.step(12)
    expired = sheep[:heading]
    assert_operator expired, :<, stopped
    match.step(6)
    assert_in_delta expired, sheep[:heading], 0.000001
    assert_in_delta 260, Math.hypot(sheep[:vx], sheep[:vy]), 0.001
  end

  def test_captain_wools_third_activation_detonates_in_flight
    match = arena
    sheep = release(match, "super_sheep")
    activate(match)
    match.step(15)
    ammo = match.team[:inventory]["super_sheep"]
    activate(match)
    match.step
    refute_includes match.projectiles, sheep
    refute_nil explosion(match, "super_sheep")
    assert_equal ammo, match.team[:inventory]["super_sheep"]
  end

  def test_captain_wool_gets_eight_seconds_from_launch_then_falls_and_can_detonate
    match = arena
    sheep = release(match, "super_sheep")
    match.step(180)
    activate(match)
    fly_for(match, 8 * Burrow::TICK_RATE - 1)
    assert_includes match.projectiles, sheep
    assert_equal "flying", sheep[:stage], "running must not consume the flight budget"
    match.step
    assert_equal "falling", sheep[:stage]
    refute sheep[:guided]
    assert_operator sheep[:life], :<=, 4 * Burrow::TICK_RATE
    assert_operator sheep[:life], :>, 0
    vy = sheep[:vy]
    match.step
    assert_operator sheep[:vy], :>, vy
    activate(match)
    match.step
    refute_includes match.projectiles, sheep
    refute_nil explosion(match, "super_sheep")
  end

  def test_captain_wool_falling_stage_finishes_without_another_command
    match = arena
    sheep = release(match, "super_sheep")
    activate(match)
    fly_for(match, 8 * Burrow::TICK_RATE)
    assert_equal "falling", sheep[:stage]
    match.step(4 * Burrow::TICK_RATE)
    refute_includes match.projectiles, sheep
    refute_nil explosion(match, "super_sheep")
    step_until(match, limit: 90) { match.turn > 1 }
  end

  def test_late_captain_wool_takeoff_keeps_the_turn_until_the_critter_finishes
    match = arena
    sheep = release(match, "super_sheep")
    match.step(330)
    activate(match)
    fly_for(match, 211)
    assert_operator match.tick, :>, 18 * Burrow::TICK_RATE
    assert_equal 1, match.turn, "the old settling deadline must not hand over a live remote critter"
    assert_equal "flying", sheep[:stage]
    assert_includes match.projectiles, sheep
    activate(match)
    match.step
    refute_includes match.projectiles, sheep
    step_until(match, limit: 90) { match.turn > 1 }
  end

  def test_arrow_and_ad_key_edges_steer_immediately_inside_the_refresh_interval
    match = arena
    sheep = release(match, "super_sheep")
    activate(match)
    controls = Controls.new(match)
    Burrow.stub(:clock, 100.0) do
      controls.update_controls
      {"left" => -1, "right" => 1, "a" => -1, "d" => 1}.each do |key, direction|
        before = controls.actions.length
        controls.key_down(key)
        assert_equal before + 1, controls.actions.length, "#{key} waits for neither the next frame nor the 80ms refresh"
        assert_equal ["steer", {direction: direction}], controls.actions.last
        assert_equal direction, sheep[:steer]
        controls.key_down(key)
        assert_equal before + 1, controls.actions.length, "auto-repeat is ignored"
        controls.key_up(key)
        assert_equal ["steer", {direction: 0}], controls.actions.last
        assert_equal 0, sheep[:steer], "#{key} release stops turning immediately"
      end
    end
    assert_equal 0, match.active[:input]
  end

  def test_flight_focus_loss_clears_held_keys_and_stops_the_host
    match = arena
    sheep = release(match, "super_sheep")
    activate(match)
    controls = Controls.new(match)
    controls.key_down("a")
    assert_equal(-1, sheep[:steer])
    controls.lose_focus
    assert_empty controls.keys
    assert_equal 0, sheep[:steer]
    before = controls.actions.length
    controls.key_up("a")
    controls.update_controls(force: true)
    assert_equal before, controls.actions.length, "unfocused input cannot revive steering"
    controls.regain_focus
    controls.update_controls(force: true)
    assert_equal 0, sheep[:steer]
  end

  def test_fire_acknowledgement_gate_prevents_skipping_captain_wool_stages
    match = arena
    controls = Controls.new(match)
    controls.press_fire
    sheep = match.projectiles.first
    controls.press_fire
    assert_equal "walking", sheep[:stage]
    assert_equal 1, controls.actions.length
    controls.acknowledge
    assert_equal "Launch · Space", controls.special_control.first
    controls.press_fire
    controls.press_fire
    assert_equal "flying", sheep[:stage]
    assert_equal 2, controls.actions.length
    controls.acknowledge
    assert_equal "Detonate · Space", controls.special_control.first
    controls.press_fire
    controls.press_fire
    assert_equal 3, controls.actions.length
    match.step
    assert_empty match.projectiles
    refute_nil explosion(match, "super_sheep")
  end

  def test_mole_dives_on_activation_and_carves_a_continuous_unscorched_tunnel
    match = arena
    mole = release(match, "mole")
    match.step(20)
    original = match.terrain.checksum
    assert_equal "walking", mole[:stage]
    activate(match)
    assert_equal "diving", mole[:stage]
    assert_operator mole[:vy], :<, 0
    step_until(match) { mole[:stage] == "digging" }
    x, y = mole.values_at(:x, :y)
    match.step(15)
    assert_includes match.projectiles, mole, "its own freshly carved tunnel is not an exit"
    assert_operator mole[:x], :>, x + 20
    assert_operator mole[:y], :>, y + 25
    refute_equal original, match.terrain.checksum
    refute match.terrain.solid?(x, y)
    refute match.terrain.solid?(mole[:x], mole[:y])
    assert_equal 0, match.terrain.data.count("\4"), "digging does not scorch the tunnel"
  end

  def test_mole_can_detonate_while_diving_or_digging
    %w[diving digging].each do |stage|
      match = arena
      mole = release(match, "mole")
      activate(match)
      step_until(match) { mole[:stage] == stage }
      activate(match)
      match.step
      refute_includes match.projectiles, mole, stage
      refute_nil explosion(match, "mole"), stage
    end
  end

  def test_mole_detects_a_real_air_pocket_ahead_of_its_tunnel
    match = arena
    mole = release(match, "mole")
    activate(match)
    step_until(match) { mole[:stage] == "digging" }
    match.step(8)
    pocket_x, pocket_y = mole[:x] + 60, mole[:y] + 88
    match.terrain.carve(pocket_x, pocket_y, 32, scorch: false)
    step_until(match, limit: 50) { !match.projectiles.include?(mole) }
    blast = explosion(match, "mole")
    refute_nil blast
    assert_operator Math.hypot(blast[:x] - pocket_x, blast[:y] - pocket_y), :<, 65
  end

  def test_mole_detonates_on_a_grub_in_its_tunnel
    match = arena
    mole = release(match, "mole")
    activate(match)
    step_until(match) { mole[:stage] == "digging" }
    victim = match.worms.find { |worm| worm[:team] == "p1" }
    victim.merge!(x: mole[:x] + 5, y: mole[:y] + 12, vx: 0.0, vy: 0.0)
    match.step(2)
    refute_includes match.projectiles, mole
    refute_nil explosion(match, "mole")
    assert_operator victim[:hp], :<, 100
  end

  def test_mole_has_a_timer_even_if_it_is_never_activated
    match = arena
    mole = release(match, "mole")
    match.step(12 * Burrow::TICK_RATE - 1)
    assert_includes match.projectiles, mole
    match.step
    refute_includes match.projectiles, mole
    refute_nil explosion(match, "mole")
    step_until(match, limit: 90) { match.turn > 1 }
  end

  def test_skunk_sprays_for_four_full_seconds_after_a_late_activation
    match = arena
    skunk = release(match, "skunk")
    match.step(210)
    assert_empty match.hazards.select { |hazard| hazard[:kind] == "gas" }
    activate(match)
    assert_equal "spraying", skunk[:stage]
    assert match.hazards.any? { |hazard| hazard[:kind] == "gas" }
    start_x = skunk[:x]
    match.step(4 * Burrow::TICK_RATE - 1)
    assert_includes match.projectiles, skunk
    assert_operator skunk[:x], :>, start_x + 300
    assert_operator match.hazards.count { |hazard| hazard[:kind] == "gas" }, :>=, 8
    match.step
    refute_includes match.projectiles, skunk
    blast = explosion(match, "skunk")
    refute_nil blast
    assert_equal 18, blast[:radius]
    assert match.hazards.any? { |hazard| hazard[:kind] == "gas" && hazard[:radius] == Burrow::Catalog.fetch("skunk")[:radius] }
    step_until(match, limit: 90) { match.turn > 1 }
  end

  def test_skunk_clouds_poison_grubs_near_the_running_trail
    match = arena
    skunk = release(match, "skunk")
    match.step(30)
    victim = match.worms.find { |worm| worm[:team] == "p1" }
    victim[:x] = skunk[:x] + 25
    refute victim[:poisoned]
    activate(match)
    match.step(15)
    assert victim[:poisoned]
    assert_includes match.projectiles, skunk, "spraying continues through a grub"
  end

  def test_cows_release_every_twenty_four_ticks_and_pending_cows_are_invisible
    match = arena
    ammo = match.team[:inventory]["cow"]
    release(match, "cow")
    pending = match.projectiles.drop(1)
    pending_positions = pending.map { |cow| cow.values_at(:x, :y, :life) }
    snapshot = match.snapshot
    assert_equal 1, snapshot[:projectiles].length
    refute snapshot[:motion][:shots].any? { |track| pending.any? { |cow| cow[:id] == track["id"] } }
    match.step(23)
    assert_equal 1, match.snapshot[:projectiles].length
    assert_equal pending_positions, pending.map { |cow| cow.values_at(:x, :y, :life) }
    assert pending.all? { |cow| cow[:age].zero? }
    match.step
    assert_equal 2, match.snapshot[:projectiles].length
    match.step(23)
    assert_equal 2, match.snapshot[:projectiles].length
    match.step
    assert_equal 3, match.snapshot[:projectiles].length
    assert_operator match.projectiles.map { |cow| cow[:x] }.max - match.projectiles.map { |cow| cow[:x] }.min, :>, 100
    assert_equal ammo - 1, match.team[:inventory]["cow"], "one release spends one herd cartridge"
  end

  def test_cows_explode_on_a_wall_instead_of_hopping_it
    match = arena
    match.terrain.bridge(600, FLOOR - 100, width: 10, height: 100)
    cow = release(match, "cow")
    step_until(match, limit: 90) { !match.projectiles.include?(cow) }
    blast = explosion(match, "cow")
    refute_nil blast
    assert_operator blast[:x], :<, 600
    assert_in_delta FLOOR - 6, blast[:y], 2
  end

  def test_cows_explode_on_contact_with_a_grub
    match = arena
    victim = match.worms.find { |worm| worm[:team] == "p1" }
    victim[:x] = 600
    cow = release(match, "cow")
    step_until(match, limit: 90) { !match.projectiles.include?(cow) }
    refute_nil explosion(match, "cow")
    assert_operator victim[:hp], :<, 100
  end

  def test_cows_time_out_and_the_entire_herd_finishes_the_turn
    match = arena
    first = release(match, "cow")
    match.step(8 * Burrow::TICK_RATE - 1)
    assert_equal 3, match.projectiles.length
    assert_includes match.projectiles, first
    match.step
    refute_includes match.projectiles, first
    refute_nil explosion(match, "cow")
    match.step(48)
    assert_empty match.projectiles
    assert_equal 3, match.events.count { |event| event[:kind] == "explosion" && event[:style] == "cow" }
    step_until(match, limit: 90) { match.turn > 1 }
  end

  def test_all_critter_stages_resume_deterministically_from_checkpoints
    stages = {"sheep" => %w[walking], "super_sheep" => %w[walking flying falling],
      "mole" => %w[walking diving digging], "skunk" => %w[walking spraying], "cow" => %w[walking]}
    stages.each do |weapon, weapon_stages|
      weapon_stages.each do |stage|
        match = arena
        shot = release(match, weapon)
        match.step(10)
        activate(match) unless stage == "walking"
        case stage
        when "flying" then fly_for(match, 42)
        when "falling" then fly_for(match, 8 * Burrow::TICK_RATE)
        when "diving", "spraying" then match.step(3)
        when "digging"
          step_until(match) { shot[:stage] == "digging" }
          match.step(8)
        end
        assert_equal stage, shot[:stage], weapon
        recovered = restore(match)
        assert recovered.projectiles.first.key?(:flight_ticks) if stage == "flying"
        40.times { match.step; recovered.step }
        assert_equal JSON.generate(match.snapshot(terrain: true)), JSON.generate(recovered.snapshot(terrain: true)), "#{weapon} #{stage}"
      end
    end
  end

  def test_legacy_flying_checkpoint_without_a_flight_budget_has_a_bounded_lifetime
    match = arena
    release(match, "super_sheep")
    activate(match)
    match.step(30)
    saved = JSON.parse(JSON.generate(match.checkpoint))
    saved["projectiles"].first.delete("flight_ticks")
    recovered = Burrow::Match.restore(saved)
    sheep = recovered.projectiles.first
    (8 * Burrow::TICK_RATE).times do |index|
      break unless recovered.projectiles.include?(sheep) && sheep[:stage] == "flying"
      recovered.command("p0", "steer", direction: 1) if index % 6 == 0
      recovered.step
    end
    refute_equal "flying", sheep[:stage], "older checkpoints must not retain unlimited guided flight"
    recovered.step(4 * Burrow::TICK_RATE)
    refute_includes recovered.projectiles, sheep
    refute_nil explosion(recovered, "super_sheep")
  end

  def test_stage_audio_predictions_match_host_reports_without_double_playing
    {"super_sheep" => "launch", "mole" => "jump", "skunk" => "throw"}.each do |weapon, cue|
      match = arena
      release(match, weapon)
      audio = SoundRecorder.new
      state = JSON.parse(JSON.generate(match.snapshot))
      receipt = {"match" => "critter-match", "player" => "p0", "seq" => 2}
      audio.local_action("activate", values: {}, state: state, player: "p0", sequence: 2, match_id: "critter-match")
      assert_equal [cue], audio.heard.map(&:first), weapon
      assert audio.heard.first.last[:immediate]
      activate(match)
      report = JSON.parse(JSON.generate(match.events.reverse.find { |event| event[:kind] == "activate" }))
      assert_equal cue, audio.event_cue(report)
      audio.event(report.merge("input" => receipt))
      assert_equal [cue], audio.heard.map(&:first), "the acknowledged #{weapon} stage does not sound twice"
    end
  end

  def test_captain_wool_remote_detonation_does_not_predict_another_launch
    match = arena
    release(match, "super_sheep")
    activate(match)
    match.step(15)
    audio = SoundRecorder.new
    state = JSON.parse(JSON.generate(match.snapshot))
    audio.local_action("activate", values: {}, state: state, player: "p0", sequence: 3, match_id: "critter-match")
    activate(match)
    event = match.events.last
    assert_equal "activate", event[:kind]
    report = JSON.parse(JSON.generate(event))
    assert_equal audio.event_cue(report), audio.heard.first.first
    refute_includes audio.heard.map(&:first), "launch"
    refute_includes audio.heard.map(&:first), "throw"
    audio.event(report.merge("input" => {"match" => "critter-match", "player" => "p0", "seq" => 3}))
    assert_equal 1, audio.heard.length
    match.step
    audio.event(JSON.parse(JSON.generate(explosion(match, "super_sheep"))))
    assert_match(/explosion/, audio.heard.last.first)
  end

  def test_each_cow_release_reuses_the_low_pitched_call_and_damage_keeps_normal_pitch
    match = arena
    audio = SoundRecorder.new
    state = JSON.parse(JSON.generate(match.snapshot))
    receipt = {"match" => "critter-match", "player" => "p0", "seq" => 1}
    audio.local_action("fire", values: {weapon: "cow"}, state: state, player: "p0", sequence: 1, match_id: "critter-match")
    release(match, "cow")
    first = match.events.find { |event| event[:kind] == "fire" && event[:weapon] == "cow" }
    audio.event(JSON.parse(JSON.generate(first)).merge("input" => receipt))
    assert_equal 1, audio.heard.length, "the first cow's host report acknowledges its immediate local call"
    match.step(48)
    delayed = match.events.select { |event| event[:kind] == "critter_release" && event[:weapon] == "cow" }
    assert_equal [24, 48], delayed.map { |event| event[:tick] }
    delayed.each { |event| audio.event(JSON.parse(JSON.generate(event))) }
    assert_equal %w[hurt hurt hurt], audio.heard.map(&:first)
    assert_equal [0.65, 0.65, 0.65], audio.heard.map { |entry| entry.last[:pitch] }
    audio.event({"kind" => "damage"})
    assert_equal "hurt", audio.heard.last.first
    assert_equal 1.0, audio.heard.last.last[:pitch]
  end

  def test_reusing_a_native_audio_voice_resets_the_cow_pitch
    mixer = PitchMixer.new
    audio = Burrow::Client::Audio.allocate
    {preferences: {"volume" => 1, "muted" => false}, available: true, al: mixer,
      sources: (1..13).to_a, cursor: 0, source_status: Struct.new(:read_int).new,
      buffers: Burrow::Client::Audio::CUES.to_h { |cue| [cue, cue] },
      voice_priority: {}, voice_started: {}, gains: {}, last: {}}.each do |key, value|
      audio.instance_variable_set("@#{key}", value)
    end
    audio.play("hurt", pitch: 0.65, immediate: true)
    11.times { audio.play("launch", immediate: true) }
    audio.play("hurt", immediate: true)
    assert_nil audio.error
    assert_equal [1, 0.65], mixer.pitches.first
    assert_equal [1, 1.0], mixer.pitches.last, "ordinary sounds must reset a reused cow voice"
  end

  def sprite_shot(weapon, stage: "walking", vx: 105.0, vy: 0.0)
    {"id" => "critter", "weapon" => weapon, "stage" => stage,
      "walker" => %w[walking spraying].include?(stage), "x" => 600.0, "y" => FLOOR - 6.0,
      "vx" => vx, "vy" => vy, "life" => 180, "owner" => "p0"}
  end

  def test_running_critter_art_uses_directional_world_sprites_without_spinning
    %w[sheep super_sheep mole skunk cow].each do |weapon|
      right = Burrow::Client::Sprites.projectile(sprite_shot(weapon, vx: 500.0), 19)
      left = Burrow::Client::Sprites.projectile(sprite_shot(weapon, vx: -500.0), 19)
      assert_equal 0, right.rotation, weapon
      assert_equal 0, left.rotation, weapon
      assert_match(%r{/ordnance/critters/#{weapon}-walk-\d+\.png\z}, right.path)
      assert_match(%r{/ordnance/critters/left/#{weapon}-walk-\d+\.png\z}, left.path)
      assert_equal File.basename(right.path), File.basename(left.path)
      assert File.file?(right.path), right.path
      assert File.file?(left.path), left.path
      assert_equal [64, 64], [right.width, right.height], "#{weapon} must read beside a 64px grub"
    end
  end

  def test_captain_wool_flips_its_flying_art_instead_of_turning_upside_down
    [[260, 0], [180, -180], [180, 180], [-260, 0], [-180, -180], [-180, 180], [0, -260], [0, 260]].each do |vx, vy|
      look = Burrow::Client::Sprites.projectile(sprite_shot("super_sheep", stage: "flying", vx: vx, vy: vy), 8)
      assert_operator look.rotation, :>=, -90
      assert_operator look.rotation, :<=, 90
      assert_equal(vx.negative?, look.path.include?("/critters/left/"))
      assert_match(/super_sheep-flying-\d+\.png\z/, look.path)
      assert File.file?(look.path), look.path
      angle = look.rotation * Math::PI / 180
      facing = vx.negative? ? -1 : 1
      speed = Math.hypot(vx, vy)
      assert_in_delta vx / speed, facing * Math.cos(angle), 0.001
      assert_in_delta vy / speed, facing * Math.sin(angle), 0.001
      assert_equal [32, 32], [look.anchor_x, look.anchor_y], "flying poses turn around their centre"
    end
  end

  def test_walking_and_special_critter_animations_change_both_path_and_pixels
    shots = %w[sheep super_sheep mole skunk cow].map { |weapon| sprite_shot(weapon) }
    shots += [sprite_shot("super_sheep", stage: "flying", vx: 260.0),
      sprite_shot("mole", stage: "digging", vx: 52.0, vy: 76.0), sprite_shot("skunk", stage: "spraying")]
    shots.each do |shot|
      paths = (0..30).map { |tick| Burrow::Client::Sprites.projectile(shot, tick).path }.uniq
      assert_operator paths.length, :>, 1, "#{shot['weapon']} #{shot['stage']} should animate"
      pixels = paths.map { |path| ChunkyPNG::Image.from_file(path).pixels }
      assert_equal paths.length, pixels.uniq.length, "#{shot['weapon']} #{shot['stage']} frames must contain distinct poses"
    end
  end

  def test_hop_fall_dive_dig_and_spray_stages_choose_existing_world_poses
    %w[sheep super_sheep mole skunk cow].each do |weapon|
      {"hop" => -80.0, "fall" => 80.0}.each do |pose, vy|
        [-105.0, 105.0].each do |vx|
          look = Burrow::Client::Sprites.projectile(sprite_shot(weapon, vx: vx, vy: vy), 4)
          assert_match(/#{weapon}-#{pose}-\d+\.png\z/, look.path)
          assert File.file?(look.path), look.path
          assert_equal 0, look.rotation, "#{weapon} #{pose} keeps its feet below its body"
        end
      end
    end
    [["super_sheep", "falling", "fall", 260.0, 0.0],
      ["mole", "diving", "hop", 110.0, -150.0],
      ["mole", "diving", "dive", 110.0, 150.0],
      ["mole", "digging", "dig", 52.0, 76.0],
      ["skunk", "spraying", "spray", 105.0, 0.0]].each do |weapon, stage, pose, vx, vy|
      [-1, 1].each do |direction|
        look = Burrow::Client::Sprites.projectile(sprite_shot(weapon, stage: stage, vx: vx * direction, vy: vy), 4)
        assert_match(/#{weapon}-#{pose}-\d+\.png\z/, look.path)
        assert File.file?(look.path), look.path
      end
    end
  end

  def test_critter_manifest_and_rasters_match_runtime_sizes_and_stay_inside_the_canvas
    metadata = JSON.parse(File.read(File.join(Burrow::Client::Theme::ART, "manifest.json"))).fetch("ordnance").fetch("critters")
    assert_equal [128, 128], metadata.fetch("source_size")
    assert_equal [64, 64], metadata.fetch("logical_size")
    assert_equal metadata.fetch("logical_size").map { |n| n * 2 }, metadata.fetch("source_size")
    assert_equal metadata.fetch("anchor").map { |n| n * 2 }, metadata.fetch("source_anchor")
    assert_equal %w[cow mole sheep skunk super_sheep], metadata.fetch("sprites").keys.sort
    metadata.fetch("sprites").each do |weapon, poses|
      look = Burrow::Client::Sprites.projectile(sprite_shot(weapon), 0)
      assert_equal metadata.fetch("logical_size"), [look.width, look.height]
      assert_equal metadata.fetch("anchor"), [look.anchor_x, look.anchor_y]
      poses.each do |pose, count|
        count.times do |frame|
          %w[pattern left_pattern].each do |pattern|
            relative = metadata.fetch(pattern).sub("{id}", "#{weapon}-#{pose}-#{frame}")
            path = File.join(Burrow::Client::Theme::ART, relative)
            assert File.file?(path), relative
            image = ChunkyPNG::Image.from_file(path)
            assert_equal metadata.fetch("source_size"), [image.width, image.height], relative
            border = image.row(0) + image.row(image.height - 1) + image.column(0) + image.column(image.width - 1)
            assert border.all? { |pixel| ChunkyPNG::Color.a(pixel).zero? }, "#{relative} must not clip against a canvas edge"
            opaque = image.pixels.count { |pixel| ChunkyPNG::Color.a(pixel) >= 128 }
            assert_operator opaque, :>, 1000, "#{relative} needs a readable body, not an empty or tiny raster"
          end
        end
      end
    end
    flight = Burrow::Client::Sprites.projectile(sprite_shot("super_sheep", stage: "flying", vx: 260), 0)
    assert_equal metadata.fetch("flight_anchor"), [flight.anchor_x, flight.anchor_y]
  end

  def test_running_raster_feet_meet_the_same_ground_as_the_host_collider
    %w[sheep super_sheep mole skunk cow].each do |weapon|
      [-105.0, 105.0].each do |vx|
        shot = sprite_shot(weapon, vx: vx)
        looks = (0..30).map { |tick| Burrow::Client::Sprites.projectile(shot, tick) }.uniq(&:path)
        looks.each do |look|
          image = ChunkyPNG::Image.from_file(look.path)
          bottom = (0...image.height).to_a.reverse.find do |y|
            image.row(y).any? { |pixel| ChunkyPNG::Color.a(pixel) >= 32 }
          end
          refute_nil bottom, look.path
          feet = shot["y"] - look.anchor_y + (bottom + 1) * look.height.fdiv(image.height)
          assert_in_delta FLOOR, feet, 3.0, "#{File.basename(look.path)} floats above or sinks into its collision floor"
        end
      end
    end
  end

  def test_guided_critter_renderer_keeps_small_heading_changes_without_duplicate_writes
    scene = Burrow::Client::Scene.allocate
    shot = sprite_shot("super_sheep", stage: "flying", vx: 260.0)
    image = CritterImage.new
    controller = Object.new
    def controller.motion? = false
    {state: {"projectiles" => [shot]}, scale: 1, timeline: Struct.new(:tick).new(0),
      projectile_nodes: {"critter" => {image: image}}, controller: controller}.each do |key, value|
      scene.instance_variable_set("@#{key}", value)
    end
    scene.send(:render_projectiles)
    shot["vx"], shot["vy"] = Math.cos(2 * Math::PI / 180) * 260, Math.sin(2 * Math::PI / 180) * 260
    scene.send(:render_projectiles)
    assert_equal [2], image.rotations, "a two-degree heading change must survive rendering"
    3.times { scene.send(:render_projectiles) }
    assert_equal [2], image.rotations, "an unchanged heading must not send more native rotation writes"
    shot["stage"], shot["vy"] = "falling", 80.0
    scene.send(:render_projectiles)
    assert_equal [2, 0], image.rotations, "falling art must clear the preceding flight rotation"
  end

  def test_new_explosion_effects_keep_their_first_frame_during_the_creation_update
    scene = Burrow::Client::Scene.allocate
    paths = Burrow::Client::Sprites.frames("fx/explosion-%d", 9)
    nodes = Array.new(2) { CritterImage.new.tap { |image| image.path = paths.first } }
    cached = []
    scene.define_singleton_method(:cache_frame) { |path| cached << path }
    effects = nodes.map.with_index do |node, index|
      {node: node, born: 100.005, life: 0.5, frame: 0, fps: 18,
        kind: index.zero? ? :sprite : :frames, name: "explosion", paths: paths}
    end
    scene.instance_variable_set(:@effects, effects)
    # Scene captures its render timestamp before creating effects from events.
    scene.send(:render_effects, 100.0)
    assert_equal [paths.first, paths.first], nodes.map(&:path), "new blasts must never request frame -1"
    assert_empty cached
    scene.send(:render_effects, 100.065)
    assert_equal [paths[1], paths[1]], nodes.map(&:path)
    nodes.each { |node| assert File.file?(node.path), node.path }
  end
end
