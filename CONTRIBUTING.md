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
| Art or audio assets | `uv run tools/check_assets.py` plus the relevant native journey |
| Host/container | `python3 tools/check_container.py` (requires Docker) |
| Scarpe patches | `python3 tools/verify_scarpe.py` and relevant upstream tests |
| Documentation only | Check relative links and runnable command examples |

For rendering or scheduling changes, also run this benchmark serially:

```sh
xvfb-run -a -s '-screen 0 3840x2400x24' \
  python3 tools/check_rendering.py --scale 2 --size 1920x1200 --audio
```

Add `--timer-slack-ms 100` to reproduce the old Mac timing failure on Linux.
Run `python3 tools/test_rendering.py` when changing the timing analysis itself.
See [validation](docs/VALIDATION.md) for scope and limits.

The rendering report retains the original spaced `zoom` inputs and adds
`zoom_sweep`, which retargets the camera before a transition settles. Compare
`active_motion_intervals` for motion and keep whole-stage `presented_intervals`
separate: gaps between spaced inputs can be intentionally skipped idle paints.
`updates` and paint counts do not identify individual IPC batches or prove scanout.
Native captures include bounded batch receipt/settle/redraw timestamps and phase
thread CPU time alongside wall time, to distinguish work from scheduling delays.

For input latency and snapshot costs, run `nice -n 10 flock /tmp/burrow-bench.lock
bundle exec ruby tools/check_latency.rb --output /tmp/burrow-latency.json`.
It exercises real TCP/TLS host subprocesses, App input, Timeline playback and
OpenAL submission, plus a 36-grub snapshot workload. Linux uses the null mixer;
these timings do not measure acoustic output or display latency.

For Ruby frame costs, add `BURROW_BENCH_PROFILE=1` to the rendering command.
Its summary includes per-method CPU/wall time, allocations, native property
messages (including unchanged messages), stage GC counts/time, and connection
snapshot decode costs. The `.raw.json` retains individual samples. Counters for
allocations and GC include all GUI-process threads; nested method totals overlap.
Profiling adds overhead, so also capture ordinary runs. On Linux,
`BURROW_BENCH_SCHED=1` with profiling records GUI run-queue waits to distinguish
CPU contention from time spent waiting for another Ruby thread.

A deterministic native workload isolates 36 grubs, 60 flames, HUD, pan and zoom:

```sh
nice -n 10 flock /tmp/burrow-bench.lock env \
  SCARPE_DISPLAY_SERVICE=native SCARPE_NATIVE_HEADLESS=1 \
  BURROW_FRAME_ALLOCATIONS=1 ./bin/scarpe tools/check_frame_work.rb
```

It writes `profile.json`, four native screenshots, and optional single-frame
ObjectSpace allocation sites to `.cache/frame-work/`. Set `BURROW_FRAME_OUTPUT`
to retain another run. This fixture supplies frozen presentation state and does
not measure timeline interpolation, network playback, or presented cadence.
Both tools accept `BURROW_BENCH_SOURCE` pointing to an archived source tree with
its assets, so before/after comparisons can use the same instrumentation without
switching branches. Do not tune packaged GC settings from a profiled run alone.

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
