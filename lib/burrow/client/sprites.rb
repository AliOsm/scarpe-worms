# frozen_string_literal: true

module Burrow
  module Client
    # How weapons look in play. Each weapon family registers its rules in
    # client/sprites/<family>.rb, with art from tools/build_ordnance_<family>.py
    # under assets/art/ordnance/<family>/, so families evolve independently.
    #
    # - projectile(weapon) { |shot, tick| Look }   in-flight objects and critters
    # - overlay(name) { |worm, tick| Look or nil } pictures attached to a grub
    # - effect(kind) { |scene, event, now| true }   extra effects for host events;
    #   return true to replace the scene's default effect for that event.
    module Sprites
      # Anchor is the point placed on the object's world position, in logical
      # pixels from the picture's top-left. Rotation turns about the centre.
      Look = Struct.new(:path, :width, :height, :anchor_x, :anchor_y, :rotation, keyword_init: true)
      COMBAT = JSON.parse(File.read(File.join(Theme::ART, "manifest.json"), encoding: Encoding::UTF_8)).fetch("combat").freeze
      @projectiles, @overlays, @effects, @paths = {}, {}, {}, {}

      class << self
        def projectile_rule(*weapons, &rule) = weapons.each { |weapon| @projectiles[weapon] = rule }
        def overlay_rule(name, &rule) = @overlays[name] = rule
        def effect_rule(*kinds, &rule) = kinds.each { |kind| (@effects[kind] ||= []) << rule }

        # A frozen absolute path for an art name like "ordnance/critters/sheep-walk-0".
        def art(name) = @paths[name] ||= File.join(Theme::ART, "#{name}.png").freeze

        def projectile(shot, tick)
          (rule = @projectiles[shot["weapon"]]) && rule.call(shot, tick) || default_projectile(shot, tick)
        end

        def overlays(worm, tick) = @overlays.values.filter_map { |rule| rule.call(worm, tick) }

        def effect(scene, event, now)
          (@effects[event["kind"]] || []).any? { |rule| rule.call(scene, event, now) }
        end

        # Rockets with directional art point along their flight; other objects
        # tumble once they move quickly. Walkers keep still.
        def default_projectile(shot, tick)
          directional = COMBAT["projectiles"].include?(shot["weapon"])
          rotation = nil
          if !shot["walker"] && Math.hypot(shot["vx"], shot["vy"]) > 25
            rotation = directional ? heading(shot) : tick * 7
          end
          Look.new(path: art("#{directional ? 'projectiles' : 'weapons'}/#{shot['weapon']}"),
            width: 28, height: 28, anchor_x: 14, anchor_y: 14, rotation: rotation)
        end

        def heading(shot) = Math.atan2(shot["vy"], shot["vx"]) * 180 / Math::PI

        # Every animation frame name for a pattern, for cache warming.
        def frames(pattern, count) = Array.new(count) { |i| art(format(pattern, i)) }
      end
    end
  end
end

Dir[File.join(__dir__, "sprites", "*.rb")].sort.each { |family| require family }
