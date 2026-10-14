# frozen_string_literal: true
# Uninstrumented hot-path cost/allocations, including native mixer CPU. Use the
# exclusive bench wrapper, same Ruby, and >=5 interleaved arms. Set
# BURROW_BENCH_SOURCE for source, SCARPE_NATIVE_STATS for shipping log on/off.
# --scenario play is deliberately saturated (20,000 submissions, no sleeps);
# --scenario queue is 200,000 frames with a future cue; --scenario frame measures
# 200,000 frame-log hooks. These are cost probes, not game/acoustic latency.
require "optparse"
require "json"
options = {scenario: "play"}
OptionParser.new do |p|
  p.on("--scenario NAME") { |v| options[:scenario] = v }
  p.on("--output PATH") { |v| options[:output] = v }
end.parse!
ENV["ALSOFT_DRIVERS"] ||= "null" if RUBY_PLATFORM.include?("linux")
root = File.expand_path(ENV.fetch("BURROW_BENCH_SOURCE", ".."), __dir__)
require File.join(root, "lib/burrow")
require File.join(root, "lib/burrow/client/audio")
audio = Burrow::Client::Audio.new({"volume" => 0.4, "muted" => false, "music" => false})
abort "OpenAL unavailable: #{audio.error}" unless audio.available
count = options[:scenario] == "play" ? 20_000 : 200_000
audio.send(:later, "pop", 1000) if options[:scenario] == "queue"
100.times { audio.play("pop", throttle: false) } if options[:scenario] == "play"
GC.start
cpu_clock = Process::CLOCK_THREAD_CPUTIME_ID
allocated = GC.stat(:total_allocated_objects)
collections, gc_ms = GC.stat.values_at(:count, :time)
times = Process.times
cpu, at = Process.clock_gettime(cpu_clock), Burrow.clock
case options[:scenario]
when "play" then count.times { audio.play("pop", throttle: false) }
when "queue" then count.times { audio.update }
when "frame" then count.times { audio.frame(Burrow.clock) }
else abort "Unknown scenario"
end
wall = Burrow.clock - at
thread_cpu = Process.clock_gettime(cpu_clock) - cpu
finished = Process.times
allocated = GC.stat(:total_allocated_objects) - allocated
result = {schema: 1, ruby: RUBY_DESCRIPTION, platform: RUBY_PLATFORM, source: root,
  scenario: options[:scenario], log: !ENV.fetch("SCARPE_NATIVE_STATS", "").empty?, operations: count,
  wall_ms: wall * 1000, thread_cpu_ms: thread_cpu * 1000,
  process_cpu_ms: (finished.utime + finished.stime - times.utime - times.stime) * 1000,
  allocated: allocated, gc_count: GC.stat(:count) - collections, gc_ms: GC.stat(:time) - gc_ms,
  us_per_operation: wall * 1_000_000 / count}
at = Burrow.clock
audio.close
result[:close_ms] = (Burrow.clock - at) * 1000
if result[:log]
  path = File.join(ENV.fetch("SCARPE_NATIVE_STATS"), "audio.json")
  result[:log_bytes] = File.size(path)
  FileUtils.cp(path, options.fetch(:output).sub(/\.json\z/, ".audio.json"))
end
File.write(options.fetch(:output), JSON.pretty_generate(result) + "\n")
puts JSON.generate(result)
