# frozen_string_literal: true

module Burrow
  # Shared geometry for authoritative placement and its client preview. The
  # client supplies the worker's collision mask; only the host places anything.
  module Placement
    module_function

    def teleport(terrain, x, y, water:, worms:, active_id:)
      landing = terrain.landing(x, y, water: water)
      return {valid: false, message: "Choose clear ground above the water."} unless landing
      occupied = worms.any? do |worm|
        value(worm, :id) != active_id && value(worm, :hp) > 0 &&
          Math.hypot(value(worm, :x) - x, value(worm, :y) - landing) < 25
      end
      return {valid: false, message: "Choose ground away from another grub."} if occupied
      {valid: true, y: landing, message: "Clear landing"}
    end

    def girder(terrain, x, y, water:, worms:, rotation: 0)
      unless x.between?(80, terrain.width - 80) && y.between?(100, water - 30)
        return {valid: false, message: "Build above water and inside the battlefield."}
      end
      ux, uy = Math.cos(rotation * Math::PI / 180), Math.sin(rotation * Math::PI / 180)
      # Cell-sized samples across the entire beam catch thin terrain and girders.
      points = (-70..70).step(Terrain::CELL).map { |d| [x + ux * d, y + 6 + uy * d] }
      blocked = points.any? do |px, py|
        !py.between?(60, water - 20) || (-6..6).step(Terrain::CELL).any? { |o| terrain.solid?(px - uy * o, py + ux * o) }
      end
      return {valid: false, message: "The beam needs clear space above water."} if blocked
      occupied = worms.any? do |worm|
        value(worm, :hp) > 0 && points.any? { |px, py| (value(worm, :x) - px).abs < 13 && (value(worm, :y) - 10 - py).abs < 21 }
      end
      return {valid: false, message: "Move the beam away from grubs."} if occupied
      {valid: true, message: "Clear placement"}
    end

    def value(worm, key) = worm.key?(key) ? worm[key] : worm[key.to_s]
    private_class_method :value
  end
end
