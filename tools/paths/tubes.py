#!/usr/bin/env python
"""Swept tubes, flat decking and hub nodes for an era whose streets are tubes (docs/INTERFACES.md
"Wave 4.1b -- organic Orbital").

    py tools/paths/tubes.py OrbitalColony              # bake every piece for upload
    py tools/paths/tubes.py OrbitalColony --list       # the piece table and the client/bake gate; writes nothing
    py tools/paths/tubes.py OrbitalColony --dry-run    # what would be baked; writes nothing
    py tools/paths/tubes.py OrbitalColony --piece L1_1 # one piece (repeatable)
    py tools/paths/tubes.py OrbitalColony --out-root DIR   # bake under DIR, not assets/

`py tools/paths/bake.py --era OrbitalColony ...` is the same command: bake.py hands a tube era here.

A tube era is a path era (`road.paths`) with a `road.paths.tube` block. Its streets are the same
chains and the same pieces tools/paths/network.py cuts for Village and Boomtown -- one per stretch,
`L<polyline>_<rank>`; one per landmark path, `SP_<slot>`; one per back lane, `LN_<k>` -- so the
client asks for a tube by the id it already asks a baked path by. What differs is the mesh:

  * a street piece is a HALF-PIPE swept along the chain's smoothed centreline from one of its
    nodes to the other, in tube-kit's own section (read from tools/assets/tube_kit.py, the kit's
    source: radius, sill, ring pitch and size, colours), a ring every RING_PITCH of the chain's own
    arc length so the rings run on evenly across a joint, and a closed disc at both ends. A piece
    stops exactly on its nodes: where a hub stands the end is inside the drum, and at any other
    node (a landmark's join, the frontier of a growing tube) two pieces butt on one cross-section,
    or the disc closes the pipe;
  * a landmark's piece is its APRON, flat decking: the footpath from the tube at
    `road.paths.spurWidth`, widened by a rect under the pad and one under the building's harvested
    extents, each grown APRON_MARGIN. tools/fabric.py keeps every lot off those shapes;
  * a lane's piece is flat decking at `fabric.lanes.width`, round at its far end;
  * the ENTRANCE APRON (`SP_entrance`) is flat decking as wide as a landmark's footpath, straight
    in from the plot's front edge to the first point of street 1, where the entrance hub stands.
    It belongs to no slot and is laid from the start: the world's road ends at the plot's front
    face, and the first tube starts further in.

A hub (`road.paths.tube.hub`, a round drum wider than the pipe) stands at every node where tubes
branch, where one ends, and where two chains meet end to end; `hubs()` lists them. Two tubes into
one hub leave it HUB_ARM_DEGREES or more apart (`hub_problems()`): a branch leaves a straight tube
square on, or the tube bends at the node and the three arms share the turn.

A centreline never curves tighter than MIN_RADIUS: the chains are smoothed by filleting each
polyline corner at two road widths, and a corner on legs too short for that is filleted tighter,
so `radius_problems()` names it and the generator refuses the layout.

The bake (INTERFACES "Wave 4.2 -- Assets") is the baked-paths route's, one mesh to a piece:

  * `assets/build/paths/<Era>/Fill_<pieceId>.glb`, the name tools/paths/bake.py gives a ribbon's
    fill: one node, one primitive, no material, so Roblox builds exactly one untextured MeshPart.
    Its UVs put every vertex on its material's swatch of the era's palette;
  * `assets/paths/<Era>_fill.png`, that palette (PALETTE's swatches in a row): where
    tools/assets/upload_paths.py looks for an era's fill texture. A tube era has no rim layer;
  * `assets/build/paths/<Era>.json`, the bake record upload_paths.py reads: bake.py's shape, with
    `layers` ["fill"], `look` "palette", each piece's `kind` and each mesh's sha256.

`--list` is the era's list gate, bake.py's exit codes: 1 when the pieces the client will ask for
(tools/paths/clientarcs.py's reading of RoadGraph, plus the entrance apron) and the pieces baked
disagree in ids, count, chain or arcs, when they overrun `budget.pathPieces`, or when the layout
breaks the radius or the hub rule; 2 when they agree but the files on disk are missing or are not
today's bytes (bake, upload, harvest); 0 otherwise.

tools/testfit/plotrender.py draws the same meshes from its own copies (`write`): the same
triangles with plain glTF colour factors, which Blender shows and Roblox would drop, in a folder
under the system temp folder named after this checkout, so a render never writes into assets/.
"""

from __future__ import annotations

import argparse
import ast
import hashlib
import json
import math
import os
import struct
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(REPO_ROOT, "tools"))
sys.path.insert(0, os.path.join(REPO_ROOT, "tools", "assets"))
sys.path.insert(0, os.path.join(REPO_ROOT, "tools", "pathmock"))
sys.path.insert(0, HERE)
import assets_config as cfg  # noqa: E402
import glbtools  # noqa: E402
import network  # noqa: E402
import palette as palette_png  # noqa: E402
import pathgeom as pg  # noqa: E402
import streetplan  # noqa: E402

TUBE_KIT = os.path.join(REPO_ROOT, "tools", "assets", "tube_kit.py")
# The contract's own numbers (INTERFACES "Wave 4.1b"), not tunables.
MIN_RADIUS = 6.0  # a centreline never curves tighter
HUB_FALLBACK = (4.6, 2.6)  # the drum's width and height until the hub prop has a blueprint
# Two tubes into one hub leave it at least this far apart, measured where each leaves the drum:
# closer and the two pipes meet outside it (a notch at 85 degrees, 0.9 studs of it at 60). The
# slack is for the smoothing, which turns a drawn right angle by a fraction of a degree.
HUB_ARM_DEGREES = 90.0
HUB_ARM_SLACK = 1.0
APRON_MARGIN = 0.25  # the decking shows this far round a pad and a building
ENTRANCE = "entrance"  # the entrance apron's piece kind, and its id after `SP_`

LINE_STEP = 0.25  # studs between the centreline samples tools/fabric.py measures against
LINE_CHUNK = 16  # samples to a chunk: a shape is only measured against the chunks near it
SECTION_STEP = 2.0  # a cross-section at least this often along a pipe...
SECTION_TURN = 4.0  # ...and whenever the heading has turned this many degrees
DECK_STEP = 1.0
CAP_SEGMENTS = 6  # a lane's round far end
GRID = 0.05  # the candidate spacing the two rules above pick from
ROUGHNESS = 0.9
# Flat decking is crowned along its middle, as a baked ribbon is, so no piece's box is flat.
DECK_CROWN = 0.005

# The bake: where tools/assets/upload_paths.py reads an era's record, meshes and textures.
BUILD_DIR = os.path.join(REPO_ROOT, "assets", "build", "paths")
PATHS_DIR = os.path.join(REPO_ROOT, "assets", "paths")
LAYER = "Fill"  # a tube era bakes this layer alone: bake.py's fill, no rim
LOOK = "palette"
# The swatches of the era's palette image, left to right. The order is part of every baked UV:
# changing it re-bakes every piece.
PALETTE = ("shell", "ring", "hull", "deck")
SWATCH = 16  # pixels a swatch; a vertex's UV is its swatch's middle
# What a piece is to the template (tools/assets/gen_templates.py): a tube stands on the plot, the
# decking lies at `paths.fillHeight`.
TUBE, DECK = "tube", "deck"


def tube_config(era):
    """`road.paths.tube` when the era's streets are swept tubes, else None."""
    paths = era.paths if isinstance(era.paths, dict) else None
    tube = paths.get("tube") if paths else None
    return tube if isinstance(tube, dict) else None


def default_root() -> str:
    """Where this checkout's render meshes go: outside every repo, not shared between worktrees."""
    return os.path.join(tempfile.gettempdir(), "EraCityTycoon", "tubes", os.path.basename(REPO_ROOT))


def log(msg: str) -> None:
    print(f"[tubes] {msg}", flush=True)


def warn(msg: str) -> None:
    print(f"[tubes] WARNING: {msg}", flush=True)


def kit_numbers(path: str = TUBE_KIT) -> dict:
    """tube-kit's module-level numbers and colours, read from its source: the kit script itself
    only runs inside Blender. Every plain assignment that evaluates from the ones before it."""
    with open(path, "r", encoding="utf-8") as handle:
        tree = ast.parse(handle.read(), path)
    values: dict = {}
    for node in tree.body:
        if not (isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name)):
            continue
        try:
            values[node.targets[0].id] = eval(compile(ast.Expression(node.value), path, "eval"), {"__builtins__": {}}, dict(values))
        except Exception:  # an assignment that needs an import (a path, a function call): not a number
            continue
    return values


def srgb_to_linear(byte: float) -> float:
    s = byte / 255.0
    return s / 12.92 if s <= 0.04045 else ((s + 0.055) / 1.055) ** 2.4


# ---------------------------------------------------------------------------------------------
# Meshes: flat-shaded triangles by material, in plot-local glTF space (Y up)
# ---------------------------------------------------------------------------------------------


class Mesh:
    def __init__(self, name: str):
        self.name = name
        self.groups: dict[str, list] = {}

    def tri(self, material: str, a, b, c, out) -> None:
        """One triangle, wound counter-clockwise as seen from the `out` direction."""
        ux, uy, uz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
        vx, vy, vz = c[0] - a[0], c[1] - a[1], c[2] - a[2]
        normal = (uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx)
        size = math.sqrt(normal[0] ** 2 + normal[1] ** 2 + normal[2] ** 2)
        if size < 1e-12:
            return  # a degenerate sliver (a cap's first fan triangle on a straight edge)
        if normal[0] * out[0] + normal[1] * out[1] + normal[2] * out[2] < 0:
            b, c = c, b
            normal = (-normal[0], -normal[1], -normal[2])
        unit = (normal[0] / size, normal[1] / size, normal[2] / size)
        self.groups.setdefault(material, []).append((a, b, c, unit))

    def quad(self, material: str, a, b, c, d, out) -> None:
        self.tri(material, a, b, c, out)
        self.tri(material, a, c, d, out)

    @property
    def tris(self) -> int:
        return sum(len(group) for group in self.groups.values())


def write_glb(path: str, mesh: Mesh, colours: dict) -> int:
    """One node, one mesh, a primitive per material: positions, flat normals, a colour factor."""
    binary = bytearray()
    views, accessors, primitives, materials = [], [], [], []
    for material in sorted(mesh.groups):
        group = mesh.groups[material]
        positions = b"".join(struct.pack("<fff", *p) for tri in group for p in tri[:3])
        normals = b"".join(struct.pack("<fff", *tri[3]) * 3 for tri in group)
        points = [p for tri in group for p in tri[:3]]
        lo = [min(p[i] for p in points) for i in range(3)]
        hi = [max(p[i] for p in points) for i in range(3)]
        for blob, extra in ((positions, {"min": lo, "max": hi}), (normals, {})):
            while len(binary) % 4:
                binary.append(0)
            views.append({"buffer": 0, "byteOffset": len(binary), "byteLength": len(blob), "target": 34962, "byteStride": 12})
            binary.extend(blob)
            accessors.append({"bufferView": len(views) - 1, "componentType": glbtools.FLOAT, "count": len(points), "type": "VEC3", **extra})
        rgb = colours[material]
        materials.append(
            {
                "name": material,
                "pbrMetallicRoughness": {
                    "baseColorFactor": [srgb_to_linear(rgb[0]), srgb_to_linear(rgb[1]), srgb_to_linear(rgb[2]), 1.0],
                    "metallicFactor": 0.0,
                    "roughnessFactor": ROUGHNESS,
                },
            }
        )
        primitives.append({"attributes": {"POSITION": len(accessors) - 2, "NORMAL": len(accessors) - 1}, "material": len(materials) - 1})
    doc = {
        "asset": {"version": "2.0", "generator": "EraCityTycoon tubes"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"name": mesh.name, "mesh": 0}],
        "meshes": [{"name": mesh.name, "primitives": primitives}],
        "materials": materials,
        "bufferViews": views,
        "accessors": accessors,
        "buffers": [{"byteLength": len(binary)}],
    }
    data = glbtools.write_glb(doc, bytes(binary))
    glbtools.validate(data)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as handle:
        handle.write(data)
    return len(data)


def swatch_uv(material: str) -> tuple[float, float]:
    return ((PALETTE.index(material) + 0.5) / len(PALETTE), 0.5)


def upload_glb(mesh: Mesh) -> bytes:
    """The piece as it is uploaded: one node, one mesh, one primitive and no material -- what
    tools/paths/planargeom.py writes for a ribbon -- with positions, flat normals and, for every
    vertex, the UV of its material's swatch. The same triangles `write_glb` colours by factor."""
    positions, normals, uvs = [], [], []
    for material in PALETTE:
        uv = swatch_uv(material)
        for a, b, c, normal in mesh.groups.get(material, ()):
            positions += [a, b, c]
            normals += [normal] * 3
            uvs += [uv] * 3
    unknown = sorted(set(mesh.groups) - set(PALETTE))
    if unknown or not positions:
        raise SystemExit(f"tubes: {mesh.name}: no triangles to bake" if not positions else f"tubes: {mesh.name}: no palette swatch for {unknown}")
    binary = bytearray()
    views = []

    def view(blob: bytes, target: int, stride: int | None = None) -> int:
        while len(binary) % 4:
            binary.append(0)
        views.append({"buffer": 0, "byteOffset": len(binary), "byteLength": len(blob), "target": target, **({"byteStride": stride} if stride else {})})
        binary.extend(blob)
        return len(views) - 1

    count = len(positions)
    pos = view(b"".join(struct.pack("<fff", *p) for p in positions), 34962, 12)
    nrm = view(b"".join(struct.pack("<fff", *n) for n in normals), 34962, 12)
    tex = view(b"".join(struct.pack("<ff", *t) for t in uvs), 34962, 8)
    idx = view(struct.pack(f"<{count}I", *range(count)), 34963)
    while len(binary) % 4:
        binary.append(0)
    lo, hi = bounds(positions)
    doc = {
        "asset": {"version": "2.0", "generator": "EraCityTycoon tubes"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"name": mesh.name, "mesh": 0}],
        "meshes": [{"name": mesh.name, "primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2}, "indices": 3}]}],
        "bufferViews": views,
        "accessors": [
            {"bufferView": pos, "componentType": glbtools.FLOAT, "count": count, "type": "VEC3", "min": lo, "max": hi},
            {"bufferView": nrm, "componentType": glbtools.FLOAT, "count": count, "type": "VEC3"},
            {"bufferView": tex, "componentType": glbtools.FLOAT, "count": count, "type": "VEC2"},
            {"bufferView": idx, "componentType": glbtools.UNSIGNED_INT, "count": count, "type": "SCALAR"},
        ],
        "buffers": [{"byteLength": len(binary)}],
    }
    data = glbtools.write_glb(doc, bytes(binary))
    problems = glbtools.roblox_problems(data)
    if problems:
        raise SystemExit(f"tubes: {mesh.name}: not importable: {problems}")
    return data


def bounds(points) -> tuple[list[float], list[float]]:
    return [min(p[i] for p in points) for i in range(3)], [max(p[i] for p in points) for i in range(3)]


def palette_image(colours: dict) -> bytes:
    """The era's palette as PNG bytes: PALETTE's colours, a SWATCH-wide swatch each, in a row.
    tools/assets/palette.py writes it (the one PNG writer the kits' palettes use), so the bytes
    are a fixed function of the colours."""
    row = [tuple(int(v) for v in colours[material]) for material in PALETTE for _ in range(SWATCH)]
    with tempfile.TemporaryDirectory() as folder:
        target = os.path.join(folder, "palette.png")
        palette_png.write_png(target, len(row), SWATCH, [row] * SWATCH)
        with open(target, "rb") as handle:
            return handle.read()


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


# ---------------------------------------------------------------------------------------------
# The plan: lines, hubs, aprons, pieces
# ---------------------------------------------------------------------------------------------


def bend_radii(points, radius: float):
    """(corner, degrees turned, fillet radius) for every corner pathgeom.fillet rounds, by its own
    rule: the asked `radius`, shrunk where a leg is too short to hold the arc's tangent."""
    points = pg.merge_short_legs(list(points), pg.MIN_LEG_WIDTHS * radius / pg.FILLET_RADIUS_WIDTHS)
    found = []
    before = points[0] if points else None
    for i in range(1, len(points) - 1):
        corner, after = points[i], points[i + 1]
        d_in, d_out = pg.norm(pg.sub(corner, before)), pg.norm(pg.sub(after, corner))
        turn = math.acos(max(-1.0, min(1.0, pg.dot(d_in, d_out))))
        if math.degrees(turn) < pg.FILLET_MIN_DEG:
            before = corner
            continue
        half = math.tan(turn / 2)
        tangent = min(radius * half, 0.95 * pg.length(pg.sub(corner, before)), 0.48 * pg.length(pg.sub(after, corner)))
        found.append((corner, math.degrees(turn), tangent / half))
        before = pg.add(corner, pg.mul(d_out, tangent))
    return found


class Line:
    """One street chain's drawn centreline between its first and last node, sampled every LINE_STEP:
    what a lot, a pad or a marker is measured against, and what a lot is laid along."""

    def __init__(self, label: str, polyline, chain: dict):
        self.label, self.polyline, self.chain = label, polyline, chain
        curve = chain["final"]
        self.lo, self.hi = chain["ext"][0], curve.total - chain["ext"][1]
        self.length = self.hi - self.lo
        count = max(1, math.ceil(self.length / LINE_STEP))
        self.arcs = [self.length * k / count for k in range(count + 1)]
        self.points = [curve.point(self.lo + arc) for arc in self.arcs]
        self.box = (
            min(p[0] for p in self.points),
            max(p[0] for p in self.points),
            min(p[1] for p in self.points),
            max(p[1] for p in self.points),
        )
        self.stretches: list[tuple[int, float, float]] = []  # (stretch index, arc from, arc to)
        self.chunks = []  # (x0, x1, z0, z1, first sample, one past the last): overlapping by one
        for first in range(0, len(self.points) - 1, LINE_CHUNK):
            part = self.points[first : first + LINE_CHUNK + 1]
            self.chunks.append((min(p[0] for p in part), max(p[0] for p in part), min(p[1] for p in part), max(p[1] for p in part), first, first + len(part)))

    def point(self, arc: float):
        return self.chain["final"].point(self.lo + max(0.0, min(self.length, arc)))

    def tangent(self, arc: float):
        return self.chain["final"].tangent(self.lo + max(0.0, min(self.length, arc)), 0.2)

    def stretch_at(self, arc: float):
        """The stretch whose run holds `arc`; a node belongs to the stretch that starts there."""
        best = None
        for index, start, end in self.stretches:
            if start - 1e-6 <= arc <= end + 1e-6 and (best is None or start > best[1]):
                best = (index, start)
        return best[0] if best is not None else None

    def project(self, point):
        """(distance, arc) of the sample nearest `point`."""
        return min((math.hypot(point[0] - q[0], point[1] - q[1]), arc) for arc, q in zip(self.arcs, self.points))

    def gap(self, poly, reach: float) -> float:
        """Daylight between a convex polygon and the centreline, measured at its samples; 0 when the
        line runs through it, and `inf` when it is more than `reach` away (nobody asks how far)."""
        x0, x1 = min(p[0] for p in poly) - reach, max(p[0] for p in poly) + reach
        z0, z1 = min(p[1] for p in poly) - reach, max(p[1] for p in poly) + reach
        # Each edge as (start, direction, its length squared): a lot walker asks this tens of
        # thousands of times, so the point-to-polygon distance is written out here.
        edges = []
        for (ax, az), (bx, bz) in zip(poly, poly[1:] + poly[:1]):
            dx, dz = bx - ax, bz - az
            edges.append((ax, az, dx, dz, dx * dx + dz * dz))
        best = math.inf
        for cx0, cx1, cz0, cz1, first, last in self.chunks:
            if cx0 > x1 or cx1 < x0 or cz0 > z1 or cz1 < z0:
                continue
            for qx, qz in self.points[first:last]:
                if qx < x0 or qx > x1 or qz < z0 or qz > z1:
                    continue
                nearest, left, right = math.inf, True, True
                for ax, az, dx, dz, squared in edges:
                    px, pz = qx - ax, qz - az
                    turn = dx * pz - dz * px
                    left, right = left and turn >= 0, right and turn <= 0
                    along = 0.0 if squared < 1e-18 else max(0.0, min(1.0, (px * dx + pz * dz) / squared))
                    ex, ez = px - dx * along, pz - dz * along
                    nearest = min(nearest, ex * ex + ez * ez)
                if left or right:
                    return 0.0  # on one side of every edge: inside the polygon
                best = min(best, nearest)
        best = math.sqrt(best) if best < math.inf else best
        return best if best <= reach else math.inf


class TubePlan:
    """One tube era's network as tools/paths/network.py cuts it, with what is new to tubes."""

    entrance_kind = ENTRANCE  # a piece of this kind is the entrance apron, drawn from the start

    def __init__(self, era_name: str, city: dict, fabric_data=None):
        self.bake = network.Bake(era_name, city, fabric_data)
        self.era, self.net = self.bake.era, self.bake.network
        self.config = tube_config(self.era)
        if self.config is None:
            raise ValueError(f"{era_name}: eras.{era_name}.road.paths.tube is missing from CityDressing.json")
        self.front = float(self.config["front"])
        self.kit = kit_numbers()
        deck = (self.era.paths.get("deck") or {}).get("color") or self.era.dressing["road"]["color"]
        self.colours = {"shell": self.kit["SHELL"], "ring": self.kit["RING"], "hull": self.kit["HULL"], "deck": tuple(deck)}
        hub = streetplan.prop_footprint(era_name, [self.config.get("hub")] if self.config.get("hub") else [], (HUB_FALLBACK[0], HUB_FALLBACK[0]))
        self.hub_radius = max(hub) / 2
        if any(slot["id"] == ENTRANCE for slot in self.era.slots):
            raise ValueError(f"{era_name}: a slot named {ENTRANCE!r} would share the entrance apron's piece id")
        self._pieces = self.bake.pieces()
        apron = self.entrance_apron()
        if apron is not None:
            self._pieces.append({"id": f"SP_{ENTRANCE}", "kind": ENTRANCE, "ground": apron})
            self._pieces.sort(key=lambda piece: piece["id"])
        self._hubs = None
        self.lines: list[Line] = []
        self.line_of_stretch: dict[int, Line] = {}
        by_chain: dict[str, Line] = {}
        for stretch_index, stretch in enumerate(self.net.stretches):
            chain = self.bake.chain_for_stretch(stretch_index)
            line = by_chain.get(chain["id"])
            if line is None:
                polyline = stretch["polyline"] if stretch["segment"] is not None else None
                label = f"street {polyline + 1}" if polyline is not None else f"the link {streetplan.fmt(stretch['a'])}->{streetplan.fmt(stretch['b'])}"
                line = by_chain[chain["id"]] = Line(label, polyline, chain)
                self.lines.append(line)
            start = self.bake.arc_at(chain, stretch["a"]) - line.lo
            end = self.bake.arc_at(chain, stretch["b"]) - line.lo
            line.stretches.append((stretch_index, min(start, end), max(start, end)))
            self.line_of_stretch[stretch_index] = line

    # -- nodes ----------------------------------------------------------------------------

    def node_point(self, node: int):
        """A node on the drawn centreline: where its first stretch's chain passes it."""
        for stretch_index, stretch in enumerate(self.net.stretches):
            for end in ("from", "to"):
                if stretch[end] == node:
                    chain = self.bake.chain_for_stretch(stretch_index)
                    return chain["final"].point(self.bake.arc_at(chain, stretch["a" if end == "from" else "b"]))
        return tuple(self.net.nodes[node])

    def hubs(self) -> list[dict]:
        """Every node a hub stands on, as {node, point, why}: a tube ends there (one stretch), tubes
        branch there (three or more), or two chains meet there end to end -- anywhere two pipes
        would otherwise meet at an angle or stop in the open for good."""
        if self._hubs is not None:
            return self._hubs
        ends: dict[int, list[int]] = {}
        for stretch_index, stretch in enumerate(self.net.stretches):
            for node in (stretch["from"], stretch["to"]):
                ends.setdefault(node, []).append(stretch_index)
        found = []
        for node in sorted(ends):
            chains = {self.bake.chain_for_stretch(index)["id"] for index in ends[node]}
            why = "end" if len(ends[node]) == 1 else "branch" if len(ends[node]) >= 3 else "joint" if len(chains) > 1 else None
            if why is not None:
                found.append({"node": node, "point": self.node_point(node), "why": why, "stretches": list(ends[node])})
        self._hubs = found
        return found

    def hub_problems(self) -> list[str]:
        """Every pair of tubes that leave one hub closer than HUB_ARM_DEGREES: each arm's heading
        is from the node to where its centreline leaves the drum."""
        problems = []
        for hub in self.hubs():
            arms = []
            for stretch_index in hub["stretches"]:
                stretch = self.net.stretches[stretch_index]
                chain = self.bake.chain_for_stretch(stretch_index)
                arc_a, arc_b = self.bake.arc_at(chain, stretch["a"]), self.bake.arc_at(chain, stretch["b"])
                here, there = (arc_a, arc_b) if stretch["from"] == hub["node"] else (arc_b, arc_a)
                reach = min(self.hub_radius, abs(there - here))
                leave = chain["final"].point(here + math.copysign(reach, there - here))
                arms.append((self.line_of_stretch[stretch_index].label, pg.norm(pg.sub(leave, chain["final"].point(here)))))
            for i, (first, a) in enumerate(arms):
                for second, b in arms[i + 1 :]:
                    apart = math.degrees(math.acos(max(-1.0, min(1.0, pg.dot(a, b)))))
                    if apart < HUB_ARM_DEGREES - HUB_ARM_SLACK:
                        where = streetplan.fmt((round(hub["point"][0], 2), round(hub["point"][1], 2)))
                        problems.append(
                            f"the hub at {where}: {first} and {second} leave it {apart:.0f} degrees apart; two tubes into one hub "
                            f"need {HUB_ARM_DEGREES:g}, or their pipes meet outside the drum"
                        )
        return problems

    # -- the 6-stud rule --------------------------------------------------------------------

    def radius_problems(self) -> list[str]:
        problems = []
        for line in self.lines:
            chain = line.chain
            for corner, turn, radius in bend_radii(chain["points"], pg.FILLET_RADIUS_WIDTHS * chain["width"]):
                if radius < MIN_RADIUS - 1e-6:
                    problems.append(
                        f"{line.label}: the bend at {streetplan.fmt((round(corner[0], 2), round(corner[1], 2)))} turns {turn:.0f} degrees on legs too short "
                        f"to round it: radius {radius:.2f}, a tube needs {MIN_RADIUS:g} (lengthen the legs beside it or soften the turn)"
                    )
        return problems

    # -- aprons -----------------------------------------------------------------------------

    def apron_rects(self, slot_id: str) -> list[tuple[str, list]]:
        """The two rects that widen a landmark's footpath into its apron: under its pad and under
        its building's harvested extents (its declared footprint before a harvest), each grown
        APRON_MARGIN. A street-only slot spawns no building and has only its pad's."""
        slot = next(s for s in self.era.slots if s["id"] == slot_id)
        pad = slot["pad"]
        rects = [("pad", streetplan.square(pad, self.era.pad_size[0] + 2 * APRON_MARGIN, self.era.pad_size[1] + 2 * APRON_MARGIN, 0))]
        for other_id, poly, _measured in streetplan.landmark_extents(self.era):
            if other_id == slot_id:
                cx = sum(p[0] for p in poly) / 4
                cz = sum(p[1] for p in poly) / 4
                width, depth = math.dist(poly[0], poly[1]), math.dist(poly[1], poly[2])
                rects.append(("building", streetplan.square((cx, cz), width + 2 * APRON_MARGIN, depth + 2 * APRON_MARGIN, slot["rotation"])))
        return rects

    def entrance_apron(self):
        """The entrance apron's ground, front edge first, or None when street 1 starts on the plot's
        front edge: `road.paths.spurWidth` wide, straight in to the first point of street 1."""
        if not self.era.streets or not self.era.streets[0]:
            return None
        x, z = self.era.streets[0][0]
        front = -self.era.half_z
        if z - front < streetplan.MIN_LENGTH:
            return None
        return streetplan.slab_poly((x, front), (x, z), streetplan.spur_path_width(self.era), 0.0)

    def apron_path(self, slot_id: str):
        """A landmark footpath's centreline, anchor to join, as the bake smooths it, and its width."""
        index = self.bake.spur_chains.get(slot_id)
        if index is None:
            return None
        chain = self.bake.chains[index]
        curve = chain["final"]
        lo, hi = chain["ext"][0], curve.total - chain["ext"][1]
        count = max(1, math.ceil((hi - lo) / DECK_STEP))
        return [curve.point(lo + (hi - lo) * k / count) for k in range(count + 1)], chain["width"]

    # -- pieces -----------------------------------------------------------------------------

    def pieces(self) -> list[dict]:
        return self._pieces

    def _sections(self, curve, lo: float, hi: float, step: float) -> list[float]:
        count = max(2, math.ceil((hi - lo) / GRID))
        grid = [lo + (hi - lo) * k / count for k in range(count + 1)]
        kept = [grid[0]]
        last = curve.tangent(grid[0], 0.2)
        for s in grid[1:-1]:
            tangent = curve.tangent(s, 0.2)
            turn = math.degrees(math.acos(max(-1.0, min(1.0, pg.dot(tangent, last)))))
            if s - kept[-1] >= step - 1e-9 or turn >= SECTION_TURN:
                kept.append(s)
                last = tangent
        kept.append(grid[-1])
        return kept

    @staticmethod
    def _frame(curve, s: float):
        point, tangent = curve.point(s), curve.tangent(s, 0.2)
        return point, tangent, (-tangent[1], tangent[0])

    def _loop(self, curve, s: float, profile):
        point, _, normal = self._frame(curve, s)
        return [(point[0] + normal[0] * z, y, point[1] + normal[1] * z) for z, y in profile]

    def tube_mesh(self, piece: dict) -> Mesh:
        """One stretch's half-pipe: shell and sill, rings, a disc closing each end."""
        kit = self.kit
        radius, sill = kit["R"], kit["SILL"]

        def arc(r: float, segments: int):
            return [(r * math.cos(math.pi * i / segments), sill + r * math.sin(math.pi * i / segments)) for i in range(segments + 1)]

        def ring_profile(r: float):
            return [(r, 0.0)] + arc(r, kit["RING_SEGS"])[1:-1] + [(-r, 0.0)]

        section = [(radius, 0.0)] + arc(radius, kit["ARC_SEGS"]) + [(-radius, 0.0)]
        chain = piece["_chain"]
        curve = chain["final"]
        lo, hi = sorted(piece["nodeArcs"])
        mesh = Mesh(piece["id"])

        def axis(s: float):
            point = curve.point(s)
            return (point[0], sill * 0.5, point[1])

        def away(a, b, s0: float, s1: float):
            """Outward for a face between two section points: away from the pipe's axis."""
            a0, a1 = axis(s0), axis(s1)
            return ((a[0] + b[0]) / 2 - (a0[0] + a1[0]) / 2, (a[1] + b[1]) / 2 - a0[1], (a[2] + b[2]) / 2 - (a0[2] + a1[2]) / 2)

        stations = self._sections(curve, lo, hi, SECTION_STEP)
        loops = [self._loop(curve, s, section) for s in stations]
        for k in range(len(stations) - 1):
            for j in range(len(section) - 1):
                material = "ring" if section[j][1] == 0.0 or section[j + 1][1] == 0.0 else "shell"
                a, b, c, d = loops[k][j], loops[k + 1][j], loops[k + 1][j + 1], loops[k][j + 1]
                mesh.quad(material, a, b, c, d, away(a, c, stations[k], stations[k + 1]))
        for s, sign in ((lo, -1.0), (hi, 1.0)):
            loop = self._loop(curve, s, section)
            tangent = curve.tangent(s, 0.2)
            out = (sign * tangent[0], 0.0, sign * tangent[1])
            for j in range(1, len(loop) - 1):
                mesh.tri("hull", loop[0], loop[j], loop[j + 1], out)
        # Rings on the chain's own lattice of arc length, so they run on evenly from piece to
        # piece; one whose middle lies in this piece is this piece's, and none stands inside a hub.
        pitch, half = kit["RING_PITCH"], kit["RING_W"] / 2
        start = chain["ext"][0]
        hub_points = [hub["point"] for hub in self.hubs()]
        first = math.ceil((lo - start) / pitch - 1e-9)
        k = first
        while start + k * pitch < hi - 1e-9:
            at = start + k * pitch
            k += 1
            if at < lo + half or at > hi - half:
                continue
            centre = curve.point(at)
            if any(math.dist(centre, hub) < self.hub_radius + half for hub in hub_points):
                continue
            outer = [self._loop(curve, s, ring_profile(kit["RING_OUT"])) for s in (at - half, at + half)]
            inner = [self._loop(curve, s, ring_profile(kit["RING_IN"])) for s in (at - half, at + half)]
            tangent = curve.tangent(at, 0.2)
            for j in range(len(outer[0]) - 1):
                a, b, c, d = outer[0][j], outer[1][j], outer[1][j + 1], outer[0][j + 1]
                mesh.quad("ring", a, b, c, d, away(a, c, at - half, at + half))
                for side, sign in ((0, -1.0), (1, 1.0)):
                    mesh.quad("ring", outer[side][j], outer[side][j + 1], inner[side][j + 1], inner[side][j], (sign * tangent[0], 0.0, sign * tangent[1]))
        return mesh

    def _ribbon(self, mesh: Mesh, curve, lo: float, hi: float, half: float, round_start: bool) -> None:
        up = (0.0, 1.0, 0.0)
        stations = self._sections(curve, lo, hi, DECK_STEP)
        edges = []
        for s in stations:
            point, _, normal = self._frame(curve, s)
            edges.append(
                (
                    (point[0] + normal[0] * half, 0.0, point[1] + normal[1] * half),
                    (point[0], DECK_CROWN, point[1]),
                    (point[0] - normal[0] * half, 0.0, point[1] - normal[1] * half),
                )
            )
        for (l0, m0, r0), (l1, m1, r1) in zip(edges, edges[1:]):
            mesh.quad("deck", l0, l1, m1, m0, up)
            mesh.quad("deck", m0, m1, r1, r0, up)
        if round_start:
            point, tangent, normal = self._frame(curve, lo)
            fan = []
            for k in range(CAP_SEGMENTS + 1):
                angle = math.pi * k / CAP_SEGMENTS
                x = point[0] + half * (normal[0] * math.cos(angle) - tangent[0] * math.sin(angle))
                z = point[1] + half * (normal[1] * math.cos(angle) - tangent[1] * math.sin(angle))
                fan.append((x, 0.0, z))
            centre = (point[0], DECK_CROWN, point[1])
            for a, b in zip(fan, fan[1:]):
                mesh.tri("deck", centre, a, b, up)

    @staticmethod
    def _slab(mesh: Mesh, poly) -> None:
        """A flat shape of decking, crowned at its middle."""
        corners = [(p[0], 0.0, p[1]) for p in poly]
        middle = (sum(p[0] for p in poly) / len(poly), DECK_CROWN, sum(p[1] for p in poly) / len(poly))
        for a, b in zip(corners, corners[1:] + corners[:1]):
            mesh.tri("deck", middle, a, b, (0.0, 1.0, 0.0))

    def deck_mesh(self, piece: dict) -> Mesh:
        """A landmark's apron, the entrance apron or a lane: flat decking at y 0 (the template lifts
        it), crowned by DECK_CROWN. The shapes of an apron overlap in one colour within that crown,
        as two baked path pieces do at a node."""
        mesh = Mesh(piece["id"])
        if piece["kind"] == ENTRANCE:
            self._slab(mesh, piece["ground"])
            return mesh
        chain = piece["_chain"]
        curve = chain["final"]
        lo, hi = chain["ext"][0], curve.total - chain["ext"][1]
        if piece["kind"] == "lane":
            # A lane chain runs from its far point (a round end) to its mouth on the tube.
            self._ribbon(mesh, curve, lo, hi, chain["width"] / 2, True)
            return mesh
        self._ribbon(mesh, curve, lo, hi, chain["width"] / 2, False)
        for _, poly in self.apron_rects(piece["slot"]):
            self._slab(mesh, poly)
        return mesh

    def mesh_for(self, piece: dict) -> tuple[str, Mesh]:
        if piece["kind"] == "stretch":
            return "Tube", self.tube_mesh(piece)
        return "Deck", self.deck_mesh(piece)

    def write(self, root: str | None = None) -> dict:
        """The render copies (tools/testfit/plotrender.py): every piece as
        `<root>/<Era>/{Tube,Deck}/<id>.glb`, coloured by glTF colour factors, and
        `<root>/<Era>/<Era>.json` listing them with the hubs. Refuses a layout with a bend under
        MIN_RADIUS. Returns the listing."""
        problems = self.radius_problems()
        if problems:
            raise SystemExit("\n".join(f"tubes: {problem}" for problem in problems))
        root = os.path.join(root or default_root(), self.era.name)
        listing = {"era": self.era.name, "layoutHash": self.bake.layout_hash(), "root": root, "pieces": [], "hubs": []}
        for piece in self._pieces:
            layer, mesh = self.mesh_for(piece)
            path = os.path.join(root, layer, f"{piece['id']}.glb")
            size = write_glb(path, mesh, self.colours)
            listing["pieces"].append({"id": piece["id"], "kind": piece["kind"], "layer": layer, "glb": path, "tris": mesh.tris, "bytes": size})
        for hub in self.hubs():
            listing["hubs"].append({"node": hub["node"], "point": [round(hub["point"][0], 3), round(hub["point"][1], 3)], "why": hub["why"]})
        with open(os.path.join(root, f"{self.era.name}.json"), "w", encoding="utf-8", newline="\n") as handle:
            json.dump(listing, handle, indent=2)
        return listing

    def tube_length(self) -> float:
        """Studs of tube at full build: the drawn stretches, node to node along the centreline."""
        return sum(abs(piece["nodeArcs"][1] - piece["nodeArcs"][0]) for piece in self._pieces if piece["kind"] == "stretch")


# ---------------------------------------------------------------------------------------------
# The bake: upload-ready pieces, the record tools/assets/upload_paths.py reads, and the list gate
# ---------------------------------------------------------------------------------------------


def piece_kind(piece: dict) -> str:
    return TUBE if piece["kind"] == "stretch" else DECK


def bake_paths(era: str, out_root: str | None) -> tuple[str, str, str]:
    """(the record, the era's mesh folder, its palette) of a bake: bake.py's and upload_paths.py's
    places under assets/, or everything under `out_root` (a scratch bake)."""
    if out_root is None:
        return os.path.join(BUILD_DIR, f"{era}.json"), os.path.join(BUILD_DIR, era), os.path.join(PATHS_DIR, f"{era}_fill.png")
    return os.path.join(out_root, f"{era}.json"), os.path.join(out_root, era), os.path.join(out_root, f"{era}_fill.png")


def recorded(path: str) -> str:
    """A file as a bake record names it: from the repo root when it lies in the repo (what
    upload_paths.py joins onto the root), else whole."""
    inside = os.path.relpath(path, REPO_ROOT)
    return (path if inside.startswith("..") or os.path.isabs(inside) else inside).replace(os.sep, "/")


def baked_mesh(plan: TubePlan, piece: dict) -> tuple[dict, bytes]:
    """One piece's record entry and its upload bytes."""
    _, mesh = plan.mesh_for(piece)
    data = upload_glb(mesh)
    points = [p for group in mesh.groups.values() for tri in group for p in tri[:3]]
    lo, hi = bounds(points)
    info = {
        "triangles": mesh.tris,
        "vertices": 3 * mesh.tris,
        "centre": [round((a + b) / 2, 4) for a, b in zip(lo, hi)],
        "size": [round(b - a, 4) for a, b in zip(lo, hi)],
        "bytes": len(data),
        "sha256": sha256(data),
    }
    return info, data


def bake_record(plan: TubePlan, out_root: str | None) -> tuple[dict, dict[str, bytes], bytes]:
    """The whole era as it bakes today: (the record, each piece's GLB bytes, the palette's)."""
    era = plan.era.name
    _, mesh_dir, palette_path = bake_paths(era, out_root)
    image = palette_image(plan.colours)
    record = {
        "era": era,
        "tileStuds": plan.bake.tile_studs,
        "width": plan.era.width,
        "spurWidth": plan.bake.spur_width,
        "layoutHash": plan.bake.layout_hash(),
        "look": LOOK,
        "layers": [LAYER.lower()],
        "palette": {"file": recorded(palette_path), "sha256": sha256(image), "size": [SWATCH * len(PALETTE), SWATCH], "swatches": list(PALETTE)},
        "hubs": [{"node": hub["node"], "point": [round(hub["point"][0], 3), round(hub["point"][1], 3)], "why": hub["why"]} for hub in plan.hubs()],
        "pieces": {},
    }
    blobs: dict[str, bytes] = {}
    for piece in plan.pieces():
        info, data = baked_mesh(plan, piece)
        info["glb"] = recorded(os.path.join(mesh_dir, f"{LAYER}_{piece['id']}.glb"))
        entry = {"kind": piece_kind(piece), "piece": piece["kind"], "meshes": {LAYER: info}}
        if "nodeArcs" in piece:
            entry["chain"] = piece["chain"]
            entry["nodeArcs"] = [round(v, 4) for v in piece["nodeArcs"]]
        for key in ("slot", "lane", "stretch"):
            if key in piece:
                entry[key] = piece[key]
        record["pieces"][piece["id"]] = entry
        blobs[piece["id"]] = data
    meshes = [(piece_id, entry["meshes"][LAYER]) for piece_id, entry in record["pieces"].items()]
    largest = max(meshes, key=lambda item: item[1]["triangles"], default=("-", {"triangles": 0}))
    record["totals"] = {
        "pieces": len(meshes),
        "meshes": len(meshes),
        "triangles": sum(info["triangles"] for _, info in meshes),
        "vertices": sum(info["vertices"] for _, info in meshes),
        "tubes": sum(1 for entry in record["pieces"].values() if entry["kind"] == TUBE),
        "decking": sum(1 for entry in record["pieces"].values() if entry["kind"] == DECK),
        "largest": {"piece": largest[0], "layer": LAYER, "triangles": largest[1]["triangles"]},
    }
    return record, blobs, image


def layout_problems(plan: TubePlan) -> list[str]:
    return plan.radius_problems() + plan.hub_problems()


def bake(plan: TubePlan, only: list[str], dry_run: bool, out_root: str | None) -> int:
    """Write the era's upload-ready pieces, its palette and its record. Refuses a layout that
    breaks the radius or the hub rule, and -- as bake.py does -- a piece id set that moved under
    an unchanged layout hash."""
    import bake as ribbons  # tools/paths/bake.py; late, as it hands a tube era to this module

    era = plan.era.name
    problems = layout_problems(plan) + ribbons.check_ids(era, plan.bake.layout_hash(), [piece["id"] for piece in plan.pieces()])
    for line in problems:
        warn(line)
    if problems:
        warn("refusing to bake; fix the layout, or clear the era's pieces in Assets.json first")
        return 1
    record, blobs, image = bake_record(plan, out_root)
    unknown = [piece_id for piece_id in only if piece_id not in blobs]
    if unknown:
        warn(f"no such piece(s) in {era}: {', '.join(unknown)}")
        return 1
    record_path, mesh_dir, palette_path = bake_paths(era, out_root)
    chosen = [piece_id for piece_id in sorted(blobs) if not only or piece_id in only]
    totals = record["totals"]
    if dry_run:
        log(f"{era}: would write {len(chosen)} GLB(s) into {recorded(mesh_dir)}, {recorded(palette_path)} and {recorded(record_path)}")
        log(f"{era}: {totals['pieces']} pieces = {totals['tubes']} tube + {totals['decking']} decking, {totals['triangles']} triangles; nothing written")
        return 0
    os.makedirs(mesh_dir, exist_ok=True)
    os.makedirs(os.path.dirname(palette_path), exist_ok=True)
    for piece_id in chosen:
        with open(os.path.join(mesh_dir, f"{LAYER}_{piece_id}.glb"), "wb") as handle:
            handle.write(blobs[piece_id])
    with open(palette_path, "wb") as handle:
        handle.write(image)
    with open(record_path, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(record, handle, indent=1, sort_keys=True)
        handle.write("\n")
    largest = totals["largest"]
    log(f"{era}: wrote {len(chosen)} GLB(s), {recorded(palette_path)} and {recorded(record_path)}")
    log(
        f"{era}: {totals['pieces']} pieces = {totals['tubes']} tube + {totals['decking']} decking, {totals['triangles']} triangles total, "
        f"largest {LAYER}_{largest['piece']} at {largest['triangles']}"
    )
    return 0


def client_pieces(plan: TubePlan) -> dict[str, dict]:
    """Every piece id the client can ask for on this era: tools/paths/clientarcs.py's reading of
    RoadGraph (the reveal rule and both budgets) and, where the first tube starts inside the plot's
    front edge, the entrance apron, which is laid from the start and belongs to no slot."""
    import clientarcs  # tools/paths; late: it imports tools/cityfabric.py, which imports this module's users

    asked = dict(clientarcs.requested(plan.bake))
    streets = plan.era.streets
    if streets and streets[0] and streets[0][0][1] + plan.era.half_z >= streetplan.MIN_LENGTH:
        asked[f"SP_{ENTRANCE}"] = {"id": f"SP_{ENTRANCE}"}
    return asked


def gate_problems(plan: TubePlan) -> list[str]:
    """What the client will ask for against what is baked: ids, count, chain and arcs, and the
    piece budget the client spends them from."""
    import clientarcs

    pieces = plan.pieces()
    asked = client_pieces(plan)
    cut = [piece for piece in pieces if "nodeArcs" in piece]
    problems = clientarcs.verify(plan.bake, cut)
    special = f"SP_{ENTRANCE}"
    baked = {piece["id"] for piece in pieces}
    if (special in asked) != (special in baked):
        problems.append(f"{special}: the client {'asks for' if special in asked else 'never asks for'} it and the bake {'has' if special in baked else 'has not'} it")
    budget = streetplan.budget_value(plan.era.city.get("budget", {}).get("pathPieces"), 0)
    if len(asked) > budget:
        problems.append(f"{len(asked)} pieces asked for, more than budget.pathPieces {budget:g}: the client drops the last ones")
    return problems


def stale_problems(record: dict, blobs: dict[str, bytes], image: bytes, on_disk: dict | None) -> tuple[list[str], str]:
    """Today's bake against the files on disk: a piece is fresh when its GLB is there with today's
    bytes. Returns one line per difference and a tally."""
    known = (on_disk or {}).get("pieces") or {}
    fresh, missing, changed = [], [], []
    for piece_id in sorted(blobs):
        rel = ((known.get(piece_id) or {}).get("meshes") or {}).get(LAYER, {}).get("glb")
        file = os.path.join(REPO_ROOT, rel) if rel else None
        if file is None or not os.path.isfile(file):
            missing.append(piece_id)
            continue
        with open(file, "rb") as handle:
            (fresh if sha256(handle.read()) == sha256(blobs[piece_id]) else changed).append(piece_id)
    retired = sorted(set(known) - set(blobs))
    problems = []
    if missing:
        problems.append(f"{len(missing)} piece(s) have no mesh on disk yet: {', '.join(missing)}")
    if changed:
        problems.append(f"{len(changed)} piece(s) on disk are not today's mesh: {', '.join(changed)}")
    if retired:
        problems.append(f"{len(retired)} piece(s) on disk are no longer baked: {', '.join(retired)}")
    palette_file = ((on_disk or {}).get("palette") or {}).get("file")
    palette_path = os.path.join(REPO_ROOT, palette_file) if palette_file else None
    if palette_path is None or not os.path.isfile(palette_path):
        problems.append("the palette image is not on disk yet")
    else:
        with open(palette_path, "rb") as handle:
            if sha256(handle.read()) != sha256(image):
                problems.append(f"the palette image on disk is not today's: {palette_file}")
    return problems, f"{len(fresh)} piece(s) fresh, {len(missing)} missing, {len(changed)} changed, {len(retired)} retired"


def listing(plan: TubePlan, out_root: str | None) -> int:
    """The piece table and the era's list gate (bake.py's exit codes: 1 a disagreement or a layout
    fault, 2 stale or missing files, 0 neither)."""
    era = plan.era.name
    faults = layout_problems(plan)
    for line in faults:
        warn(line)
    if faults:
        return 1
    record, blobs, image = bake_record(plan, out_root)
    asked = client_pieces(plan)
    log(f"{era}: layout hash {record['layoutHash']}, pipe {plan.era.width:g} wide, decking {plan.bake.spur_width:g}")
    for piece in plan.pieces():
        entry = record["pieces"][piece["id"]]
        seen = asked.get(piece["id"])
        cut = "arc %8.3f-%8.3f" % tuple(piece["nodeArcs"]) if "nodeArcs" in piece else "laid from the start"
        client = "   (never asked for)" if seen is None else "client %8.3f-%8.3f" % tuple(seen["arcs"]) if "arcs" in seen else "client asks"
        log(f"  {piece['id']:<24} {entry['kind']:<5} {entry['meshes'][LAYER]['triangles']:>5} triangles  {cut}  {client}")
    hubs = plan.hubs()
    log(f"  hubs: {len(hubs)} -- " + ", ".join(f"{hub['why']} {streetplan.fmt((round(hub['point'][0], 1), round(hub['point'][1], 1)))}" for hub in hubs))
    totals = record["totals"]
    tube_tris = sum(e["meshes"][LAYER]["triangles"] for e in record["pieces"].values() if e["kind"] == TUBE)
    log(
        f"{era}: {totals['tubes']} tube pieces ({plan.tube_length():.0f} studs, {tube_tris} triangles), "
        f"{totals['decking']} decking pieces ({totals['triangles'] - tube_tris} triangles)"
    )
    problems = gate_problems(plan)
    for line in problems:
        warn(line)
    if problems:
        warn("client/bake disagreement: fix the mirror or the layout, then re-bake and re-upload the pieces named")
        return 1
    log(f"{era}: client/bake check OK -- {len(asked)} piece(s) asked for, ids, count and arcs all agree")
    record_path, _, _ = bake_paths(era, out_root)
    on_disk = None
    if os.path.isfile(record_path):
        with open(record_path, "r", encoding="utf-8") as handle:
            on_disk = json.load(handle)
    stale, tally = stale_problems(record, blobs, image, on_disk)
    for line in stale:
        warn(f"stale mesh: {line}")
    if stale:
        warn(f"{era}: the meshes on disk are STALE or missing ({tally}): bake, upload and harvest before this era is judged in Studio")
        return 2
    log(f"{era}: the meshes on disk are today's ({tally})")
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("era")
    parser.add_argument("--list", action="store_true", help="print the piece table and run the client/bake gate; write nothing")
    parser.add_argument("--dry-run", action="store_true", help="report what would be baked; write nothing")
    parser.add_argument("--piece", action="append", default=[], help="only this piece id (repeatable)")
    parser.add_argument("--out-root", help="bake under this folder (record, meshes and palette) instead of assets/build/paths and assets/paths")
    parser.add_argument("--assets-json", help="check piece ids against this Assets.json instead of the real one")
    args = parser.parse_args(argv)
    cfg.use_assets_path(args.assets_json)
    out_root = os.path.abspath(args.out_root) if args.out_root else None
    plan = TubePlan(args.era, network.load_city())
    if args.list:
        return listing(plan, out_root)
    return bake(plan, args.piece, args.dry_run, out_root)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
