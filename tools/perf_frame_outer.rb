# frozen_string_literal: true

# Run check_frame_work.rb with only outer Scene/HUD timing/allocation probes.
# Unlike FrameProfile's attribution mode, this retains one sample per frame and
# does not inspect native messages or wrap inner methods. This checks whether
# GC/frame tails seen with the full profiler survive its removal. Example:
#   PERF_AGENT=frame TMPDIR=... bench mise exec ruby@3.4.7 -- env \
#     SCARPE_DISPLAY_SERVICE=native SCARPE_NATIVE_HEADLESS=1 \
#     BURROW_BENCH_SOURCE=/source BURROW_FRAME_OUTPUT=/captures/outer \
#     bundle exec ./bin/scarpe tools/perf_frame_outer.rb
# BURROW_OUTER_SCENARIO=reactions selects the reaction fixture instead.
require_relative "frame_profile"

module OuterFrameProfile
  def install
    @samples, @stages = [], {}
    Burrow::Client::Scene.prepend(Module.new do
      def render
        return super unless FrameProfile.stage
        FrameProfile.capture_outer("Scene#render") { super }
      end
    end)
    Burrow::Client::App.prepend(Module.new do
      def refresh_match_hud
        return super unless FrameProfile.stage
        FrameProfile.capture_outer("App#refresh_match_hud") { super }
      end
    end)
  end

  def capture_outer(method)
    at, used = clock, cpu
    allocated, minor, major, gc = GC.stat(:total_allocated_objects), GC.stat(:minor_gc_count), GC.stat(:major_gc_count), GC.stat(:time)
    result = yield
    @samples << [Time.now.to_f, stage, method, (clock - at) * 1000, (cpu - used) * 1000,
      GC.stat(:total_allocated_objects) - allocated, GC.stat(:minor_gc_count) - minor,
      GC.stat(:major_gc_count) - major, GC.stat(:time) - gc]
    result
  end

  def start(name)
    self.stage = name
    @stages[name] = {before: GC.stat}
  end

  def finish
    @stages.fetch(stage)[:after] = GC.stat
    self.stage = nil
  end

  def report
    {probe: "outer-frame-v1", columns: %w[at stage method wall_ms cpu_ms allocated_objects minor_gc major_gc gc_ms],
      samples: @samples, stages: @stages, ruby: RUBY_VERSION, platform: RUBY_PLATFORM,
      caveats: "Outer probes add overhead, but no nested method/native-message hooks run. Allocations/GC include all GUI-process threads; CPU is the calling thread. Native message counts are not measured."}
  end
end

FrameProfile.singleton_class.prepend(OuterFrameProfile)
require_relative(ENV["BURROW_OUTER_SCENARIO"] == "reactions" ? "perf_frame_reactions" : "check_frame_work")
