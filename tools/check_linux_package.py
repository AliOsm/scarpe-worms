#!/usr/bin/env python3
"""Verify the actual tarball on Linux; no installed Ruby, gems or source renderer.

Python 3.11+, Xvfb for --windowed. Run python3 -I.
"""
from pathlib import Path, PurePosixPath
import argparse
import hashlib
import json
import os
import platform
import shutil
import signal
import subprocess
import tarfile
import tempfile
import time


def digest(path):
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def inventory(app):
    return {str(p.relative_to(app)): (p.stat().st_size, digest(p))
            for p in app.rglob('*') if p.is_file()}


def extract_package(archive, destination):
    # Debian 12's Python lacks tarfile's data filter. The Linux release format
    # needs only directories and regular files; reject links, special files,
    # traversal, duplicate files and excess data before creating any content.
    with tarfile.open(archive) as tar:
        members = tar.getmembers()
        if sum(item.size for item in members) > 512 * 1024**2:
            raise ValueError('Package exceeds the extraction size limit')
        names = set()
        for item in members:
            path = PurePosixPath(item.name)
            if (path.is_absolute() or '..' in path.parts or not path.parts
                    or not (item.isdir() or item.isfile()) or path in names):
                raise ValueError(f'Unsafe or duplicate archive entry: {item.name}')
            names.add(path)
        for item in members:
            path = destination / item.name
            if item.isdir():
                path.mkdir(parents=True, exist_ok=True)
            else:
                path.parent.mkdir(parents=True, exist_ok=True)
                with tar.extractfile(item) as source, path.open('xb') as target:
                    shutil.copyfileobj(source, target)
                path.chmod(0o755 if item.mode & 0o111 else 0o644)


def bundle_processes(app):
    found = []
    for process in Path('/proc').glob('[0-9]*'):
        try:
            executable = (process / 'exe').resolve(strict=True)
            if executable.is_relative_to(app):
                found.append(int(process.name))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return found


def run(command, env, cwd, log, timeout=90):
    # Own the process group so a failed check cannot leave a host behind.
    with log.open('w') as stream:
        process = subprocess.Popen(list(map(str, command)), env=env, cwd=cwd,
                                   stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            code = process.wait(timeout=timeout)
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
    if code:
        raise RuntimeError(f'{command} exited {code}:\n{log.read_text(errors="replace")}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('--windowed', action='store_true')
    parser.add_argument('--locale', choices=['unset', 'c'], default='unset')
    parser.add_argument('--audio-driver', choices=['null', 'pulse', 'alsa'], default='null',
                        help='Windowed checks can use an externally configured silent audio device')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    archive = args.archive.resolve()
    actual_digest = digest(archive)
    checksum = archive.with_suffix('.gz.sha256').read_text().strip()
    if checksum != f'{actual_digest}  {archive.name}':
        raise RuntimeError('Archive checksum/filename mismatch')
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    for key in list(env):
        if key.startswith(('RUBY', 'GEM_', 'BUNDLE_', 'BURROW_', 'SCARPE_', 'LC_', 'XDG_')) or key in ('LANG', 'LANGUAGE', 'LD_LIBRARY_PATH'):
            env.pop(key, None)
    if args.locale == 'c':
        env.update(LC_ALL='C', LANG='C')
    if args.windowed:
        # Exercise X11 under Xvfb even if the invoking machine uses Wayland.
        env.pop('WAYLAND_DISPLAY', None)
        env['WINIT_UNIX_BACKEND'] = 'x11'
    # Deliberately contaminated development settings must be ignored by launcher.
    env.update(RUBYOPT='-r/nonexistent/developer.rb', RUBYLIB='/nonexistent/libraries',
               GEM_HOME='/nonexistent/gems', BUNDLE_GEMFILE='/nonexistent/Gemfile',
               SCARPE_NATIVE_HEADLESS='0' if args.windowed else '1', ALSOFT_DRIVERS=args.audio_driver)
    with tempfile.TemporaryDirectory(prefix='Burrow Équipe package ') as directory:
        temporary = Path(directory)
        installed = temporary / 'Installed game'
        installed.mkdir()
        extract_package(archive, installed)
        if sorted(p.name for p in installed.iterdir()) != ['Burrow Brigade']:
            raise RuntimeError('Unexpected archive layout')
        app = installed / 'Burrow Brigade'
        before = inventory(app)
        build = json.loads((app / 'resources/build.json').read_text())
        (temporary / 'home').mkdir()
        (temporary / 'terrain Équipe').mkdir()
        env.update(HOME=str(temporary / 'home'), XDG_DATA_HOME=str(temporary / 'data Équipe'),
                   XDG_STATE_HOME=str(temporary / 'state Équipe'), TMPDIR=str(temporary / 'terrain Équipe'))
        # Filesystem permissions and the content inventory both check no writes.
        for path in app.rglob('*'):
            if not path.is_symlink():
                path.chmod(path.stat().st_mode & ~0o222)
        app.chmod(0o555)
        launcher = app / 'burrow-brigade'
        launches = []
        try:
            run([launcher, '--check'], env, temporary, out / 'runtime.log')
            run([launcher, '--install-desktop'], env, temporary, out / 'desktop.log')
            entry = Path(env['XDG_DATA_HOME']) / 'applications/burrow-brigade.desktop'
            contents = entry.read_text()
            assert f'Exec="{launcher}"' in contents and f'Icon={app}/burrow-brigade.png' in contents
            if shutil.which('desktop-file-validate'):
                subprocess.run(['desktop-file-validate', str(entry)], check=True)
            for resume in ('0', '1'):
                report = out / f'launch-{resume}.json'
                env.update(BURROW_SMOKE_RESUME=resume, BURROW_SMOKE_REPORT=str(report),
                           BURROW_SMOKE_SHOT=str(out / f'launch-{resume}.png'))
                run([launcher, '--smoke'], env, temporary, out / f'launch-{resume}.log')
                launches.append(json.loads(report.read_text()))
                deadline = time.monotonic() + 5
                while bundle_processes(app) and time.monotonic() < deadline:
                    time.sleep(0.1)
                assert not bundle_processes(app), 'Bundled host/terrain/renderer survived shutdown'
                assert all(not Path(f'/proc/{pid}').exists() for pid in launches[-1]['subprocesses'].values()), 'A worker was not reaped'
            assert launches[0]['shot_presented'], 'No shot reached the renderer'
            assert launches[0]['match_id'] == launches[1]['match_id'], 'Restart created another match'
            assert launches[0]['player_id'] == launches[1]['player_id'], 'Restart changed player identity'
            assert all(p['unicode_terrain_path'] for p in launches)
            saved = Path(env['XDG_DATA_HOME']) / 'burrow-brigade/local/server.json'
            assert json.loads(saved.read_text())['rooms'], 'Match was not saved'
            logs = Path(env['XDG_STATE_HOME']) / 'burrow-brigade/logs/performance'
            sessions = sorted(logs.glob('session-*'))
            assert len(sessions) == 2, 'Expected two diagnostic sessions in XDG_STATE_HOME'
            for session in sessions:
                for name in ('session.json', 'ruby.json', 'rust.json', 'game.json'):
                    data = json.loads((session / name).read_text())
                    if name in ('rust.json', 'game.json'):
                        assert data['frames'] and len(data['frames']) <= data['sample_limit'] == 10000
                        assert data['sample_policy'] == 'most_recent'
                    if name == 'ruby.json':
                        assert data['wait_backend']['name'] == 'TimerFD' and data['wait_backend']['error'] is None
                    if name == 'rust.json' and args.windowed:
                        assert data['counters']['exit_callback_flush'] == 1
                if args.windowed:
                    assert launches[0]['openal'] and launches[1]['audio_cues'] > 0
                    assert (session / 'audio.json').exists()
            run([launcher, '--uninstall-desktop'], env, temporary, out / 'desktop-uninstall.log')
            assert not entry.exists() and saved.exists(), 'Desktop removal damaged saved data'
            assert inventory(app) == before, 'The read-only bundle was modified'
            result = {'archive': archive.name, 'bytes': archive.stat().st_size, 'sha256': actual_digest,
                      'environment': platform.freedesktop_os_release(), 'kernel': platform.release(),
                      'build': {k: build[k] for k in ('version', 'revision', 'ruby', 'openal_soft', 'build_os', 'glibc_floor')},
                      'windowed': args.windowed, 'locale': args.locale, 'launches': launches,
                      'same_match_and_player_resumed': True, 'save_verified': True,
                      'no_child_processes': True, 'bundle_unchanged': True, 'desktop_entry': True,
                      'xdg_data_and_diagnostics': True,
                      'audio_output': f'OpenAL {args.audio_driver}' if args.windowed else 'disabled by headless mode'}
            (out / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
            print(json.dumps(result, indent=2))
        finally:
            for pid in bundle_processes(app):
                try:
                    os.kill(pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            for path in [app, *app.rglob('*')]:
                if path.is_dir():
                    path.chmod(0o755)


if __name__ == '__main__':
    main()
