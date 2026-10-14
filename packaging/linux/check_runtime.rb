# frozen_string_literal: true

abort "Packaged Ruby must be 4.0.7" unless RUBY_VERSION == "4.0.7"

require "fiddle"
require "json"
require "openssl"
require "ffi"

headless = ENV["SCARPE_NATIVE_HEADLESS"] == "1"
libraries = %w[libgcc_s.so.1 libstdc++.so.6 libopenal.so.1]
unless headless
  libraries << "libxkbcommon.so.0"
  if ENV["WAYLAND_DISPLAY"] && ENV["WINIT_UNIX_BACKEND"] != "x11"
    libraries.concat(%w[libwayland-client.so.0 libwayland-cursor.so.0])
  elsif ENV["DISPLAY"]
    libraries.concat(%w[libX11.so.6 libX11-xcb.so.1 libXcursor.so.1 libXi.so.6
      libXrandr.so.2 libxcb.so.1 libxkbcommon-x11.so.0])
  else
    abort "Burrow Brigade needs an X11 or Wayland desktop (DISPLAY or WAYLAND_DISPLAY is unset)."
  end
end
missing = libraries.filter_map do |name|
  begin
    Fiddle.dlopen(name)
    nil
  rescue Fiddle::DLError => error
    "#{name}: #{error.message}"
  end
end
unless missing.empty?
  abort "Burrow Brigade is missing desktop runtime libraries:\n#{missing.join("\n")}\n" \
    "Install the prerequisites in READ-ME.txt or docs/LINUX.md; Ruby and OpenAL are already bundled."
end
if $PROGRAM_NAME == __FILE__ && !ARGV.include?("--quiet")
  puts JSON.generate(ruby: RUBY_VERSION, openssl: OpenSSL::OPENSSL_VERSION,
    ffi: FFI::VERSION, libraries: libraries, headless: headless)
end
