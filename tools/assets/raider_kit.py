"""The raider kit (L4): the Forest's raiders and the Camp Chief as rigid five-piece models.

Runs inside Blender (headless):

    blender -b -P tools/assets/raider_kit.py                       # every model, blueprints, config
    blender -b -P tools/assets/raider_kit.py -- --only RaiderFodder
    blender -b -P tools/assets/raider_kit.py -- --merge            # then merge_stages --props --era Raiders
    blender -b -P tools/assets/raider_kit.py -- --look-b           # the Chief's look B (front view only)

Writes, per model, one GLB per body piece per kit into assets/kenney3d/<kit>/Models/GLB format/
(raider-kit, raider-cloth, raider-skin, raider-glow: raider_kit_mesh.py says why there are four),
`<Model>.rig.json` beside the gear GLBs, the prop blueprint
tools/testfit/blueprints/_props/Raiders/<Model>.json and the kind's entry in the proposed config
tools/assets/out/RaiderModels.json. assets/ is gitignored: this script is the record.

Ben's rulings (MISSIONS_DESIGN section 26 and the L4 W1 brief): real models for all seven looks,
detailed, drawn on today's crowd bodies (the hit shapes every band was measured on: fodder 5 tall,
brute 7.5, the Chief at the Colossus's 14); one tribe of forest raiders in hide, fur, rope, bone,
flint and war paint, told apart by gear, size and cloth colour; each kind keeps its colour on its
cloth; the Chief is look A, a fur-cloaked chieftain in a skull mask carrying the L3 Warhammer
(attached at runtime, never modelled here), with look B (war paint, antler crown, log club) as one
front view. Step 1 is the prototype sheet of three: fodder, brute and the Chief.

Budgets (triangles, the whole body with its gear): fodder 600, slinger / marksman / lobber 800,
plated elite 1,000, brute 1,200, the Chief 4,000 (plus the Warhammer's 3,142).

**The head rule** shapes every head: its centre is the scored head's (feet + height - headRadius),
it fills that sphere and nothing of the body does; horns, antlers or a crest outside it are misses by
design (study report section 1). The rig keeps it there in every pose (tools/testfit/raiderpose.py).
"""

from __future__ import annotations

import argparse
import math
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "testfit"))
import raider_kit_mesh as rk  # noqa: E402
import raiderpose  # noqa: E402
from raider_kit_mesh import BUDGETS, add, ball, band, blob, cross3, fang_row, horn, jagged, lerp3, limb, shell, shell_jag, spike  # noqa: E402
from raider_kit_palette import FOREST as F  # noqa: E402
from raider_kit_palette import FOREST_HIDE as H  # noqa: E402
from raider_kit_palette import RAIDER as R  # noqa: E402

LOOK_B_ROOT = os.path.join(rk.REPO_ROOT, "assets", "build", "raider-lookb", "kenney3d")
PALETTE_CACHE = os.path.join(rk.REPO_ROOT, "assets", "build", "palettes")

# --- the fodder: a lean raider with a flint-studded club --------------------------------------------


def fodder() -> rk.Body:
    """5 tall, radius 1.3, head 0.7 (the scored head is a 0.7 ball centred 4.3 up).

    A wiry raider in a sleeveless tunic (the cloth, red-brown from config) and cloth leg wraps (the
    leg shade), rawhide belt, bandolier and foot wraps, one wolf-fur pauldron, a charcoal war-paint
    band across the eyes, a shaggy mane and a one-handed club with flint teeth in the right hand.
    L4 W2 brought him to the others' detail (the lead's note: about 800 with gear) without moving
    his silhouette Ben approved: a short fur cape over the back, a fang necklace, a bone knife in a
    sheath on the left hip, a second feather, a rope-bound grip and two more flint teeth on the club,
    a forearm wrap, rope at the knees."""
    b = rk.Body("RaiderFodder", "fodder", 5.0, 1.3, 0.7)
    hc = (0.0, 4.3, 0.0)
    b.points.update({
        "head": hc,
        "headTop": (0.0, 5.0, 0.0),
        "neck": (0.0, 3.66, 0.0),
        "shoulder": (0.8, 3.38, 0.02),
        "shoulderL": (-0.8, 3.38, 0.02),
        "hipL": (-0.32, 2.02, 0.0),
        "hipR": (0.32, 2.02, 0.0),
        "hand": (0.94, 2.16, -0.12),
        "chest": (0.0, 3.0, -0.44),
    })
    b.leg_length = 2.02
    b.lead_leg = "legL"

    # Head: skin skull with a jaw, a nose; gear: a mane, a charcoal band, white eyes.
    head = b["head"]
    blob(head.skin, [
        (3.80, 0.0, -0.10, 0.28, 0.30),
        (4.00, 0.0, -0.04, 0.46, 0.48),
        (4.27, 0.0, 0.00, 0.56, 0.58),
        (4.56, 0.0, 0.02, 0.55, 0.57),
        (4.80, 0.0, 0.04, 0.42, 0.45),
    ], rk.rpal.PAINT.SKIN, segments=7, apex0=(0.0, 3.68, -0.12), apex1=(0.0, 4.94, 0.04))
    head.skin.prism([(0.0, 0.16), (0.12, -0.06), (-0.04, -0.08)], -0.07, 0.07, rk.rpal.PAINT.SKIN,
                    origin=(0.0, 4.22, -0.56), u=(0.0, 0.0, -1.0), v=(0.0, 1.0, 0.0))
    blob(head.gear, [
        (4.50, 0.0, 0.07, 0.62, 0.64),
        (4.80, 0.0, 0.09, 0.52, 0.56),
    ], R.HAIR, segments=7, smooth=False, apex1=(0.0, 5.0, 0.10))
    blob(head.gear, [
        (3.62, 0.0, 0.40, 0.26, 0.16),
        (4.05, 0.0, 0.42, 0.44, 0.24),
        (4.52, 0.0, 0.30, 0.52, 0.32),
    ], R.HAIR, segments=5, smooth=False, apex0=(0.0, 3.5, 0.42))
    shell(head.gear, [
        (4.28, 0.0, 0.0, 0.575, 0.595, -1.15, 1.15),
        (4.44, 0.0, 0.01, 0.57, 0.59, -1.15, 1.15),
    ], R.HAIR, thickness=0.05, points=4)
    # One ochre-dyed feather stuck in the mane, leaning back: the raider's mark at a distance.
    head.gear.prism([(0.0, -0.05), (0.62, -0.07), (0.72, 0.0), (0.0, 0.05)], -0.015, 0.015, F.OCHRE,
                    origin=(-0.34, 4.62, 0.36), u=rk.norm((-0.35, 0.75, 0.55)), v=rk.norm((0.0, -0.6, 0.8)))
    head.gear.prism([(0.0, -0.04), (0.46, -0.05), (0.54, 0.0), (0.0, 0.04)], -0.015, 0.015, F.FEATHER,
                    origin=(-0.3, 4.58, 0.4), u=rk.norm((-0.6, 0.55, 0.6)), v=rk.norm((0.0, -0.6, 0.8)))
    for side in (-1, 1):
        head.gear.prism([(0.0, 0.035), (0.11, 0.0), (0.0, -0.035)], -0.03, 0.03, F.BONE,
                        origin=(side * 0.2 - 0.05 * side, 4.36, -0.6), u=(side * 1.0, 0.0, 0.0), v=(0.0, 1.0, 0.0))

    # Torso: the tunic is the cloth; skin neck and the off (left) arm; gear belt, bandolier, pauldron.
    torso = b["torso"]
    blob(torso.cloth, [
        (1.62, 0.0, 0.02, 0.60, 0.46, jagged(0.09, 13)),
        (2.10, 0.0, 0.00, 0.56, 0.40),
        (2.55, 0.0, 0.00, 0.53, 0.38),
        (3.05, 0.0, -0.02, 0.66, 0.44),
        (3.46, 0.0, 0.02, 0.56, 0.34),
    ], rk.rpal.PAINT.CLOTH, segments=7)
    band(torso.skin, 3.40, 3.76, 0.0, 0.02, 0.2, 0.19, rk.rpal.PAINT.SKIN, segments=6)
    limb(torso.skin, [(-0.76, 3.40, 0.02), (-0.88, 2.86, 0.04), (-0.86, 2.36, -0.06)], [0.19, 0.16, 0.13],
         rk.rpal.PAINT.SKIN, segments=5)
    ball(torso.skin, (-0.86, 2.22, -0.08), (0.15, 0.16, 0.15), rk.rpal.PAINT.SKIN, segments=5, rings=3)
    band(torso.gear, 2.28, 2.46, 0.0, 0.0, 0.575, 0.415, H.HIDE, segments=7)
    limb(torso.gear, [(-0.52, 3.5, -0.3), (0.52, 2.36, -0.42)], [(0.07, 0.03), (0.07, 0.03)], H.HIDE,
         segments=4, smooth=False, normal0=(0.0, 0.0, 1.0))
    ball(torso.gear, (-0.64, 3.44, 0.02), (0.38, 0.24, 0.42), H.FUR, segments=6, rings=3, jitter=0.2, seed=7, smooth=False)
    # A short fur cape over the back, ragged at the hem.
    shell(torso.gear, [
        (2.62, 0.0, 0.1, 0.6, 0.5, 2.0, 2 * math.pi - 2.0),
        (3.42, 0.0, 0.08, 0.66, 0.46, 1.75, 2 * math.pi - 1.75),
    ], H.FUR, thickness=0.08, points=6, jag=shell_jag(0.1, 9), cap_colour=H.HIDE_PALE)
    # A fang necklace on a cord.
    band(torso.gear, 3.48, 3.54, 0.0, 0.02, 0.27, 0.25, F.ROPE, segments=6)
    fang_row(torso.gear, (0.0, 3.5, 0.02), 0.28, 0.27, -0.75, 0.75, 4, 0.2, 0.045, F.BONE)
    # A bone knife in a leather sheath on the left hip.
    knife = rk.norm((0.15, -1.0, -0.25))
    limb(torso.gear, [(-0.6, 2.42, -0.22), add((-0.6, 2.42, -0.22), rk.mul(knife, 0.6))], [(0.08, 0.04), (0.05, 0.03)],
         F.LEATHER, segments=4, smooth=False, normal0=(1.0, 0.0, 0.0))
    limb(torso.gear, [(-0.6, 2.42, -0.22), add((-0.6, 2.42, -0.22), rk.mul(knife, -0.28))], [0.045, 0.05], F.BONE,
         segments=4, smooth=False)
    # A rawhide wrap on the left forearm.
    band(torso.gear, 2.44, 2.66, -0.875, -0.01, 0.15, 0.15, H.HIDE, segments=5)

    # Weapon arm: skin arm and fist, rawhide bracer, the club with flint teeth.
    arm = b["arm"]
    limb(arm.skin, [(0.76, 3.40, 0.02), (0.92, 2.86, 0.02), (0.94, 2.32, -0.08)], [0.19, 0.16, 0.13],
         rk.rpal.PAINT.SKIN, segments=5)
    ball(arm.skin, (0.94, 2.16, -0.12), (0.15, 0.16, 0.15), rk.rpal.PAINT.SKIN, segments=5, rings=3)
    band(arm.gear, 2.4, 2.66, 0.935, -0.05, 0.155, 0.155, H.HIDE, segments=5)
    grip = b.points["hand"]
    d = rk.norm((0.0, -0.34, -1.0))
    arm.gear.lathe([(-0.14, 0.0), (-0.1, 0.075), (0.9, 0.12), (1.34, 0.18), (1.56, 0.0)],
                   F.WOOD, axis=d, centre=grip, segments=5, smooth=True)
    b.points["tip"] = add(grip, rk.mul(d, 1.56))
    arm.gear.lathe([(0.1, 0.105), (0.42, 0.11)], F.ROPE, axis=d, centre=grip, segments=5, smooth=False)
    for k, (along, ang) in enumerate(((1.12, 0.0), (1.3, math.pi * 0.66), (1.22, math.pi * 1.33),
                                      (1.42, math.pi * 0.33), (1.0, math.pi))):
        u, v = rk.basis(d, (1.0, 0.0, 0.0))
        out = add(rk.mul(u, math.cos(ang)), rk.mul(v, math.sin(ang)))
        base = add(grip, rk.mul(d, along))
        spike(arm.gear, add(base, rk.mul(out, 0.12)), add(base, rk.mul(out, 0.34)), 0.055, F.FLINT_LIGHT, segments=3)

    # Legs: cloth wraps (the leg shade) and rawhide foot wraps.
    for name, x in (("legL", -0.32), ("legR", 0.32)):
        leg = b[name]
        limb(leg.cloth, [(x, 2.08, 0.0), (x * 1.03, 1.08, -0.05), (x, 0.34, 0.02)], [0.25, 0.2, 0.17],
             rk.rpal.PAINT.CLOTH, segments=6)
        leg.gear.prism([(0.18, 0.0), (0.2, 0.36), (-0.08, 0.4), (-0.38, 0.15), (-0.44, 0.0)], -0.16, 0.16, H.HIDE,
                       origin=(x, 0.0, 0.0), u=(0.0, 0.0, 1.0), v=(0.0, 1.0, 0.0))
        band(leg.gear, 0.52, 0.64, x, 0.01, 0.185, 0.185, F.ROPE, segments=5)
        band(leg.gear, 1.03, 1.13, x * 1.03, -0.05, 0.215, 0.215, F.ROPE, segments=5)

    # The weapon arm's keyed poses (pitch, yaw, roll about the shoulder, in the torso's frame;
    # raiderpose.arm_channel blends them). The torso leans about the neck, which swings a hanging arm
    # the other way, so a key is the pitch wanted in the world plus the lean of its moment: the
    # lunge's coil ends leaning back 0.45, its blow lands leaning forward 0.5. The L4 W2 fix round (K1):
    # the strike's pitch 0.85 -> 1.1 brings the club up toward level at the blow; with the strike
    # window's slide (rig.slideShare) it reaches 3.86 at the impact, past the placeholder's 3.44.
    b.arm = {
        "carry": [0.0, 0.0, 0.0],
        "seat": [0.67, 0.0, -0.08],
        "slump": [0.18, 0.0, 0.05],
        "shapes": {
            "lunge": {"coil": [1.85, 0.25, 0.25], "strike": [1.1, -0.15, -0.1], "follow": [0.1, -0.1, 0.0]},
        },
    }
    b.budget = BUDGETS["fodder"]
    return b


# --- the brute: a hulking raider with a log club ------------------------------------------------------


def brute() -> rk.Body:
    """7.5 tall, radius 2.2, head 0.9 (the scored head: a 0.9 ball centred 6.6 up).

    Hunched and wide: a bare barrel chest (skin), a rust kilt with a ragged hem and rust leg wraps
    (the cloth), a cloth sash; a wolf-fur mantle over the shoulders and back, a rawhide belt with a
    bone skull buckle, a fang necklace, fur boots; an aurochs-skull cap with two horns (outside the
    head sphere: misses by design, as the study says), a black beard; both arms hold a log club with
    rope lashings and bone spikes, the arms piece turning about the middle of the shoulder line."""
    b = rk.Body("RaiderBrute", "brute", 7.5, 2.2, 0.9)
    skin, cloth = rk.rpal.PAINT.SKIN, rk.rpal.PAINT.CLOTH
    b.points.update({
        "head": (0.0, 6.6, 0.0),
        "headTop": (0.0, 7.5, 0.0),
        "neck": (0.0, 5.72, 0.12),
        "shoulder": (0.0, 5.25, 0.15),
        "shoulderR": (1.5, 5.25, 0.15),
        "shoulderL": (-1.5, 5.25, 0.15),
        "hipL": (-0.66, 3.05, 0.12),
        "hipR": (0.66, 3.05, 0.12),
        "hand": (0.62, 3.95, -0.95),
        "handL": (0.32, 3.7, -1.72),
        "chest": (0.0, 4.75, -0.95),
    })
    b.leg_length = 3.05
    b.arm_swing_share = 0.35

    head = b["head"]
    blob(head.skin, [
        (5.80, 0.0, -0.16, 0.40, 0.40),
        (6.05, 0.0, -0.12, 0.62, 0.64),
        (6.45, 0.0, -0.03, 0.72, 0.74),
        (6.85, 0.0, 0.02, 0.70, 0.72),
        (7.12, 0.0, 0.04, 0.56, 0.60),
    ], skin, segments=8, apex0=(0.0, 5.72, -0.2), apex1=(0.0, 7.32, 0.04))
    head.skin.prism([(0.0, 0.22), (0.2, -0.08), (-0.04, -0.12)], -0.12, 0.12, skin,
                    origin=(0.0, 6.5, -0.72), u=(0.0, 0.0, -1.0), v=(0.0, 1.0, 0.0))
    # The aurochs-skull cap: a bone dome down to the brow, horns curving out and forward.
    blob(head.gear, [
        (6.72, 0.0, 0.0, 0.78, 0.80),
        (7.05, 0.0, 0.02, 0.70, 0.73),
        (7.30, 0.0, 0.03, 0.48, 0.52),
    ], F.BONE, segments=8, smooth=True, apex1=(0.0, 7.46, 0.03))
    head.gear.prism([(0.0, 0.18), (0.42, 0.06), (0.42, -0.06), (0.0, -0.14)], -0.22, 0.22, F.BONE_SHADE,
                    origin=(0.0, 6.88, -0.66), u=(0.0, 0.0, -1.0), v=(0.0, 1.0, 0.0))
    for side in (-1, 1):
        horn(head.gear, [(side * 0.62, 7.0, 0.02), (side * 1.05, 7.12, -0.06), (side * 1.38, 7.42, -0.3),
                         (side * 1.5, 7.82, -0.58), (side * 1.42, 8.12, -0.78)], 0.19, F.BONE_SHADE, F.BONE, segments=5)
        head.gear.prism([(0.0, 0.05), (0.16, 0.0), (0.0, -0.05)], -0.03, 0.03, R.EYE,
                        origin=(side * 0.24 - 0.08 * side, 6.62, -0.71), u=(side * 1.0, 0.0, 0.0), v=(0.0, 1.0, 0.0))
        head.gear.prism([(0.0, 0.06), (0.3, 0.02), (0.3, -0.02), (0.0, -0.06)], -0.02, 0.02, F.OCHRE,
                        origin=(side * 0.3, 6.32, -0.68), u=rk.norm((side * 0.9, -0.25, 0.3)), v=(0.0, 1.0, 0.0))
    blob(head.gear, [
        (5.55, 0.0, -0.52, 0.22, 0.16),
        (5.86, 0.0, -0.58, 0.46, 0.26),
        (6.2, 0.0, -0.56, 0.6, 0.3),
    ], R.HAIR, segments=6, smooth=False, apex0=(0.0, 5.4, -0.5))

    torso = b["torso"]
    blob(torso.skin, [
        (3.40, 0.0, 0.10, 1.05, 0.80),
        (4.10, 0.0, -0.05, 1.25, 0.95),
        (4.80, 0.0, 0.05, 1.45, 0.95),
        (5.35, 0.0, 0.18, 1.48, 0.86),
        (5.80, 0.0, 0.22, 0.92, 0.62),
    ], skin, segments=9)
    blob(torso.cloth, [
        (2.25, 0.0, 0.10, 1.30, 1.04, jagged(0.08, 11)),
        (2.95, 0.0, 0.10, 1.14, 0.90),
        (3.72, 0.0, 0.08, 1.08, 0.84),
    ], cloth, segments=10)
    torso.cloth.sweep([(-1.25, 5.3, -0.25), (0.0, 4.55, -1.0), (0.95, 3.75, -0.82)], [(0.07, 0.24)] * 3, cloth,
                      segments=6, normal0=(0.0, 0.0, -1.0))
    band(torso.gear, 3.55, 3.85, 0.0, 0.08, 1.11, 0.87, H.HIDE, segments=10)
    ball(torso.gear, (0.0, 3.7, -0.9), (0.26, 0.24, 0.12), F.BONE, segments=5, rings=3)
    shell(torso.gear, [
        (4.5, 0.0, 0.32, 1.60, 1.10, 0.75, 2 * math.pi - 0.75),
        (5.25, 0.0, 0.24, 1.66, 1.04, 0.55, 2 * math.pi - 0.55),
        (5.78, 0.0, 0.2, 1.04, 0.72, 0.5, 2 * math.pi - 0.5),
    ], H.FUR, thickness=0.18, points=9, jag=shell_jag(0.12, 5), cap_colour=H.HIDE_PALE)
    fang_row(torso.gear, (0.0, 5.5, 0.14), 1.02, 0.96, -0.8, 0.8, 4, 0.3, 0.07, F.BONE)

    arm = b["arm"]
    for path, hand in (([(1.5, 5.25, 0.15), (1.62, 4.45, -0.25), (0.82, 4.02, -0.82)], b.points["hand"]),
                       ([(-1.5, 5.25, 0.15), (-1.15, 4.3, -0.82), (0.12, 3.78, -1.58)], b.points["handL"])):
        limb(arm.skin, path, [0.44, 0.38, 0.3], skin, segments=7)
        ball(arm.skin, hand, (0.3, 0.28, 0.3), skin, segments=6, rings=3)
        mid = lerp3(path[1], path[2], 0.45)
        fore = rk.norm(rk.sub(path[2], path[1]))
        u, v = rk.basis(fore, (1.0, 0.0, 0.0))
        band_ring = [[add(add(mid, rk.mul(fore, t)), add(rk.mul(u, 0.4 * math.cos(2 * math.pi * k / 8)),
                                                         rk.mul(v, 0.4 * math.sin(2 * math.pi * k / 8)))) for k in range(8)]
                     for t in (-0.25, 0.25)]
        rk._open_grid_along(arm.gear, band_ring, H.HIDE, mid)
    grip = b.points["hand"]
    d = rk.norm(rk.sub(b.points["handL"], grip))
    arm.gear.lathe([(-0.55, 0.0), (-0.5, 0.2), (0.6, 0.22), (1.8, 0.34), (2.9, 0.42), (3.25, 0.36), (3.35, 0.0)],
                   F.WOOD, axis=d, centre=grip, segments=7, smooth=True,
                   face_colour=lambda i, j: F.WOOD_DARK if (i in (3, 4) and j % 2 == 0) else F.WOOD)
    b.points["tip"] = add(grip, rk.mul(d, 3.35))
    for along in (1.25, 2.05):
        arm.gear.lathe([(-0.07, 0.0), (-0.06, 0.36 + along * 0.05), (0.06, 0.36 + along * 0.05), (0.07, 0.0)],
                       F.ROPE, axis=d, centre=add(grip, rk.mul(d, along)), segments=6, smooth=False)
    u, v = rk.basis(d, (0.0, 1.0, 0.0))
    for k in range(4):
        ang = k * 2 * math.pi / 4 + 0.4
        out = add(rk.mul(u, math.cos(ang)), rk.mul(v, math.sin(ang)))
        base = add(grip, rk.mul(d, 2.6 + 0.2 * (k % 2)))
        spike(arm.gear, add(base, rk.mul(out, 0.3)), add(base, rk.mul(out, 0.72)), 0.09, F.BONE, segments=4)

    for name, x in (("legL", -0.66), ("legR", 0.66)):
        leg = b[name]
        limb(leg.cloth, [(x, 3.2, 0.12), (x * 1.04, 1.7, -0.04), (x, 0.7, 0.06)], [0.56, 0.46, 0.4], cloth, segments=7)
        blob(leg.gear, [
            (0.0, x, -0.12, 0.44, 0.6),
            (0.42, x, -0.08, 0.47, 0.56),
            (0.82, x, 0.04, 0.47, 0.47, jagged(0.14, 3 if x < 0 else 4)),
        ], H.FUR, segments=7, smooth=False)
        band(leg.gear, 0.5, 0.62, x, -0.06, 0.5, 0.58, F.ROPE, segments=7)

    b.arm = {
        "carry": [0.0, 0.0, 0.0],
        "seat": [0.35, 0.0, 0.0],
        "slump": [-0.3, 0.0, 0.0],
        "shapes": {
            "lane": {"coil": [1.0, 0.0, 0.0], "strike": [0.62, 0.0, 0.0], "follow": [0.4, 0.0, 0.0]},
        },
    }
    b.budget = BUDGETS["brute"]
    return b


# --- the Camp Chief: look A (skull mask, fur cloak, the Warhammer) and look B (antlers, war paint, log club)


WARHAMMER_SCALE = 14.0 / 5.0  # the Chief's height over a player's: the hammer in proportion
WARHAMMER_TIP = 3.704  # Warhammer.frame.json `tip` (studs along -Z at scale 1): the weapon kit's number


def chief(look: str = "A") -> rk.Body:
    """14 tall, radius 4, head 1.6 (the Colossus's body: the scored head is a 1.6 ball centred 12.4 up).

    Look A: a fur-cloaked chieftain in a bear-skull mask whose eye sockets glow (raider-glow: hot
    through every windup, ember once enraged), a wolf-pelt hood with ears, a bare war-painted chest
    (the skin) with a fang necklace and a bone-and-rope amulet ring where the client keeps the boss's
    charging core, a wine kilt and sash (the cloth), fur boots; the L3 Warhammer in his right hand,
    attached at runtime from the weapon kit at x2.8 (the `hold` record), never modelled here. He is
    one-handed on purpose: the arm piece then turns about the right shoulder, so the slam, the call,
    the charge and a wide sweep are single rotations (two arms in one rigid piece can only pitch).
    Look B (one front view for Ben's choice, never merged): the same body with war paint on a bare
    face, an antler crown, a lighter fur cloak and a log club in place of the hammer."""
    name = "RaiderChief" if look == "A" else "RaiderChiefB"
    b = rk.Body(name, "chief", 14.0, 4.0, 1.6)
    skin, cloth = rk.rpal.PAINT.SKIN, rk.rpal.PAINT.CLOTH
    b.points.update({
        "head": (0.0, 12.4, 0.0),
        "headTop": (0.0, 14.0, 0.0),
        "neck": (0.0, 10.75, 0.2),
        "shoulder": (2.95, 10.0, 0.25),
        "shoulderL": (-2.95, 10.0, 0.25),
        "hipL": (-1.25, 5.7, 0.2),
        "hipR": (1.25, 5.7, 0.2),
        "hand": (3.45, 6.45, -0.8),
        "handL": (-2.9, 6.5, -0.6),
        "core": (0.0, 7.75, -1.92),
        "chest": (0.0, 9.0, -1.75),
    })
    b.leg_length = 5.7
    # L4 W2: no walk swing on the hammer arm, and the carry lifted (0.48 -> 0.62): the dragged
    # hammer swinging with the stride sank its head up to 2.9 studs into the ground on the
    # backswing; now it rests 0.4 above the ground and dips at most about 0.65 into it mid-stride.
    b.arm_swing_share = 0.0
    cloak = H.FUR_DARK if look == "A" else H.FUR

    head = b["head"]
    blob(head.skin, [
        (10.95, 0.0, -0.18, 0.78, 0.80),
        (11.40, 0.0, -0.12, 1.14, 1.20),
        (12.20, 0.0, -0.02, 1.30, 1.35),
        (13.00, 0.0, 0.04, 1.22, 1.28),
        (13.50, 0.0, 0.06, 0.86, 0.92),
    ], skin, segments=14, apex0=(0.0, 10.82, -0.24), apex1=(0.0, 13.76, 0.06))
    blob(head.gear, [
        (10.55, 0.0, -1.0, 0.45, 0.28),
        (10.95, 0.0, -1.12, 0.92, 0.46),
        (11.45, 0.0, -1.0, 1.08, 0.5),
    ], R.HAIR, segments=10, smooth=False, apex0=(0.0, 10.2, -1.0))
    if look == "A":
        # The bear-skull mask: a bone face plate, a snout, fangs on the upper jaw, sockets that glow.
        shell(head.gear, [
            (11.55, 0.0, 0.0, 1.42, 1.48, -1.25, 1.25),
            (12.40, 0.0, 0.0, 1.48, 1.52, -1.3, 1.3),
            (13.25, 0.0, 0.02, 1.32, 1.38, -1.2, 1.2),
        ], F.BONE, thickness=0.16, points=11, smooth=True, cap_colour=F.BONE_SHADE)
        head.gear.lathe([(0.0, 0.62, 0.5), (0.35, 0.6, 0.46), (0.7, 0.42, 0.34), (0.86, 0.0, 0.0)], F.BONE,
                        axis=(0.0, -0.18, -1.0), centre=(0.0, 12.05, -1.32), segments=10, smooth=True,
                        ref=(1.0, 0.0, 0.0), cap_colour=F.BONE_SHADE)
        ball(head.gear, (0.0, 12.1, -2.0), (0.22, 0.14, 0.12), R.EYE, segments=6, rings=3)
        fang_row(head.gear, (0.0, 11.62, -0.02), 1.45, 1.5, -0.75, 0.75, 6, 0.42, 0.09, F.BONE)
        head.gear.prism([(0.0, 0.1), (0.9, 0.0), (0.0, -0.1)], -0.04, 0.04, F.BONE_SHADE,
                        origin=(0.0, 13.05, -1.38), u=(0.0, 1.0, -0.3), v=(1.0, 0.0, 0.0))
        for side in (-1, 1):
            blob(head.glow, [
                (12.42, side * 0.5, -1.47, 0.3, 0.12),
                (12.62, side * 0.5, -1.5, 0.32, 0.12),
                (12.78, side * 0.5, -1.48, 0.2, 0.1),
            ], rk.rpal.PAINT.GLOW, segments=8, smooth=False)
        # The wolf-pelt hood: sides and back as a fur sheet, a full crown, the wolf's ears.
        shell(head.gear, [
            (10.85, 0.0, 0.5, 1.5, 1.32, 0.95, 2 * math.pi - 0.95),
            (12.2, 0.0, 0.12, 1.56, 1.56, 1.2, 2 * math.pi - 1.2),
            (13.25, 0.0, 0.08, 1.42, 1.44, 1.05, 2 * math.pi - 1.05),
        ], cloak, thickness=0.2, points=11, jag=shell_jag(0.1, 21), cap_colour=H.FUR)
        blob(head.gear, [
            (13.15, 0.0, 0.06, 1.46, 1.5),
            (13.6, 0.0, 0.08, 1.12, 1.2),
            (13.88, 0.0, 0.1, 0.62, 0.7),
        ], cloak, segments=12, smooth=False, apex1=(0.0, 14.0, 0.1))
        for side in (-1, 1):
            spike(head.gear, (side * 0.72, 13.55, 0.15), (side * 1.02, 14.55, 0.1), 0.3, cloak, segments=4)
            spike(head.gear, (side * 0.74, 13.6, 0.05), (side * 0.98, 14.38, 0.0), 0.16, H.HIDE_PALE, segments=4)
            head.gear.prism([(0.0, 0.07), (0.9, 0.0), (0.0, -0.07)], -0.03, 0.03, F.FEATHER,
                            origin=(side * 1.5, 12.0, 0.4), u=rk.norm((side * 0.25, -0.95, 0.2)), v=(0.0, 0.0, 1.0))
    else:
        # Look B: a bare face in war paint, eyes, a brow band of rope and an antler crown.
        head.skin.prism([(0.0, 0.36), (0.34, -0.12), (-0.06, -0.2)], -0.2, 0.2, skin,
                        origin=(0.0, 12.25, -1.3), u=(0.0, 0.0, -1.0), v=(0.0, 1.0, 0.0))
        shell(head.gear, [
            (12.38, 0.0, 0.0, 1.32, 1.37, -1.0, 1.0),
            (12.78, 0.0, 0.01, 1.29, 1.34, -1.0, 1.0),
        ], R.HAIR, thickness=0.08, points=7)
        for side in (-1, 1):
            head.gear.prism([(0.0, 0.07), (0.3, 0.0), (0.0, -0.07)], -0.04, 0.04, F.BONE,
                            origin=(side * 0.34, 12.58, -1.36), u=(side * 1.0, 0.0, 0.0), v=(0.0, 1.0, 0.0))
            for k in range(3):
                head.gear.prism([(0.0, 0.05), (0.75, 0.02), (0.75, -0.02), (0.0, -0.05)], -0.03, 0.03, F.OCHRE,
                                origin=(side * (0.55 + 0.05 * k), 12.0 - 0.22 * k, -1.18 + 0.1 * k),
                                u=rk.norm((side * 0.75, -0.1, 0.65)), v=(0.0, 1.0, 0.0))
        band(head.gear, 13.0, 13.3, 0.0, 0.03, 1.27, 1.33, F.ROPE, segments=14)
        blob(head.gear, [(13.25, 0.0, 0.06, 1.22, 1.28), (13.6, 0.0, 0.08, 0.95, 1.0)], R.HAIR, segments=12,
             smooth=False, apex1=(0.0, 13.92, 0.08))
        for side in (-1, 1):
            beam = [(side * 0.9, 13.2, 0.1), (side * 1.6, 13.9, 0.05), (side * 2.2, 14.9, -0.1), (side * 2.4, 16.1, -0.15),
                    (side * 2.25, 17.2, -0.2)]
            horn(head.gear, beam, 0.22, F.BONE_SHADE, F.BONE, segments=6)
            for base_i, tip in ((1, (side * 2.6, 15.0, -0.75)), (2, (side * 3.25, 15.9, -0.4)), (3, (side * 1.7, 17.0, -0.5))):
                horn(head.gear, [beam[base_i], lerp3(beam[base_i], tip, 0.55), tip], 0.12, F.BONE_SHADE, F.BONE, segments=5)

    torso = b["torso"]
    blob(torso.skin, [
        (6.55, 0.0, 0.20, 1.95, 1.45),
        (7.60, 0.0, 0.00, 2.25, 1.65),
        (8.90, 0.0, 0.05, 2.60, 1.70),
        (9.90, 0.0, 0.25, 2.72, 1.55),
        (10.75, 0.0, 0.30, 1.62, 1.08),
    ], skin, segments=16)
    # War paint across the chest: ochre bands a little proud of the skin.
    for k, (y, rx, rz) in enumerate(((9.35, 2.665, 1.66), (8.95, 2.62, 1.725), (8.55, 2.53, 1.73))):
        for a0, a1 in ((-0.9 + 0.1 * k, -0.25), (0.25, 0.9 - 0.1 * k)):
            shell(torso.gear, [(y - 0.1, 0.0, 0.07, rx, rz, a0, a1), (y + 0.1, 0.0, 0.07, rx, rz, a0, a1)],
                  F.OCHRE, thickness=0.05, points=4)
    blob(torso.cloth, [
        (4.30, 0.0, 0.20, 2.22, 1.72, jagged(0.07, 31)),
        (5.40, 0.0, 0.20, 2.04, 1.55),
        (6.95, 0.0, 0.14, 2.0, 1.52),
    ], cloth, segments=18)
    torso.cloth.sweep([(2.3, 10.15, -0.5), (0.4, 8.7, -1.7), (-1.9, 6.85, -1.22)], [(0.12, 0.5)] * 3, cloth,
                      segments=6, normal0=(0.0, 0.0, -1.0))
    band(torso.gear, 6.75, 7.25, 0.0, 0.14, 2.06, 1.58, F.LEATHER, segments=16)
    ball(torso.gear, (0.0, 7.0, -1.55), (0.5, 0.45, 0.22), F.BONE, segments=8, rings=4)
    for side in (-1, 1):
        ball(torso.gear, (side * 0.18, 7.08, -1.74), (0.1, 0.1, 0.06), R.EYE, segments=5, rings=3)
    # The amulet ring the client's charging core sits in (points.core).
    torso.gear.loop(b.points["core"], (0.0, 0.0, -1.0), 1.28, 1.28, (0.16, 0.12), F.ROPE, segments=16, tube_segments=5)
    for k in range(4):
        ang = k * math.pi / 2 + math.pi / 4
        at = add(b.points["core"], (1.32 * math.cos(ang), 1.32 * math.sin(ang), -0.04))
        ball(torso.gear, at, (0.18, 0.18, 0.14), F.BONE, segments=5, rings=3)
    fang_row(torso.gear, (0.0, 10.25, 0.28), 1.75, 1.32, -1.0, 1.0, 9, 0.55, 0.11, F.BONE)
    # The fur cloak: over the shoulders and down the back to the knees, a lighter fringe at the hem.
    shell(torso.gear, [
        (3.30, 0.0, 1.55, 2.55, 1.40, 1.15, 2 * math.pi - 1.15),
        (6.00, 0.0, 1.20, 2.55, 1.60, 1.05, 2 * math.pi - 1.05),
        (8.50, 0.0, 0.85, 2.85, 1.86, 0.95, 2 * math.pi - 0.95),
        (10.05, 0.0, 0.30, 3.15, 1.92, 0.7, 2 * math.pi - 0.7),
        (10.95, 0.0, 0.32, 1.92, 1.30, 0.55, 2 * math.pi - 0.55),
    ], cloak, thickness=0.26, points=17, jag=shell_jag(0.11, 41), cap_colour=H.HIDE_PALE)
    shell(torso.gear, [
        (9.55, 0.0, 0.28, 3.25, 2.02, 0.62, 2 * math.pi - 0.62),
        (10.15, 0.0, 0.3, 3.25, 2.0, 0.6, 2 * math.pi - 0.6),
    ], H.HIDE_PALE, thickness=0.2, points=17, jag=shell_jag(0.1, 43))
    for side in (-1, 1):
        ball(torso.gear, (side * 2.85, 10.75, 0.3), (0.55, 0.5, 0.55), F.BONE, segments=8, rings=4)
        for e in (-1, 1):
            ball(torso.gear, (side * 2.85 + e * 0.2, 10.82, -0.2), (0.11, 0.12, 0.06), R.EYE, segments=5, rings=3)

    # The off (left) arm hangs from the torso; the right arm and what it holds are the arm piece.
    for piece, path, hand in ((torso, [(-2.95, 10.0, 0.25), (-3.35, 8.3, 0.18), (-3.0, 6.9, -0.4)], b.points["handL"]),
                              (b["arm"], [(2.95, 10.0, 0.25), (3.4, 8.3, 0.0), (3.45, 6.85, -0.55)], b.points["hand"])):
        limb(piece.skin, path, [0.88, 0.74, 0.58], skin, segments=12)
        ball(piece.skin, hand, (0.6, 0.55, 0.6), skin, segments=8, rings=5)
        fore = rk.norm(rk.sub(path[2], path[1]))
        mid = lerp3(path[1], path[2], 0.45)
        piece.gear.lathe([(-0.55, 0.0), (-0.52, 0.8), (0.5, 0.74), (0.55, 0.0)], H.FUR if look == "A" else H.HIDE,
                         axis=fore, centre=mid, segments=12, smooth=False)
        piece.gear.loop(lerp3(path[1], path[2], 0.85), fore, 0.66, 0.66, (0.1, 0.1), F.BONE, segments=12, tube_segments=4)
    arm = b["arm"]
    grip = b.points["hand"]
    # The weapon's -Z, nearly in line with the forearm (18 degrees forward of it): a rigid wrist can then
    # drag the head on the ground (carry), lift it overhead and slam it into the ground in front (one
    # shoulder rotation each), hold it out like a lance (the charge) and sweep it wide at arm's length.
    toward_head = rk.norm((-0.06, -0.951, -0.309))
    if look == "A":
        back = rk.mul(toward_head, -1.0)
        wx = rk.norm(cross3((0.0, 1.0, 0.0), back))
        wy = cross3(back, wx)  # the weapon's +Y as near the body's up as the haft allows: its face strikes down
        b.points["tip"] = add(grip, rk.mul(toward_head, WARHAMMER_TIP * WARHAMMER_SCALE))
        b.hold = {
            "model": "Warhammer",
            "folder": "Weapons",
            "scale": round(WARHAMMER_SCALE, 3),
            "piece": "arm",
            "grip": rk.r3(grip),
            "right": rk.r3(wx),
            "up": rk.r3(wy),
            "note": "CFrame.fromMatrix(grip, right, up) in the arm piece's rest frame, then Model:ScaleTo(scale) about Base (the grip)",
        }
    else:
        d = toward_head
        b.points["tip"] = add(grip, rk.mul(d, 6.9))
        arm.gear.lathe([(-1.0, 0.0), (-0.9, 0.36), (1.4, 0.42), (3.8, 0.7), (6.0, 0.92), (6.7, 0.8), (6.9, 0.0)],
                       F.WOOD, axis=d, centre=grip, segments=10, smooth=True,
                       face_colour=lambda i, j: F.WOOD_DARK if (i in (3, 4) and j % 2 == 0) else F.WOOD)
        for along in (2.4, 4.3):
            arm.gear.lathe([(-0.14, 0.0), (-0.12, 0.56 + along * 0.06), (0.12, 0.56 + along * 0.06), (0.14, 0.0)],
                           F.ROPE, axis=d, centre=add(grip, rk.mul(d, along)), segments=10, smooth=False)
        u, v = rk.basis(d, (0.0, 1.0, 0.0))
        for k in range(7):
            ang = k * 2 * math.pi / 7
            out = add(rk.mul(u, math.cos(ang)), rk.mul(v, math.sin(ang)))
            base = add(grip, rk.mul(d, 5.1 + 0.45 * (k % 2)))
            spike(arm.gear, add(base, rk.mul(out, 0.6)), add(base, rk.mul(out, 1.45)), 0.2, F.BONE, segments=4)

    for name, x in (("legL", -1.25), ("legR", 1.25)):
        leg = b[name]
        limb(leg.cloth, [(x, 5.85, 0.2), (x * 1.04, 3.2, -0.08), (x, 1.35, 0.1)], [1.05, 0.88, 0.74], cloth, segments=12)
        blob(leg.gear, [
            (0.0, x, -0.25, 0.85, 1.12),
            (0.8, x, -0.16, 0.9, 1.05),
            (1.6, x, 0.08, 0.92, 0.92, jagged(0.16, 51 if x < 0 else 52)),
        ], H.FUR if look == "A" else H.HIDE, segments=14, smooth=False)
        band(leg.gear, 1.0, 1.22, x, -0.12, 0.96, 1.1, F.ROPE, segments=14)
        band(leg.gear, 2.6, 2.82, x, -0.04, 0.88, 0.88, F.LEATHER, segments=12)

    # Keys carry the lean of their moment (see the fodder): the slam's coil leans back 0.45 and its
    # impact forward 0.3, the charge runs leaning forward 0.5, the call throws the head back 0.5.
    # L4 W2 (measured on every vertex over every pose, raiderpose.posed_extent): the charge's coil
    # (0.25 -> 1.1) and strike (1.7 -> 1.9) and the slump (0.75 -> 0.9) were lifted, because leaning
    # into the charge or slumping after any blow drove the hammer's head 1.7 to 4.6 studs into the
    # ground; only the slam still buries it, about 1.5 to 1.9, which is the impact. The fix round (K2):
    # the sweep winds the hammer out to his right and sweeps it low across his front, rising to his
    # left, so every 15-degree sector of the 150-degree wedge is swept (12.4 to 13.0 studs: the sweep's
    # range is 12.7); `steady` keeps it from jumping at the impact, where the arc's lean flips.
    b.arm = {
        "carry": [0.62, 0.0, 0.0],
        "seat": [1.12, 0.0, 0.05],
        "slump": [0.9, 0.0, 0.05],
        "shapes": {
            "ring": {"coil": [2.3, 0.0, 0.12], "strike": [0.79, 0.0, 0.0], "follow": [0.47, 0.0, 0.0]},
            "lane": {"coil": [1.1, 0.0, 0.0], "strike": [1.9, 0.0, 0.0], "follow": [1.2, 0.0, 0.0]},
            "summon": {"coil": [2.3, 0.0, 0.25], "strike": [3.2, 0.0, 0.3], "follow": [2.6, 0.0, 0.25]},
            "arc": {"coil": [-0.12, 0.86, 1.07], "strike": [0.4, -0.3, 1.45], "follow": [-0.19, 1.71, 1.69], "steady": True},
        },
    }
    # The boss's charging core at model size (the lead's note, Ben's verdict 27.4): today's cue is a
    # 2.4-stud ball swelling to 4.2 (enraged 3.24 at rest) that hid his chest in every frame. 1.6 at
    # rest sits inside the amulet ring (2.24 across inside); charged to 2.6 it covers the ring, which
    # still says "something is coming" from across the clearing. Enraged the rest size grows by
    # Theme.COMBAT_RANGE_ENRAGE_CORE_SCALE (2.16) and the charged size never shrinks under it.
    b.cue = {"piece": "torso", "point": "core", "size": 1.6, "charged": 2.6}
    b.budget = BUDGETS["chief"]
    return b


import raider_kit_elite  # noqa: E402  (step 2: the plated elite)
import raider_kit_marksman  # noqa: E402  (step 2: the marksman)
import raider_kit_throwers  # noqa: E402  (step 2: the slinger and the lobber)

MODELS = {"RaiderFodder": fodder, "RaiderBrute": brute, "RaiderChief": chief,
          "RaiderSlinger": raider_kit_throwers.slinger, "RaiderLobber": raider_kit_throwers.lobber,
          "RaiderMarksman": raider_kit_marksman.marksman, "RaiderArmoured": raider_kit_elite.armoured}


def centre_head(b: rk.Body) -> None:
    """Move the head piece so its skull (the skin) is centred exactly on the scored head: the rule's
    margin is then spent only on the pose, never on where the modeller happened to put the skull."""
    skins = [m for k, m in b["head"].meshes.items() if k == "raider-skin" and m.faces]
    lo, hi = rk.bounds_of(skins)
    centre = tuple((lo[i] + hi[i]) / 2 for i in range(3))
    delta = rk.sub(b.points["head"], centre)
    for mesh in b["head"].meshes.values():
        mesh.verts = [rk.add(v, delta) for v in mesh.verts]
    b.notes["headShift"] = rk.r3(delta)


# --- driver ---------------------------------------------------------------------------------------


def add_posed_reach(body: rk.Body, record: dict, kinds: dict, threat_cfg: dict, consts, rig_numbers: dict) -> None:
    """`posedReach` in the kind's record: every vertex (and the held Warhammer's) over every sampled
    pose before a hit (raiderpose.posed_extent), for camp C's sight gate. raiderpose --check measures
    it again on the exported GLBs and fails when the config is stale."""
    kind = kinds.get(body.kind)
    if kind is None:
        print(f"[raider-kit] WARNING: no crowd kind {body.kind!r}: no posed reach", flush=True)
        return
    pieces = {p: raiderpose.unique_points([v for m in body[p].meshes.values() if m.faces for v in m.verts])
              for p in rk.PIECES}
    held = []
    if body.hold:
        path = os.path.join(raiderpose.WEAPONS_DIR, f"{body.hold['model']}.glb")
        if os.path.isfile(path):
            held = raiderpose.unique_points(raiderpose._glb_points(path))
        else:
            print(f"[raider-kit] WARNING: no {body.hold['model']}.glb: the posed reach leaves the weapon out", flush=True)
    ext = raiderpose.posed_extent(record, kind, threat_cfg, consts, rig_numbers, pieces, held)
    record["posedReach"] = raiderpose.reach_record(ext, body.radius)
    body.notes["inHead"] = round(ext["intrude"], 3)
    record["notes"] = body.notes


def merge(models: list[str]) -> int:
    """Delete the raider kits' palette caches (the cache trap), then merge the props for measuring."""
    import bpy

    for kit in rk.rpal.KITS:
        for ext in (".json", ".png"):
            path = os.path.join(PALETTE_CACHE, kit + ext)
            if os.path.isfile(path):
                os.remove(path)
    cmd = [bpy.app.binary_path, "-b", "-P", os.path.join(HERE, "merge_stages.py"), "--", "--props", "--era", rk.ERA]
    for m in models:
        cmd += ["--model", m]
    print(f"[raider-kit] merging: {' '.join(cmd[3:])}", flush=True)
    return subprocess.run(cmd).returncode


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Generate the raider kit.")
    parser.add_argument("--only", action="append", help="only this model (repeatable)")
    parser.add_argument("--merge", action="store_true", help="also run merge_stages.py --props --era Raiders")
    parser.add_argument("--look-b", action="store_true", help="the Chief's look B, into assets/build/raider-lookb")
    args = parser.parse_args(argv)

    if args.look_b:
        body = chief(look="B")
        centre_head(body)
        if os.path.isdir(LOOK_B_ROOT):
            shutil.rmtree(LOOK_B_ROOT)
        rec = rk.export_body(body, LOOK_B_ROOT)
        print(f"[raider-kit] look B: {body.model} {rec['triangles']} tris, {rec['meshParts']} MeshParts -> "
              f"{os.path.relpath(LOOK_B_ROOT, rk.REPO_ROOT)}", flush=True)
        return 0

    rk.export_palette_cards()
    consts = raiderpose.Constants()
    kinds, threat_cfg, _ = raiderpose.load_kinds()
    rig_numbers = dict(raiderpose.RIG_DEFAULTS)
    records = {}
    failures = 0
    built = []
    for name, make in MODELS.items():
        if args.only and name not in args.only:
            continue
        body = make()
        centre_head(body)
        rec = rk.export_body(body, extend=lambda r, b=body: add_posed_reach(b, r, kinds, threat_cfg, consts, rig_numbers))
        bp = rk.write_blueprint(body)
        records[body.kind] = rec
        built.append(name)
        over = "" if rec["triangles"] <= body.budget else f" OVER the {body.budget} budget"
        if over:
            failures += 1
        s = rec["bounds"]["size"]
        pr = rec.get("posedReach") or {}
        print(f"[raider-kit] {name} ({body.kind}): {rec['triangles']} tris{over}, {rec['meshParts']} MeshParts, "
              f"{s[0]} x {s[1]} x {s[2]} studs, rest reach {rec['reach']} ({rec['reachRadii']} radii), posed reach "
              f"{pr.get('out')} out / {pr.get('up')} up -> {os.path.relpath(bp, rk.REPO_ROOT)}", flush=True)
        for p in rec["pieces"]:
            print(f"[raider-kit]   S{p['stage']} {p['name']:5s} {p['triangles']:5d} tris  {p['parts']}", flush=True)
    path = rk.write_config(records, dict(raiderpose.RIG_DEFAULTS))
    print(f"[raider-kit] config -> {os.path.relpath(path, rk.REPO_ROOT)}", flush=True)
    if args.merge and built:
        failures += 1 if merge(built) else 0
    return 1 if failures else 0


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    sys.exit(main(argv))
