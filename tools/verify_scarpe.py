#!/usr/bin/env python3
"""Verify the pinned upstream tree plus exactly the exported Scarpe patches."""
from pathlib import Path
import os
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def verify(apply=False):
    repo = ROOT / 'vendor/scarpe'
    def git(*args, env=None):
        return subprocess.check_output(['git', '-C', str(repo), *args], env=env, text=True).strip()
    assert git('rev-parse', 'HEAD') == (ROOT / 'SCARPE_REVISION').read_text().strip(), 'Wrong Scarpe revision'
    patches = sorted((ROOT / 'patches/scarpe').glob('*.patch'))
    actual = set(git('diff', 'HEAD', '--name-only').splitlines()) | set(git('ls-files', '--others', '--exclude-standard').splitlines())
    applied = None
    with tempfile.TemporaryDirectory(prefix='burrow-index-') as directory:
        env = os.environ | {'GIT_INDEX_FILE': str(Path(directory) / 'index')}
        git('read-tree', 'HEAD', env=env)
        # Compare each complete prefix. Reverse-checking individual patches is not
        # idempotent when a later patch intentionally changes the same lines.
        for count in range(len(patches) + 1):
            if count:
                git('apply', '--cached', str(patches[count - 1]), env=env)
            expected = set(git('diff', '--cached', '--name-only', 'HEAD', env=env).splitlines())
            if actual == expected and all(
                git('hash-object', path) == git('ls-files', '-s', '--', path, env=env).split()[1]
                for path in expected
            ):
                applied = count
    assert applied is not None, 'Scarpe has changes outside the exported patch series; refusing to overwrite them'
    if apply:
        for patch in patches[applied:]:
            git('apply', str(patch))
    else:
        assert applied == len(patches), f'Missing Scarpe patches: {[p.name for p in patches[applied:]]}'
    print('Scarpe revision and independent patches verified.')


if __name__ == '__main__':
    verify(apply='--apply' in sys.argv[1:])
