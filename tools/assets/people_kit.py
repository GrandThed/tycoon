"""Chunky toy pedestrians and birds for Village, Boomtown and Metropolis, generated as a kit.

Runs inside Blender (headless):

    blender -b -P tools/assets/people_kit.py [-- --out <dir>]

Writes one GLB per piece into assets/kenney3d/people-kit/Models/GLB format/ (the Kenney folder
convention, so testfit and merge_stages discover the kit with no registration step). assets/ is
gitignored; this script is the committed artifact. Mesh helpers and the export plumbing come from
garden_kit.py.

Why a custom kit (INTERFACES "Wave 2c -- living city", Pedestrians and Ambient): no kit the eras
use carries a person or a bird, and Walkers.luau moves each walker as one merged MeshPart with a
vertical bob -- no rig, no animation -- so a figure has to read as a person while standing still.
That is why the proportions are toy-like: a head about a third of the height (it is what the eye
finds at the ~23-30 degree tycoon camera), a torso and arms in one strong outfit colour, two
separate legs, and dark eyes on the front face so the direction of travel reads.

Scale: the contract asks for 1.6-2.0 studs, and a figure here is 1.75-1.85. That is deliberately
taller than a kit door (measured in renders: a suburban door is ~1.0 stud and a commercial one ~1.2
at blueprint scale 4, houses 3.3), because anything door-sized is a speck at the tycoon camera; the
kits are toy-scale next to a 5-stud avatar anyway. A walker blueprint's `scale` shrinks a figure
without touching this script. A bird spans 0.64.

**Units: 1 glTF unit = 1 stud** (blueprints use `"scale": 1.0`). Front is -Z in glTF space, origin
at bottom centre. Colours are texels of each era's own kit colormaps: fantasy-town-kit for Village
(its earthy browns, cream and teal), the City Kits for Boomtown and Metropolis.
"""

from __future__ import annotations

import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from garden_kit import REPO_ROOT, Part, generate  # noqa: E402

KIT = "people-kit"
DEFAULT_OUT = os.path.join(REPO_ROOT, "assets", "kenney3d", KIT, "Models", "GLB format")

# Shared by both colormaps (fantasy-town-kit and the City Kits carry the same base ramp).
SKIN_LIGHT = (253, 228, 199)
SKIN = (242, 191, 153)
SKIN_TAN = (250, 174, 138)
SKIN_DARK = (176, 96, 65)
WHITE = (255, 255, 255)
BLACK = (56, 56, 61)
SLATE = (79, 82, 96)
YELLOW = (255, 192, 68)
RED = (207, 83, 79)
ORANGE = (255, 126, 68)
BLUE = (103, 148, 217)
PURPLE = (168, 120, 232)
GREY = (134, 139, 161)
GREY_LIGHT = (160, 168, 201)
# fantasy-town-kit only: the Village's cloth and leather.
F_BROWN = (154, 89, 66)
F_TAN = (197, 130, 98)
F_SAND = (238, 186, 136)
F_TEAL = (81, 178, 150)
F_MAROON = (195, 73, 92)
# City Kits only.
C_MINT = (97, 203, 139)
C_CHARCOAL = (58, 60, 63)
C_NAVY = (81, 85, 102)
C_PEACH = (241, 151, 108)
C_TRIM = (142, 149, 179)
C_BROWN = (176, 96, 65)

# --- the figure, in studs -------------------------------------------------------------------------
SHOE_TOP = 0.1
HIP = 0.6
SHOULDER = 1.1
HEAD_BOTTOM = 1.13
HEAD_TOP = 1.65
HEAD_HALF = 0.27  # 0.54 wide: a third of the height is what makes it a toy, not a mannequin
HEAD_HALF_Z = 0.25
LEG_HALF = 0.1
LEG_X = 0.12  # leg centres; the 0.04 gap between them is what keeps "two legs" at a distance
TORSO_HIP = 0.24  # half-widths of the torso at the hip and at the shoulder
TORSO_SHOULDER = 0.28
TORSO_HALF_Z = 0.17
ARM_IN = TORSO_SHOULDER
ARM_OUT = TORSO_SHOULDER + 0.14
ARM_HALF_Z = 0.1
HAND = 0.1  # the skin-coloured bottom of each arm


def body(p: Part, *, skin, top, legs, shoes, hair, hair_style="short", sleeves=None, torso_bottom=HIP):
    """The shared figure: shoes, two legs, torso, arms with hands, head with eyes, and hair.

    `top` colours torso and sleeves; `torso_bottom` below HIP makes a smock or coat that covers the
    upper legs (the legs still show under it). Every outfit below adds to this, never replaces it.
    """
    sleeves = sleeves or top
    for sx in (-1, 1):
        x = sx * LEG_X
        p.box(x - LEG_HALF - 0.01, x + LEG_HALF + 0.01, 0.0, SHOE_TOP, -0.16, 0.12, shoes)
        p.box(x - LEG_HALF, x + LEG_HALF, SHOE_TOP, HIP + 0.02, -0.1, 0.1, legs)
    p.frustum(-TORSO_HIP, TORSO_HIP, -TORSO_HALF_Z, TORSO_HALF_Z, torso_bottom,
              -TORSO_SHOULDER, TORSO_SHOULDER, -TORSO_HALF_Z, TORSO_HALF_Z, SHOULDER, top)
    for sx in (-1, 1):
        x0, x1 = sorted((sx * ARM_IN, sx * ARM_OUT))
        p.box(x0, x1, HIP + 0.1 + HAND, SHOULDER - 0.01, -ARM_HALF_Z, ARM_HALF_Z, sleeves)
        p.box(x0 + 0.01, x1 - 0.01, HIP + 0.1, HIP + 0.1 + HAND, -ARM_HALF_Z + 0.01, ARM_HALF_Z - 0.01, skin)
    p.box(-0.1, 0.1, SHOULDER - 0.01, HEAD_BOTTOM + 0.01, -0.09, 0.09, skin)  # neck
    p.box(-HEAD_HALF, HEAD_HALF, HEAD_BOTTOM, HEAD_TOP, -HEAD_HALF_Z, HEAD_HALF_Z, skin)
    eye_y = HEAD_BOTTOM + 0.24
    for sx in (-1, 1):
        x = sx * 0.11
        p.box(x - 0.04, x + 0.04, eye_y, eye_y + 0.1, -HEAD_HALF_Z - 0.02, -HEAD_HALF_Z, BLACK)
    hair_cap(p, hair, hair_style)


def hair_cap(p: Part, colour, style: str) -> None:
    """Hair as a thick cap over the top and back of the head, the fringe left open for the eyes."""
    if style == "none":
        return
    h = HEAD_HALF + 0.03
    p.box(-h, h, HEAD_TOP - 0.02, HEAD_TOP + 0.1, -HEAD_HALF_Z - 0.03, HEAD_HALF_Z + 0.03, colour)
    back_bottom = HEAD_BOTTOM + (0.02 if style == "long" else 0.2)
    p.box(-h, h, back_bottom, HEAD_TOP - 0.02, HEAD_HALF_Z, HEAD_HALF_Z + 0.03, colour)
    for sx in (-1, 1):
        x0, x1 = sorted((sx * HEAD_HALF, sx * h))
        p.box(x0, x1, HEAD_BOTTOM + 0.3, HEAD_TOP - 0.02, -HEAD_HALF_Z - 0.03, HEAD_HALF_Z, colour)
    p.box(-h, h, HEAD_TOP - 0.1, HEAD_TOP - 0.02, -HEAD_HALF_Z - 0.03, -HEAD_HALF_Z, colour)  # fringe
    if style == "bun":
        p.box(-0.12, 0.12, HEAD_TOP - 0.1, HEAD_TOP + 0.12, HEAD_HALF_Z + 0.03, HEAD_HALF_Z + 0.2, colour)


def hood(p: Part, colour) -> None:
    """A peaked hood over the hair line plus a short cape across the shoulders."""
    h = HEAD_HALF + 0.05
    z0, z1 = -HEAD_HALF_Z - 0.05, HEAD_HALF_Z + 0.06
    p.frustum(-h, h, z0, z1, HEAD_TOP - 0.02, -0.12, 0.12, z0 + 0.1, z1, HEAD_TOP + 0.2, colour)
    p.box(-h, h, HEAD_BOTTOM - 0.02, HEAD_TOP - 0.02, HEAD_HALF_Z, z1, colour)
    for sx in (-1, 1):
        x0, x1 = sorted((sx * HEAD_HALF, sx * h))
        p.box(x0, x1, HEAD_BOTTOM + 0.05, HEAD_TOP - 0.02, z0, HEAD_HALF_Z, colour)
    p.frustum(-ARM_OUT - 0.02, ARM_OUT + 0.02, -TORSO_HALF_Z - 0.03, TORSO_HALF_Z + 0.05, SHOULDER - 0.2,
              -0.2, 0.2, -TORSO_HALF_Z, TORSO_HALF_Z + 0.03, SHOULDER + 0.06, colour)


def brimmed_hat(p: Part, brim, crown, width: float = 0.46, crown_h: float = 0.2) -> None:
    y = HEAD_TOP - 0.04
    p.box(-width, width, y, y + 0.05, -width, width, brim)
    p.box(-0.22, 0.22, y + 0.05, y + 0.05 + crown_h, -0.21, 0.21, crown)


def cap(p: Part, colour) -> None:
    """Baseball cap: a crown on the head and a peak pushed out over the eyes (front -Z)."""
    h = HEAD_HALF + 0.03
    p.box(-h, h, HEAD_TOP - 0.08, HEAD_TOP + 0.1, -HEAD_HALF_Z - 0.03, HEAD_HALF_Z + 0.03, colour)
    p.box(-0.2, 0.2, HEAD_TOP - 0.08, HEAD_TOP - 0.03, -HEAD_HALF_Z - 0.22, -HEAD_HALF_Z - 0.03, colour)


def skirt(p: Part, colour, bottom: float, flare: float = 0.08) -> None:
    """A flared skirt or dress hem from the waist down to `bottom`, over the legs."""
    p.frustum(-TORSO_HIP - flare, TORSO_HIP + flare, -TORSO_HALF_Z - flare * 0.8, TORSO_HALF_Z + flare * 0.8, bottom,
              -TORSO_HIP, TORSO_HIP, -TORSO_HALF_Z, TORSO_HALF_Z, HIP + 0.04, colour)


def front_panel(p: Part, colour, y0: float, y1: float, half_w: float, at_z: float, proud: float = 0.02) -> None:
    """A flat panel standing proud of a front face: aprons, shirt fronts, ties, scarves."""
    p.box(-half_w, half_w, y0, y1, at_z - proud, at_z, colour)


def belt(p: Part, colour, y: float, half_x: float, half_z: float) -> None:
    p.box(-half_x, half_x, y, y + 0.06, -half_z, half_z, colour)


def held_box(p: Part, colour, side: int, size=(0.08, 0.26, 0.3)) -> None:
    """Briefcase, bag or basket hanging from one hand."""
    sx, sy, sz = size
    x = side * (ARM_OUT - 0.07)
    top = HIP + 0.1
    p.box(x - sx / 2, x + sx / 2, top - sy, top, -sz / 2, sz / 2, colour)


# --- Village: smocks, aprons, hoods ---------------------------------------------------------------


def walker_village_a() -> Part:
    """Hooded peasant: long brown smock, teal hood and cape."""
    p = Part("walker-village-a")
    body(p, skin=SKIN, top=F_BROWN, legs=F_TAN, shoes=BLACK, hair=F_BROWN, torso_bottom=0.38)
    belt(p, BLACK, 0.64, TORSO_HIP + 0.01, TORSO_HALF_Z + 0.01)
    hood(p, F_TEAL)
    return p


def walker_village_b() -> Part:
    """Market woman: maroon dress to the ankles, cream apron, headscarf, bun."""
    p = Part("walker-village-b")
    body(p, skin=SKIN_TAN, top=F_MAROON, legs=F_MAROON, shoes=F_BROWN, hair=F_BROWN, hair_style="bun")
    skirt(p, F_MAROON, 0.12, flare=0.1)
    front_panel(p, SKIN_LIGHT, 0.22, 0.98, 0.17, -TORSO_HALF_Z - 0.06, proud=0.03)
    p.box(-HEAD_HALF - 0.03, HEAD_HALF + 0.03, HEAD_TOP - 0.02, HEAD_TOP + 0.08, -HEAD_HALF_Z - 0.02,
          HEAD_HALF_Z + 0.03, SKIN_LIGHT)  # the headscarf sits on the hair cap
    return p


def walker_village_c() -> Part:
    """Farmer: sand shirt, brown breeches, a wide straw hat."""
    p = Part("walker-village-c")
    body(p, skin=SKIN_DARK, top=F_SAND, legs=F_BROWN, shoes=BLACK, hair=BLACK)
    belt(p, F_BROWN, HIP, TORSO_HIP + 0.01, TORSO_HALF_Z + 0.01)
    brimmed_hat(p, YELLOW, YELLOW, width=0.44, crown_h=0.16)
    return p


def walker_village_d() -> Part:
    """Basket carrier: teal tunic belted over tan trousers, ginger hair, a wicker basket."""
    p = Part("walker-village-d")
    body(p, skin=SKIN_LIGHT, top=F_TEAL, legs=F_TAN, shoes=F_BROWN, hair=ORANGE, torso_bottom=0.44)
    belt(p, F_BROWN, 0.66, TORSO_HIP + 0.01, TORSO_HALF_Z + 0.01)
    held_box(p, F_TAN, 1, size=(0.26, 0.22, 0.3))
    return p


# --- Boomtown: casual -----------------------------------------------------------------------------


def walker_boomtown_a() -> Part:
    """Red tee, blue jeans, navy cap."""
    p = Part("walker-boomtown-a")
    body(p, skin=SKIN, top=RED, legs=BLUE, shoes=WHITE, hair=C_BROWN, sleeves=RED)
    cap(p, C_NAVY)
    return p


def walker_boomtown_b() -> Part:
    """Yellow shirt, dark jeans, black hair."""
    p = Part("walker-boomtown-b")
    body(p, skin=SKIN_DARK, top=YELLOW, legs=SLATE, shoes=BLACK, hair=BLACK)
    return p


def walker_boomtown_c() -> Part:
    """Purple top, blue denim skirt, long blonde hair."""
    p = Part("walker-boomtown-c")
    body(p, skin=SKIN_TAN, top=PURPLE, legs=SKIN_TAN, shoes=RED, hair=YELLOW, hair_style="long")
    skirt(p, BLUE, 0.36)
    return p


def walker_boomtown_d() -> Part:
    """Orange hoodie, grey trousers, mint backpack."""
    p = Part("walker-boomtown-d")
    body(p, skin=SKIN_LIGHT, top=ORANGE, legs=GREY, shoes=WHITE, hair=C_BROWN)
    p.box(-0.2, 0.2, 0.62, 1.04, TORSO_HALF_Z, TORSO_HALF_Z + 0.16, C_MINT)
    return p


# --- Metropolis: suits and coats ------------------------------------------------------------------


def walker_metropolis_a() -> Part:
    """Charcoal suit, white shirt front, red tie, brown briefcase."""
    p = Part("walker-metropolis-a")
    body(p, skin=SKIN, top=C_CHARCOAL, legs=C_CHARCOAL, shoes=BLACK, hair=C_BROWN)
    front_panel(p, WHITE, 0.82, SHOULDER - 0.01, 0.09, -TORSO_HALF_Z)
    front_panel(p, RED, 0.7, SHOULDER - 0.02, 0.035, -TORSO_HALF_Z - 0.02)
    held_box(p, C_BROWN, 1)
    return p


def walker_metropolis_b() -> Part:
    """Belted peach trench coat to the knees over dark trousers."""
    p = Part("walker-metropolis-b")
    body(p, skin=SKIN_LIGHT, top=C_PEACH, legs=BLACK, shoes=BLACK, hair=BLACK, torso_bottom=0.3)
    belt(p, C_BROWN, 0.66, TORSO_HIP + 0.01, TORSO_HALF_Z + 0.01)
    return p


def walker_metropolis_c() -> Part:
    """Blue skirt suit, long dark hair, red handbag."""
    p = Part("walker-metropolis-c")
    body(p, skin=SKIN_DARK, top=BLUE, legs=SKIN_DARK, shoes=BLACK, hair=BLACK, hair_style="long")
    skirt(p, C_NAVY, 0.34, flare=0.04)
    front_panel(p, WHITE, 0.86, SHOULDER - 0.01, 0.08, -TORSO_HALF_Z)
    held_box(p, RED, -1, size=(0.1, 0.18, 0.22))
    return p


def walker_metropolis_d() -> Part:
    """Grey overcoat, yellow scarf, grey trousers, bare head of ginger hair."""
    p = Part("walker-metropolis-d")
    body(p, skin=SKIN_TAN, top=C_TRIM, legs=C_NAVY, shoes=BLACK, hair=ORANGE, torso_bottom=0.34)
    p.box(-0.22, 0.22, SHOULDER - 0.08, SHOULDER + 0.04, -TORSO_HALF_Z - 0.04, TORSO_HALF_Z + 0.02, YELLOW)
    front_panel(p, YELLOW, 0.72, SHOULDER - 0.08, 0.06, -TORSO_HALF_Z - 0.04, proud=0.03)
    return p


# --- birds ----------------------------------------------------------------------------------------


def bird(name: str, body_colour, wing, tip, beak) -> Part:
    """A bird gliding with wings spread and a slight dihedral, 0.64 studs across.

    Ambient.luau flies it in a circle at a height, so most of what the camera sees is the wing
    plan-form from above: the wings carry the colour and the dark tips give the silhouette.
    """
    p = Part(name)
    p.frustum(-0.05, 0.05, -0.1, 0.12, 0.0, -0.07, 0.07, -0.12, 0.1, 0.12, body_colour)
    p.box(-0.055, 0.055, 0.07, 0.17, -0.22, -0.1, body_colour)  # head
    p.box(-0.02, 0.02, 0.1, 0.13, -0.28, -0.22, beak)
    p.frustum(-0.07, 0.07, 0.1, 0.24, 0.05, -0.03, 0.03, 0.1, 0.12, 0.09, tip)  # tail
    for sx in (-1, 1):
        inner, mid, out = 0.06 * sx, 0.24 * sx, 0.32 * sx
        # Each wing is two slabs, inner in the wing colour and a darker tip, rising 0.03 outward.
        p.hexa(_slab(inner, mid, 0.08, 0.1, -0.07, 0.08, -0.05, 0.05), wing)
        p.hexa(_slab(mid, out, 0.1, 0.11, -0.05, 0.05, -0.02, 0.04), tip)
    return p


def _slab(xa, xb, ya, yb, za0, za1, zb0, zb1):
    """Corners of a thin wing slab from span position xa (chord za0..za1, height ya) to xb."""
    x0, x1 = sorted((xa, xb))
    if xa > xb:
        ya, yb, za0, zb0, za1, zb1 = yb, ya, zb0, za0, zb1, za1
    t = 0.025
    return [
        (x0, ya, za0), (x1, yb, zb0), (x1, yb, zb1), (x0, ya, za1),
        (x0, ya + t, za0), (x1, yb + t, zb0), (x1, yb + t, zb1), (x0, ya + t, za1),
    ]


def bird_brown() -> Part:
    return bird("bird-brown", C_PEACH, C_BROWN, BLACK, YELLOW)


def bird_grey() -> Part:
    return bird("bird-grey", GREY_LIGHT, GREY, C_NAVY, BLACK)


PIECES = {
    "walker-village-a": walker_village_a,
    "walker-village-b": walker_village_b,
    "walker-village-c": walker_village_c,
    "walker-village-d": walker_village_d,
    "walker-boomtown-a": walker_boomtown_a,
    "walker-boomtown-b": walker_boomtown_b,
    "walker-boomtown-c": walker_boomtown_c,
    "walker-boomtown-d": walker_boomtown_d,
    "walker-metropolis-a": walker_metropolis_a,
    "walker-metropolis-b": walker_metropolis_b,
    "walker-metropolis-c": walker_metropolis_c,
    "walker-metropolis-d": walker_metropolis_d,
    "bird-brown": bird_brown,
    "bird-grey": bird_grey,
}


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Generate the people-kit GLBs.")
    parser.add_argument("--out", default=DEFAULT_OUT, help="target Models/GLB format directory")
    args = parser.parse_args(argv)
    return generate(KIT, PIECES, args.out)


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    sys.exit(main(argv))
