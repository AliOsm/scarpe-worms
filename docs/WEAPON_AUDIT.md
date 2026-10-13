# Weapon, input, and presentation audit — 0.5.0

This is Burrow Brigade's implemented contract, first reviewed on 2026-10-09 and
updated for 0.5.0 on 2026-10-12 (see [0.5.0 changes](#050-blast-physics-and-multi-step-weapons)). Its 48
weapons have original names, art, and balance values. It is not a compatibility
implementation of a particular Worms release. [WEAPONS.md](WEAPONS.md) lists
all 48 entries, ammunition defaults, and their current in-game descriptions.

The critter contracts below were refreshed on 2026-10-13 for the 0.5.1 weapons
sweep, including Captain wool's manual detonation and dedicated in-world art.

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
Its third activation now detonates it in flight (the sweep replaces the previous
manual drop). Turning preserves a 260 px/s speed at 2.7 rad/s. Takeoff starts a
separate eight-second flight timer, then it falls for up to four seconds and can
still be detonated. Steering changes are sent on key transitions as well as the
12 Hz refresh; a lost input expires after 12 host ticks. Presentation interpolates
velocity for smooth heading changes without predicting collision or damage.

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
| Pocket rocket | Charged, wind-sensitive ballistic flight; terrain/body collision; swept muzzle and thin-wall collision. |
| Moon mortar | Instant fixed-power launch; five secondary fragments on impact. |
| Love letter | Two steps: lock a target, then aim and charge (mouse or Space); Backspace re-targets. Ballistic launch, then bounded homing at a cruise speed set by launch power; the motor burns out after 4.5 s and the rocket falls. |
| Tick-tock | Variable fuse; bounces on ground and grubs; surface-normal reflection; rolls down slopes steeper than about 35°; falls if support disappears; blasts knock it away. |
| Party popper, Fruit salad | Timed parent explosion; five/six fragments; boosted fragment damage; fragments settle before handover. Fruit salad splits early on a second Fire press while airborne. |
| Velcro bomb | Timed attachment to terrain or a grub; follows the attached grub; falls after support destruction. |
| Short fuse | Placement and four-second countdown; full retreat window. |
| Big trouble | Charged bouncing explosive with adjustable fuse and larger radius. |
| Choir bomb | Fixed five-second fuse; waits for rest, bounded by a twelve-second safety lifetime. |
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
| Special delivery, Rain check, Spicy forecast | ← → chooses the bombers' approach; five objects are released upwind so they land in a line across the target; normal blasts, armed mines, or spreading flames; cavern restrictions exposed before equipping. |
| Bad astronomy | Random six-meteor shower, activated without a meaningless target selection; cavern restriction. |
| Rumble button | Bounded seeded impulses; respects frozen bodies. |
| Woolly menace | Eight-second runner; hops small obstacles and ledges, turns away from tall walls after twelve blocked ticks; Space/click detonates. Upright mirrored walk/hop/fall art and wool blast accents. |
| Captain wool | Walking → upward launch → eight-second directional flight → falling; Space/click detonates in flight or while falling. Immediate A/D and arrow steering intents, leased by the host; cape follows interpolated heading and stays upright when flying left; wool/sparkle trail. Late takeoff extends settlement through the remaining flight. |
| Tunnel buddy | Walking → dive → digging → detonation; dirt follows the visible tunnel, exit detection probes ahead of carved material, and grub contact wins over entering terrain. Space/click also detonates while diving or digging. |
| Stink express | Walking → four seconds of activated spray → final gas and small blast; late activation retains the full spray. Animated upright runner, visible green puffs, and passive spray status in the HUD. |
| Cattle call | Three releases 24 ticks apart; pending cows stay invisible and inert. Swept body contact or a wall detonates each cow; eight-second fallback per runner. Mirrored walking art and a low cartoon call reuse the existing voiced cue. |
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
| Stink bomb | Timed bouncing gas canister, no premature body-impact explosion. |
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

## Automated evidence

- `test/match_test.rb`: every catalog entry launches, spends the right ammo, and
  completes its action; deterministic six-team matches; validation and recovery.
- `test/weapons_critters_test.rb`: obstacle/ledge running, remote stages, flight
  timeout and late takeoff, instant steering intents, poison spray, staggered
  cows, sprite orientation, and deterministic/legacy checkpoint continuation.
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
