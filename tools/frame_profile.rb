# frozen_string_literal: true

# Opt-in measurement at the Ruby/renderer boundary. No hooks run in the game.
# Allocation and GC counters are process-wide (a connection decode can overlap
# an update); CPU time is for the calling thread. Nested method totals overlap.
require "objspace"

module FrameProfile
  class << self
    attr_accessor :stage

    def install
      @samples, @decodes, @props, @duplicates, @known = [], [], 0, 0, {}
      @native_counts = Hash.new(0)
      @stages = {}
      if ENV["BURROW_BENCH_SCHED"] == "1" && RUBY_PLATFORM.include?("linux")
        @schedstat = "/proc/self/task/#{Thread.current.native_thread_id}/schedstat"
      end
      wrap(Burrow::Client::App, %i[update update_connection update_controls refresh_match_hud play_event])
      wrap(Burrow::Client::Scene, %i[render render_camera render_backdrop render_actors render_projectiles render_hazards update_terrain reconcile_actors
        reconcile_objects build_label restyle_label render_aim render_effects render_navigation
        resize_world resize_actor place_tile cache_frame event float_text sprite_effect add_particle
        render_overlays fx_frames outlined_effect comic pop drown])
      wrap(Burrow::Client::Timeline, %i[sample accept])
      Scarpe::Native::Child.prepend(Module.new do
        def post(message)
          FrameProfile.message(message)
          super
        end
      end)
      Burrow::Protocol.singleton_class.prepend(Module.new do
        def decode(line, **options)
          return super unless FrameProfile.stage
          at, cpu = FrameProfile.clock, FrameProfile.cpu
          allocated = GC.stat(:total_allocated_objects)
          result = super
          FrameProfile.decode(line, result, at, cpu, allocated)
          result
        end
      end)
    end

    def cpu = Process.clock_gettime(Process::CLOCK_THREAD_CPUTIME_ID)
    def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    def wrap(klass, methods)
      prefix = klass.name.split("::").last
      klass.prepend(Module.new do
        methods.each do |method|
          name = "#{prefix}##{method}"
          define_method(method) do |*args, **kwargs, &block|
            return super(*args, **kwargs, &block) unless FrameProfile.stage
            FrameProfile.measure(name) { super(*args, **kwargs, &block) }
          end
        end
      end)
    end

    def measure(name)
      queued = scheduler_wait if @schedstat && name == "App#update"
      at, cost = clock, cpu
      allocated, minor, major, gc = GC.stat(:total_allocated_objects), GC.stat(:minor_gc_count), GC.stat(:major_gc_count), GC.stat(:time)
      props, duplicates = @props, @duplicates
      creates, destroys, reparents = @native_counts.values_at(:create, :destroy, :reparent)
      result = yield
      elapsed, used = (clock - at) * 1000, (cpu - cost) * 1000
      waited = scheduler_wait - queued if queued
      @samples << [Time.now.to_f, stage, name, elapsed, used,
        GC.stat(:total_allocated_objects) - allocated, @props - props, @duplicates - duplicates,
        GC.stat(:minor_gc_count) - minor, GC.stat(:major_gc_count) - major, GC.stat(:time) - gc, waited,
        @native_counts[:create] - creates, @native_counts[:destroy] - destroys, @native_counts[:reparent] - reparents]
      result
    end

    # Optional Linux diagnosis of scheduler delays, distinct from sleeping for
    # another Ruby thread's GVL. Reading procfs adds overhead: leave it off for
    # the main before/after comparison.
    def scheduler_wait = File.read(@schedstat).split[1].to_i / 1_000_000.0

    def message(message)
      id = message[:id]
      case message[:t]
      when "create"
        @native_counts[:create] += 1
        @known[id] = message[:props].dup
      when "props"
        previous = (@known[id] ||= {})
        same = true
        message[:props].each do |key, value|
          same = false unless previous.key?(key) && previous[key] == value
          previous[key] = value
        end
        @props += 1
        @duplicates += 1 if same
      when "destroy", "reparent"
        @native_counts[message[:t].to_sym] += 1
        @known.delete(id) if message[:t] == "destroy"
      end
    end

    def decode(line, result, at, cost, allocated)
      @decodes << [Time.now.to_f, stage, result["type"], line.bytesize, (clock - at) * 1000,
        (cpu - cost) * 1000, GC.stat(:total_allocated_objects) - allocated]
    end

    def start(name)
      self.stage = name
      @stages[name] = {before: GC.stat, objects_before: ObjectSpace.count_objects, native_before: @native_counts.dup}
    end

    def finish
      @stages.fetch(stage).merge!(after: GC.stat, objects_after: ObjectSpace.count_objects, native_after: @native_counts.dup)
      self.stage = nil
    end

    def report
      {columns: %w[at stage method wall_ms cpu_ms allocated_objects props duplicate_props minor_gc major_gc gc_ms runqueue_ms creates destroys reparents],
        samples: @samples, decode_columns: %w[at stage type bytes wall_ms cpu_ms allocated_objects], decodes: @decodes,
        stages: @stages,
        caveats: "Opt-in hooks add overhead; nested totals overlap; allocation/GC counters include all GUI-process threads. ObjectSpace counts are live objects at stage boundaries, not allocation counts."}
    end
  end
end
