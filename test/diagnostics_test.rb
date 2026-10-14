# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/burrow/client/diagnostics"
require_relative "../lib/burrow/mac_activity"

class DiagnosticsTest < Minitest::Test
  def test_log_directory_follows_platform_conventions_and_explicit_overrides
    diagnostics = Burrow::Client::Diagnostics
    assert_equal "/users/Pip/Library/Logs/Burrow Brigade",
      diagnostics.log_dir(platform: "arm64-darwin", env: {}, home: "/users/Pip")
    assert_equal "C:/Users/Zoë Q/AppData/Local/Burrow Brigade/Logs",
      diagnostics.log_dir(platform: "x64-mingw-ucrt", env: {"LOCALAPPDATA" => "C:/Users/Zoë Q/AppData/Local"})
    assert_equal "/state/burrow-brigade/logs",
      diagnostics.log_dir(platform: "x86_64-linux", env: {"XDG_STATE_HOME" => "/state"})
    assert_equal "/users/Pip/.local/state/burrow-brigade/logs",
      diagnostics.log_dir(platform: "x86_64-linux", env: {}, home: "/users/Pip")
    assert_equal "/users/Pip/.local/state/burrow-brigade/logs",
      diagnostics.log_dir(platform: "x86_64-linux", env: {"XDG_STATE_HOME" => ""}, home: "/users/Pip")
    %w[arm64-darwin x64-mingw-ucrt x86_64-linux].each do |platform|
      assert_equal "/custom/logs", diagnostics.log_dir(platform: platform, env: {"BURROW_LOG_DIR" => "/custom/logs"})
    end
  end

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
