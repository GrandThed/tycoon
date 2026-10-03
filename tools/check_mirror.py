#!/usr/bin/env python
"""Cross-check the Luau city fabric against its Python mirror on the real data.

`src/shared/CityFabric.luau` is pure, so the official `luau` interpreter can run the very file the
game runs. This gives both implementations the same inputs -- every fabric era's real layout, data
and config, at every purchase of the sim's greedy player, at the last moment of every tier and at
the finished plot -- and compares what they answer:

  * `Develop`: every parcel's level, district and governor;
  * `LaneReach`: every lane's reach, to the last bit;
  * `IsCleared`: every wild clearing point (each clump quarter, each single) against the moment's
    clearing mask (so `RectDistance` and `SegmentDistance` too, which are also compared number for
    number on the finished plot);
  * the looks (INTERFACES "Wave 3.2"): at every moment, the site every level-1 parcel shows
    (`SiteProp`) and the prop every building shows once the swaps have had their say (`ValidSwaps`,
    `SwappedProp`), from the era's real config; and all three on synthetic vectors, malformed
    configs included;
  * `LevelStage` and `RingRects` on synthetic vectors.

A Luau export this script has no comparison for, and a comparison whose Luau function does not exist
yet, are listed; with `--strict` either one fails the run. Any difference exits 1.

    py tools/check_mirror.py                # Village, Boomtown, Metropolis
    py tools/check_mirror.py Metropolis     # one era
    py tools/check_mirror.py --keep <dir>   # leave the generated Luau files there
    py tools/check_mirror.py --module <f>   # run another copy of the module (a deliberately broken one)

The interpreter comes from the same pinned release tools/check_compile.py takes luau-compile from,
downloaded into tools/bin/ (gitignored) on first use: Rokit installs neither here.
"""

from __future__ import annotations

import argparse
import io
import json
import math
import platform
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))

import check_compile  # noqa: E402
import cityfabric  # noqa: E402

MODULE = ROOT / "src" / "shared" / "CityFabric.luau"
DEFAULT_ERAS = ("Village", "Boomtown", "Metropolis")
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

HARNESS = r"""
local CityFabric = require("./CityFabric")
local data = require("./cases")

local function num(value)
	return string.format("%.17g", value)
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

for e, era in data.eras do
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
		-- Wave 3.2 looks: a level-1 parcel's site, and a building's prop after the swaps. The prop a
		-- building starts from is Fabric.luau's business (district lists, heights), so Python hands
		-- it over; the level and the district are this run's own.
		if siteProp ~= nil and validSwaps ~= nil and swappedProp ~= nil then
			local owned = {}
			for _, slot in case.owned do
				owned[slot] = true
			end
			local swaps = validSwaps(era.swaps)
			local function exists(name)
				return era.exists[name] == true
			end
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

if validSwaps ~= nil then
	for index, vector in data.swapLists do
		local ok, swaps = pcall(validSwaps, vector.swaps)
		if ok then
			local out = {}
			for _, swap in swaps do
				local names = {}
				if swap.districts ~= nil then
					for name in swap.districts do
						table.insert(names, name)
					end
					table.sort(names)
				end
				table.insert(out, string.format("%s|%s|%s", swap.requiresSlot, swap.suffix, if swap.districts ~= nil then table.concat(names, ",") else "*"))
			end
			print(string.format("VALID %d %s", index, table.concat(out, ";")))
		else
			print(string.format("VALID %d error:%s", index, tostring(swaps)))
		end
	end
end

if validSwaps ~= nil and swappedProp ~= nil then
	local function exists(name)
		return data.swapExisting[name] == true
	end
	for index, vector in data.swapVectors do
		local owned = {}
		for _, slot in vector.owned do
			owned[slot] = true
		end
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
				out[r] = string.format("%s,%s,%s,%s,%s,%s", num(rect.x), num(rect.z), num(rect.hx), num(rect.hz), num(rect.rotationY), num(rect.margin))
			end
			print(string.format("RING %d %s", index, table.concat(out, " ")))
		else
			print(string.format("RING %d error:%s", index, tostring(rects)))
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


def moments(plot, city):
    """(label, owned set, GrowthTier, each owned landmark's visible stage) for an era: after each
    slot the greedy player buys, at the last moment of each tier, and the finished plot."""
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
    everything = {slot["id"] for slot in plot.era.config["slots"] if slot["id"] in plot.layout["slots"]}
    out.append(("full build", everything, len(city["tier"]["thresholds"]), plot.final_stages(everything)))
    return out


def era_cases(era_name, city):
    """(the table handed to Luau, what Python answers) for one era, or None without fabric data."""
    plot = cityfabric.FabricPlot.load(era_name, city=city)
    if plot is None or plot.pull is None:
        return None
    points = []
    radii = plot.wild_config or {}
    for entry in plot.wild_data:
        if entry.get("kind") == cityfabric.CLUMP:
            points += [[quad[0], quad[1], radii.get("quarterRadius", 0)] for quad in entry.get("quads") or []]
        else:
            points.append([entry["x"], entry["z"], radii.get("singleRadius", 0)])
    cases, expected = [], []
    config = plot.config or {}
    swaps = cityfabric.valid_swaps(config.get("swaps"))
    asked = {}  # every name the swaps asked about -> whether it can spawn

    def exists(name):
        asked[name] = plot.heights.exists(name)
        return asked[name]

    for label, owned, tier, stages in moments(plot, city):
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
        cases.append({"tier": tier, "stretches": stretches, "landmarks": given["landmarks"], "mask": mask, "owned": sorted(owned), "base": base})
        expected.append(
            {
                "label": label,
                "states": [f"{g17(s['level'])}:{s['district'] or '-'}:{s['governor'] or '-'}" for s in states],
                "reaches": [g17(reach) for reach in reaches],
                "cleared": "".join("1" if cityfabric.is_cleared(p[0], p[1], p[2], mask) else "0" for p in points),
                "mask": mask,
                "looks": looks,
            }
        )
    distances = []
    if cases:
        mask = cases[-1]["mask"]
        for point in points[:DISTANCE_POINTS]:
            distances += [g17(cityfabric.rect_distance(point[0], point[1], rect)) for rect in mask["rects"][:DISTANCE_RECTS]]
            distances += [g17(cityfabric.segment_distance(point[0], point[1], seg)) for seg in mask["segments"][:DISTANCE_RECTS]]
    table = {
        "name": era_name,
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
        "exists": {name: True for name, can in asked.items() if can},
    }
    sites = sum(1 for case in expected for look in case["looks"] if look.startswith("S:"))
    swapped = sum(1 for case, given in zip(expected, cases) for index, look in enumerate(case["looks"], start=1) if look.startswith("B:") and look[2:] != given["base"].get(str(index)))
    return table, {
        "cases": expected,
        "distances": distances,
        "parcels": len(plot.parcel_data),
        "lanes": len(plot.lane_data),
        "points": len(points),
        "sites": sites,
        "swapped": swapped,
    }


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
        want = " ".join(",".join(g17(rect[key]) for key in ("x", "z", "hx", "hz", "rotationY", "margin")) for rect in rects)
        vectors.append(({"ring": ring, "tileStuds": tile, "ramp": ramp, "rampCells": cells}, want))
    return vectors


def differences(kind, label, want, got):
    """One message per item of two aligned lists that differs (or a length mismatch)."""
    if len(want) != len(got):
        return [f"{kind} {label}: Python has {len(want)} values, Luau {len(got)}"]
    return [f"{kind} {label} #{index}: Python {a}, Luau {b}" for index, (a, b) in enumerate(zip(want, got), start=1) if a != b]


def run(eras, keep=None, strict=False, module=MODULE):
    city = cityfabric.load_json(cityfabric.CITY_CONFIG_PATH)
    tables, expected = [], []
    for era_name in eras:
        built = era_cases(era_name, city)
        if built is None:
            print(f"{era_name}: no fabric data or no valid `pull`; skipped")
            continue
        tables.append(built[0])
        expected.append(built[1])
    stage_vectors, rings = level_stage_vectors(), ring_vectors()
    site_vectors, valid_vectors, swap_vectors = look_vectors(city)
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
    }
    work = Path(keep) if keep else Path(tempfile.mkdtemp(prefix="check_mirror_"))
    work.mkdir(parents=True, exist_ok=True)
    try:
        shutil.copyfile(module, work / "CityFabric.luau")  # the game's own file, byte for byte
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
    by_case = {kind: {tuple(int(v) for v in rest.split(" ", 2)[:2]): rest.split(" ", 2)[2] if rest.count(" ") >= 2 else "" for rest in lines.get(kind, [])} for kind in ("DEV", "LANE", "CLR", "LOOK")}
    looks_run = all(name in exports for name in ("SiteProp", "ValidSwaps", "SwappedProp"))
    for e, (table, want) in enumerate(zip(tables, expected), start=1):
        found = []
        for c, case in enumerate(want["cases"], start=1):
            label = f"{table['name']} ({case['label']})"
            found += differences("Develop", label, case["states"], by_case["DEV"].get((e, c), "").split())
            found += differences("LaneReach", label, case["reaches"], by_case["LANE"].get((e, c), "").split())
            found += differences("IsCleared", label, list(case["cleared"]), list(by_case["CLR"].get((e, c), "")))
            if looks_run:
                found += differences("SiteProp/SwappedProp", label, case["looks"], by_case["LOOK"].get((e, c), "").split())
        got = next((rest.split(" ", 1)[1].split() if " " in rest else [] for rest in lines.get("DIST", []) if rest.split(" ", 1)[0] == str(e)), [])
        found += differences("RectDistance/SegmentDistance", table["name"], want["distances"], got)
        print(
            f"{table['name']}: {len(want['cases'])} moments x {want['parcels']} parcels, {want['lanes']} lanes, "
            f"{want['points']} clearing points, {len(want['distances'])} distances"
            + (f", {want['sites']} sites and {want['swapped']} swaps shown" if looks_run else "")
            + ": "
            + ("identical" if not found else f"{len(found)} DIFFERENCES")
        )
        problems += found
    want = [g17(cityfabric.lane_reach(LANE_DOGLEG, 1, lane_lots, levels, sizes, budget)) for levels, sizes, budget in LANE_CASES]
    got = [rest.split(" ", 1)[1] for rest in sorted(lines.get("LANEV", []), key=lambda rest: int(rest.split(" ", 1)[0]))]
    found = differences("LaneReach", "(synthetic dogleg)", want, got)
    print(f"LaneReach: {len(want)} synthetic vectors: " + ("identical" if not found else f"{len(found)} DIFFERENCES"))
    problems += found
    covered = {"Develop", "LaneReach", "IsCleared", "RectDistance", "SegmentDistance"}
    waiting = []
    for name, kind, vectors in (
        ("LevelStage", "STAGE", stage_vectors),
        ("RingRects", "RING", rings),
        ("SiteProp", "SITE", site_vectors),
        ("ValidSwaps", "VALID", valid_vectors),
        ("SwappedProp", "SWAP", swap_vectors),
    ):
        if name not in exports or (name == "SwappedProp" and "ValidSwaps" not in exports):
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
    unchecked = [name for name in exports if name not in covered]
    if waiting:
        print("not exported by CityFabric.luau yet, so not compared: " + ", ".join(waiting))
    if unchecked:
        print("exported by CityFabric.luau with no comparison here (add one): " + ", ".join(unchecked))
    for message in problems[:SHOWN]:
        print(f"   DIFFERENCE: {message}")
    if len(problems) > SHOWN:
        print(f"   ... and {len(problems) - SHOWN} more")
    failed = bool(problems) or (strict and bool(waiting or unchecked))
    print("check_mirror: " + ("FAILED" if failed else "Luau and Python agree"))
    return 1 if failed else 0


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("eras", nargs="*", default=list(DEFAULT_ERAS), help="era names (default: every fabric era)")
    parser.add_argument("--keep", help="write the generated Luau files to this folder and leave them there")
    parser.add_argument("--strict", action="store_true", help="also fail when a helper is missing on either side")
    parser.add_argument("--module", type=Path, default=MODULE, help="a CityFabric.luau to run instead of src/shared's (to prove the check bites)")
    args = parser.parse_args(argv)
    return run(args.eras, args.keep, args.strict, args.module)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
