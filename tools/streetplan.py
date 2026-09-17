#!/usr/bin/env python
"""Top-down street-plan check for the M9 city dressing (docs/INTERFACES.md "M9 contracts",
"Street-plan amendments" and "Wave 1b — natural paths").

Parses src/shared/Layouts/<Era>.luau and mirrors the client's road rules: spurs from the slot
anchor along the facing onto the nearest spine; the visible spine as the union of shortest paths
from the entrance (polyline 1, point 1) to every drawn spur's join point; meandered pieces on
near plots. It checks every clearance, reachability and budget rule and draws one PNG per era to
assets/testfit/out/<Era>/streetplan.png so the plan can be approved without Studio.

The network, the shortest-path tree and the budget are a line-for-line mirror of
src/client/City/RoadGraph.luau (buildNetwork, buildShortestPaths, allocate); see class Network.
When a plan exceeds a budget the client drops roads silently, so the budget check counts what
the client *reserves* for the whole layout (every stretch, spur and bend node, drawn or not),
not what happens to be visible at full ownership. Change RoadGraph and this file together.
The PNG's meander is a visual stand-in (different noise, node-distance taper): judge shape and
widths from it, never exact clearance near nodes.

Numbers come from their owners, never from this file: road width, meander, tree rules and budgets
from Config/CityDressing.json, slot and prop footprints from the testfit blueprints (contract
defaults 9x9 / monument 14x14 when a blueprint has none), pad and plot sizes from the layout, and
the purchase order and tier times from tools/sim_economy.py's greedy player. The only tool-local
numbers are the contract's own rule values and the preview's drawing constants, named below.

Usage:
  py tools/streetplan.py                # Village and Boomtown (wave 1)
  py tools/streetplan.py Metropolis     # any era(s) by name
Exit code 1 when any violation is found.
"""

from __future__ import annotations

import importlib.util
import json
import math
import random
import re
import sys
from collections import namedtuple
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

REPO_ROOT = Path(__file__).resolve().parent.parent
LAYOUTS_DIR = REPO_ROOT / "src" / "shared" / "Layouts"
ERAS_DIR = REPO_ROOT / "src" / "shared" / "Config" / "Eras"
CITY_CONFIG_PATH = REPO_ROOT / "src" / "shared" / "Config" / "CityDressing.json"
BLUEPRINTS_DIR = REPO_ROOT / "tools" / "testfit" / "blueprints"
OUT_DIR = REPO_ROOT / "assets" / "testfit" / "out"
SIM_PATH = REPO_ROOT / "tools" / "sim_economy.py"

DEFAULT_ERAS = ("Village", "Boomtown")

# Contract rule values (INTERFACES.md "Layouts" and amendments), not game tunables.
SLOT_FOOTPRINT_DEFAULT = 9
MONUMENT_FOOTPRINT_DEFAULT = 14
SPINE_EXTRA_CLEARANCE = 1  # spine clear of slots/pads/Sign by width/2 (+ meander) + this
LOT_SLOT_CLEARANCE = 6
STREET_COUNT = (2, 5)
LOT_COUNT = (8, 12)
LOT_TIERS = (2, 5)
PLAZA_COUNT = (1, 2)
PLAZA_TIERS = (3, 5)
ZONE_COUNT = (3, 6)
# Amendment P1 (INTERFACES "Street-plan amendments"): slots whose model is itself a road piece may
# lie under a spine, pads included. Boomtown's main street is exactly one road wide between the
# storefront pads and these slots stand on its centreline. P2 (a 1-point spur = no spur) needs
# no table.
STREET_FURNITURE = {
    # P1 road-piece slots, plus P3: the monument on the main-street centreline and the decor
    # slot overlapping it (INTERFACES "Street-plan amendments").
    "Boomtown": ("paveMainStreet", "streetlampRow", "trafficLights", "clockTower", "fireHydrant"),
}
# A lot "faces the road" when a spine centreline lies within this many studs of its front edge.
LOT_FRONT_REACH = 10
# The entrance sits on the front (hub) edge, near the Sign.
ENTRANCE_EDGE_REACH = 8
ENTRANCE_SIGN_REACH = 30
EDGE_MARGIN = 1  # every road piece (centreline + width/2 + meander) stays this far inside the plot
MIN_LENGTH = 0.05
# RoadGraph constants, mirrored so the tool's network is the client's network.
NODE_KEY_SCALE = 10  # nodes merge on a 1/NODE_KEY_SCALE stud grid
STRAIGHT_DOT = 0.999  # consecutive directions at least this aligned are straight, not a bend
FLOAT32_SLACK = 1e-4  # piece counts within this of a .5 rounding boundary count high (see piece_count)
# city-kit-roads tile exits at rotY 0 (x, z): the T junction opens to -X, +X, +Z; the bend to -X, +Z.
JUNCTION_EXITS = ((-1.0, 0.0), (1.0, 0.0), (0.0, 1.0))
BEND_EXITS = ((-1.0, 0.0), (0.0, 1.0))
# Spurs longer than this (anchor to join, ~11 studs of it under the building and pad) are listed so
# "every path reads as a short front path" can be judged.
LONG_SPUR = 22

# Preview-only drawing constants.
PX_PER_STUD = 8
MARGIN_PX = 60
LEGEND_PX = 360
SAMPLE_STEP = 0.4
TIER_COLOURS = {
    1: (214, 69, 65),
    2: (235, 140, 52),
    3: (214, 190, 40),
    4: (70, 160, 80),
    5: (60, 110, 200),
}
NEVER_COLOUR = (150, 150, 150)

# --------------------------------------------------------------------------
# Luau subset parser (tables, numbers, strings, booleans, Vector3/Color3 constructors)
# --------------------------------------------------------------------------

TOKEN_RE = re.compile(
    r"\s*(?:(--\[\[.*?\]\])|(--[^\n]*)|([A-Za-z_][A-Za-z0-9_.:]*)|(-?\d+(?:\.\d+)?)|"
    r'("(?:[^"\\]|\\.)*")|(.))',
    re.S,
)


def tokenize(text):
    tokens = []
    for match in TOKEN_RE.finditer(text):
        block, line, name, number, string, other = match.groups()
        if block or line:
            continue
        if name is not None:
            tokens.append(("name", name))
        elif number is not None:
            tokens.append(("number", float(number)))
        elif string is not None:
            tokens.append(("string", json.loads(string)))
        elif other is not None and not other.isspace():
            tokens.append(("sym", other))
    return tokens


class Parser:
    def __init__(self, tokens):
        self.tokens = tokens
        self.pos = 0

    def peek(self, offset=0):
        index = self.pos + offset
        return self.tokens[index] if index < len(self.tokens) else ("eof", None)

    def take(self, kind=None, value=None):
        token = self.peek()
        if (kind is not None and token[0] != kind) or (value is not None and token[1] != value):
            raise ValueError(f"expected {kind} {value!r}, got {token!r} at token {self.pos}")
        self.pos += 1
        return token

    def value(self):
        kind, val = self.peek()
        if kind == "sym" and val == "{":
            return self.table()
        if kind == "number":
            self.pos += 1
            return val
        if kind == "string":
            self.pos += 1
            return val
        if kind == "name":
            self.pos += 1
            if val in ("true", "false"):
                return val == "true"
            if val == "nil":
                return None
            if val in ("Vector3.new", "Color3.fromRGB", "Color3.new"):
                self.take("sym", "(")
                args = []
                while self.peek() != ("sym", ")"):
                    args.append(self.value())
                    if self.peek() == ("sym", ","):
                        self.pos += 1
                self.take("sym", ")")
                return tuple(args)
            raise ValueError(f"unsupported identifier {val!r}")
        raise ValueError(f"unexpected token {self.peek()!r}")

    def table(self):
        self.take("sym", "{")
        mapping, array = {}, []
        while self.peek() != ("sym", "}"):
            if self.peek()[0] == "name" and self.peek(1) == ("sym", "="):
                key = self.take("name")[1]
                self.take("sym", "=")
                mapping[key] = self.value()
            else:
                array.append(self.value())
            if self.peek()[0] == "sym" and self.peek()[1] in (",", ";"):
                self.pos += 1
        self.take("sym", "}")
        if mapping and array:
            raise ValueError("mixed table")
        return array if array else mapping


def parse_layout(path):
    text = path.read_text(encoding="utf-8")
    body = text[text.index("return") + len("return") :]
    return Parser(tokenize(body)).value()


# --------------------------------------------------------------------------
# Geometry (plot-local x/z studs; Y is ignored)
# --------------------------------------------------------------------------


def facing(rotation_y):
    """CFrame.Angles(0, rad(r), 0):VectorToWorldSpace(0, 0, -1) on the XZ plane."""
    rad = math.radians(rotation_y)
    # Rounded so axis-aligned facings print as whole studs instead of 1e-16 noise.
    return (round(-math.sin(rad), 12) + 0.0, round(-math.cos(rad), 12) + 0.0)


def square(center, size_x, size_z, rotation_y):
    """Corners of a rectangle rotated like a Roblox part (local X right, local -Z front)."""
    rad = math.radians(rotation_y)
    right = (math.cos(rad), -math.sin(rad))
    front = facing(rotation_y)
    hx, hz = size_x / 2, size_z / 2
    corners = []
    for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        corners.append(
            (
                center[0] + right[0] * hx * sx - front[0] * hz * sz,
                center[1] + right[1] * hx * sx - front[1] * hz * sz,
            )
        )
    return corners


SpineHit = namedtuple("SpineHit", "point polyline segment t distance")


def unit(v):
    length = math.hypot(v[0], v[1])
    return None if length < MIN_LENGTH else (v[0] / length, v[1] / length)


def lerp(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)


def node_key(p):
    """RoadGraph.keyFor, including Luau math.round's half-away-from-zero."""
    return (round_half(p[0] * NODE_KEY_SCALE), round_half(p[1] * NODE_KEY_SCALE))


def round_half(x):
    return math.floor(x + 0.5) if x >= 0 else math.ceil(x - 0.5)


def segment_t(a, b, p):
    """The clamped parameter ClosestOnSegment returns alongside the closest point."""
    dx, dz = b[0] - a[0], b[1] - a[1]
    length_sq = dx * dx + dz * dz
    if length_sq == 0:
        return 0.0
    return max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dz) / length_sq))


def nearest_on_spine(polylines, point, skip=None, ahead_of=None, face=None):
    """RoadGraph.nearestOnSpine: the single nearest point on any spine segment, optionally
    skipping one polyline and optionally ignoring points behind `ahead_of` along `face`."""
    best = None
    for index, street in enumerate(polylines):
        if index == skip:
            continue
        for segment, (a, b) in enumerate(polyline_segments(street)):
            distance, closest = point_segment_distance(point, a, b)
            if ahead_of is not None and face is not None:
                if (closest[0] - ahead_of[0]) * face[0] + (closest[1] - ahead_of[1]) * face[1] < -MIN_LENGTH:
                    continue
            if best is None or distance < best.distance:
                best = SpineHit(closest, index, segment, segment_t(a, b, closest), distance)
    return best


def tile_rotation(arms, exits):
    """RoadGraph.tileRotation: the quarter turn about Y lining a kit tile's exits up with the arms
    meeting at a node, or None when the geometry is not that tile."""
    if len(arms) != len(exits):
        return None
    for quarter in range(4):
        angle = quarter * math.pi / 2
        cos_a, sin_a = math.cos(angle), math.sin(angle)
        if all(
            any(arm[0] * (cos_a * ex + sin_a * ez) + arm[1] * (-sin_a * ex + cos_a * ez) >= STRAIGHT_DOT for arm in arms)
            for ex, ez in exits
        ):
            return quarter
    return None


def point_segment_distance(p, a, b):
    ax, az = a
    bx, bz = b
    dx, dz = bx - ax, bz - az
    length_sq = dx * dx + dz * dz
    t = 0.0 if length_sq == 0 else max(0.0, min(1.0, ((p[0] - ax) * dx + (p[1] - az) * dz) / length_sq))
    cx, cz = ax + t * dx, az + t * dz
    return math.hypot(p[0] - cx, p[1] - cz), (cx, cz)


def cross(o, a, b):
    return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])


def segments_intersect(a, b, c, d):
    d1, d2 = cross(c, d, a), cross(c, d, b)
    d3, d4 = cross(a, b, c), cross(a, b, d)
    return (d1 * d2 < 0) and (d3 * d4 < 0)


def point_in_polygon(p, polygon):
    inside = False
    count = len(polygon)
    for i in range(count):
        a, b = polygon[i], polygon[(i + 1) % count]
        if (a[1] > p[1]) != (b[1] > p[1]):
            x = a[0] + (p[1] - a[1]) * (b[0] - a[0]) / (b[1] - a[1])
            if p[0] < x:
                inside = not inside
    return inside


def segment_polygon_distance(a, b, polygon):
    if point_in_polygon(a, polygon) or point_in_polygon(b, polygon):
        return 0.0
    edges = [(polygon[i], polygon[(i + 1) % len(polygon)]) for i in range(len(polygon))]
    best = math.inf
    for c, d in edges:
        if segments_intersect(a, b, c, d):
            return 0.0
        best = min(
            best,
            point_segment_distance(a, c, d)[0],
            point_segment_distance(b, c, d)[0],
            point_segment_distance(c, a, b)[0],
            point_segment_distance(d, a, b)[0],
        )
    return best


def polygon_edges(polygon):
    return [(polygon[i], polygon[(i + 1) % len(polygon)]) for i in range(len(polygon))]


def polygon_polygon_distance(p, q):
    best = math.inf
    for i in range(len(p)):
        best = min(best, segment_polygon_distance(p[i], p[(i + 1) % len(p)], q))
        if best == 0:
            return 0.0
    return best


def point_polygon_distance(p, polygon):
    return segment_polygon_distance(p, p, polygon)


def polyline_segments(points):
    return [(points[i], points[i + 1]) for i in range(len(points) - 1)]


# --------------------------------------------------------------------------
# Era model
# --------------------------------------------------------------------------


def xz(vector):
    return (vector[0], vector[2])


def blueprint_footprint(era_name, model_name, default):
    path = BLUEPRINTS_DIR / era_name / f"{model_name}.json"
    if path.exists():
        footprint = json.loads(path.read_text(encoding="utf-8")).get("footprint")
        if footprint:
            return footprint[0], footprint[1]
    return default, default


def prop_footprint(era_name, prop_names, fallback):
    """Largest footprint among the named props, so a lot fits whichever house the seed picks."""
    best = None
    for name in prop_names:
        path = BLUEPRINTS_DIR / "_props" / era_name / f"{name}.json"
        if not path.exists():
            continue
        footprint = json.loads(path.read_text(encoding="utf-8")).get("footprint")
        if footprint and (best is None or footprint[0] * footprint[1] > best[0] * best[1]):
            best = (footprint[0], footprint[1])
    return best or fallback


def load_era_config(era_name):
    for path in ERAS_DIR.glob("*.json"):
        config = json.loads(path.read_text(encoding="utf-8"))
        if config["name"] == era_name:
            return config
    raise SystemExit(f"no era config named {era_name}")


def load_sim():
    spec = importlib.util.spec_from_file_location("sim_economy", SIM_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def greedy_buy_tiers(era_name, city):
    """slotId -> growth tier right after the greedy player buys it (lap 1, legacy carried in from
    the earlier eras), so the preview can colour each stretch by the tier it first appears at."""
    sim = load_sim()
    game = sim.load_game_config()
    legacy = 0
    for era in sim.load_eras():
        result = sim.simulate_era(era, game, legacy, "greedy", city=city)
        if era["name"] == era_name:
            tiers = {}
            for slot_id, t in result.slot_order:
                tiers[slot_id] = max(1, sum(1 for reached in result.tier_times if reached is not None and reached <= t))
            return tiers
        legacy += result.legacy_gained
    return {}


class Era:
    def __init__(self, name, city):
        self.name = name
        self.furniture = set(STREET_FURNITURE.get(name, ()))
        self.layout = parse_layout(LAYOUTS_DIR / f"{name}.luau")
        self.config = load_era_config(name)
        self.dressing = city["eras"][name]
        self.city = city
        road = self.dressing["road"]
        self.width = road["width"]
        self.attach_radius = self.width / 2 + MIN_LENGTH  # RoadGraph's attachRadius
        self.meander = road.get("meander")
        self.amplitude = self.meander["amplitude"] if self.meander else 0.0
        plot = self.layout["plotSize"]
        self.half_x, self.half_z = plot[0] / 2, plot[2] / 2
        pad_size = self.layout["padSize"]
        self.pad_size = (pad_size[0], pad_size[2])
        self.pad_offset = self.layout["padOffset"]
        self.sign = (0.0, -self.half_z)
        # Sign post is padSize.Y thick (PlotService), straddling the front-edge centre.
        self.sign_poly = square(self.sign, pad_size[1], pad_size[1], 0)

        self.slots = []
        for slot in self.config["slots"]:
            entry = self.layout["slots"].get(slot["id"])
            if entry is None:
                continue
            default = MONUMENT_FOOTPRINT_DEFAULT if slot["type"] == "monument" else SLOT_FOOTPRINT_DEFAULT
            fx, fz = blueprint_footprint(name, slot["modelName"], default)
            position = xz(entry["position"])
            rotation = entry["rotationY"]
            face = facing(rotation)
            if "padPosition" in entry:
                pad = xz(entry["padPosition"])
            else:
                pad = (position[0] + face[0] * self.pad_offset, position[1] + face[1] * self.pad_offset)
            self.slots.append(
                {
                    "id": slot["id"],
                    "type": slot["type"],
                    "position": position,
                    "rotation": rotation,
                    "facing": face,
                    "footprint": square(position, fx, fz, rotation),
                    "pad": pad,
                    "pad_poly": square(pad, self.pad_size[0], self.pad_size[1], rotation),
                    "spur_override": [xz(p) for p in entry["spur"]] if "spur" in entry else None,
                }
            )

        self.streets = [[xz(p) for p in street["points"]] for street in self.layout.get("streets", [])]
        self.street_y = [[p[1] for p in street["points"]] for street in self.layout.get("streets", [])]
        house_size = prop_footprint(name, self.dressing["houses"]["props"], (SLOT_FOOTPRINT_DEFAULT, SLOT_FOOTPRINT_DEFAULT))
        self.lots = []
        for lot in self.layout.get("lots", []):
            position = xz(lot["position"])
            self.lots.append(
                {
                    "position": position,
                    "rotation": lot["rotationY"],
                    "tier": lot["tier"],
                    "poly": square(position, house_size[0], house_size[1], lot["rotationY"]),
                    "depth": house_size[1],
                }
            )
        self.plazas = []
        for plaza in self.layout.get("plazas", []):
            position = xz(plaza["position"])
            size = prop_footprint(name, [plaza["prop"]], (12, 12))
            self.plazas.append(
                {
                    "position": position,
                    "rotation": plaza["rotationY"],
                    "tier": plaza["tier"],
                    "prop": plaza["prop"],
                    "poly": square(position, size[0], size[1], plaza["rotationY"]),
                }
            )
        self.zones = [
            {"center": xz(z["center"]), "radius": z["radius"], "count": int(z["count"])}
            for z in self.layout.get("treeZones", [])
        ]
        self.spurs = {slot["id"]: self.spur_for(slot) for slot in self.slots}

    def spine_segments(self):
        for index, street in enumerate(self.streets):
            for a, b in polyline_segments(street):
                yield index, a, b

    def spur_for(self, slot):
        """RoadGraph.routePoints plus the join step of buildNetwork (INTERFACES "Road routing"
        and Wave 1b): the anchor, then along the facing until level with the nearest spine point
        ahead of the pad (any spine point when none is ahead), then across onto it. A multi-point
        override gets the anchor prefixed; a one-point override is no spur (P2). The end is then
        attached to the single nearest spine point when that lies within attachRadius (width / 2),
        exactly as the client does, so a hand-authored override that stops just short of a street
        grows the same extra leg -- and the same extra road piece -- in the tool as in game."""
        face = slot["facing"]
        anchor = slot["position"]
        pad_edge = (slot["pad"][0] + face[0] * self.pad_size[1] / 2, slot["pad"][1] + face[1] * self.pad_size[1] / 2)
        override = slot["spur_override"]
        none = {"points": [], "override": override is not None, "none": True, "backwards": False, "joins": False, "hit": None}
        if override is not None and len(override) == 1:
            return none
        backwards = False
        if override is not None:
            points = list(override)
            if math.dist(points[0], anchor) > MIN_LENGTH:
                points.insert(0, anchor)
        else:
            hit = nearest_on_spine(self.streets, pad_edge, ahead_of=pad_edge, face=face) or nearest_on_spine(self.streets, pad_edge)
            if hit is None:
                return none
            target = hit.point
            along = (target[0] - anchor[0]) * face[0] + (target[1] - anchor[1]) * face[1]
            corner = (anchor[0] + face[0] * along, anchor[1] + face[1] * along)
            points = [anchor]
            for p in (corner, target):
                if math.dist(p, points[-1]) >= MIN_LENGTH:
                    points.append(p)
            backwards = (target[0] - pad_edge[0]) * face[0] + (target[1] - pad_edge[1]) * face[1] < -MIN_LENGTH
        hit = nearest_on_spine(self.streets, points[-1])
        joins = hit is not None and hit.distance <= self.attach_radius
        if joins:
            if hit.distance >= MIN_LENGTH:
                points.append(hit.point)
            else:
                points[-1] = hit.point
        return {
            "points": points,
            "override": override is not None,
            "none": False,
            "backwards": backwards,
            "joins": joins,
            "hit": hit if joins else None,
        }

    def spur_direction(self, slot_id):
        """Junction.direction: the unit heading of the spur's last leg, the facing as a fallback."""
        points = self.spurs[slot_id]["points"]
        direction = unit((points[-1][0] - points[-2][0], points[-1][1] - points[-2][1])) if len(points) >= 2 else None
        return direction or facing(next(s["rotation"] for s in self.slots if s["id"] == slot_id))


# --------------------------------------------------------------------------
# Road network (Wave 1b growth rule) -- a line-for-line mirror of RoadGraph.luau
# --------------------------------------------------------------------------


class Network:
    """Mirrors RoadGraph's buildNetwork, buildShortestPaths and allocate.

    Deliberate details, each one a place where a looser tool would pass a plan the client cannot
    draw (it drops roads silently when a budget is exceeded):
      * a polyline point splits and connects onto the *single nearest other* polyline within
        width / 2 (nearestOnSpine(..., skipPolyline)) -- never onto its own line, never onto a
        second line that also happens to be in reach;
      * a spur join splits the single nearest segment of any polyline;
      * a point off that line by more than MIN_LENGTH gets a short connector stretch, which is a
        road piece of its own group;
      * nodes are created in the client's order (all polyline points, then split points in
        segment order) and merged on the same 1 / NODE_KEY_SCALE stud grid, because Dijkstra's
        tie-break is "lowest node index wins", and the first parent to reach a node keeps it;
      * every stretch and every bend node is *reserved* in the budget whether or not it is ever
        drawn, so purchase order cannot change what fits.
    """

    def __init__(self, era):
        self.era = era
        polylines = era.streets
        self.nodes = []  # node index -> point, in the client's creation order
        self.node_by_key = {}
        self.node_stretches = []
        self.stretches = []
        self.groups = []  # group index -> stretch ids, in order along the group
        self.bend_nodes = []
        self.seen_pairs = set()
        for street in polylines:
            for point in street:
                self.node_at(point)

        splits = {}
        connectors = []
        for index, street in enumerate(polylines):
            for point in street:
                hit = nearest_on_spine(polylines, point, skip=index)
                if hit is None or hit.distance > era.attach_radius:
                    continue
                splits.setdefault((hit.polyline, hit.segment), []).append(hit.t)
                if hit.distance >= MIN_LENGTH:
                    connectors.append((point, hit.point, index))
        self.spur_ids = [slot_id for slot_id in sorted(era.spurs) if era.spurs[slot_id]["points"]]
        for slot_id in self.spur_ids:
            hit = era.spurs[slot_id]["hit"]
            if hit is not None:
                splits.setdefault((hit.polyline, hit.segment), []).append(hit.t)

        for index, street in enumerate(polylines):
            arc_base = 0.0
            for segment, (a, b) in enumerate(polyline_segments(street)):
                length = math.dist(a, b)
                params = sorted(splits.get((index, segment), []) + [0.0, 1.0])
                self.groups.append([])
                group_index = len(self.groups) - 1
                for t0, t1 in zip(params, params[1:]):
                    self.add_stretch(
                        group_index,
                        lerp(a, b, t0),
                        lerp(a, b, t1),
                        index,
                        segment,
                        t0,
                        t1,
                        arc_base + length * t0,
                    )
                arc_base += length
            for i in range(1, len(street) - 1):
                incoming = unit((street[i][0] - street[i - 1][0], street[i][1] - street[i - 1][1]))
                outgoing = unit((street[i + 1][0] - street[i][0], street[i + 1][1] - street[i][1]))
                if incoming and outgoing and incoming[0] * outgoing[0] + incoming[1] * outgoing[1] < STRAIGHT_DOT:
                    self.bend_nodes.append(self.node_at(street[i]))
        for start, end, index in connectors:
            self.groups.append([])
            self.add_stretch(len(self.groups) - 1, start, end, index, None, 0.0, 1.0, 0.0)

        self.junction_nodes = {}
        for slot_id in self.spur_ids:
            if era.spurs[slot_id]["joins"]:
                self.junction_nodes[slot_id] = self.node_by_key.get(node_key(era.spurs[slot_id]["points"][-1]))
        self.entrance = self.node_by_key.get(node_key(polylines[0][0])) if polylines and polylines[0] else None
        self.distance, self.parent = self.shortest_paths()

    # -- construction -------------------------------------------------------

    def node_at(self, point):
        key = node_key(point)
        node = self.node_by_key.get(key)
        if node is None:
            self.nodes.append(point)
            node = len(self.nodes) - 1
            self.node_by_key[key] = node
            self.node_stretches.append([])
        return node

    def add_stretch(self, group_index, a, b, polyline, segment, t0, t1, arc_start):
        length = math.dist(a, b)
        if length < MIN_LENGTH:
            return
        u, v = self.node_at(a), self.node_at(b)
        pair = (min(u, v), max(u, v))
        if u == v or pair in self.seen_pairs:
            return
        self.seen_pairs.add(pair)
        self.stretches.append(
            {
                "a": a,
                "b": b,
                "from": u,
                "to": v,
                "polyline": polyline,  # the line it takes its meander phase from
                "segment": segment,  # None for a connector between two polylines
                "t0": t0,
                "t1": t1,
                "length": length,
                "group": group_index,
                "arc_start": arc_start,
            }
        )
        stretch_id = len(self.stretches) - 1
        self.groups[group_index].append(stretch_id)
        self.node_stretches[u].append(stretch_id)
        self.node_stretches[v].append(stretch_id)

    # -- shortest paths -----------------------------------------------------

    def shortest_paths(self):
        """RoadGraph.buildShortestPaths: a scan, not a heap. Among equal distances the lowest node
        index wins, and a node keeps the first parent that reaches it, so two routes of exactly
        equal length resolve the same way here as in game. (Roblox Vector3 components are float32,
        so lengths can differ in the last bits; a tie that is only a tie in float64 could still
        fall the other way in game. Keep symmetric plans away from exact ties.)"""
        distance, parent = {}, {}
        if self.entrance is None:
            return distance, parent
        distance[self.entrance] = 0.0
        done = set()
        while True:
            best = None
            for node in range(len(self.nodes)):
                d = distance.get(node)
                if node not in done and d is not None and (best is None or d < distance[best]):
                    best = node
            if best is None:
                break
            done.add(best)
            for stretch_id in self.node_stretches[best]:
                stretch = self.stretches[stretch_id]
                other = stretch["to"] if stretch["from"] == best else stretch["from"]
                candidate = distance[best] + stretch["length"]
                known = distance.get(other)
                if known is None or candidate < known:
                    distance[other] = candidate
                    parent[other] = stretch_id
        return distance, parent

    def path_stretches(self, node):
        """Stretch ids from the entrance to `node` (the chain RoadGraph.reveal walks), or None."""
        if node is None or node not in self.distance:
            return None
        ids = []
        current = node
        while current != self.entrance:
            stretch_id = self.parent[current]
            ids.append(stretch_id)
            stretch = self.stretches[stretch_id]
            current = stretch["to"] if stretch["from"] == current else stretch["from"]
        return ids

    def near_distance(self, stretch_id):
        stretch = self.stretches[stretch_id]
        a, b = self.distance.get(stretch["from"]), self.distance.get(stretch["to"])
        return None if a is None or b is None else min(a, b)

    # -- kit tiles ----------------------------------------------------------

    def arms_at(self, node, slot_ids):
        """RoadGraph.armsAt: every direction a road can ever leave this node in."""
        point = self.nodes[node]
        arms = []

        def add(direction):
            if direction is None:
                return
            for arm in arms:
                if arm[0] * direction[0] + arm[1] * direction[1] >= STRAIGHT_DOT:
                    return
            arms.append(direction)

        for street in self.era.streets:
            for a, b in polyline_segments(street):
                if point_segment_distance(point, a, b)[0] >= MIN_LENGTH:
                    continue
                along = unit((b[0] - a[0], b[1] - a[1]))
                if along is None:
                    continue
                if math.dist(point, a) >= MIN_LENGTH:
                    add((-along[0], -along[1]))
                if math.dist(b, point) >= MIN_LENGTH:
                    add(along)
        for slot_id in slot_ids:
            direction = self.era.spur_direction(slot_id)
            add((-direction[0], -direction[1]))
        return arms

    def tiles(self):
        """node -> prop name for every junction/bend tile RoadGraph.allocate would place. Each is
        one piece of the straight budget; a node whose arms do not match the tile's exits (a
        4-way, a diagonal, a bend with a spur) gets none, exactly as tileRotation decides."""
        road = self.era.dressing["road"]
        junction_prop, bend_prop = road.get("junctionProp"), road.get("bendProp")
        junction_slots, junction_order = {}, []
        for slot_id in self.spur_ids:
            node = self.junction_nodes.get(slot_id)
            if node is None:
                continue
            if node not in junction_slots:
                junction_slots[node] = []
                junction_order.append(node)
            junction_slots[node].append(slot_id)
        placed = {}
        if bend_prop is not None:
            for node in self.bend_nodes:
                if node in junction_slots or node in placed:
                    continue
                if tile_rotation(self.arms_at(node, []), BEND_EXITS) is not None:
                    placed[node] = bend_prop
        if junction_prop is not None:
            for node in junction_order:
                if node in placed:
                    continue
                if tile_rotation(self.arms_at(node, junction_slots[node]), JUNCTION_EXITS) is not None:
                    placed[node] = junction_prop
        return placed

    # -- budget -------------------------------------------------------------

    def reserve(self):
        """What RoadGraph.allocate holds back for the whole layout, uncapped: (near, far, detail).

        allocate reserves for **everything the layout can ever draw**, not for what is visible at
        full ownership, and the near budget is spent **per stretch**, never per merged run -- the
        meander is cut per stretch. So:
          far  = per spine group 1 piece, or 2 when its visible part can be reached from both ends
                 (a group with no reachable stretch costs nothing) + one per spur leg + one tile;
          near = max(1, round(length / segmentLength)) per reachable stretch and per spur leg,
                 + one corner disc per interior spur point, + one disc per bend node.
        A total inside the budget means the greedy reservation fits everything; over it, the
        client drops the tail and a road ends in mid-air."""
        era = self.era
        spine_far = 0
        for stretch_ids in self.groups:
            toward_start = toward_end = reachable = False
            for stretch_id in stretch_ids:
                stretch = self.stretches[stretch_id]
                a, b = self.distance.get(stretch["from"]), self.distance.get(stretch["to"])
                if a is None or b is None:
                    continue
                reachable = True
                if a <= b:
                    toward_start = True
                else:
                    toward_end = True
            if reachable:
                spine_far += 2 if (toward_start and toward_end) else 1
        spur_far = sum(max(len(era.spurs[slot_id]["points"]) - 1, 0) for slot_id in self.spur_ids)
        tiles = self.tiles()
        detail = {"spineFar": spine_far, "spurFar": spur_far, "tiles": len(tiles)}
        far = spine_far + spur_far + len(tiles)
        if era.meander is None:
            detail.update({"spineNear": spine_far, "spurNear": spur_far, "bends": 0})
            return far, far, detail
        segment_length = era.meander["segmentLength"]
        spine_near = sum(
            piece_count(self.stretches[stretch_id]["length"], segment_length)
            for stretch_id in range(len(self.stretches))
            if self.near_distance(stretch_id) is not None
        )
        spur_near = 0
        for slot_id in self.spur_ids:
            points = era.spurs[slot_id]["points"]
            spur_near += max(len(points) - 2, 0)  # corner discs
            spur_near += sum(piece_count(math.dist(a, b), segment_length) for a, b in polyline_segments(points))
        bends = len(self.bend_nodes)  # one disc reserved per bend node, drawn or not
        lengths = [self.stretches[i]["length"] for i in range(len(self.stretches)) if self.near_distance(i) is not None]
        for slot_id in self.spur_ids:
            lengths += [math.dist(a, b) for a, b in polyline_segments(era.spurs[slot_id]["points"])]
        detail["boundary"] = sum(1 for length in lengths if on_rounding_boundary(length, segment_length))
        detail.update({"spineNear": spine_near, "spurNear": spur_near, "bends": bends})
        return spine_near + spur_near + bends, far, detail

    def drawn_bends(self, visible):
        """Bend discs actually drawn: RoadGraph.drawBends places one only when **every** stretch
        at the node is visible (the tool's old "both sides drawn" rule, now node-based so a
        connector arriving at the bend counts too). Reporting only -- the budget reserves all."""
        count = 0
        for node in self.bend_nodes:
            stretches = self.node_stretches[node]
            if stretches and all(stretch_id in visible for stretch_id in stretches):
                count += 1
        return count


def visible_network(era, network, buy_tiers):
    """stretch id -> tier it first appears at, plus the join points no path can reach."""
    visible, unreachable = {}, []
    for slot_id in network.spur_ids:
        join = era.spurs[slot_id]["points"][-1]
        stretch_ids = network.path_stretches(network.junction_nodes.get(slot_id))
        if stretch_ids is None:
            unreachable.append((slot_id, join))
            continue
        tier = buy_tiers.get(slot_id, 5)
        for stretch_id in stretch_ids:
            visible[stretch_id] = min(visible.get(stretch_id, tier), tier)
    return visible, unreachable


def piece_count(length, segment_length):
    """RoadGraph.pieceCount: the meander cuts every run into this many pieces, per stretch, with
    Luau math.round (half up). The client measures in float32 Vector3s, so a length sitting on a
    .5 boundary can land on either side in game; FLOAT32_SLACK resolves those toward the higher
    count so the budget check never under-reports."""
    return max(1, math.floor(length / max(segment_length, MIN_LENGTH) + 0.5 + FLOAT32_SLACK))


def on_rounding_boundary(length, segment_length):
    ratio = length / max(segment_length, MIN_LENGTH)
    return abs(ratio - math.floor(ratio) - 0.5) <= FLOAT32_SLACK


# --------------------------------------------------------------------------
# Checks
# --------------------------------------------------------------------------


def check(era, network, visible, unreachable):
    violations = []
    notes = []
    width = era.width
    half_road = width / 2 + era.amplitude
    spine_clear = half_road + SPINE_EXTRA_CLEARANCE

    def add(message):
        violations.append(message)

    if not STREET_COUNT[0] <= len(era.streets) <= STREET_COUNT[1]:
        add(f"streets: {len(era.streets)} polylines, need {STREET_COUNT[0]}-{STREET_COUNT[1]}")
    for index, ys in enumerate(era.street_y):
        if any(abs(y) > 1e-9 for y in ys):
            add(f"street {index + 1}: a point is not at Y 0")
    limit_x = era.half_x - half_road - EDGE_MARGIN
    limit_z = era.half_z - half_road - EDGE_MARGIN
    for index, street in enumerate(era.streets):
        if len(street) < 2:
            add(f"street {index + 1}: fewer than 2 points")
        for p in street:
            if abs(p[0]) > limit_x + 1e-9 or abs(p[1]) > limit_z + 1e-9:
                add(f"street {index + 1}: point {fmt(p)} leaves the plot (limit +/-{limit_x:g})")

    for index, a, b in era.spine_segments():
        for slot in era.slots:
            if slot["id"] in era.furniture:
                continue
            for what, poly in (("footprint", slot["footprint"]), ("pad", slot["pad_poly"])):
                d = segment_polygon_distance(a, b, poly)
                if d < spine_clear - 1e-6:
                    add(f"street {index + 1} {fmt(a)}->{fmt(b)}: {d:.2f} from {slot['id']} {what} (need {spine_clear:g})")
        d = segment_polygon_distance(a, b, era.sign_poly)
        if d < spine_clear - 1e-6:
            add(f"street {index + 1} {fmt(a)}->{fmt(b)}: {d:.2f} from the Sign (need {spine_clear:g})")

    if era.streets:
        entrance = era.streets[0][0]
        if entrance[1] > -era.half_z + ENTRANCE_EDGE_REACH or abs(entrance[0] - era.sign[0]) > ENTRANCE_SIGN_REACH:
            add(f"entrance {fmt(entrance)} is not on the front edge near the Sign")
    for slot_id, join in unreachable:
        add(f"spur {slot_id}: join point {fmt(join)} is not reachable from the entrance")
    never = [stretch_id for stretch_id in range(len(network.stretches)) if stretch_id not in visible]
    if never:
        length = sum(network.stretches[stretch_id]["length"] for stretch_id in never)
        notes.append(f"{len(never)} spine stretches ({length:.0f} studs) are never drawn (still reserved)")

    obstacles = []
    for slot in era.slots:
        if slot["id"] in era.furniture:
            continue
        obstacles.append((f"{slot['id']} footprint", slot["footprint"], slot["id"]))
        obstacles.append((f"{slot['id']} pad", slot["pad_poly"], slot["id"]))
    for i, lot in enumerate(era.lots):
        obstacles.append((f"lot {i + 1}", lot["poly"], None))
    for i, plaza in enumerate(era.plazas):
        obstacles.append((f"plaza {i + 1}", plaza["poly"], None))
    obstacles.append(("Sign", era.sign_poly, None))
    all_segments = [(a, b) for _, a, b in era.spine_segments()]
    longest = (0.0, None)
    for slot in era.slots:
        spur = era.spurs[slot["id"]]
        points = spur["points"]
        label = f"spur {slot['id']}{' (override)' if spur['override'] else ''}"
        if spur["none"]:
            if spur["override"]:
                notes.append(f"{label}: single point, no spur drawn (P2)")
            continue
        if spur["backwards"]:
            add(f"{label}: no spine ahead of the pad, the path runs back past its own building")
        end = points[-1]
        # The client only attaches a spur whose end is within attachRadius of a spine; anything
        # farther draws a path that joins nothing and reveals no spine.
        if not spur["joins"]:
            add(f"{label}: last point {fmt(end)} is farther than {era.attach_radius:.2g} from any spine, so it joins nothing")
        length = sum(math.dist(a, b) for a, b in polyline_segments(points))
        if length > longest[0]:
            longest = (length, slot["id"])
        if length > LONG_SPUR:
            notes.append(f"{label}: {length:.0f} studs long")
        for a, b in polyline_segments(points):
            if math.dist(a, b) < MIN_LENGTH:
                continue
            for name, poly, owner in obstacles:
                if owner == slot["id"]:
                    continue  # Wave 1b: a spur runs out from under its own building and pad
                d = segment_polygon_distance(a, b, poly)
                if d < half_road - 1e-6:
                    add(f"{label} {fmt(a)}->{fmt(b)}: cuts {name} ({d:.2f} < {half_road:g})")
        for p in points:
            if abs(p[0]) > era.half_x or abs(p[1]) > era.half_z:
                add(f"{label}: point {fmt(p)} leaves the plot")
    if longest[1] is not None:
        notes.append(f"longest spur: {longest[1]} {longest[0]:.0f} studs")

    # Only stretches some building's path draws exist (Wave 1b); at full ownership those and the
    # paths themselves are the roads a filler house can face, but never the part of a path still
    # under its own building or pad.
    drawn = [(network.stretches[stretch_id]["a"], network.stretches[stretch_id]["b"], ()) for stretch_id in visible]
    for slot in era.slots:
        own = (slot["footprint"], slot["pad_poly"])
        drawn += [(a, b, own) for a, b in polyline_segments(era.spurs[slot["id"]]["points"])]
    if not LOT_COUNT[0] <= len(era.lots) <= LOT_COUNT[1]:
        add(f"lots: {len(era.lots)}, need {LOT_COUNT[0]}-{LOT_COUNT[1]}")
    for i, lot in enumerate(era.lots):
        label = f"lot {i + 1} {fmt(lot['position'])}"
        if not LOT_TIERS[0] <= lot["tier"] <= LOT_TIERS[1]:
            add(f"{label}: tier {lot['tier']} outside {LOT_TIERS}")
        for slot in era.slots:
            d = point_polygon_distance(lot["position"], slot["footprint"])
            if d < LOT_SLOT_CLEARANCE - 1e-6:
                add(f"{label}: {d:.2f} from {slot['id']} footprint (need {LOT_SLOT_CLEARANCE})")
            if polygon_polygon_distance(lot["poly"], slot["footprint"]) <= 0:
                add(f"{label}: house overlaps {slot['id']}")
            if polygon_polygon_distance(lot["poly"], slot["pad_poly"]) < 1:
                add(f"{label}: house touches the {slot['id']} pad")
        if polygon_polygon_distance(lot["poly"], era.sign_poly) < 1:
            add(f"{label}: house touches the Sign")
        for _, a, b in era.spine_segments():
            if segment_polygon_distance(a, b, lot["poly"]) < half_road + 0.5:
                add(f"{label}: house sits on street {fmt(a)}->{fmt(b)}")
        for j, other in enumerate(era.lots):
            if j > i and polygon_polygon_distance(lot["poly"], other["poly"]) < 1:
                add(f"{label}: house overlaps lot {j + 1}")
        for j, plaza in enumerate(era.plazas):
            if polygon_polygon_distance(lot["poly"], plaza["poly"]) < 1:
                add(f"{label}: house overlaps plaza {j + 1}")
        for corner in lot["poly"]:
            if abs(corner[0]) > era.half_x - 1 or abs(corner[1]) > era.half_z - 1:
                add(f"{label}: house leaves the plot")
                break
        face = facing(lot["rotation"])
        front = (lot["position"][0] + face[0] * lot["depth"] / 2, lot["position"][1] + face[1] * lot["depth"] / 2)
        nearest = min((nearest_outside(front, a, b, own) for a, b, own in drawn), key=lambda item: item[0])
        facing_dot = (nearest[1][0] - front[0]) * face[0] + (nearest[1][1] - front[1]) * face[1]
        if nearest[0] > LOT_FRONT_REACH or facing_dot < 0:
            add(f"{label}: does not face a drawn road (nearest {nearest[0]:.1f} studs from its front)")

    if not PLAZA_COUNT[0] <= len(era.plazas) <= PLAZA_COUNT[1]:
        add(f"plazas: {len(era.plazas)}, need {PLAZA_COUNT[0]}-{PLAZA_COUNT[1]}")
    for i, plaza in enumerate(era.plazas):
        label = f"plaza {i + 1} {fmt(plaza['position'])}"
        if plaza["prop"] not in era.dressing["plazas"]["props"]:
            add(f"{label}: prop {plaza['prop']} not in eras.{era.name}.plazas.props")
        if not PLAZA_TIERS[0] <= plaza["tier"] <= PLAZA_TIERS[1]:
            add(f"{label}: tier {plaza['tier']} outside {PLAZA_TIERS}")
        for slot in era.slots:
            if polygon_polygon_distance(plaza["poly"], slot["footprint"]) < 1:
                add(f"{label}: overlaps {slot['id']}")
            if polygon_polygon_distance(plaza["poly"], slot["pad_poly"]) < 1:
                add(f"{label}: overlaps the {slot['id']} pad")
        for _, a, b in era.spine_segments():
            if segment_polygon_distance(a, b, plaza["poly"]) < half_road - 1e-6:
                add(f"{label}: sits on street {fmt(a)}->{fmt(b)}")

    total = sum(zone["count"] for zone in era.zones)
    max_count = era.dressing["trees"]["maxCount"]
    if not ZONE_COUNT[0] <= len(era.zones) <= ZONE_COUNT[1]:
        add(f"treeZones: {len(era.zones)}, need {ZONE_COUNT[0]}-{ZONE_COUNT[1]}")
    if total > max_count:
        add(f"treeZones: sum count {total} > trees.maxCount {max_count}")
    for i, zone in enumerate(era.zones):
        c = zone["center"]
        if abs(c[0]) > era.half_x or abs(c[1]) > era.half_z:
            add(f"tree zone {i + 1}: centre {fmt(c)} outside the plot")

    # RoadGraph.allocate reserves for the whole network up front -- every stretch, every spur and
    # every bend node, drawn or not -- so a plan is only safe when the *reserved* total fits.
    near, far, detail = network.reserve()
    budget = era.city.get("budget", {})
    if far > budget.get("roadPieces", math.inf):
        add(
            f"straight road pieces reserved {far} > budget.roadPieces {budget['roadPieces']} "
            f"(spine groups {detail['spineFar']}, spur legs {detail['spurFar']}, kit tiles {detail['tiles']}) "
            "-- the client would drop the far spine"
        )
    if era.meander is not None and near > budget.get("roadPiecesNear", math.inf):
        add(
            f"near road pieces reserved {near} > budget.roadPiecesNear {budget['roadPiecesNear']} "
            f"(spine {detail['spineNear']}, spurs {detail['spurNear']}, bend discs {detail['bends']}) "
            "-- the client would drop the far end of the meandered trail"
        )
    if era.meander is not None:
        notes.append(f"bend discs: {detail['bends']} reserved, {network.drawn_bends(visible)} drawn at full ownership")
        if detail["boundary"]:
            notes.append(
                f"{detail['boundary']} road run(s) sit exactly on a .5 piece-rounding boundary; counted high, "
                "the client may use one piece fewer each (float32)"
            )
    return violations, notes, near, far, detail


def nearest_outside(point, a, b, own):
    """Nearest point of segment a-b to point, ignoring the stretch inside any polygon in own."""
    if not own:
        return point_segment_distance(point, a, b)
    best = (math.inf, point)
    steps = max(1, int(math.dist(a, b) / 0.5))
    for step in range(steps + 1):
        t = step / steps
        q = (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
        if not any(point_in_polygon(q, poly) for poly in own):
            d = math.dist(point, q)
            if d < best[0]:
                best = (d, q)
    return best


def fmt(p):
    return f"({p[0]:g}, {p[1]:g})"


# --------------------------------------------------------------------------
# Tree scatter preview (same rejection rules as Scatter.luau; the RNG differs, so this shows
# where trees can land, not the exact in-game points)
# --------------------------------------------------------------------------


def scatter_trees(era):
    trees_cfg = era.dressing["trees"]
    clearance = trees_cfg["clearance"]
    edge = era.city["trees"]["edgeMargin"]
    anchors = [s["position"] for s in era.slots] + [s["pad"] for s in era.slots]
    anchors += [lot["position"] for lot in era.lots] + [p["position"] for p in era.plazas]
    anchors.append(era.sign)
    # Every potential centreline counts, drawn or not, so a tree never has to move later.
    roads = [(a, b) for _, a, b in era.spine_segments()]
    for spur in era.spurs.values():
        roads += polyline_segments(spur["points"])
    road_clear = era.width / 2 + era.amplitude + era.city["trees"]["roadClearance"]
    footprint_margin = era.city["trees"]["footprintMargin"]
    solids = [s["footprint"] for s in era.slots] + [s["pad_poly"] for s in era.slots]
    solids += [lot["poly"] for lot in era.lots] + [plaza["poly"] for plaza in era.plazas]
    rng = random.Random(era.name)
    placed = []
    stats = []
    for zone in era.zones:
        kept, accepted_samples = [], 0
        samples = 400
        for n in range(samples):
            angle = rng.random() * math.tau
            radius = zone["radius"] * math.sqrt(rng.random())
            p = (zone["center"][0] + math.cos(angle) * radius, zone["center"][1] + math.sin(angle) * radius)
            if abs(p[0]) > era.half_x - edge or abs(p[1]) > era.half_z - edge:
                continue
            if any(math.dist(p, a) < clearance for a in anchors):
                continue
            if any(point_segment_distance(p, a, b)[0] < road_clear for a, b in roads):
                continue
            if any(point_polygon_distance(p, solid) < footprint_margin for solid in solids):
                continue
            accepted_samples += 1
            if len(kept) < zone["count"] and n < zone["count"]:
                kept.append(p)
        stats.append((zone, accepted_samples / samples, len(kept)))
        placed += kept
    return placed, stats


# --------------------------------------------------------------------------
# Drawing
# --------------------------------------------------------------------------


def wobble(arc, phase):
    """Preview stand-in for the client's two-sine noise: smooth, in [-1, 1], a function of arc
    length and a per-line phase only."""
    return 0.65 * math.sin(arc * 0.35 + phase) + 0.35 * math.sin(arc * 0.93 + phase * 1.7)


def draw(era, network, visible, violations, trees, near, far, path):
    size_x = int(era.half_x * 2 * PX_PER_STUD + MARGIN_PX * 2)
    size_z = int(era.half_z * 2 * PX_PER_STUD + MARGIN_PX * 2)
    image = Image.new("RGB", (size_x + LEGEND_PX, size_z), (245, 243, 236))
    canvas = ImageDraw.Draw(image, "RGBA")
    try:
        font = ImageFont.truetype("arial.ttf", 13)
        small = ImageFont.truetype("arial.ttf", 11)
        big = ImageFont.truetype("arialbd.ttf", 18)
    except OSError:
        font = small = big = ImageFont.load_default()

    # True top-down view (+X right, +Z down): the front/hub edge (-Z) is at the top.
    def px(p):
        return (MARGIN_PX + (p[0] + era.half_x) * PX_PER_STUD, MARGIN_PX + (p[1] + era.half_z) * PX_PER_STUD)

    def poly(points, **kwargs):
        canvas.polygon([px(p) for p in points], **kwargs)

    base = era.layout["baseColor"]
    base_rgb = tuple(int(v) for v in base) if max(base) > 1 else tuple(int(v * 255) for v in base)
    poly(
        [(-era.half_x, -era.half_z), (era.half_x, -era.half_z), (era.half_x, era.half_z), (-era.half_x, era.half_z)],
        fill=base_rgb + (90,),
        outline=(40, 40, 40),
        width=3,
    )
    canvas.text((MARGIN_PX, 18), f"{era.name} street plan -- FRONT (hub, -Z) is the top edge", font=big, fill=(20, 20, 20))

    for zone in era.zones:
        c = px(zone["center"])
        r = zone["radius"] * PX_PER_STUD
        canvas.ellipse((c[0] - r, c[1] - r, c[0] + r, c[1] + r), fill=(60, 150, 60, 35), outline=(40, 120, 40), width=2)
        canvas.text((c[0] - 14, c[1] - 7), f"x{zone['count']}", font=font, fill=(20, 90, 20))

    nodes = [p for street in era.streets for p in street]
    nodes += [s["points"][-1] for s in era.spurs.values() if s["points"]]
    nodes += [s["points"][0] for s in era.spurs.values() if s["points"]]

    def taper(p):
        """PREVIEW STAND-IN, not the client's taper. RoadGraph tapers along each stretch's own
        arc length (0 at the stretch's two ends, 1 one width in), which no point outside that
        stretch can widen. This narrows by distance to the *nearest node of any line*, spur
        anchors included, so the PNG pinches the trail near every node and around building
        anchors. Judge road width and shape from it, never node-area clearance."""
        if era.meander is None:
            return 0.0
        return min(1.0, min((math.dist(p, n) for n in nodes), default=era.width) / era.width)

    def road_piece(a, b, colour, arc0, phase):
        """One centreline segment, meandered when the era has a meander; arc0 is the arc length of
        a along its whole line so the wobble never depends on which stretches are visible."""
        length = math.dist(a, b)
        if length < MIN_LENGTH:
            return
        ux, uz = (b[0] - a[0]) / length, (b[1] - a[1]) / length
        if era.meander is None:
            half = era.width / 2
            nx, nz = -uz * half, ux * half
            a2 = (a[0] - ux * half, a[1] - uz * half)
            b2 = (b[0] + ux * half, b[1] + uz * half)
            poly(
                [(a2[0] + nx, a2[1] + nz), (b2[0] + nx, b2[1] + nz), (b2[0] - nx, b2[1] - nz), (a2[0] - nx, a2[1] - nz)],
                fill=colour,
            )
            return
        steps = max(1, int(length / SAMPLE_STEP))
        for step in range(steps + 1):
            s = length * step / steps
            p = (a[0] + ux * s, a[1] + uz * s)
            offset = era.amplitude * taper(p) * wobble(arc0 + s, phase)
            q = (p[0] - uz * offset, p[1] + ux * offset)
            radius = (era.width + era.meander["widthJitter"] * wobble(arc0 + s, phase + 2.1)) / 2
            c = px(q)
            r = radius * PX_PER_STUD
            canvas.ellipse((c[0] - r, c[1] - r, c[0] + r, c[1] + r), fill=colour)

    for slot in sorted(era.slots, key=lambda s: s["id"]):
        spur = era.spurs[slot["id"]]
        colour = (170, 90, 170, 210) if spur["override"] else (130, 105, 80, 210)
        arc = 0.0
        phase = sum(map(ord, slot["id"])) * 0.37
        for a, b in polyline_segments(spur["points"]):
            road_piece(a, b, colour, arc, phase)
            arc += math.dist(a, b)

    for stretch_id, stretch in enumerate(network.stretches):
        tier = visible.get(stretch_id)
        colour = TIER_COLOURS.get(tier, NEVER_COLOUR) + ((225,) if tier else (90,))
        road_piece(stretch["a"], stretch["b"], colour, stretch["arc_start"], stretch["polyline"] * 1.3)
    for index, street in enumerate(era.streets):
        for a, b in polyline_segments(street):
            canvas.line([px(a), px(b)], fill=(255, 255, 255, 120), width=1)
        canvas.text(px(street[0]), f"S{index + 1}", font=big, fill=(0, 0, 0))
    if era.streets:
        e = px(era.streets[0][0])
        canvas.ellipse((e[0] - 7, e[1] - 7, e[0] + 7, e[1] + 7), outline=(0, 0, 0), width=3)

    for plaza in era.plazas:
        poly(plaza["poly"], fill=(200, 180, 140, 200), outline=(120, 90, 50), width=2)
        c = px(plaza["position"])
        canvas.text((c[0] - 30, c[1] - 7), f"{plaza['prop']} T{int(plaza['tier'])}", font=font, fill=(60, 40, 10))

    for lot in era.lots:
        poly(lot["poly"], fill=(240, 210, 170, 220), outline=(150, 100, 60), width=2)
        c = px(lot["position"])
        face = facing(lot["rotation"])
        tip = px((lot["position"][0] + face[0] * lot["depth"] / 2, lot["position"][1] + face[1] * lot["depth"] / 2))
        canvas.line([c, tip], fill=(150, 100, 60), width=2)
        canvas.text((c[0] - 12, c[1] - 7), f"L{int(lot['tier'])}", font=font, fill=(90, 50, 20))

    for slot in era.slots:
        fill = (120, 120, 200, 150) if slot["type"] == "building" else (170, 170, 170, 150)
        if slot["type"] == "monument":
            fill = (230, 180, 60, 160)
        poly(slot["footprint"], fill=fill, outline=(30, 30, 60), width=2)
        poly(slot["pad_poly"], fill=(90, 200, 220, 110), outline=(20, 110, 130))
        c = px(slot["position"])
        face = slot["facing"]
        tip = px((slot["position"][0] + face[0] * 6, slot["position"][1] + face[1] * 6))
        canvas.line([c, tip], fill=(10, 10, 10), width=3)
        canvas.text((c[0] - 4 * len(slot["id"]) / 1.6, c[1] - 18), slot["id"], font=small, fill=(0, 0, 0))

    for p in trees:
        c = px(p)
        canvas.ellipse((c[0] - 4, c[1] - 4, c[0] + 4, c[1] + 4), fill=(30, 110, 40, 220))

    s = px(era.sign)
    canvas.rectangle((s[0] - 5, s[1] - 5, s[0] + 5, s[1] + 5), fill=(200, 30, 30))
    canvas.text((s[0] + 8, s[1] - 16), "Sign", font=font, fill=(200, 30, 30))

    lx = size_x + 10
    y = MARGIN_PX
    canvas.text((lx, y), "Legend", font=big, fill=(0, 0, 0))
    y += 28
    for tier in range(1, 6):
        canvas.rectangle((lx, y, lx + 26, y + 12), fill=TIER_COLOURS[tier])
        canvas.text((lx + 34, y - 2), f"spine first drawn at tier {tier}", font=font, fill=(0, 0, 0))
        y += 20
    entries = [
        (NEVER_COLOUR, "spine stretch never drawn"),
        ((130, 105, 80), "auto spur (from the anchor)"),
        ((170, 90, 170), "spur override"),
        ((120, 120, 200), "building slot (arrow = facing)"),
        ((170, 170, 170), "unlock/decor slot"),
        ((230, 180, 60), "monument"),
        ((90, 200, 220), "pad"),
        ((240, 210, 170), "filler lot (L = tier)"),
        ((200, 180, 140), "plaza"),
        ((60, 150, 60), "tree zone (xN) / preview trees"),
    ]
    for colour, text in entries:
        canvas.rectangle((lx, y, lx + 26, y + 12), fill=colour)
        canvas.text((lx + 34, y - 2), text, font=font, fill=(0, 0, 0))
        y += 20
    y += 8
    canvas.text((lx, y), "circle = entrance; tiers follow the sim's greedy buy order", font=small, fill=(0, 0, 0))
    y += 22
    meander = f", meander {era.amplitude:g}" if era.meander else ""
    canvas.text((lx, y), f"road width {era.width:g}{meander}", font=font, fill=(0, 0, 0))
    y += 18
    canvas.text((lx, y), f"spines {len(era.streets)}, lots {len(era.lots)}", font=font, fill=(0, 0, 0))
    y += 18
    canvas.text((lx, y), f"plazas {len(era.plazas)}, trees {sum(z['count'] for z in era.zones)}", font=font, fill=(0, 0, 0))
    y += 18
    canvas.text((lx, y), f"road pieces reserved: near {near}, far {far}", font=font, fill=(0, 0, 0))
    y += 18
    colour = (0, 130, 0) if not violations else (200, 0, 0)
    canvas.text((lx, y), f"violations: {len(violations)}", font=big, fill=colour)

    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path)


def main():
    names = sys.argv[1:] or list(DEFAULT_ERAS)
    city = json.loads(CITY_CONFIG_PATH.read_text(encoding="utf-8"))
    total = 0
    for name in names:
        era = Era(name, city)
        network = Network(era)
        visible, unreachable = visible_network(era, network, greedy_buy_tiers(name, city))
        violations, notes, near, far, detail = check(era, network, visible, unreachable)
        trees, stats = scatter_trees(era)
        path = OUT_DIR / name / "streetplan.png"
        draw(era, network, visible, violations, trees, near, far, path)
        overrides = [s["id"] for s in era.slots if era.spurs[s["id"]]["override"]]
        budget = city.get("budget", {})
        print(
            f"== {name}: road width {era.width:g}, {len(era.streets)} spines, {len(era.lots)} lots, "
            f"{len(era.plazas)} plazas, {len(era.zones)} tree zones "
            f"(sum {sum(z['count'] for z in era.zones)} / max {era.dressing['trees']['maxCount']})"
        )
        print(f"   spur overrides: {', '.join(overrides) if overrides else 'none'}")
        print(
            f"   road pieces RESERVED for the whole layout (what RoadGraph.allocate holds back, "
            f"drawn or not): far {far} / {budget.get('roadPieces')} "
            f"[spine groups {detail['spineFar']} + spur legs {detail['spurFar']} + tiles {detail['tiles']}]"
        )
        if era.meander:
            print(
                f"     near {near} / {budget.get('roadPiecesNear')} "
                f"[spine {detail['spineNear']} + spurs {detail['spurNear']} + bend discs {detail['bends']}]"
            )
        else:
            print("     near: straight era, same as far")
        for zone, usable, _ in stats:
            print(
                f"   tree zone {fmt(zone['center'])} r{zone['radius']:g} x{zone['count']}: "
                f"{usable * 100:.0f}% of the circle is plantable"
            )
        for note in notes:
            print(f"   note: {note}")
        for violation in violations:
            print(f"   VIOLATION: {violation}")
        print(f"   {len(violations)} violations -> {path.relative_to(REPO_ROOT)}")
        total += len(violations)
    print(f"TOTAL: {total} violations")
    sys.exit(1 if total else 0)


if __name__ == "__main__":
    main()
