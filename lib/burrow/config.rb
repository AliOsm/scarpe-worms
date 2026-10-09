# frozen_string_literal: true

module Burrow
  class Config
    DEFAULT = {
      "seed" => "little-havoc", "biome" => "meadow", "terrain" => "islands", "scheme" => "full", "map_size" => "auto",
      "worms" => 3, "health" => 100, "turn_seconds" => 45, "retreat_seconds" => 4,
      "round_limit" => 12, "gravity" => 1.0, "wind" => 1.0, "damage" => 1.0,
      "fall_damage" => true, "friendly_fire" => true, "crates" => true,
      "mines" => 4, "barrels" => 3, "water_rise" => 12, "ammo" => {}
    }.freeze
    RANGES = {"worms" => 1..6, "health" => 50..200, "turn_seconds" => 15..90,
      "retreat_seconds" => 0..10, "round_limit" => 3..30, "mines" => 0..12,
      "barrels" => 0..12, "water_rise" => 0..40, "gravity" => 0.4..1.6,
      "wind" => 0.0..2.0, "damage" => 0.5..2.0}.freeze
    CHOICES = {"biome" => %w[meadow desert glacier volcano],
      "terrain" => %w[islands archipelago cavern], "scheme" => %w[full classic sandbox],
      "map_size" => %w[auto standard large huge]}.freeze
    attr_reader :values

    def initialize(input = {})
      raise RuleError, "Rules must be an object." unless input.is_a?(Hash)
      raise RuleError, "Unknown match option." unless (input.keys - DEFAULT.keys).empty?
      @values = DEFAULT.merge(input)
      CHOICES.each { |key, choices| raise RuleError, "Invalid #{key}." unless choices.include?(@values[key]) }
      RANGES.each do |key, range|
        value = @values[key]
        valid = value.is_a?(Numeric) && value.finite? && range.cover?(value)
        valid &&= value.is_a?(Integer) unless %w[gravity wind damage].include?(key)
        raise RuleError, "#{key.tr('_', ' ')} must be in #{range}." unless valid
      end
      %w[fall_damage friendly_fire crates].each do |key|
        raise RuleError, "Invalid #{key}." unless [true, false].include?(@values[key])
      end
      seed = @values["seed"]
      raise RuleError, "Map seed must be 1–40 characters." unless seed.is_a?(String) && seed.length.between?(1, 40) && seed.valid_encoding? && !seed.match?(/[[:cntrl:]]/)
      ammo = @values["ammo"]
      unless ammo.is_a?(Hash) && ammo.all? { |id, n| Catalog::WEAPONS.key?(id) && n.is_a?(Integer) && n.between?(-1, 99) }
        raise RuleError, "Ammo must be −1 (unlimited) or 0–99 for a known weapon."
      end
      @values["ammo"] = ammo.dup.freeze
      @values.freeze
    end

    def [](key) = values.fetch(key.to_s)
    def to_h = values.dup
    def seed_number = Digest::SHA256.hexdigest(self["seed"])[0, 16].to_i(16)

    def world_size(players = 2)
      size = self["map_size"]
      if size == "auto"
        count = players * self["worms"]
        size = players >= 5 || count > 24 ? "huge" : players >= 3 || count > 12 ? "large" : "standard"
      end
      {"standard" => [2880, 1280], "large" => [3840, 1440], "huge" => [4800, 1600]}.fetch(size)
    end
  end
end
