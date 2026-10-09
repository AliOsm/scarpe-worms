# Validation

The 0.4.0 presentation pass is a preview. The current [report index](validation/README.md)
links to versioned evidence; older reports remain historical. All execution in
this pass ran on Linux. Native Apple silicon acceptance remains required.

## Recorded 0.4.0 results

| Check | Result |
| --- | --- |
| Core on Ruby 3.4.7 and 4.0.7 | 91 tests / 5,014 assertions each; no failures, errors or skips |
| Native input/UI journeys | Seven journeys / 204 assertions; no failures |
| Asset audit | 516 runtime PNGs, 336 animation frames, 23 directional combat sprites; all 48 weapon icons |
| Terrain | All four biome masks equal collision; tiled/whole painting and crater invalidation pass |
| Reproducibility | Two full art/audio builds, 618 PNG/SVG/WAV/JSON files byte-identical; first build without cached preview masks |
| Audio | 22 cues; decoding, OpenAL mixing, positioning, mute/resume and shutdown; Linux null output |
| Timing analysis | Eight focused regression tests for moving/idle presentation gaps |
| 30-minute source endurance | 14 matches / 13 completed, 580 turns, 202 socket shots, 558 terrain changes, 59 resizes, 349 camera changes |
| Scarpe | Pinned revision and all 12 independent patches verified |

The native journeys exercise real Rust key/pointer/focus dispatch, six-client
TLS recovery, staged controls, arsenal, camera, rematches and input cancellation.
The presentation journey adds small-window dialogs, room pagination, long chat,
all four biomes and manual-camera persistence. Selected [screenshots](evidence/README.md)
are actual unedited native frames, not the asset generator's review composites.

The source soak retained one scene and terrain worker after every rematch. Peak
RSS was about 101 MiB for GUI Ruby, 129 MiB for the renderer, 100 MiB for the host
and 97 MiB for terrain. Whole-session timings include rematches and resize work.
The soak preceded a final pickup-label clipping fix, which has a focused native
regression. The 0.4.0 archive passes source/asset parity, ZIP integrity, resource
seals and 106 arm64 binary checks. Relocated Ruby execution passes fresh/resumed
launches under unset and C locales from a Unicode installation path. Linux
Ruby, renderer and ffi substitutions do not execute the Darwin binaries.

A relocated Unicode installation exposed mixed UTF-8/US-ASCII tags in Ruby's
load paths. Both worker launchers now join the original filesystem bytes.
Encoding regressions create real Unicode subdirectories: Ruby's `mktmpdir`
sanitizes non-ASCII prefixes, so the older fixtures did not cover those paths.
The 30-minute soak and native journeys preceded this startup-only correction;
final core and relocated-package checks cover the corrected launch boundary.

## Rendering measurements

36 grubs, 4,800×1,600 world, 1,920×1,200 window, simulated 2× density, audio enabled.
Linux Xvfb presents a 3,840×2,400 surface; the software render budget uses
1,280×800 pixels. This does not measure a Mac compositor or input-to-photon delay.

| Run | Combat mean | Combat p95 | Combat maximum |
| --- | --- | --- | --- |
| Source | 16.10 ms | 19.91 ms | 32.01 ms |
| Source with 100 ms timer slack | 16.33 ms | 20.25 ms | 31.59 ms |
| Packaged Ruby code on Linux | 16.57 ms | 20.41 ms | 57.36 ms |
| Packaged with 100 ms timer slack | 16.48 ms | 21.16 ms | 38.14 ms |

All four final captures pass the unchanged continuous combat/pan budgets:
mean <18.5 ms, p95 <25 ms and max <60 ms. Discrete zoom uses a separate paint-work
budget (<55 ms); normal source zoom presentation peaked at 48.54 ms and the
timer-slack run at 82.64 ms. Packaged zoom presentation peaked at 84.35 ms
and 81.51 ms respectively; its paint work stayed within budget. These measurements
do not promise every frame reaches 60 FPS.

Motion analysis version 2 uses completed GUI updates. A movement already shown
can end at an explicit idle update; any new movement between paints remains
chargeable until the next paint, even if it stops meanwhile. Missing updates
retain the active stall. At most one sample is emitted per native gap, and a
separate <60 ms combat GUI-update budget catches stalls during idle frames too.
This avoids charging skipped, unchanged frames as animation stalls without
concealing an unpresented short movement. Motion detection version 2 compares
rounded visible actor/projectile positions and camera origins actually sent to
the renderer. Small collision/interpolation velocities alone are insufficient:
a later velocity-based capture reported an apparent 89.68 ms gap while draw
positions were unchanged and GUI updates remained regular. Raw captures retain
both the velocity flag and actual pixel-change counts for inspection.

An earlier capture exceeded the 60 ms budget at **61.23 ms**, alongside a roughly
46 ms Ruby scene update. Its cause was not established. A separate apparent
92 ms stall was an already-presented camera handoff followed by intentionally
skipped idle frames; the corrected classifier no longer mislabels that case.
The genuine 61 ms outlier still fails under the corrected analysis. Preserve
that distinction when comparing later passing runs.

## Reproduce relevant checks

After [setup](../CONTRIBUTING.md):

```sh
bundle exec rake test
./bin/check-native
uv run tools/check_assets.py
bundle exec ruby tools/check_audio.rb
python3 tools/test_rendering.py
python3 tools/verify_scarpe.py
```

Run native/performance checks serially without competing builds:

```sh
xvfb-run -a -s '-screen 0 3840x2400x24' \
  python3 tools/check_rendering.py --scale 2 --size 1920x1200 --audio
```

Repeat with `--timer-slack-ms 100` for the precise-wait regression. Add
`--output .cache/your-run.json` to keep exploratory captures out of published
evidence. `BURROW_BENCH_PROFILE=1` adds benchmark-only slow-phase and thread-CPU
measurements when investigating a failure.

For a windowed endurance run with Linux null audio:

```sh
xvfb-run -a -s '-screen 0 1920x1200x24' \
  env SCARPE_DISPLAY_SERVICE=native SCARPE_NATIVE_HEADLESS=0 \
  ALSOFT_DRIVERS=null BURROW_SOAK_AUDIO=1 BURROW_SOAK_SECONDS=1800 \
  BURROW_SOAK_OUTPUT=.cache/native-soak.json \
  ./bin/scarpe tools/check_soak.rb
```

The soak includes rematches, resizing, menus and explicit collection; its whole-
session maximum is not the continuous-motion benchmark. It checks lifecycle
retention and bounded effects, terrain files and motion history.

Package and native Mac commands are in [MACOS.md](MACOS.md). New native captures
go under `.cache/native-checks/`. Promote reviewed summaries and selected frames
to versioned paths; retain raw arrays locally. Never publish saves, tokens,
certificates or unreviewed player diagnostics.

## Remaining acceptance

- Execute the actual Darwin bundle on target Macs; test audible device output,
  human balance/readability and separate internet connections.
- Sign, notarize and test a quarantined download on a clean Mac before sales.
- The owner's M3 Pro confirmation applies to 0.2.4. That precise-wait and
  elapsed-time playback behavior remains covered by the Mac-cadence fixture;
  see [performance history](history/PERFORMANCE.md).
- CI configuration has been updated, but no fresh hosted CI run is claimed.

See [release requirements](RELEASE.md) for the remaining human and platform work.
