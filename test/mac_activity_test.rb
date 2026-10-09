# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/burrow/mac_activity"

class MacActivityTest < Minitest::Test
  class Backend
    attr_reader :begun, :ended
    def initialize = (@begun, @ended = [], [])
    def begin_activity(options, reason)
      token = Object.new
      @begun << [options, reason, token]
      token
    end
    def end_activity(token) = @ended << token
  end

  def test_transitions_hold_one_token_and_release_it_when_inactive
    backend = Backend.new
    activity = Burrow::MacActivity.new("Match", backend: backend)
    60.times { activity.active = true }
    assert activity.active?
    assert_equal 1, backend.begun.size
    60.times { activity.active = false }
    refute activity.active?
    assert_equal [backend.begun[0][2]], backend.ended
    activity.active = true
    activity.close
    activity.close
    assert_equal 2, backend.begun.size
    assert_equal backend.begun.map(&:last), backend.ended
    assert_equal 2, activity.report[:activations]
  end

  def test_precision_is_scoped_to_timers_and_never_blocks_system_or_display_sleep
    [true, false].each do |precise|
      backend = Backend.new
      activity = Burrow::MacActivity.new("Match", precise: precise, backend: backend)
      activity.active = true
      flags = backend.begun[0][0]
      assert_equal 0, flags & (1 << 20), "Must allow idle system sleep"
      assert_equal 0, flags & (1 << 40), "Must allow idle display sleep"
      assert_equal precise, (flags & Burrow::MacActivity::LATENCY_CRITICAL) != 0
      activity.close
    end
  end

  def test_platform_failure_is_reported_once_without_breaking_the_game
    backend = Object.new
    calls = 0
    backend.define_singleton_method(:begin_activity) { |*| calls += 1; raise "Unavailable" }
    activity = Burrow::MacActivity.new("Match", backend: backend)
    _, error = capture_io { 60.times { activity.active = true } }
    assert_equal 1, calls
    refute activity.active?
    assert_match(/Unavailable/, activity.report[:error])
    assert_match(/macOS activity unavailable/, error)
    activity.close
  end
end
