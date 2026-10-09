# frozen_string_literal: true

require "tmpdir"
require "rbconfig"

module Burrow
  module Client
    class TerrainArt
      attr_reader :directory, :error

      def initialize
        @directory = Dir.mktmpdir("burrow-terrain-")
        @mutex, @condition = Mutex.new, ConditionVariable.new
        @result, @job, @stopped = nil, nil, false
        @thread = Thread.new { work }
      end

      def request(terrain, biome)
        # The immutable compressed export is tiny; no per-pixel work on the UI thread.
        @mutex.synchronize do
          @job = {terrain: terrain.is_a?(Hash) ? terrain : terrain.export, biome: biome}
          @condition.signal
        end
      end

      def poll
        @mutex.synchronize do
          value = @result
          @result = nil
          value
        end
      end

      def close
        @mutex.synchronize { @stopped = true; @condition.signal }
        begin
          Process.kill("TERM", @pid) if @pid
        rescue Errno::ESRCH
          nil
        end
        @thread.join(1)
        @thread.kill if @thread.alive?
        FileUtils.remove_entry(directory) if File.directory?(directory)
      end

      private

      def work
        command = [ENV.fetch("BURROW_RUBY") { RbConfig.ruby }, "-EUTF-8", "-I", $LOAD_PATH.join(File::PATH_SEPARATOR), File.join(__dir__, "terrain_worker.rb"), directory]
        IO.popen(command, "r+:UTF-8") do |io|
          @pid = io.pid
          io.sync = true
          loop do
            job = @mutex.synchronize do
              @condition.wait(@mutex) while !@job && !@stopped
              break if @stopped
              value = @job
              @job = nil
              value
            end
            break unless job
            io.puts(JSON.generate(job))
            line = io.gets
            raise IOError, "Terrain renderer exited" unless line
            value = JSON.parse(line, symbolize_names: true)
            @mutex.synchronize { @result = value }
          end
        end
      rescue StandardError => error
        @error = error.message unless @stopped
      ensure
        @pid = nil
      end
    end
  end
end
