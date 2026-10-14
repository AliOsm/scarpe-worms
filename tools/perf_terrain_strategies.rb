# frozen_string_literal: true

# Exploratory zlib strategy and SHA-256 implementation sweep. Run under the
# exclusive bench wrapper with Ruby 4.0.7. This is a screen for candidates,
# not the interleaved host acceptance test. All streams must inflate exactly.
# Usage: bundle exec ruby tools/perf_terrain_strategies.rb --output capture.json
require "json"
require "openssl"
require "optparse"
require_relative "../lib/burrow"

output = nil
OptionParser.new { |p| p.on("--output PATH") { |v| output = v } }.parse!
def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)
def stats(values)
  a = values.sort
  {n: a.size, median: a[a.size / 2], p95: a[[(a.size * 0.95).floor, a.size - 1].min],
    min: a.first, max: a.last, iqr: a[(a.size * 0.75).floor] - a[(a.size * 0.25).floor]}
end
variants = {default: [-1, Zlib::DEFAULT_STRATEGY], speed: [1, Zlib::DEFAULT_STRATEGY],
  level3: [3, Zlib::DEFAULT_STRATEGY], rle: [1, Zlib::RLE],
  huffman: [1, Zlib::HUFFMAN_ONLY], filtered: [3, Zlib::FILTERED]}
rows = []
%w[islands archipelago cavern].product(%w[meadow desert glacier volcano]).each do |shape, biome|
  terrain = Burrow::Terrain.new(seed: 0x5eed, width: 4800, height: 1600, shape: shape, biome: biome)
  [0, 200].each do |craters|
    rng = Random.new(0xface)
    craters.times { terrain.carve(rng.rand(terrain.width), rng.rand(400...terrain.height), rng.rand(10..80)) }
    variants.each do |variant, (level, strategy)|
      samples, bytes = [], []
      5.times do
        t = clock
        deflater = Zlib::Deflate.new(level, Zlib::MAX_WBITS, Zlib::DEF_MEM_LEVEL, strategy)
        compressed = deflater.deflate(terrain.data, Zlib::FINISH)
        deflater.close
        samples << (clock - t) * 1000
        bytes << Base64.strict_encode64(compressed).bytesize
        raise "material bytes changed" unless Zlib::Inflate.inflate(compressed) == terrain.data
      end
      rows << {shape: shape, biome: biome, craters: craters, variant: variant,
        milliseconds: stats(samples), base64_bytes: bytes.max, raw_ms: samples}
    end
    digest = Digest::SHA256.hexdigest(terrain.data)
    {digest: -> { Digest::SHA256.hexdigest(terrain.data) },
      openssl: -> { OpenSSL::Digest::SHA256.hexdigest(terrain.data) }}.each do |variant, f|
      samples = 5.times.map do
        t = clock
        value = f.call
        duration = (clock - t) * 1000
        raise "SHA-256 differs" unless value == digest
        duration
      end
      rows << {shape: shape, biome: biome, craters: craters, variant: variant,
        milliseconds: stats(samples), raw_ms: samples}
    end
  end
end
result = {ruby: RUBY_DESCRIPTION, zlib: Zlib::ZLIB_VERSION, openssl: OpenSSL::OPENSSL_VERSION, rows: rows}
json = JSON.pretty_generate(result) + "\n"
output ? File.write(output, json) : print(json)
