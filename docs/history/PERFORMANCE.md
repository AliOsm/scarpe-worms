# Mac performance and startup history

This history explains regressions that future changes must not reintroduce.
The owner confirmed **0.2.4 was very smooth on an M3 Pro**. Version 0.3.0 preserves
those fixes. It has separate [Linux validation](../VALIDATION.md).

## What changed

| Version | Problem | Correction |
| --- | --- | --- |
| 0.2.1 | Expensive terrain resizes and uneven frames on large/Retina surfaces | SIMD resizing, alpha-span caching, bounded software rendering, even frame pacing |
| 0.2.2 | Finder locale caused `C2 on US-ASCII` host startup errors | Explicit UTF-8 for launcher, workers, JSON pipes, and saved data |
| 0.2.3 | Command-Q omitted native reports | Flush stats from the AppKit exit callback; add bounded Ruby/game timing logs |
| 0.2.3 | Candidate background throttling | Scoped NSProcessInfo activities; helpful instrumentation, insufficient to fix stutter |
| 0.2.4 | UI waits overshot by about 100 ms; playback accumulated seconds of lag | Precise kernel timers plus elapsed-time and history-recovery fixes |

## Evidence behind the timer fix

The owner's 0.2.3 capture had 646 focused, loaded updates over 27.69 seconds.
Updates averaged 43.05 ms (p95 113.13 ms), while update work averaged 2.48 ms.
Requested waits never exceeded 16.61 ms; 352 waits overshot by more than 50 ms.
Native painting and presentation averaged about 1.3 ms each. The recording used
1280×800 at 1× density, so it did not point to Retina raster cost.

A Linux experiment with **100 ms timer slack** reproduced the wait pattern.
Patch 0012 uses a dedicated timer descriptor: `kevent64` with `NOTE_CRITICAL`
on macOS and `timerfd` on 64-bit Linux. Input readiness still wakes immediately;
early input cancels the timer, idle windows sleep, and no global priority changes
are made. The old 50 ms elapsed-time clamp was also removed from playback.

The original logs cannot prove the Mac kernel policy. The controlled reproduction,
regressions, and subsequent owner feedback support the fix; keep that distinction
when reporting evidence.

## Regression contracts

- The UI advances playback using actual elapsed time after delayed frames.
- Short projectile flights remain visible before their impact events.
- Recovery catches up when retained motion history no longer includes the cursor.
- Precise waits release descriptors, cancel/rearm correctly, and fall back safely.
- Focus loss cancels input before synthetic key releases can fire a charged shot.
- Command-Q saves native diagnostics even when AppKit skips Rust destruction.
- Host/terrain child Ruby processes use explicit UTF-8, even under `LC_ALL=C`.

The [anonymized cadence fixture](../../test/fixtures/README.md) contains no player
identities or content. `test/presentation_test.rb` replays it alongside long
pauses and history jumps. Encoding, activity, diagnostics, and native lifecycle
tests cover the other contracts.

## Comparison controls and reports

| Control/report | Purpose |
| --- | --- |
| `BURROW_RENDER_PIXELS=0` | Disable the default 1.5-million-pixel render budget for comparison |
| `BURROW_MAC_ACTIVITY=0` | Disable scoped activity assertions for comparison |
| `BURROW_DATA_DIR`, `BURROW_LOG_DIR` | Isolate test state and logs |
| `ruby.json` | Requested/actual waits, selected timer backend, fallback errors |
| `rust.json` | Paint/present timings, surface density, render size, exit flush |
| `game.json` | Focus, loading, updates, host/playback ticks, backlog, resynchronization |

Reports retain recent samples, so whole-session averages and active-motion
intervals must not be confused. Linux OpenAL null output checks mixing, not sound.
Linux Xvfb presentation does not measure Mac displays or input-to-photon latency.

## References

- [Mac 0.2.3 analysis](../validation/macos-user-0.2.3-analysis.json)
- [0.2.4 integrated evidence](../validation/release-0.2.4.json)
- [0.3.0 integrated evidence](../validation/release-0.3.0.json)
- [Independent Scarpe patches](../../patches/scarpe/README.md)
- [Apple select implementation](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/sys_generic.c)
- [Apple kernel events and timers](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_event.c)


## 0.5.0 renderer investigation (2026-10-12)

Patches 0014–0017 reduce native work without changing simulation or Ruby timing.
The 50% damage cutoff repainted the full window whenever the clipped battlefield
moved. Keeping the undamaged strips until damage reaches 95% preserves the HUD's
already-correct pixels, without a second transparent subtree compositor. The
existing padded raster, clipping and damage verification remain in use.

Shaping is cached by content/style/width/owner, and glyphs by physical glyph key.
Moving an unchanged para reuses its shape; integer physical moves also reuse its
glyph raster. Fractional X movement can populate four subpixel bins. Outlined
labels have separate hit-test owners and shape entries but share glyph rasters;
full paints still traverse and blend every layer.

Images have four exact device-size copies per path. Fractional edge rounding can
need four width/height combinations even at a fixed zoom; zooming needs new sizes.
Rotated images use the normal bicubic shader and do not increment the resample
counter. The document's hidden references already keep many grub frames alive,
but other path cycles lost both decode and resized copies as soon as they were
unshown. A 64-path / 32 MiB inactive cache removes that avoidable churn while
preserving file invalidation. IPC already batches pipe writes and native event
wakeups; removing a redundant property-map clone provides smaller headroom.

[Mac preview run 38299955006](https://github.com/AliOsm/scarpe-worms/actions/runs/38299955006)
executed packaged 0.5.0 on Apple silicon and failed its sustained-rendering gate.
Combat/pan presentation intervals averaged 22.27/24.62 ms, with 32.95/36.21 ms p95,
while paint averaged 2.07/3.80 ms and present 1.61/1.73 ms. The surface was only
1280×653 at 1×. This confirms a Mac cadence problem, not its cause or Retina cost.
The renderer queued expired frame deadlines in `AboutToWait`, after winit AppKit
had drained redraws; patch 0016 queues them in `NewEvents` and records lateness.
No new Mac result exists for that change.

Mac presentation already uses the bounded CoreAnimation image and DeviceRGB
matching. Scarpe converts RGBA to softbuffer's 0RGB; softbuffer 0.4 allocates a
fresh presentation buffer each frame and ignores damage hints on Mac. That path
was not rewritten without a Mac measurement. With the 1.5 MP budget, a physical
3024×1964 window renders 1512×982; 3456×2234 renders 1152×745, because divisors are
integers. Linux's 3840×2400 benchmark renders 1280×800, then expands in software.

The [renderer validation report](../validation/renderer-per-frame-0.5.0.json) retains
before/after and failed captures plus microbenchmarks. `perf` was installed but
unavailable (`perf_event_paranoid=4`). Linux/Xvfb and OpenAL null output do not
establish Retina Mac frame times or audible sound.
