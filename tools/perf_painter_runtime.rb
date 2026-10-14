# frozen_string_literal: true

# Metadata-only preloader for existing native benchmarks. No method tracing,
# GC profiler, or background sampler. PERF_PAINTER_RUNTIME_DIR receives one JSON
# file per Ruby process on normal exit. A terminated terrain worker may not flush.
at_exit do
  if ENV["PERF_PAINTER_RUNTIME_DIR"]
    require_relative "perf_painter_support"
    FileUtils.mkdir_p(ENV.fetch("PERF_PAINTER_RUNTIME_DIR"))
    File.write(File.join(ENV.fetch("PERF_PAINTER_RUNTIME_DIR"), "#{Process.pid}.json"),
      JSON.pretty_generate(PainterPerf.metadata.merge(program: $PROGRAM_NAME,
        rss_kib: PainterPerf.rss, gc: GC.stat)) + "\n")
  end
end
