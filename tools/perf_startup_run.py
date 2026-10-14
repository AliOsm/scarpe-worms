#!/usr/bin/env python3
"""One capture; caller MUST wrap this command with bench (heavy for verification).

Example: bench mise exec ruby@4.0.7 -- python3 tools/perf_startup_run.py \
    --mode app --source /frozen/baseline --output /scratch/baseline-1.json
Pass --ruby-option=--yjit / --env RUBY_GC_HEAP_FREE_SLOTS=... for runtime A/B.
App runs are headless unless --windowed is set (requires a display); --audio
requires --windowed. Reuse --data then add --resume for saved-match launch.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import threading
import time

ROOT = Path(__file__).resolve().parents[1]


def processes(root):
    """Linux current RSS for this capture's descendants; no other app is read."""
    pending, seen, rows = [root], set(), []
    while pending:
        pid = pending.pop()
        if pid in seen:
            continue
        seen.add(pid)
        directory = Path('/proc') / str(pid)
        try:
            for children in directory.glob('task/*/children'):
                pending.extend(map(int, children.read_text().split()))
            cmd = (directory / 'cmdline').read_bytes().replace(b'\0', b' ').decode(errors='replace')
            if 'process_main.rb' in cmd:
                role = 'host'
            elif 'terrain_worker.rb' in cmd:
                role = 'terrain'
            elif 'scarpe-native' in cmd:
                role = 'native'
            elif 'ruby' in cmd or 'bin/scarpe' in cmd:
                role = 'gui' if 'perf_startup_core' not in cmd else 'core'
            else:
                continue
            status = dict(line.split(':', 1) for line in (directory / 'status').read_text().splitlines())
            rows.append(dict(pid=pid, role=role, rss_kib=int(status.get('VmRSS', '0 kB').split()[0]),
                             hwm_kib=int(status.get('VmHWM', '0 kB').split()[0])))
        except (OSError, ValueError):
            continue
    return rows


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--mode', choices=['app', 'host', 'terrain', 'verify', 'frame', 'rendering'], required=True)
    p.add_argument('--source', type=Path, default=ROOT)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--ruby-option', action='append', default=[])
    p.add_argument('--env', action='append', default=[])
    p.add_argument('--windowed', action='store_true')
    p.add_argument('--audio', action='store_true')
    p.add_argument('--data', type=Path)
    p.add_argument('--resume', action='store_true')
    p.add_argument('--cold-assets', action='store_true', help='Advise Linux to evict only selected source asset file pages before spawn; not a cold OS/runtime cache')
    args = p.parse_args()
    if args.audio and not args.windowed:
        p.error('--audio requires --windowed')
    if args.resume and (not args.data or not (args.data / 'preferences.json').is_file()):
        p.error('--resume requires --data from a completed fresh capture')
    out = args.output.resolve()
    out.parent.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    # No ambient JIT/GC setting may leak into the baseline.
    for key in list(env):
        if key.startswith('RUBY_GC_') or key in ('RUBYOPT', 'RUBY_YJIT_ENABLE'):
            env.pop(key)
    for key in ('PERF_STARTUP_NO_MAJOR', 'PERF_STARTUP_RESUME', 'PERF_STARTUP_DATA',
                'BURROW_BENCH_PROFILE', 'BURROW_FRAME_ALLOCATIONS'):
        env.pop(key, None)
    env.update(BURROW_BENCH_SOURCE=str(args.source.resolve()), PERF_STARTUP_OUTPUT=str(out),
               SCARPE_DISPLAY_SERVICE='native', SCARPE_NATIVE_HEADLESS='0' if args.windowed else '1',
               PERF_STARTUP_AUDIO='1' if args.audio else '0', ALSOFT_DRIVERS='null')
    env['PERF_STARTUP_SOURCE_FILES'] = json.dumps({name: hashlib.sha256((args.source / name).read_bytes()).hexdigest()
        for name in ('lib/burrow/client/app.rb', 'lib/burrow/terrain_generator.rb')})
    env['RUBYOPT'] = ' '.join([f'-r{ROOT / "tools/perf_startup_runtime.rb"}', *args.ruby_option])
    env['PERF_STARTUP_RUNTIME_DIR'] = str(out.with_suffix('.runtime'))
    for setting in args.env:
        key, value = setting.split('=', 1)
        env[key] = value
    if args.data:
        args.data.mkdir(parents=True, exist_ok=True)
        env['PERF_STARTUP_DATA'] = str(args.data.resolve())
    if args.resume:
        env['PERF_STARTUP_RESUME'] = '1'
    env['PERF_STARTUP_FILE_CACHE'] = 'warm/uncontrolled'
    if args.cold_assets:
        if not hasattr(os, 'posix_fadvise'):
            p.error('--cold-assets requires posix_fadvise')
        # No global cache drop or file mutation, and the caller holds bench.
        for path in (args.source / 'assets').rglob('*'):
            if path.is_file():
                with path.open('rb') as file:
                    os.posix_fadvise(file.fileno(), 0, 0, os.POSIX_FADV_DONTNEED)
        env['PERF_STARTUP_FILE_CACHE'] = 'asset file pages advised DONTNEED; OS may retain mapped pages; runtime/libraries warm'
    if args.mode == 'app':
        command = [str(ROOT / 'bin/scarpe'), str(ROOT / 'tools/perf_startup_app.rb')]
    elif args.mode == 'frame':
        env['BURROW_FRAME_OUTPUT'] = str(out.with_suffix(''))
        command = [str(ROOT / 'bin/scarpe'), str(ROOT / 'tools/check_frame_work.rb')]
    elif args.mode == 'rendering':
        command = ['python3', str(ROOT / 'tools/check_rendering.py'), '--output', str(out), '--record-only']
        if args.audio:
            command.append('--audio')
    else:
        env['PERF_STARTUP_MODE'] = args.mode
        command = ['bundle', 'exec', 'ruby', str(ROOT / 'tools/perf_startup_core.rb')]
    env['PERF_STARTUP_LAUNCHED'] = str(time.monotonic())
    samples, done = [], threading.Event()
    with out.with_suffix('.log').open('w') as log:
        child = subprocess.Popen(command, cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT)
        def monitor():
            while not done.wait(1):
                samples.append(dict(seconds=time.monotonic() - float(env['PERF_STARTUP_LAUNCHED']),
                                    processes=processes(child.pid)))
        thread = threading.Thread(target=monitor, daemon=True)
        thread.start()
        try:
            code = child.wait(timeout=280)
        finally:
            if child.poll() is None:
                # A failed capture must not leave its host/native/worker doing
                # work after the caller releases the exclusive benchmark lock.
                descendants = processes(child.pid)
                for row in reversed(descendants):
                    try:
                        os.kill(row['pid'], signal.SIGTERM)
                    except ProcessLookupError:
                        pass
                child.terminate()
                try:
                    child.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait()
                for row in descendants:
                    try:
                        os.kill(row['pid'], signal.SIGKILL)
                    except ProcessLookupError:
                        pass
            done.set()
            thread.join()
    out.with_suffix('.processes.json').write_text(json.dumps(samples) + '\n')
    if code:
        print(out.with_suffix('.log').read_text()[-10000:])
        raise SystemExit(code)
    print(json.dumps(dict(output=str(out), mode=args.mode, success=True)), flush=True)


if __name__ == '__main__':
    main()
