# Working on Burrow Brigade

Start with [project status](docs/STATUS.md) and the [architecture](docs/ARCHITECTURE.md).
The repository is `scarpe-worms`; the game and bundle are **Burrow Brigade**.

## Setup

Use Ruby **4.0.7** for development or **3.4.7** to match the packaged runtime.
Rust **1.99.0** is pinned in `rust-toolchain.toml`; install it through rustup.
You also need Git, Bundler (the lockfile records its version), and Python 3.12+.

Ubuntu 24.04 dependencies:

```sh
sudo apt-get install build-essential pkg-config libffi-dev libxkbcommon-dev \
  libxkbcommon-x11-0 libfontconfig1-dev libopenal1 xvfb xauth
./setup.sh
./run.sh
```

On macOS, install Xcode Command Line Tools (`xcode-select --install`), Ruby,
rustup, and Python, then run the same setup and launch scripts.
A graphical desktop is needed for interactive play; native checks run headlessly.

`vendor/` is untracked. Setup clones upstream Scarpe at `SCARPE_REVISION`,
verifies/applies the ordered patches, and builds locally. It refuses unexplained
edits to that checkout. Re-running setup is supported.

## Choose checks for the change

| Change | Run |
| --- | --- |
| Gameplay, network, input, or saves | `bundle exec rake test` |
| One regression while iterating | `bundle exec ruby -Itest test/weapon_physics_test.rb` |
| Native UI or input | `./bin/check-native` |
| One native journey | `./bin/check-native checks/controls.sspec` |
| Audio | `bundle exec ruby tools/check_audio.rb` |
| Host/container | `python3 tools/check_container.py` (requires Docker) |
| Scarpe patches | `python3 tools/verify_scarpe.py` and relevant upstream tests |
| Documentation only | Check relative links and runnable command examples |

For rendering or scheduling changes, also run this benchmark serially:

```sh
xvfb-run -a -s '-screen 0 3840x2400x24' \
  python3 tools/check_rendering.py --scale 2 --size 1920x1200 --audio
```

Add `--timer-slack-ms 100` to reproduce the old Mac timing failure on Linux.
See [validation](docs/VALIDATION.md) for scope and limits.

## Assets and framework patches

Assets are committed so a clone runs without regeneration. Change the generator
alongside its output; see [art direction](docs/ART_DIRECTION.md). Art builds use
`uv run tools/build_art.py`; audio uses `ruby tools/build_audio.rb`.

Keep framework fixes in the ordered [Scarpe patch series](patches/scarpe/README.md),
with no game-specific logic. Export fixes separately, then verify the resulting
tree with `python3 tools/verify_scarpe.py`. Do not commit the dependency checkout.

## Before handing off

- Explain the change and the checks actually run; distinguish Linux from macOS.
- Update the relevant guide when behavior or setup changes.
- Keep [STATUS.md](docs/STATUS.md) current when priorities or release evidence change.
- Keep saves, tokens, certificates, caches, and build archives out of commits.
- Follow [macOS packaging](docs/MACOS.md) and [release requirements](docs/RELEASE.md) for distribution.

CI runs core and native checks on Ruby 3.4.7 and 4.0.7. The separate macOS preview
workflow runs manually or for `v*` tags; it builds a ZIP and exercises it on an
Apple silicon runner. Workflow results are evidence only after they run.
