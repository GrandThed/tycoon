#!/usr/bin/env python
"""Swept tubes, flat decking and hub nodes for an era whose streets are tubes (docs/INTERFACES.md
"Wave 4.1b -- organic Orbital").

    py tools/paths/tubes.py OrbitalColony              # write every mesh, print the listing
    py tools/paths/tubes.py OrbitalColony --list       # the listing only, nothing written
    py tools/paths/tubes.py OrbitalColony --out-root DIR

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

For now the meshes are only rendered (tools/testfit/plotrender.py draws them): they are written
under the system temp folder, in a folder named after this checkout, so two worktrees never share
them and nothing lands in the shared assets/build. Colours are plain glTF colour factors, as every
generated kit writes them; the upload route (wave 4.2) bakes them into a palette texture.
"""

from __future__ import annotations

import argparse
import ast
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
import glbtools  # noqa: E402
import network  # noqa: E402
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


def tube_config(era):
    """`road.paths.tube` when the era's streets are swept tubes, else None."""
    paths = era.paths if isinstance(era.paths, dict) else None
    tube = paths.get("tube") if paths else None
    return tube if isinstance(tube, dict) else None


def default_root() -> str:
    """Where this checkout's meshes go: outside every repo, and not shared between worktrees."""
    return os.path.join(tempfile.gettempdir(), "EraCityTycoon", "tubes", os.path.basename(REPO_ROOT))


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
            edges.append(((point[0] + normal[0] * half, 0.0, point[1] + normal[1] * half), (point[0] - normal[0] * half, 0.0, point[1] - normal[1] * half)))
        for (l0, r0), (l1, r1) in zip(edges, edges[1:]):
            mesh.quad("deck", l0, l1, r1, r0, up)
        if round_start:
            point, tangent, normal = self._frame(curve, lo)
            fan = []
            for k in range(CAP_SEGMENTS + 1):
                angle = math.pi * k / CAP_SEGMENTS
                x = point[0] + half * (normal[0] * math.cos(angle) - tangent[0] * math.sin(angle))
                z = point[1] + half * (normal[1] * math.cos(angle) - tangent[1] * math.sin(angle))
                fan.append((x, 0.0, z))
            centre = (point[0], 0.0, point[1])
            for a, b in zip(fan, fan[1:]):
                mesh.tri("deck", centre, a, b, up)

    def deck_mesh(self, piece: dict) -> Mesh:
        """A landmark's apron, the entrance apron or a lane: flat decking at y 0 (the template lifts
        it). The shapes of an apron overlap in one plane and one colour, as two baked path pieces do
        at a node."""
        mesh = Mesh(piece["id"])
        if piece["kind"] == ENTRANCE:
            a, b, c, d = [(p[0], 0.0, p[1]) for p in piece["ground"]]
            mesh.quad("deck", a, b, c, d, (0.0, 1.0, 0.0))
            return mesh
        chain = piece["_chain"]
        curve = chain["final"]
        lo, hi = chain["ext"][0], curve.total - chain["ext"][1]
        if piece["kind"] == "lane":
            # A lane chain runs from its far point (a round end) to its mouth on the tube.
            self._ribbon(mesh, curve, lo, hi, chain["width"] / 2, True)
            return mesh
        self._ribbon(mesh, curve, lo, hi, chain["width"] / 2, False)
        up = (0.0, 1.0, 0.0)
        for _, poly in self.apron_rects(piece["slot"]):
            a, b, c, d = [(p[0], 0.0, p[1]) for p in poly]
            mesh.quad("deck", a, b, c, d, up)
        return mesh

    def mesh_for(self, piece: dict) -> tuple[str, Mesh]:
        if piece["kind"] == "stretch":
            return "Tube", self.tube_mesh(piece)
        return "Deck", self.deck_mesh(piece)

    def write(self, root: str | None = None) -> dict:
        """Every piece as `<root>/<Era>/{Tube,Deck}/<id>.glb`, and `<root>/<Era>/<Era>.json` listing
        them with the hubs. Refuses a layout with a bend under MIN_RADIUS. Returns the listing."""
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


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("era")
    parser.add_argument("--list", action="store_true", help="print the listing, write nothing")
    parser.add_argument("--out-root", help=f"where <Era>/ is written (default {default_root()})")
    args = parser.parse_args(argv)
    plan = TubePlan(args.era, network.load_city())
    problems = plan.radius_problems()
    for problem in problems:
        print(f"   VIOLATION: {problem}")
    if problems:
        return 1
    rows = []
    if args.list:
        for piece in plan.pieces():
            layer, mesh = plan.mesh_for(piece)
            rows.append((piece["id"], layer, mesh.tris))
        root = "(not written)"
    else:
        listing = plan.write(args.out_root)
        rows = [(piece["id"], piece["layer"], piece["tris"]) for piece in listing["pieces"]]
        root = listing["root"]
    for piece_id, layer, tris in rows:
        print(f"   {layer:<5} {piece_id:<24} {tris:>5} triangles")
    hubs = plan.hubs()
    print(f"   hubs: {len(hubs)} -- " + ", ".join(f"{hub['why']} {streetplan.fmt((round(hub['point'][0], 1), round(hub['point'][1], 1)))}" for hub in hubs))
    tubes = [row for row in rows if row[1] == "Tube"]
    print(
        f"{args.era}: {len(tubes)} tube pieces ({plan.tube_length():.0f} studs, {sum(row[2] for row in tubes)} triangles), "
        f"{len(rows) - len(tubes)} decking pieces ({sum(row[2] for row in rows if row[1] == 'Deck')} triangles) -> {root}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
