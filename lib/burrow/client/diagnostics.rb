# frozen_string_literal: true

require "fileutils"
require "time"

module Burrow
  module Client
    module Diagnostics
      # Only cue names and timing/category data. No event payloads, players,
      # device names, paths, or free-form backend errors enter this report.
      class AudioLog
        LIMIT = 4096
        COLUMNS = %w[at cue origin lateness_ms frame_interval_ms voices_busy_estimate reason openal_ms submit_ms stolen_cue frame_at].freeze
        attr_accessor :device

        def initialize(directory: ENV["SCARPE_NATIVE_STATS"])
          @directory = directory unless directory.to_s.empty?
          @samples, @count, @totals = [], 0, Hash.new(0)
          @device = {}
        end

        def enabled? = !!@directory

        def frame(now)
          @interval_ms = (now - @frame) * 1000 if @frame
          @frame = now
          @frame_wall = Time.now.to_f
        end

        def record(cue, origin:, due:, at:, reason:, busy: nil, openal_ms: nil, submit_ms: nil, stolen: nil)
          return unless @directory
          @samples[@count % LIMIT] = [Time.now.to_f, cue, origin, (at - due) * 1000,
            @interval_ms, busy, reason, openal_ms, submit_ms, stolen, @frame_wall]
          @count += 1
          @totals[reason] += 1
        end

        def write
          return unless @directory
          first = @count % LIMIT
          samples = @count < LIMIT ? @samples : @samples.drop(first) + @samples.take(first)
          Burrow.atomic_json(File.join(@directory, "audio.json"), schema: 1, version: Burrow::VERSION,
            ruby: RUBY_VERSION, platform: RUBY_PLATFORM, columns: COLUMNS, cues: samples,
            total_cues: @count, totals: @totals, sample_limit: LIMIT, sample_policy: "most_recent",
            device: @device, timing: {
              lateness: "monotonic submission/drop minus due; events due at the Scene sample, delayed cues at their scheduled deadline",
              openal_ms: "source selection plus stop/bind/pitch/gain/position/play block; includes Ruby dispatch, excludes logging",
              voices_busy_estimate: "submitted duration divided by pitch; may differ from the mixer by an output quantum",
              output: "submission only; device properties are reported estimates, not measured acoustic latency"})
        rescue SystemCallError, IOError => error
          warn "Audio timing log unavailable: #{error.class}"
        end
      end

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
