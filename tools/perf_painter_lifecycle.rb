# frozen_string_literal: true
# Worker lifecycle/collision correctness probe; run under heavy, with
# PERF_AGENT=painter, scratch TMPDIR, BURROW_BENCH_SOURCE and PERF_PAINTER_OUTPUT.
# Exercises close while busy, a worker crash, abrupt parent exit, repeated
# matches and bounded tile retention. Timings here are deadlines, not benchmarks.
require_relative "perf_painter_support"
require "tmpdir"
require "rbconfig"
require File.join(PainterPerf.source, "lib/burrow")
require File.join(PainterPerf.source, "lib/burrow/client/terrain_art")

def await_condition
  deadline = PainterPerf.clock + 15
  loop do
    value = yield
    return value if value
    raise "Worker deadline exceeded" if PainterPerf.clock > deadline
    sleep 0.01
  end
end

def alive?(pid)
  Process.kill(0, pid)
  true
rescue Errno::ESRCH
  false
end

def result_for(art, terrain, biome = "meadow")
  art.request(terrain.export, biome)
  result = await_condition do
    raise art.error if art.error
    art.poll
  end
  raise "Collision mismatch" unless result[:preview_terrain].data == terrain.data && result[:checksum] == terrain.checksum
  raise "Revision mismatch" unless result[:revision] == terrain.revision
  result
end

def await_painting(art)
  await_condition do
    raise art.error if art.error
    Dir[File.join(art.directory, "tile-*.png")].any?
  end
  raise "Expected an unfinished paint" if art.poll
end

if ARGV.first == "--parent"
  STDOUT.sync = true
  art = Burrow::Client::TerrainArt.new
  art.request(Burrow::Terrain.new(seed: 615, width: 4800, height: 1600).export, "meadow")
  pid = await_condition { art.instance_variable_get(:@pid) }
  await_painting(art)
  puts JSON.generate(pid: pid, directory: art.directory)
  sleep 30
  exit
end

checks = []
5.times do |i|
  art = Burrow::Client::TerrainArt.new
  art.request(Burrow::Terrain.new(seed: i + 615, width: 4800, height: 1600).export, "meadow")
  pid = await_condition { art.instance_variable_get(:@pid) }
  await_painting(art)
  art.close
  raise "Close left a process" if alive?(pid)
  raise "Close left files" if File.exist?(art.directory)
end
checks << {id: "busy-close", cycles: 5, pass: true}

art = Burrow::Client::TerrainArt.new
terrain = Burrow::Terrain.new(seed: 615, width: 4800, height: 1600)
art.request(terrain.export, "meadow")
pid = await_condition { art.instance_variable_get(:@pid) }
await_painting(art)
Process.kill("KILL", pid)
await_condition { art.error && !art.instance_variable_get(:@thread).alive? }
raise "Crashed worker was not reaped" if alive?(pid)
art.close
raise "Crash close left files" if File.exist?(art.directory)
checks << {id: "worker-kill", error: art.error, pass: true}

# A killed parent cannot remove its own directory; the operating system closes
# both pipe ends, and the painter must exit after its bounded current job.
paths = $LOAD_PATH.map(&:b).join(File::PATH_SEPARATOR)
if RUBY_PLATFORM.include?("linux")
  # Reap the orphan ourselves even in containers whose PID 1 delays reaping.
  require "fiddle"
  prctl = Fiddle::Function.new(Fiddle::Handle::DEFAULT["prctl"], [Fiddle::TYPE_INT, *[Fiddle::TYPE_LONG] * 4], Fiddle::TYPE_INT)
  raise "Could not become subreaper" unless prctl.call(36, 1, 0, 0, 0).zero?
end
IO.popen([RbConfig.ruby, "-I", paths, __FILE__, "--parent"], "r") do |io|
  state = JSON.parse(io.gets)
  Process.kill("KILL", io.pid)
  Process.waitpid(io.pid)
  await_condition do
    if RUBY_PLATFORM.include?("linux")
      Process.waitpid(state.fetch("pid"), Process::WNOHANG)
    else
      !alive?(state.fetch("pid"))
    end
  end
  raise "Parent crash left a worker" if alive?(state.fetch("pid"))
  checks << {id: "parent-kill", worker_running: false, directory: "harness removed after crash", pass: true}
  FileUtils.remove_entry(state.fetch("directory"))
end

max_files = 0
3.times do |match|
  art = Burrow::Client::TerrainArt.new
  terrain = Burrow::Terrain.new(seed: 615 + match, width: 1450, height: 726)
  10.times do |revision|
    # Keep changing the same four boundary tiles to exercise version retirement.
    terrain.bridge(384, 382, width: 140, height: 20)
    terrain.carve(382 + revision, 390, 16 + revision)
    result = result_for(art, terrain, Burrow::Config::CHOICES.fetch("biome")[match])
    files = Dir.children(art.directory).length
    raise "Unbounded tile files" if files > result[:tiles].length * 3 + 4
    max_files = [max_files, files].max
  end
  pid = art.instance_variable_get(:@pid)
  art.close
  raise "Rematch left worker/files" if alive?(pid) || File.exist?(art.directory)
end
checks << {id: "repeated-match", matches: 3, revisions: 30, max_files: max_files, pass: true}
PainterPerf.write(scenario: "lifecycle", checks: checks)
