"""Props, app icon and FX animation frames."""
from __future__ import annotations

import math

from PIL import Image, ImageFilter

from build_art_core import (
    ART, GOLD, INK, ORANGE, PAPER, RED, STEEL, STEEL_DARK, STEEL_LIGHT, TEAL, TEAMS, WHITE, WOOD, WOOD_DARK,
    Rand, circle, clip_to, darken, ellipse, fill, inked, lighten, lin_grad, outline_pass, poly, rad_grad, rrect,
    shine, smooth, src, star_pts, stroke, surface, svg_surface,
)

LW = 2.4

PROPS_META = {
    "app-icon": {"note": "also app-icon-{16,32,48,64,128,512,1024}.png"},
    "crate": {"note": "weapon crate; crate-health.png and crate-utility.png variants"},
    "grave": {"anchor": [32, 60], "note": "neutral; grave-{team}.png carry team ribbons"},
    "cloud": {"note": "transparent parallax cloud; cloud-small.png too"},
    "mine-prop": {"anchor": [16, 26], "note": "in-world land mine (blinking light frame: mine-prop-lit.png)"},
    "barrel-prop": {"anchor": [20, 46], "note": "in-world explosive drum"},
}

FX_META = {
    "explosion": {"frames": 9, "size": [160, 160], "anchor": [80, 80], "fps": 18,
                  "pattern": "fx/explosion-{frame}.png"},
    "smoke": {"frames": 6, "size": [64, 64], "anchor": [32, 32], "fps": 10, "pattern": "fx/smoke-{frame}.png"},
    "dust": {"frames": 5, "size": [64, 32], "anchor": [32, 28], "fps": 14, "pattern": "fx/dust-{frame}.png",
             "note": "landing/walk puff"},
    "splash": {"frames": 6, "size": [96, 96], "anchor": [48, 84], "fps": 14, "pattern": "fx/splash-{frame}.png",
               "note": "falling into water"},
    "sparkle": {"frames": 4, "size": [48, 48], "anchor": [24, 24], "fps": 12, "pattern": "fx/sparkle-{frame}.png"},
    "crosshair": {"frames": 1, "size": [40, 40], "anchor": [20, 20], "pattern": "ui/crosshair.png"},
    "wind-arrow": {"frames": 1, "size": [64, 32], "anchor": [32, 16], "pattern": "ui/wind-arrow.png",
                   "note": "points right; rotate/mirror for wind direction"},
    "turn-marker": {"frames": 4, "size": [32, 32], "anchor": [16, 30], "fps": 8,
                    "pattern": "ui/turn-marker-{frame}.png", "note": "bobbing arrow above the active grub; tint-free"},
}
for spec in FX_META.values():
    spec["raster_scale"] = 2
    spec["source_size"] = [value * 2 for value in spec["size"]]


def _shadow(path, alpha=0.26, off=(1, 2), blur=1.2, density=1):
    im = Image.open(path).convert("RGBA")
    sh = Image.new("RGBA", im.size, (24, 45, 53, 0))
    sh.putalpha(im.getchannel("A").point(lambda v: int(v * alpha)))
    sh = sh.filter(ImageFilter.GaussianBlur(blur * density))
    base = Image.new("RGBA", im.size, (0, 0, 0, 0))
    base.alpha_composite(sh, tuple(value * density for value in off))
    base.alpha_composite(im)
    base.save(path)


def _render(name, w, h, fn, sub="", svg=True, shadow=True):
    path = ART / sub / f"{name}.png"
    path.parent.mkdir(parents=True, exist_ok=True)
    # App-icon sizes are platform contracts; in-game props/effects use Retina
    # rasters while their scene and animation metadata stays in logical pixels.
    density = 1 if name.startswith("app-icon") else 2
    s, ctx = surface(w * density, h * density)
    ctx.scale(density, density)
    fn(ctx)
    s.write_to_png(str(path))
    if shadow:
        _shadow(path, density=density)
    if svg:
        vs, vctx = svg_surface(ART / "src" / sub / f"{name}.svg", w, h)
        fn(vctx)
        vs.finish()
    return path


# --------------------------------------------------------------------------
# Crates
# --------------------------------------------------------------------------

def crate(ctx, emblem="star", band=TEAL):
    box = lambda c: rrect(c, 6, 10, 52, 48, 5)
    inked(ctx, box, WOOD, LW)
    ctx.save()
    clip_to(ctx, box)
    for k, y in enumerate(range(10, 58, 12)):
        fill(ctx, lambda c, y=y, k=k: c.rectangle(6, y, 52, 12), darken(WOOD, 0.08 * (k % 2)))
        stroke(ctx, lambda c, y=y: (c.move_to(6, y), c.line_to(58, y)), WOOD_DARK, 1.2, 0.8)
        for x in (12, 30, 47):
            fill(ctx, lambda c, x=x + (k * 7) % 11, y=y: ellipse(c, x, y + 6, 2.2, 0.8), WOOD_DARK, 0.45)
    fill(ctx, lambda c: c.rectangle(46, 10, 14, 50), WOOD_DARK, 0.35)
    fill(ctx, lambda c: c.rectangle(6, 10, 52, 3), lighten(WOOD, 0.3), 0.8)
    # diagonal brace
    stroke(ctx, lambda c: (c.move_to(9, 55), c.line_to(55, 13)), INK, 7.6)
    stroke(ctx, lambda c: (c.move_to(9, 55), c.line_to(55, 13)), darken(WOOD, 0.15), 5)
    ctx.restore()
    stroke(ctx, box, INK, LW)
    # band
    inked(ctx, lambda c: rrect(c, 4, 27, 56, 13, 2), band, LW)
    stroke(ctx, lambda c: (c.move_to(6, 30), c.line_to(58, 30)), lighten(band, 0.4), 1.2)
    for (x, y) in ((6, 12), (58, 12), (6, 56), (58, 56)):
        inked(ctx, lambda c, x=x, y=y: rrect(c, x - 4, y - 4, 8, 8, 2), STEEL, LW * 0.8)
        fill(ctx, lambda c, x=x, y=y: circle(c, x, y, 1.2), INK)
    # emblem disc
    inked(ctx, lambda c: circle(c, 32, 33.5, 11), PAPER, LW)
    if emblem == "star":
        inked(ctx, lambda c: poly(c, star_pts(32, 34, 8, 3.6)), ORANGE, 1.6)
    elif emblem == "heart":
        inked(ctx, lambda c: (c.move_to(32, 41), c.curve_to(22, 35, 23, 26, 28, 27), c.curve_to(30, 27.5, 31.5, 29, 32, 30),
                              c.curve_to(32.5, 29, 34, 27.5, 36, 27), c.curve_to(41, 26, 42, 35, 32, 41), c.close_path()),
              "#ff6f86", 1.6)
    elif emblem == "bolt":
        inked(ctx, lambda c: poly(c, [(34, 24), (26, 35), (31, 35), (29, 43), (38, 31), (33, 31)]), GOLD, 1.6)
    shine(ctx, 13, 16, 9, 2.2, 0)


# --------------------------------------------------------------------------
# Grave
# --------------------------------------------------------------------------

def grave(ctx, team=None):
    # grass mound
    inked(ctx, lambda c: (c.move_to(4, 62), c.curve_to(10, 52, 54, 52, 60, 62), c.close_path()), "#7fb069", LW)
    stone = lambda c: (c.move_to(14, 58), c.line_to(14, 22), c.curve_to(14, 4, 50, 4, 50, 22), c.line_to(50, 58),
                       c.close_path())
    inked(ctx, stone, "#a9b4b8", LW)
    ctx.save()
    clip_to(ctx, stone)
    fill(ctx, lambda c: c.rectangle(40, 0, 20, 64), "#86949a", 0.8)
    fill(ctx, lambda c: (c.move_to(18, 58), c.line_to(18, 23), c.curve_to(18, 10, 36, 7, 42, 13), c.line_to(24, 58),
                         c.close_path()), "#c3ccd0", 0.6)
    fill(ctx, lambda c: ellipse(c, 22, 50, 6, 3), "#7fb069", 0.7)
    ctx.restore()
    stroke(ctx, stone, INK, LW)
    # engraved grub curl
    for w, col in ((4.2, "#5f6e74"), (1.6, "#d6dde0")):
        stroke(ctx, lambda c: (c.move_to(23, 40), c.curve_to(22, 30, 29, 25, 33, 26), c.curve_to(39, 27, 41, 34, 36, 37),
                               c.curve_to(32, 39, 29, 36, 31, 33)), col, w)
    fill(ctx, lambda c: circle(c, 36.5, 28, 1.3), "#5f6e74")
    for x in (24, 32, 40):
        stroke(ctx, lambda c, x=x: (c.move_to(x - 3, 47), c.line_to(x + 3, 47)), "#6c7a80", 1.6)
    if team is not None:
        col = TEAMS[team]
        rib = lambda c: (c.move_to(11, 17), c.curve_to(24, 22, 40, 22, 53, 17), c.line_to(53, 24),
                         c.curve_to(40, 29, 24, 29, 11, 24), c.close_path())
        inked(ctx, rib, col, LW * 0.9)
        for sx in (-1, 1):
            x = 32 + sx * 23
            inked(ctx, lambda c, x=x, s=sx: poly(c, [(x, 20), (x + s * 5, 30), (x + s * 1, 28), (x - s * 2, 32)]),
                  darken(col, 0.2), LW * 0.8)
    # flower + tufts
    stroke(ctx, lambda c: (c.move_to(54, 60), c.curve_to(55, 54, 53, 52, 55, 48)), "#4f8a4a", 1.8)
    for k in range(5):
        a = k * math.tau / 5
        inked(ctx, lambda c, a=a: circle(c, 55 + math.cos(a) * 2.6, 47 + math.sin(a) * 2.6, 2.0), WHITE, 1.0)
    fill(ctx, lambda c: circle(c, 55, 47, 1.6), GOLD)
    for x in (9, 16, 46):
        stroke(ctx, lambda c, x=x: (c.move_to(x, 60), c.line_to(x - 1.5, 55), c.move_to(x + 1.5, 60),
                                    c.line_to(x + 3, 54.5)), "#4f8a4a", 1.6)


# --------------------------------------------------------------------------
# Clouds
# --------------------------------------------------------------------------

def cloud(ctx, w, h, seed=3, col=WHITE, shade="#d8e3e8", lw=3.0):
    r = Rand(seed)
    base = h * 0.78
    puffs = []
    n = 6
    for i in range(n):
        u = (i + 0.5) / n
        x = w * (0.1 + 0.8 * u)
        rr = h * (0.22 + 0.2 * math.sin(math.pi * u)) * r.uniform(0.85, 1.1)
        y = base - rr * r.uniform(0.6, 1.0)
        puffs.append((x, y, rr))
    bottom = lambda c: rrect(c, w * 0.08, base - h * 0.2, w * 0.84, h * 0.2, h * 0.1)
    fns = [lambda c, p=p: circle(c, *p) for p in puffs] + [bottom]
    outline_pass(ctx, fns, lw / 2, INK)
    for fn in fns:
        fill(ctx, fn, shade)
    ctx.save()
    ctx.new_path()
    for fn in fns:
        fn(ctx)
    ctx.clip()
    for (x, y, rr) in puffs:
        fill(ctx, lambda c, x=x, y=y, rr=rr: circle(c, x - rr * 0.12, y - rr * 0.16, rr * 0.92), col)
    for (x, y, rr) in puffs[1:4]:
        fill(ctx, lambda c, x=x, y=y, rr=rr: circle(c, x - rr * 0.3, y - rr * 0.38, rr * 0.4), WHITE, 0.9)
    ctx.restore()


# --------------------------------------------------------------------------
# App icon
# --------------------------------------------------------------------------

def app_icon(ctx, size):
    from build_art_grubs import Pose, draw_grub

    k = size / 256
    ctx.scale(k, k)
    tile = lambda c: rrect(c, 10, 10, 236, 236, 52)
    ctx.save()
    clip_to(ctx, tile)
    ctx.set_source(rad_grad(150, 90, 10, 230, [(0, "#7fd0c8"), (0.55, TEAL), (1, "#244b52")]))
    ctx.paint()
    # sunburst
    for i in range(16):
        a0 = i * math.tau / 16
        fill(ctx, lambda c, a0=a0: poly(c, [(150, 110), (150 + math.cos(a0) * 300, 110 + math.sin(a0) * 300),
                                            (150 + math.cos(a0 + 0.2) * 300, 110 + math.sin(a0 + 0.2) * 300)]),
             WHITE, 0.08)
    # explosion puff behind
    for (x, y, r, col) in ((196, 66, 34, ORANGE), (214, 98, 24, GOLD), (176, 44, 20, "#ffd35c")):
        inked(ctx, lambda c, x=x, y=y, r=r: circle(c, x, y, r), col, 0)
    inked(ctx, lambda c: poly(c, star_pts(200, 70, 40, 24, 9, 0.3)), "#ffd35c", 4.5)
    inked(ctx, lambda c: poly(c, star_pts(200, 70, 22, 13, 9, 0.5)), WHITE, 0)
    # dirt hill
    inked(ctx, lambda c: (c.move_to(0, 214), c.curve_to(60, 180, 180, 186, 256, 206), c.line_to(256, 256),
                          c.line_to(0, 256), c.close_path()), "#8b5e3c", 5)
    fill(ctx, lambda c: (c.move_to(0, 214), c.curve_to(60, 180, 180, 186, 256, 206), c.line_to(256, 216),
                         c.curve_to(180, 198, 60, 192, 0, 226), c.close_path()), "#7fb069")
    # hero grub, big
    ctx.save()
    ctx.translate(-14, 20)
    ctx.scale(3.0, 3.0)
    pose = Pose([(12.5, 64.0), (21.5, 63.4), (31.5, 60.0), (40.5, 54.8), (44.5, 47.0), (45.4, 40.5), (45.8, 32.0)],
                [2.6, 6.0, 9.4, 10.8, 10.4, 9.8, 15.0], look=(0.6, -0.1), mouth="grin", brow=0.7, low_lid=0.12,
                scarf_phase=0.8)
    draw_grub(ctx, pose, 0, lw=2.4)
    ctx.restore()
    ctx.restore()
    stroke(ctx, tile, INK, 9)
    stroke(ctx, lambda c: rrect(c, 17, 17, 222, 222, 46), WHITE, 2.5, 0.35)


# --------------------------------------------------------------------------
# In-world props
# --------------------------------------------------------------------------

def mine_prop(ctx, lit):
    from build_art_icons import mine_shape
    ctx.translate(16, 25)
    ctx.scale(0.72, 0.72)
    ctx.translate(-16, -25)
    mine_shape(ctx, 16, 25, 13, blink=False)
    col = "#ff4a3d" if lit else "#7a2a2a"
    if lit:
        fill(ctx, lambda c: circle(c, 16, 12.6, 7), "#ff4a3d", 0.3)
    inked(ctx, lambda c: circle(c, 16, 12.6, 3.2), col, 1.6)
    if lit:
        fill(ctx, lambda c: circle(c, 15.2, 11.8, 1.0), WHITE)


def barrel_prop(ctx):
    from build_art_icons import ICONS
    ctx.scale(40 / 64, 48 / 64)
    ctx.translate(0, -4)
    ICONS["barrel"](ctx)


# --------------------------------------------------------------------------
# FX
# --------------------------------------------------------------------------

def explosion(ctx, k, n=9):
    t = k / (n - 1)
    cx, cy = 80, 80
    r = Rand(77)
    lw = 3.0
    if k == 0:
        inked(ctx, lambda c: poly(c, star_pts(cx, cy, 30, 12, 8, 0.2)), "#fff3b8", lw)
        fill(ctx, lambda c: poly(c, star_pts(cx, cy, 16, 7, 8, 0.4)), WHITE)
        return
    if k == 1:
        inked(ctx, lambda c: poly(c, star_pts(cx, cy, 58, 30, 10, 0.1)), ORANGE, lw)
        inked(ctx, lambda c: poly(c, star_pts(cx, cy, 44, 22, 10, 0.3)), "#ffd35c", 0)
        fill(ctx, lambda c: circle(c, cx, cy, 20), WHITE)
        return
    # debris shards flying out
    dr = Rand(5)
    for i in range(9):
        a = i * math.tau / 9 + dr.jit(0.3)
        dist = 30 + 50 * t ** 0.7
        if dist > 76:
            continue
        x, y = cx + math.cos(a) * dist, cy + math.sin(a) * dist + 20 * t * t
        sz = 4.5 * (1 - t * 0.6)
        ctx.save()
        ctx.translate(x, y)
        ctx.rotate(a * 3 + k)
        inked(ctx, lambda c, s=sz: poly(c, [(-s, -s * 0.6), (s, -s * 0.4), (s * 0.4, s * 0.8), (-s * 0.8, s * 0.5)]),
              "#8b5e3c" if i % 2 else "#5d4636", 1.6)
        ctx.restore()
    # smoke ring
    smoke_r = 34 + 28 * t
    smoke_a = max(0.0, min(1.0, (t - 0.3) * 2.5))
    puffs = []
    for i in range(10):
        a = i * math.tau / 10 + r.jit(0.2)
        rr = (16 + 10 * t) * r.uniform(0.8, 1.15)
        puffs.append((cx + math.cos(a) * smoke_r * 0.62, cy + math.sin(a) * smoke_r * 0.55 - 10 * t, rr))
    fade = 1 - max(0.0, (t - 0.75) / 0.4)
    if smoke_a > 0 and fade > 0.02:
        smoke_col = "#5f5a5e" if t < 0.6 else "#8a8488"
        shrink = 1 - max(0.0, (t - 0.7)) * 1.4
        outline_pass(ctx, [lambda c, p=p: circle(c, p[0], p[1], p[2] * shrink) for p in puffs], lw / 2)
        for p in puffs:
            fill(ctx, lambda c, p=p: circle(c, p[0], p[1], p[2] * shrink), smoke_col)
        for p in puffs:
            fill(ctx, lambda c, p=p: circle(c, p[0] - p[2] * 0.2, p[1] - p[2] * 0.25, p[2] * shrink * 0.6),
                 lighten(smoke_col, 0.25))
    # fireball core
    core = max(0.0, 1 - t * 1.25)
    if core > 0.02:
        fr = 54 * core + 12
        fb = [(cx + r.jit(18) * core, cy + r.jit(12) * core - 6 * t, fr * r.uniform(0.55, 0.8)) for _ in range(6)]
        outline_pass(ctx, [lambda c, p=p: circle(c, *p) for p in fb], lw / 2)
        for p in fb:
            fill(ctx, lambda c, p=p: circle(c, *p), "#e8513f")
        for p in fb:
            fill(ctx, lambda c, p=p: circle(c, p[0] - p[2] * 0.1, p[1] - p[2] * 0.15, p[2] * 0.78), ORANGE)
        for p in fb[:4]:
            fill(ctx, lambda c, p=p: circle(c, p[0] - p[2] * 0.2, p[1] - p[2] * 0.3, p[2] * 0.48), "#ffd35c")
        if t < 0.35:
            fill(ctx, lambda c: circle(c, cx - 4, cy - 8, 12 * core), WHITE, 0.9)
    # embers
    for i in range(7):
        a = i * math.tau / 7 + 0.4
        dist = 20 + 60 * t
        if dist > 74:
            continue
        x, y = cx + math.cos(a) * dist, cy + math.sin(a) * dist * 0.8 - 8 * t
        inked(ctx, lambda c, x=x, y=y: circle(c, x, y, 2.6 * (1 - t)), "#ffd35c", 1.2)


def smoke(ctx, k, n=6):
    t = k / (n - 1)
    r = Rand(11)
    a = 1 - t * 0.85
    puffs = [(32 + r.jit(8), 34 - t * 10 + r.jit(5), (8 + 10 * t) * r.uniform(0.7, 1.0)) for _ in range(4)]
    for (x, y, rr) in puffs:
        inked(ctx, lambda c, x=x, y=y, rr=rr: circle(c, x, y, rr), "#9a9498", 2.0, INK, a)
    for (x, y, rr) in puffs:
        fill(ctx, lambda c, x=x, y=y, rr=rr: circle(c, x - rr * 0.2, y - rr * 0.25, rr * 0.55), "#c9c4c6", a)


def dust(ctx, k, n=5):
    t = k / (n - 1)
    a = 1 - t * 0.9
    for sx in (-1, 1):
        x = 32 + sx * (8 + 18 * t)
        y = 26 - 4 * t
        rr = 5 + 4 * t * (1 - t) * 3
        inked(ctx, lambda c, x=x, y=y, rr=rr: (circle(c, x, y, rr), circle(c, x + sx * rr * 0.8, y + 1, rr * 0.7)),
              "#e4d6b8", 1.6, INK, a)


def splash(ctx, k, n=6):
    t = k / (n - 1)
    a = 1 - max(0.0, t - 0.6) * 2.2
    h = 60 * math.sin(math.pi * min(1.0, t * 1.3))
    for i, dx in enumerate((-16, -6, 6, 16)):
        hh = h * (0.7 + 0.3 * (i % 2))
        col = "#7cc6dd" if i % 2 else "#a9e4f2"
        inked(ctx, lambda c, dx=dx, hh=hh: (c.move_to(48 + dx - 5, 84), c.curve_to(48 + dx * 1.3 - 3, 84 - hh, 48 + dx * 1.3 + 3,
                                                                                  84 - hh, 48 + dx + 5, 84), c.close_path()),
              col, 2.0, INK, a)
    for i in range(6):
        ang = -math.pi / 2 + (i - 2.5) * 0.35
        d = 20 + 50 * t
        x, y = 48 + math.cos(ang) * d * 0.8, 84 + math.sin(ang) * d + 60 * t * t
        if y < 88:
            inked(ctx, lambda c, x=x, y=y: circle(c, x, y, 3.4 * (1 - t * 0.5)), "#a9e4f2", 1.4, INK, a)
    inked(ctx, lambda c: ellipse(c, 48, 86, 20 + 20 * t, 5), "#7cc6dd", 2.0, INK, a)


def sparkle_fx(ctx, k):
    s = [0.4, 1.0, 0.7, 0.3][k]
    rot = k * 0.4
    inked(ctx, lambda c: poly(c, [(24 + math.cos(rot + i * math.pi / 4) * (18 * s if i % 2 == 0 else 5 * s),
                                   24 + math.sin(rot + i * math.pi / 4) * (18 * s if i % 2 == 0 else 5 * s))
                                  for i in range(8)]), GOLD, 2.0)
    fill(ctx, lambda c: circle(c, 24, 24, 3.5 * s), WHITE)


def crosshair(ctx):
    for w, col in ((5.5, INK), (2.6, WHITE)):
        stroke(ctx, lambda c: circle(c, 20, 20, 12), col, w)
        stroke(ctx, lambda c: (c.move_to(20, 2), c.line_to(20, 11), c.move_to(20, 29), c.line_to(20, 38),
                               c.move_to(2, 20), c.line_to(11, 20), c.move_to(29, 20), c.line_to(38, 20)), col, w)
    inked(ctx, lambda c: circle(c, 20, 20, 2.6), ORANGE, 1.4)


def wind_arrow(ctx):
    arrow = lambda c: poly(c, [(4, 11), (40, 11), (40, 3), (60, 16), (40, 29), (40, 21), (4, 21)])
    inked(ctx, arrow, "#bfe9ea", 2.6)
    ctx.save()
    clip_to(ctx, arrow)
    fill(ctx, lambda c: c.rectangle(0, 17, 64, 20), "#7fc8c8")
    for x in (10, 20, 30):
        fill(ctx, lambda c, x=x: c.rectangle(x, 0, 4, 32), WHITE, 0.5)
    ctx.restore()
    stroke(ctx, arrow, INK, 2.6)


def turn_marker(ctx, k):
    dy = [0, -2, -3, -2][k]
    tri = lambda c: (c.move_to(6, 8 + dy), c.line_to(26, 8 + dy), c.line_to(16, 26 + dy), c.close_path())
    inked(ctx, tri, GOLD, 2.6)
    fill(ctx, lambda c: poly(c, [(10, 10 + dy), (16, 10 + dy), (14, 15 + dy)]), WHITE, 0.8)


# --------------------------------------------------------------------------

def build_all():
    _render("crate", 64, 64, lambda c: crate(c, "star", TEAL))
    _render("crate-health", 64, 64, lambda c: crate(c, "heart", "#e0607a"))
    _render("crate-utility", 64, 64, lambda c: crate(c, "bolt", ORANGE))
    _render("grave", 64, 64, lambda c: grave(c))
    for t in range(6):
        _render(f"grave-{t}", 64, 64, lambda c, t=t: grave(c, t), svg=False)
    _render("cloud", 256, 128, lambda c: cloud(c, 256, 128, 3), shadow=False)
    _render("cloud-small", 128, 64, lambda c: cloud(c, 128, 64, 8, lw=2.4), shadow=False)
    _render("mine-prop", 32, 32, lambda c: mine_prop(c, False), svg=False)
    _render("mine-prop-lit", 32, 32, lambda c: mine_prop(c, True), svg=False)
    _render("barrel-prop", 40, 48, barrel_prop, svg=False)
    for size in (256, 16, 32, 48, 64, 128, 512, 1024):
        name = "app-icon" if size == 256 else f"app-icon-{size}"
        _render(name, size, size, lambda c, s=size: app_icon(c, s), svg=(size == 256), shadow=False)
    for k in range(9):
        _render(f"explosion-{k}", 160, 160, lambda c, k=k: explosion(c, k), "fx", svg=False, shadow=False)
    for k in range(6):
        _render(f"smoke-{k}", 64, 64, lambda c, k=k: smoke(c, k), "fx", svg=False, shadow=False)
        _render(f"splash-{k}", 96, 96, lambda c, k=k: splash(c, k), "fx", svg=False, shadow=False)
    for k in range(5):
        _render(f"dust-{k}", 64, 32, lambda c, k=k: dust(c, k), "fx", svg=False, shadow=False)
    for k in range(4):
        _render(f"sparkle-{k}", 48, 48, lambda c, k=k: sparkle_fx(c, k), "fx", svg=False, shadow=False)
        _render(f"turn-marker-{k}", 32, 32, lambda c, k=k: turn_marker(c, k), "ui", svg=False)
    _render("crosshair", 40, 40, crosshair, "ui", svg=False, shadow=False)
    _render("wind-arrow", 64, 32, wind_arrow, "ui", svg=False)
    return {}
