# Credits and distribution notices

Burrow Brigade is an original turn-based artillery game. It contains no Team17
art, audio, code, logos, or branding. Internal weapon identifiers describe game
mechanics; displayed names and artwork are original. This project is not an
official Worms title.

- Character frames, weapon icons, directional combat sprites, masonry and effects:
  original Cairo artwork in `tools/build_art.py`. The menu, four distant
  backgrounds and four terrain materials are original AI-assisted paintings made with Codex's built-in
  imagegen tool. Their reviewed PNG masters, exact prompts and checksums are
  in `assets/art/source/{paintings,materials}/provenance.json`; rebuilding uses those local
  masters. See `docs/ART_DIRECTION.md`. No Team17 image was used as generation
  input. The menu reference was this project's existing original illustration.
- Music and several effects are original synthesis in `tools/build_audio.rb`.
  Selected effects are from Kenney's Interface Sounds, Impact Sounds, RPG Audio
  and Sci-fi Sounds packs, under CC0-1.0. Full pack notices ship in
  `assets/audio/KENNEY-NOTICES.txt`; source URLs, original hashes and converted
  PCM master hashes are in `assets/audio/source/kenney/manifest.json`.
  Sources: https://kenney.nl/assets/interface-sounds,
  https://kenney.nl/assets/impact-sounds, https://kenney.nl/assets/rpg-audio,
  https://kenney.nl/assets/sci-fi-sounds.
- Inter: Rasmus Andersson, SIL OFL 1.1. Fira Mono: Mozilla and Telefonica, SIL OFL
  1.1. Fredoka: Milena Brandau, SIL OFL 1.1. Font licenses are in `assets/fonts`.
  Fredoka source: https://github.com/google/fonts/tree/main/ofl/fredoka.
- Scarpe, Lacci, and Scarpe Components: MIT, pinned in `SCARPE_REVISION`,
  https://github.com/scarpe-team/scarpe. The standalone local patch is in
  `patches/scarpe`; distribution includes upstream notices.
- The macOS packaging scripts and native test runner were adapted from
  asda-scarpe / Lanternfall, Copyright (c) 2026 Lanternfall contributors, MIT.
  Its full notice is retained in `packaging/macos/licenses/Lanternfall-MIT`.
- Ruby, Traveling Ruby, OpenSSL, libyaml, libedit, GMP, and Ruby standard library
  components: notices and source links in `packaging/macos/licenses` and the
  packaged `Contents/Resources/licenses`. GMP remains a separate, replaceable
  shared library. Traveling Ruby's runtime is distributed unmodified apart from
  ad-hoc code signatures. The SDK and build tools are not included in the app.
- chunky_png (MIT), ffi/libffi (BSD/MIT), base64 and logger (Ruby/BSD-2-Clause),
  fastimage (MIT): complete gem sources and licenses included in the Mac app.
- Native Rust dependency notices are collected from the exact Cargo lockfile
  during packaging into `Contents/Resources/licenses/rust`, with an index.
  The Rust runtime notices are included separately.

Build downloads are checksum-pinned in `packaging/macos/dependencies.json`.
No customer data, session tokens, host keys, or development caches are included
in the distributable. Read `docs/RELEASE.md` for the remaining release checks.
