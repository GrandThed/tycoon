"""VIP colourway per kit: a luminance gradient map applied to the kit's colormap (or palette), and
a one-piece "swatch" GLB that carries the recoloured image so Open Cloud hands back an Image asset.

VIP is a texture swap at runtime (`MeshPart.TextureID`), so one recoloured colormap per kit skins
every building of that kit. Roblox splits an embedded texture into its own Image asset on import;
the swatch's only job is to get that Image asset created and its id harvested.

    py tools/assets/vip_palette.py --kit fantasy-town-kit --era Village [--kit nature-kit] [--out assets/build/vip]

Textured kits embed the recoloured `Textures/colormap.png` into the kit's smallest piece. Palette
kits (material colours, see palette.py) recolour their palette PNG onto a generated quad, because a
raw kit piece has no palette UVs. Runs under `py` (needs Pillow).
"""

from __future__ import annotations

import argparse
import io
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import glbtools  # noqa: E402
import palette  # noqa: E402

REPO_ROOT = palette.REPO_ROOT
VIP_DIR = os.path.join(REPO_ROOT, "assets", "build", "vip")

# Gradient stops from dark to light, per era (assets/research/2026-09-15/vip_palette.py).
STOPS = {
    "Village": ["#24123A", "#6B3FA0", "#D9A935", "#FFF1C9"],
    "Boomtown": ["#0F1A2A", "#2BB5C8", "#C9D3DE", "#FFFFFF"],
    "Metropolis": ["#0B0C10", "#2A2E36", "#B8913A", "#F3DC9A"],
    "OrbitalColony": ["#1C2A3A", "#3FB6D9", "#DCE6EE", "#FFFFFF"],
}
DEFAULT_ERA = "Village"
# How much of the original hue survives; keeps roofs and walls distinguishable under the gold.
KEEP_ORIGINAL = 0.12


def log(msg: str) -> None:
    print(f"[vip] {msg}", flush=True)


def _rgb(h: str) -> tuple[int, int, int]:
    return tuple(int(h[i : i + 2], 16) for i in (1, 3, 5))  # type: ignore[return-value]


def lut(era: str) -> list[tuple[int, int, int]]:
    stops = [_rgb(s) for s in STOPS.get(era, STOPS[DEFAULT_ERA])]
    table = []
    for v in range(256):
        t = v / 255 * (len(stops) - 1)
        i = min(int(t), len(stops) - 2)
        f = t - i
        table.append(tuple(round(stops[i][c] + (stops[i + 1][c] - stops[i][c]) * f) for c in range(3)))
    return table  # type: ignore[return-value]


def recolor(img: Image.Image, era: str) -> Image.Image:
    table = lut(era)
    src = img.convert("RGBA")
    px = src.load()
    out = Image.new("RGBA", src.size)
    op = out.load()
    for y in range(src.height):
        for x in range(src.width):
            r, g, b, a = px[x, y]
            lum = int(0.2126 * r + 0.7152 * g + 0.0722 * b)
            mr, mg, mb = table[lum]
            k = KEEP_ORIGINAL
            op[x, y] = (round(mr + (r - mr) * k), round(mg + (g - mg) * k), round(mb + (b - mb) * k), a)
    return out


def png_bytes(img: Image.Image) -> bytes:
    buf = io.BytesIO()
    img.save(buf, format="PNG", optimize=True)
    return buf.getvalue()


def kit_colormap(kit: str) -> str | None:
    folder = palette.kit_model_dir(kit)
    if folder is None:
        return None
    path = os.path.join(folder, "Textures", "colormap.png")
    return path if os.path.isfile(path) else None


def smallest_piece(kit: str) -> str | None:
    folder = palette.kit_model_dir(kit)
    if folder is None:
        return None
    files = [f for f in os.listdir(folder) if f.lower().endswith(".glb")]
    if not files:
        return None
    files.sort(key=lambda f: (os.path.getsize(os.path.join(folder, f)), f))
    return os.path.join(folder, files[0])


def build_swatch(kit: str, era: str, out_dir: str = VIP_DIR) -> str:
    """Write assets/build/vip/<kit>_swatch.glb (+ <kit>_colormap.png) and return the GLB path."""
    if era not in STOPS:
        log(f"WARNING: no VIP stops for era {era!r}; using {DEFAULT_ERA}")
    os.makedirs(out_dir, exist_ok=True)
    colormap = kit_colormap(kit)
    if colormap is not None:
        recoloured = png_bytes(recolor(Image.open(colormap), era))
        piece = smallest_piece(kit)
        data = None
        if piece is not None:
            with open(piece, "rb") as fh:
                raw = fh.read()
            data, notes = glbtools.embed_images(raw, lambda uri: recoloured)
            if not notes:
                log(f"WARNING: {os.path.basename(piece)} has no external image; using a quad instead")
                data = None
            else:
                log(f"{kit}: {os.path.basename(piece)} with the {era} colourway embedded ({len(recoloured)} B)")
        if data is None:
            data = glbtools.make_textured_quad_glb(recoloured, f"{kit}-vip")
    else:
        pal = palette.ensure_palette(kit)
        recoloured = png_bytes(recolor(Image.open(os.path.join(REPO_ROOT, pal["png"])), era))
        data = glbtools.make_textured_quad_glb(recoloured, f"{kit}-vip")
        log(f"{kit}: palette kit, {era} colourway on a quad ({len(recoloured)} B)")
    problems = glbtools.roblox_problems(data)
    for p in problems:
        log(f"WARNING: {kit} swatch: {p}")
    glb_path = os.path.join(out_dir, f"{kit}_swatch.glb")
    with open(glb_path, "wb") as fh:
        fh.write(data)
    with open(os.path.join(out_dir, f"{kit}_colormap.png"), "wb") as fh:
        fh.write(recoloured)
    log(f"wrote {os.path.relpath(glb_path, REPO_ROOT)} ({len(data)} B)")
    return glb_path


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Build VIP swatch GLBs (recoloured kit textures).")
    parser.add_argument("--kit", action="append", required=True, help="kit slug (repeatable)")
    parser.add_argument("--era", default=DEFAULT_ERA, help="era whose colourway to use")
    parser.add_argument("--out", default=VIP_DIR)
    args = parser.parse_args(argv)
    failures = 0
    for kit in args.kit:
        try:
            build_swatch(kit, args.era, args.out)
        except (OSError, ValueError, glbtools.GlbError) as exc:
            log(f"WARNING: {kit}: {exc}")
            failures += 1
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
