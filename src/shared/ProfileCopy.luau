--!strict
-- The hub's copy of a combat profile for its Deltas (docs/prompts/l3-w1-fix-round.md R7). The client
-- merges a Delta's `combat` straight into its model, so the copy must share no table with the
-- server's profile, and it must carry EVERY field: C0's hand-written copy dropped the v7 maps, and
-- the hub's screen then lost what a player had found. So it copies the whole tree rather than a
-- list of fields, and a field a later schema adds rides along without an edit here; the harness
-- walks ProfileSchema's template against it. Pure: no Instance, no service.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

local ProfileCopy = {}

-- A profile is decoded DataStore data: a tree of tables, strings, numbers and booleans, never a
-- cycle, so a plain recursive copy is total.
local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, item in value do
		copy[key] = deepCopy(item)
	end
	return copy
end

-- A deep copy of `combat`, every table fresh. A saved loadout keeps the shape its type promises
-- (`variants` a table) even when a hand-edited profile lost it.
function ProfileCopy.Combat(combat: Types.CombatProfile): Types.CombatProfile
	local copy: Types.CombatProfile = deepCopy(combat)
	local loadout: any = copy.loadout
	if type(loadout) == "table" and type(loadout.variants) ~= "table" then
		loadout.variants = {}
	end
	return copy
end

return ProfileCopy
