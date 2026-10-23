"""The raider kit's throwers (L4 W2): the slinger and the lobber, registered by raider_kit.py.

Runs inside Blender as part of the generator (never on its own):

    blender -b -P tools/assets/raider_kit.py -- --only RaiderSlinger --only RaiderLobber --merge

Both are keepAway shooters 5 tall that walk through their recover, so they are drawn light and
upright (no hunch), and their lit piece is the whole tell before they fire (ThreatFx/Cues):

  * **the slinger** (radius 1.2, head 0.65, cloth yellow): a sleeveless tunic and a head wrap in the
    kind's cloth, a leather sling on two sinew cords in the right hand, a bag of stones on the left
    hip, a bandolier of small pouches. The lit orb rides the sling's pouch (`cue` piece arm, point
    `pouch`): it hangs by his knee at rest and whirls over his head through the windup (the
    `whirl` rule, raiderpose.arm_channel), at its largest at the release.
  * **the lobber** (radius 1.4, head 0.7, cloth green): stocky, a green scarf over nose and mouth
    and a hide cap with ear flaps (a fire handler), a leather apron, a hide satchel of fired-clay
    firepots on his back held by crossed straps, two more pots at his belt. The lit round sits in
    the satchel's mouth (`cue` piece torso, point `pack`); his throw reaches back over his shoulder
    to it and hurls overhand (the keys blend the shortest way round, so over the top).

Each body is five rigid pieces in the body frame (raider_kit_mesh says how), the head centred on
the scored head by raider_kit.centre_head.
"""

from __future__ import annotations

import raider_kit_mesh as rk
from raider_kit_mesh import BUDGETS, ball, band, blob, jagged, lerp3, limb
from raider_kit_palette import FOREST as F
from raider_kit_palette import FOREST_HIDE as H
from raider_kit_palette import RAIDER as R

SKIN, CLOTH = rk.rpal.PAINT.SKIN, rk.rpal.PAINT.CLOTH


def face(head, hc_y: float, *, eye_y: float, eye_z: float, paint: bool = True) -> None:
    """White eyes on a charcoal band (the fodder's war paint), a nose."""
    head.skin.prism([(0.0, 0.15), (0.11, -0.06), (-0.04, -0.08)], -0.065, 0.065, SKIN,
                    origin=(0.0, hc_y - 0.1, eye_z + 0.02), u=(0.0, 0.0, -1.0), v=(0.0, 1.0, 0.0))
    if paint:
        rk.shell(head.gear, [
            (eye_y - 0.07, 0.0, 0.0, 0.535, 0.555, -1.1, 1.1),
            (eye_y + 0.09, 0.0, 0.01, 0.53, 0.55, -1.1, 1.1),
        ], R.HAIR, thickness=0.05, points=4)
    for side in (-1, 1):
        head.gear.prism([(0.0, 0.033), (0.1, 0.0), (0.0, -0.033)], -0.03, 0.03, F.BONE,
                        origin=(side * 0.14, eye_y + 0.01, eye_z), u=(side * 1.0, 0.0, 0.0), v=(0.0, 1.0, 0.0))


def legs(b: rk.Body, x: float, top: float, radii, *, foot: float = 0.42) -> None:
    """Cloth leg wraps (the leg shade), rope at the knee and the ankle, rawhide foot wraps."""
    for name, sx in (("legL", -x), ("legR", x)):
        leg = b[name]
        knee = (sx * 1.03, top * 0.52, -0.05)
        limb(leg.cloth, [(sx, top, 0.0), knee, (sx, 0.34, 0.02)], list(radii), CLOTH, segments=6)
        leg.gear.prism([(0.18, 0.0), (0.2, 0.36), (-0.08, 0.4), (-0.38, 0.15), (-foot, 0.0)], -0.16, 0.16, H.HIDE,
                       origin=(sx, 0.0, 0.0), u=(0.0, 0.0, 1.0), v=(0.0, 1.0, 0.0))
        band(leg.gear, 0.52, 0.64, sx, 0.01, radii[2] + 0.015, radii[2] + 0.015, F.ROPE, segments=5)
        band(leg.gear, knee[1] - 0.05, knee[1] + 0.05, knee[0], knee[2], radii[1] + 0.015, radii[1] + 0.015, F.ROPE,
             segments=5)


# --- the slinger -------------------------------------------------------------------------------------


def slinger() -> rk.Body:
    """5 tall, radius 1.2, head 0.65 (the scored head: a 0.65 ball centred 4.35 up)."""
    b = rk.Body("RaiderSlinger", "slinger", 5.0, 1.2, 0.65)
    hc = (0.0, 4.35, 0.0)
    b.points.update({
        "head": hc,
        "headTop": (0.0, 5.0, 0.0),
        "neck": (0.0, 3.72, 0.0),
        "shoulder": (0.74, 3.44, 0.02),
        "shoulderL": (-0.74, 3.44, 0.02),
        "hipL": (-0.3, 2.06, 0.0),
        "hipR": (0.3, 2.06, 0.0),
        "hand": (0.9, 2.2, -0.1),
        "chest": (0.0, 3.05, -0.4),
        "pouch": (0.92, 1.18, -0.12),
    })
    b.leg_length = 2.06
    b.lead_leg = "legL"

    head = b["head"]
    blob(head.skin, [
        (3.88, 0.0, -0.09, 0.26, 0.28),
        (4.07, 0.0, -0.04, 0.43, 0.45),
        (4.33, 0.0, 0.00, 0.52, 0.54),
        (4.60, 0.0, 0.02, 0.51, 0.53),
        (4.83, 0.0, 0.04, 0.39, 0.42),
    ], SKIN, segments=7, apex0=(0.0, 3.75, -0.11), apex1=(0.0, 4.98, 0.04))
    face(head, 4.35, eye_y=4.36, eye_z=-0.555)
    # The head wrap in the kind's cloth: a dome over the brow, a knot at the back and two tails.
    blob(head.cloth, [
        (4.47, 0.0, 0.04, 0.565, 0.585),
        (4.72, 0.0, 0.05, 0.53, 0.56),
        (4.93, 0.0, 0.06, 0.35, 0.39),
    ], CLOTH, segments=8, smooth=False, apex1=(0.0, 5.0, 0.06))
    ball(head.cloth, (0.0, 4.52, 0.6), (0.17, 0.15, 0.13), CLOTH, segments=5, rings=3, smooth=False)
    for side in (-1, 1):
        head.cloth.prism([(0.0, 0.07), (0.62, 0.05), (0.7, -0.02), (0.0, -0.07)], -0.025, 0.025, CLOTH,
                         origin=(side * 0.06, 4.5, 0.66), u=rk.norm((side * 0.2, -0.85, 0.35)), v=(side * 1.0, 0.0, 0.0))

    torso = b["torso"]
    blob(torso.cloth, [
        (1.68, 0.0, 0.02, 0.56, 0.42, jagged(0.09, 17)),
        (2.10, 0.0, 0.00, 0.52, 0.37),
        (2.55, 0.0, 0.00, 0.50, 0.35),
        (3.05, 0.0, -0.02, 0.60, 0.40),
        (3.48, 0.0, 0.02, 0.52, 0.31),
    ], CLOTH, segments=8)
    band(torso.skin, 3.42, 3.78, 0.0, 0.02, 0.19, 0.18, SKIN, segments=6)
    limb(torso.skin, [(-0.72, 3.44, 0.02), (-0.84, 2.88, 0.05), (-0.84, 2.36, -0.04)], [0.18, 0.15, 0.12], SKIN, segments=5)
    ball(torso.skin, (-0.84, 2.22, -0.06), (0.14, 0.15, 0.14), SKIN, segments=5, rings=3)
    band(torso.gear, 2.5, 2.7, -0.84, -0.0, 0.135, 0.135, F.LEATHER, segments=5)
    band(torso.gear, 2.26, 2.42, 0.0, 0.0, 0.535, 0.385, F.ROPE, segments=8)
    # The bag of stones on the left hip, tied to the belt, and a bandolier of small pouches.
    blob(torso.gear, [
        (1.76, -0.6, -0.04, 0.1, 0.1),
        (1.92, -0.62, -0.05, 0.22, 0.2),
        (2.16, -0.6, -0.05, 0.2, 0.18),
        (2.3, -0.58, -0.04, 0.09, 0.09),
    ], H.HIDE, segments=6, smooth=False)
    band(torso.gear, 2.24, 2.3, -0.58, -0.04, 0.1, 0.1, F.ROPE, segments=5)
    limb(torso.gear, [(0.5, 3.5, -0.28), (-0.52, 2.36, -0.4)], [(0.065, 0.03), (0.065, 0.03)], F.LEATHER,
         segments=4, smooth=False, normal0=(0.0, 0.0, 1.0))
    for k in range(3):
        at = lerp3((0.32, 3.3, -0.4), (-0.3, 2.6, -0.46), k / 2)
        ball(torso.gear, at, (0.09, 0.1, 0.06), H.HIDE_DARK, segments=5, rings=3, smooth=False)

    arm = b["arm"]
    limb(arm.skin, [(0.72, 3.44, 0.02), (0.88, 2.86, 0.02), (0.9, 2.34, -0.08)], [0.18, 0.15, 0.12], SKIN, segments=5)
    ball(arm.skin, (0.9, 2.2, -0.1), (0.14, 0.15, 0.14), SKIN, segments=5, rings=3)
    band(arm.gear, 2.42, 2.66, 0.895, -0.05, 0.14, 0.14, F.LEATHER, segments=5)
    # The sling: two sinew cords from the fist to a leather pouch (the lit orb rides in it).
    pouch = b.points["pouch"]
    for dx, dz in ((-0.07, -0.04), (0.07, 0.03)):
        limb(arm.gear, [(0.9 + dx * 0.4, 2.1, -0.1), (0.9 + dx, 1.62, -0.12 + dz), (pouch[0] + dx * 1.3, pouch[1] + 0.12, pouch[2] + dz)],
             [0.03, 0.03, 0.03], F.SINEW, segments=3, smooth=False)
    arm.gear.lathe([(-0.2, 0.0), (-0.14, 0.13), (0.0, 0.2), (0.08, 0.21)], F.LEATHER, axis=(0.0, 1.0, 0.0),
                   centre=pouch, segments=7, smooth=False, cap_colour=F.LEATHER_DARK)
    ball(arm.gear, (pouch[0], pouch[1] - 0.02, pouch[2]), (0.12, 0.11, 0.12), F.FLINT, segments=5, rings=3, smooth=False)

    legs(b, 0.3, 2.1, (0.24, 0.19, 0.16))

    # Keys (raiderpose.arm_channel): the sling is raised up and out over the right shoulder through
    # the windup (leaning back 0.45 there, so its pitch is tipped forward) and whirled twice round
    # that (`whirl`), released up, forward and out to his right (the blow leans forward 0.33 at the
    # release; rolled out 0.55 so the pouch passes beside his head, never in front of his face) and
    # follows through down across the body.
    b.arm = {
        "carry": [0.0, 0.0, 0.0],
        "seat": [1.05, 0.0, -0.08],
        "slump": [0.18, 0.0, 0.05],
        "shapes": {
            "shot": {
                "coil": [-0.35, 0.0, 2.55],
                "strike": [2.4, -0.1, 0.55],
                "follow": [0.9, 0.0, -0.25],
                "whirl": {"turns": 2, "sin": [0.45, 0.0, 0.0], "cos": [0.0, 0.0, 0.25]},
            },
        },
    }
    b.cue = {"piece": "arm", "point": "pouch"}
    b.budget = BUDGETS["slinger"]
    return b


# --- the lobber ----------------------------------------------------------------------------------------


def _firepot(m, centre, size: float, axis=(0.0, 1.0, 0.0)) -> None:
    """A fired-clay firepot: a round belly, a sooty neck and a rope-tied hide stopper."""
    ax = rk.norm(axis)
    m.lathe([(-0.5 * size, 0.0), (-0.3 * size, 0.4 * size), (0.08 * size, 0.46 * size), (0.32 * size, 0.24 * size),
             (0.46 * size, 0.2 * size), (0.52 * size, 0.23 * size), (0.66 * size, 0.1 * size), (0.7 * size, 0.0)],
            R.CLAY, axis=ax, centre=centre, segments=5, smooth=False,
            face_colour=lambda i, j: R.HAIR if i == 3 else (H.HIDE_PALE if i >= 4 else R.CLAY))


def lobber() -> rk.Body:
    """5 tall, radius 1.4, head 0.7 (the scored head: a 0.7 ball centred 4.3 up)."""
    b = rk.Body("RaiderLobber", "lobber", 5.0, 1.4, 0.7)
    hc = (0.0, 4.3, 0.0)
    b.points.update({
        "head": hc,
        "headTop": (0.0, 5.0, 0.0),
        "neck": (0.0, 3.64, 0.02),
        "shoulder": (0.86, 3.36, 0.04),
        "shoulderL": (-0.86, 3.36, 0.04),
        "hipL": (-0.36, 2.0, 0.0),
        "hipR": (0.36, 2.0, 0.0),
        "hand": (1.02, 2.12, -0.1),
        "chest": (0.0, 2.95, -0.52),
        "pack": (0.0, 3.62, 0.84),
    })
    b.leg_length = 2.0
    b.lead_leg = "legL"

    head = b["head"]
    blob(head.skin, [
        (3.80, 0.0, -0.10, 0.29, 0.31),
        (4.00, 0.0, -0.04, 0.48, 0.49),
        (4.27, 0.0, 0.00, 0.57, 0.59),
        (4.56, 0.0, 0.02, 0.56, 0.58),
        (4.80, 0.0, 0.04, 0.43, 0.46),
    ], SKIN, segments=7, apex0=(0.0, 3.68, -0.12), apex1=(0.0, 4.94, 0.04))
    face(head, 4.36, eye_y=4.38, eye_z=-0.6, paint=False)
    # The scarf over nose and mouth (the kind's cloth): a fire handler's face cover.
    rk.shell(head.cloth, [
        (3.84, 0.0, 0.0, 0.46, 0.5, -1.35, 1.35),
        (4.27, 0.0, 0.0, 0.6, 0.62, -1.45, 1.45),
    ], CLOTH, thickness=0.06, points=6)
    # The hide cap with ear flaps, soot on the brow.
    blob(head.gear, [
        (4.46, 0.0, 0.04, 0.625, 0.645),
        (4.74, 0.0, 0.05, 0.56, 0.6),
        (4.94, 0.0, 0.06, 0.36, 0.42),
    ], H.HIDE_DARK, segments=7, smooth=False, apex1=(0.0, 5.0, 0.06))
    for side in (-1, 1):
        head.gear.prism([(0.0, 0.18), (0.42, 0.13), (0.5, -0.1), (0.0, -0.16)], -0.04, 0.04, H.HIDE_DARK,
                        origin=(side * 0.6, 4.5, 0.1), u=(side * 0.08, -1.0, 0.0), v=(0.0, 0.0, 1.0))

    torso = b["torso"]
    blob(torso.cloth, [
        (1.66, 0.0, 0.02, 0.66, 0.52, jagged(0.08, 23)),
        (2.08, 0.0, 0.00, 0.64, 0.48),
        (2.55, 0.0, 0.00, 0.62, 0.46),
        (3.02, 0.0, -0.02, 0.7, 0.5),
        (3.44, 0.0, 0.02, 0.6, 0.38),
    ], CLOTH, segments=7)
    band(torso.skin, 3.38, 3.72, 0.0, 0.02, 0.22, 0.21, SKIN, segments=6)
    limb(torso.skin, [(-0.84, 3.36, 0.04), (-0.98, 2.84, 0.06), (-0.98, 2.3, -0.04)], [0.21, 0.18, 0.15], SKIN, segments=5)
    ball(torso.skin, (-0.98, 2.15, -0.06), (0.16, 0.17, 0.16), SKIN, segments=5, rings=3)
    # The leather apron, belt, crossed satchel straps.
    rk.shell(torso.gear, [
        (1.5, 0.0, 0.02, 0.7, 0.56, -0.75, 0.75),
        (2.34, 0.0, 0.0, 0.655, 0.5, -0.7, 0.7),
    ], F.LEATHER, thickness=0.05, points=4)
    band(torso.gear, 2.28, 2.46, 0.0, 0.0, 0.645, 0.495, F.LEATHER_DARK, segments=8)
    for side in (-1, 1):
        limb(torso.gear, [(side * 0.5, 3.48, -0.26), (-side * 0.56, 2.52, -0.5)],
             [(0.07, 0.03)] * 2, H.HIDE_DARK, segments=4, smooth=False, normal0=(0.0, 0.0, 1.0))
    # The satchel on the back, its mouth open at the top (the lit round sits in it), three firepots.
    blob(torso.gear, [
        (2.42, 0.0, 0.78, 0.4, 0.22),
        (2.62, 0.0, 0.8, 0.52, 0.3),
        (3.1, 0.0, 0.82, 0.54, 0.32),
        (3.42, 0.0, 0.84, 0.5, 0.3),
    ], H.HIDE, segments=7, smooth=False)
    band(torso.gear, 3.3, 3.42, 0.0, 0.84, 0.515, 0.315, F.ROPE, segments=7)
    for at, tilt in (((-0.44, 3.42, 0.84), (-0.5, 1.0, 0.1)), ((0.46, 3.4, 0.86), (0.5, 1.0, 0.15))):
        _firepot(torso.gear, at, 0.42, axis=tilt)

    arm = b["arm"]
    limb(arm.skin, [(0.84, 3.36, 0.04), (1.0, 2.84, 0.04), (1.02, 2.28, -0.08)], [0.21, 0.18, 0.15], SKIN, segments=5)
    ball(arm.skin, (1.02, 2.12, -0.1), (0.17, 0.18, 0.17), SKIN, segments=5, rings=3)
    # A heavy leather gauntlet: he handles fire.
    limb(arm.gear, [(1.0, 2.66, -0.0), (1.02, 2.18, -0.1)], [0.19, 0.21], F.LEATHER_DARK, segments=6, smooth=False)
    band(arm.gear, 2.64, 2.72, 1.0, 0.0, 0.2, 0.2, F.ROPE, segments=6)

    legs(b, 0.36, 2.04, (0.28, 0.23, 0.2), foot=0.46)

    # Keys: he reaches back over his right shoulder to the satchel (pitch -2.8, the hand up behind
    # the shoulder: the windup's lean back 0.45 tips it further back, over the lit round), hurls
    # overhand over the top (the strike's 2.35 is reached the short way round through pi) and
    # follows through forward and down across his body.
    b.arm = {
        "carry": [0.0, 0.0, 0.0],
        "seat": [0.67, 0.0, -0.08],
        "slump": [0.2, 0.0, 0.06],
        "shapes": {
            "lob": {"coil": [-2.8, 0.0, 0.0], "strike": [2.35, 0.0, 0.2], "follow": [1.15, -0.2, -0.2]},
        },
    }
    b.cue = {"piece": "torso", "point": "pack"}
    b.budget = BUDGETS["lobber"]
    return b
