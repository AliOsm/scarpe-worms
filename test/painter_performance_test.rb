# frozen_string_literal: true
require_relative "test_helper"
require_relative "../lib/burrow/client/terrain_painter"

class PainterPerformanceTest < Minitest::Test
  Painter = Burrow::Client::TerrainPainter

  def test_row_filter_preserves_png_bytes_for_partial_rows_and_color_modes
    random = Random.new(291)
    [1, 2, 3, 7, 13, 192].each do |width|
      [1, 2, 19].each do |height|
        [Array.new(width * height) { random.rand(0x100000000) },
         Array.new(width * height) { [0, 0xffffffff, 0xff0080ff, 0x0080ffff].sample(random: random) }].each do |pixels|
          expected = ChunkyPNG::Image.new(width, height, pixels)
          actual = Painter::TileImage.new(width, height, pixels)
          [{}, {color_mode: ChunkyPNG::COLOR_TRUECOLOR_ALPHA}, :fast_rgba, :best_compression].each do |encoding|
            assert_equal expected.to_blob(encoding.dup), actual.to_blob(encoding.dup), "#{width}x#{height} #{encoding}"
          end
        end
      end
    end
  end

  def test_packed_average_reconstructs_all_channel_values_without_carries
    random = Random.new(812)
    [1, 2, 7, 192, 512].each do |width|
      pixels = Array.new(width * 8) { random.rand(0x100000000) }
      pixels[0, [8, pixels.length].min] = [0, 0xffffffff, 0x80808080, 0x7f7f7f7f,
        0xff00ff00, 0x00ff00ff, 0x01010101, 0xfefefefe].first([8, pixels.length].min)
      image = ChunkyPNG::Image.new(width, 8, pixels)
      [ChunkyPNG::FILTER_NONE, ChunkyPNG::FILTER_SUB, ChunkyPNG::FILTER_UP,
       ChunkyPNG::FILTER_AVERAGE, ChunkyPNG::FILTER_PAETH].each do |filter|
        blob = image.to_blob(color_mode: ChunkyPNG::COLOR_TRUECOLOR_ALPHA, filtering: filter)
        assert_equal pixels, Painter::KitImage.from_blob(blob).pixels, "width #{width}, filter #{filter}"
      end
    end
  end

  def test_optimized_kit_decode_matches_every_committed_texture
    Dir[File.join(Painter::KIT, "*.png")].sort.each do |path|
      assert_equal ChunkyPNG::Image.from_file(path).pixels, Painter::KitImage.from_file(path).pixels, File.basename(path)
    end
  end
end
