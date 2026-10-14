# frozen_string_literal: true
require_relative "test_helper"
require_relative "../lib/burrow/client/prediction"
require_relative "../lib/burrow/client/timeline"

class PredictionTest < Minitest::Test
  def course(options = {})
    match = game({"fall_damage" => false, "turn_seconds" => 90}.merge(options))
    terrain = match.terrain
    ground = 900
    data = "\0".b * terrain.cols * terrain.rows
    data[(ground / 2) * terrain.cols..] = "\1" * ((terrain.rows - ground / 2) * terrain.cols)
    terrain = Burrow::Terrain.new(seed: 1, width: terrain.width, height: terrain.height, data: data)
    match.instance_variable_set(:@terrain, terrain)
    match.worms.each_with_index { |w, i| w.merge!(x: 300.0 + i * 500, y: ground.to_f, vx: 0.0, vy: 0.0, facing: 1) }
    match.instance_variable_set(:@motion_frames, [])
    match.send(:record_motion)
    match
  end

  def packet(match, ack: 0, identity: "test")
    JSON.parse(JSON.generate(type: "state", ack: ack, room: {match_id: identity}, match: match.snapshot))
  end

  def setup_prediction(match = course, rtt: 0)
    prediction = Burrow::Client::Prediction.new
    value = packet(match)
    prediction.accept(value, player: "p0", rtt: rtt, now: 10)
    [prediction, value["match"], match]
  end

  def active(view) = view["worms"].find { |w| w["id"] == view["active"] }

  def test_walking_and_jumping_move_on_the_next_frame_without_a_host_reply
    %w[move jump].each do |type|
      p, state, match = setup_prediction
      original = Marshal.dump([state, match.checkpoint])
      p.record(type, values: {direction: 1}, sequence: 1, now: 10)
      view = p.present(state, terrain: match.terrain, now: 10 + 1.0 / 60)
      assert p.active?
      assert_operator active(view)["x"], :>, active(state)["x"]
      assert_operator active(view)["y"], :<, active(state)["y"] if type == "jump"
      assert_equal original, Marshal.dump([state, match.checkpoint]), "prediction must not mutate gameplay or the source packet"
      assert_equal state.except("worms"), view.except("worms")
      assert_equal active(state).except(*Burrow::Client::Prediction::FIELDS), active(view).except(*Burrow::Client::Prediction::FIELDS)
      assert_equal state["worms"].drop(1), view["worms"].drop(1)
    end
  end

  def test_shared_physics_matches_host_on_steps_walls_and_jumps_in_both_directions
    [0.4, 1.0, 1.6].each do |gravity|
      [-1, 1].each do |direction|
        [false, true].each do |backflip|
          match = course("gravity" => gravity)
          match.terrain.bridge(350, 894, width: 40, height: 6)
          match.terrain.bridge(440, 830, width: 20, height: 70)
          match.active[:facing] = direction
          body = Burrow::Client::Prediction::Body.new(packet(match)["match"], match.terrain)
          60.times do |tick|
            if tick % 3 == 0
              match.command("p0", "move", direction: direction)
              body.move({direction: direction}, until_tick: body.tick + 12)
            end
            if tick == 4 || tick == 38
              match.command("p0", "jump", backflip: backflip)
              body.jump_worm(body.worm, backflip: backflip)
            end
            match.step
            body.step
            %i[x y vx vy facing].each { |key| assert_in_delta match.active[key], body.worm[key], 1e-9, "#{[gravity, direction, backflip, tick, key]}" }
          end
        end
      end
    end
  end

  def test_acknowledged_jump_is_not_applied_a_second_time
    p, _state, match = setup_prediction
    p.record("jump", values: {}, sequence: 1, now: 10)
    match.command("p0", "jump")
    match.step(3)
    value = packet(match, ack: 1)
    p.accept(value, player: "p0", now: 10.1)
    view = p.present(value["match"], terrain: match.terrain, now: 10.1 + Burrow::DT)
    match.step
    assert_equal 0, p.pending_count
    assert_in_delta match.active[:y], active(view)["y"], 1e-6
    assert_in_delta match.active[:vy], active(view)["vy"], 1e-6
  end

  def test_acknowledged_move_continues_and_unacknowledged_release_is_replayed
    p, _state, match = setup_prediction
    p.record("move", values: {direction: 1}, sequence: 1, now: 10)
    match.command("p0", "move", direction: 1)
    match.step(3)
    value = packet(match, ack: 1)
    p.accept(value, player: "p0", now: 10.1)
    p.record("move", values: {direction: 0}, sequence: 2, now: 10.1)
    match.command("p0", "move", direction: 0)
    match.step(3)
    view = p.present(value["match"], terrain: match.terrain, now: 10.2)
    assert_in_delta match.active[:x], active(view)["x"], 1e-6
    assert_in_delta match.active[:vx], active(view)["vx"], 1e-6
    assert_equal 1, p.pending_count
  end

  def test_rejected_jump_reconciles_without_repeating_the_action
    p, state, match = setup_prediction
    p.record("jump", values: {}, sequence: 1, now: 10)
    p.present(state, terrain: match.terrain, now: 10.05)
    # The host processed the command but did not jump (e.g. changed ground).
    p.accept(packet(match, ack: 1), player: "p0", now: 10.06)
    view = p.present(state, terrain: match.terrain, now: 10.07)
    assert_equal 0, p.pending_count
    assert_equal 0, active(view)["vy"]
    assert_operator active(view)["y"], :>, 890
    assert_operator p.corrections, :>, 0
  end

  def test_terrain_mismatch_stale_packets_disabled_setting_and_other_players_use_authoritative_playback
    p, state, match = setup_prediction
    p.record("move", values: {direction: 1}, sequence: 1, now: 10)
    assert_same state, p.present(state, terrain: nil, now: 10.1)
    assert_same state, p.present(state, terrain: match.terrain, now: 10.1, enabled: false)
    assert_same state, p.present(state, terrain: match.terrain, now: 10.401)
    match.terrain.carve(300, 900, 20)
    assert_same state, p.present(state, terrain: match.terrain, now: 10.1)
    p.accept(packet(match), player: "p1", now: 10.1)
    p.record("move", values: {direction: 1}, sequence: 2, now: 10.1)
    assert_same state, p.present(state, terrain: match.terrain, now: 10.2)
  end

  def test_tools_knockback_death_and_finished_turns_disable_prediction
    [*["rope", "rope_use", "jetpack", "parachute", "frozen", "launched"].map { |key| [key, true] }, ["hp", 0]].each do |key, value|
      p, state, match = setup_prediction
      active(state)[key] = value
      p.record("move", values: {direction: 1}, sequence: 1, now: 10)
      assert_same state, p.present(state, terrain: match.terrain, now: 10.1), key
    end
    [[:phase, "settling"], [:phase, "finished"], [:tool, {"kind" => "drill"}]].each do |key, value|
      p, state, match = setup_prediction
      state[key.to_s] = value
      p.record("jump", values: {}, sequence: 1, now: 10)
      assert_same state, p.present(state, terrain: match.terrain, now: 10.1)
    end
  end

  def test_new_turn_rematch_reconnect_and_focus_reset_discard_old_inputs
    [:turn, :match, :rewind, :reset].each do |change|
      p, state, match = setup_prediction
      p.record("jump", values: {}, sequence: 1, now: 10)
      value = packet(match)
      case change
      when :turn then value["match"]["turn"] += 1
      when :match then value["room"]["match_id"] = "rematch"
      when :rewind then value["match"]["tick"] -= 1
      when :reset then p.reset
      end
      p.accept(value, player: "p0", now: 10.1)
      assert_equal 0, p.pending_count
      assert_same state, p.present(state, terrain: match.terrain, now: 10.2)
    end
  end

  def test_fire_is_a_barrier_until_a_snapshot_receipt_and_fresh_movement
    p, state, match = setup_prediction
    p.record("move", values: {direction: 1}, sequence: 1, now: 10)
    p.record("fire", values: {weapon: "teleport"}, sequence: 2, now: 10.02)
    p.record("move", values: {direction: -1}, sequence: 3, now: 10.03)
    assert_same state, p.present(state, terrain: match.terrain, now: 10.1)
    value = packet(match, ack: 2)
    p.accept(value, player: "p0", now: 10.1)
    view = p.present(value["match"], terrain: match.terrain, now: 10.15)
    assert_operator active(view)["x"], :<, active(state)["x"]
  end

  def test_replay_and_pending_inputs_are_bounded_under_a_stall
    p, state, match = setup_prediction(rtt: 200)
    p.record("move", values: {direction: 1}, sequence: 1, now: 10)
    p.present(state, terrain: match.terrain, now: 10.19)
    assert_operator p.replayed_steps, :<=, 12
    assert_same state, p.present(state, terrain: match.terrain, now: 11)
    1000.times { |i| p.record("jump", values: {}, sequence: i + 2, now: 11) }
    assert_operator p.pending_count, :<=, Burrow::Client::Prediction::LIMIT
    assert_same state, p.present(state, terrain: match.terrain, now: 11)
  end

  def test_latency_beyond_the_replay_horizon_never_flashes_a_predicted_frame
    [400, 750, 3000].each do |rtt|
      p, state, match = setup_prediction(rtt: rtt)
      p.record("jump", values: {}, sequence: 1, now: 9.8)
      assert_same state, p.present(state, terrain: match.terrain, now: 10)
      assert_same state, p.present(state, terrain: match.terrain, now: 10.01)
      assert_equal 0, p.replayed_steps
    end
  end

  def test_prediction_aborts_at_water_or_fall_damage_without_changing_health
    [false, true].each do |fall|
      match = course("fall_damage" => fall)
      match.active.merge!(y: fall ? 898.0 : match.water + 9, vy: 300.0)
      match.terrain.carve(match.active[:x], match.active[:y], 60) unless fall
      p, state = setup_prediction(match)
      p.record("move", values: {direction: 0}, sequence: 1, now: 10)
      original = Marshal.dump(state)
      assert_same state, p.present(state, terrain: match.terrain, now: 10.1)
      assert_equal original, Marshal.dump(state)
    end
  end

  def test_collision_and_correction_never_put_the_visual_body_inside_a_wall
    match = course
    match.terrain.bridge(330, 820, width: 20, height: 80)
    p, state = setup_prediction(match)
    p.record("move", values: {direction: 1}, sequence: 1, now: 10)
    20.times do |i|
      view = p.present(state, terrain: match.terrain, now: 10 + (i + 1) / 60.0)
      worm = active(view)
      assert match.body_clear?(worm["x"], worm["y"])
      assert_operator worm["x"], :<, 320
    end
  end
end
