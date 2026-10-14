#!/bin/bash
set -euo pipefail
# Isolated silent devices: never connect this test to the user's audio session.
audio_tmp=$(mktemp -d "${TMPDIR:-/tmp}/burrow-audio.XXXXXX")
pulse_pid=
cleanup() {
  if [ -n "$pulse_pid" ]; then
    kill "$pulse_pid" 2>/dev/null || true
    wait "$pulse_pid" 2>/dev/null || true
  fi
  rm -rf "$audio_tmp"
}
trap cleanup EXIT
pulseaudio -n --daemonize=no --exit-idle-time=-1 --log-target="file:$audio_tmp/pulse.log" \
  -L "module-native-protocol-unix socket=$audio_tmp/pulse.sock auth-anonymous=1" \
  -L 'module-null-sink sink_name=burrow' &
pulse_pid=$!
for _attempt in {1..100}; do
  [ ! -S "$audio_tmp/pulse.sock" ] || break
  sleep 0.1
done
if [ ! -S "$audio_tmp/pulse.sock" ]; then
  cat "$audio_tmp/pulse.log"
  exit 1
fi
PULSE_SERVER="unix:$audio_tmp/pulse.sock" xvfb-run -a -s '-screen 0 1600x1000x24' \
  python3 -I tools/check_linux_package.py dist/*.tar.gz --windowed --locale c \
  --audio-driver pulse --output .cache/linux-evidence/pulse
printf 'pcm.!default { type null }\n' > "$audio_tmp/asound.conf"
ALSA_CONFIG_PATH="$audio_tmp/asound.conf" xvfb-run -a -s '-screen 0 1600x1000x24' \
  python3 -I tools/check_linux_package.py dist/*.tar.gz --windowed --locale c \
  --audio-driver alsa --output .cache/linux-evidence/alsa
