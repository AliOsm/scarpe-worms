# frozen_string_literal: true

require "set"

module Burrow
  module Client
    # Render a little behind the host so interpolation has both endpoints.
    # Coordinates use authoritative ticks, never a fixed fraction per packet.
    class Timeline
      DELAY = 4.5 # 150 ms: one 10 Hz snapshot plus a jitter cushion.
      MAX_BACKLOG = 12.0 # Recover within retained history after a long UI pause.
      attr_reader :tick, :events, :seen_shots, :underruns, :backlog_ms, :resyncs

      def initialize
        @offsets, @frames, @shots, @pending, @seen_shots = [], {}, {}, {}, Set.new
        @last_event, @underruns, @resyncs = 0, 0, 0
      end

      def accept(state, now: Burrow.clock)
        @state = state
        @latest = state.fetch("tick")
        if @received && now - @received > 0.6
          @offsets.clear
          @tick = nil
          @frames.clear
          @shots.clear
          @pending.clear
        end
        @received = now
        @offsets << now - @latest.fdiv(TICK_RATE)
        @offsets.shift while @offsets.length > 30
        motion = state["motion"] || {}
        Array(motion["frames"]).each { |frame| @frames[frame["tick"]] = frame }
        @frames[@latest] ||= {"tick" => @latest, "worms" => state["worms"].map { |w| w.values_at("id", "x", "y", "vx", "vy", "hp", "facing") },
          "hazards" => state["hazards"].map { |h| h.values_at("id", "x", "y") }}
        Array(motion["shots"]).each { |shot| @shots[shot["id"]] = shot }
        @frames.delete_if { |t, _| t < @latest - 30 }
        @shots.delete_if { |_, shot| shot["to"] && shot["to"] < @latest - 30 }
        state["events"].each do |event|
          next if event["id"] <= @last_event
          @pending[event["id"]] = event if event["tick"] >= @latest - 18
          @last_event = event["id"]
        end
      end

      def sample(now: Burrow.clock)
        return unless @state
        desired = (now - @offsets.min) * TICK_RATE - DELAY
        @underruns += 1 if desired > @latest + 1
        if @tick
          # Account for ALL elapsed time. Clamping each interval to 50 ms loses
          # time permanently under repeated stalls and can leave playback many
          # seconds behind a healthy host.
          speed = desired - @tick > 1 ? 1.12 : 1.0
          advance = [now - @sample_at, 0].max * TICK_RATE * speed
          target = [[@tick + advance, desired, @latest].min, @tick].max
          floor = [[desired - MAX_BACKLOG, @frames.keys.min].max, @latest].min
          target = [target, floor].max
          if @tick < floor
            @resyncs += 1
            @pending.delete_if { |_, event| event["tick"] < floor }
          end
          # A coalesced packet can contain a complete one-tick flight. Give each
          # unseen flight within the live playback window at least one visible
          # sample before delivering its impact, without slowing the whole clock.
          flight = @shots.values.filter_map do |shot|
            next if @seen_shots.include?(shot["id"]) || !shot["to"] || shot["to"] > target
            next if shot["to"] <= [@tick, floor].max
            [shot["from"], @tick, floor].max
          end.min
          @tick = flight || target
        else
          @tick = [[desired, @frames.keys.min].max, @latest].min
        end
        @backlog_ms = [desired - @tick, 0].max * 1000.0 / TICK_RATE
        @sample_at = now
        keys = @frames.keys.sort
        before = @frames[keys.reverse.find { |t| t <= tick } || keys.first]
        after = @frames[keys.find { |t| t >= tick } || keys.last]
        alpha = before == after ? 1.0 : (tick - before["tick"]).fdiv(after["tick"] - before["tick"]).clamp(0, 1)
        worms = interpolate_rows(before["worms"], after["worms"], alpha)
        hazards = interpolate_rows(before["hazards"], after["hazards"], alpha)
        shots = @shots.values.filter_map do |shot|
          next if tick < shot["from"] || (shot["to"] && tick >= shot["to"])
          samples = shot["samples"]
          a = samples.reverse.find { |point| point[0] <= tick } || samples.first
          b = samples.find { |point| point[0] >= tick } || samples.last
          blend = a[0] == b[0] ? 1.0 : (tick - a[0]).fdiv(b[0] - a[0]).clamp(0, 1)
          @seen_shots << shot["id"]
          shot.slice("id", "weapon", "walker", "owner", "fused").merge("x" => a[1] + (b[1] - a[1]) * blend,
            "y" => a[2] + (b[2] - a[2]) * blend, "vx" => a[3] + (b[3] - a[3]) * blend, "vy" => a[4] + (b[4] - a[4]) * blend,
            "walker" => a.length > 5 ? a[5] : shot["walker"], "stage" => a[6], "life" => a[7])
        end
        @events = @pending.values.select { |event| event["tick"] <= tick }
        @events.each { |event| @pending.delete(event["id"]) }
        @state.merge("worms" => @state["worms"].map do |w|
          row = worms[w["id"]]
          row ? w.merge(%w[x y vx vy hp facing].zip(row.drop(1)).to_h) : w
        end, "projectiles" => shots, "hazards" => @state["hazards"].map do |h|
          row = hazards[h["id"]]
          row ? h.merge("x" => row[1], "y" => row[2]) : h
        end)
      end

      private

      def interpolate_rows(first, last, alpha)
        prior = first.to_h { |row| [row[0], row] }
        last.to_h do |b|
          a = prior[b[0]] || b
          # Teleport discontinuities are intentional; walking and impacts interpolate.
          snap = Math.hypot(b[1] - a[1], b[2] - a[2]) > 120
          row = (alpha >= 1 ? b : a).dup
          row[1] = a[1] + (b[1] - a[1]) * alpha unless snap
          row[2] = a[2] + (b[2] - a[2]) * alpha unless snap
          [b[0], row]
        end
      end
    end
  end
end
