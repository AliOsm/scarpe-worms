# frozen_string_literal: true
require_relative "weapon_controls_test"

class ClientMobilityTest < Minitest::Test
  def harness
    match = game("scheme" => "sandbox", "ammo" => {"rope" => 1})
    [WeaponControlsTest::Harness.new(match), match]
  end

  def test_wasd_thrusts_and_focus_loss_clears_the_jetpack_controls
    client, match = harness
    match.active.merge!(jetpack: true, fuel: 150)
    client.sync
    client.select("jetpack")
    client.key_down("w")
    client.key_down("d")
    client.update_controls
    assert_equal [1, 1], match.active.values_at(:input, :lift)
    refute client.actions.any? { |type, _| type == "jump" }, "W must never jump instead of thrusting"
    client.lose_focus
    assert_equal [0, 0], match.active.values_at(:input, :lift)
    assert_empty client.keys
  end

  def test_rope_w_reels_and_enter_releases_without_changing_momentum
    client, match = harness
    match.active.merge!(rope: {stage: "attached", x: 400.0, y: 120.0, length: 240.0}, rope_use: true, vx: 110.0, vy: -60.0)
    client.sync
    client.select("rope")
    client.key_down("w")
    client.update_controls
    assert_equal 1, match.active[:lift]
    assert match.active[:rope]
    client.key_up("w")
    client.key_down("enter")
    assert_nil match.active[:rope]
    assert_equal [110.0, -60.0], match.active.values_at(:vx, :vy)
    assert match.active[:rope_use]
    actions = client.actions.length
    client.key_down(" ")
    assert_equal actions, client.actions.length, "a fast Fire waits for the Jump-release acknowledgement"
  end

  def test_empty_ammo_still_allows_an_airborne_rope_chain_and_respects_ack_gating
    client, match = harness
    match.team[:inventory]["rope"] = 0
    match.active[:rope_use] = true
    client.sync
    assert client.can_equip?("rope")
    client.instance_variable_set(:@pending_action, 123)
    refute client.can_equip?("rope")
    client.sync
    match.active[:rope_use] = false
    client.sync
    refute client.can_equip?("rope")
  end

  def test_teleport_preview_uses_worker_collision_and_marks_actual_landing
    client, match = harness
    map = Burrow::Terrain.new(seed: 1, data: "\0".b * Burrow::Terrain::SIZE)
    map.bridge(500, 500, width: 300)
    match.instance_variable_set(:@terrain, map)
    match.worms.each_with_index { |worm, i| worm.merge!(x: 120.0 + i * 40, y: 200.0) }
    client.sync
    scene = Struct.new(:preview_terrain).new(map)
    def scene.terrain = raise("The GUI must not decode the terrain packet")
    client.instance_variable_set(:@scene, scene)
    client.select("teleport")
    client.instance_variable_set(:@target, [500, 450])
    assert_equal({valid: true, y: 500, message: "Clear landing"}, client.placement_preview)
    match.worms.last.merge!(x: 500.0, y: 500.0)
    client.sync
    # A real host snapshot advances its tick; update the key as the socket does.
    client.state["tick"] += 1
    refute client.placement_preview[:valid]
    assert_match(/another grub/, client.placement_preview[:message])
  end

  def test_girder_preview_detects_cell_thin_ground_between_old_samples
    map = Burrow::Terrain.new(seed: 1, data: "\0".b * Burrow::Terrain::SIZE)
    map.bridge(505, 302, width: 0, height: 0)
    result = Burrow::Placement.girder(map, 500, 300, water: 624, worms: [], rotation: 0)
    refute result[:valid]
  end
end
