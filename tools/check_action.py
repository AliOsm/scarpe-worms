#!/usr/bin/env python3
"""Measure frames actually presented by the native window during moving action.
On Linux: xvfb-run -a python3 tools/check_action.py. No headless paint shortcuts.
"""
from pathlib import Path
import json, os, statistics, subprocess, tempfile
from check_rendering import frame_unix, moving_intervals
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
    # Preserve diagnostic rows before the temporary native logs disappear.
    raw = ROOT/'.cache/native-action.raw.json'
    raw.parent.mkdir(parents=True, exist_ok=True)
    raw.write_text(json.dumps(dict(report=report, native=native))+'\n')
    samples = report.pop('motion_samples')
    rows = [row for row in native['frames']
            if samples[0][0] <= frame_unix(row, native['started_unix']) <= samples[-1][0]]
    intervals = moving_intervals(rows, samples, native['started_unix'])
    assert intervals, 'No sustained visible motion was measured'
    report['native_motion_frame_intervals'] = stats(intervals)
    report['motion_analysis_version'] = 3
    report['raw_capture'] = str(raw)
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
