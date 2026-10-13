# Weapon, input, and presentation audit — 0.5.0

This is Burrow Brigade's implemented contract, first reviewed on 2026-10-09 and
updated for 0.5.0 on 2026-10-12 (see [0.5.0 changes](#050-blast-physics-and-multi-step-weapons)). Its 48
weapons have original names, art, and balance values. It is not a compatibility
implementation of a particular Worms release. [WEAPONS.md](WEAPONS.md) lists
all 48 entries, ammunition defaults, and their current in-game descriptions.

## Research and decisions

The [Team17 World Party manual](https://cdn.akamai.steamstatic.com/steam/apps/270910/manuals/Worms_World_Party_Remastered_MANUAL.pdf)
distinguishes charged throws, instantaneous guns, target selection, remote
activation, and mobility controls. That distinction now drives the input layer:
only throws charge; other actions use a press; target locking is a separate
step; each remote stage displays its own action. The manual also documents two
shotgun shots, rope reeling, and stopping a digging tool. These are now explicit
contracts with regression and native input coverage.

The archived Team17 Wormopedia describes [Super Sheep](https://wormopedia.worms2d.info/Super_Sheep_%26_Aqua_Sheep)
as a runner that launches upward on its second activation, then turns using
Left/Right. Captain wool now follows those stages instead of chasing the cursor.
Its third activation drops it into a gravity-driven flight. Turning preserves
speed, and a lost or released steering input expires.

The [Mole Bomb reference](https://wormopedia.worms2d.info/Mole_Bomb) describes
running, a player-triggered jump, then digging and detonation. Tunnel buddy now
runs first, dives on command, digs on terrain contact, and detonates on a grub,
tunnel exit, timeout, or another activation. The [Sheep reference](https://wormopedia.worms2d.info/Sheep)
informs obstacle hopping and manual detonation for Woolly menace. The
[Mad Cows reference](https://wormopedia.worms2d.info/Mad_Cows) informs staggered
runners that explode on impact; our fixed three-critter herd is an intentional
simplification. [Skunk](https://wormopedia.worms2d.info/Skunk) informs poison
clouds and a small final blast; spraying is an explicit second activation here.

[Homing Missile](https://wormopedia.worms2d.info/Homing_Missile) separates the
impact marker from the launch. Our marker stays fixed while aiming, and its
rocket has a delayed motor, limited angular turn rate, maintained speed, and
underwater travel until it leaves the world. [Mortar](https://wormopedia.worms2d.info/Mortar)
is a fixed-power impact shell with fragments; Moon mortar now does that.
[Cluster Bomb](https://wormopedia.worms2d.info/Cluster_Bomb) informs the parent
fuse and secondary fragments. Damage boosts now apply to the fragments too.

[Jet Pack](https://wormopedia.worms2d.info/Jet_Pack) emphasizes fuel conservation.
Fuel now drains during thrust, and the HUD displays its remaining thrust time.
Exhaustion or manual shutdown deploys a parachute. The
[Ninja Rope reference](https://wormopedia.worms2d.info/Ninja_Rope) informs swinging
and firing from a suspended position. Our grapple has one anchor, a 460-unit
reach, and 28–460-unit reeling; it does not implement corner wrapping or a
competitive rope-racing ruleset. Reeling cannot pull a body through solid ground.

The requested [WMD Steam reference](https://store.steampowered.com/app/327030/Worms_WMD/)
and [Team17's WMD presentation](https://www.team17.com/games/worms-w-m-d)
provide the visual direction: illustrated 2D environments, expressive characters,
and strong separation between playable terrain and scenery. Their artwork is a
reference, not an asset source. Original asset provenance and generator contracts
are recorded in [ART_DIRECTION.md](ART_DIRECTION.md).

## Arsenal sweep

| Entries | Contract checked or corrected |
| --- | --- |
| Pocket rocket | Charge/wind and swept impacts verified; dedicated heading-aligned rocket, motor trail, warm flash and debris. |
| Moon mortar | Fixed-power impact shell; five distinct small fragments inherit 30% horizontal momentum and damage boost; no recursive split or fragment fuse badges. |
| Love letter | Lock → aim/charge; half-second ballistic launch, bounded powered steering through age 4.5s, then gravity. Powered/coasting sprites and trails follow motor age; legacy saves retain cruise defaults. |
| Tick-tock | Exact 1–5s fuse through body/ground bounces; surface-normal rolling and support loss verified. Pin/lever grenade art, slow tumble, readable fuse and blast. |
| Party popper | Timed bouncing shell and five distinct small bomblets. Fragments retain horizontal momentum and boosted damage, settle before handover and never fragment recursively. |
| Fruit salad | Owner-only Fire split spends no extra ammo; six distinct bananettes, boosted damage and inherited momentum; yellow burst and locally predicted split sound. |
| Velcro bomb | Terrain takes priority over a body behind a wall. Body attachment follows the grub through the final fuse tick and releases on death; terrain attachment falls if support disappears. Dedicated adhesive bomb and violet-tinted blast. |
| Short fuse | Swept near-foot placement cannot cross a close wall or attach to its deploying owner. Fixed 4s fuse, retreat controls, animated sparks, heavy blast and immediate fuse-tick sound. |
| Big trouble | Adjustable fuse and heavy restitution verified; oversized original bomb, sparking fuse, larger flash/smoke/debris and bounded shake. |
| Choir bomb | Corrected airborne freeze at fuse expiry. Keeps falling after 5s, rests, then emits one 0.6s chord/glow before its huge blast; 12s total safety lifetime. Rest/chord badges and checkpoint recovery verified. |
| Double tap | Two separately aimed shots per cartridge, including the final cartridge; switching locked between shots. |
| Long goodbye | Instant terrain-blocked ray; no muzzle gap through close walls. |
| Peashooter | Eight visible rounds over time; saved burst queue survives host recovery. |
| Sunbeam | Piercing ray, terrain cutting, one hit per body per ray. |
| Hot breath | Seven timed short-range rays; each spills loose flames where it stops. |
| Uppercrust | Close uppercut with upward motion and knockback; ordinary melee cannot hit through walls. |
| Dragon dash | Movement spans twelve ticks; carves along its path; hits each body once. |
| Little nudge | Zero-damage shove; terrain obstruction respected. |
| Home run | Angle-sensitive knockback; frozen bodies stay still. |
| Half measure | Halves current health before configured damage modifiers. |
| Special delivery | Visible bomber pass survives zoom/window rebuilds and follows playback time; five delayed drops follow the selected side and span about 152px at the target. Off-map approach releases survive long enough to enter, including low gravity. Dedicated impact bombs, launch cue and blasts. |
| Rain check | Same timed approach; dedicated dropped mines land, arm for 40 ticks, then trigger after 18 ticks near a grub. Persistent mines and pending releases restore exactly. |
| Spicy forecast | Same timed approach; original firebomb sprites, orange fire bursts and bounded loose flames. Turn waits for fire to burn out. |
| Bad astronomy | Six seeded, staggered flaming rocks cover the battlefield; launch positions compensate horizontal fall so edge rocks do not disappear. Fiery trails and rock blasts; no target needed; cavern restriction. |
| Rumble button | Seeded impulses detach ropes and move loose props without prematurely igniting them; frozen grubs and terrain remain intact. Bounded camera shake, ground dust and immediate heavy report; reduced motion disables shake. |
| Woolly menace | Hops at obstacles/ledges; manual or timed detonation. |
| Captain wool | Walking → upward launch → directional flight → falling; collision and lifetime termination. |
| Tunnel buddy | Walking → dive → digging → detonation; tunnel exit detection probes ahead of carved material. |
| Stink express | Walking → activated spray → final gas and small blast. |
| Cattle call | Three timed releases; pending cows are invisible and do not collide before release. |
| Mind your step | Arms after deployment; delayed proximity trigger; persistent hazard; blasts throw it and close blasts arm a short fuse. |
| Sentry sprout | Five shots, range and line-of-sight limits, enemy selection. |
| Red barrel | Persistent explosive; blasts throw and dent it, and a ruptured barrel explodes after a short delay, spilling flames. |
| Grapple line | Validated overhead attachment; swing/reel/release; destroyed anchors detach; no extra ammo for releasing. |
| Personal cloud | Directional thrust; fuel conservation; mutually exclusive with rope; graceful fuel exhaustion. |
| Soft landing | Slows descent; suppresses fall damage; directional drift. |
| Here to there | Clear landing and occupied-body validation before spending ammo; ends turn. |
| Bridge builder | ← → tilts the beam in 22.5° steps up to vertical; tilted preview; collision and bounds validation along the beam before spending ammo. |
| Down we go, Side hustle | Bounded-duration terrain tools; early stop; steerable torch slope; checkpoint recovery. |
| First aid | Health cap, poison cure, rejects wasted use without spending ammo. |
| Bubble wrap, Ice break | Protection lifetime through the team's next turn; frozen grubs resist weapon knockback. |
| Stink bomb | Exact bouncing fuse; drifting poison cloud changes status without a crater or premature body-impact blast. Leaking canister, toxic bloom and release impact cue. |
| Extra spicy, Moon boots, Weather vane | Attack damage, current-turn gravity, and bounded wind changes; utility actions preserve the turn. |
| Pass the turn | Settles safely before handover; unavailable between shotgun shots. |

These contracts cover the implemented arsenal, not a claim that its tuning,
weapon roster, or every advanced move is identical to Worms.

## Input reliability

The client keeps a charge's source, weapon, and turn. Mouse release only completes
a mouse charge; keyboard release only completes a keyboard charge. Full power
fires once. Focus loss, menus, weapon changes, disconnects, and turn expiry cancel
charging. Steering is independent of cursor motion; focus loss sends a neutral
input. The server applies a bounded input lease when packets stop arriving.

Fire/activation waits for a snapshot's command-sequence acknowledgement before
another activation. This prevents rapid clicks against an old snapshot from
skipping stages or spending another cartridge. Invalid commands remain rejected
by the host, without spending ammo. Remote control remains available while the
shot settles, including after the launching grub dies if its team still has a
living member. A rematch invalidates lobby rendering state so Ready correctly
re-enables Start.

Protocol 4 is required on both ends. Existing checkpoint formats remain readable;
legacy in-flight critters gain explicit stages during restore, and fire zones from
older saves keep burning as static zones.

## 0.5.0 blast physics and multi-step weapons

- **Blast impulse.** Explosions push along the line from the blast centre through
  each body, scaled by damage and distance, with extra lift. A blast underneath
  throws a grub upward; one overhead barely lifts it.
- **Tumbling.** Blasted grubs keep their momentum, rebound off walls, ceilings and
  floors, and slide to a stop. Their controls return when they settle. A blast flight
  ends without fall damage; an ordinary drop still hurts.
- **Loose objects.** Resting or rolling bombs, mines, barrels, crates and sentries are
  thrown by blasts and fall, bounce and settle. Close mines, crates and sentries are
  set off after a short, seeded delay; barrels take blast damage and rupture.
  Parachuting crates drift with the wind.
- **Fire.** Firebombs, barrels and the flamethrower spill flames (at most 60) that fall,
  drift with the wind, creep downhill and burn out after 3–5 s. A grub in fire takes 3
  damage every third of a second and hops, however many flames touch it.
- **Bounces.** Restitution is per weapon (bouncy fruit, heavy choir bomb, dull
  dynamite). Gentle contacts roll; bombs rest only on level ground.
- **Craters.** Blasts char a rim of soil (material 4) with no grass regrowing on the
  floor; drills, moles and dashes leave clean tunnels; the blowtorch scorches.
- **Multi-step controls.** Homing is lock → aim and charge; air support takes a target
  and an approach; girders take a target and a tilt; Fruit salad splits on command.
  Arrow keys (not A/D) steer approach and tilt, so the grub does not walk meanwhile.

## Munitions sweep (2026-10-13)

The munitions family adds dedicated original Cairo art and runtime rules in
`sprites/munitions.rb`, compiled by `build_ordnance_munitions.py`. Cached frame
paths and the existing 100-effect cap bound presentation work. The shared
`explode`, `shove` and `throw_body` damage/knockback formulas are unchanged.
No base damage or radius values changed; fragments inherit 30% horizontal launch
momentum, strikes widen from 120 to 152 pixels, and meteors arrive in waves.

Version-one checkpoints and protocol 4 remain supported. Optional projectile
fields (`sky_drop`, `choir_at`) use absent-field defaults; pending releases use
the existing saved delay. Motion samples append age/rest state while old samples
still render; restored legacy tracks recover fragment identity from the host's
projectile list. Fragment metadata selects distinct art. No fire acknowledgement or
charge-source gate was relaxed. One prior Choir test was updated intentionally:
a resting expired bomb now warns for 18 ticks before it disappears.

Baseline sheets are in the original checkout's `.cache/weapon-lab/`; this sweep's
new sheets are in `/tmp/munitions-lab/<weapon>-sheet.png`, with authoritative
per-frame logs at `/tmp/munitions-lab/<weapon>/log.json`. The committed
[munitions report](validation/munitions-sweep.json) records each weapon's defects,
changes and evidence. `python3 tools/check_munitions_lab.py /tmp/munitions-lab`
checks all 16 using isolated event IDs, accepted fire, ammo and real turn handover.
The revised scripts wait through handover, demonstrate a real homing target and
sticky body attachment, and return to Follow for the aerial pass. These are
Linux native input captures; audible Mac output and the owner's feel/balance
judgment require device playtesting.

The action-cadence checker exposed a measurement defect during this sweep: it
counted global velocity after visible positions stopped changing. A diagnostic
capture contained 154 such updates; the old selector reported 19.14ms mean /
33.76ms p95, while the rendering benchmark's existing visible-motion selector
measured the same capture at 16.30ms / 20.43ms. The action checker now shares that
selector, records completed updates, grants Xvfb focus for scripted controls,
and retains raw evidence in `.cache/native-action.raw.json`. Frame budgets are
unchanged; timing-analysis regressions still require real pending motion and
blocked GUI intervals to count as stalls.

## Automated evidence

- `test/weapons_munitions_test.rb`: all 16 munitions, exact fuses, impacts, staged
  releases, fragments, mine arming, fire cleanup, earthquake props, legacy saves
  and recovery during actions; every action finishes before emergency settling.
- `test/match_test.rb`: every catalog entry launches, spends the right ammo, and
  completes its action; deterministic six-team matches; validation and recovery.
- `test/weapon_physics_test.rb`: controlled impact geometry, first-tick hits,
  terrain normals, fuse timing, moving attachments, critical weapon stages,
  ownership, fuel/reeling, fragments, animated dash, and recovery within actions.
- `test/weapon_controls_test.rb`: actual input handler contracts, source-specific
  releases, target locks, cancellation, auto-repeat, pending actions, and selection;
  two-step homing by mouse, re-targeting, strike approach, girder tilt and splitting.
- `test/battlefield_physics_test.rb`: blast direction, tumbling and rebounds, fall
  damage rules, shoved bombs and props, staggered chains, flames, rolling, strike
  approach, tilted girders, homing burnout, charred rims and checkpoint recovery.
- `checks/controls.sspec`: native Rust keyboard/pointer/focus dispatch into the
  client and through a TLS host, with a repeatable obstacle course and observer.
- Existing presentation/cadence regressions preserve 0.2.4's smooth playback;
  native multiplayer and packaged rendering checks validate the integrated build.

Final run counts and platform limitations are in [VALIDATION.md](VALIDATION.md).
