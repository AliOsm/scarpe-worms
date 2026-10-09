#!/bin/bash
set -eu
RES="$(cd "$(dirname "$0")" && pwd -P)"
LOG_DIR="${BURROW_LOG_DIR:-$HOME/Library/Logs/Burrow Brigade}"
umask 077
mkdir -p "$LOG_DIR"
if [ -f "$LOG_DIR/launcher.log" ] && [ "$(wc -c < "$LOG_DIR/launcher.log")" -gt 5242880 ]; then
  mv -f "$LOG_DIR/launcher.log" "$LOG_DIR/launcher.log.1"
fi
exec >>"$LOG_DIR/launcher.log" 2>&1
printf '\nBurrow Brigade starting at %s\n' "$(date -u '+%Y-%m-%d %H:%M:%S UTC')"

# Same Traveling Ruby environment contract as Scarpe's native packager.
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
# Traveling Ruby's RbConfig points to bin/ruby, which is a wrapper omitted from
# the bundle. Workers inherit the actual relocatable interpreter and load paths.
export BURROW_RUBY="$RES/runtime/ruby/bin.real/ruby"
# Finder launches have no guaranteed shell locale. Configure Ruby before it
# reads paths, standard streams or libraries; workers pass the same option.
exec "$BURROW_RUBY" -EUTF-8 "$RES/boot.rb" "$@"
