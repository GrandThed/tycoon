#!/usr/bin/env python
"""Upload an era's baked path meshes and its two path textures to Roblox via Open Cloud, writing
the ids into src/shared/Config/Assets.json (v3 `paths`; INTERFACES "Wave 1d - baked paths").

    "/c/Program Files/.../python.exe" tools/paths/texture.py --era Village   # the two PNGs
    py tools/paths/bake.py --era Village                                     # the GLBs
    py tools/assets/upload_paths.py --era Village --dry-run
    py tools/assets/upload_paths.py --era Village
    py tools/assets/harvest.py --emit    # then paste tools/assets/harvest.luau in Studio, then
    py tools/assets/harvest.py           # merge: writes meshId / size / offset and the image ids

Each mesh goes up as a Model (Open Cloud returns the Model id; the MeshId, Size and offset of the
MeshPart Roblox builds inside it can only be read in Studio) and each texture as a Decal (whose
inner Image asset is likewise Studio-only). That is why the harvest step exists.

Idempotent, and hash-checked: an entry whose assetId is non-zero and whose file still has the
recorded sha256 is skipped; a file that changed since its upload is uploaded again and its
harvested ids are cleared, so Studio can never show stale art under a fresh-looking id.
Assets.json is rewritten after every successful upload, because an id on Roblox but not on disk is
lost work. Open Cloud occasionally answers "Unknown Error": just run it again.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
import assets_config as cfg  # noqa: E402
from upload_audio import CREATE_URL, UploadError, api_request, build_multipart, load_env, require_credentials  # noqa: E402
from upload_models import poll_operation, upload_glb  # noqa: E402

PATHS_DIR = os.path.join(cfg.REPO_ROOT, "assets", "paths")
BAKE_DIR = os.path.join(cfg.REPO_ROOT, "assets", "build", "paths")
TEXTURE_CMD = '"/c/Program Files/Blender Foundation/Blender 5.2/5.2/python/bin/python.exe" tools/paths/texture.py --era {era}'
BAKE_CMD = "py tools/paths/bake.py --era {era}"
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
# The planar UVs make the texture square and its size part of the look (tools/paths/texture.py).
EXPECTED_SIZE = (1024, 1024)
RGB_COLOUR_TYPE, RGBA_COLOUR_TYPE = 2, 6
UPLOAD_SPACING_SECONDS = 1.5
# Open Cloud answers HTTP 400 INVALID_ARGUMENT "Asset name length is invalid" for a displayName
# longer than this. Boomtown's longest piece (SP_departmentStore) is one character over with the
# full prefix, so a name that would not fit drops to the short prefix instead of losing the piece
# id, which is the part a human reads in the asset library.
MAX_DISPLAY_NAME = 50


def log(msg: str) -> None:
    print(f"[paths] {msg}", flush=True)


def warn(msg: str) -> None:
    print(f"[paths] WARNING: {msg}", flush=True)


def display_name(era: str, layer: str, piece_id: str | None = None) -> str:
    tail = f"{era}_{layer.capitalize()}" + (f"_{piece_id}" if piece_id else "")
    name = f"EraCityTycoon_Path_{tail}"
    if len(name) > MAX_DISPLAY_NAME:
        name = f"ECT_Path_{tail}"
    return name[:MAX_DISPLAY_NAME]


def sha256(path: str) -> str:
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


def png_problems(data: bytes) -> list[str]:
    """Catch a stale or wrong file before it spends an upload: the size is load-bearing and an
    alpha channel would mean the opaque-texture rule was broken somewhere upstream."""
    if not data.startswith(PNG_SIGNATURE) or data[12:16] != b"IHDR":
        return ["not a PNG"]
    width, height, _depth, colour_type = struct.unpack(">IIBB", data[16:26])
    problems = []
    if (width, height) != EXPECTED_SIZE:
        problems.append(f"is {width}x{height}, expected {EXPECTED_SIZE[0]}x{EXPECTED_SIZE[1]}")
    if colour_type == RGBA_COLOUR_TYPE:
        problems.append("has an alpha channel; baked paths must be fully opaque")
    elif colour_type != RGB_COLOUR_TYPE:
        problems.append(f"PNG colour type {colour_type} is neither RGB nor RGBA")
    return problems


def upload_decal(path: str, display_name: str, description: str, creds: tuple[str, str, str]) -> int:
    """A PNG as a Decal asset. Shared with tools/pathtest/upload.py."""
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


class Job:
    def __init__(self, label, path, display_name, description, kind, commit):
        self.label = label
        self.path = path
        self.display_name = display_name
        self.description = description
        self.kind = kind  # "model" or "decal"
        self.commit = commit  # callable(asset_id): record the id and clear harvested fields


def load_bake(era: str, bake_root: str) -> dict | None:
    path = os.path.join(bake_root, f"{era}.json")
    if not os.path.isfile(path):
        return None
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def texture_jobs(era: str, entry: dict, paths_dir: str) -> tuple[list[Job], list[str]]:
    jobs, problems = [], []
    for layer in cfg.PATH_LAYERS:
        png = os.path.join(paths_dir, f"{era}_{layer}.png")
        label = f"{era} {layer} texture"
        if not os.path.isfile(png):
            problems.append(f"{label}: missing {os.path.relpath(png, cfg.REPO_ROOT)}; generate it first: {TEXTURE_CMD.format(era=era)}")
            continue
        with open(png, "rb") as fh:
            bad = png_problems(fh.read())
        if bad:
            problems += [f"{label}: {os.path.basename(png)} {p}" for p in bad]
            continue
        digest = sha256(png)
        asset_id = int(entry.get(f"{layer}AssetId", 0))
        if asset_id != 0:
            if entry.get(f"{layer}Sha256") == digest:
                log(f"{label}: already uploaded as {asset_id} (image {entry.get(f'{layer}ImageId', 0)}), skipped")
                continue
            log(f"{label}: file changed since upload {asset_id}; uploading again")

        def commit(new_id: int, layer: str = layer, digest: str = digest) -> None:
            entry[f"{layer}AssetId"] = new_id
            entry[f"{layer}Sha256"] = digest
            entry[f"{layer}ImageId"] = 0  # a new Decal's image is unknown until harvested

        jobs.append(
            Job(
                label,
                png,
                display_name(era, layer),
                f"Era City Tycoon {era} baked path {layer} texture. Procedurally generated (tools/paths/texture.py).",
                "decal",
                commit,
            )
        )
    return jobs, problems


def mesh_jobs(assets: dict, era: str, bake: dict, only: list[str]) -> tuple[list[Job], list[str]]:
    jobs, problems = [], []
    for piece_id in sorted(bake.get("pieces") or {}):
        if only and piece_id not in only:
            continue
        piece = cfg.ensure_path_piece(assets, era, piece_id)
        for layer in cfg.PATH_LAYERS:
            mesh = piece[layer]
            baked = (bake["pieces"][piece_id].get("meshes") or {}).get(layer.capitalize()) or {}
            rel = baked.get("glb")
            label = f"{era} {piece_id} {layer}"
            if not rel:
                problems.append(f"{label}: no {layer} mesh in the bake record; re-run {BAKE_CMD.format(era=era)}")
                continue
            glb = os.path.join(cfg.REPO_ROOT, rel)
            if not os.path.isfile(glb):
                problems.append(f"{label}: missing {rel}; re-run {BAKE_CMD.format(era=era)}")
                continue
            digest = sha256(glb)
            asset_id = int(mesh.get("assetId", 0))
            if asset_id != 0:
                if mesh.get("sha256") == digest:
                    continue
                log(f"{label}: file changed since upload {asset_id}; uploading again")

            def commit(new_id: int, mesh: dict = mesh, digest: str = digest) -> None:
                mesh.update({"assetId": new_id, "sha256": digest, "meshId": 0, "size": [0, 0, 0], "offset": [0, 0, 0]})

            jobs.append(
                Job(
                    label,
                    glb,
                    display_name(era, layer, piece_id),
                    f"Era City Tycoon {era} baked path piece {piece_id} ({layer}). Generated (tools/paths/bake.py).",
                    "model",
                    commit,
                )
            )
    return jobs, problems


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--era", required=True)
    parser.add_argument("--piece", action="append", default=[], help="only this piece id (repeatable)")
    parser.add_argument("--dry-run", action="store_true", help="validate and pre-list; call no API")
    parser.add_argument("--assets-json", help="read and write this Assets.json instead of src/shared/Config/Assets.json")
    parser.add_argument("--bake-root", help="bake output root to read instead of assets/build/paths")
    parser.add_argument("--paths-dir", help="texture directory to read instead of assets/paths")
    args = parser.parse_args(argv)
    cfg.use_assets_path(args.assets_json)
    bake_root = os.path.abspath(args.bake_root) if args.bake_root else BAKE_DIR
    paths_dir = os.path.abspath(args.paths_dir) if args.paths_dir else PATHS_DIR

    bake = load_bake(args.era, bake_root)
    if bake is None:
        warn(f"no bake record at {os.path.relpath(os.path.join(bake_root, args.era + '.json'), cfg.REPO_ROOT)}; run {BAKE_CMD.format(era=args.era)}")
        return 1
    unknown = [p for p in args.piece if p not in (bake.get("pieces") or {})]
    if unknown:
        warn(f"no such piece(s) in the {args.era} bake: {', '.join(unknown)}")
        return 1

    assets = cfg.load_assets()
    entry = cfg.ensure_path_era(
        assets, args.era, bake["tileStuds"], bake["layoutHash"], (bake.get("totals") or {}).get("triangles", 0)
    )
    jobs, problems = texture_jobs(args.era, entry, paths_dir)
    mesh, mesh_problems = mesh_jobs(assets, args.era, bake, args.piece)
    jobs += mesh
    problems += mesh_problems
    # Drop pieces that are no longer baked: their ids would otherwise linger and the client would
    # be handed a template for a path that does not exist.
    stale = [p for p in list(entry["pieces"]) if p not in (bake.get("pieces") or {})]
    for piece_id in stale:
        del entry["pieces"][piece_id]
        log(f"{args.era} {piece_id}: no longer baked; removed from Assets.json")
    cfg.save_assets(assets)
    for line in problems:
        warn(line)
    if problems:
        warn("nothing uploaded; fix the files above first")
        return 1
    if not jobs:
        log(f"{args.era}: everything is already uploaded ({len(entry['pieces'])} piece(s))")
        return 0

    if args.dry_run:
        for job in jobs:
            log(f"would upload {job.kind} {job.label} <- {os.path.relpath(job.path, cfg.REPO_ROOT)} ({os.path.getsize(job.path) / 1024:.0f} KB)")
        log(f"dry run: {len(jobs)} upload(s) pending, nothing sent")
        return 0

    creds = require_credentials(load_env())
    failures = []
    for index, job in enumerate(jobs, start=1):
        log(f"[{index}/{len(jobs)}] {job.label}: uploading {os.path.basename(job.path)} ({os.path.getsize(job.path) / 1024:.0f} KB)")
        try:
            if job.kind == "model":
                asset_id = upload_glb(job.path, job.display_name, job.description, creds)
            else:
                asset_id = upload_decal(job.path, job.display_name, job.description, creds)
        except UploadError as exc:
            warn(f"{job.label}: FAILED: {exc}")
            failures.append(job.label)
            continue
        job.commit(asset_id)
        cfg.save_assets(assets)
        log(f"{job.label}: OK -> {asset_id}")
        if index < len(jobs):
            time.sleep(UPLOAD_SPACING_SECONDS)
    log(f"{args.era}: uploaded {len(jobs) - len(failures)}/{len(jobs)}")
    if failures:
        warn(f"{len(failures)} failed (safe to re-run): " + ", ".join(failures[:8]))
        return 1
    log("next: py tools/assets/harvest.py --emit, paste tools/assets/harvest.luau in Studio, then py tools/assets/harvest.py")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
