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
      raise RuleError, "That weapon is out of ammo." if inventory.fetch(id).zero? && !(@shots_left > 0 && id == @shot_weapon)
      raise RuleError, "Take your second Double tap shot first." if @shots_left > 0 && id != @shot_weapon
      raise RuleError, "Air support cannot reach this cavern." if config["terrain"] == "cavern" && Catalog::SKY.include?(kind)
      angle = number(values.fetch("angle", -45), -180..180) * Math::PI / 180
      power = number(values.fetch("power", 0.65), 0.05..1.0)
      fuse = number(values.fetch("fuse", 3), 1..5)
      x, y = Catalog::TARGETED.include?(kind) ? target_point(values) : [active[:x] + Math.cos(angle) * 200, active[:y] - 12 + Math.sin(angle) * 200]
      # Air support approaches from a chosen side; girders take a chosen tilt.
      side = values.key?("direction") ? (number(values["direction"], -1..1) < 0 ? -1 : 1) : (x >= active[:x] ? 1 : -1)
      tilt = number(values.fetch("rotation", 0), -90..90)
      validate_tool(kind, x, y, tilt: tilt)
      # Spend only after complete validation. The second shotgun shot shares its cartridge.
      inventory[id] -= 1 if inventory[id] > 0 && @shots_left.zero?
      active[:facing] = Math.cos(angle) < 0 ? -1 : 1 if Catalog::AIMED.include?(kind)
      active[:rope] = nil unless Catalog::UTILITY.include?(kind)
      damage = weapon[:damage] * (@damage_boost ? 2 : 1)
      emit("fire", weapon: id, worm: active_id, x: active[:x], y: active[:y] - 12)
      case kind
      when "projectile", "bounce", "cluster", "sticky", "homing", "gas"
        speed = id == "mortar" ? 580 : 130 + power * 540
        mx, my = muzzle_point(angle)
        staged = {}
        # The launch power sets how fast a homing rocket cruises once its motor locks on.
        staged[:cruise] = 300 + power * 370 if kind == "homing"
        staged.merge!(remote: true, stage: "thrown") if id == "banana"
        projectile(weapon, x: mx, y: my,
          vx: Math.cos(angle) * speed, vy: Math.sin(angle) * speed, damage: damage,
          life: %w[bounce cluster sticky gas].include?(kind) ? ((id == "holy_bomb" ? 5 : fuse) * TICK_RATE).round : 9 * TICK_RATE,
          bounce: %w[bounce cluster gas].include?(kind), sticky: kind == "sticky", homing: kind == "homing",
          target_x: x, target_y: y, wind: id != "mortar" && %w[projectile homing].include?(kind), shooter: active_id, **staged)
      when "place"
        projectile(weapon, x: active[:x] + active[:facing] * 15, y: active[:y] - 8,
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
        count = kind == "meteor" ? 6 : 5
        count.times do |i|
          if kind == "meteor"
            px, top, vx = @rng.rand(40..world_width - 40), -40 - i * 36, 85.0
          else
            # Bombers cross from `side`; each bomb is released ahead of the target
            # so the stick lands in a line across it.
            vx, top = side * 95.0, -40 - i * 18
            drop = [y - top, 40].max
            fall = (-130 + Math.sqrt(130**2 + 2 * gravity * drop)) / gravity
            px = (x - vx * fall + (i - 2) * 30).clamp(-60, world_width + 60)
          end
          projectile(weapon, x: px, y: top, vx: vx, vy: 130,
            damage: damage, life: 12 * TICK_RATE, drop_mine: kind == "mines", fire: kind == "napalm")
        end
      when "quake"
        worms.each do |w|
          next if w[:hp] <= 0 || w[:frozen]
          w[:vx] += (@rng.rand - 0.5) * 420
          w[:vy] = -90 - @rng.rand * 70
          w[:launched] = true
          hurt(w, damage, source: team[:id])
        end
        emit("quake", x: world_width / 2, y: world_height / 2, radius: 100)
      when "walker", "guided", "digger", "poisoner", "herd"
        count = kind == "herd" ? 3 : 1
        count.times do |i|
          projectile(weapon, x: active[:x] + active[:facing] * 10, y: active[:y] - 8,
            vx: active[:facing] * 105, vy: -80, direction: active[:facing], shooter: active_id,
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
      when "rope"
        active[:jetpack], active[:fuel] = false, 0
        point = terrain.ray(active[:x], active[:y] - 12, x - active[:x], y - active[:y] + 12, limit: 460)
        active[:rope] = {x: point[0], y: point[1], length: Math.hypot(point[0] - active[:x], point[1] - active[:y] + 12)}
        active[:vy] = -55
      when "jetpack"
        active[:rope] = nil
        active[:fuel] = 4 * TICK_RATE
        active[:jetpack] = true
        active[:vy] = -80
      when "parachute"
        active[:parachute] = true
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
        landing = terrain.landing(x, y, water: water)
        if !landing || worms.any? { |w| w[:id] != active_id && w[:hp] > 0 && Math.hypot(w[:x] - x, w[:y] - landing) < 25 }
          raise RuleError, "Choose clear ground above the water."
        end
      elsif kind == "girder"
        # Sample the tilted beam's centre line and both faces.
        ux, uy = Math.cos(tilt * Math::PI / 180), Math.sin(tilt * Math::PI / 180)
        points = (-70..70).step(10).map { |d| [x + ux * d, y + 6 + uy * d] }
        if !x.between?(80, world_width - 80) || !y.between?(100, water - 30) ||
            points.any? { |px, py| !py.between?(60, water - 20) || [-6, 0, 6].any? { |o| terrain.solid?(px - uy * o, py + ux * o) } } ||
            worms.any? { |w| w[:hp] > 0 && points.any? { |px, py| (w[:x] - px).abs < 13 && (w[:y] - 10 - py).abs < 21 } }
          raise RuleError, "A bridge needs clear space above water, away from grubs."
        end
      elsif kind == "rope"
        if y >= active[:y] - 20 || !terrain.ray(active[:x], active[:y] - 12, x - active[:x], y - active[:y] + 12, limit: 460)
          raise RuleError, "Aim the grapple at solid ground above you, within 460 pixels."
        end
      elsif kind == "heal" && active[:hp] == active[:max_hp] && !active[:poisoned]
        raise RuleError, "This grub is already healthy."
      elsif kind == "jetpack" && active[:jetpack]
        raise RuleError, "Your jetpack is already active."
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
        case [p[:kind], p[:stage]]
        when ["guided", "walking"]
          p[:stage], p[:walker], p[:guided] = "flying", false, true
          p[:vx], p[:vy], p[:heading] = 0.0, -230.0, -Math::PI / 2
          p[:steer], p[:input_until] = 0, tick
        when ["guided", "flying"]
          p[:stage], p[:guided], p[:remote] = "falling", false, false
        when ["digger", "walking"]
          p[:stage], p[:walker] = "diving", false
          p[:vx], p[:vy] = p[:direction] * 110.0, -150.0
        when ["poisoner", "walking"]
          p[:stage], p[:spraying], p[:remote] = "spraying", true, false
          p[:life] = [p[:life], 4 * TICK_RATE].min
          gas_cloud(p[:x], p[:y] - 6, owner, radius: 35, life: 150)
        when ["cluster", "thrown"]
          # Fruit salad bursts early on command.
          p[:life], p[:remote], p[:stage] = 0, false, "split"
        else
          p[:life] = 0
        end
        emit("activate", weapon: p[:weapon], x: p[:x], y: p[:y], stage: p[:stage])
      elsif @tool
        emit("activate", weapon: @tool[:kind] == "torch" ? "blowtorch" : @tool[:kind] == "dash" ? "dragon_punch" : "drill",
          x: active[:x], y: active[:y] - 10, stage: "stopped")
        @tool = nil
      elsif active[:rope]
        active[:rope] = nil
      elsif active[:jetpack]
        active[:jetpack] = false
        active[:fuel] = 0
        active[:parachute] = true
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
        return
      end
      if p[:kind] == "gas" || p[:poisoner]
        gas_cloud(p[:x], p[:y], p[:owner], radius: p[:radius], life: 6 * TICK_RATE)
        explode(p[:x], p[:y], damage: p[:damage], radius: 18, owner: p[:owner], kind: p[:weapon]) if p[:poisoner]
      else
        explode(p[:x], p[:y], damage: p[:damage], radius: p[:radius], owner: p[:owner], kind: p[:weapon])
      end
      if (p[:kind] == "cluster" || p[:weapon] == "mortar") && !p[:fragment]
        count = p[:weapon] == "banana" ? 6 : 5
        count.times do |i|
          projectiles << {id: next_object_id, weapon: p[:weapon], kind: "projectile", owner: p[:owner],
            x: p[:x], y: p[:y] - 12, vx: (i - (count - 1) / 2.0) * 85,
            vy: -135 - @rng.rand * 95, age: 0, life: 100, radius: p[:weapon] == "banana" ? 40 : 25,
            damage: (p[:weapon] == "banana" ? 45 : p[:weapon] == "mortar" ? 15 : 24) * p.fetch(:damage_scale, 1), fragment: true}
          record_projectile(projectiles.last)
        end
      end
      fire_patch(p[:x], p[:y], p[:owner], radius: 50) if p[:fire]
    end

    def gas_cloud(x, y, owner, radius:, life:)
      hazards << {id: next_object_id, kind: "gas", x: x, y: y, owner: owner, radius: radius, life: life}
      emit("gas", x: x, y: y, radius: radius)
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
        force = kind == "flame" ? 10 : kind == "burst" ? 16 : 40
        victim[:vx] += Math.cos(angle) * force
        victim[:vy] += Math.sin(angle) * force - (kind == "flame" ? 5 : 18)
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
        case weapon[:id]
        when "bat"
          w[:vx], w[:vy] = Math.cos(angle) * 490, Math.sin(angle) * 490
        when "prod"
          w[:vx], w[:vy] = active[:facing] * 140, -35
        when "axe"
          w[:vx], w[:vy] = active[:facing] * 25, -25
        when "fire_punch"
          w[:vx], w[:vy] = active[:facing] * 95, -285
        end
        w[:launched] = true
      end
      if weapon[:id] == "fire_punch"
        active[:vy], active[:launched] = -175, true
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
        x = (active[:x] + @tool[:direction] * 9).clamp(12, world_width - 12)
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
          w[:vx], w[:vy], w[:launched] = @tool[:direction] * 230, -95, true if w[:hp] > 0 && !w[:frozen]
        end
        if tick % 3 == 0 || !hits.empty?
          emit("melee", x: active[:x], y: active[:y] - 10, style: "dragon_punch", worm: active_id,
            facing: @tool[:direction], angle: @tool[:direction] > 0 ? 0 : Math::PI, hits: hits, continuing: true)
        end
        return
      end
      drilling = @tool[:kind] == "drill"
      lift = tick <= @tool.fetch(:input_until, 0) ? @tool.fetch(:lift, 0) : 0
      nx = (active[:x] + (drilling ? 0 : @tool[:direction] * 3)).clamp(12, world_width - 12)
      ny = active[:y] + (drilling ? 2.8 : -lift * 1.35)
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
          lift: lift, angle: drilling ? Math::PI / 2 : Math.atan2(-lift * 1.35, @tool[:direction] * 3))
      end
    end
  end
end
