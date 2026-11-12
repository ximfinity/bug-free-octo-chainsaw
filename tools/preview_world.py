#!/usr/bin/env python3
"""Python mirror of scripts/world/world_gen.gd for quick offline checks.

Usage:  python3 tools/preview_world.py [seed] [size] [out.png]

Uses OpenSimplex instead of Godot's FastNoiseLite, so the exact map differs
from the game for the same seed, but every generation step (quantile
classing, valley lakes, MST river carving, shallows/marsh, store and treasure
placement) follows the GDScript version, which makes this useful for
verifying connectivity and tuning parameters. Requires numpy, opensimplex, Pillow.
"""
import heapq
import sys
from collections import deque

import numpy as np
from opensimplex import OpenSimplex
from PIL import Image

DEEP, SHALLOW, RIVER, SAND, GRASS, FOREST, HILL, MOUNTAIN, SNOW, MARSH, DOCK = range(11)
KAYAK_OK = {DEEP, SHALLOW, RIVER, MARSH}
WALK_OK = {SHALLOW, SAND, GRASS, FOREST, HILL, MARSH, DOCK}
LAKE = {DEEP, SHALLOW}
WATER = {DEEP, SHALLOW, RIVER}
LAND = {SAND, GRASS, FOREST, HILL, MARSH, DOCK}
COLORS = {
    DEEP: (46, 86, 140), SHALLOW: (78, 140, 186), RIVER: (70, 128, 184), SAND: (226, 206, 150),
    GRASS: (120, 168, 90), FOREST: (70, 122, 66), HILL: (150, 160, 104), MOUNTAIN: (120, 110, 100),
    SNOW: (236, 236, 236), MARSH: (96, 142, 116), DOCK: (150, 106, 60),
}


def fbm(gen, w, h, freq, octaves):
    out = np.zeros((h, w))
    amp, f, total = 1.0, freq, 0.0
    xs = np.arange(w) * 1.0
    ys = np.arange(h) * 1.0
    for _ in range(octaves):
        out += amp * gen.noise2array(xs * f, ys * f)
        total += amp
        amp *= 0.5
        f *= 2.0
    return out / total


def label(tiles, mask):
    h, w = tiles.shape
    m = np.isin(tiles, list(mask))
    labels = -np.ones((h, w), dtype=np.int32)
    sizes = []
    cur = 0
    for y in range(h):
        for x in range(w):
            if not m[y, x] or labels[y, x] != -1:
                continue
            stack = [(x, y)]
            labels[y, x] = cur
            size = 0
            while stack:
                cx, cy = stack.pop()
                size += 1
                for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                    if 0 <= nx < w and 0 <= ny < h and m[ny, nx] and labels[ny, nx] == -1:
                        labels[ny, nx] = cur
                        stack.append((nx, ny))
            sizes.append(size)
            cur += 1
    return labels, sizes


def representatives(labels, sizes):
    reps = []
    for c in range(len(sizes)):
        ys, xs = np.nonzero(labels == c)
        cx, cy = xs.mean(), ys.mean()
        i = np.argmin((xs - cx) ** 2 + (ys - cy) ** 2)
        reps.append((int(xs[i]), int(ys[i])))
    return reps


def mst_edges(reps, rng):
    n = len(reps)
    if n < 2:
        return []
    in_tree = [False] * n
    dist = [1e20] * n
    parent = [-1] * n
    dist[0] = 0
    edges, existing = [], set()
    for _ in range(n):
        u = min((i for i in range(n) if not in_tree[i]), key=lambda i: dist[i])
        in_tree[u] = True
        if parent[u] >= 0:
            edges.append((parent[u], u))
            existing.add(frozenset((parent[u], u)))
        for v in range(n):
            if not in_tree[v]:
                d = np.hypot(reps[u][0] - reps[v][0], reps[u][1] - reps[v][1])
                if d < dist[v]:
                    dist[v], parent[v] = d, u
    for i in range(n):
        if rng.random() > 0.3:
            continue
        best_j, best_d = -1, 1e20
        for j in range(n):
            if j == i or frozenset((i, j)) in existing:
                continue
            d = np.hypot(reps[i][0] - reps[j][0], reps[i][1] - reps[j][1])
            if d < best_d:
                best_d, best_j = d, j
        if best_j >= 0 and best_d < 140:
            edges.append((i, best_j))
            existing.add(frozenset((i, best_j)))
    return edges


def astar(cost, solid, a, b):
    h, w = cost.shape
    openh = [(0, a)]
    g = {a: 0.0}
    came = {}
    while openh:
        _, cur = heapq.heappop(openh)
        if cur == b:
            path = [cur]
            while cur in came:
                cur = came[cur]
                path.append(cur)
            return path[::-1]
        cx, cy = cur
        for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
            if 0 <= nx < w and 0 <= ny < h and not solid[ny, nx]:
                ng = g[cur] + cost[ny, nx]
                if ng < g.get((nx, ny), 1e30):
                    g[(nx, ny)] = ng
                    came[(nx, ny)] = cur
                    heapq.heappush(openh, (ng + abs(nx - b[0]) + abs(ny - b[1]), (nx, ny)))
    return []


def generate(seed, w, h):
    rng = np.random.default_rng(seed)
    e = fbm(OpenSimplex(seed), w, h, 0.016, 5) * 0.5 + 0.5
    moist = fbm(OpenSimplex(seed + 7919), w, h, 0.02, 3)
    border = max(12.0, w * 0.06)
    yy, xx = np.mgrid[0:h, 0:w]
    d = np.minimum(np.minimum(xx, yy), np.minimum(w - 1 - xx, h - 1 - yy)).astype(float)
    t = np.clip(d / border, 0, 1)
    e = np.where(d < border, 1.5 + (e - 1.5) * (t * t * (3 - 2 * t)), e)
    interior = e[d >= border]
    q = lambda p: np.quantile(interior, p)
    deep_q, water_q, sand_q, hill_q, mount_q, snow_q = q(.19), q(.31), q(.36), q(.81), q(.89), q(.975)
    tiles = np.full((h, w), GRASS, dtype=np.int8)
    tiles[e >= sand_q] = GRASS
    tiles[(e >= sand_q) & (e < hill_q) & (moist > 0.05)] = FOREST
    tiles[e < sand_q] = SAND
    tiles[e < water_q] = SHALLOW
    tiles[e < deep_q] = DEEP
    tiles[(e >= hill_q) & (e < mount_q)] = HILL
    tiles[(e >= mount_q) & (e < snow_q)] = MOUNTAIN
    tiles[e >= snow_q] = SNOW

    labels, sizes = label(tiles, LAKE)
    for c, s in enumerate(sizes):
        if s < 30:
            tiles[labels == c] = SAND

    labels, sizes = label(tiles, LAND)
    lake_m = np.isin(tiles, list(LAKE))
    adj = np.zeros_like(lake_m)
    adj[1:, :] |= lake_m[:-1, :]
    adj[:-1, :] |= lake_m[1:, :]
    adj[:, 1:] |= lake_m[:, :-1]
    adj[:, :-1] |= lake_m[:, 1:]
    reps_land = representatives(labels, sizes)
    for c, s in enumerate(sizes):
        comp = labels == c
        if (adj & comp).any():
            continue
        if s < 160:
            tiles[comp] = MOUNTAIN
        else:
            rx, ry = reps_land[c]
            rad = int(np.clip(int(np.sqrt(s) * 0.18), 3, 7))
            for dy in range(-rad - 1, rad + 2):
                for dx in range(-rad - 1, rad + 2):
                    x, y = rx + dx, ry + dy
                    if 1 <= x < w - 1 and 1 <= y < h - 1:
                        dd = np.hypot(dx, dy)
                        if dd <= rad and labels[y, x] == c:
                            tiles[y, x] = DEEP if dd < rad - 1.5 else SHALLOW

    labels, sizes = label(tiles, LAKE)
    reps = representatives(labels, sizes)
    edges = mst_edges(reps, rng)
    flow = np.zeros((h, w, 2))
    jit = fbm(OpenSimplex(seed + 31337), w, h, 0.05, 2) * 0.5 + 0.5
    base = np.full((h, w), 3.0)
    base[np.isin(tiles, list(LAKE))] = 1.0
    base[tiles == FOREST] = 4.0
    base[tiles == HILL] = 8.0
    base[tiles == MOUNTAIN] = 30.0
    base[tiles == SNOW] = 45.0
    cost = base + jit * 14.0
    solid = d < int(border * 0.5)
    jobs = [(reps[a_i], reps[b_i], None) for a_i, b_i in edges]
    # Spur rivers: from random hills down to the nearest lake.
    hills = list(zip(*np.nonzero(tiles == HILL)))
    for _ in range(w // 32 if hills and reps else 0):
        hy, hx = hills[int(rng.integers(0, len(hills)))]
        near_rep = min(reps, key=lambda r: (r[0] - hx) ** 2 + (r[1] - hy) ** 2)
        if np.hypot(near_rep[0] - hx, near_rep[1] - hy) < 120:
            jobs.append(((int(hx), int(hy)), near_rep, False))
    for a, b, force_wide in jobs:
        path = astar(cost, solid, a, b)
        if len(path) < 2:
            continue
        if e[a[1], a[0]] < e[b[1], b[0]]:
            path.reverse()
        wide = (rng.random() < 0.5) if force_wide is None else force_wide
        n = len(path)
        for k, (px, py) in enumerate(path):
            ax, ay = path[max(0, k - 3)]
            bx, by = path[min(n - 1, k + 3)]
            dv = np.array([bx - ax, by - ay], dtype=float)
            if np.linalg.norm(dv) > 0:
                dv /= np.linalg.norm(dv)
            for dy in range(-1, (1 if wide else 0) + 1):
                for dx in range(-1, (1 if wide else 0) + 1):
                    x, y = px + dx, py + dy
                    if 1 <= x < w - 1 and 1 <= y < h - 1 and tiles[y, x] not in LAKE:
                        tiles[y, x] = RIVER
                        flow[y, x] = dv

    water = np.isin(tiles, list(WATER))
    lake = np.isin(tiles, list(LAKE))
    near = np.zeros_like(lake)
    for pass_i in range(2):
        src = ~water if pass_i == 0 else near
        nb = np.zeros_like(lake)
        nb[1:, :] |= src[:-1, :]
        nb[:-1, :] |= src[1:, :]
        nb[:, 1:] |= src[:, :-1]
        nb[:, :-1] |= src[:, 1:]
        near = near | (lake & nb)
    tiles[lake & near] = SHALLOW
    tiles[lake & ~near] = DEEP
    lake = np.isin(tiles, list(LAKE))
    nb = np.zeros_like(lake)
    nb[1:, :] |= lake[:-1, :]
    nb[:-1, :] |= lake[1:, :]
    nb[:, 1:] |= lake[:, :-1]
    nb[:, :-1] |= lake[:, 1:]
    tiles[np.isin(tiles, [GRASS, SAND]) & (moist > 0.35) & nb] = MARSH
    for fill in (SAND, GRASS):
        labels, sizes = label(tiles, KAYAK_OK)
        if sizes:
            main = int(np.argmax(sizes))
            stray = (labels >= 0) & (labels != main)
            tiles[stray & (tiles != MARSH)] = fill if fill == SAND else GRASS
            if fill == GRASS:
                tiles[stray] = GRASS
    return tiles, flow, len(jobs)


def place_pois(tiles, rng):
    h, w = tiles.shape
    shore, shore_water = [], []
    for y in range(2, h - 2):
        for x in range(2, w - 2):
            if tiles[y, x] not in (SAND, GRASS, FOREST):
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                if tiles[y + dy, x + dx] in LAKE:
                    shore.append((x, y))
                    shore_water.append((x + dx, y + dy))
                    break
    c = (w / 2, h / 2)
    si = min(range(len(shore)), key=lambda i: (shore[i][0] - c[0]) ** 2 + (shore[i][1] - c[1]) ** 2)
    start, start_water = shore[si], shore_water[si]
    stores, docks = [], []
    cands = [i for i in range(len(shore)) if np.hypot(shore[i][0] - start[0], shore[i][1] - start[1]) >= 4]
    fi = min(cands, key=lambda i: np.hypot(shore[i][0] - start[0], shore[i][1] - start[1]))
    stores.append(shore[fi])
    docks.append(shore_water[fi])
    for i in rng.permutation(len(shore)):
        if len(stores) >= 10:
            break
        p = shore[i]
        if all(np.hypot(p[0] - s[0], p[1] - s[1]) >= 55 for s in stores):
            stores.append(p)
            docks.append(shore_water[i])
    treasures = []
    tries = 0
    while len(treasures) < 45 and tries < 30000:
        tries += 1
        x, y = int(rng.integers(4, w - 4)), int(rng.integers(4, h - 4))
        if tiles[y, x] not in (GRASS, FOREST, SAND, HILL):
            continue
        if np.hypot(x - start[0], y - start[1]) < 12:
            continue
        if any(np.hypot(x - s[0], y - s[1]) < 8 for s in stores):
            continue
        if any(np.hypot(x - t[0], y - t[1]) < 12 for t in treasures):
            continue
        treasures.append((x, y))
    return start, start_water, stores, docks, treasures


def reachable(tiles, start):
    h, w = tiles.shape
    seen = np.zeros((h, w), bool)
    dq = deque([start])
    seen[start[1], start[0]] = True
    while dq:
        x, y = dq.popleft()
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < w and 0 <= ny < h and not seen[ny, nx] and tiles[ny, nx] in KAYAK_OK:
                seen[ny, nx] = True
                dq.append((nx, ny))
    return seen


def main():
    seed = int(sys.argv[1]) if len(sys.argv) > 1 else 42
    size = int(sys.argv[2]) if len(sys.argv) > 2 else 320
    out = sys.argv[3] if len(sys.argv) > 3 else f"world_{seed}.png"
    tiles, flow, n_edges = generate(seed, size, size)
    rng = np.random.default_rng(seed + 1)
    start, start_water, stores, docks, treasures = place_pois(tiles, rng)
    kayak = np.isin(tiles, list(KAYAK_OK))
    seen = reachable(tiles, start_water)
    connected = int(kayak.sum()) == int((seen & kayak).sum())
    docks_ok = all(seen[d[1], d[0]] for d in docks)
    print(f"seed {seed} size {size}: water {kayak.mean() * 100:.0f}%  rivers carved {n_edges}  "
          f"stores {len(stores)}  treasures {len(treasures)}  all-water-connected={connected}  docks-reachable={docks_ok}")
    img = np.zeros((size, size, 3), np.uint8)
    for t, col in COLORS.items():
        img[tiles == t] = col
    im = Image.fromarray(img).resize((size * 2, size * 2), Image.NEAREST)
    px = im.load()
    for (x, y) in treasures:
        for k in range(-2, 3):
            for (a, b) in ((x * 2 + k, y * 2 + k), (x * 2 + k, y * 2 - k)):
                if 0 <= a < size * 2 and 0 <= b < size * 2:
                    px[a, b] = (220, 30, 30)
    for (x, y) in stores:
        for a in range(x * 2 - 3, x * 2 + 4):
            for b in range(y * 2 - 3, y * 2 + 4):
                px[a, b] = (30, 90, 255)
    for a in range(start[0] * 2 - 3, start[0] * 2 + 4):
        for b in range(start[1] * 2 - 3, start[1] * 2 + 4):
            px[a, b] = (255, 255, 255)
    im.save(out)
    print("wrote", out)
    return 0 if (connected and docks_ok) else 1


if __name__ == "__main__":
    sys.exit(main())
