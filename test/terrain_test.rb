# frozen_string_literal: true
require_relative "test_helper"

class TerrainTest < Minitest::Test
  def test_seeds_are_repeatable_and_restore_exact_destructible_caves
    terrain = Burrow::Terrain.new(seed: 914)
    same = Burrow::Terrain.new(seed: 914)
    assert_equal terrain.checksum, same.checksum
    refute_equal terrain.checksum, Burrow::Terrain.new(seed: 915).checksum
    x = (100...terrain.width - 100).step(12).find { |px| terrain.surface(px) < terrain.height - 120 }
    y = terrain.surface(x)
    assert terrain.solid?(x, y + 20)
    assert terrain.carve(x, y + 20, 48)
    refute terrain.solid?(x, y + 20)
    terrain.bridge(300, 160)
    restored = Burrow::Terrain.restore(JSON.parse(JSON.generate(terrain.export)))
    assert_equal terrain.data, restored.data
    assert_equal terrain.revision, restored.revision
    assert_equal terrain.checksum, restored.checksum
    assert restored.solid?(300, 165)
  end

  def test_maps_give_six_full_teams_distinct_safe_spawns
    %w[islands archipelago cavern].each do |shape|
      12.times do |seed|
        match = game({"seed" => "generation-#{seed}", "terrain" => shape, "worms" => 6}, players: 6)
        assert_equal 36, match.worms.size
        match.worms.each do |worm|
          assert match.terrain.free_body?(worm[:x], worm[:y]), "#{shape}/#{seed}: blocked #{worm}"
          assert_operator worm[:y], :<, match.water - 10
        end
        match.step(30)
        assert match.worms.all? { |worm| worm[:hp] == worm[:max_hp] }, "A new map hurt a spawned grub: #{shape}/#{seed}"
      end
    end
  end

  def test_bad_and_oversized_packets_are_rejected
    terrain = Burrow::Terrain.new(seed: 7)
    payload = terrain.export.dup
    payload["checksum"] = "not the terrain"
    assert_raises(Burrow::RuleError) { Burrow::Terrain.restore(payload) }
    payload["data"] = Base64.strict_encode64(Zlib.deflate("\0" * (Burrow::Terrain::SIZE + 20_000)))
    assert_raises(Burrow::RuleError) { Burrow::Terrain.restore(payload) }
  end

  def test_auto_size_gives_four_and_six_teams_room_and_seeds_change_the_layout
    assert_equal [3840, 1440], Burrow::Config.new.world_size(4)
    assert_equal [4800, 1600], Burrow::Config.new.world_size(6)
    assert_equal [2880, 1280], Burrow::Config.new("map_size" => "standard").world_size(6)
    maps = 6.times.map { |seed| game({"seed" => "roomy-#{seed}", "worms" => 6}, players: 6) }
    assert_equal 6, maps.map { |m| m.terrain.checksum }.uniq.length
    maps.each do |match|
      positions = match.worms.map { |w| w.values_at(:x, :y) }
      assert_operator positions.map(&:first).minmax.reduce { |low, high| high - low }, :>, 4400
      assert_operator positions.combination(2).map { |a, b| Math.hypot(a[0] - b[0], a[1] - b[1]) }.min, :>=, 80
      assert_operator positions.map(&:last).minmax.reduce { |low, high| high - low }, :>, 240
    end
  end

  def test_blast_outside_world_never_wraps_rows
    terrain = Burrow::Terrain.new(seed: 9)
    checksum = terrain.checksum
    refute terrain.carve(-100, 300, 20)
    refute terrain.carve(Burrow::WIDTH + 100, 300, 20)
    assert_equal checksum, terrain.checksum
  end
end
