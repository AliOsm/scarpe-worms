"""Shared drawing helpers for the BURROW BRIGADE art pipeline.

Foreground vectors are drawn with cairo (via cairocffi). Painted backgrounds
and materials compile from reviewed local masters; builds need no downloads.
"""
from __future__ import annotations

import math
import os
import random
from pathlib import Path

import cairocffi as cairo

ROOT = Path(__file__).resolve().parent.parent
ART = ROOT / "assets" / "art"

# --- Brand palette -------------------------------------------------------
INK = "#182d35"
PAPER = "#f7f2e6"
ORANGE = "#f57c49"
TEAL = "#407d80"
GOLD = "#edc16d"

TEAMS = ["#ef765e", "#61bdba", "#edc56a", "#ac98cf", "#82b67f", "#7faade"]
TEAM_NAMES = ["coral", "lagoon", "mustard", "lilac", "clover", "sky"]

# Grub skin (pink/peach)
SKIN = "#f9ab98"
SKIN_SHADE = "#e07f86"
SKIN_DEEP = "#c8607a"
SKIN_LIGHT = "#ffd5c2"
BELLY = "#ffc9a6"
BLUSH = "#ff6f86"

STEEL = "#8fa3ab"
STEEL_DARK = "#5d7480"
STEEL_LIGHT = "#d5e0e2"
RED = "#e2524a"
RED_DARK = "#a83a3f"
WOOD = "#c98a4f"
WOOD_DARK = "#8e5a33"
GREEN = "#7dbb6a"
GREEN_DARK = "#4f8a4a"
PURPLE = "#8f74c4"
BLUE = "#5aa3d9"
WHITE = "#fffdf7"


def rgb(hexstr: str, alpha: float = 1.0):
    h = hexstr.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return (r, g, b, alpha)


def mix(a: str, b: str, t: float) -> str:
    ra, ga, ba, _ = rgb(a)
    rb, gb, bb, _ = rgb(b)
    r = ra + (rb - ra) * t
    g = ga + (gb - ga) * t
    bl = ba + (bb - ba) * t
    return "#%02x%02x%02x" % (round(r * 255), round(g * 255), round(bl * 255))


def darken(c: str, t: float = 0.25) -> str:
    return mix(c, INK, t)


def lighten(c: str, t: float = 0.35) -> str:
    return mix(c, WHITE, t)


def src(ctx, color, alpha: float = 1.0):
    if isinstance(color, str):
        ctx.set_source_rgba(*rgb(color, alpha))
    else:
        ctx.set_source_rgba(*color)


# --- Surfaces ------------------------------------------------------------

def surface(w: int, h: int):
    s = cairo.ImageSurface(cairo.FORMAT_ARGB32, w, h)
    ctx = cairo.Context(s)
    ctx.set_line_join(cairo.LINE_JOIN_ROUND)
    ctx.set_line_cap(cairo.LINE_CAP_ROUND)
    return s, ctx


def svg_surface(path: Path, w: int, h: int):
    path.parent.mkdir(parents=True, exist_ok=True)
    s = cairo.SVGSurface(str(path), w, h)
    ctx = cairo.Context(s)
    ctx.set_line_join(cairo.LINE_JOIN_ROUND)
    ctx.set_line_cap(cairo.LINE_CAP_ROUND)
    return s, ctx


def save(s, path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    s.flush()
    s.write_to_png(str(path))


def render(path: Path, w: int, h: int, draw, svg: Path | None = None):
    s, ctx = surface(w, h)
    draw(ctx)
    save(s, path)
    if svg is not None:
        vs, vctx = svg_surface(svg, w, h)
        draw(vctx)
        vs.finish()
    return path


# --- Path helpers --------------------------------------------------------

def rrect(ctx, x, y, w, h, r):
    r = min(r, w / 2, h / 2)
    ctx.new_sub_path()
    ctx.arc(x + w - r, y + r, r, -math.pi / 2, 0)
    ctx.arc(x + w - r, y + h - r, r, 0, math.pi / 2)
    ctx.arc(x + r, y + h - r, r, math.pi / 2, math.pi)
    ctx.arc(x + r, y + r, r, math.pi, 3 * math.pi / 2)
    ctx.close_path()


def ellipse(ctx, cx, cy, rx, ry, rot=0.0):
    ctx.save()
    ctx.translate(cx, cy)
    ctx.rotate(rot)
    ctx.scale(rx, ry)
    ctx.new_sub_path()
    ctx.arc(0, 0, 1, 0, 2 * math.pi)
    ctx.restore()


def circle(ctx, cx, cy, r):
    ctx.new_sub_path()
    ctx.arc(cx, cy, r, 0, 2 * math.pi)


def poly(ctx, pts, close=True):
    ctx.move_to(*pts[0])
    for p in pts[1:]:
        ctx.line_to(*p)
    if close:
        ctx.close_path()


def smooth(ctx, pts, close=True, tension=0.5):
    """Catmull-Rom spline through points, emitted as cubic beziers."""
    n = len(pts)
    if n < 3:
        poly(ctx, pts, close)
        return
    ctx.move_to(*pts[0])
    rng = range(n) if close else range(n - 1)
    for i in rng:
        p0 = pts[(i - 1) % n] if (close or i > 0) else pts[i]
        p1 = pts[i]
        p2 = pts[(i + 1) % n]
        p3 = pts[(i + 2) % n] if (close or i + 2 < n) else pts[(i + 1) % n]
        t = tension / 3 * 2
        c1 = (p1[0] + (p2[0] - p0[0]) * t / 2, p1[1] + (p2[1] - p0[1]) * t / 2)
        c2 = (p2[0] - (p3[0] - p1[0]) * t / 2, p2[1] - (p3[1] - p1[1]) * t / 2)
        ctx.curve_to(*c1, *c2, *p2)
    if close:
        ctx.close_path()


def star_pts(cx, cy, r1, r2, n=5, rot=-math.pi / 2):
    pts = []
    for i in range(n * 2):
        r = r1 if i % 2 == 0 else r2
        a = rot + i * math.pi / n
        pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    return pts


# --- Styled drawing ------------------------------------------------------

def inked(ctx, path_fn, fill, lw=3.0, ink=INK, alpha=1.0):
    """Fill a path and give it a chunky ink outline."""
    ctx.new_path()
    path_fn(ctx)
    if fill is not None:
        src(ctx, fill, alpha)
        ctx.fill_preserve()
    if lw > 0:
        src(ctx, ink)
        ctx.set_line_width(lw)
        ctx.stroke()
    else:
        ctx.new_path()


def outline_pass(ctx, path_fns, lw=3.0, ink=INK):
    """Draw a unified outline behind several overlapping shapes."""
    for fn in path_fns:
        ctx.new_path()
        fn(ctx)
        src(ctx, ink)
        ctx.set_line_width(lw * 2)
        ctx.stroke_preserve()
        ctx.fill()


def fill(ctx, path_fn, color, alpha=1.0):
    ctx.new_path()
    path_fn(ctx)
    src(ctx, color, alpha)
    ctx.fill()


def stroke(ctx, path_fn, color, lw, alpha=1.0):
    ctx.new_path()
    path_fn(ctx)
    src(ctx, color, alpha)
    ctx.set_line_width(lw)
    ctx.stroke()


def clip_to(ctx, path_fn):
    ctx.new_path()
    path_fn(ctx)
    ctx.clip()


def lin_grad(x0, y0, x1, y1, stops):
    g = cairo.LinearGradient(x0, y0, x1, y1)
    for off, col, *a in stops:
        g.add_color_stop_rgba(off, *rgb(col, a[0] if a else 1.0))
    return g


def rad_grad(cx, cy, r0, r1, stops, fx=None, fy=None):
    g = cairo.RadialGradient(fx if fx is not None else cx, fy if fy is not None else cy, r0, cx, cy, r1)
    for off, col, *a in stops:
        g.add_color_stop_rgba(off, *rgb(col, a[0] if a else 1.0))
    return g


def sparkle(ctx, cx, cy, r, color=GOLD, lw=1.6, ink=INK):
    """Four-point twinkle star with ink outline."""
    pts = []
    for i in range(8):
        rr = r if i % 2 == 0 else r * 0.32
        a = -math.pi / 2 + i * math.pi / 4
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
    inked(ctx, lambda c: poly(c, pts), color, lw, ink)


def shine(ctx, x, y, w, h, rot=-0.6, alpha=0.85):
    """Small glossy highlight capsule."""
    ctx.save()
    ctx.translate(x, y)
    ctx.rotate(rot)
    rrect(ctx, -w / 2, -h / 2, w, h, h / 2)
    src(ctx, WHITE, alpha)
    ctx.fill()
    ctx.restore()


class Rand(random.Random):
    def __init__(self, seed):
        super().__init__(seed)

    def jit(self, a):
        return self.uniform(-a, a)


def fbm1d(seed, octaves=5, base_freq=1.0):
    """Returns f(x)->[-1,1] smooth 1D fractal value noise built from sines."""
    r = random.Random(seed)
    waves = []
    amp, freq, total = 1.0, base_freq, 0.0
    for _ in range(octaves):
        for _k in range(2):
            waves.append((amp / 2, freq * r.uniform(0.8, 1.25), r.uniform(0, math.tau)))
        total += amp
        amp *= 0.5
        freq *= 2.03
    def f(x):
        return sum(a * math.sin(x * fr + ph) for a, fr, ph in waves) / total
    return f


def ensure_dirs():
    for d in ("grubs", "grubs/left", "weapons", "src"):
        (ART / d).mkdir(parents=True, exist_ok=True)


def rel(p: Path) -> str:
    return os.path.relpath(p, ART)
