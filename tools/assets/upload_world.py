#!/usr/bin/env python
"""Upload a landscape set's generated meshes and its palette to Roblox via Open Cloud, writing the
ids into src/shared/Config/Assets.json (v4 `world`; INTERFACES "M13 Wave 2 - the Valley meshes").

    py tools/world/valley.py build                                  # GLBs, palette, bake record
    py tools/assets/upload_world.py --dry-run                       # validate and list; writes nothing
    py tools/assets/upload_world.py --only Basin_1 --only Mountains_1   # the trial: just these meshes
    py tools/assets/upload_world.py                                 # everything still pending
    py tools/assets/harvest.py --emit    # then paste tools/assets/harvest.luau in Studio, then
    py tools/assets/harvest.py           # merge: meshId / size / offset, the palette image id

A copy of the baked-paths route (upload_paths.py), not of the props route: the meshes are generated,
not merged from kits, and each carries a hash. Each GLB goes up as a Model (the MeshId, Size and
offset of the MeshPart Roblox builds inside it can only be read in Studio) and the one palette PNG
as a Decal (whose inner Image asset is likewise Studio-only). That is why the harvest step exists.

Idempotent, hash-checked and resumable: an entry whose assetId is non-zero and whose file still has
the recorded sha256 is skipped; a file that changed since its upload goes up again and its
harvested ids are cleared, so Studio can never show stale art under a fresh-looking id. Assets.json
is rewritten after every successful upload, because an id on Roblox but not on disk is lost work.
Meshes that left the bake record are dropped from Assets.json. Open Cloud occasionally answers
"Unknown Error": just run it again.

Unlike upload_paths.py, --dry-run writes NOTHING, and neither does a run that finds a problem in
the baked files. A real run first pre-lists the whole set from the bake record (ids untouched;
triangles, look, a flat mesh's colour and transparency refreshed, so a colour-only change costs no
upload), then uploads. --only names meshes only; the palette goes up with a run that has no --only.

Before anything is sent every file is checked against the bake record: its sha256, the GLB shape
the contract freezes (one primitive, no material), its triangle count and its bounding box. The
last one matters because harvest.py later compares Studio's Size with the record's `size` to 0.01
studs: a record that rounds its sizes would fail there, after the paste, so it fails here instead.
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
import glbtools  # noqa: E402
from upload_audio import UploadError, load_env, require_credentials  # noqa: E402
from upload_models import upload_glb  # noqa: E402
from upload_paths import MAX_DISPLAY_NAME, UPLOAD_SPACING_SECONDS, Job, upload_decal  # noqa: E402

BAKE_DIR = os.path.join(cfg.REPO_ROOT, "assets", "build", "world")
DEFAULT_SET = "Valley"
BUILD_CMD = "py tools/world/valley.py build"
# The generator's naming rule (INTERFACES "M13 Wave 2 - The generator"). The uploader depends on
# it twice: the name is a file name and a template name, and at 24 characters the short display
# prefix always fits Open Cloud's 50.
MESH_NAME = re.compile(r"^[A-Za-z0-9_]{1,24}$")
SET_NAME = re.compile(r"^[A-Za-z0-9_]{1,24}$")
PNG_ALPHA_COLOUR_TYPES = (4, 6)  # greyscale + alpha, RGBA
# Half of harvest.py's tolerance: the record must describe its own GLB tightly enough that the
# harvest check, which compares Studio's size with the record, can only trip on the importer.
RECORD_TOLERANCE_STUDS = 0.005
RECORD_TOLERANCE_SHARE = 0.0005


def log(msg: str) -> None:
    print(f"[world] {msg}", flush=True)


def warn(msg: str) -> None:
    print(f"[world] WARNING: {msg}", flush=True)


def rel(path: str) -> str:
    """A path for a log line; a scratch folder on another drive has no relative form."""
    try:
        return os.path.relpath(path, cfg.REPO_ROOT)
    except ValueError:
        return path


def display_name(set_name: str, name: str) -> str:
    """`EraCityTycoon_World_<Set>_<Mesh>`, or the short prefix when that would pass Open Cloud's
    50 characters (upload_paths.py has the story), so the mesh name a human reads is never cut."""
    tail = f"{set_name}_{name}"
    full = f"EraCityTycoon_World_{tail}"
    if len(full) > MAX_DISPLAY_NAME:
        full = f"ECT_World_{tail}"
    return full[:MAX_DISPLAY_NAME]


def load_bake(set_name: str, bake_root: str) -> dict | None:
    path = os.path.join(bake_root, f"{set_name}.json")
    if not os.path.isfile(path):
        return None
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def record_problems(bake: dict, set_name: str) -> list[str]:
    """What must hold in the bake record before any file is opened."""
    problems = []
    if bake.get("set") != set_name:
        problems.append(f"bake record is for set {bake.get('set')!r}, not {set_name!r}")
    meshes = bake.get("meshes")
    if not isinstance(meshes, dict) or not meshes:
        return problems + ["bake record lists no meshes"]
    for name in sorted(meshes):
        baked = meshes[name] if isinstance(meshes[name], dict) else {}
        if not MESH_NAME.match(name):
            problems.append(f"{name}: mesh names are [A-Za-z0-9_], at most 24 characters")
        look = baked.get("look")
        if look not in cfg.WORLD_LOOKS:
            problems.append(f"{name}: look {look!r} is neither 'palette' nor 'flat'")
        elif look == cfg.WORLD_LOOK_FLAT:
            color = baked.get("color")
            if not (isinstance(color, list) and len(color) == 3 and all(isinstance(v, int) and 0 <= v <= 255 for v in color)):
                problems.append(f"{name}: a flat mesh needs \"color\": [r, g, b] in 0-255, got {color!r}")
            transparency = baked.get("transparency")
            if isinstance(transparency, bool) or not isinstance(transparency, (int, float)) or not 0 <= transparency <= 1:
                problems.append(f"{name}: a flat mesh needs \"transparency\" in 0-1, got {transparency!r}")
    return problems


def palette_problems(data: bytes, expected_size: list | None) -> list[str]:
    """Opaque, any size (the swatch grid grows with the palette). The size is only compared with
    the bake record's own note of it, which catches a PNG left over from another build."""
    if not data.startswith(glbtools.PNG_SIGNATURE) or data[12:16] != b"IHDR":
        return ["not a PNG"]
    width, height, _depth, colour_type = struct.unpack(">IIBB", data[16:26])
    problems = []
    if expected_size and [width, height] != [int(v) for v in expected_size]:
        problems.append(f"is {width}x{height}, the bake record says {expected_size[0]}x{expected_size[1]}")
    if colour_type in PNG_ALPHA_COLOUR_TYPES:
        problems.append("has an alpha channel; the palette must be fully opaque (write it as RGB)")
    elif b"tRNS" in png_chunk_types(data):
        problems.append("has a tRNS transparency chunk; the palette must be fully opaque")
    return problems


def png_chunk_types(data: bytes) -> list[bytes]:
    types = []
    offset = len(glbtools.PNG_SIGNATURE)
    while offset + 8 <= len(data):
        (length,) = struct.unpack(">I", data[offset : offset + 4])
        types.append(data[offset + 4 : offset + 8])
        offset += 12 + length
    return types


def record_slack(extent: float) -> float:
    return max(RECORD_TOLERANCE_STUDS, RECORD_TOLERANCE_SHARE * abs(extent))


def glb_problems(data: bytes, baked: dict) -> list[str]:
    """The GLB shape the contract freezes, checked before an upload is spent on it: anything other
    than one untextured primitive would come back from the importer as several MeshParts (the
    harvest wants exactly one), and a record whose triangles or bounds are not its GLB's would
    fail the harvest size check after Ben's paste instead of here."""
    problems = glbtools.roblox_problems(data)
    if problems:
        return problems
    doc, _binary = glbtools.parse_glb(data)
    meshes = doc.get("meshes") or []
    primitives = [p for m in meshes for p in m.get("primitives") or []]
    if len(meshes) != 1 or len(primitives) != 1:
        return [f"expected one mesh with one primitive, found {len(meshes)} mesh(es) and {len(primitives)} primitive(s)"]
    if doc.get("materials") or doc.get("images") or doc.get("textures"):
        problems.append("carries a material or an image; world meshes have none (the template colours them)")
    primitive = primitives[0]
    attributes = primitive.get("attributes") or {}
    accessors = doc.get("accessors") or []
    if "POSITION" not in attributes or "indices" not in primitive:
        return problems + ["has no POSITION attribute or no indices"]
    if baked.get("look") == cfg.WORLD_LOOK_PALETTE and "TEXCOORD_0" not in attributes:
        problems.append("is a palette mesh without TEXCOORD_0; it could not sample the palette")
    triangles = int(accessors[primitive["indices"]]["count"]) // 3
    if triangles != int(baked.get("triangles", -1)):
        problems.append(f"has {triangles} triangles, the bake record says {baked.get('triangles')}")
    position = accessors[attributes["POSITION"]]
    lo, hi = position.get("min"), position.get("max")
    size, centre = baked.get("size"), baked.get("centre")
    if not (lo and hi) or not (isinstance(size, list) and len(size) == 3) or not (isinstance(centre, list) and len(centre) == 3):
        return problems + ["bounds missing: the POSITION accessor needs min/max and the bake record size and centre"]
    real_size = [hi[i] - lo[i] for i in range(3)]
    real_centre = [(hi[i] + lo[i]) / 2 for i in range(3)]
    slack = [record_slack(real_size[i]) for i in range(3)]
    if not all(abs(float(size[i]) - real_size[i]) <= slack[i] for i in range(3)):
        problems.append(
            f"bake record size {size} is not the GLB's bounding box {[round(v, 4) for v in real_size]}"
            " (the record must not round it: harvest compares Studio's size with it to 0.01 studs)"
        )
    if not all(abs(float(centre[i]) - real_centre[i]) <= slack[i] for i in range(3)):
        problems.append(f"bake record centre {centre} is not the GLB's bounding-box centre {[round(v, 4) for v in real_centre]}")
    return problems


def checked_file(label: str, path: str, recorded_sha: str | None) -> tuple[bytes | None, str, list[str]]:
    """(bytes, sha256, problems) of one baked file; the record's own hash must still describe it,
    or the record and the file come from two different builds."""
    if not os.path.isfile(path):
        return None, "", [f"{label}: missing {rel(path)}; run {BUILD_CMD}"]
    with open(path, "rb") as fh:
        data = fh.read()
    digest = hashlib.sha256(data).hexdigest()
    if recorded_sha and recorded_sha != digest:
        return None, digest, [f"{label}: {os.path.basename(path)} is not the file the bake record hashed; re-run {BUILD_CMD}"]
    return data, digest, []


def palette_job(set_name: str, entry: dict, bake: dict, bake_root: str) -> tuple[list[Job], list[str]]:
    baked = bake.get("palette") or {}
    label = f"{set_name} palette"
    if not baked.get("file"):
        return [], [f"{label}: the bake record names no palette file; re-run {BUILD_CMD}"]
    png = os.path.join(bake_root, baked["file"])
    data, digest, problems = checked_file(label, png, baked.get("sha256"))
    if data is None:
        return [], problems
    bad = palette_problems(data, baked.get("size"))
    if bad:
        return [], [f"{label}: {os.path.basename(png)} {p}" for p in bad]
    asset_id = int(entry.get("paletteAssetId", 0))
    if asset_id != 0:
        if entry.get("paletteSha256") == digest:
            log(f"{label}: already uploaded as {asset_id} (image {entry.get('paletteImageId', 0)}), skipped")
            return [], []
        log(f"{label}: file changed since upload {asset_id}; uploading again")

    def commit(new_id: int) -> None:
        entry["paletteAssetId"] = new_id
        entry["paletteSha256"] = digest
        entry["paletteImageId"] = 0  # a new Decal's image is unknown until harvested

    job = Job(
        label,
        png,
        display_name(set_name, "Palette"),
        f"Era City Tycoon {set_name} landscape palette. Generated (tools/world/valley.py).",
        "decal",
        commit,
    )
    return [job], []


def mesh_jobs(assets: dict, set_name: str, bake: dict, bake_root: str, only: list[str]) -> tuple[list[Job], list[str], int]:
    jobs, problems, skipped = [], [], 0
    for name in sorted(bake["meshes"]):
        baked = bake["meshes"][name]
        mesh = cfg.ensure_world_mesh(
            assets, set_name, name, baked.get("triangles", 0), baked["look"], baked.get("color"), baked.get("transparency")
        )
        if only and name not in only:
            continue
        label = f"{set_name} {name}"
        if not baked.get("file"):
            problems.append(f"{label}: the bake record names no file; re-run {BUILD_CMD}")
            continue
        glb = os.path.join(bake_root, baked["file"])
        data, digest, file_problems = checked_file(label, glb, baked.get("sha256"))
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
                display_name(set_name, name),
                f"Era City Tycoon {set_name} landscape mesh {name}. Generated (tools/world/valley.py).",
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
    parser.add_argument("--set", default=DEFAULT_SET, help=f"the landscape set to upload (default {DEFAULT_SET})")
    parser.add_argument("--only", action="append", default=[], metavar="MESH", help="only this mesh, and not the palette (repeatable)")
    parser.add_argument("--dry-run", action="store_true", help="validate and list; call no API and write nothing")
    parser.add_argument("--assets-json", help="read and write this Assets.json instead of src/shared/Config/Assets.json")
    parser.add_argument("--bake-root", help="bake output root to read instead of assets/build/world")
    args = parser.parse_args(argv)
    cfg.use_assets_path(args.assets_json)
    bake_root = os.path.abspath(args.bake_root) if args.bake_root else BAKE_DIR
    set_name = args.set
    if not SET_NAME.match(set_name):
        warn(f"set name {set_name!r} is not [A-Za-z0-9_], at most 24 characters")
        return 1

    bake = load_bake(set_name, bake_root)
    if bake is None:
        warn(f"no bake record at {rel(os.path.join(bake_root, set_name + '.json'))}; run {BUILD_CMD}")
        return 1
    problems = record_problems(bake, set_name)
    if problems:
        for line in problems:
            warn(line)
        warn(f"nothing uploaded, nothing written; re-run {BUILD_CMD}")
        return 1
    unknown = [name for name in args.only if name not in bake["meshes"]]
    if unknown:
        warn(f"no such mesh(es) in the {set_name} bake: {', '.join(unknown)}")
        return 1

    # Everything below edits `assets` in memory; it reaches the disk only through save_assets,
    # which a dry run and a run with problems never call.
    assets = cfg.load_assets()
    triangles = sum(int(baked.get("triangles", 0)) for baked in bake["meshes"].values())
    entry = cfg.ensure_world_set(assets, set_name, bake.get("plotCount", 0), bake.get("planHash", ""), triangles)
    jobs, problems = ([], []) if args.only else palette_job(set_name, entry, bake, bake_root)
    mesh, mesh_problems, skipped = mesh_jobs(assets, set_name, bake, bake_root, args.only)
    jobs += mesh
    problems += mesh_problems
    # Drop meshes that are no longer baked: their ids would otherwise linger and the server would
    # be handed a template for a piece of landscape the generator no longer makes.
    stale = [name for name in sorted(entry["meshes"]) if name not in bake["meshes"]]
    for line in problems:
        warn(line)
    if problems:
        warn("nothing uploaded, nothing written; fix the files above first")
        return 1
    if skipped:
        log(f"{set_name}: {skipped} mesh(es) already uploaded and unchanged, skipped")

    if args.dry_run:
        for name in stale:
            log(f"would remove {set_name} {name} from Assets.json: no longer baked")
        for job in jobs:
            log(
                f"would upload {job.kind} {job.label} <- {rel(job.path)} "
                f"({os.path.getsize(job.path) / 1024:.0f} KB) as {job.display_name}"
            )
        log(f"dry run: {len(jobs)} upload(s) pending, nothing sent, nothing written")
        return 0

    for name in stale:
        del entry["meshes"][name]
        log(f"{set_name} {name}: no longer baked; removed from Assets.json")
    cfg.save_assets(assets)
    if not jobs:
        log(f"{set_name}: everything asked for is already uploaded ({len(entry['meshes'])} mesh(es) listed)")
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
    log(f"{set_name}: uploaded {len(jobs) - len(failures)}/{len(jobs)}")
    if failures:
        warn(f"{len(failures)} failed (safe to re-run): " + ", ".join(failures[:8]))
        return 1
    log("next: py tools/assets/harvest.py --emit, paste tools/assets/harvest.luau in Studio, then py tools/assets/harvest.py")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
