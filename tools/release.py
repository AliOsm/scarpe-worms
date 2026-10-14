#!/usr/bin/env python3
"""Validate, assemble and publish verified release assets. Run with python3 -I."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def run(*args):
    return subprocess.check_output(args, cwd=ROOT, text=True).strip()


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def metadata(tag, draft, sha=None):
    require(re.fullmatch(r'(v\d+\.\d+\.\d+|test-rel-\d+\.\d+\.\d+-[a-z0-9-]+)', tag),
            'Use v<version> or test-rel-<version>-<name>.')
    commit = run('git', 'rev-parse', '--verify', f'refs/tags/{tag}^{{commit}}')
    require(sha is None or commit == sha, 'The release tag moved after validation.')
    source = run('git', 'show', f'{commit}:lib/burrow.rb')
    version = re.search(r'^  VERSION = "(\d+\.\d+\.\d+)"$', source, re.M).group(1)
    protocol = int(re.search(r'^  PROTOCOL = (\d+)$', source, re.M).group(1))
    if tag.startswith('test-rel-'):
        require(draft and tag.startswith(f'test-rel-{version}-'),
                'Test tags must match Burrow::VERSION and must remain drafts.')
    else:
        require(tag == f'v{version}', f'Tag {tag} does not match Burrow::VERSION {version}.')
    repository = os.environ.get('GITHUB_REPOSITORY', 'AliOsm/scarpe-worms')
    require(re.fullmatch(r'[\w.-]+/[\w.-]+', repository), 'Invalid GitHub repository.')
    return dict(tag=tag, version=version, protocol=protocol, sha=commit, draft=draft,
                repository=repository, image=f'ghcr.io/{repository.split("/")[0].lower()}/burrow-brigade:{version}')


def remote_tag(meta):
    ref = f'refs/tags/{meta["tag"]}'
    lines = run('git', 'ls-remote', '--tags', 'origin', ref, ref + '^{}').splitlines()
    refs = {name: sha for sha, name in (line.split() for line in lines)}
    require(refs.get(ref + '^{}', refs.get(ref)) == meta['sha'],
            'The remote tag is missing or moved; refusing to publish different source.')


def write_checksum(path):
    path.with_name(path.name + '.sha256').write_text(f'{digest(path)}  {path.name}\n')


def package_names(version):
    prefix = f'Burrow-Brigade-{version}'
    return {
        'macos': {f'{prefix}-macos-arm64.zip'},
        'windows': {f'{prefix}-windows-x64-setup.exe', f'{prefix}-windows-x64.zip'},
        'linux': {f'{prefix}-linux-x86_64.AppImage', f'{prefix}-linux-x86_64.tar.gz'},
        'server-amd64': {f'Burrow-Brigade-server-{version}-docker-linux-amd64.tar.gz'},
        'server-arm64': {f'Burrow-Brigade-server-{version}-docker-linux-arm64.tar.gz'},
    }


def check_pair(path):
    require(path.is_file() and not path.is_symlink() and path.stat().st_size > 0,
            f'Missing, empty or symlink asset: {path}')
    sidecar = path.with_name(path.name + '.sha256')
    require(sidecar.is_file() and not sidecar.is_symlink(), f'Missing checksum: {path.name}')
    require(sidecar.read_text().strip() == f'{digest(path)}  {path.name}',
            f'Checksum or sidecar filename mismatch: {path.name}')


def release_notes(meta, assets):
    version, tag, repo = meta['version'], meta['tag'], meta['repository']
    base = f'https://github.com/{repo}/releases/download/{tag}'
    prefix = f'Burrow-Brigade-{version}'

    def link(name, label):
        return f'[{label}]({base}/{name})'

    linux = ' / '.join(link(name, 'AppImage' if name.endswith('.AppImage') else 'portable tar.gz')
                       for name in sorted(package_names(version)['linux'] & set(assets)))
    linux_extra = (' For an AppImage, run `chmod +x` first; FUSE 2 is needed for mounting, or use '
                   '`--appimage-extract-and-run` where supported.'
                   if any(name.endswith('.AppImage') for name in assets) else '')
    notes = f'''Burrow Brigade {version} · protocol {meta['protocol']}

| Platform | Download |
| --- | --- |
| macOS 13+, Apple silicon | {link(prefix + '-macos-arm64.zip', 'ZIP app')} |
| Windows x64 | {link(prefix + '-windows-x64-setup.exe', 'Installer')} / {link(prefix + '-windows-x64.zip', 'portable ZIP')} |
| Linux x86-64 | {linux} |
| Linux server x86-64 | {link('Burrow-Brigade-server-' + version + '-docker-linux-amd64.tar.gz', 'Docker image archive')} |
| Linux server ARM64 | {link('Burrow-Brigade-server-' + version + '-docker-linux-arm64.tar.gz', 'Docker image archive')} |

### First launch

- **macOS:** extract the ZIP and move `Burrow Brigade.app` to Applications. This is an ad-hoc signed, unnotarized app. If Gatekeeper blocks a download you trust, use Privacy & Security → Open Anyway, or run `xattr -dr com.apple.quarantine "/Applications/Burrow Brigade.app"` after checking its SHA-256.
- **Windows:** run the installer, or extract the portable ZIP before launching. The unsigned app may show SmartScreen's “Windows protected your PC”; use More info → Run anyway only for a verified download you trust.
- **Linux:** use a graphical x86-64 desktop with glibc 2.35+ (Ubuntu 22.04+, Debian 12+, Fedora 40+), `libcrypt.so.1`, libstdc++, and X11/Wayland desktop libraries. For sound, provide PulseAudio/PipeWire or ALSA. Extract the tar.gz, enter `Burrow Brigade`, and run `./burrow-brigade`; `./burrow-brigade --check` diagnoses missing libraries. See [the Linux guide](https://github.com/{repo}/blob/{tag}/docs/LINUX.md) for distro package names.{linux_extra} No system Ruby or Rust installation is needed.
- Saves and settings are outside the installation. Quit an older copy before upgrading. Clients and hosts must use protocol {meta['protocol']}.

### Host a persistent server

Download the Docker archive for your **server's** architecture, then load it:

```sh
docker load --input Burrow-Brigade-server-{version}-docker-linux-amd64.tar.gz
docker run -d --name burrow-brigade --restart unless-stopped \\
  -p 4388:4388 -v burrow-data:/var/lib/burrow \\
  --read-only --tmpfs /tmp:size=16m,mode=1777 --cap-drop=ALL \\
  --security-opt=no-new-privileges:true --stop-timeout 20 \\
  {meta['image']}
docker logs burrow-brigade
```

Alternatively, download {link('compose.yaml', 'compose.yaml')} into its own directory and run `docker compose up -d`. Loading the archive first also works offline; Compose uses the local versioned image. The independent deployment workflow publishes the same version to GHCR, so `docker pull {meta['image']}` is another option after that workflow succeeds. Release archives do not depend on registry publication.

Open **4388/TCP** in the firewall and share `tls://YOUR-HOST:4388` with the SHA-256 certificate fingerprint from the container log. Compare the fingerprint through a trusted channel before connecting. The named volume preserves saves, sessions and TLS identity; back it up before upgrades. [Hosting guide](https://github.com/{repo}/blob/{tag}/docs/HOSTING.md).

### Verify downloads

Every asset has a `.sha256` sidecar; {link('SHA256SUMS', 'SHA256SUMS')} covers all packages, Compose and provenance. With all assets downloaded, run `sha256sum -c SHA256SUMS` (macOS: `shasum -a 256 -c SHA256SUMS`). For one download, check its sidecar with the same command. Windows: `Get-FileHash .\\FILE -Algorithm SHA256` and compare with `FILE.sha256`. Checksums establish integrity, not a developer signature.

{link('release.json', 'Build provenance')} records the source commit, workflow run, sizes and hashes. Required native package and server smoke checks passed before upload; shared-runner timing benchmarks are informational. These builds do not establish physical-device audio, display performance, notarization or human playtest acceptance.

### Changes

'''
    custom = subprocess.run(['git', 'show', f'{meta["sha"]}:docs/releases/{version}.md'],
                            cwd=ROOT, capture_output=True, text=True)
    if custom.returncode == 0 and custom.stdout.strip():
        return notes + custom.stdout.strip() + '\n'
    tags = run('git', 'tag', '--merged', meta['sha'], '--sort=-version:refname').splitlines()
    previous = next((name for name in tags if re.fullmatch(r'v\d+\.\d+\.\d+', name)
                     and name != tag and run('git', 'rev-parse', f'{name}^{{commit}}') != meta['sha']), None)
    revision_range = f'{previous}..{meta["sha"]}' if previous else meta['sha']
    changes = run('git', 'log', '--no-merges', '--format=- %s (%h)', revision_range)
    if previous:
        notes += f'[All changes since {previous}](https://github.com/{repo}/compare/{previous}...{tag})\n\n'
    return notes + (changes or '- No source changes since the previous release.') + '\n'


def assemble(meta, artifacts, output, notes):
    groups = package_names(meta['version'])
    require({p.name for p in artifacts.iterdir()} == {f'burrow-brigade-{g}' for g in groups},
            'Expected exactly the macOS, Windows, Linux and two server artifacts.')
    require(not output.exists() or not any(output.iterdir()), 'Output directory must be empty.')
    output.mkdir(parents=True, exist_ok=True)
    inventory = {}
    for group, allowed in groups.items():
        directory = artifacts / f'burrow-brigade-{group}'
        require(directory.is_dir() and not directory.is_symlink(), f'Invalid artifact: {group}')
        names = {p.name for p in directory.iterdir() if not p.name.endswith('.sha256')}
        require((bool(names) and names <= allowed) if group == 'linux' else names == allowed,
                f'Unexpected or missing {group} assets: {sorted(names)}')
        require({p.name for p in directory.iterdir()} == names | {name + '.sha256' for name in names},
                f'Unexpected {group} checksum files.')
        for name in sorted(names):
            path = directory / name
            check_pair(path)
            inventory[name] = dict(sha256=digest(path), bytes=path.stat().st_size, platform=group)
            shutil.copyfile(path, output / name)
            write_checksum(output / name)
    compose = run('git', 'show', f'{meta["sha"]}:packaging/server/compose.yaml')
    require('${BURROW_IMAGE:?Set BURROW_IMAGE in .env}' in compose, 'Unrecognized server Compose template.')
    compose = compose.replace('${BURROW_IMAGE:?Set BURROW_IMAGE in .env}', '${BURROW_IMAGE:-' + meta['image'] + '}')
    (output / 'compose.yaml').write_text(compose + '\n')
    provenance = dict(meta, assets=inventory, run_url=os.environ.get('GITHUB_SERVER_URL', 'https://github.com') +
                      f'/{meta["repository"]}/actions/runs/' + os.environ.get('GITHUB_RUN_ID', 'local'))
    (output / 'release.json').write_text(json.dumps(provenance, indent=2, sort_keys=True) + '\n')
    for name in ('compose.yaml', 'release.json'):
        write_checksum(output / name)
    payloads = sorted(p for p in output.iterdir() if not p.name.endswith('.sha256'))
    (output / 'SHA256SUMS').write_text(''.join(f'{digest(p)}  {p.name}\n' for p in payloads))
    write_checksum(output / 'SHA256SUMS')
    notes.write_text(release_notes(meta, inventory))
    verify_assets(meta, output)


def verify_assets(meta, directory):
    manifest = directory / 'SHA256SUMS'
    check_pair(manifest)
    entries = {}
    for line in manifest.read_text().splitlines():
        match = re.fullmatch(r'([0-9a-f]{64})  ([A-Za-z0-9_.-]+)', line)
        require(match is not None, 'Malformed SHA256SUMS entry.')
        sha, name = match.groups()
        require(name not in entries, f'Duplicate checksum: {name}')
        entries[name] = sha
        check_pair(directory / name)
        require(digest(directory / name) == sha, f'SHA256SUMS mismatch: {name}')
    groups = package_names(meta['version'])
    expected = {'compose.yaml', 'release.json'}
    for group, names in groups.items():
        present = names & set(entries)
        require(bool(present) if group == 'linux' else present == names, f'Missing {group} assets.')
        expected |= present
    require(set(entries) == expected, 'Unexpected release payloads.')
    payloads = expected | {'SHA256SUMS'}
    require({p.name for p in directory.iterdir()} == payloads | {p + '.sha256' for p in payloads},
            'Unexpected files in release asset directory.')
    provenance = json.loads((directory / 'release.json').read_text())
    require(all(provenance[key] == meta[key] for key in ('sha', 'tag', 'version', 'protocol', 'image')),
            'Provenance does not match the requested release.')
    return sorted(p.name for p in directory.iterdir())


def publish(meta, directory, notes):
    names = verify_assets(meta, directory)
    remote_tag(meta)
    repo, tag = meta['repository'], meta['tag']
    # Listing is deliberate: authentication/network errors must not be confused
    # with an absent release. --slurp preserves page boundaries as valid JSON.
    pages = json.loads(run('gh', 'api', '--paginate', '--slurp', f'repos/{repo}/releases?per_page=100'))
    existing = next((release for page in pages for release in page if release['tag_name'] == tag), None)
    title = f'Burrow Brigade {meta["version"]}'
    if existing:
        run('gh', 'release', 'edit', tag, '--repo', repo, '--draft=true', '--title', title, '--notes-file', str(notes))
        # Replaced/obsolete assets are only removed while the release is a draft.
        for asset in existing['assets']:
            if asset['name'] not in names:
                run('gh', 'api', '--method', 'DELETE', f'repos/{repo}/releases/assets/{asset["id"]}')
    else:
        run('gh', 'release', 'create', tag, '--repo', repo, '--verify-tag', '--draft',
            '--title', title, '--notes-file', str(notes))
    run('gh', 'release', 'upload', tag, '--repo', repo, '--clobber', *(str(directory / name) for name in names))
    # The REST by-tag endpoint does not return draft releases, even to the
    # workflow that created one. Resolve through gh's draft-aware lookup and
    # use the stable numeric release ID for both draft and published reads.
    release_id = json.loads(run('gh', 'release', 'view', tag, '--repo', repo, '--json', 'databaseId'))['databaseId']
    endpoint = f'repos/{repo}/releases/{release_id}'
    uploaded = json.loads(run('gh', 'api', endpoint))
    require(uploaded['draft'], 'Release became public before uploaded assets were verified.')
    require({asset['name'] for asset in uploaded['assets']} == set(names), 'Uploaded asset inventory differs.')
    # GitHub reports upload SHA-256 digests. If a host omits them, download those
    # assets into an empty directory and verify the actual uploaded bytes.
    with tempfile.TemporaryDirectory(prefix='burrow-release-verify-') as temporary:
        for asset in uploaded['assets']:
            local = directory / asset['name']
            expected = 'sha256:' + digest(local)
            require(asset['state'] == 'uploaded' and asset['size'] == local.stat().st_size,
                    f'Incomplete uploaded asset: {asset["name"]}')
            if asset.get('digest'):
                require(asset['digest'] == expected, f'Uploaded checksum mismatch: {asset["name"]}')
            else:
                run('gh', 'release', 'download', tag, '--repo', repo, '--pattern', asset['name'], '--dir', temporary)
                require(digest(Path(temporary) / asset['name']) == expected.removeprefix('sha256:'),
                        f'Downloaded checksum mismatch: {asset["name"]}')
    remote_tag(meta)
    if not meta['draft']:
        run('gh', 'release', 'edit', tag, '--repo', repo, '--draft=false', '--latest')
    final = json.loads(run('gh', 'api', endpoint))
    require(final['draft'] == meta['draft'], 'Unexpected final release state.')
    message = f'{"Draft" if final["draft"] else "Published"} release: {final["html_url"]} ({len(names)} verified assets)'
    print(message)
    if os.environ.get('GITHUB_STEP_SUMMARY'):
        with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as summary:
            summary.write(message + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['metadata', 'assemble', 'publish'])
    parser.add_argument('--tag', required=True)
    parser.add_argument('--draft', choices=['true', 'false'], required=True)
    parser.add_argument('--sha')
    parser.add_argument('--artifacts', type=Path, default=Path('downloaded'))
    parser.add_argument('--output', type=Path, default=Path('release-assets'))
    parser.add_argument('--assets', type=Path, default=Path('release-assets'))
    parser.add_argument('--notes', type=Path, default=Path('release-notes.md'))
    args = parser.parse_args()
    meta = metadata(args.tag, args.draft == 'true', args.sha)
    if args.command == 'metadata':
        if os.environ.get('GITHUB_OUTPUT'):
            with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
                for key in ('tag', 'version', 'sha', 'draft', 'image'):
                    value = str(meta[key]).lower() if isinstance(meta[key], bool) else meta[key]
                    output.write(f'{key}={value}\n')
        print(json.dumps(meta, indent=2))
    elif args.command == 'assemble':
        assemble(meta, args.artifacts, args.output, args.notes)
    else:
        publish(meta, args.assets, args.notes)


if __name__ == '__main__':
    main()
