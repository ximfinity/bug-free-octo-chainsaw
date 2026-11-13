#!/usr/bin/env python3
"""Generates Paddle & Pine's 32px "cozy & vibrant" pixel art into assets/.

Run:  python3 tools/gen_art.py         (needs Pillow + numpy)

Technique: every sprite is drawn with vector shapes at 4x scale, then reduced
with a per-block colour *mode* (not averaging), so pixels stay crisp with no
blended in-between colours, and finally given a soft coloured outline. This
keeps one consistent style for every heading, frame and creature.

Atlases (all original art, CC0):
  terrain.png    32x32 tileable ground textures, row = tile id, 3 variants
  water_noise.png 128x128 tileable RGB noise for the water/terrain shader
  kayak.png      64x64 cells: row = hull*16 + heading, col 0 empty, 1-4 strokes
  player.png     32x48 cells: row = down/up/side, cols walk0-3, carry0-1
  creatures.png  48x48 cells: row = kind, cols = 2 walk frames
  decor.png      64x64 cells, drawn centred on a 32px map cell (see DECOR)
  props.png      64x64 cells: tent, fire A/B, fire out, chest, X, hole, bite, arrow
  items.png      32x32 item icons
  store.png      96x96 "100's of Kayaks" cabin
"""
import math
import random
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets"
OUT.mkdir(exist_ok=True)
S = 4  # supersampling factor


def rgb(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def shade(c, f):
    return tuple(max(0, min(255, int(v * f))) for v in c[:3]) + (c[3] if len(c) > 3 else 255,)


def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3)) + (255,)


# ------------------------------------------------------------------ palette
P = {
    "outline": rgb("#2b2033"),
    "skin": rgb("#f4c7a1"), "skin_d": rgb("#d99b77"),
    "hair": rgb("#7a4a2a"),
    "hat": rgb("#e7c27a"), "hat_d": rgb("#b98f4a"), "hat_band": rgb("#c2503a"),
    "pfd": rgb("#ff8c2e"), "pfd_d": rgb("#d0601c"), "pfd_l": rgb("#ffb56b"),
    "shirt": rgb("#2fb6a6"), "shirt_d": rgb("#1f8a80"),
    "shorts": rgb("#b8a06a"), "shorts_d": rgb("#8d7748"),
    "sandal": rgb("#6b3f24"),
    "paddle": rgb("#3b3f4a"), "blade": rgb("#ffd23f"), "blade_d": rgb("#d9a514"),
    "eye": rgb("#2b2033"),
}
# Second character (Rowan): green vest, red cap, darker hair, denim.
P2 = dict(P)
P2.update({
    "hair": rgb("#3a2618"), "skin": rgb("#d9a07a"), "skin_d": rgb("#b47a56"),
    "hat": rgb("#e0453a"), "hat_d": rgb("#a82f27"), "hat_band": rgb("#ffffff"),
    "pfd": rgb("#5cc05a"), "pfd_d": rgb("#3a8f3d"), "pfd_l": rgb("#9be488"),
    "shirt": rgb("#f2e6c8"), "shirt_d": rgb("#cfc09a"),
    "shorts": rgb("#4a6fa8"), "shorts_d": rgb("#34507d"),
    "blade": rgb("#3fd0c9"), "blade_d": rgb("#22a19b"),
})
PAL = P  # palette used by draw_person / paddler (swapped per character)

HULLS = [  # base, light, dark
    (rgb("#ffcc3d"), rgb("#ffe58a"), rgb("#d99a12")),
    (rgb("#ff5e57"), rgb("#ff9a8f"), rgb("#c8352f")),
    (rgb("#3fa7f0"), rgb("#8fd0ff"), rgb("#2370b8")),
]
HULL_LEN = [50, 54, 58]
HULL_W = [7.0, 6.6, 6.2]


# ------------------------------------------------------------------ canvas
class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.img = Image.new("RGBA", (w * S, h * S), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.img)

    def poly(self, pts, col):
        if len(pts) >= 3:
            self.d.polygon([(x * S, y * S) for x, y in pts], fill=col)

    def rect(self, x0, y0, x1, y1, col):
        self.d.rectangle([x0 * S, y0 * S, x1 * S - 1, y1 * S - 1], fill=col)

    def ellipse(self, cx, cy, rx, ry, col, rot=0.0, n=28):
        c, s = math.cos(rot), math.sin(rot)
        pts = []
        for i in range(n):
            a = 2 * math.pi * i / n
            x, y = math.cos(a) * rx, math.sin(a) * ry
            pts.append((cx + x * c - y * s, cy + x * s + y * c))
        self.poly(pts, col)

    def circle(self, cx, cy, r, col):
        self.ellipse(cx, cy, r, r, col)

    def line(self, x0, y0, x1, y1, col, w=1.0):
        # Thick line as a quad (PIL's wide lines have ragged ends).
        dx, dy = x1 - x0, y1 - y0
        ln = math.hypot(dx, dy) or 1.0
        nx, ny = -dy / ln * w / 2, dx / ln * w / 2
        self.poly([(x0 + nx, y0 + ny), (x1 + nx, y1 + ny), (x1 - nx, y1 - ny), (x0 - nx, y0 - ny)], col)

    def finish(self, outline=True, shadow=None):
        return reduce_img(self.img, self.w, self.h, outline, shadow)


def reduce_img(img, w, h, outline=True, shadow=None):
    """4x RGBA -> 1x using the most common opaque colour of each 4x4 block."""
    a = np.asarray(img).reshape(h, S, w, S, 4).transpose(0, 2, 1, 3, 4).reshape(h, w, S * S, 4)
    alpha = a[..., 3] > 0
    enc = (a[..., 0].astype(np.int64) << 16) | (a[..., 1].astype(np.int64) << 8) | a[..., 2].astype(np.int64)
    enc = np.where(alpha, enc, -1)
    counts = (enc[..., :, None] == enc[..., None, :]).sum(-1)
    counts = np.where(alpha, counts, -1)
    pick = counts.argmax(-1)
    chosen = np.take_along_axis(a, pick[..., None, None].repeat(4, -1), axis=2)[:, :, 0, :].copy()
    opaque = alpha.sum(-1) >= 7
    chosen[..., 3] = np.where(opaque, 255, 0)
    out = chosen
    if outline:
        op = out[..., 3] > 0
        res = out.copy()
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            nb = np.roll(np.roll(op, dy, 0), dx, 1)
            nbcol = np.roll(np.roll(out, dy, 0), dx, 1)
            # don't wrap around the edges
            if dy == 1:
                nb[0, :] = False
            if dy == -1:
                nb[-1, :] = False
            if dx == 1:
                nb[:, 0] = False
            if dx == -1:
                nb[:, -1] = False
            m = (~op) & nb & (res[..., 3] == 0)
            dark = (nbcol[..., :3].astype(np.float32) * 0.38 + np.array(P["outline"][:3]) * 0.4).astype(np.uint8)
            res[m, :3] = dark[m]
            res[m, 3] = 255
        out = res
    im = Image.fromarray(out.astype(np.uint8), "RGBA")
    if shadow:
        cx, cy, rx, ry = shadow
        sh = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        sd = ImageDraw.Draw(sh)
        sd.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=(30, 40, 60, 70))
        sh.alpha_composite(im)
        im = sh
    return im


# ------------------------------------------------------------- tileable noise
def tile_noise(n, scales, seed):
    rnd = np.random.default_rng(seed)
    out = np.zeros((n, n))
    amp_total = 0.0
    for sc, amp in scales:
        g = rnd.random((sc, sc))
        # bilinear upsample with wrap
        xs = np.arange(n) * sc / n
        x0 = np.floor(xs).astype(int)
        t = xs - x0
        t = t * t * (3 - 2 * t)
        x1 = (x0 + 1) % sc
        row = g[:, x0] * (1 - t) + g[:, x1] * t
        full = row[x0, :] * (1 - t)[:, None] + row[x1, :] * t[:, None]
        out += full * amp
        amp_total += amp
    return out / amp_total


def make_water_noise():
    n = 128
    r = tile_noise(n, [(4, 1.0), (8, 0.6), (16, 0.35)], 11)
    g = tile_noise(n, [(8, 1.0), (16, 0.5), (32, 0.25)], 12)
    b = tile_noise(n, [(16, 1.0), (32, 0.6), (64, 0.3)], 13)
    arr = np.stack([r, g, b], -1)
    arr = (arr - arr.min(axis=(0, 1))) / (arr.max(axis=(0, 1)) - arr.min(axis=(0, 1)))
    Image.fromarray((arr * 255).astype(np.uint8), "RGB").save(OUT / "water_noise.png")


# ------------------------------------------------------------- terrain atlas
# Tile ids (must match scripts/world/tiles.gd)
DEEP, SHALLOW, RIVER, SAND, GRASS, PINE, HILL, MOUNTAIN, SNOW, MARSH, DOCK, BIRCH, MAPLE, MEADOW, ROCKY = range(15)
TILE_COUNT = 15
T = 32


def ground(base, var, seed, n=T):
    """Tileable ground: two-tone noise blotches."""
    nz = tile_noise(n, [(4, 1.0), (8, 0.7), (16, 0.4)], seed)
    lo, hi = shade(base, 1 - var), shade(base, 1 + var)
    img = np.zeros((n, n, 4), np.uint8)
    q = np.digitize(nz, [0.36, 0.5, 0.64])
    cols = [lo, mix(lo, base, 0.6), base, hi]
    for i, c in enumerate(cols):
        img[q == i] = c
    return img


def stamp(img, x, y, col):
    n = img.shape[0]
    img[y % n, x % n] = col


def tufts(img, rnd, col, count, h=2):
    n = img.shape[0]
    for _ in range(count):
        x, y = rnd.randrange(n), rnd.randrange(n)
        for k in range(h):
            stamp(img, x, y - k, col)
        if rnd.random() < 0.5:
            stamp(img, x + 1, y - 1, col)


def dots(img, rnd, cols, count, size=1):
    n = img.shape[0]
    for _ in range(count):
        x, y = rnd.randrange(n), rnd.randrange(n)
        c = rnd.choice(cols)
        for dy in range(size):
            for dx in range(size):
                stamp(img, x + dx, y + dy, c)


def make_terrain():
    atlas = np.zeros((TILE_COUNT * T, 3 * T, 4), np.uint8)
    for tid in range(TILE_COUNT):
        for v in range(3):
            seed = tid * 31 + v * 7 + 1
            rnd = random.Random(seed)
            if tid in (DEEP, SHALLOW, RIVER, SAND, DOCK):
                img = ground(rgb("#f2d48f"), 0.05, seed)
                dots(img, rnd, [rgb("#e3be72"), rgb("#fae6b4")], 14)
                if rnd.random() < 0.5:
                    dots(img, rnd, [rgb("#f7f1e6"), rgb("#e89a8a")], 2)  # shells
            elif tid == GRASS:
                img = ground(rgb("#6cc24a"), 0.07, seed)
                tufts(img, rnd, rgb("#8ee05e"), 14)
                tufts(img, rnd, rgb("#4f9e38"), 8)
            elif tid == MEADOW:
                img = ground(rgb("#86d158"), 0.06, seed)
                tufts(img, rnd, rgb("#a8ea70"), 14)
                dots(img, rnd, [rgb("#ffe066"), rgb("#ffffff"), rgb("#ff8fb1")], 6)
            elif tid == PINE:
                img = ground(rgb("#3f8a4c"), 0.09, seed)
                dots(img, rnd, [rgb("#7a5a3a"), rgb("#2f6b3a")], 22)
                tufts(img, rnd, rgb("#5aa860"), 6)
            elif tid == BIRCH:
                img = ground(rgb("#7cc75a"), 0.07, seed)
                dots(img, rnd, [rgb("#d9e86a"), rgb("#f0d65a")], 12)
                tufts(img, rnd, rgb("#9be06e"), 8)
            elif tid == MAPLE:
                img = ground(rgb("#78b04a"), 0.08, seed)
                dots(img, rnd, [rgb("#ff7a2f"), rgb("#e8452f"), rgb("#ffb23a")], 20)
            elif tid == HILL:
                img = ground(rgb("#9fbf5a"), 0.08, seed)
                tufts(img, rnd, rgb("#c2db76"), 10)
                dots(img, rnd, [rgb("#8a8a7a")], 3, 2)
            elif tid == ROCKY:
                img = ground(rgb("#a9b388"), 0.08, seed)
                dots(img, rnd, [rgb("#8d8f86"), rgb("#c9c9bd")], 10, 2)
                tufts(img, rnd, rgb("#86b05a"), 6)
            elif tid == MOUNTAIN:
                img = ground(rgb("#7a6e80"), 0.1, seed)
                for _ in range(4):  # cracks
                    x, y = rnd.randrange(T), rnd.randrange(T)
                    for k in range(rnd.randint(3, 6)):
                        stamp(img, x + k, y + rnd.randint(-1, 1), rgb("#6a6272"))
                dots(img, rnd, [rgb("#b3abba")], 8, 2)
            elif tid == SNOW:
                img = ground(rgb("#eef4fb"), 0.03, seed)
                dots(img, rnd, [rgb("#d4e2f2"), rgb("#ffffff")], 14)
            elif tid == MARSH:
                img = ground(rgb("#5fa07a"), 0.08, seed)
                dots(img, rnd, [rgb("#4a8a8a")], 5, 2)
                tufts(img, rnd, rgb("#a9c46a"), 12, 3)
            else:
                img = ground(rgb("#6cc24a"), 0.07, seed)
            atlas[tid * T:(tid + 1) * T, v * T:(v + 1) * T] = img
    Image.fromarray(atlas, "RGBA").save(OUT / "terrain.png")


# ------------------------------------------------------------------- kayak
def rot(x, y, a):
    c, s = math.cos(a), math.sin(a)
    return x * c - y * s, x * s + y * c


def draw_kayak(cv, cx, cy, heading, hull, with_paddler, stroke):
    base, light, dark = HULLS[hull]
    L, W = HULL_LEN[hull], HULL_W[hull]
    LIGHT = (-0.6, -0.8)

    def tp(x, y):
        rx, ry = rot(x, y, heading)
        return cx + rx, cy + ry

    def hw(t):
        return W * max(0.0, 1 - (2 * t - 1) ** 2) ** 0.55

    n = 26
    top, bot = [], []
    for i in range(n + 1):
        t = i / n
        x = -L / 2 + t * L
        top.append((x, -hw(t)))
        bot.append((x, hw(t)))
    cv.poly([tp(x, y) for x, y in top + bot[::-1]], base)
    # side strips: lit or shaded depending on which way the side faces
    for side in (-1, 1):
        nx, ny = rot(0, side, heading)
        lit = nx * LIGHT[0] + ny * LIGHT[1] > 0
        col = light if lit else dark
        outer = [(x, y) for x, y in (top if side < 0 else bot)]
        inner = [(x, y * 0.45) for x, y in outer]
        cv.poly([tp(x, y) for x, y in outer + inner[::-1]], col)
    # deck ridge
    cv.line(*tp(-L / 2 + 3, 0), *tp(L / 2 - 3, 0), shade(light, 1.05), 1.0)
    # bow / stern deck lines (bungees)
    for bx in (L * 0.30, L * 0.37):
        cv.line(*tp(bx, -W * 0.5), *tp(bx + 2, W * 0.5), rgb("#2b2033"), 0.7)
    # two cockpits (tandem): front at +8, back at -10
    for sx in (FRONT_X, BACK_X):
        cv.ellipse(*tp(sx, 0), 6.4, 4.4, rgb("#2b2033"), heading)
        cv.ellipse(*tp(sx, 0), 5.2, 3.3, rgb("#3c3446"), heading)
    if with_paddler is None:
        return
    for seat_x, pal, stroke_shift in with_paddler:
        draw_paddler(cv, tp, heading, seat_x, (stroke + stroke_shift) % 4, pal)


FRONT_X = 8.0
BACK_X = -10.0


def draw_paddler(cv, tp, heading, seat_x, stroke, pal):
    sweep = [26, 8, -26, -8][stroke] * math.pi / 180
    shift = [2.0, -1.5, 2.0, -1.5][stroke]
    pa = heading + math.pi / 2 + sweep
    pcx, pcy = tp(seat_x + 0.5 + shift, 0)
    half = 16
    ex, ey = math.cos(pa) * half, math.sin(pa) * half
    blade_side = 1 if stroke < 2 else -1  # which blade is in the water
    cv.line(pcx - ex, pcy - ey, pcx + ex, pcy + ey, pal["paddle"], 1.6)
    for sgn in (-1, 1):
        bx, by = pcx + ex * sgn, pcy + ey * sgn
        dip = sgn == blade_side
        if dip:  # splash where the blade bites
            cv.ellipse(bx, by, 6.0, 3.6, rgb("#e8fbff"), pa)
        cv.ellipse(bx, by, 5.0, 2.5, pal["blade_d"] if dip else pal["blade"], pa)
    # paddler seen from above: shoulders in a bright vest, arms, hat
    tx, ty = tp(seat_x - 1.0, 0)
    cv.ellipse(tx, ty, 4.0, 7.0, pal["pfd_d"], heading)
    cv.ellipse(*tp(seat_x - 0.7, -0.6), 3.4, 6.2, pal["pfd"], heading)
    cv.ellipse(*tp(seat_x + 0.5, -2.4), 1.5, 2.2, pal["pfd_l"], heading)
    for sgn in (-1, 1):
        hx, hy = pcx + ex * sgn * 0.45, pcy + ey * sgn * 0.45
        sx, sy = tp(seat_x, 5.2 * sgn)
        cv.line(sx, sy, hx, hy, pal["skin_d"], 2.0)
        cv.circle(hx, hy, 1.4, pal["skin"])
    hx, hy = tp(seat_x + 0.5, 0)
    cv.ellipse(hx + 0.8, hy + 1.0, 4.2, 4.2, rgb("#2b2033"), heading)
    cv.circle(hx, hy, 4.2, pal["hat"])
    cv.circle(hx - 0.2, hy - 0.2, 2.7, pal["hat_band"])
    cv.circle(hx - 0.3, hy - 0.3, 2.1, pal["hat_d"])
    cv.circle(hx - 1.0, hy - 1.0, 0.9, rgb("#f5f0e0"))


def kayak_shadow(heading, hull):
    """Soft translucent shadow of the hull, offset down-right."""
    L, W = HULL_LEN[hull], HULL_W[hull]
    cv = Canvas(64, 64)
    pts = []
    for i in range(27):
        t = i / 26
        pts.append((-L / 2 + t * L, -W * max(0.0, 1 - (2 * t - 1) ** 2) ** 0.55))
    pts += [(x, -y) for x, y in pts[::-1]]
    cv.poly([(32 + 2 + rot(x, y, heading)[0], 32 + 3 + rot(x, y, heading)[1]) for x, y in pts], (10, 40, 70, 255))
    im = cv.finish(outline=False)
    a = np.asarray(im).copy()
    a[..., 3] = (a[..., 3] > 0) * 70
    return Image.fromarray(a, "RGBA")


# Kayak columns: 0 empty | 1-4 Juniper solo (back seat) | 5-8 Rowan solo
# (back seat) | 9-12 both (Rowan front, Juniper back, strokes offset).
KAYAK_COLS = 13


def kayak_riders(col):
    if col == 0:
        return None, 0
    if col <= 4:
        return [(BACK_X, P, 0)], col - 1
    if col <= 8:
        return [(BACK_X, P2, 0)], col - 5
    return [(FRONT_X, P2, 2), (BACK_X, P, 0)], col - 9


def make_kayak():
    atlas = Image.new("RGBA", (KAYAK_COLS * 64, 48 * 64), (0, 0, 0, 0))
    for hull in range(3):
        for h in range(16):
            heading = h * 2 * math.pi / 16
            for col in range(KAYAK_COLS):
                cv = Canvas(64, 64)
                riders, stroke = kayak_riders(col)
                draw_kayak(cv, 32, 32, heading, hull, riders, stroke)
                im = kayak_shadow(heading, hull)
                im.alpha_composite(cv.finish(outline=True))
                atlas.paste(im, (col * 64, (hull * 16 + h) * 64))
    atlas.save(OUT / "kayak.png")


# ------------------------------------------------------------------ player
def draw_person(cv, view, frame, carry):
    """32x48 cell, feet at y~46. view: 0 down, 1 up, 2 side(right)."""
    step = [0, 1, 0, -1][frame] if not carry else [0, 1][frame % 2]
    bob = -0.6 if step != 0 else 0.0
    oy = bob
    sk, skd = PAL["skin"], PAL["skin_d"]
    if view in (0, 1):
        # legs
        for lx, s in ((12.5, step), (17.5, -step)):
            cv.rect(lx, 35 + oy, lx + 3, 44 - max(0, s) * 1.5 + oy, skd if view == 1 else sk)
            cv.rect(lx - 0.5, 44 - max(0, s) * 1.5 + oy, lx + 3.5, 46 - max(0, s) * 1.5 + oy, PAL["sandal"])
        cv.rect(11, 29 + oy, 21, 37 + oy, PAL["shorts"])
        cv.rect(11, 35 + oy, 21, 37 + oy, PAL["shorts_d"])
        # arms
        if carry:
            for ax in (7.5, 21.5):
                cv.rect(ax, 8 + oy, ax + 3, 22 + oy, sk)
        else:
            for ax, s in ((7.5, -step), (21.5, step)):
                cv.rect(ax, 19 + oy + s, ax + 3, 30 + oy + s, sk)
                cv.rect(ax, 19 + oy + s, ax + 3, 22 + oy + s, PAL["shirt"])
        # torso: shirt + vest
        cv.rect(10, 18 + oy, 22, 31 + oy, PAL["shirt"])
        cv.rect(11, 18 + oy, 21, 30 + oy, PAL["pfd"])
        cv.rect(11, 26 + oy, 21, 30 + oy, PAL["pfd_d"])
        if view == 0:
            cv.rect(15.5, 19 + oy, 16.5, 29 + oy, PAL["pfd_d"])
            cv.rect(12, 22 + oy, 15, 23 + oy, PAL["pfd_l"])
            cv.rect(17, 22 + oy, 20, 23 + oy, PAL["pfd_l"])
        else:
            cv.rect(13, 20 + oy, 19, 25 + oy, PAL["pfd_l"])
        # head
        cv.circle(16, 13 + oy, 6, sk if view == 0 else PAL["hair"])
        if view == 0:
            cv.rect(10.5, 9 + oy, 21.5, 11 + oy, PAL["hair"])
            cv.rect(13, 13 + oy, 14.2, 15 + oy, PAL["eye"])
            cv.rect(17.8, 13 + oy, 19, 15 + oy, PAL["eye"])
            cv.rect(12, 16 + oy, 13.5, 17 + oy, rgb("#f3a08a"))
            cv.rect(18.5, 16 + oy, 20, 17 + oy, rgb("#f3a08a"))
        # hat
        cv.ellipse(16, 9 + oy, 10, 3.2, PAL["hat_d"])
        cv.ellipse(16, 8.5 + oy, 9.5, 2.8, PAL["hat"])
        cv.rect(11, 3 + oy, 21, 9 + oy, PAL["hat"])
        cv.rect(11, 7 + oy, 21, 8.5 + oy, PAL["hat_band"])
        cv.rect(12, 3 + oy, 15, 5 + oy, rgb("#f5dca3"))
    else:
        # side view, facing right
        back_leg, front_leg = step, -step
        for lx, s, col in ((14, back_leg, skd), (16, front_leg, sk)):
            cv.line(lx + 1.5, 35 + oy, lx + 1.5 + s * 2.5, 44 + oy, col, 3)
            cv.rect(lx + s * 2.5, 44 + oy, lx + 4.5 + s * 2.5, 46 + oy, PAL["sandal"])
        cv.rect(12, 29 + oy, 20, 37 + oy, PAL["shorts"])
        cv.rect(12, 35 + oy, 20, 37 + oy, PAL["shorts_d"])
        cv.rect(12, 18 + oy, 20, 31 + oy, PAL["shirt"])
        cv.rect(12.5, 18 + oy, 20, 30 + oy, PAL["pfd"])
        cv.rect(12.5, 26 + oy, 20, 30 + oy, PAL["pfd_d"])
        cv.rect(18, 19 + oy, 19, 29 + oy, PAL["pfd_d"])
        if carry:
            cv.rect(15, 8 + oy, 18, 22 + oy, sk)
        else:
            cv.line(16, 20 + oy, 16 + step * 3, 29 + oy, sk, 3)
            cv.rect(14.5, 19 + oy, 17.5, 22 + oy, PAL["shirt"])
        cv.circle(16.5, 13 + oy, 6, sk)
        cv.poly([(10.5, 9 + oy), (17, 9 + oy), (16, 15 + oy), (11, 17 + oy)], PAL["hair"])
        cv.rect(19, 12.5 + oy, 20.2, 14.5 + oy, PAL["eye"])
        cv.rect(22, 13.5 + oy, 23.2, 15 + oy, skd)
        cv.ellipse(17.5, 9 + oy, 11, 3.0, PAL["hat_d"])
        cv.ellipse(17.5, 8.5 + oy, 10.5, 2.6, PAL["hat"])
        cv.rect(12, 3 + oy, 21, 9 + oy, PAL["hat"])
        cv.rect(12, 7 + oy, 21, 8.5 + oy, PAL["hat_band"])


def make_player():
    """Rows 0-2 Juniper (down/up/side), rows 3-5 Rowan."""
    global PAL
    atlas = Image.new("RGBA", (6 * 32, 6 * 48), (0, 0, 0, 0))
    for who, pal in enumerate((P, P2)):
        PAL = pal
        for view in range(3):
            for col in range(6):
                cv = Canvas(32, 48)
                draw_person(cv, view, col % 4 if col < 4 else col - 4, col >= 4)
                im = cv.finish(outline=True, shadow=(16, 46, 8, 2.5))
                atlas.paste(im, (col * 32, (who * 3 + view) * 48))
    PAL = P
    atlas.save(OUT / "player.png")


# --------------------------------------------------------------- creatures
def draw_creature(cv, kind, frame):
    s = [0, 1][frame]
    if kind == "rabbit":
        fur, fur_d, belly = rgb("#c9a27a"), rgb("#a07c58"), rgb("#f2e4d0")
        cv.ellipse(30, 31, 3.2, 6.5, fur_d, 0.35)  # far ear
        cv.ellipse(22, 34, 9, 6.5, fur)
        cv.ellipse(22, 37, 7, 3.5, belly)
        cv.circle(13.5, 32, 3, rgb("#ffffff"))
        cv.circle(30, 31, 5, fur)
        cv.ellipse(28, 23, 2.6, 6.5, fur, 0.2)
        cv.ellipse(28, 23, 1.2, 4.8, rgb("#f4b6b6"), 0.2)
        cv.circle(31.5, 30, 1.1, P["eye"])
        cv.circle(34.6, 32, 0.9, rgb("#e88a8a"))
        cv.ellipse(17 + s * 2, 40, 4, 2, fur_d)
        cv.ellipse(27 - s, 40, 2.5, 1.6, fur_d)
    elif kind == "deer":
        hide, hide_d, light = rgb("#b5713c"), rgb("#8a5128"), rgb("#f2dcc0")
        for lx, o in ((15, s), (18, -s), (29, -s), (32, s)):
            cv.line(lx, 30, lx + o * 1.5, 43, hide_d, 2.2)
            cv.rect(lx - 1 + o * 1.5, 42, lx + 1.2 + o * 1.5, 44, rgb("#3b2a20"))
        cv.ellipse(23, 27, 11, 6.5, hide)
        cv.ellipse(23, 30, 9, 3, light)
        cv.ellipse(12.5, 24, 2.2, 2.6, rgb("#ffffff"))
        cv.line(31, 25, 35, 16, hide, 4.5)
        cv.ellipse(37, 14, 5, 3.4, hide, 0.25)
        cv.ellipse(40.5, 15.5, 2, 1.6, hide_d)
        cv.circle(37, 12.6, 0.9, P["eye"])
        cv.ellipse(34, 10, 1.4, 2.8, hide_d, -0.4)
        for i, (ax, ay) in enumerate(((35, 8), (37, 7))):
            cv.line(ax, ay, ax - 2 + i * 3, ay - 6, rgb("#e8d2a8"), 1.0)
            cv.line(ax - 1 + i * 3, ay - 3, ax - 3 + i * 4, ay - 5, rgb("#e8d2a8"), 0.9)
        for k in range(4):
            cv.circle(19 + k * 3.5, 24 + (k % 2), 0.8, light)
    elif kind == "duck":
        body, body_d, head = rgb("#8f7a63"), rgb("#6d5a47"), rgb("#2f9e5b")
        cv.ellipse(22, 33, 11, 6, body_d)
        cv.ellipse(22, 32, 10, 5, body)
        cv.ellipse(18, 31, 6, 2.6, rgb("#c9c2b4"))
        cv.poly([(12, 29), (8, 27), (11, 32)], body_d)
        cv.rect(28, 25, 31, 29, rgb("#ffffff"))
        cv.circle(31, 22, 4.2, head)
        cv.ellipse(36, 23, 3, 1.4, rgb("#ffc23a"))
        cv.circle(32, 21, 0.9, P["eye"])
        cv.ellipse(22, 38.5 + s * 0.4, 12, 1.2, rgb("#bfeeff"))
    elif kind == "wolf":
        fur, fur_d, light = rgb("#7c7f93"), rgb("#575a6b"), rgb("#c9cbd6")
        for lx, o in ((15, s), (18, -s), (29, -s), (32, s)):
            cv.line(lx, 30, lx + o * 1.5, 42, fur_d, 2.6)
        cv.poly([(12, 25), (4, 20 + s), (6, 27)], fur_d)
        cv.ellipse(22, 27, 11, 6.5, fur)
        cv.ellipse(22, 30.5, 8, 2.6, light)
        cv.ellipse(34, 22, 6, 5, fur)
        cv.poly([(37, 21), (44, 23), (37, 26)], fur)
        cv.circle(43.5, 23, 1.1, P["eye"])
        cv.poly([(31, 18), (32, 12), (35, 17)], fur_d)
        cv.poly([(34, 18), (36, 12), (38, 18)], fur)
        cv.circle(36, 21, 1.0, rgb("#ffd23f"))


def draw_danger(cv, kind, frame):
    s = [0, 1][frame]
    if kind == "spider":
        body, body_d, mark = rgb("#3b2f4a"), rgb("#251c30"), rgb("#e0392b")
        for side in (-1, 1):
            for k in range(4):
                ang = math.radians(-50 + k * 33) + (0.15 if (k + s) % 2 else -0.1)
                bx, by = 24 + side * 4, 33
                kx, ky = bx + side * math.cos(ang) * 9, by + math.sin(ang) * 6 - 4
                ex, ey = kx + side * 5, ky + 7
                cv.line(bx, by, kx, ky, body_d, 1.4)
                cv.line(kx, ky, ex, ey, body_d, 1.2)
        cv.ellipse(24, 37, 7.5, 6, body)
        cv.ellipse(24, 37, 2.2, 3, mark)
        cv.circle(24, 29, 4.5, body)
        for ex in (22, 26):
            cv.circle(ex, 28, 1.1, rgb("#ff5a4a"))
    elif kind == "wildcat":
        fur, fur_d, light = rgb("#c98a4a"), rgb("#9a6232"), rgb("#f2dcb8")
        for lx, o in ((14, s), (17, -s), (29, -s), (32, s)):
            cv.line(lx, 32, lx + o * 2, 42, fur_d, 2.6)
        cv.line(10, 30, 5, 24 - s * 2, fur_d, 3)
        cv.ellipse(22, 30, 11, 5.8, fur)
        cv.ellipse(22, 33, 8, 2.4, light)
        for k in range(4):
            cv.line(16 + k * 4, 26, 17 + k * 4, 30, fur_d, 1.2)
        cv.circle(34, 26, 5.2, fur)
        cv.poly([(31, 22), (31.5, 15), (34.5, 21)], fur_d)
        cv.poly([(35, 21), (37.5, 15), (38.5, 22)], fur)
        cv.line(31.5, 15, 31.5, 13, rgb("#2b2033"), 0.8)
        cv.line(37.5, 15, 37.5, 13, rgb("#2b2033"), 0.8)
        cv.circle(36.5, 25.5, 1.1, rgb("#d6f05a"))
        cv.ellipse(38.5, 28, 1.6, 1.1, rgb("#e8a0a0"))
    elif kind == "bear":
        fur, fur_d, fur_l = rgb("#6b4a33"), rgb("#4a3222"), rgb("#8f6848")
        for lx, o in ((10, s), (15, -s), (31, -s), (36, s)):
            cv.rect(lx - 2.5 + o, 32, lx + 2.5 + o, 44, fur_d)
        cv.ellipse(23, 28, 16, 11, fur)
        cv.ellipse(20, 23, 11, 5, fur_l)
        cv.circle(39, 24, 7.5, fur)
        cv.circle(36, 17.5, 2.6, fur_d)
        cv.circle(42, 18, 2.6, fur_d)
        cv.ellipse(44.5, 26.5, 3.2, 2.6, rgb("#c9a27a"))
        cv.circle(46.5, 25.5, 1.2, rgb("#2b2033"))
        cv.circle(40.5, 22.5, 1.1, rgb("#2b2033"))


def swap_colors(cv, mapping):
    """Exact colour swap on a Canvas before reduction (fills are exact)."""
    a = np.asarray(cv.img).copy()
    for src, dst in mapping.items():
        m = (a[..., 0] == src[0]) & (a[..., 1] == src[1]) & (a[..., 2] == src[2]) & (a[..., 3] > 0)
        a[m, 0], a[m, 1], a[m, 2] = dst[0], dst[1], dst[2]
    cv.img = Image.fromarray(a, "RGBA")
    cv.d = ImageDraw.Draw(cv.img)


def draw_rare(cv, kind, frame):
    s = [0, 1][frame]
    if kind == "white_stag":
        draw_creature(cv, "deer", frame)
        swap_colors(cv, {rgb("#b5713c"): rgb("#f6f2ea"), rgb("#8a5128"): rgb("#d9d2c6"),
                         rgb("#f2dcc0"): rgb("#ffffff"), rgb("#e8d2a8"): rgb("#ffd23f")})
        # extra-grand golden antlers
        for i, (ax, ay) in enumerate(((35, 8), (37, 7))):
            cv.line(ax, ay, ax - 4 + i * 6, ay - 7, rgb("#ffd23f"), 1.2)
            cv.line(ax - 2 + i * 4, ay - 4, ax - 5 + i * 8, ay - 5, rgb("#ffd23f"), 1.0)
    elif kind == "moose":
        hide, hide_d, light = rgb("#5a3d2a"), rgb("#3e2a1c"), rgb("#7a5a40")
        for lx, o in ((12, s), (16, -s), (31, -s), (35, s)):
            cv.line(lx, 30, lx + o * 1.5, 45, hide_d, 3.0)
        cv.ellipse(23, 26, 14, 8.5, hide)
        cv.ellipse(18, 21, 8, 3.5, light)
        cv.poly([(15, 18), (24, 14), (30, 19)], hide_d)  # shoulder hump
        cv.line(33, 23, 37, 18, hide, 6)
        cv.ellipse(41, 19, 6, 4, hide, 0.3)
        cv.ellipse(45.5, 21, 2.6, 2.4, hide_d)
        cv.line(39, 23, 39, 28, hide_d, 2)  # bell
        cv.circle(40, 16.5, 1.0, P["eye"])
        for side in (-1, 1):  # broad palmate antlers
            cx, cy = 38 + side * 1.5, 13
            cv.ellipse(cx + side * 5, cy - 3, 6, 3, rgb("#e8d2a8"), side * -0.4)
            for k in range(3):
                cv.line(cx + side * (3 + k * 3), cy - 4, cx + side * (4 + k * 3), cy - 8, rgb("#e8d2a8"), 1.0)
    elif kind == "otter":
        fur, fur_d, belly = rgb("#7a5234"), rgb("#56382a"), rgb("#c9a27a")
        cv.ellipse(24, 38.5, 15, 2.2, rgb("#bfeeff"))
        cv.ellipse(22, 34, 12, 4.8, fur)
        cv.ellipse(24, 36, 8, 2.2, belly)
        cv.poly([(10, 33), (2, 30 + s * 2), (10, 36)], fur_d)
        cv.circle(34, 31, 5, fur)
        cv.ellipse(37.5, 33, 3.2, 2.4, belly)
        cv.circle(36, 29.5, 1.0, P["eye"])
        cv.circle(39.5, 32, 0.9, rgb("#2b2033"))
        cv.circle(31.5, 27.5, 1.3, fur_d)
        for k in range(2):
            cv.line(38, 33 + k, 43, 32 + k * 2, rgb("#f2e4d0"), 0.5)
    elif kind == "loon":
        body = rgb("#2b2b38")
        cv.ellipse(24, 38.5 + s * 0.3, 14, 1.4, rgb("#bfeeff"))
        cv.ellipse(23, 33, 12, 5.5, body)
        for k in range(5):  # checker back
            for j in range(2):
                cv.rect(15 + k * 3.2, 30.5 + j * 2.5, 16.4 + k * 3.2, 31.7 + j * 2.5, rgb("#f4f4f4"))
        cv.poly([(31, 31), (34, 22), (37, 24), (35, 32)], body)
        cv.rect(32.5, 26, 35.5, 27.2, rgb("#f4f4f4"))
        cv.circle(36, 21.5, 3.8, body)
        cv.poly([(39, 21), (45, 22.3), (39, 23.2)], rgb("#1a1a22"))
        cv.circle(37, 20.5, 1.0, rgb("#e0392b"))
    elif kind == "fox":
        fur, fur_d, light = rgb("#e8692a"), rgb("#b84a1a"), rgb("#fff3e6")
        for lx, o in ((16, s), (19, -s), (29, -s), (32, s)):
            cv.line(lx, 31, lx + o * 1.5, 41, rgb("#2b2033"), 2.0)
        cv.poly([(13, 27), (2, 22 - s * 2), (1, 28), (12, 31)], fur)
        cv.circle(2.5, 25 - s, 2.8, light)
        cv.ellipse(23, 28, 10, 5.5, fur)
        cv.ellipse(24, 31, 7, 2.2, light)
        cv.circle(34, 24, 5, fur)
        cv.poly([(36, 25), (43, 26.5), (36, 28.5)], light)
        cv.circle(42.8, 26.3, 1.0, rgb("#2b2033"))
        cv.poly([(31, 21), (31.5, 14), (35, 20)], fur_d)
        cv.poly([(35, 20), (37.5, 14), (38.5, 21)], fur)
        cv.circle(36, 23, 1.0, P["eye"])
    elif kind == "owl":
        body, body_d, light = rgb("#8a6a4a"), rgb("#5e4630"), rgb("#d9c4a0")
        cv.rect(8, 41, 40, 44, rgb("#6b4a33"))  # branch
        cv.ellipse(24, 30, 9, 12, body)
        cv.ellipse(24, 33, 6, 8, light)
        for k in range(3):
            cv.line(20 + k * 4, 30, 21 + k * 4, 38, body_d, 0.8)
        cv.circle(24, 18, 7.5, body)
        cv.poly([(17, 13), (18, 6), (21, 12)], body_d)
        cv.poly([(27, 12), (30, 6), (31, 13)], body_d)
        for ex in (21, 27):
            cv.circle(ex, 18, 3, rgb("#ffd23f"))
            cv.circle(ex, 18, 1.4, rgb("#2b2033"))
        cv.poly([(23, 20.5), (25, 20.5), (24, 24)], rgb("#e8a83a"))
        cv.rect(20, 40, 22, 42, rgb("#e8a83a"))
        cv.rect(26, 40, 28, 42, rgb("#e8a83a"))
    elif kind == "spirit":
        glow, core, deep = rgb("#7af0ff"), rgb("#e8ffff"), rgb("#3ab8e0")
        cv.ellipse(24, 40, 12, 2.6, rgb("#bfeeff"))
        cv.poly([(15, 40), (18, 22), (30, 22), (33, 40), (29, 37 - s), (24, 40), (19, 37 + s)], glow)
        cv.poly([(19, 38), (21, 25), (27, 25), (29, 38)], deep)
        cv.circle(24, 17, 6.5, glow)
        cv.circle(24, 17, 4.2, core)
        for ex in (22, 26):
            cv.circle(ex, 17, 0.9, rgb("#2b6a8a"))
        for k in range(3):  # floating motes
            cv.circle(12 + k * 12, 9 + ((k + s) % 2) * 3, 1.2, core)
    elif kind == "elder_bear":
        draw_danger(cv, "bear", frame)
        swap_colors(cv, {rgb("#6b4a33"): rgb("#c08a3e"), rgb("#4a3222"): rgb("#8a5a24"),
                         rgb("#8f6848"): rgb("#e8b862"), rgb("#c9a27a"): rgb("#f2dcb0")})
        for k in range(3):  # silver battle scars
            cv.line(17 + k * 5, 22, 20 + k * 5, 30, rgb("#f4f1ea"), 0.9)


RARE_KINDS = ["white_stag", "moose", "otter", "loon", "fox", "owl", "spirit", "elder_bear"]
CREATURE_ORDER = ["rabbit", "deer", "duck", "wolf", "spider", "wildcat", "bear"] + RARE_KINDS


def make_creatures():
    atlas = Image.new("RGBA", (2 * 48, len(CREATURE_ORDER) * 48), (0, 0, 0, 0))
    for r, kind in enumerate(CREATURE_ORDER):
        for f in range(2):
            cv = Canvas(48, 48)
            if kind in RARE_KINDS:
                draw_rare(cv, kind, f)
            elif kind in ("spider", "wildcat", "bear"):
                draw_danger(cv, kind, f)
            else:
                draw_creature(cv, kind, f)
            sh = (24, 44, 11, 2.5)
            if kind in ("duck", "otter", "loon", "spirit", "owl"):
                sh = None
            elif kind in ("bear", "elder_bear", "moose"):
                sh = (24, 44, 17, 3)
            atlas.paste(cv.finish(True, sh), (f * 48, r * 48))
    atlas.save(OUT / "creatures.png")


# ------------------------------------------------------------------- decor
# Each decor sprite is 64x64 drawn so that its "foot" sits at (32, 40): the
# map cell centre plus 8px, so TileMapLayer can place it with no offset.
FX, FY = 32, 40


def tree_pine(cv, rnd, snow=False):
    trunk = rgb("#7a4f2f")
    cv.rect(FX - 2, FY - 6, FX + 2, FY + 1, trunk)
    cols = [rgb("#1f6b4a"), rgb("#2a8a58"), rgb("#3fae6a")]
    if snow:
        cols = [rgb("#2a6f5a"), rgb("#3a8a6a"), rgb("#eef4fb")]
    for i, (w, y) in enumerate(((13, FY - 4), (11, FY - 13), (8.5, FY - 21), (6, FY - 28))):
        cv.poly([(FX - w, y), (FX + w, y), (FX, y - 13)], cols[0])
        cv.poly([(FX - w + 1.5, y - 1.5), (FX + 1, y - 1.5), (FX, y - 12)], cols[1])
        cv.poly([(FX - w + 3, y - 2.5), (FX - 2, y - 2.5), (FX - 1, y - 9)], cols[2])


def tree_round(cv, rnd, leaf, leaf_l, leaf_d, trunk, birch=False):
    tw = 2.2 if not birch else 1.8
    cv.rect(FX - tw, FY - 14, FX + tw, FY + 1, trunk)
    if birch:
        for k in range(4):
            y = FY - 2 - k * 3.5
            cv.rect(FX - tw, y, FX - tw + 2.2 + (k % 2), y + 1, rgb("#2b2033"))
    blobs = [(0, -24, 13), (-8, -18, 9), (8, -18, 9.5), (-4, -31, 8), (5, -30, 8)]
    for bx, by, r in blobs:
        cv.circle(FX + bx, FY + by + 1.5, r, leaf_d)
    for bx, by, r in blobs:
        cv.circle(FX + bx, FY + by, r * 0.92, leaf)
    for bx, by, r in blobs[:3]:
        cv.circle(FX + bx - r * 0.3, FY + by - r * 0.35, r * 0.45, leaf_l)


def tree_willow(cv, rnd):
    cv.rect(FX - 2.5, FY - 14, FX + 2.5, FY + 1, rgb("#6b4a33"))
    cv.circle(FX, FY - 24, 14, rgb("#4f9e48"))
    for k in range(9):
        x = FX - 13 + k * 3.2
        cv.line(x, FY - 24, x + rnd.uniform(-1, 1), FY - 4 - rnd.uniform(0, 4), rgb("#6cc24a"), 2.2)
    cv.circle(FX - 4, FY - 29, 6, rgb("#8ee05e"))


def tree_snag(cv, rnd):
    c = rgb("#8a7a6a")
    cv.rect(FX - 2, FY - 26, FX + 2, FY + 1, c)
    cv.line(FX, FY - 18, FX - 9, FY - 26, c, 1.6)
    cv.line(FX, FY - 14, FX + 8, FY - 21, c, 1.6)
    cv.rect(FX - 2, FY - 26, FX, FY + 1, rgb("#a89a8a"))


def bush(cv, rnd, berries=False):
    for bx, by, r in ((-5, -5, 6), (5, -5, 6), (0, -9, 7)):
        cv.circle(FX + bx, FY + by + 1, r, rgb("#2f7a3a"))
        cv.circle(FX + bx, FY + by, r * 0.9, rgb("#4fae4a"))
    cv.circle(FX - 3, FY - 11, 3, rgb("#7fd468"))
    if berries:
        for _ in range(7):
            cv.circle(FX + rnd.uniform(-9, 9), FY - rnd.uniform(3, 13), 1.4, rgb("#c2185b"))


def boulder(cv, big):
    r = 10 if big else 6
    cv.ellipse(FX, FY - r * 0.6, r * 1.25, r, rgb("#7d7a86"))
    cv.ellipse(FX - r * 0.25, FY - r * 0.8, r, r * 0.75, rgb("#a3a0ad"))
    cv.ellipse(FX - r * 0.45, FY - r * 1.05, r * 0.4, r * 0.3, rgb("#cfcbd6"))
    if big:
        cv.ellipse(FX + 4, FY - 3, 3, 1.6, rgb("#7fb85a"))


def flowers(cv, rnd, col):
    for _ in range(6):
        x, y = FX + rnd.uniform(-10, 10), FY - 8 + rnd.uniform(-6, 6)
        cv.line(x, y, x, y + 4, rgb("#3f8a3a"), 0.8)
        for a in range(5):
            ang = a * 2 * math.pi / 5
            cv.circle(x + math.cos(ang) * 1.4, y + math.sin(ang) * 1.4, 1.0, col)
        cv.circle(x, y, 0.8, rgb("#ffe066"))


def fern(cv, rnd):
    for k in range(7):
        ang = math.pi + (k / 6) * math.pi
        ex, ey = FX + math.cos(ang) * 11, FY - 4 + math.sin(ang) * 9
        cv.line(FX, FY - 2, ex, ey, rgb("#3f9e4a"), 2.0)
        cv.line(FX, FY - 2, (FX + ex) / 2, (FY - 2 + ey) / 2 - 1, rgb("#6cc95a"), 1.0)


def mushrooms(cv, rnd):
    for x, y, r in ((-5, -2, 3.2), (3, 0, 4), (7, -4, 2.4)):
        cv.rect(FX + x - 1, FY + y - 3, FX + x + 1, FY + y + 1, rgb("#f5ead6"))
        cv.ellipse(FX + x, FY + y - 3, r, r * 0.65, rgb("#e0392b"))
        cv.circle(FX + x - r * 0.3, FY + y - 3.6, 0.7, rgb("#ffffff"))


def reeds(cv, rnd, cattail):
    for k in range(7):
        x = FX - 9 + k * 3 + rnd.uniform(-1, 1)
        top = FY - 14 - rnd.uniform(0, 8)
        cv.line(x, FY, x + rnd.uniform(-2, 2), top, rgb("#6aa84f"), 1.2)
        if cattail and k % 2 == 0:
            cv.ellipse(x + 0.5, top + 3, 1.3, 3, rgb("#7a4a2a"))


def lily(cv, rnd, flower):
    for x, y, r in ((-5, -2, 5), (5, 2, 4)):
        cv.circle(FX + x, FY - 8 + y, r, rgb("#3f9e5a"))
        cv.poly([(FX + x, FY - 8 + y), (FX + x + r, FY - 8 + y - 1), (FX + x + r, FY - 8 + y + 1.5)], (0, 0, 0, 0))
        cv.circle(FX + x - 1, FY - 9 + y, r * 0.5, rgb("#5cc06e"))
    if flower:
        for a in range(6):
            ang = a * math.pi / 3
            cv.ellipse(FX - 5 + math.cos(ang) * 1.6, FY - 11 + math.sin(ang) * 1.6, 1.6, 1.0, rgb("#ffc1d9"), ang)
        cv.circle(FX - 5, FY - 11, 1.0, rgb("#ffe066"))


def driftwood(cv, rnd):
    cv.line(FX - 12, FY - 3, FX + 11, FY - 6, rgb("#b8a48c"), 3.2)
    cv.line(FX + 3, FY - 5, FX + 8, FY - 11, rgb("#b8a48c"), 1.6)
    cv.line(FX - 12, FY - 4, FX + 11, FY - 7, rgb("#d8c8b0"), 1.0)


def stump(cv, rnd):
    cv.ellipse(FX, FY - 2, 6, 3, rgb("#6b4a33"))
    cv.rect(FX - 6, FY - 8, FX + 6, FY - 2, rgb("#7a5538"))
    cv.ellipse(FX, FY - 8, 6, 3, rgb("#d9b98a"))
    cv.ellipse(FX, FY - 8, 3, 1.5, rgb("#b8946a"))


def tuft(cv, rnd):
    for k in range(6):
        x = FX - 6 + k * 2.4
        cv.line(x, FY - 2, x + rnd.uniform(-2, 2), FY - 9 - rnd.uniform(0, 3), rgb("#8ee05e"), 1.2)


def peak(cv, rnd, variant, snowy):
    """A rocky mountain peak filling most of the cell, foot at FY."""
    rock, rock_l, rock_d = rgb("#8f8496"), rgb("#b9adbd"), rgb("#5e5468")
    if snowy:
        rock, rock_l, rock_d = rgb("#a59bb0"), rgb("#d6cee0"), rgb("#6e6480")
    w = [26, 22, 24][variant]
    h = [42, 36, 46][variant]
    px = FX + [0, -3, 3][variant]
    base_y = FY + 4
    top = (px, base_y - h)
    cv.poly([(FX - w - 2, base_y), top, (FX + w + 2, base_y)], rock_d)
    cv.poly([(FX - w, base_y), top, (px + 3, base_y)], rock_l)
    cv.poly([(px + 1, base_y), top, (FX + w, base_y)], rock)
    # secondary ridge
    sx = FX + [12, -14, -12][variant]
    sh = h * 0.55
    cv.poly([(sx - 12, base_y), (sx, base_y - sh), (sx + 12, base_y)], rock_d)
    cv.poly([(sx - 10, base_y), (sx, base_y - sh), (sx + 1, base_y)], rock_l)
    # cracks / strata
    for k in range(3):
        y = base_y - h * (0.25 + k * 0.2)
        cv.line(px - 6 + k * 3, y, px + 4 + k * 2, y + 3, rock_d, 1.0)
    # snow cap
    cap = h * (0.55 if snowy else 0.3)
    t = cap / h
    cv.poly([(px - w * t, top[1] + cap), top, (px + w * t, top[1] + cap),
             (px + w * t * 0.4, top[1] + cap * 0.8), (px, top[1] + cap * 0.95),
             (px - w * t * 0.5, top[1] + cap * 0.75)], rgb("#f4f8ff"))
    cv.poly([(px + 1, top[1] + 2), top, (px + w * t, top[1] + cap), (px + w * t * 0.4, top[1] + cap * 0.8)], rgb("#cfdcf0"))


def sapling(cv, rnd):
    cv.line(FX, FY, FX, FY - 14, rgb("#7a4f2f"), 1.6)
    for bx, by, r in ((-4, -14, 4), (4, -15, 4), (0, -19, 4.5)):
        cv.circle(FX + bx, FY + by, r, rgb("#4fae4a"))
    cv.circle(FX - 2, FY - 19, 2, rgb("#8ee05e"))


def dug_patch(cv, rnd):
    cv.ellipse(FX, FY - 8, 13, 9, rgb("#8a5a34"))
    cv.ellipse(FX, FY - 7, 10, 6.5, rgb("#6b4428"))
    for _ in range(6):
        cv.circle(FX + rnd.uniform(-11, 11), FY - 8 + rnd.uniform(-7, 7), 1.4, rgb("#a8744a"))


def plot(cv, rnd):
    cv.rect(FX - 14, FY - 22, FX + 14, FY + 4, rgb("#7a4c2a"))
    for k in range(4):
        y = FY - 19 + k * 6.5
        cv.rect(FX - 13, y, FX + 13, y + 3, rgb("#5e3920"))
        cv.rect(FX - 13, y + 3, FX + 13, y + 4, rgb("#9a6a40"))


def crop(cv, rnd, kind, stage):
    plot(cv, rnd)
    rows = [FY - 17, FY - 4]
    cols = [FX - 7, FX + 7]
    for cy in rows:
        for cx in cols:
            if stage == 0:
                cv.circle(cx, cy, 1.6, rgb("#c9a06a"))
                continue
            leaf = rgb("#5cc05a")
            if kind == "carrot":
                h = [0, 4, 7, 9][stage]
                for dx in (-2, 0, 2):
                    cv.line(cx, cy, cx + dx, cy - h, leaf, 1.4)
                if stage == 3:
                    cv.poly([(cx - 2, cy - 1), (cx + 2, cy - 1), (cx, cy + 4)], rgb("#ff8a2a"))
            elif kind == "potato":
                r = [0, 2.5, 4, 5.5][stage]
                cv.circle(cx, cy - r * 0.6, r, rgb("#4f9e48"))
                cv.circle(cx - 1, cy - r, r * 0.5, rgb("#7fd468"))
                if stage == 3:
                    cv.circle(cx + 2, cy - r, 1.3, rgb("#ffffff"))
            else:
                r = [0, 2, 3.5, 4][stage]
                cv.circle(cx, cy - 2, r, rgb("#4f9e48"))
                if stage >= 2:
                    pr = 2.5 if stage == 2 else 5
                    cv.ellipse(cx + 1, cy + 1, pr, pr * 0.8, rgb("#ff9a2a") if stage == 3 else rgb("#c9d65a"))


# name -> (drawer, tall).  tall decor is y-sorted with the player.
DECOR = [
    ("pine0", lambda c, r: tree_pine(c, r), True),
    ("pine1", lambda c, r: tree_pine(c, r), True),
    ("birch0", lambda c, r: tree_round(c, r, rgb("#9ad65a"), rgb("#c8f07a"), rgb("#5fa83f"), rgb("#f2efe6"), True), True),
    ("birch1", lambda c, r: tree_round(c, r, rgb("#b5e05a"), rgb("#e0f58a"), rgb("#78b03f"), rgb("#f2efe6"), True), True),
    ("maple0", lambda c, r: tree_round(c, r, rgb("#ff7a2f"), rgb("#ffb35a"), rgb("#c9481f"), rgb("#6b4a33")), True),
    ("maple1", lambda c, r: tree_round(c, r, rgb("#e8452f"), rgb("#ff8a5a"), rgb("#a82a1f"), rgb("#6b4a33")), True),
    ("oak0", lambda c, r: tree_round(c, r, rgb("#4fae4a"), rgb("#86d868"), rgb("#2f7a3a"), rgb("#6b4a33")), True),
    ("oak1", lambda c, r: tree_round(c, r, rgb("#5cba52"), rgb("#9be070"), rgb("#36843f"), rgb("#7a5538")), True),
    ("willow", tree_willow, True),
    ("snag", tree_snag, True),
    ("snowpine", lambda c, r: tree_pine(c, r, True), True),
    ("boulder", lambda c, r: boulder(c, True), True),
    ("bush", lambda c, r: bush(c, r), True),
    ("berrybush", lambda c, r: bush(c, r, True), True),
    ("stump", stump, True),
    ("cattail", lambda c, r: reeds(c, r, True), True),
    ("rock", lambda c, r: boulder(c, False), False),
    ("flowers_y", lambda c, r: flowers(c, r, rgb("#ffe066")), False),
    ("flowers_p", lambda c, r: flowers(c, r, rgb("#ff8fb1")), False),
    ("flowers_v", lambda c, r: flowers(c, r, rgb("#b48cff")), False),
    ("flowers_w", lambda c, r: flowers(c, r, rgb("#ffffff")), False),
    ("fern", fern, False),
    ("mushrooms", mushrooms, False),
    ("reeds", lambda c, r: reeds(c, r, False), False),
    ("lily", lambda c, r: lily(c, r, False), False),
    ("lilyflower", lambda c, r: lily(c, r, True), False),
    ("driftwood", driftwood, False),
    ("tuft", tuft, False),
    ("peak0", lambda c, r: peak(c, r, 0, False), True),
    ("peak1", lambda c, r: peak(c, r, 1, False), True),
    ("peak2", lambda c, r: peak(c, r, 2, False), True),
    ("snowpeak0", lambda c, r: peak(c, r, 0, True), True),
    ("snowpeak1", lambda c, r: peak(c, r, 2, True), True),
    ("sapling", sapling, True),
    ("dug", dug_patch, False),
    ("plot", plot, False),
] + [(f"{k}{st}", (lambda kk, ss: (lambda c, r: crop(c, r, kk, ss)))(k, st), False)
     for k in ("carrot", "potato", "pumpkin") for st in range(4)]


def make_decor():
    cols = 8
    rows = (len(DECOR) + cols - 1) // cols
    atlas = Image.new("RGBA", (cols * 64, rows * 64), (0, 0, 0, 0))
    for i, (name, fn, tall) in enumerate(DECOR):
        cv = Canvas(64, 64)
        fn(cv, random.Random(i * 13 + 5))
        is_tree = name.startswith(("pine", "birch", "maple", "oak", "willow", "snow", "snag"))
        sh = (FX, FY, 12, 3.5) if is_tree else ((FX, FY - 1, 9, 2.5) if tall and not name.startswith(("peak", "snowpeak")) else None)
        atlas.paste(cv.finish(True, sh), ((i % cols) * 64, (i // cols) * 64))
    atlas.save(OUT / "decor.png")
    # index list for GDScript
    lines = ["# Generated by tools/gen_art.py - decor atlas index (name, tall)"]
    for i, (name, _, tall) in enumerate(DECOR):
        lines.append(f"{i} {name} {'tall' if tall else 'flat'}")
    (OUT / "decor_index.txt").write_text("\n".join(lines) + "\n")


# ------------------------------------------------------------------- props
def make_props():
    atlas = Image.new("RGBA", (8 * 64, 2 * 64), (0, 0, 0, 0))
    cells = []
    # (cells 0..12; see scripts/art.gd)
    # 0 tent
    cv = Canvas(64, 64)
    cv.poly([(10, 46), (32, 14), (54, 46)], rgb("#c9481f"))
    cv.poly([(32, 14), (54, 46), (36, 46)], rgb("#ff7a2f"))
    cv.poly([(32, 14), (10, 46), (24, 46)], rgb("#e8622a"))
    cv.poly([(27, 46), (32, 30), (37, 46)], rgb("#5a2a14"))
    cv.line(32, 14, 32, 9, rgb("#6b4a33"), 1.4)
    cells.append(cv.finish(True, (32, 46, 22, 3)))

    def fire(frame, lit):
        cv = Canvas(64, 64)
        for a in range(6):
            ang = a * math.pi / 3 + 0.3
            cv.ellipse(32 + math.cos(ang) * 8, 42 + math.sin(ang) * 3.5, 3, 2.2, rgb("#8d8f86"))
        cv.line(24, 42, 40, 38, rgb("#7a4f2f"), 3)
        cv.line(24, 38, 40, 42, rgb("#6b4a33"), 3)
        if lit:
            sw = 2 if frame else -2
            cv.poly([(24, 40), (32 + sw, 18), (40, 40)], rgb("#ff6a2a"))
            cv.poly([(27, 40), (32 - sw, 24), (37, 40)], rgb("#ffb23a"))
            cv.poly([(29.5, 40), (32 + sw * 0.5, 30), (34.5, 40)], rgb("#fff1a8"))
        else:
            cv.ellipse(32, 39, 6, 2.5, rgb("#4a4a52"))
            cv.circle(31, 38, 1.2, rgb("#d9521f"))
        return cv.finish(True)
    cells += [fire(0, True), fire(1, True), fire(0, False)]
    # 4 chest
    cv = Canvas(64, 64)
    cv.rect(18, 26, 46, 44, rgb("#8a5428"))
    cv.rect(18, 26, 46, 32, rgb("#a8693a"))
    cv.rect(18, 31, 46, 33, rgb("#ffd23f"))
    cv.rect(30, 30, 34, 37, rgb("#ffd23f"))
    cv.rect(18, 26, 20, 44, rgb("#ffd23f"))
    cv.rect(44, 26, 46, 44, rgb("#ffd23f"))
    cells.append(cv.finish(True, (32, 44, 15, 2.5)))
    # 5 X mark
    cv = Canvas(64, 64)
    cv.line(20, 22, 44, 46, rgb("#e0392b"), 5)
    cv.line(44, 22, 20, 46, rgb("#e0392b"), 5)
    cells.append(cv.finish(True))
    # 6 dug hole
    cv = Canvas(64, 64)
    cv.ellipse(32, 34, 12, 7, rgb("#8a5a34"))
    cv.ellipse(32, 35, 9, 5, rgb("#4a2e1c"))
    for k in range(5):
        cv.circle(20 + k * 6, 26 + (k % 2) * 16, 2, rgb("#a8744a"))
    cells.append(cv.finish(False))
    # 7 bite "!"
    cv = Canvas(64, 64)
    cv.rect(29, 14, 35, 34, rgb("#ffe066"))
    cv.rect(29, 38, 35, 44, rgb("#ffe066"))
    cells.append(cv.finish(True))
    # 8 arrow (pointing right)
    cv = Canvas(64, 64)
    cv.line(14, 32, 48, 32, rgb("#8a5428"), 1.6)
    cv.poly([(48, 28.5), (55, 32), (48, 35.5)], rgb("#b8bec9"))
    cv.poly([(14, 32), (10, 28), (18, 28)], rgb("#ffffff"))
    cv.poly([(14, 32), (10, 36), (18, 36)], rgb("#ffffff"))
    cells.append(cv.finish(True))
    # 9 sparkle star
    cv = Canvas(64, 64)
    cv.poly([(32, 18), (35, 29), (46, 32), (35, 35), (32, 46), (29, 35), (18, 32), (29, 29)], rgb("#fff6c2"))
    cv.circle(32, 32, 3, rgb("#ffffff"))
    cells.append(cv.finish(False))
    # 10 swing arc (pointing right)
    cv = Canvas(64, 64)
    outer = [(32 + math.cos(a) * 24, 32 + math.sin(a) * 24) for a in [math.radians(d) for d in range(-70, 71, 10)]]
    inner = [(32 + math.cos(a) * 15, 32 + math.sin(a) * 15) for a in [math.radians(d) for d in range(70, -71, -10)]]
    cv.poly(outer + inner, rgb("#ffffff"))
    cells.append(cv.finish(False))
    # 11 red alert "!"
    cv = Canvas(64, 64)
    cv.rect(29, 14, 35, 34, rgb("#ff4a3a"))
    cv.rect(29, 38, 35, 44, rgb("#ff4a3a"))
    cells.append(cv.finish(True))
    # 12 heart
    cv = Canvas(64, 64)
    cv.circle(26, 28, 7, rgb("#ff5e78"))
    cv.circle(38, 28, 7, rgb("#ff5e78"))
    cv.poly([(19.5, 31), (44.5, 31), (32, 45)], rgb("#ff5e78"))
    cv.circle(24, 26, 2, rgb("#ffc2cf"))
    cells.append(cv.finish(True))
    for i, c in enumerate(cells):
        atlas.paste(c, ((i % 8) * 64, (i // 8) * 64))
    atlas.save(OUT / "props.png")


# ------------------------------------------------------------------- items
def make_items():
    icons = []

    def icon(fn):
        cv = Canvas(32, 32)
        fn(cv)
        icons.append(cv.finish(True))

    def meat(cv, cooked):
        c = rgb("#8a4a22") if cooked else rgb("#e0524a")
        cv.ellipse(18, 15, 10, 7.5, shade(c, 0.8), -0.5)
        cv.ellipse(17, 14, 9, 6.5, c, -0.5)
        cv.line(8, 24, 12, 19, rgb("#f5ead6"), 3)
        cv.circle(7, 25, 2.2, rgb("#f5ead6"))
        cv.ellipse(19, 12, 4, 2, rgb("#ffb3a8") if not cooked else rgb("#c8844a"), -0.5)

    def fish(cv, cooked):
        c = rgb("#d9a05a") if cooked else rgb("#8fc3e0")
        cv.ellipse(16, 16, 10, 5.5, c)
        cv.poly([(6, 16), (1, 10), (2, 22)], shade(c, 0.85))
        cv.circle(22, 14.5, 1.3, P["eye"])
        cv.line(10, 18, 22, 18, shade(c, 1.15), 1)

    def berries(cv):
        for x, y in ((12, 18), (18, 20), (15, 13), (21, 14), (10, 24), (19, 25)):
            cv.circle(x, y, 3.4, rgb("#7b2d8b"))
            cv.circle(x - 1, y - 1, 1, rgb("#c58ad6"))
        cv.ellipse(18, 8, 4, 2, rgb("#3f9e4a"), -0.4)

    def trailmix(cv):
        cv.rect(8, 9, 24, 26, rgb("#d9b06a"))
        cv.rect(8, 9, 24, 12, rgb("#b8904a"))
        for x, y, c in ((12, 16, "#6b3f24"), (18, 18, "#ff5e57"), (14, 21, "#ffd23f"), (20, 23, "#6b3f24")):
            cv.circle(x, y, 1.8, rgb(c))

    def hide(cv):
        cv.poly([(6, 10), (12, 6), (20, 7), (27, 11), (25, 24), (16, 27), (7, 23)], rgb("#b5835a"))
        for x, y in ((12, 13), (18, 17), (14, 21), (21, 12)):
            cv.circle(x, y, 1.4, rgb("#dcb48a"))

    def wood(cv):
        for i, y in enumerate((10, 16, 22)):
            cv.rect(5 + i, y - 2.5, 26 - i, y + 2.5, rgb("#8a5428"))
            cv.ellipse(26 - i, y, 2, 2.5, rgb("#e0bc84"))

    def arrows(cv):
        for k in range(3):
            y = 10 + k * 6
            cv.line(5, y + 4, 25, y - 2, rgb("#8a5428"), 1.2)
            cv.poly([(25, y - 4.5), (29, y - 3.2), (26, y + 0.5)], rgb("#b8bec9"))

    def purse(cv):
        cv.ellipse(16, 19, 9, 8, rgb("#8a5428"))
        cv.rect(12, 9, 20, 13, rgb("#6b3f24"))
        cv.circle(16, 6.5, 3, rgb("#ffd23f"))

    def compass(cv):
        cv.circle(16, 16, 11, rgb("#d4a64a"))
        cv.circle(16, 16, 8.5, rgb("#f5ead6"))
        cv.poly([(16, 8), (18, 16), (14, 16)], rgb("#e0392b"))
        cv.poly([(16, 24), (18, 16), (14, 16)], rgb("#3b3f4a"))

    def gem(cv):
        cv.poly([(10, 12), (16, 6), (22, 12), (16, 27)], rgb("#2ec4b6"))
        cv.poly([(10, 12), (16, 6), (16, 12)], rgb("#8af0e4"))
        cv.poly([(16, 12), (22, 12), (16, 27)], rgb("#1f9488"))

    def idol(cv):
        cv.ellipse(16, 11, 6, 6.5, rgb("#ffd23f"))
        cv.rect(11, 15, 21, 27, rgb("#ffd23f"))
        cv.rect(17, 15, 21, 27, rgb("#d9a514"))
        cv.rect(13, 10, 15, 12, P["eye"])
        cv.rect(17, 10, 19, 12, P["eye"])

    def tmap(cv):
        cv.poly([(5, 8), (12, 6), (20, 8), (27, 6), (27, 25), (20, 27), (12, 25), (5, 27)], rgb("#f2dcab"))
        cv.line(9, 22, 14, 15, rgb("#c2503a"), 1)
        cv.line(14, 15, 19, 18, rgb("#c2503a"), 1)
        cv.line(20, 11, 24, 15, rgb("#e0392b"), 1.6)
        cv.line(24, 11, 20, 15, rgb("#e0392b"), 1.6)

    def shovel(cv):
        cv.line(6, 26, 20, 12, rgb("#8a5428"), 2)
        cv.poly([(19, 9), (25, 5), (28, 11), (24, 16)], rgb("#b8bec9"))
        cv.line(4, 24, 8, 28, rgb("#6b3f24"), 2.5)

    def bow(cv):
        pts = [(10 + 9 * math.sin(math.pi * t), 3 + 26 * t) for t in [i / 12 for i in range(13)]]
        for a, b in zip(pts, pts[1:]):
            cv.line(*a, *b, rgb("#8a5428"), 2)
        cv.line(10, 3, 10, 29, rgb("#f5ead6"), 0.8)

    def tent(cv):
        cv.poly([(4, 26), (16, 6), (28, 26)], rgb("#ff7a2f"))
        cv.poly([(13, 26), (16, 16), (19, 26)], rgb("#5a2a14"))

    def rod(cv):
        cv.line(4, 28, 26, 4, rgb("#6b3f24"), 1.4)
        cv.line(26, 4, 27, 18, rgb("#e8e8e8"), 0.6)
        cv.circle(27, 19, 1.8, rgb("#e0392b"))

    def coin(cv):
        cv.circle(16, 16, 10, rgb("#d9a514"))
        cv.circle(15, 15, 9, rgb("#ffd23f"))
        cv.rect(14, 10, 16.5, 21, rgb("#d9a514"))

    def seeds(cv, col):
        cv.rect(8, 7, 24, 26, rgb("#e8d5a0"))
        cv.rect(8, 7, 24, 10, rgb("#c9b07a"))
        cv.circle(16, 18, 4.5, col)
        for x, y in ((11, 23), (21, 23), (13, 13)):
            cv.circle(x, y, 1.2, rgb("#8a6a3a"))

    def carrot(cv):
        cv.poly([(10, 10), (16, 8), (14, 28)], rgb("#ff8a2a"))
        cv.line(13, 9, 9, 3, rgb("#5cc05a"), 1.6)
        cv.line(13, 9, 15, 2, rgb("#5cc05a"), 1.6)
        cv.line(13, 9, 19, 4, rgb("#5cc05a"), 1.6)

    def potato(cv, baked):
        c = rgb("#b07a3a") if baked else rgb("#d9b06a")
        cv.ellipse(16, 17, 10, 7, c, 0.3)
        for x, y in ((12, 15), (19, 19), (17, 13)):
            cv.circle(x, y, 1, shade(c, 0.7))
        if baked:
            cv.ellipse(16, 15, 5, 2, rgb("#fff1a8"), 0.3)

    def pumpkin(cv):
        for dx in (-6, 0, 6):
            cv.ellipse(16 + dx, 18, 6.5, 8, rgb("#ff9a2a") if dx == 0 else rgb("#e8782a"))
        cv.rect(15, 6, 18, 11, rgb("#6b8a2a"))

    def silk(cv):
        cv.circle(16, 16, 9, rgb("#f2f2f8"))
        for k in range(4):
            cv.line(9, 10 + k * 4, 23, 12 + k * 4, rgb("#c9c9d9"), 0.8)

    def pelt(cv, col, spots):
        cv.poly([(5, 10), (11, 5), (21, 6), (27, 10), (26, 24), (16, 28), (6, 24)], col)
        for x, y in ((11, 13), (17, 18), (13, 21), (21, 12)):
            cv.circle(x, y, 1.6, spots)

    def knife(cv):
        cv.poly([(8, 24), (22, 6), (25, 8), (12, 26)], rgb("#c9ced8"))
        cv.line(7, 25, 4, 29, rgb("#6b3f24"), 3.5)

    def hatchet(cv):
        cv.line(8, 28, 20, 6, rgb("#8a5428"), 2.2)
        cv.poly([(16, 6), (26, 4), (27, 14), (19, 12)], rgb("#b8bec9"))

    def worms(cv):
        for k, col in enumerate((rgb("#e88a8a"), rgb("#d97070"))):
            pts = [(6 + i * 2.5, 14 + k * 6 + math.sin(i * 1.3 + k) * 3) for i in range(9)]
            for a, b in zip(pts, pts[1:]):
                cv.line(*a, *b, col, 2.2)

    def mushroom(cv):
        cv.rect(14, 16, 18, 27, rgb("#f5ead6"))
        cv.ellipse(16, 15, 10, 6.5, rgb("#c98a4a"))
        cv.ellipse(13, 13, 3, 1.6, rgb("#e8b07a"))

    def stone(cv):
        cv.ellipse(16, 18, 9, 7, rgb("#8d8f86"))
        cv.ellipse(14, 16, 4, 2.5, rgb("#c9c9bd"))

    def antler(cv, col, big):
        cv.line(8, 27, 14, 14, col, 2.4)
        cv.line(14, 14, 22, 5, col, 2.0)
        cv.line(13, 17, 6, 10, col, 1.6)
        cv.line(18, 10, 24, 12, col, 1.6)
        if big:
            cv.line(20, 7, 27, 4, col, 1.4)
            cv.line(11, 21, 4, 18, col, 1.4)

    def moose_antler(cv):
        cv.ellipse(18, 13, 10, 6, rgb("#e8d2a8"), -0.3)
        for k in range(4):
            cv.line(11 + k * 5, 9, 12 + k * 5, 3, rgb("#e8d2a8"), 1.6)
        cv.line(10, 16, 6, 27, rgb("#c9b088"), 2.6)

    def feather(cv, col, tip):
        cv.ellipse(16, 15, 4.5, 11, col, 0.5)
        cv.line(9, 28, 22, 3, rgb("#f4f1ea"), 0.8)
        cv.ellipse(20, 7, 2.6, 3.5, tip, 0.5)

    def golden_trout(cv):
        cv.ellipse(16, 16, 11, 5.8, rgb("#ffcf3f"))
        cv.poly([(5, 16), (0, 10), (1, 22)], rgb("#e8a514"))
        cv.line(8, 17, 24, 17, rgb("#ff8a5a"), 1.4)
        cv.circle(23, 14.5, 1.3, P["eye"])
        cv.circle(13, 13, 1, rgb("#fff6c2"))

    def pearl(cv):
        cv.circle(16, 16, 9, rgb("#c9f4ff"))
        cv.circle(16, 16, 6.5, rgb("#e8ffff"))
        cv.circle(13, 12, 2.4, rgb("#ffffff"))

    def claw(cv, col, n):
        for k in range(n):
            x = 8 + k * 6
            cv.poly([(x, 26), (x + 4, 26), (x + 6, 8), (x + 2, 12)], col)

    def fang(cv):
        cv.poly([(12, 6), (20, 6), (16, 27)], rgb("#f4f1ea"))
        cv.line(16, 8, 16, 22, rgb("#d9d2c6"), 1)

    def amber(cv):
        cv.poly([(10, 8), (22, 6), (26, 18), (16, 27), (7, 19)], rgb("#ffa51f"))
        cv.poly([(10, 8), (16, 7), (14, 15), (8, 17)], rgb("#ffd06a"))
        cv.circle(17, 17, 1.6, rgb("#5a3a1a"))

    def egg(cv):
        cv.ellipse(16, 17, 7, 9.5, rgb("#bfe8ff"))
        for x, y in ((13, 14), (18, 20), (15, 22), (19, 12)):
            cv.circle(x, y, 0.9, rgb("#5a8aa8"))

    def gold_mushroom(cv):
        cv.rect(14, 16, 18, 27, rgb("#f5ead6"))
        cv.ellipse(16, 15, 10, 6.5, rgb("#ffcf3f"))
        cv.ellipse(12, 13, 3, 1.6, rgb("#fff6c2"))
        cv.circle(20, 12, 1, rgb("#ffffff"))

    def arrowhead(cv):
        cv.poly([(16, 4), (24, 20), (16, 17), (8, 20)], rgb("#5a5466"))
        cv.poly([(16, 4), (16, 17), (8, 20)], rgb("#7d7688"))
        cv.rect(14, 18, 18, 27, rgb("#8a5428"))

    def old_coin(cv):
        cv.circle(16, 16, 10, rgb("#a8b0b8"))
        cv.circle(16, 16, 7.5, rgb("#c9d0d8"))
        cv.rect(13, 12, 19, 14, rgb("#7d858c"))
        cv.rect(15, 14, 17, 21, rgb("#7d858c"))

    def boot(cv):
        cv.rect(10, 5, 18, 21, rgb("#6b4a33"))
        cv.poly([(10, 18), (26, 20), (26, 27), (10, 27)], rgb("#5a3a22"))
        cv.circle(22, 10, 2.5, rgb("#3f9e5a"))

    def bottle(cv):
        cv.ellipse(16, 19, 7, 9, rgb("#7ad0a8"))
        cv.rect(14, 4, 18, 11, rgb("#7ad0a8"))
        cv.rect(14, 3, 18, 5, rgb("#8a5428"))
        cv.rect(13, 15, 19, 22, rgb("#f2dcab"))

    def trophy(cv, col, shine):
        cv.poly([(5, 10), (11, 5), (21, 6), (27, 10), (26, 24), (16, 28), (6, 24)], col)
        for x, y in ((11, 12), (20, 19), (14, 22)):
            cv.circle(x, y, 1.3, shine)
        cv.poly([(22, 4), (23.5, 8), (27, 9), (23.5, 10), (22, 14), (20.5, 10), (17, 9), (20.5, 8)], shine)

    def rabbit_foot(cv):
        cv.ellipse(16, 18, 6, 9, rgb("#f2e4d0"))
        cv.ellipse(16, 25, 5, 3, rgb("#e8d2b8"))
        cv.line(16, 9, 16, 3, rgb("#c2503a"), 1.6)
        cv.circle(16, 3, 2, rgb("#ffd23f"))

    for fn in (lambda c: meat(c, False), lambda c: meat(c, True), lambda c: fish(c, False),
               lambda c: fish(c, True), berries, trailmix, hide, wood, arrows, purse, compass, gem,
               idol, tmap, shovel, bow, tent, rod, coin,
               lambda c: seeds(c, rgb("#ff8a2a")), lambda c: seeds(c, rgb("#d9b06a")),
               lambda c: seeds(c, rgb("#e8782a")), carrot, lambda c: potato(c, False),
               lambda c: potato(c, True), pumpkin, silk,
               lambda c: pelt(c, rgb("#c98a4a"), rgb("#7a4a22")),
               lambda c: pelt(c, rgb("#6b4a33"), rgb("#8f6848")), knife, hatchet, worms, stone, mushroom,
               lambda c: antler(c, rgb("#f6f2ea"), True), moose_antler,
               lambda c: pelt(c, rgb("#e8692a"), rgb("#fff3e6")),
               lambda c: feather(c, rgb("#2b2b38"), rgb("#f4f4f4")),
               lambda c: feather(c, rgb("#8a6a4a"), rgb("#d9c4a0")), golden_trout, pearl,
               lambda c: claw(c, rgb("#ffd23f"), 3), rabbit_foot,
               lambda c: antler(c, rgb("#e8d2a8"), False), fang, amber,
               lambda c: claw(c, rgb("#f4f1ea"), 2), lambda c: claw(c, rgb("#d9d2c6"), 3),
               egg, gold_mushroom, arrowhead, old_coin, boot, bottle,
               lambda c: trophy(c, rgb("#ff7ad9"), rgb("#7af0ff")),
               lambda c: trophy(c, rgb("#c9d0dc"), rgb("#ffffff")),
               lambda c: trophy(c, rgb("#ffcf3f"), rgb("#fff6c2"))):
        icon(fn)
    atlas = Image.new("RGBA", (8 * 32, ((len(icons) + 7) // 8) * 32), (0, 0, 0, 0))
    for i, c in enumerate(icons):
        atlas.paste(c, ((i % 8) * 32, (i // 8) * 32))
    atlas.save(OUT / "items.png")


# ------------------------------------------------------------------- store
def make_store():
    cv = Canvas(96, 96)
    log, log_d, log_l = rgb("#a8693a"), rgb("#7a4a2a"), rgb("#c98a52")
    # walls of stacked logs
    for k in range(8):
        y = 44 + k * 4
        cv.rect(14, y, 82, y + 4, log if k % 2 == 0 else log_d)
        cv.rect(14, y, 82, y + 1, log_l)
        cv.circle(14, y + 2, 2, rgb("#e0bc84"))
        cv.circle(82, y + 2, 2, rgb("#e0bc84"))
    # roof
    cv.poly([(6, 46), (48, 14), (90, 46)], rgb("#1f8a80"))
    cv.poly([(48, 14), (90, 46), (66, 46)], rgb("#2fb6a6"))
    for k in range(5):
        y = 22 + k * 5
        w = (y - 14) * 42 / 32
        cv.line(48 - w, y, 48 + w, y, rgb("#177066"), 0.8)
    cv.rect(62, 18, 68, 30, rgb("#8d8f86"))  # chimney
    # door + windows
    cv.rect(42, 58, 54, 76, rgb("#5a3a22"))
    cv.circle(51, 67, 1, rgb("#ffd23f"))
    for wx in (22, 62):
        cv.rect(wx, 54, wx + 12, 64, rgb("#ffe9a8"))
        cv.rect(wx + 5.5, 54, wx + 6.5, 64, log_d)
        cv.rect(wx, 58.5, wx + 12, 59.5, log_d)
    # sign board with a kayak
    cv.rect(30, 36, 66, 46, rgb("#f5ead6"))
    cv.rect(30, 36, 66, 37, rgb("#d9c49a"))
    cv.ellipse(48, 41, 13, 2.6, HULLS[0][0])
    cv.ellipse(48, 41, 3, 1.4, rgb("#2b2033"))
    # porch + kayak rack
    cv.rect(10, 76, 86, 80, rgb("#c98a52"))
    for i, hull in enumerate(HULLS):
        cv.ellipse(84, 58 + i * 7, 9, 2.6, hull[0], math.pi / 2 * 0.0)
    cv.rect(91, 54, 93, 80, log_d)
    cv.rect(75, 54, 77, 80, log_d)
    im = cv.finish(True, (48, 80, 40, 5))
    im.save(OUT / "store.png")


def make_icon():
    img = Image.new("RGBA", (128, 128), rgb("#2c8fd6"))
    k = Image.open(OUT / "kayak.png").crop((64, 0, 128, 64)).resize((128, 128), Image.NEAREST)
    img.alpha_composite(k)
    img.save(ROOT / "icon.png")


if __name__ == "__main__":
    make_water_noise()
    make_terrain()
    make_kayak()
    make_player()
    make_creatures()
    make_decor()
    make_props()
    make_items()
    make_store()
    make_icon()
    for old in ("sprites.png", "tiles.png"):
        p = OUT / old
        if p.exists():
            p.unlink()
    print("art written to", OUT)
