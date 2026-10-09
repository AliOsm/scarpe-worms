#!/usr/bin/env python3
"""Cross-build a self-contained arm64 macOS test app on Linux, with independently verified engine patches.

Requires Python 3.12+, tar, Git and the pinned Rust toolchain. Downloads are
checksum-pinned in packaging/macos/dependencies.json. No Apple credentials are
used: this produces an ad-hoc signed, unnotarized ZIP, not an App Store release.
"""
from pathlib import Path
import hashlib
import io
import json
import os
import plistlib
import re
import shutil
import stat
import struct
import subprocess
import sys
import tarfile
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / 'packaging/macos'
CACHE = ROOT / '.cache/macos'
DIST = ROOT / 'dist'
APP = DIST / 'Burrow Brigade.app'
RES = APP / 'Contents/Resources'
TARGET = 'aarch64-apple-darwin'
RUST_VERSION = '1.99.0'
VERSION = re.search(r'^  VERSION = "([^"]+)"', (ROOT / 'lib/burrow.rb').read_text(), re.MULTILINE).group(1)


def run(*args, **kwargs):
    subprocess.run([str(arg) for arg in args], check=True, **kwargs)


def download(asset):
    path = CACHE / 'downloads' / asset['name']
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists():
        print('Downloading', path.name, flush=True)
        temporary = path.with_suffix(path.suffix + '.part')
        with urllib.request.urlopen(asset['url'], timeout=60) as source, temporary.open('wb') as out:
            shutil.copyfileobj(source, out)
        temporary.replace(path)
    with path.open('rb') as source:
        digest = 'sha256:' + hashlib.file_digest(source, 'sha256').hexdigest()
    if digest != asset['digest']:
        raise RuntimeError(f'Checksum mismatch: {path}')
    return path


def unpack(archive, directory):
    marker = directory / '.extracted'
    if marker.exists():
        return
    directory.mkdir(parents=True, exist_ok=True)
    # Python's data filter rejects paths/symlinks escaping the destination.
    with tarfile.open(archive) as source:
        source.extractall(directory, filter='data')
    marker.touch()


def copy_tree(source, destination, **options):
    shutil.copytree(source, destination, symlinks=True, dirs_exist_ok=True, **options)


def install_gem(archive, name):
    destination = RES / 'gems' / name
    destination.mkdir(parents=True)
    with tarfile.open(archive) as gem:
        compressed = gem.extractfile('data.tar.gz').read()
    with tarfile.open(fileobj=io.BytesIO(compressed), mode='r:gz') as data:
        data.extractall(destination, filter='data')
    # Keep source/license notices; discard native extensions for other Ruby ABIs.
    if name == 'ffi':
        for directory in (destination / 'lib').iterdir():
            if directory.is_dir() and re.fullmatch(r'\d+\.\d+', directory.name) and directory.name != '3.4':
                shutil.rmtree(directory)


def archive_app(path):
    # Some dependency archives use the Unix epoch; ZIP dates start in 1980.
    with zipfile.ZipFile(path, 'w', compression=zipfile.ZIP_DEFLATED,
                         compresslevel=6, strict_timestamps=False) as archive:
        for file in sorted(APP.rglob('*')):
            relative = file.relative_to(DIST).as_posix()
            if file.is_symlink():
                entry = zipfile.ZipInfo(relative)
                entry.create_system = 3
                entry.external_attr = (stat.S_IFLNK | 0o777) << 16
                archive.writestr(entry, os.readlink(file))
            elif file.is_file():
                archive.write(file, relative)
        archive.write(CONFIG / 'READ-ME.txt', 'READ-ME.txt')


def copy_rust_notices(cargo, scarpe, sysroot, env):
    metadata = json.loads(subprocess.check_output([
        str(cargo), 'metadata', '--locked', '--offline', '--format-version', '1',
        '--filter-platform', TARGET, '--manifest-path', str(scarpe / 'native/Cargo.toml'),
    ], env=env))
    resolved = {node['id'] for node in metadata['resolve']['nodes']}
    destination = RES / 'licenses/rust'
    destination.mkdir(parents=True)
    index = []
    for package in metadata['packages']:
        if package['id'] not in resolved or package['source'] is None:
            continue
        name = f"{package['name']}-{package['version']}"
        source = Path(package['manifest_path']).parent
        target = destination / name
        target.mkdir()
        notices = [path for path in source.iterdir() if path.name.lower().startswith(
            ('license', 'licence', 'copying', 'copyright', 'notice', 'authors'))]
        if package.get('license_file'):
            notices.append(source / package['license_file'])
        for path in notices:
            if path.is_dir():
                copy_tree(path, target / path.name)
            else:
                shutil.copy2(path, target / path.name)
        # Some published crates omit their repository's license text. Exact
        # revision notices for those crates are retained with the build source.
        extra = CONFIG / 'licenses/rust-extra' / name
        if extra.exists():
            copy_tree(extra, target)
        if not any(target.iterdir()):
            raise RuntimeError(f'Missing dependency license notice: {name}')
        index.append({key: package[key] for key in ('name', 'version', 'license', 'repository')})
    (destination / 'index.json').write_text(json.dumps(index, indent=2) + '\n')
    runtime = RES / 'licenses/rust-runtime'
    copy_tree(sysroot / 'share/doc/rust/licenses', runtime)
    shutil.copy2(sysroot / 'share/doc/rust/COPYRIGHT-library.html', runtime / 'COPYRIGHT-library.html')


def main():
    if sys.platform != 'linux':
        raise SystemExit('This cross-build recipe runs on Linux. The resulting app runs on Apple silicon Macs.')
    scarpe = ROOT / 'vendor/scarpe'
    pin = (ROOT / 'SCARPE_REVISION').read_text().strip()
    revision = subprocess.check_output(['git', '-C', str(scarpe), 'rev-parse', 'HEAD'], text=True).strip()
    run(sys.executable, ROOT / 'tools/verify_scarpe.py')
    assets = json.loads((CONFIG / 'dependencies.json').read_text())
    downloads = {item['name']: download(item) for item in assets}
    unpack(downloads['MacOSX26.1.sdk.tar.xz'], CACHE / 'sdk')
    unpack(downloads['traveling-ruby-20251122-3.4.7-macos-arm64-full.tar.gz'], CACHE / 'runtime')
    unpack(downloads['apple-codesign-0.29.0-x86_64-unknown-linux-musl.tar.gz'], CACHE / 'signing')

    rustup = Path(os.environ.get('BURROW_RUSTUP', str(Path.home() / '.cargo/bin/rustup')))
    run(rustup, 'target', 'add', '--toolchain', RUST_VERSION, TARGET)
    rustc = subprocess.check_output([str(rustup), 'which', '--toolchain', RUST_VERSION, 'rustc'], text=True).strip()
    cargo = subprocess.check_output([str(rustup), 'which', '--toolchain', RUST_VERSION, 'cargo'], text=True).strip()
    sysroot = Path(subprocess.check_output([rustc, '--print', 'sysroot'], text=True).strip())
    linker = sysroot / 'lib/rustlib/x86_64-unknown-linux-gnu/bin/rust-lld'
    env = os.environ | {
        'RUSTC': rustc, 'RUSTUP_TOOLCHAIN': RUST_VERSION,
        'LD_LIBRARY_PATH': str(sysroot / 'lib') + (':' + os.environ['LD_LIBRARY_PATH'] if os.environ.get('LD_LIBRARY_PATH') else ''),
        'SDKROOT': str(CACHE / 'sdk/MacOSX26.1.sdk'), 'MACOSX_DEPLOYMENT_TARGET': '13.0',
        'CARGO_TARGET_DIR': str(CACHE / 'target'),
        'CARGO_TARGET_AARCH64_APPLE_DARWIN_LINKER': str(linker),
        'CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS': '-C linker-flavor=ld64.lld',
    }
    print('Building pinned Scarpe for Apple silicon', flush=True)
    run(cargo, 'build', '--release', '--locked', '--target', TARGET,
        '--manifest-path', scarpe / 'native/Cargo.toml', env=env, cwd=ROOT)
    run(rustc, CONFIG / 'launcher.rs', '--edition=2021', '--target', TARGET,
        '-C', 'opt-level=s', '-C', 'strip=symbols', '-C', 'linker-flavor=ld64.lld',
        '-C', f'linker={linker}', '-o', CACHE / 'Burrow Brigade', env=env)

    # Only this known generated bundle is replaced; never copy databases, cached
    # accounts, credentials, dependency checkouts or the development worktree.
    if APP.exists():
        shutil.rmtree(APP)
    (APP / 'Contents/MacOS').mkdir(parents=True)
    (RES / 'app').mkdir(parents=True)
    shutil.copy2(CACHE / 'Burrow Brigade', APP / 'Contents/MacOS/Burrow Brigade')
    shutil.copy2(CACHE / 'target' / TARGET / 'release/scarpe-native', APP / 'Contents/MacOS/scarpe-native')
    shutil.copy2(ROOT / 'game.rb', RES / 'app/game.rb')
    for directory in ('lib',):
        copy_tree(ROOT / directory, RES / 'app' / directory)
    (RES / 'app/docs').mkdir()
    for document in (ROOT / 'docs').glob('*.md'):
        shutil.copy2(document, RES / 'app/docs' / document.name)
    copy_tree(ROOT / 'assets', RES / 'app/assets', ignore=shutil.ignore_patterns('source', '*.svg'))
    for name in ('LICENSE', 'THIRD_PARTY.md', 'SCARPE_REVISION', 'README.md'):
        shutil.copy2(ROOT / name, RES / 'app' / name)
    for name in ('boot.rb', 'launch.sh'):
        shutil.copy2(CONFIG / name, RES / name)
    shutil.copy2(CONFIG / 'dependencies.json', RES / 'build-dependencies.json')
    for directory in ('lib', 'lacci/lib', 'scarpe-components/lib'):
        copy_tree(scarpe / directory, RES / 'scarpe' / directory)
    for name in ('CHANGELOG.md', 'LICENSE.txt'):
        shutil.copy2(scarpe / name, RES / 'scarpe' / name)
    copy_tree(scarpe / 'docs/static', RES / 'scarpe/docs/static', ignore=shutil.ignore_patterns('stubs'))
    for name in ('wv', 'wv.rb', 'wv_local.rb', 'wv_relay.rb', 'assets.rb', 'package', 'package.rb'):
        path = RES / 'scarpe/lib/scarpe' / name
        if path.is_dir():
            shutil.rmtree(path)
        elif path.exists():
            path.unlink()

    runtime = CACHE / 'runtime'
    for directory in ('bin.real', 'lib'):
        copy_tree(runtime / directory, RES / 'runtime/ruby' / directory,
                  ignore=shutil.ignore_patterns('gems', '*.dSYM', '*.a'))
    (RES / 'runtime/gems').mkdir(parents=True)
    for name, version in [('ffi', '1.17.4-arm64-darwin'), ('chunky_png', '1.4.0'), ('base64', '0.3.0'), ('logger', '1.7.0'), ('fastimage', '2.4.1')]:
        install_gem(downloads[f'{name}-{version}.gem'], name)
    copy_tree(CONFIG / 'licenses', RES / 'licenses', ignore=shutil.ignore_patterns('rust-extra'))
    copy_rust_notices(cargo, scarpe, sysroot, env)
    copy_tree(scarpe / 'native/assets/fonts', RES / 'licenses/scarpe-fonts', ignore=shutil.ignore_patterns('*.ttf', '*.otf'))

    # Original artwork at every macOS icon resolution.
    chunks = []
    for kind, size in [('icp4', 16), ('icp5', 32), ('icp6', 64), ('ic07', 128), ('ic08', 256), ('ic09', 512), ('ic10', 1024)]:
        png = (ROOT / ('assets/art/app-icon.png' if size == 256 else f'assets/art/app-icon-{size}.png')).read_bytes()
        chunks.append(kind.encode() + struct.pack('>I', len(png) + 8) + png)
    chunk = b''.join(chunks)
    (RES / 'Burrow Brigade.icns').write_bytes(b'icns' + struct.pack('>I', len(chunk) + 8) + chunk)
    plist = {
        'CFBundleExecutable': 'Burrow Brigade', 'CFBundleIdentifier': 'com.burrowbrigade.game',
        'CFBundleName': 'Burrow Brigade', 'CFBundleDisplayName': 'Burrow Brigade',
        'CFBundleShortVersionString': VERSION, 'CFBundleVersion': '20261009.5',
        'CFBundlePackageType': 'APPL', 'CFBundleIconFile': 'Burrow Brigade.icns',
        'LSMinimumSystemVersion': '13.0', 'LSArchitecturePriority': ['arm64'],
        'NSHighResolutionCapable': True,
        'NSLocalNetworkUsageDescription': 'Connect to your friends’ matches and host a private Burrow Brigade game on your network.',
        'NSHumanReadableCopyright': 'Burrow Brigade contributors. MIT license.',
    }
    (APP / 'Contents/Info.plist').write_bytes(plistlib.dumps(plist))
    (APP / 'Contents/PkgInfo').write_bytes(b'APPL????')
    for path in (APP / 'Contents/MacOS').iterdir():
        path.chmod(0o755)
    (RES / 'launch.sh').chmod(0o755)
    signer = CACHE / 'signing/apple-codesign-0.29.0-x86_64-unknown-linux-musl/rcodesign'
    print('Ad-hoc signing the complete app', flush=True)
    run(signer, '-C', '/dev/null', 'sign', APP)
    run(sys.executable, ROOT / 'tools/verify_macos.py', APP,
        '--report', ROOT / 'docs/validation/macos-arm64-package.json')
    archive = DIST / f'Burrow-Brigade-{VERSION}-macos-arm64.zip'
    temporary = archive.with_suffix('.zip.part')
    archive_app(temporary)
    temporary.replace(archive)
    with archive.open('rb') as source:
        digest = hashlib.file_digest(source, 'sha256').hexdigest()
    archive.with_suffix('.zip.sha256').write_text(f'{digest}  {archive.name}\n')
    print(f'Created {archive} ({archive.stat().st_size / 1024**2:.1f} MiB)', flush=True)
    print('Mac binaries are cross-built; macOS launch testing remains required.', flush=True)


if __name__ == '__main__':
    main()
