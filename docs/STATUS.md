# Current status

Updated **2026-10-13** · game **0.5.2 (unreleased)** · protocol **4** · macOS preview.

## 0.5.2 weapons sweep (unreleased)

The owner found 0.5.1's weapons broken or cheap: the jetpack would not fly, the
grapple would not catch, and Captain wool spun while flying with loose steering.
All 48 weapons were reworked one by one in four families, each with its own
mechanics fixes, original in-world art, effects, audio cues, HUD hints and
regression tests, then integrated on `weapons/integration`:

- **Mobility.** Grapple fires a visible hook along the aim, swings and reels with
  WASD/arrows and keeps momentum on release. The jetpack flies with WASD thrust and
  five seconds of fuel burned only while thrusting. Soft landing, teleport and
  girder placement show their result before committing.
- **Munitions.** The 16 launchers, explosives and air strikes have dedicated flight
  and fragment art, distinct blasts, bounded camera shake and fixes for fuse,
  sticky, dynamite, strike and earthquake behaviour.
- **Critters.** Upright, mirrored animation replaces spinning icons. Captain wool
  keeps its heading art level, steers immediately with arrows or A/D, and a third
  press detonates it; the sheep, mole, skunk and cows got stage hints and fixes.
- **Close-up, hazards, tools and supplies.** Shotgun pellets, rifle tracers,
  minigun bursts, a piercing laser and a persistent flamethrower stream; visible
  melee poses with fixed launches; validated mine/sentry/barrel placement ahead of
  the grub; deterministic drill and blowtorch with early stop; supplies that state
  whether they keep the turn.

Integration keeps munitions' terrain-first contact rule while a diving mole still
strikes a grub at the surface, and merges every family's HUD labels, cues and lab
scripts. Starting mines and barrels now need ground under their centre and mines
start well clear of grubs: about a quarter of starting props used to slide off overhang
tips at match start, occasionally onto a grub, and a few mines went off untouched. Protocol 4 and version-one checkpoints remain supported.

Integrated Linux evidence: Ruby 4.0.7 and 3.4.7 each pass 296 tests / 8,994
assertions; all seven native journeys pass; assets pass and a full art rebuild is
byte-identical. A native lab drove all 48 weapons through real input with no errors; the
close and munitions checkers pass every weapon (Choir bomb after a rerun that caught its
0.6 s warning between captures), and rope, jetpack and parachute traces show hooking,
swinging, powered flight and safe descent. Action cadence passes at 16.53 ms mean /
21.57 ms p95; scale-2 rendering with audio passes at combat/pan means of 16.55/16.70 ms,
zoom 20.6 ms. See the [integrated report](validation/weapons-0.5.2-linux.json). The family reports below keep each branch's own
measurements, including failed and retried captures. Feel, balance and audible
output on the owner's Mac remain the acceptance check.

### Mobility family

Grapple line now fires a visible hook along the aim, swings and reels with WASD or
arrows, and preserves momentum on release; airborne re-hooks share one cartridge
until landing. Personal cloud supports WASD thrust, five seconds of fuel burned
only while thrusting, a fuel readout, and animated equipment. Soft landing has a
visible canopy that opens during descent after arming, with steering and safe falls.
Here to there and Bridge builder share host/preview placement checks, show invalid
targets, and complete their turns. Original equipment art, teleport effects, local
audio receipts, input acknowledgement gates, and old-checkpoint defaults accompany
the mechanics.

Linux evidence: 156 tests / 6,115 assertions on both Ruby 4.0.7 and 3.4.7; seven
native journeys / 237 assertions; a final controls rerun; all five native weapon
labs with 53 captures and no notices; asset/audio checks and byte-identical art
rebuilds. The action benchmark and final rendering capture passed: combat mean /
p95 / max 16.64 / 20.26 / 46.09 ms, pan 16.66 / 19.71 / 25.20 ms. The
[mobility report](validation/weapons-mobility-linux.json) retains earlier failed
captures and a foundation comparison that recorded CPU scheduling contention;
the final pass does not establish the cause of every earlier stall. Physical Mac
play and audible output remain untested. Rope uses one anchor without corner
wrapping; girders retain a fixed 140-pixel length.

### Munitions family

The 16 munitions now have dedicated flight/fragment art, distinct impacts and
existing-cue audio feedback. Corrections cover choir fuse expiry, close-wall
dynamite placement, terminal sticky attachment, legacy fragment playback, staged
air support, edge-entry drops and earthquake rope/prop impulses. Aircraft survive
zoom and window rebuilds; bounded camera shake respects reduced motion.

The [munition validation report](validation/munitions-sweep.json) records each
weapon's findings, tests, native lab evidence and shared-file integration notes.
Ruby 4.0.7 and 3.4.7 each pass 175 tests / 7,346 assertions; all seven native
journeys pass. The art checker covers all 162 new frames and rebuilds are
byte-identical. All 16 native lab cases pass. Action cadence passes at 16.09ms
mean / 20.83ms p95; scale-2 rendering with audio passes with combat/pan means
of 16.22/16.66ms. The action checker now uses the existing rendering analysis to
exclude measured idle gaps; the report retains its original failures and the
diagnostic comparison, with no relaxed budgets.

The remaining product check is human feel/balance and audible
output on the owner's Mac; this branch's native measurements run on Linux.

### Critter family

The critter family now has dedicated mirrored in-world animation instead of
spinning arsenal icons. Captain wool uses immediate arrow/A/D steering intents,
a separate eight-second flight timer, and a third press to detonate. Late
launches retain the turn through flight and falling. Sheep turnarounds use
blocked simulation ticks; Tunnel buddy has digging feedback; Stink express
keeps four seconds of spray after late activation; cows have contact sweeps and
staggered low calls using an existing cue. Stage hints and Fire labels match.
The lab also exposed a shared first-frame effect bug: newly created explosions
could request frame −1 and flash a missing-image rectangle. Effect age now
starts at zero, covered by a renderer regression.

Protocol 4 and version-one checkpoints remain supported. See the critter rows
in [the weapon audit](WEAPON_AUDIT.md) for the controls and regression coverage.
Linux validation is recorded in [the critter report](validation/weapons-critters-linux.json).
Both Ruby versions pass 172 tests / 6,883 assertions; all seven native journeys
pass (229 assertions). Assets and byte-identical rebuilds pass, and lab captures
cover all five weapons through turn completion. The final rendering gate passes
(combat/pan means 16.54/16.71 ms); two earlier worst-frame failures and the
scheduling profile are retained in the report rather than hidden by the retry.
Physical Mac play and listening remain part of the owner acceptance checks.

### Close-up, hazards, tools and supplies family

The close-family branch validated each of its 22 weapons through native input
with numeric acceptance checks (`tools/check_close_lab.py`) over the lab's
authoritative logs, plus 44 focused tests. Its branch run passed both Rubies, all
seven native journeys, the action cadence check (16.96 ms mean, 22.57 ms p95) and
the rendering benchmark; the blowtorch lab script was tightened and rerun.

## 0.5.1 performance sweep (unreleased)

The owner found 0.5.0 stuttering, with lagging audio, on an M3 Pro. Measured on a
GitHub Apple silicon runner (packaged app, 1280×656 at 1×, 60 Hz), the fixes moved combat
from 21.6 to 16.0–16.2 ms mean presented intervals (p95 29.9 → 18.8–22.1 ms) and pan
from 21.9 to 16.7 ms: the Mac now presents nearly every 60 Hz update. Linux combat and
pan stay at 16.5/16.7 ms with 25–30% cheaper painting.

- Native pacing no longer adds a software refresh wait on macOS (patch 0018); deadlines
  are taken before AppKit drains redraws (0016). Static HUD pixels survive large
  partial repaints (0014), animation frames stay cached (0015), and parsed property
  maps move instead of cloning (0017). Patch 0019 corrects Mac timing diagnostics.
- The Ruby frame loop skips unchanged properties, reuses actor data, builds names
  lazily and animates only visible flames. A zoom regression from hiding offscreen
  hazards was found and removed.
- Your own fire, jump and activation sounds play as soon as the input is accepted
  (≈200 ms → <1 ms to OpenAL); loopback snapshots run at 30 Hz with incremental
  motion history (≈41 → 18 KB), and adaptive playback buffers 50–150 ms instead of a
  fixed 150 ms, cutting Fire→visible projectile from ≈199 to ≈72 ms locally.

Zoom remains the weakest motion (Mac 21.8–31.1 ms mean; Linux 19.7–23.1 ms), and
occasional single stalls still exceed 50 ms. ProMotion/Retina, physical display output
and audible latency still need the owner's Mac.

## Implemented

Burrow Brigade supports two to six teams, bots, 48 weapons/tools, four seeded
destructible biomes, self-hosted TLS rooms, reconnects, saves and rematches.
It uses native Scarpe; host simulation and terrain painting run outside the GUI.

Local input feedback now submits fire, jump and activation sounds immediately,
with exact host-event receipts preventing duplicate reports. Loopback matches
send incremental snapshots at 30 Hz; a measured 50–150 ms playback buffer retains
the elapsed-time, short-flight and history-recovery protections from 0.2.4.
The [latency/audio report](validation/latency-audio-linux.json) records TCP/TLS
latency, snapshot/CPU costs and native checks, including a rendering outlier.
These are Linux OpenAL submission and Timeline measurements; audible Mac output,
display latency and real internet jitter still need testing.

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

## Mac cadence follow-up (2026-10-13)

The packaged integration run on Apple silicon still coalesced continuous pan:
357 moving Ruby updates produced 274 paints (21.90 ms mean / 29.44 ms p95).
Software frame deadlines arrived 5.70 ms late on average. Patch 0018 requests
AppKit redraws when complete dirty updates arrive, preserving Linux pacing and
all precise-timer protections. Ruby timers already use a fixed monotonic grid.
The 144.8 ms maximum redraw in that capture belongs to startup, before combat;
a separate 268.8 ms combat gap included a large layout/system stall.

Patch 0019 appends live frame wall-clock anchors to correct drift between Rust's
raw clock and Ruby wall time; durations remain monotonic and budgets unchanged.
Two packaged captures with corrected correlation restored pan means to
16.77/16.66 ms (358/359 and 361/361 paints/updates), with p95 20.93/17.96 ms.
Combat mean/p95 was 15.98/22.13 and 16.23/18.78 ms. Both runs still failed the
strict maximum-interval gate: a 67.09 ms pan gap and a 95.43 ms combat gap.
The first overlaps a 32.04 ms native paint and a Ruby wait overshoot of 24.67 ms;
the exact cause remains unresolved. The second gap includes 44.25 ms accumulated
layout and 44.15 ms outside measured native phases, while Ruby keeps updating.
Timestamped batch receipt/redraw events and native layout CPU time are the next
diagnostics needed to attribute that delay. The
[cadence report](validation/mac-cadence-0.5.0.json) retains all four Mac attempts,
the clock defect and Linux before/after captures.

Patch verification, 368 Rust tests (11 ignored), 133 Ruby tests/5,979 assertions,
seven native journeys/228 assertions, timer regressions and rendering-analysis
tests passed. Final Linux rendering passed both normally and with 100 ms timer
slack. This establishes a submission-cadence improvement, not every-update
delivery: combat motion selection is heuristic, paint/update counts do not
identify individual batches, and physical scanout, ProMotion/Retina and audible
device output still require physical Mac validation.

## Zoom and stall follow-up (2026-10-13)

Round 3b keeps the elapsed-time camera zoom and continuous `zoom_sweep` journey,
shares repeated native text shaping, records frame-stall phases, and culls fully
clipped image resizes. Terrain presentation now defers offscreen tile geometry
without show/hide messages; resize restores the last completed terrain result and
keeps its worker and playback timeline. The package smoke resize check passed 40
C-locale/default launches in the local repetition; the earlier CI failure was timing
dependent and did not reproduce with diagnostics.

The Apple silicon run 38345368622 measured combat 16.05/19.77/41.06 ms, pan
17.15/23.38/81.41 ms, discrete zoom 24.88/58.87/121.90 ms, and the continuous
zoom sweep 16.33/20.07/40.12 ms (mean/p95/max). Its active discrete zoom was
15.09/19.90/22.96 ms. The discrete zoom tail is mostly
intentional idle time: its active intervals were 15.66/20.69/36.95 ms. A 60.07 ms
GUI update used 0.76 ms CPU while native presentation used 58.74 ms wall time and
1.04 ms CPU, so the outlier is waiting or descheduling rather than Ruby or paint
work. Patch 0023 corrects coalesced-batch diagnostic attribution; no timer or
pacing change is justified by this evidence.

See [zoom validation](validation/zoom-0.5.1.json) for alternating Linux captures,
Mac limits, and the kept/reverted change decisions.

## Next checks

The owner reports dropped frames and lagging audio in packaged 0.5.0 on an M3 Pro.
The Ruby frame workstream now suppresses unchanged native properties, reuses actor
presentation data, builds at most two names per frame, and defers invisible hazard
animation and actor resizes. The visible deterministic native fixtures are
byte-identical before and after on Ruby 3.4.7 and 4.0.7. On Linux Ruby 3.4.7,
the idle 36-grub/60-flame scene drops from 4,039 to 182 allocations per frame;
animated flames drop from 4,711 to 825. Both core suites and seven native journeys
pass. The [Ruby frame report](validation/ruby-frame-0.5.0-linux.json) records live
measurements, failed captures under CPU contention, and remaining zoom bursts.
These Ruby changes are included in the packaged Mac cadence captures above;
they do not establish that every frame meets its deadline or that the reported
audio lag is resolved.

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

The source is self-contained. `setup.sh` fetches pinned Scarpe and applies 23
independent patches; the arcade interface added 0013, the renderer investigation
added 0014–0017, cadence and clock work added 0018–0019, and the zoom follow-up
added 0020–0023. Protocol 4 hosts and clients must upgrade together.
Runtime assets live in the source tree, so running the game needs no image service or
asset download. Generated bundles, raw captures and player data remain ignored.
No publishing or deployment was performed.

The [clean-checkout bootstrap report](validation/repository-bootstrap.json)
belongs to the preceding 0.3.0 baseline, not a fresh 0.4.0 clone. Current checks
ran in this workspace; CI definitions are not evidence of a CI execution.
