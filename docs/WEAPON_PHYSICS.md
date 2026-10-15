# Weapon physics · 0.5.13

This tuning was developed through Apple silicon previews and is included in
0.5.13. It is original to Burrow Brigade; the videos inform behavior rather
than supplying exact physical constants or game assets.

## Reference study

The supplied [Big Boom short](https://www.youtube.com/shorts/KQJyX3acyPU)
shows a bazooka impact at about 2.4 seconds throwing a worm away from the crater.
The worm lands near mines and a barrel; their delayed explosions around 6–7
seconds launch it again and leave fire in the new crater. The sequence separates
the initial impact, free flight, landing, chain reactions and settling. Existing
mine/barrel delays and spreading fire already cover that chain in this game.
The correction here removes the lost motion at floor and wall rebounds.

The [Basic Training video](https://www.youtube.com/watch?v=EyrKBNpAMiI)
demonstrates the following sequences, checked visually with timestamped frames
and alongside its commentary:

- **0:54–1:08, 2:04–2:29, 3:32–4:03:** charged grenade trajectories and
  selectable fuse times matter for targets at different heights and behind
  girders. Airbursts should occur at the end of the selected flight time.
- **1:27–1:44:** bazookas curve with wind and explode on contact. Existing
  wind selectivity is retained: thrown bombs and mortar do not drift.
- **3:12–3:32**, especially **3:27–3:29:** a near-horizontal bazooka shot
  skims the water and reaches a low target beyond the gap. Ordinary shots
  previously disappeared at their first water crossing in Burrow Brigade.
- **1:44–2:04, 2:29–3:12:** rope swinging, momentum on release, airborne
  uppercuts and suspended weapon use provide surrounding movement context.
  This change does not add rope wrapping or another weapon-control scheme.

The short was inspected in half-second frame sequences, with closer visual
review of the blast/chain reaction. The training video was inspected through
the browser, including quarter-second samples around the water skips. Its
automatic captions supplement the visible actions. Reference media is not
redistributed with the repository or app.

## Implemented behavior

- **Charge:** base launch speed is `670 × power` pixels/second, multiplied by
  the weapon's launch scale. The former
  `130 + 540 × power` made a 5% tap launch at 157 px/s; it now launches at
  33.5 px/s for the rocket and grenade. Their full charge remains 670 px/s;
  other thrown weapons use their profile's scale. Mortar stays fixed at 580 px/s.
  The host, bot and aim dots share the speed function. Short-lob dots stay near
  the muzzle and account for the host's discrete gravity/wind integration.
- **Contacts:** projectile sweeps remain at most 1.5 pixels long. Contact is
  refined within the sweep, then reflected velocity spends the remaining tick.
  At most eight contacts per tick bound crevice work. Gentle ground contacts
  roll; a bomb only sleeps on sufficiently level support. Destroying support
  still wakes it. Weapon-specific rebound strength is retained.
- **Fuses:** a normal fuse includes its final movement tick before detonation.
  Manual detonation remains immediate; sticky bombs follow their target on the
  terminal tick; Choir bomb still waits for rest and its warning chord.
- **Water:** the rocket, mortar and bouncing thrown bombs skip when horizontal
  speed is at least 180 px/s and downward speed is at most 45% of it. A skip
  retains 85% of horizontal speed and reverses 65% of downward speed. Each
  contact loses energy; the original fuse/lifetime still bounds the action.
  Steep/slow shots, fragments, sticky charges and dynamite sink. Homing retains
  underwater flight. Splash events mark skims without a premature explosion.
- **Blast follow-through:** a tumbling grub uses its new velocity during the
  remaining movement substeps after hitting a wall, floor or ceiling. The
  second pass adds weapon-specific impulse, a visible landing rebound and a
  delayed chain window so the short's crater → flight → landing sequence reads.

These thresholds are design choices, not measurements extracted from the videos.
The simulation remains host-owned at 30 Hz. Presentation timing, frame deadlines
and terrain workers retain their existing architecture.

## Second video pass

The first preview corrected discrete contacts but left the signature video
sequence too subtle in play. This preview makes the reference motion explicit:

- launcher and hand-bomb blasts use weapon-specific pressure multipliers and a
  stronger lift impulse, so a grub rises, travels away from the crater, rebounds
  on landing and slides before the turn settles;
- each launched victim reports authoritative impulse metadata, letting the
  client follow the airborne grub through the landing and delayed mine/barrel
  chain without predicting a local path;
- landing and shell contacts produce a small contact cue, while the tumbling
  grub rotates in presentation during its host-owned flight;
- water-skipping events carry outgoing velocity. The client draws a wake in that
  direction and the rocket keeps its smoke trail, making a shallow skim visibly
  different from a shot that sinks;
- blast-propelled mines, crates and barrels wait 14–20 ticks before a triggered
  chain detonation. Direct gun ruptures keep their existing short fuse.

At this stage, critter blasts retained their previous impulse scale because
those weapons already had long remote flight budgets. The full-arsenal pass
below subsequently gave critters their own blast profiles.

## Full-arsenal retune

The 0.5.13 pass moves the physical constants into one immutable profile for
each of the 48 catalog entries. This makes the visible response consistent in
Quick Battle, bot traces, checkpoints and the aim preview instead of changing
only the three weapons in the reference sequence.

- **Launchers and explosives** use individual launch scale, gravity, wind,
  restitution, water-entry and blast-lift values. Cluster and banana fragments
  inherit their parent's spread and lift, while heavy bombs settle with lower
  rebound and Stink bomb remains a low-pressure gas release.
- **Direct weapons** have distinct body impulses: the rifle is a precise shove,
  the minigun is a light repeated push, the laser sits between them, and the
  flamethrower keeps a soft stream push. Shotgun keeps its cartridge contract
  and one recoil impulse for a five-pellet hit.
- **Close attacks** read their launch vectors from the profile. Uppercrust,
  Little nudge, Home run and Half measure therefore keep separate lift and
  horizontal responses; Dragon dash uses the same profile for its rush and
  victim launch.
- **Sky weapons** share the drop solver but have separate bomber speed, drop
  speed, spacing, meteor drift and quake impulses. The gravity multiplier used
  to place a drop is the same multiplier used while it falls.
- **Critters** use profile speeds for release, walking, ledge hops, Captain
  wool's flight, Tunnel buddy's dive and tunnel motion, and their final blast.
- **Props and mobility** use profile mass and gravity. Mines, barrels and
  sentries therefore move differently under a blast; rope hook/reel/pump,
  jetpack thrust, parachute fall and drill/blowtorch/dash travel are also
  authoritative profile values.

The profile table is checked against `Catalog::WEAPONS` in regression tests, so
adding a selectable weapon without a physical contract fails the test suite.
Some profiles, including rope, jetpack and non-projectile utilities, preserve
their established constants or rules; coverage is not a claim that every item
has changed motion.

## Verification and compatibility

`test/video_weapon_physics_test.rb` covers short-lob range, the launcher arc and
landing carry-through, terminal airburst
position, floor/wall/corner contacts, blast rebounds, both skim directions,
energy loss, sinking exceptions, exact fuses, far-bank impact, bot targeting and
checkpoint recovery on every subsequent tick. Existing weapon tests cover wind,
slope rolling, thin walls, sticky attachment, heavy-bomb rebounds, fragments,
homing, melee, chain reactions and turn completion.

`checks/physics.sspec` drives actual native keyboard/pointer input through TLS:
short throw, timed wall rebound and a full-charge water skip to the far bank.
It also runs on Apple silicon before packaging. The packaged prediction and
physics journeys, menu/gameplay smoke, audio checks and archive verification
pass; see the [release validation](validation/release-0.5.13.json) for the tagged
packages and the remaining informational rendering outliers. The
[preview record](validation/weapon-physics-0.5.13.json) retains its earlier
build evidence.

Protocol 4 and version-one saves remain supported. Restored shots retain their
saved velocity and remaining fuse, then follow the new host physics. A snapshot
adds optional `physics_revision: 3`; the new client uses the legacy power curve
when that field is absent. Upgrade clients on a new host for accurate aim dots.
An old online host still owns its original rules, even when joined from this app.

## Mac playtest

Use **Quick battle**, or create a match hosted by 0.5.13.

1. Compare a quick Space tap with a half and full charge of **Tick-tock**.
   Try one- and three-second fuses near a wall and on a slope.
2. Fire **Pocket rocket** almost horizontally across a water gap with a strong
   charge. Compare it with a steep shot: the shallow shot can skip; the steep
   one sinks. Wind still bends the flight.
3. Blast a grub near a wall or crater and watch its rebound and landing. Try a
   nearby mine/barrel chain and confirm the next turn waits for the action.
4. Check **Fruit salad**, **Choir bomb**, and **Velcro bomb** for their different
   rebound, rest/warning and attachment behavior. Resume an unfinished match.

Check feel, balance, sound and smoothness on a physical Mac after installing.
The Mac app is ad-hoc signed and unnotarized like earlier downloads.
