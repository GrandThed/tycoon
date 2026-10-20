"""The Planet's weapons for the generated weapon kit (L3): a far colony's workshop of alloy and glow strips.

Runs inside Blender (headless):

    blender -b -P tools/assets/weapon_kit_planet.py [-- --out <dir>] [--only Launcher]

Writes `<Model>.glb` and `<Model>.frame.json` per weapon, and `palette-card.glb`, into
assets/kenney3d/weapon-kit/Models/GLB format/. The frame contract, the colour rule and the mesh
vocabulary are weapon_kit_mesh.py's; the colours are weapon_kit_palette.PLANET.

What makes the three one family, and the Planet's:
  * white alloy shells with a grey alloy rim on every edge (the chamfered slab below), dark alloy
    in the joints and vents, so the Forest's "light edge on a darker face" carries to machined metal;
  * glow strips set in dark channels, always the brightest thing on the weapon: cyan on the
    Launcher and the Beam, green on the SMG to match its magazine;
  * rubber grips framed in alloy (rubber is an inner colour, never a silhouette edge), ribbed
    like the Forest's wound grips;
  * a hanging tag on a cable where the Forest hangs its charm.
Each is more machined than anything of the levels before it: no hand-made binding, every part a
bevelled panel, a bolt or a ring.

The shape helpers here (`slab`, `bar`, `crystal`, `pistol_grip`, `tag`) are local to the Planet and
Dream generators (weapon_kit_dream.py imports them); weapon_kit_mesh.py stays frozen.
"""

from __future__ import annotations

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from weapon_kit_mesh import Mesh, add, cli, cross, mul, norm, sub  # noqa: E402
from weapon_kit_palette import PLANET as P  # noqa: E402


# --- shape helpers shared with weapon_kit_dream.py -----------------------------------------------


def inset(outline, d: float):
    """A 2D outline moved inward by d along each corner's bisector (mitred, clamped at sharp corners)."""
    n = len(outline)
    area = sum(outline[i][0] * outline[(i + 1) % n][1] - outline[(i + 1) % n][0] * outline[i][1] for i in range(n))
    s = 1.0 if area > 0 else -1.0
    out = []
    for i in range(n):
        p0, p1, p2 = outline[i - 1], outline[i], outline[(i + 1) % n]
        e0 = (p1[0] - p0[0], p1[1] - p0[1])
        e1 = (p2[0] - p1[0], p2[1] - p1[1])
        l0, l1 = math.hypot(*e0) or 1.0, math.hypot(*e1) or 1.0
        n0 = (-e0[1] / l0 * s, e0[0] / l0 * s)  # the left normal of a counter-clockwise outline is inward
        n1 = (-e1[1] / l1 * s, e1[0] / l1 * s)
        b = (n0[0] + n1[0], n0[1] + n1[1])
        lb = math.hypot(*b) or 1.0
        b = (b[0] / lb, b[1] / lb)
        k = d / max(0.45, b[0] * n0[0] + b[1] * n0[1])
        out.append((p1[0] + b[0] * k, p1[1] + b[1] * k))
    return out


def zy(outline, x: float):
    """A side-profile outline of (z, y) points placed at x."""
    return [(x, y, z) for z, y in outline]


def slab(m: Mesh, outline, half: float, colour, *, rim=None, side=None, chamfer: float = 0.0, x0: float = 0.0,
         band=None) -> None:
    """A side profile of (z, y) points (convex or not) extruded across X from x0 - half to x0 + half.

    With `chamfer`, every edge of both side faces is bevelled at 45 degrees and the bevel takes `rim`:
    the light edge that makes a flat-palette body read as machined. The side faces take `side`, the
    strip round the outline takes `colour`, or `band(j)` for the strip of outline edge j."""
    rim = rim or colour
    side = side or colour
    if chamfer <= 0:
        rings = [zy(outline, x0 - half), zy(outline, x0 + half)]

        def fc(i, j):
            return band(j) if band else colour
    else:
        inner = inset(outline, chamfer)
        rings = [zy(inner, x0 - half), zy(outline, x0 - half + chamfer), zy(outline, x0 + half - chamfer),
                 zy(inner, x0 + half)]

        def fc(i, j):
            if i != 1:
                return rim
            return band(j) if band else colour
    m.grid(rings, colour, cap0_colour=side, cap1_colour=side, face_colour=fc)


def bar(m: Mesh, p0, p1, up, w: float, h: float, colour, *, taper: float = 1.0) -> None:
    """A box from p0 to p1, w across and h along `up` (the ends may taper): a strip, a rail, a strut."""
    d = norm(sub(p1, p0))
    s = norm(cross(d, up))
    u = cross(s, d)

    def ring(p, k):
        return [add(p, add(mul(s, sx * w / 2 * k), mul(u, sy * h / 2 * k))) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]

    m.grid([ring(p0, 1.0), ring(p1, taper)], colour)


def crystal(m: Mesh, base, axis, length: float, radius: float, colours, *, sides: int = 6, ref=None,
            shoulder: float = 0.68, foot: float = 0.55, phase: float = 0.0) -> None:
    """A faceted crystal from a narrower foot at `base` to a point, its facets alternating `colours`
    (a lit and a shaded face read as cut stone even in a flat palette). The point is a tiny ring, not an
    apex, so the facet colours carry into it."""
    k = len(colours)
    m.lathe([(0.0, radius * foot), (length * shoulder, radius), (length * 0.97, radius * 0.08), (length, 1e-3)],
            colours[0], axis=axis, centre=base, segments=sides, smooth=False, ref=ref, phase=phase,
            face_colour=lambda i, j: colours[j % k], cap_colour=colours[-1])


def grip_outline(rake_deg: float = 14.0, top: float = 0.30, bottom: float = -0.34, depth: float = 0.12,
                 grooves: int = 3):
    """A pistol grip's side profile in (z, y), its centre at the origin, raked so the butt sits back
    (+Z). Finger grooves on the front, a flared butt and a beavertail at the top of the back."""
    r = math.radians(rake_deg)
    upv = (-math.sin(r), math.cos(r))
    back = (math.cos(r), math.sin(r))

    def at(t, c):
        return (t * upv[0] + c * back[0], t * upv[1] + c * back[1])

    front = [(top, -depth * 0.95)]
    span = top - 0.06 - (bottom + 0.06)
    for g in range(grooves * 2 + 1):
        t = top - 0.06 - span * g / (grooves * 2)
        front.append((t, -depth * (1.0 if g % 2 == 0 else 0.84)))
    pts = [at(t, c) for t, c in front]
    pts += [at(bottom + 0.035, -depth * 1.1), at(bottom, -depth * 1.06), at(bottom, depth * 1.12),
            at(bottom + 0.035, depth * 1.16), at(bottom + 0.12, depth), at(top - 0.12, depth * 0.92),
            at(top - 0.03, depth * 1.12), at(top + 0.01, depth * 1.2)]
    return pts


def pistol_grip(m: Mesh, rubber, rim, *, half: float = 0.085, rake: float = 14.0, top: float = 0.30,
                bottom: float = -0.34, depth: float = 0.12, ribs=None) -> None:
    """A rubber grip framed in alloy: the rubber fills both side faces, the bevelled rim carries the
    silhouette (rubber is an inner colour). `ribs` (a colour) adds raised ribs across the side faces."""
    outline = grip_outline(rake, top, bottom, depth)
    slab(m, outline, half, rim, rim=rim, side=rubber, chamfer=0.022)
    if ribs:
        r = math.radians(rake)
        upv = (-math.sin(r), math.cos(r))
        back = (math.cos(r), math.sin(r))
        for k in range(5):
            t = top - 0.12 - k * (top - bottom - 0.24) / 4
            for sx in (-1.0, 1.0):
                a = (t * upv[0] - depth * 0.62 * back[0], t * upv[1] - depth * 0.62 * back[1])
                b = (t * upv[0] + depth * 0.62 * back[0], t * upv[1] + depth * 0.62 * back[1])
                x = sx * (half + 0.004)
                bar(m, (x, a[1], a[0]), (x, b[1], b[0]), (sx, 0.0, 0.0), 0.028, 0.014, ribs)


def tag(m: Mesh, anchor, colour, rim, *, cable, mark=None, drop: float = 0.26, sway: float = 0.06,
        size=(0.12, 0.17), x: float | None = None) -> None:
    """A tag on a short cable hanging from `anchor` on the +X side: the Planet's charm (the Forest
    hangs fangs and a feather in the same place)."""
    ax, ay, az = anchor
    x = ax if x is None else x
    end = (x, ay - drop, az + sway)
    m.sweep([anchor, (x, ay - drop * 0.45, az + sway * 0.4), end], 0.011, cable, segments=5, smooth=True)
    m.loop(end, (0.0, 0.0, 1.0), 0.022, 0.022, 0.008, cable, ref=(1.0, 0.0, 0.0), segments=8, tube_segments=4)
    w, h = size
    top = ay - drop - 0.02
    outline = [(az + sway - w / 2, top), (az + sway + w / 2, top), (az + sway + w / 2, top - h + 0.04),
               (az + sway + w / 2 - 0.04, top - h), (az + sway - w / 2 + 0.04, top - h), (az + sway - w / 2, top - h + 0.04)]
    slab(m, outline, 0.014, colour, rim=rim, side=colour, chamfer=0.008, x0=x)
    if mark:
        m.box(x + 0.012, x + 0.02, top - h * 0.62, top - h * 0.38, az + sway - w * 0.28, az + sway + w * 0.28, mark)


def trigger(m: Mesh, z_front: float, y_top: float, colour, guard) -> None:
    """A trigger blade and its guard, in front of a grip whose front face is near z_front."""
    m.sweep([(0.0, y_top - 0.02, z_front - 0.07), (0.0, y_top - 0.09, z_front - 0.09), (0.0, y_top - 0.15, z_front - 0.06)],
            (0.016, 0.03), colour, segments=6, smooth=True, normal0=(1.0, 0.0, 0.0))
    path = [(0.0, y_top - 0.21, z_front + 0.01), (0.0, y_top - 0.23, z_front - 0.12), (0.0, y_top - 0.19, z_front - 0.24),
            (0.0, y_top - 0.08, z_front - 0.28), (0.0, y_top + 0.02, z_front - 0.27)]
    m.sweep(path, (0.03, 0.022), guard, segments=6, smooth=True, normal0=(1.0, 0.0, 0.0))


def band_by(profile, bands, default):
    """face_colour for a lathe: the quad between profile entries i and i+1 takes the colour of the band
    (a0, a1, colour) that holds its midpoint, else `default`. Apex entries (radius 0) must be the ends."""
    along = [p[0] for p in profile if p[1] > 1e-9]

    def fc(i, j):
        mid = (along[i] + along[i + 1]) / 2
        for a0, a1, c in bands:
            if a0 <= mid <= a1:
                return c
        return default

    return fc


# The pistol grip's visible run on every Planet gun: the hand closes round its middle, the origin.
GRIP_TOP = 0.28
GRIP_BOTTOM = -0.28


# --- Launcher -----------------------------------------------------------------------------------
# A colony's shell launcher: a white alloy tube carried over the hand, cyan glow strips down both
# sides, a hazard-orange band where the shell sits and the shell's orange nose in the muzzle, a flared
# exhaust behind with a cyan glow deep in its throat. 3.69 studs from the exhaust lip to the nose.

LT_Y = 0.58  # the tube's axis above the grip centre
LT_R = 0.205
LT_MUZZLE = -2.20  # the muzzle lip
LT_REAR = 1.40  # the exhaust lip


def launcher() -> Mesh:
    m = Mesh("Launcher")
    axis = (0.0, 0.0, -1.0)
    centre = (0.0, LT_Y, 0.0)
    R = LT_R

    # The tube, along = -z. Raised collars, the hazard shell band, a seam either side of it.
    prof = [(-1.16, R - 0.01), (-1.10, R), (-1.04, R), (-1.035, R + 0.025), (-0.93, R + 0.025), (-0.925, R),
            (-0.52, R), (-0.515, R + 0.02), (-0.43, R + 0.02), (-0.425, R),
            (0.33, R), (0.335, R + 0.018), (0.41, R + 0.018), (0.415, R),
            (1.20, R), (1.205, R + 0.03), (1.25, R + 0.03), (1.255, R + 0.022), (1.56, R + 0.022), (1.565, R + 0.03),
            (1.61, R + 0.03), (1.615, R), (1.87, R)]
    bands = [(-1.04, -0.92, P.ALLOY), (-0.52, -0.42, P.ALLOY_DARK), (0.33, 0.42, P.ALLOY),
             (1.20, 1.255, P.ALLOY_DARK), (1.255, 1.56, P.HAZARD), (1.56, 1.62, P.ALLOY_DARK)]
    m.lathe(prof, P.ALLOY_WHITE, axis=axis, centre=centre, segments=18, smooth=True, ref=(1.0, 0.0, 0.0),
            face_colour=band_by(prof, bands, P.ALLOY_WHITE), cap_colour=P.ALLOY_DARK)

    # The muzzle shroud: a thicker grey ring with a white lip, a dark bore, and the shell's nose in it.
    mz = -LT_MUZZLE
    prof = [(1.84, R - 0.005), (1.86, R + 0.055), (mz - 0.05, R + 0.06), (mz - 0.02, R + 0.07), (mz, R + 0.06),
            (mz, R + 0.0), (mz - 0.03, 0.165), (mz - 0.24, 0.165)]
    bands = [(mz - 0.06, mz + 0.01, P.ALLOY_WHITE), (mz - 0.25, mz - 0.025, P.ALLOY_DARK)]
    m.lathe(prof, P.ALLOY, axis=axis, centre=centre, segments=18, smooth=False, ref=(1.0, 0.0, 0.0),
            face_colour=band_by(prof, bands, P.ALLOY), cap_colour=P.ALLOY_DARK)
    nose = [(mz - 0.2, 0.15), (mz - 0.08, 0.148), (mz + 0.0, 0.128), (mz + 0.05, 0.092), (mz + 0.075, 0.05),
            (mz + 0.085, 0.0)]
    m.lathe(nose, P.HAZARD, axis=axis, centre=centre, segments=14, smooth=True, ref=(1.0, 0.0, 0.0),
            face_colour=band_by(nose, [(mz - 0.09, mz - 0.05, P.ALLOY_WHITE)], P.HAZARD))
    # Four bolts round the shroud.
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        d = (math.cos(a), math.sin(a), 0.0)
        m.rivet(add(centre, (d[0] * (R + 0.06), d[1] * (R + 0.06), -(mz - 0.17))), d, 0.026, 0.02, P.ALLOY_WHITE,
                segments=6)

    # Bolts on the grey collars, on the side and the top.
    for along in (-0.985, 0.372):
        for a in (0.0, math.pi / 2, math.pi):
            d = (math.cos(a), math.sin(a), 0.0)
            m.rivet(add(centre, (d[0] * (R + 0.02), d[1] * (R + 0.02), -along)), d, 0.022, 0.018, P.ALLOY_WHITE, segments=6)

    # The exhaust: a grey bell flaring to a white lip, dark inside, a cyan glow deep in the throat.
    rear = -LT_REAR
    prof = [(-1.12, R - 0.012), (-1.2, R + 0.0), (rear + 0.12, R + 0.045), (rear + 0.03, R + 0.072), (rear, R + 0.072),
            (rear, R + 0.035), (rear + 0.06, R - 0.01), (rear + 0.2, 0.15)]
    bands = [(rear - 0.01, rear + 0.035, P.ALLOY_WHITE), (rear + 0.035, rear + 0.21, P.ALLOY_DARK)]
    m.lathe(prof, P.ALLOY, axis=axis, centre=centre, segments=18, smooth=True, ref=(1.0, 0.0, 0.0),
            face_colour=band_by(prof, bands, P.ALLOY), cap_colour=P.GLOW_CYAN)
    for k in range(6):  # vanes in the bell
        a = k * math.pi / 3
        d = (math.cos(a), math.sin(a), 0.0)
        p0 = add(centre, (d[0] * 0.15, d[1] * 0.15, -(rear + 0.2)))
        p1 = add(centre, (d[0] * (R + 0.02), d[1] * (R + 0.02), -(rear + 0.02)))
        bar(m, p0, p1, (0.0, 0.0, 1.0), 0.02, 0.02, P.ALLOY_DARK)

    # Cyan glow strips down both sides in dark channels, broken by the middle collar.
    for sx in (-1.0, 1.0):
        for z0, z1 in ((0.40, -0.31), (-0.44, -1.17)):
            x_in, x_out = sx * (R - 0.03), sx * (R + 0.016)
            m.box(min(x_in, x_out), max(x_in, x_out), LT_Y - 0.052, LT_Y + 0.052, z1, z0, P.ALLOY_DARK)
            x_in, x_out = sx * (R + 0.0), sx * (R + 0.03)
            m.box(min(x_in, x_out), max(x_in, x_out), LT_Y - 0.026, LT_Y + 0.026, z1 + 0.025, z0 - 0.025, P.GLOW_CYAN)
    # And one along the top, short, behind the sight.
    m.box(-0.026, 0.026, LT_Y + R - 0.03, LT_Y + R + 0.016, 0.85, 0.42, P.ALLOY_DARK)
    m.box(-0.013, 0.013, LT_Y + R, LT_Y + R + 0.03, 0.82, 0.45, P.GLOW_CYAN)

    # The receiver under the tube, the grip, the trigger.
    yb, yt = GRIP_TOP - 0.06, LT_Y - R + 0.04
    recv = [(0.30, yt), (0.30, yb + 0.1), (0.18, yb), (-0.36, yb), (-0.46, yb + 0.08), (-0.46, yt)]
    slab(m, recv, 0.1, P.ALLOY, rim=P.ALLOY_WHITE, side=P.ALLOY_WHITE, chamfer=0.024)
    m.box(0.101, 0.11, yb + 0.05, yb + 0.09, -0.3, 0.12, P.ALLOY_DARK)  # a vent seam on the side
    pistol_grip(m, P.RUBBER, P.ALLOY, top=GRIP_TOP, bottom=GRIP_BOTTOM, depth=0.115, ribs=P.ALLOY_DARK)
    trigger(m, -0.16, yb, P.ALLOY_DARK, P.ALLOY)

    # The foregrip under the front of the tube, on a dark clamp.
    fz = -0.98
    m.lathe([(-fz - 0.07, R + 0.018), (-fz + 0.07, R + 0.018)], P.ALLOY_DARK, axis=axis, centre=centre, segments=18,
            smooth=True, ref=(1.0, 0.0, 0.0))
    fg = [(fz + 0.09, LT_Y - R + 0.02), (fz - 0.09, LT_Y - R + 0.02), (fz - 0.1, LT_Y - R - 0.08),
          (fz - 0.075, LT_Y - R - 0.38), (fz + 0.075, LT_Y - R - 0.38), (fz + 0.1, LT_Y - R - 0.08)]
    slab(m, fg, 0.075, P.ALLOY, rim=P.ALLOY, side=P.RUBBER, chamfer=0.02)
    m.box(-0.06, 0.06, LT_Y - R - 0.42, LT_Y - R - 0.37, fz - 0.085, fz + 0.085, P.ALLOY_WHITE)

    # The shoulder pad under the rear: rubber framed in alloy.
    sp = [(1.05, LT_Y - R + 0.03), (0.55, LT_Y - R + 0.03), (0.6, LT_Y - R - 0.07), (1.0, LT_Y - R - 0.1)]
    slab(m, sp, 0.13, P.ALLOY, rim=P.ALLOY, side=P.RUBBER, chamfer=0.025)

    # The sight: a scope on a dark mount, white rings, cyan lenses at both ends and a cyan strip.
    sz = -0.14
    ty = LT_Y + R
    sy = ty + 0.16
    m.box(-0.045, 0.045, ty - 0.03, ty + 0.06, sz - 0.12, sz + 0.12, P.ALLOY_DARK)
    for dz in (-0.07, 0.07):
        m.box(-0.03, 0.03, ty + 0.04, sy - 0.03, sz + dz - 0.03, sz + dz + 0.03, P.ALLOY)
    sprof = [(-0.2, 0.05), (-0.16, 0.058), (-0.15, 0.052), (0.14, 0.052), (0.15, 0.065), (0.21, 0.07)]
    m.lathe([(-sz + a, r) for a, r in sprof], P.ALLOY_DARK, axis=axis, centre=(0.0, sy, 0.0), segments=12, smooth=True,
            ref=(1.0, 0.0, 0.0), face_colour=band_by([(-sz + a, r) for a, r in sprof],
                                                     [(-sz - 0.21, -sz - 0.15, P.ALLOY_WHITE),
                                                      (-sz + 0.14, -sz + 0.22, P.ALLOY_WHITE)], P.ALLOY_DARK),
            cap_colour=P.GLOW_CYAN)
    m.box(0.04, 0.062, sy - 0.016, sy + 0.016, sz - 0.11, sz + 0.1, P.GLOW_CYAN)

    # The tag, hanging off the rear collar on the right.
    tag(m, (R + 0.02, LT_Y - 0.1, 0.98), P.HAZARD, P.ALLOY_WHITE, cable=P.ALLOY_DARK, mark=P.ALLOY_DARK,
        drop=0.24, sway=0.05, x=R + 0.035)

    lo, hi = m.bounds()
    m.frame = {
        "grip": (0.0, 0.0, 0.0),
        "tip": (0.0, LT_Y, LT_MUZZLE),
        "holster": (0.0, round((lo[1] + hi[1]) / 2, 3), round((lo[2] + hi[2]) / 2, 3)),
        "support": (0.0, round(LT_Y - R - 0.2, 3), fz),  # the off hand on the foregrip, for a later two-hand hold
    }
    m.notes = {"length": f"exhaust lip z +{LT_REAR} to muzzle z {LT_MUZZLE}, nose to {round(lo[2], 3)}",
               "boreY": LT_Y, "holster": "bbox centre"}
    return m


# --- Smg ----------------------------------------------------------------------------------------
# A colony guard's machine pistol: a compact bevelled alloy receiver, a glowing green cell magazine
# ahead of the trigger, a vented octagonal shroud, a skeleton stock with a rubber pad, rubber grips.
# 2.56 studs from the butt to the muzzle.

SMG_Y = 0.44  # the bore above the grip centre
SMG_MUZZLE = -1.44
SMG_BUTT = 1.12


def smg() -> Mesh:
    m = Mesh("Smg")
    axis = (0.0, 0.0, -1.0)
    bore = (0.0, SMG_Y, 0.0)

    # The receiver: one bevelled block, its chin cut back under the shroud.
    body = [(0.56, 0.62), (0.56, 0.32), (0.44, 0.24), (-0.42, 0.24), (-0.80, 0.26), (-0.90, 0.33),
            (-0.90, 0.60), (-0.84, 0.66), (0.48, 0.66)]
    slab(m, body, 0.12, P.ALLOY, rim=P.ALLOY, side=P.ALLOY_WHITE, chamfer=0.032)
    # A raised side plate on both sides, a green strip in a dark channel along it.
    plate = [(0.40, 0.60), (0.40, 0.36), (0.30, 0.30), (-0.72, 0.30), (-0.80, 0.38), (-0.80, 0.60)]
    for sx in (-1.0, 1.0):
        slab(m, plate, 0.012, P.ALLOY, rim=P.ALLOY, side=P.ALLOY_WHITE, chamfer=0.01, x0=sx * 0.12)
        m.box(sx * 0.128 - 0.012, sx * 0.128 + 0.012, 0.47, 0.53, -0.76, 0.36, P.ALLOY_DARK)
        m.box(sx * 0.14 - 0.008, sx * 0.14 + 0.008, 0.484, 0.516, -0.74, 0.34, P.GLOW_GREEN)
    # The ejection port on the right, the charging handle at the rear top.
    m.box(0.13, 0.15, 0.36, 0.43, -0.42, -0.12, P.ALLOY_DARK)
    m.box(0.14, 0.152, 0.38, 0.41, -0.4, -0.14, P.ALLOY)
    m.box(-0.05, 0.05, 0.64, 0.7, 0.32, 0.5, P.ALLOY_DARK)
    m.box(-0.11, 0.11, 0.655, 0.69, 0.42, 0.48, P.ALLOY)
    for z in (0.22, -0.62):  # bolts through the plates
        for sx in (-1.0, 1.0):
            m.rivet((sx * 0.133, 0.355, z), (sx, 0.0, 0.0), 0.02, 0.015, P.ALLOY_DARK, segments=6)

    # The top rail and a small reflex sight with a green pane.
    for k in range(7):
        z = 0.3 - k * 0.12
        m.box(-0.07, 0.07, 0.655, 0.69, z - 0.04, z + 0.04, P.ALLOY_DARK)
    # The sight: a round window on a mount, its green pane facing the shooter.
    sz, sy = -0.36, 0.8
    m.box(-0.06, 0.06, 0.67, 0.72, sz - 0.12, sz + 0.1, P.ALLOY)
    m.box(-0.03, 0.03, 0.7, sy - 0.07, sz - 0.05, sz + 0.03, P.ALLOY_DARK)
    m.loop((0.0, sy, sz), (0.0, 0.0, 1.0), 0.075, 0.07, (0.022, 0.04), P.ALLOY_WHITE, segments=14, tube_segments=5,
           ref=(1.0, 0.0, 0.0))
    m.lathe([(-sz - 0.012, 0.062), (-sz + 0.012, 0.062)], P.GLOW_GREEN, axis=(0.0, 0.0, -1.0), centre=(0.0, sy, 0.0),
            segments=12, smooth=False, ref=(1.0, 0.0, 0.0))

    # The shroud: octagonal, its middle band slotted with dark vents; then a dark compensator.
    sh0, sh1 = 0.86, 1.22
    prof = [(sh0, 0.115), (sh0 + 0.03, 0.122), (sh0 + 0.06, 0.122), (sh1 - 0.06, 0.122), (sh1 - 0.03, 0.122), (sh1, 0.112)]

    def shroud_colour(i, j):
        if i == 2 and j % 2 == 0:
            return P.ALLOY_DARK
        return P.ALLOY if i in (0, 4) else P.ALLOY_WHITE

    m.lathe(prof, P.ALLOY_WHITE, axis=axis, centre=bore, segments=8, smooth=False, ref=(1.0, 0.0, 0.0),
            phase=math.pi / 8, face_colour=shroud_colour, cap_colour=P.ALLOY_DARK)
    mz = -SMG_MUZZLE
    prof = [(sh1 - 0.02, 0.07), (sh1, 0.082), (mz - 0.03, 0.082), (mz, 0.09), (mz, 0.06), (mz - 0.04, 0.045)]
    m.lathe(prof, P.ALLOY_DARK, axis=axis, centre=bore, segments=10, smooth=False, ref=(1.0, 0.0, 0.0),
            face_colour=band_by(prof, [(mz - 0.035, mz + 0.01, P.ALLOY_WHITE)], P.ALLOY_DARK), cap_colour=P.RUBBER)
    for k in range(2):  # the compensator's ports
        z = -(sh1 + 0.06 + k * 0.07)
        m.box(-0.03, 0.03, SMG_Y + 0.07, SMG_Y + 0.1, z - 0.02, z + 0.02, P.ALLOY_WHITE)

    # The cell magazine: green glow framed in white alloy, ribs between the cells, a dark base plate.
    mag_r = math.radians(-8.0)
    up = (-math.sin(mag_r), math.cos(mag_r))
    fw = (math.cos(mag_r), math.sin(mag_r))
    mc = (-0.60, 0.0)

    def mag_at(t, c):
        return (mc[0] + t * up[0] + c * fw[0], mc[1] + t * up[1] + c * fw[1])

    mag = [mag_at(0.3, -0.11), mag_at(-0.26, -0.115), mag_at(-0.3, -0.09), mag_at(-0.3, 0.09), mag_at(-0.26, 0.115),
           mag_at(0.3, 0.11)]
    slab(m, mag, 0.085, P.ALLOY_WHITE, rim=P.ALLOY_WHITE, side=P.GLOW_GREEN, chamfer=0.022)
    for k in range(4):
        t = 0.16 - k * 0.12
        a, b = mag_at(t, -0.1), mag_at(t, 0.1)
        bar(m, (0.0, a[1], a[0]), (0.0, b[1], b[0]), (1.0, 0.0, 0.0), 0.03, 0.19, P.ALLOY_WHITE)
    a, b = mag_at(-0.33, -0.12), mag_at(-0.33, 0.12)
    bar(m, (0.0, a[1], a[0]), (0.0, b[1], b[0]), (1.0, 0.0, 0.0), 0.06, 0.2, P.ALLOY_DARK)
    # The magwell collar it seats in.
    well = [mag_at(0.36, -0.14), mag_at(0.2, -0.14), mag_at(0.2, 0.14), mag_at(0.36, 0.14)]
    slab(m, well, 0.105, P.ALLOY, rim=P.ALLOY, side=P.ALLOY, chamfer=0.02)

    # The grip and trigger.
    pistol_grip(m, P.RUBBER, P.ALLOY, top=GRIP_TOP, bottom=GRIP_BOTTOM, depth=0.115, ribs=P.ALLOY_DARK)
    trigger(m, -0.16, 0.24, P.ALLOY_DARK, P.ALLOY)

    # The skeleton stock: two struts to a butt plate, a rubber pad framed in alloy.
    for (y0, y1) in ((0.57, 0.56), (0.33, 0.26)):
        m.sweep([(0.0, y0, 0.5), (0.0, (y0 + y1) / 2, 0.8), (0.0, y1, 1.02)], (0.035, 0.05), P.ALLOY, segments=6,
                smooth=False, normal0=(1.0, 0.0, 0.0))
    butt = [(1.0, 0.66), (1.0, 0.18), (1.07, 0.16), (1.07, 0.68)]
    slab(m, butt, 0.09, P.ALLOY, rim=P.ALLOY_WHITE, side=P.ALLOY_WHITE, chamfer=0.02)
    pad = [(1.07, 0.64), (1.07, 0.2), (SMG_BUTT, 0.22), (SMG_BUTT, 0.62)]
    slab(m, pad, 0.08, P.RUBBER, rim=P.ALLOY, side=P.RUBBER, chamfer=0.012)
    m.box(-0.1, 0.1, 0.4, 0.44, 0.98, 1.02, P.ALLOY_DARK)  # the hinge

    # The tag on the lower strut.
    tag(m, (0.04, 0.29, 0.86), P.GLOW_GREEN, P.ALLOY_WHITE, cable=P.ALLOY_DARK, mark=P.ALLOY_DARK, drop=0.2, sway=0.05,
        x=0.06, size=(0.1, 0.14))

    lo, hi = m.bounds()
    m.frame = {
        "grip": (0.0, 0.0, 0.0),
        "tip": (0.0, SMG_Y, SMG_MUZZLE),
        "holster": (0.0, round((lo[1] + hi[1]) / 2, 3), round((lo[2] + hi[2]) / 2, 3)),
        "support": (0.0, 0.0, -0.6),  # the off hand round the magazine, for a later two-hand hold
    }
    m.notes = {"length": f"butt z +{SMG_BUTT} to muzzle z {SMG_MUZZLE}", "boreY": SMG_Y, "holster": "bbox centre"}
    return m


# --- Beam ---------------------------------------------------------------------------------------
# A colony's beam projector: an alloy body with a glowing cyan power cell on its back, a stack of
# white cooling fins round the barrel, and a dish emitter with a cyan ring and lens. The most
# advanced of the Planet: 2.98 studs from the rear cap to the emitter ring, 3.16 to the tines' tips.

BM_Y = 0.46
BM_EMIT = -1.98  # the emitter ring's front face
BM_REAR = 0.97


def beam() -> Mesh:
    m = Mesh("Beam")
    axis = (0.0, 0.0, -1.0)
    bore = (0.0, BM_Y, 0.0)

    # The body: a bevelled shell, lower at the back, the grip under its middle.
    body = [(BM_REAR, 0.50), (0.92, 0.62), (0.70, 0.70), (-0.46, 0.70), (-0.52, 0.64), (-0.52, 0.28),
            (-0.40, 0.22), (0.20, 0.22), (0.60, 0.30), (0.88, 0.40)]
    slab(m, body, 0.13, P.ALLOY, rim=P.ALLOY, side=P.ALLOY_WHITE, chamfer=0.035)
    # A side panel in dark alloy with a cyan strip, bolts at its corners.
    panel = [(0.66, 0.6), (0.6, 0.38), (-0.38, 0.32), (-0.44, 0.38), (-0.44, 0.6)]
    for sx in (-1.0, 1.0):
        slab(m, panel, 0.01, P.ALLOY_DARK, rim=P.ALLOY, side=P.ALLOY_DARK, chamfer=0.008, x0=sx * 0.132)
        m.box(sx * 0.143 - 0.008, sx * 0.143 + 0.008, 0.47, 0.51, -0.36, 0.56, P.GLOW_CYAN)
        for z, y in ((0.58, 0.56), (-0.4, 0.56), (-0.36, 0.37)):
            m.rivet((sx * 0.142, y, z), (sx, 0.0, 0.0), 0.02, 0.014, P.ALLOY_WHITE, segments=6)

    # The power cell on its back: a cyan core seen between white rings, in a dark cradle.
    cell_y, c0, c1 = 0.80, 0.66, -0.06
    prof = [(-c0, 0.07), (-c0 + 0.02, 0.105)]
    windows = []
    span = c0 - c1
    for k in range(4):
        a = -c0 + 0.05 + k * (span - 0.1) / 4
        prof += [(a, 0.105), (a + 0.035, 0.105), (a + 0.035, 0.09), (a + (span - 0.1) / 4, 0.09)]
        windows.append((a + 0.035, a + (span - 0.1) / 4))
    prof += [(-c1 - 0.05, 0.105), (-c1 - 0.02, 0.105), (-c1, 0.07)]
    m.lathe(prof, P.ALLOY_WHITE, axis=axis, centre=(0.0, cell_y, 0.0), segments=12, smooth=False, ref=(1.0, 0.0, 0.0),
            face_colour=band_by(prof, [(a0, a1, P.GLOW_CYAN) for a0, a1 in windows], P.ALLOY_WHITE),
            cap_colour=P.ALLOY)
    for z in (0.5, 0.08):
        m.box(-0.085, 0.085, 0.66, cell_y - 0.02, z - 0.05, z + 0.05, P.ALLOY_DARK)

    # The rear cap, with a cyan vent.
    m.box(-0.07, 0.07, 0.44, 0.56, BM_REAR - 0.03, BM_REAR + 0.02, P.ALLOY_DARK)
    m.box(-0.045, 0.045, 0.47, 0.53, BM_REAR + 0.0, BM_REAR + 0.03, P.GLOW_CYAN)

    # The barrel core and the fin stack: white fins, grey rims, dark core between, tapering forward.
    m.lathe([(0.4, 0.09), (1.62, 0.09)], P.ALLOY_DARK, axis=axis, centre=bore, segments=12, smooth=True,
            ref=(1.0, 0.0, 0.0))
    fins, f0, f1 = 7, 0.56, 1.42
    pitch = (f1 - f0) / fins
    prof = []
    colours = []
    for k in range(fins):
        a = f0 + k * pitch
        r = 0.275 - 0.05 * k / (fins - 1)
        t = pitch * 0.42
        prof += [(a, 0.11), (a, r), (a + t, r), (a + t, 0.11)]
        colours += [P.ALLOY_WHITE, P.ALLOY, P.ALLOY_WHITE, P.ALLOY_DARK]
    colours = colours[:-1]
    m.lathe(prof, P.ALLOY_WHITE, axis=axis, centre=bore, segments=16, smooth=False, ref=(1.0, 0.0, 0.0),
            phase=math.pi / 16, face_colour=lambda i, j: colours[i], cap_colour=P.ALLOY_WHITE)
    # Four spines through the fins hold the stack.
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        d = (math.cos(a), math.sin(a), 0.0)
        bar(m, add(bore, (d[0] * 0.16, d[1] * 0.16, -(f0 + 0.01))), add(bore, (d[0] * 0.16, d[1] * 0.16, -(f1 - 0.07))),
            d, 0.03, 0.03, P.ALLOY)

    # The emitter: a neck, a white dish dark inside, a cyan ring on its rim, a cyan lens in its heart.
    ez = -BM_EMIT
    prof = [(f1 + 0.02, 0.1), (f1 + 0.1, 0.12), (ez - 0.28, 0.13), (ez - 0.12, 0.24), (ez - 0.03, 0.3), (ez, 0.3),
            (ez, 0.255), (ez - 0.1, 0.19), (ez - 0.16, 0.1)]
    bands = [(f1, f1 + 0.11, P.ALLOY), (ez - 0.001, ez + 0.001, P.ALLOY_WHITE), (ez - 0.17, ez - 0.0005, P.ALLOY_DARK)]
    m.lathe(prof, P.ALLOY_WHITE, axis=axis, centre=bore, segments=18, smooth=False, ref=(1.0, 0.0, 0.0),
            face_colour=band_by(prof, bands, P.ALLOY_WHITE), cap_colour=P.ALLOY_DARK)
    m.loop(add(bore, (0.0, 0.0, -(ez - 0.01))), axis, 0.28, 0.28, 0.034, P.GLOW_CYAN, segments=20, tube_segments=6,
           smooth=True, ref=(1.0, 0.0, 0.0))
    m.lathe([(ez - 0.17, 0.11), (ez - 0.1, 0.1), (ez - 0.05, 0.065), (ez - 0.03, 0.0)], P.GLOW_CYAN, axis=axis,
            centre=bore, segments=12, smooth=True, ref=(1.0, 0.0, 0.0))
    m.loop(add(bore, (0.0, 0.0, -(ez - 0.09))), axis, 0.2, 0.2, 0.014, P.GLOW_CYAN, segments=16, tube_segments=4,
           ref=(1.0, 0.0, 0.0))
    # Three focusing tines arching forward off the rim, a cyan bead on each tip.
    for k in range(3):
        a = math.pi / 2 + k * 2 * math.pi / 3
        d = (math.cos(a), math.sin(a), 0.0)
        path = [add(bore, (d[0] * r, d[1] * r, -al)) for al, r in ((ez - 0.12, 0.27), (ez - 0.02, 0.31), (ez + 0.08, 0.29),
                                                                     (ez + 0.15, 0.23))]
        m.sweep(path, [0.03, 0.032, 0.026, 0.018], P.ALLOY_WHITE, segments=6, smooth=True)
        m.nodule(path[-1], (0.03, 0.03, 0.03), P.GLOW_CYAN, axis=(0.0, 0.0, 1.0), segments=6, rings=4, jitter=0.0)

    # The grip and trigger.
    pistol_grip(m, P.RUBBER, P.ALLOY, top=GRIP_TOP, bottom=GRIP_BOTTOM, depth=0.115, ribs=P.ALLOY_DARK)
    trigger(m, -0.16, 0.22, P.ALLOY_DARK, P.ALLOY)

    # The tag off the body's rear underside.
    tag(m, (0.1, 0.36, 0.72), P.GLOW_CYAN, P.ALLOY_WHITE, cable=P.ALLOY_DARK, mark=P.ALLOY_DARK, drop=0.22, sway=0.05,
        x=0.15, size=(0.1, 0.14))

    lo, hi = m.bounds()
    m.frame = {
        "grip": (0.0, 0.0, 0.0),
        "tip": (0.0, BM_Y, BM_EMIT),  # the emitter ring's front face; the tines reach 0.15 past it
        "holster": (0.0, round((lo[1] + hi[1]) / 2, 3), round((lo[2] + hi[2]) / 2, 3)),
        "support": (0.0, 0.2, -0.44),  # the off hand under the body's front, behind the hot fins
    }
    m.notes = {"length": f"rear cap z +{BM_REAR} to emitter ring z {BM_EMIT}", "boreY": BM_Y, "holster": "bbox centre"}
    return m


PIECES = {
    "Launcher": launcher,
    "Smg": smg,
    "Beam": beam,
}


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    sys.exit(cli("planet", PIECES, argv))
