# frozen_string_literal: true

module Burrow
  module Weapons
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
      validate_tool(kind, x, y)
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
        projectile(weapon, x: mx, y: my,
          vx: Math.cos(angle) * speed, vy: Math.sin(angle) * speed, damage: damage,
          life: %w[bounce cluster sticky gas].include?(kind) ? ((id == "holy_bomb" ? 5 : fuse) * TICK_RATE).round : 9 * TICK_RATE,
          bounce: %w[bounce cluster gas].include?(kind), sticky: kind == "sticky", homing: kind == "homing",
          target_x: x, target_y: y, wind: id != "mortar" && %w[projectile homing].include?(kind), shooter: active_id)
      when "place"
        projectile(weapon, x: active[:x] + active[:facing] * 15, y: active[:y] - 8,
          vx: active[:facing] * 16, vy: 0, damage: damage, bounce: true, sticky: true, life: 4 * TICK_RATE)
      when "shotgun", "beam", "laser", "burst", "flame"
        shots = kind == "burst" ? 8 : kind == "flame" ? 7 : 1
        shots.times do |i|
          spread = kind == "burst" ? (@rng.rand - 0.5) * 0.15 : kind == "flame" ? (i - 3) * 0.08 : 0
          shot = {at: tick + i * (kind == "flame" ? 3 : 2), angle: angle + spread, damage: damage,
            radius: weapon[:radius], kind: kind, range: kind == "flame" ? 150 : world_width,
            x: active[:x], y: active[:y] - 12, owner: team[:id], shooter: active_id}
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
          px = kind == "meteor" ? @rng.rand(40..world_width - 40) : (x + (i - 2) * 34).clamp(15, world_width - 15)
          projectile(weapon, x: px, y: -40 - i * 36, vx: kind == "meteor" ? 85 : 12, vy: 130,
            damage: damage, life: 12 * TICK_RATE, drop_mine: kind == "mines", fire: kind == "napalm")
        end
      when "quake"
        worms.each do |w|
          next if w[:hp] <= 0 || w[:frozen]
          w[:vx] += (@rng.rand - 0.5) * 420
          w[:vy] = -90 - @rng.rand * 70
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
        hazards << {id: next_object_id, kind: kind, x: active[:x] + active[:facing] * 23, y: active[:y] - 2,
          owner: team[:id], armed: tick + TICK_RATE, life: 100_000, hp: 20, shots: 5}
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
        terrain.bridge(x, y)
        emit("build", x: x, y: y)
      when "drill", "torch"
        @tool = {kind: kind, until: tick + 60, direction: active[:facing], owner: team[:id], damage: damage, lift: 0, input_until: tick}
        active[:input] = active[:lift] = 0
      when "heal"
        amount = [35, active[:max_hp] - active[:hp]].min
        active[:hp] += amount
        active[:poisoned] = false
        emit("heal", x: active[:x], y: active[:y] - 20, amount: amount)
      when "shield"
        active[:shield] = true
      when "freeze"
        worms.select { |w| w[:team] == team[:id] }.each { |w| w[:frozen] = true }
      when "boost"
        @damage_boost = true
      when "gravity"
        @low_gravity = true
      when "wind"
        @wind = (-wind * 2).clamp(-4.0, 4.0)
      when "skip"
        # Passing still waits for a safe settled turn boundary.
      end
      resolve_turn(retreat: !%w[teleport girder heal freeze skip].include?(kind)) unless Catalog::UTILITY.include?(kind)
    end

    def validate_tool(kind, x, y)
      if kind == "teleport"
        landing = terrain.landing(x, y, water: water)
        if !landing || worms.any? { |w| w[:id] != active_id && w[:hp] > 0 && Math.hypot(w[:x] - x, w[:y] - landing) < 25 }
          raise RuleError, "Choose clear ground above the water."
        end
      elsif kind == "girder"
        if !x.between?(80, world_width - 80) || !y.between?(100, water - 30) ||
            (-70..70).step(10).any? { |dx| terrain.solid?(x + dx, y) || terrain.solid?(x + dx, y + 12) } ||
            worms.any? { |w| w[:hp] > 0 && (w[:x] - x).abs < 83 && (w[:y] - 10 - y).abs < 27 }
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
        else
          p[:life] = 0
        end
        emit("activate", weapon: p[:weapon], x: p[:x], y: p[:y], stage: p[:stage])
      elsif @tool
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
      hazards << {id: next_object_id, kind: "fire", x: x, y: y, owner: owner, radius: radius, life: 4 * TICK_RATE}
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
        shot[:x], shot[:y] = shooter[:x], shooter[:y] - 12
        fire_ray(shot)
        true
      end
    end

    def fire_ray(shot)
      angle, damage, radius, kind, range = shot.values_at(:angle, :damage, :radius, :kind, :range)
      x, y = shot.values_at(:x, :y)
      start_x, start_y = x, y
      hit_ids = []
      (range / 3).times do
        x += Math.cos(angle) * 3
        y += Math.sin(angle) * 3
        break unless x.between?(0, world_width) && y.between?(0, world_height)
        # Terrain takes precedence: a bullet cannot hit a body through a wall.
        if terrain.solid?(x, y)
          terrain.carve(x, y, radius)
          break unless kind == "laser"
        end
        victim = worms.find { |w| w[:hp] > 0 && w[:id] != shot[:shooter] && !hit_ids.include?(w[:id]) && Math.hypot(w[:x] - x, w[:y] - 10 - y) < 13 }
        if victim
          hurt(victim, damage, source: shot[:owner])
          unless victim[:frozen] || victim[:hp] <= 0
            victim[:vx] += Math.cos(angle) * 40
            victim[:vy] -= 22
          end
          hit_ids << victim[:id]
          break unless kind == "laser"
        end
      end
      fire_patch(x, y, shot[:owner], radius: 24) if kind == "flame"
      emit("beam", x: start_x, y: start_y, x2: x, y2: y, style: kind)
    end

    def melee(weapon, damage, angle)
      if weapon[:kind] == "dash"
        @tool = {kind: "dash", until: tick + 12, direction: active[:facing], owner: team[:id], damage: damage, hits: []}
        active[:input] = active[:lift] = 0
        return
      end
      reach = weapon[:kind] == "dash" ? 120 : 56
      victims = worms.select do |w|
        w[:id] != active_id && w[:hp] > 0 && (w[:x] - active[:x]) * active[:facing] >= -5 &&
          Math.hypot(w[:x] - active[:x], w[:y] - active[:y]) < reach &&
          (weapon[:kind] == "dash" || clear_line?(active[:x], active[:y] - 10, w[:x], w[:y] - 10))
      end
      victims.each do |w|
        hit = weapon[:id] == "axe" ? (w[:hp] / 2.0).ceil : damage
        hurt(w, hit, source: team[:id])
        next if w[:frozen] || w[:hp] <= 0
        force = weapon[:id] == "bat" ? 490 : weapon[:id] == "prod" ? 180 : 200
        w[:vx] = active[:facing] * force * [Math.cos(angle).abs, 0.35].max
        w[:vy] = weapon[:id] == "axe" ? -25 : -[Math.sin(angle).abs * force, 90].max
        w[:vx], w[:vy] = active[:facing] * 95, -235 if weapon[:id] == "fire_punch"
      end
      active[:vy] = -135 if weapon[:id] == "fire_punch"
      emit("melee", x: active[:x], y: active[:y] - 10, style: weapon[:id], facing: active[:facing])
    end

    def update_tool
      return unless @tool
      if tick >= @tool[:until] || active[:hp] <= 0
        @tool = nil
        return
      end
      if @tool[:kind] == "dash"
        x = (active[:x] + @tool[:direction] * 9).clamp(12, world_width - 12)
        terrain.carve(x, active[:y] - 10, 23)
        active[:x] = x
        worms.each do |w|
          next if w[:id] == active_id || w[:hp] <= 0 || @tool[:hits].include?(w[:id]) || Math.hypot(w[:x] - x, w[:y] - active[:y]) > 33
          @tool[:hits] << w[:id]
          hurt(w, @tool[:damage], source: @tool[:owner])
          w[:vx], w[:vy] = @tool[:direction] * 230, -95 if w[:hp] > 0 && !w[:frozen]
        end
        emit("melee", x: x, y: active[:y] - 10, style: "dragon_punch", facing: active[:facing]) if tick % 3 == 0
        return
      end
      return unless tick % 3 == 0
      drilling = @tool[:kind] == "drill"
      x = active[:x] + (drilling ? 0 : @tool[:direction] * 9)
      lift = tick <= @tool.fetch(:input_until, 0) ? @tool.fetch(:lift, 0) : 0
      y = active[:y] + (drilling ? 8 : -10 - lift * 7)
      terrain.carve(x, y, drilling ? 22 : 25)
      active[:x] = x.clamp(12, world_width - 12) unless drilling
      active[:y] += 4 if drilling
      active[:y] -= lift * 4 unless drilling
      worms.each do |w|
        next if w[:id] == active_id || w[:hp] <= 0 || Math.hypot(w[:x] - x, w[:y] - y) > 36
        hurt(w, (@tool[:damage] / 10.0).ceil, source: @tool[:owner])
      end
      emit("dig", x: x, y: y, radius: 22)
    end
  end
end
