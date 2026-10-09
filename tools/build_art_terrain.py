"""Terrain material kit: tileable textures for the destructible landscape.

The game's terrain is a bitmap of cells (1 cell = 2 world pixels) painted by
lib/burrow/client/terrain_painter.rb in a worker process.  These textures are
authored at *cell* resolution so the painter only does table lookups per cell,
with no per-pixel trigonometry or colour blending:

    terrain/{biome}-fill.png    512x512  tileable rock/soil body
    terrain/{biome}-deep.png    512x512  same, slightly darker: more than DEEP cells below the surface
    terrain/{biome}-shade.png   512x512  same, occluded (under the grass lip, cave ceilings)
    terrain/{biome}-edge.png    512x512  same, deep shadow tone (1-2 cell silhouette rim)
    terrain/{biome}-crust.png   512x20   surface lip; row r = r cells below the air above.
                                         alpha 255 = paint crust colour, alpha 0 = use fill,
                                         any other alpha = use the shade texture (lip shadow)
    terrain/{biome}-tufts.png   512x12   grass/snow/ash fringe drawn into the *empty* cells
                                         above a surface; the bottom row touches the ground.
                                         Written with its own alpha (no blending needed).
    terrain/{biome}-masonry.png 128x64   weathered dressed stone for material 3
    terrain/girder.png          32x6     steel girder for material 2; row = depth from its top

Body materials compile from reviewed painted masters. Surface lips and masonry
are drawn with Cairo at 4x and box-filtered down. All random choices are seeded;
mirrored world-coordinate sampling keeps the painted body seamless.
"""
from __future__ import annotations

import hashlib
import json
import math

import cairocffi as cairo
from PIL import Image

from build_art_core import ART, Rand, circle, ellipse, mix, poly, smooth, src

OUT = ART / "terrain"
T = 512          # fill tile, cells; broad painted masses repeat every 1024 world pixels
SS = 4           # supersampling
CR = 20          # crust rows
TU = 12          # tuft rows
DEEP = 24        # cells below the surface where the darker "deep" fill starts

BIOMES = {
    "meadow": dict(
        base="#986d4a", lo="#87603f", hi="#a97e55", band="#7b563a", band_hi="#b88c61",
        stone="#c2b29a", stone_lo="#9c8a72", stone_hi="#e6dbc8", stone_ink="#563c2a",
        pebble=("#6f4c35", "#c7a47c", "#a07a57"), root="#5c3f2d", hole="#4a3224", hole_rim="#b88d61",
        shade_to="#4a3640", edge_to="#2e211b",
        crust=dict(ink="#2d5527", top="#a9d865", hi="#cdec88", body="#79b34b", deep="#5d9840"),
        tuft=("#7fbe4f", "#4f8a39", "#a9d865"), flowers=("#fff6e0", "#ffd35c", "#ff8fa3"),
        masonry=("#c8b896", "#a8977a", "#e4d8bd", "#5d4a3a"),
    ),
    "desert": dict(
        base="#c47a4a", lo="#b0683f", hi="#d48c5a", band="#9d5636", band_hi="#e7a874",
        stone="#efcf9d", stone_lo="#d2a676", stone_hi="#fff0d0", stone_ink="#7a3f27",
        pebble=("#8f4a30", "#f2cd96", "#b56f43"), root="#8f4a30", hole="#6b3524", hole_rim="#e7a874",
        shade_to="#5a2a30", edge_to="#3a1c1f",
        crust=dict(ink="#7a3f27", top="#f9dca3", hi="#fff1c9", body="#ecc07f", deep="#d99d62"),
        tuft=("#c2ad5a", "#8d7a3a", "#e0cc7a"), flowers=("#ff8fa3", "#fff0c4", "#ffb347"),
        masonry=("#e9c08e", "#cf9f6e", "#fbdcae", "#87503a"),
    ),
    "glacier": dict(
        base="#7fb0cf", lo="#6c9dc0", hi="#97c4de", band="#5f8db5", band_hi="#c2e1ef",
        stone="#66778f", stone_lo="#4e6078", stone_hi="#93a5ba", stone_ink="#26384f",
        pebble=("#4b6380", "#dff0f8", "#6f90ad"), root="#3f6d96", hole="#3d5d80", hole_rim="#dff0f8",
        shade_to="#2a4166", edge_to="#18263f",
        crust=dict(ink="#4f7395", top="#ffffff", hi="#ffffff", body="#eef7fb", deep="#d3e7f1"),
        tuft=("#ffffff", "#c7dfec", "#e6f4fa"), flowers=("#bfeaf5", "#ffffff", "#9fd6ea"),
        masonry=("#bcd2e2", "#9ab6cc", "#e2eff6", "#3f5873"),
    ),
    "volcano": dict(
        base="#4b4049", lo="#3f353e", hi="#5b4e58", band="#251c25", band_hi="#8a7686",
        stone="#7a6875", stone_lo="#5e4d5c", stone_hi="#9c8894", stone_ink="#251a24",
        pebble=("#2e2330", "#8a7684", "#ff8a3d"), root="#ff7a3d", hole="#2a1f2b", hole_rim="#8a7684",
        shade_to="#2a1c2c", edge_to="#170f18",
        crust=dict(ink="#1f1620", top="#9a8590", hi="#b9a5ae", body="#76626f", deep="#5f4d5c"),
        tuft=("#3a2c38", "#211821", "#5a4752"), flowers=("#ffb347", "#ffd35c", "#ff7a3d"),
        masonry=("#7d6d7b", "#64546a", "#9a8a96", "#231a25"),
    ),
}


# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------

def canvas(w, h):
    s = cairo.ImageSurface(cairo.FORMAT_ARGB32, w * SS, h * SS)
    ctx = cairo.Context(s)
    ctx.scale(SS, SS)
    ctx.set_line_join(cairo.LINE_JOIN_ROUND)
    ctx.set_line_cap(cairo.LINE_CAP_ROUND)
    return s, ctx


def to_image(s, w, h):
    s.flush()
    im = Image.frombuffer("RGBA", (s.get_width(), s.get_height()), bytes(s.get_data()), "raw", "BGRa", 0, 1)
    return im.resize((w, h), Image.BOX)


def variant(im, to, t, lift=0.0):
    """Darken a texture toward a tone (shade/edge copies baked at build time)."""
    tint = Image.new("RGBA", im.size, to)
    out = Image.blend(im.convert("RGBA"), tint, t)
    if lift:
        out = Image.blend(out, im, lift)
    return out


def material_manifest():
    return json.loads((ART / "source/materials/provenance.json").read_text(encoding="utf-8"))


def painted_fill(biome):
    entries = material_manifest()["assets"]
    if {entry["name"] for entry in entries} != set(BIOMES):
        raise ValueError("Painted materials must cover all four biomes")
    entry = next(entry for entry in entries if entry["name"] == biome)
    path = ART / "source/materials" / entry["source"]
    if hashlib.sha256(path.read_bytes()).hexdigest() != entry["sha256"]:
        raise ValueError(f"Material master changed without a provenance review: {path}")
    if entry["output_size"] != [T, T]:
        raise ValueError(f"Material dimensions disagree with the painter: {biome}")
    with Image.open(path) as master:
        if master.width != master.height:
            raise ValueError(f"Material master must be square: {path}")
        return master.convert("RGB").resize((T, T), Image.Resampling.LANCZOS).convert("RGBA")


# --------------------------------------------------------------------------
# crust and tufts
# --------------------------------------------------------------------------

def crust(biome, p, r):
    """Surface lip, 512 x CR cells.  Opaque = crust, alpha 0 = fill, other = lip shadow."""
    c = p["crust"]
    s, ctx = canvas(T, CR)
    # per-column lip length: smooth periodic wave + drips
    def lip(x):
        base = {"meadow": 6.5, "desert": 4.5, "glacier": 6.0, "volcano": 3.5}[biome]
        v = base + 1.3 * math.sin(x / T * math.tau * 3 + 0.7) + 0.8 * math.sin(x / T * math.tau * 7 + 2.1)
        return v
    drips = []
    for _ in range({"meadow": 16, "desert": 8, "glacier": 18, "volcano": 10}[biome]):
        drips.append((r.uniform(0, T), r.uniform(2.5, 5.5), r.uniform(3, 8.5)))
    def drip_extra(x):
        best = 0.0
        for (dx, w, L) in drips:
            d = min(abs(x - dx), T - abs(x - dx))
            if d < w:
                best = max(best, L * math.cos(d / w * math.pi / 2) ** 1.5)
        return best
    xs = [x * 0.5 for x in range(-8, T * 2 + 9)]
    edge = [(x, lip(x) + drip_extra(x % T)) for x in xs]
    body = lambda cc: poly(cc, [(xs[0], -1), (xs[-1], -1)] + edge[::-1])
    # lip shadow zone (marker alpha) a few cells below the lip
    ctx.new_path(); poly(ctx, [(xs[0], -1), (xs[-1], -1)] + [(x, y + 3.2) for (x, y) in edge[::-1]])
    src(ctx, "#000000", 0.5); ctx.fill()
    ctx.set_operator(cairo.OPERATOR_SOURCE)
    ctx.new_path(); poly(ctx, [(xs[0], -1), (xs[-1], -1)] + [(x, y + 1.1) for (x, y) in edge[::-1]])
    src(ctx, c["ink"]); ctx.fill()
    ctx.set_operator(cairo.OPERATOR_OVER)
    ctx.new_path(); body(ctx); src(ctx, c["body"]); ctx.fill()
    ctx.save(); ctx.new_path(); body(ctx); ctx.clip()
    # A soft crown gives the surface volume without extending into empty cells.
    grad = cairo.LinearGradient(0, 0, 0, 11)
    from build_art_core import rgb
    for at, col in ((0, c["top"]), (0.26, c["body"]), (1, c["deep"])):
        grad.add_color_stop_rgba(at, *rgb(col))
    ctx.set_source(grad); ctx.paint()
    ctx.new_path(); poly(ctx, [(x, y - 1.6) for (x, y) in edge] + [(xs[-1], CR), (xs[0], CR)])
    src(ctx, c["deep"]); ctx.fill()
    # Broken highlights read as moss/snow grains instead of a ruler-straight stripe.
    for k in range(T // 2):
        x, yy = r.uniform(0, T), r.uniform(0.6, 3.0)
        length = r.uniform(0.8, 3.0)
        for dx in (-T, 0, T):
            ctx.new_path(); ellipse(ctx, x + dx, yy, length, r.uniform(0.3, 0.7))
            src(ctx, c["hi"], r.uniform(0.35, 0.75)); ctx.fill()
    # texture strokes inside the lip
    if biome in ("meadow", "glacier"):
        for k in range(300):
            x = r.uniform(0, T)
            y = r.uniform(3, 9)
            L = r.uniform(1.5, 3.5)
            col = c["top"] if biome == "glacier" else r.choice((c["top"], c["deep"]))
            for dx in (-T, 0, T):
                ctx.new_path(); ctx.move_to(x + dx, y); ctx.line_to(x + dx + 0.6, y + L)
                src(ctx, col, 0.55); ctx.set_line_width(0.8); ctx.stroke()
    elif biome == "desert":
        for k in range(5):
            y = 2.5 + k * 1.3
            ctx.new_path()
            for x in range(-4, T + 5, 2):
                yy = y + 0.4 * math.sin(x / T * math.tau * (6 + k) + k)
                (ctx.line_to if x > -4 else ctx.move_to)(x, yy)
            src(ctx, c["deep"], 0.5); ctx.set_line_width(0.5); ctx.stroke()
    else:  # volcano: scorched crust with ember cracks
        for k in range(18):
            x = r.uniform(0, T)
            for dx in (-T, 0, T):
                ctx.new_path(); ctx.move_to(x + dx, 0.5); ctx.line_to(x + dx + r.uniform(-1, 1), r.uniform(2, 3.5))
                src(ctx, "#ff8a3d", 0.75); ctx.set_line_width(0.6); ctx.stroke()
    ctx.restore()
    # Fine dark boundary preserves the exact collision contour.
    ctx.new_path(); ctx.rectangle(-8, 0, T + 16, 0.65); src(ctx, c["ink"]); ctx.fill()
    im = to_image(s, T, CR)
    # quantise alpha into the three-way contract
    px = im.load()
    for y in range(CR):
        for x in range(T):
            r_, g_, b_, a_ = px[x, y]
            if a_ >= 168:
                # un-premultiplied by PIL already; force opaque
                px[x, y] = (r_, g_, b_, 255)
            elif a_ >= 40:
                px[x, y] = (0, 0, 0, 128)
            else:
                px[x, y] = (0, 0, 0, 0)
    return im


def tufts(biome, p, r):
    """Fringe drawn into empty cells above the surface; bottom row = just above ground."""
    s, ctx = canvas(T, TU)
    base = TU + 0.6
    g, gd, gl = p["tuft"]
    if biome == "meadow":
        for _ in range(240):
            x = r.uniform(0, T)
            hgt = r.uniform(2.0, 6.5) if r.random() < 0.8 else r.uniform(6, 9)
            lean = r.uniform(-1.8, 1.8)
            col = r.choice((g, g, gl, gd))
            def blade(c, x=x, hgt=hgt, lean=lean, col=col):
                c.new_path(); c.move_to(x - 0.9, base); c.curve_to(x - 0.4, base - hgt * 0.6, x + lean * 0.6, base - hgt * 0.8,
                                                                    x + lean, base - hgt)
                c.curve_to(x + lean * 0.4, base - hgt * 0.7, x + 0.5, base - hgt * 0.4, x + 0.9, base)
                c.close_path(); src(c, gd); c.set_line_width(0.7); c.stroke_preserve(); src(c, col); c.fill()
            for dx in (-T, 0, T):
                ctx.save(); ctx.translate(dx, 0); blade(ctx); ctx.restore()
        for _ in range(14):
            x, hh = r.uniform(0, T), r.uniform(5, 8.5)
            col = r.choice(p["flowers"])
            for dx in (-T, 0, T):
                ctx.new_path(); ctx.move_to(x + dx, base); ctx.line_to(x + dx + 0.4, base - hh)
                src(ctx, gd); ctx.set_line_width(0.8); ctx.stroke()
                for k in range(5):
                    a = k / 5 * math.tau
                    ctx.new_path(); circle(ctx, x + dx + 0.4 + math.cos(a) * 1.1, base - hh + math.sin(a) * 1.1, 0.9)
                    src(ctx, col); ctx.fill()
                ctx.new_path(); circle(ctx, x + dx + 0.4, base - hh, 0.7); src(ctx, "#ffb347"); ctx.fill()
    elif biome == "desert":
        for _ in range(16):
            x = r.uniform(0, T)
            for dx in (-T, 0, T):
                for k in range(7):
                    a = -math.pi / 2 + (k - 3) * 0.28
                    L = r.uniform(3, 6.5)
                    ctx.new_path(); ctx.move_to(x + dx, base)
                    ctx.line_to(x + dx + math.cos(a) * L, base + math.sin(a) * L)
                    src(ctx, r.choice((g, gd, gl))); ctx.set_line_width(0.7); ctx.stroke()
        for _ in range(30):
            x = r.uniform(0, T)
            s_ = r.uniform(0.8, 1.6)
            for dx in (-T, 0, T):
                ctx.new_path(); ellipse(ctx, x + dx, base - s_ * 0.6, s_ * 1.4, s_)
                src(ctx, p["stone_ink"]); ctx.set_line_width(0.5); ctx.stroke_preserve()
                src(ctx, r.choice(p["pebble"])); ctx.fill()
    elif biome == "glacier":
        # soft rolling snow lip and a few ice spikes
        pts = [(x, base - 1.6 - 1.2 * (0.5 + 0.5 * math.sin(x / T * math.tau * 9 + 0.3))
                - 0.9 * (0.5 + 0.5 * math.sin(x / T * math.tau * 23 + 1.1))) for x in range(-4, T + 5, 2)]
        ctx.new_path(); poly(ctx, pts + [(T + 4, base), (-4, base)])
        src(ctx, "#ffffff"); ctx.fill_preserve(); src(ctx, p["crust"]["ink"], 0.6); ctx.set_line_width(0.5); ctx.stroke()
        for _ in range(18):
            x = r.uniform(0, T)
            hh = r.uniform(3.5, 8)
            ww = r.uniform(1.2, 2.2)
            for dx in (-T, 0, T):
                ctx.new_path(); poly(ctx, [(x + dx - ww, base), (x + dx + 0.3, base - hh), (x + dx + ww, base)])
                src(ctx, p["crust"]["ink"]); ctx.set_line_width(0.6); ctx.stroke_preserve()
                src(ctx, "#cdeef7"); ctx.fill()
                ctx.new_path(); poly(ctx, [(x + dx - ww * 0.3, base - 0.6), (x + dx + 0.2, base - hh * 0.8),
                                          (x + dx + 0.1, base - 0.6)]); src(ctx, "#ffffff", 0.9); ctx.fill()
    else:  # volcano: charred stubs and loose cinders
        for _ in range(26):
            x = r.uniform(0, T)
            hh = r.uniform(1.8, 5.5)
            for dx in (-T, 0, T):
                ctx.new_path(); poly(ctx, [(x + dx - 1.2, base), (x + dx - 0.3, base - hh), (x + dx + 0.5, base - hh + 0.6),
                                          (x + dx + 1.2, base)])
                src(ctx, gd); ctx.fill()
        for _ in range(26):
            x = r.uniform(0, T)
            for dx in (-T, 0, T):
                ctx.new_path(); circle(ctx, x + dx, base - r.uniform(0.6, 1.2), r.uniform(0.6, 1.1))
                src(ctx, r.choice((g, gl))); ctx.fill()
        for _ in range(9):
            x = r.uniform(0, T)
            for dx in (-T, 0, T):
                ctx.new_path(); circle(ctx, x + dx, base - 0.8, 0.7); src(ctx, "#ffb347"); ctx.fill()
    return to_image(s, T, TU)


# --------------------------------------------------------------------------
# masonry and girder
# --------------------------------------------------------------------------

def masonry(biome, p, r):
    face, lo, hi, ink = p["masonry"]
    MW, MH = 128, 64
    s, ctx = canvas(MW, MH)
    src(ctx, mix(ink, lo, 0.35)); ctx.paint()
    for row in range(8):
        y = row * 8
        off = 8 if row % 2 else 0
        for k in range(8):
            x = k * 16 + off
            tone = mix(face, lo, r.uniform(0.05, 0.72))
            corners = [(x + 1.5, y + 0.6), (x + 13.5, y + r.uniform(0.4, 0.9)),
                       (x + 15.5, y + 2), (x + 15.1, y + 6.6),
                       (x + 13.5, y + 7.5), (x + 1.4, y + 7.2), (x + 0.4, y + 5.7), (x + 0.7, y + 2)]
            grains = [(x + r.uniform(2, 14), y + r.uniform(1.5, 6.5), r.uniform(0.25, 0.7)) for _ in range(9)]
            for dx in (-MW, 0):
                ctx.save(); ctx.translate(dx, 0)
                ctx.new_path(); poly(ctx, corners); src(ctx, mix(tone, lo, 0.5)); ctx.fill()
                ctx.new_path(); poly(ctx, [(a, b - 0.8) for a, b in corners]); src(ctx, tone); ctx.fill()
                ctx.new_path(); poly(ctx, corners[:3], close=False); src(ctx, hi, 0.65); ctx.set_line_width(0.7); ctx.stroke()
                for gx, gy, rr in grains:
                    ctx.new_path(); ellipse(ctx, gx, gy, rr * 1.8, rr); src(ctx, lo, 0.38); ctx.fill()
                ctx.restore()
            if r.random() < 0.35:
                cx, cy = x + r.uniform(4, 12), y + r.uniform(2, 5)
                for dx in (-MW, 0):
                    ctx.new_path(); poly(ctx, [(cx + dx, cy), (cx + dx + 1.5, cy + 1.2), (cx + dx + 1, cy + 2.6)], close=False)
                    src(ctx, ink, 0.5); ctx.set_line_width(0.55); ctx.stroke()
            if biome == "meadow" and r.random() < 0.25:
                cx = x + r.uniform(2, 13)
                moss_width = r.uniform(2, 4)
                for dx in (-MW, 0):
                    ctx.new_path(); ellipse(ctx, cx + dx, y + 7.4, moss_width, 0.8); src(ctx, "#648355", 0.8); ctx.fill()
    return to_image(s, MW, MH)


def girder():
    GW, GH = 32, 6
    s, ctx = canvas(GW, GH)
    ink, steel, hi, lo = "#182d35", "#c7643f", "#ee9a6d", "#8f3f2b"
    src(ctx, ink); ctx.paint()
    ctx.new_path(); ctx.rectangle(-1, 0.7, GW + 2, 1.3); src(ctx, steel); ctx.fill()
    ctx.new_path(); ctx.rectangle(-1, 0.7, GW + 2, 0.55); src(ctx, hi); ctx.fill()
    ctx.new_path(); ctx.rectangle(-1, 4.0, GW + 2, 1.3); src(ctx, lo); ctx.fill()
    ctx.new_path(); ctx.rectangle(-1, 2.0, GW + 2, 2.0); src(ctx, mix(steel, lo, 0.4)); ctx.fill()
    for x in (0, 16, 32):
        ctx.new_path(); poly(ctx, [(x - 6, 2.0), (x - 1, 4.0), (x + 1, 4.0), (x + 6, 2.0)]); src(ctx, ink, 0.55); ctx.fill()
    for x in (4, 12, 20, 28):
        ctx.new_path(); circle(ctx, x, 1.35, 0.42); src(ctx, "#ffe2c4"); ctx.fill()
        ctx.new_path(); circle(ctx, x, 4.65, 0.42); src(ctx, hi); ctx.fill()
    return to_image(s, GW, GH)


# --------------------------------------------------------------------------
# build
# --------------------------------------------------------------------------

def terrain_meta():
    """Static description of the kit (identical whether or not the section ran)."""
    biomes = {}
    for biome, p in BIOMES.items():
        biomes[biome] = {k: f"terrain/{biome}-{k}.png" for k in ("fill", "deep", "shade", "edge", "crust", "tufts", "masonry", "masonry-edge")}
        biomes[biome].update(minimap=p["base"], minimap_top=p["crust"]["top"])
    return {
        "cell": 2, "fill_size": [T, T], "crust_rows": CR, "tuft_rows": TU,
        "masonry_size": [128, 64], "girder": "terrain/girder.png", "girder_size": [32, 6],
        "edge_cells": 2, "shade_cells": 6, "deep_cells": DEEP,
        "contract": "crust alpha 255 = crust colour, 0 = fill texture, other = shade texture; tufts are "
                    "written with their own alpha into empty cells above a material-1 surface (bottom row "
                    "touches the ground); see docs/ART_DIRECTION.md 'Terrain material kit'",
        "biomes": biomes,
        "sampling": "mirrored repeat at 512 cells; world coordinates, independent of render tile",
        "source": "source/materials/provenance.json",
    }


def build_all():
    OUT.mkdir(parents=True, exist_ok=True)
    for i, (biome, p) in enumerate(BIOMES.items()):
        fill_im = painted_fill(biome)
        fill_im.save(OUT / f"{biome}-fill.png", optimize=True)
        variant(fill_im, p["shade_to"], 0.32).save(OUT / f"{biome}-shade.png", optimize=True)
        variant(fill_im, p["edge_to"], 0.72).save(OUT / f"{biome}-edge.png", optimize=True)
        variant(fill_im, p["shade_to"], 0.12).save(OUT / f"{biome}-deep.png", optimize=True)
        crust(biome, p, Rand(9100 + i)).save(OUT / f"{biome}-crust.png", optimize=True)
        tufts(biome, p, Rand(9200 + i)).save(OUT / f"{biome}-tufts.png", optimize=True)
        wall = masonry(biome, p, Rand(9300 + i)).convert("RGB").convert("RGBA")
        wall.save(OUT / f"{biome}-masonry.png", optimize=True)
        variant(wall, p["masonry"][3], 0.58).save(OUT / f"{biome}-masonry-edge.png", optimize=True)
    girder().convert("RGB").convert("RGBA").save(OUT / "girder.png", optimize=True)
    return {}


# --------------------------------------------------------------------------
# Reference painter (previews only; the game's painter is Ruby)
# --------------------------------------------------------------------------

def paint(mask, biome, tufts=False):
    """Paint a terrain cell mask (uint8 HxW, 0 air, 1 soil, 2 girder, 3 masonry) with the kit.

    This is the exact per-cell rule set proposed for terrain_painter.rb, written
    with numpy so previews stay fast.  Returns an RGBA PIL image at cell size.
    """
    import numpy as np

    def load(name):
        return np.asarray(Image.open(ART / name).convert("RGBA"))

    tex = {k: load(f"terrain/{biome}-{k}.png") for k in ("fill", "deep", "shade", "edge", "crust", "tufts", "masonry", "masonry-edge")}
    gird = load("terrain/girder.png")
    h, w = mask.shape
    solid = mask > 0
    up = np.zeros((h, w), np.int32)      # cells since air above (1 = surface)
    down = np.zeros((h, w), np.int32)    # cells until air below (1 = underside)
    gap = np.zeros((h, w), np.int32)     # for air: cells until solid below
    prev = np.zeros(w, np.int32)
    for y in range(h):
        prev = np.where(solid[y], prev + 1, 0)
        up[y] = prev
    prev = np.full(w, 99, np.int32)
    gprev = np.full(w, 999, np.int32)
    for y in range(h - 1, -1, -1):
        prev = np.where(solid[y], np.minimum(prev + 1, 99), 0)
        down[y] = prev
        gprev = np.where(solid[y], 0, gprev + 1)
        gap[y] = gprev
    left = np.zeros_like(solid); left[:, 1:] = solid[:, :-1]; left[:, 0] = True
    right = np.zeros_like(solid); right[:, :-1] = solid[:, 1:]; right[:, -1] = True
    side = solid & ~(left & right)
    ys, xs = np.mgrid[0:h, 0:w]
    tx, ty = xs % (T * 2), ys % (T * 2)
    tx, ty = np.minimum(tx, T * 2 - 1 - tx), np.minimum(ty, T * 2 - 1 - ty)
    out = np.where((up > DEEP)[..., None], tex["deep"][ty, tx], tex["fill"][ty, tx])
    crow = np.clip(up - 1, 0, CR - 1)
    crust = tex["crust"][crow, tx]
    in_crust = (up >= 1) & (up <= CR)
    ca = np.where(in_crust, crust[..., 3], 0)
    edge = (down <= 2) | side
    shade = ((ca > 0) & (ca < 255)) | (down <= 6)
    out = np.where(shade[..., None], tex["shade"][ty, tx], out)
    out = np.where(edge[..., None], tex["edge"][ty, tx], out)
    out = np.where((ca == 255)[..., None], crust, out)
    # masonry: own texture, edge-darkened rim
    m3 = mask == 3
    mas = tex["masonry"][ys % 64, xs % 128]
    mas_edge = tex["masonry-edge"][ys % 64, xs % 128]
    out = np.where(m3[..., None], np.where(edge[..., None], mas_edge, mas), out)
    # girder: row from its top
    m2 = mask == 2
    out = np.where(m2[..., None], gird[np.clip(up - 1, 0, 5), xs % 32], out)
    out[..., 3] = np.where(solid, 255, 0)
    if not tufts:
        # shipped painter: the visible mask is exactly the collision mask
        return Image.fromarray(out.astype(np.uint8), "RGBA")
    # optional: tufts into air directly above a soil surface
    k = gap
    below_y = np.clip(ys + k, 0, h - 1)
    ok = (~solid) & (k >= 1) & (k <= TU) & (mask[below_y, xs] == 1)
    trow = np.clip(TU - k, 0, TU - 1)
    tuft = tex["tufts"][trow, tx]
    out = np.where((ok & (tuft[..., 3] > 0))[..., None], tuft, out)
    return Image.fromarray(out.astype(np.uint8), "RGBA")
