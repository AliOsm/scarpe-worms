# Bundled runtime notices

The game is MIT licensed; see `../app/LICENSE` and `../app/THIRD_PARTY.md`.
Scarpe's notice is in `../scarpe/LICENSE.txt`. Gem notices remain beside their
sources. Rust crate notices are in `rust/`, with standard-library notices in
`rust-runtime/`. Fonts retain their SIL Open Font Licenses.

Ruby 4.0.7 is built from source with relocatable load paths. OpenSSL 3.5.9,
libffi 3.8.0, libyaml 0.2.5 and zlib 1.3.2 are statically linked. Exact source
URLs and SHA-256 digests are in `../ruby-build-dependencies.json`. Their original
license texts are collected from those sources into `ruby/`. Build instructions
are in `tools/build_ruby.py` in the game source repository. Fiddle 1.1.8 is a
separate bundled gem and retains its license with its source.

The Mozilla CA bundle from curl.se is distributed as PEM source at
`../runtime/ruby/lib/ca-bundle.crt`. Its original URL and checksum are recorded
with the build dependencies; the MPL 2.0 text is `Mozilla-MPL-2.0`.
