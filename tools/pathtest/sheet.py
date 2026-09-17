"""Compose tools/pathtest/out/renders/<view>_<A|B|C>.png into one contact sheet per scale.

    py tools/pathtest/sheet.py      # writes out/renders/sheet.png (full) and sheet_small.png (1/3 size)

Rows are junction / near / mid / far, columns A / B / C / C2 / C3. The small sheet is the honest
one: a path that only reads at full size will not read on a phone.
"""

from pathlib import Path

from PIL import Image, ImageDraw

RENDERS = Path(__file__).resolve().parent / "out" / "renders"
VIEWS = ("junction", "near", "mid", "far")
VARIANTS = ("A", "B", "C", "C2", "C3")


def main():
    tiles = {(v, x): Image.open(RENDERS / f"{v}_{x}.png").convert("RGB") for v in VIEWS for x in VARIANTS if (RENDERS / f"{v}_{x}.png").exists()}
    if not tiles:
        raise SystemExit("no renders; run render.py first")
    w, h = next(iter(tiles.values())).size
    gap = 6
    cols = len(VARIANTS)
    sheet = Image.new("RGB", (w * cols + gap * (cols - 1), h * len(VIEWS) + gap * (len(VIEWS) - 1)), (25, 25, 25))
    for r, view in enumerate(VIEWS):
        for c, variant in enumerate(VARIANTS):
            im = tiles.get((view, variant))
            if im is None:
                continue
            ImageDraw.Draw(im).rectangle((0, 0, 150, 44), fill=(0, 0, 0))
            ImageDraw.Draw(im).text((10, 12), f"{variant}  {view}", fill=(255, 255, 255))
            sheet.paste(im, (c * (w + gap), r * (h + gap)))
    sheet.save(RENDERS / "sheet.png")
    sheet.resize((sheet.width // 5, sheet.height // 5), Image.LANCZOS).save(RENDERS / "sheet_small.png")
    print("wrote", RENDERS / "sheet.png", "and sheet_small.png")


if __name__ == "__main__":
    main()
