# frozen_string_literal: true

Encoding.default_external = Encoding::UTF_8
require "fileutils"
require File.join(__dir__, "app/lib/burrow")
data = Burrow.data_dir
FileUtils.mkdir_p(data)
ENV["BURROW_DATA_DIR"] = data
ENV["SCARPE_DISPLAY_SERVICE"] = "native"
ENV["SCARPE_NATIVE_CACHE"] = File.join(data, "cache")
Dir.chdir(data)
require File.join(__dir__, "app/lib/burrow/client/diagnostics")
Burrow::Client::Diagnostics.start
require "scarpe"
# The verifier injects automation into the normal launcher/boot/game path.
require ENV.fetch("BURROW_WINDOWS_PROBE") if ENV["BURROW_WINDOWS_PROBE"]
Shoes.run_app(File.join(__dir__, "app/game.rb"))
