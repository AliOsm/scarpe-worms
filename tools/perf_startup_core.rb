# frozen_string_literal: true

# Deterministic terrain, host simulation/snapshot, and checkpoint probes.
# PERF_STARTUP_MODE=terrain|host|verify; PERF_STARTUP_OUTPUT=/absolute/report.json
# BURROW_BENCH_SOURCE=/frozen/tree selects code/assets independently of Bundler.
# Run via: bench mise exec ruby@4.0.7 -- bundle exec ruby tools/perf_startup_core.rb
# "verify" hashes every full checkpoint (including RNG and terrain) separately
# from timing. Host timing includes one JSON snapshot/tick and a save/60 ticks,
# but excludes socket I/O, idle waits, and the separate correctness hashes.
# GC samples are GC.total_time deltas per tick, not individual stop-the-world
# pauses. Compare their distribution together with tick CPU and process RSS.
require_relative "perf_startup_support"
require File.join(StartupPerf.source, "lib/burrow")

mode = ENV.fetch("PERF_STARTUP_MODE", "host")
GC.config(rgengc_allow_full_mark: false) if ENV["PERF_STARTUP_NO_MAJOR"] == "1"
if mode == "terrain"
  count = Integer(ENV.fetch("PERF_STARTUP_SEEDS", "1"))
  sizes = [[1440, 720], [2880, 1280], [3840, 1440], [4800, 1600]]
  rows = []
  count.times do |seed|
    sizes.each do |width, height|
      %w[meadow desert glacier volcano].each do |biome|
        %w[islands archipelago cavern].each do |shape|
          terrain, timing = StartupPerf.measure do
            Burrow::Terrain.new(seed: seed, width: width, height: height, biome: biome, shape: shape)
          end
          rows << timing.merge(seed: seed, width: width, height: height, biome: biome, shape: shape,
            checksum: terrain.checksum, bytes: terrain.data.bytesize)
        end
      end
    end
  end
  StartupPerf.write(scenario: "terrain", rows: rows, rss_kib: StartupPerf.rss,
    summary: %i[wall_ms cpu_ms allocations gc_ms].to_h { |key| [key, StartupPerf.stats(rows.map { |r| r[key] })] })
else
  ticks = Integer(ENV.fetch("PERF_STARTUP_TICKS", "3600"))
  seeds = ENV.fetch("PERF_STARTUP_MATCH_SEEDS", "runtime-0,runtime-1,runtime-2").split(",")
  players = 6.times.map { |i| {id: "p#{i}", name: "Team #{i}", bot: true} }
  reports = seeds.map do |seed|
    match, create = StartupPerf.measure do
      Burrow::Match.new(players: players, config: Burrow::Config.new("worms" => 6, "seed" => seed,
        "turn_seconds" => 15, "retreat_seconds" => 0))
    end
    rows, hashes, memory = [], [], []
    saved = nil
    ticks.times do |index|
      break if match.finished?
      if mode == "verify"
        match.step
        hashes << Digest::SHA256.hexdigest(JSON.generate(match.checkpoint))
      else
        _, row = StartupPerf.measure do
          match.step
          JSON.generate(match.snapshot)
          saved = JSON.generate(match.checkpoint) if index % 60 == 0
        end
        rows << row.values_at(:wall_ms, :cpu_ms, :allocations, :gc_ms)
        memory << [index, StartupPerf.rss, GC.stat(:heap_live_slots)] if index % 300 == 0
      end
    end
    saved ||= JSON.generate(match.checkpoint)
    restored, restore = StartupPerf.measure { Burrow::Match.restore(JSON.parse(saved)) }
    raise "Checkpoint restore changed state" unless JSON.generate(restored.checkpoint) == saved
    {seed: seed, create: create, restore: restore, ticks: match.tick, turn: match.turn,
      terrain_checksum: match.terrain.checksum, final_checkpoint_sha256: Digest::SHA256.hexdigest(JSON.generate(match.checkpoint)),
      tick_hashes: hashes, rows: rows, rss: memory, rss_kib: StartupPerf.rss,
      summary: %i[wall_ms cpu_ms allocations gc_ms].each_with_index.to_h { |key, i| [key, StartupPerf.stats(rows.map { |r| r[i] })] },
      gc_pauses_ms: StartupPerf.stats(rows.map { |r| r[3] }.select(&:positive?))}
  end
  StartupPerf.write(scenario: mode, columns: %w[wall_ms cpu_ms allocations gc_ms],
    matches: reports, gc: GC.stat, rss_kib: StartupPerf.rss)
end
