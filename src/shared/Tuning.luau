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

-- String leaves whose value picks a code path. A free-text value there would reach a resolver
-- that only knows these, so they are the only strings accepted.
local ENUM_VALUES: { [string]: { string } } = {
	shape = { "arc", "sphere", "capsule", "cone", "ray" },
	kind = { "melee", "ranged" },
	touchMode = { "autoFire", "tapFire" },
	behaviour = { "idle", "walk", "strafe", "jump", "chase" },
}

local overrides: Types.TuneOverrides = {}
local merged: Types.ProvingGroundsConfig? = nil
local warnedMissing = false
local listeners: { () -> () } = {}

local Tuning = {}

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
-- set; free strings stay short).
function Tuning.Validate(path: string, value: any): boolean
	local current = baseLeaf(path)
	if current == nil or typeof(value) ~= typeof(current) then
		return false
	end
	if typeof(value) == "number" then
		return isFinite(value)
	end
	if typeof(value) == "string" then
		if #value > MAX_STRING_LENGTH then
			return false
		end
		local segments = splitPath(path)
		local allowed = ENUM_VALUES[segments[#segments]]
		return allowed == nil or table.find(allowed, value) ~= nil
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
