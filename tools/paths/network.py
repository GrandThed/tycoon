"""The path network the bake slices into pieces: a Python mirror of src/client/City/PathRibbon.luau
`Build` / `ArcAt` / `FullSpan`, over tools/streetplan.py's road network.

Why a mirror and not a second design: every client derives its own dressing from
(era, tier, owned slots), so the piece the client asks for must be the piece that was baked. Both
sides therefore start from the same three facts -- the layout's street polylines, its spurs and
streetplan's node/stretch numbering -- and apply the same smoothing.

Chains are maximal (one per polyline, one per connector, one per spur) and never depend on what is
owned, exactly as PathRibbon does, so a piece's geometry is fixed for the layout.

Piece ids (INTERFACES "Wave 1d - Pieces"):
    L<polylineIndex>_<stretchIndex>   one spine stretch, `polylineIndex` 1-based and
                                      `stretchIndex` the 1-based rank of the stretch among the
                                      stretches of that polyline, in network creation order
    SP_<slotId>                       one spur

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
        meander = self.era.meander
        self.amplitude = float(meander["amplitude"]) if meander else 0.0
        self.wavelength = float(meander["wavelength"]) if meander and meander.get("wavelength") else FALLBACK_WAVELENGTH
        self.jitter = float(meander.get("widthJitter", 0.0)) if meander else 0.0
        self.chains: list[dict] = []
        self.polyline_chains: dict[int, int] = {}
        self.connector_chains: dict[int, int] = {}
        self.spur_chains: dict[str, int] = {}
        self._build_chains()
        self._prepare()

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

    def _prepare(self) -> None:
        width = self.era.width
        radius = pg.FILLET_RADIUS_WIDTHS * width
        for c in self.chains:
            c["curve"] = pg.smooth_curve(c["points"], radius)
            c["raw"] = pg.Curve(list(c["points"]))

        reach = width / 2 + HOST_REACH_EXTRA

        def host_for(c, q):
            best = None
            for host in self.chains:
                if host["kind"] == "spur" or host["layer"] >= c["layer"]:
                    continue
                d, _ = host["raw"].project(q)
                if d <= reach and (best is None or d < best[0]):
                    best = (d, host["curve"].project(q)[1], host)
            return best

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
                c["curve"] = pg.smooth_curve(c["points"], radius)
                host["junctions"].append(arc)
                if arc < ROUND_END_REACH:
                    host["round_start"] = True
                if arc > host["curve"].total - ROUND_END_REACH:
                    host["round_end"] = True

        taper_length = pg.MEANDER_TAPER_WIDTHS * width
        for c in self.chains:
            curve = c["curve"]
            total = curve.total
            phase = (c["key"] * GOLDEN_ANGLE) % (2 * math.pi)
            c["phase"] = phase
            nodes = [0.0, total] + list(c["junctions"])
            # The plot entrance stays open at full width: no extension there.
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
            c["width_at"] = lambda s, c=c: width + self.jitter * pg.wave(
                s * 1.37, c["phase"] + 2.1, self.wavelength * 0.8
            ) * 0.5

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
        """Every piece of the era, sorted by id: one per drawn spine stretch, one per spur."""
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
        text = json.dumps(payload, sort_keys=True, separators=(",", ":"))
        return hashlib.sha256(text.encode("utf-8")).hexdigest()[:16]


def load_city() -> dict:
    return json.loads(streetplan.CITY_CONFIG_PATH.read_text(encoding="utf-8"))


def bake_for(era_name: str) -> Bake:
    return Bake(era_name, load_city())
