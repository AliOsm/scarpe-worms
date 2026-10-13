#!/usr/bin/env python3
"""Check numeric evidence from tools/weapon_lab.rb without opening screenshots.

    python3 tools/check_munitions_lab.py /tmp/munitions-lab
    python3 tools/check_munitions_lab.py /tmp/munitions-lab --weapons rocket grenade

The default requires all 16 munitions. This validates native input outcomes and
turn handover; deterministic unit tests cover trajectories, damage and saves.
"""
from __future__ import annotations

import argparse
from collections import Counter
import json
from pathlib import Path


MUNITIONS = (
    "rocket", "mortar", "homing", "grenade", "cluster", "sticky", "dynamite",
    "mega_bomb", "banana", "holy_bomb", "poison", "airstrike", "mine_strike",
    "napalm", "meteor", "earthquake",
)
BLASTS = {
    "rocket": 1, "mortar": 6, "homing": 1, "grenade": 1, "cluster": 6,
    "sticky": 1, "dynamite": 1, "mega_bomb": 1, "banana": 7, "holy_bomb": 1,
    "airstrike": 5, "napalm": 5, "meteor": 6,
}


def validate(weapon, summary, frames):
    errors = []

    def require(condition, description):
        if not condition:
            errors.append(description)

    require(summary.get("evidence_version") == 2, "rerun lab with evidence_version 2")
    require(bool(frames), "no captured state")
    if not frames:
        return errors
    events = summary.get("events", [])
    captured_events = [event for frame in frames for event in frame.get("events", [])]
    event_ids = [event["id"] for event in events]
    floor = summary.get("event_floor", 0)
    require(event_ids == sorted(set(event_ids)), "event IDs are duplicated or unordered")
    require(all(event_id > floor for event_id in event_ids), "events leaked from a previous weapon")
    require(event_ids == [event["id"] for event in captured_events], "summary/capture events disagree")
    require(summary.get("lost_events") == 0, "event ring overflowed between captures")
    require(all(event["tick"] >= summary.get("start_tick", 0) for event in events), "events predate reset")
    require(summary.get("frames") == len(frames), "summary/capture frame counts disagree")
    require(frames[0].get("phase") == "aiming", "course did not start in aiming")
    require(frames[0].get("turn") == summary.get("start_turn"), "starting turn disagrees")
    require(frames[-1].get("turn") == summary.get("final_turn"), "final turn disagrees")

    fired = [event for event in events if event.get("kind") == "fire" and event.get("weapon") == weapon]
    require(len(fired) == 1, f"expected one accepted {weapon} fire, saw {len(fired)}")
    if fired:
        require(summary.get("fire_event_id") == fired[0]["id"], "accepted fire ID disagrees")
        require(any(event.get("kind") == "turn" and event["id"] > fired[0]["id"] for event in events),
                "no turn handover after accepted fire")
    require(summary.get("final_turn", 0) > summary.get("start_turn", 0), "turn never advanced")
    require(summary.get("turn_completed") is True, "action did not complete a clean turn")
    require(summary.get("phase") == "aiming" and frames[-1].get("phase") == "aiming", "final phase is not aiming")
    require(summary.get("remaining_projectiles") == 0 and not frames[-1].get("projectiles"),
            "projectiles remain at handover")
    require(summary.get("pending_hazards") == 0 and frames[-1].get("flame_count") == 0,
            "flames, triggered mines or moving props remain at handover")
    require(summary.get("moving_worms") == 0, "worms remain in motion at handover")
    require(frames[-1].get("pending_salvos") == 0, "salvos remain at handover")
    before, after = summary.get("start_ammo"), summary.get("final_ammo")
    require(isinstance(before, int) and isinstance(after, int), "ammo evidence is missing")
    if isinstance(before, int) and isinstance(after, int):
        require(after == (before - 1 if before > 0 else before), "ammo was not consumed exactly once (or unlimited preserved)")

    shots = [shot for frame in frames for shot in frame.get("projectiles", []) if shot.get("weapon") == weapon]
    parents = [shot for shot in shots if not shot.get("fragment")]
    if weapon != "earthquake":
        require(bool(parents), "no primary projectile captured")
        require(all("id" in shot and "age" in shot and "life" in shot for shot in shots),
                "projectile identity/age/fuse evidence is missing")
    blasts = [event for event in events if event.get("kind") == "explosion" and event.get("style") == weapon]
    if weapon in BLASTS:
        require(len(blasts) == BLASTS[weapon], f"expected {BLASTS[weapon]} weapon blasts, saw {len(blasts)}")
    if weapon in ("mortar", "cluster", "banana"):
        require(any(shot.get("fragment") and shot.get("stage") == "fragment" for shot in shots),
                "no distinct fragment flight captured")
    if weapon in ("sticky", "dynamite"):
        require(any(shot.get("stuck") for shot in parents), "no attached/resting charge captured")

    if weapon == "homing":
        # Clicking locks a target; it must not itself launch or spend the shot.
        locked = [frame for frame in frames if frame.get("script_action", {}).get("type") == "click"]
        require(bool(locked) and not locked[0].get("projectiles") and
                not any(event.get("kind") == "fire" for event in locked[0].get("events", [])),
                "target-lock click did not precede launch as a separate step")
        require(any(shot.get("homing") and shot.get("age", 0) > 15 for shot in parents),
                "homing motor flight was not captured")
        require(any(abs(shot.get("target_x", 0) - 760) <= 3 and abs(shot.get("target_y", 0) - 888) <= 3 for shot in parents),
                "homing projectile did not retain the clicked target")
    elif weapon == "banana":
        splits = [event for event in events if event.get("kind") == "activate" and
                  event.get("weapon") == weapon and event.get("stage") == "split"]
        require(len(splits) == 1, "expected one accepted early-split activation")
        if splits and fired:
            require(0 < splits[0]["tick"] - fired[0]["tick"] < 5 * 30, "split occurred after the selected fuse")
            require(bool(blasts) and splits[0]["id"] < blasts[0]["id"], "split activation did not precede the blast")
    elif weapon == "holy_bomb":
        choir = [event for event in events if event.get("kind") == "choir" and event.get("weapon") == weapon]
        require(len(choir) == 1, "expected one choir warning")
        require(any(shot.get("stage") == "choir" for shot in parents), "choir warning stage was not captured")
        if choir and blasts:
            require(blasts[0]["tick"] - choir[0]["tick"] >= 18, "choir warning did not precede the blast by 18 ticks")
    elif weapon == "poison":
        require(sum(event.get("kind") == "gas" and event.get("weapon") == weapon for event in events) == 1,
                "expected one poison cloud release")
        require(any(hazard.get("kind") == "gas" for frame in frames for hazard in frame.get("hazards", [])),
                "no poison cloud captured")

    if weapon in ("airstrike", "mine_strike", "napalm"):
        strikes = [event for event in events if event.get("kind") == "strike" and event.get("weapon") == weapon]
        expected_side = 1 if weapon == "mine_strike" else -1
        require(len(strikes) == 1, "expected one bomber approach")
        if strikes:
            require(strikes[0].get("side") == expected_side and strikes[0].get("vx", 0) * expected_side > 0,
                    "bomber ignored the scripted approach direction")
        require(len({shot["id"] for shot in parents}) == 5, "expected five dropped projectile identities")
        require(any(shot.get("delay", 0) > 0 for shot in parents), "staggered releases were not captured")
    if weapon == "mine_strike":
        require(sum(event.get("kind") == "mine_land" and event.get("weapon") == weapon for event in events) == 5,
                "expected five landed mines")
        mines = [(frame["tick"], hazard) for frame in frames for hazard in frame.get("hazards", [])
                 if hazard.get("kind") == "mine"]
        require(len({hazard["id"] for _, hazard in mines}) == 5, "expected five mine identities")
        require(any(hazard.get("armed", 0) > tick for tick, hazard in mines), "mine arming delay was not captured")
        require(any(hazard.get("armed", tick + 1) <= tick for tick, hazard in mines), "no armed mine captured")
        require(all(not hazard.get("trigger") or hazard["trigger"] >= hazard.get("armed", 0)
                    for _, hazard in mines), "a mine triggered before arming")
    elif weapon == "napalm":
        counts = [frame.get("flame_count", 0) for frame in frames]
        require(0 < max(counts) <= 60, "expected bounded loose flames (1–60)")
        require(summary.get("peak_flames") == max(counts), "peak flame count disagrees")
    elif weapon == "meteor":
        require(len({shot["id"] for shot in parents}) == 6, "expected six meteor identities")
        require(any(shot.get("delay", 0) > 0 for shot in parents), "staggered meteor waves were not captured")
    elif weapon == "earthquake":
        require(sum(event.get("kind") == "quake" for event in events) == 1, "expected one earthquake impulse")
        require(any(worm.get("launched") and (abs(worm.get("vx", 0)) > 4 or abs(worm.get("vy", 0)) > 4)
                    for frame in frames for worm in [frame.get("active") or {}, *frame.get("enemies", [])]),
                "no earthquake knockback captured")
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--weapons", nargs="+", choices=MUNITIONS, default=MUNITIONS)
    args = parser.parse_args()
    try:
        summaries = json.loads((args.directory / "lab.json").read_text())
    except (OSError, ValueError) as error:
        parser.exit(1, f"Cannot read lab summary: {error}\n")
    failures = 0
    for weapon in args.weapons:
        try:
            summary = summaries[weapon]
            frames = json.loads((args.directory / weapon / "log.json").read_text())
            errors = validate(weapon, summary, frames)
        except (OSError, ValueError, KeyError, TypeError) as error:
            errors = [f"missing or malformed evidence: {error}"]
        if errors:
            failures += 1
            print(f"FAIL {weapon}: " + "; ".join(errors))
        else:
            counts = Counter(event["kind"] for event in summary["events"])
            print(f"PASS {weapon}: turn {summary['start_turn']}→{summary['final_turn']}, "
                  f"{len(frames)} captures, events {dict(counts)}")
    print(f"{len(args.weapons) - failures}/{len(args.weapons)} munitions passed")
    return bool(failures)


if __name__ == "__main__":
    raise SystemExit(main())
