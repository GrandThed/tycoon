"""The Forest's weapons for the generated weapon kit (L3): a raider's camp of wood, bone, rope and flint.

Runs inside Blender (headless):

    blender -b -P tools/assets/weapon_kit_forest.py [-- --out <dir>] [--only Broadsword]

Writes `<Model>.glb` and `<Model>.frame.json` per weapon, and `palette-card.glb`, into
assets/kenney3d/weapon-kit/Models/GLB format/. The frame contract, the colour rule and the mesh
vocabulary are weapon_kit_mesh.py's; the colours are weapon_kit_palette.FOREST (and FIRE for the
Flamethrower that step 2 adds here, with the Warhammer).

What makes these two one family, and the Forest's:
  * the same three materials carry both: knapped flint (the blade, the sword's pommel), pale bone
    (the sword's guard, the bow's nocks and charm beads), rope lashings in two alternating tones;
  * a spiral leather grip on both, bound at its ends with rope;
  * red-ochre war paint in bands, and a hanging charm with an ochre feather;
  * every dark colour is inner: the silhouette edge is always flint-light, bone, rope or the pale
    back of the bow, so both read on the Armory panel (30, 41, 70).
"""

from __future__ import annotations

import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from weapon_kit_mesh import Mesh, add, cli, cross, mul, norm, sub  # noqa: E402
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


PIECES = {
    "Broadsword": broadsword,
    "Longbow": longbow,
}


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    sys.exit(cli("forest", PIECES, argv))
