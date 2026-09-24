"""Store icons for the game passes and developer products (M10, docs/INTERFACES.md "M10 contracts").

    py tools/marketing/store_icons.py                 # render every candidate + contact sheet
    py tools/marketing/store_icons.py --only VIP_A    # re-render some, then recompose all
    py tools/marketing/store_icons.py --compose-only  # reuse the raw renders

Blender (store_scene.py) renders each subject on a transparent film; Pillow adds the background
badge, a drop shadow, the circle fit and the numeral labels, then builds contact_sheet.png with
every candidate at 512 and circle-cropped at 150 px the way the store shows it.

Family rules shared by all fourteen: one lighting rig, gold subjects, a background hue per item
(green = more cash, indigo = offline/night, purple = VIP, blue = cash products), two badge styles
("burst" = full-square rays, "badge" = gold-ringed disc), one font (Titan One, OFL).
"""

import argparse
import json
import math
import os
import subprocess
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(REPO, "assets", "marketing", "store")
RAW = os.path.join(OUT, "raw")
FONT = os.path.join(REPO, "assets", "marketing", "fonts", "TitanOne-Regular.ttf")
BLENDER = r"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe"
SIZE = 512

# (inner, outer) of the radial gradient per background family.
BACKGROUNDS = {
    "green": ((120, 230, 90), (18, 120, 52)),
    "indigo": ((96, 92, 220), (22, 18, 78)),
    "purple": ((196, 96, 240), (70, 20, 120)),
    "blue": ((90, 200, 255), (18, 70, 170)),
}

# The three cash tiers share one fixed camera so the subject's size on the icon IS the tier;
# auto-fitting each would blow the small pile up to the chest's size.
TIER_CAMERA = {"elev": 24, "azim": 18, "lens": 50, "fixed": {"target": [0, -0.4, 0.5], "dist": 13.5}}


CANDIDATES = [
    # --- Double Cash: "2x" on money. A = coin towers + 3D numeral, B = two big coins side by side.
    {
        "id": "DoubleCash_A", "item": "DoubleCash", "bg": "green", "style": "burst",
        "sells": "Two coin towers and a chunky 3D 2x: every coin you make, twice.",
        "camera": {"elev": 14, "azim": 10, "lens": 55},
        "elements": [
            {"type": "stack", "loc": [-1.3, 0.8, 0], "n": 9, "seed": 1},
            {"type": "stack", "loc": [0.9, 1.2, 0], "n": 12, "seed": 2},
            {"type": "pile", "loc": [0, 0.4, 0], "radius": 2.4, "height": 0.7, "r": 0.55, "seed": 4, "skirt": 8},
            {"type": "label", "text": "2\u00d7", "size": 2.9, "loc": [0.2, -1.8, 1.55], "mat": "white",
             "outline": "greenDark", "outlineWidth": 0.07, "extrude": 0.25},
        ],
    },
    {
        "id": "DoubleCash_B", "item": "DoubleCash", "bg": "green", "style": "badge",
        "sells": "One coin becomes two: a pair of big face-on coins with the x2 badge.",
        "camera": {"elev": 8, "azim": 0, "lens": 60},
        "label": {"text": "\u00d72", "at": "bottomRight"},
        "elements": [
            {"type": "coin", "r": 1.5, "loc": [-0.95, 0.6, 1.8], "rot": [80, 0, 12], "emboss": True, "both": True},
            {"type": "coin", "r": 1.5, "loc": [0.95, -0.2, 1.55], "rot": [78, 0, -14], "emboss": True, "both": True},
            {"type": "star", "loc": [2.2, -0.6, 3.3], "scale": 0.35},
            {"type": "star", "loc": [-2.3, 0.2, 3.1], "scale": 0.25},
        ],
    },
    # --- Offline Pro: earn while away, up to 24 h.
    {
        "id": "OfflinePro_A", "item": "OfflinePro", "bg": "indigo", "style": "burst",
        "sells": "Moon + alarm clock over a coin pile: the clock keeps paying through the night, 24 h.",
        "camera": {"elev": 16, "azim": 10, "lens": 55},
        "label": {"text": "24h", "at": "bottom"},
        "elements": [
            {"type": "moon", "loc": [-1.7, 1.2, 3.6], "rot": [0, 0, -20], "scale": 0.95},
            {"type": "clock", "loc": [0.5, -0.2, 2.0], "rot": [0, 0, 12], "scale": 0.95, "mat": "blue", "time": [10, 10]},
            {"type": "pile", "loc": [0, 0.2, 0], "radius": 2.5, "height": 0.8, "r": 0.5, "seed": 7, "skirt": 10},
            {"type": "star", "loc": [2.2, 0.5, 3.9], "scale": 0.3},
            {"type": "star", "loc": [-2.6, 0.6, 1.8], "scale": 0.2},
        ],
    },
    {
        "id": "OfflinePro_B", "item": "OfflinePro", "bg": "indigo", "style": "badge",
        "sells": "Your city sleeps (dark windows, Zzz, moon) and the coins still pile up at the door.",
        "camera": {"elev": 20, "azim": 25, "lens": 55},
        "label": {"text": "24h", "at": "bottom"},
        "elements": [
            {"type": "house", "loc": [0, 0.8, 0], "rot": [0, 0, 0], "scale": 1.0},
            {"type": "moon", "loc": [-1.9, 1.2, 4.0], "rot": [0, 0, -25], "scale": 0.7},
            {"type": "label", "text": "Zzz", "size": 0.9, "loc": [1.7, 0.4, 3.9], "rot": [90, 0, 12], "mat": "zzz",
             "outline": "ink", "outlineWidth": 0.05, "extrude": 0.2},
            {"type": "pile", "loc": [0.2, -1.4, 0], "radius": 1.6, "height": 0.7, "r": 0.42, "seed": 8, "skirt": 7},
            {"type": "star", "loc": [0.4, 1.0, 4.6], "scale": 0.22},
        ],
    },
    # --- VIP: gold crown, gold plot sign.
    {
        "id": "VIP_A", "item": "VIP", "bg": "purple", "style": "burst",
        "sells": "A jewelled gold crown on a pile of coins: status plus +10 % income.",
        "camera": {"elev": 12, "azim": 10, "lens": 55},
        "label": {"text": "VIP", "at": "bottom"},
        "elements": [
            {"type": "crown", "loc": [0, 0.1, 0.75], "rot": [14, 0, 0], "scale": 1.05},
            {"type": "pile", "loc": [0, 0.1, 0], "radius": 2.4, "height": 0.8, "r": 0.5, "seed": 12, "skirt": 10},
            {"type": "star", "loc": [2.0, -0.4, 3.4], "scale": 0.32},
            {"type": "star", "loc": [-2.1, -0.2, 2.9], "scale": 0.24},
        ],
    },
    {
        "id": "VIP_B", "item": "VIP", "bg": "purple", "style": "badge",
        "sells": "The actual VIP perk: the gold plot sign, crowned.",
        "camera": {"elev": 10, "azim": 12, "lens": 55},
        "elements": [
            {"type": "sign", "loc": [0, 0, 0], "text": "VIP", "board": "window"},
            {"type": "crown", "loc": [0, 0.1, 3.05], "rot": [-10, 0, 0], "scale": 0.55},
            {"type": "pile", "loc": [0, -0.6, 0], "radius": 1.8, "height": 0.45, "r": 0.42, "seed": 13, "skirt": 8},
        ],
    },
    # --- Cash tiers, series A: pile < bag < chest, same camera.
    {
        "id": "Cash30m_A", "item": "Cash30m", "bg": "blue", "style": "burst", "tier": True,
        "sells": "A handful of coins: a quick top-up.",
        "camera": TIER_CAMERA,
        "label": {"text": "30m", "at": "bottom"},
        "elements": [
            {"type": "stack", "loc": [-0.5, 0.5, 0], "n": 4, "r": 0.75, "seed": 21},
            {"type": "pile", "loc": [0.3, -0.2, 0], "radius": 1.4, "height": 0.45, "r": 0.55, "seed": 22, "skirt": 6},
        ],
    },
    {
        "id": "Cash2h_A", "item": "Cash2h", "bg": "blue", "style": "burst", "tier": True,
        "sells": "A fat money bag with coins spilling out.",
        "camera": TIER_CAMERA,
        "label": {"text": "2h", "at": "bottom"},
        "elements": [
            {"type": "bag", "loc": [-0.2, 0.5, 0], "rot": [0, 0, 8], "scale": 0.95},
            {"type": "pile", "loc": [0.4, -0.6, 0], "radius": 1.9, "height": 0.5, "r": 0.55, "seed": 23, "skirt": 8},
        ],
    },
    {
        "id": "Cash8h_A", "item": "Cash8h", "bg": "blue", "style": "burst", "tier": True,
        "sells": "An open treasure chest overflowing onto a heap of coins.",
        "camera": TIER_CAMERA,
        "label": {"text": "8h", "at": "bottom"},
        "elements": [
            {"type": "chest", "loc": [0, 0.6, 0.0], "rot": [0, 0, 10], "scale": 1.12},
            {"type": "pile", "loc": [0, -0.4, 0], "radius": 3.4, "height": 0.6, "r": 0.55, "seed": 24, "skirt": 12},
            {"type": "bag", "loc": [-2.6, 0.3, 0], "rot": [0, 0, 20], "scale": 0.6},
        ],
    },
    # --- Cash tiers, series B: coin towers growing into a city skyline of money.
    {
        "id": "Cash30m_B", "item": "Cash30m", "bg": "blue", "style": "badge", "tier": True,
        "sells": "One short coin tower.",
        "camera": TIER_CAMERA,
        "label": {"text": "30m", "at": "bottom"},
        "elements": [
            {"type": "stack", "loc": [-0.3, 0.3, 0], "n": 6, "r": 0.8, "seed": 31},
            {"type": "stack", "loc": [1.1, 0.0, 0], "n": 3, "r": 0.8, "seed": 35},
            {"type": "coin", "r": 0.8, "loc": [0.2, -1.2, 0.1], "rot": [0, 0, 0], "emboss": True},
        ],
    },
    {
        "id": "Cash2h_B", "item": "Cash2h", "bg": "blue", "style": "badge", "tier": True,
        "sells": "Three coin towers and a bundle of bills.",
        "camera": TIER_CAMERA,
        "label": {"text": "2h", "at": "bottom"},
        "elements": [
            {"type": "stack", "loc": [-1.1, 0.8, 0], "n": 8, "r": 0.8, "seed": 32},
            {"type": "stack", "loc": [0.7, 1.0, 0], "n": 11, "r": 0.8, "seed": 33},
            {"type": "stack", "loc": [1.6, -0.3, 0], "n": 5, "r": 0.8, "seed": 34},
            {"type": "bills", "loc": [-0.4, -0.7, 0], "rot": [0, 0, 18], "n": 4},
        ],
    },
    {
        "id": "Cash8h_B", "item": "Cash8h", "bg": "blue", "style": "badge", "tier": True,
        "sells": "A whole skyline of coin towers, bills and bags: the big one.",
        "camera": TIER_CAMERA,
        "label": {"text": "8h", "at": "bottom"},
        "elements": [
            {"type": "stack", "loc": [-2.2, 1.4, 0], "n": 13, "r": 0.8, "seed": 41},
            {"type": "stack", "loc": [-0.5, 2.0, 0], "n": 19, "r": 0.8, "seed": 42},
            {"type": "stack", "loc": [1.3, 1.6, 0], "n": 16, "r": 0.8, "seed": 43},
            {"type": "stack", "loc": [2.8, 0.6, 0], "n": 10, "r": 0.8, "seed": 44},
            {"type": "stack", "loc": [-3.1, -0.2, 0], "n": 7, "r": 0.8, "seed": 45},
            {"type": "bag", "loc": [0.6, 0.0, 0], "rot": [0, 0, -10], "scale": 0.75},
            {"type": "bills", "loc": [-1.5, -0.9, 0], "rot": [0, 0, 20], "n": 6},
            {"type": "bills", "loc": [2.2, -1.2, 0], "rot": [0, 0, -25], "n": 3},
            {"type": "pile", "loc": [0, -0.6, 0], "radius": 3.6, "height": 0.4, "r": 0.5, "seed": 46, "skirt": 12},
        ],
    },
    # --- Double it (welcome-back card): the night's earnings, doubled.
    {
        "id": "DoubleOffline_A", "item": "DoubleOffline", "bg": "indigo", "style": "burst",
        "sells": "The moon over last night's coins with a big x2: double what you earned away.",
        "camera": {"elev": 20, "azim": 12, "lens": 55},
        "label": {"text": "\u00d72", "at": "bottomRight"},
        "elements": [
            {"type": "moon", "loc": [-1.2, 1.0, 3.0], "rot": [0, 0, -20], "scale": 1.0},
            {"type": "pile", "loc": [0, 0, 0], "radius": 2.5, "height": 1.3, "r": 0.5, "seed": 51, "skirt": 10},
            {"type": "star", "loc": [1.6, 0.8, 3.6], "scale": 0.3},
        ],
    },
    {
        "id": "DoubleOffline_B", "item": "DoubleOffline", "bg": "indigo", "style": "badge",
        "sells": "Night coins with a green up-arrow and a big x2: the one-tap doubler.",
        "camera": {"elev": 12, "azim": 8, "lens": 55},
        "label": {"text": "\u00d72", "at": "bottomRight"},
        "elements": [
            {"type": "moon", "loc": [-2.0, 1.2, 3.3], "rot": [0, 0, -25], "scale": 0.7},
            {"type": "stack", "loc": [-1.0, 0.5, 0], "n": 6, "r": 0.8, "seed": 52},
            {"type": "stack", "loc": [0.9, 0.7, 0], "n": 9, "r": 0.8, "seed": 53},
            {"type": "arrow", "loc": [0.0, 0.1, 2.7], "rot": [90, 0, 0], "scale": 1.0},
        ],
    },
]


def render(only):
    os.makedirs(RAW, exist_ok=True)
    spec_path = os.path.join(RAW, "store_specs.json")
    with open(spec_path, "w", encoding="utf-8") as f:
        json.dump(CANDIDATES, f, indent=1)
    cmd = [BLENDER, "-b", "--factory-startup", "-P", os.path.join(HERE, "store_scene.py"), "--",
           "--spec", spec_path, "--out", RAW]
    if only:
        cmd += ["--only", ",".join(only)]
    proc = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    for line in proc.stdout.splitlines():
        if line.startswith("[store]") or "Error" in line or "Traceback" in line:
            print(line)
    if proc.returncode != 0:
        print(proc.stderr[-4000:])
        sys.exit(f"blender exited {proc.returncode}")


# ---------------------------------------------------------------------------------------------
# Compositing


def radial(size, inner, outer, centre=None, power=1.0):
    cx, cy = centre or (size / 2, size / 2)
    maxd = math.hypot(size / 2, size / 2)
    grad = Image.new("L", (size, size))
    px = grad.load()
    for y in range(size):
        for x in range(size):
            t = min(1.0, math.hypot(x - cx, y - cy) / maxd) ** power
            px[x, y] = int(255 * t)
    return Image.composite(Image.new("RGB", (size, size), outer), Image.new("RGB", (size, size), inner), grad)


def rays(size, count, colour, alpha, centre):
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    cx, cy = centre
    reach = size * 1.5
    for i in range(count):
        a0 = 2 * math.pi * i / count
        a1 = a0 + math.pi / count
        draw.polygon([(cx, cy), (cx + reach * math.cos(a0), cy + reach * math.sin(a0)),
                      (cx + reach * math.cos(a1), cy + reach * math.sin(a1))], fill=(*colour, alpha))
    # Rays fade out towards the rim so the circle crop never cuts a hard wedge edge.
    fade = Image.new("L", (size, size), 0)
    ImageDraw.Draw(fade).ellipse([cx - size * 0.48, cy - size * 0.48, cx + size * 0.48, cy + size * 0.48], fill=255)
    fade = fade.filter(ImageFilter.GaussianBlur(size * 0.12))
    layer.putalpha(ImageChops.multiply(layer.getchannel("A"), fade))
    return layer


def background(family, style):
    inner, outer = BACKGROUNDS[family]
    centre = (SIZE / 2, SIZE * 0.44)
    if style == "burst":
        img = radial(SIZE, inner, outer, centre, power=0.9).convert("RGBA")
        img.alpha_composite(rays(SIZE, 16, (255, 255, 255), 46, centre))
        return img
    # Badge: a dark square with a gold-ringed disc; the ring sits just inside the store's crop
    # circle so the cropped icon keeps a finished gold edge.
    dark = tuple(max(0, int(c * 0.55)) for c in outer)
    scale = 4
    big = SIZE * scale
    img = Image.new("RGBA", (big, big), (*dark, 255))
    ring = Image.new("L", (big, big), 0)
    d = ImageDraw.Draw(ring)
    d.ellipse([6 * scale, 6 * scale, big - 6 * scale, big - 6 * scale], fill=255)
    ring = ring.resize((SIZE, SIZE), Image.LANCZOS)
    gold = radial(SIZE, (255, 236, 140), (214, 138, 20), (SIZE * 0.35, SIZE * 0.25), power=1.3).convert("RGBA")
    base = Image.new("RGBA", (SIZE, SIZE), (*dark, 255))
    base.paste(gold, (0, 0), ring)
    disc_mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(disc_mask).ellipse([22 * scale, 22 * scale, big - 22 * scale, big - 22 * scale], fill=255)
    disc_mask = disc_mask.resize((SIZE, SIZE), Image.LANCZOS)
    disc = radial(SIZE, inner, outer, centre, power=1.1).convert("RGBA")
    disc.alpha_composite(rays(SIZE, 12, (255, 255, 255), 34, centre))
    base.paste(disc, (0, 0), disc_mask)
    # Inner bevel shadow under the ring reads as depth at 150 px.
    edge = ImageChops.subtract(disc_mask, disc_mask.filter(ImageFilter.GaussianBlur(10)))
    shade = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    shade.putalpha(edge.point(lambda v: min(255, v * 2)))
    base.alpha_composite(shade)
    return base


def fit_subject(raw, cand):
    """Scales the render so every opaque pixel lies inside the store's crop circle with margin.
    Tier candidates keep the shared camera's scale, so their relative sizes survive."""
    img = raw.resize((SIZE, SIZE), Image.LANCZOS)
    if cand.get("tier"):
        return img, (0, 0)
    alpha = img.getchannel("A").point(lambda v: 255 if v > 24 else 0)
    box = alpha.getbbox()
    if box is None:
        return img, (0, 0)
    sub = img.crop(box)
    ax = alpha.crop(box)
    cx, cy = sub.width / 2, sub.height / 2
    px = ax.load()
    reach = 1.0
    step = max(1, min(sub.width, sub.height) // 128)
    for y in range(0, sub.height, step):
        for x in range(0, sub.width, step):
            if px[x, y]:
                reach = max(reach, math.hypot(x - cx, y - cy))
    has_label = "label" in cand
    target = 196 if has_label else 212
    k = target / reach
    sub = raw.crop(tuple(v * 2 for v in box)).resize((max(1, int(sub.width * k)), max(1, int(sub.height * k))), Image.LANCZOS)
    centre_y = SIZE / 2 - (18 if has_label else 0)
    return sub, (int(SIZE / 2 - sub.width / 2), int(centre_y - sub.height / 2))


def shadow_of(img, offset, blur, opacity):
    sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
    sh.putalpha(img.getchannel("A").point(lambda v: int(v * opacity)))
    pad = blur * 3
    canvas = Image.new("RGBA", (img.width + pad * 2, img.height + pad * 2), (0, 0, 0, 0))
    canvas.paste(sh, (pad, pad))
    return canvas.filter(ImageFilter.GaussianBlur(blur)), (offset[0] - pad, offset[1] - pad)


def draw_label(icon, spec, family):
    text = spec["text"]
    size = {"bottom": 118, "bottomRight": 150}[spec["at"]]
    font = ImageFont.truetype(FONT, size)
    stroke = max(8, size // 11)
    left, top, right, bottom = font.getbbox(text, stroke_width=stroke)
    w, h = right - left, bottom - top
    if spec["at"] == "bottom":
        x, y = SIZE / 2 - w / 2 - left, SIZE - 58 - h - top
    else:
        x, y = SIZE - 70 - w - left, SIZE - 66 - h - top
    dark = tuple(max(0, int(c * 0.35)) for c in BACKGROUNDS[family][1])

    shadow = Image.new("RGBA", icon.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).text((x, y + 8), text, font=font, fill=(0, 0, 0, 150), stroke_width=stroke, stroke_fill=(0, 0, 0, 150))
    icon.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(4)))
    ImageDraw.Draw(icon).text((x, y), text, font=font, fill=(*dark, 255), stroke_width=stroke, stroke_fill=(*dark, 255))
    # Glossy fill: white top half into warm yellow, clipped to the glyphs.
    mask = Image.new("L", icon.size, 0)
    ImageDraw.Draw(mask).text((x, y), text, font=font, fill=255)
    grad = Image.new("RGBA", icon.size)
    gd = ImageDraw.Draw(grad)
    y0, y1 = int(y + top), int(y + bottom - stroke)
    for row in range(icon.height):
        t = min(1.0, max(0.0, (row - y0) / max(1, y1 - y0)))
        t = 0.0 if t < 0.45 else (t - 0.45) / 0.55
        gd.line([(0, row), (icon.width, row)], fill=(255, int(255 - 45 * t), int(255 - 170 * t), 255))
    icon.paste(grad, (0, 0), mask)


def compose(cand):
    raw = Image.open(os.path.join(RAW, f"store_raw_{cand['id']}.png")).convert("RGBA")
    icon = background(cand["bg"], cand["style"])
    sub, pos = fit_subject(raw, cand)
    sh, sh_pos = shadow_of(sub, (pos[0], pos[1] + 10), 9, 0.55)
    # paste() accepts negative offsets where alpha_composite() does not; the shadow's blur pad
    # usually starts off-canvas.
    layer = Image.new("RGBA", icon.size, (0, 0, 0, 0))
    layer.paste(sh, sh_pos, sh)
    icon.alpha_composite(layer)
    layer = Image.new("RGBA", icon.size, (0, 0, 0, 0))
    layer.paste(sub, pos, sub)
    icon.alpha_composite(layer)
    if "label" in cand:
        draw_label(icon, cand["label"], cand["bg"])
    path = os.path.join(OUT, f"{cand['id']}.png")
    icon.convert("RGB").save(path, optimize=True)
    return path


def circle_crop(img, px, backdrop):
    small = img.resize((px, px), Image.LANCZOS).convert("RGBA")
    mask = Image.new("L", (px * 4, px * 4), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, px * 4 - 1, px * 4 - 1], fill=255)
    tile = Image.new("RGBA", (px, px), (*backdrop, 255))
    tile.paste(small, (0, 0), mask.resize((px, px), Image.LANCZOS))
    return tile


def contact_sheet(paths):
    thumb, circ, pad, caption = 300, 150, 24, 34
    cell_w = thumb + 12 + circ
    cols = 2
    items = []
    for c in CANDIDATES:
        if c["item"] not in items:
            items.append(c["item"])
    sheet_w = pad + cols * (cell_w + pad) + 190
    sheet_h = pad + len(items) * (thumb + caption + pad) + 40
    sheet = Image.new("RGB", (sheet_w, sheet_h), (238, 238, 242))
    d = ImageDraw.Draw(sheet)
    title_font = ImageFont.truetype(FONT, 21)
    cap_font = ImageFont.truetype(FONT, 18)
    d.text((pad, 10), "Store icons: 512 px (left), store circle crop at 150 px on dark and light (right)", font=cap_font, fill=(30, 30, 40))
    for row, item in enumerate(items):
        y = 40 + row * (thumb + caption + pad)
        d.text((pad, y + thumb / 2 - 14), item, font=title_font, fill=(30, 30, 40))
        for col, cand in enumerate([c for c in CANDIDATES if c["item"] == item]):
            x = pad + 190 + col * (cell_w + pad)
            img = Image.open(paths[cand["id"]])
            sheet.paste(img.resize((thumb, thumb), Image.LANCZOS), (x, y))
            sheet.paste(circle_crop(img, circ, (24, 24, 28)), (x + thumb + 12, y))
            sheet.paste(circle_crop(img, circ, (242, 242, 245)), (x + thumb + 12, y + circ))
            d.text((x, y + thumb + 6), f"{cand['id']}.png", font=cap_font, fill=(30, 30, 40))
    out = os.path.join(OUT, "contact_sheet.png")
    sheet.save(out, optimize=True)
    return out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", default="", help="comma-separated candidate ids to re-render")
    parser.add_argument("--compose-only", action="store_true")
    args = parser.parse_args()
    os.makedirs(OUT, exist_ok=True)
    only = [s for s in args.only.split(",") if s]
    if not args.compose_only:
        render(only)
    paths = {}
    for cand in CANDIDATES:
        if os.path.exists(os.path.join(RAW, f"store_raw_{cand['id']}.png")):
            paths[cand["id"]] = compose(cand)
            print(f"composed {cand['id']}")
    if len(paths) == len(CANDIDATES):
        print(contact_sheet(paths))


if __name__ == "__main__":
    main()
