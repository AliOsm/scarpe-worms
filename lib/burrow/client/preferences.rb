# frozen_string_literal: true

module Burrow
  module Client
    class Preferences
      DEFAULT = {"name" => "Pip", "volume" => 0.7, "music" => true, "muted" => false,
        "motion" => true, "allow_lan" => false, "endpoint" => "tls://localhost:4388",
        "fingerprint" => "", "sessions" => {}, "config" => Config::DEFAULT}.freeze
      attr_reader :values

      def initialize(path = File.join(Burrow.data_dir, "preferences.json"))
        @path = path
        value = File.exist?(path) ? JSON.parse(File.read(path, encoding: Encoding::UTF_8)) : {}
        @values = Marshal.load(Marshal.dump(DEFAULT)).merge(value.is_a?(Hash) ? value.slice(*DEFAULT.keys) : {})
        @values["config"] = Config.new(@values["config"]).to_h
        @values["sessions"] = {} unless @values["sessions"].is_a?(Hash)
        @values["volume"] = 0.7 unless @values["volume"].is_a?(Numeric) && @values["volume"].between?(0, 1)
      rescue SystemCallError, JSON::ParserError, RuleError
        @values = Marshal.load(Marshal.dump(DEFAULT))
      end

      def [](key) = values[key]
      def []=(key, value)
        values[key] = value
        save
      end
      def save = Burrow.atomic_json(@path, values)
    end
  end
end
