"""Compile the reviewed background paintings to their native runtime sizes.

The source PNGs and their full generation prompts are committed alongside the
provenance manifest. Rebuilding is local and deterministic; it does not call an
image service. Foreground sprites remain procedural Cairo artwork; terrain
materials compile from their own reviewed painted masters.
"""
from __future__ import annotations

import hashlib
import json

from PIL import Image

from build_art_core import ART

SOURCE = ART / "source" / "paintings"
EXPECTED = {
    "menu-bg": (1440, 900),
    "sky-meadow": (1600, 800),
    "sky-desert": (1600, 800),
    "sky-glacier": (1600, 800),
    "sky-volcano": (1600, 800),
}


def painting_manifest():
    return json.loads((SOURCE / "provenance.json").read_text(encoding="utf-8"))


def build_all():
    paintings = painting_manifest()["assets"]
    if {entry["name"] for entry in paintings} != set(EXPECTED):
        raise ValueError("The painting manifest must cover the menu and all four biomes")
    for entry in paintings:
        path = SOURCE / entry["source"]
        if hashlib.sha256(path.read_bytes()).hexdigest() != entry["sha256"]:
            raise ValueError(f"Painting checksum changed: {path}. Review and update its provenance.")
        size = EXPECTED[entry["name"]]
        if list(size) != entry["output_size"]:
            raise ValueError(f"Painting dimensions disagree with the renderer: {entry['name']}")
        with Image.open(path) as master:
            if abs(master.width / master.height - size[0] / size[1]) > 0.025:
                raise ValueError(f"Painting aspect ratio would distort the artwork: {path}")
            compiled = master.convert("RGB").resize(size, Image.Resampling.LANCZOS)
            compiled.save(ART / f"{entry['name']}.png", optimize=True)
    return {"paintings": [entry["name"] for entry in paintings]}
