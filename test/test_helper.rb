# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "timeout"
require "stringio"
require_relative "../lib/burrow"

module GameTestHelpers
  def game(options = {}, players: 2, bots: false, **extra)
    options = options.merge(extra)
    members = players.times.map { |i| {id: "p#{i}", name: Burrow::TEAM_NAMES[i], bot: bots} }
    config = Burrow::Config.new({"mines" => 0, "barrels" => 0, "crates" => false, "worms" => 2}.merge(options))
    Burrow::Match.new(players: members, config: config)
  end

  def wait_for(seconds: 6)
    deadline = Burrow.clock + seconds
    loop do
      value = yield
      return value if value
      raise "Condition did not become true within #{seconds}s" if Burrow.clock >= deadline
      sleep 0.015
    end
  end
end

class Minitest::Test
  include GameTestHelpers
end
