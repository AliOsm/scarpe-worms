# frozen_string_literal: true

# Keep direct boot/script entry points consistent with launch.sh's -EUTF-8.
Encoding.default_external = Encoding::UTF_8
# All writes live outside the signed, movable app bundle.
require "fileutils"
File.umask(0o077)
resources = __dir__
data_directory = ENV.fetch("BURROW_DATA_DIR") { File.join(Dir.home, "Library/Application Support/burrow-brigade") }
FileUtils.mkdir_p(data_directory, mode: 0o700)
ENV["BURROW_DATA_DIR"] = data_directory
Dir.chdir(data_directory)
ENV["SCARPE_DISPLAY_SERVICE"] = "native"
ENV["SCARPE_NATIVE_CACHE"] = File.join(data_directory, "cache")
require File.join(resources, "app/lib/burrow")
require File.join(resources, "app/lib/burrow/client/diagnostics")
Burrow::Client::Diagnostics.start
require "scarpe"
Shoes.run_app(File.join(resources, "app/game.rb"))
