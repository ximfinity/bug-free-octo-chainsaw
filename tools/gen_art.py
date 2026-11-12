#!/usr/bin/env python3
"""Generates the game's placeholder pixel art (original, CC0) into assets/.

Run:  python3 tools/gen_art.py
Requires Pillow.  Every texture is a fixed-grid atlas so it can be swapped for a
third-party pack (e.g. Kenney CC0) later by redrawing the same cells.
"""
import random
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets"
OUT.mkdir(exist_ok=True)
T = 16


def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) + (255,)


def jitter(c, amt, rnd):
    d = rnd.randint(-amt, amt)
    return tuple(max(0, min(255, v + d)) for v in c[:3]) + (255,)


def fill_noise(img, ox, oy, w, h, base, amt, seed):
    rnd = random.Random(seed)
    for y in range(h):
        for x in range(w):
            img.putpixel((ox + x, oy + y), jitter(base, amt, rnd))


def ascii_sprite(img, ox, oy, rows, pal):
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch in pal:
                img.putpixel((ox + x, oy + y), pal[ch])


# ---------------------------------------------------------------- tiles.png
# Layout (8 columns x 3 rows of 16x16):
# row0: deep0 deep1 shallow0 shallow1 river0 river1 sand0 sand1
# row1: grass0 grass1 forest0 forest1 hill0 hill1 mountain0 mountain1
# row2: snow0 snow1 dock hole marsh0 marsh1 - -
DEEP = rgb("#24508c")
SHALLOW = rgb("#3f8cbe")
RIVER = rgb("#3a7db9")
SAND = rgb("#dcc78a")
GRASS = rgb("#5ca046")
HILL = rgb("#7f9a52")
ROCK = rgb("#7a7470")
SNOW = rgb("#eef2f5")


def water_tile(img, ox, oy, base, seed, streak):
    fill_noise(img, ox, oy, T, T, base, 4, seed)
    rnd = random.Random(seed + 99)
    for _ in range(3):
        x, y = rnd.randint(0, 11), rnd.randint(0, 15)
        for i in range(rnd.randint(2, 4)):
            img.putpixel((ox + x + i, oy + y), streak)


def tree(img, ox, oy, cx, cy, rnd):
    canopy = rgb("#2d6e36")
    dark = rgb("#1f5228")
    light = rgb("#48904a")
    trunk = rgb("#6b4a2b")
    for y in range(-4, 5):
        for x in range(-4, 5):
            if x * x + y * y <= 17:
                c = canopy
                if x + y > 3:
                    c = dark
                elif x + y < -3:
                    c = light
                px, py = ox + cx + x, oy + cy + y
                if 0 <= px - ox < T and 0 <= py - oy < T:
                    img.putpixel((px, py), jitter(c, 6, rnd))
    for y in range(5, 7):
        py = oy + cy + y
        if py - oy < T:
            img.putpixel((ox + cx, py), trunk)


def mountain_tile(img, ox, oy, seed):
    rnd = random.Random(seed)
    fill_noise(img, ox, oy, T, T, rgb("#6c665f"), 6, seed)
    light = rgb("#9a938b")
    dark = rgb("#4c4742")
    peak_x = rnd.randint(5, 10)
    for y in range(2, 16):
        half = (y - 2) * 0.6 + 1
        for x in range(T):
            dx = x - peak_x
            if abs(dx) <= half:
                img.putpixel((ox + x, oy + y), jitter(light if dx < 0 else dark, 5, rnd))
    for y in range(2, 5):
        for x in range(T):
            if abs(x - peak_x) <= (y - 2) * 0.6 + 0.5:
                img.putpixel((ox + x, oy + y), SNOW)


def make_tiles():
    img = Image.new("RGBA", (8 * T, 3 * T), (0, 0, 0, 0))
    water_tile(img, 0 * T, 0, DEEP, 1, rgb("#30609e"))
    water_tile(img, 1 * T, 0, DEEP, 2, rgb("#30609e"))
    water_tile(img, 2 * T, 0, SHALLOW, 3, rgb("#6fb2d8"))
    water_tile(img, 3 * T, 0, SHALLOW, 4, rgb("#6fb2d8"))
    water_tile(img, 4 * T, 0, RIVER, 5, rgb("#8cc6e6"))
    water_tile(img, 5 * T, 0, RIVER, 6, rgb("#8cc6e6"))
    fill_noise(img, 6 * T, 0, T, T, SAND, 8, 7)
    fill_noise(img, 7 * T, 0, T, T, SAND, 8, 8)
    # grass with tufts
    for i, s in enumerate((9, 10)):
        ox = i * T
        fill_noise(img, ox, T, T, T, GRASS, 7, s)
        rnd = random.Random(s)
        for _ in range(5):
            x, y = rnd.randint(1, 14), rnd.randint(2, 15)
            img.putpixel((ox + x, T + y), rgb("#79c25c"))
            img.putpixel((ox + x, T + y - 1), rgb("#79c25c"))
    # forest
    for i, s in enumerate((11, 12)):
        ox = (2 + i) * T
        fill_noise(img, ox, T, T, T, rgb("#4e8f3d"), 6, s)
        rnd = random.Random(s)
        tree(img, ox, T, 5 + i * 2, 5, rnd)
        tree(img, ox, T, 11 - i * 2, 9, rnd)
    # hills
    for i, s in enumerate((13, 14)):
        ox = (4 + i) * T
        fill_noise(img, ox, T, T, T, HILL, 6, s)
        rnd = random.Random(s)
        for _ in range(2):
            cx, cy = rnd.randint(3, 12), rnd.randint(4, 12)
            for x in range(-3, 4):
                img.putpixel((ox + cx + x, T + cy - (3 - abs(x)) // 2), rgb("#a6b872"))
                img.putpixel((ox + cx + x, T + cy + 1), rgb("#5f7a3c"))
    mountain_tile(img, 6 * T, T, 15)
    mountain_tile(img, 7 * T, T, 16)
    fill_noise(img, 0, 2 * T, T, T, SNOW, 5, 17)
    fill_noise(img, T, 2 * T, T, T, rgb("#dfe6ec"), 5, 18)
    # dock planks
    fill_noise(img, 2 * T, 2 * T, T, T, rgb("#9a6a3c"), 6, 19)
    for y in (3, 7, 11, 15):
        for x in range(T):
            img.putpixel((2 * T + x, 2 * T + y), rgb("#5c3d22"))
    # dug hole on sand/grass
    fill_noise(img, 3 * T, 2 * T, T, T, GRASS, 6, 20)
    for y in range(T):
        for x in range(T):
            d = (x - 7.5) ** 2 + (y - 8) ** 2
            if d < 20:
                img.putpixel((3 * T + x, 2 * T + y), rgb("#4a3220"))
            elif d < 30:
                img.putpixel((3 * T + x, 2 * T + y), rgb("#7a5634"))
    # marsh
    for i, s in enumerate((21, 22)):
        ox = (4 + i) * T
        fill_noise(img, ox, 2 * T, T, T, rgb("#4d8a6a"), 6, s)
        rnd = random.Random(s)
        for _ in range(4):
            x, y = rnd.randint(1, 14), rnd.randint(3, 15)
            for k in range(3):
                img.putpixel((ox + x, 2 * T + y - k), rgb("#a3b85a"))
    img.save(OUT / "tiles.png")


# ------------------------------------------------------------- sprites.png
# 16x16 grid, 8 columns.  Index = row*8 + col.  See scripts/art.gd.
SKIN = rgb("#f1c27d")
HAIR = rgb("#5b3a1e")
SHIRT = rgb("#d9472b")
PANTS = rgb("#34495e")
BOOT = rgb("#2b2b2b")
OUT_C = rgb("#1b1b1b")
WHITE = rgb("#ffffff")

PLAYER_DOWN = [
    "................",
    "......kkkk......",
    ".....khhhhk.....",
    ".....hhhhhh.....",
    ".....hssssh.....",
    ".....sksksks....",
    ".....ssssss.....",
    "......ssss......",
    "....rrrrrrrr....",
    "...srrrrrrrrs...",
    "...s.rrrrrr.s...",
    ".....rrrrrr.....",
    ".....pppppp.....",
    ".....pp..pp.....",
    ".....pp..pp.....",
    ".....bb..bb.....",
]
PLAYER_UP = [
    "................",
    "......kkkk......",
    ".....khhhhk.....",
    ".....hhhhhh.....",
    ".....hhhhhh.....",
    ".....hhhhhh.....",
    ".....shhhhs.....",
    "......ssss......",
    "....rrrrrrrr....",
    "...srrrrrrrrs...",
    "...s.rrrrrr.s...",
    ".....rrrrrr.....",
    ".....pppppp.....",
    ".....pp..pp.....",
    ".....pp..pp.....",
    ".....bb..bb.....",
]
PLAYER_SIDE = [
    "................",
    "......kkkk......",
    ".....khhhhk.....",
    ".....hhhhhs.....",
    ".....hhhsss.....",
    ".....hhsssks....",
    ".....hssssss....",
    "......ssss......",
    ".....rrrrrr.....",
    ".....rrrrrr.....",
    ".....rrsrrr.....",
    ".....rrsrrr.....",
    ".....pppppp.....",
    ".....pp.pp......",
    "....pp...pp.....",
    "....bb...bb.....",
]
PLAYER_PAL = {"k": OUT_C, "h": HAIR, "s": SKIN, "r": SHIRT, "p": PANTS, "b": BOOT}

RABBIT = [
    "................",
    "................",
    "..........w.w...",
    "..........w.w...",
    "..........wwww..",
    ".........wwkww..",
    "...wwwwwwwwwwp..",
    "..wwwwwwwwwww...",
    ".wwwwwwwwwwww...",
    ".Wwwwwwwwwwww...",
    "..wwwwwwwwww....",
    "...ww....ww.....",
    "................",
    "................",
    "................",
    "................",
]
RABBIT_PAL = {"w": rgb("#b8a48a"), "W": WHITE, "k": OUT_C, "p": rgb("#e89aa0")}

DEER = [
    "............a.a.",
    "............aaa.",
    "...........dddd.",
    "...........ddkd.",
    "..........ddddn.",
    "..........ddd...",
    "..dddddddddd....",
    ".ddddddddddd....",
    ".dlldddddddd....",
    ".dlldddddddd....",
    "..dddddddddd....",
    "..d.d....d.d....",
    "..d.d....d.d....",
    "..d.d....d.d....",
    "..k.k....k.k....",
    "................",
]
DEER_PAL = {"d": rgb("#9c6b3d"), "l": rgb("#e8d6b8"), "a": rgb("#5d4128"), "k": OUT_C, "n": OUT_C}

DUCK = [
    "................",
    "................",
    "................",
    "..........ggg...",
    ".........ggkgo..",
    ".........gggoo..",
    "..........gg....",
    "...bbbbbbbbb....",
    "..bbwwwbbbbbb...",
    "..bbbwwwbbbbb...",
    "...bbbbbbbbb....",
    "................",
    "................",
    "................",
    "................",
    "................",
]
DUCK_PAL = {"g": rgb("#2f7d4f"), "k": OUT_C, "o": rgb("#f0a020"), "b": rgb("#8a6a4a"), "w": rgb("#d8d0c0")}

WOLF = [
    "................",
    "..........g..g..",
    "..........gg.gg.",
    "..........ggggg.",
    "..........gykgg.",
    "..........ggggkk",
    "...gggggggggg...",
    ".ggggggggggggg..",
    "gg.gggggggggg...",
    "g..gllllllggg...",
    "...gggggggggg...",
    "...g.g....g.g...",
    "...g.g....g.g...",
    "...k.k....k.k...",
    "................",
    "................",
]
WOLF_PAL = {"g": rgb("#6e6e78"), "l": rgb("#a8a8b0"), "k": OUT_C, "y": rgb("#f5d742")}

TENT = [
    "................",
    "................",
    ".......k........",
    "......kok.......",
    ".....koook......",
    "....kooodok.....",
    "...koooddook....",
    "..kooooddoook...",
    ".koooooddooook..",
    "kooooooddoooook.",
    "kkkkkkkddkkkkkkk",
    "................",
    "................",
    "................",
    "................",
    "................",
]
TENT_PAL = {"k": rgb("#3d2a14"), "o": rgb("#e07b2e"), "d": rgb("#5a2f10")}

FIRE_A = [
    "................",
    "................",
    "................",
    ".......y........",
    "......yy........",
    "......yoy.......",
    ".....yooy.y.....",
    ".....orrooy.....",
    "....oorrroo.....",
    "....orrrrro.....",
    "....oorrroo.....",
    "...wwwoooww.....",
    "..wwwwwwwwwww...",
    "...ww.....ww....",
    "................",
    "................",
]
FIRE_B = [
    "................",
    "................",
    "................",
    "........y.......",
    "........yy......",
    ".......yoy......",
    ".....y.yooy.....",
    ".....yoorro.....",
    ".....oorrroo....",
    ".....orrrrro....",
    "....oorrroo.....",
    "...wwwoooww.....",
    "..wwwwwwwwwww...",
    "...ww.....ww....",
    "................",
    "................",
]
FIRE_PAL = {"y": rgb("#ffe066"), "o": rgb("#ff9a1f"), "r": rgb("#e0391b"), "w": rgb("#6b4a2b")}

FIRE_OUT = [
    "................",
    "................",
    "................",
    "................",
    "................",
    "................",
    "................",
    "................",
    "......aa........",
    ".....aaaa.......",
    "....aagaaa......",
    "...wwwaaaww.....",
    "..wwwwwwwwwww...",
    "...ww.....ww....",
    "................",
    "................",
]
FIRE_OUT_PAL = {"a": rgb("#5a5a5a"), "g": rgb("#8a3a1a"), "w": rgb("#4a3220")}

ARROW = [
    "................",
    "................",
    "................",
    "................",
    "................",
    "................",
    "................",
    ".ff.........h...",
    "..sssssssssshh..",
    ".ff.........h...",
    "................",
    "................",
    "................",
    "................",
    "................",
    "................",
]
ARROW_PAL = {"f": rgb("#e8e8e8"), "s": rgb("#8a5a2b"), "h": rgb("#9aa0a8")}

CHEST = [
    "................",
    "................",
    "................",
    "................",
    "..kkkkkkkkkkkk..",
    "..kbbbbbbbbbbk..",
    "..kbbbbbbbbbbk..",
    "..kyyyyyyyyyyk..",
    "..kbbbbyybbbbk..",
    "..kbbbbkkbbbbk..",
    "..kbbbbbbbbbbk..",
    "..kyyyyyyyyyyk..",
    "..kkkkkkkkkkkk..",
    "................",
    "................",
    "................",
]
CHEST_PAL = {"k": rgb("#3a2410"), "b": rgb("#8a5a2b"), "y": rgb("#e6b422")}

DIG_HINT = [
    "................",
    "................",
    "................",
    "................",
    "................",
    "................",
    "......d..d......",
    "....d..dd...d...",
    "...ddd.dddd.....",
    ".....dddd.dd....",
    "...d..dd..d.....",
    "......d....d....",
    "................",
    "................",
    "................",
    "................",
]
DIG_PAL = {"d": rgb("#6a4a2a")}

X_MARK = [
    "................",
    "................",
    "..rr........rr..",
    "..rrr......rrr..",
    "...rrr....rrr...",
    "....rrr..rrr....",
    ".....rrrrrr.....",
    "......rrrr......",
    "......rrrr......",
    ".....rrrrrr.....",
    "....rrr..rrr....",
    "...rrr....rrr...",
    "..rrr......rrr..",
    "..rr........rr..",
    "................",
    "................",
]
X_PAL = {"r": rgb("#d0201a")}


def icon_from(rows, pal):
    img = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    ascii_sprite(img, 0, 0, rows, pal)
    return img


def blob_icon(color, shape="round", accent=None, seed=0):
    img = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    rnd = random.Random(seed)
    for y in range(T):
        for x in range(T):
            dx, dy = x - 7.5, y - 7.5
            inside = False
            if shape == "round":
                inside = dx * dx + dy * dy < 25
            elif shape == "oval":
                inside = (dx / 6.5) ** 2 + (dy / 4) ** 2 < 1
            elif shape == "square":
                inside = abs(dx) < 5.5 and abs(dy) < 4.5
            elif shape == "diamond":
                inside = abs(dx) + abs(dy) < 6
            elif shape == "tall":
                inside = (dx / 3.5) ** 2 + (dy / 6.5) ** 2 < 1
            if inside:
                img.putpixel((x, y), jitter(color, 8, rnd))
                if (dx * dx + dy * dy) > 16 and (dx + dy) > 3:
                    img.putpixel((x, y), jitter(tuple(int(v * 0.7) for v in color[:3]) + (255,), 4, rnd))
    if accent:
        for (x, y) in accent[1]:
            img.putpixel((x, y), accent[0])
    return img


def make_sprites():
    cols = 8
    cells = []
    cells.append(icon_from(PLAYER_DOWN, PLAYER_PAL))      # 0
    cells.append(icon_from(PLAYER_UP, PLAYER_PAL))        # 1
    cells.append(icon_from(PLAYER_SIDE, PLAYER_PAL))      # 2
    cells.append(icon_from(RABBIT, RABBIT_PAL))           # 3
    cells.append(icon_from(DEER, DEER_PAL))               # 4
    cells.append(icon_from(DUCK, DUCK_PAL))               # 5
    cells.append(icon_from(WOLF, WOLF_PAL))               # 6
    cells.append(icon_from(TENT, TENT_PAL))               # 7
    cells.append(icon_from(FIRE_A, FIRE_PAL))             # 8
    cells.append(icon_from(FIRE_B, FIRE_PAL))             # 9
    cells.append(icon_from(FIRE_OUT, FIRE_OUT_PAL))       # 10
    cells.append(icon_from(ARROW, ARROW_PAL))             # 11
    cells.append(icon_from(CHEST, CHEST_PAL))             # 12
    cells.append(icon_from(DIG_HINT, DIG_PAL))            # 13
    cells.append(icon_from(X_MARK, X_PAL))                # 14
    # 15: fish (swimming shadow)
    fish = blob_icon(rgb("#9fb8c8"), "oval", seed=3)
    for y in range(5, 11):
        fish.putpixel((1, y), rgb("#9fb8c8"))
        fish.putpixel((2, y), rgb("#9fb8c8"))
    fish.putpixel((12, 7), OUT_C)
    cells.append(fish)
    # item icons 16..
    cells.append(blob_icon(rgb("#c0392b"), "oval", (WHITE, [(3, 7), (4, 7), (3, 8)]), 4))  # 16 raw meat
    cells.append(blob_icon(rgb("#8a4a22"), "oval", (rgb("#c8a070"), [(3, 7), (4, 7)]), 5))  # 17 cooked meat
    cells.append(fish.copy())                                                                # 18 raw fish
    cf = blob_icon(rgb("#c98a3c"), "oval", seed=6)
    cells.append(cf)                                                                         # 19 cooked fish
    cells.append(blob_icon(rgb("#b08a5a"), "square", (rgb("#e0c090"), [(5, 6), (9, 9), (7, 8)]), 7))  # 20 hide
    wood = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    for i in range(3):
        for x in range(2, 14):
            for y in range(3 + i * 4, 6 + i * 4):
                wood.putpixel((x, y), rgb("#8a5a2b") if y % 4 else rgb("#5c3d22"))
        for y in range(3 + i * 4, 6 + i * 4):
            wood.putpixel((13, y), rgb("#d8b070"))
    cells.append(wood)                                                                       # 21 wood
    cells.append(icon_from(ARROW, ARROW_PAL))                                                # 22 arrows
    cells.append(blob_icon(rgb("#c8a060"), "square", (rgb("#6a3a1a"), [(5, 6), (8, 7), (10, 9), (6, 9)]), 8))  # 23 trail mix
    cells.append(blob_icon(rgb("#8a6a3a"), "round", (rgb("#f0c030"), [(7, 3), (8, 3), (7, 4), (8, 4)]), 9))  # 24 coin purse
    cells.append(blob_icon(rgb("#e6b422"), "tall", (OUT_C, [(6, 5), (9, 5)]), 10))          # 25 gold idol
    comp = blob_icon(rgb("#b08d57"), "round", seed=11)
    for y in range(4, 12):
        comp.putpixel((7, y), WHITE if y < 8 else rgb("#d0201a"))
    cells.append(comp)                                                                       # 26 compass
    cells.append(blob_icon(rgb("#2ec4b6"), "diamond", (WHITE, [(6, 5), (7, 5)]), 12))       # 27 gem
    tmap = blob_icon(rgb("#e8d5a0"), "square", seed=13)
    for (x, y) in [(5, 5), (6, 6), (7, 7), (8, 8), (9, 7), (10, 6), (5, 8), (10, 9)]:
        tmap.putpixel((x, y), rgb("#d0201a"))
    cells.append(tmap)                                                                       # 28 treasure map
    shovel = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    for i in range(9):
        shovel.putpixel((3 + i, 12 - i), rgb("#8a5a2b"))
    for y in range(1, 6):
        for x in range(10, 15):
            if abs(x - 12) + abs(y - 3) < 3:
                shovel.putpixel((x, y), rgb("#9aa0a8"))
    cells.append(shovel)                                                                     # 29 shovel
    bow = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    for y in range(1, 15):
        x = int(4 + 5 * (1 - ((y - 8) / 7) ** 2))
        bow.putpixel((x, y), rgb("#8a5a2b"))
        bow.putpixel((4, y), rgb("#e8e8e8"))
    cells.append(bow)                                                                        # 30 bow
    cells.append(icon_from(TENT, TENT_PAL))                                                  # 31 tent item
    cells.append(blob_icon(rgb("#f0c030"), "round", (rgb("#a07010"), [(7, 5), (7, 6), (7, 7), (7, 8), (7, 9), (8, 7)]), 14))  # 32 coin
    rod = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    for i in range(12):
        rod.putpixel((2 + i, 13 - i), rgb("#5c3d22"))
    for y in range(2, 12):
        rod.putpixel((13, y), rgb("#e8e8e8"))
    cells.append(rod)                                                                        # 33 fishing rod
    berries = blob_icon(rgb("#7b2d8b"), "round", (rgb("#2d8b3a"), [(7, 1), (8, 1), (8, 2)]), 15)
    cells.append(berries)                                                                    # 34 berries
    excl = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    for y in range(2, 10):
        for x in (7, 8):
            excl.putpixel((x, y), rgb("#ffe066"))
    for x in (7, 8):
        excl.putpixel((x, 12), rgb("#ffe066"))
        excl.putpixel((x, 13), rgb("#ffe066"))
    cells.append(excl)                                                                       # 35 "!" bite
    sheet = Image.new("RGBA", (cols * T, ((len(cells) + cols - 1) // cols) * T), (0, 0, 0, 0))
    for i, c in enumerate(cells):
        sheet.paste(c, ((i % cols) * T, (i // cols) * T))
    sheet.save(OUT / "sprites.png")


# --------------------------------------------------------------- kayak.png
# 32x16 frames, columns: empty, paddle-left, paddle-right ; rows: hull tiers
HULLS = [rgb("#f2c230"), rgb("#d9472b"), rgb("#2e86c1")]


def make_kayak():
    img = Image.new("RGBA", (3 * 32, 3 * 16), (0, 0, 0, 0))
    for row, hull in enumerate(HULLS):
        dark = tuple(int(v * 0.65) for v in hull[:3]) + (255,)
        for col in range(3):
            ox, oy = col * 32, row * 16
            for x in range(32):
                # hull half-width profile, pointing right (bow at x=31)
                t = x / 31.0
                hw = 4.6 * (1 - (2 * t - 1) ** 2) ** 0.6 + 0.4
                for y in range(16):
                    dy = y - 7.5
                    if abs(dy) <= hw:
                        c = hull if dy < hw - 1.2 else dark
                        if abs(dy) > hw - 0.9:
                            c = OUT_C
                        img.putpixel((ox + x, oy + y), c)
            # cockpit
            for x in range(12, 19):
                for y in range(6, 10):
                    img.putpixel((ox + x, oy + y), rgb("#222222"))
            if col > 0:
                # paddler head/torso
                for x in range(13, 18):
                    for y in range(5, 11):
                        if (x - 15) ** 2 + (y - 7.5) ** 2 < 6:
                            img.putpixel((ox + x, oy + y), SHIRT)
                for x in range(14, 17):
                    for y in range(6, 10):
                        if (x - 15) ** 2 + (y - 7.5) ** 2 < 2:
                            img.putpixel((ox + x, oy + y), HAIR)
                # paddle shaft across, angled by frame
                tilt = -1 if col == 1 else 1
                for i in range(-8, 9):
                    px = 15 + (i * tilt) // 4
                    py = int(7.5 + i)
                    if 0 <= py < 16:
                        img.putpixel((ox + px, oy + py), rgb("#3a3a3a"))
                for (bx, by) in ((15 - 2 * tilt, 0), (15 + 2 * tilt, 15)):
                    for k in range(-1, 2):
                        x = bx + k
                        if 0 <= x < 32:
                            img.putpixel((ox + x, oy + by), rgb("#202020"))
    img.save(OUT / "kayak.png")


# --------------------------------------------------------------- store.png
def make_store():
    img = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    rnd = random.Random(42)
    wall = rgb("#b5835a")
    roof = rgb("#2e86c1")
    for y in range(12, 30):
        for x in range(3, 29):
            img.putpixel((x, y), jitter(wall, 6, rnd))
    for y in range(4, 13):
        inset = (12 - y)
        for x in range(1 + inset, 31 - inset):
            img.putpixel((x, y), jitter(roof, 6, rnd))
    for x in range(1, 31):
        img.putpixel((x, 12), rgb("#1b5a85"))
    # door
    for y in range(20, 30):
        for x in range(14, 19):
            img.putpixel((x, y), rgb("#5c3d22"))
    # windows
    for (wx, wy) in ((6, 17), (22, 17)):
        for y in range(wy, wy + 5):
            for x in range(wx, wx + 5):
                img.putpixel((x, y), rgb("#bfe6ff"))
    # sign board with a little kayak
    for y in range(13, 17):
        for x in range(10, 23):
            img.putpixel((x, y), rgb("#f4ecd0"))
    for x in range(11, 22):
        img.putpixel((x, 15), rgb("#f2c230"))
    img.putpixel((16, 14), rgb("#d9472b"))
    # stacked kayaks out front
    for i, c in enumerate(HULLS):
        for x in range(2, 12):
            img.putpixel((x, 26 + i), c)
        for x in range(20, 30):
            img.putpixel((x, 28 - i), HULLS[(i + 1) % 3])
    img.save(OUT / "store.png")


def make_icon():
    img = Image.new("RGBA", (64, 64), rgb("#24508c"))
    k = Image.open(OUT / "kayak.png").crop((32, 0, 64, 16)).resize((64, 32), Image.NEAREST)
    img.alpha_composite(k, (0, 16))
    for y in range(52, 64):
        for x in range(64):
            img.putpixel((x, y), rgb("#5ca046"))
    img.save(ROOT / "icon.png")


if __name__ == "__main__":
    make_tiles()
    make_sprites()
    make_kayak()
    make_store()
    make_icon()
    print("art written to", OUT)
