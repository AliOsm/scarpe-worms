"""Terrain material kit: tileable textures for the destructible landscape.

The game's terrain is a bitmap of cells (1 cell = 2 world pixels) painted by
lib/burrow/client/terrain_painter.rb in a worker process.  These textures are
authored at *cell* resolution so the painter only does table lookups per cell,
with no per-pixel trigonometry or colour blending:

    terrain/{biome}-fill.png    256x256  tileable rock/soil body
    terrain/{biome}-deep.png    256x256  same, slightly darker: more than DEEP cells below the surface
    terrain/{biome}-shade.png   256x256  same, occluded (under the grass lip, cave ceilings)
    terrain/{biome}-edge.png    256x256  same, deep shadow tone (1-2 cell silhouette rim)
    terrain/{biome}-crust.png   256x20   surface lip; row r = r cells below the air above.
                                         alpha 255 = paint crust colour, alpha 0 = use fill,
                                         any other alpha = use the shade texture (lip shadow)
    terrain/{biome}-tufts.png   256x12   grass/snow/ash fringe drawn into the *empty* cells
                                         above a surface; the bottom row touches the ground.
                                         Written with its own alpha (no blending needed).
    terrain/{biome}-masonry.png 64x32    tileable dressed stone for material 3
    terrain/girder.png          32x6     steel girder for material 2; row = depth from its top

Everything is drawn with cairo at 4x and box-filtered down, so edges inside
the textures are anti-aliased.  Tileability: every feature is drawn at all
wrap offsets.  All randomness is seeded.
"""
from __future__ import annotations

import math

import cairocffi as cairo
from PIL import Image

from build_art_core import ART, Rand, circle, ellipse, mix, poly, smooth, src

OUT = ART / "terrain"
T = 256          # fill tile, cells
SS = 4           # supersampling
CR = 20          # crust rows
TU = 12          # tuft rows
DEEP = 24        # cells below the surface where the darker "deep" fill starts

BIOMES = {
    "meadow": dict(
        base="#986d4a", lo="#87603f", hi="#a97e55", band="#7b563a", band_hi="#b88c61",
        stone="#c2b29a", stone_lo="#9c8a72", stone_hi="#e6dbc8", stone_ink="#563c2a",
        pebble=("#6f4c35", "#c7a47c", "#a07a57"), root="#5c3f2d", hole="#4a3224", hole_rim="#b88d61",
        shade_to="#4a3640", edge_to="#2e211b",
        crust=dict(ink="#2d5527", top="#a9d865", hi="#cdec88", body="#79b34b", deep="#5d9840"),
        tuft=("#7fbe4f", "#4f8a39", "#a9d865"), flowers=("#fff6e0", "#ffd35c", "#ff8fa3"),
        masonry=("#c8b896", "#a8977a", "#e4d8bd", "#5d4a3a"),
    ),
    "desert": dict(
        base="#c47a4a", lo="#b0683f", hi="#d48c5a", band="#9d5636", band_hi="#e7a874",
        stone="#efcf9d", stone_lo="#d2a676", stone_hi="#fff0d0", stone_ink="#7a3f27",
        pebble=("#8f4a30", "#f2cd96", "#b56f43"), root="#8f4a30", hole="#6b3524", hole_rim="#e7a874",
        shade_to="#5a2a30", edge_to="#3a1c1f",
        crust=dict(ink="#7a3f27", top="#f9dca3", hi="#fff1c9", body="#ecc07f", deep="#d99d62"),
        tuft=("#c2ad5a", "#8d7a3a", "#e0cc7a"), flowers=("#ff8fa3", "#fff0c4", "#ffb347"),
        masonry=("#e9c08e", "#cf9f6e", "#fbdcae", "#87503a"),
    ),
    "glacier": dict(
        base="#7fb0cf", lo="#6c9dc0", hi="#97c4de", band="#5f8db5", band_hi="#c2e1ef",
        stone="#66778f", stone_lo="#4e6078", stone_hi="#93a5ba", stone_ink="#26384f",
        pebble=("#4b6380", "#dff0f8", "#6f90ad"), root="#3f6d96", hole="#3d5d80", hole_rim="#dff0f8",
        shade_to="#2a4166", edge_to="#18263f",
        crust=dict(ink="#4f7395", top="#ffffff", hi="#ffffff", body="#eef7fb", deep="#d3e7f1"),
        tuft=("#ffffff", "#c7dfec", "#e6f4fa"), flowers=("#bfeaf5", "#ffffff", "#9fd6ea"),
        masonry=("#bcd2e2", "#9ab6cc", "#e2eff6", "#3f5873"),
    ),
    "volcano": dict(
        base="#4b4049", lo="#3f353e", hi="#5b4e58", band="#251c25", band_hi="#8a7686",
        stone="#7a6875", stone_lo="#5e4d5c", stone_hi="#9c8894", stone_ink="#251a24",
        pebble=("#2e2330", "#8a7684", "#ff8a3d"), root="#ff7a3d", hole="#2a1f2b", hole_rim="#8a7684",
        shade_to="#2a1c2c", edge_to="#170f18",
        crust=dict(ink="#1f1620", top="#9a8590", hi="#b9a5ae", body="#76626f", deep="#5f4d5c"),
        tuft=("#3a2c38", "#211821", "#5a4752"), flowers=("#ffb347", "#ffd35c", "#ff7a3d"),
        masonry=("#7d6d7b", "#64546a", "#9a8a96", "#231a25"),
    ),
}


# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------

def canvas(w, h):
    s = cairo.ImageSurface(cairo.FORMAT_ARGB32, w * SS, h * SS)
    ctx = cairo.Context(s)
    ctx.scale(SS, SS)
    ctx.set_line_join(cairo.LINE_JOIN_ROUND)
    ctx.set_line_cap(cairo.LINE_CAP_ROUND)
    return s, ctx


def to_image(s, w, h):
    s.flush()
    im = Image.frombuffer("RGBA", (s.get_width(), s.get_height()), bytes(s.get_data()), "raw", "BGRa", 0, 1)
    return im.resize((w, h), Image.BOX)


def wrapped(ctx, fn, w=T, h=T):
    """Draw fn at every wrap offset so the tile repeats seamlessly."""
    for dx in (-w, 0, w):
        for dy in (-h, 0, h):
            ctx.save()
            ctx.translate(dx, dy)
            fn(ctx)
            ctx.restore()


def periodic_noise(size, cells, seed, smooth_px=None):
    """Tileable smooth value noise as an L image (0..255)."""
    r = Rand(seed)
    small = Image.frombytes("L", (cells, cells), bytes(r.randrange(256) for _ in range(cells * cells)))
    big = Image.new("L", (cells * 3, cells * 3))
    for i in range(3):
        for j in range(3):
            big.paste(small, (i * cells, j * cells))
    big = big.resize((size * 3, size * 3), Image.BICUBIC)
    return big.crop((size, size, size * 2, size * 2))


def tone_layer(ctx, col, alpha_img, alpha_scale, w, h):
    """Paint col through a greyscale mask (PIL L image at cell res)."""
    a = alpha_img.resize((w * SS, h * SS), Image.BICUBIC).point(lambda v: round(v * alpha_scale))
    rgba = Image.new("RGBA", a.size, col)
    rgba.putalpha(a)
    data = bytearray(rgba.tobytes("raw", "BGRa"))
    surf = cairo.ImageSurface.create_for_data(data, cairo.FORMAT_ARGB32, a.size[0], a.size[1])
    ctx.save()
    ctx.identity_matrix()
    ctx.set_source_surface(surf, 0, 0)
    ctx.paint()
    ctx.restore()


def blob_pts(cx, cy, rx, ry, r, n=9, jag=0.18):
    pts = []
    for i in range(n):
        a = i / n * math.tau
        k = 1 + r.uniform(-jag, jag)
        pts.append((cx + math.cos(a) * rx * k, cy + math.sin(a) * ry * k))
    return pts


def stone(ctx, cx, cy, rx, ry, r, p, lw=1.0):
    pts = blob_pts(cx, cy, rx, ry, r)
    body = lambda c: smooth(c, pts, True, 0.55)
    ctx.new_path(); body(ctx)
    src(ctx, p["stone_ink"]); ctx.set_line_width(lw * 1.6); ctx.stroke_preserve()
    src(ctx, p["stone_lo"]); ctx.fill()
    ctx.save()
    ctx.new_path(); body(ctx); ctx.clip()
    ctx.new_path(); smooth(ctx, [(x - rx * 0.14, y - ry * 0.18) for (x, y) in pts], True, 0.55)
    src(ctx, p["stone"]); ctx.fill()
    ctx.new_path(); ellipse(ctx, cx - rx * 0.35, cy - ry * 0.45, rx * 0.38, ry * 0.2, -0.3)
    src(ctx, p["stone_hi"], 0.85); ctx.fill()
    ctx.restore()


# --------------------------------------------------------------------------
# fills
# --------------------------------------------------------------------------

def strata(ctx, p, r, count, amp, thick, col, hi, alpha=0.75):
    """Wavy horizontal bands, periodic in x (integer cycles per tile)."""
    for k in range(count):
        y0 = (k + r.uniform(0.15, 0.85)) * T / count
        c1, c2 = r.choice((1, 2)), r.choice((2, 3, 4))
        ph1, ph2 = r.uniform(0, math.tau), r.uniform(0, math.tau)
        th = thick * r.uniform(0.7, 1.3)
        def wave(x, y0=y0, c1=c1, c2=c2, ph1=ph1, ph2=ph2):
            return y0 + amp * math.sin(x / T * math.tau * c1 + ph1) + amp * 0.35 * math.sin(x / T * math.tau * c2 + ph2)
        top = [(x, wave(x)) for x in range(-4, T + 5, 4)]
        bot = [(x, wave(x) + th * (0.75 + 0.25 * math.sin(x / T * math.tau * 3 + ph2))) for x in range(T + 4, -5, -4)]
        def draw(c, top=top, bot=bot):
            c.new_path(); poly(c, top + bot); src(c, col, alpha); c.fill()
            c.new_path(); poly(c, [(x, y + 0.6) for (x, y) in top], close=False)
            src(c, hi, 0.55); c.set_line_width(0.8); c.stroke()
        for dy in (-T, 0, T):
            ctx.save(); ctx.translate(0, dy); draw(ctx); ctx.restore()


def scatter(r, n, min_gap, existing=None):
    pts = list(existing or [])
    out = []
    tries = 0
    while len(out) < n and tries < n * 60:
        tries += 1
        x, y = r.uniform(0, T), r.uniform(0, T)
        ok = True
        for (px, py, pr) in pts:
            dx = min(abs(x - px), T - abs(x - px))
            dy = min(abs(y - py), T - abs(y - py))
            if math.hypot(dx, dy) < min_gap + pr:
                ok = False
                break
        if ok:
            out.append((x, y))
            pts.append((x, y, min_gap))
    return out, pts


def fill_common(ctx, p, seed):
    src(ctx, p["base"]); ctx.paint()
    tone_layer(ctx, p["lo"], periodic_noise(T, 8, seed), 0.9, T, T)
    tone_layer(ctx, p["hi"], periodic_noise(T, 16, seed + 1), 0.55, T, T)


def fill_meadow(ctx, p, r):
    fill_common(ctx, p, 101)
    strata(ctx, p, r, 4, 7, 9, p["band"], p["band_hi"], 0.55)
    used = []
    # burrow holes (on-theme little tunnels)
    holes, used = scatter(r, 3, 26, used)
    for (x, y) in holes:
        rx, ry = r.uniform(5, 7), r.uniform(3.5, 4.5)
        def hole(c, x=x, y=y, rx=rx, ry=ry):
            c.new_path(); ellipse(c, x, y + 0.8, rx + 1.2, ry + 1.2); src(c, p["hole_rim"], 0.7); c.fill()
            c.new_path(); ellipse(c, x, y, rx, ry); src(c, p["hole"]); c.fill()
            c.new_path(); ellipse(c, x + 0.8, y + 0.9, rx * 0.65, ry * 0.5); src(c, "#000000", 0.25); c.fill()
        wrapped(ctx, hole)
    stones, used = scatter(r, 16, 14, used)
    for (x, y) in stones:
        rx = r.uniform(4, 10)
        ry = rx * r.uniform(0.55, 0.8)
        sd = r.random()
        wrapped(ctx, lambda c, x=x, y=y, rx=rx, ry=ry, sd=sd: stone(c, x, y, rx, ry, Rand(int(sd * 1e6)), p))
    # roots: short wiggly fibres
    for _ in range(14):
        x, y = r.uniform(0, T), r.uniform(0, T)
        a = r.uniform(0.6, 2.5)
        pts = [(x, y)]
        for k in range(5):
            a += r.uniform(-0.5, 0.5)
            pts.append((pts[-1][0] + math.cos(a) * 4, pts[-1][1] + math.sin(a) * 4))
        def root(c, pts=pts):
            c.new_path(); smooth(c, pts, False, 0.5); src(c, p["root"], 0.7); c.set_line_width(1.0); c.stroke()
        wrapped(ctx, root)
    pebbles(ctx, p, r, 120)


def pebbles(ctx, p, r, n):
    for _ in range(n):
        x, y = r.uniform(0, T), r.uniform(0, T)
        s = r.uniform(0.6, 1.6)
        col = r.choice(p["pebble"])
        def peb(c, x=x, y=y, s=s, col=col):
            c.new_path(); ellipse(c, x, y, s * 1.3, s); src(c, col, 0.85); c.fill()
        wrapped(ctx, peb)


def fill_desert(ctx, p, r):
    src(ctx, p["base"]); ctx.paint()
    # strong sandstone layering
    cols = [p["lo"], p["hi"], p["band"], p["base"], p["band_hi"], p["lo"]]
    strata(ctx, p, r, 6, 5, 18, cols[0], p["band_hi"], 0.6)
    strata(ctx, p, r, 5, 4, 7, p["band"], p["band_hi"], 0.5)
    tone_layer(ctx, p["hi"], periodic_noise(T, 16, 203), 0.4, T, T)
    # cross-bedding: short diagonal hairlines
    for _ in range(40):
        x, y = r.uniform(0, T), r.uniform(0, T)
        L = r.uniform(6, 14)
        def cb(c, x=x, y=y, L=L):
            c.new_path(); c.move_to(x, y); c.line_to(x + L, y + L * 0.32)
            src(c, p["band"], 0.45); c.set_line_width(0.7); c.stroke()
        wrapped(ctx, cb)
    used = []
    fossils, used = scatter(r, 4, 30, used)
    for (x, y) in fossils:
        rr = r.uniform(5, 7.5)
        def fossil(c, x=x, y=y, rr=rr):
            c.new_path(); circle(c, x, y, rr); src(c, p["stone_ink"]); c.set_line_width(1.4); c.stroke_preserve()
            src(c, p["stone"]); c.fill()
            pts = [(x + math.cos(t) * rr * (1 - t / 13), y + math.sin(t) * rr * (1 - t / 13)) for t in
                   [k * 0.35 for k in range(34)]]
            c.new_path(); poly(c, pts, close=False); src(c, p["stone_ink"], 0.75); c.set_line_width(0.8); c.stroke()
            for k in range(8):
                a = k / 8 * math.tau
                c.new_path(); c.move_to(x + math.cos(a) * rr * 0.55, y + math.sin(a) * rr * 0.55)
                c.line_to(x + math.cos(a) * rr * 0.95, y + math.sin(a) * rr * 0.95)
                src(c, p["stone_lo"], 0.8); c.set_line_width(0.6); c.stroke()
            c.new_path(); ellipse(c, x - rr * 0.4, y - rr * 0.45, rr * 0.35, rr * 0.18, -0.4); src(c, p["stone_hi"], 0.8); c.fill()
        wrapped(ctx, fossil)
    stones, used = scatter(r, 9, 16, used)
    for (x, y) in stones:
        rx = r.uniform(4, 8)
        ry = rx * r.uniform(0.5, 0.7)
        sd = r.random()
        wrapped(ctx, lambda c, x=x, y=y, rx=rx, ry=ry, sd=sd: stone(c, x, y, rx, ry, Rand(int(sd * 1e6)), p))
    pebbles(ctx, p, r, 90)


def fill_glacier(ctx, p, r):
    fill_common(ctx, p, 301)
    strata(ctx, p, r, 5, 6, 10, p["band"], p["band_hi"], 0.5)
    # long diagonal pressure cracks
    for _ in range(9):
        x, y = r.uniform(0, T), r.uniform(0, T)
        pts = [(x, y)]
        a = r.uniform(-0.6, 0.6) + (math.pi if r.random() < 0.5 else 0)
        for k in range(6):
            a += r.uniform(-0.45, 0.45)
            pts.append((pts[-1][0] + math.cos(a) * 6, pts[-1][1] + math.sin(a) * 6))
        def crack(c, pts=pts):
            c.new_path(); poly(c, [(x + 0.7, y + 0.7) for (x, y) in pts], close=False)
            src(c, "#ffffff", 0.7); c.set_line_width(0.9); c.stroke()
            c.new_path(); poly(c, pts, close=False); src(c, p["root"], 0.8); c.set_line_width(0.9); c.stroke()
        wrapped(ctx, crack)
    used = []
    stones, used = scatter(r, 10, 18, used)
    for (x, y) in stones:
        rx = r.uniform(4, 9)
        ry = rx * r.uniform(0.6, 0.85)
        sd = r.random()
        def frozen(c, x=x, y=y, rx=rx, ry=ry, sd=sd):
            stone(c, x, y, rx, ry, Rand(int(sd * 1e6)), p)
            c.new_path(); ellipse(c, x, y, rx + 2.2, ry + 2.0); src(c, "#e9f6fb", 0.35); c.set_line_width(1.2); c.stroke()
        wrapped(ctx, frozen)
    # air bubbles
    for _ in range(70):
        x, y = r.uniform(0, T), r.uniform(0, T)
        s = r.uniform(0.8, 2.4)
        def bub(c, x=x, y=y, s=s):
            c.new_path(); circle(c, x, y, s); src(c, "#e6f4fa", 0.55); c.set_line_width(0.6); c.stroke()
            c.new_path(); circle(c, x - s * 0.35, y - s * 0.35, s * 0.35); src(c, "#ffffff", 0.9); c.fill()
        wrapped(ctx, bub)


def fill_volcano(ctx, p, r):
    src(ctx, p["base"]); ctx.paint()
    # columnar basalt: jittered hex cells with lit top-left bevel
    cells = []
    nx, ny = 9, 11
    for j in range(ny):
        for i in range(nx):
            cx = (i + 0.5 * (j % 2)) * T / nx + r.uniform(-4, 4)
            cy = j * T / ny + r.uniform(-3, 3)
            cells.append((cx, cy))
    tones = (p["lo"], p["base"], p["hi"], p["base"])
    for (cx, cy) in cells:
        rx, ry = T / nx * 0.5, T / ny * 0.66
        rot = r.uniform(-0.25, 0.25)
        pts = [(cx + math.cos(a) * rx * (1 + r.uniform(-0.16, 0.16)),
                cy + math.sin(a) * ry * (1 + r.uniform(-0.16, 0.16)))
               for a in [k * math.tau / 6 + math.pi / 6 + rot for k in range(6)]]
        tone = r.choice(tones)
        def cell(c, pts=pts, tone=tone, cx=cx, cy=cy):
            c.new_path(); poly(c, pts); src(c, p["band"]); c.set_line_width(1.6); c.stroke_preserve()
            src(c, tone); c.fill()
            c.new_path(); poly(c, [pts[3], pts[4], pts[5]], close=False); src(c, p["band_hi"], 0.55)
            c.set_line_width(0.9); c.stroke()
            c.new_path(); poly(c, [pts[0], pts[1], pts[2]], close=False); src(c, p["stone_ink"], 0.45)
            c.set_line_width(0.9); c.stroke()
        wrapped(ctx, cell)
    tone_layer(ctx, p["lo"], periodic_noise(T, 8, 401), 0.55, T, T)
    # sparse glowing lava veins along the cracks
    for _ in range(6):
        x, y = r.uniform(0, T), r.uniform(0, T)
        pts = [(x, y)]
        a = r.uniform(0, math.tau)
        for k in range(7):
            a += r.uniform(-0.8, 0.8)
            pts.append((pts[-1][0] + math.cos(a) * 5, pts[-1][1] + math.sin(a) * 5))
        def vein(c, pts=pts):
            for wd, col, al in ((3.4, "#ff6a2e", 0.35), (1.6, "#ff8a3d", 0.95), (0.7, "#ffd35c", 1.0)):
                c.new_path(); smooth(c, pts, False, 0.5); src(c, col, al); c.set_line_width(wd); c.stroke()
        wrapped(ctx, vein)
    used = []
    stones, used = scatter(r, 6, 20, used)
    for (x, y) in stones:
        rx = r.uniform(4, 7)
        sd = r.random()
        wrapped(ctx, lambda c, x=x, y=y, rx=rx, sd=sd: stone(c, x, y, rx, rx * 0.7, Rand(int(sd * 1e6)), p))
    pebbles(ctx, dict(p, pebble=p["pebble"][:2]), r, 60)
    for _ in range(26):
        x, y = r.uniform(0, T), r.uniform(0, T)
        wrapped(ctx, lambda c, x=x, y=y: (c.new_path(), circle(c, x, y, 0.7), src(c, "#ffb347", 0.9), c.fill()))


FILLS = {"meadow": fill_meadow, "desert": fill_desert, "glacier": fill_glacier, "volcano": fill_volcano}


def variant(im, to, t, lift=0.0):
    """Darken a texture toward a tone (shade/edge copies baked at build time)."""
    tint = Image.new("RGBA", im.size, to)
    out = Image.blend(im.convert("RGBA"), tint, t)
    if lift:
        out = Image.blend(out, im, lift)
    return out


# --------------------------------------------------------------------------
# crust and tufts
# --------------------------------------------------------------------------

def crust(biome, p, r):
    """Surface lip, 256 x CR cells.  Opaque = crust, alpha 0 = fill, other = lip shadow."""
    c = p["crust"]
    s, ctx = canvas(T, CR)
    # per-column lip length: smooth periodic wave + drips
    def lip(x):
        base = {"meadow": 6.5, "desert": 4.5, "glacier": 6.0, "volcano": 3.5}[biome]
        v = base + 1.3 * math.sin(x / T * math.tau * 3 + 0.7) + 0.8 * math.sin(x / T * math.tau * 7 + 2.1)
        return v
    drips = []
    for _ in range({"meadow": 16, "desert": 8, "glacier": 18, "volcano": 10}[biome]):
        drips.append((r.uniform(0, T), r.uniform(2.5, 5.5), r.uniform(3, 8.5)))
    def drip_extra(x):
        best = 0.0
        for (dx, w, L) in drips:
            d = min(abs(x - dx), T - abs(x - dx))
            if d < w:
                best = max(best, L * math.cos(d / w * math.pi / 2) ** 1.5)
        return best
    xs = [x * 0.5 for x in range(-8, T * 2 + 9)]
    edge = [(x, lip(x) + drip_extra(x % T)) for x in xs]
    body = lambda cc: poly(cc, [(xs[0], -1), (xs[-1], -1)] + edge[::-1])
    # lip shadow zone (marker alpha) a few cells below the lip
    ctx.new_path(); poly(ctx, [(xs[0], -1), (xs[-1], -1)] + [(x, y + 3.2) for (x, y) in edge[::-1]])
    src(ctx, "#000000", 0.5); ctx.fill()
    ctx.set_operator(cairo.OPERATOR_SOURCE)
    ctx.new_path(); poly(ctx, [(xs[0], -1), (xs[-1], -1)] + [(x, y + 1.1) for (x, y) in edge[::-1]])
    src(ctx, c["ink"]); ctx.fill()
    ctx.set_operator(cairo.OPERATOR_OVER)
    ctx.new_path(); body(ctx); src(ctx, c["body"]); ctx.fill()
    ctx.save(); ctx.new_path(); body(ctx); ctx.clip()
    # depth gradient inside the lip
    ctx.new_path(); poly(ctx, [(xs[0], 3.0), (xs[-1], 3.0), (xs[-1], CR), (xs[0], CR)])
    src(ctx, c["deep"]); ctx.fill()
    ctx.new_path(); poly(ctx, [(x, y - 1.6) for (x, y) in edge] + [(xs[-1], CR), (xs[0], CR)])
    src(ctx, c["deep"]); ctx.fill()
    ctx.new_path(); ctx.rectangle(-8, 0, T + 16, 2.6); src(ctx, c["top"]); ctx.fill()
    ctx.new_path(); ctx.rectangle(-8, 1.0, T + 16, 0.9); src(ctx, c["hi"]); ctx.fill()
    # texture strokes inside the lip
    if biome in ("meadow", "glacier"):
        for k in range(110):
            x = r.uniform(0, T)
            y = r.uniform(3, 9)
            L = r.uniform(1.5, 3.5)
            col = c["top"] if biome == "glacier" else r.choice((c["top"], c["deep"]))
            for dx in (-T, 0, T):
                ctx.new_path(); ctx.move_to(x + dx, y); ctx.line_to(x + dx + 0.6, y + L)
                src(ctx, col, 0.55); ctx.set_line_width(0.8); ctx.stroke()
    elif biome == "desert":
        for k in range(5):
            y = 2.5 + k * 1.3
            ctx.new_path()
            for x in range(-4, T + 5, 2):
                yy = y + 0.4 * math.sin(x / T * math.tau * (6 + k) + k)
                (ctx.line_to if x > -4 else ctx.move_to)(x, yy)
            src(ctx, c["deep"], 0.5); ctx.set_line_width(0.5); ctx.stroke()
    else:  # volcano: scorched crust with ember cracks
        for k in range(18):
            x = r.uniform(0, T)
            for dx in (-T, 0, T):
                ctx.new_path(); ctx.move_to(x + dx, 0.5); ctx.line_to(x + dx + r.uniform(-1, 1), r.uniform(2, 3.5))
                src(ctx, "#ff8a3d", 0.75); ctx.set_line_width(0.6); ctx.stroke()
    ctx.restore()
    # top ink line
    ctx.new_path(); ctx.rectangle(-8, 0, T + 16, 1.0); src(ctx, c["ink"]); ctx.fill()
    im = to_image(s, T, CR)
    # quantise alpha into the three-way contract
    px = im.load()
    for y in range(CR):
        for x in range(T):
            r_, g_, b_, a_ = px[x, y]
            if a_ >= 168:
                # un-premultiplied by PIL already; force opaque
                px[x, y] = (r_, g_, b_, 255)
            elif a_ >= 40:
                px[x, y] = (0, 0, 0, 128)
            else:
                px[x, y] = (0, 0, 0, 0)
    return im


def tufts(biome, p, r):
    """Fringe drawn into empty cells above the surface; bottom row = just above ground."""
    s, ctx = canvas(T, TU)
    base = TU + 0.6
    g, gd, gl = p["tuft"]
    if biome == "meadow":
        for _ in range(240):
            x = r.uniform(0, T)
            hgt = r.uniform(2.0, 6.5) if r.random() < 0.8 else r.uniform(6, 9)
            lean = r.uniform(-1.8, 1.8)
            col = r.choice((g, g, gl, gd))
            def blade(c, x=x, hgt=hgt, lean=lean, col=col):
                c.new_path(); c.move_to(x - 0.9, base); c.curve_to(x - 0.4, base - hgt * 0.6, x + lean * 0.6, base - hgt * 0.8,
                                                                    x + lean, base - hgt)
                c.curve_to(x + lean * 0.4, base - hgt * 0.7, x + 0.5, base - hgt * 0.4, x + 0.9, base)
                c.close_path(); src(c, gd); c.set_line_width(0.7); c.stroke_preserve(); src(c, col); c.fill()
            for dx in (-T, 0, T):
                ctx.save(); ctx.translate(dx, 0); blade(ctx); ctx.restore()
        for _ in range(14):
            x, hh = r.uniform(0, T), r.uniform(5, 8.5)
            col = r.choice(p["flowers"])
            for dx in (-T, 0, T):
                ctx.new_path(); ctx.move_to(x + dx, base); ctx.line_to(x + dx + 0.4, base - hh)
                src(ctx, gd); ctx.set_line_width(0.8); ctx.stroke()
                for k in range(5):
                    a = k / 5 * math.tau
                    ctx.new_path(); circle(ctx, x + dx + 0.4 + math.cos(a) * 1.1, base - hh + math.sin(a) * 1.1, 0.9)
                    src(ctx, col); ctx.fill()
                ctx.new_path(); circle(ctx, x + dx + 0.4, base - hh, 0.7); src(ctx, "#ffb347"); ctx.fill()
    elif biome == "desert":
        for _ in range(16):
            x = r.uniform(0, T)
            for dx in (-T, 0, T):
                for k in range(7):
                    a = -math.pi / 2 + (k - 3) * 0.28
                    L = r.uniform(3, 6.5)
                    ctx.new_path(); ctx.move_to(x + dx, base)
                    ctx.line_to(x + dx + math.cos(a) * L, base + math.sin(a) * L)
                    src(ctx, r.choice((g, gd, gl))); ctx.set_line_width(0.7); ctx.stroke()
        for _ in range(30):
            x = r.uniform(0, T)
            s_ = r.uniform(0.8, 1.6)
            for dx in (-T, 0, T):
                ctx.new_path(); ellipse(ctx, x + dx, base - s_ * 0.6, s_ * 1.4, s_)
                src(ctx, p["stone_ink"]); ctx.set_line_width(0.5); ctx.stroke_preserve()
                src(ctx, r.choice(p["pebble"])); ctx.fill()
    elif biome == "glacier":
        # soft rolling snow lip and a few ice spikes
        pts = [(x, base - 1.6 - 1.2 * (0.5 + 0.5 * math.sin(x / T * math.tau * 9 + 0.3))
                - 0.9 * (0.5 + 0.5 * math.sin(x / T * math.tau * 23 + 1.1))) for x in range(-4, T + 5, 2)]
        ctx.new_path(); poly(ctx, pts + [(T + 4, base), (-4, base)])
        src(ctx, "#ffffff"); ctx.fill_preserve(); src(ctx, p["crust"]["ink"], 0.6); ctx.set_line_width(0.5); ctx.stroke()
        for _ in range(18):
            x = r.uniform(0, T)
            hh = r.uniform(3.5, 8)
            ww = r.uniform(1.2, 2.2)
            for dx in (-T, 0, T):
                ctx.new_path(); poly(ctx, [(x + dx - ww, base), (x + dx + 0.3, base - hh), (x + dx + ww, base)])
                src(ctx, p["crust"]["ink"]); ctx.set_line_width(0.6); ctx.stroke_preserve()
                src(ctx, "#cdeef7"); ctx.fill()
                ctx.new_path(); poly(ctx, [(x + dx - ww * 0.3, base - 0.6), (x + dx + 0.2, base - hh * 0.8),
                                          (x + dx + 0.1, base - 0.6)]); src(ctx, "#ffffff", 0.9); ctx.fill()
    else:  # volcano: charred stubs and loose cinders
        for _ in range(26):
            x = r.uniform(0, T)
            hh = r.uniform(1.8, 5.5)
            for dx in (-T, 0, T):
                ctx.new_path(); poly(ctx, [(x + dx - 1.2, base), (x + dx - 0.3, base - hh), (x + dx + 0.5, base - hh + 0.6),
                                          (x + dx + 1.2, base)])
                src(ctx, gd); ctx.fill()
        for _ in range(26):
            x = r.uniform(0, T)
            for dx in (-T, 0, T):
                ctx.new_path(); circle(ctx, x + dx, base - r.uniform(0.6, 1.2), r.uniform(0.6, 1.1))
                src(ctx, r.choice((g, gl))); ctx.fill()
        for _ in range(9):
            x = r.uniform(0, T)
            for dx in (-T, 0, T):
                ctx.new_path(); circle(ctx, x + dx, base - 0.8, 0.7); src(ctx, "#ffb347"); ctx.fill()
    return to_image(s, T, TU)


# --------------------------------------------------------------------------
# masonry and girder
# --------------------------------------------------------------------------

def masonry(biome, p, r):
    face, lo, hi, ink = p["masonry"]
    MW, MH = 64, 32
    s, ctx = canvas(MW, MH)
    src(ctx, ink); ctx.paint()
    for row in range(4):
        y = row * 8
        off = 8 if row % 2 else 0
        for k in range(-1, 5):
            x = k * 16 + off + r.uniform(-0.5, 0.5)
            w_ = 16 - 1.1
            tone = mix(face, lo, r.uniform(0, 0.45))
            def blk(c, x=x, y=y, w_=w_, tone=tone):
                c.new_path(); c.rectangle(x + 0.55, y + 0.55, w_, 6.9); src(c, mix(tone, lo, 0.55)); c.fill()
                c.new_path(); c.rectangle(x + 0.55, y + 0.55, w_ - 1.2, 5.7); src(c, tone); c.fill()
                c.new_path(); c.rectangle(x + 0.55, y + 0.55, w_ - 1.2, 1.0); src(c, hi, 0.9); c.fill()
                c.new_path(); c.rectangle(x + 0.55, y + 0.55, 1.0, 5.7); src(c, hi, 0.6); c.fill()
            for dx in (-MW, 0, MW):
                ctx.save(); ctx.translate(dx, 0); blk(ctx); ctx.restore()
            if r.random() < 0.35:
                cx, cy = x + r.uniform(4, 12), y + r.uniform(2, 5)
                for dx in (-MW, 0, MW):
                    ctx.new_path(); poly(ctx, [(cx + dx, cy), (cx + dx + 1.5, cy + 1.2), (cx + dx + 1, cy + 2.6)], close=False)
                    src(ctx, lo); ctx.set_line_width(0.6); ctx.stroke()
            if biome == "meadow" and r.random() < 0.25:
                cx = x + r.uniform(2, 13)
                for dx in (-MW, 0, MW):
                    ctx.new_path(); ellipse(ctx, cx + dx, y + 7.4, r.uniform(2, 4), 1.1); src(ctx, "#6fa64a", 0.9); ctx.fill()
    return to_image(s, MW, MH)


def girder():
    GW, GH = 32, 6
    s, ctx = canvas(GW, GH)
    ink, steel, hi, lo = "#182d35", "#c7643f", "#ee9a6d", "#8f3f2b"
    src(ctx, ink); ctx.paint()
    ctx.new_path(); ctx.rectangle(-1, 0.7, GW + 2, 1.3); src(ctx, steel); ctx.fill()
    ctx.new_path(); ctx.rectangle(-1, 0.7, GW + 2, 0.55); src(ctx, hi); ctx.fill()
    ctx.new_path(); ctx.rectangle(-1, 4.0, GW + 2, 1.3); src(ctx, lo); ctx.fill()
    ctx.new_path(); ctx.rectangle(-1, 2.0, GW + 2, 2.0); src(ctx, mix(steel, lo, 0.4)); ctx.fill()
    for x in (0, 16, 32):
        ctx.new_path(); poly(ctx, [(x - 6, 2.0), (x - 1, 4.0), (x + 1, 4.0), (x + 6, 2.0)]); src(ctx, ink, 0.55); ctx.fill()
    for x in (4, 12, 20, 28):
        ctx.new_path(); circle(ctx, x, 1.35, 0.42); src(ctx, "#ffe2c4"); ctx.fill()
        ctx.new_path(); circle(ctx, x, 4.65, 0.42); src(ctx, hi); ctx.fill()
    return to_image(s, GW, GH)


# --------------------------------------------------------------------------
# build
# --------------------------------------------------------------------------

def terrain_meta():
    """Static description of the kit (identical whether or not the section ran)."""
    biomes = {}
    for biome, p in BIOMES.items():
        biomes[biome] = {k: f"terrain/{biome}-{k}.png" for k in ("fill", "deep", "shade", "edge", "crust", "tufts", "masonry")}
        biomes[biome].update(minimap=p["base"], minimap_top=p["crust"]["top"])
    return {
        "cell": 2, "fill_size": [T, T], "crust_rows": CR, "tuft_rows": TU,
        "masonry_size": [64, 32], "girder": "terrain/girder.png", "girder_size": [32, 6],
        "edge_cells": 2, "shade_cells": 6, "deep_cells": DEEP,
        "contract": "crust alpha 255 = crust colour, 0 = fill texture, other = shade texture; tufts are "
                    "written with their own alpha into empty cells above a material-1 surface (bottom row "
                    "touches the ground); see docs/ART_DIRECTION.md 'Terrain material kit'",
        "biomes": biomes,
    }


def build_all():
    OUT.mkdir(parents=True, exist_ok=True)
    for i, (biome, p) in enumerate(BIOMES.items()):
        r = Rand(9000 + i)
        s, ctx = canvas(T, T)
        FILLS[biome](ctx, p, r)
        fill_im = to_image(s, T, T).convert("RGB").convert("RGBA")
        fill_im.save(OUT / f"{biome}-fill.png", optimize=True)
        variant(fill_im, p["shade_to"], 0.42).save(OUT / f"{biome}-shade.png", optimize=True)
        variant(fill_im, p["edge_to"], 0.8).save(OUT / f"{biome}-edge.png", optimize=True)
        variant(fill_im, p["shade_to"], 0.2).save(OUT / f"{biome}-deep.png", optimize=True)
        crust(biome, p, Rand(9100 + i)).save(OUT / f"{biome}-crust.png", optimize=True)
        tufts(biome, p, Rand(9200 + i)).save(OUT / f"{biome}-tufts.png", optimize=True)
        masonry(biome, p, Rand(9300 + i)).convert("RGB").convert("RGBA").save(OUT / f"{biome}-masonry.png", optimize=True)
    girder().convert("RGB").convert("RGBA").save(OUT / "girder.png", optimize=True)
    return {}


# --------------------------------------------------------------------------
# Reference painter (previews only; the game's painter is Ruby)
# --------------------------------------------------------------------------

def paint(mask, biome, tufts=False):
    """Paint a terrain cell mask (uint8 HxW, 0 air, 1 soil, 2 girder, 3 masonry) with the kit.

    This is the exact per-cell rule set proposed for terrain_painter.rb, written
    with numpy so previews stay fast.  Returns an RGBA PIL image at cell size.
    """
    import numpy as np

    def load(name):
        return np.asarray(Image.open(ART / name).convert("RGBA"))

    tex = {k: load(f"terrain/{biome}-{k}.png") for k in ("fill", "deep", "shade", "edge", "crust", "tufts", "masonry")}
    gird = load("terrain/girder.png")
    h, w = mask.shape
    solid = mask > 0
    up = np.zeros((h, w), np.int32)      # cells since air above (1 = surface)
    down = np.zeros((h, w), np.int32)    # cells until air below (1 = underside)
    gap = np.zeros((h, w), np.int32)     # for air: cells until solid below
    prev = np.zeros(w, np.int32)
    for y in range(h):
        prev = np.where(solid[y], prev + 1, 0)
        up[y] = prev
    prev = np.full(w, 99, np.int32)
    gprev = np.full(w, 999, np.int32)
    for y in range(h - 1, -1, -1):
        prev = np.where(solid[y], np.minimum(prev + 1, 99), 0)
        down[y] = prev
        gprev = np.where(solid[y], 0, gprev + 1)
        gap[y] = gprev
    left = np.zeros_like(solid); left[:, 1:] = solid[:, :-1]; left[:, 0] = True
    right = np.zeros_like(solid); right[:, :-1] = solid[:, 1:]; right[:, -1] = True
    side = solid & ~(left & right)
    ys, xs = np.mgrid[0:h, 0:w]
    tx, ty = xs % T, ys % T
    out = np.where((up > DEEP)[..., None], tex["deep"][ty, tx], tex["fill"][ty, tx])
    crow = np.clip(up - 1, 0, CR - 1)
    crust = tex["crust"][crow, tx]
    in_crust = (up >= 1) & (up <= CR)
    ca = np.where(in_crust, crust[..., 3], 0)
    edge = (down <= 2) | side
    shade = ((ca > 0) & (ca < 255)) | (down <= 6)
    out = np.where(shade[..., None], tex["shade"][ty, tx], out)
    out = np.where(edge[..., None], tex["edge"][ty, tx], out)
    out = np.where((ca == 255)[..., None], crust, out)
    # masonry: own texture, edge-darkened rim
    m3 = mask == 3
    mas = tex["masonry"][ys % 32, xs % 64]
    out = np.where(m3[..., None], np.where(edge[..., None], tex["edge"][ty, tx], mas), out)
    # girder: row from its top
    m2 = mask == 2
    out = np.where(m2[..., None], gird[np.clip(up - 1, 0, 5), xs % 32], out)
    out[..., 3] = np.where(solid, 255, 0)
    if not tufts:
        # shipped painter: the visible mask is exactly the collision mask
        return Image.fromarray(out.astype(np.uint8), "RGBA")
    # optional: tufts into air directly above a soil surface
    k = gap
    below_y = np.clip(ys + k, 0, h - 1)
    ok = (~solid) & (k >= 1) & (k <= TU) & (mask[below_y, xs] == 1)
    trow = np.clip(TU - k, 0, TU - 1)
    tuft = tex["tufts"][trow, tx]
    out = np.where((ok & (tuft[..., 3] > 0))[..., None], tuft, out)
    return Image.fromarray(out.astype(np.uint8), "RGBA")
