# Validation reports

These are recorded results, not live status badges. Versioned filenames identify
their scope; generic filenames are outputs of individual tools.

| Evidence | Start here |
| --- | --- |
| 0.5.7 combat responsiveness | [Damage-label preparation, terrain equivalence, mixed audio, Mac backend comparisons and remaining frame stalls](responsiveness-0.5.7.json) |
| 0.5.7 movement experiment | [Apple silicon build, prediction latency, native checks, compatibility and rendering limits](client-prediction-0.5.7.json) |
| 0.5.6 Ruby 4 and Rust 1.99 | [Source, runtime relocation, packaged clients and server checks](runtime-0.5.6.json) |
| 0.5.4 optimization round | [Final Linux A/B vs 0.5.3](perf-0.5.4-final-linux.json), [Apple silicon runner captures](perf-0.5.4-mac.json); per-area experiments for [audio](perf-0.5.4-audio.json), [frame loop](perf-0.5.4-frame.json), [renderer](perf-0.5.4-renderer.json), [host](perf-0.5.4-host.json), [network/playback](perf-0.5.4-net.json), [startup/runtime](perf-0.5.4-startup.json), [terrain packets](perf-0.5.4-terrain.json), [terrain painting](perf-0.5.4-painter.json) and the [Apple OpenAL voice follow-up](perf-0.5.4-voices.json) |
| 0.5.3 grub reactions: sounds and animations | [Linux tests, assets, native lab captures, rendering and limits](reactions-0.5.3-linux.json) |
| 0.5.2 server deployment and YJIT host | [GitHub Actions deploy rehearsal, redeploy during a match, tick cost](server-deploy-0.5.2.json) |
| 0.5.2 weapons sweep (48 weapons, integrated) | [Linux tests, native lab, checkers and performance](weapons-0.5.2-linux.json); family reports for [mobility](weapons-mobility-linux.json), [munitions](munitions-sweep.json) and [critters](weapons-critters-linux.json) |
| 0.5.1 smooth zoom and stall attribution | [Linux A/B, Apple silicon, exact pixels and remaining limits](zoom-0.5.1.json) |
| 0.5.0 Mac update cadence | [Mac and Linux comparisons, timer checks and limits](mac-cadence-0.5.0.json) |
| 0.5.0 renderer per-frame investigation | [Linux before/after, Mac CI baseline, tests and limits](renderer-per-frame-0.5.0.json) |
| 0.5.1 performance sweep on an Apple silicon runner | [0.5.0 vs 0.5.1 packaged rendering](macos-runner-0.5.1.json) |
| 0.5.2 on a GitHub Apple silicon runner | [Two attempts and a same-hour 0.5.1 baseline](macos-runner-0.5.2.json) |
| 0.5.2 Mac archive (cross-built) | [Integrity](distributable-0.5.2.json), [static checks](macos-arm64-package-0.5.2.json), relocated packaged Ruby code on Linux ([unset locale](package-0.5.2-relocated-linux.json), [C locale](package-0.5.2-relocated-linux-locale-c.json)) |
| 0.5.1 Mac archive (cross-built) | [Integrity](distributable-0.5.1.json), [static checks](macos-arm64-package-0.5.1.json), relocated packaged Ruby code on Linux ([unset locale](package-0.5.1-relocated-linux.json), [C locale](package-0.5.1-relocated-linux-locale-c.json)) |
| 0.5.0 battlefield and blast physics (unreleased) | [battlefield-0.5.0-linux.json](battlefield-0.5.0-linux.json) |
| Input latency, adaptive playback and immediate audio (unreleased) | [latency-audio-linux.json](latency-audio-linux.json) |
| 0.5.0 Ruby frame work (isolated branch) | [CPU, properties, allocations, GC and scheduler diagnosis](ruby-frame-0.5.0-linux.json) |
| 0.5.0 Mac archive (cross-built, not launched on a Mac) | [Integrity](distributable-0.5.0.json), [static checks](macos-arm64-package-0.5.0.json), relocated packaged Ruby code on Linux ([unset locale](package-0.5.0-relocated-linux.json), [C locale](package-0.5.0-relocated-linux-locale-c.json)) |
| Arcade interface restyle (unreleased) | [ui-arcade-restyle-linux.json](ui-arcade-restyle-linux.json) |
| 0.4.0 integrated preview | [release-0.4.0.json](release-0.4.0.json) |
| Core | [Ruby 3.4.7](core-0.4.0-ruby-3.4.7.json), [Ruby 4.0.7](core-0.4.0-ruby-4.0.7.json) |
| Native journeys | [native-0.4.0.json](native-0.4.0.json) |
| Rendering | [source](rendering-0.4.0-source-linux.json), [packaged](rendering-0.4.0-linux.json) |
| Timing stress | [source with 100 ms slack](rendering-0.4.0-source-slack-linux.json), [packaged with slack](rendering-0.4.0-slack-linux.json) |
| Timing investigation | [Outlier and classification correction](rendering-0.4.0-investigation.json) |
| Endurance | [30-minute native soak](native-soak-0.4.0.json) |
| Art and audio assets | [Audit](assets-0.4.0.json), [two identical full builds](asset-reproducibility-0.4.0.json) |
| Audio mixer | [22 cues and positional effects](audio-0.4.0.json) |
| Opus 5.5 review | [Findings and dispositions](presentation-review-0.4.0.json) |
| Unicode installation startup | [Regression and fixture correction](encoding-0.4.0.json) |
| Mac archive | [Integrity](distributable-0.4.0.json), [static checks](macos-arm64-package-0.4.0.json) |
| Relocated packaged Ruby code on Linux | [Unset locale](package-0.4.0-relocated-linux.json), [windowed C locale](package-0.4.0-relocated-linux-windowed-locale-c.json) |
| Prior 0.3.0 baseline and clean setup | [release-0.3.0.json](release-0.3.0.json), [repository-bootstrap.json](repository-bootstrap.json) |
| Previous smoothness fix | [release-0.2.4.json](release-0.2.4.json), [timing history](../history/PERFORMANCE.md) |

Report paths use `<workspace>`, `<ruby-home>`, `<user-home>` or `<scratch>` (an optimization
round's local capture directory) where local absolute paths were removed for publication. Measurements and checksums are unchanged.
Fresh captures and raw frame arrays stay local or in CI artifacts; regenerate
with the commands in [VALIDATION.md](../VALIDATION.md).

Only promote useful, reviewed summaries to versioned filenames. Never add player
saves, session tokens, certificates, chat, or unreviewed customer diagnostics.
