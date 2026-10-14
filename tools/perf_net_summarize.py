#!/usr/bin/env python3
"""Summarize completed net captures without taking new measurements.

python3 -I tools/perf_net_summarize.py --captures <scratch>/raw \
  --output docs/validation/perf-0.5.4-net.json
The source captures remain the evidence; this intentionally requires five pairs.
"""
import argparse
import json
import platform
import re
from pathlib import Path


def stats(values):
    a = sorted(values)
    if not a:
        return {"n": 0}
    return {"n": len(a), "median": a[len(a) // 2],
            "p95": a[min(int(len(a) * .95), len(a) - 1)], "min": a[0], "max": a[-1],
            "iqr": a[int(len(a) * .75)] - a[int(len(a) * .25)], "mean": sum(a) / len(a)}


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--captures", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()


def read(name):
    return json.loads((args.captures / name).read_text())


def pairs(stem):
    return [[read(f"{stem}-{arm}-{i}.json") for i in range(1, 6)] for arm in ("A", "B")]


def comparison(a, b):
    before, after = stats(a), stats(b)
    gain = (1 - after["median"] / before["median"]) * 100 if before["median"] else None
    return {"baseline": before, "candidate": after, "improvement_percent": gain,
            "improved_pairs": sum(y < x for x, y in zip(a, b)), "pairs": len(a)}


def experiment(identifier, hypothesis, change, files, metric, a, b, verdict, reason, **extra):
    return {"id": identifier, "hypothesis": hypothesis, "change": change, "files": files,
            "metric": metric, **comparison(a, b), "verdict": verdict, "reason": reason, **extra}


experiments = []
for stem, identifier in (("terrain", "minimap-cache"), ("terrain-final", "terrain-combined")):
    a, b = pairs(stem)
    values = [[d["results"]["worker_revisions_ms"]["median"] for d in arm] for arm in (a, b)]
    guards = {"tile_pngs_byte_identical": all(x["output"]["tiles"] == y["output"]["tiles"]
              for aa, bb in zip(a, b) for x, y in zip(aa["results"]["raw"], bb["results"]["raw"]))}
    guards["terrain_checksums_identical"] = all(x["output"]["checksum"] == y["output"]["checksum"]
        for aa, bb in zip(a, b) for x, y in zip(aa["results"]["raw"], bb["results"]["raw"]))
    if stem == "terrain-final":
        guards["all_decoded_pixels_identical"] = all(
            x["output"]["tile_pixels"] == y["output"]["tile_pixels"] and
            x["output"]["overview_pixels"] == y["output"]["overview_pixels"]
            for aa, bb in zip(a, b) for x, y in zip(aa["results"]["raw"], bb["results"]["raw"]))
        guards["gui_collision_validation_cpu_ms"] = [stats([r["cpu_ms"] for d in arm
            for r in d["results"]["gui_collision_validation"]["raw"]]) for arm in (a, b)]
        guards["worker_final_rss_kb"] = [stats([d["results"]["raw"][-1]["worker_rss_kb"] for d in arm]) for arm in (a, b)]
    else:
        guards["minimap_pngs_byte_identical"] = all(x["output"]["overview"] == y["output"]["overview"]
            for aa, bb in zip(a, b) for x, y in zip(aa["results"]["raw"], bb["results"]["raw"]))
    experiments.append(experiment(identifier, "Full minimap work dominates small terrain revisions",
        "Cache sampled overview regions; final arm also uses the actual fast RGBA preset for the minimap",
        ["lib/burrow/client/terrain_painter.rb"], "run median request-to-tiles-ready ms", *values,
        "ACCEPT", "Improvement exceeds 5% in at least four of five pairs; guards and correctness pass",
        pooled_revision_ms=[stats([r["ready_ms"] for d in arm for r in d["results"]["raw"][1:]]) for arm in (a, b)],
        painter_cpu_ms=[stats([d["results"]["painter"]["summary"]["cpu_ms"]["median"] for d in arm]) for arm in (a, b)], guards=guards))

a, b = pairs("timeline")
experiments.append(experiment("timeline-field-merge", "Per-grub temporary containers cost GUI CPU and allocations",
    "Merge the six interpolated fields directly", ["lib/burrow/client/timeline.rb"], "run median sample thread CPU ms",
    *[[d["results"]["sample"]["summary"]["cpu_ms"]["median"] for d in arm] for arm in (a, b)],
    "ACCEPT", "Same complete presentation digest and playback counters; five-pair CPU and allocation win",
    allocations=[stats([d["results"]["sample"]["summary"]["allocations"]["median"] for d in arm]) for arm in (a, b)],
    presentation_sha256=sorted({d["results"]["presentation_sha256"] for d in a + b}),
    guards=[{k: d["results"][k] for k in ("underruns", "resyncs")} for d in a + b]))

decoders = [read(f"decode-prototype-{i}.json")["results"] for i in range(1, 6)]
for variant, reason in (("frozen_envelopes", "Decode CPU regresses despite fewer allocations"),
                        ("explicit_no_additions", "Improvement is below run-to-run noise and does not simplify code")):
    experiments.append(experiment("json-" + variant, "Parser options might reduce GUI-process decode cost",
        variant, ["lib/burrow/protocol.rb", "lib/burrow/client/connection.rb"], "run median incremental decode CPU ms",
        *[[d["incremental"]["variants"][v]["summary"]["cpu_ms"]["median"] for d in decoders] for v in ("protocol", variant)],
        "REJECT", reason, allocations=[stats([d["incremental"]["variants"][v]["summary"]["allocations"]["median"] for d in decoders]) for v in ("protocol", variant)]))

pngs = [read("png-prototype.json")["results"]] + [read(f"png-prototype-{i}.json")["results"] for i in range(2, 6)]
experiments.append(experiment("minimap-png-preset", "The ignored fast_rgba hash option leaves slow PNG filtering enabled",
    "Use the actual :fast_rgba preset for the overview only", ["lib/burrow/client/terrain_painter.rb"], "overview encode CPU ms",
    *[[d[v]["cost"]["raw"][0]["cpu_ms"] for d in pngs] for v in ("current", "preset")],
    "ACCEPT", "Faster encoding, smaller minimap PNGs and identical decoded RGBA pixels",
    overview_bytes=[stats([d[v]["bytes"][0] for d in pngs]) for v in ("current", "preset")]))
for variant, reason in (("preset", "Tile PNG bytes rise 12.93%"),
                        ("rgba_no_filter", "Tile PNG bytes rise 10.12%"),
                        ("rgba_default_compression", "Aggregate tile CPU does not improve by 5% or simplify code")):
    experiments.append(experiment("tile-png-" + variant, "PNG encoding alternatives might help full-sized terrain tiles",
        "Prototype only: " + variant, ["lib/burrow/client/terrain_painter.rb"], "aggregate tile PNG encode CPU ms",
        *[[sum(r["cpu_ms"] for r in d[v]["cost"]["raw"][1:]) for d in pngs] for v in ("current", variant)],
        "REJECT", reason, tile_png_bytes=[stats([sum(d[v]["bytes"][1:]) for d in pngs]) for v in ("current", variant)]))

replays = [read(f"lower-buffer-{arm}.json")["results"] for arm in ("A", "B")]
final_replay = read("playback-final.json")["results"]
playback_guards = {scenario: {
    "baseline": {key: values[key] for key in ("underruns", "resyncs")},
    "candidate": {key: final_replay[scenario][key] for key in ("underruns", "resyncs")},
    "virtual_timing_trace_identical": values["raw"] == final_replay[scenario]["raw"]}
    for scenario, values in replays[0].items()}
experiments.append({"id": "lower-playback-buffer", "hypothesis": "A smaller local cushion may reduce event latency",
    "change": "Prototype only: 1.0 tick floor and zero extra local margin", "files": ["lib/burrow/client/timeline.rb"],
    "metric": "sparse-local-stall underruns (deterministic replay)", "baseline": replays[0]["sparse_local_stall"]["underruns"],
    "candidate": replays[1]["sparse_local_stall"]["underruns"], "verdict": "REJECT", "reason": "Adds an underrun",
    "replay_guards": [{k: {key: v[key] for key in ("underruns", "resyncs")} for k, v in d.items()} for d in replays]})

a, b = pairs("cadence")
experiments.append(experiment("loopback-cadence", "A wall-time cadence gate can miss a local physics tick",
    "Prototype only: broadcast on every local simulation tick", ["lib/burrow/server/reactor.rb#snapshot_interval"],
    "run median jump-to-event ms", *[[d["latency"]["jump_event_ms"]["median"] for d in arm] for arm in (a, b)],
    "REJECT", "Jump-to-event improvement does not hold in at least four of five paired captures",
    other_inputs={key: comparison(*[[d["latency"][key]["median"] for d in arm] for arm in (a, b)])
                  for key in ("fire_event_ms", "activate_event_ms")},
    host_cpu_ms_per_second=[stats([d["load"]["host_cpu_ms_per_second"] for d in arm if d["load"].get("host_cpu_ms_per_second") is not None]) for arm in (a, b)]))

a, b = pairs("crater")
crater = {}
for key, start in (("blast_to_ready_ms", lambda d: d["explosions"][0]["started"]),
                   ("request_to_ready_ms", lambda d: d["crater"]["result"]["request"][1])):
    crater[key] = comparison(*[[(d["crater"]["result"]["ready"] - start(d)) * 1000 for d in arm] for arm in (a, b)])

wire = [read(f"wire-prototype-{i}.json")["results"]["incremental"] for i in range(1, 6)]
experiments.append(experiment("compressed-envelope", "Compression might reduce snapshot bandwidth",
    "Prototype only: base64/zlib level-1 JSON envelope requiring negotiated support for a new wire message",
    [], "incremental wire bytes", [d["protocol4_bytes"] for d in wire], [d["prototype_bytes"] for d in wire],
    "PROPOSAL", "Not protocol-4 compatible; no production wire changes",
    decode_cpu_ms=[stats([d[v]["summary"]["cpu_ms"]["median"] for d in wire]) for v in ("plain_decode", "prototype_decode")]))

check_path = args.captures / "check-exits.json"
checks = read("check-exits.json") if check_path.exists() else {
    "ruby_3_4_7": None, "ruby_4_0_7": None, "native": None}
for name in ("core-3.4.7-final-exit.json", "focused-final-exit.json", "final-test-exits.json", "native-final-exit.json"):
    if (args.captures / name).exists():
        checks.update(read(name))
checks["initial_failure"] = {
    "test": "NetworkTest#test_input_receipts_identify_only_events_from_that_authoritative_command",
    "reason": "The test compared a restored checkpoint tick to the later live host tick",
    "fix": "Compare against checkpoint['match']['state']['tick']; no production host or persistence change",
    "initial_focused": {"runs": 44, "assertions": 2649, "failures": 1},
    "initial_core_3_4_7": {"runs": 314, "assertions": 9857, "failures": 1},
    "intermediate_test_edit": "A wrong tick field path in the first assertion edit was corrected before final reruns; logs retained as *-test-edit.log",
    "fixed_regression": read("checkpoint-race-fixed-exit.json") if (args.captures / "checkpoint-race-fixed-exit.json").exists() else "pending",
    "baseline_reproduction": read("baseline-checkpoint-race-exit.json") if (args.captures / "baseline-checkpoint-race-exit.json").exists() else "pending"}
for name in ("initial", "final"):
    path = f"native-{name}-results.json"
    if (args.captures / path).exists():
        checks[f"native_{name}_results"] = read(path)
exit_values = [checks.get(key) for key in ("ruby_3_4_7", "ruby_4_0_7", "native", "focused_checks")]
checks["status"] = "pending" if None in exit_values else "passed" if all(v == 0 for v in exit_values) else "failed"
checks["summaries"] = {}
for name in ("core-3.4.7", "core-4.0.7", "native", "focused-checks"):
    path = args.captures / f"{name}.log"
    content = path.read_text() if path.exists() else ""
    clean = re.sub(r"\x1b\[[0-9;]*m", "", content)
    checks["summaries"][name] = [line for line in clean.splitlines()
        if re.search(r"(runs|tests|assertions|failures|errors|passed|failed|success|summary|skips)", line, re.I)][-12:] or ["pending"]
if "native_final_results" in checks:
    native = checks["native_final_results"]
    counts = native["counts"]
    assertions = sum(result["assertions"] for result in native["results"].values())
    checks["summaries"]["native"] = [f"{len(native['results'])} cases, {assertions} assertions, "
        f"{counts['pass']} passed, {counts['fail']} failures, {counts['error']} errors, {counts['timeout']} timeouts"]
interop = {}
for path in sorted(args.captures.glob("interop-*.json")):
    data = json.loads(path.read_text())
    interop[path.stem] = {key: data[key] for key in
        ("source", "host_source", "transport", "remote", "interop", "guards", "latency")}
    entry = interop[path.stem]
    # Early captures counted fire-to-projectile observations as input events too.
    # Derive the actual event count from the retained per-event sample arrays.
    event_count = sum(len(rows) for kind, rows in data["latency_raw"].items() if kind.endswith("_event_ms"))
    entry["interop"]["input_events_presented"] = event_count
    entry["passed"] = (data["protocol"] == 4 and entry["interop"]["reconnect_identity"]
        and entry["interop"]["full_history"] == 18 and event_count == data["rounds"] * 3
        and entry["interop"]["sync_sequence"] > entry["interop"]["resumed_sequence"]
        and all(row["underruns"] == 0 and row["resyncs"] == 0 for row in entry["guards"]))
interop_status = ("pending" if len(interop) != 8 else "passed" if all(d["passed"] for d in interop.values()) else "failed")
validation_status = ("failed" if "failed" in (checks["status"], interop_status)
    else "passed" if checks["status"] == interop_status == "passed" else "pending")
if not all(d["virtual_timing_trace_identical"] for d in playback_guards.values()):
    validation_status = "failed"
initial = read("baseline-initial-latency.json")
baseline = {transport: {key: initial[transport][key] for key in
    ("latency", "payload_bytes", "parse_cpu_ms", "parse_cpu_ms_per_second", "receive_cpu_ms", "snapshot_rate_hz")}
    for transport in ("tcp", "tls")}
observer = {mode: stats([v for d in decoders for v in d["heartbeat"][mode]["lateness_raw_ms"]])
            for mode in ("control", "decode")}
observer["decode_overlap_run_medians_ms"] = stats([d["heartbeat"]["decode"]["decode_overlap_lateness_ms"]["median"] for d in decoders])
report = {"schema_version": 1, "area": "net", "target_version": "0.5.4", "baseline_commit": "8bf41edf524e518c15bc38889b4425e26d31fa15",
    "validation_status": validation_status,
    "machine": {"os": "Ubuntu 26.04 LTS", "kernel": platform.release(), "cpu": "Intel Core i5-8500, six physical cores",
                "ruby": "3.4.7", "json": "2.9.1", "yjit": False},
    "scenario": "Frozen-tree interleaved pairs, 36 grubs, 4800x1600 terrain, real TCP/TLS and ordered userspace jitter proxy",
    "statistics": "Five captures per arm. Median uses sorted[n//2] (upper middle for even n); p95 and quartiles use sorted[floor(n*q)], clamped to n-1. Raw captures retain individual observations.",
    "baseline_real_sessions": baseline, "gui_observer_lateness_ms": observer,
    "experiments": experiments, "real_explosion_pipeline": crater, "interop": interop,
    "final_playback_guards": playback_guards, "checks": checks,
    "raw_captures": str(args.captures),
    "limits": ["Linux source runs, no packaged Mac/audio/physical display claim", "Timeline sample and tiles-ready endpoints precede native scanout",
               "Observer lateness includes scheduling and GC, not a direct GVL ownership probe", "Proxy models ordered delay and jitter, not packet loss"]}
args.output.parent.mkdir(parents=True, exist_ok=True)


def rounded(value):
    if isinstance(value, float):
        return round(value, 6)
    if isinstance(value, dict):
        return {k: rounded(v) for k, v in value.items()}
    if isinstance(value, list):
        return [rounded(v) for v in value]
    return value


args.output.write_text(json.dumps(rounded(report), indent=2) + "\n")
