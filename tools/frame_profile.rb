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
      @stages = {}
      wrap(Burrow::Client::App, %i[update update_connection update_controls refresh_match_hud])
      wrap(Burrow::Client::Scene, %i[render render_camera render_backdrop update_terrain reconcile_actors
        reconcile_objects build_label restyle_label render_aim render_effects render_navigation])
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
      at, cost = clock, cpu
      allocated, minor, major, gc = GC.stat(:total_allocated_objects), GC.stat(:minor_gc_count), GC.stat(:major_gc_count), GC.stat(:time)
      props, duplicates = @props, @duplicates
      result = yield
      @samples << [Time.now.to_f, stage, name, (clock - at) * 1000, (cpu - cost) * 1000,
        GC.stat(:total_allocated_objects) - allocated, @props - props, @duplicates - duplicates,
        GC.stat(:minor_gc_count) - minor, GC.stat(:major_gc_count) - major, GC.stat(:time) - gc]
      result
    end

    def message(message)
      id = message[:id]
      case message[:t]
      when "create"
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
      when "remove"
        @known.delete(id)
      end
    end

    def decode(line, result, at, cost, allocated)
      @decodes << [Time.now.to_f, stage, result["type"], line.bytesize, (clock - at) * 1000,
        (cpu - cost) * 1000, GC.stat(:total_allocated_objects) - allocated]
    end

    def start(name)
      self.stage = name
      @stages[name] = {before: GC.stat, objects_before: ObjectSpace.count_objects}
    end

    def finish
      @stages.fetch(stage).merge!(after: GC.stat, objects_after: ObjectSpace.count_objects)
      self.stage = nil
    end

    def report
      {columns: %w[at stage method wall_ms cpu_ms allocated_objects props duplicate_props minor_gc major_gc gc_ms],
        samples: @samples, decode_columns: %w[at stage type bytes wall_ms cpu_ms allocated_objects], decodes: @decodes,
        stages: @stages,
        caveats: "Opt-in hooks add overhead; nested totals overlap; allocation/GC counters include all GUI-process threads. ObjectSpace counts are live objects at stage boundaries, not allocation counts."}
    end
  end
end
