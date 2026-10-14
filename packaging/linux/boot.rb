# frozen_string_literal: true

Encoding.default_external = Encoding::UTF_8
require_relative "check_runtime"
require "fileutils"
File.umask(0o077)
data = ENV.fetch("BURROW_DATA_DIR")
FileUtils.mkdir_p(data, mode: 0o700)
Dir.chdir(data)
ENV["SCARPE_NATIVE_CACHE"] = File.join(data, "cache")
require_relative "app/lib/burrow"
require_relative "app/lib/burrow/client/diagnostics"
Burrow::Client::Diagnostics.start
require "scarpe"
Shoes.run_app(File.join(__dir__, "app/game.rb"))
