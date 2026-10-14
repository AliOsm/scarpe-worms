# Bundled Linux runtime notices

The game's MIT license is in `../app/LICENSE`; art, fonts and audio credits
are in `../app/THIRD_PARTY.md` and the assets' own notices. Scarpe's notice is
in `../scarpe/LICENSE.txt`. Every shipped gem retains its license in
`../gems/<name>/`. Rust crate notices and their version/source index are in
`rust/`, and Rust standard-library notices are in `rust-runtime/`.

Traveling Ruby 3.4.7 comes from the checksum-pinned **minimal** Linux x86-64
archive, rel-20251122. It was built in Holy Build Box on CentOS 7; its sources
and build recipes are at https://github.com/trubygems/traveling-ruby/tree/rel-20251122/linux.
The exact URLs and hashes are in `../build-dependencies.json`. The game retains the
interpreter and standard libraries, not the archive's unrelated gem executables,
libtinfo or libffi.so.6. The retained extensions have no dependency on those two
shared libraries; packaging audits every ELF dependency.
Packaging removes the Ruby executable's original `/tmp/ruby/lib` ELF RPATH.

| Component | Source | Notice |
| --- | --- | --- |
| Ruby 3.4.7 and standard libraries | https://github.com/ruby/ruby/tree/v3_4_7 | Ruby-COPYING, Ruby-BSDL, Ruby-LEGAL |
| Traveling Ruby | https://github.com/trubygems/traveling-ruby/tree/rel-20251122 | Traveling-Ruby-LICENSE |
| OpenSSL 3.6.0 (Ruby extension) | https://github.com/openssl/openssl/tree/openssl-3.6.0 | OpenSSL-LICENSE |
| libffi 3.5.2 (Fiddle extension) | https://github.com/libffi/libffi/tree/v3.5.2 | libffi-LICENSE |
| libyaml 0.2.5 (Psych extension) | https://github.com/yaml/libyaml/tree/0.2.5 | libyaml-LICENSE |
| zlib 1.3 | https://github.com/madler/zlib/tree/v1.3 | zlib-LICENSE |
| CA certificate bundle | https://github.com/trubygems/traveling-ruby/blob/rel-20251122/shared/ca-bundle.crt | Mozilla-MPL-2.0 |
| OpenAL Soft 1.24.3 | https://github.com/kcat/openal-soft/releases/tag/1.24.3 | openal-soft/COPYING (LGPL v2 or later), LICENSE-pffft, fmt-LICENSE |

The CA bundle is copied unchanged from Traveling Ruby. Its upstream commit
`ccfda25664d9290dc704719b86fd2c5ecfdd93d6` identifies it as CentOS 8's bundle,
derived from Mozilla's certificate store. The PEM source is shipped at
`../runtime/ruby/lib/ca-bundle.crt`; the MPL 2.0 text accompanies this notice.

OpenAL Soft is dynamically linked at `../../lib/libopenal.so.1`. Its complete
corresponding source archive and the actual CMake build flags accompany the
library in `openal-soft/`. You may modify or replace it with an ABI-compatible
build and reverse engineer the application to debug those modifications.
There is no signature or loader restriction preventing replacement.

The operating system supplies glibc, libcrypt, libgcc, libstdc++, the desktop
connection libraries and audio server/client libraries. They are not copied
into this archive. The renderer paints with tiny-skia and softbuffer; it does
not require OpenGL, Vulkan, GTK, WebKit or a web browser.
