"""Compile the reviewed background paintings to their native runtime sizes.

The source PNGs and their full generation prompts are committed alongside the
provenance manifest. Rebuilding is local and deterministic; it does not call an
image service. Foreground sprites remain procedural Cairo artwork; terrain
materials compile from their own reviewed painted masters.
"""
from __future__ import annotations

import hashlib
import json

from PIL import Image, ImageDraw

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
    menu_scene().save(ART / "menu-scene.png", optimize=True)
    return {"paintings": [entry["name"] for entry in paintings] + ["menu-scene"]}


MENU_SCENE = (1440, 900)
# The crew island fades in across these columns, over the open meadow panorama.
MENU_SEAM = (560, 800)


def menu_scene():
    """Full-bleed menu backdrop for framed menu panels, derived from two masters.

    The menu painting's ivory text column is replaced by the meadow panorama,
    then a soft dusk vignette lifts the bright glossy panels off the scene.
    """
    w, h = MENU_SCENE
    with Image.open(SOURCE / "menu-bg.png") as master:
        crew = master.convert("RGB").resize(MENU_SCENE, Image.Resampling.LANCZOS)
    with Image.open(SOURCE / "sky-meadow.png") as master:
        width = round(master.width * h / master.height)
        sky = master.convert("RGB").resize((width, h), Image.Resampling.LANCZOS)
    left = (width - w) // 2
    sky = sky.crop((left, 0, left + w, h))
    seam = Image.new("L", MENU_SCENE, 0)
    draw = ImageDraw.Draw(seam)
    start, end = MENU_SEAM
    for x in range(w):
        t = min(max((x - start) / (end - start), 0.0), 1.0)
        draw.line([(x, 0), (x, h)], fill=round(255 * t * t * (3 - 2 * t)))
    scene = Image.composite(crew, sky, seam)
    # radial_gradient is 0 at its centre and 255 at its corners.
    vignette = Image.radial_gradient("L").resize((w + w // 3, h + h // 3), Image.Resampling.BICUBIC)
    vignette = vignette.crop((w // 6, h // 6, w // 6 + w, h // 6 + h)).point(lambda v: round(max(v - 120, 0) * 0.62))
    dusk = Image.new("RGB", MENU_SCENE, (8, 22, 52))
    return Image.composite(dusk, scene, vignette)
