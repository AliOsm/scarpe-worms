#!/usr/bin/env python3
"""Check that the macOS ZIP contains the current source, assets, and signed app."""
from pathlib import Path
import hashlib
import json
import os
import plistlib
import stat
import zipfile

from package_macos import ROOT, APP, DIST, RES, VERSION


def digest(path):
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def main():
    expected = [ROOT / name for name in ('game.rb', 'LICENSE', 'THIRD_PARTY.md', 'SCARPE_REVISION', 'README.md')]
    expected += list((ROOT / 'docs').glob('*.md'))
    for name in ('lib', 'assets'):
        expected += [p for p in (ROOT / name).rglob('*') if p.is_file() and p.suffix != '.svg' and 'source' not in p.parts]
    for source in expected:
        target = RES / 'app' / source.relative_to(ROOT)
        assert target.is_file() and digest(source) == digest(target), f'Stale or absent packaged file: {source.relative_to(ROOT)}'
    for name in ('boot.rb', 'launch.sh'):
        assert digest(ROOT / 'packaging/macos' / name) == digest(RES / name), f'Stale packaged launcher: {name}'
    info = plistlib.loads((APP / 'Contents/Info.plist').read_bytes())
    assert info['CFBundleShortVersionString'] == VERSION, 'App version differs from game source'
    runtime_files = 0
    for target in (RES / 'scarpe').rglob('*'):
        if target.is_file():
            source = ROOT / 'vendor/scarpe' / target.relative_to(RES / 'scarpe')
            assert source.is_file() and digest(source) == digest(target), f'Stale Scarpe runtime file: {target}'
            runtime_files += 1
    archive = DIST / f'Burrow-Brigade-{VERSION}-macos-arm64.zip'
    sha256 = digest(archive)
    assert archive.with_suffix('.zip.sha256').read_text().split()[0] == sha256, 'ZIP checksum differs from sidecar'
    with zipfile.ZipFile(archive) as zipped:
        assert zipped.testzip() is None, 'ZIP CRC failure'
        inventory = {}
        for path in APP.rglob('*'):
            if path.is_file() or path.is_symlink():
                inventory[path.relative_to(DIST).as_posix()] = path
        inventory['READ-ME.txt'] = ROOT / 'packaging/macos/READ-ME.txt'
        assert set(zipped.namelist()) == set(inventory), 'ZIP inventory differs from app'
        for name, path in inventory.items():
            info = zipped.getinfo(name)
            assert zipped.read(name) == (os.readlink(path).encode() if path.is_symlink() else path.read_bytes()), f'ZIP differs: {name}'
            mode = info.external_attr >> 16
            assert stat.S_ISLNK(mode) == path.is_symlink(), f'Symlink flag differs: {name}'
            if not path.is_symlink() and os.access(path, os.X_OK):
                assert mode & 0o111, f'Executable bit missing: {name}'
    report = dict(version=VERSION, current_launcher_files=2,
                  current_game_source_and_asset_files=len(expected), current_scarpe_runtime_files=runtime_files,
                  zip_entries_matched=len(inventory), zip_crc=True, zip_executable_permissions=True,
                  symlinks_preserved=True, sha256=sha256, zip_bytes=archive.stat().st_size)
    (ROOT / 'docs/validation/distributable.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
