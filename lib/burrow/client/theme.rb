# frozen_string_literal: true

module Burrow
  module Client
    module Theme
      INK = "#182d35"
      MUTED = "#5d6f72"
      PAPER = "#f7f2e6"
      WELL = "#eee7d7"
      PANEL = "#fffaf0"
      SLATE = "#29444c"
      WHITE = "#fffaf0"
      TEAL = "#407d80"
      ORANGE = "#f57c49"
      LINE = "#182d3529"
      GOLD = "#edc16d"
      ART = File.join(Burrow::ROOT, "assets/art")
      class << self
        attr_accessor :sans, :display, :mono
      end
      self.sans, self.display, self.mono = "Inter", "Fredoka", "Fira Mono"
    end

    module Widgets
      # Shoes treats a fractional number below 1 as a proportion of its parent.
      # Integer pixels keep a one-pixel inset from becoming an 89% inset at 1280px.
      def px(value) = (value * @scale).round

      def label(text, x, y, width, size: 16, color: Theme::INK, font: Theme.sans, **options)
        @shoes.para(text, left: px(x), top: px(y), width: px(width), size: px(size),
          font: font, stroke: color, margin: 0, **options)
      end

      def micro(text, x, y, width, color: Theme::MUTED)
        label(text, x, y, width, size: 11, color: color, font: Theme.mono)
      end

      def box(x, y, width, height, color: Theme::PAPER, radius: 12, stroke: nil)
        @shoes.rect(px(x), px(y), px(width), px(height), px(radius), fill: color,
          stroke: stroke || color, strokewidth: stroke ? px(1) : 0)
      end

      def line(x1, y1, x2, y2, color: Theme::LINE, width: 1)
        @shoes.line(px(x1), px(y1), px(x2), px(y2), stroke: color, strokewidth: px(width))
      end

      def image(name, x, y, width, height, alt: "")
        @shoes.image(File.join(Theme::ART, "#{name}.png"), left: px(x), top: px(y), width: px(width), height: px(height), alt: alt)
      end

      def button(text, x, y, width, height: 38, primary: false, selected: false, danger: false,
        size: 14, font: Theme.sans, color: nil, text_color: nil, &action)
        @shoes.button(text, left: px(x), top: px(y), width: px(width), height: px(height), size: px(size),
          font: font, color: color || (primary ? Theme::TEAL : selected ? "#d6e6dd" : Theme::WELL),
          text_color: text_color || (primary ? Theme::WHITE : danger ? "#98472f" : Theme::INK)) do
          @audio&.play("click", volume: 0.5)
          action&.call
        end
      end

      def panel(x, y, width, height, color: Theme::PANEL, radius: 14)
        box(x, y + 3, width, height, color: "#182d3510", radius: radius)
        box(x, y, width, height, color: color, radius: radius, stroke: Theme::LINE)
      end

      def short_text(text, limit)
        value = text.to_s
        value.length > limit ? value[0, limit - 1] + "…" : value
      end

      def input(text, x, y, width, secret: false, &change)
        @shoes.edit_line(text.to_s, left: px(x), top: px(y), width: px(width), height: px(38),
          font: "#{Theme.sans} #{px(15)}px", secret: secret, &change)
      end

      def select(items, selected, x, y, width, &change)
        @shoes.list_box(items: items, choose: selected, left: px(x), top: px(y), width: px(width), height: px(36),
          font: "#{Theme.sans} #{px(14)}px", &change)
      end

      def set_text(node, text)
        node.text = text if node && node.text != text
      end

      def grub(team, x, y, size: 80, state: "idle", frame: 0)
        folder = size > 80 && [["idle", 0], ["victory", 2]].include?([state, frame]) ? "grubs/portraits" : "grubs"
        image("#{folder}/#{team}-#{state}-#{frame}", x, y, size, size)
      end
    end
  end
end
