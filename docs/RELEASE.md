# Release status and remaining acceptance work

Version 0.3.0 is a functional preview with the implemented game and automated
validation. It is **not yet certified for sale**. The evidence in VALIDATION.md
describes what actually ran; generated workflows are not execution evidence.

The user confirmed 0.2.4 runs smoothly on an M3 Pro; 0.3.0 retains that renderer
fix and needs the same Mac acceptance pass for its new art and weapon controls.
The available workstation is Linux. The remaining Mac-specific requirements
cannot be established by its cross-compiler or headless Linux renderer:

- Launch the delivered app through Finder on clean Apple silicon Macs running
  the minimum supported macOS and a current macOS version. Check Retina and
  external displays, resize, minimize, fullscreen/Spaces, sleep/wake, keyboard
  focus, and a relocated app path. Run the provided native package smoke checks.
- Listen to every effect, simultaneous explosions, music loops, mute/resume,
  and volume changes using the Mac's actual OpenAL output and headphones.
  The Linux null-output test validates decoding/mixing only.
- Complete matches with two through six humans on separate internet connections,
  including an unreachable host, slow connection, dropped Wi-Fi, host restart,
  reconnection, host migration, and rematch. Automated loopback tests establish
  protocol behavior, not every real network condition.
- Obtain human playtesting of weapon balance, bot behavior, aiming, crowded
  landscapes, small-window legibility, sound levels, and reduced-motion mode.
  The 48-weapon tests establish implemented mechanics; they do not establish
  competitive balance or subjective polish.
- Run Developer ID signing, hardened-runtime validation, notarization, stapling,
  and a clean-machine Gatekeeper test against the final ZIP. Credentials and
  an Apple developer account are not available in this workspace.
- Confirm a distribution channel, support/contact process, price, refund policy,
  crash-reporting process, and update delivery before offering it for sale.
  The current app has no store, payment integration, or automatic updater.

The first package is arm64 only. No claim is made for Intel Macs, Windows,
gamepads, Steam integration, public matchmaking, or replay playback. The game
can be hosted privately without any of those services.

Release procedure: run all repository checks → build the preview → run native
Mac and human acceptance → sign/notarize → rerun native tests on the signed
artifact → test the quarantined download → archive hashes/evidence → publish
through the chosen channel. No publishing or external deployment has been
performed as part of this implementation.
