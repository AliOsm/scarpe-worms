# frozen_string_literal: true

module Burrow
  module Client
    # A disposable presentation of ONE ordinary walking/jumping grub. Never runs
    # Match#step, weapons, hazards, RNG, damage or terrain mutation in the GUI.
    # The host still receives intents and owns every gameplay outcome.
    class Prediction
      HORIZON = 0.4
      LIMIT = 96
      FIELDS = %w[x y vx vy facing].freeze
      attr_reader :corrections, :max_correction, :replayed_steps

      # Use the exact host collision/integration code, with a private actor copy
      # and the worker's immutable, already-painted collision mask. Unsupported
      # mechanics are filtered before entry; damage/water abort the preview.
      class Body
        include Physics
        attr_reader :terrain, :worms, :config, :active_id, :phase, :tick,
          :world_width, :world_height, :water, :wind

        def initialize(state, terrain)
          @terrain, @config = terrain, state.fetch("config")
          @active_id, @phase, @tick = state.values_at("active", "phase", "tick")
          @world_width, @world_height = terrain.width, terrain.height
          @water, @wind = state.values_at("water", "wind")
          @low_gravity = state.dig("effects", "low_gravity")
          @worms = [state.fetch("worms").find { |w| w["id"] == active_id }.transform_keys(&:to_sym)]
          worm.merge!(input: 0, lift: 0, input_until: tick)
        end

        def worm = worms.first
        def interrupt_displaced_tool; end
        def hurt(*) = throw(:unsafe_prediction)
        def kill(*) = throw(:unsafe_prediction)
        def emit(*) = throw(:unsafe_prediction)

        def move(values, until_tick:, facing: true)
          worm[:input] = values.fetch(:direction, 0)
          worm[:input_until] = until_tick
          worm[:facing] = worm[:input] < 0 ? -1 : 1 if facing && !worm[:input].zero?
        end

        def step
          @tick += 1
          update_worms
        end
      end

      def initialize
        @corrections, @max_correction = 0, 0.0
        reset
      end

      def reset
        clear_inputs
        @state = @identity = nil
      end

      def clear_inputs
        @commands = []
        @confirmed_move = @barrier = @last = nil
        @engaged = @active = false
        @offset = [0.0, 0.0]
        @replayed_steps = 0
      end

      def active? = @active
      def pending_count = @commands.length

      def accept(packet, player:, rtt: 0, now: Burrow.clock)
        state = packet["match"]
        identity = [packet.dig("room", "match_id"), state && state.values_at("turn", "active", "team"), player]
        reset if identity != @identity || (state && @state && state["tick"] < @state["tick"])
        @identity, @state, @player = identity, state, player
        return unless state
        @received = state.dig(:presentation_timing, :received_at) || now
        # Prediction follows the local input clock, one upstream trip ahead of
        # server simulation. A received snapshot is about one RTT behind that
        # clock. This also works with protocol-4 hosts predating the experiment.
        @lag = (rtt.to_f / 1000).clamp(0, HORIZON)
        @base_at = @received - @lag
        ack = packet.fetch("ack", 0)
        @commands.delete_if do |command|
          next false if command[:seq] > ack
          @confirmed_move = command if command[:type] == "move"
          true
        end
        @barrier = nil if @barrier && ack >= @barrier
        @rebased = true
      end

      def record(type, values:, sequence:, now: Burrow.clock)
        unless %w[move jump].include?(type)
          # Firing can teleport, deploy a tool, knock the shooter back or change
          # turns. Resume only from a new authoritative snapshot and new input.
          @commands.clear
          @confirmed_move = nil
          @barrier = sequence
          @engaged = false
          return
        end
        if @commands.length >= LIMIT
          @commands.clear
          @confirmed_move = nil
          @barrier = sequence
          @engaged = false
          return
        end
        @commands << {type: type, values: values.dup, seq: sequence, at: now}
        @engaged = true
      end

      def present(view, terrain:, enabled: true, now: Burrow.clock)
        @replayed_steps = 0
        unless enabled && eligible?(view, terrain, now)
          return fallback(view)
        end
        body = Body.new(@state, terrain)
        return fallback(view) unless body.body_clear?(body.worm[:x], body.worm[:y])
        ahead = [(now - @base_at) * TICK_RATE, 0].max
        raw = catch(:unsafe_prediction) { replay(body, ahead) }
        return fallback(view) unless raw
        elapsed = @last ? [now - @last[:at], 0].max : 0
        if @rebased && @last
          dx = @last[:x] + @last[:vx] * elapsed - raw["x"]
          dy = @last[:y] + @last[:vy] * elapsed - raw["y"]
          distance = Math.hypot(dx, dy)
          @corrections += 1 if distance > 0.5
          @max_correction = [@max_correction, distance].max
          @offset = distance <= 18 ? [dx, dy] : [0.0, 0.0]
        end
        @rebased = false
        decay = Math.exp(-elapsed / 0.08)
        @offset.map! { |value| value * decay }
        # Smoothing must not move the displayed body through terrain.
        steps = [(Math.hypot(*@offset) / 2).ceil, 1].max
        clear = (1..steps).all? do |i|
          body.body_clear?(raw["x"] + @offset[0] * i / steps, raw["y"] + @offset[1] * i / steps)
        end
        @offset = [0.0, 0.0] unless clear
        raw["x"] += @offset[0]
        raw["y"] += @offset[1]
        @last = {at: now, x: raw["x"], y: raw["y"], vx: raw["vx"], vy: raw["vy"]}
        @active = true
        view.merge("worms" => view["worms"].map { |w| w["id"] == @state["active"] ? w.merge(raw) : w })
      end

      private

      def fallback(view)
        @active = false
        @last = nil
        @offset = [0.0, 0.0]
        view
      end

      def eligible?(view, terrain, now)
        return false unless @state && @engaged && !@barrier && terrain
        return false if @lag >= HORIZON
        return false if @commands.first && now - @commands.first[:at] > HORIZON
        return false unless @state["team"] == @player && view["active"] == @state["active"] && view["turn"] == @state["turn"]
        return false unless %w[aiming retreat].include?(@state["phase"]) && !@state["tool"]
        return false unless terrain.revision == @state["terrain_revision"] && now - @base_at <= HORIZON
        worm = @state["worms"].find { |w| w["id"] == @state["active"] }
        worm && worm["hp"] > 0 && %w[rope rope_use jetpack parachute frozen launched].none? { |key| worm[key] }
      end

      def replay(body, ahead)
        if @confirmed_move
          expiry = @state["tick"] + ((@confirmed_move[:at] + HORIZON - @base_at) * TICK_RATE).floor
          body.move(@confirmed_move[:values], until_tick: expiry, facing: false)
        end
        index, before = 0, body.worm.dup
        ahead.ceil.times do |step|
          while (command = @commands[index]) && ((command[:at] - @base_at) * TICK_RATE).floor <= step
            if command[:type] == "move"
              expiry = @state["tick"] + ((command[:at] + HORIZON - @base_at) * TICK_RATE).floor
              body.move(command[:values], until_tick: expiry)
            else
              body.jump_worm(body.worm, backflip: command[:values][:backflip])
            end
            index += 1
          end
          before = body.worm.dup
          body.step
          @replayed_steps += 1
        end
        alpha = ahead == ahead.floor ? 1.0 : ahead - ahead.floor
        raw = FIELDS.to_h { |key| [key, body.worm.fetch(key.to_sym)] }
        %w[x y].each { |key| raw[key] = before[key.to_sym] + (raw[key] - before[key.to_sym]) * alpha }
        raw
      end
    end
  end
end
