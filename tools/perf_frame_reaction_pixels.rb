# frozen_string_literal: true

# Correctness-only extension of perf_frame_reactions.rb. Use the same native
# headless command, BURROW_BENCH_SOURCE and BURROW_FRAME_OUTPUT. Captures 21
# extra frames during damage, tumbling, pops, caption reuse and zoom changes.
# Separating the second blast lets the rate-limited BYE BYE caption appear.
# Ignore this run's profile times: synchronous screenshots interrupt rendering.
require "scarpe"
require "scarpe/native"
source_root = File.expand_path(ENV.fetch("BURROW_BENCH_SOURCE", "."), File.expand_path("..", __dir__))
require File.join(source_root, "lib/burrow")
require File.join(source_root, "lib/burrow/client/app")

module ReactionPixelsTimeline
  def prepare(frame)
    super
    cycle, local = frame.divmod(300)
    @events.clear if local == 42
    if local == 72
      @events << {"id" => 130 + cycle * 1000, "kind" => "explosion", "style" => "mega_bomb",
        "x" => 1060.0, "y" => 740.0, "radius" => 96.0}
    end
  end
end

# The base fixture defines this class when loaded below. Prepending first keeps
# the normal benchmark untouched and gives this journey its own event schedule.
class ReactionFixtureTimeline
  prepend ReactionPixelsTimeline
end

module ReactionPixelsScene
  FRAMES = [15, 16, 37, 52, 72, 84, 100].freeze

  def render
    if defined?(ReactionFixtureClock) && ReactionFixtureClock.now && @timeline.is_a?(ReactionFixtureTimeline)
      frame = ((ReactionFixtureClock.now - 100) * 60).round
      @reaction_pixel_seen ||= {}
      if !@reaction_pixel_seen[frame] && [300, 600].include?(frame)
        camera.zoom_by(frame == 300 ? -1 : 1)
      end
    end
    result = super
    if frame && !@reaction_pixel_seen[frame]
      @reaction_pixel_seen[frame] = true
      if FRAMES.include?(frame % 300)
        output = File.expand_path(ENV.fetch("BURROW_FRAME_OUTPUT", ".cache/frame-reaction-pixels"), Burrow::ROOT)
        Scarpe::Native::DisplayService.instance.automation.snapshot(File.join(output, "frame-%03d.png" % frame))
      end
    end
    result
  end
end

Burrow::Client::Scene.prepend(ReactionPixelsScene)
ENV["BURROW_FRAME_OUTPUT"] ||= File.join(Burrow::ROOT, ".cache/frame-reaction-pixels")
at_exit do
  path = File.join(ENV.fetch("BURROW_FRAME_OUTPUT"), "profile.json")
  if File.file?(path)
    report = JSON.parse(File.read(path))
    report.merge!("fixture" => "frame-reaction-pixels-v1", "timing_usable" => false)
    File.write(path, JSON.generate(report))
  end
end
require_relative "perf_frame_reactions"
