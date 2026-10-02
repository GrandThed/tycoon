"""RoadGraph's own view of the baked pieces, recomputed from tools/paths/network.py.

Why a second derivation instead of a getter on `Bake`: bake.py records the arcs it *meant* to cut
each mesh at, and the client separately asks PathRibbon for the arcs of the piece it is about to
clone. Wave 1d's first shipped bug lived exactly in that gap -- `RoadGraph.chainArc` mapped a
polyline's own end points straight to the chain's full span instead of projecting them, so Village
`L3_1` began 1.86 studs from where its mesh was baked, which moved a lane and a dust track, and
nothing anywhere failed.

So this module walks the client's steps, from network.py's functions only and **without** that end
point special case:

* connector / lane split       `stretch.group > segmentGroups`, not network.py's `segment is None`
* connector chain key          `CONNECTOR_KEY_BASE + <1-based stretch id>` (96 + i + 1 == 97 + i)
* piece id                     a running per-polyline ordinal over the stretch list, the way
                               RoadGraph numbers `stretch.pieceId`, not a rank recomputed per piece
* arcs                         a connector reads `PathRibbon.FullSpan`; a lane stretch projects
                               each of its two nodes with `PathRibbon.ArcAt`; a spur reads
                               `FullSpan`
* which pieces exist           `RoadGraph.pathPieceIds` at full ownership: a stretch must be both
                               revealed (on some owned spur's shortest path) and inside
                               `budget.pathPieces`, and a spur must be inside both budgets
* back lanes (wave 2.5)        `RoadGraph.SetLanes`: lane k is piece `LN_<k>` when the fabric
                               wants it shown (some lot on it has a building site) and k is
                               within what `budget.pathPieces` has left after every stretch and
                               spur. The client reads no arc for a lane -- it clones the template
                               where the bake put it -- so a lane is checked against the fabric
                               data instead: its polyline, its width, its mouth's address. That
                               side comes from tools/cityfabric.py (the mirror of Fabric.luau),
                               never from network.py's own lane chains

`verify()` compares all of that against the piece table bake.py is about to emit; `stale()`
compares that table against the `<Era>.json` the meshes on disk were actually baked from. They are
two different findings: the first is a mirror that has drifted from the client, the second a
layout or a width that changed after the last bake and only needs a re-bake.

What this cannot do: it does not read RoadGraph.luau. It proves the Python side is self-consistent
and that the meshes on disk match today's mirror; it cannot prove the Luau still mirrors network.py.
Keep the two in step by hand, and diff `--list` when either moves.
"""

from __future__ import annotations

import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(REPO_ROOT, "tools"))
sys.path.insert(0, os.path.join(REPO_ROOT, "tools", "pathmock"))
sys.path.insert(0, HERE)
import pathgeom  # noqa: E402
import cityfabric  # noqa: E402
import streetplan  # noqa: E402

# RoadGraph.luau's own value. Luau stretch ids are 1-based and network.py's are 0-based, so this
# is one less than network.CONNECTOR_KEY_BASE and the two keys agree.
CONNECTOR_KEY_BASE = 96
SPUR_PIECE_PREFIX = "SP_"
LANE_PIECE_FORMAT = "LN_{}"  # RoadGraph.LANE_PIECE_FORMAT
# A lane's data points are written to 2 decimals and its baked polyline is the same points, so a
# real difference is never this small; the mouth alone may move, by the join snap.
LANE_POINT_EPS = 0.05
# Two derivations of the same float64 expression, so a real difference is never this small. Well
# under a texel of the 11-stud path tile either way.
ARC_EPS = 1e-3
# <Era>.json rounds arcs to 4 decimals.
RECORD_EPS = 1e-3
HOST_REACH = 0.1  # network.HOST_REACH_EXTRA: how far past half a road width a join still lands


def pg_curve(points):
    """A plain polyline as a curve, for distance tests."""
    return pathgeom.Curve([tuple(p) for p in points])


def _full_span(chain) -> tuple[float, float]:
    """PathRibbon.FullSpan: the drawn curve minus the join/round extensions at each end."""
    ext_s, ext_e = chain["ext"]
    return ext_s, chain["final"].total - ext_e


def segment_groups(bake) -> int:
    """RoadGraph's `segmentGroups`: one group per polyline segment, created before any connector
    group, so a stretch in a later group is a connector."""
    return sum(max(len(street) - 1, 0) for street in bake.era.streets)


def stretch_pieces(bake) -> dict[int, dict]:
    """stretch id -> {id, chain index, arcs}, derived the way RoadGraph derives them."""
    boundary = segment_groups(bake)
    ordinals: dict[int, int] = {}
    out: dict[int, dict] = {}
    for index, stretch in enumerate(bake.network.stretches):
        polyline = stretch["polyline"]
        ordinal = ordinals.get(polyline, 0) + 1
        ordinals[polyline] = ordinal
        connector = stretch["group"] >= boundary
        chain_index = (
            bake.connector_chains.get(CONNECTOR_KEY_BASE + index + 1)
            if connector
            else bake.polyline_chains.get(polyline)
        )
        if chain_index is None:
            continue  # the client skips a stretch whose chain PathRibbon did not build
        chain = bake.chains[chain_index]
        arcs = _full_span(chain) if connector else (bake.arc_at(chain, stretch["a"]), bake.arc_at(chain, stretch["b"]))
        out[index] = {
            "id": f"L{polyline + 1}_{ordinal}",
            "chain": chain["id"],
            "connector": connector,
            "arcs": arcs,
        }
    return out


def spur_pieces(bake) -> dict[str, dict]:
    """slot id -> {id, chain, arcs}. A spur's piece spans its whole chain; there are no interior
    nodes to project."""
    out: dict[str, dict] = {}
    for slot_id in bake.network.spur_ids:
        chain_index = bake.spur_chains.get(slot_id)
        if chain_index is None:
            continue  # a one-leg route PathRibbon refused; the client asks for no piece
        chain = bake.chains[chain_index]
        out[slot_id] = {"id": SPUR_PIECE_PREFIX + slot_id, "chain": chain["id"], "arcs": _full_span(chain)}
    return out


def lane_pieces(bake) -> dict[int, dict]:
    """lane index -> {id, lane, points, width}: the lanes the fabric hands RoadGraph.SetLanes on a
    finished plot -- every lane that can be laid and has a lot with at least a building site --
    with the polyline (mouth first) and width it hands over."""
    plot = cityfabric.FabricPlot.load(bake.era_name, city=bake.era.city, era=bake.era, network=bake.network)
    if plot is None:
        return {}
    everything = {slot["id"] for slot in plot.era.config["slots"] if slot["id"] in plot.layout["slots"]}
    tiers = len(bake.era.city["tier"]["thresholds"])
    reaches = plot.snapshot(everything, plot.final_stages(everything), tiers)["laneReaches"]
    return {
        view["index"]: {
            "id": LANE_PIECE_FORMAT.format(view["index"]),
            "lane": view["lane"],
            "points": [(p[0], p[1]) for p in view["lane"]["points"]],
            "width": plot.lane_config["width"],
        }
        for view in plot.lane_views
        if reaches[view["index"]] > 0
    }


def requested(bake) -> dict[str, dict]:
    """Every piece id `RoadGraph.pathPieceIds` can ever return for this era, with its arc pair
    (a lane piece carries its fabric data instead; see `lane_pieces`).

    That is the reveal rule and both budgets together: a stretch is drawn only if some owned
    building's shortest path from the entrance runs over it, its spine group survived
    `budget.roadPieces`, and it fell inside `budget.pathPieces`; a spur needs both budgets too, and
    spurs are allocated after every stretch.
    """
    network = bake.network
    groups_allowed, spurs_allowed = network.straight_allocate()
    budget = bake.era.city.get("budget", {})
    remaining = streetplan.budget_value(
        budget.get("pathPieces"), streetplan.budget_value(budget.get("roadPieces"), 0)
    )

    # RoadGraph.pathStretchOrder: the budget is spent over the union of the shortest paths only
    # (the set the bake emits), not over every allowed stretch.
    union: set[int] = set()
    for slot_id in network.spur_ids:
        ids = network.path_stretches(network.junction_nodes.get(slot_id))
        if ids:
            union.update(ids)
    order = []
    for stretch_id in sorted(union):
        distance = network.near_distance(stretch_id)
        if distance is not None and network.stretches[stretch_id]["group"] in groups_allowed:
            order.append((distance, stretch_id))
    order.sort()
    stretch_allowed = set()
    for _, stretch_id in order:
        if remaining <= 0:
            break
        stretch_allowed.add(stretch_id)
        remaining -= 1
    spur_allowed = []
    for slot_id in spurs_allowed:
        if remaining > 0:
            spur_allowed.append(slot_id)
            remaining -= 1

    visible = set()
    for slot_id in spurs_allowed:
        ids = network.path_stretches(network.junction_nodes.get(slot_id))
        if ids:
            visible.update(ids)

    out: dict[str, dict] = {}
    for stretch_id, piece in stretch_pieces(bake).items():
        if stretch_id in visible and stretch_id in stretch_allowed:
            out[piece["id"]] = piece
    for slot_id in spur_allowed:
        piece = spur_pieces(bake).get(slot_id)
        if piece is not None:
            out[piece["id"]] = piece
    # RoadGraph.SetLanes: lane k is cloned while k is within what the budget has left.
    for index, piece in sorted(lane_pieces(bake).items()):
        if index <= remaining:
            out[piece["id"]] = piece
    return out


def lane_problems(bake, piece_id: str, want: dict, got: dict) -> list[str]:
    """One baked lane piece against the fabric data it stands for: the polyline, the width, the
    join onto a street and the mouth's address on that street."""
    problems: list[str] = []
    chain = got["_chain"]
    lane, points = want["lane"], want["points"]
    if chain["width"] != want["width"]:
        problems.append(f"{piece_id}: baked {chain['width']:g} wide, fabric.lanes.width is {want['width']:g}")
    # The baked control polyline, far point first; the data's points must all lie on it and its
    # ends must be the data's ends.
    control = pg_curve(chain["points"])
    worst = max(control.project(p)[0] for p in points[1:])
    far = math.dist(chain["points"][0], points[-1])
    if worst > LANE_POINT_EPS or far > LANE_POINT_EPS:
        problems.append(
            f"{piece_id}: the baked polyline leaves the fabric data's by {max(worst, far):.2f} studs "
            f"(data {[list(p) for p in points]})"
        )
    reach = bake.era.width / 2 + HOST_REACH
    if not chain["join_end"]:
        problems.append(f"{piece_id}: its mouth {list(points[0])} is on no street, so nothing covers it")
    elif math.dist(chain["points"][-1], points[0]) > reach:
        problems.append(f"{piece_id}: the mouth was snapped {math.dist(chain['points'][-1], points[0]):.2f} studs from the data's")
    # The mouth's address: `along` studs from the `a` end of the stretch it names.
    ids = {bake.piece_id(index): index for index in range(len(bake.network.stretches))}
    stretch_index = ids.get(lane["stretch"])
    if stretch_index is None:
        problems.append(f"{piece_id}: its mouth is on stretch {lane['stretch']!r}, which the network does not have")
    else:
        stretch = bake.network.stretches[stretch_index]
        t = lane["along"] / stretch["length"] if stretch["length"] > 0 else 0.0
        at = (stretch["a"][0] + (stretch["b"][0] - stretch["a"][0]) * t, stretch["a"][1] + (stretch["b"][1] - stretch["a"][1]) * t)
        if math.dist(at, points[0]) > reach:
            problems.append(
                f"{piece_id}: {lane['stretch']} at {lane['along']:g} is ({at[0]:.2f}, {at[1]:.2f}), "
                f"{math.dist(at, points[0]):.2f} studs from the lane's mouth {list(points[0])}"
            )
    return problems


def _record_path(era: str) -> str:
    return os.path.join(REPO_ROOT, "assets", "build", "paths", f"{era}.json")


def load_record(era: str) -> dict | None:
    """The `<Era>.json` the GLBs on disk (and the uploaded models) were baked from, or None."""
    path = _record_path(era)
    if not os.path.isfile(path):
        return None
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def verify(bake, pieces: list[dict]) -> list[str]:
    """Compare the client's derivation with what the bake emits.

    Returns one line per disagreement; empty means the two agree on the piece set, the piece
    count and every piece's arc pair and chain.
    """
    problems: list[str] = []
    baked = {p["id"]: p for p in pieces}
    client = requested(bake)

    missing = sorted(set(client) - set(baked))
    extra = sorted(set(baked) - set(client))
    if missing:
        problems.append(
            f"{len(missing)} piece(s) the client would clone are not baked: {missing[:8]}"
        )
    if extra:
        problems.append(
            f"{len(extra)} baked piece(s) the client never asks for (budget or reveal drops them): {extra[:8]}"
        )
    if len(client) != len(baked):
        problems.append(f"piece count: client {len(client)}, bake {len(baked)}")

    for piece_id in sorted(set(client) & set(baked)):
        if baked[piece_id]["kind"] == "lane" or "lane" in client[piece_id]:
            if baked[piece_id]["kind"] != "lane" or "lane" not in client[piece_id]:
                problems.append(f"{piece_id}: a lane on one side and a street piece on the other")
            else:
                problems += lane_problems(bake, piece_id, client[piece_id], baked[piece_id])
            continue
        want = client[piece_id]["arcs"]
        got = baked[piece_id]["nodeArcs"]
        if max(abs(want[0] - got[0]), abs(want[1] - got[1])) > ARC_EPS:
            problems.append(
                f"{piece_id}: the client reads arcs {want[0]:.3f}-{want[1]:.3f} but the mesh is cut "
                f"at {got[0]:.3f}-{got[1]:.3f} (off by {max(abs(want[0] - got[0]), abs(want[1] - got[1])):.3f} studs)"
            )
        if client[piece_id]["chain"] != baked[piece_id]["chain"]:
            problems.append(
                f"{piece_id}: the client puts it on chain {client[piece_id]['chain']!r}, "
                f"the bake on {baked[piece_id]['chain']!r}"
            )
    return problems


def stale(bake, pieces: list[dict], record: dict | None) -> tuple[list[str], str]:
    """Compare what the bake would emit today with what the meshes on disk were baked from.

    Returns one line per difference and a one-line tally. No lines means every piece of today
    has its two GLBs on disk, baked at today's arcs from today's layout. The tally counts piece
    by piece, so a new kind of piece (a lane) or a moved hash never makes a street piece that
    has not moved look stale: it stays "fresh" and the upload's own sha256 check skips it.
    """
    problems: list[str] = []
    baked = {p["id"]: p for p in pieces}
    known = (record or {}).get("pieces") or {}
    missing = sorted(set(baked) - set(known))
    retired = sorted(set(known) - set(baked))
    moved, fresh = [], []
    for piece_id in sorted(set(known) & set(baked)):
        was = known[piece_id].get("nodeArcs") or [None, None]
        now = baked[piece_id]["nodeArcs"]
        files = [mesh.get("glb") for mesh in (known[piece_id].get("meshes") or {}).values()]
        absent = [rel for rel in files if not rel or not os.path.isfile(os.path.join(REPO_ROOT, rel))]
        drift = 0.0 if None in was else max(abs(was[0] - now[0]), abs(was[1] - now[1]))
        if drift > RECORD_EPS:
            moved.append(piece_id)
            problems.append(
                f"{piece_id}: the mesh on disk was baked at arcs {was[0]:.3f}-{was[1]:.3f}, "
                f"today's network says {now[0]:.3f}-{now[1]:.3f} ({drift:.3f} studs) -- re-bake and re-upload"
            )
        elif absent or len(files) < 2:
            missing.append(piece_id)
        else:
            fresh.append(piece_id)
    if missing:
        problems.append(f"{len(missing)} piece(s) have no mesh on disk yet: {', '.join(sorted(missing))}")
    if retired:
        problems.append(f"{len(retired)} piece(s) on disk are no longer baked: {', '.join(retired)}")
    if record and record.get("layoutHash") and record["layoutHash"] != bake.layout_hash():
        problems.append(f"layout hash moved since the bake: {record['layoutHash']} -> {bake.layout_hash()}")
    tally = f"{len(fresh)} piece(s) fresh, {len(missing)} missing, {len(moved)} moved, {len(retired)} retired"
    return problems, tally
