"""The Forest Road's dresser (L4): one deterministic generator that turns the level's layout into the
real forest, on paper. It writes the baked meshes, the props the client places, the new invisible
character-only walls, and one data file the game reads (src/shared/Config/LevelDress/<layout>.json,
the L4 W2 contract's L4W2-1: Rojo makes it a ModuleScript beside Valley.json).

    py tools/levels/forest.py build      # GLBs + palette into assets/build/levels/ForestRoad/,
                                         # the data file src/shared/Config/LevelDress/ForestRoad.json,
                                         # the upload record assets/build/levels/ForestRoad.json
    py tools/levels/forest.py check      # QA gate (see `check`); writes nothing
    py tools/levels/forest.py stats      # counts only

Inputs: the layout (`src/shared/Layouts/Levels/<layout>.json`, named by the level's config
`src/shared/Config/Levels/1_ForestRoad.json`), Combat.json `levels` (fence thickness), and the kit
(tools/assets/forest_kit.py, imported: the baked trees are the very triangles the kit exports).
Textures come from tools/levels/forest_textures.py (Blender's Python, numpy); `build` does not need
them, the renders and the upload do.

**The rules this generator keeps** (MISSIONS_DESIGN section 26 and the lead's L4 rulings; `check`
proves each one on every run):
  * Dressing never changes collision. Every collidable piece is a layout block, or a new invisible
    character-only wall this generator writes (`barriers`, the ArenaBarrier group: rays and the
    camera pass). Everything baked or placed is walk-through.
  * The forest floor beside the road is closed to players by those walls at the walkable edge,
    except at designed drops: the trailhead gap, the lookout's double-jump gap, the creek (deep
    water, frozen by the frost hammer), and every step between two walkable blocks.
  * No new standable top: a wall's top is unclimbable (43 over every walkable top within 49.3,
    check_levels' rule), and no wall reaches into walkable ground.
  * Inside the plateau region's walking space nothing is taller than 4 studs, except the spawn
    tents, which stand inside their own layout markers (the marker was already there, 8 tall).
  * Camp edges are natural on today's outlines: logs, rocks, stakes and thicket, at most 4 tall,
    gaps at the gates; the 4-stud fence Part stays the collider, hidden.
  * Camp C: nothing of the clearing shows above its wall; the Chief's tent is walk-through.
  * Coplanar faces of two different looks never overlap (they shimmer).

**Frames and units:** the level frame is Roblox world studs, as the layout writes them; yaw in
degrees about +Y the CFrame.Angles way ((x, z) -> (x cos + z sin, -x sin + z cos)). A prop's
origin is its bottom centre and its front faces -Z (the blueprint frame).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import random
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(REPO_ROOT, "tools", "assets"))
import forest_kit as kit  # noqa: E402
import levelmesh as lm  # noqa: E402
from forest_palette import BARK, CAMP, FOLIAGE, GROUND, ROCK  # noqa: E402
from levelmesh import Bake, Rect, hash01, lerp, smoothstep  # noqa: E402

GENERATOR = "EraCityTycoon levels/forest"
GENERATOR_VERSION = 1
LEVEL_CONFIG = os.path.join(REPO_ROOT, "src", "shared", "Config", "Levels", "1_ForestRoad.json")
LAYOUT_DIR = os.path.join(REPO_ROOT, "src", "shared", "Layouts", "Levels")
COMBAT_JSON = os.path.join(REPO_ROOT, "src", "shared", "Config", "Combat.json")
OUT_ROOT = os.path.join(REPO_ROOT, "assets", "build", "levels")
DRESS_DIR = os.path.join(REPO_ROOT, "src", "shared", "Config", "LevelDress")

# check_levels' constants this generator must agree with (tools/check_levels.py; restated, since
# importing it pulls in the simulator). UNCLIMB: a wall top is out of reach when it stands this far
# over every walkable top within UNCLIMB_REACH.
UNCLIMB = 43.0
UNCLIMB_REACH = 49.3
COVER_MAX = 3.5
REGION_PIECE_MAX = 4.0  # the lead's rule for the region's walking space
ORIGIN_LIMIT = 1000.0
TRI_BUDGET = 150000  # the whole level at the game camera (the lead's budget); check fails at +10%

# ---------------------------------------------------------------- art numbers (this level's own)
# They are part of the plan hash: changing any of them changes the bake.

ART = {
    "grid": 2.0,  # heightfield cell, studs
    "domainMargin": 90.0,  # forest floor this far past every walkable block
    "lifts": {"floor": 0.0, "rim": 0.03, "camp": 0.06, "decal": 0.075, "road": 0.09, "top": 0.06},
    "edgeAmp": 0.55,  # a road's noisy edge, studs either way of the block edge
    "rimWidth": 0.45,
    "roadTile": 12.0,  # studs per texture repeat
    "floorTile": 16.0,
    "campTile": 14.0,
    "zones": {
        # The visible ground is three levels, the heights the layout's floors already use: the low
        # forest (0) by the trailhead, creek and cave mouth, the plateau (8) the road climbs onto at
        # Road5, and the highland (12) of the Chief's massif. A lip is a meandering cliff line, exact
        # where the road climbs it.
        "levels": [0.0, 8.0, 12.0],
        "lips": [
            {"x": -302.0, "amp": 7.0, "seed": 11.0, "exact": [-56.0, -32.0], "northX": -352.0, "northZ": -84.0},
            {"x": 230.0, "amp": 5.0, "seed": 12.0, "exact": [-56.0, -32.0]},
        ],
        "band": 3.0,  # a lip's slope, studs, on its low side
    },
    "ravine": {
        "depth": 20.0,  # under the rim: below killY, so a fall never touches the visible floor
        "wall": 2.2,
        # The gully the two designed drops open into, carried on past them as scenery: north round
        # the lookout's rock and south into the creek.
        "extra": [[-436.0, -422.0, -52.0, -8.0], [-438.0, -424.0, 8.0, 44.0], [-438.0, -408.0, 34.0, 46.0], [-462.0, -434.0, -48.0, -40.0]],
    },
    "water": {"bed": -3.6, "bank": 4.0},
    "slab": {"row": [4.0, 8.5], "width": [5.0, 12.0], "thin": [0.1, 0.25], "thick": [0.5, 2.2], "overlap": 0.35},
    "trees": {"near": [5.0, 11.0], "mid": [11.0, 19.0], "nearStep": 7.2, "midStep": 7.8},
    "blanket": {"start": 17.0, "cell": 10.0, "under": 6.5, "low": 14.0, "high": 27.0},
    "massif": {"reach": 28.0, "margin": 3.0, "slope": 2.2},
    "backdrop": {"inner": 40.0, "outer": 520.0, "ring": 20, "rows": 6, "peak": [40.0, 110.0]},
    "camps": {"clutterA": 12, "clutterB": 20, "clutterC": 12, "seats": 4},
}

CHIEF_SCALE = 1.25  # the hall at 33 wide, 19 tall: the clearing's one big shape

# Which pieces the client places as props: the ones a run touches (a fire's flames and light, the
# tent the tent raiders step out of, the hall the Chief steps out of). Everything else is baked.
PROP_PIECES = ("Campfire", "SpawnTent", "ChiefTent")

# Proposed Expeditions.json looks for W2 (the parts the dressing keeps visible): a wooden sign,
# a darker bramble, forest water, a log gate. The renders draw them; W2 applies them by config.
LOOKS = {
    "sign": {"material": "Wood", "color": [124, 88, 56]},
    "bramble": {"material": "LeafyGrass", "color": [62, 84, 34]},
    "water": {"material": "SmoothPlastic", "color": [52, 80, 82], "transparency": 0.3},
    "gate": {"material": "Wood", "color": [104, 74, 50]},
}

TEXTURES = {
    "forestFloor": {"tile": ART["floorTile"]},
    "road": {"tile": ART["roadTile"]},
    "roadRim": {"tile": ART["roadTile"]},
    "camp": {"tile": ART["campTile"]},
}

# The Normal raiders' kinds as the renders draw them (ProvingGrounds.json crowd.kinds), for levelrender.
SIDES = {"north": (0, -1), "south": (0, 1), "west": (-1, 0), "east": (1, 0)}


def log(msg: str) -> None:
    print(f"[forest] {msg}", flush=True)


# ---------------------------------------------------------------- the layout


class Walk:
    """A walkable top: a block of a ground look, or a camp's floor."""

    def __init__(self, name, rect, top, kind):
        self.name, self.rect, self.top, self.kind = name, rect, top, kind

    def __repr__(self):
        return f"Walk({self.name}, {self.rect}, {self.top}, {self.kind})"


class Solid:
    """A collidable box the layout builds (walls, roofs, fences), in world studs."""

    def __init__(self, name, x0, x1, y0, y1, z0, z1, kind):
        self.name, self.kind = name, kind
        self.lo = [x0, y0, z0]
        self.hi = [x1, y1, z1]

    @property
    def rect(self):
        return Rect(self.lo[0], self.hi[0], self.lo[2], self.hi[2])


class Level:
    def __init__(self, config_path=LEVEL_CONFIG):
        with open(config_path, encoding="utf-8") as fh:
            self.config = json.load(fh)
        self.layout_name = self.config["layout"]
        self.layout_path = os.path.join(LAYOUT_DIR, self.layout_name + ".json")
        with open(self.layout_path, encoding="utf-8") as fh:
            self.layout = json.load(fh)
        with open(COMBAT_JSON, encoding="utf-8") as fh:
            combat = json.load(fh)
        self.fence_default = float(combat["levels"]["fenceThickness"])
        lay = self.layout
        self.kill_y = float(lay["killY"])
        self.barrier = lay.get("barrier") or {"height": 80.0, "thickness": 8.0}
        self.blocks = {b["name"]: b for b in lay["blocks"]}
        self.camps = {c["id"]: c for c in lay.get("camps") or []}
        self.walks: list[Walk] = []
        self.water: list[Walk] = []
        self.solids: list[Solid] = []
        for b in lay["blocks"]:
            top = b["y"] + b["sy"] / 2
            look = b["look"]
            r = Rect.of(b)
            if look in ("path", "ground") and b.get("collide", True) is not False:
                self.walks.append(Walk(b["name"], r, top, look))
            elif look == "water":
                self.water.append(Walk(b["name"], r, top, "water"))
            elif look == "wall" and b.get("collide", True) is not False:
                self.solids.append(Solid(b["name"], r.x0, r.x1, b["y"] - b["sy"] / 2, top, r.z0, r.z1, "wall"))
        for cid, c in self.camps.items():
            r = Rect(c["x"] - c["sx"] / 2, c["x"] + c["sx"] / 2, c["z"] - c["sz"] / 2, c["z"] + c["sz"] / 2)
            self.walks.append(Walk(f"Camp_{cid}", r, float(c["y"]), "camp"))
            for k, box in enumerate(self.fence_boxes(c)):
                x0, x1, y0, y1, z0, z1 = box
                self.solids.append(Solid(f"Fence_{cid}_{k}", x0, x1, y0, y1, z0, z1, "fence"))
        self.region_cells = []
        for region in lay.get("regions") or []:
            y = float(region["y"])
            for cell in region["cells"]:
                self.region_cells.append((cell["id"], Rect.of(cell), y))
            for cid in region.get("camps") or []:
                c = self.camps[cid]
                self.region_cells.append((f"Camp_{cid}", Rect(c["x"] - c["sx"] / 2, c["x"] + c["sx"] / 2, c["z"] - c["sz"] / 2, c["z"] + c["sz"] / 2), y))
        # Pillars: a walkable block standing far over the ground around it (the lookout ledge). It
        # gets rock faces like a wall and a walkable top skin; the heightfield does not climb it.
        self.pillars = [w for w in self.walks if w.kind == "ground" and w.top - self.zone_level((w.rect.x0 + w.rect.x1) / 2, (w.rect.z0 + w.rect.z1) / 2) > 2.0]
        for w in self.pillars:
            b = self.blocks[w.name]
            self.solids.append(Solid(w.name, w.rect.x0, w.rect.x1, b["y"] - b["sy"] / 2, w.top, w.rect.z0, w.rect.z1, "pillar"))
        self.drops = self.find_drops()
        self.roofed = {w.name for w in self.walks if w.kind == "path" and self.is_roofed(w)}

    # -- camps ------------------------------------------------------------------------------

    def fence_thickness(self, camp) -> float:
        own = (camp.get("fence") or {}).get("thickness")
        return float(own) if isinstance(own, (int, float)) and own > 0 else self.fence_default

    def fence_boxes(self, camp):
        """LevelGeometry.FenceBoxes, mirrored: per side the stretches no gate opens, outside the
        floor's edge, `thickness` deep; north and south run past west and east."""
        fence = camp.get("fence") or {}
        height = float(fence.get("height") or 0)
        t = self.fence_thickness(camp)
        out = []
        if height <= 0:
            return out
        x, y, z, sx, sz = camp["x"], camp["y"], camp["z"], camp["sx"], camp["sz"]
        for name in ("north", "south", "west", "east"):
            along_x = name in ("north", "south")
            sign = -1 if name in ("north", "west") else 1
            half = (sx if along_x else sz) / 2
            reach = half + t if along_x else half
            cuts = []
            for g in camp.get("gates") or []:
                if g["side"] != name:
                    continue
                a = max(g["at"] - g["width"] / 2, -half)
                b = min(g["at"] + g["width"] / 2, half)
                if b > a:
                    cuts.append((a, b))
            for a, b in lm.subtract_intervals(-reach, reach, cuts):
                if along_x:
                    zc = z + sign * (sz / 2 + t / 2)
                    out.append((x + a, x + b, y, y + height, zc - t / 2, zc + t / 2))
                else:
                    xc = x + sign * (sx / 2 + t / 2)
                    out.append((xc - t / 2, xc + t / 2, y, y + height, z + a, z + b))
        return out

    def gate_spans(self, camp):
        """(side, a, b) of every gate, offsets along the side from the camp's centre."""
        out = []
        for g in camp.get("gates") or []:
            half = (camp["sx"] if g["side"] in ("north", "south") else camp["sz"]) / 2
            out.append((g["side"], max(g["at"] - g["width"] / 2, -half), min(g["at"] + g["width"] / 2, half)))
        return out

    # -- derived ----------------------------------------------------------------------------

    def is_roofed(self, w: Walk) -> bool:
        covered = 0.0
        for s in self.solids:
            if s.kind == "wall" and s.lo[1] > w.top + 4 and w.rect.overlaps(s.rect):
                r = s.rect
                covered += max(0.0, min(r.x1, w.rect.x1) - max(r.x0, w.rect.x0)) * max(0.0, min(r.z1, w.rect.z1) - max(r.z0, w.rect.z0))
        return covered >= 0.5 * w.rect.area()

    def find_drops(self) -> list[Rect]:
        """The designed drops a player may fall into, as rectangles of void that belong to the
        walkable whole (no wall between them and the ground they open off):
          * a route leg marked `via: gap`: the void between the two blocks it jumps, the road's width;
          * a double-jump secret's ledge: the void between the ledge and the nearest walkable block
            across from it, over their shared span (the lookout's 18-stud gap)."""
        drops = []
        route = self.layout.get("route") or []
        for a, b in zip(route, route[1:]):
            if b.get("via") != "gap":
                continue
            wa = self.walk_at(a["x"], a["z"], a.get("y"))
            wb = self.walk_at(b["x"], b["z"], b.get("y"))
            if wa is None or wb is None:
                continue
            ra, rb = wa.rect, wb.rect
            if abs(a["z"] - b["z"]) < 1e-6:
                x0, x1 = (ra.x1, rb.x0) if ra.x1 <= rb.x0 else (rb.x1, ra.x0)
                drops.append(Rect(x0, x1, max(ra.z0, rb.z0), min(ra.z1, rb.z1)))
            else:
                z0, z1 = (ra.z1, rb.z0) if ra.z1 <= rb.z0 else (rb.z1, ra.z0)
                drops.append(Rect(max(ra.x0, rb.x0), min(ra.x1, rb.x1), z0, z1))
        for s in self.layout.get("secrets") or []:
            if s.get("needs") != "doubleJump":
                continue
            ledge = next((w for w in self.pillars if w.rect.contains(s["x"], s["z"])), None)
            if ledge is None:
                continue
            best = None
            for w in self.walks:
                if w is ledge:
                    continue
                r, L = w.rect, ledge.rect
                if min(r.x1, L.x1) - max(r.x0, L.x0) > 4:  # across in z
                    gap = r.z0 - L.z1 if r.z0 >= L.z1 else L.z0 - r.z1 if r.z1 <= L.z0 else None
                    if gap is not None and gap > 0 and (best is None or gap < best[0]):
                        lo, hi = (L.z1, r.z0) if r.z0 >= L.z1 else (r.z1, L.z0)
                        best = (gap, Rect(max(r.x0, L.x0), min(r.x1, L.x1), lo, hi))
                if min(r.z1, L.z1) - max(r.z0, L.z0) > 4:  # across in x
                    gap = r.x0 - L.x1 if r.x0 >= L.x1 else L.x0 - r.x1 if r.x1 <= L.x0 else None
                    if gap is not None and gap > 0 and (best is None or gap < best[0]):
                        lo, hi = (L.x1, r.x0) if r.x0 >= L.x1 else (r.x1, L.x0)
                        best = (gap, Rect(lo, hi, max(r.z0, L.z0), min(r.z1, L.z1)))
            if best is not None:
                drops.append(best[1])
        return drops

    def walk_at(self, x, z, y=None):
        best = None
        for w in self.walks:
            if w.rect.contains(x, z, 0.01) and (y is None or abs(w.top - y) < 0.6):
                if best is None or w.top > best.top:
                    best = w
        return best

    def zone_level(self, x, z) -> float:
        """The ground level of the zone (x, z) lies in, with each lip's slope on its low side."""
        levels = ART["zones"]["levels"]
        band = ART["zones"]["band"]
        h = levels[0]
        for k, lip in enumerate(ART["zones"]["lips"]):
            lx = self.lip_x(lip, z)
            t = smoothstep(lx - band, lx, x)
            h = lerp(h, levels[k + 1], t) if t > 0 else h
        return h

    def lip_x(self, lip, z) -> float:
        if "northZ" in lip and z < lip["northZ"]:
            return lip["northX"]
        e0, e1 = lip["exact"]
        # No meander where the road climbs the lip: the cliff meets the step exactly.
        weight = min((1.0 - smoothstep(e0 - 12.0, e0, z)) + smoothstep(e1, e1 + 12.0, z), 1.0)
        n = NOISE.fbm(z / 40.0, lip["seed"], seed=lip["seed"])
        return lip["x"] + lip["amp"] * n * weight

    # -- the walkable whole ---------------------------------------------------------------

    def union_parts(self):
        """Everything a player may stand on, fall through on purpose, or wade into: walkable
        blocks (pillars too), camp floors grown by an open camp's fence (its top is in reach),
        water, and the designed drops. (rect, reference top, kind)."""
        parts = []
        for w in self.walks:
            r = w.rect
            if w.kind == "camp":
                camp = self.camps[w.name.split("_", 1)[1]]
                if not camp.get("locks"):
                    r = r.grown(self.fence_thickness(camp))
            parts.append((r, w.top, w.kind, w.name))
        for w in self.water:
            parts.append((w.rect, w.top, "water", w.name))
        for k, d in enumerate(self.drops):
            parts.append((d, None, "drop", f"Drop{k + 1}"))
        return parts


NOISE = lm.Noise(20261021)


# ---------------------------------------------------------------- invisible walls


def barriers(level: Level):
    """The walls at the walkable edge: every stretch of the walkable whole's outline that no layout
    wall already closes, one box per stretch, outside it, from killY - 2 to `barrier.height` over
    the highest walkable top within 20 studs. Thickness `barrier.thickness`, cut short of any other
    walkable ground; each stretch runs on past its ends by its thickness, so outer corners close."""
    parts = level.union_parts()
    rects = [p[0] for p in parts]
    eps = 1e-4
    lines: dict[tuple, list] = {}
    for rect, _top, _kind, _name in parts:
        for side, (nx, nz) in SIDES.items():
            if nx:
                c = rect.x1 if nx > 0 else rect.x0
                lo, hi = rect.z0, rect.z1
                cuts = [(o.z0, o.z1) for o in rects if o is not rect and (o.x0 <= c + eps if nx > 0 else o.x1 >= c - eps)
                        and (o.x1 > c + eps if nx > 0 else o.x0 < c - eps)]
            else:
                c = rect.z1 if nz > 0 else rect.z0
                lo, hi = rect.x0, rect.x1
                cuts = [(o.x0, o.x1) for o in rects if o is not rect and (o.z0 <= c + eps if nz > 0 else o.z1 >= c - eps)
                        and (o.z1 > c + eps if nz > 0 else o.z0 < c - eps)]
            for a, b in lm.subtract_intervals(lo, hi, cuts):
                lines.setdefault((side, round(c, 4)), []).append((a, b))
    tall = [s for s in level.solids if s.kind in ("wall", "fence", "pillar")]
    walk_tops = [(w.rect, w.top) for w in level.walks]
    out = []
    for (side, c), spans in sorted(lines.items(), key=lambda kv: (kv[0][0], kv[0][1])):
        nx, nz = SIDES[side]
        merged = []
        for a, b in sorted(spans):
            if merged and a <= merged[-1][1] + 1e-6:
                merged[-1] = (merged[-1][0], max(merged[-1][1], b))
            else:
                merged.append((a, b))
        for a, b in merged:
            ref = reference_top(walk_tops, side, c, a, b, 20.0)
            # A layout wall standing right outside, unclimbably tall, already closes the stretch.
            cover = []
            for s in tall:
                r = s.rect
                if s.hi[1] < ref + UNCLIMB:
                    continue
                probe_in = (r.x0 <= c + 0.5 * nx <= r.x1) if nx else (r.z0 <= c + 0.5 * nz <= r.z1)
                if probe_in:
                    cover.append((r.z0, r.z1) if nx else (r.x0, r.x1))
            for a2, b2 in lm.subtract_intervals(a, b, cover):
                if b2 - a2 < 0.25:
                    continue
                depth = float(level.barrier["thickness"])
                for o in rects:
                    if nx:
                        if o.z1 <= a2 + eps or o.z0 >= b2 - eps:
                            continue
                        gap = (o.x0 - c) if nx > 0 else (c - o.x1)
                    else:
                        if o.x1 <= a2 + eps or o.x0 >= b2 - eps:
                            continue
                        gap = (o.z0 - c) if nz > 0 else (c - o.z1)
                    if gap > eps:
                        depth = min(depth, gap - 0.5)
                depth = max(depth, 1.0)
                ext0 = ext1 = depth
                lo_y = level.kill_y - 2.0
                hi_y = ref + float(level.barrier["height"])
                a3, b3 = a2 - ext0, b2 + ext1
                # Never run on into walkable ground past an end.
                for o in rects:
                    if nx:
                        inside = (o.x0 < c + nx * depth and o.x1 > c) if nx > 0 else (o.x1 > c - depth and o.x0 < c)
                        if inside:
                            if o.z1 <= a2 + eps:
                                a3 = max(a3, o.z1)
                            if o.z0 >= b2 - eps:
                                b3 = min(b3, o.z0)
                    else:
                        inside = (o.z0 < c + nz * depth and o.z1 > c) if nz > 0 else (o.z1 > c - depth and o.z0 < c)
                        if inside:
                            if o.x1 <= a2 + eps:
                                a3 = max(a3, o.x1)
                            if o.x0 >= b2 - eps:
                                b3 = min(b3, o.x0)
                if nx:
                    x0, x1 = (c, c + depth) if nx > 0 else (c - depth, c)
                    box = {"x": (x0 + x1) / 2, "z": (a3 + b3) / 2, "sx": depth, "sz": b3 - a3}
                else:
                    z0, z1 = (c, c + depth) if nz > 0 else (c - depth, c)
                    box = {"x": (a3 + b3) / 2, "z": (z0 + z1) / 2, "sx": b3 - a3, "sz": depth}
                box["y"] = (lo_y + hi_y) / 2
                box["sy"] = hi_y - lo_y
                box["side"] = side
                box["edge"] = [round(c, 3), round(a2, 3), round(b2, 3)]
                out.append(box)
    for k, box in enumerate(out):
        box["name"] = f"TreeLine{k + 1}"
        for key in ("x", "y", "z", "sx", "sy", "sz"):
            box[key] = round(box[key], 3)
    return out


def reference_top(walk_tops, side, c, a, b, reach):
    nx, nz = SIDES[side]
    best = -math.inf
    for r, top in walk_tops:
        if nx:
            dx = max(0.0, r.x0 - c, c - r.x1)
            dz = max(0.0, r.z0 - b, a - r.z1)
        else:
            dz = max(0.0, r.z0 - c, c - r.z1)
            dx = max(0.0, r.x0 - b, a - r.x1)
        if math.hypot(dx, dz) <= reach:
            best = max(best, top)
    return best if best > -math.inf else 0.0


# ---------------------------------------------------------------- the ground


class Ground:
    """The forest floor as a heightfield on an ART.grid lattice over the domain: three zone levels
    with meandering lips, the gully under the designed drops, creek and pond beds with banks, and
    every flat walkable block's top held exactly (its skin lies on it). Pillars are left to their
    rock faces."""

    def __init__(self, level: Level):
        self.level = level
        g = ART["grid"]
        xs, zs = [], []
        for w in level.walks + level.water:
            xs += [w.rect.x0, w.rect.x1]
            zs += [w.rect.z0, w.rect.z1]
        for s in level.solids:
            xs += [s.lo[0], s.hi[0]]
            zs += [s.lo[2], s.hi[2]]
        m = ART["domainMargin"]
        self.x0 = math.floor((min(xs) - m) / 8) * 8
        self.x1 = math.ceil((max(xs) + m) / 8) * 8
        self.z0 = math.floor((min(zs) - m) / 8) * 8
        self.z1 = math.ceil((max(zs) + m) / 8) * 8
        self.nx = int(round((self.x1 - self.x0) / g))
        self.nz = int(round((self.z1 - self.z0) / g))
        self.g = g
        self.flats = [w for w in level.walks if w not in level.pillars]
        self.islands = {w.name for w in self.flats for wt in level.water
                        if wt.rect.x0 <= w.rect.x0 and w.rect.x1 <= wt.rect.x1 and wt.rect.z0 <= w.rect.z0 and w.rect.z1 <= wt.rect.z1}
        self.ravine = [Rect(*r) for r in ART["ravine"]["extra"]] + list(level.drops)
        # A walled camp sits in a rock massif that rises from the forest to its wall's top, held
        # off every other walkable block by a steep bank (the gatehouse and the trail's end become
        # notches in it). Nobody stands on it: the tree-line walls keep players off.
        self.massifs = []
        for cid, camp in level.camps.items():
            if not camp.get("locks"):
                continue
            t = level.fence_thickness(camp)
            fenced = Rect(camp["x"] - camp["sx"] / 2 - t, camp["x"] + camp["sx"] / 2 + t, camp["z"] - camp["sz"] / 2 - t, camp["z"] + camp["sz"] / 2 + t)
            top = float(camp["y"]) + float((camp.get("fence") or {}).get("height") or 0)
            others = [w.rect for w in level.walks if w.name != f"Camp_{cid}"]
            self.massifs.append((fenced, top, others))
        self.h = [[0.0] * (self.nx + 1) for _ in range(self.nz + 1)]
        for j in range(self.nz + 1):
            z = self.z0 + j * g
            row = self.h[j]
            for i in range(self.nx + 1):
                row[i] = self.height(self.x0 + i * g, z)

    def over_water(self, x, z) -> bool:
        return any(w.rect.contains(x, z) for w in self.level.water)

    def height(self, x, z) -> float:
        lv = self.level
        base = lv.zone_level(x, z)
        held = None
        for w in self.flats:
            # A road over water is a bridge (the bed runs on under its deck); an island, wholly
            # inside the water, is ground.
            if w.rect.contains(x, z, 1e-6) and (w.name in self.islands or not any(wt.rect.contains(x, z, -1e-6) for wt in lv.water)):
                held = w.top if held is None else min(held, w.top)
        if held is not None:
            return held
        h = base
        for fenced, top, others in self.massifs:
            ms = ART["massif"]
            d = fenced.distance(x, z)
            if 0.0 < d < ms["reach"] * 1.3:
                reach = ms["reach"] * (0.85 + 0.3 * (0.5 + 0.5 * NOISE.n2(x / 30.0, z / 30.0, 31.0)))
                prof = max(0.0, 1.0 - d / reach) ** 0.75 * (top - base)
                dw = min(r.distance(x, z) for r in others)
                cap = (dw - ms["margin"]) * ms["slope"]
                bump = 2.5 * NOISE.n2(x / 9.0, z / 9.0, 32.0) * min(1.0, prof / 10.0)
                h = max(h, base + max(0.0, min(prof + bump, cap)))
        # the gully
        depth_in = max((-r.signed(x, z) for r in self.ravine if r.contains(x, z)), default=None)
        if depth_in is not None:
            rv = ART["ravine"]
            floor = base - rv["depth"] + 1.2 * NOISE.n2(x / 7.0, z / 7.0, 5.0)
            return lerp(base, floor, smoothstep(0.0, rv["wall"], depth_in))
        # water: the bed inside, a low bank outside
        for w in lv.water:
            if w.rect.contains(x, z):
                # The shore line stands a hair over the water's top: no ground face lies in the
                # water Part's top plane (they would shimmer).
                d = -w.rect.signed(x, z)
                return lerp(w.top + 0.06, ART["water"]["bed"], smoothstep(0.0, 3.0, d))
        dw = min((w.rect.distance(x, z) for w in lv.water), default=math.inf)
        if dw < ART["water"]["bank"]:
            return lerp(min(base, lv.water[0].top + 0.45), base, smoothstep(0.0, ART["water"]["bank"], dw))
        return h

    def steep(self, x, z, limit=1.4) -> bool:
        """Is the ground here steeper than `limit` (rise over run)? Trees stay off cliffs."""
        g = self.g
        dx = self.at(x + g, z) - self.at(x - g, z)
        dz = self.at(x, z + g) - self.at(x, z - g)
        return math.hypot(dx, dz) / (2 * g) > limit

    def at(self, x, z) -> float:
        """Bilinear height between lattice points (clamped to the domain)."""
        fx = (x - self.x0) / self.g
        fz = (z - self.z0) / self.g
        i = min(max(int(math.floor(fx)), 0), self.nx - 1)
        j = min(max(int(math.floor(fz)), 0), self.nz - 1)
        tx = min(max(fx - i, 0.0), 1.0)
        tz = min(max(fz - j, 0.0), 1.0)
        h = self.h
        a = lerp(h[j][i], h[j][i + 1], tx)
        b = lerp(h[j + 1][i], h[j + 1][i + 1], tx)
        return lerp(a, b, tz)

    def meshes(self):
        """(textured flat triangles, palette slope triangles). Flat cells of one height are merged
        into rectangles (planar UVs make the merge lossless); a merged edge only ever meets
        neighbours at that same height, so a T-junction there is collinear and shows no crack."""
        g, h = self.g, self.h
        flat_tris, pal_tris = [], []
        nx, nz = self.nx, self.nz
        flat = [[False] * nx for _ in range(nz)]
        for j in range(nz):
            for i in range(nx):
                a, b, c, d = h[j][i], h[j][i + 1], h[j + 1][i + 1], h[j + 1][i]
                flat[j][i] = max(a, b, c, d) - min(a, b, c, d) < 1e-6
        used = [[False] * nx for _ in range(nz)]
        lift = ART["lifts"]["floor"]
        for j in range(nz):
            for i in range(nx):
                if used[j][i] or not flat[j][i]:
                    continue
                y = h[j][i]
                w = 1
                while i + w < nx and flat[j][i + w] and not used[j][i + w] and h[j][i + w] == y:
                    w += 1
                d = 1
                while j + d < nz and all(flat[j + d][i + k] and not used[j + d][i + k] and h[j + d][i + k] == y for k in range(w)):
                    d += 1
                for jj in range(j, j + d):
                    for ii in range(i, i + w):
                        used[jj][ii] = True
                x0, x1 = self.x0 + i * g, self.x0 + (i + w) * g
                z0, z1 = self.z0 + j * g, self.z0 + (j + d) * g
                yy = y + lift
                p = [(x0, yy, z0), (x1, yy, z0), (x1, yy, z1), (x0, yy, z1)]
                flat_tris.append(up(p[0], p[1], p[2]))
                flat_tris.append(up(p[0], p[2], p[3]))
        for j in range(nz):
            for i in range(nx):
                if flat[j][i]:
                    continue
                x0, x1 = self.x0 + i * g, self.x0 + (i + 1) * g
                z0, z1 = self.z0 + j * g, self.z0 + (j + 1) * g
                p = [(x0, h[j][i], z0), (x1, h[j][i + 1], z0), (x1, h[j + 1][i + 1], z1), (x0, h[j + 1][i], z1)]
                # Split along the diagonal that keeps the surface convex-ish (the lower pair).
                if abs(p[0][1] - p[2][1]) <= abs(p[1][1] - p[3][1]):
                    quads = ((p[0], p[1], p[2]), (p[0], p[2], p[3]))
                else:
                    quads = ((p[0], p[1], p[3]), (p[1], p[2], p[3]))
                for t in quads:
                    a, b, c = up(*t)
                    rise = max(a[1], b[1], c[1]) - min(a[1], b[1], c[1])
                    if rise < 0.3 and min(a[1], b[1], c[1]) > -0.95:
                        flat_tris.append((a, b, c))
                    else:
                        pal_tris.append((a, b, c, self.slope_colour(a, b, c, rise)))
        return flat_tris, pal_tris

    def slope_colour(self, a, b, c, rise):
        y = (a[1] + b[1] + c[1]) / 3
        cx, cz = (a[0] + b[0] + c[0]) / 3, (a[2] + b[2] + c[2]) / 3
        if y < -14.0:
            return GROUND.GULLY if hash01(cx, cz) < 0.7 else ROCK.ROCK_DARK
        if self.over_water(cx, cz):
            return GROUND.MUD
        if rise > 2.5:
            k = hash01(cx * 0.31, cz * 0.17, y)
            return ROCK.ROCK_DARK if k < 0.4 else ROCK.ROCK if k < 0.8 else ROCK.ROCK_LIGHT
        if rise > 1.0 or y < -0.9:
            return GROUND.MUD if hash01(cx, cz) < 0.5 else ROCK.ROCK_DARK
        return GROUND.NEEDLES if hash01(cx, cz, 2.0) < 0.6 else GROUND.FLOOR_DARK


def up(a, b, c):
    n = lm.tri_normal(a, b, c)
    return (a, c, b) if n[1] < 0 else (a, b, c)


# ---------------------------------------------------------------- road, camp and ledge skins


def edge_state(level: Level, parts, x, z, w: Walk):
    """What lies just outside a skin's edge point: "same" (more walkable ground at this top: the
    skin runs on under it), "camp", "step" (walkable ground at another top), "open" (water or a
    drop: no overhang), or "edge" (the walled forest)."""
    for rect, top, kind, name in parts:
        if name == w.name or not rect.contains(x, z, 1e-6):
            continue
        if kind in ("water", "drop"):
            return "open"
        if kind == "camp" and w.kind != "camp":
            return "camp" if abs(top - w.top) < 0.6 else "step"
        if top is not None and abs(top - w.top) < 0.6:
            return "same"
        return "step"
    return "edge"


def ribbon(level: Level, ground: Ground, parts, w: Walk, lift: float, rim: bool, spans=None, grow=0.0, seed=0.0):
    """A walkable rectangle's skin as a ribbon along its longer axis: stations every stud, three
    columns (edge, centre, edge), each long edge pushed out over its neighbours where the ground
    goes on, cut by smooth noise where it meets the walled forest, held in where it opens onto
    water or a drop. `spans` limits the long axis (a bridge cuts a road in two)."""
    r = w.rect
    along_x = (r.x1 - r.x0) >= (r.z1 - r.z0)
    a0, a1 = (r.x0, r.x1) if along_x else (r.z0, r.z1)
    c0, c1 = (r.z0, r.z1) if along_x else (r.x0, r.x1)
    amp = ART["edgeAmp"]
    rimw = ART["rimWidth"] if rim else 0.0
    tris = []
    for s0, s1 in spans or [(a0, a1)]:
        # Ends: run on into the same ground or a camp, stop flush at a step or an opening.
        def end_reach(at, sign):
            mid = (c0 + c1) / 2
            px, pz = (at + sign * 0.3, mid) if along_x else (mid, at + sign * 0.3)
            state = edge_state(level, parts, px, pz, w)
            if state == "same":
                return 0.6 + grow
            if state == "camp":
                return 5.0
            if state in ("step", "open"):
                return -0.05 if not rim else 0.0
            return 0.0 + grow

        e0 = s0 - end_reach(s0, -1) if not (spans and s0 > a0 + 1e-6) else s0 + 0.05
        e1 = s1 + end_reach(s1, 1) if not (spans and s1 < a1 - 1e-6) else s1 - 0.05
        n = max(2, int(math.ceil((e1 - e0) / 1.5)))
        stations = []
        for k in range(n + 1):
            t = e0 + (e1 - e0) * k / n
            offs = []
            for side_sign, cc in ((-1, c0), (1, c1)):
                px, pz = (t, cc + side_sign * 0.3) if along_x else (cc + side_sign * 0.3, t)
                state = edge_state(level, parts, px, pz, w)
                line_seed = round(cc, 3) * 0.7 + (1.3 if along_x else 2.9) + seed
                if state == "same" or state == "camp":
                    off = 0.6 + grow
                elif state in ("open", "step"):
                    off = -0.08
                else:
                    off = amp * lm.edge_noise(t, line_seed) - 0.12 + grow
                off += rimw + (0.15 * lm.edge_noise(t * 1.7, line_seed + 4.0) if rim else 0.0)
                offs.append(off)
            # Taper the tips that run out into a camp (the road fades into the camp's earth).
            taper = 1.0
            if t < s0 - 0.6 or t > s1 + 0.6:
                over = (s0 - t) if t < s0 else (t - s1)
                taper = max(0.15, 1.0 - over / 6.0)
            mid = (c0 + c1) / 2
            half = (c1 - c0) / 2
            left = mid - (half + offs[0]) * taper
            right = mid + (half + offs[1]) * taper
            stations.append((t, left, mid, right))
        for (t0, l0, m0, r0), (t1, l1, m1, r1) in zip(stations, stations[1:]):
            y0 = w.top + lift
            row0 = [pt(along_x, t0, l0, y0), pt(along_x, t0, m0, y0), pt(along_x, t0, r0, y0)]
            row1 = [pt(along_x, t1, l1, y0), pt(along_x, t1, m1, y0), pt(along_x, t1, r1, y0)]
            for k in range(2):
                tris.append(up(row0[k], row0[k + 1], row1[k + 1]))
                tris.append(up(row0[k], row1[k + 1], row1[k]))
    return tris


def pt(along_x, t, c, y):
    return (t, y, c) if along_x else (c, y, t)


def bridge_spans(level: Level, w: Walk):
    """A road's stretches off the water, and the water crossings (the creek under Road2)."""
    r = w.rect
    along_x = (r.x1 - r.x0) >= (r.z1 - r.z0)
    a0, a1 = (r.x0, r.x1) if along_x else (r.z0, r.z1)
    crossings = []
    for wt in level.water:
        q = wt.rect
        if not q.overlaps(r):
            continue
        if along_x and q.z0 <= r.z0 + 1e-6 and q.z1 >= r.z1 - 1e-6:
            crossings.append((max(q.x0, a0), min(q.x1, a1)))
        elif not along_x and q.x0 <= r.x0 + 1e-6 and q.x1 >= r.x1 - 1e-6:
            crossings.append((max(q.z0, a0), min(q.z1, a1)))
    return lm.subtract_intervals(a0, a1, crossings), crossings, along_x


def bridge_deck(w: Walk, crossing, along_x, bake: Bake):
    """A log bridge where a road crosses water: planks across the road (their top at the road's
    skin height), two log stringers under them, both well clear of the water's top."""
    r = w.rect
    a, b = crossing
    c0, c1 = (r.z0, r.z1) if along_x else (r.x0, r.x1)
    top = w.top + ART["lifts"]["road"]
    rng = random.Random(int((a + b) * 100) & 0xFFFF)
    t = a - 0.4
    k = 0
    while t < b + 0.4:
        width = 0.78
        jag = rng.uniform(-0.25, 0.25)
        lo, hi = c0 - 0.3 + jag, c1 + 0.3 + rng.uniform(-0.25, 0.25)
        y1 = top + rng.uniform(-0.02, 0.03)
        y0 = y1 - 0.35
        col = CAMP.WOOD if k % 3 else CAMP.WOOD_DARK
        add_box(bake, along_x, (t, t + width), (y0, y1), (lo, hi), col, CAMP.WOOD_LIGHT if k % 4 == 0 else col)
        t += width + 0.06
        k += 1
    for cc in (c0 + 2.5, c1 - 2.5):
        m = kit.Mesh("stringer")
        p0 = pt(along_x, a - 2.0, cc, top - 1.0)
        p1 = pt(along_x, b + 2.0, cc, top - 1.0)
        m.rod(p0, p1, 0.6, BARK.BARK, sides=6, cap_colour=BARK.LOG_END)
        bake.extend(m.tris)


def add_box(bake: Bake, along_x, ar, yr, cr, colour, top_colour):
    """An axis-aligned box given its ranges along the road axis, up, and across."""
    (a0, a1), (y0, y1), (c0, c1) = ar, yr, cr
    if along_x:
        lo, hi = (a0, y0, c0), (a1, y1, c1)
    else:
        lo, hi = (c0, y0, a0), (c1, y1, a1)
    solid_box(bake, box_corners(lo, hi), colour, top_colour)


def box_corners(lo, hi):
    return [(x, y, z) for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])]


BOX_FACES = ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3))


def solid_box(bake: Bake, v, colour, top_colour=None):
    """Eight corners (x-major, then y, then z, as box_corners orders them) as a closed solid,
    wound outward from its centroid; the face that points most up takes `top_colour`."""
    cx = sum(p[0] for p in v) / 8
    cy = sum(p[1] for p in v) / 8
    cz = sum(p[2] for p in v) / 8
    for f in BOX_FACES:
        a, b, c, d = (v[i] for i in f)
        fx = (a[0] + b[0] + c[0] + d[0]) / 4 - cx
        fy = (a[1] + b[1] + c[1] + d[1]) / 4 - cy
        fz = (a[2] + b[2] + c[2] + d[2]) / 4 - cz
        col = top_colour if (top_colour is not None and fy > abs(fx) and fy > abs(fz)) else colour
        bake.toward(a, b, c, col, (fx, fy, fz))
        bake.toward(a, c, d, col, (fx, fy, fz))


def skins(level: Level, ground: Ground):
    """The road, camp and ledge skins (texture meshes), and the bridge decks (palette)."""
    parts = level.union_parts()
    lifts = ART["lifts"]
    road, road_rim, camp, cave, deck_tris = [], [], [], [], []
    deck = Bake("BridgeDeck", "palette")
    for w in level.walks:
        if w.kind == "path":
            spans, crossings, along_x = bridge_spans(level, w)
            seed = hash01(w.rect.x0, w.rect.z0) * 10
            if w.name in level.roofed:
                cave += ribbon(level, ground, parts, w, lifts["decal"], False, spans, seed=seed)
                continue
            road += ribbon(level, ground, parts, w, lifts["road"], False, spans, seed=seed)
            road_rim += ribbon(level, ground, parts, w, lifts["rim"], True, spans, seed=seed)
            for crossing in crossings:
                bridge_deck(w, crossing, along_x, deck)
        elif w.kind == "camp":
            camp += ribbon(level, ground, parts, w, lifts["camp"], False, grow=0.6, seed=7.0)
            road_rim += ribbon(level, ground, parts, w, lifts["rim"], True, grow=0.6, seed=7.0)
        elif w in level.pillars:
            road_rim += ribbon(level, ground, parts, w, lifts["top"], False, grow=-0.25, seed=3.0)
    return {"road": road, "roadRim": road_rim, "camp": camp, "cave": cave}, deck


# ---------------------------------------------------------------- rock faces


def exposed_faces(level: Level):
    """Every face of the tall solids (walls, roofs, the walled camp's fence, the lookout's rock)
    that no other solid covers, as (normal axis, sign, plane, (u0, u1, v0, v1), solid). For a face
    across x, u is z; across z, u is x; v is y. Top faces use (x, z)."""
    solids = [s for s in level.solids if s.kind in ("wall", "pillar") or (s.kind == "fence" and s.hi[1] - s.lo[1] > 20)]
    out = []
    eps = 1e-3
    emitted: dict[tuple, list] = {}  # (axis, sign, plane) -> regions already skinned on that plane
    # A Part the dressing keeps visible (a bramble) owns its own faces: rock flush with one of
    # them is cut back from it, or the two would shimmer.
    for b in level.layout["blocks"]:
        if b["look"] in ("path", "ground", "wall", "water") or b.get("collide", True) is False:
            continue
        lo = (b["x"] - b["sx"] / 2, b["y"] - b["sy"] / 2, b["z"] - b["sz"] / 2)
        hi = (b["x"] + b["sx"] / 2, b["y"] + b["sy"] / 2, b["z"] + b["sz"] / 2)
        for axis in (0, 1, 2):
            ua, va = (2, 1) if axis == 0 else (0, 1) if axis == 2 else (0, 2)
            for sign in (-1, 1):
                plane = hi[axis] if sign > 0 else lo[axis]
                emitted.setdefault((axis, sign, round(plane, 4)), []).append((lo[ua], hi[ua], lo[va], hi[va]))
    for s in solids:
        for axis in (0, 1, 2):
            for sign in (-1, 1):
                plane = s.hi[axis] if sign > 0 else s.lo[axis]
                ua, va = (2, 1) if axis == 0 else (0, 1) if axis == 2 else (0, 2)
                base = (s.lo[ua], s.hi[ua], s.lo[va], s.hi[va])
                cuts = []
                for o in solids:
                    if o is s:
                        continue
                    probe = plane + eps * sign
                    if not (o.lo[axis] <= probe <= o.hi[axis]):
                        continue
                    cuts.append((o.lo[ua], o.hi[ua], o.lo[va], o.hi[va]))
                # Two solids flush on one plane (a roof over its wall) would skin it twice: the
                # second skin would fight the first, so a region is skinned once.
                key = (axis, sign, round(plane, 4))
                cuts += emitted.get(key, [])
                for region in lm.subtract_rects(base, cuts):
                    out.append((axis, sign, plane, region, s))
                    emitted.setdefault(key, []).append(region)
    return out


def faces_walkable(level: Level, parts, axis, sign, plane, u, v):
    """Does a face point look onto ground a player stands on (so its rock must stay thin)?"""
    if axis == 1:
        if sign > 0:
            return False
        x, z = u, v
        return any(w.rect.contains(x, z) and w.top < plane for w in level.walks)
    x, z = (plane + sign * 1.5, u) if axis == 0 else (u, plane + sign * 1.5)
    return any(rect.contains(x, z) for rect, _t, kind, _n in parts if kind != "drop")


def rock_faces(level: Level, ground: Ground):
    """Rock over every exposed face of the tall solids: a faceted cliff (a lattice on the face,
    each inner vertex pushed out and jittered by seeded noise, every border vertex left on the
    box so two faces meet at their edge with no crack), boulders along the outer corners and top
    edges so no box silhouette shows, and firs along the wide tops nobody can reach. A face that
    looks onto ground a player walks stays within a quarter stud of the collision face (its
    vertices go 0.45 in to 0.12 out), so no rock reaches into walking space."""
    parts = level.union_parts()
    bake = Bake("RockFaces", "palette")
    pillar_tops = {s.name: s.hi[1] for s in level.solids if s.kind == "pillar"}
    exterior_faces = {}
    for axis, sign, plane, (u0, u1, v0, v1), s in exposed_faces(level):
        if axis == 1:
            if sign < 0:
                if not faces_walkable(level, parts, axis, sign, plane, (u0 + u1) / 2, (v0 + v1) / 2):
                    continue
                cliff_face(bake, axis, sign, plane, (u0, u1, v0, v1), True)
            elif s.kind != "pillar":
                cliff_face(bake, axis, sign, plane, (u0, u1, v0, v1), False)
            continue
        if s.kind == "pillar":
            v1 = min(v1, pillar_tops[s.name])
        lows = []
        for k in range(9):
            uu = u0 + (u1 - u0) * k / 8
            gx, gz = (plane + sign * 1.0, uu) if axis == 0 else (uu, plane + sign * 1.0)
            lows.append(ground.at(gx, gz))
        v0c = max(v0, min(lows) - 1.0)
        if v0c >= v1 - 0.3:
            continue
        thin = faces_walkable(level, parts, axis, sign, plane, (u0 + u1) / 2, (v0c + v1) / 2)
        # Out of every player's reach (a double jump and a leap stay under REACH_ABOVE over the
        # floor in front), a face that looks onto walking space may bulge like any other cliff.
        reach = floor_in_front(level, axis, sign, plane, u0, u1) + REACH_ABOVE if thin else None
        cliff_face(bake, axis, sign, plane, (u0, u1, v0c, v1), thin, bulge_above=reach)
        if not thin:
            exterior_faces.setdefault(s.name, []).append((axis, sign, plane, (u0, u1, v0c, v1)))
    rim_boulders(level, ground, parts, bake, exterior_faces)
    crown_firs(level, ground, parts, bake)
    return bake


def crown_firs(level: Level, ground: Ground, parts, bake: Bake):
    """A crown of firs on the massif just outside a walled camp's rim, which a player inside sees
    against the sky over the rock all round."""
    walk_rects = [p[0].grown(2.5) for p in parts]
    for camp in level.camps.values():
        if not camp.get("locks"):
            continue
        t = level.fence_thickness(camp)
        fenced = Rect(camp["x"] - camp["sx"] / 2 - t, camp["x"] + camp["sx"] / 2 + t, camp["z"] - camp["sz"] / 2 - t, camp["z"] + camp["sz"] / 2 + t)
        for side, (nx, nz) in SIDES.items():
            lo_u, hi_u = (fenced.x0, fenced.x1) if nz else (fenced.z0, fenced.z1)
            plane = (fenced.z0 if nz < 0 else fenced.z1) if nz else (fenced.x0 if nx < 0 else fenced.x1)
            u = lo_u + 2.0
            while u < hi_u - 2.0:
                d = 3.5 + 6.0 * hash01(u, plane, 1.0)
                x, z = (u, plane + nz * d) if nz else (plane + nx * d, u)
                if not any(r.contains(x, z) for r in walk_rects):
                    piece = "FirHeroA" if hash01(x, z, 3.0) < 0.55 else "FirMassB"
                    bake.extend(kit.build(piece).transformed(x, ground.at(x, z) - 0.5, z, hash01(x, z) * 360, 0.9 + 0.35 * hash01(z, x)))
                u += 6.5 + 4.0 * hash01(u, plane, 2.0)


REACH_ABOVE = 36.0  # a double jump (30) and a head over the floor, with a margin


def floor_in_front(level: Level, axis, sign, plane, u0, u1) -> float:
    """The highest walkable top a face looks onto, within 3 studs in front of it."""
    best = -math.inf
    for w in level.walks:
        r = w.rect
        if axis == 0:
            near = (r.x0 - 3 <= plane + sign * 1.5 <= r.x1 + 3) and r.z1 > u0 and r.z0 < u1
        else:
            near = (r.z0 - 3 <= plane + sign * 1.5 <= r.z1 + 3) and r.x1 > u0 and r.x0 < u1
        if near:
            best = max(best, w.top)
    return best if best > -math.inf else 0.0


def cliff_face(bake: Bake, axis, sign, plane, region, thin, cell=5.5, bulge_above=None):
    """One face region as a faceted cliff (see rock_faces). u runs along the face, v up it (for a
    top or bottom face, u is x and v is z). `bulge_above`: a thin face bulges above this height."""
    u0, u1, v0, v1 = region
    if not thin:
        cell *= 1.2  # a face nobody touches carries bigger facets
    cell = min(cell, max(2.5, min(u1 - u0, v1 - v0) / 3.0))
    nu = max(1, int(math.ceil((u1 - u0) / cell)))
    nv = max(1, int(math.ceil((v1 - v0) / cell)))
    du, dv = (u1 - u0) / nu, (v1 - v0) / nv
    grid = []
    for j in range(nv + 1):
        row = []
        for i in range(nu + 1):
            u = u0 + i * du
            v = v0 + j * dv
            border = i in (0, nu) or j in (0, nv)
            if border:
                d = 0.0
            else:
                h = hash01(u * 1.31, v * 0.77, plane * 0.29 + axis)
                ridge = 0.5 + 0.5 * NOISE.n2(u / 17.0, v / 9.0, plane * 0.01 + axis)
                if thin:
                    d = -0.45 + 0.57 * h
                    if bulge_above is not None and axis != 1 and v > bulge_above:
                        d = max(d, min(1.0, (v - bulge_above) / 8.0) * (0.6 + 3.4 * h * (0.4 + 0.6 * ridge)))
                else:
                    d = 0.6 + 4.2 * h * (0.35 + 0.65 * ridge)
                spread = 0.3 if thin else 0.55
                u += (hash01(u, v, 1.0) - 0.5) * du * spread
                v += (hash01(u, v, 2.0) - 0.5) * dv * spread * 0.85
            row.append(face_point(axis, plane + sign * d, u, v))
        grid.append(row)
    normal = [0.0, 0.0, 0.0]
    normal[axis] = float(sign)
    for j in range(nv):
        for i in range(nu):
            a, b, c, d = grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]
            if hash01(i, j, plane) < 0.5:
                tris = ((a, b, c), (a, c, d))
            else:
                tris = ((a, b, d), (b, c, d))
            for t in tris:
                n = lm.tri_normal(*t)
                if n[0] * normal[0] + n[1] * normal[1] + n[2] * normal[2] < 0:
                    t = (t[0], t[2], t[1])
                    n = (-n[0], -n[1], -n[2])
                bake.tri(t[0], t[1], t[2], rock_colour(t, n, thin))


def rock_colour(t, n, thin):
    length = math.sqrt(n[0] * n[0] + n[1] * n[1] + n[2] * n[2]) or 1.0
    ny = n[1] / length
    cx = (t[0][0] + t[1][0] + t[2][0]) / 3
    cy = (t[0][1] + t[1][1] + t[2][1]) / 3
    cz = (t[0][2] + t[1][2] + t[2][2]) / 3
    k = hash01(round(cx, 1), round(cy, 1), round(cz, 1))
    if ny > 0.55:
        if not thin and k < 0.55:
            return FOLIAGE.MOSS if k < 0.3 else ROCK.LICHEN
        return ROCK.ROCK_LIGHT
    if ny < -0.35:
        return ROCK.ROCK_DARK
    band = NOISE.n2(cy / 7.0, (cx + cz) / 60.0, 21.0)
    if band > 0.35:
        return ROCK.ROCK_LIGHT if k < 0.6 else ROCK.ROCK
    if band < -0.3:
        return ROCK.ROCK_DARK if k < 0.6 else ROCK.ROCK
    return ROCK.ROCK if k < 0.65 else ROCK.ROCK_DARK if k < 0.85 else ROCK.ROCK_LIGHT


def face_point(axis, n, u, v):
    if axis == 0:
        return (n, v, u)
    if axis == 2:
        return (u, v, n)
    return (u, n, v)


def rim_boulders(level: Level, ground: Ground, parts, bake: Bake, exterior_faces):
    """Boulders down every outer corner where two exterior faces meet, and along the top edge of
    every exterior face, so the solids read as rock, not boxes; firs along wide unreachable tops."""
    walk_rects = [p[0].grown(2.5) for p in parts]
    for s in level.solids:
        faces = exterior_faces.get(s.name)
        if not faces:
            continue
        top = s.hi[1]
        for axis, sign, plane, (u0, u1, v0, v1) in faces:
            if v1 < top - 0.5:
                continue
            n = max(1, int((u1 - u0) / 10.0))
            for k in range(n + 1):
                u = u0 + (u1 - u0) * k / n
                x, z = (plane + sign * 0.5, u) if axis == 0 else (u, plane + sign * 0.5)
                if any(r.contains(x, z) for r in walk_rects):
                    continue
                r = 2.2 + 1.6 * hash01(x, z, 7.0)
                kit_boulder(bake, (x, top - 0.6 * r, z), r, hash01(x, z, 8.0))
            for u in (u0, u1):
                x, z = (plane + sign * 0.4, u) if axis == 0 else (u, plane + sign * 0.4)
                if any(r.contains(x, z) for r in walk_rects):
                    continue
                y = v0 + 3.0
                while y < top - 2.0:
                    r = 2.4 + 1.8 * hash01(x, y, z)
                    kit_boulder(bake, (x, y, z), r, hash01(z, y, x))
                    y += 9.0 + 4.0 * hash01(y, x, 3.0)
        r = s.rect
        if min(r.x1 - r.x0, r.z1 - r.z0) >= 12.0 and s.kind == "wall":
            step = 9.0
            z = r.z0 + 3.5
            while z < r.z1 - 3.0:
                x = r.x0 + 3.5 + hash01(z, s.hi[1]) * 4
                while x < r.x1 - 3.0:
                    m = kit.build("FirMassA" if hash01(x, z) < 0.6 else "FirMassB")
                    bake.extend(m.transformed(x, top + 0.8, z, hash01(x, z, 2.0) * 360, 0.8 + 0.4 * hash01(z, x)))
                    x += step + 3 * hash01(x, z, 4.0)
                z += step


def kit_boulder(bake: Bake, centre, radius, seed):
    m = kit.Mesh("boulder")
    m.blob(centre, (radius, radius * 0.8, radius * 0.95), ROCK.ROCK if seed < 0.6 else ROCK.ROCK_LIGHT, rot=seed * 6.0,
           seed=seed * 100.0, rough=0.25, colour2=ROCK.ROCK_DARK)
    bake.extend(m.tris)


def step_faces(level: Level, bake: Bake):
    """Rock on the face of every step between two walkable blocks (the climb onto the plateau,
    the climb to the gatehouse, the cave's climb), thin: it faces the lower block's walkers."""
    for lo in level.walks:
        for hi in level.walks:
            if hi.top - lo.top < 0.5 or lo is hi:
                continue
            a, b = lo.rect, hi.rect
            for axis, plane, sign, span in (
                (0, b.x0, -1, (max(a.z0, b.z0), min(a.z1, b.z1))) if abs(a.x1 - b.x0) < 1e-6 else (None,) * 4,
                (0, b.x1, 1, (max(a.z0, b.z0), min(a.z1, b.z1))) if abs(a.x0 - b.x1) < 1e-6 else (None,) * 4,
                (2, b.z0, -1, (max(a.x0, b.x0), min(a.x1, b.x1))) if abs(a.z1 - b.z0) < 1e-6 else (None,) * 4,
                (2, b.z1, 1, (max(a.x0, b.x0), min(a.x1, b.x1))) if abs(a.z0 - b.z1) < 1e-6 else (None,) * 4,
            ):
                if axis is None or span[1] - span[0] < 0.5:
                    continue
                cliff_face(bake, axis, sign, plane, (span[0], span[1], lo.top - 0.6, hi.top + 0.05), True, cell=2.5)


# ---------------------------------------------------------------- placements


class Placements:
    """Every piece the dressing stands in the level: (piece, x, y, z, yaw, scale, tags)."""

    def __init__(self):
        self.items: list[dict] = []

    def add(self, piece, x, y, z, yaw=0.0, scale=1.0, **tags):
        item = {"piece": piece, "x": round(x, 3), "y": round(y, 3), "z": round(z, 3), "yaw": round(yaw % 360.0, 2), "scale": round(scale, 3)}
        item.update(tags)
        self.items.append(item)
        return item


def footprint(item):
    """A placed piece's ground rectangle and its top, from the kit's bounds, turned and scaled."""
    mesh = kit.build(item["piece"])
    lo, hi = mesh.bounds()
    s = item["scale"]
    c, sn = math.cos(math.radians(item["yaw"])), math.sin(math.radians(item["yaw"]))
    xs, zs = [], []
    for px in (lo[0], hi[0]):
        for pz in (lo[2], hi[2]):
            xs.append(item["x"] + (px * c + pz * sn) * s)
            zs.append(item["z"] + (-px * sn + pz * c) * s)
    return Rect(min(xs), max(xs), min(zs), max(zs)), item["y"] + hi[1] * s


class Keepout:
    """Rectangles and discs no clutter may stand in (posts, routes, doors, cover, spawns)."""

    def __init__(self):
        self.rects: list[Rect] = []
        self.discs: list[tuple[float, float, float]] = []

    def rect(self, r):
        self.rects.append(r)

    def disc(self, x, z, radius):
        self.discs.append((x, z, radius))

    def line(self, pts, half):
        for a, b in zip(pts, pts[1:]):
            n = max(1, int(math.hypot(b[0] - a[0], b[1] - a[1]) / 1.5))
            for k in range(n + 1):
                t = k / n
                self.disc(a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, half)

    def blocked(self, r: Rect) -> bool:
        if any(r.overlaps(o) for o in self.rects):
            return True
        for x, z, radius in self.discs:
            if r.distance(x, z) < radius:
                return True
        return False


def dress_camps(level: Level, ground: Ground, P: Placements, cover: Bake):
    """The camps: natural edges on the fence lines, totems at the gates, fires with seats, the
    spawn tents in their markers, cover dressed as log cribs, clutter where no raider stands, and
    the tents and racks of the camp out under the trees beyond the edge."""
    route = [(p["x"], p["z"]) for p in level.layout.get("route") or []]
    sneak = [(p["x"], p["z"]) for p in level.layout.get("sneak") or []]
    outside_rects = []
    for cid, camp in level.camps.items():
        x, y, z, sx, sz = camp["x"], float(camp["y"]), camp["z"], camp["sx"], camp["sz"]
        floor = Rect(x - sx / 2, x + sx / 2, z - sz / 2, z + sz / 2)
        rng = random.Random(1000 + ord(cid))
        locked = bool(camp.get("locks"))
        keep = Keepout()
        keep.line(route, 9.0)
        keep.line(sneak, 3.0)
        for spot in camp.get("spots") or []:
            pts = [(p["x"], p["z"]) for p in spot["points"]]
            if spot["posture"] == "fire":
                keep.disc(pts[0][0], pts[0][1], spot.get("radius", 5) + 5.0)
            elif spot["posture"] == "patrol":
                keep.line(pts + pts[:1], 3.5)
            else:
                for p in pts:
                    keep.disc(p[0], p[1], 4.0)
        for p in camp.get("spawns") or []:
            keep.disc(p["x"], p["z"], 5.0)
        for key in ("entry", "exit", "checkpoint", "approach"):
            if key in camp:
                keep.disc(camp[key]["x"], camp[key]["z"], 6.0)
        for o in camp.get("obstacles") or []:
            keep.rect(Rect.of(o).grown(2.0))
        tent = camp.get("tent")
        if tent:
            keep.rect(Rect.of(tent).grown(5.0))
        if not locked:
            edge_pieces(level, camp, floor, P, rng)
            outside = camp_outside(level, ground, camp, floor, P, rng)
            outside_rects.append(outside)
        # fires and their seats
        for spot in camp.get("spots") or []:
            if spot["posture"] != "fire":
                continue
            fx, fz = spot["points"][0]["x"], spot["points"][0]["z"]
            P.add("Campfire", fx, y, fz, rng.uniform(0, 360), 1.0, camp=cid, effect="fire")
            seats = ART["camps"]["seats"]
            ring = spot.get("radius", 5) + 2.6
            for k in range(seats):
                a = k * math.tau / seats + rng.uniform(-0.25, 0.25)
                sxp, szp = fx + ring * math.cos(a), fz + ring * math.sin(a)
                item = {"piece": "LogSeat", "x": sxp, "y": y, "z": szp, "yaw": -math.degrees(a) + 90.0, "scale": 1.0}
                r, _ = footprint(item)
                if any(r.distance(px, pz) < 3.0 for px, pz in route_points(route)) or not floor.grown(-3).contains(sxp, szp):
                    continue
                P.add("LogSeat", sxp, y, szp, item["yaw"], 1.0, camp=cid)
        # the spawn tent in its marker, its door toward the camp's centre
        if tent:
            # A quarter turn toward the camp's middle, so the tent stays inside its square marker.
            yaw = round(door_yaw(tent["x"], tent["z"], x, z) / 90.0) * 90.0
            P.add("SpawnTent", tent["x"], y, tent["z"], yaw, 1.0, camp=cid, marker="tent")
        # cover dressed as cribs (baked, sized to the collision box)
        for k, o in enumerate(camp.get("obstacles") or []):
            m = kit.cover_skin(f"Cover{cid}{k}", o["sx"] + 0.2, min(o["sy"], COVER_MAX), o["sz"] + 0.2, seed=k * 31 + ord(cid))
            cover.extend(m.transformed(o["x"], y, o["z"], 0.0, 1.0))
        # clutter where no raider stands
        if cid == "C":
            dress_clearing(level, camp, floor, P, keep, rng)
        else:
            count = ART["camps"]["clutter" + cid]
            pieces = ["HideRack", "WeaponRack", "Firewood", "Sacks", "Bedroll", "BonePile", "SkullPole", "LeanTo"]
            placed = 0
            tries = 0
            while placed < count and tries < 600:
                tries += 1
                px = rng.uniform(floor.x0 + 5, floor.x1 - 5)
                pz = rng.uniform(floor.z0 + 5, floor.z1 - 5)
                piece = pieces[(placed + rng.randrange(3)) % len(pieces)]
                item = {"piece": piece, "x": px, "y": y, "z": pz, "yaw": rng.uniform(0, 360), "scale": 1.0}
                r, _ = footprint(item)
                if keep.blocked(r):
                    continue
                keep.rect(r.grown(2.5))
                P.add(piece, px, y, pz, item["yaw"], 1.0, camp=cid)
                placed += 1
    return outside_rects


def route_points(route):
    out = []
    for a, b in zip(route, route[1:]):
        n = max(1, int(math.hypot(b[0] - a[0], b[1] - a[1]) / 2))
        for k in range(n + 1):
            out.append((a[0] + (b[0] - a[0]) * k / n, a[1] + (b[1] - a[1]) * k / n))
    return out


def door_yaw(px, pz, tx, tz):
    """The yaw that turns a piece's front (-Z) at (px, pz) toward (tx, tz)."""
    dx, dz = tx - px, tz - pz
    # front -Z turned by yaw lands at (-sin, -cos): solve for yaw.
    return math.degrees(math.atan2(-dx, -dz))


def edge_pieces(level, camp, floor: Rect, P: Placements, rng):
    """The natural edge on an open camp's fence line, side by side, the gates left open. Each
    piece's inner face lies on the floor's edge and it reaches outward, so a player at the fence
    never stands inside the visual. Camp A, the Pickets, is mostly stakes."""
    cid = camp["id"]
    y = float(camp["y"])
    gates = level.gate_spans(camp)
    if cid == "A":
        mix = ["EdgeStakes", "EdgeStakes", "EdgeLogs", "EdgeStakes", "EdgeRocks", "EdgeStakes", "EdgeThicket"]
    else:
        mix = ["EdgeLogs", "EdgeThicket", "EdgeRocks", "EdgeLogs", "EdgeStakes", "EdgeThicket", "EdgeLogs"]
    k = 0
    for side, (nx, nz) in SIDES.items():
        along_x = nz != 0
        half = (floor.x1 - floor.x0) / 2 if along_x else (floor.z1 - floor.z0) / 2
        cx, cz = (floor.x0 + floor.x1) / 2, (floor.z0 + floor.z1) / 2
        cuts = [(a - 0.5, b + 0.5) for s, a, b in gates if s == side]
        for a, b in lm.subtract_intervals(-half - 1.0, half + 1.0, cuts):
            length = b - a
            n = max(1, round(length / 7.6))
            seg = length / n
            for i in range(n):
                piece = mix[k % len(mix)]
                k += 1
                mesh = kit.build(piece)
                lo, hi = mesh.bounds()
                natural = hi[0] - lo[0]
                scale = min(1.15, max(0.75, (seg + 0.6) / natural))
                if hi[1] * scale > kit.EDGE_MAX:
                    scale = kit.EDGE_MAX / hi[1] * 0.995
                t = a + (i + 0.5) * seg
                if along_x:
                    px, pz = cx + t, (floor.z0 if nz < 0 else floor.z1)
                else:
                    px, pz = (floor.x0 if nx < 0 else floor.x1), cz + t
                # Front (-Z) toward the camp: the piece's +Z (its body) reaches outward.
                yaw = door_yaw(px, pz, px - nx, pz - nz)
                P.add(piece, px + nx * 0.05, y, pz + nz * 0.05, yaw, scale, camp=cid, edge=side)
    # totems at the gates, outside the fence and off the road
    for side, a, b in gates:
        nx, nz = SIDES[side]
        for t in (a - 2.2, b + 2.2):
            if nz:
                px, pz = camp["x"] + t, (floor.z0 - 2.5 if nz < 0 else floor.z1 + 2.5)
            else:
                px, pz = (floor.x0 - 2.5 if nx < 0 else floor.x1 + 2.5), camp["z"] + t
            P.add("GatePost", px, y, pz, door_yaw(px, pz, px + nx, pz + nz), 1.0, camp=cid, gate=side)


def camp_outside(level, ground: Ground, camp, floor: Rect, P: Placements, rng):
    """The camp under the trees just beyond its edge (behind the wall the player cannot pass):
    hide tents, lean-tos, racks, banners and, at the Main Camp, a watch platform. Kept off the
    roads and the gates' approaches."""
    cid = camp["id"]
    y = float(camp["y"])
    band = floor.grown(17.0)
    keep = Keepout()
    for w in level.walks:
        if w.kind != "camp":
            keep.rect(w.rect.grown(4.0))
    for d in level.drops:
        keep.rect(d.grown(2.0))
    for s in level.solids:
        if s.kind in ("wall", "pillar"):
            keep.rect(s.rect.grown(2.5))
    keep.rect(floor.grown(4.5))
    pieces = ["HideTent", "HideTent", "LeanTo", "HideRack", "Banner", "Firewood", "HideTent", "SkullPole", "Banner"]
    want = 10 if cid == "A" else 16
    placed = 0
    tries = 0
    if cid == "B":
        # A watch platform over the Main Camp's south-east corner, under the trees.
        wx, wz = floor.x1 + 9.0, floor.z1 - 22.0
        item = {"piece": "Watchtower", "x": wx, "y": y, "z": wz, "yaw": door_yaw(wx, wz, floor.x1 - 10, wz), "scale": 1.0}
        if not keep.blocked(footprint(item)[0]):
            P.add("Watchtower", wx, ground.at(wx, wz), wz, item["yaw"], 1.0, camp=cid, outside=True)
            keep.disc(wx, wz, 6.0)
    while placed < want and tries < 800:
        tries += 1
        side = rng.choice(list(SIDES))
        nx, nz = SIDES[side]
        d = rng.uniform(6.5, 12.0)
        if nz:
            px = rng.uniform(floor.x0 + 4, floor.x1 - 4)
            pz = (floor.z0 - d) if nz < 0 else (floor.z1 + d)
        else:
            pz = rng.uniform(floor.z0 + 4, floor.z1 - 4)
            px = (floor.x0 - d) if nx < 0 else (floor.x1 + d)
        piece = pieces[placed % len(pieces)]
        yaw = door_yaw(px, pz, px - nx, pz - nz) + rng.uniform(-20, 20)
        item = {"piece": piece, "x": px, "y": y, "z": pz, "yaw": yaw, "scale": 1.0}
        r, _ = footprint(item)
        if keep.blocked(r):
            continue
        keep.rect(r.grown(1.5))
        P.add(piece, px, ground.at(px, pz), pz, yaw, 1.0, camp=cid, outside=True)
        placed += 1
    return band


def dress_clearing(level, camp, floor: Rect, P: Placements, keep: Keepout, rng):
    """The Chief's Clearing: his hall behind where he appears (his first steps come out of its
    door), fire bowls at its porch, skull poles and banners along the rock wall, hide screens in
    the two corners the ambushers spring from."""
    cid = camp["id"]
    y = float(camp["y"])
    stages = level.config.get("stages") or []
    boss_at = None
    for st in stages:
        if st.get("zone") != cid:
            continue
        for wave in st.get("waves") or []:
            if wave.get("boss"):
                boss_at = wave["boss"].get("at")
    bx = camp["x"] + (boss_at[0] if boss_at else 0.0)
    bz = camp["z"] + (boss_at[1] if boss_at else 0.0)
    # The hall's door (its -Z face, 11 + 0.2 out from its origin) a few studs behind the Chief.
    tent = kit.build("ChiefTent")
    lo, hi = tent.bounds()
    half_depth = hi[2] * CHIEF_SCALE
    front = -lo[2] * CHIEF_SCALE
    entry = camp.get("entry") or {"x": camp["x"], "z": floor.z0}
    yaw = door_yaw(bx, bz, entry["x"], entry["z"])
    dirx, dirz = -math.sin(math.radians(yaw)), -math.cos(math.radians(yaw))
    room = min(floor.z1 - bz, 40.0) if abs(dirz) > 0.7 else 30.0
    back = min(front + half_depth, room - 2.0)
    tx = bx - dirx * (back - half_depth + 0.0)
    tz = bz - dirz * (back - half_depth + 0.0)
    tx, tz = bx - dirx * (front - 3.0), bz - dirz * (front - 3.0)
    # keep its back off the wall
    over = (tz + half_depth) - (floor.z1 + 2.0)  # its back may sink into the rock, never out of it
    if over > 0 and abs(dirz) > 0.7:
        tz -= over
    P.add("ChiefTent", tx, y, tz, yaw, CHIEF_SCALE, camp=cid, boss=[round(bx, 2), round(bz, 2)])
    keep.rect(Rect(tx - 19, tx + 19, tz - 20, tz + 16))
    for side in (-1, 1):
        fx = tx + side * 13.0
        fz = tz - front - 3.0
        P.add("Campfire", fx, y, fz, rng.uniform(0, 360), 1.0, camp=cid, effect="fire")
        keep.disc(fx, fz, 3.0)
    # Along the walls: skull poles and banners within two studs of the rock.
    k = 0
    for side, (nx, nz) in SIDES.items():
        along_x = nz != 0
        lo_t = floor.x0 if along_x else floor.z0
        hi_t = floor.x1 if along_x else floor.z1
        t = lo_t + 8.0
        while t < hi_t - 8.0:
            if along_x:
                px, pz = t, (floor.z0 + 1.6 if nz < 0 else floor.z1 - 1.6)
            else:
                px, pz = (floor.x0 + 1.6 if nx < 0 else floor.x1 - 1.6), t
            piece = "Banner" if k % 3 == 0 else "SkullPole"
            item = {"piece": piece, "x": px, "y": y, "z": pz, "yaw": door_yaw(px, pz, px - nx, pz - nz), "scale": 1.0}
            r, _ = footprint(item)
            if not keep.blocked(r):
                P.add(piece, px, y, pz, item["yaw"], 1.0, camp=cid, wall=side)
            k += 1
            t += rng.uniform(10.0, 16.0)
    # Hide screens and racks in the two north corners, where the ambush waits.
    for spot in camp.get("spots") or []:
        if not spot["id"].startswith("ambush"):
            continue
        pts = spot["points"]
        cx = sum(p["x"] for p in pts) / len(pts)
        cz = sum(p["z"] for p in pts) / len(pts)
        for j, (dx, dz, piece) in enumerate(((0.0, 7.5, "LeanTo"), (-7.0, 5.0, "HideRack"), (7.0, 5.0, "HideRack"), (0.0, -4.5, "Sacks"))):
            px, pz = cx + dx, cz + dz
            if not floor.grown(-2.5).contains(px, pz):
                continue
            yawp = door_yaw(px, pz, camp["x"], camp["z"])
            P.add(piece, px, y, pz, yawp, 1.0, camp=cid, ambush=spot["id"])
    pieces = ["BonePile", "Firewood", "Sacks", "WeaponRack", "Bedroll", "HideRack"]
    placed = tries = 0
    while placed < ART["camps"]["clutterC"] and tries < 600:
        tries += 1
        px = rng.uniform(floor.x0 + 4, floor.x1 - 4)
        pz = rng.uniform(floor.z0 + 12, floor.z1 - 4)
        piece = pieces[placed % len(pieces)]
        item = {"piece": piece, "x": px, "y": y, "z": pz, "yaw": rng.uniform(0, 360), "scale": 1.0}
        r, _ = footprint(item)
        if keep.blocked(r):
            continue
        keep.rect(r.grown(3.0))
        P.add(piece, px, y, pz, item["yaw"], 1.0, camp=cid)
        placed += 1


def gatehouse_arch(level, P: Placements, bake: Bake):
    """A log lintel with skulls across the gatehouse's mouth, above head height: the Chief's gate."""
    walk = level.blocks.get("GatehouseWalk")
    if not walk:
        return
    r = Rect.of(walk)
    top = walk["y"] + walk["sy"] / 2
    x = r.x0 + 1.5
    m = kit.Mesh("lintel")
    m.rod((x, top + 18.0, r.z0 - 2.4), (x, top + 18.4, r.z1 + 2.4), 0.9, BARK.BARK, sides=6, cap_colour=BARK.LOG_END)
    m.rod((x, top + 16.6, r.z0 - 2.4), (x, top + 16.8, r.z1 + 2.4), 0.7, BARK.BARK_DARK, sides=6, cap_colour=BARK.LOG_END)
    for k in range(6):
        zz = r.z0 + 1.5 + k * (r.z1 - r.z0 - 3.0) / 5
        m.rod((x, top + 16.0, zz), (x, top + 13.6 - (k % 2) * 1.2, zz), 0.05, CAMP.ROPE, sides=3)
        m.blob((x, top + 13.3 - (k % 2) * 1.2, zz), (0.45, 0.42, 0.48), CAMP.BONE, seed=k + 3.0, rough=0.06)
    bake.extend(m.tris)


def dress_pillars(level: Level, P: Placements):
    """A lone fir and ferns on the back corners of every pillar's top (the lookout rock), away
    from its chest and from the side players jump onto it from."""
    for w in level.pillars:
        r = w.rect
        chest = next((s for s in level.layout.get("secrets") or [] if r.contains(s["x"], s["z"])), None)
        drop = next((d for d in level.drops if d.distance((r.x0 + r.x1) / 2, (r.z0 + r.z1) / 2) < max(r.x1 - r.x0, r.z1 - r.z0)), None)
        corners = [(r.x0 + 2.2, r.z0 + 2.2), (r.x1 - 2.2, r.z0 + 2.2), (r.x0 + 2.2, r.z1 - 2.2), (r.x1 - 2.2, r.z1 - 2.2)]
        if drop is not None:
            corners.sort(key=lambda c: -drop.distance(*c))
        for k, (x, z) in enumerate(corners[:2]):
            if chest and math.hypot(x - chest["x"], z - chest["z"]) < 6.0:
                continue
            P.add("FirHeroB" if k == 0 else "Fern", x, w.top, z, hash01(x, z) * 360, 0.7 if k == 0 else 1.0, pillar=w.name)


def dress_islands(level: Level, ground: Ground, P: Placements):
    """A ring of standing stones on the rim of every island (the shrine's), walk-through, clear of
    its chest, with ferns between them."""
    for name in sorted(ground.islands):
        r = level.blocks[name]
        rect = Rect.of(r)
        top = r["y"] + r["sy"] / 2
        cx, cz = (rect.x0 + rect.x1) / 2, (rect.z0 + rect.z1) / 2
        rad = min(rect.x1 - rect.x0, rect.z1 - rect.z0) / 2 - 1.6
        for k in range(5):
            a = k * math.tau / 5 + 0.4
            x, z = cx + rad * math.cos(a), cz + rad * math.sin(a)
            P.add("StandingStone", x, top, z, math.degrees(a), 0.8 + 0.2 * hash01(x, z), island=name)
            a2 = a + math.tau / 10
            P.add("Fern", cx + (rad + 0.4) * math.cos(a2), top, cz + (rad + 0.4) * math.sin(a2), hash01(z, x) * 360, 1.0, island=name)


def dress_brambles(level: Level, ground: Ground, P: Placements):
    """Low thorny bush along both faces of every burnable bramble block, as props tagged `with` the
    block: W2 removes them with it when the fire burns it, so the way opens to the eye too. Both
    faces of both brambles look onto walking ground, so nothing here stands over 4 studs; the
    block's own look (LeafyGrass, LOOKS.bramble) carries the wall above them."""
    for b in level.layout["blocks"]:
        if b.get("react") != "fire":
            continue
        r = Rect.of(b)
        along_x = (r.x1 - r.x0) >= (r.z1 - r.z0)
        base = b["y"] - b["sy"] / 2
        a0, a1 = (r.x0, r.x1) if along_x else (r.z0, r.z1)
        c = (r.z0 + r.z1) / 2 if along_x else (r.x0 + r.x1) / 2
        half = ((r.z1 - r.z0) if along_x else (r.x1 - r.x0)) / 2
        for side in (-1, 1):
            off = c + side * (half + 0.4)
            t = a0 + 1.5
            while t < a1 - 1.0:
                px, pz = (t, off) if along_x else (off, t)
                yaw = (0.0 if along_x else 90.0) + 13.0 * (hash01(px, pz) - 0.5)
                P.add("Bramble", px, base, pz, yaw, min(1.2 + 0.3 * hash01(pz, px), EDGE_BAND_MAX / kit.build("Bramble").bounds()[1][1]),
                      **{"with": b["name"]})
                t += 3.6 + 0.8 * hash01(t, side)


# ---------------------------------------------------------------- the forest


def plant(level: Level, ground: Ground, P: Placements, reserved: list[Rect]):
    """Trees and undergrowth by distance from the walkable whole: a thicket band right outside
    every walled edge, hero trees (the layered firs, the gnarled broadleaf, snags) in the near
    band, mass firs in the middle band, and beyond it the canopy blanket (built separately)."""
    parts = level.union_parts()
    rects = [p[0] for p in parts]
    tr = ART["trees"]
    tall = [s.rect.grown(2.5) for s in level.solids if s.kind in ("wall", "pillar", "fence")]
    ravine = ground.ravine

    def dist_u(x, z):
        return min(r.distance(x, z) for r in rects)

    def blocked(x, z, pad):
        if any(r.contains(x, z, pad) for r in tall):
            return True
        if ground.steep(x, z):
            return True
        if any(r.contains(x, z, pad) for r in ravine):
            return True
        if any(w.rect.distance(x, z) < pad + 1.5 for w in level.water):
            return True
        return any(r.contains(x, z) for r in reserved)

    rng = random.Random(77)
    # the thicket band, along every walled stretch (the barriers' own edges)
    for bar in level._barriers:
        c, a, b = bar["edge"]
        nx, nz = SIDES[bar["side"]]
        camp_edge = any(abs(c - v) < 1.5 for v in camp_edge_lines(level, bar["side"]))
        if camp_edge:
            continue
        t = a + rng.uniform(0.5, 2.5)
        while t < b - 0.5:
            d = rng.uniform(1.6, 2.6)
            px, pz = (c + nx * d, t) if nx else (t, c + nz * d)
            if not blocked(px, pz, 0.0) and dist_u(px, pz) > 0.9:
                k = rng.random()
                piece = "Thicket" if k < 0.34 else "BushLarge" if k < 0.6 else "Bush" if k < 0.8 else "Bramble" if k < 0.9 else "Fern"
                yaw = 0.0 if nz else 90.0
                yaw += rng.uniform(-14, 14)
                scale = min(rng.uniform(0.9, 1.15), EDGE_BAND_MAX / kit.build(piece).bounds()[1][1])
                P.add(piece, px, ground.at(px, pz), pz, yaw, scale, band="edge")
            t += rng.uniform(5.6, 7.4)
    # near and middle bands: a jittered grid
    for band, (d0, d1), step, choose in (
        ("near", tr["near"], tr["nearStep"], near_piece),
        ("mid", tr["mid"], tr["midStep"], mid_piece),
    ):
        z = ground.z0 + step / 2
        while z < ground.z1:
            x = ground.x0 + step / 2
            while x < ground.x1:
                px = x + (hash01(x, z, 1.0) - 0.5) * step * 0.8
                pz = z + (hash01(x, z, 2.0) - 0.5) * step * 0.8
                d = dist_u(px, pz)
                if d0 <= d < d1 and not blocked(px, pz, 1.0):
                    piece, scale = choose(hash01(px, pz, 3.0), hash01(px, pz, 4.0))
                    # No branch over walkable ground: a tree's reach stays outside it.
                    fit = (d - 0.4) / reach_of(piece)
                    if fit < scale * 0.8:
                        piece, scale = ("SnagA", min(1.0, (d - 0.4) / reach_of("SnagA"))) if d > 3.0 else (None, 0)
                    else:
                        scale = min(scale, fit)
                    if piece:
                        P.add(piece, px, ground.at(px, pz) - 0.1, pz, hash01(px, pz, 5.0) * 360.0, scale, band=band)
                    if band == "near" and hash01(px, pz, 6.0) < 0.35:
                        ux = px + (hash01(px, pz, 7.0) - 0.5) * 4.0
                        uz = pz + (hash01(px, pz, 8.0) - 0.5) * 4.0
                        if dist_u(ux, uz) > 2.5 and not blocked(ux, uz, 0.5):
                            under = ("Fern", "Fern", "RockA", "Stump", "Mushrooms", "StumpMossy", "RockB", "Bush")[int(hash01(ux, uz) * 8)]
                            P.add(under, ux, ground.at(ux, uz), uz, hash01(ux, uz, 9.0) * 360.0, 0.8 + 0.4 * hash01(ux, uz, 10.0), band=band)
                x += step
            z += step
    # rocks along the gully's rims and the plateau's lip
    for r in ravine:
        for k in range(int((r.x1 - r.x0 + r.z1 - r.z0) / 6)):
            t = hash01(r.x0, k, 1.0)
            side = int(hash01(r.z0, k, 2.0) * 4)
            px = r.x0 + (r.x1 - r.x0) * t if side < 2 else (r.x0 - 1.8 if side == 2 else r.x1 + 1.8)
            pz = r.z0 + (r.z1 - r.z0) * t if side >= 2 else (r.z0 - 1.8 if side == 0 else r.z1 + 1.8)
            if dist_u(px, pz) > 1.6 and not any(q.contains(px, pz) for q in ravine) and not any(q.contains(px, pz, 1.0) for q in tall):
                P.add("RockA" if k % 2 else "RockB", px, ground.at(px, pz) - 0.3, pz, hash01(px, pz) * 360, 0.8 + 0.5 * hash01(pz, px), band="rim")


EDGE_BAND_MAX = 3.9  # the thicket band reaches over the walkable edge: kept under the 4-stud rule


def reach_of(piece):
    """A piece's reach from its origin on the ground plane (its widest bound), unscaled."""
    lo, hi = kit.build(piece).bounds()
    return max(-lo[0], hi[0], -lo[2], hi[2])


def camp_edge_lines(level, side):
    out = []
    for camp in level.camps.values():
        if camp.get("locks"):
            continue
        t = level.fence_thickness(camp)
        if side == "north":
            out.append(camp["z"] - camp["sz"] / 2 - t)
        elif side == "south":
            out.append(camp["z"] + camp["sz"] / 2 + t)
        elif side == "west":
            out.append(camp["x"] - camp["sx"] / 2 - t)
        else:
            out.append(camp["x"] + camp["sx"] / 2 + t)
    return out


def near_piece(k, s):
    if k < 0.32:
        return "FirHeroA", 0.85 + 0.35 * s
    if k < 0.6:
        return "FirHeroB", 0.9 + 0.35 * s
    if k < 0.75:
        return "FirMassB", 0.8 + 0.3 * s
    if k < 0.86:
        return "Broadleaf", 0.9 + 0.3 * s
    if k < 0.95:
        return "SnagA", 0.8 + 0.4 * s
    return "SnagB", 0.9 + 0.3 * s


def mid_piece(k, s):
    if k < 0.5:
        return "FirMassA", 0.9 + 0.4 * s
    if k < 0.93:
        return "FirMassB", 0.85 + 0.4 * s
    return "SnagA", 0.9 + 0.3 * s


def blanket(level: Level, ground: Ground, reserved: list[Rect]):
    """The far forest as one canopy: past ART.blanket.start studs from any walkable ground, an
    8-stud lattice of fir tops (alternate vertices high and low, so the top reads as a mass of
    spires from the lookout and the plateau), a dark flat underside, a skirt where it ends and
    trunks under the skirt. Far cheaper than trees, and the near bands stand in front of it."""
    bl = ART["blanket"]
    cell = bl["cell"]
    parts = level.union_parts()
    rects = [p[0] for p in parts]
    tall = [s.rect.grown(3.0) for s in level.solids if s.kind in ("wall", "pillar", "fence")]
    nx = int((ground.x1 - ground.x0) / cell)
    nz = int((ground.z1 - ground.z0) / cell)
    on = [[False] * nx for _ in range(nz)]
    for j in range(nz):
        for i in range(nx):
            cx = ground.x0 + (i + 0.5) * cell
            cz = ground.z0 + (j + 0.5) * cell
            r = Rect(cx - cell / 2, cx + cell / 2, cz - cell / 2, cz + cell / 2)
            d = min(q.distance(cx, cz) for q in rects) - cell * 0.7
            if d < bl["start"] - cell * 0.5:
                continue
            if any(q.overlaps(r) for q in tall) or any(q.overlaps(r) for q in ground.ravine) or any(q.overlaps(r) for q in reserved):
                continue
            if any(w.rect.distance(cx, cz) < 6 + cell for w in level.water):
                continue
            if ground.steep(cx, cz, 2.2):
                continue
            on[j][i] = True

    def vxz(i, j):
        x = ground.x0 + i * cell + (hash01(i, j, 1.0) - 0.5) * cell * 0.7
        z = ground.z0 + j * cell + (hash01(i, j, 2.0) - 0.5) * cell * 0.7
        return x, z

    def edge_vertex(i, j):
        for ii in (i - 1, i):
            for jj in (j - 1, j):
                if not (0 <= ii < nx and 0 <= jj < nz) or not on[jj][ii]:
                    return True
        return False

    def top(i, j):
        x, z = vxz(i, j)
        base = ground.at(x, z)
        if edge_vertex(i, j):
            # The canopy's rim comes down to its underside, so its edge reads as the slope of a
            # mass of firs, not as a wall.
            return (x, base + bl["under"] + 3.0 + 2.0 * hash01(i, j, 4.0), z)
        spire = bl["low"] + (bl["high"] - bl["low"]) * hash01(i, j, 3.0) ** 0.6
        return (x, base + spire + 4.0 * NOISE.n2(x / 40.0, z / 40.0, 9.0), z)

    def under(i, j):
        x, z = vxz(i, j)
        return (x, ground.at(x, z) + bl["under"], z)

    tris = []
    for j in range(nz):
        for i in range(nx):
            if not on[j][i]:
                continue
            a, b, c, d = top(i, j), top(i + 1, j), top(i + 1, j + 1), top(i, j + 1)
            for t in ((a, b, c), (a, c, d)) if hash01(i, j, 5.0) < 0.5 else ((a, b, d), (b, c, d)):
                t = up(*t)
                tris.append((*t, canopy_colour(t, i, j)))
            ua, ub, uc, ud = under(i, j), under(i + 1, j), under(i + 1, j + 1), under(i, j + 1)
            for t in ((ua, uc, ub), (ua, ud, uc)):
                n = lm.tri_normal(*t)
                t = t if n[1] < 0 else (t[0], t[2], t[1])
                tris.append((*t, FOLIAGE.FIR_DARK))
            # the skirt and the trunks on every side with no blanket beyond
            for di, dj, p0, p1 in ((0, -1, (i, j), (i + 1, j)), (1, 0, (i + 1, j), (i + 1, j + 1)), (0, 1, (i + 1, j + 1), (i, j + 1)), (-1, 0, (i, j + 1), (i, j))):
                ii, jj = i + di, j + dj
                if 0 <= ii < nx and 0 <= jj < nz and on[jj][ii]:
                    continue
                t0, t1 = top(*p0), top(*p1)
                u0, u1 = under(*p0), under(*p1)
                outward = (di, 0.0, dj)
                for t in ((u0, u1, t1), (u0, t1, t0)):
                    n = lm.tri_normal(*t)
                    if n[0] * outward[0] + n[2] * outward[2] < 0:
                        t = (t[0], t[2], t[1])
                    tris.append((*t, FOLIAGE.FIR_DARK))
                mx, mz = (u0[0] + u1[0]) / 2, (u0[2] + u1[2]) / 2
                m = kit.Mesh("trunk")
                gy = ground.at(mx, mz)
                m.frustum((mx, gy - 0.3, mz), 0.55, 0.4, u0[1] - gy + 0.6, BARK.BARK_DARK, sides=4, rot=hash01(mx, mz) * 3, top=False)
                tris.extend(m.tris)
    return tris


SUN = (0.42, 0.78, -0.46)


def canopy_colour(t, i, j):
    """A canopy facet's swatch by how squarely it faces the sun, so the spires read as lit and
    shaded fir tops from above rather than as a pattern."""
    n = lm.tri_normal(*t)
    length = math.sqrt(n[0] * n[0] + n[1] * n[1] + n[2] * n[2]) or 1.0
    lit = (n[0] * SUN[0] + n[1] * SUN[1] + n[2] * SUN[2]) / length + 0.25 * (hash01(i, j, 6.0) - 0.5)
    return FOLIAGE.FIR_TIP if lit > 0.82 else FOLIAGE.FIR if lit > 0.5 else FOLIAGE.FIR_DARK


def backdrop(level: Level, ground: Ground):
    """A ring of low forested hills round the domain, so no edge of the world shows from the
    lookout or the plateau: a coarse lattice rising from the domain's edge into ridges, coloured
    as far firs, with no underside (nobody can stand outside it)."""
    bd = ART["backdrop"]
    cx, cz = (ground.x0 + ground.x1) / 2, (ground.z0 + ground.z1) / 2
    hx, hz = (ground.x1 - ground.x0) / 2, (ground.z1 - ground.z0) / 2
    ring = 64
    rows = bd["rows"]
    pts = []
    for r in range(rows + 1):
        t = r / rows
        row = []
        for k in range(ring):
            a = k * math.tau / ring
            ca, sa = math.cos(a), math.sin(a)
            # the domain's own outline (a rounded rectangle) pushed outward
            scale = 1.0 / max(abs(ca) / hx, abs(sa) / hz)
            reach = bd["inner"] * (1 - t) + bd["outer"] * t
            x = cx + ca * (scale + reach * (0.15 + 0.85 * t) - 6.0 * (1 - t))
            z = cz + sa * (scale + reach * (0.15 + 0.85 * t) - 6.0 * (1 - t))
            if r == 0:
                y = ground.at(min(max(x, ground.x0), ground.x1), min(max(z, ground.z0), ground.z1)) + 14.0
            else:
                peak = bd["peak"][0] + (bd["peak"][1] - bd["peak"][0]) * (0.5 + 0.5 * NOISE.n2(a * 3.0, r * 0.9, 13.0))
                y = 8.0 + peak * math.sin(min(t, 0.8) / 0.8 * math.pi * 0.5) ** 1.3 + 6.0 * NOISE.n2(a * 9.0, r, 14.0)
            row.append((x, y, z))
        pts.append(row)
    tris = []
    for r in range(rows):
        for k in range(ring):
            a, b = pts[r][k], pts[r][(k + 1) % ring]
            c, d = pts[r + 1][(k + 1) % ring], pts[r + 1][k]
            for t in ((a, b, c), (a, c, d)):
                t = up(*t)
                y = sum(p[1] for p in t) / 3
                col = FOLIAGE.FIR_DARK if y < 30 else FOLIAGE.FIR if y < 70 else FOLIAGE.FIR_TIP
                tris.append((*t, col))
    return tris


# ---------------------------------------------------------------- the build


class Build:
    """Everything one run of the generator makes, in memory."""

    def __init__(self, level: Level):
        self.level = level
        log(f"layout {level.layout_name}: {len(level.walks)} walkable tops, {len(level.solids)} solids, {len(level.drops)} drops")
        level._barriers = barriers(level)
        self.ground = Ground(level)
        log(f"ground lattice {self.ground.nx} x {self.ground.nz} over x {self.ground.x0}..{self.ground.x1}, z {self.ground.z0}..{self.ground.z1}")
        self.P = Placements()
        cover = Bake("Cover", "palette")
        reserved = dress_camps(level, self.ground, self.P, cover)
        lintel = Bake("Lintel", "palette")
        gatehouse_arch(level, self.P, lintel)
        dress_brambles(level, self.ground, self.P)
        dress_pillars(level, self.P)
        dress_islands(level, self.ground, self.P)
        plant(level, self.ground, self.P, reserved)
        flat, slopes = self.ground.meshes()
        skin, deck = skins(level, self.ground)
        rocks = rock_faces(level, self.ground)
        step_faces(level, rocks)
        canopy = blanket(level, self.ground, reserved)
        hills = backdrop(level, self.ground)
        self.meshes: list[Bake] = []
        self.meshes += lm.split_by_cells("Floor", "texture", [(*t, None) for t in flat], 256.0, "forestFloor", TEXTURES["forestFloor"]["tile"], "ground")
        self.meshes += lm.split_by_cells("Slopes", "palette", slopes, 256.0, group="ground")
        self.meshes += lm.split_by_cells("Road", "texture", [(*t, None) for t in skin["road"]], 512.0, "road", TEXTURES["road"]["tile"], "skin")
        self.meshes += lm.split_by_cells("RoadRim", "texture", [(*t, None) for t in skin["roadRim"]], 512.0, "roadRim", TEXTURES["roadRim"]["tile"], "skin")
        self.meshes += lm.split_by_cells("CampFloor", "texture", [(*t, None) for t in skin["camp"]], 512.0, "camp", TEXTURES["camp"]["tile"], "skin")
        if skin["cave"]:
            self.meshes += lm.split_by_cells("CaveFloor", "texture", [(*t, None) for t in skin["cave"]], 512.0, "roadRim", TEXTURES["roadRim"]["tile"], "skin")
        self.meshes += lm.split_by_cells("Rock", "palette", rocks.tris, 256.0, group="rock")
        for bake in (deck, cover, lintel):
            bake.group = "camp"
            if bake.count():
                self.meshes.append(bake)
        self.meshes += lm.split_by_cells("Canopy", "palette", canopy, 256.0, group="canopy")
        self.meshes += lm.split_by_cells("Hills", "palette", hills, 4096.0, group="backdrop")
        # Baked placements into chunk meshes by area; props stay props.
        baked = []
        self.props = []
        for item in self.P.items:
            if item["piece"] in PROP_PIECES or item.get("with"):
                self.props.append(item)
            else:
                baked.extend(kit.build(item["piece"]).transformed(item["x"], item["y"], item["z"], item["yaw"], item["scale"]))
        self.meshes += lm.split_by_cells("Dress", "palette", baked, 192.0, group="dress")
        self.baked_items = [i for i in self.P.items if i["piece"] not in PROP_PIECES and not i.get("with")]

    def triangles(self) -> int:
        props = sum(kit.build(i["piece"]).count() for i in self.props)
        return sum(m.count() for m in self.meshes) + props

    def plan_hash(self) -> str:
        return plan_hash(self.level)

    def data(self) -> dict:
        level = self.level
        hidden = hide_list(level)
        pieces_used = sorted({i["piece"] for i in self.props})
        meshes = []
        for m in self.meshes:
            lo, hi = m.bounds()
            entry = {"name": m.name, "look": m.look, "group": m.group, "triangles": m.count(),
                     "min": [round(v, 3) for v in lo], "max": [round(v, 3) for v in hi]}
            if m.look == "texture":
                entry["texture"] = m.texture
            meshes.append(entry)
        effects = [{"kind": i["effect"], "x": i["x"], "y": round(i["y"] + 0.6, 3), "z": i["z"], "camp": i.get("camp")} for i in self.props if i.get("effect")]
        return {
            "version": 1,
            "level": level.config["id"],
            "layout": level.layout_name,
            "planHash": self.plan_hash(),
            "frame": "level",
            "units": "studs; yaw in degrees about +Y (CFrame.Angles); a prop's origin is its bottom centre, front -Z",
            "triangles": self.triangles(),
            "palette": "palette.png",
            "textures": {k: {"file": f"{k}.png", "tileStuds": v["tile"]} for k, v in TEXTURES.items()},
            "meshes": meshes,
            "props": [{k: v for k, v in i.items()} for i in self.props],
            "propPieces": pieces_used,
            "effects": effects,
            "barriers": [{"name": b["name"], "x": b["x"], "y": b["y"], "z": b["z"], "sx": b["sx"], "sy": b["sy"], "sz": b["sz"],
                          "group": "ArenaBarrier", "side": b["side"], "edge": b["edge"]} for b in level._barriers],
            "hide": hidden,
            "looks": LOOKS,
            "bakedPieces": count_pieces(self.baked_items),
        }


def count_pieces(items):
    out: dict[str, int] = {}
    for i in items:
        out[i["piece"]] = out.get(i["piece"], 0) + 1
    return dict(sorted(out.items()))


def hide_list(level: Level) -> dict:
    """The layout Parts W2 makes invisible (Transparency 1, collision kept) because a skin, a rock
    face or a prop now shows them; everything else keeps today's look."""
    blocks = sorted(b["name"] for b in level.layout["blocks"] if b["look"] in ("path", "ground", "wall") and b.get("collide", True) is not False)
    # A camp's roles are LevelGeometry's piece roles (its floor, fence strips, cover boxes, fire
    # markers and tent marker), so the server finds the Parts by role (L4W2-5).
    camps = {}
    for cid, camp in level.camps.items():
        camps[cid] = ["floor", "fence"]
        if camp.get("obstacles"):
            camps[cid].append("obstacle")
        if any(s["posture"] == "fire" for s in camp.get("spots") or []):
            camps[cid].append("fire")
        if camp.get("tent"):
            camps[cid].append("tent")
    return {"blocks": blocks, "camps": camps,
            "keep": ["water", "ice", "bramble", "secret chests", "signs", "checkpoints", "gates (camp C, while shut)"]}


def stage_geometry(level: Level) -> list:
    """What of the level's stages the dressing reads: each stage's kind and zone, and where its
    bosses stand (the Chief's hall is placed behind the boss point). A boss's kind, his Valor and
    every wave number are play, not geometry, so they never move the plan hash (L4W2-4)."""
    out = []
    for st in level.config.get("stages") or []:
        bosses = [(wave.get("boss") or {}).get("at") for wave in st.get("waves") or [] if wave.get("boss")]
        out.append({"kind": st.get("kind"), "zone": st.get("zone"), "bossAt": bosses})
    return out


def plan_hash(level: Level) -> str:
    """What the bake depends on: the layout as written, the fence thickness, the stages' geometry
    (stage_geometry), this generator's version and art numbers, and the kit's geometry. Any change
    is a re-bake and a paste."""
    h = hashlib.sha256()
    h.update(json.dumps(level.layout, sort_keys=True, separators=(",", ":")).encode("utf-8"))
    h.update(json.dumps({"fence": level.fence_default, "stages": stage_geometry(level)}, sort_keys=True).encode("utf-8"))
    h.update(json.dumps({"v": GENERATOR_VERSION, "art": ART, "props": PROP_PIECES, "tex": TEXTURES}, sort_keys=True).encode("utf-8"))
    for name in sorted(kit.PIECES):
        h.update(name.encode("utf-8"))
        h.update(kit.glb_bytes(kit.build(name)))
    return h.hexdigest()[:16]


def upload_record(build: Build, out_root: str, glbs: dict) -> dict:
    """The upload manifest, `<out_root>/<layout>.json` beside the bake folder (the Valley's bake
    record shape): what tools/assets/upload_level.py sends and what harvest.py checks Studio's
    sizes against. Every file is named relative to out_root with its sha256, so a file left over
    from another build is caught before an upload is spent on it. A mesh's size and centre are its
    GLB's own float32 bounding box (a flat sheet's 0.01 hair included), which the data file's
    rounded min/max are not. A texture forest_textures.py has not written yet is listed unhashed:
    the uploader refuses it by name."""
    layout = build.level.layout_name
    folder = os.path.join(out_root, layout)
    images = {}
    palette_path = os.path.join(folder, "palette.png")
    with open(palette_path, "rb") as fh:
        palette_bytes = fh.read()
    pal = lm.Palette()
    images["palette"] = {"file": f"{layout}/palette.png", "sha256": hashlib.sha256(palette_bytes).hexdigest(), "size": [pal.width, pal.height]}
    for name in sorted(TEXTURES):
        path = os.path.join(folder, "textures", f"{name}.png")
        entry = {"file": f"{layout}/textures/{name}.png", "sha256": "", "tileStuds": TEXTURES[name]["tile"]}
        if os.path.isfile(path):
            with open(path, "rb") as fh:
                data = fh.read()
            width, height = struct.unpack(">II", data[16:24]) if data[12:16] == b"IHDR" else (0, 0)
            entry.update({"sha256": hashlib.sha256(data).hexdigest(), "size": [width, height]})
        else:
            log(f"note: {entry['file']} is missing (run tools/levels/forest_textures.py); the upload record lists it unhashed")
        images[name] = entry
    meshes = {}
    for m in build.meshes:
        data, lo, hi = glbs[m.name]
        entry = {
            "file": f"{layout}/{m.name}.glb",
            "sha256": hashlib.sha256(data).hexdigest(),
            "triangles": m.count(),
            "vertices": 3 * m.count(),
            "centre": [round((lo[i] + hi[i]) / 2, 6) for i in range(3)],
            "size": [round(hi[i] - lo[i], 6) for i in range(3)],
            "look": m.look,
            "group": m.group,
        }
        if m.look == "texture":
            entry["texture"] = m.texture
        meshes[m.name] = entry
    return {
        "version": 1,
        "set": layout,
        "level": build.level.config["id"],
        "planHash": build.plan_hash(),
        "frame": "level",
        "images": images,
        "meshes": meshes,
    }


def write(build: Build, out_root: str, data_path: str) -> None:
    folder = os.path.join(out_root, build.level.layout_name)
    os.makedirs(folder, exist_ok=True)
    for f in os.listdir(folder):
        if f.endswith(".glb"):
            os.remove(os.path.join(folder, f))
    pal = lm.Palette()
    pal.write(os.path.join(folder, "palette.png"))
    glbs = {}
    for m in build.meshes:
        data, lo, hi = m.glb(pal, GENERATOR)
        glbs[m.name] = (data, lo, hi)
        with open(os.path.join(folder, m.name + ".glb"), "wb") as fh:
            fh.write(data)
    upload_path = os.path.join(out_root, f"{build.level.layout_name}.json")
    with open(upload_path, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(upload_record(build, out_root, glbs), fh, indent=1)
        fh.write("\n")
    log(f"wrote the upload record {upload_path}")
    record = build.data()
    record["paletteSwatches"] = pal.record()
    os.makedirs(os.path.dirname(data_path), exist_ok=True)
    with open(data_path, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(record, fh, indent=1, sort_keys=False)
        fh.write("\n")
    bake_path = os.path.join(folder, "bake.json")
    with open(bake_path, "w", encoding="utf-8", newline="\n") as fh:
        json.dump({"planHash": record["planHash"], "placements": build.P.items}, fh, separators=(",", ":"))
        fh.write("\n")
    log(f"wrote {len(build.meshes)} meshes + palette into {folder}")
    log(f"wrote {data_path}")


# ---------------------------------------------------------------- the gate


def check(build: Build, data_path: str) -> list[str]:
    """The QA gate: what `build` would write must equal the committed data file, and the rules in
    the module docstring must hold on it."""
    import forestcheck  # noqa: E402  (kept apart: it is long and only the gate needs it)

    return forestcheck.run(build, data_path)


def stats(build: Build) -> None:
    groups: dict[str, list] = {}
    for m in build.meshes:
        groups.setdefault(m.group, []).append(m)
    total = build.triangles()
    print(f"meshes {len(build.meshes)}, props {len(build.props)}, baked placements {len(build.baked_items)}, barriers {len(build.level._barriers)}")
    for g, ms in sorted(groups.items()):
        print(f"  {g:9s} {len(ms):3d} meshes {sum(m.count() for m in ms):7d} triangles")
    print(f"  props     {len(build.props):3d} placed  {sum(kit.build(i['piece']).count() for i in build.props):7d} triangles")
    print(f"  total {total} triangles (budget {TRI_BUDGET})")
    for piece, n in count_pieces(build.P.items).items():
        print(f"    {piece:14s} x{n:5d}  {n * kit.build(piece).count():7d} tris")


def main(argv) -> int:
    parser = argparse.ArgumentParser(description="Dress the Forest Road.")
    parser.add_argument("mode", choices=("build", "check", "stats"))
    parser.add_argument("--out-root", default=OUT_ROOT)
    parser.add_argument("--data", help="the dress data file (default src/shared/Config/LevelDress/<layout>.json)")
    args = parser.parse_args(argv)
    level = Level()
    args.data = args.data or os.path.join(DRESS_DIR, f"{level.layout_name}.json")
    build = Build(level)
    if args.mode == "stats":
        stats(build)
        return 0
    if args.mode == "build":
        stats(build)
        write(build, args.out_root, args.data)
        bad = check(build, args.data)
        for line in bad:
            print(f"[forest] FAIL {line}")
        return 1 if bad else 0
    bad = check(build, args.data)
    for line in bad:
        print(f"[forest] FAIL {line}")
    print(f"[forest] check: {'PASS' if not bad else f'{len(bad)} FAIL'}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
