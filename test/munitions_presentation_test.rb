# frozen_string_literal: true
require_relative "test_helper"
require_relative "../lib/burrow/client/theme"
require_relative "../lib/burrow/client/scene"

class MunitionsPresentationTest < Minitest::Test
  class Drawable
    attr_accessor :left, :top, :width, :height, :path, :hidden, :strokewidth, :size
    attr_reader :removed, :writes
    def initialize(**values)
      @writes = 0
      values.each { |key, value| instance_variable_set("@#{key}", value) }
    end
    def style(**values)
      @writes += 1
      values.each { |key, value| instance_variable_set("@#{key}", value) }
    end
    def move(left, top) = style(left: left, top: top)
    def show = @hidden = false
    def hide = @hidden = true
    def remove = @removed = true
    def append = yield
  end

  class Shoes
    attr_reader :images
    def initialize = @images = []
    def stack(**values)
      yield
      Drawable.new(**values)
    end
    def image(path, **values) = Drawable.new(path: path, **values).tap { |node| @images << node }
  end

  Controller = Struct.new(:motion) { def motion? = motion }
  Timeline = Struct.new(:tick, :events)

  def test_bomber_survives_zoom_at_its_current_position_from_either_side
    [-1, 1].each do |side|
      scene, shoes = build_scene
      strike(scene, side: side)
      scene.send(:render_strike)
      plane = shoes.images.last
      assert_match(/bomber-#{side < 0 ? 'left' : 'right'}-0\.png\z/, plane.path)
      scene.timeline.tick = 30
      scene.send(:render_strike)
      assert_equal 600 + side * 95 - 72, plane.left

      transient = Drawable.new
      scene.instance_variable_get(:@effects) << {node: transient}
      scene.camera.zoom_by(1)
      scene.instance_variable_set(:@scale, scene.camera.zoom)
      scene.send(:resize_world)
      scene.send(:render_strike)
      assert transient.removed, "ordinary effects still clear on zoom"
      refute plane.removed, "the aircraft must survive until its pass ends"
      assert_equal 180, plane.width
      assert_in_delta 600 + side * 95, (plane.left + plane.width / 2.0) / scene.camera.zoom, 0.5
      assert_equal 2, shoes.images.size, "one backdrop and one retained aircraft"
    end
  end

  def test_window_rebuild_keeps_the_pass_age_without_replaying_the_event
    scene, = build_scene
    scene.timeline.tick = 45
    strike(scene) # A delayed event must start at the current presentation age.
    scene.send(:render_strike)
    saved = scene.take_presentation
    rebuilt, shoes = build_scene(presentation: saved)
    rebuilt.send(:render_strike)
    plane = shoes.images.last
    assert_same scene.timeline, rebuilt.timeline
    assert_in_delta 600 + 95 * 1.5, plane.left + plane.width / 2.0, 0.5

    # A stalled host leaves the plane aligned with the unreleased bombs.
    old_position, writes = plane.left, plane.writes
    rebuilt.send(:render_camera, nil, 1_000)
    rebuilt.send(:render_strike)
    assert_equal old_position, plane.left
    assert_equal writes, plane.writes

    rebuilt.timeline.tick = 90
    rebuilt.send(:render_strike)
    assert plane.hidden, "the original pass deadline survives a rebuild"
    assert_nil rebuilt.instance_variable_get(:@strike_focus)
  end

  def test_reduced_motion_hides_the_aircraft_without_restarting_its_pass
    scene, shoes, controller = build_scene
    strike(scene)
    scene.send(:render_strike)
    plane = shoes.images.last
    controller.motion = false
    scene.send(:render_strike)
    assert plane.hidden
    scene.timeline.tick = 60
    controller.motion = true
    scene.send(:render_strike)
    refute plane.hidden
    assert_equal 600 + 190 - 72, plane.left
    assert_equal 2, shoes.images.size
  end

  def test_effect_created_after_the_frame_timestamp_keeps_its_first_frame
    scene, = build_scene
    node = Drawable.new(path: "first")
    scene.instance_variable_get(:@effects) << {node: node, born: 10.001, life: 0.5,
      kind: :frames, paths: %w[first last], fps: 16, frame: 0}
    scene.send(:render_effects, 10)
    assert_equal "first", node.path, "a negative age must not select the final burst frame"
    assert_equal 0, scene.instance_variable_get(:@effects).first[:frame]
  end

  private

  def strike(scene, side: 1)
    scene.event("kind" => "strike", "weapon" => "airstrike", "tick" => 0,
      "x" => 600, "y" => -54, "vx" => side * 95, "side" => side, "duration" => 3.0)
  end

  def build_scene(presentation: nil)
    shoes, controller = Shoes.new, Controller.new(true)
    presentation ||= {terrain_art: Object.new, timeline: Timeline.new(0, []),
      camera: Burrow::Client::Camera.new(4800, 1600), hurt_until: {}}
    scene = Burrow::Client::Scene.new(shoes, controller, presentation: presentation)
    {width: 4800, height: 1600, state: {"projectiles" => []}, aim_dots: []}.each do |key, value|
      scene.instance_variable_set("@#{key}", value)
    end
    %i[world terrain_layer props_layer actor_layer overlay_layer shot_layer effect_layer aim_layer
      reticle placement active_arrow].each { |name| scene.instance_variable_set("@#{name}", Drawable.new) }
    [scene, shoes, controller]
  end
end
