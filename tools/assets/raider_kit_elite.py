"""The raider kit's plated elite (L4 W2), registered by raider_kit.py.

Runs inside Blender as part of the generator (never on its own):

    blender -b -P tools/assets/raider_kit.py -- --only RaiderArmoured --merge

**The plated elite** (crowd kind `armoured`: 6.5 tall, radius 1.7, head 0.8, cloth steel blue): a
broad raider in a steel-blue kilt and sleeves, a hair crest, war paint, fur boots and a long-hafted
flint axe swung one-handed (the arc: the arm piece turns about the right shoulder, so the sweep is a
single rotation, keyed like the Chief's).

**The plate is lashed planks** (MISSIONS_DESIGN section 26: raider gear is the kit's own): planks
over the chest and back bound by two lashings, plank pauldrons on both shoulders and a plank shield
on the left forearm. They are their own kit, `raider-plate` (role `plate`), one untextured MeshPart
in the torso stage, so the client can paint them by today's shell rule (the plate's colour while
the plate is on, a white glint when it turns a hit, the ward while a guard lives, a white burst on
the break) and hide them when it breaks, leaving the tunic, the harness and the bare left arm. They
are authored one colour (raider_kit_palette PAINT.PLATE): the planks read by their shapes and
their shading, never by paint the client would have to fight.
"""

from __future__ import annotations

import math

import raider_kit_mesh as rk
from raider_kit_mesh import BUDGETS, ball, band, blob, cross3, jagged, limb
from raider_kit_palette import FOREST as F
from raider_kit_palette import FOREST_HIDE as H
from raider_kit_palette import RAIDER as R

SKIN, CLOTH, PLATE = rk.rpal.PAINT.SKIN, rk.rpal.PAINT.CLOTH, rk.rpal.PAINT.PLATE
UP = (0.0, 1.0, 0.0)


def plank(m, bottom, outward, width: float, height: float, thickness: float, *, top: float = 0.12,
          up=UP) -> None:
    """One plank standing on `bottom`, its face toward `outward`, its top cut to a point `top` high."""
    n = rk.norm(outward)
    v = rk.norm(rk.sub(up, rk.mul(n, rk.dot(up, n))))
    u = rk.norm(cross3(v, n))  # u x v = n: the prism's depth runs outward
    hw = width / 2
    outline = ([(-hw, 0.0), (hw, 0.0), (hw, height - top), (0.0, height), (-hw, height - top)] if top > 0
               else [(-hw, 0.0), (hw, 0.0), (hw, height), (-hw, height)])
    m.prism(outline, 0.0, thickness, PLATE, origin=bottom, u=u, v=v)


def armoured() -> rk.Body:
    """6.5 tall, radius 1.7, head 0.8 (the scored head: a 0.8 ball centred 5.7 up)."""
    b = rk.Body("RaiderArmoured", "armoured", 6.5, 1.7, 0.8)
    hc = (0.0, 5.7, 0.0)
    b.points.update({
        "head": hc,
        "headTop": (0.0, 6.5, 0.0),
        "neck": (0.0, 4.95, 0.06),
        "shoulder": (1.08, 4.62, 0.06),
        "shoulderL": (-1.08, 4.62, 0.06),
        "hipL": (-0.46, 2.75, 0.04),
        "hipR": (0.46, 2.75, 0.04),
        "hand": (1.32, 2.95, -0.2),
        "handL": (-1.3, 2.98, -0.15),
        "chest": (0.0, 3.95, -0.78),
    })
    b.leg_length = 2.75
    b.lead_leg = "legL"
    b.arm_swing_share = 0.6

    # Head: the skull, a hair crest from brow to nape (outside the head sphere: a miss by design),
    # a charcoal band with white eyes, ochre stripes on the cheeks.
    head = b["head"]
    blob(head.skin, [
        (5.13, 0.0, -0.11, 0.32, 0.34),
        (5.36, 0.0, -0.05, 0.52, 0.55),
        (5.67, 0.0, 0.00, 0.64, 0.66),
        (6.00, 0.0, 0.02, 0.63, 0.65),
        (6.27, 0.0, 0.05, 0.48, 0.51),
    ], SKIN, segments=8, apex0=(0.0, 5.06, -0.14), apex1=(0.0, 6.46, 0.05))
    head.skin.prism([(0.0, 0.18), (0.13, -0.07), (-0.05, -0.1)], -0.08, 0.08, SKIN,
                    origin=(0.0, 5.6, -0.66), u=(0.0, 0.0, -1.0), v=(0.0, 1.0, 0.0))
    rk.shell(head.gear, [
        (5.66, 0.0, 0.0, 0.655, 0.675, -1.1, 1.1),
        (5.86, 0.0, 0.01, 0.65, 0.67, -1.1, 1.1),
    ], R.HAIR, thickness=0.05, points=4)
    for side in (-1, 1):
        head.gear.prism([(0.0, 0.04), (0.13, 0.0), (0.0, -0.04)], -0.03, 0.03, F.BONE,
                        origin=(side * 0.17, 5.77, -0.68), u=(side * 1.0, 0.0, 0.0), v=(0.0, 1.0, 0.0))
        for k in range(2):
            head.gear.prism([(0.0, 0.035), (0.34, 0.015), (0.34, -0.015), (0.0, -0.035)], -0.02, 0.02, F.OCHRE,
                            origin=(side * 0.34, 5.42 - 0.13 * k, -0.6 + 0.04 * k), u=rk.norm((side * 0.85, -0.15, 0.5)),
                            v=(0.0, 1.0, 0.0))
    head.gear.prism([(0.42, 0.2), (0.0, 0.72), (-0.6, 0.44), (-0.7, 0.0), (0.38, 0.06)],
                    -0.08, 0.08, R.HAIR, origin=(0.0, 6.02, 0.02), u=(0.0, 0.0, -1.0), v=(0.0, 1.0, 0.0))

    # Torso: a steel-blue tunic and kilt (the cloth), the neck, the left arm with its sleeve, a belt
    # and a harness that stays when the plate goes.
    torso = b["torso"]
    blob(torso.cloth, [
        (1.95, 0.0, 0.04, 0.96, 0.76, jagged(0.08, 37)),
        (2.6, 0.0, 0.02, 0.9, 0.68),
        (3.3, 0.0, 0.00, 0.92, 0.66),
        (4.1, 0.0, 0.00, 1.02, 0.7),
        (4.7, 0.0, 0.04, 0.95, 0.6),
        (5.0, 0.0, 0.06, 0.52, 0.4),
    ], CLOTH, segments=8)
    band(torso.skin, 4.86, 5.06, 0.0, 0.06, 0.27, 0.25, SKIN, segments=6)
    limb(torso.cloth, [(-1.08, 4.62, 0.06), (-1.26, 3.95, 0.06)], [0.3, 0.27], CLOTH, segments=6, smooth=False)
    limb(torso.skin, [(-1.24, 4.1, 0.06), (-1.3, 3.15, -0.1)], [0.24, 0.19], SKIN, segments=6)
    ball(torso.skin, b.points["handL"], (0.21, 0.22, 0.21), SKIN, segments=5, rings=3)
    band(torso.gear, 2.98, 3.16, 0.0, 0.02, 0.935, 0.675, F.LEATHER, segments=9)
    for side in (-1, 1):
        # Under the planks (between the tunic and their inner face, both measured where it runs): it shows
        # only once the plate is gone, never through the gaps between planks.
        limb(torso.gear, [(side * 0.62, 4.98, -0.1), (side * 0.48, 4.3, -0.615), (side * 0.36, 3.12, -0.645)],
             [(0.1, 0.02)] * 3, F.LEATHER_DARK, segments=4, smooth=False, normal0=(0.0, 0.0, 1.0))

    # The plate: chest and back planks, two lashings, pauldrons, the shield on the left forearm.
    rx, rz = 1.0, 0.72
    for a, h, top in ((-0.84, 1.3, 0.12), (-0.42, 1.4, 0.12), (0.0, 1.5, 0.12), (0.42, 1.4, 0.12), (0.84, 1.3, 0.12),
                      (math.pi - 0.62, 1.32, 0.0), (math.pi - 0.2, 1.4, 0.0), (math.pi + 0.2, 1.36, 0.0),
                      (math.pi + 0.62, 1.3, 0.0)):
        out = (math.sin(a), 0.0, -math.cos(a))
        at = (rx * 1.02 * out[0], 3.12, rz * 1.02 * out[2])
        plank(torso.plate, at, (out[0] / rx, 0.0, out[2] / rz), 0.42, h, 0.1, top=top)
    for y in (3.4, 4.12):
        band(torso.plate, y, y + 0.13, 0.0, 0.0, rx * 1.02 + 0.13, rz * 1.02 + 0.13, PLATE, segments=8)
    for side in (-1, 1):
        for dz in (-0.2, 0.2):
            out = rk.norm((side * 1.0, 0.75, 0.0))
            plank(torso.plate, (side * 0.86, 4.9, 0.06 + dz), out, 0.36, 0.62, 0.08, top=0.0,
                  up=rk.norm((side * 0.55, -0.85, 0.0)))
    n = rk.norm((-0.42, 0.0, -0.91))
    t = rk.norm(cross3(UP, n))
    centre = (-1.5, 2.55, -0.52)
    for k in range(4):
        off = (k - 1.5) * 0.33
        plank(torso.plate, rk.add(centre, rk.mul(t, off)), n, 0.34, 1.5 - 0.08 * abs(k - 1.5), 0.09, top=0.14)
    for y in (0.35, 1.05):
        a0 = rk.add(rk.add(centre, rk.mul(t, -0.66)), (0.0, y, 0.0))
        a1 = rk.add(rk.add(centre, rk.mul(t, 0.66)), (0.0, y, 0.0))
        torso.plate.prism([(0.0, -0.08), (rk.length(rk.sub(a1, a0)), -0.08), (rk.length(rk.sub(a1, a0)), 0.08), (0.0, 0.08)],
                          0.09, 0.16, PLATE, origin=a0, u=t, v=UP)

    # The right arm (the arm piece): sleeve, skin, a bracer, the long flint axe nearly in line with
    # the forearm (18 degrees forward of it, like the Chief's hammer: a rigid wrist can then hang it
    # at his side and sweep it wide at arm's length).
    arm = b["arm"]
    limb(arm.cloth, [(1.08, 4.62, 0.06), (1.26, 3.95, 0.06)], [0.3, 0.27], CLOTH, segments=6, smooth=False)
    limb(arm.skin, [(1.24, 4.1, 0.06), (1.32, 3.12, -0.14)], [0.24, 0.19], SKIN, segments=6)
    ball(arm.skin, b.points["hand"], (0.21, 0.22, 0.21), SKIN, segments=5, rings=3)
    band(arm.gear, 3.35, 3.62, 1.3, -0.07, 0.215, 0.215, F.LEATHER, segments=6)
    grip = b.points["hand"]
    d = rk.norm((-0.06, -0.951, -0.309))
    e = rk.norm(rk.sub((0.0, 0.0, -1.0), rk.mul(d, rk.dot((0.0, 0.0, -1.0), d))))
    arm.gear.lathe([(-0.4, 0.0), (-0.36, 0.085), (2.3, 0.075), (2.45, 0.0)], F.WOOD, axis=d, centre=grip, segments=5,
                   smooth=True)
    arm.gear.prism([(1.7, 0.04), (2.36, 0.04), (2.62, 0.62), (2.14, 0.9), (1.54, 0.58)], -0.07, 0.07, F.FLINT,
                   origin=grip, u=d, v=e, side_colour=F.FLINT_LIGHT)
    arm.gear.prism([(1.96, -0.04), (2.16, -0.04), (2.06, -0.42)], -0.04, 0.04, F.BONE, origin=grip, u=d, v=e)
    arm.gear.lathe([(1.82, 0.12), (2.28, 0.12)], F.ROPE, axis=d, centre=grip, segments=5, smooth=False)
    b.points["tip"] = rk.add(grip, rk.add(rk.mul(d, 2.14), rk.mul(e, 0.9)))

    for name, x in (("legL", -0.46), ("legR", 0.46)):
        leg = b[name]
        limb(leg.cloth, [(x, 2.9, 0.04), (x * 1.04, 1.5, -0.04), (x, 0.6, 0.04)], [0.36, 0.3, 0.26], CLOTH, segments=6)
        blob(leg.gear, [
            (0.0, x, -0.1, 0.32, 0.46),
            (0.38, x, -0.06, 0.33, 0.4),
            (0.72, x, 0.04, 0.33, 0.33, jagged(0.14, 61 if x < 0 else 62)),
        ], H.FUR, segments=6, smooth=False)
        band(leg.gear, 1.42, 1.54, x * 1.04, -0.04, 0.315, 0.315, F.ROPE, segments=6)

    # Keys like the Chief's sweep: out to the side and back through the windup, across the front
    # in the swing, through to the left in the follow.
    b.arm = {
        "carry": [0.2, 0.0, 0.0],
        "seat": [1.35, 0.0, -0.1],
        "slump": [0.35, 0.0, 0.05],
        "shapes": {
            "arc": {"coil": [0.1, -0.9, 1.45], "strike": [0.4, -0.3, 1.45], "follow": [0.3, 1.1, 1.35]},
        },
    }
    b.budget = BUDGETS["armoured"]
    return b
