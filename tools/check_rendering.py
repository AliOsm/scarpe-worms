#!/usr/bin/env python3
"""Measure sustained action, pan and zoom in a native window at its real device density.
Linux: xvfb-run -a -s '-screen 0 3840x2400x24' python3 tools/check_rendering.py --scale 2
Mac: python3 tools/check_rendering.py --app 'dist/Burrow Brigade.app'
"""
from pathlib import Path
import argparse
import bisect
from collections import defaultdict
import json
import os
import statistics
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def stats(values):
    ordered = sorted(values)
    if not ordered:
        return dict(count=0, mean_ms=None, p95_ms=None, p99_ms=None, max_ms=None, over_33ms=0, over_50ms=0)
    return dict(count=len(values), mean_ms=statistics.mean(values),
                p95_ms=ordered[min(len(ordered)-1, int(len(ordered)*.95))],
                p99_ms=ordered[min(len(ordered)-1, int(len(ordered)*.99))],
                max_ms=max(values), over_33ms=sum(v > 33.4 for v in values), over_50ms=sum(v > 50 for v in values))


def frame_unix(row, started_unix):
    """Use a live wall-clock anchor to join Ruby and native frame samples.

    Rust Instant uses CLOCK_UPTIME_RAW on macOS. Mapping its elapsed time to
    wall time once at startup drifts when the OS disciplines the wall clock.
    Older captures retain their original, approximate mapping.
    """
    return row[7] if len(row) > 7 else started_unix + row[0]


def moving_intervals(rows, samples, started_unix):
    """Measure motion gaps using completed updates, never update start times.

    A turn handoff can move the camera once and then become idle before the next
    paint. If that move was already presented, an explicit idle update ends the
    interval. Any NEW movement inside the gap remains unpainted until its end,
    even if it stops meanwhile. Absent updates retain the entire active stall.
    Emit at most one interval per native gap to avoid inflating sample counts.
    """
    times = [s[0] for s in samples]
    intervals = []
    for a, b in zip(rows, rows[1:]):
        start, end = frame_unix(a, started_unix), frame_unix(b, started_unix)
        if end <= start:
            raise ValueError('Frame wall clock moved backwards; repeat the timing capture')
        index = bisect.bisect_right(times, start) - 1
        stop = bisect.bisect_right(times, end)
        updates = samples[index + 1:stop]
        active = index >= 0 and samples[index][4]
        idle_at = next((s[0] for s in updates if not s[4]), end)
        pending_at = next((s[0] for s in updates if s[4]), None)
        duration = max(0, idle_at - start) if active else 0
        if pending_at is not None:
            # Continuing motion is charged from the preceding presentation.
            # A new burst after a confirmed idle begins at its first update.
            pending_start = start if active and pending_at < idle_at else pending_at
            duration = max(duration, end - pending_start)
        if duration > 0:
            # Correlate against the live wall clock, but measure the selected
            # fraction of this frame interval with the monotonic native clock.
            intervals.append(duration / (end - start) * (b[0] - a[0]) * 1000)
    return intervals


def distribution(values):
    """A unit-neutral distribution for objects, messages, bytes and milliseconds."""
    values = sorted(values)
    if not values:
        return dict(count=0, mean=None, p95=None, max=None)
    return dict(count=len(values), mean=statistics.mean(values),
                p95=values[min(len(values)-1, int(len(values)*.95))], max=values[-1])


def frame_profile_summary(profile):
    if not profile:
        return None
    groups = defaultdict(lambda: defaultdict(list))
    for row in profile['samples']:
        groups[row[1]][row[2]].append(row)
    stages = {}
    for stage, methods in groups.items():
        counters = profile['stages'][stage]
        decodes = [row for row in profile['decodes'] if row[1] == stage and row[2] == 'state']
        stages[stage] = dict(methods={method: {
            key: distribution(row[i] for row in rows)
            for i, key in enumerate(profile['columns']) if 3 <= i <= 7
        } for method, rows in methods.items()},
            gc={key: counters['after'][key] - counters['before'][key]
                for key in ('minor_gc_count', 'major_gc_count', 'time', 'total_allocated_objects')},
            snapshot_decode={key: distribution(row[i] for row in decodes)
                             for i, key in enumerate(profile['decode_columns']) if i >= 3})
    slowest = sorted((s for s in profile['samples'] if s[2] == 'App#update'), key=lambda s: -s[3])[:10]
    stalls = []
    for row in slowest:
        start, end = row[0] - row[3] / 1000, row[0]
        overlapping = [d for d in profile['decodes'] if d[0] >= start and d[0] - d[4] / 1000 <= end]
        stalls.append(dict(zip(profile['columns'], row), overlapping_decodes=overlapping))
    return dict(stages=stages, slowest_updates=stalls, caveats=profile['caveats'])


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
        audio_path = Path(directory)/'audio.json'
        audio_timing = json.loads(audio_path.read_text()) if audio_path.exists() else None
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.with_suffix('.raw.json').write_text(json.dumps(dict(journey=report, native=native, ruby=ruby, gameplay=gameplay, audio=audio_timing))+'\n')
        if audio_timing:
            args.output.with_suffix('.audio.json').write_text(json.dumps(audio_timing)+'\n')
        report['frame_profile'] = frame_profile_summary(report.get('frame_profile'))
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
            rows = [r for r in native['frames'] if first <= frame_unix(r, native['started_unix']) <= last]
            stage_samples = [s for s in samples if s[1] == stage['name']]
            active_intervals = moving_intervals(rows, stage_samples, native['started_unix'])
            if stage['name'] == 'combat':
                intervals = active_intervals
            else:
                # Preserve historical whole-stage intervals for comparison.
                # Gaps between zoom inputs include intentionally skipped idle
                # paints; active_motion_intervals measures the moving parts.
                intervals = [(b[0]-a[0])*1000 for a,b in zip(rows, rows[1:])]
            results[stage['name']] = dict(presented_intervals=stats(intervals),
                active_motion_intervals=stats(active_intervals),
                updates=len(stage_samples), moving_updates=sum(bool(s[4]) for s in stage_samples),
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
        report['motion_analysis_version'] = 3
        report['frame_clock_correlation'] = 'per-frame wall clock' if 'unix' in native['frame_columns'] else 'startup wall clock plus native elapsed (legacy)'
        report['motion_interval_selection'] = 'completed updates; already-presented motion may end at idle, new unpainted movement is charged until the next presentation; at most one sample per gap'
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
                assert interval['count'] >= 2, f'{name}: insufficient active-motion evidence'
                assert interval['mean_ms'] < 18.5 and interval['p95_ms'] < 25, f'{name}: sustained motion missed its budget'
                assert interval['max_ms'] < 60, f'{name}: a frame stalled'
            # Damage-based rendering intentionally skips unchanged idle frames.
            # The GUI still updates at 60Hz: catch a blocked thread even while
            # actors/camera are idle, without demanding redundant native paints.
            assert results['combat']['app_update']['max_ms'] < 60, 'Combat GUI updates stalled, including idle time'
            assert results['zoom']['paint']['count'], 'Zoom did not paint'
            assert results['zoom']['paint']['max_ms'] < 55, 'Zoom stalled in painting'


if __name__ == '__main__':
    main()
