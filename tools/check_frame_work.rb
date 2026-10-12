# frozen_string_literal: true

# Deterministic, native Scene/HUD workload (not a presentation-cadence test).
# nice -n 10 flock /tmp/burrow-bench.lock env SCARPE_DISPLAY_SERVICE=native SCARPE_NATIVE_HEADLESS=1 \
#   BURROW_FRAME_OUTPUT=.cache/frame-work ./bin/scarpe tools/check_frame_work.rb
require "scarpe"
require "scarpe/native"
source_root = File.expand_path(ENV.fetch("BURROW_BENCH_SOURCE", "."), File.expand_path("..", __dir__))
require File.join(source_root, "lib/burrow")
require File.join(source_root, "lib/burrow/client/app")
require_relative "frame_profile"

module FixtureClock
  class << self
    attr_accessor :now
  end
  def clock = FixtureClock.now || super
end
Burrow.singleton_class.prepend(FixtureClock)

FixtureTimeline = Struct.new(:state, :tick, :events) do
  def sample(now:) = state
end

out = File.expand_path(ENV.fetch("BURROW_FRAME_OUTPUT", ".cache/frame-work"), Burrow::ROOT)
FileUtils.mkdir_p(out)
FrameProfile.install
Burrow::Client::Theme.sans = font(File.join(Burrow::ROOT, "assets/fonts/InterVariable.ttf")).first
Burrow::Client::Theme.display = font(File.join(Burrow::ROOT, "assets/fonts/Fredoka.ttf")).first
players = 6.times.map { |i| {id: "p#{i}", name: Burrow::TEAM_NAMES[i], bot: false} }
match = Burrow::Match.new(players: players, config: Burrow::Config.new("worms" => 6, "seed" => "frame-work"))
state = JSON.parse(JSON.generate(match.snapshot(terrain: true)))
state["worms"].each_with_index do |worm, i|
  worm.merge!("x" => 350.0 + i % 12 * 92, "y" => 650.0 + i / 12 * 95, "vx" => 0, "vy" => 0)
end
state["hazards"] = 60.times.map { |i| {"id" => "flame-#{i}", "kind" => "flame", "x" => 320.0 + i * 20, "y" => 955.0} }
state["events"], state["projectiles"] = [], []
state.delete("motion")
client = Burrow::Client::App.allocate
{state: state, preferences: {"motion" => false}, keys: Set.new, page: :match, scale: 1,
  selected_weapon: "homing", locked_target: [1060, 760], target: [1100, 600], angle: -40.0,
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
    timeline = FixtureTimeline.new(state, 600.0, [])
    scene.instance_variable_set(:@timeline, timeline)
    scene.camera.navigate(850, 740)
    FixtureClock.now = 100.0
    20.times { scene.render }
    client.refresh_match_hud
    auto.snapshot(File.join(out, "static.png"))
    if ENV["BURROW_FRAME_ALLOCATIONS"] == "1"
      # Trace a single warmed frame separately: allocation tracing changes cost
      # substantially and must not contaminate the measured frame distributions.
      was_disabled = GC.disable
      ObjectSpace.trace_object_allocations_start
      scene.render
      ObjectSpace.trace_object_allocations_stop
      sites = Hash.new(0)
      ObjectSpace.each_object do |object|
        file = ObjectSpace.allocation_sourcefile(object)
        next unless file
        sites[[file.delete_prefix(Burrow::ROOT + "/"), ObjectSpace.allocation_sourceline(object), object.class.name]] += 1
      end
      File.write(File.join(out, "allocation-sites.json"), JSON.pretty_generate(sites.sort_by { |_site, count| -count }))
      ObjectSpace.trace_object_allocations_clear
      GC.enable unless was_disabled
    end
    %w[static flames pan zoom].each do |name|
      client.preferences["motion"] = name != "static"
      GC.start
      FrameProfile.start(name)
      360.times do |i|
        FixtureClock.now = 100 + i / 60.0
        timeline.tick = 600 + i * 0.5
        scene.camera.pan(i < 180 ? 2 : -2, 0) if name == "pan"
        scene.camera.zoom_by(i < 180 ? -1 : 1) if name == "zoom" && i % 60 == 0
        scene.render
        client.refresh_match_hud if i % 6 == 0
        service.child.flush
      end
      FrameProfile.finish
      auto.snapshot(File.join(out, "#{name}.png"))
    end
    File.write(File.join(out, "profile.json"), JSON.generate(FrameProfile.report))
    raise "Native callback failed" if service.instance_variable_get(:@handler_errors)&.any?
  rescue Exception => error
    failed = true
    warn error.full_message
  ensure
    FixtureClock.now = nil
    client.scene&.close
    Shoes.APPS.each(&:destroy)
  end
end
at_exit { exit(1) if failed }
Shoes.app(title: "Ruby frame workload", width: 1440, height: 900) do
  client.instance_variable_set(:@shoes, self)
  client.draw_match
end
