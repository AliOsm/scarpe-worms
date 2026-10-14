# Windows client

Target: **Windows 10 1903 or newer and Windows 11, x64**. The package contains
Ruby 3.4.7, the patched native Scarpe renderer, Ruby libraries, fonts, art,
audio, and OpenAL Soft. Players need no Ruby, Rust, browser, or separate server.
Windows on ARM and 32-bit Windows are not validated targets.

## Install or run the portable ZIP

* `Burrow-Brigade-<version>-windows-x64-setup.exe` installs for the current user
  under `%LOCALAPPDATA%\Programs\Burrow Brigade`, adds a Start menu shortcut,
  offers an optional desktop shortcut, and registers an uninstaller.
* `Burrow-Brigade-<version>-windows-x64.zip` extracts a **Burrow Brigade** folder.
  Keep that folder together and run **Burrow Brigade.exe**. It may be moved,
  including to a path with spaces or Unicode characters.

Both assets have `.sha256` sidecars. In PowerShell, `Get-FileHash <file> -Algorithm
SHA256` should match the digest in the corresponding sidecar. These builds are
unsigned; SmartScreen can display an unknown-publisher warning. Only run a
download you trust. There is no automatic updater: quit and install the newer
setup.exe, or replace the extracted portable folder.

Both formats use the same player data location. Upgrading and uninstalling
preserve that data; the portable archive does not store saves beside the EXE.

| Data | Default location |
| --- | --- |
| Settings, saves, local hosts | `%LOCALAPPDATA%\burrow-brigade` |
| Launcher log, rotated at 5 MiB | `%LOCALAPPDATA%\Burrow Brigade\Logs\launcher.log` |
| Latest three timing sessions | `%LOCALAPPDATA%\Burrow Brigade\Logs\performance` |

`BURROW_DATA_DIR` and `BURROW_LOG_DIR` can override the two locations. To
transfer a save, quit the game and copy its entire data folder. Do not share
that folder publicly: it includes session identities and host keys. Timing
reports are local and bounded; nothing is uploaded automatically.

Choose **Quick battle** to play against two computer teams. **Host for friends**
uses TCP 4388 and may need a Windows Firewall rule and router port forwarding;
see [Hosting](HOSTING.md). The GUI owns no simulation: the bundled Ruby also
runs the host and terrain worker as separate processes. Closing the game
closes the host's input pipe so it checkpoints, then stops the terrain worker.

## Build from source

Install Git, RubyInstaller **3.4.7 x64 UCRT with Devkit**, Bundler **4.0.16**,
Python **3.13+**, rustup, Visual Studio 2022 C++ build tools with a Windows SDK,
and PowerShell 7. Rust **1.99.0** is selected by `rust-toolchain.toml`.
Open an **x64 Visual Studio developer PowerShell**, then:

```powershell
./setup-windows.ps1
./run-windows.ps1
bundle exec rake test
```

Setup fetches `SCARPE_REVISION`, verifies/applies the ordered exported patches,
installs the locked gems, compiles the MSVC renderer with a static C runtime,
and fetches the checksum-pinned OpenAL Soft DLL for source runs. It refuses
unexported Scarpe edits. Source runs use RubyInstaller; packaged runs use the
isolated runtime described below.

Install **Inno Setup 6** to package, then use the same developer shell:

```powershell
python -I tools/package_windows.py
```

The script uses `packaging/windows/dependencies.json` for pinned download URLs
and SHA-256 digests, extracts archives into separate generated directories,
and stages only application/runtime files under `.cache/windows/stage/`.
It creates the two assets and checksum sidecars in `dist/`. Set `ISCC` to an
explicit Inno Setup compiler path if it is not installed in the default location.

The small Rust GUI launcher finds resources relative to its own executable,
replaces inherited developer Ruby/Bundler settings, passes UTF-8 from startup,
and sets `BURROW_RUBY` for both workers. The bundled `rubyw.exe` uses the Windows
GUI subsystem and an embedded UTF-8 active-code-page manifest. This prevents
worker consoles from overriding the locale and corrupting Unicode script paths.
It is launched detached from any console, with stdout and stderr going to the
rotating launcher log. The renderer is a Windows GUI
binary. The game icon is embedded in the launcher and supplied to the native
window/taskbar. Launch failures are written to the log and shown in a dialog.

OpenAL Soft's Win64 mixer DLL is loaded dynamically as `OpenAL32.dll` beside
the interpreter (the launcher prepends that directory to the child `PATH`). The package includes its LGPL/PFFFT notices and source links,
plus Ruby, gem, compiler-runtime, font, and resolved Rust-crate notices under
`resources/licenses/`. Compatible replacement DLLs are permitted. No OpenAL
configuration utility, system router, or optional database runtime is shipped.

## Automated verification

`.github/workflows/package-windows.yml` builds on `windows-2022`. It supports
`workflow_call` with a required `ref`, manual dispatch, and pull requests that
touch the game or Windows packaging. The reusable job uploads
`burrow-brigade-windows`, containing exactly the two `dist/` assets and their
sidecars. Execution reports and screenshots use a separate evidence artifact.

The runner executes the core Ruby suite and renderer process regressions.
`python -I tools/check_windows.py` is restricted to a disposable GitHub runner:
it installs into a path with spaces and Unicode, launches the actual packaged
EXE with developer tools removed from `PATH`, reaches the menu, starts a bot
match, checks terrain, input, focus loss, arsenal and resize, presents a fired
shot, quits and resumes the same saved match/player. It checks default Windows
data/log locations, bounded diagnostics, child-process termination, installer
registration/shortcuts, upgrade cleanup, uninstall, preserved saves, and a
separately extracted portable ZIP.

The Windows Server 2022 runner is evidence for those binaries and functional
paths. It is not a physical Windows 10/11 desktop, GPU/display, or audio-device
acceptance test. Audio verification uses OpenAL Soft's null output driver.
Shared-runner frame budgets are diagnostic data, not release gates. Physical
device sound, display scaling, sleep/wake, SmartScreen reputation and human
playtesting remain acceptance work.

See [the Windows release evidence](validation/release-windows.json) for the
actual revisions, runner image versions, asset sizes, run URLs and results.
