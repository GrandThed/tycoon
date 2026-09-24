#!/usr/bin/env python
"""Experience thumbnails from real Studio screenshots: crop to 1920x1080, add one chunky caption.

    py tools/marketing/caption.py                       # every shot in shots.json
    py tools/marketing/caption.py --check               # + a copy with the tile band shaded
    py tools/marketing/caption.py --only growth,scale_metropolis
    py tools/marketing/caption.py --in shot.png --caption "BUILD A METROPOLIS" --focus 0.5,0.45 --out x.png
    py tools/marketing/caption.py --in lo.png --in hi.png --caption "LEVEL IT UP!" --labels "LV 1,LV 100" --out x.png

The shot list is tools/marketing/shots.json (how to take each screenshot: SHOTLIST.md next to it).
Sources live in assets/marketing/screenshots/, finals land in assets/marketing/final/thumbs/<id>.png
and, with --check, <id>_check.png beside them with the bottom 15 % shaded -- the strip Roblox's
tile overlay covers, which must hold nothing important.

The layout follows the number of sources, each cropped around its own `focus` (0..1 of the source
width and height, default the centre):
  * one source: cover-cropped to 16:9, caption at the top;
  * two sources: a 2-up, each half 960x1080, a white divider and a fat arrow between them, and
    optional `labels` over the tile band naming the halves (the Growth hook: the same building at
    a low and a high stage);
  * three or more: slices, equal columns with leaning white edges and one `label` per column at
    the top (the Eras hook: one screenshot per era, Village left to Orbital right); a slices shot
    has its labels instead of a caption.
Text is Titan One (OFL, assets/marketing/fonts/), chunky and outlined; a caption is at most five
words and shrinks to fit the width. Nothing is drawn but caption, labels, arrow and dividers: no
fake UI.

Runs under `py` (Pillow). A missing source is reported and skipped, never a crash, so the set can
be regenerated while Ben is still taking screenshots.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

REPO_ROOT = Path(__file__).resolve().parents[2]
SHOTS_FILE = Path(__file__).with_name("shots.json")
SOURCE_DIR = REPO_ROOT / "assets" / "marketing" / "screenshots"
OUT_DIR = REPO_ROOT / "assets" / "marketing" / "final" / "thumbs"
FONT_PATH = REPO_ROOT / "assets" / "marketing" / "fonts" / "TitanOne-Regular.ttf"

SIZE = (1920, 1080)
MAX_BYTES = 3 * 1024 * 1024
TILE_BAND = 0.15  # Roblox's tile overlay covers this fraction of the height, from the bottom
MAX_WORDS = 5
CAPTION_PX = 128
CAPTION_Y = 0.12  # caption centre, as a fraction of the height
CAPTION_MAX_WIDTH = 0.9
LABEL_PX = 84
LABEL_Y = 0.74  # 2-up half labels sit just above the tile band
CAPTION_FILL = (255, 214, 60)
CAPTION_GLOSS = (255, 240, 150)
OUTLINE = (30, 26, 60)
ARROW_FILL = (255, 205, 40)
DIVIDER = 10
SLANT = 70  # half the horizontal lean of a slice edge, in pixels
SLICE_LABEL_Y = 0.1
SLICE_COLOURS = ((255, 226, 120), (255, 180, 120), (170, 220, 255), (200, 170, 255))


def font(px):
    return ImageFont.truetype(str(FONT_PATH), px)


def stroke_for(px):
    return max(4, px // 9)


def text_width(message, px):
    box = ImageDraw.Draw(Image.new("L", (1, 1))).textbbox((0, 0), message, font=font(px), stroke_width=stroke_for(px))
    return box[2] - box[0]


def text(canvas, message, centre, px, fill=(255, 255, 255), gloss=None):
    """Chunky outlined text with a soft drop shadow, centred on `centre`."""
    face = font(px)
    stroke = stroke_for(px)
    draw = ImageDraw.Draw(canvas)
    box = draw.textbbox((0, 0), message, font=face, stroke_width=stroke)
    x = centre[0] - (box[2] - box[0]) / 2 - box[0]
    y = centre[1] - (box[3] - box[1]) / 2 - box[1]
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).text(
        (x + px * 0.06, y + px * 0.09), message, font=face, fill=(0, 0, 0, 150), stroke_width=stroke, stroke_fill=(0, 0, 0, 150)
    )
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(px * 0.06)))
    draw.text((x, y), message, font=face, fill=fill, stroke_width=stroke, stroke_fill=OUTLINE)
    if gloss:
        # A lighter top half gives the caption the glossy two-tone read of front-page titles.
        top = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        ImageDraw.Draw(top).text((x, y), message, font=face, fill=gloss)
        cut = Image.new("L", canvas.size, 0)
        ImageDraw.Draw(cut).rectangle((0, 0, canvas.size[0], y + box[1] + (box[3] - box[1]) * 0.48), fill=255)
        top.putalpha(ImageChops.multiply(top.getchannel("A"), cut))
        canvas.alpha_composite(top)


def arrow(canvas, centre, length=260, width=80):
    """A fat right-pointing arrow centred on `centre` (pixels)."""
    cx, cy = centre
    head = width * 1.1
    half = width / 2
    x0 = cx - length / 2
    shape = [
        (0, -half),
        (length - head, -half),
        (length - head, -width),
        (length, 0),
        (length - head, width),
        (length - head, half),
        (0, half),
    ]
    points = [(x0 + x, cy + y) for x, y in shape]
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).polygon([(x + 6, y + 9) for x, y in points], fill=(0, 0, 0, 140))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(6)))
    ImageDraw.Draw(canvas).polygon(points, fill=ARROW_FILL, outline=OUTLINE, width=9)


def cover(image, size, focus):
    """Scale `image` to cover `size` and crop it there, keeping `focus` (0..1 of the source) as
    near the middle of the crop as the image edges allow."""
    scale = max(size[0] / image.width, size[1] / image.height)
    scaled = image.resize((round(image.width * scale), round(image.height * scale)), Image.LANCZOS)
    fx, fy = focus
    left = min(max(fx * scaled.width - size[0] / 2, 0), scaled.width - size[0])
    top = min(max(fy * scaled.height - size[1] / 2, 0), scaled.height - size[1])
    return scaled.crop((round(left), round(top), round(left) + size[0], round(top) + size[1]))


def check_caption(caption):
    words = caption.split()
    if len(words) > MAX_WORDS:
        raise SystemExit(f"caption {caption!r} has {len(words)} words; the limit is {MAX_WORDS}")


def compose(sources, caption, focus=None, labels=None):
    """The finished 1920x1080 RGBA canvas for one shot."""
    w, h = SIZE
    focus = focus or [[0.5, 0.5]] * len(sources)
    images = [Image.open(path).convert("RGB") for path in sources]
    if len(images) == 1:
        canvas = cover(images[0], SIZE, focus[0]).convert("RGBA")
    elif len(images) == 2:
        canvas = Image.new("RGBA", SIZE)
        half = (w // 2, h)
        canvas.paste(cover(images[0], half, focus[0]), (0, 0))
        canvas.paste(cover(images[1], half, focus[1]), (w // 2, 0))
        draw = ImageDraw.Draw(canvas)
        draw.rectangle((w // 2 - DIVIDER - 4, 0, w // 2 + DIVIDER + 4, h), fill=OUTLINE)
        draw.rectangle((w // 2 - DIVIDER, 0, w // 2 + DIVIDER, h), fill=(255, 255, 255))
        arrow(canvas, (w / 2, h * 0.5))
        for index, label in enumerate(labels or []):
            text(canvas, label, (w * (0.25 + 0.5 * index), h * LABEL_Y), LABEL_PX)
    else:
        if caption:
            raise SystemExit("a slices shot is labelled per column; give it labels, not a caption")
        canvas = slices(images, focus, labels or [])
    if caption:
        check_caption(caption)
        px = CAPTION_PX
        while px > 40 and text_width(caption, px) > w * CAPTION_MAX_WIDTH:
            px -= 4
        text(canvas, caption, (w / 2, h * CAPTION_Y), px, fill=CAPTION_FILL, gloss=CAPTION_GLOSS)
    return canvas


def slices(images, focus, labels):
    """Equal columns with leaning edges. Each column is cropped from its own screenshot, scaled
    to the full frame height so the subject keeps its size, around that shot's focus."""
    w, h = SIZE
    count = len(images)
    column = w / count
    canvas = Image.new("RGBA", SIZE, (0, 0, 0, 255))
    # Wide enough that the lean never shows the column's own edge.
    tile = (round(column + 4 * SLANT), h)
    edges = []
    for index, image in enumerate(images):
        x0, x1 = index * column, (index + 1) * column
        left = (x0 + SLANT, x0 - SLANT) if index else (-2 * SLANT, -2 * SLANT)
        right = (x1 + SLANT, x1 - SLANT) if index < count - 1 else (w + 2 * SLANT, w + 2 * SLANT)
        mask = Image.new("L", SIZE, 0)
        ImageDraw.Draw(mask).polygon([(left[0], 0), (right[0], 0), (right[1], h), (left[1], h)], fill=255)
        layer = Image.new("RGBA", SIZE, (0, 0, 0, 0))
        layer.paste(cover(image, tile, focus[index]), (round(x0 - 2 * SLANT), 0))
        canvas.paste(layer, (0, 0), mask)
        if index:
            edges.append(((left[0], 0), (left[1], h)))
    draw = ImageDraw.Draw(canvas)
    for top, bottom in edges:
        draw.line([top, bottom], fill=OUTLINE, width=14)
        draw.line([top, bottom], fill=(255, 255, 255), width=7)
    if labels:
        # One size for every label: the largest at which the longest still fits its column.
        px = LABEL_PX
        while px > 30 and max(text_width(label, px) for label in labels) > column * 0.88:
            px -= 2
        for index, label in enumerate(labels):
            colour = SLICE_COLOURS[index % len(SLICE_COLOURS)]
            text(canvas, label, (column * (index + 0.5), h * SLICE_LABEL_Y), px, fill=colour)
    return canvas


def shade_band(canvas):
    """The --check view: darken the strip the tile overlay covers and outline its edge."""
    w, h = SIZE
    top = round(h * (1 - TILE_BAND))
    band = Image.new("RGBA", SIZE, (0, 0, 0, 0))
    draw = ImageDraw.Draw(band)
    draw.rectangle((0, top, w, h), fill=(0, 0, 0, 150))
    draw.line((0, top, w, top), fill=(255, 60, 60, 255), width=4)
    out = canvas.copy()
    out.alpha_composite(band)
    return out


def save(canvas, out):
    out.parent.mkdir(parents=True, exist_ok=True)
    rgb = canvas.convert("RGB")
    rgb.save(out, optimize=True)
    if out.stat().st_size > MAX_BYTES:
        # A busy screenshot can pass 3 MB as a PNG; an adaptive 256-colour palette with dithering
        # keeps the look and fits Roblox's limit.
        rgb.quantize(256, dither=Image.Dither.FLOYDSTEINBERG).save(out, optimize=True)
    return out.stat().st_size


def render(shot_id, sources, caption, focus, labels, out, check):
    missing = [str(path) for path in sources if not Path(path).exists()]
    if missing:
        print(f"   {shot_id}: SKIPPED, missing {', '.join(missing)}")
        return
    canvas = compose(sources, caption, focus, labels)
    size = save(canvas, out)
    print(f"   {shot_id}: {out} ({size / 1e6:.2f} MB)")
    if check:
        save(shade_band(canvas), out.with_name(f"{out.stem}_check.png"))


def parse_focus(values):
    return [[float(v) for v in value.split(",")] for value in values] if values else None


def main():
    parser = argparse.ArgumentParser(prog="caption.py", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--only", help="comma list of shot ids from shots.json")
    parser.add_argument("--check", action="store_true", help="also write <id>_check.png with the tile band shaded")
    parser.add_argument("--in", dest="sources", action="append", help="ad-hoc: a source image (twice: 2-up, 3+: slices)")
    parser.add_argument("--caption", default="", help="ad-hoc: caption text, at most five words")
    parser.add_argument("--focus", action="append", help="ad-hoc: x,y in 0..1, once per --in")
    parser.add_argument("--labels", help="ad-hoc 2-up or slices: comma list of labels, one per source")
    parser.add_argument("--out", help="ad-hoc: output PNG")
    args = parser.parse_args()

    if args.sources:
        if not args.out:
            raise SystemExit("--in needs --out")
        labels = [part.strip() for part in args.labels.split(",")] if args.labels else None
        render("ad-hoc", args.sources, args.caption, parse_focus(args.focus), labels, Path(args.out), args.check)
        return

    shots = json.loads(SHOTS_FILE.read_text(encoding="utf-8"))["shots"]
    if args.only:
        wanted = {part.strip() for part in args.only.split(",")}
        unknown = wanted - {shot["id"] for shot in shots}
        if unknown:
            raise SystemExit(f"unknown shot id(s): {', '.join(sorted(unknown))}")
        shots = [shot for shot in shots if shot["id"] in wanted]
    for shot in shots:
        sources = [SOURCE_DIR / name for name in shot["sources"]]
        render(
            shot["id"],
            sources,
            shot.get("caption", ""),
            shot.get("focus"),
            shot.get("labels"),
            OUT_DIR / f"{shot['id']}.png",
            args.check,
        )


if __name__ == "__main__":
    sys.exit(main())
