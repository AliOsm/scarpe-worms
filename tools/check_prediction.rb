# frozen_string_literal: true
# Deterministic delayed/ordered transport and 60 Hz presentation experiment.
# Uses real App controls, Connection snapshot preparation, Timeline, Prediction,
# and the authoritative Match. No display/network timing is claimed here; the
# native prediction journey separately exercises real TLS and native key events.
# bundle exec ruby tools/check_prediction.rb --output /tmp/prediction.json
require "optparse"
require_relative "../lib/burrow"
require_relative "../lib/burrow/client/app"

options = {output: "/tmp/prediction.json"}
OptionParser.new { |p| p.on("--output PATH") { |v| options[:output] = v } }.parse!

module PredictionExperiment
  class Wire < Burrow::Client::Connection
    attr_reader :sent
    def initialize
      super(endpoint: "tcp://127.0.0.1:1", name: "Experiment")
      @sent = []
      receive({"type" => "welcome", "version" => Burrow::PROTOCOL, "seq" => 0, "id" => "p0", "token" => "test"})
    end

    def send_action(type, **values)
      @sequence += 1
      @sent << {"type" => type, "seq" => @sequence, "at" => Burrow.clock, **values.transform_keys(&:to_s)}
      true
    end
  end

  class App < Burrow::Client::App
    attr_reader :view, :timeline
    def initialize(wire, terrain, enabled, rtt)
      @connection, @terrain, @enabled, @rtt = wire, terrain, enabled, rtt
      @prediction = Burrow::Client::Prediction.new
      @timeline = Burrow::Client::Timeline.new
      @keys = Set.new
      @page, @window_active, @connection_status = :match, true, "online"
      @angle, @power, @fuse, @selected_weapon = -40.0, 0.65, 3, "rocket"
      @scene = Struct.new(:terrain_revision).new(terrain.revision)
      @audio = Object.new
      def @audio.local_action(*) = nil
    end

    def responsive_movement? = @enabled
    def notify(message) = raise(message)

    def frame
      if (packet = connection.poll[:state])
        @room, @state = packet.values_at("room", "match")
        @timeline.accept(@state)
        @prediction.accept(packet, player: my_id, rtt: @rtt)
      end
      return unless @state
      update_controls
      @view = present_movement(@timeline.sample, terrain: @terrain, now: Burrow.clock)
    end
  end

  module_function

  def stats(values)
    values = values.sort
    return {n: 0} if values.empty?
    {n: values.size, median: values[values.size / 2], p95: values[(values.size * 0.95).floor], max: values.last}
  end

  def course
    players = 2.times.map { |i| {id: "p#{i}", name: "Team #{i}", bot: false} }
    match = Burrow::Match.new(players: players, config: Burrow::Config.new(
      "seed" => "prediction", "worms" => 2, "mines" => 0, "barrels" => 0, "crates" => false, "turn_seconds" => 90, "fall_damage" => false))
    terrain = match.terrain
    data = "\0".b * terrain.cols * terrain.rows
    data[450 * terrain.cols..] = "\1" * ((terrain.rows - 450) * terrain.cols)
    match.instance_variable_set(:@terrain, Burrow::Terrain.new(seed: 1, width: terrain.width, height: terrain.height, data: data))
    match.worms.each_with_index { |w, i| w.merge!(x: 400.0 + i * 500, y: 900.0, vx: 0.0, vy: 0.0, facing: 1) }
    match.instance_variable_set(:@motion_frames, [])
    match.send(:record_motion)
    match
  end

  def run(enabled:, rtt:, cadence:, jitter: [0], outage: false, ui_pause: false)
    $prediction_time = 100.0
    match = course
    wire = Wire.new
    app = App.new(wire, match.terrain, enabled, rtt)
    incoming, outgoing, probes, cpu, frame_gaps, errors = [], [], [], [], [], []
    last_ack, last_due, send_index, receive_index, max_steps, max_pending = 0, 100.0, 0, 0, 0, 0
    inputs = []
    6.times do |i|
      start = 103.0 + i * 1.35 + (i % 3) * 0.007
      key = i.even? ? "d" : "a"
      inputs << [start, :down, key, "walk"] << [start + 0.35, :up, key, nil]
    end
    4.times do |i|
      start = 112.0 + i * 2.0 + i * 0.009
      inputs << [start, :down, "w", "jump"] << [start + 0.02, :up, "w", nil]
    end
    inputs.sort_by!(&:first)
    # 600 Hz scheduler avoids quantizing network arrivals to the render clock.
    (0..(21 * 600)).each do |frame|
      now = $prediction_time = 100.0 + frame / 600.0
      while outgoing.first && outgoing.first[0] <= now
        _, command = outgoing.shift
        begin
          match.command("p0", command.fetch("type"), command)
        rescue Burrow::RuleError => error
          errors << error.message
        end
        last_ack = command["seq"]
      end
      if frame % 20 == 0
        match.step
        if match.tick % cadence == 0
          packet = JSON.parse(JSON.generate(type: "state", ack: last_ack, room: {match_id: "experiment"}, match: match.snapshot))
          delay = rtt / 2000.0 + jitter[send_index % jitter.length]
          due = [now + delay, last_due].max
          due = [due, 108.8].max if outage && now.between?(108, 108.8)
          incoming << [due, packet]
          last_due, send_index = due, send_index + 1
        end
      end
      while incoming.first && incoming.first[0] <= now
        _, packet = incoming.shift
        wire.send(:receive, packet, now: now)
      end
      next if ui_pause && now.between?(114, 114.6)
      while inputs.first && inputs.first[0] <= now && app.view
        _, kind, key, probe = inputs.shift
        if probe
          worm = app.view["worms"].find { |w| w["id"] == app.state["active"] }
          probes << {kind: probe, at: now, x: worm["x"], y: worm["y"], sequence: wire.sequence + 1}
        end
        kind == :down ? app.key_down(key) : app.key_up(key)
      end
      if frame % 10 == 0
        started = Process.clock_gettime(Process::CLOCK_THREAD_CPUTIME_ID)
        app.frame
        cpu << (Process.clock_gettime(Process::CLOCK_THREAD_CPUTIME_ID) - started) * 1000
        if app.view
          worm = app.view["worms"].find { |w| w["id"] == app.state["active"] }
          probes.each do |probe|
            moved = probe[:kind] == "walk" ? (worm["x"] - probe[:x]).abs > 0.5 : worm["y"] < probe[:y] - 0.5
            probe[:visible_ms] ||= (now - probe[:at]) * 1000 if moved
          end
          raise "Predicted body entered terrain" if app.prediction.active? && !match.body_clear?(worm["x"], worm["y"])
          max_steps = [max_steps, app.prediction.replayed_steps].max
          max_pending = [max_pending, app.prediction.pending_count].max
          frame_gaps << app.timeline.backlog_ms
        end
      end
      until wire.sent.empty?
        command = wire.sent.shift
        probes.each { |probe| probe[:enqueue_ms] ||= (command["at"] - probe[:at]) * 1000 if command["seq"] >= probe[:sequence] }
        due = now + rtt / 2000.0
        outgoing << [due, command]
        receive_index += 1
      end
    end
    raise "Unpresented input: #{probes}" unless probes.size == 10 && probes.all? { |p| p[:visible_ms] }
    raise "Prediction exceeded replay bound" unless max_steps <= 12 && max_pending <= 96
    raise "Unexpected rejected input: #{errors}" unless errors.empty?
    {enabled: enabled, rtt_ms: rtt, snapshot_hz: 30 / cadence,
      walk_ms: stats(probes.select { |p| p[:kind] == "walk" }.map { |p| p[:visible_ms] }),
      jump_ms: stats(probes.select { |p| p[:kind] == "jump" }.map { |p| p[:visible_ms] }),
      enqueue_ms: stats(probes.map { |p| p[:enqueue_ms] }), frame_cpu_ms: stats(cpu),
      max_replay_steps: max_steps, max_pending: max_pending, sent_commands: receive_index,
      corrections: app.prediction.corrections, max_correction_px: app.prediction.max_correction,
      playback_underruns: app.timeline.underruns, backlog_ms: stats(frame_gaps), inputs: probes}
  end
end

Burrow.define_singleton_method(:clock) { $prediction_time || Process.clock_gettime(Process::CLOCK_MONOTONIC) }
scenarios = {
  loopback: {rtt: 0, cadence: 1}, remote_100: {rtt: 100, cadence: 3}, remote_200: {rtt: 200, cadence: 3},
  remote_450_fallback: {rtt: 450, cadence: 3},
  jitter: {rtt: 100, cadence: 3, jitter: [0, 0.01, 0.035, 0.005, 0.055, 0]},
  outage: {rtt: 100, cadence: 3, outage: true}, ui_pause: {rtt: 100, cadence: 3, ui_pause: true}
}
report = {version: Burrow::VERSION, ruby: RUBY_VERSION, platform: RUBY_PLATFORM,
  scope: "Deterministic ordered transport simulation, actual input/host/playback code; 60 Hz sampled positions, not photons or network measurements",
  scenarios: scenarios.transform_values { |settings| [false, true].to_h { |enabled| [enabled ? :on : :off, PredictionExperiment.run(**settings, enabled: enabled)] } }}
File.write(options[:output], JSON.pretty_generate(report) + "\n")
report[:scenarios].each { |name, result| puts "#{name}: walk #{result[:off][:walk_ms][:median].round(1)} -> #{result[:on][:walk_ms][:median].round(1)} ms; jump #{result[:off][:jump_ms][:median].round(1)} -> #{result[:on][:jump_ms][:median].round(1)} ms" }
