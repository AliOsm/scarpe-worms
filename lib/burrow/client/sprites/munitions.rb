# frozen_string_literal: true

module Burrow
  module Client
    module Sprites
      # Logical canvases match build_ordnance_munitions.py. Frames and dimensions
      # are retained once; the hot path creates only the existing Look value.
      MUNITION_SIZES = {
        "rocket" => [48, 28], "homing" => [48, 28], "homing-coast" => [48, 28],
        "mortar" => [34, 26], "mortar-fragment" => [18, 18], "grenade" => [30, 34],
        "cluster" => [34, 34], "cluster-fragment" => [20, 22], "sticky" => [34, 34],
        "dynamite" => [32, 40], "mega_bomb" => [42, 46], "banana" => [38, 38],
        "banana-fragment" => [22, 22], "holy_bomb" => [48, 48], "holy_bomb-choir" => [48, 48],
        "poison" => [34, 38], "airstrike" => [36, 26], "mine_strike" => [30, 28],
        "napalm" => [38, 28], "meteor" => [64, 44]
      }.transform_values(&:freeze).freeze
      MUNITION_PATHS = MUNITION_SIZES.to_h { |name, _| [name, frames("ordnance/munitions/#{name}-%d", 4).freeze] }.freeze
      MUNITION_FRAGMENTS = {"mortar" => "mortar-fragment", "cluster" => "cluster-fragment", "banana" => "banana-fragment"}.freeze
      MUNITION_DIRECTIONAL = %w[rocket homing mortar airstrike napalm meteor].freeze
      MUNITION_ANIMATED = %w[rocket homing sticky dynamite mega_bomb holy_bomb-choir poison mine_strike meteor].freeze
      MUNITION_BLASTS = {
        "rocket" => ["blast", "#f5bc73", 6, 2.5], "homing" => ["blast", "#dec6e9", 6, 2.5],
        "mortar" => ["shrapnel", "#a9baa1", 5, 1.5], "grenade" => ["blast", "#d6c18a", 6, 2.3],
        "cluster" => ["shrapnel", "#f1c889", 5, 1.8], "sticky" => ["blast", "#ddb0ce", 6, 2.5],
        "dynamite" => ["heavy", "#f9bf91", 8, 4.5], "mega_bomb" => ["heavy", "#f7c485", 9, 6],
        "banana" => ["fruit", "#ffe693", 5, 3], "holy_bomb" => ["choir", "#fff4c9", 8, 6],
        "poison" => ["toxic", "#bfd989", 3, 0], "airstrike" => ["blast", "#f1c889", 5, 2.8],
        "mine_strike" => ["shrapnel", "#bcd1c2", 5, 2.5], "napalm" => ["fire", "#ffb477", 4, 2],
        "meteor" => ["meteor", "#ffc29b", 7, 5]
      }.transform_values(&:freeze).freeze
      MUNITION_BURSTS = %w[blast shrapnel heavy fruit choir toxic fire meteor].to_h do |name|
        [name, frames("ordnance/munitions/#{name}-burst-%d", 8).freeze]
      end.freeze
      MUNITION_BOMBERS = {1 => frames("ordnance/munitions/bomber-right-%d", 4).freeze,
                         -1 => frames("ordnance/munitions/bomber-left-%d", 4).freeze}.freeze
      MUNITION_CHOIR_GLOW = frames("ordnance/munitions/choir-glow-%d", 6).freeze
      MUNITION_EMITTERS = {"dynamite" => [5, -11], "mega_bomb" => [5, -16], "poison" => [2, -12]}.freeze

      def self.munition_motor?(shot)
        age = shot["age"].to_f
        age > TICK_RATE / 2 && age <= TICK_RATE * 4.5
      end

      def self.munition_look(shot, tick)
        weapon = shot["weapon"]
        name = shot["fragment"] ? MUNITION_FRAGMENTS.fetch(weapon, weapon) : weapon
        name = "homing-coast" if weapon == "homing" && !munition_motor?(shot)
        name = "holy_bomb-choir" if weapon == "holy_bomb" && shot["stage"] == "choir"
        width, height = MUNITION_SIZES.fetch(name)
        speed = Math.hypot(shot["vx"].to_f, shot["vy"].to_f)
        rotation = if !shot["stuck"] && speed > 15
          if !shot["fragment"] && MUNITION_DIRECTIONAL.include?(weapon)
            heading(shot)
          else
            # A stable spin keeps a wall bounce from snapping the accumulated
            # angle through a sign change. About one turn every four seconds;
            # resting/attached bombs retain their last drawn orientation.
            age = shot["age"] || tick
            age * (shot["id"].to_i.odd? ? -2.6 : 2.6)
          end
        end
        frame = MUNITION_ANIMATED.include?(name) ? (tick / 3).floor % 4 : 0
        Look.new(path: MUNITION_PATHS.fetch(name)[frame], width: width, height: height,
          anchor_x: width / 2.0, anchor_y: height / 2.0, rotation: rotation)
      end

      projectile_rule(*MUNITION_BLASTS.keys) { |shot, tick| munition_look(shot, tick) }

      # Called at the scene's bounded trail cadence, replacing its generic dot.
      # No emitter arrays, RNG, state caches or node creation per display frame.
      def self.munition_trail(scene, shot, rotation: 0)
        weapon = shot["weapon"]
        return false unless MUNITION_BLASTS.key?(weapon)
        return true if shot["fragment"] || !scene.fx_motion?
        vx, vy = shot["vx"].to_f, shot["vy"].to_f
        speed = Math.hypot(vx, vy)
        x, y = shot["x"], shot["y"]
        if (offset = MUNITION_EMITTERS[weapon])
          angle = rotation.to_f * Math::PI / 180
          dx, dy = offset
          x += dx * Math.cos(angle) - dy * Math.sin(angle)
          y += dx * Math.sin(angle) + dy * Math.cos(angle)
        end
        if weapon == "poison"
          scene.fx_particle(x, y, color: "#bad48c88", life: 0.35, size: 5, vx: 3, vy: -30)
        elsif weapon == "dynamite" || weapon == "mega_bomb"
          scene.fx_particle(x, y, color: "#ffe6a5", life: 0.16, size: 2, vx: 8, vy: -40)
        elsif speed > 40 && (weapon == "rocket" || weapon == "meteor" || (weapon == "homing" && munition_motor?(shot)))
          offset = weapon == "meteor" ? 22 : 15
          scene.fx_particle(x - vx / speed * offset, y - vy / speed * offset,
            color: weapon == "meteor" ? "#f5a86fc0" : "#d9d6ba99", life: 0.38,
            size: weapon == "meteor" ? 9 : 8, vx: -vx * 0.03, vy: -18)
          if weapon == "rocket" && speed > 260
            scene.fx_line(x - vx / speed * 34, y - vy / speed * 34,
              x - vx / speed * 8, y - vy / speed * 8, color: "#e6dfc38c", width: 2, life: 0.12)
          end
        end
        true
      end

      effect_rule("explosion") do |scene, event, _now|
        spec = MUNITION_BLASTS[event["style"]]
        next false unless spec
        burst, color, count, shake = spec
        x, y = event.values_at("x", "y")
        radius = event.fetch("radius", 45).to_f
        size = (radius * 2.8).clamp(48, 340)
        scene.fx_frames(MUNITION_BURSTS.fetch(burst), x, y, size, size, fps: burst == "choir" ? 12 : 16)
        if scene.fx_motion?
          scene.fx_sprite("smoke", x, y - radius * 0.15, (radius / 65).clamp(0.4, 1.5)) if burst == "heavy" || burst == "meteor"
          count.times do |i|
            angle = i * Math::PI * 2 / count + 0.2
            speed = 55 + i % 3 * 35
            scene.fx_particle(x, y, color: i.even? ? color : "#fff1c5", life: 0.28 + i % 3 * 0.1,
              size: 3 + i % 3, vx: Math.cos(angle) * speed, vy: Math.sin(angle) * speed - 45)
          end
          scene.fx_shake(shake * (radius / 50).clamp(0.5, 1.2), duration: 0.3) if shake > 0
        else
          # A brief static marker retains impact feedback in reduced motion.
          scene.fx_particle(x - 5, y - 5, color: color, life: 0.12, size: 10)
        end
        true
      end

      effect_rule("choir") do |scene, event, _now|
        scene.fx_frames(MUNITION_CHOIR_GLOW, event["x"], event["y"], 96, 96, fps: 10)
        true
      end

      effect_rule("strike") do |scene, event, _now|
        next false unless %w[airstrike mine_strike napalm].include?(event["weapon"])
        direction = event.fetch("side", event.fetch("direction", 1)).to_i < 0 ? -1 : 1
        scene.fx_strike(MUNITION_BOMBERS.fetch(direction), event)
        true
      end

      effect_rule("quake") do |scene, event, _now|
        scene.fx_shake(8, duration: 0.8)
        points = event["points"] || [[event["x"], event["y"]]]
        points.first(12).each do |point|
          x, y = point
          scene.fx_sprite("dust", x, y, 1.2)
          scene.fx_particle(x - 3, y - 3, color: "#d5c29e", life: 0.32, size: 5,
            vx: scene.fx_motion? ? 15 : 0, vy: scene.fx_motion? ? -65 : 0)
        end
        true
      end

      effect_rule("gas") do |scene, event, _now|
        next false unless event["weapon"] == "poison"
        size = (event.fetch("radius", 40) * 2.5).clamp(60, 200)
        scene.fx_frames(MUNITION_BURSTS.fetch("toxic"), event["x"], event["y"], size, size, fps: 12)
        true
      end
    end
  end
end
