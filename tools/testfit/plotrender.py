#!/usr/bin/env python
"""Offline plot-level test-fit render: a whole era plot, dressed, from the tycoon camera.

tools/streetplan.py answers "is the plan legal?" from directly above; this answers "does it look
like a city?" from where the player stands. It mirrors the wave 1b/1e/2a contracts (docs/
INTERFACES.md) the same way streetplan mirrors them -- same layout parser, same network, same
shortest-path visibility -- and then hands Blender a scene of kit blueprints instead of a PNG of
coloured rectangles.

    py tools/testfit/plotrender.py Metropolis
    py tools/testfit/plotrender.py Metropolis --camera entrance --out plot_entrance
    py tools/testfit/plotrender.py Metropolis --tier 3
    py tools/testfit/plotrender.py Boomtown --camera overview

Outputs land in assets/testfit/out/<Era>/plot_<camera>.png.

This half runs under the system `py` because it imports tools/streetplan.py, which needs Pillow;
the rendering half is tools/testfit/plotscene.py, which runs inside Blender (no Pillow, no PIL
import allowed). They talk through a scene JSON in a temp file -- see plotscene.py for its shape.

What is mirrored, and from where (never re-derived, never duplicated as a constant):
  * layout, era config, dressing config, spurs, the road network and the shortest-path visibility:
    streetplan.Era / streetplan.Network / streetplan.visible_network;
  * tile cells, the connectivity mask table and the zebra rule: src/client/City/TileRenderer.luau
    (PIECE_BY_MASK, ARM_STEPS, CROSSING_MIN_RUN);
  * the ring cycle, the reveal-independent cell kinds and the ramp: src/client/City/Highway.luau
    and the INTERFACES "Elevated highway" contract. Where the two differ the CONTRACT wins: the
    ramp's high cell is the first cell inward of the junction (so its 3 cells are the ones
    streetplan checks and its toe lands on the street's end cell), not half a cell further out.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import random
import subprocess
import sys
import tempfile
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "tools"))
sys.path.insert(0, str(REPO_ROOT / "tools" / "testfit"))

import streetplan  # noqa: E402
from blueprint import load_blueprint  # noqa: E402

BLUEPRINTS_DIR = REPO_ROOT / "tools" / "testfit" / "blueprints"
OUT_ROOT = REPO_ROOT / "assets" / "testfit" / "out"
DEFAULT_BLENDER = r"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe"
RENDER_SIZE = (1600, 1000)
SKY = [190, 206, 226]

# TileRenderer.luau, mirrored: arm n is ARM_STEPS[n] on the (i, j) lattice, bit n-1 of a mask.
ARM_STEPS = ((1, 0), (0, -1), (-1, 0), (0, 1))  # +X, -Z, -X, +Z
SAMPLES_PER_CELL = 4
CROSSING_MIN_RUN = 3
# (kind, quarter turns) for every one of the 16 connectivity masks -- PIECE_BY_MASK, index = mask.
PIECE_BY_MASK = (
    ("end", 0), ("end", 0), ("end", 1), ("bend", 2),
    ("end", 2), ("straight", 0), ("bend", 3), ("tee", 2),
    ("end", 3), ("bend", 1), ("straight", 1), ("tee", 1),
    ("bend", 0), ("tee", 0), ("tee", 3), ("cross", 0),
)
RAMP_DIRECTIONS = {"+X": (1.0, 0.0), "-X": (-1.0, 0.0), "+Z": (0.0, 1.0), "-Z": (0.0, -1.0)}

# Camera presets. `dir` is the direction from the subject toward the lens in plot-local studs (the
# tycoon three-quarter of testfit: +X and -Z, so the plot's hub edge faces the viewer); `half` is
# the horizontal half-box the shot must contain and `height` how tall the box is above ground;
# `lens` is millimetres on a 36 mm sensor.
TYCOON_DIR = (0.52, 0.78, -1.0)
CAMERAS = {
    "overview": {"dir": TYCOON_DIR, "lens": 42.0, "half": (63.0, 63.0), "height": 38.0},
    "cityhall": {"dir": (0.55, 0.60, -1.0), "lens": 46.0, "half": (33.0, 33.0), "height": 20.0},
    "ramp": {"dir": (0.95, 0.50, -1.0), "lens": 42.0, "half": (17.0, 17.0), "height": 12.0},
    "plaza": {"dir": (0.80, 0.55, -1.0), "lens": 42.0, "half": (15.0, 15.0), "height": 10.0},
    "point": {"dir": (0.80, 0.60, -1.0), "lens": 42.0, "half": (20.0, 20.0), "height": 14.0},
}
FIT_MARGIN = 1.04
FIT_PASSES = 8

# Scene-only drawing numbers (nothing here is a game tunable).
PAD_TINT = 1.55  # pads are the plot base this much lighter, as the in-game pad reads
PAD_ON_PAVING_TINT = 1.12  # ... or this much lighter than the pavement, when there is paving
GROUND_TINT = 0.55  # the apron outside the plot, so the plot edge is legible
PLAYER_SIZE = (2.0, 5.0, 1.0)
PLAYER_COLOR = [48, 110, 210]
SPUR_TOP = 0.1
SLAB_THICKNESS = 0.2
VEHICLES_ON_STREETS = 6
# Scatter.luau constants and paths, mirrored (geometry, not tunables).
STRAIGHT_ENOUGH = 0.9
MIN_STEP = 0.05
ASSETS_PATH = REPO_ROOT / "src" / "shared" / "Config" / "Assets.json"  # read only, never written
MIN_VEHICLE_STRETCH = 16.0
# TileRenderer.luau ground-slab constants, mirrored (geometry, not tunables).
BLOCK_DROP = 0.02  # a block slab's top, and a park strip's, sits this far under the kerb
TOUCH_EPSILON = 1e-3  # rectangles that only touch are not an overlap
# The corner squares of a cell's kerb, in the client's order: (x arm, z arm).
CORNER_PAIRS = ((1, 2), (1, 4), (3, 2), (3, 4))
HASH_MULTIPLIER = 31  # Noise.Hash
HASH_MODULUS = 16777216
FULL_CIRCLE_DEGREES = 360


def blueprint_path(era_name, model_name, prop=False):
    root = BLUEPRINTS_DIR / "_props" / era_name if prop else BLUEPRINTS_DIR / era_name
    path = root / f"{model_name}.json"
    return path if path.exists() else None


def centred_extents(size_x, size_z):
    """Scatter.centredExtents: (minX, maxX, minZ, maxZ) about the origin."""
    return (-size_x / 2, size_x / 2, -size_z / 2, size_z / 2)


def tint(color, factor):
    return [max(0, min(255, int(round(c * factor)))) for c in color]


def facing_rot(direction):
    """The rotationY whose facing() is `direction` -- facing(r) = (-sin r, -cos r)."""
    return math.degrees(math.atan2(-direction[0], -direction[1]))


def right_of(direction):
    """Roblox's right vector for a front heading, front:Cross(Vector3.yAxis), on the XZ plane."""
    return (-direction[1], direction[0])


def noise_hash(text):
    """Noise.Hash: a 31-multiplier byte hash mod 2^24, identical on every client."""
    value = 0
    for byte in text.encode("utf-8"):
        value = (value * HASH_MULTIPLIER + byte) % HASH_MODULUS
    return value


# -- ground rectangles (TileRenderer.luau: overlapping, subtract, cutAgainst) ----------------
# A rect is (x0, x1, z0, z1) in plot-local studs, x0 <= x1 and z0 <= z1. The kerb, a block's
# paving and a park strip are all cut by these three, so each covers its ground exactly once.


def overlapping(a, b):
    return (
        min(a[1], b[1]) - max(a[0], b[0]) > TOUCH_EPSILON
        and min(a[3], b[3]) - max(a[2], b[2]) > TOUCH_EPSILON
    )


def subtract(rect, cut, into):
    """`rect` minus `cut`, as up to four rectangles: the strips left of, right of, below and
    above the cut. The caller has already checked that they overlap."""

    def keep(x0, x1, z0, z1):
        if x1 - x0 > TOUCH_EPSILON and z1 - z0 > TOUCH_EPSILON:
            into.append((x0, x1, z0, z1))

    keep(rect[0], max(rect[0], cut[0]), rect[2], rect[3])
    keep(min(rect[1], cut[1]), rect[1], rect[2], rect[3])
    x0 = max(rect[0], cut[0])
    x1 = min(rect[1], cut[1])
    keep(x0, x1, rect[2], max(rect[2], cut[2]))
    keep(x0, x1, min(rect[3], cut[3]), rect[3])


def cut_against(candidate, laid, into):
    """`candidate` minus every rectangle in `laid`, appended to `into`."""
    pieces = [candidate]
    for cut in laid:
        if not pieces:
            break
        remainder = []
        for piece in pieces:
            if overlapping(piece, cut):
                subtract(piece, cut, remainder)
            else:
                remainder.append(piece)
        pieces = remainder
    into.extend(pieces)


def cell_rect(cell, step, reach):
    """The square of half-size `reach` centred on lattice cell `cell`."""
    return (
        cell[0] * step - reach,
        cell[0] * step + reach,
        cell[1] * step - reach,
        cell[1] * step + reach,
    )


# --------------------------------------------------------------------------
# Scene assembly
# --------------------------------------------------------------------------


class PlotScene:
    def __init__(self, era, network, owned, tier):
        self.era = era
        self.network = network
        self.owned = owned
        self.tier = tier
        self.boxes = []
        self.models = []
        self.rng = random.Random(f"{era.name}:plotrender")
        self.lift = float(era.city["paths"].get("buildingLift", 0.0))
        self.thickness = float(era.city["road"]["thickness"])
        self.era_config_slots = {slot["id"]: slot for slot in era.config["slots"]}
        self.visible = self.visible_stretches()
        self.notes = []
        # Set by the tile passes; empty in an era without `road.tiles`, so every later pass can
        # read them without asking which kind of era it is.
        self.planned_cells = {}  # (i, j) -> plan record, in the client's cell order
        self.planned_stretches = []
        self.drawn_order = []  # the drawn cells, in that same order (TileRenderer's `due`)
        self.tile_cells = {}
        self.tile_masks = {}
        self.pavement_rects = []  # the kerb as geometry, for the strips to cut against
        self.blocks = []
        self.block_rects = []
        self.strip_cells = set()

    # -- helpers ---------------------------------------------------------

    def box(self, name, size, pos, color, rot_y=0.0, roughness=0.9):
        self.boxes.append(
            {
                "name": name,
                "size": [round(v, 4) for v in size],
                "pos": [round(v, 4) for v in pos],
                "color": list(color),
                "rotY": round(rot_y, 4),
                "roughness": roughness,
            }
        )

    def model(self, name, path, pos, rot_y=0.0, stage=None):
        if path is None:
            self.notes.append(f"no blueprint for {name} (nothing drawn)")
            return
        entry = {"name": name, "blueprint": str(path), "pos": [round(v, 4) for v in pos], "rotY": round(rot_y, 4)}
        if stage is not None:
            entry["stage"] = stage
        self.models.append(entry)

    def ribbon(self, name, a, b, width, top, color, cap=True):
        """A flat slab along a-b, overlapped by half a width at each end so corners close -- the
        same trick TileRenderer's kerbs use, and the reason a footpath bend has no notch."""
        length = math.dist(a, b)
        if length < 0.05:
            return
        along = ((b[0] - a[0]) / length, (b[1] - a[1]) / length)
        mid = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
        run = length + (width if cap else 0.0)
        self.box(
            name,
            (width, SLAB_THICKNESS, run),
            (mid[0], top - SLAB_THICKNESS / 2, mid[1]),
            color,
            # A part's local Z is its length; rotationY 0 runs along -Z, so turn the slab to `along`.
            rot_y=facing_rot(along),
        )

    # -- visibility ------------------------------------------------------

    def visible_stretches(self):
        """The stretch ids the client would have drawn: the union of the shortest paths from the
        plot entrance to each owned building's join point (wave 1b), exactly as RoadGraph does."""
        visible = set()
        unreachable = []
        for slot_id in self.network.spur_ids:
            if slot_id not in self.owned:
                continue
            node = self.network.junction_nodes.get(slot_id)
            ids = self.network.path_stretches(node)
            if ids is None:
                unreachable.append(slot_id)
                continue
            visible.update(ids)
        self.unreachable = unreachable
        return visible

    # -- the plot itself -------------------------------------------------

    def build_ground(self):
        era = self.era
        base = era.layout["baseColor"]
        base_rgb = [int(v) if max(base) > 1 else int(v * 255) for v in base]
        plot = era.layout["plotSize"]
        self.base_rgb = base_rgb
        # An apron of the same colour, darkened: the plot edge stays legible without a white card.
        self.box("Apron", (plot[0] * 4, 2.0, plot[2] * 4), (0.0, -1.2, 0.0), tint(base_rgb, GROUND_TINT))
        self.box("PlotBase", (plot[0], plot[1], plot[2]), (0.0, -plot[1] / 2, 0.0), base_rgb)

    def build_pads(self):
        era = self.era
        pad = era.layout["padSize"]
        # Brighter than whatever the pad stands on. Against bare plot base that is the base itself;
        # on an era with pavement and paved blocks a tint of the base would be *darker* than the
        # paving around it and the pads would read as potholes.
        surround = ((era.tiles or {}).get("pavement") or {}).get("color")
        colour = tint(self.base_rgb, PAD_TINT)
        if surround is not None:
            bright = tint([int(v) for v in surround], PAD_ON_PAVING_TINT)
            if sum(bright) > sum(colour):
                colour = bright
        for slot in era.slots:
            if slot["id"] not in self.owned:
                continue
            self.box(
                f"Pad_{slot['id']}",
                (era.pad_size[0], pad[1], era.pad_size[1]),
                (slot["pad"][0], pad[1] / 2, slot["pad"][1]),
                colour,
                rot_y=slot["rotation"],
            )

    def build_buildings(self):
        era = self.era
        for slot in era.slots:
            if slot["id"] not in self.owned:
                continue
            config = self.era_config_slots.get(slot["id"], {})
            if config.get("streetOnly"):
                continue  # the server spawns an empty marker: no model, only the pad is real
            path = blueprint_path(era.name, config.get("modelName", ""))
            self.model(
                slot["id"],
                path,
                (slot["position"][0], self.lift, slot["position"][1]),
                rot_y=slot["rotation"],
            )

    def build_lots(self):
        """Filler houses: the client picks one of `houses.props` per lot from the plot seed; the
        render picks from its own seed, because which house stands where is not what is judged."""
        era = self.era
        props = era.dressing.get("houses", {}).get("props") or []
        if not props:
            return
        for index, lot in enumerate(era.lots):
            if lot["tier"] > self.tier:
                continue
            name = props[self.rng.randrange(len(props))]
            self.model(
                f"House{index}",
                blueprint_path(era.name, name, prop=True),
                (lot["position"][0], 0.0, lot["position"][1]),
                rot_y=lot["rotation"],
            )

    # -- streets ---------------------------------------------------------

    def ranked_stretches(self):
        """Stretches ranked nearest-the-entrance first, ties by id: the order the controller hands
        TileRenderer.Plan, and therefore the order the cell budget is spent in."""
        order = []
        for stretch_id in range(len(self.network.stretches)):
            distance = self.network.near_distance(stretch_id)
            if distance is not None:
                order.append((distance, stretch_id))
        order.sort()
        return [stretch_id for _, stretch_id in order]

    def plan_cells(self):
        """TileRenderer.Plan: rasterise every plannable stretch onto the lattice, nearest first,
        stopping at the first stretch whose fresh cells do not fit budget.tileCells."""
        era = self.era
        step = era.tile_studs
        cells = {}  # (i, j) -> {"stretches": set, "links": {arm: set}}
        remaining = int(self.era.city.get("budget", {}).get("tileCells", 0))
        planned = []
        for stretch_id in self.ranked_stretches():
            stretch = self.network.stretches[stretch_id]
            path = rasterise(step, stretch["a"], stretch["b"])
            fresh = sum(1 for cell in path if cell not in cells)
            if fresh > remaining:
                self.notes.append(f"tile budget exhausted at stretch {stretch_id}; the plan is truncated")
                break
            remaining -= fresh
            for cell in path:
                record = cells.setdefault(cell, {"stretches": set(), "links": {}})
                record["stretches"].add(stretch_id)
            for index in range(1, len(path)):
                delta = (path[index][0] - path[index - 1][0], path[index][1] - path[index - 1][1])
                arm = arm_for(delta)
                if arm is None:
                    continue
                cells[path[index - 1]]["links"].setdefault(arm, set()).add(stretch_id)
                cells[path[index]]["links"].setdefault(opposite_arm(arm), set()).add(stretch_id)
            planned.append(stretch_id)
        return cells, planned

    def build_tile_streets(self):
        era = self.era
        step = era.tile_studs
        props = era.tiles["props"]
        cells, planned = self.plan_cells()
        drawn = {cell: record for cell, record in cells.items() if record["stretches"] & self.visible}
        masks, kinds, quarters = {}, {}, {}
        for cell, record in drawn.items():
            mask = 0
            for arm, ids in record["links"].items():
                neighbour = step_cell(cell, arm)
                if neighbour not in cells or not (ids & self.visible):
                    continue
                mask |= 1 << (arm - 1)
            masks[cell] = mask
            kinds[cell], quarters[cell] = PIECE_BY_MASK[mask & 15]

        crossings = set()
        if props.get("crossing"):
            for cell in drawn:
                if kinds[cell] != "straight":
                    continue
                for arm in range(1, 5):
                    if not masks[cell] & (1 << (arm - 1)):
                        continue
                    neighbour = step_cell(cell, arm)
                    if kinds.get(neighbour) not in ("tee", "cross"):
                        continue
                    if run_cells(kinds, masks, cell, opposite_arm(arm)) >= CROSSING_MIN_RUN:
                        crossings.add(cell)
                        break

        for cell in sorted(drawn):
            kind = "crossing" if cell in crossings else kinds[cell]
            self.model(
                f"Tile{cell[0]}_{cell[1]}",
                blueprint_path(era.name, props.get(kind, ""), prop=True),
                (cell[0] * step, 0.0, cell[1] * step),
                rot_y=quarters[cell] * 90.0,
            )
        self.planned_cells = cells
        self.planned_stretches = planned
        self.tile_cells = drawn
        self.tile_masks = masks
        # TileRenderer's `due`: the drawn cells in plan order, which is the order the kerb and the
        # park strips cut in. `sorted(drawn)` above only orders what the render draws over nothing.
        self.drawn_order = [cell for cell in cells if cell in drawn]
        self.notes.append(f"{len(drawn)} tile cells drawn of {len(cells)} planned ({len(planned)} stretches)")

    def build_pavements(self):
        """TileRenderer.cellSlabs + syncPavement, restated. Pavement PER CELL, never over asphalt:
        a `pavement.width` band flush against every side of a drawn cell the asphalt does not leave,
        plus a width x width square at each corner whose two adjacent arms are both closed. A
        crossroads therefore gets no pavement at all and a street end gets a U, and nothing has to
        overlap a junction the way the old per-stretch kerbs did.

        A band that would lie over any *planned* cell's tile is dropped whole -- a cell that
        arrives later must not find a kerb sitting on its asphalt -- and then each cell in turn
        subtracts what is already laid from its own rectangles, so the ground is covered exactly
        once. The order is the cell order, which is the plan order, so every client cuts the same
        shapes and so does this tool."""
        era = self.era
        pavement = era.tiles.get("pavement")
        if pavement is None:
            return
        width = max(float(pavement["width"]), MIN_STEP)
        colour = [int(v) for v in pavement["color"]]
        step = era.tile_studs
        half = step / 2
        laid = self.pavement_rects
        for cell in self.drawn_order:
            mask = self.tile_masks[cell]
            centre_x, centre_z = cell[0] * step, cell[1] * step
            candidates = []

            def add(x0, x1, z0, z1):
                rect = (min(x0, x1), max(x0, x1), min(z0, z1), max(z0, z1))
                if not self.overlaps_tile(rect):
                    candidates.append(rect)

            for arm in range(1, 5):
                if mask & (1 << (arm - 1)):
                    continue  # the asphalt leaves the tile on this side
                delta = ARM_STEPS[arm - 1]
                out_x = delta[0] * (half + width) if delta[0] else half
                out_z = delta[1] * (half + width) if delta[1] else half
                add(
                    centre_x + (delta[0] * half if delta[0] else -out_x),
                    centre_x + out_x,
                    centre_z + (delta[1] * half if delta[1] else -out_z),
                    centre_z + out_z,
                )
            # Corners: the two arms either side of the diagonal must both be missing, or the corner
            # square would stick out into a road that turns there.
            for x_arm, z_arm in CORNER_PAIRS:
                if mask & (1 << (x_arm - 1)) or mask & (1 << (z_arm - 1)):
                    continue
                offset_x = ARM_STEPS[x_arm - 1][0] + ARM_STEPS[z_arm - 1][0]
                offset_z = ARM_STEPS[x_arm - 1][1] + ARM_STEPS[z_arm - 1][1]
                add(
                    centre_x + offset_x * half,
                    centre_x + offset_x * (half + width),
                    centre_z + offset_z * half,
                    centre_z + offset_z * (half + width),
                )
            for candidate in candidates:
                kept = []
                cut_against(candidate, laid, kept)
                laid.extend(kept)
        for index, rect in enumerate(laid):
            self.box(
                f"Pavement{index}",
                (rect[1] - rect[0], self.thickness, rect[3] - rect[2]),
                ((rect[0] + rect[1]) / 2, 0.0, (rect[2] + rect[3]) / 2),
                colour,
            )
        self.notes.append(f"{len(laid)} pavement slabs")

    def overlaps_tile(self, rect):
        """TileRenderer.overlapsTile: whether a rectangle lies over any *planned* cell's tile.
        Planned, not drawn -- see build_pavements."""
        step = self.era.tile_studs
        half = step / 2
        from_i = math.floor((rect[0] - half) / step)
        to_i = math.ceil((rect[1] + half) / step)
        from_j = math.floor((rect[2] - half) / step)
        to_j = math.ceil((rect[3] + half) / step)
        for i in range(from_i, to_i + 1):
            for j in range(from_j, to_j + 1):
                if (i, j) not in self.planned_cells:
                    continue
                if overlapping(rect, cell_rect((i, j), step, half)):
                    return True
        return False

    def build_plain_streets(self):
        """A non-tile era (Boomtown, Village): the spine as plain slabs of road.width. The shipped
        client draws baked mesh pieces there; this is deliberately the plain stand-in, because the
        bake is judged by tools/paths and this render is about the plot reading as a place."""
        era = self.era
        colour = [int(v) for v in era.dressing["road"]["color"]]
        for stretch_id in sorted(self.visible):
            stretch = self.network.stretches[stretch_id]
            self.ribbon(f"Road{stretch_id}", stretch["a"], stretch["b"], era.width, self.thickness / 2, colour)

    def build_spurs(self):
        """The footpath from the pad's kerb to the slot anchor. A tiles era gives it its own look
        (`tiles.spur`); elsewhere it is the road itself, which is what the baked spur bakes."""
        era = self.era
        spur_cfg = (era.tiles or {}).get("spur")
        width = float(spur_cfg["width"]) if spur_cfg else era.width
        colour = [int(v) for v in (spur_cfg["color"] if spur_cfg else era.dressing["road"]["color"])]
        for slot in era.slots:
            spur = era.spurs[slot["id"]]
            if slot["id"] not in self.owned or not spur["points"]:
                continue
            for index, (a, b) in enumerate(streetplan.polyline_segments(spur["points"])):
                self.ribbon(f"Spur_{slot['id']}_{index}", a, b, width, SPUR_TOP, colour)

    # -- highway, subway, dressing ---------------------------------------

    def build_highway(self):
        era = self.era
        highway = era.highway
        config = era.dressing.get("highway")
        if highway is None or config is None or era.tile_studs <= 0:
            return
        if config.get("requiresSlot") and config["requiresSlot"] not in self.owned:
            return
        step = era.tile_studs
        half = int(round(float(highway["ring"]) / step))
        if half < 1:
            return
        cycle = ring_cycle(half)
        ramp = highway["ramp"]
        requested = streetplan.xz(ramp["cell"])
        junction_index = min(
            range(len(cycle)),
            key=lambda i: math.dist((cycle[i][0] * step, cycle[i][1] * step), requested),
        )
        direction = RAMP_DIRECTIONS.get(ramp["direction"])
        junction = cycle[junction_index]
        if direction is None:
            inward = (-junction[0], -junction[1])
            direction = max(RAMP_DIRECTIONS.values(), key=lambda d: d[0] * inward[0] + d[1] * inward[1])
        props = config["props"]
        count = len(cycle)
        for index, cell in enumerate(cycle):
            previous = cycle[(index - 1) % count]
            following = cycle[(index + 1) % count]
            mask = 0
            for neighbour in (previous, following):
                arm = arm_for((neighbour[0] - cell[0], neighbour[1] - cell[1]))
                if arm is not None:
                    mask |= 1 << (arm - 1)
            if index == junction_index:
                arm = arm_for((int(direction[0]), int(direction[1])))
                if arm is not None:
                    mask |= 1 << (arm - 1)
            kind, quarters = PIECE_BY_MASK[mask & 15]
            name = props["deck"] if kind == "straight" else props["corner"] if kind == "bend" else props["junction"]
            self.model(
                f"Ring{cell[0]}_{cell[1]}",
                blueprint_path(era.name, name, prop=True),
                (cell[0] * step, 0.0, cell[1] * step),
                rot_y=quarters * 90.0,
            )

        # The ramp: its highest cell is the first cell INWARD of the junction, so the prop's three
        # cells are exactly the cells streetplan checks and its toe lands on the street's end cell
        # (INTERFACES "Elevated highway"). Placing the origin at the junction cell's inner edge --
        # what the client does today -- would sit the whole ramp half a cell off the lattice.
        origin = (junction[0] * step + direction[0] * step, junction[1] * step + direction[1] * step)
        ramp_arm = arm_for((int(direction[0]), int(direction[1]))) or 1
        self.ramp_origin = origin
        self.model(
            "HighwayRamp",
            blueprint_path(era.name, props["ramp"], prop=True),
            (origin[0], 0.0, origin[1]),
            rot_y=(ramp_arm - 1) * 90.0,
        )
        self.build_deck_cars(half * step, config)

    def build_deck_cars(self, ring, config):
        era = self.era
        vehicles = config.get("vehicles") or {}
        height = config.get("deckHeight")
        props = era.dressing.get("vehicles", {}).get("props") or []
        if height is None or not props:
            return
        lane = era.width * float(era.dressing["road"].get("laneOffsetFraction", era.city["road"]["laneOffsetFraction"]))
        # One car each way, on the two long legs, on the right of its own travel direction.
        runs = (((0.0, -ring), (1.0, 0.0)), ((0.0, ring), (-1.0, 0.0)))
        for index in range(min(int(vehicles.get("count", 2)), len(runs))):
            centre, heading = runs[index]
            right = right_of(heading)
            along = (index * 2 - 1) * ring * 0.35
            position = (
                centre[0] + heading[0] * along + right[0] * lane,
                centre[1] + heading[1] * along + right[1] * lane,
            )
            self.model(
                f"DeckCar{index}",
                blueprint_path(era.name, props[index % len(props)], prop=True),
                (position[0], float(height), position[1]),
                rot_y=facing_rot(heading),
            )

    def build_subway(self):
        era = self.era
        config = era.dressing.get("subway")
        if not config or not era.subways:
            return
        if config.get("requiresSlot") and config["requiresSlot"] not in self.owned:
            return
        path = blueprint_path(era.name, config["prop"], prop=True)
        entrance = era.streets[0][0] if era.streets else (0.0, -era.half_z)
        nearest_index = min(
            range(len(era.subways)), key=lambda i: math.dist(era.subways[i]["position"], entrance)
        )
        for index, entry in enumerate(era.subways[: int(config.get("maxPerPlot", len(era.subways)))]):
            # Each kiosk is tied to its nearest stretch and waits for it, except the one by the
            # plot entrance, which buying the slot always shows.
            if index != nearest_index and not self.stretch_visible_near(entry["position"]):
                continue
            self.model(f"Metro{index}", path, (entry["position"][0], 0.0, entry["position"][1]), rot_y=entry["rotation"])

    def stretch_visible_near(self, point):
        best, best_id = math.inf, None
        for stretch_id, stretch in enumerate(self.network.stretches):
            distance = streetplan.point_segment_distance(point, stretch["a"], stretch["b"])[0]
            if distance < best:
                best, best_id = distance, stretch_id
        return best_id in self.visible

    def build_plazas(self):
        era = self.era
        for index, plaza in enumerate(era.plazas):
            if plaza["tier"] > self.tier:
                continue
            self.model(
                f"Plaza{index}",
                blueprint_path(era.name, plaza["prop"], prop=True),
                (plaza["position"][0], 0.0, plaza["position"][1]),
                rot_y=plaza["rotation"],
            )

    # -- paved blocks and street trees ------------------------------------

    def build_blocks(self):
        """INTERFACES "Paved blocks": one slab per layout `blocks` rect, shown when any of its
        `slots` is owned, top at road.thickness / 2 - 0.02 so it never shares a plane with the
        pavement or a pad. No layout table means no slabs, which is today's behaviour."""
        era = self.era
        config = (era.tiles or {}).get("blocks")
        blocks = era.layout.get("blocks") or []
        if config is None or not blocks:
            if blocks and config is None:
                self.notes.append("layout has blocks but road.tiles.blocks config is absent")
            return
        colour = [int(v) for v in config["color"]]
        top = self.thickness / 2 - 0.02
        for index, block in enumerate(blocks):
            slots = block.get("slots") or []
            if slots and not (set(slots) & self.owned):
                continue
            low, high = streetplan.xz(block["min"]), streetplan.xz(block["max"])
            size = (abs(high[0] - low[0]), abs(high[1] - low[1]))
            if min(size) < 0.05:
                continue
            centre = ((low[0] + high[0]) / 2, (low[1] + high[1]) / 2)
            self.box(
                f"Block{index}",
                (size[0], SLAB_THICKNESS, size[1]),
                (centre[0], top - SLAB_THICKNESS / 2, centre[1]),
                colour,
            )
            self.blocks.append({"min": (min(low[0], high[0]), min(low[1], high[1])),
                                "max": (max(low[0], high[0]), max(low[1], high[1]))})
            self.block_rects.append((
                min(low[0], high[0]), max(low[0], high[0]),
                min(low[1], high[1]), max(low[1], high[1]),
            ))
        self.notes.append(f"{len(self.blocks)} paved blocks of {len(blocks)} in the layout")

    def build_park_strips(self):
        """TileRenderer.syncStrips, restated (INTERFACES "Park strips in undrawn corridors"): a
        planned cell whose street has not grown yet is planted rather than left as bare ground
        beside a dead-end sidewalk. The strip covers the cell and its pavement band, minus
        everything already laid -- the tiles drawn so far, the kerb around them, the strips of the
        cells before it in the plan, and the paved blocks, whose top it shares.

        Tiles and strips share `budget.tileCells`; a cut band can need more than one Part, so the
        ceiling is spent in Parts, in cell order (entrance outward), not counted in cells."""
        era = self.era
        config = (era.tiles or {}).get("parkStrips")
        if config is None:
            return
        step = era.tile_studs
        pavement = era.tiles.get("pavement")
        reach = step / 2 + (max(float(pavement["width"]), 0.0) if pavement is not None else 0.0)
        colour = [int(v) for v in config["color"]]
        top = self.thickness / 2 - BLOCK_DROP
        laid = []
        drawn_count = 0
        for cell in self.planned_cells:
            if cell in self.tile_cells:
                drawn_count += 1
                laid.append(cell_rect(cell, step, step / 2))
        # The client's `laid` takes the kerb and the block slabs out of two hash tables, whose order
        # it does not control; every rectangle in both is disjoint from the others, so the ground a
        # strip is left with is the same however they are ordered.
        laid.extend(self.pavement_rects)
        laid.extend(self.block_rects)
        remaining = max(int(era.city.get("budget", {}).get("tileCells", 0)) - drawn_count, 0)
        pieces = []
        for cell in self.planned_cells:
            if cell in self.tile_cells or remaining <= 0:
                continue
            kept = []
            cut_against(cell_rect(cell, step, reach), laid, kept)
            for piece in kept:
                if remaining <= 0:
                    break
                remaining -= 1
                laid.append(piece)
                pieces.append(piece)
                self.strip_cells.add(cell)
        for index, rect in enumerate(pieces):
            self.box(
                f"ParkStrip{index}",
                (rect[1] - rect[0], SLAB_THICKNESS, rect[3] - rect[2]),
                ((rect[0] + rect[1]) / 2, top - SLAB_THICKNESS / 2, (rect[2] + rect[3]) / 2),
                colour,
            )
        undrawn = len(self.planned_cells) - drawn_count
        self.notes.append(
            f"{len(pieces)} park-strip slabs over {len(self.strip_cells)} of {undrawn} undrawn cells"
        )

    def street_lines(self):
        """RoadGraph.StreetLines, restated: every *plannable* spine piece as a centreline, grouped
        into continuous runs along each polyline (a piece outside the plan breaks the run), plus
        every allowed spur's centreline. Nothing here depends on what is owned or drawn."""
        era, network = self.era, self.network
        planned = set(self.planned_stretches)
        # Baked piece ids: the n-th stretch of a polyline in creation order, exactly as RoadGraph
        # numbers them, so a planter can be ordered by (polyline, stretch) rather than by a string
        # in which "L1_10" sorts before "L1_2".
        ordinals, per_polyline = {}, {}
        for stretch_id, stretch in enumerate(network.stretches):
            ordinal = per_polyline.get(stretch["polyline"], 0) + 1
            per_polyline[stretch["polyline"]] = ordinal
            ordinals[stretch_id] = ordinal
        if era.meander is not None:
            self.notes.append("meandering tiles era: street lines are drawn straight here")
        segment_groups = sum(max(len(street) - 1, 0) for street in era.streets)
        runs, open_runs = [], {}
        for group_index, stretch_ids in enumerate(network.groups):
            for stretch_id in stretch_ids:
                stretch = network.stretches[stretch_id]
                polyline = stretch["polyline"]
                if stretch_id not in planned:
                    open_runs.pop(polyline, None)  # a piece outside the plan breaks the street
                    continue
                # A connector is a short link onto another polyline, not a continuation of one.
                continues = group_index < segment_groups
                run = open_runs.get(polyline) if continues else None
                if run is None:
                    run = {"polyline": polyline, "pieces": []}
                    runs.append(run)
                    if continues:
                        open_runs[polyline] = run
                run["pieces"].append(
                    {"stretch": ordinals[stretch_id], "points": [stretch["a"], stretch["b"]]}
                )
        _groups_allowed, spurs_allowed = network.straight_allocate()
        spurs = [era.spurs[slot_id]["points"] for slot_id in spurs_allowed]
        return runs, spurs

    def park_strip_trees(self):
        """Scatter.parkStripTrees, restated: a planter every `parkStrips.treeSpacing` studs down
        the centreline of every street the plot can ever draw, the marks measured from each piece's
        own start and the step counted whether or not the spot is taken. A spot inside any
        footprint (by `blocks.treeClearance`) or on any allowed spur is dropped; the rest are
        ordered (polyline, stretch, step) and thinned evenly to `parkStrips.maxTrees`."""
        era = self.era
        config = (era.tiles or {}).get("parkStrips")
        if config is None or not era.dressing.get("trees", {}).get("prop"):
            return []
        spacing = config.get("treeSpacing")
        if not isinstance(spacing, (int, float)) or spacing < MIN_STEP:
            return []
        # A planter keeps the daylight a street tree keeps from the same solids; an era that plants
        # strips without paving blocks simply has no such distance to keep.
        blocks = (era.tiles or {}).get("blocks")
        clearance = max(float(blocks["treeClearance"]), 0.0) if blocks is not None else 0.0
        spur_half = max(float(era.tiles["spur"]["width"]), 0.0) / 2 + clearance
        footprints = self.footprints_for()
        runs, spurs = self.street_lines()
        spur_segments = [seg for spur in spurs for seg in streetplan.polyline_segments(spur)]

        def blocked(point):
            if any(self.inside_footprint(f, point, clearance) for f in footprints):
                return True
            # The footpath to a building crosses the corridor it serves.
            return any(
                streetplan.point_segment_distance(point, a, b)[0] <= spur_half
                for a, b in spur_segments
            )

        trees = []
        for run in runs:
            for piece in run["pieces"]:
                walked, step_index = 0.0, 0
                for index in range(1, len(piece["points"])):
                    start = piece["points"][index - 1]
                    finish = piece["points"][index]
                    span = (finish[0] - start[0], finish[1] - start[1])
                    length = math.hypot(span[0], span[1])
                    if length < MIN_STEP:
                        continue
                    mark = (step_index + 1) * spacing
                    while mark <= walked + length:
                        step_index += 1
                        fraction = (mark - walked) / length
                        point = (start[0] + span[0] * fraction, start[1] + span[1] * fraction)
                        if not blocked(point):
                            key = "{}:{}:{}".format(run["polyline"], piece["stretch"], step_index)
                            trees.append(
                                {
                                    "polyline": run["polyline"],
                                    "stretch": piece["stretch"],
                                    "step": step_index,
                                    "position": point,
                                    # Hashed, not drawn: the same planter turns the same way
                                    # on every client.
                                    "yaw": noise_hash(key) % FULL_CIRCLE_DEGREES,
                                }
                            )
                        mark = (step_index + 1) * spacing
                    walked += length
        trees.sort(key=lambda tree: (tree["polyline"], tree["stretch"], tree["step"]))
        cap = max(int(math.floor(config.get("maxTrees", 0))), 0)
        count = len(trees)
        if count <= cap:
            return trees
        # Scatter's even thinning, the same integer test the row lamps use.
        return [
            tree
            for index, tree in enumerate(trees, start=1)
            if (index * cap) // count != ((index - 1) * cap) // count
        ]

    def build_park_trees(self):
        """CityDressingController.syncParkTrees: a planter stands only while the cell under it is
        still carrying a strip (TileRenderer.StripAt), at the fixed `parkStrips.treeStage`."""
        era = self.era
        config = (era.tiles or {}).get("parkStrips")
        if config is None:
            return
        prop = era.dressing.get("trees", {}).get("prop")
        path = blueprint_path(era.name, prop, prop=True)
        stage = max(int(math.floor(config.get("treeStage", 0))), 0)
        step = era.tile_studs
        planned = self.park_strip_trees()
        shown = 0
        for index, tree in enumerate(planned):
            if cell_at(step, tree["position"]) not in self.strip_cells:
                continue
            shown += 1
            self.model(
                f"ParkTree{index}",
                path,
                (tree["position"][0], 0.0, tree["position"][1]),
                rot_y=tree["yaw"],
                stage=stage,
            )
        self.notes.append(f"park planters: {shown} standing of {len(planned)} planned")

    # Scatter.luau's footprintsFor, mirrored: every rectangle a street tree may not stand in,
    # measured from the harvested parts in Assets.json (which every client reads identically), not
    # from the blueprint `footprint` key. A slot with nothing harvested stands as the layout's
    # placeholderSize, exactly as the client assumes.
    def model_extents(self, model_name, prop=False):
        if model_name is None:
            return None
        try:
            assets = json.loads(ASSETS_PATH.read_text(encoding="utf-8"))
            table = assets["props"][self.era.name] if prop else assets["eras"][self.era.name]
            stages = table[model_name]["stages"]
        except (OSError, ValueError, KeyError, TypeError):
            return None
        low_x = low_z = math.inf
        high_x = high_z = -math.inf
        for stage in stages:
            for part in stage.get("parts") or []:
                offset, size, mesh = part.get("offset"), part.get("size"), part.get("meshId")
                if not offset or not size or not isinstance(mesh, (int, float)) or mesh <= 0:
                    continue
                # Harvested offsets are in the template frame, whose X and Z run opposite the plot
                # frame; Scatter negates them, so an off-centre model leans the same way here.
                centre_x, centre_z = -offset[0], -offset[2]
                low_x = min(low_x, centre_x - size[0] / 2)
                high_x = max(high_x, centre_x + size[0] / 2)
                low_z = min(low_z, centre_z - size[2] / 2)
                high_z = max(high_z, centre_z + size[2] / 2)
        return None if low_x > high_x else (low_x, high_x, low_z, high_z)

    def footprints_for(self):
        era = self.era
        layout = era.layout
        placeholder = layout["placeholderSize"]
        pad = layout["padSize"]
        names = {slot["id"]: slot.get("modelName") for slot in era.config["slots"]}
        footprints = []
        largest_x, largest_z = placeholder[0], placeholder[2]
        slot_extents = {}
        for slot_id in layout["slots"]:
            extents = self.model_extents(names.get(slot_id)) or centred_extents(placeholder[0], placeholder[2])
            slot_extents[slot_id] = extents
            largest_x = max(largest_x, extents[1] - extents[0])
            largest_z = max(largest_z, extents[3] - extents[2])

        def prop_extents(name):
            return self.model_extents(name, prop=True) or centred_extents(largest_x, largest_z)

        for slot in era.slots:
            # Every layout slot counts, streetOnly included: the client walks layout.slots, not the
            # era config's buildings.
            footprints.append((slot["position"], slot["rotation"], slot_extents[slot["id"]]))
            # Pads are placed unrotated in the plot frame (PlotService.padWorldCFrame).
            footprints.append((slot["pad"], 0.0, centred_extents(pad[0], pad[2])))
        houses = era.dressing.get("houses", {}).get("props") or []
        lot_extents = prop_extents(None)
        if houses:
            lot_extents = prop_extents(houses[0])
            for name in houses[1:]:
                other = prop_extents(name)
                lot_extents = (
                    min(lot_extents[0], other[0]), max(lot_extents[1], other[1]),
                    min(lot_extents[2], other[2]), max(lot_extents[3], other[3]),
                )
        for lot in era.lots:
            footprints.append((lot["position"], lot["rotation"], lot_extents))
        for plaza in era.plazas:
            footprints.append((plaza["position"], plaza["rotation"], prop_extents(plaza["prop"])))
        subway = era.dressing.get("subway")
        if subway is not None and era.subways:
            extents = self.model_extents(subway["prop"], prop=True) or centred_extents(placeholder[0], placeholder[2])
            for entry in era.subways:
                footprints.append((entry["position"], entry["rotation"], extents))
        return footprints

    @staticmethod
    def inside_footprint(footprint, point, margin=0.0):
        origin, rotation, extents = footprint
        radians = math.radians(rotation)
        dx, dz = point[0] - origin[0], point[1] - origin[1]
        # CFrame.Angles(0, r, 0):PointToObjectSpace, on the XZ plane.
        local_x = dx * math.cos(radians) - dz * math.sin(radians)
        local_z = dx * math.sin(radians) + dz * math.cos(radians)
        return (
            extents[0] - margin <= local_x <= extents[1] + margin
            and extents[2] - margin <= local_z <= extents[3] + margin
        )

    def nearest_piece(self, point):
        """Scatter's nearestPiece over the drawable spine pieces: the distance to the nearest one
        and that piece's own direction. The tool's pieces are the visible stretches, which is what
        RoadGraph hands the client as StreetLines."""
        best, along = math.inf, None
        for stretch_id in self.visible:
            stretch = self.network.stretches[stretch_id]
            distance, _ = streetplan.point_segment_distance(point, stretch["a"], stretch["b"])
            if distance < best:
                best = distance
                along = (stretch["b"][0] - stretch["a"][0], stretch["b"][1] - stretch["a"][1])
        return best, along

    def street_trees(self):
        """Scatter.streetTreeSpots, restated: every block is planned (the block-owned gate is at
        spawn time, so it must not change the order or the cap); edges in the fixed order
        -Z, +X, +Z, -X; steps 1..floor(length / spacing) from the edge's start corner, never
        centred; an edge qualifies when the nearest drawable spine piece to its inset midpoint is
        within roadWidth / 2 + 2 * pavement.width + treeClearance AND runs parallel to it; a spot
        is blocked by any footprint within `treeClearance` or any drawn spur.

        Returns (point, block index) so the caller can apply the spawn-time gate."""
        era = self.era
        config = (era.tiles or {}).get("blocks")
        blocks = era.layout.get("blocks") or []
        if config is None or not blocks or not era.dressing.get("trees", {}).get("prop"):
            return []
        spacing = config.get("treeSpacing")
        if not isinstance(spacing, (int, float)) or spacing < MIN_STEP:
            return []
        clearance = max(float(config.get("treeClearance", 0)), 0.0)
        inset = max(float(config.get("treeInset", 0)), 0.0)
        spur_cfg = (era.tiles or {}).get("spur")
        spur_half = (float(spur_cfg["width"]) if spur_cfg else era.width) / 2 + clearance
        reach = era.width / 2 + 2 * era.pavement + clearance
        footprints = self.footprints_for()
        spurs = []
        for slot in era.slots:
            spur = era.spurs[slot["id"]]
            if slot["id"] in self.owned and spur["points"]:
                spurs += streetplan.polyline_segments(spur["points"])

        def blocked(point):
            if any(self.inside_footprint(f, point, clearance) for f in footprints):
                return True
            return any(streetplan.point_segment_distance(point, a, b)[0] <= spur_half for a, b in spurs)

        spots = []
        for block_index, block in enumerate(blocks):
            low, high = streetplan.xz(block["min"]), streetplan.xz(block["max"])
            min_x, max_x = min(low[0], high[0]), max(low[0], high[0])
            min_z, max_z = min(low[1], high[1]), max(low[1], high[1])
            edges = (
                ((min_x, min_z), (max_x, min_z), (0.0, 1.0)),
                ((max_x, min_z), (max_x, max_z), (-1.0, 0.0)),
                ((min_x, max_z), (max_x, max_z), (0.0, -1.0)),
                ((min_x, min_z), (min_x, max_z), (1.0, 0.0)),
            )
            for begin, finish, inward in edges:
                span = (finish[0] - begin[0], finish[1] - begin[1])
                length = math.hypot(span[0], span[1])
                if length < spacing:
                    continue
                along = (span[0] / length, span[1] / length)
                midpoint = (
                    (begin[0] + finish[0]) / 2 + inward[0] * inset,
                    (begin[1] + finish[1]) / 2 + inward[1] * inset,
                )
                distance, direction = self.nearest_piece(midpoint)
                unit = streetplan.unit(direction) if direction is not None else None
                parallel = unit is not None and abs(unit[0] * along[0] + unit[1] * along[1]) > STRAIGHT_ENOUGH
                if distance > reach or not parallel:
                    continue
                for step in range(1, int(length // spacing) + 1):
                    point = (
                        begin[0] + along[0] * spacing * step + inward[0] * inset,
                        begin[1] + along[1] * spacing * step + inward[1] * inset,
                    )
                    # A spot with no piece beside it is dropped; with no visible stretch at all
                    # there is no street to line.
                    if blocked(point) or self.nearest_piece(point)[1] is None:
                        continue
                    spots.append((point, block_index))
        return spots

    def build_trees(self):
        era = self.era
        prop = era.dressing.get("trees", {}).get("prop")
        if not prop:
            return
        path = blueprint_path(era.name, prop, prop=True)
        # Scatter.Plan's cap: the era's maxCount, never more than budget.trees.
        cap = min(max(int(era.dressing["trees"].get("maxCount", 0)), 0), int(era.city["budget"]["trees"]))
        street = self.street_trees()
        count = len(street)
        if count > cap:
            # Scatter's even thinning, the same integer test the row lamps use.
            street = [
                spot
                for index, spot in enumerate(street, start=1)
                if (index * cap) // count != ((index - 1) * cap) // count
            ]
            self.notes.append("street trees thinned " + str(count) + " -> " + str(len(street)))
        # The spawn-time gate (CityDressingController.blockPaved): a planned tree waits for its own
        # block to be owned. It runs after the cap, so an unowned block costs its trees, not others.
        blocks = era.layout.get("blocks") or []
        shown = []
        for point, block_index in street:
            slots = (blocks[block_index].get("slots") or []) if block_index < len(blocks) else []
            if slots and not (set(slots) & self.owned):
                continue
            shown.append(point)
        zone, _ = streetplan.scatter_trees(era)
        zone = zone[: max(cap - len(street), 0)]
        for index, point in enumerate(shown + zone):
            self.model("Tree" + str(index), path, (point[0], 0.0, point[1]), rot_y=self.rng.randrange(4) * 90.0)
        if self.blocks:
            self.notes.append(
                "trees: " + str(len(shown)) + " street (planned " + str(len(street)) + ") + "
                + str(len(zone)) + " zone (cap " + str(cap) + ")"
            )

    def build_street_vehicles(self):
        """Cars on the longest visible stretches, on the right of their travel direction (Traffic's
        lane graph is the centreline offset by laneOffsetFraction * width to the right)."""
        era = self.era
        props = era.dressing.get("vehicles", {}).get("props") or []
        if not props or not self.visible:
            return
        lane = era.width * float(era.dressing["road"].get("laneOffsetFraction", era.city["road"]["laneOffsetFraction"]))
        candidates = sorted(
            (self.network.stretches[i] for i in self.visible if self.network.stretches[i]["length"] >= MIN_VEHICLE_STRETCH),
            key=lambda s: -s["length"],
        )
        count = min(int(era.dressing["vehicles"].get("perPlot", VEHICLES_ON_STREETS)), len(candidates))
        for index in range(count):
            stretch = candidates[index]
            a, b = stretch["a"], stretch["b"]
            length = stretch["length"]
            heading = ((b[0] - a[0]) / length, (b[1] - a[1]) / length)
            if index % 2:  # the other lane, so both sides of the asphalt are used
                heading = (-heading[0], -heading[1])
            right = right_of(heading)
            t = 0.3 + 0.4 * ((index * 0.37) % 1.0)
            centre = (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
            self.model(
                f"Car{index}",
                blueprint_path(era.name, props[index % len(props)], prop=True),
                (centre[0] + right[0] * lane, 0.0, centre[1] + right[1] * lane),
                rot_y=facing_rot(heading),
            )

    def build_player(self):
        """A 2 x 5 x 1 box by the plot entrance: every other size in the frame is judged against it."""
        era = self.era
        if era.streets:
            entrance = era.streets[0][0]
        else:
            entrance = (0.0, -era.half_z)
        offset = era.width / 2 + era.pavement / 2 + 1.5
        self.box(
            "Player",
            PLAYER_SIZE,
            (entrance[0] + offset, PLAYER_SIZE[1] / 2, entrance[1] + 3.0),
            PLAYER_COLOR,
            roughness=0.6,
        )

    def build(self):
        self.build_ground()
        if self.era.tiles is not None:
            self.build_tile_streets()
            self.build_pavements()
        else:
            self.build_plain_streets()
        self.build_blocks()
        self.build_park_strips()
        self.build_spurs()
        self.build_pads()
        self.build_buildings()
        self.build_lots()
        self.build_plazas()
        self.build_highway()
        self.build_subway()
        self.build_trees()
        self.build_park_trees()
        self.build_street_vehicles()
        self.build_player()
        return self


# --------------------------------------------------------------------------
# Lattice helpers (TileRenderer.luau)
# --------------------------------------------------------------------------


def cell_at(step, point):
    return (streetplan.round_half(point[0] / step), streetplan.round_half(point[1] / step))


def rasterise(step, a, b):
    path = [cell_at(step, a)]
    length = math.dist(a, b)
    steps = max(1, math.ceil(length / (step / SAMPLES_PER_CELL)))
    for index in range(1, steps + 1):
        cell = cell_at(step, streetplan.lerp(a, b, index / steps))
        if cell != path[-1]:
            path.append(cell)
    return path


def arm_for(delta):
    for arm, step in enumerate(ARM_STEPS, start=1):
        if delta == step:
            return arm
    return None


def opposite_arm(arm):
    """TileRenderer.oppositeArm: 1<->3 (+X/-X) and 2<->4 (-Z/+Z)."""
    return (arm + 1) % 4 + 1


def step_cell(cell, arm):
    delta = ARM_STEPS[arm - 1]
    return (cell[0] + delta[0], cell[1] + delta[1])


def run_cells(kinds, masks, cell, arm):
    """TileRenderer.runCells: straight cells from `cell` along `arm` until the street turns, ends
    or reaches the next junction."""
    count = 0
    current = cell
    while current is not None and kinds.get(current) == "straight":
        count += 1
        if not masks[current] & (1 << (arm - 1)):
            break
        current = step_cell(current, arm)
    return count


def ring_cycle(half):
    """Highway.ringCycle: the ring's cells as one cycle, counter-clockwise from (-half, -half)."""
    cycle = []
    for i in range(-half, half):
        cycle.append((i, -half))
    for j in range(-half, half):
        cycle.append((half, j))
    for i in range(half, -half, -1):
        cycle.append((i, half))
    for j in range(half, -half, -1):
        cycle.append((-half, j))
    return cycle


# --------------------------------------------------------------------------
# Cameras
# --------------------------------------------------------------------------


def normalize3(v):
    length = math.sqrt(sum(c * c for c in v))
    return tuple(c / length for c in v)


def cross3(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def box_corners(centre, half, height):
    """The eight corners of a box standing on the ground: `half` in X/Z about `centre`, 0..height."""
    return [
        (centre[0] + half[0] * sx, y, centre[1] + half[1] * sz)
        for sx in (-1, 1)
        for sz in (-1, 1)
        for y in (0.0, height)
    ]


def fit_camera(points, direction, lens, size):
    """eye and target that frame `points` tightly from `direction`.

    testfit aims at the centre of the bounding box, which is right for one building seen head on.
    A 120-stud plot seen from a corner at 35 degrees is not: its near corner lands far off the view
    axis, so a centre-aimed camera wastes most of the frame (the first Metropolis overview filled
    barely half of it). So the aim point is recentred on the *projected* bounds and the distance
    refitted, a few times, until the content is centred in the frame rather than in the world."""
    tan_x = math.tan(math.atan(18.0 / lens))  # 36 mm sensor, horizontal fit
    tan_y = tan_x * size[1] / size[0]
    direction = normalize3(direction)
    right = normalize3(cross3(direction, (0.0, 1.0, 0.0)))
    up = normalize3(cross3(right, (-direction[0], -direction[1], -direction[2])))
    target = tuple(sum(p[i] for p in points) / len(points) for i in range(3))
    distance = 1.0
    for _ in range(FIT_PASSES):
        distance = 1.0
        rels = []
        for point in points:
            rel = tuple(point[i] - target[i] for i in range(3))
            rels.append(rel)
            depth = sum(rel[i] * direction[i] for i in range(3))
            lateral = abs(sum(rel[i] * right[i] for i in range(3)))
            vertical = abs(sum(rel[i] * up[i] for i in range(3)))
            distance = max(distance, depth + lateral / tan_x, depth + vertical / tan_y)
        distance *= FIT_MARGIN
        us, vs = [], []
        for rel in rels:
            ahead = distance - sum(rel[i] * direction[i] for i in range(3))
            if ahead < 0.01:
                continue
            us.append(sum(rel[i] * right[i] for i in range(3)) / (tan_x * ahead))
            vs.append(sum(rel[i] * up[i] for i in range(3)) / (tan_y * ahead))
        if not us:
            break
        u_mid = (min(us) + max(us)) / 2
        v_mid = (min(vs) + max(vs)) / 2
        if abs(u_mid) < 0.005 and abs(v_mid) < 0.005:
            break
        shift_u = u_mid * tan_x * distance
        shift_v = v_mid * tan_y * distance
        target = tuple(target[i] + right[i] * shift_u + up[i] * shift_v for i in range(3))
    eye = tuple(target[i] + direction[i] * distance for i in range(3))
    return list(eye), list(target)


def camera_for(name, era, scene):
    """eye / target / lens in plot-local studs."""
    if name == "entrance":
        # Standing outside the plot on the entrance avenue, looking up it: the ring deck crosses
        # the top of the frame, which is the one thing a top-down plan cannot show.
        entrance = era.streets[0][0] if era.streets else (0.0, -era.half_z)
        # Eye height 5 is the character's; aiming only just above it keeps the sky out of half the
        # frame, which is what a plot of mostly sub-20-stud buildings otherwise gives.
        eye = (entrance[0], 5.0, entrance[1] - 15.0)
        return {"eye": list(eye), "target": [entrance[0], 6.0, entrance[1] + 55.0], "lens": 30.0}

    preset = dict(CAMERAS.get(name) or CAMERAS["point"])
    half, height = preset["half"], preset["height"]
    if name == "overview":
        centre = (0.0, 0.0)
        half = (era.half_x + 4.0, era.half_z + 4.0)
    elif name == "cityhall":
        slot = next((s for s in era.slots if s["id"] == "cityGrid"), None)
        centre = slot["position"] if slot else (0.0, 0.0)
    elif name == "ramp":
        origin = getattr(scene, "ramp_origin", None)
        if origin is None:
            raise SystemExit(f"{era.name} has no highway ramp to aim at")
        direction = RAMP_DIRECTIONS.get(era.highway["ramp"]["direction"], (1.0, 0.0))
        # Halfway down the ramp's three cells, so both the deck it leaves and the street it lands
        # on are in frame.
        centre = (origin[0] + direction[0] * era.tile_studs, origin[1] + direction[1] * era.tile_studs)
    elif name == "plaza":
        if not era.plazas:
            raise SystemExit(f"{era.name} has no plaza to aim at")
        centre = era.plazas[0]["position"]
    else:
        centre = preset["at"]

    eye, target = fit_camera(box_corners(centre, half, height), preset["dir"], preset["lens"], RENDER_SIZE)
    return {"eye": eye, "target": target, "lens": preset["lens"]}


# --------------------------------------------------------------------------
# Driver
# --------------------------------------------------------------------------


def resolve_owned(era, owned_arg, tier):
    """Which slots the plot has bought. `--tier N` on its own means "whatever the sim's greedy
    player owns by tier N", which is the only ownership set that produces a street network the
    client would really show partway through an era; an explicit `--owned` list wins over it."""
    ids = [slot["id"] for slot in era.slots]
    if owned_arg == "all":
        if tier is None:
            return set(ids)
        tiers = streetplan.greedy_buy_tiers(era.name, era.city)
        return {slot_id for slot_id in ids if tiers.get(slot_id, 99) <= tier}
    wanted = {part.strip() for part in owned_arg.split(",") if part.strip()}
    unknown = wanted - set(ids)
    if unknown:
        raise SystemExit(f"unknown slot id(s): {', '.join(sorted(unknown))}")
    return wanted


def run_blender(scene_spec, blender):
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8") as handle:
        json.dump(scene_spec, handle)
        scene_path = handle.name
    try:
        result = subprocess.run(
            [blender, "-b", "-P", str(Path(__file__).with_name("plotscene.py")), "--", "--scene", scene_path],
            capture_output=True,
            text=True,
        )
    finally:
        os.unlink(scene_path)
    for line in result.stdout.splitlines():
        if "[plotrender]" in line or "[testfit]" in line or "Error" in line:
            print(line)
    if result.returncode != 0:
        print(result.stderr[-4000:], file=sys.stderr)
        raise SystemExit(f"blender failed ({result.returncode})")


def main():
    parser = argparse.ArgumentParser(prog="plotrender.py", description=__doc__)
    parser.add_argument("era", help="era name, e.g. Metropolis")
    parser.add_argument(
        "--tier",
        type=int,
        help="growth tier 1-5: gates plazas and filler lots, and (unless --owned says otherwise) "
        "owns exactly what the sim's greedy player has bought by then. Default: the finished plot",
    )
    parser.add_argument("--owned", default="all", help="'all' (default) or a comma list of slot ids")
    parser.add_argument(
        "--camera",
        default="overview",
        help="overview | entrance | ramp | plaza | cityhall | x,z",
    )
    parser.add_argument("--out", help="output file stem (default plot_<camera>)")
    parser.add_argument("--blender", default=os.environ.get("BLENDER", DEFAULT_BLENDER))
    args = parser.parse_args()

    started = time.time()
    city = json.loads((REPO_ROOT / "src" / "shared" / "Config" / "CityDressing.json").read_text(encoding="utf-8"))
    era = streetplan.Era(args.era, city)
    network = streetplan.Network(era)
    tier = args.tier
    owned = resolve_owned(era, args.owned, tier)

    camera_name = args.camera
    if camera_name not in CAMERAS and camera_name != "entrance":
        try:
            x, z = (float(part) for part in camera_name.split(","))
        except ValueError:
            raise SystemExit(f"unknown --camera {camera_name!r}")
        CAMERAS["point"]["at"] = (x, z)
        camera_name = "point"

    scene = PlotScene(era, network, owned, 5 if tier is None else tier).build()
    stem = args.out or f"plot_{args.camera.replace(',', '_')}"
    out_path = OUT_ROOT / era.name / f"{stem}.png"
    scene_spec = {
        "era": era.name,
        "out": str(out_path),
        "size": list(RENDER_SIZE),
        "sky": SKY,
        "boxes": scene.boxes,
        "models": scene.models,
        "camera": camera_for(camera_name, era, scene),
    }

    print(
        f"== {era.name} plot render: camera {args.camera}, {len(owned)} of {len(era.slots)} slots owned, "
        f"tier {'full' if tier is None else tier}"
    )
    print(f"   {len(scene.visible)} of {len(network.stretches)} spine stretches visible")
    for note in scene.notes:
        print(f"   note: {note}")
    if scene.unreachable:
        print(f"   WARNING: no route from the entrance to {', '.join(sorted(scene.unreachable))}")
    run_blender(scene_spec, args.blender)
    print(f"   {out_path} in {time.time() - started:.1f}s")


if __name__ == "__main__":
    main()
