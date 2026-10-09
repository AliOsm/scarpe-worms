# Validation reports

These are recorded results, not live status badges. Versioned filenames identify
their scope; generic filenames are outputs of individual tools.

| Evidence | Start here |
| --- | --- |
| Current integrated preview | [release-0.4.0.json](release-0.4.0.json) |
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

Report paths use `<workspace>`, `<ruby-home>`, or `<user-home>` where local absolute
paths were removed for publication. Measurements and checksums are unchanged.
Fresh captures and raw frame arrays stay local or in CI artifacts; regenerate
with the commands in [VALIDATION.md](../VALIDATION.md).

Only promote useful, reviewed summaries to versioned filenames. Never add player
saves, session tokens, certificates, chat, or unreviewed customer diagnostics.
