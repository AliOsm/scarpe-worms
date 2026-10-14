# frozen_string_literal: true
require_relative "test_helper"
require_relative "../lib/burrow/client/terrain_painter"

class NetPerformanceTest < Minitest::Test
  def assert_same_landscape(expected, actual)
    assert_equal expected[:checksum], actual[:checksum]
    assert_equal expected[:tiles].map { |t| t[:id] }, actual[:tiles].map { |t| t[:id] }
    expected[:tiles].zip(actual[:tiles]).each do |a, b|
      assert_equal File.binread(a[:path]), File.binread(b[:path]), "tile #{a[:id]}"
    end
    assert_equal File.binread(expected[:overview]), File.binread(actual[:overview]), "minimap must agree with a complete repaint"
  end

  def test_incremental_minimap_matches_complete_repaints_across_tile_edges_and_world_changes
    Dir.mktmpdir("net-overview-") do |directory|
      incremental_dir = File.join(directory, "incremental")
      FileUtils.mkdir_p(incremental_dir)
      incremental = Burrow::Client::TerrainPainter.new(incremental_dir)
      terrain = Burrow::Terrain.new(seed: 291, width: 1440, height: 720)
      previous = incremental.render(terrain, "meadow")
      unchanged = incremental.render(terrain, "meadow")
      assert_equal previous[:tiles], unchanged[:tiles]
      assert_equal File.binread(previous[:overview]), File.binread(unchanged[:overview])
      # Geometry crosses horizontal and vertical tile edges, including their rims.
      terrain.bridge(384, 382, width: 200, height: 20)
      operations = [-> { terrain.carve(382, 388, 48) }, -> { terrain.girder(768, 320, angle: 40) },
        -> { terrain = Burrow::Terrain.new(seed: 812, width: 1450, height: 726) }]
      operations.each_with_index do |operation, i|
        operation.call
        biome = i == 1 ? "glacier" : "meadow"
        actual = incremental.render(terrain, biome)
        fresh_dir = File.join(directory, "fresh-#{i}")
        FileUtils.mkdir_p(fresh_dir)
        fresh = Burrow::Client::TerrainPainter.new(fresh_dir)
        assert_same_landscape(fresh.render(terrain, biome), actual)
      end
    end
  end
end
