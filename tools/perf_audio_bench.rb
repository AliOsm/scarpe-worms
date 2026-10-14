# frozen_string_literal: true
# Reproducible OpenAL submission/voice-pressure and delayed-deadline probes.
# Run under .perf-round/bin/bench with Ruby 3.4.7. Set BURROW_BENCH_SOURCE to
# an archived source tree; dependencies always come from this worktree's bundle.
# Examples: bundle exec ruby tools/perf_audio_bench.rb --scenario combat --output /path/result.json
#           ... --scenario deadline (real App#update, controlled 9 ms frame work)
#           ... --scenario dispatch (unpaced API cost; deliberately saturated)
# Linux defaults to the null mixer. ALSOFT_DRIVERS=wave and ALSOFT_CONF can retain
# mixed PCM. Neither backend measures acoustic/device latency. Instrumentation
# is identical in both arms; raw cue rows and all steals remain in the report.
require "optparse"
require "json"
options = {scenario: "combat", output: nil, cycles: 2}
OptionParser.new do |parser|
  parser.on("--scenario NAME") { |v| options[:scenario] = v }
  parser.on("--output PATH") { |v| options[:output] = v }
  parser.on("--cycles N", Integer) { |v| options[:cycles] = v }
end.parse!
root = File.expand_path(ENV.fetch("BURROW_BENCH_SOURCE", ".."), __dir__)
ENV["ALSOFT_DRIVERS"] ||= "null" if RUBY_PLATFORM.include?("linux")
require File.join(root, "lib/burrow")
require File.join(root, "lib/burrow/client/app")

module AudioProbe
  attr_reader :probe_rows, :probe_steals, :probe_drops, :probe_calls

  def probe_start
    @probe_rows, @probe_steals, @probe_drops, @probe_calls = [], [], Hash.new(0), Hash.new(0)
    @probe_states, @probe_ends, @probe_names = {}, {}, {}
    owner = self
    hook = Module.new
    %i[alSourceStop alSourcei alSourcef alSource3f alSourcePlay alGetSourcei].each do |name|
      hook.define_method(name) do |*args|
        owner.probe_al_before(name, args)
        at = Burrow.clock
        result = super(*args)
        elapsed = Burrow.clock - at
        owner.probe_al_after(name, args, elapsed)
        result
      end
    end
    @al.singleton_class.prepend(hook)
  end

  def probe_al_before(method, args)
    return if @probe_finished
    source = args.first
    if method == :alSourceStop && @probe_states[source] == 0x1012
      @probe_steals << {cue: @probe_names[source], replacement: @probe_name,
        remaining_ms: [(@probe_ends.fetch(source, Burrow.clock) - Burrow.clock) * 1000, 0].max}
    end
  end

  def probe_al_after(method, args, elapsed)
    return if @probe_finished
    @probe_calls[method] += 1
    @probe_al_ms = (@probe_al_ms || 0) + elapsed * 1000
    source = args.first
    case method
    when :alGetSourcei then @probe_states[source] = args.last.read_int
    when :alSourceStop then @probe_states[source] = 0x1014
    when :alSourcePlay
      @probe_submitted = Burrow.clock
      @probe_states[source] = 0x1012
      @probe_names[source] = @probe_name
      @probe_ends[source] = @probe_submitted + @seconds.fetch(@probe_name, 0) / (@probe_pitch || 1)
    end
  end

  def play(name, **kwargs)
    return super unless @probe_rows
    before, cpu = Burrow.clock, Process.clock_gettime(Process::CLOCK_THREAD_CPUTIME_ID)
    @probe_name, @probe_pitch, @probe_al_ms, @probe_submitted = name, kwargs.fetch(:pitch, 1), 0, nil
    busy = @probe_ends.values.count { |at| at > before }
    result = super
    duration = (Burrow.clock - before) * 1000
    cpu_ms = (Process.clock_gettime(Process::CLOCK_THREAD_CPUTIME_ID) - cpu) * 1000
    @probe_drops[:play_rejected] += 1 unless result
    @probe_rows << {cue: name, origin: @probe_origin || (kwargs[:immediate] ? "predicted" : "direct"),
      at: Time.now.to_f, lateness_ms: @probe_submitted && @probe_due && (@probe_submitted - @probe_due) * 1000,
      play_ms: duration, cpu_ms: cpu_ms, al_ms: @probe_al_ms, played: !!result, busy_estimate: busy}
    result
  end

  def event(*args, **kwargs)
    previous = [@probe_origin, @probe_due]
    @probe_origin, @probe_due = "event", Burrow.clock
    super
  ensure
    @probe_origin, @probe_due = previous
  end

  def update(now = Burrow.clock)
    previous = [@probe_origin, @probe_due]
    @probe_due_entries = (@queue || []).select { |at, *_| at <= now }
    @probe_drops[:stale] += @probe_due_entries.count { |at, *_| now - at >= 0.5 } if @probe_drops
    @probe_in_update = true
    super
  ensure
    @probe_in_update = false
    @probe_origin, @probe_due = previous
  end

  def speak(name, **kwargs)
    if @probe_in_update
      index = @probe_due_entries.index { |_, cue, _| cue == name }
      @probe_due = @probe_due_entries.delete_at(index).first if index
      @probe_origin = "delayed"
    end
    previous_count = @probe_rows&.length
    result = super
    if @probe_rows && previous_count == @probe_rows.length
      @probe_drops[kwargs[:chatter] && Burrow.clock < (@voice_until || 0) ? :chatter : :squeak_cap] += 1
    end
    result
  end

  def later(name, delay, **kwargs)
    overflow = delay > 0 && (@queue || []).length >= self.class::QUEUE_LIMIT
    result = super
    @probe_drops[:queue_overflow] += 1 if overflow && @probe_drops
    result
  end

  def probe_finish = @probe_finished = true
end
Burrow::Client::Audio.prepend(AudioProbe)

def stats(values)
  sorted = values.compact.sort
  return {n: 0} if sorted.empty?
  {n: sorted.length, median: sorted[sorted.length / 2], p95: sorted[[(sorted.length * 0.95).ceil - 1, 0].max],
    min: sorted.first, max: sorted.last, iqr: sorted[(sorted.length * 0.75).floor] - sorted[(sorted.length * 0.25).floor]}
end

# Retain the production update ordering, while replacing unrelated GUI/host work
# with a repeatable 9 ms delay. This tests whether cues due during work wait again.
class DeadlineApp < Burrow::Client::App
  def initialize(audio)
    @audio, @frame, @page = audio, 0, :probe
    @shoes = Struct.new(:width, :height).new(1, 1)
    @dimensions = [1, 1]
    @frame_log = Burrow::Client::Diagnostics::FrameLog.new(directory: nil)
    @activity = Struct.new(:active?).new(false)
  end
  def update_activity = sleep(0.009)
end

audio = Burrow::Client::Audio.new({"muted" => false, "music" => false, "volume" => 0.4})
abort "OpenAL unavailable: #{audio.error}" unless audio.available
audio.probe_start
bursts, intervals = [], []
started, previous_frame = Burrow.clock, nil
case options[:scenario]
when "combat"
  state = {"team" => "p0", "turn" => 4, "phase" => "settling",
    "teams" => 6.times.map { |i| {"id" => "p#{i}", "color" => i} },
    "worms" => 36.times.map { |i| {"id" => "w#{i}", "team" => "p#{i / 6}", "hp" => i % 6 < 3 ? 0 : 20, "x" => 300 + i * 10, "y" => 500} }}
  # A heavy blast, a chain blast 180 ms later, then drowning and delayed graves.
  schedule = options[:cycles].times.flat_map do |cycle|
    base = cycle * 3.5
    events = [[base, {"kind" => "fire", "weapon" => "banana", "worm" => "w0"}],
      [base + 0.10, {"kind" => "explosion", "radius" => 92}]]
    [6, 7, 12].each { |i| events << [base + 0.10, {"kind" => "defeat", "worm" => "w#{i}"}] }
    [9, 10, 15].each { |i| events << [base + 0.28, {"kind" => "damage", "worm" => "w#{i}", "amount" => 45}] }
    events << [base + 0.28, {"kind" => "explosion", "radius" => 50}]
    [18, 19, 24].each { |i| events << [base + 0.45, {"kind" => "splash", "worm" => "w#{i}"}] }
    events << [base + 0.63, {"kind" => "explosion", "radius" => 92}]
    events << [base + 0.80, {"kind" => "critter_release", "weapon" => "cows"}]
    events
  end.sort_by(&:first).each_with_index.map { |(at, event), i| [at, event.merge("id" => 100 + i, "x" => 500, "y" => 500)] }
  frame = 0
  while (now = Burrow.clock) - started < options[:cycles] * 3.5
    intervals << (now - previous_frame) * 1000 if previous_frame
    previous_frame = now
    audio.frame(now) if audio.respond_to?(:frame)
    at = Burrow.clock
    while schedule.first && schedule.first[0] <= now - started
      _, event = schedule.shift
      audio.event(event, state: state)
    end
    audio.update(now)
    bursts << (Burrow.clock - at) * 1000
    frame += 1
    sleep([started + frame / 60.0 - Burrow.clock, 0].max)
  end
when "deadline"
  app = DeadlineApp.new(audio)
  300.times do |frame|
    at = Burrow.clock
    # Vary the deadline's phase within the frame; each cue is >65 ms apart.
    audio.send(:later, "click", (frame % 17 + 0.5) / 1000.0) if frame % 6 == 0
    app.update
    sleep([started + (frame + 1) / 60.0 - Burrow.clock, 0].max)
    intervals << (Burrow.clock - at) * 1000
  end
when "dispatch"
  10_000.times { |i| audio.play(i.even? ? "explosion-heavy" : "squeak-yelp", throttle: false) }
else
  abort "Unknown scenario #{options[:scenario]}"
end
audio.probe_finish
audio.close
rows = audio.probe_rows
report = {schema: 1, source: root, ruby: RUBY_DESCRIPTION, platform: RUBY_PLATFORM,
  scenario: options[:scenario], mixer: ENV["ALSOFT_DRIVERS"] || "platform default", voice_limit: Burrow::Client::Audio::MAX_VOICES,
  elapsed: Burrow.clock - started, cues: rows.length, played: rows.count { |row| row[:played] }, steals: audio.probe_steals,
  drops: audio.probe_drops, al_calls: audio.probe_calls,
  metrics: {play_ms: stats(rows.select { |r| r[:played] }.map { |r| r[:play_ms] }),
    play_cpu_ms: stats(rows.select { |r| r[:played] }.map { |r| r[:cpu_ms] }), al_ms: stats(rows.map { |r| r[:al_ms] }),
    delayed_lateness_ms: stats(rows.select { |r| r[:origin] == "delayed" }.map { |r| r[:lateness_ms] }),
    event_lateness_ms: stats(rows.select { |r| r[:origin] == "event" }.map { |r| r[:lateness_ms] }),
    frame_interval_ms: stats(intervals), burst_ms: stats(bursts)}, rows: rows}
File.write(options.fetch(:output), JSON.pretty_generate(report) + "\n")
puts JSON.generate(report.reject { |key, _| %i[rows steals].include?(key) }.merge(steals: audio.probe_steals.length))
