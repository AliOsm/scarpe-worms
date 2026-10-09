# frozen_string_literal: true

require "rbconfig"

module Burrow
  module Server
    # Hosting is independent of the GUI's Ruby VM. AI, checkpoints, compression
    # and six-client broadcasts cannot hold the animation loop's execution lock.
    class ProcessHost
      attr_reader :host, :port, :fingerprint, :pid

      def initialize(**options)
        @host = options.fetch(:host)
        # Ruby's default_external setting does not survive exec. Finder need not
        # provide a UTF-8 locale; worker paths and JSON must not depend on it.
        # Startup RUBYLIB paths can be tagged US-ASCII despite containing UTF-8
        # bytes. Pass filesystem bytes intact, including runtime-added paths.
        load_path = $LOAD_PATH.map(&:b).join(File::PATH_SEPARATOR)
        command = [ENV.fetch("BURROW_RUBY") { RbConfig.ruby }, "-EUTF-8", "-I", load_path, File.join(__dir__, "process_main.rb")]
        @io = IO.popen(command, "r+:UTF-8")
        @pid = @io.pid
        @io.sync = true
        @io.puts(JSON.generate(options))
        raise RuleError, "The host did not start in time." unless IO.select([@io], nil, nil, 8)
        ready = JSON.parse(@io.gets || "{}")
        raise RuleError, ready.fetch("error", "The host could not start.") unless ready["port"]
        @port, @fingerprint = ready.values_at("port", "fingerprint")
      rescue StandardError
        stop
        raise
      end

      def running?
        return false if @stopped
        Process.waitpid(pid, Process::WNOHANG).nil?
      rescue Errno::ESRCH, Errno::ECHILD
        false
      end

      def stop
        return if @stopped
        @stopped = true
        @io&.close_write
        # EOF saves the host and exits. Bound shutdown if a dependency hangs.
        deadline = Burrow.clock + 3
        while @pid && Process.waitpid(@pid, Process::WNOHANG).nil?
          if Burrow.clock > deadline
            Process.kill("TERM", @pid)
            unless IO.select([@io], nil, nil, 1)
              Process.kill("KILL", @pid)
            end
            break
          end
          sleep 0.01
        end
        @io&.close
      rescue IOError, Errno::ECHILD, Errno::ESRCH, Errno::EPIPE
        @io&.close rescue nil
      end
    end
  end
end
