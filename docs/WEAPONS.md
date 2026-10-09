# Arsenal and rules

All 48 entries have authoritative server behavior and native arsenal controls.
Ammo below is the full preset; −1 means unlimited. Hosts can override every entry.

| Weapon | Category | Ammo | Behavior |
| --- | --- | ---: | --- |
| Pocket rocket | Launchers | -1 | Wind bends its flight. Point, charge, and let it fly. |
| Moon mortar | Launchers | 3 | A fixed-power shell bursts on impact into five fragments. |
| Love letter | Launchers | 2 | Click a destination. The rocket steers toward it after launch. |
| Tick-tock | Explosives | -1 | Bounces until the fuse expires. Set a 1–5 second fuse. |
| Party popper | Explosives | 3 | A bouncing shell that scatters five explosive fragments. |
| Velcro bomb | Explosives | 2 | Sticks to the first surface it touches. Mind the fuse. |
| Short fuse | Explosives | 2 | Drop it at your feet, then use your retreat time. |
| Big trouble | Explosives | 1 | A very large bouncing bomb. Your friends may object. |
| Fruit salad | Explosives | 1 | One fruit becomes six. Each piece packs a punch. |
| Choir bomb | Explosives | 1 | A weighty bomb with a five-second fuse and a grand finale. |
| Double tap | Direct | -1 | Two separate shots. Re-aim before the second. |
| Long goodbye | Direct | 3 | A precise single shot. Terrain blocks the bullet. |
| Peashooter | Direct | 2 | Eight rounds spread around your aim, chewing small holes. |
| Sunbeam | Direct | 2 | A straight beam cuts through terrain and enemies. |
| Hot breath | Direct | 2 | A short cone of fire leaves burning ground behind. |
| Uppercrust | Close-up | -1 | A close-range uppercut that launches an opponent. |
| Dragon dash | Close-up | 2 | Burst forward through a short tunnel, striking everyone ahead. |
| Little nudge | Close-up | -1 | No damage. Plenty of shove. Best beside the water. |
| Home run | Close-up | 2 | Aim the angle of an enormous knockback. |
| Half measure | Close-up | 2 | Halves a nearby opponent's current health. |
| Special delivery | Sky | 2 | Click a target for five falling bombs. Unavailable in caverns. |
| Rain check | Sky | 1 | Drops five persistent proximity mines from above. |
| Spicy forecast | Sky | 1 | A line of firebombs spreads persistent fire. |
| Bad astronomy | Sky | 1 | A scattered shower of six destructive meteors. |
| Rumble button | Sky | 1 | Shakes everyone loose. Watch the edges. |
| Woolly menace | Critters | 2 | A hopping runner. Press Fire again to detonate early. |
| Captain wool | Critters | 1 | Release, then Fire to fly. Left / Right steers; Fire again drops it. |
| Tunnel buddy | Critters | 2 | Release, Fire to dive and dig, then Fire again to detonate. |
| Stink express | Critters | 2 | Release, then Fire to spray poison as it runs. |
| Cattle call | Critters | 1 | Three walking troublemakers, released one after another. |
| Mind your step | Hazards | 3 | Arms after one second, then reacts to nearby grubs. |
| Sentry sprout | Hazards | 1 | A five-shot sentry fires at enemies within sight. |
| Red barrel | Hazards | 2 | An explosive obstacle. Blasts can start a chain reaction. |
| Grapple line | Mobility | 4 | Click ground above to attach. Left / Right swings; Up / Down reels; Fire releases. |
| Personal cloud | Mobility | 2 | Four seconds of thrust. Arrows fly; Fire stops. Fuel only burns while thrusting. |
| Soft landing | Mobility | 2 | Slows this turn's falls and prevents fall damage. |
| Here to there | Mobility | 2 | Click clear ground to relocate. Uses the turn. |
| Bridge builder | Tools | 3 | Click open space to build a 140-pixel bridge. Uses the turn. |
| Down we go | Tools | 2 | Bore downward for two seconds. Fire again stops early. |
| Side hustle | Tools | 2 | Dig forward; Up / Down changes slope. Fire again stops early. |
| First aid | Supplies | 2 | Restore 35 health and clear poison. Uses the turn. |
| Bubble wrap | Supplies | 1 | Halve incoming damage until your next turn. |
| Ice break | Supplies | 1 | Protect your whole team until its next turn. Uses the turn. |
| Stink bomb | Explosives | 2 | A bouncing canister leaves a lingering poison cloud. |
| Extra spicy | Supplies | 1 | Double the damage of the attack you make this turn. |
| Moon boots | Supplies | 1 | Reduce gravity for the rest of this turn. |
| Weather vane | Supplies | 1 | Reverse and double the wind, up to storm strength, for this turn. |
| Pass the turn | Supplies | -1 | Let the next team take its turn. |

## Controls by stage

- Thrown weapons: hold Space or left mouse, release to fire. Guns, mortar, tools,
  and critters fire on the press. Auto-repeat never counts as another press.
- Homing: click to lock a destination, move the cursor or use Up/Down to aim the
  launch, then charge with Space. Moving the cursor does not move the lock.
- Captain wool: tap to release, tap to launch upward, Left/Right turns in flight,
  tap again to drop. Flight ends on collision, water, or timeout.
- Tunnel buddy: tap to release, tap to jump and dive, tap to detonate while diving
  or digging. It also explodes after breaking out of the ground.
- Woolly menace: tap to release, tap to detonate. Stink express: tap to release,
  tap to spray poison along its path. Cattle call deploys three critters at intervals.
- Grapple: click an overhead surface to attach, Left/Right swings, Up/Down reels,
  Space or Jump detaches. The anchor releases if destroyed.
- Jetpack: arrows apply thrust; released keys conserve fuel. Space deploys a
  parachute and stops the pack. Fuel exhaustion also provides a soft landing.
- Digging: Fire stops early. Up/Down changes the blowtorch slope.
- Double tap: each press fires one shot. Re-aim for the second; it belongs to the
  same cartridge, including the last cartridge. Finish both before switching.

The HUD shows the current stage, next action, fuse, rope length, or remaining
thrust. Irrelevant controls are disabled. Focus loss, menus, weapon changes, and
turn expiry cancel charging. A mouse release cannot release a keyboard charge.
A pending action waits for the host's next authoritative snapshot before a second
activation can be sent. The server validates ownership, parameters, phase, and ammo.

## Match options

Rules are locked during a match. Changing a lobby rule clears all human ready checks.
Import/export preserves the seed and every ammo override. All values are validated.

| Option | Default | Supported values |
| --- | --- | --- |
| seed | little-havoc | 1–40 printable characters |
| biome | meadow | meadow, desert, glacier, volcano |
| terrain | islands | islands, archipelago, cavern |
| scheme | full | full, classic, sandbox |
| worms | 3 | 1..6 |
| health | 100 | 50..200 |
| turn seconds | 45 | 15..90 |
| retreat seconds | 4 | 0..10 |
| round limit | 12 | 3..30 |
| gravity | 1.0 | 0.4..1.6 |
| wind | 1.0 | 0.0..2.0 |
| damage | 1.0 | 0.5..2.0 |
| fall damage | true | true, false |
| friendly fire | true | true, false |
| crates | true | true, false |
| mines | 4 | 0..12 |
| barrels | 3 | 0..12 |
| water rise | 12 | 0..40 |

Maps use hills and underground hollows (islands), separated land masses (archipelago),
or an enclosed ceiling (cavern). Every biome is cosmetic: collision uses the same
material mask. Caverns disable air support. Craters and bridges alter that mask.

After the configured round limit, surviving grubs drop to one health and water
rises each turn. Setting the water rise to zero permits longer standoffs. A grub
entering water is eliminated regardless of health. Poison does not reduce health
below one; protection effects expire on the team's next turn.

Up/Down adjusts aim, reels the rope, or controls the active tool; Up supplies
lift with the jetpack. The arsenal describes
targeted tools and whether they use a turn. Hover a grub in a crowded battle
to reveal its name; the active grub always shows its name.
