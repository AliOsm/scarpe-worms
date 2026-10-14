# frozen_string_literal: true

# Metadata-only preloader for existing native benchmarks. No method tracing,
# GC profiler, or background sampler. PERF_STARTUP_RUNTIME_DIR receives one JSON
# file per Ruby process on normal exit. A terminated terrain worker may not flush.
at_exit do
  if ENV["PERF_STARTUP_RUNTIME_DIR"]
    require_relative "perf_startup_support"
    FileUtils.mkdir_p(ENV.fetch("PERF_STARTUP_RUNTIME_DIR"))
    File.write(File.join(ENV.fetch("PERF_STARTUP_RUNTIME_DIR"), "#{Process.pid}.json"),
      JSON.pretty_generate(StartupPerf.metadata.merge(program: $PROGRAM_NAME,
        rss_kib: StartupPerf.rss, gc: GC.stat)) + "\n")
  end
end
