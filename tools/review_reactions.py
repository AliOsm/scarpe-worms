#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow>=10"]
# ///
"""Review new grub/reaction art at game size and 2×, without editing assets.

    uv run tools/review_reactions.py --output /tmp/fx-art-review

GIFs repeat for inspection, including animations the game plays once. Balanced
10 ms GIF delays preserve the declared average fps (including 12/14/16 fps).
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "assets/art"
BACKGROUNDS = (("sky", "#7ea4b3"), ("meadow soil", "#986d4a"))
INK, PAPER = "#182d35", "#f7f2e6"
FONT = ImageFont.truetype(str(ROOT / "assets/fonts/InterVariable.ttf"), 14)
TITLE = ImageFont.truetype(str(ROOT / "assets/fonts/Fredoka.ttf"), 22)


def animations(manifest):
    for team in (0, 3):
        for state in ("tumble", "dying", "drown", "grave"):
            spec = manifest["grubs"]["states"][state]
            for facing in (("right", "left") if state == "tumble" else ("right",)):
                folder = "grubs/left" if facing == "left" else "grubs"
                yield {"name": f"team-{team}-{state}-{facing}", "fps": spec["fps"], "size": (64, 64),
                       "anchor": (32, 54.4), "loop": spec["loop"],
                       "paths": [ART / folder / f"{team}-{state}-{k}.png" for k in range(spec["frames"])]}
    for name, spec in manifest["ordnance"]["reactions"].items():
        yield {"name": name, "fps": spec["fps"], "size": tuple(spec["size"]),
               "anchor": tuple(spec["anchor"]), "loop": spec["loop"],
               "paths": [ART / spec["pattern"].format(frame=k) for k in range(spec["frames"])]}


def stamp(canvas, sprite, origin, size, anchor, zoom):
    x, y = origin
    draw = ImageDraw.Draw(canvas)
    ax, ay = x + anchor[0] * zoom, y + anchor[1] * zoom
    # Subtle registration tick, behind the image; no guides go into game art.
    draw.line((ax - 4, ay, ax + 4, ay), fill=(245, 241, 218, 180), width=1)
    draw.line((ax, ay - 3, ax, ay + 3), fill=(245, 241, 218, 180), width=1)
    canvas.alpha_composite(sprite.resize((size[0] * zoom, size[1] * zoom), Image.Resampling.LANCZOS), (x, y))


def review_panel(anim, sprites):
    w, h = anim["size"]
    count = len(sprites)
    width = max(880, 124 + count * (w * 2 + 12))
    height = 58 + sum(h * zoom + 34 for zoom in (1, 2) for _ in BACKGROUNDS)
    panel = Image.new("RGBA", (width, height), PAPER)
    draw = ImageDraw.Draw(panel)
    draw.text((12, 7), anim["name"], font=TITLE, fill=INK)
    draw.text((12, 34), f"{count} frames · {anim['fps']} fps · {'loop' if anim['loop'] else 'once / hold or remove'} · game canvas {w}×{h}", font=FONT, fill=INK)
    y = 58
    for zoom in (1, 2):
        for label, color in BACKGROUNDS:
            row_h = h * zoom + 34
            draw.rectangle((0, y, width, y + row_h), fill=color)
            draw.text((10, y + 8), f"{label}\n{zoom}×", font=FONT, fill=PAPER, spacing=6)
            for k, sprite in enumerate(sprites):
                x = 116 + k * (w * zoom + 12)
                draw.text((x + 3, y + 3), str(k), font=FONT, fill=PAPER)
                stamp(panel, sprite, (x, y + 23), (w, h), anim["anchor"], zoom)
            y += row_h
    return panel


def review_gif(anim, sprites, path):
    w, h = anim["size"]
    cell_w, cell_h = max(160, 2 * w + 20), 3 * h + 78
    frames = []
    for sprite in sprites:
        page = Image.new("RGBA", (cell_w * 2, cell_h), PAPER)
        d = ImageDraw.Draw(page)
        for side, (label, color) in enumerate(BACKGROUNDS):
            left = side * cell_w
            d.rectangle((left, 0, left + cell_w, cell_h), fill=color)
            d.text((left + 9, 7), f"{label} · {anim['fps']} fps", font=FONT, fill=PAPER)
            for zoom, y in ((1, 34), (2, 56 + h)):
                d.text((left + 8, y), f"{zoom}×", font=FONT, fill=PAPER)
                stamp(page, sprite, (left + (cell_w - w * zoom) // 2, y + 18), (w, h), anim["anchor"], zoom)
        frames.append(page.convert("RGB"))
    # Repeat whole cycles only when needed to close a GIF's centisecond clock.
    repeats = anim["fps"] // math.gcd(anim["fps"], len(frames) * 100)
    frames *= repeats
    durations = [10 * (round((k + 1) * 100 / anim["fps"]) - round(k * 100 / anim["fps"])) for k in range(len(frames))]
    frames[0].save(path, save_all=True, append_images=frames[1:], duration=durations,
                   loop=0, disposal=2, optimize=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path("/tmp/fx-art-review"))
    output = parser.parse_args().output
    output.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((ART / "manifest.json").read_text())
    panels, index = [], []
    for anim in animations(manifest):
        sprites = [Image.open(path).convert("RGBA") for path in anim["paths"]]
        panel = review_panel(anim, sprites)
        panel.save(output / f"{anim['name']}.png")
        review_gif(anim, sprites, output / f"{anim['name']}.gif")
        panels.append(panel)
        index.append({key: value for key, value in anim.items() if key != "paths"} | {"frames": len(sprites)})
    sheet = Image.new("RGBA", (max(p.width for p in panels), sum(p.height + 12 for p in panels)), PAPER)
    y = 0
    for panel in panels:
        sheet.alpha_composite(panel, (0, y))
        y += panel.height + 12
    sheet.convert("RGB").save(output / "sheet.png")
    (output / "index.json").write_text(json.dumps(index, indent=2) + "\n")
    print(f"{output / 'sheet.png'}: {len(panels)} panels, {sum(a['frames'] for a in index)} frames; PNG + GIF per panel")


if __name__ == "__main__":
    main()
