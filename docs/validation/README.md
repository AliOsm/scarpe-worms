# Validation reports

These are recorded results, not live status badges. Versioned filenames identify
their scope; generic filenames are outputs of individual tools.

| Evidence | Start here |
| --- | --- |
| Repository setup from a clean checkout | [repository-bootstrap.json](repository-bootstrap.json) |
| Integrated baseline | [release-0.3.0.json](release-0.3.0.json) |
| Core | [Ruby 3.4.7](core-0.3.0-ruby-3.4.7.json), [Ruby 4.0.7](core-0.3.0-ruby-4.0.7.json) |
| Native journeys | [native-0.3.0.json](native-0.3.0.json) |
| Rendering | [source](rendering-0.3.0-source-linux.json), [packaged](rendering-0.3.0-linux.json) |
| Timing stress | [rendering-0.3.0-slack-linux.json](rendering-0.3.0-slack-linux.json) |
| Mac archive | [integrity](distributable-0.3.0.json), [static checks](macos-arm64-package-0.3.0.json) |
| Previous smoothness fix | [release-0.2.4.json](release-0.2.4.json), [timing history](../history/PERFORMANCE.md) |

Report paths use `<workspace>`, `<ruby-home>`, or `<user-home>` where local absolute
paths were removed for publication. Measurements and checksums are unchanged.
Fresh captures and raw frame arrays stay local or in CI artifacts; regenerate
with the commands in [VALIDATION.md](../VALIDATION.md).

Only promote useful, reviewed summaries to versioned filenames. Never add player
saves, session tokens, certificates, chat, or unreviewed customer diagnostics.
