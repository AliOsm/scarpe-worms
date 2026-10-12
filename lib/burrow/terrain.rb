# frozen_string_literal: true

require "zlib"
require "base64"

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
      @data.getbyte((y / CELL).floor * cols + (x / CELL).floor) != 0
    end

    def free_body?(x, feet)
      return false unless x.between?(12, width - 12) && feet.between?(24, height - 10)
      [-6, 0, 6].all? { |dx| [-18, -9, -1].all? { |dy| !solid?(x + dx, feet + dy) } }
    end

    def surface(x, from: 0)
      y = [from.to_i, 0].max
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

    def checksum = (@checksum ||= Digest::SHA256.hexdigest(data))
    def export = (@export ||= {"revision" => revision, "seed" => seed, "shape" => shape, "width" => width, "height" => height, "data" => Base64.strict_encode64(Zlib::Deflate.deflate(data)), "checksum" => checksum}.freeze)

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
