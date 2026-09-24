#!/usr/bin/env python
"""Experience thumbnails (M10 testfit round): 1920x1080 candidates for the Growth, Eras, Scale and
Social hooks, rendered in Blender from the shipped blueprints and whole plotrender plots.

    py tools/marketing/thumbs.py                      # every candidate + contact sheet
    py tools/marketing/thumbs.py --only scale_metropolis,growth_tavern
    py tools/marketing/thumbs.py --post-only          # re-paint sky/text over the last renders

Outputs: assets/marketing/thumbs/<name>.png and contact_sheet.png; raw transparent renders and
the projected label anchors are kept in assets/marketing/thumbs/raw/ so text can be iterated
without re-rendering.

The scene content is never re-derived: whole plots come from plotrender.PlotScene (itself a mirror
of streetplan and the client), single buildings from their blueprints at a real stage. The Blender
half (thumb_scene.py) builds them with plotscene's own builders. Only the look is set here: sky,
light, camera, captions. Runs under `py` (Pillow, streetplan); Blender is only the renderer.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import random
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter, ImageFont

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "tools"))
sys.path.insert(0, str(REPO_ROOT / "tools" / "testfit"))

import plotrender  # noqa: E402
import streetplan  # noqa: E402

OUT_DIR = REPO_ROOT / "assets" / "marketing" / "thumbs"
RAW_DIR = OUT_DIR / "raw"
FONT_PATH = REPO_ROOT / "assets" / "marketing" / "fonts" / "TitanOne-Regular.ttf"
SCENE_SCRIPT = Path(__file__).with_name("thumb_scene.py")
SIZE = (1920, 1080)
MAX_BYTES = 3 * 1024 * 1024
WORKERS = 4
# The Roblox tile overlay covers the bottom 15 %; fitted content stays above this frame line
# (v runs -1 bottom .. +1 top, so -0.7 is 15 % up).
SAFE_BOTTOM = -0.66

DAY_SKY = ((70, 150, 235), (190, 225, 250))
SPACE_SKY = ((6, 8, 24), (48, 36, 84))
DAY_LIGHT = {"sun": 2.5, "elevation": 42, "azimuth": 35, "softness": 7, "fill": 0.45, "ambientStrength": 0.55}
SPACE_LIGHT = {
    "sun": 2.7,
    "elevation": 38,
    "azimuth": 40,
    "softness": 3,
    "fill": 0.45,
    "fillColor": [150, 140, 255],
    "ambient": [170, 170, 215],
    "ambientStrength": 0.5,
}
ERA_ORDER = ("Village", "Boomtown", "Metropolis", "OrbitalColony")
ERA_TITLES = {"Village": "VILLAGE", "Boomtown": "BOOMTOWN", "Metropolis": "METROPOLIS", "OrbitalColony": "ORBITAL"}
# What the plots stand on in these shots: a grass that stays green after the post saturation,
# and dark regolith for Orbital. Backdrop only, never read as part of a plot.
ERA_GROUND = {
    "Village": (78, 138, 58),
    "Boomtown": (84, 142, 62),
    "Metropolis": (84, 142, 62),
    "OrbitalColony": (62, 54, 70),
}


# --------------------------------------------------------------------------
# Scene content, straight from plotrender / blueprints
# --------------------------------------------------------------------------


_CITY = None


def city_config():
    global _CITY
    if _CITY is None:
        _CITY = json.loads((REPO_ROOT / "src" / "shared" / "Config" / "CityDressing.json").read_text(encoding="utf-8"))
    return _CITY


def plot_group(name, era_name, tier=None, owned="all", offset=(0.0, 0.0, 0.0), rot_y=0.0, stages=None, extra=()):
    """A whole plot exactly as plotrender builds it, minus its render-only aids (the dark apron and
    the blue reference box). `stages` pins some slots' buildings below their final stage."""
    era = streetplan.Era(era_name, city_config())
    network = streetplan.Network(era)
    owned_ids = plotrender.resolve_owned(era, owned, tier)
    scene = plotrender.PlotScene(era, network, owned_ids, 5 if tier is None else tier, staged=tier is not None).build()
    boxes = [b for b in scene.boxes if b["name"] not in ("Apron", "Player")]
    models = [dict(m) for m in scene.models]
    for model in models:
        if stages and model["name"] in stages:
            model["stage"] = stages[model["name"]]
    models.extend(extra)
    return {"name": name, "offset": list(offset), "rotY": rot_y, "boxes": boxes, "models": models}


def slot(era_name, slot_id):
    era = streetplan.Era(era_name, city_config())
    return next(s for s in era.slots if s["id"] == slot_id)


def building(model_name, era_name, pos, stage=None, rot_y=0.0, scale=1.0, prop=False):
    path = plotrender.blueprint_path(era_name, model_name, prop=prop)
    if path is None:
        raise SystemExit(f"no blueprint {era_name}/{model_name}")
    entry = {"name": model_name, "blueprint": str(path), "pos": list(pos), "rotY": rot_y}
    if stage is not None:
        entry["stage"] = stage
    if scale != 1.0:
        entry["scale"] = scale
    return entry


def slab(name, size, centre, color):
    """A plinth of the era's plot base, top at y 0 like a plot."""
    return {"name": name, "size": [size[0], 1.0, size[1]], "pos": [centre[0], -0.5, centre[1]], "color": list(color)}


def base_rgb(era_name):
    era = streetplan.Era(era_name, city_config())
    base = era.layout["baseColor"]
    return [int(v) if max(base) > 1 else int(v * 255) for v in base]


def pad_color(era_name):
    return plotrender.tint(base_rgb(era_name), plotrender.PAD_TINT)


def ground(era_name, haze, start=1.6, end=8.0):
    return {"color": list(ERA_GROUND[era_name]), "haze": list(haze), "y": -1.0, "hazeStart": start, "hazeEnd": end}


# --------------------------------------------------------------------------
# Candidates
# --------------------------------------------------------------------------


def growth_row(name, era_name, model_name, pitch, caption, sky, light):
    """One building at all five stages, left (bought) to right (level 100)."""
    models = []
    # The camera looks from +X, so +X is screen-left: stage 0 goes there to read left to right.
    xs = [(2 - i) * pitch for i in range(5)]
    for stage, x in enumerate(xs):
        models.append(building(model_name, era_name, (x, 0.0, 0.0), stage=stage))
    boxes = [slab("Plinth", (pitch * 5 + 6, 18), (0.0, 0.0), base_rgb(era_name))]
    for stage, x in enumerate(xs):
        boxes.append({"name": f"Pad{stage}", "size": [6, 0.2, 6], "pos": [x, 0.1, -9.0], "color": pad_color(era_name)})
    return {
        "name": name,
        "hook": "Growth",
        "groups": [{"name": "row", "boxes": boxes, "models": models}],
        "ground": ground(era_name, sky[1]),
        "light": light,
        "camera": {"dir": [0.3, 0.4, -1.0], "pitch": 12, "lens": 40, "window": [-0.95, 0.95, SAFE_BOTTOM, 0.56]},
        "anchors": {},
        "post": {"sky": sky, "captions": [caption]},
    }


def growth_duo(name, era_name, model_name, caption, sky, light, gap=24.0):
    """Stage 0 beside stage 4 with a chunky arrow between them: the bought-to-level-100 promise."""
    left, right = (gap / 2, 0.0, 0.0), (-gap / 2, 0.0, 0.0)
    models = [
        building(model_name, era_name, left, stage=0),
        building(model_name, era_name, right, stage=4),
    ]
    boxes = [slab("Plinth", (gap + 20, 18), (0.0, 0.0), base_rgb(era_name))]
    return {
        "name": name,
        "hook": "Growth",
        "groups": [{"name": "duo", "boxes": boxes, "models": models}],
        "ground": ground(era_name, sky[1]),
        "light": light,
        "camera": {"dir": [0.3, 0.36, -1.0], "pitch": 8, "lens": 40, "window": [-0.75, 0.75, SAFE_BOTTOM, 0.62]},
        "anchors": {"from": [left[0] - 5.5, 5.0, left[2] - 3], "to": [right[0] + 5.5, 5.0, right[2] - 3]},
        "post": {"sky": sky, "captions": [caption], "arrow": ("from", "to")},
    }


def eras_plots():
    """The four finished plots in a row, Village left to Orbital right, era names over each."""
    pitch = 132.0
    groups, anchors = [], {}
    for index, era_name in enumerate(ERA_ORDER):
        # +X is screen-left from this camera, so Village takes the +X end.
        x = (1.5 - index) * pitch
        groups.append(plot_group(era_name, era_name, offset=(x, 0.0, 0.0)))
        anchors[era_name] = [x, 0.0, 0.0]
    return {
        "name": "eras_plots",
        "hook": "Eras",
        "groups": groups,
        "ground": {"color": list(ERA_GROUND["Boomtown"]), "haze": list(DAY_SKY[1]), "y": -1.0, "hazeStart": 1.3, "hazeEnd": 5.0},
        "light": DAY_LIGHT,
        "camera": {"dir": [0.08, 0.5, -1.0], "pitch": 14, "lens": 32, "window": [-1.0, 1.0, SAFE_BOTTOM, 0.55]},
        "anchors": anchors,
        "post": {"sky": "day_to_space", "era_labels": True},
    }


# Landmark vignettes: a tall building of the era plus two neighbours from its own plot, each on a
# square of its plot base. Heights climb left to right exactly as the eras do in game.
VIGNETTES = {
    "Village": ("Watchtower", [("Tavern", (-12.0, 6.0), 270.0), ("Windmill", (11.0, 7.0), 90.0)]),
    "Boomtown": ("ClockTower", [("Diner", (-12.0, 6.0), 270.0), ("FireStation", (12.0, 7.0), 90.0)]),
    "Metropolis": ("SkyscraperA", [("HotelTower", (-13.0, 7.0), 270.0), ("BankTower", (13.0, 8.0), 90.0)]),
    "OrbitalColony": ("LaunchTower", [("FusionReactor", (-13.0, 8.0), 270.0), ("CommsArray", (13.0, 7.0), 90.0)]),
}


def eras_landmarks():
    pitch = 42.0
    groups, anchors = [], {}
    for index, era_name in enumerate(ERA_ORDER):
        x = (1.5 - index) * pitch
        hero, neighbours = VIGNETTES[era_name]
        models = [building(hero, era_name, (0.0, 0.0, -2.0))]
        for model_name, (nx, nz), rot in neighbours:
            models.append(building(model_name, era_name, (nx, 0.0, nz), rot_y=rot))
        boxes = [slab("Base", (pitch - 2, 32), (0.0, 0.0), base_rgb(era_name))]
        groups.append({"name": era_name, "offset": [x, 0.0, 0.0], "boxes": boxes, "models": models})
        anchors[era_name] = [x, 0.0, -16.0]
    return {
        "name": "eras_landmarks",
        "hook": "Eras",
        "groups": groups,
        "ground": {"color": list(ERA_GROUND["Boomtown"]), "haze": list(DAY_SKY[1]), "y": -1.0, "hazeStart": 1.5, "hazeEnd": 6.0},
        "light": DAY_LIGHT,
        "camera": {"dir": [0.1, 0.3, -1.0], "pitch": 4, "lens": 35, "window": [-0.98, 0.98, SAFE_BOTTOM, 0.66]},
        "anchors": anchors,
        "post": {"sky": "day_to_space", "era_labels": True},
    }


def scale_plot(name, era_name, dir_, pitch, lens, window, caption, sky, light):
    return {
        "name": name,
        "hook": "Scale",
        "groups": [plot_group(era_name, era_name)],
        "ground": ground(era_name, sky[1], 1.3, 5.0),
        "light": light,
        "camera": {"dir": list(dir_), "pitch": pitch, "lens": lens, "window": window},
        "anchors": {},
        "post": {"sky": sky, "captions": [caption]},
    }


def social(name, era_name, slot_id, stage, tier, walkers, caption, sky, light, view, lens=35):
    """Two people-kit walkers, scaled to a 5-stud avatar, on a buy pad in front of a building that
    is still growing. The walkers are the game's own ambient figures standing in for players,
    since a Roblox avatar cannot be rendered offline. `view` is (along the pad->building axis, to
    its side, up): the direction the lens looks from, relative to the pad."""
    s = slot(era_name, slot_id)
    pad = s["pad"]
    face = (s["position"][0] - pad[0], s["position"][1] - pad[1])
    length = math.hypot(*face)
    face = (face[0] / length, face[1] / length)
    side = (-face[1], face[0])
    look_from = (face[0] * view[0] + side[0] * view[1], view[2], face[1] * view[0] + side[1] * view[1])
    # They pose for the lens, turned a little toward each other, the way players line up for a
    # screenshot; a walker's front is -Z, so rotY atan2(-dx, -dz) points it along (dx, dz).
    to_eye = math.degrees(math.atan2(-look_from[0], -look_from[2]))
    avatar_scale = 5.0 / 1.8
    hero = []
    for index, walker in enumerate(walkers):
        k = -1.4 if index == 0 else 1.4
        pos = (pad[0] + side[0] * k, 0.2, pad[1] + side[1] * k)
        turn = to_eye + (-25.0 if index == 0 else 25.0) * (1 if view[1] > 0 else -1)
        hero.append(building(walker, era_name, pos, rot_y=turn, scale=avatar_scale, prop=True))
    plot = plot_group(era_name, era_name, tier=tier, stages={slot_id: stage})
    # The building moves to its own group, unchanged, so the camera can frame it with the players.
    hero.extend(m for m in plot["models"] if m["name"] == slot_id)
    plot["models"] = [m for m in plot["models"] if m["name"] != slot_id]
    return {
        "name": name,
        "hook": "Social",
        "groups": [plot, {"name": "hero", "boxes": [], "models": hero}],
        "ground": ground(era_name, sky[1], 3.0, 14.0),
        "light": light,
        "camera": {
            "dir": list(look_from),
            "pitch": 6,
            "lens": lens,
            "groups": ["hero"],
            "window": [-0.5, 0.5, SAFE_BOTTOM + 0.04, 0.5],
            "dof": {"focus": [pad[0], 3.0, pad[1]], "fstop": 4.0},
        },
        "anchors": {},
        "post": {"sky": sky, "captions": [caption]},
    }


def eras_slices():
    """Each era's finished plot from its own tycoon three-quarter, cut into four slanted columns,
    Village left to Orbital right, each under its own sky."""
    panels = []
    for era_name in ERA_ORDER:
        space = era_name == "OrbitalColony"
        sky = SPACE_SKY if space else DAY_SKY
        panels.append(
            {
                "name": f"eras_slices_{era_name}",
                "groups": [plot_group(era_name, era_name)],
                "ground": ground(era_name, sky[1], 1.3, 5.0),
                "light": SPACE_LIGHT if space else DAY_LIGHT,
                "camera": {"dir": [0.6, 0.55, -1.0], "pitch": 12, "lens": 30, "window": [-0.36, 0.36, -0.95, 0.5]},
                "anchors": {},
                "post": {"sky": sky},
            }
        )
    return {"name": "eras_slices", "hook": "Eras", "panels": panels, "post": {"slices": True, "era_labels": True}}


def candidates():
    # Overscan: the plot's near corner and sides run out of frame, so the city fills it.
    wide = [-1.3, 1.3, -1.25, 0.5]
    return [
        growth_row("growth_tavern_row", "Village", "Tavern", 12.0, "WATCH IT GROW", DAY_SKY, DAY_LIGHT),
        growth_duo("growth_banktower_duo", "Metropolis", "BankTower", "LEVEL IT UP!", DAY_SKY, DAY_LIGHT),
        growth_row("growth_comms_row", "OrbitalColony", "CommsArray", 12.0, "BUILD IT HIGHER", SPACE_SKY, SPACE_LIGHT),
        eras_plots(),
        eras_landmarks(),
        eras_slices(),
        scale_plot("scale_metropolis", "Metropolis", (0.8, 0.5, -1.0), 16, 28, wide, "BUILD A METROPOLIS", DAY_SKY, DAY_LIGHT),
        scale_plot("scale_orbital", "OrbitalColony", (0.7, 0.5, -1.0), 16, 28, wide, "BUILD A SPACE COLONY", SPACE_SKY, SPACE_LIGHT),
        scale_plot("scale_boomtown", "Boomtown", (0.75, 0.55, -1.0), 18, 28, wide, "GROW YOUR TOWN", DAY_SKY, DAY_LIGHT),
        social(
            "social_village", "Village", "tavern", 2, 3, ("WalkerA", "WalkerC"),
            "BUILD WITH FRIENDS", DAY_SKY, DAY_LIGHT, view=(-1.0, -0.55, 0.42),
        ),
        social(
            "social_boomtown", "Boomtown", "diner", 2, 3, ("WalkerA", "WalkerB"),
            "BUILD WITH FRIENDS", DAY_SKY, DAY_LIGHT, view=(-1.0, 0.6, 0.42),
        ),
        social(
            "social_metropolis", "Metropolis", "coffeeShop", 2, 3, ("WalkerB", "WalkerD"),
            "BUILD WITH FRIENDS", DAY_SKY, DAY_LIGHT, view=(-1.0, 0.6, 0.42),
        ),
    ]


# --------------------------------------------------------------------------
# Rendering
# --------------------------------------------------------------------------


def raw_path(name):
    return RAW_DIR / f"thumb_{name}_raw.png"


def anchors_path(name):
    return RAW_DIR / f"thumb_{name}_anchors.json"


def render(spec, blender):
    scene = {k: v for k, v in spec.items() if k not in ("post", "hook")}
    scene["out"] = str(raw_path(spec["name"]))
    scene["anchorsOut"] = str(anchors_path(spec["name"]))
    scene["size"] = list(SIZE)
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", prefix="thumb_", suffix=".json", delete=False, encoding="utf-8") as handle:
        json.dump(scene, handle)
        scene_file = handle.name
    started = time.time()
    try:
        result = subprocess.run(
            [blender, "-b", "-P", str(SCENE_SCRIPT), "--", "--scene", scene_file],
            capture_output=True,
            text=True,
        )
    finally:
        os.unlink(scene_file)
    lines = [ln for ln in result.stdout.splitlines() if "[thumbs]" in ln or "WARNING" in ln or "Error" in ln]
    if result.returncode != 0 or not raw_path(spec["name"]).exists():
        return f"{spec['name']}: blender failed ({result.returncode})\n" + result.stdout[-3000:] + result.stderr[-3000:]
    return f"{spec['name']}: {time.time() - started:.0f}s " + " | ".join(lines[-3:])


# --------------------------------------------------------------------------
# Paint: sky, colour, captions
# --------------------------------------------------------------------------


def vertical_gradient(size, top, bottom):
    w, h = size
    column = Image.new("RGB", (1, h))
    for y in range(h):
        t = (y / (h - 1)) ** 1.3
        column.putpixel((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return column.resize(size)


def stars(size, seed, count=900):
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    rng = random.Random(seed)
    for _ in range(count):
        x, y = rng.uniform(0, size[0]), rng.uniform(0, size[1] * 0.75)
        r = rng.choice((0.8, 0.8, 1.0, 1.3, 1.8))
        a = int(rng.uniform(90, 255) * (1 - y / size[1]))
        draw.ellipse((x - r, y - r, x + r, y + r), fill=(255, 255, 255, a))
    return layer


def space_sky(size):
    sky = vertical_gradient(size, *SPACE_SKY).convert("RGBA")
    glow = Image.new("RGBA", size, (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse((size[0] * 0.45, size[1] * 0.05, size[0] * 1.15, size[1] * 0.75), fill=(120, 70, 190, 90))
    sky = Image.alpha_composite(sky, glow.filter(ImageFilter.GaussianBlur(160)))
    return Image.alpha_composite(sky, stars(size, "thumbs"))


def day_sky(size):
    sky = vertical_gradient(size, *DAY_SKY).convert("RGBA")
    # A warm glow where the sun sits, top right, so the sky is not a flat card.
    glow = Image.new("RGBA", size, (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse((size[0] * 0.7, -size[1] * 0.4, size[0] * 1.3, size[1] * 0.3), fill=(255, 240, 200, 150))
    return Image.alpha_composite(sky, glow.filter(ImageFilter.GaussianBlur(140)))


def paint_sky(kind, size):
    if kind == "day_to_space":
        # Left to right the sky goes from the Village day to the Orbital night, like the eras do.
        day, space = day_sky(size), space_sky(size)
        mask = Image.linear_gradient("L").rotate(90, expand=True).transpose(Image.FLIP_LEFT_RIGHT).resize(size)
        mask = mask.point(lambda v: max(0, min(255, int((v / 255 - 0.5) * 3.2 * 255 + 128))))
        return Image.composite(space, day, mask)
    if tuple(kind[0]) == SPACE_SKY[0]:
        return space_sky(size)
    return day_sky(size)


def font(px):
    return ImageFont.truetype(str(FONT_PATH), px)


def text(canvas, message, centre, px, fill=(255, 255, 255), outline=(30, 26, 60), accent=None):
    """Chunky outlined caption with a soft drop shadow, centred on `centre`."""
    face = font(px)
    stroke = max(4, px // 9)
    draw = ImageDraw.Draw(canvas)
    box = draw.textbbox((0, 0), message, font=face, stroke_width=stroke)
    x = centre[0] - (box[2] - box[0]) / 2 - box[0]
    y = centre[1] - (box[3] - box[1]) / 2 - box[1]
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).text(
        (x + px * 0.06, y + px * 0.09), message, font=face, fill=(0, 0, 0, 150), stroke_width=stroke, stroke_fill=(0, 0, 0, 150)
    )
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(px * 0.06)))
    draw.text((x, y), message, font=face, fill=fill, stroke_width=stroke, stroke_fill=outline)
    if accent:
        # A lighter top half gives the caption the glossy two-tone read of front-page titles.
        top = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        ImageDraw.Draw(top).text((x, y), message, font=face, fill=accent)
        cut = Image.new("L", canvas.size, 0)
        ImageDraw.Draw(cut).rectangle((0, 0, canvas.size[0], y + box[1] + (box[3] - box[1]) * 0.48), fill=255)
        top.putalpha(ImageChops.multiply(top.getchannel("A"), cut))
        canvas.alpha_composite(top)


def label_width(message, px):
    face = font(px)
    box = ImageDraw.Draw(Image.new("L", (1, 1))).textbbox((0, 0), message, font=face, stroke_width=max(4, px // 9))
    return box[2] - box[0]


def arrow(canvas, a, b, width=70, fill=(255, 205, 40), outline=(30, 26, 60)):
    """A fat right-pointing arrow from a to b (pixels)."""
    ax, ay = a
    bx, by = b
    angle = math.atan2(by - ay, bx - ax)
    length = math.hypot(bx - ax, by - ay)
    head = width * 1.1
    half = width / 2
    shape = [
        (0, -half),
        (length - head, -half),
        (length - head, -width),
        (length, 0),
        (length - head, width),
        (length - head, half),
        (0, half),
    ]
    c, s = math.cos(angle), math.sin(angle)
    points = [(ax + x * c - y * s, ay + x * s + y * c) for x, y in shape]
    draw = ImageDraw.Draw(canvas)
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).polygon([(x + 6, y + 9) for x, y in points], fill=(0, 0, 0, 140))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(6)))
    draw.polygon(points, fill=fill, outline=outline, width=9)


def layer(spec):
    """Sky, render and the colour push, before any text: one finished picture per scene."""
    raw = Image.open(raw_path(spec["name"])).convert("RGBA")
    canvas = paint_sky(spec["post"]["sky"], SIZE)
    canvas.alpha_composite(raw)
    rgb = ImageEnhance.Color(canvas.convert("RGB")).enhance(1.22)
    rgb = ImageEnhance.Contrast(rgb).enhance(1.06)
    return rgb.convert("RGBA")


SLANT = 70  # half the horizontal lean of a slice edge, in pixels


def slices(panels):
    """Four equal columns with leaning edges; each shows the middle of its own panel, where the
    fitted plot sits."""
    w, h = SIZE
    column = w / len(panels)
    canvas = Image.new("RGBA", SIZE, (0, 0, 0, 255))
    edges = []
    for index, panel in enumerate(panels):
        picture = layer(panel)
        centre = column * (index + 0.5)
        shifted = Image.new("RGBA", SIZE, (0, 0, 0, 0))
        shifted.paste(picture, (int(centre - w / 2), 0))
        x0 = index * column
        x1 = x0 + column
        left = (x0 + SLANT, x0 - SLANT) if index else (-SLANT * 2, -SLANT * 2)
        right = (x1 + SLANT, x1 - SLANT) if index < len(panels) - 1 else (w + SLANT * 2, w + SLANT * 2)
        mask = Image.new("L", SIZE, 0)
        ImageDraw.Draw(mask).polygon([(left[0], 0), (right[0], 0), (right[1], h), (left[1], h)], fill=255)
        canvas.paste(shifted, (0, 0), mask)
        if index:
            edges.append(((left[0], 0), (left[1], h)))
    draw = ImageDraw.Draw(canvas)
    for top, bottom in edges:
        draw.line([top, bottom], fill=(30, 26, 60), width=14)
        draw.line([top, bottom], fill=(255, 255, 255), width=7)
    return canvas, [column * (i + 0.5) / w for i in range(len(panels))]


def post(spec):
    name = spec["name"]
    p = spec["post"]
    w, h = SIZE
    if p.get("slices"):
        canvas, columns = slices(spec["panels"])
        anchors = {era_name: [x, 0.0] for era_name, x in zip(ERA_ORDER, columns)}
    else:
        canvas = layer(spec)
        anchors = json.loads(anchors_path(name).read_text()) if anchors_path(name).exists() else {}
    if p.get("arrow"):
        a, b = (anchors[k] for k in p["arrow"])
        arrow(canvas, (a[0] * w, a[1] * h), (b[0] * w, b[1] * h))
    for caption in p.get("captions", []):
        text(canvas, caption, (w / 2, h * 0.12), 128, fill=(255, 214, 60), accent=(255, 240, 150))
    if p.get("era_labels"):
        xs = [anchors[era_name][0] * w for era_name in ERA_ORDER]
        # One size for all four, the largest at which the longest name still fits its column.
        room = min(min(abs(b - a) for a, b in zip(xs, xs[1:])), 2 * min(xs[0], w - xs[-1], xs[-1], w - xs[0]))
        px = 84
        while px > 30 and max(label_width(ERA_TITLES[e], px) for e in ERA_ORDER) > room * 0.92:
            px -= 2
        colours = ((255, 226, 120), (255, 180, 120), (170, 220, 255), (200, 170, 255))
        for era_name, x, colour in zip(ERA_ORDER, xs, colours):
            text(canvas, ERA_TITLES[era_name], (x, h * 0.1), px, fill=colour)
    out = OUT_DIR / f"{name}.png"
    canvas.convert("RGB").save(out, optimize=True)
    if out.stat().st_size > MAX_BYTES:
        # A render's sky gradient and soft shadows compress badly; an adaptive 256-colour palette
        # with dithering keeps the look and fits Roblox's 3 MB limit.
        canvas.convert("RGB").quantize(256, dither=Image.Dither.FLOYDSTEINBERG).save(out, optimize=True)
    return out


def contact_sheet(specs):
    thumb_w, thumb_h, label_h, cols, pad = 640, 360, 44, 3, 16
    rows = math.ceil(len(specs) / cols)
    sheet = Image.new("RGB", (cols * (thumb_w + pad) + pad, rows * (thumb_h + label_h + pad) + pad), (24, 24, 28))
    draw = ImageDraw.Draw(sheet)
    label = font(24)
    for index, spec in enumerate(specs):
        path = OUT_DIR / f"{spec['name']}.png"
        if not path.exists():
            continue
        col, row = index % cols, index // cols
        x = pad + col * (thumb_w + pad)
        y = pad + row * (thumb_h + label_h + pad)
        image = Image.open(path).convert("RGB").resize((thumb_w, thumb_h), Image.LANCZOS)
        sheet.paste(image, (x, y + label_h))
        # The tile overlay band, shown so the safe area can be judged at a glance.
        band = Image.new("RGBA", (thumb_w, int(thumb_h * 0.15)), (0, 0, 0, 90))
        sheet.paste(band, (x, y + label_h + thumb_h - band.size[1]), band)
        draw.text((x, y + 8), f"{spec['hook']}: {spec['name']}", font=label, fill=(235, 235, 240))
    sheet.save(OUT_DIR / "contact_sheet.png", optimize=True)


def main():
    parser = argparse.ArgumentParser(prog="thumbs.py", description=__doc__)
    parser.add_argument("--only", help="comma list of candidate names")
    parser.add_argument("--post-only", action="store_true", help="repaint over the last raw renders")
    parser.add_argument("--blender", default=os.environ.get("BLENDER", plotrender.DEFAULT_BLENDER))
    args = parser.parse_args()

    specs = candidates()
    wanted = specs
    if args.only:
        names = {n.strip() for n in args.only.split(",")}
        wanted = [s for s in specs if s["name"] in names]
        unknown = names - {s["name"] for s in wanted}
        if unknown:
            raise SystemExit(f"unknown candidate(s): {', '.join(sorted(unknown))}")
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    if not args.post_only:
        jobs = [panel for spec in wanted for panel in spec.get("panels", [spec])]
        with ThreadPoolExecutor(WORKERS) as pool:
            for line in pool.map(lambda s: render(s, args.blender), jobs):
                print(line, flush=True)
    for spec in wanted:
        if all(raw_path(panel["name"]).exists() for panel in spec.get("panels", [spec])):
            out = post(spec)
            print(f"   {out.name}: {out.stat().st_size / 1e6:.2f} MB")
    contact_sheet(specs)
    print(f"   {OUT_DIR / 'contact_sheet.png'}")


if __name__ == "__main__":
    main()
