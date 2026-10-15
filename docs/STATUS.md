# Current status

Updated **2026-10-15** · client **0.5.13 test preview** · published release **0.5.10** · protocol **4**.

## 0.5.13 full-arsenal weapon physics preview (unreleased)

The two supplied videos informed short charged throws, continuous rebounds,
rolling, water skimming, and the separation between a crater, a launched grub,
its landing and a delayed prop chain. This pass applies that physical language
to all 48 catalog entries through immutable profiles: launcher gravity and
restitution, direct-hit push, close-attack impulses, sky-drop timing, critter
movement, loose-prop mass, rope and jetpack motion, parachutes, and digging
tools. Full-power reach, weapon damage and host ownership remain unchanged;
low-power shots stay short and fused projectiles move on their last tick before
exploding.

Linux passes 361 Ruby tests / 14,538 assertions and both native prediction and
physics journeys. The Apple silicon preview is packaged and verified from
immutable commit `ee079a0` in the [Package macOS workflow](https://github.com/AliOsm/scarpe-worms/actions/runs/38802597969).
The archive checksum and runner evidence are recorded in
[the validation report](validation/weapon-physics-0.5.13.json). Its
informational rendering benchmark has shared-runner outliers: combat peaks at
73.82 ms and zoom-sweep at 127.96 ms; the workflow continued because those
benchmarks are non-blocking and do not establish physical-Mac acceptance.

This branch is for the owner's Mac playtest before release. No release tag,
publication or production deployment is part of this preview. Protocol 4 and
version-one saves remain supported. Physics belongs to the host: test in Quick
battle or host with this build to exercise it. The new client uses the old power
curve for aim dots when connected to a host without `physics_revision` metadata.
The new host advertises `physics_revision: 3`.


## 0.5.10 two-finger camera panning

Precise trackpad scroll now carries both axes through the native wheel path. A
two-finger swipe pans the free camera in the swipe direction; pinch remains
pointer-anchored zoom, and ordinary mouse-wheel zoom is unchanged. Existing
three-argument wheel subscriptions retain their wire shape, while trackpad and
pinch events append source and axis metadata. The camera journey covers
horizontal and vertical trackpad movement through native automation, alongside
minimap and middle-drag panning.

Ruby tests (348 runs / 13,905 assertions), all eight native journeys, the 59-case
native protocol suite, and Scarpe patch verification pass. A physical macOS
trackpad playtest is still useful for gesture feel and device-specific momentum.

Protocol 4, existing saves and the server/client wire compatibility remain
unchanged.

[0.5.10 is published](https://github.com/AliOsm/scarpe-worms/releases/tag/v0.5.10).
All 18 release assets and their GitHub SHA-256 digests are verified, including
the published `SHA256SUMS` and provenance files. The [release workflow](https://github.com/AliOsm/scarpe-worms/actions/runs/38726690515)
and [server deployment](https://github.com/AliOsm/scarpe-worms/actions/runs/38726690542)
pass. Production is healthy and reports **0.5.10 · protocol 4 · YJIT**.

## 0.5.9 public TLS certificate chains

The server now sends every PEM certificate after the leaf in `--cert` as the
TLS intermediate chain. This lets clients validate certificates issued by a
public CA without pinning a fingerprint; the protocol and saved-state formats
remain unchanged. The regression suite covers a multi-certificate server
handshake, and the deployed host was checked with the issued public CA
certificate after the release image was updated.

[0.5.9 is published](https://github.com/AliOsm/scarpe-worms/releases/tag/v0.5.9).
All release package and server verification jobs pass; production runs the
0.5.9 image with the renewed certificate chain.

## 0.5.7 combat responsiveness

The accepted movement experiment is included with **Settings → Responsive
movement**, on by default. Walking, jumping and backflips appear locally while
the host confirms them; changed controls send immediately. Disabling the setting
restores the original movement gate and server playback. Shared movement physics,
sequence acknowledgement, collision checks and a 400 ms / 96-command bound keep
the preview disposable. Weapons, damage, terrain and turns remain authoritative
on the host. Protocol 4 and existing saves remain compatible.

Combat preparation now creates damage labels during quiet frames and encodes
terrain PNGs faster. The Mac app bundles OpenAL Soft 1.24.3 through CoreAudio.
Its 24 effect voices preserve busy sound bursts; source installations using the
old Apple mixer retain 12 voices. Windows and Linux also use 24 effects.

[Combat validation](validation/responsiveness-0.5.7.json) records three Linux A/B
pairs: the cold blast preparation CPU maximum falls from a median 18.12 to
11.54 ms. Six native screenshots are byte-identical, and 84 terrain revisions
retain identical decoded pixels and collision checksums. A mixed-PCM probe
confirms that the former 12-voice pool cuts off a tone while the new pool retains
its tail. The controlled heavy audio workload drops from nine cut-offs to zero.
Two rounds of three Apple silicon audio-backend pairs show OpenAL Soft submission
medians around 0.03–0.04 ms, versus 0.4–0.5 ms with Apple's old mixer, and no
stolen voices with OpenAL Soft.

The Mac scheduling profile selects two 256-frame OpenAL periods. This is not
measured acoustic latency: the runner still reports a 512-frame CoreAudio buffer
at 48 kHz and a 12.75 ms device path. Frame outliers remain with both backends.
One ordinary Mac capture reached a 404.77 ms combat gap; its large wall/CPU
differences, timer overshoots and native layout work implicate scheduling and
event-loop delays, not expensive audio calls. These runner measurements do not
establish the cause of every stall on the player's Mac or promise stall-free play.
The tagged Mac capture averaged 17.79 ms in combat (p95 31.92 ms, maximum
144.07 ms), with zero stolen audio voices. Human Mac playtesting remains useful.

The existing core/native checks pass 346 Ruby tests / 13,899 assertions, eight
native journeys, 93 Rust integration tests, audio, windowed action and six-team
TLS container recovery. All required Windows, Mac and Linux package checks
pass. The Windows smoke verifies the renderer and its actual voice pool; the
Mac audio checker loads the delivered library and scheduling configuration,
then exercises all 76 cues, panning, mute and resume.

## 0.5.8 camera navigation

The battle camera now supports dragging the minimap to move its view rectangle,
removes the on-screen zoom buttons, and accepts macOS two-finger pinch gestures
through the existing pointer-anchored wheel zoom path. Keyboard zoom remains
available. Ruby, native Linux, asset, audio and container validation passes; a
physical macOS pinch playtest is still useful for input feel.

[0.5.8 is published](https://github.com/AliOsm/scarpe-worms/releases/tag/v0.5.8).
All 18 release assets are uploaded and their GitHub SHA-256 digests plus the
published `SHA256SUMS` and provenance files are verified. The [release workflow](https://github.com/AliOsm/scarpe-worms/actions/runs/38628287193),
[game/native checks](https://github.com/AliOsm/scarpe-worms/actions/runs/38628286999),
and [server deployment](https://github.com/AliOsm/scarpe-worms/actions/runs/38628286972)
pass. Production is healthy and reports **0.5.8 · protocol 4 · YJIT**.

[0.5.7 is published](https://github.com/AliOsm/scarpe-worms/releases/tag/v0.5.7).
All 18 downloaded assets and their checksums are verified; the Mac archive
contains the tag's exact 40 Ruby source files, boot code and audio profile.
The [tagged release](https://github.com/AliOsm/scarpe-worms/actions/runs/38593730150)
and [game/native checks](https://github.com/AliOsm/scarpe-worms/actions/runs/38593729966)
pass. [Production deployment](https://github.com/AliOsm/scarpe-worms/actions/runs/38593730034)
is healthy and reports **0.5.7 · protocol 4 · YJIT**.

## Earlier movement experiment evidence

The [historical experiment report](validation/client-prediction-0.5.7.json)
retains its original build, checks and rendering limits. Its deterministic
100 ms RTT / 10 Hz snapshot comparison reduced median walking onset from
267 to 8 ms and jumping from 238 to 7 ms at a 60 Hz sampling cadence. These
measure presentation state, not display photons. All 900 authoritative
checkpoint hashes matched 0.5.6; mixed-version TLS and reconnects passed.
The native journey verified movement before a delayed host response,
convergence, the settings switch and focus/charge cancellation. The experiment
was accepted by the owner; combat and audible output are the current follow-up.

## 0.5.6 Ruby 4 and Rust 1.99

Source installations require Ruby 4.0+. Development, CI, all packaged clients
and the server image use Ruby 4.0.7. Rust is pinned to 1.99.0, and patch 0026
raises the framework's Ruby and Rust minimums. Ruby 3 CI, Traveling Ruby
archives, environment-restoration shims and unused ffi ABI directories are
removed. Optional GC API checks now use Ruby 4's API directly.

macOS and Linux build relocatable Ruby from checksum-pinned sources with static
OpenSSL, libffi, libyaml and zlib. Fiddle is packaged as a gem. Windows uses the
official RubyInstaller 4.0.7-1 archive. macOS builds run on Apple silicon.
Protocol 4 and checkpoint format 1 are unchanged.

Local validation on Ruby 4.0.7 / Rust 1.99.0 passed: 328 core tests / 10,166
assertions; 93 Rust integration tests; all seven native journeys (the camera
journey passed on a quiet rerun after an initial assertion during compilation);
windowed action and 76-cue audio checks; and six-team TLS container play with
restart, session and certificate recovery. Ruby 3.4.7 is rejected before setup
or application startup. Release-helper and timing-analysis tests also pass.

The Ruby source runtime loaded Fiddle/OpenSSL/YAML/zlib after relocation to a
Unicode path with its original install hidden. All required pre-release package
checks passed: Windows install/play/resume/upgrade/uninstall and portable launch;
Linux play/recovery on Ubuntu 22.04/24.04, Debian 12 and Fedora 40, including
PulseAudio/ALSA paths; and Apple silicon signatures, relocated launch, gameplay,
input, precise timers and saved-match recovery. The first Mac build exposed
Fiddle object files retained by Ruby's gem installer; the final recipe removes
those build intermediates. [Recorded checks and CI runs](validation/runtime-0.5.6.json).

[0.5.6 is published](https://github.com/AliOsm/scarpe-worms/releases/tag/v0.5.6)
with all 18 assets verified. The tagged release and source checks passed.
[Production deployment](https://github.com/AliOsm/scarpe-worms/actions/runs/38558068643)
completed at 11:40 UTC: `ghcr.io/aliosm/burrow-brigade:0.5.6` is healthy on
port 4388 and reports version 0.5.6 / protocol 4 with YJIT. Both exported server
architectures passed TLS play and restart recovery.

The optional tagged Mac rendering benchmark recorded a 64.98 ms pan frame
against its 60 ms threshold; combat/pan means were 16.11/16.85 ms, spaced zoom
28.41 ms and continuous zoom 16.33 ms. This informational shared-runner result
is retained in the report; required Mac gameplay and timer checks passed.
Physical desktop/audio acceptance, Developer ID signing and notarization remain
outside the automated checks. Historical evidence below retains the runtime
versions actually measured.

## 0.5.5 releases for macOS, Windows and Linux

A `v*` tag now publishes a GitHub Release once every client has been built and
played on its own operating system ([release process](RELEASE.md)):

- **macOS** (`package-macos.yml`): the Apple silicon ZIP, cross-built on Linux,
  then launched on a `macos-15` runner (menu, bot match, focus/charge, resize,
  save and resume, Unicode paths). Timing benchmarks are informational.
- **Windows** (`package-windows.yml`, [guide](WINDOWS.md)): a per-user installer
  and a portable ZIP with Traveling Ruby 3.4.7 (as in aljam3-desktop), the patched renderer built
  with MSVC (new patch 0025: Windows process groups and runtime fixes) and OpenAL
  Soft. On a `windows-2022` runner the core suite passes; the installer installs
  into a Unicode path with spaces, plays and resumes a three-team bot match with
  audio, upgrades and uninstalls; the portable ZIP does the same headless.
- **Linux** (`package-linux.yml`, [guide](LINUX.md)): a portable tar.gz with
  Traveling Ruby 3.4.7, the renderer and OpenAL Soft built on Ubuntu 22.04
  (glibc 2.35). It plays, saves and resumes on Ubuntu 22.04 and 24.04 runners
  and in Debian 12 and Fedora 40 containers, headless and under Xvfb, including
  PulseAudio and ALSA playback paths.
- **Server**: amd64 and ARM64 Docker image archives built natively, reloaded and
  put through a six-team TLS match with restart recovery, plus `compose.yaml`.
  `deploy-server.yml` still publishes the GHCR image and deploys the owner's host.

Timing logs moved to platform locations: `%LOCALAPPDATA%\Burrow Brigade\Logs`
on Windows and `$XDG_STATE_HOME/burrow-brigade/logs` on Linux (macOS unchanged).
All clients are unsigned: macOS Gatekeeper and Windows SmartScreen will warn.
Nobody has yet played the Windows or Linux builds on a physical machine.

## 0.5.4 optimization round

The owner heard lagging audio while playing packaged 0.5.3 on an M3 Pro. Eight
Astra 6 Max agents swept audio, the Ruby frame loop, the native renderer, the
host, networking/playback, startup/runtime, terrain packets and terrain painting.
Each kept a change only when five interleaved runs against frozen 0.5.3 showed
a win beyond noise with no regression and unchanged pixels, simulation and wire
format ([method and per-area reports](validation/README.md)). The integrated
build was then measured against 0.5.3 again, five pairs on Ruby 3.4.7
([final Linux report](validation/perf-0.5.4-final-linux.json)):

| Measure (Linux, medians of five runs) | 0.5.3 | 0.5.4 |
| --- | --- | --- |
| Host ticks over 33 ms (six teams, heavy weapons, 900 ticks) | 16 | 0 |
| Slowest host tick / CPU per simulated second | 63 / 65 ms | 26 / 42 ms |
| Blast → terrain packet sent / crater tiles ready | 61 / 283 ms | 24 / 50 ms |
| Playback underruns in a loopback match with craters | 2 | 0 |
| Jump → event on screen (loopback) | 67 ms | 50 ms |
| Delayed sound (voice, pop, thud) start after its due time | 17.5 ms | 8.8 ms |
| Quick Battle → battlefield painted | 4.50 s | 3.39 s |
| Combat / pan presented frame mean | 16.56 / 16.67 ms | 16.59 / 16.71 ms |

- **The likely lag:** every crater made the host rebuild its whole terrain packet
  (default zlib + SHA-256) on the simulation thread, about 60 ms. In Quick battle
  the host runs on the player's Mac, so the client's playback ran dry exactly at
  the explosion, delaying its sound and picture. zlib's run-length strategy
  (any zlib reader decodes it; default compression remains the fallback for
  unusual masks) and OpenSSL hashing removed every late tick.
- Craters appear sooner: the terrain worker updates only changed minimap regions
  and filters/decodes PNG rows with packed integer arithmetic (tiles byte-identical),
  which also makes the first paint a second faster.
- Delayed sounds no longer wait an extra frame; voice selection is allocation-free.
  Big-blast captions reuse their text nodes (repeat blast frames 18–20 → 7–8 ms of
  Ruby work); playback sampling allocates less; host collision loops are cheaper;
  native patch 0024 skips a second scan of opaque images when resizing.
- Every session now writes `audio.json` beside the other timing logs: when each
  sound was due and started, drops and cut-offs, and the output device's reported
  latency and type (built-in, Bluetooth, …), without device names.

On GitHub's Apple silicon runner ([report](validation/perf-0.5.4-mac.json)), the
integrated build measured combat p95 19.1/19.7 ms and zoom 19.3/20.6 ms mean,
against 21.9/24.1 and 23.5/24.3 ms for 0.5.3 in the same hour. Raising effect
voices from 12 to 24 removed cut-off sounds on Linux but slowed Mac zoom in all
four captures (28–29 ms), so 0.5.4 keeps 12 voices. A follow-up tried 24 sources
capped at 12 playing, low spatial quality, stereo output, a matched mixer size,
other output rates and 14 or 16 voices on eight more runner captures; none kept
zoom at the 12-voice level ([report](validation/perf-0.5.4-voices.json)). Idle
sources cost nothing measurable; playing voices did.

Rejected on data: YJIT (faster match start but higher frame/tick maxima and
memory; the packaged Mac Ruby has no YJIT), GC tuning, deferred requires, four
parallel terrain painters (twice the memory), a smaller playback buffer (added
an underrun), faster PNG presets, broader effect pooling (changed pixels) and a
compressed snapshot envelope (protocol change, +67% decode CPU). In the Linux
rendering comparison the combat stage had one more single dropped frame per run
(median 3 vs 2) although per-frame Ruby and native costs were unchanged; earlier
crater loads overlapping blast frames are the likely reason. Nobody has played
0.5.4 or listened to it on a Mac yet.

## 0.5.3 grub reactions: sounds and animations (unreleased)

The owner asked for simple, funny sound effects and animations for weapons and
for grubs being hit and dying, without music. Grubs now react to every hit:

- **Hits.** The victim squeaks "oof", "ow" or "yaaah" in its team's voice; big
  hits add dizzy stars, a slide whistle and an "OUCH!" burst, and a blasted grub
  spins while it flies. A badly hurt grub may call for a medic; a grub on its
  last 20 health sweats.
- **Deaths.** A fallen grub says "buh-bye", swells for 0.6 s, pops into a puff
  with a "BYE BYE!" cloud while its winged ghost floats up, and leaves its team's
  gravestone. The host keeps the gravestone as an inert prop: it falls, flies from
  later blasts and sinks, but never hurts, blocks or delays a turn. Drowning grubs
  wail, flail and sink under a "SPLOOSH!" with bubbles.
- **Weapons and match.** Bonk, pow, whoosh and boop melee hits with comic words;
  BOOM/KABOOM bursts for big blasts; fuse sparks and sizzle; a prop plane and
  falling-bomb whistle for strikes; sheep baa, cows moo, skunks blow raspberries;
  the choir bomb sings; girders clank and the grapple goes "thwip".
- **Voices.** Kenney's CC0 soldier lines, sped up per team into squeaky voices:
  "fire in the hole", "get down", "medic", "target destroyed", "hurry up" at five
  seconds, turn-start chatter and "you win". An announcer calls the fight, sudden
  death, multi-kills, flawless victories and draws. The last grub of a team gets
  a sad trombone. Optional lines use a roll on the event id, so everyone hears the
  same ones, and chatter never talks over another line.

Two Astra 6 Max subagents made the assets in parallel: 54 new mono cues (29 Kenney
CC0 recordings, 25 original syntheses; [notes](ART_RESEARCH.md)) and 260 new frames
(four grub states for six teams and both facings, and a `reactions` effects family;
[art direction](ART_DIRECTION.md)). Burst words are drawn by the game, not baked
into art. Existing cues, music and art are byte-identical, and both builds are
reproducible. Protocol 4 and version-one checkpoints remain compatible: an older
host simply leaves gravestones where grubs fell.

Linux evidence: Ruby 4.0.7 and 3.4.7 each pass 313 tests / 9,822 assertions; all
seven native journeys, the asset and OpenAL checks and the container host check
pass. Scale-2 rendering with audio measured combat/pan means of 16.56/16.67 ms
and zoom 19.5 ms, in line with 0.5.2. The weapon lab captured knockouts, graves,
tumbling, drowning and bursts in the native window ([report](validation/reactions-0.5.3-linux.json),
[screenshots](evidence/README.md)). Nobody has listened to the new sounds yet: their
humour, intelligibility and mix, and anything on a Mac, remain unverified.

## Server deployment (live)

`.github/workflows/deploy-server.yml` deploys the host to one Linux server: a
`v*` tag matching `Burrow::VERSION` runs the container check, publishes an
x86-64/ARM image to GHCR and runs `packaging/server/deploy.sh` over SSH with a
pinned host key. Running it by hand redeploys a published version. `bin/server`
now enables YJIT, which cut the measured host tick from 1.10 to 0.80 ms (p95 4.8
to 3.0 ms); Ruby 4.0.7 alone measured the same as 3.4.7. A local rehearsal with a
stand-in registry redeployed during a six-team match in 7.1 s, keeping the room,
session, certificate and in-flight shell, and a failed pull left the running host
untouched ([report](validation/server-deploy-0.5.2.json)).

The first real deployment ran on 2026-10-14: tag `v0.5.4` published
`ghcr.io/aliosm/burrow-brigade:0.5.4` and deployed it to the owner's Ubuntu
server as root, with a dedicated deploy key and the server's pinned host keys in
the `production` environment ([run](https://github.com/AliOsm/scarpe-worms/actions/runs/38517775519)).
The container came up healthy (`Burrow Brigade 0.5.4 · protocol 4 · YJIT`). From
another network, a client completed TLS 1.3 with the published certificate
fingerprint, received `welcome` for a protocol-4 `hello` and listed rooms. A full
game client match over the internet has not been played yet.

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
zoom 20.6 ms. See the [integrated report](validation/weapons-0.5.2-linux.json). On a GitHub Apple silicon runner the packaged app launches and passes its
window and timer checks; combat/pan average 15.95–17.13/16.67–16.84 ms. Its stall
gates failed, as did unchanged 0.5.1 in the same hour, on isolated waits with
little CPU work ([Mac runner report](validation/macos-runner-0.5.2.json)). The family reports below keep each branch's own
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

The owner heard lagging audio in packaged 0.5.3 on an M3 Pro. 0.5.4 removes the
measured host stall at every crater and the extra frame wait on delayed sounds;
whether that was the lag the owner heard is not yet known. Each session's
`audio.json` and `game.json` (in `~/Library/Logs/Burrow Brigade/performance/`)
now show late, dropped and cut-off sounds and the output device type, so the
next playtest can answer it.

1. Play 0.5.0 with people: tune blast force, tumbling, fire damage and the new maps
   (island size, cave frequency, set-piece density) from their feedback.
2. Run the packaged game on the M3 Pro and clean Apple silicon Macs, including
   Retina/external displays, Finder launch, focus, resizing and sleep/wake; play
   the Windows build on a Windows 10/11 PC and the Linux build on a Wayland and an
   X11 desktop with real audio.
3. Play 0.5.4 on the M3 Pro and send the session's `audio.json`/`game.json` if
   sound still lags; note whether Bluetooth headphones were used. Listen to the
   mixed audio, including the 0.5.3 voices, squeaks and announcer
   (`ruby tools/build_audio.rb` rebuilds them; tune pitches in `Audio::VOICES`),
   and complete two-to-six-person internet matches.
   Collect human feedback on aiming, camera, balance and small-window legibility.
4. Launch the 0.5.0 archive on Macs and run the 30-minute soak; profile the isolated
   timing outlier if it reproduces, preserving the 0.2.4 precise-wait/playback fixes.
5. Complete the [release requirements](RELEASE.md) before sales.
6. Play a match through the deployed server from two networks (address,
   port 4388 and certificate fingerprint are in the deploy run's summary).

## Repository handoff

The source is self-contained. `setup.sh` (or `setup-windows.ps1`) fetches pinned
Scarpe and applies 25 independent patches; the arcade interface added 0013, the renderer investigation
added 0014–0017, cadence and clock work added 0018–0019, the zoom follow-up
added 0020–0023, the 0.5.4 round added 0024, and Windows support added 0025. Protocol 4 hosts and clients must upgrade together.
Runtime assets live in the source tree, so running the game needs no image service or
asset download. Generated bundles, raw captures and player data remain ignored.
The server image is published on GHCR and deployed from the `v0.5.4` tag; no Mac
package has been signed, notarized or published.

The [clean-checkout bootstrap report](validation/repository-bootstrap.json)
belongs to the preceding 0.3.0 baseline, not a fresh 0.4.0 clone. Current checks
ran in this workspace; CI definitions are not evidence of a CI execution.
