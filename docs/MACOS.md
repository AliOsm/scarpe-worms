# macOS build and diagnostics

Target: **Apple silicon (arm64), macOS 13+**. The Mac ZIP is an ad-hoc signed,
unnotarized preview. The reusable package workflow runs the delivered binaries
on an Apple silicon `macos-15` runner before the
[release pipeline](RELEASE.md) accepts them. This does not establish physical
display/audio acceptance or notarization. Intel Mac packages are not provided.

## Build the standalone app on Apple silicon

After [development setup](../CONTRIBUTING.md), with Xcode Command Line Tools,
Python 3.12+, make, Perl and pkg-config:

```sh
python3 -I tools/package_macos.py
python3 -I tools/verify_macos.py 'dist/Burrow Brigade.app'
python3 tools/check_distributable.py
```

Output: `dist/Burrow-Brigade-<version>-macos-arm64.zip` (currently 0.5.8) and its `.sha256` sidecar.
The archive bundles Ruby 4.0.7, patched native Scarpe, OpenAL Soft 1.24.3 with
CoreAudio, a two-period mixer profile, gems, fonts, art, and audio.
CMake is needed to build the mixer. The profile selects two 256-frame periods,
lowering OpenAL's configured scheduling cushion. CoreAudio renders the frames
requested by the hardware callback; this setting does not set its buffer size
or measure audible latency. The measured runner still reported a 512-frame
hardware buffer at 48 kHz and a 12.75 ms device path.
Players do not need a separate Ruby, Rust, browser, or server installation.

Build downloads are checksum-pinned in `packaging/macos/dependencies.json` and
`packaging/ruby/dependencies.json`. The shared builder compiles relocatable Ruby
with static OpenSSL, libffi, libyaml and zlib. The script verifies all Scarpe
patches, builds the native renderer, collects notices and applies ad-hoc signatures. It checks Mach-O architecture/deployment targets,
library paths, executable hashes, resource seals, and leaked state.
**Static verification does not execute the app or establish Gatekeeper acceptance.**

Build outputs are ignored by Git. `package-macos.yml` can build and upload the
archive manually, for packaging pull requests, or through `release.yml` on a
release tag. Its `ref` input selects the source commit. The verified artifact
`burrow-brigade-macos` contains only the ZIP and its sidecar; diagnostic evidence
is uploaded separately. The retired preview workflow no longer duplicates tag
builds. See [release validation](validation/release-pipeline.json) for actual runs.

## Install and find data

Verify the ZIP's `.sha256` sidecar, extract it and move **Burrow Brigade.app** to
Applications. Quit an older copy before replacing it. Gatekeeper may refuse this
unnotarized preview. For a verified download you trust, use **System Settings →
Privacy & Security → Open Anyway**, or remove quarantine from that app only:

```sh
xattr -dr com.apple.quarantine '/Applications/Burrow Brigade.app'
```

A Developer ID signed/notarized build is still needed for standard Gatekeeper
acceptance. Ad-hoc codesign verification checks integrity, not developer identity.

| Data | Location |
| --- | --- |
| Settings, saves, host state | `~/Library/Application Support/burrow-brigade` |
| Launcher log (rotates at 5 MiB) | `~/Library/Logs/Burrow Brigade/launcher.log` |
| Latest three timing sessions | `~/Library/Logs/Burrow Brigade/performance/` |

The app bundle stays read-only. Existing settings and unfinished matches remain
compatible. Host and client must both use protocol 4. Do not delete data to upgrade.

After reproducing a problem, quit normally, including Command-Q, then:

```sh
open "$HOME/Library/Logs/Burrow Brigade/performance"
ditto -c -k --keepParent "$HOME/Library/Logs/Burrow Brigade" "$HOME/Desktop/Burrow-Brigade-logs.zip"
```

Quote `$HOME`, not `~`. Reports include `session.json`, `ruby.json`, `rust.json`,
`game.json` and `audio.json` (when each sound was due and started, drops, and the
output device's reported latency and type, e.g. built-in or Bluetooth). They retain bounded timing samples locally; nothing is uploaded.
Review diagnostics before sharing them publicly.

## Verify a package

Linux can exercise bundled Ruby code with explicit executable substitutions:

```sh
python3 tools/check_package.py 'dist/Burrow Brigade.app' \
  --linux-ruby /path/to/ruby-4.0.7/bin/ruby
```

This tests fresh/resumed matches, Unicode paths, input, resize, and diagnostics.
Add `--locale c` for the previous Finder/ASCII startup regression. Linux Ruby,
Scarpe, and ffi substitutions do **not** validate the delivered Darwin binaries.
Also move the app beneath a directory containing spaces and Unicode (for example
`Brigade Équipe`) before testing; Unicode data paths alone do not cover Ruby's
startup library-path encoding.

On an Apple silicon Mac, run:

```sh
codesign --verify --deep --strict --verbose=2 'dist/Burrow Brigade.app'
python3 tools/check_package.py 'dist/Burrow Brigade.app'
python3 tools/check_package.py 'dist/Burrow Brigade.app' --windowed --locale c
python3 tools/check_macos_audio.py 'dist/Burrow Brigade.app'
python3 tools/check_waits.py --app 'dist/Burrow Brigade.app' --output docs/validation/waits-macos.json
python3 tools/check_rendering.py --app 'dist/Burrow Brigade.app' --audio
```

Repeat rendering at `--size 1920x1200` on the actual display. The package workflow
runs these checks serially on an Apple silicon runner. Native menu/bot-match,
input, save/recovery, packaged audio and signature checks gate releases; deadline/rendering
benchmarks are informational because shared-runner timing is noisy. Human audio,
display and internet acceptance still follow [RELEASE.md](RELEASE.md).

## Sign for distribution

Configure a Developer ID identity and a `notarytool` Keychain profile on the
release Mac. Keep credentials in Keychain/CI secrets, then:

```sh
export BURROW_SIGN_IDENTITY='Developer ID Application: your identity'
export BURROW_NOTARY_PROFILE='your-keychain-profile'
./tools/sign_macos.sh
```

The script signs nested code, enables hardened runtime, notarizes, staples,
checks Gatekeeper, and creates a separate ZIP/checksum. Validate that final
quarantined download on a clean Mac. Signing has not been completed in this repo.

For the resolved stutter, UTF-8 startup fix, diagnostic fields, and comparison
switches, read [performance history](history/PERFORMANCE.md).
