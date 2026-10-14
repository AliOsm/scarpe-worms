#!/usr/bin/env python3
"""Build the portable x86-64 Linux client (Python 3.12+, Ubuntu 22.04).

Run with python3 -I. Downloads and gems are SHA-256 pinned; Cargo uses its lock.
The ELF audit rejects a build requiring anything newer than glibc 2.35.
"""
from pathlib import Path
import hashlib
import io
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / 'packaging/linux'
CACHE = ROOT / '.cache/linux'
DIST = ROOT / 'dist'
APP = CACHE / 'bundle/Burrow Brigade'
RES = APP / 'resources'
TARGET = 'x86_64-unknown-linux-gnu'
OPENAL_FLAGS = [
    '-DCMAKE_BUILD_TYPE=Release', '-DALSOFT_UTILS=OFF', '-DALSOFT_EXAMPLES=OFF',
    '-DALSOFT_TESTS=OFF', '-DALSOFT_DLOPEN=ON', '-DALSOFT_REQUIRE_PIPEWIRE=ON',
    '-DALSOFT_REQUIRE_PULSEAUDIO=ON', '-DALSOFT_REQUIRE_ALSA=ON',
    '-DALSOFT_BACKEND_JACK=OFF', '-DALSOFT_BACKEND_OSS=OFF',
    '-DALSOFT_BACKEND_SNDIO=OFF', '-DALSOFT_UPDATE_BUILD_VERSION=OFF',
]


def run(*args, **kwargs):
    subprocess.run([str(arg) for arg in args], check=True, **kwargs)


def output(*args, **kwargs):
    return subprocess.check_output([str(arg) for arg in args], text=True, **kwargs).strip()


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
    if directory.exists():
        shutil.rmtree(directory)
    directory.mkdir(parents=True)
    with tarfile.open(archive) as source:
        source.extractall(directory, filter='data')


def copy_tree(source, destination, **options):
    shutil.copytree(source, destination, symlinks=True, dirs_exist_ok=True, **options)


def install_gem(archive, name):
    destination = RES / 'gems' / name
    destination.mkdir(parents=True)
    with tarfile.open(archive) as gem:
        compressed = gem.extractfile('data.tar.gz').read()
    with tarfile.open(fileobj=io.BytesIO(compressed), mode='r:gz') as data:
        data.extractall(destination, filter='data')
    if name == 'ffi':
        for directory in (destination / 'lib').iterdir():
            if directory.is_dir() and re.fullmatch(r'\d+\.\d+', directory.name) and directory.name != '3.4':
                shutil.rmtree(directory)


def rust_notices(scarpe, env):
    metadata = json.loads(output('cargo', 'metadata', '--locked', '--offline',
        '--format-version', '1', '--filter-platform', TARGET,
        '--manifest-path', scarpe / 'native/Cargo.toml', env=env))
    resolved = {node['id'] for node in metadata['resolve']['nodes']}
    destination = RES / 'licenses/rust'
    destination.mkdir(parents=True)
    index, missing = [], []
    for package in metadata['packages']:
        if package['id'] not in resolved or package['source'] is None:
            continue
        name = f"{package['name']}-{package['version']}"
        source = Path(package['manifest_path']).parent
        target = destination / name
        target.mkdir()
        notices = [p for p in source.iterdir() if p.name.lower().startswith(
            ('license', 'licence', 'copying', 'copyright', 'notice', 'authors'))]
        if package.get('license_file'):
            notices.append(source / package['license_file'])
        for path in notices:
            if path.is_dir():
                copy_tree(path, target / path.name)
            else:
                shutil.copy2(path, target / path.name)
        for extra in (ROOT / 'packaging/macos/licenses/rust-extra' / name,
                      CONFIG / 'licenses/rust-extra' / name):
            if extra.exists():
                copy_tree(extra, target)
        if not any(target.iterdir()):
            missing.append(name)
        index.append({key: package[key] for key in ('name', 'version', 'license', 'repository')})
    if missing:
        raise RuntimeError(f'Missing Rust notices: {missing}')
    (destination / 'index.json').write_text(json.dumps(index, indent=2) + '\n')
    sysroot = Path(output('rustc', '--print', 'sysroot', env=env))
    copy_tree(sysroot / 'share/doc/rust/licenses', RES / 'licenses/rust-runtime')
    shutil.copy2(sysroot / 'share/doc/rust/COPYRIGHT-library.html', RES / 'licenses/rust-runtime')


def audit_elf():
    """Check every delivered ELF, including Ruby extensions and OpenAL."""
    files = []
    allowed = {'libc.so.6', 'libm.so.6', 'libpthread.so.0', 'librt.so.1',
               'libdl.so.2', 'libcrypt.so.1', 'libgcc_s.so.1', 'libstdc++.so.6',
               'ld-linux-x86-64.so.2'}
    for path in sorted(APP.rglob('*')):
        if path.is_symlink():
            if not path.resolve().is_relative_to(APP) or not path.exists():
                raise RuntimeError(f'Escaping or broken link: {path}')
            continue
        if not path.is_file():
            continue
        with path.open('rb') as source:
            if source.read(4) != b'\x7fELF':
                continue
        header = output('readelf', '-h', path)
        if 'Advanced Micro Devices X86-64' not in header or 'ELF64' not in header:
            raise RuntimeError(f'Not an x86-64 ELF: {path}')
        dynamic = output('readelf', '-d', path)
        needed = sorted(set(re.findall(r'\(NEEDED\).*\[(.*?)\]', dynamic)))
        if set(needed) - allowed:
            raise RuntimeError(f'Undocumented linked libraries in {path}: {needed}')
        if re.search(r'\((?:RPATH|RUNPATH)\)', dynamic):
            raise RuntimeError(f'Unexpected embedded library search path: {path}')
        symbols = output('readelf', '--version-info', path)
        requirements = {}
        for family, maximum in [('GLIBC', (2, 35)), ('GLIBCXX', (3, 4, 30))]:
            versions = [tuple(map(int, s.split('.'))) for s in re.findall(rf'\b{family}_([0-9.]+)', symbols)]
            if versions:
                high = max(versions)
                if high > maximum:
                    raise RuntimeError(f'{path} requires {family}_{high}, newer than Ubuntu 22.04')
                requirements[family] = '.'.join(map(str, high))
        files.append({'path': path.relative_to(APP).as_posix(), 'needed': needed, **requirements})
    return files


def main():
    if sys.platform != 'linux' or platform.machine() != 'x86_64':
        raise SystemExit('Build on x86-64 Linux, using Ubuntu 22.04 for the release baseline.')
    if sys.version_info < (3, 12):
        raise SystemExit('Python 3.12+ is required for safe archive extraction.')
    version = re.search(r'^  VERSION = "([^"]+)"', (ROOT / 'lib/burrow.rb').read_text(), re.M).group(1)
    scarpe = ROOT / 'vendor/scarpe'
    pin = (ROOT / 'SCARPE_REVISION').read_text().strip()
    if not (scarpe / '.git').exists():
        scarpe.mkdir(parents=True, exist_ok=True)
        run('git', '-C', scarpe, 'init', '-q')
        run('git', '-C', scarpe, 'remote', 'add', 'origin', 'https://github.com/scarpe-team/scarpe.git')
        run('git', '-C', scarpe, 'fetch', '-q', '--depth=1', 'origin', pin)
        run('git', '-C', scarpe, 'checkout', '-q', '--detach', pin)
    run(sys.executable, '-I', ROOT / 'tools/verify_scarpe.py', '--apply')
    assets = json.loads((CONFIG / 'dependencies.json').read_text())
    downloads = {item['name']: download(item) for item in assets}
    unpack(downloads['traveling-ruby-20251122-3.4.7-linux-x86_64.tar.gz'], CACHE / 'runtime')
    unpack(downloads['openal-soft-1.24.3.tar.bz2'], CACHE / 'openal-source')
    # A fresh baseline build, never the developer's newer-glibc renderer.
    env = os.environ.copy()
    for key in ('RUSTFLAGS', 'CARGO_ENCODED_RUSTFLAGS', 'LD_LIBRARY_PATH'):
        env.pop(key, None)
    env['CARGO_TARGET_DIR'] = str(CACHE / 'target')
    run('cargo', 'build', '--release', '--locked', '--target', TARGET,
        '--manifest-path', scarpe / 'native/Cargo.toml', env=env, cwd=ROOT)
    source = CACHE / 'openal-source/openal-soft-1.24.3'
    run('cmake', '-S', source, '-B', CACHE / 'openal-build', *OPENAL_FLAGS, env=env)
    run('cmake', '--build', CACHE / 'openal-build', '--parallel', os.environ.get('CMAKE_BUILD_PARALLEL_LEVEL', '2'), env=env)

    if APP.exists():
        shutil.rmtree(APP)
    (RES / 'app').mkdir(parents=True)
    (APP / 'lib').mkdir()
    (RES / 'bin').mkdir()
    shutil.copy2(CACHE / 'target' / TARGET / 'release/scarpe-native', RES / 'bin/scarpe-native')
    run('strip', '--strip-unneeded', RES / 'bin/scarpe-native')
    shutil.copy2(CACHE / 'openal-build/libopenal.so.1.24.3', APP / 'lib/libopenal.so.1')
    run('strip', '--strip-unneeded', APP / 'lib/libopenal.so.1')
    shutil.copy2(ROOT / 'game.rb', RES / 'app')
    copy_tree(ROOT / 'lib', RES / 'app/lib')
    copy_tree(ROOT / 'assets', RES / 'app/assets', ignore=shutil.ignore_patterns('source', '*.svg'))
    (RES / 'app/docs').mkdir()
    for path in (ROOT / 'docs').glob('*.md'):
        shutil.copy2(path, RES / 'app/docs')
    for name in ('LICENSE', 'THIRD_PARTY.md', 'SCARPE_REVISION'):
        shutil.copy2(ROOT / name, RES / 'app')
    for directory in ('lib', 'lacci/lib', 'scarpe-components/lib', 'docs/static'):
        copy_tree(scarpe / directory, RES / 'scarpe' / directory, ignore=shutil.ignore_patterns('stubs'))
    for name in ('CHANGELOG.md', 'LICENSE.txt'):
        shutil.copy2(scarpe / name, RES / 'scarpe')
    for name in ('wv', 'wv.rb', 'wv_local.rb', 'wv_relay.rb', 'assets.rb', 'package', 'package.rb'):
        path = RES / 'scarpe/lib/scarpe' / name
        if path.is_dir():
            shutil.rmtree(path)
        elif path.exists():
            path.unlink()
    runtime = RES / 'runtime/ruby'
    (runtime / 'bin.real').mkdir(parents=True)
    shutil.copy2(CACHE / 'runtime/bin.real/ruby', runtime / 'bin.real/ruby')
    # The upstream executable retains /tmp/ruby/lib from its build prefix.
    # All shipped dependencies use our explicit bundle paths or system SONAMEs.
    run('patchelf', '--remove-rpath', runtime / 'bin.real/ruby')
    copy_tree(CACHE / 'runtime/lib/ruby', runtime / 'lib/ruby', ignore=shutil.ignore_patterns('gems', '*.a'))
    shutil.copy2(CACHE / 'runtime/lib/ca-bundle.crt', runtime / 'lib')
    (RES / 'runtime/gems').mkdir()
    for name, gem_version in [('ffi', '1.17.4-x86_64-linux-gnu'), ('chunky_png', '1.4.0'),
                              ('base64', '0.3.0'), ('logger', '1.7.0'), ('fastimage', '2.4.1')]:
        install_gem(downloads[f'{name}-{gem_version}.gem'], name)
    for name in ('boot.rb', 'check_runtime.rb', 'desktop.rb', 'smoke.rb'):
        shutil.copy2(CONFIG / name, RES)
    shutil.copy2(CONFIG / 'launch.sh', APP / 'burrow-brigade')
    (APP / 'burrow-brigade').chmod(0o755)
    shutil.copy2(CONFIG / 'burrow-brigade.desktop', APP)
    shutil.copy2(ROOT / 'assets/art/app-icon.png', APP / 'burrow-brigade.png')
    shutil.copy2(CONFIG / 'READ-ME.txt', APP)
    shutil.copy2(CONFIG / 'dependencies.json', RES / 'build-dependencies.json')
    copy_tree(CONFIG / 'licenses', RES / 'licenses', ignore=shutil.ignore_patterns('rust-extra'))
    rust_notices(scarpe, env)
    copy_tree(scarpe / 'native/assets/fonts', RES / 'licenses/scarpe-fonts', ignore=shutil.ignore_patterns('*.ttf', '*.otf'))
    openal_licenses = RES / 'licenses/openal-soft'
    openal_licenses.mkdir()
    for name in ('COPYING', 'LICENSE-pffft'):
        shutil.copy2(source / name, openal_licenses)
    shutil.copy2(source / 'fmt-11.1.1/LICENSE', openal_licenses / 'fmt-LICENSE')
    shutil.copy2(downloads['openal-soft-1.24.3.tar.bz2'], openal_licenses)
    (openal_licenses / 'build.txt').write_text('cmake -S openal-soft-1.24.3 -B build ' + ' '.join(OPENAL_FLAGS) + '\ncmake --build build --parallel 2\n')
    elf = audit_elf()
    build = {'version': version, 'revision': output('git', 'rev-parse', 'HEAD', cwd=ROOT),
             'platform': TARGET, 'ruby': '3.4.7', 'openal_soft': '1.24.3', 'scarpe': pin,
             'rust': output('rustc', '--version', env=env), 'build_os': platform.freedesktop_os_release(),
             'glibc_floor': '2.35', 'elf': elf}
    (RES / 'build.json').write_text(json.dumps(build, indent=2) + '\n')
    DIST.mkdir(exist_ok=True)
    archive = DIST / f'Burrow-Brigade-{version}-linux-x86_64.tar.gz'
    temporary = archive.with_suffix('.gz.part')
    with tarfile.open(temporary, 'w:gz', compresslevel=6) as tar:
        tar.add(APP, arcname=APP.name)
    temporary.replace(archive)
    with archive.open('rb') as source:
        digest = hashlib.file_digest(source, 'sha256').hexdigest()
    archive.with_suffix('.gz.sha256').write_text(f'{digest}  {archive.name}\n')
    print(json.dumps({'asset': archive.name, 'bytes': archive.stat().st_size, 'sha256': digest,
                      'elf_files': len(elf)}, indent=2), flush=True)


if __name__ == '__main__':
    main()
