# frozen_string_literal: true
require_relative "test_helper"
require_relative "../lib/burrow/client/theme"
require_relative "../lib/burrow/client/scene"
require_relative "../lib/burrow/client/match_ui"

class FrameWorkTest < Minitest::Test
  # Like Shoes, setters count even when the value did not change. This catches
  # needless pipe traffic at the call sites, without depending on native timing.
  class Drawable
    attr_reader :writes
    %i[left top width height size stroke fill path text state hidden].each do |name|
      attr_reader name
      define_method("#{name}=") { |value| @writes << {name => value}; instance_variable_set("@#{name}", value) }
    end
    def initialize(**values)
      @writes = []
      values.each { |name, value| instance_variable_set("@#{name}", value) }
    end
    def style(**values)
      @writes << values
      values.each { |name, value| instance_variable_set("@#{name}", value) }
    end
    def move(left, top) = style(left: left, top: top)
    def hide = self.hidden = true
    def show = self.hidden = false
    def hover(&block) = @hover = block
    def leave(&block) = @leave = block
  end

  class HUD
    include Burrow::Client::Widgets
    include Burrow::Client::MatchUI
    attr_reader :state, :drawables
    def initialize(state)
      @state, @drawables = state, []
      @page, @scale, @connection_status = :match, 1, "online"
      @selected_weapon, @angle, @power, @fuse, @rtt = "rocket", -40, 0.65, 3, 0
      %i[connection_overlay reconnect_label turn_label clock_label phase_label wind_label round_label
        weapon_image weapon_label weapon_ammo aim_label power_bar control_hint].each do |name|
        instance_variable_set("@#{name}", node)
      end
      %i[power_minus power_plus fuse_button fire_button pass_button].each do |name|
        instance_variable_set("@#{name}", Burrow::Client::GlossButton.new(node, node, :blue, flat: true))
      end
      @wind_chevrons = {1 => Array.new(3) { node }, -1 => Array.new(3) { node }}
      @team_hud = state["teams"].to_h do |team|
        [team["id"], {bar: node, width: 120, health: node, members: node, marker: node}]
      end
    end
    def node = Drawable.new.tap { |node| drawables << node }
    def active_worm = state["worms"].find { |w| w["id"] == state["active"] }
    def my_id = "p0"
    def my_turn? = state["team"] == my_id && @connection_status == "online"
    def my_inventory = state["teams"].find { |team| team["id"] == my_id }["inventory"]
    def writes = drawables.sum { |node| node.writes.length }
    def control(name) = instance_variable_get("@#{name}")
  end

  def test_unchanged_hud_refresh_sends_no_properties_but_status_and_actions_still_update
    hud = HUD.new(JSON.parse(JSON.generate(game.snapshot)))
    hud.refresh_match_hud
    count = hud.writes
    6.times { hud.refresh_match_hud }
    assert_equal count, hud.writes, "an unchanged HUD must not resend its styles, paths or button text"
    hud.state["seconds"] = 9
    hud.instance_variable_set(:@pending_action, 42)
    hud.refresh_match_hud
    assert_equal "09", hud.control(:clock_label).text
    assert_equal "#ff5a45", hud.control(:clock_label).stroke
    assert_equal "Sending…", hud.control(:fire_button).text
    assert_equal "disabled", hud.control(:fire_button).state
    hud.instance_variable_set(:@connection_status, "reconnecting")
    hud.instance_variable_set(:@status_message, "Rejoining")
    hud.refresh_match_hud
    refute hud.control(:connection_overlay).hidden
    assert_equal "Rejoining", hud.control(:reconnect_label).text
    hud.instance_variable_set(:@connection_status, "online")
    hud.refresh_match_hud
    assert hud.control(:connection_overlay).hidden
  end

  def test_minimap_only_moves_marks_when_their_rounded_pixels_change
    scene = Burrow::Client::Scene.allocate
    worm = {"id" => "a", "x" => 500.0, "y" => 400.0, "hp" => 100}
    mark = Drawable.new
    frame, water, shot, caption = Array.new(4) { Drawable.new }
    camera = Burrow::Client::Camera.new(4800, 1600)
    {state: {"worms" => [worm], "projectiles" => [], "water" => 1400}, scale: 1, ui_scale: 1,
      width: 4800, height: 1600, camera: camera, map_x: 1122, map_y: 572, map_w: 286, map_h: 95.0,
      map_marks: {"a" => mark}, map_frame: frame, map_water: water, map_shot: shot,
      camera_caption: caption}.each { |key, value| scene.instance_variable_set("@#{key}", value) }
    scene.send(:render_navigation)
    nodes = [mark, frame, water, shot, caption]
    initial = nodes.sum { |n| n.writes.length }
    worm["x"] += 0.01
    scene.send(:render_navigation)
    assert_equal initial, nodes.sum { |n| n.writes.length }
    worm["x"] += 100
    scene.send(:render_navigation)
    assert_equal initial + 1, nodes.sum { |n| n.writes.length }
    assert_equal((1122 + worm["x"] / 4800 * 286 - 2).round, mark.left)
    worm["hp"] = 0
    scene.send(:render_navigation)
    assert mark.hidden
    camera.pan(100, 0)
    scene.send(:render_navigation)
    assert_match(/FREE/, caption.text)
    assert_equal((1122 + 100.0 / 4800 * 286).round, frame.left)
  end

  def test_outline_visibility_and_partial_styles_retain_the_visible_values
    nodes = Array.new(5) { Drawable.new(text: "Grub", hidden: false) }
    outlined = Burrow::Client::Outlined.new(nodes)
    2.times { outlined.hide }
    2.times { outlined.show }
    assert nodes.all? { |node| !node.hidden && node.writes.length == 2 }
    widget = Object.new.extend(Burrow::Client::Widgets)
    node = Drawable.new(left: 10, top: 20, width: 30, height: 40)
    widget.restyle(node, left: 10, top: 21, width: 30, height: 41)
    assert_equal [{top: 21, height: 41}], node.writes
    assert_equal [10, 21, 30, 41], [node.left, node.top, node.width, node.height]
  end
end
