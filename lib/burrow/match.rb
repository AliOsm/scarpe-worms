# frozen_string_literal: true

require_relative "random_stream"
require_relative "physics"
require_relative "weapons"
require_relative "bot"

module Burrow
  class Match
    include Physics
    include Weapons
    PARAMETERS = {"move" => %w[direction lift], "jump" => %w[backflip],
      "fire" => %w[weapon angle power fuse x y], "steer" => %w[direction lift], "activate" => [], "detonate" => []}.freeze
    attr_reader :config, :terrain, :teams, :worms, :projectiles, :hazards, :events,
      :tick, :phase, :turn, :active_id, :water, :winner, :wind, :inputs, :initial_teams

    def initialize(players:, config: Config.new)
      raise RuleError, "A match needs 2–6 teams." unless players.length.between?(2, 6)
      raise RuleError, "Team IDs must be unique." unless players.map { |p| p.fetch(:id) }.uniq.length == players.length
      @config = config
      @rng = RandomStream.new(config.seed_number)
      @terrain = Terrain.new(seed: config.seed_number, shape: config["terrain"],
        width: config.world_size(players.length)[0], height: config.world_size(players.length)[1])
      @initial_teams = players.map(&:dup)
      @teams = players.each_with_index.map do |p, i|
        {id: p.fetch(:id), name: p.fetch(:name), color: i, bot: !!p[:bot],
         inventory: Catalog.inventory(config["scheme"], config["ammo"]), score: 0, cursor: -1}
      end
      @tick, @turn, @event_seq, @object_seq = 0, 0, 0, 0
      @water, @wind = (@terrain.height - 96).to_f, 0.0
      @worms, @projectiles, @hazards, @events, @inputs = [], [], [], [], []
      @motion_frames, @shot_tracks, @salvos = [], {}, []
      @phase, @team_index = "aiming", -1
      @winner = nil
      spawn_worms
      spawn_obstacles
      next_turn
      record_motion
    end

    def world_width = terrain.width
    def world_height = terrain.height

    def active = worms.find { |w| w[:id] == active_id }
    def team = teams[@team_index]
    def seconds_left = [(@deadline - tick).fdiv(TICK_RATE), 0].max
    def alive_teams = teams.select { |t| worms.any? { |w| w[:team] == t[:id] && w[:hp] > 0 } }
    def round = ((turn - 1) / teams.length) + 1
    def finished? = phase == "finished"

    def command(player_id, type, values = {})
      raise RuleError, "The match has ended." if finished?
      remote_action = %w[activate detonate steer].include?(type) && controllable_projectile(player_id)
      raise RuleError, "Wait for your team's turn." unless active && active[:team] == player_id && (active[:hp] > 0 || remote_action)
      raise RuleError, "Wait for the action to settle." unless %w[aiming retreat].include?(phase) || remote_action || (@tool && %w[activate steer].include?(type))
      raise RuleError, "Only movement is available during retreat." if phase == "retreat" && !%w[move jump steer detonate activate].include?(type)
      raise RuleError, "Action parameters must be an object." unless values.is_a?(Hash)
      values = values.transform_keys(&:to_s).slice(*PARAMETERS.fetch(type, []))
      case type
      when "move"
        direction = number(values.fetch("direction", 0), -1..1)
        lift = number(values.fetch("lift", 0), -1..1)
        active[:input] = direction
        active[:lift] = lift
        active[:input_until] = tick + 12
        active[:facing] = direction < 0 ? -1 : 1 unless direction.zero?
      when "jump"
        if values.key?("backflip") && ![true, false].include?(values["backflip"])
          raise RuleError, "Backflip must be true or false."
        end
        if active[:rope]
          active[:rope] = nil
          active[:vy] -= 100
        elsif grounded?(active)
          active[:vx] = active[:facing] * (values["backflip"] ? -68 : 100)
          active[:vy] = values["backflip"] ? -220 : -178
          emit("jump", x: active[:x], y: active[:y], worm: active[:id])
        end
      when "fire"
        use_weapon(values)
        values = values.except("x", "y") unless Catalog::TARGETED.include?(Catalog.fetch(values["weapon"])[:kind])
      when "detonate", "activate"
        activate_control(player_id)
      when "steer"
        direction = number(values.fetch("direction", 0), -1..1)
        lift = number(values.fetch("lift", 0), -1..1)
        if (critter = controllable_projectile(player_id)) && critter[:stage] == "flying"
          critter[:steer], critter[:input_until] = direction, tick + 12
        elsif @tool
          @tool[:lift], @tool[:input_until] = lift, tick + 12
        else
          raise RuleError, "There is nothing to steer right now."
        end
      else
        raise RuleError, "Unknown game action."
      end
      @inputs << {tick: tick, player: player_id, type: type, values: values} if inputs.length < 50_000
      true
    rescue KeyError, TypeError, ArgumentError
      raise RuleError, "That action has invalid parameters."
    end

    def step(count = 1)
      count.times do
        break if finished?
        @tick += 1
        run_bot if phase == "aiming" && team[:bot]
        update_worms
        update_salvos
        update_projectiles
        update_hazards
        update_tool
        record_motion
        check_victory
        break if finished?
        if phase == "aiming" && (tick >= @deadline || active[:hp] <= 0)
          resolve_turn(retreat: false)
        elsif phase == "retreat" && tick >= @retreat_until
          @phase = "settling"
          active[:input] = active[:lift] = 0
        elsif phase == "settling"
          quiet = projectiles.empty? && (@salvos || []).empty? && !@tool && worms.none? { |w| w[:hp] > 0 && (w[:vy].abs > 4 || w[:vx].abs > 4) }
          @quiet_ticks = quiet ? @quiet_ticks + 1 : 0
          next_turn if @quiet_ticks >= 20 || tick >= @settle_limit
        end
      end
      self
    end

    def snapshot(terrain: false)
      value = {
        tick: tick, world_width: world_width, world_height: world_height, phase: phase, turn: turn, round: round, active: active_id, team: team[:id],
        seconds: seconds_left.round(1), water: water.round(2), wind: wind.round(3), winner: winner,
        config: config.to_h, teams: teams.map { |t| t.reject { |k, _| k == :cursor } },
        worms: worms.map { |w| w.reject { |k, _| %i[input input_until lift last_fall].include?(k) } },
        projectiles: projectiles.reject { |p| p[:delay].to_i > 0 }.map(&:dup), hazards: hazards.map(&:dup), events: events.map(&:dup),
        tool: @tool&.dup,
        motion: {frames: @motion_frames || [], shots: (@shot_tracks || {}).values},
        terrain_revision: @terrain.revision, terrain_checksum: @terrain.checksum,
        shots_left: @shots_left, sudden_death: round > config["round_limit"]
      }
      value[:effects] = {low_gravity: @low_gravity, double_damage: @damage_boost}
      value[:terrain] = @terrain.export if terrain
      value
    end

    def checkpoint
      {
        "version" => 1, "config" => config.to_h, "initial_teams" => initial_teams,
        "terrain" => terrain.export, "teams" => teams, "worms" => worms,
        "projectiles" => projectiles, "hazards" => hazards, "events" => events, "inputs" => inputs,
        "motion_frames" => @motion_frames, "shot_tracks" => @shot_tracks,
        "state" => %i[tick turn event_seq object_seq water wind phase team_index winner active_id
          deadline retreat_until settle_limit quiet_ticks shots_left shot_weapon damage_boost
          low_gravity bot_at bot_angle bot_search tool salvos].to_h { |name| [name.to_s, instance_variable_get("@#{name}")] },
        "random" => @rng.state
      }
    end

    def self.restore(saved)
      raise RuleError, "Unsupported match checkpoint." unless saved["version"] == 1
      match = allocate
      match.instance_variable_set(:@config, Config.new(saved.fetch("config")))
      match.instance_variable_set(:@terrain, Terrain.restore(saved.fetch("terrain")))
      %w[initial_teams teams worms projectiles hazards events inputs].each do |key|
        match.instance_variable_set("@#{key}", saved.fetch(key).map { |row| row.transform_keys(&:to_sym) })
      end
      saved.fetch("state").each do |key, value|
        value = value.transform_keys(&:to_sym) if key == "tool" && value
        match.instance_variable_set("@#{key}", value)
      end
      match.worms.each do |w|
        w[:rope] = w[:rope].transform_keys(&:to_sym) if w[:rope]
        w[:jetpack] = w[:fuel].to_i > 0 unless w.key?(:jetpack)
      end
      # Version-one checkpoints predate the explicit critter stages.
      match.projectiles.each do |p|
        next if p[:stage] || !%w[walker guided digger poisoner herd].include?(p[:kind])
        p[:stage] = p[:guided] ? "flying" : p[:dig] ? "digging" : "walking"
        p[:direction] = p[:vx] < 0 ? -1 : 1
      end
      match.instance_variable_set(:@salvos, Array(match.instance_variable_get(:@salvos)).map { |s| s.transform_keys(&:to_sym) })
      match.instance_variable_set(:@rng, RandomStream.new(saved.fetch("random")))
      match.instance_variable_set(:@motion_frames, saved.fetch("motion_frames", []))
      match.instance_variable_set(:@shot_tracks, saved.fetch("shot_tracks", {}))
      match
    end

    def surrender(player_id)
      worms.select { |w| w[:team] == player_id && w[:hp] > 0 }.each { |w| kill(w, "surrender") }
      check_victory
    end

    private

    # A short authoritative motion history survives both network jitter and
    # snapshot coalescing. A weapon that lives for one tick still has a flight.
    def record_motion
      @motion_frames ||= []
      @shot_tracks ||= {}
      @motion_frames << {"tick" => tick, "worms" => worms.map { |w| [w[:id], *w.values_at(:x, :y, :vx, :vy).map { |n| n.round(3) }, w[:hp], w[:facing]] },
        "hazards" => hazards.map { |h| [h[:id], h[:x].round(3), h[:y].round(3)] }}
      @motion_frames.shift while @motion_frames.length > 18
      @shot_tracks.delete_if { |_, track| track["to"] && track["to"] < tick - 18 }
      @shot_tracks.each_value { |track| track["samples"].shift while track["samples"].length > 20 }
    end

    def record_projectile(p, ended: false)
      @shot_tracks ||= {}
      track = (@shot_tracks[p[:id]] ||= {"id" => p[:id], "weapon" => p[:weapon], "walker" => p[:walker],
        "owner" => p[:owner], "fused" => !!(p[:bounce] || p[:sticky]), "from" => tick, "samples" => []})
      track["samples"] << [tick, *p.values_at(:x, :y, :vx, :vy).map { |n| n.round(3) }, !!p[:walker], p[:stage], p[:life]]
      track["to"] = tick if ended
    end

    def number(value, range)
      raise RuleError, "Aim and power must be finite numbers within range." unless value.is_a?(Numeric) && value.finite? && range.cover?(value)
      value.to_f
    end

    def target_point(values)
      [number(values.fetch("x"), 0..world_width), number(values.fetch("y"), 0..world_height)]
    end

    def next_object_id
      @object_seq += 1
      "o#{@object_seq}"
    end

    def emit(kind, **payload)
      @event_seq += 1
      events << {id: @event_seq, tick: tick, kind: kind, **payload}
      events.shift while events.size > 96
    end

    def spawn_worms
      count = teams.length * config["worms"]
      spots = (44..world_width - 44).step(6).filter_map do |x|
        y = terrain.landing(x, config["terrain"] == "cavern" ? 170 : 0, water: water)
        [x.to_f, y.to_f] if y
      end
      # Reserve all positions first. Greedy nearest-point placement can strand the
      # last team on a crowded archipelago even when there is enough total ground.
      spaced = []
      spots.each { |spot| spaced << spot if spaced.empty? || spot[0] - spaced.last[0] >= 20 }
      if spaced.length < count
        # Emergency wooden landing shelves keep every seed playable at 36 grubs.
        count.times do |i|
          x = 50 + (world_width - 100) * (i + 0.5) / count
          next if terrain.landing(x, config["terrain"] == "cavern" ? 170 : 0, water: water)
          terrain.bridge(x, 520 + (i % 3) * 22, width: 30, height: 10)
        end
        spaced = (44..world_width - 44).step(24).filter_map do |x|
          y = terrain.landing(x, config["terrain"] == "cavern" ? 170 : 0, water: water)
          [x.to_f, y.to_f] if y
        end
      end
      raise RuleError, "This seed has too little safe ground. Try another seed." if spaced.length < count
      count.times do |i|
        spot = spaced[((i + 0.5) * spaced.length / count).floor]
        t = teams[i % teams.length]
        worms << {id: "w#{i + 1}", team: t[:id], name: GRUB_NAMES[(i / teams.length + t[:color] * 2) % GRUB_NAMES.length],
          x: spot[0], y: spot[1], vx: 0.0, vy: 0.0, hp: config["health"], max_hp: config["health"],
          facing: spot[0] < world_width / 2 ? 1 : -1, input: 0.0, lift: 0.0, input_until: 0,
          poisoned: false, shield: false, frozen: false, parachute: false, jetpack: false, fuel: 0, rope: nil}
      end
    end

    def spawn_obstacles
      {"mine" => config["mines"], "barrel" => config["barrels"]}.each do |kind, count|
        count.times do
          50.times do
            x = @rng.rand(70..world_width - 70)
            y = terrain.landing(x, config["terrain"] == "cavern" ? 160 : 0, water: water)
            next unless y && worms.none? { |w| Math.hypot(w[:x] - x, w[:y] - y) < 38 }
            hazards << {id: next_object_id, kind: kind, x: x.to_f, y: y.to_f, owner: nil, armed: 90, life: 100_000, hp: 20}
            break
          end
        end
      end
    end

    def next_turn
      return if check_victory
      @turn += 1
      teams.length.times do
        @team_index = (@team_index + 1) % teams.length
        break if worms.any? { |w| w[:team] == team[:id] && w[:hp] > 0 }
      end
      members = worms.select { |w| w[:team] == team[:id] && w[:hp] > 0 }
      team[:cursor] = (team[:cursor] + 1) % members.length
      @active_id = members[team[:cursor]][:id]
      worms.each do |w|
        w[:input] = w[:lift] = 0.0
        w[:rope] = nil
        w[:fuel] = 0
        w[:jetpack] = false
        w[:parachute] = false
        if w[:team] == team[:id]
          w[:shield] = w[:frozen] = false
          hurt(w, 5, source: nil, poison: true) if w[:poisoned] && w[:hp] > 1
        end
      end
      @phase = "aiming"
      @deadline = tick + config["turn_seconds"] * TICK_RATE
      @quiet_ticks, @shots_left = 0, 0
      @shot_weapon = nil
      @damage_boost, @low_gravity = false, false
      @wind = (@rng.rand * 2 - 1) * config["wind"]
      @bot_at = tick + 38
      @bot_search = nil
      if round > config["round_limit"]
        @water = [water - config["water_rise"], 170].max
        worms.each { |w| w[:hp] = [w[:hp], 1].min if w[:hp] > 0 }
        emit("flood", water: water)
      end
      drop_crate if config["crates"] && turn > 1 && turn % 2 == 1
      emit("turn", team: team[:id], worm: active_id, text: "#{team[:name]} · #{active[:name]}")
    end

    def resolve_turn(retreat: true)
      @shots_left = 0
      @shot_weapon = nil
      @retreat_until = tick + (retreat ? config["retreat_seconds"] * TICK_RATE : 0)
      @settle_limit = tick + 18 * TICK_RATE
      @quiet_ticks = 0
      @phase = @retreat_until > tick ? "retreat" : "settling"
      active[:rope] = nil
      active[:fuel] = 0
      active[:jetpack] = false
    end

    def check_victory
      return true if finished?
      survivors = alive_teams
      return false if survivors.length > 1
      @winner = survivors.first&.fetch(:id)
      @phase = "finished"
      emit("victory", team: winner, text: survivors.empty? ? "A spectacular draw!" : "#{survivors.first[:name]} wins!")
      true
    end

    def drop_crate
      return if hazards.count { |h| h[:kind] == "crate" } >= 4
      x = @rng.rand(70..world_width - 70)
      hazards << {id: next_object_id, kind: "crate", x: x.to_f, y: 130.0, owner: nil,
        life: 100_000, armed: tick, hp: 15, supply: @rng.rand < 0.35 ? "health" : Catalog::WEAPONS.keys[@rng.rand(Catalog::WEAPONS.length - 1)]}
      emit("supply", x: x, y: 130)
    end
  end
end
