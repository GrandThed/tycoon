#!/usr/bin/env python
"""Upload an era's ribbon path texture to Roblox via Open Cloud and record it in Assets.json
(INTERFACES "Wave 1c — ribbon paths", Texture).

    "/c/Program Files/Blender Foundation/Blender 5.2/5.2/python/bin/python.exe" tools/paths/texture.py --era Village
    py tools/assets/upload_path_texture.py --era Village [--dry-run]
    py tools/assets/harvest.py --emit      # then paste tools/assets/harvest.luau in Studio, then
    py tools/assets/harvest.py             # merge: writes pathTextures.<Era>.imageId

The PNG goes up as a Decal. Open Cloud answers with the Decal's asset id only; the Image asset a
MeshPart's TextureContent needs is created inside that Decal and, like the VIP swatch images, can
only be read in Studio (InsertService:LoadAsset), so the harvest paste resolves `imageId`.

Idempotent: an era whose pathTextures.<Era>.assetId is already non-zero is skipped, and the id is
written the moment the upload succeeds. --dry-run validates the PNG and pre-lists the entry but
calls no API. Credentials, multipart and polling are the shared uploader helpers.
"""

from __future__ import annotations

import argparse
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
import assets_config as cfg  # noqa: E402
from upload_audio import CREATE_URL, UploadError, api_request, build_multipart, load_env, require_credentials  # noqa: E402
from upload_models import poll_operation  # noqa: E402

PATHS_DIR = os.path.join(cfg.REPO_ROOT, "assets", "paths")
GENERATE_CMD = '"/c/Program Files/Blender Foundation/Blender 5.2/5.2/python/bin/python.exe" tools/paths/texture.py --era {era}'
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
# The ribbon's UV layout and the alpha fade are authored for exactly this size (tools/paths/texture.py).
EXPECTED_SIZE = (1024, 512)
RGBA_COLOUR_TYPE = 6


def log(msg: str) -> None:
    print(f"[pathtex] {msg}", flush=True)


def warn(msg: str) -> None:
    print(f"[pathtex] WARNING: {msg}", flush=True)


def png_problems(data: bytes) -> list[str]:
    """Catch a stale or wrong file before it spends an upload: size and alpha are load-bearing."""
    if not data.startswith(PNG_SIGNATURE) or data[12:16] != b"IHDR":
        return ["not a PNG"]
    width, height, _depth, colour_type = struct.unpack(">IIBB", data[16:26])
    problems = []
    if (width, height) != EXPECTED_SIZE:
        problems.append(f"is {width}x{height}, expected {EXPECTED_SIZE[0]}x{EXPECTED_SIZE[1]}")
    if colour_type != RGBA_COLOUR_TYPE:
        problems.append(f"PNG colour type {colour_type} has no alpha channel (expected RGBA)")
    return problems


def upload_decal(path: str, display_name: str, description: str, creds: tuple[str, str, str]) -> int:
    api_key, creator_type, creator_id = creds
    with open(path, "rb") as fh:
        data = fh.read()
    creator = {"userId": creator_id} if creator_type == "user" else {"groupId": creator_id}
    payload = {
        "assetType": "Decal",
        "displayName": display_name,
        "description": description,
        "creationContext": {"creator": creator},
    }
    body, content_type = build_multipart(payload, os.path.basename(path), data)
    created = api_request(CREATE_URL, api_key, body, content_type)
    operation_path = created.get("path") or created.get("operationId")
    if not operation_path:
        raise UploadError(f"no operation path in create response: {created}")
    return poll_operation(str(operation_path), api_key)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--era", required=True)
    parser.add_argument("--dry-run", action="store_true", help="validate and pre-list; call no API")
    parser.add_argument("--png", help="upload this PNG instead of assets/paths/<era>_path.png")
    parser.add_argument("--assets-json", help="read and write this Assets.json instead of src/shared/Config/Assets.json")
    args = parser.parse_args(argv)
    cfg.use_assets_path(args.assets_json)

    png = os.path.abspath(args.png) if args.png else os.path.join(PATHS_DIR, f"{args.era.lower()}_path.png")
    label = f"path texture {args.era}"
    assets = cfg.load_assets()
    entry = cfg.ensure_path_texture(assets, args.era)
    if int(entry["assetId"]) != 0:
        log(f"{label}: already uploaded as {entry['assetId']} (imageId {entry['imageId']}), skipped")
        return 0
    if not os.path.isfile(png):
        warn(f"{label}: missing {os.path.relpath(png, cfg.REPO_ROOT)}; generate it first: {GENERATE_CMD.format(era=args.era)}")
        return 1
    with open(png, "rb") as fh:
        problems = png_problems(fh.read())
    if problems:
        for p in problems:
            warn(f"{label}: {os.path.basename(png)} {p}")
        warn(f"{label}: not uploaded")
        return 1

    cfg.save_assets(assets)
    display_name = f"EraCityTycoon_Path_{args.era}"
    if args.dry_run:
        log(f"would upload {label} <- {os.path.relpath(png, cfg.REPO_ROOT)} ({os.path.getsize(png) / 1024:.0f} KB) as Decal {display_name}")
        log("dry run: nothing sent")
        return 0

    creds = require_credentials(load_env())
    log(f"{label}: uploading {os.path.basename(png)} ({os.path.getsize(png) / 1024:.0f} KB) as a Decal")
    try:
        asset_id = upload_decal(
            png,
            display_name,
            f"Era City Tycoon {args.era} path ribbon texture. Procedurally generated (tools/paths/texture.py).",
            creds,
        )
    except UploadError as exc:
        warn(f"{label}: FAILED: {exc}")
        warn("assetId is still 0, safe to re-run")
        return 1
    entry["assetId"] = asset_id
    entry["imageId"] = 0  # a new Decal's image is unknown until harvested; never keep a stale one
    cfg.save_assets(assets)  # persist immediately: an id on Roblox but not in the config is lost work
    log(f"{label}: OK -> Decal {asset_id} (written to Assets.json)")
    log("next: py tools/assets/harvest.py --emit, paste tools/assets/harvest.luau in Studio, then py tools/assets/harvest.py")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
