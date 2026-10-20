"""The Castle's weapons for the generated weapon kit (L3): a keep's armoury of steel, crests and gold.

Runs inside Blender (headless):

    blender -b -P tools/assets/weapon_kit_castle.py [-- --out <dir>] [--only Greataxe]

Writes `<Model>.glb` and `<Model>.frame.json` per weapon, and `palette-card.glb`, into
assets/kenney3d/weapon-kit/Models/GLB format/. The frame contract, the colour rule and the mesh
vocabulary are weapon_kit_mesh.py's; the colours are weapon_kit_palette.CASTLE, and ICE for the
Frost Hammer.

What makes these three one family, and the Castle's:
  * forged steel read through shape: every blade, face and plate has a pale bevel or edge band
    against the mid-steel flats, as the Forest's flint reads through its bevel line;
  * gold where the Forest has rope: gold collars bind both ends of every grip and every join,
    gold rivets hold every plate, gold caps the ends;
  * the grip is the Forest's spiral wrap in dyed cloth (crest red, or crest blue on the Frost
    Hammer), and the hanging charm becomes heraldry: a crest-blue ribbon, a tassel, a crest shield;
  * a step up from the Forest: symmetric, turned and faceted parts, crisp edges, no knapping.
The Splitbow is the level's relic and its most ornate piece: laminated steel-and-oak recurve limbs,
gold-capped steel tips, a crest on each side of the riser and a gold three-way arrow guide.
"""

from __future__ import annotations

import math
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from weapon_kit_mesh import Mesh, add, basis, cli, cross, mul, norm, sub  # noqa: E402
from weapon_kit_palette import CASTLE as C  # noqa: E402
from weapon_kit_palette import ICE  # noqa: E402

X = (1.0, 0.0, 0.0)
Y = (0.0, 1.0, 0.0)
Z = (0.0, 0.0, 1.0)


# --- shared Castle pieces -----------------------------------------------------------------------


def collar(m: Mesh, centre, axis, radius: float, width: float, *, ry: float | None = None, colour=C.GOLD,
           bevel=C.GOLD_DARK, segments: int = 12, rise: float = 0.016) -> None:
    """A metal band round a haft or grip (elliptical with `ry`): a flat crown between two bevels."""
    w = width / 2
    ry = radius if ry is None else ry
    prof = [(-w, radius, ry), (-w + 0.008, radius + rise, ry + rise), (w - 0.008, radius + rise, ry + rise),
            (w, radius, ry)]
    m.lathe(prof, colour, axis=axis, centre=centre, ref=X if abs(norm(axis)[0]) < 0.9 else Y, segments=segments,
            smooth=False, face_colour=lambda i, j: colour if i == 1 else bevel, cap_colour=bevel)


def castle_grip(m: Mesh, centre, axis, length: float, rx: float, ry: float, *, cloth=C.CREST_RED,
                groove=C.CLOTH, turns: float = 4.0) -> None:
    """The Forest's spiral grip in dyed cloth, bound at both ends with gold instead of rope."""
    ax = norm(axis)
    m.wrap(centre, ax, length, rx, ry, cloth, groove, turns=turns, ridge=0.14, ref=X, segments=10, per_turn=5)
    for end in (-1.0, 1.0):
        collar(m, add(centre, mul(ax, end * (length / 2 + 0.012))), ax, rx * 1.06, 0.05, ry=ry * 1.06)


def spike(m: Mesh, base, direction, length: float, radius: float, colour, *, segments: int = 8, edge=None) -> None:
    """A faceted steel point (a haft's top spike, a butt spike)."""
    m.lathe([(0.0, radius), (length * 0.3, radius * 0.82), (length, 0.0)], colour, axis=direction, centre=base,
            segments=segments, smooth=False, cap_colour=edge or colour,
            face_colour=lambda i, j: (edge or colour) if j % 2 else colour)


def crystal(m: Mesh, base, direction, length: float, radius: float, *, phase: float = 0.0) -> None:
    """A clear ice crystal: a hexagonal prism, a faceted point in frost, its root sunk into the surface."""
    d = norm(direction)
    u, v = basis(d)
    rings = []
    for along, k in ((-0.05 * length, 1.0), (0.42 * length, 1.06), (0.7 * length, 0.94)):
        c = add(base, mul(d, along))
        rings.append([add(c, add(mul(u, radius * k * math.cos(phase + math.pi * s / 3)),
                                 mul(v, radius * k * math.sin(phase + math.pi * s / 3)))) for s in range(6)])
    m.grid(rings, ICE.ICE, apex1=add(base, mul(d, length)), cap0_colour=ICE.ICE_DEEP, cap1_colour=ICE.FROST,
           face_colour=lambda i, j: ICE.ICE if (j + i) % 2 == 0 else ICE.ICE_MID)


def rime(m: Mesh, centre, axis, along0: float, along1: float, radius, *, segments: int = 8, phase: float = 0.0,
         jag: float = 0.08, seed: int = 1, ref=X) -> None:
    """Frost crusted over a round or faceted part from along0 to along1, its far edge torn into
    drips (the jagged edge is what says rime, not a painted band). `radius(along)` is the part's."""
    rng = random.Random(seed)
    u, v = basis(axis, ref)
    ax = norm(axis)
    teeth = [rng.uniform(0.15, 1.0) * jag * (1.0 if s % 2 else 0.45) for s in range(segments)]
    rings = []
    steps = 4
    for k in range(steps + 1):
        t = k / steps
        ring = []
        for s in range(segments):
            a = along0 + (along1 - along0) * t + (teeth[s] * t ** 3 if along1 > along0 else -teeth[s] * t ** 3)
            r = radius(a) + 0.014 + rng.uniform(0.0, 0.008)
            th = phase + 2 * math.pi * s / segments
            ring.append(add(add(centre, mul(ax, a)), add(mul(u, r * math.cos(th)), mul(v, r * math.sin(th)))))
        rings.append(ring)
    m.grid(rings, ICE.FROST, face_colour=lambda i, j: ICE.FROST if (i + j) % 3 else ICE.ICE)


def shield(m: Mesh, centre, normal, up, size: float) -> None:
    """A heraldic crest: a gold-rimmed heater shield, crest blue, a red chevron and a gold boss."""
    outline = [(-0.5, 0.48), (0.5, 0.48), (0.5, 0.05), (0.43, -0.2), (0.26, -0.4), (0.0, -0.52), (-0.26, -0.4),
               (-0.43, -0.2), (-0.5, 0.05)]
    n = norm(normal)
    v = norm(up)
    u = norm(cross(v, n))  # so that u x v = n: the prism extrudes outward

    def scaled(k):
        return [(x * size * k, y * size * k) for x, y in outline]

    m.prism(scaled(1.0), 0.0, 0.014, C.GOLD, origin=centre, u=u, v=v, side_colour=C.GOLD_DARK)
    m.prism(scaled(0.8), 0.0, 0.022, C.CREST_BLUE, origin=add(centre, mul(v, size * 0.02)), u=u, v=v,
            side_colour=C.CREST_BLUE)
    chevron = [(-0.36, -0.12), (0.0, 0.16), (0.36, -0.12), (0.36, -0.28), (0.0, 0.0), (-0.36, -0.28)]
    m.prism([(x * size, y * size) for x, y in chevron], 0.0, 0.028, C.CREST_RED, origin=centre, u=u, v=v)
    m.rivet(add(centre, add(mul(v, size * 0.26), mul(n, 0.022))), n, size * 0.09, size * 0.06, C.GOLD, segments=6)


# --- Greataxe -----------------------------------------------------------------------------------
# A crescent steel axe on an oak haft: the bit faces -Y (the frame's edge side), a short back spike
# at +Y, a steel spike on top, langets riveted in gold down the haft, a crest-blue ribbon tied under
# the head. 4.46 studs from the butt spike to the top spike.

AXE_HEAD_Z = -3.0  # the socket's centre on the haft line
# The bit in the YZ plane: the cutting edge is an arc (radius AXE_R, its lowest point AXE_EDGE_LOW),
# the back runs straight along the socket for +-AXE_NECK, then curves down to meet the edge in two
# horns at +-AXE_HORN_DZ. Measured across the blade, along Y, at every z.
AXE_R, AXE_EDGE_LOW, AXE_HORN_DEG = 0.85, -0.98, 70.0
AXE_BACK, AXE_NECK, AXE_BACK_POW = -0.12, 0.26, 0.6
AXE_T0, AXE_T_MIN, AXE_BEVEL = 0.057, 0.022, 0.1
AXE_CY = AXE_EDGE_LOW + AXE_R
AXE_HORN_DZ = AXE_R * math.sin(math.radians(AXE_HORN_DEG))


def axe_edge_y(dz: float) -> float:
    return AXE_CY - math.sqrt(max(0.0, AXE_R * AXE_R - dz * dz))


AXE_BACK_K = (AXE_BACK - axe_edge_y(AXE_HORN_DZ)) / (AXE_HORN_DZ - AXE_NECK) ** AXE_BACK_POW


def axe_back_y(dz: float) -> float:
    a = abs(dz)
    return AXE_BACK if a <= AXE_NECK else AXE_BACK - AXE_BACK_K * (a - AXE_NECK) ** AXE_BACK_POW


def axe_thick(dz: float) -> float:
    return AXE_T_MIN + (AXE_T0 - AXE_T_MIN) * math.sqrt(max(0.0, 1 - (dz / AXE_HORN_DZ) ** 2))


def crescent_bit(m: Mesh) -> None:
    """The bit: each section runs from the thick back (seated in the socket along the neck) to the
    cutting edge, with a light bevel band along the edge and mid-steel flats; the horns are points."""
    zh = AXE_HEAD_Z
    n = 22
    rings = []
    for k in range(n + 1):
        dz = AXE_HORN_DZ * 0.97 * (2 * k / n - 1)
        yb, ye, t = axe_back_y(dz), axe_edge_y(dz), axe_thick(dz)
        bev = ye + min(AXE_BEVEL, 0.55 * (yb - ye))
        z = zh + dz
        rings.append([(t, yb, z), (0.8 * t, bev, z), (0.0, ye, z), (-0.8 * t, bev, z), (-t, yb, z)])
    tip = axe_edge_y(AXE_HORN_DZ)

    def colour(i, j):
        return C.STEEL_LIGHT if j in (1, 2) else C.STEEL

    m.grid(rings, C.STEEL, apex0=(0.0, tip, zh - AXE_HORN_DZ), apex1=(0.0, tip, zh + AXE_HORN_DZ), face_colour=colour)


def ribbon_tail(m: Mesh, origin, length: float, drift: float, wave: float, phase: float, x: float) -> None:
    """A cloth tail hanging (-Y) from `origin`, waving along Z, cut in a swallowtail."""
    hw = 0.045
    steps = 8

    def centre(s):
        return drift * s / length + wave * math.sin(phase + 7.0 * s) * (s / length)

    left = [(length * k / steps, centre(length * k / steps) - hw) for k in range(steps + 1)]
    right = [(length * k / steps, centre(length * k / steps) + hw) for k in range(steps + 1)]
    notch = (length - 0.07, centre(length - 0.07))
    outline = left + [notch] + list(reversed(right))
    m.prism(outline, -0.006, 0.006, C.CREST_BLUE, origin=add(origin, (x, 0.0, 0.0)), u=(0.0, -1.0, 0.0), v=Z,
            side_colour=C.CREST_BLUE)


def greataxe() -> Mesh:
    m = Mesh("Greataxe")
    zh = AXE_HEAD_Z

    # The haft: oak, swelling a little toward the head.
    m.lathe([(0.44, 0.094), (0.0, 0.096), (-1.2, 0.1), (-2.2, 0.104), (zh + 0.3, 0.106), (zh - 0.32, 0.1)], C.OAK,
            axis=Z, ref=X, segments=10, smooth=True, cap_colour=C.OAK)
    castle_grip(m, (0.0, 0.0, 0.0), Z, 0.72, 0.1, 0.1)
    # The butt: a steel ferrule, a gold collar, a short spike.
    m.lathe([(0.0, 0.1), (0.02, 0.112), (0.1, 0.108), (0.12, 0.09)], C.STEEL, axis=Z, centre=(0.0, 0.0, 0.44),
            ref=X, segments=10, smooth=False, cap_colour=C.STEEL_LIGHT)
    collar(m, (0.0, 0.0, 0.43), Z, 0.1, 0.04)
    spike(m, (0.0, 0.0, 0.56), Z, 0.1, 0.07, C.STEEL, edge=C.STEEL_LIGHT)

    # The socket round the haft, gold at both ends, langets down the haft with gold rivets.
    m.lathe([(-0.3, 0.13), (-0.27, 0.15), (0.27, 0.15), (0.3, 0.13)], C.STEEL, axis=Z, centre=(0.0, 0.0, zh),
            ref=X, segments=8, smooth=False, face_colour=lambda i, j: C.STEEL if i == 1 else C.STEEL_LIGHT,
            cap_colour=C.STEEL_LIGHT)
    for end in (-0.31, 0.31):
        collar(m, (0.0, 0.0, zh + end), Z, 0.15, 0.05, segments=8)
    for ang in (0.0, math.pi / 2, math.pi, 1.5 * math.pi):
        c, s = math.cos(ang), math.sin(ang)
        out = (c, s, 0.0)
        side = (-s, c, 0.0)
        r = 0.098
        z0, z1 = zh + 0.33, zh + 0.98
        outline = [(-0.035, 0.0), (0.035, 0.0), (0.035, 0.55), (0.0, z1 - z0), (-0.035, 0.55)]
        m.prism(outline, 0.0, 0.016, C.STEEL, origin=(c * r, s * r, z0), u=side, v=Z, side_colour=C.STEEL_LIGHT)
        for z in (z0 + 0.14, z0 + 0.44):
            m.rivet((c * (r + 0.016), s * (r + 0.016), z), out, 0.02, 0.018, C.GOLD, segments=6)

    # The bit, riveted along its back with gold.
    crescent_bit(m)
    for dz in (-0.4, -0.2, 0.0, 0.2, 0.4):
        t = axe_thick(dz)
        for sx in (1.0, -1.0):
            m.rivet((sx * t, axe_back_y(dz) - 0.075, zh + dz), mul(X, sx), 0.026, 0.022, C.GOLD, segments=6)
    # The crest on both flats, laid on the flat's slope between the back and the bevel.
    yc = -0.48
    t = axe_thick(0.0)
    bev = axe_edge_y(0.0) + AXE_BEVEL
    x = t - 0.2 * t * (AXE_BACK - yc) / (AXE_BACK - bev) - 0.002
    for sx in (1.0, -1.0):
        shield(m, (sx * x, yc, zh), (sx, 0.0, 0.0), (0.0, 0.0, -1.0), 0.24)
    # The back: a short faceted spike in a gold collar.
    collar(m, (0.0, 0.15, zh), Y, 0.075, 0.045, segments=8)
    spike(m, (0.0, 0.12, zh), Y, 0.36, 0.07, C.STEEL, edge=C.STEEL_LIGHT)
    # The top: a gold knop and a steel spike.
    m.lathe([(0.0, 0.1), (0.04, 0.13), (0.1, 0.12), (0.13, 0.08)], C.GOLD, axis=(0.0, 0.0, -1.0),
            centre=(0.0, 0.0, zh - 0.33), ref=X, segments=8, smooth=False, cap_colour=C.GOLD_DARK,
            face_colour=lambda i, j: C.GOLD if j % 2 else C.GOLD_DARK)
    spike(m, (0.0, 0.0, zh - 0.45), (0.0, 0.0, -1.0), 0.32, 0.075, C.STEEL, edge=C.STEEL_LIGHT)

    # The ribbon: crest blue, knotted under the head, two tails hanging.
    zr = zh + 1.06
    m.binding((0.0, 0.0, zr), Z, 0.104, 0.104, 2, 0.022, (C.CREST_BLUE,), ref=X, segments=10)
    m.nodule((0.0, -0.13, zr), (0.05, 0.045, 0.05), C.CREST_BLUE, axis=Y, ref=X, segments=6, rings=4, jitter=0.1, seed=61)
    ribbon_tail(m, (0.0, -0.14, zr), 0.62, 0.16, 0.035, 0.4, 0.012)
    ribbon_tail(m, (0.0, -0.14, zr - 0.02), 0.48, -0.05, 0.03, 2.2, -0.012)

    lo, hi = m.bounds()
    m.frame = {
        "grip": (0.0, 0.0, 0.0),
        "tip": (0.0, 0.0, round(lo[2], 3)),  # the spike's point: the end of the swing
        "holster": (0.0, 0.0, round((lo[2] + hi[2]) / 2, 3)),
        "edge": (0.0, AXE_EDGE_LOW, zh),  # the middle of the cutting edge
    }
    m.notes = {"length": round(hi[2] - lo[2], 3), "bitReach": round(-lo[1], 3), "edge": "-Y; back spike +Y",
               "holster": "middle of the length"}
    return m


# --- Frost Hammer -------------------------------------------------------------------------------
# A steel war hammer the cold has taken: an octagonal head in gold bands, clear ice crystals grown
# out of its back and over its top, frost crusted on the head and dripping down the haft, a crest on
# each side of the socket, a crest-blue grip, a gold pommel with an ice point. The striking face is
# -Y; the crystals crowd the back (+Y). 4.37 studs from the pommel's ice point to the head.

FROST_HEAD_Z = -3.0
FROST_HEAD = [  # (along Y, radius of the octagon's corners)
    (-0.6, 0.0), (-0.6, 0.185), (-0.578, 0.225), (-0.49, 0.225), (-0.485, 0.248), (-0.425, 0.248), (-0.42, 0.212),
    (-0.27, 0.212), (-0.265, 0.26), (0.265, 0.26), (0.27, 0.212), (0.42, 0.212), (0.425, 0.248), (0.485, 0.248),
    (0.49, 0.225), (0.578, 0.225), (0.6, 0.185), (0.6, 0.0),
]
FROST_GOLD = (0.425, 0.485)  # |y| of the gold bands
FROST_SOCKET = 0.265
FROST_HAFT_R = 0.088


def frost_head_r(y: float) -> float:
    for (y0, r0), (y1, r1) in zip(FROST_HEAD, FROST_HEAD[1:]):
        if y0 <= y <= y1 and y1 > y0:
            return r0 + (r1 - r0) * (y - y0) / (y1 - y0)
    return 0.0


def frost_hammer() -> Mesh:
    m = Mesh("FrostHammer")
    zh = FROST_HEAD_Z
    hc = (0.0, 0.0, zh)

    # The haft: an octagonal steel bar, gold rings along it.
    prof = [(0.4, FROST_HAFT_R), (-0.4, FROST_HAFT_R), (-1.2, 0.09), (-2.0, 0.093), (zh + 0.1, 0.096)]
    # Darker facets than the head: the frost and the crystals need something to stand out from, and a
    # pale bar vanishes on the sky.
    m.lathe(prof, C.STEEL, axis=Z, ref=X, segments=8, phase=math.pi / 8, smooth=False,
            face_colour=lambda i, j: C.STEEL if j % 2 else C.STEEL_DARK, cap_colour=C.STEEL)
    for z in (-1.2, -2.0):
        collar(m, (0.0, 0.0, z), Z, 0.092, 0.05, segments=8)
    castle_grip(m, (0.0, 0.0, 0.0), Z, 0.72, 0.094, 0.094, cloth=C.CREST_BLUE, groove=C.STEEL_DARK)
    # The pommel: a faceted gold knop with an ice point growing out of it.
    m.lathe([(0.0, 0.08), (0.03, 0.12), (0.1, 0.13), (0.16, 0.1), (0.19, 0.05)], C.GOLD, axis=Z,
            centre=(0.0, 0.0, 0.41), ref=X, segments=8, phase=math.pi / 8, smooth=False, cap_colour=C.GOLD_DARK,
            face_colour=lambda i, j: C.GOLD if j % 2 == 0 else C.GOLD_DARK)
    crystal(m, (0.0, 0.0, 0.58), Z, 0.2, 0.045)

    # The head: an octagon along Y, gold bands, the striking face pale steel.
    def head_colour(i, j):
        y = (FROST_HEAD[i + 1][0] + FROST_HEAD[i + 2][0]) / 2 if i + 2 < len(FROST_HEAD) else 0.0
        if FROST_GOLD[0] <= abs(y) <= FROST_GOLD[1]:
            return C.GOLD
        if abs(y) > 0.575:
            return C.STEEL_LIGHT
        return C.STEEL_LIGHT if j % 2 else C.STEEL

    m.lathe(FROST_HEAD, C.STEEL, axis=Y, centre=hc, ref=X, segments=8, phase=math.pi / 8, smooth=False,
            face_colour=head_colour, cap_colour=C.STEEL_LIGHT)
    # The socket: a gold collar under the head, a crest on each side (its point toward the grip).
    collar(m, (0.0, 0.0, zh + 0.29), Z, 0.1, 0.07, segments=8)
    flat = FROST_SOCKET * math.cos(math.pi / 8)
    for c in (1.0, -1.0):
        shield(m, (c * (flat + 0.001), 0.0, zh), (c, 0.0, 0.0), (0.0, 0.0, -1.0), 0.19)

    # The cold: frost crusted over the back half of the head and dripping toward the face; frost
    # dripping down the haft from the socket; crystals grown out of the back, over the top and
    # through the frost.
    rime(m, hc, Y, 0.42, 0.29, frost_head_r, segments=8, phase=math.pi / 8, jag=0.15, seed=71)
    rime(m, (0.0, 0.0, 0.0), Z, zh + 0.35, zh + 0.97, lambda a: 0.096, segments=8, phase=math.pi / 8, jag=0.24,
         seed=72)
    cluster = [  # (base offset from the head centre, direction, length, radius)
        ((0.0, 0.56, 0.0), (0.0, 1.0, 0.0), 0.52, 0.075),
        ((0.08, 0.54, 0.06), (0.55, 1.0, 0.35), 0.36, 0.055),
        ((-0.08, 0.54, -0.05), (-0.6, 1.0, -0.3), 0.34, 0.055),
        ((0.02, 0.52, 0.11), (0.1, 0.8, 1.0), 0.3, 0.05),
        ((-0.03, 0.52, -0.12), (-0.1, 0.9, -1.0), 0.38, 0.055),
        ((0.1, 0.5, -0.1), (0.7, 0.7, -0.6), 0.26, 0.045),
        ((-0.1, 0.5, 0.1), (-0.7, 0.6, 0.6), 0.24, 0.04),
        ((0.0, 0.3, -0.2), (0.0, 0.45, -1.0), 0.36, 0.06),  # over the top
        ((0.08, 0.14, -0.2), (0.35, 0.2, -1.0), 0.24, 0.045),
        ((-0.07, 0.2, -0.2), (-0.4, 0.3, -1.0), 0.26, 0.045),
        ((0.16, 0.32, 0.12), (1.0, 0.3, 0.4), 0.2, 0.04),  # through the frost on the flanks
        ((-0.16, 0.36, 0.1), (-1.0, 0.4, 0.3), 0.22, 0.04),
        ((0.0, 0.3, 0.2), (0.0, 0.3, 1.0), 0.2, 0.04),
    ]
    for k, (off, d, length, r) in enumerate(cluster):
        crystal(m, add(hc, mul(off, 1.07)), d, length * 1.15, r * 1.1, phase=0.3 * k)
    for z, side in ((zh + 0.64, 1.0), (zh + 0.84, -1.0)):
        crystal(m, (side * 0.09, 0.03, z), (side * 1.0, 0.25, -0.3), 0.15, 0.03)

    lo, hi = m.bounds()
    m.frame = {
        "grip": (0.0, 0.0, 0.0),
        "tip": (0.0, 0.0, round(lo[2], 3)),  # the top of the head (its crystals): the end of the swing
        "holster": (0.0, 0.0, round((lo[2] + hi[2]) / 2, 3)),
        "head": hc,  # the head's centre: where a freeze patch or a hit flash belongs
    }
    m.notes = {"length": round(hi[2] - lo[2], 3), "headSpan": round(hi[1] - lo[1], 3),
               "striking face": "-Y; crystals +Y", "holster": "middle of the length"}
    return m


# --- Splitbow -----------------------------------------------------------------------------------
# The Castle's relic: a recurve of laminated limbs (steel back, oak belly), gold bands at the joins,
# steel recurve tips with gold caps, a crest-red grip in gold collars, a crest shield on each side
# of the upper riser, a gold three-way arrow guide in front of the arrow shelf, and a crest-blue
# tassel. 3.9 studs tall; the string lies along the recurves and leaves them for its straight run.

SB_TIP_Y = 1.86
SB_RISER = 0.45
SB_BACK, SB_RECURVE, SB_RECURVE_FROM = 0.62, 0.55, 0.62
SB_ARROW_Y = 0.3
SB_RISER_A, SB_RISER_B = 0.1, 0.125
SB_ROOT_A, SB_ROOT_B = 0.1, 0.072
SB_TIP_A, SB_TIP_B = 0.056, 0.036
SB_STEEL_TIP = 0.8  # u from which the limb is all steel
SB_STRING_R = 0.017


def sb_smooth(e0: float, e1: float, x: float) -> float:
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def sb_u(y: float) -> float:
    return max(0.0, (abs(y) - SB_RISER) / (SB_TIP_Y - SB_RISER))


def sb_stave(y: float):
    """The recurve's centreline point and half-sizes (a across X, b front to back) at height y: the
    limbs sweep back toward the string (+Z), then the last part curls forward again."""
    u = sb_u(y)
    r = max(0.0, (u - SB_RECURVE_FROM) / (1 - SB_RECURVE_FROM)) ** 2
    z = SB_BACK * u * u - SB_RECURVE * r
    riser = 1.0 - sb_smooth(SB_RISER - 0.1, SB_RISER + 0.1, abs(y))
    a = (SB_ROOT_A + (SB_TIP_A - SB_ROOT_A) * u) * (1 - riser) + SB_RISER_A * riser
    b = (SB_ROOT_B + (SB_TIP_B - SB_ROOT_B) * u) * (1 - riser) + SB_RISER_B * riser
    return (0.0, y, z), a, b


def sb_belly_normal(y: float):
    """The unit normal of the limb's string side (its belly, toward +Z) at height y, in the YZ plane."""
    p, _, _ = sb_stave(y)
    q, _, _ = sb_stave(y + 1e-3)
    return norm((0.0, -(q[2] - p[2]) / 1e-3, 1.0))


def sb_belly(y: float):
    """The point on the limb's string side (its belly) at height y, one string radius out."""
    p, _, b = sb_stave(y)
    return add(p, mul(sb_belly_normal(y), b + SB_STRING_R))


def splitbow() -> Mesh:
    m = Mesh("Splitbow")

    ys = [-SB_TIP_Y + (SB_TIP_Y - SB_RISER) * (k / 20) ** 1.1 for k in range(21)]
    ys += [-0.3, -0.15, 0.0, 0.15, 0.3]
    ys += [-v for v in reversed(ys[:21])]
    path, radii = [], []
    for y in ys:
        p, a, b = sb_stave(y)
        path.append(p)
        radii.append((a, b))

    def stave_colour(i, j):
        y = (ys[i] + ys[i + 1]) / 2
        u = sb_u(y)
        if 0.0 < u < 0.035 or 0.44 < u < 0.47 or SB_STEEL_TIP - 0.035 < u < SB_STEEL_TIP:
            return C.GOLD
        if u >= SB_STEEL_TIP:
            return C.STEEL_LIGHT if j < 4 else C.STEEL
        return C.STEEL if j < 4 else C.OAK  # the back (-Z) steel, the belly oak, through the riser too

    m.sweep(path, radii, C.OAK, segments=8, smooth=True, normal0=X, face_colour=stave_colour, cap_colour=C.STEEL)

    # The riser: the crest-red grip in gold, a gold arrow shelf, gold studs on the steel back.
    castle_grip(m, (0.0, 0.0, 0.0), Y, 0.44, SB_RISER_A + 0.004, SB_RISER_B + 0.004, turns=3.0)
    m.prism([(-0.07, 0.0), (0.05, 0.0), (0.035, 0.035), (-0.06, 0.035)], SB_RISER_A - 0.01, SB_RISER_A + 0.04,
            C.GOLD, origin=(0.0, SB_ARROW_Y - 0.02, 0.0), u=(0.0, 0.0, -1.0), v=Y, side_colour=C.GOLD_DARK)
    for y in (-0.33, 0.33):
        p, _, b = sb_stave(y)
        m.rivet((0.0, y, p[2] - b), (0.0, 0.0, -1.0), 0.026, 0.022, C.GOLD, segments=6)
    # Gold studs down each limb's steel back, between the gold bands: the relic's extra dress.
    for u in (0.2, 0.32, 0.6, 0.7):
        for sign in (-1.0, 1.0):
            y = sign * (SB_RISER + u * (SB_TIP_Y - SB_RISER))
            p, _, b = sb_stave(y)
            n = mul(sb_belly_normal(y), -1.0)
            m.rivet(add(p, mul(n, b - 0.004)), n, 0.024, 0.02, C.GOLD, segments=6)

    # The crests, one each side of the upper riser.
    for side in (-1.0, 1.0):
        p, a, _ = sb_stave(0.6)
        shield(m, (side * (a + 0.004), 0.6, p[2]), (side, 0.0, 0.0), Y, 0.25)

    # The three-way arrow guide: a gold block on the riser's front, three rods fanning forward, each
    # ending in a flat gold arrowhead (flat in YZ, so the fan reads from the side).
    front = -SB_RISER_B
    gb = (0.0, SB_ARROW_Y, front - 0.02)
    m.lathe([(0.0, 0.05), (0.03, 0.06), (0.08, 0.05), (0.1, 0.03)], C.GOLD, axis=(0.0, 0.0, -1.0), centre=gb, ref=X,
            segments=8, smooth=False, cap_colour=C.GOLD_DARK, face_colour=lambda i, j: C.GOLD if j % 2 else C.GOLD_DARK)
    tips = []
    head = [(0.11, 0.0), (0.0, 0.05), (0.02, 0.016), (-0.05, 0.016), (-0.05, -0.016), (0.02, -0.016), (0.0, -0.05)]
    for ang in (0.42, 0.0, -0.42):
        d = (0.0, math.sin(ang), -math.cos(ang))
        start = add(gb, mul(d, 0.07))
        end = add(gb, mul(d, 0.27))
        m.sweep([start, end], 0.016, C.GOLD, segments=6, smooth=True, cap_colour=C.GOLD_DARK)
        perp = norm(cross(X, d))
        m.prism(head, -0.012, 0.012, C.GOLD, origin=end, u=d, v=perp, side_colour=C.GOLD_DARK)
        tips.append(add(end, mul(d, 0.11)))

    # The recurve tips: gold caps with grooves for the string loop.
    for sign in (-1.0, 1.0):
        y = sign * SB_TIP_Y
        p, a, b = sb_stave(y)
        q, _, _ = sb_stave(y - sign * 0.01)
        out = norm(sub(p, q))
        prof = [(-0.12, 0.06), (-0.08, 0.068), (-0.06, 0.05), (-0.045, 0.05), (-0.03, 0.064), (0.04, 0.056),
                (0.1, 0.035), (0.14, 0.0)]
        m.lathe(prof, C.GOLD, axis=out, centre=p, ref=X, segments=8, smooth=False,
                face_colour=lambda i, j: C.GOLD_DARK if i in (1, 2) else (C.GOLD if j % 2 else C.GOLD_DARK))

    # The string: from each nock along its recurve's belly to where it leaves the limb, then straight.
    belly = {}
    for sign in (-1.0, 1.0):
        samples = [sign * (SB_TIP_Y - 0.06 - (SB_TIP_Y - SB_RISER) * 0.42 * k / 14) for k in range(15)]
        pts = [sb_belly(y) for y in samples]
        top = max(range(len(pts)), key=lambda k: pts[k][2])
        belly[sign] = pts[: top + 1]
    string_z = max(belly[-1][-1][2], belly[1][-1][2])
    lower = belly[-1]
    upper = list(reversed(belly[1]))
    lower[-1] = (0.0, lower[-1][1], string_z)
    upper[0] = (0.0, upper[0][1], string_z)
    m.sweep(lower + upper, SB_STRING_R, C.STEEL_LIGHT, segments=6, smooth=True)
    # The serving where the arrow is nocked, with gold nock locators.
    m.sweep([(0.0, SB_ARROW_Y - 0.34, string_z), (0.0, SB_ARROW_Y + 0.2, string_z)], 0.024, C.STEEL, segments=6,
            smooth=True)
    for dy in (-0.035, 0.035):
        m.loop((0.0, SB_ARROW_Y + dy, string_z), Y, 0.026, 0.026, 0.011, C.GOLD, ref=X, segments=8, tube_segments=4)

    # The tassel off the lower grip collar: a gold cap and a crest-blue skirt.
    tx = SB_RISER_A + 0.03
    m.sweep([(tx - 0.03, -0.25, -0.02), (tx, -0.36, -0.05), (tx, -0.43, -0.06)], 0.012, C.GOLD_DARK, segments=5,
            smooth=True)
    m.lathe([(0.0, 0.0), (0.02, 0.03), (0.06, 0.04), (0.07, 0.03)], C.GOLD, axis=(0.0, -1.0, 0.0),
            centre=(tx, -0.43, -0.06), ref=X, segments=8, smooth=True)
    m.lathe([(0.0, 0.03), (0.08, 0.042), (0.2, 0.06), (0.24, 0.05), (0.245, 0.0)], C.CREST_BLUE,
            axis=(0.0, -1.0, 0.0), centre=(tx, -0.5, -0.06), ref=X, segments=10, smooth=False,
            face_colour=lambda i, j: C.GOLD if i == 0 else C.CREST_BLUE)

    lo_b, hi_b = m.bounds()
    m.frame = {
        "grip": (0.0, 0.0, 0.0),
        "tip": tuple(round(c, 3) for c in tips[1]),  # the muzzle: the middle arrowhead of the guide
        "nock": (0.0, SB_ARROW_Y, round(string_z, 3)),
        "holster": (0.0, 0.0, round((lo_b[2] + hi_b[2]) / 2, 3)),
        "splitUp": tuple(round(c, 3) for c in tips[0]),  # the fan's outer arrowheads, should the split
        "splitDown": tuple(round(c, 3) for c in tips[2]),  # effect want to start from the guide
    }
    m.notes = {"height": round(hi_b[1] - lo_b[1], 3), "braceHeight": round(string_z, 3), "holster": "bbox centre"}
    return m


PIECES = {
    "Greataxe": greataxe,
    "FrostHammer": frost_hammer,
    "Splitbow": splitbow,
}


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    sys.exit(cli("castle", PIECES, argv))
