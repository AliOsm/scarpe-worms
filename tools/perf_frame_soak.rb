# frozen_string_literal: true

# The existing real-time combat soak, with bounded App frame samples and GC
# pause telemetry (no nested FrameProfile hooks). Run in the tree being tested:
#   PERF_AGENT=frame TMPDIR=... bench mise exec ruby@4.0.7 -- env \
#     SCARPE_DISPLAY_SERVICE=native SCARPE_NATIVE_HEADLESS=1 \
#     BURROW_SOAK_SECONDS=150 BURROW_SOAK_OUTPUT=/captures/soak.json \
#     bundle exec ./bin/scarpe tools/perf_frame_soak.rb
# GC::Profiler and the outer frame hook add some overhead. This is a longevity
# and pause diagnostic, not an uninstrumented latency benchmark. Use the normal
# check_rendering.py run for the latter. Linux null audio is not acoustic output.
require "json"
require "fileutils"
require "scarpe"
require "scarpe/native"
require_relative "../lib/burrow"
require_relative "../lib/burrow/client/app"

ENV["BURROW_SOAK_OUTPUT"] ||= File.join(Burrow::ROOT, ".cache/frame-soak/report.json")

module FrameSoakTelemetry
  LIMIT = 18_000
  SAMPLES = []

  def update
    wall = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    cpu = Process.clock_gettime(Process::CLOCK_THREAD_CPUTIME_ID)
    allocated, minor, major, gc = GC.stat(:total_allocated_objects), GC.stat(:minor_gc_count), GC.stat(:major_gc_count), GC.stat(:time)
    result = super
    SAMPLES << [Time.now.to_f, page, (Process.clock_gettime(Process::CLOCK_MONOTONIC) - wall) * 1000,
      (Process.clock_gettime(Process::CLOCK_THREAD_CPUTIME_ID) - cpu) * 1000,
      GC.stat(:total_allocated_objects) - allocated, GC.stat(:minor_gc_count) - minor,
      GC.stat(:major_gc_count) - major, GC.stat(:time) - gc]
    SAMPLES.shift if SAMPLES.length > LIMIT
    result
  end
end

Burrow::Client::App.prepend(FrameSoakTelemetry)
GC::Profiler.enable
at_exit do
  path = ENV.fetch("BURROW_SOAK_OUTPUT")
  telemetry = {columns: %w[at page wall_ms cpu_ms allocated_objects minor_gc major_gc gc_ms],
    samples: FrameSoakTelemetry::SAMPLES, gc_pauses: GC::Profiler.raw_data, final_gc: GC.stat,
    limit: FrameSoakTelemetry::LIMIT, source: Burrow::ROOT,
    caveats: "Outer App hook and GC::Profiler add overhead. Allocations/GC include all GUI-process threads; CPU is the GUI thread. No acoustic or physical display measurement."}
  FileUtils.mkdir_p(File.dirname(path))
  # Keep diagnostic samples even if the soak's gameplay/retention check fails.
  File.write(path + ".frames.json", JSON.generate(telemetry) + "\n")
  if File.file?(path)
    report = JSON.parse(File.read(path))
    report["frame_telemetry"] = telemetry
    File.write(path, JSON.pretty_generate(report) + "\n")
  end
end
load File.join(__dir__, "check_soak.rb")
