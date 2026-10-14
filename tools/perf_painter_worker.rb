# frozen_string_literal: true

# Optional attribution preloader, NOT used in paired acceptance captures:
# RUBYOPT=-r/absolute/tools/perf_painter_worker.rb, PERF_PAINTER_OUTPUT=/report
# Writes .spawn-PID.json (GUI) and .worker-PID.json (terrain processes). IO.popen
# measures process/pipe creation, not child Ruby boot. The worker separately
# records entry -> painter class loaded, terrain restore, and painter render.
# Class-definition tracing stops once both worker classes have been discovered.
require_relative "perf_painter_support"

if File.basename($PROGRAM_NAME) == "terrain_worker.rb"
  entered = PainterPerf.clock
  rows, loaded = [], {}
  write = lambda do
    File.write("#{ENV.fetch('PERF_PAINTER_OUTPUT')}.worker-#{Process.pid}.json",
      JSON.pretty_generate(pid: Process.pid, source: PainterPerf.source,
        entered_since_launch_ms: (entered - Float(ENV.fetch("PERF_PAINTER_LAUNCHED"))) * 1000,
        loaded_ms: loaded, rows: rows) + "\n")
  end
  trace = TracePoint.new(:end) do |event|
    klass = event.self
    name = klass.is_a?(Module) && klass.name
    next unless %w[Burrow::Terrain Burrow::Client::TerrainPainter].include?(name)
    next if loaded.key?(name)
    loaded[name] = (PainterPerf.clock - entered) * 1000
    receiver, method = name == "Burrow::Terrain" ? [klass.singleton_class, :restore] : [klass, :render]
    receiver.prepend(Module.new do
      define_method(method) do |*args, **kwargs, &block|
        at = PainterPerf.clock
        value, timing = PainterPerf.measure { super(*args, **kwargs, &block) }
        rows << timing.merge(method: "#{name}##{method}", since_entry_ms: (at - entered) * 1000)
        write.call
        value
      end
    end)
    trace.disable if loaded.length == 2
  end
  trace.enable
  at_exit { write.call }
else
  spawns = []
  IO.singleton_class.prepend(Module.new do
    define_method(:popen) do |*args, **kwargs, &block|
      terrain = args.first.is_a?(Array) && args.first.any? { |value| value.to_s.end_with?("/terrain_worker.rb") }
      if terrain && block
        at, cpu = PainterPerf.clock, PainterPerf.cpu
        super(*args, **kwargs) do |io|
          spawns << {pid: io.pid, wall_ms: (PainterPerf.clock - at) * 1000,
            cpu_ms: (PainterPerf.cpu - cpu) * 1000,
            since_launch_ms: (at - Float(ENV.fetch("PERF_PAINTER_LAUNCHED"))) * 1000}
          block.call(io)
        end
      else
        super(*args, **kwargs, &block)
      end
    end
  end)
  at_exit do
    unless spawns.empty?
      File.write("#{ENV.fetch('PERF_PAINTER_OUTPUT')}.spawn-#{Process.pid}.json",
        JSON.pretty_generate(spawns: spawns) + "\n")
    end
  end
end
