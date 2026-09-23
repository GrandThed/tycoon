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

Wave 2c ("living city") adds lots by kind (house 9x9 / small 6x6, small under the ring deck), the
parked bays (off every lane strip and walk lane, kerbside, on a street that is drawn) and the
greenery zones (Scatter.greenerySpots' road keep and blockers), all drawn in the PNG.

Numbers come from their owners, never from this file: road width, meander, tree rules and budgets
from Config/CityDressing.json, slot and prop footprints from the testfit blueprints (contract
defaults 9x9 / monument 14x14 when a blueprint has none), pad and plot sizes from the layout, and
the purchase order and tier times from tools/sim_economy.py's greedy player. The only tool-local
numbers are the contract's own rule values and the preview's drawing constants, named below.

Usage:
  py tools/streetplan.py                # every era with a street plan (DEFAULT_ERAS)
  py tools/streetplan.py Metropolis     # any era(s) by name
Exit code 1 when any violation is found.
"""

from __future__ import annotations

import importlib.util
import itertools
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
ASSETS_PATH = REPO_ROOT / "src" / "shared" / "Config" / "Assets.json"  # read only, never written

DEFAULT_ERAS = ("Village", "Boomtown", "Metropolis", "OrbitalColony")  # every era with a street plan (wave 2b)

# Contract rule values (INTERFACES.md "Layouts" and amendments), not game tunables.
SLOT_FOOTPRINT_DEFAULT = 9
MONUMENT_FOOTPRINT_DEFAULT = 14
SPINE_EXTRA_CLEARANCE = 1  # spine clear of slots/pads/Sign by width/2 (+ meander) + this
LOT_SLOT_CLEARANCE = 6  # a "house" lot's centre from any slot footprint (M9 "Layouts")
STREET_COUNT = (2, 5)
# Wave 2b: the Orbital plot is a full 4x4 module grid with no pavement, so it takes 6-10 small domes.
LOT_COUNT_BY_ERA = {"OrbitalColony": (6, 10)}
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
    # Wave 2a: Metropolis' two streetOnly slots. The server spawns an empty marker for them, so
    # their nominal 9x9 footprint is fiction -- only the pad is real, and it is meant to stand on
    # the street furniture it names (the ramp foot, the kerb beside a metro entrance).
    "Metropolis": ("subwayLine", "highwayRamp"),
    # Wave 2b: Build the Monorail is streetOnly the same way; its pad stands in a tube corner.
    "OrbitalColony": ("walkwayNetwork",),
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
# Wave 2a (INTERFACES "Wave 2a -- Metropolis streets, highway, subway"). Contract rules again,
# not tunables; everything here only applies to an era whose CityDressing.json has road.tiles.
# Fallback ramp length in whole cells, used only when Assets.json cannot be read: the real number
# is measured off the built prop the way Highway.rampCells does (prop_cell_length below).
RAMP_CELLS_FALLBACK = 3
RAMP_DIRECTIONS = {"+X": (1.0, 0.0), "-X": (-1.0, 0.0), "+Z": (0.0, 1.0), "-Z": (0.0, -1.0)}
SUBWAY_COUNT = (4, 6)
# Measured bounds (x, z) of the built Metropolis/MetroEntrance prop at rotationY 0 -- front (stair
# mouth) on -Z, origin bottom-centre. The blueprint's `footprint` key is only the envelope the
# builder was briefed to fit inside, and the sidewalk an entrance stands on is exactly 6 studs
# wide (road edge to block face), so the checker measures the prop and merely flags a blueprint
# that declares less than the prop really is.
METRO_ENTRANCE_EXTENTS = (4.90, 5.79)
SUBWAY_CLEARANCE = 0.5  # daylight between an entrance and any footprint, pad or plaza
# Wave 2a, after Ben's Studio look: a tiles-era plaza is 14 x 14 with the pavement apron built
# into the prop, and its front (-Z at rotation 0) is flush with a street's pavement edge. The
# blueprint may still declare the pre-resize envelope while the prop is reworked, so the checker
# takes whichever is bigger -- a stale file must never pass a plan the real prop will not fit.
PLAZA_MIN_SIZE = (14.0, 14.0)
PLAZA_EDGE_SLACK = 0.5  # how far the front edge may sit from the pavement's outer edge
# Wave 2b: a tiles era without pavement (Orbital tubes) has no apron to build in, so its plaza is
# the prop's own blueprint footprint (this fallback when the blueprint declares none) and its front
# is flush with the tube cell edge instead.
PLAZA_BARE_SIZE = (12.0, 12.0)
# Paved blocks (INTERFACES "Paved blocks"): slabs are Parts, so two of them meeting edge to edge
# would share a plane and z-fight; the contract asks for daylight between neighbours instead.
BLOCK_GAP = 0.5
ZONE_SOLID_CLEARANCE = 3  # wave 2b: a rock zone circle's daylight to any footprint or pad
# Scatter.luau mirrors: an edge counts as fronting a street within `reach` of it and aligned to
# better than STRAIGHT_ENOUGH. The clearance a street tree keeps off spurs and solids comes from
# `road.tiles.blocks.treeClearance`; this is only the fallback for a config that predates the key.
STREET_TREE_CLEARANCE = 1
STRAIGHT_ENOUGH = 0.9
# An entrance stands on the pavement it faces: its front edge may come this close to the asphalt.
SUBWAY_STREET_REACH = 1.5

# Wave 2c (INTERFACES "Wave 2c -- living city"). Contract caps and minimums again, not tunables.
# A lot reserves its kind's cap, not the props' current size: the client sizes a lot from the
# union of that kind's harvested props, and a builder may grow a prop up to the cap later.
LOT_KINDS = {"house": (9.0, 9.0), "small": (6.0, 6.0)}
SMALL_LOT_MAX_HEIGHT = 6.0  # a "small" lot may stand under the ring deck
LOT_MINIMUM = {"Village": 18, "Boomtown": 18, "Metropolis": 10}
LOT_TIERS = (1, 5)
LOT_PER_TIER = 2  # every tier step adds visible houses
# Eras outside wave 2c (OrbitalColony, wave 2b) keep the M9 rule unchanged.
LEGACY_LOT_COUNT = (8, 12)
LEGACY_LOT_TIERS = (2, 5)
# A small lot tucks in behind a block or beside a slot, so it only keeps daylight from a slot's
# footprint (a house keeps LOT_SLOT_CLEARANCE from its centre, as before). Pads keep 1 stud either way.
SMALL_LOT_SLOT_GAP = 0.5
# Ring pier, measured off tools/assets/highway_kit.py: one per deck cell at the cell centre, the
# hammerhead cap flaring to PIER_CAP_HALF_Z_TOP = 2.40 across the ring above 5.35 studs, which is
# lower than a 6-stud small lot. The plinth is narrower; the cap is what a roof would hit.
PIER_HALF = 2.4
PIER_GAP = 0.5
# Parked bays, from the built props plus daylight (lead, 2026-09-23): Boomtown cars are up to
# 3.75 x 7.13, Metropolis ParkedC is 2.56 x 5.52, Village CartParked 2.23 x 3.47. A bay is the
# larger of this and its props' declared footprints.
PARKING_BAY = {"Village": (3.0, 4.5), "Boomtown": (4.0, 7.5), "Metropolis": (3.0, 6.0)}
PARK_TIERS = (2, 5)  # parked vehicles start at tier 2 (INTERFACES "Done when")
PARK_ROAD_GAP = 0.5  # off every lane strip: this far outside the drawn road edge
PARK_GAP = 0.5  # daylight to footprints, pads, lots, plazas, kiosks and other bays
PARK_STREET_REACH = 6.0  # a bay's near edge within this of the drawn road edge, or it is not kerbside
# Half a walker's width, arm to arm (tools/assets/people_kit.py ARM_OUT). A bay keeps this plus
# PARK_GAP from a walk lane line, and a walker this far out from its lane must clear the cars.
WALKER_HALF = 0.42
# Wave 2d: studs between two cars packed into one bay when `parked.gap` is absent (Scatter's
# DEFAULT_PARKED_GAP, mirrored).
PARKED_GAP_DEFAULT = 0.3
MAX_PER_BAY = 4  # Scatter's MAX_PER_BAY, mirrored: perBay is clamped to 1..this
GREENERY_ZONE_COUNT = (2, 8)
# Walk lanes are clipped wherever they pass within `pedestrians.clearance` of a solid; the tool
# samples every lane this finely to find the clipped runs.
WALK_SAMPLE = 0.25
POST_FALLBACK = 0.5  # base width of a lamp or signal whose prop is not harvested yet
# RoadGraph.SignalSpots constants, mirrored.
SIGNAL_MIN_ARMS = 3
SIGNAL_GAP_MIN = math.pi / 6
SIGNAL_GAP_MAX = math.pi * 0.95
# Greenery yield (Scatter.greenerySpots draws exactly `count` candidates per zone and never redraws
# one it rejects): simulated over this many seeds; the plan fails when this quantile of the yield
# falls short of perTier's tier-5 count.
GREENERY_SEEDS = 120
GREENERY_QUANTILE = 0.10

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


def declared_footprints(era_name, prop_names):
    """(name, (x, z)) for every named prop blueprint that declares a footprint."""
    found = []
    for name in prop_names:
        path = BLUEPRINTS_DIR / "_props" / era_name / f"{name}.json"
        if not path.exists():
            continue
        footprint = json.loads(path.read_text(encoding="utf-8")).get("footprint")
        if footprint:
            found.append((name, (float(footprint[0]), float(footprint[1]))))
    return found


def harvested_extents(era_name, prop_name):
    """(x, y, z) size of a harvested prop's stage 0 in Assets.json -- what the client measures --
    or None before the prop is harvested. Offsets carry the importer's 180-degree turn, which
    flips signs but not extents, so no un-turning is needed here."""
    try:
        assets = json.loads(ASSETS_PATH.read_text(encoding="utf-8"))
        parts = assets["props"][era_name][prop_name]["stages"][0]["parts"]
    except (OSError, ValueError, KeyError, IndexError, TypeError):
        return None
    low = [math.inf, math.inf, math.inf]
    high = [-math.inf, -math.inf, -math.inf]
    for part in parts:
        centre, size = part.get("offset"), part.get("size")
        if not part.get("meshId") or not centre or not size:
            continue
        for axis in range(3):
            low[axis] = min(low[axis], centre[axis] - size[axis] / 2)
            high[axis] = max(high[axis], centre[axis] + size[axis] / 2)
    if low[0] > high[0]:
        return None
    return tuple(high[axis] - low[axis] for axis in range(3))


def config_scale(config):
    """PropFactory.ScaleOf, mirrored: a config `scale` that is missing, NaN or not positive is 1."""
    value = (config or {}).get("scale")
    if isinstance(value, bool) or not isinstance(value, (int, float)) or value != value or value <= 0 or value == math.inf:
        return 1.0
    return float(value)


def scaled_extents(era_name, prop_name, scale):
    """harvested_extents at the runtime scale the client spawns the prop with (wave 2d)."""
    extents = harvested_extents(era_name, prop_name)
    return tuple(axis * scale for axis in extents) if extents else None


def walker_half(era):
    """WALKER_HALF at the era's `pedestrians.scale`."""
    return WALKER_HALF * config_scale(era.dressing.get("pedestrians"))


def union_length(era_name, prop_names):
    """Scatter.harvestedUnion's Z length (the car's long axis) at the built size, None before any
    of them is harvested. Offsets are only sign-flipped by the import turn, so min/max of |z| spans
    are taken over the raw offsets and give the same length."""
    try:
        assets = json.loads(ASSETS_PATH.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    low, high = math.inf, -math.inf
    for name in prop_names:
        try:
            stages = assets["props"][era_name][name]["stages"]
        except (KeyError, TypeError):
            continue
        for stage in stages:
            for part in stage.get("parts", []):
                centre, size = part.get("offset"), part.get("size")
                if not part.get("meshId") or not centre or not size:
                    continue
                low = min(low, centre[2] - size[2] / 2)
                high = max(high, centre[2] + size[2] / 2)
    return high - low if low <= high else None


def per_bay(config):
    """Scatter's `parked.perBay`: floored, clamped to 1..MAX_PER_BAY, 1 when missing or not a number."""
    value = (config or {}).get("perBay", 1)
    if isinstance(value, bool) or not isinstance(value, (int, float)) or value != value:
        return 1
    return min(max(int(math.floor(value)), 1), MAX_PER_BAY) if value != math.inf else MAX_PER_BAY


def bay_length(era_name, config):
    """Scatter's packing length: `parked.bayLength` when it is a positive finite number, else the
    pool's built-size union length (None before any of it is harvested)."""
    value = (config or {}).get("bayLength")
    if not isinstance(value, bool) and isinstance(value, (int, float)) and value == value and 0 < value < math.inf:
        return float(value)
    return union_length(era_name, (config or {}).get("props") or [])


def bay_packing(era):
    """Scatter.packBay over every ordered pick of `perBay` cars from `parked.props`: (perBay, how
    many of those rows fit, how many there are, the longest row that fits). A row fits when its
    scaled lengths plus `gap` between them are within bay_length; a row that does not keeps one car."""
    config = era.dressing.get("parked") or {}
    props = config.get("props") or []
    cars = per_bay(config)
    if cars <= 1 or not props:
        return cars, 0, 0, 0.0
    scale = config_scale(config)
    spacing = max(float(config.get("gap", PARKED_GAP_DEFAULT)), 0.0)
    bay = bay_length(era.name, config)
    lengths = [scaled_extents(era.name, name, scale) for name in props]
    fits, total, longest = 0, 0, 0.0
    for row in itertools.product(range(len(props)), repeat=cars):
        total += 1
        if bay is None or any(lengths[i] is None for i in row):
            continue
        length = sum(lengths[i][2] for i in row) + spacing * (cars - 1)
        if length <= bay + 1e-9:
            fits += 1
            longest = max(longest, length)
    return cars, fits, total, longest


def gap(p, q):
    """Daylight between two convex polygons, 0 when they touch, overlap or one holds the other
    (polygon_polygon_distance alone misses a large p wholly containing q)."""
    return min(polygon_polygon_distance(p, q), polygon_polygon_distance(q, p))


def prop_cell_length(era_name, prop_name, tile_studs, fallback):
    """Highway.rampCells, off the same numbers: the built prop's X extent in whole cells. The
    client measures the spawned parts at runtime; the harvested sizes and anchor-relative offsets
    in Assets.json are those parts, so the tool reads them (and only reads -- another session may
    own that file). A missing file, prop or stage degrades to `fallback`, as the client degrades
    to drawing nothing."""
    try:
        assets = json.loads(ASSETS_PATH.read_text(encoding="utf-8"))
        stages = assets["props"][era_name][prop_name]["stages"]
        parts = stages[0]["parts"]
    except (OSError, ValueError, KeyError, IndexError):
        return fallback
    low, high = math.inf, -math.inf
    for part in parts:
        centre, size = part.get("offset"), part.get("size")
        if not centre or not size:
            continue
        low = min(low, centre[0] - size[0] / 2)
        high = max(high, centre[0] + size[0] / 2)
    if low > high or tile_studs <= 0:
        return fallback
    return max(1, int(round_half((high - low) / tile_studs)))


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
        self.paths = road.get("paths")  # Wave 1d: baked pieces; absent means the parts renderer
        # Wave 2a: presence of road.tiles selects the kit-tile renderer, which rasterises every
        # street to whole cells of `tileStuds`. Everything lattice-shaped below is gated on it, so
        # Village and Boomtown keep exactly the rules they had.
        self.tiles = road.get("tiles")
        self.tile_studs = float(self.tiles["tileStuds"]) if self.tiles else 0.0
        pavement = (self.tiles or {}).get("pavement")
        self.pavement = float(pavement["width"]) if pavement else 0.0
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
        # Wave 2c: a lot is a "house" (houses.props) or a "small" (houses.smallProps) and reserves
        # its kind's contract cap, whatever the props measure today.
        houses = self.dressing.get("houses", {})
        self.lot_props = {"house": list(houses.get("props", [])), "small": list(houses.get("smallProps", []))}
        # Eras outside wave 2c (OrbitalColony's small domes) keep the wave 2b rule: the house props'
        # own footprint, not the 9x9 contract cap.
        legacy_size = (
            None
            if name in LOT_MINIMUM
            else prop_footprint(name, self.lot_props["house"], (SLOT_FOOTPRINT_DEFAULT, SLOT_FOOTPRINT_DEFAULT))
        )
        self.lots = []
        for lot in self.layout.get("lots", []):
            position = xz(lot["position"])
            kind = lot.get("kind", "house")
            size = legacy_size or LOT_KINDS.get(kind, LOT_KINDS["house"])
            self.lots.append(
                {
                    "position": position,
                    "rotation": lot["rotationY"],
                    "tier": lot["tier"],
                    "kind": kind,
                    "poly": square(position, size[0], size[1], lot["rotationY"]),
                    "depth": size[1],
                }
            )
        parked = self.dressing.get("parked") or {}
        bay = PARKING_BAY.get(name, PARKING_BAY["Boomtown"])
        for _, footprint in declared_footprints(name, parked.get("props", [])):
            bay = (max(bay[0], footprint[0]), max(bay[1], footprint[1]))
        # Wave 2d: packed cars stay inside bay_length (Scatter.packBay), so a bay at least that
        # long holds every row the client can draw.
        packed = bay_length(name, parked) if per_bay(parked) > 1 else None
        if packed:
            bay = (bay[0], max(bay[1], packed))
        self.bay = bay
        self.parking = []
        for spot in self.layout.get("parking", []):
            position = xz(spot["position"])
            self.parking.append(
                {
                    "position": position,
                    "rotation": spot["rotationY"],
                    "tier": spot["tier"],
                    "lot": int(spot["lot"]) if spot.get("lot") is not None else None,
                    "poly": square(position, bay[0], bay[1], spot["rotationY"]),
                }
            )
        self.greenery_zones = [
            {"center": xz(z["center"]), "radius": z["radius"], "count": int(z["count"])}
            for z in self.layout.get("greeneryZones", [])
        ]
        self.plazas = []
        for plaza in self.layout.get("plazas", []):
            position = xz(plaza["position"])
            paved = self.tiles is not None and self.pavement > 0
            size = prop_footprint(name, [plaza["prop"]], PLAZA_MIN_SIZE if paved else PLAZA_BARE_SIZE if self.tiles else (12, 12))
            if paved:
                size = (max(size[0], PLAZA_MIN_SIZE[0]), max(size[1], PLAZA_MIN_SIZE[1]))
            self.plazas.append(
                {
                    "position": position,
                    "rotation": plaza["rotationY"],
                    "tier": plaza["tier"],
                    "prop": plaza["prop"],
                    "size": size,
                    "facing": facing(plaza["rotationY"]),
                    "poly": square(position, size[0], size[1], plaza["rotationY"]),
                }
            )
        self.zones = [
            {"center": xz(z["center"]), "radius": z["radius"], "count": int(z["count"])}
            for z in self.layout.get("treeZones", [])
        ]
        self.blocks = []
        for entry in self.layout.get("blocks", []):
            low, high = xz(entry["min"]), xz(entry["max"])
            self.blocks.append(
                {
                    "min": low,
                    "max": high,
                    "slots": list(entry.get("slots", [])),
                    "poly": [(low[0], low[1]), (high[0], low[1]), (high[0], high[1]), (low[0], high[1])],
                }
            )
        self.highway = self.layout.get("highway")
        highway_cfg = self.dressing.get("highway")
        # Wave 2b: `junction` and `ramp` are optional (loop mode), in the config and the layout.
        ramp_prop = highway_cfg["props"].get("ramp") if highway_cfg else None
        self.highway_ramp = self.highway.get("ramp") if self.highway else None
        self.ramp_cells = (
            prop_cell_length(name, ramp_prop, self.tile_studs, RAMP_CELLS_FALLBACK)
            if ramp_prop
            else RAMP_CELLS_FALLBACK
        )
        self.highway_sign = bool(highway_cfg and highway_cfg["props"].get("sign"))
        subway = self.dressing.get("subway")
        self.subway_prop = subway["prop"] if subway else None
        self.subway_size = METRO_ENTRANCE_EXTENTS
        self.subway_declared = prop_footprint(name, [self.subway_prop] if self.subway_prop else [], self.subway_size)
        self.subways = []
        for entry in self.layout.get("subwayEntrances", []):
            position = xz(entry["position"])
            rotation = entry["rotationY"]
            self.subways.append(
                {
                    "position": position,
                    "rotation": rotation,
                    "facing": facing(rotation),
                    "poly": square(position, self.subway_size[0], self.subway_size[1], rotation),
                }
            )
        self.spurs = {slot["id"]: self.spur_for(slot) for slot in self.slots}

    def road_cells(self):
        """Every lattice cell the tile renderer would rasterise the plan to, drawn or not. The
        client picks a cell's prop from its visible neighbours, so the cell -- not the centreline
        -- is the unit a pad, a plaza or a subway entrance has to stay off."""
        cells = set()
        if not self.tiles:
            return cells
        step = self.tile_studs
        for _, a, b in self.spine_segments():
            length = math.dist(a, b)
            steps = max(1, int(length / (step / 2)))
            for index in range(steps + 1):
                p = lerp(a, b, index / steps)
                cells.add((round_half(p[0] / step), round_half(p[1] / step)))
        return cells

    def cell_square(self, cell):
        """The footprint of one lattice cell, keyed as (i, j) with centre (i * step, j * step)."""
        step = self.tile_studs
        centre = (cell[0] * step, cell[1] * step)
        return square(centre, step, step, 0)

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

    def straight_allocate(self):
        """RoadGraph.allocate's greedy straight pass: which spine groups and which spurs are
        switched on inside budget.roadPieces. `reserve()` adds up what the layout *wants*; this is
        what the client actually turns on, and the baked-path pass is gated on both flags.

        Groups go first, nearest the entrance and ties by group index, each costing 1 or 2. Spurs
        follow in sorted slot order and cost one per leg -- with no `break`, so a short spur still
        fits after a long one was refused, exactly as the client does.
        """
        budget = self.era.city.get("budget", {})
        remaining = budget_value(budget.get("roadPieces"), 0)
        order = []
        for group_index, stretch_ids in enumerate(self.groups):
            nearest = None
            for stretch_id in stretch_ids:
                distance = self.near_distance(stretch_id)
                if distance is not None and (nearest is None or distance < nearest):
                    nearest = distance
            if nearest is not None:
                order.append((nearest, group_index))
        order.sort()  # byDistance: distance, then index -- identical on every client
        groups_allowed = set()
        for _, group_index in order:
            toward_start = toward_end = False
            for stretch_id in self.groups[group_index]:
                stretch = self.stretches[stretch_id]
                a, b = self.distance.get(stretch["from"]), self.distance.get(stretch["to"])
                if a is None or b is None:
                    continue
                if a <= b:
                    toward_start = True
                else:
                    toward_end = True
            cost = 2 if (toward_start and toward_end) else 1
            if cost > remaining:
                break
            groups_allowed.add(group_index)
            remaining -= cost
        spurs_allowed = []
        for slot_id in self.spur_ids:
            legs = max(len(self.era.spurs[slot_id]["points"]) - 1, 0)
            if legs <= remaining:
                spurs_allowed.append(slot_id)
                remaining -= legs
        return groups_allowed, spurs_allowed

    def path_reserve(self):
        """What RoadGraph.allocate's baked-path pass holds back out of `budget.pathPieces`, for an
        era with `road.paths`: one cloned piece per reachable stretch whose group survived the
        straight budget, then one per allowed spur. Returns (total, detail).

        Line for line with the client: stretches are ranked nearest-the-entrance first and spend
        one piece each until `pathRemaining` hits 0, and **spurs are allocated after every
        stretch**. So an overrun costs buildings their path first -- the spine stays whole, a
        building simply never gets a trail, and nothing in game or in the bake says so. That is
        why this has to be a tool check.

        Reserved, not drawn: allocate runs over the whole layout before anything is owned, so a
        stretch no path ever reveals still holds its piece.
        """
        groups_allowed, spurs_allowed = self.straight_allocate()
        stretches = sum(
            1
            for stretch_id, stretch in enumerate(self.stretches)
            if self.near_distance(stretch_id) is not None and stretch["group"] in groups_allowed
        )
        spurs = len(spurs_allowed)
        return stretches + spurs, {"pathStretches": stretches, "pathSpurs": spurs}

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


def budget_value(value, fallback):
    """RoadGraph.budgetValue: a budget key a stale CityDressing.json does not carry (or a NaN)
    degrades to `fallback` on the client, so the tool has to read it the same way or it would
    check a plan against a number the game never uses."""
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return fallback
    return value if value == value else fallback


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


def lattice_violations(era):
    """Wave 2a grid rule: in a tiles era every streets point sits on the (step * i, step * j)
    lattice and every segment is axis-aligned, because a street is a run of whole kit tiles and a
    half-cell point would leave a gap the renderer cannot fill."""
    messages = []
    step = era.tile_studs
    for index, street in enumerate(era.streets):
        for p in street:
            off = max(abs(p[axis] / step - round_half(p[axis] / step)) for axis in (0, 1))
            if off > 1e-6:
                messages.append(f"street {index + 1}: point {fmt(p)} is off the {step:g}-stud tile lattice")
        for a, b in polyline_segments(street):
            if abs(a[0] - b[0]) > 1e-6 and abs(a[1] - b[1]) > 1e-6:
                messages.append(f"street {index + 1}: segment {fmt(a)}->{fmt(b)} is not axis-aligned")
    return messages


def rect_overlap(p, q):
    """Overlap area of the axis-aligned boxes around two polygons; every rotation in a layout is a
    quarter turn, so for the checks below the boxes are the shapes themselves. Touching is 0."""
    width = min(max(c[0] for c in p), max(c[0] for c in q)) - max(min(c[0] for c in p), min(c[0] for c in q))
    depth = min(max(c[1] for c in p), max(c[1] for c in q)) - max(min(c[1] for c in p), min(c[1] for c in q))
    return max(width, 0.0) * max(depth, 0.0)


def cell_violations(era, cells):
    """Wave 2b: the whole lattice cell is the road, whatever width the tile draws inside it (a tube
    is 4 wide in a 7 cell), so pads, real footprints, lots and rock zones stay off every cell a
    street rasterises to. Flush against a cell edge is fine -- that is where a pad belongs."""
    messages = []
    solids = []
    for slot in era.slots:
        solids.append((f"{slot['id']} pad", slot["pad_poly"]))
        if slot["id"] not in era.furniture:
            solids.append((f"{slot['id']} footprint", slot["footprint"]))
    solids += [(f"lot {i + 1}", lot["poly"]) for i, lot in enumerate(era.lots)]
    for cell in sorted(cells):
        square_ = era.cell_square(cell)
        where = fmt((cell[0] * era.tile_studs, cell[1] * era.tile_studs))
        for name, poly in solids:
            if rect_overlap(poly, square_) > 1e-6:
                messages.append(f"{name} stands on the road cell {where}")
        for i, zone in enumerate(era.zones):
            if point_polygon_distance(zone["center"], square_) < zone["radius"] - 1e-6 or point_in_polygon(zone["center"], square_):
                messages.append(f"tree zone {i + 1} reaches onto the road cell {where}")
    return messages


def bare_zone_violations(era):
    """Wave 2b (Ben's look): in an era whose decking carries no trees (`treeSpacing` 0) the decking
    sits only under module clusters and the rocks belong on the bare regolith between them, so no
    zone centre may fall inside a block rect, and every zone circle keeps ZONE_SOLID_CLEARANCE off
    each footprint and pad -- a rock field crowding a module reads as rubble against its wall."""
    messages = []
    for i, zone in enumerate(era.zones):
        label = f"tree zone {i + 1} {fmt(zone['center'])}"
        for j, block in enumerate(era.blocks):
            if point_in_polygon(zone["center"], block["poly"]):
                messages.append(f"{label}: centre is on decking block {j + 1}, not bare regolith")
        for slot in era.slots:
            checks = [("pad", slot["pad_poly"])]
            if slot["id"] not in era.furniture:
                checks.append(("footprint", slot["footprint"]))
            for what, poly in checks:
                gap = point_polygon_distance(zone["center"], poly) - zone["radius"]
                if point_in_polygon(zone["center"], poly) or gap < ZONE_SOLID_CLEARANCE - 1e-6:
                    messages.append(f"{label}: {gap:.2f} from {slot['id']} {what} (need {ZONE_SOLID_CLEARANCE})")
    return messages


def ring_reach(poly):
    """How far a footprint reaches from the plot centre along the worse axis -- the number the
    square ring deck cares about."""
    return max(max(abs(corner[0]), abs(corner[1])) for corner in poly)


def highway_violations(era):
    """Wave 2a elevated ring: the deck and its pillars are props on the street lattice, so they
    are checked like streets (against footprints and pads), and the ramp has to land where a
    street actually starts or it comes down on bare ground."""
    messages = []
    highway = era.highway
    step = era.tile_studs
    if step <= 0:
        return [f"highway: {era.name} has no road.tiles, so the deck has no cell pitch"]
    ring, half = float(highway["ring"]), step / 2
    if abs(ring / step - round_half(ring / step)) > 1e-6:
        messages.append(f"highway ring {ring:g} is off the {step:g}-stud lattice")
    if ring + half > min(era.half_x, era.half_z) + 1e-6:
        messages.append(f"highway ring {ring:g}: the deck band {ring - half:g}..{ring + half:g} leaves the plot")
    inner = ring - half
    # Nothing may stand in the band: pillars come down inside it all the way round.
    for slot in era.slots:
        if slot["id"] in era.furniture:
            continue  # streetOnly: no model spawns, the 9x9 is nominal
        for what, poly in (("footprint", slot["footprint"]), ("pad", slot["pad_poly"])):
            reach = ring_reach(poly)
            if reach > inner - 1e-6:
                messages.append(
                    f"highway ring: {slot['id']} {what} reaches {reach:g} studs from the centre, "
                    f"into the deck band {inner:g}..{ring + half:g}"
                )
    for index, plaza in enumerate(era.plazas):
        reach = ring_reach(plaza["poly"])
        if reach > inner - 1e-6:
            messages.append(f"highway ring: plaza {index + 1} reaches {reach:g} studs, into the deck band")
    for index, zone in enumerate(era.zones):
        # A tree planted under the deck grows through it: Scatter knows nothing about the highway,
        # so the zone itself has to stop short of the band.
        reach = max(abs(zone["center"][0]), abs(zone["center"][1])) + zone["radius"]
        if reach > inner - 1e-6:
            messages.append(f"highway ring: tree zone {index + 1} reaches {reach:g} studs, into the deck band")

    ramp = era.highway_ramp
    if ramp is None:
        return messages  # loop mode (wave 2b): no deck T, no ramp, no foot to land
    cell = xz(ramp["cell"])
    direction = RAMP_DIRECTIONS.get(ramp["direction"])
    if direction is None:
        return messages + [f"highway ramp: direction {ramp['direction']!r} is not one of {sorted(RAMP_DIRECTIONS)}"]
    on_x = abs(abs(cell[0]) - ring) < 1e-6
    on_z = abs(abs(cell[1]) - ring) < 1e-6
    if not (on_x or on_z):
        messages.append(f"highway ramp: cell {fmt(cell)} is not on the ring (|x| or |z| = {ring:g})")
    if on_x and on_z:
        # A corner cell carries the ring's own turn, so a deck T there would face sideways.
        messages.append(f"highway ramp: cell {fmt(cell)} is a ring corner cell; the deck T needs a mid-side cell")
    along = (0.0, 1.0) if on_x else (1.0, 0.0)  # the leg's own run; the ramp has to leave across it
    inward = (-math.copysign(1.0, cell[0]), 0.0) if on_x else (0.0, -math.copysign(1.0, cell[1]))
    if abs(direction[0] * along[0] + direction[1] * along[1]) > 1e-6:
        messages.append(f"highway ramp: direction {ramp['direction']} runs along the ring leg, not off it")
    elif direction != inward:
        messages.append(f"highway ramp: direction {ramp['direction']} points out of the plot, not into the city")
    cells = [(cell[0] + direction[0] * step * k, cell[1] + direction[1] * step * k) for k in range(1, era.ramp_cells + 1)]
    foot = cells[-1]
    ends = [point for street in era.streets for point in (street[0], street[-1])]
    if not any(math.dist(foot, end) < 1e-6 for end in ends):
        messages.append(
            f"highway ramp: foot cell {fmt(foot)} ({era.ramp_cells} cells from the ring) is not the end of a "
            "streets polyline, so the deck would land where no street starts"
        )
    for centre in cells:
        poly = square(centre, step, step, 0)
        for slot in era.slots:
            if slot["id"] in era.furniture:
                continue
            for what, other in (("footprint", slot["footprint"]), ("pad", slot["pad_poly"])):
                if polygon_polygon_distance(poly, other) < 1e-6:
                    messages.append(f"highway ramp: cell {fmt(centre)} crosses {slot['id']} {what}")
    return messages


def subway_violations(era, cells):
    """Wave 2a entrances: on the pavement beside a street they face, off the asphalt, out of
    everything else's way, and spread so the client has one to show in every quadrant."""
    messages = []
    half_road = era.width / 2
    if not SUBWAY_COUNT[0] <= len(era.subways) <= SUBWAY_COUNT[1]:
        messages.append(f"subwayEntrances: {len(era.subways)}, need {SUBWAY_COUNT[0]}-{SUBWAY_COUNT[1]}")
    quadrants = {(entry["position"][0] >= 0, entry["position"][1] >= 0) for entry in era.subways}
    if era.subways and len(quadrants) < 4:
        messages.append(f"subwayEntrances: only {len(quadrants)} of the 4 quadrants have one")
    if era.subway_declared[0] + 1e-6 < era.subway_size[0] or era.subway_declared[1] + 1e-6 < era.subway_size[1]:
        messages.append(
            f"{era.subway_prop} blueprint footprint {era.subway_declared} is smaller than the built prop "
            f"{era.subway_size} -- the plan was checked against the prop"
        )
    ring_inner = float(era.highway["ring"]) - era.tile_studs / 2 if era.highway else math.inf
    for index, entry in enumerate(era.subways):
        label = f"subway entrance {index + 1} {fmt(entry['position'])}"
        poly = entry["poly"]
        for slot in era.slots:
            # A streetOnly slot's footprint is nominal (no model spawns), but its pad is a real
            # part an entrance must not stand in.
            checks = [("pad", slot["pad_poly"])]
            if slot["id"] not in era.furniture:
                checks.append(("footprint", slot["footprint"]))
            for what, other in checks:
                d = polygon_polygon_distance(poly, other)
                if d < SUBWAY_CLEARANCE - 1e-6:
                    messages.append(f"{label}: {d:.2f} from {slot['id']} {what} (need {SUBWAY_CLEARANCE})")
        for j, plaza in enumerate(era.plazas):
            if polygon_polygon_distance(poly, plaza["poly"]) < SUBWAY_CLEARANCE - 1e-6:
                messages.append(f"{label}: overlaps plaza {j + 1}")
        for other in era.subways[index + 1 :]:
            if polygon_polygon_distance(poly, other["poly"]) < SUBWAY_CLEARANCE - 1e-6:
                messages.append(f"{label}: too close to another entrance")
        # The kiosk stands on the pavement; the asphalt itself has to stay clear.
        for cell in cells:
            if polygon_polygon_distance(poly, era.cell_square(cell)) < 1e-6:
                where = fmt((cell[0] * era.tile_studs, cell[1] * era.tile_studs))
                messages.append(f"{label}: stands on the road cell {where}")
                break
        if ring_reach(poly) > ring_inner - 1e-6:
            messages.append(f"{label}: reaches into the highway pillar band")
        face = entry["facing"]
        front = (
            entry["position"][0] + face[0] * era.subway_size[1] / 2,
            entry["position"][1] + face[1] * era.subway_size[1] / 2,
        )
        nearest = min(
            (point_segment_distance(front, a, b) for _, a, b in era.spine_segments()),
            key=lambda hit: hit[0],
            default=None,
        )
        if nearest is None:
            messages.append(f"{label}: there are no streets to face")
        elif nearest[0] > half_road + SUBWAY_STREET_REACH:
            messages.append(f"{label}: its front is {nearest[0]:.1f} studs from the nearest street, not on a pavement")
        elif (nearest[1][0] - front[0]) * face[0] + (nearest[1][1] - front[1]) * face[1] < -1e-6:
            messages.append(f"{label}: faces away from the street it stands on")
    return messages


def street_tree_spots(era):
    """Scatter.streetTreeSpots, spot for spot: every `treeSpacing` from a block corner along each
    block edge that runs alongside a street, `treeInset` inside the edge, dropping anything inside
    a solid or on a spur. The client plans these before the zone trees and they share
    `trees.maxCount` / `budget.trees`, so the tool has to count them to check that cap.

    Footprints here are the tool's declared blueprint boxes rather than the client's harvested
    extents, which are usually a little larger -- so this errs toward counting *more* spots, and
    the budget check errs toward firing early."""
    tiles = era.tiles
    config = tiles.get("blocks") if tiles else None
    if config is None or not era.blocks or not era.dressing["trees"].get("prop"):
        return []
    spacing = config.get("treeSpacing")
    if not isinstance(spacing, (int, float)) or isinstance(spacing, bool) or spacing < MIN_LENGTH:
        return []
    inset = max(float(config.get("treeInset", 0)), 0.0)
    # Daylight between a trunk and anything it stands beside, from the config the client reads.
    clearance = max(float(config.get("treeClearance", STREET_TREE_CLEARANCE)), 0.0)
    reach = era.width / 2 + 2 * era.pavement + clearance
    spur_width = tiles["spur"]["width"] if tiles and "spur" in tiles else era.width
    solids = [slot["footprint"] for slot in era.slots] + [slot["pad_poly"] for slot in era.slots]
    solids += [lot["poly"] for lot in era.lots] + [plaza["poly"] for plaza in era.plazas]
    solids += [entry["poly"] for entry in era.subways]
    spur_segments = [seg for spur in era.spurs.values() for seg in polyline_segments(spur["points"])]

    def nearest_piece(point):
        best = (math.inf, None)
        for _, a, b in era.spine_segments():
            distance, _closest = point_segment_distance(point, a, b)
            if distance < best[0]:
                best = (distance, unit((b[0] - a[0], b[1] - a[1])))
        return best

    def blocked(point):
        if any(point_polygon_distance(point, poly) < clearance for poly in solids):
            return True
        return any(
            point_segment_distance(point, a, b)[0] < spur_width / 2 + clearance
            for a, b in spur_segments
        )

    spots = []
    for block in era.blocks:
        min_x, max_x = min(block["min"][0], block["max"][0]), max(block["min"][0], block["max"][0])
        min_z, max_z = min(block["min"][1], block["max"][1]), max(block["min"][1], block["max"][1])
        edges = (
            ((min_x, min_z), (max_x, min_z), (0.0, 1.0)),
            ((max_x, min_z), (max_x, max_z), (-1.0, 0.0)),
            ((min_x, max_z), (max_x, max_z), (0.0, -1.0)),
            ((min_x, min_z), (min_x, max_z), (1.0, 0.0)),
        )
        for start, end, inward in edges:
            length = math.dist(start, end)
            if length < spacing:
                continue
            along = ((end[0] - start[0]) / length, (end[1] - start[1]) / length)
            midpoint = (
                (start[0] + end[0]) / 2 + inward[0] * inset,
                (start[1] + end[1]) / 2 + inward[1] * inset,
            )
            distance, direction = nearest_piece(midpoint)
            parallel = direction is not None and abs(direction[0] * along[0] + direction[1] * along[1]) > STRAIGHT_ENOUGH
            if distance > reach or not parallel:
                continue
            for step in range(1, int(length // spacing) + 1):
                position = (
                    start[0] + along[0] * spacing * step + inward[0] * inset,
                    start[1] + along[1] * spacing * step + inward[1] * inset,
                )
                if blocked(position) or nearest_piece(position)[1] is None:
                    continue
                spots.append(position)
    return spots


def parallel_street_violations(era):
    """Two streets closer than both their pavements would overlap the strips into one slab of
    concrete and leave no ground between them, which no block rect could then fill."""
    messages = []
    need = 2 * (era.width / 2 + era.pavement) + 1
    segments = list(era.spine_segments())
    for index, (line_a, a0, a1) in enumerate(segments):
        for line_b, b0, b1 in segments[index + 1 :]:
            axis_a = 0 if abs(a1[1] - a0[1]) < 1e-6 else (1 if abs(a1[0] - a0[0]) < 1e-6 else None)
            axis_b = 0 if abs(b1[1] - b0[1]) < 1e-6 else (1 if abs(b1[0] - b0[0]) < 1e-6 else None)
            if axis_a is None or axis_b is None or axis_a != axis_b:
                continue
            other = 1 - axis_a
            gap = abs(a0[other] - b0[other])
            if gap < 1e-6 or gap >= need - 1e-6:
                continue  # collinear runs of one street, or far enough apart
            lo_a, hi_a = sorted((a0[axis_a], a1[axis_a]))
            lo_b, hi_b = sorted((b0[axis_a], b1[axis_a]))
            if min(hi_a, hi_b) - max(lo_a, lo_b) <= 0:
                continue  # they never run beside each other
            messages.append(
                f"streets {line_a + 1} {fmt(a0)}->{fmt(a1)} and {line_b + 1} {fmt(b0)}->{fmt(b1)}: "
                f"{gap:g} studs apart, pavements overlap (need {need:g})"
            )
    return messages


def block_violations(era, cells):
    """Paved blocks: one slab per rect, so the rect has to stay off everything the client draws at
    ground level -- road cells, the pavement strip either side of a centreline, plazas, kiosks and
    the highway pillar band -- and off its neighbours. It may run under footprints and pads: that
    is what makes a block read as one paved city block."""
    messages, notes = [], []
    # The amendment lets a slab run under the elevated deck and its ramp right out to the plot
    # edge (the ramp foot's own road tile sits on top of it), so unlike a plaza or a kiosk a block
    # has no business with the pillar band.
    pavement_clear = era.width / 2 + era.pavement
    known = {slot["id"]: slot for slot in era.slots}
    listed = {}
    for index, block in enumerate(era.blocks):
        label = f"block {index + 1} {fmt(block['min'])}..{fmt(block['max'])}"
        if block["max"][0] - block["min"][0] <= 0 or block["max"][1] - block["min"][1] <= 0:
            messages.append(f"{label}: min is not below max on both axes")
            continue
        for corner in block["poly"]:
            if abs(corner[0]) > era.half_x or abs(corner[1]) > era.half_z:
                messages.append(f"{label}: leaves the plot")
                break
        for _, a, b in era.spine_segments():
            d = segment_polygon_distance(a, b, block["poly"])
            if d < pavement_clear - 1e-6:
                messages.append(f"{label}: {d:.2f} from street {fmt(a)}->{fmt(b)} (need {pavement_clear:g}, road + pavement)")
                break
        for cell in cells:
            if polygon_polygon_distance(block["poly"], era.cell_square(cell)) < 1e-6:
                where = fmt((cell[0] * era.tile_studs, cell[1] * era.tile_studs))
                messages.append(f"{label}: covers the road cell {where}")
                break
        for j, plaza in enumerate(era.plazas):
            if polygon_polygon_distance(block["poly"], plaza["poly"]) < 1e-6:
                messages.append(f"{label}: overlaps plaza {j + 1}")
        for j, entry in enumerate(era.subways):
            if polygon_polygon_distance(block["poly"], entry["poly"]) < 1e-6:
                messages.append(f"{label}: overlaps subway entrance {j + 1}")
        for j, other in enumerate(era.blocks[index + 1 :], start=index + 2):
            d = polygon_polygon_distance(block["poly"], other["poly"])
            if d < BLOCK_GAP - 1e-6:
                messages.append(f"{label}: {d:.2f} from block {j} (need {BLOCK_GAP}, or the two slabs share a plane)")
        for slot_id in block["slots"]:
            slot = known.get(slot_id)
            if slot is None:
                messages.append(f"{label}: lists {slot_id}, which is not a slot of this era")
                continue
            listed.setdefault(slot_id, []).append(index + 1)
            if not point_in_polygon(slot["position"], block["poly"]):
                messages.append(f"{label}: lists {slot_id}, whose anchor {fmt(slot['position'])} is outside it")
    for slot_id, blocks in sorted(listed.items()):
        if len(blocks) > 1:
            messages.append(f"slot {slot_id} is listed on blocks {blocks}; its slab would be drawn twice")
    if era.blocks:
        homeless = [
            slot["id"] for slot in era.slots if slot["type"] == "building" and slot["id"] not in listed
        ]
        if homeless:
            notes.append(f"{len(homeless)} building slot(s) stand on no paved block: {', '.join(homeless)}")
    return messages, notes


# --------------------------------------------------------------------------
# Wave 2c -- living city: lots by kind, parked bays, greenery zones
# --------------------------------------------------------------------------


def band(a, b, half):
    """A street's ground as a rectangle `half` either side of a-b with square ends `half` past
    each end -- the shape a tile street and its pavement actually cover, corners included."""
    length = math.dist(a, b)
    if length < MIN_LENGTH:
        return square(a, half * 2, half * 2, 0)
    ux, uz = (b[0] - a[0]) / length, (b[1] - a[1]) / length
    nx, nz = -uz * half, ux * half
    a2 = (a[0] - ux * half, a[1] - uz * half)
    b2 = (b[0] + ux * half, b[1] + uz * half)
    return [(a2[0] + nx, a2[1] + nz), (b2[0] + nx, b2[1] + nz), (b2[0] - nx, b2[1] - nz), (a2[0] - nx, a2[1] - nz)]


def spur_half_width(era):
    """A tiles era draws spurs as narrower footpaths (road.tiles.spur.width); elsewhere a spur is
    as wide as the road."""
    if era.tiles and "spur" in era.tiles:
        return float(era.tiles["spur"]["width"]) / 2
    return era.width / 2 + era.amplitude


def spur_segments(era):
    return [seg for spur in era.spurs.values() for seg in polyline_segments(spur["points"]) if math.dist(*seg) >= MIN_LENGTH]


def pier_squares(era):
    """One square per ring cell, PIER_HALF either side of the cell centre (the pier cap)."""
    if era.highway is None or era.tile_studs <= 0:
        return []
    ring = float(era.highway["ring"])
    cells = int(round_half(ring / era.tile_studs))
    centres = set()
    for i in range(-cells, cells + 1):
        along = i * era.tile_studs
        for c in ((along, -ring), (along, ring), (-ring, along), (ring, along)):
            centres.add((round(c[0], 6), round(c[1], 6)))
    return [square(c, PIER_HALF * 2, PIER_HALF * 2, 0) for c in sorted(centres)]


def ramp_squares(era):
    # Wave 2b loop mode (the Orbital monorail) has no ramp.
    ramp = era.highway_ramp
    if ramp is None or era.tile_studs <= 0:
        return []
    cell = xz(ramp["cell"])
    direction = RAMP_DIRECTIONS.get(ramp["direction"], (0.0, 0.0))
    step = era.tile_studs
    return [
        square((cell[0] + direction[0] * step * k, cell[1] + direction[1] * step * k), step, step, 0)
        for k in range(1, era.ramp_cells + 1)
    ]


def spur_path_width(era):
    """RoadGraph's state.spurWidth: a tiles era's footpath width, the road width elsewhere."""
    if era.tiles and "spur" in era.tiles:
        return float(era.tiles["spur"]["width"])
    return era.width


def trimmed(points, start, back):
    """RoadGraph.trimmed: the part of a polyline from arc `start` to `back` short of its end."""
    total = sum(math.dist(a, b) for a, b in polyline_segments(points))
    stop = total - back
    if stop - start < MIN_LENGTH:
        return None
    kept, arc = [], 0.0
    for a, b in polyline_segments(points):
        length = math.dist(a, b)
        if length < MIN_LENGTH:
            continue
        lo, hi = max(start, arc), min(stop, arc + length)
        if hi > lo:
            p, q = lerp(a, b, (lo - arc) / length), lerp(a, b, (hi - arc) / length)
            if not kept or math.dist(kept[-1], p) > 1e-9:
                kept.append(p)
            kept.append(q)
        arc += length
    return kept if len(kept) >= 2 else None


def offset_polyline(points, off):
    """Each segment moved `off` to its right (RoadGraph: (b - a).Unit:Cross(UP) * side)."""
    segments = []
    for a, b in polyline_segments(points):
        d = unit((b[0] - a[0], b[1] - a[1]))
        if d is None:
            continue
        r = (-d[1] * off, d[0] * off)
        segments.append(((a[0] + r[0], a[1] + r[1]), (b[0] + r[0], b[1] + r[1])))
    return segments


def walk_lanes(era, network, visible):
    """RoadGraph.buildWalkLanes at full ownership, on straight centrelines (a meander moves lanes and
    the things beside them alike): both sides of every drawn stretch at `pedestrians.offset`, and
    both sides of every drawn spur at min(offset, spurWidth / 2), from the pad's inner edge (the
    door) to the kerb of the street it joins."""
    config = era.dressing.get("pedestrians")
    if not config or "offset" not in config:
        return []
    offset = max(float(config["offset"]), 0.0)
    lanes = []
    for sid in sorted(visible):
        stretch = network.stretches[sid]
        for side in (1, -1):
            segments = offset_polyline([stretch["a"], stretch["b"]], offset * side)
            if segments:
                lanes.append({"kind": "street", "key": sid, "owner": None, "segments": segments})
    spur_side = min(offset, spur_path_width(era) / 2)
    for slot in era.slots:
        spur = era.spurs[slot["id"]]
        if spur["none"] or len(spur["points"]) < 2:
            continue
        door = max(math.dist(slot["pad"], slot["position"]) - era.pad_size[1] / 2, 0.0)
        kerb = era.width / 2 if spur["joins"] else 0.0
        walk = trimmed(spur["points"], door, kerb)
        if walk is None:
            continue
        for side in (1, -1):
            segments = offset_polyline(walk, spur_side * side)
            if segments:
                lanes.append({"kind": "spur", "key": slot["id"], "owner": slot["id"], "segments": segments})
    return lanes


def walk_lines(era, network, visible):
    return [segment for lane in walk_lanes(era, network, visible) for segment in lane["segments"]]


def post_size(era, prop):
    """Base width of a pole prop: its narrower harvested extent (an arm or a lamp head is up high,
    out of a walker's way)."""
    extents = harvested_extents(era.name, prop) if prop else None
    return min(extents[0], extents[2]) if extents else POST_FALLBACK


def planner_solids(era):
    """Scatter.solidsFor with the declared footprints: every slot that spawns a model, every pad,
    lot, plaza and subway kiosk, as (name, kind, polygon, owning slot id or None)."""
    street_only = {slot["id"] for slot in era.config["slots"] if slot.get("streetOnly")}
    solids = []
    for slot in era.slots:
        if slot["id"] not in street_only:
            solids.append((f"{slot['id']} footprint", "slot footprint", slot["footprint"], slot["id"]))
        solids.append((f"{slot['id']} pad", "pad", slot["pad_poly"], slot["id"]))
    solids += [(f"lot {j + 1}", f"{lot['kind']} lot", lot["poly"], None) for j, lot in enumerate(era.lots)]
    solids += [(f"plaza {j + 1}", "plaza", plaza["poly"], None) for j, plaza in enumerate(era.plazas)]
    solids += [(f"subway entrance {j + 1}", "subway kiosk", entry["poly"], None) for j, entry in enumerate(era.subways)]
    return solids


def row_lamp_posts(era, network):
    """Scatter.lampPosts ("row" placement): a post every `spacing` of arc along each street run,
    alternating sides, width / 2 + offset out, dropped inside a solid or within width / 2 of another
    street or a spur, thinned evenly to budget.lampPosts. A run is taken as the stretches its
    polyline owns, in order -- the client's runs may split a shared ring differently, so treat the
    positions as a close mirror, not an exact one."""
    lamps = era.dressing.get("lamps") or {}
    spacing = lamps.get("spacing")
    if not lamps.get("prop") or lamps.get("placement") != "row" or not spacing or spacing < MIN_LENGTH:
        return []
    reach = era.width / 2 + max(float(lamps.get("offset", 0)), 0.0)
    clearance = era.width / 2
    solids = [poly for _, _, poly, _ in planner_solids(era)]
    spurs = spur_segments(era)
    posts = []
    for polyline in range(len(era.streets)):
        ids = [sid for sid, s in enumerate(network.stretches) if s["polyline"] == polyline and s["segment"] is not None]
        ids.sort(key=lambda sid: (network.stretches[sid]["segment"], network.stretches[sid]["t0"]))
        points, arcs, total = [], [], 0.0
        for sid in ids:
            for p in (network.stretches[sid]["a"], network.stretches[sid]["b"]):
                if points:
                    advance = math.dist(p, points[-1])
                    if advance < MIN_LENGTH:
                        continue
                    total += advance
                points.append(p)
                arcs.append(total)
        if len(points) < 2:
            continue
        others = [(a, b) for index, a, b in era.spine_segments() if index != polyline]
        index = 1
        for step in range(1, int(total // spacing) + 1):
            target = spacing * step
            while index < len(arcs) - 1 and arcs[index] < target:
                index += 1
            a, b = points[index - 1], points[index]
            d = unit((b[0] - a[0], b[1] - a[1]))
            if d is None:
                continue
            hand = 1 if step % 2 == 1 else -1
            span = arcs[index] - arcs[index - 1]
            base = lerp(a, b, (target - arcs[index - 1]) / span if span > 0 else 0.0)
            position = (base[0] - d[1] * hand * reach, base[1] + d[0] * hand * reach)
            if any(point_in_polygon(position, poly) for poly in solids):
                continue
            if any(point_segment_distance(position, p, q)[0] < clearance for p, q in others + spurs):
                continue
            posts.append(position)
    cap = int(budget_value(era.city.get("budget", {}).get("lampPosts"), era.city["lamps"]["maxPerPlot"]))
    count = len(posts)
    if count <= cap:
        return posts
    return [post for i, post in enumerate(posts, start=1) if (i * cap) // count != ((i - 1) * cap) // count]


def junction_lamp_spots(era):
    """Scatter.LampFrame at every spur junction ("junction" placement). The client lights a seeded
    subset; every candidate is returned, since any of them may be one that is lit."""
    lamps = era.dressing.get("lamps") or {}
    if not lamps.get("prop") or lamps.get("placement", "junction") != "junction":
        return []
    spots = []
    for slot in era.slots:
        spur = era.spurs[slot["id"]]
        if not spur["joins"] or len(spur["points"]) < 2:
            continue
        a, b = spur["points"][-2], spur["points"][-1]
        d = unit((b[0] - a[0], b[1] - a[1]))
        if d is None:
            continue
        back = max(0.0, min(math.dist(a, b), era.width))
        right = (-d[1], d[0])
        spots.append((b[0] - d[0] * back + right[0] * era.width / 2, b[1] - d[1] * back + right[1] * era.width / 2))
    return spots


def signal_spots(era, network):
    """RoadGraph.SignalSpots: at each node where three or more stretches meet, in node order, the
    corner of the widest usable gap, `offset` outside both road edges, capped at maxPerPlot."""
    config = era.dressing.get("signals")
    if not config or not config.get("prop"):
        return []
    reach = era.width / 2 + max(float(config.get("offset", 0)), 0.0)
    cap = config.get("maxPerPlot", math.inf)
    spots = []
    for node, stretch_ids in enumerate(network.node_stretches):
        if len(spots) >= cap:
            break
        if len(stretch_ids) < SIGNAL_MIN_ARMS:
            continue
        point = network.nodes[node]
        arms = []
        for sid in stretch_ids:
            stretch = network.stretches[sid]
            far = stretch["b"] if stretch["from"] == node else stretch["a"]
            d = unit((far[0] - point[0], far[1] - point[1]))
            if d is not None:
                arms.append(d)
        if len(arms) < SIGNAL_MIN_ARMS:
            continue
        arms.sort(key=lambda v: math.atan2(v[1], v[0]))
        corner, best = None, 0.0
        for i, arm in enumerate(arms):
            following = arms[(i + 1) % len(arms)]
            angle = math.atan2(following[1], following[0]) - math.atan2(arm[1], arm[0])
            if angle <= 0:
                angle += math.tau
            if SIGNAL_GAP_MIN <= angle <= SIGNAL_GAP_MAX and angle > best:
                corner, best = unit((arm[0] + following[0], arm[1] + following[1])), angle
        if corner is None:
            continue
        distance = reach / math.sin(best / 2)
        spots.append((point[0] + corner[0] * distance, point[1] + corner[1] * distance))
    return spots


def street_posts(era, network):
    """(kind, polygon) for every lamp post and signal the client may stand beside a street."""
    posts = []
    lamps = era.dressing.get("lamps") or {}
    size = post_size(era, lamps.get("prop"))
    posts += [("row lamp", square(p, size, size, 0)) for p in row_lamp_posts(era, network)]
    posts += [("junction lamp", square(p, size, size, 0)) for p in junction_lamp_spots(era)]
    signals = era.dressing.get("signals") or {}
    size = post_size(era, signals.get("prop"))
    posts += [("signal", square(p, size, size, 0)) for p in signal_spots(era, network)]
    return posts


def walk_clip_report(era, network, visible):
    """Where the client clips walk lanes: every stretch of a lane that passes within
    `pedestrians.clearance` of a solid other than a pad (a spur's lanes never clip on their own building).
    Returns (clip count, clips by kind of solid, violations). A clip is only a dead end, so it is
    information; a street whose lanes are clipped end to end on *both* sides has nowhere to walk."""
    config = era.dressing.get("pedestrians")
    if not config:
        return 0, {}, []
    clearance = max(float(config.get("clearance", 0)), 0.0)
    # Pads are flat and walkable, so walkers cross them (lead ruling, 2026-09-23).
    solids = [(kind, poly, owner) for _, kind, poly, owner in planner_solids(era) if kind != "pad"]
    solids += [(kind, poly, None) for kind, poly in street_posts(era, network)]
    boxes = []
    for kind, poly, owner in solids:
        xs, zs = [p[0] for p in poly], [p[1] for p in poly]
        boxes.append((min(xs) - clearance, max(xs) + clearance, min(zs) - clearance, max(zs) + clearance, kind, poly, owner))
    clips, hits, sides = 0, {}, {}
    for lane in walk_lanes(era, network, visible):
        flags = []
        for a, b in lane["segments"]:
            steps = max(1, int(math.dist(a, b) / WALK_SAMPLE))
            for k in range(steps + 1):
                q = lerp(a, b, k / steps)
                hit = None
                for x0, x1, z0, z1, kind, poly, owner in boxes:
                    if owner is not None and owner == lane["owner"]:
                        continue
                    if not (x0 <= q[0] <= x1 and z0 <= q[1] <= z1):
                        continue
                    if point_in_polygon(q, poly) or point_polygon_distance(q, poly) < clearance - 1e-6:
                        hit = kind
                        break
                flags.append(hit)
        previous = None
        for hit in flags:
            if hit is not None and previous is None:
                clips += 1
                hits[hit] = hits.get(hit, 0) + 1
            previous = hit
        sides.setdefault((lane["kind"], lane["key"]), []).append(bool(flags) and all(flag is not None for flag in flags))
    violations = []
    for (kind, key), clipped in sides.items():
        if kind == "street" and len(clipped) == 2 and all(clipped):
            stretch = network.stretches[key]
            violations.append(
                f"walk lanes: street {fmt(stretch['a'])}->{fmt(stretch['b'])} is clipped end to end on both "
                "sides, so no walker can use it"
            )
    return clips, hits, violations


def walker_vehicle_violations(era):
    """A walker on its lane must clear the cars on theirs: offset - WALKER_HALF >= the vehicle lane
    offset + half the widest harvested vehicle."""
    config = era.dressing.get("pedestrians")
    vehicles = era.dressing.get("vehicles") or {}
    if not config or "offset" not in config:
        return []
    fraction = era.dressing["road"].get("laneOffsetFraction", era.city["road"]["laneOffsetFraction"])
    scale = config_scale(vehicles)
    widths = [e[0] for e in (scaled_extents(era.name, p, scale) for p in vehicles.get("props", [])) if e]
    if not widths:
        return []
    car_edge = fraction * era.width + max(widths) / 2
    walker_edge = float(config["offset"]) - walker_half(era)
    if walker_edge < car_edge - 1e-6:
        return [
            f"pedestrians.offset {config['offset']:g}: a walker reaches {walker_edge:.2f} from the centreline, "
            f"into the cars (to {car_edge:.2f})"
        ]
    return []


def lot_count_violations(era):
    messages = []
    for kind in sorted({lot["kind"] for lot in era.lots}):
        count = sum(1 for lot in era.lots if lot["kind"] == kind)
        if kind not in LOT_KINDS:
            messages.append(f"lots: {count} of kind {kind!r}, which is not one of {sorted(LOT_KINDS)}")
        elif not era.lot_props[kind]:
            key = "props" if kind == "house" else "smallProps"
            messages.append(f"lots: {count} {kind} lot(s) authored but eras.{era.name}.houses.{key} is empty, so none are drawn")
    for kind, props in era.lot_props.items():
        cap = LOT_KINDS[kind]
        for name, footprint in declared_footprints(era.name, props):
            if footprint[0] > cap[0] + 1e-6 or footprint[1] > cap[1] + 1e-6:
                messages.append(f"houses: {name} blueprint footprint {footprint} exceeds the {kind} cap {cap}")
        for name in props:
            extents = harvested_extents(era.name, name)
            if extents is None:
                continue
            if extents[0] > cap[0] + 0.05 or extents[2] > cap[1] + 0.05:
                messages.append(f"houses: {name} harvests {extents[0]:.2f} x {extents[2]:.2f}, over the {kind} cap {cap}")
            if kind == "small" and extents[1] > SMALL_LOT_MAX_HEIGHT + 0.05:
                messages.append(f"houses: {name} harvests {extents[1]:.2f} tall, over the small cap {SMALL_LOT_MAX_HEIGHT}")
    if not any(era.lot_props.values()):
        return messages
    if era.name not in LOT_MINIMUM:
        low, high = LOT_COUNT_BY_ERA.get(era.name, LEGACY_LOT_COUNT)
        if not low <= len(era.lots) <= high:
            messages.append(f"lots: {len(era.lots)}, need {low}-{high}")
        return messages
    minimum = LOT_MINIMUM[era.name]
    if len(era.lots) < minimum:
        messages.append(f"lots: {len(era.lots)}, need at least {minimum}")
    for tier in range(LOT_TIERS[0], LOT_TIERS[1] + 1):
        count = sum(1 for lot in era.lots if lot["tier"] == tier)
        if count < LOT_PER_TIER:
            messages.append(f"lots: tier {tier} adds {count}, need at least {LOT_PER_TIER} so every tier step shows new houses")
    # budget.fillerPieces holds plazas, lots and junction lamps together (row lamps have their own).
    lamps = era.dressing.get("lamps") or {}
    junction_lamps = era.city["lamps"]["maxPerPlot"] if lamps.get("prop") and lamps.get("placement", "junction") == "junction" else 0
    filler = len(era.lots) + len(era.plazas) + junction_lamps
    cap = budget_value(era.city.get("budget", {}).get("fillerPieces"), math.inf)
    if filler > cap:
        messages.append(
            f"filler pieces {filler} (lots {len(era.lots)} + plazas {len(era.plazas)} + junction lamps {junction_lamps}) "
            f"> budget.fillerPieces {cap:g}"
        )
    return messages


def lot_violations(era, index, lot, drawn, cells):
    """Every placement rule for one lot. `drawn` is the full-ownership road set check() builds
    (visible stretches plus every spur, each with the polygons its own building may hide it in)."""
    messages = []
    label = f"lot {index + 1} {fmt(lot['position'])} {lot['kind']}"
    poly = lot["poly"]
    small = lot["kind"] == "small"
    tiers = LOT_TIERS if era.name in LOT_MINIMUM else LEGACY_LOT_TIERS
    if not tiers[0] <= lot["tier"] <= tiers[1]:
        messages.append(f"{label}: tier {lot['tier']:g} outside {tiers}")
    for slot in era.slots:
        furniture = slot["id"] in era.furniture and era.tiles is not None  # streetOnly: no model spawns
        if not furniture:
            if small:
                d = gap(poly, slot["footprint"])
                if d < SMALL_LOT_SLOT_GAP - 1e-6:
                    messages.append(f"{label}: {d:.2f} from {slot['id']} footprint (need {SMALL_LOT_SLOT_GAP})")
            else:
                d = point_polygon_distance(lot["position"], slot["footprint"])
                if d < LOT_SLOT_CLEARANCE - 1e-6:
                    messages.append(f"{label}: {d:.2f} from {slot['id']} footprint (need {LOT_SLOT_CLEARANCE})")
                if gap(poly, slot["footprint"]) <= 0:
                    messages.append(f"{label}: house overlaps {slot['id']}")
        if gap(poly, slot["pad_poly"]) < 1:
            messages.append(f"{label}: house touches the {slot['id']} pad")
    if gap(poly, era.sign_poly) < 1:
        messages.append(f"{label}: house touches the Sign")
    half_road = era.width / 2 + era.amplitude
    for _, a, b in era.spine_segments():
        if era.tiles is not None:
            # A tile street's pavement is part of the street: the house stands behind it.
            d = gap(poly, band(a, b, era.width / 2 + era.pavement))
            if d < 0.5 - 1e-6:
                messages.append(f"{label}: {d:.2f} from the pavement of street {fmt(a)}->{fmt(b)} (need 0.5)")
        elif segment_polygon_distance(a, b, poly) < half_road + 0.5:
            messages.append(f"{label}: house sits on street {fmt(a)}->{fmt(b)}")
    for j, other in enumerate(era.lots):
        if j != index and gap(poly, other["poly"]) < 1:
            messages.append(f"{label}: house overlaps lot {j + 1}")
    for j, plaza in enumerate(era.plazas):
        if gap(poly, plaza["poly"]) < 1:
            messages.append(f"{label}: house overlaps plaza {j + 1}")
    for j, entry in enumerate(era.subways):
        if gap(poly, entry["poly"]) < SUBWAY_CLEARANCE - 1e-6:
            messages.append(f"{label}: too close to subway entrance {j + 1}")
    for corner in poly:
        if abs(corner[0]) > era.half_x - 1 or abs(corner[1]) > era.half_z - 1:
            messages.append(f"{label}: house leaves the plot")
            break
    if era.highway is not None:
        inner = float(era.highway["ring"]) - era.tile_studs / 2
        if ring_reach(poly) > inner + 1e-6 and not small:
            messages.append(f"{label}: reaches {ring_reach(poly):g} studs, under the ring deck (from {inner:g}), so it must be small")
        for pier in pier_squares(era):
            if gap(poly, pier) < PIER_GAP - 1e-6:
                messages.append(f"{label}: within {PIER_GAP} of a ring pier")
                break
        for ramp in ramp_squares(era):
            if gap(poly, ramp) < 0.5 - 1e-6:
                messages.append(f"{label}: under the highway ramp")
                break
    face = facing(lot["rotation"])
    front = (lot["position"][0] + face[0] * lot["depth"] / 2, lot["position"][1] + face[1] * lot["depth"] / 2)
    nearest = min((nearest_outside(front, a, b, own) for a, b, own in drawn), key=lambda item: item[0])
    facing_dot = (nearest[1][0] - front[0]) * face[0] + (nearest[1][1] - front[1]) * face[1]
    if nearest[0] > LOT_FRONT_REACH or facing_dot < 0:
        messages.append(f"{label}: does not face a drawn road (nearest {nearest[0]:.1f} studs from its front)")
    return messages


def per_tier_list(config, key, label):
    """A cumulative perTier list: five non-decreasing non-negative numbers, or a message."""
    values = config.get(key)
    if not isinstance(values, list) or len(values) != 5:
        return None, f"{label}.{key} must list 5 numbers (tiers 1-5)"
    if any(v < 0 for v in values) or any(values[i] > values[i + 1] for i in range(4)):
        return None, f"{label}.{key} {values} must be non-negative and non-decreasing (it is cumulative)"
    return values, None


def parking_violations(era, network, visible):
    messages = []
    config = era.dressing.get("parked")
    label_cfg = f"eras.{era.name}.parked"
    if era.parking and not config:
        messages.append(f"parking: {len(era.parking)} spots authored but {label_cfg} is absent, so none are drawn")
    per_tier = None
    if config:
        if not config.get("props"):
            messages.append(f"{label_cfg}.props is empty")
        per_tier, problem = per_tier_list(config, "perTier", label_cfg)
        if problem:
            messages.append(problem)
        cap = budget_value(era.city.get("budget", {}).get("parked"), math.inf)
        # perTier counts bays, budget.parked counts cars (wave 2d), and every bay may take perBay.
        cars = per_bay(config)
        if per_tier and per_tier[-1] * cars > cap:
            messages.append(
                f"{label_cfg}.perTier reaches {per_tier[-1]} bays x perBay {cars} > budget.parked {cap:g} cars"
            )
    if per_tier:
        for tier in range(1, 6):
            available = sum(1 for spot in era.parking if effective_spot_tier(era, spot) <= tier)
            if available < per_tier[tier - 1]:
                messages.append(f"parking: {available} spots by tier {tier}, but perTier asks for {per_tier[tier - 1]}")

    half_road = era.width / 2 + era.amplitude
    spur_half = spur_half_width(era)
    spines = [(a, b) for _, a, b in era.spine_segments()]
    spurs = spur_segments(era)
    # A bay keeps clear of the walk lanes as they are drawn at full ownership.
    lanes = walk_lines(era, network, visible)
    solids = []
    for slot in era.slots:
        if slot["id"] not in era.furniture:
            solids.append((f"{slot['id']} footprint", slot["footprint"]))
        solids.append((f"{slot['id']} pad", slot["pad_poly"]))
    solids += [(f"lot {j + 1}", lot["poly"]) for j, lot in enumerate(era.lots)]
    solids += [(f"plaza {j + 1}", plaza["poly"]) for j, plaza in enumerate(era.plazas)]
    solids += [(f"subway entrance {j + 1}", entry["poly"]) for j, entry in enumerate(era.subways)]
    solids += [("the Sign", era.sign_poly)]
    # Lamp posts and signals, the row lamps included: a car parked across a lantern reads as a crash.
    solids += [(f"a {kind}", poly) for kind, poly in street_posts(era, network)]
    solids += [("a ring pier", pier) for pier in pier_squares(era)]
    solids += [("the highway ramp", ramp) for ramp in ramp_squares(era)]
    # A path only counts as a kerb where it is out in the open: the stretch under its own building
    # is hidden, and a bay behind that building is not beside anything.
    open_path = []
    for slot in era.slots:
        for a, b in polyline_segments(era.spurs[slot["id"]]["points"]):
            steps = max(1, int(math.dist(a, b) / 0.5))
            open_path += [
                q for q in (lerp(a, b, k / steps) for k in range(steps + 1)) if not point_in_polygon(q, slot["footprint"])
            ]
    for index, spot in enumerate(era.parking):
        label = f"parking {index + 1} {fmt(spot['position'])}"
        poly = spot["poly"]
        if not PARK_TIERS[0] <= spot["tier"] <= PARK_TIERS[1]:
            messages.append(f"{label}: tier {spot['tier']:g} outside {PARK_TIERS}")
        if spot["lot"] is not None:
            if not 1 <= spot["lot"] <= len(era.lots):
                messages.append(f"{label}: lot {spot['lot']} is not a lot of this layout")
            elif gap(poly, era.lots[spot["lot"] - 1]["poly"]) > 3:
                messages.append(f"{label}: a driveway spot, but {gap(poly, era.lots[spot['lot'] - 1]['poly']):.1f} studs from lot {spot['lot']}")
        for a, b in spines:
            if era.tiles is not None:
                d = gap(poly, band(a, b, era.width / 2))
            else:
                d = segment_polygon_distance(a, b, poly) - half_road
            if d < PARK_ROAD_GAP - 1e-6:
                messages.append(f"{label}: {d:.2f} outside the road edge of {fmt(a)}->{fmt(b)} (need {PARK_ROAD_GAP})")
        for a, b in spurs:
            d = segment_polygon_distance(a, b, poly) - spur_half
            if d < PARK_ROAD_GAP - 1e-6:
                messages.append(f"{label}: on the path {fmt(a)}->{fmt(b)}")
        for a, b in lanes:
            d = segment_polygon_distance(a, b, poly)
            if d < walker_half(era) + PARK_GAP - 1e-6:
                messages.append(f"{label}: {d:.2f} from the walk lane {fmt(a)}->{fmt(b)} (need {walker_half(era) + PARK_GAP:g})")
                break
        for name, solid in solids:
            if gap(poly, solid) < PARK_GAP - 1e-6:
                messages.append(f"{label}: {gap(poly, solid):.2f} from {name} (need {PARK_GAP})")
        for j, other in enumerate(era.parking):
            if j > index and gap(poly, other["poly"]) < PARK_GAP - 1e-6:
                messages.append(f"{label}: overlaps parking {j + 1}")
        for corner in poly:
            if abs(corner[0]) > era.half_x - 0.5 or abs(corner[1]) > era.half_z - 0.5:
                messages.append(f"{label}: leaves the plot")
                break
        kerb = min(
            [segment_polygon_distance(a, b, poly) - half_road for a, b in spines]
            + [point_polygon_distance(q, poly) - spur_half for q in open_path]
        )
        if kerb > PARK_STREET_REACH:
            messages.append(f"{label}: {kerb:.1f} studs from any road edge, not kerbside")
        # The controller shows a spot only while its nearest spine stretch is drawn.
        nearest = min(
            range(len(network.stretches)),
            key=lambda sid: point_segment_distance(spot["position"], network.stretches[sid]["a"], network.stretches[sid]["b"])[0],
            default=None,
        )
        if nearest is not None and nearest not in visible:
            messages.append(f"{label}: its nearest street stretch is never drawn, so the car never appears")
    return messages


def effective_spot_tier(era, spot):
    """A driveway spot shows only once its lot does."""
    tier = spot["tier"]
    if spot["lot"] is not None and 1 <= spot["lot"] <= len(era.lots):
        tier = max(tier, era.lots[spot["lot"] - 1]["tier"])
    return tier


def greenery_rules(era):
    """(keep from every centreline, piece spacing, blockers) -- Scatter.greenerySpots' numbers:
    road width / 2 + meander + pavement + roadClearance, raised to pedestrians.offset + spacing / 2
    where walkers stroll, from every spine *and* spur centreline; blockers are kept spacing / 2 off."""
    config = era.dressing.get("greenery") or {}
    clearance = max(float(config.get("clearance", 0)), 0.0)
    keep = era.width / 2 + era.amplitude + era.pavement + max(float(config.get("roadClearance", 0)), 0.0)
    pedestrians = era.dressing.get("pedestrians")
    if pedestrians:
        keep = max(keep, float(pedestrians.get("offset", 0)) + clearance / 2)
    solids = [slot["footprint"] for slot in era.slots if slot["id"] not in era.furniture]
    solids += [slot["pad_poly"] for slot in era.slots]
    solids += [lot["poly"] for lot in era.lots] + [plaza["poly"] for plaza in era.plazas]
    solids += [entry["poly"] for entry in era.subways] + [spot["poly"] for spot in era.parking]
    solids += pier_squares(era) + ramp_squares(era)
    return keep, clearance, solids


def greenery_violations(era):
    messages, notes = [], []
    config = era.dressing.get("greenery")
    zones = era.greenery_zones
    label_cfg = f"eras.{era.name}.greenery"
    if zones and not config:
        messages.append(f"greeneryZones: {len(zones)} authored but {label_cfg} is absent, so nothing is planted")
    if not config:
        return messages, notes
    if not config.get("props"):
        messages.append(f"{label_cfg}.props is empty")
    per_tier, problem = per_tier_list(config, "perTier", label_cfg)
    if problem:
        messages.append(problem)
    if not GREENERY_ZONE_COUNT[0] <= len(zones) <= GREENERY_ZONE_COUNT[1]:
        messages.append(f"greeneryZones: {len(zones)}, need {GREENERY_ZONE_COUNT[0]}-{GREENERY_ZONE_COUNT[1]}")
    total = sum(zone["count"] for zone in zones)
    garnish = float(config.get("lotGarnish", 0)) * len(era.lots)
    cap = budget_value(era.city.get("budget", {}).get("greenery"), math.inf)
    if per_tier:
        if total < per_tier[-1]:
            messages.append(f"greeneryZones hold {total} pieces, fewer than perTier's {per_tier[-1]}")
        if per_tier[-1] + garnish > cap:
            messages.append(
                f"greenery at tier 5: zones {per_tier[-1]} + lot garnish {garnish:g} = {per_tier[-1] + garnish:g} "
                f"> budget.greenery {cap:g}"
            )
    keep, _, solids = greenery_rules(era)
    lines = [(a, b) for _, a, b in era.spine_segments()] + spur_segments(era)
    inner = float(era.highway["ring"]) - era.tile_studs / 2 if era.highway else math.inf
    if per_tier and zones:
        yields = greenery_yields(era)
        low = yields[int(GREENERY_QUANTILE * (len(yields) - 1))]
        median = yields[len(yields) // 2]
        notes.append(
            f"greenery zone yield over {len(yields)} seeds: min {yields[0]}, "
            f"p{int(GREENERY_QUANTILE * 100)} {low}, median {median} (perTier tier 5 = {per_tier[-1]})"
        )
        if low < per_tier[-1]:
            messages.append(
                f"greeneryZones: the {int(GREENERY_QUANTILE * 100)}th-percentile yield is {low} pieces, fewer than "
                f"perTier's {per_tier[-1]} (the client draws `count` candidates per zone and never redraws)"
            )
    for index, zone in enumerate(zones):
        label = f"greenery zone {index + 1} {fmt(zone['center'])}"
        c = zone["center"]
        if abs(c[0]) > era.half_x or abs(c[1]) > era.half_z:
            messages.append(f"{label}: centre outside the plot")
        if any(point_segment_distance(c, a, b)[0] < keep for a, b in lines):
            messages.append(f"{label}: centre sits on a road (need {keep:g} from every centreline)")
        if any(point_in_polygon(c, solid) for solid in solids):
            messages.append(f"{label}: centre is inside a footprint, pad, lot, plaza or bay")
        if max(abs(c[0]), abs(c[1])) + zone["radius"] > inner - 1e-6:
            messages.append(f"{label}: reaches into the ring pillar band")
    return messages, notes


def _boxed(polys, margin):
    """(x0, x1, z0, z1, poly) with the box grown by `margin`, so a point test can skip most polygons."""
    boxed = []
    for poly in polys:
        xs, zs = [p[0] for p in poly], [p[1] for p in poly]
        boxed.append((min(xs) - margin, max(xs) + margin, min(zs) - margin, max(zs) + margin, poly))
    return boxed


def _near_any(p, boxed, margin):
    for x0, x1, z0, z1, poly in boxed:
        if x0 <= p[0] <= x1 and z0 <= p[1] <= z1:
            if point_in_polygon(p, poly) or point_polygon_distance(p, poly) < margin:
                return True
    return False


def greenery_yields(era, seeds=GREENERY_SEEDS):
    """Sorted zone-piece yields of Scatter.greenerySpots over `seeds` random streams: the zone trees
    are drawn first (Scatter.treeSpots: `count` draws per zone, thinned to the tree cap after the
    street trees), then each greenery zone draws exactly `count` candidates and keeps those that
    pass every rule *and* stand `clearance` from every tree and every piece already kept. The
    result is capped at perTier's tier-5 count, as the client caps it."""
    config = era.dressing["greenery"]
    per_tier = config.get("perTier") or [0]
    zone_cap = min(per_tier[-1], budget_value(era.city.get("budget", {}).get("greenery"), math.inf))
    keep, clearance, solids = greenery_rules(era)
    lines = [(a, b) for _, a, b in era.spine_segments()] + spur_segments(era)
    edge = era.city["trees"]["edgeMargin"]
    half_x, half_z = era.half_x - edge, era.half_z - edge
    sign_keep = era.dressing["trees"]["clearance"]
    boxed = _boxed(solids, clearance / 2)

    trees_cfg = era.dressing["trees"]
    tree_clear = trees_cfg["clearance"]
    anchors = [s["position"] for s in era.slots] + [s["pad"] for s in era.slots]
    anchors += [lot["position"] for lot in era.lots] + [p["position"] for p in era.plazas] + [era.sign]
    tree_road = era.width / 2 + era.amplitude + era.city["trees"]["roadClearance"]
    footprint_margin = era.city["trees"]["footprintMargin"]
    tree_solids = [poly for _, _, poly, _ in planner_solids(era)]
    tree_boxed = _boxed(tree_solids, footprint_margin)
    street_trees = street_tree_spots(era) if trees_cfg.get("prop") else []
    tree_cap = max(
        min(max(trees_cfg["maxCount"], 0), budget_value(era.city.get("budget", {}).get("trees"), math.inf)) - len(street_trees),
        0,
    )

    def near_line(p, limit):
        return any(point_segment_distance(p, a, b)[0] < limit for a, b in lines)

    def tree_ok(p):
        if abs(p[0]) > half_x or abs(p[1]) > half_z:
            return False
        if any(math.dist(p, a) < tree_clear for a in anchors):
            return False
        if _near_any(p, tree_boxed, footprint_margin):
            return False
        return not any(point_segment_distance(p, a, b)[0] < tree_road for a, b in lines)

    def piece_ok(p):
        if abs(p[0]) > half_x or abs(p[1]) > half_z or math.dist(p, era.sign) < sign_keep:
            return False
        if _near_any(p, boxed, clearance / 2):
            return False
        return not near_line(p, keep)

    yields = []
    for seed in range(seeds):
        rng = random.Random(seed * 7919 + 7001)
        trees = []
        if trees_cfg.get("prop"):
            for zone in era.zones:
                for _ in range(max(int(zone["count"]), 0)):
                    radial, angle = zone["radius"] * math.sqrt(rng.random()), math.tau * rng.random()
                    rng.random()
                    p = (zone["center"][0] + radial * math.cos(angle), zone["center"][1] + radial * math.sin(angle))
                    if tree_ok(p):
                        trees.append(p)
            if len(trees) > tree_cap:
                total = len(trees)
                trees = [t for i, t in enumerate(trees, start=1) if (i * tree_cap) // total != ((i - 1) * tree_cap) // total]
        taken = trees + street_trees
        kept = 0
        for zone in era.greenery_zones:
            for _ in range(max(int(zone["count"]), 0)):
                radial, angle = zone["radius"] * math.sqrt(rng.random()), math.tau * rng.random()
                rng.random()
                rng.random()
                p = (zone["center"][0] + radial * math.cos(angle), zone["center"][1] + radial * math.sin(angle))
                if piece_ok(p) and all(math.dist(p, q) >= clearance for q in taken):
                    taken.append(p)
                    kept += 1
        yields.append(min(kept, zone_cap))
    return sorted(yields)


def scatter_greenery(era):
    """Preview of the greenery rules (INTERFACES "Greenery"): candidates in each zone, kept when
    clear of roads by roadClearance, of every footprint/pad/lot/plaza/bay and of each other. The
    RNG is not the client's, so this shows where pieces can land and how crowded a zone is."""
    config = era.dressing.get("greenery")
    if not config:
        return [], []
    keep, clearance, solids = greenery_rules(era)
    lines = [(a, b) for _, a, b in era.spine_segments()] + spur_segments(era)
    edge = era.city["trees"]["edgeMargin"]
    sign_keep = era.dressing["trees"]["clearance"]
    rng = random.Random(era.name + "greenery")
    placed, stats = [], []
    for zone in era.greenery_zones:
        kept, usable, samples = [], 0, 400
        for _ in range(samples):
            angle = rng.random() * math.tau
            radius = zone["radius"] * math.sqrt(rng.random())
            p = (zone["center"][0] + math.cos(angle) * radius, zone["center"][1] + math.sin(angle) * radius)
            if abs(p[0]) > era.half_x - edge or abs(p[1]) > era.half_z - edge:
                continue
            if math.dist(p, era.sign) < sign_keep:
                continue
            if any(point_segment_distance(p, a, b)[0] < keep for a, b in lines):
                continue
            if any(point_in_polygon(p, solid) or point_polygon_distance(p, solid) < clearance / 2 for solid in solids):
                continue
            usable += 1
            if len(kept) < zone["count"] and all(math.dist(p, q) >= clearance for q in placed + kept):
                kept.append(p)
        stats.append((zone, usable / samples, len(kept)))
        placed += kept
    return placed, stats


def check(era, network, visible, unreachable):
    violations = []
    notes = []
    width = era.width
    half_road = width / 2 + era.amplitude
    spine_clear = half_road + SPINE_EXTRA_CLEARANCE
    # Wave 2a: in a tiles era the pad belongs *on* the sidewalk. A corridor between two 9x9 blocks
    # is 19 studs and road + pavement takes 15 of them, so a 6-deep pad in front of a facade always
    # comes within width / 2 of the centreline -- and a smaller padOffset would put the pad inside
    # the building instead. It only has to stay off the asphalt.
    pad_clear = half_road if era.tiles is not None else spine_clear
    cells = era.road_cells()  # empty unless the era draws kit tiles

    def add(message):
        violations.append(message)

    if not STREET_COUNT[0] <= len(era.streets) <= STREET_COUNT[1]:
        add(f"streets: {len(era.streets)} polylines, need {STREET_COUNT[0]}-{STREET_COUNT[1]}")
    for index, ys in enumerate(era.street_y):
        if any(abs(y) > 1e-9 for y in ys):
            add(f"street {index + 1}: a point is not at Y 0")
    # Wave 2a: a tile street carries a pavement strip either side, and that strip is what
    # reaches the plot edge first, so the outermost legal centreline moves in by its width.
    edge_half = half_road + era.pavement
    limit_x = era.half_x - edge_half - EDGE_MARGIN
    limit_z = era.half_z - edge_half - EDGE_MARGIN
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
            for what, poly, need in (
                ("footprint", slot["footprint"], spine_clear),
                ("pad", slot["pad_poly"], pad_clear),
            ):
                d = segment_polygon_distance(a, b, poly)
                if d < need - 1e-6:
                    add(f"street {index + 1} {fmt(a)}->{fmt(b)}: {d:.2f} from {slot['id']} {what} (need {need:g})")
        d = segment_polygon_distance(a, b, era.sign_poly)
        if d < spine_clear - 1e-6:
            add(f"street {index + 1} {fmt(a)}->{fmt(b)}: {d:.2f} from the Sign (need {spine_clear:g})")

    if era.streets:
        entrance = era.streets[0][0]
        # The entrance is measured from the front edge, except in a tiles era: there the
        # front-most street line is the outermost lattice row whose pavement still fits on the
        # plot (at 7-stud pitch on a 120 plot that row is 11 studs in, and no closer row exists).
        front = -era.half_z
        if era.tiles is not None:
            front = -math.floor((era.half_z - edge_half) / era.tile_studs) * era.tile_studs
        if entrance[1] > front + ENTRANCE_EDGE_REACH or abs(entrance[0] - era.sign[0]) > ENTRANCE_SIGN_REACH:
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
    for message in lot_count_violations(era):
        add(message)
    for i, lot in enumerate(era.lots):
        for message in lot_violations(era, i, lot, drawn, cells):
            add(message)
    for message in parking_violations(era, network, visible):
        add(message)
    for message in walker_vehicle_violations(era):
        add(message)
    clips, clip_kinds, clip_messages = walk_clip_report(era, network, visible)
    for message in clip_messages:
        add(message)
    greenery_messages, greenery_notes = greenery_violations(era)
    for message in greenery_messages:
        add(message)
    notes += greenery_notes

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
        # Wave 2a: a plaza is a walk-in square now, so it takes the same clearances a kiosk does
        # and, unlike one, it has to touch the street it belongs to.
        for j, entry in enumerate(era.subways):
            d = polygon_polygon_distance(plaza["poly"], entry["poly"])
            if d < SUBWAY_CLEARANCE - 1e-6:
                add(f"{label}: {d:.2f} from subway entrance {j + 1} (need {SUBWAY_CLEARANCE})")
        for j, zone in enumerate(era.zones):
            if point_polygon_distance(zone["center"], plaza["poly"]) < zone["radius"] - 1e-6:
                add(f"{label}: tree zone {j + 1} overlaps it")
        # Overlap, not touch: a plaza of a pavement-less era stands flush against the cell edge.
        for cell in cells:
            if rect_overlap(plaza["poly"], era.cell_square(cell)) > 1e-6:
                where = fmt((cell[0] * era.tile_studs, cell[1] * era.tile_studs))
                add(f"{label}: covers the road cell {where}")
                break
        if era.tiles is not None:
            face = plaza["facing"]
            front = (
                plaza["position"][0] + face[0] * plaza["size"][1] / 2,
                plaza["position"][1] + face[1] * plaza["size"][1] / 2,
            )
            # With no pavement the plaza fronts the tube cell itself (wave 2b).
            edge = era.width / 2 + era.pavement if era.pavement > 0 else era.tile_studs / 2
            nearest = min(
                (point_segment_distance(front, a, b) for _, a, b in era.spine_segments()),
                key=lambda hit: hit[0],
                default=None,
            )
            if nearest is None:
                add(f"{label}: there is no street for it to front")
            elif abs(nearest[0] - edge) > PLAZA_EDGE_SLACK:
                add(
                    f"{label}: its front edge is {nearest[0]:.2f} from the nearest centreline, not flush "
                    f"with the {'pavement' if era.pavement > 0 else 'tube cell'} edge at {edge:g}"
                )
            elif (nearest[1][0] - front[0]) * face[0] + (nearest[1][1] - front[1]) * face[1] < -1e-6:
                add(f"{label}: its back is turned to the street it fronts")

    total = sum(zone["count"] for zone in era.zones)
    # Wave 2a: street trees are planned first and the zones keep the remainder, so the cap is
    # shared. budget.trees caps it too -- the client takes the lower of the two.
    street_trees = len(street_tree_spots(era))
    tree_cap = min(max(era.dressing["trees"]["maxCount"], 0), budget_value(era.city.get("budget", {}).get("trees"), math.inf))
    if not ZONE_COUNT[0] <= len(era.zones) <= ZONE_COUNT[1]:
        add(f"treeZones: {len(era.zones)}, need {ZONE_COUNT[0]}-{ZONE_COUNT[1]}")
    if street_trees + total > tree_cap:
        add(
            f"trees: {street_trees} street + {total} zone = {street_trees + total} > cap {tree_cap:g} "
            "(min of trees.maxCount and budget.trees) -- the client thins the street rows and drops zone trees"
        )
    for i, zone in enumerate(era.zones):
        c = zone["center"]
        if abs(c[0]) > era.half_x or abs(c[1]) > era.half_z:
            add(f"tree zone {i + 1}: centre {fmt(c)} outside the plot")
        # Client trees do not know about parked bays (so existing trees never shift), so a grove
        # and a bay must simply never share ground.
        for j, spot in enumerate(era.parking):
            if point_in_polygon(c, spot["poly"]) or point_polygon_distance(c, spot["poly"]) < zone["radius"] - 1e-6:
                add(f"tree zone {i + 1} {fmt(c)} r{zone['radius']:g}: reaches parking {j + 1} {fmt(spot['position'])}")

    # RoadGraph.allocate reserves for the whole network up front -- every stretch, every spur and
    # every bend node, drawn or not -- so a plan is only safe when the *reserved* total fits.
    near, far, detail = network.reserve()
    detail["streetTrees"] = street_trees
    detail["treeCap"] = tree_cap
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
    # Wave 1d: the baked-path renderer has its own budget and its own greedy pass, and it drops
    # spurs before stretches, so an overrun is invisible in game -- a building keeps its road but
    # loses the trail up to its door.
    if era.paths is not None:
        path_total, path_detail = network.path_reserve()
        detail.update(path_detail)
        path_budget = budget_value(budget.get("pathPieces"), budget_value(budget.get("roadPieces"), 0))
        detail["pathPieces"] = path_total
        detail["pathBudget"] = path_budget
        if path_total > path_budget:
            add(
                f"baked path pieces reserved {path_total} > budget.pathPieces {path_budget} "
                f"(stretches {path_detail['pathStretches']}, spurs {path_detail['pathSpurs']}) "
                "-- the client allocates spurs last, so the tail buildings would silently lose their paths"
            )
    # Wave 2a. Each of these is a place the client fails silently: an off-lattice point leaves a
    # hole between tiles, a deck over a roof or a ramp onto bare ground just looks wrong, and a
    # cell budget overrun drops the tail of the network with no error.
    if era.tiles is not None:
        for message in lattice_violations(era):
            add(message)
        for message in parallel_street_violations(era):
            add(message)
        for message in cell_violations(era, cells):
            add(message)
        tile_budget = budget_value(budget.get("tileCells"), math.inf)
        detail["tileCells"] = len(cells)
        if len(cells) > tile_budget:
            add(f"tile cells {len(cells)} > budget.tileCells {tile_budget} -- the client would drop the tail")
    if era.highway is not None:
        for message in highway_violations(era):
            add(message)
        # Highway.place counts props, not cells: ringCycle walks four arms of 2 * half cells
        # (corners counted once), the whole ramp is ONE prop however many cells it spans, and the
        # optional sign at its foot is one more.
        half_cells = int(round_half(float(era.highway["ring"]) / era.tile_studs)) if era.tile_studs else 0
        ramp_props = (1 + (1 if era.highway_sign else 0)) if era.highway_ramp is not None else 0
        highway_cells = 8 * half_cells + ramp_props
        detail["highwayCells"] = highway_cells
        highway_budget = budget_value(budget.get("highwayCells"), math.inf)
        if highway_cells > highway_budget:
            add(f"highway cells {highway_cells} > budget.highwayCells {highway_budget}")
    if era.subways or era.dressing.get("subway") is not None:
        for message in subway_violations(era, cells):
            add(message)
    blocks_cfg = (era.tiles or {}).get("blocks")
    if era.blocks and blocks_cfg is not None and not blocks_cfg.get("treeSpacing"):
        for message in bare_zone_violations(era):
            add(message)
    if era.blocks:
        block_messages, block_notes = block_violations(era, cells)
        for message in block_messages:
            add(message)
        notes += block_notes

    if era.meander is not None:
        notes.append(f"bend discs: {detail['bends']} reserved, {network.drawn_bends(visible)} drawn at full ownership")
        if detail["boundary"]:
            notes.append(
                f"{detail['boundary']} road run(s) sit exactly on a .5 piece-rounding boundary; counted high, "
                "the client may use one piece fewer each (float32)"
            )
    if era.dressing.get("pedestrians"):
        detail["walkClips"] = clips
        detail["walkClipKinds"] = clip_kinds
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


def draw(era, network, visible, violations, trees, greenery, near, far, path):
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

    for index, block in enumerate(era.blocks):
        # Under everything else: the slab is the ground the rest of the city stands on.
        poly(block["poly"], fill=(214, 212, 220, 150), outline=(168, 168, 178), width=2)
        c = px(((block["min"][0] + block["max"][0]) / 2, (block["min"][1] + block["max"][1]) / 2))
        canvas.text((c[0] - 6, c[1] - 7), f"B{index + 1}", font=small, fill=(120, 120, 132))

    for zone in era.zones:
        c = px(zone["center"])
        r = zone["radius"] * PX_PER_STUD
        canvas.ellipse((c[0] - r, c[1] - r, c[0] + r, c[1] + r), fill=(60, 150, 60, 35), outline=(40, 120, 40), width=2)
        canvas.text((c[0] - 14, c[1] - 7), f"x{zone['count']}", font=font, fill=(20, 90, 20))

    def rect(x0, z0, x1, z1, **kwargs):
        poly([(x0, z0), (x1, z0), (x1, z1), (x0, z1)], **kwargs)

    if era.tiles is not None:
        # Wave 2a: the pavement strip either side of every centreline, then the cells the tile
        # renderer rasterises the plan to. Drawn under the tier colouring so a pad or a subway
        # entrance standing on asphalt is visible in the picture, not only in the violations.
        pavement = era.tiles.get("pavement")
        pavement_rgb = tuple(int(v) for v in pavement["color"]) if pavement else (176, 180, 196)
        road_rgb = tuple(int(v) for v in era.dressing["road"]["color"])
        for _, a, b in era.spine_segments():
            length = math.dist(a, b)
            if length < MIN_LENGTH:
                continue
            ux, uz = (b[0] - a[0]) / length, (b[1] - a[1]) / length
            half = era.width / 2 + era.pavement
            nx, nz = -uz * half, ux * half
            a2 = (a[0] - ux * half, a[1] - uz * half)
            b2 = (b[0] + ux * half, b[1] + uz * half)
            poly(
                [(a2[0] + nx, a2[1] + nz), (b2[0] + nx, b2[1] + nz), (b2[0] - nx, b2[1] - nz), (a2[0] - nx, a2[1] - nz)],
                fill=pavement_rgb + (200,),
            )
        for cell in sorted(era.road_cells()):
            poly(era.cell_square(cell), fill=road_rgb + (255,), outline=(20, 20, 24), width=1)

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

    for zone in era.greenery_zones:
        c = px(zone["center"])
        r = zone["radius"] * PX_PER_STUD
        canvas.ellipse((c[0] - r, c[1] - r, c[0] + r, c[1] + r), fill=(150, 210, 60, 40), outline=(110, 170, 20), width=2)
        canvas.text((c[0] - 14, c[1] + 4), f"g{zone['count']}", font=small, fill=(70, 120, 0))

    for index, lot in enumerate(era.lots):
        if lot["kind"] == "small":
            poly(lot["poly"], fill=(250, 228, 196, 220), outline=(190, 120, 60), width=1)
        else:
            poly(lot["poly"], fill=(240, 210, 170, 220), outline=(150, 100, 60), width=2)
        c = px(lot["position"])
        face = facing(lot["rotation"])
        tip = px((lot["position"][0] + face[0] * lot["depth"] / 2, lot["position"][1] + face[1] * lot["depth"] / 2))
        canvas.line([c, tip], fill=(150, 100, 60), width=2)
        tag = "s" if lot["kind"] == "small" else "L"
        canvas.text((c[0] - 14, c[1] - 7), f"{tag}{int(lot['tier'])}#{index + 1}", font=small, fill=(90, 50, 20))

    for a, b in walk_lines(era, network, visible):
        canvas.line([px(a), px(b)], fill=(220, 60, 150, 110), width=1)

    for index, spot in enumerate(era.parking):
        poly(spot["poly"], fill=(60, 60, 70, 200), outline=(250, 250, 250), width=1)
        c = px(spot["position"])
        if spot["lot"] is not None and 1 <= spot["lot"] <= len(era.lots):
            canvas.line([c, px(era.lots[spot["lot"] - 1]["position"])], fill=(60, 60, 70, 160), width=1)
        canvas.text((c[0] - 8, c[1] - 6), f"P{int(spot['tier'])}", font=small, fill=(255, 255, 255))

    for p in greenery:
        c = px(p)
        canvas.ellipse((c[0] - 2.5, c[1] - 2.5, c[0] + 2.5, c[1] + 2.5), fill=(120, 190, 40, 230))

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

    for index, entry in enumerate(era.subways):
        poly(entry["poly"], fill=(210, 120, 50, 220), outline=(110, 55, 10), width=2)
        c = px(entry["position"])
        face = entry["facing"]
        tip = px((entry["position"][0] + face[0] * 4, entry["position"][1] + face[1] * 4))
        canvas.line([c, tip], fill=(110, 55, 10), width=2)
        canvas.text((c[0] - 4, c[1] - 7), f"M{index + 1}", font=small, fill=(60, 25, 0))

    for p in trees:
        c = px(p)
        canvas.ellipse((c[0] - 4, c[1] - 4, c[0] + 4, c[1] + 4), fill=(30, 110, 40, 220))

    highway = era.highway
    if highway is not None and era.tile_studs > 0:
        # The deck is elevated, so it is drawn last and half transparent: everything it covers is
        # still walkable underneath (soffit >= 6 studs), the pillars are what the band reserves.
        ring, half = float(highway["ring"]), era.tile_studs / 2
        outer, inner = ring + half, ring - half
        for x0, z0, x1, z1 in (
            (-outer, -outer, outer, -inner),
            (-outer, inner, outer, outer),
            (-outer, -inner, -inner, inner),
            (inner, -inner, outer, inner),
        ):
            rect(x0, z0, x1, z1, fill=(150, 150, 160, 130), outline=(70, 70, 82), width=2)
        ramp = era.highway_ramp or {}
        cell = xz(ramp["cell"]) if ramp else (0.0, 0.0)
        direction = RAMP_DIRECTIONS.get(ramp.get("direction"), (0.0, 0.0))
        for k in range(1, (era.ramp_cells if ramp else 0) + 1):
            centre = (cell[0] + direction[0] * era.tile_studs * k, cell[1] + direction[1] * era.tile_studs * k)
            poly(square(centre, era.tile_studs, era.tile_studs, 0), fill=(190, 150, 90, 170), outline=(120, 80, 20), width=2)
            if k == era.ramp_cells:
                c = px(centre)
                canvas.text((c[0] - 14, c[1] - 7), "ramp", font=small, fill=(90, 55, 0))

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
        ((240, 210, 170), "filler lot (L = house, s = small; tier#index)"),
        ((60, 60, 70), "parked bay (P = tier; line = its lot)"),
        ((150, 210, 60), "greenery zone (gN) / preview pieces"),
        ((220, 60, 150), "walk lanes (pedestrians.offset)"),
        ((200, 180, 140), "plaza"),
        ((60, 150, 60), "tree zone (xN) / preview trees"),
    ]
    if era.tiles is not None:
        entries.append((tuple(int(v) for v in era.dressing["road"]["color"]), "kit road tile (cell)"))
    if era.highway is not None:
        entries.append(((150, 150, 160), "elevated ring deck / pillar band"))
        if era.highway_ramp is not None:
            entries.append(((190, 150, 90), "highway ramp cells"))
    if era.subways:
        entries.append(((210, 120, 50), "subway entrance (M = index)"))
    if era.blocks:
        entries.append(((214, 212, 220), "paved block (B = index)"))
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
    small_lots = sum(1 for lot in era.lots if lot["kind"] == "small")
    canvas.text(
        (lx, y),
        f"spines {len(era.streets)}, lots {len(era.lots)} ({small_lots} small)",
        font=font,
        fill=(0, 0, 0),
    )
    y += 18
    canvas.text(
        (lx, y),
        f"parking {len(era.parking)}, greenery zones {len(era.greenery_zones)} "
        f"({sum(z['count'] for z in era.greenery_zones)} pieces)",
        font=font,
        fill=(0, 0, 0),
    )
    y += 18
    canvas.text((lx, y), f"plazas {len(era.plazas)}, trees {sum(z['count'] for z in era.zones)}", font=font, fill=(0, 0, 0))
    y += 18
    canvas.text((lx, y), f"road pieces reserved: near {near}, far {far}", font=font, fill=(0, 0, 0))
    y += 18
    if era.tiles is not None:
        canvas.text(
            (lx, y),
            f"tile cells {len(era.road_cells())} (pitch {era.tile_studs:g}, pavement {era.pavement:g})",
            font=font,
            fill=(0, 0, 0),
        )
        y += 18
    if era.highway is not None:
        ramp = era.highway_ramp
        where = f"ramp {fmt(xz(ramp['cell']))} {ramp['direction']}" if ramp else "loop, no ramp"
        canvas.text(
            (lx, y),
            f"highway ring {era.highway['ring']:g}, {where}",
            font=font,
            fill=(0, 0, 0),
        )
        y += 18
    if era.subways:
        canvas.text((lx, y), f"subway entrances {len(era.subways)}", font=font, fill=(0, 0, 0))
        y += 18
    if era.blocks:
        canvas.text((lx, y), f"paved blocks {len(era.blocks)}", font=font, fill=(0, 0, 0))
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
        greenery, greenery_stats = scatter_greenery(era)
        path = OUT_DIR / name / "streetplan.png"
        draw(era, network, visible, violations, trees, greenery, near, far, path)
        overrides = [s["id"] for s in era.slots if era.spurs[s["id"]]["override"]]
        budget = city.get("budget", {})
        zone_trees = sum(z["count"] for z in era.zones)
        # An era with paved blocks shares its tree cap with the street rows, so its header reports
        # the split; the others keep the zones-only line they have always printed.
        trees = (
            f"(street {detail['streetTrees']} + zone {zone_trees} / cap {detail['treeCap']:g})"
            if era.blocks
            else f"(sum {zone_trees} / max {era.dressing['trees']['maxCount']})"
        )
        print(
            f"== {name}: road width {era.width:g}, {len(era.streets)} spines, {len(era.lots)} lots, "
            f"{len(era.plazas)} plazas, {len(era.zones)} tree zones {trees}"
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
        if "pathPieces" in detail:
            print(
                f"     baked path pieces {detail['pathPieces']} / {detail['pathBudget']} "
                f"[stretches {detail['pathStretches']} + spurs {detail['pathSpurs']}] "
                "(spurs are allocated last, so an overrun costs buildings their path)"
            )
        else:
            print("     baked paths: none (no eras.<Era>.road.paths; the parts renderer draws)")
        if "tileCells" in detail:
            print(
                f"   kit tiles: {detail['tileCells']} cells / {budget.get('tileCells')} "
                f"(pitch {era.tile_studs:g}, pavement {era.pavement:g} either side)"
            )
        if "highwayCells" in detail and era.highway_ramp is None:
            print(f"   highway: ring {era.highway['ring']:g}, {detail['highwayCells']} props / {budget.get('highwayCells')}, loop (no ramp)")
        elif "highwayCells" in detail:
            ramp = era.highway_ramp
            foot_step = RAMP_DIRECTIONS.get(ramp["direction"], (0.0, 0.0))
            cell = xz(ramp["cell"])
            foot = (cell[0] + foot_step[0] * era.tile_studs * era.ramp_cells, cell[1] + foot_step[1] * era.tile_studs * era.ramp_cells)
            print(
                f"   highway: ring {era.highway['ring']:g}, {detail['highwayCells']} props / "
                f"{budget.get('highwayCells')}, ramp {fmt(cell)} {ramp['direction']} "
                f"x{era.ramp_cells} cells, foot {fmt(foot)}"
            )
        if era.subways:
            spots = ", ".join(f"{fmt(entry['position'])}@{entry['rotation']:g}" for entry in era.subways)
            print(f"   subway entrances ({len(era.subways)}): {spots}")
        if era.blocks:
            paved = sum(
                (block["max"][0] - block["min"][0]) * (block["max"][1] - block["min"][1]) for block in era.blocks
            )
            print(f"   paved blocks: {len(era.blocks)} rects, {paved:.0f} studs^2, {sum(len(b['slots']) for b in era.blocks)} slots on them")
        for zone, usable, _ in stats:
            print(
                f"   tree zone {fmt(zone['center'])} r{zone['radius']:g} x{zone['count']}: "
                f"{usable * 100:.0f}% of the circle is plantable"
            )
        if era.lots:
            by_tier = {t: [lot["kind"][0] for lot in era.lots if lot["tier"] == t] for t in range(1, 6)}
            print(
                "   lots by tier (h = house, s = small): "
                + ", ".join(f"T{t} {''.join(sorted(kinds)) or '-'}" for t, kinds in by_tier.items())
            )
        if era.parking:
            counts = [sum(1 for spot in era.parking if effective_spot_tier(era, spot) <= t) for t in range(1, 6)]
            driveways = sum(1 for spot in era.parking if spot["lot"] is not None)
            print(
                f"   parking: {len(era.parking)} spots ({driveways} driveways), bay {era.bay[0]:g}x{era.bay[1]:g}, "
                f"available by tier 1-5 {counts}, perTier {(era.dressing.get('parked') or {}).get('perTier')}"
            )
            cars, fits, rows, longest = bay_packing(era)
            if rows:
                print(
                    f"   bay packing: perBay {cars}, {fits}/{rows} prop rows fit "
                    f"(longest {longest:.2f}); the rest keep one car"
                )
        for zone, usable, kept in greenery_stats:
            print(
                f"   greenery zone {fmt(zone['center'])} r{zone['radius']:g} x{zone['count']}: "
                f"{usable * 100:.0f}% plantable, preview fits {kept}"
            )
        if "walkClips" in detail:
            kinds = ", ".join(f"{kind} {count}" for kind, count in sorted(detail["walkClipKinds"].items()))
            print(f"   walk lanes: {detail['walkClips']} clipped runs at full ownership ({kinds or 'none'})")
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
