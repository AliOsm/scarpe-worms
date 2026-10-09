# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/burrow/client/diagnostics"
require_relative "../lib/burrow/mac_activity"

class DiagnosticsTest < Minitest::Test
  def test_frame_log_keeps_recent_updates_in_order_without_player_content
    Dir.mktmpdir do |directory|
      log = Burrow::Client::Diagnostics::FrameLog.new(directory: directory)
      activity = Burrow::MacActivity.new("Test")
      count = Burrow::Client::Diagnostics::FrameLog::LIMIT + 3
      count.times do |i|
        log.record(Burrow.clock, page: :match, focused: true,
          state: {"tick" => i, "phase" => "aiming", "name" => "PRIVATE NAME", "token" => "PRIVATE TOKEN"}, scene: nil, activity: activity)
      end
      log.write(activity: activity)
      raw = File.read(File.join(directory, "game.json"))
      value = JSON.parse(raw)
      assert_equal count, value["total_updates"]
      assert_equal 10_000, value["frames"].length
      tick = value["columns"].index("host_tick")
      assert_equal 3, value["frames"].first[tick]
      assert_equal count - 1, value["frames"].last[tick]
      assert value["frames"].all? { |row| row.length == value["columns"].length }
      refute_includes raw, "PRIVATE"
      assert_equal "most_recent", value["sample_policy"]
      assert value["mac_activity"]["allows_idle_sleep"]
    end
  end
end
