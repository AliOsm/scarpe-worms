# frozen_string_literal: true

module Burrow
  module Client
    class Camera
      VIEW_WIDTH, VIEW_HEIGHT = 1440, 720
      attr_reader :x, :y, :zoom, :width, :height, :following

      def initialize(width, height)
        @width, @height, @zoom = width, height, 1.0
        @x, @y, @following = 0.0, 0.0, true
        @overview, @ceiling = false, -500
        @snap = true
      end

      def minimum = [VIEW_WIDTH.fdiv(width), VIEW_HEIGHT.fdiv(height), 1.0].min
      def world(sx, sy) = [x + sx / zoom, y + sy / zoom]
      def screen(wx, wy) = [(wx - x) * zoom, (wy - y) * zoom]
      def overview? = @overview

      def overview
        @zoom, @following = minimum, false
        @overview, @ceiling = true, -500
        center(width / 2.0, height / 2.0)
      end

      def follow
        @following = true
        @zoom = 1.0 if overview?
        @overview = false
        @snap = true
      end

      # Wheel zoom keeps the world point beneath the pointer in place. Taking an
      # explicit anchor enters free camera so follow does not undo that choice.
      # Buttons/keys keep following, centered on the current viewport.
      def zoom_by(direction, anchor: nil)
        return if direction.zero?
        sx, sy = anchor || [VIEW_WIDTH / 2.0, VIEW_HEIGHT / 2.0]
        cx, cy = world(sx, sy)
        levels = ([minimum, 0.5, 0.7, 1.0, 1.25].select { |z| z >= minimum }).uniq.sort
        next_zoom = direction > 0 ? (levels.find { |z| z > zoom + 0.001 } || levels.last) : (levels.reverse.find { |z| z < zoom - 0.001 } || levels.first)
        return if next_zoom == zoom
        @zoom = next_zoom
        @overview = (zoom - minimum).abs < 0.001
        @following = false if anchor || @overview
        @x, @y = cx - sx / zoom, cy - sy / zoom
        @snap = false
        clamp
      end

      def pan(dx, dy)
        @following, @overview = false, false
        @x += dx / zoom
        @y += dy / zoom
        @ceiling = -500 if @y >= -500
        clamp
      end

      def navigate(wx, wy)
        @following = false
        @zoom = [0.7, minimum].max if overview?
        @overview = false
        @ceiling = -500
        center(wx, wy)
      end

      def update(target, dt:, velocity: nil, mode: :actor)
        return unless following && target
        tx, ty = target
        # Anticipate a flying shot without changing the simulated position. A
        # bounded lead also behaves well when a grenade bounces or reverses.
        if mode == :projectile && velocity
          tx += (velocity[0].to_f * 0.18).clamp(-150 / zoom, 150 / zoom)
          ty += (velocity[1].to_f * 0.13).clamp(-75 / zoom, 75 / zoom)
        end
        wanted_x, wanted_y = tx - VIEW_WIDTH * 0.46 / zoom, ty - VIEW_HEIGHT * 0.58 / zoom
        # A small safe area absorbs walking, hops and resting physics jitter.
        # Projectiles use tighter framing so quick flights stay in view.
        dead_x, dead_y = mode == :actor ? [95.0, 52.0] : [18.0, 12.0]
        dx, dy = wanted_x - x, wanted_y - y
        unless @snap
          dx = outside_deadzone(dx, dead_x / zoom)
          dy = outside_deadzone(dy, dead_y / zoom)
        end
        # Elapsed time, rather than a frame count, keeps 30/60/120 Hz motion
        # consistent and recovers immediately after a delayed UI frame.
        blend = @snap ? 1.0 : 1 - Math.exp(-[dt, 0].max * (mode == :actor ? 7 : 11))
        @x += dx * blend if dx.abs * zoom > 0.35
        @y += dy * blend if dy.abs * zoom > 0.35
        @snap = false
        # Retain the explored sky while returning from a high arc. A ceiling
        # derived only from today's target would clamp a falling shot (or the
        # handoff to its owner) by thousands of pixels in a single frame.
        @ceiling = [@ceiling, wanted_y, -500].min
        @ceiling = -500 if @y >= -500
        clamp
      end

      private

      def outside_deadzone(delta, radius)
        delta.positive? ? [delta - radius, 0].max : [delta + radius, 0].min
      end

      def center(wx, wy)
        @x, @y = wx - VIEW_WIDTH / (zoom * 2), wy - VIEW_HEIGHT / (zoom * 2)
        clamp
      end

      def clamp
        vw, vh = VIEW_WIDTH / zoom, VIEW_HEIGHT / zoom
        @x = width < vw ? (width - vw) / 2 : x.clamp(0, width - vw)
        # Allow upward tracking of a high ballistic arc, while the overview stays centered.
        @y = height < vh ? (height - vh) / 2 : y.clamp(@ceiling, height - vh)
      end
    end
  end
end
