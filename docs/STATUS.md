# Current status

Updated **2026-10-09** · game **0.4.0** · protocol **3** · macOS preview.

## Implemented

Burrow Brigade supports two to six teams, bots, 48 weapons/tools, four seeded
destructible biomes, self-hosted TLS rooms, reconnects, saves and rematches.
It uses native Scarpe; host simulation and terrain painting run outside the GUI.

The 0.4.0 presentation pass adds:

- An original painted menu, four atmospheric skies and four painted materials;
  sharper characters, props, effects and icons, plus directional combat sprites.
- Redesigned menus, lobby, arsenal and results; room pagination, live scrollable
  chat, preserved drafts/notices, readable badges, wind and retreat indicators.
- Pointer-anchored zoom, explicit overview, smoother shot following and impact
  framing, bounded scenery parallax and brief turn cues. Manual exploration
  persists until **F / Follow**; reduced motion disables decorative drift.
- Twelve licensed CC0 samples within 22 audio cues, preloaded voices, distinct
  weapon reports and camera-relative stereo positioning of mono effects.
- Local deterministic asset compilation with source prompts, hashes and notices.
- Worker startup preserves filesystem bytes when an installation path contains
  Unicode and the launch locale is unset or ASCII.

See [native screenshots](evidence/README.md), [research](ART_RESEARCH.md), and
[art contracts](ART_DIRECTION.md). No Team17 assets or code are distributed.
Claude Opus 5.5 reviewed the integrated work after its initial access outage;
the implementation continued under the user's authorized model fallback.

## Evidence and limits

| Evidence | Result |
| --- | --- |
| Core on Ruby 3.4.7 and 4.0.7 | 91 tests / 5,014 assertions each; no failures |
| Native interaction journeys | Seven journeys / 204 assertions; no failures |
| Source rendering, simulated 2× density | Combat mean 16.10 ms; p95 19.91 ms; max 32.01 ms |
| Source with 100 ms timer slack | Combat mean 16.33 ms; p95 20.25 ms; max 31.59 ms |
| Packaged rendering, simulated 2× density | Combat mean 16.57 ms; p95 20.41 ms; max 57.36 ms |
| Packaged with 100 ms timer slack | Combat mean 16.48 ms; p95 21.16 ms; max 38.14 ms |
| Archive and relocated runtime | Integrity/static checks; fresh/resumed launch under unset and C locales with Unicode installation/data paths |
| Art/audio rebuilds | Two full builds; 618 files byte-identical, including a clean preview-mask build |
| Asset and audio checks | 516 runtime PNGs, exact terrain masks, 22 decoded/mixed cues |
| 30-minute source endurance | 14 matches, 580 turns, 59 resizes; one scene/terrain worker retained after each rematch |

The [validation guide](VALIDATION.md) and [versioned reports](validation/README.md)
record the build and platform actually measured. Packaged checks substitute
Linux executables while exercising the delivered Ruby code and assets.
An earlier 61.23 ms combat outlier remains
documented; subsequent passing captures do not establish its cause or promise
every frame reaches 60 FPS.

All current execution evidence is Linux. The owner's M3 Pro smoothness report
was for 0.2.4, whose timing fixes are preserved. Native 0.4.0 Mac execution,
audible sound, real internet matches and signing/notarization remain outstanding.
This is a preview, not a certified sales release.

## Next checks

1. Run the packaged game on the M3 Pro and clean Apple silicon Macs, including
   Retina/external displays, Finder launch, focus, resizing and sleep/wake.
2. Listen to the mixed audio and complete two-to-six-person internet matches.
   Collect human feedback on aiming, camera, balance and small-window legibility.
3. Profile the isolated timing outlier if it reproduces on target hardware;
   preserve strict budgets and the 0.2.4 precise-wait/playback fixes.
4. Complete the [release requirements](RELEASE.md) before sales.

## Repository handoff

The source is self-contained. `setup.sh` fetches pinned Scarpe and applies 12
independent patches; this pass makes no new framework patch or protocol change.
Runtime assets live in the source tree, so running the game needs no image service or
asset download. Generated bundles, raw captures and player data remain ignored.
No publishing or deployment was performed.

The [clean-checkout bootstrap report](validation/repository-bootstrap.json)
belongs to the preceding 0.3.0 baseline, not a fresh 0.4.0 clone. Current checks
ran in this workspace; CI definitions are not evidence of a CI execution.
