# frozen_string_literal: true
# SCARPE_DISPLAY_SERVICE=native SCARPE_NATIVE_HEADLESS=1 ./bin/scarpe tools/check_cadence.rb
# Separates normal timer delivery from the soak driver's synchronous screenshots,
# UI interactions, forced headless paints, resizes, and rematch construction.
require "tmpdir"
require_relative "../lib/burrow"
directory = Dir.mktmpdir("burrow-cadence-")
ENV["BURROW_DATA_DIR"] = directory
ENV["BURROW_MUTE"] = "1"
ENV.delete("BURROW_CONNECT")
ENV.delete("BURROW_AUTOPLAY")
require_relative "../lib/burrow/client/app"
failed = false
intervals, preparation = [], []
last_at = nil
Burrow::Client::App.prepend(Module.new do
  define_method(:update) do
    at = Burrow.clock
    intervals << (at - last_at) * 1000 if last_at
    last_at = at
    super()
  end
end)
Burrow::Client::Scene.prepend(Module.new do
  define_method(:render) do
    at = Burrow.clock
    super()
    preparation << (Burrow.clock - at) * 1000
  end
end)
at_exit { FileUtils.remove_entry(directory) if File.directory?(directory); exit(1) if failed }
Scarpe::Native.after_first_heartbeat do
  begin
    auto = Scarpe::Native::DisplayService.instance.automation
    client = Shoes.APPS.first.instance_variable_get(:@burrow)
    wait = lambda do |&condition|
      deadline = Burrow.clock + 15
      until condition.call
        raise "Cadence setup timed out" if Burrow.clock > deadline
        auto.advance(0.05)
      end
    end
    auto.click({text: "Create a match"})
    wait.call { client.page == :lobby }
    client.action("configure", config: client.room["config"].merge("worms" => 6, "turn_seconds" => 90, "seed" => "copper-harbor"))
    4.times { client.action("add_bot") }
    wait.call { client.room["members"].size == 6 && client.room.dig("config", "worms") == 6 }
    auto.click({text: "Start the mischief"})
    wait.call { client.scene && client.scene.terrain_revision >= 0 }
    auto.advance(2)
    out = File.join(Burrow::ROOT, "docs/evidence")
    auto.resize(1440, 900)
    wait.call { client.scene && client.scene.terrain_revision >= 0 && client.instance_variable_get(:@dimensions) == [1440, 900] }
    auto.key("g")
    auto.advance(1)
    raise "Map shortcut failed" unless client.scene.camera.overview?
    auto.snapshot(File.join(out, "large-map-overview.png"))
    auto.key("f")
    auto.advance(1)
    auto.snapshot(File.join(out, "large-map-close.png"))
    [["glacier", "archipelago", "polar-bridges"], ["desert", "islands", "amber-canyons"], ["volcano", "cavern", "ember-vaults"]].each do |biome, shape, seed|
      config = client.room["config"].merge("biome" => biome, "terrain" => shape, "seed" => seed)
      client.action("leave")
      wait.call { client.room.nil? }
      client.action("create", name: "Map gallery", bots: 5, config: config)
      wait.call { client.room && client.room["members"].size == 6 }
      client.action("start")
      wait.call { client.page == :match && client.scene.terrain_revision >= 0 }
      auto.key("g")
      auto.advance(0.5)
      auto.snapshot(File.join(out, "large-#{biome}-#{shape}.png"))
    end
    puts JSON.generate({world: [client.state["world_width"], client.state["world_height"]], grubs: client.scene.actors.size})
  rescue Exception => error
    failed = true
    warn error.full_message
  ensure
    Shoes.APPS.each(&:destroy)
  end
end
load File.join(Burrow::ROOT, "game.rb")
