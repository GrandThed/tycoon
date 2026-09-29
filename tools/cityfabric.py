#!/usr/bin/env python
"""Offline mirror of the M12 city fabric (docs/INTERFACES.md "M12 contracts"): what the client's
src/shared/CityFabric.luau decides and src/client/City/Fabric.luau draws, for every tool that has to
show exactly what the game shows -- tools/testfit/plotrender.py above all, which Ben compares Studio
against.

    py tools/cityfabric.py selftest            # the contract's test vector, asserted
    py tools/cityfabric.py timeline Village    # parcels by level and wild counts at tiers 1-5

What is mirrored, and from where (nothing is re-derived; a divergence is a bug in one of them):
  * develop, rect_distance, segment_distance, is_cleared: src/shared/CityFabric.luau, line for line
    -- pulls summed over the landmarks in slot-id order one `+=` at a time (Python's sum() is
    compensated and would round differently), sqrt(x*x + z*z) never hypot, and the plain O(V^2)
    Dijkstra that settles the lowest node id first among equals;
  * goal_for (the district prop by index, the height cap, the stage lowering, the site at level 1),
    the budgets (fixed prefixes of the data lists), the clearing mask and the wild draw:
    src/client/City/Fabric.luau;
  * the street network the fabric develops along: RoadGraph.FabricNetwork over tools/streetplan.py's
    Network -- visible stretches keyed by baked piece id, every routable slot's join node, and the
    mask's street segments as straight chords plus spur legs -- with the straight budget's spur and
    group gates that decide RoadGraph's `state.visible`;
  * the slot, pad and plaza rects: Scatter.Solids (harvested extents from Assets.json, the layout's
    placeholder without them) turned into rects by Fabric's footprintRect;
  * what the controller hands Fabric.Sync: the owned slots, each one's visible Stage<n> (PlotService's
    stage rule over the template's harvested stages), GrowthTier and the pads PlotService shows.

Heights. A landmark's height at a stage comes from its Assets.json stage parts, measured exactly as
the client measures it (no entry: 0). A fabric prop uses Assets.json when it has an entry there;
until the Village props are harvested it falls back to the blueprint's measured stage y-range (kit
GLB bounds x blueprint scale), so a render shows what the client will show once the props exist --
the client itself draws nothing for a prop without a template. The fallback goes away with the
harvest.

Node ids here are RoadGraph's (1-based); streetplan numbers them from 0.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "tools"))
sys.path.insert(0, str(REPO_ROOT / "tools" / "testfit"))
sys.path.insert(0, str(REPO_ROOT / "tools" / "assets"))

import streetplan  # noqa: E402

CONFIG_DIR = REPO_ROOT / "src" / "shared" / "Config"
CITY_CONFIG_PATH = CONFIG_DIR / "CityDressing.json"
ASSETS_PATH = CONFIG_DIR / "Assets.json"  # read only, never written
FABRIC_DIR = CONFIG_DIR / "Fabric"
GAME_CONFIG_PATH = CONFIG_DIR / "Game.json"
BLUEPRINTS_DIR = REPO_ROOT / "tools" / "testfit" / "blueprints"
KITS_ROOT = REPO_ROOT / "assets" / "kenney3d"
KIT_MODEL_DIRS = ("GLB format", "GLTF format")  # testfit.find_glb's search order

# Contract vocabulary (INTERFACES "M12 contracts -- Data").
SMALL = "small"
MEDIUM = "medium"
CLUMP = "clump"
SINGLE = "single"
SITE = "site"
BUILDING = "building"
QUARTERS = 4
ALL_QUARTERS = 15
QUARTER_TURN_DEGREES = 90
# CityFabric.luau: IsCleared skips a rect whose centre is out of reach, with this much slack so the
# skip stays strictly inside the exact test. Copied so the mirror runs the same branches.
SKIP_SLACK = 0.01
# Fabric.luau's site look: stakes at the footprint corners and a string between them.
STAKE_WIDTH = 0.3
STAKE_HEIGHT = 1.4
STRING_THICKNESS = 0.08
STRING_HEIGHT = 1.1
CORNER_SIGNS = ((-1, -1), (1, -1), (1, 1), (-1, 1))
# The numeric pull fields Fabric.validPull demands finite; with `thresholds`, the contract's six.
PULL_NUMBERS = ("radius", "tierTerm", "reach", "levelsOverTier", "smallMaxLevel")
# A score, a network distance or a pull this close to its threshold could fall the other way in game,
# where Vector3 components (and so stretch lengths) are float32: reported, never "fixed".
FRAGILE = 1e-4


# --------------------------------------------------------------------------------------------
# CityFabric.luau, one to one
# --------------------------------------------------------------------------------------------


def _build_graph(stretches):
    """buildGraph: every visible stretch is an undirected edge; nodes sorted ascending."""
    nodes, edges = [], {}

    def connect(a, b, length):
        adjacent = edges.get(a)
        if adjacent is None:
            adjacent = []
            edges[a] = adjacent
            nodes.append(a)
        adjacent.append((b, length))

    # The Luau walks a dictionary here; the distances do not depend on the order, which is only
    # fixed so this tool is reproducible.
    for key in sorted(stretches):
        stretch = stretches[key]
        connect(stretch["from"], stretch["to"], stretch["length"])
        connect(stretch["to"], stretch["from"], stretch["length"])
    nodes.sort()
    return nodes, edges


def _shortest_distances(graph, sources):
    """shortestDistances: each round settles the nearest unsettled node, the lowest id among equals."""
    nodes, edges = graph
    dist = dict(sources)
    settled = set()
    while True:
        best, best_distance = None, math.inf
        for node in nodes:
            d = dist.get(node)
            if d is not None and d < best_distance and node not in settled:
                best, best_distance = node, d
        if best is None:
            break
        settled.add(best)
        for other, length in edges[best]:
            candidate = best_distance + length
            current = dist.get(other)
            if current is None or candidate < current:
                dist[other] = candidate
    return dist


def _parcel_distance(dist, stretch, along):
    at_from, at_to = dist.get(stretch["from"]), dist.get(stretch["to"])
    via_from = at_from + along if at_from is not None else math.inf
    via_to = at_to + (stretch["length"] - along) if at_to is not None else math.inf
    return min(via_from, via_to)


def _keep_nearest(dist, node, distance):
    current = dist.get(node)
    if current is None or distance < current:
        dist[node] = distance


def _integral(value):
    """Luau has one number type; Python keeps an int where the Luau value is integral."""
    return int(value) if isinstance(value, float) and value.is_integer() else value


def develop(input, pull, trace=None):
    """CityFabric.Develop: each parcel's {level, district, governor}, parcel i at index i - 1.

    `input` is {tier, stretches: {pieceId: {from, to, length}}, landmarks: [{slotId, node,
    district}], parcels: [...]}. `trace`, when a list, receives one record per parcel with the
    score and distances the result was decided on, for the fragility report."""
    stretches = input["stretches"]
    parcels = input["parcels"]
    tier = input["tier"]
    graph = _build_graph(stretches)

    # Float addition is not associative, so pulls are summed in slot id order (then node).
    landmarks = sorted(input["landmarks"], key=lambda landmark: (landmark["slotId"], landmark["node"]))

    searched, landmark_distances = {}, []
    for landmark in landmarks:
        dist = searched.get(landmark["node"])
        if dist is None:
            dist = _shortest_distances(graph, {landmark["node"]: 0})
            searched[landmark["node"]] = dist
        landmark_distances.append(dist)

    states = []
    for parcel in parcels:
        stretch = stretches.get(parcel["stretch"])
        influence = 0
        governor, governor_pull = None, 0
        pulls = []
        if stretch is not None:
            for landmark_index, landmark in enumerate(landmarks):
                distance = _parcel_distance(landmark_distances[landmark_index], stretch, parcel["along"])
                landmark_pull = max(0, 1 - distance / pull["radius"])
                pulls.append((landmark["slotId"], distance))
                if landmark_pull > 0:
                    influence += landmark_pull
                    if (
                        governor is None
                        or landmark_pull > governor_pull
                        or (landmark_pull == governor_pull and landmark["slotId"] > governor["slotId"])
                    ):
                        governor = landmark
                        governor_pull = landmark_pull
        score = influence + pull["tierTerm"] * tier if governor is not None else 0
        level = 0
        for threshold in pull["thresholds"]:
            if score >= threshold:
                level += 1
        level = min(level, tier + pull["levelsOverTier"])
        if parcel["size"] == SMALL:
            level = min(level, pull["smallMaxLevel"])
        if stretch is None:
            level = 0
        states.append(
            {
                "level": level,
                "district": governor["district"] if governor is not None else None,
                "governor": governor["slotId"] if governor is not None else None,
            }
        )
        if trace is not None:
            trace.append({"score": score, "pulls": pulls, "reach": None})

    # Step 7: growth spreads outward, pass by pass, from the landmarks and the accepted parcels.
    accepted, accepted_order = set(), []
    grew = True
    while grew:
        grew = False
        sources = {}
        for landmark in landmarks:
            sources[landmark["node"]] = 0
        for index in accepted_order:
            parcel = parcels[index - 1]
            stretch = stretches.get(parcel["stretch"])
            if stretch is not None:
                _keep_nearest(sources, stretch["from"], parcel["along"])
                _keep_nearest(sources, stretch["to"], stretch["length"] - parcel["along"])
        dist = _shortest_distances(graph, sources)
        for index, parcel in enumerate(parcels, start=1):
            if parcel["row"] != 1 or index in accepted or states[index - 1]["level"] < 1:
                continue
            stretch = stretches.get(parcel["stretch"])
            if stretch is None:
                continue
            near = _parcel_distance(dist, stretch, parcel["along"])
            if trace is not None:
                trace[index - 1]["reach"] = near
            if near <= pull["reach"]:
                accepted.add(index)
                accepted_order.append(index)
                grew = True
    for index, parcel in enumerate(parcels, start=1):
        if parcel["row"] == 1 and index not in accepted:
            states[index - 1]["level"] = 0

    # Step 8: a second-row parcel stays a level behind its front parcel and takes its kind. The Luau
    # indexes `states[parcel.front]`, so anything but an index 1..n reads as a missing front.
    for parcel, state in zip(parcels, states):
        if parcel["row"] == 2:
            front_index = parcel["front"]
            front = None
            if isinstance(front_index, (int, float)) and not isinstance(front_index, bool):
                if float(front_index).is_integer() and 1 <= front_index <= len(states):
                    front = states[int(front_index) - 1]
            front_level = front["level"] if front is not None else 0
            state["level"] = max(0, min(state["level"], front_level - 1))
            state["district"] = front["district"] if front is not None else None
            state["governor"] = front["governor"] if front is not None else None
    for state in states:
        state["level"] = _integral(state["level"])
    return states


def rect_distance(px, pz, rect):
    """CityFabric.RectDistance: 0 inside; the point is taken into the rect's frame with the inverse
    of CFrame.Angles(0, a, 0)."""
    angle = math.radians(rect["rotationY"])
    cos_a, sin_a = math.cos(angle), math.sin(angle)
    dx, dz = px - rect["x"], pz - rect["z"]
    lx = dx * cos_a - dz * sin_a
    lz = dx * sin_a + dz * cos_a
    ox = max(abs(lx) - rect["hx"], 0)
    oz = max(abs(lz) - rect["hz"], 0)
    return math.sqrt(ox * ox + oz * oz)


def segment_distance(px, pz, seg):
    """CityFabric.SegmentDistance: a zero-length segment is its end point."""
    dx, dz = seg["bx"] - seg["ax"], seg["bz"] - seg["az"]
    length_sq = dx * dx + dz * dz
    t = 0
    if length_sq > 0:
        t = max(0, min(1, ((px - seg["ax"]) * dx + (pz - seg["az"]) * dz) / length_sq))
    ex, ez = px - (seg["ax"] + t * dx), pz - (seg["az"] + t * dz)
    return math.sqrt(ex * ex + ez * ez)


def is_cleared(px, pz, radius, mask):
    """CityFabric.IsCleared, the reach skip included."""
    for rect in mask["rects"]:
        bound = rect["margin"] + radius + abs(rect["hx"]) + abs(rect["hz"]) + SKIP_SLACK
        dx, dz = px - rect["x"], pz - rect["z"]
        out_of_reach = bound > 0 and dx * dx + dz * dz >= bound * bound
        if not out_of_reach and rect_distance(px, pz, rect) - radius < rect["margin"]:
            return True
    for segment in mask["segments"]:
        if segment_distance(px, pz, segment) - radius < mask["streetClear"]:
            return True
    return False


# --------------------------------------------------------------------------------------------
# Fabric.luau's renderer rules
# --------------------------------------------------------------------------------------------


def is_number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def finite(value):
    """Fabric.finite: a number that is neither NaN nor infinite."""
    return is_number(value) and math.isfinite(value)


def number_or(value, fallback):
    """Fabric.numberOr: a finite number, else the fallback."""
    return value if finite(value) else fallback


def is_triple(value):
    """Fabric.isTriple: three numbers."""
    return isinstance(value, list) and len(value) >= 3 and all(is_number(v) for v in value[:3])


def is_xz_triple(value):
    """Scatter.isNumberTriple, which checks only the X and Z entries."""
    return isinstance(value, list) and len(value) >= 3 and is_number(value[0]) and is_number(value[2])


def by_size(size, small, medium):
    return small if size == SMALL else medium


def luau_index(items, index):
    """items[index] as Luau reads a 1-based list: anything but an integral index 1..n is nil."""
    if isinstance(items, list) and is_number(index) and float(index).is_integer() and 1 <= index <= len(items):
        return items[int(index) - 1]
    return None


def valid_pull(pull):
    """Fabric.validPull (review amendment): a copy when the five numeric fields are finite and
    `thresholds` is an array of finite numbers; otherwise None, which keeps every parcel at level 0."""
    if not isinstance(pull, dict):
        return None
    for key in PULL_NUMBERS:
        if not finite(pull.get(key)):
            return None
    thresholds = pull.get("thresholds")
    # A JSON object arrives in Luau with string keys, which the client rejects like any hole.
    if not isinstance(thresholds, list) or not all(finite(t) for t in thresholds):
        return None
    return {key: pull[key] for key in PULL_NUMBERS} | {"thresholds": list(thresholds)}


def prop_list(value):
    """Fabric.propList: names kept by position (a clump's variant indexes it); anything that is not a
    name reads as a missing prop, and a missing list (or a JSON object) as an empty one."""
    if not isinstance(value, list):
        return []
    return [name if isinstance(name, str) else None for name in value]


def valid_wild_config(wild):
    """Fabric.validWildConfig."""
    if not isinstance(wild, dict):
        return None
    return {
        "clumps": prop_list(wild.get("clumps")),
        "quarters": prop_list(wild.get("quarters")),
        "quarterRadius": number_or(wild.get("quarterRadius"), 0),
        "singleRadius": number_or(wild.get("singleRadius"), 0),
    }


def valid_parcel(parcel):
    """Fabric.validParcel: every field CityFabric reads and Fabric.new places by."""
    return (
        isinstance(parcel, dict)
        and all(finite(parcel.get(key)) for key in ("x", "z", "rotationY", "along", "row", "front"))
        and isinstance(parcel.get("stretch"), str)
        and parcel.get("size") in (SMALL, MEDIUM)
    )


def blank_parcel():
    """Fabric.blankParcel: a malformed parcel's stand-in, on no street, so it never develops and every
    later index (a row-2 parcel names its front by index) stays put."""
    return {"x": 0, "z": 0, "rotationY": 0, "size": SMALL, "stretch": "", "along": 0, "row": 1, "front": 0}


def valid_wild_entry(entry):
    """Fabric.validWildEntry: a malformed entry is skipped where it stands."""
    if not isinstance(entry, dict) or not all(finite(entry.get(key)) for key in ("x", "z", "rotationY")):
        return False
    return entry.get("kind") == CLUMP or (entry.get("kind") == SINGLE and isinstance(entry.get("prop"), str))


def scale_of(value):
    """PropFactory.ScaleOf: missing, NaN, non-positive or infinite is 1."""
    if not is_number(value) or value != value or value <= 0 or value == math.inf:
        return 1.0
    return value


def stage_heights(model):
    """Fabric.stageHeights: each stage's max(offset.y + size.y / 2) - min(offset.y - size.y / 2)
    over its parts, 0 for a stage with nothing measured; empty without an entry."""
    heights = []
    if not isinstance(model, dict) or not isinstance(model.get("stages"), list):
        return heights
    for stage in model["stages"]:
        top, bottom = -math.inf, math.inf
        parts = stage.get("parts") if isinstance(stage, dict) else None
        if isinstance(parts, list):
            for part in parts:
                if isinstance(part, dict) and is_triple(part.get("size")) and is_triple(part.get("offset")):
                    top = max(top, part["offset"][1] + part["size"][1] / 2)
                    bottom = min(bottom, part["offset"][1] - part["size"][1] / 2)
        heights.append(top - bottom if top >= bottom else 0)
    return heights


def site_look(config, size):
    sites = config.get("sites")
    if not isinstance(sites, dict):
        return None
    prop = by_size(size, sites.get("small"), sites.get("medium"))
    return {"kind": SITE, "prop": prop, "stage": 0} if isinstance(prop, str) else None


def goal_for(config, index, parcel, state, prop_heights, landmark_height):
    """Fabric.goalFor ("What a parcel shows"): nothing at level 0, the site at 1, and from 2 the
    district's prop for parcel `index` at the highest stage its level allows that stays under the
    governor's height, never under heightFloor. `prop_heights(prop)` and `landmark_height(slotId)`
    answer as the client's propHeights and landmarkHeight."""
    if state is None or state["level"] <= 0:
        return None
    if state["level"] == 1:
        return site_look(config, parcel["size"])
    district = state["district"]
    districts = config.get("districts")
    props = districts.get(district) if district is not None and isinstance(districts, dict) else None
    chosen = by_size(parcel["size"], props.get("small"), props.get("medium")) if isinstance(props, dict) else None
    if not isinstance(chosen, list) or len(chosen) == 0:
        return None
    prop = chosen[(index - 1) % len(chosen)]
    if not isinstance(prop, str):
        return None
    heights = prop_heights(prop)
    stage = max(min(state["level"] - 2, len(heights) - 1), 0)
    cap = max(number_or(config.get("heightFloor"), 0), landmark_height(state["governor"]))
    while stage > 0 and heights[stage] > cap:
        stage -= 1
    return {"kind": BUILDING, "prop": prop, "stage": stage}


def color_from(rgb, fallback):
    """Fabric.colorFrom: each channel a finite number clamped to 0..255 (a missing one is 0); the
    fallback when there is no list at all."""
    if not isinstance(rgb, list):
        return fallback
    return tuple(min(max(number_or(luau_index(rgb, i), 0), 0), 255) for i in (1, 2, 3))


def grown(rect, margin):
    return {**rect, "margin": margin}


def chord(a, b):
    """A mask segment from two plot-local (x, z) points."""
    return {"ax": a[0], "az": a[1], "bx": b[0], "bz": b[1]}


def rect_corners(rect):
    """Fabric.rectCorners: plot-local corners in order round the rect."""
    angle = math.radians(rect["rotationY"])
    cos_a, sin_a = math.cos(angle), math.sin(angle)
    corners = []
    for sx, sz in CORNER_SIGNS:
        lx, lz = sx * rect["hx"], sz * rect["hz"]
        corners.append((rect["x"] + lx * cos_a + lz * sin_a, rect["z"] - lx * sin_a + lz * cos_a))
    return corners


def rotate(x, z, degrees):
    """CFrame.Angles(0, a, 0):VectorToWorldSpace on the XZ plane."""
    angle = math.radians(degrees)
    return (x * math.cos(angle) + z * math.sin(angle), -x * math.sin(angle) + z * math.cos(angle))


def facing_rot(dx, dz):
    """The rotationY whose front (-Z) points along (dx, dz), as CFrame.lookAt would turn a part."""
    return math.degrees(math.atan2(-dx, -dz))


# --------------------------------------------------------------------------------------------
# Heights: Assets.json first (the client's rule), the blueprint's measured stages as a fallback
# --------------------------------------------------------------------------------------------


class Heights:
    """Stage heights of landmarks (Assets.json only, as the client) and of fabric props (Assets.json,
    else the blueprint's measured y-range until the prop is harvested)."""

    def __init__(self, era_name, assets):
        self.era_name = era_name
        self.assets = assets
        self.prop_cache = {}
        self.glb_cache = {}
        self.fallbacks = set()  # props whose heights came from their blueprint
        self.missing = set()  # props with neither an Assets.json entry nor a usable blueprint

    def landmark(self, model_name):
        models = ((self.assets or {}).get("eras") or {}).get(self.era_name) or {}
        return stage_heights(models.get(model_name)) if model_name is not None else []

    def prop(self, prop):
        cached = self.prop_cache.get(prop)
        if cached is not None:
            return cached
        props = ((self.assets or {}).get("props") or {}).get(self.era_name) or {}
        if isinstance(prop, str) and prop in props:
            heights = stage_heights(props[prop])
        else:
            heights = self.blueprint_heights(prop)
            if heights:
                self.fallbacks.add(prop)
            else:
                self.missing.add(str(prop))
        self.prop_cache[prop] = heights
        return heights

    def glb_y_range(self, kit, model):
        key = (kit, model)
        if key in self.glb_cache:
            return self.glb_cache[key]
        import glbtools  # tools/assets, stdlib only

        found = None
        for sub in KIT_MODEL_DIRS:
            path = KITS_ROOT / kit / "Models" / sub / f"{model}.glb"
            if path.is_file():
                try:
                    bounds = glbtools.node_bounds(path.read_bytes())
                except (OSError, ValueError, KeyError, IndexError) as exc:
                    print(f"   note: cannot measure {kit}/{model}: {exc}", file=sys.stderr)
                    bounds = {}
                if bounds:
                    found = (
                        min(entry["min"][1] for entry in bounds.values()),
                        max(entry["max"][1] for entry in bounds.values()),
                    )
                break
        self.glb_cache[key] = found
        return found

    def blueprint_heights(self, prop):
        """Each stage's y-range in studs: the pieces up to that stage (stages are additive), turned
        about Y only, so their y-extent is the kit GLB's, lifted by pos.y and scaled."""
        if not isinstance(prop, str):
            return []
        path = BLUEPRINTS_DIR / "_props" / self.era_name / f"{prop}.json"
        if not path.exists():
            return []
        from blueprint import BlueprintError, load_blueprint  # tools/testfit, stdlib only

        try:
            blueprint = load_blueprint(str(path))
        except BlueprintError:
            return []
        heights = []
        for stage in range(blueprint.max_stage + 1):
            top, bottom = -math.inf, math.inf
            for piece in blueprint.pieces_at(stage):
                y_range = self.glb_y_range(piece.kit, piece.model)
                if y_range is None:
                    continue
                bottom = min(bottom, blueprint.scale * (piece.pos[1] + y_range[0]))
                top = max(top, blueprint.scale * (piece.pos[1] + y_range[1]))
            heights.append(top - bottom if top >= bottom else 0)
        return heights if any(heights) else []


# --------------------------------------------------------------------------------------------
# The plot the client sees: network, solids, pads, stages
# --------------------------------------------------------------------------------------------


def load_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def load_fabric_data(era_name):
    """Catalog.GetFabric: Config/Fabric/<Era>.json, or None (the era keeps its M9 dressing)."""
    path = FABRIC_DIR / f"{era_name}.json"
    return load_json(path) if path.exists() else None


def piece_ids(network):
    """RoadGraph's baked piece ids: L<polyline>_<n>, the n-th stretch of that polyline in creation
    order (its segments in order, then its connectors). streetplan counts polylines from 0."""
    ids, per_polyline = [], {}
    for stretch in network.stretches:
        ordinal = per_polyline.get(stretch["polyline"], 0) + 1
        per_polyline[stretch["polyline"]] = ordinal
        ids.append(f"L{stretch['polyline'] + 1}_{ordinal}")
    return ids


def model_extents(model):
    """Scatter.modelExtents: XZ bounds of every harvested part of every stage, offsets negated (the
    glTF import's turn); a part without a mesh id is not harvested and is skipped."""
    if not isinstance(model, dict) or not isinstance(model.get("stages"), list):
        return None
    extents = None
    for stage in model["stages"]:
        for part in (stage or {}).get("parts") or []:
            mesh = part.get("meshId")
            if not is_xz_triple(part.get("size")) or not is_xz_triple(part.get("offset")):
                continue
            if not is_number(mesh) or mesh <= 0:
                continue
            centre_x, centre_z = -part["offset"][0], -part["offset"][2]
            box = [
                centre_x - part["size"][0] / 2,
                centre_x + part["size"][0] / 2,
                centre_z - part["size"][2] / 2,
                centre_z + part["size"][2] / 2,
            ]
            if extents is None:
                extents = box
            else:
                extents = [
                    min(extents[0], box[0]),
                    max(extents[1], box[1]),
                    min(extents[2], box[2]),
                    max(extents[3], box[3]),
                ]
    return tuple(extents) if extents is not None else None


def centred_extents(size_x, size_z):
    return (-size_x / 2, size_x / 2, -size_z / 2, size_z / 2)


def footprint_rect(origin, rotation_y, extents):
    """Fabric.footprintRect: the extents need not be centred on the origin, so the rect's centre is
    their middle carried into the plot. The rect keeps the footprint's own rotation."""
    mid_x, mid_z = (extents[0] + extents[1]) / 2, (extents[2] + extents[3]) / 2
    offset = rotate(mid_x, mid_z, rotation_y)
    return {
        "x": origin[0] + offset[0],
        "z": origin[1] + offset[1],
        "hx": (extents[1] - extents[0]) / 2,
        "hz": (extents[3] - extents[2]) / 2,
        "rotationY": rotation_y,
        "margin": 0,
    }


def stage_for_level(level, milestone_levels):
    """PlotService.stageForLevel: the count of base milestones at or below the level."""
    return sum(1 for milestone in milestone_levels if milestone <= level)


def present_stages(model):
    """gen_templates: a template carries Stage<n> for every uploaded and harvested stage."""
    present = []
    if not isinstance(model, dict):
        return present
    for index, stage in enumerate(model.get("stages") or []):
        parts = (stage or {}).get("parts") or []
        if int(stage.get("modelAssetId", 0) or 0) == 0:
            continue
        if not parts or not all(int(p.get("meshId", 0) or 0) != 0 for p in parts):
            continue
        present.append(index)
    return present if present and present[0] == 0 else []


def visible_stage(slot_config, level, era_models, milestone_levels):
    """The Stage<n> a client reads under Building_<slotId> at `level`: PlotService's stage for the
    level (buildings only), picked among the template's harvested stages (the highest present at or
    under it); 0 for a streetOnly marker or a slot without a template."""
    if slot_config is None or slot_config.get("streetOnly"):
        return 0
    wanted = stage_for_level(level, milestone_levels) if slot_config.get("type") == "building" else 0
    present = present_stages((era_models or {}).get(slot_config.get("modelName")))
    chosen = [index for index in present if index <= wanted]
    return max(chosen) if chosen else 0


def landmark_stages(era_config, owned, levels, assets=None, game=None, final=False):
    """slot id -> visible stage for every owned slot: at its level in `levels` (1 when absent), or
    with `final` at the game's last level -- what the finished plot shows."""
    assets = assets if assets is not None else load_json(ASSETS_PATH)
    game = game if game is not None else load_json(GAME_CONFIG_PATH)
    era_models = ((assets or {}).get("eras") or {}).get(era_config["name"]) or {}
    configs = {slot["id"]: slot for slot in era_config["slots"]}
    stages = {}
    for slot_id in owned:
        level = game["maxLevel"] if final else levels.get(slot_id, 1)
        stages[slot_id] = visible_stage(configs.get(slot_id), level, era_models, game["milestoneLevels"])
    return stages


class FabricPlot:
    """One era's fabric as a client builds it (Fabric.new): everything static, plus `snapshot`, which
    is one settled Fabric.Sync -- the state a joining player sees, with no construction under way."""

    def __init__(self, era_name, city=None, era=None, network=None, data=None, assets=None):
        self.city = city if city is not None else load_json(CITY_CONFIG_PATH)
        self.era = era if era is not None else streetplan.Era(era_name, self.city)
        self.network = network if network is not None else streetplan.Network(self.era)
        self.name = era_name
        self.data = data if data is not None else load_fabric_data(era_name)
        self.config = (self.city.get("eras", {}).get(era_name) or {}).get("fabric")
        self.assets = assets if assets is not None else load_json(ASSETS_PATH)
        self.budget = self.city.get("budget") or {}
        self.game = load_json(GAME_CONFIG_PATH)
        layout = self.era.layout
        self.layout = layout
        self.ground_drop = float(layout["plotSize"][1])  # PlotService: bases rest on the ground plane
        self.heights = Heights(era_name, self.assets)
        self.slot_configs = {slot["id"]: slot for slot in self.era.config["slots"]}
        self.model_names = {slot["id"]: slot.get("modelName") for slot in self.era.config["slots"]}
        self.street_only = {slot["id"]: slot.get("streetOnly") is True for slot in self.era.config["slots"]}
        self.ids = piece_ids(self.network)
        self.groups_allowed, spurs_allowed = self.network.straight_allocate()
        self.spurs_allowed = set(spurs_allowed)
        self._build_solids()
        self._build_views()

    @classmethod
    def load(cls, era_name, **kwargs):
        """The fabric the client would build, or None: it needs both the era's data and its config
        block (CityDressingController only builds a Fabric then)."""
        city = kwargs.get("city") if kwargs.get("city") is not None else load_json(CITY_CONFIG_PATH)
        kwargs["city"] = city
        data = kwargs.get("data") if kwargs.get("data") is not None else load_fabric_data(era_name)
        config = (city.get("eras", {}).get(era_name) or {}).get("fabric")
        if data is None or config is None:
            return None
        kwargs["data"] = data
        return cls(era_name, **kwargs)

    # -- static (Fabric.new) ---------------------------------------------------------------

    def _build_solids(self):
        """Scatter.Solids' slot, pad and plaza keep-outs as Fabric's clearing rects."""
        layout = self.layout
        placeholder = layout["placeholderSize"]
        pad_size = layout["padSize"]
        era_models = ((self.assets or {}).get("eras") or {}).get(self.name) or {}
        era_props = ((self.assets or {}).get("props") or {}).get(self.name) or {}
        largest_x, largest_z = placeholder[0], placeholder[2]
        slot_extents = {}
        for slot_id in layout["slots"]:
            model_name = self.model_names.get(slot_id)
            extents = model_extents(era_models.get(model_name)) if model_name is not None else None
            extents = extents or centred_extents(placeholder[0], placeholder[2])
            slot_extents[slot_id] = extents
            largest_x = max(largest_x, extents[1] - extents[0])
            largest_z = max(largest_z, extents[3] - extents[2])
        self.slot_rects, self.pad_rects, self.slot_frames = {}, {}, {}
        for slot_id, slot in layout["slots"].items():
            position = (slot["position"][0], slot["position"][2])
            rotation = slot["rotationY"]
            self.slot_frames[slot_id] = (position[0], position[1], rotation)
            self.slot_rects[slot_id] = footprint_rect(position, rotation, slot_extents[slot_id])
            if "padPosition" in slot:
                pad = (slot["padPosition"][0], slot["padPosition"][2])
            else:
                face = streetplan.facing(rotation)
                pad = (position[0] + face[0] * layout["padOffset"], position[1] + face[1] * layout["padOffset"])
            # Pads lie unturned in the plot frame (PlotService.padWorldCFrame).
            self.pad_rects[slot_id] = footprint_rect(pad, 0, centred_extents(pad_size[0], pad_size[2]))
        self.plaza_rects = {}
        for index, plaza in enumerate(layout.get("plazas") or [], start=1):
            extents = model_extents(era_props.get(plaza["prop"])) or centred_extents(largest_x, largest_z)
            position = (plaza["position"][0], plaza["position"][2])
            self.plaza_rects[index] = footprint_rect(position, plaza["rotationY"], extents)

    def _build_views(self):
        """Fabric.new: config and data validated once, the parcel views (a malformed parcel is a blank
        that never develops; none at all without `sizes`) and the budgets, fixed prefixes of the
        data lists."""
        config = self.config or {}
        data = self.data if isinstance(self.data, dict) else {}
        self.pull = valid_pull(config.get("pull"))
        self.clear = config.get("clear") if isinstance(config.get("clear"), dict) else None
        self.wild_config = valid_wild_config(config.get("wild"))
        parcel_budget = max(math.floor(number_or(self.budget.get("parcels"), 0)), 0)
        raw_parcels = data.get("parcels") if isinstance(data.get("parcels"), list) else []
        self.parcel_data = []
        self.parcel_views = []
        sizes = config.get("sizes")
        for index, raw in enumerate(raw_parcels, start=1):
            well_formed = valid_parcel(raw)
            parcel = raw if well_formed else blank_parcel()
            self.parcel_data.append(parcel)
            if not isinstance(sizes, dict):
                continue
            size = by_size(parcel["size"], sizes.get("small"), sizes.get("medium"))
            width = number_or(luau_index(size, 1), 0)
            depth = number_or(luau_index(size, 2), 0)
            self.parcel_views.append(
                {
                    "index": index,
                    "parcel": parcel,
                    "rect": {
                        "x": parcel["x"],
                        "z": parcel["z"],
                        "hx": width / 2,
                        "hz": depth / 2,
                        "rotationY": parcel["rotationY"],
                        "margin": 0,
                    },
                    "eligible": well_formed and index <= parcel_budget,
                }
            )
        self.wild_data = data.get("wild") if isinstance(data.get("wild"), list) else []
        near_budget = max(math.floor(number_or(self.budget.get("wild"), 0)), 0)
        far_budget = max(math.floor(number_or(self.budget.get("wildFar"), 0)), 0)
        self.wild_valid, self.wild_near, self.wild_far = set(), set(), set()
        clumps = 0
        for index, entry in enumerate(self.wild_data, start=1):
            well_formed = valid_wild_entry(entry)
            if well_formed:
                self.wild_valid.add(index)
            if index <= near_budget:
                self.wild_near.add(index)
            if well_formed and entry.get("kind") == CLUMP:
                clumps += 1
                if clumps <= far_budget:
                    self.wild_far.add(index)

    # -- inputs the controller gathers ------------------------------------------------------

    def buyable_in_order(self, owned):
        """PlotService.refreshPads (Fabric.buyableSlots): unowned, and the effective requires (the
        config's, else the previous slot in purchase order) owned; the first slot is always
        buyable. In purchase order."""
        slots, previous = [], None
        for config in self.era.config["slots"]:
            requires = config.get("requires") or previous
            if config["id"] not in owned and (requires is None or requires in owned):
                slots.append(config["id"])
            previous = config["id"]
        return slots

    def buyable(self, owned):
        return set(self.buyable_in_order(owned))

    def visible_stage(self, slot_id, level):
        era_models = ((self.assets or {}).get("eras") or {}).get(self.name) or {}
        return visible_stage(self.slot_configs.get(slot_id), level, era_models, self.game["milestoneLevels"])

    def final_stages(self, owned):
        """Every owned slot at the stage its template shows at the last level."""
        return landmark_stages(self.era.config, owned, {}, self.assets, self.game, final=True)

    def network_view(self, owned):
        """RoadGraph.AddSpur for each owned slot in sorted order, then RoadGraph.FabricNetwork:
        (stretches by piece id, join nodes, mask segments, visible stretch ids, drawn spur slots)."""
        network, era = self.network, self.era
        visible, drawn = set(), []
        for slot_id in sorted(owned):
            if slot_id not in self.spurs_allowed:
                continue
            drawn.append(slot_id)
            node = network.junction_nodes.get(slot_id)
            if node is not None:
                self._reveal(node, visible)
        stretches, segments = {}, []
        for stretch_id in sorted(visible):
            stretch = network.stretches[stretch_id]
            stretches[self.ids[stretch_id]] = {
                "from": stretch["from"] + 1,
                "to": stretch["to"] + 1,
                "length": stretch["length"],
            }
            segments.append(chord(stretch["a"], stretch["b"]))
        joins = {}
        drawn_set = set(drawn)
        for slot_id in network.spur_ids:
            node = network.junction_nodes.get(slot_id)
            if node is not None:
                joins[slot_id] = node + 1
            if slot_id in drawn_set:
                for a, b in streetplan.polyline_segments(era.spurs[slot_id]["points"]):
                    segments.append(chord(a, b))
        return stretches, joins, segments, visible, drawn

    def _reveal(self, node, visible):
        """RoadGraph.reveal: walk back to the first visible stretch, then reveal from the entrance
        outward up to the first stretch whose group missed the straight budget."""
        network = self.network
        if node not in network.distance:
            return
        path, current = [], node
        while current != network.entrance:
            stretch_id = network.parent.get(current)
            if stretch_id is None or stretch_id in visible:
                break
            path.append(stretch_id)
            stretch = network.stretches[stretch_id]
            current = stretch["to"] if stretch["from"] == current else stretch["from"]
        for stretch_id in reversed(path):
            if network.stretches[stretch_id]["group"] not in self.groups_allowed:
                break
            visible.add(stretch_id)

    def visible_plazas(self, tier):
        """syncFabric: plazas by syncFiller's rule (Scatter.Plan's filler budget, then the tier)."""
        plazas = self.layout.get("plazas") or []
        remaining = number_or(self.budget.get("fillerPieces"), 0)
        shown = []
        for index, plaza in enumerate(plazas, start=1):
            allowed = remaining > 0
            if allowed:
                remaining -= 1
            if allowed and plaza["tier"] <= tier:
                shown.append(index)
        return shown

    # -- one settled sync -------------------------------------------------------------------

    def landmark_height(self, slot_id, stages):
        """Fabric.landmarkHeight: the governor's harvested height at the stage it shows; 0 without
        a template."""
        model_name = self.model_names.get(slot_id) if slot_id is not None else None
        if slot_id is None or model_name is None:
            return 0
        heights = self.heights.landmark(model_name)
        stage = stages.get(slot_id) or 0
        return heights[stage] if 0 <= stage < len(heights) else 0

    def develop_states(self, owned, tier, stretches, joins, trace=None):
        """Fabric.develop: every parcel at level 0 without a valid pull block."""
        parcels = self.parcel_data
        if self.pull is None:
            return [{"level": 0, "district": None, "governor": None} for _ in parcels]
        landmarks = []
        for slot_id in sorted(owned):
            slot = self.layout["slots"].get(slot_id)
            district = slot.get("district") if slot is not None else None
            node = joins.get(slot_id)
            if district is not None and node is not None:
                landmarks.append({"slotId": slot_id, "node": node, "district": district})
        return develop({"tier": tier, "stretches": stretches, "landmarks": landmarks, "parcels": parcels}, self.pull, trace)

    def mask(self, owned, states, segments, plazas):
        """Fabric.buildMask: owned footprints (+clear.slot) and their pads (+clear.pad), every buyable
        slot's footprint and pad (+clear.pad), parcels at level 1 and up (+clear.parcel, budget or not), visible plazas
        (+clear.parcel), and the street segments (clear.street)."""
        clear = self.clear
        if clear is None:
            return {"rects": [], "segments": [], "streetClear": 0}
        rects = []
        slot_margin = number_or(clear.get("slot"), 0)
        pad_margin = number_or(clear.get("pad"), 0)
        parcel_margin = number_or(clear.get("parcel"), 0)
        for slot_id in sorted(owned):
            rect = self.slot_rects.get(slot_id)
            if rect is not None:
                rects.append(grown(rect, slot_margin))
            # Fabric.buildMask: a bought slot keeps its pad clearing (woods never regrow on a buy).
            pad = self.pad_rects.get(slot_id)
            if pad is not None:
                rects.append(grown(pad, pad_margin))
        for slot_id in self.buyable_in_order(owned):
            footprint = self.slot_rects.get(slot_id)
            if footprint is not None:
                rects.append(grown(footprint, pad_margin))
            pad = self.pad_rects.get(slot_id)
            if pad is not None:
                rects.append(grown(pad, pad_margin))
        for view, state in zip(self.parcel_views, states):
            if state["level"] >= 1:
                rects.append(grown(view["rect"], parcel_margin))
        for index in plazas:
            rect = self.plaza_rects.get(index)
            if rect is not None:
                rects.append(grown(rect, parcel_margin))
        return {"rects": rects, "segments": segments, "streetClear": number_or(clear.get("street"), 0)}

    def cleared_flags(self, mask):
        """Fabric.clearedFlags: bit q-1 per cleared quarter of a clump, bit 0 for a single; a
        malformed entry clears nothing."""
        wild_config = self.wild_config or {}
        quarter_radius = number_or(wild_config.get("quarterRadius"), 0)
        single_radius = number_or(wild_config.get("singleRadius"), 0)
        flags = {}
        for index, entry in enumerate(self.wild_data, start=1):
            bits = 0
            if index not in self.wild_valid:
                flags[index] = bits
                continue
            if entry.get("kind") == CLUMP:
                quads = entry.get("quads")
                for quarter in range(1, QUARTERS + 1):
                    point = quads[quarter - 1] if isinstance(quads, list) and len(quads) >= quarter else None
                    x = number_or(point[0], entry["x"]) if isinstance(point, list) and len(point) > 0 else entry["x"]
                    z = number_or(point[1], entry["z"]) if isinstance(point, list) and len(point) > 1 else entry["z"]
                    if is_cleared(x, z, quarter_radius, mask):
                        bits |= 1 << (quarter - 1)
            elif is_cleared(entry["x"], entry["z"], single_radius, mask):
                bits = 1
            flags[index] = bits
        return flags

    def wild_placements(self, cleared, near, share=1.0):
        """Fabric.syncWild, settled: near plots draw every uncleared clump, quarter and single among
        the first budget.wild entries, far plots the whole clumps among the first budget.wildFar
        clumps; detail off keeps an even share by index. A skirt entry stands on the world ground."""
        wild_config = self.wild_config
        if wild_config is None:
            return []
        clumps, quarters = wild_config["clumps"], wild_config["quarters"]
        share = min(max(number_or(share, 1), 0), 1)
        placements = []
        for index, entry in enumerate(self.wild_data, start=1):
            if index not in self.wild_valid:
                continue
            bits = cleared.get(index, 0)
            kept = share >= 1 or math.floor(index * share) > math.floor((index - 1) * share)
            in_budget = index in (self.wild_near if near else self.wild_far)
            show = kept and in_budget
            clump = entry.get("kind") == CLUMP
            want_whole = clump and show and bits == 0
            want_quarters = clump and show and near and bits != 0 and bits != ALL_QUARTERS
            want_single = not clump and show and near and bits == 0
            ground = -self.ground_drop if entry.get("skirt") is True else 0.0
            variant = entry.get("variant")
            base = {"index": index, "x": entry["x"], "y": ground, "z": entry["z"], "scale": scale_of(entry.get("scale"))}
            if want_whole:
                placements.append(
                    {**base, "kind": "whole", "prop": luau_index(clumps, variant), "rotationY": entry["rotationY"]}
                )
            if want_single:
                placements.append(
                    {**base, "kind": "single", "prop": entry.get("prop"), "rotationY": entry["rotationY"]}
                )
            if want_quarters:
                for quarter in range(1, QUARTERS + 1):
                    if bits & (1 << (quarter - 1)):
                        continue
                    placements.append(
                        {
                            **base,
                            "kind": "quarter",
                            "quarter": quarter,
                            "prop": luau_index(quarters, variant),
                            "rotationY": entry["rotationY"] + QUARTER_TURN_DEGREES * (quarter - 1),
                        }
                    )
        return placements

    def pad_dressing(self, owned, near):
        """Fabric.syncPads for the pads PlotService shows (the buyable slots): padLook on every pad;
        on a near plot the marker, in the slot's frame, and (not for streetOnly slots) stakes and
        strings round the slot's footprint rect."""
        config = self.config or {}
        look = config.get("padLook") if isinstance(config.get("padLook"), dict) else None
        marker = config.get("marker") if isinstance(config.get("marker"), dict) else None
        pad_color = color_from(look.get("color"), None) if look is not None else None
        stake_color = color_from(marker.get("stakeColor"), (0, 0, 0)) if marker is not None else None
        string_color = color_from(marker.get("stringColor"), (255, 255, 255)) if marker is not None else None
        pads = []
        for slot_id in self.buyable_in_order(owned):
            if slot_id not in self.layout["slots"]:
                continue
            pad_rect = self.pad_rects.get(slot_id)
            dressing = {
                "slotId": slot_id,
                "pad": pad_rect,
                "color": pad_color,  # None: the pad keeps the server's look
                "material": look.get("material") if look is not None else None,
                "marker": None,
                "stakes": [],
                "strings": [],
                "stakeColor": stake_color,
                "stringColor": string_color,
            }
            pads.append(dressing)
            if not near or marker is None:
                continue
            frame = self.slot_frames.get(slot_id)
            if pad_rect is not None and frame is not None and isinstance(marker.get("prop"), str):
                offset = marker.get("offset") if isinstance(marker.get("offset"), list) else []
                ox = number_or(offset[0], 0) if len(offset) > 0 else 0
                oy = number_or(offset[1], 0) if len(offset) > 1 else 0
                oz = number_or(offset[2], 0) if len(offset) > 2 else 0
                turned = rotate(ox, oz, frame[2])
                dressing["marker"] = {
                    "prop": marker.get("prop"),
                    "x": pad_rect["x"] + turned[0],
                    "y": oy,
                    "z": pad_rect["z"] + turned[1],
                    "rotationY": frame[2],
                }
            rect = self.slot_rects.get(slot_id)
            if self.street_only.get(slot_id) or rect is None:
                continue
            corners = rect_corners(rect)
            for index, corner in enumerate(corners):
                dressing["stakes"].append(
                    {
                        "size": (STAKE_WIDTH, STAKE_HEIGHT, STAKE_WIDTH),
                        "pos": (corner[0], STAKE_HEIGHT / 2, corner[1]),
                        "rotationY": rect["rotationY"],
                    }
                )
                following = corners[(index + 1) % len(corners)]
                dx, dz = following[0] - corner[0], following[1] - corner[1]
                length = math.sqrt(dx * dx + dz * dz)
                if length > 0:
                    dressing["strings"].append(
                        {
                            "size": (STRING_THICKNESS, STRING_THICKNESS, length),
                            "pos": ((corner[0] + following[0]) / 2, STRING_HEIGHT, (corner[1] + following[1]) / 2),
                            "rotationY": facing_rot(dx, dz),
                        }
                    )
        return pads

    def snapshot(self, owned, stages, tier, near=True, share=1.0):
        """One settled Fabric.Sync: what a player who joins now sees on this plot.

        `owned` is the owned slot ids, `stages` each owned slot's visible stage, `tier` GrowthTier."""
        owned = set(owned)
        stretches, joins, segments, visible, drawn = self.network_view(owned)
        trace = []
        states = self.develop_states(owned, tier, stretches, joins, trace)
        config = self.config or {}
        parcels = []
        for view, state in zip(self.parcel_views, states):
            look = goal_for(
                config,
                view["index"],
                view["parcel"],
                state,
                self.heights.prop,
                lambda slot_id: self.landmark_height(slot_id, stages),
            )
            parcels.append({**view, "state": state, "look": look if view["eligible"] else None})
        plazas = self.visible_plazas(tier)
        mask = self.mask(owned, states, segments, plazas) if self.wild_config is not None else None
        cleared = self.cleared_flags(mask) if mask is not None else {}
        return {
            "tier": tier,
            "owned": sorted(owned),
            "stages": dict(stages),
            "stretches": stretches,
            "joins": joins,
            "segments": segments,
            "visible": visible,
            "drawn": drawn,
            "states": states,
            "trace": trace,
            "parcels": parcels,
            "plazas": plazas,
            "mask": mask,
            "cleared": cleared,
            "wild": self.wild_placements(cleared, near, share),
            "pads": self.pad_dressing(owned, near),
            "near": near,
        }

    def fragile(self, snap):
        """Parcels whose outcome sits within FRAGILE of a threshold, the pull radius or the reach:
        float32 stretch lengths in game could tip them the other way."""
        pull = self.pull
        found = []
        if pull is None:
            return found
        for index, (state, record) in enumerate(zip(snap["states"], snap["trace"]), start=1):
            score = record["score"]
            for threshold in pull["thresholds"]:
                if score and abs(score - threshold) < FRAGILE:
                    pulling = ", ".join(
                        f"{slot_id} {distance:.4f}" for slot_id, distance in record["pulls"] if distance < pull["radius"]
                    )
                    found.append(f"parcel {index}: score {score!r} at threshold {threshold} (pulled by {pulling})")
            for slot_id, distance in record["pulls"]:
                if abs(distance - pull["radius"]) < FRAGILE:
                    found.append(f"parcel {index}: {slot_id} at the pull radius ({distance:.6f})")
            near = record["reach"]
            if near is not None and abs(near - pull["reach"]) < FRAGILE:
                found.append(f"parcel {index}: contiguity distance {near:.6f} at reach {pull['reach']}")
        return found

    def stale(self):
        """Parcels whose address the current street network cannot hold: a piece id it does not have,
        or `along` past that stretch's end. The client develops such data silently (a parcel on a
        stretch that is never visible never develops), so this is only a hint that the fabric JSON
        predates the layout and `fabric.py build` is due."""
        lengths = {piece_id: self.network.stretches[index]["length"] for index, piece_id in enumerate(self.ids)}
        notes = []
        for index, parcel in enumerate(self.parcel_data, start=1):
            if parcel["stretch"] == "":
                notes.append(f"parcel {index} is malformed (a blank that never develops)")
            elif parcel["stretch"] not in lengths:
                notes.append(f"parcel {index} fronts {parcel['stretch']}, which the network does not have")
            elif not -0.05 <= parcel["along"] <= lengths[parcel["stretch"]] + 0.05:
                length = lengths[parcel["stretch"]]
                notes.append(f"parcel {index}: along {parcel['along']} outside {parcel['stretch']} ({length:.2f})")
        return notes

    def unclear_risks(self):
        """Wild points a slot's pad part of the mask clears (footprint and pad, +clear.pad, while the
        slot is buyable) that its owned part does not (footprint +clear.slot, its spur legs and its
        path from the entrance, +clear.street). The client rebuilds the cleared flags from the mask
        on every change, so such a point grows its trees back when the slot is bought, whatever the
        purchase order -- the review amendment's "the mask never shrinks" holds only while this is
        empty."""
        clear = self.clear
        if clear is None or self.wild_config is None:
            return []
        points = []
        for index, entry in enumerate(self.wild_data, start=1):
            if index not in self.wild_valid:
                continue
            if entry.get("kind") == CLUMP and isinstance(entry.get("quads"), list):
                for quarter, point in enumerate(entry["quads"][:QUARTERS], start=1):
                    points.append((index, quarter, point[0], point[1], self.wild_config["quarterRadius"]))
            elif entry.get("kind") != CLUMP:
                points.append((index, 0, entry["x"], entry["z"], self.wild_config["singleRadius"]))
        street = number_or(clear.get("street"), 0)
        pad_margin = number_or(clear.get("pad"), 0)
        slot_margin = number_or(clear.get("slot"), 0)
        risks = []
        for slot_id in self.layout["slots"]:
            footprint, pad = self.slot_rects[slot_id], self.pad_rects[slot_id]
            buyable = {"rects": [grown(footprint, pad_margin), grown(pad, pad_margin)], "segments": [], "streetClear": street}
            segments = []
            if slot_id in self.spurs_allowed:
                segments += [chord(a, b) for a, b in streetplan.polyline_segments(self.era.spurs[slot_id]["points"])]
                visible = set()
                node = self.network.junction_nodes.get(slot_id)
                if node is not None:
                    self._reveal(node, visible)
                segments += [chord(self.network.stretches[i]["a"], self.network.stretches[i]["b"]) for i in visible]
            owned = {"rects": [grown(footprint, slot_margin)], "segments": segments, "streetClear": street}
            for index, quarter, x, z, radius in points:
                if is_cleared(x, z, radius, buyable) and not is_cleared(x, z, radius, owned):
                    where = f" quarter {quarter}" if quarter else ""
                    risks.append(f"{slot_id}: wild {index}{where} at ({x:g}, {z:g})")
        return risks


# --------------------------------------------------------------------------------------------
# The sim's greedy player: who owns what, at which level, at the end of each tier
# --------------------------------------------------------------------------------------------


def _replay_greedy(sim, era, game, legacy, city):
    """tools/sim_economy.py simulate_era(strategy "greedy", free player, empty shop, lap 1), step
    for step, recording every purchase: (tick, kind, slot id, levels after). Returns (purchases,
    tier_times)."""
    shop = {"version": 1, "perks": []}
    shop_state = sim.empty_shop_state()
    discount = sim.level_cost_discount(shop, shop_state)
    floor = sim.level_floor(shop, shop_state)
    milestones = sim.milestone_levels(shop, shop_state, game)
    by_id = {slot["id"]: slot for slot in era["slots"]}
    requires = sim.resolve_requires(era)
    children = {}
    for slot_id, required in requires.items():
        if required is not None:
            children.setdefault(required, []).append(slot_id)
    mults = {
        "legacy": sim.legacy_mult(legacy, game),
        "perk": sim.perk_income_mult(shop, shop_state),
        "pass": 1,
        "premium": 1,
        "neighbors": 1,
    }
    owned = {}
    frontier = [slot["id"] for slot in era["slots"] if requires[slot["id"]] is None]
    total_slots = len(era["slots"])
    cash = sim.inheritance_cash(era, shop, shop_state)
    ips = 0.0
    t = 0
    thresholds = city["tier"]["thresholds"]
    weight = city["tier"]["ownedWeight"]
    tier_times = [None] * len(thresholds)
    purchases = []
    while True:
        while True:
            best_cost, best_kind, best_id = None, None, None
            for slot_id in frontier:
                cost = by_id[slot_id]["baseCost"]
                if best_cost is None or cost < best_cost:
                    best_cost, best_kind, best_id = cost, "slot", slot_id
            for slot_id, level in owned.items():
                slot = by_id[slot_id]
                if slot["type"] == "building" and level < game["maxLevel"]:
                    cost = sim.level_up_cost(slot["baseCost"], level + 1, game, discount)
                    if best_cost is None or cost < best_cost:
                        best_cost, best_kind, best_id = cost, "level", slot_id
            if best_cost is None or cash < best_cost - 1e-9:
                break
            cash -= best_cost
            if best_kind == "slot":
                owned[best_id] = floor if by_id[best_id]["type"] == "building" else 1
                frontier.remove(best_id)
                frontier.extend(children.get(best_id, []))
            else:
                owned[best_id] += 1
            score = sim.city_growth_score(len(owned), sum(owned.values()), weight)
            for index in range(sim.city_growth_tier_for(score, thresholds)):
                if tier_times[index] is None:
                    tier_times[index] = t
            purchases.append((t, best_kind, best_id, dict(owned)))
            if best_kind == "slot" and len(owned) == total_slots:
                return purchases, tier_times
            ips = sim.income_per_second(owned, era, game, mults, milestones)
        t += 1
        if t > sim.TICK_LIMIT:
            raise RuntimeError(f"{era['name']} did not finish in the replay")
        cash += ips


def greedy_history(era_name, city):
    """The greedy player's purchases in `era_name`, legacy carried in from the earlier eras exactly as
    streetplan.greedy_buy_tiers does. simulate_era exposes only the slot order and tier times, so
    the replay is checked against both: a change to the sim's loop fails here instead of drifting."""
    sim = streetplan.load_sim()
    game = sim.load_game_config()
    legacy = 0
    for era in sim.load_eras():
        reference = sim.simulate_era(era, game, legacy, "greedy", city=city)
        if era["name"] == era_name:
            purchases, tier_times = _replay_greedy(sim, era, game, legacy, city)
            order = [(slot_id, t) for t, kind, slot_id, _ in purchases if kind == "slot"]
            if order != list(reference.slot_order) or tier_times != list(reference.tier_times):
                raise SystemExit(
                    "cityfabric: the greedy replay no longer matches tools/sim_economy.py; update _replay_greedy"
                )
            return {"purchases": purchases, "tier_times": tier_times}
        legacy += reference.legacy_gained
    raise SystemExit(f"cityfabric: no era named {era_name} in the sim")


def tier_at_tick(tier_times, t):
    """The growth tier at the end of tick t (every purchase of that tick made)."""
    return sum(1 for reached in tier_times if reached is not None and reached <= t)


def buy_tiers(history):
    """streetplan.greedy_buy_tiers from the same replay: slot -> tier right after its tick."""
    tiers = {}
    for t, kind, slot_id, _ in history["purchases"]:
        if kind == "slot":
            tiers[slot_id] = max(1, tier_at_tick(history["tier_times"], t))
    return tiers


def tier_snapshot(history, tier):
    """The last moment of `tier`: levels at the end of the last tick whose tier is at most `tier`.
    Its owned set is exactly the slots greedy_buy_tiers puts at or below `tier` (plotrender's
    resolve_owned). Returns (levels, GrowthTier then, tick)."""
    chosen = None
    for purchase in history["purchases"]:
        if tier_at_tick(history["tier_times"], purchase[0]) <= tier:
            chosen = purchase
    if chosen is None:
        return {}, 0, 0
    return dict(chosen[3]), tier_at_tick(history["tier_times"], chosen[0]), chosen[0]


# --------------------------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------------------------

SELFTEST_PULL = {
    "radius": 24,
    "tierTerm": 0.14,
    "thresholds": [0.9, 1.4, 1.7, 2.1],
    "reach": 13,
    "levelsOverTier": 1,
    "smallMaxLevel": 3,
}
SELFTEST_STRETCHES = {
    "L1_1": {"from": 1, "to": 2, "length": 10},
    "L1_2": {"from": 2, "to": 3, "length": 10},
    "L2_1": {"from": 3, "to": 4, "length": 20},
}
SELFTEST_LANDMARKS = [
    {"slotId": "well", "node": 1, "district": "civic"},
    {"slotId": "tavern", "node": 2, "district": "market"},
]


def _parcel(size, stretch, along, row, front=0):
    return {"x": 0, "z": 0, "rotationY": 0, "size": size, "stretch": stretch, "along": along, "row": row, "front": front}


SELFTEST_PARCELS = [
    _parcel("medium", "L1_2", 6, 1),
    _parcel("small", "L2_1", 5, 1),
    _parcel("medium", "L1_2", 6, 2, front=1),
]


def selftest():
    failures = []

    def run(label, tier, parcels, stretches=None, landmarks=None):
        return label, develop(
            {
                "tier": tier,
                "stretches": SELFTEST_STRETCHES if stretches is None else stretches,
                "landmarks": SELFTEST_LANDMARKS if landmarks is None else landmarks,
                "parcels": parcels,
            },
            SELFTEST_PULL,
        )

    def expect(case, wanted):
        label, states = case
        got = [(s["level"], s["district"], s["governor"]) for s in states]
        verdict = "ok" if got == wanted else "FAIL"
        print(f"  {verdict:4s} {label}: {got}")
        if got != wanted:
            failures.append(f"{label}: wanted {wanted}")

    expect(run("tier 4", 4, SELFTEST_PARCELS), [(2, "market", "tavern"), (1, "market", "tavern"), (1, "market", "tavern")])
    expect(run("tier 1", 1, SELFTEST_PARCELS), [(1, "market", "tavern"), (0, "market", "tavern"), (0, "market", "tavern")])
    expect(run("tier 4, P2 alone (contiguity)", 4, [SELFTEST_PARCELS[1]]), [(0, "market", "tavern")])
    expect(run("tier 4, small on L1_1 at 5 (19/24 tie)", 4, [_parcel("small", "L1_1", 5, 1)]), [(3, "civic", "well")])
    hidden = {key: value for key, value in SELFTEST_STRETCHES.items() if key != "L1_2"}
    expect(run("tier 4, L1_2 hidden", 4, SELFTEST_PARCELS, stretches=hidden), [(0, None, None)] * 3)
    # Landmark order must not matter: the Luau sorts them before summing.
    expect(
        run("tier 4, landmarks listed backwards", 4, SELFTEST_PARCELS, landmarks=list(reversed(SELFTEST_LANDMARKS))),
        [(2, "market", "tavern"), (1, "market", "tavern"), (1, "market", "tavern")],
    )

    # The geometry helpers.
    rect = {"x": 10, "z": 0, "hx": 2, "hz": 1, "rotationY": 90, "margin": 1}
    checks = [
        ("rect inside", rect_distance(10, 0, rect), 0.0),
        # Turned 90 degrees, the rect's local X runs along world -Z: (10, 5) is 3 out along it.
        ("rect turned", rect_distance(10, 5, rect), 3.0),
        ("rect corner", rect_distance(13, 4, rect), math.sqrt(4 + 4)),
        ("segment middle", segment_distance(5, 3, {"ax": 0, "az": 0, "bx": 10, "bz": 0}), 3.0),
        ("segment end", segment_distance(13, 4, {"ax": 0, "az": 0, "bx": 10, "bz": 0}), 5.0),
        ("segment point", segment_distance(3, 4, {"ax": 0, "az": 0, "bx": 0, "bz": 0}), 5.0),
    ]
    for label, got, wanted in checks:
        good = abs(got - wanted) < 1e-9
        print(f"  {'ok' if good else 'FAIL':4s} {label}: {got:.6f}")
        if not good:
            failures.append(f"{label}: wanted {wanted}")
    # The turned rect reaches 2 studs along world Z, and its margin 1 more.
    mask = {"rects": [rect], "segments": [{"ax": -10, "az": 20, "bx": 10, "bz": 20}], "streetClear": 2}
    cases = [
        ("cleared by rect margin", (10, 2.9, 0), True),
        ("not cleared past margin", (10, 3.1, 0), False),
        ("radius reaches margin", (10, 3.5, 0.6), True),
        ("cleared by street", (0, 18.5, 0), True),
        ("street margin is strict", (0, 18.0, 0), False),
    ]
    for label, (px, pz, radius), wanted in cases:
        got = is_cleared(px, pz, radius, mask)
        print(f"  {'ok' if got == wanted else 'FAIL':4s} {label}: {got}")
        if got != wanted:
            failures.append(f"{label}: wanted {wanted}")

    if failures:
        print(f"selftest FAILED: {len(failures)}")
        for failure in failures:
            print(f"   {failure}")
        return 1
    print("selftest passed")
    return 0


def level_counts(snap):
    """Parcels in budget by level, and how many are drawn as sites or buildings."""
    counts = [0] * 5
    for view in snap["parcels"]:
        if view["eligible"]:
            counts[min(max(int(view["state"]["level"]), 0), 4)] += 1
    return counts


def wild_counts(snap):
    whole = sum(1 for p in snap["wild"] if p["kind"] == "whole")
    partial = len({p["index"] for p in snap["wild"] if p["kind"] == "quarter"})
    quarters = sum(1 for p in snap["wild"] if p["kind"] == "quarter")
    singles = sum(1 for p in snap["wild"] if p["kind"] == "single")
    return whole, partial, quarters, singles


def timeline(era_name):
    city = load_json(CITY_CONFIG_PATH)
    plot = FabricPlot.load(era_name, city=city)
    if plot is None:
        print(f"{era_name}: no fabric (needs src/shared/Config/Fabric/{era_name}.json and a `fabric` config block)")
        return 1
    history = greedy_history(era_name, city)
    tiers = buy_tiers(history)
    data = plot.data
    total_wild = len(data["wild"])
    print(
        f"{era_name} fabric timeline: the sim's greedy player at the last moment of each tier "
        f"(owned = bought by then, stages at that moment); {len(data['parcels'])} parcels "
        f"(budget {plot.budget.get('parcels')}), {total_wild} wild entries (near budget "
        f"{plot.budget.get('wild')}, far {plot.budget.get('wildFar')} clumps)"
    )
    print("  levels are counted over the parcels in budget; wild counts are what a near (far) plot draws")
    rows = []
    for tier in range(1, len(city["tier"]["thresholds"]) + 1):
        levels, actual, tick = tier_snapshot(history, tier)
        owned = {slot_id for slot_id in levels if tiers.get(slot_id, 99) <= tier}
        stages = {slot_id: plot.visible_stage(slot_id, levels.get(slot_id, 1)) for slot_id in owned}
        rows.append((f"tier {tier}", f"t={tick}s", owned, stages, actual))
    everything = {slot["id"] for slot in plot.era.config["slots"] if slot["id"] in plot.layout["slots"]}
    rows.append(("full", "final stages", everything, plot.final_stages(everything), len(city["tier"]["thresholds"])))
    fragile_notes = []
    for label, moment, owned, stages, tier in rows:
        near = plot.snapshot(owned, stages, tier, near=True)
        far = plot.snapshot(owned, stages, tier, near=False)
        counts = level_counts(near)
        whole, partial, quarters, singles = wild_counts(near)
        far_whole = wild_counts(far)[0]
        stage_text = " ".join(f"{sid}:{stages[sid]}" for sid in sorted(stages) if stages[sid])
        print(
            f"  {label:6s} ({moment:>12s}, GrowthTier {tier}): {len(owned):2d} owned, "
            f"{len(near['stretches']):2d} stretches | parcels L0 {counts[0]:2d}  L1 {counts[1]:2d}  "
            f"L2 {counts[2]:2d}  L3 {counts[3]:2d}  L4 {counts[4]:2d} | wild near {whole} whole, "
            f"{partial} partial ({quarters} quarters), {singles} singles; far {far_whole} whole"
        )
        if stage_text:
            print(f"         stages above 0: {stage_text}")
        fragile_notes += [f"{label}: {note}" for note in plot.fragile(near)]
    if plot.heights.fallbacks:
        print(f"  heights from blueprints (not harvested yet): {', '.join(sorted(plot.heights.fallbacks))}")
    if plot.heights.missing:
        print(f"  no height at all (no Assets entry, no measurable blueprint): {', '.join(sorted(plot.heights.missing))}")
    for note in fragile_notes:
        print(f"  FRAGILE {note}")
    for note in plot.stale():
        print(f"  STALE {note}")
    risks = plot.unclear_risks()
    print(f"  woods that grow back when their pad's slot is bought (any purchase order): {len(risks)}")
    for risk in risks:
        print(f"    {risk}")
    return 0


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("selftest", help="assert the contract's test vector")
    line = sub.add_parser("timeline", help="parcels by level and wild counts at tiers 1-5")
    line.add_argument("era")
    args = parser.parse_args(argv)
    if args.command == "selftest":
        return selftest()
    return timeline(args.era)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
