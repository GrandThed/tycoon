#!/usr/bin/env python
"""Upload the path look test to Roblox via Open Cloud and record the ids in pathtest_assets.json.

    py tools/pathtest/upload.py [--dry-run]

Uploads out/Lane.glb and out/Spur.glb as Model assets and the five texture PNGs (out/tex/) as
Decals, using the pipeline's own helpers (tools/assets/upload_models.upload_glb,
tools/assets/upload_path_texture.upload_decal; credentials from .env via tools/upload_audio.py).

Idempotent: an entry whose assetId is non-zero and whose file still has the uploaded sha256 is
skipped. A file that changed since its upload is uploaded again and its harvested ids are cleared,
so Studio can never show stale art under a fresh-looking id. The JSON is rewritten after every
successful upload. Open Cloud occasionally answers "Unknown Error": just run it again.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(REPO, "tools", "assets"))
sys.path.insert(0, os.path.join(REPO, "tools"))
from upload_audio import UploadError, load_env, require_credentials  # noqa: E402
from upload_models import upload_glb  # noqa: E402
from upload_path_texture import upload_decal  # noqa: E402

ASSETS_JSON = os.path.join(HERE, "pathtest_assets.json")
OUT = os.path.join(HERE, "out")
# Round 1: A/B/C ribbon-UV meshes and textures. Round 2 (C2, C3): planar-UV fill and rim meshes,
# which carry no Y of their own, plus the opaque planar fill and rim textures.
MODELS = ("Lane", "Spur", "Fill_Lane", "Fill_Spur", "Rim_Lane", "Rim_Spur")
IMAGES = ("A_color", "B_color", "B_normal", "B_rough", "C_color", "P_fill", "P_rim")
SPACING_SECONDS = 1.5


def log(msg: str) -> None:
    print(f"[pathtest] {msg}", flush=True)


def load() -> dict:
    data = {"models": {}, "images": {}}
    if os.path.isfile(ASSETS_JSON):
        with open(ASSETS_JSON, encoding="utf-8") as fh:
            data = json.load(fh)
    for name in MODELS:
        data["models"].setdefault(name, {"file": f"tools/pathtest/out/{name}.glb", "sha256": "", "assetId": 0, "meshId": 0, "size": None, "offset": None})
    for name in IMAGES:
        data["images"].setdefault(name, {"file": f"tools/pathtest/out/tex/{name}.png", "sha256": "", "assetId": 0, "imageId": 0})
    return data


def save(data: dict) -> None:
    tmp = ASSETS_JSON + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(data, fh, indent=2)
        fh.write("\n")
    os.replace(tmp, ASSETS_JSON)


def sha256(path: str) -> str:
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dry-run", action="store_true", help="list what would upload; call no API")
    args = parser.parse_args(argv)
    data = load()

    jobs = []
    for group, names in (("models", MODELS), ("images", IMAGES)):
        for name in names:
            entry = data[group][name]
            path = os.path.join(REPO, entry["file"])
            if not os.path.isfile(path):
                log(f"{name}: missing {entry['file']} (run patch.py / textures.py first); skipped")
                continue
            digest = sha256(path)
            if int(entry["assetId"]) != 0:
                if entry["sha256"] == digest:
                    log(f"{name}: already uploaded as {entry['assetId']}, skipped")
                    continue
                log(f"{name}: file changed since upload {entry['assetId']}; uploading again")
            jobs.append((group, name, entry, path, digest))
    save(data)
    if not jobs:
        log("nothing to upload")
        return 0
    if args.dry_run:
        for group, name, _, path, _ in jobs:
            log(f"would upload {group[:-1]} {name} <- {os.path.relpath(path, REPO)} ({os.path.getsize(path) // 1024} KB)")
        return 0

    creds = require_credentials(load_env())
    failures = []
    for index, (group, name, entry, path, digest) in enumerate(jobs, start=1):
        log(f"[{index}/{len(jobs)}] {name}: uploading {os.path.basename(path)} ({os.path.getsize(path) // 1024} KB)")
        try:
            if group == "models":
                asset_id = upload_glb(path, f"EraCityTycoon_PathTest_{name}", "Era City Tycoon path look test mesh (tools/pathtest).", creds)
            else:
                asset_id = upload_decal(path, f"EraCityTycoon_PathTest_{name}", "Era City Tycoon path look test texture (tools/pathtest, procedural).", creds)
        except UploadError as exc:
            log(f"{name}: FAILED: {exc}")
            failures.append(name)
            continue
        entry.update({"assetId": asset_id, "sha256": digest})
        if group == "models":
            entry.update({"meshId": 0, "size": None, "offset": None})
        else:
            entry["imageId"] = 0
        save(data)  # an id on Roblox but not on disk is lost work
        log(f"{name}: OK -> {asset_id}")
        if index < len(jobs):
            time.sleep(SPACING_SECONDS)
    log(f"uploaded {len(jobs) - len(failures)}/{len(jobs)}")
    if failures:
        log("failed (safe to re-run): " + ", ".join(failures))
        return 1
    log("next: py tools/pathtest/harvest_pathtest.py --emit, paste tools/pathtest/harvest_pathtest.luau in Studio")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
