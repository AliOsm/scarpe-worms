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

exec /bin/bash "$RES/ruby.sh" "$RES/boot.rb" "$@"
