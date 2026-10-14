# frozen_string_literal: true
# Isolated painter attribution and pixel evidence. Run under the round's bench
# wrapper, Ruby 4.0.7, PERF_AGENT=painter and scratch TMPDIR. Select the A/B source
# with BURROW_BENCH_SOURCE; write JSON with PERF_PAINTER_OUTPUT. --verify expands
# the matrix (run under heavy; no timings are recorded). Add --extra-seeds to
# verify seven more seeds on a world whose dimensions do not divide into tiles.
require_relative "perf_painter_support"
require "tmpdir"
require "digest"
require File.join(PainterPerf.source, "lib/burrow")
require File.join(PainterPerf.source, "lib/burrow/client/terrain_painter")

costs = Hash.new { |h, k| h[k] = [] }
probes = [[Burrow::Client::TerrainPainter.singleton_class, :tile],
  [Burrow::Client::TerrainPainter.singleton_class, :kit], [ChunkyPNG::Image, :save]]
if ARGV.include?("--deep")
  probes.concat([[ChunkyPNG::Image, :determine_png_encoding], [ChunkyPNG::Image, :encode_png_pixelstream],
    [ChunkyPNG::Chunk::ImageData.singleton_class, :split_in_chunks]])
end
probes.clear if ARGV.include?("--verify")
probes.each do |receiver, method|
  receiver.prepend(Module.new do
    define_method(method) do |*args, **kwargs, &block|
      value, timing = PainterPerf.measure { super(*args, **kwargs, &block) }
      costs[method] << timing
      value
    end
  end)
end
digest = lambda do |path|
  png = ChunkyPNG::Image.from_file(path)
  {pixels: Digest::SHA256.hexdigest([png.width, png.height].pack("N*") + png.pixels.pack("N*")),
    bytes: File.size(path), file: Digest::SHA256.file(path).hexdigest}
end
verify = ARGV.include?("--verify")
cases = if verify && ARGV.include?("--extra-seeds")
  [0, 1, 42, 9919, 12_345, 424_242, 0xdeadbeef].product(Burrow::Config::CHOICES.fetch("biome"), [[1450, 726]])
elsif verify
  [615, 291, 812].product(Burrow::Config::CHOICES.fetch("biome"),
    [[1440, 720], [1450, 726], [2880, 1280], [4800, 1600]])
else
  [[291, "meadow", [2880, 1280]], [291, "meadow", [4800, 1600]]]
end
records = cases.map.with_index do |(seed, biome, (width, height)), index|
  Dir.mktmpdir("painter-work-") do |directory|
    terrain = Burrow::Terrain.new(seed: seed, biome: biome,
      shape: Burrow::Config::CHOICES.fetch("terrain")[index % 3], width: width, height: height)
    painter = Burrow::Client::TerrainPainter.new(directory)
    rows = 3.times.map do |revision|
      if revision == 1
        terrain.bridge(384, 380, width: 210, height: 28)
        terrain.carve(382, 386, 48)
      elsif revision == 2
        terrain.bridge(768, 382, width: 200, height: 60) if verify
        terrain.girder(768, 380, angle: 40)
        terrain.carve(770, 386, 90)
      end
      costs.clear
      result, timing = verify ? [painter.render(terrain, biome), nil] : PainterPerf.measure { painter.render(terrain, biome) }
      parts = costs.transform_values { |v| {count: v.size, wall_ms: v.sum { |r| r[:wall_ms] }, cpu_ms: v.sum { |r| r[:cpu_ms] }} }
      {revision: revision, render: timing, parts: parts, rss_kib: PainterPerf.rss,
        tiles: result[:tiles].to_h { |tile| [tile[:id], digest.call(tile[:path])] },
        overview: digest.call(result[:overview]), checksum: result[:checksum], files: Dir.children(directory).size}
    end
    {seed: seed, biome: biome, size: [width, height], rows: rows}
  end
end
PainterPerf.write(scenario: verify ? "pixel-matrix" : "painter", records: records)
