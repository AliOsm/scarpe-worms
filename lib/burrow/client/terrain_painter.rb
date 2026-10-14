# frozen_string_literal: true

require "chunky_png"

module Burrow
  module Client
    class TerrainPainter
      TILE = 192 # 384 world pixels; a small blast changes only one or two textures.
      # Baked material kit (tools/build_art_terrain.py, docs/ART_DIRECTION.md).
      # Every texture is authored at cell resolution, so painting is table lookups only.
      KIT = File.join(Burrow::ROOT, "assets/art/terrain")
      T = 512      # fill texture size (cells); the baked fills wrap seamlessly
      CRUST = 20   # surface lip rows
      TUFT = 12    # fringe rows above the surface (optional, see TUFTS)
      DEEP = 24    # cells below the air above where the darker "deep" fill begins
      EDGE = 2     # cells above air below that use the dark silhouette rim
      SHADE = 6    # cells above air below that use the occluded fill
      # Tufts paint into empty cells, so the visible mask would no longer equal the
      # collision mask. Kept off; the art is in terrain/{biome}-tufts.png.
      TUFTS = false
      # A tile's pixels depend on this many rows above it (DEEP priming) and below it
      # (underside rim/shade, tufts), and one column either side; the digest covers them.
      RIM_UP = DEEP + 2
      RIM_DOWN = TUFTS ? TUFT + 2 : SHADE + 2
      RIM_SIDE = 2

      Kit = Struct.new(:fill, :deep, :shade, :edge, :crust, :tufts, :masonry, :girder, :masonry_edge, :scorch)

      # Apply PNG's UP filter to a whole scanline using Ruby's C-backed integer
      # operations. Each byte has a high-bit guard during subtraction, preventing
      # a borrow into its neighbor; the XOR restores the original high bits.
      # The filtered bytes, palette and compression are identical to ChunkyPNG.
      class TileImage < ChunkyPNG::Image
        protected

        def encode_png_image_without_interlacing(color_mode, bit_depth = 8, filtering = ChunkyPNG::FILTER_NONE)
          return super unless filtering == ChunkyPNG::FILTER_UP
          stream = super(color_mode, bit_depth, ChunkyPNG::FILTER_NONE)
          bytes = ChunkyPNG::Color.scanline_bytesize(color_mode, bit_depth, width)
          high = ("\x80".b * bytes).unpack1("H*").to_i(16)
          low = high - (high >> 7)
          current = stream.byteslice((height - 1) * (bytes + 1) + 1, bytes).unpack1("H*").to_i(16)
          (height - 1).downto(1) do |y|
            pos = y * (bytes + 1)
            previous = stream.byteslice(pos - bytes, bytes).unpack1("H*").to_i(16)
            delta = ((current | high) - (previous & low)) ^ ((current ^ ~previous) & high)
            stream.setbyte(pos, ChunkyPNG::FILTER_UP)
            stream[pos + 1, bytes] = [delta.to_s(16).rjust(bytes * 2, "0")].pack("H*")
            current = previous
          end
          stream.setbyte(0, ChunkyPNG::FILTER_UP)
          stream
        end
      end

      # The baked kit is RGBA8. Reconstruct its average-filtered rows a pixel at
      # a time, with independent arithmetic in the four packed color channels.
      class KitImage < ChunkyPNG::Image
        class << self
          protected

          def decode_png_str_scanline_average(stream, pos, prev_pos, line_length, pixel_size)
            return super unless pixel_size == 4
            pixels = stream.byteslice(pos + 1, line_length).unpack("N*")
            above = prev_pos ? stream.byteslice(prev_pos + 1, line_length).unpack("N*") : Array.new(pixels.length, 0)
            left = 0
            pixels.each_index do |x|
              up, value = above[x], pixels[x]
              average = ((left & 0xfefefefe) >> 1) + ((up & 0xfefefefe) >> 1) + (left & up & 0x01010101)
              left = ((value & 0x7f7f7f7f) + (average & 0x7f7f7f7f)) ^ ((value ^ average) & 0x80808080)
              pixels[x] = left
            end
            stream[pos + 1, line_length] = pixels.pack("N*")
          end
        end
      end

      def self.kit(biome)
        @kits ||= {}
        @kits[biome] ||= begin
          read = ->(name) { KitImage.from_file(File.join(KIT, name)).pixels.freeze }
          Kit.new(*%w[fill deep shade edge crust tufts masonry].map { |k| read.call("#{biome}-#{k}.png") },
            read.call("girder.png"), read.call("#{biome}-masonry-edge.png"), read.call("#{biome}-scorch.png")).freeze
        end
      end

      def initialize(directory)
        @directory, @tiles, @hashes, @sequence = directory, {}, {}, 0
      end

      def render(terrain, biome)
        @sequence += 1
        kit = self.class.kit(biome)
        dimensions = [terrain.cols, terrain.rows]
        if @dimensions != dimensions
          @dimensions = dimensions
          @tiles.clear
          @hashes.clear
          @overview = ChunkyPNG::Image.new((terrain.cols / 4.0).ceil, (terrain.rows / 4.0).ceil, 0)
        end
        tiles_x = (terrain.cols.to_f / TILE).ceil
        tiles_y = (terrain.rows.to_f / TILE).ceil
        tiles_y.times do |ty|
          tiles_x.times do |tx|
            x, y = tx * TILE, ty * TILE
            w, h = [TILE, terrain.cols - x].min, [TILE, terrain.rows - y].min
            # Include a rim around a tile: a cut just across the boundary changes its shading.
            digest = Digest::SHA256.new
            left, right = [0, x - RIM_SIDE].max, [terrain.cols, x + w + RIM_SIDE].min
            ([0, y - RIM_UP].max...[terrain.rows, y + h + RIM_DOWN].min).each do |cy|
              digest << terrain.data.byteslice(cy * terrain.cols + left, right - left)
            end
            signature = [digest.hexdigest, biome, terrain.seed]
            id = "#{tx}-#{ty}"
            next if @hashes[id] == signature
            @hashes[id] = signature
            png = self.class.tile(terrain, x, y, w, h, kit)
            # TILE is divisible by four: these are exactly the global overview
            # samples. Keep unchanged regions instead of resampling every tile
            # after a small crater, and retain only the much smaller overview.
            (0...h).step(4) do |ly|
              source = ly * w
              target = (y / 4 + ly / 4) * @overview.width + x / 4
              (0...w).step(4) { |lx| @overview.pixels[target + lx / 4] = png.pixels[source + lx] }
            end
            path = File.join(@directory, "tile-#{id}-#{@sequence}.png")
            # These are disposable local textures, not download assets. Palette
            # selection and maximum compression delayed every crater; RGBA at
            # level 1 keeps the same pixels and avoids that worker-side pause.
            png.save(path, :fast_rgba)
            @tiles[id] = {id: id, x: x * 2, y: y * 2, width: w * 2, height: h * 2, path: path}
            # Keep older versions long enough for Ruby/Rust to retire the previous frame.
            Dir[File.join(@directory, "tile-#{id}-*.png")].sort_by { |p| File.mtime(p) }.reverse.drop(3).each { |p| File.unlink(p) }
          end
        end
        path = File.join(@directory, "overview-#{@sequence}.png")
        @overview.save(path, :fast_rgba)
        File.unlink(File.join(@directory, "overview-#{@sequence - 3}.png")) if @sequence > 3
        {tiles: @tiles.values, overview: path, revision: terrain.revision, checksum: terrain.checksum}
      end

      # Per cell: girder (2) and masonry (3) use their own textures; scorched soil (4)
      # is charred with no surface lip; soil (1) takes the surface lip by depth below
      # the air above, then a dark rim on undersides and walls, an occluded tone under
      # the lip and over cave ceilings, and a slightly darker body deep inside.
      # Colours are ChunkyPNG 0xRRGGBBAA integers.
      def self.tile(terrain, ox, oy, width, height, kit)
        png = TileImage.new(width, height, 0)
        out = png.pixels
        cols, rows, data = terrain.cols, terrain.rows, terrain.data
        fill, deep, shade, edge, crust, tufts, masonry, girder, masonry_edge, scorch = kit.to_a
        last = cols - 1
        texture_rows = Array.new(height) { |ly| ((oy + ly) & (T - 1)) * T }
        width.times do |lx|
          x = ox + lx
          tx = x & (T - 1)
          # Cells since the air above, read upward only until the first air cell.
          up = 0
          burnt = false # charred soil above this cell, since the last air: no surface lip
          cy = oy - 1
          floor = [oy - RIM_UP, 0].max
          while cy >= floor && (above = data.getbyte(cy * cols + x)) != 0
            burnt ||= above == 4
            up += 1
            cy -= 1
          end
          air = oy # next air row below the current row (forward pointer)
          stop = [oy + height + SHADE + 1, rows].min
          height.times do |ly|
            y = oy + ly
            i = y * cols + x
            material = data.getbyte(i)
            if material.zero?
              up = 0
              burnt = false
              if TUFTS
                k = 1
                k += 1 while k <= TUFT && y + k < rows && data.getbyte((y + k) * cols + x).zero?
                if k <= TUFT && y + k < rows && data.getbyte((y + k) * cols + x) == 1
                  tuft = tufts[(TUFT - k) * T + tx]
                  out[ly * width + lx] = tuft if (tuft & 255) != 0
                end
              end
              next
            end
            up += 1
            burnt ||= material == 4
            if air <= y
              # Scan forward to the next real air cell. Past `stop` every row of this
              # tile is more than SHADE cells above air, so stopping there is exact; the
              # pointer only moves forward, so a column costs at most height + SHADE reads.
              air = y + 1
              air += 1 while air < stop && data.getbyte(air * cols + x) != 0
              air = rows + SHADE + 1 if air == rows # the world floor is not an underside
            end
            dn = air - y
            t = texture_rows[ly] + tx
            out[ly * width + lx] = if material == 2
              girder[(up > 6 ? 5 : up - 1) * 32 + (x & 31)]
            else
              rim = dn <= EDGE || x.zero? || x == last || data.getbyte(i - 1).zero? || data.getbyte(i + 1).zero?
              if material == 3
                (rim ? masonry_edge : masonry)[((y & 63) << 7) | (x & 127)]
              elsif material == 4
                rim ? edge[t] : scorch[t]
              else
                lip = up <= CRUST && !burnt ? crust[(up - 1) * T + tx] : 0
                alpha = lip & 255
                if alpha == 255 then lip
                elsif rim then edge[t]
                elsif alpha != 0 || dn <= SHADE then shade[t]
                elsif up > DEEP then deep[t]
                else fill[t]
                end
              end
            end
          end
        end
        png
      end
    end
  end
end
