#!/usr/bin/env python
"""Cross-check the Luau city fabric against its Python mirror on the real data.

`src/shared/CityFabric.luau` is pure, so the official `luau` interpreter can run the very file the
game runs. This gives both implementations the same inputs -- every fabric era's real layout, data
and config, at every purchase of the sim's greedy player, at the last moment of every tier, at the
finished plot and, where a slot builds a highway, at the finished plot without that slot -- and
compares what they answer:

  * `Develop`: every parcel's level, district and governor;
  * `LaneReach`: every lane's reach, to the last bit;
  * `IsCleared`: every wild clearing point (each clump quarter, each single) against the moment's
    clearing mask (so `RectDistance` and `SegmentDistance` too, which are also compared number for
    number on the finished plot);
  * the looks (INTERFACES "Wave 3.2"): at every moment, the site every level-1 parcel shows
    (`SiteProp`) and the prop every building shows once the swaps have had their say (`ValidSwaps`,
    `SwappedProp`), from the era's real config; and all three on synthetic vectors, malformed
    configs included;
  * `LevelStage` and `RingRects` on synthetic vectors;
  * the highway's ring (INTERFACES "Wave 4.2"): whether it is a round loop (`RoundLoop`), the rects
    it hands the mask (`RingGround`), the band that never clears (`RingBand`: the layout's ring
    and the era's `highway.bandHalf`) and, at every moment, every wild clearing point with that
    band kept (`KeptInBand`, then `IsCleared`) against the mirror's cleared flags. The same again
    on the finished plot under other `highway` blocks (HIGHWAY_VARIANTS: round or not, `clearBand`
    false or not, another `bandHalf`, Metropolis's ring with and without its ramp), which is where
    a ring that has rects loses them for being round. And under the blocks the tools refuse or
    have no reading for (HIGHWAY_RULED), where the review ruled what the game makes of each;
  * the wild swaps: at every moment, the prop every standing wild placement shows
    (`ValidWildSwaps`, `SwappedWild`) against the mirror's placements;
  * the upgrade layers: at every moment, which entries of every layer are placed
    (`ValidUpgradeItem`, `HighwayBuilt`, `UpgradeDeveloped` and the layer's own slot) against the
    mirror's placements;
  * `RingClears`, `RingKeeps`, `ValidWildSwaps`, `SwappedWild`, `ValidUpgradeItem` and
    `HighwayBuilt` on synthetic vectors, malformed configs included.

And `src/client/City/Tubes.luau`, the client's copy of tools/paths/tubes.py, which is pure as well:
for every era, whether its streets are tubes and the hub's prop (`Tubes.Config`); for every tube
era, the nodes a hub stands on, why and with which stretches (`Tubes.HubNodes` against
`TubePlan.hubs`) and the entrance apron (`Tubes.EntranceApron` against `TubePlan.entrance_apron`).
Where a hub stands on the drawn centreline (`TubePlan.node_point`) is RoadGraph's to compute, with
Roblox types, and is not run here.

Sines and cosines. The two interpreters take them from different C libraries, and those may round
the last bit differently (the cosine of Orbital's 300.03 degree landmark, on the machine this was
written on). The number-for-number distances are therefore taken with the mirror computing on the
Luau run's own cos and sin of each rect's turn: everything the module itself computes is still
compared to the last bit, and the era's line says how many turns the libraries disagreed on. The
cleared bits are compared as each side computed them, so a difference there is a wild point that
stands within a rounding error of a margin.

A Luau export this script has no comparison for, and a comparison whose Luau function does not exist
yet, are listed; with `--strict` either one fails the run. Any difference exits 1.

    py tools/check_mirror.py                # Village, Boomtown, Metropolis, OrbitalColony
    py tools/check_mirror.py Metropolis     # one era
    py tools/check_mirror.py --keep <dir>   # leave the generated Luau files there
    py tools/check_mirror.py --module <f>   # run another copy of the module (a deliberately broken one)
    py tools/check_mirror.py --tubes <f>    # likewise for Tubes.luau

The interpreter comes from the same pinned release tools/check_compile.py takes luau-compile from,
downloaded into tools/bin/ (gitignored) on first use: Rokit installs neither here.
"""

from __future__ import annotations

import argparse
import contextlib
import copy
import io
import json
import math
import platform
import shutil
import subprocess
import sys
import tempfile
import types
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))

import check_compile  # noqa: E402
import cityfabric  # noqa: E402
import streetplan  # noqa: E402

MODULE = ROOT / "src" / "shared" / "CityFabric.luau"
TUBES = ROOT / "src" / "client" / "City" / "Tubes.luau"
TUBES_COMPARED = ("Config", "HubNodes", "EntranceApron")  # the functions of Tubes.luau compared here
# A network for Tubes.HubNodes with every kind of node, as (from, to, chain) a stretch: an end (0,
# 4, 6, 7), two stretches of one chain (1, 5: no hub), two chains meeting end to end (2: a joint,
# which no shipped tube era has), a branch of four (3), a stretch that ends where it starts (8: no
# hub) and a node no stretch reaches (9).
HUB_NET = ((0, 1, "a"), (1, 2, "a"), (2, 3, "b"), (3, 4, "b"), (3, 5, "c"), (5, 6, "c"), (3, 7, "d"), (8, 8, "e"))
HUB_NET_NODES = 10
# First tubes that leave no entrance apron, as (street 1's first z, the plot's depth): on the front
# edge and inside streetplan.MIN_LENGTH of it.
APRON_EDGES = ((-60.0, 120.0), (-59.96, 120.0))
DEFAULT_ERAS = ("Village", "Boomtown", "Metropolis", "OrbitalColony")
# How many clearing points and mask rects of the finished plot are compared number for number.
DISTANCE_POINTS = 60
DISTANCE_RECTS = 40
SHOWN = 12  # differences listed per kind before "... and N more"

# The comparisons that need a Luau export INTERFACES "Wave 3.2" names; each is skipped, and listed,
# until the module exports it.
LEVEL_STAGE_LISTS = (None, [0, 1, 2], [1, 3, 4], [1, 3], [2], [1, 3, 4, 4, 7], [], [1.5, 3, 4], [-1, 3, 4], [1, "3", 4], "x", True)
LEVEL_STAGE_LEVELS = range(2, 8)
LEVEL_STAGE_COUNTS = range(1, 7)
RING_CASES = (
    (56, 7, None, 0),
    (56, 7, {"cell": [-56, -28], "direction": "+X"}, 3),
    (56, 7, {"cell": [28, 56], "direction": "-Z"}, 2),
    (56, 7, {"cell": [-56, -28], "direction": "up"}, 3),
    (49, 7, {"cell": [49, 0], "direction": "-X"}, 1),
    (0, 7, None, 0),
    (56, 0, None, 0),
)

# The real lanes end at a square lot or at the lane's own length, so they cannot tell a lot's frontage
# from its depth: these do. (lane, lots as (size, lane, laneAlong), levels, sizes, budget)
LANE_DOGLEG = {"points": [[0, 0], [0, 10], [8, 10]], "stretch": "L1_1", "along": 3}
LANE_LOTS = [("narrow", 1, 2.0), ("small", 1, 7.5), ("narrow", 1, 11.0), ("medium", 2, 12.0), ("narrow", 1, 15.5)]
LANE_SIZES = {"narrow": [4, 8], "small": [6, 6], "medium": [8, 8]}
LANE_CASES = (
    ([1, 0, 0, 0, 0], LANE_SIZES, 99),
    ([0, 1, 0, 0, 0], LANE_SIZES, 99),
    ([2, 2, 3, 0, 0], LANE_SIZES, 99),
    ([2, 2, 3, 4, 1], LANE_SIZES, 99),
    ([2, 2, 3, 4, 1], LANE_SIZES, 3),
    ([2, 2, 3, 4, 1], {"small": [6, 6]}, 99),
    ([0, 0, 0, 4, 0], LANE_SIZES, 99),
    ([0, 0, 0, 0, 0], LANE_SIZES, 99),
)

# Looks (wave 3.2). Site configs beyond the eras' own: malformed and partial ones.
SITE_SIZES = ("small", "medium", "narrow", "large")
SITE_INDEXES = range(1, 9)
SITES = {"small": "SiteSmall", "medium": "SiteMedium", "narrow": "SiteNarrow"}
SITE_CONFIGS = (
    {"sites": SITES, "siteVariants": {"narrow": ["SiteNarrow", "SiteNarrowCrane", "SiteNarrow"], "small": ["SiteSmall", "SiteSmallCrane"]}},
    {"sites": SITES, "siteVariants": None},
    {"sites": SITES, "siteVariants": "x"},
    {"sites": SITES, "siteVariants": []},
    {"sites": SITES, "siteVariants": {"narrow": []}},
    {"sites": SITES, "siteVariants": {"narrow": "SiteNarrow"}},
    {"sites": SITES, "siteVariants": {"narrow": ["A", 3, "C"], "small": {"a": "b"}}},
    {"sites": SITES, "siteVariants": {"narrow": [True, "B"], "medium": ["M"]}},
    {"sites": None, "siteVariants": {"narrow": ["A", "B"]}},
    {"sites": "x", "siteVariants": None},
    {"sites": {"small": 5, "medium": "SiteMedium"}, "siteVariants": {"large": ["Z"]}},
    {"sites": {"large": "Big"}, "siteVariants": {"large": ["Z"]}},
)
# Swap lists. An empty JSON object for `districts` reads in Luau as an empty list (a table either
# way): Python skips that entry and Luau keeps it with no district, so neither ever swaps. It is
# therefore in the SwappedProp vectors (SWAP_ONLY_LISTS) and left out of the ValidSwaps ones.
SWAP_LISTS = (
    None,
    "x",
    {"requiresSlot": "a", "suffix": "G"},
    [],
    [{"requiresSlot": "a", "suffix": "Green"}],
    [{"requiresSlot": "a", "suffix": "Green"}, {"requiresSlot": "b", "suffix": "Crown"}],
    [{"requiresSlot": "a", "suffix": "Green", "districts": ["residential", "retail"]}],
    [{"requiresSlot": "a", "suffix": "Green", "districts": []}],
    [{"requiresSlot": "a", "suffix": "Green", "districts": {"x": "residential"}}],
    [{"requiresSlot": "a", "suffix": "Green", "districts": ["residential", 3]}],
    [{"requiresSlot": "a", "suffix": ""}, {"requiresSlot": "b", "suffix": "Crown"}],
    [{"requiresSlot": 4, "suffix": "Green"}, "junk", ["requiresSlot"], {"suffix": "Crown"}, {"requiresSlot": "b", "suffix": "Crown"}],
    [{"requiresSlot": "a", "suffix": "Green", "districts": "residential"}],
)
SWAP_ONLY_LISTS = ([{"requiresSlot": "a", "suffix": "Green", "districts": {}}],)
SWAP_EXISTING = ("TowerGreen", "TowerGreenCrown", "TowerCrown", "ShopGreen", "FabricResNarrowAGreen", "OfficeCrown")
SWAP_PROPS = ("Tower", "Shop", "Office", "FabricResNarrowA", "Plaza")
SWAP_DISTRICTS = (None, "residential", "retail", "office")
SWAP_OWNED = ([], ["a"], ["b"], ["a", "b"], ["rooftopGarden"], ["rooftopGarden", "a", "b"])

# The highway's ring (wave 4.2). `highway` blocks for RingClears: only the boolean false keeps the band.
RING_CLEAR_BLOCKS = (
    None,
    {},
    {"requiresSlot": "highwayRamp"},
    {"clearBand": False},
    {"clearBand": True},
    {"clearBand": 0},
    {"clearBand": "false"},
    {"requiresSlot": "walkwayNetwork", "round": True, "clearBand": False},
    "x",
    [],
    7,
)
# Points for RingKeeps and KeptInBand: the mirror's selftest points round a ring of 56 with a half
# of 3.5 (the band's two edges from each side), the edges of a half of 2, the centre, diagonals and
# points no number places.
BAND_POINTS = (
    (55.75, 3.25),
    (-39.6, -39.6),
    (49.25, 3.25),
    (52.5, 0),
    (52.4, 0),
    (0, 59.5),
    (0, 59.6),
    (54, 0),
    (53.9, 0),
    (0, -58),
    (0, -58.1),
    (46, 46),
    (0, 0),
    (-56, 0.0),
    (37.2, -37.2),
    (41.9, 42.2),
    (math.nan, 0),
    (math.inf, 0),
    (0, -math.inf),
)
BAND_RINGS = (56, 56.0, 42, 59.5, 0, -56, None, "56", True, math.inf, math.nan)
BAND_HALVES = (3.5, 0.25, 0, -1, None, "3.5", math.inf)
# `highway` blocks laid over an era's own (None takes the key out), each run through the mirror's
# own FabricPlot on the finished plot: whether the loop is round, what the ring hands the mask and
# which band is kept. The third entry is whether the layout keeps its ramp: Metropolis's ring
# without it is the one ring that has rects to lose for being round.
ROUND = {"round": True, "segments": 48, "bandHalf": 3.5}
HIGHWAY_VARIANTS = (
    ("Metropolis", {"clearBand": False}, True),
    ("Metropolis", {"clearBand": True}, True),
    ("Metropolis", {"clearBand": 0}, True),
    ("Metropolis", {"clearBand": "false"}, True),
    ("Metropolis", {}, False),
    ("Metropolis", {"clearBand": False}, False),
    ("Metropolis", ROUND, False),
    ("Metropolis", {**ROUND, "clearBand": True}, False),
    ("Metropolis", {**ROUND, "clearBand": False}, False),
    ("Metropolis", {**ROUND, "clearBand": False, "bandHalf": 6}, False),
    ("Metropolis", {"round": "true", "clearBand": False}, False),
    ("Metropolis", {"round": 1, "clearBand": False}, False),
    ("OrbitalColony", {"clearBand": True}, True),
    ("OrbitalColony", {"clearBand": 0}, True),
    ("OrbitalColony", {"clearBand": None}, True),
    ("OrbitalColony", {"bandHalf": 2}, True),
    ("OrbitalColony", {"bandHalf": 5.25}, True),
    ("OrbitalColony", {"round": False}, True),
    ("OrbitalColony", {"round": 1}, True),
    ("OrbitalColony", {"round": None}, True),
    ("OrbitalColony", {"round": None, "clearBand": None}, True),
)
# Blocks the tools refuse (a round loop without a usable `bandHalf`) or have no reading of their
# own for (`round` on a ring with a ramp). The wave 4.2 review ruled what each is in the game, and
# each ruling names a block the mirror does read: Luau is handed the first block, the mirror the
# second, and their answers must be the same.
HIGHWAY_RULED = (
    # `round` on a layout highway with a ramp is the square ring (CityFabric.RoundLoop).
    ("Metropolis", ROUND, {}),
    ("Metropolis", {**ROUND, "clearBand": True}, {"clearBand": True}),
    ("Metropolis", {**ROUND, "clearBand": False}, {"clearBand": False}),
    # A bad or absent `bandHalf` is no band: the same loop with `clearBand` true.
    ("OrbitalColony", {"bandHalf": None}, {"clearBand": True}),
    ("OrbitalColony", {"bandHalf": 0}, {"clearBand": True}),
    ("OrbitalColony", {"bandHalf": -3.5}, {"clearBand": True}),
    ("OrbitalColony", {"bandHalf": "3.5"}, {"clearBand": True}),
    ("OrbitalColony", {"bandHalf": True}, {"clearBand": True}),
    ("OrbitalColony", {"bandHalf": math.inf}, {"clearBand": True}),
    ("OrbitalColony", {"bandHalf": math.nan}, {"clearBand": True}),
)

# Wild swaps (wave 4.2): `fabric.swaps`' shape without districts, so SWAP_LISTS and SWAP_ONLY_LISTS
# are asked as well (an entry that names districts, well formed or not, is skipped on both sides).
WILD_SWAP_LISTS = (
    [{"requiresSlot": "rockGarden", "suffix": "Garden"}],
    [{"requiresSlot": "rockGarden", "suffix": "Garden"}, {"requiresSlot": "holoBeacon", "suffix": "Lit"}],
    [{"requiresSlot": "holoBeacon", "suffix": "Lit"}, {"requiresSlot": "rockGarden", "suffix": "Garden"}],
    [{"requiresSlot": "rockGarden", "suffix": "Garden"}, {"requiresSlot": "holoBeacon", "suffix": "Lit"}, {"requiresSlot": "x", "suffix": "Q", "districts": ["habitat"]}, {"requiresSlot": "y"}, 7],
    [{"requiresSlot": "rockGarden", "suffix": "Garden", "districts": []}, {"requiresSlot": "holoBeacon", "suffix": "Lit"}],
)
WILD_EXISTING = ("RegolithClumpA", "RegolithClumpAGarden", "RegolithQuarterA", "RegolithQuarterAGarden", "RegolithClumpAGardenLit", "SurveyBeacon", "RegolithCraterLit", "RegolithCraterLitGarden")
WILD_PROPS = (None, "RegolithClumpA", "RegolithQuarterA", "SurveyBeacon", "RegolithCrater", "RegolithBoulder", "Tower")
WILD_OWNED = ([], ["rockGarden"], ["holoBeacon"], ["rockGarden", "holoBeacon"], ["x", "y"], ["a", "b"])

# Upgrade entries (wave 4.2) for ValidUpgradeItem: every anchor with and without what it needs.
UPGRADE_ITEM = {"x": 1, "z": 2, "rotationY": 0, "scale": 1, "variant": 2}
UPGRADE_ITEMS = (
    {**UPGRADE_ITEM, "anchor": "highway"},
    {**UPGRADE_ITEM, "anchor": "highway", "stretch": 5, "parcel": "x"},
    {**UPGRADE_ITEM, "anchor": "stretch", "stretch": "L1_1"},
    {**UPGRADE_ITEM, "anchor": "stretch"},
    {**UPGRADE_ITEM, "anchor": "stretch", "stretch": 3},
    {**UPGRADE_ITEM, "anchor": "stretch", "parcel": 4},
    {**UPGRADE_ITEM, "anchor": "parcel", "parcel": 4},
    {**UPGRADE_ITEM, "anchor": "parcel", "parcel": 4.5},
    {**UPGRADE_ITEM, "anchor": "parcel"},
    {**UPGRADE_ITEM, "anchor": "parcel", "parcel": "4"},
    {**UPGRADE_ITEM, "anchor": "parcel", "parcel": math.nan},
    {**UPGRADE_ITEM, "anchor": "parcel", "stretch": "L1_1"},
    {**UPGRADE_ITEM, "anchor": "pier"},
    {**UPGRADE_ITEM, "anchor": True},
    {**UPGRADE_ITEM},
    {**UPGRADE_ITEM, "anchor": "highway", "scale": 0},
    {**UPGRADE_ITEM, "anchor": "highway", "scale": -1},
    {**UPGRADE_ITEM, "anchor": "highway", "scale": "1"},
    {**UPGRADE_ITEM, "anchor": "highway", "scale": True},
    {**UPGRADE_ITEM, "anchor": "highway", "scale": math.inf},
    {**UPGRADE_ITEM, "anchor": "highway", "variant": None},
    {**UPGRADE_ITEM, "anchor": "highway", "variant": "2"},
    {**UPGRADE_ITEM, "anchor": "highway", "x": math.inf},
    {**UPGRADE_ITEM, "anchor": "highway", "z": None},
    {**UPGRADE_ITEM, "anchor": "highway", "rotationY": "0"},
    {**UPGRADE_ITEM, "anchor": "highway", "rotationY": math.nan},
    "highway",
    7,
    [],
    None,
)
# HighwayBuilt: the era's `highway` block, the layout's highway and the owned slots. An empty JSON
# array reads in Luau as the empty table an empty object is, so neither stands in for a block here.
BUILT_BLOCKS = (None, {}, {"requiresSlot": "walkwayNetwork"}, {"requiresSlot": 7}, {"requiresSlot": "walkwayNetwork", "round": True, "clearBand": False}, {"props": {"arc": "MonorailArc"}}, "x", 7)
BUILT_LAYOUTS = (None, {"ring": 56}, {"ring": 56, "ramp": {"direction": "+X"}}, {}, "ring", 56)
BUILT_OWNED = ([], ["walkwayNetwork"], ["highwayRamp"], ["highwayRamp", "walkwayNetwork"])

# The per-moment and per-era comparisons on the real data, by the line the harness prints them on,
# with the exports each needs: a comparison runs only when the module has them all.
REAL_GROUPS = (
    ("LOOK", ("SiteProp", "ValidSwaps", "SwappedProp")),
    ("ROUND", ("RoundLoop",)),
    ("KEPT", ("RingBand", "KeptInBand")),
    ("GROUND", ("RingGround",)),
    ("WILD", ("ValidWildSwaps", "SwappedWild")),
    ("UPG", ("ValidUpgradeItem", "HighwayBuilt", "UpgradeDeveloped")),
)

HARNESS = r"""
local CityFabric = require("./CityFabric")
local data = require("./cases")

local function num(value)
	return string.format("%.17g", value)
end

local function rectText(rect)
	return string.format("%s,%s,%s,%s,%s,%s", num(rect.x), num(rect.z), num(rect.hx), num(rect.hz), num(rect.rotationY), num(rect.margin))
end

local function setOf(list)
	local set = {}
	for _, name in list do
		set[name] = true
	end
	return set
end

-- A pcall's answer as text: booleans as "true" and "false", so nil in place of false shows.
local function answer(ok, value)
	return if ok then tostring(value) else "error:" .. tostring(value)
end

local exported = {}
for name, value in CityFabric do
	if type(value) == "function" then
		table.insert(exported, name)
	end
end
table.sort(exported)
print("EXPORTS " .. table.concat(exported, " "))

local siteProp = (CityFabric :: any).SiteProp
local validSwaps = (CityFabric :: any).ValidSwaps
local swappedProp = (CityFabric :: any).SwappedProp
local roundLoop = (CityFabric :: any).RoundLoop
local ringGround = (CityFabric :: any).RingGround
local ringBand = (CityFabric :: any).RingBand
local keptInBand = (CityFabric :: any).KeptInBand
local validWildSwaps = (CityFabric :: any).ValidWildSwaps
local swappedWild = (CityFabric :: any).SwappedWild
local validUpgradeItem = (CityFabric :: any).ValidUpgradeItem
local highwayBuilt = (CityFabric :: any).HighwayBuilt
local upgradeDeveloped = (CityFabric :: any).UpgradeDeveloped

for e, era in data.eras do
	local function exists(name)
		return era.exists[name] == true
	end
	-- Wave 4.2: the highway as the client hands it over -- the era's `highway` block, the layout's
	-- highway (its ring, and its ramp where it has one), the tile pitch, the ramp as RingRects
	-- reads it and its length in cells.
	if roundLoop ~= nil then
		print(string.format("ROUND %d %s", e, answer(pcall(roundLoop, era.highway, era.layoutHighway))))
	end
	if ringGround ~= nil then
		local out = {}
		for r, rect in ringGround(era.highway, era.layoutHighway, era.tileStuds, era.ramp, era.rampCells) do
			out[r] = rectText(rect)
		end
		print(string.format("GROUND %d %s", e, table.concat(out, " ")))
	end
	local band = nil
	if ringBand ~= nil then
		band = ringBand(era.highway, era.layoutHighway)
		print(string.format("BAND %d %s", e, if band ~= nil then num(band.ring) .. " " .. num(band.half) else "-"))
	end
	-- The band alone, on points round its edges.
	if ringBand ~= nil and keptInBand ~= nil then
		local inside = {}
		for index, point in data.bandPoints do
			inside[index] = if keptInBand(point[1], point[2], band) then "1" else "0"
		end
		print(string.format("BPTS %d %s", e, table.concat(inside)))
	end
	for c, case in era.cases do
		local states = CityFabric.Develop({
			tier = case.tier,
			stretches = case.stretches,
			landmarks = case.landmarks,
			parcels = era.parcels,
		}, era.pull)
		local out, levels = {}, {}
		for index, state in states do
			out[index] = string.format("%s:%s:%s", num(state.level), state.district or "-", state.governor or "-")
			levels[index] = state.level
		end
		print(string.format("DEV %d %d %s", e, c, table.concat(out, " ")))
		local reaches = {}
		for index, lane in era.lanes do
			reaches[index] = num(CityFabric.LaneReach(lane, index, era.parcels, levels, era.sizes, era.budget))
		end
		print(string.format("LANE %d %d %s", e, c, table.concat(reaches, " ")))
		local bits = {}
		for index, point in era.points do
			bits[index] = if CityFabric.IsCleared(point[1], point[2], point[3], case.mask) then "1" else "0"
		end
		print(string.format("CLR %d %d %s", e, c, table.concat(bits)))
		-- Wave 4.2: the same points as Fabric.clearedFlags asks them, the band's kept ones first.
		if ringBand ~= nil and keptInBand ~= nil then
			local kept = {}
			for index, point in era.points do
				local cleared = not keptInBand(point[1], point[2], band)
					and CityFabric.IsCleared(point[1], point[2], point[3], case.mask)
				kept[index] = if cleared then "1" else "0"
			end
			print(string.format("KEPT %d %d %s", e, c, table.concat(kept)))
		end
		local owned = setOf(case.owned)
		-- Wave 3.2 looks: a level-1 parcel's site, and a building's prop after the swaps. The prop a
		-- building starts from is Fabric.luau's business (district lists, heights), so Python hands
		-- it over; the level and the district are this run's own.
		if siteProp ~= nil and validSwaps ~= nil and swappedProp ~= nil then
			local swaps = validSwaps(era.swaps)
			local looks = {}
			for index, state in states do
				local base = case.base[tostring(index)]
				if state.level == 1 then
					looks[index] = "S:" .. (siteProp(era.sites, era.siteVariants, era.parcels[index].size, index) or "-")
				elseif state.level >= 2 and base ~= nil then
					looks[index] = "B:" .. swappedProp(base, state.district, swaps, owned, exists)
				else
					looks[index] = "-"
				end
			end
			print(string.format("LOOK %d %d %s", e, c, table.concat(looks, " ")))
		end
		-- Wave 4.2 wild swaps: which placements stand and what each starts from is Fabric.luau's
		-- business (the cleared flags, the budgets, the variant lists), so Python hands them over.
		if validWildSwaps ~= nil and swappedWild ~= nil then
			local swaps = validWildSwaps(era.wildSwaps)
			local shown = {}
			for index, prop in case.wild do
				shown[index] = swappedWild(prop, swaps, owned, exists) or "-"
			end
			print(string.format("WILD %d %d %s", e, c, table.concat(shown, " ")))
		end
		-- Wave 4.2 upgrade layers: each layer's entries inside its budget as the data lists them --
		-- "-" one the renderer skips, "1" one that is placed, "0" one that waits -- after whether
		-- the highway stands.
		if validUpgradeItem ~= nil and highwayBuilt ~= nil and upgradeDeveloped ~= nil then
			local built = highwayBuilt(era.highway, era.layoutHighway, owned)
			local placed = { answer(true, built) }
			for _, layer in era.layers do
				local slotOwned = owned[layer.requiresSlot] == true
				local chars = {}
				for index, item in layer.items do
					if not validUpgradeItem(item) then
						chars[index] = "-"
					elseif slotOwned and upgradeDeveloped(item, case.stretches, states, built) then
						chars[index] = "1"
					else
						chars[index] = "0"
					end
				end
				table.insert(placed, layer.name .. "=" .. table.concat(chars))
			end
			print(string.format("UPG %d %d %s", e, c, table.concat(placed, " ")))
		end
	end
	local last = era.cases[#era.cases]
	if last ~= nil then
		local values = {}
		for p = 1, math.min(#era.points, data.distancePoints) do
			local point = era.points[p]
			for r = 1, math.min(#last.mask.rects, data.distanceRects) do
				table.insert(values, num(CityFabric.RectDistance(point[1], point[2], last.mask.rects[r])))
			end
			for s = 1, math.min(#last.mask.segments, data.distanceRects) do
				table.insert(values, num(CityFabric.SegmentDistance(point[1], point[2], last.mask.segments[s])))
			end
		end
		print(string.format("DIST %d %s", e, table.concat(values, " ")))
		-- This interpreter's cos and sin of each of those rects' turns, for Python to compute on.
		local turns = {}
		for r = 1, math.min(#last.mask.rects, data.distanceRects) do
			local angle = math.rad(last.mask.rects[r].rotationY)
			table.insert(turns, num(math.cos(angle)))
			table.insert(turns, num(math.sin(angle)))
		end
		print(string.format("TRIG %d %s", e, table.concat(turns, " ")))
	end
end

for index, vector in data.laneCases do
	print(string.format("LANEV %d %s", index, num(CityFabric.LaneReach(data.laneDogleg, 1, data.laneLots, vector.levels, vector.sizes, vector.budget))))
end

if siteProp ~= nil then
	for index, vector in data.siteVectors do
		local ok, prop = pcall(siteProp, vector.sites, vector.variants, vector.size, vector.index)
		print(string.format("SITE %d %s", index, if ok then (prop or "-") else "error:" .. tostring(prop)))
	end
end

-- A swap list as text: each entry's slot, suffix and (ValidSwaps only) sorted districts.
local function swapText(swaps, withDistricts)
	local out = {}
	for _, swap in swaps do
		local text = swap.requiresSlot .. "|" .. swap.suffix
		if withDistricts then
			local names = {}
			if swap.districts ~= nil then
				for name in swap.districts do
					table.insert(names, name)
				end
				table.sort(names)
			end
			text ..= "|" .. (if swap.districts ~= nil then table.concat(names, ",") else "*")
		end
		table.insert(out, text)
	end
	return table.concat(out, ";")
end

if validSwaps ~= nil then
	for index, vector in data.swapLists do
		local ok, swaps = pcall(validSwaps, vector.swaps)
		print(string.format("VALID %d %s", index, if ok then swapText(swaps, true) else "error:" .. tostring(swaps)))
	end
end

if validSwaps ~= nil and swappedProp ~= nil then
	local function exists(name)
		return data.swapExisting[name] == true
	end
	for index, vector in data.swapVectors do
		local owned = setOf(vector.owned)
		local ok, prop = pcall(function()
			return swappedProp(vector.prop, vector.district, validSwaps(vector.swaps), owned, exists)
		end)
		print(string.format("SWAP %d %s", index, if ok then prop else "error:" .. tostring(prop)))
	end
end

local levelStage = (CityFabric :: any).LevelStage
if levelStage ~= nil then
	for index, vector in data.levelStages do
		local ok, value = pcall(levelStage, vector.list, vector.level, vector.count)
		print(string.format("STAGE %d %s", index, if ok then num(value) else "error:" .. tostring(value)))
	end
end

local ringRects = (CityFabric :: any).RingRects
if ringRects ~= nil then
	for index, vector in data.rings do
		local ok, rects = pcall(ringRects, vector.ring, vector.tileStuds, vector.ramp, vector.rampCells)
		if ok then
			local out = {}
			for r, rect in rects do
				out[r] = rectText(rect)
			end
			print(string.format("RING %d %s", index, table.concat(out, " ")))
		else
			print(string.format("RING %d error:%s", index, tostring(rects)))
		end
	end
end

local ringClears = (CityFabric :: any).RingClears
if ringClears ~= nil then
	for index, vector in data.ringClears do
		print(string.format("RCLR %d %s", index, answer(pcall(ringClears, vector.highway))))
	end
end

local ringKeeps = (CityFabric :: any).RingKeeps
if ringKeeps ~= nil then
	for index, vector in data.ringKeeps do
		print(string.format("RKEEP %d %s", index, answer(pcall(ringKeeps, vector.px, vector.pz, vector.ring, vector.half))))
	end
end

if validWildSwaps ~= nil then
	for index, vector in data.wildLists do
		local ok, swaps = pcall(validWildSwaps, vector.swaps)
		print(string.format("WVALID %d %s", index, if ok then swapText(swaps, false) else "error:" .. tostring(swaps)))
	end
end

if validWildSwaps ~= nil and swappedWild ~= nil then
	local function exists(name)
		return data.wildExisting[name] == true
	end
	for index, vector in data.wildVectors do
		local owned = setOf(vector.owned)
		local ok, prop = pcall(function()
			return swappedWild(vector.prop, validWildSwaps(vector.swaps), owned, exists)
		end)
		print(string.format("WSWAP %d %s", index, if ok then (prop or "-") else "error:" .. tostring(prop)))
	end
end

if validUpgradeItem ~= nil then
	for index, vector in data.upgradeItems do
		print(string.format("UITEM %d %s", index, answer(pcall(validUpgradeItem, vector.entry))))
	end
end

if highwayBuilt ~= nil then
	for index, vector in data.builtVectors do
		print(string.format("HBUILT %d %s", index, answer(pcall(highwayBuilt, vector.highway, vector.layout, setOf(vector.owned)))))
	end
end

-- src/client/City/Tubes.luau, the client's copy of tools/paths/tubes.py: whether an era's streets
-- are tubes and, where they are, its hub nodes and its entrance apron from the network Python
-- hands over as RoadGraph hands it over.
if #data.tubes > 0 then
	local Tubes = require("./Tubes")
	local functions = {}
	for name, value in Tubes do
		if type(value) == "function" then
			table.insert(functions, name)
		end
	end
	table.sort(functions)
	print("TEXPORTS " .. table.concat(functions, " "))
	print("TENTR " .. tostring(Tubes.ENTRANCE))
	for t, era in data.tubes do
		local config = Tubes.Config(era.paths)
		print(string.format("TCONF %d %s", t, if config ~= nil then "tube:" .. (config.hub or "-") else "-"))
		if era.nodeStretches ~= nil then
			local hubs = {}
			local function chainOf(stretch)
				return era.chains[stretch]
			end
			for _, hub in Tubes.HubNodes(era.nodeStretches, chainOf) do
				table.insert(hubs, string.format("%d:%s:%s", hub.node, hub.why, table.concat(hub.stretches, ",")))
			end
			print(string.format("HUBS %d %s", t, table.concat(hubs, " ")))
			-- Without a first street point RoadGraph asks for no apron at all.
			local apron = if era.firstX ~= nil
				then Tubes.EntranceApron(era.firstX, era.firstZ, era.plotDepth, era.entranceSlot)
				else nil
			local ends = if apron ~= nil then { num(apron.ax), num(apron.az), num(apron.bx), num(apron.bz) } else { "-" }
			print(string.format("APRON %d %s", t, table.concat(ends, " ")))
		end
	end
end
"""


def interpreter_path() -> Path:
    return check_compile.BIN_DIR / ("luau.exe" if platform.system() == "Windows" else "luau")


def ensure_interpreter() -> Path:
    """The `luau` interpreter of the release check_compile.py pins, fetched once into tools/bin/."""
    path = interpreter_path()
    if path.exists():
        return path
    asset = check_compile.ASSETS.get(platform.system())
    if asset is None:
        sys.exit(f"check_mirror: no Luau release asset for {platform.system()}")
    url = check_compile.RELEASE_URL.format(version=check_compile.LUAU_VERSION, asset=asset)
    print(f"downloading luau {check_compile.LUAU_VERSION} from {url}")
    with urllib.request.urlopen(url, timeout=120) as response:
        archive = zipfile.ZipFile(io.BytesIO(response.read()))
    check_compile.BIN_DIR.mkdir(parents=True, exist_ok=True)
    path.write_bytes(archive.read(path.name))
    path.chmod(0o755)
    return path


def luau(value, indent=0) -> str:
    """A Python value as a Luau literal: None is nil, a dict a table with string keys, a list an
    array, a float written so that it reads back as the same double."""
    if value is None:
        return "nil"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        if math.isnan(value):
            return "(0/0)"
        if math.isinf(value):
            return "math.huge" if value > 0 else "-math.huge"
        return repr(value)
    if isinstance(value, str):
        return json.dumps(value)
    pad = "\t" * (indent + 1)
    if isinstance(value, dict):
        items = [f"{pad}[{json.dumps(str(key))}] = {luau(item, indent + 1)}," for key, item in value.items() if item is not None]
    elif isinstance(value, (list, tuple, set)):
        items = [f"{pad}{luau(item, indent + 1)}," for item in (sorted(value) if isinstance(value, set) else value)]
    else:
        raise TypeError(f"check_mirror: cannot write {type(value).__name__} as Luau")
    return "{\n" + "\n".join(items) + "\n" + "\t" * indent + "}" if items else "{}"


def g17(value) -> str:
    """C's %.17g, as Luau's string.format writes it."""
    return "%.17g" % value


def truth(value) -> str:
    """A boolean as Luau's tostring writes it; anything else as itself, so it shows as a difference."""
    return "true" if value is True else "false" if value is False else repr(value)


def finished_moments(plot, city):
    """The finished plot and, before it, the finished plot without the slot that builds the highway
    (where the era's `highway` block names one): the greedy player buys Orbital's monorail before
    the flags, so no purchase shows a layer owned whose highway entries still wait."""
    last = len(city["tier"]["thresholds"])
    everything = {slot["id"] for slot in plot.era.config["slots"] if slot["id"] in plot.layout["slots"]}
    out = []
    highway = plot.era.dressing.get("highway")
    slot = highway.get("requiresSlot") if isinstance(highway, dict) else None
    if isinstance(slot, str) and slot in everything:
        rest = everything - {slot}
        out.append((f"full build without {slot}", rest, last, plot.final_stages(rest)))
    out.append(("full build", everything, last, plot.final_stages(everything)))
    return out


def moments(plot, city):
    """(label, owned set, GrowthTier, each owned landmark's visible stage) for an era: after each
    slot the greedy player buys, at the last moment of each tier, and the finished plot's two."""
    history = cityfabric.greedy_history(plot.name, city)
    tiers = cityfabric.buy_tiers(history)

    def stages_of(owned, levels):
        return {slot_id: plot.visible_stage(slot_id, levels.get(slot_id, 1)) for slot_id in owned}

    out = []
    for tick, kind, slot_id, levels in history["purchases"]:
        if kind == "slot":
            out.append((f"buys {slot_id}", set(levels), cityfabric.tier_at_tick(history["tier_times"], tick), stages_of(set(levels), levels)))
    for tier in range(1, len(city["tier"]["thresholds"]) + 1):
        levels, actual, _tick = cityfabric.tier_snapshot(history, tier)
        owned = {slot_id for slot_id in levels if tiers.get(slot_id, 99) <= tier}
        out.append((f"end of tier {tier}", owned, actual, stages_of(owned, levels)))
    return out + finished_moments(plot, city)


def highway_view(plot):
    """What the client hands CityFabric about the plot's highway, from where the mirror reads it:
    the era's `highway` block, the layout's highway (its ring, and its ramp when it has one), the
    tile pitch, the ramp as Highway.Ground views it and its length in cells."""
    era = plot.era
    layout = era.highway if isinstance(era.highway, dict) else None
    ramp = era.highway_ramp
    view = {"cell": [ramp["cell"][0], ramp["cell"][2]], "direction": ramp.get("direction")} if isinstance(ramp, dict) else None
    return {
        "highway": era.dressing.get("highway"),
        # A ramp the view cannot show is a ramp all the same: the rules only ask whether one is there.
        "layoutHighway": {"ring": layout.get("ring"), "ramp": view if view is not None or ramp is None else True} if layout is not None else None,
        "tileStuds": era.tile_studs,
        "ramp": view,
        "rampCells": era.ramp_cells,
    }


def rect_text(rect) -> str:
    return ",".join(g17(rect[key]) for key in ("x", "z", "hx", "hz", "rotationY", "margin"))


def era_cases(era_name, city, label=None, history=True, luau_highway=None):
    """(the table handed to Luau, what Python answers) for one era, or None without fabric data.
    `label` names it in the report (the era's own name without one); `history` False keeps the
    finished plot's moments only; `luau_highway` is the `highway` block Luau is handed where that
    is not the one in `city` (HIGHWAY_RULED)."""
    plot = cityfabric.FabricPlot.load(era_name, city=city)
    if plot is None or plot.pull is None:
        return None
    points, owners = [], []  # owners: the (wild entry, quarter) each clearing point belongs to
    radii = plot.wild_config or {}
    for index, entry in enumerate(plot.wild_data, start=1):
        if entry.get("kind") == cityfabric.CLUMP:
            for quarter, quad in enumerate(entry.get("quads") or [], start=1):
                points.append([quad[0], quad[1], radii.get("quarterRadius", 0)])
                owners.append((index, quarter))
        else:
            points.append([entry["x"], entry["z"], radii.get("singleRadius", 0)])
            owners.append((index, 1))
    banded = [plot.kept_in_band(point[0], point[1]) for point in points]
    cases, expected = [], []
    config = plot.config or {}
    swaps = cityfabric.valid_swaps(config.get("swaps"))
    wild_swaps = cityfabric.valid_wild_swaps(config.get("wildSwaps"))
    asked = {}  # every name the swaps may ask about -> whether it can spawn

    def exists(name):
        asked[name] = plot.heights.exists(name)
        return asked[name]

    twinned = set()  # the wild props whose twins have been asked about

    def ask_twins(name):
        """Whether `name` and everything the wild swaps can turn it into can spawn."""
        twinned.add(name)
        names = [name]
        for swap in wild_swaps:
            names += [each + swap["suffix"] for each in names]
        for each in names:
            exists(each)

    # Each layer's entries inside its budget as the data lists them, malformed ones included:
    # FabricPlot keeps only the well-formed ones, by their index here.
    listed = plot.data.get("upgrades") if isinstance(plot.data, dict) else None
    layers = []
    for layer in plot.layers:
        items = listed.get(layer["name"]) if isinstance(listed, dict) else None
        items = items if isinstance(items, list) else []
        layers.append({"name": layer["name"], "requiresSlot": layer["config"]["requiresSlot"], "items": items[: int(layer["config"]["budget"])]})
    held = standing = turned = placed_total = on_highway = 0
    for moment, owned, tier, stages in moments(plot, city) if history else finished_moments(plot, city):
        stretches, joins, segments, _visible, _drawn = plot.network_view(owned)
        given = plot.develop_input(owned, tier, stretches, joins)
        states = cityfabric.develop(given, plot.pull)
        levels = [state["level"] for state in states]
        reaches = [
            cityfabric.lane_reach(lane, index, plot.parcel_data, levels, plot.lane_sizes, plot.parcel_budget)
            for index, lane in enumerate(plot.lane_data, start=1)
        ]
        mask = plot.mask(owned, states, segments, plot.visible_plazas(tier), plot.lane_reaches(states))
        # The looks, budget or not: what goal_for chooses, then the swaps. `base` is the building
        # prop before the swaps, which only Fabric.luau can choose in the game.
        base, looks = {}, []
        for index, (parcel, state) in enumerate(zip(plot.parcel_data, states), start=1):
            look = cityfabric.goal_for(config, index, parcel, state, plot.heights.prop, lambda slot_id: plot.landmark_height(slot_id, stages))
            if state["level"] == 1:
                looks.append("S:" + (look["prop"] if look is not None else "-"))
            elif look is not None:
                base[str(index)] = look["prop"]
                looks.append("B:" + cityfabric.swapped_look(look, state["district"], swaps, owned, exists)["prop"])
            else:
                looks.append("-")
        cleared = "".join("1" if cityfabric.is_cleared(p[0], p[1], p[2], mask) else "0" for p in points)
        # Fabric.clearedFlags as the mirror answers it, a bit per point; "?" where it tests another
        # point than the one listed here (a malformed entry, a clump with more than four quads).
        flags = plot.cleared_flags(mask)
        kept = "".join(
            "?" if index not in plot.wild_valid or quarter > cityfabric.QUARTERS else "1" if flags.get(index, 0) >> (quarter - 1) & 1 else "0"
            for index, quarter in owners
        )
        held += sum(1 for bit, inside in zip(cleared, banded) if inside and bit == "1")
        # Fabric.syncWild on a near plot: each standing placement's prop before the wild swaps and
        # after them. A variant without a name spawns nothing and is left out.
        wild = [placement for placement in plot.wild_placements(flags, True, 1.0, owned) if isinstance(placement.get("swappedFrom", placement["prop"]), str)]
        wild_base = [placement.get("swappedFrom", placement["prop"]) for placement in wild]
        for name in set(wild_base) - twinned:
            ask_twins(name)
        standing += len(wild)
        turned += sum(1 for placement in wild if "swappedFrom" in placement)
        # Fabric.syncLayer on a near plot: the entries placed, by index. An entry without a prop is
        # placed but not drawn, so the mirror's list cannot say which way it went ("?"); its
        # layer's count can.
        placements = plot.upgrade_placements(owned, states, stretches, tier, True)
        upgrades, counts = [truth(plot.highway_built(owned))], []
        for layer, shown in zip(plot.layers, layers):
            views = {view["index"]: view for view in layer["views"]}
            result = placements[layer["name"]]
            drawn = {placement["index"] for placement in result["drawn"]}
            chars = "".join(
                "-" if index not in views else "?" if views[index]["prop"] is None else "1" if index in drawn else "0"
                for index in range(1, len(shown["items"]) + 1)
            )
            upgrades.append(f"{layer['name']}={chars}")
            counts.append(result["placed"])
            placed_total += result["placed"]
            on_highway += sum(1 for index in drawn if views[index]["item"].get("anchor") == cityfabric.ANCHOR_HIGHWAY)
        cases.append({"tier": tier, "stretches": stretches, "landmarks": given["landmarks"], "mask": mask, "owned": sorted(owned), "base": base, "wild": wild_base})
        expected.append(
            {
                "label": moment,
                "states": [f"{g17(s['level'])}:{s['district'] or '-'}:{s['governor'] or '-'}" for s in states],
                "reaches": [g17(reach) for reach in reaches],
                "cleared": cleared,
                "kept": kept,
                "looks": looks,
                "wild": [placement["prop"] for placement in wild],
                "upgrades": upgrades,
                "placed": counts,
            }
        )
    table = {
        "name": label or era_name,
        "pull": plot.pull,
        "parcels": plot.parcel_data,
        "lanes": plot.lane_data,
        "sizes": plot.lane_sizes,
        "budget": plot.parcel_budget,
        "points": points,
        "cases": cases,
        "sites": config.get("sites"),
        "siteVariants": config.get("siteVariants"),
        "swaps": config.get("swaps"),
        "wildSwaps": config.get("wildSwaps"),
        "layers": layers,
        "exists": {name: True for name, can in asked.items() if can},
        **highway_view(plot),
    }
    if luau_highway is not None:
        table["highway"] = luau_highway
    sites = sum(1 for case in expected for look in case["looks"] if look.startswith("S:"))
    swapped = sum(1 for case, given in zip(expected, cases) for index, look in enumerate(case["looks"], start=1) if look.startswith("B:") and look[2:] != given["base"].get(str(index)))
    return table, {
        "cases": expected,
        "parcels": len(plot.parcel_data),
        "lanes": len(plot.lane_data),
        "points": len(points),
        "sites": sites,
        "swapped": swapped,
        "round": truth(plot.era.round_ring is not None),
        "band": f"{g17(plot.band_ring)} {g17(plot.era.band_half)}" if plot.band_ring is not None else "-",
        "bandPoints": "".join("1" if plot.kept_in_band(px, pz) else "0" for px, pz in BAND_POINTS),
        "ground": [rect_text(rect) for rect in plot.ring_rects],
        "banded": sum(banded),
        "held": held,
        "wild": standing,
        "wildSwapped": turned,
        "placed": placed_total,
        "onHighway": on_highway,
    }


def highway_variant(city, era_name, keys):
    """A copy of the city config with `keys` laid over one era's `highway` block (None takes a key
    out), or None for an era that has no such block."""
    highway = (city.get("eras", {}).get(era_name) or {}).get("highway")
    if not isinstance(highway, dict):
        return None
    varied = copy.deepcopy(city)
    block = varied["eras"][era_name]["highway"]
    for key, value in keys.items():
        if value is None:
            block.pop(key, None)
        else:
            block[key] = value
    return varied


@contextlib.contextmanager
def layout_ramp(keep):
    """While open with `keep` false, the tools read every layout's highway without its ramp: the
    ring Metropolis would have as a plain loop, which no shipped layout is."""
    real = streetplan.parse_layout

    def rampless(path):
        layout = dict(real(path))
        if isinstance(layout.get("highway"), dict):
            layout["highway"] = {key: value for key, value in layout["highway"].items() if key != "ramp"}
        return layout

    streetplan.parse_layout = real if keep else rampless
    try:
        yield
    finally:
        streetplan.parse_layout = real


def hub_inputs(stretches, nodes, chain_of):
    """What RoadGraph hands Tubes.HubNodes, from a network as the mirror has it: every node's
    stretches in stretch order (1-based, as Luau counts) and each stretch's chain."""
    at_node = [[] for _ in range(nodes)]
    for index, stretch in enumerate(stretches, start=1):
        for node in (stretch["from"], stretch["to"]):
            at_node[node].append(index)
    return {"nodeStretches": at_node, "chains": [str(chain_of(index)) for index in range(len(stretches))]}


def hub_text(hubs):
    return [f"{hub['node'] + 1}:{hub['why']}:{','.join(str(index + 1) for index in hub['stretches'])}" for hub in hubs]


def tube_cases(era_name, city):
    """(what Tubes.luau is handed, what tools/paths/tubes.py answers) for one era: its `road.paths`
    for Tubes.Config and, where its streets are tubes, the network for Tubes.HubNodes and what
    RoadGraph hands Tubes.EntranceApron (street 1's first point, the plot's depth, whether a slot
    is named like the apron). The apron the mirror answers is the ground it bakes, so Luau's
    centreline is compared as the slab the same tools make of it."""
    era = streetplan.Era(era_name, city)
    plan = streetplan.tube_plan(era)
    given = {"name": era_name, "paths": era.paths if isinstance(era.paths, dict) else None}
    if plan is None:
        return given, {"config": "-", "hubs": None}
    given.update(hub_inputs(plan.net.stretches, len(plan.net.nodes), lambda index: plan.bake.chain_for_stretch(index)["id"]))
    first = era.streets[0][0] if era.streets and era.streets[0] else None
    given["firstX"], given["firstZ"] = first if first is not None else (None, None)
    given["plotDepth"] = 2 * era.half_z
    given["entranceSlot"] = any(slot["id"] == plan.entrance_kind for slot in era.slots)
    hub = plan.config.get("hub")
    apron = plan.entrance_apron()
    return given, {
        "config": f"tube:{hub if isinstance(hub, str) and hub else '-'}",
        "hubs": hub_text(plan.hubs()),
        "apron": [g17(value) for corner in apron for value in corner] if apron is not None else ["-"],
        "width": streetplan.spur_path_width(era),
    }


def tube_synthetic():
    """[(what Tubes.luau is handed, what tools/paths/tubes.py answers)] for what no shipped tube era
    shows: a network with a node where two chains meet end to end (HUB_NET), and a first tube that
    starts on the plot's front edge or within a hair of it (APRON_EDGES), which leaves no apron.
    TubePlan answers both as methods of a whole plan, so each is asked of a stand-in that has only
    what the method reads; a method that has come to read more raises here, and the caller says so."""
    tubes = streetplan.tubes_module()
    stretches = [{"from": a, "to": b} for a, b, _chain in HUB_NET]
    plan = types.SimpleNamespace(
        _hubs=None,
        net=types.SimpleNamespace(stretches=stretches),
        bake=types.SimpleNamespace(chain_for_stretch=lambda index: {"id": HUB_NET[index][2]}),
        node_point=lambda node: (0.0, 0.0),  # where the hub stands: not Tubes.luau's to answer
    )
    cases = [
        (
            {"name": "a network with a joint", **hub_inputs(stretches, HUB_NET_NODES, lambda index: HUB_NET[index][2])},
            {"config": "-", "hubs": hub_text(tubes.TubePlan.hubs(plan)), "apron": ["-"], "width": 0.0},
        )
    ]
    for z, depth in APRON_EDGES:
        era = types.SimpleNamespace(streets=[[(0.0, z)]], half_z=depth / 2)
        if tubes.TubePlan.entrance_apron(types.SimpleNamespace(era=era)) is not None:
            raise ValueError(f"APRON_EDGES: a tube from z {z:g} on a plot {depth:g} deep has an apron after all")
        cases.append(({"name": f"a first tube at z {z:g}", "nodeStretches": [], "chains": [], "firstX": 0.0, "firstZ": z, "plotDepth": depth, "entranceSlot": False}, {"config": "-", "hubs": [], "apron": ["-"], "width": 0.0}))
    return cases


def tube_differences(given, want, lines, t):
    """The differences between Tubes.luau and tools/paths/tubes.py for one era."""
    name = given["name"]
    found = differences("Tubes.Config", name, [want["config"]], [lines["TCONF"].get(t, "")])
    if want["hubs"] is None:
        return found
    found += differences("Tubes.HubNodes", name, want["hubs"], lines["HUBS"].get(t, "").split())
    ends = lines["APRON"].get(t, "").split()
    if len(ends) == 4:
        slab = streetplan.slab_poly((float(ends[0]), float(ends[1])), (float(ends[2]), float(ends[3])), want["width"], 0.0)
        ends = [g17(value) for corner in slab for value in corner]
    return found + differences("Tubes.EntranceApron", name, want["apron"], ends)


def final_distances(table):
    """RectDistance and SegmentDistance from the finished plot's first clearing points to its mask's
    first rects and segments, in the order the harness lists them."""
    if not table["cases"]:
        return []
    mask = table["cases"][-1]["mask"]
    distances = []
    for point in table["points"][:DISTANCE_POINTS]:
        distances += [g17(cityfabric.rect_distance(point[0], point[1], rect)) for rect in mask["rects"][:DISTANCE_RECTS]]
        distances += [g17(cityfabric.segment_distance(point[0], point[1], seg)) for seg in mask["segments"][:DISTANCE_RECTS]]
    return distances


def luau_turns(table, text):
    """{a rect's turn in radians: (cos, sin) as the Luau run took them} for the rects of
    `final_distances`, from the harness's TRIG line; empty when the line does not fit them."""
    rects = table["cases"][-1]["mask"]["rects"][:DISTANCE_RECTS] if table["cases"] else []
    values = text.split()
    if len(values) != 2 * len(rects):
        return {}
    return {math.radians(rect["rotationY"]): (float(values[2 * i]), float(values[2 * i + 1])) for i, rect in enumerate(rects)}


@contextlib.contextmanager
def trig_from(turns):
    """While open, the mirror takes the cos and sin of the angles in `turns` from there instead of
    from this interpreter's C library (see "Sines and cosines" above), and everything else from
    `math` as always."""
    shim = types.SimpleNamespace(**{name: getattr(math, name) for name in dir(math) if not name.startswith("_")})
    shim.cos = lambda angle: turns[angle][0] if angle in turns else math.cos(angle)
    shim.sin = lambda angle: turns[angle][1] if angle in turns else math.sin(angle)
    real, cityfabric.math = cityfabric.math, shim
    try:
        yield
    finally:
        cityfabric.math = real


def look_vectors(city):
    """(site vectors, swap-list vectors, swapped-prop vectors), each as [(what Luau gets, what Python
    answers)]: every fabric era's own site config and swap list, then the malformed ones above."""
    site_configs, swap_lists = [], []
    for era in city.get("eras", {}).values():
        fabric = era.get("fabric") if isinstance(era, dict) else None
        if isinstance(fabric, dict):
            site_configs.append({"sites": fabric.get("sites"), "siteVariants": fabric.get("siteVariants")})
            if fabric.get("swaps") is not None:
                swap_lists.append(fabric.get("swaps"))
    site_configs += list(SITE_CONFIGS)
    swap_lists += list(SWAP_LISTS)
    sites = []
    for config in site_configs:
        present = {key: value for key, value in config.items() if value is not None}
        for size in SITE_SIZES:
            for index in SITE_INDEXES:
                look = cityfabric.site_look(present, size, index)
                sites.append(({"sites": config["sites"], "variants": config["siteVariants"], "size": size, "index": index}, look["prop"] if look is not None else "-"))
    valid = []
    for swaps in swap_lists:
        want = ";".join(
            f"{swap['requiresSlot']}|{swap['suffix']}|{','.join(sorted(swap['districts'])) if swap['districts'] is not None else '*'}"
            for swap in cityfabric.valid_swaps(swaps)
        )
        valid.append(({"swaps": swaps}, want))
    swapped = []
    for swaps in swap_lists + list(SWAP_ONLY_LISTS):
        checked = cityfabric.valid_swaps(swaps)
        for prop in SWAP_PROPS:
            for district in SWAP_DISTRICTS:
                for owned in SWAP_OWNED:
                    look = cityfabric.swapped_look({"kind": cityfabric.BUILDING, "prop": prop, "stage": 2}, district, checked, set(owned), lambda name: name in SWAP_EXISTING)
                    swapped.append(({"swaps": swaps, "prop": prop, "district": district, "owned": owned}, look["prop"]))
    return sites, valid, swapped


def level_stage_vectors():
    vectors = []
    for stages in LEVEL_STAGE_LISTS:
        for level in LEVEL_STAGE_LEVELS:
            for count in LEVEL_STAGE_COUNTS:
                want = max(min(cityfabric.level_stage({"levelStages": stages}, level), count - 1), 0)
                vectors.append(({"list": stages, "level": level, "count": count}, g17(want)))
    return vectors


def ring_vectors():
    vectors = []
    for ring, tile, ramp, cells in RING_CASES:
        rects = cityfabric.ring_rects(ring, tile, {"cell": tuple(ramp["cell"]), "direction": ramp["direction"]} if ramp else None, cells)
        vectors.append(({"ring": ring, "tileStuds": tile, "ramp": ramp, "rampCells": cells}, " ".join(rect_text(rect) for rect in rects)))
    return vectors


def band_vectors():
    """(RingClears, RingKeeps) vectors. KeptInBand has none of its own: the mirror's is a method of
    its plot, so every era and every highway variant is asked about BAND_POINTS instead."""
    clears = [({"highway": block}, truth(cityfabric.ring_clears(block))) for block in RING_CLEAR_BLOCKS]
    keeps = [
        ({"px": px, "pz": pz, "ring": ring, "half": half}, truth(cityfabric.ring_keeps(px, pz, ring, half)))
        for px, pz in BAND_POINTS
        for ring in BAND_RINGS
        for half in BAND_HALVES
    ]
    return clears, keeps


def wild_vectors(city):
    """(wild swap-list vectors, swapped-wild vectors): every fabric era's own `wildSwaps`, the lists
    above and the `fabric.swaps` ones."""
    lists = []
    for era in city.get("eras", {}).values():
        fabric = era.get("fabric") if isinstance(era, dict) else None
        if isinstance(fabric, dict) and fabric.get("wildSwaps") is not None:
            lists.append(fabric.get("wildSwaps"))
    lists += list(WILD_SWAP_LISTS) + list(SWAP_LISTS) + list(SWAP_ONLY_LISTS)
    existing = set(WILD_EXISTING) | set(SWAP_EXISTING)
    valid, swapped = [], []
    for swaps in lists:
        checked = cityfabric.valid_wild_swaps(swaps)
        valid.append(({"swaps": swaps}, ";".join(f"{swap['requiresSlot']}|{swap['suffix']}" for swap in checked)))
        for prop in WILD_PROPS:
            for owned in WILD_OWNED:
                shown = cityfabric.swapped_wild(prop, checked, set(owned), lambda name: name in existing)
                swapped.append(({"swaps": swaps, "prop": prop, "owned": owned}, shown if shown is not None else "-"))
    return valid, swapped, existing


def upgrade_vectors():
    """(ValidUpgradeItem, HighwayBuilt) vectors. The mirror keeps the second as a method of its plot
    too, reading the layout's highway and the era's `highway` block: a stand-in carries just those."""
    items = [({"entry": entry}, truth(cityfabric.valid_upgrade_item(entry))) for entry in UPGRADE_ITEMS]
    built = []
    for block in BUILT_BLOCKS:
        for layout in BUILT_LAYOUTS:
            for owned in BUILT_OWNED:
                plot = types.SimpleNamespace(era=types.SimpleNamespace(highway=layout, dressing={"highway": block}))
                built.append(({"highway": block, "layout": layout, "owned": owned}, truth(cityfabric.FabricPlot.highway_built(plot, set(owned)))))
    return items, built


def differences(kind, label, want, got):
    """One message per item of two aligned lists that differs (or a length mismatch)."""
    if len(want) != len(got):
        return [f"{kind} {label}: Python has {len(want)} values, Luau {len(got)}"]
    return [f"{kind} {label} #{index}: Python {a}, Luau {b}" for index, (a, b) in enumerate(zip(want, got), start=1) if a != b]


def unsettled(want, got):
    """`got` with a "?" wherever `want` has one: an item the mirror's answer does not settle."""
    if len(want) != len(got):
        return got
    return "".join("?" if a == "?" else b for a, b in zip(want, got))


def upgrade_differences(label, case, text):
    """The differences in one moment's upgrade layers: whether the highway stands, then each layer's
    entries, then each layer's count of placed entries."""
    kind = "HighwayBuilt, ValidUpgradeItem, UpgradeDeveloped"
    want, got = case["upgrades"], text.split()
    if len(want) != len(got):
        return differences(kind, label, want, got)
    found = differences(kind, label, want, [got[0]] + [unsettled(a, b) for a, b in zip(want[1:], got[1:])])
    for token, count in zip(got[1:], case["placed"]):
        name, _, chars = token.partition("=")
        if chars.count("1") != count:
            found.append(f"{kind} {label}: layer {name} places {count} entries in Python, {chars.count('1')} in Luau")
    return found


def variant_cases(city):
    """(tables, what Python answers, the variants the tools refuse) for HIGHWAY_VARIANTS, where both
    sides read one block, and HIGHWAY_RULED, where the mirror reads the block the ruling names."""
    variants = [(era_name, keys, keys, ramp, False) for era_name, keys, ramp in HIGHWAY_VARIANTS]
    variants += [(era_name, keys, ruled, True, True) for era_name, keys, ruled in HIGHWAY_RULED]
    tables, expected, refused = [], [], []
    for era_name, luau_keys, mirror_keys, ramp, ruled in variants:
        label = f"{era_name} with highway {json.dumps(luau_keys)}" + ("" if ramp else " and no ramp") + (f", ruled to be {json.dumps(mirror_keys)}" if ruled else "")
        mirror_city, luau_city = highway_variant(city, era_name, mirror_keys), highway_variant(city, era_name, luau_keys)
        if mirror_city is None:
            print(f"{label}: no `highway` block; skipped")
            continue
        with layout_ramp(ramp):
            try:
                streetplan.Era(era_name, mirror_city)
            except ValueError as refusal:
                refused.append(f"{label}: {refusal}")
                continue
            built = era_cases(era_name, mirror_city, label=label, history=False, luau_highway=luau_city["eras"][era_name]["highway"])
        if built is None:
            print(f"{label}: no fabric data or no valid `pull`; skipped")
            continue
        built[1]["ruled"] = ruled
        tables.append(built[0])
        expected.append(built[1])
    return tables, expected, refused


def run(eras, keep=None, strict=False, module=MODULE, tubes=TUBES):
    city = cityfabric.load_json(cityfabric.CITY_CONFIG_PATH)
    tables, expected = [], []
    for era_name in eras:
        built = era_cases(era_name, city)
        if built is None:
            print(f"{era_name}: no fabric data or no valid `pull`; skipped")
            continue
        tables.append(built[0])
        expected.append(built[1])
    real = len(tables)
    varied_tables, varied_expected, refused = variant_cases(city)
    tables += varied_tables
    expected += varied_expected
    # Tubes.luau: every era asked for that the city config dresses, when the file is there.
    tube_given, tube_want, tube_eras, tube_stale = [], [], 0, None
    if Path(tubes).exists():
        for era_name in eras:
            if isinstance(city.get("eras", {}).get(era_name), dict):
                given, want = tube_cases(era_name, city)
                tube_given.append(given)
                tube_want.append(want)
        tube_eras = len(tube_given)
        try:
            synthetic = tube_synthetic()
        except (AttributeError, KeyError, TypeError, ValueError) as changed:
            synthetic, tube_stale = [], f"{type(changed).__name__}: {changed}"
        tube_given += [given for given, _ in synthetic]
        tube_want += [want for _, want in synthetic]
    stage_vectors, rings = level_stage_vectors(), ring_vectors()
    site_vectors, valid_vectors, swap_vectors = look_vectors(city)
    clear_vectors, keep_vectors = band_vectors()
    wild_valid_vectors, wild_swap_vectors, wild_existing = wild_vectors(city)
    item_vectors, built_vectors = upgrade_vectors()
    lane_lots = [
        {"x": 0, "z": 0, "rotationY": 0, "size": size, "stretch": "L1_1", "along": 3, "row": 2, "front": 1, "lane": lane, "laneAlong": along}
        for size, lane, along in LANE_LOTS
    ]
    data = {
        "laneDogleg": LANE_DOGLEG,
        "laneLots": lane_lots,
        "laneCases": [{"levels": levels, "sizes": sizes, "budget": budget} for levels, sizes, budget in LANE_CASES],
        "eras": tables,
        "distancePoints": DISTANCE_POINTS,
        "distanceRects": DISTANCE_RECTS,
        "siteVectors": [vector for vector, _ in site_vectors],
        "swapLists": [vector for vector, _ in valid_vectors],
        "swapVectors": [vector for vector, _ in swap_vectors],
        "swapExisting": {name: True for name in SWAP_EXISTING},
        "levelStages": [vector for vector, _ in stage_vectors],
        "rings": [vector for vector, _ in rings],
        "ringClears": [vector for vector, _ in clear_vectors],
        "ringKeeps": [vector for vector, _ in keep_vectors],
        "bandPoints": [list(point) for point in BAND_POINTS],
        "wildLists": [vector for vector, _ in wild_valid_vectors],
        "wildVectors": [vector for vector, _ in wild_swap_vectors],
        "wildExisting": {name: True for name in sorted(wild_existing)},
        "upgradeItems": [vector for vector, _ in item_vectors],
        "builtVectors": [vector for vector, _ in built_vectors],
        "tubes": tube_given,
    }
    work = Path(keep) if keep else Path(tempfile.mkdtemp(prefix="check_mirror_"))
    work.mkdir(parents=True, exist_ok=True)
    try:
        shutil.copyfile(module, work / "CityFabric.luau")  # the game's own file, byte for byte
        if tube_given:
            shutil.copyfile(tubes, work / "Tubes.luau")  # and the client's, likewise
        (work / "cases.luau").write_text("return " + luau(data) + "\n", encoding="utf-8")
        (work / "run.luau").write_text(HARNESS, encoding="utf-8")
        result = subprocess.run([str(ensure_interpreter()), "run.luau"], cwd=work, capture_output=True, text=True)
    finally:
        if not keep:
            shutil.rmtree(work, ignore_errors=True)
    if result.returncode != 0:
        print(result.stdout[-2000:])
        print(result.stderr[-4000:], file=sys.stderr)
        print("check_mirror: the Luau run failed")
        return 1
    lines = {}
    for line in result.stdout.splitlines():
        head, _, rest = line.partition(" ")
        lines.setdefault(head, []).append(rest)
    exports = (lines.get("EXPORTS") or [""])[0].split()
    problems = []
    by_case = {
        kind: {tuple(int(v) for v in rest.split(" ", 2)[:2]): rest.split(" ", 2)[2] if rest.count(" ") >= 2 else "" for rest in lines.get(kind, [])}
        for kind in ("DEV", "LANE", "CLR", "LOOK", "KEPT", "WILD", "UPG")
    }
    by_era = {
        kind: {int(rest.split(" ", 1)[0]): rest.partition(" ")[2] for rest in lines.get(kind, [])}
        for kind in ("DIST", "TRIG", "ROUND", "GROUND", "BAND", "BPTS", "TCONF", "HUBS", "APRON")
    }
    runs = {kind: all(name in exports for name in names) for kind, names in REAL_GROUPS}
    variants = {"count": 0, "ruled": 0, "moments": 0, "round": 0, "banded": 0, "held": 0, "ground": 0, "found": 0}
    for e, (table, want) in enumerate(zip(tables, expected), start=1):
        found = []
        for c, case in enumerate(want["cases"], start=1):
            label = f"{table['name']} ({case['label']})"
            found += differences("Develop", label, case["states"], by_case["DEV"].get((e, c), "").split())
            found += differences("LaneReach", label, case["reaches"], by_case["LANE"].get((e, c), "").split())
            found += differences("IsCleared", label, list(case["cleared"]), list(by_case["CLR"].get((e, c), "")))
            if runs["LOOK"]:
                found += differences("SiteProp/SwappedProp", label, case["looks"], by_case["LOOK"].get((e, c), "").split())
            if runs["KEPT"]:
                found += differences("KeptInBand, IsCleared", label, list(case["kept"]), list(unsettled(case["kept"], by_case["KEPT"].get((e, c), ""))))
            if runs["WILD"]:
                found += differences("SwappedWild", label, case["wild"], by_case["WILD"].get((e, c), "").split())
            if runs["UPG"]:
                found += upgrade_differences(label, case, by_case["UPG"].get((e, c), ""))
        if runs["ROUND"]:
            found += differences("RoundLoop", table["name"], [want["round"]], [by_era["ROUND"].get(e, "")])
        if runs["KEPT"]:
            found += differences("RingBand", table["name"], [want["band"]], [by_era["BAND"].get(e, "")])
            found += differences("KeptInBand", f"{table['name']} (BAND_POINTS)", list(want["bandPoints"]), list(by_era["BPTS"].get(e, "")))
        if runs["GROUND"]:
            found += differences("RingGround", table["name"], want["ground"], by_era["GROUND"].get(e, "").split())
        # The distances, with the mirror on the Luau run's cos and sin (see "Sines and cosines").
        turns = luau_turns(table, by_era["TRIG"].get(e, ""))
        with trig_from(turns):
            distances = final_distances(table)
        apart = sum(1 for angle, pair in turns.items() if pair != (math.cos(angle), math.sin(angle)))
        found += differences("RectDistance/SegmentDistance", table["name"], distances, by_era["DIST"].get(e, "").split())
        problems += found
        if e > real:
            variants["count"] += 1
            variants["ruled"] += 1 if want["ruled"] else 0
            variants["moments"] += len(want["cases"])
            variants["round"] += 1 if want["round"] == truth(True) else 0
            variants["banded"] += 1 if want["band"] != "-" else 0
            variants["held"] += want["held"]
            variants["ground"] += 1 if want["ground"] else 0
            variants["found"] += len(found)
            continue
        print(
            f"{table['name']}: {len(want['cases'])} moments x {want['parcels']} parcels, {want['lanes']} lanes, "
            f"{want['points']} clearing points"
            + (f" ({want['banded']} in the band, held {want['held']} times against the mask)" if runs["KEPT"] and want["band"] != "-" else "")
            + f", {len(distances)} distances"
            + (f" (taken on Luau's cos and sin: the two C libraries differ in the last bit on {apart} of {len(turns)} rect turns)" if apart else "")
            + (f", {want['sites']} sites and {want['swapped']} swaps shown" if runs["LOOK"] else "")
            + (f", {want['wild']} wild placements ({want['wildSwapped']} swapped)" if runs["WILD"] else "")
            + (f", {want['placed']} upgrade entries placed ({want['onHighway']} on the highway)" if runs["UPG"] else "")
            + ": "
            + ("identical" if not found else f"{len(found)} DIFFERENCES")
        )
    if variants["count"]:
        print(
            f"highway variants: {variants['count']} `highway` blocks ({variants['ruled']} of them by the review's rulings), {variants['moments']} moments"
            + (
                f" ({variants['round']} round, {variants['ground']} with ring rects, {variants['banded']} with a band, held {variants['held']} times against the mask)"
                if runs["ROUND"] and runs["KEPT"] and runs["GROUND"]
                else ""
            )
            + ": "
            + ("identical" if not variants["found"] else f"{variants['found']} DIFFERENCES")
        )
    for message in refused:
        print(f"the tools refuse a highway variant, so it is not compared (HIGHWAY_VARIANTS needs a block they read): {message}")
    # Tubes.luau against tools/paths/tubes.py.
    tube_unchecked = [name for name in (lines.get("TEXPORTS") or [""])[0].split() if name not in TUBES_COMPARED]
    if tube_given:
        found = differences("Tubes.ENTRANCE", "", [streetplan.tubes_module().ENTRANCE], lines.get("TENTR") or [""])
        for t, (given, want) in enumerate(zip(tube_given, tube_want), start=1):
            found += tube_differences(given, want, by_era, t)
        hubs = sum(len(want["hubs"]) for want in tube_want[:tube_eras] if want["hubs"] is not None)
        tubed = [given["name"] for given, want in zip(tube_given[:tube_eras], tube_want) if want["hubs"] is not None]
        print(
            f"Tubes.luau: {tube_eras} eras' `road.paths`, {len(tubed)} tube era{'' if len(tubed) == 1 else 's'}"
            + (f" ({', '.join(tubed)}: {hubs} hubs and the entrance apron)" if tubed else "")
            + f", {len(tube_given) - tube_eras} synthetic cases: "
            + ("identical" if not found else f"{len(found)} DIFFERENCES")
        )
        problems += found
    else:
        print(f"Tubes.luau: {tubes} is not there or no era was asked for, so it is not compared")
    if tube_stale is not None:
        print(f"Tubes.luau: tools/paths/tubes.py no longer answers the stand-in plans of tube_synthetic ({tube_stale}), so the synthetic cases are not compared")
    want = [g17(cityfabric.lane_reach(LANE_DOGLEG, 1, lane_lots, levels, sizes, budget)) for levels, sizes, budget in LANE_CASES]
    got = [rest.split(" ", 1)[1] for rest in sorted(lines.get("LANEV", []), key=lambda rest: int(rest.split(" ", 1)[0]))]
    found = differences("LaneReach", "(synthetic dogleg)", want, got)
    print(f"LaneReach: {len(want)} synthetic vectors: " + ("identical" if not found else f"{len(found)} DIFFERENCES"))
    problems += found
    covered = {"Develop", "LaneReach", "IsCleared", "RectDistance", "SegmentDistance"}
    waiting = []
    for name, kind, vectors, needs in (
        ("LevelStage", "STAGE", stage_vectors, ()),
        ("RingRects", "RING", rings, ()),
        ("SiteProp", "SITE", site_vectors, ()),
        ("ValidSwaps", "VALID", valid_vectors, ()),
        ("SwappedProp", "SWAP", swap_vectors, ("ValidSwaps",)),
        ("RingClears", "RCLR", clear_vectors, ()),
        ("RingKeeps", "RKEEP", keep_vectors, ()),
        ("ValidWildSwaps", "WVALID", wild_valid_vectors, ()),
        ("SwappedWild", "WSWAP", wild_swap_vectors, ("ValidWildSwaps",)),
        ("ValidUpgradeItem", "UITEM", item_vectors, ()),
        ("HighwayBuilt", "HBUILT", built_vectors, ()),
    ):
        if name not in exports or any(need not in exports for need in needs):
            waiting.append(name)
            continue
        covered.add(name)
        got = {int(rest.split(" ", 1)[0]): (rest.split(" ", 1)[1] if " " in rest else "") for rest in lines.get(kind, [])}
        found = [
            f"{name}{json.dumps(vector)}: Python {want!r}, Luau {got.get(index, '(nothing)')!r}"
            for index, (vector, want) in enumerate(vectors, start=1)
            if got.get(index, "") != want
        ]
        print(f"{name}: {len(vectors)} vectors: " + ("identical" if not found else f"{len(found)} DIFFERENCES"))
        problems += found
    # The exports that only the real data (and the highway variants) compare.
    for kind, names in REAL_GROUPS:
        for name in names:
            if runs[kind]:
                covered.add(name)
            elif name not in exports and name not in waiting:
                waiting.append(name)
    unchecked = [name for name in exports if name not in covered]
    if waiting:
        print("not exported by CityFabric.luau yet, so not compared: " + ", ".join(waiting))
    if unchecked:
        print("exported by CityFabric.luau with no comparison here (add one): " + ", ".join(unchecked))
    if tube_unchecked:
        print("exported by Tubes.luau with no comparison here (add one): " + ", ".join(tube_unchecked))
    for message in problems[:SHOWN]:
        print(f"   DIFFERENCE: {message}")
    if len(problems) > SHOWN:
        print(f"   ... and {len(problems) - SHOWN} more")
    failed = bool(problems) or (strict and bool(waiting or unchecked or tube_unchecked or refused or tube_stale or not tube_given))
    print("check_mirror: " + ("FAILED" if failed else "Luau and Python agree"))
    return 1 if failed else 0


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("eras", nargs="*", default=list(DEFAULT_ERAS), help="era names (default: every fabric era)")
    parser.add_argument("--keep", help="write the generated Luau files to this folder and leave them there")
    parser.add_argument("--strict", action="store_true", help="also fail when a helper is missing on either side")
    parser.add_argument("--module", type=Path, default=MODULE, help="a CityFabric.luau to run instead of src/shared's (to prove the check bites)")
    parser.add_argument("--tubes", type=Path, default=TUBES, help="a Tubes.luau to run instead of src/client/City's (likewise)")
    args = parser.parse_args(argv)
    return run(args.eras, args.keep, args.strict, args.module, args.tubes)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
