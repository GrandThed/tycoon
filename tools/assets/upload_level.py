#!/usr/bin/env python
"""Upload a dungeon level's baked meshes, its palette and its ground textures to Roblox via Open
Cloud, writing the ids into src/shared/Config/Assets.json (v6 `levels`; the runbook is
docs/prompts/l4-w2-asset-run.md).

    py tools/levels/forest.py build                                    # GLBs, palette, data file, upload record
    py tools/assets/upload_level.py --level ForestRoad --dry-run       # validate and list; writes nothing
    py tools/assets/upload_level.py --level ForestRoad --only Dress_4  # a trial: just this mesh
    py tools/assets/upload_level.py --level ForestRoad                 # everything still pending
    py tools/assets/harvest.py --emit --props   # the level rides along in either harvest mode; paste,
    py tools/assets/harvest.py --props --file <saved Output>           # then merge
    py tools/assets/gen_templates.py --levels                          # templates/_levels/<Level>/

The Valley's world route (upload_world.py) with a map of images instead of one palette: every mesh
wears the level's palette (`palette` look) or one named ground texture (`texture` look, world-planar
UVs that tile). Each GLB goes up as a Model and each PNG as a Decal; the MeshId, Size and offset of
the MeshPart inside a Model, and the Image inside a Decal, can only be read in Studio, which is why
the harvest step exists.

The input is the level's upload record, `assets/build/levels/<Level>.json`, written by the level's
generator beside its bake folder. Before anything is sent every file is checked against it: its
sha256 (a file from another build is refused), the GLB shape the Valley froze (one primitive, no
material, UVs), its triangle count, its bounding box to 0.005 studs (harvest.py later compares
Studio's Size with the record's to 0.01) and, for an image, that it is an opaque PNG of the
recorded size and at most 1024 px a side (Roblox stores no larger). Every mesh's group must have a
draw rule in gen_templates.LEVEL_GROUP_DRAW, every texture a mesh names must be in the record,
every image must be worn by a mesh, and every display name must fit Open Cloud's 50 characters
with the short prefix, or nothing is uploaded at all.

Idempotent, hash-checked and resumable, like upload_world.py: an entry whose assetId is non-zero
and whose file still has the recorded sha256 is skipped; a file that changed since its upload goes
up again and its harvested ids are cleared, so Studio never shows stale art under a fresh-looking
id. Assets.json is rewritten after every successful upload. Meshes and images that left the record
are dropped from Assets.json. --dry-run writes NOTHING, and neither does a run that finds a
problem. --only names meshes only; the images go up with a run that has no --only. Open Cloud
occasionally answers "Unknown Error": just run it again.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
import assets_config as cfg  # noqa: E402
from gen_templates import LEVEL_GROUP_DRAW  # noqa: E402
from upload_audio import UploadError, load_env, require_credentials  # noqa: E402
from upload_models import upload_glb  # noqa: E402
from upload_paths import MAX_DISPLAY_NAME, UPLOAD_SPACING_SECONDS, Job, upload_decal  # noqa: E402
from upload_world import MESH_NAME, glb_problems, palette_problems, rel  # noqa: E402

BAKE_DIR = os.path.join(cfg.REPO_ROOT, "assets", "build", "levels")
DEFAULT_LEVEL = "ForestRoad"
# Each level's generator; the record also names the level's config id, but the command is how a
# human fixes a stale record, so it is spelled out here.
BUILD_CMDS = {"ForestRoad": "py tools/levels/forest.py build"}
TEXTURE_CMDS = {"ForestRoad": '"<Blender 5.2>/5.2/python/bin/python.exe" tools/levels/forest_textures.py'}
LEVEL_NAME = re.compile(r"^[A-Za-z0-9_]{1,24}$")
PLAN_HASH = re.compile(r"^[0-9a-f]{16}$")
MAX_IMAGE_SIDE = 1024


def log(msg: str) -> None:
    print(f"[level] {msg}", flush=True)


def warn(msg: str) -> None:
    print(f"[level] WARNING: {msg}", flush=True)


def build_cmd(level: str) -> str:
    return BUILD_CMDS.get(level, "the level's generator in tools/levels/ (build)")


def display_name(level: str, tail: str) -> str:
    """`EraCityTycoon_Level_<Level>_<tail>`, or the short `ECT_` prefix when that would pass Open
    Cloud's 50 characters. Never cut: record_problems refuses a name that fits neither way."""
    full = f"EraCityTycoon_Level_{level}_{tail}"
    return full if len(full) <= MAX_DISPLAY_NAME else f"ECT_Level_{level}_{tail}"


def image_tail(name: str) -> str:
    return "Palette" if name == cfg.LEVEL_PALETTE_IMAGE else f"Image_{name}"


def load_record(level: str, bake_root: str) -> dict | None:
    path = os.path.join(bake_root, f"{level}.json")
    if not os.path.isfile(path):
        return None
    with open(path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
    return data if isinstance(data, dict) else None


def record_problems(record: dict, level: str) -> list[str]:
    """What must hold in the upload record before any file is opened."""
    problems = []
    if record.get("set") != level:
        problems.append(f"upload record is for level {record.get('set')!r}, not {level!r}")
    if not PLAN_HASH.match(str(record.get("planHash", ""))):
        problems.append(f"planHash {record.get('planHash')!r} is not 16 hex digits")
    images = record.get("images")
    meshes = record.get("meshes")
    if not isinstance(images, dict) or cfg.LEVEL_PALETTE_IMAGE not in images:
        problems.append(f"upload record lists no {cfg.LEVEL_PALETTE_IMAGE!r} image")
        images = images if isinstance(images, dict) else {}
    if not isinstance(meshes, dict) or not meshes:
        return problems + ["upload record lists no meshes"]
    worn = set()
    for name in sorted(meshes):
        baked = meshes[name] if isinstance(meshes[name], dict) else {}
        if not MESH_NAME.match(name):
            problems.append(f"{name}: mesh names are [A-Za-z0-9_], at most 24 characters")
        look = baked.get("look")
        if look not in cfg.LEVEL_LOOKS:
            problems.append(f"{name}: look {look!r} is neither 'palette' nor 'texture'")
            continue
        image = cfg.level_mesh_image(baked)
        if look == cfg.LEVEL_LOOK_TEXTURE and (image == cfg.LEVEL_PALETTE_IMAGE or image not in images):
            problems.append(f"{name}: wears texture {baked.get('texture')!r}, which the record does not list as a ground texture")
        worn.add(image)
        if baked.get("group") not in LEVEL_GROUP_DRAW:
            problems.append(
                f"{name}: group {baked.get('group')!r} has no draw rule; add it to gen_templates.LEVEL_GROUP_DRAW"
                f" ({', '.join(sorted(LEVEL_GROUP_DRAW))}) before uploading"
            )
        if len(display_name(level, name)) > MAX_DISPLAY_NAME:
            problems.append(f"{name}: display name {display_name(level, name)!r} is over {MAX_DISPLAY_NAME} characters")
    for name in sorted(images):
        if not MESH_NAME.match(name):
            problems.append(f"image {name}: image names are [A-Za-z0-9_], at most 24 characters")
        if name not in worn:
            problems.append(f"image {name}: no mesh wears it (an upload for nothing)")
        if len(display_name(level, image_tail(name))) > MAX_DISPLAY_NAME:
            problems.append(f"image {name}: display name {display_name(level, image_tail(name))!r} is over {MAX_DISPLAY_NAME} characters")
    return problems


def checked_file(level: str, label: str, path: str, recorded_sha: str | None) -> tuple[bytes | None, str, list[str]]:
    """(bytes, sha256, problems) of one baked file; the record's own hash must still describe it,
    or the record and the file come from two different builds."""
    if not recorded_sha:
        texture = TEXTURE_CMDS.get(level, "the level's texture tool")
        return None, "", [f"{label}: the upload record lists {os.path.basename(path)} unhashed (it was missing at the build); run {texture}, then {build_cmd(level)}"]
    if not os.path.isfile(path):
        return None, "", [f"{label}: missing {rel(path)}; run {build_cmd(level)}"]
    with open(path, "rb") as fh:
        data = fh.read()
    digest = hashlib.sha256(data).hexdigest()
    if recorded_sha != digest:
        return None, digest, [f"{label}: {os.path.basename(path)} is not the file the upload record hashed; re-run {build_cmd(level)}"]
    return data, digest, []


def image_problems(data: bytes, baked: dict, what: str) -> list[str]:
    problems = palette_problems(data, baked.get("size"), what)
    if not problems:
        width, height = struct.unpack(">II", data[16:24])
        if max(width, height) > MAX_IMAGE_SIDE:
            problems.append(f"is {width}x{height}; Roblox stores images at most {MAX_IMAGE_SIDE} px a side")
    return problems


def image_jobs(assets: dict, level: str, record: dict, bake_root: str) -> tuple[list[Job], list[str], int]:
    jobs, problems, skipped = [], [], 0
    for name in sorted(record["images"]):
        baked = record["images"][name] if isinstance(record["images"][name], dict) else {}
        entry = cfg.ensure_level_image(assets, level, name)
        label = f"{level} image {name}"
        if not baked.get("file"):
            problems.append(f"{label}: the upload record names no file; re-run {build_cmd(level)}")
            continue
        png = os.path.join(bake_root, baked["file"])
        data, digest, file_problems = checked_file(level, label, png, baked.get("sha256"))
        if data is None:
            problems += file_problems
            continue
        what = "palette" if name == cfg.LEVEL_PALETTE_IMAGE else "ground texture"
        bad = image_problems(data, baked, what)
        if bad:
            problems += [f"{label}: {os.path.basename(png)} {p}" for p in bad]
            continue
        asset_id = int(entry.get("assetId", 0))
        if asset_id != 0:
            if entry.get("sha256") == digest:
                skipped += 1
                continue
            log(f"{label}: file changed since upload {asset_id}; uploading again")

        def commit(new_id: int, entry: dict = entry, digest: str = digest) -> None:
            entry.update({"assetId": new_id, "imageId": 0, "sha256": digest})  # a new Decal's image is unknown until harvested

        jobs.append(
            Job(
                label,
                png,
                display_name(level, image_tail(name)),
                f"Era City Tycoon level {level} {what} '{name}'. Generated ({build_cmd(level)}).",
                "decal",
                commit,
            )
        )
    return jobs, problems, skipped


def mesh_jobs(assets: dict, level: str, record: dict, bake_root: str, only: list[str]) -> tuple[list[Job], list[str], int]:
    jobs, problems, skipped = [], [], 0
    for name in sorted(record["meshes"]):
        baked = record["meshes"][name]
        mesh = cfg.ensure_level_mesh(assets, level, name, baked.get("triangles", 0), baked["look"], baked.get("texture"), baked.get("group", ""))
        if only and name not in only:
            continue
        label = f"{level} {name}"
        if not baked.get("file"):
            problems.append(f"{label}: the upload record names no file; re-run {build_cmd(level)}")
            continue
        glb = os.path.join(bake_root, baked["file"])
        data, digest, file_problems = checked_file(level, label, glb, baked.get("sha256"))
        if data is None:
            problems += file_problems
            continue
        bad = glb_problems(data, baked)
        if bad:
            problems += [f"{label}: {os.path.basename(glb)} {p}" for p in bad]
            continue
        asset_id = int(mesh.get("assetId", 0))
        if asset_id != 0:
            if mesh.get("sha256") == digest:
                skipped += 1
                continue
            log(f"{label}: file changed since upload {asset_id}; uploading again")

        def commit(new_id: int, mesh: dict = mesh, digest: str = digest) -> None:
            mesh.update({"assetId": new_id, "sha256": digest, "meshId": 0, "size": [0, 0, 0], "offset": [0, 0, 0]})

        jobs.append(
            Job(
                label,
                glb,
                display_name(level, name),
                f"Era City Tycoon level {level} mesh {name}. Generated ({build_cmd(level)}).",
                "model",
                commit,
            )
        )
    return jobs, problems, skipped


def send(job: Job, creds: tuple[str, str, str]) -> int:
    if job.kind == "model":
        return upload_glb(job.path, job.display_name, job.description, creds)
    return upload_decal(job.path, job.display_name, job.description, creds)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--level", default=DEFAULT_LEVEL, help=f"the level to upload (default {DEFAULT_LEVEL}), its layout name")
    parser.add_argument("--only", action="append", default=[], metavar="MESH", help="only this mesh, and no image (repeatable)")
    parser.add_argument("--dry-run", action="store_true", help="validate and list; call no API and write nothing")
    parser.add_argument("--assets-json", help="read and write this Assets.json instead of src/shared/Config/Assets.json")
    parser.add_argument("--bake-root", help="upload records and bake folders to read instead of assets/build/levels")
    args = parser.parse_args(argv)
    cfg.use_assets_path(args.assets_json)
    bake_root = os.path.abspath(args.bake_root) if args.bake_root else BAKE_DIR
    level = args.level
    if not LEVEL_NAME.match(level):
        warn(f"level name {level!r} is not [A-Za-z0-9_], at most 24 characters")
        return 1

    record = load_record(level, bake_root)
    if record is None:
        warn(f"no upload record at {rel(os.path.join(bake_root, level + '.json'))}; run {build_cmd(level)}")
        return 1
    problems = record_problems(record, level)
    if problems:
        for line in problems:
            warn(line)
        warn(f"nothing uploaded, nothing written; fix the record ({build_cmd(level)})")
        return 1
    unknown = [name for name in args.only if name not in record["meshes"]]
    if unknown:
        warn(f"no such mesh(es) in the {level} upload record: {', '.join(unknown)}")
        return 1

    # Everything below edits `assets` in memory; it reaches the disk only through save_assets,
    # which a dry run and a run with problems never call.
    assets = cfg.load_assets()
    triangles = sum(int(baked.get("triangles", 0)) for baked in record["meshes"].values())
    entry = cfg.ensure_level(assets, level, record["planHash"], triangles)
    jobs, problems, skipped_images = ([], [], 0) if args.only else image_jobs(assets, level, record, bake_root)
    meshes, mesh_problems, skipped_meshes = mesh_jobs(assets, level, record, bake_root, args.only)
    jobs += meshes
    problems += mesh_problems
    # Drop what is no longer baked: a lingering id would hand the client a template for a piece of
    # the level the generator no longer makes, or an image nothing wears.
    stale_meshes = [name for name in sorted(entry["meshes"]) if name not in record["meshes"]]
    stale_images = [name for name in sorted(entry["images"]) if name not in record["images"]]
    for line in problems:
        warn(line)
    if problems:
        warn("nothing uploaded, nothing written; fix the files above first")
        return 1
    if skipped_images or skipped_meshes:
        log(f"{level}: {skipped_images} image(s) and {skipped_meshes} mesh(es) already uploaded and unchanged, skipped")

    if args.dry_run:
        for name in stale_meshes:
            log(f"would remove {level} mesh {name} from Assets.json: no longer baked")
        for name in stale_images:
            log(f"would remove {level} image {name} from Assets.json: no longer in the record")
        for job in jobs:
            log(
                f"would upload {job.kind} {job.label} <- {rel(job.path)} "
                f"({os.path.getsize(job.path) / 1024:.0f} KB) as {job.display_name}"
            )
        images = sum(1 for job in jobs if job.kind == "decal")
        log(f"dry run: {len(jobs)} upload(s) pending ({images} image(s), {len(jobs) - images} mesh(es)), nothing sent, nothing written")
        return 0

    for name in stale_meshes:
        del entry["meshes"][name]
        log(f"{level} mesh {name}: no longer baked; removed from Assets.json")
    for name in stale_images:
        del entry["images"][name]
        log(f"{level} image {name}: no longer in the record; removed from Assets.json")
    cfg.save_assets(assets)
    if not jobs:
        log(f"{level}: everything asked for is already uploaded ({len(entry['images'])} image(s), {len(entry['meshes'])} mesh(es) listed)")
        return 0

    creds = require_credentials(load_env())
    failures = []
    for index, job in enumerate(jobs, start=1):
        log(f"[{index}/{len(jobs)}] {job.label}: uploading {os.path.basename(job.path)} ({os.path.getsize(job.path) / 1024:.0f} KB)")
        try:
            asset_id = send(job, creds)
        except UploadError as exc:
            warn(f"{job.label}: FAILED: {exc}")
            failures.append(job.label)
            continue
        job.commit(asset_id)
        cfg.save_assets(assets)
        log(f"{job.label}: OK -> {asset_id}")
        if index < len(jobs):
            time.sleep(UPLOAD_SPACING_SECONDS)
    log(f"{level}: uploaded {len(jobs) - len(failures)}/{len(jobs)}")
    if failures:
        warn(f"{len(failures)} failed (safe to re-run): " + ", ".join(failures[:8]))
        return 1
    log("next: py tools/assets/harvest.py --emit --props, paste tools/assets/harvest.luau in Studio, then py tools/assets/harvest.py --props --file <saved Output>")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
