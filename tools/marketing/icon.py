"""Experience-icon candidates for M10 (INTERFACES "M10 contracts -- Icons and thumbnails").

Each candidate is a blueprint scene rendered by Blender on a transparent film (icon_scene.py),
then painted over a stylised sky with a silhouette glow and a vignette here under the system `py`
(Blender's Python has no Pillow). Output: assets/marketing/icon/icon_<name>.png (512 x 512) and
contact_sheet.png, which also shows every candidate at 64 px on the (24, 24, 28) store tile.

    py tools/marketing/icon.py                        # render every candidate, then the sheet
    py tools/marketing/icon.py --only skyline,launch  # re-render some, re-compose the rest
    py tools/marketing/icon.py --compose-only         # repaint skies/sheet from the last renders

BLENDER=<path> overrides the Blender executable.
"""

import argparse
import json
import math
import os
import random
import subprocess
import sys

from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter, ImageFont

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
BLUEPRINTS = os.path.join(REPO_ROOT, "tools", "testfit", "blueprints")
SCENE_SCRIPT = os.path.join(REPO_ROOT, "tools", "marketing", "icon_scene.py")
OUT_DIR = os.path.join(REPO_ROOT, "assets", "marketing", "icon")
RAW_DIR = os.path.join(OUT_DIR, "_raw")
BLENDER = os.environ.get("BLENDER", r"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe")

# Rendered at twice the icon size and downsampled, which is cheaper than more EEVEE samples for
# clean silhouette edges.
WORK = 1024
ICON = 512
SMALL = 64
TILE = (24, 24, 28)
FINAL_STAGE = 4


def model(era, name, pos, rot_y=0.0, stage=FINAL_STAGE, scale=1.0):
    return {
        "blueprint": os.path.join(BLUEPRINTS, era, f"{name}.json"),
        "name": name,
        "stage": stage,
        "pos": list(pos),
        "rotY": rot_y,
        "scale": scale,
    }


DAY_LIGHTS = [
    {"from": [0.8, 1.1, -0.5], "energy": 3.2, "color": [255, 244, 226]},
    {"from": [-0.6, 0.5, 1.0], "energy": 2.2, "color": [200, 225, 255]},  # rim from behind
]

# The fixed (+X, -Z) camera quadrant looks up +Z, so screen right is scene -X: a row that must
# rise left to right is laid out toward -X.
CANDIDATES = [
    {
        "name": "skyline",
        "label": "SkyscraperA hero, low angle, blue sky",
        "models": [
            model("Metropolis", "SkyscraperA", (0, 0, 0)),
            model("Metropolis", "OfficeTowerA", (13, 0, 10)),
            model("Metropolis", "HotelTower", (-13, 0, 14)),
        ],
        "boxes": [{"size": [600, 0.4, 600], "pos": [0, -0.2, 0], "color": [74, 78, 90]}],
        "camera": {"eye": [20, 1.5, -36], "target": [-1, 19, 0], "lens": 40},
        "world": {"ambient": [170, 200, 240], "ambientStrength": 0.7},
        "lights": DAY_LIGHTS,
        "sky": {"stops": [(0.0, (6, 48, 170)), (0.6, (30, 116, 230)), (1.0, (100, 185, 250))],
                "sun": (0.85, 0.1, (255, 245, 210), False), "clouds": [(0.82, 0.3, 0.3), (0.12, 0.2, 0.22)]},
        "glow": ((220, 240, 255), 0.6),
    },
    {
        "name": "launch",
        "label": "LaunchTower in deep space",
        "models": [model("OrbitalColony", "LaunchTower", (0, 0, 0))],
        "islands": [{"pos": [0, 0, 0], "radius": 13, "depth": 10, "top": [96, 88, 112], "side": [62, 54, 80], "seed": 3}],
        "camera": {"dir": [0.6, 0.12, -1.0], "lens": 30, "margin": 0.93, "offset": [0.08, -0.06], "fitGround": True},
        "world": {"ambient": [120, 90, 190], "ambientStrength": 0.5},
        "lights": [
            {"from": [0.9, 1.0, -0.6], "energy": 3.0, "color": [255, 236, 220]},
            {"from": [-0.8, 0.3, 0.9], "energy": 3.5, "color": [90, 255, 230]},
        ],
        "sky": {"stops": [(0.0, (14, 6, 40)), (0.55, (58, 28, 110)), (1.0, (20, 150, 160))],
                "stars": 150, "planet": (0.23, 0.24, 0.15, (255, 140, 90), (150, 40, 110))},
        "glow": ((120, 255, 235), 0.5),
    },
    {
        "name": "castle",
        "label": "CastleKeep at sunset (Village)",
        "models": [
            model("Village", "CastleKeep", (0, 0, 0)),
            model("Village", "TreeOak", (-11, 0, -6)),
            model("Village", "TreeOak", (10, 0, -9)),
        ],
        "islands": [{"pos": [0, 0, 0], "radius": 15, "depth": 11, "top": [104, 176, 70], "side": [138, 96, 64], "seed": 5}],
        "camera": {"dir": [0.75, 0.55, -1.0], "lens": 40, "margin": 1.0, "fitGround": True},
        "world": {"ambient": [255, 190, 170], "ambientStrength": 0.55},
        "lights": [
            {"from": [1.0, 0.8, -0.4], "energy": 3.0, "color": [255, 214, 170]},
            {"from": [-0.7, 0.4, 1.0], "energy": 3.0, "color": [255, 170, 110]},
        ],
        "sky": {"stops": [(0.0, (64, 52, 150)), (0.45, (220, 100, 130)), (0.75, (255, 160, 90)), (1.0, (255, 214, 120))],
                "sun": (0.62, 0.5, (255, 236, 170), True), "stars": 25},
        "glow": ((255, 220, 170), 0.55),
    },
    {
        "name": "erastack",
        "label": "Era stack: Windmill > ClockTower > SkyscraperA > LaunchTower",
        "models": [
            model("Village", "Windmill", (24, 0, -5)),
            model("Boomtown", "ClockTower", (8, 0, -1)),
            model("Metropolis", "SkyscraperA", (-8, 0, 2)),
            model("OrbitalColony", "LaunchTower", (-24, 0, 5)),
        ],
        "islands": [{"pos": [0, 0, 0], "radius": 11, "depth": 9, "stretch": [3.0, 1.2], "top": [104, 186, 72], "side": [132, 92, 60], "seed": 2}],
        "camera": {"dir": [0.22, 0.2, -1.0], "lens": 45, "margin": 0.97, "fitGround": True},
        "world": {"ambient": [190, 200, 235], "ambientStrength": 0.65},
        "lights": DAY_LIGHTS,
        "sky": {"diagonal": [(0.0, (255, 190, 110)), (0.35, (90, 175, 245)), (0.7, (40, 70, 170)), (1.0, (26, 12, 60))],
                "stars": 70, "starsFrom": 0.62},
        "glow": ((255, 255, 255), 0.6),
    },
    {
        "name": "growth",
        "label": "Growth: Windmill stage 0 > 2 > 4",
        "models": [
            model("Village", "Windmill", (15, 0, 12), stage=0),
            model("Village", "Windmill", (3, 0, 2), stage=2),
            model("Village", "Windmill", (-9, 0, -9), stage=4),
        ],
        "islands": [{"pos": [0, 0, 0], "radius": 21, "depth": 11, "top": [104, 186, 72], "side": [132, 92, 60], "seed": 11}],
        # Stage 4 nearest the lens: perspective adds to the real growth instead of hiding it.
        "camera": {"dir": [0.5, 0.3, -1.0], "lens": 30, "margin": 1.15, "offset": [0.0, 0.06]},
        "world": {"ambient": [180, 210, 245], "ambientStrength": 0.65},
        "lights": DAY_LIGHTS,
        "sky": {"stops": [(0.0, (30, 120, 230)), (1.0, (170, 225, 255))], "clouds": [(0.15, 0.22, 0.28), (0.85, 0.3, 0.3), (0.5, 0.8, 0.4)]},
        "glow": ((240, 250, 255), 0.5),
    },
    {
        "name": "tower",
        "label": "Growth: HotelTower stage 0 behind stage 4",
        "models": [
            model("Metropolis", "HotelTower", (8, 0, 7), stage=0),
            model("Metropolis", "HotelTower", (-6, 0, -4), stage=4),
        ],
        "islands": [{"pos": [0, 0, 0], "radius": 14, "depth": 8, "top": [104, 186, 72], "side": [132, 92, 60], "seed": 23}],
        "camera": {"dir": [0.6, 0.2, -1.0], "lens": 35, "margin": 1.12, "offset": [0.0, 0.05]},
        "world": {"ambient": [180, 210, 245], "ambientStrength": 0.65},
        "lights": DAY_LIGHTS,
        "sky": {"stops": [(0.0, (8, 70, 200)), (1.0, (120, 205, 255))]},
        "glow": ((240, 250, 255), 0.55),
    },
    {
        "name": "island",
        "label": "Floating Village plot corner",
        "models": [
            model("Village", "Windmill", (5, 0, 7)),
            model("Village", "Tavern", (-8, 0, 3)),
            model("Village", "HouseSmallA", (8, 0, -8)),
            model("Village", "Well", (-2, 0, -9)),
            model("Village", "TreeOak", (-14, 0, -5)),
            model("Village", "TreeOak", (-6, 0, 14)),
            model("Village", "TreeOak", (16, 0, 4)),
        ],
        "islands": [{"pos": [0, 0, 0], "radius": 21, "depth": 16, "top": [104, 186, 72], "side": [132, 92, 60], "seed": 17}],
        "camera": {"dir": [0.8, 0.75, -1.0], "lens": 40, "margin": 1.0, "fitGround": True},
        "world": {"ambient": [180, 210, 245], "ambientStrength": 0.65},
        "lights": DAY_LIGHTS,
        "sky": {"stops": [(0.0, (40, 140, 240)), (1.0, (150, 220, 255))], "clouds": [(0.85, 0.18, 0.28), (0.12, 0.62, 0.3), (0.9, 0.7, 0.26)]},
        "glow": ((240, 250, 255), 0.45),
    },
]


def log(msg):
    print(f"[icon] {msg}", flush=True)


def raw_path(name):
    return os.path.join(RAW_DIR, f"icon_{name}_raw.png")


def render_raw(candidate):
    scene = {
        "out": raw_path(candidate["name"]),
        "size": [WORK, WORK],
        "models": candidate["models"],
        "islands": candidate.get("islands", []),
        "boxes": candidate.get("boxes", []),
        "camera": candidate["camera"],
        "world": candidate["world"],
        "lights": candidate["lights"],
        "samples": 48,
    }
    os.makedirs(RAW_DIR, exist_ok=True)
    scene_path = os.path.join(RAW_DIR, f"icon_{candidate['name']}_scene.json")
    with open(scene_path, "w", encoding="utf-8") as handle:
        json.dump(scene, handle, indent=1)
    log(f"rendering {candidate['name']} ...")
    result = subprocess.run(
        [BLENDER, "-b", "-P", SCENE_SCRIPT, "--", "--scene", scene_path],
        capture_output=True, text=True,
    )
    for line in result.stdout.splitlines():
        if line.startswith("[icon]") or "WARNING" in line or "Error" in line:
            print("   ", line)
    if result.returncode != 0 or not os.path.isfile(scene["out"]):
        sys.exit(f"Blender failed for {candidate['name']}:\n{result.stderr[-2000:]}")


# --- Painting ------------------------------------------------------------------


def lerp_stops(stops, t):
    for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
        if t <= t1:
            f = 0.0 if t1 == t0 else (t - t0) / (t1 - t0)
            return tuple(round(a + (b - a) * f) for a, b in zip(c0, c1))
    return stops[-1][1]


def gradient(stops, size, diagonal):
    """A vertical (top->bottom) or diagonal (bottom-left->top-right) ramp."""
    n = 256
    ramp = Image.new("RGB", (n, 1))
    for i in range(n):
        ramp.putpixel((i, 0), lerp_stops(stops, i / (n - 1)))
    if not diagonal:
        return ramp.rotate(-90, expand=True).resize((size, size), Image.BILINEAR)
    # Rotating a wide ramp by 45 degrees and cropping the middle gives a clean diagonal.
    big = ramp.resize((size * 2, size * 2), Image.BILINEAR).rotate(45, resample=Image.BILINEAR)
    offset = size // 2
    return big.crop((offset, offset, offset + size, offset + size))


def radial_glow(size, cx, cy, radius, colour, strength):
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    r = radius * size
    draw.ellipse((cx * size - r, cy * size - r, cx * size + r, cy * size + r), fill=round(255 * strength))
    mask = mask.filter(ImageFilter.GaussianBlur(r * 0.45))
    return Image.new("RGB", (size, size), colour), mask


def paint_sky(spec, size, seed):
    rng = random.Random(seed)
    if "diagonal" in spec:
        sky = gradient(spec["diagonal"], size, diagonal=True)
    else:
        sky = gradient(spec["stops"], size, diagonal=False)

    if spec.get("stars"):
        draw = ImageDraw.Draw(sky)
        start = spec.get("starsFrom", 0.0)
        for _ in range(spec["stars"]):
            x = rng.uniform(start, 1.0) * size
            y = rng.uniform(0.0, 0.7 if start == 0.0 else 0.55) * size
            r = rng.choice((1.2, 1.6, 2.2, 3.2))
            draw.ellipse((x - r, y - r, x + r, y + r), fill=(255, 255, 240))
        sky = sky.filter(ImageFilter.GaussianBlur(0.6))

    if "sun" in spec:
        cx, cy, colour, disc_shown = spec["sun"]
        halo, mask = radial_glow(size, cx, cy, 0.34, colour, 0.75)
        sky.paste(halo, (0, 0), mask)
        if disc_shown:
            disc = Image.new("L", (size, size), 0)
            r = 0.085 * size
            ImageDraw.Draw(disc).ellipse((cx * size - r, cy * size - r, cx * size + r, cy * size + r), fill=255)
            sky.paste(Image.new("RGB", (size, size), (255, 252, 235)), (0, 0), disc.filter(ImageFilter.GaussianBlur(3)))

    if "planet" in spec:
        cx, cy, radius, light, dark = spec["planet"]
        halo, mask = radial_glow(size, cx, cy, radius * 1.45, light, 0.45)
        sky.paste(halo, (0, 0), mask)
        r = radius * size
        body = gradient([(0.0, light), (1.0, dark)], size, diagonal=True)
        disc = Image.new("L", (size, size), 0)
        ImageDraw.Draw(disc).ellipse((cx * size - r, cy * size - r, cx * size + r, cy * size + r), fill=255)
        # Bands sell "planet" rather than "circle" at icon size.
        bands = Image.new("L", (size, size), 0)
        bd = ImageDraw.Draw(bands)
        for k in range(-3, 4):
            y = cy * size + k * r * 0.28
            bd.rectangle((0, y - r * 0.05, size, y + r * 0.05), fill=60)
        body.paste(Image.new("RGB", (size, size), dark), (0, 0), ImageChops.multiply(bands, disc))
        sky.paste(body, (0, 0), disc.filter(ImageFilter.GaussianBlur(1.5)))
        ring = Image.new("L", (size, size), 0)
        rd = ImageDraw.Draw(ring)
        rd.ellipse((cx * size - r * 1.9, cy * size - r * 0.42, cx * size + r * 1.9, cy * size + r * 0.42), outline=200, width=max(3, size // 110))
        # The ring's back half hides behind the planet body.
        ring = ImageChops.subtract(ring, ImageChops.multiply(disc, Image.linear_gradient("L").resize((size, size)).point(lambda v: 255 if v < cy * 255 else 0)))
        sky.paste(Image.new("RGB", (size, size), (255, 220, 200)), (0, 0), ring.filter(ImageFilter.GaussianBlur(1)))

    # Clouds are placed by hand, (x, y, width) in frame fractions: random placement kept stacking
    # two into one lumpy speech-bubble shape.
    for cx, cy, w in spec.get("clouds", []):
        cloud = Image.new("L", (size, size), 0)
        cd = ImageDraw.Draw(cloud)
        cx, cy, w = cx * size, cy * size, w * size
        for ox, rr in ((-0.55, 0.26), (-0.2, 0.4), (0.2, 0.33), (0.52, 0.22)):
            x, r = cx + ox * w, rr * w
            cd.ellipse((x - r, cy - r, x + r, cy + r), fill=225)
        cd.rectangle((cx - w, cy + w * 0.08, cx + w, size), fill=0)
        sky.paste(Image.new("RGB", (size, size), (255, 255, 255)), (0, 0), cloud.filter(ImageFilter.GaussianBlur(size * 0.004)))
    return sky


def glow_behind(layer, colour, strength, size):
    """A soft halo in the sky's light colour around the subject: separates a dark silhouette from
    a dark sky, which is what keeps it legible at 64 px."""
    alpha = layer.getchannel("A")
    wide = alpha.filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.GaussianBlur(size * 0.02))
    wide = wide.point(lambda v: round(v * strength))
    return Image.new("RGB", (size, size), colour), wide


def vignette(image, amount=0.45):
    """Darken toward the corners by brightness, not by blending in a dark colour: a blend greys a
    pale sky corner, a brightness drop keeps its hue."""
    size = image.size[0]
    mask = Image.radial_gradient("L").resize((size, size), Image.BILINEAR)
    mask = mask.point(lambda v: round(min(255, max(0, v - 110) * 1.75)))
    return Image.composite(ImageEnhance.Brightness(image).enhance(1.0 - amount), image, mask)


def compose(candidate):
    layer = Image.open(raw_path(candidate["name"])).convert("RGBA")
    size = layer.size[0]
    image = paint_sky(candidate["sky"], size, seed=len(candidate["name"]) * 31)
    colour, strength = candidate["glow"]
    halo, mask = glow_behind(layer, colour, strength, size)
    image.paste(halo, (0, 0), mask)
    image.paste(layer.convert("RGB"), (0, 0), layer.getchannel("A"))
    image = ImageEnhance.Color(image).enhance(1.18)
    image = ImageEnhance.Contrast(image).enhance(1.06)
    image = vignette(image)
    image = image.resize((ICON, ICON), Image.LANCZOS)
    path = os.path.join(OUT_DIR, f"icon_{candidate['name']}.png")
    image.save(path, optimize=True)
    log(f"wrote {os.path.relpath(path, REPO_ROOT)}")
    return path


def contact_sheet(candidates, paths):
    """Each candidate at full size with its label, then every candidate at 64 px on the store's
    dark tile -- the size a player actually meets it at."""
    font = ImageFont.load_default(size=22)
    small_font = ImageFont.load_default(size=14)
    cols = 3
    pad = 24
    cell_h = ICON + 40 + SMALL + 24
    rows = math.ceil(len(paths) / cols)
    strip_h = SMALL + 60
    width = cols * ICON + (cols + 1) * pad
    height = rows * cell_h + (rows + 1) * pad + strip_h
    sheet = Image.new("RGB", (width, height), (40, 40, 46))
    draw = ImageDraw.Draw(sheet)
    for index, (candidate, path) in enumerate(zip(candidates, paths)):
        icon = Image.open(path).convert("RGB")
        x = pad + (index % cols) * (ICON + pad)
        y = pad + (index // cols) * (cell_h + pad)
        sheet.paste(icon, (x, y))
        draw.text((x, y + ICON + 8), f"{index + 1}. icon_{candidate['name']}", fill=(240, 240, 240), font=font)
        tile_y = y + ICON + 40
        draw.rectangle((x, tile_y - 8, x + ICON, tile_y + SMALL + 8), fill=TILE)
        sheet.paste(icon.resize((SMALL, SMALL), Image.LANCZOS), (x + 8, tile_y))
        draw.text((x + SMALL + 20, tile_y + 4), candidate["label"], fill=(200, 200, 205), font=small_font)
        draw.text((x + SMALL + 20, tile_y + 26), "64 px on (24,24,28)", fill=(130, 130, 140), font=small_font)
    # All candidates side by side at 64 px, the way a store row would show them.
    y = height - strip_h
    draw.rectangle((0, y, width, height), fill=TILE)
    draw.text((pad, y + 6), "64 px row", fill=(150, 150, 160), font=small_font)
    for index, path in enumerate(paths):
        icon = Image.open(path).convert("RGB").resize((SMALL, SMALL), Image.LANCZOS)
        sheet.paste(icon, (pad + index * (SMALL + 20), y + 30))
    out = os.path.join(OUT_DIR, "contact_sheet.png")
    sheet.save(out, optimize=True)
    log(f"wrote {os.path.relpath(out, REPO_ROOT)}")


def main():
    parser = argparse.ArgumentParser(prog="icon.py")
    parser.add_argument("--only", help="comma list of candidate names to re-render in Blender")
    parser.add_argument("--compose-only", action="store_true", help="reuse the last Blender renders")
    args = parser.parse_args()
    names = [c["name"] for c in CANDIDATES]
    only = set(args.only.split(",")) if args.only else None
    if only and not only <= set(names):
        sys.exit(f"unknown candidate(s): {', '.join(sorted(only - set(names)))}; known: {', '.join(names)}")
    os.makedirs(OUT_DIR, exist_ok=True)
    for candidate in CANDIDATES:
        wanted = not args.compose_only and (only is None or candidate["name"] in only)
        if wanted or not os.path.isfile(raw_path(candidate["name"])):
            render_raw(candidate)
    paths = [compose(candidate) for candidate in CANDIDATES]
    contact_sheet(CANDIDATES, paths)


if __name__ == "__main__":
    main()
