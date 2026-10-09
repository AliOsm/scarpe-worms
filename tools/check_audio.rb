# frozen_string_literal: true
# Linux CI uses OpenAL's null output. A Mac runs this against its real OpenAL device.
ENV["ALSOFT_DRIVERS"] ||= "null" if RUBY_PLATFORM.include?("linux")
require_relative "../lib/burrow"
require_relative "../lib/burrow/client/audio"
settings = {"muted" => false, "music" => true, "volume" => 0.4}
audio = Burrow::Client::Audio.new(settings)
abort "OpenAL could not initialize (device or ffi unavailable)" unless audio.available
al = audio.instance_variable_get(:@al)
al.attach_function :alGetError, [], :int
al.attach_function :alGetSource3f, [:uint, :int, :pointer, :pointer, :pointer], :void
abort "Audio initialization failed: #{audio.error}" if audio.error
abort "OpenAL rejected a sample" unless al.alGetError.zero?
files = Dir[File.join(Burrow::ROOT, "assets/audio/*.wav")]
files.each do |path|
  audio.play(File.basename(path, ".wav"))
  sleep 0.075
end
abort "A cue failed to decode" unless audio.instance_variable_get(:@buffers).length == files.length
abort "OpenAL rejected playback" unless al.alGetError.zero?
# Verify real source positioning; stereo effects silently ignore this in OpenAL.
[-100, Burrow::WIDTH + 100].each do |screen_x|
  audio.play("click", x: screen_x)
  sources = audio.instance_variable_get(:@sources)
  cursor = audio.instance_variable_get(:@cursor)
  source = sources[(cursor - 1) % Burrow::Client::Audio::MAX_VOICES]
  x, y, z = 3.times.map { FFI::MemoryPointer.new(:float) }
  al.alGetSource3f(source, 0x1004, x, y, z)
  expected = screen_x < 0 ? -0.9 : 0.9
  abort "Effect panning was not applied" unless (x.read_float - expected).abs < 0.001 && z.read_float == -1.0
  sleep 0.075
end
settings["muted"] = true
audio.refresh
abort "Mute did not apply" unless audio.muted?
settings["muted"] = false
audio.refresh
abort "Unmute did not apply" if audio.muted?
audio.close
audio.close # Shutdown is idempotent.
puts "OpenAL initialized, decoded and mixed #{files.size} cues; camera-relative positioning, mute, resume, and shutdown passed."
