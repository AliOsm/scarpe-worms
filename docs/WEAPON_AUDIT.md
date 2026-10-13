# Weapon, input, and presentation audit — 0.5.1

This is Burrow Brigade's implemented contract, first reviewed on 2026-10-09 and
updated for 0.5.0 on 2026-10-12 (see [0.5.0 changes](#050-blast-physics-and-multi-step-weapons))
and the guns, close-up, hazards, digging tools and supplies sweep on 2026-10-13. Its 48
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
| Pocket rocket | Charged, wind-sensitive ballistic flight; terrain/body collision; swept muzzle and thin-wall collision. |
| Moon mortar | Instant fixed-power launch; five secondary fragments on impact. |
| Love letter | Two steps: lock a target, then aim and charge (mouse or Space); Backspace re-targets. Ballistic launch, then bounded homing at a cruise speed set by launch power; the motor burns out after 4.5 s and the rocket falls. |
| Tick-tock | Variable fuse; bounces on ground and grubs; surface-normal reflection; rolls down slopes steeper than about 35°; falls if support disappears; blasts knock it away. |
| Party popper, Fruit salad | Timed parent explosion; five/six fragments; boosted fragment damage; fragments settle before handover. Fruit salad splits early on a second Fire press while airborne. |
| Velcro bomb | Timed attachment to terrain or a grub; follows the attached grub; falls after support destruction. |
| Short fuse | Placement and four-second countdown; full retreat window. |
| Big trouble | Charged bouncing explosive with adjustable fuse and larger radius. |
| Choir bomb | Fixed five-second fuse; waits for rest, bounded by a twelve-second safety lifetime. |
| Double tap | Five spread pellets per press, totaling 26 damage at close range; two separately aimed presses per cartridge, including the last cartridge. Pellets test the same cover before cutting holes. Distinct muzzle flash and pellet tracers; HUD identifies shot one/two; switching stays locked between shots. |
| Long goodbye | One bright tracer and 42-damage hit; terrain and props block the ray, including a one-cell wall beside the muzzle. Impact sparks and terrain chips mark the hit. |
| Peashooter | Eight timed 9-damage rounds with seeded spread, small recoil per hit and rapid flashes/tracers; the saved burst queue survives recovery. A dead shooter cannot finish the burst. |
| Sunbeam | Thick glowing beam cuts through terrain and props, dealing 38 damage once per body along its path; bounded impact effects show entry points. |
| Hot breath | Eighteen 3-damage pulses over about 1.2 seconds, reaching 160 world pixels; the visible stream stops at cover and spills persistent fire. Gentle push avoids launching every target out of the stream. The global 60-flame cap applies; interrupted streams restore deterministically. |
| Uppercrust | Fiery fist pose; the attacker leaps and launches a nearby victim upward for 35 damage. Its leap does not cause self-inflicted fall damage; cover and frozen bodies are respected. |
| Dragon dash | Fiery rush over twelve ticks; carves a body-clear tunnel, holds its height, and hits each nearby unobstructed body once for 42 damage. Space/click can stop the rush; the HUD names the dash. |
| Little nudge | Visible poke; zero damage with a small forward shove and lift. Terrain obstruction and frozen bodies are respected. |
| Home run | Visible swing arc; 32 damage and a large launch along the exact aim vector, including downward aim. Cover blocks it; frozen bodies stay still. |
| Half measure | Visible chop; removes half current health rounded upward, then applies damage modifiers including Extra spicy. It has a small recoil instead of an uppercut launch. |
| Special delivery, Rain check, Spicy forecast | ← → chooses the bombers' approach; five objects are released upwind so they land in a line across the target; normal blasts, armed mines, or spreading flames; cavern restrictions exposed before equipping. |
| Bad astronomy | Random six-meteor shower, activated without a meaningless target selection; cavern restriction. |
| Rumble button | Bounded seeded impulses; respects frozen bodies. |
| Woolly menace | Hops at obstacles/ledges; manual or timed detonation. |
| Captain wool | Walking → upward launch → directional flight → falling; collision and lifetime termination. |
| Tunnel buddy | Walking → dive → digging → detonation; tunnel exit detection probes ahead of carved material. |
| Stink express | Walking → activated spray → final gas and small blast. |
| Cattle call | Three timed releases; pending cows are invisible and do not collide before release. |
| Mind your step | Validated placement ahead; one-second arming delay, visibly distinct safe/armed states, blinking light and a 0.6-second proximity fuse. Reacts within 36 pixels with clear sight. Persistent mine; blasts throw it and close blasts arm a short fuse. |
| Sentry sprout | Dedicated sentry sprite tracks targets; five visible shots within 420 pixels and clear sight, enemy selection and an empty-ammo pose. Placement is validated ahead of the grub. |
| Red barrel | Validated placement ahead with visible feedback; blasts throw and dent the drum. Gun hits can rupture it; the cracked barrel explodes after a short delay and spills flames. |
| Grapple line | Validated overhead attachment; swing/reel/release; destroyed anchors detach; no extra ammo for releasing. |
| Personal cloud | Directional thrust; fuel conservation; mutually exclusive with rope; graceful fuel exhaustion. |
| Soft landing | Slows descent; suppresses fall damage; directional drift. |
| Here to there | Clear landing and occupied-body validation before spending ammo; ends turn. |
| Bridge builder | ← → tilts the beam in 22.5° steps up to vertical; tilted preview; collision and bounds validation along the beam before spending ammo. |
| Down we go | Controlled downward drilling for at most two seconds, with a drilling pose and debris. Space/click stops cutting immediately; no fall damage while drilling. Uses the turn; saved drilling resumes deterministically. |
| Side hustle | Forward cutting with a flame jet, sparks and a tool pose; Up/Down steers both slopes with an expiring input lease. Space/click stops cutting immediately. Uses the turn; saved damage history prevents extra hits after recovery. |
| First aid | Restores up to 35 health, clears poison, and shows a healing effect and health number. Rejects wasted use without spending ammo; uses the turn. |
| Bubble wrap | Animated shield bubble; halves incoming damage until the team's next turn. Keeps the turn; the active HUD directs the player to choose an attack. |
| Ice break | Frost shell on every living team member; prevents damage and weapon knockback until the team's next turn. Uses the turn. |
| Stink bomb | Timed bouncing gas canister, no premature body-impact explosion. |
| Extra spicy | Animated glow and ×2 cue; doubles attack damage, including Half measure, for the turn. Keeps the turn; the HUD says to choose an attack next. |
| Moon boots | Reduced gravity for jumps and shots during the current turn, with a visible float cue. Keeps the turn; the HUD explains jump and backflip controls. |
| Weather vane | Bounded reversed/strengthened wind, including a visible gust from calm conditions; animated wind cue and authoritative wind gauge. Keeps the turn. |
| Pass the turn | Explicit Pass action; waits for a safe settled handover and remains unavailable between shotgun shots. |

These contracts cover the implemented arsenal, not a claim that its tuning,
weapon roster, or every advanced move is identical to Worms.

The close-weapon sweep also tightens the shared line-of-sight helper to sample
every two world pixels, matching the terrain cell size. This prevents narrow
walls from being skipped by melee, sentries and other line-of-sight callers.

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
- `test/weapon_physics_test.rb`: controlled impact geometry, first-tick hits,
  terrain normals, fuse timing, moving attachments, critical weapon stages,
  ownership, fuel/reeling, fragments, animated dash, and recovery within actions.
- `test/weapon_controls_test.rb`: actual input handler contracts, source-specific
  releases, target locks, cancellation, auto-repeat, pending actions, and selection;
  two-step homing by mouse, re-targeting, strike approach, girder tilt and splitting.
- `test/weapons_close_test.rb`: pellet/cover geometry, gun bursts and streams,
  weapon-specific melee launches, digging speed and stop/steering contracts,
  checkpoint recovery, and native-input-handler keyboard/mouse sequences for
  Double tap, tools and supplies. The weapon lab captures the corresponding real
  native keyboard/pointer journeys on its fixed course; healing begins injured
  and poisoned, while short-range weapons begin within reach.
- `test/battlefield_physics_test.rb`: blast direction, tumbling and rebounds, fall
  damage rules, shoved bombs and props, staggered chains, flames, rolling, strike
  approach, tilted girders, homing burnout, charred rims and checkpoint recovery.
- `checks/controls.sspec`: native Rust keyboard/pointer/focus dispatch into the
  client and through a TLS host, with a repeatable obstacle course and observer.
- Existing presentation/cadence regressions preserve 0.2.4's smooth playback;
  native multiplayer and packaged rendering checks validate the integrated build.

Final run counts and platform limitations are in [VALIDATION.md](VALIDATION.md).
