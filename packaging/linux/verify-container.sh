#!/bin/bash
set -euo pipefail
if command -v ruby || command -v cargo || command -v bundle; then
  echo 'Verification image must not contain a developer runtime.' >&2
  exit 1
fi
python3 -I /source/tools/check_linux_package.py /source/dist/*.tar.gz --output /evidence/headless
Xvfb :99 -screen 0 1600x1000x24 -nolisten tcp &
display_pid=$!
trap 'kill "$display_pid" 2>/dev/null || true' EXIT
export DISPLAY=:99
for _attempt in {1..50}; do
  [ ! -S /tmp/.X11-unix/X99 ] || break
  sleep 0.1
done
python3 -I /source/tools/check_linux_package.py /source/dist/*.tar.gz --windowed --locale c --output /evidence/windowed
