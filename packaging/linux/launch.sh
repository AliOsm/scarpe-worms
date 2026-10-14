#!/bin/sh
set -eu
# readlink follows a desktop/user-created symlink without depending on cwd.
BURROW_BUNDLE=$(dirname -- "$(readlink -f -- "$0")")
export BURROW_PACKAGE_RES="$BURROW_BUNDLE/resources"
RES=$BURROW_PACKAGE_RES
export BURROW_RUBY="$RES/runtime/ruby/bin.real/ruby"
export BURROW_LOG_DIR="${BURROW_LOG_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/burrow-brigade/logs}"
export BURROW_DATA_DIR="${BURROW_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/burrow-brigade}"
umask 077
mkdir -p "$BURROW_LOG_DIR"
if [ -f "$BURROW_LOG_DIR/launcher.log" ] && [ "$(wc -c < "$BURROW_LOG_DIR/launcher.log")" -gt 5242880 ]; then
  mv -f "$BURROW_LOG_DIR/launcher.log" "$BURROW_LOG_DIR/launcher.log.1"
fi
# Installed Rubies, Bundler and compiler libraries must not contaminate the bundle.
unset RUBYOPT RUBYLIB GEM_HOME GEM_PATH BUNDLE_GEMFILE BUNDLE_PATH BUNDLE_BIN_PATH
unset SSL_CERT_DIR RUBYGEMS_GEMDEPS
export LD_LIBRARY_PATH="$BURROW_BUNDLE/lib:$RES/runtime/ruby/lib"
export SSL_CERT_FILE="$RES/runtime/ruby/lib/ca-bundle.crt"
export GEM_HOME="$RES/runtime/gems" GEM_PATH="$RES/runtime/gems"
RUBY_LIB="$RES/runtime/ruby/lib/ruby"
export RUBYLIB="$RES/scarpe/lib:$RES/scarpe/lacci/lib:$RES/scarpe/scarpe-components/lib:$RES/gems/ffi/lib:$RES/gems/chunky_png/lib:$RES/gems/base64/lib:$RES/gems/logger/lib:$RES/gems/fastimage/lib:$RUBY_LIB/site_ruby/3.4.0:$RUBY_LIB/site_ruby/3.4.0/x86_64-linux:$RUBY_LIB/site_ruby:$RUBY_LIB/vendor_ruby/3.4.0:$RUBY_LIB/vendor_ruby/3.4.0/x86_64-linux:$RUBY_LIB/vendor_ruby:$RUBY_LIB/3.4.0:$RUBY_LIB/3.4.0/x86_64-linux"
export SCARPE_NATIVE_BIN="$RES/bin/scarpe-native" SCARPE_DISPLAY_SERVICE=native
# libcrypt.so.1 is separate from glibc on Fedora; report it before Ruby starts.
if command -v ldd >/dev/null 2>&1; then
  BURROW_MISSING=$(ldd "$BURROW_RUBY" 2>&1 | sed -n '/not found/p')
  if [ -n "$BURROW_MISSING" ]; then
    printf 'Burrow Brigade needs a system library:\n%s\nInstall libcrypt1 (Debian/Ubuntu) or libxcrypt-compat (Fedora). See READ-ME.txt.\n' "$BURROW_MISSING" >&2
    exit 1
  fi
fi
case "${1:-}" in
  --check) exec "$BURROW_RUBY" -EUTF-8 "$RES/check_runtime.rb" ;;
  --install-desktop|--uninstall-desktop) exec "$BURROW_RUBY" -EUTF-8 "$RES/desktop.rb" "$1" ;;
  --smoke) exec "$BURROW_RUBY" -EUTF-8 "$RES/smoke.rb" ;;
  '') ;;
  *) printf 'Usage: %s [--check|--install-desktop|--uninstall-desktop]\n' "$0" >&2; exit 2 ;;
esac
# Keep startup failures visible in the terminal as well as in the launch log.
"$BURROW_RUBY" -EUTF-8 "$RES/check_runtime.rb" --quiet || exit 1
exec >>"$BURROW_LOG_DIR/launcher.log" 2>&1
printf '\nBurrow Brigade starting at %s\n' "$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
exec "$BURROW_RUBY" -EUTF-8 "$RES/boot.rb"
