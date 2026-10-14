#!/usr/bin/env python3
"""Summarize retained perf_audio captures; no timing work is performed here.

python3 -I tools/perf_audio_summary.py /scratch/audio/raw --output /scratch/summary.json
Statistics summarize five independent capture values (each capture's median
where relevant), not a pooled distribution that hides run-to-run variation.
"""
import argparse
import json
import math
from pathlib import Path
import statistics


def stats(values):
    values = sorted(values)
    if not values:
        return {"n": 0}
    return dict(n=len(values), median=statistics.median(values),
                p95=values[math.ceil(len(values) * .95) - 1],
                min=values[0], max=values[-1],
                iqr=values[int(len(values) * .75)] - values[int(len(values) * .25)])


def compare(root, prefix_a, prefix_b, metric, higher=False):
    a = [json.loads((root / f"{prefix_a}-{i}.json").read_text()) for i in range(1, 6)]
    b = [json.loads((root / f"{prefix_b}-{i}.json").read_text()) for i in range(1, 6)]
    av, bv = list(map(metric, a)), list(map(metric, b))
    med_a, med_b = statistics.median(av), statistics.median(bv)
    change = ((med_b - med_a) if higher else (med_a - med_b)) / abs(med_a) if med_a else None
    better = sum(y > x if higher else y < x for x, y in zip(av, bv)) / len(av)
    separate = min(bv) > max(av) if higher else max(bv) < min(av)
    return dict(baseline=stats(av), candidate=stats(bv), baseline_runs=av, candidate_runs=bv,
                median_improvement_percent=change * 100 if change is not None else None,
                paired_direction=better, nonoverlapping_improvement=separate,
                primary_rule_pass=bool(separate or (change is not None and change >= .05 and better >= .8)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = {}
    cases = {
        "voice_steals": ("voices-baseline", "voices-candidate", lambda d: len(d["steals"]), False),
        "voice_cut_ms": ("voices-baseline", "voices-candidate", lambda d: sum(s["remaining_ms"] for s in d["steals"]), False),
        "voice_play_cpu_ms": ("voices-baseline", "voices-candidate", lambda d: d["metrics"]["play_cpu_ms"]["median"], False),
        "voice_burst_p95_ms": ("voices-baseline", "voices-candidate", lambda d: d["metrics"]["burst_ms"]["p95"], False),
        "voice_frame_p95_ms": ("voices-baseline", "voices-candidate", lambda d: d["metrics"]["frame_interval_ms"]["p95"], False),
        "deadline_median_ms": ("deadline-baseline", "deadline-candidate", lambda d: d["metrics"]["delayed_lateness_ms"]["median"], False),
        "deadline_p95_ms": ("deadline-baseline", "deadline-candidate", lambda d: d["metrics"]["delayed_lateness_ms"]["p95"], False),
        "wave_tail_ratio": ("wave-baseline", "wave-candidate", lambda d: d["tail_ratio"], True),
        "wave_visibility_ms": ("wave-baseline", "wave-candidate", lambda d: d["submission_to_file_visibility_ms"], False),
        "selection_cpu_ms": ("selection-voices", "selection-selection", lambda d: d["thread_cpu_ms"], False),
        "selection_allocations": ("selection-voices", "selection-selection", lambda d: d["allocated"], False),
        "final_selection_cpu_ms": ("final-selection-baseline", "final-selection-candidate", lambda d: d["thread_cpu_ms"], False),
        "final_selection_wall_ms": ("final-selection-baseline", "final-selection-candidate", lambda d: d["wall_ms"], False),
        "final_selection_process_cpu_ms": ("final-selection-baseline", "final-selection-candidate", lambda d: d["process_cpu_ms"], False),
        "final_selection_allocations": ("final-selection-baseline", "final-selection-candidate", lambda d: d["allocated"], False),
        "log_play_us": ("log-off", "log-on", lambda d: d["us_per_operation"], False),
        "log_frame_us": ("log-frame-off", "log-frame-on", lambda d: d["us_per_operation"], False),
        "log_frame_allocations": ("log-frame-off", "log-frame-on", lambda d: d["allocated"], False),
        "final_log_play_us": ("final-log-off", "final-log-on", lambda d: d["us_per_operation"], False),
        "final_log_cpu_us": ("final-log-off", "final-log-on", lambda d: d["thread_cpu_ms"] * 1000 / d["operations"], False),
        "final_log_process_cpu_ms": ("final-log-off", "final-log-on", lambda d: d["process_cpu_ms"], False),
        "final_log_allocations": ("final-log-off", "final-log-on", lambda d: d["allocated"], False),
        "final_log_close_ms": ("final-log-off", "final-log-on", lambda d: d["close_ms"], False),
    }
    # Combined shipping patch with diagnostics on, against frozen 0.5.3.
    for name, key, statistic in (
        ("play_cpu", "play_cpu_ms", "median"), ("play_wall", "play_ms", "median"),
        ("burst_p95", "burst_ms", "p95"), ("frame_p95", "frame_interval_ms", "p95"),
    ):
        cases[f"shipping_{name}_ms"] = (
            "shipping-combat-baseline", "shipping-combat-candidate",
            lambda d, key=key, statistic=statistic: d["metrics"][key][statistic], False)
    cases["shipping_steals"] = ("shipping-combat-baseline", "shipping-combat-candidate", lambda d: len(d["steals"]), False)
    cases["shipping_cut_ms"] = ("shipping-combat-baseline", "shipping-combat-candidate", lambda d: sum(s["remaining_ms"] for s in d["steals"]), False)
    for statistic in ("median", "p95"):
        cases[f"shipping_deadline_{statistic}_ms"] = (
            "shipping-deadline-baseline", "shipping-deadline-candidate",
            lambda d, statistic=statistic: d["metrics"]["delayed_lateness_ms"][statistic], False)
    for name, (a, b, metric, higher) in cases.items():
        try:
            result[name] = compare(args.directory, a, b, metric, higher)
        except FileNotFoundError:
            result[name] = {"status": "pending"}
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
