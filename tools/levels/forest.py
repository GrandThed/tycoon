"""The Forest Road's dresser (L4): one deterministic generator that turns the level's layout into the
real forest, on paper. It writes the baked meshes, the props the client places, the new invisible
character-only walls, and one data file the game reads (src/shared/Config/LevelDress/<layout>.json,
the L4 W2 contract's L4W2-1: Rojo makes it a ModuleScript beside Valley.json).

    py tools/levels/forest.py build      # GLBs + palette into assets/build/levels/ForestRoad/,
                                         # the data file src/shared/Config/LevelDress/ForestRoad.json,
                                         # the upload record assets/build/levels/ForestRoad.json
    py tools/levels/forest.py check      # QA gate (see `check`); writes nothing
    py tools/levels/forest.py stats      # counts only
    py tools/levels/forest.py mutants    # proves each rule of the gate catches a fault (every line CAUGHT)

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
  * Rock never reaches into walking space: over walkable ground, up to REACH_ABOVE, every rock
    vertex lies on a collision solid's skin (a thin face's blocks at most THIN_OUT out of their
    wall), and no kit stone stands on walkable ground or water (the island shrine's ring and the
    summit's aside). Every rock is in the language of Ben's references (2026-10-21): clustered
    chamfered blocks, cut by pack_cells with no grid, course or long straight joint (his second
    look, the same day: "less regular walls").
  * The climb (MISSIONS_DESIGN 28, tools/check_parkour.py CLIMBS): its yard, trail and path are
    walled to the climb's wallTop; its summit opens no designed drop; no tree on a ledge or the
    summit, nothing on a hop's take-off or landing; the summit's ring of standing stones stays
    under 4 studs and outside the chest's trigger.
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
sys.path.insert(0, os.path.join(REPO_ROOT, "tools"))
import check_parkour  # noqa: E402  (CLIMBS only: the climb's pieces and its wall's height)
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
DROP_MAX = 50.0  # a double-jump secret's designed drop: only across to a block a double jump can carry (the lookout's is 18)
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
    # Round the climb's yard (seen from inside it and from the ledges above, never along a road):
    # the near band at `yardNear` of its trees, no middle band, the thicket band `yardEdge` times
    # as sparse, and the canopy from `blanket.yardStart` (it stands where the middle band would).
    "trees": {"near": [5.0, 11.0], "mid": [11.0, 19.0], "nearStep": 7.2, "midStep": 7.8, "yardNear": 0.45, "yardEdge": 2.4},
    "blanket": {"start": 17.0, "cell": 15.0, "under": 6.5, "low": 14.0, "high": 27.0, "yardStart": 11.0, "deep": 3},
    "massif": {"reach": 28.0, "margin": 3.0, "slope": 2.2},
    "backdrop": {"inner": 40.0, "outer": 520.0, "ring": 20, "rows": 6, "peak": [40.0, 110.0]},
    "camps": {"clutterA": 12, "clutterB": 20, "clutterC": 12, "seats": 4},
    # Ben's rock references (2026-10-21): the cliffs are clustered chamfered blocks (rock_faces), cut
    # by pack_cells (his second look, the same day: "less regular walls", no grid, no course).
    # Per style, studs: the blocks' width and height ranges (their means set the size and how much
    # taller than wide a block is), the spread of one block's size round that mean, how far a block's
    # front stands out of the collision face (negative: behind it), the front corners' extra rise
    # (its facets), the chamfer, how deep the dark backing lies, the front's slide (a tilt), how far
    # the chamfer runs in (times the bevel), the shortest edge a block keeps, and (`mass`, default 2.4)
    # how many blocks across a mass of pack_cells is (a small face wants smaller masses).
    "cliff": {
        "gap": 0.14,  # between two blocks: the backing's crevice
        "crevice": 2.0,  # some crevices up to this many times wider
        "poke": [-1.5, 3.2],  # a block over a free top edge
        "crown": 0.45,  # the tilt of a free block's top
        "crownBevel": 2.0,  # and its bigger chamfer
        "thinBack": 1.5,  # how deep a thin face's blocks may sit back, where the wall is thick enough
        "skyline": 16.0,  # studs: how long a rise or fall of a free top's skyline runs
        "talus": [3.0, 24.0],  # a face nobody stands at bulges this much more at its foot, fading over this height
        "clear": 1.5,  # and every block of it stops this far short of ground a walker stands on or falls into
        "nearReach": 32.0,  # a face this near a walker carries the "near" blocks
        "blend": 30.0,  # and they grow to the "far" ones over this many studs farther
        "foot": [0.55, 24.0],  # a thin face's blocks at its foot: this share of the size, growing over this height
        "thin": {"width": [8.0, 17.0], "height": [14.0, 32.0], "spread": [0.5, 1.7], "front": [-1.3, 0.06], "lift": 0.9,
                 "bevel": [0.5, 0.95], "back": 0.8, "shear": 0.35, "round": 2.3, "minEdge": 1.5},
        "tunnel": {"width": [14.0, 26.0], "height": [18.0, 32.0], "spread": [0.6, 1.5], "front": [-1.0, 0.06], "lift": 0.6,
                   "bevel": [0.45, 0.8], "back": 0.8, "shear": 0.3, "round": 2.0, "minEdge": 1.5},
        "step": {"width": [2.5, 6.0], "height": [3.0, 6.0], "spread": [0.6, 1.4], "front": [-0.7, 0.06], "lift": 0.3,
                 "bevel": [0.25, 0.45], "back": 1.0, "shear": 0.12, "round": 1.6, "minEdge": 0.7},
        "near": {"width": [9.0, 19.0], "height": [16.0, 36.0], "spread": [0.5, 1.7], "front": [0.5, 4.5], "lift": 1.3,
                 "bevel": [0.6, 1.1], "back": 0.3, "shear": 0.55, "round": 2.0, "minEdge": 1.5, "poke": [-2.0, 5.5]},
        "far": {"width": [13.0, 26.0], "height": [24.0, 48.0], "spread": [0.55, 1.6], "front": [0.8, 4.5], "lift": 1.6,
                "bevel": [0.8, 1.4], "back": 0.3, "shear": 0.8, "round": 1.9, "minEdge": 2.0, "poke": [-2.0, 6.0]},
        "pillar": {"width": [5.0, 10.0], "height": [7.0, 15.0], "spread": [0.6, 1.5], "front": [0.3, 2.2], "lift": 0.45,
                   "bevel": [0.4, 0.8], "back": 0.3, "shear": 0.4, "round": 1.8, "minEdge": 1.0, "mass": 1.7},
        "gully": {"width": [6.0, 13.0], "height": [11.0, 22.0], "spread": [0.6, 1.5], "front": [0.3, 1.6], "lift": 0.4,
                  "bevel": [0.4, 0.8], "back": 1.0, "shear": 0.3, "round": 1.7, "minEdge": 1.0},
        # The mountain's faces (mountain_faces): thin where a body stands beside them (the yard, a
        # ledge below), the big "mountUp" blocks bulging above that reach, finer blocks in the `fine`
        # band under a ledge's top (band, size share), where the player stands and looks at them.
        # `wrap`: how far a block high on one of the tower's outer corners may run round it.
        "mount": {"width": [9.0, 20.0], "height": [16.0, 36.0], "spread": [0.5, 1.6], "front": [-1.3, 0.06], "lift": 0.9,
                  "bevel": [0.6, 1.0], "back": 1.2, "shear": 0.35, "round": 2.3, "minEdge": 2.0, "above": "mountUp",
                  "fine": [16.0, 0.3], "wrap": 4.0},
        "mountUp": {"width": [10.0, 20.0], "height": [20.0, 42.0], "spread": [0.5, 1.7], "front": [1.0, 7.0], "lift": 1.6,
                    "bevel": [0.8, 1.4], "back": 0.3, "shear": 0.8, "round": 1.9, "minEdge": 1.8},
        "cap": {"width": [8.0, 14.0], "front": [0.5, 2.4], "lift": 0.4, "bevel": [0.5, 0.9], "back": 1.5, "shear": 0.4,
                "overhang": 0.6, "moss": 0.25, "rim": 3.0, "narrow": [12.0, 20.0], "floor": 0.35, "slant": 1.2, "tilt": 0.18, "round": 1.8},
    },
    # The massif round the walled camp, the plateau's lips and the gully's walls: columns of
    # chamfered blocks standing on the ground (massif_columns, lip_columns, gully_columns).
    # The stones of reference 1 placed out in the forest (scatter_stones, foot_boulders): cluster
    # spacing and band (studs from walkable ground), the clearance from a tree, the anchor and
    # companion pieces, the spacing of stones on a bank and at a cliff's foot.
    "stones": {"step": 38.0, "band": [5.0, 9.0], "trunk": 2.6,
               "anchors": ["StoneMonolith", "StoneTall", "StandingStone", "StoneSlim", "StoneBroad", "RockB", "StoneLean", "RockB"],
               "small": ["RockA", "RockFlat", "RockSmall", "RockSmall"], "pebbles": 0.3, "bank": 18.0, "foot": 22.0, "clear": 5.0,
               "bed": 0.6},
    # The mountain (the climb, MISSIONS_DESIGN 28): its cap stones (mean size, spread, shortest edge,
    # the mass factor, how far a stone's top rises over the top's lift, the grout's width, the
    # chamfer's run, the overhang over a side that drops), the scree on the yard at its foot (how
    # far out, how many, their radii and tops), the summit's ring of standing stones (radius from
    # the chest, the gap toward the last hop in degrees, heights) and the yard's firs (as shares of
    # the yard's rect, in its far corners).
    "mountain": {
        "cap": {"size": 9.5, "spread": [0.55, 1.6], "minEdge": 1.2, "mass": 1.0, "rise": 0.04, "tilt": 0.05, "gap": 0.2, "inset": 0.35, "overhang": 0.15},
        "scree": {"band": 7.0, "count": 24, "size": [0.7, 2.0], "rise": [0.1, 0.18]},
        "ring": {"radius": 10.5, "open": 100.0, "height": [2.8, 3.7]},
        "yardFirs": [[0.06, 0.06], [0.94, 0.06]],
    },
    # Boulder piles where nobody walks (boulder_piles): how far out of a camp's fence line and along
    # past a gate's end, how far out of a wall's corner, how near walkable ground a corner must be,
    # the least distance between two piles, and the heap (piece, distance from the pile's centre,
    # scale).
    "piles": {"out": 5.0, "along": 5.0, "corner": 3.0, "beside": 8.0, "spacing": 10.0,
              "heap": [["RockB", 0.0, 1.15], ["StoneBroad", 2.6, 0.9], ["Pebbles", 2.2, 1.0]]},
    # Firs on the cave ridge's wide tops, and round the walled camp's rim: the spacing, studs.
    "ridgeFirs": 15.0,
    "crownFirs": 15.0,
    "massifRock": {"cell": [8.0, 12.0], "slant": 1.6, "poke": [0.3, 2.4], "bevel": [0.6, 1.2], "lift": 0.5, "shear": 0.5,
                   "minRise": 1.5, "keep": 1.5, "round": 1.6,
                   "stack": [10.0, 18.0], "ledge": [0.35, 0.9]},
    "lipRock": {"width": [3.5, 7.0], "out": [0.4, 2.2], "into": 1.2, "poke": [0.1, 1.4], "bevel": [0.4, 0.8], "lift": 0.35,
                "reach": 55.0, "keep": 1.0, "round": 1.5},
}
THIN_OUT = 0.12  # a block over walking ground stands at most this far out of the collision face

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
        # A climb (tools/check_parkour.py CLIMBS, MISSIONS_DESIGN 28): the mountain's yard, ledges
        # and summit, dressed by mountain_faces and walled to its wallTop.
        self.climb = check_parkour.CLIMBS.get(self.layout_name)
        self.climb_pieces = set()
        if self.climb:
            self.climb_pieces = set(self.climb["yard"]) | set(self.climb["ledges"]) | {self.climb["summit"]}
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
            across from it, over their shared span (the lookout's 18-stud gap), when that block is no
            farther than DROP_MAX. A climb's summit has none: every fall off it is designed onto a
            lower ledge or the walled yard (check_parkour's fall table)."""
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
            if s.get("needs") != "doubleJump" or (self.climb and s.get("id") == self.climb["secret"]):
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
            if best is not None and best[0] <= DROP_MAX:
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
    the highest walkable top within 20 studs (a climb's yard, trail and path: to the climb's
    wallTop, over every flight off its summit). Thickness `barrier.thickness`, cut short of any other
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
                if on_climb(level, side, c, a2, b2):
                    hi_y = max(hi_y, float(level.climb["wallTop"]))
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


def climb_yard(level: Level):
    """The climb's yard (the first of CLIMBS `yard`: the ground round the mountain), or None."""
    if not level.climb or level.climb["yard"][0] not in level.blocks:
        return None
    return Rect.of(level.blocks[level.climb["yard"][0]])


def yard_nearest(level: Level, rects, x, z) -> bool:
    """Is the climb's yard the walkable ground nearest to (x, z)?"""
    yard = climb_yard(level)
    return yard is not None and yard.distance(x, z) <= min(r.distance(x, z) for r in rects) + 1e-6


def climb_outline(level: Level) -> list[Rect]:
    """The ground at a climb's foot (check_parkour CLIMBS `yard`: the yard, the trail, the path)."""
    if not level.climb:
        return []
    return [Rect.of(level.blocks[n]) for n in level.climb["yard"] if n in level.blocks]


def on_climb(level: Level, side, c, a, b) -> bool:
    """Does the walled stretch [a, b] of line c on `side` run along a climb's yard piece?"""
    nx, nz = SIDES[side]
    for r in climb_outline(level):
        edge = (r.x1 if nx > 0 else r.x0) if nx else (r.z1 if nz > 0 else r.z0)
        lo, hi = (r.z0, r.z1) if nx else (r.x0, r.x1)
        if abs(edge - c) < 1e-4 and min(b, hi) - max(a, lo) > 1e-3:
            return True
    return False


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
        self.masked: set[tuple[int, int]] = set()  # cells a rock column covers whole (mask_quads)
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

    def mask_quads(self, quads, inset: float) -> None:
        """Drop the cells lying whole inside one of `quads` (counter-clockwise (x, z) outlines of
        rock columns standing on the ground, shrunk by `inset`): nobody sees the ground under a
        column, and a column's foot reaches below every lattice point it covers (massif_columns)."""
        g = self.g
        for quad in quads:
            q = kit.inset_poly(kit.poly_ccw(quad), inset)
            xs, zs = [p[0] for p in q], [p[1] for p in q]
            i0, i1 = int(math.floor((min(xs) - self.x0) / g)), int(math.ceil((max(xs) - self.x0) / g))
            j0, j1 = int(math.floor((min(zs) - self.z0) / g)), int(math.ceil((max(zs) - self.z0) / g))
            for j in range(max(j0, 0), min(j1, self.nz)):
                for i in range(max(i0, 0), min(i1, self.nx)):
                    corners = ((self.x0 + i * g, self.z0 + j * g), (self.x0 + (i + 1) * g, self.z0 + j * g),
                               (self.x0 + (i + 1) * g, self.z0 + (j + 1) * g), (self.x0 + i * g, self.z0 + (j + 1) * g))
                    if all(inside_convex(q, cx, cz) for cx, cz in corners):
                        self.masked.add((i, j))

    def lattice_range(self, quad):
        """The lowest and highest lattice height under a quad's box (one cell round it)."""
        g = self.g
        xs, zs = [p[0] for p in quad], [p[1] for p in quad]
        i0, i1 = int(math.floor((min(xs) - self.x0) / g)), int(math.ceil((max(xs) - self.x0) / g))
        j0, j1 = int(math.floor((min(zs) - self.z0) / g)), int(math.ceil((max(zs) - self.z0) / g))
        lo, hi = math.inf, -math.inf
        for j in range(max(j0, 0), min(j1, self.nz) + 1):
            for i in range(max(i0, 0), min(i1, self.nx) + 1):
                lo = min(lo, self.h[j][i])
                hi = max(hi, self.h[j][i])
        return lo, hi

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
        for (i, j) in self.masked:
            used[j][i] = True
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
                if flat[j][i] or (i, j) in self.masked:
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
            # A steep slope shows only in the crevices between rock columns, or far off: the
            # dark of a cliff in shade, never the noisy three-tone face it was (Ben, 2026-10-21).
            return ROCK.ROCK_SHADE if hash01(cx * 0.31, cz * 0.17, y) < 0.6 else ROCK.ROCK_DARK
        if rise > 1.0 or y < -0.9:
            return GROUND.MUD if hash01(cx, cz) < 0.5 else ROCK.ROCK_DARK
        return GROUND.NEEDLES if hash01(cx, cz, 2.0) < 0.6 else GROUND.FLOOR_DARK


def up(a, b, c):
    n = lm.tri_normal(a, b, c)
    return (a, c, b) if n[1] < 0 else (a, b, c)


def inside_convex(quad, x, z) -> bool:
    """Is (x, z) inside a counter-clockwise convex polygon (edges included)?"""
    n = len(quad)
    for k in range(n):
        a, b = quad[k], quad[(k + 1) % n]
        if (b[0] - a[0]) * (z - a[1]) - (b[1] - a[1]) * (x - a[0]) < -1e-9:
            return False
    return True


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
        elif w in level.pillars and w.name not in level.climb_pieces:  # the mountain's tops: mountain_caps
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
    """Rock over every exposed face of the tall solids, in the language of Ben's references
    (2026-10-21, assets/research/2026-10-21-l4/ref_rocks_cliffs.png): a cliff of clustered, stacked
    chamfered blocks (forest_kit.block) in columns of varied width, each column stacked to its own
    heights so no seam runs across the face, over a dark backing quad that closes every crevice
    (nothing of the hidden collision wall, nor the sky through it, shows between two blocks). The
    tops get bigger caps; a free top edge is broken by columns standing a little over it; firs grow
    on the wide tops nobody reaches.

    How far a block may stand out is the collision rule: a face that looks onto ground a player
    walks ("thin") keeps every block within 0.12 stud in front of the collision face and at most
    0.55 behind it, up to REACH_ABOVE over the floor in front (a double jump and a head), and may
    bulge like any other cliff above that. A face nobody stands at bulges up to ART.cliff's front.
    Inside a walled camp nothing rises over the wall's top."""
    parts = level.union_parts()
    bake = Bake("RockFaces", "palette")
    # walkable ground a face's blocks are sized for: never the cave's inside (behind the ridge)
    walk_rects = [p[0] for p in parts if p[2] != "drop" and p[3] not in level.roofed]
    screens = [s.rect for s in level.solids if s.kind in ("wall", "fence", "pillar") and s.hi[1] - s.lo[1] > 20]
    open_rects = [p[0] for p in parts]  # walkable ground, the open camps' fence strips, water and the drops
    pillar_tops = {s.name: s.hi[1] for s in level.solids if s.kind == "pillar"}
    walled = walled_floors(level)
    for axis, sign, plane, (u0, u1, v0, v1), s in exposed_faces(level):
        if s.name in level.climb_pieces:
            continue  # the mountain: mountain_faces and mountain_caps
        seed = hash01(axis * 7.0 + sign, plane, u0, v0) * 1000.0
        if axis == 1:
            if sign < 0:
                if not faces_walkable(level, parts, axis, sign, plane, (u0 + u1) / 2, (v0 + v1) / 2):
                    continue
                block_face(bake, axis, sign, plane, (u0, u1, v0, v1), "tunnel", seed,
                           back=thin_depth(level, parts, s, axis, sign, (u0 + u1) / 2, (v0 + v1) / 2))
            elif s.kind != "pillar":
                block_caps(bake, plane, (u0, u1, v0, v1), s, walled, seed)
            continue
        top_edge = v1
        if s.kind == "pillar":
            v1 = min(v1, pillar_tops[s.name]) - 0.05
        lows = []
        for k in range(9):
            uu = u0 + (u1 - u0) * k / 8
            gx, gz = (plane + sign * 1.0, uu) if axis == 0 else (uu, plane + sign * 1.0)
            lows.append(ground.at(gx, gz))
        v0c = max(v0, min(lows) - 1.0)
        if v0c >= v1 - 0.3:
            continue
        thin = faces_walkable(level, parts, axis, sign, plane, (u0 + u1) / 2, (v0c + v1) / 2)
        inward = thin and s.kind == "fence" and any(f.overlaps(s.rect.grown(0.01)) for f in walled)
        free = s.kind != "pillar" and not inward and abs(top_edge - s.hi[1]) < 1e-6 and not covered_above(level, s, axis, sign, plane, u0, u1, top_edge)
        if thin:
            style = "tunnel" if roofed_in_front(level, axis, sign, plane, u0, u1) else "thin"
            reach = floor_in_front(level, axis, sign, plane, u0, u1) + REACH_ABOVE
            block_face(bake, axis, sign, plane, (u0, u1, v0c, v1), style, seed, reach=reach, free_top=free,
                       back=thin_depth(level, parts, s, axis, sign, (u0 + u1) / 2, (v0c + v1) / 2))
            continue
        # A face nobody stands at: where only far walkers see it, it carries bigger blocks (the sizes
        # blend along it, so no seam runs up the face where near turns to far).
        if s.kind == "pillar":
            top = v1 + ART["cliff"]["gap"] / 2  # its blocks end flush with the ledge's top
            block_face(bake, axis, sign, plane, (u0, u1, v0c, top), "pillar", seed, pillar=True, backing_region=(u0, u1, v0c, v1),
                       open_rects=open_rects)
            continue
        near_at = face_reach(walk_rects, axis, sign, plane, u0, u1, screens)
        style = "near" if min(near_at(u0 + (u1 - u0) * k / 8) for k in range(9)) < ART["cliff"]["nearReach"] else "far"
        block_face(bake, axis, sign, plane, (u0, u1, v0c, v1), style, seed, free_top=free, open_rects=open_rects, near_at=near_at)
    ridge_firs(level, bake)
    crown_firs(level, ground, parts, bake)
    return bake


def room_ahead(rects, axis, sign, plane, ua, ub) -> float:
    """How far in front of a face (along its normal) the nearest of `rects` begins, over [ua, ub]."""
    best = math.inf
    for r in rects:
        lo_u, hi_u = (r.z0, r.z1) if axis == 0 else (r.x0, r.x1)
        if hi_u <= ua or lo_u >= ub:
            continue
        lo_w, hi_w = (r.x0, r.x1) if axis == 0 else (r.z0, r.z1)
        if (sign > 0 and hi_w <= plane + 1e-6) or (sign < 0 and lo_w >= plane - 1e-6):
            continue  # wholly behind the face
        d = (lo_w - plane) if sign > 0 else (plane - hi_w)
        best = min(best, max(0.0, d))  # a rect reaching past the face's plane leaves no room
    return best


def thin_depth(level: Level, parts, s, axis, sign, u, v) -> float:
    """How deep a thin face's blocks may sit back: ART.cliff.thinBack, within the wall's thickness
    less what its other face's blocks take (half of it when walkers stand on both sides)."""
    cf = ART["cliff"]
    thickness = s.hi[axis] - s.lo[axis]
    other = s.lo[axis] if sign > 0 else s.hi[axis]
    if faces_walkable(level, parts, axis, -sign, other, u, v):
        return max(0.3, min(cf["thinBack"], thickness / 2 - 0.05))
    return max(0.3, min(cf["thinBack"], thickness - cf["near"]["back"] - 0.1))


def massif_columns(level: Level, ground: Ground) -> list:
    """The rock massif round a walled camp (the Chief's hollow) as stepped columns of chamfered
    blocks, reference 2's outcrops: a jittered grid of columns over the massif, each standing from
    under the lowest ground it covers to a little over the highest, so the slope reads as blocks
    stacked in terraces up to the wall's rim (a column by the wall stands a little over it: the
    clearing's broken skyline). The ground under a column is dropped (Ground.mask_quads)."""
    mc = ART["massifRock"]
    gap = ART["cliff"]["gap"]
    keep = [w.rect.grown(mc["keep"]) for w in level.walks] + [d.grown(mc["keep"]) for d in level.drops]
    keep += [wt.rect.grown(mc["keep"]) for wt in level.water]
    keep += [s.rect.grown(0.1) for s in level.solids if s.kind in ("wall", "pillar")]
    m = kit.Mesh("massif")
    quads = []
    for n, (fenced, top, _others) in enumerate(ground.massifs):
        dom = fenced.grown(ART["massif"]["reach"] * 1.3)
        seed = 7000.0 + n
        for k, j, quad, _top in joint_grid(dom.x0, dom.x1, dom.z0, dom.z1, mc["cell"], mc["cell"], seed, mc["slant"], 0.0):
            q = kit.poly_ccw(quad)
            box = Rect(min(p[0] for p in q), max(p[0] for p in q), min(p[1] for p in q), max(p[1] for p in q))
            if box.overlaps(fenced) or any(box.overlaps(r) for r in keep):
                continue
            cx, cz = sum(p[0] for p in q) / 4, sum(p[1] for p in q) / 4
            base = level.zone_level(cx, cz)
            hi = max([ground.at(p[0], p[1]) for p in q] + [ground.at(cx, cz)])
            if hi - base < mc["minRise"]:
                continue
            lo, _hi = ground.lattice_range(q)
            front = min(hi + mc["poke"][0] + (mc["poke"][1] - mc["poke"][0]) * hash01(seed, k, j, 1.0), top + mc["poke"][1])
            # A tall column is a stack: blocks of their own heights, each a little narrower than the
            # one under it, so its side reads as ledges (reference 2), not one plain face.
            bottom = lo - 1.0
            cuts = [front]
            while cuts[-1] - bottom > mc["stack"][1]:
                cuts.append(cuts[-1] - mc["stack"][0] - (mc["stack"][1] - mc["stack"][0]) * hash01(seed, k, j, 20.0 + len(cuts)))
            cuts.append(bottom)
            levels = len(cuts) - 1
            for i in range(levels):
                ledge = sum(mc["ledge"][0] + (mc["ledge"][1] - mc["ledge"][0]) * hash01(seed, k, j, 30.0 + t) for t in range(levels - 1 - i))
                outline = kit.inset_poly(q, ledge) if ledge > 0 else q
                if kit.poly_span(outline) < 1.5:
                    continue
                seg_top, seg_back = cuts[i], (cuts[i + 1] - (0.6 if i < levels - 1 else 0.0))
                bevel = mc["bevel"][0] + (mc["bevel"][1] - mc["bevel"][0]) * hash01(seed, k, j, 2.0 + i)
                lifts = [(hash01(seed, k, j, 3.0 + i + 0.1 * c) - 0.5) * 2 * mc["lift"] for c in range(4)]
                sh = mc["shear"] if i == 0 else 0.0
                shear = ((hash01(seed, k, j, 8.0 + i) - 0.5) * 2 * sh, (hash01(seed, k, j, 9.0 + i) - 0.5) * 2 * sh)
                kit.block_poly(m, (0.0, 0.0, 0.0), (1.0, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0), outline, seg_back, seg_top, bevel,
                               shear=shear, lift=lifts, tone=hash01(seed, k, j, 10.0 + i), side_role="face", gap=gap,
                               inset=bevel * mc["round"])
            quads.append(q)
    ground.mask_quads(quads, gap / 2 + 0.15)
    return m.tris


def lip_columns(level: Level, ground: Ground) -> list:
    """The plateau's lips (the 8-stud cliff the road climbs at Road5, the step up to the highland)
    as a row of chamfered columns standing on the lower ground, their tops a little over the upper
    one, where a walker can see them (within ART.lipRock.reach of walkable ground)."""
    lc = ART["lipRock"]
    gap = ART["cliff"]["gap"]
    parts = level.union_parts()
    walk = [p[0] for p in parts]
    keep = [r.grown(lc["keep"]) for r in walk] + [s.rect.grown(0.5) for s in level.solids] + list(ground.ravine)
    keep += [wt.rect.grown(2.0) for wt in level.water]
    levels = ART["zones"]["levels"]
    band = ART["zones"]["band"]
    m = kit.Mesh("lips")
    quads = []
    for n, lip in enumerate(ART["zones"]["lips"]):
        upper = levels[n + 1]
        seed = 7100.0 + n
        for k, (za, zb) in enumerate(split_span(ground.z0, ground.z1, lc["width"], seed)):
            xa, xb = level.lip_x(lip, za), level.lip_x(lip, zb)
            if abs(xa - xb) > 6.0:
                continue  # the lip turns a corner here (under the ridge)
            xm = (xa + xb) / 2
            if min(r.distance(xm, (za + zb) / 2) for r in walk) > lc["reach"]:
                continue
            out_a = band + lc["out"][0] + (lc["out"][1] - lc["out"][0]) * hash01(seed, k, 1.0)
            out_b = band + lc["out"][0] + (lc["out"][1] - lc["out"][0]) * hash01(seed, k + 1, 1.0)
            quad = kit.poly_ccw([(xa - out_a, za), (xa + lc["into"], za), (xb + lc["into"], zb), (xb - out_b, zb)])
            box = Rect(min(p[0] for p in quad), max(p[0] for p in quad), za, zb)
            if any(box.overlaps(r) for r in keep):
                continue
            lo, _hi = ground.lattice_range(quad)
            front = upper + lc["poke"][0] + (lc["poke"][1] - lc["poke"][0]) * hash01(seed, k, 2.0)
            bevel = lc["bevel"][0] + (lc["bevel"][1] - lc["bevel"][0]) * hash01(seed, k, 3.0)
            lifts = [(hash01(seed, k, 4.0 + i) - 0.5) * 2 * lc["lift"] for i in range(4)]
            kit.block_poly(m, (0.0, 0.0, 0.0), (1.0, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0), quad, lo - 1.0, front, bevel,
                           shear=((hash01(seed, k, 8.0) - 0.5) * 0.6, 0.0), lift=lifts, tone=hash01(seed, k, 9.0),
                           side_role="face", gap=gap, inset=bevel * lc["round"])
            quads.append(quad)
    ground.mask_quads(quads, gap / 2 + 0.15)
    return m.tris


def gully_faces(level: Level, ground: Ground, bake: Bake) -> None:
    """The gully's walls (under the trailhead gap and the lookout's double-jump gap, and on into
    the creek) as cliffs of stacked blocks like every other tall face (block_face, "gully"): one
    face per wall, in the middle of the heightfield's slope down from the rim, its blocks standing
    out into the gully, their tops under the rim (no ledge to land on)."""
    wall = ART["ravine"]["wall"]
    depth = ART["ravine"]["depth"]
    for n, r in enumerate(ground.ravine):
        for side, (nx, nz) in SIDES.items():
            lo_u, hi_u = (r.x0, r.x1) if nz else (r.z0, r.z1)
            edge = (r.z0 if nz < 0 else r.z1) if nz else (r.x0 if nx < 0 else r.x1)
            # Cut the wall where the gully runs on (another ravine) or water lies beyond it.
            open_cuts = []
            for q in list(ground.ravine) + [w.rect for w in level.water]:
                if q is r:
                    continue
                if nz and q.z0 - 1e-6 <= edge + nz * 0.6 <= q.z1 + 1e-6:
                    open_cuts.append((q.x0, q.x1))
                elif nx and q.x0 - 1e-6 <= edge + nx * 0.6 <= q.x1 + 1e-6:
                    open_cuts.append((q.z0, q.z1))
            plane = edge - (nz if nz else nx) * wall / 2
            axis = 2 if nz else 0
            sign = -(nz if nz else nx)  # the face looks into the gully
            for k, (a, b) in enumerate(lm.subtract_intervals(lo_u, hi_u, open_cuts)):
                if b - a < 1.0:
                    continue
                um = (a + b) / 2
                ox, oz = (um, edge + nz * 0.6) if nz else (edge + nx * 0.6, um)
                rim = min(ground.at(*((u, edge + nz * 0.6) if nz else (edge + nx * 0.6, u))) for u in (a, um, b))
                base = level.zone_level(ox, oz)
                seed = 7200.0 + n * 16 + list(SIDES).index(side) * 4 + k
                block_face(bake, axis, sign, plane, (a, b, base - depth - 2.0, rim - 0.15), "gully", seed)


def walled_floors(level: Level) -> list[Rect]:
    """The floor of every walled (locked) camp: nothing of the dressing rises over its wall there."""
    out = []
    for camp in level.camps.values():
        if camp.get("locks"):
            out.append(Rect(camp["x"] - camp["sx"] / 2, camp["x"] + camp["sx"] / 2, camp["z"] - camp["sz"] / 2, camp["z"] + camp["sz"] / 2))
    return out


def roofed_in_front(level: Level, axis, sign, plane, u0, u1) -> bool:
    """Does a thin face look onto a roofed walk (the cave tunnel), and nothing else?"""
    seen = []
    for w in level.walks:
        r = w.rect
        if axis == 0:
            near = (r.x0 - 3 <= plane + sign * 1.5 <= r.x1 + 3) and r.z1 > u0 and r.z0 < u1
        else:
            near = (r.z0 - 3 <= plane + sign * 1.5 <= r.z1 + 3) and r.x1 > u0 and r.x0 < u1
        if near:
            seen.append(w.name in level.roofed)
    return bool(seen) and all(seen)


def face_distance(walk_rects, axis, sign, plane, u0, u1, screens=()) -> float:
    """How near a face comes to walkable ground in front of it (studs on the ground plane; ground
    behind the face, or behind a tall wall standing in front of it, does not count): it sets the
    size of its blocks (a face seen only from far carries bigger ones). `screens`: the plan rects
    of the tall solids that hide what lies past them."""
    best = math.inf
    ahead = []
    for r in walk_rects:
        lo, hi = (r.x0, r.x1) if axis == 0 else (r.z0, r.z1)
        if not ((sign > 0 and hi > plane + 0.5) or (sign < 0 and lo < plane - 0.5)):
            continue
        rlo, rhi = (r.z0, r.z1) if axis == 0 else (r.x0, r.x1)
        hidden = False
        for q in screens:
            qlo, qhi = (q.x0, q.x1) if axis == 0 else (q.z0, q.z1)
            ulo, uhi = (q.z0, q.z1) if axis == 0 else (q.x0, q.x1)
            between = (qlo >= plane - 1e-6 and qhi <= lo + 1e-6) if sign > 0 else (qhi <= plane + 1e-6 and qlo >= hi - 1e-6)
            if between and ulo <= max(u0, rlo) + 1e-6 and uhi >= min(u1, rhi) - 1e-6:
                hidden = True
                break
        if not hidden:
            ahead.append(r)
    for k in range(7):
        u = u0 + (u1 - u0) * k / 6
        x, z = (plane + sign * 0.5, u) if axis == 0 else (u, plane + sign * 0.5)
        best = min([best] + [r.distance(x, z) for r in ahead])
    return best


def face_reach(walk_rects, axis, sign, plane, u0, u1, screens=()):
    """How near a walker comes to each point of a face (face_distance, sampled every 6 studs and
    read between): the size of its blocks blends from "near" to "far" along it."""
    n = max(1, int(math.ceil((u1 - u0) / 6.0)))
    marks = [u0 + (u1 - u0) * k / n for k in range(n + 1)]
    dists = [face_distance(walk_rects, axis, sign, plane, max(u0, u - 3.0), min(u1, u + 3.0), screens) for u in marks]

    def at(u):
        t = min(max((u - u0) / max(u1 - u0, 1e-9) * n, 0.0), float(n))
        k = min(int(t), n - 1)
        a, b = dists[k], dists[k + 1]
        if math.isinf(a) or math.isinf(b):
            return min(a, b)
        return lerp(a, b, t - k)

    return at


def covered_above(level: Level, s, axis, sign, plane, u0, u1, top) -> bool:
    """Does another solid sit on this face's top edge (a roof over a wall)? Then no block may
    stand over the edge."""
    for k in range(5):
        u = u0 + (u1 - u0) * (k + 0.5) / 5
        p = [0.0, top + 0.5, 0.0]
        p[axis] = plane - sign * 0.3
        p[2 if axis == 0 else 0] = u
        for o in level.solids:
            if o is not s and all(o.lo[i] - 1e-6 <= p[i] <= o.hi[i] + 1e-6 for i in range(3)):
                return True
    return False


def ridge_firs(level: Level, bake: Bake):
    """Firs along the wide tops of the walls nobody can reach (the cave ridge's roofs)."""
    for s in level.solids:
        r = s.rect
        if s.kind != "wall" or min(r.x1 - r.x0, r.z1 - r.z0) < 12.0:
            continue
        top = s.hi[1]
        step = ART["ridgeFirs"]
        z = r.z0 + 3.5
        while z < r.z1 - 3.0:
            x = r.x0 + 3.5 + hash01(z, s.hi[1]) * 4
            while x < r.x1 - 3.0:
                m = kit.build("FirMassA" if hash01(x, z) < 0.6 else "FirMassB")
                bake.extend(m.transformed(x, top + 0.8, z, hash01(x, z, 2.0) * 360, 0.8 + 0.4 * hash01(z, x)))
                x += step + 3 * hash01(x, z, 4.0)
            z += step


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
                piece = "FirHeroA" if hash01(x, z, 3.0) < 0.4 else "FirMassB"
                scale = 0.9 + 0.35 * hash01(z, x)
                # no branch over walkable ground (the gatehouse walk passes close by)
                if not any(r.contains(x, z) for r in walk_rects) and min(p[0].distance(x, z) for p in parts) > reach_of(piece) * scale + 0.4:
                    bake.extend(kit.build(piece).transformed(x, ground.at(x, z) - 0.5, z, hash01(x, z) * 360, scale))
                u += ART["crownFirs"] + 6.0 * hash01(u, plane, 2.0)


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


def face_frame(axis, sign, plane):
    """A face's frame: origin, u along it, v up it (z for a horizontal face), w out of it."""
    if axis == 0:
        return (plane, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0), (float(sign), 0.0, 0.0)
    if axis == 2:
        return (0.0, 0.0, plane), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, float(sign))
    return (0.0, plane, 0.0), (1.0, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, float(sign), 0.0)


def split_span(lo, hi, size, seed) -> list[tuple[float, float]]:
    """[lo, hi] cut into pieces of about `size` = [min, max] studs, each a different width."""
    mean = (size[0] + size[1]) / 2
    n = max(1, int(round((hi - lo) / mean)))
    weights = [size[0] + (size[1] - size[0]) * hash01(seed, k, 3.1) for k in range(n)]
    total = sum(weights)
    cuts = [lo]
    acc = 0.0
    for w in weights:
        acc += w
        cuts.append(lo + (hi - lo) * acc / total)
    cuts[-1] = hi
    return list(zip(cuts, cuts[1:]))


def joint_grid(u0, u1, v0, v1, wsize, hsize, seed, slant, tilt):
    """A flat region (a wall's top, the massif's plan) cut into columns of different widths whose
    joints lean a little (`slant`: how far a joint's foot and head may stray, studs), each column
    cut into blocks of its own heights by joints tilted up to `tilt` (rise over run). Returns
    (column, row, quad, is_top) with the quad counter-clockwise in (u, v). A cliff face is cut by
    pack_cells instead (no column runs up it)."""
    cols = split_span(u0, u1, wsize, seed)
    n = len(cols)
    joints = []
    for k in range(n + 1):
        if k in (0, n):
            u = u0 if k == 0 else u1
            joints.append((u, u))
            continue
        c = cols[k][0]
        room = min(slant, 0.28 * min(cols[k - 1][1] - cols[k - 1][0], cols[k][1] - cols[k][0]))
        joints.append((c + (hash01(seed, k, 21.0) - 0.5) * 2 * room, c + (hash01(seed, k, 22.0) - 0.5) * 2 * room))
    height = max(v1 - v0, 1e-6)

    def ju(k, v):
        ub, ut = joints[k]
        return ub + (ut - ub) * (v - v0) / height

    mid = (u0 + u1) / 2
    out = []
    for k in range(n):
        top = v1
        rows = split_span(v0, top, hsize, seed + 17.0 * k + 1.0)
        um = (cols[k][0] + cols[k][1]) / 2
        half = (cols[k][1] - cols[k][0]) / 2
        lines = [(v0, 0.0, mid)]
        for j in range(1, len(rows)):
            room = 0.3 * min(rows[j - 1][1] - rows[j - 1][0], rows[j][1] - rows[j][0])
            t = (hash01(seed, k, j, 23.0) - 0.5) * 2 * tilt
            t = max(-room / max(half, 1e-6), min(room / max(half, 1e-6), t))
            lines.append((rows[j][0], t, um))
        lines.append((top, 0.0, mid))

        def cross(kj, line):
            h, t, uref = line
            v = h
            for _ in range(4):
                v = h + t * (ju(kj, v) - uref)
            return (ju(kj, v), v)

        for j in range(len(rows)):
            quad = [cross(k, lines[j]), cross(k + 1, lines[j]), cross(k + 1, lines[j + 1]), cross(k, lines[j + 1])]
            out.append((k, j, quad, j == len(rows) - 1))
    return out


def clip_half(poly, a, b, c):
    """The part of a convex (u, v) polygon where a u + b v <= c (one Sutherland-Hodgman pass)."""
    out = []
    n = len(poly)
    for i in range(n):
        p, q = poly[i], poly[(i + 1) % n]
        dp = a * p[0] + b * p[1] - c
        dq = a * q[0] + b * q[1] - c
        if dp <= 0.0:
            out.append(p)
        if (dp < 0.0 < dq) or (dq < 0.0 < dp):
            t = dp / (dp - dq)
            out.append((p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t))
    return out


def poly_area(poly) -> float:
    n = len(poly)
    return 0.5 * sum(poly[i][0] * poly[(i + 1) % n][1] - poly[(i + 1) % n][0] * poly[i][1] for i in range(n))


def simplify_poly(poly, min_edge, keep=4):
    """A convex polygon with its short edges and near-straight corners dropped, vertex by vertex,
    each time the one whose loss cuts the least area: it stays convex and only shrinks (the crevice
    widens there), and a block costs fewer triangles."""
    pts = list(poly)
    while len(pts) > keep:
        n = len(pts)
        best = None
        for k in range(n):
            a, b, c = pts[k - 1], pts[k], pts[(k + 1) % n]
            loss = abs((b[0] - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (b[1] - a[1])) / 2
            short = min(math.hypot(b[0] - a[0], b[1] - a[1]), math.hypot(c[0] - b[0], c[1] - b[1]))
            off = 2 * loss / max(1e-9, math.hypot(c[0] - a[0], c[1] - a[1]))  # how far b stands off the chord
            if short < min_edge or off < 0.12 * min_edge:
                if best is None or loss < best[0]:
                    best = (loss, k)
        if best is None:
            break
        del pts[best[1]]
    return pts


def split_cell(poly, size, aspect, seed, out, depth=0):
    """Cut a convex cell into blocks the way the references stack them: a cell much taller than
    the block size wanted there (`size(u, v)`, a block `aspect` times as tall as wide) is cut by a
    near-level joint, a much wider one by a near-upright joint, each tilted its own way and placed
    off-centre, and each half is cut again on its own: every joint ends on another (a T), so no
    joint or course runs across the face."""
    us = [p[0] for p in poly]
    vs = [p[1] for p in poly]
    w, h = max(us) - min(us), max(vs) - min(vs)
    cu, cv = (min(us) + max(us)) / 2, (min(vs) + max(vs)) / 2
    want = size(cu, cv) * (0.7 + 0.6 * hash01(seed, 31.0))
    tw = want / aspect
    if depth > 9 or (h <= want * 1.45 and w <= tw * 1.45):
        out.append(poly)
        return
    t = 0.36 + 0.28 * hash01(seed, 32.0)
    lean = (hash01(seed, 33.0) - 0.5) * 2
    if h / want >= w / tw:
        # a near-level joint: v - tilt (u - cu) = cut
        tilt = 0.32 * lean
        cut = min(vs) + h * t
        a, b, c = -tilt, 1.0, cut - tilt * cu
    else:
        # a near-upright joint: u - lean (v - cv) = cut
        tilt = 0.22 * lean
        cut = min(us) + w * t
        a, b, c = 1.0, -tilt, cut - tilt * cv
    lo = clip_half(poly, a, b, c)
    hi = clip_half(poly, -a, -b, -c)
    for k, part in enumerate((lo, hi)):
        if len(part) >= 3 and poly_area(part) > 0.25:
            split_cell(part, size, aspect, hash01(seed, 34.0 + k) * 1000.0, out, depth + 1)


def pack_cells(u0, u1, v0, v1, size, seed, aspect, spread, crown=None, min_edge=1.0, mass=2.4):
    """A face region cut into blocks the way Ben's references cluster them (2026-10-21, his second
    look: "less regular walls": bigger uneven blocks, broken layers, fewer straight joints). First
    masses: seeds thrown like a Poisson disc whose radius follows `mass` times `size(u, v)` (the
    mean block height there) times a spread per seed (`spread` = [least, most]: big masses beside
    small ones), stretched `aspect` times taller than wide, and the masses are the seeds' power
    diagram (each seed weighted by its radius), so their outlines run every way. Then each mass is
    stacked into blocks by split_cell. `crown(u)` gives a free top edge its skyline: (height, tilt)
    of the mass whose centre stands at u; without it every block stops at v1. Returns [(outline
    ccw in (u, v), the mass's spread share 0..1, the mass's index, touches_top)]."""
    asp = max(0.2, aspect)
    lo_s, hi_s = spread

    def msize(u, v):
        return mass * size(u, v)

    probes = [msize(u0 + (u1 - u0) * i / 6, v0 + (v1 - v0) * j / 6) for i in range(7) for j in range(7)]
    smin, smax = min(probes), max(probes)
    rmax = 0.5 * smax * hi_s
    step = max(0.75, 0.3 * smin * lo_s)
    poke = 0.0
    if crown is not None:
        poke = max(0.0, max(crown(u0 + (u1 - u0) * i / 12)[0] for i in range(13)) - v1) + 0.5
    # candidates: a jittered lattice in the stretched frame (x = u * asp, y = v)
    cands = []
    ny = max(1, int(math.ceil((v1 - v0) / step)))
    nx = max(1, int(math.ceil((u1 - u0) * asp / step)))
    for j in range(ny):
        for i in range(nx):
            x = u0 * asp + (i + 0.15 + 0.7 * hash01(seed, i, j, 1.0)) * step
            y = v0 + (j + 0.15 + 0.7 * hash01(seed, i, j, 2.0)) * step
            if x > u1 * asp or y > v1:
                continue
            share = hash01(seed, i, j, 3.0)
            r = 0.5 * msize(x / asp, y) * (lo_s + (hi_s - lo_s) * share)
            # big seeds tend to go first, so small ones fill between them
            cands.append((0.55 * hash01(seed, i, j, 4.0) + 0.45 * (1.0 - share), x, y, r, share))
    cands.sort()
    g = 2.0 * rmax
    grid: dict[tuple[int, int], list[int]] = {}
    seeds: list[tuple[float, float, float, float]] = []
    for _key, x, y, r, share in cands:
        gi, gj = int(math.floor(x / g)), int(math.floor(y / g))
        ok = True
        for di in (-1, 0, 1):
            for dj in (-1, 0, 1):
                for k in grid.get((gi + di, gj + dj), ()):
                    sx, sy, sr, _ = seeds[k]
                    if (sx - x) ** 2 + (sy - y) ** 2 < (0.9 * (sr + r)) ** 2:
                        ok = False
                        break
                if not ok:
                    break
            if not ok:
                break
        if ok:
            grid.setdefault((gi, gj), []).append(len(seeds))
            seeds.append((x, y, r, share))
    top = v1 + poke
    frame = [(u0 * asp, v0), (u1 * asp, v0), (u1 * asp, top), (u0 * asp, top)]
    reach = int(math.ceil(2.6 * (2 * rmax) / g)) + 1
    out = []
    for idx, (x, y, r, share) in enumerate(seeds):
        poly = frame
        gi, gj = int(math.floor(x / g)), int(math.floor(y / g))
        for di in range(-reach, reach + 1):
            for dj in range(-reach, reach + 1):
                for k in grid.get((gi + di, gj + dj), ()):
                    if k == idx:
                        continue
                    sx, sy, sr, _ = seeds[k]
                    if (sx - x) ** 2 + (sy - y) ** 2 > (2.6 * (sr + r)) ** 2:
                        continue
                    poly = clip_half(poly, 2 * (sx - x), 2 * (sy - y), sx * sx + sy * sy - x * x - y * y - sr * sr + r * r)
                    if len(poly) < 3:
                        break
                if len(poly) < 3:
                    break
            if len(poly) < 3:
                break
        if len(poly) < 3:
            continue
        cell = [(p[0] / asp, p[1]) for p in poly]
        if crown is not None and max(p[1] for p in cell) > v1 + 1e-6:
            uc = sum(p[0] for p in cell) / len(cell)
            h, tilt = crown(uc)
            cell = clip_half(cell, -tilt, 1.0, h - tilt * uc)
        elif crown is None:
            cell = clip_half(cell, 0.0, 1.0, v1)
        if len(cell) < 3 or poly_area(cell) < 0.5:
            continue
        blocks: list = []
        split_cell(kit.poly_ccw(cell), size, aspect, hash01(seed, idx, 30.0) * 1000.0, blocks)
        for b in blocks:
            b = simplify_poly(kit.poly_ccw(b), min_edge)
            if len(b) < 3 or poly_area(b) < 0.4:
                continue
            out.append((b, share, idx, max(p[1] for p in b) > v1 - 0.5))
    return out


def thin_front(st, fmin, prom, lean) -> tuple[float, float]:
    """A thin face's block: its highest corner from `fmin` (deep) up to the style's front (the big,
    prominent ones), never over THIN_OUT, and its front leaning back from that corner by up to the
    style's lift (`lean` 0..1 of it), each corner its own share: a faceted front, never a flat
    tile. Returns (front, lift_max) for block_poly."""
    peak = min(THIN_OUT, fmin + (st["front"][1] - fmin) * prom ** 0.6)
    tilt = min(st["lift"], peak - fmin) * lean
    return peak - tilt, tilt


def style_size(st) -> tuple[float, float]:
    """A style's mean block height and its blocks' aspect (height over width)."""
    h = (st["height"][0] + st["height"][1]) / 2
    w = (st["width"][0] + st["width"][1]) / 2
    return h, h / w


def block_face(bake: Bake, axis, sign, plane, region, style, seed, reach=None, free_top=False, pillar=False, back=None,
               backing=True, backing_region=None, open_rects=None, near_at=None):
    """One face region as a cliff of clustered chamfered blocks (see rock_faces): `pack_cells` cuts
    it (no tier, course or column running across it), and each block is a chamfered prism standing
    out of the dark backing. `style` names the block sizes and reliefs in ART.cliff: "thin" (a face
    over walking ground), "tunnel" (the cave's inside), "near" and "far" (faces nobody touches, by
    how far the nearest walker is: `near_at(u)` gives that distance along the face and the sizes
    blend from near to far, so no stretch seam runs up it), "pillar" (a ledge's side), "step" (the
    face of a step between two walks), "gully". `back`: how deep the backing lies behind the face
    (a thin face's blocks may sit back as far as the wall's thickness allows). `reach`: a thin face
    bulges, and carries the bigger blocks, only above it. `free_top`: the face's top edge is open
    sky, so its blocks stand over it, each to its own height, their tops tilted. `open_rects`: the
    ground walkers may stand on or fall into; a block of a face nobody stands at still stops
    ART.cliff.clear short of it. (The mountain's faces have their own maker, mountain_faces.)"""
    u0, u1, v0, v1 = region
    if u1 - u0 < 0.3 or v1 - v0 < 0.3:
        return
    cf = ART["cliff"]
    st = cf[style]
    o, eu, ev, ew = face_frame(axis, sign, plane)
    depth = st["back"] if back is None else back
    gap = cf["gap"]

    def fp(u, v, w):
        return (o[0] + eu[0] * u + ev[0] * v + ew[0] * w, o[1] + eu[1] * u + ev[1] * v + ew[1] * w, o[2] + eu[2] * u + ev[2] * v + ew[2] * w)

    if backing:
        # The dark backing: one quad for the whole face, the crevice behind every block.
        bu0, bu1, bv0, bv1 = backing_region or region
        a, b, c, d = fp(bu0, bv0, -depth), fp(bu1, bv0, -depth), fp(bu1, bv1, -depth), fp(bu0, bv1, -depth)
        bake.toward(a, b, c, ROCK.ROCK_SHADE, ew)
        bake.toward(a, c, d, ROCK.ROCK_SHADE, ew)
    thin = style in ("thin", "tunnel", "step", "mount")
    near = cf["near"]
    far = cf["far"]
    above = cf[st.get("above", "near")]  # a thin face's blocks over every walker's reach
    base_h, aspect = style_size(st)
    near_h, _ = style_size(near)
    far_h, _ = style_size(far)
    above_h, _ = style_size(above)

    def blend(u):
        """0 by a near walker, 1 where only far ones see the face."""
        return smoothstep(cf["nearReach"], cf["nearReach"] + cf["blend"], near_at(u))

    def size(u, v):
        h = lerp(near_h, far_h, blend(u)) if near_at is not None else base_h
        if thin and reach is not None:
            h = lerp(h, above_h, smoothstep(reach, reach + 10.0, v))
            # at the foot, beside the walker, the blocks are broken smaller (the references' cliffs
            # stand on their rubble), the big slabs above
            base, rise = cf["foot"]
            floor = reach - REACH_ABOVE
            h *= lerp(base, 1.0, smoothstep(floor + 2.0, floor + rise, v))
        return h

    crown = None
    if free_top:
        poke = st.get("poke", cf["poke"])

        def crown(u):
            # The skyline rises and falls in groups of blocks (smooth along the face, a little
            # jitter each), never an even row of merlons.
            swell = 0.5 + 0.5 * NOISE.n2(u / cf["skyline"], plane * 0.013 + axis, 17.0)
            jit = hash01(seed, round(u, 1), 2.0)
            return v1 + poke[0] + (poke[1] - poke[0]) * (0.75 * swell + 0.25 * jit), (hash01(seed, round(u, 1), 3.0) - 0.5) * 2 * cf["crown"]

    cells = pack_cells(u0, u1, v0, v1, size, seed, aspect, st["spread"], crown=crown, min_edge=st.get("minEdge", 1.0), mass=st.get("mass", 2.4))
    m = kit.Mesh("cliff")
    fmin = max(st["front"][0], -depth + 0.3) if thin else st["front"][0]
    for n, (quad, share, mass, is_top) in enumerate(cells):
        # The blocks of one mass share its relief and tone, give or take: a mass reads as one rock
        # split by cracks, the step between two masses as the joint between two rocks.
        hh = 0.7 * hash01(seed, mass, 6.0) + 0.3 * hash01(seed, n, 6.0)
        va = min(q[1] for q in quad)
        vb = max(q[1] for q in quad)
        uc = sum(q[0] for q in quad) / len(quad)
        cst = st
        if near_at is not None:
            cst = far if blend(uc) > 0.5 else near
        if thin:
            # In front of walkers no block stands more than THIN_OUT out of the collision face; the
            # relief is in how far each block sits back (the big ones near the front, the small
            # ones deep), and in its front's facets (each corner lifted on its own).
            front, lift_max = thin_front(st, fmin, 0.55 * hh + 0.45 * share, hash01(seed, n, 15.0))
            if reach is not None and axis != 1 and va > reach:
                ramp = min(1.0, (va - reach) / 10.0)
                bulge = above["front"][0] + (above["front"][1] - above["front"][0]) * hh
                front = max(front, ramp * bulge)
                lift_max = lift_max + ramp * (above["lift"] - lift_max)
                cst = above if ramp > 0.5 else st
        else:
            cluster = 0.5 + 0.5 * NOISE.n2(uc / 13.0, (va + vb) / 2 / 17.0, seed * 0.01)
            front = cst["front"][0] + (cst["front"][1] - cst["front"][0]) * (0.45 * hh + 0.3 * cluster + 0.25 * share)
            if style in ("near", "far", "pillar"):
                foot = max(0.0, 1.0 - (va - v0) / max(1.0, cf["talus"][1]))
                front += cf["talus"][0] * foot * foot
            lift_max = cst["lift"]
        if open_rects and axis != 1:
            # a block's front slides and leans: ground just past either end of it counts too
            room = room_ahead(open_rects, axis, sign, plane, min(q[0] for q in quad) - cf["clear"], max(q[0] for q in quad) + cf["clear"])
            front = max(0.0, min(front, room - cf["clear"]))
        if pillar and vb > v1 - 4.0:
            # a ledge's top edge stays honest for the double jump onto it
            front = min(front, 0.25)
            lift_max = min(lift_max, 0.05)
        bevel = cst["bevel"][0] + (cst["bevel"][1] - cst["bevel"][0]) * hash01(seed, n, 7.0)
        if is_top and free_top:
            bevel *= cf["crownBevel"]
        lifts = [lift_max * hash01(seed, n, 8.0 + q) for q in range(len(quad))]
        sh = cst["shear"]
        shear = ((hash01(seed, n, 12.0) - 0.5) * 2 * sh, (hash01(seed, n, 13.0) - 0.5) * 2 * sh)
        if is_top and not free_top:
            shear = (shear[0], min(shear[1], 0.0))  # a capped top edge: no front slides over it
        tone = 0.65 * hash01(seed, mass, 5.0) + 0.35 * hash01(seed, n, 5.0)
        crevice = gap * (1.0 + cf["crevice"] * hash01(seed, n, 17.0))
        kit.block_poly(m, o, eu, ev, ew, quad, -depth, front, bevel, shear=shear, lift=lifts, tone=tone,
                       sides=front - bevel > -depth + 0.3, gap=crevice, inset=bevel * cst["round"])
    bake.extend(m.tris)


def block_caps(bake: Bake, plane, region, s, walled, seed):
    """The top of a tall solid as bigger caps (the reference's crowns): irregular chamfered slabs
    standing up to ART.cliff.cap.front over it, sunk into it, overhanging its sides a little except
    over a walled camp's floor; some carry moss."""
    cf = ART["cliff"]
    st = cf["cap"]
    x0, x1, z0, z1 = region
    ov = st["overhang"]
    r = Rect(x0 - ov, x1 + ov, z0 - ov, z1 + ov)
    for f in walled:
        if not r.overlaps(f):
            continue
        # keep off the floor, by more than a cap's slide: cut the side that faces it
        keep = st["shear"] + 0.05
        if f.x0 >= x1 - 1e-6:
            r.x1 = min(r.x1, f.x0 - keep)
        if f.x1 <= x0 + 1e-6:
            r.x0 = max(r.x0, f.x1 + keep)
        if f.z0 >= z1 - 1e-6:
            r.z1 = min(r.z1, f.z0 - keep)
        if f.z1 <= z0 + 1e-6:
            r.z0 = max(r.z0, f.z1 + keep)
    o, eu, ev, ew = face_frame(1, 1, plane)
    m = kit.Mesh("caps")
    long_x = (r.x1 - r.x0) >= (r.z1 - r.z0)
    short = min(r.x1 - r.x0, r.z1 - r.z0)
    # A narrow top (a 2-stud wall) gets one row of long caps across it; a wide top a grid.
    wsize = st["width"] if short > st["width"][0] else st["narrow"]
    for k, j, quad, _top in joint_grid(r.x0, r.x1, r.z0, r.z1, wsize if long_x else st["width"], st["width"] if long_x else wsize,
                                       seed, st["slant"], st["tilt"]):
        cx, cz = sum(q[0] for q in quad) / 4, sum(q[1] for q in quad) / 4
        if min(cx - x0, x1 - cx, cz - z0, z1 - cz) > st["rim"]:
            continue  # nobody sees a wide top's middle: its caps ring its edges, the skyline
        hh = hash01(seed, k, j, 1.0)
        front = st["front"][0] + (st["front"][1] - st["front"][0]) * hh
        bevel = st["bevel"][0] + (st["bevel"][1] - st["bevel"][0]) * hash01(seed, k, j, 2.0)
        lifts = [(hash01(seed, k, j, 3.0 + q) - 0.5) * 2 * st["lift"] for q in range(4)]
        sh = st["shear"]
        shear = ((hash01(seed, k, j, 8.0) - 0.5) * 2 * sh, (hash01(seed, k, j, 9.0) - 0.5) * 2 * sh)
        mossy = hash01(seed, k, j, 10.0) < st["moss"]
        kit.block_poly(m, o, eu, ev, ew, quad, -st["back"], front, bevel, shear=shear, lift=lifts, tone=hash01(seed, k, j, 11.0),
                       paint=moss_paint if mossy else kit.rock_paint, gap=cf["gap"], inset=bevel * st["round"])
    bake.extend(m.tris)
    # The middle the ring leaves (a wide roof's): one flat mossy floor between the caps' feet, so
    # nothing of the hollow inside shows from above.
    inner = Rect(x0 + st["rim"] - 1.0, x1 - st["rim"] + 1.0, z0 + st["rim"] - 1.0, z1 - st["rim"] + 1.0)
    if inner.x1 - inner.x0 > 1.0 and inner.z1 - inner.z0 > 1.0:
        y = plane + st["floor"]
        bake.up((inner.x0, y, inner.z0), (inner.x1, y, inner.z0), (inner.x1, y, inner.z1), FOLIAGE.MOSS)
        bake.up((inner.x0, y, inner.z0), (inner.x1, y, inner.z1), (inner.x0, y, inner.z1), FOLIAGE.MOSS)


def moss_paint(role, n, tone):
    """A cap with moss on its top (a few of the ridge's caps), rock everywhere else."""
    if role == "cap" and n[1] > kit.ROCK_TOP:
        return FOLIAGE.MOSS if tone < 0.5 else ROCK.LICHEN
    return kit.rock_paint(role, n, tone)


def step_faces(level: Level, bake: Bake):
    """Stacked blocks on the face of every step between two walkable blocks (the climb onto the
    plateau, the climb to the gatehouse, the cave's climb), thin: it faces the lower block's
    walkers."""
    for lo in level.walks:
        for hi in level.walks:
            if hi.top - lo.top < 0.5 or lo is hi or (lo.name in level.climb_pieces and hi.name in level.climb_pieces):
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
                seed = hash01(plane, span[0], lo.top, 4.0) * 1000.0
                block_face(bake, axis, sign, plane, (span[0], span[1], lo.top - 0.6, hi.top + 0.05), "step", seed)


# ---------------------------------------------------------------- the mountain (the climb)


def climb_boxes(level: Level) -> list[tuple[str, Rect, float]]:
    """The climb's ledges and its summit (check_parkour CLIMBS) as (name, plan rect, top)."""
    if not level.climb:
        return []
    out = []
    for name in list(level.climb["ledges"]) + [level.climb["summit"]]:
        b = level.blocks.get(name)
        if b:
            out.append((name, Rect.of(b), b["y"] + b["sy"] / 2))
    return out


def mountain_faces(level: Level, bake: Bake) -> None:
    """The mountain (MISSIONS_DESIGN 28), the forest's landmark, in Ben's clustered-block style (his
    second reference is a rock tower): every side of its ledges and its core as cliffs of
    pack_cells blocks, the sides of different pillars that share a plane packed as one face (no
    seam where one pillar's side runs on into the next; a block crossing a step in the skyline is
    cut there, at the real corner). Where a body stands beside a face (the yard, or the ledge in
    front of it) the face is thin (THIN_OUT) up to REACH_ABOVE over that floor, and the big
    "mountUp" blocks bulge only above it, the ones at the tower's outer corners wrapping round them
    (no notch at a corner, a broken silhouette); in ART.cliff.mount.fine under a ledge's top, and
    over a ledge in front, the blocks are finer (where the player stands and looks at them); a
    ledge's top edge stays honest: flush in its last four studs, the bulge fading in below."""
    boxes = climb_boxes(level)
    if not boxes:
        return
    cf = ART["cliff"]
    st = cf["mount"]
    above = cf[st["above"]]
    gap = cf["gap"]
    ext = st["wrap"]
    groups: dict[tuple, list] = {}
    for name, r, top in boxes:
        for axis, sign, plane, lo, hi in ((0, -1, r.x0, r.z0, r.z1), (0, 1, r.x1, r.z0, r.z1), (2, -1, r.z0, r.x0, r.x1), (2, 1, r.z1, r.x0, r.x1)):
            groups.setdefault((axis, sign, round(plane, 4)), []).append((lo, hi, top, name))
    base_h, aspect = style_size(st)
    above_h, _ = style_size(above)
    band, share = st["fine"]
    m = kit.Mesh("mountain")
    for (axis, sign, plane), segs in sorted(groups.items()):
        segs.sort()

        def cover(u, axis=axis, sign=sign, plane=plane):
            """The top of the pillar standing in front of the face at u (the floor a body stands on
            there), or the yard's 0."""
            best = 0.0
            x, z = (plane + sign * 0.01, u) if axis == 0 else (u, plane + sign * 0.01)
            for _n, r, top in boxes:
                if r.x0 < x < r.x1 and r.z0 < z < r.z1:
                    best = max(best, top)
            return best

        def top_at(u, segs=segs):
            for lo, hi, top, _n in segs:
                if lo - 1e-6 <= u <= hi + 1e-6:
                    return top
            return None

        def floor_over(a, b, cover=cover):
            """The highest floor in front over [a, b] and a body's width either side."""
            return max(cover(a - 1.5 + (b - a + 3.0) * k / 8) for k in range(9))

        def open_end(u, step, name, axis=axis, sign=sign, plane=plane):
            """Is the mountain's outside past this end of a pillar's side (an outer corner)?"""
            ua, ub = (u - ext, u) if step < 0 else (u, u + ext)
            wa, wb = plane - sign * (st["back"] + 0.5), plane + sign * (ext + 1.0)
            wa, wb = min(wa, wb), max(wa, wb)
            box = Rect(wa, wb, ua, ub) if axis == 0 else Rect(ua, ub, wa, wb)
            return not any(r.overlaps(box) for n, r, _t in boxes if n != name)

        exposed = [(lo, hi, top, open_end(lo, -1, name), open_end(hi, 1, name)) for lo, hi, top, name in segs
                   if any(cover(lo + (hi - lo) * (k + 0.5) / 12) < top - 0.5 for k in range(12))]
        if not exposed:
            continue
        u0, u1 = min(e[0] for e in exposed), max(e[1] for e in exposed)
        vtop = max(e[2] for e in exposed)

        def size(u, v, cover=cover, top_at=top_at, vtop=vtop):
            floor = cover(u)
            top = top_at(u)
            h = lerp(base_h, above_h, smoothstep(floor + REACH_ABOVE, floor + REACH_ABOVE + 20.0, v))
            fine = lerp(share, 1.0, smoothstep(0.0, band, (top if top is not None else vtop) - v))
            if floor > 0.5:  # over a ledge in front: the rock beside the player
                fine = min(fine, lerp(share, 1.0, smoothstep(floor + 18.0, floor + 40.0, v)))
            return h * fine

        seed = 9000.0 + hash01(axis, sign, plane) * 1000.0
        o, eu, ev, ew = face_frame(axis, sign, plane)
        depth = st["back"]
        # the dark backing, per exposed pillar side, from the floor in front to its top
        for lo, hi, top, _ol, _oh in exposed:
            fl = min(cover(lo + (hi - lo) * (k + 0.5) / 12) for k in range(12))
            for a, b, c in (((lo, fl - 1.0), (hi, fl - 1.0), (hi, top - 0.05)), ((lo, fl - 1.0), (hi, top - 0.05), (lo, top - 0.05))):
                pts = [tuple(o[i] + eu[i] * p[0] + ev[i] * p[1] - ew[i] * depth for i in range(3)) for p in (a, b, c)]
                bake.toward(*pts, ROCK.ROCK_SHADE, ew)
        cells = pack_cells(u0 - ext, u1 + ext, -1.0, vtop, size, seed, aspect, st["spread"], min_edge=st["minEdge"])
        yard_reach = REACH_ABOVE + 2.0
        for n, (quad, sh_share, mass, _top) in enumerate(cells):
            qa, qb = min(p[1] for p in quad), max(p[1] for p in quad)
            for lo, hi, top, open_lo, open_hi in exposed:
                # a block high on the tower's outer corner wraps round it
                wrap = qa > yard_reach and qb < top - 10.0
                elo = lo - ext if (wrap and open_lo) else lo
                ehi = hi + ext if (wrap and open_hi) else hi
                piece = clip_half(quad, 1.0, 0.0, ehi)
                piece = clip_half(piece, -1.0, 0.0, -elo) if len(piece) >= 3 else piece
                piece = clip_half(piece, 0.0, 1.0, top - 0.05 + gap / 2) if len(piece) >= 3 else piece
                if len(piece) < 3 or poly_area(piece) < 0.4:
                    continue
                piece = simplify_poly(kit.poly_ccw(piece), st["minEdge"] * 0.6)
                if len(piece) < 3:
                    continue
                ua, ub = min(p[0] for p in piece), max(p[0] for p in piece)
                va, vb = min(p[1] for p in piece), max(p[1] for p in piece)
                if ub <= lo + 0.3 or ua >= hi - 0.3:
                    continue  # all of it past the corner: the next face carries that corner
                ia, ib = max(lo, ua), min(hi, ub)
                if vb < min(cover(ia + (ib - ia) * (k + 0.5) / 5) for k in range(5)) - 0.5:
                    continue  # wholly behind the pillar in front
                hh = 0.7 * hash01(seed, mass, 6.0) + 0.3 * hash01(seed, n, 6.0)
                reach = floor_over(max(lo, ua), min(hi, ub)) + REACH_ABOVE
                fmin = max(st["front"][0], -depth + 0.3)
                front, lift_max = thin_front(st, fmin, 0.55 * hh + 0.45 * sh_share, hash01(seed, n, 15.0))
                cst = st
                if va > reach:
                    ramp = min(1.0, (va - reach) / 10.0)
                    bulge = above["front"][0] + (above["front"][1] - above["front"][0]) * (0.6 * hh + 0.4 * hash01(seed, n, 14.0))
                    front = max(front, ramp * bulge)
                    lift_max = lift_max + ramp * (above["lift"] - lift_max)
                    cst = above if ramp > 0.5 else st
                    # past a corner the block stands out at least as far as it wraps
                    front = max(front, max(lo - ua, ub - hi, 0.0) + 0.6)
                # the ledge's top edge: flush in its last four studs, the bulge fading in below
                edge = 0.25 + 0.3 * max(0.0, (top - 4.0) - vb)
                if front > edge:
                    front = edge
                    if vb > top - 4.0:
                        lift_max = min(lift_max, 0.05)
                bevel = cst["bevel"][0] + (cst["bevel"][1] - cst["bevel"][0]) * hash01(seed, n, 7.0)
                lifts = [lift_max * hash01(seed, n, 8.0 + q) for q in range(len(piece))]
                sh = cst["shear"] if va > reach + 10.0 else min(cst["shear"], 0.2)
                shear = ((hash01(seed, n, 12.0) - 0.5) * 2 * sh, (hash01(seed, n, 13.0) - 0.5) * 2 * sh)
                if vb > top - 4.0:
                    shear = (shear[0], min(shear[1], 0.0))  # no front slides over the ledge's edge
                # nor past a side's end where the next pillar stands (its top is walking space)
                su = shear[0] if open_hi else min(shear[0], max(0.0, hi - ub))
                su = su if open_lo else max(su, -max(0.0, ua - lo))
                shear = (su, shear[1])
                tone = 0.65 * hash01(seed, mass, 5.0) + 0.35 * hash01(seed, n, 5.0)
                crevice = gap * (1.0 + cf["crevice"] * hash01(seed, n, 17.0))
                kit.block_poly(m, o, eu, ev, ew, piece, -depth, front, bevel, shear=shear, lift=lifts, tone=tone,
                               sides=front - bevel > -depth + 0.3, gap=crevice, inset=bevel * cst["round"])
    bake.extend(m.tris)


def cap_paint(role, n, tone):
    """A ledge's cap stone: its top light (the lit tops of the references, and "stand here"), a few
    with lichen, its edge rock."""
    if role == "cap" and n[1] > kit.ROCK_TOP:
        return ROCK.LICHEN if tone < 0.1 else ROCK.ROCK_LIGHT
    return ROCK.ROCK if n[1] > 0.3 else ROCK.ROCK_DARK


def mountain_caps(level: Level, bake: Bake) -> None:
    """Every ledge's top and the summit paved with flat cap stones (ART.mountain.cap), flush with
    the top (the pillar top's lift), lighter than the faces, over a dark grout at the rim's lift:
    what reads as "stand here" from below and from the ledge before. A cap overhangs a side that
    drops by a little (it hides the face blocks' upper ends), never a side against a taller pillar."""
    mc = ART["mountain"]["cap"]
    boxes = climb_boxes(level)
    lifts = ART["lifts"]
    for k, (name, r, top) in enumerate(boxes):
        grow = {}
        for side, (nx, nz) in SIDES.items():
            x = (r.x1 + 0.5 if nx > 0 else r.x0 - 0.5) if nx else (r.x0 + r.x1) / 2
            z = (r.z1 + 0.5 if nz > 0 else r.z0 - 0.5) if nz else (r.z0 + r.z1) / 2
            taller = any(o.contains(x, z) and otop > top for _n, o, otop in boxes)
            grow[side] = 0.0 if taller else mc["overhang"]
        rr = Rect(r.x0 - grow["west"], r.x1 + grow["east"], r.z0 - grow["north"], r.z1 + grow["south"])
        y = top + lifts["rim"]
        bake.up((r.x0, y, r.z0), (r.x1, y, r.z0), (r.x1, y, r.z1), ROCK.ROCK_SHADE)
        bake.up((r.x0, y, r.z0), (r.x1, y, r.z1), (r.x0, y, r.z1), ROCK.ROCK_SHADE)
        o, eu, ev, ew = face_frame(1, 1, top)
        m = kit.Mesh("caps")
        seed = 9500.0 + k
        for n, (quad, sh, _mass, _t) in enumerate(pack_cells(rr.x0, rr.x1, rr.z0, rr.z1, lambda u, v: mc["size"], seed, 1.0, mc["spread"],
                                                            min_edge=mc["minEdge"], mass=mc["mass"])):
            front = lifts["top"] + mc["rise"] * hash01(seed, n, 1.0)
            tilt = [mc["tilt"] * hash01(seed, n, 3.0 + q) for q in range(len(quad))]  # a stone's own lie
            kit.block_poly(m, o, eu, ev, ew, quad, lifts["rim"], front, 0.05, lift=tilt, tone=hash01(seed, n, 2.0), paint=cap_paint,
                           sides=False, gap=mc["gap"], inset=mc["inset"])
        bake.extend(m.tris)


def mountain_scree(level: Level, ground: Ground, bake: Bake) -> None:
    """Scree at the mountain's foot: flat stones laid on the yard's floor (never over REACH's 0.2,
    so nothing stands up in the walking space), thickest against the faces and thinning out."""
    boxes = climb_boxes(level)
    if not boxes:
        return
    ms = ART["mountain"]["scree"]
    foot = Rect(min(b[1].x0 for b in boxes), max(b[1].x1 for b in boxes), min(b[1].z0 for b in boxes), max(b[1].z1 for b in boxes))
    yard = [Rect.of(level.blocks[n]) for n in level.climb["yard"] if n in level.blocks]
    m = kit.Mesh("scree")
    rnd = random.Random(2810)
    area = foot.grown(ms["band"])
    placed = 0
    tries = 0
    stones: list[tuple[float, float, float]] = []
    while placed < ms["count"] and tries < ms["count"] * 30:
        tries += 1
        x = rnd.uniform(area.x0, area.x1)
        z = rnd.uniform(area.z0, area.z1)
        d = foot.distance(x, z)
        if d <= 0.3 or d > ms["band"] or rnd.random() > (1.0 - d / ms["band"]) ** 1.5:
            continue
        rad = ms["size"][0] + (ms["size"][1] - ms["size"][0]) * rnd.random() ** 1.6
        if not any(yr.contains(x, z, -rad) for yr in yard) or any(math.hypot(x - sx, z - sz) < rad + sr + 0.2 for sx, sz, sr in stones):
            continue
        sides = 5 + int(rnd.random() * 2)
        rot = rnd.uniform(0, math.tau)
        outline = [(x + math.cos(rot + i * math.tau / sides + rnd.uniform(-0.25, 0.25)) * rad * rnd.uniform(0.8, 1.1),
                    z + math.sin(rot + i * math.tau / sides + rnd.uniform(-0.25, 0.25)) * rad * rnd.uniform(0.8, 1.1)) for i in range(sides)]
        o, eu, ev, ew = face_frame(1, 1, ground.at(x, z))
        kit.block_poly(m, o, eu, ev, ew, outline, 0.02, ms["rise"][0] + (ms["rise"][1] - ms["rise"][0]) * rnd.random(), 0.05,
                       tone=rnd.random(), sides=False, inset=rad * 0.45)
        stones.append((x, z, rad))
        placed += 1
    bake.extend(m.tris)


SUMMIT_RING = ("StandingStone", "StoneTall", "StoneSlim", "StoneLean", "StoneBroad")


def dress_mountain(level: Level, ground: Ground, P: Placements) -> None:
    """The summit's ring of standing stones round the chest (each under REGION_PIECE_MAX, outside the
    chest's trigger and off the last hop's landing, open toward it), and a few firs in the yard's
    far corners, off every hop line and the trail's mouth."""
    boxes = climb_boxes(level)
    if not boxes:
        return
    mc = ART["mountain"]
    summit = level.blocks[level.climb["summit"]]
    chest = next((s for s in level.layout.get("secrets") or [] if s.get("id") == level.climb["secret"]), None)
    top = summit["y"] + summit["sy"] / 2
    cx, cz = (chest["x"], chest["z"]) if chest else (summit["x"], summit["z"])
    # the last hop lands over the summit's side that faces the last ledge
    last = level.blocks[level.climb["ledges"][-1]]
    lx, lz = last["x"] - cx, last["z"] - cz
    land = math.atan2(lz, lx)
    ring = mc["ring"]
    for k, piece in enumerate(SUMMIT_RING):
        t = (k + 0.5) / len(SUMMIT_RING)
        a = land + math.radians(ring["open"]) / 2 + t * (math.tau - math.radians(ring["open"]))
        x, z = cx + ring["radius"] * math.cos(a), cz + ring["radius"] * math.sin(a)
        h = kit.build(piece).bounds()[1][1]
        scale = min(ring["height"][0] + (ring["height"][1] - ring["height"][0]) * hash01(x, z, 1.0), REGION_PIECE_MAX - 0.2) / h
        P.add(piece, x, top, z, -math.degrees(a) + 180.0, scale, summit=level.climb["summit"])
    yard = Rect.of(level.blocks[level.climb["yard"][0]])
    foot = Rect(min(b[1].x0 for b in boxes), max(b[1].x1 for b in boxes), min(b[1].z0 for b in boxes), max(b[1].z1 for b in boxes))
    for k, (fx, fz) in enumerate(mc["yardFirs"]):
        x = yard.x0 + fx * (yard.x1 - yard.x0)
        z = yard.z0 + fz * (yard.z1 - yard.z0)
        if foot.distance(x, z) < 6.0:
            continue
        P.add("FirHeroA" if k % 2 == 0 else "FirHeroB", x, ground.at(x, z) - 0.1, z, hash01(x, z) * 360.0, 0.9 + 0.2 * hash01(z, x), band="yard")


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
        if w.name in level.climb_pieces:
            continue  # the mountain: no fir on a hop's take-off or landing (dress_mountain)
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


ISLAND_RING = ("StoneTall", "StandingStone", "StoneSlim", "StoneLean", "StoneBroad")


def dress_islands(level: Level, ground: Ground, P: Placements):
    """A ring of standing stones on the rim of every island (the shrine's): one of each of the
    family's standing stones (reference 1), walk-through, clear of its chest, leaning outward,
    pebbles at their feet and ferns between them."""
    for name in sorted(ground.islands):
        r = level.blocks[name]
        rect = Rect.of(r)
        top = r["y"] + r["sy"] / 2
        cx, cz = (rect.x0 + rect.x1) / 2, (rect.z0 + rect.z1) / 2
        rad = min(rect.x1 - rect.x0, rect.z1 - rect.z0) / 2 - 1.6
        for k, piece in enumerate(ISLAND_RING):
            a = k * math.tau / len(ISLAND_RING) + 0.4
            x, z = cx + rad * math.cos(a), cz + rad * math.sin(a)
            # each stone's lean (+X in the kit) turned outward, away from the chest
            P.add(piece, x, top, z, -math.degrees(a), 0.8 + 0.15 * hash01(x, z), island=name)
            a2 = a + math.tau / 10
            if k % 2 == 0:
                P.add("Pebbles", cx + (rad - 0.6) * math.cos(a2), top, cz + (rad - 0.6) * math.sin(a2), hash01(x, z, 2.0) * 360, 0.8, island=name)
            else:
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
    yard = climb_yard(level)
    # the thicket band, along every walled stretch (the barriers' own edges)
    for bar in level._barriers:
        c, a, b = bar["edge"]
        nx, nz = SIDES[bar["side"]]
        camp_edge = any(abs(c - v) < 1.5 for v in camp_edge_lines(level, bar["side"]))
        if camp_edge:
            continue
        sparse = tr["yardEdge"] if yard is not None and yard_nearest(level, rects, (c + nx * 2.0) if nx else (a + b) / 2, (c + nz * 2.0) if nz else (a + b) / 2) else 1.0
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
            t += rng.uniform(5.6, 7.4) * sparse
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
                if yard is not None and d0 <= d < d1 and yard_nearest(level, rects, px, pz):
                    if band == "mid" or hash01(px, pz, 11.0) > tr["yardNear"]:
                        x += step
                        continue
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
                            under = ("Fern", "Fern", "RockA", "Stump", "Mushrooms", "StumpMossy", "RockFlat", "Bush")[int(hash01(ux, uz) * 8)]
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
                piece = ("RockA", "RockB", "RockFlat", "StoneLean", "RockSmall")[k % 5]
                P.add(piece, px, ground.at(px, pz) - 0.2, pz, hash01(px, pz) * 360, 0.8 + 0.4 * hash01(pz, px), band="rim")


def scatter_stones(level: Level, ground: Ground, P: Placements, reserved: list[Rect]):
    """The stones of reference 1 out in the forest: clusters (one big stone, a smaller one or two,
    pebbles at their feet) in the band just past the thicket where the road's walker sees them,
    boulders at the foot of the cliffs nobody stands at, and low stones on the creek and pond
    banks. Everything walk-through and off the walkable ground, the water and the gully; a cluster
    is placed before the trees, which keep off its stones (the returned rects: each stone's
    footprint with a margin, so a fir may stand beside a stone, never in it)."""
    sc = ART["stones"]
    parts = level.union_parts()
    rects = [p[0] for p in parts]
    tall = [s.rect.grown(1.5) for s in level.solids if s.kind in ("wall", "pillar", "fence")]
    trunks = [(i["x"], i["z"]) for i in P.items if i.get("band") in ("near", "mid")]

    def free(x, z, pad):
        if any(r.contains(x, z, pad) for r in rects) or any(r.contains(x, z) for r in tall):
            return False
        if any(r.contains(x, z, 1.0) for r in ground.ravine) or any(w.rect.distance(x, z) < 1.0 for w in level.water):
            return False
        if ground.steep(x, z, 1.0) or any(r.contains(x, z) for r in reserved):
            return False
        return all((x - tx) ** 2 + (z - tz) ** 2 > sc["trunk"] ** 2 for tx, tz in trunks)

    grounds = rects + [w.rect for w in level.water]

    def put(piece, x, z, yaw, scale, **tags):
        """Place a stone unless its footprint reaches walkable ground or water (rule 4c)."""
        item = {"piece": piece, "x": x, "y": 0.0, "z": z, "yaw": yaw % 360.0, "scale": scale}
        foot, _top = footprint(item)
        if any(foot.overlaps(r.grown(0.2)) for r in grounds):
            return False
        P.add(piece, x, ground.at(x, z) - 0.05, z, yaw, scale, **tags)
        beds.append(foot.grown(sc["bed"]))
        return True

    anchors = sc["anchors"]
    small = sc["small"]
    beds: list[Rect] = []  # each stone's footprint and a margin: the trees keep off them
    taken: list[Rect] = []  # the clusters' own spacing
    # Along every walled stretch of the road (the tree-line walls' own edges), a cluster every
    # ART.stones.step studs or so, ART.stones.band out from the edge: what the walker sees.
    for bar in level._barriers:
        c, a, b = bar["edge"]
        nx, nz = SIDES[bar["side"]]
        if any(abs(c - v) < 1.5 for v in camp_edge_lines(level, bar["side"])):
            continue
        t = a + sc["step"] * (0.25 + 0.5 * hash01(c, a, 30.0))
        while t < b - 2.0:
            d = sc["band"][0] + (sc["band"][1] - sc["band"][0]) * hash01(c, t, 31.0)
            px, pz = (c + nx * d, t) if nx else (t, c + nz * d)
            if free(px, pz, sc["band"][0] - 0.5) and not any(r.contains(px, pz) for r in taken):
                piece = anchors[int(hash01(px, pz, 33.0) * len(anchors))]
                yaw = hash01(px, pz, 34.0) * 360.0
                if not put(piece, px, pz, yaw, 0.85 + 0.3 * hash01(px, pz, 35.0), band="stones"):
                    t += sc["step"] * 0.5
                    continue
                for k in range(int(hash01(px, pz, 36.0) * 2)):
                    ang = hash01(px, pz, 37.0 + k) * math.tau
                    rr = 2.4 + 1.6 * hash01(px, pz, 39.0 + k)
                    cx, cz = px + rr * math.cos(ang), pz + rr * math.sin(ang)
                    if free(cx, cz, 1.0):
                        put(small[int(hash01(cx, cz, 41.0) * len(small))], cx, cz, hash01(cx, cz, 42.0) * 360, 0.8 + 0.4 * hash01(cx, cz, 43.0), band="stones")
                ang = hash01(px, pz, 44.0) * math.tau
                if hash01(px, pz, 46.0) < sc["pebbles"]:
                    put("Pebbles", px + 1.6 * math.cos(ang), pz + 1.6 * math.sin(ang), yaw, 1.0, band="stones")
                taken.append(Rect(px - sc["clear"], px + sc["clear"], pz - sc["clear"], pz + sc["clear"]))
            t += sc["step"] * (0.75 + 0.5 * hash01(t, c, 45.0))
    # the creek and the pond: low stones on the bank, never in the water
    for w in level.water:
        r = w.rect
        for side, (nx, nz) in SIDES.items():
            lo_u, hi_u = (r.x0, r.x1) if nz else (r.z0, r.z1)
            t = lo_u + sc["bank"] * hash01(lo_u, r.x0, 1.0)
            while t < hi_u:
                off = 2.6 + 1.6 * hash01(t, lo_u, 2.0)
                bx, bz = (t, (r.z0 - off) if nz < 0 else (r.z1 + off)) if nz else (((r.x0 - off) if nx < 0 else (r.x1 + off)), t)
                if free(bx, bz, 1.0) and not any(o.rect.contains(bx, bz, 0.8) for o in level.water):
                    put(("RockFlat", "RockSmall", "RockA", "Pebbles")[int(hash01(bx, bz, 3.0) * 4)], bx, bz, hash01(bx, bz, 4.0) * 360, 0.8 + 0.3 * hash01(bz, bx), band="bank")
                t += sc["bank"] * (0.7 + 0.6 * hash01(t, 5.0))
    return beds


def foot_boulders(level: Level, ground: Ground, P: Placements, reserved: list[Rect]):
    """Boulders at the foot of the cliffs nobody stands at (the ridge's south face over camp A,
    the cave mouth's outer walls): the cliff's blocks fall away into the forest floor."""
    sc = ART["stones"]
    parts = level.union_parts()
    rects = [p[0] for p in parts]
    tall = [s.rect.grown(0.5) for s in level.solids if s.kind in ("wall", "pillar", "fence")]
    trunks = [(i["x"], i["z"]) for i in P.items if i.get("band") in ("near", "mid")]
    out = ART["cliff"]["talus"][0] + 0.5 + ART["cliff"]["near"]["front"][1]
    for axis, sign, plane, (u0, u1, v0, v1), s in exposed_faces(level):
        if axis == 1 or s.kind not in ("wall", "pillar"):
            continue
        if faces_walkable(level, parts, axis, sign, plane, (u0 + u1) / 2, (v0 + v1) / 2):
            continue
        u = u0 + sc["foot"] * hash01(plane, u0, 1.0)
        while u < u1 - 1.0:
            d = out + 2.0 * hash01(u, plane, 2.0)
            x, z = (plane + sign * d, u) if axis == 0 else (u, plane + sign * d)
            ok = not any(r.contains(x, z, 2.5) for r in rects) and not any(r.contains(x, z) for r in tall)
            ok = ok and not any(r.contains(x, z, 1.0) for r in ground.ravine) and not any(r.contains(x, z) for r in reserved)
            ok = ok and not ground.steep(x, z) and all((x - tx) ** 2 + (z - tz) ** 2 > 6.0 for tx, tz in trunks)
            fx, fz = (plane + sign * 1.0, u) if axis == 0 else (u, plane + sign * 1.0)
            ok = ok and ground.at(x, z) < ground.at(fx, fz) + 3.0  # the face's own foot, not up a slope
            if ok:
                piece = ("RockB", "StoneBroad", "RockA", "StoneLean")[int(hash01(x, z, 3.0) * 4)]
                P.add(piece, x, ground.at(x, z) - 0.05, z, hash01(x, z, 4.0) * 360, 0.9 + 0.4 * hash01(z, x), band="foot")
            u += sc["foot"] * (0.7 + 0.6 * hash01(u, 5.0))


def boulder_piles(level: Level, ground: Ground, P: Placements, reserved: list[Rect]) -> list[Rect]:
    """Boulder piles where nobody walks (Ben's second look at the rocks, 2026-10-21): beside every
    open camp's gates, just outside the fence line and the road, and at the corners where a tall
    wall's end stands beside walkable ground (the gatehouse's mouth, the clearing's east gate):
    the cliff's blocks fallen into a heap, a big stone, a smaller one or two and pebbles, every
    stone's footprint off walkable ground and water (rule 4c). Returns the piles' footprints with
    a margin (the trees keep off them)."""
    bp = ART["piles"]
    parts = level.union_parts()
    rects = [p[0] for p in parts]
    grounds = rects + [w.rect for w in level.water]
    tall = [s for s in level.solids if s.kind in ("wall", "fence", "pillar") and s.hi[1] - s.lo[1] > 20 and s.name not in level.climb_pieces]
    # the ground a wall's corner must stand beside to be seen: not the cave's inside, not a walled
    # camp's floor (its wall hides everything outside it)
    walled = walled_floors(level)
    seen = [p[0] for p in parts if p[3] not in level.roofed and not any(p[0].overlaps(f) for f in walled)]
    anchors = []
    for cid, camp in sorted(level.camps.items()):
        if camp.get("locks"):
            continue
        t = level.fence_thickness(camp)
        for side, a, b in level.gate_spans(camp):
            nx, nz = SIDES[side]
            out = (camp["sx"] if nz == 0 else camp["sz"]) / 2 + t + bp["out"]
            for end, step in ((a, -1), (b, 1)):
                along = end + step * bp["along"]
                x = camp["x"] + nx * out + (along if nz else 0.0)
                z = camp["z"] + nz * out + (along if nx else 0.0)
                anchors.append((x, z, (nx, nz), True))
    for s in tall:
        r = s.rect
        for cx, cz, dx, dz in ((r.x0, r.z0, -1, -1), (r.x1, r.z0, 1, -1), (r.x0, r.z1, -1, 1), (r.x1, r.z1, 1, 1)):
            x, z = cx + dx * bp["corner"], cz + dz * bp["corner"]
            q = min(seen, key=lambda q: q.distance(x, z))
            if q.distance(x, z) > bp["beside"]:
                continue
            # seen from there: no tall wall between the corner and that ground
            qx, qz = min(max(x, q.x0), q.x1), min(max(z, q.z0), q.z1)
            steps = max(2, int(math.hypot(qx - x, qz - z) / 0.5))
            if any(o.rect.contains(x + (qx - x) * k / steps, z + (qz - z) * k / steps) for o in tall for k in range(steps + 1)):
                continue
            if any(o.rect.contains(x, z, 0.5) for o in level.solids):
                continue
            anchors.append((x, z, (dx, dz), False))
    out = []
    taken: list[tuple[float, float]] = []
    for x, z, (dx, dz), gate in anchors:
        if any(math.hypot(x - tx, z - tz) < bp["spacing"] for tx, tz in taken):
            continue
        if any(r.contains(x, z, 1.0) for r in grounds) or any(r.contains(x, z, 1.0) for r in ground.ravine):
            continue
        if not gate and any(r.contains(x, z) for r in reserved):
            continue  # a camp's own outskirts: its tents and racks stand there
        placed = 0
        for k, (piece, off, scale) in enumerate(bp["heap"]):
            ang = math.atan2(dz, dx) + (hash01(x, z, 3.0 + k) - 0.5) * 2.2
            px, pz = x + math.cos(ang) * off, z + math.sin(ang) * off
            item = {"piece": piece, "x": px, "y": 0.0, "z": pz, "yaw": hash01(px, pz, 5.0) * 360.0, "scale": scale * (0.9 + 0.25 * hash01(px, pz, 6.0))}
            foot, _top = footprint(item)
            if any(foot.overlaps(r.grown(0.2)) for r in grounds) or any(foot.overlaps(s.rect) for s in tall):
                continue
            P.add(piece, px, ground.at(px, pz) - 0.08, pz, item["yaw"], item["scale"], band="pile")
            out.append(foot.grown(0.6))
            placed += 1
        if placed:
            taken.append((x, z))
    return out


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
            start = bl["yardStart"] if yard_nearest(level, rects, cx, cz) else bl["start"]
            if d < start - cell * 0.5:
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

    # How many cells in from the canopy's edge each cell lies: an underside `deep` cells in is
    # never seen (the tops above it are opaque, and no walker gets under it), so it is left out.
    depth = [[0 if on[j][i] else -1 for i in range(nx)] for j in range(nz)]
    frontier = []
    for j in range(nz):
        for i in range(nx):
            if on[j][i] and any(not (0 <= i + di < nx and 0 <= j + dj < nz) or not on[j + dj][i + di]
                                for di in (-1, 0, 1) for dj in (-1, 0, 1)):
                depth[j][i] = 1
                frontier.append((i, j))
    level_n = 1
    while frontier:
        nxt = []
        for i, j in frontier:
            for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                ii, jj = i + di, j + dj
                if 0 <= ii < nx and 0 <= jj < nz and depth[jj][ii] == 0:
                    depth[jj][ii] = level_n + 1
                    nxt.append((ii, jj))
        frontier = nxt
        level_n += 1

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
            for t in ((ua, uc, ub), (ua, ud, uc)) if depth[j][i] < bl["deep"] else ():
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
        dress_mountain(level, self.ground, self.P)
        stones = scatter_stones(level, self.ground, self.P, reserved)
        piles = boulder_piles(level, self.ground, self.P, reserved)
        plant(level, self.ground, self.P, reserved + stones + piles)
        foot_boulders(level, self.ground, self.P, reserved)
        columns = massif_columns(level, self.ground) + lip_columns(level, self.ground)
        flat, slopes = self.ground.meshes()
        skin, deck = skins(level, self.ground)
        rocks = rock_faces(level, self.ground)
        mountain_faces(level, rocks)
        mountain_caps(level, rocks)
        mountain_scree(level, self.ground, rocks)
        step_faces(level, rocks)
        gully_faces(level, self.ground, rocks)
        rocks.extend(columns)
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
    parser.add_argument("mode", choices=("build", "check", "stats", "mutants"))
    parser.add_argument("--out-root", default=OUT_ROOT)
    parser.add_argument("--data", help="the dress data file (default src/shared/Config/LevelDress/<layout>.json)")
    args = parser.parse_args(argv)
    level = Level()
    args.data = args.data or os.path.join(DRESS_DIR, f"{level.layout_name}.json")
    build = Build(level)
    if args.mode == "stats":
        stats(build)
        return 0
    if args.mode == "mutants":
        import forestcheck  # noqa: E402

        results = forestcheck.mutants(build, args.data)
        for name, ok, line in results:
            print(f"{'CAUGHT' if ok else 'MISSED':7s} {name:34s} {line[:140]}")
        caught = sum(ok for _, ok, _ in results)
        print(f"[forest] mutants: {caught}/{len(results)} caught")
        return 0 if caught == len(results) else 1
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
