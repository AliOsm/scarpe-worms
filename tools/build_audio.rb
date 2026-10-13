#!/usr/bin/env ruby
# frozen_string_literal: true

# Original synthesis plus reviewed CC0 Kenney cues. All builds use committed
# canonical PCM masters; neither ffmpeg nor a network connection is required.
require "fileutils"
require "digest"
require "json"
ROOT = File.expand_path("..", __dir__)
RATE = 22_050
FileUtils.mkdir_p(File.join(ROOT, "assets/audio"))

def write_pcm(name, pcm, channels: 1)
  header = "RIFF" + [36 + pcm.bytesize].pack("V") + "WAVEfmt " + [16, 1, channels, RATE, RATE * channels * 2, channels * 2, 16].pack("VvvVVvv") + "data" + [pcm.bytesize].pack("V")
  File.binwrite(File.join(ROOT, "assets/audio/#{name}.wav"), header + pcm)
end

def wave(name, seconds, stereo: false, &block)
  rng = Random.new(73)
  count = (seconds * RATE).to_i
  channels = stereo ? 2 : 1
  pcm = String.new(capacity: count * channels * 2, encoding: Encoding::BINARY)
  count.times do |i|
    t = i.fdiv(RATE)
    sample = block.call(t, seconds, rng).clamp(-0.92, 0.92)
    if stereo
      pan = Math.sin(t * 1.7) * 0.12
      pcm << [(sample * (1 - pan) * 24_000).round, (sample * (1 + pan) * 24_000).round].pack("s<s<")
    else
      pcm << [(sample * 24_000).round].pack("s<")
    end
  end
  write_pcm(name, pcm, channels: channels)
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
wave("music", 24, stereo: true) do |t, _, r|
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
# A short, dry gun report; use separate beam/impact sounds for lasers and punches.
wave("shot", 0.23) do |t, _, r|
  ((r.rand * 2 - 1) * Math.exp(-t * 32) * 0.72 +
    Math.sin(tau * (145 * t - 220 * t * t)) * Math.exp(-t * 24) * 0.36) * [t * 1000, 1].min
end

# Short original cartoon performances. Pitch curves use normalized time; vowel
# targets describe a small vocal tract, before the game's per-team pitch shift.
module CartoonAudio
  extend self
  TAU = Math::PI * 2
  VOWELS = {
    uh: [500, 1250, 2850, 4000, 5000], a: [850, 1600, 2900, 4050, 5050],
    u: [420, 950, 2700, 3900, 4800], i: [340, 2750, 3550, 4500, 5400],
    e: [600, 2300, 3150, 4150, 5100], ae: [780, 2100, 2900, 3900, 4950],
    w: [320, 700, 2400, 3700, 4800]
  }.freeze

  def curve(points, position)
    return points.first.last if position <= points.first.first
    points.each_cons(2) do |(left, a), (right, b)|
      next if position > right
      u = (position - left) / (right - left)
      return a + (b - a) * u * u * (3 - 2 * u)
    end
    points.last.last
  end

  def envelope(t, seconds, attack: 0.012, release: 0.035)
    return 0.0 unless t.between?(0, seconds)
    Math.sin([t / attack, 1].min * Math::PI / 2)**2 *
      Math.sin([(seconds - t) / release, 1].min * Math::PI / 2)**2
  end

  def render(seconds)
    count = (seconds * RATE).to_i
    Array.new(count) { |i| yield(i.fdiv(RATE), i.fdiv([1, count - 1].max)) }
  end

  def mix(buffer, sound, at: 0, gain: 1)
    offset = (at * RATE).round
    sound.each_with_index do |value, i|
      break if offset + i >= buffer.length
      buffer[offset + i] += value * gain
    end
    buffer
  end

  class Lowpass
    def initialize
      @last = 0.0
    end

    def tick(value, frequency)
      @last += (1 - Math.exp(-TAU * frequency / RATE)) * (value - @last)
    end
  end

  class Resonator
    def initialize(bandwidth)
      @radius = Math.exp(-Math::PI * bandwidth / RATE)
      @square = @radius**2
      @last = @previous = 0.0
    end

    def tick(value, frequency)
      coefficient = 2 * @radius * Math.cos(TAU * frequency / RATE)
      result = value * (1 - coefficient + @square) + coefficient * @last - @square * @previous
      @previous, @last = @last, result
      result
    end
  end

  # A Fourier-limited Rosenberg glottal-flow derivative. The highest harmonic
  # stays below 8 kHz throughout a glide; interpolation avoids pulse-edge aliasing.
  def glottal_table(harmonics)
    @glottal_tables ||= {}
    @glottal_tables[harmonics] ||= begin
      pulse = Array.new(512) do |i|
        phase = i / 512.0
        if phase < 0.42
          Math::PI / 0.84 * Math.sin(Math::PI * phase / 0.42)
        elsif phase < 0.66
          -Math::PI / 0.48 * Math.sin(Math::PI * (phase - 0.42) / 0.24)
        else
          0.0
        end
      end
      coefficients = (1..harmonics).map do |h|
        taper = Math.cos(Math::PI * h / (2 * (harmonics + 1)))**2
        [pulse.each_with_index.sum { |v, i| v * Math.cos(TAU * h * i / 512) } / 256 * taper,
          pulse.each_with_index.sum { |v, i| v * Math.sin(TAU * h * i / 512) } / 256 * taper]
      end
      table = Array.new(2048) do |i|
        coefficients.each_with_index.sum do |(cosine, sine), h|
          phase = TAU * (h + 1) * i / 2048
          cosine * Math.cos(phase) + sine * Math.sin(phase)
        end
      end
      rms = Math.sqrt(table.sum { |v| v * v } / table.length)
      table.map { |v| v / rms }
    end
  end

  class Glottis
    def initialize(max_frequency, seed, rough)
      @table = CartoonAudio.glottal_table((8000 / max_frequency).floor)
      @rng, @air = Random.new(seed), Lowpass.new
      @phase, @jitter, @shimmer, @rough = 0.0, 1.0, 1.0, rough
    end

    def tick(frequency, breath)
      @phase += frequency * @jitter / RATE
      if @phase >= 1
        @phase %= 1
        @jitter = 1 + (@rng.rand * 2 - 1) * @rough
        @shimmer = 1 + (@rng.rand * 2 - 1) * 0.035
      end
      position = @phase * @table.length
      index = position.floor
      value = @table[index] + (@table[(index + 1) % @table.length] - @table[index]) * (position - index)
      value * @shimmer + @air.tick(@rng.rand * 2 - 1, 5500) * breath
    end
  end

  def voice(seconds, pitch:, vowels:, seed: 73, breath: 0.10, vibrato: 0.012,
    rough: 0.006, scale: 1.0, tremolo: 0, flutter: 0, nasal: false, attack: 0.012, release: 0.040)
    source = Glottis.new(pitch.map(&:last).max * (1.08 + flutter), seed, rough)
    filters = [110, 150, 210, 260, 310].map { |bandwidth| Resonator.new(bandwidth) }
    nose = Resonator.new(110) if nasal
    tracks = 5.times.map { |i| vowels.map { |u, vowel| [u, VOWELS.fetch(vowel)[i] * scale] } }
    samples = render(seconds) do |t, u|
      gargle = flutter * curve([[0, 0], [0.60, 0], [0.80, 1], [1, 1]], u)
      frequency = curve(pitch, u) * (1 + vibrato * Math.sin(TAU * 5.4 * t) + gargle * Math.sin(TAU * 29 * t))
      value = source.tick(frequency, breath)
      filters.each_with_index { |filter, i| value = filter.tick(value, curve(tracks[i], u)) }
      value = value * 0.75 + nose.tick(value, 450) * 0.25 if nose
      value * envelope(t, seconds, attack: attack, release: release) *
        (1 - tremolo * (0.5 + 0.5 * Math.cos(TAU * 7.5 * t))) *
        (1 - gargle * 3 * (0.5 + 0.5 * Math.sin(TAU * 29 * t)))
    end
    rms = Math.sqrt(samples.sum { |v| v * v } / samples.length)
    samples.map { |v| v * 0.18 / rms }
  end

  def noise(seconds, from:, to:, seed: 73, attack: 0.012, decay: 6, highpass: 100)
    rng, low, high = Random.new(seed), Lowpass.new, Lowpass.new
    render(seconds) do |t, u|
      white = rng.rand * 2 - 1
      value = low.tick(white, curve([[0, from], [1, to]], u)) - high.tick(white, highpass)
      value * envelope(t, seconds, attack: attack) * Math.exp(-decay * t)
    end
  end

  def chirp(seconds, from:, to:, decay: 8, partials: [1, 0.12], wobble: 0, vibrato: 0, release: 0.020)
    phase = 0.0
    render(seconds) do |t, u|
      frequency = curve([[0, from], [1, to]], u) *
        (1 + wobble * Math.exp(-t * 10) * Math.sin(TAU * 28 * t) + vibrato * Math.sin(TAU * 5.5 * t))
      phase += TAU * frequency / RATE
      partials.each_with_index.sum { |amplitude, h| amplitude * Math.sin(phase * (h + 1)) } *
        envelope(t, seconds, attack: 0.006, release: release) * Math.exp(-decay * t)
    end
  end

  def bubbles(seconds, starts:, base: 400)
    buffer = Array.new((seconds * RATE).to_i, 0.0)
    starts.each_with_index do |start, i|
      frequency = base + i * 75
      mix(buffer, chirp(0.13, from: frequency, to: frequency * 1.85, decay: 30), at: start, gain: 0.8 - i * 0.07)
    end
    buffer
  end

  def whistle(seconds, from:, to:, bomb: false)
    sound = chirp(seconds, from: from, to: to, decay: 0, partials: [1, 0.025],
      vibrato: bomb ? 0.006 : 0.012, release: bomb ? 0.006 : 0.020)
    mix(sound, noise(seconds, from: 3600, to: 2500, decay: 0, highpass: 1800), gain: 0.035)
    sound.each_with_index.map do |v, i|
      v * envelope(i.fdiv(RATE), seconds, attack: 0.025, release: bomb ? 0.006 : 0.045)
    end
  end

  def effect(name, samples, rms_db: -20)
    raise "Invalid synthesis: #{name}" unless samples.all?(&:finite?)
    low = Lowpass.new
    weights = samples.each_index.map do |i|
      envelope(i.fdiv(RATE), (samples.length - 1).fdiv(RATE), attack: 0.006, release: 0.006)
    end
    samples = samples.each_with_index.map { |v, i| (v - low.tick(v, 20)) * weights[i] }
    dc = samples.sum / weights.sum
    samples.each_index { |i| samples[i] -= dc * weights[i] }
    rms = Math.sqrt(samples.sum { |v| v * v } / samples.length)
    gain = [10**(rms_db / 20.0) / rms, 0.68 / samples.map(&:abs).max].min
    pcm = samples.map { |v| (v * gain * 32_768).round }
    # Distribute the rounding residue inside the cue, keeping exact zero DC and
    # silent endpoints without adding an audible constant or changing its crest.
    residue = pcm.sum
    residue.abs.times do |i|
      index = 160 + i * (pcm.length - 320) / [residue.abs, 1].max
      pcm[index] -= residue <=> 0
    end
    write_pcm(name, pcm.pack("s<*"))
  end

  def squeaks
    oof = voice(0.22, pitch: [[0, 480], [0.45, 410], [1, 365]], vowels: [[0, :uh], [1, :u]], breath: 0.28)
    oof.each_index { |i| oof[i] *= curve([[0, 1], [0.65, 1], [0.9, 0.08], [1, 0]], i.fdiv(oof.length)) }
    mix(oof, noise(0.09, from: 5800, to: 4200, highpass: 2300, decay: 18), at: 0.13, gain: 0.35)
    effect("squeak-oof", oof)
    effect("squeak-ow", voice(0.32, pitch: [[0, 540], [0.18, 575], [1, 370]],
      vowels: [[0, :a], [0.3, :a], [0.86, :u], [1, :u]]))
    effect("squeak-yelp", voice(0.45, pitch: [[0, 450], [0.18, 660], [0.5, 560], [1, 385]],
      vowels: [[0, :i], [0.22, :a], [1, :a]], rough: 0.018, breath: 0.18))
    effect("squeak-eek", voice(0.30, pitch: [[0, 390], [0.7, 510], [1, 550]], vowels: [[0, :i], [1, :i]], breath: 0.12))
    wah = voice(0.90, pitch: [[0, 480], [0.16, 545], [0.6, 425], [1, 320]],
      vowels: [[0, :w], [0.18, :a], [0.6, :a], [0.82, :u], [1, :u]], flutter: 0.22, breath: 0.22)
    mix(wah, bubbles(0.28, starts: [0, 0.075, 0.16], base: 480), at: 0.61, gain: 0.24)
    effect("squeak-wah", wah)

    bye = Array.new((0.60 * RATE).to_i, 0.0)
    [0.0, 0.29].each_with_index do |start, i|
      mix(bye, noise(0.032, from: 800, to: 1400, attack: 0.003, decay: 80), at: start, gain: 0.42)
      mix(bye, voice(0.27, pitch: [[0, 520 - i * 45], [0.28, 550 - i * 55], [1, 440 - i * 65]],
        vowels: [[0, :uh], [0.18, :a], [0.40, :a], [0.88, :i], [1, :i]], seed: 91 + i), at: start + 0.024)
    end
    effect("squeak-byebye", bye)
    effect("squeak-yay", voice(0.50, pitch: [[0, 400], [0.42, 565], [1, 450]],
      vowels: [[0, :i], [0.22, :e], [0.64, :e], [1, :i]]))
    giggle = Array.new((0.60 * RATE).to_i, 0.0)
    [0, 0.205, 0.405].each_with_index do |start, i|
      mix(giggle, voice(0.185, pitch: [[0, 510 - i * 40], [1, 455 - i * 40]],
        vowels: [[0, :e], [1, :e]], seed: 110 + i, breath: 0.65, attack: 0.028, release: 0.065), at: start)
      mix(giggle, noise(0.055, from: 2300, to: 1700, decay: 30), at: start, gain: 0.10)
    end
    effect("squeak-giggle", giggle)
  end

  def foley
    effect("slide-whistle-up", whistle(0.45, from: 500, to: 1600), rms_db: -22)
    effect("slide-whistle-down", whistle(0.80, from: 1500, to: 350), rms_db: -22)
    boing = chirp(0.50, from: 240, to: 125, decay: 6, partials: [1, 0.52, 0.27, 0.19, 0.10], wobble: 0.34)
    filter = Resonator.new(380)
    effect("boing", boing.each_with_index.map { |v, i| filter.tick(v, 1000 + 500 * Math.exp(-i.fdiv(RATE) * 9)) }, rms_db: -21)
    pop = chirp(0.12, from: 1000, to: 360, decay: 42, partials: [1, 0.20])
    mix(pop, noise(0.035, from: 2600, to: 850, attack: 0.003, decay: 65), gain: 0.20)
    effect("pop", pop, rms_db: -21)
    effect("poof", noise(0.45, from: 2000, to: 450, attack: 0.060, decay: 10), rms_db: -23)
    effect("blub", bubbles(0.80, starts: [0, 0.14, 0.245, 0.445, 0.64]), rms_db: -22)

    fuse = noise(0.70, from: 5000, to: 4300, highpass: 2400, attack: 0.040, decay: 0)
    rng = Random.new(731)
    16.times do |i|
      mix(fuse, noise(0.018, from: 6000, to: 2100, highpass: 1200, attack: 0.003, decay: 120, seed: i + 731),
        at: 0.025 + rng.rand * 0.64, gain: 0.5 + rng.rand)
    end
    effect("fuse", fuse, rms_db: -25)
    ice = noise(0.60, from: 6000, to: 3200, highpass: 2300, decay: 9).map { |v| v * 0.08 }
    [1450, 2087, 2791, 3503, 4379, 5297].each_with_index do |frequency, i|
      mix(ice, chirp(0.42, from: frequency, to: frequency * 0.985, decay: 13, partials: [1]),
        at: i * 0.033, gain: 0.5 / (1 + i * 0.35))
    end
    effect("ice", ice, rms_db: -25)
    thwip = noise(0.18, from: 5500, to: 450, attack: 0.016, decay: 22, highpass: 300)
    mix(thwip, chirp(0.12, from: 760, to: 130, decay: 32), gain: 0.26)
    effect("thwip", thwip, rms_db: -22)
    whoosh = noise(0.35, from: 1100, to: 5500, attack: 0.13, decay: 5, highpass: 700)
    effect("whoosh", whoosh, rms_db: -23)
    effect("bomb-whistle", whistle(1.10, from: 2000, to: 600, bomb: true), rms_db: -23)

    phase, rng, low = 0.0, Random.new(917), Lowpass.new
    plane = render(1.80) do |t, u|
      frequency = curve([[0, 185], [0.38, 180], [0.62, 120], [1, 108]], u)
      phase += TAU * frequency / RATE
      drone = (1..9).sum { |h| Math.sin(phase * h) / h**1.4 }
      distance = 0.12 + 0.88 * Math.exp(-((u - 0.48) / 0.24)**2)
      (drone * (0.73 + 0.27 * Math.sin(TAU * 31 * t)) + low.tick(rng.rand * 2 - 1, 1600) * 0.14) *
        distance * envelope(t, 1.80, attack: 0.14, release: 0.26)
    end
    effect("plane", plane, rms_db: -23)

    choir = Array.new((1.80 * RATE).to_i, 0.0)
    [261.6256, 329.6276, 391.9954, 523.2511].each_with_index do |frequency, i|
      part = voice(1.68, pitch: [[0, frequency * 0.98], [0.18, frequency], [1, frequency]],
        vowels: [[0, :a], [1, :a]], seed: 330 + i, scale: 0.90 + i * 0.055,
        vibrato: 0.009 + i * 0.001, breath: 0.28, attack: 0.32, release: 0.38)
      mix(choir, part, at: i * 0.008, gain: 0.58)
      mix(choir, part, at: 0.09 + i * 0.008, gain: 0.09)
    end
    mix(choir, noise(0.35, from: 3100, to: 1200, attack: 0.045, decay: 12), at: 1.45, gain: 0.055)
    effect("choir", choir)
    effect("baa", voice(0.70, pitch: [[0, 235], [0.25, 290], [0.6, 245], [1, 200]],
      vowels: [[0, :ae], [1, :ae]], scale: 0.86, tremolo: 0.62, rough: 0.028, breath: 0.20, nasal: true))
    effect("moo", voice(1.00, pitch: [[0, 110], [0.30, 121], [1, 90]],
      vowels: [[0, :w], [0.26, :u], [1, :u]], scale: 0.76, vibrato: 0.018, breath: 0.18, attack: 0.09, release: 0.12))

    raspberry = noise(0.50, from: 2200, to: 950, decay: 1, highpass: 90)
    raspberry.each_index do |i|
      t = i.fdiv(RATE)
      pulse = (0.5 + 0.5 * Math.sin(TAU * (30 * t + 2 * t * t)))**3
      raspberry[i] = (raspberry[i] * 0.8 + Math.sin(TAU * 120 * t) * 0.12) * pulse
    end
    effect("pfft", raspberry, rms_db: -23)
    trombone = Array.new(2 * RATE, 0.0)
    [[0, 0.30, 293.665], [0.34, 0.30, 277.183], [0.68, 0.30, 261.626], [1.02, 0.98, 246.942]].each_with_index do |(start, seconds, frequency), i|
      phase, filter = 0.0, Resonator.new(180)
      note = render(seconds) do |t, u|
        vibrato = i == 3 ? 0.035 * curve([[0, 0], [0.3, 0.1], [0.65, 1], [1, 1]], u) : 0.005
        phase += TAU * frequency * (1 + vibrato * Math.sin(TAU * 5.8 * t)) / RATE
        saw = (1..14).sum { |h| Math.sin(phase * h) / h**1.15 }
        value = filter.tick(saw, curve([[0, 520], [0.22, 1350], [0.65, 850], [1, 450]], u))
        value * envelope(t, seconds, attack: 0.025, release: 0.065)
      end
      mix(trombone, note, at: start)
    end
    effect("sad-trombone", trombone, rms_db: -22)
  end
end

CartoonAudio.squeaks
CartoonAudio.foley

source = File.join(ROOT, "assets/audio/source/kenney")
manifest = JSON.parse(File.read(File.join(source, "manifest.json"), encoding: Encoding::UTF_8))
manifest.fetch("cues").each do |cue|
  master = File.join(source, cue.fetch("master"))
  raise "Audio master checksum changed: #{master}" unless Digest::SHA256.file(master).hexdigest == cue.fetch("master_sha256")
  FileUtils.cp(master, File.join(ROOT, "assets/audio", "#{cue.fetch('cue')}.wav"))
end
puts "Built #{Dir[File.join(ROOT, 'assets/audio/*.wav')].length} cues: original synthesis and #{manifest.fetch('cues').length} CC0 Kenney samples."
