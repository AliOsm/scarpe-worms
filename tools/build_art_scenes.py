"""Backdrops (sky-*.png) and the menu illustration (menu-bg.png).

Each backdrop is a stack of procedural layers: sky gradient, light source,
clouds, 2-3 mountain ranges with atmospheric haze, and a few small floating
islands set far back between the ranges.  No playable terrain is drawn, and
nothing in the lower half has a dark ink outline: the game's bitmap terrain
must read as the only solid ground.  A light paper grain is added in post
(seeded, so builds are byte-for-byte reproducible).
"""
from __future__ import annotations

import math
import zlib

import cairocffi as cairo
from PIL import Image, ImageChops

from build_art_core import (
    ART, GOLD, INK, ORANGE, PAPER, TEAL, WHITE, Rand, circle, clip_to, darken, ellipse, fbm1d, fill,
    inked, lighten, lin_grad, mix, outline_pass, poly, rad_grad, rrect, rgb, smooth, src, star_pts, stroke,
    surface,
)

W, H = 1600, 800


# --------------------------------------------------------------------------
# Generic layers
# --------------------------------------------------------------------------

def sky(ctx, w, h, stops):
    ctx.set_source(lin_grad(0, 0, 0, h, stops))
    ctx.paint()


def glow(ctx, x, y, r, col, a=0.6):
    ctx.set_source(rad_grad(x, y, 0, r, [(0, col, a), (0.35, col, a * 0.45), (1, col, 0)]))
    ctx.paint()


def ridge_pts(w, base, amp, seed, freq=3.0, sharp=False, step=5):
    f = fbm1d(seed, 5, 1.0)
    pts = []
    x = -20
    while x <= w + 20:
        v = f(x / w * freq * math.tau / 2)
        if sharp:
            v = 1 - abs(v) * 2.2
            v = max(-1.0, min(1.0, v))
        pts.append((x, base - amp * (0.5 + 0.5 * v)))
        x += step
    return pts


def ridge_y(pts, x):
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        if x0 <= x <= x1:
            return y0 + (y1 - y0) * (x - x0) / max(1e-6, x1 - x0)
    return pts[-1][1]


def ridge(ctx, w, h, pts, col, rim=None, rim_w=3.0, haze=None, outline=None, snow=None, shade=None):
    path = lambda c: (poly(c, pts + [(w + 20, h + 20), (-20, h + 20)]))
    fill(ctx, path, col)
    ctx.save()
    clip_to(ctx, path)
    if shade:
        # shadowed right-hand faces: shade everything, then re-light with a copy shifted left
        fill(ctx, lambda c: c.rectangle(-20, 0, w + 40, h + 20), shade)
        for (dx, dy) in ((-46, 5),):
            sp = [(x + dx, y + dy) for (x, y) in pts]
            fill(ctx, lambda c, sp=sp: poly(c, sp + [(w + 80, h + 20), (-80, h + 20)]), col)
    if snow:
        line, scol = snow
        runs, cur = [], []
        for (x, y) in pts:
            if y < line:
                cur.append((x, y))
            elif cur:
                runs.append(cur)
                cur = []
        if cur:
            runs.append(cur)
        for run in runs:
            if len(run) < 2:
                continue
            bottom = []
            for i, (x, y) in enumerate(run):
                dd = (line - y) * 0.55
                zig = math.sin(i * 1.7) * 5 + math.sin(i * 0.45) * 4
                bottom.append((x, min(line + 2, y + dd + zig)))
            fill(ctx, lambda c, r_=run, b_=bottom: smooth(c, r_ + b_[::-1], True, 0.3), scol)
    if haze:
        top = min(p[1] for p in pts)
        ctx.set_source(lin_grad(0, top, 0, h, [(0, haze, 0.0), (0.55, haze, 0.35), (1, haze, 0.85)]))
        ctx.paint()
    ctx.restore()
    if rim:
        stroke(ctx, lambda c: poly(c, pts, close=False), rim, rim_w, 0.85)
    if outline:
        stroke(ctx, lambda c: poly(c, pts, close=False), outline, 2.0, 0.8)


def soft_cloud(ctx, x, y, w, h, seed, col, shade, outline=None, alpha=1.0, lw=2.5):
    r = Rand(seed)
    n = max(4, int(w / (h * 0.75)))
    puffs = []
    for i in range(n):
        u = (i + 0.5) / n
        rr = h * (0.32 + 0.3 * math.sin(math.pi * u)) * r.uniform(0.8, 1.15)
        puffs.append((x + w * (0.08 + 0.84 * u), y + h * 0.75 - rr * r.uniform(0.55, 0.95), rr))
    base = lambda c: rrect(c, x + w * 0.05, y + h * 0.5, w * 0.9, h * 0.32, h * 0.16)
    fns = [lambda c, p=p: circle(c, *p) for p in puffs] + [base]
    ctx.push_group()
    if outline:
        outline_pass(ctx, fns, lw / 2, outline)
    for fn in fns:
        fill(ctx, fn, shade)
    ctx.save()
    ctx.new_path()
    for fn in fns:
        fn(ctx)
    ctx.clip()
    for (px, py, rr) in puffs:
        fill(ctx, lambda c, a=(px, py, rr): circle(c, a[0] - a[2] * 0.1, a[1] - a[2] * 0.18, a[2] * 0.9), col)
    for (px, py, rr) in puffs[1:-1]:
        fill(ctx, lambda c, a=(px, py, rr): circle(c, a[0] - a[2] * 0.3, a[1] - a[2] * 0.4, a[2] * 0.38),
             lighten(col, 0.6), 0.7)
    ctx.restore()
    ctx.pop_group_to_source()
    ctx.paint_with_alpha(alpha)


def birds(ctx, pts, col, s=1.0):
    for (x, y, k) in pts:
        stroke(ctx, lambda c, x=x, y=y, k=k: (c.move_to(x - 7 * k * s, y - 2 * k * s),
                                              c.curve_to(x - 4 * k * s, y - 5 * k * s, x - 1 * k * s, y - 3 * k * s, x, y),
                                              c.curve_to(x + 1 * k * s, y - 3 * k * s, x + 4 * k * s, y - 5 * k * s,
                                                         x + 7 * k * s, y - 2 * k * s)), col, 2.0 * k * s, 0.8)


# --------------------------------------------------------------------------
# Floating islands and their decorations
# --------------------------------------------------------------------------

def island(ctx, x, y, w, depth, pal, seed, outline, lw=3.0, decor=None, falls=None):
    """pal: dict top, top_dark, rock, rock_dark, rock_light."""
    r = Rand(seed)
    hw = w / 2
    # underside: jagged inverted cone
    n = 9
    left, right = [], []
    tipx = x + r.jit(w * 0.08)
    for i in range(1, n):
        u = i / n
        span = hw * (1 - u) ** 0.9
        cy = y + depth * (u ** 1.15)
        left.append((tipx - span * (1 + r.jit(0.12)) + (x - tipx) * (1 - u), cy + r.jit(depth * 0.04)))
        right.append((tipx + span * (1 + r.jit(0.12)) + (x - tipx) * (1 - u), cy + r.jit(depth * 0.04)))
    under = [(x - hw, y)] + left + [(tipx, y + depth)] + right[::-1] + [(x + hw, y)]
    rock = lambda c: poly(c, under)
    if falls:
        for (fx, fl) in falls:
            fxx = x + fx * hw
            ctx.save()
            ctx.set_source(lin_grad(0, y, 0, y + fl, [(0, "#d9f1f2", 0.95), (0.8, "#bfe6ea", 0.6), (1, "#bfe6ea", 0)]))
            rrect(ctx, fxx - 5, y, 10, fl, 4)
            ctx.fill()
            ctx.restore()
            stroke(ctx, lambda c, fxx=fxx, fl=fl: (c.move_to(fxx - 1.5, y + 8), c.line_to(fxx - 1.5, y + fl * 0.7)),
                   WHITE, 1.6, 0.7)
            for k in range(4):
                fill(ctx, lambda c, fxx=fxx, fl=fl, k=k: circle(c, fxx + (k - 1.5) * 6, y + fl * 0.95 - k % 2 * 4,
                                                                5 - k % 2), WHITE, 0.35)
    if outline:
        stroke(ctx, rock, outline, lw * 2)
    fill(ctx, rock, pal["rock"])
    ctx.save()
    clip_to(ctx, rock)
    fill(ctx, lambda c: poly(c, [(tipx, y - 5), (x + hw + 5, y - 5), (x + hw + 5, y + depth + 5), (tipx, y + depth + 5)]),
         pal["rock_dark"], 0.55)
    for k in range(1, 5):
        yy = y + depth * k / 5.2
        stroke(ctx, lambda c, yy=yy, k=k: (c.move_to(x - hw, yy), c.curve_to(x - hw * 0.3, yy + 6, x + hw * 0.3, yy - 4,
                                                                             x + hw, yy + 3)),
               pal["rock_dark"], 2.2, 0.5)
    for k in range(int(w / 18)):
        px = x + r.uniform(-hw * 0.7, hw * 0.6)
        py = y + r.uniform(depth * 0.1, depth * 0.55)
        fill(ctx, lambda c, px=px, py=py, s=r.uniform(3, 7): ellipse(c, px, py, s * 1.4, s * 0.8, r.jit(0.4)),
             pal["rock_light"], 0.55)
    ctx.restore()
    # hanging roots
    for k in range(int(w / 40) + 1):
        rx = x + r.uniform(-hw * 0.7, hw * 0.7)
        ln = r.uniform(12, 30)
        stroke(ctx, lambda c, rx=rx, ln=ln: (c.move_to(rx, y + 6), c.curve_to(rx + 4, y + ln * 0.5, rx - 4, y + ln * 0.7,
                                                                              rx + 1, y + 6 + ln)),
               pal.get("root", pal["top_dark"]), 2.0, 0.8)
    # grass/sand/snow cap with drips
    cap_h = max(8, w * 0.055)
    top = []
    m = 14
    for i in range(m + 1):
        u = i / m
        px = x - hw - 4 + (w + 8) * u
        top.append((px, y - math.sin(math.pi * u) * cap_h * 0.9 - 2))
    drips = []
    for i in range(m, -1, -1):
        u = i / m
        px = x - hw - 4 + (w + 8) * u
        dy = cap_h * (0.55 + 0.45 * (i % 2)) + r.jit(2)
        drips.append((px, y + dy))
    cap = lambda c: smooth(c, top + drips, True, 0.35)
    if outline:
        stroke(ctx, cap, outline, lw * 2)
    fill(ctx, cap, pal["top"])
    ctx.save()
    clip_to(ctx, cap)
    fill(ctx, lambda c: c.rectangle(x - hw - 10, y + 1, w + 20, cap_h * 2), pal["top_dark"], 0.8)
    stroke(ctx, lambda c: smooth(c, [(p[0], p[1] + 3) for p in top], False, 0.35), lighten(pal["top"], 0.35), 3, 0.7)
    ctx.restore()
    if decor:
        decor(ctx, x, y, w, r)


def far_isle(ctx, x, y, s, w, depth, pal, seed, tint, t, decor=None, falls=None, extra=None, ink=None):
    """A floating island pushed onto a distant plane.

    Drawn small (scale s), with a thin outline in the island's own shade
    instead of ink, then washed with the atmosphere colour (tint at strength
    t) so it sits behind the gameplay layer and never reads as solid ground.
    """
    ink = ink or mix(pal["rock_dark"], tint, 0.15)
    ctx.push_group()
    ctx.save()
    ctx.translate(x, y)
    ctx.scale(s, s)
    island(ctx, 0, 0, w, depth, pal, seed, ink, 1.6, decor, falls)
    if extra:
        extra(ctx)
    ctx.restore()
    ctx.set_operator(cairo.OPERATOR_ATOP)
    src(ctx, tint, t)
    ctx.paint()
    ctx.set_operator(cairo.OPERATOR_OVER)
    ctx.pop_group_to_source()
    ctx.paint()


def tree_round(ctx, x, y, s, col, dark, trunk, outline=None, lw=2.5):
    stroke(ctx, lambda c: (c.move_to(x, y), c.line_to(x, y - 14 * s)), outline or darken(trunk, 0.4), 6 * s)
    stroke(ctx, lambda c: (c.move_to(x, y), c.line_to(x, y - 14 * s)), trunk, 3.6 * s)
    blobs = [(x, y - 24 * s, 12 * s), (x - 8 * s, y - 18 * s, 8 * s), (x + 8 * s, y - 18 * s, 8.5 * s)]
    fns = [lambda c, b=b: circle(c, *b) for b in blobs]
    if outline:
        outline_pass(ctx, fns, lw / 2, outline)
    for fn in fns:
        fill(ctx, fn, dark)
    for b in blobs:
        fill(ctx, lambda c, b=b: circle(c, b[0] - b[2] * 0.15, b[1] - b[2] * 0.2, b[2] * 0.82), col)
    fill(ctx, lambda c: circle(c, x - 4 * s, y - 28 * s, 4 * s), lighten(col, 0.3), 0.7)


def tree_pine(ctx, x, y, s, col, dark, outline=None, snow=None, lw=2.5):
    tiers = [(0, 22, 15), (9, 18, 12), (17, 13, 9)]
    if outline:
        for (dy, ww, hh) in tiers:
            stroke(ctx, lambda c, dy=dy, ww=ww, hh=hh: poly(c, [(x - ww * s / 2, y - dy * s), (x, y - (dy + hh + 8) * s),
                                                               (x + ww * s / 2, y - dy * s)]), outline, lw * 2)
    stroke(ctx, lambda c: (c.move_to(x, y + 2), c.line_to(x, y - 6 * s)), "#6b4a35", 4 * s)
    for (dy, ww, hh) in tiers:
        tri = [(x - ww * s / 2, y - dy * s), (x, y - (dy + hh + 8) * s), (x + ww * s / 2, y - dy * s)]
        fill(ctx, lambda c, t=tri: poly(c, t), dark)
        fill(ctx, lambda c, t=tri: poly(c, [t[0], t[1], ((t[0][0] + t[2][0]) / 2, t[2][1])]), col)
        if snow:
            fill(ctx, lambda c, t=tri: poly(c, [((t[0][0] + t[1][0]) / 2, (t[0][1] + t[1][1]) / 2), t[1],
                                                ((t[2][0] + t[1][0]) / 2, (t[2][1] + t[1][1]) / 2),
                                                (t[1][0] + 2 * s, (t[2][1] + t[1][1]) / 2 + 3 * s),
                                                (t[1][0] - 3 * s, (t[0][1] + t[1][1]) / 2 + 2 * s)]), snow)


def cactus(ctx, x, y, s, col, dark, outline):
    def shape(c):
        c.move_to(x, y)
        c.line_to(x, y - 34 * s)
        c.move_to(x, y - 14 * s)
        c.line_to(x - 9 * s, y - 14 * s)
        c.line_to(x - 9 * s, y - 26 * s)
        c.move_to(x, y - 20 * s)
        c.line_to(x + 9 * s, y - 20 * s)
        c.line_to(x + 9 * s, y - 31 * s)
    stroke(ctx, shape, outline, 12 * s)
    stroke(ctx, shape, col, 7.2 * s)
    stroke(ctx, lambda c: (c.move_to(x + 1.6 * s, y - 2 * s), c.line_to(x + 1.6 * s, y - 32 * s)), dark, 1.8 * s, 0.8)
    fill(ctx, lambda c: circle(c, x, y - 37 * s, 3 * s), "#ff8fa3")


def rock_spire(ctx, x, y, s, col, dark, outline):
    pts = [(x - 10 * s, y), (x - 6 * s, y - 26 * s), (x - 1 * s, y - 34 * s), (x + 5 * s, y - 24 * s), (x + 9 * s, y)]
    inked(ctx, lambda c: poly(c, pts), col, 2.0, outline)
    fill(ctx, lambda c: poly(c, [pts[2], pts[3], pts[4], (x, y)]), dark, 0.6)


# --------------------------------------------------------------------------
# Themes
# --------------------------------------------------------------------------

def windmill(ctx, x, y, s, line="#6f949a"):
    tower = [(x - 14 * s, y), (x - 8 * s, y - 60 * s), (x + 8 * s, y - 60 * s), (x + 14 * s, y)]
    inked(ctx, lambda c: poly(c, tower), "#f3e6c8", 1.8, line)
    inked(ctx, lambda c: poly(c, [(x - 11 * s, y - 60 * s), (x, y - 72 * s), (x + 11 * s, y - 60 * s)]), "#e2a08a", 1.8,
          line)
    for k in range(4):
        a = 0.4 + k * math.pi / 2
        bx, by = x + math.cos(a) * 34 * s, y - 62 * s + math.sin(a) * 34 * s
        stroke(ctx, lambda c, bx=bx, by=by: (c.move_to(x, y - 62 * s), c.line_to(bx, by)), line, 2.4)
        ctx.save()
        ctx.translate(x, y - 62 * s)
        ctx.rotate(a)
        inked(ctx, lambda c: rrect(c, 10 * s, -2 * s, 24 * s, 8 * s, 1.5), "#fff8ea", 1.4, line)
        ctx.restore()
    inked(ctx, lambda c: circle(c, x, y - 62 * s, 3.5 * s), GOLD, 1.4, line)


def sea(ctx, w, h, col, dark, y0=None):
    y0 = y0 or h * 0.93
    ctx.set_source(lin_grad(0, y0 - 10, 0, h, [(0, col, 0.0), (0.3, col, 0.85), (1, dark, 1.0)]))
    ctx.rectangle(0, y0 - 10, w, h - y0 + 10)
    ctx.fill()
    for k in range(int(w / 90)):
        x = 30 + k * 90 + (k * 53) % 40
        yy = y0 + 10 + (k * 17) % 22
        stroke(ctx, lambda c, x=x, yy=yy: (c.move_to(x, yy), c.curve_to(x + 8, yy - 4, x + 16, yy - 4, x + 24, yy)),
               WHITE, 2.0, 0.45)


def balloon(ctx, x, y, s):
    for sx in (-1, 1):
        stroke(ctx, lambda c, sx=sx: (c.move_to(x + sx * 18 * s, y + 20 * s), c.line_to(x + sx * 7 * s, y + 44 * s)),
               "#7a4a3a", 1.6)
    env = lambda c: (c.move_to(x, y + 30 * s), c.curve_to(x - 40 * s, y + 5 * s, x - 40 * s, y - 50 * s, x, y - 50 * s),
                     c.curve_to(x + 40 * s, y - 50 * s, x + 40 * s, y + 5 * s, x, y + 30 * s), c.close_path())
    inked(ctx, env, "#f57c49", 2.4, "#7a4a3a")
    ctx.save()
    clip_to(ctx, env)
    for k in (-1, 1):
        fill(ctx, lambda c, k=k: ellipse(c, x + k * 22 * s, y - 10 * s, 9 * s, 45 * s), GOLD)
    fill(ctx, lambda c: ellipse(c, x, y - 10 * s, 7 * s, 45 * s), "#fff1dd")
    ctx.restore()
    stroke(ctx, env, "#7a4a3a", 2.4)
    inked(ctx, lambda c: rrect(c, x - 8 * s, y + 42 * s, 16 * s, 12 * s, 3), "#c98a4f", 2.0, "#7a4a3a")


def arch(ctx, x, y, s, ink="#3a2a2e"):
    pth = lambda c: (c.move_to(x - 70 * s, y), c.curve_to(x - 70 * s, y - 120 * s, x + 50 * s, y - 120 * s, x + 50 * s, y),
                     c.line_to(x + 30 * s, y), c.curve_to(x + 30 * s, y - 80 * s, x - 50 * s, y - 80 * s, x - 50 * s, y),
                     c.close_path())
    inked(ctx, pth, "#d98d66", 2.6, ink)
    ctx.save()
    clip_to(ctx, pth)
    for k in range(5):
        fill(ctx, lambda c, k=k: c.rectangle(x - 80, y - 110 + k * 22, 160, 4), "#b5684c", 0.5)
    fill(ctx, lambda c: c.rectangle(x + 10, y - 130, 60, 140), "#9c5440", 0.4)
    ctx.restore()


def crystal(ctx, x, y, s, ink=INK):
    for (dx, hh, ww, a) in ((-7, 26, 7, -0.25), (6, 20, 6, 0.3), (0, 36, 9, 0.0)):
        ctx.save()
        ctx.translate(x + dx * s, y)
        ctx.rotate(a)
        pts = [(-ww * s / 2, 0), (-ww * s / 2, -hh * s * 0.75), (0, -hh * s), (ww * s / 2, -hh * s * 0.75), (ww * s / 2, 0)]
        inked(ctx, lambda c: poly(c, pts), "#a9e4f2", 1.6, ink)
        fill(ctx, lambda c: poly(c, [(0, 0), (0, -hh * s), (ww * s / 2, -hh * s * 0.75), (ww * s / 2, 0)]), "#6fb4c9", 0.6)
        stroke(ctx, lambda c: (c.move_to(-ww * s * 0.2, -3), c.line_to(-ww * s * 0.2, -hh * s * 0.65)), WHITE, 1.6, 0.8)
        ctx.restore()


def iceberg(ctx, x, y, s):
    pts = [(x - 60 * s, y), (x - 44 * s, y - 34 * s), (x - 20 * s, y - 40 * s), (x - 4 * s, y - 70 * s),
           (x + 22 * s, y - 50 * s), (x + 40 * s, y - 52 * s), (x + 62 * s, y)]
    inked(ctx, lambda c: poly(c, pts), "#eef8fc", 1.4, "#8fb8cc")
    fill(ctx, lambda c: poly(c, [(x - 4 * s, y - 70 * s), (x + 22 * s, y - 50 * s), (x + 40 * s, y - 52 * s),
                                 (x + 62 * s, y), (x + 4 * s, y)]), "#c9e4ef", 0.8)
    fill(ctx, lambda c: ellipse(c, x, y + 4, 70 * s, 6 * s), "#3c7f99", 0.35)


def volcano(ctx, x, y, w, h):
    base = h * 0.82
    pts = [(x - 360, base), (x - 150, y + 60), (x - 70, y + 4), (x - 40, y), (x + 40, y), (x + 70, y + 6),
           (x + 160, y + 70), (x + 380, base)]
    cone = lambda c: smooth(c, pts + [(x + 380, base + 10), (x - 360, base + 10)], True, 0.25)
    fill(ctx, cone, "#5a2e44")
    ctx.save()
    clip_to(ctx, cone)
    fill(ctx, lambda c: poly(c, [(x + 10, y - 10), (x + 420, y - 10), (x + 420, base + 20), (x + 60, base + 20)]),
         "#3e2032", 0.7)
    for (lx, spread, wob) in ((-24, -26, 1), (20, 24, -1), (-4, -6, 1.4), (6, 40, 0.8)):
        ln = [(x + lx, y + 2)]
        for k in range(1, 10):
            ln.append((x + lx + spread * k + wob * math.sin(k * 1.3) * 10, y + k * 30))
        for wd, col, al in ((14, "#ff7a3d", 0.25), (6, "#ff7a3d", 0.95), (2.4, "#ffd35c", 1.0)):
            stroke(ctx, lambda c, ln=ln: smooth(c, ln, False, 0.5), col, wd, al)
    ctx.set_source(lin_grad(0, y, 0, base, [(0, "#c2513f", 0), (1, "#c2513f", 0.55)]))
    ctx.paint()
    ctx.restore()
    stroke(ctx, lambda c: smooth(c, pts, False, 0.25), "#e8743f", 2.6, 0.8)
    fill(ctx, lambda c: ellipse(c, x, y + 1, 42, 8), "#ffb347")
    fill(ctx, lambda c: ellipse(c, x, y, 30, 4.5), "#fff0b0")
    glow(ctx, x, y, 140, "#ffb347", 0.55)


# --------------------------------------------------------------------------
# Painterly depth helpers (round 3)
# --------------------------------------------------------------------------

def _peaks(pts, win=7):
    """Indices of local summits (smallest y within +/- win samples)."""
    out = []
    for i in range(win, len(pts) - win):
        y = pts[i][1]
        if all(y <= pts[j][1] for j in range(i - win, i + win + 1)) and (not out or i - out[-1] > win):
            out.append(i)
    return out


def faceted(ctx, w, h, pts, col, shade, base, seed, light=1, snow=None, snow_shade=None, rim=None, rim_w=2.4,
            haze=None, haze_top=0.0, gullies=None, texture=None):
    """A mountain range with sculpted light/shadow faces instead of one flat tone.

    light=+1: light from the right (shadowed faces are the left slopes), -1 the reverse.
    Each summit gets a wandering spine down to the base; the face away from the
    light is filled with the shade colour.  Gullies add a few thin facet lines.
    """
    r = Rand(seed)
    body = lambda c: poly(c, pts + [(w + 20, h + 20), (-20, h + 20)])
    fill(ctx, body, col)
    ctx.save()
    clip_to(ctx, body)
    if texture:
        texture(ctx)
    if snow:
        line = snow
        runs, cur = [], []
        for (x, y) in pts:
            if y < line:
                cur.append((x, y))
            elif cur:
                runs.append(cur)
                cur = []
        if cur:
            runs.append(cur)
        for run in runs:
            if len(run) < 2:
                continue
            bottom = []
            for i, (x, y) in enumerate(run):
                dd = (line - y) * 0.6
                zig = math.sin(i * 1.9 + seed) * 6 + math.sin(i * 0.5) * 5
                bottom.append((x, min(line + 4, y + dd + zig)))
            fill(ctx, lambda c, r_=run, b_=bottom: smooth(c, r_ + b_[::-1], True, 0.3), WHITE if snow_shade else "#f4fbff")
    peaks = _peaks(pts)
    bounds = [0] + peaks + [len(pts) - 1]
    ctx.push_group()
    for k, i in enumerate(peaks):
        px, py = pts[i]
        # valley on the shadow side
        lo, hi = (bounds[k], i) if light > 0 else (i, bounds[k + 2])
        vi = max(range(lo, hi + 1), key=lambda j: pts[j][1])
        vx = pts[vi][0]
        lo, hi = (vi, i) if light > 0 else (i, vi)
        spine = []
        n = 9
        for s in range(n + 1):
            t = s / n
            x = px + (vx - px) * 0.22 * t + r.jit(7) * t
            y = py + (base + 40 - py) * t
            spine.append((x, y))
        # the face tapers from the valley toward the foot of the spine, so ranges
        # read as overlapping shoulders instead of vertical slabs
        vy = pts[vi][1]
        foot = (vx + (spine[-1][0] - vx) * 0.55, vy + (base + 40 - vy) * 0.85)
        if light > 0:
            face = list(pts[lo:i + 1]) + spine[1:] + [foot]
        else:
            face = list(pts[i:hi + 1]) + [foot] + spine[::-1][:-1]
        fill(ctx, lambda c, f=face: poly(c, f), shade, 0.62 if snow else 0.75)
        if gullies:
            gcol, galpha = gullies
            for g in range(r.randint(1, 3)):
                off = r.uniform(18, 60) * (1 if light > 0 else -1)
                gx0 = px + off * 0.3
                gl = [(gx0 + r.jit(3), py + 14 + g * 6)]
                for s in range(6):
                    gl.append((gl[-1][0] + off * 0.1 + r.jit(5), gl[-1][1] + (base - py) / 7))
                stroke(ctx, lambda c, gl=gl: smooth(c, gl, False, 0.5), gcol, 1.6, galpha)
    # faces and gullies dissolve toward the foot of the range: no hard wedge ends
    ctx.pop_group_to_source()
    top = min(p[1] for p in pts)
    ctx.mask(lin_grad(0, top, 0, base + 30, [(0, WHITE, 1.0), (0.6, WHITE, 0.85), (1, WHITE, 0.0)]))
    if haze:
        top = min(p[1] for p in pts)
        ctx.set_source(lin_grad(0, top, 0, h, [(0, haze, haze_top), (0.5, haze, 0.35 + haze_top * 0.5), (1, haze, 0.9)]))
        ctx.paint()
    ctx.restore()
    if rim:
        stroke(ctx, lambda c: poly(c, pts, close=False), rim, rim_w, 0.85)


def lit_hills(ctx, w, h, pts, col, top_col, shade, haze=None, rim=None, depth=60):
    """Rolling hills: lit crest band fading into a shadowed body."""
    body = lambda c: poly(c, pts + [(w + 20, h + 20), (-20, h + 20)])
    fill(ctx, body, col)
    ctx.save()
    clip_to(ctx, body)
    crest = [(x, y + depth) for (x, y) in pts]
    ctx.set_source(lin_grad(0, min(p[1] for p in pts), 0, max(p[1] for p in pts) + depth,
                            [(0, top_col, 0.9), (1, top_col, 0.0)]))
    poly(ctx, pts + crest[::-1])
    ctx.fill()
    # soft shadowed hollow under each crest
    ctx.set_source(lin_grad(0, max(p[1] for p in pts), 0, max(p[1] for p in pts) + depth * 2.5,
                            [(0, shade, 0.0), (0.5, shade, 0.35), (1, shade, 0.0)]))
    ctx.paint()
    if haze:
        ctx.set_source(lin_grad(0, min(p[1] for p in pts), 0, h, [(0, haze, 0.0), (0.6, haze, 0.45), (1, haze, 0.9)]))
        ctx.paint()
    ctx.restore()
    if rim:
        stroke(ctx, lambda c: poly(c, pts, close=False), rim, 2.4, 0.8)


def forest_band(ctx, pts, seed, col, dark, lit, s=1.0, spacing=13, kind="round", alpha=1.0, snow=None, ground=True):
    """A dense tree line along a ridge, as one silhouette with lit crowns."""
    r = Rand(seed)
    ctx.push_group()
    trees = []
    x = pts[0][0]
    while x < pts[-1][0]:
        trees.append((x + r.jit(4), r.uniform(0.6, 1.45) * s))
        x += spacing * s * r.uniform(0.7, 1.2)
    for (tx, ts) in trees:
        ty = ridge_y(pts, tx) + 6 * s
        if kind == "round":
            fill(ctx, lambda c, tx=tx, ty=ty, ts=ts: ellipse(c, tx, ty - 12 * ts, 9 * ts, 13 * ts), dark)
            fill(ctx, lambda c, tx=tx, ty=ty, ts=ts: ellipse(c, tx + 2 * ts, ty - 15 * ts, 6 * ts, 8 * ts), col)
            fill(ctx, lambda c, tx=tx, ty=ty, ts=ts: ellipse(c, tx + 3.5 * ts, ty - 19 * ts, 3 * ts, 3.5 * ts), lit, 0.8)
        else:
            tri = [(tx - 8 * ts, ty), (tx, ty - 30 * ts), (tx + 8 * ts, ty)]
            fill(ctx, lambda c, t=tri: poly(c, t), dark)
            fill(ctx, lambda c, t=tri: poly(c, [t[1], t[2], (t[1][0], t[2][1])]), col)
            if snow:
                fill(ctx, lambda c, tx=tx, ty=ty, ts=ts: poly(c, [(tx - 3.4 * ts, ty - 17 * ts), (tx, ty - 30 * ts),
                                                                   (tx + 3.4 * ts, ty - 17 * ts), (tx, ty - 20 * ts)]), snow)
    # ground under the tree line
    if ground:
        fill(ctx, lambda c: poly(c, pts + [(x, y + 30) for (x, y) in pts[::-1]]), dark)
    ctx.pop_group_to_source()
    ctx.paint_with_alpha(alpha)


def mist(ctx, w, y, thick, col, alpha, seed, waves=3):
    """A soft horizontal mist bank with a gently scalloped top."""
    f = fbm1d(seed, 4, 1.0)
    top = [(x, y - thick * 0.25 * (1 + f(x / w * math.tau * waves))) for x in range(-20, w + 21, 10)]
    ctx.save()
    poly(ctx, top + [(w + 20, y + thick), (-20, y + thick)])
    ctx.set_source(lin_grad(0, y - thick * 0.5, 0, y + thick, [(0, col, 0.0), (0.35, col, alpha), (0.75, col, alpha),
                                                                (1, col, 0.0)]))
    ctx.fill()
    ctx.restore()


def shafts(ctx, x, y, count, spread, start, length, col, alpha, seed):
    r = Rand(seed)
    for k in range(count):
        a = start + spread * (k + r.uniform(0.1, 0.9)) / count
        da = r.uniform(0.015, 0.045)
        ctx.save()
        poly(ctx, [(x, y), (x + math.cos(a) * length, y + math.sin(a) * length),
                   (x + math.cos(a + da) * length, y + math.sin(a + da) * length)])
        ctx.set_source(rad_grad(x, y, 0, length, [(0, col, alpha), (0.6, col, alpha * 0.5), (1, col, 0)]))
        ctx.fill()
        ctx.restore()


def cloud_bank(ctx, w, y, h_, col, shade, alpha, seed, lit=None):
    """Long painterly strata clouds: overlapping soft lozenges, lit on top."""
    r = Rand(seed)
    ctx.push_group()
    x = -60
    while x < w + 60:
        cw = r.uniform(120, 260)
        cy = y + r.jit(h_ * 0.4)
        fill(ctx, lambda c, a=(x, cy, cw): ellipse(c, a[0] + a[2] / 2, a[1] + 4, a[2] / 2, h_ * 0.42), shade)
        fill(ctx, lambda c, a=(x, cy, cw): ellipse(c, a[0] + a[2] / 2 - 6, a[1] - 2, a[2] / 2 * 0.92, h_ * 0.34), col)
        if lit:
            fill(ctx, lambda c, a=(x, cy, cw): ellipse(c, a[0] + a[2] / 2 - 12, a[1] - h_ * 0.16, a[2] / 2 * 0.6,
                                                       h_ * 0.12), lit, 0.8)
        x += cw * r.uniform(0.55, 0.8)
    ctx.pop_group_to_source()
    ctx.paint_with_alpha(alpha)


def puff_cloud(ctx, x, y, w_, h_, seed, col, shade, lit, alpha=1.0):
    """Volumetric cumulus without an outline: shaded base, lit domes, rim glow."""
    r = Rand(seed)
    n = max(4, int(w_ / (h_ * 0.6)))
    puffs = []
    for i in range(n):
        u = (i + 0.5) / n
        rr = h_ * (0.3 + 0.38 * math.sin(math.pi * u)) * r.uniform(0.8, 1.15)
        puffs.append((x + w_ * (0.06 + 0.88 * u) + r.jit(6), y + h_ * 0.72 - rr * r.uniform(0.5, 0.9), rr))
    ctx.push_group()
    for (px, py, rr) in puffs:
        fill(ctx, lambda c, a=(px, py, rr): circle(c, *a), shade)
    fill(ctx, lambda c: rrect(c, x + w_ * 0.04, y + h_ * 0.5, w_ * 0.92, h_ * 0.3, h_ * 0.15), shade)
    for (px, py, rr) in puffs:
        fill(ctx, lambda c, a=(px, py, rr): circle(c, a[0] - a[2] * 0.08, a[1] - a[2] * 0.16, a[2] * 0.86), col)
    for (px, py, rr) in puffs:
        fill(ctx, lambda c, a=(px, py, rr): circle(c, a[0] - a[2] * 0.22, a[1] - a[2] * 0.36, a[2] * 0.42), lit, 0.75)
    ctx.pop_group_to_source()
    ctx.paint_with_alpha(alpha)


def lake(ctx, w, y0, h, top, bottom, glint, seed):
    ctx.set_source(lin_grad(0, y0, 0, h, [(0, top, 1.0), (1, bottom, 1.0)]))
    ctx.rectangle(0, y0, w, h - y0)
    ctx.fill()
    r = Rand(seed)
    for k in range(60):
        x = r.uniform(0, w)
        yy = y0 + 6 + (h - y0) * r.random() ** 1.6
        L = r.uniform(10, 50) * (1 + (yy - y0) / (h - y0))
        stroke(ctx, lambda c, x=x, yy=yy, L=L: (c.move_to(x, yy), c.line_to(x + L, yy)), glint, 1.6, r.uniform(0.15, 0.4))
    stroke(ctx, lambda c: (c.move_to(0, y0 + 1), c.line_to(w, y0 + 1)), glint, 2, 0.5)


# --------------------------------------------------------------------------
# Themes
# --------------------------------------------------------------------------

def scene_meadow(ctx, w=W, h=H, seed=1):
    sky(ctx, w, h, [(0, "#4ea3c2"), (0.45, "#9fd3d6"), (0.75, "#e9f0dc"), (1, "#f4f0df")])
    sx, sy = w * 0.8, h * 0.17
    glow(ctx, sx, sy, w * 0.55, "#fff1c0", 0.9)
    shafts(ctx, sx, sy, 9, 1.4, 1.75, 1300, "#fffbe8", 0.1, 17)
    fill(ctx, lambda c: circle(c, sx, sy, 74), "#fff4cf", 0.3)
    fill(ctx, lambda c: circle(c, sx, sy, 50), "#fff8e2")
    cloud_bank(ctx, w, h * 0.13, 40, "#f5fbf8", "#cfe6ea", 0.4, 5, lit=WHITE)
    for (cx, cy, cw, ch, sd, a) in ((40, 60, 380, 120, 3, 0.95), (560, 30, 260, 86, 5, 0.85), (1010, 150, 240, 70, 9, 0.8),
                                    (1380, 40, 260, 76, 11, 0.85)):
        puff_cloud(ctx, cx, cy, cw, ch, sd, "#fbfdf9", "#c8e0e6", WHITE, a)
    birds(ctx, [(430, 170, 1.0), (458, 184, 0.8), (404, 190, 0.7), (1030, 120, 0.9)], "#3f6c77")
    # far range: faceted, snow-capped, lit from the sun on the right
    far = ridge_pts(w, h * 0.55, 240, seed * 11, 4.0, sharp=True)
    faceted(ctx, w, h, far, "#a7cfd2", "#7ba8b8", h * 0.55, 11, light=1, snow=h * 0.55 - 165, snow_shade=True,
            rim="#d9efee", haze="#d6ece8", haze_top=0.05, gullies=("#8fb8c2", 0.5))
    pal = dict(top="#8ccf6e", top_dark="#5f9e4f", rock="#b98a64", rock_dark="#7f5a43", rock_light="#d3a77d",
               root="#6b4a35")
    ink = "#7d8f80"

    def decor_trees(c, x, y, ww, r):
        for i in range(max(1, int(ww / 70))):
            tx = x - ww * 0.35 + (ww * 0.7) * (i + 0.5) / max(1, int(ww / 70)) + r.jit(10)
            tree_round(c, tx, y - 4, r.uniform(0.8, 1.2), "#7cc278", "#4f9a5c", "#7a5a40", ink, 1.6)
    far_isle(ctx, 300, h * 0.37, 0.42, 260, 150, pal, 31, "#cfe6e4", 0.45, decor_trees, falls=[(0.45, 170)], ink=ink)
    far_isle(ctx, 1040, h * 0.42, 0.3, 220, 130, pal, 35, "#d3e9e6", 0.52, decor_trees, ink=ink)
    far_isle(ctx, 1500, h * 0.33, 0.26, 170, 100, pal, 37, "#d3e9e6", 0.55, decor_trees, ink=ink)
    mist(ctx, w, h * 0.55, 70, "#eef7f2", 0.7, 61)
    # middle range: forested blue-green shoulders
    mid = ridge_pts(w, h * 0.64, 120, seed * 13 + 1, 2.8)
    lit_hills(ctx, w, h, mid, "#86b9a6", "#b4dcc0", "#689f96", haze="#d9ede3", rim="#b9dcc4", depth=50)
    forest_band(ctx, [(x, y + 26) for (x, y) in mid], 71, "#79b08f", "#5f9883", "#a6d0a8", 0.62, 12, alpha=0.85)
    mist(ctx, w, h * 0.66, 60, "#eef7f0", 0.6, 63)
    # near rolling hills with lit crests, hedgerows and a windmill
    near = ridge_pts(w, h * 0.74, 70, seed * 17 + 3, 2.2)
    lit_hills(ctx, w, h, near, "#8fc293", "#c3e3a6", "#6fa685", haze="#e6f2e4", rim="#d4ecbc")
    windmill(ctx, 1290, ridge_y(near, 1290) + 12, 0.85)
    for (x0, x1, sd) in ((980, 1170, 73), (130, 400, 75), (620, 700, 77)):
        forest_band(ctx, [(x, ridge_y(near, x) + 8) for x in range(x0, x1, 6)], sd, "#86b98f", "#6a9c82", "#b8dcab",
                    0.8, 10, alpha=0.65, ground=False)
    # calm valley mist and a still lake behind every cave
    mist(ctx, w, h * 0.8, 90, "#f1f7ef", 0.75, 65)
    lake(ctx, w, h * 0.885, h, "#a9d6d2", "#5f9fa8", WHITE, 67)


def scene_desert(ctx, w=W, h=H, seed=2):
    sky(ctx, w, h, [(0, "#d9775e"), (0.35, "#f0a173"), (0.7, "#fbd9ad"), (1, "#fbeedb")])
    sx, sy = w * 0.3, h * 0.33
    glow(ctx, sx, sy, w * 0.5, "#fff0c0", 0.9)
    shafts(ctx, sx, sy, 10, math.tau, 0, 1100, "#fff5d6", 0.07, 23)
    sun = lambda c: circle(c, sx, sy, 105)
    fill(ctx, sun, "#ffe39a")
    ctx.save()
    clip_to(ctx, sun)
    fill(ctx, lambda c: circle(c, sx - 20, sy - 25, 80), "#fff0bf", 0.6)
    for k in range(6):
        yy = sy + 20 + k * 16
        fill(ctx, lambda c, yy=yy, k=k: c.rectangle(sx - 120, yy, 240, 3 + k * 1.6), "#f2a774")
    ctx.restore()
    cloud_bank(ctx, w, h * 0.12, 34, "#ffe9d2", "#f2b28e", 0.65, 4, lit="#fff6e8")
    for (cx, cy, cw, ch, sd, a) in ((880, 60, 360, 70, 4, 0.8), (1260, 140, 280, 58, 6, 0.75), (60, 110, 240, 52, 8, 0.7)):
        puff_cloud(ctx, cx, cy, cw, ch, sd, "#fff1dd", "#efb595", "#fffaf0", a)
    birds(ctx, [(1100, 230, 0.9), (1130, 245, 0.7)], "#7a4a3a")
    balloon(ctx, 1380, 250, 0.8)
    # distant buttes: cool lavender haze so the terracotta terrain stands apart
    butte_range(ctx, w, h, h * 0.6, "#d9a39b", "#b98490", seed * 17, 150, "#f6d2bd", light=-1, haze="#f6d8c8")
    pal = dict(top="#f2cf8e", top_dark="#d9a868", rock="#cf7f58", rock_dark="#9c5440", rock_light="#e9a27a",
               root="#8a6a4a")
    ink = "#a8705c"

    def decor(c, x, y, ww, r):
        for i in range(max(1, int(ww / 90))):
            tx = x - ww * 0.3 + ww * 0.6 * (i + 0.5) / max(1, int(ww / 90)) + r.jit(10)
            if i % 2 == 0:
                cactus(c, tx, y - 2, r.uniform(0.9, 1.2), "#7fae6a", "#5d8f52", ink)
            else:
                rock_spire(c, tx, y - 2, r.uniform(0.8, 1.1), "#d98d66", "#9c5440", ink)
    far_isle(ctx, 190, h * 0.43, 0.38, 280, 160, pal, 41, "#f6cfb2", 0.5, decor, ink=ink)
    far_isle(ctx, 1080, h * 0.4, 0.44, 260, 150, pal, 45, "#f6cfb2", 0.46, decor, ink=ink,
             extra=lambda c: arch(c, 0, -6, 1.0, ink))
    far_isle(ctx, 760, h * 0.49, 0.26, 190, 110, pal, 43, "#f8d9c0", 0.55, decor, ink=ink)
    mist(ctx, w, h * 0.6, 60, "#fbe3cf", 0.55, 81)
    butte_range(ctx, w, h, h * 0.7, "#e5aa88", "#c58272", seed * 19, 115, "#fbd9bb", light=-1, haze="#fae2cc")
    mist(ctx, w, h * 0.72, 60, "#fdebd6", 0.6, 83)
    dunes = ridge_pts(w, h * 0.82, 50, seed * 23, 2.0)
    lit_hills(ctx, w, h, dunes, "#f2d0a4", "#fff0cf", "#e2b48c", haze="#fbeedb", rim="#fff3da", depth=40)
    r = Rand(29)
    for k in range(26):
        x = r.uniform(0, w)
        y = ridge_y(dunes, x) + r.uniform(14, 90)
        stroke(ctx, lambda c, x=x, y=y: (c.move_to(x, y), c.curve_to(x + 20, y - 5, x + 40, y - 5, x + 60, y)),
               "#e2b48c", 1.6, 0.45)
    for k in range(9):
        y = h * 0.58 + k * 18
        stroke(ctx, lambda c, y=y, k=k: (c.move_to(60 + k * 170, y), c.curve_to(90 + k * 170, y - 4, 120 + k * 170, y + 4,
                                                                                150 + k * 170, y)), WHITE, 1.6, 0.22)


def butte_range(ctx, w, h, base, col, shade, seed, amp, rim, light=-1, haze=None):
    """Eroded buttes: talus skirts, sheer banded cliffs, rounded caprock, a shadowed flank."""
    r = Rand(seed)
    pts = [(-20, base)]
    tops = []
    x = -20
    while x < w + 20:
        seg = r.uniform(90, 230)
        if r.random() < 0.62:
            hgt = amp * r.uniform(0.45, 1.0)
            cliff = seg * r.uniform(0.18, 0.26)      # talus width on each side
            x0, x1 = x + cliff, x + seg - cliff
            pts += [(x + 4, base), (x + cliff * 0.55, base - hgt * 0.22), (x0 - 3, base - hgt * 0.4),
                    (x0, base - hgt * 0.92), (x0 + 6, base - hgt), (x1 - 6, base - hgt + r.jit(3)), (x1, base - hgt * 0.9),
                    (x1 + 3, base - hgt * 0.42), (x + seg - cliff * 0.55, base - hgt * 0.2), (x + seg - 4, base)]
            tops.append((x0, x1, base - hgt, hgt, cliff))
        else:
            pts += [(x + seg * 0.3, base - amp * 0.1 * r.random()), (x + seg * 0.7, base - amp * 0.16 * r.random())]
        x += seg
    pts.append((w + 20, base))
    path = lambda c: poly(c, pts + [(w + 20, h + 20), (-20, h + 20)])
    fill(ctx, path, col)
    ctx.save()
    clip_to(ctx, path)
    for k in range(1, 8):
        yy = base - amp * k / 8
        band = [(xx, yy + 1.6 * math.sin(xx / 37 + k)) for xx in range(-20, w + 21, 20)]
        stroke(ctx, lambda c, b=band: poly(c, b, close=False), shade, 2.0 + k % 3, 0.4)
    for (x0, x1, top, hgt, cliff) in tops:
        if light < 0:
            face = [(x1 - (x1 - x0) * 0.16, top), (x1 + 4, top), (x1 + cliff + 4, top + hgt + 4),
                    (x1 - (x1 - x0) * 0.1, top + hgt + 4)]
        else:
            face = [(x0 - 4, top), (x0 + (x1 - x0) * 0.16, top), (x0 + (x1 - x0) * 0.1, top + hgt + 4),
                    (x0 - cliff - 4, top + hgt + 4)]
        fill(ctx, lambda c, f=face: poly(c, f), shade, 0.6)
        # caprock lip and a few vertical erosion grooves
        fill(ctx, lambda c, a=(x0, x1, top): rrect(c, a[0] + 2, a[2] - 1, a[1] - a[0] - 4, 5, 2.5), rim, 0.75)
        for g in range(int((x1 - x0) / 22)):
            gx = x0 + 10 + g * 22 + r.jit(5)
            stroke(ctx, lambda c, gx=gx, a=(top, hgt): (c.move_to(gx, a[0] + 8), c.line_to(gx + r.jit(2), a[0] + a[1] * 0.45)),
                   shade, 1.4, 0.4)
    if haze:
        ctx.set_source(lin_grad(0, base - amp, 0, h, [(0, haze, 0.0), (0.5, haze, 0.3), (1, haze, 0.85)]))
        ctx.paint()
    ctx.restore()
    stroke(ctx, lambda c: poly(c, pts, close=False), rim, 2.0, 0.7)


def scene_glacier(ctx, w=W, h=H, seed=3):
    sky(ctx, w, h, [(0, "#22305f"), (0.38, "#465d97"), (0.7, "#9fb6d8"), (1, "#dde8f0")])
    for k, (col, yb, amp, ph) in enumerate((("#7ff2c4", 130, 40, 0.0), ("#8fd4ff", 175, 50, 1.4), ("#c49cff", 95, 30, 2.6))):
        line = [(x, yb + math.sin(x / w * math.tau * 1.3 + ph) * amp) for x in range(-40, w + 60, 40)]
        for wd, al in ((120, 0.05), (84, 0.06), (54, 0.08), (28, 0.09), (10, 0.12)):
            stroke(ctx, lambda c, ln=line: smooth(c, ln, False, 0.5), col, wd, al)
        for x in range(0, w, 12):
            yy = yb + math.sin(x / w * math.tau * 1.3 + ph) * amp
            stroke(ctx, lambda c, x=x, yy=yy: (c.move_to(x, yy - 60), c.line_to(x, yy + 12)), col, 2, 0.06)
    r = Rand(9)
    for _ in range(120):
        x, y = r.uniform(0, w), r.uniform(0, h * 0.42)
        fill(ctx, lambda c, x=x, y=y, s=r.uniform(0.8, 2.0): circle(c, x, y, s), WHITE, r.uniform(0.4, 0.9))
    mx, my = w * 0.16, h * 0.16
    glow(ctx, mx, my, 260, "#e8f4ff", 0.55)
    shafts(ctx, mx, my, 6, 1.2, 0.3, 900, "#e8f4ff", 0.06, 31)
    fill(ctx, lambda c: circle(c, mx, my, 46), "#f6fbff")
    fill(ctx, lambda c: circle(c, mx + 14, my - 6, 9), "#d6e6f3", 0.7)
    fill(ctx, lambda c: circle(c, mx - 14, my + 12, 6), "#d6e6f3", 0.7)
    # far range: deep indigo, moonlit from the left, crisp ice facets
    far = ridge_pts(w, h * 0.58, 270, seed * 31, 4.2, sharp=True)
    faceted(ctx, w, h, far, "#6f86b8", "#4a5d92", h * 0.58, 31, light=-1, snow=h * 0.58 - 190, snow_shade=True,
            rim="#e9f3ff", haze="#a9bddb", haze_top=0.05, gullies=("#5d72a6", 0.55))
    pal = dict(top="#f6fbff", top_dark="#cfe3f2", rock="#7f9fbf", rock_dark="#57789a", rock_light="#a9c5de",
               root="#8fd4ff")
    ink = "#6f8faf"

    def decor(c, x, y, ww, r):
        for i in range(max(1, int(ww / 60))):
            tx = x - ww * 0.35 + ww * 0.7 * (i + 0.5) / max(1, int(ww / 60)) + r.jit(8)
            if i % 3 == 1:
                crystal(c, tx, y - 2, r.uniform(0.8, 1.1), ink)
            else:
                tree_pine(c, tx, y - 2, r.uniform(1.0, 1.3), "#5f9a92", "#3f736e", ink, WHITE, 1.6)
    far_isle(ctx, 560, h * 0.38, 0.36, 250, 140, pal, 61, "#b9cbe4", 0.45, decor, ink=ink)
    far_isle(ctx, 1290, h * 0.34, 0.44, 300, 160, pal, 65, "#b9cbe4", 0.4, decor, ink=ink)
    far_isle(ctx, 120, h * 0.46, 0.26, 180, 100, pal, 63, "#c3d3e8", 0.5, decor, ink=ink)
    mist(ctx, w, h * 0.58, 70, "#cddbee", 0.6, 91)
    mid = ridge_pts(w, h * 0.7, 150, seed * 37, 3.0, sharp=True)
    faceted(ctx, w, h, mid, "#8fa6cf", "#647aaa", h * 0.7, 37, light=-1, snow=h * 0.7 - 110, snow_shade=True,
            rim="#ffffff", haze="#d2def0", gullies=("#7488b8", 0.5))
    forest_band(ctx, [(x, ridge_y(mid, x) + 60) for x in range(-20, w + 20, 8)], 93, "#5b7f98", "#435f7d", "#cfe3f2",
                0.7, 10, kind="pine", alpha=0.75, snow="#eef6fb")
    mist(ctx, w, h * 0.77, 70, "#e6eef7", 0.7, 95)
    # frozen lake with moonlit glints
    lake(ctx, w, h * 0.86, h, "#c6dcec", "#7fa3c4", WHITE, 97)
    for (x, s) in ((560, 0.7), (1480, 0.55), (60, 0.5)):
        iceberg(ctx, x, h * 0.92, s)
    r = Rand(12)
    for _ in range(150):
        x, y = r.uniform(0, w), r.uniform(0, h)
        fill(ctx, lambda c, x=x, y=y, s=r.uniform(1.2, 3.0): circle(c, x, y, s), WHITE, r.uniform(0.35, 0.8))


def scene_volcano(ctx, w=W, h=H, seed=4):
    sky(ctx, w, h, [(0, "#241c3c"), (0.36, "#552a48"), (0.68, "#b9503f"), (1, "#f39a5c")])
    r = Rand(4)
    for _ in range(80):
        x, y = r.uniform(0, w), r.uniform(0, h * 0.35)
        fill(ctx, lambda c, x=x, y=y, s=r.uniform(0.7, 1.8): circle(c, x, y, s), "#ffe9c9", r.uniform(0.3, 0.8))
    glow(ctx, w * 0.62, h * 0.5, w * 0.55, "#ff7a3d", 0.55)
    cloud_bank(ctx, w, h * 0.2, 36, "#6a3c55", "#4a2a44", 0.4, 77, lit="#c2604f")
    # ash plume: one billowing mass, under-lit by the crater
    pr = Rand(71)
    puffs = []
    for k in range(28):
        u = k / 27
        px = w * 0.62 + u * 400 + math.sin(u * 5) * 30 + pr.jit(30)
        py = h * 0.33 - u * 340 + pr.jit(20)
        rr = 28 + u * 95 * pr.uniform(0.7, 1.1)
        puffs.append((px, py, rr))
    for (px, py, rr) in puffs:
        fill(ctx, lambda c, a=(px, py, rr): circle(c, *a), "#3a2537")
    for (px, py, rr) in puffs:
        fill(ctx, lambda c, a=(px, py, rr): circle(c, a[0] - a[2] * 0.12, a[1] - a[2] * 0.18, a[2] * 0.82), "#533a4f")
    for (px, py, rr) in puffs[::2]:
        fill(ctx, lambda c, a=(px, py, rr): circle(c, a[0] - a[2] * 0.3, a[1] - a[2] * 0.36, a[2] * 0.4), "#6f566a", 0.8)
    ctx.save()
    ctx.new_path()
    for (px, py, rr) in puffs:
        circle(ctx, px, py, rr)
    ctx.clip()
    ctx.set_source(rad_grad(w * 0.62, h * 0.36, 0, 260, [(0, "#ff7a3d", 0.55), (1, "#ff7a3d", 0.0)]))
    ctx.paint()
    ctx.restore()
    far = ridge_pts(w, h * 0.64, 170, seed * 41, 3.6, sharp=True)
    faceted(ctx, w, h, far, "#7a4057", "#5a2d46", h * 0.64, 41, light=1, rim="#d0644f", haze="#c2513f", haze_top=0.1,
            gullies=("#ff8a3d", 0.25))
    volcano(ctx, w * 0.62, h * 0.36, w, h)
    pal = dict(top="#5a4650", top_dark="#3d2d36", rock="#4c3a44", rock_dark="#2e2129", rock_light="#6a525e",
               root="#ff8a3d")
    ink = "#3a2632"

    def decor(c, x, y, ww, r):
        for i in range(max(1, int(ww / 70))):
            tx = x - ww * 0.35 + ww * 0.7 * (i + 0.5) / max(1, int(ww / 70)) + r.jit(10)
            rock_spire(c, tx, y - 2, r.uniform(0.8, 1.2), "#5a4650", "#2e2129", ink)
        for i in range(3):
            fx = x + r.uniform(-ww * 0.35, ww * 0.35)
            stroke(c, lambda cc, fx=fx: (cc.move_to(fx, y + 4), cc.line_to(fx + 6, y + 18), cc.line_to(fx + 2, y + 30)),
                   "#ffb347", 2.4, 0.9)
    far_isle(ctx, 250, h * 0.46, 0.42, 260, 150, pal, 81, "#a84c58", 0.45, decor, ink=ink)
    far_isle(ctx, 1460, h * 0.49, 0.36, 280, 160, pal, 85, "#b0505a", 0.48, decor, ink=ink)
    far_isle(ctx, 520, h * 0.55, 0.24, 170, 100, pal, 83, "#b8575a", 0.52, decor, ink=ink)
    mist(ctx, w, h * 0.66, 70, "#e0704a", 0.45, 101)
    # mid basalt ridge with molten rims and a lava fall
    mid = ridge_pts(w, h * 0.78, 90, seed * 43, 2.6, sharp=True)
    faceted(ctx, w, h, mid, "#8a4a4c", "#6a3644", h * 0.78, 43, light=1, rim="#ff9a52", rim_w=2.6, haze="#e0784e",
            haze_top=0.25)
    for lx in (330, 1180):
        ly = ridge_y(mid, lx)
        for wd, col, al in ((22, "#ff7a3d", 0.25), (9, "#ff8a3d", 0.85), (3.4, "#ffd35c", 1.0)):
            stroke(ctx, lambda c, lx=lx, ly=ly: smooth(c, [(lx, ly + 2), (lx + 6, ly + 30), (lx + 2, ly + 62),
                                                            (lx + 7, ly + 92)], False, 0.5), col, wd, al)
        glow(ctx, lx + 7, ly + 96, 70, "#ffb347", 0.45)
        fill(ctx, lambda c, lx=lx, ly=ly: ellipse(c, lx + 7, ly + 96, 26, 6), "#ffd35c", 0.85)
    # glowing lava-lit haze across the lower band keeps dark basalt terrain readable
    ctx.set_source(lin_grad(0, h * 0.7, 0, h, [(0, "#f08a50", 0.0), (0.6, "#f6a065", 0.55), (1, "#f9b77a", 0.75)]))
    ctx.paint()
    sea(ctx, w, h, "#ff8a3d", "#c2412f", h * 0.93)
    r = Rand(5)
    for _ in range(90):
        x, y = r.uniform(0, w), r.uniform(h * 0.15, h)
        fill(ctx, lambda c, x=x, y=y, s=r.uniform(1.2, 3.2): circle(c, x, y, s), r.choice(["#ffb347", "#ffd35c", "#ff7a3d"]),
             r.uniform(0.5, 0.95))


# --------------------------------------------------------------------------
# Menu illustration
# --------------------------------------------------------------------------

def bazooka(ctx, x, y, ang, s):
    ctx.save()
    ctx.translate(x, y)
    ctx.rotate(ang)
    ctx.scale(s, s)
    tube = lambda c: rrect(c, -30, -8, 72, 16, 6)
    inked(ctx, tube, "#4f8f86", 2.6)
    ctx.save()
    clip_to(ctx, tube)
    fill(ctx, lambda c: c.rectangle(-32, 2, 80, 8), "#356a66", 0.8)
    for bx in (-22, 22):
        fill(ctx, lambda c, bx=bx: c.rectangle(bx, -9, 6, 18), ORANGE)
    ctx.restore()
    stroke(ctx, tube, INK, 2.6)
    inked(ctx, lambda c: rrect(c, 38, -10.5, 9, 21, 3), "#356a66", 2.6)
    inked(ctx, lambda c: rrect(c, -36, -10, 8, 20, 3), "#356a66", 2.6)
    inked(ctx, lambda c: rrect(c, 2, -17, 14, 9, 2.5), "#c9d6d8", 2.2)
    fill(ctx, lambda c: circle(c, 13, -12.5, 2), "#86d6d3")
    inked(ctx, lambda c: rrect(c, -6, 6, 8, 14, 2.5), "#8e5a33", 2.4)
    fill(ctx, lambda c: rrect(c, -24, -6, 50, 3, 1.5), WHITE, 0.35)
    ctx.restore()


def menu(ctx, w=1440, h=900):
    from build_art_grubs import Pose, draw_grub
    from build_art_icons import ICONS
    from build_art_props import crate, explosion

    sky(ctx, w, h, [(0, "#2e5f68"), (0.45, "#5ea4ab"), (0.8, "#bfe0d6"), (1, "#f7f2e6")])
    # warm the sky toward the paper panel so the fade reads as morning haze, not grey fog
    ctx.set_source(lin_grad(PANEL_SOLID - 100, 0, 1000, 0, [(0, "#f1e6cf", 0.95), (0.4, "#dfe2cf", 0.6),
                                                             (1, "#dfe2cf", 0)]))
    ctx.paint()
    glow(ctx, w * 0.8, h * 0.18, 700, "#ffe7a8", 0.75)
    # soft light rays from the upper right
    for k in range(9):
        a = 2.0 + k * 0.13
        fill(ctx, lambda c, a=a: poly(c, [(w * 0.8, h * 0.18), (w * 0.8 + math.cos(a) * 2000, h * 0.18 + math.sin(a) * 2000),
                                          (w * 0.8 + math.cos(a + 0.05) * 2000, h * 0.18 + math.sin(a + 0.05) * 2000)]),
             WHITE, 0.05)
    # faint mountains behind the diorama
    far = ridge_pts(w, h * 0.72, 220, 501, 3.2, sharp=True)
    ridge(ctx, w, h, far, "#7fb3b4", rim="#bfe0dc", shade="#6a9fa4", snow=(h * 0.72 - 170, "#e3f2ee"), haze="#cfe8e0")
    mid = ridge_pts(w, h * 0.84, 110, 503, 2.4)
    ridge(ctx, w, h, mid, "#6fa894", rim="#a7d3b4", shade="#5c957f", haze="#d8ecdf")
    for (cx, cy, cw, ch, sd, a) in ((560, 250, 300, 80, 5, 0.6), (980, 70, 280, 80, 9, 0.85)):
        soft_cloud(ctx, cx, cy, cw, ch, sd, WHITE, "#d6ebee", "#8fbfc4", a, 2.4)
    # left: warm ivory title panel that dissolves into the scene by x ~720
    ivory_panel(ctx, w, h)
    # rocket trail across the sky toward an explosion
    trail = [(1178, 472), (1192, 390), (1188, 300), (1196, 225), (1210, 165)]
    for k, (wd, col, a) in enumerate(((26, WHITE, 0.35), (14, WHITE, 0.7))):
        stroke(ctx, lambda c, wd=wd: smooth(c, trail, False, 0.5), col, wd, a)
    r = Rand(3)
    for i, (px, py) in enumerate(trail[:-1]):
        soft_cloud(ctx, px - 30, py - 20, 60, 34, 300 + i, "#f5f1e8", "#d9d2c4", None, 0.8 - i * 0.12)
    ctx.save()
    ctx.translate(1290 - 80 * 1.6, 130 - 80 * 1.6)
    ctx.scale(1.6, 1.6)
    explosion(ctx, 3)
    ctx.restore()
    ctx.save()
    ctx.translate(1205, 160)
    ctx.rotate(-0.3)
    ctx.scale(1.6, 1.6)
    ctx.translate(-32, -32)
    ICONS["rocket"](ctx)
    ctx.restore()
    # main floating island diorama (right side)
    big = dict(top="#8ccf6e", top_dark="#5f9e4f", rock="#c08d62", rock_dark="#7f5a43", rock_light="#ddb084",
               root="#6b4a35")
    def deco_main(c, x, y, ww, r):
        tree_round(c, x + ww * 0.38, y - 6, 2.2, "#7cc278", "#4f9a5c", "#7a5a40", INK, 3.0)
        for k in range(14):
            fx = x + r.uniform(-ww * 0.45, ww * 0.45)
            fill(c, lambda cc, fx=fx: circle(cc, fx, y - 6 + r.jit(3), 4), r.choice(["#ffd35c", "#ff8fa3", WHITE]))
    island(ctx, 1050, h * 0.79, 760, 260, big, 99, INK, 3.4, deco_main, falls=[(0.62, 240)])
    gy = h * 0.79 - 14  # ground line on the island
    # burrow hole with a peeking grub
    fill(ctx, lambda c: ellipse(c, 760, gy + 10, 70, 18), "#3d2a22")
    # crate with parachute coming down
    ctx.save()
    ctx.translate(1350, 330)
    ctx.scale(1.4, 1.4)
    chute = lambda c: (c.move_to(-40, 0), c.curve_to(-40, -50, 40, -50, 40, 0), c.curve_to(30, -8, 20, -8, 13, 0),
                       c.curve_to(6, -8, -6, -8, -13, 0), c.curve_to(-20, -8, -30, -8, -40, 0), c.close_path())
    inked(ctx, chute, PAPER, 2.4)
    ctx.save()
    clip_to(ctx, chute)
    fill(ctx, lambda c: poly(c, [(-13, 0), (-6, -60), (6, -60), (13, 0)]), ORANGE)
    ctx.restore()
    stroke(ctx, chute, INK, 2.4)
    for sx in (-40, -13, 13, 40):
        stroke(ctx, lambda c, sx=sx: (c.move_to(sx, 0), c.line_to(sx * 0.3, 44)), INK, 1.4)
    ctx.translate(-32, 36)
    crate(ctx)
    ctx.restore()

    def put_grub(pose, team, x, y, s, flip=False):
        ctx.save()
        ctx.translate(x, y)
        ctx.scale(-s if flip else s, s)
        ctx.translate(-40, -68)
        draw_grub(ctx, pose, team, lw=2.2)
        ctx.restore()

    base = [(11.5, 61.2), (21.5, 62.4), (31.5, 59.0), (40.5, 53.8), (44.5, 46.0), (45.4, 39.5), (45.8, 31.0)]
    radii = [2.6, 6.0, 9.4, 10.8, 10.4, 9.8, 15.0]
    # hero with bazooka (team 0), aiming up-right
    hero = Pose(base, radii, look=(0.55, -0.6), brow=0.9, mouth="grit", low_lid=0.15, scarf_phase=1.2)
    put_grub(hero, 0, 1010, gy + 6, 4.4)
    bazooka(ctx, 1128, gy - 140, -1.05, 2.2)
    # cheering grub jumping (team 2)
    cheer = Pose([(37.0, 52.0), (31.5, 60.0), (37.0, 66.0), (45.5, 62.0), (48.5, 53.5), (48.2, 45.5), (47.0, 35.5)],
                 [2.6, 6.0, 9.0, 10.4, 10.4, 9.8, 15.0], eyes="happy", mouth="cheer", scarf_phase=2.2,
                 scarf_lift=0.4, blush=0.6, rot=-8)
    put_grub(cheer, 2, 1305, gy - 60, 3.4)
    # worried grub peeking from the burrow (team 1), facing left toward the viewer side
    peek = Pose([(40.0, 74.0), (41.0, 68.0), (42.0, 62.0), (43.0, 55.0), (44.5, 48.0), (45.4, 41.0), (45.8, 32.0)],
                [8, 9, 9.6, 10.2, 10.2, 9.8, 15.0], look=(0.2, -0.7), eyes="wide", mouth="o", brow=-0.8,
                brow_lift=1.5, scarf_phase=0.4)
    ctx.save()
    clip_to(ctx, lambda c: c.rectangle(600, 0, 400, gy + 12))
    put_grub(peek, 1, 760, gy + 8, 3.2, flip=True)
    ctx.restore()
    stroke(ctx, lambda c: (c.move_to(690, gy + 12), c.curve_to(730, gy + 26, 790, gy + 26, 830, gy + 12)), INK, 4)
    # parachuting grub (team 4) drifting in
    ctx.save()
    ctx.translate(780, 210)
    ctx.rotate(-0.12)
    ch = lambda c: (c.move_to(-90, 0), c.curve_to(-90, -110, 90, -110, 90, 0), c.curve_to(70, -14, 50, -14, 30, 0),
                    c.curve_to(10, -14, -10, -14, -30, 0), c.curve_to(-50, -14, -70, -14, -90, 0), c.close_path())
    inked(ctx, ch, "#82b67f", 3)
    ctx.save()
    clip_to(ctx, ch)
    for sx in (-60, 0, 60):
        fill(ctx, lambda c, sx=sx: poly(c, [(sx - 14, 0), (sx * 0.4 - 5, -120), (sx * 0.4 + 5, -120), (sx + 14, 0)]), PAPER)
    fill(ctx, lambda c: c.rectangle(-100, -20, 200, 30), "#4f8a4a", 0.35)
    ctx.restore()
    stroke(ctx, ch, INK, 3)
    for sx in (-90, -30, 30, 90):
        stroke(ctx, lambda c, sx=sx: (c.move_to(sx, 0), c.line_to(sx * 0.15, 120)), INK, 1.8)
    ctx.restore()
    para = Pose([(41.0, 67.5), (42.0, 61.5), (42.6, 55.0), (43.6, 48.0), (45.0, 41.0), (46.0, 36.5), (46.2, 29.5)],
                [2.4, 5.6, 8.0, 9.2, 9.6, 9.2, 14.4], look=(0.6, 0.4), mouth="smile", scarf_lift=0.8, scarf_phase=3.0)
    put_grub(para, 4, 790, 420, 2.6)
    # sheep charging (bonus mischief)
    from build_art_icons import sheep
    sheep(ctx, 872, gy - 34, 2.6)
    for k in range(3):
        stroke(ctx, lambda c, k=k: (c.move_to(818 - k * 8, gy - 56 + k * 16), c.line_to(845 - k * 8, gy - 56 + k * 16)),
               INK, 3, 0.6)
    # team flags planted on the island
    for i, (fx, team) in enumerate(((1395, 5),)):
        stroke(ctx, lambda c, fx=fx: (c.move_to(fx, gy + 6), c.line_to(fx, gy - 120)), INK, 6)
        stroke(ctx, lambda c, fx=fx: (c.move_to(fx, gy + 6), c.line_to(fx, gy - 120)), "#c98a4f", 3)
        from build_art_core import TEAMS
        flag = lambda c, fx=fx: (c.move_to(fx, gy - 118), c.curve_to(fx + 30, gy - 128, fx + 40, gy - 100, fx + 70, gy - 108),
                                 c.line_to(fx + 62, gy - 88), c.line_to(fx + 70, gy - 70),
                                 c.curve_to(fx + 40, gy - 62, fx + 30, gy - 90, fx, gy - 80), c.close_path())
        inked(ctx, flag, TEAMS[team], 3)
        fill(ctx, lambda c, fx=fx: circle(c, fx, gy - 122, 5), GOLD)
    # foreground mist along the bottom edge
    ctx.set_source(lin_grad(0, h * 0.82, 0, h, [(0, "#f7f2e6", 0), (1, "#f7f2e6", 0.85)]))
    ctx.paint()


PANEL_SOLID, PANEL_CLEAR = 540, 720


def ivory_panel(ctx, w, h):
    """Warm paper panel for the title and menu (ink #182d35 / muted #637579 text).

    Solid ivory over x 0..PANEL_SOLID, then an eased fade (with a soft,
    cloud-like scalloped edge) that is fully clear by PANEL_CLEAR, so the crew
    diorama stays crisp.  Decoration inside the panel is kept within a few
    levels of the paper so text contrast is unaffected.
    """
    def eased(x0, x1, n=12):
        stops = []
        for i in range(n + 1):
            u = i / n
            stops.append(((x0 + (x1 - x0) * u) / w, 1 - u * u * (3 - 2 * u)))
        return stops

    paper_top, paper_bot = "#fbf7ee", "#f7f1e3"
    ctx.push_group()
    # vertical paper gradient (slightly warmer toward the bottom)
    ctx.set_source(lin_grad(0, 0, 0, h, [(0, paper_top), (0.55, "#f9f4e9"), (1, paper_bot)]))
    ctx.paint()
    # very faint contour lines, like a field map of the islands
    for k in range(7):
        cy = 640 + k * 44
        pts = [(x, cy + 26 * math.sin(x / 210 + k * 0.7) + 14 * math.sin(x / 83 + k * 1.9)) for x in range(-20, 760, 20)]
        stroke(ctx, lambda c, pts=pts: smooth(c, pts, False, 0.5), "#e6dac2", 1.4, 0.5)
    for k in range(4):
        rr = 60 + k * 34
        stroke(ctx, lambda c, rr=rr: ellipse(c, 520, 900, rr * 1.5, rr), "#e6dac2", 1.2, 0.4)
    # warm sun-wash behind the title
    ctx.set_source(rad_grad(260, 230, 0, 420, [(0, "#fff9ee", 0.9), (1, "#fff9ee", 0)]))
    ctx.paint()
    group = ctx.pop_group()
    # mask: solid to PANEL_SOLID, eased fade to PANEL_CLEAR, plus scalloped puffs on the edge
    ctx.push_group()
    ctx.set_source(lin_grad(0, 0, w, 0, [(0, "#000000", 1.0)] + [(o, "#000000", a) for o, a in eased(PANEL_SOLID, PANEL_CLEAR)]))
    ctx.paint()
    r = Rand(540)
    y = -40
    while y < h + 60:
        rr = r.uniform(70, 120)
        cx = PANEL_SOLID + r.uniform(10, 55)
        ctx.set_source(rad_grad(cx, y, 0, rr, [(0, "#000000", 0.85), (0.6, "#000000", 0.45), (1, "#000000", 0)]))
        ctx.paint()
        y += rr * 0.9
    mask = ctx.pop_group()
    ctx.set_source(group)
    ctx.mask(mask)
    # a soft warm halo where paper meets sky, so the edge never looks like a seam
    ctx.set_source(lin_grad(PANEL_SOLID - 40, 0, PANEL_CLEAR + 60, 0,
                            [(0, "#fff4dc", 0), (0.45, "#fff4dc", 0.18), (1, "#fff4dc", 0)]))
    ctx.paint()


# --------------------------------------------------------------------------

def grain_noise(size, seed, spread=12):
    """Seeded grey paper grain centred on mid-grey (uniform, +/- spread levels).

    Seeded from the asset name, so every rebuild is byte-for-byte identical.
    """
    w, h = size
    r = Rand(zlib.crc32(seed.encode()))
    noise = Image.frombytes("L", size, r.randbytes(w * h))
    return noise.point(lambda v: round(128 + (v - 127.5) * spread / 127.5)).convert("RGB")


def mottle(size, seed, cells=(14, 7), strength=26):
    """Seeded low-frequency mottling (soft 'paint' variation), grey-centred."""
    w, h = size
    r = Rand(zlib.crc32(seed.encode()) ^ 0x5EED)
    cw, ch = cells
    small = Image.frombytes("L", (cw, ch), r.randbytes(cw * ch)).resize((w, h), Image.BICUBIC)
    streak = Image.frombytes("L", (12, 90), r.randbytes(12 * 90)).resize((w, h), Image.BICUBIC)
    mixed = Image.blend(small, streak, 0.35)
    return mixed.point(lambda v: round(128 + (v - 127.5) * strength / 127.5)).convert("RGB")


def _post(path, name):
    base = Image.open(path).convert("RGB")
    if name.startswith("sky-"):
        # painterly pass: broad soft tonal variation like layered gouache washes
        base = ImageChops.soft_light(base, mottle(base.size, name))
    im = ImageChops.soft_light(base, grain_noise(base.size, name))
    Image.blend(base, im, 0.4).save(path, optimize=True)


def _render(name, w, h, fn):
    s, ctx = surface(w, h)
    fn(ctx)
    path = ART / f"{name}.png"
    s.write_to_png(str(path))
    _post(path, name)


def build_all():
    _render("sky-meadow", W, H, scene_meadow)
    _render("sky-desert", W, H, scene_desert)
    _render("sky-glacier", W, H, scene_glacier)
    _render("sky-volcano", W, H, scene_volcano)
    _render("menu-bg", 1440, 900, menu)
    return {}
