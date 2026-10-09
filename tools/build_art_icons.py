"""Weapon / utility icons: 64x64 transparent, chunky ink outlines, soft drop shadow."""
from __future__ import annotations

import math

from PIL import Image, ImageFilter

from build_art_core import (
    ART, BLUE, GOLD, GREEN, GREEN_DARK, INK, ORANGE, PAPER, PURPLE, RED, RED_DARK, SKIN, SKIN_SHADE,
    STEEL, STEEL_DARK, STEEL_LIGHT, TEAL, WHITE, WOOD, WOOD_DARK, circle, clip_to, darken, ellipse,
    fill, inked, lighten, poly, rrect, shine, smooth, src, star_pts, stroke, surface, svg_surface,
)

LW = 2.4
BOMB = "#2c4752"
FLAME_R = "#e8513f"
FLAME_O = ORANGE
FLAME_Y = "#ffd35c"
ICE = "#a9e4f2"
SMOKE = "#e9e2d2"
GOO = "#8fd16a"
WOOL = "#fbf6ea"
FUR = "#9a6b4f"


# --------------------------------------------------------------------------
# Building blocks
# --------------------------------------------------------------------------

def I(ctx, fn, col, lw=LW):
    inked(ctx, fn, col, lw)


def spark(ctx, x, y, r, rot=0.2):
    I(ctx, lambda c: poly(c, star_pts(x, y, r, r * 0.42, 6, rot)), FLAME_Y, LW * 0.8)
    fill(ctx, lambda c: poly(c, star_pts(x, y, r * 0.5, r * 0.22, 6, rot + 0.3)), WHITE)


def flame(ctx, x, y, s, rot=0.0, layers=(FLAME_R, FLAME_O, FLAME_Y), lw=LW):
    """Teardrop flame pointing up (local) at base (x, y) with size s."""
    ctx.save()
    ctx.translate(x, y)
    ctx.rotate(rot)
    for i, col in enumerate(layers):
        k = 1 - i * 0.3
        def fl(c, k=k):
            c.move_to(0, -s * 1.15 * k)
            c.curve_to(s * 0.25 * k, -s * 0.6 * k, s * 0.62 * k, -s * 0.35 * k, s * 0.52 * k, s * 0.05)
            c.curve_to(s * 0.45 * k, s * 0.42, -s * 0.45 * k, s * 0.42, -s * 0.52 * k, s * 0.05)
            c.curve_to(-s * 0.6 * k, -s * 0.3 * k, -s * 0.12 * k, -s * 0.5 * k, 0, -s * 1.15 * k)
            c.close_path()
        if i == 0:
            I(ctx, fl, col, lw)
        else:
            ctx.save()
            ctx.translate(0, s * 0.12 * i)
            fill(ctx, fl, col)
            ctx.restore()
    ctx.restore()


def puff(ctx, x, y, r, col=SMOKE, lw=LW * 0.8):
    I(ctx, lambda c: (circle(c, x, y, r), circle(c, x + r * 0.8, y + r * 0.25, r * 0.75),
                      circle(c, x - r * 0.75, y + r * 0.3, r * 0.65)), col, lw)


def bomb(ctx, cx, cy, r, col=BOMB, fuse=(0.55, -0.85), lit=True, band=None):
    fx, fy = fuse
    nx, ny = cx + fx * r * 0.95, cy + fy * r * 0.95
    # cap + fuse
    ctx.save()
    ctx.translate(nx, ny)
    ctx.rotate(math.atan2(fy, fx) + math.pi / 2)
    I(ctx, lambda c: rrect(c, -r * 0.32, -r * 0.28, r * 0.64, r * 0.42, 1.5), STEEL)
    ctx.restore()
    ex, ey = nx + fx * r * 0.55 + 3, ny + fy * r * 0.55 - 1
    stroke(ctx, lambda c: (c.move_to(nx + fx * 2, ny + fy * 2),
                           c.curve_to(nx + fx * 6, ny + fy * 6 - 3, ex - 3, ey + 2, ex, ey)), INK, 4.4)
    stroke(ctx, lambda c: (c.move_to(nx + fx * 2, ny + fy * 2),
                           c.curve_to(nx + fx * 6, ny + fy * 6 - 3, ex - 3, ey + 2, ex, ey)), "#c9a77a", 2.0)
    body = lambda c: circle(c, cx, cy, r)
    I(ctx, body, col)
    ctx.save()
    clip_to(ctx, body)
    fill(ctx, lambda c: circle(c, cx + r * 0.25, cy + r * 0.3, r * 0.95), darken(col, 0.35), 0.7)
    fill(ctx, lambda c: circle(c, cx - r * 0.1, cy - r * 0.1, r * 0.82), col)
    if band:
        fill(ctx, lambda c: c.rectangle(cx - r, cy - r * 0.18, 2 * r, r * 0.36), band)
    ctx.restore()
    if band:
        stroke(ctx, lambda c: (c.move_to(cx - r, cy - r * 0.18), c.line_to(cx + r, cy - r * 0.18),
                               c.move_to(cx - r, cy + r * 0.18), c.line_to(cx + r, cy + r * 0.18)), INK, 1.2)
        stroke(ctx, body, INK, LW)
    shine(ctx, cx - r * 0.42, cy - r * 0.45, r * 0.55, r * 0.22, -0.7)
    fill(ctx, lambda c: circle(c, cx - r * 0.1, cy - r * 0.62, r * 0.08), WHITE, 0.9)
    if lit:
        spark(ctx, ex, ey, max(4.5, r * 0.45))


def rocket(ctx, cx, cy, L, w, ang, body=PAPER, nose=RED, fin=TEAL, exhaust=True):
    ctx.save()
    ctx.translate(cx, cy)
    ctx.rotate(ang)
    if exhaust:
        flame(ctx, -L / 2 - w * 0.2, 0, w * 1.3, -math.pi / 2)
    for sgn in (-1, 1):
        I(ctx, lambda c, s=sgn: poly(c, [(-L / 2 + 1, s * w * 0.6), (-L / 2 - w * 0.55, s * w * 1.45),
                                         (-L / 2 + w * 1.2, s * w * 1.25), (-L / 2 + w * 1.8, s * w * 0.6)]), fin)
    hull = lambda c: (c.move_to(-L / 2, -w), c.line_to(L / 2 - w * 1.6, -w),
                      c.curve_to(L / 2 - w * 0.6, -w, L / 2, -w * 0.35, L / 2 + w * 0.25, 0),
                      c.curve_to(L / 2, w * 0.35, L / 2 - w * 0.6, w, L / 2 - w * 1.6, w),
                      c.line_to(-L / 2, w), c.close_path())
    I(ctx, hull, body)
    ctx.save()
    clip_to(ctx, hull)
    fill(ctx, lambda c: c.rectangle(L / 2 - w * 1.6, -w * 2, w * 3, w * 4), nose)
    fill(ctx, lambda c: c.rectangle(-L / 2, w * 0.35, L * 1.2, w), darken(body, 0.18), 0.55)
    fill(ctx, lambda c: c.rectangle(-L / 2 + w * 0.6, -w, w * 0.7, 2 * w), fin)
    ctx.restore()
    stroke(ctx, hull, INK, LW)
    stroke(ctx, lambda c: (c.move_to(L / 2 - w * 1.6, -w), c.line_to(L / 2 - w * 1.6, w)), INK, 1.4)
    stroke(ctx, lambda c: (c.move_to(-L / 2 + w * 2.2, -w * 0.45), c.line_to(L / 2 - w * 2.2, -w * 0.45)),
           WHITE, 1.6, 0.9)
    ctx.restore()


def motion(ctx, pts_list, alpha=0.8):
    for (x0, y0, x1, y1) in pts_list:
        stroke(ctx, lambda c, a=(x0, y0, x1, y1): (c.move_to(a[0], a[1]), c.line_to(a[2], a[3])), INK, 2.0, alpha)


def glove(ctx, cx, cy, s, rot, col=RED, point=False):
    """Cartoon boxing-style fist, knuckles toward local +x."""
    ctx.save()
    ctx.translate(cx, cy)
    ctx.rotate(rot)
    ctx.scale(s, s)
    cuff = lambda c: rrect(c, -15, -7, 8, 14, 3)
    I(ctx, cuff, WHITE, LW / s)
    if point:
        I(ctx, lambda c: rrect(c, 2, -9, 15, 6.2, 3.1), col, LW / s)
    fist = lambda c: (c.move_to(-8, -9), c.curve_to(-2, -13, 9, -12, 10, -4), c.curve_to(11, 4, 6, 10, -2, 10),
                      c.curve_to(-6, 10, -8, 7, -8, 4), c.close_path())
    I(ctx, fist, col, LW / s)
    ctx.save()
    clip_to(ctx, fist)
    fill(ctx, lambda c: ellipse(c, 2, 8, 12, 5), darken(col, 0.25), 0.7)
    ctx.restore()
    stroke(ctx, lambda c: (c.move_to(3, -8), c.curve_to(0, -3, 0, 1, 3, 4)), INK, 1.6 / s)
    shine(ctx, 0, -7.5, 6, 2.4, -0.15)
    ctx.restore()


# --------------------------------------------------------------------------
# Icons
# --------------------------------------------------------------------------

ICONS = {}


def icon(name):
    def deco(fn):
        ICONS[name] = fn
        return fn
    return deco


@icon("rocket")
def _rocket(ctx):
    puff(ctx, 12, 50, 5.5)
    puff(ctx, 20, 42, 4.0)
    rocket(ctx, 35, 29, 34, 7, -0.72, PAPER, RED, TEAL)


@icon("mortar")
def _mortar(ctx):
    stroke(ctx, lambda c: (c.move_to(30, 22), c.curve_to(36, 4, 50, 4, 56, 14)), INK, 2.2, 0.6)
    ctx.set_dash([0.1, 5])
    stroke(ctx, lambda c: (c.move_to(30, 22), c.curve_to(36, 4, 50, 4, 56, 14)), INK, 3.2)
    ctx.set_dash([])
    I(ctx, lambda c: ellipse(c, 57, 18, 4.5, 5.8, 0.6), BOMB)
    I(ctx, lambda c: rrect(c, 8, 50, 40, 8, 3), STEEL_DARK)
    for x in (16, 36):
        I(ctx, lambda c, x=x: poly(c, [(x, 51), (x + 4, 51), (x + 10, 40), (x + 6, 40)]), STEEL)
    ctx.save()
    ctx.translate(26, 38)
    ctx.rotate(-0.85)
    tube = lambda c: rrect(c, -8, -8, 32, 16, 4)
    I(ctx, tube, "#6b8f5a")
    fill(ctx, lambda c: c.rectangle(-6, 2, 28, 4.5), darken("#6b8f5a", 0.25), 0.8)
    I(ctx, lambda c: rrect(c, 20, -9.5, 6, 19, 2), darken("#6b8f5a", 0.15))
    fill(ctx, lambda c: ellipse(c, 25, 0, 1.6, 5.5), INK)
    shine(ctx, 6, -4, 16, 2.4, 0)
    ctx.restore()
    I(ctx, lambda c: circle(c, 24, 40, 4), GOLD)


@icon("homing")
def _homing(ctx):
    for r, a in ((20, 0.25), (12, 0.45)):
        stroke(ctx, lambda c, r=r: circle(c, 42, 22, r), RED, 2.2, a + 0.4)
    stroke(ctx, lambda c: (c.move_to(42, 0), c.line_to(42, 8), c.move_to(42, 36), c.line_to(42, 44),
                           c.move_to(20, 22), c.line_to(28, 22), c.move_to(56, 22), c.line_to(64, 22)), RED, 2.6)
    stroke(ctx, lambda c: (c.move_to(8, 58), c.curve_to(6, 40, 22, 44, 24, 36)), INK, 2.0, 0.5)
    ctx.set_dash([4, 4])
    stroke(ctx, lambda c: (c.move_to(8, 58), c.curve_to(6, 40, 22, 44, 24, 36)), WHITE, 1.6)
    ctx.set_dash([])
    rocket(ctx, 31, 31, 28, 6.2, -0.75, "#efe4ff", PURPLE, GOLD)


@icon("grenade")
def _grenade(ctx):
    cx, cy = 30, 38
    body = lambda c: ellipse(c, cx, cy, 15, 18)
    I(ctx, body, "#6f9e52")
    ctx.save()
    clip_to(ctx, body)
    fill(ctx, lambda c: ellipse(c, cx + 5, cy + 6, 15, 17), darken("#6f9e52", 0.3), 0.7)
    for k in range(-2, 3):
        stroke(ctx, lambda c, k=k: (c.move_to(cx - 20, cy + k * 7), c.line_to(cx + 20, cy + k * 7)), INK, 1.5, 0.75)
    for k in (-1, 0, 1):
        stroke(ctx, lambda c, k=k: (c.move_to(cx + k * 8, cy - 20), c.curve_to(cx + k * 9.5, cy, cx + k * 9.5, cy,
                                                                               cx + k * 8, cy + 20)), INK, 1.5, 0.75)
    ctx.restore()
    stroke(ctx, body, INK, LW)
    shine(ctx, cx - 6, cy - 9, 9, 3.4, -0.9)
    # lever + head
    I(ctx, lambda c: (c.move_to(33, 20), c.curve_to(44, 17, 48, 24, 47, 36), c.line_to(44, 36),
                      c.curve_to(44, 27, 40, 24, 33, 25), c.close_path()), STEEL)
    I(ctx, lambda c: rrect(c, 22, 14, 16, 8, 2), STEEL_LIGHT)
    stroke(ctx, lambda c: circle(c, 18, 14, 6), INK, 4.4)
    stroke(ctx, lambda c: circle(c, 18, 14, 6), GOLD, 2.0)


@icon("cluster")
def _cluster(ctx):
    bomb(ctx, 26, 34, 15, "#d9573f", (0.55, -0.85), True, None)
    for (x, y, r, a) in ((50, 44, 6.0, 0.3), (46, 58, 4.8, 1.2), (12, 56, 4.8, 2.0)):
        I(ctx, lambda c, x=x, y=y, r=r: circle(c, x, y, r), "#f0a34b")
        shine(ctx, x - r * 0.35, y - r * 0.35, r * 0.6, r * 0.28, -0.7)
    motion(ctx, [(42, 38, 37, 35), (40, 53, 35, 49), (18, 51, 21, 47)], 0.6)


@icon("sticky")
def _sticky(ctx):
    cx, cy = 32, 30
    body = lambda c: smooth(c, [(cx - 16, cy - 2), (cx - 10, cy - 15), (cx + 4, cy - 17), (cx + 16, cy - 6),
                                (cx + 15, cy + 9), (cx + 11, cy + 22), (cx + 7, cy + 13), (cx + 1, cy + 25),
                                (cx - 4, cy + 14), (cx - 10, cy + 19), (cx - 12, cy + 10)], True, 0.9)
    I(ctx, body, GOO)
    ctx.save()
    clip_to(ctx, body)
    fill(ctx, lambda c: circle(c, cx + 6, cy + 10, 16), darken(GOO, 0.3), 0.6)
    fill(ctx, lambda c: circle(c, cx - 3, cy - 3, 9), BOMB)
    stroke(ctx, lambda c: circle(c, cx - 3, cy - 3, 9), INK, 1.6)
    fill(ctx, lambda c: circle(c, cx - 3, cy - 3, 3), RED)
    ctx.restore()
    stroke(ctx, body, INK, LW)
    shine(ctx, cx - 9, cy - 9, 7, 2.6, -0.8)
    fill(ctx, lambda c: circle(c, cx + 9, cy - 9, 1.6), WHITE)
    I(ctx, lambda c: circle(c, cx + 18, cy + 23, 3.0), GOO, LW * 0.8)
    I(ctx, lambda c: circle(c, cx - 19, cy + 18, 2.3), GOO, LW * 0.8)


@icon("dynamite")
def _dynamite(ctx):
    for k, (dx, dy, rot) in enumerate(((-11, 4, -0.18), (11, 4, 0.18), (0, 0, 0))):
        ctx.save()
        ctx.translate(32 + dx, 38 + dy)
        ctx.rotate(rot)
        st = lambda c: rrect(c, -6, -18, 12, 36, 3)
        I(ctx, st, RED)
        ctx.save()
        clip_to(ctx, st)
        fill(ctx, lambda c: c.rectangle(1.5, -20, 6, 40), RED_DARK, 0.7)
        fill(ctx, lambda c: c.rectangle(-4, -16, 2.4, 30), WHITE, 0.35)
        ctx.restore()
        ellipse(ctx, 0, -18, 6, 2)
        src(ctx, "#f2c9a0")
        ctx.fill()
        ctx.restore()
    I(ctx, lambda c: rrect(c, 14, 34, 36, 7, 2), "#e6d6b0")
    stroke(ctx, lambda c: (c.move_to(32, 18), c.curve_to(32, 10, 40, 12, 42, 6)), INK, 4.2)
    stroke(ctx, lambda c: (c.move_to(32, 18), c.curve_to(32, 10, 40, 12, 42, 6)), "#c9a77a", 1.8)
    spark(ctx, 44, 6, 6)


@icon("mega_bomb")
def _mega(ctx):
    for k in range(12):
        a = k * math.tau / 12
        stroke(ctx, lambda c, a=a: (c.move_to(30 + math.cos(a) * 26, 36 + math.sin(a) * 26),
                                    c.line_to(30 + math.cos(a) * 30, 36 + math.sin(a) * 30)), GOLD, 2.4, 0.9)
    bomb(ctx, 30, 37, 21, BOMB, (0.6, -0.8), True, GOLD)
    I(ctx, lambda c: poly(c, star_pts(30, 37, 7, 3)), FLAME_Y, 1.6)


@icon("banana")
def _banana(ctx):
    ban = lambda c: (c.move_to(10, 22), c.curve_to(12, 50, 40, 60, 58, 42), c.curve_to(56, 40, 54, 40, 52, 41),
                     c.curve_to(42, 44, 26, 40, 21, 20), c.close_path())
    I(ctx, ban, "#ffd84e")
    ctx.save()
    clip_to(ctx, ban)
    fill(ctx, lambda c: (c.move_to(10, 22), c.curve_to(12, 50, 40, 60, 58, 42), c.line_to(58, 60), c.line_to(5, 60),
                         c.close_path()), "#e9a92c", 0.85)
    stroke(ctx, lambda c: (c.move_to(15, 28), c.curve_to(20, 45, 36, 50, 50, 46)), "#fff1a8", 2.0)
    ctx.restore()
    stroke(ctx, ban, INK, LW)
    I(ctx, lambda c: rrect(c, 8, 16, 9, 7, 2), "#7a5a2e")
    fill(ctx, lambda c: circle(c, 57, 42, 2.0), "#6a4a22")
    stroke(ctx, lambda c: (c.move_to(12, 16), c.curve_to(10, 8, 16, 6, 18, 4)), INK, 4.2)
    stroke(ctx, lambda c: (c.move_to(12, 16), c.curve_to(10, 8, 16, 6, 18, 4)), "#c9a77a", 1.8)
    spark(ctx, 20, 6, 5.5)
    for (x, y) in ((40, 22), (52, 28)):
        I(ctx, lambda c, x=x, y=y: ellipse(c, x, y, 5.5, 2.6, -0.6), "#ffd84e", LW * 0.8)


@icon("holy_bomb")
def _holy(ctx):
    for k in range(16):
        a = k * math.tau / 16
        r0, r1 = 23, 29 if k % 2 == 0 else 26
        stroke(ctx, lambda c, a=a, r1=r1: (c.move_to(32 + math.cos(a) * r0, 37 + math.sin(a) * r0),
                                           c.line_to(32 + math.cos(a) * r1, 37 + math.sin(a) * r1)),
               "#ffe28a", 2.6, 0.95)
    orb = lambda c: circle(c, 32, 38, 17)
    I(ctx, orb, GOLD)
    ctx.save()
    clip_to(ctx, orb)
    fill(ctx, lambda c: circle(c, 37, 44, 17), "#c98f2e", 0.7)
    fill(ctx, lambda c: circle(c, 30, 35, 13), GOLD)
    fill(ctx, lambda c: c.rectangle(10, 33, 44, 6), "#fff0bf")
    ctx.restore()
    stroke(ctx, lambda c: (c.move_to(15, 33), c.line_to(49, 33), c.move_to(15, 39), c.line_to(49, 39)), INK, 1.3)
    stroke(ctx, orb, INK, LW)
    for x in (20, 27, 34, 41):
        fill(ctx, lambda c, x=x: circle(c, x + 2, 36, 1.4), "#5aa3d9")
    shine(ctx, 24, 28, 9, 3, -0.7)
    I(ctx, lambda c: rrect(c, 28, 16, 8, 6, 2), "#e9b24a")
    I(ctx, lambda c: poly(c, star_pts(32, 10, 7, 3, 4, -math.pi / 2)), "#fff6cf", 1.8)
    ellipse(ctx, 32, 6, 9, 2.6)
    src(ctx, INK, 1)
    ctx.set_line_width(4)
    ctx.stroke_preserve()
    src(ctx, "#ffe28a")
    ctx.set_line_width(1.8)
    ctx.stroke()


def gun_stock(ctx, pts, col=WOOD):
    I(ctx, lambda c: smooth(c, pts, True, 0.6), col)


@icon("shotgun")
def _shotgun(ctx):
    ctx.save()
    ctx.translate(32, 32)
    ctx.rotate(-0.42)
    for dy in (-3.4, 1.6):
        I(ctx, lambda c, dy=dy: rrect(c, -6, dy - 2.6, 36, 5.2, 2.2), STEEL)
    fill(ctx, lambda c: c.rectangle(-4, -2.2, 32, 1.2), STEEL_LIGHT)
    for dy in (-3.4, 1.6):
        fill(ctx, lambda c, dy=dy: circle(c, 29.5, dy, 1.4), INK)
    I(ctx, lambda c: rrect(c, 4, 4, 18, 5, 2.5), WOOD)
    I(ctx, lambda c: smooth(c, [(-6, -6.5), (-12, -5), (-28, 4), (-29, 13), (-20, 11), (-8, 6), (-2, 5),
                                (-2, -5)], True, 0.5), WOOD)
    fill(ctx, lambda c: smooth(c, [(-13, 0), (-24, 6), (-25, 9), (-20, 8), (-10, 3)], True, 0.5), WOOD_DARK, 0.6)
    I(ctx, lambda c: rrect(c, -9, -7.5, 9, 12, 2), STEEL_DARK)
    stroke(ctx, lambda c: (c.move_to(-6, 4), c.curve_to(-6, 10, -2, 10, -1, 6)), INK, 1.8)
    ctx.restore()
    for (x, y, r) in ((14, 50, -0.3), (24, 54, 0.4)):
        ctx.save()
        ctx.translate(x, y)
        ctx.rotate(r)
        I(ctx, lambda c: rrect(c, -3.2, -6, 6.4, 12, 1.5), RED, LW * 0.8)
        I(ctx, lambda c: rrect(c, -3.4, 2.5, 6.8, 4, 1), GOLD, LW * 0.8)
        ctx.restore()


@icon("rifle")
def _rifle(ctx):
    ctx.save()
    ctx.translate(32, 33)
    ctx.rotate(-0.38)
    I(ctx, lambda c: rrect(c, 0, -2.2, 31, 4.4, 2), STEEL_DARK)
    I(ctx, lambda c: rrect(c, 28, -3, 4, 6, 1.2), INK)
    I(ctx, lambda c: smooth(c, [(-6, -4.5), (-14, -4), (-29, 2), (-30, 10), (-22, 9), (-10, 5), (8, 5),
                                (12, 1), (8, -4.5)], True, 0.5), "#b97a45")
    fill(ctx, lambda c: smooth(c, [(-14, 1), (-26, 5), (-26, 7), (-12, 4)], True, 0.5), WOOD_DARK, 0.6)
    I(ctx, lambda c: rrect(c, -12, -12.5, 22, 7, 3.5), INK, LW * 0.6)
    fill(ctx, lambda c: rrect(c, -11, -11.6, 20, 5.2, 2.6), STEEL)
    I(ctx, lambda c: ellipse(c, 10.5, -9, 2.4, 3.6), "#86d6d3", LW * 0.6)
    fill(ctx, lambda c: ellipse(c, 10, -10, 0.8, 1.2), WHITE)
    I(ctx, lambda c: poly(c, [(-4, -7), (-1, -7), (-1, -4), (-4, -4)]), INK, 1)
    stroke(ctx, lambda c: (c.move_to(-4, 5), c.curve_to(-4, 11, 0, 11, 1, 7)), INK, 1.8)
    shine(ctx, -2, -10.5, 12, 1.6, 0)
    ctx.restore()
    # crosshair glint
    stroke(ctx, lambda c: circle(c, 54, 12, 6), RED, 2.0)
    stroke(ctx, lambda c: (c.move_to(54, 3), c.line_to(54, 21), c.move_to(45, 12), c.line_to(63, 12)), RED, 1.6)


@icon("minigun")
def _minigun(ctx):
    ctx.save()
    ctx.translate(30, 34)
    ctx.rotate(-0.25)
    for dy in (-5.5, 0, 5.5):
        I(ctx, lambda c, dy=dy: rrect(c, 0, dy - 2.4, 30, 4.8, 2.2), STEEL if dy else STEEL_LIGHT)
        fill(ctx, lambda c, dy=dy: circle(c, 28.5, dy, 1.3), INK)
    for x in (6, 20):
        I(ctx, lambda c, x=x: rrect(c, x, -9.5, 4, 19, 1.5), STEEL_DARK)
    body = lambda c: rrect(c, -22, -11, 24, 22, 6)
    I(ctx, body, "#d26a3c")
    ctx.save()
    clip_to(ctx, body)
    fill(ctx, lambda c: c.rectangle(-24, 3, 30, 10), darken("#d26a3c", 0.25), 0.8)
    ctx.restore()
    I(ctx, lambda c: rrect(c, -16, 9, 7, 10, 2.5), STEEL_DARK)
    I(ctx, lambda c: rrect(c, -18, -15, 14, 6, 3), STEEL)
    shine(ctx, -12, -6, 12, 2.6, 0)
    ctx.restore()
    # ammo belt
    for k in range(5):
        x, y = 12 - k * 3.6, 47 + k * 2.4
        I(ctx, lambda c, x=x, y=y: rrect(c, x - 2, y - 4.5, 4, 9, 1.4), GOLD, LW * 0.6)
    flame(ctx, 61, 27, 6, 1.32, (FLAME_O, FLAME_Y, WHITE), LW * 0.8)


@icon("laser")
def _laser(ctx):
    beam = lambda c: (c.move_to(34, 20), c.line_to(64, 6), c.line_to(64, 14), c.line_to(36, 26), c.close_path())
    fill(ctx, beam, "#ff6fb5", 0.5)
    stroke(ctx, lambda c: (c.move_to(35, 23), c.line_to(64, 10)), WHITE, 2.4)
    ctx.save()
    ctx.translate(28, 34)
    ctx.rotate(-0.42)
    I(ctx, lambda c: smooth(c, [(-12, -7), (8, -9), (14, -5), (14, 3), (-2, 5), (-6, 18), (-14, 18), (-13, 4)],
                            True, 0.45), "#7fc8f8")
    for x in (0, 5, 10):
        I(ctx, lambda c, x=x: rrect(c, x, -10.5, 3, 15, 1.4), "#ff6fb5", LW * 0.7)
    I(ctx, lambda c: rrect(c, 13, -5, 6, 7, 2), STEEL_LIGHT)
    fill(ctx, lambda c: circle(c, -5, -1.5, 3.4), "#ffe17a")
    stroke(ctx, lambda c: circle(c, -5, -1.5, 3.4), INK, 1.4)
    shine(ctx, -4, -5.5, 12, 2, 0)
    ctx.restore()
    for (x, y, r) in ((52, 26, 4), (58, 22, 2.6), (46, 6, 3)):
        I(ctx, lambda c, x=x, y=y, r=r: poly(c, star_pts(x, y, r, r * 0.35, 4)), WHITE, 1.2)


@icon("flamethrower")
def _flamer(ctx):
    for k, (x, y, s, r) in enumerate(((54, 22, 11, 1.2), (44, 26, 8, 1.25))):
        flame(ctx, x, y, s, r)
    tank = lambda c: rrect(c, 6, 26, 15, 30, 7)
    I(ctx, tank, RED)
    ctx.save()
    clip_to(ctx, tank)
    fill(ctx, lambda c: c.rectangle(15, 20, 10, 40), RED_DARK, 0.6)
    ctx.restore()
    shine(ctx, 10, 34, 2.4, 12, 0)
    I(ctx, lambda c: rrect(c, 9, 22, 9, 5, 2), STEEL)
    stroke(ctx, lambda c: (c.move_to(19, 50), c.curve_to(30, 54, 30, 44, 26, 40)), INK, 5)
    stroke(ctx, lambda c: (c.move_to(19, 50), c.curve_to(30, 54, 30, 44, 26, 40)), STEEL_DARK, 2.6)
    ctx.save()
    ctx.translate(30, 34)
    ctx.rotate(-0.38)
    I(ctx, lambda c: rrect(c, -6, -4, 22, 8, 3), STEEL)
    I(ctx, lambda c: rrect(c, 14, -5.5, 6, 11, 2), STEEL_DARK)
    I(ctx, lambda c: rrect(c, -3, 3, 6, 9, 2), WOOD)
    shine(ctx, 4, -2, 14, 1.8, 0)
    ctx.restore()


@icon("fire_punch")
def _firepunch(ctx):
    flame(ctx, 21, 44, 13, -0.55)
    flame(ctx, 45, 42, 13, 0.55)
    flame(ctx, 33, 30, 22, 0.0)
    glove(ctx, 32, 34, 1.3, -1.35, RED)
    motion(ctx, [(16, 58, 20, 50), (26, 62, 28, 54), (40, 60, 39, 53)], 0.7)


@icon("dragon_punch")
def _dragonpunch(ctx):
    # swirling energy spiral
    for k, (col, w) in enumerate(((INK, 9), (TEAL, 6.5), ("#9fe8e2", 2.6))):
        stroke(ctx, lambda c: (c.move_to(10, 58), c.curve_to(2, 36, 34, 40, 26, 26),
                               c.curve_to(20, 14, 40, 6, 52, 14)), col, w)
    for (x, y) in ((12, 44), (48, 26), (8, 30)):
        I(ctx, lambda c, x=x, y=y: poly(c, star_pts(x, y, 4, 1.4, 4)), GOLD, 1.3)
    glove(ctx, 40, 24, 1.25, -1.55, GOLD)
    I(ctx, lambda c: poly(c, star_pts(42, 6, 5, 2.2)), "#fff1b8", 1.4)


@icon("prod")
def _prod(ctx):
    motion(ctx, [(6, 22, 16, 24), (4, 32, 15, 32), (6, 42, 16, 40)], 0.7)
    glove(ctx, 30, 33, 1.3, 0.0, "#f6d6b8", point=True)
    for k in range(3):
        a = -0.8 + k * 0.8
        stroke(ctx, lambda c, a=a: (c.move_to(56 + math.cos(a) * 4, 26 + math.sin(a) * 6),
                                    c.line_to(56 + math.cos(a) * 9, 26 + math.sin(a) * 11)), INK, 2.2)


@icon("bat")
def _bat(ctx):
    stroke(ctx, lambda c: (c.move_to(12, 18), c.curve_to(26, 6, 46, 8, 56, 20)), INK, 7, 0.15)
    stroke(ctx, lambda c: (c.move_to(16, 13), c.curve_to(30, 4, 46, 6, 54, 14)), INK, 2, 0.5)
    ctx.save()
    ctx.translate(30, 36)
    ctx.rotate(-0.78)
    bat = lambda c: (c.move_to(-24, -2), c.line_to(-6, -2.6), c.curve_to(4, -6.5, 20, -7.5, 25, -5),
                     c.curve_to(27.5, -2, 27.5, 2, 25, 5), c.curve_to(20, 7.5, 4, 6.5, -6, 2.6),
                     c.line_to(-24, 2), c.close_path())
    I(ctx, bat, "#d9a066")
    ctx.save()
    clip_to(ctx, bat)
    fill(ctx, lambda c: c.rectangle(-30, 1, 60, 10), WOOD, 0.8)
    for x in (2, 10, 18):
        stroke(ctx, lambda c, x=x: (c.move_to(x, -5), c.curve_to(x + 3, -1, x + 1, 2, x + 4, 5)), WOOD_DARK, 0.9, 0.5)
    ctx.restore()
    stroke(ctx, bat, INK, LW)
    I(ctx, lambda c: rrect(c, -27, -3.6, 5, 7.2, 2), WOOD_DARK)
    for x in (-20, -16, -12):
        stroke(ctx, lambda c, x=x: (c.move_to(x, -2.5), c.line_to(x + 2, 2.5)), INK, 1.2, 0.8)
    shine(ctx, 12, -3.5, 14, 1.8, -0.05)
    ctx.restore()
    I(ctx, lambda c: circle(c, 52, 50, 7), WHITE)
    stroke(ctx, lambda c: (c.move_to(47, 46), c.curve_to(50, 49, 50, 52, 47, 55)), RED, 1.4)
    stroke(ctx, lambda c: (c.move_to(57, 45), c.curve_to(54, 49, 54, 52, 57, 55)), RED, 1.4)


@icon("axe")
def _axe(ctx):
    ctx.save()
    ctx.translate(32, 32)
    ctx.rotate(0.6)
    I(ctx, lambda c: rrect(c, -3.2, -16, 6.4, 44, 3), WOOD)
    fill(ctx, lambda c: c.rectangle(0.6, -14, 1.6, 40), WOOD_DARK, 0.6)
    head = lambda c: (c.move_to(-2, -24), c.line_to(6, -24), c.curve_to(14, -30, 22, -26, 24, -20),
                      c.curve_to(26, -12, 24, -4, 22, 2), c.curve_to(18, -2, 12, -6, 6, -8), c.line_to(-2, -8),
                      c.close_path())
    I(ctx, head, STEEL)
    ctx.save()
    clip_to(ctx, head)
    fill(ctx, lambda c: smooth(c, [(18, -28), (26, -18), (24, 4), (19, -6)], True), STEEL_LIGHT)
    fill(ctx, lambda c: c.rectangle(-4, -26, 9, 20), RED)
    ctx.restore()
    stroke(ctx, head, INK, LW)
    shine(ctx, 21, -15, 1.8, 10, 0.1)
    ctx.restore()
    for k in range(3):
        stroke(ctx, lambda c, k=k: (c.move_to(54 + k * 1.5, 30 + k * 6), c.line_to(60 + k, 28 + k * 7)), INK, 2, 0.6)


def plane(ctx, cx, cy, s, col=TEAL):
    ctx.save()
    ctx.translate(cx, cy)
    ctx.scale(s, s)
    I(ctx, lambda c: poly(c, [(-14, -3), (-20, -12), (-15, -12), (-6, -3)]), darken(col, 0.2), LW / s)
    body = lambda c: (c.move_to(-18, -2), c.curve_to(-12, -7, 8, -8, 16, -4), c.curve_to(20, -2, 20, 3, 16, 5),
                      c.curve_to(6, 7, -10, 6, -18, 2), c.close_path())
    I(ctx, body, col, LW / s)
    ctx.save()
    clip_to(ctx, body)
    fill(ctx, lambda c: c.rectangle(-20, 1.5, 40, 8), darken(col, 0.25), 0.7)
    ctx.restore()
    I(ctx, lambda c: ellipse(c, 6, -5.5, 5, 3.4), "#bfeef0", LW * 0.8 / s)
    I(ctx, lambda c: poly(c, [(-6, 0), (8, 0), (3, 9), (-4, 9)]), lighten(col, 0.2), LW / s)
    I(ctx, lambda c: rrect(c, 17, -6, 3, 12, 1.5), INK, 0)
    fill(ctx, lambda c: ellipse(c, 21, 0, 1.6, 8), STEEL_LIGHT, 0.85)
    shine(ctx, -2, -4.5, 12, 1.8, -0.05)
    ctx.restore()


@icon("airstrike")
def _airstrike(ctx):
    plane(ctx, 33, 19, 1.12)
    for k, (x, y) in enumerate(((16, 34), (28, 42), (40, 52))):
        ctx.save()
        ctx.translate(x, y)
        ctx.rotate(0.35)
        I(ctx, lambda c: ellipse(c, 0, 0, 4.2, 6.5), BOMB)
        I(ctx, lambda c: poly(c, [(-3.5, -6), (3.5, -6), (4.5, -10), (-4.5, -10)]), RED, LW * 0.7)
        shine(ctx, -1.5, -2, 1.6, 4, 0)
        ctx.restore()
        motion(ctx, [(x - 6, y - 12, x - 4, y - 8)], 0.5)


def mine_shape(ctx, cx, cy, r, blink=True):
    for k in range(5):
        a = math.pi + k * math.pi / 4
        x, y = cx + math.cos(a) * r * 1.2, cy + math.sin(a) * r * 1.2
        I(ctx, lambda c, x=x, y=y: circle(c, x, y, r * 0.22), STEEL_DARK, LW * 0.7)
    dome = lambda c: (c.move_to(cx - r, cy), c.curve_to(cx - r, cy - r * 1.3, cx + r, cy - r * 1.3, cx + r, cy),
                      c.close_path())
    I(ctx, dome, "#56707a")
    I(ctx, lambda c: rrect(c, cx - r * 1.25, cy - r * 0.1, r * 2.5, r * 0.5, r * 0.2), "#3b525c")
    shine(ctx, cx - r * 0.35, cy - r * 0.6, r * 0.6, r * 0.2, -0.4)
    if blink:
        I(ctx, lambda c: circle(c, cx, cy - r * 0.95, r * 0.24), RED, LW * 0.7)
        fill(ctx, lambda c: circle(c, cx, cy - r * 0.95, r * 0.5), RED, 0.25)


@icon("mine_strike")
def _minestrike(ctx):
    for (x, y, s) in ((20, 22, 1.0), (45, 34, 0.85)):
        stroke(ctx, lambda c, x=x, y=y, s=s: (c.move_to(x - 10 * s, y - 6 * s), c.line_to(x, y + 6 * s),
                                              c.move_to(x + 10 * s, y - 6 * s), c.line_to(x, y + 6 * s)), INK, 1.2)
        chute = lambda c, x=x, y=y, s=s: (c.move_to(x - 12 * s, y - 6 * s),
                                          c.curve_to(x - 12 * s, y - 20 * s, x + 12 * s, y - 20 * s, x + 12 * s,
                                                     y - 6 * s), c.close_path())
        I(ctx, chute, PAPER)
        ctx.save()
        clip_to(ctx, chute)
        fill(ctx, lambda c, x=x, y=y, s=s: c.rectangle(x - 4 * s, y - 22 * s, 8 * s, 20 * s), RED)
        ctx.restore()
        stroke(ctx, chute, INK, LW)
        mine_shape(ctx, x, y + 12 * s, 7 * s)
    for x in (10, 34, 56):
        stroke(ctx, lambda c, x=x: (c.move_to(x, 52), c.line_to(x, 60), c.move_to(x - 3, 57), c.line_to(x, 60),
                                    c.line_to(x + 3, 57)), INK, 1.8, 0.6)


@icon("napalm")
def _napalm(ctx):
    plane(ctx, 30, 13, 1.1, "#c25b4f")
    for (x, y, s, r) in ((14, 40, 7, 0.0), (28, 48, 9, 0.1), (44, 42, 7.5, -0.1), (54, 56, 6, 0.2),
                         (20, 58, 5.5, 0)):
        flame(ctx, x, y, s, math.pi + r)
    I(ctx, lambda c: rrect(c, 4, 58, 56, 5, 2.5), "#7a4a35", LW * 0.8)


@icon("meteor")
def _meteor(ctx):
    trail = lambda c: (c.move_to(4, 6), c.line_to(36, 26), c.line_to(26, 40), c.close_path())
    fill(ctx, trail, FLAME_O, 0.5)
    fill(ctx, lambda c: (c.move_to(10, 12), c.line_to(36, 28), c.line_to(30, 36), c.close_path()), FLAME_Y, 0.7)
    flame(ctx, 36, 34, 16, -2.35)
    rock = lambda c: smooth(c, [(30, 38), (34, 28), (46, 26), (54, 34), (52, 48), (42, 54), (32, 50)], True, 0.7)
    I(ctx, rock, "#7b5b52")
    ctx.save()
    clip_to(ctx, rock)
    fill(ctx, lambda c: circle(c, 48, 48, 12), "#53403c", 0.8)
    for (x, y, r) in ((40, 34, 3), (47, 42, 2.4), (37, 46, 2)):
        I(ctx, lambda c, x=x, y=y, r=r: circle(c, x, y, r), "#5e4741", 1.2)
    ctx.restore()
    stroke(ctx, rock, INK, LW)
    shine(ctx, 38, 31, 6, 2, -0.6)


@icon("earthquake")
def _quake(ctx):
    ground = lambda c: (c.move_to(4, 36), c.line_to(22, 34), c.line_to(28, 40), c.line_to(36, 33), c.line_to(60, 36),
                        c.line_to(60, 60), c.line_to(4, 60), c.close_path())
    I(ctx, ground, "#a7764d")
    ctx.save()
    clip_to(ctx, ground)
    fill(ctx, lambda c: c.rectangle(0, 30, 64, 9), "#7fb069")
    fill(ctx, lambda c: c.rectangle(0, 48, 64, 14), "#8a5f3e")
    ctx.restore()
    stroke(ctx, ground, INK, LW)
    I(ctx, lambda c: poly(c, [(29, 38), (34, 44), (30, 48), (36, 54), (33, 60), (28, 60), (31, 54), (25, 48),
                              (28, 44), (25, 39)]), INK, 1.0)
    for k, (x, y) in enumerate(((10, 24), (22, 18), (42, 18), (54, 24))):
        stroke(ctx, lambda c, x=x, y=y: (c.move_to(x - 4, y), c.line_to(x - 2, y - 3), c.line_to(x, y),
                                         c.line_to(x + 2, y - 3), c.line_to(x + 4, y)), INK, 2.0, 0.75)
    for (x, y, r) in ((14, 30, 3), (50, 28, 2.4)):
        I(ctx, lambda c, x=x, y=y, r=r: ellipse(c, x, y, r * 1.3, r), "#9b8a7a", 1.6)


def sheep(ctx, cx, cy, s=1.0, cape=False):
    ctx.save()
    ctx.translate(cx, cy)
    ctx.scale(s, s)
    lw = LW / s
    if cape:
        cp = lambda c: (c.move_to(-4, -8), c.curve_to(-14, -14, -24, -10, -30, -16), c.curve_to(-28, -6, -26, 4, -18, 6),
                        c.curve_to(-12, 2, -6, 0, -2, -2), c.close_path())
        inked(ctx, cp, RED, lw)
        fill(ctx, lambda c: (c.move_to(-22, -10), c.curve_to(-20, -4, -18, 0, -16, 3), c.line_to(-14, 1),
                             c.curve_to(-16, -3, -18, -7, -19, -11), c.close_path()), RED_DARK, 0.6)
    for x in (-8, -2, 5, 10):
        inked(ctx, lambda c, x=x: rrect(c, x - 1.8, 4, 3.6, 10, 1.6), INK, 0)
    puffs = [(-10, -2, 7), (-3, -7, 7.5), (5, -6, 7), (10, 0, 6.5), (2, 3, 8), (-8, 4, 6)]
    from build_art_core import outline_pass
    outline_pass(ctx, [lambda c, p=p: circle(c, *p) for p in puffs], lw / 2)
    for p in puffs:
        fill(ctx, lambda c, p=p: circle(c, *p), WOOL)
    for p in puffs[:3]:
        fill(ctx, lambda c, p=p: circle(c, p[0] - 1.5, p[1] - 2, p[2] * 0.45), WHITE)
    fill(ctx, lambda c: circle(c, 2, 4, 6), "#e8dfcc", 0.6)
    head = lambda c: ellipse(c, 15, -4, 6.5, 7.5, 0.3)
    inked(ctx, head, "#3a3436", lw)
    inked(ctx, lambda c: ellipse(c, 10.5, -9, 3.6, 2, -0.6), "#3a3436", lw * 0.8)
    inked(ctx, lambda c: circle(c, 15, -10, 4), WOOL, lw * 0.8)
    inked(ctx, lambda c: circle(c, 17.5, -5.5, 2.8), WHITE, lw * 0.6)
    fill(ctx, lambda c: circle(c, 18.3, -5.3, 1.4), INK)
    fill(ctx, lambda c: circle(c, 17.8, -6, 0.5), WHITE)
    fill(ctx, lambda c: ellipse(c, 19, 0.5, 1.6, 1), "#f39aa8")
    if cape:
        stroke(ctx, lambda c: (c.move_to(13.5, -8.5), c.line_to(19, -8)), INK, 1.4 / s)
        inked(ctx, lambda c: rrect(c, 12, -12.5, 9, 3, 1.4), GOLD, lw * 0.5)
    ctx.restore()


@icon("sheep")
def _sheep(ctx):
    sheep(ctx, 29, 36, 1.45)
    motion(ctx, [(3, 30, 8, 30), (2, 40, 7, 40)], 0.6)


@icon("super_sheep")
def _supersheep(ctx):
    for (x0, y0, x1, y1) in ((2, 50, 14, 44), (2, 58, 16, 52), (8, 62, 20, 58)):
        stroke(ctx, lambda c, a=(x0, y0, x1, y1): (c.move_to(a[0], a[1]), c.line_to(a[2], a[3])), INK, 2, 0.6)
    ctx.save()
    ctx.translate(34, 34)
    ctx.rotate(-0.45)
    sheep(ctx, 0, 0, 1.3, cape=True)
    ctx.restore()
    I(ctx, lambda c: poly(c, star_pts(56, 8, 5, 2)), GOLD, 1.4)


@icon("mole")
def _mole(ctx):
    I(ctx, lambda c: (c.move_to(2, 48), c.curve_to(10, 40, 54, 40, 62, 48), c.line_to(62, 62), c.line_to(2, 62),
                      c.close_path()), "#8a5f3e")
    for (x, y, r) in ((10, 44, 3.5), (54, 43, 4), (46, 39, 2.5)):
        I(ctx, lambda c, x=x, y=y, r=r: circle(c, x, y, r), "#a7764d", 1.6)
    body = lambda c: (c.move_to(14, 50), c.curve_to(12, 22, 22, 10, 32, 10), c.curve_to(42, 10, 52, 22, 50, 50),
                      c.close_path())
    I(ctx, body, "#6b5560")
    ctx.save()
    clip_to(ctx, body)
    fill(ctx, lambda c: ellipse(c, 36, 40, 14, 18), "#54424c", 0.8)
    fill(ctx, lambda c: ellipse(c, 32, 40, 9, 12), "#9c8590")
    ctx.restore()
    I(ctx, lambda c: rrect(c, 17, 18, 30, 6, 3), "#7a5a2e", LW * 0.8)
    for x in (24, 40):
        I(ctx, lambda c, x=x: circle(c, x, 21, 5.4), GOLD, LW * 0.8)
        I(ctx, lambda c, x=x: circle(c, x, 21, 3.6), "#86d6d3", LW * 0.5)
        fill(ctx, lambda c, x=x: circle(c, x - 1.2, 19.8, 1.1), WHITE)
    I(ctx, lambda c: ellipse(c, 32, 30, 5, 3.6), "#ff8fa3")
    fill(ctx, lambda c: ellipse(c, 31, 29, 1.6, 0.9), WHITE, 0.8)
    stroke(ctx, lambda c: (c.move_to(28, 35), c.curve_to(30, 38, 34, 38, 36, 35)), INK, 1.6)
    I(ctx, lambda c: rrect(c, 30, 35.5, 4, 3.5, 0.8), WHITE, 1.0)
    for sx in (-1, 1):
        cx = 32 + sx * 15
        I(ctx, lambda c, cx=cx: ellipse(c, cx, 44, 6, 4.5), "#f6b9a8")
        for k in (-1, 0, 1):
            stroke(ctx, lambda c, cx=cx, k=k: (c.move_to(cx + k * 3, 47), c.line_to(cx + k * 3.6, 52)), INK, 2.4)
            stroke(ctx, lambda c, cx=cx, k=k: (c.move_to(cx + k * 3, 47), c.line_to(cx + k * 3.6, 51)), WHITE, 1.0)


@icon("skunk")
def _skunk(ctx):
    for (x, y, r) in ((50, 12, 7), (58, 22, 5), (42, 6, 5)):
        I(ctx, lambda c, x=x, y=y, r=r: (circle(c, x, y, r), circle(c, x + r * 0.7, y + 2, r * 0.7)),
          "#b6dc6a", LW * 0.8)
    tail = lambda c: (c.move_to(34, 44), c.curve_to(56, 46, 60, 24, 46, 18), c.curve_to(34, 14, 30, 30, 40, 32),
                      c.curve_to(46, 34, 48, 26, 44, 24), c.curve_to(52, 28, 48, 42, 34, 40), c.close_path())
    I(ctx, tail, "#2c3438")
    stroke(ctx, lambda c: (c.move_to(38, 41), c.curve_to(54, 40, 54, 22, 44, 21)), WHITE, 3.4)
    body = lambda c: ellipse(c, 28, 46, 15, 11)
    I(ctx, body, "#2c3438")
    stroke(ctx, lambda c: (c.move_to(14, 42), c.curve_to(22, 36, 32, 36, 40, 42)), WHITE, 3)
    head = lambda c: circle(c, 16, 40, 10)
    I(ctx, head, "#2c3438")
    I(ctx, lambda c: (c.move_to(16, 31), c.curve_to(18, 36, 14, 42, 8, 44), c.line_to(12, 38), c.close_path()), WHITE,
      0)
    I(ctx, lambda c: poly(c, [(18, 32), (22, 25), (24, 34)]), "#2c3438")
    I(ctx, lambda c: circle(c, 13, 39, 3.6), WHITE, 1.4)
    fill(ctx, lambda c: circle(c, 12.4, 39.5, 1.8), INK)
    fill(ctx, lambda c: circle(c, 12, 38.6, 0.6), WHITE)
    fill(ctx, lambda c: circle(c, 6.5, 44, 1.8), "#ff8fa3")
    stroke(ctx, lambda c: (c.move_to(9, 46), c.curve_to(11, 48, 14, 48, 15, 46)), WHITE, 1.2)
    for x in (20, 34):
        I(ctx, lambda c, x=x: rrect(c, x - 2.5, 52, 5, 7, 2), "#2c3438", LW * 0.8)


@icon("cow")
def _cow(ctx):
    for x in (10, 20, 44, 54):
        stroke(ctx, lambda c, x=x: (c.move_to(x, 2), c.line_to(x, 10)), INK, 2, 0.5)
    ctx.save()
    ctx.translate(32, 34)
    ctx.rotate(0.15)
    for sx in (-1, 1):
        I(ctx, lambda c, s=sx: poly(c, [(s * 10, -14), (s * 17, -24), (s * 15, -12)]), "#f3e6c8")
        I(ctx, lambda c, s=sx: ellipse(c, s * 19, -10, 6, 3, s * 0.35), "#f2b8a0")
    head = lambda c: (c.move_to(-14, -10), c.curve_to(-14, -20, 14, -20, 14, -10), c.curve_to(16, 4, 14, 14, 0, 14),
                      c.curve_to(-14, 14, -16, 4, -14, -10), c.close_path())
    I(ctx, head, WHITE)
    ctx.save()
    clip_to(ctx, head)
    fill(ctx, lambda c: smooth(c, [(-16, -18), (-4, -16), (-6, -6), (-14, -2)], True), INK)
    fill(ctx, lambda c: smooth(c, [(8, -6), (16, -8), (16, 4), (10, 2)], True), INK)
    ctx.restore()
    stroke(ctx, head, INK, LW)
    snout = lambda c: ellipse(c, 0, 9, 13, 8)
    I(ctx, snout, "#f6a9b4")
    for sx in (-1, 1):
        fill(ctx, lambda c, s=sx: ellipse(c, s * 5, 9, 2, 3), "#b85f75")
    for sx in (-1, 1):
        I(ctx, lambda c, s=sx: circle(c, s * 6.5, -6, 4.2), WHITE, 1.6)
        fill(ctx, lambda c, s=sx: circle(c, s * 6.5 + 1, -5, 2.2), INK)
        fill(ctx, lambda c, s=sx: circle(c, s * 6.5 + 0.2, -6, 0.8), WHITE)
    shine(ctx, -6, 6, 4, 1.6, -0.3)
    ctx.restore()
    I(ctx, lambda c: (c.move_to(26, 51), c.curve_to(26, 58, 38, 58, 38, 51), c.close_path()), GOLD, LW * 0.8)
    fill(ctx, lambda c: circle(c, 32, 55.5, 1.4), INK)


@icon("mine")
def _mine(ctx):
    mine_shape(ctx, 32, 44, 18)
    for k in range(3):
        a = -math.pi / 2 + (k - 1) * 0.6
        stroke(ctx, lambda c, a=a: (c.move_to(32 + math.cos(a) * 26, 22 + math.sin(a) * 10),
                                    c.line_to(32 + math.cos(a) * 32, 22 + math.sin(a) * 14)), RED, 2.4)


@icon("turret")
def _turret(ctx):
    for (x0, x1) in ((32, 12), (32, 52), (32, 32)):
        I(ctx, lambda c, a=x0, b=x1: poly(c, [(a - 2, 40), (a + 2, 40), (b + 2, 60), (b - 2, 60)]), STEEL_DARK, 1.8)
    ctx.save()
    ctx.translate(30, 30)
    ctx.rotate(-0.25)
    I(ctx, lambda c: rrect(c, 6, -4, 26, 8, 3), STEEL)
    I(ctx, lambda c: rrect(c, 28, -5.5, 5, 11, 2), STEEL_DARK)
    shine(ctx, 18, -2, 12, 1.6, 0)
    ctx.restore()
    dome = lambda c: (c.move_to(14, 40), c.curve_to(14, 18, 44, 18, 44, 40), c.close_path())
    I(ctx, dome, TEAL)
    ctx.save()
    clip_to(ctx, dome)
    fill(ctx, lambda c: c.rectangle(10, 34, 40, 8), darken(TEAL, 0.3))
    ctx.restore()
    stroke(ctx, dome, INK, LW)
    I(ctx, lambda c: circle(c, 29, 30, 5.5), "#1f3a40", LW * 0.8)
    fill(ctx, lambda c: circle(c, 29, 30, 2.8), "#ff6f6f")
    fill(ctx, lambda c: circle(c, 28, 29, 1.0), WHITE)
    shine(ctx, 20, 25, 7, 2.4, -0.8)
    I(ctx, lambda c: rrect(c, 10, 38, 38, 6, 2.5), STEEL_DARK)


@icon("barrel")
def _barrel(ctx):
    body = lambda c: (c.move_to(16, 10), c.curve_to(13, 24, 13, 42, 16, 56), c.line_to(48, 56),
                      c.curve_to(51, 42, 51, 24, 48, 10), c.close_path())
    I(ctx, body, RED)
    ctx.save()
    clip_to(ctx, body)
    fill(ctx, lambda c: c.rectangle(38, 0, 20, 64), RED_DARK, 0.65)
    fill(ctx, lambda c: c.rectangle(19, 0, 4, 64), WHITE, 0.3)
    for y in (20, 46):
        fill(ctx, lambda c, y=y: c.rectangle(0, y - 2.4, 64, 4.8), darken(RED, 0.4))
    ctx.restore()
    stroke(ctx, body, INK, LW)
    I(ctx, lambda c: ellipse(c, 32, 10, 16, 4), "#c94a42")
    fill(ctx, lambda c: ellipse(c, 38, 9.5, 3, 1.3), INK)
    tri = lambda c: poly(c, [(32, 24), (42, 41), (22, 41)])
    I(ctx, tri, GOLD, 1.8)
    flame(ctx, 32, 37.5, 5, 0, (INK,), 0)


@icon("rope")
def _rope(ctx):
    for k in range(4):
        r = 15 - k * 3.2
        stroke(ctx, lambda c, r=r: ellipse(c, 26, 42, r, r * 0.75), INK, 5.6)
        stroke(ctx, lambda c, r=r: ellipse(c, 26, 42, r, r * 0.75), "#d8b277", 3.0)
    stroke(ctx, lambda c: (c.move_to(40, 38), c.curve_to(52, 34, 44, 20, 50, 14)), INK, 5.6)
    stroke(ctx, lambda c: (c.move_to(40, 38), c.curve_to(52, 34, 44, 20, 50, 14)), "#d8b277", 3.0)
    ctx.set_dash([1.4, 2.6])
    stroke(ctx, lambda c: (c.move_to(40, 38), c.curve_to(52, 34, 44, 20, 50, 14)), WOOD_DARK, 1.4)
    ctx.set_dash([])
    ctx.save()
    ctx.translate(51, 12)
    ctx.rotate(0.3)
    I(ctx, lambda c: rrect(c, -2, -8, 4, 12, 1.5), STEEL)
    for sx in (-1, 1):
        I(ctx, lambda c, s=sx: (c.move_to(0, -6), c.curve_to(s * 10, -6, s * 10, 2, s * 6, 4), c.line_to(s * 5, 1),
                                c.curve_to(s * 7, -1, s * 6, -4, 0, -3), c.close_path()), STEEL_LIGHT, 1.8)
    ctx.restore()


@icon("jetpack")
def _jetpack(ctx):
    for x in (21, 41):
        flame(ctx, x, 52, 8, math.pi)
    for x in (21, 41):
        t = lambda c, x=x: rrect(c, x - 8, 12, 16, 38, 8)
        I(ctx, t, ORANGE)
        ctx.save()
        clip_to(ctx, t)
        fill(ctx, lambda c, x=x: c.rectangle(x + 2, 8, 8, 44), darken(ORANGE, 0.28), 0.7)
        fill(ctx, lambda c, x=x: c.rectangle(x - 9, 30, 18, 5), GOLD)
        ctx.restore()
        stroke(ctx, t, INK, LW)
        shine(ctx, x - 4, 22, 2.6, 10, 0)
        I(ctx, lambda c, x=x: rrect(c, x - 5, 47, 10, 6, 2), STEEL_DARK)
    I(ctx, lambda c: rrect(c, 27, 20, 8, 22, 3), STEEL)
    I(ctx, lambda c: circle(c, 31, 26, 2.6), RED, 1.2)


@icon("parachute")
def _parachute(ctx):
    canopy = lambda c: (c.move_to(4, 30), c.curve_to(4, 2, 60, 2, 60, 30), c.curve_to(55, 26, 50, 26, 46, 30),
                        c.curve_to(41, 26, 36, 26, 32, 30), c.curve_to(28, 26, 23, 26, 18, 30),
                        c.curve_to(14, 26, 9, 26, 4, 30), c.close_path())
    I(ctx, canopy, PAPER)
    ctx.save()
    clip_to(ctx, canopy)
    fill(ctx, lambda c: (c.move_to(18, 30), c.curve_to(18, 10, 24, 6, 32, 4), c.curve_to(26, 10, 24, 20, 25, 30),
                         c.close_path()), ORANGE)
    fill(ctx, lambda c: (c.move_to(46, 30), c.curve_to(46, 10, 40, 6, 32, 4), c.curve_to(39, 10, 40, 20, 39, 30),
                         c.close_path()), ORANGE)
    fill(ctx, lambda c: c.rectangle(0, 22, 64, 10), darken(PAPER, 0.15), 0.6)
    ctx.restore()
    stroke(ctx, canopy, INK, LW)
    for x in (5, 18, 32, 46, 59):
        stroke(ctx, lambda c, x=x: (c.move_to(x, 30), c.line_to(32, 50)), INK, 1.2)
    I(ctx, lambda c: rrect(c, 25, 48, 14, 11, 3), WOOD)
    stroke(ctx, lambda c: (c.move_to(25, 53), c.line_to(39, 53)), WOOD_DARK, 1.4)


@icon("teleport")
def _teleport(ctx):
    for k, (r, col) in enumerate(((24, "#6c4fb0"), (18, PURPLE), (12, "#b9a3f0"), (6, WHITE))):
        I(ctx, lambda c, r=r: ellipse(c, 32, 34, r, r * 0.95), col, LW if k == 0 else 0)
    for k in range(3):
        a0 = k * math.tau / 3
        stroke(ctx, lambda c, a0=a0: [c.move_to(32, 34)] + [c.line_to(32 + math.cos(a0 + u * 0.12) * u,
                                                                      34 + math.sin(a0 + u * 0.12) * u * 0.95)
                                                            for u in range(1, 23)], WHITE, 1.8, 0.7)
    for (x, y, r) in ((8, 10, 5), (56, 12, 4), (54, 56, 4.5), (10, 54, 3.5)):
        I(ctx, lambda c, x=x, y=y, r=r: poly(c, star_pts(x, y, r, r * 0.35, 4)), GOLD, 1.3)


@icon("girder")
def _girder(ctx):
    ctx.save()
    ctx.translate(32, 34)
    ctx.rotate(-0.38)
    beam = lambda c: rrect(c, -28, -9, 56, 18, 2)
    I(ctx, beam, ORANGE)
    ctx.save()
    clip_to(ctx, beam)
    fill(ctx, lambda c: c.rectangle(-30, -9, 60, 4), lighten(ORANGE, 0.25))
    fill(ctx, lambda c: c.rectangle(-30, 5, 60, 4), darken(ORANGE, 0.3))
    for x in range(-26, 28, 13):
        stroke(ctx, lambda c, x=x: (c.move_to(x, -5), c.line_to(x + 6.5, 5), c.line_to(x + 13, -5)),
               darken(ORANGE, 0.45), 2.0)
    ctx.restore()
    stroke(ctx, beam, INK, LW)
    for x in (-24, 24):
        for y in (-7, 7):
            fill(ctx, lambda c, x=x, y=y: circle(c, x, y, 1.2), INK)
    ctx.restore()


@icon("drill")
def _drill(ctx):
    bit = lambda c: poly(c, [(24, 40), (40, 40), (32, 62)])
    I(ctx, bit, STEEL_LIGHT)
    ctx.save()
    clip_to(ctx, bit)
    for k in range(5):
        stroke(ctx, lambda c, k=k: (c.move_to(22, 42 + k * 4.5), c.line_to(42, 38 + k * 4.5)), STEEL_DARK, 1.8)
    ctx.restore()
    stroke(ctx, bit, INK, LW)
    body = lambda c: rrect(c, 20, 12, 24, 30, 5)
    I(ctx, body, GOLD)
    ctx.save()
    clip_to(ctx, body)
    fill(ctx, lambda c: c.rectangle(34, 10, 12, 34), darken(GOLD, 0.25), 0.8)
    fill(ctx, lambda c: c.rectangle(18, 22, 30, 6), INK, 0.85)
    ctx.restore()
    stroke(ctx, body, INK, LW)
    I(ctx, lambda c: rrect(c, 6, 6, 52, 7, 3.5), STEEL)
    shine(ctx, 25, 17, 2.4, 8, 0)
    for (x, y, r) in ((12, 54, 4), (52, 52, 3.5), (18, 46, 2.6)):
        I(ctx, lambda c, x=x, y=y, r=r: circle(c, x, y, r), "#a7764d", 1.6)


@icon("blowtorch")
def _torch(ctx):
    flame(ctx, 50, 22, 10, 1.0, ("#3d8fd6", "#7fd0ff", WHITE))
    ctx.save()
    ctx.translate(26, 38)
    ctx.rotate(-0.55)
    tank = lambda c: rrect(c, -18, -9, 22, 18, 7)
    I(ctx, tank, "#4a9bd0")
    ctx.save()
    clip_to(ctx, tank)
    fill(ctx, lambda c: c.rectangle(-20, 2, 26, 10), darken("#4a9bd0", 0.3), 0.7)
    ctx.restore()
    stroke(ctx, tank, INK, LW)
    I(ctx, lambda c: rrect(c, 3, -4, 9, 8, 2), STEEL_DARK)
    I(ctx, lambda c: rrect(c, 11, -2.5, 18, 5, 2), GOLD)
    I(ctx, lambda c: rrect(c, 4, -9, 5, 6, 1.5), RED, 1.6)
    shine(ctx, -10, -5, 10, 2.2, 0)
    ctx.restore()


@icon("heal")
def _heal(ctx):
    heart = lambda c: (c.move_to(32, 56), c.curve_to(10, 42, 4, 30, 6, 21), c.curve_to(8, 10, 24, 6, 32, 18),
                       c.curve_to(40, 6, 56, 10, 58, 21), c.curve_to(60, 30, 54, 42, 32, 56), c.close_path())
    I(ctx, heart, "#ff6f86")
    ctx.save()
    clip_to(ctx, heart)
    fill(ctx, lambda c: circle(c, 44, 44, 22), "#d84462", 0.7)
    ctx.restore()
    stroke(ctx, heart, INK, LW)
    plus = lambda c: poly(c, [(28, 20), (36, 20), (36, 28), (44, 28), (44, 36), (36, 36), (36, 44), (28, 44),
                              (28, 36), (20, 36), (20, 28), (28, 28)])
    I(ctx, plus, WHITE, 2.0)
    shine(ctx, 15, 19, 8, 3, -0.8)
    for (x, y) in ((56, 50), (8, 48)):
        I(ctx, lambda c, x=x, y=y: poly(c, star_pts(x, y, 4.5, 1.6, 4)), GOLD, 1.3)


@icon("shield")
def _shield(ctx):
    sh = lambda c: (c.move_to(32, 4), c.curve_to(42, 9, 50, 10, 56, 10), c.curve_to(57, 34, 50, 50, 32, 60),
                    c.curve_to(14, 50, 7, 34, 8, 10), c.curve_to(14, 10, 22, 9, 32, 4), c.close_path())
    I(ctx, sh, GOLD)
    inner = lambda c: (c.move_to(32, 10), c.curve_to(40, 14, 46, 15, 50, 15), c.curve_to(50, 34, 45, 46, 32, 54),
                       c.curve_to(19, 46, 14, 34, 14, 15), c.curve_to(18, 15, 24, 14, 32, 10), c.close_path())
    I(ctx, inner, TEAL, 1.8)
    ctx.save()
    clip_to(ctx, inner)
    fill(ctx, lambda c: c.rectangle(32, 0, 30, 64), darken(TEAL, 0.25))
    ctx.restore()
    stroke(ctx, inner, INK, 1.8)
    I(ctx, lambda c: poly(c, star_pts(32, 31, 10, 4.4)), "#fff1c4", 1.8)
    shine(ctx, 20, 20, 2.6, 10, 0.3)


@icon("freeze")
def _freeze(ctx):
    cube = lambda c: rrect(c, 8, 14, 40, 40, 8)
    I(ctx, cube, ICE)
    ctx.save()
    clip_to(ctx, cube)
    fill(ctx, lambda c: poly(c, [(8, 54), (48, 14), (48, 54)]), "#7cc6dd", 0.7)
    fill(ctx, lambda c: poly(c, [(14, 20), (26, 20), (14, 32)]), WHITE, 0.8)
    ctx.restore()
    stroke(ctx, cube, INK, LW)
    # snowflake
    cx, cy, r = 44, 20, 13
    for k in range(3):
        a = k * math.pi / 3
        for w, col in ((5.2, INK), (2.4, WHITE)):
            stroke(ctx, lambda c, a=a: (c.move_to(cx - math.cos(a) * r, cy - math.sin(a) * r),
                                        c.line_to(cx + math.cos(a) * r, cy + math.sin(a) * r)), col, w)
    for k in range(6):
        a = k * math.pi / 3
        px, py = cx + math.cos(a) * r * 0.62, cy + math.sin(a) * r * 0.62
        for w, col in ((4.2, INK), (1.8, WHITE)):
            stroke(ctx, lambda c, a=a, px=px, py=py: (
                c.move_to(px + math.cos(a + 2.4) * 4, py + math.sin(a + 2.4) * 4), c.line_to(px, py),
                c.line_to(px + math.cos(a - 2.4) * 4, py + math.sin(a - 2.4) * 4)), col, w)
    I(ctx, lambda c: circle(c, cx, cy, 2.6), WHITE, 1.4)


@icon("poison")
def _poison(ctx):
    flask = lambda c: (c.move_to(26, 8), c.line_to(38, 8), c.line_to(38, 22), c.curve_to(52, 28, 56, 50, 44, 58),
                       c.line_to(20, 58), c.curve_to(8, 50, 12, 28, 26, 22), c.close_path())
    I(ctx, flask, "#e9f3ee")
    ctx.save()
    clip_to(ctx, flask)
    fill(ctx, lambda c: (c.move_to(0, 36), c.curve_to(16, 32, 40, 40, 64, 34), c.line_to(64, 64), c.line_to(0, 64),
                         c.close_path()), "#8ccf4d")
    fill(ctx, lambda c: c.rectangle(36, 30, 30, 40), "#5f9e3a", 0.6)
    for (x, y, r) in ((24, 48, 2.6), (34, 42, 1.8), (30, 52, 1.4)):
        I(ctx, lambda c, x=x, y=y, r=r: circle(c, x, y, r), "#c8f08a", 1.0)
    ctx.restore()
    stroke(ctx, flask, INK, LW)
    I(ctx, lambda c: rrect(c, 23, 4, 18, 7, 2.5), "#a26cc8")
    shine(ctx, 18, 34, 2.6, 10, 0.4)
    for (x, y, r) in ((46, 12, 3.4), (52, 4, 2.4), (14, 14, 2.6)):
        I(ctx, lambda c, x=x, y=y, r=r: circle(c, x, y, r), "#b6e07a", 1.4)


def glyph_x2(ctx, x, y, s):
    """Stroke-built '×2' (no fonts needed)."""
    def strokes(c):
        c.move_to(x - 9 * s, y - 5 * s), c.line_to(x - 1 * s, y + 5 * s)
        c.move_to(x - 1 * s, y - 5 * s), c.line_to(x - 9 * s, y + 5 * s)
        c.move_to(x + 2 * s, y - 4 * s)
        c.curve_to(x + 3 * s, y - 10 * s, x + 13 * s, y - 10 * s, x + 12 * s, y - 3 * s)
        c.curve_to(x + 11 * s, y + 1 * s, x + 4 * s, y + 4 * s, x + 2 * s, y + 8 * s)
        c.line_to(x + 13 * s, y + 8 * s)
    stroke(ctx, strokes, INK, 7.5 * s)
    stroke(ctx, strokes, WHITE, 3.6 * s)


@icon("double_damage")
def _double(ctx):
    I(ctx, lambda c: poly(c, star_pts(32, 32, 30, 20, 12, 0.1)), RED)
    I(ctx, lambda c: poly(c, star_pts(32, 32, 22, 16, 12, 0.36)), ORANGE, 0)
    glyph_x2(ctx, 30, 33, 1.35)


@icon("low_gravity")
def _lowgrav(ctx):
    moon = lambda c: circle(c, 32, 36, 18)
    I(ctx, moon, "#d9d4f0")
    ctx.save()
    clip_to(ctx, moon)
    fill(ctx, lambda c: circle(c, 40, 44, 18), "#b3abd8", 0.8)
    for (x, y, r) in ((26, 30, 4), (38, 40, 3), (28, 44, 2.4), (40, 28, 2)):
        I(ctx, lambda c, x=x, y=y, r=r: circle(c, x, y, r), "#c2bbe2", 1.2)
    ctx.restore()
    stroke(ctx, moon, INK, LW)
    stroke(ctx, lambda c: ellipse(c, 32, 38, 29, 8, -0.3), INK, 4.2)
    stroke(ctx, lambda c: ellipse(c, 32, 38, 29, 8, -0.3), GOLD, 2)
    ctx.save()
    clip_to(ctx, lambda c: c.rectangle(0, 0, 64, 34))
    I(ctx, moon, None, 0)
    ctx.restore()
    for (x, y) in ((10, 14), (52, 10)):
        I(ctx, lambda c, x=x, y=y: poly(c, [(x, y - 7), (x + 6, y), (x + 2.4, y), (x + 2.4, y + 6), (x - 2.4, y + 6),
                                             (x - 2.4, y), (x - 6, y)]), "#7fd0cf", 1.6)


@icon("wind_control")
def _wind(ctx):
    stroke(ctx, lambda c: (c.move_to(10, 60), c.line_to(10, 8)), INK, 5)
    stroke(ctx, lambda c: (c.move_to(10, 60), c.line_to(10, 8)), STEEL, 2.4)
    sock = lambda c: (c.move_to(11, 10), c.line_to(44, 14), c.curve_to(52, 16, 54, 22, 46, 24), c.line_to(11, 26),
                      c.close_path())
    I(ctx, sock, WHITE)
    ctx.save()
    clip_to(ctx, sock)
    for x in (11, 31):
        fill(ctx, lambda c, x=x: c.rectangle(x, 0, 10, 40), ORANGE)
    fill(ctx, lambda c: c.rectangle(0, 20, 64, 10), INK, 0.15)
    ctx.restore()
    stroke(ctx, sock, INK, LW)
    for (y, x0, x1, curl) in ((36, 18, 50, 1), (46, 22, 58, -1), (56, 16, 44, 1)):
        stroke(ctx, lambda c, y=y, x0=x0, x1=x1, k=curl: (c.move_to(x0, y), c.line_to(x1 - 4, y),
                                                          c.curve_to(x1 + 2, y, x1 + 2, y - 7 * k, x1 - 3, y - 6 * k)),
               INK, 4.6)
        stroke(ctx, lambda c, y=y, x0=x0, x1=x1, k=curl: (c.move_to(x0, y), c.line_to(x1 - 4, y),
                                                          c.curve_to(x1 + 2, y, x1 + 2, y - 7 * k, x1 - 3, y - 6 * k)),
               "#bfe9ea", 2.0)


@icon("skip")
def _skip(ctx):
    glass = lambda c: (c.move_to(14, 8), c.line_to(42, 8), c.curve_to(42, 22, 32, 28, 32, 32),
                       c.curve_to(32, 36, 42, 42, 42, 56), c.line_to(14, 56), c.curve_to(14, 42, 24, 36, 24, 32),
                       c.curve_to(24, 28, 14, 22, 14, 8), c.close_path())
    I(ctx, glass, "#e6f4f4")
    ctx.save()
    clip_to(ctx, glass)
    fill(ctx, lambda c: poly(c, [(16, 18), (40, 18), (28, 31)]), GOLD)
    fill(ctx, lambda c: (c.move_to(16, 56), c.curve_to(20, 46, 36, 46, 40, 56), c.close_path()), GOLD)
    stroke(ctx, lambda c: (c.move_to(28, 32), c.line_to(28, 48)), GOLD, 1.6)
    ctx.restore()
    stroke(ctx, glass, INK, LW)
    for y in (6, 58):
        I(ctx, lambda c, y=y: rrect(c, 10, y - 3, 36, 6, 2.5), WOOD)
    for (x, s) in ((44, 1), (52, 1)):
        I(ctx, lambda c, x=x: poly(c, [(x, 22), (x + 9, 32), (x, 42)]), ORANGE, 1.8)
    I(ctx, lambda c: rrect(c, 60, 22, 3.4, 20, 1.4), ORANGE, 1.8)


# --------------------------------------------------------------------------

def _with_shadow(path):
    im = Image.open(path).convert("RGBA")
    a = im.getchannel("A")
    sh = Image.new("RGBA", im.size, (24, 45, 53, 0))
    sh.putalpha(a.point(lambda v: int(v * 0.28)))
    sh = sh.filter(ImageFilter.GaussianBlur(1.1))
    base = Image.new("RGBA", im.size, (0, 0, 0, 0))
    base.alpha_composite(sh, (1, 2))
    base.alpha_composite(im)
    base.save(path)


def render_icon(name, path, svg=None):
    fn = ICONS[name]
    s, ctx = surface(64, 64)
    fn(ctx)
    s.write_to_png(str(path))
    _with_shadow(path)
    if svg is not None:
        vs, vctx = svg_surface(svg, 64, 64)
        fn(vctx)
        vs.finish()


def build_all(names=None):
    out = ART / "weapons"
    out.mkdir(parents=True, exist_ok=True)
    for name in (names or ICONS):
        render_icon(name, out / f"{name}.png", ART / "src" / "weapons" / f"{name}.svg")
    return {"weapons": sorted(ICONS)}
