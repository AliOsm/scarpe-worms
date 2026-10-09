# frozen_string_literal: true
# Run with Ruby 3.4+; optional first argument names an extracted app bundle.
require "json"
require "fiddle"
module Scarpe
  module Native; end
end
path = ARGV[0] ? File.join(ARGV[0], "Contents/Resources/scarpe/lib/scarpe/native/deadline_wait.rb") :
  File.expand_path("../vendor/scarpe/lib/scarpe/native/deadline_wait.rb", __dir__)
require File.expand_path(path)

def summary(values)
  sorted = values.sort
  {samples: values.size, mean_ms: values.sum / values.size, p95_ms: sorted[(sorted.size * 0.95).floor], max_ms: sorted.last}
end

reader, writer = IO.pipe
waiter = Scarpe::Native::DeadlineWait.new([reader])
report = {ruby: RUBY_VERSION, platform: RUBY_PLATFORM, backend: waiter.backend,
  requested_ms: 10, macos_execution: RUBY_PLATFORM.include?("darwin"), timer_slack_ms: 0}
begin
  if RUBY_PLATFORM.include?("linux")
    prctl = Fiddle::Function.new(Fiddle::Handle::DEFAULT["prctl"],
      [Fiddle::TYPE_INT, *Array.new(4, Fiddle::TYPE_LONG)], Fiddle::TYPE_INT)
    original = prctl.call(30, 0, 0, 0, 0)
    raise "Could not set timer slack" unless prctl.call(29, 100_000_000, 0, 0, 0).zero?
    report[:timer_slack_ms] = 100
  end
  [:ordinary_timeout, :deadline_descriptor].each do |mode|
    samples = 60.times.map do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      mode == :ordinary_timeout ? IO.select([reader], nil, nil, 0.01) : waiter.wait(0.01)
      (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000
    end
    report[mode] = summary(samples)
  end
  puts JSON.pretty_generate(report)
  raise "No precise backend" if waiter.backend == "select_timeout"
  raise "Deadline waits are stalling" unless report[:deadline_descriptor][:p95_ms] < 25
ensure
  prctl.call(29, original, 0, 0, 0) if original && original >= 0
  waiter.close
  reader.close
  writer.close
end
