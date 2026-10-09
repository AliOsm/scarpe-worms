# frozen_string_literal: true

module Burrow
  module Client
    # One native OpenAL context mixes all voices in process. No per-effect subprocesses.
    class Audio
      MAX_VOICES = 12
      ROOT = File.join(Burrow::ROOT, "assets/audio")
      attr_reader :available

      def initialize(preferences)
        @preferences = preferences
        @available, @buffers, @sources, @last = false, {}, [], {}
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
        @cursor = 0
        @available = true
        refresh
      rescue LoadError, StandardError
        close
      end

      def muted? = @preferences["muted"] || !available

      def refresh
        return unless available
        if @preferences["muted"]
          @sources.each { |source| @al.alSourceStop(source) }
        elsif @preferences["music"]
          unless @music_started
            @al.alSourcei(@music_source, 0x1009, buffer("music"))
            @al.alSourcei(@music_source, 0x1007, 1)
            @music_started = true
          end
          @al.alSourcef(@music_source, 0x100a, @preferences["volume"] * 0.35)
          status = FFI::MemoryPointer.new(:int)
          @al.alGetSourcei(@music_source, 0x1010, status)
          @al.alSourcePlay(@music_source) unless status.read_int == 0x1012
        else
          @al.alSourceStop(@music_source)
        end
      end

      def play(name, x: WIDTH / 2, volume: 1)
        return if muted?
        now = Burrow.clock
        return if now - @last.fetch(name, 0) < 0.065
        @last[name] = now
        source = @sources[@cursor % MAX_VOICES]
        @cursor += 1
        @al.alSourceStop(source)
        @al.alSourcei(source, 0x1009, buffer(name))
        @al.alSourcei(source, 0x202, 1)
        @al.alSourcef(source, 0x100a, volume * @preferences["volume"])
        @al.alSourcePlay(source)
      rescue StandardError
        nil
      end

      def event(event)
        cue = {"fire" => "launch", "explosion" => "explosion", "damage" => "hurt", "jump" => "jump",
          "bounce" => "bounce", "splash" => "splash", "beam" => "beam", "turn" => "turn", "pickup" => "pickup",
          "heal" => "pickup", "victory" => "victory", "teleport" => "teleport", "build" => "click", "quake" => "explosion"}[event["kind"]]
        cue = event["stage"] == "flying" ? "launch" : "click" if event["kind"] == "activate"
        play(cue, x: event.fetch("x", WIDTH / 2)) if cue
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

      def buffer(name)
        @buffers[name] ||= begin
          wav = File.binread(File.join(ROOT, "#{name}.wav"))
          raise "Invalid PCM audio" unless wav.start_with?("RIFF") && wav[8, 4] == "WAVE" && wav[36, 4] == "data"
          channels, rate, bits = wav[22, 2].unpack1("v"), wav[24, 4].unpack1("V"), wav[34, 2].unpack1("v")
          raise "Unsupported PCM format" unless channels == 2 && bits == 16
          pcm = wav.byteslice(44..)
          memory = FFI::MemoryPointer.new(:char, pcm.bytesize)
          memory.put_bytes(0, pcm)
          id = FFI::MemoryPointer.new(:uint)
          @al.alGenBuffers(1, id)
          @al.alBufferData(id.read_uint, 0x1103, memory, pcm.bytesize, rate)
          id.read_uint
        end
      end
    end
  end
end
