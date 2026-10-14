# frozen_string_literal: true

# Save/load compatibility fixture for protocol-4 match checkpoints.  Emit a
# checkpoint with one source tree, then restore it with the other source tree;
# the normalized simulation digest includes the raw terrain checksum while
# ignoring only the zlib bytes that are allowed to vary by compression level.
# It also steps the restored match for 180 ticks and compares every checkpoint.
# Run every command under .perf-round/bin/heavy.

require "digest"
require "json"
require "optparse"

source = ENV.fetch("BURROW_TERRAIN_SOURCE", File.expand_path("..", __dir__))
$LOAD_PATH.unshift(File.join(source, "lib"))
require File.join(source, "lib", "burrow")

options = {mode: nil, input: nil, output: nil}
OptionParser.new do |parser|
  parser.on("--emit") { options[:mode] = :emit }
  parser.on("--restore") { options[:mode] = :restore }
  parser.on("--input PATH") { |value| options[:input] = value }
  parser.on("--output PATH") { |value| options[:output] = value }
end.parse!
raise "Choose exactly one of --emit or --restore." unless options[:mode]

def digest_checkpoint(value, match)
  normalized = Marshal.load(Marshal.dump(value))
  normalized["terrain"] = normalized.fetch("terrain").merge("data" => nil, "data_sha256" => match.terrain.checksum)
  Digest::SHA256.hexdigest(JSON.generate(normalized))
end

if options[:mode] == :emit
  players = 6.times.map { |i| {id: "p#{i}", name: "Checkpoint #{i}", bot: true} }
  config = Burrow::Config.new("seed" => "terrain-checkpoint", "worms" => 6, "map_size" => "huge")
  match = Burrow::Match.new(players: players, config: config)
  90.times { match.step }
  10.times do |i|
    x = 240 + i * 410
    match.terrain.carve(x, match.terrain.surface(x) + 35, 48)
  end
  checkpoint = match.checkpoint
  value = {"format" => 1, "source" => source, "checkpoint" => checkpoint,
    "simulation_hash" => digest_checkpoint(checkpoint, match), "terrain_checksum" => match.terrain.checksum}
  # checkpoint contains live simulation arrays; freeze the wire representation
  # before stepping so the saved state remains the starting point.
  value = JSON.parse(JSON.generate(value))
  value["continuation_hashes"] = 180.times.map do
    match.step
    digest_checkpoint(match.checkpoint, match)
  end
else
  value = JSON.parse(File.read(options.fetch(:input)), max_nesting: 64)
  match = Burrow::Match.restore(value.fetch("checkpoint"))
  digest = digest_checkpoint(match.checkpoint, match)
  raise "checkpoint simulation digest changed" unless digest == value.fetch("simulation_hash")
  raise "terrain checksum changed" unless match.terrain.checksum == value.fetch("terrain_checksum")
  checksum, tick, revision = match.terrain.checksum, match.tick, match.terrain.revision
  value.fetch("continuation_hashes").each_with_index do |expected, index|
    match.step
    raise "checkpoint continuation changed at tick #{index + 1}" unless digest_checkpoint(match.checkpoint, match) == expected
  end
  value = {"format" => 1, "source" => source, "input_source" => value["source"],
    "simulation_hash" => digest, "terrain_checksum" => checksum,
    "tick" => tick, "revision" => revision, "continuation_ticks_equal" => 180}
end

json = JSON.pretty_generate(value) + "\n"
options[:output] ? File.write(options[:output], json) : print(json)
