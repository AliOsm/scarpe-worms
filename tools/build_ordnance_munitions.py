"""Original game-scale ordnance: ink silhouettes, cel shading and restrained FX.

Coordinates are logical pixels; PNGs are deterministic 2x rasters. Projectile
centres are collision anchors and directional objects point right. No inventory
illustrations or external game's assets are used.
"""
from __future__ import annotations

import math

from build_art_core import (
    ART, GOLD, INK, ORANGE, PAPER, TEAL, WHITE, circle, clip_to, darken,
    ellipse, fill, inked, lighten, poly, rad_grad, rrect, save, shine,
    sparkle, star_pts, stroke, surface,
)

OUT = ART / "ordnance" / "munitions"
PROJECTILES = {
    "rocket": (48, 28), "homing": (48, 28), "mortar": (34, 26),
    "mortar-fragment": (18, 18), "grenade": (30, 34), "cluster": (34, 34),
    "cluster-fragment": (20, 22), "sticky": (34, 34), "dynamite": (32, 40),
    "mega_bomb": (42, 46), "banana": (38, 38), "banana-fragment": (22, 22),
    "holy_bomb": (48, 48), "poison": (34, 38), "airstrike": (36, 26),
    "mine_strike": (30, 28), "napalm": (38, 28), "meteor": (64, 44),
    "earthquake": (32, 34),
}
BLASTS = {
    "blast": ("#fff3b2", "#ffb44d", "#ee7343", "#697879"),
    "shrapnel": ("#fff4c2", "#efd779", "#749e91", "#687b7b"),
    "heavy": ("#fff1b1", "#ffad4b", "#e45f49", "#515d68"),
    "fruit": ("#fffad2", "#ffe675", "#e8ae44", "#969967"),
    "choir": (WHITE, "#fff1bd", "#edcf82", "#b4a9ce"),
    "toxic": ("#e7f5b0", "#bcd786", "#84a56c", "#657c70"),
    "fire": ("#fff0b7", "#ffb456", "#ed7751", "#736675"),
    "meteor": ("#fff1ca", "#ffd16e", "#ed795c", "#5a6572"),
}


def render(name, width, height, draw):
    image, ctx = surface(width * 2, height * 2)
    ctx.scale(2, 2)
    draw(ctx)
    save(image, OUT / f"{name}.png")


def cel(ctx, shape, color, width=1.8):
    inked(ctx, shape, color, width)
    ctx.save()
    clip_to(ctx, shape)
    fill(ctx, lambda c: poly(c, [(-80, 1), (80, 13), (80, 90), (-80, 90)]), darken(color, .25))
    ctx.restore()
    stroke(ctx, shape, INK, width)


def glow(ctx, x, y, radius, color, alpha=.5):
    ctx.set_source(rad_grad(x, y, 0, radius, [(0, color, alpha), (.5, color, alpha * .5), (1, color, 0)]))
    circle(ctx, x, y, radius)
    ctx.fill()


def spark(ctx, x, y, frame, radius=4):
    glow(ctx, x, y, radius + 2, GOLD, .7)
    sparkle(ctx, x, y, radius * (1 + (frame % 2) * .2), "#fff5c4", .7, "#db8246")
    for i in range(2):
        a = frame * 1.4 + i * 2.7
        dx, dy = math.cos(a), math.sin(a)
        stroke(ctx, lambda c: (c.move_to(x + dx * (radius + 1), y + dy * (radius + 1)),
                              c.line_to(x + dx * (radius + 3), y + dy * (radius + 3))), GOLD, 1.2)


def exhaust(ctx, frame, x, y, length=13, height=5):
    end = x - length + (frame % 2) * 2
    inked(ctx, lambda c: poly(c, [(x, y - height), (end + 4, y - height * .5),
                                  (end, y), (end + 4, y + height * .5), (x, y + height)]),
          ORANGE, 1.1, "#cb6845")
    fill(ctx, lambda c: poly(c, [(x, y - height * .5), (end + 4, y), (x, y + height * .5)]), "#fff2bf")


def missile(ctx, name, frame):
    y = 14
    if name != "homing-coast":
        exhaust(ctx, frame, 17, y, 13, 4)
    purple = name.startswith("homing")
    color = "#d9cbed" if purple else PAPER
    fins = "#a188bd" if purple else TEAL
    inked(ctx, lambda c: poly(c, [(17, 11), (13, 5), (22, 9), (22, 19), (13, 23), (17, 17)]), fins, 1.7)
    body = lambda c: (c.move_to(17, 9), c.line_to(31, 9), c.curve_to(37, 9, 40, 12, 43, 14),
                      c.curve_to(39, 17, 37, 19, 31, 19), c.line_to(17, 19), c.close_path())
    cel(ctx, body, color)
    inked(ctx, lambda c: poly(c, [(34, 9.5), (43, y), (34, 18.5)]), "#cc879e" if purple else "#e8735f", 1.2)
    stroke(ctx, lambda c: (c.move_to(21, 11), c.line_to(30, 11)), WHITE, 1.5)
    if purple:
        inked(ctx, lambda c: circle(c, 28, y, 2.7), GOLD, .9)
        fill(ctx, lambda c: circle(c, 28.5, y - .5, 1), WHITE)


def shell(ctx, name, frame):
    width, height = PROJECTILES[name]
    ctx.translate(width / 2, height / 2)
    color = {"mortar": "#8eaa79", "airstrike": "#a7bab1", "napalm": "#df9660"}[name]
    inked(ctx, lambda c: poly(c, [(-8, -3), (-14, -8), (-13, 8), (-8, 3)]), TEAL, 1.6)
    body = lambda c: (c.move_to(-8, -6), c.line_to(4, -6), c.curve_to(10, -6, 13, -3, 14, 0),
                      c.curve_to(13, 3, 10, 6, 4, 6), c.line_to(-8, 6), c.close_path())
    cel(ctx, body, color)
    stroke(ctx, lambda c: (c.move_to(-5, -3), c.line_to(4, -3)), lighten(color, .6), 1.6)
    stroke(ctx, lambda c: (c.move_to(5, -5), c.line_to(5, 5)), GOLD if name != "napalm" else "#f8d595", 2)
    if name == "napalm":
        inked(ctx, lambda c: poly(c, [(-4, 3), (-2, -3), (0, 0), (2, -3), (3, 3)]), ORANGE, .8)


def grenade(ctx, frame, cluster=False, fragment=False):
    width, height = PROJECTILES["cluster-fragment" if fragment else "cluster" if cluster else "grenade"]
    ctx.translate(width / 2, height / 2)
    radius = 6 if fragment else 10
    color = "#efa458" if cluster else "#8eb385"
    cel(ctx, lambda c: ellipse(c, 0, 2, radius, radius + (0 if fragment else 1)), color, 1.5 if fragment else 1.9)
    if cluster:
        for xx in (-4, 4) if not fragment else (0,):
            stroke(ctx, lambda c, xx=xx: (c.move_to(xx, -6 if not fragment else -3), c.line_to(xx, 9 if not fragment else 6)),
                   darken(color, .42), 1.3)
        stroke(ctx, lambda c: (c.move_to(-radius + 2, 2), c.line_to(radius - 2, 2)), INK, 1)
    else:
        for yy in (-3, 3, 8):
            stroke(ctx, lambda c, yy=yy: (c.move_to(-7, yy), c.line_to(7, yy)), "#527864", 1.1)
        stroke(ctx, lambda c: (c.move_to(0, -6), c.line_to(0, 11)), "#527864", 1.2)
    inked(ctx, lambda c: rrect(c, -4, -radius - 2, 8, 4, 1), "#a2b8b8", 1.3)
    if not fragment:
        stroke(ctx, lambda c: (c.move_to(-3, -radius - 3), c.line_to(5, -radius - 3), c.line_to(10, -2)), INK, 3)
        stroke(ctx, lambda c: (c.move_to(-3, -radius - 3), c.line_to(5, -radius - 3), c.line_to(10, -2)), "#d6dfd9", 1.2)
        stroke(ctx, lambda c: circle(c, -7, -radius - 1, 2.5), GOLD, 1.2)
    shine(ctx, -4, -3, 4, 2, -.7)


def sticky(ctx, frame):
    ctx.translate(17, 17)
    inked(ctx, lambda c: poly(c, star_pts(0, 0, 13, 10, 8, .12)), "#ac8bc0", 1.8)
    cel(ctx, lambda c: circle(c, 0, 0, 9), "#d8abd2")
    inked(ctx, lambda c: circle(c, 0, 0, 4), "#f1d8b5", 1.3)
    fill(ctx, lambda c: circle(c, 1, -1, 1.8), ORANGE if frame % 2 else GOLD)
    shine(ctx, -4, -5, 5, 2)


def dynamite(ctx, frame):
    ctx.translate(16, 22)
    stroke(ctx, lambda c: (c.move_to(0, -9), c.curve_to(-5, -14, 5, -15, 5, -12)), INK, 2.8)
    stroke(ctx, lambda c: (c.move_to(0, -9), c.curve_to(-5, -14, 5, -15, 5, -12)), "#d3b691", 1.2)
    cel(ctx, lambda c: rrect(c, -6, -9, 12, 23, 3), "#df725e", 1.8)
    inked(ctx, lambda c: ellipse(c, 0, -8, 5, 2), "#f19d78", 1.2)
    inked(ctx, lambda c: rrect(c, -6, -1, 12, 6, 1), GOLD, 1.2)
    stroke(ctx, lambda c: (c.move_to(-3, -5), c.line_to(-3, -2)), "#ffe0b6", 1.5)
    spark(ctx, 5, -13, frame, 2.8)


def mega_bomb(ctx, frame):
    ctx.translate(21, 25)
    stroke(ctx, lambda c: (c.move_to(0, -12), c.curve_to(-3, -19, 6, -18, 5, -17)), GOLD, 2)
    cel(ctx, lambda c: circle(c, 0, 0, 15), "#597b84", 2.3)
    inked(ctx, lambda c: rrect(c, -5, -16, 10, 5, 2), "#92aab0", 1.5)
    shine(ctx, -6, -7, 8, 3)
    inked(ctx, lambda c: poly(c, star_pts(4, 3, 6, 3, 5)), "#e9bc6e", 1)
    spark(ctx, 5, -18, frame, 2.5)


def banana(ctx, frame, fragment=False):
    width = 22 if fragment else 38
    ctx.translate(width / 2, width / 2)
    if fragment:
        ctx.scale(.57, .57)
    shape = lambda c: (c.move_to(-11, -10), c.curve_to(-6, 5, 3, 9, 12, -3),
                       c.curve_to(15, 11, -7, 20, -13, 1), c.curve_to(-15, -4, -14, -9, -11, -10), c.close_path())
    inked(ctx, shape, "#f4d66b", 1.9)
    stroke(ctx, lambda c: (c.move_to(-11, -4), c.curve_to(-6, 12, 3, 13, 11, 3)), "#d59e47", 2)
    stroke(ctx, lambda c: (c.move_to(-8, 1), c.curve_to(-3, 8, 2, 9, 6, 5)), "#fff4b0", 1.8)
    inked(ctx, lambda c: poly(c, [(-14, -9), (-10, -11), (-11, -14), (-14, -13)]), "#8e7350", 1)
    fill(ctx, lambda c: ellipse(c, 11.3, -.3, 1.5, 2.3), "#806447")


def choir(ctx, frame, charging=False):
    ctx.translate(24, 24)
    glow(ctx, 0, 0, 23, "#fff1b9", (.45 + (frame % 2) * .12) if charging else .22)
    cel(ctx, lambda c: circle(c, 0, 3, 11), "#ebc875", 1.9)
    stroke(ctx, lambda c: ellipse(c, 0, -12, 10, 2.8), INK, 3.4)
    stroke(ctx, lambda c: ellipse(c, 0, -12, 10, 2.8), "#fff0ab", 1.7)
    sparkle(ctx, 1, 3, 7, WHITE, 1.2, "#a77841")
    shine(ctx, -5, -3, 5, 2)
    if charging:
        for i in range(3):
            angle = frame * .42 + i * math.tau / 3
            sparkle(ctx, math.cos(angle) * 17, math.sin(angle) * 17, 2.5, WHITE, .5, GOLD)


def poison(ctx, frame):
    ctx.translate(17, 21)
    for i in range(2):
        t = ((frame + i * 2) % 4) / 4
        fill(ctx, lambda c, t=t: circle(c, 2 + t * 5, -12 - t * 5, 2 + t * 2), "#b7cf81", .65 - t * .4)
    inked(ctx, lambda c: rrect(c, -5, -13, 10, 5, 1), "#a9bec0", 1.5)
    cel(ctx, lambda c: rrect(c, -9, -10, 18, 22, 4), "#9fb16d", 1.8)
    inked(ctx, lambda c: rrect(c, -8, -5, 16, 12, 1), "#ece6b5", 1)
    for xx, yy in ((-3, 1), (3, 1), (0, -3)):
        inked(ctx, lambda c, xx=xx, yy=yy: circle(c, xx, yy, 2), "#779261", .7)
    shine(ctx, -5, -7, 4, 1.5, 0)


def mine(ctx, frame):
    ctx.translate(15, 14)
    inked(ctx, lambda c: poly(c, [(-10, -1), (-8, -7), (8, -7), (10, -1)]), "#a8b19b", 1.5)
    cel(ctx, lambda c: ellipse(c, 0, 2, 11, 7), "#709493", 1.7)
    stroke(ctx, lambda c: (c.move_to(-9, 4), c.line_to(9, 4)), "#bfd1bb", 1.5)
    inked(ctx, lambda c: circle(c, 0, -3, 3), "#e97f63" if frame % 2 else "#d9bc76", 1.3)
    for xx in (-7, 7):
        fill(ctx, lambda c, xx=xx: circle(c, xx, 1, 1), "#dbe1ca")


def meteor(ctx, frame):
    ctx.translate(32, 22)
    glow(ctx, -2, 0, 20, ORANGE, .45)
    exhaust(ctx, frame, -2, 0, 27, 12)
    pts = [(-9, -8), (0, -12), (10, -8), (14, 0), (9, 10), (-2, 12), (-11, 5)]
    cel(ctx, lambda c: poly(c, pts), "#737487", 2)
    stroke(ctx, lambda c: (c.move_to(-7, -6), c.line_to(0, -2), c.line_to(7, -6),
                          c.move_to(0, -2), c.line_to(2, 7), c.line_to(8, 9)), "#f6b564", 1.7)
    fill(ctx, lambda c: poly(c, [(2, -10), (9, -7), (8, -3), (3, -4)]), "#b5aaa7")
    fill(ctx, lambda c: ellipse(c, -4, 4, 3, 2.3), "#4e5965")


def fragment(ctx, frame):
    ctx.translate(9, 9)
    inked(ctx, lambda c: poly(c, [(-5, -3), (1, -6), (5, -1), (2, 5), (-4, 4)]), "#9cad84", 1.5)
    fill(ctx, lambda c: poly(c, [(-3, -2), (1, -4), (2, 0), (-2, 2)]), "#e6d5a0")


def earthquake(ctx, frame):
    cel(ctx, lambda c: rrect(c, 5, 9, 22, 21, 4), "#879b91", 1.8)
    inked(ctx, lambda c: ellipse(c, 16, 12, 7, 4), "#e47e60", 1.5)
    stroke(ctx, lambda c: poly(c, [(9, 24), (13, 18), (17, 26), (23, 20)], False), GOLD, 2)
    stroke(ctx, lambda c: (c.move_to(24, 9), c.line_to(24, 3)), INK, 2)


def bomber(ctx, frame, left=False):
    if left:
        ctx.translate(144, 0)
        ctx.scale(-1, 1)
    inked(ctx, lambda c: poly(c, [(47, 31), (39, 8), (50, 7), (85, 32)]), "#759d9c", 2)
    inked(ctx, lambda c: poly(c, [(25, 36), (12, 17), (22, 15), (39, 36)]), "#e79a67", 2)
    body = lambda c: (c.move_to(16, 32), c.line_to(105, 25), c.curve_to(123, 24, 136, 33, 136, 39),
                      c.curve_to(136, 47, 114, 48, 98, 47), c.line_to(23, 42), c.close_path())
    cel(ctx, body, "#ddd4ac", 2.3)
    inked(ctx, lambda c: poly(c, [(107, 26), (119, 28), (124, 35), (103, 35)]), "#91c5ca", 1.5)
    stroke(ctx, lambda c: (c.move_to(113, 28), c.line_to(115, 35)), INK, 1.1)
    inked(ctx, lambda c: poly(c, [(51, 36), (93, 43), (59, 62), (47, 59)]), "#699596", 2)
    stroke(ctx, lambda c: (c.move_to(53, 56), c.line_to(76, 43)), "#b5d3c6", 2)
    inked(ctx, lambda c: rrect(c, 75, 43, 26, 9, 4), "#d8b36e", 1.5)
    stroke(ctx, lambda c: ellipse(c, 102, 47, 2 + frame % 2, 11 if frame % 2 == 0 else 5), PAPER, 2.2, .8)
    inked(ctx, lambda c: ellipse(c, 101, 47, 3, 2), TEAL, 1)
    for xx in (47, 62, 77):
        inked(ctx, lambda c, xx=xx: circle(c, xx, 32, 2.4), "#7babba", 1)
    inked(ctx, lambda c: poly(c, star_pts(30, 35, 4, 2, 4)), GOLD, .8)
    stroke(ctx, lambda c: (c.move_to(23, 21), c.line_to(19, 22)), PAPER, 2)


def blast(ctx, name, frame):
    core, middle, edge, smoke = BLASTS[name]
    ctx.translate(64, 64)
    t = frame / 7
    if name == "toxic":
        for i in range(7):
            a = i * math.tau / 7 + .4 + math.sin(i * 3.7) * .17
            r = (5 + t * 24) * (1 + math.sin(i * 1.8) * .2)
            cloud = 12 + t * (7 + i % 3 * 2)
            fill(ctx, lambda c, a=a, r=r, cloud=cloud: ellipse(c, math.cos(a) * r, math.sin(a) * r - t * 9, cloud, cloud * .87),
                 middle if i % 2 else edge, (1 - t * .8) * .58)
        return
    if frame < 2:
        radius = 19 + frame * 18
        fill(ctx, lambda c: poly(c, star_pts(0, 0, radius, radius * .45, 10, .12)), core)
        glow(ctx, 0, 0, radius * 1.45, middle, .55)
        return
    if name == "choir":
        radius = 18 + t * 33
        stroke(ctx, lambda c: circle(c, 0, 0, radius), middle, 4 * (1 - t) + 1, 1 - t * .7)
        glow(ctx, 0, 0, radius + 6, core, .55 * (1 - t))
        for i in range(8):
            angle = i * math.tau / 8 + .25
            sparkle(ctx, math.cos(angle) * radius, math.sin(angle) * radius, (1 - t) * 5 + 1.5,
                    core, .8, edge)
        return
    for i in range(8):
        a = i * math.tau / 8 + .2 + math.sin(i * 2.1) * .2
        radius = (9 + t * 25) * (.75 + (i % 3) * .13)
        x, y = math.cos(a) * radius, math.sin(a) * radius - (t - .25) * 12
        r = (19 if name in ("heavy", "meteor") else 16) * (.82 + (i % 3) * .11) * (1 + t * .12)
        color = edge if frame < 4 else smoke
        fill(ctx, lambda c, x=x, y=y, r=r: circle(c, x, y, r), color, 1 - max(t - .5, 0) * 1.5)
        if frame >= 4:
            fill(ctx, lambda c, x=x, y=y, r=r: ellipse(c, x - 2, y - r * .22, r * .76, r * .58),
                 lighten(smoke, .12), (1 - t * .8) * .4)
        if frame < 5:
            fill(ctx, lambda c, x=x, y=y, r=r: circle(c, x * .72, y * .72 - 2, r * .7), middle, .95 - t * .45)
    if frame < 5:
        fill(ctx, lambda c: circle(c, 0, -2, 21 * (1 - t)), core)
        for i in range(5):
            angle = i * 2.4 + .3
            reach = (35 + i % 2 * 12) * (.65 + t * .45)
            dx, dy = math.cos(angle), math.sin(angle)
            stroke(ctx, lambda c, dx=dx, dy=dy, reach=reach:
                   (c.move_to(dx * reach * .7, dy * reach * .7), c.line_to(dx * reach, dy * reach)),
                   middle if name == "shrapnel" else core, 1.7 if name == "shrapnel" else 2.2, 1 - t * .6)
    if name == "fire":
        for i in range(3):
            x = (i - 1) * 20
            def tongue(c, x=x, i=i):
                c.move_to(x - 9, 10)
                c.curve_to(x - 13, -6, x + 2, -13, x + 1, -38 * (1 - t * .3) + i * 3)
                c.curve_to(x + 17, -14, x + 6, -2, x + 9, 10)
                c.close_path()
            fill(ctx, tongue, middle, 1 - t * .82)
    for i in range(6 if name in ("shrapnel", "meteor") else 4):
        a = i * 2.4 + .3
        radius = 28 + t * 25
        x, y = math.cos(a) * radius, math.sin(a) * radius + t * t * 8
        fill(ctx, lambda c, x=x, y=y: poly(c, [(x - 2, y - 2), (x + 3, y), (x, y + 3)]),
             edge if name == "fruit" else middle if name == "meteor" else smoke, 1 - t * .65)


def choir_glow(ctx, frame):
    ctx.translate(48, 48)
    radius = 16 + frame * 5
    glow(ctx, 0, 0, radius + 4, "#fff4c6", .6)
    stroke(ctx, lambda c: ellipse(c, 0, 0, radius, radius * .6), "#f4d58d", 1.5, .85)
    for i in range(4):
        angle = i * math.pi / 2 + frame * .15
        sparkle(ctx, math.cos(angle) * radius, math.sin(angle) * radius * .6, 3, WHITE, .6, GOLD)


def draw_projectile(ctx, name, frame):
    if name in ("rocket", "homing", "homing-coast"):
        missile(ctx, name, frame)
    elif name in ("mortar", "airstrike", "napalm"):
        shell(ctx, name, frame)
    elif name in ("grenade", "cluster", "cluster-fragment"):
        grenade(ctx, frame, cluster=name.startswith("cluster"), fragment=name.endswith("fragment"))
    elif name in ("banana", "banana-fragment"):
        banana(ctx, frame, fragment=name.endswith("fragment"))
    elif name in ("holy_bomb", "holy_bomb-choir"):
        choir(ctx, frame, charging=name.endswith("choir"))
    else:
        {"sticky": sticky, "dynamite": dynamite, "mega_bomb": mega_bomb, "poison": poison,
         "mine_strike": mine, "meteor": meteor, "mortar-fragment": fragment, "earthquake": earthquake}[name](ctx, frame)


def build_all():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, (width, height) in PROJECTILES.items():
        for frame in range(4):
            render(f"{name}-{frame}", width, height, lambda c, n=name, f=frame: draw_projectile(c, n, f))
    for name, size in (("homing-coast", PROJECTILES["homing"]), ("holy_bomb-choir", PROJECTILES["holy_bomb"])):
        for frame in range(4):
            render(f"{name}-{frame}", *size, lambda c, n=name, f=frame: draw_projectile(c, n, f))
    for left in (False, True):
        for frame in range(4):
            render(f"bomber-{'left' if left else 'right'}-{frame}", 144, 72, lambda c, f=frame, left=left: bomber(c, f, left))
    for name in BLASTS:
        for frame in range(8):
            render(f"{name}-burst-{frame}", 128, 128, lambda c, n=name, f=frame: blast(c, n, f))
    for frame in range(6):
        render(f"choir-glow-{frame}", 96, 96, lambda c, f=frame: choir_glow(c, f))
    return metadata()


def metadata():
    return {
        "raster_scale": 2,
        "facing": "right",
        "projectiles": {name: {"pattern": f"ordnance/munitions/{name}-{{frame}}.png", "frames": 4, "fps": 10,
                                "size": list(size), "source_size": [v * 2 for v in size], "anchor": [v / 2 for v in size]}
                        for name, size in PROJECTILES.items()},
        "stages": {"homing": "homing-coast-{frame} before ignition / after burnout",
                   "holy_bomb": "holy_bomb-choir-{frame} during the final chord"},
        "variants": {name: {"pattern": f"ordnance/munitions/{name}-{{frame}}.png", "frames": 4,
                            "size": list(size), "source_size": [v * 2 for v in size], "anchor": [v / 2 for v in size]}
                     for name, size in (("homing-coast", PROJECTILES["homing"]),
                                        ("holy_bomb-choir", PROJECTILES["holy_bomb"]))},
        "bomber": {"pattern": "ordnance/munitions/bomber-{direction}-{frame}.png", "frames": 4, "fps": 12,
                   "size": [144, 72], "source_size": [288, 144], "anchor": [72, 36]},
        "effects": {name: {"pattern": f"ordnance/munitions/{name}-burst-{{frame}}.png", "frames": 8,
                            "fps": 12 if name == "choir" else 16,
                            "size": [128, 128], "source_size": [256, 256], "anchor": [64, 64]}
                    for name in BLASTS},
        "choir_glow": {"pattern": "ordnance/munitions/choir-glow-{frame}.png", "frames": 6, "fps": 10,
                       "size": [96, 96], "source_size": [192, 192], "anchor": [48, 48]},
    }
