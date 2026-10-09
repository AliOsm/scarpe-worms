# frozen_string_literal: true
require_relative "test_helper"
require_relative "../lib/burrow/client/audio"

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

  private

  def chunk(name, bytes)
    name + [bytes.bytesize].pack("V") + bytes + (bytes.bytesize.odd? ? "\0" : "")
  end
end
