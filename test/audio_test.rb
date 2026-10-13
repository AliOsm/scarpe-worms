# frozen_string_literal: true
require_relative "test_helper"
require_relative "../lib/burrow/client/audio"
require_relative "../lib/burrow/client/app"

class AudioTest < Minitest::Test
  class Recorder < Burrow::Client::Audio
    attr_reader :heard
    def initialize = @heard = []
    def play(name, **options) = @heard << [name, options]
  end

  def test_weapons_have_distinct_reports_without_duplicate_launches
    audio = Recorder.new
    audio.event({"kind" => "fire", "weapon" => "rocket"}, screen_x: 120)
    audio.event({"kind" => "fire", "weapon" => "grenade"}, screen_x: 900)
    audio.event({"kind" => "fire", "weapon" => "laser"})
    audio.event({"kind" => "beam", "style" => "laser"})
    audio.event({"kind" => "fire", "weapon" => "shotgun"})
    audio.event({"kind" => "beam", "style" => "shotgun"})
    assert_equal %w[launch throw beam shot], audio.heard.map(&:first)
    assert_equal 120, audio.heard[0][1][:x]
    assert_equal 900, audio.heard[1][1][:x]
  end

  def test_supplies_and_turn_changes_do_not_sound_like_a_rocket
    audio = Recorder.new
    audio.event({"kind" => "fire", "weapon" => "heal"})
    audio.event({"kind" => "heal"})
    audio.event({"kind" => "fire", "weapon" => "skip"})
    audio.event({"kind" => "turn"})
    audio.event({"kind" => "explosion", "radius" => 40})
    audio.event({"kind" => "explosion", "radius" => 92})
    assert_equal %w[pickup turn explosion explosion-heavy], audio.heard.map(&:first)
  end

  def test_shipped_effects_are_mono_for_positioning_and_music_stays_stereo
    paths = Dir[File.join(Burrow::Client::Audio::ROOT, "*.wav")]
    assert_equal Burrow::Client::Audio::CUES.sort, paths.map { |path| File.basename(path, ".wav") }.sort
    paths.each do |path|
      data = Burrow::Client::Audio.decode_wave(File.binread(path))
      assert_equal File.basename(path) == "music.wav" ? 2 : 1, data[:channels], path
      assert_equal 22_050, data[:rate], path
      assert_operator data[:pcm].bytesize, :>, 0, path
    end
  end

  def test_decoder_handles_metadata_and_odd_sized_riff_chunks
    fmt = [1, 1, 22_050, 44_100, 2, 16].pack("vvVVvv")
    samples = [-10_000, 0, 10_000].pack("s<*")
    body = "WAVE" + chunk("JUNK", "abc") + chunk("fmt ", fmt) + chunk("LIST", "INFO") + chunk("data", samples)
    wav = "RIFF" + [body.bytesize].pack("V") + body
    decoded = Burrow::Client::Audio.decode_wave(wav)
    assert_equal samples, decoded[:pcm]
    assert_equal 1, decoded[:channels]
    assert_equal 22_050, decoded[:rate]
  end

  def test_decoder_rejects_truncated_or_non_pcm_audio
    wav = File.binread(File.join(Burrow::Client::Audio::ROOT, "click.wav"))
    assert_raises(RuntimeError) { Burrow::Client::Audio.decode_wave(wav[0...-4]) }
    unsupported = wav.dup
    unsupported[20, 2] = [3].pack("v") # IEEE float, not PCM.
    assert_raises(RuntimeError) { Burrow::Client::Audio.decode_wave(unsupported) }
    assert_raises(RuntimeError) { Burrow::Client::Audio.decode_wave("RIFF") }
  end

  def test_local_reports_are_immediate_and_only_the_matching_authoritative_cue_is_suppressed
    state = {"team" => "p0", "projectiles" => [{"owner" => "p0", "remote" => true, "life" => 100,
      "kind" => "guided", "stage" => "walking"}]}
    [[:fire, "rocket", {"kind" => "fire", "weapon" => "rocket"}, "launch"],
      [:fire, "grenade", {"kind" => "fire", "weapon" => "grenade"}, "throw"],
      [:fire, "shotgun", {"kind" => "beam", "style" => "shotgun"}, "shot"],
      [:fire, "laser", {"kind" => "beam", "style" => "laser"}, "beam"],
      [:fire, "flamethrower", {"kind" => "beam", "style" => "flame"}, "launch"],
      [:jump, nil, {"kind" => "jump"}, "jump"],
      [:activate, nil, {"kind" => "activate", "stage" => "flying"}, "launch"]].each do |type, weapon, event, cue|
      audio = Recorder.new
      audio.local_action(type.to_s, values: {weapon: weapon}, state: state, player: "p0", sequence: 7, match_id: "m")
      assert_equal [cue], audio.heard.map(&:first), weapon || type
      assert audio.heard.first.last[:immediate]
      # Time/position similarity must never swallow another player's report.
      audio.event(event.merge("input" => {"match" => "m", "player" => "p1", "seq" => 7}))
      assert_equal [cue, cue], audio.heard.map(&:first)
      audio.event(event.merge("input" => {"match" => "m", "player" => "p0", "seq" => 7}))
      assert_equal [cue, cue], audio.heard.map(&:first)
      audio.event(event.merge("input" => {"match" => "m", "player" => "p0", "seq" => 8}))
      assert_equal [cue, cue, cue], audio.heard.map(&:first)
      audio.event(event.merge("input" => {"match" => "m", "player" => "p0", "seq" => 7}))
      assert_equal [cue, cue, cue], audio.heard.map(&:first), "another report from the same input must also be suppressed"
    end
  end

  def test_unacknowledged_predictions_are_bounded_and_do_not_suppress_impacts_or_new_matches
    audio = Recorder.new
    200.times do |seq|
      audio.local_action("fire", values: {weapon: "rocket"}, state: {"team" => "p0"}, player: "p0", sequence: seq, match_id: "m")
    end
    assert_equal 96, audio.instance_variable_get(:@predicted).size
    audio.heard.clear
    audio.event({"kind" => "explosion", "input" => {"match" => "m", "player" => "p0", "seq" => 199}})
    audio.event({"kind" => "fire", "weapon" => "rocket", "input" => {"match" => "new", "player" => "p0", "seq" => 199}})
    assert_equal %w[explosion launch], audio.heard.map(&:first)
  end

  def test_build_events_cannot_repeat_the_local_girder_report
    audio = Recorder.new
    audio.local_action("fire", values: {weapon: "girder"}, state: {"team" => "p0"}, player: "p0", sequence: 1, match_id: "m")
    receipt = {"match" => "m", "player" => "p0", "seq" => 1}
    audio.event({"kind" => "fire", "weapon" => "girder", "input" => receipt})
    audio.event({"kind" => "build", "input" => receipt})
    assert_equal ["clank"], audio.heard.map(&:first)
  end

  class InputHarness < Burrow::Client::App
    def initialize(audio, online: true)
      @audio = audio
      @state, @room = {"team" => "p0"}, {"match_id" => "m"}
      @connection = Struct.new(:sequence, :online).new(0, online)
      def @connection.send_action(*)
        return false unless online
        self.sequence += 1
        true
      end
    end
    def my_id = "p0"
    def notify(*); end
  end

  def test_real_app_input_hook_respects_pending_action_and_failed_send
    audio = Recorder.new
    app = InputHarness.new(audio)
    app.submit_weapon("fire", weapon: "rocket")
    app.submit_weapon("fire", weapon: "rocket")
    app.submit_weapon("activate")
    assert_equal ["launch"], audio.heard.map(&:first)
    assert_equal 1, app.connection.sequence
    assert_equal 1, app.instance_variable_get(:@pending_action)
    InputHarness.new(audio, online: false).submit_weapon("fire", weapon: "rocket")
    assert_equal ["launch"], audio.heard.map(&:first)
  end

  class FakeAL
    attr_reader :calls, :playing
    def initialize
      @calls, @playing = [], {}
    end
    def alGetSourcei(source, _key, pointer) = pointer.read_int = playing[source] ? 0x1012 : 0x1014
    def alSourceStop(source)
      @calls << [:stop, source]
      @playing[source] = false
    end
    def alSourcei(source, _key, buffer) = @calls << [:buffer, source, buffer]
    def alSourcef(*); end
    def alSource3f(*); end
    def alSourcePlay(source)
      @calls << [:play, source]
      @playing[source] = true
    end
  end

  def fake_mixer
    audio = Burrow::Client::Audio.allocate
    al = FakeAL.new
    {preferences: {"volume" => 1, "muted" => false}, available: true, al: al,
      sources: (1..13).to_a, cursor: 0, source_status: Struct.new(:read_int).new,
      buffers: Burrow::Client::Audio::CUES.to_h { |cue| [cue, cue] },
      voice_priority: {}, voice_started: {}, gains: {}, last: {}}.each do |key, value|
      audio.instance_variable_set("@#{key}", value)
    end
    [audio, al]
  end

  def test_immediate_reports_bypass_cue_throttling_and_voice_reuse_stops_before_rebinding
    audio, al = fake_mixer
    Burrow.stub(:clock, 100) do
      audio.play("launch")
      audio.play("launch")
      audio.play("launch", immediate: true)
    end
    assert_equal 2, al.calls.count { |call| call.first == :play }
    (1..12).each { |source| al.playing[source] = true }
    al.calls.clear
    audio.play("explosion")
    source = al.calls.first[1]
    assert_equal [[:stop, source], [:buffer, source, "explosion"], [:play, source]], al.calls
    refute_equal 2, source, "a local report should survive a burst of impact sounds"
    refute_equal 13, source, "effects must never steal the music source"
    al.playing[8] = false
    al.calls.clear
    audio.play("jump", immediate: true)
    assert_equal [:stop, 8], al.calls.first, "use a finished voice before cutting off a playing voice"
  end

  def test_authoritative_attack_reports_are_not_lost_to_the_ambient_cue_throttle
    audio, al = fake_mixer
    Burrow.stub(:clock, 100) do
      2.times { |id| audio.event({"id" => id, "kind" => "beam", "style" => "burst"}) }
      2.times { |id| audio.event({"id" => id + 2, "kind" => "explosion"}) }
    end
    assert_equal 2, al.calls.count { |call| call.first == :buffer && call.last == "shot" }
    assert_equal 1, al.calls.count { |call| call.first == :buffer && call.last == "explosion" }
  end

  private

  def chunk(name, bytes)
    name + [bytes.bytesize].pack("V") + bytes + (bytes.bytesize.odd? ? "\0" : "")
  end
end
