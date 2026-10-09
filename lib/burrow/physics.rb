# frozen_string_literal: true

module Burrow
  module Physics
    def gravity = 285 * config["gravity"] * (@low_gravity ? 0.45 : 1)
    def grounded?(w) = terrain.solid?(w[:x] - 6, w[:y] + 1) || terrain.solid?(w[:x] + 6, w[:y] + 1)

    def update_worms
      worms.each do |w|
        next if w[:hp] <= 0
        was_grounded = grounded?(w) && w[:vy] >= 0
        controlled = w[:id] == active_id && %w[aiming retreat].include?(phase) && tick <= w[:input_until] && !w[:frozen] && !@tool
        direction = controlled ? w[:input] : 0
        lift = controlled ? w[:lift] : 0
        if w[:frozen]
          w[:vx] = 0.0
          w[:vy] = was_grounded ? 0.0 : w[:vy] + gravity * DT
        elsif w[:fuel] > 0
          w[:fuel] -= 1 if !direction.zero? || !lift.zero?
          w[:vx] = w[:vx] * 0.92 + direction * 14
          w[:vy] += gravity * DT - lift * 23
          w[:vy] = w[:vy].clamp(-130, 170)
          if w[:fuel] <= 0
            w[:jetpack] = false
            w[:parachute] = true
          end
        elsif w[:rope]
          w[:rope][:length] = (w[:rope][:length] - lift * 105 * DT).clamp(28, 460)
          w[:vx] = w[:vx] * 0.995 + direction * 5
          w[:vy] += gravity * DT
        elsif was_grounded && !direction.zero?
          w[:vx] = direction * 72
          w[:vy] = 0
        else
          w[:vx] *= was_grounded ? 0.68 : 0.985
          w[:vx] += direction * 3 if w[:parachute] && !was_grounded
          w[:vy] += gravity * DT unless was_grounded
          w[:vy] = [w[:vy], 65].min if w[:parachute]
        end
        w[:vx] = 0.0 if w[:vx].abs < 0.3
        dx, dy = w[:vx] * DT, w[:vy] * DT
        steps = [(dx.abs + dy.abs).fdiv(2).ceil, 1].max
        steps.times do
          nx = (w[:x] + dx / steps).clamp(10, world_width - 10)
          if body_clear?(nx, w[:y])
            w[:x] = nx
          elsif was_grounded && !direction.zero? && (1..7).any? { |up| body_clear?(nx, w[:y] - up) }
            up = (1..7).find { |offset| body_clear?(nx, w[:y] - offset) }
            w[:x], w[:y] = nx, w[:y] - up
          else
            w[:vx] = 0
          end
          ny = w[:y] + dy / steps
          if dy >= 0 && (terrain.solid?(w[:x] - 6, ny) || terrain.solid?(w[:x] + 6, ny))
            impact = w[:vy]
            w[:vy] = 0.0
            dy = 0
            if config["fall_damage"] && impact > 225 && !w[:parachute] && !w[:rope]
              hurt(w, ((impact - 225) * 0.16).round, source: nil)
            end
          elsif dy < 0 && !body_clear?(w[:x], ny)
            w[:vy] = 0.0
            dy = 0
          else
            w[:y] = ny
          end
        end
        if (rope = w[:rope])
          unless terrain.solid?(rope[:x], rope[:y])
            w[:rope] = nil
            kill(w, "water") if w[:y] >= water + 10 || w[:y] > world_height
            next
          end
          dxr, dyr = w[:x] - rope[:x], w[:y] - 12 - rope[:y]
          distance = Math.hypot(dxr, dyr)
          if distance > rope[:length]
            nx, ny = rope[:x] + dxr / distance * rope[:length], rope[:y] + dyr / distance * rope[:length] + 12
            correction = [(Math.hypot(nx - w[:x], ny - w[:y]) / 2).ceil, 1].max
            path_clear = (1..correction).all? do |part|
              body_clear?(w[:x] + (nx - w[:x]) * part / correction, w[:y] + (ny - w[:y]) * part / correction)
            end
            if path_clear
              w[:x], w[:y] = nx, ny
              dot = [(w[:vx] * dxr + w[:vy] * dyr) / distance**2, 0].max
              w[:vx] -= dot * dxr
              w[:vy] -= dot * dyr
            else
              # Do not accumulate impossible reeling through an overhang.
              rope[:length] = distance.clamp(28, 460)
            end
          end
        end
        kill(w, "water") if w[:y] >= water + 10 || w[:y] > world_height
      end
    end

    def body_clear?(x, y)
      [-6, 0, 6].all? { |dx| [-18, -9, -1].all? { |dy| !terrain.solid?(x + dx, y + dy) } }
    end

    def hurt(w, amount, source:, poison: false)
      return if w[:hp] <= 0 || w[:frozen]
      return if source == w[:team] && !config["friendly_fire"]
      amount = (amount * config["damage"] * (w[:shield] ? 0.5 : 1)).round
      amount = [amount, w[:hp] - 1].min if poison
      amount = [amount, w[:hp]].min
      return if amount <= 0
      w[:hp] -= amount
      scoring_team = teams.find { |t| t[:id] == source }
      scoring_team[:score] += amount if scoring_team && source != w[:team]
      emit("damage", worm: w[:id], x: w[:x], y: w[:y] - 22, amount: amount)
      if w[:hp] <= 0
        w[:hp] = 1
        kill(w, "blast")
      end
    end

    def kill(w, reason)
      return if w[:hp] <= 0
      w[:hp] = 0
      w[:vx] = w[:vy] = 0.0
      w[:rope] = nil
      w[:fuel], w[:jetpack] = 0, false
      w[:input] = w[:lift] = 0.0
      emit(reason == "water" ? "splash" : "defeat", worm: w[:id], x: w[:x], y: [w[:y], water].min, text: "#{w[:name]} is out")
    end

    def explode(x, y, damage:, radius:, owner:, kind: "blast", knock: 1.0)
      return if y > water + 15
      terrain.carve(x, y, radius)
      emit("explosion", x: x, y: y, radius: radius, style: kind)
      reach = radius + 27
      worms.each do |w|
        next if w[:hp] <= 0
        distance = Math.hypot(w[:x] - x, w[:y] - 10 - y)
        next if distance > reach || w[:frozen]
        ratio = (1 - distance / (reach + 1)).clamp(0.15, 1)
        hurt(w, (damage * ratio).round, source: owner)
        next if w[:hp] <= 0
        dx = (w[:x] - x) / [distance, 1].max
        w[:vx] += dx * ratio * 270 * knock
        w[:vy] -= (85 + ratio * 160) * knock
        w[:rope] = nil
      end
      chain = hazards.select { |h| %w[mine barrel turret crate].include?(h[:kind]) && Math.hypot(h[:x] - x, h[:y] - y) < reach }
      chain.each { |h| hazards.delete(h) }
      chain.each do |h|
        next if h[:kind] == "crate" || h[:kind] == "turret"
        weapon = Catalog.fetch(h[:kind])
        explode(h[:x], h[:y] - 4, damage: weapon[:damage], radius: weapon[:radius], owner: owner)
      end
    end

    def update_projectiles
      projectiles.dup.each do |p|
        next unless projectiles.include?(p)
        if p[:delay].to_i > 0
          p[:delay] -= 1
          next if p[:delay] > 0
        end
        p[:age] += 1
        p[:life] -= 1
        if p[:life] > 0
          if p[:stage] == "digging"
            advance_digger(p)
          elsif p[:walker]
            advance_walker(p)
          else
            advance_projectile(p)
          end
        end
        # The choir bomb finishes its count, then waits for a resting position.
        p[:life] = 1 if p[:weapon] == "holy_bomb" && p[:life] <= 0 && !p[:stuck] && p[:age] < 12 * TICK_RATE
        outside = p[:y] > (p[:homing] ? world_height + 40 : water) || p[:x] < -80 || p[:x] > world_width + 80 || p[:y] < -800
        record_projectile(p, ended: outside || p[:life] <= 0)
        if outside
          projectiles.delete(p)
          emit("splash", x: p[:x].clamp(0, world_width), y: water) if p[:y] > water
        elsif p[:life] <= 0
          projectiles.delete(p)
          detonate(p)
        end
      end
    end

    def advance_projectile(p)
      if p[:stuck]
        if p[:attached_to] && (w = worms.find { |worm| worm[:id] == p[:attached_to] && worm[:hp] > 0 })
          p[:x], p[:y] = w[:x] + p[:attach_dx], w[:y] + p[:attach_dy]
          return
        end
        return if p[:support_x] && terrain.solid?(p[:support_x], p[:support_y])
        return if !p[:support_x] && terrain.solid?(p[:x], p[:y] + 3) # old saves
        p[:stuck], p[:attached_to] = false, nil
      end
      if p[:guided]
        steering = tick <= p.fetch(:input_until, 0) ? p.fetch(:steer, 0) : 0
        p[:heading] = p.fetch(:heading, Math.atan2(p[:vy], p[:vx])) + steering * 2.9 * DT
        p[:vx], p[:vy] = Math.cos(p[:heading]) * 230, Math.sin(p[:heading]) * 230
      elsif p[:homing] && p[:age] > TICK_RATE / 2
        # Rotate towards the beacon at a bounded rate, preserving speed through
        # turns. Vector blending used to stall rockets on a target behind them.
        desired = Math.atan2(p[:target_y] - p[:y], p[:target_x] - p[:x])
        heading = Math.atan2(p[:vy], p[:vx])
        delta = Math.atan2(Math.sin(desired - heading), Math.cos(desired - heading))
        heading += delta.clamp(-2.6 * DT, 2.6 * DT)
        speed = (Math.hypot(p[:vx], p[:vy]) + 100 * DT).clamp(260, 670)
        p[:vx], p[:vy] = Math.cos(heading) * speed, Math.sin(heading) * speed
      else
        p[:vx] += wind * 42 * DT if p[:wind]
        p[:vy] += gravity * DT
      end
      steps = [(Math.hypot(p[:vx], p[:vy]) * DT / 1.5).ceil, 1].max
      steps.times do
        nx, ny = p[:x] + p[:vx] * DT / steps, p[:y] + p[:vy] * DT / steps
        victim = projectile_victim(p, nx, ny)
        solid = terrain.solid?(nx, ny)
        if solid && p[:stage] == "diving"
          p[:stage] = "digging"
          p[:vx], p[:vy] = p[:direction] * 52.0, 76.0
          advance_digger(p)
          break
        elsif solid || victim
          if p[:sticky]
            p[:stuck] = true
            p[:vx] = p[:vy] = 0.0
            if victim
              p[:attached_to], p[:attach_dx], p[:attach_dy] = victim[:id], p[:x] - victim[:x], p[:y] - victim[:y]
            else
              p[:support_x], p[:support_y] = nx, ny
            end
          elsif p[:bounce]
            normal = if victim
              dx, dy = p[:x] - victim[:x], p[:y] - victim[:y] + 10
              distance = [Math.hypot(dx, dy), 0.001].max
              [dx / distance, dy / distance]
            else
              terrain_normal(nx, ny, p)
            end
            reflect_projectile(p, *normal)
            if !victim && p[:vx].abs < 12 && p[:vy].abs < 22 && normal[1] < -0.35
              p[:stuck] = true
              p[:support_x], p[:support_y] = nx, ny
              p[:vx] = p[:vy] = 0.0
            end
            emit("bounce", x: p[:x], y: p[:y]) if p[:age] - p.fetch(:last_bounce, -10) > 2
            p[:last_bounce] = p[:age]
          else
            p[:life] = 0
          end
          break
        else
          p[:x], p[:y] = nx, ny
        end
      end
    end

    def projectile_victim(p, x, y)
      shooter = worms.find { |w| w[:id] == p[:shooter] }
      p[:cleared_shooter] = true if !shooter || Math.hypot(shooter[:x] - x, shooter[:y] - 10 - y) > 18
      worms.find do |w|
        w[:hp] > 0 && (w[:id] != p[:shooter] || p[:cleared_shooter]) && Math.hypot(w[:x] - x, w[:y] - 10 - y) < 12
      end
    end

    def terrain_normal(x, y, p)
      # Average a small patch of the collision mask, so sloping hills bounce
      # along their surface normal rather than behaving like vertical walls.
      gx = gy = 0.0
      [-4, -2, 0, 2, 4].each do |dx|
        [-4, -2, 0, 2, 4].each do |dy|
          next unless terrain.solid?(x + dx, y + dy)
          gx -= dx
          gy -= dy
        end
      end
      length = Math.hypot(gx, gy)
      if length < 0.01 || gx * p[:vx] + gy * p[:vy] >= 0
        gx, gy = terrain.solid?(x, p[:y]) ? [-p[:vx], 0.0] : [0.0, -p[:vy]]
        length = [Math.hypot(gx, gy), 0.001].max
      end
      [gx / length, gy / length]
    end

    def reflect_projectile(p, nx, ny)
      dot = p[:vx] * nx + p[:vy] * ny
      return if dot >= 0
      bounce = p[:weapon] == "banana" ? 0.72 : 0.55
      tangent_x, tangent_y = p[:vx] - dot * nx, p[:vy] - dot * ny
      p[:vx] = tangent_x * 0.8 - dot * nx * bounce
      p[:vy] = tangent_y * 0.8 - dot * ny * bounce
    end

    def walker_clear?(x, y)
      [-5, 5].all? { |dx| [-5, 0, 5].all? { |dy| !terrain.solid?(x + dx, y + dy) } }
    end

    def advance_walker(p)
      direction = p.fetch(:direction, p[:vx] < 0 ? -1 : 1)
      p[:direction] = direction
      p[:vx] = direction * 105.0
      grounded = terrain.solid?(p[:x] - 4, p[:y] + 7) || terrain.solid?(p[:x] + 4, p[:y] + 7)
      p[:vy] += gravity * DT
      steps = [((p[:vx].abs + p[:vy].abs) * DT / 2).ceil, 1].max
      steps.times do
        nx = p[:x] + p[:vx] * DT / steps
        if walker_clear?(nx, p[:y])
          p[:x] = nx
          p[:blocked] = 0
        elsif grounded && (up = (1..6).find { |offset| walker_clear?(nx, p[:y] - offset) })
          p[:x], p[:y] = nx, p[:y] - up
        elsif p[:kind] == "herd"
          p[:life] = 0
          break
        else
          p[:blocked] = p.fetch(:blocked, 0) + 1
          p[:vy] = -165 if grounded
          p[:direction] *= -1 if p[:blocked] % 24 == 0
        end
        ny = p[:y] + p[:vy] * DT / steps
        if walker_clear?(p[:x], ny)
          p[:y] = ny
        else
          p[:vy] = 0.0
        end
      end
      # Sheep attempt a jump at a ledge; cows commit to their direction.
      if grounded && p[:kind] != "herd" && !terrain.solid?(p[:x] + direction * 12, p[:y] + 12)
        p[:vy] = -135
      end
      if p[:spraying] && p[:age] % 12 == 0
        gas_cloud(p[:x], p[:y] - 6, p[:owner], radius: 35, life: 150)
      end
      p[:life] = 0 if p[:kind] == "herd" && projectile_victim(p, p[:x], p[:y])
    end

    def advance_digger(p)
      nx, ny = p[:x] + p[:vx] * DT, p[:y] + p[:vy] * DT
      # Probe ahead of the tunnel we just carved, not its empty centre.
      in_earth = terrain.solid?(nx + p[:direction] * 13, ny + 19)
      if p[:dug] && !in_earth
        p[:life] = 0
        return
      end
      terrain.carve(nx, ny, 17)
      p[:dug] = true
      p[:x], p[:y] = nx, ny
      p[:life] = 0 if projectile_victim(p, nx, ny)
    end

    def update_hazards
      hazards.dup.each do |h|
        next unless hazards.include?(h)
        h[:life] -= 1
        if %w[fire gas].include?(h[:kind])
          if tick % 15 == 0
            worms.each do |w|
              next if w[:hp] <= 0 || Math.hypot(w[:x] - h[:x], w[:y] - 10 - h[:y]) > h[:radius]
              if h[:kind] == "gas"
                w[:poisoned] = true unless w[:frozen] || (w[:team] == h[:owner] && !config["friendly_fire"])
              else
                hurt(w, 4, source: h[:owner])
              end
            end
          end
        else
          # Sweep falling props so narrow bridges can catch them too.
          (h[:kind] == "crate" ? 2 : 4).times do
            break if terrain.solid?(h[:x], h[:y] + 1)
            h[:y] += h[:kind] == "crate" ? 0.65 : 1.0
          end
          near = worms.select { |w| w[:hp] > 0 && Math.hypot(w[:x] - h[:x], w[:y] - h[:y]) < 25 }
          if h[:kind] == "mine" && tick >= h[:armed] && !near.empty?
            h[:trigger] ||= tick + 18
          end
          if h[:trigger] && tick >= h[:trigger]
            hazards.delete(h)
            explode(h[:x], h[:y] - 4, damage: 48, radius: 44, owner: h[:owner])
          elsif h[:kind] == "crate" && !near.empty?
            collector = near.first
            if h[:supply] == "health"
              collector[:hp] = [collector[:hp] + 30, collector[:max_hp]].min
              collector[:poisoned] = false
            else
              inv = teams.find { |t| t[:id] == collector[:team] }[:inventory]
              inv[h[:supply]] += 1 if inv[h[:supply]] >= 0
            end
            hazards.delete(h)
            emit("pickup", x: h[:x], y: h[:y], text: h[:supply] == "health" ? "+30 health" : Catalog.fetch(h[:supply])[:name])
          elsif h[:kind] == "turret" && tick >= h[:armed] && tick % 35 == 0 && h[:shots] > 0
            target = worms.select { |w| w[:hp] > 0 && w[:team] != h[:owner] && Math.hypot(w[:x] - h[:x], w[:y] - h[:y]) < 270 }
              .find { |w| clear_line?(h[:x], h[:y] - 20, w[:x], w[:y] - 10) }
            if target
              hurt(target, 16, source: h[:owner])
              emit("beam", x: h[:x], y: h[:y] - 20, x2: target[:x], y2: target[:y] - 10, style: "turret")
              h[:shots] -= 1
            end
          end
        end
        hazards.delete(h) if h[:life] <= 0 || h[:y] > water + 5
      end
    end

    def clear_line?(x, y, tx, ty)
      limit = Math.hypot(tx - x, ty - y)
      !terrain.ray(x, y, tx - x, ty - y, limit: [limit - 8, 0].max)
    end
  end
end
