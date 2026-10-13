# frozen_string_literal: true

module Burrow
  module Client
    # One native OpenAL context mixes all voices in process. No per-effect subprocesses.
    class Audio
      MAX_VOICES = 12
      ROOT = File.join(Burrow::ROOT, "assets/audio")
      CUES = %w[beam bounce click close equip error explosion explosion-heavy hurt impact
        jump launch music open pickup shot splash teleport throw tick turn victory].freeze
      EVENT_CUES = {"damage" => "hurt", "jump" => "jump", "bounce" => "bounce",
        "splash" => "splash", "turn" => "turn", "pickup" => "pickup", "heal" => "pickup",
        "victory" => "victory", "teleport" => "teleport", "build" => "equip",
        "melee" => "impact", "quake" => "explosion-heavy", "rope_hook" => "equip"}.freeze
      attr_reader :available, :error

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
        @available, @buffers, @sources, @last, @gains = false, {}, [], {}, {}
        @predicted, @voice_priority, @voice_started = {}, {}, {}
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
        end
        @device = @al.alcOpenDevice(nil)
        return if @device.null?
        @context = @al.alcCreateContext(@device, nil)
        return close if @context.null?
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

      def play(name, x: WIDTH / 2, volume: 1, immediate: false, throttle: true, pitch: 1.0)
        return if muted? || !CUES.include?(name)
        now = Burrow.clock
        return if throttle && !immediate && now - @last.fetch(name, 0) < 0.065
        @last[name] = now
        source = voice(immediate)
        return unless source
        @voice_priority[source], @voice_started[source] = immediate, now
        @al.alSourceStop(source)
        @al.alSourcei(source, 0x1009, @buffers.fetch(name))
        @al.alSourcef(source, 0x1003, pitch.clamp(0.25, 2.0))
        @gains[source] = volume.clamp(0.0, 1.0)
        @al.alSourcef(source, 0x100a, @gains[source] * @preferences["volume"])
        pan = ((x.to_f / WIDTH - 0.5) * 1.8).clamp(-0.9, 0.9)
        @al.alSource3f(source, 0x1004, pan, 0.0, -1.0)
        @al.alSourcePlay(source)
        true
      rescue StandardError => exception
        @error = exception.message
        nil
      end

      def event(event, screen_x: WIDTH / 2)
        cue = event_cue(event)
        if cue && (receipt = event["input"])
          key = receipt.values_at("match", "player", "seq")
          # A single command can emit two reports (fire + build, for example).
          # Keep the bounded receipt so neither repeats the local cue.
          return if @predicted && @predicted[key] == cue
        end
        # Timeline already emits each event once. Valid reports in a burst can
        # arrive less than 65 ms apart during catch-up; do not discard them.
        report = %w[fire beam jump activate].include?(event["kind"])
        play(cue, x: screen_x, throttle: !report, pitch: event_pitch(event)) if cue
      end

      # Called only after an input passes the UI gate and enters the connection
      # queue. It predicts sound alone; the host still owns every game change.
      def local_action(type, values:, state:, player:, sequence:, match_id:)
        return unless state && state["team"] == player
        event = case type
        when "fire"
          weapon = values[:weapon]
          kind = Catalog::WEAPONS[weapon]&.fetch(:kind)
          if %w[beam laser shotgun burst flame].include?(kind)
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
          return "tick" if event["weapon"] == "dynamite"
          return "explosion-heavy" if event["weapon"] == "earthquake"
          case kind
          when "projectile", "homing" then "launch"
          when "strike", "mines", "napalm", "meteor" then "launch"
          when "bounce", "cluster", "sticky", "gas" then "throw"
          when "rope" then "throw"
          when "jetpack" then "launch"
          # Beam, melee, healing and teleport events supply their own report.
          when "beam", "laser", "shotgun", "burst", "flame", "melee", "dash", "heal", "teleport", "skip" then nil
          when "shield", "freeze", "boost", "gravity", "wind" then "pickup"
          when "herd" then "hurt"
          else "equip"
          end
        when "beam" then event["style"] == "laser" ? "beam" : "shot"
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
        when "choir" then "pickup"
        when "mine_land" then "impact"
        when "gas" then "impact" if event["weapon"] == "poison"
        when "critter_release" then "hurt"
        when "critter_dive" then "impact"
        when "critter_fall" then "throw"
        else EVENT_CUES[event["kind"]]
        end
      end

      # A low cartoon call reuses the original voiced cue for each cow release.
      # Reset pitch on every voice use so later damage reports sound normal.
      def event_pitch(event)
        event["weapon"] == "cow" && %w[fire critter_release].include?(event["kind"]) ? 0.65 : 1.0
      end

      def close
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

      def voice(immediate)
        # Prefer finished voices. When all twelve are busy, protect a fresh
        # local report from a same-frame burst of authoritative impact effects.
        indices = MAX_VOICES.times.map { |i| (@cursor + i) % MAX_VOICES }
        index = indices.find do |i|
          @al.alGetSourcei(@sources[i], 0x1010, @source_status)
          @source_status.read_int != 0x1012
        end
        index ||= indices.reject { |i| @voice_priority[@sources[i]] }.min_by { |i| @voice_started.fetch(@sources[i], 0) }
        index ||= indices.min_by { |i| @voice_started.fetch(@sources[i], 0) } if immediate
        return unless index
        @cursor = index + 1
        @sources[index]
      end

      def buffer(name)
        raise "Unknown sound cue" unless CUES.include?(name)
        @buffers[name] ||= begin
          wav = File.binread(File.join(ROOT, "#{name}.wav"))
          data = self.class.decode_wave(wav)
          pcm = data.fetch(:pcm)
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
