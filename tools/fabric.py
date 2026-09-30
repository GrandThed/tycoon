#!/usr/bin/env python
"""The city fabric of a growth layout: the parcels a town grows on, the trees it plants and the wild
land it grows out of (docs/INTERFACES.md "M12 contracts": "Fabric data" and "Tools"; "Wave 1c").

    py tools/fabric.py build Village     # writes src/shared/Config/Fabric/Village.json
    py tools/fabric.py check Village     # exit 1 when that file is stale or breaks a rule

Inputs, each from its owner:
  * the layout (streets, slots, pads, plazas, the Sign) through tools/streetplan.py, which parses
    src/shared/Layouts/<Era>.luau exactly as it does for its own rules;
  * the road network, and each stretch's piece id, through tools/streetplan.Network and
    tools/paths/network.py's `Bake.piece_id`, so a parcel's `stretch` is the RoadGraph piece id the
    client keys its visible stretches by, and its `along` is measured from that stretch's `a` end;
  * parcel sizes, pull, marker and town-tree config from Config/CityDressing.json `eras.<Era>.fabric`;
  * everything the generator decides with -- seeds, spacing, setbacks, rows, tree rules, the wild
    density plan -- from tools/fabric/<Era>.plan.json. Nothing tunable lives in this file: the
    constants below are the contract's own check values.

Parcels. Row 1 lines every street leg on both sides, front on the setback line, facing the street
square on, sizes drawn medium-or-small per position, with a gap left every few parcels for a street
tree. Rows 2 and 3 stand directly behind the row in front and inherit its address; CityFabric keeps
each a `rowLag` behind its front, so a back row is only laid where it still becomes a house once the
era is finished. Row 1 comes first, nearest the entrance first; then row 2 and row 3, each in the
order of its fronts.

Town trees. Street trees in the frontage gaps (anchored to their stretch), green and orchard trees
round the civic and farm landmarks and the tree slot's green (anchored to the landmark's approach
stretch), yard trees behind the last row of houses (anchored to the nearest parcel). Every one keeps
off the walker and car lanes and clear of parcels, slots, pads, markers and lamps.

Wild. Merged clumps of woods laid by blue noise (variable spacing, any turn, varied scale) wherever
the density plan says woods, singles and round trees on a finer blue noise where the woods thin out
and round a few small glades, a low sparse band at the front so the camera always sees the next pad,
and a skirt past the side and back edges that tapers toward the hub corners. A clump is four copies
of one quarter design, and `quads` holds each quarter's centre by the contract's rotation mapping.

The JSON is deterministic: string-seeded random streams, fixed iteration order, numbers rounded
to 0.01 and written by a fixed formatter, so two builds are byte-identical and `check` can demand
that the committed file equals a fresh build.
"""

from __future__ import annotations

import argparse
import json
import math
import random
import sys
import types
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "tools"))
sys.path.insert(0, str(REPO_ROOT / "tools" / "paths"))

import streetplan  # noqa: E402

PLAN_DIR = REPO_ROOT / "tools" / "fabric"
OUT_DIR = REPO_ROOT / "src" / "shared" / "Config" / "Fabric"
CITY_CONFIG_PATH = REPO_ROOT / "src" / "shared" / "Config" / "CityDressing.json"

FORMAT_VERSION = 1
DECIMALS = 2

# Contract check values (INTERFACES "M12 contracts" -> "Tools", "Review amendments", "Wave 1c"),
# not tunables: a parcel keeps this much daylight from each kind of solid, a row-1 parcel's front
# stays this close to its setback line, and a town tree keeps a stud from everything built.
CHECK_SLOT = 1.0
CHECK_PAD = 0.5
CHECK_PLAZA = 1.0
CHECK_EDGE = 1.0
CHECK_STRIP_EXTRA = 1.0  # a street or spur strip is road width / 2 + this
CHECK_FRONT_SLACK = 2.0
CHECK_MARKER_SLOT = 0.5  # the next-pad marker's daylight to any slot footprint (and any parcel)
CHECK_TREE = 1.0  # a town tree's daylight to a parcel, slot footprint, pad, marker or lamp
CHECK_TREE_EDGE = 1.0
CHECK_TREE_SPACING = 2.0  # two trunks closer than this read as one tree
MARKER_SIZE = 2.0  # the marker prop's ground square, the contract's cap
BUILT_LEVEL = 2  # a parcel's house stands from level 2 (a parcel-anchored tree needs it)
MAX_ROW = 3
# Two derivations of the same rounded number agree to this.
EPS = 0.02
COLLINEAR = 1e-6  # |sin| between two legs that count as one straight run
QUARTER_TURN = 90.0
TOP_TIER = 5  # GrowthTier at the end of an era (CityGrowth thresholds has five entries)
QUARTERS = 4
SIZES = ("small", "medium")
KINDS = ("clump", "single")
ANCHORS = ("stretch", "parcel")


# --------------------------------------------------------------------------------------------
# Geometry (plot-local x/z studs, the same conventions as streetplan)
# --------------------------------------------------------------------------------------------


def rotate(x, z, degrees):
    """Roblox CFrame.Angles(0, a, 0) on the XZ plane: local (x, z) -> (x cos a + z sin a,
    -x sin a + z cos a). Every mirror of the fabric uses exactly this mapping."""
    a = math.radians(degrees)
    return (x * math.cos(a) + z * math.sin(a), -x * math.sin(a) + z * math.cos(a))


def rect(centre, size, rotation):
    """A parcel's footprint polygon (local X right, local -Z the front)."""
    return streetplan.square(centre, size[0], size[1], rotation)


def unrotated_pad(slot, pad_size):
    """PlotService.padWorldCFrame places every pad unrotated in the plot frame."""
    return streetplan.square(slot["pad"], pad_size[0], pad_size[1], 0)


def gap(p, q):
    """Daylight between two convex polygons; 0 when they touch, cross or one holds the other."""
    if any(streetplan.point_in_polygon(v, q) for v in p) or any(streetplan.point_in_polygon(v, p) for v in q):
        return 0.0
    return streetplan.gap(p, q)


def point_gap(point, poly):
    """Daylight from a point to a convex polygon; 0 inside it."""
    if streetplan.point_in_polygon(point, poly):
        return 0.0
    return streetplan.point_polygon_distance(point, poly)


def segment_gap(a, b, poly):
    return streetplan.segment_polygon_distance(a, b, poly)


def front_centre(x, z, rotation, depth):
    f = streetplan.facing(rotation)
    return (x + f[0] * depth / 2, z + f[1] * depth / 2)


def rounded(value):
    return round(value + 0.0, DECIMALS) + 0.0


def norm_degrees(value):
    value = value % 360.0
    return 0.0 if abs(value - 360.0) < 10 ** -DECIMALS else value


def box_of(points):
    xs = [p[0] for p in points]
    zs = [p[1] for p in points]
    return (min(xs), max(xs), min(zs), max(zs))


def boxes_apart(a, b, margin):
    """True when two bounding boxes are more than `margin` apart, so no exact test can fail."""
    return a[0] - b[1] > margin or b[0] - a[1] > margin or a[2] - b[3] > margin or b[2] - a[3] > margin


def point_box_apart(point, box, margin):
    return (
        point[0] < box[0] - margin or point[0] > box[1] + margin or point[1] < box[2] - margin or point[1] > box[3] + margin
    )


def facing_rot(direction):
    """The rotationY whose facing is `direction`: facing(r) = (-sin r, -cos r)."""
    return math.degrees(math.atan2(-direction[0], -direction[1]))


# --------------------------------------------------------------------------------------------
# Inputs
# --------------------------------------------------------------------------------------------


def load_city():
    return json.loads(CITY_CONFIG_PATH.read_text(encoding="utf-8"))


def load_plan(era_name):
    path = PLAN_DIR / f"{era_name}.plan.json"
    if not path.exists():
        raise SystemExit(f"no fabric plan for {era_name}: {path.relative_to(REPO_ROOT)}")
    return json.loads(path.read_text(encoding="utf-8"))


def fabric_config(city, era_name):
    config = (city.get("eras", {}).get(era_name) or {}).get("fabric")
    if not config:
        raise SystemExit(f"CityDressing.json has no eras.{era_name}.fabric block")
    return config


def piece_ids(network):
    """tools/paths/network.py's Bake.piece_id for every stretch: `L<polyline>_<rank>`, the rank of
    the stretch among its polyline's stretches in network creation order."""
    import network as paths_network  # tools/paths; imported late so streetplan can import this file

    view = types.SimpleNamespace(network=network)
    return [paths_network.Bake.piece_id(view, index) for index in range(len(network.stretches))]


class Site:
    """Everything static the fabric is generated against and checked against."""

    def __init__(self, era_name, city=None, era=None, network=None):
        self.city = city or load_city()
        self.era = era or streetplan.Era(era_name, self.city)
        self.network = network or streetplan.Network(self.era)
        self.name = era_name
        self.config = fabric_config(self.city, era_name)
        self.sizes = {name: tuple(float(v) for v in self.config["sizes"][name]) for name in SIZES}
        self.width = float(self.era.width)
        self.ids = piece_ids(self.network)
        self.stretch_by_id = {pid: index for index, pid in enumerate(self.ids)}
        # Every stretch some building's path draws once the whole era is owned (wave 1b's rule).
        self.drawn = set()
        # The stretch that brings each routable slot's path to its join: drawn exactly when that
        # slot, or one further along the same street, is owned.
        self.approach = {}
        for slot_id in self.network.spur_ids:
            path = self.network.path_stretches(self.network.junction_nodes.get(slot_id))
            if path:
                self.drawn.update(path)
                self.approach[slot_id] = path[0]
        pad = self.era.layout["padSize"]
        self.pad_size = (float(pad[0]), float(pad[2]))
        self.slot_polys = {}
        self.pad_polys = {}
        for slot in self.era.slots:
            self.slot_polys[slot["id"]] = slot["footprint"]
            self.pad_polys[slot["id"]] = unrotated_pad(slot, self.pad_size)
        self.plaza_polys = [plaza["poly"] for plaza in self.era.plazas]
        # The next-pad marker (NoticeBoard) is at most 2 x 2 studs (INTERFACES "Village props").
        self.marker_size = (MARKER_SIZE, MARKER_SIZE)
        marker = self.config.get("marker") or {}
        self.marker_offset = [float(v) for v in marker["offset"]] if marker.get("offset") is not None else None
        self.marker_polys = {}
        if self.marker_offset is not None:
            for slot in self.era.slots:
                self.marker_polys[slot["id"]] = marker_poly(self, slot, self.marker_offset)
        self.street_segments = []  # (polyline, segment, a, b)
        for index, street in enumerate(self.era.streets):
            for segment, (a, b) in enumerate(streetplan.polyline_segments(street)):
                if math.dist(a, b) >= streetplan.MIN_LENGTH:
                    self.street_segments.append((index, segment, a, b))
        self.spur_segments = []  # (slot id, a, b)
        for slot in self.era.slots:
            for a, b in streetplan.polyline_segments(self.era.spurs[slot["id"]]["points"]):
                if math.dist(a, b) >= streetplan.MIN_LENGTH:
                    self.spur_segments.append((slot["id"], a, b))
        self.street_boxes = [(pl, seg, a, b, box_of((a, b))) for pl, seg, a, b in self.street_segments]
        self.spur_boxes = [(a, b, box_of((a, b))) for _, a, b in self.spur_segments]
        self.entrance = self.era.streets[0][0] if self.era.streets and self.era.streets[0] else (0.0, -self.era.half_z)
        lamps = self.era.dressing.get("lamps") or {}
        post = streetplan.post_size(self.era, lamps.get("prop"))
        self.lamps = [streetplan.square(p, post, post, 0) for p in streetplan.row_lamp_posts(self.era, self.network)]
        walkers = self.era.dressing.get("pedestrians") or {}
        offset = float(walkers.get("offset", self.width / 2))
        clearance = float(walkers.get("clearance", 0.0))
        # A walker's lane is `offset` off a street's centreline and keeps `clearance` from solids;
        # carts run on the centreline (laneOffsetFraction 0), so past the walker lane is past both.
        self.lane_clear = offset + clearance
        # Back rows are not walk solids (INTERFACES "Review rulings", wave 1c), so they keep a
        # meandering walker's whole reach off every street and spur.
        meander = float((self.era.meander or {}).get("amplitude", 0.0))
        self.walker_street = offset + meander + clearance
        self.walker_spur = min(offset, streetplan.spur_path_width(self.era) / 2) + meander + clearance
        # A streetOnly slot spawns no model: its rect only clears woods, so parcels may use it.
        self.street_only = {slot["id"] for slot in self.era.config["slots"] if slot.get("streetOnly")}

    def solid_boxes(self, rules):
        """(polygon, its bounding box, the daylight a parcel keeps from it) for every solid."""
        key = (rules["slot"], rules["pad"], rules["plaza"], rules["sign"], rules["marker"])
        if getattr(self, "_solids_key", None) != key:
            solids = [(poly, rules["slot"]) for slot_id, poly in self.slot_polys.items() if slot_id not in self.street_only]
            solids += [(poly, rules["pad"]) for poly in self.pad_polys.values()]
            solids += [(poly, rules["plaza"]) for poly in self.plaza_polys]
            solids += [(poly, rules["marker"]) for poly in self.marker_polys.values()]
            solids.append((self.era.sign_poly, rules["sign"]))
            self._solids = [(poly, box_of(poly), margin) for poly, margin in solids]
            self._solids_key = key
        return self._solids

    def stretch_at(self, polyline, segment, t):
        """The stretch of `polyline`'s `segment` holding parameter t (a node shared by two
        stretches belongs to the one that starts there, so a parcel at a node is addressed forward)."""
        best = None
        for index, stretch in enumerate(self.network.stretches):
            if stretch["polyline"] != polyline or stretch["segment"] != segment:
                continue
            if stretch["t0"] - 1e-9 <= t <= stretch["t1"] + 1e-9:
                if best is None or stretch["t0"] > self.network.stretches[best]["t0"]:
                    best = index
        return best

    def nearest_drawn(self, point):
        """The drawn stretch whose chord passes nearest `point`."""
        best, best_d = None, math.inf
        for index in sorted(self.drawn):
            st = self.network.stretches[index]
            d, _ = streetplan.point_segment_distance(point, st["a"], st["b"])
            if d < best_d:
                best, best_d = index, d
        return best


# --------------------------------------------------------------------------------------------
# Parcels
# --------------------------------------------------------------------------------------------


def parcel_clear(site, poly, rules, own_segments, placed):
    """Every clearance the generator keeps (the plan's numbers, at least the contract's). A
    bounding-box test skips every obstacle too far away to matter before the exact one runs."""
    era = site.era
    edge = era.half_x - rules["edge"]
    if any(abs(v[0]) > edge or abs(v[1]) > era.half_z - rules["edge"] for v in poly):
        return False
    box = box_of(poly)
    for obstacle, obstacle_box, margin in site.solid_boxes(rules):
        if not boxes_apart(box, obstacle_box, margin) and gap(poly, obstacle) < margin:
            return False
    for polyline, segment, a, b, segment_box in site.street_boxes:
        need = rules["frontSetback"] - 0.05 if (polyline, segment) in own_segments else rules["street"]
        if not boxes_apart(box, segment_box, need) and segment_gap(a, b, poly) < need:
            return False
    for a, b, segment_box in site.spur_boxes:
        if not boxes_apart(box, segment_box, rules["spur"]) and segment_gap(a, b, poly) < rules["spur"]:
            return False
    for other in placed:
        # Coordinates are rounded to 0.01, so a neighbour laid exactly `gap` away can measure a
        # hair under it.
        if not boxes_apart(box, other["box"], rules["gap"]) and gap(poly, other["poly"]) < rules["gap"] - EPS:
            return False
    return True


def make_parcel(site, size, centre, rotation, stretch, along, row, front):
    x, z = rounded(centre[0]), rounded(centre[1])
    rotation = rounded(norm_degrees(rotation))
    poly = rect((x, z), site.sizes[size], rotation)
    return {
        "x": x,
        "z": z,
        "rotationY": rotation,
        "size": size,
        "stretch": site.ids[stretch],
        "along": rounded(along),
        "row": row,
        "front": front,
        "poly": poly,
        "box": box_of(poly),
    }


def street_runs(site):
    """Each polyline as maximal straight runs: a vertex where the line does not turn (a lane
    junction on a straight stretch) does not break the frontage, a bend does."""
    runs = []
    for index, street in enumerate(site.era.streets):
        run = None
        for segment, (a, b) in enumerate(streetplan.polyline_segments(street)):
            d = streetplan.unit((b[0] - a[0], b[1] - a[1]))
            if d is None:
                continue
            # Only truly collinear legs share a run: parcels are laid along the run's chord, so a
            # kink, however slight, would put their fronts off their own stretch.
            collinear = run is not None and abs(run["d"][0] * d[1] - run["d"][1] * d[0]) < COLLINEAR
            if collinear and run["d"][0] * d[0] + run["d"][1] * d[1] > 0:
                run["b"] = b
                run["segments"].append((segment, a, b))
            else:
                run = {"polyline": index, "a": a, "b": b, "d": d, "segments": [(segment, a, b)]}
                runs.append(run)
    return runs


def locate(site, run, s):
    """(stretch index, along) of the point `s` studs along a run, or None past its ends."""
    acc = 0.0
    for segment, a, b in run["segments"]:
        length = math.dist(a, b)
        if s <= acc + length + 1e-9:
            t = max(0.0, (s - acc) / length)
            stretch = site.stretch_at(run["polyline"], segment, t)
            if stretch is None:
                return None
            point = (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
            return stretch, math.dist(site.network.stretches[stretch]["a"], point)
        acc += length
    return None


def walk_run(site, rules, run, side, sizes_for, rng, jitter, placed, rhythm=None, gaps=None):
    """Lay parcels along one side of a straight run, fronts near the setback line, from its start.
    Each candidate stands a little back from the line and a few degrees off square (the plan's
    jitter, its own random stream), so a row of cottages reads as grown rather than surveyed. With
    `gaps`, every few parcels in an unbroken row leave a gap a street tree stands in."""
    a, b, d = run["a"], run["b"], run["d"]
    length = math.dist(a, b)
    own = {(run["polyline"], segment) for segment, _, _ in run["segments"]}
    front = rules["frontSetback"]
    n = (-d[1] * side, d[0] * side)
    square_on = facing_rot((-n[0], -n[1]))
    s = rules["endMargin"]
    streak = 0
    every = rhythm.choice(rules["treeGapEvery"]) if rhythm is not None else 0
    last_end = None
    while s < length - rules["endMargin"]:
        accepted = None
        for size in sizes_for(rng):
            w, depth = site.sizes[size]
            mid = s + w / 2
            back = jitter.uniform(0.0, rules["setbackJitter"])
            turn = jitter.uniform(-rules["turnJitter"], rules["turnJitter"])
            if mid > length:
                continue  # the front centre must project onto its own stretch
            where = locate(site, run, mid)
            if where is None or where[0] not in site.drawn:
                continue
            stretch, along = where
            reach = front + back + depth / 2
            centre = (a[0] + d[0] * mid + n[0] * reach, a[1] + d[1] * mid + n[1] * reach)
            candidate = make_parcel(site, size, centre, square_on + turn, stretch, along, 1, 0)
            # `along` is the foot of the perpendicular from the (turned) front centre, per contract.
            fc = front_centre(candidate["x"], candidate["z"], candidate["rotationY"], depth)
            st = site.network.stretches[stretch]
            _, foot = streetplan.point_segment_distance(fc, st["a"], st["b"])
            candidate["along"] = rounded(math.dist(st["a"], foot))
            if parcel_clear(site, candidate["poly"], rules, own, placed):
                accepted = candidate
                break
        if accepted is None:
            s += rules["walkStep"]
            continue
        # A free stretch at least a tree gap wide (a pad, a junction, a jitter clash) already broke
        # the row: a street tree may stand in it, and the rhythm restarts after it.
        start = rules["endMargin"] if last_end is None else last_end
        if s - start >= rules["treeGap"]:
            if gaps is not None:
                gaps.append({"run": run, "side": side, "s": (start + s) / 2})
            streak = 0
        placed.append(accepted)
        s += site.sizes[accepted["size"]][0]
        streak += 1
        if gaps is not None and streak >= every and s + rules["treeGap"] < length - rules["endMargin"]:
            gaps.append({"run": run, "side": side, "s": s + rules["treeGap"] / 2})
            s += rules["treeGap"]
            streak, every = 0, rhythm.choice(rules["treeGapEvery"])
        else:
            s += rules["gap"]
        last_end = s


def entrance_order(site, parcel):
    """Straight-line distance from the entrance (the first point of polyline 1), ties by position."""
    return (round(math.dist(site.entrance, (parcel["x"], parcel["z"])), DECIMALS), parcel["z"], parcel["x"])


def settle_first_row(site, row1, min_level):
    """Drop row-1 parcels that never reach `min_level`. Contiguity links parcels, so one drop can
    strand another: repeat until the set is stable."""
    while True:
        levels = full_build_levels(site, row1)
        keep = [parcel for parcel, level in zip(row1, levels) if level >= min_level]
        if len(keep) == len(row1):
            return keep
        row1 = keep


def behind(site, rules, front, front_index, row, placed):
    """A parcel standing directly behind `front`, facing the same street: the front's size when it
    fits, else a small one, centred on the front's axis. It repeats the front's address."""
    face = streetplan.facing(front["rotationY"])
    depth = site.sizes[front["size"]][1]
    stretch = site.stretch_by_id[front["stretch"]]
    for size in dict.fromkeys((front["size"], "small")):
        offset = depth / 2 + rules["rowGap"] + site.sizes[size][1] / 2
        centre = (front["x"] - face[0] * offset, front["z"] - face[1] * offset)
        candidate = make_parcel(site, size, centre, front["rotationY"], stretch, front["along"], row, front_index)
        candidate["along"] = front["along"]
        if parcel_clear(site, candidate["poly"], rules, set(), placed):
            return candidate
    return None


def generate_parcels(site, plan):
    """Returns (parcels, street-tree gaps). Parcels are in data order: row 1 by distance from the
    entrance, then each back row in the order of its fronts (INTERFACES "Wave 1c": Order)."""
    rules = plan["parcels"]
    rng = random.Random(f"{plan['seed']}:parcels")
    jitter = random.Random(f"{plan['seed']}:jitter")
    rhythm = random.Random(f"{plan['seed']}:rhythm")
    placed, gaps = [], []

    def first_pass(stream):
        return ("medium", "small") if stream.random() < rules["mediumShare"] else ("small", "medium")

    def fill_pass(_stream):
        return ("small",)

    # Frontage first, mostly medium where it fits and a street-tree gap every few parcels; then a
    # second walk fills the holes the first left with small parcels, so no street-side spot a
    # cottage fits is wasted.
    for first, sizes_for in ((True, first_pass), (False, fill_pass)):
        for run in street_runs(site):
            for side in (1, -1):
                walk_run(site, rules, run, side, sizes_for, rng, jitter, placed, rhythm if first else None, gaps if first else None)
    min_level = rules["minLevel"]
    parcels = settle_first_row(site, placed, min_level)
    parcels.sort(key=lambda parcel: entrance_order(site, parcel))
    for row in range(2, min(rules["rows"], MAX_ROW) + 1):
        added = []
        for index, front in enumerate(parcels):
            if front["row"] != row - 1:
                continue
            candidate = behind(site, rules, front, index + 1, row, parcels + added)
            if candidate is not None:
                added.append(candidate)
        # A back row keeps `rowLag` levels behind its front; one that would stay a building site or
        # wild land once the era is finished is not laid at all.
        levels = full_build_levels(site, parcels + added)[len(parcels) :]
        parcels += [parcel for parcel, level in zip(added, levels) if level >= min_level]
    return parcels, gaps


def full_build_levels(site, parcels):
    """Each parcel's level once the whole era is owned (tier 5, every stretch drawn): the contract's
    Develop, steps 1-8 with wave 1c's rows (INTERFACES "CityFabric.Develop", "Rows"), for exactly
    that one state. Levels only rise as slots are bought and the tier climbs, so this is the most a
    parcel ever becomes. `front` is resolved by position in `parcels`."""
    pull = site.config["pull"]
    lag = pull.get("rowLag", 1)
    tier = TOP_TIER
    graph = {}
    lengths = {}
    for index in site.drawn:
        st = site.network.stretches[index]
        graph.setdefault(st["from"], []).append((st["to"], st["length"]))
        graph.setdefault(st["to"], []).append((st["from"], st["length"]))
        lengths[site.ids[index]] = st
    nodes = sorted(graph)
    landmarks = []
    for slot in sorted(site.era.slots, key=lambda s: s["id"]):
        district = site.era.layout["slots"][slot["id"]].get("district")
        node = site.network.junction_nodes.get(slot["id"])
        if district and node is not None:
            landmarks.append((slot["id"], node))

    def shortest(sources):
        dist = dict(sources)
        settled = set()
        while True:
            best, best_d = None, math.inf
            for node in nodes:
                d = dist.get(node)
                if d is not None and d < best_d and node not in settled:
                    best, best_d = node, d
            if best is None:
                return dist
            settled.add(best)
            for other, length in graph[best]:
                if other not in dist or best_d + length < dist[other]:
                    dist[other] = best_d + length

    def reach(dist, st, along):
        a, b = dist.get(st["from"]), dist.get(st["to"])
        return min(a + along if a is not None else math.inf, b + (st["length"] - along) if b is not None else math.inf)

    per_node = {node: shortest({node: 0.0}) for _, node in landmarks}
    levels = []
    for parcel in parcels:
        st = lengths.get(parcel["stretch"])
        influence, pulled = 0.0, False
        for _, node in landmarks:
            if st is None:
                break
            share = max(0.0, 1.0 - reach(per_node[node], st, parcel["along"]) / pull["radius"])
            if share > 0:
                influence += share
                pulled = True
        score = influence + pull["tierTerm"] * tier if pulled else 0.0
        level = min(sum(1 for threshold in pull["thresholds"] if score >= threshold), tier + pull["levelsOverTier"])
        if parcel["size"] == "small":
            level = min(level, pull["smallMaxLevel"])
        levels.append(level if st is not None else 0)
    accepted, grew = set(), True
    while grew:
        grew = False
        sources = {node: 0.0 for _, node in landmarks}
        for index in accepted:
            parcel = parcels[index]
            st = lengths[parcel["stretch"]]
            for node, d in ((st["from"], parcel["along"]), (st["to"], st["length"] - parcel["along"])):
                if node not in sources or d < sources[node]:
                    sources[node] = d
        dist = shortest(sources)
        for index, parcel in enumerate(parcels):
            if parcel["row"] != 1 or index in accepted or levels[index] < 1:
                continue
            st = lengths.get(parcel["stretch"])
            if st is not None and reach(dist, st, parcel["along"]) <= pull["reach"]:
                accepted.add(index)
                grew = True
    for index, parcel in enumerate(parcels):
        if parcel["row"] == 1 and index not in accepted:
            levels[index] = 0
    for index, parcel in enumerate(parcels):
        if parcel["row"] != 1:
            front = parcel["front"] - 1
            front_level = levels[front] if 0 <= front < index else 0
            levels[index] = max(0, min(levels[index], front_level - lag))
    return levels


# --------------------------------------------------------------------------------------------
# Town trees
# --------------------------------------------------------------------------------------------


class TreeSpots:
    """Where a town tree may stand: off every street and spur by the walker lanes' reach, clear of
    every parcel, slot footprint, pad, marker, lamp and the Sign, inside the plot, and apart from
    the trees already chosen. Points are tested exactly as they will be written (rounded)."""

    def __init__(self, site, parcels, cfg):
        self.site, self.cfg = site, cfg
        solids = [(parcel["poly"], cfg["clear"]) for parcel in parcels]
        solids += [(poly, cfg["clear"]) for poly in site.slot_polys.values()]
        solids += [(poly, cfg["clear"]) for poly in site.pad_polys.values()]
        solids += [(poly, cfg["clear"]) for poly in site.marker_polys.values()]
        solids += [(poly, cfg["clear"]) for poly in site.plaza_polys]
        solids += [(poly, cfg["lamp"]) for poly in site.lamps]
        solids.append((site.era.sign_poly, cfg["clear"]))
        self.solids = [(poly, box_of(poly), margin) for poly, margin in solids]
        self.segments = [(a, b, box) for _, _, a, b, box in site.street_boxes] + list(site.spur_boxes)
        self.lane = max(cfg["laneClear"], site.lane_clear)
        self.trees = []

    def fits(self, point):
        site, cfg = self.site, self.cfg
        edge = cfg["edge"]
        if abs(point[0]) > site.era.half_x - edge or abs(point[1]) > site.era.half_z - edge:
            return False
        for poly, box, margin in self.solids:
            if not point_box_apart(point, box, margin) and point_gap(point, poly) < margin:
                return False
        for a, b, box in self.segments:
            if not point_box_apart(point, box, self.lane) and streetplan.point_segment_distance(point, a, b)[0] < self.lane:
                return False
        return all(math.dist(point, (t["x"], t["z"])) >= cfg["spacing"] for t in self.trees)

    def add(self, point, rng, variant, anchor, kind):
        x, z = rounded(point[0]), rounded(point[1])
        if not self.fits((x, z)):
            return False
        low, high = self.cfg["scale"]
        tree = {"x": x, "z": z, "rotationY": rounded(norm_degrees(rng.uniform(0.0, 360.0))), "scale": rounded(rng.uniform(low, high)), "variant": variant}
        tree.update(anchor)
        tree["kind"] = kind  # generator bookkeeping only; stripped before writing
        self.trees.append(tree)
        return True


def ring_candidates(rng, poly, near, far, attempts):
    """Random points whose daylight to `poly` is within [near, far], in draw order."""
    box = box_of(poly)
    out = []
    for _ in range(attempts):
        point = (rng.uniform(box[0] - far, box[1] + far), rng.uniform(box[2] - far, box[3] + far))
        d = point_gap(point, poly)
        if near <= d <= far:
            out.append(point)
    return out


def generate_trees(site, plan, parcels, levels, gaps):
    """The town trees (INTERFACES "Wave 1c": Town trees), in data order: nearest the entrance first."""
    cfg = plan["trees"]
    props = (site.config.get("townTrees") or {}).get("props") or []
    if not props:
        return []
    variants = cfg["variants"]
    rng = random.Random(f"{plan['seed']}:trees")
    spots = TreeSpots(site, parcels, cfg)
    # Street trees: first one in each gap the frontage walk left, then a sweep along both sides of
    # every drawn stretch for any other free spot, `street.spacing` apart along a lane, so every
    # lane gets its rhythm of trees between the houses and the landmarks.
    street = cfg["street"]

    def plant_street(run, side, s):
        where = locate(site, run, s)
        if where is None or where[0] not in site.drawn:
            return False
        d = run["d"]
        n = (-d[1] * side, d[0] * side)
        base = (run["a"][0] + d[0] * s, run["a"][1] + d[1] * s)
        for setback in street["setbacks"]:
            point = (base[0] + n[0] * setback, base[1] + n[1] * setback)
            near = [t for t in spots.trees if t["kind"] == "street" and math.dist(point, (t["x"], t["z"])) < street["spacing"]]
            if near:
                continue
            if spots.add(point, rng, variants["street"], {"anchor": "stretch", "stretch": site.ids[where[0]]}, "street"):
                return True
        return False

    for item in gaps:
        plant_street(item["run"], item["side"], item["s"])
    for run in street_runs(site):
        length = math.dist(run["a"], run["b"])
        for side in (1, -1):
            s = street["step"]
            while s < length - street["step"]:
                s += street["spacing"] if plant_street(run, side, s) else street["step"]
    # Green and orchard trees round landmarks, planted once the landmark's street is drawn; the
    # tree slot's own green (its rect) is ringed by green trees on the stretch nearest it.
    town = site.config.get("townTrees") or {}
    groups = []
    for slot in sorted(site.era.slots, key=lambda s: s["id"]):
        district = site.era.layout["slots"][slot["id"]].get("district")
        if slot["id"] == town.get("requiresSlot"):
            groups.append(("green", slot, site.nearest_drawn(slot["position"])))
        elif district in cfg["orchard"]["districts"] and slot["id"] in site.approach:
            groups.append(("orchard", slot, site.approach[slot["id"]]))
        elif district in cfg["green"]["districts"] and slot["id"] in site.approach:
            groups.append(("green", slot, site.approach[slot["id"]]))
    for kind, slot, stretch in groups:
        if stretch is None:
            continue
        rule = cfg[kind]
        placed = 0
        for point in ring_candidates(rng, slot["footprint"], rule["ring"][0], rule["ring"][1], rule["attempts"]):
            if placed >= rule["count"]:
                break
            if spots.add(point, rng, variants[kind], {"anchor": "stretch", "stretch": site.ids[stretch]}, kind):
                placed += 1
    # Yard trees behind the last row of houses, anchored to the nearest parcel (a house by then).
    yard = cfg["yard"]
    fronts = {parcel["front"] for parcel in parcels if parcel["row"] > 1}
    for index, parcel in enumerate(parcels, start=1):
        if index in fronts or levels[index - 1] < BUILT_LEVEL or rng.random() >= yard["share"]:
            continue
        face = streetplan.facing(parcel["rotationY"])
        width, depth = site.sizes[parcel["size"]]
        side = rng.uniform(-yard["lateral"], yard["lateral"]) * width / 2
        right = (-face[1], face[0])
        reach = depth / 2 + yard["offset"]
        point = (parcel["x"] - face[0] * reach + right[0] * side, parcel["z"] - face[1] * reach + right[1] * side)
        nearest = nearest_parcel((rounded(point[0]), rounded(point[1])), parcels)
        if levels[nearest - 1] < BUILT_LEVEL:
            continue
        spots.add(point, rng, variants["yard"], {"anchor": "parcel", "parcel": nearest}, "yard")
    trees = spots.trees
    trees.sort(key=lambda t: (round(math.dist(site.entrance, (t["x"], t["z"])), DECIMALS), t["z"], t["x"]))
    return trees


def nearest_parcel(point, parcels):
    """1-based index of the parcel whose footprint lies nearest `point` (lowest index on a tie)."""
    best, best_d = None, math.inf
    for index, parcel in enumerate(parcels, start=1):
        d = point_gap(point, parcel["poly"])
        if d < best_d - 1e-9:
            best, best_d = index, d
    return best


def planted_at_full(site, tree, levels):
    """INTERFACES "Wave 1c": a tree stands once the tree slot is owned and its anchor developed."""
    if tree.get("anchor") == "stretch":
        index = site.stretch_by_id.get(tree.get("stretch"))
        return index is not None and index in site.drawn
    if tree.get("anchor") == "parcel":
        parcel = tree.get("parcel")
        return isinstance(parcel, int) and 1 <= parcel <= len(levels) and levels[parcel - 1] >= BUILT_LEVEL
    return False


# --------------------------------------------------------------------------------------------
# Wild land
# --------------------------------------------------------------------------------------------


class Noise:
    """A few summed sines with seeded directions and phases: smooth, deterministic, cheap."""

    def __init__(self, seed, waves, base):
        rng = random.Random(seed)
        self.terms = []
        for i in range(waves):
            angle = rng.uniform(0, math.pi)
            freq = base * (1.6**i) * rng.uniform(0.8, 1.2)
            self.terms.append((math.cos(angle) * freq, math.sin(angle) * freq, rng.uniform(0, 2 * math.pi), 1.0 / (1.5**i)))
        self.norm = sum(term[3] for term in self.terms)

    def __call__(self, x, z):
        return sum(math.sin(x * fx + z * fz + ph) * amp for fx, fz, ph, amp in self.terms) / self.norm


def density(x, z, plan, noise, half, glades=()):
    """1 = woods. The interior is woods except the heart clearing, a few glades and a low front
    band; past the side and back edges a skirt continues, tapering toward the hub corners; nothing
    in front of the plot, where the hub approach stays open."""
    wild = plan["wild"]
    woods = wild["woods"]
    wobble = noise(x, z)
    if z < -half:
        return 0.0
    skirt = wild["skirt"]
    if x < -half or x > half or z > half:
        beyond = max(-half - x, x - half, z - half)
        reach = skirt["depth"] + skirt["wobble"] * wobble
        if z <= half and (x < -half or x > half):
            share = skirt["cornerShare"]
            along = min(1.0, max(0.0, (z + half) / (2 * half)))
            reach = skirt["depth"] * (share + (1 - share) * along) + skirt["sideWobble"] * wobble
        if beyond > reach:
            return 0.0
        return woods * min(1.0, (reach - beyond) / skirt["fade"])
    band = wild["front"]
    ramp = min(1.0, max(0.0, (z + half - band["start"] - band["wobble"] * wobble) / band["ramp"]))
    value = band["low"] + (woods - band["low"]) * ramp
    heart = wild["heart"]
    distance = math.dist((x, z), tuple(heart["centre"])) + heart["wobble"] * wobble
    if distance < heart["clear"] + heart["fade"]:
        value = min(value, band["low"] + (woods - band["low"]) * max(0.0, (distance - heart["clear"]) / heart["fade"]))
    for gx, gz, radius, fade in glades:
        d = math.dist((x, z), (gx, gz))
        if d < radius + fade:
            value = min(value, woods * max(0.0, (d - radius) / fade))
    return value


def blue_noise(rng, limit, attempts, spacing_at, accept):
    """Dart throwing: `attempts` uniform darts over the square, each kept when `accept` takes it and
    no kept point lies within the larger of the two points' spacings. Deterministic for a stream,
    and free of the rows a jittered grid leaves."""
    kept = []
    cell = 4.0
    grid = {}
    widest = 0.0
    for _ in range(attempts):
        x, z = rng.uniform(-limit, limit), rng.uniform(-limit, limit)
        spacing = spacing_at(x, z)
        if spacing <= 0 or not accept(x, z):
            continue
        reach = max(spacing, widest)
        cx, cz = int(math.floor(x / cell)), int(math.floor(z / cell))
        span = int(math.ceil(reach / cell))
        clash = False
        for i in range(cx - span, cx + span + 1):
            for j in range(cz - span, cz + span + 1):
                for px, pz, ps in grid.get((i, j), ()):
                    if math.dist((x, z), (px, pz)) < max(spacing, ps):
                        clash = True
                        break
                if clash:
                    break
            if clash:
                break
        if clash:
            continue
        kept.append((x, z, spacing))
        grid.setdefault((cx, cz), []).append((x, z, spacing))
        widest = max(widest, spacing)
    return kept


def quad_centres(x, z, rotation, scale, offset):
    """INTERFACES "Fabric data": quarter q is the quarter prop turned rotationY + 90 (q - 1), and
    quads[q] is that quarter's centre, the prop's (offset, offset) point in its own frame."""
    out = []
    for q in range(QUARTERS):
        lx, lz = rotate(offset * scale, offset * scale, rotation + QUARTER_TURN * q)
        out.append((x + lx, z + lz))
    return out


def pick_glades(plan, noise, half):
    """A few small clearings deep in the plot's woods, apart from each other and the heart."""
    cfg = plan["wild"]["glades"]
    rng = random.Random(f"{plan['seed']}:glades")
    heart = tuple(plan["wild"]["heart"]["centre"])
    inner = half - cfg["inset"]
    glades = []
    for _ in range(cfg["attempts"]):
        if len(glades) >= cfg["count"]:
            break
        x, z = rng.uniform(-inner, inner), rng.uniform(-inner, inner)
        radius = rng.uniform(*cfg["radius"])
        if math.dist((x, z), heart) < plan["wild"]["heart"]["clear"] + cfg["apart"]:
            continue
        if density(x, z, plan, noise, half) < cfg["minDensity"]:
            continue
        if any(math.dist((x, z), (gx, gz)) < cfg["apart"] + radius + gr for gx, gz, gr, _ in glades):
            continue
        glades.append((x, z, radius, cfg["fade"]))
    return glades


def generate_wild(site, plan):
    wild = plan["wild"]
    names = site.config["wild"]
    half = site.era.half_x
    noise = Noise(f"{plan['seed']}:noise", wild["noise"]["waves"], wild["noise"]["base"])
    spread = Noise(f"{plan['seed']}:spread", wild["noise"]["waves"], wild["noise"]["base"] * 1.7)
    glades = pick_glades(plan, noise, half)
    clumps_cfg, singles_cfg = wild["clumps"], wild["singles"]
    limit = half + wild["skirt"]["depth"] + wild["skirt"]["wobble"]

    def woods(x, z):
        return density(x, z, plan, noise, half, glades)

    # Clumps: spacing varies with a second noise field and with each clump's own size.
    rng = random.Random(f"{plan['seed']}:wild")
    sizes = random.Random(f"{plan['seed']}:clump-size")
    scale_for = {}

    def clump_spacing(x, z):
        scale = sizes.uniform(*clumps_cfg["scale"])
        scale_for[(x, z)] = scale
        return clumps_cfg["spacing"] * scale * (1.0 + clumps_cfg["spacingVar"] * spread(x, z))

    darts = blue_noise(rng, limit, clumps_cfg["attempts"], clump_spacing, lambda x, z: woods(x, z) >= clumps_cfg["minDensity"])
    clumps = []
    for x, z, _spacing in darts:
        variant = rng.randrange(len(names["clumps"])) + 1
        # Rounded before the quarters are placed, so a reader recomputing them from the file lands
        # on the same points.
        cx, cz = rounded(x), rounded(z)
        rotation, scale = rounded(norm_degrees(rng.uniform(0.0, 360.0))), rounded(scale_for[(x, z)])
        inside = abs(cx) <= half and abs(cz) <= half
        quads = quad_centres(cx, cz, rotation, scale, clumps_cfg["quarterOffset"])
        # A clump sits wholly on the plot or wholly off it: the ground past the edge is lower.
        if any((abs(q[0]) <= half and abs(q[1]) <= half) != inside for q in quads):
            continue
        clumps.append(
            {
                "kind": "clump",
                "variant": variant,
                "x": cx,
                "z": cz,
                "rotationY": rotation,
                "scale": scale,
                "skirt": not inside,
                "quads": [[rounded(q[0]), rounded(q[1])] for q in quads],
            }
        )
    # Singles: where the woods thin out (their edge, the front band, the glades' rims), a finer blue
    # noise of round trees, pines and rocks, never inside a clump.
    srng = random.Random(f"{plan['seed']}:singles")
    keep = clumps_cfg["spacing"] * singles_cfg["clumpKeep"]

    def single_spacing(x, z):
        return singles_cfg["spacing"] * (1.0 + singles_cfg["spacingVar"] * spread(x, z))

    def edge_of_woods(x, z):
        value = woods(x, z)
        if not singles_cfg["minDensity"] < value < clumps_cfg["minDensity"]:
            return False
        return all(math.dist((x, z), (c["x"], c["z"])) >= keep * c["scale"] for c in clumps)

    singles = []
    for x, z, _spacing in blue_noise(srng, limit, singles_cfg["attempts"], single_spacing, edge_of_woods):
        value = woods(x, z)
        pick, grow, rotation = srng.random(), srng.random(), srng.uniform(0.0, 360.0)
        if value >= singles_cfg["treeDensity"]:
            pool, scales = singles_cfg["trees"], singles_cfg["treeScale"]
        else:
            pool, scales = singles_cfg["meadow"], singles_cfg["meadowScale"]
        prop = pool[int(pick * len(pool)) % len(pool)]
        inside = abs(x) <= half and abs(z) <= half
        singles.append(
            {
                "kind": "single",
                "prop": prop,
                "x": rounded(x),
                "z": rounded(z),
                "rotationY": rounded(norm_degrees(rotation)),
                "scale": rounded(scales[0] + (scales[1] - scales[0]) * grow),
                "skirt": not inside,
            }
        )
    # The client draws a fixed prefix of this list (INTERFACES "Review amendments"): near plots the
    # first budget.wild entries, far plots the first budget.wildFar clumps. So the skirt's clumps
    # lead -- a far town that has cleared its own woods still sits in its landscape band -- then the
    # plot's clumps farthest from the entrance first, because the town grows out from the entrance
    # and clears those last: the far prefix then keeps the woods a near view still shows. Singles
    # come last. Ties keep a front-to-back order.
    entrance = site.entrance

    def order(entry):
        group = 0 if entry["kind"] == "clump" and entry["skirt"] else 1 if entry["kind"] == "clump" else 2
        reach = round(math.dist(entrance, (entry["x"], entry["z"])), DECIMALS) if group == 1 else 0.0
        return (group, -reach, entry["z"], entry["x"])

    return sorted(clumps + singles, key=order)


# --------------------------------------------------------------------------------------------
# Document
# --------------------------------------------------------------------------------------------

PARCEL_KEYS = ("x", "z", "rotationY", "size", "stretch", "along", "row", "front")
TREE_KEYS = ("x", "z", "rotationY", "scale", "variant", "anchor", "stretch", "parcel")


def build(era_name, city=None, era=None, network=None):
    """The document and the generator's bookkeeping (tree kinds) for the summary."""
    site = Site(era_name, city, era, network)
    plan = load_plan(era_name)
    parcels, gaps = generate_parcels(site, plan)
    levels = full_build_levels(site, parcels)
    trees = generate_trees(site, plan, parcels, levels, gaps)
    wild = generate_wild(site, plan)
    doc = {
        "version": FORMAT_VERSION,
        "parcels": [{key: p[key] for key in PARCEL_KEYS} for p in parcels],
        "trees": [{key: t[key] for key in TREE_KEYS if key in t} for t in trees],
        "wild": wild,
    }
    return doc, [t["kind"] for t in trees]


def build_document(era_name, city=None, era=None, network=None):
    return build(era_name, city, era, network)[0]


def number(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    text = f"{value:.{DECIMALS}f}".rstrip("0").rstrip(".")
    return "0" if text in ("-0", "") else text


def entry_text(entry):
    parts = []
    for key, value in entry.items():
        if isinstance(value, str):
            text = json.dumps(value)
        elif isinstance(value, list):
            text = "[" + ", ".join("[" + ", ".join(number(v) for v in pair) + "]" for pair in value) + "]"
        else:
            text = number(value)
        parts.append(f'"{key}": {text}')
    return "{ " + ", ".join(parts) + " }"


def render(doc):
    """Fixed formatting, one entry per line, so a rebuild is byte-identical and a diff reads."""
    lines = ["{", f'  "version": {doc["version"]},']
    for key in ("parcels", "trees", "wild"):
        items = doc.get(key, [])
        lines.append(f'  "{key}": [')
        lines += [f"    {entry_text(item)}{',' if i < len(items) - 1 else ''}" for i, item in enumerate(items)]
        lines.append("  ]" + ("," if key != "wild" else ""))
    lines.append("}")
    return "\n".join(lines) + "\n"


def out_path(era_name):
    return OUT_DIR / f"{era_name}.json"


# --------------------------------------------------------------------------------------------
# Checks
# --------------------------------------------------------------------------------------------


def marker_poly(site, slot, offset):
    """The next-pad marker's ground square: `marker.offset` is in the slot's frame, turned by its
    rotationY and added to the pad centre (INTERFACES "Review amendments")."""
    dx, dz = rotate(offset[0], offset[2], slot["rotation"])
    size = site.marker_size
    return streetplan.square((slot["pad"][0] + dx, slot["pad"][1] + dz), size[0], size[1], slot["rotation"])


def marker_messages(site):
    """A marker may not sit on a slot footprint (+CHECK_MARKER_SLOT), a pad, or a street or spur
    strip. streetOnly slots count: their pad is real."""
    messages = []
    strip = site.width / 2 + CHECK_STRIP_EXTRA
    for slot in site.era.slots:
        poly = site.marker_polys[slot["id"]]
        label = f"{slot['id']} marker"
        for other_id, footprint in site.slot_polys.items():
            if other_id in site.street_only:
                continue  # a nominal rect (INTERFACES "Review rulings", wave 1c)
            d = gap(poly, footprint)
            if d < CHECK_MARKER_SLOT - EPS:
                messages.append(f"{label}: {d:.2f} from the {other_id} footprint (need {CHECK_MARKER_SLOT})")
        for other_id, pad in site.pad_polys.items():
            if gap(poly, pad) <= 0:
                messages.append(f"{label}: overlaps the {other_id} pad")
        for polyline, _segment, a, b in site.street_segments:
            d = segment_gap(a, b, poly)
            if d < strip - EPS:
                messages.append(f"{label}: {d:.2f} from street {polyline + 1} (strip {strip:g})")
        for other_id, a, b in site.spur_segments:
            d = segment_gap(a, b, poly)
            if d < strip - EPS:
                messages.append(f"{label}: {d:.2f} from the {other_id} path (strip {strip:g})")
    return messages


def parcel_messages(site, plan, parcels):
    """Placement, address and row rules for every parcel, then the order and the counts."""
    messages = []
    strip = site.width / 2 + CHECK_STRIP_EXTRA
    front_line = plan["parcels"]["frontSetback"]
    polys = []
    for index, parcel in enumerate(parcels, start=1):
        label = f"parcel {index} ({number(parcel['x'])}, {number(parcel['z'])})"
        size = site.sizes.get(parcel["size"])
        if size is None:
            messages.append(f"{label}: size {parcel['size']!r} is not one of {list(site.sizes)}")
            polys.append(None)
            continue
        poly = rect((parcel["x"], parcel["z"]), size, parcel["rotationY"])
        polys.append(poly)
        for corner in poly:
            if abs(corner[0]) > site.era.half_x - CHECK_EDGE + EPS or abs(corner[1]) > site.era.half_z - CHECK_EDGE + EPS:
                messages.append(f"{label}: within {CHECK_EDGE} of the plot edge")
                break
        for slot_id, footprint in site.slot_polys.items():
            if slot_id in site.street_only:
                continue  # no model stands there (INTERFACES "Review rulings", wave 1c)
            d = gap(poly, footprint)
            if d < CHECK_SLOT - EPS:
                messages.append(f"{label}: {d:.2f} from the {slot_id} footprint (need {CHECK_SLOT})")
        for slot_id, pad in site.pad_polys.items():
            d = gap(poly, pad)
            if d < CHECK_PAD - EPS:
                messages.append(f"{label}: {d:.2f} from the {slot_id} pad (need {CHECK_PAD})")
        for slot_id, marker in site.marker_polys.items():
            d = gap(poly, marker)
            if d < CHECK_MARKER_SLOT - EPS:
                messages.append(f"{label}: {d:.2f} from the {slot_id} marker (need {CHECK_MARKER_SLOT})")
        for j, plaza in enumerate(site.plaza_polys, start=1):
            d = gap(poly, plaza)
            if d < CHECK_PLAZA - EPS:
                messages.append(f"{label}: {d:.2f} from plaza {j} (need {CHECK_PLAZA})")
        if gap(poly, site.era.sign_poly) <= 0:
            messages.append(f"{label}: overlaps the Sign")
        back_row = parcel["row"] != 1
        street_need = site.walker_street if back_row else strip
        spur_need = site.walker_spur if back_row else strip
        for polyline, _segment, a, b in site.street_segments:
            d = segment_gap(a, b, poly)
            if d < street_need - EPS:
                messages.append(f"{label}: {d:.2f} from street {polyline + 1} {streetplan.fmt(a)}->{streetplan.fmt(b)} (need {street_need:g})")
        for slot_id, a, b in site.spur_segments:
            d = segment_gap(a, b, poly)
            if d < spur_need - EPS:
                messages.append(f"{label}: {d:.2f} from the {slot_id} path (need {spur_need:g})")
        stretch = site.stretch_by_id.get(parcel["stretch"])
        if stretch is None:
            messages.append(f"{label}: stretch {parcel['stretch']!r} is not a piece of this network")
            continue
        if stretch not in site.drawn:
            messages.append(f"{label}: stretch {parcel['stretch']} is never drawn, so it can never develop")
        st = site.network.stretches[stretch]
        row = parcel["row"]
        if row == 1:
            if parcel["front"] != 0:
                messages.append(f"{label}: row 1 must have front 0")
            if not -EPS <= parcel["along"] <= st["length"] + EPS:
                messages.append(f"{label}: along {number(parcel['along'])} outside [0, {st['length']:.2f}] of {parcel['stretch']}")
            fc = front_centre(parcel["x"], parcel["z"], parcel["rotationY"], size[1])
            distance, foot = streetplan.point_segment_distance(fc, st["a"], st["b"])
            if abs(distance - front_line) > CHECK_FRONT_SLACK + EPS:
                messages.append(f"{label}: front {distance:.2f} from {parcel['stretch']}, not within {CHECK_FRONT_SLACK} of the setback line {front_line:g}")
            if abs(math.dist(st["a"], foot) - parcel["along"]) > 0.05:
                messages.append(f"{label}: along {number(parcel['along'])} is not the foot of its front ({math.dist(st['a'], foot):.2f})")
            face = streetplan.facing(parcel["rotationY"])
            toward = (foot[0] - fc[0], foot[1] - fc[1])
            if face[0] * toward[0] + face[1] * toward[1] < -EPS:
                messages.append(f"{label}: faces away from {parcel['stretch']}")
        elif isinstance(row, int) and 2 <= row <= MAX_ROW:
            front = parcel["front"]
            if not (isinstance(front, int) and 1 <= front < index and parcels[front - 1]["row"] == row - 1):
                messages.append(f"{label}: front {front!r} is not an earlier row-{row - 1} parcel")
                continue
            ahead = parcels[front - 1]
            if ahead["stretch"] != parcel["stretch"] or abs(ahead["along"] - parcel["along"]) > EPS:
                messages.append(f"{label}: must repeat parcel {front}'s stretch and along")
            # Directly behind: the same facing, the centre behind the front's, within its width.
            face = streetplan.facing(ahead["rotationY"])
            dx, dz = parcel["x"] - ahead["x"], parcel["z"] - ahead["z"]
            lateral = abs(-face[1] * dx + face[0] * dz)
            if face[0] * dx + face[1] * dz >= 0 or lateral > site.sizes[ahead["size"]][0] / 2 + EPS:
                messages.append(f"{label}: is not directly behind parcel {front}")
            if abs((parcel["rotationY"] - ahead["rotationY"] + 180.0) % 360.0 - 180.0) > EPS:
                messages.append(f"{label}: does not face the same street as parcel {front}")
        else:
            messages.append(f"{label}: row {row!r} is not 1 to {MAX_ROW}")
    for i, p in enumerate(polys):
        if p is None:
            continue
        box = box_of(p)
        for j in range(i + 1, len(polys)):
            q = polys[j]
            if q is not None and not boxes_apart(box, box_of(q), 0.0) and gap(p, q) <= 0:
                messages.append(f"parcel {i + 1} overlaps parcel {j + 1}")
    # Order (INTERFACES "Wave 1c"): row 1, nearest the entrance first; then row 2 and row 3, each
    # in the order of its fronts.
    rows = [p["row"] for p in parcels]
    if rows != sorted(rows):
        messages.append("parcels: rows are not listed row 1, then row 2, then row 3")
    first = [p for p in parcels if p["row"] == 1]
    reach = [math.dist(site.entrance, (p["x"], p["z"])) for p in first]
    if any(b < a - EPS for a, b in zip(reach, reach[1:])):
        messages.append("parcels: row 1 is not ordered nearest the entrance first")
    for row in range(2, MAX_ROW + 1):
        fronts = [p["front"] for p in parcels if p["row"] == row]
        if fronts != sorted(fronts):
            messages.append(f"parcels: row {row} is not in the order of its fronts")
    if all(poly is not None for poly in polys) and all(p["stretch"] in site.stretch_by_id for p in parcels):
        need_level = plan["parcels"].get("minLevel", 1)
        for index, level in enumerate(full_build_levels(site, parcels), start=1):
            if level < need_level:
                what = "stays wild" if level == 0 else f"only reaches level {level}"
                messages.append(f"parcel {index}: {what} even with the whole era owned (need {need_level})")
    need = plan.get("require") or {}
    medium = sum(1 for p in parcels if p["size"] == "medium")
    if len(parcels) < need.get("parcels", 0):
        messages.append(f"parcels: {len(parcels)}, need at least {need['parcels']}")
    if medium < need.get("medium", 0):
        messages.append(f"parcels: {medium} medium, need at least {need['medium']}")
    cap = site.city.get("budget", {}).get("parcels")
    if isinstance(cap, (int, float)) and len(parcels) > cap:
        messages.append(f"parcels: {len(parcels)}, more than budget.parcels {cap:g} -- near plots never draw the tail")
    return messages


def tree_messages(site, plan, doc):
    """INTERFACES "Wave 1c": Town trees."""
    messages = []
    trees = doc.get("trees", [])
    parcels = doc.get("parcels", [])
    config = site.config.get("townTrees") or {}
    props = config.get("props") or []
    polys = [rect((p["x"], p["z"]), site.sizes.get(p["size"], (0, 0)), p["rotationY"]) for p in parcels]
    levels = full_build_levels(site, parcels) if parcels else []
    solids = [(f"parcel {i}", poly) for i, poly in enumerate(polys, start=1)]
    solids += [(f"the {slot_id} footprint", poly) for slot_id, poly in site.slot_polys.items()]
    solids += [(f"the {slot_id} pad", poly) for slot_id, poly in site.pad_polys.items()]
    solids += [(f"the {slot_id} marker", poly) for slot_id, poly in site.marker_polys.items()]
    solids += [(f"lamp {i}", poly) for i, poly in enumerate(site.lamps, start=1)]
    boxes = [(label, poly, box_of(poly)) for label, poly in solids]
    lanes = [(f"street {pl + 1}", a, b) for pl, _seg, a, b in site.street_segments]
    lanes += [(f"the {slot_id} path", a, b) for slot_id, a, b in site.spur_segments]
    planted = 0
    for index, tree in enumerate(trees, start=1):
        label = f"tree {index} ({number(tree['x'])}, {number(tree['z'])})"
        point = (tree["x"], tree["z"])
        variant = tree.get("variant")
        if not (isinstance(variant, int) and 1 <= variant <= len(props)):
            messages.append(f"{label}: variant {variant!r} is not 1 to {len(props)} (townTrees.props)")
        if not tree.get("scale", 0) > 0:
            messages.append(f"{label}: scale must be positive")
        anchor = tree.get("anchor")
        if anchor not in ANCHORS:
            messages.append(f"{label}: anchor {anchor!r} is not one of {ANCHORS}")
        elif anchor == "stretch":
            if "parcel" in tree:
                messages.append(f"{label}: a stretch tree names a parcel")
            stretch = site.stretch_by_id.get(tree.get("stretch"))
            if stretch is None:
                messages.append(f"{label}: stretch {tree.get('stretch')!r} is not a piece of this network")
            elif stretch not in site.drawn:
                messages.append(f"{label}: stretch {tree['stretch']} is never drawn, so the tree is never planted")
        else:
            if "stretch" in tree:
                messages.append(f"{label}: a parcel tree names a stretch")
            parcel = tree.get("parcel")
            if not (isinstance(parcel, int) and 1 <= parcel <= len(parcels)):
                messages.append(f"{label}: parcel {parcel!r} is not a parcel index")
            else:
                if levels[parcel - 1] < BUILT_LEVEL:
                    messages.append(f"{label}: parcel {parcel} never becomes a house, so the tree is never planted")
                nearest = nearest_parcel(point, [{"poly": poly} for poly in polys])
                if nearest != parcel and point_gap(point, polys[nearest - 1]) < point_gap(point, polys[parcel - 1]) - EPS:
                    messages.append(f"{label}: anchored to parcel {parcel}, but parcel {nearest} is nearer")
        if planted_at_full(site, tree, levels):
            planted += 1
        edge = CHECK_TREE_EDGE
        if abs(point[0]) > site.era.half_x - edge + EPS or abs(point[1]) > site.era.half_z - edge + EPS:
            messages.append(f"{label}: within {edge} of the plot edge")
        for what, poly, box in boxes:
            if not point_box_apart(point, box, CHECK_TREE) and point_gap(point, poly) < CHECK_TREE - EPS:
                messages.append(f"{label}: {point_gap(point, poly):.2f} from {what} (need {CHECK_TREE})")
        for what, a, b in lanes:
            d, _ = streetplan.point_segment_distance(point, a, b)
            if d < site.lane_clear - EPS:
                messages.append(f"{label}: {d:.2f} from {what}, on its walker or cart lane (need {site.lane_clear:g})")
        for j in range(index, len(trees)):
            other = trees[j]
            if math.dist(point, (other["x"], other["z"])) < CHECK_TREE_SPACING - EPS:
                messages.append(f"{label}: within {CHECK_TREE_SPACING} of tree {j + 1}")
    cap = site.city.get("budget", {}).get("townTrees")
    if isinstance(cap, (int, float)) and len(trees) > cap:
        messages.append(f"trees: {len(trees)}, more than budget.townTrees {cap:g} -- near plots never draw the tail")
    need = (plan.get("require") or {}).get("trees", 0)
    if planted < need:
        messages.append(f"trees: {planted} planted with the whole era owned, need at least {need}")
    return messages


def wild_messages(site, plan, doc):
    messages = []
    budget = site.city.get("budget", {})
    wild = doc.get("wild", [])
    near_cap = budget.get("wild")
    if isinstance(near_cap, (int, float)) and len(wild) > near_cap:
        messages.append(f"wild: {len(wild)} entries, more than budget.wild {near_cap:g} -- near plots never draw the tail")
    far_cap = budget.get("wildFar")
    clumps = [item for item in wild if item["kind"] == "clump"]
    if isinstance(far_cap, (int, float)):
        shown = clumps[: int(far_cap)]
        missing = sum(1 for item in clumps[int(far_cap) :] if item["skirt"])
        if missing:
            messages.append(f"wild: {missing} skirt clump(s) fall outside the first budget.wildFar {far_cap:g} clumps, so far plots never show them")
        if any(not a["skirt"] and b["skirt"] for a, b in zip(shown, shown[1:])):
            messages.append("wild: an on-plot clump comes before a skirt clump")
    names = site.config["wild"]
    singles_allowed = set(plan["wild"]["singles"]["trees"]) | set(plan["wild"]["singles"]["meadow"])
    half = site.era.half_x
    offset = plan["wild"]["clumps"]["quarterOffset"]
    for index, item in enumerate(wild, start=1):
        label = f"wild {index} ({number(item['x'])}, {number(item['z'])})"
        if item["kind"] not in KINDS:
            messages.append(f"{label}: kind {item['kind']!r} is not one of {KINDS}")
            continue
        inside = abs(item["x"]) <= half and abs(item["z"]) <= half
        if item["skirt"] == inside:
            messages.append(f"{label}: skirt {item['skirt']} but it stands {'on' if inside else 'off'} the plot base")
        if item["kind"] == "clump":
            if not 1 <= item["variant"] <= len(names["clumps"]) or len(names["quarters"]) < item["variant"]:
                messages.append(f"{label}: variant {item['variant']} has no clump/quarter prop")
            expected = quad_centres(item["x"], item["z"], item["rotationY"], item["scale"], offset)
            if len(item["quads"]) != QUARTERS or any(math.dist(e, q) > EPS for e, q in zip(expected, item["quads"])):
                messages.append(f"{label}: quads do not match the contract's rotation of ({offset:g}, {offset:g}) x scale")
        elif item["prop"] not in singles_allowed:
            messages.append(f"{label}: single prop {item['prop']!r} is not in the plan's single pools")
    return messages


def check_document(era_name, doc, compare_committed=True, city=None, era=None, network=None):
    """Every rule of INTERFACES "Tools" (`fabric.py check`) and "Wave 1c", plus the layout minimums
    the plan asks for. Returns violation strings; empty means green."""
    site = Site(era_name, city, era, network)
    plan = load_plan(era_name)
    messages = []
    if compare_committed:
        path = out_path(era_name)
        fresh = render(build_document(era_name, site.city, site.era, site.network))
        if not path.exists():
            messages.append(f"{path.relative_to(REPO_ROOT)} is missing; run `py tools/fabric.py build {era_name}`")
        elif path.read_text(encoding="utf-8") != fresh:
            messages.append(f"{path.relative_to(REPO_ROOT)} differs from a fresh build; run `py tools/fabric.py build {era_name}`")
        doc = json.loads(path.read_text(encoding="utf-8")) if path.exists() else doc
    messages += parcel_messages(site, plan, doc.get("parcels", []))
    if site.marker_offset is not None:
        messages += marker_messages(site)
    messages += tree_messages(site, plan, doc)
    messages += wild_messages(site, plan, doc)
    return messages


# --------------------------------------------------------------------------------------------
# Driver
# --------------------------------------------------------------------------------------------


def tree_kind(tree):
    """Each placement rule writes one variant/anchor pair (the plan's `variants`), so the kind
    reads back from the data: yard trees are the parcel-anchored ones."""
    if tree.get("anchor") == "parcel":
        return "yard"
    return {3: "street", 2: "orchard"}.get(tree.get("variant"), "green")


def summary(era_name, doc):
    parcels, trees, wild = doc["parcels"], doc.get("trees", []), doc["wild"]
    by_row = {row: sum(1 for p in parcels if p["row"] == row) for row in range(1, MAX_ROW + 1)}
    medium = sum(1 for p in parcels if p["size"] == "medium")
    clumps = [w for w in wild if w["kind"] == "clump"]
    singles = [w for w in wild if w["kind"] == "single"]
    kinds = {}
    for tree in trees:
        kinds[tree_kind(tree)] = kinds.get(tree_kind(tree), 0) + 1
    return (
        f"{era_name}: {len(parcels)} parcels (rows {by_row[1]}/{by_row[2]}/{by_row[3]}; "
        f"{medium} medium, {len(parcels) - medium} small); {len(trees)} town trees "
        f"({', '.join(f'{k} {v}' for k, v in sorted(kinds.items()))}); wild {len(wild)}: "
        f"{len(clumps)} clumps ({sum(1 for c in clumps if not c['skirt'])} on the plot, "
        f"{sum(1 for c in clumps if c['skirt'])} skirt), {len(singles)} singles "
        f"({sum(1 for s in singles if not s['skirt'])} on the plot, {sum(1 for s in singles if s['skirt'])} skirt)"
    )


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=("build", "check"))
    parser.add_argument("era")
    args = parser.parse_args(argv)
    if args.command == "build":
        doc = build_document(args.era)
        path = out_path(args.era)
        path.parent.mkdir(parents=True, exist_ok=True)
        with open(path, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(render(doc))
        print(f"wrote {path.relative_to(REPO_ROOT)}")
        print(summary(args.era, doc))
        return 0
    path = out_path(args.era)
    doc = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {"parcels": [], "trees": [], "wild": []}
    messages = check_document(args.era, doc)
    print(summary(args.era, doc))
    for message in messages:
        print(f"   VIOLATION: {message}")
    print(f"{len(messages)} violations")
    return 1 if messages else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
