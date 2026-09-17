"""Compose growth_f*.png side by side into growth_strip.png (system py, Pillow)."""

import sys
from pathlib import Path

from PIL import Image, ImageDraw

out = Path(sys.argv[1])
frames = sorted(out.glob("growth_f*.png"))
images = [Image.open(p).convert("RGB") for p in frames]
w, h = images[0].size
strip = Image.new("RGB", (w * len(images) + 8 * (len(images) - 1), h), (30, 30, 30))
for i, im in enumerate(images):
    ImageDraw.Draw(im).text((12, 10), f"{(i + 1) * 100 // len(images)}%", fill=(255, 255, 255))
    strip.paste(im, (i * (w + 8), 0))
strip.save(out / "growth_strip.png")
print("wrote", out / "growth_strip.png")
