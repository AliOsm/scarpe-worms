# Agent handoff

## Start here

Read [README.md](README.md), [docs/STATUS.md](docs/STATUS.md), and
[CONTRIBUTING.md](CONTRIBUTING.md). Use [the documentation index](docs/README.md)
for the area you are changing. Do not infer release readiness from old reports.

The game is **Burrow Brigade**, an original six-player desktop artillery game.
The repository is `AliOsm/scarpe-worms`. The first package targets Apple silicon
and macOS 13+; source development and automated checks also run on Linux.

## Source map

| Area | Start with |
| --- | --- |
| Rules, maps, physics, weapons, bots | `lib/burrow/{config,terrain,match,physics,weapons,catalog,bot}.rb` |
| TLS host, room ownership, persistence | `lib/burrow/server/` |
| Native UI and input | `lib/burrow/client/{app,match_ui,dialogs}.rb` |
| Rendering and terrain | `lib/burrow/client/{scene,timeline,terrain_worker,terrain_painter}.rb` |
| Regressions / native input journeys | `test/` / `checks/` |
| Asset generators / packaging | `tools/` / `packaging/` |
| Framework changes | `SCARPE_REVISION`, `patches/scarpe/` |

## Invariants to preserve

- The host owns simulation, ammo, damage, turns, and collision. Clients send intent.
- Simulation is 30 Hz, snapshots normally 10 Hz, presentation targets 60 Hz.
  Preserve deterministic randomness and checkpoint recovery inside weapon actions.
- Host work and terrain rasterization stay out of the GUI Ruby process. Socket
  reads stay off the UI thread; caches and queues must remain bounded.
- **Preserve the 0.2.4 smoothness fix:** precise deadline waits, elapsed-time playback,
  short-flight presentation, and recovery when history is pruned. Read
  [the timing investigation](docs/history/PERFORMANCE.md) before changing scheduling.
- Clear held controls on focus loss, menu/weapon changes, and disconnection.
  Fire/activation waits for the snapshot sequence acknowledgement; charge releases
  must match their keyboard or mouse source.
- Protocol 3 hosts reject older clients. Coordinate protocol changes on both ends;
  retain supported save compatibility or document an explicit migration.
- Visible terrain must agree with collision. Keep sprite dimensions, anchors,
  and generator/runtime contracts consistent.

## Workflow

Run `./setup.sh` on a fresh checkout. Choose checks from
[CONTRIBUTING.md](CONTRIBUTING.md); run native performance journeys serially.
For physics/control fixes, add a behavioral regression and exercise the relevant
native input path. Documentation-only edits do not need gameplay tests.

Keep Scarpe changes as separate numbered patches and verify with
`python3 tools/verify_scarpe.py`. Setup rejects unexported changes; do not discard
another contributor's dependency edits to make it pass.

Dependencies, app bundles, raw diagnostics, credentials, and player state are
ignored. Keep concise, versioned validation summaries and selected screenshots.
Reports in `docs/validation/` describe the build and machine actually measured.

Linux cross-builds do not execute Darwin binaries. Do not claim native Mac tests,
audible Mac sound, notarization, or sales readiness without new evidence.
Update `docs/STATUS.md` with completed work, gaps, and next checks at handoff.
Use licensed/original assets and preserve third-party notices.
