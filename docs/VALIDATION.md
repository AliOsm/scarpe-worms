# Validation

The [0.3.0 release report](validation/release-0.3.0.json) is the integrated baseline.
All implementation checks below ran on Linux. The owner confirmed 0.2.4 smooth
on an M3 Pro; that timing fix is preserved in 0.3.0.

## Recorded 0.3.0 results

| Check | Result |
| --- | --- |
| Core on Ruby 3.4.7 and 4.0.7 | 80 tests / 4,902 assertions each; no failures, errors, or skips |
| Native input/UI journeys | Six journeys / 172 assertions; no failures |
| Terrain art | Four biome masks match collision; tiles stitch; craters invalidate shading |
| Relocated packaged runtime | Four launches; fresh/resumed games, Unicode paths, unset/C locales, saved diagnostics |
| Mac archive, static checks | 106 arm64 binaries; macOS 13+; ad-hoc code/resource hashes and archive parity |
| Audio | 13 cues; OpenAL mixing, mute/resume, shutdown; Linux null output |
| Scarpe | Pinned revision and 12 independent patches verified |

## Rendering measurements

36 grubs, 4,800×1,600 world, 1,920×1,200 window, simulated 2× density, audio enabled.
Native windows use Xvfb; Mac compositor/display behavior is not measured here.

| Run | Combat mean | Combat p95 | Combat maximum |
| --- | --- | --- | --- |
| Source | 16.81 ms | 20.30 ms | 53.52 ms |
| Packaged Ruby application | 16.81 ms | 21.14 ms | 47.83 ms |
| Package with 100 ms timer slack | 16.85 ms | 20.90 ms | 45.15 ms |

Continuous combat/pan budgets passed. Discrete zoom changes are evaluated by paint
cost; the normal packaged run had three presentation intervals above 50 ms, with
63.71 ms maximum. These results do not promise every frame reaches 60 FPS.

## Reproduce relevant checks

After [setup](../CONTRIBUTING.md):

```sh
bundle exec rake test
./bin/check-native
bundle exec ruby tools/check_audio.rb
bundle exec ruby tools/check_waits.rb
python3 tools/verify_scarpe.py
python3 tools/check_container.py
```

For windowed timing, run serially without concurrent builds:

```sh
xvfb-run -a -s '-screen 0 3840x2400x24' \
  python3 tools/check_rendering.py --scale 2 --size 1920x1200 --audio
```

Repeat with `--timer-slack-ms 100` for the timing regression. Package checks and
native Mac commands are in [MACOS.md](MACOS.md). Upstream Rust checks are in the
[patch guide](../patches/scarpe/README.md).

Native screenshots/reports go to `.cache/native-checks/`. Other tools write to
`docs/validation/`; keep raw captures local and promote selected summaries to
versioned filenames. See the [report index](validation/README.md).

## Coverage and limits

- Core: all 48 arsenal actions, deterministic maps, geometry, staged controls,
  turn ownership, ammo, checkpoint recovery, malformed traffic, TLS, and reconnects.
- Native: real Rust key/pointer/focus dispatch, six-player TLS recovery, arsenal,
  camera, rematches, and cancellation during window/menu transitions.
- Presentation: the anonymized 646-update Mac cadence remains a regression fixture;
  [performance history](history/PERFORMANCE.md) explains why it matters.
- Outstanding: native 0.3.0 Mac execution, audible output, human balance/polish,
  real internet play, and signing/notarization. See [release requirements](RELEASE.md).

Older JSON reports remain historical evidence; they do not certify the current
checkout. GitHub workflow definitions alone are not execution evidence.
