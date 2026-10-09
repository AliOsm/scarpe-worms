#!/usr/bin/env python3
"""Measure frames actually presented by the native window during moving action.
On Linux: xvfb-run -a python3 tools/check_action.py. No headless paint shortcuts.
"""
from pathlib import Path
import json, os, statistics, subprocess, tempfile
ROOT = Path(__file__).resolve().parents[1]

def stats(values):
    ordered = sorted(values)
    return dict(count=len(values), mean_ms=statistics.mean(values), p95_ms=ordered[int(len(ordered)*.95)], max_ms=max(values))

with tempfile.TemporaryDirectory(prefix='burrow-frames-') as directory:
    env = os.environ | {'SCARPE_DISPLAY_SERVICE': 'native', 'SCARPE_NATIVE_HEADLESS': '0',
        'SCARPE_NATIVE_STATS': directory, 'BURROW_ACTION_REPORT': str(Path(directory)/'action.json')}
    subprocess.run([str(ROOT/'bin/scarpe'), str(ROOT/'tools/check_action.rb')], cwd=ROOT, env=env, check=True)
    report = json.loads((Path(directory)/'action.json').read_text())
    native = json.loads((Path(directory)/'rust.json').read_text())
    samples = report.pop('motion_samples')
    periods = []
    start = None
    for at, moving in samples:
        if moving and start is None: start = at
        if not moving and start is not None:
            if at-start >= .25: periods.append((start, at))
            start = None
    if start is not None: periods.append((start, samples[-1][0]))
    frames = [native['started_unix']+row[0] for row in native['frames']]
    intervals = []
    counts = []
    for start, end in periods:
        selected = [at for at in frames if start+.05 <= at <= end]
        intervals += [(b-a)*1000 for a,b in zip(selected,selected[1:])]
        counts.append({'seconds': end-start, 'frames': len(selected)})
    report['native_motion_frame_intervals'] = stats(intervals)
    report['motion_periods'] = counts
    report['native_phases'] = native['phases']
    report['native_repaints'] = native['counters']
    report['measurement'] = 'Native window on Xvfb' if os.environ.get('DISPLAY') else 'Native desktop window'
    (ROOT/'docs/validation/native-action.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report['native_motion_frame_intervals']))
    assert intervals and len(report['presented_shots']) >= 2, 'No sustained weapon motion was measured'
    assert report['terrain_revision'] > 0, 'Explosions never changed the landscape'
    measured = report['native_motion_frame_intervals']
    assert measured['mean_ms'] < 19 and measured['p95_ms'] < 28, 'Presented motion missed the frame budget'
    assert report['app_update_intervals']['p95_ms'] < 20, 'GUI update cadence fell below its budget'
    assert report['app_update_intervals']['max_ms'] < 65, 'An action blocked the GUI thread'
