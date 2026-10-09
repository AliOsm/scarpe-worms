# frozen_string_literal: true

module Burrow
  # Seeded landforms, not a repeating height wave. Everything in this mask,
  # including shelves, masonry and arches, participates in destruction/collision.
  class TerrainGenerator
    def initialize(seed:, shape:, width:, height:)
      @rng, @shape, @width, @height = Random.new(seed), shape, width, height
      @cols, @rows = width / Terrain::CELL, height / Terrain::CELL
      @data = "\0".b * (@cols * @rows)
    end

    def generate
      count = [(@width / (@shape == "archipelago" ? 720 : 1200.0)).round, 2].max
      weights = Array.new(count) { @rng.rand(0.8..1.25) }
      gaps = Array.new(count - 1) { @rng.rand(@shape == "archipelago" ? 95..170 : 55..115) }
      usable = @width - 128 - gaps.sum
      left = 64.0
      weights.each_with_index do |weight, i|
        span = usable * weight / weights.sum
        landform(left, span, i)
        left += span + gaps.fetch(i, 0)
      end
      if @shape == "cavern"
        roof = [[36, 0], [@width - 36, 0]]
        (@width - 36).step(36, -70) { |x| roof << [x, @rng.rand(70..145)] }
        polygon(roof, 1)
        8.times do
          x = @rng.rand(80..@width - 80)
          polygon([[x - 32, 95], [x + 42, 95], [x + 10, @rng.rand(160..250)]], 1)
        end
      end
      @data
    end

    private

    def landform(left, span, index)
      baseline = @height * @rng.rand(0.43..0.60)
      knots = (span / 115).ceil
      heights = Array.new(knots + 1) { baseline + @rng.rand(-150..130) }
      # Broad terraces alternate with high ridges and short, steep escarpments.
      heights[knots / 2] -= @rng.rand(60..150)
      top = []
      (0..(span / 4).ceil).each do |i|
        x = [i * 4.0, span].min
        at = x / span * knots
        k = [at.floor, knots - 1].min
        t = at - k
        t = (1 - Math.cos(t * Math::PI)) / 2
        y = heights[k] * (1 - t) + heights[k + 1] * t
        # Fine contour detail varies the rim without making it unwalkable.
        y += Math.sin(x / 17.0 + index) * 2
        top << [left + x, y.clamp(240, @height - 300)]
      end
      bottom = []
      (0..knots).to_a.reverse_each do |k|
        bottom << [left + span * k / knots, @height * @rng.rand(0.86..1.03)]
      end
      polygon(top + bottom, 1)

      # Open archways and connected pockets make multiple useful vertical routes.
      cavities = [2, (span / 260).round].max
      cavities.times do |j|
        x = left + span * (j + 0.5) / cavities
        surface = top.min_by { |point| (point[0] - x).abs }[1]
        y = [surface + @rng.rand(150..235), @height - 130].min
        rx = @rng.rand(85..145)
        ry = @rng.rand(50..100)
        ellipse(x, y, rx, ry, 0)
        if j.zero? || j == cavities - 1
          side = j.zero? ? left - 8 : left + span + 8
          polygon([[side, y - 35], [x, y - ry / 2], [x, y + 45], [side, y + 55]], 0)
        end
      end

      # A raised shelf creates an overhang and a separate firing position.
      if span > 520
        x = left + span * @rng.rand(0.25..0.72)
        y = top.min_by { |point| (point[0] - x).abs }[1] - @rng.rand(115..170)
        shelf = @rng.rand(125..195)
        polygon([[x - shelf / 2, y], [x + shelf / 2, y - 8], [x + shelf / 2 + 14, y + 28],
          [x + 30, y + 88], [x - shelf / 2 + 20, y + 40]], 1)
      end

      # Seeded ruins are solid, destructible silhouettes, with doorways and ledges.
      x, ground = top[(top.length * @rng.rand(0.35..0.65)).floor]
      ruin_width, rise = @rng.rand(95..145), @rng.rand(65..145)
      polygon([[x - ruin_width / 2, ground + 38], [x - ruin_width / 2, ground - rise],
        [x + ruin_width / 2, ground - rise], [x + ruin_width / 2, ground + 38]], 3)
      ellipse(x, ground - 3, 25, 43, 0)
      4.times do |j|
        bx = x - ruin_width / 2 + j * ruin_width / 3.0
        polygon([[bx - 9, ground - rise + 3], [bx - 9, ground - rise - 18],
          [bx + 8, ground - rise - 18], [bx + 8, ground - rise + 3]], 3)
      end
    end

    def ellipse(x, y, rx, ry, material)
      phase = @rng.rand * Math::PI * 2
      polygon(Array.new(48) do |i|
        angle = i * Math::PI / 24
        rough = 1 + Math.sin(angle * 3 + phase) * 0.12 + Math.cos(angle * 5 + phase) * 0.06
        [x + Math.cos(angle) * rx * rough, y + Math.sin(angle) * ry * rough]
      end, material)
    end

    def polygon(points, material)
      points = points.map { |x, y| [x / Terrain::CELL, y / Terrain::CELL] }
      low = points.map(&:last).min.floor.clamp(0, @rows - 1)
      high = points.map(&:last).max.ceil.clamp(0, @rows - 1)
      edges = points.zip(points.rotate)
      (low..high).each do |y|
        scan = y + 0.5
        xs = edges.filter_map do |(x1, y1), (x2, y2)|
          x1 + (scan - y1) * (x2 - x1) / (y2 - y1) if (y1 <= scan && y2 > scan) || (y2 <= scan && y1 > scan)
        end.sort
        xs.each_slice(2) do |a, b|
          next unless b
          left, right = a.ceil.clamp(0, @cols), b.floor.clamp(-1, @cols - 1)
          @data[y * @cols + left, right - left + 1] = material.chr.b * (right - left + 1) if right >= left
        end
      end
    end
  end
end
