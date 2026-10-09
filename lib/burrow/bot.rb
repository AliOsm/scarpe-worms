# frozen_string_literal: true

module Burrow
  module Bot
    module_function

    # Score real ballistic traces, including terrain and wind. No privileged teleporting,
    # aiming through walls, or damage calls: the bot submits the same commands as a player.
    def choose(match)
      actor = match.active
      enemies = match.worms.select { |w| w[:hp] > 0 && w[:team] != actor[:team] }
      target = enemies.min_by { |w| Math.hypot(w[:x] - actor[:x], w[:y] - actor[:y]) }
      return {"weapon" => "skip"} unless target
      inventory = match.team[:inventory]
      available = ->(id) { inventory[id] != 0 }
      if actor[:hp] <= 35 && available.call("heal")
        return {"weapon" => "heal"}
      end
      if match.turn % 5 == 0 && match.config["terrain"] != "cavern" && available.call("airstrike")
        return {"weapon" => "airstrike", "x" => target[:x], "y" => target[:y]}
      end
      dx, dy = target[:x] - actor[:x], target[:y] - actor[:y]
      angle = Math.atan2(dy, dx) * 180 / Math::PI
      if Math.hypot(dx, dy) < 50 && available.call("bat")
        return {"weapon" => "bat", "angle" => dx < 0 ? -140 : -40}
      end
      if available.call("shotgun") && match.send(:clear_line?, actor[:x], actor[:y] - 12, target[:x], target[:y] - 10)
        return {"weapon" => "shotgun", "angle" => angle}
      end
      if available.call("rocket")
        return {"search" => true, "left" => dx < 0, "index" => 0, "best" => nil}
      end
      if available.call("grenade")
        return {"weapon" => "grenade", "angle" => dx < 0 ? -140 : -40, "power" => [Math.hypot(dx, dy) / 1000, 0.1].max.clamp(0.05, 1), "fuse" => 3}
      end
      {"weapon" => "skip"}
    end

    # A fixed four traces per tick bounds latency without wall-clock-dependent AI.
    # The tiny plan is JSON-safe, so a restart midway through aiming is identical.
    def advance_search(match, plan)
      actor = match.active
      enemies = match.worms.select { |w| w[:hp] > 0 && w[:team] != actor[:team] }
      friends = match.worms.select { |w| w[:hp] > 0 && w[:team] == actor[:team] }
      return {"weapon" => "skip"} if enemies.empty?
      4.times do
        index = plan["index"]
        break if index >= 128
        degrees = (plan["left"] ? -170 : -85) + (index / 8) * 5
        power = (index % 8 + 1) / 8.0
        x, y = impact(match, degrees, power)
        score = enemies.map { |w| Math.hypot(w[:x] - x, w[:y] - 10 - y) }.min
        friendly = friends.map { |w| Math.hypot(w[:x] - x, w[:y] - y) }.min
        score += (80 - friendly).clamp(0, 80) * 3
        plan["best"] = [score, degrees, power] if !plan["best"] || score < plan["best"][0]
        plan["index"] += 1
      end
      return unless plan["index"] >= 128
      {"weapon" => "rocket", "angle" => plan["best"][1], "power" => plan["best"][2]}
    end

    def impact(match, degrees, power)
      angle = degrees * Math::PI / 180
      x = match.active[:x] + Math.cos(angle) * 20
      y = match.active[:y] - 13 + Math.sin(angle) * 20
      vx, vy = Math.cos(angle) * (130 + power * 540), Math.sin(angle) * (130 + power * 540)
      240.times do |tick|
        vx += match.wind * 42 * DT
        vy += match.send(:gravity) * DT
        3.times do
          x += vx * DT / 3
          y += vy * DT / 3
          hit = tick > 5 && match.worms.any? { |w| w[:hp] > 0 && Math.hypot(w[:x] - x, w[:y] - 10 - y) < 12 }
          return [x, y] if hit || match.terrain.solid?(x, y) || y > match.water || x < 0 || x > match.world_width
        end
      end
      [x, y]
    end
  end

  class Match
    private

    def run_bot
      return unless tick >= @bot_at
      if @bot_search
        values = Bot.advance_search(self, @bot_search)
        return unless values
        @bot_search = nil
      else
        values = @shots_left > 0 ? {"weapon" => "shotgun", "angle" => @bot_angle || -40} : Bot.choose(self)
        if values["search"]
          @bot_search = values
          return
        end
      end
      @bot_at = tick + 35
      @bot_angle = values["angle"]
      command(team[:id], "fire", values)
    rescue RuleError
      command(team[:id], "fire", {"weapon" => "skip"}) if phase == "aiming" && @shots_left.zero?
    end
  end
end
