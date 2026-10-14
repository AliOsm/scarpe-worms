# frozen_string_literal: true
require_relative "test_helper"
require_relative "../lib/burrow/client/theme"
require_relative "../lib/burrow/client/scene"

class FrameEffectPoolTest < Minitest::Test
  # Retain a tree like Shoes does: reparenting to the same parent appends the
  # child, and removing a stack removes its paragraphs. Native fixtures check
  # the renderer's actual ordering as well.
  class Node
    attr_reader :children, :removed, :parent
    attr_accessor :left, :top, :width, :height, :size, :text, :stroke, :hidden

    def initialize(shoes, **styles)
      @shoes, @children = shoes, []
      style(**styles)
    end

    def style(**styles) = styles.each { |key, value| instance_variable_set("@#{key}", value) }
    def move(left, top) = style(left: left, top: top)
    def hide = @hidden = true
    def show = @hidden = false
    def append(&block) = @shoes.inside(self, &block)

    def set_parent(parent)
      @parent&.children&.delete(self)
      @parent = parent
      parent&.children&.push(self)
    end

    def remove
      children.dup.each(&:remove)
      set_parent(nil)
      @removed = true
    end
  end

  class Shoes
    def inside(parent)
      previous, @parent = @parent, parent
      yield
    ensure
      @parent = previous
    end

    def stack(**styles, &block)
      node = Node.new(self, **styles)
      node.set_parent(@parent)
      inside(node, &block) if block
      node
    end

    def para(text, **styles) = stack(text: text, **styles)
  end

  def scene
    scene = Burrow::Client::Scene.allocate
    shoes = Shoes.new
    {shoes: shoes, effect_layer: shoes.stack, effects: [], scale: 1, ui_scale: 1}.each do |key, value|
      scene.instance_variable_set("@#{key}", value)
    end
    scene
  end

  def caption(scene, text, at:, life: 1, size: 18, colors: ["#ffffff", "#000000"])
    Burrow.stub(:clock, at) { scene.fx_caption(text, 500, 300, life: life, size: size, colors: colors) }
    scene.instance_variable_get(:@effects).last[:node]
  end

  def test_expired_text_is_hidden_and_reappears_above_effects_created_since_it
    view = scene
    first = caption(view, "OLD", at: 0)
    live = caption(view, "STILL HERE", at: 0.5, life: 5)
    view.send(:render_effects, 1.1)
    assert first.hidden
    refute first.removed
    reused = caption(view, "NEW", at: 1.2, colors: ["#ff0000", "#0000ff"])
    assert_same first, reused
    refute reused.hidden
    assert_equal [live, reused], view.instance_variable_get(:@effect_layer).children
    assert_equal ["NEW"] * 5, reused.children.map(&:text)
    assert_equal ["#0000ff"] * 4 + ["#ff0000"], reused.children.map(&:stroke)
    view.send(:render_effects, 2.3)
    assert reused.hidden
    refute live.hidden, "the recycled caption keeps its new lifetime"
  end

  def test_reuse_after_zoom_matches_a_fresh_caption_including_text_bounds
    view = scene
    Burrow.stub(:clock, 0) { view.send(:float_text, "-55", 900, 600, ["#ffff00", "#000000"]) }
    view.send(:render_effects, 2)
    view.instance_variable_set(:@scale, 0.4)
    reused = caption(view, "KABOOM!", at: 3, size: 22)
    fresh_view = scene
    fresh_view.instance_variable_set(:@scale, 0.4)
    fresh = caption(fresh_view, "KABOOM!", at: 3, size: 22)
    [fresh, *fresh.children].zip([reused, *reused.children]).each do |expected, actual|
      %i[left top width height size text stroke].each do |property|
        value = expected.public_send(property)
        value.nil? ? assert_nil(actual.public_send(property), property.to_s) : assert_equal(value, actual.public_send(property), property.to_s)
      end
    end
  end

  def test_both_live_effects_and_expired_caption_nodes_remain_bounded
    view = scene
    140.times { |i| caption(view, i.to_s, at: 0) }
    effects = view.instance_variable_get(:@effects)
    assert_equal 100, effects.length
    layer = view.instance_variable_get(:@effect_layer)
    assert_equal 100, layer.children.count { |node| !node.hidden }
    view.send(:render_effects, 2)
    assert_empty effects
    assert_equal Burrow::Client::Scene::EFFECT_TEXT_POOL_LIMIT, layer.children.length
    assert layer.children.all?(&:hidden)
    assert_equal 5 * layer.children.length, layer.children.sum { |node| node.children.length }
  end

  def test_nontext_effects_are_removed_on_expiry
    view = scene
    node = Node.new(Shoes.new)
    view.send(:retain_effect, node: node, born: 0, life: 1, kind: :particle)
    view.send(:render_effects, 2)
    assert node.removed
  end

  def test_quiet_preparation_builds_one_hidden_caption_at_a_time_and_reuses_it
    view = scene
    view.send(:prepare_effect_text)
    layer = view.instance_variable_get(:@effect_layer)
    assert_equal 1, layer.children.length
    prepared = layer.children.first
    assert prepared.hidden
    assert_empty view.instance_variable_get(:@effects)
    reused = caption(view, "55", at: 0)
    assert_same prepared, reused
    refute reused.hidden
    assert_equal ["55"] * 5, reused.children.map(&:text)
    view.send(:prepare_effect_text)
    assert_equal 1, layer.children.length, "preparation waits for a quiet frame"
    view.send(:render_effects, 2)
    30.times { view.send(:prepare_effect_text) }
    assert_equal Burrow::Client::Scene::EFFECT_TEXT_POOL_LIMIT, layer.children.length
    assert layer.children.all?(&:hidden)
  end
end
