# frozen_string_literal: true

# Original in-world cast; all paths are cached once, never built in a frame.
module Burrow
  module Client
    module Sprites
      CRITTER_META = JSON.parse(File.read(File.join(Theme::ART, "manifest.json"), encoding: Encoding::UTF_8)).fetch("ordnance").fetch("critters").freeze
      CRITTER_FRAMES = CRITTER_META.fetch("sprites").to_h do |weapon, poses|
        [weapon, ["", "left/"].map do |direction|
          poses.to_h { |pose, count| [pose, frames("ordnance/critters/#{direction}#{weapon}-#{pose}-%d", count).freeze] }.freeze
        end.freeze]
      end.freeze

      projectile_rule(*CRITTER_FRAMES.keys) do |shot, tick|
        weapon, stage = shot.values_at("weapon", "stage")
        left = shot["vx"] < 0
        poses = CRITTER_FRAMES.fetch(weapon)[left ? 1 : 0]
        airborne = !shot["walker"] || shot["vy"].abs > 18
        pose = if stage == "flying"
          "flying"
        elsif stage == "digging"
          "dig"
        elsif stage == "diving"
          shot["vy"] < 0 ? "hop" : "dive"
        elsif stage == "falling" || (airborne && shot["vy"] >= 0)
          "fall"
        elsif airborne
          "hop"
        elsif stage == "spraying"
          "spray"
        else
          "walk"
        end
        paths = poses.fetch(pose)
        fps = %w[walk spray].include?(pose) ? 10 : 8
        frame = (tick * fps / TICK_RATE).floor % paths.length
        # Source art always faces right or left with its feet below its body.
        # Rotate left-facing flight about the opposite heading so it never
        # turns upside down. Timeline already interpolates velocity at 60 Hz.
        rotation = 0.0
        if %w[flying digging].include?(stage)
          rotation = heading(shot)
          rotation += rotation < 0 ? 180 : -180 if left
        end
        Look.new(path: paths[frame], width: 64, height: 64, anchor_x: 32,
          anchor_y: stage == "flying" || stage == "digging" ? 32 : 44, rotation: rotation)
      end

      effect_rule("critter_trail") do |scene, event, _now|
        if scene.fx_motion?
          x, y = event.values_at("x", "y")
          scene.fx_particle(x - event["vx"] * 0.035, y - event["vy"] * 0.035,
            color: "#fff9e4dd", life: 0.38, size: 5, vx: -event["vx"] * 0.08, vy: -35)
          scene.fx_sprite("sparkle", x, y, 0.35) if event["tick"] % 8 == 0
        end
        true
      end

      effect_rule("critter_dirt", "critter_dive") do |scene, event, _now|
        if scene.fx_motion?
          x, y = event.values_at("x", "y")
          [-1, 1].each do |side|
            scene.fx_particle(x + side * 4, y - 3, color: side < 0 ? "#c29367" : "#79503a",
              life: 0.42, size: 4, vx: side * 30 - event.fetch("vx", 0) * 0.3, vy: -50)
          end
          scene.fx_sprite("dust", x, y, 0.5) if event["kind"] == "critter_dive" || event["tick"] % 10 == 0
        end
        true
      end

      effect_rule("gas") do |scene, event, _now|
        next false unless event["weapon"] == "skunk"
        if scene.fx_motion?
          x, y = event.values_at("x", "y")
          [-1, 0, 1].each do |side|
            scene.fx_particle(x + side * 12 - 8, y - 12, color: side.zero? ? "#d9efa2bb" : "#92c96199",
              life: 0.65, size: side.zero? ? 22 : 16, vx: side * 12, vy: -75)
          end
        end
        true
      end

      effect_rule("critter_release", "critter_fall") do |scene, event, _now|
        scene.fx_sprite("dust", event["x"], event["y"] + 6, 0.45)
        true
      end

      effect_rule("activate") do |scene, event, _now|
        next false unless CRITTER_FRAMES.key?(event["weapon"])
        scene.fx_sprite("sparkle", event["x"], event["y"], 0.65) if event["stage"] == "flying"
        false # Keep the standard launch dust as well.
      end

      effect_rule("explosion") do |scene, event, _now|
        if %w[sheep super_sheep].include?(event["style"]) && scene.fx_motion?
          6.times do |i|
            angle = i * Math::PI / 3
            scene.fx_particle(event["x"], event["y"], color: "#fff7df", life: 0.65, size: 7,
              vx: Math.cos(angle) * 100, vy: Math.sin(angle) * 100 - 60)
          end
        end
        false # Preserve the authoritative blast's normal fireball and ring.
      end
    end
  end
end
