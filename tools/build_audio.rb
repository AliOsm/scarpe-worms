#!/usr/bin/env ruby
# frozen_string_literal: true

# Original synthesis: no samples or copyrighted recordings. Deterministic stereo PCM.
require "fileutils"
ROOT = File.expand_path("..", __dir__)
RATE = 22_050
FileUtils.mkdir_p(File.join(ROOT, "assets/audio"))

def wave(name, seconds, &block)
  rng = Random.new(73)
  count = (seconds * RATE).to_i
  pcm = String.new(capacity: count * 4, encoding: Encoding::BINARY)
  count.times do |i|
    t = i.fdiv(RATE)
    sample = block.call(t, seconds, rng).clamp(-0.92, 0.92)
    pan = Math.sin(t * 1.7) * 0.12
    pcm << [(sample * (1 - pan) * 24_000).round, (sample * (1 + pan) * 24_000).round].pack("s<s<")
  end
  header = "RIFF" + [36 + pcm.bytesize].pack("V") + "WAVEfmt " + [16, 1, 2, RATE, RATE * 4, 4, 16].pack("VvvVVvv") + "data" + [pcm.bytesize].pack("V")
  File.binwrite(File.join(ROOT, "assets/audio/#{name}.wav"), header + pcm)
end

tau = Math::PI * 2
wave("click", 0.12) { |t, _, _| Math.sin(tau * (740 * t - 1000 * t * t)) * Math.exp(-t * 44) * 0.4 }
wave("launch", 0.42) { |t, _, r| ((r.rand * 2 - 1) * 0.5 + Math.sin(tau * (180 * t - 140 * t * t)) * 0.25) * Math.exp(-t * 9) }
wave("explosion", 1.0) { |t, _, r| ((r.rand * 2 - 1) * Math.exp(-t * 7) * 0.68 + Math.sin(tau * (65 * t - 20 * t * t)) * Math.exp(-t * 5) * 0.45) * [t * 200, 1].min }
wave("bounce", 0.23) { |t, _, _| Math.sin(tau * (500 * t - 650 * t * t)) * Math.exp(-t * 23) * 0.45 }
wave("jump", 0.26) { |t, _, _| Math.sin(tau * (230 * t + 550 * t * t)) * Math.sin(Math::PI * t / 0.26) * 0.25 }
wave("hurt", 0.26) { |t, _, _| (Math.sin(tau * 170 * t) + Math.sin(tau * 256 * t) * 0.4) * Math.exp(-t * 15) * 0.3 }
wave("splash", 0.7) { |t, _, r| ((r.rand * 2 - 1) * 0.4 + Math.sin(tau * (170 * t + 120 * t * t)) * 0.15) * Math.exp(-t * 6) }
wave("beam", 0.32) { |t, _, _| Math.sin(tau * (1200 * t - 1200 * t * t)) * Math.exp(-t * 15) * 0.35 }
wave("turn", 0.75) { |t, _, _| frequency = t < 0.22 ? 440 : t < 0.44 ? 554.365 : 659.255; Math.sin(tau * frequency * t) * Math.exp(-(t % 0.22) * 12) * 0.25 }
wave("pickup", 0.52) { |t, _, _| note = [523.25, 659.255, 783.99, 1046.5][[(t / 0.13).floor, 3].min]; Math.sin(tau * note * t) * Math.exp(-(t % 0.13) * 15) * 0.23 }
wave("teleport", 0.75) { |t, _, _| Math.sin(tau * (300 * t + 600 * t * t)) * Math.sin(tau * 7 * t) * Math.sin(Math::PI * t / 0.75) * 0.3 }
wave("victory", 2.5) { |t, _, _| notes = [392, 493.88, 587.33, 783.99, 659.25, 783.99, 987.77, 1174.66]; f = notes[[(t / 0.28).floor, 7].min]; phase = t % 0.28; (Math.sin(tau * f * t) + Math.sin(tau * f * 2 * t) * 0.2) * Math.exp(-phase * 8) * [1, (2.5 - t) * 3].min * 0.28 }
# A 24-second loop of gentle marimba-like melody, warm bass and soft brushed noise.
wave("music", 24) do |t, _, r|
  beat = (t / 0.375).floor
  melody = [64, 67, 71, 67, 62, 66, 69, 66, 60, 64, 67, 64, 62, 66, 69, 74]
  note = melody[(beat / 2) % melody.length]
  f = 440 * 2**((note - 69) / 12.0)
  phase = t % 0.75
  top = (Math.sin(tau * f * phase) + Math.sin(tau * f * 3.99 * phase) * 0.14) * Math.exp(-phase * 7) * 0.16
  bass_f = [82.407, 73.416, 65.406, 73.416][(beat / 16) % 4]
  bass = Math.sin(tau * bass_f * t) * Math.exp(-(t % 1.5) * 4) * 0.09
  brush = (r.rand * 2 - 1) * Math.exp(-(t % 0.375) * 70) * 0.025
  (top + bass + brush) * [t * 4, 1, (24 - t) * 4].min
end
puts "Generated #{Dir[File.join(ROOT, 'assets/audio/*.wav')].length} original stereo cues."
