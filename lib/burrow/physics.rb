# frozen_string_literal: true

module Burrow
  module Physics
    def gravity = 285 * config["gravity"] * (@low_gravity ? 0.45 : 1)
    def grounded?(w) = terrain.solid?(w[:x] - 6, w[:y] + 1) || terrain.solid?(w[:x] + 6, w[:y] + 1)

    def update_worms
      interrupt_displaced_tool
      worms.each do |w|
        next if w[:hp] <= 0
        was_grounded = grounded?(w) && w[:vy] >= 0
        tumbling = w[:launched]
        controlled = w[:id] == active_id && %w[aiming retreat].include?(phase) && tick <= w[:input_until] && !w[:frozen] && !@tool && !tumbling
        direction = controlled ? w[:input] : 0
        lift = controlled ? w[:lift] : 0
        if w[:id] == active_id && @tool && %w[drill torch dash].include?(@tool[:kind])
          # Digging and dashing advance explicitly in update_tool. Letting gravity
          # integrate here turns a two-second drill into an uncontrolled fall.
          w[:vx] = w[:vy] = 0.0
        elsif w[:frozen]
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
        elsif tumbling
          # A blasted grub keeps its momentum, rebounds and slides to a stop.
          w[:vx] *= was_grounded ? 0.86 : 0.995
          w[:vy] += gravity * DT unless was_grounded
          if was_grounded && w[:vx].abs < 16
            w[:launched] = tumbling = false
            w[:vx] = 0.0
          end
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
          elsif was_grounded && (!direction.zero? || tumbling) && (up = (1..(tumbling ? 5 : 7)).find { |offset| body_clear?(nx, w[:y] - offset) })
            w[:x], w[:y] = nx, w[:y] - up
          elsif tumbling && w[:vx].abs > 45
            # Tumbling grubs rebound off walls instead of sticking to them.
            w[:vx] = -w[:vx] * 0.45
            dx = 0
          else
            w[:vx] = 0
          end
          ny = w[:y] + dy / steps
          if dy >= 0 && (terrain.solid?(w[:x] - 6, ny) || terrain.solid?(w[:x] + 6, ny))
            impact = w[:vy]
            if tumbling && impact > 110
              w[:vy] = -impact * 0.3
              w[:vx] *= 0.8
              emit("bounce", x: w[:x], y: w[:y], worm: w[:id]) if impact > 170
            else
              w[:vy] = 0.0
              # Blast flights end in a tumble, not a fall: only drops hurt.
              if config["fall_damage"] && impact > 225 && !w[:parachute] && !w[:rope] && !tumbling
                hurt(w, ((impact - 225) * 0.16).round, source: nil)
              end
            end
            dy = 0
          elsif dy < 0 && !body_clear?(w[:x], ny)
            w[:vy] = tumbling ? -w[:vy] * 0.3 : 0.0
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
      w[:launched] = false
      w[:input] = w[:lift] = 0.0
      emit(reason == "water" ? "splash" : "defeat", worm: w[:id], x: w[:x], y: [w[:y], water].min, text: "#{w[:name]} is out")
    end

    def explode(x, y, damage:, radius:, owner:, kind: "blast", knock: 1.0)
      return if y > water + 15
      terrain.carve(x, y, radius)
      emit("explosion", x: x, y: y, radius: radius, style: kind)
      reach = radius + 27
      strength = (120 + damage * 2.2) * knock
      worms.each do |w|
        next if w[:hp] <= 0
        distance = Math.hypot(w[:x] - x, w[:y] - 10 - y)
        next if distance > reach || w[:frozen]
        ratio = (1 - distance / (reach + 1)).clamp(0.15, 1)
        hurt(w, (damage * ratio).round, source: owner)
        next if w[:hp] <= 0
        w[:rope] = nil
        throw_body(w, x, y + 10, strength * ratio, lift: (60 + 90 * ratio) * knock)
      end
      shove(x, y, reach, strength, owner)
    end

    # Push a body away from a blast centre, with extra lift off the ground.
    def throw_body(body, x, y, force, lift:)
      distance = Math.hypot(body[:x] - x, body[:y] - y)
      nx, ny = distance < 1 ? [0.0, -1.0] : [(body[:x] - x) / distance, (body[:y] - y) / distance]
      body[:vx] = body.fetch(:vx, 0.0) + nx * force
      body[:vy] = body.fetch(:vy, 0.0) + ny * force - lift
      body[:launched] = true
    end

    PROP_MASS = {"mine" => 0.8, "barrel" => 1.7, "crate" => 1.4, "turret" => 1.6, "flame" => 2.5}.freeze

    # A blast also moves the battlefield's loose objects: resting bombs roll away,
    # mines and barrels fly, close mines arm a short fuse and barrels rupture.
    def shove(x, y, reach, strength, owner)
      projectiles.each do |p|
        next unless p[:bounce] && !p[:attached_to] && p[:life] > 0
        distance = Math.hypot(p[:x] - x, p[:y] - y)
        next if distance > reach
        ratio = (1 - distance / (reach + 1)).clamp(0.15, 1)
        throw_body(p, x, y, strength * ratio * 0.8, lift: 50 * ratio)
        p[:stuck], p[:support_x], p[:support_y] = false, nil, nil
      end
      hazards.each do |h|
        mass = PROP_MASS[h[:kind]]
        next unless mass
        distance = Math.hypot(h[:x] - x, h[:y] - 8 - y)
        next if distance > reach
        ratio = (1 - distance / (reach + 1)).clamp(0.15, 1)
        throw_body(h, x, y + 8, strength * ratio / mass, lift: 70 * ratio / mass)
        h[:chute] = false
        case h[:kind]
        when "mine", "crate", "turret"
          ignite(h, owner, 8 + @rng.rand(10)) if ratio > (h[:kind] == "mine" ? 0.5 : 0.6)
        when "barrel"
          h[:hp] = h.fetch(:hp, 20) - (strength * ratio / 9)
          ignite(h, owner, 4 + @rng.rand(6)) if h[:hp] <= 0
        end
      end
    end

    def ignite(h, owner, delay)
      return if h[:trigger] && h[:trigger] <= tick + delay
      h[:trigger] = tick + delay
      h[:blame] = owner
    end

    def detonate_hazard(h)
      hazards.delete(h)
      case h[:kind]
      when "barrel"
        emit("barrel_rupture", hazard_id: h[:id], style: "barrel", hazard_kind: "barrel", x: h[:x], y: h[:y], owner: h[:blame] || h[:owner])
        weapon = Catalog.fetch("barrel")
        explode(h[:x], h[:y] - 14, damage: weapon[:damage], radius: weapon[:radius], owner: h[:blame] || h[:owner], kind: "barrel")
        # Spilled fuel keeps burning.
        7.times { |i| flame(h[:x], h[:y] - 18, h[:blame] || h[:owner], vx: (i - 3) * 38 + @rng.rand(-12.0..12.0), vy: -110 - @rng.rand(90.0)) }
      when "mine"
        explode(h[:x], h[:y] - 4, damage: 48, radius: 44, owner: h[:blame] || h[:owner], kind: "mine")
      when "crate"
        explode(h[:x], h[:y] - 12, damage: 24, radius: 34, owner: h[:blame])
      when "turret"
        emit("defeat", x: h[:x], y: h[:y] - 10)
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
      elsif p[:homing] && p[:age] > TICK_RATE / 2 && p[:age] <= HOMING_TICKS
        # After a short ballistic launch the motor locks on: rotate towards the
        # beacon at a bounded rate, preserving speed through turns, and cruise
        # at a speed set by the launch power. Once the motor burns out it falls.
        desired = Math.atan2(p[:target_y] - p[:y], p[:target_x] - p[:x])
        heading = Math.atan2(p[:vy], p[:vx])
        delta = Math.atan2(Math.sin(desired - heading), Math.cos(desired - heading))
        heading += delta.clamp(-2.6 * DT, 2.6 * DT)
        cruise = p.fetch(:cruise, 670)
        speed = (Math.hypot(p[:vx], p[:vy]) + 160 * DT).clamp([260, cruise].min, cruise)
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
            # Bombs settle on level ground and keep rolling down steeper slopes.
            if !victim && p[:vx].abs < 12 && p[:vy].abs < 22 && normal[1] < -0.8
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

    HOMING_TICKS = TICK_RATE * 9 / 2
    BOUNCE = {"banana" => 0.72, "cluster" => 0.48, "mega_bomb" => 0.38, "holy_bomb" => 0.32,
      "dynamite" => 0.2, "poison" => 0.5}.freeze

    def reflect_projectile(p, nx, ny)
      dot = p[:vx] * nx + p[:vy] * ny
      return if dot >= 0
      bounce = BOUNCE.fetch(p[:weapon], 0.55)
      # Gentle contacts roll; hard impacts scrub off more speed along the surface.
      grip = dot > -40 ? 0.9 : 0.8
      tangent_x, tangent_y = p[:vx] - dot * nx, p[:vy] - dot * ny
      p[:vx] = tangent_x * grip - dot * nx * bounce
      p[:vy] = tangent_y * grip - dot * ny * bounce
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
      terrain.carve(nx, ny, 17, scorch: false)
      p[:dug] = true
      p[:x], p[:y] = nx, ny
      p[:life] = 0 if projectile_victim(p, nx, ny)
    end

    def update_hazards
      burning = []
      hazards.dup.each do |h|
        next unless hazards.include?(h)
        h[:life] -= 1
        case h[:kind]
        when "flame"
          update_flame(h)
          burning << h
        when "gas"
          # Poison drifts with the wind and rises slowly.
          h[:x] += wind * 9 * DT
          h[:y] -= 2.5 * DT
          poison_cloud(h) if tick % 15 == 0
        when "fire"
          # Saved games from before burning fuel became loose flames.
          if tick % 15 == 0
            worms.each { |w| hurt(w, 4, source: h[:owner]) if w[:hp] > 0 && Math.hypot(w[:x] - h[:x], w[:y] - 10 - h[:y]) <= h[:radius] }
          end
        else
          # Old checkpoints and hand-authored test fixtures may omit newer prop
          # fields.  Fill safe deterministic defaults before integrating motion.
          h[:armed] = tick if h[:kind] == "mine" && !h.key?(:armed)
          h[:hp] = h[:kind] == "barrel" ? 24 : 20 if %w[mine barrel turret crate].include?(h[:kind]) && !h.key?(:hp)
          h[:shots] = 5 if h[:kind] == "turret" && !h.key?(:shots)
          h[:facing] ||= 1 if %w[turret mine barrel].include?(h[:kind])
          if h[:kind] == "turret"
            h[:angle] ||= h[:facing].to_i.negative? ? Math::PI : 0.0
            h[:aim_angle] ||= h[:angle]
          end
          prop_motion(h)
          next unless hazards.include?(h)
          if h[:trigger] && tick >= h[:trigger]
            emit("hazard_trigger", hazard_id: h[:id], style: h[:kind], hazard_kind: h[:kind], x: h[:x], y: h[:y], owner: h[:blame] || h[:owner])
            detonate_hazard(h)
            next
          end
          if h[:kind] == "mine" && tick >= h[:armed].to_i && !h[:arm_reported]
            h[:arm_reported] = true
            emit("mine_arm", hazard_id: h[:id], style: "mine", hazard_kind: "mine", x: h[:x], y: h[:y], owner: h[:owner], fuse: 0)
          end
          proximity = h[:kind] == "mine" ? 36 : 25
          near = worms.select do |w|
            w[:hp] > 0 && Math.hypot(w[:x] - h[:x], w[:y] - h[:y]) < proximity &&
              (h[:kind] != "mine" || clear_line?(h[:x], h[:y] - 4, w[:x], w[:y] - 10))
          end
          if h[:kind] == "mine" && tick >= h[:armed].to_i && !near.empty?
            unless h[:trigger]
              h[:trigger] = tick + 18
              emit("mine_trigger", hazard_id: h[:id], style: "mine", hazard_kind: "mine", x: h[:x], y: h[:y], owner: h[:owner], fuse: 18)
            end
          elsif h[:kind] == "crate" && !near.empty? && !h[:trigger]
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
            next
          elsif h[:kind] == "turret" && tick >= h[:armed].to_i && tick % 35 == 0 && h[:shots].to_i > 0
            target = worms.select { |w| w[:hp] > 0 && !w[:frozen] && w[:team] != h[:owner] && Math.hypot(w[:x] - h[:x], w[:y] - h[:y]) < 420 }
              .find { |w| clear_line?(h[:x], h[:y] - 20, w[:x], w[:y] - 10) }
            if target
              h[:facing] = target[:x] < h[:x] ? -1 : 1
              h[:angle] = Math.atan2(target[:y] - 10 - (h[:y] - 20), target[:x] - h[:x])
              h[:aim_angle] = h[:angle]
              h[:target_id], h[:target_x], h[:target_y] = target[:id], target[:x], target[:y]
              hurt(target, 16, source: h[:owner])
              emit("beam", x: h[:x], y: h[:y] - 20, x2: target[:x], y2: target[:y] - 10,
                style: "turret", hazard: h[:id], facing: h[:facing], angle: h[:angle], shots: h[:shots] - 1)
              h[:shots] -= 1
            end
          end
        end
        if h[:y] > water + 5 && h[:kind] != "gas"
          hazards.delete(h)
          emit("splash", x: h[:x].clamp(0, world_width), y: water) if PROP_MASS[h[:kind]] && h[:kind] != "flame"
        elsif h[:life] <= 0
          hazards.delete(h)
        end
      end
      scald(burning) if tick % 10 == 0 && !burning.empty?
    end

    def poison_cloud(h)
      worms.each do |w|
        next if w[:hp] <= 0 || Math.hypot(w[:x] - h[:x], w[:y] - 10 - h[:y]) > h[:radius]
        w[:poisoned] = true unless w[:frozen] || (w[:team] == h[:owner] && !config["friendly_fire"])
      end
    end

    # Loose props fall, bounce, slide and settle; parachuted crates drift down.
    def prop_motion(h)
      vx, vy = h.fetch(:vx, 0.0), h.fetch(:vy, 0.0)
      grounded = terrain.solid?(h[:x], h[:y] + 1)
      if grounded && vy >= 0 && vx.abs < 8
        h[:vx] = h[:vy] = 0.0 if vx != 0 || vy != 0
        h[:chute] = false
        return
      end
      if h[:chute]
        vx, vy = wind * 14, 40.0
      else
        vy += gravity * DT unless grounded && vy >= 0
        vx *= grounded ? 0.8 : 0.995
      end
      steps = [((vx.abs + vy.abs) * DT / 2).ceil, 1].max
      steps.times do
        nx = (h[:x] + vx * DT / steps).clamp(6, world_width - 6)
        if terrain.solid?(nx, h[:y] - 6)
          vx = -vx * 0.35
        else
          h[:x] = nx
        end
        ny = h[:y] + vy * DT / steps
        if vy > 0 && terrain.solid?(h[:x], ny)
          vy = vy > 90 && !h[:chute] ? -vy * 0.3 : 0.0
          vx *= 0.8
          h[:chute] = false
          break
        elsif vy < 0 && terrain.solid?(h[:x], ny - 14)
          vy = 0.0
        else
          h[:y] = ny
        end
      end
      h[:vx], h[:vy] = vx, vy
    end

    # Burning fuel: falls, slides downhill along the ground and fizzles out.
    def flame(x, y, owner, vx: 0.0, vy: 0.0)
      return if hazards.count { |h| h[:kind] == "flame" } >= 60
      hazards << {id: next_object_id, kind: "flame", x: x.to_f, y: y.to_f, vx: vx.to_f, vy: vy.to_f,
        owner: owner, life: 3 * TICK_RATE + @rng.rand(2 * TICK_RATE), radius: 10}
    end

    def update_flame(h)
      grounded = terrain.solid?(h[:x], h[:y] + 1)
      if grounded && h[:vy] >= 0
        h[:vy] = 0.0
        h[:vx] *= 0.88
        # Creep down a slope: compare the ground a few pixels to either side.
        left, right = terrain.solid?(h[:x] - 5, h[:y] + 4), terrain.solid?(h[:x] + 5, h[:y] + 4)
        h[:vx] += left && !right ? 9 : right && !left ? -9 : 0
      else
        h[:vy] = [h[:vy] + gravity * 0.8 * DT, 260].min
        h[:vx] += wind * 18 * DT
      end
      steps = [((h[:vx].abs + h[:vy].abs) * DT / 2).ceil, 1].max
      steps.times do
        nx = (h[:x] + h[:vx] * DT / steps).clamp(4, world_width - 4)
        if terrain.solid?(nx, h[:y] - 3)
          h[:vx] = 0.0
        else
          h[:x] = nx
        end
        ny = h[:y] + h[:vy] * DT / steps
        if h[:vy] > 0 && terrain.solid?(h[:x], ny)
          h[:vy] = 0.0
          break
        elsif h[:vy] < 0 && terrain.solid?(h[:x], ny - 6)
          h[:vy] = 0.0
        else
          h[:y] = ny
        end
      end
    end

    # Each grub standing in fire takes one scald per check, however many flames.
    def scald(flames)
      worms.each do |w|
        next if w[:hp] <= 0
        source = flames.find { |h| (h[:x] - w[:x]).abs < 13 && (h[:y] - w[:y] + 8).abs < 16 }
        next unless source
        hurt(w, 3, source: source[:owner])
        w[:vy] = -70.0 if w[:hp] > 0 && !w[:frozen] && grounded?(w) # a hot-footed hop
      end
    end

    def clear_line?(x, y, tx, ty)
      limit = Math.hypot(tx - x, ty - y)
      !terrain.ray(x, y, tx - x, ty - y, limit: [limit - 8, 0].max, step: 2)
    end
  end
end
