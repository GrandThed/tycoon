"""Compose the five stage renders into one labelled strip. Run with `py`; needs Pillow."""

import argparse
import os

from PIL import Image, ImageDraw, ImageFont

LABELS = ["stage 0 (buy)", "stage 1 (L10)", "stage 2 (L25)", "stage 3 (L50)", "stage 4 (L100)"]
THUMB_WIDTH = 640
LABEL_HEIGHT = 44
GAP = 8


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    parser.add_argument("stages", nargs="+")
    args = parser.parse_args()

    try:
        font = ImageFont.truetype("arial.ttf", 26)
    except OSError:
        font = ImageFont.load_default()

    thumbs = []
    for path in args.stages:
        img = Image.open(path).convert("RGB")
        ratio = THUMB_WIDTH / img.width
        thumbs.append(img.resize((THUMB_WIDTH, int(img.height * ratio)), Image.LANCZOS))

    height = max(t.height for t in thumbs)
    width = len(thumbs) * THUMB_WIDTH + (len(thumbs) + 1) * GAP
    strip = Image.new("RGB", (width, height + LABEL_HEIGHT + GAP * 2), (245, 245, 245))
    draw = ImageDraw.Draw(strip)
    for i, thumb in enumerate(thumbs):
        x = GAP + i * (THUMB_WIDTH + GAP)
        strip.paste(thumb, (x, GAP + LABEL_HEIGHT))
        label = LABELS[i] if i < len(LABELS) else os.path.basename(args.stages[i])
        draw.text((x + 8, GAP + 8), label, fill=(20, 20, 20), font=font)

    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    strip.save(args.out)
    print(f"[strip] wrote {args.out}")


if __name__ == "__main__":
    main()
