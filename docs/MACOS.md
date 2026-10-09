# macOS build and diagnostics

Target: **Apple silicon (arm64), macOS 13+**. Version 0.3.0 is an ad-hoc signed
preview. Intel/Windows packages and a notarized sales release are not provided.

## Build the standalone app on Linux

After [development setup](../CONTRIBUTING.md), with Python 3.12+:

```sh
python3 tools/package_macos.py
python3 tools/verify_macos.py 'dist/Burrow Brigade.app'
python3 tools/check_distributable.py
```

Output: `dist/Burrow-Brigade-0.3.0-macos-arm64.zip` and its `.sha256` sidecar.
The archive bundles Ruby 3.4.7, patched native Scarpe, gems, fonts, art, and audio.
Players do not need a separate Ruby, Rust, browser, or server installation.

Build downloads are checksum-pinned in `packaging/macos/dependencies.json`.
The script verifies all Scarpe patches, cross-compiles, collects notices, and
applies ad-hoc signatures. It checks Mach-O architecture/deployment targets,
library paths, executable hashes, resource seals, and leaked state.
**Static verification does not execute the app or establish Gatekeeper acceptance.**

Build outputs are ignored by Git. The macOS preview workflow can also build and
upload the archive through Actions; it runs manually or on `v*` tags.

## Install and find data

Extract the ZIP and move **Burrow Brigade.app** to Applications. Quit an older
copy before replacing it. An unnotarized preview may be refused by Gatekeeper;
use a trusted Developer ID build for normal distribution.

| Data | Location |
| --- | --- |
| Settings, saves, host state | `~/Library/Application Support/burrow-brigade` |
| Launcher log (rotates at 5 MiB) | `~/Library/Logs/Burrow Brigade/launcher.log` |
| Latest three timing sessions | `~/Library/Logs/Burrow Brigade/performance/` |

The app bundle stays read-only. Existing settings and unfinished matches remain
compatible. Host and client must both use protocol 3. Do not delete data to upgrade.

After reproducing a problem, quit normally, including Command-Q, then:

```sh
open "$HOME/Library/Logs/Burrow Brigade/performance"
ditto -c -k --keepParent "$HOME/Library/Logs/Burrow Brigade" "$HOME/Desktop/Burrow-Brigade-logs.zip"
```

Quote `$HOME`, not `~`. Reports include `session.json`, `ruby.json`, `rust.json`,
and `game.json`. They retain bounded timing samples locally; nothing is uploaded.
Review diagnostics before sharing them publicly.

## Verify a package

Linux can exercise bundled Ruby code with explicit executable substitutions:

```sh
python3 tools/check_package.py 'dist/Burrow Brigade.app' \
  --linux-ruby /path/to/ruby-3.4/bin/ruby
```

This tests fresh/resumed matches, Unicode paths, input, resize, and diagnostics.
Add `--locale c` for the previous Finder/ASCII startup regression. Linux Ruby,
Scarpe, and ffi substitutions do **not** validate the delivered Darwin binaries.

On an Apple silicon Mac, run:

```sh
codesign --verify --deep --strict --verbose=2 'dist/Burrow Brigade.app'
python3 tools/check_package.py 'dist/Burrow Brigade.app'
python3 tools/check_package.py 'dist/Burrow Brigade.app' --windowed --locale c
python3 tools/check_waits.py --app 'dist/Burrow Brigade.app' --output docs/validation/waits-macos.json
python3 tools/check_rendering.py --app 'dist/Burrow Brigade.app' --audio
```

Repeat rendering at `--size 1920x1200` on the actual display. The preview workflow
runs these checks on an Apple silicon runner; human audio, display, and internet
acceptance still follow [RELEASE.md](RELEASE.md).

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
