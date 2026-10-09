"""Contact sheets and animated GIF previews (for humans; not loaded by the game)."""
from __future__ import annotations

from PIL import Image, ImageDraw

from pathlib import Path
import functools
import subprocess

from build_art_core import ART, PAPER, ROOT, TEAMS

OUT = Path(__file__).resolve().parent / "build_art_previews"


def _paper(w, h):
    return Image.new("RGBA", (w, h), PAPER)


def grub_sheet(scale=2):
    from build_art_grubs import STATE_ORDER, frames_for
    cols = max(len(frames_for(s, 0)) for s in STATE_ORDER)
    cell = 80 * scale
    rows = len(STATE_ORDER)
    out = _paper(cols * cell * 6 + 5 * 16, rows * cell)
    for team in range(6):
        ox = team * (cols * cell + 16)
        for r, st in enumerate(STATE_ORDER):
            for k in range(len(frames_for(st, team))):
                im = Image.open(ART / "grubs" / f"{team}-{st}-{k}.png").resize((cell, cell), Image.LANCZOS)
                out.alpha_composite(im, (ox + k * cell, r * cell))
    out.save(OUT / "grubs-sheet.png")


def grub_small_check():
    """All teams at a compact 40px draw size, on a mid-tone background."""
    from build_art_grubs import STATE_ORDER, frames_for
    out = Image.new("RGBA", (6 * 44 * 8 + 8, len(STATE_ORDER) * 44 + 8), "#7aa7b0")
    for team in range(6):
        for r, st in enumerate(STATE_ORDER):
            for k in range(min(8, len(frames_for(st, team)))):
                im = Image.open(ART / "grubs" / f"{team}-{st}-{k}.png").resize((40, 40), Image.LANCZOS)
                out.alpha_composite(im, (4 + (team * 8 + k) * 44, 4 + r * 44))
    out.save(OUT / "grubs-40px.png")


def grub_gifs():
    from build_art_grubs import STATE_ORDER, frames_for
    fps = {"idle": 6, "walk": 12, "jump": 6, "hurt": 6, "victory": 10, "dead": 1, "blink": 8}
    for st in ("idle", "walk", "jump", "hurt", "victory"):
        frames = []
        n = len(frames_for(st, 0))
        reps = max(1, 24 // n)
        for _ in range(reps):
            for k in range(n):
                row = Image.new("RGBA", (6 * 120, 120), PAPER)
                for team in range(6):
                    im = Image.open(ART / "grubs" / f"{team}-{st}-{k}.png").resize((120, 120), Image.LANCZOS)
                    row.alpha_composite(im, (team * 120, 0))
                frames.append(row.convert("RGB").quantize(colors=255, method=Image.MEDIANCUT))
        frames[0].save(OUT / f"grubs-{st}.gif", save_all=True, append_images=frames[1:],
                       duration=int(1000 / fps[st]), loop=0)


def icon_sheet():
    wdir = ART / "weapons"
    icons = sorted(wdir.glob("*.png"))
    if not icons:
        return
    cols = 8
    cell = 88
    rows = (len(icons) + cols - 1) // cols
    out = _paper(cols * cell, rows * cell)
    d = ImageDraw.Draw(out)
    for i, p in enumerate(icons):
        x, y = (i % cols) * cell, (i // cols) * cell
        d.rounded_rectangle((x + 6, y + 4, x + cell - 6, y + 70), 12, fill="#e9e0cc")
        out.alpha_composite(Image.open(p).resize((64, 64), Image.LANCZOS), (x + 12, y + 5))
        d.text((x + cell / 2, y + 78), p.stem, fill="#182d35", anchor="mm")
    out.save(OUT / "weapons-sheet.png")


def scenes_sheet():
    names = ["menu-bg", "sky-meadow", "sky-desert", "sky-glacier", "sky-volcano", "app-icon", "crate", "grave",
             "cloud"]
    ims = [(n, ART / f"{n}.png") for n in names if (ART / f"{n}.png").exists()]
    if not ims:
        return
    w = 720
    tiles = []
    for n, p in ims:
        im = Image.open(p).convert("RGBA")
        if im.width > 300:
            im = im.resize((w, int(im.height * w / im.width)), Image.LANCZOS)
        tiles.append(im)
    big = [t for t in tiles if t.width == w]
    small = [t for t in tiles if t.width != w]
    h = sum(t.height + 8 for t in big) + (max((t.height for t in small), default=0) + 8)
    out = _paper(w * 2 + 24, (h // 2) + 400)
    x, y = 8, 8
    col = 0
    for t in big:
        out.alpha_composite(t, (8 + col * (w + 8), y))
        if col == 1:
            y += t.height + 8
        col ^= 1
    if col == 1:
        y += big[-1].height + 8
    x = 8
    for t in small:
        out.alpha_composite(t, (x, y))
        x += t.width + 12
    out = out.crop((0, 0, out.width, y + max((t.height for t in small), default=0) + 8))
    out.save(OUT / "scenes-sheet.png")


# --------------------------------------------------------------------------
# Terrain kit and combat-board mock-ups (round 3)
# --------------------------------------------------------------------------

BIOMES = ("meadow", "desert", "glacier", "volcano")


@functools.cache
def _mask(name):
    """Generate real collision data; never depend on an ignored previous build."""
    import numpy as np
    script = ('terrain = Burrow::Terrain.new(seed: 314159, shape: ARGV.fetch(0), '
              'width: 4800, height: 1600); STDOUT.binmode; STDOUT.write(terrain.data)')
    data = subprocess.check_output(["ruby", "-I", str(ROOT / "lib"), "-r", "burrow",
                                    "-e", script, name], cwd=ROOT)
    mask = np.frombuffer(data, dtype=np.uint8).reshape((800, 2400))
    Image.fromarray(mask * 80).save(OUT / f"terrain-mask-{name}.png")
    return mask


def terrain_kit_sheet():
    from build_art_terrain import CR, T, TU
    cell = 3
    out = _paper(4 * (T + 24) + 24, T + 384)
    d = ImageDraw.Draw(out)
    for i, b in enumerate(BIOMES):
        x = 24 + i * (T + 24)
        d.text((x, 8), b, fill="#182d35")
        fill = Image.open(ART / f"terrain/{b}-fill.png").convert("RGBA")
        out.alpha_composite(fill, (x, 24))
        for j, k in enumerate(("deep", "shade", "edge")):
            sw = Image.open(ART / f"terrain/{b}-{k}.png").convert("RGBA").crop((0, 0, 80, 64))
            out.alpha_composite(sw, (x + j * 88, T + 34))
            d.text((x + j * 88, T + 100), k, fill="#5d6f72")
        crust = Image.open(ART / f"terrain/{b}-crust.png").convert("RGBA").crop((0, 0, T // cell, CR))
        crust = crust.resize((T, CR * cell), Image.NEAREST)
        backing = Image.open(ART / f"terrain/{b}-fill.png").convert("RGBA").crop((0, 0, T, CR * cell))
        backing.alpha_composite(crust)
        out.alpha_composite(backing, (x, T + 124))
        tufts = Image.open(ART / f"terrain/{b}-tufts.png").convert("RGBA").crop((0, 0, T // cell, TU))
        out.alpha_composite(tufts.resize((T, TU * cell), Image.NEAREST), (x, T + 194))
        d.text((x, T + 234), "crust (x3) / optional tufts (x3)", fill="#5d6f72")
        mas = Image.open(ART / f"terrain/{b}-masonry.png").convert("RGBA").resize((192, 96), Image.NEAREST)
        out.alpha_composite(mas, (x, T + 256))
        out.alpha_composite(Image.open(ART / "terrain/girder.png").convert("RGBA").resize((128, 24), Image.NEAREST),
                            (x + 200, T + 276))
        d.text((x, T + 362), "masonry (x1.5) / girder (x4)", fill="#5d6f72")
    out.save(OUT / "terrain-kit.png")


def combat_board(biome, mask_name="islands", cam=(420, 470)):
    """A 1440x720 battle view assembled the way scene.rb layers it (camera zoom 1)."""
    from PIL import ImageFont
    from build_art_terrain import paint

    mask = _mask(mask_name)
    terrain = paint(mask, biome)
    world = terrain.resize((terrain.width * 2, terrain.height * 2), Image.NEAREST)
    view = Image.open(ART / f"sky-{biome}.png").convert("RGBA").resize((1440, 720), Image.LANCZOS)
    cx, cy = cam
    view.alpha_composite(world.crop((cx, cy, cx + 1440, cy + 720)))

    def surface(wx):
        col = mask[:, wx // 2]
        for y in range(int(cy // 2) + 10, mask.shape[0]):
            if col[y] and not col[y - 1]:
                return y * 2
        return None

    def put(name, x, y, w, h):
        im = Image.open(ART / f"{name}.png").convert("RGBA").resize((w, h), Image.LANCZOS)
        view.alpha_composite(im, (int(x - cx), int(y - cy)))

    font = ImageFont.load_default()
    d = ImageDraw.Draw(view)
    teams = [0, 1, 3, 4, 2, 5]
    names = ["Pip", "Beans", "Miso", "Sprout", "Honey", "Blue"]
    states = [("idle", 0), ("walk", 3), ("idle", 2), ("victory", 1), ("hurt", 2), ("idle", 1)]
    spots = [cx + 160, cx + 430, cx + 700, cx + 900, cx + 1130, cx + 1330]
    for k, wx in enumerate(spots):
        sy = surface(wx)
        if sy is None or sy > cy + 640:
            continue
        team, (st, fr) = teams[k], states[k]
        left = "left/" if k % 2 else ""
        put(f"grubs/{left}{team}-{st}-{fr}", wx - 32, sy - 54.4, 64, 64)
        bx, by = wx - 42 - cx, sy - 83.4 - cy
        d.rounded_rectangle((bx, by, bx + 84, by + 20), 6, fill="#182d35")
        d.text((bx + 42, by + 10), f"{names[k]}  {100 - k * 13}", fill="#fffaf0", anchor="mm", font=font)
        d.rectangle((bx + 1, by + 19, bx + 82, by + 20), fill=TEAMS[team])
    for name, wx, width, height, ax, ay in (("crate", cx + 560, 34, 34, 17, 31.875),
                                          ("mine-prop", cx + 1010, 34, 34, 17, 27.625),
                                          ("barrel-prop", cx + 1230, 32, 38, 16, 36.8)):
        sy = surface(wx)
        if sy is not None and sy < cy + 680:
            put(name, wx - ax, sy - ay, width, height)
    # a shot in flight and an impact
    put("projectiles/rocket", cx + 610, cy + 120, 28, 28)
    ex = Image.open(ART / "fx/explosion-3.png").convert("RGBA").resize((160, 160), Image.LANCZOS)
    view.alpha_composite(ex, (1050 - 80, 300 - 80))
    # the game's water layer (scene.rb box + waterline)
    wy = mask.shape[0] * 2 - 96 - cy
    if wy < 720:
        water = Image.new("RGBA", (1440, 720 - wy), (0x43, 0x8c, 0x97, 0xdd))
        view.alpha_composite(water, (0, wy))
        d.line((0, wy, 1440, wy), fill="#c1e9dd", width=3)
    return view


def combat_boards():
    boards = [combat_board(b) for b in BIOMES]
    sheet = _paper(1440 + 24, 4 * (360 + 12) + 12)
    for i, im in enumerate(boards):
        if i == 0:
            im.convert("RGB").save(OUT / "combat-board-meadow.png")
        sheet.alpha_composite(im.resize((720, 360), Image.LANCZOS), (8 + (i % 2) * 728, 8 + (i // 2) * 372))
    cav = combat_board("volcano", "cavern", (500, 300))
    sheet.alpha_composite(cav.resize((720, 360), Image.LANCZOS), (8, 8 + 2 * 372))
    cav2 = combat_board("glacier", "cavern", (1300, 300))
    sheet.alpha_composite(cav2.resize((720, 360), Image.LANCZOS), (736, 8 + 2 * 372))
    # grubs with the new contact shadow + volume on terrain-coloured swatches
    row = _paper(1440, 300)
    for i, b in enumerate(BIOMES):
        sw = Image.open(ART / f"terrain/{b}-fill.png").convert("RGBA").resize((360, 300), Image.NEAREST)
        row.alpha_composite(sw, (i * 360, 0))
    for t in range(6):
        for j, (st, fr) in enumerate((("idle", 0), ("walk", 4), ("victory", 2), ("hurt", 2))):
            im = Image.open(ART / "grubs" / f"{t}-{st}-{fr}.png").resize((120, 120), Image.LANCZOS)
            row.alpha_composite(im, (10 + (t * 4 + j) % 12 * 118, 20 + ((t * 4 + j) // 12) * 140))
    sheet.alpha_composite(row.resize((1440 // 2 * 2, 300)), (12, 8 + 3 * 372 - 4))
    sheet = sheet.crop((0, 0, sheet.width, 8 + 3 * 372 + 300))
    sheet.convert("RGB").save(OUT / "art-contact-sheet.png")


def build_all():
    OUT.mkdir(exist_ok=True)
    grub_sheet()
    grub_small_check()
    grub_gifs()
    icon_sheet()
    scenes_sheet()
    terrain_kit_sheet()
    combat_boards()
    return {}
