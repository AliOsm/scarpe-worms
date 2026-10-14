# frozen_string_literal: true

abort "Packaged Ruby must be 4.0.7" unless RUBY_VERSION == "4.0.7"
# The delivered launcher's --smoke entry uses only bundled libraries/binaries.
require "json"
require "scarpe"
require "scarpe/native"

failed = false
at_exit { exit(1) if failed }
Scarpe::Native.after_first_heartbeat do
  begin
    auto = Scarpe::Native::DisplayService.instance.automation
    client = Shoes.APPS.first.instance_variable_get(:@burrow)
    raise "Menu was not reached" unless client.page == :menu
    resume = ENV["BURROW_SMOKE_RESUME"] == "1"
    name = "Pip\u00a0Équipe"
    if resume
      raise "Profile was not restored" unless client.preferences["name"] == name
      raise "Local session was not saved" unless client.preferences["sessions"]["local"]
    else
      client.preferences["name"] = name
    end
    wait_for = lambda do |message, &predicate|
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 30
      until predicate.call
        raise "#{message}: #{client.instance_variable_get(:@last_notice)}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        auto.advance(0.05)
      end
    end
    auto.frames(1)
    auto.snapshot(ENV.fetch("BURROW_SMOKE_SHOT").sub(".png", "-menu.png"))
    auto.click({text: "Quick battle"})
    wait_for.call("Battle/terrain did not start") { client.state && client.scene.terrain_revision >= 0 }
    raise "Expected two computer teams" unless client.state["teams"].count { |team| team["bot"] } == 2
    raise "Unicode name changed" unless client.state["teams"].any? { |team| team["name"] == name }
    terrain = client.scene.instance_variable_get(:@terrain_art)
    host = client.instance_variable_get(:@local_server)
    pids = {host: host.pid, terrain: terrain.instance_variable_get(:@pid)}
    pids.each do |kind, pid|
      raise "#{kind} didn't use bundled Ruby" unless File.identical?("/proc/#{pid}/exe", ENV.fetch("BURROW_RUBY"))
    end
    original_terrain = terrain
    original_timeline = client.scene.timeline
    auto.window_focus(true)
    shot = false
    unless resume
      wait_for.call("Human turn did not start") { client.my_turn? && client.state["phase"] == "aiming" }
      auto.key_down("right")
      auto.advance(0.1)
      raise "Movement input did not reach game" unless client.instance_variable_get(:@last_input) == [1, 0]
      auto.key_up("right")
      auto.key_down(" ")
      auto.advance(0.15)
      raise "Charge did not begin" unless client.instance_variable_get(:@charge_started)
      auto.window_focus(false)
      auto.advance(0.05)
      raise "Focus loss kept charge" if client.instance_variable_get(:@charge_started)
      raise "Focus loss fired" unless client.state["phase"] == "aiming"
      auto.window_focus(true)
      auto.key_up(" ")
      auto.key("e")
      raise "Arsenal did not open" unless client.overlay?
      auto.click({text: "Back"})
      # A fused grenade persists long enough to observe the actual renderer
      # even when a random map puts the active grub directly against a wall.
      raise "Could not equip grenade" unless client.equip_weapon("grenade")
      auto.key_down(" ")
      auto.advance(0.5)
      auto.key_up(" ")
      wait_for.call("Shot was not presented") do
        shot = client.scene.instance_variable_get(:@projectile_nodes).any?
      end
      auto.snapshot(ENV.fetch("BURROW_SMOKE_SHOT").sub(".png", "-shot.png"))
    end
    auto.resize(1440, 900)
    wait_for.call("Terrain lost after resize") do
      client.scene.terrain_revision >= 0 && client.scene.terrain_revision == client.state["terrain_revision"]
    end
    raise "Resize replaced terrain process" unless client.scene.instance_variable_get(:@terrain_art).equal?(original_terrain)
    raise "Resize restarted playback" unless client.scene.timeline.equal?(original_timeline)
    audio = client.instance_variable_get(:@audio)
    audio_cues = 0
    if ENV["SCARPE_NATIVE_HEADLESS"] != "1"
      raise "Packaged OpenAL failed: #{audio.error}" unless audio.available
      al = audio.instance_variable_get(:@al)
      al.attach_function :alGetError, [], :int
      Burrow::Client::Audio::CUES.each do |cue|
        raise "Audio cue was not submitted: #{cue}" unless audio.play(cue, throttle: false)
        auto.advance(0.03)
        audio_cues += 1
      end
      raise "OpenAL rejected audio" unless al.alGetError.zero?
      maps = File.read("/proc/self/maps")
      raise "System OpenAL was used" unless maps.b.include?(File.expand_path("../lib/libopenal.so.1", __dir__).b)
    end
    # Let presentation/diagnostics collect some actual frames on resume too.
    auto.advance(0.3)
    auto.snapshot(ENV.fetch("BURROW_SMOKE_SHOT"))
    report = {ruby: RUBY_VERSION, platform: RUBY_PLATFORM, version: Burrow::VERSION,
      menu: true, terrain: true, teams: 3, bots: 2, shot_presented: shot,
      resumed: resume, match_id: client.room.fetch("match_id"), player_id: client.my_id,
      profile_name: name, headless: ENV["SCARPE_NATIVE_HEADLESS"] == "1",
      bundled_interpreter: ENV.fetch("BURROW_RUBY"), subprocesses: pids,
      bundled_host_and_terrain: true, unicode_terrain_path: !terrain.directory.ascii_only?,
      resize_reuses_terrain: true, resize_preserves_playback: true,
      openal: audio.available, audio_cues: audio_cues, external_encoding: Encoding.default_external.name}
    File.write(ENV.fetch("BURROW_SMOKE_REPORT"), JSON.pretty_generate(report) + "\n")
    puts JSON.generate(report)
  rescue Exception => error
    failed = true
    # Backtrace filenames retain filesystem encodings under a C locale.
    warn "Linux package smoke failed: #{error.class}: #{error.message.b.force_encoding(Encoding::UTF_8).scrub}"
    warn error.backtrace.map { |line| line.b.force_encoding(Encoding::UTF_8).scrub }.join("\n")
  ensure
    Shoes.APPS.each(&:destroy)
  end
end
load File.join(__dir__, "boot.rb")
