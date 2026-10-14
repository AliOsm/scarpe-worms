# frozen_string_literal: true

# Shared helpers for perf_painter_* probes. These are measurement tools, never
# loaded by the game. Use the round's bench wrapper for every timed invocation.
require "json"
require "fileutils"

module PainterPerf
  module_function

  def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  def cpu = Process.clock_gettime(Process::CLOCK_THREAD_CPUTIME_ID)

  def stats(values)
    sorted = values.sort
    return {n: 0} if sorted.empty?
    {n: sorted.length, median: quantile(sorted, 0.5), p95: quantile(sorted, 0.95),
      min: sorted.first, max: sorted.last, iqr: quantile(sorted, 0.75) - quantile(sorted, 0.25),
      mean: sorted.sum.fdiv(sorted.length)}
  end

  def quantile(sorted, fraction)
    at = (sorted.length - 1) * fraction
    sorted[at.floor] + (sorted[at.ceil] - sorted[at.floor]) * (at - at.floor)
  end

  def rss(pid = Process.pid)
    if File.exist?("/proc/#{pid}/status")
      File.read("/proc/#{pid}/status")[/^VmRSS:\s+(\d+)/, 1].to_i
    elsif RUBY_PLATFORM.include?("darwin")
      IO.popen(["ps", "-o", "rss=", "-p", pid.to_s], &:read).to_i
    end
  rescue Errno::ENOENT, Errno::ESRCH
    nil
  end

  def metadata
    {ruby: RUBY_DESCRIPTION, platform: RUBY_PLATFORM, source: ENV["BURROW_BENCH_SOURCE"],
      yjit: defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?,
      yjit_stats: defined?(RubyVM::YJIT) && RubyVM::YJIT.runtime_stats,
      gc_config: GC.config,
      environment: ENV.to_h.select { |key, _| key.start_with?("RUBY_GC_", "PERF_PAINTER_") || %w[RUBYOPT RUBY_YJIT_ENABLE].include?(key) }}
  end

  def source
    File.expand_path(ENV.fetch("BURROW_BENCH_SOURCE", ".."), __dir__)
  end

  def measure
    at, cost = clock, cpu
    allocated, gc = GC.stat(:total_allocated_objects), GC.total_time
    result = yield
    [result, {wall_ms: (clock - at) * 1000, cpu_ms: (cpu - cost) * 1000,
      allocations: GC.stat(:total_allocated_objects) - allocated, gc_ms: (GC.total_time - gc) / 1e6}]
  end

  def write(report)
    path = ENV.fetch("PERF_PAINTER_OUTPUT")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.pretty_generate(metadata.merge(report)) + "\n")
    puts JSON.generate(output: path, scenario: report[:scenario])
  end
end
