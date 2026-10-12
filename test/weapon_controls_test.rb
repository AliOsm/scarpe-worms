# frozen_string_literal: true
require_relative "test_helper"
require "set"
require_relative "../lib/burrow/client/theme"
require_relative "../lib/burrow/client/scene"
require_relative "../lib/burrow/client/match_ui"

class WeaponControlsTest < Minitest::Test
  class Harness
    include Burrow::Client::MatchUI
    attr_reader :state, :keys, :actions, :connection, :selected_weapon, :locked_target, :angle, :target, :notice
    def initialize(match)
      @match, @actions, @keys = match, [], Set.new
      @connection = Struct.new(:sequence).new(0)
      @selected_weapon, @angle, @power, @fuse = "rocket", -40.0, 0.65, 3
      @target = [700.0, 200.0]
      @page, @window_active, @scale, @offset_x, @offset_y = :match, true, 1, 0, 0
      camera = Burrow::Client::Camera.new(match.world_width, match.world_height)
      @scene = Struct.new(:camera).new(camera)
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
    def overlay? = !!@overlay
    def refresh_match_hud; end
    def notify(message) = @notice = message
    def action(type, **values)
      @connection.sequence += 1
      @actions << [type, values]
      @match.command(my_id, type, values)
      true
    rescue Burrow::RuleError => e
      @notice = e.message
      true
    end
    def show_arsenal
      cancel_controls
      @overlay = true
    end
    def lose_focus
      @window_active = false
      cancel_controls
    end
    def regain_focus = @window_active = true
    def select(id)
      equip_weapon(id)
      @actions.clear
    end
    def fired = actions.select { |type, _values| type == "fire" }
  end

  def harness(options = {})
    match = game({"retreat_seconds" => 0}.merge(options))
    [Harness.new(match), match]
  end

  def test_each_weapon_declares_a_useful_control_hint_and_charge_contract
    Burrow::Catalog::WEAPONS.each_key do |id|
      refute_empty Burrow::Catalog.hint(id), id
    end
    %w[rocket grenade cluster sticky homing mega_bomb banana holy_bomb poison].each { |id| assert Burrow::Catalog.charged?(id), id }
    %w[mortar shotgun sheep super_sheep mole skunk cow rope jetpack drill blowtorch].each { |id| refute Burrow::Catalog.charged?(id), id }
  end

  def test_homing_target_lock_is_independent_of_aim_and_click_does_not_fire
    c, m = harness
    c.select("homing")
    c.pointer_click(1, 700, 320)
    locked = c.locked_target.dup
    assert_empty c.fired
    c.pointer(400, 220)
    refute_equal locked, c.target
    assert_equal locked, c.locked_target
    angle = c.angle
    c.key_down(" ")
    assert c.instance_variable_get(:@charge_started)
    c.key_up(" ")
    assert_equal 1, c.fired.length
    assert_in_delta angle, c.fired.first[1][:angle], 0.001
    assert_equal locked, m.projectiles.first.values_at(:target_x, :target_y)
  end

  def test_homing_is_two_steps_with_the_mouse_and_backspace_retargets
    c, m = harness
    c.select("homing")
    c.pointer_click(1, 700, 320)
    first = c.locked_target.dup
    c.key_down("backspace")
    c.key_up("backspace")
    assert_nil c.locked_target, "Backspace returns to target selection"
    c.pointer_click(1, 900, 300)
    second = c.locked_target.dup
    refute_equal first, second
    c.pointer(300, 200)
    c.pointer_click(1, 300, 200)
    assert c.instance_variable_get(:@charge_started), "the second click charges instead of re-locking"
    assert_equal second, c.locked_target
    c.release_charge(source: :mouse)
    assert_equal 1, c.fired.length
    assert_equal second, m.projectiles.first.values_at(:target_x, :target_y)
  end

  def test_arrows_pick_a_strike_approach_without_walking
    c, m = harness("terrain" => "islands")
    c.select("airstrike")
    actor = m.active
    start = actor[:x]
    c.key_down("left")
    c.update_controls
    c.key_up("left")
    assert_equal(-1, c.strike_direction)
    m.step(10)
    assert_in_delta start, actor[:x], 0.5, "the arrow chose a direction instead of walking"
    c.pointer_click(1, 900, 300)
    assert_equal(-1, c.fired.last[1][:direction])
    assert m.projectiles.all? { |p| p[:vx] < 0 }
  end

  def test_arrows_tilt_the_girder_and_its_preview
    c, = harness
    c.select("girder")
    2.times do
      c.key_down("right")
      c.key_up("right")
    end
    assert_equal 45.0, c.girder_rotation
    10.times do
      c.key_down("left")
      c.key_up("left")
    end
    assert_equal(-90.0, c.girder_rotation)
  end

  def test_space_splits_a_thrown_fruit_salad_and_the_grub_can_still_retreat
    c, m = harness("scheme" => "sandbox", "retreat_seconds" => 3)
    c.select("banana")
    c.key_down(" ")
    c.key_up(" ")
    assert_equal 1, c.fired.length
    m.step(6)
    c.sync
    assert_equal "Split · Space", c.special_control[0]
    c.key_down(" ")
    c.key_up(" ")
    assert_equal "activate", c.actions.last[0]
    m.step
    assert_equal 6, m.projectiles.count { |p| p[:fragment] }
  end

  def test_space_also_locks_before_charging_homing
    c, = harness
    c.select("homing")
    c.key_down(" ")
    c.key_up(" ")
    assert c.locked_target
    assert_nil c.instance_variable_get(:@charge_started)
    assert_empty c.fired
    c.key_down(" ")
    c.key_up(" ")
    assert_equal 1, c.fired.length
  end

  def test_direct_weapon_fires_on_press_and_auto_repeat_cannot_consume_second_shot
    c, m = harness("ammo" => {"shotgun" => 1})
    c.select("shotgun")
    c.key_down(" ")
    5.times { c.key_down(" ") }
    assert_equal 1, c.fired.length
    assert_nil c.instance_variable_get(:@charge_started)
    c.key_up(" ")
    c.key_down(" ") # Snapshot has not acknowledged first shot.
    c.key_up(" ")
    assert_equal 1, c.fired.length
    c.sync
    refute c.can_equip?("rocket")
    assert c.can_equip?("shotgun"), "last cartridge retains the second shot"
    c.key_down(" ")
    c.key_up(" ")
    assert_equal 2, c.fired.length
    assert_equal "settling", m.phase
  end

  def test_a_mouse_release_cannot_fire_a_keyboard_charge_or_the_reverse
    c, = harness
    c.key_down(" ")
    c.release_charge(source: :mouse)
    assert_empty c.fired
    c.key_up(" ")
    assert_equal 1, c.fired.length
    c, = harness
    c.begin_fire(:mouse)
    c.key_up(" ")
    assert_empty c.fired
    c.release_charge(source: :mouse)
    assert_equal 1, c.fired.length
  end

  def test_full_power_fires_once_and_does_not_activate_the_next_stage_on_release
    c, = harness
    c.key_down(" ")
    c.instance_variable_set(:@charge_started, Burrow.clock - 2)
    c.update_controls
    c.key_up(" ")
    assert_equal 1, c.fired.length
    assert_in_delta 1.0, c.fired.first[1][:power]
  end

  def test_focus_loss_overlay_and_turn_expiry_cancel_a_charge
    %i[focus overlay expired].each do |reason|
      c, = harness
      c.key_down(" ")
      case reason
      when :focus then c.lose_focus; c.regain_focus
      when :overlay then c.show_arsenal
      when :expired then c.state["phase"] = "settling"; c.update_controls
      end
      c.key_up(" ")
      assert_empty c.fired, reason.to_s
      assert_nil c.instance_variable_get(:@charge_started)
    end
  end

  def test_weapon_change_cancels_charge_and_clears_old_homing_target
    c, = harness
    c.select("homing")
    c.lock_homing_target
    c.key_down(" ")
    assert c.equip_weapon("grenade")
    c.key_up(" ")
    assert_nil c.locked_target
    assert_empty c.fired
  end

  def test_super_sheep_controls_use_arrows_and_focus_loss_stops_turning
    c, m = harness
    c.select("super_sheep")
    c.key_down(" ")
    c.key_up(" ")
    c.sync
    assert_match(/Launch/, c.special_control[0])
    c.key_down(" ")
    c.key_up(" ")
    c.sync
    assert_match(/Drop/, c.special_control[0])
    c.key_down("left")
    c.update_controls
    assert_equal(-1, m.projectiles.first[:steer])
    assert_equal 0, m.active[:input]
    c.lose_focus
    assert_equal 0, m.projectiles.first[:steer]
    c.regain_focus
    c.key_up("left")
  end

  def test_out_of_ammo_and_cavern_air_support_cannot_be_equipped
    c, = harness("terrain" => "cavern", "ammo" => {"grenade" => 0})
    refute c.equip_weapon("grenade")
    refute c.equip_weapon("airstrike")
    assert_equal "rocket", c.selected_weapon
  end
end
