"""Original procedural sprites for sheep, super sheep, mole, skunk and cows.

Sources are authored in a 64px logical canvas and rendered at 2x.  Every pose
has a right-facing source and a pre-mirrored left-facing copy, keeping runtime
image nodes cacheable and upright while a critter changes direction.
"""
from __future__ import annotations

import math
from pathlib import Path

from build_art_core import ART, GOLD, INK, ORANGE, PAPER, TEAL, WHITE
from build_art_core import ellipse, fill, inked, poly, rrect, save, surface, stroke

OUT = ART / "ordnance" / "critters"
S = 2
LW = 1.55
WOOL, WOOL_SHADE = "#f7f2e6", "#d6d3c7"
FUR, FUR_DARK, FUR_LIGHT = "#9d704f", "#6e4939", "#c29367"
SKUNK, SKUNK_DARK, SKUNK_LIGHT = "#71808a", "#344752", "#bdc8c4"
GAS, HORN, SPOT = "#b7d97f", "#e7c58a", "#57433e"


def I(c, path, colour, width=LW):
    inked(c, path, colour, width, INK)


def shade(c, x, y, rx, ry, colour):
    fill(c, lambda p: ellipse(p, x + rx * .14, y + ry * .2, rx * .92, ry * .78), colour, .68)


def shine(c, x, y, rx=3.2, ry=1.2, angle=-.5):
    fill(c, lambda p: ellipse(p, x, y, rx, ry, angle), WHITE, .72)


def eye(c, x, y, r=1.9):
    I(c, lambda p: ellipse(p, x, y, r, r * 1.14), WHITE, .8)
    fill(c, lambda p: ellipse(p, x + .4, y + .1, r * .37, r * .53), INK)
    fill(c, lambda p: ellipse(p, x + .05, y - .3, r * .11, r * .16), WHITE)


def leg(c, x, y, lean=0, colour=FUR, hoof=FUR_DARK, lifted=False):
    end = y - (4 if lifted else 0)
    I(c, lambda p: (p.move_to(x - 1.45, y - 1), p.line_to(x - 1.25 + lean, end - 5),
                    p.curve_to(x - 1 + lean, end - 7, x + 2 + lean, end - 7, x + 2.1 + lean, end - 4),
                    p.line_to(x + 2.35 + lean, end), p.line_to(x - 1.7 + lean, end), p.close_path()), colour)
    fill(c, lambda p: rrect(p, x - 2.35 + lean, end - .9, 5.2, 1.9, .75), hoof)


def sheep(c, phase=0, state="walk"):
    bob = -1.2 * math.sin(phase * math.tau) if state == "walk" else (-2.5 + phase * 1.2 if state == "hop" else 1)
    stride = math.sin(phase * math.tau)
    # The body clears the feet so the four-frame gait remains legible at 64px.
    bx, by = 31 + .45 * math.cos(phase * math.tau), 36.2 + bob
    leg(c, 23, 48.8 + bob, -1.5 * stride, FUR, FUR_DARK, stride > .35)
    leg(c, 35, 49 + bob, 1.7 * stride, FUR, FUR_DARK, stride < -.35)
    I(c, lambda p: (ellipse(p, bx, by, 15.4, 10.6), ellipse(p, bx - 11.2, by + 1.3, 6, 7.1), ellipse(p, bx + 10.3, by - .8, 6, 8)), WOOL, 1.8)
    shade(c, bx + 1, by + 1, 14.5, 9.6, WOOL_SHADE)
    fill(c, lambda p: ellipse(p, bx - 1.8, by - 2.2, 12.9, 7.8), WOOL, .92)
    stroke(c, lambda p: (p.move_to(bx - 8, by - 1), p.curve_to(bx - 10, by - 5, bx - 5, by - 7, bx - 4, by - 4),
                        p.move_to(bx + 1, by + 1), p.curve_to(bx - 1, by - 2, bx + 3, by - 4, bx + 5, by - 1)), WOOL_SHADE, 1.1)
    shine(c, bx - 7, by - 6.6, 4.6, 1.6)
    hx, hy = 47.3, 34.2 + bob
    I(c, lambda p: ellipse(p, hx, hy, 8, 7.7), WOOL, 1.55)
    shade(c, hx + 1, hy + 1, 7, 6.8, WOOL_SHADE)
    fill(c, lambda p: ellipse(p, hx - 1.8, hy - 2.4, 5.6, 4.8), WOOL, .93)
    I(c, lambda p: (p.move_to(43, 28.7 + bob), p.curve_to(39.8, 25, 41.1, 23.9, 44.5, 26.8), p.line_to(46.1, 29.4 + bob), p.close_path()), WOOL_SHADE, 1.05)
    eye(c, 49.3, 32 + bob, 2)
    fill(c, lambda p: ellipse(p, 52.8, 37.6 + bob, 1.45, 1), FUR_DARK)
    I(c, lambda p: (p.move_to(43.6, 29.6 + bob), p.curve_to(46, 25.8 + bob, 49.4, 27.1 + bob, 49.3, 30 + bob), p.curve_to(47.4, 28.4 + bob, 46, 29.6 + bob, 43.6, 29.6 + bob), p.close_path()), WHITE, 1)
    stroke(c, lambda p: (p.move_to(50.3, 38.7 + bob), p.curve_to(48.8, 40 + bob, 47, 39.8 + bob, 46.3, 38.9 + bob)), FUR_DARK, .75)


def super_sheep(c, phase=0, state="walk"):
    if state != "flying":
        sheep(c, phase, state)
        I(c, lambda p: (p.move_to(35.8, 35), p.curve_to(29.5, 31.4, 24, 32.6, 20.5, 36.6), p.line_to(26.6, 42.3), p.curve_to(31.8, 39.1, 35.1, 39.8, 38.3, 41.3), p.close_path()), "#e2524a", 1.15)
        fill(c, lambda p: ellipse(p, 36.6, 35.2, 1.5, 1.5), GOLD)
        return
    bx, by = 35, 34
    I(c, lambda p: ellipse(p, bx, by, 12.6, 6.6), WOOL, 1.65)
    shade(c, bx + 1, by + 1, 11.5, 5.7, WOOL_SHADE)
    fill(c, lambda p: ellipse(p, bx - 2.4, by - 1.9, 10.4, 4.6), WOOL, .95)
    shine(c, 29.3, 30.1, 3.4, 1.1)
    wave = math.sin(phase * math.tau) * 1.4
    I(c, lambda p: (p.move_to(27.4, 32 + wave), p.curve_to(21.4, 27 + wave, 13.6, 27 - wave, 7.8, 32), p.curve_to(13.3, 33, 18.5, 37 - wave, 23.6, 39.8), p.curve_to(25, 37, 26, 34.3 + wave, 27.4, 32 + wave), p.close_path()), "#e2524a", 1.35)
    fill(c, lambda p: poly(p, [(9, 31.9), (15.2, 31 - wave), (20.5, 35.9), (23.6, 39.8), (19, 37.2)]), ORANGE, .8)
    hx, hy = 45.5, 31.6
    I(c, lambda p: ellipse(p, hx, hy, 6.8, 6), WOOL, 1.45)
    eye(c, 47, 30, 1.7)
    I(c, lambda p: (p.move_to(42, 26.6), p.curve_to(42.8, 22.9, 46.2, 24.2, 47.2, 26.6), p.close_path()), GOLD, 1)
    fill(c, lambda p: ellipse(p, 50.1, 34, 1.2, .8), FUR_DARK)
    fill(c, lambda p: ellipse(p, 26, 33.2, 1.7, 1.7), GOLD)


def mole(c, phase=0, state="walk"):
    bob = -math.sin(phase * math.tau) if state == "walk" else (-2.6 if state in ("dive", "dig", "hop") else 1 if state == "fall" else 0)
    stride = math.sin(phase * math.tau)
    bx, by = 31.5 + .45 * math.cos(phase * math.tau), 37 + bob
    leg(c, 24.5, 49.3 + bob, -1.4 * stride, FUR_DARK, INK, stride > .25)
    leg(c, 35.2, 49.3 + bob, 1.5 * stride, FUR_DARK, INK, stride < -.25)
    I(c, lambda p: ellipse(p, bx, by, 14.8, 9.8), FUR, 1.8)
    shade(c, bx + 1.2, by + 1.3, 13.7, 8.6, FUR_DARK)
    fill(c, lambda p: ellipse(p, bx - 2.8, by - 2.6, 11, 6.9), FUR_LIGHT, .88)
    shine(c, bx - 6.5, by - 6, 3.5, 1.3)
    hx, hy = 45, 37 + bob
    I(c, lambda p: ellipse(p, hx, hy, 8.2, 7.5), FUR, 1.5)
    shade(c, hx + 1, hy + 1, 7.2, 6.6, FUR_DARK)
    fill(c, lambda p: ellipse(p, hx - 2, hy - 2.3, 5.3, 4.6), FUR_LIGHT, .9)
    fill(c, lambda p: ellipse(p, 52.2, 38.8 + bob, 2, 1.5), INK)
    eye(c, 46, 34.5 + bob, 1.85)
    stroke(c, lambda p: (p.move_to(48.4, 41 + bob), p.curve_to(46.2, 42.1 + bob, 44, 41 + bob, 43.4, 40.4 + bob)), INK, .8)
    I(c, lambda p: (p.move_to(38, 31 + bob), p.curve_to(40.2, 24.8 + bob, 49.6, 24.8 + bob, 51.5, 31.2 + bob), p.curve_to(47.2, 29.7 + bob, 42.1, 29.8 + bob, 38, 31 + bob), p.close_path()), GOLD, 1.2)
    fill(c, lambda p: ellipse(p, 45, 28.5 + bob, 2.2, 1), WHITE, .85)
    if state == "dig":
        swing = math.sin(phase * math.tau) * 2
        stroke(c, lambda p: (p.move_to(49.5, 43 + bob), p.line_to(57 + swing, 49 + bob)), "#8e5a33", 1.65)
        I(c, lambda p: (p.move_to(54 + swing, 46.8 + bob), p.curve_to(58 + swing, 45.3 + bob, 60 + swing, 48.6 + bob, 58.2 + swing, 51.4 + bob), p.line_to(53 + swing, 49.7 + bob), p.close_path()), "#d5e0e2", 1.05)
        fill(c, lambda p: ellipse(p, 55.5 + swing, 43.2 + bob, 1.6, 1.1), GOLD, .9)


def skunk(c, phase=0, state="walk"):
    bob = -.9 * math.sin(phase * math.tau) if state == "walk" else (-2.2 if state == "hop" else 1 if state == "fall" else 0)
    stride = math.sin(phase * math.tau)
    bx, by = 31.3 + .45 * math.cos(phase * math.tau), 37 + bob
    I(c, lambda p: (p.move_to(21.5, 39.5 + bob), p.curve_to(13, 31 + bob, 9, 21.5 + bob, 15, 18.2 + bob), p.curve_to(22, 20 + bob, 24.8, 29.5 + bob, 27, 35 + bob), p.close_path()), SKUNK_DARK, 1.8)
    stroke(c, lambda p: (p.move_to(15, 21.3 + bob), p.curve_to(18.2, 22 + bob, 20.8, 26.4 + bob, 21.4, 29.7 + bob)), WHITE, 2)
    leg(c, 24.5, 49.1 + bob, -1.4 * stride, SKUNK_DARK, INK, stride > .3)
    leg(c, 35, 49.1 + bob, 1.6 * stride, SKUNK_DARK, INK, stride < -.3)
    I(c, lambda p: ellipse(p, bx, by, 14.7, 9.6), SKUNK, 1.8)
    shade(c, bx + 1, by + 1.4, 13.6, 8.4, SKUNK_DARK)
    I(c, lambda p: (p.move_to(25.6, 31 + bob), p.curve_to(30.5, 28.6 + bob, 35.5, 29.2 + bob, 39, 34 + bob), p.line_to(35.4, 38 + bob), p.curve_to(31.2, 34.3 + bob, 28.2, 34.2 + bob, 25.6, 35.1 + bob), p.close_path()), WHITE, .9)
    shine(c, bx - 6, by - 5.8, 3.7, 1.2)
    hx, hy = 45.8, 36.2 + bob
    I(c, lambda p: ellipse(p, hx, hy, 7.3, 7), SKUNK, 1.45)
    shade(c, hx + 1, hy + 1, 6.4, 6.1, SKUNK_DARK)
    fill(c, lambda p: ellipse(p, hx - 1.4, hy - 2, 4.9, 4.1), SKUNK_LIGHT, .7)
    eye(c, 47.8, 34.2 + bob, 1.8)
    fill(c, lambda p: ellipse(p, 51.8, 38.7 + bob, 1.8, 1.25), INK)
    if state == "spray":
        # Skunks spray from the raised tail, behind the runner; this also keeps
        # the cloud visually separate from the face at small draw sizes.
        wave = math.sin(phase * math.tau) * 1.4
        stroke(c, lambda p: (p.move_to(16.8, 27.0), p.line_to(8.4, 25.0 + wave)), "#8fd0b3", 1.4)
        for x, y, r in ((10.0, 24.4 + wave, 2.0), (6.8, 21.8 + wave, 2.4), (8.0, 28.3 + wave, 1.6)):
            I(c, lambda p, x=x, y=y, r=r: (ellipse(p, x, y, r, r * .8), ellipse(p, x + r * .8, y + 1, r * .55, r * .45)), GAS, .9)


def cow(c, phase=0, state="walk"):
    bob = -.75 * math.sin(phase * math.tau) if state == "walk" else (-2.4 if state == "hop" else 1 if state == "fall" else 0)
    stride = math.sin(phase * math.tau)
    bx, by = 31 + .45 * math.cos(phase * math.tau), 36 + bob
    leg(c, 22.6, 49.4 + bob, -1.4 * stride, PAPER, INK, stride > .3)
    leg(c, 35, 49.4 + bob, 1.5 * stride, PAPER, INK, stride < -.3)
    I(c, lambda p: ellipse(p, bx, by, 16, 10.4), PAPER, 1.8)
    shade(c, bx + 1.4, by + 1.5, 14.8, 9.3, "#d9d1c4")
    fill(c, lambda p: ellipse(p, bx - 2.2, by - 2.3, 12.7, 7.6), PAPER, .9)
    fill(c, lambda p: ellipse(p, 25, 36.7 + bob, 3.8, 3.1), SPOT, .95)
    fill(c, lambda p: ellipse(p, 36.5, 43.3 + bob, 4.5, 2.5), SPOT, .92)
    shine(c, bx - 7, by - 6.8, 4.4, 1.35)
    hx, hy = 46.8, 36.8 + bob
    I(c, lambda p: ellipse(p, hx, hy, 8.2, 7.6), PAPER, 1.55)
    shade(c, hx + 1.1, hy + 1.1, 7.2, 6.8, "#d9d1c4")
    fill(c, lambda p: ellipse(p, 46.2, 35 + bob, 4.5, 3.8), PAPER, .9)
    eye(c, 48.5, 34.4 + bob, 1.8)
    fill(c, lambda p: ellipse(p, 53, 39 + bob, 2, 1.45), INK)
    I(c, lambda p: (p.move_to(42, 30.5 + bob), p.curve_to(39.2, 25.2 + bob, 40.4, 23.1 + bob, 43.5, 27 + bob), p.line_to(44.7, 31.1 + bob), p.close_path()), HORN, 1)
    I(c, lambda p: (p.move_to(48.4, 29.5 + bob), p.curve_to(52.2, 24.6 + bob, 54, 26 + bob, 51.5, 30.7 + bob), p.close_path()), HORN, 1)
    stroke(c, lambda p: (p.move_to(40.5, 41.1 + bob), p.curve_to(46, 43.4 + bob, 51, 42 + bob, 53.6, 40.4 + bob)), "#e2524a", 1.05)
    fill(c, lambda p: ellipse(p, 41.7, 40.8 + bob, 1.3, 1.3), GOLD)


def render(path: Path, draw, mirror=False):
    s, c = surface(128, 128)
    c.scale(S, S)
    if mirror:
        c.translate(64, 0)
        c.scale(-1, 1)
    draw(c)
    save(s, path)


def poses(weapon):
    if weapon == "sheep":
        return [(f"sheep-walk-{i}", lambda c, i=i: sheep(c, i / 4, "walk")) for i in range(4)] + [(f"sheep-hop-{i}", lambda c, i=i: sheep(c, i / 2, "hop")) for i in range(2)] + [("sheep-fall-0", lambda c: sheep(c, .1, "fall"))]
    if weapon == "super_sheep":
        return ([(f"super_sheep-walk-{i}", lambda c, i=i: super_sheep(c, i / 4, "walk")) for i in range(4)] +
                [("super_sheep-hop-0", lambda c: super_sheep(c, 0, "hop")), ("super_sheep-fall-0", lambda c: super_sheep(c, 0, "fall"))] +
                [(f"super_sheep-flying-{i}", lambda c, i=i: super_sheep(c, .25 + i / 2, "flying")) for i in range(2)])
    if weapon == "mole":
        return [(f"mole-walk-{i}", lambda c, i=i: mole(c, i / 4, "walk")) for i in range(4)] + [("mole-hop-0", lambda c: mole(c, 0, "hop")), ("mole-fall-0", lambda c: mole(c, 0, "fall")), ("mole-dive-0", lambda c: mole(c, 0, "dive")), ("mole-dig-0", lambda c: mole(c, .25, "dig")), ("mole-dig-1", lambda c: mole(c, .75, "dig"))]
    if weapon == "skunk":
        return ([(f"skunk-walk-{i}", lambda c, i=i: skunk(c, i / 4, "walk")) for i in range(4)] +
                [("skunk-hop-0", lambda c: skunk(c, 0, "hop")), ("skunk-fall-0", lambda c: skunk(c, 0, "fall"))] +
                [(f"skunk-spray-{i}", lambda c, i=i: skunk(c, .25 + i / 2, "spray")) for i in range(2)])
    return [(f"cow-walk-{i}", lambda c, i=i: cow(c, i / 4, "walk")) for i in range(4)] + [("cow-hop-0", lambda c: cow(c, 0, "hop")), ("cow-fall-0", lambda c: cow(c, 0, "fall")), ("cow-impact-0", lambda c: cow(c, 0, "impact"))]


def build_all():
    OUT.mkdir(parents=True, exist_ok=True)
    for weapon in ("sheep", "super_sheep", "mole", "skunk", "cow"):
        for name, draw in poses(weapon):
            render(OUT / f"{name}.png", draw)
            render(OUT / "left" / f"{name}.png", draw, mirror=True)
    return {}


def metadata():
    return {"source_size": [128, 128], "logical_size": [64, 64], "source_anchor": [64, 88], "anchor": [32, 44], "flight_anchor": [32, 32],
            "pattern": "ordnance/critters/{id}.png", "left_pattern": "ordnance/critters/left/{id}.png",
            "directions": ["right", "left"], "sprites": {
                "sheep": {"walk": 4, "hop": 2, "fall": 1}, "super_sheep": {"walk": 4, "hop": 1, "fall": 1, "flying": 2},
                "mole": {"walk": 4, "hop": 1, "fall": 1, "dive": 1, "dig": 2}, "skunk": {"walk": 4, "hop": 1, "fall": 1, "spray": 2}, "cow": {"walk": 4, "hop": 1, "fall": 1, "impact": 1}},
            "note": "Original Cairo vectors, mirrored at build time; no external art source."}


if __name__ == "__main__":
    build_all()
