"""The weapon kit's colours: one set of swatches per level, plus the fire and ice accents (L3).

Ben's ruling (MISSIONS_DESIGN section 24): every weapon family is dressed by the level where it is
found -- Forest wood, bone, rope, flint; Castle steel, crests, gold; Underworld black iron,
embers; Planet alloy, glow strips; Dream crystal, pastels -- and fire weapons read fire, ice
weapons read ice. Every weapon generator imports its colours from here and nowhere else:
weapon_kit_mesh.Mesh refuses any colour this module does not list, so two builders can never
drift into two near-identical browns.

Why the values are what they are. The weapons are judged in two places:
  * The Armory stage: the panel colour (30, 41, 70) (Theme.MAP_COLOR_PANEL) with the L0 mock's
    lighter radial (58, 77, 130) behind the weapon, lit by one ViewportFrame light plus ambient.
    Dark colours vanish there (the dark-pitch trap of the Metropolis Stadium), so a swatch whose
    contrast against the panel is under EDGE_CONTRAST is an "inner" colour: it may fill a face,
    never the silhouette edge, and it needs a lighter edge swatch around it (a bevel, a rim, a band).
  * In the hand, in daylight: on the Forest floor, a grey level block, the sky. Nothing here is
    saturated past what Roblox's Plastic shows as paint, and nothing is pure white or black.

The palette is flat: merge_stages.py bakes these into one swatch texture (palette.py) and Roblox
draws them as Plastic, so there is no sheen. Metal reads as metal only through a light edge on a
darker face; glow reads as glow only through a saturated light colour beside a dark one.

Units: sRGB bytes, as Color3.fromRGB writes them. The mesh module turns them into linear material
factors, and palette.py (weapon-kit is not an sRGB-factor kit) turns those back into the same bytes.

    py tools/assets/weapon_kit_palette.py            # contrast table of every swatch
    py tools/assets/weapon_kit_palette.py --sheet    # also assets/testfit/out/Weapons/_palette.png

**Changing or adding a colour** changes the palette texture: delete assets/build/palettes/weapon-kit.*
before the next merge_stages run, or the cached palette silently snaps the new colour to an old one.
"""

from __future__ import annotations

import argparse
import os
import sys

Rgb = tuple[int, int, int]

# The backgrounds the swatches are judged on.
PANEL = (30, 41, 70)  # Theme.MAP_COLOR_PANEL: the Armory screen
STAGE_GLOW = (58, 77, 130)  # the L0 mock's radial centre behind the stage (#3a4d82)
ICON_DARK = (24, 24, 28)  # a dark shelf card
DAYLIGHT = {"forest floor": (106, 127, 63), "grey block": (104, 106, 112), "sky": (180, 205, 235)}

# A swatch at or above this contrast ratio against PANEL may be a silhouette edge.
EDGE_CONTRAST = 2.4


class FOREST:
    """A raider's camp: wood, bone, rope, flint, leather, feathers, red-ochre paint."""

    WOOD_LIGHT = (205, 150, 96)  # freshly carved faces, bow bellies
    WOOD = (164, 108, 64)  # the default wood
    WOOD_DARK = (116, 74, 46)  # heartwood, grain bands (inner)
    BONE = (238, 228, 204)
    BONE_SHADE = (204, 188, 158)  # bone ends, worn bone
    ROPE = (216, 184, 124)  # lashings and bindings
    ROPE_DARK = (168, 134, 86)  # the groove between rope turns
    LEATHER = (156, 96, 60)  # grip wraps
    LEATHER_DARK = (112, 68, 46)  # the groove between leather turns (inner)
    FLINT = (150, 144, 136)  # the knapped face
    FLINT_LIGHT = (212, 206, 194)  # fresh flake scars and the cutting edge
    FLINT_DARK = (102, 98, 96)  # cortex, the median ridge's shadow (inner)
    SINEW = (236, 226, 198)  # bowstrings, thin cords
    OCHRE = (186, 72, 50)  # war paint, dyed feathers
    FEATHER = (242, 238, 228)
    FEATHER_TIP = (70, 62, 60)  # the dark barred tip of a feather (inner, small only)


class CASTLE:
    """A keep's armoury: steel, heraldic crests, gold, oak, dyed cloth."""

    STEEL_LIGHT = (222, 228, 236)  # edges, bevels, polished rims
    STEEL = (170, 178, 194)
    STEEL_DARK = (110, 118, 138)  # fullers, recesses (inner)
    GOLD = (255, 200, 76)
    GOLD_DARK = (206, 146, 48)
    CREST_BLUE = (62, 112, 208)
    CREST_RED = (204, 58, 62)
    OAK = (136, 92, 58)
    CLOTH = (120, 60, 70)  # wine-red grip cloth


class UNDERWORLD:
    """A forge below the world: black iron, embers, ash-white bone, obsidian."""

    IRON_EDGE = (156, 146, 144)  # every black-iron silhouette needs this edge around it
    IRON = (98, 92, 96)
    IRON_BLACK = (64, 60, 66)  # the body of black iron (inner)
    OBSIDIAN = (52, 44, 60)  # glassy black inlays (inner, small only)
    EMBER_HOT = (255, 206, 96)  # the brightest core of a glowing crack
    EMBER = (255, 126, 44)
    EMBER_DEEP = (204, 56, 32)
    ASH_BONE = (200, 188, 174)


class PLANET:
    """A far colony's workshop: white and grey alloy, glow strips, hazard orange."""

    ALLOY_WHITE = (228, 234, 240)
    ALLOY = (178, 188, 202)
    ALLOY_DARK = (98, 108, 126)  # vents and joints (inner)
    GLOW_CYAN = (86, 236, 240)
    GLOW_GREEN = (124, 248, 152)
    HAZARD = (255, 150, 52)
    RUBBER = (82, 86, 98)  # grips (inner)


class DREAM:
    """A place that is not quite real: crystal and pastels, pearl, a deep violet heart."""

    PEARL = (250, 244, 250)
    CRYSTAL_PINK = (255, 184, 224)
    CRYSTAL_LILAC = (202, 172, 255)
    CRYSTAL_MINT = (172, 240, 220)
    PASTEL_BLUE = (172, 208, 255)
    PASTEL_YELLOW = (255, 238, 164)
    CRYSTAL_DEEP = (150, 112, 222)


class FIRE:
    """Fire weapons read fire: these go on nozzles, pilot lights, tanks and scorch marks."""

    FLAME_YELLOW = (255, 216, 92)
    FLAME_ORANGE = (255, 142, 40)
    FLAME_RED = (228, 72, 36)
    SOOT = (58, 50, 50)  # scorch on a nozzle (inner, small only)
    PILOT_BLUE = (96, 164, 255)


class ICE:
    """Ice weapons read ice: rime, clear ice, deep ice."""

    FROST = (238, 250, 255)
    ICE = (178, 230, 255)
    ICE_MID = (112, 192, 242)
    ICE_DEEP = (62, 132, 204)


GROUPS = {
    "forest": FOREST,
    "castle": CASTLE,
    "underworld": UNDERWORLD,
    "planet": PLANET,
    "dream": DREAM,
    "fire": FIRE,
    "ice": ICE,
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
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def role(rgb: Rgb) -> str:
    return "edge" if contrast(rgb, PANEL) >= EDGE_CONTRAST else "inner"


def table() -> str:
    rows = [f"{'swatch':28s} {'sRGB':15s} {'role':5s} {'panel':>6s} {'glow':>6s} {'icon':>6s} " + " ".join(f"{k[:6]:>6s}" for k in DAYLIGHT)]
    for name, rgb in swatches().items():
        cols = [contrast(rgb, PANEL), contrast(rgb, STAGE_GLOW), contrast(rgb, ICON_DARK)] + [contrast(rgb, bg) for bg in DAYLIGHT.values()]
        rows.append(f"{name:28s} {str(rgb):15s} {role(rgb):5s} " + " ".join(f"{c:6.2f}" for c in cols))
    return "\n".join(rows)


def write_sheet(path: str) -> None:
    """Every swatch as a chip on the panel, on the stage glow and on each daylight background."""
    from PIL import Image, ImageDraw, ImageFont

    items = list(swatches().items())
    backs = [("panel", PANEL), ("glow", STAGE_GLOW), ("icon", ICON_DARK)] + list(DAYLIGHT.items())
    cell, label_w, pad = 44, 300, 6
    width = label_w + len(backs) * (cell + pad) + pad
    height = 30 + len(items) * (cell + pad)
    img = Image.new("RGB", (width, height), (16, 16, 18))
    draw = ImageDraw.Draw(img)
    try:
        font = ImageFont.truetype("arial.ttf", 15)
    except OSError:
        font = ImageFont.load_default()
    for i, (bname, _) in enumerate(backs):
        draw.text((label_w + pad + i * (cell + pad), 8), bname[:7], fill=(220, 220, 220), font=font)
    for row, (name, rgb) in enumerate(items):
        y = 30 + row * (cell + pad)
        draw.text((8, y + 6), f"{name} {rgb}", fill=(230, 230, 230), font=font)
        draw.text((8, y + 24), f"{role(rgb)}  panel {contrast(rgb, PANEL):.2f}", fill=(150, 150, 150), font=font)
        for i, (_, back) in enumerate(backs):
            x = label_w + pad + i * (cell + pad)
            draw.rectangle([x, y, x + cell, y + cell], fill=back)
            draw.rectangle([x + 10, y + 10, x + cell - 10, y + cell - 10], fill=rgb)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    print(f"[weapon-palette] wrote {path}")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Print the weapon kit's swatches and their contrast.")
    parser.add_argument("--sheet", action="store_true", help="also write assets/testfit/out/Weapons/_palette.png")
    args = parser.parse_args(argv)
    print(table())
    names = swatches()
    if len(set(names.values())) != len(names):
        dupes = sorted({n for n, c in names.items() if list(names.values()).count(c) > 1})
        print(f"[weapon-palette] two names share one colour: {', '.join(dupes)}")
        return 1
    if args.sheet:
        repo = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
        write_sheet(os.path.join(repo, "assets", "testfit", "out", "Weapons", "_palette.png"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
