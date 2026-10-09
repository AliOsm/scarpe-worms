# Current status

Updated **2026-10-09** · game **0.3.0** · protocol **3** · macOS preview.

## Implemented

- Two to six teams, bots, large seeded destructible maps, four biomes, custom rules.
- 48 weapons/tools; staged critters, directional steering, rope reeling, jetpack fuel.
- Self-hosted TLS multiplayer, reconnects, checkpoints, rematches, Docker/systemd.
- Native Scarpe UI, generated artwork/audio, and an Apple silicon macOS packager.

The 0.3.0 sweep improved terrain/backdrops, weapon physics, and input reliability.
See the [weapon audit](WEAPON_AUDIT.md) for contracts and intentional differences
from reference games. The owner says it looks better and still wants more polish.

## Evidence and limits

| Evidence | Result |
| --- | --- |
| Core suite | 80 tests / 4,902 assertions on Ruby 3.4.7 and 4.0.7 |
| Native interaction journeys | Six journeys / 172 assertions |
| Packaged Linux window benchmark | Combat mean 16.81 ms; p95 21.14 ms at simulated 2× density |
| Timing stress check | Passed with 100 ms Linux timer slack |
| Owner's Mac feedback | 0.2.4 confirmed smooth on M3 Pro; 0.3.0 visuals improved |

The [0.3.0 report](validation/release-0.3.0.json) records exactly what ran.
Linux package checks substitute Linux executables; native Mac acceptance of the
new build, real audio, internet playtesting, and notarization remain outstanding.

## Next work

1. Refine art/UI with native screenshots at actual gameplay sizes; the owner
   still wants visual improvements. Keep foreground collision boundaries clear.
2. Collect concrete weapon/control edge cases and add regressions before fixes.
   The arsenal was audited, but human balance and polish need more playtesting.
3. Run packaged checks on the M3 Pro, then clean Macs and real internet matches.
4. Complete signing/notarization and the [release checklist](RELEASE.md) before sales.

Preserve the resolved frame-pacing fix. Single-anchor rope without corner wrapping,
a fixed three-critter herd, and original balance values are intentional contracts.

## Repository handoff

The source is self-contained; `setup.sh` fetches upstream Scarpe and applies 12
independent patches. No sibling repositories or local build caches are needed.
Tests, generators, package recipes, and third-party notices are included.
Repository organization does not change gameplay or rebuild the previous preview
ZIP; rebuild from this checkout to include the updated documentation.
