"""The Forest Road's ground textures: the road, its rim, the camps' trampled earth and the forest
floor. Every image is 1024 x 1024, opaque RGB and seamless on both axes, because the baked skins
carry world-planar UVs (u = x / tile, v = z / tile; tools/levels/forest.py TEXTURES): two pieces
covering the same ground sample the same texel, so their overlap and any coplanar fight vanish
(the city's C3 recipe), and nothing directional may show, since a road runs any way across a tile.

Needs numpy, so it runs under Blender's bundled Python, like tools/paths/texture.py, whose noise,
stamping and PNG helpers it reuses unchanged:

    "/c/Program Files/Blender Foundation/Blender 5.2/5.2/python/bin/python.exe" tools/levels/forest_textures.py

Writes assets/build/levels/ForestRoad/textures/{road,roadRim,camp,forestFloor}.png. Deterministic:
one generator seeded per image. The colours are tools/assets/forest_palette.py's ground swatches
(restated as anchors below; this script cannot import that module's sRGB class without the repo's
tools on the path, so it does, and checks the anchors against it).
"""

from __future__ import annotations

import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(REPO_ROOT, "tools", "paths"))
sys.path.insert(0, os.path.join(REPO_ROOT, "tools", "assets"))
import texture as tx  # noqa: E402  (read-only use: fourier_noise, stamp_planar, drop_shadow, write_png)
from forest_palette import GROUND, ROCK  # noqa: E402

P = tx.P
OUT = os.path.join(REPO_ROOT, "assets", "build", "levels", "ForestRoad", "textures")


def srgb(c):
    return tx.srgb(c)


def two_tone(rng, light, dark, lo_cut=4, hi_cut=14, bias=0.75):
    blobs = tx.fourier_noise(rng, (P, P), 2.0, lo_cut=lo_cut, hi_cut=hi_cut)
    tone = tx.smoothstep(-0.2, 0.2, blobs + bias)
    colour = srgb(dark)[None, None, :] * (1 - tone[..., None]) + srgb(light)[None, None, :] * tone[..., None]
    fine = tx.fourier_noise(rng, (P, P), 1.6, lo_cut=12, hi_cut=45)
    colour *= (1 + 0.04 * np.sign(fine) * tx.smoothstep(0.1, 0.8, np.abs(fine)))[..., None]
    return colour


def specks(rng, albedo, count, colour, length, width):
    """Short thin flecks (needles, straw) at every angle, wrapped on both axes."""
    for _ in range(count):
        cx, cy = rng.uniform(0, P), rng.uniform(0, P)
        ang = rng.uniform(0, np.pi)
        ln = rng.uniform(*length)
        ca, sa = np.cos(ang), np.sin(ang)
        rad = int(ln) + 3
        yr = np.arange(int(cy - rad), int(cy + rad) + 1)
        xr = np.arange(int(cx - rad), int(cx + rad) + 1)
        dy, dx = yr[:, None] - cy, xr[None, :] - cx
        along = dx * ca + dy * sa
        across = -dx * sa + dy * ca
        inside = np.clip(1 - np.abs(across) / width, 0, 1) * (np.abs(along) < ln)
        yi = np.broadcast_to((yr % P)[:, None], inside.shape)
        xi = np.broadcast_to((xr % P)[None, :], inside.shape)
        tint = srgb(colour) * rng.uniform(0.9, 1.08)
        blend = inside[..., None] * 0.85
        albedo[yi, xi] = albedo[yi, xi] * (1 - blend) + tint[None, None, :] * blend


def road(rng):
    """Packed dark earth, clearly lighter than the forest floor beside it, a scatter of flat grey
    and brown stones with one hard shadow each, and needle litter blown in from the trees."""
    albedo = two_tone(rng, GROUND.ROAD_LIGHT, GROUND.ROAD, bias=0.2)
    mask = np.zeros((P, P))
    stones = [srgb((150, 138, 120)), srgb((118, 104, 88)), srgb((166, 152, 128))]
    placed = []
    tx.stamp_planar(rng, 14, (12, 20), stones, albedo, mask, placed, 4)
    tx.stamp_planar(rng, 40, (6, 11), stones, albedo, mask, placed, 4)
    albedo = tx.drop_shadow(albedo, mask, 4, 0.22)
    specks(rng, albedo, 320, GROUND.NEEDLES, (7, 14), 1.5)
    specks(rng, albedo, 90, GROUND.ROAD_DARK, (5, 9), 2.2)
    return tx.to8(np.clip(albedo, 0, 1))


def camp(rng):
    """The camps' trampled earth: muddier, with dark wet patches, straw and wood chips."""
    albedo = two_tone(rng, GROUND.CAMP, GROUND.CAMP_DARK, lo_cut=3, hi_cut=10, bias=1.0)
    mud = tx.fourier_noise(rng, (P, P), 2.2, lo_cut=2, hi_cut=8)
    wet = tx.smoothstep(1.2, 1.8, mud)[..., None] * 0.55
    albedo = albedo * (1 - wet) + srgb(GROUND.MUD)[None, None, :] * wet
    specks(rng, albedo, 420, GROUND.STRAW, (10, 22), 2.0)
    specks(rng, albedo, 120, (150, 118, 82), (6, 12), 3.0)
    mask = np.zeros((P, P))
    tx.stamp_planar(rng, 22, (10, 18), [srgb(ROCK.ROCK), srgb(ROCK.ROCK_LIGHT)], albedo, mask, [], 5)
    albedo = tx.drop_shadow(albedo, mask, 5, 0.25)
    return tx.to8(np.clip(albedo, 0, 1))


def forest_floor(rng):
    """The floor under the firs: needles over moss in large soft patches, darker shade pools,
    and a litter of needles; no stones (the rocks are pieces)."""
    base = two_tone(rng, GROUND.FLOOR_MOSS, GROUND.FLOOR, lo_cut=2, hi_cut=9, bias=-0.3)
    shade = tx.fourier_noise(rng, (P, P), 2.0, lo_cut=2, hi_cut=7)
    dark = tx.smoothstep(0.6, 1.3, shade)[..., None]
    base = base * (1 - dark) + srgb(GROUND.FLOOR_DARK)[None, None, :] * dark
    litter = tx.fourier_noise(rng, (P, P), 1.8, lo_cut=4, hi_cut=16)
    needles = tx.smoothstep(0.9, 1.4, litter)[..., None] * 0.75
    base = base * (1 - needles) + srgb(GROUND.NEEDLES)[None, None, :] * needles
    specks(rng, base, 700, GROUND.NEEDLES, (6, 13), 1.4)
    specks(rng, base, 300, GROUND.FLOOR_DARK, (5, 10), 1.4)
    return tx.to8(np.clip(base, 0, 1))


def main() -> int:
    os.makedirs(OUT, exist_ok=True)
    road_rgb = road(np.random.default_rng(20261101))
    images = {
        "road": road_rgb,
        "roadRim": tx.planar_rim(road_rgb),
        "camp": camp(np.random.default_rng(20261102)),
        "forestFloor": forest_floor(np.random.default_rng(20261103)),
    }
    for name, rgb in images.items():
        path = os.path.join(OUT, name + ".png")
        tx.write_png(path, rgb)
        mean = rgb.reshape(-1, 3).mean(axis=0)
        print(f"[forest-textures] {name}: mean sRGB ({mean[0]:.0f}, {mean[1]:.0f}, {mean[2]:.0f}) -> {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
