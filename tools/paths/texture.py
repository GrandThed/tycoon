"""Procedural tiling path texture for the ribbon renderer (INTERFACES "Wave 1c — ribbon paths").

Needs numpy, which the system `py` lacks, so it runs under Blender's bundled Python:
  "/c/Program Files/Blender Foundation/Blender 5.2/5.2/python/bin/python.exe" tools/paths/texture.py --era Village
  (optional: --out <png> [default assets/paths/village_path.png], --preview <png> for a 2x2 tile over grass)

Deterministic: every random draw comes from one generator seeded per era, so the same numpy build
writes the same bytes on every run (the uploaded asset must be reproducible from the repo).

Image x = u (along the path, seamless: every noise field is built in the Fourier domain on a
periodic grid and pebbles wrap), image y = v (across the path; alpha fades irregularly to 0 at
both edges). PNG writing is a tiny zlib encoder so no Pillow is needed.
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

W, H = 1024, 512  # u (along, textureLength studs) x v (across the whole mesh width)
# Per-era look. Only Village has a ribbon in wave 1c; seed and colours are the approved mock's.
ERAS = {
    "Village": {
        "seed": 20260917,
        "file": "village_path.png",
        "base": (126, 99, 66),
        "grass": (106, 127, 63),
    },
}


def fourier_noise(rng, shape, beta, lo_cut=0.0, hi_cut=None):
    """Periodic 1/f^beta noise, normalised to zero mean, unit std."""
    h, w = shape
    white = rng.standard_normal(shape)
    fy = np.fft.fftfreq(h)[:, None] * h
    fx = np.fft.fftfreq(w)[None, :] * w
    # both axes in cycles per 1024 px, so features are round in pixels (the mesh maps ~125 px per stud both ways)
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


def mesh_width_factor(era):
    """The alpha 0.5 line must sit on the mesh's nominal edge, so read the value PathRibbon uses
    from config instead of keeping a second copy of it here."""
    ribbon = json.loads(CITY_DRESSING.read_text(encoding="utf-8"))["eras"][era]["road"]["ribbon"]
    return float(ribbon["meshWidthFactor"])


def generate(rng, edge_scale, base_rgb):
    """RGBA uint8 (H, W, 4). The order of draws from rng is part of the approved look; keep it."""
    base = np.array(base_rgb, dtype=np.float64) / 255.0
    yy, _ = np.mgrid[0:H, 0:W].astype(np.float64)
    v = (yy + 0.5) / H

    # ---- dirt albedo: low-frequency colour patches + mid mottling + fine grain
    low = fourier_noise(rng, (H, W), 2.2, hi_cut=10)
    mid = fourier_noise(rng, (H, W), 1.4, lo_cut=6, hi_cut=60)
    grain = fourier_noise(rng, (H, W), 0.4, lo_cut=80)
    warm = fourier_noise(rng, (H, W), 2.0, hi_cut=8)
    light = 1.0 + 0.05 * low + 0.045 * mid + 0.045 * grain
    colour = base[None, None, :] * light[..., None]
    # warmer/ochre vs cooler/grey patches
    colour += (0.028 * warm)[..., None] * np.array([1.0, 0.55, 0.05])
    # compacted centre is a touch lighter and smoother, the shoulders a touch darker
    across = np.abs(v - 0.5) * 2 * edge_scale  # 1.0 at the nominal edge
    colour *= (1.04 - 0.09 * smoothstep(0.3, 1.1, across))[..., None]

    # ---- height field: dirt relief + pebbles (domes), shaded by one light
    height = 0.25 * mid + 0.35 * grain
    peb_albedo = np.zeros((H, W, 3))
    peb_mask = np.zeros((H, W))
    for _ in range(400):
        # more pebbles toward the shoulders, fewer in the worn middle; a few stray past the edge
        side = rng.choice([-1.0, 1.0])
        dist = np.clip(abs(rng.normal(0.58, 0.28)), 0.0, 0.98)
        vy = 0.5 + side * dist * 0.5 / edge_scale
        cy = vy * H
        cx = rng.uniform(0, W)
        r = rng.lognormal(np.log(4.2), 0.42)
        r = float(np.clip(r, 2.6, 12.0))
        ecc = rng.uniform(0.62, 1.0)
        ang = rng.uniform(0, np.pi)
        tone = rng.uniform(0.0, 1.0)
        if tone < 0.55:
            albedo = np.array([150, 140, 124]) / 255 * rng.uniform(0.85, 1.12)  # grey stone
        elif tone < 0.85:
            albedo = np.array([168, 142, 104]) / 255 * rng.uniform(0.85, 1.1)  # tan stone
        else:
            albedo = np.array([112, 96, 80]) / 255 * rng.uniform(0.85, 1.1)  # dark stone
        rad = int(np.ceil(r + 3))
        y0, y1 = int(max(0, cy - rad)), int(min(H, cy + rad + 1))
        if y1 <= y0:
            continue
        ys = np.arange(y0, y1)[:, None]
        xs = (np.arange(int(cx - rad), int(cx + rad) + 1) % W)[None, :]
        dx = np.arange(int(cx - rad), int(cx + rad) + 1)[None, :] - cx
        dy = ys - cy
        ca, sa = np.cos(ang), np.sin(ang)
        lx = (dx * ca + dy * sa) / r
        ly = (-dx * sa + dy * ca) / (r * ecc)
        d2 = lx * lx + ly * ly
        dome = np.sqrt(np.clip(1 - d2, 0, 1)) * r * 0.55
        inside = np.clip((1 - np.sqrt(d2)) * r * 0.9, 0, 1)  # 1px anti-aliased rim
        yi = np.broadcast_to(ys, d2.shape)
        xi = np.broadcast_to(xs, d2.shape)
        height[yi, xi] = np.maximum(height[yi, xi], dome)
        m_old = peb_mask[yi, xi]
        m_new = np.maximum(m_old, inside)
        blend = np.where(inside > m_old, inside, 0)[..., None]
        speck = 1 + 0.08 * rng.standard_normal(d2.shape)
        peb_albedo[yi, xi] = peb_albedo[yi, xi] * (1 - blend) + (albedo[None, None, :] * speck[..., None]) * blend
        peb_mask[yi, xi] = m_new

    colour = colour * (1 - peb_mask[..., None]) + peb_albedo * peb_mask[..., None]

    # shading from the height field (light from upper-left of the image, soft)
    gx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * 0.5
    gy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * 0.5
    nrm = np.stack([-gx, -gy, np.full_like(gx, 1.6)], axis=-1)
    nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True)
    ldir = np.array([-0.45, -0.55, 0.7])
    ldir /= np.linalg.norm(ldir)
    lambert = np.clip((nrm * ldir).sum(-1), 0, 1) / ldir[2]
    shade = 0.62 + 0.38 * lambert
    # contact/drop shadow: height shifted toward bottom-right, darker where it towers over here
    shifted = np.roll(np.roll(height, 2, axis=0), 2, axis=1)
    shade -= np.clip((shifted - height) * 0.35, 0, 0.35)
    colour *= shade[..., None]
    # tiny specular glint on pebble tops
    colour += (np.clip(lambert - 1.05, 0, 1) * 0.35 * peb_mask)[..., None]

    # ---- alpha: soft, irregular fall-off toward both v edges
    edge_top = fourier_noise_1d(rng, W, 1.2, hi_cut=22)
    edge_bot = fourier_noise_1d(rng, W, 1.2, hi_cut=22)
    fine = fourier_noise(rng, (H, W), 0.8, lo_cut=40)
    nominal = 0.5 / edge_scale  # distance from centre (in v) where alpha should be 0.5
    wobble = np.where(0.5 - v > 0, edge_top[None, :], edge_bot[None, :])
    boundary = nominal + 0.035 * wobble + 0.012 * fine
    dc = np.abs(v - 0.5)
    soft = 0.075
    alpha = 1 - smoothstep(boundary - soft, boundary + soft, dc)
    # crumbly grain in the fade band
    alpha = np.clip(alpha + 0.16 * fine * alpha * (1 - alpha) * 4, 0, 1)
    # stray pebbles stay mostly opaque where they sit in the inner fade
    alpha = np.maximum(alpha, peb_mask * smoothstep(0.37, 0.33, dc) * 0.95)
    # Outer fade rows fade to a low-passed copy of the dirt, so a ribbon tip that squeezes these
    # rows across the path (the cap collapses its inner columns toward the tip) shows no streaks.
    fy = np.fft.fftfreq(H)[:, None] * 1024
    fx = np.fft.fftfreq(W)[None, :] * 1024
    lowpass = np.exp(-((fx**2 + fy**2) / 24.0**2))
    flat = np.stack([np.real(np.fft.ifft2(np.fft.fft2(colour[..., i]) * lowpass)) for i in range(3)], axis=-1)
    t_flat = smoothstep(0.31, 0.39, dc)[..., None]
    colour = colour * (1 - t_flat) + flat * t_flat
    # the mesh border itself must be fully transparent
    alpha *= smoothstep(0.5, 0.47, dc)
    # edge darkening where the dirt thins into grass
    colour *= (0.9 + 0.1 * smoothstep(0.1, 0.7, alpha))[..., None]

    rgb8 = (np.clip(colour, 0, 1) * 255 + 0.5).astype(np.uint8)
    a8 = (np.clip(alpha, 0, 1) * 255 + 0.5).astype(np.uint8)
    return np.dstack([rgb8, a8])


def preview(rng, rgba, grass_rgb):
    """2x2 tile composited over grass, to eyeball the seam and the edge (never uploaded)."""
    grass_c = np.array(grass_rgb, dtype=np.float64) / 255.0
    tile = np.tile(rgba, (2, 2, 1)).astype(np.float64) / 255
    grass = grass_c[None, None, :] * (1 + 0.05 * np.tile(fourier_noise(rng, (H, W), 1.5, hi_cut=40), (2, 2)))[..., None]
    comp = tile[..., :3] * tile[..., 3:4] + grass * (1 - tile[..., 3:4])
    return (np.clip(comp, 0, 1) * 255 + 0.5).astype(np.uint8)


def main(argv):
    parser = argparse.ArgumentParser(description="Generate an era's tiling path texture.")
    parser.add_argument("--era", required=True, choices=sorted(ERAS))
    parser.add_argument("--out", help="PNG to write (default assets/paths/<file>)")
    parser.add_argument("--preview", help="also write a 2x2 tiled preview over grass here")
    args = parser.parse_args(argv)
    spec = ERAS[args.era]
    out = Path(args.out) if args.out else OUT_DIR / spec["file"]
    rng = np.random.default_rng(spec["seed"])
    rgba = generate(rng, mesh_width_factor(args.era), spec["base"])
    write_png(out, rgba)
    print("wrote", out, rgba.shape)
    if args.preview:
        write_png(args.preview, preview(rng, rgba, spec["grass"]))
        print("wrote", args.preview)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
