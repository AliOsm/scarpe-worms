#!/usr/bin/env python3
"""Static arm64 bundle verification; this is not a substitute for a Mac launch."""
from pathlib import Path
import argparse
import hashlib
import json
import plistlib
import struct

ARM64 = 0x0100000C


def macho(path):
    data = path.read_bytes()
    if data[:4] == b'\x7fELF':
        raise ValueError(f'Linux executable leaked into app: {path}')
    if data[:4] != b'\xcf\xfa\xed\xfe':
        if data[:4] in (b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca'):
            raise ValueError(f'Unexpected universal binary: {path}')
        return None
    _, cpu, _, _, count, _, _, _ = struct.unpack_from('<8I', data)
    if cpu != ARM64:
        raise ValueError(f'Wrong architecture: {path}')
    offset, minimum, signature, libraries, rpaths = 32, 0, None, [], []
    for _ in range(count):
        command, size = struct.unpack_from('<2I', data, offset)
        if size < 8 or offset + size > len(data):
            raise ValueError(f'Invalid Mach-O load command: {path}')
        if command in (0xC, 0x80000018, 0x8000001F, 0x80000023, 0x8000001C):
            string_offset = struct.unpack_from('<I', data, offset + 8)[0]
            text = data[offset + string_offset:offset + size].split(b'\0')[0].decode()
            (rpaths if command == 0x8000001C else libraries).append(text)
        elif command == 0x32:
            platform, minimum = struct.unpack_from('<2I', data, offset + 8)
            if platform != 1:
                raise ValueError(f'Non-macOS binary: {path}')
        elif command == 0x24:
            minimum = struct.unpack_from('<I', data, offset + 8)[0]
        elif command == 0x1D:
            signature = struct.unpack_from('<2I', data, offset + 8)
        offset += size
    return {'minimum': minimum, 'signature': signature, 'libraries': libraries, 'rpaths': rpaths}


def check_signature(path, record, info_plist=None, resource_seal=None):
    """Check ad-hoc CodeDirectory page/special-slot hashes, without trusting CMS.

    rcodesign 0.29's verify rejects empty CMS on its own ad-hoc signatures. An
    ad-hoc signature intentionally has no certificate/CMS signer. This checks
    integrity only; it makes no Gatekeeper, notarization or identity claim.
    """
    data = path.read_bytes()
    start, size = record['signature']
    signature = data[start:start + size]
    magic, length, count = struct.unpack_from('>3I', signature)
    assert magic == 0xFADE0CC0 and length <= size, f'Invalid signature container: {path}'
    blobs = {}
    for index in range(count):
        kind, offset = struct.unpack_from('>2I', signature, 12 + index * 8)
        blob_length = struct.unpack_from('>I', signature, offset + 4)[0]
        blobs[kind] = signature[offset:offset + blob_length]
    directories = [value for kind, value in blobs.items() if kind == 0 or 0x1000 <= kind <= 0x1005]
    assert directories, f'Missing CodeDirectory: {path}'
    for directory in directories:
        magic, length, version, flags, hashes, _, special, pages, limit = struct.unpack_from('>9I', directory)
        hash_size, algorithm, _, page_shift = struct.unpack_from('4B', directory, 36)
        assert magic == 0xFADE0C02 and flags & 2, f'Expected ad-hoc CodeDirectory: {path}'
        assert algorithm in (1, 2), f'Unsupported digest: {path}'
        if version >= 0x20300 and limit == 0xFFFFFFFF:
            limit = struct.unpack_from('>Q', directory, 56)[0]
        page_size = 1 << page_shift
        digest = hashlib.sha1 if algorithm == 1 else hashlib.sha256
        assert limit <= start and pages == (limit + page_size - 1) // page_size
        for index in range(pages):
            expected = directory[hashes + index * hash_size:hashes + (index + 1) * hash_size]
            page = data[index * page_size:min((index + 1) * page_size, limit)]
            assert digest(page).digest() == expected, f'Invalid signed code page: {path}: {index}'
        external = {1: info_plist, 3: resource_seal}
        for slot in range(1, special + 1):
            expected = directory[hashes - slot * hash_size:hashes - (slot - 1) * hash_size]
            if expected == bytes(hash_size):
                continue
            value = external.get(slot) if slot in external else blobs.get(slot)
            assert value is not None and digest(value).digest() == expected, f'Invalid signature slot: {path}: {slot}'


def validate(app):
    app = app.resolve()
    resources = app / 'Contents/Resources'
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    assert info['LSArchitecturePriority'] == ['arm64']
    assert info['LSMinimumSystemVersion'] == '13.0'
    required = ['boot.rb', 'launch.sh', 'app/game.rb', 'app/lib/burrow/server/reactor.rb',
                'app/assets/art/manifest.json', 'app/assets/art/menu-bg.png',
                'app/assets/fonts/InterVariable.ttf', 'app/assets/fonts/Fredoka.ttf',
                'gems/ffi/lib/3.4/ffi_c.bundle', 'gems/chunky_png/lib/chunky_png.rb',
                'app/assets/art/grubs/0-walk-0.png', 'app/assets/art/weapons/rocket.png',
                'app/assets/audio/explosion.wav', 'app/assets/audio/music.wav',
                'runtime/ruby/bin.real/ruby', 'runtime/ruby/lib/ca-bundle.crt']
    for name in required:
        assert (resources / name).is_file(), f'Missing runtime file: {name}'
    binaries = []
    for path in sorted(app.rglob('*')):
        if path.is_symlink():
            assert path.resolve().is_relative_to(app) and path.exists(), f'Invalid bundle symlink: {path}'
            continue
        if not path.is_file():
            continue
        assert path.name not in ('server.json', 'preferences.json', 'server.lock'), f'Player state in bundle: {path}'
        if path.suffix == '.pem':
            assert b'PRIVATE KEY' not in path.read_bytes(), f'Private key in bundle: {path}'
        record = macho(path)
        if record is None:
            continue
        assert record['signature'], f'Unsigned binary: {path}'
        assert record['minimum'] <= 0x000D0000, f'Requires newer than macOS 13: {path}'
        executable_directory = (app / 'Contents/MacOS' if path.parent == app / 'Contents/MacOS'
                                else resources / 'runtime/ruby/bin.real')

        def expand_loader_path(value):
            for token, base in [('@loader_path', path.parent), ('@executable_path', executable_directory)]:
                if value == token or value.startswith(token + '/'):
                    return base / value.removeprefix(token).lstrip('/')
            return None

        for library in record['libraries']:
            if library.startswith(('/usr/lib/', '/System/Library/')):
                continue
            candidates = []
            resolved = expand_loader_path(library)
            if resolved is not None:
                candidates.append(resolved)
            elif library.startswith('@rpath/'):
                for rpath in record['rpaths']:
                    resolved = expand_loader_path(rpath)
                    if resolved is not None:
                        candidates.append(resolved / library.removeprefix('@rpath/'))
            assert any(p.exists() and p.resolve().is_relative_to(app) for p in candidates), f'Unresolved library: {path}: {library}'
        is_main = path == app / 'Contents/MacOS' / info['CFBundleExecutable']
        check_signature(path, record,
                        (app / 'Contents/Info.plist').read_bytes() if is_main else None,
                        (app / 'Contents/_CodeSignature/CodeResources').read_bytes() if is_main else None)
        binaries.append(str(path.relative_to(app)))

    # Independently check the resource seal's file hashes. Apple platform trust
    # and Gatekeeper policy still require a Mac test.
    seal = plistlib.loads((app / 'Contents/_CodeSignature/CodeResources').read_bytes())
    hashes = 0
    for relative, entry in seal.get('files2', {}).items():
        target = app / 'Contents' / relative
        if isinstance(entry, bytes):
            assert hashlib.sha1(target.read_bytes()).digest() == entry
            hashes += 1
        elif isinstance(entry, dict):
            if 'symlink' in entry:
                assert target.is_symlink() and str(target.readlink()) == entry['symlink']
            for name, algorithm in [('hash', hashlib.sha1), ('hash2', hashlib.sha256)]:
                if name in entry:
                    assert algorithm(target.read_bytes()).digest() == entry[name], f'Broken resource seal: {relative}'
                    hashes += 1
    assert hashes > 100, 'Missing resource seals'
    report = {'architecture': 'arm64', 'minimum_macos': '13.0', 'macho_binaries': len(binaries),
              'resource_hashes_checked': hashes, 'adhoc_code_hashes_verified': True,
              'macos_launch_tested': False, 'notarized': False, 'binaries': binaries}
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    report = validate(args.app)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({key: value for key, value in report.items() if key != 'binaries'}, indent=2))
