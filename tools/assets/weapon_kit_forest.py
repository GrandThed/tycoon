"""The Forest's weapons for the generated weapon kit (L3): a raider's camp of wood, bone, rope and flint.

Runs inside Blender (headless):

    blender -b -P tools/assets/weapon_kit_forest.py [-- --out <dir>] [--only Broadsword]

Writes `<Model>.glb` and `<Model>.frame.json` per weapon, and `palette-card.glb`, into
assets/kenney3d/weapon-kit/Models/GLB format/. The frame contract, the colour rule and the mesh
vocabulary are weapon_kit_mesh.py's; the colours are weapon_kit_palette.FOREST, and FIRE for the
Flamethrower's embers.

What makes these four one family, and the Forest's:
  * the same three materials carry all of them: flint or river stone (the sword's blade and pommel,
    the maul's head), pale bone (the guard, the nocks, the maul's spikes, the sprayer's fanged
    mouth and its butt knobs), rope lashings in two alternating tones (an X over every big join);
  * a spiral leather grip on each, bound at its ends with rope;
  * red-ochre war paint in bands, and a hanging charm with fangs and an ochre feather;
  * every dark colour is inner: the silhouette edge is always flint-light, bone, rope, leather or
    pale wood, so all four read on the Armory panel (30, 41, 70);
  * glow is geometry: the Flamethrower's embers are heaped past its lip and a coal sits on top,
    because a ViewportFrame draws no lights or particles.
"""

from __future__ import annotations

import math
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from weapon_kit_mesh import Mesh, add, cli, cross, dot, mul, norm, sub  # noqa: E402
from weapon_kit_palette import FIRE  # noqa: E402
from weapon_kit_palette import FOREST as F  # noqa: E402

ROPE = (F.ROPE, F.ROPE_DARK)


# --- Broadsword ---------------------------------------------------------------------------------
# A raider chief's great flint blade, lashed into a bone crossguard, on a leather-wrapped grip with
# a flint pommel. 3.83 studs from the pommel to the point, 1.32 across the guard.

SWORD_TIP = -3.18
SWORD_BLADE_BASE = -0.40  # inside the guard: the blade runs into the bone
SWORD_GUARD_Z = -0.42
SWORD_POMMEL_Z = 0.52


def broadsword() -> Mesh:
    m = Mesh("Broadsword")

    # The blade: parallel-sided for most of its run, a sharp ogive point, both edges knapped into
    # scallops. The light bevel bands along the edges against the mid flint of the flats are what
    # say "blade" at icon size.
    m.blade(SWORD_BLADE_BASE, SWORD_TIP, lambda t: 0.24 - 0.04 * t, lambda t: 0.06 - 0.022 * t,
            F.FLINT_LIGHT, F.FLINT, bevel=0.6, knap=0.008, knap_pitch=0.2, tip_length=0.74, seed=7)

    # Rope bound round the blade's root, below the guard.
    m.binding((0.0, 0.0, -0.60), (0.0, 0.0, 1.0), 0.062, 0.245, 4, 0.022, ROPE, ref=(1.0, 0.0, 0.0), tilt=0.06)

    # The crossguard: one long bone, knobbed at both ends like a real long bone, ochre bands near
    # the knobs. Along Y, flattened a little front to back.
    profile = [(-0.66, 0.0), (-0.655, 0.05, 0.04), (-0.63, 0.1, 0.078), (-0.585, 0.12, 0.092), (-0.53, 0.1, 0.082),
               (-0.47, 0.08, 0.072), (-0.40, 0.072, 0.068), (-0.22, 0.066, 0.064), (0.0, 0.07, 0.076)]
    profile = profile + [(-a, *r) for a, *r in reversed(profile[:-1])]
    along = [p[0] for p in profile if p[1] > 0]
    ochre = [(-0.47, -0.40), (0.40, 0.47)]

    def guard_colour(i, j):
        mid = (along[i] + along[i + 1]) / 2
        return F.OCHRE if any(a <= mid <= b for a, b in ochre) else F.BONE

    m.lathe(profile, F.BONE, axis=(0.0, 1.0, 0.0), centre=(0.0, 0.0, SWORD_GUARD_Z), ref=(0.0, 0.0, 1.0),
            segments=10, smooth=True, face_colour=guard_colour, cap_colour=F.BONE_SHADE)
    # The bone lashed to the blade's shoulders, then an X of rope over the junction on both flats.
    for y in (-0.31, 0.31):
        m.binding((0.0, y, SWORD_GUARD_Z), (0.0, 1.0, 0.0), 0.066, 0.064, 2, 0.019, ROPE, ref=(0.0, 0.0, 1.0), segments=10)
    for tilt in (-0.62, 0.62):
        m.loop((0.0, 0.0, SWORD_GUARD_Z), (0.0, 0.0, 1.0), 0.092, 0.37, 0.018, F.ROPE, ref=(1.0, 0.0, 0.0),
               tilt=tilt, segments=16)

    # The grip: a leather strap wound in a spiral, rope collars at both ends.
    m.wrap((0.0, 0.0, 0.0), (0.0, 0.0, 1.0), 0.66, 0.084, 0.084, F.LEATHER, F.LEATHER_DARK, turns=4.5,
           ridge=0.16, ref=(1.0, 0.0, 0.0), segments=12, per_turn=6)
    m.binding((0.0, 0.0, -0.315), (0.0, 0.0, 1.0), 0.088, 0.088, 1, 0.02, (F.ROPE_DARK,), ref=(1.0, 0.0, 0.0), segments=10)
    m.binding((0.0, 0.0, 0.365), (0.0, 0.0, 1.0), 0.088, 0.088, 2, 0.02, ROPE, ref=(1.0, 0.0, 0.0), segments=10)

    # The pommel: a knapped flint nodule, its facets light and mid at random like the blade's flakes.
    rng = random.Random(11)
    flakes = {}

    def pommel_colour(i, j):
        return flakes.setdefault((i, j), F.FLINT_LIGHT if rng.random() < 0.4 else F.FLINT)

    m.nodule((0.0, 0.0, SWORD_POMMEL_Z), (0.15, 0.145, 0.13), F.FLINT, axis=(0.0, 0.0, 1.0), ref=(1.0, 0.0, 0.0),
             segments=8, rings=5, jitter=0.1, seed=5, face_colour=pommel_colour)

    # A charm under the pommel: a cord, a bone bead, two fangs and an ochre feather.
    m.sweep([(0.0, -0.085, 0.41), (0.0, -0.2, 0.44), (0.0, -0.3, 0.45)], 0.012, F.LEATHER, segments=5, smooth=True)
    m.nodule((0.0, -0.24, 0.445), (0.034, 0.034, 0.03), F.BONE, axis=(0.0, 1.0, 0.0), segments=6, rings=4, jitter=0.0)
    for dx, lean in ((-0.022, -0.25), (0.022, 0.25)):
        base = (dx, -0.3, 0.45)
        m.lathe([(0.0, 0.024), (0.04, 0.026), (0.13, 0.0)], F.BONE, axis=norm((lean * 0.3, -1.0, 0.05)), centre=base,
                segments=6, smooth=True, cap_colour=F.BONE_SHADE)
    m.feather((0.0, -0.3, 0.465), (0.12, -1.0, 0.3), (0.0, 0.0, 1.0), 0.34, 0.1, F.OCHRE, tip_colour=F.FEATHER_TIP,
              quill=F.BONE)

    m.frame = {
        "grip": (0.0, 0.0, 0.0),
        "tip": (0.0, 0.0, SWORD_TIP),
        "holster": (0.0, 0.0, round((SWORD_TIP + 0.65) / 2, 3)),
        "bladeBase": (0.0, 0.0, -0.66),  # where a swing trail's inner end belongs: the blade past the binding
    }
    m.notes = {"length": "pommel z +0.65 to point z -3.18", "guardSpan": 1.32, "holster": "middle of the length"}
    return m


# --- Longbow ------------------------------------------------------------------------------------
# A self bow: one stave, pale sapwood on the back and darker heartwood on the belly, bone horn nocks,
# a leather grip bound with rope, ochre bands, lashings on the limbs and a feather charm.
# 3.91 studs tall; the string sits 0.51 behind the grip (the archer's side, +Z).

BOW_TIP_Y = 1.81
BOW_RISER = 0.42  # half-length of the stiff middle
BOW_DRAW = 0.58  # how far back (+Z) the limb tips sit
BOW_RECURVE = 0.12  # how far the last fifth of each limb kicks forward again
ARROW_Y = 0.31  # the arrow's height above the grip centre
# Half-sizes of the riser (across X, front to back Z) and of a limb at its root and tip. Chunkier than
# a real longbow on purpose: next to the sword's bone guard a true-to-life stave looks spindly, and
# a limb under a tenth of a stud is two pixels on a 64 px shelf icon.
RISER_A, RISER_B = 0.09, 0.11
LIMB_ROOT_A, LIMB_ROOT_B = 0.092, 0.078
LIMB_TIP_A, LIMB_TIP_B = 0.046, 0.04


def smoothstep(e0: float, e1: float, x: float) -> float:
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def stave(y: float):
    """The stave's centreline point and its half-sizes (a across, along X; b front to back) at height y."""
    ay = abs(y)
    u = max(0.0, (ay - BOW_RISER) / (BOW_TIP_Y - BOW_RISER))
    r = max(0.0, (u - 0.8) / 0.2) ** 2
    z = BOW_DRAW * u * u - BOW_RECURVE * r
    riser = 1.0 - smoothstep(BOW_RISER - 0.1, BOW_RISER + 0.1, ay)
    a = (LIMB_ROOT_A + (LIMB_TIP_A - LIMB_ROOT_A) * u) * (1 - riser) + RISER_A * riser
    b = (LIMB_ROOT_B + (LIMB_TIP_B - LIMB_ROOT_B) * u) * (1 - riser) + RISER_B * riser
    return (0.0, y, z), a, b


def stave_tangent(y: float):
    p0, _, _ = stave(y - 0.01)
    p1, _, _ = stave(y + 0.01)
    return norm(sub(p1, p0))


def longbow() -> Mesh:
    m = Mesh("Longbow")

    ys = []
    for k in range(17):  # lower limb, tip to riser, denser toward the tip where it bends most
        ys.append(-BOW_TIP_Y + (BOW_TIP_Y - BOW_RISER) * (k / 16) ** 1.15)
    ys += [-0.3, -0.15, 0.0, 0.15, 0.3]
    ys += [-v for v in reversed(ys[:17])]
    path, radii = [], []
    for y in ys:
        p, a, b = stave(y)
        path.append(p)
        radii.append((a, b))
    ochre_u = (0.6, 0.66)

    def stave_colour(i, j):
        y = (ys[i] + ys[i + 1]) / 2
        u = (abs(y) - BOW_RISER) / (BOW_TIP_Y - BOW_RISER)
        if ochre_u[0] <= u <= ochre_u[1]:
            return F.OCHRE
        return F.WOOD_LIGHT if j < 4 else F.WOOD  # the back (-Z) pale sapwood, the belly heartwood

    m.sweep(path, radii, F.WOOD, segments=8, smooth=True, normal0=(1.0, 0.0, 0.0), face_colour=stave_colour,
            cap_colour=F.WOOD_DARK)

    # The grip: leather in a spiral over the riser, rope at both ends; a bone arrow shelf above it.
    m.wrap((0.0, 0.0, 0.0), (0.0, 1.0, 0.0), 0.44, RISER_A + 0.005, RISER_B + 0.005, F.LEATHER, F.LEATHER_DARK, turns=3.5, ridge=0.15,
           ref=(1.0, 0.0, 0.0), segments=12, per_turn=6)
    for y in (-0.245, 0.245):
        m.binding((0.0, y, 0.0), (0.0, 1.0, 0.0), RISER_A + 0.01, RISER_B + 0.01, 2, 0.019, ROPE, ref=(1.0, 0.0, 0.0),
                  segments=10)
    m.prism([(-0.06, 0.0), (0.05, 0.0), (0.03, 0.03), (-0.05, 0.03)], RISER_A - 0.01, RISER_A + 0.035, F.BONE,
            origin=(0.0, ARROW_Y - 0.02, 0.0), u=(0.0, 0.0, -1.0), v=(0.0, 1.0, 0.0))

    # Knots in the stave: a hand-cut bow, not a turned one.
    for y, side, seed in ((-0.82, 1.0, 21), (0.74, -1.0, 22), (1.38, 1.0, 23)):
        p, a, b = stave(y)
        m.nodule(add(p, (side * a * 0.8, 0.0, 0.0)), (0.03, 0.045, 0.034), F.WOOD_DARK, axis=(1.0, 0.0, 0.0),
                 segments=6, rings=3, jitter=0.15, seed=seed)

    # Lashings where the riser becomes the limbs, and once more half-way along each limb.
    for y in (-0.5, 0.5, -1.06, 1.06):
        p, a, b = stave(y)
        m.binding(p, stave_tangent(y), a, b, 2, 0.017, ROPE, ref=(1.0, 0.0, 0.0), tilt=0.08, segments=10)

    # Bone horn nocks at both tips, grooved for the string loop.
    nocks = []
    for sign in (-1.0, 1.0):
        y = sign * BOW_TIP_Y
        p, a, b = stave(y)
        t = stave_tangent(y)
        out = mul(t, sign)  # pointing off the tip
        # A long horn tip, bigger than a real nock on purpose: it is the bone that carries the
        # family (the sword's guard) to the icon, where a real-sized nock is a pixel.
        prof = [(-0.16, 0.05), (-0.11, 0.062), (-0.075, 0.053), (-0.055, 0.053), (-0.035, 0.064), (0.03, 0.057),
                (0.09, 0.038), (0.13, 0.018), (0.145, 0.0)]
        groove = (-0.075, -0.055)

        def nock_colour(i, j, prof=prof, groove=groove):
            return F.BONE_SHADE if groove[0] - 1e-6 <= prof[i][0] and prof[i + 1][0] <= groove[1] + 1e-6 else F.BONE

        m.lathe(prof, F.BONE, axis=out, centre=p, ref=(1.0, 0.0, 0.0), segments=8, smooth=True, face_colour=nock_colour)
        g = add(p, mul(out, -0.065))
        m.loop(g, out, 0.057, 0.057, (0.014, 0.012), F.SINEW, ref=(1.0, 0.0, 0.0), segments=10)
        # The string leaves the loop on the belly side (+Z).
        belly = norm(cross((1.0, 0.0, 0.0), out)) if sign > 0 else norm(cross(out, (1.0, 0.0, 0.0)))
        if belly[2] < 0:
            belly = mul(belly, -1)
        nocks.append(add(g, mul(belly, 0.057)))

    lo, hi = nocks
    string_z = (lo[2] + hi[2]) / 2
    m.sweep([lo, hi], 0.018, F.SINEW, segments=6, smooth=True)
    # The serving: a darker wrap on the string where the arrow is nocked, with two ochre nock locators.
    s0 = add(lo, mul(sub(hi, lo), (ARROW_Y - 0.36 - lo[1]) / (hi[1] - lo[1])))
    s1 = add(lo, mul(sub(hi, lo), (ARROW_Y + 0.2 - lo[1]) / (hi[1] - lo[1])))
    m.sweep([s0, s1], 0.025, F.ROPE_DARK, segments=6, smooth=True)
    for dy in (-0.035, 0.035):
        c = add(lo, mul(sub(hi, lo), (ARROW_Y + dy - lo[1]) / (hi[1] - lo[1])))
        m.loop(c, norm(sub(hi, lo)), 0.026, 0.026, 0.011, F.OCHRE, ref=(1.0, 0.0, 0.0), segments=8, tube_segments=4)

    # A charm off the lower grip binding: a cord, two feathers, two fangs and a knapped flint
    # arrowhead, hanging just clear of the stave's +X side.
    cx = RISER_A + 0.035
    end = (cx + 0.005, -0.53, -0.115)
    m.sweep([(cx - 0.03, -0.27, -0.085), (cx, -0.42, -0.105), end], 0.011, F.LEATHER, segments=5)
    m.feather((cx + 0.01, -0.47, -0.11), (0.1, -1.0, -0.55), (0.0, 0.0, 1.0), 0.34, 0.1, F.FEATHER, tip_colour=F.OCHRE,
              quill=F.BONE_SHADE)
    m.feather((cx - 0.005, -0.47, -0.11), (0.0, -1.0, 0.45), (0.0, 0.0, 1.0), 0.3, 0.09, F.OCHRE,
              tip_colour=F.FEATHER_TIP, quill=F.BONE)
    for dz, lean in ((-0.03, -0.3), (0.025, 0.3)):  # two fangs, as on the sword's charm
        m.lathe([(0.0, 0.022), (0.035, 0.024), (0.115, 0.0)], F.BONE, axis=norm((0.05, -1.0, lean)),
                centre=(cx + 0.002, -0.45, -0.11 + dz), segments=6, smooth=True, cap_colour=F.BONE_SHADE)
    point = [(0.17, 0.0), (0.05, 0.046), (0.01, 0.034), (0.022, 0.012), (-0.03, 0.012), (-0.03, -0.012),
             (0.022, -0.012), (0.01, -0.034), (0.05, -0.046)]
    m.prism(point, -0.012, 0.012, F.FLINT_LIGHT, origin=end, u=(0.0, -1.0, 0.0), v=(0.0, 0.0, 1.0),
            side_colour=F.FLINT)

    lo_b, hi_b = m.bounds()
    m.frame = {
        "grip": (0.0, 0.0, 0.0),
        "tip": (0.0, ARROW_Y, round(-stave(ARROW_Y)[2] - 0.005, 3)),  # the muzzle: the arrow leaves the riser's front here
        "nock": (0.0, ARROW_Y, round(string_z, 3)),  # where the arrow's nock sits on the string at rest
        "holster": (0.0, 0.0, round((lo_b[2] + hi_b[2]) / 2, 3)),
    }
    m.notes = {"height": round(hi_b[1] - lo_b[1], 3), "braceHeight": round(string_z, 3), "holster": "bbox centre"}
    return m


# --- local shape helpers (step 2) ---------------------------------------------------------------


def horn(m: Mesh, base, direction, bend, length: float, radius: float, colour, *, curve: float = 0.2,
         rings: int = 6, segments: int = 7, base_colour=None, smooth: bool = True) -> None:
    """A tapering spike (a tusk, a fang, a bone spike, a prong) from `base` along `direction`, its
    tip `curve` x length off the straight line toward `bend`. Rings stay square to the curve."""
    d = norm(direction)
    b = norm(sub(bend, mul(d, dot(bend, d))))
    w = norm(cross(d, b))
    pts = [add(base, add(mul(d, length * k / rings), mul(b, curve * length * (k / rings) ** 2))) for k in range(rings + 1)]
    ring_list = []
    for k in range(rings):
        tan = norm(sub(pts[k + 1], pts[k - 1] if k else pts[k]))
        v = cross(tan, w)
        r = radius * (1.0 - k / rings) ** 0.8
        ring_list.append([add(pts[k], add(mul(w, r * math.cos(2 * math.pi * s / segments)),
                                          mul(v, r * math.sin(2 * math.pi * s / segments)))) for s in range(segments)])
    m.grid(ring_list, colour, smooth=smooth, apex1=pts[-1], cap0_colour=base_colour or colour)


def convex_hull(points):
    """Monotone chain; counter-clockwise, no repeated end point."""
    pts = sorted(set(points))
    if len(pts) < 3:
        return pts

    def turn(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lower, upper = [], []
    for p in pts:
        while len(lower) >= 2 and turn(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(pts):
        while len(upper) >= 2 and turn(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


def belt(m: Mesh, z: float, circles, cord: float, colour, *, samples: int = 20) -> None:
    """A cord pulled tight round round parts lying side by side along Z (a barrel and the gourd
    lashed under it): the convex hull of their cross-sections in the plane z, as one closed loop.
    `circles` = [((x, y), radius), ...]."""
    ring = []
    for (cx, cy), r in circles:
        for k in range(64):
            a = 2 * math.pi * k / 64
            ring.append((cx + (r + cord * 0.8) * math.cos(a), cy + (r + cord * 0.8) * math.sin(a)))
    hull = convex_hull(ring)
    seg = [math.dist(hull[i], hull[(i + 1) % len(hull)]) for i in range(len(hull))]
    total = sum(seg)
    path, i, run = [], 0, 0.0
    for k in range(samples):
        s = total * k / samples
        while run + seg[i] < s:
            run += seg[i]
            i += 1
        f = (s - run) / seg[i]
        a, b = hull[i], hull[(i + 1) % len(hull)]
        path.append((a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f, z))
    m.sweep(path, cord, colour, segments=4, loop=True, smooth=True, normal0=(0.0, 0.0, 1.0))


def charm(m: Mesh, top, *, feather_colour=F.OCHRE, tip_colour=F.FEATHER_TIP, drop: float = 0.21) -> None:
    """The Forest's charm, as on the Broadsword: a cord hanging from `top`, a bone bead, two fangs
    and a dyed feather."""
    x, y, z = top
    m.sweep([(x, y, z), (x, y - drop * 0.55, z + 0.03), (x, y - drop, z + 0.04)], 0.012, F.LEATHER, segments=5, smooth=True)
    m.nodule((x, y - drop * 0.75, z + 0.035), (0.034, 0.034, 0.03), F.BONE, axis=(0.0, 1.0, 0.0), segments=6, rings=4,
             jitter=0.0)
    for dx, lean in ((-0.022, -0.25), (0.022, 0.25)):
        m.lathe([(0.0, 0.024), (0.04, 0.026), (0.13, 0.0)], F.BONE, axis=norm((lean * 0.3, -1.0, 0.05)),
                centre=(x + dx, y - drop, z + 0.04), segments=6, smooth=True, cap_colour=F.BONE_SHADE)
    m.feather((x, y - drop, z + 0.055), (0.12, -1.0, 0.3), (0.0, 0.0, 1.0), 0.34, 0.1, feather_colour,
              tip_colour=tip_colour, quill=F.BONE)


# --- Warhammer ----------------------------------------------------------------------------------
# A river stone, a flattened pebble worn into striking faces, seated in the split top of a thick club
# haft and lashed in with an X of rope; three bone spikes fan out of its back, red ochre is painted
# round it and the haft. The striking face is -Y (the axe's edge side), the spikes +Y. 4.36 studs
# from the butt knob to the stone.

HAMMER_HEAD_Z = -3.25  # the stone's centre on the haft line
HAMMER_HEAD_Y = 0.0
STONE = [  # (along Y, half-size along X, half-size along Z): a flattened river pebble, its two ends
    # worn into rounded striking faces (-Y the face, +Y the back where the spikes sit)
    (-0.66, 0.0, 0.0), (-0.658, 0.13, 0.17), (-0.645, 0.2, 0.26), (-0.615, 0.25, 0.325), (-0.55, 0.285, 0.375),
    (-0.42, 0.305, 0.405), (-0.25, 0.315, 0.42), (-0.08, 0.318, 0.425), (0.08, 0.315, 0.42), (0.24, 0.305, 0.405),
    (0.38, 0.285, 0.375), (0.48, 0.255, 0.33), (0.555, 0.2, 0.26), (0.6, 0.13, 0.17), (0.615, 0.0, 0.0),
]
HAMMER_BUTT = 0.4


def stone_size(y: float):
    """The stone's half-sizes (X, Z) at height y along its axis (stone frame)."""
    for (y0, a0, b0), (y1, a1, b1) in zip(STONE, STONE[1:]):
        if y0 <= y <= y1:
            f = (y - y0) / (y1 - y0)
            return a0 + (a1 - a0) * f, b0 + (b1 - b0) * f
    return 0.0, 0.0


def river_stone(m: Mesh, centre, ochre_band) -> None:
    """A smooth, slightly irregular pebble along Y: per-vertex low-frequency wobble, smooth-shaded,
    a painted red-ochre band, and the striking face paler where it has been battered. (A quartz vein
    painted across the faces was tried: at this face size it stair-steps into square pale patches.)"""
    seg = 16
    rings = []
    for y, a, b in STONE[1:-1]:
        ring = []
        for s in range(seg):
            t = 2 * math.pi * s / seg
            k = 1.0 + 0.035 * math.sin(2 * t + 1.1 + 3.0 * y) + 0.02 * math.cos(3 * t - 2.0 * y)
            ring.append(add(centre, (a * k * math.cos(t), y, b * k * math.sin(t))))
        rings.append(ring)
    ys = [e[0] for e in STONE[1:-1]]

    def colour(i, j):
        y = (ys[i] + ys[i + 1]) / 2
        t = 2 * math.pi * (j + 0.5) / seg
        if ochre_band[0] <= y <= ochre_band[1]:
            return F.OCHRE
        return F.FLINT_LIGHT if y < -0.6 + 0.012 * math.sin(3 * t) else F.FLINT

    m.grid(rings, F.FLINT, smooth=True, apex0=add(centre, (0.0, STONE[0][0], 0.0)),
           apex1=add(centre, (0.0, STONE[-1][0], 0.0)), face_colour=colour, cap0_colour=F.FLINT_LIGHT,
           cap1_colour=F.FLINT)


def warhammer() -> Mesh:
    m = Mesh("Warhammer")
    hc = (0.0, HAMMER_HEAD_Y, HAMMER_HEAD_Z)

    # The haft: a thick club, swelling toward the head, two ochre bands below the stone.
    prof = [(HAMMER_BUTT, 0.098), (0.2, 0.1), (-0.4, 0.1), (-0.9, 0.106), (-1.5, 0.114), (-2.1, 0.122),
            (-2.55, 0.128), (-2.75, 0.13), (-2.95, 0.12)]
    bands = [(-2.42, -2.3), (-2.2, -2.08)]
    # Split the profile so the bands get their own rings.
    extra = sorted({z for band in bands for z in band}, reverse=True)
    full = []
    for (z0, r0), (z1, r1) in zip(prof, prof[1:]):
        full.append((z0, r0))
        for z in extra:
            if z1 < z < z0:
                full.append((z, r0 + (r1 - r0) * (z - z0) / (z1 - z0)))
    full.append(prof[-1])
    zs = [p[0] for p in full]

    def haft_colour(i, j):
        mid = (zs[i] + zs[i + 1]) / 2
        return F.OCHRE if any(a <= mid <= b for a, b in bands) else F.WOOD

    m.lathe(full, F.WOOD, axis=(0.0, 0.0, 1.0), ref=(1.0, 0.0, 0.0), segments=10, smooth=True,
            face_colour=haft_colour, cap_colour=F.WOOD_DARK)
    # Knots: a cut sapling, not a turned pole.
    for z, side, seed in ((-1.2, 1.0, 31), (-1.75, -1.0, 32)):
        m.nodule((0.0, side * 0.105, z), (0.035, 0.03, 0.05), F.WOOD_DARK, axis=(0.0, 0.0, 1.0), segments=6, rings=3,
                 jitter=0.15, seed=seed)

    # The grip: the same spiral leather as the sword's, rope collars at both ends.
    m.wrap((0.0, 0.0, 0.0), (0.0, 0.0, 1.0), 0.7, 0.104, 0.104, F.LEATHER, F.LEATHER_DARK, turns=4.5, ridge=0.15,
           ref=(1.0, 0.0, 0.0), segments=10, per_turn=5)
    m.binding((0.0, 0.0, -0.385), (0.0, 0.0, 1.0), 0.106, 0.106, 2, 0.022, ROPE, ref=(1.0, 0.0, 0.0), segments=12)
    m.binding((0.0, 0.0, 0.37), (0.0, 0.0, 1.0), 0.104, 0.104, 1, 0.022, (F.ROPE_DARK,), ref=(1.0, 0.0, 0.0), segments=12)
    # The butt: a knuckle of bone, as on the ends of the sword's guard.
    m.lathe([(0.0, 0.11), (0.05, 0.13, 0.125), (0.12, 0.14, 0.13), (0.18, 0.115, 0.11), (0.22, 0.06), (0.235, 0.0)],
            F.BONE, axis=(0.0, 0.0, 1.0), centre=(0.0, 0.0, HAMMER_BUTT - 0.02), ref=(1.0, 0.0, 0.0), segments=10,
            smooth=True, cap_colour=F.BONE_SHADE)
    charm(m, (0.0, -0.12, HAMMER_BUTT + 0.1))

    # The head.
    river_stone(m, hc, ochre_band=(0.24, 0.38))
    # The haft's split top: two wooden cheeks up the stone's flanks.
    for side in (-1.0, 1.0):
        path = []
        for z in (-2.62, -2.76, -2.9, -3.06, -3.25, -3.42, -3.54, -3.62):
            if z > HAMMER_HEAD_Z + 0.4:
                x = 0.12 + (0.24 - 0.12) * (-2.62 - z) / (-2.62 - (HAMMER_HEAD_Z + 0.4))
            else:
                a, b = stone_size(0.0)
                dz = (z - HAMMER_HEAD_Z) / b
                x = a * math.sqrt(max(0.0, 1 - dz * dz)) + 0.035
            path.append((side * x, HAMMER_HEAD_Y, z))
        m.sweep(path, (0.03, 0.1), F.WOOD, segments=8, smooth=True, normal0=(1.0, 0.0, 0.0), cap_colour=F.WOOD_LIGHT)
    # Rope over the stone and its cheeks in an X (the sword guard's lashing), and round the closed split.
    a, b = stone_size(0.0)
    for tilt, colour in ((0.34, F.ROPE), (-0.34, F.ROPE_DARK)):
        m.loop(hc, (0.0, 1.0, 0.0), a + 0.075, b + 0.035, (0.024, 0.022), colour, ref=(1.0, 0.0, 0.0), segments=16,
               tilt=tilt)
    m.binding((0.0, 0.0, -2.68), (0.0, 0.0, 1.0), 0.14, 0.14, 3, 0.022, ROPE, ref=(1.0, 0.0, 0.0), segments=10, tilt=0.06)

    # Bone spikes fanning out of the stone's back, each lashed at its root.
    for lean, length, r in ((0.0, 0.46, 0.085), (-0.6, 0.36, 0.07), (0.6, 0.36, 0.07)):
        d = norm((0.0, math.cos(lean), math.sin(lean)))
        base = add(hc, (0.0, 0.5 * math.cos(lean), 0.3 * math.sin(lean)))
        horn(m, base, d, (0.0, 0.0, -1.0), length, r, F.BONE, curve=0.12, rings=6, segments=8, base_colour=F.BONE_SHADE)
        m.loop(add(base, mul(d, 0.07)), d, r * 0.95 + 0.012, r * 0.95 + 0.012, 0.017, F.ROPE_DARK,
               ref=(1.0, 0.0, 0.0), segments=8, tube_segments=4)

    lo, hi = m.bounds()
    m.frame = {
        "grip": (0.0, 0.0, 0.0),
        "tip": (0.0, HAMMER_HEAD_Y, round(lo[2], 3)),  # the top of the stone, the end of the swing
        "holster": (0.0, 0.0, round((lo[2] + hi[2]) / 2, 3)),
        "head": hc,  # the stone's centre: where a slam ring or a hit flash belongs
    }
    m.notes = {"length": round(hi[2] - lo[2], 3), "headSpan": round(hi[1] - lo[1], 3),
               "striking face": "-Y; spikes +Y", "holster": "middle of the length"}
    return m


# --- Flamethrower -------------------------------------------------------------------------------
# A raider's bellows sprayer: a pleated hide bellows between two carved boards (squeezed by the
# handles at the back), a wooden barrel, a bone horn mouth crowned with fangs and glowing with
# embers, a hide-and-gourd fuel flask lashed under the barrel, and a coal kept alight on top as
# the pilot. Pistol grip at the origin. 3.3 studs from the handles to the mouth.

BELLOWS_REAR, BELLOWS_NOSE = 0.9, -0.42
BELLOWS_HW, BELLOWS_HW_NOSE, BELLOWS_CAP = 0.25, 0.085, 0.2
BOARD_T = 0.06
BOARD_LOW = 0.27  # the bottom board's underside: just above the grip
TOP_REAR, TOP_NOSE = 0.8, 0.45  # the top board's underside at the rear and at the nose
BARREL_Y = 0.39
BARREL_FRONT = -1.66
GOURD_REAR, GOURD_Y = -0.44, 0.13
GOURD = [(0.0, 0.0), (0.04, 0.11), (0.1, 0.17), (0.2, 0.2), (0.31, 0.195), (0.42, 0.16), (0.5, 0.118), (0.56, 0.112),
         (0.64, 0.13), (0.72, 0.125), (0.8, 0.09), (0.86, 0.056), (0.9, 0.046), (0.93, 0.0)]
GRIP_AXIS = norm((0.0, 1.0, -0.25))


def bellows_hw(f: float) -> float:
    """Half-width of the bellows boards at f studs forward of their rear: a round paddle end, then
    a taper to the nose."""
    length = BELLOWS_REAR - BELLOWS_NOSE
    if f < BELLOWS_CAP:
        return BELLOWS_HW * math.sqrt(max(0.0, 1 - ((BELLOWS_CAP - f) / BELLOWS_CAP) ** 2))
    u = (f - BELLOWS_CAP) / (length - BELLOWS_CAP)
    return BELLOWS_HW + (BELLOWS_HW_NOSE - BELLOWS_HW) * u ** 1.3


def bellows_outline(inset: float = 0.0):
    """The boards' outline as (x, z), round end at the rear, cut square at the nose."""
    length = BELLOWS_REAR - BELLOWS_NOSE
    fs = [0.0, 0.04, 0.1, 0.2, 0.45, 0.72, 1.0, length]
    right = [(max(bellows_hw(f) - inset, 0.012), BELLOWS_REAR - f - (inset if f == 0 else 0.0)) for f in fs[1:]]
    return [(0.0, BELLOWS_REAR - inset)] + right + [(-x, z) for x, z in reversed(right)]


def top_low(z: float) -> float:
    return TOP_NOSE + (TOP_REAR - TOP_NOSE) * (z - BELLOWS_NOSE) / (BELLOWS_REAR - BELLOWS_NOSE)


def gourd_r(along: float) -> float:
    for (a0, r0), (a1, r1) in zip(GOURD, GOURD[1:]):
        if a0 <= along <= a1:
            return r0 + (r1 - r0) * (along - a0) / (a1 - a0)
    return 0.0


def flamethrower() -> Mesh:
    m = Mesh("Flamethrower")

    # The boards: the bottom one flat on the grip, the top one tilted up to the rear.
    outline = bellows_outline()
    lo = [(x, BOARD_LOW, z) for x, z in outline]
    hi = [(x, BOARD_LOW + BOARD_T, z) for x, z in outline]
    m.grid([lo, hi], F.WOOD_LIGHT, cap0_colour=F.WOOD, cap1_colour=F.WOOD)
    lo = [(x, top_low(z), z) for x, z in outline]
    hi = [(x, top_low(z) + BOARD_T, z) for x, z in outline]
    m.grid([lo, hi], F.WOOD_LIGHT, cap0_colour=F.WOOD, cap1_colour=F.WOOD)

    # The pleated hide bag between them: rings alternately out and in, lit faces up, shaded down.
    folds = 5
    levels = 2 * folds + 1
    bag = []
    for k in range(levels):
        t = k / (levels - 1)
        inset = 0.012 if k % 2 == 0 else 0.065
        ring = []
        for x, z in bellows_outline(inset):
            y0 = BOARD_LOW + BOARD_T
            ring.append((x, y0 + (top_low(z) - y0) * t, z))
        bag.append(ring)

    def bag_colour(i, j):
        return F.LEATHER if i % 2 == 0 else F.LEATHER_DARK

    m.grid(bag, F.LEATHER, face_colour=bag_colour)

    # Ochre chevrons painted on the top board, bone studs round its rim.
    slope = norm((0.0, TOP_REAR - TOP_NOSE, BELLOWS_REAR - BELLOWS_NOSE))  # up the board, toward the rear
    board_n = norm(cross((1.0, 0.0, 0.0), slope))
    if board_n[1] < 0:
        board_n = mul(board_n, -1)
    for z0 in (0.38, 0.1):
        y0 = top_low(z0) + BOARD_T
        chevron = [(-0.15, 0.0), (0.0, 0.09), (0.15, 0.0), (0.15, -0.05), (0.0, 0.04), (-0.15, -0.05)]
        m.prism(chevron, 0.0, 0.007, F.OCHRE, origin=(0.0, y0, z0), u=(1.0, 0.0, 0.0), v=mul(slope, -1.0))
    for f, side in ((0.3, 1), (0.3, -1), (0.72, 1), (0.72, -1), (1.08, 1), (1.08, -1)):
        z = BELLOWS_REAR - f
        m.rivet((side * (bellows_hw(f) - 0.045), top_low(z) + BOARD_T, z), board_n, 0.028, 0.026, F.BONE, segments=5)

    # The handles at the back, turned wood with bone knobs: squeeze them to blow.
    handle = [(0.0, 0.045), (0.05, 0.05), (0.14, 0.04), (0.22, 0.048), (0.27, 0.042)]
    for base, axis in (((0.0, BOARD_LOW + BOARD_T / 2, BELLOWS_REAR - 0.05), (0.0, 0.0, 1.0)),
                       ((0.0, TOP_REAR + BOARD_T / 2, BELLOWS_REAR - 0.05), slope)):
        m.lathe(handle, F.WOOD, axis=axis, centre=base, ref=(1.0, 0.0, 0.0), segments=7, smooth=True,
                cap_colour=F.WOOD_DARK)
        m.nodule(add(base, mul(axis, 0.31)), (0.06, 0.06, 0.055), F.BONE, axis=axis, ref=(1.0, 0.0, 0.0), segments=7,
                 rings=4, jitter=0.06, seed=41)

    # The nose block where the boards meet the barrel, bound with rope.
    m.lathe([(0.0, 0.1, 0.075), (0.06, 0.11, 0.085), (0.16, 0.095, 0.08), (0.22, 0.075)], F.WOOD,
            axis=(0.0, 0.0, -1.0), centre=(0.0, BARREL_Y, BELLOWS_NOSE + 0.04), ref=(1.0, 0.0, 0.0), segments=10,
            smooth=True, cap_colour=F.WOOD_DARK)
    m.binding((0.0, BARREL_Y, BELLOWS_NOSE - 0.12), (0.0, 0.0, 1.0), 0.088, 0.078, 2, 0.02, ROPE, ref=(1.0, 0.0, 0.0),
              segments=8)

    # The barrel: wood, two ochre bands, rope at the joins.
    prof = [(0.0, 0.07), (0.38, 0.068), (0.42, 0.068), (0.5, 0.068), (0.86, 0.066), (0.94, 0.066), (1.02, 0.066),
            (BELLOWS_NOSE - 0.18 - BARREL_FRONT, 0.064)]
    alongs = [p[0] for p in prof]

    def barrel_colour(i, j):
        mid = (alongs[i] + alongs[i + 1]) / 2
        return F.OCHRE if 0.38 < mid < 0.5 or 0.86 < mid < 0.94 else F.WOOD

    m.lathe(prof, F.WOOD, axis=(0.0, 0.0, -1.0), centre=(0.0, BARREL_Y, BELLOWS_NOSE - 0.18), ref=(1.0, 0.0, 0.0),
            segments=8, smooth=True, face_colour=barrel_colour, cap_colour=F.WOOD_DARK)

    # The mouth: a bone horn bell with a fang crown on the lip; its throat glows, and the embers are
    # heaped up past the lip, so the fire shows from the side and on a 64 px icon, not only head on.
    bell = [(1.6, 0.074), (1.7, 0.082), (1.8, 0.1), (1.88, 0.13), (1.95, 0.175), (2.0, 0.215), (2.03, 0.214),
            (2.035, 0.19), (2.0, 0.16), (1.95, 0.12), (1.92, 0.0)]

    def bell_colour(i, j):
        if i >= 8:
            return FIRE.FLAME_RED
        if i == 7:
            return FIRE.FLAME_ORANGE
        return F.BONE_SHADE if i in (0, 5, 6) else F.BONE

    m.lathe(bell, F.BONE, axis=(0.0, 0.0, -1.0), centre=(0.0, BARREL_Y, 0.0), ref=(1.0, 0.0, 0.0), segments=12,
            smooth=True, face_colour=bell_colour, cap_colour=F.BONE_SHADE)
    rng = random.Random(53)
    heap = {}
    m.nodule((0.0, BARREL_Y, -2.0), (0.155, 0.155, 0.13), FIRE.FLAME_ORANGE, axis=(0.0, 0.0, -1.0), ref=(1.0, 0.0, 0.0),
             segments=9, rings=5, jitter=0.12, seed=54,
             face_colour=lambda i, j: heap.setdefault((i, j), FIRE.FLAME_YELLOW if i >= 2 and rng.random() < 0.7
                                                         else FIRE.FLAME_ORANGE))
    for k in range(8):
        a = 2 * math.pi * (k + 0.5) / 8
        c, s = math.cos(a), math.sin(a)
        base = (0.205 * c, BARREL_Y + 0.205 * s, -2.02)
        horn(m, base, (0.45 * c, 0.45 * s, -1.0), (c, s, 0.0), 0.11, 0.024, F.BONE, curve=0.25, rings=3, segments=5,
             base_colour=F.BONE_SHADE)
    m.binding((0.0, BARREL_Y, -1.64), (0.0, 0.0, 1.0), 0.078, 0.078, 2, 0.02, ROPE, ref=(1.0, 0.0, 0.0), segments=8)

    # The pilot: a coal on top of the barrel, held in three bone prongs.
    coal = (0.0, BARREL_Y + 0.15, -1.42)
    rng = random.Random(51)
    glow = {}
    m.nodule(coal, (0.075, 0.075, 0.08), FIRE.FLAME_ORANGE, axis=(0.0, 1.0, 0.0), ref=(1.0, 0.0, 0.0), segments=7,
             rings=4, jitter=0.12, seed=52,
             face_colour=lambda i, j: glow.setdefault((i, j), FIRE.FLAME_YELLOW if rng.random() < 0.45 else FIRE.FLAME_ORANGE))
    for k in range(3):
        a = 2 * math.pi * k / 3 + 0.4
        c, s = math.cos(a), math.sin(a)
        base = (0.05 * c, BARREL_Y + 0.055, -1.42 + 0.05 * s)
        horn(m, base, (0.4 * c, 1.0, 0.4 * s), (-c, 0.0, -s), 0.19, 0.018, F.BONE, curve=0.35, rings=3, segments=5)

    # The fuel flask under the barrel: a calabash, hide stitched over its big end, its neck a hose up
    # into the barrel, lashed on with two rope belts.
    gc = (0.0, GOURD_Y, GOURD_REAR)
    galong = [g[0] for g in GOURD if g[1] > 0]

    def gourd_colour(i, j):
        mid = (galong[i] + galong[i + 1]) / 2
        if 0.4 < mid < 0.46:
            return F.ROPE
        return F.LEATHER if mid < 0.42 else F.WOOD_LIGHT

    m.lathe(GOURD, F.WOOD_LIGHT, axis=(0.0, 0.0, -1.0), centre=gc, ref=(1.0, 0.0, 0.0), segments=10, smooth=True,
            face_colour=gourd_colour)
    tip = add(gc, (0.0, 0.0, -0.9))
    m.sweep([add(tip, (0.0, 0.02, 0.0)), add(tip, (0.0, 0.1, -0.05)), add(tip, (0.0, 0.18, -0.07)),
             (0.0, BARREL_Y - 0.03, tip[2] - 0.08)], 0.034, F.LEATHER, segments=7, smooth=True, cap_colour=F.LEATHER_DARK)
    for along in (0.22, 0.7):
        belt(m, GOURD_REAR - along, [((0.0, BARREL_Y), 0.068), ((0.0, GOURD_Y), gourd_r(along))], 0.02,
             F.ROPE if along < 0.5 else F.ROPE_DARK)

    # The grip: leather spiral, rope collars, a bone knob, the Forest's charm.
    m.wrap((0.0, 0.0, 0.0), GRIP_AXIS, 0.5, 0.072, 0.082, F.LEATHER, F.LEATHER_DARK, turns=3.0, ridge=0.15,
           ref=(1.0, 0.0, 0.0), segments=10, per_turn=5)
    for along, turns, cols in ((0.265, 1, (F.ROPE,)), (-0.255, 1, (F.ROPE_DARK,))):
        m.binding(mul(GRIP_AXIS, along), GRIP_AXIS, 0.074, 0.084, turns, 0.02, cols, ref=(1.0, 0.0, 0.0), segments=10)
    knob = mul(GRIP_AXIS, -0.29)
    m.nodule(knob, (0.085, 0.09, 0.06), F.BONE, axis=GRIP_AXIS, ref=(1.0, 0.0, 0.0), segments=8, rings=4, jitter=0.06,
             seed=43)
    charm(m, add(knob, (0.0, -0.05, 0.02)), drop=0.18)

    lo_b, hi_b = m.bounds()
    m.frame = {
        "grip": (0.0, 0.0, 0.0),
        "tip": (0.0, BARREL_Y, -2.04),  # the muzzle: the centre of the horn's mouth, where the flame starts
        "holster": (0.0, round((lo_b[1] + hi_b[1]) / 2, 3), round((lo_b[2] + hi_b[2]) / 2, 3)),
        "pilot": coal,
    }
    m.notes = {"length": round(hi_b[2] - lo_b[2], 3), "barrelY": BARREL_Y, "holster": "bbox centre"}
    return m


PIECES = {
    "Broadsword": broadsword,
    "Longbow": longbow,
    "Flamethrower": flamethrower,
    "Warhammer": warhammer,
}


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    sys.exit(cli("forest", PIECES, argv))
