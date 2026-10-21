"""The raider kit's marksman (L4 W2), registered by raider_kit.py.

Runs inside Blender as part of the generator (never on its own):

    blender -b -P tools/assets/raider_kit.py -- --only RaiderMarksman --merge

**The marksman** (5.4 tall, radius 1.2, head 0.65, cloth purple): the tallest of the 5-stud raiders
and the leanest, in a long hooded coat of the kind's cloth, a quiver of bolts slung across his
back, and a heavy crossbow held in both hands: a carved stock, a thick prod lashed on with rope, a
drawn sinew string and a flint-headed bolt. The lit tip (ThreatFx/Cues) rides the bolt's head
(`cue` piece arm, point `tip`); the warning line is ThreatFx's.

**Two-handed, so the arm piece holds both arms and may only pitch** (a yaw or a roll would tear a
shoulder off): it turns about the middle of the shoulder line, where both shoulders sit on the
axis. The piece is authored **aimed**: the crossbow level at the chin, its butt at the right
shoulder; `carry` lowers it (pitch -0.45: held across the chest, the bow pointing at the ground a
few studs ahead; lowered further, the rigid piece swings his elbows behind his back and his hands
into his coat, because it can only turn about the shoulder line). Its keys are
`steady` (raiderpose.arm_channel): world pitches, the body's lean taken off, so the aim stays level
while the windup leans him back; and a `line` arm is raised by the time its line locks.
"""

from __future__ import annotations

import raider_kit_mesh as rk
from raider_kit_mesh import BUDGETS, ball, band, blob, jagged, limb
from raider_kit_palette import FOREST as F
from raider_kit_palette import FOREST_HIDE as H
from raider_kit_throwers import face, legs

SKIN, CLOTH = rk.rpal.PAINT.SKIN, rk.rpal.PAINT.CLOTH

# The crossbow, aimed: braced against the right breast, its centre line at x 0.3, y 3.55, running
# from the butt (z -0.05) forward. Shouldered at the cheek, its lit tip (1.6 across at full charge)
# hid his face, the crit point, for the whole windup; at the chest it stays under his chin.
AXIS_X, AXIS_Y = 0.3, 3.55
BUTT_Z, FRONT_Z, PROD_Z, NUT_Z = -0.05, -1.95, -1.72, -0.95
BOLT_TIP_Z = -2.22


def _crossbow(m) -> None:
    """Stock, prod, rope lashing, drawn string, the bolt, a bone trigger."""
    # The stock: a deep butt tapering to a slim fore-stock, 0.16 wide.
    m.prism([(0.0, -0.2), (0.0, 0.12), (0.5, 0.1), (0.75, 0.04), (1.9, 0.06), (1.9, -0.08), (0.75, -0.1), (0.42, -0.24)],
            -0.08, 0.08, F.WOOD, origin=(AXIS_X, AXIS_Y, BUTT_Z), u=(0.0, 0.0, -1.0), v=(0.0, 1.0, 0.0),
            side_colour=F.WOOD_DARK)
    # The prod: two thick limbs swept back to their tips, lashed to the stock with rope.
    for side in (-1, 1):
        limb(m, [(AXIS_X, AXIS_Y + 0.02, PROD_Z), (AXIS_X + side * 0.88, AXIS_Y + 0.02, PROD_Z + 0.22)],
             [(0.065, 0.095), (0.035, 0.05)], F.WOOD_DARK, segments=4, smooth=False, normal0=(0.0, 1.0, 0.0))
        # The string, drawn back to the nut.
        limb(m, [(AXIS_X + side * 0.86, AXIS_Y + 0.02, PROD_Z + 0.22), (AXIS_X + side * 0.04, AXIS_Y + 0.07, NUT_Z)],
             [0.022, 0.022], F.SINEW, segments=3, smooth=False)
    m.lathe([(-0.09, 0.11, 0.13), (0.09, 0.11, 0.13)], F.ROPE, axis=(0.0, 0.0, 1.0), centre=(AXIS_X, AXIS_Y, PROD_Z),
            segments=6, smooth=False, ref=(1.0, 0.0, 0.0))
    # The bolt in its groove: a shaft, a knapped flint head, two fletches by the nut.
    limb(m, [(AXIS_X, AXIS_Y + 0.1, NUT_Z), (AXIS_X, AXIS_Y + 0.1, BOLT_TIP_Z + 0.2)], [0.03, 0.03], F.WOOD_LIGHT,
         segments=3, smooth=False)
    m.lathe([(0.0, 0.07), (0.2, 0.0)], F.FLINT_LIGHT, axis=(0.0, 0.0, -1.0), centre=(AXIS_X, AXIS_Y + 0.1, BOLT_TIP_Z + 0.2),
            segments=4, smooth=False)
    m.prism([(0.0, 0.0), (0.24, 0.0), (0.06, 0.12)], -0.01, 0.01, F.FEATHER,
            origin=(AXIS_X, AXIS_Y + 0.12, NUT_Z - 0.02), u=(0.0, 0.0, -1.0), v=(0.0, 1.0, 0.0))
    # A bone trigger lever under the stock.
    m.prism([(0.0, 0.0), (0.08, 0.0), (0.16, -0.27)], -0.03, 0.03, F.BONE,
            origin=(AXIS_X, AXIS_Y - 0.16, -0.62), u=(0.0, 0.0, -1.0), v=(0.0, 1.0, 0.0))


def marksman() -> rk.Body:
    """5.4 tall, radius 1.2, head 0.65 (the scored head: a 0.65 ball centred 4.75 up)."""
    b = rk.Body("RaiderMarksman", "marksman", 5.4, 1.2, 0.65)
    hc = (0.0, 4.75, 0.0)
    b.points.update({
        "head": hc,
        "headTop": (0.0, 5.4, 0.0),
        "neck": (0.0, 4.12, 0.02),
        "shoulder": (0.0, 3.82, 0.06),
        "shoulderR": (0.72, 3.82, 0.06),
        "shoulderL": (-0.72, 3.82, 0.06),
        "hipL": (-0.3, 2.3, 0.0),
        "hipR": (0.3, 2.3, 0.0),
        "hand": (0.38, 3.43, -0.5),
        "handL": (0.26, 3.35, -1.04),
        "chest": (0.0, 3.4, -0.42),
        "tip": (AXIS_X, AXIS_Y + 0.1, BOLT_TIP_Z),
    })
    b.leg_length = 2.3
    b.lead_leg = "legL"
    b.arm_swing_share = 0.25

    head = b["head"]
    blob(head.skin, [
        (4.28, 0.0, -0.09, 0.26, 0.28),
        (4.47, 0.0, -0.04, 0.43, 0.45),
        (4.73, 0.0, 0.00, 0.52, 0.54),
        (5.00, 0.0, 0.02, 0.51, 0.53),
        (5.23, 0.0, 0.04, 0.39, 0.42),
    ], SKIN, segments=7, apex0=(0.0, 4.15, -0.11), apex1=(0.0, 5.38, 0.04))
    face(head, 4.75, eye_y=4.76, eye_z=-0.555)
    # The hood: open at the face, close round the skull, peaked at the back.
    rk.shell(head.cloth, [
        (4.12, 0.0, 0.08, 0.6, 0.6, 1.0, 6.283 - 1.0),
        (4.7, 0.0, 0.04, 0.6, 0.62, 0.78, 6.283 - 0.78),
        (5.1, 0.0, 0.06, 0.5, 0.55, 0.62, 6.283 - 0.62),
    ], CLOTH, thickness=0.07, points=6)
    blob(head.cloth, [
        (5.06, 0.0, 0.06, 0.49, 0.54),
        (5.26, 0.0, 0.12, 0.34, 0.4),
    ], CLOTH, segments=7, smooth=False, apex1=(0.0, 5.42, 0.3))

    torso = b["torso"]
    blob(torso.cloth, [
        (1.45, 0.0, 0.02, 0.6, 0.48, jagged(0.08, 29)),
        (2.1, 0.0, 0.00, 0.54, 0.41),
        (2.7, 0.0, 0.00, 0.5, 0.36),
        (3.3, 0.0, -0.02, 0.58, 0.4),
        (3.8, 0.0, 0.03, 0.6, 0.37),
        (4.02, 0.0, 0.04, 0.38, 0.27),
    ], CLOTH, segments=7)
    # The hood's cowl over the shoulders.
    blob(torso.cloth, [
        (3.72, 0.0, 0.05, 0.66, 0.46),
        (3.98, 0.0, 0.06, 0.5, 0.38),
        (4.12, 0.0, 0.08, 0.36, 0.32),
    ], CLOTH, segments=6, smooth=False)
    band(torso.skin, 3.98, 4.22, 0.0, 0.02, 0.19, 0.18, SKIN, segments=6)
    band(torso.gear, 2.5, 2.66, 0.0, 0.0, 0.525, 0.385, F.LEATHER, segments=7)
    # The quiver on his back, slung from the right shoulder to the left hip, three bolts showing.
    q0, q1 = (-0.3, 2.55, 0.5), (0.22, 3.95, 0.56)
    axis = rk.sub(q1, q0)
    limb(torso.gear, [q0, q1], [0.17, 0.2], H.HIDE, segments=6, smooth=False)
    d = rk.norm(axis)
    for k, (dx, dz) in enumerate(((-0.06, 0.02), (0.06, -0.04))):
        base = rk.add(q1, (dx, 0.0, dz))
        tip = rk.add(base, rk.mul(d, 0.42 + 0.05 * k))
        limb(torso.gear, [rk.sub(base, rk.mul(d, 0.1)), tip], [0.03, 0.03], F.WOOD_LIGHT, segments=3, smooth=False)
        torso.gear.prism([(0.0, 0.0), (0.2, 0.0), (0.05, 0.08)], -0.01, 0.01, F.FEATHER,
                         origin=rk.sub(tip, rk.mul(d, 0.22)), u=d, v=(1.0, 0.0, 0.0))
    limb(torso.gear, [(0.52, 3.78, -0.3), (-0.5, 2.62, -0.42)], [(0.06, 0.03), (0.06, 0.03)], F.LEATHER,
         segments=4, smooth=False, normal0=(0.0, 0.0, 1.0))

    # Both arms and the crossbow, aimed (the piece turns about `shoulder`, the middle of the line).
    arm = b["arm"]
    for path, hand in (([(0.72, 3.82, 0.06), (0.9, 3.12, -0.16), (0.42, 3.39, -0.46)], b.points["hand"]),
                       ([(-0.72, 3.82, 0.06), (-0.62, 3.06, -0.42), (0.2, 3.31, -0.98)], b.points["handL"])):
        elbow = path[1]
        limb(arm.cloth, [path[0], elbow], [0.19, 0.16], CLOTH, segments=5, smooth=False)
        limb(arm.skin, [elbow, path[2]], [0.15, 0.12], SKIN, segments=5)
        ball(arm.skin, hand, (0.13, 0.14, 0.13), SKIN, segments=5, rings=3)
    _crossbow(arm.gear)

    legs(b, 0.3, 2.34, (0.24, 0.19, 0.16))

    # Keys, world pitches (`steady`): held low at rest, level when aimed (the coil: reached when the
    # line locks), a kick up at the shot and back to level.
    b.arm = {
        "carry": [-0.45, 0.0, 0.0],
        "seat": [-0.75, 0.0, 0.0],
        "slump": [-0.62, 0.0, 0.0],
        "shapes": {
            "line": {"coil": [0.0, 0.0, 0.0], "strike": [0.22, 0.0, 0.0], "follow": [0.05, 0.0, 0.0], "steady": True},
        },
    }
    b.cue = {"piece": "arm", "point": "tip"}
    b.budget = BUDGETS["marksman"]
    return b
