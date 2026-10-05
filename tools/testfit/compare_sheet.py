#!/usr/bin/env python
"""Compose plot renders into one labelled comparison sheet, like the gate sheets Ben judges
(assets/testfit/out/Boomtown/m12b_compare.png): a dark title row naming the columns, a dark label
column naming the rows, and every render scaled to one cell size.

    py tools/testfit/compare_sheet.py --out assets/testfit/out/Metropolis/m12m_compare.png \
        --cols "Tier 1,Tier 3,Full" \
        --row "Today=m12m_today_tier1.png,m12m_today_tier3.png,m12m_today_full.png" \
        --row "Boulevard=m12m_boulevard_tier1.png,m12m_boulevard_tier3.png,m12m_boulevard_full.png" \
        --dir assets/testfit/out/Metropolis

    py tools/testfit/compare_sheet.py --out assets/testfit/out/OrbitalColony/m12o_compare.png \
        --cols "Tier 1,Tier 3,Full" --dir assets/testfit/out/OrbitalColony \
        --row "Today=m12o_today_tier1.png|4 modules,m12o_today_tier3.png|15 modules,m12o_today_full.png|24 modules, 7 domes" \
        --row "Docks=m12o_docks_tier1.png,m12o_docks_tier3.png,m12o_docks_full.png" \
        --row "Axis=m12o_axis_tier1.png,m12o_axis_tier3.png,m12o_axis_full.png"

A relative image path is read from `--dir` (default: the current directory). A missing image leaves
its cell dark with the file name in it, so a sheet can be made while a render is still running.
`image|caption` writes a caption on that cell, bottom left on a dark band -- the lot count of a
render that does not carry one (plotrender.py `--label` stamps its own, and needs none here).
Labels are set in Titan One (assets/marketing/fonts/) when it is there, else Pillow's default face.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

REPO_ROOT = Path(__file__).resolve().parents[2]
FONT_PATH = REPO_ROOT / "assets" / "marketing" / "fonts" / "TitanOne-Regular.ttf"
BACKGROUND = (24, 24, 28)
INK = (245, 245, 245)
MISSING_FILL = (44, 44, 50)
MISSING_INK = (150, 150, 158)
# Proportions of the Boomtown gate sheet: 800-wide cells, a 230 px label column, a 70 px title row.
DEFAULT_CELL_WIDTH = 800
LABEL_SHARE = 230 / 800  # label column width per cell width
HEAD_SHARE = 70 / 800  # column-title row height per cell width
TITLE_SHARE = 60 / 800  # optional sheet-title band height per cell width
LABEL_FONT_SHARE = 0.55  # of the head row's height
TITLE_FONT_SHARE = 0.55
CAPTION_SHARE = 0.036  # a cell caption's text height per cell height, as plotrender's `--label`
CAPTION_BAND = (24, 24, 28, 200)


def font(size):
    try:
        return ImageFont.truetype(str(FONT_PATH), size)
    except OSError:
        try:
            return ImageFont.load_default(size)
        except TypeError:
            return ImageFont.load_default()


def parse_row(text):
    """'Label=a.png,b.png|a caption' -> ('Label', ['a.png', 'b.png'], [None, 'a caption']). Cells are
    cut at the commas that follow an image name, so a caption may hold commas of its own."""
    if "=" not in text:
        raise SystemExit(f"--row {text!r}: expected Label=image,image,...")
    label, cells = text.split("=", 1)
    images, captions = [], []
    for part in re.split(r",(?=[^,|]*\.png)", cells, flags=re.IGNORECASE):
        image, _, caption = part.partition("|")
        images.append(image.strip())
        captions.append(caption.strip() or None)
    return label.strip(), images, captions


def caption_cell(sheet, box, text):
    """One cell's caption: bottom left of `box`, on a dark band, in the sheet's face."""
    left, top, right, bottom = box
    size = max(round((bottom - top) * CAPTION_SHARE), 10)
    face = font(size)
    layer = Image.new("RGBA", sheet.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    bounds = draw.textbbox((0, 0), text, font=face)
    pad = size // 2
    band_top = bottom - (bounds[3] - bounds[1]) - 2 * pad
    draw.rectangle((left, band_top, min(left + bounds[2] - bounds[0] + 2 * pad, right), bottom), fill=CAPTION_BAND)
    draw.text((left + pad - bounds[0], band_top + pad - bounds[1]), text, font=face, fill=INK)
    sheet.paste(Image.alpha_composite(sheet.convert("RGBA"), layer).convert("RGB"))


def centred_text(draw, box, text, face):
    left, top, right, bottom = box
    bounds = draw.textbbox((0, 0), text, font=face)
    width, height = bounds[2] - bounds[0], bounds[3] - bounds[1]
    draw.text(((left + right - width) / 2 - bounds[0], (top + bottom - height) / 2 - bounds[1]), text, font=face, fill=INK)


def wrapped(draw, text, face, width):
    """The label broken into lines no wider than `width` (whole words; a long word stands alone)."""
    lines, line = [], ""
    for word in text.split():
        trial = f"{line} {word}".strip()
        if line and draw.textlength(trial, font=face) > width:
            lines.append(line)
            line = word
        else:
            line = trial
    return lines + ([line] if line else [])


def compose(out, columns, rows, base, cell_width, title=None):
    paths = [[(base / image) if not Path(image).is_absolute() else Path(image) for image in images] for _, images, _ in rows]
    first = next((path for row in paths for path in row if path.exists()), None)
    if first is None:
        raise SystemExit("compare_sheet: none of the images exists")
    with Image.open(first) as probe:
        cell_height = round(cell_width * probe.height / probe.width)
    label_width = round(cell_width * LABEL_SHARE)
    head_height = round(cell_width * HEAD_SHARE)
    title_height = round(cell_width * TITLE_SHARE) if title else 0
    width = label_width + cell_width * len(columns)
    height = title_height + head_height + cell_height * len(rows)
    sheet = Image.new("RGB", (width, height), BACKGROUND)
    draw = ImageDraw.Draw(sheet)
    head_face = font(round(head_height * LABEL_FONT_SHARE))
    if title:
        centred_text(draw, (0, 0, width, title_height), title, font(round(title_height * TITLE_FONT_SHARE)))
    for c, name in enumerate(columns):
        left = label_width + c * cell_width
        centred_text(draw, (left, title_height, left + cell_width, title_height + head_height), name, head_face)
    for r, ((label, _, captions), row_paths) in enumerate(zip(rows, paths)):
        top = title_height + head_height + r * cell_height
        lines = wrapped(draw, label, head_face, label_width - 16)
        line_height = round(head_height * LABEL_FONT_SHARE * 1.25)
        start = top + (cell_height - line_height * len(lines)) / 2
        for k, line in enumerate(lines):
            centred_text(draw, (0, start + k * line_height, label_width, start + (k + 1) * line_height), line, head_face)
        for c in range(len(columns)):
            left = label_width + c * cell_width
            path = row_paths[c] if c < len(row_paths) else None
            if path is not None and path.exists():
                with Image.open(path) as image:
                    sheet.paste(image.convert("RGB").resize((cell_width, cell_height), Image.LANCZOS), (left, top))
                if c < len(captions) and captions[c]:
                    caption_cell(sheet, (left, top, left + cell_width, top + cell_height), captions[c])
                    draw = ImageDraw.Draw(sheet)
            else:
                draw.rectangle((left, top, left + cell_width - 1, top + cell_height - 1), fill=MISSING_FILL)
                name = path.name if path is not None else "(no image)"
                centred_text(draw, (left, top, left + cell_width, top + cell_height), f"missing: {name}", font(round(head_height * 0.3)))
                print(f"   missing: {path}")
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)
    return sheet.size


def main(argv):
    parser = argparse.ArgumentParser(prog="compare_sheet.py", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", required=True, type=Path, help="the sheet to write (.png)")
    parser.add_argument("--cols", required=True, help="column titles, comma-separated")
    parser.add_argument("--row", action="append", required=True, help="Label=image,image,... (one per row, in order)")
    parser.add_argument("--dir", type=Path, default=Path.cwd(), help="where relative image paths are read from")
    parser.add_argument("--cell", type=int, default=DEFAULT_CELL_WIDTH, help=f"cell width in px (default {DEFAULT_CELL_WIDTH})")
    parser.add_argument("--title", help="an optional title band above the column titles")
    args = parser.parse_args(argv)
    columns = [part.strip() for part in args.cols.split(",")]
    rows = [parse_row(text) for text in args.row]
    for label, images, _ in rows:
        if len(images) != len(columns):
            raise SystemExit(f"row {label!r} has {len(images)} images for {len(columns)} columns")
    size = compose(args.out, columns, rows, args.dir, args.cell, args.title)
    print(f"wrote {args.out} ({size[0]} x {size[1]})")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
