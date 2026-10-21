"""The raider kit's colours (L4): the Forest's own swatches plus the few a raider's body needs.

Ben's rulings (MISSIONS_DESIGN section 26, the study's B4): real models for the seven Forest looks,
one tribe told apart by gear, size and cloth colour, and **each kind keeps today's colour on its
cloth** so the warnings still read. The cloth colour is therefore never a swatch here: the client
paints it from the kind's `color` in ProvingGrounds.json, exactly as it paints today's figure, and
the strips read that same file. What this module holds:

  * `FOREST`: the weapon kit's Forest (wood, bone, rope, leather, flint, ochre, feathers), and
    `FOREST_HIDE`: the forest track's hide and fur (tools/assets/forest_palette.py `HIDE`), both
    imported, never redefined: a raider's club and the rack it hangs on are one wood, his fur cloak
    and the tent's bedding one fur. forest_palette has no skin (the skin is painted from config)
    and its rock is the camp's, not a raider's.
  * `RAIDER`: the two colours only a body needs (hair and war paint, eyes).
  * `PAINT`: one fallback swatch per painted kit (raider-cloth, raider-skin, raider-glow). The
    client clears those MeshParts' TextureID and paints Color and Material by role, so these only
    show if a template is used unpainted: a flat light grey cloth reads "unpainted", never as a
    kind colour it is not.

Kits and the colours each may use (raider_kit_mesh.RMesh refuses anything else):
    raider-kit    FOREST + FOREST_HIDE + RAIDER   textured through the palette (palette.py), never painted
    raider-cloth  PAINT.CLOTH       painted: the kind's colour (body) or its darkened leg colour
    raider-skin   PAINT.SKIN        painted: the kind's skin colour, tinted half as far (the crit point)
    raider-glow   PAINT.GLOW        painted: the visor rule (dark, hot orange through an attack, ember enraged)

Units: sRGB bytes, as Color3.fromRGB writes them (the mesh module writes linear factors and
palette.py turns them back into the same bytes; none of these kits is an sRGB-factor kit).

    py tools/assets/raider_kit_palette.py      # contrast of every swatch on the forest grounds

**Changing or adding a colour** changes a palette texture: delete assets/build/palettes/raider-*.*
before the next merge_stages run (tools/assets/raider_kit.py --merge does it for you), or the cached
palette silently snaps the new colour to an old one.
"""

from __future__ import annotations

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from forest_palette import GROUND as FOREST_GROUND  # noqa: E402
from forest_palette import HIDE as FOREST_HIDE  # noqa: E402
from weapon_kit_palette import FOREST, contrast, srgb_to_linear  # noqa: E402,F401

Rgb = tuple[int, int, int]

# Grounds the swatches are judged on: the forest track's floor and road, and the grey level block.
GROUNDS = {"forest floor": FOREST_GROUND.FLOOR, "road": FOREST_GROUND.ROAD, "grey block": (104, 106, 112)}


class RAIDER:
    """What only a raider's body needs beside the Forest's gear: hair (and charcoal war paint), eyes."""

    HAIR = (54, 44, 40)  # hair, beards and charcoal war paint (inner, small only)
    EYE = (30, 25, 24)  # eyes, mouths, the skull mask's sockets (inner, small only)


class PAINT:
    """One fallback swatch per painted kit. The client paints these MeshParts; see the module notes."""

    CLOTH = (214, 214, 210)
    SKIN = (196, 148, 112)  # also the default `skin` the config proposes (RaiderModels.json)
    GLOW = (40, 32, 30)


GROUPS = {"forest": FOREST, "forest_hide": FOREST_HIDE, "raider": RAIDER}
PAINT_KITS = {"raider-cloth": PAINT.CLOTH, "raider-skin": PAINT.SKIN, "raider-glow": PAINT.GLOW}
GEAR_KIT = "raider-kit"
KITS = (GEAR_KIT, *PAINT_KITS)


def swatches() -> dict[str, Rgb]:
    """Every gear swatch as "group.NAME" -> sRGB, in declaration order."""
    out: dict[str, Rgb] = {}
    for group, cls in GROUPS.items():
        for name, value in vars(cls).items():
            if name.isupper():
                out[f"{group}.{name}"] = value
    return out


GEAR_COLOURS: frozenset[Rgb] = frozenset(swatches().values())


def allowed(kit: str) -> frozenset[Rgb]:
    if kit == GEAR_KIT:
        return GEAR_COLOURS
    if kit in PAINT_KITS:
        return frozenset({PAINT_KITS[kit]})
    raise ValueError(f"{kit} is not a raider kit ({', '.join(KITS)})")


def table() -> str:
    rows = [f"{'swatch':26s} {'sRGB':15s} " + " ".join(f"{k[:12]:>12s}" for k in GROUNDS)]
    for name, rgb in list(swatches().items()) + [(f"paint.{k}", v) for k, v in PAINT_KITS.items()]:
        rows.append(f"{name:26s} {str(rgb):15s} " + " ".join(f"{contrast(rgb, g):12.2f}" for g in GROUNDS.values()))
    return "\n".join(rows)


def main() -> int:
    print(table())
    values = list(swatches().values())
    if len(set(values)) != len(values):
        print("[raider-palette] two names share one colour")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
