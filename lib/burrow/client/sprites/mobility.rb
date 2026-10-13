# frozen_string_literal: true

module Burrow
  module Client
    module Sprites
      # Equipment follows the grub's feet. Frame paths and Looks are retained:
      # idle packs incur no image changes; flames run only under host thrust.
      MOBILITY_PACKS = %w[left right].to_h do |side|
        looks = ["idle", 0, 1, 2, 3].map do |frame|
          Look.new(path: art("ordnance/mobility/jetpack-#{side}-#{frame}"),
            width: 64, height: 80, anchor_x: 32, anchor_y: 54.4).freeze
        end
        [side, looks.freeze]
      end.freeze
      MOBILITY_CANOPIES = Array.new(7) do |frame|
        Look.new(path: art("ordnance/mobility/parachute-#{frame}"),
          width: 112, height: 112, anchor_x: 56, anchor_y: 105).freeze
      end.freeze
      MOBILITY_TELEPORT_OUT = frames("ordnance/mobility/teleport-out-%d", 8).freeze
      MOBILITY_TELEPORT_IN = frames("ordnance/mobility/teleport-in-%d", 8).freeze

      overlay_rule(:mobility_pack) do |worm, tick|
        if worm["jetpack"] && worm["fuel"].to_i > 0
          side = worm.fetch("facing", 1) < 0 ? "left" : "right"
          frame = worm["thrusting"] ? (tick / 2).floor % 4 + 1 : 0
          MOBILITY_PACKS.fetch(side)[frame]
        end
      end

      overlay_rule(:mobility_canopy) do |worm, tick|
        open = worm.fetch("parachute_open") { worm["parachute"] && worm["vy"].to_f > 0 }
        if open && !worm["jetpack"] && !worm["rope"]
          sway = Math.sin(tick * 0.11) * 0.65 - worm["vx"].to_f / 85
          MOBILITY_CANOPIES[(3 + sway * 2).round.clamp(0, 6)]
        end
      end

      effect_rule("teleport") do |scene, event, _now|
        x, y, x2, y2 = event.values_at("x", "y", "x2", "y2")
        scene.fx_frames(MOBILITY_TELEPORT_OUT, x, y, 96, 112, fps: 16, anchor_x: 48, anchor_y: 87)
        scene.fx_frames(MOBILITY_TELEPORT_IN, x2, y2, 96, 112, fps: 16, anchor_x: 48, anchor_y: 87) if x2 && y2
        # The brief ground flash remains useful when decorative motion is off.
        [[x, y], [x2, y2]].each do |tx, ty|
          next unless tx && ty
          scene.fx_line(tx - 18, ty - 1, tx + 18, ty - 1, color: "#182d35", width: 5, life: 0.24)
          scene.fx_line(tx - 16, ty - 1, tx + 16, ty - 1, color: "#a9f2df", width: 2, life: 0.24)
        end
        true
      end
    end
  end
end
