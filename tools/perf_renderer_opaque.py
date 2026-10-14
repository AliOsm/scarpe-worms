#!/usr/bin/env python3
"""Summarize interleaved baseline/candidate renderer captures.

Usage (after ``run-opaque-ab.sh``):
  python3 -I tools/perf_renderer_opaque.py \
    --input <scratch>/renderer/captures/opaque-ab

The input contains the regular ``check_rendering.py`` JSON and its adjacent
``.raw.json`` files.  Stage intervals come from the journey timestamps; native
frame rows are selected by their live Unix timestamp (column 7 in the patched
format).  No source tree or game code is loaded, so this remains useful when
comparing binaries built in separate worktrees.
"""

from __future__ import annotations

import argparse
import json
import math
import statistics
from pathlib import Path
from typing import Any, Iterable


STAGES = ("combat", "pan", "zoom", "zoom_sweep")
ARMS = ("A", "B")


def percentile(values: Iterable[float], q: float) -> float | None:
    xs = sorted(values)
    if not xs:
        return None
    # Match the rendering report's nearest-rank convention.
    return xs[min(len(xs) - 1, int(len(xs) * q))]


def stats(values: Iterable[float]) -> dict[str, Any]:
    xs = list(values)
    return {
        "n": len(xs),
        "mean": statistics.mean(xs) if xs else None,
        "median": statistics.median(xs) if xs else None,
        "p95": percentile(xs, 0.95),
        "p99": percentile(xs, 0.99),
        "max": max(xs) if xs else None,
        "over33": sum(x > 33.4 for x in xs),
        "over50": sum(x > 50.0 for x in xs),
    }


def run_number(path: Path) -> int:
    return int(path.stem.rsplit("-", 1)[1])


def load_runs(root: Path) -> dict[str, dict[int, tuple[dict[str, Any], dict[str, Any]]]]:
    result: dict[str, dict[int, tuple[dict[str, Any], dict[str, Any]]]] = {}
    for arm in ARMS:
        result[arm] = {}
        paths = [path for path in root.glob(f"{arm}-*.json") if not path.name.endswith(".raw.json")]
        for path in sorted(paths, key=run_number):
            raw_path = path.with_suffix(".raw.json")
            if not raw_path.exists():
                raise SystemExit(f"missing raw capture for {path}")
            result[arm][run_number(path)] = (
                json.loads(path.read_text()),
                json.loads(raw_path.read_text()),
            )
    if not result["A"] or not result["B"]:
        raise SystemExit(f"expected A and B captures in {root}")
    return result


def stage_rows(raw: dict[str, Any], stage: str) -> list[list[float]]:
    interval = next(s for s in raw["journey"]["stages"] if s["name"] == stage)
    lo, hi = interval["from"], interval["to"]
    rows = []
    for row in raw["native"].get("frames", []):
        # Patch 0019+ appends a live Unix timestamp.  Older rows cannot be
        # correlated reliably, but all captures in this experiment have it.
        if len(row) > 7 and lo <= row[7] <= hi:
            rows.append(row)
    return rows


def native_stage(raw: dict[str, Any], stage: str) -> dict[str, Any]:
    rows = stage_rows(raw, stage)
    # Patched frame rows are parse, apply, layout, paint, present, req, at,
    # unix.  Keep the names from the capture when available for resilience.
    names = raw["native"].get("frame_columns", [])
    index = {name: i for i, name in enumerate(names)}
    if not index:
        index = {name: i for i, name in enumerate(("at", "parse", "apply", "layout", "paint", "present", "req", "unix"))}
    out: dict[str, Any] = {"frames": len(rows)}
    for name in ("layout", "paint", "present"):
        i = index.get(name)
        out[name] = stats(row[i] for row in rows if i is not None and len(row) > i)
    cpu_rows = raw["native"].get("frame_cpu", [])
    cpu_names = raw["native"].get("frame_cpu_columns", [])
    ci = {name: i for i, name in enumerate(cpu_names)}
    # frame_cpu has no timestamp; align it with the full frame array by index.
    selected_indices = {
        i for i, row in enumerate(raw["native"].get("frames", []))
        if len(row) > 7 and next(s for s in raw["journey"]["stages"] if s["name"] == stage)["from"] <= row[7] <= next(s for s in raw["journey"]["stages"] if s["name"] == stage)["to"]
    }
    for name in ("layout", "paint", "present"):
        i = ci.get(name)
        if i is not None:
            out[f"cpu_{name}"] = stats(row[i] for n, row in enumerate(cpu_rows) if n in selected_indices and len(row) > i)
    return out


def summary_stage(data: dict[str, Any], stage: str) -> dict[str, Any]:
    src = data["scenarios"][stage]
    return {
        "presented": src.get("presented_intervals", {}),
        "active": src.get("active_motion_intervals", {}),
        "paint": src.get("paint", {}),
        "present": src.get("present", {}),
        "app_update": src.get("app_update", {}),
    }


def pct_change(a: float | None, b: float | None) -> float | None:
    if a is None or b is None or a == 0:
        return None
    return (b / a - 1.0) * 100.0


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", type=Path, required=True)
    ap.add_argument("--json", type=Path, help="also write the machine-readable summary")
    args = ap.parse_args()
    runs = load_runs(args.input)
    report: dict[str, Any] = {"input": str(args.input), "arms": {}, "paired": {}}

    for arm in ARMS:
        report["arms"][arm] = {}
        print(f"\n{arm}: {len(runs[arm])} runs")
        for n, (data, raw) in sorted(runs[arm].items()):
            report["arms"][arm][str(n)] = {"counters": data.get("counters", {}), "stages": {}}
            print(f"  run {n}: images_resampled={data.get('counters', {}).get('images_resampled')}")
            for stage in STAGES:
                report["arms"][arm][str(n)]["stages"][stage] = {
                    "summary": summary_stage(data, stage),
                    "native": native_stage(raw, stage),
                }
                p = data["scenarios"][stage]["presented_intervals"]
                native = report["arms"][arm][str(n)]["stages"][stage]["native"]
                print(
                    f"    {stage}: presented {p.get('mean_ms', math.nan):.3f}/"
                    f"{p.get('p95_ms', math.nan):.3f}/{p.get('max_ms', math.nan):.3f} ms "
                    f">33={p.get('over_33ms', 0)}; "
                    f"layout/paint/present means "
                    f"{native['layout']['mean'] if native['layout']['mean'] is not None else math.nan:.3f}/"
                    f"{native['paint']['mean'] if native['paint']['mean'] is not None else math.nan:.3f}/"
                    f"{native['present']['mean'] if native['present']['mean'] is not None else math.nan:.3f}"
                )

    for stage in STAGES:
        report["paired"][stage] = {}
        print(f"\n{stage} paired candidate vs baseline (negative is faster)")
        for family, metric in (("summary", "presented"), ("summary", "paint"), ("summary", "present"), ("native", "layout"), ("native", "paint"), ("native", "present")):
            changes: list[float] = []
            for n in sorted(set(runs["A"]) & set(runs["B"])):
                a = report["arms"]["A"][str(n)]["stages"][stage][family][metric]["mean_ms" if family == "summary" else "mean"]
                b = report["arms"]["B"][str(n)]["stages"][stage][family][metric]["mean_ms" if family == "summary" else "mean"]
                change = pct_change(a, b)
                if change is not None:
                    changes.append(change)
            if changes:
                item = {"changes_pct": changes, "median_pct": statistics.median(changes), "wins": sum(x < 0 for x in changes), "pairs": len(changes)}
                report["paired"][stage][f"{family}_{metric}"] = item
                print(f"  {family}.{metric}: {[round(x, 2) for x in changes]} median={item['median_pct']:.2f}% wins={item['wins']}/{item['pairs']}")

    if args.json:
        args.json.write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
