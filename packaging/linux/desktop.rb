# frozen_string_literal: true

require "fileutils"
bundle = File.expand_path("..", __dir__)
base = ENV.fetch("XDG_DATA_HOME", File.join(Dir.home, ".local/share"))
desktop = File.join(base, "applications/burrow-brigade.desktop")
if ARGV.first == "--uninstall-desktop"
  FileUtils.rm_f(desktop)
  puts "Removed #{desktop}. Saved games are kept."
  exit
end
abort "Desktop entry paths cannot contain newlines." if bundle.match?(/[\r\n]/)
# The Desktop Entry specification applies both string and Exec quoting. Percent
# characters must be doubled so an installation path never becomes a field code.
executable = File.join(bundle, "burrow-brigade").gsub(/([\\"`$])/) { |c| "\\#{c}" }.gsub("%", "%%")
executable = executable.gsub("\\") { "\\\\" }
icon = File.join(bundle, "burrow-brigade.png").gsub("\\") { "\\\\" }
content = File.read(File.join(bundle, "burrow-brigade.desktop"))
content = content.sub(/^Exec=.*$/) { "Exec=\"#{executable}\"" }
content = content.sub(/^Icon=.*$/) { "Icon=#{icon}" }
FileUtils.mkdir_p(File.dirname(desktop))
File.write(desktop, content)
File.chmod(0o644, desktop)
puts "Installed #{desktop}. Run this command again if you move the game folder."
