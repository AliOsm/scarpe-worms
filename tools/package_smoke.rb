# frozen_string_literal: true
# Runs the package's real boot and game code using only its vendored Ruby libraries.
require "json"
require "scarpe"
require "scarpe/native"
require "rbconfig"

# Preserve the packaged runtime's missing bin/ruby wrapper in the Linux
# substitution test too. Both subprocesses must use the launcher's interpreter.
RbConfig::CONFIG["bindir"] = File.join(ENV.fetch("BURROW_PACKAGE_RES"), "runtime/ruby/bin")

failed = false
at_exit { exit(1) if failed }
Scarpe::Native.after_first_heartbeat do
  begin
    auto = Scarpe::Native::DisplayService.instance.automation
    client = Shoes.APPS.first.instance_variable_get(:@burrow)
    player_name = "Pip\u00A0\u00C9quipe"
    if ENV["BURROW_SMOKE_RESUME"] == "1"
      raise "Unicode profile was not restored" unless client.preferences["name"] == player_name
      raise "Local session was not saved" unless client.preferences["sessions"]["local"]
    else
      client.preferences["name"] = player_name
    end
    auto.frames(1)
    auto.click({text: "Quick battle"})
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 18
    until client.state && client.scene.terrain_revision >= 0
      if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        raise "Packaged battle did not start: #{client.instance_variable_get(:@last_notice)}"
      end
      auto.advance(0.05)
    end
    raise "Expected three teams" unless client.state["teams"].size == 3
    raise "Unicode player name changed" unless client.state["teams"].any? { |team| team["name"] == player_name }
    # Virtual displays/CI can open a window without granting it OS focus.
    # Establish activation through native dispatch before testing held input.
    auto.window_focus(true)
    activity = client.instance_variable_get(:@activity)
    if RUBY_PLATFORM.include?("darwin")
      raise "Mac gameplay activity did not start: #{activity.report}" unless activity.active?
    end
    auto.key_down("right")
    auto.advance(0.25)
    raise "Movement input did not reach the game" unless client.instance_variable_get(:@last_input) == [1, 0]
    auto.key_up("right")
    auto.key_down(" ")
    auto.advance(0.15)
    unless client.instance_variable_get(:@charge_started)
      raise "Charging did not begin: #{ {page: client.page, phase: client.state['phase'], my_turn: client.my_turn?,
        active: client.instance_variable_get(:@window_active), keys: client.instance_variable_get(:@keys).to_a,
        notice: client.instance_variable_get(:@last_notice)} }"
    end
    auto.window_focus(false)
    raise "Background window kept its interactive activity" if activity.active?
    auto.advance(0.05)
    raise "Focus loss failed to cancel charging" if client.instance_variable_get(:@charge_started)
    raise "Focus loss fired a shot" unless client.state["phase"] == "aiming"
    auto.window_focus(true)
    auto.key_up(" ")
    auto.key("e")
    raise "Arsenal did not open" unless client.overlay?
    auto.click({text: "Close"})
    terrain_revision = client.scene.terrain_revision
    terrain_worker = client.scene.instance_variable_get(:@terrain_art)
    timeline = client.scene.timeline
    auto.resize(1440, 900)
    auto.advance(0.7)
    raise "Terrain lost on resize" unless client.scene.terrain_revision == terrain_revision
    raise "Resize replaced the terrain process" unless client.scene.instance_variable_get(:@terrain_art).equal?(terrain_worker)
    raise "Resize restarted motion playback" unless client.scene.timeline.equal?(timeline)
    auto.snapshot(ENV.fetch("BURROW_SMOKE_SHOT"))
    result = {ruby: RUBY_VERSION, platform: RUBY_PLATFORM, boot: true, teams: 3,
      version: Burrow::VERSION, match_id: client.room.fetch("match_id"), player_id: client.my_id,
      profile_name: client.preferences["name"], resumed: ENV["BURROW_SMOKE_RESUME"] == "1",
      external_encoding: Encoding.default_external.name, unicode_terrain_path: !terrain_worker.directory.ascii_only?,
      mac_activity: activity.report,
      terrain: true, arsenal: true, resize: true, movement_input: true, activation_cancels_charge: true,
      process_host: true, process_terrain: true, bundled_interpreter: ENV.fetch("BURROW_RUBY"),
      resize_reuses_terrain: true, resize_preserves_playback: true,
      headless: ENV["SCARPE_NATIVE_HEADLESS"] == "1",
      macos_execution: RUBY_PLATFORM.include?("darwin"), performance: client.scene.performance}
    File.write(ENV.fetch("BURROW_SMOKE_REPORT"), JSON.pretty_generate(result) + "\n")
    puts JSON.generate(result)
  rescue Exception => error
    failed = true
    warn "Package smoke failed: #{error.full_message}"
  ensure
    Shoes.APPS.each(&:destroy)
  end
end
load File.join(ENV.fetch("BURROW_PACKAGE_RES"), "boot.rb")
