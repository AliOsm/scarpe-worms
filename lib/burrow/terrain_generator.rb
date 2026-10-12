# frozen_string_literal: true

module Burrow
  # Seeded landforms. Islands are built from layered value noise: a broad character
  # (rolling hills, a summit, a valley, stepped mesas or a volcanic cone) shaped by
  # shoulders that run down into the sea as beaches, cliffs or undercut overhangs.
  # Caves with walkable floors, winding tunnels, floating rocks and biome set pieces
  # (towers, colonnades, henges, ziggurats, igloos, basalt columns, aqueducts and
  # girders) are drawn into the same mask, so everything visible is destructible.
  class TerrainGenerator
    TAU = Math::PI * 2
    AIR, SOIL, GIRDER, MASONRY = 0, 1, 2, 3
    CHARACTERS = {
      "meadow" => %i[hills hills summit valley mesa],
      "desert" => %i[mesa mesa hills valley summit],
      "glacier" => %i[summit summit hills valley mesa],
      "volcano" => %i[cone summit hills valley mesa]
    }.freeze
    PIECES = {
      "meadow" => %i[tower colonnade henge wall arch],
      "desert" => %i[ziggurat obelisk colonnade arch tower],
      "glacier" => %i[igloo spires tower wall arch],
      "volcano" => %i[basalt spires tower arch wall]
    }.freeze

    def initialize(seed:, shape:, width:, height:, biome: "meadow")
      @rng, @shape, @width, @height = Random.new(seed), shape, width, height
      @biome = CHARACTERS.key?(biome) ? biome : "meadow"
      @cols, @rows = width / Terrain::CELL, height / Terrain::CELL
      @data = "\0".b * (@cols * @rows)
      @water = height - 96
      @top = Array.new(@cols) # island surface per column (world y), before carving
      @occupied = []
    end

    def generate
      @ceiling = ceiling if cavern?
      islands = layout
      islands.each { |island| landform(island) }
      islands.each { |island| caves(island) }
      pillars(islands) if cavern?
      islands.each { |island| set_pieces(island) }
      remove_specks(700) # before the deliberately small girders and rocks
      bridges(islands)
      floating_rocks(islands)
      girders(islands)
      @data
    end

    private

    def cavern? = @shape == "cavern"
    def archipelago? = @shape == "archipelago"

    # ---- Layout -----------------------------------------------------------------

    def layout
      count = [(@width / (archipelago? ? 760.0 : 1180.0)).round, 2].max
      weights = Array.new(count) { @rng.rand(0.75..1.3) }
      gaps = Array.new(count - 1) { archipelago? ? @rng.rand(120..210) : @rng.rand(60..130) }
      margin = [@rng.rand(36..80), @rng.rand(36..80)]
      usable = @width - margin.sum - gaps.sum
      left = margin[0].to_f
      characters = CHARACTERS.fetch(@biome)
      weights.each_with_index.map do |weight, i|
        span = usable * weight / weights.sum
        island = {left: left, right: left + span, character: characters[@rng.rand(characters.length)], index: i}
        left += span + gaps.fetch(i, 0)
        island
      end
    end

    # Smooth 1-D value noise: eased random knots every `spacing` world pixels.
    def wave(length, spacing, amplitude)
      count = (length / spacing).ceil + 3
      knots = Array.new(count) { @rng.rand * 2 - 1 }
      lambda do |x|
        at = x / spacing
        k = at.floor.clamp(0, count - 2)
        t = (at - k).clamp(0.0, 1.0)
        t = t * t * (3 - 2 * t)
        (knots[k] * (1 - t) + knots[k + 1] * t) * amplitude
      end
    end

    def smoothstep(t)
      t = t.clamp(0.0, 1.0)
      t * t * (3 - 2 * t)
    end

    # ---- Islands ----------------------------------------------------------------

    def landform(island)
      left, right = island[:left], island[:right]
      span = right - left
      high = cavern? ? @height * 0.34 : @height * 0.2
      # Cavern floors stay within grapple reach (460 px) of the roof.
      base = cavern? ? @ceiling_mean + @rng.rand(320.0..400.0) : archipelago? ? @height * @rng.rand(0.46..0.62) : @height * @rng.rand(0.40..0.58)
      broad = wave(span, @rng.rand(220.0..330.0), cavern? || archipelago? ? @rng.rand(60.0..100.0) : @rng.rand(80.0..140.0))
      medium = wave(span, @rng.rand(80.0..115.0), @rng.rand(18.0..34.0))
      fine = wave(span, @rng.rand(22.0..30.0), @rng.rand(2.0..4.5))
      feature = character(island[:character], span)
      ends = [edge_style, edge_style]
      shoulders = ends.map { |style| style == :beach ? @rng.rand(170.0..280.0) : @rng.rand(50.0..90.0) }
      island[:ends], island[:shoulders] = ends, shoulders
      sea = @water + 70
      top = []
      x = left
      while x <= right + 0.01
        local = x - left
        y = base + broad.call(local) + medium.call(local) + fine.call(local) + feature.call(local)
        y = y.clamp(cavern? ? 0 : high, @water - 150)
        y = [y, @ceiling_floor[(x / Terrain::CELL).floor.clamp(0, @cols - 1)] + 120].max if cavern?
        reach = [local / shoulders[0], (right - x) / shoulders[1]].min
        side = local < span / 2 ? 0 : 1
        y = if ends[side] == :beach
          sea - (sea - y) * smoothstep(reach)**0.85
        else
          y + (1 - smoothstep(reach)) * 34 # a clifftop rounds over its edge
        end
        top << [x, y]
        x += 4
      end
      island[:profile] = top.map(&:last)
      top.each { |px, py| @top[(px / Terrain::CELL).floor.clamp(0, @cols - 1)] = py }
      island[:top] = top
      right_side = cliff(top.last, ends[1], 1)
      left_side = cliff(top.first, ends[0], -1).reverse
      fill(top + right_side + [[right_side.last[0], @height + 4], [left_side.first[0], @height + 4]] + left_side, SOIL)
      ends.each_with_index { |style, side| undercut(island, side) if style == :overhang }
      grottos(island)
    end

    # A cliff face from the end of the island's top down into the sea. Its slant
    # and bulges vary; overhanging ends lean back so the clifftop juts out.
    def cliff(from, style, direction)
      x, y = from
      sea = @water + 80
      return [[x, sea]] if y >= sea - 4
      slant = case style
      when :beach then @rng.rand(0.1..0.5)
      when :overhang then @rng.rand(-0.55..-0.25)
      else @rng.rand(-0.15..0.3)
      end
      bulge = wave(sea - y, @rng.rand(50.0..90.0), @rng.rand(10.0..26.0))
      points = []
      (y + 6).step(sea, 6) do |py|
        depth = py - y
        fade = smoothstep(depth / 40.0)
        # The lean saturates, so tall islands do not topple sideways.
        lean = 240 * (1 - Math.exp(-depth / 240.0))
        points << [x + direction * (slant * lean + bulge.call(depth) * fade), py]
      end
      points << [points.last[0], sea] unless points.empty?
      points.empty? ? [[x, sea]] : points
    end

    def edge_style = %i[beach cliff overhang overhang cliff][@rng.rand(5)]

    def character(kind, span)
      centre = span * @rng.rand(0.3..0.7)
      width = span * @rng.rand(0.16..0.26)
      bump = ->(x, w) { t = (x - centre) / w; t.abs >= 1 ? 0.0 : (1 - t * t)**2 }
      case kind
      when :summit
        height = @rng.rand(140.0..230.0)
        ->(x) { -height * bump.call(x, width) }
      when :valley
        depth = @rng.rand(110.0..170.0)
        ->(x) { depth * bump.call(x, width * 1.3) - 70 * (1 - bump.call(x, span * 0.6)) }
      when :cone
        # A volcano: a tall cone with a crater bowl in its summit.
        height = @rng.rand(190.0..250.0)
        crater = width * 0.28
        lambda do |x|
          rise = -height * [1 - ((x - centre) / (width * 1.4)).abs, 0].max**1.4
          t = (x - centre) / crater
          rise + (t.abs < 1 ? 60 * (1 - t * t) : 0)
        end
      when :mesa
        # Stepped plateaus with short, steep risers.
        step = @rng.rand(160.0..240.0)
        levels = Array.new((span / step).ceil + 2) { @rng.rand(-140.0..50.0).round(-1) }
        riser = @rng.rand(18.0..30.0)
        lambda do |x|
          k = (x / step).floor
          t = smoothstep((x - k * step - (step - riser)) / riser)
          levels[k] * (1 - t) + levels[k + 1] * t
        end
      else
        ->(x) { -60 * bump.call(x, width * 1.5) }
      end
    end

    # A sea cave beneath a cliff leaves the clifftop overhanging the water.
    def undercut(island, side)
      shoulder = island[:shoulders][side]
      x = side.zero? ? island[:left] + shoulder * 0.4 : island[:right] - shoulder * 0.4
      surface = surface_at(x)
      return unless surface && surface < @water - 210
      rx, ry = @rng.rand(60.0..100.0), @rng.rand(60.0..95.0)
      cy = [@water - @rng.rand(0.0..40.0), surface + ry + 80].max
      cx = x + (side.zero? ? -1 : 1) * rx * 0.2
      fill(blob(cx, cy, rx, ry, rough: 0.12), AIR, only: [SOIL])
    end

    # Grottos open from the sea into the island, leaving arches and buttresses
    # instead of a solid block below the playable surface.
    def grottos(island)
      span = island[:right] - island[:left]
      count = (span / 760.0).floor.clamp(0, 2)
      count += 1 if @rng.rand < 0.45
      count.times do |i|
        x = island[:left] + span * (i + @rng.rand(0.25..0.75)) / [count, 1].max
        surface = surface_at(x)
        next unless surface
        rx = @rng.rand(60.0..130.0)
        roof = ((x - rx).to_i..(x + rx).to_i).step(10).filter_map { |px| surface_at(px) }.max
        reach = [@water + 40 - (roof + @rng.rand(90.0..140.0)), rx * 2.2].min
        next if reach < 120
        fill(blob(x, @water + 40, rx, reach, rough: 0.1), AIR, only: [SOIL])
      end
    end

    def surface_at(x)
      return nil unless x.between?(0, @width - 1)
      @top[(x / Terrain::CELL).floor]
    end

    # ---- Caves and tunnels -----------------------------------------------------

    def caves(island)
      left, right = island[:left], island[:right]
      span = right - left
      count = (span / (archipelago? ? 420.0 : 340.0)).round.clamp(1, 5)
      placed = []
      count.times do |i|
        8.times do
          x = left + span * (i + @rng.rand(0.2..0.8)) / count
          surface = surface_at(x)
          next unless surface
          rx, ry = @rng.rand(60.0..150.0), @rng.rand(30.0..56.0)
          cy = surface + @rng.rand(60.0..230.0) + ry
          next if cy + ry * 0.6 > @water - 40
          next if placed.any? { |px, py, prx| (px - x).abs < prx + rx + 40 && (py - cy).abs < 140 }
          floor = cy + ry * 0.55
          # Ceilings must stay thick enough to stand on above.
          next if (-rx.to_i..rx.to_i).step(16).any? { |dx| (s = surface_at(x + dx)) && cy - ry * 1.2 - s < 42 }
          shape = blob(x, cy, rx, ry, rough: 0.16).map { |px, py| [px, [py, floor + Math.sin(px / 9.0) * 1.5].min] }
          fill(shape, AIR, only: [SOIL])
          placed << [x, cy, rx]
          tunnel_to_surface(x, cy, rx, ry) if @rng.rand < 0.7
          break
        end
      end
      placed.each_cons(2) do |(ax, ay, arx), (bx, by, brx)|
        next unless @rng.rand < 0.45 && (bx - ax).abs < 520
        tunnel([ax + arx * 0.6, ay], [bx - brx * 0.6, by], radius: @rng.rand(17.0..21.0))
      end
    end

    # A winding passage from a cave up to daylight.
    def tunnel_to_surface(x, cy, rx, ry)
      direction = @rng.rand < 0.5 ? -1 : 1
      start = [x + direction * rx * 0.55, cy - ry * 0.2]
      exit_x = x + direction * (rx + @rng.rand(50.0..150.0))
      surface = surface_at(exit_x)
      return unless surface
      tunnel(start, [exit_x, surface - 30], radius: @rng.rand(17.0..21.0), stop_at_surface: true)
    end

    def tunnel(from, to, radius:, stop_at_surface: false)
      x, y = from
      heading = Math.atan2(to[1] - y, to[0] - x)
      wobble = @rng.rand * TAU
      200.times do |i|
        disc(x, y, radius, AIR, only: [SOIL])
        break if Math.hypot(to[0] - x, to[1] - y) < radius
        if stop_at_surface && (s = surface_at(x)) && y < s - radius * 0.5
          break
        end
        desired = Math.atan2(to[1] - y, to[0] - x)
        turn = Math.atan2(Math.sin(desired - heading), Math.cos(desired - heading))
        heading += turn * 0.35 + Math.sin(i * 0.45 + wobble) * 0.22
        x += Math.cos(heading) * radius * 0.45
        y += Math.sin(heading) * radius * 0.45
      end
    end

    # ---- Floating rocks, cavern ceiling and pillars ------------------------------

    def floating_rocks(islands)
      count = archipelago? ? (@width / 900.0).round + 1 : cavern? ? (@width / 1600.0).round : (@width / 1500.0).round
      placed = []
      count.times do
        16.times do
          width = @rng.rand(130.0..300.0)
          x = @rng.rand(width..@width - width)
          below = ((x - width / 2).to_i..(x + width / 2).to_i).step(8).filter_map { |px| surface_at(px) }.min || @water
          ceiling = cavern? ? (((x - width / 2).to_i..(x + width / 2).to_i).step(8).map { |px| @ceiling_floor[(px / Terrain::CELL).clamp(0, @cols - 1)] }.max + 150) : @height * 0.2
          depth = @rng.rand(50.0..110.0) * (width / 200.0)**0.5
          y_max = below - depth - 110
          next if y_max < ceiling
          y = @rng.rand(ceiling..y_max)
          next if placed.any? { |px, py, pw| (px - x).abs < (pw + width) / 2 + 80 && (py - y).abs < 200 }
          next unless clear?(x - width / 2 - 50, y - 90, x + width / 2 + 50, y + depth + 60)
          fill(rock(x, y, width, depth), SOIL)
          placed << [x, y, width]
          ((x - width / 2 + 10).to_i..(x + width / 2 - 10).to_i).step(2) do |px|
            column = (px / Terrain::CELL).floor
            @top[column] = y if @top[column].nil? || @top[column] > y
          end
          break
        end
      end
    end

    # A flat-topped boulder that tapers to a rough point underneath.
    def rock(x, y, width, depth)
      half = width / 2
      bumps = wave(width, 26.0, 4.0)
      jag = wave(width, 14.0, 9.0)
      tip = @rng.rand(-0.25..0.25)
      top = (0..20).map do |i|
        u = i / 20.0
        px = x - half + width * u
        round = (1 - Math.sqrt([1 - ((u - 0.5) * 2)**8, 0].max)) * 26
        [px, y + bumps.call(px - x + half) + round]
      end
      bottom = (1..19).map do |i|
        u = 1 - i / 20.0
        v = (u - 0.5) * 2 - tip
        fall = [1 - v.abs**1.6, 0].max
        px = x - half + width * u
        [px, y + 18 + depth * fall + jag.call(px - x + half) * fall]
      end
      top + bottom
    end

    def ceiling
      broad = wave(@width, @rng.rand(220.0..320.0), 60.0)
      fine = wave(@width, 30.0, 6.0)
      @ceiling_floor = Array.new(@cols) { |c| (110 + broad.call(c * 2.0) + fine.call(c * 2.0)).clamp(60, 200) }
      @ceiling_mean = @ceiling_floor.sum / @cols
      points = (0..@width).step(4).map { |x| [x, @ceiling_floor[(x / Terrain::CELL).floor.clamp(0, @cols - 1)]] }
      fill([[0, -4]] + points + [[@width, -4]], SOIL)
      (@width / 230.0).round.times do
        x = @rng.rand(60..@width - 60)
        base = @ceiling_floor[(x / Terrain::CELL).floor] - 8
        width, length = @rng.rand(36.0..80.0), @rng.rand(50.0..130.0)
        fill(spike(x, base, width, length, 1), SOIL)
      end
      # Thick walls close the cave at both ends.
      [0, @width].each do |edge|
        wall = wave(@height, 90.0, 26.0)
        side = edge.zero? ? 1 : -1
        points = (0..@water + 80).step(8).map { |y| [edge + side * (54 + wall.call(y)), y] }
        fill([[edge, 0]] + points + [[edge, @height]], SOIL)
      end
    end

    # A stalactite (direction 1) or stalagmite (-1).
    def spike(x, base, width, length, direction)
      jag = wave(length, 12.0, 5.0)
      lean = @rng.rand(-0.2..0.2) * length
      right = (0..10).map { |i| t = i / 10.0; [x + width / 2 * (1 - t)**1.3 + lean * t + jag.call(t * length), base + direction * length * t] }
      left = (0..10).map { |i| t = 1 - i / 10.0; [x - width / 2 * (1 - t)**1.3 + lean * t - jag.call(t * length + 7), base + direction * length * t] }
      [[x - width / 2 - 6, base - direction * 10], [x + width / 2 + 6, base - direction * 10]] + right + left
    end

    # Hourglass columns join the cavern roof to the larger islands.
    def pillars(islands)
      islands.select { |island| island[:right] - island[:left] > 700 }.each do |island|
        next unless @rng.rand < 0.75
        x = @rng.rand(island[:left] + 250..island[:right] - 250)
        ground = surface_at(x)
        roof = @ceiling_floor[(x / Terrain::CELL).floor]
        next unless ground && ground - roof > 260
        waist = @rng.rand(26.0..40.0)
        flare = @rng.rand(70.0..110.0)
        sway = wave(ground - roof, 60.0, 10.0)
        right, left = [], []
        (roof - 20).step(ground + 40, 8) do |y|
          t = (y - roof) / (ground - roof)
          half = waist + (flare - waist) * ((t - 0.5).abs * 2)**2.2
          offset = sway.call(y - roof + 20)
          right << [x + offset + half, y]
          left.unshift([x + offset - half, y])
        end
        fill(right + left, SOIL)
        @occupied << [x - flare, x + flare]
      end
    end

    # ---- Set pieces --------------------------------------------------------------

    def set_pieces(island)
      span = island[:right] - island[:left]
      count = span > 900 ? 2 : 1
      count += 1 if span > 1600
      pieces = PIECES.fetch(@biome)
      count.times do
        kind = pieces[@rng.rand(pieces.length)]
        width = {tower: 96, colonnade: 170, henge: 160, wall: 190, arch: 120, ziggurat: 220,
          obelisk: 50, igloo: 130, spires: 110, basalt: 140}.fetch(kind)
        spot = flat_spot(island, width)
        next unless spot
        x, ground = spot
        @island = island
        send(kind, x, ground)
        @occupied << [x - width / 2 - 30, x + width / 2 + 30]
      end
    end

    # A level stretch of island top, away from the shoulders and other pieces.
    def flat_spot(island, width)
      left = island[:left] + island[:shoulders][0] + width / 2
      right = island[:right] - island[:shoulders][1] - width / 2
      return nil if right <= left
      candidates = (left.to_i..right.to_i).step(12).filter_map do |x|
        next if @occupied.any? { |a, b| x + width / 2 > a && x - width / 2 < b }
        ys = (-width / 2..width / 2).step(6).map { |dx| island_surface(island, x + dx) }
        next if ys.any?(&:nil?)
        next if ys.max - ys.min > 34 || ys.min < @height * 0.22
        next unless clear?(x - width / 2, ys.min - 250, x + width / 2, ys.min - 6)
        # Caves and tunnels carved later may have opened the ground underneath.
        next unless (-width / 2..width / 2).step(6).all? { |dx| solid?(x + dx, island_surface(island, x + dx) + 8) }
        [x, ys.max]
      end
      candidates.empty? ? nil : candidates[@rng.rand(candidates.length)]
    end

    def island_surface(island, x)
      index = ((x - island[:left]) / 4).round
      index.between?(0, island[:profile].length - 1) ? island[:profile][index] : nil
    end

    def solid?(x, y)
      return false unless x.between?(0, @width - 1) && y.between?(0, @height - 1)
      @data.getbyte((y / Terrain::CELL).floor * @cols + (x / Terrain::CELL).floor) != 0
    end

    def clear?(left, top, right, bottom)
      first, last = (left / Terrain::CELL).floor.clamp(0, @cols - 1), (right / Terrain::CELL).floor.clamp(0, @cols - 1)
      ((top / Terrain::CELL).floor.clamp(0, @rows - 1)..(bottom / Terrain::CELL).floor.clamp(0, @rows - 1)).all? do |row|
        @data.byteslice(row * @cols + first, last - first + 1).count("\x01-\x05").zero?
      end
    end

    def rect(left, top, right, bottom) = [[left, top], [right, top], [right, bottom], [left, bottom]]

    # Masonry fills only open air above the ground, so foundations follow the land.
    def build(points) = fill(points, MASONRY, only: [AIR])
    def cut(points) = fill(points, AIR, only: [MASONRY])

    def arch_hole(x, bottom, width, height)
      half = width / 2.0
      points = [[x - half, bottom + 2], [x - half, bottom - height + half]]
      (0..10).each { |i| a = Math::PI + Math::PI * i / 10; points << [x + Math.cos(a) * half, bottom - height + half + Math.sin(a) * half] }
      points + [[x + half, bottom + 2]]
    end

    def battlements(left, right, top, size: 14)
      count = ((right - left) / (size * 2)).floor
      return if count < 1
      gap = (right - left - count * size) / [count - 1, 1].max.to_f
      count.times { |i| build(rect(left + i * (size + gap), top - size, left + i * (size + gap) + size, top + 2)) }
    end

    def tower(x, ground)
      width, rise = @rng.rand(70.0..100.0), @rng.rand(110.0..180.0)
      top = ground - rise
      build(rect(x - width / 2, top, x + width / 2, ground + 40))
      battlements(x - width / 2 - 6, x + width / 2 + 6, top, size: 14)
      build(rect(x - width / 2 - 6, top, x + width / 2 + 6, top + 12))
      cut(arch_hole(x + @rng.rand(-8.0..8.0), ground, 30, 44))
      ((ground - 80).step(top + 34, -46)).each_with_index do |y, i|
        cut(arch_hole(x + (i.even? ? -1 : 1) * width * 0.18, y, 14, 22))
      end
      # Some towers have lost a corner to an old siege.
      if @rng.rand < 0.5
        side = @rng.rand < 0.5 ? -1 : 1
        corner = x + side * (width / 2 + 8)
        cut([[corner, top - 20], [corner - side * width * 0.55, top - 20], [corner, top + rise * 0.35]])
      end
    end

    def colonnade(x, ground)
      count = @rng.rand(3..5)
      spacing = @rng.rand(38.0..48.0)
      height = @rng.rand(80.0..120.0)
      first = x - spacing * (count - 1) / 2.0
      build(rect(first - 22, ground - 12, first + spacing * (count - 1) + 22, ground + 30))
      standing = []
      count.times do |i|
        cx = first + i * spacing
        broken = @rng.rand < 0.3
        h = broken ? height * @rng.rand(0.35..0.7) : height
        build(rect(cx - 8, ground - 12 - h, cx + 8, ground - 8))
        build(rect(cx - 12, ground - 12 - h, cx + 12, ground - 4 - h)) unless broken
        standing << cx unless broken
      end
      return if standing.length < 2
      build(rect(standing.first - 16, ground - 30 - height, standing.last + 16, ground - 12 - height))
      peak = (standing.first + standing.last) / 2.0
      build([[standing.first - 16, ground - 30 - height], [peak, ground - 52 - height], [standing.last + 16, ground - 30 - height]]) if standing.length > 2
    end

    def henge(x, ground)
      stones = @rng.rand(3..4)
      spacing = 46.0
      first = x - spacing * (stones - 1) / 2.0
      tops = []
      stones.times do |i|
        cx = first + i * spacing + @rng.rand(-4.0..4.0)
        h = @rng.rand(62.0..92.0)
        lean = @rng.rand(-5.0..5.0)
        build([[cx - 12, ground + 20], [cx - 11 + lean, ground - h], [cx + 2 + lean, ground - h - 6], [cx + 12 + lean, ground - h + 2], [cx + 13, ground + 20]])
        tops << [cx, ground - h]
      end
      tops.each_cons(2).first(1).each do |(ax, ay), (bx, by)|
        y = [ay, by].min
        build(rect(ax - 18, y - 16, bx + 18, y + 4))
      end
    end

    def wall(x, ground)
      length = @rng.rand(150.0..200.0)
      height = @rng.rand(44.0..64.0)
      left, right = x - length / 2, x + length / 2
      tops = (left.to_i..right.to_i).step(6).map { |px| [px, (island_surface(@island, px) || ground) - height] }
      build(tops + [[right, ground + 40], [left, ground + 40]])
      battlements(left, right, tops.map(&:last).min + 2, size: 12)
      cut(arch_hole(x, ground, 30, 42))
    end

    def arch(x, ground)
      width, rise = @rng.rand(96.0..124.0), @rng.rand(86.0..110.0)
      build(rect(x - width / 2, ground - rise, x + width / 2, ground + 40))
      cut(arch_hole(x, ground, width - 44, rise - 22))
      build(rect(x - width / 2 - 6, ground - rise - 10, x + width / 2 + 6, ground - rise + 2))
    end

    def ziggurat(x, ground)
      tiers = @rng.rand(3..4)
      width = @rng.rand(180.0..220.0)
      step = @rng.rand(24.0..30.0)
      tiers.times do |i|
        half = width / 2 - i * 24
        build(rect(x - half, ground - (i + 1) * step, x + half, ground + 40))
      end
      shrine = ground - tiers * step
      build(rect(x - 22, shrine - 34, x + 22, shrine + 2))
      cut(arch_hole(x, shrine, 14, 22))
      cut(arch_hole(x, ground, 28, 40))
    end

    def obelisk(x, ground)
      height = @rng.rand(120.0..170.0)
      build([[x - 18, ground + 30], [x - 13, ground - height], [x, ground - height - 22], [x + 13, ground - height], [x + 18, ground + 30]])
      build(rect(x - 26, ground - 14, x + 26, ground + 30))
    end

    def igloo(x, ground)
      rx, ry = @rng.rand(52.0..64.0), @rng.rand(46.0..58.0)
      dome = (0..24).map { |i| a = Math::PI + Math::PI * i / 24; [x + Math.cos(a) * rx, ground + 6 + Math.sin(a) * ry] }
      build(dome + [[x + rx, ground + 40], [x - rx, ground + 40]])
      side = @rng.rand < 0.5 ? -1 : 1
      build(rect(x + side * rx - (side.negative? ? 26 : 0), ground - 30, x + side * rx + (side.positive? ? 26 : 0), ground + 30))
      cut(arch_hole(x + side * (rx - 10), ground, 28, 30))
      cut(arch_hole(x, ground, 46, ry - 12))
    end

    def spires(x, ground)
      count = @rng.rand(2..3)
      count.times do |i|
        cx = x + (i - (count - 1) / 2.0) * 34 + @rng.rand(-6.0..6.0)
        height = @rng.rand(80.0..150.0)
        lean = @rng.rand(-14.0..14.0)
        half = @rng.rand(12.0..17.0)
        build([[cx - half, ground + 30], [cx - half + lean * 0.5, ground - height * 0.7], [cx + lean, ground - height],
          [cx + half + lean * 0.5, ground - height * 0.7], [cx + half, ground + 30]])
      end
    end

    def basalt(x, ground)
      count = @rng.rand(5..7)
      width = @rng.rand(18.0..22.0)
      first = x - width * count / 2.0
      count.times do |i|
        left = first + i * width
        height = @rng.rand(40.0..120.0)
        slant = @rng.rand(-10.0..10.0)
        build([[left, ground + 30], [left, ground - height], [left + width - 1, ground - height + slant], [left + width - 1, ground + 30]])
      end
    end

    # A stone aqueduct spans a narrow strait when its two shores are level enough.
    def bridges(islands)
      islands.each_cons(2) do |a, b|
        next unless @rng.rand < (archipelago? ? 0.45 : 0.6)
        from = a[:right] - a[:shoulders][1] - 10
        to = b[:left] + b[:shoulders][0] + 10
        ya, yb = surface_at(from), surface_at(to)
        next unless ya && yb && (ya - yb).abs < 70 && to - from < 460
        next if @occupied.any? { |l, r| r > from - 20 && l < to + 20 }
        deck = [ya, yb].min - 4
        piers = [((to - from) / 210.0).round, 1].max
        build(rect(from - 10, deck - 16, to + 10, deck + 8))
        battlements(from, to, deck - 16, size: 10)
        (1...piers).each do |i|
          px = from + (to - from) * i / piers
          build(rect(px - 16, deck, px + 16, @height))
        end
        piers.times do |i|
          left = from + (to - from) * i / piers + (i.zero? ? 0 : 16)
          right = from + (to - from) * (i + 1) / piers - (i == piers - 1 ? 0 : 16)
          build(rect(left, deck, right, deck + 34))
          cut(arch_hole((left + right) / 2, deck + 70, right - left - 4, 52)) if right - left > 40
        end
        @occupied << [from - 20, to + 20]
      end
    end

    # Steel girders: stepping stones across wide gaps and lofty perches.
    def girders(islands)
      count = archipelago? ? (@width / 1300.0).round : cavern? ? 2 : (@width / 2800.0).floor
      count.times do
        12.times do
          length = @rng.rand(90.0..150.0)
          x = @rng.rand(120.0..@width - 120.0)
          below = ((x - length / 2).to_i..(x + length / 2).to_i).step(10).map { |px| surface_at(px) || @water }.min
          floor = cavern? ? @ceiling_floor[(x / Terrain::CELL).floor] + 130 : @height * 0.22
          next if below - 140 < floor
          y = @rng.rand(floor..below - 140)
          next if @occupied.any? { |l, r| x + length / 2 > l && x - length / 2 < r }
          next unless clear?(x - length / 2 - 40, y - 80, x + length / 2 + 40, y + 60)
          slope = @rng.rand < 0.4 ? @rng.rand(-0.35..0.35) : 0
          girder(x, y, length, slope)
          @occupied << [x - length / 2 - 20, x + length / 2 + 20]
          break
        end
      end
    end

    def girder(x, y, length, slope)
      dx, dy = Math.cos(Math.atan(slope)) * length / 2, Math.sin(Math.atan(slope)) * length / 2
      nx, ny = -Math.sin(Math.atan(slope)) * 6, Math.cos(Math.atan(slope)) * 6
      fill([[x - dx - nx, y - dy - ny], [x + dx - nx, y + dy - ny], [x + dx + nx, y + dy + ny], [x - dx + nx, y - dy + ny]], GIRDER, only: [AIR])
    end

    # Overlapping carvings can leave crumbs of land floating in the air. Label
    # connected runs row by row (union-find over spans) and drop tiny pieces.
    def remove_specks(min_cells)
      parent = []
      find = lambda do |i|
        i = parent[i] = parent[parent[i]] while parent[i] != i
        i
      end
      previous = []
      runs = []
      @rows.times do |row|
        line = @data.byteslice(row * @cols, @cols)
        current = []
        start = 0
        while (left = line.index(/[^\x00]/n, start))
          right = (line.index("\x00", left) || @cols) - 1
          id = runs.length
          runs << [row, left, right]
          parent << id
          previous.each do |other, a, b|
            next if b < left - 1 || a > right + 1
            ra, rb = find.call(id), find.call(other)
            parent[ra] = rb if ra != rb
          end
          current << [id, left, right]
          start = right + 1
          break if start >= @cols
        end
        previous = current
      end
      sizes = Hash.new(0)
      runs.each_with_index { |(_, a, b), id| sizes[find.call(id)] += b - a + 1 }
      runs.each_with_index do |(row, a, b), id|
        next if sizes[find.call(id)] >= min_cells
        @data[row * @cols + a, b - a + 1] = "\0" * (b - a + 1)
      end
    end

    # ---- Rasterization -------------------------------------------------------------

    def blob(cx, cy, rx, ry, rough: 0.14, points: 72)
      phases = Array.new(4) { @rng.rand * TAU }
      amps = [rough, rough * 0.55, rough * 0.3, rough * 0.15]
      freqs = [2, 3, 5, 9]
      Array.new(points) do |i|
        a = i * TAU / points
        r = 1 + 4.times.sum { |k| amps[k] * Math.sin(a * freqs[k] + phases[k]) }
        [cx + Math.cos(a) * rx * r, cy + Math.sin(a) * ry * r]
      end
    end

    def disc(x, y, radius, material, only: nil)
      cell = Terrain::CELL
      ((y - radius).div(cell)..(y + radius).div(cell)).each do |row|
        next unless row.between?(0, @rows - 1)
        dy = row * cell + 1 - y
        next if dy.abs > radius
        dx = Math.sqrt(radius * radius - dy * dy)
        span(row, ((x - dx) / cell).ceil, ((x + dx) / cell).floor, material, only)
      end
    end

    # Even-odd scanline fill with an active edge list: linear in rows + edges.
    def fill(points, material, only: nil)
      cell = Terrain::CELL.to_f
      starts = Hash.new { |hash, key| hash[key] = [] }
      low, high = @rows, -1
      count = points.length
      count.times do |i|
        x1, y1 = points[i]
        x2, y2 = points[(i + 1) % count]
        x1, y1, x2, y2 = x1 / cell, y1 / cell, x2 / cell, y2 / cell
        next if y1 == y2
        x1, y1, x2, y2 = x2, y2, x1, y1 if y1 > y2
        first = [(y1 - 0.5).ceil, 0].max
        last = [(y2 - 0.5).ceil - 1, @rows - 1].min
        next if first > last
        slope = (x2 - x1) / (y2 - y1)
        starts[first] << [last, x1 + (first + 0.5 - y1) * slope, slope]
        low = first if first < low
        high = last if last > high
      end
      active = []
      (low..high).each do |row|
        active.concat(starts[row]) if starts.key?(row)
        active.reject! { |edge| edge[0] < row }
        xs = active.map do |edge|
          x = edge[1]
          edge[1] += edge[2]
          x
        end
        xs.sort!
        xs.each_slice(2) do |a, b|
          span(row, a.ceil, b.floor, material, only) if b
        end
      end
    end

    def span(row, left, right, material, only)
      left = left.clamp(0, @cols)
      right = right.clamp(-1, @cols - 1)
      return if right < left
      offset, length = row * @cols + left, right - left + 1
      if only
        segment = @data.byteslice(offset, length)
        replaced = segment.tr(only.map(&:chr).join, material.chr)
        @data[offset, length] = replaced unless replaced == segment
      else
        @data[offset, length] = material.chr * length
      end
    end
  end
end
