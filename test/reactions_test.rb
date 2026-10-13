# frozen_string_literal: true
require_relative "test_helper"
require_relative "../lib/burrow/client/theme"
require_relative "../lib/burrow/client/scene"
require_relative "../lib/burrow/client/audio"

# Grubs react to hits and say goodbye: voices, delayed cues, the dying swell,
# the gravestone, drowning and spinning flights. Presentation only.
class ReactionsTest < Minitest::Test
  class Recorder < Burrow::Client::Audio
    attr_reader :heard
    def initialize = @heard = []
    def play(name, **options)
      @heard << [name, options]
      true
    end
    def names = heard.map(&:first)
  end

  def battle(turn: 4, phase: "aiming")
    {"team" => "p0", "phase" => phase, "turn" => turn,
      "teams" => [{"id" => "p0", "color" => 0}, {"id" => "p1", "color" => 3}],
      "worms" => [{"id" => "a", "team" => "p0", "hp" => 80, "x" => 100, "y" => 200},
        {"id" => "b", "team" => "p1", "hp" => 20, "x" => 400, "y" => 200},
        {"id" => "c", "team" => "p1", "hp" => 0, "x" => 700, "y" => 200}]}
  end

  # Delayed cues are flushed every frame; a stalled frame drops stale ones.
  def advance(audio, from, to)
    from.step(to, 0.05) { |now| Burrow.stub(:clock, now) { audio.update } }
  end

  # Lines are chosen by a roll on the event id, so every player hears the same one.
  def event_where(audio, salt, base)
    (1..500).map { |id| base.merge("id" => id) }.find { |event| yield audio.send(:roll, event, salt) }
  end

  def test_hits_squeak_in_the_victims_voice_and_a_fatal_hit_says_goodbye_instead
    audio = Recorder.new
    pitch = Burrow::Client::Audio::SQUEAK_PITCH[3]
    Burrow.stub(:clock, 50) do
      audio.event({"id" => 1, "kind" => "damage", "worm" => "b", "amount" => 12}, state: battle)
      audio.event({"id" => 2, "kind" => "damage", "worm" => "b", "amount" => 34}, state: battle)
      audio.event({"id" => 3, "kind" => "damage", "worm" => "b", "amount" => 60}, state: battle)
      audio.event({"id" => 4, "kind" => "damage", "worm" => "c", "amount" => 60}, state: battle)
    end
    assert_equal %w[squeak-oof squeak-ow squeak-yelp], audio.names
    assert_equal [pitch] * 3, audio.heard.map { |entry| entry.last[:pitch] }
    refute audio.heard.first.last[:throttle], "several grubs caught in one blast may all squeak"
  end

  def test_a_badly_hurt_grub_calls_for_a_medic_unless_someone_is_already_talking
    audio = Recorder.new
    audio.instance_variable_set(:@seconds, {"squeak-oof" => 0.22})
    calls = event_where(audio, 1, {"kind" => "damage", "worm" => "b", "amount" => 10}) { |roll| roll < 50 }
    Burrow.stub(:clock, 10) { audio.event(calls, state: battle) }
    advance(audio, 10, 11)
    assert_equal %w[squeak-oof vo-medic-f], audio.names
    assert_equal Burrow::Client::Audio::VOICES[3][1], audio.heard.last.last[:pitch]

    busy = Recorder.new
    busy.instance_variable_set(:@seconds, {"squeak-oof" => 0.22, "vo-go-go-go-m" => 2.0})
    Burrow.stub(:clock, 20) do
      busy.event(calls, state: battle)
      busy.voice_line("go-go-go", 0, chatter: false) # a long line already playing
    end
    advance(busy, 20, 21)
    assert_equal %w[squeak-oof vo-go-go-go-m], busy.names, "chatter never talks over another line"
  end

  def test_a_fallen_grub_pops_into_its_grave_and_the_last_of_a_team_gets_a_sad_trombone
    audio = Recorder.new
    Burrow.stub(:clock, 100) do
      audio.event({"id" => 9, "kind" => "defeat", "worm" => "b", "x" => 400, "y" => 200}, state: battle)
    end
    assert_equal ["squeak-byebye"], audio.names
    advance(audio, 100, 100.65)
    assert_equal %w[squeak-byebye pop poof], audio.names
    advance(audio, 100.65, 100.75)
    assert_equal "thud", audio.names.last
    advance(audio, 100.75, 101.4)
    assert_includes audio.names, "sad-trombone", "team p1 has no grub left standing"
  end

  def test_drowning_wails_and_bubbles_and_two_quick_falls_are_a_multi_kill_once
    audio = Recorder.new
    state = battle
    Burrow.stub(:clock, 200) do
      audio.event({"id" => 20, "kind" => "splash", "worm" => "b", "x" => 400, "y" => 600}, state: state)
      audio.event({"id" => 21, "kind" => "defeat", "worm" => "a", "x" => 100, "y" => 200}, state: state)
    end
    assert_equal %w[splash squeak-wah squeak-byebye], audio.names
    advance(audio, 200, 201.1)
    assert_includes audio.names, "blub"
    assert_equal 1, audio.names.count("ann-multi-kill")
    Burrow.stub(:clock, 201.2) do
      audio.event({"id" => 22, "kind" => "defeat", "worm" => "c", "x" => 700, "y" => 200}, state: state)
    end
    advance(audio, 201.2, 203)
    assert_equal 1, audio.names.count("ann-multi-kill"), "announced once per burst"
  end

  def test_a_predicted_swing_whooshes_at_once_and_the_hosts_hit_adds_the_bonk
    audio = Recorder.new
    receipt = {"match" => "m", "player" => "p0", "seq" => 3}
    audio.local_action("fire", values: {weapon: "bat"}, state: {"team" => "p0"}, player: "p0", sequence: 3, match_id: "m")
    audio.event({"kind" => "melee", "style" => "bat", "hits" => ["b"], "input" => receipt})
    audio.event({"kind" => "melee", "style" => "prod", "hits" => [], "input" => receipt})
    audio.event({"kind" => "melee", "style" => "dragon_punch", "hits" => [], "continuing" => true})
    audio.event({"kind" => "melee", "style" => "dragon_punch", "hits" => ["b"], "continuing" => true})
    assert_equal %w[whoosh bonk pow], audio.names
  end

  def test_match_start_victories_draws_and_sudden_death_are_announced
    audio = Recorder.new
    Burrow.stub(:clock, 0) do
      audio.event({"id" => 1, "kind" => "turn", "team" => "p0"}, state: battle(turn: 1))
      audio.event({"id" => 2, "kind" => "flood"}, state: battle)
      audio.event({"id" => 3, "kind" => "flood"}, state: battle)
    end
    advance(audio, 0, 1)
    assert_equal %w[turn ann-fight ann-sudden-death], audio.names

    flawless = battle
    flawless["worms"].each { |worm| worm["hp"] = 50 if worm["team"] == "p0" }
    Burrow.stub(:clock, 10) { audio.event({"id" => 4, "kind" => "victory", "team" => "p0"}, state: flawless) }
    advance(audio, 10, 13)
    assert_equal %w[victory vo-you-win-m squeak-yay ann-flawless-victory], audio.names.last(4)
    Burrow.stub(:clock, 20) { audio.event({"id" => 5, "kind" => "victory"}, state: battle) }
    advance(audio, 20, 21)
    assert_equal "ann-its-a-tie", audio.names.last
  end

  def test_grenades_can_earn_a_fire_in_the_hole_in_the_throwers_voice
    audio = Recorder.new
    shout = event_where(audio, 9, {"kind" => "fire", "weapon" => "grenade", "worm" => "a"}) { |roll| roll < 45 }
    quiet = event_where(audio, 9, {"kind" => "fire", "weapon" => "grenade", "worm" => "a"}) { |roll| roll >= 45 }
    Burrow.stub(:clock, 5) do
      audio.event(shout, state: battle)
      audio.event(quiet, state: battle)
    end
    advance(audio, 5, 5.5)
    assert_equal %w[throw throw vo-fire-in-the-hole-m], audio.names
  end

  def test_runtime_reaction_contracts_match_the_generated_art
    manifest = JSON.parse(File.read(File.join(Burrow::Client::Theme::ART, "manifest.json")))
    art = manifest.fetch("ordnance").fetch("reactions")
    assert_equal Burrow::Client::Sprites::REACTION_SIZES.keys.sort, art.keys.sort
    Burrow::Client::Sprites::REACTION_SIZES.each do |name, (width, height, ax, ay, frames, fps)|
      spec = art.fetch(name)
      assert_equal [[width, height], [ax, ay], frames, fps], [spec["size"], spec["anchor"], spec["frames"], spec["fps"]], name
      Burrow::Client::Sprites::REACTION_FRAMES.fetch(name).each { |path| assert File.file?(path), path }
    end
    states = manifest.fetch("grubs").fetch("states")
    %w[tumble dying drown grave].each do |state|
      count, fps = Burrow::Client::Scene::ANIMATIONS.fetch(state)
      assert_equal [count, fps], states.fetch(state).values_at("frames", "fps"), state
    end
    assert_equal Burrow::Client::Scene::DYING, Burrow::Client::Audio::DYING
    assert_in_delta Burrow::Client::Scene::DYING, states["dying"]["frames"].fdiv(states["dying"]["fps"]), 0.001
    Burrow::Client::Scene::DROWN_FRAMES.flatten.each { |path| assert File.file?(path), path }
  end

  # ---- Scene ---------------------------------------------------------------

  class Drawable
    attr_accessor :left, :top, :width, :height, :path, :hidden, :layers
    def initialize(**values) = values.each { |key, value| instance_variable_set("@#{key}", value) }
    def style(**values) = values.each { |key, value| instance_variable_set("@#{key}", value) }
    def move(left, top) = style(left: left, top: top)
    def hide = @hidden = true
    def show = @hidden = false
    def remove = @removed = true
    def append = yield
    def transform(*) = nil
    def rotate(*) = nil
    def rotate_angle = 0
  end

  class Shoes
    attr_reader :images
    def initialize = @images = []
    def image(path, **values) = Drawable.new(path: path, **values).tap { |node| @images << node }
    def stack(**values)
      yield if block_given?
      Drawable.new(**values)
    end
    def para(text, **values) = Drawable.new(text: text, **values)
  end

  class GraveScene < Burrow::Client::Scene
    attr_reader :pops
    def initialize(state, motion: true)
      @state, @positions, @hurt_until = state, {}, {}
      @deaths, @struck_at, @dizzy_until, @effects, @pops = {}, {}, {}, [], []
      @scale = @ui_scale = 1
      @camera = Burrow::Client::Camera.new(4800, 1600)
      @controller = Struct.new(:target, :motion) { def motion? = motion }.new([-1000, -1000], motion)
      @shoes = Shoes.new
      @effect_layer = @sink_layer = Drawable.new
      @actors = state["worms"].to_h do |w|
        [w["id"], {team: 3, slot: Drawable.new, image: Drawable.new, badge: Drawable.new}]
      end
    end
    def cache_frame(_path); end
    def pop(x, y, now) = @pops << [x, y, now]
    def frame(now)
      camera.update(nil, dt: 1, animate: false)
      @scale = @ui_scale * camera.zoom
      render_actors(now)
    end
    def pose(id) = File.basename(@actors.fetch(id)[:image].path.to_s, ".png")
  end

  def arena_state(**worm)
    {"phase" => "aiming", "water" => 1500, "teams" => [{"id" => "p1", "color" => 3}],
      "worms" => [{"id" => "w", "team" => "p1", "name" => "Pip", "hp" => 0, "max_hp" => 100,
        "x" => 600.0, "y" => 600.0, "vx" => 0.0, "vy" => 0.0, "facing" => -1}.merge(worm)]}
  end

  def test_a_fallen_grub_swells_then_pops_and_rests_in_a_gravestone_read_from_the_front
    scene = GraveScene.new(arena_state)
    scene.send(:react, {"kind" => "defeat", "worm" => "w"}, 100.0)
    scene.frame(100.31)
    assert_equal "3-dying-3", scene.pose("w")
    assert_match %r{grubs/left/}, scene.instance_variable_get(:@actors)["w"][:image].path, "the swell faces the way the grub did"
    assert_empty scene.pops
    scene.frame(100.62)
    assert_equal "3-grave-0", scene.pose("w")
    assert_equal [[600.0, 600.0, 100.62]], scene.pops
    scene.frame(102)
    assert_equal "3-grave-3", scene.pose("w")
    refute_match %r{grubs/left/}, scene.instance_variable_get(:@actors)["w"][:image].path
    assert_equal 1, scene.pops.length, "a grub pops once"
  end

  def test_graves_already_standing_skip_the_animation_and_sunk_ones_are_hidden
    scene = GraveScene.new(arena_state)
    scene.frame(50)
    assert_equal "3-grave-3", scene.pose("w")
    assert_empty scene.pops

    sunk = GraveScene.new(arena_state("sunk" => true))
    sunk.frame(50)
    assert sunk.instance_variable_get(:@actors)["w"][:slot].hidden

    still = GraveScene.new(arena_state, motion: false)
    still.send(:react, {"kind" => "defeat", "worm" => "w"}, 50.0)
    still.frame(50.1)
    assert_equal "3-grave-3", still.pose("w"), "reduced motion goes straight to the resting grave"
  end

  def test_blasted_grubs_spin_while_flying_and_big_hits_leave_them_seeing_stars
    scene = GraveScene.new(arena_state("hp" => 40, "vy" => -220.0, "vx" => 140.0))
    scene.send(:react, {"kind" => "damage", "worm" => "w", "amount" => 30, "x" => 600, "y" => 578}, 10.0)
    scene.frame(10.5)
    assert_match(/\A3-tumble-\d\z/, scene.pose("w"))
    assert_operator scene.instance_variable_get(:@dizzy_until)["w"], :>, 12
    looks = Burrow::Client::Sprites.overlays({"hp" => 40, "facing" => 1, "_dizzy" => true}, 15)
    assert_match %r{ordnance/reactions/dizzy-\d\.png\z}, looks.first.path
    scene.frame(14)
    refute_match(/tumble/, scene.pose("w"), "the spin ends after the flight")
    assert_match %r{ordnance/reactions/sweat-\d\.png\z},
      Burrow::Client::Sprites.overlays({"hp" => 12, "facing" => 1}, 3).first.path, "a grub on its last legs sweats"
    assert_empty Burrow::Client::Sprites.overlays({"hp" => 0, "facing" => 1}, 3)
  end

  def test_drowning_grubs_sink_beneath_the_water_and_leave_no_grave
    scene = GraveScene.new(arena_state("y" => 1512.0))
    sink = Drawable.new
    scene.instance_variable_set(:@sink_layer, sink)
    Burrow.stub(:clock, 30.0) do
      scene.send(:react, {"kind" => "splash", "worm" => "w", "x" => 600, "y" => 1500}, 30.0)
    end
    drowning = scene.instance_variable_get(:@effects).find { |effect| effect[:paths]&.first&.include?("drown") }
    assert drowning, "the drowning grub is drawn"
    assert_operator drowning[:vy], :>, 0, "and sinks"
    assert_match %r{grubs/left/3-drown-0\.png\z}, drowning[:paths].first
    scene.frame(30.2)
    assert scene.instance_variable_get(:@actors)["w"][:slot].hidden
  end

  def test_comic_words_are_rationed
    scene = GraveScene.new(arena_state("hp" => 50))
    3.times { |i| scene.send(:react, {"kind" => "explosion", "x" => 500, "y" => 500, "radius" => 92}, 5.0 + i * 0.1) }
    scene.send(:react, {"kind" => "explosion", "x" => 500, "y" => 500, "radius" => 40}, 6.0)
    scene.send(:react, {"kind" => "melee", "style" => "bat", "hits" => ["w"], "x" => 500, "y" => 500, "facing" => 1}, 7.0)
    captions = scene.instance_variable_get(:@effects).select { |effect| effect[:kind] == :caption }
    assert_equal 2, captions.length, "one KABOOM per burst of blasts, nothing for small ones, then BONK"
  end
end
