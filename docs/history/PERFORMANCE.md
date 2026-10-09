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
