# frozen_string_literal: true

# Deterministic reaction-heavy native workload for the frame optimization round.
# It replays a multi-kill blast, three deaths/poofs, a drowning, dizzy/tumble
# overlays and lingering effects through the real Scene/Scarpe boundary. Run
# with BURROW_BENCH_SOURCE pointing at the frozen tree to compare source arms:
#   PERF_AGENT=frame TMPDIR=... bench mise exec ruby@4.0.7 -- env \
#     SCARPE_DISPLAY_SERVICE=native SCARPE_NATIVE_HEADLESS=1 bundle exec \
#     ./bin/scarpe tools/perf_frame_reactions.rb
# Output is a profile JSON plus six screenshots under BURROW_FRAME_OUTPUT.
# v2: three volleys, wounded survivors actually tumble then settle, with no
# network or host simulation. Timings measure Ruby preparation, not scanout.
require "fileutils"
require "json"
require "scarpe"
require "scarpe/native"

source_root = File.expand_path(ENV.fetch("BURROW_BENCH_SOURCE", "."), File.expand_path("..", __dir__))
require File.join(source_root, "lib/burrow")
require File.join(source_root, "lib/burrow/client/app")
require_relative "frame_profile"

module ReactionFixtureClock
  class << self
    attr_accessor :now
  end
  def clock = ReactionFixtureClock.now || super
end
Burrow.singleton_class.prepend(ReactionFixtureClock)

class ReactionFixtureTimeline
  attr_accessor :tick, :events
  attr_reader :state

  def initialize(state)
    @state, @tick, @events = state, 600.0, []
  end

  def sample(now:)
    @state
  end

  def prepare(frame)
    @events = []
    cycle, local = frame.divmod(300)
    victims = cycle.zero? ? [3, 4, 5] : cycle == 1 ? [12, 13, 14] : [24, 25, 26]
    # A blast damages six grubs, then defeat and splash reports arrive on the
    # next presentation frame. This isolates the dying/sinking presentation;
    # packet cadence and simulation are outside this fixture.
    if local == 15
      @events << {"id" => 100, "kind" => "explosion", "style" => "mega_bomb", "x" => 780.0, "y" => 720.0, "radius" => 112.0}
      (victims + [0, 1, 2]).each do |i|
        worm = @state["worms"][i]
        @events << {"id" => 101 + i, "kind" => "damage", "worm" => worm["id"], "amount" => 55,
          "x" => worm["x"], "y" => worm["y"] - 18}
        worm["vx"], worm["vy"] = (i.even? ? 150.0 : -150.0), -180.0
        worm["hp"] = 20 if i < 3
      end
    elsif local == 16
      victims.each do |i|
        worm = @state["worms"][i]
        worm["hp"] = 0
        @events << {"id" => 110 + i, "kind" => "defeat", "worm" => worm["id"], "x" => worm["x"], "y" => worm["y"]}
      end
      drowned = @state["worms"][[6, 18, 30][cycle]]
      drowned["hp"] = 0
      drowned["y"] = @state["water"] - 4
      @events << {"id" => 120, "kind" => "splash", "worm" => drowned["id"], "x" => drowned["x"], "y" => drowned["y"]}
    elsif local == 42
      @events << {"id" => 130, "kind" => "explosion", "style" => "mega_bomb", "x" => 1060.0, "y" => 740.0, "radius" => 96.0}
    elsif local == 84
      drowned = @state["worms"][[7, 19, 31][cycle]]
      drowned["hp"], drowned["y"] = 0, @state["water"] - 8
      @events << {"id" => 131, "kind" => "splash", "worm" => drowned["id"],
        "x" => drowned["x"], "y" => drowned["y"]}
    end
    # Retain flight velocities long enough to exercise tumble and overlays,
    # then settle them. World positions are deliberately fixed in this fixture.
    if local == 100
      @state["worms"].first(3).each { |worm| worm["vx"] = worm["vy"] = 0.0 }
    end
    @events.each { |event| event["id"] += cycle * 1000 }
    @tick = 600.0 + frame * 0.5
  end
end

out = File.expand_path(ENV.fetch("BURROW_FRAME_OUTPUT", ".cache/frame-reactions"), Burrow::ROOT)
FileUtils.mkdir_p(out)
FrameProfile.install
Burrow::Client::Theme.sans = font(File.join(Burrow::ROOT, "assets/fonts/InterVariable.ttf")).first
Burrow::Client::Theme.display = font(File.join(Burrow::ROOT, "assets/fonts/Fredoka.ttf")).first
players = 6.times.map { |i| {id: "p#{i}", name: Burrow::TEAM_NAMES[i], bot: false} }
match = Burrow::Match.new(players: players, config: Burrow::Config.new("worms" => 6, "seed" => "frame-reactions"))
state = JSON.parse(JSON.generate(match.snapshot(terrain: true)))
state["worms"].each_with_index do |worm, i|
  worm.merge!("x" => 350.0 + i % 12 * 92, "y" => 620.0 + i / 12 * 95, "vx" => 0.0, "vy" => 0.0,
    "facing" => i.even? ? 1 : -1)
end
state["worms"][3, 5].each { |worm| worm["hp"] = 80 }
state["hazards"] = 60.times.map { |i| {"id" => "flame-#{i}", "kind" => "flame", "x" => 320.0 + i * 20, "y" => 955.0} }
state["events"], state["projectiles"] = [], []
state.delete("motion")

client = Burrow::Client::App.allocate
{state: state, preferences: {"motion" => true}, keys: Set.new, page: :match, scale: 1,
  selected_weapon: "mega_bomb", locked_target: [1060, 760], target: [1100, 600], angle: -40.0,
  power: 0.65, fuse: 3, rtt: 0, connection_status: "online", window_active: true}.each do |key, value|
  client.instance_variable_set("@#{key}", value)
end
def client.my_id = "p0"
def client.notify(message) = raise(message)
def client.play_event(_event); end

failed = false
Scarpe::Native.after_first_heartbeat do
  begin
    service = Scarpe::Native::DisplayService.instance
    auto, scene = service.automation, client.scene
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 20
    until scene.terrain_revision >= 0
      raise "Terrain fixture timed out" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      scene.render
      auto.advance(0.02)
    end
    timeline = ReactionFixtureTimeline.new(state)
    scene.instance_variable_set(:@timeline, timeline)
    scene.camera.navigate(850, 740)
    ReactionFixtureClock.now = 100.0
    12.times do |i|
      ReactionFixtureClock.now = 100 + i / 60.0
      timeline.prepare(i)
      scene.render
    end
    auto.snapshot(File.join(out, "before.png"))
    {"burst" => 12...60, "settle" => 60...120, "replay" => 120...300,
      "warm_burst" => 300...600, "warm_repeat" => 600...900}.each do |name, frames|
      GC.start
      FrameProfile.start(name)
      frames.each do |i|
        ReactionFixtureClock.now = 100 + i / 60.0
        timeline.prepare(i)
        scene.render
        service.child.flush
      end
      FrameProfile.finish
      auto.snapshot(File.join(out, "#{name}.png"))
    end
    File.write(File.join(out, "profile.json"), JSON.generate(FrameProfile.report.merge(
      fixture: "frame-reactions-v2", ruby: RUBY_VERSION, platform: RUBY_PLATFORM, source: source_root)))
    raise "Native callback failed" if service.instance_variable_get(:@handler_errors)&.any?
  rescue Exception => error
    failed = true
    warn error.full_message
  ensure
    ReactionFixtureClock.now = nil
    client.scene&.close
    Shoes.APPS.each(&:destroy)
  end
end
at_exit { exit(1) if failed }
Shoes.app(title: "Ruby reaction frame workload", width: 1440, height: 900) do
  client.instance_variable_set(:@shoes, self)
  client.draw_match
end
