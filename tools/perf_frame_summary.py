#!/usr/bin/env python3
"""Summarize paired FrameProfile captures without pooling different stages.

Example (paths are paired in the supplied order):
  python3 tools/perf_frame_summary.py --baseline /captures/frame-A{1,2,3,4,5} \
    --candidate /captures/frame-B{1,2,3,4,5} --output /captures/comparison.json

Each directory contains profile.json and native PNG fixtures. Retains per-run
median/p95/max and aggregates each statistic across runs, with paired direction.
CPU is thread CPU; allocations/GC include every GUI-process thread. These are
preparation costs, not acoustic latency or presented frame intervals.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import statistics


def stats(values):
    values = sorted(values)
    if not values:
        return {"n": 0}
    percentile = lambda fraction: values[min(len(values) - 1, math.ceil(len(values) * fraction) - 1)]
    return {"n": len(values), "median": statistics.median(values), "p95": percentile(.95),
            "min": values[0], "max": values[-1], "iqr": percentile(.75) - percentile(.25)}


def capture(directory):
    directory = Path(directory)
    data = json.loads((directory / "profile.json").read_text())
    rows = [dict(zip(data["columns"], row)) for row in data["samples"]]
    result = {"path": str(directory), "fixture": data.get("fixture", "frame-work"), "stages": {},
              "screenshots": {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(directory.glob("*.png"))}}
    for stage, counters in data["stages"].items():
        samples = [row for row in rows if row["stage"] == stage]
        methods = {}
        for method in sorted({row["method"] for row in samples}):
            selected = [row for row in samples if row["method"] == method]
            methods[method] = {key: stats([row[key] for row in selected]) for key in
                               ("wall_ms", "cpu_ms", "allocated_objects", "props", "creates", "destroys", "reparents", "gc_ms")
                               if key in selected[0]}
        counts = {key: counters["after"][key] - counters["before"][key] for key in
                  ("total_allocated_objects", "minor_gc_count", "major_gc_count", "time")}
        native = {key: counters["native_after"].get(key, 0) - counters.get("native_before", {}).get(key, 0)
                  for key in ("create", "destroy", "reparent")} if "native_after" in counters else {}
        result["stages"][stage] = {"methods": methods, "gc": counts, "native": native,
                                    "heap_live_slots_after": counters["after"]["heap_live_slots"],
                                    "slowest_frames": sorted((row for row in samples if row["method"] == "Scene#render"),
                                                             key=lambda row: -row["wall_ms"])[:5]}
    return result


def comparison(before, after):
    wins = sum(b < a for a, b in zip(before, after))
    base, candidate = stats(before), stats(after)
    return {"baseline": base, "candidate": candidate, "pairs_better": wins, "pairs": len(before),
            "median_improvement_percent": 100 * (1 - candidate["median"] / base["median"]) if base["median"] else None}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", nargs="+", required=True)
    parser.add_argument("--candidate", nargs="+", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    if len(args.baseline) != len(args.candidate):
        parser.error("baseline and candidate must have equal run counts")
    before, after = [capture(path) for path in args.baseline], [capture(path) for path in args.candidate]
    comparisons = {}
    for stage in before[0]["stages"]:
        stage_result = {}
        for method in before[0]["stages"][stage]["methods"]:
            result = {}
            for metric in before[0]["stages"][stage]["methods"][method]:
                result[metric] = {stat: comparison(
                    [run["stages"][stage]["methods"][method][metric][stat] for run in before],
                    [run["stages"][stage]["methods"][method][metric][stat] for run in after])
                    for stat in ("median", "p95", "max")}
            stage_result[method] = result
        for category in ("gc", "native"):
            stage_result[category] = {key: comparison([run["stages"][stage][category][key] for run in before],
                                                     [run["stages"][stage][category][key] for run in after])
                                      for key in before[0]["stages"][stage][category]}
        comparisons[stage] = stage_result
    reference = before[0]["screenshots"]
    matches = bool(reference) and all(run["screenshots"] == reference for run in before + after)
    report = {"baseline": before, "candidate": after, "comparisons": comparisons,
              "all_native_screenshots_identical": matches, "reference_sha256": reference}
    Path(args.output).write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"pairs": len(before), "all_native_screenshots_identical": matches, "output": args.output}))


if __name__ == "__main__":
    main()
