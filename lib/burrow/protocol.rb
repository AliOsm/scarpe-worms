# frozen_string_literal: true

module Burrow
  module Protocol
    MAX_CLIENT = 24 * 1024
    MAX_SERVER = 512 * 1024
    WRITE_CHUNK = 16 * 1024
    module_function

    # Socket write counts are bytes. Keep queued frames binary so slicing after a
    # partial TLS write cannot discard extra characters in a UTF-8 message.
    def encode(value) = JSON.generate(value).b + "\n".b
    def decode(line, limit: MAX_CLIENT)
      raise RuleError, "Message too large." if line.bytesize > limit
      value = JSON.parse(line, max_nesting: 12, allow_nan: false)
      raise RuleError, "Messages must be objects with a type." unless value.is_a?(Hash) && value["type"].is_a?(String)
      value
    rescue JSON::ParserError, JSON::NestingError
      raise RuleError, "Invalid JSON message."
    end

    def name(value)
      unless value.is_a?(String) && value.valid_encoding? && value.strip.length.between?(2, 24) && !value.match?(/[[:cntrl:]]/)
        raise RuleError, "Choose a name with 2–24 printable characters."
      end
      value.strip
    end
  end
end
