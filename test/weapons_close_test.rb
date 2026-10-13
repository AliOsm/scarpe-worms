# frozen_string_literal: true
require_relative "test_helper"

class WeaponsCloseTest < Minitest::Test
  def arena(**options)
    match = game({"wind" => 0, "retreat_seconds" => 0, "fall_damage" => true}.merge(options.transform_keys(&:to_s)))
    terrain = match.terrain
    data = "\0".b * (terrain.cols * terrain.rows)
    floor = 900 / Burrow::Terrain::CELL
    data[floor * terrain.cols..] = "\1" * ((terrain.rows - floor) * terrain.cols)
    match.instance_variable_set(:@terrain, Burrow::Terrain.new(seed: 1, width: terrain.width, height: terrain.height, data: data))
    match.worms.each_with_index { |w, i| w.merge!(x: 300.0 + i * 450, y: 900.0, vx: 0.0, vy: 0.0, facing: 1) }
    match
  end

  def fire(match, weapon, **values)
    match.command("p0", "fire", {weapon: weapon, angle: 0}.merge(values))
  end

  def restore(match)
    Burrow::Match.restore(JSON.parse(JSON.generate(match.checkpoint)))
  end

  def test_double_tap_five_pellets_one_impulse_and_two_independent_aims
    match = arena(ammo: {"shotgun" => 1})
    victim = match.worms[1]
    victim[:x] = 345
    fire(match, "shotgun")
    assert_equal 74, victim[:hp]
    assert_in_delta 40, victim[:vx], 0.01
    first = match.events.reverse.find { |e| e[:kind] == "beam" }
    assert_equal 5, first[:rays].length
    assert_equal "aiming", match.phase
    assert_equal 1, match.snapshot[:shots_left]
    assert_equal 0, match.team[:inventory]["shotgun"]
    assert_raises(Burrow::RuleError) { fire(match, "rifle") }
    fire(match, "shotgun", angle: -90)
    last = match.events.reverse.find { |e| e[:kind] == "beam" }
    assert_operator last[:y2], :<, first[:y2]
    assert_equal 74, victim[:hp]
    assert_equal "settling", match.phase
    assert_equal 2, match.events.count { |e| e[:kind] == "beam" }
  end

  def test_pellets_cannot_use_each_others_holes_to_hit_through_cover
    match = arena
    match.worms[1][:x] = 338
    match.terrain.bridge(320, 870, width: 2, height: 30)
    before = match.terrain.checksum
    fire(match, "shotgun")
    assert_equal 100, match.worms[1][:hp]
    refute_equal before, match.terrain.checksum
    assert match.events.last[:impacts].all? { |impact| impact[:material] == "terrain" }
  end

  def test_rifle_hits_once_and_cannot_skip_even_a_single_cell_wall
    [310, 311, 312].each do |wall_x|
      match = arena
      match.worms[1][:x] = 345
      match.terrain.bridge(wall_x, 870, width: 0, height: 30)
      fire(match, "rifle")
      assert_equal 100, match.worms[1][:hp], "wall x=#{wall_x}"
    end
    match = arena
    fire(match, "rifle")
    assert_equal 58, match.worms[1][:hp]
    beam = match.events.last
    assert_in_delta 320, beam[:x], 0.01
    assert_equal "worm", beam[:impacts].first[:material]
  end

  def test_minigun_spreads_eight_rounds_and_recovers_a_pending_burst
    match = arena
    fire(match, "minigun")
    assert_equal 1, match.events.count { |e| e[:kind] == "beam" }
    match.step(3)
    recovered = restore(match)
    20.times { match.step; recovered.step }
    beams = match.events.select { |e| e[:kind] == "beam" }
    assert_equal 8, beams.length
    assert_operator beams.map { |e| e[:angle] }.uniq.length, :>, 1
    assert_operator match.worms[1][:hp], :<, 100
    assert_equal JSON.generate(match.snapshot(terrain: true)), JSON.generate(recovered.snapshot(terrain: true))
  end

  def test_laser_cuts_through_cover_and_hits_each_grub_once
    match = arena
    match.worms[1][:x] = 430
    match.worms[2][:x] = 520
    match.terrain.bridge(375, 870, width: 14, height: 30)
    fire(match, "laser")
    assert_equal 62, match.worms[1][:hp]
    assert_equal 62, match.worms[2][:hp]
    refute match.terrain.solid?(375, 887)
    assert_operator match.events.last[:impacts].length, :>=, 3
    assert_operator match.events.last[:impacts].length, :<=, 12
  end

  def test_guns_can_rupture_barrels_instead_of_passing_through_props
    match = arena
    barrel = {id: 999, kind: "barrel", x: 365.0, y: 900.0, hp: 20, armed: 0, life: 10_000, owner: "p1"}
    match.hazards << barrel
    fire(match, "rifle")
    assert_equal 100, match.worms[1][:hp]
    assert barrel[:trigger]
    match.step(3)
    refute_includes match.hazards, barrel
    assert match.events.any? { |e| e[:kind] == "explosion" && e[:style] == "barrel" }
    assert match.hazards.any? { |h| h[:kind] == "flame" }
  end

  def test_flamethrower_stream_has_range_persistent_fire_and_saved_timing
    match = arena
    match.worms[1][:x] = 405
    fire(match, "flamethrower")
    match.step(9)
    recovered = restore(match)
    28.times { match.step; recovered.step }
    beams = match.events.select { |e| e[:kind] == "beam" && e[:style] == "flame" }
    assert_equal 18, beams.length
    assert_operator beams.last[:tick] - beams.first[:tick], :>=, 34
    assert_operator match.worms[1][:hp], :<, 100
    assert beams.all? { |e| Math.hypot(e[:x2] - e[:x], e[:y2] - e[:y]) <= 142 }
    assert_operator match.hazards.count { |h| h[:kind] == "flame" }, :>, 0
    assert_operator match.hazards.count { |h| h[:kind] == "flame" }, :<=, 60
    assert_equal JSON.generate(match.snapshot(terrain: true)), JSON.generate(recovered.snapshot(terrain: true))
  end

  def test_a_dead_shooter_does_not_finish_a_stream_or_burst
    %w[minigun flamethrower].each do |weapon|
      match = arena
      fire(match, weapon)
      match.active[:hp] = 0
      match.step(36)
      assert_equal 1, match.events.count { |e| e[:kind] == "beam" }
      assert_empty match.instance_variable_get(:@salvos)
    end
  end

  def test_uppercut_leaps_and_launches_without_self_fall_damage
    match = arena
    actor = match.active
    victim = match.worms[1]
    victim[:x] = actor[:x] + 35
    fire(match, "fire_punch")
    assert_equal 65, victim[:hp]
    assert_operator actor[:vy], :<, 0
    assert_operator victim[:vy], :<, actor[:vy]
    assert actor[:launched]
    match.step(65)
    assert_equal 100, actor[:hp]
    assert match.events.any? { |e| e[:kind] == "melee" && e[:hits] == [victim[:id]] }
  end

  def test_melee_respects_walls_and_frozen_bodies
    %w[fire_punch prod bat axe].each do |weapon|
      match = arena
      victim = match.worms[1]
      victim[:x] = 340
      match.terrain.bridge(320, 870, width: 2, height: 30)
      fire(match, weapon)
      assert_equal 100, victim[:hp], weapon
      assert_equal [0.0, 0.0], victim.values_at(:vx, :vy), weapon
      match = arena
      victim = match.worms[1]
      victim[:x], victim[:frozen] = 335, true
      fire(match, weapon)
      assert_equal 100, victim[:hp], weapon
      assert_equal [0.0, 0.0], victim.values_at(:vx, :vy), weapon
    end
  end

  def test_close_attacks_cannot_skip_a_two_pixel_wall_between_ray_samples
    %w[fire_punch prod bat axe].each do |weapon|
      match = arena
      victim = match.worms[1]
      victim[:x] = 340
      match.terrain.bridge(316, 870, width: 0, height: 30)
      fire(match, weapon)
      assert_equal 100, victim[:hp], weapon
      assert_equal [0.0, 0.0], victim.values_at(:vx, :vy), weapon
    end
  end

  def test_bat_launches_in_the_aimed_direction_including_downward
    [-75, 0, 40, -140].each do |angle|
      match = arena
      victim = match.worms[1]
      victim[:x] = angle < -90 ? 265 : 335
      fire(match, "bat", angle: angle)
      assert_equal 68, victim[:hp]
      assert_in_delta Math.cos(angle * Math::PI / 180) * 490, victim[:vx], 0.001
      assert_in_delta Math.sin(angle * Math::PI / 180) * 490, victim[:vy], 0.001
    end
  end

  def test_prod_only_nudges_and_axe_halves_odd_health_with_damage_modifiers
    match = arena
    victim = match.worms[1]
    victim[:x] = 335
    fire(match, "prod")
    assert_equal 100, victim[:hp]
    assert_equal [140, -35], victim.values_at(:vx, :vy)
    match = arena
    victim = match.worms[1]
    victim[:x], victim[:hp] = 335, 75
    fire(match, "axe")
    assert_equal 37, victim[:hp]
    match = arena
    victim = match.worms[1]
    victim[:x], victim[:hp] = 335, 75
    fire(match, "double_damage")
    fire(match, "axe")
    assert_equal 0, victim[:hp]
  end

  def test_dash_carves_forward_without_sinking_and_hits_each_target_once
    match = arena
    actor, victim = match.active, match.worms[1]
    victim[:x] = 360
    match.terrain.bridge(330, 875, width: 4, height: 25)
    fire(match, "dragon_punch")
    match.step(4)
    recovered = restore(match)
    7.times { match.step; recovered.step }
    assert_equal 58, victim[:hp]
    assert_in_delta 900, actor[:y], 0.01
    assert_in_delta 399, actor[:x], 0.01
    assert match.terrain.free_body?(actor[:x], actor[:y])
    assert_equal JSON.generate(match.snapshot(terrain: true)), JSON.generate(recovered.snapshot(terrain: true))
  end

  def test_drill_descends_at_controlled_speed_and_space_stops_all_digging
    match = arena
    actor = match.active
    fire(match, "drill")
    match.step(15)
    assert_in_delta 942, actor[:y], 0.1
    assert_equal 100, actor[:hp]
    assert_equal 0, actor[:vy]
    event = match.events.reverse.find { |e| e[:kind] == "dig" }
    assert_equal "drill", event[:style]
    assert_equal actor[:id], event[:worm]
    match.command("p0", "activate")
    checksum = match.terrain.checksum
    match.step(25)
    assert_nil match.snapshot[:tool]
    assert_equal checksum, match.terrain.checksum
    assert_equal 100, actor[:hp]
  end

  def test_torch_slope_steering_expires_and_restores_without_resuming_stopped_tool
    match = arena
    fire(match, "blowtorch")
    match.command("p0", "steer", lift: 1)
    match.step(6)
    assert_in_delta 318, match.active[:x], 0.01
    assert_operator match.active[:y], :<, 900
    match.command("p0", "steer", lift: -1)
    match.step(6)
    assert_in_delta 900, match.active[:y], 0.01
    recovered = restore(match)
    15.times { match.step; recovered.step }
    assert_equal JSON.generate(match.snapshot(terrain: true)), JSON.generate(recovered.snapshot(terrain: true))
    y = match.active[:y]
    match.step(3)
    assert_in_delta y, match.active[:y], 0.01
    match.command("p0", "activate")
    recovered = restore(match)
    assert_nil recovered.snapshot[:tool]
  end

  def test_old_saved_tool_without_damage_history_still_runs
    match = arena
    fire(match, "blowtorch")
    saved = JSON.parse(JSON.generate(match.checkpoint))
    saved["state"]["tool"].delete("hits")
    recovered = Burrow::Match.restore(saved)
    recovered.step(7)
    assert_equal "torch", recovered.snapshot[:tool][:kind]
  end

  def test_blasts_interrupt_tools_without_erasing_knockback
    %w[drill blowtorch dragon_punch].each do |weapon|
      [false, true].each do |during_tick|
        match = arena
        fire(match, weapon)
        actor = match.active
        if during_tick
          match.hazards << {id: "mine-test", kind: "mine", x: actor[:x] - 20, y: actor[:y],
            armed: 0, life: 1000, trigger: match.tick + 1, owner: "p1"}
        else
          match.explode(actor[:x] - 20, actor[:y] - 10, damage: 20, radius: 30, owner: "p1")
        end
        match.step
        assert_nil match.snapshot[:tool], "#{weapon}, explosion during tick: #{during_tick}"
        assert actor[:launched]
        assert_operator actor[:vy], :<, 0
        assert_operator actor[:vx].abs, :>, 10
      end
    end
  end
end
require "set"
require File.join(Burrow::ROOT, "lib/burrow/client/theme")
require File.join(Burrow::ROOT, "lib/burrow/client/scene")
require File.join(Burrow::ROOT, "lib/burrow/client/match_ui")

class WeaponsCloseControlsTest < Minitest::Test
  class CloseInput
    include Burrow::Client::MatchUI
    attr_reader :state, :keys, :actions, :connection, :selected_weapon, :notice

    def initialize(match)
      @match, @actions, @keys = match, [], Set.new
      @connection = Struct.new(:sequence).new(0)
      @selected_weapon, @angle, @power, @fuse = "shotgun", -40.0, 0.65, 3
      @target = [700.0, 200.0]
      @page, @window_active, @scale, @offset_x, @offset_y = :match, true, 1, 0, 0
      @scene = Struct.new(:camera).new(Burrow::Client::Camera.new(match.world_width, match.world_height))
      def @scene.navigation_hit?(*_args) = false
      sync
    end

    def sync
      @state = JSON.parse(JSON.generate(@match.snapshot))
      @pending_action = nil
    end
    def scene = @scene
    def my_id = "p0"
    def my_turn? = state["team"] == my_id
    def active_worm = state["worms"].find { |w| w["id"] == state["active"] }
    def my_inventory = state["teams"].find { |t| t["id"] == my_id }["inventory"]
    def overlay? = false
    def refresh_match_hud; end
    def notify(message) = @notice = message
    def action(type, **values)
      @connection.sequence += 1
      @actions << [type, values]
      @match.command(my_id, type, values)
      true
    rescue Burrow::RuleError => error
      @notice = error.message
      true
    end
    def press(key)
      key_down(key)
      key_up(key)
    end
    def poll_controls
      @last_input_at = 0
      update_controls
    end
    def fired = actions.select { |type, _values| type == "fire" }
  end

  def test_shotgun_keyboard_then_mouse_reaim_respects_ack_and_the_last_cartridge
    match = game("ammo" => {"shotgun" => 1}, "retreat_seconds" => 0)
    input = CloseInput.new(match)
    input.press(" ")
    first_angle = input.fired.first.last[:angle]
    input.pointer_click(1, 900, 280)
    assert_equal 1, input.fired.length, "a mouse press cannot bypass the first shot acknowledgement"
    input.sync
    refute input.can_equip?("rifle")
    assert input.can_equip?("shotgun")
    input.pointer_click(1, 900, 280)
    assert_equal 2, input.fired.length
    refute_equal first_angle, input.fired.last.last[:angle]
    assert_equal 0, match.team[:inventory]["shotgun"]
    assert_equal "settling", match.phase
  end

  def test_keyboard_starts_each_digging_tool_and_mouse_stops_it_without_more_ammo
    %w[drill blowtorch].each do |weapon|
      match = game("retreat_seconds" => 0)
      input = CloseInput.new(match)
      assert input.equip_weapon(weapon)
      before = match.team[:inventory][weapon]
      input.press(" ")
      input.sync
      assert match.snapshot[:tool]
      assert_match(/stop/i, input.special_control.first)
      input.pointer_click(1, 600, 330)
      assert_equal "activate", input.actions.last.first
      assert_nil match.snapshot[:tool]
      assert_equal before - 1, match.team[:inventory][weapon]
      assert_equal 1, input.fired.length
    end
  end

  def test_torch_arrows_steer_both_slopes_and_releasing_keys_sends_neutral
    match = game
    input = CloseInput.new(match)
    input.equip_weapon("blowtorch")
    input.press(" ")
    input.sync
    input.key_down("up")
    input.poll_controls
    assert_equal 1, match.snapshot[:tool][:lift]
    input.key_up("up")
    input.key_down("down")
    input.poll_controls
    assert_equal(-1, match.snapshot[:tool][:lift])
    input.key_up("down")
    input.poll_controls
    assert_equal 0, match.snapshot[:tool][:lift]
    assert_equal 0, match.active[:input], "tool steering never walks the grub"
  end

  def test_keep_turn_supplies_allow_an_attack_after_acknowledgement
    %w[shield double_damage low_gravity wind_control].each do |weapon|
      match = game
      input = CloseInput.new(match)
      input.equip_weapon(weapon)
      input.pointer_click(1, 600, 330)
      assert_equal "aiming", match.phase, weapon
      refute input.can_equip?("rifle"), "the activation still needs acknowledgement"
      input.sync
      assert input.supply_active? unless weapon == "wind_control"
      assert_match(/keeps your turn/i, Burrow::Catalog.hint(weapon))
      assert input.equip_weapon("rifle"), weapon
      input.press(" ")
      assert_equal 2, input.fired.length, weapon
    end
  end

  def test_heal_freeze_and_pass_use_the_turn_through_mouse_input
    %w[heal freeze skip].each do |weapon|
      match = game("retreat_seconds" => 0)
      match.active[:hp], match.active[:poisoned] = 65, true if weapon == "heal"
      input = CloseInput.new(match)
      input.equip_weapon(weapon)
      input.pointer_click(1, 600, 330)
      assert_equal "settling", match.phase, weapon
      if weapon == "heal"
        assert_equal 100, match.active[:hp]
        refute match.active[:poisoned]
      end
      input.sync
      refute input.can_equip?("rifle"), weapon
    end
  end

  def test_dragon_dash_control_describes_its_own_action_and_can_stop
    match = game
    input = CloseInput.new(match)
    input.equip_weapon("dragon_punch")
    input.press(" ")
    input.sync
    assert_match(/dash|rush/i, input.special_control.last)
    refute_match(/drill/i, input.special_control.last)
    input.press(" ")
    assert_nil match.snapshot[:tool]
  end
end

require_relative "../lib/burrow/client/audio"

class WeaponsClosePresentationTest < Minitest::Test
  class Effects
    attr_reader :calls
    def initialize = @calls = []
    def fx_frames(*args, **options) = @calls << [:frames, args, options]
    def fx_line(*args, **options) = @calls << [:line, args, options]
    def fx_particle(*args, **options) = @calls << [:particle, args, options]
    def fx_sprite(*args, **options) = @calls << [:sprite, args, options]
  end

  class Sound < Burrow::Client::Audio
    attr_reader :heard
    def initialize = @heard = []
    def play(name, **options) = @heard << [name, options]
  end

  def test_melee_effects_work_in_both_directions_without_double_rotation
    %w[fire_punch dragon_punch prod bat axe].each do |weapon|
      [-1, 1].each do |facing|
        scene = Effects.new
        event = {"kind" => "melee", "style" => weapon, "facing" => facing,
          "angle" => facing == -1 ? Math::PI : 0, "x" => 300, "y" => 800}
        assert Burrow::Client::Sprites.effect(scene, event, 0), weapon
        frames = scene.calls.find { |call| call.first == :frames }
        assert frames
        assert frames[1].first.all? { |path| File.file?(path) }
        assert_includes frames[1].first.first, "-left-" if facing == -1
        assert [nil, 0.0].include?(frames[2][:rotation]), "#{weapon} facing #{facing}"
      end
    end
  end

  def test_shotgun_emits_five_tracers_and_laser_retains_a_glowing_core
    scene = Effects.new
    rays = 5.times.map { |i| {"x2" => 600, "y2" => 500 + i} }
    event = {"kind" => "beam", "style" => "shotgun", "x" => 320, "y" => 500,
      "x2" => 600, "y2" => 500, "rays" => rays, "impacts" => []}
    Burrow::Client::Sprites.effect(scene, event, 0)
    assert_equal 5, scene.calls.count { |call| call.first == :line }
    scene = Effects.new
    Burrow::Client::Sprites.effect(scene, event.merge("style" => "laser", "rays" => nil), 0)
    assert_equal [10, 5, 2], scene.calls.select { |call| call.first == :line }.map { |call| call[2][:width] }
  end

  def test_status_overlays_are_absent_for_ordinary_grubs_and_use_existing_frames
    sprites = Burrow::Client::Sprites
    assert_empty sprites.overlays({"hp" => 100}, 0)
    %w[shield frozen poisoned _close_boost _close_moon].each do |flag|
      looks = sprites.overlays({"hp" => 100, flag => true}, 15)
      assert_equal 1, looks.length, flag
      assert File.file?(looks.first.path), flag
    end
    refute_equal sprites.close_hazard({"kind" => "mine", "armed" => 30}, 0).path,
      sprites.close_hazard({"kind" => "mine", "armed" => 30}, 35).path
    assert_includes sprites.close_hazard({"kind" => "turret", "facing" => -1, "shots" => 0}, 35).path, "left-empty"
  end

  def test_local_sound_predictions_match_authority_without_duplicate_reports
    cases = [["fire_punch", {"kind" => "melee"}, "impact"],
      ["dragon_punch", {"kind" => "melee"}, "impact"],
      ["heal", {"kind" => "heal"}, "pickup"],
      ["flamethrower", {"kind" => "beam", "style" => "flame"}, "launch"],
      ["mine", {"kind" => "hazard_place"}, "equip"],
      ["shield", {"kind" => "fire", "weapon" => "shield"}, "pickup"]]
    cases.each do |weapon, event, expected|
      sound = Sound.new
      sound.local_action("fire", values: {weapon: weapon}, state: {"team" => "p0"}, player: "p0", sequence: 3, match_id: "m")
      assert_equal [expected], sound.heard.map(&:first), weapon
      assert sound.heard.first.last[:immediate]
      sound.event(event.merge("input" => {"match" => "m", "player" => "p0", "seq" => 3}))
      assert_equal [expected], sound.heard.map(&:first), weapon
      sound.event(event)
      assert_equal [expected, expected], sound.heard.map(&:first), weapon
    end
  end
end

class WeaponsCloseHazardsAndSuppliesTest < Minitest::Test
  def arena(**options)
    match = game({"wind" => 0, "retreat_seconds" => 0, "fall_damage" => false}.merge(options.transform_keys(&:to_s)))
    terrain = match.terrain
    data = "\0".b * (terrain.cols * terrain.rows)
    floor = 900 / Burrow::Terrain::CELL
    data[floor * terrain.cols..] = "\1" * ((terrain.rows - floor) * terrain.cols)
    match.instance_variable_set(:@terrain, Burrow::Terrain.new(seed: 1, width: terrain.width, height: terrain.height, data: data))
    match.worms.each_with_index { |w, i| w.merge!(x: 300.0 + i * 450, y: 900.0, vx: 0.0, vy: 0.0, facing: 1) }
    match
  end

  def fire(match, weapon, **values)
    match.command(match.team[:id], "fire", {weapon: weapon, angle: 0}.merge(values))
  end

  def restored(match)
    Burrow::Match.restore(JSON.parse(JSON.generate(match.checkpoint)))
  end

  def pass_turn(match)
    previous = match.turn
    fire(match, "skip")
    600.times do
      match.step
      break if match.turn > previous || match.finished?
    end
    assert_equal previous + 1, match.turn
  end

  def assert_placement_rolls_back(weapon)
    %i[wall grub prop].each do |obstacle|
      match = arena
      case obstacle
      when :wall then match.terrain.bridge(310, 870, width: 0, height: 30)
      when :grub then match.worms[1][:x] = 324
      when :prop
        match.hazards << {id: "occupied", kind: "barrel", x: 324.0, y: 900.0, armed: 0, life: 10_000, hp: 24}
      end
      before = JSON.generate(match.checkpoint)
      assert_raises(Burrow::RuleError, "#{weapon}: #{obstacle}") { fire(match, weapon) }
      assert_equal before, JSON.generate(match.checkpoint), "rejected #{weapon} against #{obstacle} must not spend ammo or alter state"
    end
  end

  def test_mine_placement_failure_preserves_ammo_and_turn
    assert_placement_rolls_back("mine")
  end

  def test_mine_arms_once_respects_cover_and_restores_its_trigger_fuse
    match = arena
    fire(match, "mine")
    mine = match.hazards.last
    assert_in_delta 324, mine[:x], 0.01
    assert_equal 30, mine[:armed]
    assert_equal "hazard_place", match.events.last[:kind]
    match.worms[0][:x] = 250
    match.worms[1][:x] = 350
    match.terrain.bridge(340, 870, width: 0, height: 30)
    match.step(29)
    refute mine[:arm_reported]
    refute mine[:trigger]
    match.step(10)
    assert mine[:arm_reported]
    assert_equal 1, match.events.count { |e| e[:kind] == "mine_arm" }
    refute mine[:trigger], "the nearby grub is behind a solid wall"
    match.terrain.carve(340, 885, 20)
    match.step
    assert_equal match.tick + 18, mine[:trigger]
    assert_equal 1, match.events.count { |e| e[:kind] == "mine_trigger" }
    recovered = restored(match)
    18.times { match.step; recovered.step }
    refute match.hazards.any? { |h| h[:id] == mine[:id] }
    assert_equal 1, match.events.count { |e| e[:kind] == "explosion" && e[:style] == "mine" }
    assert_operator match.worms[1][:hp], :<, 100
    assert_equal JSON.generate(match.snapshot(terrain: true)), JSON.generate(recovered.snapshot(terrain: true))
  end

  def test_turret_placement_failure_preserves_ammo_and_turn
    assert_placement_rolls_back("turret")
  end

  def test_two_pixel_wall_at_the_edge_of_a_barrel_rejects_placement
    %w[barrel turret].each do |weapon|
      match = arena
      # A single two-pixel cell beside the 324px placement centre is outside
      # four-pixel samples but still intersects the prop's right silhouette.
      match.terrain.bridge(334, 870, width: 0, height: 28)
      before = JSON.generate(match.checkpoint)
      assert_raises(Burrow::RuleError, weapon) { fire(match, weapon) }
      assert_equal before, JSON.generate(match.checkpoint), weapon
    end
  end

  def test_barrel_on_a_short_ledge_starts_at_the_hand_and_falls_to_the_floor
    match = arena
    match.active.merge!(x: 300.0, y: 690.0, facing: 1)
    match.terrain.bridge(287, 690, width: 40, height: 12)
    fire(match, "barrel")
    barrel = match.hazards.last
    assert_in_delta 324, barrel[:x], 0.01
    assert_in_delta 688, barrel[:y], 0.01, "the barrel stays beside the hand rather than teleporting to floor 900"
    assert_operator barrel.fetch(:vy, 0), :>=, 0
    match.step(10)
    assert_operator barrel[:y], :>, 688
    assert_operator barrel[:y], :<, 900
    match.step(100)
    assert_operator barrel[:y], :>=, 899, "the loose prop settles on the lower floor"
  end

  def test_turret_tracks_left_and_fires_exactly_five_visible_shots
    match = arena
    match.active.merge!(x: 600.0, facing: -1)
    match.worms[1][:x] = 450
    fire(match, "turret")
    sentry = match.hazards.last
    assert_in_delta 576, sentry[:x], 0.01
    assert_equal 5, sentry[:shots]
    match.step(35)
    assert_equal(-1, sentry[:facing])
    assert_equal match.worms[1][:id], sentry[:target_id]
    assert_equal 84, match.worms[1][:hp]
    recovered = restored(match)
    180.times { match.step; recovered.step }
    assert_equal 0, sentry[:shots]
    assert_equal 20, match.worms[1][:hp]
    shots = match.events.select { |e| e[:kind] == "beam" && e[:style] == "turret" }
    assert_equal [4, 3, 2, 1, 0], shots.map { |e| e[:shots] }
    assert shots.all? { |e| e[:hazard] == sentry[:id] && e[:x2] < e[:x] }
    assert_equal 100, match.worms[0][:hp], "the owner is never selected as a target"
    assert_equal JSON.generate(match.snapshot(terrain: true)), JSON.generate(recovered.snapshot(terrain: true))
  end

  def test_turret_does_not_spend_ammo_on_covered_frozen_or_distant_targets
    match = arena
    match.worms[1][:x] = 500
    match.worms[2][:x] = 400 # An ally in range must not attract fire.
    fire(match, "turret")
    sentry = match.hazards.last
    match.terrain.bridge(460, 865, width: 4, height: 35)
    match.step(35)
    assert_equal 5, sentry[:shots]
    match.terrain.carve(460, 880, 25)
    match.worms[1][:frozen] = true
    match.step(35)
    assert_equal 5, sentry[:shots]
    match.worms[1].merge!(frozen: false, x: sentry[:x] + 430)
    match.step(35)
    assert_equal 5, sentry[:shots]
    match.worms[1][:x] = 500
    match.step(35)
    assert_equal 4, sentry[:shots]
    assert_equal 84, match.worms[1][:hp]
    assert_equal 100, match.worms[2][:hp]
  end

  def test_legacy_turret_checkpoint_supplies_missing_ammo_and_aim_fields
    match = arena
    match.worms[1][:x] = 500
    fire(match, "turret")
    saved = JSON.parse(JSON.generate(match.checkpoint))
    %w[shots facing angle aim_angle hp].each { |key| saved["hazards"].last.delete(key) }
    recovered = Burrow::Match.restore(saved)
    recovered.step(35)
    assert_equal 4, recovered.hazards.last[:shots]
    assert_equal 84, recovered.worms[1][:hp]
    assert recovered.hazards.last[:aim_angle].finite?
  end

  def test_first_aid_restores_health_cures_poison_and_ends_the_turn
    match = arena
    actor = match.active
    actor.merge!(hp: 62, poisoned: true)
    before_turn = match.turn
    fire(match, "heal")
    assert_equal 97, actor[:hp]
    refute actor[:poisoned]
    assert_equal "settling", match.phase
    heal = match.events.reverse.find { |event| event[:kind] == "heal" }
    assert_equal 35, heal[:amount]
    assert_equal true, heal[:cured]
    600.times do
      match.step
      break if match.turn > before_turn
    end
    assert_equal before_turn + 1, match.turn
    assert_equal "p1", match.team[:id]
  end

  def test_bubble_wrap_halves_damage_keeps_the_turn_and_expires_next_turn
    match = arena
    actor = match.active
    fire(match, "shield")
    assert actor[:shield]
    assert_equal "aiming", match.phase
    match.send(:hurt, actor, 30, source: "p1")
    assert_equal 85, actor[:hp]
    assert_equal({low_gravity: false, double_damage: false}, match.snapshot[:effects])
    pass_turn(match)
    assert actor[:shield], "the shield covers the intervening enemy turn"
    match.send(:hurt, actor, 30, source: "p1")
    assert_equal 70, actor[:hp]
    pass_turn(match)
    refute actor[:shield]
    match.send(:hurt, actor, 30, source: "p1")
    assert_equal 40, actor[:hp]
  end
end
