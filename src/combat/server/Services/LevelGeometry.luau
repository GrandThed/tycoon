--!strict
-- The arithmetic of a level's grey blocks (docs/INTERFACES.md "L1 contracts" → "Server modules"
-- → "A — the world", rulings 27, 29 and 31; "L1b contracts" → "LevelGeometry"): where a camp's
-- floor, fence, gates, invisible wall and fire markers stand (gates and the wall only for the
-- camp that locks, L1b-12), how deep the ground is built, what a layout's bounds are, the adapter that reads
-- the C1 Village arena as a level of one camp, and the whole list of Parts a layout becomes.
-- LevelService turns that list into Instances and does no arithmetic of its own.
--
-- Pure: tables and numbers only. No Vector3, no Instance, no clock and nothing yields; the one
-- require is Types, for the layout shapes. tools/crowd_harness loads this file as it stands
-- (tests_l1_world.luau), because a rule no test can load is only ever checked by reading.
--
-- Conventions. A layout is in world coordinates, in studs. A Box is a centre and a size and is
-- always axis-aligned. A camp's x, y, z is the centre of its floor's TOP face. North is -Z,
-- south +Z, west -X, east +X. A side's own coordinate runs along X for north and south and
-- along Z for west and east, measured from the middle of that side.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

export type Box = { x: number, y: number, z: number, sx: number, sy: number, sz: number }
export type Bounds = {
	minX: number,
	minY: number,
	minZ: number,
	maxX: number,
	maxY: number,
	maxZ: number,
}
export type Size = { sx: number, sy: number, sz: number }
-- What a layout does not say and the config does: the fence's thickness and how deep the ground
-- is (Combat.json levels.fenceThickness, levels.floorThickness), and how big a checkpoint
-- marker, a fire spot's marker and a secret's sign are (Combat.json levels.checkpointSize,
-- levels.fireMarkerSize, Expeditions.json sign.size). A size the config does not give is nil,
-- and what it sizes is then not built: no size lives in code. Without `floor` a layout with a
-- camp is refused (a camp has no floor) and every block is built as the layout writes it.
export type Sizes = { fence: number, floor: number?, checkpoint: Size?, fire: Size?, sign: Size? }
-- One Part to build. `look` names a key of Expeditions.json `looks` (nil = no look at all: the
-- invisible wall); `material` and `color` are the piece's own and win over the look's.
export type Piece = {
	name: string,
	-- "block" | "floor" | "fence" | "gate" | "obstacle" | "checkpoint" | "fire" | "barrier" |
	-- "secret" | "sign"
	role: string,
	box: Box,
	look: string?,
	material: string?,
	color: { number }?,
	-- The camp a floor, fence, gate, obstacle, checkpoint, fire or barrier belongs to.
	camp: string?,
	-- false = nothing collides with it, touches it or is stopped by it in a ray.
	collide: boolean,
	text: string?,
}

-- The id of the one camp an arena becomes (ruling 27; StageFlow.Resolve names the same zone).
local ARENA_CAMP_ID = "arena"
-- Two edges closer than this are one edge: layouts are written in halves and quarters of a stud.
local SEAM = 1e-6
-- The looks of the blocks a body lands on (tools/check_levels.py GROUND_LOOKS names the same
-- four). A block of any other look is a wall, a sign or a marker.
local GROUND_LOOKS: { [string]: boolean } = {
	ground = true,
	path = true,
	lobby = true,
	water = true,
}

type Side = { alongX: boolean, sign: number }
local SIDES: { [string]: Side } = {
	north = { alongX = true, sign = -1 },
	south = { alongX = true, sign = 1 },
	west = { alongX = false, sign = -1 },
	east = { alongX = false, sign = 1 },
}
-- The order boxes are returned in: the C1 arena's (its Fence1..4 and Barrier1..4).
local SIDE_ORDER = { "north", "south", "west", "east" }

local LevelGeometry = {}

-- A layout decoded from JSON may leave a list out; an absent list is an empty one.
local function listOf<T>(list: { T }?): { T }
	return list or {}
end

-- NaN fails the first comparison.
local function isFinite(value: number): boolean
	return value == value and math.abs(value) < math.huge
end

local function isSound(box: Box): boolean
	return isFinite(box.x)
		and isFinite(box.y)
		and isFinite(box.z)
		and isFinite(box.sx)
		and isFinite(box.sy)
		and isFinite(box.sz)
		and box.sx > 0
		and box.sy > 0
		and box.sz > 0
end

-- A depth the config gave: a positive number. nil for anything else, a NaN included.
local function depthOf(value: number?): number?
	if value ~= nil and value > 0 and isFinite(value) then
		return value
	end
	return nil
end

-- Whether the boxes of `under` hold up the whole of `box`, seen from above: its footprint is
-- cut along every edge of theirs that crosses it, and each cell must lie in one of them. A
-- block that only rests on something at one end hangs over the void for the rest.
local function heldUp(box: Box, under: { Box }): boolean
	local xs = { box.x - box.sx / 2, box.x + box.sx / 2 }
	local zs = { box.z - box.sz / 2, box.z + box.sz / 2 }
	for _, other in under do
		for _, way in { -1, 1 } do
			local x = other.x + way * other.sx / 2
			if x > xs[1] and x < xs[2] then
				table.insert(xs, x)
			end
			local z = other.z + way * other.sz / 2
			if z > zs[1] and z < zs[2] then
				table.insert(zs, z)
			end
		end
	end
	table.sort(xs)
	table.sort(zs)
	for i = 1, #xs - 1 do
		for j = 1, #zs - 1 do
			-- A cell with no width is a seam between two edges, not ground.
			if xs[i + 1] - xs[i] > SEAM and zs[j + 1] - zs[j] > SEAM then
				local x = (xs[i] + xs[i + 1]) / 2
				local z = (zs[j] + zs[j + 1]) / 2
				local held = false
				for _, other in under do
					local dx = math.abs(x - other.x)
					local dz = math.abs(z - other.z)
					if dx < other.sx / 2 and dz < other.sz / 2 then
						held = true
						break
					end
				end
				if not held then
					return false
				end
			end
		end
	end
	return true
end

-- Half the floor's length along `side`.
local function halfRun(camp: Types.LevelCamp, side: Side): number
	return (if side.alongX then camp.sx else camp.sz) / 2
end

-- A stretch [from, to] of `side`'s fence line, `height` tall from the floor's top, `thickness`
-- deep outward from the floor's edge.
local function sideBox(
	camp: Types.LevelCamp,
	side: Side,
	from: number,
	to: number,
	thickness: number,
	height: number
): Box
	local middle = (from + to) / 2
	local length = to - from
	local y = camp.y + height / 2
	if side.alongX then
		return {
			x = camp.x + middle,
			y = y,
			z = camp.z + side.sign * (camp.sz / 2 + thickness / 2),
			sx = length,
			sy = height,
			sz = thickness,
		}
	end
	return {
		x = camp.x + side.sign * (camp.sx / 2 + thickness / 2),
		y = y,
		z = camp.z + middle,
		sx = thickness,
		sy = height,
		sz = length,
	}
end

-- The stretch of its side a gate opens, held inside the floor's own edge so a corner always
-- keeps its post. nil for an unknown side, or a gate with no width left on the side.
local function gateSpan(camp: Types.LevelCamp, gate: Types.LevelGate): (Side?, number, number)
	local side = SIDES[gate.side]
	if side == nil then
		return nil, 0, 0
	end
	local half = halfRun(camp, side)
	-- Not math.clamp: it throws when rounding leaves its minimum above its maximum.
	local from = math.max(gate.at - gate.width / 2, -half)
	local to = math.min(gate.at + gate.width / 2, half)
	-- Written so that a NaN, which fails every comparison, is no gate.
	if not (to > from) then
		return nil, 0, 0
	end
	return side, from, to
end

local function fenceHeight(camp: Types.LevelCamp): number
	local fence = camp.fence
	if fence == nil or not (fence.height > 0) then
		return 0
	end
	return fence.height
end

-- The floor: its top face at camp.y, `depth` deep under it (Combat.json levels.floorThickness).
-- It is deep because it stands over the void: a body the rescue puts back on it still has the
-- speed of its fall, and passes through a slab of one stud.
function LevelGeometry.FloorBox(camp: Types.LevelCamp, depth: number): Box
	return {
		x = camp.x,
		y = camp.y - depth / 2,
		z = camp.z,
		sx = camp.sx,
		sy = depth,
		sz = camp.sz,
	}
end

-- The visible fence, cut at the gates: per side (north, south, west, east) the stretches no gate
-- opens, in order along the side. It stands outside the floor's edge; the north and south sides
-- run past the west and east ones by the thickness, so the corners close. Empty without a
-- fence. With no gate it is the C1 arena's four boxes.
function LevelGeometry.FenceBoxes(camp: Types.LevelCamp, thickness: number): { Box }
	local boxes: { Box } = {}
	local height = fenceHeight(camp)
	if height <= 0 or not (thickness > 0) then
		return boxes
	end
	for _, name in SIDE_ORDER do
		local side = SIDES[name]
		local half = halfRun(camp, side)
		local reach = if side.alongX then half + thickness else half
		local cuts: { { number } } = {}
		for _, gate in listOf(camp.gates) do
			if gate.side == name then
				local known, from, to = gateSpan(camp, gate)
				if known ~= nil then
					table.insert(cuts, { from, to })
				end
			end
		end
		table.sort(cuts, function(a: { number }, b: { number }): boolean
			return a[1] < b[1]
		end)
		-- Walks the side once: fence from `standing` to each cut, then on from where it ends.
		local standing = -reach
		for _, cut in cuts do
			if cut[1] > standing then
				table.insert(boxes, sideBox(camp, side, standing, cut[1], thickness, height))
			end
			standing = math.max(standing, cut[2])
		end
		if reach > standing then
			table.insert(boxes, sideBox(camp, side, standing, reach, thickness, height))
		end
	end
	return boxes
end

-- One box per gate, in the camp's own gate order (entry first), filling exactly the stretch
-- FenceBoxes leaves open for it. A gate FenceBoxes ignores (unknown side, no width) has none.
-- Empty without a fence: a gate is a piece of it.
function LevelGeometry.GateBoxes(camp: Types.LevelCamp, thickness: number): { Box }
	local boxes: { Box } = {}
	local height = fenceHeight(camp)
	if height <= 0 or not (thickness > 0) then
		return boxes
	end
	for _, gate in listOf(camp.gates) do
		local side, from, to = gateSpan(camp, gate)
		if side ~= nil then
			table.insert(boxes, sideBox(camp, side, from, to, thickness, height))
		end
	end
	return boxes
end

-- The invisible wall: four boxes (north, south, west, east) from the floor's top up to
-- barrier.height, each with its inner face on the FLOOR'S EDGE and barrier.thickness deep
-- outward from there. The fence and the gates stand inside it, so in a closed camp nobody stands
-- on a fence or in a gate gap, whatever the fence's height: a fence top is a perch the crowd
-- cannot reach. It is never thinner than the fence (it must hold the whole fence line, and a
-- dash covers over 2 studs a frame and steps through a thin wall). The north and south boxes
-- run past the west and east ones, so the corners close. A camp with no fence has the same
-- wall, and it runs across the gates: closed, it is what holds a body in.
function LevelGeometry.BarrierBoxes(
	camp: Types.LevelCamp,
	thickness: number,
	barrier: Types.LevelBarrier
): { Box }
	local boxes: { Box } = {}
	local height = barrier.height
	local depth = math.max(barrier.thickness, thickness, 0)
	if not (height > 0) or not (depth > 0) then
		return boxes
	end
	local edgeX = camp.sx / 2
	local edgeZ = camp.sz / 2
	local y = camp.y + height / 2
	for _, name in SIDE_ORDER do
		local side = SIDES[name]
		if side.alongX then
			table.insert(boxes, {
				x = camp.x,
				y = y,
				z = camp.z + side.sign * (edgeZ + depth / 2),
				sx = (edgeX + depth) * 2,
				sy = height,
				sz = depth,
			})
		else
			table.insert(boxes, {
				x = camp.x + side.sign * (edgeX + depth / 2),
				y = y,
				z = camp.z,
				sx = depth,
				sy = height,
				sz = edgeZ * 2,
			})
		end
	end
	return boxes
end

-- A camp's cover, standing on its floor.
function LevelGeometry.ObstacleBoxes(camp: Types.LevelCamp): { Box }
	local boxes: { Box } = {}
	local obstacles: { Types.ArenaObstacle } = listOf(camp.obstacles)
	for _, obstacle in obstacles do
		table.insert(boxes, {
			x = obstacle.x,
			y = camp.y + obstacle.sy / 2,
			z = obstacle.z,
			sx = obstacle.sx,
			sy = obstacle.sy,
			sz = obstacle.sz,
		})
	end
	return boxes
end

-- The checkpoint marker, standing on the floor at camp.checkpoint; nil for a camp with none.
function LevelGeometry.CheckpointBox(camp: Types.LevelCamp, size: Size): Box?
	local point = camp.checkpoint
	if point == nil then
		return nil
	end
	return {
		x = point.x,
		y = camp.y + size.sy / 2,
		z = point.z,
		sx = size.sx,
		sy = size.sy,
		sz = size.sz,
	}
end

-- A fire spot's marker (L1b: so a group's place shows in grey box): centred on the fire's
-- point, its bottom on the floor's top. nil for a spot that is no fire or has no point.
function LevelGeometry.FireBox(camp: Types.LevelCamp, spot: Types.LevelSpot, size: Size): Box?
	local centre = if spot.posture == "fire" and spot.points ~= nil then spot.points[1] else nil
	if centre == nil then
		return nil
	end
	return {
		x = centre.x,
		y = camp.y + size.sy / 2,
		z = centre.z,
		sx = size.sx,
		sy = size.sy,
		sz = size.sz,
	}
end

function LevelGeometry.SecretBox(secret: Types.LevelSecret): Box
	return {
		x = secret.x,
		y = secret.y,
		z = secret.z,
		sx = secret.sx,
		sy = secret.sy,
		sz = secret.sz,
	}
end

-- A secret's sign: the layout gives the point it stands on, so the box rises from there.
function LevelGeometry.SignBox(secret: Types.LevelSecret, size: Size): Box
	local sign = secret.sign
	return {
		x = sign.x,
		y = sign.y + size.sy / 2,
		z = sign.z,
		sx = size.sx,
		sy = size.sy,
		sz = size.sz,
	}
end

-- A layout's blocks as they are built, in the layout's order. Ground that hangs over the void
-- is as deep as a camp's floor, for the same reason: a solid block of a ground look that is
-- thinner than `floorThickness` is made that deep downward, its top where the layout puts it,
-- unless it rests on something: the other solid blocks, the camp floors and the secrets that
-- lie right under it, reach lower than it does, and between them hold all of it up. Every other
-- block is the box the layout writes: a wall or a sign, one marked `collide = false`, one deep
-- enough already, and one whose size is not sound (Pieces refuses that one by name). What a
-- block rests on is read from the layout as written, so the answer does not turn on the
-- blocks' order. Without a thickness nothing is changed. tools/check_levels.py holds every
-- layout that ships to the same rule, so there this changes no block: it is the net under a
-- layout that has not been through that gate.
function LevelGeometry.BlockBoxes(layout: Types.LevelLayout, floorThickness: number?): { Box }
	local depth = depthOf(floorThickness)
	local blocks = listOf(layout.blocks)
	local written: { Box } = {}
	for _, block in blocks do
		table.insert(written, {
			x = block.x,
			y = block.y,
			z = block.z,
			sx = block.sx,
			sy = block.sy,
			sz = block.sz,
		})
	end
	if depth == nil then
		return written
	end
	-- Everything solid a block could rest on.
	local solids: { Box } = {}
	for index, block in blocks do
		if block.collide ~= false and isSound(written[index]) then
			table.insert(solids, written[index])
		end
	end
	for _, camp in listOf(layout.camps) do
		table.insert(solids, LevelGeometry.FloorBox(camp, depth))
	end
	for _, secret in listOf(layout.secrets) do
		table.insert(solids, LevelGeometry.SecretBox(secret))
	end
	local boxes: { Box } = {}
	for index, block in blocks do
		local box = written[index]
		local ground = GROUND_LOOKS[block.look] == true and block.collide ~= false
		if ground and isSound(box) and box.sy < depth then
			-- Under it: what reaches up to its underside and lower than it. (Never the block
			-- itself, nor one beside or round it at its own depth: the void is under both. Nor
			-- one further down with air between: a body still passes through the thin block.)
			local bottom = box.y - box.sy / 2
			local under: { Box } = {}
			for _, other in solids do
				local reaches = other.y + other.sy / 2 >= bottom - SEAM
				if reaches and other.y - other.sy / 2 < bottom - SEAM then
					table.insert(under, other)
				end
			end
			if not heldUp(box, under) then
				box = {
					x = box.x,
					y = box.y + box.sy / 2 - depth / 2,
					z = box.z,
					sx = box.sx,
					sy = depth,
					sz = box.sz,
				}
			end
		end
		table.insert(boxes, box)
	end
	return boxes
end

local function widen(bounds: Bounds?, box: Box): Bounds
	local minX = box.x - box.sx / 2
	local maxX = box.x + box.sx / 2
	local minY = box.y - box.sy / 2
	local maxY = box.y + box.sy / 2
	local minZ = box.z - box.sz / 2
	local maxZ = box.z + box.sz / 2
	if bounds == nil then
		return { minX = minX, minY = minY, minZ = minZ, maxX = maxX, maxY = maxY, maxZ = maxZ }
	end
	bounds.minX = math.min(bounds.minX, minX)
	bounds.minY = math.min(bounds.minY, minY)
	bounds.minZ = math.min(bounds.minZ, minZ)
	bounds.maxX = math.max(bounds.maxX, maxX)
	bounds.maxY = math.max(bounds.maxY, maxY)
	bounds.maxZ = math.max(bounds.maxZ, maxZ)
	return bounds
end

-- The box that holds a layout as it is built: every block (BlockBoxes), every camp (its floor,
-- its fence's height, its cover) and every secret. `floorThickness` is Combat.json
-- levels.floorThickness: without it a camp's floor counts as its top face and a block as the
-- layout writes it, and what is built reaches further down than this box. It takes no fence
-- thickness either, so in X and Z a camp counts as its floor; the callers add a margin of tens
-- of studs. A layout with nothing in it is its start.
function LevelGeometry.Bounds(layout: Types.LevelLayout, floorThickness: number?): Bounds
	local depth = depthOf(floorThickness)
	local bounds: Bounds? = nil
	for _, box in LevelGeometry.BlockBoxes(layout, depth) do
		bounds = widen(bounds, box)
	end
	for _, camp in listOf(layout.camps) do
		bounds = widen(bounds, LevelGeometry.FloorBox(camp, depth or 0))
		local height = fenceHeight(camp)
		if height > 0 then
			bounds = widen(bounds, {
				x = camp.x,
				y = camp.y + height / 2,
				z = camp.z,
				sx = camp.sx,
				sy = height,
				sz = camp.sz,
			})
		end
		for _, box in LevelGeometry.ObstacleBoxes(camp) do
			bounds = widen(bounds, box)
		end
	end
	for _, secret in listOf(layout.secrets) do
		bounds = widen(bounds, LevelGeometry.SecretBox(secret))
	end
	if bounds ~= nil then
		return bounds
	end
	local start = layout.start
	return {
		minX = start.x,
		minY = start.y,
		minZ = start.z,
		maxX = start.x,
		maxY = start.y,
		maxZ = start.z,
	}
end

-- Ruling 27: the C1 arena read as a level. One camp, "arena", that locks (L1b-12), whose floor
-- top is the world origin: the arena's size, floor, fence and cover; no gates; the party enters
-- at the first
-- player spawn (else the pad) and leaves and starts at the pad; the crowd arrives at the
-- arena's enemy spawns. The invisible wall is the arena's (none without barrierHeight; a
-- thickness of 0 means the fence's). Every table is new: the arena's own is a shared module.
function LevelGeometry.FromArena(arena: Types.ArenaLayout, killY: number): Types.LevelLayout
	local pad = arena.lobbyPad
	local first = listOf(arena.playerSpawns)[1] or pad
	local spawns: { Types.ArenaPoint } = {}
	for _, point in listOf(arena.enemySpawns) do
		table.insert(spawns, { x = point.x, z = point.z })
	end
	local obstacles: { Types.ArenaObstacle } = {}
	for _, obstacle in listOf(arena.obstacles) do
		table.insert(obstacles, table.clone(obstacle))
	end
	local wall = arena.wall
	local barrier: Types.LevelBarrier? = nil
	if wall ~= nil and wall.barrierHeight ~= nil and wall.barrierHeight > 0 then
		barrier = { height = wall.barrierHeight, thickness = wall.barrierThickness or 0 }
	end
	local camp: Types.LevelCamp = {
		id = ARENA_CAMP_ID,
		x = 0,
		y = 0,
		z = 0,
		sx = arena.size.x,
		sz = arena.size.z,
		floor = { material = arena.floor.material, color = table.clone(arena.floor.color) },
		fence = if wall ~= nil
			then { height = wall.height, material = wall.material, color = table.clone(wall.color) }
			else nil,
		gates = {},
		entry = { x = first.x, z = first.z },
		exit = { x = pad.x, z = pad.z },
		checkpoint = nil,
		spawns = spawns,
		obstacles = obstacles,
		locks = true,
		spots = nil,
	}
	return {
		version = 1,
		arena = nil,
		start = { x = pad.x, y = 0, z = pad.z },
		spawns = nil,
		killY = killY,
		barrier = barrier,
		camps = { camp },
		blocks = {},
		secrets = {},
		route = {},
	}
end

-- The stand-in lobby, built when Layouts/Levels has no lobby file: one pad of look `lobby` and
-- four points on it. It lies 1,500 studs north of the world origin, clear of every camp (each
-- is within 1,000 studs of the origin on every axis). The pad is a deep block and the kill
-- height is close under it, config or no config: whoever steps off falls a short way, and is
-- put back on ground their fall's speed does not carry them through.
function LevelGeometry.BareLobby(): Types.LevelLayout
	local z = -1500
	return {
		version = 1,
		arena = nil,
		start = { x = 0, y = 0, z = z },
		spawns = {
			{ x = -6, y = 0, z = z - 6 },
			{ x = 6, y = 0, z = z - 6 },
			{ x = 6, y = 0, z = z + 6 },
			{ x = -6, y = 0, z = z + 6 },
		},
		killY = -12,
		barrier = nil,
		camps = {},
		blocks = {
			{ name = "LobbyPad", look = "lobby", x = 0, y = -2, z = z, sx = 32, sy = 4, sz = 32 },
		},
		secrets = {},
		route = {},
	}
end

-- Every Part a layout becomes, in build order: the blocks; per camp its floor, fence, gates,
-- cover, checkpoint marker, fire markers and invisible wall; per secret its marked block and its
-- sign. Only a camp that locks (L1b-12) has gates and a wall: an open camp's fence is cut at its
-- gates and the road runs through. A marker or a sign whose size `sizes` does not give is left
-- out.
-- Names are what Studio's Explorer shows (Camp_A_Floor, Gate_A_1, Barrier_A_3,
-- Secret_lookout). nil and one line saying why when the layout cannot be built: it still
-- names an arena, a camp has gates and no fence, a camp's floor has no depth (`sizes.floor`),
-- a piece has a position that is not a number or a size that is not positive (a block, a
-- camp, a piece of cover or a secret with a size of 0 or less), or it is more than `maxParts`
-- Parts.
function LevelGeometry.Pieces(
	layout: Types.LevelLayout,
	sizes: Sizes,
	maxParts: number
): ({ Piece }?, string?)
	if layout.arena ~= nil and layout.camps == nil then
		return nil,
			`the layout names the arena "{layout.arena}": resolve it with LevelGeometry.FromArena`
	end
	local depth = depthOf(sizes.floor)
	local pieces: { Piece } = {}
	local blocks = listOf(layout.blocks)
	for index, box in LevelGeometry.BlockBoxes(layout, depth) do
		local block = blocks[index]
		table.insert(pieces, {
			name = block.name or `Block_{index}`,
			role = "block",
			box = box,
			look = block.look,
			collide = block.collide ~= false,
			text = block.text,
		})
	end
	local barrier = layout.barrier
	for _, camp in listOf(layout.camps) do
		local id = camp.id
		local fence = camp.fence
		if fence == nil and #listOf(camp.gates) > 0 then
			return nil, `camp {id} has gates and no fence`
		end
		if depth == nil then
			return nil,
				`camp {id} has no floor: levels.floorThickness is missing or is not a positive number`
		end
		local floor = camp.floor
		table.insert(pieces, {
			name = `Camp_{id}_Floor`,
			role = "floor",
			box = LevelGeometry.FloorBox(camp, depth),
			look = "campFloor",
			material = if floor ~= nil then floor.material else nil,
			color = if floor ~= nil then floor.color else nil,
			camp = id,
			collide = true,
		})
		for index, box in LevelGeometry.FenceBoxes(camp, sizes.fence) do
			table.insert(pieces, {
				name = `Camp_{id}_Fence_{index}`,
				role = "fence",
				box = box,
				look = "wall",
				material = if fence ~= nil then fence.material else nil,
				color = if fence ~= nil then fence.color else nil,
				camp = id,
				collide = true,
			})
		end
		local locks = camp.locks == true
		local gates: { Box } = if locks then LevelGeometry.GateBoxes(camp, sizes.fence) else {}
		for index, box in gates do
			table.insert(pieces, {
				name = `Gate_{id}_{index}`,
				role = "gate",
				box = box,
				look = "gate",
				camp = id,
				collide = true,
			})
		end
		local obstacles = listOf(camp.obstacles)
		for index, box in LevelGeometry.ObstacleBoxes(camp) do
			local obstacle = obstacles[index]
			table.insert(pieces, {
				name = `Camp_{id}_Obstacle_{index}`,
				role = "obstacle",
				box = box,
				look = "wall",
				material = obstacle.material,
				color = obstacle.color,
				camp = id,
				collide = true,
			})
		end
		local markerSize = sizes.checkpoint
		local marker = if markerSize ~= nil
			then LevelGeometry.CheckpointBox(camp, markerSize)
			else nil
		if marker ~= nil then
			-- A marker only: nobody is stopped by it, in a camp the crowd walks through anyway.
			table.insert(pieces, {
				name = `Camp_{id}_Checkpoint`,
				role = "checkpoint",
				box = marker,
				look = "checkpoint",
				camp = id,
				collide = false,
			})
		end
		local fireSize = sizes.fire
		if fireSize ~= nil then
			for _, spot in listOf(camp.spots) do
				local fire = LevelGeometry.FireBox(camp, spot, fireSize)
				if fire ~= nil then
					-- A marker only: the group sits round it, and the crowd walks through it anyway.
					table.insert(pieces, {
						name = `Camp_{id}_Fire_{spot.id}`,
						role = "fire",
						box = fire,
						look = "fire",
						camp = id,
						collide = false,
					})
				end
			end
		end
		if barrier ~= nil and locks then
			for index, box in LevelGeometry.BarrierBoxes(camp, sizes.fence, barrier) do
				table.insert(pieces, {
					name = `Barrier_{id}_{index}`,
					role = "barrier",
					box = box,
					camp = id,
					collide = true,
				})
			end
		end
	end
	local signSize = sizes.sign
	for _, secret in listOf(layout.secrets) do
		table.insert(pieces, {
			name = `Secret_{secret.id}`,
			role = "secret",
			box = LevelGeometry.SecretBox(secret),
			look = "secret",
			collide = true,
		})
		if signSize ~= nil then
			-- A sign is read, never stood on: it must not narrow the road it stands beside.
			table.insert(pieces, {
				name = `Secret_{secret.id}_Sign`,
				role = "sign",
				box = LevelGeometry.SignBox(secret, signSize),
				look = "sign",
				collide = false,
				text = secret.sign.text,
			})
		end
	end
	for _, piece in pieces do
		if not isSound(piece.box) then
			return nil,
				`{piece.name} has a position that is not a number or a size that is not positive`
		end
	end
	if #pieces > maxParts then
		return nil, `{#pieces} Parts, over levels.maxParts ({maxParts})`
	end
	return pieces, nil
end

return LevelGeometry
