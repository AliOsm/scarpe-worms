#!/usr/bin/env python3
"""Build the pinned, relocatable Ruby 4 runtime for Linux and Apple silicon.

Supporting libraries are linked statically, so the client needs no developer
Ruby, Homebrew installation, or matching system OpenSSL/libffi ABI.
"""
from pathlib import Path
import hashlib
import json
import os
import platform
import shutil
import subprocess
import sys
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / 'packaging/ruby/dependencies.json'
VERSION = '4.0.7'
ABI = '4.0.0'


def run(*args, **kwargs):
    subprocess.run([str(arg) for arg in args], check=True, **kwargs)


def build(cache):
    cache = Path(cache).resolve()
    fingerprint = hashlib.sha256(CONFIG.read_bytes() + Path(__file__).read_bytes()
                                 + platform.platform().encode()).hexdigest()
    prefix = cache / 'install'
    marker = prefix / '.build-id'
    if marker.exists() and marker.read_text() == fingerprint:
        return prefix
    cache.mkdir(parents=True, exist_ok=True)
    downloads = cache.parent / 'downloads'
    downloads.mkdir(exist_ok=True)
    sources = cache / 'sources'
    for directory in (sources, prefix, cache / 'deps'):
        if directory.exists():
            shutil.rmtree(directory)
        directory.mkdir(parents=True)
    assets = json.loads(CONFIG.read_text())
    for asset in assets:
        path = downloads / asset['name']
        if not path.exists():
            temporary = path.with_suffix(path.suffix + '.part')
            with urllib.request.urlopen(asset['url'], timeout=120) as source, temporary.open('wb') as out:
                shutil.copyfileobj(source, out)
            temporary.replace(path)
        if 'sha256:' + hashlib.sha256(path.read_bytes()).hexdigest() != asset['digest']:
            raise RuntimeError(f'Checksum mismatch: {path}')
        if tarfile.is_tarfile(path):
            with tarfile.open(path) as archive:
                archive.extractall(sources, filter='data')
    deps = cache / 'deps'
    env = os.environ.copy()
    for key in ('RUBYOPT', 'RUBYLIB', 'GEM_HOME', 'GEM_PATH', 'BUNDLE_GEMFILE', 'BUNDLE_PATH',
                'BUNDLE_BIN_PATH', 'LD_LIBRARY_PATH', 'DYLD_LIBRARY_PATH', 'LIBRARY_PATH',
                'CPATH', 'CFLAGS', 'CXXFLAGS', 'CPPFLAGS', 'LDFLAGS', 'RUSTFLAGS'):
        env.pop(key, None)
    env.update(CFLAGS='-O2 -fPIC', CPPFLAGS=f'-I{deps}/include',
               LDFLAGS=f'-L{deps}/lib', PKG_CONFIG_PATH=str(deps / 'lib/pkgconfig'),
               PKG_CONFIG_LIBDIR=str(deps / 'lib/pkgconfig'))
    if sys.platform == 'darwin':
        env['MACOSX_DEPLOYMENT_TARGET'] = '13.0'
    jobs = os.environ.get('BURROW_BUILD_JOBS', str(min(os.cpu_count() or 2, 8)))

    def make(source, *configure):
        print(f'Building {source.name}', flush=True)
        run(*configure, cwd=source, env=env)
        run('make', f'-j{jobs}', cwd=source, env=env)
        run('make', 'install', cwd=source, env=env)

    make(sources / 'zlib-1.3.2', './configure', f'--prefix={deps}', '--static')
    make(sources / 'yaml-0.2.5', './configure', f'--prefix={deps}',
         '--disable-shared', '--enable-static')
    make(sources / 'libffi-3.8.0', './configure', f'--prefix={deps}', '--libdir=' + str(deps / 'lib'),
         '--disable-shared', '--enable-static', '--disable-docs')
    openssl = sources / 'openssl-3.5.9'
    run('./Configure', 'darwin64-arm64-cc' if sys.platform == 'darwin' else 'linux-x86_64',
        f'--prefix={deps}', f'--openssldir={deps}/ssl', '--libdir=lib',
        'no-shared', 'no-tests', 'no-module', '-fPIC', cwd=openssl, env=env)
    run('make', f'-j{jobs}', cwd=openssl, env=env)
    run('make', 'install_sw', cwd=openssl, env=env)
    ruby = sources / f'ruby-{VERSION}'
    make(ruby, './configure', f'--prefix={prefix}', '--enable-load-relative',
         '--disable-shared', '--disable-rpath', '--disable-install-doc', '--disable-yjit', '--without-gmp',
         '--with-out-ext=dbm,gdbm,readline', f'--with-openssl-dir={deps}',
         f'--with-libyaml-dir={deps}', f'--with-zlib-dir={deps}', f'--with-libffi-dir={deps}')
    # Fiddle moved out of the standard library in Ruby 4. Keep its bundled gem
    # and native extension. Other application gems are pinned by each packager.
    gems = prefix / f'lib/ruby/gems/{ABI}'
    for category in ('gems', 'specifications', 'cache', 'build_info'):
        for path in (gems / category).glob('*'):
            if path.name == 'default' or path.name.startswith('fiddle-'):
                continue
            if path.is_dir():
                shutil.rmtree(path)
            else:
                path.unlink()
    for path in (gems / 'extensions').glob('*/*/*'):
        if not path.name.startswith('fiddle-'):
            shutil.rmtree(path)
    for path in (prefix / 'bin').iterdir():
        if path.name != 'ruby':
            path.unlink()
    for directory in ('include', 'share'):
        shutil.rmtree(prefix / directory, ignore_errors=True)
    for path in prefix.rglob('*.a'):
        path.unlink()
    shutil.copy2(downloads / 'cacert.pem', prefix / 'lib/ca-bundle.crt')
    notices = prefix / 'notices'
    notices.mkdir()
    for source, name in [(ruby / 'COPYING', 'Ruby-COPYING'), (ruby / 'BSDL', 'Ruby-BSDL'),
                         (ruby / 'LEGAL', 'Ruby-LEGAL'), (openssl / 'LICENSE.txt', 'OpenSSL-LICENSE'),
                         (sources / 'libffi-3.8.0/LICENSE', 'libffi-LICENSE'),
                         (sources / 'yaml-0.2.5/License', 'libyaml-LICENSE'),
                         (sources / 'zlib-1.3.2/LICENSE', 'zlib-LICENSE')]:
        shutil.copy2(source, notices / name)
    shutil.copy2(CONFIG, notices / 'sources.json')
    run(prefix / 'bin/ruby', '-rfiddle', '-ropenssl', '-rpsych', '-rzlib', '-rjson', '-e',
        'abort RUBY_DESCRIPTION unless RUBY_VERSION == "4.0.7"; '
        'puts [RUBY_DESCRIPTION, OpenSSL::OPENSSL_VERSION, Fiddle::VERSION]', env=env)
    marker.write_text(fingerprint)
    return prefix


if __name__ == '__main__':
    print(build(sys.argv[1] if len(sys.argv) > 1 else ROOT / '.cache/ruby4/build'))
