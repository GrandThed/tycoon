--!strict
-- The Proving Grounds config with Studio overrides applied (docs/INTERFACES.md "P1 contracts" →
-- decision 3). The server owns the overrides (RequestTune) and broadcasts them on TuneState;
-- every client runs the same merge, so both sides always read the same numbers.
--
-- Every P1 system reads through Get() each time it needs a value, so a slider moves the game at
-- once. Get() is a cached merge, rebuilt only when the overrides change. The table it returns is
-- shared: callers read it and never write to it.

local HttpService = game:GetService("HttpService")

local Types = require(script.Parent:WaitForChild("Types"))
local Catalog = require(script.Parent:WaitForChild("Catalog"))

export type Connection = { Disconnect: (self: Connection) -> () }
export type Signal = { Connect: (self: Signal, callback: () -> ()) -> Connection }

-- Contract caps on a tuned value (the remote validator applies the same ones to the payload).
local MAX_PATH_LENGTH = 96
local MAX_STRING_LENGTH = 32
local INDENT = "\t"
-- Depth from the root at which an all-scalar object prints on one line (see isLeafTable).
local INLINE_OBJECT_DEPTH = 3

-- String leaves whose value picks a code path, keyed by a path pattern. A free-text value there
-- would reach a resolver that only knows a fixed set, so each rule names what is legal. Keys that
-- name other config entries are checked against the BASE config: tuning cannot add keys.
type EnumCheck = (value: string, path: string, base: Types.ProvingGroundsConfig) -> boolean
local function oneOf(values: { string }): EnumCheck
	return function(value: string): boolean
		return table.find(values, value) ~= nil
	end
end
-- loadout.<slot> must name a family whose base slot is that slot.
local function familyForSlot(value: string, path: string, base: Types.ProvingGroundsConfig): boolean
	local slot = string.match(path, "^loadout%.(%a+)$")
	local def = base.weapons[value]
	return def ~= nil and def.slot == slot
end
local SLOTS = { "melee", "ranged" }
-- A family's name, slot and era describe the roster, not a feel to try: tuning them would move a
-- family between slots under a live loadout, so they are not tunable at all. P3: an ability's id
-- picks its mechanic in AbilityService and its name labels it, and a held beam's `continuous`
-- decides how every client draws it, so those are roster too. L2-29: a family's element is a key
-- to the world (what it burns, which secrets it opens), so it is roster as well.
local STRUCTURAL_PATHS = {
	"^weapons%.[^.]+%.name$",
	"^weapons%.[^.]+%.slot$",
	"^weapons%.[^.]+%.era$",
	"^weapons%.[^.]+%.ability%.id$",
	"^weapons%.[^.]+%.ability%.name$",
	"^weapons%.[^.]+%.variants%.[^.]+%.continuous$",
	"^weapons%.[^.]+%.element$",
}
-- Ability fields that must stay positive: a repeat interval of 0 would fire a timeline's ticks
-- without end, and an ability shot at speed 0 could never leave the caster.
local POSITIVE_ABILITY_FIELDS = { "tickSeconds", "speed" }
-- Numbers that may reach 0 but never go below it: a negative burst would shrink the attack
-- credit under one shot and refuse every attack at its own rate. P4: a threat timer, a health
-- rate or an enemy attack's number below 0 means nothing, and the client times its tells from
-- the same values the server judges by, so the floor has to be the same on both sides.
local NON_NEGATIVE_PATHS = {
	"^shooting%.rateBurstShots$",
	"^crowd%.heavyHit$",
	"^crowd%.plateBreakSeconds$",
	"^crowd%.largeRadius$",
	"^crowd%.restDrop$",
	"^crowd%.riseBlendSeconds$",
	"^crowd%.threat%.[^.]+$",
	"^crowd%.kinds%.[^.]+%.attacks%.%d+%.[^.]+$",
	"^crowd%.kinds%.[^.]+%.bandMin$",
	"^crowd%.kinds%.[^.]+%.bandMax$",
	"^crowd%.kinds%.[^.]+%.perPlayer$",
	"^crowd%.kinds%.[^.]+%.enrage%.[^.]+$",
	"^crowd%.kinds%.[^.]+%.plate$",
	"^player%.[^.]+$",
}
local SPEED_SPAN_PATH = "shooting.originSpeedSeconds"
local ENUM_PATHS: { { pattern: string, check: EnumCheck } } = {
	{ pattern = "^weapons%.[^.]+%.variants%.[^.]+%.kind$", check = oneOf(SLOTS) },
	{
		pattern = "^weapons%.[^.]+%.variants%.[^.]+%.shape$",
		check = oneOf({ "arc", "sphere", "capsule", "cone", "ray" }),
	},
	{
		pattern = "^weapons%.[^.]+%.default$",
		check = function(value: string, path: string, base: Types.ProvingGroundsConfig): boolean
			local family = string.match(path, "^weapons%.([^.]+)%.default$")
			local def = if family ~= nil then base.weapons[family] else nil
			return def ~= nil and def.variants[value] ~= nil
		end,
	},
	-- L2-29: structural above, so never tuned; the set is named here too, so a rule that ever
	-- lets it through still holds it to the two words.
	{ pattern = "^weapons%.[^.]+%.element$", check = oneOf({ "fire", "ice" }) },
	{ pattern = "^loadout%.melee$", check = familyForSlot },
	{ pattern = "^loadout%.ranged$", check = familyForSlot },
	{
		pattern = "^dummySets%.[^.]+%.%d+%.kind$",
		check = function(value: string, _path: string, base: Types.ProvingGroundsConfig): boolean
			return base.crowd.kinds[value] ~= nil
		end,
	},
	{
		pattern = "^dummySets%.[^.]+%.%d+%.behaviour$",
		check = oneOf({ "idle", "walk", "strafe", "jump", "chase", "fight" }),
	},
	-- P4: what a fighting kind does and how each of its attacks resolves.
	{ pattern = "^crowd%.kinds%.[^.]+%.brain$", check = oneOf({ "rush", "keepAway" }) },
	{
		pattern = "^crowd%.kinds%.[^.]+%.enrage%.brain$",
		check = oneOf({ "rush", "keepAway" }),
	},
	{
		pattern = "^crowd%.kinds%.[^.]+%.attacks%.%d+%.shape$",
		check = oneOf({ "lunge", "arc", "lane", "line", "shot", "lob", "ring", "summon" }),
	},
	{
		-- Stop 2: what a `summon` attack raises must be a kind the base config knows.
		pattern = "^crowd%.kinds%.[^.]+%.attacks%.%d+%.summon$",
		check = function(value: string, _path: string, base: Types.ProvingGroundsConfig): boolean
			return base.crowd.kinds[value] ~= nil
		end,
	},
	{
		pattern = "^crowd%.kinds%.[^.]+%.attacks%.%d+%.interrupt$",
		check = oneOf({ "stagger", "heavy", "none" }),
	},
	{
		pattern = "^defaultSet$",
		check = function(value: string, _path: string, base: Types.ProvingGroundsConfig): boolean
			return base.dummySets[value] ~= nil
		end,
	},
	{ pattern = "^controls%.touchMode$", check = oneOf({ "autoFire", "tapFire" }) },
}

local Tuning = {}

local overrides: Types.TuneOverrides = {}
local merged: Types.ProvingGroundsConfig? = nil
local warnedMissing = false
local listeners: { () -> () } = {}

local function baseConfig(): Types.ProvingGroundsConfig?
	return Catalog.GetProvingGroundsConfig()
end

local function splitPath(path: string): { string }
	return string.split(path, ".")
end

-- One step down the config: a string key first, then an array index ("chain.3").
local function child(node: any, segment: string): (any, (string | number)?)
	if typeof(node) ~= "table" then
		return nil, nil
	end
	local byName = node[segment]
	if byName ~= nil then
		return byName, segment
	end
	local index = tonumber(segment)
	if index ~= nil and index == math.floor(index) and node[index] ~= nil then
		return node[index], index
	end
	return nil, nil
end

-- The leaf a path names in the BASE config, or nil when the path is not a scalar leaf there.
local function baseLeaf(path: string): any
	local base = baseConfig()
	if base == nil or path == "" or #path > MAX_PATH_LENGTH then
		return nil
	end
	local node: any = base
	for _, segment in splitPath(path) do
		node = child(node, segment)
		if node == nil then
			return nil
		end
	end
	if typeof(node) == "table" then
		return nil
	end
	return node
end

local function isFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

local function deepCopy(value: any): any
	if typeof(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, item in value do
		copy[key] = deepCopy(item)
	end
	return copy
end

local function writeLeaf(root: any, path: string, value: Types.TuneValue): ()
	local segments = splitPath(path)
	local node: any = root
	for index = 1, #segments - 1 do
		node = child(node, segments[index])
		if node == nil then
			return
		end
	end
	local _, key = child(node, segments[#segments])
	if key ~= nil then
		node[key] = value
	end
end

local function fireChanged(): ()
	for _, listener in table.clone(listeners) do
		task.spawn(listener)
	end
end

-- True when `value` may replace the base leaf at `path`: the path exists in the base config,
-- ends at a scalar, and the value keeps its type (finite numbers; enum strings stay in their
-- set; free strings stay short). That covers P3's nested ability blocks as they stand: every
-- numeric weapons.<family>.ability.<field> and every abilities.* leaf is tunable. P4's keys
-- tune the same way, an enemy attack's numbers by its 1-based place in the list
-- (crowd.kinds.<kind>.attacks.<n>.<field>). Only a field the base config writes can be tuned:
-- an optional one the kind leaves out (a fodder lunge's knockback) has no path.
function Tuning.Validate(path: string, value: any): boolean
	local current = baseLeaf(path)
	if current == nil or typeof(value) ~= typeof(current) then
		return false
	end
	for _, pattern in STRUCTURAL_PATHS do
		if string.match(path, pattern) ~= nil then
			return false
		end
	end
	if typeof(value) == "number" then
		if not isFinite(value) then
			return false
		end
		-- A charge weapon fires a real arrow; at speed 0 it would silently become hitscan.
		local family, key =
			string.match(path, "^weapons%.([^.]+)%.variants%.([^.]+)%.projectileSpeed$")
		if family ~= nil and key ~= nil and value <= 0 then
			local base = baseConfig()
			local def = if base ~= nil then base.weapons[family] else nil
			local variant = if def ~= nil then def.variants[key] else nil
			return variant == nil or variant.chargeSeconds == nil
		end
		local abilityField = string.match(path, "^weapons%.[^.]+%.ability%.([^.]+)$")
		if abilityField ~= nil and table.find(POSITIVE_ABILITY_FIELDS, abilityField) ~= nil then
			return value > 0
		end
		if path == SPEED_SPAN_PATH then
			-- P5 ruling 7: the stretch a player's own speed is averaged over, inside the window
			-- originLagMaxSeconds keeps. 0 would divide a single frame's step by nothing, and a
			-- span longer than the window has no samples to cover it.
			local base = baseConfig()
			return value > 0 and base ~= nil and value <= base.shooting.originLagMaxSeconds
		end
		for _, pattern in NON_NEGATIVE_PATHS do
			if string.match(path, pattern) ~= nil then
				return value >= 0
			end
		end
		return true
	end
	if typeof(value) == "string" then
		if #value > MAX_STRING_LENGTH then
			return false
		end
		local base = baseConfig()
		for _, rule in ENUM_PATHS do
			if string.match(path, rule.pattern) ~= nil then
				return base ~= nil and rule.check(value, path, base)
			end
		end
		return true
	end
	return true
end

-- The base value at a path (nil when the path is not a tunable leaf). Lets the server drop an
-- override that only restates the base.
function Tuning.BaseValue(path: string): Types.TuneValue?
	return baseLeaf(path)
end

-- False when Config/ProvingGrounds.json is absent: the range then never boots, and Get() hands
-- back an empty table rather than erroring.
function Tuning.IsAvailable(): boolean
	return baseConfig() ~= nil
end

function Tuning.Get(): Types.ProvingGroundsConfig
	local cached = merged
	if cached ~= nil then
		return cached
	end
	local base = baseConfig()
	if base == nil then
		if not warnedMissing then
			warnedMissing = true
			warn("[Tuning] Config/ProvingGrounds is missing; the Proving Grounds are unavailable")
		end
		return {} :: any
	end
	if next(overrides) == nil then
		merged = base
		return base
	end
	-- The base is Catalog's shared module table, so overrides always land on a copy.
	local copy = deepCopy(base)
	for path, value in overrides do
		writeLeaf(copy, path, value)
	end
	local result = copy :: Types.ProvingGroundsConfig
	merged = result
	return result
end

-- The fastest a character can legally move in the range: a walk, a dash or a slam's dive. A
-- position or a motion a client reports is trusted no further than this speed explains (P3.1's
-- claim slack; the lead of an enemy shot).
function Tuning.FastestMove(config: Types.ProvingGroundsConfig): number
	local movement = config.movement
	local dashSpeed = if movement.dashSeconds > 0
		then movement.dashDistance / movement.dashSeconds
		else 0
	return math.max(movement.walkSpeed, movement.slamFallSpeed, dashSpeed, 0)
end

-- How far the server's copy of a character trails that player's own screen: their ping plus a
-- fixed allowance, under a ceiling. P3.1 excuses a claimed attack origin by it, the commit rule
-- judges an enemy attack that long after its impact, and an enemy shot is led by it. `ping` is
-- Player:GetNetworkPing(), the client's word: the ceiling is what bounds it.
function Tuning.CommitLag(shooting: Types.RangeShootingConfig, ping: number): number
	-- A NaN ping fails every comparison, math.max included.
	local seen = if ping == ping then math.max(ping, 0) else 0
	return math.min(
		seen + math.max(shooting.originLagSeconds, 0),
		math.max(shooting.originLagMaxSeconds, 0)
	)
end

-- Replaces the whole override set. Entries that fail Validate are dropped silently, so a stale
-- or malformed TuneState can never corrupt the merge.
function Tuning.SetOverrides(o: Types.TuneOverrides): ()
	local accepted: Types.TuneOverrides = {}
	if typeof(o) == "table" then
		for path, value in o do
			if typeof(path) == "string" and Tuning.Validate(path, value) then
				accepted[path] = value
			end
		end
	end
	overrides = accepted
	merged = nil
	fireChanged()
end

-- A copy: callers build the next set from it without touching the live one.
function Tuning.GetOverrides(): Types.TuneOverrides
	return table.clone(overrides)
end

local changed = {}

function changed.Connect(_self: Signal, callback: () -> ()): Connection
	table.insert(listeners, callback)
	local connection = {}
	function connection.Disconnect(_connection: Connection): ()
		local index = table.find(listeners, callback)
		if index ~= nil then
			table.remove(listeners, index)
		end
	end
	return connection :: any
end

Tuning.Changed = (changed :: any) :: Signal

local function encodeScalar(value: any): string
	if typeof(value) == "string" then
		-- JSONEncode of a one-element array gives correct escaping; strip the brackets.
		local encoded = HttpService:JSONEncode({ value })
		return string.sub(encoded, 2, #encoded - 1)
	elseif typeof(value) == "number" then
		if value == math.floor(value) and math.abs(value) < 1e15 then
			return string.format("%d", value)
		end
		return tostring(value)
	elseif typeof(value) == "boolean" then
		return if value then "true" else "false"
	end
	return "null"
end

local function isArray(value: { [any]: any }): boolean
	local count = 0
	for _ in value do
		count += 1
	end
	return count == #value
end

local function sortedKeys(value: { [any]: any }): { string }
	local keys: { string } = {}
	for key in value do
		table.insert(keys, tostring(key))
	end
	table.sort(keys)
	return keys
end

-- A table of scalars (or of scalar arrays) is a candidate for one line. Arrays of scalars always
-- take it; objects only from INLINE_OBJECT_DEPTH down (variants, kinds, dummy groups), which is
-- the committed file's own layout, so a pasted export diffs cleanly against it.
local function isLeafTable(value: { [any]: any }): boolean
	for _, item in value do
		if typeof(item) == "table" then
			for _, inner in item do
				if typeof(inner) == "table" then
					return false
				end
			end
			if not isArray(item) then
				return false
			end
		end
	end
	return true
end

local function encode(value: any, depth: number): string
	if typeof(value) ~= "table" then
		return encodeScalar(value)
	end
	local tableValue = value :: { [any]: any }
	local array = isArray(tableValue)
	local inline = isLeafTable(tableValue) and (array or depth >= INLINE_OBJECT_DEPTH)
	local parts: { string } = {}
	if array then
		for _, item in tableValue do
			table.insert(parts, encode(item, depth + 1))
		end
		if #parts == 0 then
			return "[]"
		end
		if inline then
			return "[" .. table.concat(parts, ", ") .. "]"
		end
		local pad = string.rep(INDENT, depth + 1)
		return "[\n"
			.. pad
			.. table.concat(parts, ",\n" .. pad)
			.. "\n"
			.. string.rep(INDENT, depth)
			.. "]"
	end
	for _, key in sortedKeys(tableValue) do
		table.insert(parts, encodeScalar(key) .. ": " .. encode(tableValue[key], depth + 1))
	end
	if #parts == 0 then
		return "{}"
	end
	if inline then
		return "{ " .. table.concat(parts, ", ") .. " }"
	end
	local pad = string.rep(INDENT, depth + 1)
	return "{\n"
		.. pad
		.. table.concat(parts, ",\n" .. pad)
		.. "\n"
		.. string.rep(INDENT, depth)
		.. "}"
end

-- The merged config as pretty JSON ("Save winner"): keys sorted, leaf objects on one line.
function Tuning.Export(): string
	if not Tuning.IsAvailable() then
		return "{}"
	end
	return encode(Tuning.Get(), 0)
end

return Tuning
