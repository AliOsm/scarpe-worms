# frozen_string_literal: true

# Bound CPU raster work on Retina and large external displays. The Mac window
# compositor scales the finished frame; layout, mouse and world coordinates stay
# in logical pixels. Set BURROW_RENDER_PIXELS=0 for full device resolution.
ENV["SCARPE_NATIVE_MAX_RENDER_PIXELS"] ||= ENV.fetch("BURROW_RENDER_PIXELS", "1500000")

require_relative "lib/burrow"
require_relative "lib/burrow/client/app"

Burrow::Client::Theme.sans = font(File.join(Burrow::ROOT, "assets/fonts/InterVariable.ttf")).first || "Inter"
Burrow::Client::Theme.display = font(File.join(Burrow::ROOT, "assets/fonts/Fredoka.ttf")).first || "Fredoka"
Burrow::Client::Theme.mono = font(File.join(Burrow::ROOT, "assets/fonts/FiraMono-Medium.ttf")).first || "monospace"

Shoes.app(title: "Burrow Brigade", width: 1280, height: 800, min_width: 1080, min_height: 675,
  icon: File.join(Burrow::ROOT, "assets/art/app-icon.png")) do
  @burrow = Burrow::Client::App.new(self)
end
