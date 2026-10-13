# frozen_string_literal: true

# Close-family artwork is deliberately small and pre-indexed: an idle grub adds
# no image nodes, and gun bursts share Scene's bounded 100-effect pool.
module Burrow
  module Client
    module Sprites
      CLOSE_SIZES = {
        "shield" => [76, 76, 38, 65, 4], "frozen" => [64, 72, 32, 64, 2],
        "poison" => [64, 72, 32, 62, 4], "boost" => [76, 84, 38, 72, 4],
        "moon" => [72, 76, 36, 64, 4], "drill" => [80, 84, 40, 68, 2],
        "torch" => [96, 80, 40, 68, 2], "muzzle" => [48, 40, 24, 20, 3],
        "laser-muzzle" => [48, 48, 24, 24, 3], "impact" => [40, 40, 20, 20, 4],
        "jet" => [64, 40, 32, 20, 4], "fire_punch" => [112, 112, 56, 72, 4],
        "dragon_punch" => [112, 80, 56, 52, 4], "prod" => [112, 80, 56, 52, 4],
        "bat" => [112, 112, 56, 68, 4], "axe" => [112, 112, 56, 68, 4],
        "heal" => [72, 80, 36, 60, 5], "wind" => [112, 64, 56, 32, 4],
        "placement" => [72, 32, 36, 22, 4]
      }.transform_values(&:freeze).freeze
      CLOSE_MIRRORED = %w[drill torch fire_punch dragon_punch prod bat axe].freeze
      CLOSE_FRAMES = CLOSE_SIZES.each_with_object({}) do |(name, (_, _, _, _, count)), paths|
        paths[name] = frames("ordnance/status/#{name}-%d", count).freeze
        paths["#{name}-left"] = frames("ordnance/status/#{name}-left-%d", count).freeze if CLOSE_MIRRORED.include?(name)
      end.freeze
      CLOSE_LOOKS = CLOSE_SIZES.each_with_object({}) do |(name, (w, h, ax, ay, _)), looks|
        [name, *(CLOSE_MIRRORED.include?(name) ? ["#{name}-left"] : [])].each do |key|
          looks[key] = CLOSE_FRAMES.fetch(key).map do |path|
            Look.new(path: path, width: w, height: h, anchor_x: key.end_with?("-left") ? w - ax : ax, anchor_y: ay).freeze
          end.freeze
        end
      end.freeze
      CLOSE_PROPS = begin
        props = {}
        %w[safe armed lit].each do |state|
          props["mine-#{state}"] = Look.new(path: art("ordnance/status/mine-#{state}"), width: 36, height: 32, anchor_x: 18, anchor_y: 28).freeze
        end
        %w[whole cracked].each do |state|
          props["barrel-#{state}"] = Look.new(path: art("ordnance/status/barrel-#{state}"), width: 44, height: 52, anchor_x: 22, anchor_y: 47).freeze
        end
        %w[left right].each do |direction|
          [-45, 0, 45, "empty"].each do |angle|
            key = "turret-#{direction}-#{angle}"
            props[key] = Look.new(path: art("ordnance/status/#{key}"), width: 48, height: 48, anchor_x: 24, anchor_y: 42).freeze
          end
        end
        props.freeze
      end

      class << self
        def close_hazard(hazard, tick, motion: true)
          key = case hazard["kind"]
          when "mine"
            state = if tick < hazard.fetch("armed", 0)
              "safe"
            elsif hazard["trigger"] || (motion && (tick / 12).floor.odd?)
              "lit"
            else
              "armed"
            end
            "mine-#{state}"
          when "barrel" then "barrel-#{hazard['trigger'] || hazard.fetch('hp', 20) < 12 ? 'cracked' : 'whole'}"
          when "turret"
            angle = hazard.fetch("angle", hazard.fetch("aim_angle", hazard.fetch("facing", 1).negative? ? Math::PI : 0))
            left = Math.cos(angle).negative?
            pitch = left ? Math.atan2(Math.sin(angle), -Math.cos(angle)) : angle
            pitch = (pitch * 180 / Math::PI / 45).round.clamp(-1, 1) * 45
            "turret-#{left ? 'left' : 'right'}-#{hazard.fetch('shots', 5).zero? ? 'empty' : pitch}"
          end
          CLOSE_PROPS[key]
        end

        def close_frames(scene, name, x, y, fps: 18, rotation: nil, scale: 1)
          base_name = name.end_with?("-left") ? name.delete_suffix("-left") : name
          width, height, ax, ay = CLOSE_SIZES.fetch(base_name)
          anchor_x = name.end_with?("-left") ? (width - ax) * scale : ax * scale
          scene.fx_frames(CLOSE_FRAMES.fetch(name), x, y, width * scale, height * scale,
            fps: fps, anchor_x: anchor_x, anchor_y: ay * scale, rotation: rotation)
        end

        def close_impact(scene, x, y, material)
          close_frames(scene, "impact", x, y, fps: 24, scale: material == "worm" ? 0.7 : 0.9)
          return unless material == "terrain"
          3.times do |i|
            scene.fx_particle(x, y, color: i.even? ? "#b08050" : "#edc16d", life: 0.25,
              size: 2 + i, vx: (i - 1) * 48, vy: -45 - i * 18)
          end
        end
      end

      {"shield" => "shield", "frozen" => "frozen", "poisoned" => "poison",
        "_close_boost" => "boost", "_close_moon" => "moon"}.each do |field, art_name|
        overlay_rule("close_#{field}") do |worm, tick|
          if worm[field]
            looks = CLOSE_LOOKS.fetch(art_name)
            looks[(tick / 6).floor % looks.length]
          end
        end
      end
      overlay_rule("close_tool") do |worm, tick|
        tool = worm["_close_tool"]
        if tool && %w[drill torch].include?(tool["kind"])
          left = tool.fetch("direction", worm.fetch("facing", 1)).negative?
          name = "#{tool['kind']}#{left ? '-left' : ''}"
          look = CLOSE_LOOKS.fetch(name)[(tick / 3).floor % 2]
          lift = tool["kind"] == "torch" && tick <= tool.fetch("input_until", 0) ? tool.fetch("lift", 0) : 0
          lift.zero? ? look : Look.new(**look.to_h, rotation: (left ? 1 : -1) * lift * 22)
        end
      end
      overlay_rule("close_melee") do |worm, tick|
        pose = worm["_close_pose"]
        if pose && tick - pose[:tick] < 12
          name = "#{pose[:style]}#{pose[:facing].negative? ? '-left' : ''}"
          look = CLOSE_LOOKS.fetch(name)[((tick - pose[:tick]) / 3).floor.clamp(0, 3)]
          angle = if %w[bat axe prod].include?(pose[:style])
            pose[:angle] * 180 / Math::PI - (pose[:facing].negative? ? 180 : 0)
          else
            0
          end
          angle.zero? ? look : Look.new(**look.to_h, rotation: angle)
        end
      end

      effect_rule("beam") do |scene, event, _now|
        x, y, x2, y2 = event.values_at("x", "y", "x2", "y2")
        style = event["style"]
        angle = Math.atan2(y2 - y, x2 - x) * 180 / Math::PI
        if style == "flame"
          length = Math.hypot(x2 - x, y2 - y)
          count = (length / 40).ceil.clamp(1, 4)
          count.times do |i|
            t = (i + 0.5) / count
            scale = [length / count / 52, 1.0].min
            close_frames(scene, "jet", x + (x2 - x) * t, y + (y2 - y) * t, fps: 24, rotation: angle, scale: scale)
          end
        else
          close_frames(scene, style == "laser" ? "laser-muzzle" : "muzzle", x, y, fps: 24, rotation: angle,
            scale: style == "shotgun" ? 1.0 : 0.7)
          rays = event["rays"] || [{"x2" => x2, "y2" => y2}]
          rays.first(5).each do |ray|
            ex, ey = ray.values_at("x2", "y2")
            if style == "laser"
              scene.fx_line(x, y, ex, ey, color: "#ff685a88", width: 10, life: 0.24)
              scene.fx_line(x, y, ex, ey, color: "#ffb087", width: 5, life: 0.19)
              scene.fx_line(x, y, ex, ey, color: "#fff6de", width: 2, life: 0.14)
            else
              color = style == "shotgun" ? "#f8daacbb" : style == "turret" ? "#afffea" : "#fff6c9"
              scene.fx_line(x, y, ex, ey, color: color, width: style == "beam" ? 2.8 : 1.6, life: style == "beam" ? 0.22 : 0.13)
            end
          end
        end
        impacts = event["impacts"] || [{"x" => x2, "y" => y2}]
        impacts.first(style == "flame" ? 1 : 8).each { |hit| close_impact(scene, hit["x"], hit["y"], hit["material"]) }
        true
      end

      effect_rule("melee") do |scene, event, _now|
        if CLOSE_MIRRORED.include?(event["style"])
          style = event["style"]
          facing = event.fetch("facing", 1)
          key = facing.negative? ? "#{style}-left" : style
          x, y = event.values_at("x", "y")
          angle = event.fetch("angle", facing.negative? ? Math::PI : 0).to_f * 180 / Math::PI
          # Current reports attach the animation to the moving grub.  Only old
          # reports without a worm ID need the fixed-position fallback.
          unless event["worm"]
            close_frames(scene, key, x, y, fps: 18,
              rotation: %w[bat axe prod].include?(style) ? angle - (facing.negative? ? 180 : 0) : nil)
          end
          if event["style"] == "dragon_punch"
            scene.fx_particle(event["x"] - event.fetch("facing", 1) * 22, event["y"],
              color: "#ff975e", life: 0.25, size: 9, vx: -event.fetch("facing", 1) * 40, vy: -12)
          end
          Array(event["impacts"]).first(4).each { |hit| close_impact(scene, hit["x"], hit["y"], "worm") }
          Array(event["hits"]).first(4).each do |id|
            position = scene.positions[id]
            close_impact(scene, position[0], position[1] - 12, "worm") if position
          end
          true
        end
      end

      effect_rule("dig") do |scene, event, _now|
        if %w[drill torch].include?(event["style"])
          x, y = event.values_at("x", "y")
          if event["style"] == "torch"
            rotation = event.fetch("angle", event.fetch("facing", 1).negative? ? Math::PI : 0) * 180 / Math::PI
            close_frames(scene, "jet", x, y, fps: 24, rotation: rotation, scale: 0.65)
            close_frames(scene, "impact", x, y, fps: 24, scale: 0.65)
          else
            scene.fx_sprite("dust", x, y, 0.5)
          end
          3.times do |i|
            scene.fx_particle(x, y, color: i.even? ? "#bf9160" : "#ffe0a0", life: 0.28,
              size: 2 + i, vx: (i - 1) * 75, vy: -80 - i * 15)
          end
          true
        end
      end

      effect_rule("heal") do |scene, event, _now|
        close_frames(scene, "heal", event["x"], event["y"] + 20, fps: 10)
        false # Keep the authoritative +health number.
      end
      effect_rule("wind") do |scene, event, _now|
        if event["x"] && event["y"]
          close_frames(scene, "wind", event["x"], event["y"] - 30, fps: 10,
            rotation: event.fetch("wind", 1).negative? ? 180 : 0)
        end
        true
      end
      effect_rule("hazard_place", "mine_arm", "mine_trigger", "hazard_trigger", "barrel_rupture") do |scene, event, _now|
        if event["x"] && event["y"]
          if %w[hazard_trigger barrel_rupture].include?(event["kind"])
            close_frames(scene, "impact", event["x"], event["y"] - 12, fps: 18)
          else
            close_frames(scene, "placement", event["x"], event["y"], fps: 14)
          end
        end
        true
      end
    end
  end
end
