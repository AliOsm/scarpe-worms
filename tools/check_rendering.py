#!/usr/bin/env python3
"""Measure sustained action, pan and zoom in a native window at its real device density.
Linux: xvfb-run -a -s '-screen 0 3840x2400x24' python3 tools/check_rendering.py --scale 2
Mac: python3 tools/check_rendering.py --app 'dist/Burrow Brigade.app'
"""
from pathlib import Path
import argparse
import bisect
import json
import os
import statistics
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def stats(values):
    ordered = sorted(values)
    assert ordered, 'No samples were collected'
    return dict(count=len(values), mean_ms=statistics.mean(values),
                p95_ms=ordered[min(len(ordered)-1, int(len(ordered)*.95))],
                p99_ms=ordered[min(len(ordered)-1, int(len(ordered)*.99))],
                max_ms=max(values), over_33ms=sum(v > 33.4 for v in values), over_50ms=sum(v > 50 for v in values))


def moving_intervals(rows, samples, started_unix):
    """Use the latest completed app sample, including explicit transitions to idle.

    A nearby *earlier* moving sample must not label a later idle interval a stall.
    Conversely, if updates stop while motion is active, retain the entire gap.
    """
    times = [s[0] for s in samples]
    intervals = []
    for a, b in zip(rows, rows[1:]):
        index = bisect.bisect_right(times, started_unix+a[0])-1
        if index >= 0 and samples[index][4]:
            intervals.append((b[0]-a[0])*1000)
    return intervals


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--scale', type=float, help='Linux X11 window density; macOS uses the actual display')
    parser.add_argument('--size', default='1280x800')
    parser.add_argument('--output', type=Path, default=ROOT / 'docs/validation/native-rendering.json')
    parser.add_argument('--app', type=Path)
    parser.add_argument('--linux-ruby', type=Path)
    parser.add_argument('--audio', action='store_true')
    parser.add_argument('--capture', type=Path)
    parser.add_argument('--record-only', action='store_true', help='Record baseline timings without applying budgets')
    parser.add_argument('--timer-slack-ms', type=int, default=0,
                        help='Linux fault injection: coalesce ordinary UI sleeps by this much')
    args = parser.parse_args()
    if args.timer_slack_ms and sys.platform != 'linux':
        parser.error('Timer-slack fault injection is Linux only')
    env = os.environ.copy()
    command = [str(ROOT / 'bin/scarpe'), str(ROOT / 'tools/check_rendering.rb')]
    if args.app:
        from check_package import package_environment
        env, ruby = package_environment(args.app, args.linux_ruby, windowed=True)
        command = [str(ruby), '-EUTF-8', str(ROOT / 'tools/check_rendering.rb')]
    for name in ('SCARPE_NATIVE_TRACE', 'SCARPE_NATIVE_PAINT_TRACE', 'SCARPE_NATIVE_DAMAGE'):
        env.pop(name, None)
    if args.scale:
        if sys.platform == 'darwin':
            parser.error('macOS must measure the real display scale')
        env['WINIT_X11_SCALE_FACTOR'] = str(args.scale)
    env.update(SCARPE_DISPLAY_SERVICE='native', SCARPE_NATIVE_HEADLESS='0',
               BURROW_BENCH_SIZE=args.size, BURROW_BENCH_MUTE='0' if args.audio else '1',
               BURROW_BENCH_TIMER_SLACK_NS=str(args.timer_slack_ms * 1_000_000))
    if args.audio and sys.platform == 'linux':
        env.setdefault('ALSOFT_DRIVERS', 'null')
    if args.capture:
        env['BURROW_BENCH_SHOT'] = str(args.capture.resolve())
    with tempfile.TemporaryDirectory(prefix='burrow-rendering-stats-') as directory:
        env.update(SCARPE_NATIVE_STATS=directory, BURROW_BENCH_REPORT=str(Path(directory)/'journey.json'))
        subprocess.run(command, cwd=ROOT, env=env, check=True, timeout=100)
        report = json.loads((Path(directory)/'journey.json').read_text())
        native = json.loads((Path(directory)/'rust.json').read_text())
        ruby = json.loads((Path(directory)/'ruby.json').read_text())
        gameplay = json.loads((Path(directory)/'game.json').read_text())
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.with_suffix('.raw.json').write_text(json.dumps(dict(journey=report, native=native, ruby=ruby, gameplay=gameplay))+'\n')
        report['surface'] = {k: native['counters'].get(k) for k in ('surface_width', 'surface_height', 'surface_scale_milli',
                                                                 'render_width', 'render_height', 'render_scale_milli')}
        report['surface']['compositor_scaling'] = bool(native['counters'].get('compositor_scaling'))
        if sys.platform == 'darwin':
            assert report['surface']['compositor_scaling'], 'macOS compositor scaling was not configured'
        if args.scale:
            assert report['surface']['surface_scale_milli'] == round(args.scale*1000), 'Requested density was not rendered'
        budget = int(env.get('SCARPE_NATIVE_MAX_RENDER_PIXELS', env.get('BURROW_RENDER_PIXELS', '1500000')))
        if budget >= 65536:
            assert report['surface']['render_width'] * report['surface']['render_height'] <= budget, 'Rendering exceeded its pixel budget'
        if args.audio:
            assert report['audio'], 'Audio was requested but the mixer did not start'
        samples = report.pop('samples')
        results = {}
        for stage in report.pop('stages'):
            first, last = stage['from'], stage['to']
            rows = [r for r in native['frames'] if first <= native['started_unix']+r[0] <= last]
            if stage['name'] == 'combat':
                intervals = moving_intervals(rows, [s for s in samples if s[1] == 'combat'], native['started_unix'])
            else:
                # Zoom changes are discrete. Paint work is measured for every
                # frame; only continuous pan has a frame-interval budget.
                intervals = [(b[0]-a[0])*1000 for a,b in zip(rows, rows[1:])]
            results[stage['name']] = dict(presented_intervals=stats(intervals),
                paint=stats([r[4] for r in rows]), present=stats([r[5] for r in rows]),
                app_update=stats([s[2] for s in samples if s[1]==stage['name'] and s[2] is not None]))
        report.update(scenarios=results, counters=native['counters'],
                      measurement='macOS native window' if sys.platform=='darwin' else 'Linux native X11 window',
                      macos_execution=sys.platform=='darwin', packaged=bool(args.app))
        report['wait_backend'] = ruby.get('wait_backend')
        report['wait_overshoot'] = stats([r[3] for r in ruby['wait_samples']])
        report['timer_slack_ms'] = args.timer_slack_ms
        index = gameplay['columns'].index('backlog_ms')
        report['playback_backlog'] = stats([r[index] for r in gameplay['frames'] if r[index] is not None])
        report['audio_output'] = 'Linux OpenAL null driver' if args.audio and sys.platform=='linux' else 'device' if args.audio else 'muted'
        report['motion_interval_selection'] = 'latest completed app sample at the starting presentation; includes stalled updates while motion remains active'
        if args.linux_ruby:
            report['linux_substitutions'] = dict(ruby=str(args.linux_ruby), renderer=env['SCARPE_NATIVE_BIN'],
                                                 ffi_extension=env.get('BURROW_TEST_FFI_EXTENSION'))
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2)+'\n')
        for name, values in results.items():
            print(name, json.dumps(values['presented_intervals']), flush=True)
        if not args.record_only:
            assert report['wait_backend']['name'] == ('KqueueTimer' if sys.platform == 'darwin' else 'TimerFD')
            assert report['wait_backend']['error'] is None
            for name in ('combat', 'pan'):
                interval = results[name]['presented_intervals']
                assert interval['mean_ms'] < 18.5 and interval['p95_ms'] < 25, f'{name}: sustained motion missed its budget'
                assert interval['max_ms'] < 60, f'{name}: a frame stalled'
            assert results['zoom']['paint']['max_ms'] < 55, 'Zoom stalled in painting'


if __name__ == '__main__':
    main()
