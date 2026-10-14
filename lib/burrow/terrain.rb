# frozen_string_literal: true

require "zlib"
require "base64"
require "openssl"

module Burrow
  class Terrain
    CELL = 2
    W = WIDTH / CELL
    H = HEIGHT / CELL
    SIZE = W * H
    MAX_WIDTH = 4800
    MAX_HEIGHT = 1600
    # Materials: 0 air, 1 soil, 2 girder, 3 masonry, 4 scorched soil (blast rims).
    SOLID = "\x01-\x04"
    SCORCH = 4
    attr_reader :data, :revision, :seed, :shape, :width, :height, :cols, :rows

    def initialize(seed:, shape: "islands", data: nil, revision: 0, width: WIDTH, height: HEIGHT, biome: "meadow")
      @seed, @shape, @revision, @biome = seed, shape, revision, biome
      unless width.is_a?(Integer) && height.is_a?(Integer) && width.between?(1440, MAX_WIDTH) && height.between?(720, MAX_HEIGHT) && width.even? && height.even?
        raise RuleError, "Invalid battlefield dimensions."
      end
      @width, @height, @cols, @rows = width, height, width / CELL, height / CELL
      @data = data || generate
      raise RuleError, "Invalid terrain data." unless @data.bytesize == cols * rows && @data.count("\x00-\x04") == @data.bytesize
    end

    def solid?(x, y)
      return false unless x >= 0 && x < width && y >= 0 && y < height
      # Simulation coordinates are non-negative after the bounds check.  The
      # integer conversion preserves the old floor semantics for floats while
      # avoiding two float divisions and floor calls on every collision sample.
      data = @data
      data.getbyte((y.to_i >> 1) * cols + (x.to_i >> 1)) != 0
    end

    def free_body?(x, feet)
      return false unless x.between?(12, width - 12) && feet.between?(24, height - 10)
      [-6, 0, 6].all? { |dx| [-18, -9, -1].all? { |dy| !solid?(x + dx, feet + dy) } }
    end

    def surface(x, from: 0)
      # Step whole cells from a cell boundary, so the result is the top edge of
      # the first solid cell rather than a pixel inside it.
      y = [(from / CELL).floor * CELL, 0].max
      y += CELL until y >= height || solid?(x, y)
      y
    end

    def landing(x, y, water: self.height - 96)
      # Feet rest on the uphill edge of the body, so slopes are valid ground too.
      feet = [-6, 6].map { |dx| surface(x + dx, from: y) }.min
      feet < water - 10 && free_body?(x, feet) ? feet : nil
    end

    # Blasts char the soil around a crater (`scorch`); digging tools leave clean tunnels.
    def carve(x, y, radius, scorch: true)
      return false if radius <= 0
      changed = charred = false
      rim = scorch ? (radius * 0.2).clamp(5.0, 12.0) : 0
      outer = radius + rim
      min_y, max_y = [(y - outer).div(CELL), 0].max, [(y + outer).div(CELL), rows - 1].min
      (min_y..max_y).each do |cy|
        dy = cy * CELL + 1 - y
        next if dy.abs > outer
        reach = Math.sqrt(outer * outer - dy * dy)
        next if x + reach < 0 || x - reach >= width
        if dy.abs <= radius
          dx = Math.sqrt(radius * radius - dy * dy)
          left = [[(x - dx).div(CELL), 0].max, cols - 1].min
          right = [[(x + dx).div(CELL), 0].max, cols - 1].min
          offset, length = cy * cols + left, right - left + 1
          if x + dx >= 0 && x - dx < width && @data.byteslice(offset, length).count(SOLID).positive?
            @data[offset, length] = "\0" * length
            changed = true
          end
          segments = [[x - reach, x - dx], [x + dx, x + reach]]
        else
          segments = [[x - reach, x + reach]]
        end
        next unless scorch
        segments.each do |from, to|
          left = [[from.div(CELL), 0].max, cols - 1].min
          right = [[to.div(CELL), 0].max, cols - 1].min
          next if to < 0 || from >= width || right < left
          offset, length = cy * cols + left, right - left + 1
          segment = @data.byteslice(offset, length)
          next unless segment.include?("\x01")
          @data[offset, length] = segment.tr("\x01", "\x04")
          charred = true
        end
      end
      touch! if changed || charred
      changed
    end

    def bridge(x, y, width: 140, height: 12)
      left = ((x - width / 2) / CELL).floor.clamp(0, cols - 1)
      right = ((x + width / 2) / CELL).floor.clamp(0, cols - 1)
      top = (y / CELL).floor.clamp(0, rows - 1)
      bottom = ((y + height) / CELL).floor.clamp(0, rows - 1)
      (top..bottom).each { |cy| @data[cy * cols + left, right - left + 1] = "\x02" * (right - left + 1) }
      touch!
    end

    # A steel beam centred on its top-left-anchored horizontal position: at angle 0
    # this is exactly `bridge(x, y)`; other angles rotate it about its middle.
    def girder(x, y, length: 140, thickness: 12, angle: 0)
      return bridge(x, y, width: length, height: thickness) if angle.zero?
      ux, uy = Math.cos(angle * Math::PI / 180), Math.sin(angle * Math::PI / 180)
      cx, cy, half = x, y + thickness / 2.0, length / 2.0
      corners = [[-half, -thickness / 2.0], [half, -thickness / 2.0], [half, thickness / 2.0], [-half, thickness / 2.0]]
        .map { |a, b| [(cx + ux * a - uy * b) / CELL, (cy + uy * a + ux * b) / CELL] }
      top, bottom = corners.map(&:last).minmax
      (top.floor.clamp(0, rows - 1)..bottom.ceil.clamp(0, rows - 1)).each do |row|
        scan = row + 0.5
        xs = corners.zip(corners.rotate).filter_map do |(x1, y1), (x2, y2)|
          x1 + (scan - y1) * (x2 - x1) / (y2 - y1) if (y1 <= scan && y2 > scan) || (y2 <= scan && y1 > scan)
        end
        next if xs.length < 2
        left, right = xs.min.ceil.clamp(0, cols - 1), xs.max.floor.clamp(0, cols - 1)
        @data[row * cols + left, right - left + 1] = "\x02" * (right - left + 1) if right >= left
      end
      touch!
    end

    # The first open cell at or below `from` in this column (a cavern's roof underside).
    def open_below(x, from)
      y = [from.to_i, 0].max
      y += CELL while y < height && solid?(x, y)
      y
    end

    def ray(x, y, dx, dy, limit: self.width, step: 3)
      length = Math.hypot(dx, dy)
      return nil if length.zero?
      ux, uy = dx / length, dy / length
      distance = 0
      while distance <= limit
        px, py = x + ux * distance, y + uy * distance
        return [px, py] if solid?(px, py)
        distance += step
      end
      nil
    end

    def checksum = (@checksum ||= OpenSSL::Digest::SHA256.hexdigest(data))

    def export
      return @export if @export
      # Material rows contain long runs. RLE avoids expensive match searches
      # while retaining a standard zlib stream readable by protocol-4 clients.
      deflater = Zlib::Deflate.new(Zlib::BEST_SPEED, Zlib::MAX_WBITS, Zlib::DEF_MEM_LEVEL, Zlib::RLE)
      compressed = deflater.deflate(data, Zlib::FINISH)
      # Unusual saved masks (such as repeated stripes) can expand under RLE.
      # Fall back before base64 terrain alone uses half the server frame limit.
      compressed = Zlib::Deflate.deflate(data) if compressed.bytesize > 192 * 1024
      @export = {"revision" => revision, "seed" => seed, "shape" => shape, "width" => width, "height" => height,
        "data" => Base64.strict_encode64(compressed), "checksum" => checksum}.freeze
    ensure
      deflater&.close
    end

    def self.restore(value)
      raise RuleError, "Invalid terrain packet." unless value.is_a?(Hash) && value["data"].is_a?(String) && value["data"].bytesize < 700_000
      inflater = Zlib::Inflate.new
      data = +"".b
      inflater.inflate(Base64.strict_decode64(value.fetch("data"))) do |chunk|
        data << chunk
        raise RuleError, "Terrain packet too large." if data.bytesize > MAX_WIDTH / CELL * (MAX_HEIGHT / CELL)
      end
      terrain = new(seed: value.fetch("seed"), shape: value.fetch("shape"), data: data, revision: value.fetch("revision"), width: value.fetch("width", WIDTH), height: value.fetch("height", HEIGHT))
      raise RuleError, "Terrain checksum mismatch." unless terrain.checksum == value["checksum"]
      # A client/worker already has the compressed authoritative packet. Keep it
      # instead of recompressing megabytes of terrain on the animation thread.
      terrain.instance_variable_set(:@export, value.merge("width" => terrain.width, "height" => terrain.height).freeze)
      terrain
    rescue Zlib::Error, ArgumentError, KeyError => error
      raise RuleError, "Invalid terrain packet: #{error.class}."
    ensure
      inflater&.close
    end

    private

    def touch!
      @revision += 1
      @checksum = @export = nil
    end

    def generate
      require_relative "terrain_generator"
      TerrainGenerator.new(seed: seed, shape: shape, width: width, height: height, biome: @biome).generate
    end
  end
end
