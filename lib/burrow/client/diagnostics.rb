# frozen_string_literal: true

require "fileutils"
require "time"

module Burrow
  module Client
    module Diagnostics
      # A bounded timeline to distinguish loading/menus from an active match,
      # and slow rendering from missing host snapshots. No player data is logged.
      class FrameLog
        LIMIT = 10_000
        COLUMNS = %w[at interval_ms update_ms scene_ms page phase focused host_tick playback_tick underruns terrain_revision mac_activity backlog_ms playback_resyncs].freeze

        def initialize(directory: ENV["SCARPE_NATIVE_STATS"])
          @directory = directory unless directory.to_s.empty?
          @samples, @count = [], 0
        end

        def record(started, page:, focused:, state:, scene:, activity:)
          return unless @directory
          now = Burrow.clock
          timeline = scene&.timeline
          @samples[@count % LIMIT] = [Time.now.to_f, @previous && (started - @previous) * 1000,
            (now - started) * 1000, scene&.last_frame_ms, page.to_s, state && state["phase"], focused,
            state && state["tick"], timeline&.tick, timeline&.underruns, scene&.terrain_revision, activity.active?,
            timeline&.backlog_ms, timeline&.resyncs]
          @previous = started
          @count += 1
        end

        def write(activity:)
          return unless @directory
          first = @count % LIMIT
          samples = @count < LIMIT ? @samples : @samples.drop(first) + @samples.take(first)
          Burrow.atomic_json(File.join(@directory, "game.json"), version: Burrow::VERSION, platform: RUBY_PLATFORM,
            columns: COLUMNS, frames: samples, total_updates: @count, sample_limit: LIMIT,
            sample_policy: "most_recent", mac_activity: activity.report)
        rescue SystemCallError => error
          warn "Gameplay log unavailable: #{error.message}"
        end
      end

      # Local timings only. Keep three sessions, with each renderer retaining
      # only its latest 10,000 frames. Explicit benchmark directories take priority.
      def self.start
        return if ENV.key?("SCARPE_NATIVE_STATS")

        root = File.join(ENV.fetch("BURROW_LOG_DIR") { File.join(Dir.home, "Library/Logs/Burrow Brigade") }, "performance")
        FileUtils.mkdir_p(root, mode: 0o700)
        name = "session-#{Time.now.utc.strftime('%Y%m%dT%H%M%S')}-#{Process.pid}"
        directory = File.join(root, name)
        FileUtils.mkdir_p(directory, mode: 0o700)
        sessions = Dir.children(root).grep(/\Asession-\d{8}T\d{6}-\d+\z/).sort.reverse
        sessions.drop(3).each { |old| FileUtils.remove_entry(File.join(root, old)) unless old == name }
        File.write(File.join(directory, "session.json"), JSON.pretty_generate(
          version: Burrow::VERSION, ruby: RUBY_VERSION, platform: RUBY_PLATFORM,
          started_utc: Time.now.utc.iso8601, frame_sample_limit: 10_000) + "\n")
        ENV["SCARPE_NATIVE_STATS"] = directory
      rescue SystemCallError => error
        warn "Performance log unavailable: #{error.message}"
      end
    end
  end
end
