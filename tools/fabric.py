#!/usr/bin/env python
"""The city fabric of a growth layout: the parcels a town grows on, the trees it plants and the wild
land it grows out of (docs/INTERFACES.md "M12 contracts": "Fabric data" and "Tools"; "Wave 1c";
"Wave 2.0" for the parked carts).

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
square on: terraces of narrow lots on the terrace streets (the high street and the square's lane),
cottages mostly medium elsewhere, then a fill of every hole a lot still fits. Rows 2 and 3 are
infill anywhere in the block interior behind the frontage; each takes as its front the nearest
earlier lot of the row in front on the same side of the same street and repeats its address.
CityFabric keeps each back row a `rowLag` behind its front, so a lot that would never become a house
is not laid. Lots keep clear of each landmark's harvested extents (INTERFACES "Wave 1c, round 2").

Town trees. Street trees in frontage no lot took (anchored to their stretch), green and orchard trees
round the civic and farm landmarks and the tree slot's green (anchored to the landmark's approach
stretch), yard trees behind the last row of houses (anchored to the nearest parcel). Every one keeps
off the walker and car lanes and clear of parcels, slots, pads, markers and lamps.

Parked carts. Laid last, from their own random stream, in what every other list left, so adding or
tuning them never moves a parcel, a tree, a flower, a banner or the woods: kerb carts in frontage no
lot took (anchored to their stretch, parallel to it), yard carts beside a lot of the plan's cart
districts (anchored to that parcel). A cart never stands in woods its own anchor leaves standing.

Wild. The plan's `wild.pattern` picks what the town grows out of. Woods (the default): merged
clumps laid by blue noise (variable spacing, any turn, varied scale) wherever the density plan says
woods, singles and round trees on a finer blue noise where the woods thin out and round a few small
glades, a low sparse band at the front so the camera always sees the next pad, and a skirt past the
side and back edges that tapers toward the hub corners. Fields ("fields"): a fenced field per cell of
a square grid, crops and pasture chosen by low-frequency noise so they gather into larger fields,
hay and trees on the pasture, a telegraph line, and a landscape band past the edges with the plan's
landmarks. Either way a clump is four copies of one quarter design, and `quads` holds each
quarter's centre by the contract's rotation mapping.

The JSON is deterministic: string-seeded random streams, fixed iteration order, numbers rounded
to 0.01 and written by a fixed formatter, so two builds are byte-identical and `check` can demand
that the committed file equals a fresh build.
"""

from __future__ import annotations

import argparse
import itertools
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
ASSETS_PATH = REPO_ROOT / "src" / "shared" / "Config" / "Assets.json"  # read only

FORMAT_VERSION = 1
DECIMALS = 2

# Contract check values (INTERFACES "M12 contracts" -> "Tools", "Review amendments", "Wave 1c"),
# not tunables: a parcel keeps this much daylight from each kind of solid, a row-1 parcel's front
# stays this close to its setback line, and a town tree keeps a stud from everything built.
CHECK_SLOT = 1.0  # a declared footprint (a landmark without harvested extents)
CHECK_LANDMARK = 0.5  # a landmark's harvested extents, the union of its stages (wave 1c round 2)
CHECK_SIZE_GAP = 0.6  # between lots of different sizes; terraced narrow lots may touch
CHECK_PAD = 0.5
CHECK_PLAZA = 1.0
CHECK_EDGE = 1.0
CHECK_STRIP_EXTRA = 1.0  # a street or spur strip is road width / 2 + this
CHECK_FRONT_SLACK = 2.0
CHECK_MARKER_SLOT = 0.5  # the next-pad marker's daylight to any slot footprint (and any parcel)
CHECK_TREE = 1.0  # a town tree's daylight to a parcel, slot footprint, pad, marker or lamp
CHECK_TREE_EDGE = 1.0
CHECK_TREE_SPACING = 2.0  # two trunks closer than this read as one tree
CHECK_OWN_LOT = 0.6  # a planter may lean this far into its own house's front garden
CHECK_ITEM_SPACING = 0.8  # two flower or banner entries closer than this stand in each other
CHECK_BUNTING_TREE = 1.0  # no tree trunk this close under a bunting string
# A parked cart (INTERFACES "Wave 2.0"): its body's daylight to every parcel, landmark, pad, marker,
# lamp, the Sign and every entry of the other layers; to the plot edge; between two carts; and how
# widely the carts spread. Its reach off streets and spurs is the walkers' (Site.walker_*).
CHECK_CART = 0.5
CHECK_CART_EDGE = 1.0
CHECK_CART_SPACING = 12.0
CHECK_CART_STREETS = 3
CHECK_CART_PARALLEL = 0.02  # |sin| between a kerb cart's length and its stretch's chord
CHECK_CART_MARGINS = {
    "lot": CHECK_CART,
    "solid": CHECK_CART,
    "lamp": CHECK_CART,
    "tree": CHECK_CART,
    "item": CHECK_CART,
    "edge": CHECK_CART_EDGE,
    "wood": 0.0,  # "in the woods" is touching a wood's clearing disc
}
MARKER_SIZE = 2.0  # the marker prop's ground square, the contract's cap
BUILT_LEVEL = 2  # a parcel's house stands from level 2 (a parcel-anchored tree needs it)
MAX_ROW = 3
# Two derivations of the same rounded number agree to this.
EPS = 0.02
COLLINEAR = 1e-6  # |sin| between two legs that count as one straight run
QUARTER_TURN = 90.0
HALF_TURN = 180.0
TOP_TIER = 5  # GrowthTier at the end of an era (CityGrowth thresholds has five entries)
QUARTERS = 4
SIZES = ("small", "medium", "narrow")
KINDS = ("clump", "single")
FIELDS = "fields"  # the plan's `wild.pattern` for farmland on a grid; absent means woods
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


def load_assets():
    try:
        return json.loads(ASSETS_PATH.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def model_extents(model):
    """Scatter.modelExtents (tools/cityfabric.py mirrors it): XZ bounds of every harvested part of
    every stage in the model frame, offsets negated (the glTF import's turn); None without a harvest."""
    if not isinstance(model, dict) or not isinstance(model.get("stages"), list):
        return None
    extents = None
    for stage in model["stages"]:
        for part in (stage or {}).get("parts") or []:
            size, offset, mesh = part.get("size"), part.get("offset"), part.get("meshId")
            if not (isinstance(size, list) and isinstance(offset, list) and len(size) == 3 and len(offset) == 3):
                continue
            if not isinstance(mesh, (int, float)) or mesh <= 0:
                continue
            cx, cz = -offset[0], -offset[2]
            box = (cx - size[0] / 2, cx + size[0] / 2, cz - size[2] / 2, cz + size[2] / 2)
            extents = box if extents is None else (min(extents[0], box[0]), max(extents[1], box[1]), min(extents[2], box[2]), max(extents[3], box[3]))
    return extents


def extents_poly(origin, rotation, extents):
    """Fabric.footprintRect as a polygon: the extents' middle carried into the plot, the slot's turn."""
    mid = rotate((extents[0] + extents[1]) / 2, (extents[2] + extents[3]) / 2, rotation)
    return streetplan.square((origin[0] + mid[0], origin[1] + mid[1]), extents[1] - extents[0], extents[3] - extents[2], rotation)


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
        self.sizes = {name: tuple(float(v) for v in self.config["sizes"][name]) for name in SIZES if name in self.config["sizes"]}
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
        # What a lot keeps clear of (INTERFACES "Wave 1c, round 2"): each landmark's harvested
        # extents, the union over its stages, as Scatter measures them; its declared footprint only
        # when it has no harvest. A streetOnly slot spawns nothing, so it reserves no land.
        self.street_only = {slot["id"] for slot in self.era.config["slots"] if slot.get("streetOnly")}
        self.landmark_polys = {}
        models = {slot["id"]: slot.get("modelName") for slot in self.era.config["slots"]}
        assets = load_assets()
        harvested = (assets.get("eras") or {}).get(era_name) or {}
        self.props = (assets.get("props") or {}).get(era_name) or {}
        for slot in self.era.slots:
            if slot["id"] in self.street_only:
                continue
            extents = model_extents(harvested.get(models.get(slot["id"])))
            if extents is None:
                self.landmark_polys[slot["id"]] = (slot["footprint"], False)
            else:
                self.landmark_polys[slot["id"]] = (extents_poly(slot["position"], slot["rotation"], extents), True)
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

    def solid_boxes(self, rules):
        """(polygon, its bounding box, the daylight a parcel keeps from it) for every solid."""
        key = (rules["slot"], rules["landmark"], rules["pad"], rules["plaza"], rules["sign"], rules["marker"])
        if getattr(self, "_solids_key", None) != key:
            solids = [(poly, rules["landmark"] if measured else rules["slot"]) for poly, measured in self.landmark_polys.values()]
            solids += [(poly, rules["pad"]) for poly in self.pad_polys.values()]
            solids += [(poly, rules["plaza"]) for poly in self.plaza_polys]
            solids += [(poly, rules["marker"]) for poly in self.marker_polys.values()]
            solids.append((self.era.sign_poly, rules["sign"]))
            self._solids = [(poly, box_of(poly), margin) for poly, margin in solids]
            self._solids_key = key
        return self._solids

    def prop_extents(self, prop):
        """A dressing prop's harvested ground extents in its own frame, or None before its harvest."""
        return model_extents(self.props.get(prop))

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


def lot_gap(rules, size, other):
    """Terraced narrow lots stand almost touching; any other pair keeps the ordinary gap (and lots of
    different sizes at least the contract's 0.6)."""
    return rules["terraceGap"] if size == other == "narrow" else rules["gap"]


def parcel_clear(site, poly, rules, own_segments, placed, size=None):
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
        need = lot_gap(rules, size, other["size"])
        if not boxes_apart(box, other["box"], need) and gap(poly, other["poly"]) < need - EPS:
            return False
    return True


def make_parcel(site, size, centre, rotation, stretch, along, row, front, run=None, side=None):
    x, z = rounded(centre[0]), rounded(centre[1])
    rotation = rounded(norm_degrees(rotation))
    poly = rect((x, z), site.sizes[size], rotation)
    return {
        "x": x,
        "z": z,
        "rotationY": rotation,
        "size": size,
        "stretch": site.ids[stretch] if stretch is not None else None,
        "along": rounded(along),
        "row": row,
        "front": front,
        "poly": poly,
        "box": box_of(poly),
        # generator bookkeeping (never written): the street side a lot belongs to
        "polyline": run["polyline"] if run is not None else None,
        "side": street_side(site, run["polyline"], (x, z)) if run is not None else side,
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


def street_side(site, polyline, point):
    """Which side of its street a lot stands on: the sign of the turn from the nearest leg of the
    polyline to the point (+1 left of the street's travel, -1 right)."""
    best, best_d = None, math.inf
    for a, b in streetplan.polyline_segments(site.era.streets[polyline]):
        d, _ = streetplan.point_segment_distance(point, a, b)
        if d < best_d:
            best, best_d = (a, b), d
    a, b = best
    cross = (b[0] - a[0]) * (point[1] - a[1]) - (b[1] - a[1]) * (point[0] - a[0])
    return 1 if cross >= 0 else -1


def parcel_polyline(parcel):
    """The street a parcel's address stretch belongs to (`L<polyline>_<rank>`, 1-based)."""
    return int(parcel["stretch"][1:].split("_")[0]) - 1


def walk_run(site, rules, run, side, sizes_for, rng, jitter, placed):
    """Lay parcels along one side of a straight run, fronts near the setback line, from its start.
    A small or medium lot stands a little back from the line and a few degrees off square (the
    plan's jitter, its own random stream), so a row of cottages reads as grown; narrow lots stand
    square on the line, a terrace almost touching its neighbours."""
    a, b, d = run["a"], run["b"], run["d"]
    length = math.dist(a, b)
    own = {(run["polyline"], segment) for segment, _, _ in run["segments"]}
    front = rules["frontSetback"]
    n = (-d[1] * side, d[0] * side)
    square_on = facing_rot((-n[0], -n[1]))
    s = rules["endMargin"]
    while s < length - rules["endMargin"]:
        accepted = None
        for size in sizes_for(rng, run):
            if size not in site.sizes:
                continue
            w, depth = site.sizes[size]
            mid = s + w / 2
            back = jitter.uniform(0.0, rules["setbackJitter"])
            turn = jitter.uniform(-rules["turnJitter"], rules["turnJitter"])
            if size == "narrow":
                back, turn = 0.0, 0.0
            if mid > length:
                continue  # the front centre must project onto its own stretch
            where = locate(site, run, mid)
            if where is None or where[0] not in site.drawn:
                continue
            stretch, along = where
            reach = front + back + depth / 2
            centre = (a[0] + d[0] * mid + n[0] * reach, a[1] + d[1] * mid + n[1] * reach)
            candidate = make_parcel(site, size, centre, square_on + turn, stretch, along, 1, 0, run, side)
            # `along` is the foot of the perpendicular from the (turned) front centre, per contract.
            fc = front_centre(candidate["x"], candidate["z"], candidate["rotationY"], depth)
            st = site.network.stretches[stretch]
            _, foot = streetplan.point_segment_distance(fc, st["a"], st["b"])
            candidate["along"] = rounded(math.dist(st["a"], foot))
            if parcel_clear(site, candidate["poly"], rules, own, placed, size):
                accepted = candidate
                break
        if accepted is None:
            s += rules["walkStep"]
            continue
        placed.append(accepted)
        s += site.sizes[accepted["size"]][0] + (rules["terraceGap"] if accepted["size"] == "narrow" else rules["gap"])


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


def nearest_front(parcels, candidate, row):
    """INTERFACES "Wave 1c, round 2": the nearest earlier parcel of row - 1 on the same side of the
    same street (1-based index), or None. Ties go to the lower index."""
    best, best_d = None, math.inf
    for index, other in enumerate(parcels, start=1):
        if other["row"] != row - 1 or other["polyline"] != candidate["polyline"] or other["side"] != candidate["side"]:
            continue
        d = math.dist((other["x"], other["z"]), (candidate["x"], candidate["z"]))
        if d < best_d - 1e-9:
            best, best_d = index, d
    return best


def infill(site, rules, parcels, row):
    """Back-row lots anywhere in the block interior behind a street's frontage (INTERFACES "Wave 1c,
    round 2"): a raster over each run side, front edges within the row's band of studs off the
    chord, facing the street square on, each laid where it keeps every clearance (back rows keep a
    walker's reach off every street and spur). Fronts and addresses are set afterwards."""
    band = rules["infill"]["rows"][str(row)]
    step = rules["infill"]["step"]
    sizes = [size for size in rules["infill"]["sizes"] if size in site.sizes]
    added = []
    for run in street_runs(site):
        a, d = run["a"], run["d"]
        length = math.dist(a, run["b"])
        for side in (1, -1):
            n = (-d[1] * side, d[0] * side)
            square_on = facing_rot((-n[0], -n[1]))
            depth_edge = band[0]
            while depth_edge <= band[1] + 1e-9:
                s = rules["endMargin"]
                while s < length - rules["endMargin"]:
                    for size in sizes:
                        w, depth = site.sizes[size]
                        mid = s + w / 2
                        if mid > length:
                            continue
                        where = locate(site, run, mid)
                        if where is None or where[0] not in site.drawn:
                            continue
                        reach = depth_edge + depth / 2
                        centre = (a[0] + d[0] * mid + n[0] * reach, a[1] + d[1] * mid + n[1] * reach)
                        candidate = make_parcel(site, size, centre, square_on, where[0], where[1], row, 0, run, side)
                        if parcel_clear(site, candidate["poly"], rules, set(), parcels + added, size):
                            added.append(candidate)
                            s += w - step
                            break
                    s += step
                depth_edge += step
    return added


def generate_parcels(site, plan):
    """Parcels in data order: row 1 by distance from the entrance, then row 2 and row 3, each in the
    order of its fronts (INTERFACES "Wave 1c": Order)."""
    rules = plan["parcels"]
    rng = random.Random(f"{plan['seed']}:parcels")
    jitter = random.Random(f"{plan['seed']}:jitter")
    terrace = set(rules["terraceStreets"])

    def first_pass(stream, run):
        if run["polyline"] + 1 in terrace:
            return ("narrow",)
        return ("medium", "small") if stream.random() < rules["mediumShare"] else ("small", "medium")

    def fill_pass(_stream, run):
        return ("narrow",) if run["polyline"] + 1 in terrace else ("small", "narrow")

    # Frontage first: terraces of narrow lots on the terrace streets, cottages mostly medium
    # elsewhere; then a second walk fills every hole a lot still fits.
    placed = []
    for sizes_for in (first_pass, fill_pass):
        for run in street_runs(site):
            for side in (1, -1):
                walk_run(site, rules, run, side, sizes_for, rng, jitter, placed)
    min_level = rules["minLevel"]
    parcels = settle_first_row(site, placed, min_level)
    parcels.sort(key=lambda parcel: entrance_order(site, parcel))
    for row in range(2, min(rules["rows"], MAX_ROW) + 1):
        kept = []
        for candidate in infill(site, rules, parcels, row):
            front = nearest_front(parcels, candidate, row)
            if front is None:
                continue
            ahead = parcels[front - 1]
            candidate["front"], candidate["stretch"], candidate["along"] = front, ahead["stretch"], ahead["along"]
            kept.append(candidate)
        # A back row keeps `rowLag` levels behind its front; one that would stay a building site or
        # wild land once the era is finished is not laid at all.
        kept.sort(key=lambda parcel: (parcel["front"],) + entrance_order(site, parcel))
        levels = full_build_levels(site, parcels + kept)[len(parcels) :]
        parcels += [parcel for parcel, level in zip(kept, levels) if level >= min_level]
    return parcels


def full_build_levels(site, parcels):
    """Each parcel's level once the whole era is owned (see full_build_states)."""
    return full_build_states(site, parcels)[0]


def full_build_states(site, parcels):
    """Each parcel's level and district once the whole era is owned (tier 5, every stretch drawn):
    the contract's Develop, steps 1-8 with wave 1c's rows (INTERFACES "CityFabric.Develop", "Rows"),
    for exactly that one state. Levels only rise as slots are bought and the tier climbs, so this is
    the most a parcel ever becomes, and the district is the one its finished building shows.
    `front` is resolved by position in `parcels`. Returns (levels, districts)."""
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
            landmarks.append((slot["id"], node, district))

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

    per_node = {node: shortest({node: 0.0}) for _, node, _ in landmarks}
    levels, districts = [], []
    for parcel in parcels:
        st = lengths.get(parcel["stretch"])
        influence, pulled = 0.0, False
        governor, strongest = None, 0.0
        for _, node, district in landmarks:
            if st is None:
                break
            share = max(0.0, 1.0 - reach(per_node[node], st, parcel["along"]) / pull["radius"])
            if share > 0:
                influence += share
                pulled = True
                # The landmarks come in slot-id order, so `>=` gives a tie to the larger id, as
                # the contract's step 6 does.
                if share >= strongest:
                    governor, strongest = district, share
        score = influence + pull["tierTerm"] * tier if pulled else 0.0
        level = min(sum(1 for threshold in pull["thresholds"] if score >= threshold), tier + pull["levelsOverTier"])
        if parcel["size"] == "small":
            level = min(level, pull["smallMaxLevel"])
        levels.append(level if st is not None else 0)
        districts.append(governor)
    accepted, grew = set(), True
    while grew:
        grew = False
        sources = {node: 0.0 for _, node, _ in landmarks}
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
            districts[index] = districts[front] if 0 <= front < index else None
    return levels, districts


# --------------------------------------------------------------------------------------------
# City upgrade layers (INTERFACES "Wave 1c, round 3"): trees, flowers, banners; "Wave 2.0": carts
# --------------------------------------------------------------------------------------------

CARTS = "carts"
LAYERS = ("trees", "flowers", "banners", CARTS)


def upgrade_config(site, layer):
    return ((site.config.get("upgrades") or {}).get(layer)) or {}


def entry_order(site, entry):
    return (round(math.dist(site.entrance, (entry["x"], entry["z"])), DECIMALS), entry["z"], entry["x"])


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


def generate_trees(site, plan, parcels, levels):
    """The town trees (INTERFACES "Wave 1c": Town trees), in data order: nearest the entrance first."""
    cfg = plan["trees"]
    layer = upgrade_config(site, "trees")
    if not layer.get("props"):
        return []
    variants = cfg["variants"]
    rng = random.Random(f"{plan['seed']}:trees")
    spots = TreeSpots(site, parcels, cfg)
    # Street trees: the lots are laid first, so a sweep along both sides of every drawn stretch only
    # finds frontage no lot took (short gaps, corners, beside pads), `street.spacing` apart along a
    # lane (INTERFACES "Wave 1c, round 2": houses get the frontage first).
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
            # the approach from the hub stays open, so the view up the high street is clear
            if math.dist(point, site.entrance) < street["entranceClear"]:
                continue
            near = [t for t in spots.trees if t["kind"] == "street" and math.dist(point, (t["x"], t["z"])) < street["spacing"]]
            if near:
                continue
            if spots.add(point, rng, variants["street"], {"anchor": "stretch", "stretch": site.ids[where[0]]}, "street"):
                return True
        return False

    for run in street_runs(site):
        length = math.dist(run["a"], run["b"])
        for side in (1, -1):
            s = street["step"]
            while s < length - street["step"]:
                s += street["spacing"] if plant_street(run, side, s) else street["step"]
    # Green and orchard trees round landmarks, planted once the landmark's street is drawn; the
    # tree slot's own green (its rect) is ringed by green trees on the stretch nearest it.
    for kind, slot, stretch in landmark_groups(site, cfg["orchard"]["districts"], cfg["green"]["districts"], [layer.get("requiresSlot")]):
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
    trees.sort(key=lambda t: entry_order(site, t))
    return trees


def landmark_groups(site, orchard_districts, green_districts, green_slots):
    """(kind, slot, anchor stretch) for every landmark a layer rings: orchard districts, green
    districts, and the named street-only greens (anchored to the stretch nearest them)."""
    groups = []
    for slot in sorted(site.era.slots, key=lambda s: s["id"]):
        district = site.era.layout["slots"][slot["id"]].get("district")
        if slot["id"] in green_slots:
            groups.append(("green", slot, site.nearest_drawn(slot["position"])))
        elif district in orchard_districts and slot["id"] in site.approach:
            groups.append(("orchard", slot, site.approach[slot["id"]]))
        elif district in green_districts and slot["id"] in site.approach:
            groups.append(("green", slot, site.approach[slot["id"]]))
    return groups


def nearest_parcel(point, parcels):
    """1-based index of the parcel whose footprint lies nearest `point` (lowest index on a tie)."""
    best, best_d = None, math.inf
    for index, parcel in enumerate(parcels, start=1):
        d = point_gap(point, parcel["poly"])
        if d < best_d - 1e-9:
            best, best_d = index, d
    return best


class ItemSpots:
    """Flowers and banners: each entry is a footprint (the plan's measured prop size x scale, turned
    rotationY) that keeps a walker's whole reach off every street and spur, stays off every lot
    (a planter may lean into its own house's front by `ownLot`), every built landmark's harvested
    extents, pad, marker, lamp and the Sign, and apart from every entry already placed in any layer."""

    def __init__(self, site, parcels, rule, taken):
        self.site, self.rule = site, rule
        self.lots = [(parcel["poly"], parcel["box"]) for parcel in parcels]
        solids = [(poly, rule["solid"]) for poly, _ in site.landmark_polys.values()]
        solids += [(poly, rule["solid"]) for poly in site.pad_polys.values()]
        solids += [(poly, rule["solid"]) for poly in site.marker_polys.values()]
        solids += [(poly, rule["solid"]) for poly in site.plaza_polys]
        solids += [(poly, rule["lamp"]) for poly in site.lamps]
        solids.append((site.era.sign_poly, rule["solid"]))
        self.solids = [(poly, box_of(poly), margin) for poly, margin in solids]
        self.streets = [(a, b, box) for _, _, a, b, box in site.street_boxes]
        self.spurs = list(site.spur_boxes)
        self.taken = taken  # (x, z) of every entry placed so far, every layer
        self.entries = []

    def fits(self, poly, point, own=None, lane_exempt=False):
        site, rule = self.site, self.rule
        edge = rule["edge"]
        if any(abs(v[0]) > site.era.half_x - edge or abs(v[1]) > site.era.half_z - edge for v in poly):
            return False
        box = box_of(poly)
        for index, (lot, lot_box) in enumerate(self.lots, start=1):
            margin = rule["lot"]
            if not boxes_apart(box, lot_box, margin):
                d = gap(poly, lot)
                if index == own:
                    if not polygon_within(poly, lot, rule["ownLot"]):
                        return False
                elif d < margin:
                    return False
        for solid, solid_box, margin in self.solids:
            if not boxes_apart(box, solid_box, margin) and gap(poly, solid) < margin:
                return False
        if not lane_exempt:
            for a, b, segment_box in self.streets:
                if not boxes_apart(box, segment_box, site.walker_street) and segment_gap(a, b, poly) < site.walker_street:
                    return False
            for a, b, segment_box in self.spurs:
                if not boxes_apart(box, segment_box, site.walker_spur) and segment_gap(a, b, poly) < site.walker_spur:
                    return False
        return all(math.dist(point, other) >= rule["cross"] for other in self.taken)

    def add(self, entry, poly, own=None):
        if not self.fits(poly, (entry["x"], entry["z"]), own):
            return False
        self.entries.append(entry)
        self.taken.append((entry["x"], entry["z"]))
        return True


def polygon_within(poly, lot, depth):
    """True when `poly` overlaps `lot` by at most `depth` studs (every vertex inside the lot lies
    within `depth` of its boundary)."""
    for vertex in poly:
        if streetplan.point_in_polygon(vertex, lot) and streetplan.point_polygon_distance(vertex, lot) > depth + EPS:
            return False
    return True


def item_poly(plan, layer, prop, x, z, rotation, scale):
    size = plan[layer]["footprints"][prop]
    return streetplan.square((x, z), size[0] * scale, size[1] * scale, rotation)


def make_entry(x, z, rotation, scale, variant, anchor):
    entry = {"x": rounded(x), "z": rounded(z), "rotationY": rounded(norm_degrees(rotation)), "scale": rounded(scale), "variant": variant}
    entry.update(anchor)
    return entry


def corner_candidates(site):
    """(point on the corner's bisector at distance 1, bisector unit, node) for every corner between
    two street arms at a crossing or a bend, nodes in creation order."""
    out = []
    for node, stretch_ids in enumerate(site.network.node_stretches):
        if len(stretch_ids) < 2:
            continue
        point = site.network.nodes[node]
        arms = []
        for sid in stretch_ids:
            st = site.network.stretches[sid]
            far = st["b"] if st["from"] == node else st["a"]
            d = streetplan.unit((far[0] - point[0], far[1] - point[1]))
            if d is not None:
                arms.append(d)
        arms.sort(key=lambda v: math.atan2(v[1], v[0]))
        for i, arm in enumerate(arms):
            following = arms[(i + 1) % len(arms)]
            angle = math.atan2(following[1], following[0]) - math.atan2(arm[1], arm[0])
            if angle <= 0:
                angle += math.tau
            if angle > math.pi * 0.95 and len(arms) > 2:
                continue  # a straight-through side of a crossing is frontage, not a corner
            if angle >= math.pi * 1.05:
                continue
            bisector = streetplan.unit((arm[0] + following[0], arm[1] + following[1]))
            if bisector is not None:
                out.append((point, bisector, node))
    return out


def generate_flowers(site, plan, parcels, levels, taken):
    """Plant Flowers (INTERFACES "Wave 1c, round 3"): a planter in front of each frontage house,
    borders in the lane corners, beds round the greens, the square and the civic landmarks."""
    cfg = plan["flowers"]
    layer = upgrade_config(site, "flowers")
    props = layer.get("props") or []
    if not props:
        return []
    rng = random.Random(f"{plan['seed']}:flowers")
    spots = ItemSpots(site, parcels, cfg, taken)
    variants = cfg["variants"]
    low, high = cfg["scale"]
    # Planters: in each row-1 house's front setback, square to the street, leaning into the lot's
    # own front garden rather than onto the walker lane.
    planter = props[variants["planter"] - 1]
    for index, parcel in enumerate(parcels, start=1):
        if parcel["row"] != 1 or levels[index - 1] < BUILT_LEVEL:
            continue
        st = site.network.stretches[site.stretch_by_id[parcel["stretch"]]]
        depth = site.sizes[parcel["size"]][1]
        fc = front_centre(parcel["x"], parcel["z"], parcel["rotationY"], depth)
        _, foot = streetplan.point_segment_distance(fc, st["a"], st["b"])
        normal = streetplan.unit((fc[0] - foot[0], fc[1] - foot[1]))
        if normal is None:
            continue
        scale = rng.uniform(low, high)
        half = plan["flowers"]["footprints"][planter][1] * scale / 2
        reach = site.walker_street + half + cfg["planter"]["slack"]
        x, z = foot[0] + normal[0] * reach, foot[1] + normal[1] * reach
        entry = make_entry(x, z, parcel["rotationY"], scale, variants["planter"], {"anchor": "parcel", "parcel": index})
        spots.add(entry, item_poly(plan, "flowers", planter, entry["x"], entry["z"], entry["rotationY"], entry["scale"]), own=index)
    # Borders in the corners between lane arms; a planter where a border does not fit.
    border = props[variants["border"] - 1]
    for point, bisector, node in corner_candidates(site):
        stretch = site.nearest_drawn(point)
        if stretch is None or node not in (site.network.stretches[stretch]["from"], site.network.stretches[stretch]["to"]):
            continue
        placed = False
        for reach in cfg["border"]["reach"]:
            if placed:
                break
            x, z = point[0] + bisector[0] * reach, point[1] + bisector[1] * reach
            rotation = facing_rot((-bisector[0], -bisector[1]))
            for variant, prop in ((variants["border"], border), (variants["planter"], planter)):
                entry = make_entry(x, z, rotation, rng.uniform(low, high), variant, {"anchor": "stretch", "stretch": site.ids[stretch]})
                if spots.add(entry, item_poly(plan, "flowers", prop, entry["x"], entry["z"], entry["rotationY"], entry["scale"])):
                    placed = True
                    break
    # Beds round the greens, the square and the civic landmarks.
    beds = cfg["beds"]
    ring_slots = set(beds["slots"])
    for slot in sorted(site.era.slots, key=lambda s: s["id"]):
        district = site.era.layout["slots"][slot["id"]].get("district")
        if slot["id"] not in ring_slots and district not in beds["districts"]:
            continue
        stretch = site.approach.get(slot["id"]) if slot["id"] in site.approach else site.nearest_drawn(slot["position"])
        if stretch is None:
            continue
        poly = site.landmark_polys[slot["id"]][0] if slot["id"] in site.landmark_polys else slot["footprint"]
        placed = 0
        for point in ring_candidates(rng, poly, beds["ring"][0], beds["ring"][1], beds["attempts"]):
            if placed >= beds["count"]:
                break
            variant = beds["variants"][placed % len(beds["variants"])]
            prop = props[variant - 1]
            entry = make_entry(point[0], point[1], rng.uniform(0.0, 360.0), rng.uniform(low, high), variant, {"anchor": "stretch", "stretch": site.ids[stretch]})
            if spots.add(entry, item_poly(plan, "flowers", prop, entry["x"], entry["z"], entry["rotationY"], entry["scale"])):
                placed += 1
    flowers = spots.entries
    flowers.sort(key=lambda e: entry_order(site, e))
    return flowers


def bunting_posts(plan, entry):
    """The two posts of a bunting entry: `bunting.half` x scale either side along its local X."""
    half = plan["banners"]["bunting"]["half"] * entry["scale"]
    dx, dz = rotate(half, 0.0, entry["rotationY"])
    return [(entry["x"] + dx, entry["z"] + dz), (entry["x"] - dx, entry["z"] - dz)]


def generate_banners(site, plan, parcels, taken):
    """Hang Banners (INTERFACES "Wave 1c, round 3"): street banners along the banner streets,
    alternating sides every 10-14 studs, and a few buntings spanning them, posts in the front
    setbacks clear of the walker reach."""
    cfg = plan["banners"]
    layer = upgrade_config(site, "banners")
    props = layer.get("props") or []
    if not props:
        return []
    rng = random.Random(f"{plan['seed']}:banners")
    spots = ItemSpots(site, parcels, cfg, taken)
    variants = cfg["variants"]
    streets = set(cfg["streets"])
    runs = [run for run in street_runs(site) if run["polyline"] + 1 in streets]
    # Buntings first: the few spots where both posts fit, spread along the banner streets.
    bunting = cfg["bunting"]
    candidates = []
    for run in runs:
        length = math.dist(run["a"], run["b"])
        d = run["d"]
        n = (-d[1], d[0])
        s = bunting["endMargin"]
        while s < length - bunting["endMargin"]:
            where = locate(site, run, s)
            if where is not None and where[0] in site.drawn:
                candidates.append((run, s, where[0], n))
            s += bunting["step"]
    chosen = []
    for run, s, stretch, n in candidates:
        if len(chosen) >= bunting["count"]:
            break
        x, z = run["a"][0] + run["d"][0] * s, run["a"][1] + run["d"][1] * s
        if any(math.dist((x, z), (c["x"], c["z"])) < bunting["spacing"] for c in chosen):
            continue
        rotation = math.degrees(math.atan2(-n[1], n[0]))
        entry = make_entry(x, z, rotation, bunting["scale"], variants["bunting"], {"anchor": "stretch", "stretch": site.ids[stretch]})
        posts = bunting_posts(plan, entry)
        post = bunting["post"]
        if all(spots.fits(streetplan.square(p, post, post, entry["rotationY"]), p) for p in posts):
            if not bunting_clear_of_trees(entry, posts, taken, bunting):
                continue
            spots.entries.append(entry)
            spots.taken.extend(posts)
            chosen.append(entry)
    # Street banners: alternating sides, the next one 10-14 studs further on.
    banner = cfg["banner"]
    for run in runs:
        length = math.dist(run["a"], run["b"])
        d = run["d"]
        side = 1
        s = banner["start"]
        while s < length - banner["endMargin"]:
            placed = False
            for shift in banner["shifts"]:
                t = s + shift
                if not banner["endMargin"] <= t <= length - banner["endMargin"]:
                    continue
                where = locate(site, run, t)
                if where is None or where[0] not in site.drawn:
                    continue
                n = (-d[1] * side, d[0] * side)
                variant = variants["banner"][len(spots.entries) % len(variants["banner"])]
                prop = props[variant - 1]
                scale = rng.uniform(*banner["scale"])
                half = cfg["footprints"][prop][1] * scale / 2
                reach = site.walker_street + half + banner["slack"]
                x, z = run["a"][0] + d[0] * t + n[0] * reach, run["a"][1] + d[1] * t + n[1] * reach
                rotation = facing_rot((-n[0], -n[1]))  # cloth toward the street
                entry = make_entry(x, z, rotation, scale, variant, {"anchor": "stretch", "stretch": site.ids[where[0]]})
                if spots.add(entry, item_poly(plan, "banners", prop, entry["x"], entry["z"], entry["rotationY"], entry["scale"])):
                    placed = True
                    s = t
                    break
            if placed:
                side = -side
                s += rng.uniform(*banner["spacing"])
            else:
                s += banner["step"]
    banners = spots.entries
    banners.sort(key=lambda e: entry_order(site, e))
    return banners


def bunting_clear_of_trees(entry, posts, taken, rule):
    """No tree trunk within `treeClear` of the string's line between the posts, so no canopy hangs
    into the pennants."""
    a, b = posts
    for point in taken:
        if streetplan.point_segment_distance(point, a, b)[0] < rule["treeClear"]:
            return False
    return True


def placed_at_full(site, entry, levels):
    """INTERFACES "Wave 1c, round 3": an entry is placed once its layer's slot is owned and its
    anchor developed (a stretch drawn, or a parcel at level 2 or more)."""
    if entry.get("anchor") == "stretch":
        index = site.stretch_by_id.get(entry.get("stretch"))
        return index is not None and index in site.drawn
    if entry.get("anchor") == "parcel":
        parcel = entry.get("parcel")
        return isinstance(parcel, int) and 1 <= parcel <= len(levels) and levels[parcel - 1] >= BUILT_LEVEL
    return False


def generate_upgrades(site, plan, parcels, levels):
    """Every configured layer in a fixed order (trees, banners, flowers); each later layer keeps
    clear of every entry an earlier one placed."""
    out = {}
    trees = generate_trees(site, plan, parcels, levels) if upgrade_config(site, "trees") else []
    taken = [(t["x"], t["z"]) for t in trees]
    banners = generate_banners(site, plan, parcels, taken) if upgrade_config(site, "banners") else []
    flowers = generate_flowers(site, plan, parcels, levels, taken) if upgrade_config(site, "flowers") else []
    for name, entries in (("trees", trees), ("flowers", flowers), ("banners", banners)):
        if upgrade_config(site, name):
            out[name] = entries
    return out


# --------------------------------------------------------------------------------------------
# Parked carts (INTERFACES "Wave 2.0"): one more upgrade layer, laid last in what is left
# --------------------------------------------------------------------------------------------


def cart_prop(site, plan):
    """The carts layer's prop, or None when the config or the plan leaves the layer out."""
    props = upgrade_config(site, CARTS).get("props") or []
    variant = (plan.get(CARTS) or {}).get("variant")
    return props[variant - 1] if isinstance(variant, int) and 1 <= variant <= len(props) else None


def cart_extents(site, plan):
    """The cart prop's ground extents: harvested (the contract's measure) once it is uploaded;
    before that the plan's `carts.footprints` entry, centred, as the flower and banner layers are
    measured, so a layer can be laid for props that only exist as blueprints. None with neither."""
    prop = cart_prop(site, plan)
    if prop is None:
        return None
    harvested = site.prop_extents(prop)
    if harvested is not None:
        return harvested
    declared = (plan[CARTS].get("footprints") or {}).get(prop)
    return (-declared[0] / 2, declared[0] / 2, -declared[1] / 2, declared[1] / 2) if declared is not None else None


def cart_body(extents, entry):
    """A cart's ground rectangle: its prop's harvested extents x the entry's scale, turned rotationY."""
    return extents_poly((entry["x"], entry["z"]), entry["rotationY"], tuple(v * entry["scale"] for v in extents))


def cart_anchor(site, polys, entry):
    """What clears the woods round a cart once it is placed, as (daylight from a point to it, the
    margin the clearing mask grows it by): a kerb cart's stretch chord and `clear.street`, a yard
    cart's parcel rect and `clear.parcel` (INTERFACES "Clearing": both are in the mask whenever the
    anchor is developed). None for an anchor the data cannot resolve."""
    clear = site.config["clear"]
    if entry.get("anchor") == "stretch":
        index = site.stretch_by_id.get(entry.get("stretch"))
        if index is None:
            return None
        st = site.network.stretches[index]
        return (lambda point: streetplan.point_segment_distance(point, st["a"], st["b"])[0]), clear["street"]
    parcel = entry.get("parcel")
    if entry.get("anchor") == "parcel" and isinstance(parcel, int) and 1 <= parcel <= len(polys):
        lot = polys[parcel - 1]
        return (lambda point: point_gap(point, lot)), clear["parcel"]
    return None


class CartGround:
    """Everything a parked cart answers to, with the daylight each kind asks for. The generator
    builds it with the plan's margins and `check` with the contract's, so both judge a cart by one
    rule. A cart's body keeps a walker's whole reach off every street and spur (carts are not walk
    solids), `lot` from every parcel, `solid` from every landmark's harvested extents, pad, marker,
    plaza and the Sign, `lamp` from every lamp, `tree` from every town tree's trunk, `item` from
    every flower, banner and bunting, and `edge` from the plot edge. And it never stands in the
    woods: it stands on land its own anchor clears, clear of every wood that anchor leaves."""

    def __init__(self, site, plan, polys, upgrades, wild, margins, tolerance):
        self.site, self.margins, self.tolerance = site, margins, tolerance
        solids = [(f"parcel {index}", poly, margins["lot"]) for index, poly in enumerate(polys, start=1)]
        solids += [(f"the {slot_id} extents", poly, margins["solid"]) for slot_id, (poly, _) in site.landmark_polys.items()]
        solids += [(f"the {slot_id} pad", poly, margins["solid"]) for slot_id, poly in site.pad_polys.items()]
        solids += [(f"the {slot_id} marker", poly, margins["solid"]) for slot_id, poly in site.marker_polys.items()]
        solids += [(f"plaza {index}", poly, margins["solid"]) for index, poly in enumerate(site.plaza_polys, start=1)]
        solids += [(f"lamp {index}", poly, margins["lamp"]) for index, poly in enumerate(site.lamps, start=1)]
        solids.append(("the Sign", site.era.sign_poly, margins["solid"]))
        self.trunks = []  # (label, point): a layer the plan gives no footprints is a layer of trees
        self.strings = []  # (label, post, post): a bunting's pennants hang at about a cart's height
        for name in LAYERS:
            if name == CARTS:
                continue
            props = upgrade_config(site, name).get("props") or []
            footprints = (plan.get(name) or {}).get("footprints")
            bunting = (plan.get(name) or {}).get("bunting")
            for entry in upgrades.get(name, []):
                label = f"the {name} entry at ({number(entry['x'])}, {number(entry['z'])})"
                variant = entry.get("variant")
                prop = props[variant - 1] if isinstance(variant, int) and 1 <= variant <= len(props) else None
                if footprints is None:
                    self.trunks.append((label, (entry["x"], entry["z"])))
                elif bunting is not None and prop == bunting["prop"]:
                    posts = bunting_posts(plan, entry)
                    solids += [(label, streetplan.square(post, bunting["post"], bunting["post"], entry["rotationY"]), margins["item"]) for post in posts]
                    self.strings.append((label, posts[0], posts[1]))
                elif prop in footprints:
                    solids.append((label, item_poly(plan, name, prop, entry["x"], entry["z"], entry["rotationY"], entry["scale"]), margins["item"]))
        self.solids = [(label, poly, box_of(poly), margin) for label, poly, margin in solids]
        self.streets = [(f"street {polyline + 1}", a, b, box) for polyline, _, a, b, box in site.street_boxes]
        self.spurs = [(f"the {slot_id} path", a, b, box_of((a, b))) for slot_id, a, b in site.spur_segments]
        radii = site.config["wild"]
        self.woods = []  # (point, clearing radius): what Fabric tests against the mask
        for item in wild:
            if item["kind"] == "clump":
                self.woods += [((quad[0], quad[1]), radii["quarterRadius"]) for quad in item["quads"]]
            else:
                self.woods.append(((item["x"], item["z"]), radii["singleRadius"]))

    def problems(self, body, centre, anchor_gap, clear):
        """What is wrong with a cart standing as `body`, one text per broken rule, lazily, so a
        search can stop at the first. `anchor_gap` and `clear` are cart_anchor's pair."""
        site, margins, slack = self.site, self.margins, self.tolerance
        edge = margins["edge"] - slack
        if any(abs(v[0]) > site.era.half_x - edge or abs(v[1]) > site.era.half_z - edge for v in body):
            yield f"within {margins['edge']:g} of the plot edge"
        box = box_of(body)
        for lanes, need in ((self.streets, site.walker_street), (self.spurs, site.walker_spur)):
            for what, a, b, lane_box in lanes:
                if not boxes_apart(box, lane_box, need) and segment_gap(a, b, body) < need - slack:
                    yield f"{segment_gap(a, b, body):.2f} from {what}, inside the walker reach (need {need:g})"
        for what, poly, poly_box, margin in self.solids:
            if not boxes_apart(box, poly_box, margin) and gap(body, poly) < margin - slack:
                yield f"{gap(body, poly):.2f} from {what} (need {margin:g})"
        for what, point in self.trunks:
            if not point_box_apart(point, box, margins["tree"]) and point_gap(point, body) < margins["tree"] - slack:
                yield f"{point_gap(point, body):.2f} from {what} (need {margins['tree']:g})"
        for what, a, b in self.strings:
            if segment_gap(a, b, body) < margins["item"] - slack:
                yield f"{segment_gap(a, b, body):.2f} from the string of {what} (need {margins['item']:g})"
        # INTERFACES "Wave 2.0": no cart ever stands in the woods. The mask clears a wood whose
        # disc comes within `clear` of the anchor (IsCleared: distance - radius < margin), so the
        # cart's own spot must be inside that margin and its body off every wood the anchor leaves.
        # EPS keeps a wood on the boundary on the standing side, whichever way the game rounds it.
        if anchor_gap(centre) >= clear - EPS:
            yield f"stands {anchor_gap(centre):.2f} from its anchor, outside the {clear:g} its anchor clears"
        for point, radius in self.woods:
            reach = radius + margins["wood"]
            if point_box_apart(point, box, reach) or anchor_gap(point) - radius < clear - EPS:
                continue
            if point_gap(point, body) < reach - slack:
                yield f"stands in the woods at ({number(point[0])}, {number(point[1])}), which its anchor does not clear"


def generate_carts(site, plan, parcels, levels, districts, upgrades, wild):
    """Parked carts (INTERFACES "Wave 2.0"), in data order: nearest the entrance first. Every spot
    is proved with the largest cart the plan allows and then takes a scale from the plan's range: a
    prop's origin lies inside its extents, so a smaller cart on the same spot stands inside the
    larger one."""
    cfg = plan[CARTS]
    extents = cart_extents(site, plan)
    if extents is None:
        return []
    rng = random.Random(f"{plan['seed']}:{CARTS}")
    polys = [parcel["poly"] for parcel in parcels]
    ground = CartGround(site, plan, polys, upgrades, wild, cfg, 0.0)
    largest = cfg["scale"][1]
    half_width = max(-extents[0], extents[1]) * largest
    half_length = max(-extents[2], extents[3]) * largest

    def spot(x, z, rotation, anchor):
        entry = make_entry(x, z, rotation, largest, cfg["variant"], anchor)
        problems = ground.problems(cart_body(extents, entry), (entry["x"], entry["z"]), *cart_anchor(site, polys, entry))
        return entry if next(problems, None) is None else None

    # Kerb carts: both sides of every straight run are swept at the walkers' reach, a little past
    # its ends (a cart at a lane's end), and each unbroken reach of frontage where a cart fits
    # gives one spot, its middle -- the lots, trees, flowers and banners are laid, so only frontage
    # nothing took is left. A cart is parked on its own side of the lane, nose the way that side
    # travels.
    kerb = cfg["kerb"]
    reach = site.walker_street + kerb["slack"] + half_width
    gaps = []
    for run in street_runs(site):
        length = math.dist(run["a"], run["b"])
        d = run["d"]
        for side in (1, -1):
            n = (-d[1] * side, d[0] * side)
            rotation = facing_rot((d[0] * side, d[1] * side))
            sweep = []
            for step in range(int((length + 2 * kerb["overrun"]) / kerb["step"]) + 1):
                s = -kerb["overrun"] + step * kerb["step"]
                where = locate(site, run, min(max(s, 0.0), length))
                found = None
                if where is not None and where[0] in site.drawn:
                    x, z = run["a"][0] + d[0] * s + n[0] * reach, run["a"][1] + d[1] * s + n[1] * reach
                    found = spot(x, z, rotation, {"anchor": "stretch", "stretch": site.ids[where[0]]})
                sweep.append(found)
            for fits, fitting in itertools.groupby(sweep, key=lambda entry: entry is not None):
                if fits:
                    fitting = list(fitting)
                    gaps.append(fitting[len(fitting) // 2])
    carts = []

    def park(entry):
        if any(math.dist((entry["x"], entry["z"]), (other["x"], other["z"])) < cfg["spacing"] for other in carts):
            return False
        entry["scale"] = rounded(rng.uniform(*cfg["scale"]))
        carts.append(entry)
        return True

    for entry in sorted(gaps, key=lambda e: entry_order(site, e)):
        if len(carts) >= kerb["count"]:
            break
        park(entry)
    # Yard carts: beside a lot of one of the plan's cart districts (the district its finished
    # building shows), a little askew, hugging the lot's side so the lot's own clearing covers it.
    # One spot per lot; the districts take turns, so the farm, the market and the workshops each
    # get their cart before any gets a second.
    yard = cfg["yard"]
    beside = {district: [] for district in yard["districts"]}
    for index, parcel in enumerate(parcels, start=1):
        if districts[index - 1] not in beside or levels[index - 1] < BUILT_LEVEL:
            continue
        width, depth = site.sizes[parcel["size"]]
        turn = rng.uniform(-yard["turnJitter"], yard["turnJitter"])
        rotation = parcel["rotationY"] + turn + (HALF_TURN if rng.random() < 0.5 else 0.0)
        across = half_width * abs(math.cos(math.radians(turn))) + half_length * abs(math.sin(math.radians(turn)))
        sides = (1, -1) if rng.random() < 0.5 else (-1, 1)
        found = None
        for side, shift in ((side, shift) for side in sides for shift in yard["shifts"]):
            dx, dz = rotate(side * (width / 2 + yard["gap"] + across), shift * depth, parcel["rotationY"])
            found = spot(parcel["x"] + dx, parcel["z"] + dz, rotation, {"anchor": "parcel", "parcel": index})
            if found is not None:
                break
        if found is not None:
            beside[districts[index - 1]].append(found)
    queues = [beside[district] for district in yard["districts"]]
    parked = 0
    while parked < yard["count"] and any(queues):
        for queue in queues:
            while queue and parked < yard["count"]:
                if park(queue.pop(0)):
                    parked += 1
                    break
    carts.sort(key=lambda e: entry_order(site, e))
    return carts


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
    skirt = wild.get("skirt")
    if x < -half or x > half or z > half:
        if skirt is None:
            return 0.0
        beyond = max(-half - x, x - half, z - half)
        reach = skirt["depth"] + skirt["wobble"] * wobble
        if z <= half and (x < -half or x > half):
            share = skirt["cornerShare"]
            along = min(1.0, max(0.0, (z + half) / (2 * half)))
            reach = skirt["depth"] * (share + (1 - share) * along) + skirt["sideWobble"] * wobble
        if beyond > reach:
            return 0.0
        return woods * min(1.0, (reach - beyond) / skirt["fade"])
    band, heart = wild.get("front"), wild.get("heart")
    low = band["low"] if band is not None else 0.0  # how thin the woods get where the plan opens them
    value = woods
    if band is not None:
        ramp = min(1.0, max(0.0, (z + half - band["start"] - band["wobble"] * wobble) / band["ramp"]))
        value = low + (woods - low) * ramp
    if heart is not None:
        distance = math.dist((x, z), tuple(heart["centre"])) + heart["wobble"] * wobble
        if distance < heart["clear"] + heart["fade"]:
            value = min(value, low + (woods - low) * max(0.0, (distance - heart["clear"]) / heart["fade"]))
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
    cfg = plan["wild"].get("glades")
    if cfg is None:
        return []
    rng = random.Random(f"{plan['seed']}:glades")
    heart = plan["wild"].get("heart")
    inner = half - cfg["inset"]
    glades = []
    for _ in range(cfg["attempts"]):
        if len(glades) >= cfg["count"]:
            break
        x, z = rng.uniform(-inner, inner), rng.uniform(-inner, inner)
        radius = rng.uniform(*cfg["radius"])
        if heart is not None and math.dist((x, z), tuple(heart["centre"])) < heart["clear"] + cfg["apart"]:
            continue
        if density(x, z, plan, noise, half) < cfg["minDensity"]:
            continue
        if any(math.dist((x, z), (gx, gz)) < cfg["apart"] + radius + gr for gx, gz, gr, _ in glades):
            continue
        glades.append((x, z, radius, cfg["fade"]))
    return glades


def generate_wild(site, plan):
    """The era's wild land in data order, by the plan's `wild.pattern`: woods (the default) or fields."""
    if plan["wild"].get("pattern") == FIELDS:
        return generate_fields(site, plan)
    return generate_woods(site, plan)


def wild_order(site, clumps, singles):
    """The client draws a fixed prefix of the wild list (INTERFACES "Review amendments"): near plots
    the first budget.wild entries, far plots the first budget.wildFar clumps. So the skirt's clumps
    lead -- a far town that has cleared its own land still sits in its landscape band -- then the
    plot's clumps farthest from the entrance first, because the town grows out from the entrance
    and clears those last: the far prefix then keeps the wild land a near view still shows. Singles
    come last, in the order given. Ties keep a front-to-back order."""
    entrance = site.entrance

    def order(entry):
        reach = 0.0 if entry["skirt"] else round(math.dist(entrance, (entry["x"], entry["z"])), DECIMALS)
        return (0 if entry["skirt"] else 1, -reach, entry["z"], entry["x"])

    return sorted(clumps, key=order) + singles


def generate_woods(site, plan):
    wild = plan["wild"]
    names = site.config["wild"]
    half = site.era.half_x
    noise = Noise(f"{plan['seed']}:noise", wild["noise"]["waves"], wild["noise"]["base"])
    spread = Noise(f"{plan['seed']}:spread", wild["noise"]["waves"], wild["noise"]["base"] * 1.7)
    glades = pick_glades(plan, noise, half)
    clumps_cfg, singles_cfg = wild["clumps"], wild.get("singles")
    skirt = wild.get("skirt")
    limit = half + (skirt["depth"] + skirt["wobble"] if skirt is not None else 0.0)

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
    if singles_cfg is None:
        return wild_order(site, clumps, [])
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
    singles.sort(key=lambda entry: (entry["z"], entry["x"]))
    return wild_order(site, clumps, singles)


# --------------------------------------------------------------------------------------------
# Wild land as farmland (INTERFACES "Wave 2.1"): fields on a grid, pasture, a landscape band
# --------------------------------------------------------------------------------------------


def grid_point(grid, i, j):
    """The plot position of grid coordinate (i, j): cell (i, j)'s centre for whole numbers, the lane
    crossing between four cells for halves. The grid is square, `pitch` studs a cell, turned `angle`
    about its `origin`."""
    dx, dz = rotate(i * grid["pitch"], j * grid["pitch"], grid["angle"])
    return (grid["origin"][0] + dx, grid["origin"][1] + dz)


def plot_rect(site):
    return streetplan.square((0.0, 0.0), 2 * site.era.half_x, 2 * site.era.half_z, 0)


def on_plot(site, poly, inset):
    return all(abs(v[0]) <= site.era.half_x - inset and abs(v[1]) <= site.era.half_z - inset for v in poly)


def beyond_plot(site, point):
    """How far a point lies past the plot's back and side edges, 0 on it; None in front of it, where
    the hub approach stays open."""
    if point[1] < -site.era.half_z:
        return None
    dx, dz = max(abs(point[0]) - site.era.half_x, 0.0), max(point[1] - site.era.half_z, 0.0)
    return math.sqrt(dx * dx + dz * dz)


def field_poly(wild, x, z, rotation):
    size = wild["clumps"]["size"]
    return streetplan.square((x, z), size, size, rotation)


def landmark_polys(wild):
    """Each skirt landmark of the plan as (entry, position, its ground rectangle): it stands on a
    grid cell (`cell`, halves allowed), so it moves with the grid."""
    out = []
    for landmark in wild.get("landmarks") or []:
        x, z = grid_point(wild["grid"], *landmark["cell"])
        x, z = rounded(x), rounded(z)
        size = landmark["size"]
        out.append((landmark, (x, z), streetplan.square((x, z), size[0], size[1], landmark["rotationY"])))
    return out


def ranked(cells, noise, share):
    """The `share` of `cells` where the noise field is highest: a quantile, so the count is exact,
    and of a smooth field, so the chosen cells cluster."""
    order = sorted(cells, key=lambda cell: (-noise(*cell["centre"]), cell["key"]))
    return {cell["key"] for cell in order[: int(round(share * len(cells)))]}


def thinned(items, cap):
    """At most `cap` of `items`, kept evenly through the list."""
    count = len(items)
    if count <= cap:
        return items
    return [item for index, item in enumerate(items, start=1) if (index * cap) // count != ((index - 1) * cap) // count]


def generate_fields(site, plan):
    """Farmland (INTERFACES "Wave 2.1"): a fenced field per grid cell, each a clump of four
    quarter-fields that the town clears quarter by quarter. Three things keep it from reading as a
    quilt: a cell's crop comes from a low-frequency noise field, so neighbouring cells share a crop
    and read as one larger field; a share of the cells, clustered by a second field, lies fallow as
    pasture with hay, trees and a telegraph line across it; and the fields run on past the back and
    side edges into a landscape band with the plan's landmarks. A field stands wholly on the plot
    or wholly off it: the ground past the edge is lower."""
    wild = plan["wild"]
    grid, clumps_cfg, skirt = wild["grid"], wild["clumps"], wild["skirt"]
    seed = plan["seed"]
    rng = random.Random(f"{seed}:wild")
    landmarks = landmark_polys(wild)
    reach = max(site.era.half_x, site.era.half_z) + skirt["depth"] + clumps_cfg["size"]
    span = int(math.ceil(reach * math.sqrt(2) / grid["pitch"])) + 1
    plot = plot_rect(site)
    on, off = [], []
    for j in range(-span, span + 1):
        for i in range(-span, span + 1):
            centre = grid_point(grid, i, j)
            centre = (rounded(centre[0]), rounded(centre[1]))
            poly = field_poly(wild, centre[0], centre[1], grid["angle"])
            cell = {"key": (j, i), "centre": centre, "poly": poly}
            if any(gap(poly, rect) < skirt["gap"] for _, _, rect in landmarks):
                continue
            if on_plot(site, poly, grid["edge"]):
                on.append(cell)
                continue
            past = beyond_plot(site, centre)
            beside = abs(centre[0]) > site.era.half_x and centre[1] <= site.era.half_z
            if past is None or past > skirt["depth"] or gap(poly, plot) < skirt["gap"]:
                continue
            # Beside the plot the band only runs from `sideFrom` back: it tapers out toward the hub.
            if beside and centre[1] < skirt["sideFrom"]:
                continue
            off.append(cell)
    fallow_noise = Noise(f"{seed}:fallow", wild["fallow"]["noise"]["waves"], wild["fallow"]["noise"]["base"])
    pasture = ranked(on, fallow_noise, wild["fallow"]["share"])
    skirt_pasture = ranked(off, fallow_noise, skirt["fallow"])
    fields = [cell for cell in on if cell["key"] not in pasture] + [cell for cell in off if cell["key"] not in skirt_pasture]
    # Crops in bands along one smooth field: the band order is the plan's, so the middle crop is the
    # sea the others stand in as patches.
    crop_noise = Noise(f"{seed}:crops", wild["crops"]["noise"]["waves"], wild["crops"]["noise"]["base"])
    by_noise = sorted(fields, key=lambda cell: (crop_noise(*cell["centre"]), cell["key"]))
    crop, taken, share = {}, 0, 0.0
    for band in wild["crops"]["bands"]:
        share += band["share"]
        upto = int(round(share * len(by_noise)))
        for cell in by_noise[taken:upto]:
            crop[cell["key"]] = band["variant"]
        taken = max(taken, upto)
    for cell in by_noise[taken:]:
        crop[cell["key"]] = wild["crops"]["bands"][-1]["variant"]
    on_keys = {cell["key"] for cell in on}
    clumps = []
    for cell in fields:
        x, z = cell["centre"]
        rotation = rounded(norm_degrees(grid["angle"] + QUARTER_TURN * rng.randrange(QUARTERS)))
        clumps.append(
            {
                "kind": "clump",
                "variant": crop[cell["key"]],
                "x": x,
                "z": z,
                "rotationY": rotation,
                "scale": 1.0,
                "skirt": cell["key"] not in on_keys,
                "quads": [[rounded(q[0]), rounded(q[1])] for q in quad_centres(x, z, rotation, 1.0, clumps_cfg["quarterOffset"])],
            }
        )

    def single(prop, x, z, rotation, scale, is_skirt):
        return {"kind": "single", "prop": prop, "x": rounded(x), "z": rounded(z), "rotationY": rounded(norm_degrees(rotation)), "scale": rounded(scale), "skirt": is_skirt}

    # Singles lead with what the landscape cannot do without, in case a budget ever cuts the tail:
    # the landmarks, the skirt's shelterbelts, the telegraph line, then the pasture's hay and trees.
    singles = [single(landmark["prop"], x, z, landmark["rotationY"], 1.0, True) for landmark, (x, z), _ in landmarks]
    # Shelterbelts and trees in the skirt's pasture, a row lying along the plot edge it stands off.
    # Skirt-only props: nothing past the edge is ever cleared, so a prop wider than the clearing test
    # of a single (one point, `singleRadius`) is safe there and nowhere else.
    dress = skirt.get("singles")
    if dress is not None:
        srng = random.Random(f"{seed}:skirt")
        for index, cell in enumerate(thinned([cell for cell in off if cell["key"] in skirt_pasture], dress["count"])):
            x, z = cell["centre"]
            behind = z - site.era.half_z >= abs(x) - site.era.half_x
            turn = (0.0 if behind else QUARTER_TURN) + srng.uniform(-dress["turnJitter"], dress["turnJitter"])
            x, z = x + srng.uniform(-dress["jitter"], dress["jitter"]), z + srng.uniform(-dress["jitter"], dress["jitter"])
            singles.append(single(dress["props"][index % len(dress["props"])], x, z, turn, srng.uniform(*dress["scale"]), True))
    # The telegraph line: poles at lane crossings along a grid line, so no pole stands in a field.
    poles = wild.get("poles")
    if poles is not None:
        for line in poles["lines"]:
            count = int(math.floor((line["to"] - line["from"]) / line["step"] + 1e-9)) + 1
            for k in range(count):
                along = line["from"] + k * line["step"]
                point = grid_point(grid, *((along, line["lane"]) if line["axis"] == "x" else (line["lane"], along)))
                past = beyond_plot(site, point)
                inside = abs(point[0]) <= site.era.half_x - grid["edge"] and abs(point[1]) <= site.era.half_z - grid["edge"]
                outside = past is not None and skirt["gap"] <= past <= skirt["depth"]
                pole = single(poles["prop"], point[0], point[1], grid["angle"] + line.get("turn", 0.0), 1.0, not inside)
                crossing = any((pole["x"], pole["z"]) == (other["x"], other["z"]) for other in singles)  # two lines meet
                if (inside or outside) and not crossing and all(point_gap(point, rect) >= skirt["gap"] for _, _, rect in landmarks):
                    singles.append(pole)
    # Hay and trees on the plot's pasture, clear of the cell's edge (the lanes and the fences).
    loose = wild.get("singles")
    if loose is not None:
        lrng = random.Random(f"{seed}:singles")
        scattered = []
        room = grid["pitch"] / 2 - loose["inset"]
        for cell in on:
            if cell["key"] not in pasture:
                continue
            for _ in range(lrng.randint(*loose["perCell"])):
                dx, dz = rotate(lrng.uniform(-room, room), lrng.uniform(-room, room), grid["angle"])
                x, z = cell["centre"][0] + dx, cell["centre"][1] + dz
                prop, turn, scale = loose["props"][lrng.randrange(len(loose["props"]))], lrng.uniform(0.0, 360.0), lrng.uniform(*loose["scale"])
                if all(math.dist((x, z), (other["x"], other["z"])) >= loose["spacing"] for other in scattered):
                    scattered.append(single(prop, x, z, turn, scale, False))
        scattered = thinned(scattered, loose["count"])
        scattered.sort(key=lambda entry: (-round(math.dist(site.entrance, (entry["x"], entry["z"])), DECIMALS), entry["z"], entry["x"]))
        singles += scattered
    return wild_order(site, clumps, singles)


# --------------------------------------------------------------------------------------------
# Document
# --------------------------------------------------------------------------------------------

PARCEL_KEYS = ("x", "z", "rotationY", "size", "stretch", "along", "row", "front")
ENTRY_KEYS = ("x", "z", "rotationY", "scale", "variant", "anchor", "stretch", "parcel")


def build(era_name, city=None, era=None, network=None):
    """The document and the generator's bookkeeping (tree kinds) for the summary."""
    site = Site(era_name, city, era, network)
    plan = load_plan(era_name)
    parcels = generate_parcels(site, plan)
    levels, districts = full_build_states(site, parcels)
    upgrades = generate_upgrades(site, plan, parcels, levels)
    wild = generate_wild(site, plan)
    # Last, in what every other list left: nothing above may depend on the carts.
    if upgrade_config(site, CARTS) and plan.get(CARTS):
        upgrades[CARTS] = generate_carts(site, plan, parcels, levels, districts, upgrades, wild)
    doc = {
        "version": FORMAT_VERSION,
        "parcels": [{key: p[key] for key in PARCEL_KEYS} for p in parcels],
        "upgrades": {name: [{key: e[key] for key in ENTRY_KEYS if key in e} for e in entries] for name, entries in upgrades.items()},
        "wild": wild,
    }
    return doc, [t["kind"] for t in upgrades.get("trees", [])]


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
    def entries(items, indent):
        return [f"{indent}{entry_text(item)}{',' if i < len(items) - 1 else ''}" for i, item in enumerate(items)]

    lines = ["{", f'  "version": {doc["version"]},', '  "parcels": [']
    lines += entries(doc.get("parcels", []), "    ")
    lines += ["  ],", '  "upgrades": {']
    layers = [name for name in LAYERS if name in doc.get("upgrades", {})]
    for n, name in enumerate(layers):
        lines.append(f'    "{name}": [')
        lines += entries(doc["upgrades"][name], "      ")
        lines.append("    ]" + ("," if n < len(layers) - 1 else ""))
    lines += ["  },", '  "wild": [']
    lines += entries(doc.get("wild", []), "    ")
    lines += ["  ]", "}"]
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
    """A marker may not sit on a slot footprint (+CHECK_MARKER_SLOT), a pad, a street strip or another
    slot's path strip. streetOnly slots count: their pad is real."""
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
            # A marker stands only while its slot has a pad, and that slot's own path is only drawn
            # once the slot is bought: the two never share the ground. On a road-wide path that is
            # the one place beside the pad that costs the street no frontage.
            if other_id == slot["id"]:
                continue
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
        for slot_id, (footprint, measured) in site.landmark_polys.items():
            need = CHECK_LANDMARK if measured else CHECK_SLOT
            d = gap(poly, footprint)
            if d < need - EPS:
                what = "harvested extents" if measured else "footprint"
                messages.append(f"{label}: {d:.2f} from the {slot_id} {what} (need {need})")
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
            # INTERFACES "Wave 1c, round 2": the front is the nearest earlier parcel of the row in
            # front on the same side of the same street.
            polyline = parcel_polyline(parcel)
            side = street_side(site, polyline, (parcel["x"], parcel["z"]))
            if street_side(site, polyline, (ahead["x"], ahead["z"])) != side:
                messages.append(f"{label}: stands on the other side of the street from parcel {front}")
            reach = math.dist((ahead["x"], ahead["z"]), (parcel["x"], parcel["z"]))
            for j, other in enumerate(parcels[: index - 1], start=1):
                if j == front or other["row"] != row - 1 or other["stretch"] not in site.stretch_by_id:
                    continue
                if parcel_polyline(other) != polyline or street_side(site, polyline, (other["x"], other["z"])) != side:
                    continue
                if math.dist((other["x"], other["z"]), (parcel["x"], parcel["z"])) < reach - EPS:
                    messages.append(f"{label}: parcel {j} is a nearer row-{row - 1} front than parcel {front}")
                    break
        else:
            messages.append(f"{label}: row {row!r} is not 1 to {MAX_ROW}")
    for i, p in enumerate(polys):
        if p is None:
            continue
        box = box_of(p)
        for j in range(i + 1, len(polys)):
            q = polys[j]
            if q is None or boxes_apart(box, box_of(q), CHECK_SIZE_GAP):
                continue
            d = gap(p, q)
            if d <= 0:
                messages.append(f"parcel {i + 1} overlaps parcel {j + 1}")
            elif parcels[i]["size"] != parcels[j]["size"] and d < CHECK_SIZE_GAP - EPS:
                messages.append(f"parcels {i + 1} and {j + 1}: {d:.2f} apart, lots of different sizes need {CHECK_SIZE_GAP}")
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
    houses = 0
    if all(poly is not None for poly in polys) and all(p["stretch"] in site.stretch_by_id for p in parcels):
        need_level = plan["parcels"].get("minLevel", 1)
        levels = full_build_levels(site, parcels)
        houses = sum(1 for level in levels if level >= BUILT_LEVEL)
        for index, level in enumerate(levels, start=1):
            if level < need_level:
                what = "stays wild" if level == 0 else f"only reaches level {level}"
                messages.append(f"parcel {index}: {what} even with the whole era owned (need {need_level})")
    need = plan.get("require") or {}
    medium = sum(1 for p in parcels if p["size"] == "medium")
    if len(parcels) < need.get("parcels", 0):
        messages.append(f"parcels: {len(parcels)}, need at least {need['parcels']}")
    if medium < need.get("medium", 0):
        messages.append(f"parcels: {medium} medium, need at least {need['medium']}")
    if houses < need.get("houses", 0):
        messages.append(f"parcels: {houses} houses (level {BUILT_LEVEL}+) at full build, need at least {need['houses']}")
    cap = site.city.get("budget", {}).get("parcels")
    if isinstance(cap, (int, float)) and len(parcels) > cap:
        messages.append(f"parcels: {len(parcels)}, more than budget.parcels {cap:g} -- near plots never draw the tail")
    return messages


def upgrade_messages(site, plan, doc):
    """INTERFACES "Wave 1c, round 3": every layer's schema, anchors, clearances, budget and floor."""
    messages = []
    upgrades = doc.get("upgrades", {})
    if not isinstance(upgrades, dict):
        return ["upgrades: must map a layer name to a list of entries"]
    parcels = doc.get("parcels", [])
    polys = [rect((p["x"], p["z"]), site.sizes.get(p["size"], (0, 0)), p["rotationY"]) for p in parcels]
    levels, districts = full_build_states(site, parcels) if parcels else ([], [])
    streets = [(f"street {pl + 1}", a, b) for pl, _seg, a, b in site.street_segments]
    spurs = [(f"the {slot_id} path", a, b) for slot_id, a, b in site.spur_segments]
    need = plan.get("require") or {}
    everything = [(name, e) for name in LAYERS for e in upgrades.get(name, [])]
    carts = upgrades.get(CARTS, [])
    cart_size = cart_extents(site, plan) if carts else None
    ground = None
    if cart_size is not None:
        ground = CartGround(site, plan, polys, upgrades, doc.get("wild", []), CHECK_CART_MARGINS, EPS)
    elif carts:
        messages.append(f"{CARTS}: the layer's prop has neither harvested extents in Assets.json nor a `{CARTS}.footprints` entry in the plan, so no cart can be judged")
    for name in upgrades:
        if name not in LAYERS:
            messages.append(f"upgrades: layer {name!r} is not one of {LAYERS}")
    for name in LAYERS:
        config = upgrade_config(site, name)
        entries = upgrades.get(name, [])
        if not config:
            if entries:
                messages.append(f"{name}: {len(entries)} entries but CityDressing has no fabric.upgrades.{name}")
            continue
        props = config.get("props") or []
        placed = 0
        for index, entry in enumerate(entries, start=1):
            label = f"{name} {index} ({number(entry['x'])}, {number(entry['z'])})"
            messages += anchor_messages(site, label, entry, props, parcels, levels, polys)
            if placed_at_full(site, entry, levels):
                placed += 1
            point = (entry["x"], entry["z"])
            if abs(point[0]) > site.era.half_x - CHECK_TREE_EDGE + EPS or abs(point[1]) > site.era.half_z - CHECK_TREE_EDGE + EPS:
                messages.append(f"{label}: within {CHECK_TREE_EDGE} of the plot edge")
            if name == "trees":
                messages += tree_clearance(site, label, entry, polys, streets + spurs)
            elif name != CARTS:
                messages += item_clearance(site, plan, name, label, entry, props, polys, streets, spurs, everything)
            elif ground is not None:
                messages += cart_clearance(site, plan, label, entry, cart_size, ground, polys, districts)
        budget = config.get("budget")
        if isinstance(budget, (int, float)) and len(entries) > budget:
            messages.append(f"{name}: {len(entries)} entries, more than upgrades.{name}.budget {budget:g} -- near plots never draw the tail")
        if placed < need.get(name, 0):
            messages.append(f"{name}: {placed} placed with the whole era owned, need at least {need[name]}")
    trees = upgrades.get("trees", [])
    for i, tree in enumerate(trees):
        for j in range(i + 1, len(trees)):
            if math.dist((tree["x"], tree["z"]), (trees[j]["x"], trees[j]["z"])) < CHECK_TREE_SPACING - EPS:
                messages.append(f"trees {i + 1} and {j + 1}: within {CHECK_TREE_SPACING} of each other")
    for i, cart in enumerate(carts):
        for j in range(i + 1, len(carts)):
            apart = math.dist((cart["x"], cart["z"]), (carts[j]["x"], carts[j]["z"]))
            if apart < CHECK_CART_SPACING - EPS:
                messages.append(f"{CARTS} {i + 1} and {j + 1}: {apart:.2f} apart (need {CHECK_CART_SPACING:g})")
    cart_streets = {cart_street(site, parcels, cart) for cart in carts} - {None}
    if carts and len(cart_streets) < CHECK_CART_STREETS:
        messages.append(f"{CARTS}: on {len(cart_streets)} street(s), need at least {CHECK_CART_STREETS} different ones")
    return messages


def cart_street(site, parcels, cart):
    """The street (0-based polyline) a cart belongs to: its stretch's, or its parcel's address
    stretch's; None for an anchor the data cannot resolve."""
    if cart.get("anchor") == "stretch":
        return parcel_polyline(cart) if cart.get("stretch") in site.stretch_by_id else None
    parcel = cart.get("parcel")
    if isinstance(parcel, int) and 1 <= parcel <= len(parcels) and parcels[parcel - 1]["stretch"] in site.stretch_by_id:
        return parcel_polyline(parcels[parcel - 1])
    return None


def cart_clearance(site, plan, label, cart, extents, ground, polys, districts):
    """A parked cart (INTERFACES "Wave 2.0"): CartGround's clearances at the contract's margins,
    then its kind's own rule -- a kerb cart stands parallel to its stretch, a yard cart beside a lot
    of one of the plan's cart districts."""
    anchor = cart_anchor(site, polys, cart)
    if anchor is None:
        return []  # anchor_messages has said why
    centre = (cart["x"], cart["z"])
    messages = [f"{label}: {problem}" for problem in ground.problems(cart_body(extents, cart), centre, *anchor)]
    if cart["anchor"] == "stretch":
        st = site.network.stretches[site.stretch_by_id[cart["stretch"]]]
        along = streetplan.unit((st["b"][0] - st["a"][0], st["b"][1] - st["a"][1]))
        face = streetplan.facing(cart["rotationY"])  # a prop's length runs front to back
        if along is not None and abs(face[0] * along[1] - face[1] * along[0]) > CHECK_CART_PARALLEL:
            messages.append(f"{label}: a kerb cart stands parallel to its street, {cart['stretch']}")
    else:
        allowed = plan[CARTS]["yard"]["districts"]
        district = districts[cart["parcel"] - 1]
        if district not in allowed:
            messages.append(f"{label}: parcel {cart['parcel']} is a {district} lot, not one of {allowed}")
    return messages


def anchor_messages(site, label, entry, props, parcels, levels, polys):
    messages = []
    variant = entry.get("variant")
    if not (isinstance(variant, int) and 1 <= variant <= len(props)):
        messages.append(f"{label}: variant {variant!r} is not 1 to {len(props)}")
    if not entry.get("scale", 0) > 0:
        messages.append(f"{label}: scale must be positive")
    anchor = entry.get("anchor")
    if anchor not in ANCHORS:
        messages.append(f"{label}: anchor {anchor!r} is not one of {ANCHORS}")
    elif anchor == "stretch":
        if "parcel" in entry:
            messages.append(f"{label}: a stretch entry names a parcel")
        stretch = site.stretch_by_id.get(entry.get("stretch"))
        if stretch is None:
            messages.append(f"{label}: stretch {entry.get('stretch')!r} is not a piece of this network")
        elif stretch not in site.drawn:
            messages.append(f"{label}: stretch {entry['stretch']} is never drawn, so it is never placed")
    else:
        if "stretch" in entry:
            messages.append(f"{label}: a parcel entry names a stretch")
        parcel = entry.get("parcel")
        if not (isinstance(parcel, int) and 1 <= parcel <= len(parcels)):
            messages.append(f"{label}: parcel {parcel!r} is not a parcel index")
        elif levels[parcel - 1] < BUILT_LEVEL:
            messages.append(f"{label}: parcel {parcel} never becomes a house, so it is never placed")
    return messages


def tree_clearance(site, label, tree, polys, lanes):
    """A town tree: at least a stud from every parcel, slot footprint, pad, marker and lamp, off the
    walker and cart lanes, and anchored to the nearest parcel when it names one (wave 1c)."""
    messages = []
    point = (tree["x"], tree["z"])
    solids = [(f"parcel {i}", poly) for i, poly in enumerate(polys, start=1)]
    solids += [(f"the {slot_id} footprint", poly) for slot_id, poly in site.slot_polys.items()]
    solids += [(f"the {slot_id} pad", poly) for slot_id, poly in site.pad_polys.items()]
    solids += [(f"the {slot_id} marker", poly) for slot_id, poly in site.marker_polys.items()]
    solids += [(f"lamp {i}", poly) for i, poly in enumerate(site.lamps, start=1)]
    for what, poly in solids:
        if not point_box_apart(point, box_of(poly), CHECK_TREE) and point_gap(point, poly) < CHECK_TREE - EPS:
            messages.append(f"{label}: {point_gap(point, poly):.2f} from {what} (need {CHECK_TREE})")
    for what, a, b in lanes:
        d, _ = streetplan.point_segment_distance(point, a, b)
        if d < site.lane_clear - EPS:
            messages.append(f"{label}: {d:.2f} from {what}, on its walker or cart lane (need {site.lane_clear:g})")
    if tree.get("anchor") == "parcel" and isinstance(tree.get("parcel"), int) and 1 <= tree["parcel"] <= len(polys):
        parcel = tree["parcel"]
        nearest = nearest_parcel(point, [{"poly": poly} for poly in polys])
        if nearest != parcel and point_gap(point, polys[nearest - 1]) < point_gap(point, polys[parcel - 1]) - EPS:
            messages.append(f"{label}: anchored to parcel {parcel}, but parcel {nearest} is nearer")
    return messages


def item_clearance(site, plan, layer, label, entry, props, polys, streets, spurs, everything):
    """A flower or banner: its footprint (a bunting: each post) keeps a walker's reach off every
    street and spur, stays off every lot (a parcel-anchored planter may lean into its own house's
    front by CHECK_OWN_LOT), every built landmark, pad, marker and lamp, and apart from other entries.
    A bunting's string is overhead and exempt; its posts are not, and no tree stands under it."""
    messages = []
    variant = entry.get("variant")
    if not (isinstance(variant, int) and 1 <= variant <= len(props)):
        return messages
    prop = props[variant - 1]
    bunting = layer == "banners" and prop == plan["banners"]["bunting"]["prop"]
    if bunting:
        post = plan["banners"]["bunting"]["post"]
        shapes = [streetplan.square(p, post, post, entry["rotationY"]) for p in bunting_posts(plan, entry)]
    else:
        footprints = plan[layer]["footprints"]
        if prop not in footprints:
            return [f"{label}: the plan has no footprint for {prop}"]
        shapes = [item_poly(plan, layer, prop, entry["x"], entry["z"], entry["rotationY"], entry["scale"])]
    own = entry.get("parcel") if entry.get("anchor") == "parcel" else None
    solids = [(f"the {slot_id} extents", poly) for slot_id, (poly, _) in site.landmark_polys.items()]
    solids += [(f"the {slot_id} pad", poly) for slot_id, poly in site.pad_polys.items()]
    solids += [(f"the {slot_id} marker", poly) for slot_id, poly in site.marker_polys.items()]
    solids += [(f"lamp {i}", poly) for i, poly in enumerate(site.lamps, start=1)]
    for shape in shapes:
        box = box_of(shape)
        for what, a, b in streets:
            d = segment_gap(a, b, shape)
            if d < site.walker_street - EPS:
                messages.append(f"{label}: {d:.2f} from {what}, inside the walker reach (need {site.walker_street:g})")
        for what, a, b in spurs:
            d = segment_gap(a, b, shape)
            if d < site.walker_spur - EPS:
                messages.append(f"{label}: {d:.2f} from {what}, inside the walker reach (need {site.walker_spur:g})")
        for index, lot in enumerate(polys, start=1):
            if boxes_apart(box, box_of(lot), 0.0):
                continue
            if index == own:
                if not polygon_within(shape, lot, CHECK_OWN_LOT):
                    messages.append(f"{label}: leans more than {CHECK_OWN_LOT} into its own parcel {index}")
            elif gap(shape, lot) <= 0:
                messages.append(f"{label}: stands on parcel {index}")
        for what, poly in solids:
            if not boxes_apart(box, box_of(poly), 0.0) and gap(shape, poly) <= 0:
                messages.append(f"{label}: stands on {what}")
    if bunting:
        a, b = bunting_posts(plan, entry)
        for other_layer, other in everything:
            if other_layer == "trees" and streetplan.point_segment_distance((other["x"], other["z"]), a, b)[0] < CHECK_BUNTING_TREE - EPS:
                messages.append(f"{label}: a tree at ({number(other['x'])}, {number(other['z'])}) stands under the string")
    for other_layer, other in everything:
        if other is entry:
            continue
        if math.dist((entry["x"], entry["z"]), (other["x"], other["z"])) < CHECK_ITEM_SPACING - EPS:
            messages.append(f"{label}: within {CHECK_ITEM_SPACING} of {other_layer} entry at ({number(other['x'])}, {number(other['z'])})")
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
    singles_allowed = wild_single_props(plan["wild"])
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
    if plan["wild"].get("pattern") == FIELDS:
        messages += field_messages(site, plan, wild)
    return messages


def wild_single_props(wild):
    """Every prop the plan may write as a `single`, whichever pattern it lays."""
    loose = wild.get("singles") or {}
    names = {prop for pool in ("trees", "meadow", "props") for prop in loose.get(pool, ())}
    names |= set(((wild.get("skirt") or {}).get("singles") or {}).get("props", ()))
    names |= {landmark["prop"] for landmark in wild.get("landmarks") or []}
    if wild.get("poles") is not None:
        names.add(wild["poles"]["prop"])
    return names


def field_messages(site, plan, entries):
    """The field pattern's own rules (INTERFACES "Wave 2.1"): fields at scale 1, square to the grid,
    wholly on the plot or wholly off it and off each other; the skirt-only props (landmarks and the
    skirt's shelterbelts, too wide for a single's one-point clearing test) past the edge; no single
    in a field; and clearing margins wide enough that a quarter left standing never reaches into
    what cleared its neighbour."""
    wild = plan["wild"]
    messages = []
    plot = plot_rect(site)
    landmarks = landmark_polys(wild)
    # A prop the plan lays past the edge and never on the plot is a skirt-only prop.
    plot_props = set((wild.get("singles") or {}).get("props", ())) | ({wild["poles"]["prop"]} if wild.get("poles") is not None else set())
    skirt_only = (set(((wild["skirt"].get("singles") or {}).get("props", ()))) | {landmark["prop"] for landmark, _, _ in landmarks}) - plot_props
    fields, points = [], []
    for index, item in enumerate(entries, start=1):
        label = f"wild {index} ({number(item['x'])}, {number(item['z'])})"
        if item["kind"] != "clump":
            points.append((label, (item["x"], item["z"])))
            if item.get("prop") in skirt_only and not item["skirt"]:
                messages.append(f"{label}: {item['prop']} is a skirt-only prop but stands on the plot, where it would be cleared by one point")
            continue
        poly = field_poly(wild, item["x"], item["z"], item["rotationY"])
        fields.append((label, poly, box_of(poly)))
        if item["scale"] != 1:
            messages.append(f"{label}: a field is laid at scale 1, not {number(item['scale'])}")
        turn = (item["rotationY"] - wild["grid"]["angle"]) % QUARTER_TURN
        if min(turn, QUARTER_TURN - turn) > EPS:
            messages.append(f"{label}: turned {number(item['rotationY'])}, not the grid's angle plus quarter turns")
        if item["skirt"] and gap(poly, plot) <= 0:
            messages.append(f"{label}: a skirt field reaches onto the plot base")
        if not item["skirt"] and not on_plot(site, poly, 0.0):
            messages.append(f"{label}: a field of the plot hangs over its edge")
    for i, (label, poly, box) in enumerate(fields):
        for other, other_poly, other_box in fields[i + 1 :]:
            if not boxes_apart(box, other_box, 0.0) and gap(poly, other_poly) <= 0:
                messages.append(f"{label}: overlaps the field {other}")
        for what, point in points:
            if not point_box_apart(point, box, 0.0) and streetplan.point_in_polygon(point, poly):
                messages.append(f"{what}: stands in the field {label}")
    for landmark, _, rect in landmarks:
        if gap(rect, plot) <= 0:
            messages.append(f"wild: the landmark {landmark['prop']} at cell {landmark['cell']} stands on the plot; landmarks belong to the skirt")
        for label, poly, box in fields:
            if not boxes_apart(box, box_of(rect), 0.0) and gap(poly, rect) <= 0:
                messages.append(f"{label}: overlaps the landmark {landmark['prop']}")
    # IsCleared takes a quarter down when its centre comes within margin + quarterRadius of what
    # clears; a quarter still standing is a square whose corner reaches its half-diagonal that way.
    reach = wild["clumps"]["size"] / 4 * math.sqrt(2)
    least = min(site.config["clear"].values())
    radius = site.config["wild"]["quarterRadius"]
    if least + radius < reach - EPS:
        messages.append(
            f"wild: clear margin {least:g} + quarterRadius {radius:g} is under a quarter-field's half-diagonal "
            f"{reach:.2f}, so a standing quarter can overlap what cleared its neighbour"
        )
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
    messages += upgrade_messages(site, plan, doc)
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


def flower_mix(entries):
    counts = {}
    for entry in entries:
        counts[entry["variant"]] = counts.get(entry["variant"], 0) + 1
    return ", ".join(f"variant {k}: {v}" for k, v in sorted(counts.items()))


def summary(era_name, doc):
    parcels, wild = doc["parcels"], doc["wild"]
    upgrades = doc.get("upgrades", {})
    trees = upgrades.get("trees", [])
    by_row = {row: sum(1 for p in parcels if p["row"] == row) for row in range(1, MAX_ROW + 1)}
    by_size = {size: sum(1 for p in parcels if p["size"] == size) for size in SIZES}
    clumps = [w for w in wild if w["kind"] == "clump"]
    singles = [w for w in wild if w["kind"] == "single"]
    kinds = {}
    for tree in trees:
        kinds[tree_kind(tree)] = kinds.get(tree_kind(tree), 0) + 1
    carts = upgrades.get(CARTS, [])
    kerb = sum(1 for cart in carts if cart.get("anchor") == "stretch")
    return (
        f"{era_name}: {len(parcels)} parcels (rows {by_row[1]}/{by_row[2]}/{by_row[3]}; "
        f"{by_size['narrow']} narrow, {by_size['small']} small, {by_size['medium']} medium); {len(trees)} town trees "
        f"({', '.join(f'{k} {v}' for k, v in sorted(kinds.items()))}); {len(upgrades.get('flowers', []))} flowers "
        f"({flower_mix(upgrades.get('flowers', []))}); {len(upgrades.get('banners', []))} banners "
        f"({flower_mix(upgrades.get('banners', []))}); {len(carts)} carts (kerb {kerb}, yard {len(carts) - kerb}); "
        f"wild {len(wild)}: "
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
    doc = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {"parcels": [], "upgrades": {}, "wild": []}
    messages = check_document(args.era, doc)
    print(summary(args.era, doc))
    for message in messages:
        print(f"   VIOLATION: {message}")
    print(f"{len(messages)} violations")
    return 1 if messages else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
