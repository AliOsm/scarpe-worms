"""Original mobility equipment and effects, authored in logical pixels at 2×.

Grub overlays use the feet as their anchor. Canopy cords stay fixed on the
handles as the fabric sways; exhaust frames are part of the pack to keep one
image node per equipped tool. No runtime raster transforms or random draws.
"""
from __future__ import annotations

import math

from build_art_core import (
    ART, GOLD, INK, ORANGE, PAPER, STEEL, STEEL_DARK, STEEL_LIGHT, TEAL,
    WHITE, circle, clip_to, ellipse, fill, inked, poly, rrect, save, shine,
    sparkle, stroke, surface,
)

OUT = ART / "ordnance" / "mobility"


def raster(name, width, height, draw, *, left=False):
    canvas, ctx = surface(width * 2, height * 2)
    ctx.scale(2, 2)
    if left:
        ctx.translate(width, 0)
        ctx.scale(-1, 1)
    draw(ctx)
    save(canvas, OUT / f"{name}.png")


def jetpack(ctx, frame=None):
    # At 64px grub size the pack occupies the back, beside the scarf, leaving
    # the face and team headgear completely exposed.
    if frame is not None:
        for nozzle, phase in ((13, frame), (22, (frame + 2) % 4)):
            length = (24, 30, 26, 33)[phase]
            sway = (-2, 1, 3, -1)[phase]

            def flame(c):
                c.move_to(nozzle - 4, 44)
                c.curve_to(nozzle - 7, 52, nozzle + sway - 4, 60, nozzle + sway, 44 + length)
                c.curve_to(nozzle + sway + 1, 58, nozzle + 8, 51, nozzle + 4, 44)
                c.close_path()

            inked(ctx, flame, ORANGE, 1.8)
            fill(ctx, lambda c: poly(c, [(nozzle - 2.8, 45), (nozzle + 3, 45),
                 (nozzle + 1.8, 55), (nozzle + sway, 44 + length * .76), (nozzle - 3, 54)]), GOLD)
            fill(ctx, lambda c: ellipse(c, nozzle, 47.5, 2.1, 5), PAPER)
    # Shoulder strap and two short steel nozzles.
    stroke(ctx, lambda c: (c.move_to(23, 24), c.curve_to(31, 25, 34, 32, 33, 41)), INK, 5)
    stroke(ctx, lambda c: (c.move_to(23, 24), c.curve_to(31, 25, 34, 32, 33, 41)), GOLD, 2.6)
    for x in (9, 18):
        inked(ctx, lambda c, x=x: poly(c, [(x, 39), (x + 7, 39), (x + 8, 46), (x - 1, 46)]), STEEL_DARK, 1.8)
        stroke(ctx, lambda c, x=x: (c.move_to(x, 43), c.line_to(x + 6, 43)), STEEL_LIGHT, 1.5)
    inked(ctx, lambda c: rrect(c, 8, 18, 18, 25, 6), TEAL, 2.2)
    fill(ctx, lambda c: rrect(c, 9.2, 34, 15.7, 7.5, 3), "#2c555d")
    inked(ctx, lambda c: rrect(c, 5.5, 22, 6.5, 18, 3), STEEL, 1.8)
    fill(ctx, lambda c: rrect(c, 6.3, 31, 4.9, 8, 2), STEEL_DARK)
    inked(ctx, lambda c: rrect(c, 8, 27.5, 18, 6, 1.4), ORANGE, 1.5)
    inked(ctx, lambda c: circle(c, 17, 30.5, 3.6), GOLD, 1.4)
    stroke(ctx, lambda c: (c.move_to(17, 30.5), c.line_to(18.4, 28.5)), INK, 1.2)
    inked(ctx, lambda c: rrect(c, 14, 15.5, 7, 4, 1.3), STEEL_DARK, 1.5)
    shine(ctx, 17, 22, 8, 2, rot=0)
    shine(ctx, 8, 26, 4, 1.4, rot=math.pi / 2, alpha=.7)


def parachute(ctx, frame):
    sway = (frame - 3) * 2.2
    # Suspension lines meet the same hands in every pose. The upper cloth and
    # its attachment points move together, with no rotating body-side anchor.
    for x, grip in ((7, 41), (28, 41), (68, 55), (89, 55)):
        stroke(ctx, lambda c, x=x, grip=grip: (c.move_to(x + sway, 44), c.line_to(grip, 87)), INK, 2.7)
        stroke(ctx, lambda c, x=x, grip=grip: (c.move_to(x + sway, 44), c.line_to(grip, 87)), PAPER, 1.15)
    ctx.save()
    ctx.translate(sway, 0)

    def canopy(c):
        c.move_to(7, 44)
        c.curve_to(9, 21, 27, 9, 48, 9)
        c.curve_to(69, 9, 87, 21, 89, 44)
        c.curve_to(82, 39, 75, 39, 68, 44)
        c.curve_to(62, 39, 56, 39, 48, 44)
        c.curve_to(40, 39, 34, 39, 28, 44)
        c.curve_to(21, 39, 14, 39, 7, 44)
        c.close_path()

    inked(ctx, canopy, TEAL, 2.5)
    ctx.save()
    clip_to(ctx, canopy)
    fill(ctx, lambda c: poly(c, [(7, 44), (34, 7), (43, 8), (28, 44)]), ORANGE)
    fill(ctx, lambda c: poly(c, [(53, 8), (62, 7), (89, 44), (68, 44)]), ORANGE)
    fill(ctx, lambda c: (c.move_to(48, 8), c.curve_to(33, 14, 31, 24, 28, 44),
         c.line_to(68, 44), c.curve_to(65, 24, 63, 14, 48, 8)), GOLD)
    fill(ctx, lambda c: (c.move_to(48, 8), c.curve_to(42, 19, 40, 30, 41, 44),
         c.line_to(55, 44), c.curve_to(56, 30, 54, 19, 48, 8)), PAPER)
    fill(ctx, lambda c: (c.move_to(2, 37), c.curve_to(24, 31, 67, 31, 94, 37),
         c.line_to(94, 50), c.line_to(2, 50)), "#273e47", .2)
    for x in (28, 48, 68):
        stroke(ctx, lambda c, x=x: (c.move_to(48, 10), c.curve_to((48 + x) / 2, 17, x, 30, x, 43)), INK, 1.15, .8)
    ctx.restore()
    stroke(ctx, canopy, INK, 2.5)
    inked(ctx, lambda c: ellipse(c, 48, 10.3, 5, 2.2), TEAL, 1.5)
    shine(ctx, 27, 24, 15, 3, rot=-.65, alpha=.72)
    shine(ctx, 62, 23, 9, 2.5, rot=.55, alpha=.65)
    ctx.restore()
    for x in (40, 53):
        inked(ctx, lambda c, x=x: rrect(c, x, 84, 3, 7, 1.3), ORANGE, 1.4)


def grapple_hook(ctx):
    # The shaft points right; the runtime rotates this asset with the rope.
    stroke(ctx, lambda c: (c.move_to(5, 12), c.line_to(19, 12)), INK, 5.4)
    stroke(ctx, lambda c: (c.move_to(5, 12), c.line_to(19, 12)), STEEL, 2.7)
    for sign in (-1, 1):
        def claw(c, sign=sign):
            c.move_to(11, 12)
            c.curve_to(15, 12 + sign * 7.5, 21, 12 + sign * 8.5, 20, 12 + sign * 2.5)
            c.line_to(17, 12 + sign * 4)
        stroke(ctx, claw, INK, 4.4)
        stroke(ctx, claw, STEEL_LIGHT, 2.1)
    inked(ctx, lambda c: circle(c, 5, 12, 2.6), GOLD, 1.5)
    fill(ctx, lambda c: circle(c, 5, 12, 1), INK)


def teleport_ghost(ctx):
    # A hollow, translucent grub-shaped destination without a team colour.
    def body(c):
        c.move_to(16, 46)
        c.curve_to(21, 47, 22, 43, 21, 38)
        c.curve_to(17, 27, 22, 17, 31, 15)
        c.curve_to(44, 11, 50, 20, 48, 29)
        c.curve_to(46, 34, 40, 36, 38, 42)
        c.curve_to(39, 48, 36, 52, 31, 53)
        c.curve_to(25, 54, 18, 52, 16, 46)
        c.close_path()
    fill(ctx, body, "#94e4dc", .32)
    stroke(ctx, body, INK, 3.2, .68)
    stroke(ctx, body, "#bfffee", 1.6, .92)
    for x, y, rx, ry in ((34, 24, 4.3, 6.6), (42, 22.5, 3.8, 6)):
        fill(ctx, lambda c, x=x, y=y, rx=rx, ry=ry: ellipse(c, x, y, rx, ry), WHITE, .62)
        fill(ctx, lambda c, x=x, y=y: ellipse(c, x + 1.2, y + .6, 1.2, 2.1), TEAL, .8)
    stroke(ctx, lambda c: (c.move_to(24, 39), c.curve_to(28, 41, 32, 42, 36, 41),
         c.move_to(24, 44), c.curve_to(27, 46, 31, 47, 35, 46)), "#bfffee", 1.4, .75)
    stroke(ctx, lambda c: ellipse(c, 32, 54.4, 20, 3), INK, 3, .6)
    stroke(ctx, lambda c: ellipse(c, 32, 54.4, 20, 3), "#bfffee", 1.3, .85)


def teleport(ctx, frame, arriving):
    # Rings travel vertically, then scatter into four-point sparks. Incoming
    # rings gather from a wider radius; outgoing rings open and lift away.
    progress = frame / 7
    phase = 1 - progress if arriving else progress
    alpha = .88 * (1 - progress * .86)
    radius = 12 + 24 * phase
    y = 86 - 53 * phase
    if frame < 6:
        fill(ctx, lambda c: poly(c, [(48 - radius * .6, 87), (48 - radius, y),
             (48 + radius, y), (48 + radius * .6, 87)]), "#79e4da", .12 * (1 - progress))
    for band in range(3):
        rx = max(radius - band * 4.2, 7)
        cy = y - band * (13 - 7 * phase)
        color = "#8ae3d9" if band != 1 else "#bcaaee"
        stroke(ctx, lambda c, rx=rx, cy=cy: ellipse(c, 48, cy, rx, max(rx * .25, 2.5)), INK, 4, alpha)
        stroke(ctx, lambda c, rx=rx, cy=cy: ellipse(c, 48, cy, rx, max(rx * .25, 2.5)), color, 2.3, alpha)
        stroke(ctx, lambda c, rx=rx, cy=cy: (c.move_to(48 - rx * .55, cy - rx * .2),
             c.line_to(48 - rx * .15, cy - rx * .25)), WHITE, 1.5, alpha)
    for index in range(4):
        angle = index * math.pi / 2 + .55 + phase * .4
        x = 48 + math.cos(angle) * (radius + 5)
        sy = 51 + math.sin(angle) * (radius + 8)
        sparkle(ctx, x, sy, (3, 4.3, 3.2, 4)[index] * (1 - progress * .5),
                PAPER if index % 2 else GOLD, .9)


def build_all():
    OUT.mkdir(parents=True, exist_ok=True)
    for left in (False, True):
        side = "left" if left else "right"
        raster(f"jetpack-{side}-idle", 64, 80, jetpack, left=left)
        for frame in range(4):
            raster(f"jetpack-{side}-{frame}", 64, 80,
                   lambda ctx, frame=frame: jetpack(ctx, frame), left=left)
    for frame in range(7):
        raster(f"parachute-{frame}", 112, 112,
               lambda ctx, frame=frame: (ctx.translate(8, 0), parachute(ctx, frame)))
    raster("grapple-hook", 24, 24, grapple_hook)
    raster("teleport-ghost", 64, 64, teleport_ghost)
    for arriving in (False, True):
        for frame in range(8):
            raster(f"teleport-{'in' if arriving else 'out'}-{frame}", 96, 112,
                   lambda ctx, frame=frame, arriving=arriving: teleport(ctx, frame, arriving))
    return metadata()


def metadata():
    def spec(pattern, size, anchor, frames=1, fps=0, **extra):
        return {"pattern": f"ordnance/mobility/{pattern}.png", "size": size,
                "source_size": [n * 2 for n in size], "raster_scale": 2,
                "anchor": anchor, "frames": frames, "fps": fps, **extra}
    return {
        "jetpack": spec("jetpack-{facing}-{frame}", [64, 80], [32, 54.4], 4, 15,
                        facing=["left", "right"], idle="ordnance/mobility/jetpack-{facing}-idle.png"),
        "parachute": spec("parachute-{frame}", [112, 112], [56, 105], 7,
                          animation="sway selected from horizontal velocity and tick; handles stay fixed"),
        "grapple_hook": spec("grapple-hook", [24, 24], [12, 12], facing="right"),
        "teleport_ghost": spec("teleport-ghost", [64, 64], [32, 54.4]),
        "teleport_out": spec("teleport-out-{frame}", [96, 112], [48, 87], 8, 16),
        "teleport_in": spec("teleport-in-{frame}", [96, 112], [48, 87], 8, 16),
    }
