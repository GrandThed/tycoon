"""The path network the bake slices into pieces: a Python mirror of src/client/City/PathRibbon.luau
`Build` / `ArcAt` / `FullSpan`, over tools/streetplan.py's road network.

Why a mirror and not a second design: every client derives its own dressing from
(era, tier, owned slots), so the piece the client asks for must be the piece that was baked. Both
sides therefore start from the same three facts -- the layout's street polylines, its spurs and
streetplan's node/stretch numbering -- and apply the same smoothing.

Chains are maximal (one per polyline, one per connector, one per spur) and never depend on what is
owned, exactly as PathRibbon does, so a piece's geometry is fixed for the layout.

M12 wave 2.2 "narrow driveways" (`road.paths.spurWidth`): a spur chain has a width of its own.
As in PathRibbon.Build, what shapes the spur's own ribbon scales with it -- the corner radius,
the shortest leg it can bend on, the meander taper, and here the mesh width -- while what
measures the street it joins stays in street widths: the host reach and the run past the host's
centreline. Without the key the spur width is the road's and every number is the one it was.

M12 wave 2.5 "baked lanes": every back lane of the era's fabric data (Config/Fabric/<Era>.json
`lanes`) is a piece too. PathRibbon knows nothing of them -- the client clones `LN_<k>` where the
bake put it and reads no arc -- so their geometry is the bake's own, and it is a spur's: the lane's
polyline from its far point to its mouth at `fabric.lanes.width`, bends filleted at the lane's
width, the mouth snapped onto the street's smoothed centreline and run EXTEND_WIDTHS street widths
past it. The far point is a round end that runs on by the cap's length, so the lane is full
width at its last point and two lanes that meet there overlap instead of pinching. Lane chains
come after every other chain and never touch the street they join (no junction, no rounding), so
the street and spur pieces bake to the bytes they had before.

Piece ids (INTERFACES "Wave 1d - Pieces", "Wave 2.5 - Pieces"):
    L<polylineIndex>_<stretchIndex>   one spine stretch, `polylineIndex` 1-based and
                                      `stretchIndex` the 1-based rank of the stretch among the
                                      stretches of that polyline, in network creation order
    SP_<slotId>                       one spur
    LN_<laneIndex>                    one back lane, by its 1-based index in the fabric data

A reader can verify the match without running Studio: `py tools/paths/bake.py --era <Era>
--list` prints every piece id with its node points and arc range, and the client builds the same
id from `stretch.polyline` and the same rank over `state.stretches` (RoadGraph numbers stretches
1-based in the same order streetplan does 0-based, which is why only the rank is used).
"""

from __future__ import annotations

import hashlib
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(REPO_ROOT, "tools"))
sys.path.insert(0, os.path.join(REPO_ROOT, "tools", "pathmock"))
sys.path.insert(0, HERE)
import cityfabric  # noqa: E402
import pathgeom as pg  # noqa: E402
import planargeom as geom  # noqa: E402
import streetplan  # noqa: E402

# PathRibbon constants that are not pathgeom's; same names, same values.
ROUND_END_REACH = 1.5  # a join this close to a chain end rounds that end
HOST_REACH_EXTRA = 0.1  # host test radius beyond width / 2
MEANDER_STEP = 0.1  # dense resample of the meandered centreline
DENSE_DEDUPE_EPS = 1e-3
DEDUPE_EPS = 0.05
END_EPS = 0.05  # a node this close to a curve end is that end
CONNECTOR_KEY_BASE = 97  # a connector's meander phase key: 97 + its 0-based stretch id
GOLDEN_ANGLE = 2.399963
CENTRELINE_SPACING = 1.0  # studs between the centreline points written to <Era>.json
FALLBACK_WAVELENGTH = 18.0  # unused without a meander (amplitude 0), kept finite
LANE_LAYER = 3  # above the spurs' 2: a lane may join any street or connector, never a spur or a lane
LANE_KEY_BASE = 4000  # a lane's meander phase key: 4000 + its index (spurs use their id's byte sum)
# A lane's bend radius in lane widths. A spur's radius (2 widths) cuts each right-angle bend 2.49
# studs inside its data point, which put a lane's fill 0.96 studs into the lot on the inside of
# the bend: lots stand 2.2 from the lane's data polyline. At 1 width the fill stays off every lot
# and no outline folds (INTERFACES "Wave 2.5", lead's ruling).
LANE_FILLET_WIDTHS = 1.0


class Bake:
    """One era's network, chains and pieces."""

    def __init__(self, era_name: str, city: dict):
        self.era_name = era_name
        self.era = streetplan.Era(era_name, city)
        paths_cfg = ((city["eras"][era_name].get("road") or {}).get("paths"))
        if not paths_cfg or not paths_cfg.get("tileStuds"):
            raise ValueError(f"{era_name}: eras.{era_name}.road.paths.tileStuds is missing from CityDressing.json")
        self.tile_studs = float(paths_cfg["tileStuds"])
        self.network = streetplan.Network(self.era)
        # RoadGraph's state.spurWidth, which it hands PathRibbon.Build as `spurWidth`.
        self.spur_width = float(streetplan.spur_path_width(self.era))
        meander = self.era.meander
        self.amplitude = float(meander["amplitude"]) if meander else 0.0
        self.wavelength = float(meander["wavelength"]) if meander and meander.get("wavelength") else FALLBACK_WAVELENGTH
        self.jitter = float(meander.get("widthJitter", 0.0)) if meander else 0.0
        self.chains: list[dict] = []
        self.polyline_chains: dict[int, int] = {}
        self.connector_chains: dict[int, int] = {}
        self.spur_chains: dict[str, int] = {}
        self.lane_chains: dict[int, int] = {}
        self.lane_width: float | None = None
        self._build_chains()
        self._prepare()
        self._build_lanes(city)

    # -- chains -------------------------------------------------------------

    def _new_chain(self, kind: str, chain_id: str, layer: int, key: int, points) -> dict:
        return {
            "kind": kind,
            "id": chain_id,
            "layer": layer,
            "key": key,
            "entrance": False,
            "points": pg.drop_collinear(pg.dedupe(list(points), DEDUPE_EPS)),
            "junctions": [],
            "join_start": False,
            "join_end": False,
            "round_start": False,
            "round_end": False,
        }

    def _build_chains(self) -> None:
        # PathRibbon's chain order (connectors, lanes, spurs) so host ties resolve the same way.
        for sid, stretch in enumerate(self.network.stretches):
            if stretch["segment"] is not None:
                continue
            key = CONNECTOR_KEY_BASE + sid
            self.chains.append(self._new_chain("connector", f"conn{key}", 1, key, [stretch["a"], stretch["b"]]))
            self.connector_chains[key] = len(self.chains) - 1
        for index, points in enumerate(self.era.streets):
            chain = self._new_chain("lane", f"lane{index + 1}", 0 if index == 0 else 1, index + 1, points)
            chain["entrance"] = index == 0
            self.chains.append(chain)
            self.polyline_chains[index] = len(self.chains) - 1
        for slot_id in self.network.spur_ids:
            points = self.era.spurs[slot_id]["points"]
            if len(points) < 2:
                continue
            self.chains.append(self._new_chain("spur", slot_id, 2, sum(map(ord, slot_id)), points))
            self.spur_chains[slot_id] = len(self.chains) - 1

    @staticmethod
    def _smoothed(c: dict):
        # smooth_curve derives the shortest leg from the radius: MIN_LEG_WIDTHS chain widths.
        widths = LANE_FILLET_WIDTHS if c["kind"] == "backlane" else pg.FILLET_RADIUS_WIDTHS
        return pg.smooth_curve(c["points"], widths * c["width"])

    def _host_for(self, c: dict, q):
        """The nearest lower-layer street or connector whose unsmoothed centreline passes within
        half a road width of `q`, as (distance, arc on its smoothed curve, chain), or None."""
        reach = self.era.width / 2 + HOST_REACH_EXTRA
        best = None
        for host in self.chains:
            if host["kind"] == "spur" or host["layer"] >= c["layer"]:
                continue
            d, _ = host["raw"].project(q)
            if d <= reach and (best is None or d < best[0]):
                best = (d, host["curve"].project(q)[1], host)
        return best

    def _prepare(self) -> None:
        width = self.era.width
        smoothed, host_for = self._smoothed, self._host_for

        for c in self.chains:
            c["width"] = self.spur_width if c["kind"] == "spur" else width
            c["curve"] = smoothed(c)
            c["raw"] = pg.Curve(list(c["points"]))

        for index in sorted(range(len(self.chains)), key=lambda i: (self.chains[i]["layer"], i)):
            c = self.chains[index]
            if c["layer"] == 0:
                continue
            for at_start in (True, False):
                if c["kind"] == "spur" and at_start:
                    continue  # a spur starts at its slot anchor, under the building
                q = c["points"][0] if at_start else c["points"][-1]
                hit = host_for(c, q)
                if hit is None:
                    continue
                _, arc, host = hit
                target = host["curve"].point(arc)
                pts = list(c["points"])
                if at_start:
                    pts[0] = target
                    c["join_start"] = True
                else:
                    pts[-1] = target
                    c["join_end"] = True
                c["points"] = pg.dedupe(pts, DEDUPE_EPS)
                c["curve"] = smoothed(c)
                host["junctions"].append(arc)
                if arc < ROUND_END_REACH:
                    host["round_start"] = True
                if arc > host["curve"].total - ROUND_END_REACH:
                    host["round_end"] = True

        for c in self.chains:
            # The plot entrance stays open at full width: no extension there. The extensions stay
            # in street widths whatever the chain: a spur's mouth runs past its host's centreline
            # and must end inside the street it joins.
            ext_s = (
                pg.EXTEND_WIDTHS * width
                if c["join_start"]
                else (pg.ROUND_END_WIDTHS * width if (c["round_start"] and not c["entrance"]) else 0.0)
            )
            ext_e = (
                pg.EXTEND_WIDTHS * width
                if c["join_end"]
                else (pg.ROUND_END_WIDTHS * width if c["round_end"] else 0.0)
            )
            self._finish(c, ext_s, ext_e)

    def _finish(self, c: dict, ext_s: float, ext_e: float) -> None:
        """The drawn curve of a smoothed chain: the meander, then the straight end extensions."""
        curve = c["curve"]
        total = curve.total
        taper_length = pg.MEANDER_TAPER_WIDTHS * c["width"]
        phase = (c["key"] * GOLDEN_ANGLE) % (2 * math.pi)
        c["phase"] = phase
        nodes = [0.0, total] + list(c["junctions"])
        count = max(8, math.ceil(total / MEANDER_STEP))
        kept, kept_smooth = [], []
        for k in range(count + 1):
            s = total * k / count
            t = curve.tangent(s)
            nearest = min(abs(s - node) for node in nodes)
            offset = self.amplitude * pg.smoothstep(nearest / taper_length) * pg.wave(s, phase, self.wavelength)
            point = pg.add(curve.point(s), pg.mul((-t[1], t[0]), offset))
            if not kept or pg.length(pg.sub(point, kept[-1])) > DENSE_DEDUPE_EPS:
                kept.append(point)
                kept_smooth.append(s)
        c["final"] = pg.Curve(kept, ext_s, ext_e)
        if ext_s > 0 and len(kept) >= 2:
            kept_smooth.insert(0, -ext_s)
        if ext_e > 0 and len(kept) >= 2:
            kept_smooth.append(total + ext_e)
        c["final_smooth"] = kept_smooth
        c["ext"] = (ext_s, ext_e)
        c["width_at"] = lambda s, c=c: c["width"] + self.jitter * pg.wave(
            s * 1.37, c["phase"] + 2.1, self.wavelength * 0.8
        ) * 0.5

    def _build_lanes(self, city: dict) -> None:
        """The back lanes of the era's fabric data as chains, after every other chain is finished.

        A lane gets a chain when the client can show it: the era has a valid `fabric.lanes` block
        and the lane is well formed with at least one leg (Fabric.luau's rules, read through
        tools/cityfabric.py). The chain runs from the lane's far point to its mouth, which makes
        it a spur in every respect that matters to the ribbon: it joins at its end."""
        fabric = city["eras"][self.era_name].get("fabric") or {}
        config = cityfabric.valid_lane_config(fabric.get("lanes"))
        data = cityfabric.load_fabric_data(self.era_name)
        lanes = data.get("lanes") if isinstance(data, dict) else None
        if config is None or not isinstance(lanes, list):
            return
        self.lane_width = float(config["width"])
        # The round end: the fill's cap, and the rim's run past the fill's tip, both on real curve
        # (a tip on the chain's very end would cut the rim off square).
        ext_start = pg.CAP_LENGTH + geom.RIM_CAP_EXTRA
        for index, lane in enumerate(lanes, start=1):
            if not cityfabric.valid_lane(lane) or not cityfabric.lane_legs(lane):
                continue
            points = [(float(p[0]), float(p[1])) for p in reversed(lane["points"])]
            c = self._new_chain("backlane", f"backlane{index}", LANE_LAYER, LANE_KEY_BASE + index, points)
            c["lane"] = index
            c["width"] = self.lane_width
            c["raw"] = pg.Curve(list(c["points"]))
            hit = self._host_for(c, c["points"][-1])
            if hit is not None:
                # Snapped onto the street's smoothed centreline like any joiner, but the street is
                # left exactly as it was: a junction or a rounded end would move its own pieces.
                _, arc, host = hit
                c["points"] = pg.dedupe(list(c["points"][:-1]) + [host["curve"].point(arc)], DEDUPE_EPS)
                c["join_end"] = True
            c["curve"] = self._smoothed(c)
            self._finish(c, ext_start, pg.EXTEND_WIDTHS * self.era.width if c["join_end"] else 0.0)
            self.chains.append(c)
            self.lane_chains[index] = len(self.chains) - 1

    # -- arcs ---------------------------------------------------------------

    def arc_at(self, c: dict, q) -> float:
        """PathRibbon.ArcAt: a network node's arc length on the drawn curve, found on the smoothed
        centreline and mapped through it, so the same node lands identically on both sides."""
        _, smooth = c["curve"].project(q)
        table, final = c["final_smooth"], c["final"]
        if not table:
            return 0.0
        if smooth <= table[0]:
            return final.s[0]
        if smooth >= table[-1]:
            return final.s[len(table) - 1]
        lo, hi = 0, len(table) - 1
        while hi - lo > 1:
            mid = (lo + hi) // 2
            if table[mid] <= smooth:
                lo = mid
            else:
                hi = mid
        span = table[hi] - table[lo]
        t = 0.0 if span < 1e-9 else (smooth - table[lo]) / span
        return final.s[lo] + (final.s[hi] - final.s[lo]) * t

    # -- pieces -------------------------------------------------------------

    def piece_id(self, stretch_index: int) -> str:
        """`L<polylineIndex>_<stretchIndex>`; see the module docstring for the numbering."""
        polyline = self.network.stretches[stretch_index]["polyline"]
        rank = 1 + sum(1 for s in self.network.stretches[:stretch_index] if s["polyline"] == polyline)
        return f"L{polyline + 1}_{rank}"

    def chain_for_stretch(self, stretch_index: int) -> dict:
        stretch = self.network.stretches[stretch_index]
        if stretch["segment"] is None:
            return self.chains[self.connector_chains[CONNECTOR_KEY_BASE + stretch_index]]
        return self.chains[self.polyline_chains[stretch["polyline"]]]

    def visible_stretches(self) -> list[int]:
        """Every stretch some building's path draws at full ownership: the union of the shortest
        paths from the entrance to each spur's join node (Wave 1b's growth rule)."""
        visible = set()
        for slot_id in self.network.spur_ids:
            ids = self.network.path_stretches(self.network.junction_nodes.get(slot_id))
            if ids:
                visible.update(ids)
        return sorted(visible)

    def _window(self, c: dict, node_lo: float, node_hi: float) -> dict:
        """The arc range to bake for one node-to-node run, with each end's finish.

        PathRibbon's rule for a drawn run: an end on the chain's own end keeps the chain's join or
        round extension (the plot entrance stays open), and an end in the middle of the chain runs
        on by ROUND_END_WIDTHS widths and caps round there. Because that run-on equals the cap
        length, two neighbouring pieces are each exactly full width where the other's cap tapers,
        so the union has no waist and a piece whose neighbour is not owned yet still ends in a
        round tip.
        """
        total = c["final"].total
        ext_s, ext_e = c["ext"]
        run_lo, run_hi = min(node_lo, node_hi), max(node_lo, node_hi)
        start_node, end_node = ext_s, total - ext_e
        round_length = pg.ROUND_END_WIDTHS * self.era.width
        if run_lo <= start_node + END_EPS:
            lo = 0.0
            start_cap = 0.0 if c["entrance"] else (ext_s if ext_s > 0 else pg.CAP_LENGTH)
        else:
            lo = max(0.0, run_lo - round_length)
            start_cap = run_lo - lo
        if run_hi >= end_node - END_EPS:
            hi = total
            end_cap = ext_e if ext_e > 0 else pg.CAP_LENGTH
        else:
            hi = min(total, run_hi + round_length)
            end_cap = hi - run_hi
        if start_cap <= 0 and not (c["entrance"] and lo == 0.0):
            start_cap = pg.CAP_LENGTH
        return geom.window(
            lo,
            hi,
            start_cap,
            end_cap,
            lo > 1e-6 or ext_s == 0,
            hi < total - 1e-6 or ext_e == 0,
        )

    def pieces(self) -> list[dict]:
        """Every piece of the era, sorted by id: one per drawn spine stretch, one per spur, one
        per back lane."""
        out = []
        for stretch_index in self.visible_stretches():
            stretch = self.network.stretches[stretch_index]
            c = self.chain_for_stretch(stretch_index)
            node_lo = self.arc_at(c, stretch["a"])
            node_hi = self.arc_at(c, stretch["b"])
            dist_a = self.network.distance.get(stretch["from"])
            dist_b = self.network.distance.get(stretch["to"])
            out.append(
                {
                    "id": self.piece_id(stretch_index),
                    "kind": "stretch",
                    "stretch": stretch_index,
                    "chain": c["id"],
                    "nodes": [list(stretch["a"]), list(stretch["b"])],
                    "nodeArcs": [node_lo, node_hi],
                    "distances": [dist_a, dist_b],
                    "window": self._window(c, node_lo, node_hi),
                    "_chain": c,
                }
            )
        for slot_id, chain_index in self.spur_chains.items():
            c = self.chains[chain_index]
            total = c["final"].total
            ext_s, ext_e = c["ext"]
            out.append(
                {
                    "id": f"SP_{slot_id}",
                    "kind": "spur",
                    "slot": slot_id,
                    "chain": c["id"],
                    "nodes": [list(c["points"][0]), list(c["points"][-1])],
                    "nodeArcs": [ext_s, total - ext_e],
                    "distances": [None, None],
                    "window": self._window(c, ext_s, total - ext_e),
                    "_chain": c,
                }
            )
        for lane_index, chain_index in self.lane_chains.items():
            c = self.chains[chain_index]
            total = c["final"].total
            ext_s, ext_e = c["ext"]
            out.append(
                {
                    "id": f"LN_{lane_index}",
                    "kind": "lane",
                    "lane": lane_index,
                    "chain": c["id"],
                    "nodes": [list(c["points"][0]), list(c["points"][-1])],
                    "nodeArcs": [ext_s, total - ext_e],
                    "distances": [None, None],
                    # The fill starts where the rim's extra ends, caps round over CAP_LENGTH and is
                    # full width at the lane's far point; the rim wraps the tip. The mouth ends in
                    # the join extension like a spur's, with a round tip if it met no street.
                    "window": geom.window(
                        geom.RIM_CAP_EXTRA, total, pg.CAP_LENGTH, ext_e if ext_e > 0 else pg.CAP_LENGTH, True, ext_e == 0
                    ),
                    "_chain": c,
                }
            )
        out.sort(key=lambda p: p["id"])
        seen = {}
        for piece in out:
            if piece["id"] in seen:
                raise ValueError(f"{self.era_name}: two pieces share the id {piece['id']!r}: {seen[piece['id']]} and {piece}")
            seen[piece["id"]] = piece
        return out

    def seeds(self, piece: dict, rim: bool) -> tuple[int, int]:
        """Edge-noise seeds per *chain* and side, not per piece, so two pieces that meet at a node
        carry the same outline function of arc length and their overlap has no step."""
        index = next(i for i, c in enumerate(self.chains) if c["id"] == piece["chain"])
        base = 4 * (index + 1) + (2 if rim else 0)
        return base, base + 1

    def centreline(self, piece: dict) -> list[list[float]]:
        """The drawn centreline between the piece's two nodes, for the dust burst and for checking
        a client's own arcs against the bake."""
        cur = piece["_chain"]["final"]
        a, b = piece["nodeArcs"]
        count = max(1, math.ceil(abs(b - a) / CENTRELINE_SPACING))
        points = []
        for k in range(count + 1):
            p = cur.point(a + (b - a) * k / count)
            points.append([round(p[0], 3), round(p[1], 3)])
        return points

    def layout_hash(self) -> str:
        """Everything the piece set depends on. A changed hash explains a changed piece id; an
        unchanged hash with a changed piece id is a bug, and bake.py refuses it."""
        payload = {
            "streets": [[list(p) for p in street] for street in self.era.streets],
            "spurs": {s: [list(p) for p in self.era.spurs[s]["points"]] for s in sorted(self.era.spurs)},
            "width": self.era.width,
            "meander": self.era.meander,
            "tileStuds": self.tile_studs,
        }
        # Only when it narrows the spurs: an era without the key keeps the hash its meshes carry.
        if self.spur_width != self.era.width:
            payload["spurWidth"] = self.spur_width
        # Likewise only for an era with lane pieces, whose polylines and width the set depends on.
        if self.lane_chains:
            payload["lanes"] = {
                str(index): [list(p) for p in self.chains[chain]["raw"].p] for index, chain in sorted(self.lane_chains.items())
            }
            payload["laneWidth"] = self.lane_width
        text = json.dumps(payload, sort_keys=True, separators=(",", ":"))
        return hashlib.sha256(text.encode("utf-8")).hexdigest()[:16]


def load_city() -> dict:
    return json.loads(streetplan.CITY_CONFIG_PATH.read_text(encoding="utf-8"))


def bake_for(era_name: str) -> Bake:
    return Bake(era_name, load_city())
