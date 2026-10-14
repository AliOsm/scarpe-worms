#!/usr/bin/env python3
"""Build the self-contained Windows x64 ZIP and per-user Inno Setup installer.

Run with python -I on Windows after setup-windows.ps1, in an MSVC x64 shell.
All fetched payloads are SHA-256 pinned; build tools come from the runner.
"""
from pathlib import Path
import hashlib
import importlib.util
import json
import os
import platform
import re
import shutil
import struct
import subprocess
import sys
import tarfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / 'packaging/windows'
CACHE = ROOT / '.cache/windows'
DIST = ROOT / 'dist'
APP = CACHE / 'stage/Burrow Brigade'
RES = APP / 'resources'
TARGET = 'x86_64-pc-windows-msvc'
VERSION = re.search(r'^  VERSION = "([^"]+)"', (ROOT / 'lib/burrow.rb').read_text(), re.M).group(1)

# Reuse the existing checksum, gem and Rust-notice collection code. Import by
# exact repository path so python -I never searches the current directory.
spec = importlib.util.spec_from_file_location('macos_packaging', ROOT / 'tools/package_macos.py')
shared = importlib.util.module_from_spec(spec)
spec.loader.exec_module(shared)
shared.CACHE, shared.RES, shared.TARGET = CACHE, RES, TARGET
run, copy_tree = shared.run, shared.copy_tree


def fresh_directory(path):
    if path.exists():
        shutil.rmtree(path)
    path.mkdir(parents=True)


def extract_zip(archive, destination):
    """Only ordinary relative files; reject links, drives, traversal and ADS."""
    fresh_directory(destination)
    with zipfile.ZipFile(archive) as source:
        for entry in source.infolist():
            relative = Path(entry.filename.replace('\\', '/'))
            if relative.is_absolute() or '..' in relative.parts or ':' in entry.filename or (entry.external_attr >> 16) & 0o170000 == 0o120000:
                raise ValueError(f'Unsafe ZIP entry: {entry.filename}')
            target = destination / relative
            if entry.is_dir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with source.open(entry) as src, target.open('wb') as dst:
                    shutil.copyfileobj(src, dst)


def icon(path):
    # Windows accepts PNG images in ICO entries. Use the committed original art.
    images = [(size, (ROOT / f'assets/art/app-icon-{size}.png').read_bytes()) for size in (16, 32, 64, 128)]
    images.append((256, (ROOT / 'assets/art/app-icon.png').read_bytes()))
    directory, payload = bytearray(struct.pack('<HHH', 0, 1, len(images))), bytearray()
    offset = 6 + 16 * len(images)
    for size, png in images:
        directory.extend(struct.pack('<BBBBHHII', size % 256, size % 256, 0, 0, 1, 32, len(png), offset))
        payload.extend(png)
        offset += len(png)
    path.write_bytes(directory + payload)


def sha256(path):
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def prepare_audio():
    asset = next(item for item in json.loads((CONFIG / 'dependencies.json').read_text()) if item['name'].startswith('openal-'))
    archive = shared.download(asset)
    extracted = CACHE / 'openal-extracted'
    extract_zip(archive, extracted)
    directory = CACHE / 'audio'
    directory.mkdir(exist_ok=True)
    shutil.copy2(extracted / 'openal-soft-1.25.2-bin/bin/Win64/soft_oal.dll', directory / 'OpenAL32.dll')


def main():
    if sys.platform != 'win32' or platform.machine().lower() not in ('amd64', 'x86_64'):
        raise SystemExit('Build on Windows x64, in an MSVC x64 developer shell.')
    os.chdir(ROOT)
    run(sys.executable, '-I', ROOT / 'tools/verify_scarpe.py')
    downloads = {item['name']: shared.download(item) for item in json.loads((CONFIG / 'dependencies.json').read_text())}
    runtime = CACHE / 'runtime-extracted'
    fresh_directory(runtime)
    with tarfile.open(downloads['traveling-ruby-20251122-3.4.7-windows-x86_64.tar.gz']) as source:
        source.extractall(runtime, filter='data')
    openal = CACHE / 'openal-extracted'
    extract_zip(downloads['openal-soft-1.25.2-bin.zip'], openal)
    openal = openal / 'openal-soft-1.25.2-bin'

    fresh_directory(APP)
    (RES / 'ruby/bin.real').mkdir(parents=True)
    # Database/curl DLLs in Traveling Ruby are not used by this game. Keep only
    # Ruby's interpreter and dependencies; stdlib extension DLLs live in lib/.
    for name in ('rubyw.exe', 'x64-ucrt-ruby340.dll'):
        shutil.copy2(runtime / 'bin.real' / name, RES / 'ruby/bin.real' / name)
    copy_tree(runtime / 'bin.real/ruby_builtin_dlls', RES / 'ruby/bin.real/ruby_builtin_dlls')
    copy_tree(runtime / 'lib', RES / 'ruby/lib', ignore=shutil.ignore_patterns('*.a'))
    shutil.copy2(runtime / 'LICENSE.txt', RES / 'ruby/LICENSE.txt')
    (RES / 'empty-gems').mkdir()
    ruby = RES / 'ruby/bin.real/rubyw.exe'
    manifest = CACHE / 'ruby-original.manifest'
    run('mt.exe', '-nologo', f'-inputresource:{ruby};#1', f'-out:{manifest}')
    run('mt.exe', '-nologo', '-manifest', manifest, CONFIG / 'ruby.manifest', f'-outputresource:{ruby};#1')
    # Soft_oal is the actual mixer, not OpenAL's optional system router.
    shutil.copy2(openal / 'bin/Win64/soft_oal.dll', RES / 'ruby/bin.real/OpenAL32.dll')

    (RES / 'app').mkdir()
    shutil.copy2(ROOT / 'game.rb', RES / 'app/game.rb')
    copy_tree(ROOT / 'lib', RES / 'app/lib')
    copy_tree(ROOT / 'assets', RES / 'app/assets', ignore=shutil.ignore_patterns('source', '*.svg'))
    (RES / 'app/docs').mkdir()
    for document in (ROOT / 'docs').glob('*.md'):
        shutil.copy2(document, RES / 'app/docs' / document.name)
    for name in ('LICENSE', 'THIRD_PARTY.md', 'SCARPE_REVISION', 'README.md'):
        shutil.copy2(ROOT / name, RES / 'app' / name)
    shutil.copy2(CONFIG / 'boot.rb', RES / 'boot.rb')
    shutil.copy2(CONFIG / 'READ-ME.txt', APP / 'READ-ME.txt')
    shutil.copy2(CONFIG / 'dependencies.json', RES / 'build-dependencies.json')
    scarpe = ROOT / 'vendor/scarpe'
    for directory in ('lib', 'lacci/lib', 'scarpe-components/lib', 'docs/static'):
        copy_tree(scarpe / directory, RES / 'scarpe' / directory, ignore=shutil.ignore_patterns('stubs'))
    for name in ('CHANGELOG.md', 'LICENSE.txt'):
        shutil.copy2(scarpe / name, RES / 'scarpe' / name)
    for name in ('wv', 'wv.rb', 'wv_local.rb', 'wv_relay.rb', 'assets.rb', 'package', 'package.rb'):
        path = RES / 'scarpe/lib/scarpe' / name
        if path.is_dir():
            shutil.rmtree(path)
        elif path.exists():
            path.unlink()
    for name, version in [('ffi', '1.17.4-x64-mingw-ucrt'), ('chunky_png', '1.4.0'), ('base64', '0.3.0'), ('logger', '1.7.0'), ('fastimage', '2.4.1')]:
        shared.install_gem(downloads[f'{name}-{version}.gem'], name)

    copy_tree(CONFIG / 'licenses', RES / 'licenses', ignore=shutil.ignore_patterns('rust-extra'))
    common = ROOT / 'packaging/macos/licenses'
    for name in ('Ruby-COPYING', 'Ruby-BSDL', 'Ruby-LEGAL', 'Traveling-Ruby-LICENSE',
                 'OpenSSL-LICENSE', 'libffi-LICENSE', 'libyaml-LICENSE', 'GMP-LGPLv3', 'GMP-GPLv3'):
        shutil.copy2(common / name, RES / 'licenses' / name)
    (RES / 'licenses/openal-soft').mkdir()
    for name in ('COPYING', 'LICENSE-pffft'):
        shutil.copy2(openal / name, RES / 'licenses/openal-soft' / name)
    shutil.copy2(runtime / 'LICENSE.txt', RES / 'licenses/RubyInstaller-LICENSE.txt')
    cargo = subprocess.check_output(['rustup', 'which', 'cargo'], text=True).strip()
    sysroot = Path(subprocess.check_output(['rustc', '--print', 'sysroot'], text=True).strip())
    # The common collector includes notices omitted from some published crates.
    # Windows resolves additional accessibility/clipboard crates; merge their
    # revision-pinned notices with the existing cross-platform collection.
    notice_config = CACHE / 'notice-config'
    fresh_directory(notice_config)
    copy_tree(common / 'rust-extra', notice_config / 'licenses/rust-extra')
    copy_tree(CONFIG / 'licenses/rust-extra', notice_config / 'licenses/rust-extra')
    shared.CONFIG = notice_config
    shared.copy_rust_notices(cargo, scarpe, sysroot, os.environ.copy())
    copy_tree(scarpe / 'native/assets/fonts', RES / 'licenses/scarpe-fonts', ignore=shutil.ignore_patterns('*.ttf', '*.otf'))
    shutil.copy2(scarpe / 'native/Cargo.lock', RES / 'licenses/rust/Cargo.lock')
    copy_tree(ROOT / 'patches/scarpe', RES / 'licenses/scarpe-patches')

    shutil.copy2(scarpe / 'native/target/release/scarpe-native.exe', APP / 'scarpe-native.exe')
    icon(RES / 'Burrow Brigade.ico')
    resource = CACHE / 'launcher.res'
    rc = CACHE / 'launcher.rc'
    rc.write_text('1 ICON "' + str(RES / 'Burrow Brigade.ico').replace('\\', '/') + '"\n', encoding='utf-8')
    run('rc.exe', '/nologo', '/fo', resource, rc)
    linker = Path(os.environ['VCToolsInstallDir']) / 'bin/Hostx64/x64/link.exe'
    run('rustc', CONFIG / 'launcher.rs', '--edition=2021', '-O', '-C', 'target-feature=+crt-static',
        '-C', f'linker={linker}', '-C', f'link-arg={resource}', '-o', APP / 'Burrow Brigade.exe')
    build = {
        'version': VERSION, 'target': TARGET, 'ruby': '3.4.7',
        'revision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
        'scarpe_revision': (ROOT / 'SCARPE_REVISION').read_text().strip(),
        'rustc': subprocess.check_output(['rustc', '--version'], text=True).strip(),
        'runner_image': os.environ.get('ImageOS'), 'runner_image_version': os.environ.get('ImageVersion'),
        'platform': platform.platform(),
    }
    (RES / 'build.json').write_text(json.dumps(build, indent=2) + '\n', encoding='utf-8')
    manifest = {file.relative_to(APP).as_posix(): sha256(file) for file in sorted(APP.rglob('*')) if file.is_file()}
    (RES / 'files.sha256.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')

    DIST.mkdir(exist_ok=True)
    archive = DIST / f'Burrow-Brigade-{VERSION}-windows-x64.zip'
    with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED, compresslevel=6, strict_timestamps=False) as output:
        for path in sorted(APP.rglob('*')):
            if path.is_file():
                output.write(path, 'Burrow Brigade/' + path.relative_to(APP).as_posix())
    compiler = os.environ.get('ISCC', str(Path(os.environ['ProgramFiles(x86)']) / 'Inno Setup 6/ISCC.exe'))
    run(compiler, '/Qp', f'/DAppVersion={VERSION}', f'/DBundleDir={APP}', f'/DOutputPath={DIST}', CONFIG / 'installer.iss')
    assets = []
    for path in (archive, DIST / f'Burrow-Brigade-{VERSION}-windows-x64-setup.exe'):
        digest = sha256(path)
        Path(str(path) + '.sha256').write_text(f'{digest}  {path.name}\n', encoding='ascii')
        assets.append({'name': path.name, 'bytes': path.stat().st_size, 'sha256': digest})
    evidence = CACHE / 'evidence'
    evidence.mkdir(exist_ok=True)
    (evidence / 'build.json').write_text(json.dumps(build | {'assets': assets}, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(assets, indent=2), flush=True)


if __name__ == '__main__':
    if sys.argv[1:] == ['--prepare-audio']:
        prepare_audio()
    elif sys.argv[1:]:
        raise SystemExit('Usage: python -I tools/package_windows.py [--prepare-audio]')
    else:
        main()
