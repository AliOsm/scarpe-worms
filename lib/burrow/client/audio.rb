# frozen_string_literal: true

require_relative "diagnostics"

module Burrow
  module Client
    # One native OpenAL context mixes all voices in process. No per-effect subprocesses.
    class Audio
      # Twenty-four voices removed cut-offs in busy blasts, but on a GitHub Apple
      # silicon runner they slowed zoom rendering in every capture (Apple's
      # OpenAL mixer), so effects keep twelve until cheaper mixing is measured.
      MAX_VOICES = 12
      ROOT = File.join(Burrow::ROOT, "assets/audio")
      CUES = %w[ann-fight ann-flawless-victory ann-its-a-tie ann-multi-kill ann-sudden-death
        baa beam blub boing bomb-whistle bonk bounce choir clank click close equip error
        explosion explosion-heavy fuse hurt ice impact jump launch moo music open pfft
        pickup plane poof pop pow sad-trombone shot slide-whistle-down slide-whistle-up
        splash squeak-byebye squeak-eek squeak-giggle squeak-oof squeak-ow squeak-wah
        squeak-yay squeak-yelp teleport throw thud thwip tick turn victory
        vo-cover-me-f vo-cover-me-m vo-fire-in-the-hole-f vo-fire-in-the-hole-m
        vo-get-down-f vo-get-down-m vo-go-go-go-f vo-go-go-go-m vo-hurry-up-f vo-hurry-up-m
        vo-look-out-f vo-look-out-m vo-medic-f vo-medic-m vo-target-destroyed-f
        vo-target-destroyed-m vo-watch-my-back-f vo-watch-my-back-m vo-you-win-f
        vo-you-win-m whoosh].freeze
      EVENT_CUES = {"jump" => "jump",
        "splash" => "splash", "turn" => "turn", "pickup" => "pickup", "heal" => "pickup",
        "victory" => "victory", "teleport" => "teleport", "dig" => "impact", "turret_shot" => "shot",
        "hazard_place" => "equip", "mine_arm" => "tick", "mine_trigger" => "tick",
        "barrel_rupture" => "impact", "quake" => "explosion-heavy", "rope_hook" => "thwip",
        "freeze" => "ice"}.freeze
      # Each team colour has its own voice: Kenney's soldier lines recorded at
      # speaking pitch, played faster so grubs sound like squeaky little troops.
      VOICES = [["m", 1.45], ["f", 1.3], ["m", 1.62], ["f", 1.42], ["m", 1.3], ["f", 1.55]].freeze
      SQUEAK_PITCH = [1.0, 1.12, 0.9, 1.06, 0.84, 1.18].freeze
      # Matches Scene::DYING: the grub swells for this long, then pops into its grave.
      DYING = 0.6
      QUEUE_LIMIT = 24
      attr_reader :available, :error, :timing

      # RIFF allows ancillary chunks between fmt and data. Read the chunk table
      # instead of assuming one particular WAV encoder's fixed 44-byte header.
      def self.decode_wave(wav)
        raise "Invalid PCM audio" unless wav.bytesize >= 12 && wav.start_with?("RIFF") && wav[8, 4] == "WAVE"
        limit = wav[4, 4].unpack1("V") + 8
        raise "Truncated PCM audio" unless limit.between?(12, wav.bytesize)
        offset = 12
        format = pcm = nil
        while offset + 8 <= limit
          name, length = wav[offset, 4], wav[offset + 4, 4].unpack1("V")
          first = offset + 8
          raise "Truncated WAV chunk" if first + length > limit
          if name == "fmt "
            raise "Incomplete WAV format" if length < 16
            format = wav[first, 16].unpack("vvVVvv")
          elsif name == "data"
            pcm = wav.byteslice(first, length)
          end
          offset = first + length + (length & 1)
        end
        raise "Missing PCM format or samples" unless format && pcm && !pcm.empty?
        encoding, channels, rate, byte_rate, align, bits = format
        unless encoding == 1 && [1, 2].include?(channels) && bits == 16 &&
            rate.between?(8_000, 96_000) && align == channels * 2 && byte_rate == rate * align && pcm.bytesize % align == 0
          raise "Unsupported PCM format"
        end
        {channels: channels, rate: rate, pcm: pcm}
      end

      def initialize(preferences)
        @preferences = preferences
        log = Diagnostics::AudioLog.new
        @timing = log if log.enabled?
        @timing.device = {backend: RUBY_PLATFORM.include?("darwin") ? "Apple OpenAL.framework" : "system OpenAL",
          status: "disabled", effect_voices: MAX_VOICES} if @timing
        @available, @buffers, @sources, @last, @gains = false, {}, [], {}, {}
        @predicted, @voice_priority, @voice_started = {}, {}, {}
        @voice_ends, @voice_cues = {}, {} if @timing
        return if ENV["BURROW_MUTE"] == "1" || ENV["SCARPE_NATIVE_HEADLESS"] == "1"
        require "ffi"
        @al = Module.new do
          extend FFI::Library
          ffi_lib(case RUBY_PLATFORM
          when /darwin/ then "/System/Library/Frameworks/OpenAL.framework/OpenAL"
          when /mingw|mswin/ then "OpenAL32.dll"
          else "libopenal.so.1"
          end)
          attach_function :alcOpenDevice, [:pointer], :pointer
          attach_function :alcCreateContext, [:pointer, :pointer], :pointer
          attach_function :alcMakeContextCurrent, [:pointer], :bool
          attach_function :alcDestroyContext, [:pointer], :void
          attach_function :alcCloseDevice, [:pointer], :bool
          attach_function :alGenBuffers, [:int, :pointer], :void
          attach_function :alBufferData, [:uint, :int, :pointer, :int, :int], :void
          attach_function :alDeleteBuffers, [:int, :pointer], :void
          attach_function :alGenSources, [:int, :pointer], :void
          attach_function :alSourcei, [:uint, :int, :int], :void
          attach_function :alSourcef, [:uint, :int, :float], :void
          attach_function :alSource3f, [:uint, :int, :float, :float, :float], :void
          attach_function :alSourcePlay, [:uint], :void
          attach_function :alSourceStop, [:uint], :void
          attach_function :alDeleteSources, [:int, :pointer], :void
          attach_function :alGetSourcei, [:uint, :int, :pointer], :void
          attach_function :alGetString, [:int], :string
          attach_function :alcGetIntegerv, [:pointer, :int, :int, :pointer], :void
          attach_function :alcGetError, [:pointer], :int
          attach_function :alIsExtensionPresent, [:string], :bool
          attach_function :alcIsExtensionPresent, [:pointer, :string], :bool
          attach_function :alcGetProcAddress, [:pointer, :string], :pointer
        end
        @device = @al.alcOpenDevice(nil)
        if @device.null?
          @timing.device[:status] = "device_unavailable" if @timing
          return
        end
        @context = @al.alcCreateContext(@device, nil)
        if @context.null?
          @timing.device[:status] = "context_unavailable" if @timing
          return close
        end
        @al.alcMakeContextCurrent(@context)
        ptr = FFI::MemoryPointer.new(:uint, MAX_VOICES + 1)
        @al.alGenSources(MAX_VOICES + 1, ptr)
        @sources = ptr.read_array_of_uint(MAX_VOICES + 1)
        @music_source = @sources.last
        @sources.first(MAX_VOICES).each do |source|
          @al.alSourcei(source, 0x202, 1) # Positions are relative to the listener.
          @al.alSourcef(source, 0x1021, 0) # Pan without distance attenuation.
        end
        # Decode before gameplay. First explosions must not read files or
        # allocate native sample buffers in the presentation loop.
        CUES.each { |name| buffer(name) }
        @cursor = 0
        @source_status = FFI::MemoryPointer.new(:int)
        @available = true
        if @timing
          @timing.device.merge!(device_report)
          @timing.device[:output_at_open] = core_audio_output if RUBY_PLATFORM.include?("darwin")
        end
        refresh
      rescue LoadError, StandardError => exception
        @error = exception.message
        close
      end

      def muted? = @preferences["muted"] || !available

      def refresh
        return unless available
        @gains.each { |source, gain| @al.alSourcef(source, 0x100a, gain * @preferences["volume"]) }
        if @preferences["muted"]
          @queue&.each { |at, cue, _| audio_drop(cue, "muted", "delayed", at) } if @timing
          @queue&.clear
          @voice_ends&.clear
          @sources.each { |source| @al.alSourceStop(source) }
        elsif @preferences["music"]
          unless @music_started
            @al.alSourcei(@music_source, 0x1009, buffer("music"))
            @al.alSourcei(@music_source, 0x1007, 1)
            @music_started = true
          end
          @al.alSourcef(@music_source, 0x100a, @preferences["volume"] * 0.35)
          @al.alGetSourcei(@music_source, 0x1010, @source_status)
          @al.alSourcePlay(@music_source) unless @source_status.read_int == 0x1012
        else
          @al.alSourceStop(@music_source)
        end
      end

      def frame(now)
        @timing&.frame(now)
      end

      def play(name, x: WIDTH / 2, volume: 1, immediate: false, throttle: true, pitch: 1.0, origin: nil, due_at: nil)
        now = Burrow.clock
        origin ||= @cue_origin || (immediate ? "predicted" : "ui")
        due_at ||= @cue_due || now
        return unless CUES.include?(name)
        return audio_drop(name, muted? && available ? "muted" : "unavailable", origin, due_at, now) if muted?
        if throttle && !immediate && now - @last.fetch(name, 0) < 0.065
          return audio_drop(name, "throttle", origin, due_at, now)
        end
        @last[name] = now
        al_started = Burrow.clock if @timing
        @stolen_cue = nil
        source = voice(immediate)
        unless source
          if @timing
            dropped = Burrow.clock
            @timing.record(name, origin: origin, due: due_at, at: dropped, busy: @sources.length - 1,
              reason: "no_voice", openal_ms: (dropped - al_started) * 1000, submit_ms: (dropped - now) * 1000)
          end
          return
        end
        @voice_priority[source], @voice_started[source] = immediate, now
        @al.alSourceStop(source)
        @al.alSourcei(source, 0x1009, @buffers.fetch(name))
        @al.alSourcef(source, 0x1003, pitch.clamp(0.25, 2.0))
        @gains[source] = volume.clamp(0.0, 1.0)
        @al.alSourcef(source, 0x100a, @gains[source] * @preferences["volume"])
        pan = ((x.to_f / WIDTH - 0.5) * 1.8).clamp(-0.9, 0.9)
        @al.alSource3f(source, 0x1004, pan, 0.0, -1.0)
        @al.alSourcePlay(source)
        if @timing
          submitted = Burrow.clock
          busy = 0
          @voice_ends.each_value { |at| busy += 1 if at > submitted }
          @voice_ends[source] = submitted + @seconds.fetch(name) / pitch.clamp(0.25, 2.0)
          @voice_cues[source] = name
          @timing.record(name, origin: origin, due: due_at, at: submitted, busy: busy,
            reason: @stolen_cue ? "steal" : "played", stolen: @stolen_cue,
            openal_ms: (submitted - al_started) * 1000, submit_ms: (submitted - now) * 1000)
        end
        true
      rescue StandardError => exception
        @error = exception.message
        audio_drop(name, "error", origin, due_at, now) if now && CUES.include?(name)
        nil
      end

      def event(event, screen_x: WIDTH / 2, state: nil, due_at: Burrow.clock)
        previous_origin, previous_due = @cue_origin, @cue_due
        @cue_origin, @cue_due = "event", due_at
        cue = event_cue(event)
        receipt = event["input"]
        # A single command can emit two reports (fire + build, for example).
        # Keep the bounded receipt so neither repeats the local cue.
        predicted = cue && receipt && @predicted && @predicted[receipt.values_at("match", "player", "seq")] == cue
        if cue && !predicted
          # Timeline already emits each event once. Valid reports in a burst can
          # arrive less than 65 ms apart during catch-up; do not discard them.
          report = %w[fire beam jump activate].include?(event["kind"])
          play(cue, x: screen_x, throttle: !report, pitch: event_pitch(event))
        elsif predicted
          audio_drop(cue, "predicted_duplicate", @cue_origin, due_at, Burrow.clock)
        end
        react(event, screen_x, state)
      ensure
        @cue_origin, @cue_due = previous_origin, previous_due
      end

      # Delayed cues: a grave's thud after the pop, a voice line after a shot.
      def update(now = Burrow.clock)
        return if !@queue || @queue.empty?
        due, @queue = @queue.partition { |entry| entry[0] <= now }
        previous_origin, previous_due = @cue_origin, @cue_due
        @cue_origin = "delayed"
        due.each do |at, name, options|
          @cue_due = at
          if now - at < 0.5
            speak(name, **options)
          else
            audio_drop(name, "stale", "delayed", at, now)
          end
        end
      ensure
        @cue_origin, @cue_due = previous_origin, previous_due if defined?(previous_origin)
      end

      # A short line in a team colour's voice (the HUD's "hurry up").
      def voice_line(line, color, x: WIDTH / 2, chatter: true)
        say(line, color, x: x, chatter: chatter)
      end

      # Called only after an input passes the UI gate and enters the connection
      # queue. It predicts sound alone; the host still owns every game change.
      def local_action(type, values:, state:, player:, sequence:, match_id:)
        return unless state && state["team"] == player
        event = case type
        when "fire"
          weapon = values[:weapon]
          kind = Catalog::WEAPONS[weapon]&.fetch(:kind)
          if %w[melee dash].include?(kind)
            # The swing is certain; the host's report adds the hit.
            {"kind" => "melee", "hits" => []}
          elsif kind == "heal"
            {"kind" => "heal"}
          elsif %w[beam laser shotgun burst flame].include?(kind)
            {"kind" => "beam", "style" => kind}
          elsif kind == "teleport"
            # Teleport reports a paired in/out event. Predict that event shape
            # so its authoritative receipt suppresses exactly one local cue.
            {"kind" => "teleport"}
          else
            {"kind" => "fire", "weapon" => weapon}
          end
        when "jump"
          worm = state["worms"]&.find { |candidate| candidate["id"] == state["active"] }
          worm && worm["rope"] ? {"kind" => "activate", "stage" => "released"} : {"kind" => "jump"}
        when "activate", "detonate"
          projectile = state["projectiles"].find { |p| p["owner"] == player && p["remote"] && p["life"] > 0 }
          worm = state["worms"]&.find { |candidate| candidate["id"] == state["active"] }
          if projectile
            stage = if projectile["stage"] == "walking"
              {"guided" => "flying", "digger" => "diving", "poisoner" => "spraying"}[projectile["kind"]]
            end
            {"kind" => "activate", "weapon" => projectile["weapon"], "stage" => stage}
          elsif worm && worm["rope"]
            {"kind" => "activate", "stage" => "released"}
          elsif worm && worm["jetpack"]
            {"kind" => "activate", "stage" => "parachute"}
          else
            {"kind" => "activate"}
          end
        end
        cue = event && event_cue(event)
        return unless cue && play(cue, immediate: true, pitch: event_pitch(event))
        @predicted ||= {}
        @predicted[[match_id, player, sequence]] = cue
        @predicted.shift while @predicted.size > 96
      end

      def event_cue(event)
        case event["kind"]
        when "fire"
          kind = Catalog::WEAPONS[event["weapon"]]&.fetch(:kind)
          return "fuse" if event["weapon"] == "dynamite"
          return "explosion-heavy" if event["weapon"] == "earthquake"
          case kind
          when "projectile", "homing" then "launch"
          when "strike", "mines", "napalm" then "plane"
          when "meteor" then "launch"
          when "bounce", "cluster", "sticky", "gas" then "throw"
          when "rope" then "throw"
          when "jetpack" then "launch"
          # Beam, melee, healing and teleport events supply their own report.
          when "beam", "laser", "shotgun", "burst", "flame", "melee", "dash", "heal", "teleport", "skip" then nil
          when "shield", "freeze", "boost", "gravity", "wind" then "pickup"
          when "herd" then "moo"
          when "girder" then "clank"
          else "equip"
          end
        when "beam"
          # The existing launch master is thrusterFire: its rush of burning gas
          # suits a flame stream, while bullets retain the short dry gun report.
          event["style"] == "laser" ? "beam" : event["style"] == "flame" ? "launch" : "shot"
        when "dig" then event["style"] == "torch" ? "launch" : "impact"
        when "explosion" then event.fetch("radius", 0) >= 70 ? "explosion-heavy" : "explosion"
        when "activate"
          if event["weapon"] == "banana" then "impact"
          else
            case event["stage"]
            when "flying" then "launch"
            when "diving" then "jump"
            when "spraying", "released" then "throw"
            else "equip"
            end
          end
        when "choir" then "choir"
        when "mine_land" then "impact"
        when "gas" then "impact" if event["weapon"] == "poison"
        when "critter_release" then "moo"
        when "critter_dive" then "impact"
        when "critter_fall" then "throw"
        when "melee" then melee_cue(event)
        when "build" then "clank"
        when "bounce" then event["worm"] ? "boing" : "bounce"
        when "defeat" then event["worm"] ? nil : "clank"
        when "damage" then nil # the victim's own squeak (#react) is the hurt sound
        else EVENT_CUES[event["kind"]]
        end
      end

      # Each cow in a herd moos a little differently; bouncing grubs boing on
      # their own note. Every voice resets its pitch, so later cues sound normal.
      def event_pitch(event)
        if event["kind"] == "critter_release" || (event["kind"] == "bounce" && event["worm"])
          0.88 + roll(event, 7) * 0.003
        else
          1.0
        end
      end

      def close
        if @timing
          @timing.device[:status] = "ready" if available
          @timing.device[:status] = "initialization_failed" if @error && !available
          @timing.device[:output_at_close] = core_audio_output if available && RUBY_PLATFORM.include?("darwin")
          @timing.write
          @timing = nil
        end
        if @al && @context && !@context.null?
          @al.alcMakeContextCurrent(@context)
          @sources.each do |source|
            @al.alSourceStop(source)
            ptr = FFI::MemoryPointer.new(:uint).write_uint(source)
            @al.alDeleteSources(1, ptr)
          end
          @buffers.each_value do |id|
            ptr = FFI::MemoryPointer.new(:uint).write_uint(id)
            @al.alDeleteBuffers(1, ptr)
          end
          @al.alcMakeContextCurrent(nil)
          @al.alcDestroyContext(@context)
          @context = nil
        end
        @al.alcCloseDevice(@device) if @al && @device && !@device.null?
        @device = nil
        @available = false
      end

      private

      def audio_drop(name, reason, origin = @cue_origin || "ui", due = @cue_due, now = Burrow.clock)
        return unless @timing && CUES.include?(name)
        busy = 0
        @voice_ends&.each_value { |at| busy += 1 if at > now }
        @timing.record(name, origin: origin, due: due || now, at: now, reason: reason, busy: busy,
          openal_ms: reason == "error" ? nil : 0.0)
        nil
      end

      # Query capabilities once, outside gameplay. Never request the device
      # specifier: it can contain a person's name (e.g. paired headphones).
      def device_report
        result = {status: "ready", vendor: @al.alGetString(0xb001), renderer: @al.alGetString(0xb003),
          version: @al.alGetString(0xb002), sample_rates_hz: (@sample_rates || {}).keys.sort,
          source_latency_extension: @al.alIsExtensionPresent("AL_SOFT_source_latency"),
          device_clock_extension: @al.alcIsExtensionPresent(@device, "ALC_SOFT_device_clock")}
        pointer = FFI::MemoryPointer.new(:int)
        {frequency_hz: 0x1007, refresh_hz: 0x1008, mono_sources: 0x1010, stereo_sources: 0x1011}.each do |key, param|
          @al.alcGetError(@device)
          pointer.write_int(0)
          @al.alcGetIntegerv(@device, param, 1, pointer)
          # Apple returns zero for these default-context hints without an
          # error. That means unreported, not a zero-Hz device or no sources.
          value = pointer.read_int
          result[key] = value > 0 ? value : nil if @al.alcGetError(@device).zero?
        end
        if result[:device_clock_extension]
          address = @al.alcGetProcAddress(@device, "alcGetInteger64vSOFT")
          unless address.null?
            get = FFI::Function.new(:void, [:pointer, :int, :int, :pointer], address)
            value = FFI::MemoryPointer.new(:int64)
            get.call(@device, 0x1601, 1, value) # ALC_DEVICE_LATENCY_SOFT, nanoseconds.
            result[:reported_device_latency_ms] = value.read_int64 / 1_000_000.0 if @al.alcGetError(@device).zero?
          end
        end
        result
      rescue StandardError
        {status: "ready", capabilities: "unavailable"}
      end

      # Default-output properties, not an acoustic measurement or a guarantee
      # that a backend still follows that default after a device switch. Read
      # only numbers/enums; neither device IDs nor names are retained in JSON.
      def core_audio_output
        core = Module.new do
          extend FFI::Library
          ffi_lib "/System/Library/Frameworks/CoreAudio.framework/CoreAudio"
          attach_function :AudioObjectGetPropertyData, [:uint, :pointer, :uint, :pointer, :pointer, :pointer], :int
          attach_function :AudioObjectGetPropertyDataSize, [:uint, :pointer, :uint, :pointer, :pointer], :int
        end
        property = lambda do |object, selector, scope, type = :uint|
          address = FFI::MemoryPointer.new(:uint, 3).write_array_of_uint([selector.unpack1("N"), scope.unpack1("N"), 0])
          size = FFI::MemoryPointer.new(:uint).write_uint(FFI.type_size(type))
          value = FFI::MemoryPointer.new(type)
          status = core.AudioObjectGetPropertyData(object, address, 0, nil, size, value)
          next unless status.zero? && size.read_uint == FFI.type_size(type)
          type == :double ? value.read_double : value.read_uint
        end
        device = property.call(1, "dOut", "glob")
        return {status: "no_default_output"} unless device && device > 0
        transport = property.call(device, "tran", "glob")
        transports = {"bltn" => "built_in", "blue" => "bluetooth", "blea" => "bluetooth_le", "usb " => "usb",
          "hdmi" => "hdmi", "dprt" => "displayport", "airp" => "airplay", "virt" => "virtual", "grup" => "aggregate"}
        rate = property.call(device, "nsrt", "glob", :double)
        result = {status: "queried", transport: transports.fetch([transport || 0].pack("N"), "other"),
          sample_rate_hz: rate, buffer_frames: property.call(device, "fsiz", "glob"),
          device_latency_frames: property.call(device, "ltnc", "outp"), safety_offset_frames: property.call(device, "saft", "outp")}
        address = FFI::MemoryPointer.new(:uint, 3).write_array_of_uint(["stm#".unpack1("N"), "outp".unpack1("N"), 0])
        size = FFI::MemoryPointer.new(:uint)
        status = core.AudioObjectGetPropertyDataSize(device, address, 0, nil, size)
        if status.zero? && size.read_uint.between?(4, 256) && size.read_uint % 4 == 0
          streams = FFI::MemoryPointer.new(:char, size.read_uint)
          status = core.AudioObjectGetPropertyData(device, address, 0, nil, size, streams)
          if status.zero?
            latencies = streams.read_array_of_uint(size.read_uint / 4).map { |id| property.call(id, "ltnc", "glob") }
            result[:stream_latency_frames] = latencies.max if latencies.all?
          end
        end
        frames = result.values_at(:buffer_frames, :device_latency_frames, :safety_offset_frames, :stream_latency_frames)
        result[:reported_path_ms] = frames.sum * 1000.0 / rate if frames.all? && rate && rate.finite? && rate > 0
        result
      rescue LoadError, StandardError
        {status: "unavailable"}
      end

      def melee_cue(event)
        hits = Array(event["hits"])
        return if event["continuing"] && hits.empty?
        return "whoosh" if event.key?("hits") && hits.empty?
        case event["style"]
        when "bat", "axe" then "bonk"
        when "prod" then "boing"
        when "fire_punch", "dragon_punch" then "pow"
        else "impact"
        end
      end

      # The grubs' own voices and cartoon extras. These follow authoritative
      # events only (never local prediction), and a deterministic roll on the
      # event id makes every player hear the same lines.
      def react(event, x, state)
        case event["kind"]
        when "damage" then hurt_voice(event, x, state)
        when "defeat" then farewell(event, x, state, drowned: false) if event["worm"]
        when "splash" then farewell(event, x, state, drowned: true) if event["worm"]
        when "turn" then turn_chatter(event, x, state)
        when "fire" then battle_cry(event, x, state)
        when "victory" then cheer(event, state)
        when "flood"
          unless @flooded
            @flooded = true
            later("ann-sudden-death", 0.4)
          end
        when "strike" then later("bomb-whistle", 0.7, x: x, volume: 0.8)
        when "mine_trigger"
          grub = nearest(state, event, 80)
          squeak("eek", color_of(state, grub), x) if grub
        when "critter_trail"
          if event["weapon"] == "sheep" && roll(event, 3) < 12 && Burrow.clock - (@baa_at || 0) > 2.2
            @baa_at = Burrow.clock
            play("baa", x: x, volume: 0.6, pitch: 0.95 + roll(event, 5) * 0.002)
          end
        end
      end

      def hurt_voice(event, x, state)
        victim = worm(state, event["worm"])
        return unless victim && victim["hp"].to_i > 0 # a fatal hit says goodbye instead
        color = color_of(state, victim)
        amount = event["amount"].to_i
        squeak(amount < 15 ? "oof" : amount < 35 ? "ow" : "yelp", color, x)
        later("slide-whistle-up", 0.05, x: x, volume: 0.5) if amount >= 30
        if victim["hp"].to_i <= 25 && roll(event, 1) < 50
          say("medic", color, x: x, delay: 0.75)
        elsif state && victim["team"] == state["team"] && %w[retreat settling].include?(state["phase"]) && roll(event, 2) < 50
          # Hurting your own grub earns a snicker from the next team along.
          rival = state["teams"]&.find { |team| team["id"] != victim["team"] }
          later("squeak-giggle", 0.7, x: x, pitch: SQUEAK_PITCH[rival["color"].to_i % 6], voice: true, chatter: true) if rival
        end
      end

      def farewell(event, x, state, drowned:)
        victim = worm(state, event["worm"])
        color = color_of(state, victim)
        if drowned
          squeak("wah", color, x)
          later("blub", 0.4, x: x)
        else
          squeak("byebye", color, x)
          later("pop", DYING, x: x)
          later("poof", DYING + 0.02, x: x, volume: 0.7)
          later("thud", DYING + 0.1, x: x)
        end
        return unless victim && state
        shooter = state["team"]
        if shooter && victim["team"] != shooter && roll(event, 4) < 50
          say("target-destroyed", color_of(state, {"team" => shooter}), x: WIDTH / 2, delay: 1.25)
        end
        survivors = state["worms"]&.count { |w| w["team"] == victim["team"] && w["id"] != victim["id"] && w["hp"].to_i > 0 }
        later("sad-trombone", 1.3, volume: 0.8) if survivors&.zero?
        now = Burrow.clock
        (@kills ||= []) << now
        @kills.select! { |at| now - at < 0.75 }
        if @kills.length >= 2 && now - (@multi_kill_at || -10) > 3
          @multi_kill_at = now
          later("ann-multi-kill", 1.0)
        end
      end

      def turn_chatter(event, x, state)
        if state && state["turn"].to_i <= 1
          @flooded = false
          later("ann-fight", 0.3)
        elsif roll(event, 6) < 35
          line = %w[go-go-go cover-me watch-my-back][roll(event, 8) % 3]
          say(line, color_of(state, {"team" => event["team"]}), x: x, delay: 0.7)
        end
      end

      def battle_cry(event, x, state)
        kind = Catalog::WEAPONS[event["weapon"]]&.fetch(:kind)
        color = color_of(state, worm(state, event["worm"]))
        case kind
        when "bounce", "cluster", "sticky", "place"
          say("fire-in-the-hole", color, x: x, delay: 0.15) if roll(event, 9) < 45
        when "strike", "mines", "napalm", "meteor"
          say("get-down", color, x: x, delay: 0.2) if roll(event, 9) < 60
        when "walker", "guided"
          later("baa", 0.25, x: x)
        when "poisoner"
          later("pfft", 0.3, x: x)
        when "digger"
          squeak("eek", color, x)
        end
      end

      def cheer(event, state)
        team = event["team"]
        unless team
          later("ann-its-a-tie", 0.8)
          return
        end
        color = color_of(state, {"team" => team})
        say("you-win", color, delay: 0.5, chatter: false)
        squeak("yay", color, WIDTH / 2, delay: 1.5)
        members = state && state["worms"]&.select { |w| w["team"] == team }
        later("ann-flawless-victory", 2.0) if members && !members.empty? && members.all? { |w| w["hp"].to_i > 0 }
      end

      def say(line, color, x: WIDTH / 2, delay: 0, chatter: true)
        return unless color
        voice, pitch = VOICES[color.to_i % VOICES.length]
        later("vo-#{line}-#{voice}", delay, x: x, pitch: pitch, voice: true, chatter: chatter)
      end

      def squeak(kind, color, x, delay: 0)
        return unless color
        later("squeak-#{kind}", delay, x: x, pitch: SQUEAK_PITCH[color.to_i % SQUEAK_PITCH.length], voice: true)
      end

      def later(name, delay, **options)
        return speak(name, **options) if delay <= 0
        (@queue ||= []) << [Burrow.clock + delay, name, options]
        while @queue.length > QUEUE_LIMIT
          at, cue, = @queue.shift
          audio_drop(cue, "queue_overflow", "delayed", at)
        end
      end

      # Voices never talk over a line already in progress unless they react to
      # a hit. Several grubs caught in one blast may all squeak, up to three.
      def speak(name, x: WIDTH / 2, volume: 1, pitch: 1.0, voice: false, chatter: false)
        return play(name, x: x, volume: volume, pitch: pitch) unless voice
        now = Burrow.clock
        return audio_drop(name, "chatter") if chatter && now < (@voice_until || 0)
        (@squeaks ||= []).select! { |at| now - at < 0.12 }
        return audio_drop(name, "squeak_cap") if @squeaks.length >= 3
        @squeaks << now
        return unless play(name, x: x, volume: volume, pitch: pitch, throttle: false)
        length = (@seconds && @seconds[name]) || 0.8
        @voice_until = [@voice_until || 0, now + length / pitch].max
      end

      def roll(event, salt) = ((event["id"].to_i + 1) * 2_654_435_761 + salt * 40_503) % 4_294_967_296 % 100

      def worm(state, id) = id && state && state["worms"]&.find { |w| w["id"] == id }

      def color_of(state, worm)
        return unless worm && state
        state["teams"]&.find { |team| team["id"] == worm["team"] }&.fetch("color", nil)
      end

      def nearest(state, event, reach)
        return unless state && event["x"] && event["y"]
        state["worms"]&.select { |w| w["hp"].to_i > 0 }
          &.min_by { |w| Math.hypot(w["x"] - event["x"], w["y"] - event["y"]) }
          &.then { |w| w if Math.hypot(w["x"] - event["x"], w["y"] - event["y"]) <= reach }
      end

      def voice(immediate)
        # Prefer finished voices. When all effect voices are busy, protect a fresh
        # local report from a same-frame burst of authoritative impact effects.
        index = fallback = oldest = nil
        # The final allocated source belongs to music, including smaller pools.
        count = @sources.length - 1
        count.times do |offset|
          i = (@cursor + offset) % count
          source = @sources[i]
          @al.alGetSourcei(source, 0x1010, @source_status)
          if @source_status.read_int != 0x1012
            index = i
            break
          end
          started = @voice_started.fetch(source, 0)
          oldest = i if immediate && (!oldest || started < @voice_started.fetch(@sources[oldest], 0))
          fallback = i if !@voice_priority[source] && (!fallback || started < @voice_started.fetch(@sources[fallback], 0))
        end
        unless index
          index = fallback || oldest
          @stolen_cue = @voice_cues[@sources[index]] if index && @timing
        end
        return unless index
        @cursor = index + 1
        @sources[index]
      end

      def buffer(name)
        raise "Unknown sound cue" unless CUES.include?(name)
        @buffers[name] ||= begin
          wav = File.binread(File.join(ROOT, "#{name}.wav"))
          data = self.class.decode_wave(wav)
          (@sample_rates ||= {})[data[:rate]] = true if @timing
          pcm = data.fetch(:pcm)
          (@seconds ||= {})[name] = pcm.bytesize.fdiv(data[:channels] * 2 * data[:rate])
          memory = FFI::MemoryPointer.new(:char, pcm.bytesize)
          memory.put_bytes(0, pcm)
          id = FFI::MemoryPointer.new(:uint)
          @al.alGenBuffers(1, id)
          @al.alBufferData(id.read_uint, data[:channels] == 1 ? 0x1101 : 0x1103, memory, pcm.bytesize, data[:rate])
          id.read_uint
        end
      end
    end
  end
end
