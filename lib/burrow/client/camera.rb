# frozen_string_literal: true

module Burrow
  module Client
    class Camera
      VIEW_WIDTH, VIEW_HEIGHT = 1440, 720
      attr_reader :x, :y, :zoom, :width, :height, :following

      def initialize(width, height)
        @width, @height, @zoom = width, height, 1.0
        @x, @y, @following = 0.0, 0.0, true
      end

      def minimum = [VIEW_WIDTH.fdiv(width), VIEW_HEIGHT.fdiv(height), 1.0].min
      def world(sx, sy) = [x + sx / zoom, y + sy / zoom]
      def screen(wx, wy) = [(wx - x) * zoom, (wy - y) * zoom]
      def overview? = (zoom - minimum).abs < 0.001

      def overview
        @zoom, @following = minimum, false
        center(width / 2.0, height / 2.0)
      end

      def follow
        @following = true
        @zoom = 1.0 if overview?
        @snap = true
      end

      def zoom_by(direction)
        cx, cy = world(VIEW_WIDTH / 2.0, VIEW_HEIGHT / 2.0)
        levels = ([minimum, 0.5, 0.7, 1.0, 1.25].select { |z| z >= minimum }).uniq.sort
        @zoom = direction > 0 ? (levels.find { |z| z > zoom + 0.001 } || levels.last) : (levels.reverse.find { |z| z < zoom - 0.001 } || levels.first)
        center(cx, cy)
      end

      def pan(dx, dy)
        @following = false
        @x += dx / zoom
        @y += dy / zoom
        clamp
      end

      def navigate(wx, wy)
        @following = false
        @zoom = 0.7 if overview?
        center(wx, wy)
      end

      def update(target, dt:)
        return unless following && target
        tx, ty = target
        wanted_x, wanted_y = tx - VIEW_WIDTH * 0.46 / zoom, ty - VIEW_HEIGHT * 0.58 / zoom
        blend = @snap ? 1.0 : 1 - Math.exp(-dt.clamp(0, 0.05) * 7)
        # Resting characters don't make the entire landscape drift by subpixels.
        @x += (wanted_x - x) * blend if (wanted_x - x).abs * zoom > 0.7
        @y += (wanted_y - y) * blend if (wanted_y - y).abs * zoom > 0.7
        @snap = false
        clamp
      end

      private

      def center(wx, wy)
        @x, @y = wx - VIEW_WIDTH / (zoom * 2), wy - VIEW_HEIGHT / (zoom * 2)
        clamp
      end

      def clamp
        vw, vh = VIEW_WIDTH / zoom, VIEW_HEIGHT / zoom
        @x = width < vw ? (width - vw) / 2 : x.clamp(0, width - vw)
        # Allow upward tracking of a high ballistic arc, while the overview stays centered.
        @y = height < vh ? (height - vh) / 2 : y.clamp(-500, height - vh)
      end
    end
  end
end
