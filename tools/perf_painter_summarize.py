#!/usr/bin/env python3
"""Summarize paired captures, retaining distributions and pixel comparisons.

python3 -I tools/perf_painter_summarize.py --scratch /scratch/painter \
    --output /scratch/painter/comparisons.json
Captures are named <experiment>-<app|work|crater>-<A|B>-<1..5>.json.
Quantiles use linear interpolation; p95 across five runs is descriptive.
The versioned handoff adds verdicts, checks and limitations to this evidence.
"""
import argparse
import json
import statistics
from pathlib import Path


def quantile(values, q):
    a = sorted(values)
    at = (len(a) - 1) * q
    lo = int(at)
    hi = min(lo + 1, len(a) - 1)
    return a[lo] + (a[hi] - a[lo]) * (at - lo)


def stats(values):
    return dict(n=len(values), median=statistics.median(values),
                p95=quantile(values, .95), min=min(values), max=max(values),
                iqr=quantile(values, .75) - quantile(values, .25), values=values)


def compare(a, b):
    median_a, median_b = statistics.median(a), statistics.median(b)
    return dict(baseline=stats(a), candidate=stats(b),
                improvement_percent=(median_a - median_b) / median_a * 100 if median_a else None,
                lower_pairs=sum(y < x for x, y in zip(a, b)),
                nonoverlapping=max(b) < min(a) or max(a) < min(b))


def metrics(path, mode):
    data = json.loads(path.read_text())
    if mode == 'worker':
        renders = [row for capture in path.parent.glob(path.name + '.worker-*.json')
                   for row in json.loads(capture.read_text())['rows']
                   if row['method'] == 'Burrow::Client::TerrainPainter#render']
        if not renders:
            raise ValueError(f'No completed painter render: {path}')
        # The short-lived lobby preview is normally cancelled. If it completed,
        # the battle render has the larger world and dominates this fixed seed.
        render = max(renders, key=lambda row: row['cpu_ms'])
        return dict(battle_painter_wall_ms=render['wall_ms'],
                    battle_painter_cpu_ms=render['cpu_ms'],
                    battle_painter_allocations=render['allocations'],
                    battle_painter_gc_ms=render['gc_ms'])
    if mode == 'app':
        samples = json.loads(path.with_suffix('.processes.json').read_text())
        # A fixed interval of GUI work avoids changing the fraction of idle
        # frames solely because the worker finishes sooner.
        start = data['marks_ms']['first_state']
        frames = [f for f in data['frames'] if start <= f[0] < start + 2000]
        return dict(match_start_ms=data['quick_to_battle_ms'],
                    peak_total_rss_kib=max(sum(p['rss_kib'] for p in s['processes']) for s in samples),
                    peak_worker_rss_kib=max(sum(p['rss_kib'] for p in s['processes'] if p['role'] == 'terrain') for s in samples),
                    loaded_worker_rss_kib=data['battle_rss_kib']['terrain'],
                    gui_load_wall_max_ms=data['load_frame_summary']['wall_ms']['max'],
                    gui_load_cpu_max_ms=data['load_frame_summary']['cpu_ms']['max'],
                    gui_load_interval_max_ms=data['load_frame_summary']['interval_ms']['max'],
                    gui_fixed_cpu_p95_ms=quantile([f[2] for f in frames], .95),
                    gui_fixed_cpu_max_ms=max(f[2] for f in frames))
    if mode == 'work':
        initial = data['records'][0]['rows'][0]
        warm = data['records'][1]['rows'][0]
        crater = data['records'][0]['rows'][1]
        return dict(painter_initial_wall_ms=initial['render']['wall_ms'],
                    painter_initial_cpu_ms=initial['render']['cpu_ms'],
                    kit_cpu_ms=initial['parts']['kit']['cpu_ms'],
                    initial_png_cpu_ms=initial['parts']['save']['cpu_ms'],
                    painter_warm_large_wall_ms=warm['render']['wall_ms'],
                    painter_warm_large_cpu_ms=warm['render']['cpu_ms'],
                    crater_painter_wall_ms=crater['render']['wall_ms'],
                    crater_painter_cpu_ms=crater['render']['cpu_ms'],
                    direct_peak_sampled_rss_kib=max(row['rss_kib'] for case in data['records'] for row in case['rows']))
    crater = data['crater']
    explosion = data['explosions'][0]
    # Match the net harness endpoints: host explode entry and GUI enqueue
    # completion, both ending at the same 60 Hz result poll.
    return dict(explosion_to_tiles_ms=(crater['result']['ready'] - explosion['started']) * 1000,
                request_to_tiles_ms=(crater['result']['ready'] - crater['result']['request'][1]) * 1000)


def pixels(path):
    data = json.loads(path.read_text())
    return [dict(seed=case['seed'], biome=case['biome'], size=case['size'],
                 rows=[dict(revision=row['revision'], checksum=row['checksum'],
                            tiles={k: v['pixels'] for k, v in row['tiles'].items()},
                            overview=row['overview']['pixels']) for row in case['rows']])
            for case in data['records']]


def summarize(scratch):
    raw = scratch / 'raw'
    groups = sorted({p.name.rsplit('-', 3)[0] for p in raw.glob('*-A-[1-5].json')})
    results = {}
    for group in groups:
        modes = {}
        for mode in ['app', 'work', 'crater', 'worker']:
            paths = [[raw / f'{group}-{mode}-{arm}-{i}.json' for i in range(1, 6)] for arm in ['A', 'B']]
            if not all(p.exists() for arm in paths for p in arm):
                continue
            rows = [[metrics(p, mode) for p in arm] for arm in paths]
            modes[mode] = {key: compare([r[key] for r in rows[0]], [r[key] for r in rows[1]]) for key in rows[0][0]}
            if mode == 'work':
                modes[mode]['decoded_pixels_identical'] = all(pixels(a) == pixels(b) for a, b in zip(*paths))
        if modes:
            results[group] = modes
    return results


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--scratch', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.write_text(json.dumps(summarize(args.scratch), indent=2) + '\n')
