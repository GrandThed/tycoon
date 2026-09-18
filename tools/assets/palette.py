"""Deterministic palette texture for kits whose GLBs colour by material factor, not by texture.

Roblox drops glTF `baseColorFactor` on import (docs/ASSET_RESEARCH.md section 3), so a kit like
nature-kit or space-kit would arrive uniformly grey. This scans every GLB of a kit, collects the
distinct base colours of every texture-less material, and lays them out as a grid of flat
swatches: assets/build/palettes/<kit>.png plus <kit>.json describing which swatch is which
colour and where its UV centre is. merge_stages.py then moves the UVs of colour-only faces onto
their swatch, so the whole kit shares one image and one UV convention like the textured kits do.

Stdlib only (writes the PNG with zlib) so it imports under Blender's Python as well as `py`.

    py tools/assets/palette.py --kit nature-kit [--kit space-kit] [--force]
"""

from __future__ import annotations

import argparse
import json
import math
import os
import struct
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import glbtools  # noqa: E402

REPO_ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
KITS_ROOT = os.path.join(REPO_ROOT, "assets", "kenney3d")
MODEL_DIRS = ("GLB format", "GLTF format")
PALETTES_DIR = os.path.join(REPO_ROOT, "assets", "build", "palettes")
# Swatch cell in pixels; the UV sits at the cell centre so bilinear sampling never bleeds.
CELL = 16
PALETTE_VERSION = 1


def log(msg: str) -> None:
    print(f"[palette] {msg}", flush=True)


def kit_model_dir(kit: str) -> str | None:
    for sub in MODEL_DIRS:
        folder = os.path.join(KITS_ROOT, kit, "Models", sub)
        if os.path.isdir(folder):
            return folder
    return None


def linear_to_srgb(c: float) -> int:
    c = max(0.0, min(1.0, c))
    s = 12.92 * c if c <= 0.0031308 else 1.055 * (c ** (1 / 2.4)) - 0.055
    return int(round(s * 255))


def srgb_to_linear(byte: int) -> float:
    s = byte / 255
    return s / 12.92 if s <= 0.04045 else ((s + 0.055) / 1.055) ** 2.4


def write_png(path: str, width: int, height: int, rows: list[list[tuple[int, int, int]]]) -> None:
    raw = bytearray()
    for row in rows:
        raw.append(0)  # filter type: none
        for r, g, b in row:
            raw.extend((r, g, b))

    def chunk(tag: bytes, body: bytes) -> bytes:
        return struct.pack(">I", len(body)) + tag + body + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF)

    png = glbtools.PNG_SIGNATURE
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as fh:
        fh.write(png)


# Kits whose authors wrote sRGB values straight into baseColorFactor instead of linear ones.
# space-kit: raw x 255 matches Kenney's own Isometric previews (orange 255,160,52; dark 70,76,87);
# decoding as linear turns the orange into pale amber and the dark recesses into mid-grey.
# nature-kit is probably the same, but Village shipped and was approved with the decoded look.
SRGB_FACTOR_KITS = frozenset({"space-kit"})


def swatch_srgb(kit: str, factor: tuple[float, float, float]) -> tuple[int, int, int]:
    if kit in SRGB_FACTOR_KITS:
        return tuple(max(0, min(255, round(c * 255))) for c in factor)
    return tuple(linear_to_srgb(c) for c in factor)


def scan_kit(kit: str) -> dict:
    """Distinct colour-only material colours across the whole kit, plus whether any texture exists."""
    folder = kit_model_dir(kit)
    if folder is None:
        raise FileNotFoundError(f"kit not found under {KITS_ROOT}: {kit}")
    colours: set[tuple[float, float, float]] = set()
    textured = 0
    files = sorted(f for f in os.listdir(folder) if f.lower().endswith(".glb"))
    for name in files:
        with open(os.path.join(folder, name), "rb") as fh:
            doc, _ = glbtools.parse_glb(fh.read())
        for mat in doc.get("materials", []):
            pbr = mat.get("pbrMetallicRoughness") or {}
            if "baseColorTexture" in pbr:
                textured += 1
                continue
            r, g, b = (pbr.get("baseColorFactor") or [1, 1, 1, 1])[:3]
            colours.add((round(r, 6), round(g, 6), round(b, 6)))
    return {"kit": kit, "files": len(files), "textured_materials": textured, "colours": sorted(colours)}


def build_palette(kit: str) -> dict:
    scan = scan_kit(kit)
    colours = scan["colours"]
    if not colours:
        raise ValueError(f"{kit}: every material is textured; no palette needed")
    columns = max(1, math.ceil(math.sqrt(len(colours))))
    rows_n = math.ceil(len(colours) / columns)
    width, height = columns * CELL, rows_n * CELL
    swatches = []
    pixels = [[(0, 0, 0)] * width for _ in range(height)]
    for index, linear in enumerate(colours):
        col, row = index % columns, index // columns
        srgb = swatch_srgb(kit, linear)
        for y in range(row * CELL, (row + 1) * CELL):
            for x in range(col * CELL, (col + 1) * CELL):
                pixels[y][x] = srgb
        swatches.append(
            {
                "index": index,
                "linear": list(linear),
                "srgb": list(srgb),
                # glTF UV convention: origin top-left, v grows downward.
                "uv": [round((col + 0.5) * CELL / width, 6), round((row + 0.5) * CELL / height, 6)],
            }
        )
    png_path = os.path.join(PALETTES_DIR, f"{kit}.png")
    json_path = os.path.join(PALETTES_DIR, f"{kit}.json")
    write_png(png_path, width, height, pixels)
    data = {
        "version": PALETTE_VERSION,
        "kit": kit,
        "cell": CELL,
        "columns": columns,
        "rows": rows_n,
        "width": width,
        "height": height,
        "png": os.path.relpath(png_path, REPO_ROOT).replace(os.sep, "/"),
        "sourceFiles": scan["files"],
        "swatches": swatches,
    }
    with open(json_path, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(data, fh, indent=2)
        fh.write("\n")
    log(f"{kit}: {len(colours)} colours from {scan['files']} GLBs -> {data['png']} ({width}x{height})")
    return data


def load_palette(kit: str) -> dict | None:
    json_path = os.path.join(PALETTES_DIR, f"{kit}.json")
    png_path = os.path.join(PALETTES_DIR, f"{kit}.png")
    if not (os.path.isfile(json_path) and os.path.isfile(png_path)):
        return None
    with open(json_path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def ensure_palette(kit: str) -> dict:
    return load_palette(kit) or build_palette(kit)


def nearest_swatch(pal: dict, linear_rgb: tuple[float, float, float]) -> dict:
    best = None
    best_d = math.inf
    for sw in pal["swatches"]:
        d = sum((a - b) ** 2 for a, b in zip(sw["linear"], linear_rgb))
        if d < best_d:
            best, best_d = sw, d
    assert best is not None
    return best


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Build the palette texture of material-colour kits.")
    parser.add_argument("--kit", action="append", required=True, help="kit slug under assets/kenney3d (repeatable)")
    parser.add_argument("--force", action="store_true", help="rebuild even if the palette exists")
    args = parser.parse_args(argv)
    failures = 0
    for kit in args.kit:
        try:
            if not args.force and load_palette(kit):
                log(f"{kit}: palette already built (use --force to rebuild)")
                continue
            build_palette(kit)
        except (FileNotFoundError, ValueError, glbtools.GlbError) as exc:
            log(f"WARNING: {exc}")
            failures += 1
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
