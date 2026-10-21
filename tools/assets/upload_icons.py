"""Make and upload a set's shelf icons (one per family) to Roblox via Open Cloud, writing the ids
into src/shared/Config/Assets.json (v5 `icons`; docs/prompts/l3-w2-contract.md L3-42 and the lead's
ruling 3 in its section 11).

    py tools/assets/upload_icons.py --set Weapons --make        # the 256 px icons from the 512 renders
    py tools/assets/upload_icons.py --set Weapons --dry-run     # validate and list; writes nothing
    py tools/assets/upload_icons.py --set Weapons [--model Broadsword]
    py tools/assets/harvest.py --emit --props                   # the icons ride along in either paste

The list of icons is src/shared/Config/WeaponModels.json: its `folder` is the set, and each family's
`model` names one `<Model>_icon.png`. tools/testfit/weaponview.py renders them at 512 x 512 into
assets/testfit/out/<Set>/; --make shrinks each to 256 x 256 (Pillow, LANCZOS, alpha kept) into
assets/testfit/out/<Set>/icons256/, which is what goes up: the shelf draws a card icon at 40 design
px, and fifteen 512 px RGBA images would hold about 15 MB of a phone's memory while it shows.

Each icon goes up as a Decal; its Image asset id is Studio-only, so the harvest records it (kind
"icon"). A file must pass `icon_problems` before it spends an upload: a PNG, 256 x 256, 8 bits per
channel, RGBA, not interlaced, its four corner pixels fully transparent and at least one pixel fully
opaque (a render that lost its transparent background, or came out empty, is caught here). The
check decodes the PNG in plain Python (zlib and the PNG row filters), so it needs no Pillow.

Idempotent and hash-checked like upload_paths.py: an icon whose assetId is non-zero and whose file
still has the recorded sha256 is skipped; a changed file goes up again and its imageId is cleared.
Assets.json is saved after every upload. --dry-run, unlike the older uploaders, writes nothing: not
Assets.json, not an icon. Open Cloud occasionally answers "Unknown Error": just run it again.

No `#!` line on purpose: the py launcher honours one, and `#!/usr/bin/env python` runs the first
python.exe on PATH (on this machine a 3.12 without Pillow) instead of py's default (3.14, with
Pillow), which --make needs. tools/testfit/weaponstrip.py has none for the same reason.
"""

from __future__ import annotations

import argparse
import copy
import json
import os
import struct
import sys
import time
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
import assets_config as cfg  # noqa: E402
from upload_audio import UploadError, load_env, require_credentials  # noqa: E402
from upload_paths import MAX_DISPLAY_NAME, PNG_SIGNATURE, RGBA_COLOUR_TYPE, UPLOAD_SPACING_SECONDS, sha256, upload_decal  # noqa: E402

MODELS_PATH = os.path.join(cfg.REPO_ROOT, "src", "shared", "Config", "WeaponModels.json")
OUT_ROOT = os.path.join(cfg.REPO_ROOT, "assets", "testfit", "out")
ICONS_SUBDIR = "icons256"
ICON_SIZE = (256, 256)
SOURCE_SIZE = (512, 512)
BIT_DEPTH = 8
RENDER_CMD = '"/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b -P tools/testfit/weaponview.py'


def log(msg: str) -> None:
    print(f"[icons] {msg}", flush=True)


def warn(msg: str) -> None:
    print(f"[icons] WARNING: {msg}", flush=True)


def rel(path: str) -> str:
    try:
        return os.path.relpath(path, cfg.REPO_ROOT).replace("\\", "/")
    except ValueError:  # another drive has no relative form
        return path


def display_name(set_name: str, model: str) -> str:
    name = f"EraCityTycoon_Icon_{set_name}_{model}"
    if len(name) > MAX_DISPLAY_NAME:
        name = f"ECT_Icon_{set_name}_{model}"
    return name[:MAX_DISPLAY_NAME]


def description(set_name: str, model: str) -> str:
    return f"Era City Tycoon shelf icon '{model}' ({set_name}). Rendered from the generated weapon kit (tools/testfit/weaponview.py)."


def icon_file(icons_dir: str, model: str) -> str:
    return os.path.join(icons_dir, f"{model}_icon.png")


# ---------------------------------------------------------------- the PNG check


def png_chunks(data: bytes):
    """(type, body) for every chunk, CRC-checked; raises ValueError on a broken file."""
    pos = len(PNG_SIGNATURE)
    while pos + 8 <= len(data):
        length, kind = struct.unpack(">I4s", data[pos : pos + 8])
        body = data[pos + 8 : pos + 8 + length]
        crc = data[pos + 8 + length : pos + 12 + length]
        if len(body) != length or len(crc) != 4:
            raise ValueError("truncated chunk")
        if zlib.crc32(kind + body) & 0xFFFFFFFF != struct.unpack(">I", crc)[0]:
            raise ValueError(f"bad CRC in a {kind.decode('latin-1')} chunk")
        yield kind, body
        if kind == b"IEND":
            return
        pos += 12 + length
    raise ValueError("no IEND chunk")


def paeth(a: int, b: int, c: int) -> int:
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    return b if pb <= pc else c


def unfilter(raw: bytes, width: int, height: int, bpp: int) -> list[bytearray]:
    """The image's rows with the PNG filters undone (PNG spec section 9)."""
    stride = width * bpp
    rows: list[bytearray] = []
    previous = bytearray(stride)
    pos = 0
    for _ in range(height):
        kind = raw[pos]
        line = bytearray(raw[pos + 1 : pos + 1 + stride])
        pos += 1 + stride
        if len(line) != stride:
            raise ValueError("image data is shorter than the header says")
        if kind == 1:
            for i in range(bpp, stride):
                line[i] = (line[i] + line[i - bpp]) & 0xFF
        elif kind == 2:
            for i in range(stride):
                line[i] = (line[i] + previous[i]) & 0xFF
        elif kind == 3:
            for i in range(stride):
                left = line[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + ((left + previous[i]) >> 1)) & 0xFF
        elif kind == 4:
            for i in range(stride):
                left = line[i - bpp] if i >= bpp else 0
                up_left = previous[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + paeth(left, previous[i], up_left)) & 0xFF
        elif kind != 0:
            raise ValueError(f"unknown row filter {kind}")
        rows.append(line)
        previous = line
    return rows


def icon_problems(data: bytes, size: tuple[int, int] = ICON_SIZE) -> list[str]:
    """Why this file must not go up as a shelf icon (never png_problems: that one rejects alpha)."""
    if not data.startswith(PNG_SIGNATURE) or data[12:16] != b"IHDR":
        return ["not a PNG"]
    width, height, depth, colour_type, _compression, _filter, interlace = struct.unpack(">IIBBBBB", data[16:29])
    problems = []
    if (width, height) != size:
        problems.append(f"is {width}x{height}, expected {size[0]}x{size[1]}")
    if depth != BIT_DEPTH:
        problems.append(f"bit depth {depth}, expected {BIT_DEPTH}")
    if colour_type != RGBA_COLOUR_TYPE:
        problems.append(f"PNG colour type {colour_type}, expected {RGBA_COLOUR_TYPE} (RGBA): an icon needs its transparent background")
    if interlace != 0:
        problems.append("is interlaced")
    if problems:
        return problems
    try:
        idat = b"".join(body for kind, body in png_chunks(data) if kind == b"IDAT")
        rows = unfilter(zlib.decompress(idat), width, height, 4)
    except (ValueError, zlib.error) as exc:
        return [f"cannot be decoded: {exc}"]
    corners = [rows[y][x * 4 + 3] for x, y in ((0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1))]
    if any(alpha != 0 for alpha in corners):
        problems.append(f"corner alphas are {corners}, not all 0: the background is not transparent")
    if not any(row[i] == 255 for row in rows for i in range(3, len(row), 4)):
        problems.append("has no fully opaque pixel: the weapon is missing or see-through")
    return problems


# ---------------------------------------------------------------- the list


def load_models(set_name: str, models_path: str) -> list[str]:
    if not os.path.isfile(models_path):
        raise SystemExit(f"[icons] no {rel(models_path)}; run py tools/assets/weapon_frames.py first")
    with open(models_path, "r", encoding="utf-8") as fh:
        doc = json.load(fh)
    if doc.get("folder") != set_name:
        raise SystemExit(f"[icons] {rel(models_path)} lists the set {doc.get('folder')!r}, not {set_name!r}")
    return sorted(entry["model"] for entry in (doc.get("families") or {}).values())


def select(models: list[str], only: list[str]) -> list[str]:
    unknown = sorted(set(only) - set(models))
    if unknown:
        raise SystemExit(f"[icons] no such model(s) in the set: {', '.join(unknown)}")
    return [m for m in models if not only or m in only]


# ---------------------------------------------------------------- --make


def make(models: list[str], source_dir: str, icons_dir: str) -> int:
    """The 256 px set from the 512 renders. Pillow resizes RGBA through premultiplied alpha, so the
    edge of a weapon keeps its colour instead of picking up the transparent background's black."""
    try:
        from PIL import Image
    except ImportError:
        warn("Pillow is not installed for `py` (py -m pip install pillow)")
        return 1
    os.makedirs(icons_dir, exist_ok=True)
    problems = []
    for model in models:
        source = icon_file(source_dir, model)
        if not os.path.isfile(source):
            problems.append(f"{model}: no 512 px render {rel(source)}; render it first: {RENDER_CMD}")
            continue
        with open(source, "rb") as fh:
            bad = icon_problems(fh.read(), SOURCE_SIZE)
        if bad:
            problems += [f"{model}: the render {rel(source)} {p}" for p in bad]
            continue
        with Image.open(source) as image:
            small = image.convert("RGBA").resize(ICON_SIZE, Image.Resampling.LANCZOS)
        target = icon_file(icons_dir, model)
        temp = target + ".tmp.png"
        small.save(temp, format="PNG")
        with open(temp, "rb") as fh:
            bad = icon_problems(fh.read())
        if bad:
            os.remove(temp)
            problems += [f"{model}: the 256 px icon {p}" for p in bad]
            continue
        os.replace(temp, target)
        log(f"{model}: {rel(target)} ({os.path.getsize(target) / 1024:.0f} KB)")
    for line in problems:
        warn(line)
    if problems:
        warn(f"{len(problems)} problem(s); fix them and run --make again")
        return 1
    log(f"made {len(models)} icon(s) at {ICON_SIZE[0]} x {ICON_SIZE[1]} in {rel(icons_dir)}")
    return 0


# ---------------------------------------------------------------- upload


def plan(assets: dict, set_name: str, models: list[str], icons_dir: str, source_dir: str) -> tuple[list[tuple[str, str, str]], list[str]]:
    """(model, path, digest) to upload, and every reason not to upload anything."""
    jobs, problems = [], []
    for model in models:
        path = icon_file(icons_dir, model)
        label = f"icon {set_name}/{model}"
        if not os.path.isfile(path):
            problems.append(f"{label}: missing {rel(path)}; make it first: py tools/assets/upload_icons.py --set {set_name} --make")
            continue
        source = icon_file(source_dir, model)
        if os.path.isfile(source) and os.path.getmtime(source) > os.path.getmtime(path):
            problems.append(f"{label}: {rel(path)} is older than its render {rel(source)}; run --make again")
            continue
        with open(path, "rb") as fh:
            bad = icon_problems(fh.read())
        if bad:
            problems += [f"{label}: {os.path.basename(path)} {p}" for p in bad]
            continue
        digest = sha256(path)
        icon = cfg.ensure_icon(assets, set_name, model)
        asset_id = int(icon.get("assetId", 0))
        if asset_id != 0:
            if icon.get("sha256") == digest:
                log(f"{label}: already uploaded as {asset_id} (image {icon.get('imageId', 0)}), skipped")
                continue
            log(f"{label}: file changed since upload {asset_id}; uploading again")
        jobs.append((model, path, digest))
    return jobs, problems


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--set", required=True, help="the icon set: WeaponModels.json's folder (Weapons)")
    parser.add_argument("--model", action="append", default=[], help="only this model (repeatable)")
    parser.add_argument("--make", action="store_true", help="write the 256 px icons from the 512 px renders, then stop (uploads nothing)")
    parser.add_argument("--dry-run", action="store_true", help="validate and list; call no API and write nothing")
    parser.add_argument("--icons-dir", help="the icons to upload, instead of assets/testfit/out/<set>/icons256")
    parser.add_argument("--source-dir", help="the 512 px renders, instead of assets/testfit/out/<set>")
    parser.add_argument("--assets-json", help="read and write this Assets.json instead of src/shared/Config/Assets.json")
    parser.add_argument("--models-json", default=MODELS_PATH, help="the models config listing the icons")
    args = parser.parse_args(argv)
    cfg.use_assets_path(args.assets_json)
    source_dir = os.path.abspath(args.source_dir) if args.source_dir else os.path.join(OUT_ROOT, args.set)
    icons_dir = os.path.abspath(args.icons_dir) if args.icons_dir else os.path.join(source_dir, ICONS_SUBDIR)
    models = select(load_models(args.set, os.path.abspath(args.models_json)), args.model)

    if args.make:
        return make(models, source_dir, icons_dir)

    saved = cfg.load_assets()
    # A dry run plans on a copy, so not even the pre-listing reaches the file.
    assets = copy.deepcopy(saved) if args.dry_run else saved
    jobs, problems = plan(assets, args.set, models, icons_dir, source_dir)
    for line in problems:
        warn(line)
    if problems:
        warn("nothing uploaded; fix the files above first")
        return 1
    if not jobs:
        log(f"{args.set}: every icon is already uploaded ({len(models)})")
        return 0
    if args.dry_run:
        for model, path, _digest in jobs:
            log(f"would upload decal icon {args.set}/{model} <- {rel(path)} ({os.path.getsize(path) / 1024:.0f} KB) as {display_name(args.set, model)}")
        log(f"dry run: {len(jobs)} valid icon(s), {len(jobs)} upload(s) pending, nothing sent, nothing written")
        return 0

    creds = require_credentials(load_env())
    failures = []
    for index, (model, path, digest) in enumerate(jobs, start=1):
        label = f"icon {args.set}/{model}"
        log(f"[{index}/{len(jobs)}] {label}: uploading {os.path.basename(path)} ({os.path.getsize(path) / 1024:.0f} KB)")
        try:
            asset_id = upload_decal(path, display_name(args.set, model), description(args.set, model), creds)
        except UploadError as exc:
            warn(f"{label}: FAILED: {exc}")
            failures.append(label)
            continue
        icon = cfg.ensure_icon(assets, args.set, model)
        icon.update({"assetId": asset_id, "sha256": digest, "imageId": 0})  # a new Decal's image is unknown until harvested
        cfg.save_assets(assets)  # persist at once: an id on Roblox but not in the config is lost work
        log(f"{label}: OK -> {asset_id}")
        if index < len(jobs):
            time.sleep(UPLOAD_SPACING_SECONDS)
    log(f"{args.set}: uploaded {len(jobs) - len(failures)}/{len(jobs)}")
    if failures:
        warn(f"{len(failures)} failed (safe to re-run): " + ", ".join(failures))
        return 1
    log("next: py tools/assets/harvest.py --emit --props, paste tools/assets/harvest.luau in Studio, then py tools/assets/harvest.py --props --file <saved Output>")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
