--!strict
-- What a tube era adds to a path era (docs/INTERFACES.md "Wave 4.1b — organic Orbital", "Wave 4.2
-- — Orbital in the game"): where the hubs stand and where the entrance apron lies. Both are
-- copies of tools/paths/tubes.py (`TubePlan.hubs`, `TubePlan.entrance_apron`), which laid the
-- approved renders out, so a rule changed there changes here and nowhere else.
--
-- A tube era is a path era whose `road.paths` carries a `tube` block. Its streets are the pieces
-- RoadGraph already asks the baked-path renderer for by id, only swept as half-pipes; this module
-- holds the two things that are not a piece of the street network. Pure: numbers, strings and
-- tables only, with no Roblox globals or services, so the same file runs under a plain Luau
-- interpreter against the Python it copies.

-- `road.paths.tube` as the client reads it: the prop that stands on every hub node. `front` (the
-- studs from a tube's centreline to a lot's front) is the tools' alone.
export type Config = { hub: string? }

-- A network node a hub stands on and the stretches that meet there. `why` is tubes.py's word for
-- it, kept so a hub printed in Studio can be matched against `tubes.py --list`.
export type HubNode = { node: number, stretches: { number }, why: string }

-- The entrance apron's centreline, front edge first; it is `road.paths.spurWidth` wide.
export type Apron = { ax: number, az: number, bx: number, bz: number }

-- tubes.py's ENTRANCE: the apron's id after the spur prefix, so its piece is `SP_entrance`. A slot
-- of that name would share the id, and the layout then has no apron (the tool refuses it).
local ENTRANCE = "entrance"
-- tools/streetplan.py's MIN_LENGTH: a first tube that starts this close to the plot's front edge
-- leaves no apron to lay.
local MIN_LENGTH = 0.05
local WHY_END = "end"
local WHY_BRANCH = "branch"
local WHY_JOINT = "joint"

local Tubes = {}

Tubes.ENTRANCE = ENTRANCE

-- Nil in an era whose paths are flat ribbons (no `tube` block, or one that is not a table). A hub
-- name that is not a string reads as no hub: the tubes are still tubes.
function Tubes.Config(paths: any): Config?
	local tube = if type(paths) == "table" then paths.tube else nil
	if type(tube) ~= "table" then
		return nil
	end
	local hub = tube.hub
	return { hub = if type(hub) == "string" and hub ~= "" then hub else nil }
end

-- Every node a hub stands on, in node order: a tube ends there (one stretch), tubes branch there
-- (three or more), or two chains meet there end to end -- anywhere two pipes would otherwise meet
-- at an angle or stop in the open for good. `nodeStretches[node]` lists every stretch of the
-- network at that node, drawn or not, and `chainOf` names the chain a stretch is swept along (its
-- polyline, or the connector it is): two stretches of one chain butt on one cross-section and need
-- no hub.
function Tubes.HubNodes(
	nodeStretches: { { number } },
	chainOf: (stretch: number) -> string
): { HubNode }
	local found: { HubNode } = {}
	for node = 1, #nodeStretches do
		local stretches = nodeStretches[node]
		local count = #stretches
		local why: string? = nil
		if count == 1 then
			why = WHY_END
		elseif count >= 3 then
			why = WHY_BRANCH
		elseif count == 2 and chainOf(stretches[1]) ~= chainOf(stretches[2]) then
			why = WHY_JOINT
		end
		if why ~= nil then
			table.insert(found, { node = node, stretches = table.clone(stretches), why = why })
		end
	end
	return found
end

-- The entrance apron: flat decking straight in from the plot's front edge to the first point of
-- street 1 (`firstX`, `firstZ`), where the entrance hub stands. It belongs to no slot and is laid
-- from the start: the world's road ends at the plot's front face, and the first tube starts
-- further in. Nil when that tube starts on the front edge, when the numbers are not numbers, and
-- when a slot is named like the apron. `plotDepth` is the plot's size along Z.
function Tubes.EntranceApron(
	firstX: number,
	firstZ: number,
	plotDepth: number,
	entranceSlot: boolean
): Apron?
	if
		entranceSlot
		or firstX ~= firstX
		or firstZ ~= firstZ
		or plotDepth ~= plotDepth
		or plotDepth <= 0
	then
		return nil
	end
	local front = -plotDepth / 2
	if firstZ - front < MIN_LENGTH then
		return nil
	end
	return { ax = firstX, az = front, bx = firstX, bz = firstZ }
end

return Tubes
