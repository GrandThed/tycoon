#!/usr/bin/env python
"""Top-down street-plan check for the M9 city dressing (docs/INTERFACES.md "M9 contracts").

Parses src/shared/Layouts/<Era>.luau, mirrors the client's auto-spur rule from "Road routing",
checks every clearance rule from the "Layouts" section and draws one PNG per era to
assets/testfit/out/<Era>/streetplan.png so the plan can be approved without Studio.

Numbers come from their owners, never from this file: road width and tree rules from
Config/CityDressing.json, slot footprints and prop footprints from the testfit blueprints
(contract defaults 9x9 / monument 14x14 when a blueprint has none), pad and plot sizes from the
layout. The only tool-local numbers are the contract's own rule values (lot and clearance
distances, counts), named below.

Usage:
  py tools/streetplan.py                # Village and Boomtown (wave 1), frozen contract rules
  py tools/streetplan.py Metropolis     # any era(s) by name
Exit code 1 when any violation is found.
"""

from __future__ import annotations

import json
import math
import random
import re
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

REPO_ROOT = Path(__file__).resolve().parent.parent
LAYOUTS_DIR = REPO_ROOT / "src" / "shared" / "Layouts"
ERAS_DIR = REPO_ROOT / "src" / "shared" / "Config" / "Eras"
CITY_CONFIG_PATH = REPO_ROOT / "src" / "shared" / "Config" / "CityDressing.json"
BLUEPRINTS_DIR = REPO_ROOT / "tools" / "testfit" / "blueprints"
OUT_DIR = REPO_ROOT / "assets" / "testfit" / "out"

DEFAULT_ERAS = ("Village", "Boomtown")

# Contract rule values (INTERFACES.md "Layouts"), not game tunables.
SLOT_FOOTPRINT_DEFAULT = 9
MONUMENT_FOOTPRINT_DEFAULT = 14
SPINE_EXTRA_CLEARANCE = 1  # spine clear of slots/pads/Sign by width/2 + this
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
    "Boomtown": ("paveMainStreet", "streetlampRow", "trafficLights"),
}
# A lot "faces the road" when a spine centreline lies within this many studs of its front edge.
LOT_FRONT_REACH = 10
# First spine must come this close to the plot's front edge, and to the monument pad's outer edge so
# the monument's own straight spur (at most a road tile long) is its approach.
FRONT_EDGE_REACH = 8
MONUMENT_APPROACH_REACH = 14
EDGE_MARGIN = 1  # every road Part (centreline + width/2) stays this far inside the plot
PX_PER_STUD = 8
MARGIN_PX = 60
LEGEND_PX = 330
TIER_COLOURS = {
    1: (214, 69, 65),
    2: (235, 140, 52),
    3: (214, 190, 40),
    4: (70, 160, 80),
    5: (60, 110, 200),
}


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


class Era:
    def __init__(self, name, city):
        self.name = name
        self.furniture = set(STREET_FURNITURE.get(name, ()))
        self.layout = parse_layout(LAYOUTS_DIR / f"{name}.luau")
        self.config = load_era_config(name)
        self.dressing = city["eras"][name]
        self.city = city
        self.width = self.dressing["road"]["width"]
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
            default = (
                MONUMENT_FOOTPRINT_DEFAULT if slot["type"] == "monument" else SLOT_FOOTPRINT_DEFAULT
            )
            fx, fz = blueprint_footprint(name, slot["modelName"], default)
            position = xz(entry["position"])
            rotation = entry["rotationY"]
            face = facing(rotation)
            if "padPosition" in entry:
                pad = xz(entry["padPosition"])
            else:
                pad = (
                    position[0] + face[0] * self.pad_offset,
                    position[1] + face[1] * self.pad_offset,
                )
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
        self.street_y = [
            [p[1] for p in street["points"]] for street in self.layout.get("streets", [])
        ]
        house_size = prop_footprint(
            name, self.dressing["houses"]["props"], (SLOT_FOOTPRINT_DEFAULT, SLOT_FOOTPRINT_DEFAULT)
        )
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
        """INTERFACES "Road routing": pad outer edge, leg 1 along the facing until level with the
        projection onto the nearest spine segment, leg 2 perpendicular to join."""
        face = slot["facing"]
        start = (
            slot["pad"][0] + face[0] * self.pad_size[1] / 2,
            slot["pad"][1] + face[1] * self.pad_size[1] / 2,
        )
        if slot["spur_override"] is not None:
            return {"points": slot["spur_override"], "override": True, "start": start, "backwards": False}
        best = None
        for _, a, b in self.spine_segments():
            distance, projection = point_segment_distance(start, a, b)
            if best is None or distance < best[0]:
                best = (distance, projection)
        if best is None:
            return {"points": [start], "override": False, "start": start, "backwards": False}
        projection = best[1]
        along = (projection[0] - start[0]) * face[0] + (projection[1] - start[1]) * face[1]
        corner = (start[0] + face[0] * along, start[1] + face[1] * along)
        return {
            "points": [start, corner, projection],
            "override": False,
            "start": start,
            "backwards": along < -1e-6,
        }


# --------------------------------------------------------------------------
# Checks
# --------------------------------------------------------------------------


def check(era):
    violations = []
    notes = []
    width = era.width
    spine_clear = width / 2 + SPINE_EXTRA_CLEARANCE

    def add(message):
        violations.append(message)

    if not STREET_COUNT[0] <= len(era.streets) <= STREET_COUNT[1]:
        add(f"streets: {len(era.streets)} polylines, need {STREET_COUNT[0]}-{STREET_COUNT[1]}")
    for index, ys in enumerate(era.street_y):
        if any(abs(y) > 1e-9 for y in ys):
            add(f"street {index + 1}: a point is not at Y 0")
    limit_x = era.half_x - width / 2 - EDGE_MARGIN
    limit_z = era.half_z - width / 2 - EDGE_MARGIN
    for index, street in enumerate(era.streets):
        if len(street) < 2:
            add(f"street {index + 1}: fewer than 2 points")
        for p in street:
            if abs(p[0]) > limit_x + 1e-9 or abs(p[1]) > limit_z + 1e-9:
                add(f"street {index + 1}: point {p} leaves the plot (limit +/-{limit_x:g})")
        for a, b in polyline_segments(street):
            if abs(a[0] - b[0]) > 1e-9 and abs(a[1] - b[1]) > 1e-9:
                notes.append(f"street {index + 1}: diagonal segment {a} -> {b}")

    for index, a, b in era.spine_segments():
        for slot in era.slots:
            if slot["id"] in era.furniture:
                continue
            d = segment_polygon_distance(a, b, slot["footprint"])
            if d < spine_clear - 1e-6:
                add(f"street {index + 1} {a}->{b}: {d:.2f} from {slot['id']} footprint (need {spine_clear:g})")
            d = segment_polygon_distance(a, b, slot["pad_poly"])
            if d < spine_clear - 1e-6:
                add(f"street {index + 1} {a}->{b}: {d:.2f} from {slot['id']} pad (need {spine_clear:g})")
        d = segment_polygon_distance(a, b, era.sign_poly)
        if d < spine_clear - 1e-6:
            add(f"street {index + 1} {a}->{b}: {d:.2f} from the Sign (need {spine_clear:g})")

    monument = next((s for s in era.slots if s["type"] == "monument"), None)
    if era.streets:
        first = era.streets[0]
        front = min(p[1] for p in first)
        if front > -era.half_z + FRONT_EDGE_REACH:
            add(f"street 1 never reaches the front edge (min z {front:g})")
        if monument is not None:
            outer = era.spurs[monument["id"]]["start"]
            reach = min(point_segment_distance(outer, a, b)[0] for a, b in polyline_segments(first))
            if reach > MONUMENT_APPROACH_REACH:
                add(f"street 1 is {reach:.1f} from the {monument['id']} pad edge (need <= {MONUMENT_APPROACH_REACH})")

    # Spurs: never through another slot, pad, lot, plaza or the Sign; never backwards.
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
    for slot in era.slots:
        spur = era.spurs[slot["id"]]
        points = spur["points"]
        label = f"spur {slot['id']}{' (override)' if spur['override'] else ''}"
        if spur["backwards"]:
            add(f"{label}: leg 1 runs backwards into its own building")
        if spur["override"] and len(points) == 1:
            notes.append(f"{label}: single point, no spur drawn (P2)")
        if spur["override"]:
            edge = min(point_segment_distance(points[0], c, d)[0] for c, d in polygon_edges(slot["pad_poly"]))
            if edge > 0.5:
                add(f"{label}: first point {fmt(points[0])} is not on the pad edge")
            end = points[-1]
            if len(points) > 1 and (
                not all_segments or min(point_segment_distance(end, a, b)[0] for a, b in all_segments) > 0.5
            ):
                add(f"{label}: last point {end} is not on a spine")
        for a, b in polyline_segments(points):
            if math.dist(a, b) < 1e-6:
                continue
            for name, poly, owner in obstacles:
                if owner == slot["id"]:
                    # Own pad is where the spur starts; only the building itself is off-limits.
                    if name.endswith("pad"):
                        continue
                d = segment_polygon_distance(a, b, poly)
                if d < width / 2 - 1e-6:
                    add(f"{label} {fmt(a)}->{fmt(b)}: cuts {name} ({d:.2f} < {width / 2:g})")
        for p in points:
            if abs(p[0]) > era.half_x or abs(p[1]) > era.half_z:
                add(f"{label}: point {fmt(p)} leaves the plot")

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
            if segment_polygon_distance(a, b, lot["poly"]) < width / 2 + 0.5:
                add(f"{label}: house sits on street {fmt(a)}->{fmt(b)}")
        for j, other in enumerate(era.lots):
            if j > i and polygon_polygon_distance(lot["poly"], other["poly"]) < 1:
                add(f"{label}: house overlaps lot {j + 1}")
        for j, plaza in enumerate(era.plazas):
            if polygon_polygon_distance(lot["poly"], plaza["poly"]) < 1:
                add(f"{label}: house overlaps plaza {j + 1}")
        for poly_point in lot["poly"]:
            if abs(poly_point[0]) > era.half_x - 1 or abs(poly_point[1]) > era.half_z - 1:
                add(f"{label}: house leaves the plot")
                break
        face = facing(lot["rotation"])
        front = (
            lot["position"][0] + face[0] * lot["depth"] / 2,
            lot["position"][1] + face[1] * lot["depth"] / 2,
        )
        reach = min(
            (point_segment_distance(front, a, b)[0] for _, a, b in era.spine_segments()),
            default=math.inf,
        )
        ahead = min(
            (
                point_segment_distance(front, a, b)
                for _, a, b in era.spine_segments()
            ),
            default=(math.inf, front),
            key=lambda item: item[0],
        )[1]
        facing_dot = (ahead[0] - front[0]) * face[0] + (ahead[1] - front[1]) * face[1]
        if reach > LOT_FRONT_REACH or facing_dot < 0:
            add(f"{label}: does not face a street (nearest {reach:.1f} studs from its front)")

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
            if segment_polygon_distance(a, b, plaza["poly"]) < width / 2 - 1e-6:
                add(f"{label}: sits on street {fmt(a)}->{fmt(b)}")

    # Tier-5 road pieces against budget.roadPieces: one Part per non-empty spine or spur segment,
    # plus a junction prop per spur end and a bend prop per interior spine point when the era has
    # those props (INTERFACES "Road routing").
    road_cfg = era.dressing["road"]
    parts = sum(len(polyline_segments(street)) for street in era.streets)
    junctions = bends = 0
    for spur in era.spurs.values():
        segments = [seg for seg in polyline_segments(spur["points"]) if math.dist(*seg) > 1e-6]
        parts += len(segments)
        if segments and road_cfg.get("junctionProp"):
            junctions += 1
    if road_cfg.get("bendProp"):
        bends = sum(max(0, len(street) - 2) for street in era.streets)
    era.road_pieces = parts + junctions + bends
    budget = era.city.get("budget", {}).get("roadPieces")
    if budget is not None and era.road_pieces > budget:
        add(f"road pieces at tier 5: {era.road_pieces} > budget.roadPieces {budget}")

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
    return violations, notes


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
    roads = [(a, b) for _, a, b in era.spine_segments()]
    for spur in era.spurs.values():
        roads += [(a, b) for a, b in polyline_segments(spur["points"])]
    road_clear = era.width / 2 + era.city["trees"]["roadClearance"]
    # Anchor distance alone lets trees into the corners of big footprints (monument, plaza), so
    # the game also rejects points within trees.footprintMargin of any slot, pad, lot or plaza.
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


def draw(era, violations, trees, path):
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
    canvas.text(
        (MARGIN_PX, 18),
        f"{era.name} street plan -- FRONT (hub, -Z) is the top edge",
        font=big,
        fill=(20, 20, 20),
    )

    for zone in era.zones:
        c = px(zone["center"])
        r = zone["radius"] * PX_PER_STUD
        canvas.ellipse((c[0] - r, c[1] - r, c[0] + r, c[1] + r), fill=(60, 150, 60, 35), outline=(40, 120, 40), width=2)
        canvas.text((c[0] - 14, c[1] - 7), f"x{zone['count']}", font=font, fill=(20, 90, 20))

    def road(points, colour, outline=None):
        half = era.width / 2
        for a, b in polyline_segments(points):
            length = math.dist(a, b)
            if length < 1e-6:
                continue
            ux, uz = (b[0] - a[0]) / length, (b[1] - a[1]) / length
            nx, nz = -uz * half, ux * half
            a2 = (a[0] - ux * half, a[1] - uz * half)
            b2 = (b[0] + ux * half, b[1] + uz * half)
            poly(
                [(a2[0] + nx, a2[1] + nz), (b2[0] + nx, b2[1] + nz), (b2[0] - nx, b2[1] - nz), (a2[0] - nx, a2[1] - nz)],
                fill=colour,
                outline=outline,
            )

    for slot in era.slots:
        spur = era.spurs[slot["id"]]
        road(spur["points"], (150, 130, 110, 200) if not spur["override"] else (170, 90, 170, 200))
    step = era.city["road"]["spineTierStep"]
    for index, street in enumerate(era.streets):
        tier = (index + 1) * step
        road(street, TIER_COLOURS.get(tier, (90, 90, 90)) + (215,))
        for a, b in polyline_segments(street):
            canvas.line([px(a), px(b)], fill=(255, 255, 255, 180), width=1)
        canvas.text(px(street[0]), f"S{index + 1}", font=big, fill=(0, 0, 0))

    for plaza in era.plazas:
        poly(plaza["poly"], fill=(200, 180, 140, 200), outline=(120, 90, 50), width=2)
        c = px(plaza["position"])
        canvas.text((c[0] - 30, c[1] - 7), f"{plaza['prop']} T{int(plaza['tier'])}", font=font, fill=(60, 40, 10))

    for i, lot in enumerate(era.lots):
        poly(lot["poly"], fill=(240, 210, 170, 220), outline=(150, 100, 60), width=2)
        c = px(lot["position"])
        face = facing(lot["rotation"])
        tip = px((lot["position"][0] + face[0] * lot["depth"] / 2, lot["position"][1] + face[1] * lot["depth"] / 2))
        canvas.line([c, tip], fill=(150, 100, 60), width=2)
        canvas.text((c[0] - 12, c[1] - 7), f"L{int(lot['tier'])}", font=font, fill=(90, 50, 20))

    for slot in era.slots:
        monument = slot["type"] == "monument"
        fill = (120, 120, 200, 220) if slot["type"] == "building" else (170, 170, 170, 220)
        if monument:
            fill = (230, 180, 60, 230)
        poly(slot["footprint"], fill=fill, outline=(30, 30, 60), width=2)
        poly(slot["pad_poly"], fill=(90, 200, 220, 170), outline=(20, 110, 130))
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
        canvas.text((lx + 34, y - 2), f"spine S{tier} (tier {tier * step})", font=font, fill=(0, 0, 0))
        y += 20
    entries = [
        ((150, 130, 110), "auto spur"),
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
    y += 12
    canvas.text((lx, y), f"road width {era.width:g}", font=font, fill=(0, 0, 0))
    y += 18
    canvas.text((lx, y), f"spines {len(era.streets)}, lots {len(era.lots)}", font=font, fill=(0, 0, 0))
    y += 18
    canvas.text((lx, y), f"plazas {len(era.plazas)}, trees {sum(z['count'] for z in era.zones)}", font=font, fill=(0, 0, 0))
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
        violations, notes = check(era)
        trees, stats = scatter_trees(era)
        path = OUT_DIR / name / "streetplan.png"
        draw(era, violations, trees, path)
        overrides = [s["id"] for s in era.slots if era.spurs[s["id"]]["override"]]
        print(f"== {name}: road width {era.width:g}, {len(era.streets)} spines, {len(era.lots)} lots, "
              f"{len(era.plazas)} plazas, {len(era.zones)} tree zones "
              f"(sum {sum(z['count'] for z in era.zones)} / max {era.dressing['trees']['maxCount']})")
        print(f"   spur overrides: {', '.join(overrides) if overrides else 'none'}")
        print(f"   road pieces at tier 5 (parts + junction/bend props): {era.road_pieces}")
        for zone, usable, _ in stats:
            print(f"   tree zone {fmt(zone['center'])} r{zone['radius']:g} x{zone['count']}: "
                  f"{usable * 100:.0f}% of the circle is plantable")
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
