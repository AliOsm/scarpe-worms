# Linux client

The release download is `Burrow-Brigade-<version>-linux-x86_64.tar.gz` plus its
SHA-256 sidecar. It contains Ruby 3.4.7, the gems, the patched Scarpe native
renderer, OpenAL Soft 1.24.3, fonts, art, audio and dependency notices.

## Install and launch

On an x86-64 desktop with glibc 2.35 or later (Ubuntu 22.04+, Debian 12+,
Fedora 40+), download both files, then:

```sh
sha256sum -c Burrow-Brigade-<version>-linux-x86_64.tar.gz.sha256
tar -xzf Burrow-Brigade-<version>-linux-x86_64.tar.gz
cd 'Burrow Brigade'
./burrow-brigade
./burrow-brigade --install-desktop  # optional application-menu entry, no sudo
```

Keep the complete folder together. It may be moved or installed read-only;
run `--install-desktop` again after moving it. `--uninstall-desktop` removes
only the menu entry. Replacing the game folder upgrades without deleting saves.
There is no automatic updater. The archive is unsigned; compare the checksum
from a trusted release. A checksum alone does not authenticate a download.

The tarball avoids the FUSE dependency and mount/extraction variations of
AppImage. No Ruby, Rust, gems, Bundler, browser, FUSE or build tools are required
on the player's machine. This build is not for ARM or Alpine/musl.

## Desktop and audio prerequisites

Most full desktop installations already have these libraries. Run
`./burrow-brigade --check` in a terminal to diagnose missing libraries.
The launcher reports missing desktop libraries before starting the renderer.

Ubuntu 22.04 / Debian 12:

```sh
sudo apt-get install libcrypt1 libstdc++6 libgcc-s1 libx11-6 libx11-xcb1 \
  libxcursor1 libxi6 libxrandr2 libxcb1 libxkbcommon0 libxkbcommon-x11-0 \
  libwayland-client0 libwayland-cursor0 libpulse0 libasound2
```

Use `libasound2t64` instead of `libasound2` on Ubuntu 24.04 and later.
Fedora:

```sh
sudo dnf install libxcrypt-compat libstdc++ libgcc libX11 libXcursor libXi \
  libXrandr libxcb libxkbcommon libxkbcommon-x11 libwayland-client libwayland-cursor \
  pulseaudio-libs alsa-lib
```

The linked system libraries are glibc (including libm, libdl, libpthread,
librt), libcrypt.so.1, libgcc_s.so.1 and libstdc++.so.6. Winit and softbuffer
load X11/XCB, cursor, input and xkbcommon libraries at runtime, or Wayland client,
cursor and xkbcommon on a Wayland desktop. X11 extensions such as shared memory,
RandR and XInput must be available from the display server. Transitive X11
dependencies are supplied by the distro's packages. Fontconfig configuration
is read by the Rust font discovery code; the game embeds its fonts and does not
link to fontconfig or FreeType. The CPU renderer does not use OpenGL or Vulkan.
The desktop's session D-Bus and portal support enable optional native dialogs
and accessibility integration.

OpenAL is bundled as `lib/libopenal.so.1`, built with dynamically loaded
PipeWire, PulseAudio and ALSA backends. Your desktop supplies the audio server,
device permissions and its client library (`libpipewire-0.3.so.0`,
`libpulse.so.0` or `libasound.so.2`). PipeWire's PulseAudio compatibility service
can use the Pulse backend. An unavailable audio device leaves the game playable
silently. CI uses OpenAL's null output plus a private PulseAudio null sink and
ALSA null PCM on Ubuntu 24.04. These exercise the backends without physical
devices; they do not establish audible output quality or device latency.
The native PipeWire backend is compiled in but has not been exercised here.

OpenAL's LGPL notice, complete corresponding source archive, third-party
notices and actual build flags are inside `resources/licenses/openal-soft/`.
You may replace the shared library with an ABI-compatible modified build.
Other notices are in `resources/licenses/`, `resources/gems/` and
`resources/app/THIRD_PARTY.md`.

## Data and diagnostics

| Data | Location |
| --- | --- |
| Preferences, saves, local/hosted state | `$XDG_DATA_HOME/burrow-brigade`, default `~/.local/share/burrow-brigade` |
| Launcher log | `$XDG_STATE_HOME/burrow-brigade/logs/launcher.log`, default `~/.local/state/burrow-brigade/logs/launcher.log` |
| Latest three diagnostic sessions | `logs/performance/session-*` |

`BURROW_DATA_DIR` and `BURROW_LOG_DIR` override those defaults. Terrain workers
use the system temporary directory (`TMPDIR` when set). Launcher logs rotate at
5 MiB. Timing samples are bounded and remain local. Review them before sharing.
Both the in-app host and terrain worker execute the bundled Ruby through
`BURROW_RUBY`; no interpreter is found through the user's PATH.

## Build and verify

Build on Ubuntu 22.04 x86-64 with Python 3.12+, the pinned Rust toolchain,
Git, build-essential, CMake, patchelf, pkg-config, libxkbcommon-dev, libfontconfig1-dev,
libasound2-dev, libpulse-dev and libpipewire-0.3-dev:

```sh
python3 -I tools/package_linux.py
python3 -I tools/check_linux_package.py dist/*.tar.gz --output .cache/linux-smoke/headless
xvfb-run -a -s '-screen 0 1600x1000x24' \
  python3 -I tools/check_linux_package.py dist/*.tar.gz --windowed --locale c \
  --output .cache/linux-smoke/windowed
```

The build verifies the complete Scarpe patch series and the SHA-256 of each
download, extracts into separate empty directories and uses Cargo's lockfile.
Traveling Ruby's relocatable Linux runtime comes from the CentOS 7 based Holy
Build Box build; packaging removes its obsolete `/tmp/ruby/lib` ELF RPATH.
Ruby/setup-ruby installations are not used as distributable
runtimes because their build prefixes and external dependencies are not the
same portable runtime contract. The renderer and OpenAL are built on Ubuntu
22.04. A final audit checks every ELF, rejects unexpected linked libraries or
embedded search paths and rejects requirements above glibc 2.35 or
GLIBCXX_3.4.30. `resources/build.json` records the commit, build OS and each
binary's requirements.

`.github/workflows/package-linux.yml` accepts a reusable-workflow `ref`, and
uploads exactly the tarball and sidecar as `burrow-brigade-linux`. Its success
requires packaged verification on separate Ubuntu 22.04 and 24.04 runners,
plus digest-pinned Debian 12 and Fedora 40 containers on Ubuntu 24.04. The
containers contain no Ruby, Rust or Bundler and run as an unprivileged user,
with networking disabled and the checkout mounted read-only. Evidence is in
separate `linux-evidence-*` artifacts.

Both headless and Xvfb windowed checks use the delivered launcher, reach the
menu, start a three-team battle with two bots, see terrain and a rendered shot,
resize, quit, verify all child processes exit, and recover the same saved match
and player. The checks relocate into Unicode/spaced paths, contaminate developer
environment variables, make the bundle read-only and verify its contents remain
unchanged. Windowed checks also mix every audio cue with the bundled OpenAL
null driver. Ubuntu 24.04 repeats the windowed check through the PulseAudio
and ALSA backends using isolated silent devices. There are no performance-budget
release gates.

Run evidence and limitations are recorded in
[`validation/release-linux.json`](validation/release-linux.json). Native Wayland,
physical display/audio, Internet play and human game acceptance require their
own validation; an Xvfb run establishes functional X11 presentation.
