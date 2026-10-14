# frozen_string_literal: true
# Supplement check_rendering's ordinary game capture with a labeled, synthetic
# reaction burst on the already-open real device. This is submission/voice-pool
# evidence only: these extra events are not host simulation or visual playback.
# The ordinary combat/pan/zoom stages and their timing gates are unchanged.
module PerfAudioScenario
  def self.run(audio)
    al = audio.instance_variable_get(:@al)
    al.attach_function(:alGetError, [], :int) unless al.respond_to?(:alGetError)
    raise "OpenAL rejected initialization/playback before the stress probe" unless al.alGetError.zero?
    # Profile only this synthetic appendix, after the unchanged cadence stages.
    # Bound the rows and retain no source IDs, buffers, or event/player payloads.
    collecting = true
    calls = Hash.new { |hash, name| hash[name] = [] }
    hook = Module.new
    %i[alSourceStop alSourcei alSourcef alSource3f alSourcePlay alGetSourcei].each do |name|
      hook.define_method(name) do |*args|
        at = Burrow.clock
        result = super(*args)
        calls[name] << (Burrow.clock - at) * 1000 if collecting && calls[name].length < 4096
        result
      end
    end
    al.singleton_class.prepend(hook)
    state = {"team" => "p0", "turn" => 4, "phase" => "settling",
      "teams" => 6.times.map { |i| {"id" => "p#{i}", "color" => i} },
      "worms" => 36.times.map { |i| {"id" => "w#{i}", "team" => "p#{i / 6}", "hp" => i % 6 < 3 ? 0 : 20,
        "x" => 300 + i * 10, "y" => 500} }}
    groups = [
      [0.0, [{"kind" => "fire", "weapon" => "banana", "worm" => "w0"}]],
      [0.1, [{"kind" => "explosion", "radius" => 92}] + [6, 7, 12].map { |i| {"kind" => "defeat", "worm" => "w#{i}"} }],
      [0.28, [9, 10, 15].map { |i| {"kind" => "damage", "worm" => "w#{i}", "amount" => 45} } + [{"kind" => "explosion", "radius" => 50}]],
      [0.45, [18, 19, 24].map { |i| {"kind" => "splash", "worm" => "w#{i}"} }],
      [0.63, [{"kind" => "explosion", "radius" => 92}]],
      [0.80, [{"kind" => "critter_release", "weapon" => "cows"}]]
    ]
    started, previous, count = Time.now.to_f, 0, 0
    groups.each do |at, events|
      yield(at - previous) if at > previous
      previous = at
      events.each do |event|
        audio.event(event.merge("id" => 100 + count, "x" => 500, "y" => 500), state: state)
        count += 1
      end
    end
    yield(2.7)
    error = al.alGetError
    raise "OpenAL rejected a stress-probe call (#{error})" unless error.zero?
    costs = calls.transform_values do |values|
      sorted = values.sort
      {n: sorted.length, median_ms: sorted[sorted.length / 2], p95_ms: sorted[[(sorted.length * 0.95).ceil - 1, 0].max],
        max_ms: sorted.last, total_ms: sorted.sum}
    end
    {from: started, to: Time.now.to_f, events: count,
      openal_error: error, openal_calls: costs,
      description: "Synthetic multi-kill/drowning cues on the real context, separate from visual/host stages"}
  ensure
    collecting = false
  end
end
