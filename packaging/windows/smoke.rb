# frozen_string_literal: true
# Injected by the Windows verifier before the packaged game's normal startup.
require "scarpe/native"

# A detached console Ruby can still allocate consoles for its own children.
# That console's code page then overrides the UTF-8 manifest at Ruby startup.
# Exercise the exact worker spawn shape with characters outside cp1252.
require "tmpdir"
worker_startup = Dir.mktmpdir("burrow-worker-probe-") do |directory|
  script = File.join(directory, "Worker Équipe 雪 برج.rb")
  File.write(script, <<~'RUBY', encoding: "UTF-8")
    require "json"
    require "fiddle"
    kernel = Fiddle.dlopen("kernel32.dll")
    console = Fiddle::Function.new(kernel["GetConsoleWindow"], [], Fiddle::TYPE_VOIDP).call.to_i
    puts JSON.generate(argv: ARGV, external: Encoding.default_external.name,
      locale: Encoding.find("locale").name, console: console)
  RUBY
  command = [ENV.fetch("BURROW_RUBY"), "-EUTF-8", "-I", $LOAD_PATH.map(&:b).join(File::PATH_SEPARATOR), script, "雪 برج Équipe"]
  output = IO.popen(command, "r:UTF-8", &:read)
  raise "Bundled worker failed to start from a Unicode path" unless $?.success?
  result = JSON.parse(output)
  raise "Worker startup damaged Unicode" unless result.values_at("argv", "external", "locale", "console") == [["雪 برج Équipe"], "UTF-8", "UTF-8", 0]
  result
end

failed = false
at_exit { exit(1) if failed }
Scarpe::Native.after_first_heartbeat do
  begin
    auto = Scarpe::Native::DisplayService.instance.automation
    client = Shoes.APPS.first.instance_variable_get(:@burrow)
    wait_for = lambda do |message, &condition|
      deadline = Burrow.clock + 45
      until condition.call
        raise "#{message}: #{client.instance_variable_get(:@last_notice)}" if Burrow.clock > deadline
        auto.advance(0.05)
      end
    end
    raise "Did not reach the menu" unless client.page == :menu
    player = "Pip Équipe"
    resumed = ENV["BURROW_SMOKE_RESUME"] == "1"
    if resumed
      raise "Unicode profile was not saved" unless client.preferences["name"] == player
      raise "Local session was not saved" unless client.preferences["sessions"]["local"]
    else
      client.preferences["name"] = player
    end
    auto.click({text: "Quick battle"})
    wait_for.call("Match/terrain failed to start") { client.state && client.scene.terrain_revision >= 0 }
    raise "Expected two bot opponents" unless client.state["teams"].size == 3
    raise "Unicode name changed" unless client.state["teams"].any? { |team| team["name"] == player }
    terrain_worker = client.scene.instance_variable_get(:@terrain_art)
    raise "Terrain did not use Unicode paths" if terrain_worker.directory.ascii_only?
    raise "Terrain worker failed: #{terrain_worker.error}" if terrain_worker.error
    auto.window_focus(true)
    auto.key("e")
    raise "Arsenal did not open" unless client.overlay?
    auto.click({text: "Back"})
    timeline = client.scene.timeline
    auto.resize(1440, 900)
    auto.advance(0.6)
    wait_for.call("Terrain missing after resize") { client.scene.terrain_revision == client.state["terrain_revision"] }
    raise "Resize restarted terrain worker" unless client.scene.instance_variable_get(:@terrain_art).equal?(terrain_worker)
    raise "Resize restarted playback" unless client.scene.timeline.equal?(timeline)

    fired = false
    unless resumed
      wait_for.call("Human turn never became ready") { client.my_turn? && client.state["phase"] == "aiming" }
      auto.key_down("right")
      auto.advance(0.1)
      raise "Movement input was lost" unless client.instance_variable_get(:@last_input) == [1, 0]
      auto.key_up("right")
      auto.key_down(" ")
      auto.advance(0.1)
      raise "Charging did not begin" unless client.instance_variable_get(:@charge_started)
      auto.window_focus(false)
      auto.advance(0.05)
      raise "Focus loss did not cancel charge" if client.instance_variable_get(:@charge_started)
      raise "Focus loss fired a shot" unless client.state["phase"] == "aiming"
      auto.key_up(" ")
      auto.window_focus(true)
      auto.key_down(" ")
      auto.advance(0.3)
      auto.key_up(" ")
      wait_for.call("Shot never reached presentation") do
        fired = client.scene.presented && client.scene.presented["projectiles"].any?
      end
    end
    auto.snapshot(ENV.fetch("BURROW_SMOKE_SHOT"))

    # A runner has no physical output. The actual dynamically loaded OpenAL
    # Soft DLL mixes through its null driver, with all cues decoded and 12 voices.
    audio = client.instance_variable_get(:@audio)
    unless ENV["SCARPE_NATIVE_HEADLESS"] == "1"
      raise "Bundled audio failed: #{audio.error}" unless audio.available
      raise "Cue preload incomplete" unless audio.instance_variable_get(:@buffers).size == Burrow::Client::Audio::CUES.size
      raise "Effect voice count changed" unless audio.instance_variable_get(:@sources).size == 13
      12.times { audio.play("explosion", throttle: false) }
    end
    hosts = client.instance_variable_get(:@local_servers).values.map { |entry| entry[:server].pid }
    renderer = Scarpe::Native::DisplayService.instance.child.instance_variable_get(:@pid)
    window = nil
    unless ENV["SCARPE_NATIVE_HEADLESS"] == "1"
      require "fiddle"
      user32 = Fiddle.dlopen("user32.dll")
      kernel32 = Fiddle.dlopen("kernel32.dll")
      int, ptr = Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP
      function = ->(name, arguments, result = int) { Fiddle::Function.new(user32[name], arguments, result) }
      visible = function.call("IsWindowVisible", [ptr])
      owner = function.call("GetWindowThreadProcessId", [ptr, ptr])
      title = function.call("GetWindowTextW", [ptr, ptr, int])
      klass = function.call("GetClassNameW", [ptr, ptr, int])
      style = function.call("GetWindowLongPtrW", [ptr, int], ptr)
      owned_by = function.call("GetWindow", [ptr, int], ptr)
      message = function.call("SendMessageW", [ptr, int, ptr, ptr], ptr)
      dpi = function.call("GetDpiForWindow", [ptr])
      windows = []
      callback = Fiddle::Closure::BlockCaller.new(int, [ptr, ptr]) do |handle, _|
        pid = Fiddle::Pointer.malloc(4)
        owner.call(handle, pid)
        if pid[0, 4].unpack1("L") == renderer && visible.call(handle) != 0
          strings = [title, klass].map do |query|
            buffer = Fiddle::Pointer.malloc(1024)
            length = query.call(handle, buffer, 512)
            buffer[0, length * 2].force_encoding("UTF-16LE").encode("UTF-8")
          end
          windows << {handle: handle.to_i, title: strings[0], class: strings[1],
            extended_style: style.call(handle, -20).to_i, owner: owned_by.call(handle, 4).to_i}
        end
        1
      end
      function.call("EnumWindows", [ptr, ptr]).call(callback, nil)
      # Windows can enumerate auxiliary IME/accessibility windows for a renderer.
      # Taskbar entries are unowned application windows, excluding tool windows.
      taskbar = windows.reject { |entry| entry[:owner] != 0 || entry[:extended_style] & 0x80 != 0 || entry[:title].empty? }
      raise "Expected one visible game/taskbar window: #{windows.inspect}" unless taskbar.size == 1 && taskbar.first[:title] == "Burrow Brigade"
      handle = taskbar.first[:handle]
      small = message.call(handle, 0x7f, 2, 0).to_i # WM_GETICON / ICON_SMALL2
      big = message.call(handle, 0x7f, 1, 0).to_i
      raise "Missing game/window/taskbar icon" if small.zero? || big.zero?
      console = Fiddle::Function.new(kernel32["GetConsoleWindow"], [], ptr).call.to_i
      raise "GUI Ruby inherited a console window" unless console.zero?
      window = {visible_game_windows: taskbar.size, enumerated_windows: windows, small_icon: true,
        taskbar_icon: true, dpi: dpi.call(handle), console: false}
    end
    result = {
      version: Burrow::VERSION, ruby: RUBY_VERSION, platform: RUBY_PLATFORM,
      resumed: resumed, menu: true, teams: 3, terrain: true, fired_shot_visible: fired,
      match_id: client.room.fetch("match_id"), player_id: client.my_id,
      resize_preserves_terrain_and_playback: true, arsenal: true,
      focus_cancels_charge: !resumed, unicode_profile: true, unicode_terrain_path: true,
      headless: ENV["SCARPE_NATIVE_HEADLESS"] == "1", openal_available: audio.available,
      decoded_cues: audio.instance_variable_get(:@buffers).size,
      effect_voices: Burrow::Client::Audio::MAX_VOICES,
      window: window,
      bundled_interpreter: ENV.fetch("BURROW_RUBY"), external_encoding: Encoding.default_external.name,
      worker_startup: worker_startup,
      child_pids: [Process.pid, renderer, *hosts, terrain_worker.instance_variable_get(:@pid)].compact,
    }
    File.write(ENV.fetch("BURROW_WINDOWS_REPORT"), JSON.pretty_generate(result) + "\n")
    puts JSON.generate(result)
  rescue Exception => error
    failed = true
    warn "Windows package smoke failed: #{error.full_message}"
  ensure
    Shoes.APPS.each(&:destroy)
  end
end
