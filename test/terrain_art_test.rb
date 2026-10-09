# frozen_string_literal: true
require_relative "test_helper"
require_relative "../lib/burrow/client/terrain_painter"

class TerrainArtTest < Minitest::Test
  def terrain
    map = Burrow::Terrain.new(seed: 615, shape: "cavern")
    map.bridge(380, 170)
    map.carve(382, 380, 86)
    map
  end

  def test_every_biome_matches_collision_and_has_identical_pixels_across_tile_seams
    map = terrain
    Burrow::Config::CHOICES["biome"].each do |biome|
      kit = Burrow::Client::TerrainPainter.kit(biome)
      whole = Burrow::Client::TerrainPainter.tile(map, 0, 0, map.cols, map.rows, kit)
      mask = whole.pixels.map { |color| (color & 255).zero? ? 0 : 1 }.pack("C*")
      expected = map.data.bytes.map { |material| material.zero? ? 0 : 1 }.pack("C*")
      assert_equal Digest::SHA256.hexdigest(expected), Digest::SHA256.hexdigest(mask), "#{biome}: visible ground must match solid ground"
      stitched = ChunkyPNG::Image.new(map.cols, map.rows, 0)
      (0...map.rows).step(192) do |y|
        (0...map.cols).step(192) do |x|
          width, height = [192, map.cols - x].min, [192, map.rows - y].min
          tile = Burrow::Client::TerrainPainter.tile(map, x, y, width, height, kit)
          stitched.replace!(tile, x, y)
        end
      end
      assert_equal Digest::SHA256.hexdigest(whole.pixels.pack("N*")), Digest::SHA256.hexdigest(stitched.pixels.pack("N*")), "#{biome}: tile boundaries must be invisible"
      assert_operator whole.pixels.uniq.size, :>, 30, "#{biome}: material colours must survive PNG loading"
    end
  end

  def test_cached_tiles_rebuild_the_shading_rim_after_a_boundary_blast
    map = terrain
    Dir.mktmpdir("burrow-paint-test-") do |directory|
      painter = Burrow::Client::TerrainPainter.new(directory)
      first = painter.render(map, "meadow")
      unchanged = painter.render(map, "meadow")
      assert_equal first[:tiles], unchanged[:tiles]
      map.carve(386, 382, 80)
      changed = painter.render(map, "meadow")
      whole = Burrow::Client::TerrainPainter.tile(map, 0, 0, map.cols, map.rows, Burrow::Client::TerrainPainter.kit("meadow"))
      stitched = ChunkyPNG::Image.new(map.cols, map.rows, 0)
      changed[:tiles].each do |tile|
        stitched.replace!(ChunkyPNG::Image.from_file(tile[:path]), tile[:x] / 2, tile[:y] / 2)
      end
      assert_equal Digest::SHA256.hexdigest(whole.pixels.pack("N*")), Digest::SHA256.hexdigest(stitched.pixels.pack("N*"))
      assert_equal map.revision, changed[:revision]
      assert_operator changed[:tiles].zip(first[:tiles]).count { |a, b| a[:path] != b[:path] }, :<, first[:tiles].length
    end
  end
end
