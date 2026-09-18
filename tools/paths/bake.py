#!/usr/bin/env python
"""Bake every path piece of an era into GLBs for upload (INTERFACES "Wave 1d - baked paths").

    py tools/paths/bake.py --era Village                 # all pieces
    py tools/paths/bake.py --era Village --piece SP_mill  # one piece (repeatable)
    py tools/paths/bake.py --era Village --list           # what the pieces are; writes nothing
    py tools/paths/bake.py --era Village --dry-run        # what would be written; writes nothing

Writes assets/build/paths/<Era>/{Fill,Rim}_<pieceId>.glb plus assets/build/paths/<Era>.json with
each piece's bounding box, triangle count, node arcs, drawn centreline and the layout hash. The
geometry is tools/paths/planargeom.py's (the approved C3 recipe) over tools/paths/network.py's
mirror of the client's network, so a piece is a fixed function of the layout, not of ownership.

Boomtown has no `meander` in CityDressing.json, so its authored straight geometry comes through
unchanged; the edge noise, the rim and the caps are the same code as Village's.

Piece ids are derived from the layout alone. If Assets.json already lists this era's pieces under
the same layout hash and the id set has changed, the bake refuses: that would silently orphan
uploaded assets and hand the client ids it cannot resolve.
"""

from __future__ import annotations

import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(REPO_ROOT, "tools", "assets"))
import assets_config as cfg  # noqa: E402
import network as net  # noqa: E402
import planargeom as geom  # noqa: E402

BUILD_DIR = os.path.join(REPO_ROOT, "assets", "build", "paths")
LAYERS = ("Fill", "Rim")


def log(msg: str) -> None:
    print(f"[bake] {msg}", flush=True)


def warn(msg: str) -> None:
    print(f"[bake] WARNING: {msg}", flush=True)


def era_json_path(era: str, build_root: str) -> str:
    return os.path.join(build_root, f"{era}.json")


def glb_rel(era: str, layer: str, piece_id: str) -> str:
    return f"assets/build/paths/{era}/{layer}_{piece_id}.glb"


def check_ids(era: str, layout_hash: str, ids: list[str]) -> list[str]:
    """Compare the piece ids against what Assets.json already carries for this era."""
    assets = cfg.load_assets() if os.path.isfile(cfg.ASSETS_PATH) else cfg.new_assets()
    entry = (assets.get(cfg.PATHS_KEY) or {}).get(era)
    if not entry:
        return []
    known = sorted((entry.get("pieces") or {}).keys())
    if not known:
        return []
    added = [i for i in ids if i not in known]
    removed = [i for i in known if i not in ids]
    if not added and not removed:
        return []
    if entry.get("layoutHash") == layout_hash:
        return [
            f"the layout hash is unchanged ({layout_hash}) but the piece ids moved: "
            f"{len(added)} new {added[:6]}, {len(removed)} gone {removed[:6]}"
        ]
    log(f"layout changed ({entry.get('layoutHash')} -> {layout_hash}): {len(added)} new piece(s), {len(removed)} gone")
    return []


def build(era: str, only: list[str], dry_run: bool, build_root: str) -> tuple[int, dict]:
    bake = net.bake_for(era)
    pieces = bake.pieces()
    ids = [p["id"] for p in pieces]
    problems = check_ids(era, bake.layout_hash(), ids)
    for line in problems:
        warn(line)
    if problems:
        warn("refusing to bake; fix the layout or clear the era's pieces in Assets.json first")
        return 1, {}
    if only:
        unknown = [i for i in only if i not in ids]
        if unknown:
            warn(f"no such piece(s) in {era}: {', '.join(unknown)}")
            return 1, {}

    era_dir = os.path.join(build_root, era)
    record = {
        "era": era,
        "tileStuds": bake.tile_studs,
        "width": bake.era.width,
        "meander": bake.era.meander,
        "layoutHash": bake.layout_hash(),
        "pieces": {},
    }
    # A single-piece re-bake keeps the other pieces' records, but only while the layout has not
    # moved under them; if it has, every piece has to be re-baked anyway.
    existing = era_json_path(era, build_root)
    if only and os.path.isfile(existing):
        with open(existing, "r", encoding="utf-8") as fh:
            previous = json.load(fh)
        if previous.get("layoutHash") == record["layoutHash"]:
            record["pieces"] = previous.get("pieces") or {}

    if not dry_run:
        os.makedirs(era_dir, exist_ok=True)
    triangles = 0
    written = 0
    baked_ids: list[str] = []
    for piece in pieces:
        if only and piece["id"] not in only:
            continue
        entry = {
            "kind": piece["kind"],
            "chain": piece["chain"],
            "nodes": [[round(v, 4) for v in node] for node in piece["nodes"]],
            "nodeArcs": [round(v, 4) for v in piece["nodeArcs"]],
            "distances": [None if d is None else round(d, 3) for d in piece["distances"]],
            "arcRange": [round(piece["window"]["lo"], 4), round(piece["window"]["hi"], 4)],
            "caps": [round(piece["window"]["start_cap"], 4), round(piece["window"]["end_cap"], 4)],
            "centreline": bake.centreline(piece),
            "meshes": {},
        }
        if piece["kind"] == "spur":
            entry["slot"] = piece["slot"]
        else:
            entry["stretch"] = piece["stretch"]
        for layer in LAYERS:
            mesh = geom.ribbon(
                piece["_chain"],
                piece["window"],
                bake.seeds(piece, layer == "Rim"),
                rim=layer == "Rim",
                tile=bake.tile_studs,
            )
            lo, hi = geom.bounds(mesh["verts"])
            rel = glb_rel(era, layer, piece["id"])
            info = {
                "glb": rel,
                "triangles": len(mesh["tris"]),
                "vertices": len(mesh["verts"]),
                "sections": mesh["sections"],
                "centre": [round((a + b) / 2, 4) for a, b in zip(lo, hi)],
                "size": [round(b - a, 4) for a, b in zip(lo, hi)],
            }
            if not dry_run:
                info["bytes"] = geom.write_glb(
                    os.path.join(REPO_ROOT, rel), f"{layer}_{piece['id']}", mesh
                )
                written += 1
            entry["meshes"][layer] = info
            triangles += info["triangles"]
        record["pieces"][piece["id"]] = entry
        baked_ids.append(piece["id"])

    record["totals"] = {
        "pieces": len(record["pieces"]),
        "meshes": 2 * len(record["pieces"]),
        "triangles": sum(m["triangles"] for p in record["pieces"].values() for m in p["meshes"].values()),
        "vertices": sum(m["vertices"] for p in record["pieces"].values() for m in p["meshes"].values()),
    }
    largest = max(
        ((pid, layer, m["triangles"]) for pid, p in record["pieces"].items() for layer, m in p["meshes"].items()),
        key=lambda t: t[2],
        default=("-", "-", 0),
    )
    record["totals"]["largest"] = {"piece": largest[0], "layer": largest[1], "triangles": largest[2]}
    if dry_run:
        log(f"{era}: would write {2 * len(baked_ids)} GLB(s) into {os.path.relpath(era_dir, REPO_ROOT)}")
        log(f"{era}: {len(baked_ids)} piece(s), {triangles} triangle(s) in this run; nothing written")
        return 0, record
    with open(era_json_path(era, build_root), "w", encoding="utf-8", newline="\n") as fh:
        json.dump(record, fh, indent=1, sort_keys=True)
        fh.write("\n")
    log(f"{era}: wrote {written} GLB(s) and {os.path.relpath(era_json_path(era, build_root), REPO_ROOT)}")
    log(
        f"{era}: {record['totals']['pieces']} pieces, {record['totals']['triangles']} triangles total, "
        f"largest {largest[1]}_{largest[0]} at {largest[2]}"
    )
    return 0, record


def listing(era: str) -> int:
    bake = net.bake_for(era)
    pieces = bake.pieces()
    log(f"{era}: layout hash {bake.layout_hash()}, tile {bake.tile_studs:g} studs, width {bake.era.width:g}")
    for piece in pieces:
        a, b = piece["nodeArcs"]
        win = piece["window"]
        log(
            f"  {piece['id']:<16} {piece['kind']:<7} chain {piece['chain']:<12} "
            f"nodes {piece['nodes'][0][0]:7.2f},{piece['nodes'][0][1]:7.2f} -> "
            f"{piece['nodes'][1][0]:7.2f},{piece['nodes'][1][1]:7.2f} "
            f"arc {a:7.2f}-{b:7.2f} baked {win['lo']:7.2f}-{win['hi']:7.2f}"
        )
    log(f"{era}: {len(pieces)} piece(s) = {sum(1 for p in pieces if p['kind'] == 'stretch')} stretch + {sum(1 for p in pieces if p['kind'] == 'spur')} spur")
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--era", required=True)
    parser.add_argument("--piece", action="append", default=[], help="only this piece id (repeatable)")
    parser.add_argument("--dry-run", action="store_true", help="report what would be baked; write nothing")
    parser.add_argument("--list", action="store_true", help="print the piece table and exit")
    parser.add_argument("--build-root", help="write under this root instead of assets/build/paths")
    parser.add_argument("--assets-json", help="check piece ids against this Assets.json instead of the real one")
    args = parser.parse_args(argv)
    cfg.use_assets_path(args.assets_json)
    try:
        if args.list:
            return listing(args.era)
        code, _ = build(args.era, args.piece, args.dry_run, os.path.abspath(args.build_root) if args.build_root else BUILD_DIR)
        return code
    except (ValueError, KeyError) as exc:
        warn(str(exc))
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
