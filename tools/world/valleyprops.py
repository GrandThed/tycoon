"""The Valley's props, all generated geometry (no kit GLB is baked in): trees, boulders, groves,
flowers, the hub's kerb, stepping stones, bridges, the water sheet, the waterfall, clouds, and the
plot-frame aprons and entrance fences. See valleyland.py for the frame and the ground.

Everything is single-sided and wound counter-clockwise from outside (the game culls back faces),
so a cone has a bottom wherever a camera could look up into it.
"""

from __future__ import annotations

import math
import random

import wgeom as G
from wgeom import mix, polar, smoothstep
from valleyland import CROWN, MESH_AIM

TAU = math.tau


# ---------------------------------------------------------------- single props


def pine(b, x, y, z, height, radius, rot, leaf, leaf2, trunk):
    """A two-tier low-poly pine: 28 triangles."""
    b.frustum((x, y), radius * 0.2, radius * 0.16, z, z + height * 0.3, trunk, sides=4, rot=rot, top=False)
    b.frustum((x, y), radius, 0.0, z + height * 0.16, z + height * 0.66, leaf, sides=6, rot=rot, bottom=True)
    b.frustum((x, y), radius * 0.72, 0.0, z + height * 0.46, z + height, leaf2, sides=6, rot=rot + 0.5, bottom=True)


def round_tree(b, x, y, z, height, radius, rot, leaf, leaf2, trunk):
    """A round-crowned tree for the groves: trunk and two stacked blobs, 48 triangles."""
    b.frustum((x, y), radius * 0.22, radius * 0.16, z, z + height * 0.45, trunk, sides=4, rot=rot, top=False)
    b.blob((x, y, z + height * 0.55), (radius, radius * 0.94, height * 0.27), leaf, rot)
    b.blob((x + radius * 0.12, y - radius * 0.1, z + height * 0.8), (radius * 0.66, radius * 0.7, height * 0.2), leaf2, rot + 0.9)


def boulder(b, x, y, z, size, rot, colour, colour2):
    seed = x * 0.37 + y * 0.91

    def jitter(k):
        return 0.78 + 0.44 * G.hash01(seed, k)

    tone = mix(colour, colour2, G.hash01(seed, 99.0))
    b.blob((x, y, z + size * 0.28), (size, size * 0.82, size * 0.62), tone, rot, jitter)


def tuft(b, x, y, z, height, colour, turn):
    """Three blades, each a thin closed spike so it shows from every side: 9 triangles."""
    for k in range(3):
        a = turn + k * 2.1
        cx, cy = x + 0.32 * math.cos(a), y + 0.32 * math.sin(a)
        b.frustum((cx, cy), 0.2, 0.0, z, z + height * (0.75 + 0.12 * k), colour, sides=3, rot=a)


def flowers(b, x, y, z, count, colours, leaf, seed):
    """A clump: a low leafy cushion with a few flat blossoms sitting on it."""
    b.frustum((x, y), 1.25, 0.55, z, z + 0.34, leaf, sides=6, rot=seed, top=True)
    for k in range(count):
        a = seed * 3.1 + k * TAU / count
        rr = 0.62 if k else 0.0
        px, py = x + rr * math.cos(a), y + rr * math.sin(a)
        colour = colours[int(G.hash01(seed, k) * len(colours)) % len(colours)]
        b.frustum((px, py), 0.4, 0.0, z + 0.3 - 0.1 * rr, z + 0.56 - 0.1 * rr, colour, sides=6, rot=a)


# ---------------------------------------------------------------- trees and rocks


def split_by_angle(items, name, limit=MESH_AIM):
    """items: (map angle key, triangles to add as a callable taking a Builder, triangle count).
    Four Roblox quadrants, each cut again if it is too heavy. Returns {name_<k>: Builder}."""
    quadrants = [[] for _ in range(4)]
    for x, y, draw, tris in items:
        quadrants[(0 if x >= 0 else 1) + (0 if -y >= 0 else 2)].append((math.atan2(-y, x), x, y, draw, tris))
    out = {}
    number = 0
    for group in quadrants:
        if not group:
            continue
        group.sort(key=lambda item: (item[0], item[1], item[2]))
        total = sum(item[4] for item in group)
        parts = max(1, math.ceil(total / limit))
        per = total / parts
        chunks, run, weight = [], [], 0
        for item in group:
            run.append(item)
            weight += item[4]
            if weight >= per and len(chunks) < parts - 1:
                chunks.append(run)
                run, weight = [], 0
        if run:
            chunks.append(run)
        for chunk in chunks:
            number += 1
            builder = G.Builder()
            for _, _, _, draw, _ in chunk:
                draw(builder)
            out[f"{name}_{number}"] = builder
    return out


def build_trees(land):
    """The far forest and the kit-style trees of the band past the plots' skirts, with boulders.
    Returns (items outside the wall for the Forest meshes, a Builder for those inside it)."""
    P, plan, noise = land.P, land.plan, land.noise
    inside = G.Builder()
    outside = []
    stats = {"pines": 0, "nearTrees": 0, "boulders": 0}

    def place(x, y, draw, tris):
        if math.hypot(x, y) < land.r0 - 1.0:
            draw(inside)
        else:
            outside.append((x, y, draw, tris))

    # the far forest
    cfg = plan["forest"]
    rng = random.Random(99)
    s = cfg["spacing"]
    r_hi = land.r0 + cfg["reach"]
    n = int(r_hi / (s * 0.866)) + 1
    for j in range(-n, n + 1):
        for i in range(-n, n + 1):
            x = (i + 0.5 * (j & 1)) * s + rng.uniform(-0.42, 0.42) * s
            y = j * s * 0.866 + rng.uniform(-0.42, 0.42) * s
            roll, size, turn, tone = rng.random(), rng.random(), rng.random(), rng.random()
            r = math.hypot(x, y)
            if r > r_hi or r < land.inner:
                continue
            if roll > land.forest_density(x, y, r):
                continue
            if r < land.corner + 75 and land.plot_distance(x, y) < 62:
                continue  # the near trees' band
            if land.wet(x, y, 5.0 + land.bank_out):
                continue
            z, nz = land.ground_at(x, y)
            rel = z - land.lift
            if nz < 0.8 or rel > land.treeline + 14 * (tone - 0.5) or rel < -0.2:
                continue
            height = (cfg["height"][0] + (cfg["height"][1] - cfg["height"][0]) * size) * (1 - 0.3 * smoothstep(35, land.treeline, rel))
            leaf = mix(P["pine"], P["pine2"], tone)
            leaf2 = mix(leaf, P["pine2"], 0.5)
            place(x, y, lambda b, a=(x, y, z - 0.4, height, height * 0.3, turn * TAU, leaf, leaf2, P["trunk"]): pine(b, *a), 28)
            stats["pines"] += 1

    # the band 27-64 studs past the plots, and the wedges between them
    cfg = plan["nearTrees"]
    rng = random.Random(41)
    s = cfg["spacing"]
    r_hi = land.corner + cfg["reach"]
    n = int(r_hi / (s * 0.866)) + 1
    for j in range(-n, n + 1):
        for i in range(-n, n + 1):
            x = (i + 0.5 * (j & 1)) * s + rng.uniform(-0.4, 0.4) * s
            y = j * s * 0.866 + rng.uniform(-0.4, 0.4) * s
            roll, pick, turn, size = rng.random(), rng.random(), rng.random(), rng.random()
            r = math.hypot(x, y)
            if r > r_hi or r < land.inner + 30:
                continue
            d = land.plot_distance(x, y)
            if d < cfg["band"][0] or d > cfg["band"][1]:
                continue
            clump = 0.5 + 0.5 * noise.fbm(x / 42, y / 42, 61.0)
            if roll > smoothstep(0.38, 0.7, clump) * 0.85:
                continue
            if land.wet(x, y, 6.0 + land.bank_out) or abs(r - land.r0) < 2.5:
                continue
            z, nz = land.ground_at(x, y)
            if nz < 0.85 or z < land.lift - 0.2:
                continue
            if pick < cfg["rockShare"]:
                place(x, y, lambda b, a=(x, y, z - 0.25, 1.6 + 1.7 * size, turn * TAU, P["kitrock"], P["kitrock2"]): boulder(b, *a), 20)
                stats["boulders"] += 1
            else:
                height = 7.4 + 3.6 * size
                leaf = mix(P["kitleaf"], P["kitleaf2"], G.hash01(x, y))
                leaf2 = mix(leaf, P["kitleaf2"], 0.6)
                if int(pick * 977) % 7 == 3:
                    place(x, y, lambda b, a=(x, y, z - 0.2, height * 0.9, height * 0.3, turn * TAU, leaf, leaf2, P["kittrunk"]): round_tree(b, *a), 48)
                else:
                    place(x, y, lambda b, a=(x, y, z - 0.2, height, height * 0.27, turn * TAU, leaf, leaf2, P["kittrunk"]): pine(b, *a), 28)
                stats["nearTrees"] += 1
    return outside, inside, stats


def build_groves(land, b):
    """The stands of trees between the roads, boulders at their edges and by the pond."""
    P = land.P
    rng = random.Random(505)
    trees = rocks = 0
    z = land.lift
    for gx, gy, radius, count in land.groves:
        placed, tries = [], 0
        while len(placed) < count and tries < 80:
            tries += 1
            a, rr = rng.uniform(0, TAU), radius * math.sqrt(rng.random())
            scale, kind, turn = rng.random(), rng.random(), rng.uniform(0, TAU)
            x, y = gx + rr * math.cos(a), gy + rr * math.sin(a)
            if any(math.dist((x, y), p) < 4.2 for p in placed):
                continue
            if land.in_channel(x, y, land.bank_out + 4.0) or land.strip_blocked(x, y, 4.5):
                continue
            placed.append((x, y))
            height = (7.6 + 4.6 * scale) * (1.15 if rr < radius * 0.45 else 1.0)
            leaf = mix(P["kitleaf"], P["kitleaf2"], G.hash01(x, y))
            leaf2 = mix(leaf, P["kitleaf2"], 0.6)
            if kind < 0.3:
                round_tree(b, x, y, z - 0.1, height * 0.9, height * 0.3, turn, leaf, leaf2, P["kittrunk"])
            else:
                pine(b, x, y, z - 0.1, height, height * 0.27, turn, leaf, leaf2, P["kittrunk"])
            trees += 1
        for _ in range(rng.randint(1, 2)):
            a, size, turn = rng.uniform(0, TAU), rng.random(), rng.uniform(0, 6)
            x, y = gx + (radius + 2.5) * math.cos(a), gy + (radius + 2.5) * math.sin(a)
            if land.in_channel(x, y, land.bank_out + 2.0) or land.strip_blocked(x, y, 3.5):
                continue
            boulder(b, x, y, z - 0.2, 1.3 + 1.4 * size, turn, P["kitrock"], P["kitrock2"])
            rocks += 1
    ux, uy = math.cos(land.a_mid), math.sin(land.a_mid)
    half = land.pond_width / 2
    for off, side in ((-half - 5.5, 6.5), (half + 5.0, -7.0), (-half - 4.5, -9.0)):
        x, y = ux * (land.pass_r + off) - uy * side, uy * (land.pass_r + off) + ux * side
        boulder(b, x, y, z - 0.2, 1.5 + 0.8 * rng.random(), rng.uniform(0, 6), P["kitrock"], P["kitrock2"])
        rocks += 1
    # a few boulders standing in the river
    rng = random.Random(3)
    for k in range(10):
        s, ox, oy, turn, size = rng.uniform(0.3, 0.7), rng.uniform(-3, 3), rng.uniform(-3, 3), rng.uniform(0, 6), rng.uniform(1.0, 1.6)
        (x, y), _ = land.river.at(s * land.river.length)
        x, y = x + ox, y + oy
        if math.hypot(x, y) > land.r0 - 4 or any(math.dist((x, y), stone) < 7 for stone in land.stones):
            continue
        if any(math.dist((x, y), br["centre"]) < br["length"] / 2 + 6 for br in land.bridges):
            continue
        boulder(b, x, y, z - 0.25, size, turn, P["kitrock"], P["kitrock2"])
        rocks += 1
    return {"groveTrees": trees, "groveBoulders": rocks}


# ---------------------------------------------------------------- the centre's details


def build_details(land, b):
    P, plan = land.P, land.plan
    stats = {}
    lift = land.lift
    # stepping stones: an octagonal prism round the collision cylinder Valley.json describes
    pond = plan["pond"]
    visual = (pond["stoneRadius"] + 0.03) / math.cos(math.pi / 8)
    for k, (x, y) in enumerate(land.stones):
        b.frustum((x, y), visual, visual, lift - 0.04, pond["stoneTop"], P["stepstone"], sides=8, rot=k * 0.9, top=True, top_colour=mix(P["stepstone"], P["kerb2"], 0.5))
    stats["steppingStones"] = len(land.stones)
    # the hub: kerb blocks proud of its top and lapping over its edge, a darker paving ring, bollards
    hub, top = land.hub_radius, land.plot_y
    cfg = plan["hub"]
    segments = cfg["kerbSegments"]
    width = cfg["kerbWidth"]
    for k in range(segments):
        a = (k + 0.5) / segments * TAU
        centre_r = hub + 0.15 - width / 2 - 0.05
        cx, cy = polar(centre_r, a)
        length = TAU * hub / segments * 0.985
        colour = P["kerb"] if k % 2 else P["kerb2"]
        b.box((cx, cy, (0.3 + top + 0.04) / 2), (width + 0.3, length, top + 0.04 - 0.3), colour, rot=a, bottom=True)
    for k in range(24):
        a = (k + 0.5) / 24 * TAU
        cx, cy = polar(13.0, a)
        b.box((cx, cy, top - 0.02), (2.0, TAU * 13.0 / 24 * 0.97, 0.1), P["kerb"], rot=a, bottom=False)
    size = cfg["bollard"]
    for road in land.roads:
        x, y = road["pts"][0]
        length = math.hypot(x, y)
        ux, uy = x / length, y / length
        angle = math.atan2(uy, ux)
        for side in (-1, 1):
            off = land.road_width / 2 + 1.1
            px = ux * (hub + 2.2) - uy * side * off
            py = uy * (hub + 2.2) + ux * side * off
            b.box((px, py, lift + size[2] / 2 - 0.05), (size[0], size[1], size[2]), P["kerb"], rot=angle, top=P["kerb2"], bottom=False)
    stats["bollards"] = 2 * len(land.roads)
    # wildflower clumps and tufts in the meadow's flower patches
    cfg = plan["flowers"]
    rng = random.Random(2024)
    s = cfg["spacing"]
    lo, hi = land.earth_radius + 6, land.inner - 6
    n = int(hi / (s * 0.866)) + 1
    clumps = tufts = 0
    for j in range(-n, n + 1):
        for i in range(-n, n + 1):
            x = (i + 0.5 * (j & 1)) * s + rng.uniform(-0.45, 0.45) * s
            y = j * s * 0.866 + rng.uniform(-0.45, 0.45) * s
            roll, pick, size_ = rng.random(), rng.random(), rng.random()
            r = math.hypot(x, y)
            if r < lo or r > hi or roll > cfg["share"] * land.flower_patch(x, y):
                continue
            if land.in_channel(x, y, land.bank_out + 1.5) or land.strip_blocked(x, y, 1.6):
                continue
            if pick < 0.22:
                tuft(b, x, y, lift, 0.8 + 0.5 * size_, P["tuft"], pick * 40)
                tufts += 1
            else:
                count = cfg["apiece"][0] + int(size_ * (cfg["apiece"][1] - cfg["apiece"][0] + 0.999))
                flowers(b, x, y, lift, count, P["flowers"], mix(P["tuft"], P["darkgrass"], 0.4), pick * 17.0 + size_)
                clumps += 1
    stats["flowerClumps"], stats["tufts"] = clumps, tufts
    return stats


# ---------------------------------------------------------------- bridges


def build_bridge(land, bridge, b):
    """Planks from bank to bank, a solid plank ramp at each end, rails, and piles in the water.

    The deck's top face is exactly the collision deck's (Valley.json), and each ramp's top is the
    collision wedge's slope: deckTop at the deck's end down to the ground top rampLength away."""
    P, cfg = land.P, land.plan["bridge"]
    top, thick, ramp = cfg["deckTop"], cfg["deckThickness"], cfg["rampLength"]
    width, length = bridge["width"], bridge["length"]
    ux, uy = bridge["dir"]
    nx, ny = -uy, ux
    ax, ay = bridge["p0"]
    angle = math.atan2(uy, ux)
    planks = max(2, int(length / 1.7))
    step = length / planks
    for k in range(planks):
        t = (k + 0.5) * step
        colour = P["wood"] if k % 2 else P["wood2"]
        b.box((ax + ux * t, ay + uy * t, top - thick / 2), (step - 0.1, width, thick), colour, rot=angle)
    half = width / 2
    for (ex, ey), sign in ((bridge["p0"], -1.0), (bridge["p1"], 1.0)):
        ox, oy = ex + ux * sign * ramp, ey + uy * sign * ramp
        mid = ((ex + ox) / 2, (ey + oy) / 2, top / 3)
        a = (ex + nx * half, ey + ny * half, top)
        c = (ex - nx * half, ey - ny * half, top)
        d = (ox - nx * half, oy - ny * half, 0.0)
        e = (ox + nx * half, oy + ny * half, 0.0)
        a0, c0 = (a[0], a[1], 0.0), (c[0], c[1], 0.0)
        b.quad_out(a, c, d, e, P["wood"], mid)  # the slope
        b.out(a, e, a0, P["wooddark"], mid)
        b.out(c, c0, d, P["wooddark"], mid)
        b.quad_out(a, a0, c0, c, P["wooddark"], mid)  # the face under the deck's end
    rail = cfg["railHeight"]
    for side in (-1, 1):
        ox, oy = nx * side * (half - 0.3), ny * side * (half - 0.3)
        b.box((ax + ux * length / 2 + ox, ay + uy * length / 2 + oy, top + rail), (length, 0.3, 0.3), P["wooddark"], rot=angle)
        posts = max(2, int(length / 5.0) + 1)
        for k in range(posts):
            t = k / (posts - 1) * length
            b.box((ax + ux * t + ox, ay + uy * t + oy, top + rail / 2), (0.45, 0.45, rail + 0.3), P["wooddark"], rot=angle, bottom=False)
        piles = max(2, int(length / 9.0) + 1)
        for k in range(piles):
            t = (k + 0.5) / piles * length
            b.box((ax + ux * t + ox, ay + uy * t + oy, (top - thick + 0.02) / 2), (0.7, 0.7, top - thick - 0.02), P["wooddark"], rot=angle, top=None, bottom=False)


# ---------------------------------------------------------------- water


def build_riverbed(land, b):
    """The river's bed and banks again, a step above the aprons, where the river runs between two
    plots: both neighbours' aprons reach the bisector there, which is the river's own centreline,
    and would otherwise lie over the bed the basin paints."""
    P, plan = land.P, land.plan
    river = land.river_near
    z = plan["river"]["bedLift"]
    lo = land.inner - plan["apron"]["max"] - 6.0
    meadow = mix(P["grass"], P["grass2"], 0.5)
    soft = mix(P["bank"], meadow, 0.55)
    rows = []
    for i, (x, y) in enumerate(river.pts):
        r = math.hypot(x, y)
        if r < lo or r > land.r0 - 0.5:
            rows.append(None)
            continue
        tx, ty = river.tangent(i)
        nx, ny = -ty, tx
        hw = river.w[i] / 2
        offsets = (-(hw + land.soft_out), -(hw + land.bank_out), -(hw + land.water_out), -(hw - land.core_in), hw - land.core_in, hw + land.water_out, hw + land.bank_out, hw + land.soft_out)
        hair = CROWN if i % 2 else 0.0
        rows.append([(x + nx * off, y + ny * off, z - hair) for off in offsets])
    colours = (soft, P["bank"], P["bededge"], P["bedcore"], P["bededge"], P["bank"], soft)
    for row0, row1 in zip(rows, rows[1:]):
        if row0 is None or row1 is None:
            continue
        for k, colour in enumerate(colours):
            a, c, d, e = row0[k], row0[k + 1], row1[k + 1], row1[k]
            mx, my = (a[0] + c[0] + d[0] + e[0]) / 4, (a[1] + c[1] + d[1] + e[1]) / 4
            if land.plot_distance(mx, my) < -0.5:
                continue  # under a plot's slab
            b.up(a, c, d, colour)
            b.up(a, d, e, colour)


def build_water(land, b):
    """One translucent sheet `water.lift` above the ground: the river and pond as a ribbon with a
    skirt down to the overlay inside the wall, and the lake as a disc."""
    level = land.water_lift
    river = land.river_near
    n = len(river.pts)
    left, right, mids, inside = [], [], [], []
    for i, (x, y) in enumerate(river.pts):
        tx, ty = river.tangent(i)
        nx, ny = -ty, tx
        r = math.hypot(x, y)
        reach = river.w[i] / 2 + land.water_out + (1.2 if r > land.r0 + 20 else 0.0)
        hair = CROWN if i % 2 else 0.0
        left.append((x + nx * reach, y + ny * reach, level - hair))
        right.append((x - nx * reach, y - ny * reach, level - hair))
        mids.append((x, y, level))
        inside.append(r < land.r0 + 22)
    last = n - 1
    lake_reach = land.lake_r + 20
    while last > 0 and math.dist(river.pts[last - 1], land.lake) < lake_reach:
        last -= 1
    for i in range(last):
        b.up(right[i], right[i + 1], left[i + 1], None)
        b.up(right[i], left[i + 1], left[i], None)
        if inside[i] or inside[i + 1]:
            for edge in (left, right):
                a, c = edge[i], edge[i + 1]
                a0, c0 = (a[0], a[1], land.lift - 0.04), (c[0], c[1], land.lift - 0.04)
                b.quad_out(a, c, c0, a0, None, mids[i])
    cx, cy = land.lake
    rim = []
    for k in range(40):
        a = k / 40 * TAU
        rim.append((cx + (land.lake_r + 22) * math.cos(a), cy + (land.lake_r + 22) * math.sin(a), level - 0.012))
    for k in range(40):
        b.up((cx, cy, level - 0.012), rim[k], rim[(k + 1) % 40], None)


def build_waterfall(land, b):
    """The two-tier fall: a strip draped down the cliff behind the river's source, white where it
    drops and water-coloured where it runs flat, with foam where it lands."""
    P = land.P
    sx, sy = land.source
    ax, ay = land.axis
    nx, ny = -ay, ax
    rows = []
    for k in range(36):
        t = k * 1.6 - 2.0
        w = (9.5 - 1.5 * smoothstep(20, 55, t)) / 2
        x, y = sx + ax * t, sy + ay * t
        left = (x + nx * w, y + ny * w)
        right = (x - nx * w, y - ny * w)
        rows.append(
            (
                (left[0], left[1], land.ground_at(*left)[0] + 0.7),
                (right[0], right[1], land.ground_at(*right)[0] + 0.7),
                land.ground_at(x, y)[0],
            )
        )
    face = (-ax * 0.6, -ay * 0.6, 0.8)
    for k in range(len(rows) - 1):
        (l0, r0_, h0), (l1, r1, h1) = rows[k], rows[k + 1]
        white = mix(P["foam"], P["shallow"], 0.3 * (k % 2))
        colour = mix(P["water2"], white, smoothstep(0.25, 1.2, abs(h1 - h0)))
        b.toward(r0_, r1, l1, colour, face)
        b.toward(r0_, l1, l0, colour, face)
    for k in range(9):
        a = k / 9 * TAU
        b.blob((sx + 7 * math.cos(a), sy + 7 * math.sin(a), land.water_lift + 0.1), (4.2, 4.2, 1.1), P["foam"], a)


# ---------------------------------------------------------------- clouds


def build_clouds(land):
    """Flat low-poly clusters beyond the mountains, one mesh per Roblox quadrant."""
    cfg = land.plan["clouds"]
    rng = random.Random(cfg["seed"])
    builders = {}
    for _ in range(cfg["count"]):
        a = rng.uniform(0, TAU)
        r = land.r0 + rng.uniform(*cfg["radius"])
        z = rng.uniform(*cfg["height"]) + (r - land.r0) * 0.03
        cx, cy = polar(r, a)
        scale = rng.uniform(0.8, 1.6) * (1 + (r - land.r0) / 2600.0)
        rot = rng.uniform(0, TAU)
        quadrant = (0 if cx >= 0 else 1) + (0 if -cy >= 0 else 2)
        b = builders.setdefault(quadrant, G.Builder())
        for k in range(rng.randint(3, 5)):
            ox = (k - 1.5) * 44 * scale * math.cos(rot) + rng.uniform(-14, 14)
            oy = (k - 1.5) * 44 * scale * math.sin(rot) + rng.uniform(-14, 14)
            rad = rng.uniform(38, 62) * scale * (1.0 if 0 < k < 3 else 0.72)
            lift, turn = rng.uniform(-4, 6), rng.uniform(0, 3)
            b.blob((cx + ox, cy + oy, z + lift), (rad * 1.25, rad, rad * 0.36), None, turn)
    return {f"Clouds_{q + 1}": builders[q] for q in sorted(builders)}


# ---------------------------------------------------------------- plot-frame meshes


def build_aprons(land):
    """Two flat bands round a plot, in the plot's own frame (lx across, ly toward the hub): the
    same template serves every plot. A ray leaves the plot's edge every few studs; the outer edge is
    where it runs out of its irregular 16-40 stud reach, or 0.3 studs short of the sector's
    bisector, or short of the wall line, whichever comes first. The front is cut open for the road."""
    cfg = land.plan["apron"]
    noise = land.noise
    hx, hy = land.plot_x / 2, land.plot_z / 2
    half = land.ring_data["halfSector"]
    hub_ly = land.radius  # the map centre in plot-local coordinates is (0, +radius)
    corridor = land.road_width / 2 + land.plan["roads"]["rim"] + cfg["corridorMargin"]
    limit_r = land.r0 - cfg["wallGap"]

    def allowed(lx, ly):
        dx, dy = lx, ly - hub_ly  # from the map centre
        r = math.hypot(dx, dy)
        if r > limit_r or r < land.earth_radius + 6.0:
            return False
        # angle off the plot's radial (which points along -ly from the centre)
        off = abs(math.atan2(dx, -dy))
        if off >= half:
            return False
        if r * math.sin(half - off) < cfg["bisectorGap"]:
            return False
        if ly > hy and abs(lx) < corridor:
            return False
        return True

    # rays: along each side, and fanned round each corner
    rays = []
    step = cfg["step"]
    sides = (
        ((-hx, hy), (hx, hy), (0.0, 1.0)),  # front (toward the hub)
        ((hx, hy), (hx, -hy), (1.0, 0.0)),
        ((hx, -hy), (-hx, -hy), (0.0, -1.0)),
        ((-hx, -hy), (-hx, hy), (-1.0, 0.0)),
    )
    for index, (p0, p1, normal) in enumerate(sides):
        count = max(2, int(round(math.dist(p0, p1) / step)))
        for i in range(count + 1):
            t = i / count
            rays.append(((p0[0] + (p1[0] - p0[0]) * t, p0[1] + (p1[1] - p0[1]) * t), normal))
        nxt = sides[(index + 1) % 4][2]
        for i in range(1, 6):
            a = i / 6 * math.pi / 2
            # turning from this side's normal to the next side's
            rays.append((p1, (normal[0] * math.cos(a) + nxt[0] * math.sin(a), normal[1] * math.cos(a) + nxt[1] * math.sin(a))))
    reach_min, reach_max = cfg["min"], cfg["max"]
    rows = []
    for k, ((px, py), (nx, ny)) in enumerate(rays):
        qx, qy = px + nx * 9.0, py + ny * 9.0
        lobes = noise.fbm(qx / 52, qy / 52, 300.0)
        want = reach_min + (reach_max - reach_min) * smoothstep(-0.45, 0.55, lobes) + 2.5 * noise.fbm(qx / 9, qy / 9, 77.0)
        t = 0.0
        while t + 0.25 <= want and allowed(px + nx * (t + 0.25), py + ny * (t + 0.25)):
            t += 0.25
        share = cfg["innerShare"] + 0.12 * noise.fbm(qx / 17, qy / 17, 91.0)
        rows.append(((px, py), (nx, ny), t, t * share))
    # a ray that could not even start (the road corridor, or past the bisector) leaves a gap
    inner, outer = G.Builder(), G.Builder()
    lift = cfg["lift"]
    count = len(rows)
    for k in range(count):
        (p0, n0, t0, m0), (p1, n1, t1, m1) = rows[k], rows[(k + 1) % count]
        if t0 < 0.5 and t1 < 0.5:
            continue
        a0 = (p0[0], p0[1], lift)
        a1 = (p1[0], p1[1], lift)
        b0 = (p0[0] + n0[0] * m0, p0[1] + n0[1] * m0, lift - CROWN)
        b1 = (p1[0] + n1[0] * m1, p1[1] + n1[1] * m1, lift - CROWN)
        c0 = (p0[0] + n0[0] * t0, p0[1] + n0[1] * t0, lift)
        c1 = (p1[0] + n1[0] * t1, p1[1] + n1[1] * t1, lift)
        for builder, quad in ((inner, (a0, a1, b1, b0)), (outer, (b0, b1, c1, c0))):
            q0, q1, q2, q3 = quad
            if math.dist(q0[:2], q1[:2]) > 1e-6 or math.dist(q2[:2], q3[:2]) > 1e-6:
                if _area(q0, q1, q2) > 1e-6:
                    builder.up(q0, q1, q2, None)
                if _area(q0, q2, q3) > 1e-6:
                    builder.up(q0, q2, q3, None)
    return inner, outer, rows


def _area(a, b, c):
    return abs((b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])) / 2


def build_entrance(land):
    """Two short fence runs flanking the road, just outside the plot's front edge (plot frame)."""
    P, cfg = land.P, land.plan["entrance"]
    b = G.Builder()
    hy = land.plot_z / 2
    lift = land.lift
    for side in (-1, 1):
        start = side * (land.road_width / 2 + cfg["gap"])
        xs = [start + side * k * cfg["spacing"] for k in range(cfg["posts"])]
        ly = hy + cfg["outside"]
        for x in xs:
            b.box((x, ly, lift + 1.1 - 0.05), (0.42, 0.42, 2.2), P["wooddark"], bottom=False)
        mid = (xs[0] + xs[-1]) / 2
        for rail in (0.9, 1.7):
            b.box((mid, ly, lift + rail), (abs(xs[-1] - xs[0]), 0.22, 0.28), P["wood2"])
    return b
