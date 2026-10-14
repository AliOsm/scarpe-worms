#!/usr/bin/env python3
"""Alternate packaged Apple/OpenAL Soft combat captures on one Apple silicon runner.

Records comparison timings; the separate packaged benchmark retains its gates.
This measures submissions and device properties, not audible output or scanout.
"""
from pathlib import Path
import argparse
import json
import os
import subprocess
import sys


def distribution(values):
    values = sorted(value for value in values if value is not None)
    if not values:
        return {'n': 0}
    return dict(n=len(values), median=values[len(values)//2],
                p95=values[min(len(values)-1, int(len(values)*.95))], max=values[-1])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    parser.add_argument('--pairs', type=int, default=3)
    args = parser.parse_args()
    assert sys.platform == 'darwin', 'Run this comparison on macOS'
    root = Path(__file__).resolve().parents[1]
    output = root / '.cache/macos-audio-comparison'
    output.mkdir(parents=True, exist_ok=True)
    backends = {
        'apple': '/System/Library/Frameworks/OpenAL.framework/OpenAL',
        'soft': str(args.app.resolve() / 'Contents/Resources/runtime/lib/libopenal.1.dylib'),
    }
    records = []
    for pair in range(args.pairs):
        for backend in (['apple', 'soft'] if pair % 2 == 0 else ['soft', 'apple']):
            report = output / f'{pair+1}-{backend}.json'
            subprocess.run([sys.executable, str(root/'tools/check_rendering.py'),
                '--app', str(args.app.resolve()), '--audio', '--record-only', '--output', str(report)],
                env=os.environ | {'BURROW_OPENAL_LIBRARY': backends[backend]}, cwd=root,
                check=True, timeout=120)
            rendering = json.loads(report.read_text())
            audio = json.loads(report.with_suffix('.audio.json').read_text())
            assert ('OpenAL Soft' in audio['device']['renderer']) == (backend == 'soft')
            assert audio['device']['effect_voices'] == (24 if backend == 'soft' else 12)
            cues = [dict(zip(audio['columns'], row)) for row in audio['cues']]
            record = dict(pair=pair+1, backend=backend, device=audio['device'], totals=audio['totals'],
                submit_ms=distribution(row['submit_ms'] for row in cues if row['reason'] in ('played', 'steal')),
                delayed_lateness_ms=distribution(row['lateness_ms'] for row in cues if row['origin']=='delayed' and row['reason'] in ('played', 'steal')),
                scenarios=rendering['scenarios'], audio_stress=rendering['audio_stress'])
            records.append(record)
            (output/'summary.json').write_text(json.dumps(records, indent=2)+'\n')
            print(json.dumps({k:v for k,v in record.items() if k not in ('scenarios','audio_stress')}), flush=True)


if __name__ == '__main__':
    main()
