"""Original close-weapon effects and grub status overlays, rasterized at 2×.

All paths are drawn from this deterministic Cairo source; no external images.
Logical sizes/foot anchors are recorded in metadata() for the art manifest.
"""
from __future__ import annotations

import math

from build_art_core import (ART, GOLD, INK, ORANGE, PAPER, RED, SKIN, SKIN_LIGHT,
    STEEL, STEEL_DARK, STEEL_LIGHT, TEAL, WHITE, WOOD, circle, ellipse, fill,
    inked, poly, rrect, shine, src, star_pts, stroke, surface)

OUT = ART / "ordnance" / "status"
SPECS = {
    "shield": (76, 76, 38, 65, 4), "frozen": (64, 72, 32, 64, 2),
    "poison": (64, 72, 32, 62, 4), "boost": (76, 84, 38, 72, 4),
    "moon": (72, 76, 36, 64, 4), "drill": (80, 84, 40, 68, 2),
    "torch": (96, 80, 40, 68, 2), "muzzle": (48, 40, 24, 20, 3),
    "laser-muzzle": (48, 48, 24, 24, 3), "impact": (40, 40, 20, 20, 4),
    "jet": (64, 40, 32, 20, 4), "fire_punch": (112, 112, 56, 72, 4),
    "dragon_punch": (112, 80, 56, 52, 4), "prod": (112, 80, 56, 52, 4),
    "bat": (112, 112, 56, 68, 4), "axe": (112, 112, 56, 68, 4),
    "heal": (72, 80, 36, 60, 5), "wind": (112, 64, 56, 32, 4),
    "placement": (72, 32, 36, 22, 4),
}
MIRRORED = {"drill", "torch", "fire_punch", "dragon_punch", "prod", "bat", "axe"}


def _render(name, w, h, draw, left=False):
    s, ctx = surface(w * 2, h * 2)
    ctx.scale(2, 2)
    if left:
        ctx.translate(w, 0)
        ctx.scale(-1, 1)
    draw(ctx)
    s.write_to_png(str(OUT / f"{name}.png"))


def _line(ctx, points, color, width=2, alpha=1):
    stroke(ctx, lambda c: poly(c, points, close=False), color, width, alpha)


def _flame(ctx, x, y, length, width, phase=0):
    # The taper points right; a folded outer tongue and white-hot core read at 20 px.
    points = [(x, y), (x + length * .24, y - width * .28),
              (x + length * .17, y - width * .65), (x + length * .57, y - width * .36),
              (x + length * (.9 - phase * .04), y - width * .55),
              (x + length * .76, y - width * .08), (x + length, y + width * .12),
              (x + length * .64, y + width * .22), (x + length * .77, y + width * .52),
              (x + length * .3, y + width * .37)]
    inked(ctx, lambda c: poly(c, points), ORANGE, 1.4, ink="#c14831")
    fill(ctx, lambda c: poly(c, [(x, y), (x + length * .48, y - width * .19),
        (x + length * .72, y + width * .08), (x + length * .34, y + width * .21)]), GOLD)
    fill(ctx, lambda c: poly(c, [(x, y), (x + length * .38, y - width * .06),
        (x + length * .5, y + width * .07), (x + length * .17, y + width * .13)]), WHITE)


def _fist(ctx, x, y, scale=1):
    ctx.save()
    ctx.translate(x, y)
    ctx.scale(scale, scale)
    inked(ctx, lambda c: rrect(c, -10, -8, 20, 16, 5), SKIN, 2)
    inked(ctx, lambda c: rrect(c, -10, 1, 8, 9, 3), SKIN_LIGHT, 1.6)
    for xx in (-3, 3):
        _line(ctx, [(xx, -6), (xx, -1)], "#c8607a", 1)
    shine(ctx, -5, -6, 8, 2, 0)
    ctx.restore()


def _status(ctx, name, frame):
    if name == "shield":
        a = .12 + frame * .025
        fill(ctx, lambda c: ellipse(c, 38, 36, 31, 32), "#69dfd0", a)
        stroke(ctx, lambda c: ellipse(c, 38, 36, 31, 32), "#153f58", 3)
        stroke(ctx, lambda c: ellipse(c, 38, 36, 29.5, 30.5), "#a0fff2", 2)
        stroke(ctx, lambda c: c.arc(38, 36, 26, 3.65, 4.65), WHITE, 3, .85)
        shine(ctx, 54, 51, 7, 2, -.7)
    elif name == "frozen":
        shape = [(6, 59), (5, 21), (17, 7), (44, 5), (58, 20), (59, 60), (47, 66), (14, 66)]
        fill(ctx, lambda c: poly(c, shape), "#7ccfe9", .26)
        stroke(ctx, lambda c: poly(c, shape), "#22698f", 2.5)
        _line(ctx, [(7, 21), (22, 16), (45, 17), (57, 21)], "#d2fbff", 2)
        _line(ctx, [(17, 7), (22, 16), (14, 65)], "#a4efff", 2)
        _line(ctx, [(44, 6), (45, 17), (48, 64)], "#b8f9ff", 2)
        _line(ctx, [(9, 56), (21, 47), (17, 38)], "#d7fcff", 1.5)
        shine(ctx, 27 + frame, 9, 12, 2, 0)
        for x, y in ((12, 24), (52, 39)):
            _line(ctx, [(x - 3, y), (x + 3, y)], WHITE, 1.5)
            _line(ctx, [(x, y - 3), (x, y + 3)], WHITE, 1.5)
    elif name == "poison":
        for i, x in enumerate((13, 31, 50)):
            y = 17 - (frame + i) % 4 * 3
            inked(ctx, lambda c, x=x, y=y, i=i: circle(c, x, y, 2.5 + i % 2), "#a6ce60", 1, alpha=.75)
        stroke(ctx, lambda c: c.arc(32, 57, 18, .15, 2.95), "#9ec958", 2, .7)
    elif name == "boost":
        stroke(ctx, lambda c: ellipse(c, 38, 64, 25 + frame % 2, 8), ORANGE, 2.5, .7)
        for i in range(4):
            x = 9 if i < 2 else 66
            y = 30 + (i % 2) * 17 - frame * 2
            fill(ctx, lambda c, x=x, y=y: poly(c, star_pts(x, y, 3.5, 1.5, n=4)), GOLD)
        inked(ctx, lambda c: rrect(c, 26, 3, 32, 18, 8), ORANGE, 2)
        _line(ctx, [(32, 9), (38, 15)], WHITE, 2)
        _line(ctx, [(38, 9), (32, 15)], WHITE, 2)
        stroke(ctx, lambda c: (c.move_to(43, 8), c.curve_to(52, 3, 54, 11, 44, 15), c.line_to(52, 15)), WHITE, 2)
    elif name == "moon":
        for x in (20, 47):
            inked(ctx, lambda c, x=x: rrect(c, x - 9, 53, 19, 10, 4), "#9fdde8", 1.8)
            _line(ctx, [(x - 6, 59), (x + 7, 59)], WHITE, 1.5)
        for i in range(3):
            y = 65 + i * 3 - frame % 2
            stroke(ctx, lambda c, y=y, i=i: ellipse(c, 36, y, 27 - i * 6, 2), "#d7fbff", 1.3, .75 - i * .2)
        fill(ctx, lambda c: poly(c, star_pts(54, 15 - frame, 5, 2, n=4)), "#d7fbff")


def _tool(ctx, name, frame):
    if name == "drill":
        shake = frame * 1.5
        ctx.translate(shake, 0)
        inked(ctx, lambda c: rrect(c, 29, 38, 22, 26, 5), TEAL, 2)
        inked(ctx, lambda c: rrect(c, 26, 39, 28, 6, 2), STEEL_LIGHT, 2)
        inked(ctx, lambda c: poly(c, [(34, 64), (46, 64), (40, 79)]), STEEL, 1.5)
        for yy in (66, 70, 74):
            _line(ctx, [(35, yy), (44, yy - 2)], STEEL_DARK, 1.5)
        _fist(ctx, 24, 45, .55)
        _fist(ctx, 56, 45, .55)
        shine(ctx, 32, 49, 3, 8, 0)
    else:
        inked(ctx, lambda c: rrect(c, 37, 40, 24, 13, 4), GOLD, 2)
        inked(ctx, lambda c: rrect(c, 50, 43, 24, 6, 2), STEEL_DARK, 1.6)
        inked(ctx, lambda c: rrect(c, 38, 49, 9, 11, 3), TEAL, 1.5)
        _fist(ctx, 39, 50, .6)
        _flame(ctx, 74, 46, 15 + frame * 3, 7, frame)
        shine(ctx, 43, 42, 11, 2, 0)


def _effect(ctx, name, frame):
    if name in ("muzzle", "laser-muzzle"):
        cx, cy = (24, 24) if name == "laser-muzzle" else (24, 20)
        if name == "laser-muzzle":
            stroke(ctx, lambda c: circle(c, cx, cy, 7 + frame * 5), "#ff705e", 3 - frame * .5, .9 - frame * .2)
            fill(ctx, lambda c: poly(c, star_pts(cx, cy, 15 - frame * 3, 3, n=4, rot=0)), "#fff5d8")
        else:
            length = 20 - frame * 5
            fill(ctx, lambda c: poly(c, [(cx - 7, cy), (cx - 2, cy - 9), (cx + 3, cy - 3),
                (cx + length, cy - 4), (cx + length - 5, cy), (cx + length, cy + 4), (cx + 2, cy + 3), (cx - 1, cy + 9)]), ORANGE)
            fill(ctx, lambda c: poly(c, [(cx - 7, cy), (cx + length - 5, cy - 2), (cx + length - 8, cy + 2)]), WHITE)
    elif name == "impact":
        radius = 6 + frame * 4
        for i in range(7):
            a = i * math.tau / 7
            start = 2 + frame * 3
            _line(ctx, [(20 + math.cos(a) * start, 20 + math.sin(a) * start),
                (20 + math.cos(a) * radius, 20 + math.sin(a) * radius)], GOLD if i % 2 else WHITE, max(1, 3 - frame * .5), 1 - frame * .18)
    elif name == "jet":
        _flame(ctx, 5, 21, 52 + frame % 2 * 2, 22 + frame % 2 * 5, frame)
    elif name == "placement":
        stroke(ctx, lambda c: ellipse(c, 36, 22, 16 + frame * 4, 5 + frame), "#b7f3cb", 2, 1 - frame * .2)
        for x in (12 - frame * 2, 60 + frame * 2):
            _line(ctx, [(x, 18), (x, 12 - frame * 2)], GOLD, 2, 1 - frame * .2)
    elif name == "heal":
        for i, x in enumerate((17, 36, 55)):
            y = 48 - frame * 6 - i * 7
            a = min(1, (5 - frame) * .3)
            fill(ctx, lambda c, x=x, y=y: (c.move_to(x, y + 8), c.curve_to(x - 14, y - 1, x - 6, y - 11, x, y - 4),
                c.curve_to(x + 6, y - 11, x + 14, y - 1, x, y + 8)), "#87eda2", a)
            _line(ctx, [(x - 3, y), (x + 3, y)], WHITE, 1.5, a)
            _line(ctx, [(x, y - 3), (x, y + 3)], WHITE, 1.5, a)
    elif name == "wind":
        for i in range(3):
            x = 10 + frame * 3 + i * 6
            y = 17 + i * 15
            stroke(ctx, lambda c, x=x, y=y: (c.move_to(x, y), c.line_to(x + 52, y),
                c.curve_to(x + 76, y, x + 74, y - 16, x + 61, y - 10)), "#c9fff6", 3, 1 - frame * .16)


def _melee(ctx, name, frame):
    cx, cy = (56, 40) if name in ("dragon_punch", "prod") else (56, 56)
    if name == "fire_punch":
        ctx.save()
        ctx.translate(cx + 7, cy + 12)
        ctx.rotate(-math.pi / 2)
        _flame(ctx, -15, 0, 52, 26, frame)
        ctx.restore()
        _fist(ctx, cx + 8, cy - 12 - frame * 5, .85)
        stroke(ctx, lambda c: c.arc(cx - 4, cy + 8, 26, -.9, .8), GOLD, 4, .75)
    elif name == "dragon_punch":
        _flame(ctx, 7, cy + 2, 74, 39, frame)
        _fist(ctx, cx + 23 + frame, cy, .85)
        _line(ctx, [(9, 19), (37, 19)], GOLD, 2, .8)
        _line(ctx, [(15, 62), (41, 62)], GOLD, 2, .8)
    elif name == "prod":
        reach = [12, 27, 31, 18][frame]
        _line(ctx, [(cx - 6, cy + 4), (cx + reach - 8, cy + 4)], INK, 9)
        _line(ctx, [(cx - 6, cy + 4), (cx + reach - 8, cy + 4)], SKIN, 6)
        _fist(ctx, cx + reach - 4, cy, .65)
        _line(ctx, [(cx + reach, cy - 3), (cx + reach + 12, cy - 3)], INK, 5)
        _line(ctx, [(cx + reach, cy - 3), (cx + reach + 12, cy - 3)], SKIN_LIGHT, 3)
    else:
        # The outer sweep remains visible for the entire strike; a rotating prop
        # shows the windup, contact and follow-through without repainting geometry.
        for radius, color, width in ((43, ORANGE, 5), (37, GOLD, 3)):
            stroke(ctx, lambda c, r=radius: c.arc(cx, cy, r, -1.35, .7), color, width, .8 - frame * .12)
        angle = [-1.0, -.45, .12, .65][frame]
        ctx.save()
        ctx.translate(cx, cy)
        ctx.rotate(angle)
        if name == "bat":
            inked(ctx, lambda c: (c.move_to(-5, -3), c.line_to(17, -4), c.curve_to(25, -10, 42, -10, 43, -4),
                c.line_to(43, 4), c.curve_to(40, 10, 24, 8, 17, 3), c.line_to(-5, 3), c.close_path()), WOOD, 2)
            _line(ctx, [(23, -3), (36, -3)], GOLD, 2)
            _line(ctx, [(-2, -4), (-2, 4)], TEAL, 4)
        else:
            inked(ctx, lambda c: rrect(c, -6, -3, 43, 6, 2), WOOD, 2)
            inked(ctx, lambda c: poly(c, [(24, -7), (33, -21), (44, -17), (47, -4), (38, 5), (27, 6)]), STEEL, 2)
            _line(ctx, [(34, -18), (42, -15), (44, -5), (37, 2)], WHITE, 2)
        _fist(ctx, 1, 5, .65)
        ctx.restore()


def _mine(ctx, mode):
    inked(ctx, lambda c: ellipse(c, 18, 23, 14, 6), STEEL_DARK, 2)
    inked(ctx, lambda c: rrect(c, 8, 15, 20, 9, 4), TEAL, 2)
    _line(ctx, [(11, 18), (25, 18)], STEEL_LIGHT, 1)
    inked(ctx, lambda c: circle(c, 18, 12, 4), {"safe": GOLD, "armed": "#457452", "lit": "#ff6150"}[mode], 1.6)
    if mode == "lit":
        stroke(ctx, lambda c: circle(c, 18, 12, 7), RED, 1.3, .6)
    for x in (8, 28):
        inked(ctx, lambda c, x=x: circle(c, x, 23, 1.5), STEEL_LIGHT, 1)


def _barrel(ctx, cracked):
    inked(ctx, lambda c: rrect(c, 8, 6, 28, 40, 5), RED, 2.4)
    fill(ctx, lambda c: rrect(c, 27, 8, 7, 35, 3), "#a83a3f")
    for y in (13, 37):
        inked(ctx, lambda c, y=y: rrect(c, 6, y, 32, 4, 1.5), STEEL_DARK, 1.4)
    inked(ctx, lambda c: ellipse(c, 22, 7, 13, 3.5), ORANGE, 1.5)
    inked(ctx, lambda c: circle(c, 27, 7, 2), STEEL, 1)
    # A fuel drop, distinct from an ammunition or medical emblem.
    inked(ctx, lambda c: (c.move_to(21, 20), c.curve_to(11, 33, 29, 36, 29, 28), c.curve_to(29, 25, 25, 23, 21, 20)), GOLD, 1.5)
    shine(ctx, 12, 19, 2, 12, 0)
    if cracked:
        _line(ctx, [(29, 10), (24, 18), (30, 24), (24, 33), (27, 42)], INK, 2.5)
        _flame(ctx, 26, 25, 12, 12, 0)


def _turret(ctx, angle, empty=False):
    # A rooted toy sentry: three splayed feet, brass bearing and camera eye.
    for x in (8, 22, 38):
        _line(ctx, [(22, 28), (x, 41)], INK, 6)
        _line(ctx, [(22, 28), (x, 41)], STEEL, 3)
    inked(ctx, lambda c: rrect(c, 12, 25, 21, 8, 3), TEAL, 2)
    inked(ctx, lambda c: circle(c, 22, 24, 6), GOLD, 2)
    ctx.save()
    ctx.translate(22, 19)
    ctx.rotate(math.radians(angle))
    inked(ctx, lambda c: rrect(c, -12, -8, 20, 15, 4), STEEL_DARK if empty else TEAL, 2)
    inked(ctx, lambda c: rrect(c, 6, -3, 14, 6, 1), STEEL_DARK, 1.5)
    inked(ctx, lambda c: circle(c, 1, -3, 3), "#596d71" if empty else "#ff815f", 1)
    shine(ctx, -9, -6, 8, 2, 0)
    for x in (-8, -4):
        _line(ctx, [(x, 3), (x + 1, 3)], STEEL_LIGHT if empty else GOLD, 1.5)
    ctx.restore()


def metadata():
    sprites = {}
    for name, (w, h, ax, ay, count) in SPECS.items():
        sprites[name] = {"size": [w, h], "source_size": [w * 2, h * 2], "anchor": [ax, ay],
            "raster_scale": 2, "frames": count, "pattern": f"ordnance/status/{name}-{{frame}}.png"}
        if name in MIRRORED:
            sprites[name]["left_pattern"] = f"ordnance/status/{name}-left-{{frame}}.png"
    return {"sprites": sprites, "hazards": {
        "mine": {"size": [36, 32], "anchor": [18, 28], "states": ["safe", "armed", "lit"]},
        "barrel": {"size": [44, 52], "anchor": [22, 47], "states": ["whole", "cracked"]},
        "turret": {"size": [48, 48], "anchor": [24, 42], "angles": [-45, 0, 45], "directions": ["right", "left"]}},
        "note": "Original deterministic Cairo source; status overlays anchor at grub feet; all rasters are 2×."}


def build_all():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, (w, h, _ax, _ay, count) in SPECS.items():
        draw = _status if name in {"shield", "frozen", "poison", "boost", "moon"} else _tool if name in {"drill", "torch"} else _melee if name in {"fire_punch", "dragon_punch", "prod", "bat", "axe"} else _effect
        for frame in range(count):
            for left in ((False, True) if name in MIRRORED else (False,)):
                _render(f"{name}-{'left-' if left else ''}{frame}", w, h,
                    lambda c, name=name, frame=frame, draw=draw: draw(c, name, frame), left)
    for state in ("safe", "armed", "lit"):
        _render(f"mine-{state}", 36, 32, lambda c, state=state: _mine(c, state))
    for cracked in (False, True):
        _render(f"barrel-{'cracked' if cracked else 'whole'}", 44, 52, lambda c, cracked=cracked: _barrel(c, cracked))
    for left in (False, True):
        for angle in (-45, 0, 45):
            _render(f"turret-{'left' if left else 'right'}-{angle}", 48, 48,
                lambda c, angle=angle: _turret(c, angle), left)
        _render(f"turret-{'left' if left else 'right'}-empty", 48, 48, lambda c: _turret(c, 0, True), left)
    return metadata()
