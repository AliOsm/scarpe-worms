#!/usr/bin/env python3
"""Run one <=150s lease of a persistent memory probe UNDER THE BENCH WRAPPER.

bench mise exec ruby@3.4.7 -- python3 tools/perf_startup_memory.py \
  --state /scratch/memory-lease.json --output /scratch/memory.json --source /tree
Repeat the identical command until the output exists. Every workload process is
SIGSTOPped before the lock is released, then resumed in the next lease. The native
renderer owns a separate process group, so it is stopped/resumed explicitly too.
Use --cleanup to terminate a failed/abandoned probe (also under bench).
"""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]


def write(path, value):
    tmp = path.with_suffix('.tmp')
    tmp.write_text(json.dumps(value))
    tmp.replace(path)


def signal_groups(state, value):
    native = Path(state['native_pid_file'])
    groups = [state['pid']]
    if native.exists():
        groups.append(int(native.read_text().strip()))
    for group in groups:
        try:
            os.killpg(group, value)
        except ProcessLookupError:
            pass


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--state', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--source', type=Path, required=True)
    p.add_argument('--lease-seconds', type=float, default=125)
    p.add_argument('--cleanup', action='store_true')
    args = p.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    if args.output.exists():
        print('Memory probe complete:', args.output)
        return
    state = json.loads(args.state.read_text()) if args.state.exists() else None
    if args.cleanup:
        if state:
            signal_groups(state, signal.SIGCONT)
            signal_groups(state, signal.SIGTERM)
        return
    ready = Path(str(args.state) + '.ready')
    ready.unlink(missing_ok=True)
    deadline = time.monotonic() + min(args.lease_seconds, 125)
    if state:
        state['paused_seconds'] += time.monotonic() - state['paused_at']
        state['lease_deadline'] = deadline
        write(args.state, state)
        signal_groups(state, signal.SIGCONT)
    else:
        env = os.environ.copy()
        for key in list(env):
            if key.startswith('RUBY_GC_') or key in ('RUBYOPT', 'RUBY_YJIT_ENABLE'):
                env.pop(key)
        native = str(args.state) + '.native-pid'
        env.update(SCARPE_DISPLAY_SERVICE='native', SCARPE_NATIVE_HEADLESS='1',
                   SCARPE_NATIVE_PID_FILE=native, BURROW_BENCH_SOURCE=str(args.source.resolve()),
                   PERF_STARTUP_OUTPUT=str(args.output.resolve()), PERF_STARTUP_PAUSE_FILE=str(args.state.resolve()))
        with args.output.with_suffix('.log').open('w') as log:
            child = subprocess.Popen([str(ROOT / 'bin/scarpe'), str(ROOT / 'tools/perf_startup_memory.rb')],
                                     env=env, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        state = dict(pid=child.pid, native_pid_file=native, paused_seconds=0, lease_deadline=deadline)
        write(args.state, state)
    try:
        while not ready.exists() and not args.output.exists():
            failure = Path(str(args.output) + '.failure')
            if failure.exists():
                raise RuntimeError(failure.read_text())
            if time.monotonic() > deadline + 20:
                raise RuntimeError('Memory probe did not yield between native requests')
            time.sleep(0.5)
    finally:
        if args.output.exists():
            # The report is written just before normal close; let children exit
            # inside this lease so cleanup never runs during another benchmark.
            closing = time.monotonic() + 4
            status = Path('/proc') / str(state['pid']) / 'status'
            while status.exists() and time.monotonic() < closing:
                try:
                    if '\nState:\tZ' in status.read_text():
                        break
                except FileNotFoundError:
                    break
                time.sleep(0.1)
        else:
            signal_groups(state, signal.SIGSTOP)
            state['paused_at'] = time.monotonic()
            write(args.state, state)
    print(json.dumps(dict(output=str(args.output), complete=args.output.exists(), state=state)))


if __name__ == '__main__':
    main()
