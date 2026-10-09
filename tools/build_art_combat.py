"""Directional battle sprites, separate from the illustrative arsenal icons.

Every weapon points along +x on a 128px transparent canvas. Left-hand copies
are mirrored at render time in Cairo, avoiding upside-down stocks in play.
"""
from build_art_core import ART, INK, PAPER, TEAL, GOLD, RED, WHITE, surface
from build_art_icons import I, fill, stroke, rrect, ellipse, circle, poly, rocket

HELD = ("rocket", "homing", "mortar", "shotgun", "rifle", "minigun", "laser",
        "flamethrower", "rope", "blowtorch")
PROJECTILES = ("rocket", "homing", "mortar")


def held(ctx, name):
    # Stock/grip and trigger keep the hand position consistent across families.
    metal, dark = "#9eafb3", "#425761"
    I(ctx, lambda c: poly(c, [(23, 34), (32, 34), (30, 46), (23, 45)]), dark, 2)
    stroke(ctx, lambda c: (c.move_to(31, 35), c.curve_to(39, 34, 38, 43, 31, 42)), INK, 2)
    if name in ("rocket", "homing", "mortar"):
        body = "#659266" if name != "homing" else "#9483b1"
        I(ctx, lambda c: rrect(c, 8, 23, 47, 17, 4), body, 2.4)
        fill(ctx, lambda c: rrect(c, 10, 33, 42, 5, 2), "#3e6256")
        I(ctx, lambda c: rrect(c, 5, 22, 8, 19, 2), dark, 2)
        I(ctx, lambda c: rrect(c, 50, 22, 8, 19, 2), metal, 2)
        fill(ctx, lambda c: ellipse(c, 56, 31.5, 1.7, 6), INK)
        stroke(ctx, lambda c: (c.move_to(16, 26), c.line_to(46, 26)), "#bbd59e", 2)
        I(ctx, lambda c: rrect(c, 26, 18, 12, 5, 2), dark, 1.8)
        if name == "homing":
            I(ctx, lambda c: circle(c, 39, 19, 4), GOLD, 1.8)
        if name == "mortar":
            I(ctx, lambda c: poly(c, [(39, 39), (44, 39), (48, 47), (44, 47)]), metal, 1.5)
    elif name in ("shotgun", "rifle"):
        I(ctx, lambda c: poly(c, [(6, 29), (21, 27), (30, 29), (30, 35), (19, 36), (7, 42), (5, 39)]), "#b78355", 2)
        I(ctx, lambda c: rrect(c, 23, 26, 35, 7, 2), dark, 2)
        stroke(ctx, lambda c: (c.move_to(31, 28), c.line_to(56, 28)), metal, 1.4)
        if name == "shotgun":
            I(ctx, lambda c: rrect(c, 28, 32, 29, 5, 2), metal, 1.8)
            I(ctx, lambda c: rrect(c, 30, 36, 14, 5, 2), "#c1905e", 1.8)
        else:
            I(ctx, lambda c: rrect(c, 19, 17, 22, 7, 3), dark, 1.8)
            I(ctx, lambda c: ellipse(c, 41, 20.5, 2, 3.5), TEAL, 1.5)
            stroke(ctx, lambda c: (c.move_to(24, 24), c.line_to(24, 27), c.move_to(35, 24), c.line_to(35, 27)), INK, 2)
    else:
        body = {"laser": "#75bad5", "flamethrower": "#d2734f", "blowtorch": GOLD,
                "rope": TEAL, "minigun": "#d2734f"}[name]
        I(ctx, lambda c: rrect(c, 9, 23, 28, 16, 5), body, 2.2)
        I(ctx, lambda c: rrect(c, 34, 27, 23, 9, 2), dark, 2)
        stroke(ctx, lambda c: (c.move_to(38, 29), c.line_to(54, 29)), metal, 1.5)
        stroke(ctx, lambda c: (c.move_to(16, 26), c.line_to(28, 26)), WHITE, 1.6)
        if name == "minigun":
            for y in (24, 31, 38):
                I(ctx, lambda c, y=y: rrect(c, 35, y - 2, 22, 4, 1), metal, 1.3)
            I(ctx, lambda c: rrect(c, 48, 21, 4, 20, 1), dark, 1.3)
        elif name == "laser":
            for x in (39, 45, 51):
                I(ctx, lambda c, x=x: rrect(c, x, 23, 3, 16, 1), "#f79cb7", 1)
        elif name == "rope":
            I(ctx, lambda c: circle(c, 21, 34, 8), GOLD, 2)
            stroke(ctx, lambda c: (c.move_to(50, 27), c.line_to(56, 21), c.line_to(59, 26)), metal, 2)
        else:
            I(ctx, lambda c: rrect(c, 8, 19, 10, 25, 4), body, 2)
            fill(ctx, lambda c: circle(c, 56, 31, 1.7), GOLD)


def projectile(ctx, name):
    if name == "mortar":
        I(ctx, lambda c: ellipse(c, 34, 32, 15, 9), "#647759", 2.4)
        I(ctx, lambda c: poly(c, [(20, 28), (10, 22), (12, 42), (20, 36)]), GOLD, 2)
        stroke(ctx, lambda c: (c.move_to(29, 27), c.line_to(39, 27)), "#b4c592", 2)
    else:
        rocket(ctx, 34, 32, 35, 6, 0, PAPER if name == "rocket" else "#ece3fa",
               RED if name == "rocket" else "#ac98cf", TEAL if name == "rocket" else GOLD, exhaust=False)


def build_all():
    for family, names, draw in (("held", HELD, held), ("projectiles", PROJECTILES, projectile)):
        for name in names:
            for left in ((False, True) if family == "held" else (False,)):
                folder = ART / family / ("left" if left else "")
                folder.mkdir(parents=True, exist_ok=True)
                s, ctx = surface(128, 128)
                ctx.scale(2, 2)
                if left:
                    ctx.translate(64, 0)
                    ctx.scale(-1, 1)
                draw(ctx, name)
                s.write_to_png(str(folder / f"{name}.png"))


def metadata():
    return {"size": [128, 128], "facing": "right", "anchor": [64, 64],
            "held": list(HELD), "projectiles": list(PROJECTILES),
            "left_facing": "held/left/{id}.png"}
