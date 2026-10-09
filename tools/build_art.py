#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["cairocffi>=1.6", "pillow>=10", "numpy>=1.26"]
# ///
"""Build every BURROW BRIGADE art asset into assets/art/.

    uv run tools/build_art.py              # everything
    uv run tools/build_art.py grubs icons  # only some sections

Sections: grubs, portraits, icons, props, terrain, scenes, previews.  The manifest
(assets/art/manifest.json) is always rewritten from whatever exists on disk
plus the metadata produced by the sections that ran.

The build is deterministic: procedural random choices are seeded, reviewed
background paintings are compiled from committed source PNGs, and the manifest
carries a fixed ART_VERSION rather than a date. Rebuilds need no image service.
"""
from __future__ import annotations

import json
import sys
import time
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))

from build_art_core import ART, TEAM_NAMES, TEAMS, ensure_dirs, rel, save, surface  # noqa: E402

SECTIONS = ["grubs", "portraits", "icons", "props", "terrain", "scenes", "previews"]

# Bump by hand when the art changes.  Not derived from the clock, so that a
# rebuild of unchanged sources is byte-for-byte identical (reproducible builds).
ART_VERSION = "2026.10.09.3"


def build_grubs():
    from build_art_grubs import ANCHOR, GROUND_LIFT, SPRITE_SCALE, STATE_ORDER, draw_grub, frames_for

    counts = {}
    for team in range(6):
        for state in STATE_ORDER:
            frames = frames_for(state, team)
            counts[state] = len(frames)
            for k, pose in enumerate(frames):
                for mirrored in (False, True):
                    s, ctx = surface(160, 160)
                    ctx.scale(2, 2)
                    if mirrored:
                        ctx.translate(80, 0)
                        ctx.scale(-1, 1)
                    ctx.translate(ANCHOR[0], ANCHOR[1] - GROUND_LIFT)
                    ctx.scale(SPRITE_SCALE, SPRITE_SCALE)
                    ctx.translate(-ANCHOR[0], -ANCHOR[1])
                    draw_grub(ctx, pose, team)
                    sub = "grubs/left" if mirrored else "grubs"
                    save(s, ART / sub / f"{team}-{state}-{k}.png")
    return {"grub_states": counts}


def build_icons():
    from build_art_icons import build_all
    from build_art_combat import build_all as build_combat
    result = build_all()
    build_combat()
    return result


def build_portraits():
    from build_art_grubs import ANCHOR, GROUND_LIFT, SPRITE_SCALE, draw_grub, frames_for
    for team in range(6):
        for state, frame in (("idle", 0), ("victory", 2)):
            s, ctx = surface(512, 512)
            ctx.scale(512 / 80, 512 / 80)
            ctx.translate(ANCHOR[0], ANCHOR[1] - GROUND_LIFT)
            ctx.scale(SPRITE_SCALE, SPRITE_SCALE)
            ctx.translate(-ANCHOR[0], -ANCHOR[1])
            draw_grub(ctx, frames_for(state, team)[frame], team)
            save(s, ART / "grubs/portraits" / f"{team}-{state}-{frame}.png")


def build_props():
    from build_art_props import build_all
    return build_all()


def build_terrain():
    from build_art_terrain import build_all
    return build_all()


def _terrain_meta():
    try:
        from build_art_terrain import terrain_meta
        return terrain_meta()
    except ImportError:
        return {}


def build_scenes():
    from build_art_scenes import build_all
    return build_all()


def build_previews():
    from build_art_preview import build_all
    return build_all()


def _props_meta():
    try:
        from build_art_props import PROPS_META
        return PROPS_META
    except ImportError:
        return {}


def _fx_meta():
    try:
        from build_art_props import FX_META
        return FX_META
    except ImportError:
        return {}


def write_manifest(meta):
    from PIL import Image

    from build_art_grubs import ANCHOR, STATE_ORDER, frames_for

    def dims(p):
        with Image.open(p) as im:
            return list(im.size)

    def entry(p, **extra):
        d = {"path": rel(p), "size": dims(p)}
        d.update(extra)
        return d

    m = {
        "name": "BURROW BRIGADE art",
        "version": ART_VERSION,
        "generator": "tools/build_art.py (procedural Cairo foregrounds and compiled painted backgrounds; see docs/ART_DIRECTION.md)",
        "license": "Original artwork created for BURROW BRIGADE; see docs/ART_DIRECTION.md",
        "palette": {"ink": "#182d35", "paper": "#f7f2e6", "orange": "#f57c49", "teal": "#407d80", "gold": "#edc16d"},
        "teams": [{"id": i, "name": TEAM_NAMES[i], "color": TEAMS[i],
                   "headgear": ["aviator goggles", "field helmet", "headband", "pom-pom beanie",
                                "propeller cap", "backwards cap"][i]} for i in range(6)],
    }

    # Grubs
    states = {}
    fps = {"idle": 6, "walk": 12, "jump": 10, "hurt": 10, "victory": 10, "dead": 1, "blink": 12}
    loop = {"idle": True, "walk": True, "jump": False, "hurt": False, "victory": True, "dead": False, "blink": False}
    notes = {
        "jump": "0 crouch (pre-jump), 1 launch (rising), 2 apex/tuck, 3 falling; pick by vertical velocity",
        "hurt": "0 recoil, 1 squash, 2 dizzy; hold last frame while stunned",
        "blink": "optional extra: overlay occasionally during idle (half, closed)",
        "dead": "knocked-out pose; swap to props grave.png after a beat if desired",
    }
    for st in STATE_ORDER:
        n = len(frames_for(st, 0))
        states[st] = {"frames": n, "fps": fps[st], "loop": loop[st],
                      "pattern": f"grubs/{{team}}-{st}-{{frame}}.png"}
        if st in notes:
            states[st]["note"] = notes[st]
    m["grubs"] = {
        "frame_size": [160, 160],
        "logical_size": [80, 80],
        "anchor": [value * 2 for value in ANCHOR],
        "anchor_note": "Source pixels; logical foot anchor (40,68) on an 80x80 canvas. 2x raster for Retina displays.",
        "facing": "right",
        "left_facing": "grubs/left/{team}-{state}-{frame}.png (pre-mirrored, same anchor)",
        "recommended_draw_size": [64, 64],
        "teams": 6,
        "portraits": {"frame_size": [512, 512], "poses": ["idle-0", "victory-2"],
                      "pattern": "grubs/portraits/{team}-{state}-{frame}.png"},
        "states": states,
    }

    # Weapons
    from build_art_combat import metadata as combat_metadata
    m["combat"] = combat_metadata()
    wdir = ART / "weapons"
    if wdir.exists():
        m["weapons"] = {
            "size": [128, 128],
            "logical_size": [64, 64],
            "pattern": "weapons/{id}.png",
            "ids": sorted(p.stem for p in wdir.glob("*.png")),
        }

    def collect(names, **extra):
        out = {}
        for n in names:
            p = ART / f"{n}.png"
            if p.exists():
                out[n] = entry(p, **extra.get(n, {}))
        return out

    m["backgrounds"] = collect(["menu-bg", "sky-meadow", "sky-desert", "sky-glacier", "sky-volcano"], **{
        "menu-bg": {"note": "Quiet warm ivory left column for menu text; painted original crew and island on the right"},
    })
    from build_art_scenes import painting_manifest
    for painting in painting_manifest()["assets"]:
        m["backgrounds"][painting["name"]].update({
            "origin": "Original AI-assisted painting; Codex built-in imagegen",
            "source": f"source/paintings/{painting['source']}",
            "source_sha256": painting["sha256"],
        })
    m["props"] = collect(["app-icon", "crate", "crate-health", "crate-utility", "grave"]
                         + [f"grave-{t}" for t in range(6)]
                         + ["cloud", "cloud-small", "mine-prop", "mine-prop-lit", "barrel-prop"]
                         + [f"app-icon-{n}" for n in (16, 32, 48, 64, 128, 512, 1024)],
                         **_props_meta())
    if (ART / "terrain").exists():
        m["terrain"] = _terrain_meta()
    extra_dirs = {}
    for d in ("fx", "ui"):
        dd = ART / d
        if dd.exists():
            extra_dirs[d] = sorted(rel(p) for p in dd.glob("*.png"))
    if extra_dirs:
        m["extras"] = extra_dirs
        fxm = _fx_meta()
        if fxm:
            m["extras"]["fx_animations"] = fxm
    (ART / "manifest.json").write_text(json.dumps(m, indent=2) + "\n")


def main(argv):
    want = [a for a in argv if not a.startswith("-")] or SECTIONS
    ensure_dirs()
    meta = {}
    for sec in SECTIONS:
        if sec in want:
            t = time.time()
            res = globals()[f"build_{sec}"]() or {}
            meta.update(res)
            print(f"[art] {sec:8s} {time.time() - t:5.1f}s")
    write_manifest(meta)
    print("[art] manifest written")


if __name__ == "__main__":
    main(sys.argv[1:])
