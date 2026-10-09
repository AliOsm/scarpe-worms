# frozen_string_literal: true

require "json"
require "securerandom"
require "digest"
require "fileutils"

module Burrow
  ROOT = File.expand_path("..", __dir__)
  VERSION = "0.3.0"
  PROTOCOL = 3
  TICK_RATE = 30
  DT = 1.0 / TICK_RATE
  # Legacy checkpoint dimensions; new matches carry their own world size.
  WIDTH = 1440
  HEIGHT = 720
  COLORS = %w[#ef765e #61bdba #edc56a #ac98cf #82b67f #7faade].freeze
  TEAM_NAMES = ["Chili Crew", "Tidal Trouble", "Honey Badgers", "Plum Punks", "Moss Mob", "Blue Moon"].freeze
  GRUB_NAMES = %w[Pip Noodle Beans Pickle Waffles Spud Miso Pebble Sprout Biscuit Tango Pudding].freeze
  class RuleError < StandardError; end

  def self.clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  def self.data_dir
    return ENV["BURROW_DATA_DIR"] if ENV["BURROW_DATA_DIR"]
    base = if RUBY_PLATFORM.include?("darwin")
      File.join(Dir.home, "Library/Application Support")
    elsif RUBY_PLATFORM.match?(/mingw|mswin/)
      ENV.fetch("LOCALAPPDATA", Dir.home)
    else
      ENV.fetch("XDG_DATA_HOME", File.join(Dir.home, ".local/share"))
    end
    File.join(base, "burrow-brigade")
  end

  def self.atomic_json(path, value)
    FileUtils.mkdir_p(File.dirname(path), mode: 0o700)
    temporary = "#{path}.#{Process.pid}.#{SecureRandom.hex(4)}.tmp"
    File.open(temporary, "w:UTF-8", 0o600) do |file|
      file.write(JSON.generate(value))
      file.flush
      file.fsync
    end
    File.rename(temporary, path)
  ensure
    File.unlink(temporary) if temporary && File.exist?(temporary)
  end
end

require_relative "burrow/catalog"
require_relative "burrow/config"
require_relative "burrow/terrain"
require_relative "burrow/match"
