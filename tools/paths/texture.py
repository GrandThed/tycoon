"""Procedural path textures for the baked-path renderer (INTERFACES "Wave 1d - baked paths").

Needs numpy, which the system `py` lacks, so it runs under Blender's bundled Python:
  "/c/Program Files/Blender Foundation/Blender 5.2/5.2/python/bin/python.exe" tools/paths/texture.py --era Village
  (optional: --preview-dir <dir> for 2x2 tiled previews over the plot's ground colour)

Writes assets/paths/<Era>_fill.png and <Era>_rim.png, plus one pair per **surface variant** named
in that era's `variants` table (INTERFACES "Wave 1e - street upgrades"): <Era>_<variant>_fill.png
and <Era>_<variant>_rim.png. A variant is the same recipe in another material, swapped at runtime
by writing MeshPart.TextureID, so no piece is ever re-baked; --variant restricts a run to one and
--default-only to the baked-in pair. Every image is 1024x1024 **opaque** RGB, seamless
on **both** axes, because the meshes carry world-planar UVs (u = x / tileStuds, v = z / tileStuds):
two pieces that cover the same ground then sample the same texel, which is what makes a junction
overlap and any z-fighting invisible, and a path may cross a tile in any direction, so the texture
must carry no directional feature.

Deterministic: every draw comes from one generator seeded per era and layer, so the same numpy
build writes the same bytes on every run - an uploaded asset must be reproducible from the repo.
PNG writing is a tiny zlib encoder, so no Pillow is needed.

Village is the look Ben approved in the C3 bake-off (tools/pathtest/textures.py, which now imports
its fill and rim from here): warm stylised dirt, bold flat pebbles, luminance well above the grass,
with the rim a darker desaturated copy so it reads as the trodden shoulder of the same path.
Boomtown is asphalt with a lighter concrete **kerb** rim: the kerb is a separate image, not a
darkened copy, because a kerb is lighter than its road, and it is the cue that reads at 45 studs.
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
import zlib
from pathlib import Path

import numpy as np

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
CITY_DRESSING = REPO_ROOT / "src" / "shared" / "Config" / "CityDressing.json"
OUT_DIR = REPO_ROOT / "assets" / "paths"

P = 1024  # square, seamless on both axes; at tileStuds 11 that is ~93 px per stud

# Per-era look. `ground` is the plot's baseColor (src/shared/Layouts/<Era>.luau) and is only used
# by --preview-dir, so a preview shows the contrast a player actually sees. `fill` and `rim` name
# generators below; "darken" means the rim is the fill run through planar_rim. `variants` are the
# surface upgrades of INTERFACES "Wave 1e": each gets its own seeds, so adding one can never shift
# a byte of an already-uploaded image.
ERAS = {
    "Village": {
        "fill": "dirt",
        "fill_seed": 20260919,
        "rim": "darken",
        "ground": (106, 127, 63),
        "variants": {
            # "Pave the Road" (slot dirtRoad): the trail is laid with stone, so it reads brighter
            # and harder-edged than the dirt it replaces while keeping the warm village palette.
            "cobble": {"fill": "cobble", "fill_seed": 20260931, "rim": "darken"},
        },
    },
    "Boomtown": {
        "fill": "asphalt",
        "fill_seed": 20260921,
        "rim": "concrete",
        "rim_seed": 20260922,
        "ground": (173, 138, 93),
        "variants": {
            # Before "Pave Main Street" (slot paveMainStreet) the town has no asphalt: packed
            # gravel, the Village dirt recipe in a cooler grey-tan, and no kerb to go with it,
            # so its rim is a darkened copy rather than the concrete kerb of the finished street.
            "gravel": {"fill": "gravel", "fill_seed": 20260933, "rim": "darken"},
        },
    },
}
LUMA = np.array([0.2126, 0.7152, 0.0722])


# ---------------------------------------------------------------- noise and output helpers


def fourier_noise(rng, shape, beta, lo_cut=0.0, hi_cut=None):
    """Periodic 1/f^beta noise, normalised to zero mean, unit std."""
    h, w = shape
    white = rng.standard_normal(shape)
    fy = np.fft.fftfreq(h)[:, None] * h
    fx = np.fft.fftfreq(w)[None, :] * w
    # both axes in cycles per 1024 px, so features are round in pixels
    f = np.sqrt((fx * 1024 / w) ** 2 + (fy * 1024 / h) ** 2)
    f[0, 0] = 1.0
    amp = 1.0 / f**beta
    if lo_cut:
        amp *= 1 - np.exp(-((f / lo_cut) ** 2))
    if hi_cut:
        amp *= np.exp(-((f / hi_cut) ** 2))
    amp[0, 0] = 0.0
    field = np.real(np.fft.ifft2(np.fft.fft2(white) * amp))
    field -= field.mean()
    return field / (field.std() + 1e-9)


def fourier_noise_1d(rng, n, beta, hi_cut):
    white = rng.standard_normal(n)
    f = np.abs(np.fft.fftfreq(n) * n)
    f[0] = 1.0
    amp = np.exp(-((f / hi_cut) ** 2)) / f**beta
    amp[0] = 0.0
    x = np.real(np.fft.ifft(np.fft.fft(white) * amp))
    x -= x.mean()
    return x / (x.std() + 1e-9)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def srgb(c):
    return np.array(c, dtype=np.float64) / 255.0


def to8(x):
    return (np.clip(x, 0, 1) * 255 + 0.5).astype(np.uint8)


def write_png(path, rgba):
    h, w, c = rgba.shape
    raw = b"".join(b"\x00" + rgba[y].tobytes() for y in range(h))

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    colour_type = 6 if c == 4 else 2
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, colour_type, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)


def downsample(rgb8, factor):
    """Box-filtered mip, like a GPU mip chain of an uploaded PNG."""
    x = rgb8.astype(np.float64)
    h, w = x.shape[0] // factor, x.shape[1] // factor
    return x[: h * factor, : w * factor].reshape(h, factor, w, factor, -1).mean(axis=(1, 3))


def tile_studs(era: str) -> float:
    """The mesh UVs come from CityDressing.json, so the texture reads the same value rather than
    keeping a second copy of it."""
    dressing = json.loads(CITY_DRESSING.read_text(encoding="utf-8"))
    return float(dressing["eras"][era]["road"]["paths"]["tileStuds"])


# ---------------------------------------------------------------- shared stamping


def stamp_planar(rng, count, r_range, palette, albedo, mask, placed, shadow_px):
    """Flat pebbles that wrap on BOTH axes, never touching (a heap of overlapping stones reads as
    gravel, not a path). Fills albedo and mask in place; `placed` carries the rejection test."""
    stamped = 0
    for _ in range(count * 40):
        if stamped >= count:
            break
        r = float(rng.uniform(*r_range))
        ecc = rng.uniform(0.62, 0.95)
        ang = rng.uniform(0, np.pi)
        cx, cy = rng.uniform(0, P), rng.uniform(0, P)

        def wrapped(a, b, n):
            d = abs(a - b)
            return min(d, n - d)

        if any(wrapped(cx, px, P) ** 2 + wrapped(cy, py, P) ** 2 < (r + pr + shadow_px + 5) ** 2 for px, py, pr in placed):
            continue
        placed.append((cx, cy, r))
        stamped += 1
        colour = palette[int(rng.integers(len(palette)))] * rng.uniform(0.93, 1.05)
        rad = int(np.ceil(r + shadow_px + 3))
        yr = np.arange(int(cy - rad), int(cy + rad) + 1)
        xr = np.arange(int(cx - rad), int(cx + rad) + 1)
        yi = (yr % P)[:, None]
        xi = (xr % P)[None, :]
        dy, dx = yr[:, None] - cy, xr[None, :] - cx
        ca, sa = np.cos(ang), np.sin(ang)
        lx = (dx * ca + dy * sa) / r
        ly = (-dx * sa + dy * ca) / (r * ecc)
        inside = np.clip((1 - np.sqrt(lx * lx + ly * ly)) * r * 0.8, 0, 1)
        yb, xb = np.broadcast_to(yi, inside.shape), np.broadcast_to(xi, inside.shape)
        blend = inside[..., None]
        albedo[yb, xb] = albedo[yb, xb] * (1 - blend) + colour[None, None, :] * blend
        mask[yb, xb] = np.maximum(mask[yb, xb], inside)


def drop_shadow(albedo, mask, shadow_px, strength):
    """One hard offset copy of the pebble mask: cel-style, instead of a lit dome, which is what
    makes the stones read as bold shapes at the 1/8 mip."""
    shadow = np.roll(np.roll(mask, shadow_px, axis=0), shadow_px, axis=1) * (1 - mask)
    return albedo * (1 - strength * shadow[..., None])


# ---------------------------------------------------------------- Village: stylised dirt


def planar_fill(rng):
    """The approved C3 fill: warm packed dirt, gentle two-tone worn blobs, a few bold flat pebbles
    with one hard drop shadow each. No directional feature, because the mapping is world-planar."""
    light = srgb((194, 155, 106))
    dark = srgb((176, 137, 91))
    blobs = fourier_noise(rng, (P, P), 2.0, lo_cut=4, hi_cut=14)  # ~0.8-2.5 stud patches
    tone = smoothstep(-0.2, 0.2, blobs + 0.75)
    colour = dark[None, None, :] * (1 - tone[..., None]) + light[None, None, :] * tone[..., None]
    # a second, fainter tone step keeps large flat areas from reading as plastic
    fine = fourier_noise(rng, (P, P), 1.6, lo_cut=12, hi_cut=45)
    colour *= (1 + 0.035 * np.sign(fine) * smoothstep(0.1, 0.8, np.abs(fine)))[..., None]
    albedo = colour.copy()
    mask = np.zeros((P, P))
    stones = [srgb((214, 200, 172)), srgb((150, 124, 98)), srgb((202, 186, 158))]
    placed = []
    shadow_px = 6
    stamp_planar(rng, 40, (22, 38), stones, albedo, mask, placed, shadow_px)  # 0.47-0.82 studs
    stamp_planar(rng, 80, (12, 19), stones, albedo, mask, placed, shadow_px)  # 0.26-0.41 studs
    return to8(np.clip(drop_shadow(albedo, mask, shadow_px, 0.26), 0, 1))


def planar_rim(fill_rgb):
    """The approved C3 rim: the same image, darker and a little desaturated, so a rim beside a fill
    reads as the trodden shoulder of the same path and two rims that overlap are identical texels."""
    x = fill_rgb.astype(np.float64) / 255.0
    lum = (x * LUMA).sum(-1, keepdims=True)
    return to8(np.clip((x * 0.75 + lum * 0.25) * 0.72, 0, 1))


# ---------------------------------------------------------------- Village variant: cobble


def jittered_cells(rng, cells, jitter):
    """Toroidal jittered-grid Voronoi: returns (d1, d2, owner) per pixel, where d1/d2 are the
    distances to the nearest and second-nearest site and `owner` is the flat index of the nearest.

    Evaluated over the 5x5 block of grid cells around each pixel rather than all sites, which is
    exact for this jitter and keeps the generation to a couple of seconds. Cell indices wrap, and
    a wrapped site keeps its unwrapped position, so the pattern is seamless on both axes."""
    cell = P / cells
    offsets = rng.uniform(-jitter, jitter, (2, cells, cells))
    site_x = (np.arange(cells, dtype=np.float32)[None, :] + 0.5 + offsets[0]) * cell
    site_y = (np.arange(cells, dtype=np.float32)[:, None] + 0.5 + offsets[1]) * cell
    y = np.arange(P, dtype=np.float32)[:, None]
    x = np.arange(P, dtype=np.float32)[None, :]
    gy = np.floor(y / cell).astype(np.int32)
    gx = np.floor(x / cell).astype(np.int32)
    d1 = np.full((P, P), np.inf, dtype=np.float32)
    d2 = np.full((P, P), np.inf, dtype=np.float32)
    owner = np.zeros((P, P), dtype=np.int32)
    for oy in range(-2, 3):
        for ox in range(-2, 3):
            jy, jx = gy + oy, gx + ox
            iy, ix = jy % cells, jx % cells
            sx = site_x[iy, ix] + (jx - ix) * cell
            sy = site_y[iy, ix] + (jy - iy) * cell
            dist = np.hypot(x - sx, y - sy)
            d2 = np.minimum(d2, np.maximum(d1, dist))
            nearer = dist < d1
            owner = np.where(nearer, iy * cells + ix, owner)
            d1 = np.where(nearer, dist, d1)
    return d1, d2, owner


def cobble_fill(rng):
    """Village "cobble" (the Pave the Road upgrade): rounded irregular setts in four flat warm
    greys, set in a darker mortar. Each sett is its Voronoi cell intersected with a disc around
    its own site - that intersection is what rounds the corners a plain Voronoi leaves sharp - and
    carries one flat colour, one soft shade towards its edge and one hard drop shadow, the same
    bold-flat treatment as the dirt it replaces. At 64 px per cell a sett is about 0.6 studs, so
    the 3-stud Village trail shows four to five whole setts across."""
    cells, jitter = 14, 0.30
    cell = P / cells
    d1, d2, owner = jittered_cells(rng, cells, jitter)
    # min(distance to the cell boundary, distance inside the disc): straight joints between
    # neighbours, arcs where three cells meet.
    sdf = np.minimum(0.5 * (d2 - d1) - 2.6, 0.66 * cell - d1)
    mask = smoothstep(0.0, 2.5, sdf)

    stones = np.array([srgb(c) for c in ((218, 206, 186), (198, 186, 167), (226, 217, 199), (184, 171, 152))])
    mortar = srgb((139, 126, 108))
    pick = rng.integers(len(stones), size=cells * cells)
    # One flat tone per sett, nudged by a large-scale field so the paving reads as patches of
    # wear rather than confetti; sampled once per sett, so the sett itself stays flat.
    patch = fourier_noise(rng, (cells, cells), 1.8, hi_cut=4).reshape(-1)
    tone = (1 + 0.05 * rng.uniform(-1, 1, cells * cells) + 0.045 * np.clip(patch, -1.6, 1.6))[:, None]
    stone_rgb = np.clip(stones[pick] * tone, 0, 1)[owner]

    shade = 1 - 0.08 * (1 - smoothstep(0.0, 0.30 * cell, sdf))
    albedo = mortar[None, None, :] * (1 - mask[..., None]) + stone_rgb * (mask * shade)[..., None]
    return to8(np.clip(drop_shadow(albedo, mask, 5, 0.22), 0, 1))


# ---------------------------------------------------------------- Boomtown variant: gravel


def gravel_fill(rng):
    """Boomtown "gravel" (the street before Pave Main Street): packed grey-tan gravel, the Village
    dirt recipe with the warmth taken out and the stones tightened up, so a player reads it as the
    same kind of surface one era on rather than as dirt again. It has to sit on Boomtown's tan
    ground (luminance 142), so the contrast is carried by being lighter *and* far less saturated
    than the ground, the way the asphalt it upgrades into is carried by being much darker."""
    light = srgb((172, 165, 150))
    dark = srgb((150, 144, 131))
    blobs = fourier_noise(rng, (P, P), 2.0, lo_cut=4, hi_cut=14)
    tone = smoothstep(-0.2, 0.2, blobs + 0.75)
    colour = dark[None, None, :] * (1 - tone[..., None]) + light[None, None, :] * tone[..., None]
    fine = fourier_noise(rng, (P, P), 1.6, lo_cut=12, hi_cut=45)
    colour *= (1 + 0.035 * np.sign(fine) * smoothstep(0.1, 0.8, np.abs(fine)))[..., None]
    albedo = colour.copy()
    mask = np.zeros((P, P))
    stones = [srgb((201, 196, 185)), srgb((122, 118, 110)), srgb((180, 176, 166))]
    placed = []
    shadow_px = 5
    stamp_planar(rng, 40, (24, 40), stones, albedo, mask, placed, shadow_px)  # 0.52-0.86 studs
    stamp_planar(rng, 95, (12, 19), stones, albedo, mask, placed, shadow_px)  # 0.26-0.41 studs
    return to8(np.clip(drop_shadow(albedo, mask, shadow_px, 0.24), 0, 1))


# ---------------------------------------------------------------- Boomtown: asphalt and kerb


def asphalt_fill(rng):
    """Boomtown's road surface: dark blue-grey asphalt, large worn patches where the surface has
    been resealed, and bold aggregate grains. Smaller and denser stones than the Village dirt,
    because asphalt reads as grain rather than pebbles, but still stamped flat with one hard
    shadow so something survives the 1/8 mip instead of greying out."""
    light = srgb((102, 104, 110))
    dark = srgb((88, 90, 96))
    # Soft, low-contrast reseal patches: a cel-hard two-tone (which suits dirt) reads as camouflage
    # on a road, so the ramp is wide and the two tones are only 14 levels apart.
    blobs = fourier_noise(rng, (P, P), 2.0, lo_cut=3, hi_cut=11)  # ~1-3 stud patches
    tone = smoothstep(-0.45, 0.45, blobs)
    colour = dark[None, None, :] * (1 - tone[..., None]) + light[None, None, :] * tone[..., None]
    mottle = fourier_noise(rng, (P, P), 1.5, lo_cut=10, hi_cut=48)
    colour *= (1 + 0.035 * mottle)[..., None]
    # The main signal is the grain: dense fine noise, which survives to about the 1/4 mip and
    # averages to an even dark grey beyond it, which is what asphalt looks like from far away.
    grain = fourier_noise(rng, (P, P), 0.5, lo_cut=60)
    colour *= (1 + 0.055 * grain)[..., None]
    albedo = colour.copy()
    mask = np.zeros((P, P))
    grains = [srgb((124, 124, 126)), srgb((104, 102, 100)), srgb((136, 134, 130))]
    placed = []
    shadow_px = 4
    stamp_planar(rng, 45, (12, 19), grains, albedo, mask, placed, shadow_px)  # 0.26-0.41 studs
    stamp_planar(rng, 110, (6, 10), grains, albedo, mask, placed, shadow_px)  # 0.13-0.22 studs
    return to8(np.clip(drop_shadow(albedo, mask, shadow_px, 0.22), 0, 1))


def concrete_rim(rng):
    """Boomtown's kerb: pale cool concrete, faint slab mottling, a few chips. Much lighter than the
    asphalt and desaturated against the warm plot ground, so the kerb line is the cue that carries
    at 45 studs. It is drawn from scratch, not derived from the fill, because a darkened asphalt
    would read as a shadow rather than a kerb."""
    light = srgb((197, 196, 191))
    dark = srgb((181, 180, 176))
    blobs = fourier_noise(rng, (P, P), 2.1, lo_cut=3, hi_cut=9)  # ~1.5-4 stud slab tone
    tone = smoothstep(-0.3, 0.3, blobs)
    colour = dark[None, None, :] * (1 - tone[..., None]) + light[None, None, :] * tone[..., None]
    grit = fourier_noise(rng, (P, P), 1.3, lo_cut=14, hi_cut=70)
    colour *= (1 + 0.028 * grit)[..., None]
    albedo = colour.copy()
    mask = np.zeros((P, P))
    chips = [srgb((150, 149, 144)), srgb((208, 207, 202))]
    placed = []
    shadow_px = 3
    stamp_planar(rng, 26, (9, 15), chips, albedo, mask, placed, shadow_px)  # 0.19-0.32 studs
    return to8(np.clip(drop_shadow(albedo, mask, shadow_px, 0.18), 0, 1))


# ---------------------------------------------------------------- output


FILLS = {"dirt": planar_fill, "asphalt": asphalt_fill, "cobble": cobble_fill, "gravel": gravel_fill}
RIMS = {"concrete": concrete_rim}


def spec_of(era: str, variant: str | None) -> dict:
    return ERAS[era] if variant is None else ERAS[era]["variants"][variant]


def stem(era: str, variant: str | None) -> str:
    return era if variant is None else f"{era}_{variant}"


def generate(era: str, variant: str | None = None) -> dict:
    spec = spec_of(era, variant)
    fill = FILLS[spec["fill"]](np.random.default_rng(spec["fill_seed"]))
    if spec["rim"] == "darken":
        return {"fill": fill, "rim": planar_rim(fill)}
    return {"fill": fill, "rim": RIMS[spec["rim"]](np.random.default_rng(spec["rim_seed"]))}


def preview(rgb, ground, path):
    """2x2 tiles at full size, the 1/4 mip and the 1/8 mip over the plot's ground colour: checks
    both seams and the distance read at once. Never uploaded."""
    rows = []
    for factor in (1, 4, 8):
        m = downsample(rgb, factor) if factor > 1 else rgb.astype(np.float64)
        m = np.repeat(np.repeat(m, factor, axis=0), factor, axis=1)
        band = np.ones((24, 2 * P, 3)) * np.array(ground) / 255.0
        rows += [band, np.tile(m, (2, 2, 1)) / 255.0]
    img = to8(np.concatenate(rows, axis=0))
    write_png(path, downsample(img, 4).round().astype(np.uint8))


def main(argv):
    parser = argparse.ArgumentParser(description="Generate an era's baked-path fill and rim textures.")
    parser.add_argument("--era", required=True, choices=sorted(ERAS))
    parser.add_argument("--out-dir", help="write here instead of assets/paths")
    parser.add_argument("--preview-dir", help="also write 2x2 tiled previews over the plot ground here")
    parser.add_argument("--variant", action="append", default=[], help="only this surface variant (repeatable)")
    parser.add_argument("--default-only", action="store_true", help="skip the era's surface variants")
    args = parser.parse_args(argv)
    out_dir = Path(args.out_dir) if args.out_dir else OUT_DIR
    studs = tile_studs(args.era)
    known = ERAS[args.era].get("variants") or {}
    unknown = [v for v in args.variant if v not in known]
    if unknown:
        parser.error(f"{args.era} has no variant(s) {', '.join(unknown)} (known: {', '.join(sorted(known)) or 'none'})")
    if args.variant:
        wanted = [v for v in sorted(known) if v in args.variant]
    else:
        wanted = [None] + ([] if args.default_only else sorted(known))
    for variant in wanted:
        images = generate(args.era, variant)
        for layer, rgb in images.items():
            path = out_dir / f"{stem(args.era, variant)}_{layer}.png"
            write_png(path, rgb)
            lum = (rgb.astype(float) * LUMA).sum(-1).mean()
            print(f"wrote {path} {rgb.shape} mean luminance {lum:.0f}")
            if args.preview_dir:
                target = Path(args.preview_dir) / f"preview_{stem(args.era, variant)}_{layer}.png"
                preview(rgb, ERAS[args.era]["ground"], target)
                print(f"wrote {target}")
    ground_lum = (np.array(ERAS[args.era]["ground"], dtype=float) * LUMA).sum()
    print(f"{args.era}: {studs:g} studs per tile ({P / studs:.0f} px per stud), ground luminance {ground_lum:.0f}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
