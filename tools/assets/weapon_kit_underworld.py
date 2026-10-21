"""The Underworld's weapons for the generated weapon kit (L3): a forge below the world.

Runs inside Blender (headless):

    blender -b -P tools/assets/weapon_kit_underworld.py [-- --out <dir>] [--only Spear]

Writes `<Model>.glb` and `<Model>.frame.json` per weapon, and `palette-card.glb`, into
assets/kenney3d/weapon-kit/Models/GLB format/. The frame contract, the colour rule and the mesh
vocabulary are weapon_kit_mesh.py's; the colours are weapon_kit_palette.UNDERWORLD.

What makes these three one family, and the Underworld's:
  * forged black iron everywhere, always chamfered: dark flats with light IRON_EDGE arrises, so a
    dark mass never meets the Armory panel (30, 41, 70) without a light edge (black iron is an
    "inner" colour, README colour rules);
  * embers as geometry: glowing cracks, vents and mouths built as raised veins in EMBER and
    EMBER_HOT, the only saturated colour on the level (a ViewportFrame draws no lights);
  * ash-white bone for the parts a hand, a cheek or a shoulder touches (the spear's vertebra grip,
    the blunderbuss stock, the rifle's grip, cheek rest and crescent butt), cracked by the same
    embers, never black iron there;
  * a hanging charm like every family's (the Forest's are feathers): chain, an ember bead, a fang;
  * against the Forest and the Castle they read as a later level: forged, riveted and glowing,
    where the Forest is lashed and the Castle polished.
"""

from __future__ import annotations

import math
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from weapon_kit_mesh import Mesh, add, basis, cli, cross, mul, norm, sub  # noqa: E402
from weapon_kit_palette import UNDERWORLD as U  # noqa: E402

# --- shared Underworld shapes (local to this level; the mesh module is frozen) -------------------

GUN_BORE_Y = 0.17  # the bore's height above the hand
STOCK_ROUND = 2.7  # the stock section's superellipse power: round enough to read as bone, not a plank


def inset_outline(points, d: float):
    """The outline moved inward by d (mitred, the mitre capped at 2.5 d), either winding."""
    n = len(points)
    area = sum(points[i][0] * points[(i + 1) % n][1] - points[(i + 1) % n][0] * points[i][1] for i in range(n))
    sign = 1.0 if area > 0 else -1.0
    out = []
    for i in range(n):
        p0, p1, p2 = points[i - 1], points[i], points[(i + 1) % n]
        e0 = (p1[0] - p0[0], p1[1] - p0[1])
        e1 = (p2[0] - p1[0], p2[1] - p1[1])
        l0 = math.hypot(*e0) or 1e-9
        l1 = math.hypot(*e1) or 1e-9
        n0 = (-e0[1] / l0 * sign, e0[0] / l0 * sign)  # the inward normal of each edge
        n1 = (-e1[1] / l1 * sign, e1[0] / l1 * sign)
        bx, by = n0[0] + n1[0], n0[1] + n1[1]
        bl = math.hypot(bx, by)
        if bl < 1e-6:
            bx, by, bl = n0[0], n0[1], 1.0
        bx, by = bx / bl, by / bl
        cos_half = max(0.4, bx * n0[0] + by * n0[1])
        k = d / cos_half
        out.append((p1[0] + bx * k, p1[1] + by * k))
    return out


def plate(m: Mesh, outline, face_depth: float, edge_depth: float, face, edge, *, origin=(0.0, 0.0, 0.0),
          u=(0.0, 0.0, -1.0), v=(0.0, 1.0, 0.0), inset: float = 0.03, side=None) -> None:
    """A forged plate: a flat outline whose two faces (in `face`) stand proud of a bevel band (in
    `edge`) that runs right round its rim. A black-iron barb, lock plate or guard keeps its light
    edge in every view, which a plain prism with dark faces would not."""
    w = norm(cross(u, v))
    inner = inset_outline(outline, inset)

    def at(p, dd):
        return add(origin, add(add(mul(u, p[0]), mul(v, p[1])), mul(w, dd)))

    rings = [[at(p, -face_depth) for p in inner], [at(p, -edge_depth) for p in outline],
             [at(p, edge_depth) for p in outline], [at(p, face_depth) for p in inner]]

    def colour(i, j):
        return (side or edge) if i == 1 else edge

    m.grid(rings, edge, cap0_colour=face, cap1_colour=face, face_colour=colour)


def chamfered(c, u, v, hx: float, hy: float, k: float, rot: float):
    """A rectangle of half-sizes hx, hy with corners cut by k, turned by rot, round centre c:
    eight points; segment j runs from point j to j + 1, the odd segments are the chamfers."""
    pts = [(hx, -hy + k), (hx, hy - k), (hx - k, hy), (-hx + k, hy), (-hx, hy - k), (-hx, -hy + k), (-hx + k, -hy),
           (hx - k, -hy)]
    cr, sr = math.cos(rot), math.sin(rot)
    return [add(c, add(mul(u, x * cr - y * sr), mul(v, x * sr + y * cr))) for x, y in pts]


def forged(m: Mesh, profile, flat, edge, *, axis=(0.0, 0.0, -1.0), centre=(0.0, 0.0, 0.0), ref=None,
           chamfer: float = 0.38, twist: float = 0.0, flat2=None, bands=(), rot: float = 0.0,
           cap_colour=None) -> None:
    """Forged bar stock: a chamfered square (or oblong) section swept along `axis`.

    `profile` is (along, half) or (along, hx, hy); a half of 0 at an end closes it to a point. The
    flats are `flat` (and `flat2` on the two flats across, so a `twist` in radians per stud reads as
    a twisted bar), every chamfer is `edge`. `bands` are (along0, along1, colour) collars that
    colour the whole ring."""
    u, v = basis(axis, ref)
    ax = norm(axis)
    rings, apex0, apex1, along = [], None, None, []
    for k, entry in enumerate(profile):
        a = entry[0]
        hx = entry[1]
        hy = entry[2] if len(entry) > 2 else hx
        c = add(centre, mul(ax, a))
        if hx <= 1e-9:
            if k == 0:
                apex0 = c
            else:
                apex1 = c
            continue
        rings.append(chamfered(c, u, v, hx, hy, chamfer * min(hx, hy), rot + twist * a))
        along.append(a)

    def colour(i, j):
        if i >= len(along) - 1:
            return edge  # an apex fan
        mid = (along[i] + along[i + 1]) / 2
        for a0, a1, col in bands:
            if a0 - 1e-6 <= mid <= a1 + 1e-6:
                return col
        if j % 2:
            return edge
        return flat2 if (flat2 and j in (2, 6)) else flat

    m.grid(rings, flat, apex0=apex0, apex1=apex1, cap_colour=cap_colour or edge, face_colour=colour)


def vein(m: Mesh, pts, out, width: float, height: float, *, taper=None, halo: float = 1.9, hot=U.EMBER_HOT,
         glow=U.EMBER, deep=U.EMBER_DEEP) -> None:
    """A glowing crack laid on a surface whose outward normal is `out`: a low hexagonal ridge with
    its crown in `hot` and its flanks in `glow`, on a wider, flatter halo in `deep` (0 for none).
    `taper` scales the width point by point. Geometry, because a ViewportFrame draws no light."""
    scale = taper or [1.0] * len(pts)

    def colour(i, j):
        return hot if j in (0, 5) else glow

    m.sweep(pts, [(height, width * k) for k in scale], glow, segments=6, smooth=False, normal0=out,
            face_colour=colour, cap_colour=glow)
    if halo:
        low = [sub(p, mul(norm(out), height * 0.45)) for p in pts]
        m.sweep(low, [(height * 0.7, width * halo * k) for k in scale], deep, segments=4, smooth=False, normal0=out)


def link(m: Mesh, centre, along, normal, length: float, width: float, wire: float, colour) -> None:
    """One chain link: an oval ring lying in the plane of `along` and cross(normal, along)."""
    m.loop(centre, normal, length / 2, width / 2, wire, colour, segments=6, tube_segments=3, ref=along)


def chain(m: Mesh, path, pitch: float, length: float, width: float, wire: float, colours, *,
          up=(0.0, 1.0, 0.0)) -> None:
    """Links along a polyline, `pitch` apart, each turned a quarter from the last."""
    seglens = [math.dist(path[i], path[i + 1]) for i in range(len(path) - 1)]
    total = sum(seglens)
    count = max(1, int(total / pitch))
    for k in range(count + 1):
        s = k * total / count
        i = 0
        while i < len(seglens) - 1 and s > seglens[i]:
            s -= seglens[i]
            i += 1
        t = min(1.0, s / seglens[i]) if seglens[i] > 0 else 0.0
        p = add(path[i], mul(sub(path[i + 1], path[i]), t))
        d = norm(sub(path[i + 1], path[i]))
        side = norm(cross(d, up))
        if math.sqrt(sum(c * c for c in side)) < 0.5:
            side = norm(cross(d, (1.0, 0.0, 0.0)))
        flat = cross(side, d)
        link(m, p, d, side if k % 2 else flat, length, width, wire, colours[k % len(colours)])


def fang(m: Mesh, base, direction, length: float, radius: float, colour=U.ASH_BONE) -> None:
    """A tooth or a bone spur: a straight cone, slightly swollen above its root."""
    m.lathe([(0.0, radius * 0.9), (length * 0.18, radius), (length * 0.6, radius * 0.55), (length, 0.0)], colour,
            axis=norm(direction), centre=base, segments=6, smooth=True)


def charm(m: Mesh, top, *, drop: float = 0.22, scale: float = 1.0) -> None:
    """The Underworld's hanging charm (every family hangs one; the Forest's are feathers): a short
    chain from `top`, an ember bead and an ash-bone fang under it."""
    s = scale
    end = add(top, (0.0, -drop, 0.03 * s))
    chain(m, [top, end], 0.11 * s, 0.15 * s, 0.092 * s, 0.017 * s, (U.IRON, U.IRON_EDGE), up=(0.0, 0.0, 1.0))
    bead = add(end, (0.0, -0.06 * s, 0.0))
    m.nodule(bead, (0.04 * s, 0.04 * s, 0.04 * s), U.EMBER_HOT, axis=(0.0, 1.0, 0.0), segments=6, rings=4, jitter=0.1,
             seed=3)
    fang(m, add(bead, (0.0, -0.03 * s, 0.0)), (0.06, -1.0, -0.2), 0.22 * s, 0.034 * s)


def superellipse(c, hx: float, hy: float, n: float = 3.4, segments: int = 12, phase: float = 0.0):
    """A rounded-rectangle ring in the XY plane round c: a stock's or a grip's section."""
    pts = []
    for s in range(segments):
        t = phase + 2 * math.pi * s / segments
        co, si = math.cos(t), math.sin(t)
        x = hx * math.copysign(abs(co) ** (2 / n), co)
        y = hy * math.copysign(abs(si) ** (2 / n), si)
        pts.append((c[0] + x, c[1] + y, c[2]))
    return pts


def loft(m: Mesh, stations, colour, *, bands=(), segments: int = 12, n: float = 3.4, cap_colour=None,
         smooth: bool = True) -> None:
    """A stock or a grip lofted through (z, y_low, y_high, half_x) stations along Z; `bands` are
    (z0, z1, colour) straps."""
    rings = [superellipse((0.0, (lo + hi) / 2, z), hx, (hi - lo) / 2, n, segments) for z, lo, hi, hx in stations]
    zs = [st[0] for st in stations]

    def face(i, j):
        mid = (zs[i] + zs[i + 1]) / 2
        for z0, z1, col in bands:
            if z0 - 1e-6 <= mid <= z1 + 1e-6:
                return col
        return colour

    m.grid(rings, colour, smooth=smooth, face_colour=face, cap_colour=cap_colour or colour)


# --- Spear --------------------------------------------------------------------------------------
# A forge-warden's spear: a barbed leaf blade of black iron split by glowing ember cracks, on a
# twisted iron haft with a vertebra grip of ash-bone, a chain wound below the socket and a collar
# of bone fangs. 6.6 studs from the butt spike to the point; held a third of the way up.

SPEAR_TIP = -4.50
SPEAR_BLADE_BASE = -2.95
SPEAR_SOCKET = (-2.40, -3.03)  # rear and front of the iron socket
SPEAR_BUTT = 2.10
SPEAR_HAFT = 0.08  # half-size of the twisted bar
SPEAR_BEVEL = 0.6  # m.blade's default: the bevel line at 60 percent of the half width
SPEAR_TOTAL = SPEAR_BLADE_BASE - SPEAR_TIP
SPEAR_TIP_LEN = 0.5
SPEAR_PEAK = 0.33  # where the leaf is widest, as a fraction of the blade


def spear_hw(t: float) -> float:
    """The leaf's half width, t = 0 at the base to 1 at the point: widest a third of the way up."""
    if t <= SPEAR_PEAK:
        return 0.075 + 0.215 * math.sin(math.pi / 2 * t / SPEAR_PEAK)
    return 0.29 - 0.14 * ((t - SPEAR_PEAK) / (1 - SPEAR_TIP_LEN / SPEAR_TOTAL - SPEAR_PEAK)) ** 1.1


def spear_ht(t: float) -> float:
    return 0.06 - 0.022 * t


def spear_face_x(y: float, z: float) -> float:
    """Where the blade's +X flat is at (y, z), on its straight run: m.blade's cross-section."""
    t = (SPEAR_BLADE_BASE - z) / SPEAR_TOTAL
    hw, ht = spear_hw(t), spear_ht(t)
    return ht * (1.0 - 0.5 * min(1.0, abs(y) / (SPEAR_BEVEL * hw)))


def spear() -> Mesh:
    m = Mesh("Spear")

    # The blade: a black leaf with light bevelled edges and a lit upper ridge.
    m.blade(SPEAR_BLADE_BASE, SPEAR_TIP, spear_hw, spear_ht, U.IRON_EDGE, U.IRON_BLACK, bevel=SPEAR_BEVEL,
            tip_length=SPEAR_TIP_LEN, rings_per_unit=9.0, ridge=U.IRON)

    # Ember cracks on both flats: a wide fissure up the middle, branches running out toward the
    # edges, each glowing hot at its crown over a deep-red halo.
    rng = random.Random(31)
    z_end = SPEAR_TIP + SPEAR_TIP_LEN + 0.02

    def crack(side: float, path_yz, width, height, taper):
        pts = [(side * (spear_face_x(y, z) + height * 0.3), y, z) for y, z in path_yz]
        vein(m, pts, (side, 0.0, 0.0), width, height, taper=taper)

    for side in (1.0, -1.0):
        main, z = [], SPEAR_BLADE_BASE - 0.1
        while z > z_end:
            t = (SPEAR_BLADE_BASE - z) / SPEAR_TOTAL
            main.append((rng.uniform(-0.3, 0.3) * spear_hw(t) * 0.45, z))
            z -= rng.uniform(0.12, 0.16)
        n = len(main)
        crack(side, main, 0.026, 0.013, [1.0 - 0.6 * (k / (n - 1)) ** 1.3 for k in range(n)])
        for start, dy, lean in ((1, 1.0, -0.05), (2, -1.0, -0.1), (4, 1.0, -0.08), (5, -1.0, -0.06)):
            if start >= n - 1:
                continue
            y0, z0 = main[start]
            t = (SPEAR_BLADE_BASE - z0) / SPEAR_TOTAL
            reach = spear_hw(t) * SPEAR_BEVEL * 0.9 - abs(y0) * 0.5
            branch = [(y0, z0), (y0 + dy * reach * 0.55, z0 + lean * 0.45 + rng.uniform(-0.02, 0.02)),
                      (y0 + dy * reach, z0 + lean)]
            crack(side, branch, 0.019, 0.01, [1.0, 0.75, 0.4])

    # Two hooked barbs at the blade's root, sweeping back: black faces, light bevelled rims.
    b0 = SPEAR_BLADE_BASE
    barb = [(b0 - 0.27, 0.2), (b0 - 0.17, 0.3), (b0 - 0.01, 0.41), (b0 + 0.22, 0.5), (b0 + 0.12, 0.41),
            (b0 + 0.05, 0.31), (b0 + 0.01, 0.19), (b0, 0.07)]
    for sy in (1.0, -1.0):
        pts = [(z, sy * y) for z, y in barb]
        plate(m, pts, 0.038, 0.012, U.IRON_BLACK, U.IRON_EDGE, u=(0.0, 0.0, 1.0), v=(0.0, 1.0, 0.0), inset=0.026)
        # an ember seam down each barb, the blade's cracks running out into it
        seam = [(sy * 0.14, b0 - 0.17), (sy * 0.25, b0 - 0.07), (sy * 0.35, b0 + 0.06)]
        for sx in (1.0, -1.0):
            vein(m, [(sx * 0.04, y, z) for y, z in seam], (sx, 0.0, 0.0), 0.016, 0.009, taper=[1.0, 0.8, 0.45])

    # The socket: forged octagonal, collared at both ends, a glowing seam between.
    s0, s1 = SPEAR_SOCKET
    sl = s0 - s1
    forged(m, [(0.0, 0.104), (0.012, 0.126), (0.07, 0.126), (0.082, 0.11), (0.24, 0.1), (0.255, 0.108),
               (0.335, 0.108), (0.35, 0.096), (sl - 0.11, 0.084), (sl - 0.09, 0.104), (sl - 0.03, 0.104), (sl, 0.064)],
           U.IRON_BLACK, U.IRON_EDGE, axis=(0.0, 0.0, -1.0), centre=(0.0, 0.0, s0), ref=(1.0, 0.0, 0.0),
           rot=math.pi / 8, flat2=U.IRON,
           bands=[(0.0, 0.082, U.IRON_EDGE), (0.24, 0.255, U.EMBER), (0.255, 0.335, U.EMBER_HOT),
                  (0.335, 0.35, U.EMBER), (sl - 0.11, sl, U.IRON_EDGE)])

    # A collar of ash-bone fangs at the socket's rear, pointing back down the haft.
    for k in range(6):
        a = math.pi / 6 + k * math.pi / 3
        r = (math.cos(a), math.sin(a), 0.0)
        fang(m, (r[0] * 0.105, r[1] * 0.105, s0 + 0.02), (r[0] * 0.45, r[1] * 0.45, 1.0), 0.27, 0.036)

    # The haft: twisted black-iron bar, front and rear of the grip.
    twist = (math.pi / 2) / 0.42
    nf = 21
    front = [(s0 - 0.02 + i * (-0.48 - s0 + 0.02) / (nf - 1), SPEAR_HAFT) for i in range(nf)]
    forged(m, front, U.IRON_BLACK, U.IRON_EDGE, axis=(0.0, 0.0, 1.0), ref=(1.0, 0.0, 0.0), twist=twist, flat2=U.IRON)
    nr = 15
    rear = [(0.48 + i * (1.88 - 0.48) / (nr - 1), SPEAR_HAFT) for i in range(nr)]
    forged(m, rear, U.IRON_BLACK, U.IRON_EDGE, axis=(0.0, 0.0, 1.0), ref=(1.0, 0.0, 0.0), twist=twist, flat2=U.IRON)

    # The grip: four ash-bone vertebrae, iron showing between them, an iron collar at each end.
    vert = [(0.0, 0.094), (0.02, 0.12), (0.045, 0.11), (0.155, 0.11), (0.18, 0.12), (0.2, 0.094)]
    prof = []
    for k in range(4):
        prof += [(-0.43 + k * 0.22 + a, r) for a, r in vert]

    def grip_colour(i, j):
        return U.IRON if prof[i][1] < 0.1 and prof[i + 1][1] < 0.1 else U.ASH_BONE

    m.lathe(prof, U.ASH_BONE, axis=(0.0, 0.0, 1.0), centre=(0.0, 0.0, 0.0), segments=8, smooth=True,
            face_colour=grip_colour, cap_colour=U.IRON)
    for zc in (-0.47, 0.47):
        forged(m, [(-0.03, 0.106), (0.03, 0.106)], U.IRON_EDGE, U.IRON_EDGE, axis=(0.0, 0.0, 1.0),
               centre=(0.0, 0.0, zc), ref=(1.0, 0.0, 0.0), rot=math.pi / 8)

    # The butt: a forged collar with an ember groove, then a four-sided spike.
    bl = SPEAR_BUTT - 1.86
    forged(m, [(0.0, 0.102), (0.04, 0.112), (0.06, 0.096), (0.08, 0.096), (0.095, 0.112), (0.115, 0.096), (bl, 0.0)],
           U.IRON_BLACK, U.IRON_EDGE, axis=(0.0, 0.0, 1.0), centre=(0.0, 0.0, 1.86), ref=(1.0, 0.0, 0.0),
           flat2=U.IRON, bands=[(0.0, 0.04, U.IRON_EDGE), (0.06, 0.08, U.EMBER_HOT), (0.095, 0.115, U.IRON_EDGE)])

    # A chain wound twice round the haft below the socket, the charm hanging from its first turn.
    helix, turns, z0, z1, rad = [], 2.0, -1.5, -2.1, 0.128
    steps = 32
    for i in range(steps + 1):
        f = i / steps
        a = -math.pi / 2 + 2 * math.pi * turns * f
        helix.append((rad * math.cos(a), rad * math.sin(a), z0 + (z1 - z0) * f))
    chain(m, helix, 0.125, 0.155, 0.095, 0.018, (U.IRON_EDGE, U.IRON), up=(0.0, 0.0, 1.0))
    charm(m, (0.0, -0.14, z0 + 0.02))

    m.frame = {
        "grip": (0.0, 0.0, 0.0),
        "tip": (0.0, 0.0, SPEAR_TIP),
        "holster": (0.0, 0.0, round((SPEAR_TIP + SPEAR_BUTT) / 2, 3)),
        "bladeBase": (0.0, 0.0, SPEAR_SOCKET[1]),  # a thrust trail's inner end: where the iron leaf leaves the socket
    }
    m.notes = {"length": f"butt z +{SPEAR_BUTT} to point z {SPEAR_TIP}", "holster": "middle of the length",
               "held": "a third of the way up from the butt"}
    return m


# --- Shotgun ------------------------------------------------------------------------------------
# A forge blunderbuss: an octagonal black-iron barrel flaring into a bell that glows like a furnace
# mouth, an ember lock whose cock holds a live coal, on a full stock of ash-bone ending in a bone's
# two knuckles. Held by the stock's wrist; 3.1 studs from the knuckles to the bell's lip.

SHOTGUN_BREECH = -0.28
SHOTGUN_BELL = -1.60  # where the barrel starts to flare

def shotgun() -> Mesh:
    m = Mesh("Shotgun")
    by = GUN_BORE_Y

    # The stock: ash-bone from the lock to the butt, the wrist where the hand goes narrowed and
    # dropping, an iron strap round the butt. Forward of the lock the gun is all iron.
    stock = [
        (-0.5, 0.05, 0.16, 0.052), (-0.47, 0.022, 0.18, 0.066), (-0.42, 0.012, 0.19, 0.072),
        (-0.12, -0.03, 0.19, 0.076), (-0.04, -0.06, 0.15, 0.07),
        (0.06, -0.08, 0.118, 0.064), (0.2, -0.095, 0.108, 0.064), (0.36, -0.15, 0.108, 0.072),
        (0.5, -0.205, 0.112, 0.08), (0.56, -0.228, 0.113, 0.083), (0.66, -0.265, 0.116, 0.088),
        (0.82, -0.33, 0.12, 0.097), (0.94, -0.38, 0.124, 0.102),
    ]
    loft(m, stock, U.ASH_BONE, bands=[(0.5, 0.56, U.IRON_EDGE)], segments=12, n=STOCK_ROUND)
    # The butt is a bone's end: two knuckles, top and bottom, and the hollow between them.
    m.lathe([(0.0, 0.0), (0.02, 0.07, 0.062), (0.07, 0.095, 0.085), (0.12, 0.088, 0.08), (0.16, 0.0)], U.ASH_BONE,
            axis=(0.0, 0.0, 1.0), centre=(0.0, 0.07, 0.88), segments=10, smooth=True)
    m.lathe([(0.0, 0.0), (0.02, 0.08, 0.075), (0.08, 0.108, 0.1), (0.14, 0.098, 0.09), (0.18, 0.0)], U.ASH_BONE,
            axis=(0.0, 0.0, 1.0), centre=(0.0, -0.33, 0.88), segments=10, smooth=True)
    for y, z in ((0.02, 0.64), (0.0, 0.8)):  # iron rivets through the bone
        m.rivet((0.088, y, z), (1.0, 0.0, 0.0), 0.022, 0.016, U.IRON_EDGE)
        m.rivet((-0.088, y, z), (-1.0, 0.0, 0.0), 0.022, 0.016, U.IRON_EDGE)
    # The bone is cracked by the forge's heat: an ember fissure through each side of the butt.
    def stock_x(y, z):
        for (z0, lo0, hi0, hx0), (z1, lo1, hi1, hx1) in zip(stock, stock[1:]):
            if z0 <= z <= z1:
                f = (z - z0) / (z1 - z0)
                lo, hi, hx = lo0 + (lo1 - lo0) * f, hi0 + (hi1 - hi0) * f, hx0 + (hx1 - hx0) * f
                g = min(0.95, abs(y - (lo + hi) / 2) / ((hi - lo) / 2))
                return hx * (1 - g ** STOCK_ROUND) ** (1 / STOCK_ROUND)
        return stock[-1][3]

    fissure = [(-0.19, 0.6), (-0.235, 0.67), (-0.215, 0.75), (-0.275, 0.84), (-0.26, 0.92)]
    twig = [(-0.215, 0.75), (-0.16, 0.8), (-0.135, 0.87)]
    for side in (1.0, -1.0):
        for path, w, taper in ((fissure, 0.022, [0.5, 1.0, 0.9, 0.8, 0.5]), (twig, 0.016, [1.0, 0.7, 0.35])):
            vein(m, [(side * (stock_x(y, z) + 0.004), y, z) for y, z in path], (side, 0.0, 0.0), w, 0.011,
                 taper=taper)

    # The barrel: forged octagonal black iron with reinforcing rings, then the bell.
    bl = SHOTGUN_BELL
    forged(m, [(-SHOTGUN_BREECH - 0.02, 0.075), (-SHOTGUN_BREECH, 0.104), (0.43, 0.104), (0.45, 0.094), (0.82, 0.088),
               (0.84, 0.099), (0.89, 0.099), (0.91, 0.088), (-bl + 0.02, 0.083)],
           U.IRON_BLACK, U.IRON_EDGE, axis=(0.0, 0.0, -1.0), centre=(0.0, by, 0.0), ref=(1.0, 0.0, 0.0),
           chamfer=0.55, flat2=U.IRON, bands=[(-SHOTGUN_BREECH - 0.02, 0.45, U.IRON_EDGE), (0.82, 0.91, U.IRON_EDGE)])

    # The bell: a black flare with a light lip, and inside it a furnace mouth glowing deeper and
    # hotter toward the bore.
    a0 = -bl
    prof = [(a0, 0.085), (a0 + 0.1, 0.09), (a0 + 0.18, 0.104), (a0 + 0.26, 0.127), (a0 + 0.33, 0.166), (a0 + 0.39, 0.215),
            (a0 + 0.43, 0.255), (a0 + 0.455, 0.278), (a0 + 0.472, 0.272), (a0 + 0.466, 0.246), (a0 + 0.43, 0.214),
            (a0 + 0.37, 0.166), (a0 + 0.32, 0.128)]
    inner = {9: U.EMBER_DEEP, 10: U.EMBER, 11: U.EMBER}  # the white-hot throat is the flat end cap

    def bell_colour(i, j):
        if i in (7, 8):
            return U.IRON_EDGE
        if i in inner:
            return inner[i]
        return U.IRON if j % 2 else U.IRON_BLACK

    m.lathe(prof, U.IRON, axis=(0.0, 0.0, -1.0), centre=(0.0, by, 0.0), ref=(1.0, 0.0, 0.0), segments=16, smooth=False,
            face_colour=bell_colour, cap_colour=U.EMBER_HOT)
    # A charge of live coals packed in the bell's throat: the shot it fires.
    rng = random.Random(17)
    for k in range(6):
        a = k * math.pi / 3 + 0.3
        rad = 0.0 if k == 5 else 0.068
        along = a0 + (0.335 if k == 5 else 0.345)
        m.nodule((rad * math.cos(a), by + rad * math.sin(a), -along), (0.042, 0.042, 0.034), U.EMBER,
                 axis=(0.0, 0.0, -1.0), segments=5, rings=3, jitter=0.18, seed=20 + k,
                 face_colour=lambda i, j, r=rng: U.EMBER if r.random() < 0.6 else U.EMBER_DEEP)
    # Eight light ribs run up the flare to the lip, so the black bell keeps its edge on the panel.
    for k in range(8):
        a = math.pi / 8 + k * math.pi / 4
        d = (math.cos(a), math.sin(a), 0.0)
        path, radii = [], []
        for along, r in prof[1:8]:
            path.append((d[0] * (r + 0.004), by + d[1] * (r + 0.004), -along))
            radii.append((0.012, 0.016))
        m.sweep(path, radii, U.IRON_EDGE, segments=4, smooth=False, normal0=(d[0], d[1], 0.0))
    # Between the ribs, slots near the lip show the fire inside.
    for k in range(8):
        a = k * math.pi / 4
        d = (math.cos(a), math.sin(a), 0.0)
        pts = [(d[0] * (r + 0.006), by + d[1] * (r + 0.006), -along) for along, r in prof[4:7]]
        vein(m, pts, d, 0.017, 0.012, taper=[0.5, 1.0, 0.7], halo=1.6)

    # An iron rib under the barrel, bands binding the two, a ramrod under the rib in two pipes, a bone
    # bead for a sight.
    forged(m, [(0.48, 0.034, 0.03), (1.52, 0.034, 0.03)], U.IRON, U.IRON_EDGE, axis=(0.0, 0.0, -1.0),
           centre=(0.0, 0.078, 0.0), ref=(1.0, 0.0, 0.0), chamfer=0.4)
    for z in (-0.95, -1.38):
        m.loop((0.0, 0.158, z), (0.0, 0.0, 1.0), 0.096, 0.112, (0.016, 0.03), U.IRON_EDGE, ref=(1.0, 0.0, 0.0),
               segments=14, tube_segments=4)
    m.sweep([(0.0, 0.03, -0.46), (0.0, 0.03, -1.5)], 0.018, U.IRON_EDGE, segments=6, smooth=True)
    m.nodule((0.0, 0.03, -1.53), (0.03, 0.03, 0.035), U.ASH_BONE, axis=(0.0, 0.0, 1.0), segments=6, rings=4, jitter=0.0)
    for z in (-0.72, -1.18):
        m.loop((0.0, 0.03, z), (0.0, 0.0, 1.0), 0.03, 0.03, (0.01, 0.022), U.IRON_EDGE, ref=(1.0, 0.0, 0.0), segments=8,
               tube_segments=4)
    m.nodule((0.0, by + 0.098, -1.48), (0.024, 0.024, 0.03), U.ASH_BONE, axis=(0.0, 0.0, 1.0), segments=6, rings=4,
             jitter=0.0)

    # The ember lock on the right: a forged lock plate, a pan, and a cock that holds a live coal.
    plate(m, [(-0.47, 0.115), (-0.41, 0.165), (-0.13, 0.165), (-0.05, 0.11), (-0.13, 0.055), (-0.41, 0.055)], 0.014,
          0.004, U.IRON, U.IRON_EDGE, origin=(0.076, 0.0, 0.0), u=(0.0, 0.0, 1.0), v=(0.0, 1.0, 0.0), inset=0.018)
    m.box(0.07, 0.122, 0.165, 0.19, -0.42, -0.33, U.IRON_EDGE)  # the pan
    m.nodule((0.096, 0.198, -0.375), (0.022, 0.012, 0.03), U.EMBER, axis=(0.0, 1.0, 0.0), segments=6, rings=3,
             jitter=0.1, seed=4)  # embers in the pan
    cock = [(0.098, 0.1, -0.12), (0.098, 0.17, -0.11), (0.098, 0.245, -0.14), (0.098, 0.285, -0.2), (0.098, 0.285, -0.25)]
    m.sweep(cock, [(0.014, 0.026), (0.014, 0.024), (0.014, 0.022), (0.014, 0.02), (0.014, 0.024)], U.IRON_EDGE,
            segments=6, smooth=False, normal0=(1.0, 0.0, 0.0))
    rng = random.Random(9)
    coal = {}

    def coal_colour(i, j):
        return coal.setdefault((i, j), U.EMBER_HOT if rng.random() < 0.55 else U.EMBER)

    m.nodule((0.1, 0.275, -0.3), (0.054, 0.05, 0.058), U.EMBER, axis=(0.0, 0.0, 1.0), segments=7, rings=5,
             jitter=0.14, seed=8, face_colour=coal_colour)
    m.rivet((0.09, 0.1, -0.12), (1.0, 0.0, 0.0), 0.03, 0.02, U.IRON_EDGE)  # the cock's pivot

    # The trigger and its guard.
    m.sweep([(0.0, 0.02, -0.44), (0.0, -0.06, -0.4), (0.0, -0.115, -0.3), (0.0, -0.125, -0.18), (0.0, -0.1, -0.07),
             (0.0, -0.05, 0.0)], (0.016, 0.012), U.IRON_EDGE, segments=6, smooth=True, normal0=(1.0, 0.0, 0.0))
    m.sweep([(0.0, 0.0, -0.22), (0.0, -0.05, -0.215), (0.0, -0.09, -0.185)], [(0.012, 0.018), (0.012, 0.016),
            (0.012, 0.012)], U.IRON_EDGE, segments=4, smooth=False, normal0=(1.0, 0.0, 0.0))

    lo, hi = m.bounds()  # the body's bounds, before the charm hangs below them
    charm(m, (0.0, -0.225, 0.53), drop=0.16, scale=0.75)  # from the iron strap under the butt
    m.frame = {
        "grip": (0.0, 0.0, 0.0),
        "tip": (0.0, by, round(-(a0 + 0.472), 3)),  # the muzzle: the bell's lip on the bore line
        "holster": tuple(round((lo[i] + hi[i]) / 2, 3) for i in range(3)),
        "support": (0.0, 0.1, -0.8),  # where a second hand would hold the forend, between the barrel bands
    }
    m.notes = {"bore": by, "bellMouth": round(2 * 0.278, 3), "holster": "bbox centre of the body, the charm left out",
               "held": "the stock's wrist, the trigger just ahead of the hand"}
    return m


# --- Rifle --------------------------------------------------------------------------------------
# The Piercing Rifle: a long octagonal black-iron barrel in a heat jacket whose louvred ports glow
# like a furnace grate, a ported muzzle brake over a barbed bayonet, a scope sighted through
# obsidian lenses, on a skeletal iron stock with an ash-bone cheek rest, crescent butt and pistol
# grip. Held by the pistol grip; 3.4 studs. Its sections are chunkier than a real rifle's so the
# long gun keeps a body on a 64 px shelf next to the stubbier guns.

RIFLE_RECEIVER = (0.25, -0.56)  # rear and front of the receiver, z
RIFLE_RECEIVER_HALF = (0.084, 0.108)
RIFLE_JACKET = (-0.64, -1.76)
RIFLE_JACKET_HALF = 0.104  # the jacket's body; its collars stand 0.01 proud
RIFLE_BARREL_HALF = 0.066
RIFLE_MUZZLE = -2.40
RIFLE_SCOPE_Y = 0.42
RIFLE_SCOPE_HALF = 0.05
RIFLE_BUTT = 0.96


def rifle() -> Mesh:
    m = Mesh("Rifle")
    by = GUN_BORE_Y
    r0, r1 = RIFLE_RECEIVER
    rx, ry = RIFLE_RECEIVER_HALF

    # The receiver: a forged block, a lock plate on each side.
    forged(m, [(-r0, rx, ry), (-r1, rx, ry)], U.IRON_BLACK, U.IRON_EDGE, axis=(0.0, 0.0, -1.0),
           centre=(0.0, by, 0.0), ref=(1.0, 0.0, 0.0), chamfer=0.32, flat2=U.IRON)
    for sx in (1.0, -1.0):
        plate(m, [(-0.5, by - 0.075), (-0.46, by + 0.075), (0.1, by + 0.075), (0.18, by + 0.005), (0.12, by - 0.075)],
              0.012, 0.004, U.IRON, U.IRON_EDGE, origin=(sx * (rx + 0.001), 0.0, 0.0), u=(0.0, 0.0, 1.0),
              v=(0.0, 1.0, 0.0), inset=0.018)
        for z in (-0.4, 0.04):
            m.rivet((sx * (rx + 0.013), by + 0.045, z), (sx, 0.0, 0.0), 0.02, 0.013, U.IRON_EDGE)
        # a peephole on the side of the breech: the shot's charge glowing through the iron
        m.lathe([(0.0, 0.05), (0.008, 0.05), (0.015, 0.034), (0.018, 0.0)], U.EMBER, axis=(sx, 0.0, 0.0),
                centre=(sx * (rx + 0.007), by, -0.2), ref=(0.0, 0.0, 1.0), segments=10, smooth=False,
                face_colour=lambda i, j: U.EMBER if i == 0 else U.EMBER_HOT)
        m.loop((sx * (rx + 0.015), by, -0.2), (sx, 0.0, 0.0), 0.056, 0.056, (0.013, 0.009), U.IRON_EDGE,
               ref=(0.0, 0.0, 1.0), segments=10, tube_segments=4)

    # The barrel: a long forged octagon, the jacket over its middle, a ported brake at the muzzle.
    bh = RIFLE_BARREL_HALF
    forged(m, [(-r1 - 0.02, bh), (-RIFLE_MUZZLE - 0.2, bh - 0.004)], U.IRON_BLACK, U.IRON_EDGE, axis=(0.0, 0.0, -1.0),
           centre=(0.0, by, 0.0), ref=(1.0, 0.0, 0.0), chamfer=0.55, flat2=U.IRON)
    j0, j1 = -RIFLE_JACKET[0], -RIFLE_JACKET[1]
    jh = RIFLE_JACKET_HALF
    forged(m, [(j0, bh + 0.01), (j0 + 0.01, jh + 0.01), (j0 + 0.06, jh + 0.01), (j0 + 0.07, jh), (j1 - 0.07, jh),
               (j1 - 0.06, jh + 0.01), (j1 - 0.01, jh + 0.01), (j1, bh + 0.01)], U.IRON_BLACK, U.IRON_EDGE,
           axis=(0.0, 0.0, -1.0), centre=(0.0, by, 0.0), ref=(1.0, 0.0, 0.0), chamfer=0.5, flat2=U.IRON,
           bands=[(j0, j0 + 0.07, U.IRON_EDGE), (j1 - 0.07, j1, U.IRON_EDGE)])
    # The jacket's ports, in a row down each side: raked slots with the fire inside.
    count, run0, run1 = 8, j0 + 0.12, j1 - 0.12
    for k in range(count):
        z = -(run0 + (run1 - run0) * k / (count - 1))
        for sx in (1.0, -1.0):  # louvres raked forward, like a furnace's grate
            vein(m, [(sx * (jh + 0.004), by - 0.056, z + 0.034), (sx * (jh + 0.004), by + 0.056, z - 0.034)],
                 (sx, 0.0, 0.0), 0.025, 0.012, taper=[0.7, 0.9], halo=1.5)
    b0 = -RIFLE_MUZZLE - 0.22
    forged(m, [(b0, bh + 0.014), (b0 + 0.015, bh + 0.028), (b0 + 0.205, bh + 0.028), (b0 + 0.22, bh + 0.008)],
           U.IRON_BLACK, U.IRON_EDGE, axis=(0.0, 0.0, -1.0), centre=(0.0, by, 0.0), ref=(1.0, 0.0, 0.0), chamfer=0.45,
           flat2=U.IRON, bands=[(b0 + 0.205, b0 + 0.22, U.IRON_EDGE)], cap_colour=U.IRON_BLACK)
    for zc in (b0 + 0.07, b0 + 0.15):
        for sx in (1.0, -1.0):
            vein(m, [(sx * (bh + 0.031), by - 0.056, -zc), (sx * (bh + 0.031), by + 0.056, -zc)], (sx, 0.0, 0.0),
                 0.022, 0.011, taper=[0.8, 0.8], halo=1.5)
    m.loop((0.0, by, RIFLE_MUZZLE + 0.004), (0.0, 0.0, 1.0), 0.044, 0.044, (0.013, 0.006), U.EMBER_HOT,
           ref=(1.0, 0.0, 0.0), segments=8, tube_segments=4)  # the bore's hot rim

    # A barbed black-iron bayonet under the brake, the Spear's barb in small: the gun pierces.
    bay = [(-1.98, -0.075), (-2.36, -0.075), (-2.445, -0.1), (-2.3, -0.142), (-2.17, -0.16), (-2.115, -0.215),
           (-2.035, -0.262), (-2.07, -0.205), (-2.045, -0.165), (-1.98, -0.148)]
    plate(m, [(z, by + y) for z, y in bay], 0.032, 0.011, U.IRON_BLACK, U.IRON_EDGE, u=(0.0, 0.0, 1.0),
          v=(0.0, 1.0, 0.0), inset=0.021)
    for sx in (1.0, -1.0):
        vein(m, [(sx * 0.034, by - 0.108, -2.06), (sx * 0.034, by - 0.113, -2.2), (sx * 0.034, by - 0.103, -2.33)],
             (sx, 0.0, 0.0), 0.015, 0.008, taper=[0.5, 1.0, 0.45], halo=1.6)
    m.loop((0.0, by - 0.022, -2.0), (0.0, 0.0, 1.0), 0.08, 0.094, (0.015, 0.03), U.IRON_EDGE, ref=(1.0, 0.0, 0.0),
           segments=10, tube_segments=4)  # the bayonet's lug ring

    # The scope: a forged tube on two clamps, sighted through obsidian lenses in light rims.
    sy, sh = RIFLE_SCOPE_Y, RIFLE_SCOPE_HALF

    def bell_colour(i, j):
        return U.IRON_EDGE if i >= 3 or j % 3 == 0 else U.IRON

    forged(m, [(-0.12, sh), (0.66, sh)], U.IRON_BLACK, U.IRON_EDGE, axis=(0.0, 0.0, -1.0), centre=(0.0, sy, 0.0),
           ref=(1.0, 0.0, 0.0), chamfer=0.55, flat2=U.IRON)
    m.lathe([(0.0, sh), (0.03, sh + 0.007), (0.09, sh + 0.032), (0.15, sh + 0.04), (0.17, sh + 0.04), (0.172, sh + 0.02)],
            U.IRON, axis=(0.0, 0.0, -1.0), centre=(0.0, sy, -0.6), ref=(1.0, 0.0, 0.0), segments=12, smooth=False,
            face_colour=bell_colour, cap_colour=U.OBSIDIAN)
    m.lathe([(0.0, sh), (0.03, sh + 0.007), (0.09, sh + 0.02), (0.12, sh + 0.025), (0.135, sh + 0.025), (0.137, sh + 0.008)],
            U.IRON, axis=(0.0, 0.0, 1.0), centre=(0.0, sy, 0.12), ref=(1.0, 0.0, 0.0), segments=12, smooth=False,
            face_colour=bell_colour, cap_colour=U.OBSIDIAN)
    m.nodule((0.0, sy, -0.772), (sh + 0.02, sh + 0.02, 0.024), U.OBSIDIAN, axis=(0.0, 0.0, -1.0), segments=8, rings=4,
             jitter=0.0)  # the obsidian objective, domed and faceted like knapped glass
    m.lathe([(0.0, 0.02), (0.012, 0.026), (0.03, 0.026), (0.04, 0.018)], U.IRON_EDGE, axis=(0.0, 1.0, 0.0),
            centre=(0.0, sy + sh - 0.004, -0.2), segments=8, smooth=False, cap_colour=U.EMBER_HOT)  # the turret
    post0 = by + ry
    for z in (-0.4, 0.0):
        m.loop((0.0, sy, z), (0.0, 0.0, 1.0), sh + 0.012, sh + 0.012, (0.013, 0.028), U.IRON_EDGE, ref=(1.0, 0.0, 0.0),
               segments=10, tube_segments=4)
        forged(m, [(0.0, 0.024, 0.028), (sy - post0 - sh, 0.024, 0.028)], U.IRON, U.IRON_EDGE,
               axis=(0.0, 1.0, 0.0), centre=(0.0, post0, z), ref=(1.0, 0.0, 0.0), chamfer=0.4)

    # The pistol grip: ash-bone over an iron core, raked back, an iron cap at its foot, iron finger ridges.
    rake = (0.0, -math.cos(math.radians(16)), math.sin(math.radians(16)))
    m.lathe([(-0.2, 0.054, 0.066), (-0.16, 0.062, 0.078), (-0.06, 0.064, 0.084), (0.06, 0.064, 0.084),
             (0.14, 0.067, 0.088), (0.16, 0.067, 0.088)], U.ASH_BONE, axis=rake, centre=(0.0, 0.0, 0.0),
            ref=(1.0, 0.0, 0.0), segments=10, smooth=True, cap_colour=U.IRON)
    m.lathe([(0.16, 0.071, 0.092), (0.19, 0.071, 0.092), (0.205, 0.054, 0.074)], U.IRON_EDGE, axis=rake,
            centre=(0.0, 0.0, 0.0), ref=(1.0, 0.0, 0.0), segments=10, smooth=False, cap_colour=U.IRON)
    for k in range(3):
        c = mul(rake, -0.07 + k * 0.07)
        m.loop(add(c, (0.0, 0.0, -0.079)), (1.0, 0.0, 0.0), 0.02, 0.012, 0.008, U.IRON_EDGE, ref=rake, segments=6,
               tube_segments=3)

    # The trigger and its guard, ahead of the grip.
    guard_top = by - ry + 0.008
    m.sweep([(0.0, guard_top, -0.36), (0.0, 0.005, -0.33), (0.0, -0.04, -0.24), (0.0, -0.035, -0.15), (0.0, 0.015, -0.1)],
            (0.017, 0.013), U.IRON_EDGE, segments=6, smooth=True, normal0=(1.0, 0.0, 0.0))
    m.sweep([(0.0, guard_top, -0.2), (0.0, 0.025, -0.195), (0.0, -0.01, -0.17)], [(0.013, 0.019), (0.013, 0.017),
            (0.013, 0.013)], U.IRON_EDGE, segments=4, smooth=False, normal0=(1.0, 0.0, 0.0))

    # The stock: two forged struts and a brace back to the butt, a bone cheek rest on the upper one.
    up0, up1 = (0.0, 0.22, r0 - 0.03), (0.0, 0.185, RIFLE_BUTT - 0.08)
    lo0, lo1 = (0.0, -0.13, 0.07), (0.0, -0.2, RIFLE_BUTT - 0.08)
    for a, b, half in ((up0, up1, (0.042, 0.038)), (lo0, lo1, (0.042, 0.038)),
                       (add(up0, mul(sub(up1, up0), 0.45)), add(lo0, mul(sub(lo1, lo0), 0.2)), (0.033, 0.03))):
        d = sub(b, a)
        forged(m, [(0.0, *half), (math.sqrt(sum(c * c for c in d)), *half)], U.IRON, U.IRON_EDGE, axis=norm(d),
               centre=a, ref=(1.0, 0.0, 0.0), chamfer=0.4)
    # A crescent butt of ash-bone, horned top and bottom, the forge's crack running through it.
    bb = RIFLE_BUTT
    crescent = [(bb - 0.12, 0.2), (bb - 0.06, 0.25), (bb + 0.0, 0.272), (bb - 0.025, 0.15), (bb - 0.045, 0.0),
                (bb - 0.03, -0.15), (bb + 0.0, -0.285), (bb - 0.07, -0.27), (bb - 0.125, -0.21), (bb - 0.135, 0.0)]
    plate(m, crescent, 0.068, 0.04, U.ASH_BONE, U.ASH_BONE, u=(0.0, 0.0, 1.0), v=(0.0, 1.0, 0.0), inset=0.024)
    for sx in (1.0, -1.0):
        vein(m, [(sx * 0.069, 0.12, bb - 0.09), (sx * 0.069, 0.03, bb - 0.075), (sx * 0.069, -0.03, bb - 0.095),
                 (sx * 0.069, -0.13, bb - 0.07)], (sx, 0.0, 0.0), 0.018, 0.01, taper=[0.4, 1.0, 0.85, 0.4])
    loft(m, [(0.33, 0.205, 0.255, 0.044), (0.37, 0.195, 0.295, 0.06), (0.66, 0.18, 0.282, 0.06),
             (0.7, 0.185, 0.245, 0.044)], U.ASH_BONE, segments=10, n=STOCK_ROUND)

    lo, hi = m.bounds()  # the body's bounds, before the charm hangs below them
    charm(m, add(mul(rake, 0.205), (0.0, -0.01, 0.0)), drop=0.16, scale=0.75)  # from the grip's foot
    m.frame = {
        "grip": (0.0, 0.0, 0.0),
        "tip": (0.0, by, RIFLE_MUZZLE),
        "holster": tuple(round((lo[i] + hi[i]) / 2, 3) for i in range(3)),
        "sight": (0.0, sy, 0.257),  # the scope's eyepiece: where an aiming eye sits behind the weapon
        "support": (0.0, by - jh - 0.01, -1.0),  # a second hand under the jacket
    }
    m.notes = {"bore": by, "scope": sy, "holster": "bbox centre of the body, the charm left out",
               "held": "the pistol grip, raked back 16 degrees"}
    return m


PIECES = {
    "Spear": spear,
    "Shotgun": shotgun,
    "Rifle": rifle,
}


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    sys.exit(cli("underworld", PIECES, argv))
