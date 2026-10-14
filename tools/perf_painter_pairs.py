#!/usr/bin/env python3
"""Interleaved A/B driver; EACH capture acquires bench separately.

Export PERF_AGENT=painter and TMPDIR=<scratch>/tmp, then:
python3 -I tools/perf_painter_pairs.py final-net /archived/net /candidate \
    --scratch <scratch>/painter \
    --modes app,crater,worker
Do not wrap this entire driver with bench: that would nest the lock. It invokes
the sibling bin/bench wrapper and Ruby 3.4.7 for every capture. 'app' is the
unprofiled windowed/audio-null native start; 'worker' adds separate attribution;
'work' profiles two direct painter fixtures; 'crater' reuses the net session.
"""
import argparse
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('id')
    p.add_argument('baseline', type=Path)
    p.add_argument('candidate', type=Path)
    p.add_argument('--scratch', type=Path, required=True)
    p.add_argument('--modes', default='work,app')
    p.add_argument('--count', type=int, default=5)
    p.add_argument('--start', type=int, default=1)
    args = p.parse_args()
    modes = args.modes.split(',')
    if set(modes) - {'work', 'app', 'worker', 'crater'}:
        p.error('Unknown mode')
    if not 1 <= args.start <= args.count:
        p.error('Require 1 <= start <= count')
    if os.environ.get('PERF_AGENT') != 'painter' or not os.environ.get('TMPDIR'):
        p.error('Export PERF_AGENT=painter and the scratch TMPDIR')
    scratch = args.scratch.resolve()
    (scratch / 'raw').mkdir(parents=True, exist_ok=True)
    for i in range(args.start, args.count + 1):
        for arm, source in [('A', args.baseline.resolve()), ('B', args.candidate.resolve())]:
            for mode in modes:
                output = scratch / 'raw' / f'{args.id}-{mode}-{arm}-{i}.json'
                env = os.environ.copy()
                env.update(BURROW_BENCH_SOURCE=str(source), PERF_PAINTER_OUTPUT=str(output),
                           BURROW_NET_ROOT=str(source))
                if mode == 'work':
                    cmd = ['bundle', 'exec', 'ruby', 'tools/perf_painter_work.rb']
                elif mode in ('app', 'worker'):
                    cmd = ['xvfb-run', '-a', '-s', '-screen 0 3840x2400x24', 'python3', '-I',
                           'tools/perf_painter_run.py', '--mode', 'app', '--windowed', '--audio',
                           '--source', str(source), '--output', str(output)]
                    if mode == 'worker':
                        cmd += ['--env', 'RUBYOPT=-r' + str(ROOT / 'tools/perf_painter_worker.rb')]
                else:
                    cmd = ['bundle', 'exec', 'ruby', 'tools/perf_net_session.rb', '--rounds', '0',
                           '--terrain', '--output', str(output)]
                subprocess.run([str(scratch.parent / 'bin/bench'), 'mise', 'exec', 'ruby@3.4.7',
                                '--', *cmd], cwd=ROOT, env=env, check=True)


if __name__ == '__main__':
    main()
