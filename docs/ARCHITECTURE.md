# Architecture and protocol

## Process model

The native Scarpe window paints images, text, geometry, and controls through its
Rust renderer. Ruby owns the presentation, with a 60 Hz animation timer and
150 ms of buffered, tick-based motion playback. Snapshots include 18 ticks of
worm/hazard positions and projectile tracks with explicit birth/end samples.
This preserves short flights across packet coalescing. Events and audio follow
the same timeline; late packets catch up gradually instead of skipping motion.
Terrain decompression, checksum validation and rasterization run in a separate
Ruby process; the GUI forwards compressed packets without expanding the mask.
The worker caches 384-world-pixel tiles. Only changed tiles and their bevel neighbors are rerendered. Initial
lobby previews are asynchronous too.
Sprite images are retained and reused. Effects and terrain image caches are
bounded. OpenAL mixes twelve sound voices and a separate music source in process.

In-app hosts also run in a separate Ruby process. AI, compression, checkpoints,
and six-player broadcasting cannot compete for the GUI VM lock. Closing the
parent pipe saves and stops its host. The Mac launcher supplies the packaged Ruby
executable explicitly to both subprocesses; they inherit the parent's load paths.
A dedicated connection thread owns socket I/O and reconnect backoff. It coalesces
snapshots, retaining the most recent terrain payload until the UI consumes it.
The UI never blocks on a network receive. Resizing reuses the terrain worker and
its rendered tiles, camera and playback timeline while rebuilding UI nodes, so
it neither blanks the landscape nor replays old shots/sounds. Crowded battles show compact health labels, with
full names for the active or hovered grub.

The server reactor has one owner for socket I/O, room mutation, simulation, and
checkpoint writes. Simulation runs at 30 fixed steps per second; snapshots are
normally sent at 10 Hz during play. A bounded catch-up avoids unlimited lag
accumulation. Bot ballistic planning is limited to four traces per tick and is
part of the checkpoint, so no full search blocks a single turn update.

## Game state

`Config` validates every known option. `Catalog` defines all 48 weapons and
presets. `Terrain` carries explicit dimensions with a two-pixel material grid.
Auto sizes are 2880×1280 (two teams), 3840×1440 (three/four), and 4800×1600
(five/six); high grub counts also increase size. Rules can override the size.
Generation composes seeded, uneven landforms, overhangs, open archways, caves,
upper shelves and destructible masonry. Terrain packets/checkpoints include
width and height; pre-0.2 checkpoints fall back to 1440×720. Generation and
simulation randomness have explicit deterministic seeds/state. Collision,
cratering, landing, bridge construction, and bot traces use the same mask.

`Match`, `Physics`, and `Weapons` own gameplay. Clients submit intent, never
damage, player coordinates, ammo, or turn transitions. The server checks owner,
phase, numeric ranges, tool geometry, and inventory before spending ammunition.
Invalid movement does not partially update held controls. Inputs expire after
400 ms without refresh. Projectiles, hazards, poison, knockback, fall damage,
flooding, supplies, and winner detection are authoritative.

Match phases are aiming → retreat → settling → next turn, or finished. Utilities
can retain aiming; Double tap has two shots in one cartridge. Every action has
a server implementation. Match checkpoints contain all simulation fields,
terrain, inventories, in-flight objects, bot planning, and the PRNG state.

## Wire format (protocol 3)

Messages are UTF-8 JSON objects, one per newline. Client frames are limited to
24 KiB; server frames to 512 KiB; nesting and numeric values are bounded. A
connection starts with:

```json
{"type":"hello","version":3,"name":"River crew","token":null}
```

`welcome` returns `id`, a 256-bit session `token`, and the last accepted `seq`.
The server persists only SHA-256 token hashes. Clients store their tokens in a
private local preferences file. Subsequent mutating commands need increasing
integer `seq` values; duplicate sequences are ignored. Protocol 3 rejects older clients before using staged controls and directional steering. A reconnect sends the
same token, resumes its sequence, and receives a complete state/terrain packet.
Queued old commands are dropped on reconnect rather than fired unexpectedly.

Room commands: `list`, `create`, `join`, `leave`, `sync`, `ready`, `configure`,
`add_bot`, `kick`, `start`, `rematch`, `chat`, `surrender`. Game commands:
`move`, `jump`, `fire`, `steer`, `activate`, `detonate` (legacy alias for activate). `ping`/`pong` maintain liveness and RTT.
`ack`, `error`, and `fatal` distinguish success, rejected actions, and connection
failure. Snapshots contain the last processed command sequence in `ack`, lobby metadata,
and optional match data. The client holds a single pending fire/activation until
a snapshot acknowledges it, preventing duplicate clicks from spending ammo or
skipping a weapon stage. `steer` carries direction/lift, with a 12-tick input lease;
focus loss explicitly sends zero steering. Unchanged
terrain is omitted; changed terrain carries revision, checksum, and a bounded
zlib/base64 material mask.

TLS 1.2+ is required on public listeners. Clients verify the certificate through
the OS/runtime CA store or an explicit fingerprint pin before hello. The reactor
bounds per-peer buffers, commands, handshakes, idle time, and connection counts.
Slow peers cannot grow an unlimited output queue. These controls have focused
tests; there has not been an independent security audit or public load test.

## Source map

| Area | Location |
| --- | --- |
| Domain, generation, physics, weapons, bots | `lib/burrow/` |
| Lobby, session, TLS reactor, certificates | `lib/burrow/server/` |
| Native UI, scene, connection, audio, preferences | `lib/burrow/client/` |
| Core/network tests | `test/` |
| Native UI journeys | `checks/` |
| Standalone upstream patches | `patches/scarpe/` |
| Original asset generators and package tooling | `tools/` |
| Docker, systemd, Mac launch/runtime metadata | `packaging/`, `Dockerfile`, `compose.yaml` |

The prototype repositories informed the native boot, isolated dependency layout,
test harness, and packaging approach. No prototype game code or data is shared
at runtime. `setup.sh` retrieves upstream Scarpe by commit and applies only the
exported patch series; `verify_scarpe.py` checks every changed file against it.
Setup recognizes complete prefixes of that series and refuses unrelated edits.
Window deactivation arrives before synthetic key releases, allowing the client
to cancel charged shots. Room snapshots carry a persisted match identity so a
coalesced rematch still replaces the old scene, terrain, and animation state.
