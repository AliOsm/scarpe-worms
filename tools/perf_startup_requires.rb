# frozen_string_literal: true

# Optional attribution probe: RUBYOPT=-r/absolute/tools/perf_startup_requires.rb.
# Output: PERF_STARTUP_OUTPUT.requires-PID.json. Only Kernel#require is wrapped:
# require_relative keeps its original caller-relative lookup. Inclusive nested
# costs overlap. Do not use these profiled runs for acceptance decisions.
startup_requires = []
Kernel.prepend(Module.new do
  define_method(:require) do |path|
    at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    cost = Process.clock_gettime(Process::CLOCK_THREAD_CPUTIME_ID)
    loaded = super(path)
    if loaded
      startup_requires << {path: path, wall_ms: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - at) * 1000,
        cpu_ms: (Process.clock_gettime(Process::CLOCK_THREAD_CPUTIME_ID) - cost) * 1000}
    end
    loaded
  end
end)
at_exit do
  if ENV["PERF_STARTUP_OUTPUT"]
    require "json"
    File.write("#{ENV.fetch('PERF_STARTUP_OUTPUT')}.requires-#{Process.pid}.json",
      JSON.pretty_generate(program: $PROGRAM_NAME, pid: Process.pid, requires: startup_requires,
        yjit_available: defined?(RubyVM::YJIT), yjit: defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?,
        yjit_stats: defined?(RubyVM::YJIT) && RubyVM::YJIT.runtime_stats,
        gc: GC.stat) + "\n")
  end
end
