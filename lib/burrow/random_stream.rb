# frozen_string_literal: true

module Burrow
  # A small explicit PRNG makes checkpoint/replay state portable and JSON-only.
  class RandomStream
    attr_reader :state
    def initialize(seed) = (@state = (seed & 0xffffffff).nonzero? || 1)
    def rand(limit = nil)
      @state ^= (@state << 13) & 0xffffffff
      @state ^= @state >> 17
      @state ^= (@state << 5) & 0xffffffff
      value = @state.fdiv(0x100000000)
      case limit
      when Integer then (value * limit).floor
      when Range
        width = limit.end - limit.begin + (limit.exclude_end? ? 0 : 1)
        limit.begin + (value * width).floor
      else value
      end
    end
  end
end
