"""The Dream's weapons for the generated weapon kit (L3): a place that is not quite real, crystal and pastels.

Runs inside Blender (headless):

    blender -b -P tools/assets/weapon_kit_dream.py [-- --out <dir>] [--only Spinblade]

Writes `<Model>.glb` and `<Model>.frame.json` per weapon, and `palette-card.glb`, into
assets/kenney3d/weapon-kit/Models/GLB format/. The frame contract, the colour rule and the mesh
vocabulary are weapon_kit_mesh.py's; the colours are weapon_kit_palette.DREAM. The shape helpers
(`slab`, `crystal`, `pistol_grip`, ...) are shared with the Planet's generator.

What makes the two one family, and the Dream's:
  * pearl bodies and grips, smooth where the Planet is bevelled, trimmed in pastel gold;
  * faceted crystal, every facet lit or shaded in two pastels, with deep violet in the joints and
    along the edges that face away, the only colour dark enough to draw a line on a pale sky;
  * pastel-gold collars in pairs where the Forest binds with rope, and a crystal drop on a pink
    ribbon where the Forest hangs its charm;
  * nothing quite touches: rings float round the Chain Gun's barrel, a halo round the Spinblade's
    pommel gem. The last level's weapons are the most ornate of the kit, and the Spinblade, a relic,
    the most ornate of all.
"""

from __future__ import annotations

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from weapon_kit_mesh import Mesh, add, cli, mul, norm, sub  # noqa: E402
from weapon_kit_palette import DREAM as D  # noqa: E402
from weapon_kit_planet import GRIP_BOTTOM, GRIP_TOP, band_by, bar, crystal, pistol_grip, slab, trigger  # noqa: E402

GOLD = (D.PASTEL_YELLOW, D.CRYSTAL_PINK)  # the two-tone collar, as the Forest's two-tone rope


def ribbon(m: Mesh, path, colour, *, width: float = 0.05, thick: float = 0.008, normal0=(1.0, 0.0, 0.0)) -> None:
    """A flat ribbon along a polyline: an elliptical sweep, wide along normal0's side."""
    m.sweep(path, (thick, width / 2), colour, segments=6, smooth=True, normal0=normal0)


def drop_charm(m: Mesh, anchor, *, length: float = 0.28, sway: float = 0.06, x: float = 0.0) -> None:
    """A crystal drop on a pink ribbon, hanging from `anchor`: the Dream's charm."""
    ax, ay, az = anchor
    end = (x, ay - length, az + sway)
    ribbon(m, [anchor, (x, ay - length * 0.35, az + sway * 0.2), (x, ay - length * 0.7, az + sway * 0.75), end],
           D.CRYSTAL_PINK, width=0.045, normal0=(0.0, 0.0, 1.0))
    m.loop(end, (0.0, 1.0, 0.0), 0.026, 0.026, 0.01, D.PASTEL_YELLOW, ref=(1.0, 0.0, 0.0), segments=8, tube_segments=4)
    crystal(m, add(end, (0.0, -0.005, 0.0)), (0.0, -1.0, 0.0), 0.16, 0.042, (D.CRYSTAL_MINT, D.PASTEL_BLUE),
            sides=6, shoulder=0.3, foot=0.5, ref=(1.0, 0.0, 0.0))


def egg_radius(profile, along: float):
    """A lathe profile's (rx, ry) at `along`, interpolated: where to lay a line on its surface."""
    for (a0, x0, y0), (a1, x1, y1) in zip(profile, profile[1:]):
        if a0 <= along <= a1:
            f = (along - a0) / (a1 - a0)
            return x0 + (x1 - x0) * f, y0 + (y1 - y0) * f
    return profile[-1][1], profile[-1][2]


def bolt_outline(centre, length: float, width: float, dip_deg: float):
    """A lightning bolt's side profile in (z, y): its point toward -Z, `dip_deg` below the horizontal,
    `length` from the top edge to the point, centred on `centre`."""
    shape = [(0.60, 1.00), (0.20, 1.00), (0.00, 0.40), (0.36, 0.40), (0.20, -0.02), (0.82, 0.60), (0.46, 0.60)]
    cx = sum(p[0] for p in shape) / len(shape)
    cy = sum(p[1] for p in shape) / len(shape)
    dip = math.radians(dip_deg)
    # The bolt's own down (-y) becomes "forward and down": z -cos(dip), y -sin(dip).
    fwd = (-math.cos(dip), -math.sin(dip))
    side = (-fwd[1], fwd[0])
    out = []
    for x, y in shape:
        u, v = (x - cx) * width, (y - cy) * length
        out.append((centre[0] - v * fwd[0] + u * side[0], centre[1] - v * fwd[1] + u * side[1]))
    return out


# --- Chaingun -----------------------------------------------------------------------------------
# A dream's lightning gun: a smooth pearl body, a faceted violet crystal for a barrel wound with a
# mint crystal coil, three pastel conductor rings floating round it, a pink crystal held in pearl
# claws at the muzzle and a pastel-gold lightning bolt for a crest. 3.07 studs from the finial to
# the muzzle crystal.

CG_Y = 0.46
CG_TIP = -2.04
CG_REAR = 0.88


def chaingun() -> Mesh:
    m = Mesh("Chaingun")
    axis = (0.0, 0.0, -1.0)
    bore = (0.0, CG_Y, 0.0)

    # The pearl body: a smooth egg along the bore, flattened a little side to side.
    prof = [(-0.84, 0.05, 0.06), (-0.80, 0.105, 0.125), (-0.70, 0.15, 0.18), (-0.52, 0.172, 0.207), (-0.26, 0.18, 0.215),
            (0.0, 0.176, 0.207), (0.18, 0.163, 0.186), (0.3, 0.138, 0.152), (0.37, 0.1, 0.105)]
    m.lathe(prof, D.PEARL, axis=axis, centre=bore, segments=18, smooth=True, ref=(1.0, 0.0, 0.0), cap_colour=D.PASTEL_YELLOW)
    # Pastel-gold collars in pairs round the body.
    for k, (along, rx, ry) in enumerate(((-0.64, 0.16, 0.192), (-0.56, 0.168, 0.2), (0.2, 0.16, 0.183), (0.27, 0.15, 0.168))):
        m.loop(add(bore, (0.0, 0.0, -along)), axis, rx + 0.006, ry + 0.006, (0.016, 0.022), GOLD[k % 2], segments=12,
               tube_segments=4, smooth=True, ref=(1.0, 0.0, 0.0))
    # A nacre line spiralling round the egg between the collars, as on a shell.
    spiral = []
    for k in range(31):
        t = k / 30
        along = -0.5 + 0.66 * t
        ang = 2 * math.pi * 1.75 * t + 0.4
        rx, ry = egg_radius(prof, along)
        spiral.append(add(bore, (rx * 1.005 * math.cos(ang), ry * 1.005 * math.sin(ang), -along)))
    m.sweep(spiral, 0.011, D.CRYSTAL_LILAC, segments=4, smooth=True, normal0=(0.0, 0.0, 1.0))
    # Gems set in the flanks, in gold cups.
    for sx in (-1.0, 1.0):
        c = (sx * 0.176, CG_Y + 0.02, 0.12)
        m.lathe([(-0.01, 0.06), (0.012, 0.062), (0.02, 0.05)], D.PASTEL_YELLOW, axis=(sx, 0.0, 0.0), centre=c, segments=10)
        m.nodule(add(c, (sx * 0.018, 0.0, 0.0)), (0.042, 0.042, 0.03), D.CRYSTAL_MINT, axis=(sx, 0.0, 0.0), segments=6,
                 rings=3, jitter=0.0, face_colour=lambda i, j: D.CRYSTAL_MINT if (i + j) % 2 else D.PASTEL_BLUE)

    # The crest: a pastel-gold lightning bolt standing on the body's back, its point toward the muzzle,
    # violet round its edge so it draws a line even on a pale sky.
    slab(m, bolt_outline((0.2, CG_Y + 0.4), 0.72, 0.34, 40.0), 0.032, D.PASTEL_YELLOW, rim=D.PASTEL_YELLOW,
         side=D.PASTEL_YELLOW, chamfer=0.013, band=lambda j: D.CRYSTAL_DEEP)

    # The rear finial: a gold cup holding a pink crystal pointing back.
    m.lathe([(-0.9, 0.03), (-0.87, 0.075), (-0.82, 0.07)], D.PASTEL_YELLOW, axis=axis, centre=bore, segments=12)
    crystal(m, add(bore, (0.0, 0.0, 0.87)), (0.0, 0.0, 1.0), 0.16, 0.055, (D.CRYSTAL_PINK, D.CRYSTAL_LILAC),
            ref=(1.0, 0.0, 0.0), shoulder=0.35)

    # The barrel: a faceted violet crystal wound with a mint crystal coil.
    m.lathe([(0.3, 0.05), (0.36, 0.062), (1.7, 0.062), (1.74, 0.05)], D.CRYSTAL_LILAC, axis=axis, centre=bore,
            segments=6, smooth=False, ref=(1.0, 0.0, 0.0), face_colour=lambda i, j: D.CRYSTAL_LILAC if j % 2 else D.CRYSTAL_DEEP)
    m.loop(add(bore, (0.0, 0.0, -0.36)), axis, 0.1, 0.1, (0.02, 0.035), D.PASTEL_YELLOW, segments=14, smooth=True,
           ref=(1.0, 0.0, 0.0))
    coil = []
    a0, a1, turns, rc = 0.42, 1.56, 5.0, 0.118
    n = int(turns * 12)
    for k in range(n + 1):
        t = k / n
        ang = 2 * math.pi * turns * t
        coil.append(add(bore, (rc * math.cos(ang), rc * math.sin(ang), -(a0 + (a1 - a0) * t))))
    m.sweep(coil, 0.022, D.CRYSTAL_MINT, segments=4, smooth=True, normal0=(0.0, 0.0, 1.0))

    # Three conductor rings floating round it, a pearl bead on each, and their pastel order.
    for along, colour in ((0.62, D.CRYSTAL_PINK), (1.0, D.PASTEL_YELLOW), (1.38, D.PASTEL_BLUE)):
        c = add(bore, (0.0, 0.0, -along))
        m.loop(c, axis, 0.205, 0.205, (0.03, 0.042), colour, segments=16, tube_segments=5, smooth=True, ref=(1.0, 0.0, 0.0))
        for k in range(3):
            a = math.pi / 2 + k * 2 * math.pi / 3
            m.nodule(add(c, (0.205 * math.cos(a), 0.205 * math.sin(a), 0.0)), (0.034, 0.034, 0.034), D.PEARL,
                     axis=(0.0, 0.0, 1.0), segments=5, rings=3, jitter=0.0)

    # The muzzle: three pearl claws curling forward round a pink crystal.
    for k in range(3):
        a = -math.pi / 2 + k * 2 * math.pi / 3
        d = (math.cos(a), math.sin(a), 0.0)
        path = [add(bore, (d[0] * r, d[1] * r, -al)) for al, r in ((1.62, 0.05), (1.72, 0.11), (1.84, 0.14), (1.94, 0.12),
                                                                     (2.0, 0.085))]
        m.sweep(path, [0.03, 0.032, 0.03, 0.024, 0.014], D.PEARL, segments=6, smooth=True)
    m.loop(add(bore, (0.0, 0.0, -1.66)), axis, 0.075, 0.075, (0.02, 0.03), D.PASTEL_YELLOW, segments=12, ref=(1.0, 0.0, 0.0))
    gem_base = add(bore, (0.0, 0.0, -1.76))
    crystal(m, gem_base, axis, -CG_TIP - 1.76, 0.085, (D.CRYSTAL_PINK, D.CRYSTAL_LILAC), ref=(1.0, 0.0, 0.0),
            shoulder=0.25, foot=0.9)
    crystal(m, gem_base, (0.0, 0.0, 1.0), 0.11, 0.085, (D.CRYSTAL_LILAC, D.CRYSTAL_PINK), ref=(1.0, 0.0, 0.0),
            shoulder=0.05, foot=0.9)

    # The grip: pearl framed in pastel gold, lilac ribs; a gold trigger in a pearl guard.
    pistol_grip(m, D.PEARL, D.PASTEL_YELLOW, top=GRIP_TOP, bottom=GRIP_BOTTOM, depth=0.115)
    for sx in (-1.0, 1.0):  # a mint gem in a gold cup on each side of the grip
        c = (sx * 0.087, -0.02, 0.03)
        m.lathe([(-0.01, 0.045), (0.01, 0.047), (0.016, 0.036)], D.PASTEL_YELLOW, axis=(sx, 0.0, 0.0), centre=c, segments=8)
        m.nodule(add(c, (sx * 0.014, 0.0, 0.0)), (0.032, 0.032, 0.024), D.CRYSTAL_MINT, axis=(sx, 0.0, 0.0), segments=6,
                 rings=3, jitter=0.0, face_colour=lambda i, j: D.CRYSTAL_MINT if (i + j) % 2 else D.PASTEL_BLUE)
    trigger(m, -0.16, CG_Y - 0.2, D.PASTEL_YELLOW, D.PEARL)

    # The charm under the body's tail.
    drop_charm(m, (0.0, CG_Y - 0.19, 0.56), length=0.26, sway=0.05)

    lo, hi = m.bounds()
    m.frame = {
        "grip": (0.0, 0.0, 0.0),
        "tip": (0.0, CG_Y, CG_TIP),
        "holster": (0.0, round((lo[1] + hi[1]) / 2, 3), round((lo[2] + hi[2]) / 2, 3)),
        "support": (0.0, 0.28, -0.32),  # the off hand under the egg's nose, behind the coil
    }
    m.notes = {"length": f"finial z +{round(hi[2], 3)} to the muzzle crystal z {CG_TIP}", "boreY": CG_Y,
               "holster": "bbox centre"}
    return m


# --- Spinblade ----------------------------------------------------------------------------------
# The Dream's relic: a curved crystal saber, its edge pearl, its flats lilac and blue, a deep violet
# spine sprouting crystals near the hilt; a pearl crescent guard set with gems, its horns cradling
# the blade; a pearl grip wound with pastel gold, a pink crystal pommel inside a floating gold halo
# and a crystal drop on a ribbon. 3.99 studs from the pommel crystal to the point.

SB_BASE = -0.40  # the blade's root, inside the crescent
SB_LENGTH = 2.92  # along the curve
SB_TURN = math.radians(24.0)  # how far the blade has turned up (+Y) by its point
SB_TIP_RUN = 0.7  # the clipped point: the edge sweeps up to the spine over this run


def saber_frame(s: float):
    """The blade's centreline point, tangent (toward the point) and up normal (toward the spine) at
    arc length s. Straight at the hilt, turning more toward the point, like a scimitar."""
    steps = max(1, int(s / 0.02))
    y = z = 0.0
    ds = s / steps
    for k in range(steps):
        th = SB_TURN * (((k + 0.5) * ds) / SB_LENGTH) ** 1.6
        y += math.sin(th) * ds
        z -= math.cos(th) * ds
    th = SB_TURN * (s / SB_LENGTH) ** 1.6
    return (0.0, y, SB_BASE + z), (0.0, math.sin(th), -math.cos(th)), (0.0, math.cos(th), math.sin(th))


def saber_section(s: float):
    """(spine, ridge, bevel, edge) offsets along the up normal and the half thickness at arc length s."""
    t = s / SB_LENGTH
    edge = 0.2 + 0.075 * math.sin(math.pi * min(1.0, t / 0.75) * 0.5)  # widening toward the point
    spine = 0.04
    ht = 0.066 - 0.026 * t
    q = (s - (SB_LENGTH - SB_TIP_RUN)) / SB_TIP_RUN
    if q > 0:
        ease = math.cos(math.pi / 2 * min(1.0, q))
        edge = (edge + spine) * ease - spine
        ht *= 0.35 + 0.65 * ease
    ridge = spine - (edge + spine) * 0.36
    bevel = spine - (edge + spine) * 0.74
    return spine, ridge, bevel, -edge, ht


def saber_point(s: float, u: float, v: float):
    c, _, n = saber_frame(s)
    return add(c, add((u, 0.0, 0.0), mul(n, v)))


def spinblade() -> Mesh:
    m = Mesh("Spinblade")

    # The blade: seven facets round, pearl edge bands, lilac below the ridge, blue above, violet spine.
    ss = [SB_LENGTH * i / 23 for i in range(23)]
    ss = [s for s in ss if s < SB_LENGTH - SB_TIP_RUN] + [SB_LENGTH - SB_TIP_RUN + SB_TIP_RUN * i / 8 for i in range(8)]
    rings = []
    for s in ss:
        sp, ri, be, ed, ht = saber_section(s)
        tb = ht * 0.45
        rings.append([saber_point(s, u, v) for u, v in ((0.0, ed), (tb, be), (ht, ri), (ht * 0.72, sp), (-ht * 0.72, sp),
                                                          (-ht, ri), (-tb, be))])
    facet = [D.PEARL, D.CRYSTAL_LILAC, D.PASTEL_BLUE, D.CRYSTAL_DEEP, D.PASTEL_BLUE, D.CRYSTAL_LILAC, D.PEARL]
    tip, _, tip_n = saber_frame(SB_LENGTH)
    tip = add(tip, mul(tip_n, 0.03))
    m.grid(rings, D.CRYSTAL_LILAC, apex1=tip, face_colour=lambda i, j: facet[j], cap_colour=D.CRYSTAL_DEEP)
    # A pink vein down the upper flats, like a fuller lit from inside.
    for sx in (-1.0, 1.0):
        path = []
        for k in range(9):
            s = 0.56 + (SB_LENGTH * 0.66 - 0.56) * k / 8
            sp, ri, be, ed, ht = saber_section(s)
            path.append(saber_point(s, sx * (ht * 0.9 + 0.004), ri * 0.5 + sp * 0.5 - 0.01))
        m.sweep(path, (0.008, 0.016), D.CRYSTAL_PINK, segments=5, smooth=True, normal0=(1.0, 0.0, 0.0))

    # A pink gem set in gold in both flats near the hilt, where the vein starts.
    c, t, n = saber_frame(0.4)
    sp, ri, be, ed, ht = saber_section(0.4)
    mid = add(c, mul(n, (sp + ed) / 2 + 0.01))
    for sx in (-1.0, 1.0):
        g = add(mid, (sx * (ht * 0.8), 0.0, 0.0))
        m.loop(g, (sx, 0.0, 0.0), 0.072, 0.072, (0.017, 0.02), D.PASTEL_YELLOW, segments=12, tube_segments=4,
               ref=(0.0, 0.0, 1.0))
        m.nodule(add(g, (sx * 0.008, 0.0, 0.0)), (0.058, 0.058, 0.028), D.CRYSTAL_PINK, axis=(sx, 0.0, 0.0), segments=6,
                 rings=3, jitter=0.0, face_colour=lambda i, j: D.CRYSTAL_PINK if (i + j) % 2 else D.CRYSTAL_LILAC)

    # Crystals sprouting from the spine near the hilt, leaning back.
    for s, length, radius in ((0.34, 0.34, 0.06), (0.62, 0.27, 0.048), (0.88, 0.2, 0.038)):
        c, t, n = saber_frame(s)
        base = add(c, mul(n, 0.02))
        d = norm(add(mul(n, 0.78), mul(t, -0.62)))
        crystal(m, base, d, length, radius, (D.PASTEL_BLUE, D.CRYSTAL_LILAC), ref=(1.0, 0.0, 0.0), shoulder=0.4,
                foot=0.7, phase=math.pi / 6)
        m.loop(add(base, mul(d, 0.025)), d, radius * 0.72, radius * 0.72, 0.014, D.PASTEL_YELLOW, segments=8,
               tube_segments=3, ref=(1.0, 0.0, 0.0))  # a gold socket at its foot

    # Two collars, gold and pink, where the blade leaves the guard.
    for k, s in enumerate((0.06, 0.13)):
        c, t, n = saber_frame(s)
        sp, ri, be, ed, ht = saber_section(s)
        m.loop(add(c, mul(n, (sp + ed) / 2)), t, ht + 0.018, (sp - ed) / 2 + 0.018, (0.017, 0.024), GOLD[k], segments=12,
               tube_segments=4, ref=(1.0, 0.0, 0.0))

    # The crescent guard: pearl, rimmed in pastel gold, horns curling forward round the blade.
    z0 = -0.52
    outer = [(z0 + 0.22 * math.cos(math.radians(a)), 0.6 * math.sin(math.radians(a))) for a in range(-120, 121, 12)]
    inner = [(z0 - 0.05 + 0.1 * math.cos(math.radians(a)), 0.47 * math.sin(math.radians(a))) for a in range(108, -109, -12)]
    slab(m, outer + inner, 0.065, D.PASTEL_YELLOW, rim=D.PASTEL_YELLOW, side=D.PEARL, chamfer=0.022)
    # Gems along the crescent's faces, pink and mint by turns.
    for sx in (-1.0, 1.0):
        for k, a in enumerate((-82, -48, 48, 82)):
            r = math.radians(a)
            c = (sx * 0.064, 0.53 * math.sin(r), z0 + 0.15 * math.cos(r))
            m.nodule(c, (0.032, 0.032, 0.022), D.CRYSTAL_PINK if k % 2 else D.CRYSTAL_MINT, axis=(sx, 0.0, 0.0),
                     segments=6, rings=3, jitter=0.0)
    # A mint gem in a gold cup on both faces, pink crystals on the horn tips.
    for sx in (-1.0, 1.0):
        c = (sx * 0.064, 0.0, -0.33)
        m.lathe([(-0.01, 0.07), (0.016, 0.074), (0.026, 0.06)], D.PASTEL_YELLOW, axis=(sx, 0.0, 0.0), centre=c, segments=10)
        m.nodule(add(c, (sx * 0.024, 0.0, 0.0)), (0.054, 0.054, 0.036), D.CRYSTAL_MINT, axis=(sx, 0.0, 0.0), segments=6,
                 rings=3, jitter=0.0, face_colour=lambda i, j: D.CRYSTAL_MINT if (i + j) % 2 else D.PASTEL_BLUE)
    for sy in (-1.0, 1.0):
        a = math.radians(120)
        tipz, tipy = z0 + 0.22 * math.cos(a) - 0.02, sy * 0.6 * math.sin(a) - sy * 0.02
        crystal(m, (0.0, tipy, tipz), norm((0.0, sy * 0.45, -1.0)), 0.2, 0.05, (D.CRYSTAL_PINK, D.CRYSTAL_LILAC),
                ref=(1.0, 0.0, 0.0), shoulder=0.3, foot=0.8)

    # The grip: pearl wound with a pastel-gold spiral, two-tone collars at both ends.
    m.wrap((0.0, 0.0, 0.0), (0.0, 0.0, 1.0), 0.64, 0.08, 0.08, D.PEARL, D.PASTEL_YELLOW, turns=4.0, ridge=0.17,
           ref=(1.0, 0.0, 0.0), segments=12, per_turn=6)
    m.binding((0.0, 0.0, -0.3), (0.0, 0.0, 1.0), 0.082, 0.082, 2, 0.02, GOLD, ref=(1.0, 0.0, 0.0), segments=12)
    m.binding((0.0, 0.0, 0.33), (0.0, 0.0, 1.0), 0.082, 0.082, 2, 0.02, GOLD, ref=(1.0, 0.0, 0.0), segments=12)

    # The pommel: a gold cup holding a pink crystal, a gold halo floating round it.
    m.lathe([(0.36, 0.075), (0.41, 0.1), (0.45, 0.092), (0.46, 0.06)], D.PASTEL_YELLOW, axis=(0.0, 0.0, 1.0),
            centre=(0.0, 0.0, 0.0), segments=12, smooth=True)
    pommel_base = (0.0, 0.0, 0.44)
    crystal(m, pommel_base, (0.0, 0.0, 1.0), 0.3, 0.105, (D.CRYSTAL_PINK, D.CRYSTAL_LILAC), ref=(1.0, 0.0, 0.0),
            shoulder=0.35, foot=0.75)
    m.loop((0.0, 0.0, 0.55), norm((0.0, 0.35, 1.0)), 0.175, 0.175, 0.015, D.PASTEL_YELLOW, segments=16, tube_segments=4,
           ref=(1.0, 0.0, 0.0), smooth=True)

    # The charm off the pommel cup.
    drop_charm(m, (0.0, -0.09, 0.42), length=0.3, sway=0.07)

    lo, hi = m.bounds()
    base_c, _, _ = saber_frame(0.3)
    m.frame = {
        "grip": (0.0, 0.0, 0.0),
        "tip": tuple(round(c, 3) for c in tip),
        "holster": (0.0, 0.0, round((hi[2] + tip[2]) / 2, 3)),
        "bladeBase": tuple(round(c, 3) for c in base_c),  # a swing trail's inner end: the blade past the collars
    }
    m.notes = {"length": f"pommel crystal z +{round(hi[2], 3)} to point z {round(tip[2], 3)}",
               "rise": f"the point stands {round(tip[1], 3)} above the grip axis", "holster": "middle of the length"}
    return m


PIECES = {
    "Chaingun": chaingun,
    "Spinblade": spinblade,
}


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    sys.exit(cli("dream", PIECES, argv))
