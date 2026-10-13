# frozen_string_literal: true

# How grubs take a hit and say goodbye: dizzy stars, a nervous sweat, the pop,
# the ghost, drowning bubbles and comic impact bursts. Art comes from
# tools/build_ordnance_reactions.py; words are drawn by the game, never baked in.
module Burrow
  module Client
    module Sprites
      # width, height, anchor x, anchor y (logical px), frames, fps
      REACTION_SIZES = {
        "poof" => [96, 96, 48, 64, 7, 16], "ghost" => [48, 56, 24, 40, 6, 10],
        "bubbles" => [32, 48, 16, 44, 6, 10], "dizzy" => [56, 24, 28, 12, 6, 12],
        "sweat" => [16, 20, 8, 10, 3, 8],
        "burst-pow" => [128, 80, 64, 40, 4, 16], "burst-boom" => [176, 112, 88, 56, 4, 16],
        "burst-splash" => [128, 80, 64, 40, 4, 16], "burst-spirit" => [128, 80, 64, 40, 4, 16]
      }.transform_values(&:freeze).freeze
      REACTION_FRAMES = REACTION_SIZES.to_h do |name, spec|
        [name, frames("ordnance/reactions/#{name}-%d", spec[4]).freeze]
      end.freeze
      # A burst pops in, overshoots, then wobbles while its word is read.
      BURST_SEQUENCE = [0, 1, 2, 2, 3, 3, 2, 2, 3, 3, 2, 2, 3, 3].freeze
      BURST_PATHS = %w[pow boom splash spirit].to_h do |style|
        [style, BURST_SEQUENCE.map { |frame| REACTION_FRAMES.fetch("burst-#{style}")[frame] }.freeze]
      end.freeze
      BURST_SECONDS = BURST_SEQUENCE.length.fdiv(16)
      # Stars circle just above the head, a little forward; sweat runs down behind it.
      DIZZY_LOOKS = [1, -1].to_h do |facing|
        [facing, REACTION_FRAMES.fetch("dizzy").map do |path|
          Look.new(path: path, width: 56, height: 24, anchor_x: 28 - 4 * facing, anchor_y: 60).freeze
        end.freeze]
      end.freeze
      SWEAT_LOOKS = [1, -1].to_h do |facing|
        [facing, REACTION_FRAMES.fetch("sweat").map do |path|
          Look.new(path: path, width: 16, height: 20, anchor_x: 8 + 12 * facing, anchor_y: 50).freeze
        end.freeze]
      end.freeze
      MELEE_WORDS = {"fire_punch" => "POW!", "dragon_punch" => "WHAM!", "bat" => "BONK!",
        "axe" => "WHACK!", "prod" => "BOOP!"}.freeze

      overlay_rule(:dizzy) do |worm, tick|
        DIZZY_LOOKS.fetch(worm.fetch("facing", 1).negative? ? -1 : 1)[(tick / 2.5).floor % 6] if worm["_dizzy"]
      end

      overlay_rule(:sweat) do |worm, tick|
        if worm["hp"].to_i.between?(1, 20) && !worm["_dizzy"]
          SWEAT_LOOKS.fetch(worm.fetch("facing", 1).negative? ? -1 : 1)[(tick / 3.75).floor % 3]
        end
      end

      class << self
        def reaction(scene, name, x, y, **motion)
          width, height, ax, ay, _, fps = REACTION_SIZES.fetch(name)
          scene.fx_frames(REACTION_FRAMES.fetch(name), x, y, width, height, fps: fps, anchor_x: ax, anchor_y: ay, **motion)
        end

        # A comic burst behind a word, e.g. burst(scene, "pow", "BONK!", x, y).
        def burst(scene, style, word, x, y, colors:)
          width, height, ax, ay = REACTION_SIZES.fetch("burst-#{style}")
          return unless scene.fx_frames(BURST_PATHS.fetch(style), x, y, width, height, fps: 16, anchor_x: ax, anchor_y: ay)
          scene.fx_caption(word, x, y, life: BURST_SECONDS, size: style == "boom" ? 22 : 18, colors: colors)
          true
        end
      end
    end
  end
end
