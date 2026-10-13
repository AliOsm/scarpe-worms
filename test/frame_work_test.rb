# frozen_string_literal: true
require_relative "test_helper"
require_relative "../lib/burrow/client/theme"
require_relative "../lib/burrow/client/scene"
require_relative "../lib/burrow/client/match_ui"

class FrameWorkTest < Minitest::Test
  # Like Shoes, setters count even when the value did not change. This catches
  # needless pipe traffic at the call sites, without depending on native timing.
  class Drawable
    attr_reader :writes, :removed
    %i[left top width height size stroke strokewidth fill path text state hidden x2 y2].each do |name|
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
    def append = yield
    def remove = @removed = true
  end

  class ActorScene < Burrow::Client::Scene
    def initialize(state)
      @state, @positions, @hurt_until = state, {}, {}
      @scale = @ui_scale = 1
      @camera = Burrow::Client::Camera.new(4800, 1600)
      @controller = Struct.new(:target) { def motion? = false }.new([-1000, -1000])
      @shoes = Object.new
      def @shoes.para(text, **styles) = Drawable.new(text: text, **styles)
      @actors = state["worms"].to_h do |w|
        [w["id"], {team: 0, slot: Drawable.new, image: Drawable.new, badge: Drawable.new}]
      end
    end
    def cache_frame(_path); end
    def frame
      camera.update(nil, dt: 1, animate: false)
      @scale = @ui_scale * camera.zoom
      render_actors(100)
    end
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

  def test_grouped_outline_changes_visibility_without_writing_five_layers
    nodes = Array.new(5) { Drawable.new(text: "Grub", hidden: false) }
    container = Drawable.new(hidden: false)
    outlined = Burrow::Client::Outlined.new(nodes, container: container)
    2.times { outlined.hide }
    assert outlined.hidden
    2.times { outlined.show }
    refute outlined.hidden
    assert_equal [{hidden: true}, {hidden: false}], container.writes
    assert nodes.all? { |node| node.writes.empty? }
    outlined.text = "Grub\n75"
    assert nodes.all? { |node| node.text == "Grub\n75" }
  end

  def test_crowd_names_build_in_small_batches_and_refresh_after_being_hidden
    worms = 12.times.map do |i|
      {"id" => i, "name" => "Grub #{i}", "hp" => 100, "facing" => 1,
        "x" => 100 + i * 95, "y" => 500, "vx" => 0, "vy" => 0}
    end
    scene = ActorScene.new("worms" => worms, "active" => 0, "phase" => "aiming")
    scene.frame
    assert_equal 2, scene.actors.values.count { |node| node[:label] }, "do not construct a crowd of text layers in one frame"
    5.times { scene.frame }
    assert_equal 12, scene.actors.values.count { |node| node[:label] }
    node = scene.actors.fetch(1)
    writes = node[:image].writes.length
    scene.frame
    assert_equal writes, node[:image].writes.length, "a retained pose must not resend its path"
    label_writes = node[:label].layers.sum { |layer| layer.writes.length }
    scene.camera.overview
    scene.frame
    assert node[:label].hidden
    assert_equal label_writes, node[:label].layers.sum { |layer| layer.writes.length }, "hidden names need neither geometry nor five visibility messages"
    assert_equal 1, node[:badge].writes.count { |write| write == {hidden: true} }
    worms[1]["name"], worms[1]["hp"] = "Renamed", 50
    scene.frame
    scene.camera.follow
    scene.camera.update(nil, dt: 1)
    scene.camera.navigate(720, 600)
    scene.frame
    refute node[:label].hidden
    assert node[:label].layers.all? { |layer| layer.text == "Renamed\n50" }
    assert_equal [worms[1]["x"], worms[1]["y"]], scene.positions[1]
    worms[1]["facing"] = -1
    scene.frame
    assert_match(%r{/grubs/left/0-idle-0.png\z}, node[:image].path)
  end

  # Offscreen flames keep their place without cycling frames, and nothing is
  # hidden: visibility toggles during a zoom left half the frames unpainted.
  def test_offscreen_flames_skip_animation_without_toggling_visibility
    scene = Burrow::Client::Scene.allocate
    flame = {"id" => 1, "kind" => "flame", "x" => 2200.0, "y" => 500.0, "radius" => 8}
    gas = {"id" => 2, "kind" => "gas", "x" => 1550.0, "y" => 500.0, "radius" => 200}
    flame_image, gas_image = Drawable.new, Drawable.new
    timeline = Struct.new(:tick).new(0)
    camera = Burrow::Client::Camera.new(4800, 1600)
    controller = Object.new
    def controller.motion? = true
    {scale: 1, camera: camera, controller: controller, timeline: timeline, state: {"hazards" => [flame, gas]},
      hazard_nodes: {1 => {image: flame_image, bounds: [24, 32, 12, 30], phase: 0}, 2 => {image: gas_image}}}.each do |key, value|
      scene.instance_variable_set("@#{key}", value)
    end
    scene.send(:render_hazards)
    refute flame_image.hidden
    refute gas_image.hidden
    path = flame_image.path
    timeline.tick = 7.5
    flame["x"] += 5
    scene.send(:render_hazards)
    assert_equal path, flame_image.path, "an offscreen flame does not swap frames"
    assert_equal 2193, flame_image.left, "but it keeps its place"
    camera.pan(1000, 0)
    scene.send(:render_hazards)
    refute flame_image.hidden
    assert_equal 470, flame_image.top
    assert_equal Burrow::Client::Scene::FLAME_PATHS[3], flame_image.path, "it catches up when it returns"
  end

  def test_zoom_batches_actor_bounds_and_keeps_offscreen_active_marker_metrics
    worms = 2.times.map { |i| {"id" => i, "name" => "Grub", "hp" => 100, "facing" => 1,
      "x" => 2500, "y" => 500, "vx" => 0, "vy" => 0} }
    scene = ActorScene.new("worms" => worms, "active" => 0, "phase" => "aiming")
    scene.frame
    assert_equal 1, scene.actors[0][:scale]
    assert_nil scene.actors[1][:scale], "hidden actors need no geometry until they are visible"
    scene.camera.zoom_by(1)
    scene.frame
    assert_equal 1.25, scene.actors[0][:scale]
    scene.camera.navigate(2500, 500)
    scene.frame
    assert_equal 1.25, scene.actors[1][:scale]
    slot = scene.actors[1][:slot]
    assert slot.writes.any? { |write| write.key?(:left) && write.key?(:width) }, "resize and move share a message"
    assert_equal [slot.left, slot.top], scene.actors[1][:position]
    assert_equal [slot.width, slot.height], [scene.actors[1][:badge].width, scene.actors[1][:badge].height], "grouping must keep the original text clipping bounds"
  end

  def test_world_resize_keeps_combat_effects_until_their_own_expiry
    scene = Burrow::Client::Scene.allocate
    effects = [
      {kind: :particle, x: 100, y: 200, vx: 20, vy: -10, size: 8},
      {kind: :sprite, x: 80, y: 150, width: 60, height: 70, fps: 1, frame: 0},
      {kind: :text, x: 100, y: 200, width: 90, height: 30},
      {kind: :line, x: 10, y: 20, x2: 50, y2: 80, width: 4},
      {kind: :ring, x: 100, y: 200, radius: 40}
    ].map { |effect| effect.merge(node: Drawable.new, born: 100, life: 1) }
    {scale: 0.5, width: 4800, effects: effects, tiles: {}, aim_dots: []}.each do |key, value|
      scene.instance_variable_set("@#{key}", value)
    end
    %i[world terrain_layer props_layer actor_layer shot_layer effect_layer aim_layer reticle placement active_arrow].each do |name|
      scene.instance_variable_set("@#{name}", Drawable.new)
    end
    scene.send(:resize_world)
    assert_equal 5, effects.length
    refute effects.any? { |effect| effect[:node].removed }
    scene.send(:render_effects, 100.25)
    nodes = effects.map { |effect| effect[:node] }
    assert_equal [53, 102, 4, 4], nodes[0].then { |node| [node.left, node.top, node.width, node.height] }
    assert_equal [40, 75, 30, 35], nodes[1].then { |node| [node.left, node.top, node.width, node.height] }
    assert_equal [5, 57], [nodes[2].left, nodes[2].top], "floating damage keeps its readable size and world anchor"
    assert_equal [5, 10, 25, 40, 2], nodes[3].then { |node| [node.left, node.top, node.x2, node.y2, node.strokewidth] }
    assert_equal [41, 91, 18, 18, 3], nodes[4].then { |node| [node.left, node.top, node.width, node.height, node.strokewidth] }
    scene.send(:render_effects, 101)
    assert_empty effects
    assert nodes.all?(&:removed)
  end

  def test_effects_born_during_the_current_frame_start_at_age_zero
    scene = Burrow::Client::Scene.allocate
    sprite = Drawable.new(path: "sparkle-0.png")
    particle = Drawable.new
    effects = [
      {node: sprite, kind: :sprite, name: "sparkle", x: 10, y: 20, width: 30, height: 40, fps: 12, frame: 0},
      {node: particle, kind: :particle, x: 100, y: 200, vx: 400, vy: -100, size: 8}
    ].map { |effect| effect.merge(born: 100.001, life: 1) }
    scene.instance_variable_set(:@scale, 1)
    scene.instance_variable_set(:@effects, effects)
    scene.send(:render_effects, 100)
    assert_equal 0, effects.first[:frame]
    assert_equal "sparkle-0.png", sprite.path, "birth must never load a nonexistent negative animation frame"
    assert_equal [100, 200], [particle.left, particle.top]
    assert_equal 2, effects.length
  end

  def terrain_scene(camera, tiles, ui_scale: 8.0 / 9)
    Burrow::Client::Scene.allocate.tap do |scene|
      {camera: camera, ui_scale: ui_scale, scale: ui_scale * camera.zoom, tiles: tiles}.each do |key, value|
        scene.instance_variable_set("@#{key}", value)
      end
    end
  end

  def test_hidden_terrain_defers_geometry_then_places_exact_edges_before_revealing
    camera = Struct.new(:x, :y, :zoom).new(3000.3, 250.4, 1.0)
    tiles = [0, 3072, 3456].to_h do |x|
      [x, {x: x, y: 384, width: 384, height: 384, node: Drawable.new(hidden: true)}]
    end
    scene = terrain_scene(camera, tiles)
    scene.send(:render_terrain)
    far = tiles.fetch(3072)
    refute far[:node].hidden
    initial_bounds = [far[:node].left, far[:node].top, far[:node].width, far[:node].height]
    camera.x = 0.3
    scene.send(:render_terrain)
    assert far[:node].hidden
    writes = far[:node].writes.length
    camera.zoom = 0.55
    scale = camera.zoom * 8.0 / 9
    scene.instance_variable_set(:@scale, scale)
    3.times { scene.send(:render_terrain) }
    assert_equal writes, far[:node].writes.length, "offscreen scale changes must not send tile properties"
    assert_equal initial_bounds, [far[:node].left, far[:node].top, far[:node].width, far[:node].height]
    camera.x = 2000.7
    scene.send(:render_terrain)
    refute far[:node].hidden
    assert_equal scale, far[:scale]
    assert_equal((3072 * scale).round, far[:node].left)
    assert_equal((3456 * scale).round - (3072 * scale).round, far[:node].width)
    assert_equal far[:node].left + far[:node].width, tiles.fetch(3456)[:node].left, "adjacent tiles share the same rounded edge"
    assert_equal({hidden: false}, far[:node].writes.last)
    assert far[:node].writes[-2].key?(:width), "restore stale bounds before showing the tile"
    writes = tiles.values.sum { |tile| tile[:node].writes.length }
    scene.send(:render_terrain)
    assert_equal writes, tiles.values.sum { |tile| tile[:node].writes.length }, "a retained camera sends no tile properties"
  end

  def test_terrain_culling_keeps_a_margin_on_all_fractional_viewport_edges
    camera = Struct.new(:x, :y, :zoom).new(1000, 400, 0.7)
    positions = {left_edge: [987, 500], left_out: [986, 500], top_edge: [1100, 387], top_out: [1100, 386],
      right_edge: [3060, 500], right_out: [3061, 500], bottom_edge: [1100, 1431], bottom_out: [1100, 1432]}
    tiles = positions.to_h do |id, (x, y)|
      [id, {x: x, y: y, width: 10, height: 10, node: Drawable.new(hidden: true)}]
    end
    scene = terrain_scene(camera, tiles)
    scene.send(:render_terrain)
    %i[left top right bottom].each do |edge|
      refute tiles.fetch(:"#{edge}_edge")[:node].hidden, "retain the #{edge} tile within two logical pixels"
      assert tiles.fetch(:"#{edge}_out")[:node].hidden, "defer the #{edge} tile beyond the conservative margin"
    end
  end

  def test_hidden_terrain_replacement_retains_latest_path_and_geometry_before_reentry
    camera = Struct.new(:x, :y, :zoom).new(0, 0, 1.0)
    old = {id: "far", x: 3072, y: 384, width: 384, height: 384, path: "old.png", scale: 8.0 / 9,
      node: Drawable.new(path: "old.png", hidden: true)}
    tiles = {"far" => old}
    scene = terrain_scene(camera, tiles)
    replacement = {id: "far", x: 3100, y: 390, width: 400, height: 380, path: "new.png"}
    results = [{tiles: [replacement, {id: "new", x: 3600, y: 384, width: 384, height: 384, path: "new-tile.png"}],
      overview: "map-new.png", revision: 2}]
    worker = Object.new
    worker.define_singleton_method(:poll) { results.shift }
    shoes = Object.new
    def shoes.image(path, **styles) = Drawable.new(path: path, **styles)
    {terrain_art: worker, shoes: shoes, terrain_layer: Drawable.new, minimap: Drawable.new,
      loading_label: Drawable.new(hidden: false)}.each { |key, value| scene.instance_variable_set("@#{key}", value) }
    scene.send(:update_terrain)
    scene.send(:render_terrain)
    assert_same old[:node], tiles.fetch("far")[:node]
    assert_equal [{path: "new.png"}], old[:node].writes, "hidden replacement must not resize or reveal the tile"
    assert_nil old[:scale], "changed worker geometry must invalidate the retained scale"
    assert tiles.fetch("new")[:node].hidden
    assert_equal 2, scene.terrain_revision
    camera.x, camera.y, camera.zoom = 2900, 200, 0.7
    scale = camera.zoom * 8.0 / 9
    scene.instance_variable_set(:@scale, scale)
    scene.send(:render_terrain)
    refute old[:node].hidden
    assert_equal "new.png", old[:node].path
    assert_equal [(3100 * scale).round, (390 * scale).round, (3500 * scale).round - (3100 * scale).round,
      (770 * scale).round - (390 * scale).round], old[:node].then { |node| [node.left, node.top, node.width, node.height] }
    assert_equal({hidden: false}, old[:node].writes.last)
    refute tiles.fetch("new")[:node].hidden
    assert_equal scale, tiles.fetch("new")[:scale]
  end
end
