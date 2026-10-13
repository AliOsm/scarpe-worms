#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow>=10"]
# ///
"""Contact sheets for tools/weapon_lab.rb captures: one PNG per weapon.

    uv run tools/weapon_lab_sheet.py [.cache/weapon-lab] [weapon ...]
"""
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw

root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / ".cache/weapon-lab"
names = sys.argv[2:] or sorted(p.name for p in root.iterdir() if p.is_dir())
COLUMNS, WIDTH = 4, 480
for name in names:
    folder = root / name
    frames = sorted(folder.glob("frame-*.png"))
    if not frames:
        continue
    log = json.loads((folder / "log.json").read_text()) if (folder / "log.json").exists() else []
    first = Image.open(frames[0])
    # The battlefield only: below the top tray, above the bottom dock.
    box = (0, int(first.height * 0.115), first.width, int(first.height * 0.915))
    height = int(WIDTH * (box[3] - box[1]) / (box[2] - box[0]))
    rows = (len(frames) + COLUMNS - 1) // COLUMNS
    sheet = Image.new("RGB", (COLUMNS * WIDTH, rows * (height + 18)), (20, 24, 32))
    draw = ImageDraw.Draw(sheet)
    for i, path in enumerate(frames):
        im = Image.open(path).convert("RGB").crop(box).resize((WIDTH, height))
        x, y = (i % COLUMNS) * WIDTH, (i // COLUMNS) * (height + 18)
        sheet.paste(im, (x, y + 18))
        entry = log[i] if i < len(log) else {}
        active = entry.get("active") or {}
        caption = f"{i}: tick {entry.get('tick', '?')} {entry.get('phase', '')} "
        if active:
            caption += f"me ({active.get('x', 0):.0f},{active.get('y', 0):.0f}) hp {active.get('hp')} "
        shots = entry.get("projectiles") or []
        if shots:
            p = shots[0]
            caption += f"{p.get('weapon')}:{p.get('stage') or ''} ({p.get('x', 0):.0f},{p.get('y', 0):.0f})"
        draw.text((x + 4, y + 3), caption[:78], fill=(230, 236, 245))
    sheet.save(root / f"{name}-sheet.png")
    print(root / f"{name}-sheet.png")
