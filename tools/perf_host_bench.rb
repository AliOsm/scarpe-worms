# frozen_string_literal: true

# Deterministic, headless host benchmark for the 0.5.4 performance round.
#
# The harness runs the authoritative Match#step, snapshot construction, and
# the reactor's atomic checkpoint at the live host's 30 Hz logical cadence.
# It runs unpaced: per-tick work is timed, with persistence every 60 ticks.
# Set BURROW_BENCH_SOURCE to an archived source tree to measure that tree with
# this harness (the script itself may remain in the candidate worktree).  Every
# sample records wall and thread CPU time, and every tick records a SHA-256 of
# the complete Match#checkpoint for before/after determinism checks.
# Terrain probes also report cold export (checksum already memoized by snapshot),
# cold checksum and complete
# terrain-bearing JSON line bytes. Those lines are encoded in the timed tick.
# canonical_hashes keep every checkpoint field and canonicalize ONLY its zlib
# representation to default compression, outside the timed region. This lets
# new compression levels compare bit-for-bit with 0.5.3 checkpoint hashes.
#
# Example (all wall-clock captures must use the round's bench wrapper):
#   PERF_AGENT=terrain TMPDIR=<scratch>/terrain/tmp \
#     <scratch>/bin/bench \
#     mise exec ruby@4.0.7 -- bundle exec ruby tools/perf_host_bench.rb \
#       --scenario heavy --teams 6 --ticks 900 --output capture.json

require "digest"
require "fileutils"
require "json"
require "logger"
require "optparse"
require "tmpdir"

SOURCE = File.expand_path(ENV.fetch("BURROW_BENCH_SOURCE", File.join(__dir__, "..")))
$LOAD_PATH.unshift(File.join(SOURCE, "lib"))
require File.join(SOURCE, "lib", "burrow")
require File.join(SOURCE, "lib", "burrow", "server", "reactor")
require File.join(SOURCE, "lib", "burrow", "server", "room")

module PerfHostBench
  module_function

  TICK_BUDGET_MS = 1000.0 / Burrow::TICK_RATE
  HEAVY_WEAPONS = %w[napalm cluster airstrike mine_strike earthquake barrel mine].freeze
  DEFAULT_TICKS = 900

  def monotonic
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def cpu_clock
    Process.clock_gettime(Process::CLOCK_THREAD_CPUTIME_ID)
  end

  def quantile(values, fraction)
    return 0.0 if values.empty?
    sorted = values.sort
    sorted[((sorted.length - 1) * fraction).round]
  end

  def summary(values, unit: "ms")
    if unit != "ms"
      return summary(values).transform_keys { |key| key.sub(/_ms\z/, "_#{unit}") }
    end
    values = values.map(&:to_f)
    return {"n" => 0, "p50_ms" => 0.0, "p95_ms" => 0.0, "p99_ms" => 0.0,
      "max_ms" => 0.0, "min_ms" => 0.0, "iqr_ms" => 0.0} if values.empty?
    q25 = quantile(values, 0.25)
    q75 = quantile(values, 0.75)
    {"n" => values.length,
      "p50_ms" => quantile(values, 0.50).round(4),
      "p95_ms" => quantile(values, 0.95).round(4),
      "p99_ms" => quantile(values, 0.99).round(4),
      "max_ms" => values.max.round(4),
      "min_ms" => values.min.round(4),
      "iqr_ms" => (q75 - q25).round(4)}
  end

  def config_for(seed, teams:, worms:, heavy:)
    # Unlimited cartridges make the heavy script independent of inventory
    # exhaustion while retaining the normal Config validation and game rules.
    ammo = Burrow::Catalog::WEAPONS.keys.to_h { |id| [id, -1] }
    {
      "seed" => seed,
      "worms" => worms,
      "turn_seconds" => 15,
      "retreat_seconds" => 1,
      "round_limit" => heavy ? 30 : 12,
      "mines" => heavy ? 8 : 4,
      "barrels" => heavy ? 8 : 3,
      "crates" => heavy,
      "ammo" => ammo
    }
  end

  def make_match(seed, teams:, worms:, heavy:)
    players = teams.times.map do |i|
      {id: "p#{i}", name: "Bench team #{i + 1}", bot: true}
    end
    config = Burrow::Config.new(config_for(seed, teams: teams, worms: worms, heavy: heavy))
    match = Burrow::Match.new(players: players, config: config)
    if heavy
      # Keep one or more living grubs on every team, while placing graves in
      # the normal world so settle_grave and later blast shoves are exercised.
      match.worms.each_with_index do |worm, index|
        next unless index % 3 == 1
        match.send(:kill, worm, "blast")
      end
      # The scripted driver owns the turn choices.  This prevents the normal
      # bot timer from racing the forced ordnance at the start of a turn.
      # Keep this checkpoint JSON-safe; a floating Infinity is rejected by
      # Ruby's strict JSON generator.
      match.instance_variable_set(:@bot_at, 1 << 60)
    end
    [match, players]
  end

  def room_for(match, players)
    host = {id: players.first[:id], name: players.first[:name], room: "BENCH01", last_seq: 0, seen_at: Time.now.to_i}
    room = Burrow::Server::Room.new(code: "BENCH01", host: host, name: "Performance bench", config: match.config.to_h)
    members = players.map { |player| player.merge(ready: true, connected: true) }
    room.instance_variable_set(:@members, members)
    room.instance_variable_set(:@match, match)
    room.instance_variable_set(:@match_id, "bench-match")
    room.instance_variable_set(:@input_events, {})
    room
  end

  def reactor_for(room, data_dir)
    reactor = Burrow::Server::Reactor.new(host: "127.0.0.1", port: 0, data_dir: data_dir, logger: Logger.new(File::NULL))
    reactor.rooms[room.code] = room
    reactor
  end

  def close_reactor(reactor)
    reactor.instance_variable_get(:@listener)&.close unless reactor.instance_variable_get(:@listener)&.closed?
    reactor.instance_variable_get(:@data_lock)&.close
  rescue IOError, SystemCallError
    nil
  end

  def nearest_target(match)
    active = match.active
    target = match.worms.find { |w| w[:hp] > 0 && w[:team] != active[:team] }
    target || {x: (active[:x] + active[:facing] * 240).clamp(50, match.world_width - 50), y: active[:y] - 20}
  end

  def heavy_command(match)
    active = match.active
    target = nearest_target(match)
    index = (match.turn - 1) % HEAVY_WEAPONS.length
    weapon = HEAVY_WEAPONS[index]
    values = case weapon
    when "napalm", "airstrike", "mine_strike"
      {"weapon" => weapon, "x" => target[:x], "y" => target[:y],
       "direction" => match.turn.even? ? -1 : 1}
    when "cluster"
      {"weapon" => weapon, "angle" => active[:facing].positive? ? -38 : -142, "power" => 0.82, "fuse" => 1}
    when "barrel", "mine"
      {"weapon" => weapon}
    else
      {"weapon" => weapon}
    end
    match.command(active[:team], "fire", values)
    weapon
  rescue Burrow::RuleError
    # A prop can be rejected on a crowded ledge.  Keep the turn deterministic
    # and heavy by using a targetable sky weapon as the documented fallback.
    fallback = nearest_target(match)
    match.command(active[:team], "fire", {"weapon" => "napalm", "x" => fallback[:x], "y" => fallback[:y], "direction" => 1})
    "napalm_fallback"
  end

  def initialize_heavy_turn(match, action_counts)
    @last_heavy_turn = nil
    lambda do
      next unless match.phase == "aiming" && match.team[:bot]
      next if @last_heavy_turn == match.turn
      weapon = heavy_command(match)
      action_counts[weapon] = action_counts.fetch(weapon, 0) + 1
      @last_heavy_turn = match.turn
    end
  end

  def run(options)
    scenario = options.fetch(:scenario)
    heavy = scenario == "heavy"
    teams = options.fetch(:teams)
    worms = options.fetch(:worms)
    ticks = options.fetch(:ticks)
    seed = options.fetch(:seed)
    match, players = make_match(seed, teams: teams, worms: worms, heavy: heavy)
    profile_totals = {}
    if ENV["BURROW_HOST_PROFILE"] == "1"
      profile_module = Module.new do
        %i[update_worms update_salvos update_projectiles update_hazards update_tool record_motion run_bot
          update_rope_hook advance_projectile advance_walker advance_digger prop_motion update_flame scald
          clear_line? body_clear? grounded?].each do |method_name|
          define_method(method_name) do |*args|
            started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            super(*args)
          ensure
            elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000.0
            profile_totals[method_name.to_s] = (profile_totals[method_name.to_s] || 0.0) + elapsed
          end
        end
      end
      match.singleton_class.prepend(profile_module)
    end
    room = room_for(match, players)
    tmp_root = ENV.fetch("TMPDIR", Dir.tmpdir)
    FileUtils.mkdir_p(tmp_root)
    data_dir = Dir.mktmpdir("burrow-host-bench-", tmp_root)
    reactor = reactor_for(room, data_dir)
    action_counts = {}
    drive_heavy = heavy ? initialize_heavy_turn(match, action_counts) : nil

    tick_wall = []
    tick_cpu = []
    step_wall = []
    step_cpu = []
    snapshot_wall = []
    snapshot_cpu = []
    terrain_export_wall = []
    terrain_export_cpu = []
    terrain_checksum_wall = []
    terrain_checksum_cpu = []
    terrain_packet_bytes = []
    terrain_packet_data_bytes = []
    terrain_packet_compressed_bytes = []
    terrain_wire_wall = []
    terrain_wire_cpu = []
    blast_packet_delays = []
    persist_wall = []
    persist_cpu = []
    hashes = []
    simulation_hashes = []
    canonical_hashes = []
    canonical_revision = nil
    canonical_data = nil
    samples = []
    persist_sizes = []
    full_snapshots = 0
    last_revision = -1

    # Export is memoized by terrain revision.  These probes retain the cold
    # calls that actually compress a new mask, separately from the surrounding
    # Match#snapshot work measured below.
    export_samples = []
    checksum_samples = []
    export_probe = Module.new do
      define_method(:export) do |*args, **kwargs|
        cold = !instance_variable_get(:@export)
        return super(*args, **kwargs) unless cold
        started = PerfHostBench.monotonic
        cpu_started = PerfHostBench.cpu_clock
        super(*args, **kwargs).tap do |value|
          export_samples << {"revision" => revision, "cold" => cold,
            "wall_ms" => (PerfHostBench.monotonic - started) * 1000.0,
            "cpu_ms" => (PerfHostBench.cpu_clock - cpu_started) * 1000.0}
        end
      end
      define_method(:checksum) do
        return super() if instance_variable_get(:@checksum)
        started = PerfHostBench.monotonic
        cpu_started = PerfHostBench.cpu_clock
        super().tap do
          checksum_samples << {"wall_ms" => (PerfHostBench.monotonic - started) * 1000.0,
            "cpu_ms" => (PerfHostBench.cpu_clock - cpu_started) * 1000.0}
        end
      end
    end
    Burrow::Terrain.prepend(export_probe)

    blast_samples = []
    blast_probe = Module.new do
      define_method(:explode) do |*args, **kwargs|
        started = PerfHostBench.monotonic
        super(*args, **kwargs).tap do
          blast_samples << {"tick" => tick, "revision" => terrain.revision,
            "finished_at" => PerfHostBench.monotonic, "started_at" => started}
        end
      end
    end
    Burrow::Match.prepend(blast_probe)
    gc_before = GC.stat
    run_started = monotonic

    ticks.times do
      exports_before = export_samples.length
      checksums_before = checksum_samples.length
      blasts_before = blast_samples.length
      drive_heavy&.call
      tick_start = monotonic
      tick_cpu_start = cpu_clock

      step_start = monotonic
      step_cpu_start = cpu_clock
      match.step(1)
      step_wall << ((monotonic - step_start) * 1000.0)
      step_cpu << ((cpu_clock - step_cpu_start) * 1000.0)

      revision_changed = match.terrain.revision != last_revision
      full_snapshot = last_revision < 0 || revision_changed
      snapshot_start = monotonic
      snapshot_cpu_start = cpu_clock
      snapshot = room.match_snapshot(terrain: full_snapshot)
      snapshot_wall << ((monotonic - snapshot_start) * 1000.0)
      snapshot_cpu << ((cpu_clock - snapshot_cpu_start) * 1000.0)
      new_exports = export_samples[exports_before..] || []
      cold_exports = new_exports.select { |sample| sample["cold"] }
      cold_exports.each do |sample|
        terrain_export_wall << sample["wall_ms"]
        terrain_export_cpu << sample["cpu_ms"]
      end
      checksum_samples[checksums_before..].each do |sample|
        terrain_checksum_wall << sample["wall_ms"]
        terrain_checksum_cpu << sample["cpu_ms"]
      end
      if full_snapshot && snapshot && snapshot[:terrain]
        packet = snapshot[:terrain]
        terrain_packet_data_bytes << packet.fetch("data").bytesize
        terrain_packet_compressed_bytes << (packet.fetch("data").bytesize / 4 * 3 - packet.fetch("data").count("="))
        wire_cpu_started = cpu_clock
        wire_started = monotonic
        line = Burrow::Protocol.encode(type: "state", ack: 0, room: room.snapshot, match: snapshot)
        terrain_wire_wall << ((monotonic - wire_started) * 1000.0)
        terrain_wire_cpu << ((cpu_clock - wire_cpu_started) * 1000.0)
        terrain_packet_bytes << line.bytesize
        new_blasts = blast_samples[blasts_before..] || []
        new_blasts.each do |blast|
          blast_packet_delays << ((monotonic - blast.fetch("finished_at")) * 1000.0)
        end
      end
      full_snapshots += 1 if full_snapshot
      last_revision = match.terrain.revision

      # The live reactor persists at 2-second cadence (60 simulation ticks).
      if (match.tick % (Burrow::TICK_RATE * 2)).zero?
        persist_start = monotonic
        persist_cpu_start = cpu_clock
        reactor.send(:persist)
        persist_wall << ((monotonic - persist_start) * 1000.0)
        persist_cpu << ((cpu_clock - persist_cpu_start) * 1000.0)
        path = File.join(data_dir, "server.json")
        persist_sizes << (File.size(path) rescue 0)
      end

      total_tick_wall = (monotonic - tick_start) * 1000.0
      total_tick_cpu = (cpu_clock - tick_cpu_start) * 1000.0
      tick_wall << total_tick_wall
      tick_cpu << total_tick_cpu
      if canonical_revision != match.terrain.revision
        decoded = Zlib::Inflate.inflate(Base64.strict_decode64(match.terrain.export.fetch("data")))
        raise "Terrain export changed material bytes" unless decoded == match.terrain.data
        canonical_data = Base64.strict_encode64(Zlib::Deflate.deflate(decoded))
        canonical_revision = match.terrain.revision
      end
      checkpoint_json = JSON.generate(match.checkpoint)
      digest = Digest::SHA256.hexdigest(checkpoint_json)
      hashes << [match.tick, digest]
      simulation_checkpoint = match.checkpoint
      simulation_checkpoint["terrain"] = simulation_checkpoint.fetch("terrain").merge(
        "data" => nil, "data_sha256" => match.terrain.checksum)
      simulation_hashes << [match.tick, Digest::SHA256.hexdigest(JSON.generate(simulation_checkpoint))]
      canonical_checkpoint = match.checkpoint
      canonical_checkpoint["terrain"] = canonical_checkpoint.fetch("terrain").merge("data" => canonical_data)
      canonical_hashes << [match.tick, Digest::SHA256.hexdigest(JSON.generate(canonical_checkpoint))]
      samples << {"tick" => match.tick, "wall_ms" => total_tick_wall.round(4),
        "cpu_ms" => total_tick_cpu.round(4), "step_ms" => step_wall[-1].round(4),
        "snapshot_ms" => snapshot_wall[-1].round(4),
        "persist_ms" => persist_wall.empty? || match.tick % (Burrow::TICK_RATE * 2) != 0 ? 0.0 : persist_wall[-1].round(4),
        "terrain_revision" => match.terrain.revision}
    end
    elapsed = monotonic - run_started
    gc_after = GC.stat
    gc_time_before = gc_before.fetch(:time, 0)
    gc_time_after = gc_after.fetch(:time, 0)

    final_checkpoint = match.checkpoint
    final_hash = Digest::SHA256.hexdigest(JSON.generate(final_checkpoint))
    result = {
      "format" => 1,
      "source" => SOURCE,
      "baseline_commit" => "8bf41ed",
      "ruby" => RUBY_DESCRIPTION,
      "platform" => RUBY_PLATFORM,
      "scenario" => scenario,
      "seed" => seed,
      "teams" => teams,
      "worms_per_team" => worms,
      "ticks_requested" => ticks,
      "ticks_completed" => match.tick,
      "finished" => match.finished?,
      "phase" => match.phase,
      "actions" => action_counts,
      "wall_seconds" => elapsed.round(6),
      "tick_budget_ms" => TICK_BUDGET_MS.round(6),
      "ticks_over_budget" => tick_wall.count { |sample| sample > TICK_BUDGET_MS },
      "cpu_ms_per_sim_second" => (tick_cpu.sum / [match.tick, 1].max * Burrow::TICK_RATE).round(4),
      "cpu_seconds_per_wall_second" => (tick_cpu.sum / 1000.0 / [elapsed, 0.000001].max).round(4),
      "gc" => {"count" => gc_after[:count] - gc_before[:count],
        "minor" => gc_after[:minor_gc_count] - gc_before[:minor_gc_count],
        "major" => gc_after[:major_gc_count] - gc_before[:major_gc_count],
        "pause_ms" => (gc_time_after - gc_time_before).round(4),
        "allocated_objects" => gc_after[:total_allocated_objects] - gc_before[:total_allocated_objects]},
      "tick" => summary(tick_wall),
      "tick_cpu" => summary(tick_cpu),
      "step" => summary(step_wall),
      "step_cpu" => summary(step_cpu),
      "snapshot" => summary(snapshot_wall),
      "snapshot_cpu" => summary(snapshot_cpu),
      "persist" => summary(persist_wall),
      "persist_cpu" => summary(persist_cpu),
      "persist_sizes" => persist_sizes,
      "persist_size_bytes" => persist_sizes.empty? ? 0 : persist_sizes.last,
      "terrain_export" => summary(terrain_export_wall),
      "terrain_export_cpu" => summary(terrain_export_cpu),
      "terrain_checksum" => summary(terrain_checksum_wall),
      "terrain_checksum_cpu" => summary(terrain_checksum_cpu),
      "terrain_packet_bytes" => summary(terrain_packet_bytes, unit: "bytes"),
      "terrain_packet_data_bytes" => summary(terrain_packet_data_bytes, unit: "bytes"),
      "terrain_packet_compressed_bytes" => summary(terrain_packet_compressed_bytes, unit: "bytes"),
      "terrain_wire_encode" => summary(terrain_wire_wall),
      "terrain_wire_encode_cpu" => summary(terrain_wire_cpu),
      "blast_to_encoded_packet" => summary(blast_packet_delays),
      "full_snapshots" => full_snapshots,
      "profile_ms" => profile_totals.transform_values { |value| value.round(4) },
      "final_hash" => final_hash,
      "simulation_final_hash" => simulation_hashes.last&.last,
      "hashes" => hashes,
      "simulation_hashes" => simulation_hashes,
      "canonical_hashes" => canonical_hashes,
      "samples" => samples
    }
    output = options[:output]
    if output
      FileUtils.mkdir_p(File.dirname(File.expand_path(output)))
      File.write(output, JSON.pretty_generate(result))
    end
    puts JSON.generate(result.reject { |key, _| %w[hashes simulation_hashes canonical_hashes samples].include?(key) })
    result
  ensure
    close_reactor(reactor) if reactor
    FileUtils.rm_rf(data_dir) if data_dir && !options[:keep_data]
  end

  def parse!(argv)
    options = {scenario: "bot", teams: 2, worms: 6, ticks: DEFAULT_TICKS,
      seed: "perf-host", output: nil, keep_data: false}
    parser = OptionParser.new do |opts|
      opts.banner = "Usage: perf_host_bench.rb [options]"
      opts.on("--scenario NAME", %w[bot heavy], "deterministic workload (default: bot)") { |v| options[:scenario] = v }
      opts.on("--teams N", Integer, "number of teams (2–6)") { |v| options[:teams] = v }
      opts.on("--worms N", Integer, "worms per team (1–6)") { |v| options[:worms] = v }
      opts.on("--ticks N", Integer, "simulation ticks (default: #{DEFAULT_TICKS})") { |v| options[:ticks] = v }
      opts.on("--seed SEED", "map/simulation seed") { |v| options[:seed] = v }
      opts.on("--output PATH", "write complete JSON including per-tick hashes") { |v| options[:output] = v }
      opts.on("--keep-data", "retain temporary server checkpoint directory") { options[:keep_data] = true }
    end
    parser.parse!(argv)
    raise OptionParser::InvalidArgument, "teams must be 2–6" unless options[:teams].between?(2, 6)
    raise OptionParser::InvalidArgument, "worms must be 1–6" unless options[:worms].between?(1, 6)
    raise OptionParser::InvalidArgument, "ticks must be positive" unless options[:ticks].positive?
    options
  rescue OptionParser::ParseError => error
    warn error.message
    warn parser
    exit 2
  end
end

if $PROGRAM_NAME == __FILE__
  PerfHostBench.run(PerfHostBench.parse!(ARGV))
end
