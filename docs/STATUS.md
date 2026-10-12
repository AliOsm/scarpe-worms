# Current status

Updated **2026-10-12** · game **0.5.0 (unreleased)** · protocol **4** · macOS preview.

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

## 0.5.0 battlefield, blast physics and multi-step weapons (unreleased)

- **Land.** A new seeded generator builds organic islands from layered noise. Each island
  has a character (hills, summit, valley, mesa or a volcanic cone) and ends in a beach,
  cliff or undercut overhang that slopes into the sea. Islands have sea grottos,
  walkable caves, winding tunnels, floating rocks and girders. Biome set pieces (towers,
  colonnades, henges, walls, arches, ziggurats, obelisks, igloos, ice spires, basalt
  columns and aqueducts) are drawn into the same destructible mask. Caverns gain a
  stalactite roof within grapple reach, side walls and pillars.
- **Look.** Craters get charred rims with no grass on their floors (soil material 4).
  Painted fills wrap seamlessly, without mirror axes. Water is deeper, nearly opaque,
  has a pale crest and extends below the world. Generation takes 40–130 ms (it was
  100–200 ms).
- **Blast physics.** Explosions push along the line from their centre and add lift.
  Blasted grubs tumble, rebound off walls and slide to a stop without fall damage.
  Blasts throw resting bombs, mines, barrels, crates and sentries. Close mines and
  barrels chain after short, staggered fuses. Firebombs, barrels and the flamethrower
  spill flames that fall, creep downhill and scald. Bombs roll down steep slopes, and
  bounciness varies by weapon. A turn waits for fire and props to settle.
- **Multi-step weapons.** Love letter (homing) is two steps: lock a target, then aim and
  charge with the mouse or Space; Backspace re-targets. Its cruise speed follows launch
  power, and its motor burns out after 4.5 s. Air support takes an approach direction
  (← →) and lands across the target. Girders tilt in 22.5° steps. Fruit salad splits
  early on a second press.
- **Fixes.** Rotated sprites (rockets, held weapons) now turn about their centres
  instead of their top-left corners. Ground probes align to cells, so clicking an odd
  pixel on a slope no longer rejects a teleport.
- Protocol 4: new `fire` parameters (`direction`, `rotation`) and new hazard kinds.
  Checkpoints keep their format; older saves restore, and their fire zones keep burning.

Evidence (Linux): core suites on Ruby 3.4.7 and 4.0.7 (111 runs / 5,085 assertions each),
seven native journeys (including new homing, girder, strike and split input paths),
the rendering benchmark within budget, byte-identical art rebuilds and asset checks,
and six full bot matches on every terrain type
([report](validation/battlefield-0.5.0-linux.json), [screenshots](evidence/README.md)).
A 0.5.0 Apple silicon archive was cross-built on Linux and passed static,
integrity and Linux-substituted packaged-code checks ([integrity](validation/distributable-0.5.0.json),
[static](validation/macos-arm64-package-0.5.0.json)). The packaged app subsequently
ran on an Apple silicon CI runner: its sustained rendering gate failed (see the
renderer investigation below). The 30-minute soak, Retina Mac validation and
human playtesting remain outstanding.

## Arcade interface (unreleased)

Built on 0.4.0 without a version or protocol change; it ships with 0.5.0:

- Glossy blue frames with ink outlines, navy wells, cyan bubble titles, yellow menu
  text and red back arrows across the menu, room browser, lobby, every dialog and results.
  The menu uses `menu-scene.png`, derived from the existing hash-pinned masters.
- Battle HUD: team health capsules with portraits, a wind gauge, the turn timer and a
  weapon dock. Grub names, health and floating numbers use outlined lettering.
- Arsenal: one row per weapon family, `xN` ammo counts, arrow-key navigation. Slots are
  clickable images whose alt text names the weapon and its ammo.
- Scarpe patch 0013 paints bare buttons, so the glossy controls stay real buttons.
- Match screens use solid fills instead of gradients and build grub names lazily, keeping
  rendering on par with 0.4.0 ([art rules](ART_DIRECTION.md#interface)).

Evidence: core suites on Ruby 3.4.7 and 4.0.7, seven native journeys (209 assertions),
an alternating 0.4.0/restyle rendering comparison and asset checks, all on Linux; see
[validation](VALIDATION.md#arcade-interface-restyle-unreleased). Not yet run: macOS,
packaged code, the 30-minute soak and a human review of the new look. Arsenal slots are
reached by arrow keys rather than Tab focus.

## Evidence and limits

The table below is the 0.4.0 release evidence; 0.5.0's Linux results are summarized above.

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

Most execution evidence is Linux. Packaged 0.5.0 also ran on Apple silicon CI,
where the sustained-rendering gate failed on a 1× surface. The owner's M3 Pro
smoothness report was for 0.2.4, whose timing fixes are preserved. Updated Retina
Mac execution, human audio checks, real internet matches and signing/notarization
remain outstanding.
This is a preview, not a certified sales release.

## Renderer investigation (2026-10-12)

Independent patches 0014–0017 preserve static frame regions during large camera
repaints, retain a bounded cache of animation paths, dispatch native frame deadlines
before AppKit drains redraws, and avoid cloning parsed property maps. No game rules
or Ruby scheduling changed. Linux measurements and checks are in the
[renderer report](validation/renderer-per-frame-0.5.0.json); code and Mac present-path
findings are in the [performance history](history/PERFORMANCE.md#050-renderer-investigation-2026-10-12).

Patch verification, 364 Rust tests, 111 Ruby tests, all 7 native journeys and the
final rendering gate passed. The report also retains an earlier native timing
failure and an adverse rendering capture; their causes remain unestablished.

The earlier Mac CI run had combat/pan presentation means of 22.27/24.62 ms despite
paint/present means below 4 ms each. Its 1280×653, 1× surface does not test the
owner's Retina display. The new patches need a packaged Mac run, device listening
and an M3 Pro comparison before claiming the reported 0.5.0 regression is fixed.

## Next checks

1. Play 0.5.0 with people: tune blast force, tumbling, fire damage and the new maps
   (island size, cave frequency, set-piece density) from their feedback.
2. Run the packaged game on the M3 Pro and clean Apple silicon Macs, including
   Retina/external displays, Finder launch, focus, resizing and sleep/wake.
3. Listen to the mixed audio and complete two-to-six-person internet matches.
   Collect human feedback on aiming, camera, balance and small-window legibility.
4. Launch the 0.5.0 archive on Macs and run the 30-minute soak; profile the isolated
   timing outlier if it reproduces, preserving the 0.2.4 precise-wait/playback fixes.
5. Complete the [release requirements](RELEASE.md) before sales.

## Repository handoff

The source is self-contained. `setup.sh` fetches pinned Scarpe and applies 17
independent patches; the arcade interface added 0013 and the renderer investigation
added 0014–0017. Protocol 4 hosts and clients must upgrade together.
Runtime assets live in the source tree, so running the game needs no image service or
asset download. Generated bundles, raw captures and player data remain ignored.
No publishing or deployment was performed.

The [clean-checkout bootstrap report](validation/repository-bootstrap.json)
belongs to the preceding 0.3.0 baseline, not a fresh 0.4.0 clone. Current checks
ran in this workspace; CI definitions are not evidence of a CI execution.
