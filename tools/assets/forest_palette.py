"""The Forest Road's colours (L4): the raider forest's ground, foliage, bark, rock and hide.

Ben's L4 ruling (MISSIONS_DESIGN section 26) and the lead's: the real forest must not read as the
Village or the Valley re-used. It is a raider forest: darker and denser than the Valley's meadow
pines (44, 112, 78), bluer and deeper greens, wet dark earth, grey rock, and camps of hide, rope
and logs. Every forest generator (tools/assets/forest_kit.py, tools/levels/forest.py) takes its
colours from here and nowhere else: `forest_kit.Mesh` refuses any other colour, so two pieces can
never drift into two near-identical browns.

The camp's wood, bone, rope, leather, flint and ochre are the weapon kit's `FOREST` swatches
(tools/assets/weapon_kit_palette.py), reused here by reference and never redefined, so a raider's
club and the rack it hangs on are one wood. Flames reuse the weapon kit's `FIRE`.

Why the values are what they are. The level is judged at the player's eye under default Roblox
lighting (every look Ben approved so far was judged under it) and, as the second mood, darker with
haze. Dark greens and dark earth must still separate from each other there, so each family keeps
a luminance step of at least ~1.25 between its dark, mid and light swatch, and the road stays
clearly lighter than the forest floor beside it (the Village lesson: a path that matches the
ground vanishes).

Units: sRGB bytes, as Color3.fromRGB writes them. forest_kit turns them into linear material
factors and palette.py (forest-kit is not an sRGB-factor kit) turns those back into the same bytes.

    py tools/assets/forest_palette.py            # the swatch table with luminance steps

**Changing or adding a colour** changes the palette texture: delete assets/build/palettes/forest-kit.*
before the next merge_stages run (the palette cache trap), and re-run tools/levels/forest.py build.
"""

from __future__ import annotations

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from weapon_kit_palette import FIRE, FOREST  # noqa: E402  (reused by reference, never redefined)

Rgb = tuple[int, int, int]


class GROUND:
    """The floor of the forest, the road through it, the camps' trampled earth, banks and gullies."""

    FLOOR_DARK = (46, 52, 34)  # deep shade under the firs
    FLOOR = (62, 70, 42)  # needles over moss: the forest floor's base
    FLOOR_MOSS = (80, 98, 48)  # moss patches catching light
    NEEDLES = (96, 74, 48)  # bare needle litter
    ROAD = (142, 112, 80)  # packed earth: well above the floor's luminance
    ROAD_DARK = (104, 82, 60)  # ruts, the road's rim
    ROAD_LIGHT = (160, 132, 96)  # dry crown of the road, pebbles
    CAMP = (122, 100, 76)  # trampled camp earth
    CAMP_DARK = (92, 74, 56)  # mud round the fires
    STRAW = (178, 152, 96)  # straw and wood chips scattered in the camps
    MUD = (72, 60, 46)  # creek banks
    GULLY = (40, 38, 36)  # the ravine floor, far below


class FOLIAGE:
    """Firs, the dark broadleaf, thicket, bramble, ferns, moss."""

    FIR_DARK = (26, 54, 44)  # the fir's inner, shaded tiers
    FIR = (36, 74, 56)
    FIR_TIP = (54, 96, 66)  # the lit upper tier
    LEAF_DARK = (48, 66, 36)  # the gnarled broadleaf
    LEAF = (68, 90, 44)
    BUSH_DARK = (38, 62, 38)
    BUSH = (56, 86, 46)
    BRAMBLE = (82, 56, 50)  # thorny canes
    BERRY = (148, 36, 52)
    FERN = (70, 112, 52)
    MOSS = (96, 120, 54)


class BARK:
    """Trunks, logs, stumps, dead wood."""

    BARK_DARK = (52, 40, 34)
    BARK = (78, 60, 46)
    LOG_END = (150, 118, 82)  # cut log faces: pale rings read at a distance
    DEADWOOD = (128, 118, 104)  # bleached snags
    DEADWOOD_DARK = (92, 84, 74)


class ROCK:
    """Boulders, the rock faces over the tall walls, gully walls."""

    ROCK_DARK = (70, 72, 74)
    ROCK = (100, 100, 98)
    ROCK_LIGHT = (134, 132, 124)
    LICHEN = (118, 124, 80)


class HIDE:
    """The raiders' tents, racks and bedding: hide, fur, and the Chief's dyed hides."""

    HIDE_PALE = (206, 182, 140)
    HIDE = (170, 134, 94)
    HIDE_DARK = (126, 94, 66)
    FUR = (98, 80, 64)
    FUR_DARK = (66, 54, 46)
    DYED_RED = (140, 50, 40)  # the Chief's banners and tent bands (darker than FOREST.OCHRE)


class CAMP:
    """The camp's wood, bone, rope and paint: the weapon kit's FOREST swatches, reused."""

    WOOD_LIGHT = FOREST.WOOD_LIGHT
    WOOD = FOREST.WOOD
    WOOD_DARK = FOREST.WOOD_DARK
    BONE = FOREST.BONE
    BONE_SHADE = FOREST.BONE_SHADE
    ROPE = FOREST.ROPE
    ROPE_DARK = FOREST.ROPE_DARK
    LEATHER = FOREST.LEATHER
    LEATHER_DARK = FOREST.LEATHER_DARK
    FLINT = FOREST.FLINT
    FLINT_DARK = FOREST.FLINT_DARK
    OCHRE = FOREST.OCHRE
    FEATHER = FOREST.FEATHER


class FLAME:
    """A campfire's flames: the weapon kit's FIRE swatches, reused."""

    YELLOW = FIRE.FLAME_YELLOW
    ORANGE = FIRE.FLAME_ORANGE
    RED = FIRE.FLAME_RED
    SOOT = FIRE.SOOT


GROUPS = {
    "ground": GROUND,
    "foliage": FOLIAGE,
    "bark": BARK,
    "rock": ROCK,
    "hide": HIDE,
    "camp": CAMP,
    "flame": FLAME,
}


def swatches() -> dict[str, Rgb]:
    """Every swatch as "group.NAME" -> sRGB, in declaration order."""
    out: dict[str, Rgb] = {}
    for group, cls in GROUPS.items():
        for name, value in vars(cls).items():
            if name.isupper():
                out[f"{group}.{name}"] = value
    return out


ALL_COLOURS: frozenset[Rgb] = frozenset(swatches().values())


def srgb_to_linear(byte: int) -> float:
    s = byte / 255.0
    return s / 12.92 if s <= 0.04045 else ((s + 0.055) / 1.055) ** 2.4


def luminance(rgb: Rgb) -> float:
    r, g, b = (srgb_to_linear(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a: Rgb, b: Rgb) -> float:
    la, lb = luminance(a), luminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


def table() -> str:
    rows = [f"{'swatch':24s} {'sRGB':16s} {'lum':>6s} {'vs floor':>9s}"]
    for name, rgb in swatches().items():
        rows.append(f"{name:24s} {str(rgb):16s} {luminance(rgb):6.3f} {contrast(rgb, GROUND.FLOOR):9.2f}")
    return "\n".join(rows)


def main() -> int:
    print(table())
    names = swatches()
    values = list(names.values())
    dupes = sorted({n for n, c in names.items() if values.count(c) > 1})
    if dupes:
        print(f"[forest-palette] two names share one colour: {', '.join(dupes)}")
        return 1
    road = contrast(GROUND.ROAD, GROUND.FLOOR)
    print(f"[forest-palette] road against floor {road:.2f} (the road must read: at least 2.0)")
    return 0 if road >= 2.0 else 1


if __name__ == "__main__":
    sys.exit(main())
