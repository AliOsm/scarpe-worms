"""Grub characters: pose model, rendering and the animation sets.

A grub is a soft larva drawn as a variable-radius tube along a spline
"spine" (tail tip -> head centre).  The head end carries the face, team
headgear and a neck scarf, all drawn in local frames that follow the spine,
so every pose stays on-model.  Coordinates are in an 80x80 sprite space with
feet anchored at (40, 68); the same code scales up for the menu art.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field, replace

from build_art_core import (
    BLUSH, BELLY, GOLD, INK, PAPER, SKIN, SKIN_DEEP, SKIN_LIGHT, SKIN_SHADE,
    STEEL_DARK, TEAL, TEAMS, WHITE, circle, clip_to, darken, ellipse, fill,
    inked, lighten, lin_grad, mix, outline_pass, poly, rad_grad, rrect, smooth, sparkle, src,
    stroke,
)

ANCHOR = (40.0, 68.0)
NECK_T = 0.70
GROUND_LIFT = 2.0  # sprite-space lift so the ink outline sits on the anchor line
SPRITE_SCALE = 0.88
LW = 2.7  # sprite outline width (in 80px sprite units)
MOUTH_DARK = "#5b2235"
TONGUE = "#ff8a98"


# --------------------------------------------------------------------------
# Pose model
# --------------------------------------------------------------------------

@dataclass
class Pose:
    pts: list            # spine control points, tail tip -> head centre
    radii: list          # radius at each control point
    look: tuple = (0.45, 0.05)
    lid: float = 0.0          # 0 open .. 1 closed (upper lid)
    low_lid: float = 0.0      # lower lid (happy squint)
    eyes: str = "normal"      # normal | happy | x | squeeze | swirl | wide
    pupil: float = 1.0        # pupil scale
    brow: float = 0.0         # -1 worried .. 0 neutral .. 1 determined
    brow_lift: float = 0.0
    mouth: str = "smile"      # smile | grin | o | grit | wavy | tongue | flat | cheer
    sx: float = 1.0
    sy: float = 1.0
    rot: float = 0.0          # degrees about anchor
    dx: float = 0.0
    dy: float = 0.0
    scarf_phase: float = 0.0
    scarf_lift: float = 0.0   # tails blown upward (falling)
    prop: float = 0.0         # propeller angle for team 4
    extras: list = field(default_factory=list)
    belly_up: bool = False
    head_angle: float | None = None  # override head rotation (radians, 0 = upright)
    tails: bool = True
    blush: float = 0.45
    shadow: float = 0.0       # soft contact shadow strength (grounded poses only)


# --------------------------------------------------------------------------
# Spine sampling
# --------------------------------------------------------------------------

def _cr(p0, p1, p2, p3, t):
    t2, t3 = t * t, t * t * t
    return tuple(
        0.5 * ((2 * p1[i]) + (-p0[i] + p2[i]) * t + (2 * p0[i] - 5 * p1[i] + 4 * p2[i] - p3[i]) * t2
               + (-p0[i] + 3 * p1[i] - 3 * p2[i] + p3[i]) * t3)
        for i in range(2)
    )


def sample_spine(pts, radii, per=24):
    n = len(pts)
    ext = [(2 * pts[0][0] - pts[1][0], 2 * pts[0][1] - pts[1][1])] + list(pts) + \
          [(2 * pts[-1][0] - pts[-2][0], 2 * pts[-1][1] - pts[-2][1])]
    out = []
    for i in range(n - 1):
        for k in range(per):
            t = k / per
            p = _cr(ext[i], ext[i + 1], ext[i + 2], ext[i + 3], t)
            ts = t * t * (3 - 2 * t)
            r = radii[i] + (radii[i + 1] - radii[i]) * ts
            out.append((p[0], p[1], r))
    out.append((pts[-1][0], pts[-1][1], radii[-1]))
    # tangents / normals
    res = []
    for i, (x, y, r) in enumerate(out):
        a = out[max(i - 1, 0)]
        b = out[min(i + 1, len(out) - 1)]
        tx, ty = b[0] - a[0], b[1] - a[1]
        l = math.hypot(tx, ty) or 1.0
        tx, ty = tx / l, ty / l
        res.append((x, y, r, tx, ty, -ty, tx))  # x y r tangent normal(front)
    return res


def tube_path(samples, grow=0.0, shift=(0.0, 0.0), scale=1.0, t0=0.0, t1=1.0, off=0.0):
    n = len(samples)
    i0, i1 = int(t0 * (n - 1)), int(t1 * (n - 1))

    def fn(ctx):
        for i in range(i0, i1 + 1):
            x, y, r, tx, ty, nx, ny = samples[i]
            circle(ctx, x + shift[0] + nx * r * off, y + shift[1] + ny * r * off, max(r * scale + grow, 0.3))
    return fn


def spine_at(samples, t):
    i = max(0, min(len(samples) - 1, int(round(t * (len(samples) - 1)))))
    return samples[i]


# --------------------------------------------------------------------------
# Parts
# --------------------------------------------------------------------------

def _local(ctx, s, scale=1.0, angle=None):
    x, y, r, tx, ty, nx, ny = s
    ctx.translate(x, y)
    ctx.rotate(math.atan2(ty, tx) + math.pi / 2 if angle is None else angle)
    ctx.scale(scale, scale)


def draw_scarf_tails(ctx, pose, samples, team, lw):
    col = TEAMS[team]
    neck = spine_at(samples, NECK_T)
    r = neck[2]
    ctx.save()
    _local(ctx, neck)
    if pose.belly_up:
        ctx.scale(-1, 1)
    ph = pose.scarf_phase
    lift = pose.scarf_lift
    knot = (-r - 0.5, 1.0)
    for j, (length, base_ang, wid) in enumerate(((17.0, 0.30, 6.2), (13.0, 0.80, 5.4))):
        pts = []
        segs = 6
        for k in range(segs + 1):
            u = k / segs
            ang = base_ang - lift * 1.4 + 0.28 * math.sin(ph + u * 2.6 + j * 1.3) * u
            # ribbon flows back (-x) and droops (+y)
            px = knot[0] - math.cos(ang - 0.15 * u) * length * u
            py = knot[1] + math.sin(ang + 0.35 * u) * length * u
            pts.append((px, py))
        left, right = [], []
        for k, (px, py) in enumerate(pts):
            a = pts[max(k - 1, 0)]
            b = pts[min(k + 1, segs)]
            tx, ty = b[0] - a[0], b[1] - a[1]
            l = math.hypot(tx, ty) or 1
            nx, ny = -ty / l, tx / l
            w = wid * (1 - 0.25 * k / segs) * (0.85 + 0.15 * math.sin(ph * 1.7 + k + j))
            left.append((px + nx * w / 2, py + ny * w / 2))
            right.append((px - nx * w / 2, py - ny * w / 2))
        tip = pts[-1]
        prev = pts[-2]
        tx, ty = tip[0] - prev[0], tip[1] - prev[1]
        l = math.hypot(tx, ty) or 1
        notch = (tip[0] - tx / l * wid * 0.55, tip[1] - ty / l * wid * 0.55)
        outline = left + [notch] + right[::-1]
        shade = darken(col, 0.08 if j == 0 else 0.22)
        inked(ctx, lambda c, o=outline: poly(c, o), shade, lw * 0.75)
        stroke(ctx, lambda c, p=pts[1:-1]: poly(c, p, close=False), lighten(col, 0.4), 1.0, 0.75)
    ctx.restore()


def draw_scarf_band(ctx, pose, samples, team, lw):
    col = TEAMS[team]
    neck = spine_at(samples, NECK_T)
    r = neck[2]
    ctx.save()
    _local(ctx, neck)
    if pose.belly_up:
        ctx.scale(-1, 1)
    w = r + 1.6
    h = 3.6

    def band(c):
        c.move_to(-w, -h + 0.4)
        c.curve_to(-w * 0.3, -h - 1.4, w * 0.5, -h - 0.8, w, -h + 1.2)
        c.curve_to(w + 1.8, -h + 2.6, w + 1.8, h - 0.8, w - 0.2, h + 0.9)
        c.curve_to(w * 0.4, h + 2.8, -w * 0.4, h + 2.2, -w, h + 0.2)
        c.close_path()
    inked(ctx, band, col, lw)
    ctx.save()
    clip_to(ctx, band)
    fill(ctx, lambda c: rrect(c, -w - 3, 1.2, 2 * w + 6, 8, 2), darken(col, 0.18))
    # knit stripes
    for xx in (-w * 0.45, w * 0.15, w * 0.7):
        stroke(ctx, lambda c, x=xx: (c.move_to(x - 1.4, -h - 2), c.line_to(x + 1.0, h + 3)),
               lighten(col, 0.45), 1.3, 0.85)
    stroke(ctx, lambda c: (c.move_to(-w, -h + 1.6), c.curve_to(-w * 0.3, -h + 0.2, w * 0.5, -h + 0.6, w, -h + 2.6)),
           WHITE, 0.9, 0.45)
    ctx.restore()
    # knot at the back
    inked(ctx, lambda c: ellipse(c, -w + 0.6, 0.6, 3.3, 3.9, 0.3), darken(col, 0.08), lw)
    shine_dot(ctx, -w + 0.0, -0.8, 0.9)
    ctx.restore()


def shine_dot(ctx, x, y, r, alpha=0.8):
    fill(ctx, lambda c: circle(c, x, y, r), WHITE, alpha)


def draw_eye(ctx, cx, cy, rx, ry, pose, lw, far=False):
    style = pose.eyes
    lx, ly = pose.look
    if style in ("happy", "squeeze", "x"):
        if style == "x":
            inked(ctx, lambda c: ellipse(c, cx, cy, rx * 0.92, ry * 0.86), WHITE, lw)
        else:
            fill(ctx, lambda c: ellipse(c, cx, cy, rx * 0.95, ry * 0.85), SKIN)
    if style == "happy":
        # closed upturned arcs ^ ^
        stroke(ctx, lambda c: (c.move_to(cx - rx * 0.8, cy + ry * 0.25),
                               c.curve_to(cx - rx * 0.4, cy - ry * 0.75, cx + rx * 0.4, cy - ry * 0.75,
                                          cx + rx * 0.8, cy + ry * 0.25)), INK, lw * 1.25)
        return
    if style == "squeeze":
        d = 1 if not far else 1
        stroke(ctx, lambda c: (c.move_to(cx - rx * 0.7, cy - ry * 0.55),
                               c.line_to(cx + rx * 0.6 * d, cy),
                               c.line_to(cx - rx * 0.7, cy + ry * 0.55)), INK, lw * 0.95)
        return
    if style == "x":
        e = rx * 0.62
        stroke(ctx, lambda c: (c.move_to(cx - e, cy - e), c.line_to(cx + e, cy + e),
                               c.move_to(cx + e, cy - e), c.line_to(cx - e, cy + e)), INK, lw * 0.95)
        return

    def eye(c):
        ellipse(c, cx, cy, rx, ry)
    inked(ctx, eye, WHITE, lw)
    ctx.save()
    clip_to(ctx, eye)
    # soft inner shading
    fill(ctx, lambda c: ellipse(c, cx - rx * 0.25, cy + ry * 0.35, rx * 1.1, ry * 0.85), "#dfe7ea", 0.55)
    fill(ctx, lambda c: ellipse(c, cx + rx * 0.1, cy - ry * 0.15, rx * 0.95, ry * 0.85), WHITE)
    if style == "swirl":
        ctx.save()
        ctx.translate(cx, cy)
        ctx.new_path()
        steps = 40
        for k in range(steps):
            u = k / steps
            a = u * math.tau * 2.2 + (1.4 if far else 0)
            rr = 0.4 + u * rx * 0.72
            px, py = math.cos(a) * rr, math.sin(a) * rr * ry / rx
            (ctx.move_to if k == 0 else ctx.line_to)(px, py)
        src(ctx, INK)
        ctx.set_line_width(lw * 0.55)
        ctx.stroke()
        ctx.restore()
    else:
        ps = pose.pupil * (0.72 if style == "wide" else 1.0)
        prx, pry = rx * 0.5 * ps, ry * 0.52 * ps
        px = cx + lx * (rx - prx) * 0.85
        py = cy + ly * (ry - pry) * 0.85
        fill(ctx, lambda c: ellipse(c, px, py, prx, pry), INK)
        fill(ctx, lambda c: ellipse(c, px, py + pry * 0.3, prx * 0.7, pry * 0.55), "#2f4c58", 0.9)
        fill(ctx, lambda c: circle(c, px - prx * 0.35, py - pry * 0.4, max(prx * 0.38, 0.7)), WHITE)
        fill(ctx, lambda c: circle(c, px + prx * 0.35, py + pry * 0.35, max(prx * 0.16, 0.4)), WHITE, 0.9)
    # eyelids
    if pose.lid > 0.01:
        top = cy - ry - 1
        edge = cy - ry + 2 * ry * pose.lid
        fill(ctx, lambda c: (c.rectangle(cx - rx - 2, top, 2 * rx + 4, edge - top)), SKIN)
        fill(ctx, lambda c: (c.rectangle(cx - rx - 2, edge - 2.2, 2 * rx + 4, 2.2)), SKIN_SHADE, 0.7)
    if pose.low_lid > 0.01:
        bot = cy + ry + 1
        edge = cy + ry - 2 * ry * pose.low_lid
        fill(ctx, lambda c: c.rectangle(cx - rx - 2, edge, 2 * rx + 4, bot - edge), SKIN)
    ctx.restore()
    stroke(ctx, eye, INK, lw)
    if pose.lid > 0.01:
        edge = cy - ry + 2 * ry * pose.lid
        hw = rx * math.sqrt(max(0.0, 1 - ((edge - cy) / ry) ** 2))
        stroke(ctx, lambda c: (c.move_to(cx - hw - 0.4, edge), c.line_to(cx + hw + 0.4, edge)), INK, lw * 0.9)
    if pose.low_lid > 0.01:
        edge = cy + ry - 2 * ry * pose.low_lid
        hw = rx * math.sqrt(max(0.0, 1 - ((edge - cy) / ry) ** 2))
        stroke(ctx, lambda c: (c.move_to(cx - hw, edge + 0.6), c.curve_to(cx - hw * 0.3, edge - 0.6,
                                                                         cx + hw * 0.3, edge - 0.6,
                                                                         cx + hw, edge + 0.6)), INK, lw * 0.8)


def draw_mouth(ctx, pose, lw):
    m = pose.mouth
    if m == "smile":
        stroke(ctx, lambda c: (c.move_to(4.2, 4.6), c.curve_to(6.5, 8.4, 10.8, 8.2, 12.6, 4.4)), INK, lw * 0.75)
        stroke(ctx, lambda c: (c.move_to(3.6, 4.0), c.line_to(4.6, 5.1)), INK, lw * 0.55)
    elif m == "flat":
        stroke(ctx, lambda c: (c.move_to(5.0, 6.0), c.curve_to(7.5, 6.8, 10.0, 6.6, 12.0, 5.6)), INK, lw * 0.7)
    elif m in ("grin", "cheer", "o", "tongue_out"):
        if m == "o":
            path = lambda c: ellipse(c, 9.0, 6.6, 2.4, 3.0)
        elif m == "cheer":
            path = lambda c: (c.move_to(3.4, 3.8), c.curve_to(7.0, 4.8, 11.0, 4.6, 14.0, 2.8),
                              c.curve_to(14.0, 9.5, 9.0, 13.5, 5.0, 8.5), c.close_path())
        else:
            path = lambda c: (c.move_to(4.0, 4.4), c.curve_to(7.0, 5.4, 10.5, 5.2, 13.2, 3.8),
                              c.curve_to(12.8, 9.0, 8.0, 11.0, 5.0, 7.6), c.close_path())
        inked(ctx, path, MOUTH_DARK, lw * 0.75)
        ctx.save()
        clip_to(ctx, path)
        fill(ctx, lambda c: ellipse(c, 8.6, 11.0, 4.2, 3.2), TONGUE)
        if m != "o":
            fill(ctx, lambda c: c.rectangle(3, 2.0, 12, 3.1), WHITE)
        ctx.restore()
        stroke(ctx, path, INK, lw * 0.75)
    elif m == "grit":
        path = lambda c: rrect(c, 4.2, 3.8, 9.0, 4.8, 2.0)
        inked(ctx, path, WHITE, lw * 0.75)
        stroke(ctx, lambda c: (c.move_to(4.6, 6.2), c.line_to(12.8, 6.0),
                               c.move_to(7.2, 4.0), c.line_to(7.2, 8.4),
                               c.move_to(10.2, 4.0), c.line_to(10.2, 8.4)), INK, lw * 0.45)
    elif m == "wavy":
        stroke(ctx, lambda c: (c.move_to(3.8, 6.4), c.curve_to(5.2, 4.6, 6.4, 8.2, 8.0, 6.2),
                               c.curve_to(9.4, 4.6, 10.6, 8.2, 12.6, 5.8)), INK, lw * 0.7)
    elif m == "tongue":
        stroke(ctx, lambda c: (c.move_to(4.0, 5.0), c.curve_to(6.5, 7.6, 10.5, 7.6, 12.8, 4.8)), INK, lw * 0.75)
        inked(ctx, lambda c: (c.move_to(8.0, 6.8), c.curve_to(8.2, 11.5, 12.6, 11.2, 11.8, 6.2), c.close_path()),
              TONGUE, lw * 0.6)


def draw_headgear_back(ctx, pose, team, lw):
    col = TEAMS[team]
    if team == 2:
        # headband tails at the back of the head
        ph = pose.scarf_phase
        for j, (ang, ln) in enumerate(((2.75, 9.5), (2.35, 8.0))):
            a = ang + 0.18 * math.sin(ph + j)
            ex, ey = -11.5 + math.cos(a) * ln, -8 + math.sin(a) * ln * 0.8 + pose.scarf_lift * -4
            pts = [(-11.5, -9.6), (ex, ey - 1.8), (ex - 1.2, ey + 0.4), (ex + 0.4, ey + 2.0), (-11.0, -6.6)]
            inked(ctx, lambda c, p=pts: smooth(c, p, True, 0.3), darken(col, 0.2 + 0.1 * j), lw)


def draw_headgear(ctx, pose, team, lw):
    ctx.save()
    lift = {1: -2.4, 3: -0.8, 4: 0.4, 5: -2.4}.get(team)
    if lift is not None:
        ctx.translate(-0.6, lift)
    _draw_headgear(ctx, pose, team, lw)
    ctx.restore()


def _draw_headgear(ctx, pose, team, lw):
    col = TEAMS[team]
    dk = darken(col, 0.25)
    lt = lighten(col, 0.45)
    if team == 0:
        # aviator goggles pushed up onto the crown
        strap = lambda c: (c.move_to(-14.2, -4.0), c.curve_to(-10, -12.5, 0, -15.2, 9.5, -13.8),
                           c.line_to(9.0, -10.2), c.curve_to(0, -11.4, -9, -9.6, -13.6, -0.8), c.close_path())
        inked(ctx, strap, col, lw)
        stroke(ctx, lambda c: (c.move_to(-12.6, -4.6), c.curve_to(-8, -11, 0, -13.2, 8.6, -12.2)), lt, 0.9, 0.8)
        for (gx, gy, gr) in ((-4.0, -15.6, 5.2), (5.6, -16.4, 5.5)):
            inked(ctx, lambda c, a=gx, b=gy, r=gr: circle(c, a, b, r), "#f5d58a", lw * 0.8)
            inked(ctx, lambda c, a=gx, b=gy, r=gr: circle(c, a, b, r - 1.8), "#86d6d3", lw * 0.45)
            fill(ctx, lambda c, a=gx, b=gy, r=gr: ellipse(c, a - 0.8, b - 1.0, r * 0.32, r * 0.22, -0.5), WHITE, 0.95)
        inked(ctx, lambda c: rrect(c, -0.4, -17.4, 2.2, 2.0, 0.8), darken(GOLD, 0.2), lw * 0.45)
    elif team == 1:
        # rounded field helmet tipped back
        ctx.save()
        ctx.rotate(-0.22)
        dome = lambda c: (c.move_to(-16.5, -5.2), c.curve_to(-16.5, -21.5, 13.5, -21.5, 13.5, -5.2),
                          c.curve_to(5, -7.3, -8, -7.3, -16.5, -5.2), c.close_path())
        inked(ctx, dome, col, lw)
        ctx.save()
        clip_to(ctx, dome)
        fill(ctx, lambda c: ellipse(c, 4, -2, 17, 6.5), dk, 0.75)
        fill(ctx, lambda c: ellipse(c, -6, -15.5, 6.5, 3.2, -0.25), lt, 0.8)
        ctx.restore()
        rim = lambda c: (c.move_to(-18.0, -4.6), c.curve_to(-6, -8.6, 6, -8.6, 15.6, -4.4),
                         c.curve_to(15.8, -2.6, 15.0, -2.0, 14.0, -2.2), c.curve_to(5, -5.6, -6, -5.6, -17.2, -2.4),
                         c.curve_to(-18.8, -2.6, -18.8, -4.0, -18.0, -4.6), c.close_path())
        inked(ctx, rim, dk, lw * 0.85)
        for rx_ in (-9.0, -1.5, 6.0):
            fill(ctx, lambda c, x=rx_: circle(c, x, -10.5 - (0 if x != -1.5 else 1.8), 1.0), darken(col, 0.5))
        ctx.restore()
    elif team == 2:
        band = lambda c: (c.move_to(-13.0, -11.4), c.curve_to(-6, -15.5, 6, -15.2, 13.2, -10.0),
                          c.line_to(13.6, -5.8), c.curve_to(6, -10.6, -6, -10.6, -13.6, -6.0), c.close_path())
        inked(ctx, band, col, lw)
        ctx.save()
        clip_to(ctx, band)
        for k in range(6):
            fill(ctx, lambda c, x=-11 + k * 5: circle(c, x, -10.5 + abs(x) * 0.12, 0.95), WHITE, 0.9)
        ctx.restore()
        inked(ctx, lambda c: ellipse(c, -12.8, -8.4, 2.9, 3.4, 0.4), dk, lw * 0.85)
    elif team == 3:
        # knit beanie with a pom-pom
        hat = lambda c: (c.move_to(-14.6, -7.2), c.curve_to(-15.5, -24.5, 12.5, -25.5, 12.6, -8.6),
                         c.curve_to(4, -11.6, -6, -11.0, -14.6, -7.2), c.close_path())
        inked(ctx, hat, col, lw)
        ctx.save()
        clip_to(ctx, hat)
        for k in range(7):
            x = -12 + k * 4.2
            stroke(ctx, lambda c, x=x: (c.move_to(x, -8), c.curve_to(x + 0.6, -14, x + 1.6, -19, x + 3.2, -24)),
                   dk, 0.9, 0.7)
        fill(ctx, lambda c: ellipse(c, -6, -18, 4.5, 2.4, -0.4), lt, 0.7)
        ctx.restore()
        cuff = lambda c: (c.move_to(-16.0, -6.6), c.curve_to(-6, -12.4, 6, -12.6, 14.0, -8.8),
                          c.line_to(14.4, -4.6), c.curve_to(6, -8.4, -6, -8.4, -15.6, -2.4), c.close_path())
        inked(ctx, cuff, dk, lw)
        ctx.save()
        clip_to(ctx, cuff)
        for k in range(10):
            x = -15 + k * 3.2
            stroke(ctx, lambda c, x=x: (c.move_to(x, -14), c.line_to(x + 0.4, -1)), darken(col, 0.42), 0.8, 0.8)
        ctx.restore()
        pom = lambda c: (circle(c, -3.4, -22.2, 3.8))
        inked(ctx, pom, PAPER, lw)
        for (a, b) in ((-4.6, -23.4), (-2.0, -21.2), (-4.8, -20.8), (-2.3, -24.0)):
            fill(ctx, lambda c, a=a, b=b: circle(c, a, b, 0.7), darken(PAPER, 0.15))
    elif team == 4:
        # propeller beanie
        cap = lambda c: (c.move_to(-13.8, -8.6), c.curve_to(-13.2, -22.0, 11.2, -22.6, 11.8, -9.4),
                         c.curve_to(4, -12.4, -6, -12.0, -13.8, -8.6), c.close_path())
        inked(ctx, cap, col, lw)
        ctx.save()
        clip_to(ctx, cap)
        fill(ctx, lambda c: (c.move_to(-1.5, -24), c.line_to(3.5, -24), c.line_to(1.5, -8), c.line_to(-4.5, -8),
                             c.close_path()), GOLD)
        fill(ctx, lambda c: (c.move_to(-14, -24), c.line_to(-9, -24), c.line_to(-11, -8), c.line_to(-16, -8),
                             c.close_path()), PAPER, 0.85)
        fill(ctx, lambda c: ellipse(c, -6, -17, 4.0, 2.0, -0.4), WHITE, 0.45)
        ctx.restore()
        stroke(ctx, cap, INK, lw)
        stroke(ctx, lambda c: (c.move_to(-0.6, -20.6), c.line_to(-0.6, -23.4)), INK, lw * 0.9)
        # propeller (foreshortened)
        a = pose.prop
        span = 9.0 * abs(math.cos(a)) + 2.2
        for sgn, colr in ((1, "#e2524a"), (-1, "#5aa3d9")):
            blade = lambda c, s=sgn: ellipse(c, -0.6 + s * span / 2, -24.0, span / 2, 1.8 + 0.6 * abs(math.sin(a)))
            inked(ctx, blade, colr, lw * 0.75)
        inked(ctx, lambda c: circle(c, -0.6, -24.0, 1.5), GOLD, lw * 0.6)
    elif team == 5:
        # cap worn backwards, brim sticking out behind
        brim = lambda c: (c.move_to(-10.8, -10.6), c.curve_to(-16.5, -12.4, -21.5, -11.4, -22.6, -8.6),
                          c.curve_to(-20.5, -6.6, -15.0, -6.6, -11.4, -6.8), c.close_path())
        inked(ctx, brim, dk, lw)
        cap = lambda c: (c.move_to(-13.6, -8.2), c.curve_to(-13.6, -22.2, 12.6, -23.0, 12.8, -9.2),
                         c.curve_to(4, -12.2, -6, -11.8, -13.6, -8.2), c.close_path())
        inked(ctx, cap, col, lw)
        ctx.save()
        clip_to(ctx, cap)
        stroke(ctx, lambda c: (c.move_to(-0.5, -22), c.curve_to(0.2, -17, 0.6, -13, 0.4, -10)), dk, 1.0)
        fill(ctx, lambda c: ellipse(c, -6.5, -17.5, 4.0, 2.2, -0.4), lt, 0.7)
        fill(ctx, lambda c: ellipse(c, 6, -15, 3.0, 3.0), WHITE, 0.95)
        ctx.restore()
        stroke(ctx, lambda c: (c.move_to(4.2, -16.6), c.line_to(6.0, -13.6), c.line_to(7.8, -16.6)), col, 1.2)
        inked(ctx, lambda c: circle(c, -0.4, -21.0, 1.3), dk, lw * 0.5)


def draw_brows(ctx, pose, lw):
    if pose.eyes in ("x", "happy"):
        return
    b = pose.brow
    lift = pose.brow_lift
    # near eye brow (over x~10), far eye brow (over x~2.5)
    for (cx, w, far) in ((10.4, 3.6, False), (1.2, 3.0, True)):
        y = -15.6 - lift
        tilt = b * (1.6 if not far else -1.2)
        stroke(ctx, lambda c, cx=cx, w=w, t=tilt: (c.move_to(cx - w, y - t * (1 if not far else 0.6) - 0.3),
                                                   c.curve_to(cx - w * 0.3, y - 1.4 - t * 0.2, cx + w * 0.3,
                                                              y - 1.4 + t * 0.2, cx + w, y + t)),
               INK, lw * 0.62)


# --------------------------------------------------------------------------
# Extras (effects drawn in sprite space)
# --------------------------------------------------------------------------

def draw_extra(ctx, ex, team, lw):
    kind = ex[0]
    if kind == "sparkle":
        _, x, y, r, col = ex
        sparkle(ctx, x, y, r, col, lw * 0.5)
    elif kind == "confetti":
        _, x, y, a, col = ex
        ctx.save()
        ctx.translate(x, y)
        ctx.rotate(a)
        inked(ctx, lambda c: rrect(c, -2.0, -1.1, 4.0, 2.2, 0.5), col, lw * 0.4)
        ctx.restore()
    elif kind == "dust":
        _, x, y, r, a = ex
        inked(ctx, lambda c: (circle(c, x, y, r), circle(c, x + r * 0.9, y + r * 0.2, r * 0.75),
                              circle(c, x - r * 0.8, y + r * 0.3, r * 0.6)), PAPER, lw * 0.45, INK, a)
    elif kind == "star":
        _, x, y, r, a = ex
        ctx.save()
        ctx.translate(x, y)
        ctx.rotate(a)
        from build_art_core import star_pts
        inked(ctx, lambda c: poly(c, star_pts(0, 0, r, r * 0.45)), GOLD, lw * 0.5)
        ctx.restore()
    elif kind == "sweat":
        _, x, y, s = ex
        inked(ctx, lambda c: (c.move_to(x, y - 3.6 * s), c.curve_to(x + 2.6 * s, y, x + 2.4 * s, y + 2.6 * s, x, y + 2.6 * s),
                              c.curve_to(x - 2.4 * s, y + 2.6 * s, x - 2.6 * s, y, x, y - 3.6 * s), c.close_path()),
              "#9fdcf0", lw * 0.5)
        fill(ctx, lambda c: circle(c, x - 0.6 * s, y + 0.8 * s, 0.6 * s), WHITE)
    elif kind == "speed":
        _, x, y, ln = ex
        stroke(ctx, lambda c: (c.move_to(x, y), c.line_to(x + ln, y)), INK, lw * 0.5, 0.55)
    elif kind == "impact":
        _, x, y, r = ex
        from build_art_core import star_pts
        inked(ctx, lambda c: poly(c, star_pts(x, y, r, r * 0.5, 7, 0.2)), "#ffe7a3", lw * 0.55)
        inked(ctx, lambda c: poly(c, star_pts(x, y, r * 0.55, r * 0.28, 7, 0.4)), WHITE, 0)
    elif kind == "halo":
        _, x, y = ex
        ctx.save()
        ellipse(ctx, x, y, 8.0, 2.6)
        src(ctx, INK)
        ctx.set_line_width(lw * 1.9)
        ctx.stroke_preserve()
        src(ctx, GOLD)
        ctx.set_line_width(lw * 0.9)
        ctx.stroke()
        ctx.restore()
    elif kind == "zz":
        pass


# --------------------------------------------------------------------------
# Full grub
# --------------------------------------------------------------------------

def draw_grub(ctx, pose: Pose, team: int, lw: float = LW, under_extras=True):
    ax, ay = ANCHOR
    ctx.save()
    ctx.translate(ax + pose.dx, ay + pose.dy)
    ctx.rotate(math.radians(pose.rot))
    ctx.scale(pose.sx, pose.sy)
    ctx.translate(-ax, -ay)

    if pose.shadow > 0:
        # contact shadow in sprite space: it stays on the ground while the body hops
        lift = max(0.0, -pose.dy)
        rx = 17.0 - lift * 1.1
        ctx.save()
        ctx.translate(ax - 2.5, ay - 0.6)
        ctx.scale(1.0, 0.2)
        ctx.set_source(rad_grad(0, 0, 0, rx, [(0, INK, 0.34 * pose.shadow), (0.6, INK, 0.2 * pose.shadow),
                                              (1, INK, 0.0)]))
        circle(ctx, 0, 0, rx)
        ctx.fill()
        ctx.restore()
    samples = sample_spine(pose.pts, pose.radii)
    if pose.belly_up:
        samples = [(x, y, r, tx, ty, -nx, -ny) for (x, y, r, tx, ty, nx, ny) in samples]
    head = samples[-1]
    hr = head[2]
    hscale = hr / 13.5

    # extras behind the character
    for ex in pose.extras:
        if ex[0] in ("dust", "speed"):
            draw_extra(ctx, ex, team, lw)

    # 1. scarf tails + headgear back pieces (behind the body)
    if pose.tails:
        draw_scarf_tails(ctx, pose, samples, team, lw)
    ctx.save()
    _local(ctx, head, hscale, pose.head_angle)
    if pose.belly_up and pose.head_angle is None:
        ctx.scale(-1, 1)
    draw_headgear_back(ctx, pose, team, lw / hscale)
    ctx.restore()

    # 2. body tube with unified outline
    body = tube_path(samples)
    outline_pass(ctx, [body], lw / 2 + 0.05)
    fill(ctx, body, SKIN_SHADE)
    ctx.save()
    clip_to(ctx, body)
    # lit body volume (light from upper front)
    lx, ly = (1.3, -1.5) if not pose.belly_up else (-1.3, -1.5)
    fill(ctx, tube_path(samples, scale=0.86, shift=(lx, ly)), SKIN)
    # belly plate along the front
    fill(ctx, tube_path(samples, scale=0.42, off=0.56, t0=0.04, t1=NECK_T - 0.02), BELLY, 0.95)
    # segment creases
    total = 0.0
    last = samples[0]
    marks = []
    for s in samples[1:int(len(samples) * NECK_T)]:
        total += math.hypot(s[0] - last[0], s[1] - last[1])
        last = s
        if total > 5.2:
            marks.append(s)
            total = 0.0
    for s in marks:
        x, y, r, tx, ty, nx, ny = s
        if r < 4:
            continue
        stroke(ctx, lambda c, x=x, y=y, r=r, tx=tx, ty=ty, nx=nx, ny=ny: (
            c.move_to(x + nx * r * 1.05, y + ny * r * 1.05),
            c.curve_to(x + nx * r * 0.6 + tx * 1.4, y + ny * r * 0.6 + ty * 1.4,
                       x + nx * r * 0.1 + tx * 1.4, y + ny * r * 0.1 + ty * 1.4,
                       x - nx * r * 0.25, y - ny * r * 0.25)), SKIN_DEEP, 1.05, 0.55)
    # highlight streak
    hl = [(s[0] + lx * 0.4 + s[5] * s[2] * 0.42, s[1] + ly * 0.4 + s[6] * s[2] * 0.42 - s[2] * 0.25)
          for s in samples[int(len(samples) * 0.35):int(len(samples) * 0.72)]]
    if len(hl) > 2:
        stroke(ctx, lambda c: poly(c, hl, close=False), SKIN_LIGHT, 1.9, 0.75)
    # volume: warm top light falling off into a cooler underside
    top = min(s[1] - s[2] for s in samples)
    bottom = max(s[1] + s[2] for s in samples)
    ctx.set_source(lin_grad(0, top, 0, bottom, [(0, WHITE, 0.16), (0.45, WHITE, 0.0), (0.78, SKIN_DEEP, 0.0),
                                                (1, SKIN_DEEP, 0.32)]))
    ctx.paint()
    ctx.restore()

    # 3. face, scarf band, headgear in the head frame
    draw_scarf_band(ctx, pose, samples, team, lw)

    ctx.save()
    _local(ctx, head, hscale, pose.head_angle)
    if pose.belly_up and pose.head_angle is None:
        ctx.scale(-1, 1)
    hlw = lw / hscale
    # head gloss + blush
    fill(ctx, lambda c: ellipse(c, 3.5, -9.5, 4.5, 2.6, -0.35), WHITE, 0.55)
    if pose.blush > 0:
        fill(ctx, lambda c: ellipse(c, 4.4, 2.6, 3.4, 1.9), BLUSH, pose.blush)
    draw_mouth(ctx, pose, hlw)
    draw_headgear(ctx, pose, team, hlw)
    # eyes: far first, then near
    draw_eye(ctx, 1.0, -6.0, 6.0, 7.6, pose, hlw * 0.8, far=True)
    draw_eye(ctx, 9.6, -4.6, 6.8, 8.5, pose, hlw * 0.8)
    draw_brows(ctx, pose, hlw)
    ctx.restore()

    ctx.restore()
    for ex in pose.extras:
        if ex[0] not in ("dust", "speed"):
            draw_extra(ctx, ex, team, lw)


# --------------------------------------------------------------------------
# Animation sets
# --------------------------------------------------------------------------

BASE_PTS = [(11.5, 61.2), (21.5, 62.4), (31.5, 59.0), (40.5, 53.8), (44.5, 46.0), (45.4, 39.5), (45.8, 31.0)]
BASE_R = [2.6, 6.0, 9.4, 10.8, 10.4, 9.8, 15.0]


def _pts(offsets):
    return [(x + dx, y + dy) for (x, y), (dx, dy) in zip(BASE_PTS, offsets)]


def idle_frames():
    out = []
    looks = [(0.45, 0.05), (0.35, -0.25), (0.45, 0.05), (0.55, 0.15)]
    for k in range(4):
        b = math.sin(k * math.tau / 4)
        offs = [(0, 0), (0, 0), (0, 0), (-0.3 * b, -0.4 * b), (-0.4 * b, -1.0 * b), (-0.2 * b, -1.6 * b),
                (0.3 * b, -2.0 * b)]
        out.append(Pose(_pts(offs), BASE_R, look=looks[k], sx=1 - 0.02 * b, sy=1 + 0.02 * b,
                        scarf_phase=k * math.tau / 4, prop=k * 0.7, lid=0.06 if k != 3 else 0.18))
    return out


def blink_frames():
    a = idle_frames()[0]
    return [replace(a, lid=0.55), replace(a, lid=1.0)]


def walk_frames():
    out = []
    for k in range(8):
        ph = k * math.tau / 8
        c = (1 - math.cos(ph)) / 2          # rear bunch-up amount
        s = math.sin(ph)
        offs = [(7.5 * c, -1.2 * c), (4.5 * c, -9.0 * c), (1.5 * c, -2.5 * c), (0.6 * c, -0.8 * c),
                (0.8 + 0.6 * s, 0.6 * c), (1.6 + 1.0 * s, 0.4 * c - 0.6), (2.6 + 1.6 * s, 0.9 * c - 0.6)]
        extras = []
        if k in (5, 6):
            extras.append(("dust", 13.0 - (k - 5) * 3.5, 64.5 - (k - 5) * 1.6, 2.4 + (k - 5) * 0.6, 0.9 - (k - 5) * 0.3))
        out.append(Pose(_pts(offs), BASE_R, look=(0.6, 0.12), rot=1.5 + 1.5 * s, sx=1 + 0.03 * c,
                        sy=1 - 0.03 * c, scarf_phase=ph * 2, prop=k * 0.8, extras=extras,
                        brow=0.15, mouth="smile" if k % 4 != 2 else "smile"))
    return out


def jump_frames():
    crouch = Pose(_pts([(2, 0.5), (2, 0.5), (1, 0.5), (0.5, 2.0), (1.0, 4.5), (1.6, 6.5), (2.4, 7.5)]),
                  [2.8, 6.6, 10.0, 11.6, 11.2, 10.4, 15.0], look=(0.55, -0.45), sx=1.08, sy=0.92,
                  brow=0.9, low_lid=0.2, mouth="grit", prop=0.3,
                  extras=[("dust", 18, 66, 2.6, 0.9), ("dust", 62, 66, 2.6, 0.9)])
    launch = Pose([(38.0, 67.5), (40.0, 61.5), (42.0, 55.0), (44.0, 48.0), (45.5, 41.0), (46.2, 36.5), (46.5, 29.5)],
                  [2.4, 5.6, 8.0, 9.4, 9.6, 9.2, 14.4], look=(0.4, -0.8), sx=0.94, sy=1.05, rot=4,
                  eyes="wide", brow_lift=1.5, mouth="cheer", scarf_lift=0.6, scarf_phase=1.0, prop=1.2,
                  extras=[("speed", 31, 50, -8), ("speed", 30, 58, -6)])
    apex = Pose([(37.0, 52.0), (31.5, 60.0), (37.0, 66.0), (45.5, 62.0), (48.5, 53.5), (48.2, 45.5), (47.0, 35.5)],
                [2.6, 6.0, 9.0, 10.4, 10.4, 9.8, 15.0], look=(0.5, 0.0), dy=-6.0, rot=-6,
                mouth="grin", low_lid=0.15, brow_lift=1.0, scarf_lift=0.35, scarf_phase=2.2, prop=2.0)
    fall = Pose([(41.0, 67.5), (42.0, 61.5), (42.6, 55.0), (43.6, 48.0), (45.0, 41.0), (46.0, 36.5), (46.2, 29.5)],
                [2.4, 5.6, 8.0, 9.2, 9.6, 9.2, 14.4], look=(0.3, 0.8), sx=0.95, sy=1.04, rot=-4,
                eyes="wide", brow=-0.8, brow_lift=2.0, mouth="o", scarf_lift=1.0, scarf_phase=3.2, prop=2.9,
                extras=[("speed", 31, 30, 0.01), ("sweat", 66, 16, 0.9)])
    return [crouch, launch, apex, fall]


def hurt_frames():
    recoil = Pose(_pts([(0, 0), (0, 0), (0, 0), (-1.5, 0.5), (-4.5, 0.8), (-7.5, 1.6), (-10.5, 3.0)]),
                  BASE_R, rot=-4, eyes="squeeze", mouth="grin", brow=-0.6, scarf_phase=2.0, scarf_lift=0.4,
                  extras=[("impact", 66, 30, 9.0), ("sweat", 18, 20, 0.9)])
    squash = Pose(_pts([(-1, 0.5), (-1, 0.5), (0, 0.5), (0, 2.5), (-0.5, 5.5), (-1.0, 7.5), (-1.5, 8.5)]),
                  [2.8, 6.8, 10.2, 11.8, 11.4, 10.6, 15.2], sx=1.12, sy=0.9, eyes="wide", pupil=0.8,
                  mouth="wavy", brow=-1.0, brow_lift=1.2, scarf_phase=3.5,
                  extras=[("star", 24, 18, 3.2, 0.3), ("star", 66, 14, 2.6, 0.8)])
    dizzy = Pose(_pts([(0, 0), (0, 0), (0, 0), (0.5, 0), (1.5, 0), (3.0, 0.5), (4.5, 1.0)]),
                 BASE_R, rot=5, eyes="swirl", mouth="wavy", brow=-0.4, scarf_phase=4.5,
                 extras=[("star", 30, 7, 3.0, 0.1), ("star", 47, 3.5, 2.4, 0.9), ("star", 63, 8, 2.8, 1.6)])
    return [recoil, squash, dizzy]


def victory_frames(team):
    out = []
    confetti_cols = [TEAMS[team], GOLD, "#ffffff", TEAL, "#ff8fa3"]
    for k in range(6):
        ph = k * math.tau / 6
        hop = max(0.0, math.sin(ph)) * 3.0
        land = max(0.0, -math.sin(ph))
        lean = math.sin(ph + math.pi / 2) * 7
        offs = [(1.5 * land, 0), (1 * land, -1.5 * hop / 3.0), (0, 0), (0, 0.5 * land),
                (0.5 * math.cos(ph), 1.2 * land), (1.0 * math.cos(ph), 2.0 * land - 1.0),
                (1.6 * math.cos(ph), 2.6 * land - 1.4)]
        extras = []
        for j in range(6):
            a = ph * 0.5 + j * math.tau / 6
            r = 26 + 3 * math.sin(ph + j)
            x = 40 + math.cos(a) * r
            y = 30 + math.sin(a) * r * 0.45
            if j % 2 == 0:
                extras.append(("confetti", x, y, a * 2.3, confetti_cols[j % len(confetti_cols)]))
            else:
                extras.append(("sparkle", x, y, 2.4 + 1.2 * ((k + j) % 2), GOLD if j != 3 else WHITE))
        out.append(Pose(_pts(offs), BASE_R, eyes="happy", mouth="cheer", dy=-hop, rot=lean,
                        sx=1 + 0.07 * land, sy=1 - 0.07 * land + 0.03 * (hop / 3.0),
                        scarf_phase=ph * 2, scarf_lift=0.3 * hop / 3.0, prop=k * 1.1, blush=0.6,
                        extras=extras))
    return out


def dead_frames():
    # flopped flat on the ground, head resting on its cheek, X eyes and a halo
    p = Pose([(9.0, 64.5), (18.0, 63.6), (28.0, 62.8), (37.0, 62.2), (44.0, 61.4), (49.0, 60.0), (55.5, 55.4)],
             [2.4, 5.6, 7.6, 8.4, 8.6, 8.6, 12.6], eyes="x", mouth="tongue", head_angle=-0.55,
             scarf_phase=0.5, blush=0.0, tails=False, dy=-3.5, extras=[("halo", 55, 31)])
    return [p]


STATES = {
    "idle": idle_frames,
    "walk": walk_frames,
    "jump": jump_frames,
    "hurt": hurt_frames,
    "victory": None,
    "dead": dead_frames,
    "blink": blink_frames,
}
STATE_ORDER = ["idle", "walk", "jump", "hurt", "victory", "dead", "blink"]


SHADOW = {"idle": 1.0, "walk": 1.0, "blink": 1.0, "victory": 1.0, "dead": 0.8}


def frames_for(state, team):
    frames = victory_frames(team) if state == "victory" else STATES[state]()
    # jump/hurt can be airborne in play, so they carry no ground shadow
    return [replace(p, shadow=SHADOW.get(state, 0.0)) for p in frames]
