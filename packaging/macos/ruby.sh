#!/bin/bash
# Shared interpreter entry point for the app and packaged verification scripts.
set -eu
RES="$(cd "$(dirname "$0")" && pwd -P)"

# -EUTF-8 alone leaves startup RUBYLIB paths tagged US-ASCII under Finder/C
# locales. RubyGems can then fail on a relocated Unicode installation directory.
# macOS supplies this locale; select it before Ruby reads any paths or gems.
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

# Traveling Ruby environment contract, also inherited by the host/terrain workers.
export ORIG_TERMINFO="${TERMINFO:-}" ORIG_RUBYOPT="${RUBYOPT:-}" ORIG_RUBYLIB="${RUBYLIB:-}"
export ORIG_DYLD_LIBRARY_PATH="${DYLD_LIBRARY_PATH:-}"
export OLD_SSL_CERT_DIR="${SSL_CERT_DIR:-}" OLD_SSL_CERT_FILE="${SSL_CERT_FILE:-}"
export TERMINFO=/usr/share/terminfo
export SSL_CERT_FILE="$RES/runtime/ruby/lib/ca-bundle.crt"
unset SSL_CERT_DIR BUNDLE_GEMFILE BUNDLE_PATH BUNDLE_BIN_PATH DYLD_LIBRARY_PATH
export RUBYOPT="-rtraveling_ruby_restore_environment"
export GEM_HOME="$RES/runtime/gems" GEM_PATH="$RES/runtime/gems"
RUBY_LIB="$RES/runtime/ruby/lib/ruby"
export RUBYLIB="$RES/scarpe/lib:$RES/scarpe/lacci/lib:$RES/scarpe/scarpe-components/lib:$RES/gems/ffi/lib:$RES/gems/chunky_png/lib:$RES/gems/base64/lib:$RES/gems/logger/lib:$RES/gems/fastimage/lib:$RUBY_LIB/site_ruby/3.4.0:$RUBY_LIB/site_ruby/3.4.0/arm64-darwin22:$RUBY_LIB/site_ruby:$RUBY_LIB/vendor_ruby/3.4.0:$RUBY_LIB/vendor_ruby/3.4.0/arm64-darwin22:$RUBY_LIB/vendor_ruby:$RUBY_LIB/3.4.0:$RUBY_LIB/3.4.0/arm64-darwin22"
export SCARPE_NATIVE_BIN="$RES/../MacOS/scarpe-native"
export SCARPE_DISPLAY_SERVICE=native
export BURROW_RUBY="$RES/runtime/ruby/bin.real/ruby"
exec "$BURROW_RUBY" -EUTF-8 "$@"
