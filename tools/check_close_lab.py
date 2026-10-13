#!/usr/bin/env python3
"""Validate the close-family native lab from authoritative logs, without images."""
import argparse
import json
from pathlib import Path

WEAPONS = "shotgun rifle minigun laser flamethrower fire_punch dragon_punch prod bat axe mine turret barrel drill blowtorch heal shield freeze double_damage low_gravity wind_control skip".split()
GUNS = dict(shotgun=("shotgun", 2), rifle=("beam", 1), minigun=("burst", 8),
            laser=("laser", 1), flamethrower=("flame", 18))
MELEE = {"fire_punch", "dragon_punch", "prod", "bat", "axe"}
KEEP_TURN = {"shield", "double_damage", "low_gravity", "wind_control"}


def validate(weapon, rows):
    assert len(rows) >= 3, "missing native captures"
    events = [event for row in rows for event in row["events"]]
    first = rows[0]
    actor_id = first["active"]["id"]
    actors = [row["active"] for row in rows if row["active"]["id"] == actor_id]
    targets = [enemy for row in rows for enemy in row["enemies"]
               if enemy["id"] == first["enemies"][0]["id"]]
    reports = [event for event in events if event["kind"] == "fire" and event["weapon"] == weapon]
    assert len(reports) == (2 if weapon == "shotgun" else 1), "native action was missed or repeated"
    assert not any(row.get("notice") for row in rows), "client reported a rejected action"
    if weapon in KEEP_TURN:
        assert all(row["phase"] == "aiming" and row["team"] == first["team"] for row in rows), "utility lost the turn"
    else:
        assert any(row["phase"] != "aiming" or row["turn"] != first["turn"] for row in rows[1:]), "attack did not resolve"
    if weapon in GUNS:
        style, count = GUNS[weapon]
        beams = [event for event in events if event["kind"] == "beam" and event["style"] == style]
        assert len(beams) == count, f"expected {count} gun reports, got {len(beams)}"
        assert min(enemy["hp"] for enemy in targets) < 100, "aimed gun did not hit the target"
        if weapon == "shotgun":
            assert all(len(event["rays"]) == 5 for event in beams), "missing pellet spread"
            assert any(row["shots_left"] == 1 for row in rows) and rows[-1]["shots_left"] == 0, "second shot did not finish cartridge"
        if weapon == "flamethrower":
            assert beams[-1]["tick"] - beams[0]["tick"] >= 34, "flame stream ended early"
            assert any(h["kind"] == "flame" for row in rows for h in row["hazards"]), "no persistent flames"
    if weapon in MELEE:
        assert any(event["kind"] == "melee" and event.get("hits") for event in events), "melee missed its nearby target"
        assert any(enemy["x"] != targets[0]["x"] or enemy["y"] != targets[0]["y"] for enemy in targets), "melee did not move the target"
        assert min(enemy["hp"] for enemy in targets) == 100 if weapon == "prod" else min(enemy["hp"] for enemy in targets) < 100
        if weapon == "fire_punch":
            assert min(actor["y"] for actor in actors) < first["active"]["y"] - 10, "uppercut did not leap"
        if weapon == "dragon_punch":
            assert max(actor["x"] for actor in actors) > first["active"]["x"] + 60, "dash did not advance"
            assert max(row["terrain_revision"] for row in rows) > first["terrain_revision"], "dash cut no tunnel"
    if weapon in {"mine", "turret", "barrel"}:
        assert any(event["kind"] == "hazard_place" and event["style"] == weapon for event in events), "prop was not placed"
    if weapon == "mine":
        assert {"mine_arm", "mine_trigger", "explosion"} <= {event["kind"] for event in events}, "mine lifecycle incomplete"
        assert min(enemy["hp"] for enemy in targets) < 100, "mine never hurt nearby target"
    if weapon == "turret":
        beams = [event for event in events if event["kind"] == "beam" and event["style"] == "turret"]
        assert len(beams) == 5 and beams[-1]["shots"] == 0, "sentry did not spend exactly five shots"
        assert min(enemy["hp"] for enemy in targets) == 20, "sentry damage differs from five hits"
    if weapon == "barrel":
        assert any(event["kind"] == "barrel_rupture" for event in events), "barrel did not rupture in the incoming blast"
        assert any(event["kind"] == "explosion" and event["style"] == "barrel" for event in events), "barrel did not explode"
        assert any(h["kind"] == "flame" for row in rows for h in row["hazards"]), "barrel spilled no fire"
    if weapon in {"drill", "blowtorch"}:
        assert any(row["tool"] for row in rows), "tool did not start"
        assert rows[-1]["tool"] is None, "tool did not stop"
        assert any(event["kind"] == "activate" and event.get("stage") == "stopped" for event in events), "native stop input was missed"
        assert max(row["terrain_revision"] for row in rows) > first["terrain_revision"], "tool removed no ground"
        assert all(actor["hp"] == 100 for actor in actors), "tool hurt its user"
        if weapon == "blowtorch":
            lifts = {row["tool"]["lift"] for row in rows if row["tool"]}
            assert {-1, 1} <= lifts, "both slope controls were not exercised"
    if weapon == "heal":
        assert first["active"]["poisoned"] and first["active"]["hp"] == 65, "healing fixture was not injured/poisoned"
        assert any(actor["hp"] == 100 and not actor["poisoned"] for actor in actors), "first aid failed to heal and cure"
    if weapon in {"shield", "freeze"}:
        flag = "frozen" if weapon == "freeze" else "shield"
        assert any(actor[flag] for actor in actors), f"{flag} never became active"
    if weapon in {"double_damage", "low_gravity"}:
        assert any(row["effects"][weapon] for row in rows), "turn effect never became active"
    if weapon == "low_gravity":
        assert min(actor["y"] for actor in actors) < first["active"]["y"] - 30, "native float jump failed"
    if weapon == "wind_control":
        assert any(row["wind"] == -2 * first["wind"] for row in rows), "wind was not reversed and doubled"
    if weapon == "skip":
        assert rows[-1]["team"] != first["team"], "pass never handed over"
    return {"captures": len(rows), "events": len(events), "result": "passed"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folder", type=Path)
    parser.add_argument("weapons", nargs="*", choices=WEAPONS)
    args = parser.parse_args()
    report = {}
    for weapon in args.weapons or WEAPONS:
        try:
            report[weapon] = validate(weapon, json.loads((args.folder / weapon / "log.json").read_text()))
        except (AssertionError, KeyError, FileNotFoundError) as error:
            report[weapon] = {"result": "failed", "reason": str(error)}
    print(json.dumps(report, indent=2))
    return 1 if any(row["result"] == "failed" for row in report.values()) else 0


if __name__ == "__main__":
    raise SystemExit(main())
