# frozen_string_literal: true

module Burrow
  module Weapons
    # Half-width and height from the foot anchor, including the solid inked
    # bodies of the status sprites. Placement and bullets share these bounds.
    HAZARD_BOUNDS = {"mine" => [15, 21], "barrel" => [17, 45],
      "turret" => [21, 40], "crate" => [13, 26]}.transform_values(&:freeze).freeze
    PLACEMENT_BOUNDS = {"mine" => [9, 9], "barrel" => [15, 21],
      "turret" => [15, 21]}.transform_values(&:freeze).freeze

    def use_weapon(values)
      id = values.fetch("weapon")
      weapon = Catalog.fetch(id)
      kind = weapon[:kind]
      inventory = team[:inventory]
      raise RuleError, "That weapon is out of ammo." if inventory.fetch(id).zero? && !(@shots_left > 0 && id == @shot_weapon) && !(kind == "rope" && active[:rope_use])
      raise RuleError, "Take your second Double tap shot first." if @shots_left > 0 && id != @shot_weapon
      raise RuleError, "Air support cannot reach this cavern." if config["terrain"] == "cavern" && Catalog::SKY.include?(kind)
      angle = number(values.fetch("angle", -45), -180..180) * Math::PI / 180
      power = number(values.fetch("power", 0.65), 0.05..1.0)
      fuse = number(values.fetch("fuse", 3), 1..5)
      x, y = Catalog::TARGETED.include?(kind) ? target_point(values) : [active[:x] + Math.cos(angle) * 200, active[:y] - 12 + Math.sin(angle) * 200]
      # Air support approaches from a chosen side; girders take a chosen tilt.
      side = values.key?("direction") ? (number(values["direction"], -1..1) < 0 ? -1 : 1) : (x >= active[:x] ? 1 : -1)
      tilt = number(values.fetch("rotation", 0), -90..90)
      # Grapple shots are a utility chain: a miss retracts without spending a
      # cartridge, while an airborne re-hook keeps the same cartridge alive.
      return use_rope(angle) if kind == "rope"
      validate_tool(kind, x, y, tilt: tilt)
      # Spend only after complete validation. The second shotgun shot shares its cartridge.
      inventory[id] -= 1 if inventory[id] > 0 && @shots_left.zero?
      active[:facing] = Math.cos(angle) < 0 ? -1 : 1 if Catalog::AIMED.include?(kind)
      active[:rope] = nil unless Catalog::UTILITY.include?(kind)
      damage = weapon[:damage] * (@damage_boost ? 2 : 1)
      emit("fire", weapon: id, worm: active_id, x: active[:x], y: active[:y] - 12)
      case kind
      when "projectile", "bounce", "cluster", "sticky", "homing", "gas"
        speed = Physics.launch_speed(id, power)
        mx, my = muzzle_point(angle)
        staged = {}
        # The launch power sets how fast a homing rocket cruises once its motor locks on.
        staged[:cruise] = 300 + power * 370 if kind == "homing"
        staged.merge!(remote: true, stage: "thrown") if id == "banana"
        projectile(weapon, x: mx, y: my,
          vx: Math.cos(angle) * speed, vy: Math.sin(angle) * speed, damage: damage,
          life: %w[bounce cluster sticky gas].include?(kind) ? ((id == "holy_bomb" ? 5 : fuse) * TICK_RATE).round : 9 * TICK_RATE,
          bounce: %w[bounce cluster gas].include?(kind), sticky: kind == "sticky", homing: kind == "homing",
          target_x: x, target_y: y, wind: Physics.profile(id)[:wind_scale] > 0, shooter: active_id, **staged)
      when "place"
        # A close wall must not place the charge on its far side or inside it.
        px, py = active[:x], active[:y] - 8
        7.times do
          break if terrain.solid?(px + active[:facing] * 2, py)
          px += active[:facing] * 2
        end
        projectile(weapon, x: px, y: py, shooter: active_id,
          vx: active[:facing] * 16, vy: 0, damage: damage, bounce: true, sticky: true, life: 4 * TICK_RATE)
      when "shotgun", "beam", "laser", "burst", "flame"
        shots = kind == "burst" ? 8 : kind == "flame" ? 18 : 1
        shots.times do |i|
          spread = kind == "burst" ? (@rng.rand - 0.5) * 0.09 : kind == "flame" ? ((i % 5) - 2) * 0.025 : 0
          shot = {at: tick + i * 2, angle: angle + spread, damage: damage, weapon: id,
            radius: weapon[:radius], kind: kind, range: kind == "flame" ? 160 : world_width,
            x: active[:x], y: active[:y] - 13, owner: team[:id], shooter: active_id}
          if i.zero?
            fire_ray(shot)
          else
            (@salvos ||= []) << shot
          end
        end
        if kind == "shotgun"
          @shots_left = @shots_left > 0 ? @shots_left - 1 : 1
          @shot_weapon = @shots_left > 0 ? id : nil
          return if @shots_left > 0
        end
      when "melee", "dash"
        melee(weapon, damage, angle)
      when "strike", "mines", "napalm", "meteor"
        if kind == "meteor"
          # A shower crosses the whole battlefield in readable waves, not six
          # simultaneous flashes. Persisted projectile delays keep saves exact.
          tuning = Physics.profile(id)
          drop_gravity = gravity * tuning[:gravity_scale]
          6.times do |i|
            landing = 40 + (world_width - 80) * (i + @rng.rand) / 6.0
            vx = @rng.rand(-tuning[:meteor_drift]..tuning[:meteor_drift])
            drop_speed = tuning[:meteor_drop]
            drop = [terrain.surface(landing) + 40, 40].max
            fall = (-drop_speed + Math.sqrt(drop_speed**2 + 2 * drop_gravity * drop)) / drop_gravity
            projectile(weapon, x: landing - vx * fall, y: -40, vx: vx, vy: drop_speed,
              damage: damage, life: 12 * TICK_RATE, delay: i * 9, sky_drop: true)
          end
        else
          # The plane and release points use the same trajectory. Its bombs
          # inherit its speed and cover a 152-pixel stick in approach order.
          tuning = Physics.profile(id)
          vx, top, spacing = side * tuning[:sky_speed], -40.0, tuning[:release_spacing]
          drop_speed = tuning[:drop_speed]
          drop_gravity = gravity * tuning[:gravity_scale]
          drop = [y - top, 40].max
          fall = (-drop_speed + Math.sqrt(drop_speed**2 + 2 * drop_gravity * drop)) / drop_gravity
          first = x - vx * fall - vx * (2 * spacing).fdiv(TICK_RATE)
          lead = 18
          start = first - vx * lead.fdiv(TICK_RATE)
          emit("strike", weapon: id, x: start, y: top - 14, vx: vx, side: side,
            duration: (lead + spacing * 4 + 24).fdiv(TICK_RATE))
          5.times do |i|
            projectile(weapon, x: first + vx * (i * spacing).fdiv(TICK_RATE), y: top, vx: vx, vy: drop_speed,
              damage: damage, life: 12 * TICK_RATE, delay: lead + i * spacing,
              drop_mine: kind == "mines", fire: kind == "napalm", sky_drop: true)
          end
        end
      when "quake"
        tuning = Physics.profile("earthquake")
        worms.each do |w|
          next if w[:hp] <= 0 || w[:frozen]
          w[:vx] += (@rng.rand - 0.5) * tuning[:quake_horizontal]
          w[:vy] = -tuning[:quake_lift] - @rng.rand * 70
          w[:rope] = nil
          w[:launched] = true
          hurt(w, damage, source: team[:id])
        end
        hazards.each do |h|
          next unless %w[mine barrel crate turret].include?(h[:kind])
          mass = Physics::PROP_MASS.fetch(h[:kind]) * Physics.profile(h[:kind])[:prop_mass]
          h[:vx] = h.fetch(:vx, 0) + (@rng.rand - 0.5) * tuning[:quake_horizontal] * 0.57 / mass
          h[:vy], h[:launched], h[:chute] = -70 - @rng.rand * 60, true, false
        end
        emit("quake", x: active[:x], y: active[:y], radius: 100,
          points: worms.select { |w| w[:hp] > 0 }.first(8).map { |w| [w[:x], w[:y]] })
      when "walker", "guided", "digger", "poisoner", "herd"
        tuning = Physics.profile(id)
        count = kind == "herd" ? 3 : 1
        count.times do |i|
          projectile(weapon, x: active[:x] + active[:facing] * 10, y: active[:y] - 8,
            vx: active[:facing] * tuning[:walker_speed], vy: -80, direction: active[:facing], shooter: active_id,
            damage: damage, walker: true, remote: kind != "herd", stage: "walking", delay: i * 24,
            poisoner: kind == "poisoner", life: (kind == "guided" || kind == "digger" ? 12 : 8) * TICK_RATE)
        end
        active[:input] = active[:lift] = 0
      when "mine", "barrel", "turret"
        # Props are placed on the first clear patch immediately in front of the
        # grub.  Validation runs before inventory is spent, so a wall or a
        # crowded ledge gives useful feedback and leaves the action available.
        px, py = hazard_place_point
        hazard = {id: next_object_id, kind: kind, x: px, y: py, owner: team[:id], damage: damage,
          armed: tick + (kind == "mine" ? TICK_RATE : 8), life: 100_000, hp: kind == "barrel" ? 24 : 20,
          shots: kind == "turret" ? 5 : 0, facing: active[:facing], angle: active[:facing].negative? ? Math::PI : 0.0,
          aim_angle: active[:facing].negative? ? Math::PI : 0.0}
        hazards << hazard
        emit("hazard_place", hazard_id: hazard[:id], style: kind, hazard_kind: kind, x: px, y: py, owner: team[:id], armed: hazard[:armed])
      when "jetpack"
        active[:rope] = nil
        active[:rope_use] = active[:rope_airborne] = false
        active[:parachute] = active[:parachute_open] = false
        # Five seconds of powered flight; idle controls conserve the supply.
        active[:fuel] = 5 * TICK_RATE
        active[:jetpack] = true
        active[:launched] = false
        active[:thrusting] = false
        active[:vy] = Physics.profile("jetpack")[:jetpack_start]
      when "parachute"
        active[:launched] = false
        active[:parachute] = true
        active[:parachute_open] = active[:vy] > 0 && !grounded?(active)
      when "teleport"
        landing = terrain.landing(x, y, water: water)
        emit("teleport", x: active[:x], y: active[:y], x2: x, y2: landing)
        active[:x], active[:y], active[:vx], active[:vy] = x, landing.to_f, 0.0, 0.0
      when "girder"
        terrain.girder(x, y, angle: tilt)
        emit("build", x: x, y: y, rotation: tilt)
      when "drill", "torch"
        @tool = {kind: kind, until: tick + 60, direction: active[:facing], owner: team[:id], damage: damage,
          lift: 0, input_until: tick, hits: {}, explicit_motion: true}
        active[:vx] = active[:vy] = 0.0
        active[:launched] = false
        active[:input] = active[:lift] = 0
      when "heal"
        cured = active[:poisoned]
        amount = [35, active[:max_hp] - active[:hp]].min
        active[:hp] += amount
        active[:poisoned] = false
        emit("heal", x: active[:x], y: active[:y] - 20, amount: amount, cured: cured)
      when "shield"
        active[:shield] = true
        emit("shield", worm: active_id, x: active[:x], y: active[:y] - 24, duration: "turn")
      when "freeze"
        frozen = worms.select { |w| w[:team] == team[:id] && w[:hp] > 0 }
        frozen.each { |w| w[:frozen] = true }
        emit("freeze", team: team[:id], worms: frozen.map { |w| w[:id] }, x: active[:x], y: active[:y] - 24, duration: "turn")
      when "boost"
        @damage_boost = true
        emit("boost", worm: active_id, x: active[:x], y: active[:y] - 24, duration: "turn")
      when "gravity"
        @low_gravity = true
        emit("gravity", worm: active_id, x: active[:x], y: active[:y] - 24, duration: "turn")
      when "wind"
        prior_wind = wind
        # A calm match still needs a readable Weather vane result.  Seed the
        # gust from the configured wind cap, then reverse/double subsequent
        # uses while keeping the authoritative bound.
        baseline = config["wind"].to_f.clamp(0.25, 2.0)
        @wind = if prior_wind.abs < 0.03
          baseline
        else
          (-prior_wind * 2).clamp(-4.0, 4.0)
        end
        emit("wind", x: active[:x], y: active[:y] - 24, previous: prior_wind, wind: @wind, duration: "turn")
      when "skip"
        # Passing still waits for a safe settled turn boundary.
        emit("skip", worm: active_id, team: team[:id])
      end
      resolve_turn(retreat: !%w[teleport girder heal freeze skip].include?(kind)) unless Catalog::UTILITY.include?(kind)
    end

    def validate_tool(kind, x, y, tilt: 0)
      if kind == "teleport"
        preview = Placement.teleport(terrain, x, y, water: water, worms: worms, active_id: active_id)
        raise RuleError, preview[:message] unless preview[:valid]
      elsif kind == "girder"
        preview = Placement.girder(terrain, x, y, water: water, worms: worms, rotation: tilt)
        raise RuleError, preview[:message] unless preview[:valid]
      elsif kind == "heal" && active[:hp] == active[:max_hp] && !active[:poisoned]
        raise RuleError, "This grub is already healthy."
      elsif kind == "jetpack" && active[:jetpack]
        raise RuleError, "Your jetpack is already active."
      elsif kind == "parachute" && active[:parachute]
        raise RuleError, "Your parachute is already equipped for this turn."
      elsif %w[mine barrel turret].include?(kind)
        x, y = hazard_place_point
        validate_hazard_place(kind, x, y)
      end
    end

    # Hazard placement deliberately does not use the long aim ray used by
    # projectiles.  Mines, barrels and sentries are hand-placed props, just
    # ahead of the actor, and need a small clear footprint to avoid spawning in
    # a wall or on top of another grub/prop.
    def hazard_place_point
      x = active[:x] + active[:facing] * 24
      y = active[:y] - 2
      if grounded?(active)
        # Snap to nearby ground, but release at hand height beside a ledge.
        # An unrestricted landing search would teleport props to distant floors.
        landing = terrain.landing(x, [active[:y] - 4, 0].max, water: water)
        y = landing if landing && (landing - active[:y]).abs <= 8
      end
      [x, y]
    end

    def validate_hazard_place(kind, x, y)
      width, height = PLACEMENT_BOUNDS.fetch(kind)
      unless x.between?(width + 8, world_width - width - 8) &&
          y.between?(height + 10, water - 4)
        raise RuleError, "There is no clear ground ahead for that #{kind}."
      end
      # Sample every terrain cell across the full footprint, including its top
      # and feet. Coarser samples can skip a one-cell wall inside the prop.
      if (-width..width).step(Terrain::CELL).any? do |dx|
        (-height..-1).step(Terrain::CELL).any? { |dy| terrain.solid?(x + dx, y + dy) }
      end
        raise RuleError, "There is no clear ground ahead for that #{kind}."
      end
      # The hand-to-ground sweep prevents placing through a one-cell wall.
      span = x - active[:x]
      steps = [(span.abs / 2).ceil, 1].max
      if (1..steps).any? do |step|
        sx = active[:x] + span * step / steps.to_f
        terrain.solid?(sx, y - height / 2)
      end
        raise RuleError, "There is no clear ground ahead for that #{kind}."
      end
      if worms.any? { |w| w[:id] != active_id && w[:hp] > 0 && Math.hypot(w[:x] - x, w[:y] - y) < width + 18 }
        raise RuleError, "Give the #{kind} more room before placing it."
      end
      if hazards.any? { |h| %w[mine barrel turret crate].include?(h[:kind]) && Math.hypot(h[:x] - x, h[:y] - y) < width + 18 }
        raise RuleError, "Give the #{kind} more room before placing it."
      end
    end

    def use_rope(angle)
      raise RuleError, "Release the current grapple before firing again." if active[:rope]
      ux, uy = Math.cos(angle), Math.sin(angle)
      raise RuleError, "Aim the grapple sideways or upward, away from straight down." if uy > 0.985
      active[:jetpack], active[:fuel], active[:thrusting] = false, 0, false
      active[:parachute] = active[:parachute_open] = false
      active[:facing] = ux < 0 ? -1 : 1
      # Collision and ammo are resolved as the hook travels, never from the
      # pointer's destination. A miss returns the complete cartridge.
      active[:rope] = {stage: "shooting", x: active[:x], y: active[:y] - 12,
        ux: ux, uy: uy, travel: 0.0, length: 0.0}
      emit("fire", weapon: "rope", worm: active_id, x: active[:x], y: active[:y] - 12)
    end

    def release_rope
      active[:rope] = nil
      if grounded?(active) && active[:vy] >= 0
        active[:rope_use] = active[:rope_airborne] = false
      end
      emit("activate", weapon: "rope", x: active[:x], y: active[:y] - 12, stage: "released")
    end

    # Start inside the body, then sweep to the muzzle. A wall beside the grub
    # must intercept the shot, even when it is thinner than the weapon sprite.
    def muzzle_point(angle)
      x, y = active[:x], active[:y] - 13
      (1..10).each do |i|
        nx, ny = active[:x] + Math.cos(angle) * i * 2, active[:y] - 13 + Math.sin(angle) * i * 2
        break if terrain.solid?(nx, ny)
        x, y = nx, ny
      end
      [x, y]
    end

    def controllable_projectile(owner)
      projectiles.find { |p| p[:owner] == owner && p[:remote] && p[:delay].to_i <= 0 && p[:life] > 0 }
    end

    def activate_control(owner)
      if (p = controllable_projectile(owner))
        tuning = Physics.profile(p[:weapon])
        case [p[:kind], p[:stage]]
        when ["guided", "walking"]
          p[:stage], p[:walker], p[:guided] = "flying", false, true
          p[:vx], p[:vy], p[:heading] = 0.0, -tuning[:guided_speed], -Math::PI / 2
          p[:steer], p[:input_until] = 0, tick
          p[:flight_ticks], p[:life] = Physics::CRITTER_FLIGHT_TICKS, Physics::CRITTER_FLIGHT_TICKS + 4 * TICK_RATE
          # A late takeoff still gets its full flight, without handing control
          # to the next team while the critter is alive.
          @settle_limit = [@settle_limit, tick + p[:life] + TICK_RATE].max
        when ["guided", "flying"]
          p[:life], p[:guided], p[:remote], p[:stage] = 0, false, false, "detonating"
        when ["digger", "walking"]
          p[:stage], p[:walker] = "diving", false
          p[:vx], p[:vy] = p[:direction] * tuning[:digger_vx], tuning[:digger_vy]
        when ["poisoner", "walking"]
          p[:stage], p[:spraying], p[:remote] = "spraying", true, false
          p[:life] = 4 * TICK_RATE
          gas_cloud(p[:x], p[:y] - 6, owner, radius: 35, life: 150, weapon: p[:weapon])
        when ["cluster", "thrown"]
          # Fruit salad bursts early on command.
          p[:life], p[:remote], p[:stage] = 0, false, "split"
        else
          p[:life], p[:remote], p[:stage] = 0, false, "detonating"
        end
        emit("activate", weapon: p[:weapon], x: p[:x], y: p[:y], stage: p[:stage])
      elsif @tool
        emit("activate", weapon: @tool[:kind] == "torch" ? "blowtorch" : @tool[:kind] == "dash" ? "dragon_punch" : "drill",
          x: active[:x], y: active[:y] - 10, stage: "stopped")
        @tool = nil
      elsif active[:rope]
        release_rope
      elsif active[:jetpack]
        active[:jetpack] = active[:thrusting] = false
        active[:fuel] = 0
        active[:parachute] = true
        active[:parachute_open] = active[:vy] > 0 && !grounded?(active)
        emit("activate", weapon: "jetpack", x: active[:x], y: active[:y] - 12, stage: "parachute")
      else
        raise RuleError, "There is no active weapon to control."
      end
    end

    def projectile(weapon, x:, y:, vx:, vy:, damage:, **options)
      projectiles << {id: next_object_id, weapon: weapon[:id], kind: weapon[:kind], owner: team[:id],
        x: x.to_f, y: y.to_f, vx: vx.to_f, vy: vy.to_f, age: 0, life: 240,
        radius: weapon[:radius], damage: damage, damage_scale: weapon[:damage].zero? ? 1 : damage.fdiv(weapon[:damage]), **options}
      record_projectile(projectiles.last) unless options[:delay].to_i > 0
    end

    def detonate(p)
      if p[:drop_mine]
        hazards << {id: next_object_id, kind: "mine", x: p[:x], y: p[:y], owner: p[:owner],
          life: 100_000, armed: tick + 40, hp: 20}
        emit("mine_land", weapon: p[:weapon], x: p[:x], y: p[:y])
        return
      end
      if p[:kind] == "gas" || p[:poisoner]
        gas_cloud(p[:x], p[:y], p[:owner], radius: p[:radius], life: 6 * TICK_RATE, weapon: p[:weapon])
        explode(p[:x], p[:y], damage: p[:damage], radius: 18, owner: p[:owner], kind: p[:weapon]) if p[:poisoner]
      else
        explode(p[:x], p[:y], damage: p[:damage], radius: p[:radius], owner: p[:owner], kind: p[:weapon])
      end
      if (p[:kind] == "cluster" || p[:weapon] == "mortar") && !p[:fragment]
        tuning = Physics.profile(p[:weapon])
        count = p[:weapon] == "banana" ? 6 : 5
        count.times do |i|
          projectiles << {id: next_object_id, weapon: p[:weapon], kind: "projectile", owner: p[:owner],
            x: p[:x], y: p[:y] - 12, vx: (i - (count - 1) / 2.0) * 85 * tuning[:fragment_horizontal] + p[:vx] * 0.3,
            vy: (-135 - @rng.rand * 95) * tuning[:fragment_lift], age: 0, life: 100, radius: p[:weapon] == "banana" ? 40 : 25,
            damage: (p[:weapon] == "banana" ? 45 : p[:weapon] == "mortar" ? 15 : 24) * p.fetch(:damage_scale, 1), fragment: true, stage: "fragment"}
          record_projectile(projectiles.last)
        end
      end
      fire_patch(p[:x], p[:y], p[:owner], radius: 50) if p[:fire]
    end

    def gas_cloud(x, y, owner, radius:, life:, weapon: nil)
      hazards << {id: next_object_id, kind: "gas", x: x, y: y, owner: owner, radius: radius, life: life}
      emit("gas", x: x, y: y, radius: radius, weapon: weapon)
    end

    def fire_patch(x, y, owner, radius: 35)
      count = (radius / 8.0).round.clamp(2, 7)
      count.times do |i|
        flame(x, y - 6, owner, vx: (i - (count - 1) / 2.0) * 32 + @rng.rand(-10.0..10.0), vy: -60 - @rng.rand(80.0))
      end
    end

    def ray_shot(angle, damage, radius, kind, range:)
      fire_ray(angle: angle, damage: damage, radius: radius, kind: kind, range: range,
        x: active[:x], y: active[:y] - 12, owner: team[:id], shooter: active_id)
    end

    def update_salvos
      (@salvos || []).delete_if do |shot|
        next false if tick < shot[:at]
        shooter = worms.find { |w| w[:id] == shot[:shooter] }
        next true if !shooter || shooter[:hp] <= 0
        shot[:x], shot[:y] = shooter[:x], shooter[:y] - 13
        fire_ray(shot)
        true
      end
    end

    def fire_ray(shot)
      angle, damage, radius, kind = shot.values_at(:angle, :damage, :radius, :kind)
      start_x, start_y = shot.values_at(:x, :y)
      # Trace every pellet against the same material before cutting its holes.
      # A single cartridge report and damage event keep recoil and sound coherent.
      pellets = kind == "shotgun" ? [-2, -1, 0, 1, 2] : [0]
      weights = [4, 5, 8, 5, 4]
      cuts, impacts, hits, prop_hits = [], [], Hash.new(0), Hash.new(0)
      rays = pellets.each_with_index.map do |offset, index|
        direction = angle + offset * 0.014
        portion = kind == "shotgun" ? damage * weights[index].fdiv(26) : damage
        trace_gun_ray(shot, direction, portion, cuts, impacts, hits, prop_hits)
      end
      cuts.each { |x, y| terrain.carve(x, y, radius) }
      hits.each do |id, amount|
        victim = worms.find { |w| w[:id] == id }
        hurt(victim, amount.round, source: shot[:owner])
        next if victim[:frozen] || victim[:hp] <= 0
        # A stream pushes gently; a cartridge applies one impulse even when all
        # five pellets connect. Neither kind gives the target extra fall damage.
        tuning = Physics.profile(shot[:weapon])
        force = (kind == "flame" ? 10 : kind == "burst" ? 16 : 40) * tuning[:direct_push]
        lift = (kind == "flame" ? 5 : 18) * tuning[:direct_lift]
        victim[:vx] += Math.cos(angle) * force
        victim[:vy] += Math.sin(angle) * force - lift
        victim[:launched] = true
      end
      prop_hits.each do |id, amount|
        prop = hazards.find { |h| h[:id] == id }
        next unless prop
        prop[:hp] = prop.fetch(:hp, 20) - amount
        ignite(prop, shot[:owner], 2) if prop[:hp] <= 0
      end
      center = rays[rays.length / 2]
      if kind == "flame"
        # One loose flame per pulse is enough for a persistent carpet; the global
        # sixty-flame cap also applies to this stream.
        flame(center[:x2], center[:y2], shot[:owner], vx: Math.cos(angle) * 34, vy: -28)
      end
      distance = Math.hypot(center[:x2] - start_x, center[:y2] - start_y)
      muzzle = [20.0, distance].min
      emit("beam", x: start_x + Math.cos(angle) * muzzle, y: start_y + Math.sin(angle) * muzzle,
        x2: center[:x2], y2: center[:y2], style: kind, weapon: shot[:weapon], angle: angle,
        rays: kind == "shotgun" ? rays : nil, impacts: impacts.first(12))
    end

    def trace_gun_ray(shot, angle, damage, cuts, impacts, hits, prop_hits)
      x, y = shot.values_at(:x, :y)
      dx, dy = Math.cos(angle) * 2, Math.sin(angle) * 2
      piercing = shot[:kind] == "laser"
      hit_ids, prop_ids = [], []
      last_cut = nil
      was_solid = false
      (shot[:range] / 2).ceil.times do
        x += dx
        y += dy
        break unless x.between?(0, world_width) && y.between?(0, world_height)
        solid = terrain.solid?(x, y)
        if solid
          impacts << {x: x, y: y, material: "terrain"} if !was_solid && impacts.length < 12
          if !last_cut || Math.hypot(x - last_cut[0], y - last_cut[1]) >= shot[:radius]
            cuts << [x, y]
            last_cut = [x, y]
          end
          break unless piercing
        end
        was_solid = solid
        victim = worms.find do |w|
          w[:hp] > 0 && w[:id] != shot[:shooter] && !hit_ids.include?(w[:id]) &&
            Math.hypot(w[:x] - x, w[:y] - 10 - y) < 13
        end
        if victim
          hits[victim[:id]] += damage
          hit_ids << victim[:id]
          impacts << {x: x, y: y, material: "worm"} if impacts.length < 12
          break unless piercing
        end
        prop = hazards.find do |h|
          next false if prop_ids.include?(h[:id])
          bounds = HAZARD_BOUNDS[h[:kind]]
          across, above = (h[:x] - x).abs, h[:y] - y
          bounds && across <= bounds[0] && above.between?(0, bounds[1])
        end
        if prop
          prop_hits[prop[:id]] += damage
          prop_ids << prop[:id]
          impacts << {x: x, y: y, material: "metal"} if impacts.length < 12
          break unless piercing
        end
      end
      {x2: x.clamp(0, world_width), y2: y.clamp(0, world_height)}
    end

    def melee(weapon, damage, angle)
      if weapon[:kind] == "dash"
        @tool = {kind: "dash", until: tick + 12, direction: active[:facing], owner: team[:id], damage: damage,
          hits: [], explicit_motion: true}
        active[:input] = active[:lift] = active[:vx] = active[:vy] = 0
        active[:launched] = false
        emit("melee", x: active[:x], y: active[:y] - 10, style: weapon[:id], worm: active_id,
          facing: active[:facing], angle: active[:facing] > 0 ? 0 : Math::PI, hits: [])
        return
      end
      victims = worms.select do |w|
        w[:id] != active_id && w[:hp] > 0 && (w[:x] - active[:x]) * active[:facing] >= -5 &&
          Math.hypot(w[:x] - active[:x], w[:y] - active[:y]) < 56 &&
          clear_line?(active[:x], active[:y] - 10, w[:x], w[:y] - 10)
      end
      victims.each do |w|
        hit = weapon[:id] == "axe" ? (w[:hp] / 2.0).ceil * (@damage_boost ? 2 : 1) : damage
        hurt(w, hit, source: team[:id])
        next if w[:frozen] || w[:hp] <= 0
        impulse = Physics.profile(weapon[:id])[:melee_impulse]
        case weapon[:id]
        when "bat"
          speed = impulse ? impulse[0] : 490
          w[:vx], w[:vy] = Math.cos(angle) * speed, Math.sin(angle) * speed
        when "prod"
          w[:vx], w[:vy] = active[:facing] * (impulse ? impulse[0] : 140), impulse ? impulse[1] : -35
        when "axe"
          w[:vx], w[:vy] = active[:facing] * (impulse ? impulse[0] : 25), impulse ? impulse[1] : -25
        when "fire_punch"
          w[:vx], w[:vy] = active[:facing] * (impulse ? impulse[0] : 95), impulse ? impulse[1] : -285
        end
        w[:launched] = true
      end
      if weapon[:id] == "fire_punch"
        active[:vy], active[:launched] = Physics.profile("fire_punch")[:self_lift], true
      end
      emit("melee", x: active[:x], y: active[:y] - 10, style: weapon[:id], worm: active_id,
        facing: active[:facing], angle: angle, hits: victims.map { |w| w[:id] })
    end

    # Impacts may arrive before movement or later in the same tick from a mine.
    # End the action before its explicit motion can erase an external impulse.
    def interrupt_displaced_tool
      return unless @tool && active
      @tool = nil if active[:launched] || active[:vx].abs > 0.01 || active[:vy].abs > 0.01
    end

    def update_tool
      interrupt_displaced_tool
      return unless @tool
      if tick >= @tool[:until] || active[:hp] <= 0 || active[:frozen]
        @tool = nil
        return
      end
      if @tool[:kind] == "dash"
        tuning = Physics.profile("dragon_punch")
        x = (active[:x] + @tool[:direction] * tuning[:dash_step]).clamp(12, world_width - 12)
        terrain.carve(x, active[:y] - 10, 23, scorch: false)
        active[:x] = x if body_clear?(x, active[:y])
        @tool[:hits] ||= []
        hits = []
        worms.each do |w|
          next if w[:id] == active_id || w[:hp] <= 0 || @tool[:hits].include?(w[:id]) ||
            Math.hypot(w[:x] - active[:x], w[:y] - active[:y]) > 33 ||
            !clear_line?(active[:x], active[:y] - 10, w[:x], w[:y] - 10)
          @tool[:hits] << w[:id]
          hits << w[:id]
          hurt(w, @tool[:damage], source: @tool[:owner])
          w[:vx], w[:vy], w[:launched] = @tool[:direction] * tuning[:dash_speed], tuning[:dash_lift], true if w[:hp] > 0 && !w[:frozen]
        end
        if tick % 3 == 0 || !hits.empty?
          emit("melee", x: active[:x], y: active[:y] - 10, style: "dragon_punch", worm: active_id,
            facing: @tool[:direction], angle: @tool[:direction] > 0 ? 0 : Math::PI, hits: hits, continuing: true)
        end
        return
      end
      drilling = @tool[:kind] == "drill"
      tuning = Physics.profile(drilling ? "drill" : "blowtorch")
      lift = tick <= @tool.fetch(:input_until, 0) ? @tool.fetch(:lift, 0) : 0
      nx = (active[:x] + (drilling ? 0 : @tool[:direction] * tuning[:tool_step])).clamp(12, world_width - 12)
      ny = active[:y] + (drilling ? tuning[:tool_step] : -lift * tuning[:tool_lift])
      x = nx + (drilling ? 0 : @tool[:direction] * 12)
      y = ny + (drilling ? 4 : -10)
      terrain.carve(x, y, drilling ? 22 : 25, scorch: !drilling)
      active[:x], active[:y] = nx, ny if body_clear?(nx, ny)
      if tick % 6 == 0
        @tool[:hits] ||= {}
        worms.each do |w|
          next if w[:id] == active_id || w[:hp] <= 0 || Math.hypot(w[:x] - x, w[:y] - 10 - y) > 30 ||
            !clear_line?(x, y, w[:x], w[:y] - 10)
          dealt = @tool[:hits].fetch(w[:id], 0)
          amount = [(@tool[:damage] / 10.0).ceil, @tool[:damage] - dealt].min
          next if amount <= 0
          hurt(w, amount, source: @tool[:owner])
          @tool[:hits][w[:id]] = dealt + amount
        end
      end
      if tick % 3 == 0
        emit("dig", x: x, y: y, radius: 22, worm: active_id, style: @tool[:kind], facing: @tool[:direction],
          lift: lift, angle: drilling ? Math::PI / 2 : Math.atan2(-lift * tuning[:tool_lift], @tool[:direction] * tuning[:tool_step]))
      end
    end
  end
end
