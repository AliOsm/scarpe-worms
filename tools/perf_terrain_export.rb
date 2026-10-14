# frozen_string_literal: true

# Terrain compression/packet-size sweep for the 0.5.4 performance round.
# Run under .perf-round/bin/bench with Ruby 3.4.7.  It measures zlib default,
# level 1, level 3, level 6, level 9 and RLE on every biome/shape at standard, large
# and huge dimensions, plus a deliberately high-entropy huge mask.  The latter
# is a protocol-limit guard: it documents the existing restore ceiling rather
# than changing the wire format.
#
#   PERF_AGENT=terrain TMPDIR=<scratch>/tmp .../bin/bench mise exec ruby@3.4.7 \
#     -- bundle exec ruby tools/perf_terrain_export.rb > export-levels.json

require "base64"
require "digest"
require "json"
require "zlib"

source = ENV.fetch("BURROW_BENCH_SOURCE", File.expand_path("..", __dir__))
$LOAD_PATH.unshift(File.join(source, "lib"))
require File.join(source, "lib", "burrow")

def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)

def high_entropy(size)
  rng = Random.new(0x5eed)
  out = String.new(capacity: size).b
  while out.bytesize < size
    count = [size - out.bytesize, 65_536].min
    out << Array.new(count) { rng.rand(5) }.pack("C*")
  end
  out
end

cases = []
[["standard", 2880, 1280], ["large", 3840, 1440], ["huge", 4800, 1600]].each do |size, width, height|
  ["islands", "archipelago", "cavern"].each do |shape|
    ["meadow", "desert", "glacier", "volcano"].each do |biome|
      seed = Digest::SHA256.hexdigest("levels-#{size}-#{shape}-#{biome}")[0, 15].to_i(16)
      cases << ["#{size}/#{shape}/#{biome}", Burrow::Terrain.new(seed: seed, shape: shape, width: width, height: height, biome: biome)]
    end
  end
end
cases << ["huge/high-entropy", Burrow::Terrain.new(seed: 0xface, shape: "islands", width: 4800, height: 1600, data: high_entropy(2400 * 800))]

levels = {"default" => Zlib::DEFAULT_COMPRESSION, "best_speed" => Zlib::BEST_SPEED, "level_3" => 3, "level_6" => 6, "level_9" => 9}
levels["rle"] = Zlib::BEST_SPEED
def compress(data, label, level)
  return Zlib::Deflate.deflate(data, level) unless label == "rle"
  deflater = Zlib::Deflate.new(level, Zlib::MAX_WBITS, Zlib::DEF_MEM_LEVEL, Zlib::RLE)
  deflater.deflate(data, Zlib::FINISH)
ensure
  deflater&.close
end
rows = []
cases.each do |name, terrain|
  levels.each do |label, level|
    2.times { compress(terrain.data, label, level) }
    samples = 5.times.map do
      started = clock
      compressed = compress(terrain.data, label, level)
      encoded = Base64.strict_encode64(compressed)
      elapsed = (clock - started) * 1000
      raise "material bytes changed" unless Zlib::Inflate.inflate(compressed) == terrain.data
      {"wall_ms" => elapsed, "compressed_bytes" => compressed.bytesize, "base64_bytes" => encoded.bytesize,
       "packet_bytes" => JSON.generate("revision" => terrain.revision, "seed" => terrain.seed, "shape" => terrain.shape,
         "width" => terrain.width, "height" => terrain.height, "data" => encoded,
         "checksum" => Digest::SHA256.hexdigest(terrain.data)).bytesize}
    end
    rows << {"case" => name, "level" => label, "n" => samples.length,
      "median_ms" => samples.map { |s| s["wall_ms"] }.sort[2], "max_ms" => samples.map { |s| s["wall_ms"] }.max,
      "compressed_bytes" => samples.map { |s| s["compressed_bytes"] }.max,
      "base64_bytes" => samples.map { |s| s["base64_bytes"] }.max,
      "packet_bytes" => samples.map { |s| s["packet_bytes"] }.max}
  end
end
puts JSON.pretty_generate({"ruby" => RUBY_DESCRIPTION, "rows" => rows})
