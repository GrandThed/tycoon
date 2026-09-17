"""Three candidate path textures for the Studio look test (A solid core, B SurfaceAppearance, C stylised).

    "/c/Program Files/Blender Foundation/Blender 5.2/5.2/python/bin/python.exe" tools/pathtest/textures.py

Needs numpy (Blender's bundled Python). Writes tools/pathtest/out/tex/:
  A_color.png                RGBA, MeshPart.TextureID
  B_color.png B_normal.png B_rough.png   SurfaceAppearance ColorMap (RGBA) / NormalMap / RoughnessMap
  C_color.png                RGBA, MeshPart.TextureID
  preview_<X>.png            2x1 tile over grass at full size and at the 1/4 and 1/8 mips (never uploaded)

Why these look the way they do (the second attempt read as "faint brown smudges" in Studio):
- The dirt is lighter than the grass. Village grass (106,127,63) and the old dirt (126,99,66) have
  almost the same luminance, so only hue separated them and that vanishes at distance.
- Alpha is 1 across the core; only the outer RIM_V of v on each side ramps to 0 at the mesh border.
- Detail is sized for the 1/8 mip a player sees from 30-40 studs (~18 texels per stud): colour patches
  of 1-2 studs, pebbles of 0.2-0.45 studs with dark contact edges, no fine grain as the main signal.
- Colour is defined (dirt, never black) where alpha is 0, so mip filtering cannot darken the rim.

Layout matches tools/pathtest/patch.py: image x = u (TEXTURE_LENGTH studs per 1024 px, seamless),
image y = v across the mesh (row 0 = one outline, row 511 = the other). Every draw comes from a
seeded generator, so the bytes are reproducible.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "paths"))
from texture import fourier_noise, fourier_noise_1d, smoothstep, write_png  # noqa: E402

OUT = HERE / "out" / "tex"
W, H = 1024, 512
RIM_V = 0.1  # patch.py RIM_V: alpha reaches 1 no further than this from the mesh border
GRASS = (106, 127, 63)
PX_PER_STUD = 142.0  # both axes (patch.py EDGE * width = 3.6 studs across 512 px)


def srgb(c):
    return np.array(c, dtype=np.float64) / 255.0


def edge_distance():
    """Per-pixel distance from the nearer mesh border, in v units (0 at the border, 0.5 at centre)."""
    v = (np.arange(H, dtype=np.float64) + 0.5) / H
    e = 0.5 - np.abs(v - 0.5)
    return np.broadcast_to(e[:, None], (H, W)), np.broadcast_to((v < 0.5)[:, None], (H, W))


def rim_alpha(rng, lo, hi, wobble_amp, crumb_amp):
    """Alpha 0 at the border, 1 inside, with the ramp [lo, hi] (v units) wandering along u so the
    outline is irregular. hi + wobble stays below RIM_V, so the core is always solid."""
    e, top = edge_distance()
    w_top = fourier_noise_1d(rng, W, 1.3, hi_cut=14)
    w_bot = fourier_noise_1d(rng, W, 1.3, hi_cut=14)
    wob = np.where(top, w_top[None, :], w_bot[None, :]) * wobble_amp
    crumb = fourier_noise(rng, (H, W), 0.6, lo_cut=30, hi_cut=120) * crumb_amp
    shift = np.clip(wob + crumb, -lo * 0.9, RIM_V - hi - 0.004)
    a = smoothstep(lo + shift, hi + shift, e)
    a *= smoothstep(0.0, 0.006, e)  # the mesh border itself is always fully transparent
    return a


def stamp_pebbles(rng, count, r_range, v_band, palette, height, albedo, mask, placed, flat=False, avoid=()):
    """Elliptical pebbles, wrapping along u, never crossing the rim band and never touching another
    pebble (a heap of overlapping stones reads as gravel, not a path). `avoid` lists v centres of
    worn tracks where a pebble is rejected with probability 0.8. Fills height, albedo and mask in place."""
    stamped = 0
    for _ in range(count * 30):
        if stamped >= count:
            break
        r = float(rng.uniform(*r_range))
        ecc = rng.uniform(0.6, 0.95)
        ang = rng.uniform(0, np.pi)
        cy = rng.uniform(v_band[0] * H + r, v_band[1] * H - r)
        cx = rng.uniform(0, W)
        if any(abs(cy / H - t) < 0.05 for t in avoid) and rng.uniform() < 0.8:
            continue
        if any(min(abs(cx - px), W - abs(cx - px)) ** 2 + (cy - py) ** 2 < (r + pr + 4) ** 2 for px, py, pr in placed):
            continue
        placed.append((cx, cy, r))
        stamped += 1
        colour = palette[int(rng.integers(len(palette)))] * rng.uniform(0.92, 1.06)
        rad = int(np.ceil(r + 3))
        y0, y1 = int(max(0, cy - rad)), int(min(H, cy + rad + 1))
        ys = np.arange(y0, y1)[:, None]
        xr = np.arange(int(cx - rad), int(cx + rad) + 1)
        xs = (xr % W)[None, :]
        dx, dy = xr[None, :] - cx, ys - cy
        ca, sa = np.cos(ang), np.sin(ang)
        lx = (dx * ca + dy * sa) / r
        ly = (-dx * sa + dy * ca) / (r * ecc)
        d = np.sqrt(lx * lx + ly * ly)
        inside = np.clip((1 - d) * r * 0.7, 0, 1)  # ~1.5 px anti-aliased outline
        dome = np.sqrt(np.clip(1 - d * d, 0, 1)) * r
        yi, xi = np.broadcast_to(ys, d.shape), np.broadcast_to(xs, d.shape)
        take = inside > 0
        cur_h = height[yi, xi]
        new_h = np.where(take, np.maximum(cur_h, dome * (0.35 if flat else 0.6)), cur_h)
        height[yi, xi] = new_h
        m_old = mask[yi, xi]
        blend = inside[..., None]
        albedo[yi, xi] = albedo[yi, xi] * (1 - blend) + colour[None, None, :] * blend
        mask[yi, xi] = np.maximum(m_old, inside)


def shade_from_height(height, strength, ambient):
    gx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * 0.5
    gy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * 0.5
    n = np.stack([-gx * strength, -gy * strength, np.ones_like(gx)], axis=-1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    light = np.array([-0.5, -0.6, 0.62])
    light /= np.linalg.norm(light)
    lam = np.clip((n * light).sum(-1), 0, 1) / light[2]
    return ambient + (1 - ambient) * lam, n


def normal_map(height, strength):
    """Tangent-space, OpenGL convention (green = +V up the image), which Roblox SurfaceAppearance
    expects. Image rows grow downward, so the up-image slope is minus the row gradient."""
    gx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * 0.5
    g_row = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * 0.5
    g_up = -g_row
    n = np.stack([-gx * strength, -g_up * strength, np.ones_like(gx)], axis=-1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n * 0.5 + 0.5


def contact_shadow(height, shift, amount):
    shifted = np.roll(np.roll(height, shift, axis=0), shift, axis=1)
    return np.clip((shifted - height) * amount, 0, 0.45)


# ---------------------------------------------------------------- A / B: solid dirt


def dirt_textures(rng):
    """Shared layout for A and B: returns (A rgba, B colour rgba, B normal rgb, B roughness)."""
    base = srgb((160, 124, 84))
    low = fourier_noise(rng, (H, W), 2.4, hi_cut=7)  # 1.5-3 stud patches
    mid = fourier_noise(rng, (H, W), 1.6, lo_cut=5, hi_cut=26)  # ~0.4-1 stud mottling
    warm = fourier_noise(rng, (H, W), 2.2, hi_cut=6)
    grain = fourier_noise(rng, (H, W), 0.5, lo_cut=90)
    # patches lighten more than they darken: deep brown blotches read as mud, not packed dirt
    patches = np.where(low > 0, 0.15 * low, 0.07 * low)
    colour = base[None, None, :] * (1 + patches + 0.05 * mid + 0.02 * grain)[..., None]
    colour += (0.045 * warm)[..., None] * np.array([1.0, 0.6, 0.15])
    # two worn wheel tracks along u: the strongest "this is a path" cue at distance
    v = (np.arange(H) + 0.5) / H
    track_wob = fourier_noise_1d(rng, W, 1.8, hi_cut=6) * 0.018
    tracks = np.zeros((H, W))
    for centre in (0.33, 0.67):
        dv = np.abs(v[:, None] - (centre + track_wob[None, :]))
        tracks = np.maximum(tracks, smoothstep(0.08, 0.03, dv))
    colour *= (1 - 0.11 * tracks * (0.7 + 0.3 * mid.clip(-1, 1)))[..., None]

    height = 0.8 * mid + 0.25 * grain
    albedo = colour.copy()
    mask = np.zeros((H, W))
    stones = [srgb((186, 178, 162)), srgb((168, 156, 138)), srgb((122, 106, 90)), srgb((198, 170, 128))]
    # sparse in the worn tracks' centre, more on the shoulders; two sizes so the 1/8 mip keeps some
    placed = []
    tracks_v = (0.33, 0.67)
    stamp_pebbles(rng, 9, (26, 40), (RIM_V + 0.03, 1 - RIM_V - 0.03), stones, height, albedo, mask, placed, avoid=tracks_v)
    stamp_pebbles(rng, 26, (13, 21), (RIM_V + 0.02, 1 - RIM_V - 0.02), stones, height, albedo, mask, placed, avoid=tracks_v)
    stamp_pebbles(rng, 45, (6, 10), (RIM_V, 1 - RIM_V), stones, height, albedo, mask, placed, avoid=tracks_v)

    shade_full, _ = shade_from_height(height, 0.22, 0.55)
    cs = contact_shadow(height, 4, 0.06)
    a_col = albedo * (shade_full - cs)[..., None]
    a_col = np.clip(a_col, 0, 1)

    alpha = rim_alpha(rng, 0.012, 0.07, 0.022, 0.006)
    # A and B share alpha and layout; B's albedo carries only a hint of the baked light because
    # the normal map does the rest in Studio.
    shade_soft = 1 - 0.35 * (1 - shade_full) - 0.5 * cs
    b_col = np.clip(albedo * shade_soft[..., None], 0, 1)
    nmap = normal_map(height, 0.18)
    rough = np.clip(0.95 - 0.35 * mask, 0, 1)
    return rgba(a_col, alpha), rgba(b_col, alpha), to8(nmap), to8(rough)


# ---------------------------------------------------------------- C: stylised


def stylised(rng):
    light = srgb((194, 155, 106))
    dark = srgb((178, 139, 93))
    low = fourier_noise(rng, (H, W), 2.0, lo_cut=4, hi_cut=16)
    # two tones with a soft boundary: flat, blob-shaped worn patches (~1 stud) like the Kenney
    # palette, never bands across the path, which repeat visibly every tile
    tone = smoothstep(-0.2, 0.2, low + 0.8)
    colour = dark[None, None, :] * (1 - tone[..., None]) + light[None, None, :] * tone[..., None]
    height = np.zeros((H, W))
    albedo = colour.copy()
    mask = np.zeros((H, W))
    stones = [srgb((212, 198, 170)), srgb((148, 122, 96)), srgb((200, 184, 156))]
    placed = []
    stamp_pebbles(rng, 9, (24, 34), (RIM_V + 0.05, 1 - RIM_V - 0.05), stones, height, albedo, mask, placed, flat=True)
    stamp_pebbles(rng, 16, (12, 18), (RIM_V + 0.04, 1 - RIM_V - 0.04), stones, height, albedo, mask, placed, flat=True)
    # one flat drop shadow per pebble (offset copy of the mask), cel-style instead of a lit dome
    shadow = np.roll(np.roll(mask, 5, axis=0), 5, axis=1) * (1 - mask)
    colour = albedo * (1 - 0.28 * shadow[..., None])
    alpha = rim_alpha(rng, 0.03, 0.05, 0.02, 0.0)
    return rgba(np.clip(colour, 0, 1), alpha)


# ---------------------------------------------------------------- planar (round 2: C2 / C3)

P = 1024  # square, seamless on both axes
P_TILE = 11.0  # studs per repeat; must equal planar.py TILE (~93 px per stud)


def stamp_planar(rng, count, r_range, palette, albedo, mask, placed, shadow_px):
    """Flat pebbles that wrap on BOTH axes (the planar texture tiles in x and z), never touching."""
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


def planar_fill(rng):
    """C's stylised look, opaque and tiling on both axes: warm packed dirt, gentle two-tone worn
    blobs, a few bold flat pebbles with one hard drop shadow each. No directional feature (no wheel
    tracks), because the mapping is world-planar and a path may cross the tile in any direction."""
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
    shadow = np.roll(np.roll(mask, shadow_px, axis=0), shadow_px, axis=1) * (1 - mask)
    out = albedo * (1 - 0.26 * shadow[..., None])
    return to8(np.clip(out, 0, 1))


def planar_rim(fill_rgb):
    """C3's rim: the same image, darker and a little desaturated, so a rim beside a fill reads as
    the trodden shoulder of the same path and two rims that overlap are identical texels."""
    x = fill_rgb.astype(np.float64) / 255.0
    lum = (x * np.array([0.2126, 0.7152, 0.0722])).sum(-1, keepdims=True)
    return to8(np.clip((x * 0.75 + lum * 0.25) * 0.72, 0, 1))


def planar_preview(rgb, path):
    """2x2 tiles at full size, the 1/4 mip and the 1/8 mip: checks both seams at once."""
    rows = []
    for factor in (1, 4, 8):
        m = downsample(np.dstack([rgb, np.full(rgb.shape[:2], 255, np.uint8)]), factor) if factor > 1 else rgb.astype(np.float64)
        m = m[..., :3]
        m = np.repeat(np.repeat(m, factor, axis=0), factor, axis=1)
        rows.append(np.tile(m, (2, 2, 1)) / 255.0)
    img = to8(np.concatenate(rows, axis=0))
    write_png(path, downsample(np.dstack([img, np.full(img.shape[:2], 255, np.uint8)]), 4).round().astype(np.uint8)[..., :3])


# ---------------------------------------------------------------- output helpers


def to8(x):
    return (np.clip(x, 0, 1) * 255 + 0.5).astype(np.uint8)


def rgba(colour, alpha):
    return np.dstack([to8(colour), to8(alpha)])


def downsample(rgba8, factor):
    """Box-filtered mip, straight (non-premultiplied) like a GPU mip chain of an uploaded PNG."""
    x = rgba8.astype(np.float64)
    h, w = x.shape[0] // factor, x.shape[1] // factor
    return x[: h * factor, : w * factor].reshape(h, factor, w, factor, -1).mean(axis=(1, 3))


def preview(rgba8, path):
    """Rows: full size, 1/4 mip, 1/8 mip (each nearest-upscaled back), 2 tiles wide, over grass."""
    rows = []
    for factor in (1, 4, 8):
        m = downsample(rgba8, factor) if factor > 1 else rgba8.astype(np.float64)
        m = np.repeat(np.repeat(m, factor, axis=0), factor, axis=1)
        tile = np.tile(m, (1, 2, 1)) / 255.0
        pad = np.ones((40, tile.shape[1], 1)) * np.array(GRASS) / 255.0
        comp = tile[..., :3] * tile[..., 3:4] + np.array(GRASS) / 255.0 * (1 - tile[..., 3:4])
        rows += [pad, comp]
    img = np.concatenate(rows + [rows[0]], axis=0)
    small = downsample(to8(img).astype(np.uint8), 2)
    write_png(path, small.round().astype(np.uint8))


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    a, b_col, b_nrm, b_rough = dirt_textures(np.random.default_rng(20260917))
    c = stylised(np.random.default_rng(20260918))
    files = {
        "A_color.png": a,
        "B_color.png": b_col,
        "B_normal.png": b_nrm,
        "B_rough.png": np.dstack([b_rough] * 3),
        "C_color.png": c,
    }
    for name, img in files.items():
        write_png(OUT / name, img)
        print("wrote", OUT / name, img.shape)
    fill = planar_fill(np.random.default_rng(20260919))
    rim = planar_rim(fill)
    for name, img in (("P_fill.png", fill), ("P_rim.png", rim)):
        write_png(OUT / name, img)
        print("wrote", OUT / name, img.shape)
    planar_preview(fill, OUT / "preview_P_fill.png")
    planar_preview(rim, OUT / "preview_P_rim.png")
    preview(a, OUT / "preview_A.png")
    preview(b_col, OUT / "preview_B.png")
    preview(c, OUT / "preview_C.png")
    print(f"P_fill: luminance {(fill.astype(float) * np.array([0.2126, 0.7152, 0.0722])).sum(-1).mean():.0f}, "
          f"P_rim {(rim.astype(float) * np.array([0.2126, 0.7152, 0.0722])).sum(-1).mean():.0f}, grass 118; "
          f"{P_TILE:g} studs per tile")
    lum = lambda rgb: 0.2126 * rgb[..., 0] + 0.7152 * rgb[..., 1] + 0.0722 * rgb[..., 2]  # noqa: E731
    for name, img in (("A", a), ("C", c)):
        core = img[int(H * 0.2) : int(H * 0.8)]
        print(f"{name}: core luminance {lum(core[..., :3].astype(float)).mean():.0f} vs grass {lum(np.array(GRASS, float)):.0f}; "
              f"alpha==255 over {100 * (img[..., 3] == 255).mean(axis=1).__ge__(0.999).mean():.0f}% of rows")
    return 0


if __name__ == "__main__":
    os.chdir(HERE.parent.parent)
    sys.exit(main())
