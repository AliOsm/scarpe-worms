# Bundled runtime notices

Burrow Brigade's MIT license applies to the game. The bundled dependencies retain
their own licenses. Their license texts accompany this file; gem notices remain
in `Contents/Resources/gems/`, and Scarpe's license is in
`Contents/Resources/scarpe/LICENSE.txt`.

The runtime comes from [Traveling Ruby rel-20251122](https://github.com/trubygems/traveling-ruby/releases/tag/rel-20251122).
Its build recipes and patches are in that project's source tree. The exact
archive URL and SHA256 are in `../build-dependencies.json` inside the app and
`packaging/macos/dependencies.json` in the game source.

| Component | Source | License notice |
| --- | --- | --- |
| Ruby 3.4.7 | https://github.com/ruby/ruby/tree/v3_4_7 | Ruby-COPYING, Ruby-BSDL, Ruby-LEGAL |
| OpenSSL 3.6.0 | https://github.com/openssl/openssl/tree/openssl-3.6.0 | OpenSSL-LICENSE |
| GMP 6.3.0 | https://gmplib.org/download/gmp/gmp-6.3.0.tar.xz | GMP-LGPLv3, GMP-GPLv3 |
| libffi 3.5.2 | https://github.com/libffi/libffi/tree/v3.5.2 | libffi-LICENSE |
| libyaml 0.2.5 | https://github.com/yaml/libyaml/tree/0.2.5 | libyaml-LICENSE |
| ncurses 6.5 | https://ftp.gnu.org/gnu/ncurses/ncurses-6.5.tar.gz | ncurses-COPYING |
| libedit 20251016-3.1 | https://thrysoee.dk/editline/libedit-20251016-3.1.tar.gz | libedit-COPYING |
| XZ/liblzma 5.8.1 | https://github.com/tukaani-project/xz/tree/v5.8.1 | xz-COPYING |

GMP is a separate dynamic library at
`Contents/Resources/runtime/ruby/lib/libgmp.10.dylib`. You may modify or replace
it with an ABI-compatible build; no game restriction prevents debugging those
modifications. After modifying an app copy on macOS, re-sign that copy locally
with `codesign --force --deep --sign - '/path/to/Burrow Brigade.app'`. The game is
open source, and the package contains its Ruby runtime source files. GMP's
corresponding source and build recipes are available from the links above.

Rust dependency license texts and their version/source index are collected into
`rust/` during packaging, with Rust standard-library notices in `rust-runtime/`.
Fonts retain their separate SIL Open Font License notices. Apple SDK files and
the build-time signing utility are not redistributed in this app.
