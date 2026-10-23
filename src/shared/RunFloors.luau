--!strict
-- L4B-8 (docs/prompts/l4-w1b-contract.md §5): a run's floors ride every RunState, at
-- remotes.combatStateHz per member, and a floor of a chase region carries the region's cells
-- (Forest Road's plateau: 12 rectangles on each of its 2 floors). A region never changes inside
-- one floor set, so the cells go to each member once per set: ArenaService sends them with a
-- member's first RunState of a `floorsSeq` (Attach), and the client keeps what it was sent until
-- the seq moves on (Merge).
--
-- Pure: tables only, no service, no Instance, no clock; the server's sends and the client's
-- RunState handler call the same two functions, and tools/crowd_harness loads this file as it
-- stands. Every list returned is new and so is every floor in it; a floor's `cells` list is the
-- one it was given, shared and read-only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))

local RunFloors = {}

-- A floor without its cells (every other field as it is).
local function bare(floor: Types.RunFloor): Types.RunFloor
	local copy = table.clone(floor)
	copy.cells = nil
	return copy
end

-- The floors to send to one member, and whether they carry their cells. `floors` are the run's
-- floors as WaveService holds them (cells and all), `seq` their floorsSeq, and `sentSeq` the seq
-- this member was last sent cells for (nil = never, as after Admit or Remove). The cells go when
-- `sentSeq` is not `seq`; the caller then records `seq` for the member. A floor with no cells
-- (an open camp outside any region, or the boss room) sends none either way.
function RunFloors.Attach(
	floors: { Types.RunFloor },
	seq: number,
	sentSeq: number?
): ({ Types.RunFloor }, boolean)
	local withCells = sentSeq ~= seq
	local out: { Types.RunFloor } = table.create(#floors)
	for index, floor in floors do
		out[index] = if withCells then table.clone(floor) else bare(floor)
	end
	return out, withCells
end

-- The floors the client keeps after a RunState: `incoming` with its `seq`, against what it held
-- (`held`, of `heldSeq`; nil = nothing yet). On the same seq a floor sent without cells keeps the
-- cells its held floor of the same index had (a region never changes inside a seq); on a new seq
-- every floor is taken as sent, so one with no cells is the rectangle alone. Cells that do arrive
-- are always taken.
function RunFloors.Merge(
	held: { Types.RunFloor },
	heldSeq: number?,
	incoming: { Types.RunFloor },
	seq: number
): { Types.RunFloor }
	local same = heldSeq == seq
	local out: { Types.RunFloor } = table.create(#incoming)
	for index, floor in incoming do
		local copy = table.clone(floor)
		if copy.cells == nil and same then
			local before = held[index]
			copy.cells = if before ~= nil then before.cells else nil
		end
		out[index] = copy
	end
	return out
end

return RunFloors
