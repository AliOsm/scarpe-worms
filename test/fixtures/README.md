# Presentation cadence

`macos_0_2_3_cadence.json` contains 646 loaded, focused gameplay updates from the
user-supplied 0.2.3 M3 Pro report. Each row is `[elapsed_seconds, host_tick]`.
Times are relative to the first included frame; host ticks are rebased to 30.
There are no identities, absolute timestamps, names, tokens, or game content.

The presentation regression feeds this cadence into a synthetic moving actor.
The old 50 ms elapsed-time cap accumulated seconds of lag with these updates.
The test requires motion to stay within the retained history and ordinary
snapshot jitter, including all of the recorded long update intervals.
