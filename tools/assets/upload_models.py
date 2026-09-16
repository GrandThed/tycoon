#!/usr/bin/env python
"""Upload merged stage GLBs (and one VIP swatch per kit) to Roblox via Open Cloud, writing the
asset ids into src/shared/Config/Assets.json.

    py tools/assets/upload_models.py --era Village [--model Tavern] [--dry-run]
    py tools/assets/upload_models.py --props --era Village [--model TreeGrowing] [--dry-run]

Idempotent: a stage whose modelAssetId is already non-zero, or a kit whose vipSwatchAssetId is
non-zero, is skipped. Assets.json is rewritten after EVERY successful upload so a crash or Ctrl-C
never loses an id. --dry-run does everything (creates/pre-lists Assets.json, builds the swatch
GLBs, validates every file) except the network calls.

--props uploads city-dressing props merged by `merge_stages.py --props` into
Assets.json props.<Era>.<PropName> (stage count from the blueprint; the file becomes v2). Props
reuse their kits' building textures, so no VIP swatch is built for them. --assets-json,
--build-root and --blueprint-root point a dry run at scratch copies and fixtures.

Credentials, multipart encoding and the operation polling are tools/upload_audio.py's, imported
so the two uploaders can never drift on how .env is read.
"""

from __future__ import annotations

import argparse
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(HERE, "..", "testfit"))
import assets_config as cfg  # noqa: E402
import glbtools  # noqa: E402
from blueprint import BLUEPRINTS_ROOT, PROPS_ROOT, BlueprintError, list_blueprints, load_blueprint  # noqa: E402
from upload_audio import CREATE_URL, OPERATION_URL, UploadError, api_request, build_multipart, load_env, require_credentials  # noqa: E402

VIP_DIR = os.path.join(cfg.REPO_ROOT, "assets", "build", "vip")
# Models took ~12 s in the trial; moderation can stretch that, so wait up to three minutes.
POLL_ATTEMPTS = 90
POLL_INTERVAL_SECONDS = 2.0
UPLOAD_SPACING_SECONDS = 1.5


def log(msg: str) -> None:
    print(f"[upload] {msg}", flush=True)


def warn(msg: str) -> None:
    print(f"[upload] WARNING: {msg}", flush=True)


def poll_operation(operation_path: str, api_key: str) -> int:
    operation_id = operation_path.rsplit("/", 1)[-1]
    url = OPERATION_URL.format(operation_id=operation_id)
    for attempt in range(1, POLL_ATTEMPTS + 1):
        result = api_request(url, api_key, None, None)
        if result.get("done"):
            if "error" in result:
                # A completed operation with an error is how Roblox reports a file it could not parse.
                raise UploadError(f"operation finished with error: {result['error']}")
            asset_id = (result.get("response") or {}).get("assetId")
            if asset_id is None:
                raise UploadError(f"operation finished with no assetId: {result}")
            return int(asset_id)
        time.sleep(POLL_INTERVAL_SECONDS)
        if attempt % 5 == 0:
            log(f"  still processing ({attempt * POLL_INTERVAL_SECONDS:.0f}s)...")
    raise UploadError("operation never completed; check create.roblox.com before re-running")


def upload_glb(path: str, display_name: str, description: str, creds: tuple[str, str, str]) -> int:
    api_key, creator_type, creator_id = creds
    with open(path, "rb") as fh:
        data = fh.read()
    creator = {"userId": creator_id} if creator_type == "user" else {"groupId": creator_id}
    payload = {
        "assetType": "Model",
        "displayName": display_name,
        "description": description,
        "creationContext": {"creator": creator},
    }
    body, content_type = build_multipart(payload, os.path.basename(path), data)
    body = body.replace(b"Content-Type: application/octet-stream", b"Content-Type: model/gltf-binary", 1)
    created = api_request(CREATE_URL, api_key, body, content_type)
    operation_path = created.get("path") or created.get("operationId")
    if not operation_path:
        raise UploadError(f"no operation path in create response: {created}")
    return poll_operation(str(operation_path), api_key)


class Job:
    def __init__(self, label: str, path: str, display_name: str, description: str, commit):
        self.label = label
        self.path = path
        self.display_name = display_name
        self.description = description
        self.commit = commit  # callable(asset_id) that records the id in Assets.json


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--era", required=True)
    parser.add_argument("--model", action="append", default=[], help="only this modelName (repeatable)")
    parser.add_argument("--dry-run", action="store_true", help="prepare and validate everything; call no API")
    parser.add_argument("--props", action="store_true", help="upload city-dressing props (blueprints/_props/<Era>/)")
    parser.add_argument("--assets-json", help="read and write this Assets.json instead of src/shared/Config/Assets.json")
    parser.add_argument("--build-root", help="merge output root to read instead of assets/build")
    parser.add_argument("--blueprint-root", help="blueprints tree to read instead of tools/testfit/blueprints[/_props]")
    args = parser.parse_args(argv)
    cfg.use_assets_path(args.assets_json)
    if args.props:
        return upload_props(args)

    era_cfg = cfg.load_era_config(args.era)
    if era_cfg is None:
        warn(f"no era config named {args.era!r} under {cfg.ERAS_DIR}")
        return 1
    slot_types = {s["modelName"]: s.get("type") for s in era_cfg.get("slots", []) if s.get("modelName")}
    assets = cfg.load_assets()
    era_entries = cfg.ensure_era(assets, era_cfg)

    paths = select_blueprints(args, BLUEPRINTS_ROOT)

    jobs: list[Job] = []
    kits: set[str] = set()
    for path in paths:
        try:
            bp = load_blueprint(path)
        except BlueprintError as exc:
            warn(f"{path}: {exc}")
            continue
        model = bp.id
        if model not in slot_types:
            warn(f"{model}: no slot with that modelName in the {args.era} config; skipped")
            continue
        kits.update(bp.kits)
        sidecar = cfg.load_sidecar(args.era, model, build_root=args.build_root)
        if sidecar is None:
            warn(f"{model}: no merge output (run merge_stages.py first); skipped")
            continue
        stages = era_entries[model]["stages"]
        for index, stage in enumerate(stages):
            side_stage = next((s for s in sidecar.get("stages", []) if s.get("stage") == index), None)
            cfg.prefill_parts(stage, side_stage)
            glb = os.path.join(cfg.stages_dir(args.era, build_root=args.build_root), f"{model}_S{index}.glb")
            label = f"{args.era}/{model} S{index}"
            if int(stage.get("modelAssetId", 0)) != 0:
                log(f"{label}: already uploaded as {stage['modelAssetId']}, skipped")
                continue
            if not os.path.isfile(glb):
                warn(f"{label}: missing {os.path.relpath(glb, cfg.REPO_ROOT)}; skipped")
                continue

            def commit(asset_id: int, stage=stage) -> None:
                stage["modelAssetId"] = asset_id

            jobs.append(
                Job(
                    label,
                    glb,
                    f"EraCityTycoon_{args.era}_{model}_S{index}",
                    f"Era City Tycoon growing building '{model}' ({args.era}) stage {index}. Kenney kit pieces, CC0.",
                    commit,
                )
            )

    for kit in sorted(kits):
        tex = cfg.ensure_texture(assets, kit)
        label = f"VIP swatch {kit}"
        if int(tex.get("vipSwatchAssetId", 0)) != 0:
            log(f"{label}: already uploaded as {tex['vipSwatchAssetId']}, skipped")
            continue
        try:
            import vip_palette

            glb = vip_palette.build_swatch(kit, args.era, VIP_DIR)
        except ImportError as exc:
            warn(f"{label}: cannot build ({exc}); is Pillow installed for `py`?")
            continue
        except (OSError, ValueError, glbtools.GlbError) as exc:
            warn(f"{label}: cannot build ({exc})")
            continue

        def commit_tex(asset_id: int, tex=tex) -> None:
            tex["vipSwatchAssetId"] = asset_id

        jobs.append(
            Job(
                label,
                glb,
                f"EraCityTycoon_VIP_{kit.replace('-', '_')}",
                f"Era City Tycoon VIP colourway swatch for the Kenney {kit} ({args.era}). CC0 source.",
                commit_tex,
            )
        )

    cfg.save_assets(assets)
    log(f"Assets.json pre-listed: {len(era_entries)} {args.era} slots, {len(assets['textures'])} kit texture(s)")
    return run_jobs(jobs, assets, args.dry_run)


def select_blueprints(args, default_root: str) -> list[str]:
    root = os.path.abspath(args.blueprint_root) if args.blueprint_root else default_root
    paths = list_blueprints(args.era, root)
    if args.model:
        wanted = set(args.model)
        paths = [p for p in paths if os.path.splitext(os.path.basename(p))[0] in wanted]
        for missing in sorted(wanted - {os.path.splitext(os.path.basename(p))[0] for p in paths}):
            rel = os.path.relpath(os.path.join(root, args.era, f"{missing}.json"), cfg.REPO_ROOT).replace(os.sep, "/")
            warn(f"no blueprint {rel}")
    return paths


def upload_props(args) -> int:
    assets = cfg.load_assets()
    jobs: list[Job] = []
    listed = 0
    for path in select_blueprints(args, PROPS_ROOT):
        try:
            bp = load_blueprint(path)
        except BlueprintError as exc:
            warn(f"{path}: {exc}")
            continue
        prop = bp.id
        entry = cfg.ensure_prop(assets, args.era, prop, bp.stage_count)
        listed += 1
        sidecar = cfg.load_sidecar(args.era, prop, props=True, build_root=args.build_root)
        if sidecar is None:
            warn(f"props/{args.era}/{prop}: no merge output (run merge_stages.py --props first); skipped")
            continue
        for index, stage in enumerate(entry["stages"]):
            side_stage = next((s for s in sidecar.get("stages", []) if s.get("stage") == index), None)
            cfg.prefill_parts(stage, side_stage)
            glb = os.path.join(cfg.stages_dir(args.era, props=True, build_root=args.build_root), f"{prop}_S{index}.glb")
            label = f"props/{args.era}/{prop} S{index}"
            if int(stage.get("modelAssetId", 0)) != 0:
                log(f"{label}: already uploaded as {stage['modelAssetId']}, skipped")
                continue
            if not os.path.isfile(glb):
                warn(f"{label}: missing {os.path.relpath(glb, cfg.REPO_ROOT)}; skipped")
                continue

            def commit(asset_id: int, stage=stage) -> None:
                stage["modelAssetId"] = asset_id

            jobs.append(
                Job(
                    label,
                    glb,
                    f"EraCityTycoon_Prop_{args.era}_{prop}_S{index}",
                    f"Era City Tycoon city prop '{prop}' ({args.era}) stage {index}. Kenney kit pieces, CC0.",
                    commit,
                )
            )
    if listed:
        cfg.save_assets(assets)
    log(f"Assets.json pre-listed: {listed} {args.era} prop(s)")
    return run_jobs(jobs, assets, args.dry_run, props=True)


def run_jobs(jobs: list[Job], assets: dict, dry_run: bool, props: bool = False) -> int:
    valid: list[Job] = []
    for job in jobs:
        with open(job.path, "rb") as fh:
            problems = glbtools.roblox_problems(fh.read())
        if problems:
            for p in problems:
                warn(f"{job.label}: {p}")
            warn(f"{job.label}: not uploaded (invalid for Roblox)")
            continue
        valid.append(job)

    if not valid:
        log("nothing to upload")
        return 0
    if dry_run:
        for job in valid:
            log(f"would upload {job.label:<32} <- {os.path.relpath(job.path, cfg.REPO_ROOT)} as {job.display_name}")
        log(f"dry run: {len(valid)} upload(s) prepared, nothing sent")
        return 0

    creds = require_credentials(load_env())
    failures: list[str] = []
    for index, job in enumerate(valid, start=1):
        log(f"[{index}/{len(valid)}] {job.label}: uploading {os.path.basename(job.path)} ({os.path.getsize(job.path) / 1024:.0f} KB)")
        try:
            asset_id = upload_glb(job.path, job.display_name, job.description, creds)
        except UploadError as exc:
            warn(f"{job.label}: FAILED: {exc}")
            failures.append(job.label)
            continue
        job.commit(asset_id)
        cfg.save_assets(assets)  # persist immediately: an id on Roblox but not in the config is lost work
        log(f"{job.label}: OK -> {asset_id} (written to Assets.json)")
        if index < len(valid):
            time.sleep(UPLOAD_SPACING_SECONDS)
    log(f"uploaded {len(valid) - len(failures)}/{len(valid)}")
    if failures:
        warn("failed (still 0, safe to re-run): " + ", ".join(failures))
        return 1
    log(f"next: py tools/assets/harvest.py --emit{' --props' if props else ''}, then paste tools/assets/harvest.luau into Studio")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
