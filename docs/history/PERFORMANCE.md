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

## Mac cadence follow-up (2026-10-13)

The integrated Apple silicon capture (workflow 38321273034) did not resolve
cadence: continuous pan submitted 274 frames for 357 moving Ruby updates,
21.90 ms mean / 29.44 ms p95 between submissions. Of its paint gaps, 83 contained
at least two completed updates. Native software refresh deadlines were requested
874 times and arrived 5.70 ms late on average (61.76 ms maximum). A scheduler
that refuses an update until a full refresh after the previous *actual* draw
start adds that lateness to its next deadline. The observed wait accounts for
the roughly five milliseconds missing from each pan interval despite cheap
painting and presentation.

Ruby's `Timers::Timer#due_at` already uses `origin + slot * interval`, skipping
missed slots without moving the origin. Combat/pan update medians were
16.671/16.664 ms. Occasional stalled updates raised the means to
16.931/16.855 ms; changing Ruby to another fixed grid would not address this.
Patch 0012's `NOTE_CRITICAL` and `timerfd` paths remain unchanged.

Patch 0018 removes the extra software deadline on macOS: a complete dirty IPC
update requests AppKit redraw immediately. Winit 0.30 coalesces pending requests
within the run-loop turn, then CoreAnimation receives the submitted image.
Winit does **not** provide a display-link/vsync gate here. Ruby's existing 60 Hz
producer supplies cadence; high-rate producers may submit above display refresh.
Other platforms retain patch 0009's software pacing. This avoids adding a native
display-tick protocol, coupling animation semantics to one display, or introducing
a second precision timer. The IPC batch guard and native input's existing ability
to interrupt a batch are unchanged.

The reported 144.800 ms maximum window redraw belongs, within 0.039 ms, to the
startup frame at native uptime 1.833 s: paint 105.316 ms + present 39.445 ms.
Combat did not start until 7.548 s. A separate 268.782 ms combat submission gap
included 251.340 ms accumulated layout time. Concurrent Ruby updates took
79.722/39.708 ms wall time but only 8.035/1.065 ms thread CPU time, with 2/0 ms GC.
This suggests shared runner descheduling; existing logs cannot establish its
exact cause. A layout tally aggregates all layout work since the previous frame,
so it is not a measurement of time spent inside that one redraw callback.

Native frame timestamps mark completion of `softbuffer::present`, not physical
scanout. A passing packaged CI capture establishes submission cadence on its
measured 1× display; ProMotion/Retina behavior and visible frames need the owner's
M3 Pro or another physical display capture.

The first patch-0018 Mac run restored pan to 16.77 ms mean / 20.37 ms p95,
358 paints for 359 moving updates, with no software frame deadlines. Its remaining
failure was one 91.515 ms idle update interval: a 13.176 ms input wait took
88.809 ms, while the subsequent update cost only 0.516 ms wall / 0.459 ms CPU.
That localizes the delay to input waiting but cannot distinguish kernel scheduling
from Ruby GVL reacquisition or runner contention. It does not prove the kernel
timer itself expired late.

An unchanged second run yielded pan 16.70/19.30 ms, but exposed a diagnostic clock
mismatch. On macOS, Rust `Instant` uses `CLOCK_UPTIME_RAW`; Ruby timestamps use live
wall time. Native stats reconstructed wall time from just one startup anchor.
Pairing 625 native draws with Ruby's early layout-response wakes revealed about
-0.506 ms/second drift (0.182 ms residual standard deviation), versus -0.002 ms/s
in the first capture. After 16 seconds, a camera update could appear after the
frame that had already shown it, and the analyzer charged an unrelated next paint
as an 80 ms stall. This is an inference explaining a measurement defect; those
inferred offsets are not applied to the published historical results.

Patch 0019 appends a measured live Unix timestamp to every bounded frame row.
`check_rendering.py` uses it to correlate process samples and select stage bounds,
then measures the selected portion of each interval with the original monotonic
clock. Legacy rows retain their original mapping. Tests cover both the false
clock-drift stall and a genuinely unpainted movement; budgets are unchanged.
The second run also contained a real initial 65.276 ms combat gap, with 46.924 ms
between completion of input waiting and entry to a cheap update. Its exact source
is not recoverable from aggregate phase counters.

Two new packaged Apple silicon captures with live frame anchors retain the
cadence improvement but still fail the strict maximum-interval gate. The complete
[cadence report](../validation/mac-cadence-0.5.0.json) retains all four attempts.
The final unchanged rerun reaches 361 paints for 361 continuous pan updates,
16.66 ms mean / 17.96 ms p95 / 19.95 ms maximum. Paint and update counts do not
identify individual batches; combat also includes idle updates and extra native
redraws. Its active-motion interval selection is a timestamp-based estimate.

| Mac capture | Combat mean / p95 / max (ms) | Pan mean / p95 / max (ms) | Pan paints / updates |
| --- | --- | --- | --- |
| Integrated baseline | 21.64 / 29.88 / 268.78 | 21.90 / 29.44 / 50.56 | 274 / 357 |
| Corrected clocks, attempt 1 | 15.98 / 22.13 / 54.73 | 16.77 / 20.93 / 67.09 | 358 / 359 |
| Same build, attempt 2 | 16.23 / 18.78 / 95.43 | 16.66 / 17.96 / 19.95 | 361 / 361 |

The baseline uses the original clock correlation; corrected captures use measured
live anchors, without retroactively applying inferred offsets. Both new runs
record zero software frame deadlines. Attempt 1's real 67.092 ms pan gap overlaps
a 32.036 ms native paint and a Ruby input wait that overshot by 24.674 ms. Earlier
Ruby work took 5.217 ms wall / 1.103 ms thread CPU, with no GC. This supports a
shared scheduling/system disturbance; native paint has no CPU-time measurement,
so the exact cause remains unresolved. Attempt 2 fails on a 95.435 ms combat gap,
during which five completed Ruby updates move actors and the camera. The closing
frame includes 44.254 ms accumulated layout, 2.867 ms paint and 3.716 ms present;
44.152 ms of the gap lies outside measured native phases. A preceding 50.108 ms
active gap includes 27.043 ms accumulated layout. Combat Ruby update intervals
remain below 22.746 ms and wait overshoot below 6.166 ms. Live-clock agreement is
within 0.030 ms, so this is not the earlier clock-correlation artifact.

These remaining gaps need native batch-receipt/settle/redraw timestamps and
layout thread CPU time to distinguish event-loop delay from expensive layout
or descheduling. The current counters do not justify another pacing change.
Neither failed run is presented as an all-passing Mac validation.

Final Linux checks pass: patch verification, 368 Rust tests (11 ignored),
133 Ruby tests / 5,979 assertions, seven native journeys / 228 assertions,
timer regressions, and 13 rendering-analysis tests. Normal and 100 ms timer-slack
rendering both pass the existing budgets. The normal combat/pan means changed
from 16.57/16.67 to 16.53/16.71 ms; with timer slack they changed from 16.61/16.71
to 16.48/16.67 ms. Linux software pacing is unchanged. Discrete zoom intervals
vary with idle scene content and are retained in the report; their paint budget
passes. No budget was relaxed and no game logic or Ruby timer was changed.

## 0.5.4 optimization round (2026-10-14)

The owner heard lagging audio in packaged 0.5.3 on an M3 Pro. Eight agents
measured one area each against a frozen 0.5.3 tree: five interleaved runs per
comparison under an exclusive benchmark lock, kept only for a ≥5% median win
holding in ≥4 of 5 pairs, with identical pixels, per-tick simulation hashes and
protocol-4 interoperability in both directions. Rejected patches and raw captures
stayed outside the repository; each area's experiments are in
`docs/validation/perf-0.5.4-*.json`.

**Host stall at every crater.** `Terrain#export` deflated the whole material
grid at zlib's default level and hashed it with `Digest::SHA256` on the reactor
thread whenever the terrain changed: 16 of 900 ticks overran 33 ms in a six-team
heavy match, up to 63–71 ms. Snapshots stalled with it, so the client's
50–150 ms playback buffer drained at the explosion (2–3 underruns per loopback
session with craters) and the blast's sound and picture arrived late together.
`Zlib::RLE` at level 1 produces a standard zlib stream about three times faster;
masks that would exceed 192 KiB fall back to default compression, keeping frames
far inside the 512 KiB limit. OpenSSL hashing replaced Digest. Late ticks fell to
zero (worst 26 ms), blast → packet sent from 61 to 24 ms, and underruns to zero.

**Crater pipeline.** The terrain worker resampled the full minimap from every
tile after each revision; it now updates only changed tile regions. PNG UP
filtering and the texture kit's average-filter decoding use packed integer
arithmetic per scanline, with byte-identical tiles. Blast → crater tiles ready
fell from 283 to 50 ms and Quick Battle → painted battlefield from 4.50 to 3.39 s.

**Audio.** Delayed cues (voices, pop/poof/thud) were flushed with the frame's
start time, so a cue that became due during frame work waited for the next
frame: median lateness fell from 17.5 to 8.8 ms by reading the clock after frame
work. Voice selection became one allocation-free pass. `audio.json` records due
versus start time, drops, cut-offs, OpenAL call time and the default output
device's reported latency and transport. Twenty-four effect voices removed every
cut-off in a heavy Linux fixture (6 → 0 per 7 s), but all four Apple silicon
runner captures with 24 voices slowed zoom to 28–29 ms mean against 19–24 ms
with 12, so 0.5.4 keeps 12. A follow-up on eight more runner captures found
idle sources free (0.418% vs 0.421% process CPU for 12 and 24) but playing
voices costly (1.275% with 24 playing). Capping 24 sources at 12 playing, low
spatial quality, stereo output, a 25-bus mixer, 22.05/44.1 kHz output and 14 or
16 voices all failed the zoom guard. Mono `alSourcePlay` costs about 0.3–0.45 ms
on Apple's OpenAL (0.02 ms in a stereo configuration), which is worth revisiting
if sound bursts show up in owner logs.

**Smaller wins.** Host collision samples and hazard scans stopped allocating
(tick p50 −10%; with the export change, host CPU per simulated second fell from
65 to 42 ms). Outlined comic captions are pooled (repeat blast frames 18–20 → 7–8
ms of Ruby preparation; a broader pool changed pixels and was rejected).
Timeline sampling merges worm rows without temporary arrays (−17.6% CPU). Patch
0024 builds opaque images' alpha-run index without a second pixel scan (zoom
paint −3.6% to −5%).

**Runtime.** YJIT shortened match start by 1.3 s but doubled the maximum combat
frame CPU, raised GUI memory 24% and is not compiled into the pinned Traveling
Ruby; GC heap/malloc settings and disabling major GC failed their guards.

**Remaining.** Linux combat presentation means and p95s are unchanged, but the
median count of single dropped combat frames rose from 2 to 3 per run while
per-frame Ruby and native costs did not; crater tile loads now overlap blast
frames, which is the likely cause. Shared Mac runners still fail the strict 60 ms
single-interval gate in some runs of both versions. Only the owner's Mac can show
whether the audible lag is gone.
