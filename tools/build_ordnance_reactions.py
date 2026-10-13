"""Original, text-free character reactions, drawn deterministically at 2×.

Sizes and anchors are logical pixels. Alpha is applied to complete groups so
outlines fade along with their fills. The client supplies motion and burst words.
"""
from __future__ import annotations

import math

from build_art_core import (
    ART, GOLD, INK, ORANGE, WHITE, circle, clip_to, ellipse, fill, inked,
    outline_pass, poly, rrect, save, shine, smooth, sparkle, star_pts, stroke, surface,
)
from build_art_grubs import Pose, draw_mouth, sample_spine, tube_path

OUT = ART / "ordnance" / "reactions"
SPECS = {
    "poof": (96, 96, 48, 64, 7, 16, False,
             "Round smoke puffs and four flying twinkles; frame 6 is fully transparent. Play once at the grub's feet."),
    "ghost": (48, 56, 24, 40, 6, 10, False,
              "Happy white grub, halo and flapping wings. Loop frames 0–3 at 0.85 alpha; 4/5 repeat pose 3 at 0.55/0.28. Client supplies ascent."),
    "bubbles": (32, 48, 16, 44, 6, 10, False,
                "Five differently sized air bubbles rise from the lower anchor and pop; no water surface."),
    "dizzy": (56, 24, 28, 12, 6, 12, True,
              "Three gold stars orbit a flat ellipse. Place the anchor just above a stunned grub's head."),
    "sweat": (16, 20, 8, 10, 3, 8, True,
              "A blue nervous drop slides down and fades. Place beside a low-health grub's face."),
    "burst-pow": (128, 80, 64, 40, 4, 16, False,
                  "Yellow jagged punch/bonk burst with an orange rim; no lettering. Client overlays the word."),
    "burst-boom": (176, 112, 88, 56, 4, 16, False,
                   "Red and hot-orange explosion burst with a calm yellow core; no lettering. Client overlays the word."),
    "burst-splash": (128, 80, 64, 40, 4, 16, False,
                     "Pale aqua splash burst with a blue rim and three droplets; no lettering. Client overlays the word."),
    "burst-spirit": (128, 80, 64, 40, 4, 16, False,
                     "Soft lilac/white cloud farewell burst; no lettering. Client overlays the word."),
}


def _cloud(ctx, puffs):
    paths = [lambda c, p=p: circle(c, *p) for p in puffs]
    outline_pass(ctx, paths, 1.2)
    for path in paths:
        fill(ctx, path, "#bac7d2")
    ctx.save()
    ctx.new_path()
    for path in paths:
        path(ctx)
    ctx.clip()
    for x, y, r in puffs:
        fill(ctx, lambda c, x=x, y=y, r=r: circle(c, x - r * 0.13, y - r * 0.23, r * 0.91), WHITE)
    ctx.restore()


def poof(ctx, frame):
    if frame == 6:
        return
    spread = (6, 13, 21, 27, 31, 34)[frame]
    radius = (9, 14, 14, 11, 7, 3.6)[frame]
    ctx.push_group()
    puffs = []
    for j in range(7):
        a = j * math.tau / 7 - 0.3 + (0.04, -0.09, 0.1, 0, -0.12, 0.07, -0.06)[j]
        distance = spread * (0.94, 1.03, 0.93, 1.04, 0.95, 1, 0.88)[j]
        x, y = 48 + math.cos(a) * distance, 49 + math.sin(a) * distance * 0.75 - frame * 1.4
        r = radius * (0.82, 1.05, 0.93, 0.88, 1.08, 0.8, 1.01)[j]
        puffs.append((x, y, r))
        if frame >= 3:
            # Broken, lopsided wisps instead of a perfectly beaded smoke ring.
            puffs.append((x - r * 0.75, y + r * 0.2, r * 0.55))
    if frame < 3:
        puffs.append((48, 49 - frame * 1.4, radius * 1.1))
    _cloud(ctx, puffs)
    for j, a in enumerate((-2.6, -1.2, 0.25, 2.1)):
        distance = 21 + frame * 4.2
        x, y = 48 + math.cos(a) * distance, 47 + math.sin(a) * distance - frame * 0.9
        sparkle(ctx, x, y, (3.5, 4, 3.5, 3, 2.5, 1.6)[frame], GOLD if j % 2 else WHITE, 1.1)
    ctx.pop_group_to_source()
    ctx.paint_with_alpha((1, 1, 0.96, 0.82, 0.58, 0.28)[frame])


def _wing(ctx, x, y, side, flap):
    ctx.save()
    ctx.translate(x, y)
    ctx.scale(side, 1)
    ctx.rotate(flap)
    path = lambda c: (c.move_to(0, 1), c.curve_to(3, -1, 4, -8, 9, -9),
                      c.curve_to(11, -9, 9, -4, 7, -2),
                      c.curve_to(12, -6, 13, -1, 8, 2),
                      c.curve_to(12, 1, 11, 5, 6, 5),
                      c.curve_to(3, 5, 1, 3, 0, 1), c.close_path())
    inked(ctx, path, "#d5e3ed", 1.5)
    ctx.save()
    clip_to(ctx, path)
    fill(ctx, lambda c: ellipse(c, 5, -4, 4.2, 7, 0.45), WHITE)
    ctx.restore()
    stroke(ctx, lambda c: (c.move_to(3, 2), c.line_to(7, -1)), "#9eafc7", 1)
    ctx.restore()


def ghost(ctx, frame):
    pose_frame = min(frame, 3)
    bob = (0, -1.3, 0, 1.0)[pose_frame]
    flap = (-0.35, 0.1, 0.45, 0.1)[pose_frame]
    ctx.push_group()
    ctx.save()
    ctx.translate(0, bob)
    _wing(ctx, 17, 28, -1, flap)
    _wing(ctx, 32, 28, 1, flap)
    samples = sample_spine([(15, 42), (16, 39), (21, 37), (25, 33), (27, 28), (28, 24), (28, 21)],
                           [1.3, 3.0, 4.8, 6.7, 6.6, 6.1, 8.5])
    body = tube_path(samples)
    outline_pass(ctx, [body], 0.9)
    fill(ctx, body, "#d5e3ed")
    ctx.save()
    clip_to(ctx, body)
    fill(ctx, tube_path(samples, scale=0.87, shift=(0.5, -0.8)), WHITE)
    ctx.restore()
    for x, y in ((20, 36), (24, 32)):
        stroke(ctx, lambda c, x=x, y=y: (c.move_to(x - 1.8, y), c.curve_to(x, y + 1.6, x + 2, y + 1.6, x + 3, y)),
               "#b8cddc", 1.0)
    ctx.save()
    ctx.translate(28, 21)
    ctx.scale(8.5 / 13.5, 8.5 / 13.5)
    for x, y, rx, ry in ((1.0, -6.0, 6, 7.6), (9.6, -4.6, 6.8, 8.5)):
        stroke(ctx, lambda c, x=x, y=y, rx=rx, ry=ry: (
            c.move_to(x - rx * 0.8, y + ry * 0.25),
            c.curve_to(x - rx * 0.4, y - ry * 0.75, x + rx * 0.4, y - ry * 0.75, x + rx * 0.8, y + ry * 0.25)), INK, 2.3)
    draw_mouth(ctx, Pose([], [], mouth="smile"), 2.1)
    ctx.restore()
    stroke(ctx, lambda c: ellipse(c, 27, 6, 6.6, 2.1), INK, 3.3)
    stroke(ctx, lambda c: ellipse(c, 27, 6, 6.6, 2.1), GOLD, 1.8)
    shine(ctx, 25, 4.1, 4, 0.8, 0)
    ctx.restore()
    ctx.pop_group_to_source()
    ctx.paint_with_alpha(0.85 if frame < 4 else (0.55 if frame == 4 else 0.28))


def bubbles(ctx, frame):
    for j, (offset, radius, lead) in enumerate(((-6, 2.5, 0), (5, 3.6, 1), (0, 2.2, 0), (-7, 3.1, 2), (7, 1.8, 1))):
        age = frame + lead
        rise = min(age, 5) / 5
        x = 16 + offset * (0.65 + 0.35 * rise) + 0.6 * math.sin(j + frame)
        y = 43 - j * 3.8 - rise * 22
        if age > 6:
            continue
        if age >= 5:
            for a in (0, math.pi / 2, math.pi, 3 * math.pi / 2):
                r0, r1 = radius * 0.8, radius * 1.35
                stroke(ctx, lambda c, a=a: (
                    c.move_to(x + math.cos(a) * r0, y + math.sin(a) * r0),
                    c.line_to(x + math.cos(a) * r1, y + math.sin(a) * r1)), "#d7f7fa", 1.2, 0.85 if age == 5 else 0.35)
        else:
            r = radius * (0.65 + rise * 0.35)
            inked(ctx, lambda c: circle(c, x, y, r), "#78bdcf", 1.15)
            fill(ctx, lambda c: circle(c, x - r * 0.12, y - r * 0.15, r * 0.75), "#d7f7fa", 0.7)
            shine(ctx, x - r * 0.3, y - r * 0.4, r * 0.9, 0.8, -0.5)


def dizzy(ctx, frame):
    stroke(ctx, lambda c: ellipse(c, 28, 12, 20, 5), GOLD, 1.1, 0.45)
    # A third of a revolution closes the loop because the three stars exchange
    # places. Advancing a full turn in six frames would alias to two pictures.
    angles = [frame * math.tau / 18 + j * math.tau / 3 for j in range(3)]
    for a in sorted(angles, key=math.sin):
        x, y = 28 + math.cos(a) * 20, 12 + math.sin(a) * 5
        r = 4.2 + math.sin(a) * 0.5
        inked(ctx, lambda c, x=x, y=y, r=r, a=a: poly(c, star_pts(x, y, r, r * 0.48, rot=a - math.pi / 2)), "#ffd56c", 1.05)
        fill(ctx, lambda c, x=x, y=y: ellipse(c, x - 0.5, y - 0.8, 0.55, 0.4), WHITE)


def _drop(ctx, x, y, radius=3, height=4.5):
    path = lambda c: (c.move_to(x, y - height),
                      c.curve_to(x + radius * 1.6, y, x + radius, y + height * 0.8, x, y + height * 0.8),
                      c.curve_to(x - radius, y + height * 0.8, x - radius * 1.6, y, x, y - height), c.close_path())
    inked(ctx, path, "#68aecb", 1.2)
    ctx.save()
    clip_to(ctx, path)
    fill(ctx, lambda c: ellipse(c, x - 0.5, y - 0.6, radius * 0.78, height * 0.78), "#b9edf1")
    ctx.restore()
    shine(ctx, x - radius * 0.35, y, 0.9, height * 0.6, 0.35)


def sweat(ctx, frame):
    ctx.push_group()
    _drop(ctx, 7.5 + frame * 0.4, 6.5 + frame * 2.7, 3.1, 4.3)
    ctx.pop_group_to_source()
    ctx.paint_with_alpha((1, 0.9, 0.65)[frame])


BURST_POINTS = [(-0.42, -0.03), (-0.35, -0.14), (-0.40, -0.28), (-0.23, -0.23),
                (-0.19, -0.36), (-0.07, -0.26), (0.03, -0.36), (0.12, -0.26),
                (0.28, -0.34), (0.27, -0.20), (0.40, -0.23), (0.36, -0.08),
                (0.42, 0.03), (0.35, 0.13), (0.39, 0.29), (0.21, 0.23),
                (0.16, 0.36), (0.06, 0.26), (-0.06, 0.35), (-0.15, 0.26),
                (-0.30, 0.33), (-0.28, 0.20), (-0.41, 0.23), (-0.36, 0.06)]


def _spirit_path(ctx, w, h):
    ctx.save()
    ctx.scale(w * 0.4, h * 0.33)
    ctx.move_to(-0.94, 0.07)
    ctx.curve_to(-1.13, -0.35, -0.94, -0.77, -0.66, -0.65)
    ctx.curve_to(-0.66, -1.1, -0.2, -1.19, -0.05, -0.82)
    ctx.curve_to(0.19, -1.18, 0.6, -1.05, 0.59, -0.67)
    ctx.curve_to(1.01, -0.9, 1.14, -0.32, 0.96, 0.02)
    ctx.curve_to(1.14, 0.46, 0.87, 0.99, 0.59, 0.7)
    ctx.curve_to(0.57, 1.16, 0.08, 1.15, -0.08, 0.83)
    ctx.curve_to(-0.39, 1.18, -0.84, 0.91, -0.76, 0.56)
    ctx.curve_to(-1.1, 0.7, -1.13, 0.27, -0.94, 0.07)
    ctx.close_path()
    ctx.restore()


def burst(ctx, name, frame):
    w, h = SPECS[name][:2]
    scale = (0.45, 1.15, 1.0, 0.97)[frame]
    ctx.save()
    ctx.translate(w / 2, h / 2)
    ctx.rotate(math.radians(-3 + (3 if frame == 3 else 0)))
    ctx.scale(scale, scale)
    if name == "burst-spirit":
        shape = lambda c: _spirit_path(c, w, h)
        rim, core = "#c3afd9", "#faf4ff"
    else:
        points = [(x * w, y * h) for x, y in BURST_POINTS]
        shape = (lambda c: smooth(c, points, tension=0.2)) if name == "burst-splash" else (lambda c: poly(c, points))
        rim, core = {"burst-pow": (ORANGE, "#ffe28a"), "burst-boom": ("#e2524a", "#ffdc76"),
                     "burst-splash": ("#599fc5", "#c3f0ef")}[name]
    inked(ctx, shape, rim, 2.8)
    ctx.save()
    ctx.scale(0.93, 0.85)
    fill(ctx, shape, ORANGE if name == "burst-boom" else core)
    if name == "burst-boom":
        ctx.scale(0.94, 0.86)
        fill(ctx, shape, core)
    ctx.restore()
    # A flat central word area, >=65% of canvas width at normal scale. All
    # decorative glints/droplets stay outside it; lettering belongs to the UI.
    fill(ctx, lambda c: rrect(c, -w * 0.33, -h * 0.115, w * 0.66, h * 0.23, h * 0.05), core)
    if name == "burst-splash":
        for x, y in ((-0.39, -0.33), (0.39, 0.31), (0.30, -0.35)):
            _drop(ctx, x * w, y * h, 1.8, 3.0)
    else:
        shine(ctx, -w * 0.19, -h * 0.21, w * 0.12, 1.7, -0.12, 0.7)
    ctx.restore()


def metadata():
    result = {}
    for name, (w, h, ax, ay, count, fps, loop, note) in SPECS.items():
        result[name] = {"frames": count, "size": [w, h], "anchor": [ax, ay], "fps": fps,
                        "pattern": f"ordnance/reactions/{name}-{{frame}}.png", "raster_scale": 2,
                        "source_size": [w * 2, h * 2], "loop": loop, "note": note}
        if name.startswith("burst-"):
            result[name]["scales"] = [0.45, 1.15, 1.0, 0.97]
            result[name]["rotations"] = [-3, -3, -3, 0]
            result[name]["text_safe_size"] = [round(w * 0.65, 2), round(h * 0.22, 2)]
    result["poof"]["transparent_frames"] = [6]
    result["ghost"]["loop_frames"] = [0, 1, 2, 3]
    result["ghost"]["alpha"] = [0.85, 0.85, 0.85, 0.85, 0.55, 0.28]
    return result


def build_all():
    OUT.mkdir(parents=True, exist_ok=True)
    draw = {"poof": poof, "ghost": ghost, "bubbles": bubbles, "dizzy": dizzy, "sweat": sweat}
    for name, (w, h, _ax, _ay, count, _fps, _loop, _note) in SPECS.items():
        for frame in range(count):
            s, ctx = surface(w * 2, h * 2)
            ctx.scale(2, 2)
            if name.startswith("burst-"):
                burst(ctx, name, frame)
            else:
                draw[name](ctx, frame)
            save(s, OUT / f"{name}-{frame}.png")
    return metadata()
