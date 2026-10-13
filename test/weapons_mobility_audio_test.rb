# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/burrow/client/audio"

class WeaponsMobilityAudioTest < Minitest::Test
  class Recorder < Burrow::Client::Audio
    attr_reader :heard

    def initialize
      @heard = []
    end

    def play(name, **options)
      @heard << [name, options]
      true
    end
  end

  def state(active: {}, projectiles: [])
    {"team" => "p0", "active" => "w0", "worms" => [{"id" => "w0"}.merge(active)],
      "projectiles" => projectiles}
  end

  def predict(audio, type, values, current, sequence = 1)
    audio.local_action(type, values: values, state: current, player: "p0", sequence: sequence, match_id: "m")
  end

  def receipt(sequence = 1)
    {"match" => "m", "player" => "p0", "seq" => sequence}
  end

  def test_mobility_fire_cues_and_authoritative_receipts_are_distinct
    audio = Recorder.new
    %w[rope jetpack parachute].each_with_index do |weapon, index|
      predict(audio, "fire", {weapon: weapon}, state, index + 1)
    end
    predict(audio, "fire", {weapon: "teleport"}, state, 4)
    assert_equal %w[throw launch equip teleport], audio.heard.map(&:first)

    audio.event({"kind" => "fire", "weapon" => "rope", "input" => receipt(1)})
    audio.event({"kind" => "fire", "weapon" => "jetpack", "input" => receipt(2)})
    audio.event({"kind" => "fire", "weapon" => "parachute", "input" => receipt(3)})
    audio.event({"kind" => "teleport", "input" => receipt(4)})
    assert_equal %w[throw launch equip teleport], audio.heard.map(&:first), "matching mobility reports must be suppressed"
  end

  def test_rope_hook_and_release_have_audible_stages
    audio = Recorder.new
    audio.event({"kind" => "rope_hook"})
    predict(audio, "activate", {}, state(active: {"rope" => {"x" => 30, "y" => 20}}), 3)
    audio.event({"kind" => "activate", "stage" => "released", "input" => receipt(3)})
    predict(audio, "activate", {}, state(active: {"jetpack" => true, "fuel" => 42}), 4)
    audio.event({"kind" => "activate", "stage" => "parachute", "input" => receipt(4)})
    assert_equal %w[thwip throw equip], audio.heard.map(&:first)
  end

  def test_jump_releases_rope_and_remote_activation_takes_precedence
    audio = Recorder.new
    predict(audio, "jump", {}, state(active: {"rope" => {}}), 7)
    audio.event({"kind" => "activate", "stage" => "released", "input" => receipt(7)})
    assert_equal ["throw"], audio.heard.map(&:first)
    critter = {"owner" => "p0", "remote" => true, "life" => 90, "kind" => "guided", "stage" => "walking"}
    predict(audio, "activate", {}, state(active: {"rope" => {}}, projectiles: [critter]), 8)
    audio.event({"kind" => "activate", "stage" => "flying", "input" => receipt(8)})
    assert_equal %w[throw launch], audio.heard.map(&:first)
  end

  def test_other_players_and_unrelated_events_still_sound
    audio = Recorder.new
    predict(audio, "fire", {weapon: "rope"}, state, 5)
    audio.event({"kind" => "fire", "weapon" => "rope", "input" => {"match" => "m", "player" => "p1", "seq" => 5}})
    audio.event({"kind" => "rope_hook", "worm" => "w1"})
    assert_equal %w[throw throw thwip], audio.heard.map(&:first)
  end
end
