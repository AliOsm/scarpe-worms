# frozen_string_literal: true

# Emit and restore protocol-4 terrain packets with a selected source tree.
# Run both directions under the round's bench lock:
#
#   BURROW_TERRAIN_SOURCE=$PWD .../bin/bench mise exec ruby@3.4.7 -- \
#     bundle exec ruby tools/perf_terrain_compat.rb --emit --output packets.json
#   BURROW_TERRAIN_SOURCE=/path/to/other/tree .../bin/bench mise exec \
#     ruby@3.4.7 -- bundle exec ruby tools/perf_terrain_compat.rb --restore \
#     --input packets.json --output restore.json
#
# The fixture covers every biome/shape at legacy, standard, large and huge
# dimensions, huge maps after 200 and 1,000 craters, and a patterned saved mask
# that exercises the compression fallback. Restore compares bytes,
# dimensions, revisions and SHA-256 checksums; compression bytes may differ by
# zlib level while remaining a standard protocol-4 stream.

require "base64"
require "digest"
require "json"
require "optparse"

source = ENV.fetch("BURROW_TERRAIN_SOURCE", ENV.fetch("BURROW_BENCH_SOURCE", File.expand_path("..", __dir__)))
$LOAD_PATH.unshift(File.join(source, "lib"))
require File.join(source, "lib", "burrow")
require File.join(source, "lib", "burrow", "protocol")
require File.join(source, "lib", "burrow", "server", "room")

options = {mode: nil, input: nil, output: nil}
OptionParser.new do |parser|
  parser.on("--emit") { options[:mode] = :emit }
  parser.on("--restore") { options[:mode] = :restore }
  parser.on("--input PATH") { |value| options[:input] = value }
  parser.on("--output PATH") { |value| options[:output] = value }
end.parse!
raise "Choose exactly one of --emit or --restore." unless options[:mode]

def seed_for(label)
  Digest::SHA256.hexdigest(label)[0, 15].to_i(16)
end

def fixtures
  rows = []
  [["legacy", 1440, 720], ["standard", 2880, 1280], ["large", 3840, 1440], ["huge", 4800, 1600]].each do |size, width, height|
    %w[islands archipelago cavern].each do |shape|
      %w[meadow desert glacier volcano].each do |biome|
        label = "#{size}/#{shape}/#{biome}"
        rows << [label, Burrow::Terrain.new(seed: seed_for(label), shape: shape, width: width, height: height, biome: biome)]
      end
    end
  end
  # Late-game craters exercise the same packet path after many revisions.
  %w[islands archipelago cavern].product(%w[meadow desert glacier volcano], [200, 1000]).each do |shape, biome, count|
    label = "huge/#{shape}/#{biome}/#{count}-craters"
    terrain = Burrow::Terrain.new(seed: seed_for(label), shape: shape, width: 4800, height: 1600, biome: biome)
    rng = Random.new(0xface)
    count.times do
      terrain.carve(rng.rand(terrain.width), rng.rand(200...terrain.height), rng.rand(10..80))
    end
    rows << [label, terrain]
  end
  rows << ["huge/patterned-checkpoint", Burrow::Terrain.new(seed: 123, width: 4800, height: 1600,
    data: [0, 1, 2, 3, 4].pack("C*") * 384_000)]
  rows
end

if options[:mode] == :emit
  players = 6.times.map { |i| {id: "p#{i}", name: "Terrain fixture #{i}", bot: true} }
  config = Burrow::Config.new("seed" => "terrain-packet-carrier", "worms" => 6, "map_size" => "huge")
  match = Burrow::Match.new(players: players, config: config)
  60.times { match.step }
  room = Burrow::Server::Room.new(code: "GUARD01", host: players.first, name: "Packet guard", config: config.to_h)
  room.instance_variable_set(:@members, players.map { |p| p.merge(ready: true, connected: true) })
  room.instance_variable_set(:@match, match)
  room.instance_variable_set(:@match_id, "terrain-packet-guard")
  carrier = match.snapshot
  packets = fixtures.map do |label, terrain|
    packet = terrain.export
    snapshot = carrier.merge(terrain: packet, terrain_revision: terrain.revision, terrain_checksum: terrain.checksum,
      world_width: terrain.width, world_height: terrain.height)
    frame = Burrow::Protocol.encode(type: "state", ack: 0, room: room.snapshot, match: snapshot)
    raise "#{label}: frame exceeds protocol limit" if frame.bytesize > Burrow::Protocol::MAX_SERVER
    raise "#{label}: terrain exceeds restore limit" if packet.fetch("data").bytesize >= 700_000
    {
      "case" => label,
      "packet" => packet,
      "data_sha256" => Digest::SHA256.hexdigest(terrain.data),
      "compressed_bytes" => Base64.strict_decode64(packet.fetch("data")).bytesize,
      "base64_bytes" => packet.fetch("data").bytesize,
      "server_frame_bytes" => frame.bytesize
    }
  end
  value = {"format" => 1, "source" => source, "protocol" => Burrow::PROTOCOL, "packets" => packets}
else
  input = JSON.parse(File.read(options.fetch(:input)), max_nesting: 32)
  restored = input.fetch("packets").map do |entry|
    terrain = Burrow::Terrain.restore(entry.fetch("packet"))
    expected = entry.fetch("data_sha256")
    raise "#{entry.fetch("case")}: material bytes changed" unless Digest::SHA256.hexdigest(terrain.data) == expected
    raise "#{entry.fetch("case")}: checksum changed" unless terrain.checksum == expected
    packet = entry.fetch("packet")
    raise "#{entry.fetch("case")}: revision changed" unless terrain.revision == packet.fetch("revision")
    raise "#{entry.fetch("case")}: dimensions changed" unless [terrain.width, terrain.height] == packet.values_at("width", "height")
    {"case" => entry.fetch("case"), "revision" => terrain.revision, "width" => terrain.width,
      "height" => terrain.height, "checksum" => terrain.checksum}
  end
  value = {"format" => 1, "source" => source, "input_source" => input["source"],
    "protocol" => Burrow::PROTOCOL, "restored" => restored, "count" => restored.length}
end

json = JSON.pretty_generate(value) + "\n"
options[:output] ? File.write(options[:output], json) : print(json)
