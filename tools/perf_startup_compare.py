#!/usr/bin/env python3
"""Summarize paired captures; never silently pool frames as independent trials.

python3 tools/perf_startup_compare.py --baseline '/scratch/A-*.json' \
    --candidate '/scratch/B-*.json' --output /scratch/comparison.json
For the deterministic frame tool, pass globs ending in */profile.json.
All distributions below are across runs. Within-run p95/max are retained as
separate metrics. Positive improvement means the candidate uses less time/memory.
The acceptance rule still requires manual review of guards and correctness.
"""
import argparse
import glob
import json
from pathlib import Path
import statistics


def quantile(values, fraction):
    values = sorted(values)
    at = (len(values) - 1) * fraction
    left = int(at)
    right = min(left + 1, len(values) - 1)
    return values[left] + (values[right] - values[left]) * (at - left)


def stats(values):
    if not values:
        return dict(n=0)
    return dict(n=len(values), median=statistics.median(values), p95=quantile(values, .95),
                min=min(values), max=max(values), iqr=quantile(values, .75) - quantile(values, .25))


def rows_metrics(rows, columns, prefix=''):
    result = {}
    for key, column in columns.items():
        values = [row[column] for row in rows if row[column] is not None]
        if values:
            result.update({prefix + key + '_' + stat: value for stat, value in stats(values).items()
                           if stat in ('median', 'p95', 'max')})
    return result


def metrics(path):
    report = json.loads(path.read_text())
    mode = report.get('scenario')
    if mode == 'terrain':
        return {**{key: statistics.mean(r[key] for r in report['rows'])
                   for key in ('wall_ms', 'cpu_ms', 'allocations', 'gc_ms')},
                'rss_kib': report['rss_kib']}
    if mode == 'host':
        rows = [row for match in report['matches'] for row in match['rows']]
        result = rows_metrics(rows, dict(tick_wall_ms=0, tick_cpu_ms=1, tick_allocations=2, tick_gc_ms=3))
        result.update(rows_metrics([r for r in rows if r[3] > 0], dict(gc_nonzero_ms=3)))
        result.update(rss_kib=report['rss_kib'], tick_cpu_mean=statistics.mean(r[1] for r in rows),
                      gc_total_ms=sum(r[3] for r in rows),
                      create_ms=statistics.mean(m['create']['wall_ms'] for m in report['matches']),
                      restore_ms=statistics.mean(m['restore']['wall_ms'] for m in report['matches']))
        return result
    if mode in ('launch', 'resume'):
        result = dict(menu_ms=report['marks_ms']['menu_frame'], interactive_ms=report['marks_ms']['menu_interactive'],
                      battle_ms=report['quick_to_battle_ms'], require_ms=report['spans']['require_game']['wall_ms'],
                      require_cpu_ms=report['spans']['require_game']['cpu_ms'])
        result.update({f'{stage}_{role}_rss_kib': value for stage in ('menu', 'battle')
                       for role, value in report[stage + '_rss_kib'].items() if value is not None})
        result.update(rows_metrics(report['frames'], dict(frame_wall_ms=1, frame_cpu_ms=2, frame_gc_ms=3, frame_interval_ms=4)))
        result.update(rows_metrics([r for r in report['frames'] if r[3] > 0], dict(gc_nonzero_ms=3)))
        result['gc_total_ms'] = sum(r[3] for r in report['frames'])
        result['frame_cpu_mean'] = statistics.mean(r[2] for r in report['frames'])
        return result
    if 'scenarios' in report:  # Existing unprofiled rendering journey.
        raw = json.loads(path.with_suffix('.raw.json').read_text())['journey']
        result = {}
        for stage in ('combat', 'pan', 'zoom', 'zoom_sweep'):
            rows = [r for r in raw['samples'] if r[1] == stage]
            result.update(rows_metrics(rows, dict(cpu_ms=8, wall_ms=3, gc_ms=5, interval_ms=2), stage + '_'))
        return result
    if 'columns' in report and 'samples' in report:  # FrameProfile fixture.
        result = {}
        for stage in ('static', 'flames', 'pan', 'zoom'):
            rows = [r for r in report['samples'] if r[1] == stage and r[2] == 'Scene#render']
            result.update(rows_metrics(rows, dict(cpu_ms=4, wall_ms=3, allocations=5), stage + '_'))
        return result
    raise ValueError(f'Unknown capture schema: {path}')


def compare(baseline, candidate):
    before, after = [metrics(p) for p in baseline], [metrics(p) for p in candidate]
    if len(before) != len(after):
        raise ValueError('Paired run counts differ')
    result = {}
    for key in sorted(set.intersection(*(set(r) for r in before + after))):
        a, b = [r[key] for r in before], [r[key] for r in after]
        gain = 1 - statistics.median(b) / statistics.median(a) if statistics.median(a) else None
        fraction = sum(y < x for x, y in zip(a, b)) / len(a)
        result[key] = dict(baseline=stats(a), candidate=stats(b), improvement_percent=gain * 100 if gain is not None else None,
                           fraction_pairs_improved=fraction, nonoverlap=max(b) < min(a),
                           clears_primary_threshold=len(a) >= 5 and ((gain is not None and gain >= .05 and fraction >= .8) or max(b) < min(a)))
    return dict(baseline_files=list(map(str, baseline)), candidate_files=list(map(str, candidate)), metrics=result)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--baseline', required=True)
    p.add_argument('--candidate', required=True)
    p.add_argument('--output', type=Path, required=True)
    args = p.parse_args()
    paths = lambda pattern: sorted(Path(p) for p in glob.glob(pattern) if not p.endswith('.processes.json'))
    a, b = paths(args.baseline), paths(args.candidate)
    if not a or not b:
        p.error('No matching captures')
    result = compare(a, b)
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(args.output)


if __name__ == '__main__':
    main()
