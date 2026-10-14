# frozen_string_literal: true
# Real OpenAL Soft wave-backend probe, using diagnostic tones (no asset changes).
# Run under the exclusive bench wrapper. Output is synthetic, never microphone
# data. It measures submission -> mixed-file visibility, NOT acoustic latency.
# Set BURROW_BENCH_SOURCE for the frozen baseline. Usage:
# bundle exec ruby tools/perf_audio_wave.rb --output /scratch/wave-baseline.json
# The first source is a 440 Hz, 1.5 s tone. Twelve more sources start after 200 ms.
# With 12 voices the first tone is stolen; with spare voices it must finish.
# The analyzer measures its frequency energy before/after that burst in real PCM.
require "optparse"
require "json"
options = {}
OptionParser.new { |p| p.on("--output PATH") { |v| options[:output] = File.expand_path(v) } }.parse!
output = options.fetch(:output)
wave = output.sub(/\.json\z/, ".wav")
config = output.sub(/\.json\z/, ".conf")
File.write(config, "[general]\nchannels=stereo\nsample-type=int16\nfrequency=48000\n[wave]\nfile=#{wave}\n")
ENV["ALSOFT_CONF"], ENV["ALSOFT_DRIVERS"] = config, "wave"
root = File.expand_path(ENV.fetch("BURROW_BENCH_SOURCE", ".."), __dir__)
require File.join(root, "lib/burrow")
require File.join(root, "lib/burrow/client/audio")
audio = Burrow::Client::Audio.new({"volume" => 0.5, "muted" => false, "music" => false})
abort "OpenAL unavailable: #{audio.error}" unless audio.available
al = audio.instance_variable_get(:@al)
buffers = audio.instance_variable_get(:@buffers)
names = Burrow::Client::Audio::CUES.reject { |name| name == "music" }.first(13)
names.each_with_index do |name, i|
  hz = i.zero? ? 440 : 1_000 + i * 130
  pcm = Array.new(33_075) { |sample| (1200 * Math.sin(sample * 2 * Math::PI * hz / 22_050)).round }.pack("s<*")
  pointer = FFI::MemoryPointer.new(:char, pcm.bytesize).put_bytes(0, pcm)
  al.alBufferData(buffers.fetch(name), 0x1101, pointer, pcm.bytesize, 22_050)
end
sleep 0.12
bytes_before = File.size(wave)
submitted = Burrow.clock
audio.play(names.first, throttle: false)
# The backend writes buffered chunks. Observe the first nonzero PCM bytes, not
# just file size growth, so silence already in the stdio buffer isn't counted.
visible = nil
deadline = submitted + 0.2
until Burrow.clock >= deadline
  raw = File.binread(wave)
  offset = raw.index("data")
  if offset
    samples = raw.byteslice(offset + 8..).to_s.unpack("s<*")
    visible ||= Burrow.clock if samples.any? { |s| s.abs > 30 }
  end
  sleep 0.001
end
names.drop(1).each { |name| audio.play(name, throttle: false) }
sleep 1.45
audio.close
raw = File.binread(wave)
data_offset = raw.index("data") + 8
rate = raw.byteslice(24, 4).unpack1("V")
channels = raw.byteslice(22, 2).unpack1("v")
samples = raw.byteslice(data_offset..).unpack("s<*").each_slice(channels).map(&:first)
first = samples.index { |sample| sample.abs > 30 }
def tone_energy(samples, rate, from, to)
  section = samples.slice((from * rate).round, ((to - from) * rate).round)
  real = imaginary = 0.0
  section.each_with_index do |sample, i|
    phase = i * 2 * Math::PI * 440 / rate
    real += sample * Math.cos(phase)
    imaginary += sample * Math.sin(phase)
  end
  Math.hypot(real, imaginary) * 2 / section.length
end
onset = first.fdiv(rate)
before = tone_energy(samples, rate, onset + 0.04, onset + 0.14)
after = tone_energy(samples, rate, onset + 0.5, onset + 0.6)
tail = tone_energy(samples, rate, onset + 1.30, onset + 1.40)
result = {schema: 1, ruby: RUBY_DESCRIPTION, source: root, voices: Burrow::Client::Audio::MAX_VOICES,
  mixer: "OpenAL Soft wave", wave: wave, rate: rate, channels: channels,
  submission_to_file_visibility_ms: visible && (visible - submitted) * 1000,
  first_tone_energy: before, after_burst_energy: after, tail_energy: tail,
  after_burst_ratio: after / before, tail_ratio: tail / before,
  initial_file_bytes: bytes_before,
  limits: "File visibility includes mixer quantum, stdio buffering and <=1 ms observation sleeps; no device/acoustic output."}
File.write(output, JSON.pretty_generate(result) + "\n")
puts JSON.generate(result)
