#!/bin/bash
# Shared interpreter entry point for the app and packaged verification scripts.
set -eu
RES="$(cd "$(dirname "$0")" && pwd -P)"

# -EUTF-8 alone leaves startup RUBYLIB paths tagged US-ASCII under Finder/C
# locales. RubyGems can then fail on a relocated Unicode installation directory.
# macOS supplies this locale; select it before Ruby reads any paths or gems.
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

# The host and terrain workers inherit this isolated runtime environment.
export SSL_CERT_FILE="$RES/runtime/ruby/lib/ca-bundle.crt"
unset SSL_CERT_DIR BUNDLE_GEMFILE BUNDLE_PATH BUNDLE_BIN_PATH DYLD_LIBRARY_PATH RUBYOPT RUBYGEMS_GEMDEPS
export GEM_HOME="$RES/runtime/ruby/lib/ruby/gems/4.0.0" GEM_PATH="$RES/runtime/ruby/lib/ruby/gems/4.0.0"
export RUBYLIB="$RES/scarpe/lib:$RES/scarpe/lacci/lib:$RES/scarpe/scarpe-components/lib:$RES/gems/ffi/lib:$RES/gems/chunky_png/lib:$RES/gems/base64/lib:$RES/gems/logger/lib:$RES/gems/fastimage/lib"
export SCARPE_NATIVE_BIN="$RES/../MacOS/scarpe-native"
export SCARPE_DISPLAY_SERVICE=native
export BURROW_RUBY="$RES/runtime/ruby/bin/ruby"
exec "$BURROW_RUBY" -EUTF-8 "$@"
