# frozen_string_literal: true

require "delegate"

module Burrow
  module Client
    # Glossy arcade panels: bright blue frames with ink outlines, navy wells,
    # cyan headings and yellow menu text, after classic artillery-game menus.
    module Theme
      INK = "#0a1d3f"
      NAVY = "#0b2350"
      DEEP = "#071731"
      WELL_EDGE = "#3d7fd0"
      BLUE = ["#4a9cf0", "#1a5cbc"].freeze
      HEADER = ["#2c74d6", "#123f8f"].freeze
      CYAN = "#5ee3ff"
      YELLOW = "#ffd335"
      TEXT = "#f4f9ff"
      MUTED = "#a9cdf5"
      WHITE = "#ffffff"
      ORANGE = "#ff8a1c"
      DIM = "#7e93b3"
      # Glossy capsule faces: top, bottom, label.
      TONES = {
        blue: ["#68b6ff", "#1d63c9", WHITE],
        yellow: ["#ffe066", "#f2a40c", "#3a2200"],
        green: ["#7ee35a", "#2f9a1d", WHITE],
        red: ["#ff7b62", "#c62a1f", WHITE],
        navy: ["#24508f", "#0f2a5a", TEXT],
        off: ["#7c8ea8", "#4c5d78", "#dfe7f2"]
      }.freeze
      OUTLINE = [[-1, -1], [1, -1], [-1, 1], [1, 1], [-1, 0], [1, 0], [0, -1], [0, 1]].freeze
      ART = File.join(Burrow::ROOT, "assets/art")
      class << self
        attr_accessor :sans, :display, :mono
      end
      self.sans, self.display, self.mono = "Inter", "Fredoka", "Fira Mono"

      def self.bold = "#{display} 700"

      # The colour halfway between two "#rrggbb[aa]" colours.
      def self.blend(from, to)
        a, b = [from, to].map { |hex| hex.delete("#").ljust(8, "f").scan(/../).map(&:hex) }
        "#" + a.zip(b).map { |x, y| ((x + y) / 2.0).round.to_s(16).rjust(2, "0") }.join
      end
    end

    # Text drawn over its own ink outline. It answers `text` like a para, so
    # HUD code can update every layer through one handle.
    class Outlined
      attr_reader :layers

      def initialize(layers, container: nil)
        @layers, @container = layers, container
      end
      def fill = layers.last
      def text = fill.text
      def hidden = (@container || fill).hidden

      def text=(value)
        layers.each { |layer| layer.text = value }
      end

      def show
        return unless hidden
        @container ? @container.show : layers.each(&:show)
      end

      def hide
        return if hidden
        @container ? @container.hide : layers.each(&:hide)
      end
    end

    # A real Shoes button (focus, keys, screen readers, `state`) with a glossy
    # capsule painted behind its bare face.
    class GlossButton < SimpleDelegator
      attr_reader :tone

      def initialize(control, body, tone, flat: false)
        super(control)
        @body, @tone, @hovered, @flat = body, tone, false, flat
        control.hover { @hovered = true; paint }
        control.leave { @hovered = false; paint }
      end

      def state=(value)
        return if state == value
        __getobj__.state = value
        paint
      end

      def tone=(value)
        return if value == @tone
        @tone = value
        __getobj__.style(text_color: Theme::TONES.fetch(value)[2])
        paint
      end

      private

      def paint
        top, bottom = Theme::TONES.fetch(state == "disabled" ? :off : tone)
        top = lighten(top) if @hovered && state != "disabled"
        fill = @flat ? Theme.blend(top, bottom) : top..bottom
        @body.style(fill: fill) unless @fill == fill
        @fill = fill
      end

      def lighten(hex) = "#" + hex.delete("#").scan(/../).map { |c| [c.hex + 26, 255].min.to_s(16).rjust(2, "0") }.join
    end

    module Widgets
      # Shoes treats a fractional number below 1 as a proportion of its parent.
      # Integer pixels keep a one-pixel inset from becoming an 89% inset at 1280px.
      def px(value) = (value * @scale).round

      # Gradients rasterize on a slower path. A match repaints the whole window
      # whenever the camera moves, so its widgets fill with the gradient's midpoint.
      def flat_ui? = @page == :match
      def shade(top, bottom) = flat_ui? ? Theme.blend(top, bottom) : top..bottom

      def label(text, x, y, width, size: 16, color: Theme::TEXT, font: Theme.sans, **options)
        @shoes.para(text, left: px(x), top: px(y), width: px(width), size: px(size),
          font: font, stroke: color, margin: 0, **options)
      end

      # Small display-face captions: section names, keys and counters.
      def micro(text, x, y, width, color: Theme::MUTED, **options)
        label(text, x, y, width, size: 12, color: color, font: Theme.display, weight: 600, **options)
      end

      # Bold display text over an ink outline, for headings and anything drawn on scenery.
      def outlined(text, x, y, width, size: 24, color: Theme::WHITE, outline: Theme::INK, thickness: 2,
        align: "left", shadow: 0, offsets: Theme::OUTLINE, **options)
        layers = []
        if shadow.positive?
          layers << label(text, x + shadow * 0.6, y + shadow, width, size: size, color: outline,
            font: Theme.display, weight: 700, align: align, **options)
        end
        offsets.each do |dx, dy|
          layers << label(text, x + dx * thickness, y + dy * thickness, width, size: size, color: outline,
            font: Theme.display, weight: 700, align: align, **options)
        end
        layers << label(text, x, y, width, size: size, color: color, font: Theme.display, weight: 700, align: align, **options)
        Outlined.new(layers)
      end

      def box(x, y, width, height, color: Theme::NAVY, radius: 12, stroke: nil, stroke_width: 1)
        @shoes.rect(px(x), px(y), px(width), px(height), px(radius), fill: color,
          stroke: stroke || color, strokewidth: stroke ? px(stroke_width) : 0)
      end

      def line(x1, y1, x2, y2, color: "#ffffff30", width: 1)
        @shoes.line(px(x1), px(y1), px(x2), px(y2), stroke: color, strokewidth: px(width))
      end

      def image(name, x, y, width, height, alt: "", **options)
        @shoes.image(File.join(Theme::ART, "#{name}.png"), left: px(x), top: px(y), width: px(width), height: px(height), alt: alt, **options)
      end

      # The glossy blue panel. A title sits in a darker inset tab across its top.
      def frame(x, y, width, height, title: nil, radius: 28, title_size: 32)
        box(x + 4, y + 10, width, height, color: "#02081866", radius: radius)
        box(x - 4, y - 4, width + 8, height + 8, color: Theme::INK, radius: radius + 4)
        box(x, y, width, height, color: shade(*Theme::BLUE), radius: radius)
        box(x + 10, y + 4, width - 20, [height * 0.22, 64].min, color: shade("#ffffff52", "#ffffff00"), radius: radius - 6)
        box(x + 2, y + 2, width - 4, height - 4, color: "#ffffff00", radius: radius - 2, stroke: "#9fd2ff66", stroke_width: 2)
        return unless title
        tab_height = title_size + 34
        box(x + 18, y + 14, width - 36, tab_height, color: shade(Theme::HEADER[1], Theme::HEADER[0]), radius: 22,
          stroke: Theme::INK, stroke_width: 2)
        box(x + 30, y + 16, width - 60, tab_height * 0.42, color: shade("#ffffff2e", "#ffffff00"), radius: 18)
        outlined(title, x + 40, y + 14 + (tab_height - title_size * 1.2) / 2, width - 80, size: title_size,
          color: Theme::CYAN, thickness: 2.5, align: "center", shadow: 3)
      end

      # A recessed navy panel inside a frame.
      def well(x, y, width, height, radius: 18, color: Theme::NAVY)
        box(x, y, width, height, color: color, radius: radius, stroke: Theme::WELL_EDGE, stroke_width: 2)
        box(x + 3, y + 3, width - 6, 14, color: "#00000040".."#00000000", radius: [radius - 3, 4].max) unless flat_ui?
      end

      # A glossy capsule button. Primary actions are yellow and destructive ones red.
      def button(text, x, y, width, height: 40, primary: false, selected: false, danger: false, tone: nil,
        size: 16, font: Theme.bold, &action)
        flat = flat_ui?
        tone ||= primary || selected ? :yellow : danger ? :red : :blue
        top, bottom, ink = Theme::TONES.fetch(tone)
        radius = [height / 2.0, 18].min
        box(x - 3, y - 3, width + 6, height + 6, color: Theme::INK, radius: radius + 3)
        body = box(x, y, width, height, color: shade(top, bottom), radius: radius)
        box(x + 8, y + 3, width - 16, height * 0.42, color: shade("#ffffff70", "#ffffff10"), radius: radius * 0.8)
        control = @shoes.button(text, left: px(x), top: px(y), width: px(width), height: px(height), size: px(size),
          font: font, color: "#00000000", text_color: ink) do
          @audio&.play("click", volume: 0.5)
          action&.call
        end
        GlossButton.new(control, body, tone, flat: flat)
      end

      # Menu text in the arcade style: yellow, turning white under the pointer.
      def menu_item(text, x, y, width, height: 44, size: 26, selected: false, color: Theme::YELLOW, &action)
        resting = selected ? Theme::WHITE : color
        control = @shoes.button(text, left: px(x), top: px(y), width: px(width), height: px(height), size: px(size),
          font: Theme.bold, color: "#00000000", text_color: resting) do
          @audio&.play("click", volume: 0.5)
          action&.call
        end
        control.hover { control.style(text_color: Theme::WHITE) unless control.state == "disabled" }
        control.leave { control.style(text_color: resting) }
        control
      end

      # The red curved back arrow on a panel's left ear, captioned for clarity.
      def back_control(x, y, text = "Back", size: 15, &action)
        box(x - 4, y - 4, 92, 104, color: Theme::INK, radius: 40)
        box(x, y, 84, 96, color: shade(*Theme::BLUE), radius: 36)
        box(x + 8, y + 3, 68, 30, color: shade("#ffffff52", "#ffffff00"), radius: 26)
        arrow = back_arrow(x + 10, y + 6, 0.64)
        arrow.click { @audio&.play("click", volume: 0.5); action&.call }
        menu_item(text, x + 2, y + 66, 80, height: 26, size: size, &action)
      end

      def back_arrow(x, y, scale)
        k = 0.5523
        at = ->(px_, py) { [px(x + px_ * scale), px(y + py * scale)] }
        arrow = @shoes.shape(stroke: "#2a0605", strokewidth: px(3 * scale), fill: shade("#ff7158", "#c21d16")) do
          @shoes.move_to(*at.(74, 56))
          @shoes.line_to(*at.(96, 56))
          @shoes.curve_to(*at.(96, 56 - 42 * k), *at.(54 + 42 * k, 14), *at.(54, 14))
          @shoes.curve_to(*at.(54 - 42 * k, 14), *at.(12, 56 - 42 * k), *at.(12, 56))
          @shoes.line_to(*at.(0, 56))
          @shoes.line_to(*at.(23, 90))
          @shoes.line_to(*at.(46, 56))
          @shoes.line_to(*at.(34, 56))
          @shoes.curve_to(*at.(34, 56 - 20 * k), *at.(54 - 20 * k, 36), *at.(54, 36))
          @shoes.curve_to(*at.(54 + 20 * k, 36), *at.(74, 56 - 20 * k), *at.(74, 56))
        end
        @shoes.shape(fill: "#ffffff00", stroke: "#ffffff70", strokewidth: px(3 * scale), cap: :curve) do
          @shoes.move_to(*at.(88, 50))
          @shoes.curve_to(*at.(86, 30), *at.(70, 20), *at.(54, 20))
        end
        arrow
      end

      def short_text(text, limit)
        value = text.to_s
        value.length > limit ? value[0, limit - 1] + "…" : value
      end

      def input(text, x, y, width, secret: false, &change)
        @shoes.edit_line(text.to_s, left: px(x), top: px(y), width: px(width), height: px(38),
          font: "#{Theme.sans} #{px(15)}px", secret: secret, fill: Theme::DEEP, border_color: Theme::WELL_EDGE,
          stroke: Theme::WHITE, &change)
      end

      def select(items, selected, x, y, width, &change)
        @shoes.list_box(items: items, choose: selected, left: px(x), top: px(y), width: px(width), height: px(36),
          font: "#{Theme.sans} #{px(14)}px", stroke: Theme::INK, &change)
      end

      # A caption over a form control, in the panels' yellow.
      def field_label(text, x, y, width, size: 16)
        label(text, x, y, width, size: size, color: Theme::YELLOW, font: Theme.display, weight: 700)
      end

      def set_text(node, text)
        node.text = text if node && node.text != text
      end

      # A Shoes write is a JSON message to the native child even when its value
      # is unchanged. Compare the retained drawable first; batch changed styles
      # into one message. Reading its public properties needs no renderer roundtrip.
      def restyle(node, **styles)
        styles.delete_if { |name, value| node.public_send(name) == value }
        node.style(**styles) unless styles.empty?
      end

      def move_to(node, left, top)
        node.move(left, top) unless node.left == left && node.top == top
      end

      def place(node, left, top, width, height)
        return if node.left == left && node.top == top && node.width == width && node.height == height
        restyle(node, left: left, top: top, width: width, height: height)
      end

      def show_if(node, visible)
        if visible
          node.show if node.hidden
        else
          node.hide unless node.hidden
        end
      end

      def grub(team, x, y, size: 80, state: "idle", frame: 0)
        folder = size > 80 && [["idle", 0], ["victory", 2]].include?([state, frame]) ? "grubs/portraits" : "grubs"
        image("#{folder}/#{team}-#{state}-#{frame}", x, y, size, size)
      end
    end
  end
end
