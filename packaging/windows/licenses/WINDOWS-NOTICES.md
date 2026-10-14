# Bundled Windows runtime notices

Burrow Brigade is MIT licensed. Its license and asset notices are in
`../app/LICENSE` and `../app/THIRD_PARTY.md`. Fonts retain their SIL Open Font
Licenses, and the audio samples retain their CC0 notices in the assets tree.
The gems include their own notices under `../gems/`.

Ruby 4.0.7 is from the official
[RubyInstaller 4.0.7-1 archive](https://github.com/oneclick/rubyinstaller2/releases/tag/RubyInstaller-4.0.7-1).
The exact URL and SHA-256 are recorded in `../build-dependencies.json`.
The interpreter, standard libraries, bundled gems and supporting DLLs are
shipped; development tools are omitted.

* Ruby: Ruby-COPYING, Ruby-BSDL and Ruby-LEGAL; source
  <https://github.com/ruby/ruby/tree/v4_0_7>.
* RubyInstaller: RubyInstaller-LICENSE.txt; build recipes
  <https://github.com/oneclick/rubyinstaller2>.
* OpenSSL: OpenSSL-LICENSE; <https://github.com/openssl/openssl>.
* libffi: libffi-LICENSE; <https://github.com/libffi/libffi>.
* libyaml: libyaml-LICENSE; <https://github.com/yaml/libyaml>.
* zlib: zlib-LICENSE; <https://github.com/madler/zlib>.
* GMP: GMP-LGPLv3 and GMP-GPLv3;
  <https://gmplib.org/download/gmp/gmp-6.3.0.tar.xz>.
* GCC runtime: GCC-GPLv3 and GCC-RUNTIME-EXCEPTION;
  <https://gcc.gnu.org/git/?p=gcc.git>.
* MinGW-w64 winpthreads: winpthreads-COPYING;
  <https://github.com/mingw-w64/mingw-w64/tree/master/mingw-w64-libraries/winpthreads>.

OpenAL Soft 1.25.2 is LGPL-2.0-or-later. Its unmodified Win64 `soft_oal.dll`
is installed as `../ruby/bin/OpenAL32.dll`. The LGPL and PFFFT notices
are in `openal-soft/`. Complete corresponding source and build instructions:
<https://github.com/kcat/openal-soft/tree/1.25.2> (source archive:
<https://github.com/kcat/openal-soft/archive/refs/tags/1.25.2.tar.gz>).
No system OpenAL installation is required. The configuration utility and router
are not distributed.

GMP, GCC support libraries, winpthreads, and OpenAL are separate dynamic
libraries. You may replace them with ABI-compatible builds and debug those
modifications; the game imposes no restriction on doing so. The bundled Ruby
game/framework code is readable source. The dependency links and
RubyInstaller build recipes identify the corresponding source.

Scarpe's MIT notice is at `../scarpe/LICENSE.txt`. Its pinned upstream revision
and patches are bundled. Rust crate license texts and a version/source index
are in `rust/`, with Rust standard-library notices in `rust-runtime/`.
The launcher and renderer use a static Microsoft C runtime built with the
Windows runner's Visual Studio toolchain. Windows system libraries remain
provided by the operating system.
