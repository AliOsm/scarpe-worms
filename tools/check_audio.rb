# frozen_string_literal: true
# Linux CI uses OpenAL's null output. A Mac runs this against its real OpenAL device.
ENV["ALSOFT_DRIVERS"] ||= "null" if RUBY_PLATFORM.include?("linux")
require_relative "../lib/burrow"
require_relative "../lib/burrow/client/audio"
settings = {"muted" => false, "music" => true, "volume" => 0.4}
audio = Burrow::Client::Audio.new(settings)
abort "OpenAL could not initialize (device or ffi unavailable)" unless audio.available
files = Dir[File.join(Burrow::ROOT, "assets/audio/*.wav")]
files.each do |path|
  audio.play(File.basename(path, ".wav"))
  sleep 0.075
end
abort "A cue failed to decode" unless audio.instance_variable_get(:@buffers).length == files.length
settings["muted"] = true
audio.refresh
abort "Mute did not apply" unless audio.muted?
settings["muted"] = false
audio.refresh
abort "Unmute did not apply" if audio.muted?
audio.close
audio.close # Shutdown is idempotent.
puts "OpenAL initialized, decoded and mixed #{files.size} cues; mute, resume, and shutdown passed."
