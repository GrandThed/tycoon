"""Lay testfit's weapon renders on the Armory panel: the strip, the icon and its shelf check (L3).

Run with `py` (Pillow). testfit.py's weapon view calls it with a spec it wrote; by hand:

    py tools/testfit/weaponstrip.py --spec assets/testfit/out/Weapons/_raw/Longbow_spec.json
    py tools/testfit/weaponstrip.py --sheet assets/testfit/out/Weapons      # every strip + icon row

The background is the screen's panel colour (30, 41, 70) with the L0 mock's lighter radial behind
the weapon (#3a4d82 at the centre, fading to the panel at 62 percent, centred 62 percent down), the
colours read from weapon_kit_palette so the judging card and the swatch table cannot disagree.
"""

from __future__ import annotations

import argparse
import glob
import json
import math
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFont

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets"))
import weapon_kit_palette as pal  # noqa: E402

GAP = 8
HEADER = 64
ICON_SIZES = (64, 128)
UNOWNED_TINT = (18, 20, 26)  # the shelf's "not found yet" silhouette: ImageColor3 near black


def font(size: int):
    for name in ("arialbd.ttf", "arial.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def radial(size, centre=(0.5, 0.62), stop=0.62, inner=pal.STAGE_GLOW, outer=pal.PANEL) -> Image.Image:
    """CSS radial-gradient(ellipse at 50% 62%, inner 0%, outer 62%), computed at a quarter size."""
    w, h = size
    sw, sh = max(1, w // 4), max(1, h // 4)
    cx, cy = centre[0] * sw, centre[1] * sh
    rx, ry = max(cx, sw - cx) * math.sqrt(2), max(cy, sh - cy) * math.sqrt(2)
    img = Image.new("RGB", (sw, sh))
    px = img.load()
    for y in range(sh):
        for x in range(sw):
            d = math.hypot((x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry) / stop
            t = min(1.0, d)
            px[x, y] = tuple(round(a + (b - a) * t) for a, b in zip(inner, outer))
    return img.resize((w, h), Image.BILINEAR)


def on(background: Image.Image, render: Image.Image) -> Image.Image:
    out = background.convert("RGBA")
    out.alpha_composite(render.convert("RGBA"))
    return out.convert("RGB")


def tinted(icon: Image.Image, rgb) -> Image.Image:
    """What ImageColor3 does to an image with alpha: multiply every pixel's colour by the tint."""
    r, g, b, a = icon.split()
    mult = ImageChops.multiply(Image.merge("RGB", (r, g, b)), Image.new("RGB", icon.size, rgb))
    return Image.merge("RGBA", (*mult.split(), a))


def icon_check(icon: Image.Image, path: str, title: str) -> None:
    backs = [("card", pal.ICON_DARK), ("panel", pal.PANEL), ("stage", pal.STAGE_GLOW)]
    cells = []
    for size in ICON_SIZES:
        small = icon.resize((size, size), Image.LANCZOS)
        for name, rgb in backs:
            cells.append((f"{name} {size}", on(Image.new("RGB", (size, size), rgb), small)))
    dark = tinted(icon, UNOWNED_TINT).resize((64, 64), Image.LANCZOS)
    cells.append(("unowned 64", on(Image.new("RGB", (64, 64), pal.PANEL), dark)))
    small = icon.resize((64, 64), Image.LANCZOS)
    for name, rgb in pal.DAYLIGHT.items():  # in the world: the same colours on daylight backgrounds
        cells.append((name.split()[0] + " 64", on(Image.new("RGB", (64, 64), rgb), small)))
    f = font(13)
    probe = ImageDraw.Draw(Image.new("RGB", (1, 1)))
    widths = [max(c.width, int(probe.textlength(label, font=f))) for label, c in cells]
    width = sum(widths) + GAP * (len(cells) + 1)
    height = 128 + 54
    sheet = Image.new("RGB", (width, height), (12, 12, 14))
    d = ImageDraw.Draw(sheet)
    d.text((GAP, 4), title, fill=(230, 230, 230), font=font(15))
    x = GAP
    for (label, cell), w in zip(cells, widths):
        sheet.paste(cell, (x, 28 + (128 - cell.height)))
        d.text((x, 28 + 128 + 4), label, fill=(170, 170, 170), font=f)
        x += w + GAP
    sheet.save(path)


def compose(spec: dict) -> None:
    out = spec["out"]
    sid = spec["id"]
    raws = spec["raws"]
    side = Image.open(raws["side"]).convert("RGBA")
    stage = Image.open(raws["stage"]).convert("RGBA")
    panels = [
        ("side, beside a 5-stud R15", on(radial(side.size), side)),
        ("three-quarter, as on the stage", on(radial(stage.size), stage)),
    ]
    width = sum(p.width for _, p in panels) + GAP * (len(panels) + 1)
    height = HEADER + max(p.height for _, p in panels) + GAP
    strip = Image.new("RGB", (width, height), (14, 16, 22))
    d = ImageDraw.Draw(strip)
    tris = spec.get("triangles")
    sz = spec["size"]
    d.text((GAP + 4, 8), f"{sid}    {tris if tris is not None else '?'} tris    {spec['length']:.2f} studs long    "
           f"({sz[0]:.2f} x {sz[1]:.2f} x {sz[2]:.2f})", fill=(240, 240, 240), font=font(22))
    x = GAP + 4
    small = font(15)
    for name, p in spec["frame"].items():
        rgb = tuple(spec["markers"].get(name, (235, 235, 235)))
        d.ellipse([x, 42, x + 12, 54], fill=rgb)
        label = f"{name} ({p[0]:g}, {p[1]:g}, {p[2]:g})"
        d.text((x + 17, 39), label, fill=(210, 210, 210), font=small)
        x += 17 + int(d.textlength(label, font=small)) + 22
    x = GAP
    for label, p in panels:
        strip.paste(p, (x, HEADER))
        d.text((x + 10, HEADER + 8), label, fill=(170, 186, 220), font=small)
        x += p.width + GAP
    strip_path = os.path.join(out, f"{sid}_strip.png")
    strip.save(strip_path)
    print(f"wrote {strip_path}")

    icon = Image.open(raws["icon"]).convert("RGBA")
    icon_path = os.path.join(out, f"{sid}_icon.png")
    icon.save(icon_path)
    print(f"wrote {icon_path}")
    check_path = os.path.join(out, f"{sid}_icon_check.png")
    icon_check(icon, check_path, f"{sid} icon at shelf sizes")
    print(f"wrote {check_path}")


def sheet(folder: str) -> None:
    """Every weapon's strip stacked, then a row of every icon at 128 px on the panel."""
    strips = sorted(glob.glob(os.path.join(folder, "*_strip.png")))
    icons = sorted(glob.glob(os.path.join(folder, "*_icon.png")))
    rows = [Image.open(p).convert("RGB") for p in strips]
    width = max([r.width for r in rows] + [GAP + len(icons) * (128 + GAP)])
    row_h = 128 + 2 * GAP
    height = sum(r.height + GAP for r in rows) + row_h
    out = Image.new("RGB", (width, height), (14, 16, 22))
    y = 0
    for r in rows:
        out.paste(r, (0, y))
        y += r.height + GAP
    x = GAP
    for p in icons:
        icon = Image.open(p).convert("RGBA").resize((128, 128), Image.LANCZOS)
        out.paste(on(radial((128, 128)), icon), (x, y + GAP))
        x += 128 + GAP
    path = os.path.join(folder, "_contact.png")
    out.save(path)
    print(f"wrote {path} ({len(rows)} strips, {len(icons)} icons)")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--spec", help="the JSON testfit's weapon view wrote")
    parser.add_argument("--sheet", help="a folder of weapon strips and icons to stack into _contact.png")
    args = parser.parse_args()
    if args.spec:
        with open(args.spec, "r", encoding="utf-8") as fh:
            compose(json.load(fh))
    if args.sheet:
        sheet(args.sheet)
    if not (args.spec or args.sheet):
        parser.print_help()
    return 0


if __name__ == "__main__":
    sys.exit(main())
