# Independent native patches for Scarpe

`0001-native-held-key-events.patch` applies to the commit in `SCARPE_REVISION`.
It is independent of Burrow Brigade and is suitable for a separate upstream PR.
The prototypes and upstream checkout are not modified by this project.

The game needs continuous movement and press/release charging. `keypress` alone
does not expose releases and depends on the operating system's repeat delay.
The patch adds `keydown` and `keyup` to the Ruby DSL and native subscriptions,
tracks physical keys, releases held keys on focus loss, and extends automation
with matching press/release commands. Repeated `keypress` behavior is preserved;
text controls consume ordinary typing without moving game characters.

`0002-native-window-activation.patch` applies after the first patch. Its generic
`activation { |active| ... }` callback reports window focus before synthetic key
releases, so applications can cancel charging and dragging on interruption.
It clears captured mouse presses and modifiers, and adds a matching
`automation.window_focus(boolean)` operation. It contains no game code.

Run `python3 tools/verify_scarpe.py` to verify the pinned source plus exactly these
patches. `setup.sh` applies them idempotently and refuses conflicting local changes.

Validation:

```sh
cargo test --release --locked --manifest-path vendor/scarpe/native/Cargo.toml \
  --test held_keys --test window_activation --test protocol
./bin/check-native
```

The Rust tests check modifier changes, repeats, focus-loss releases, activation
ordering, and interrupted mouse presses. The game checks exercise held movement,
charging cancellation, and deliberate firing after refocusing through automation.


Rendering patches added for the larger battlefields (each applies after the
preceding patch and contains no game logic):

- `0003-native-clipped-image-animation.patch`: draws the full rotated silhouette
  inside a slot clip and tracks its transformed damage bounds. Includes 1×/2×
  pixel and partial repaint checks.
- `0004-native-unchanged-visual-props.patch`: ignores identical visual props,
  avoiding unnecessary layout and repaint. File-backed paint/image changes and
  text-control resets retain their existing behavior.
- `0005-native-layout-container-damage.patch`: empty layout containers do not
  contribute damage when their automatic height changes; their painted children
  still participate in clipping, movement and hiding checks.
- `0006-native-aligned-image-blits.patch`: copies/blends already resampled images
  at integer coordinates directly. Alpha and clipping are compared byte for
  byte with tiny-skia's normal pipeline; transformed/fractional images retain
  the normal rasterizer.

Additional checks:

```sh
cargo test --release --locked --manifest-path vendor/scarpe/native/Cargo.toml \
  --test damage --test image_animation --test unchanged_props --test image_blit
```

Retina performance patches (still independent of game code):

- `0007-native-cached-simd-images.patch`: separable Catmull–Rom resizing with
  `fast_image_resize` (NEON on Apple silicon), preserving premultiplied alpha.
  Bounded alpha-run indexes skip empty pixels and copy opaque spans. Fragmented
  alpha falls back to ordinary blending. Fractional rectangular clips match
  Skia's edge rounding. Pixel comparisons cover alpha, clips, scales and damage
  origins; resize tests check color/alpha and file invalidation.
- `0008-native-render-budget-and-frame-diagnostics.patch`: optional
  `SCARPE_NATIVE_MAX_RENDER_PIXELS` bounds software rasterization while retaining
  logical layout/input coordinates. The Mac surface explicitly uses CoreAnimation
  content scaling; other platforms expand the buffer before presenting. Defaults
  remain full device resolution in Scarpe. Frame diagnostics report physical and
  render dimensions and retain the most recent 10,000 samples, including lag late
  in a session. Tests cover pixel budgets, expansion, odd edges and bounded logs.

- `0009-native-even-frame-pacing.patch`: spaces frames by one display refresh
  instead of permitting two-frame bursts followed by a longer wait. Changes
  arriving early are coalesced; input after an idle interval remains immediate.
  Tests cover bursts, coalescing, idle input and unknown refresh rates.

- `0010-native-save-stats-on-appkit-quit.patch`: saves native timing data in
  the event loop's exit callback. AppKit's Command-Q can terminate the process
  without unwinding Rust and therefore skip the `Stats` destructor.
- `0011-native-scheduler-wait-diagnostics.patch`: records bounded, chronological
  requested/actual Ruby waits and wake-up overshoot. This distinguishes ordinary
  idle waits from delayed animation deadlines. Tests cover early wakes, delayed
  wakes, exceptional exits, and ring-buffer retention.
- `0012-native-precise-deadline-waits.patch`: waits on a one-shot timer descriptor
  alongside the renderer and wake pipe. macOS uses `kevent64`/`NOTE_CRITICAL`;
  64-bit Linux uses `timerfd`. Other platforms keep the portable select timeout.
  Ordinary sleep timeouts can be coalesced past animation deadlines even while
  native rendering is cheap. Input cancels the pending timer, idle apps still
  sleep, and close releases the descriptor. Fiddle is a declared dependency for
  Ruby 4 (bundled Ruby 3.4 already includes it). Tests cover real descriptor waits,
  early input, rearming, fallback, cleanup, the Darwin ABI, and Linux 100 ms timer
  slack. `ruby.json` reports the selected backend and runtime fallback errors.

Timer reproduction (on Linux this applies 100 ms timer slack to the test thread):

```sh
bundle exec ruby tools/check_waits.rb
```

The game opts into a 1,500,000-pixel budget. `BURROW_RENDER_PIXELS=0` disables it.
The larger-window check runs at 3,840 × 2,400 physical pixels; it verifies the
actual surface density and render budget, not just the Ruby animation timer.

```sh
cargo test --release --locked --manifest-path vendor/scarpe/native/Cargo.toml \
  --lib --test images --test image_blit --test image_animation --test damage
xvfb-run -a -s '-screen 0 3840x2400x24' \
  python3 tools/check_rendering.py --scale 2 --size 1920x1200
```
