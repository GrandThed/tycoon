--!strict
-- Proving Grounds, the P1 test range (docs/COMBAT_DESIGN.md section 8, INTERFACES "P1 contracts").
-- The same data-file rules as Arenas/Village.luau: plain numbers, Enum.Material NAMES and RGB
-- triples, so ArenaService owns every Instance.
--
-- Geometry that the config depends on:
-- * origin = arena centre, floor TOP face at y = 0. The lobby pad sits near the +Z edge and the
--   SpawnLocation faces -Z, so the player spawns looking down the range.
-- * Config/ProvingGrounds.json `dummySets[*].at` are ARENA coordinates, not offsets from the pad:
--   a row "d studs in front of the spawn" is at z = SPAWN_Z - d. Move SPAWN_Z and every `at` moves
--   with it by hand.
-- * The dummy field (|x| <= 20, z from -10 to 85) is kept flat: the only geometry in it is the
--   0.2-stud distance strips, which neither trip a character nor block a hitscan ray.
-- * Obstacles here are range furniture, not cover the mission AI paths around. P1 crowd steering
--   only separates enemies, so nothing solid sits in the lane a chasing set runs down.

local SPAWN_Z = 90
-- Half-width of the dummy lane; the strips span it and the tally posts stand just outside.
local LANE = 20
local STRIP_HEIGHT = 0.2
local STRIP_DEPTH = 0.6
local POST_HEIGHT = 3
local POST_GAP = 1.5

local FLOOR = { 160, 161, 166 }
local FURNITURE = { 112, 114, 122 }
local COVER = { 128, 131, 138 }
local BACKSTOP = { 88, 90, 98 }

local Types = require(script.Parent.Parent.Parent:WaitForChild("Types"))

-- One distance line: a glowing strip across the lane plus `tally` posts at each end, so the
-- distance reads from the side even when dummies hide the strip (1 post = 10, 4 posts = 100).
local function distanceLine(
	obstacles: { Types.ArenaObstacle },
	distance: number,
	tally: number,
	color: { number }
)
	local z = SPAWN_Z - distance
	table.insert(obstacles, {
		x = 0,
		z = z,
		sx = LANE * 2,
		sy = STRIP_HEIGHT,
		sz = STRIP_DEPTH,
		material = "Neon",
		color = color,
	})
	for index = 1, tally do
		local offset = LANE + 1 + (index - 1) * POST_GAP
		for _, side in { -1, 1 } do
			table.insert(obstacles, {
				x = side * offset,
				z = z,
				sx = 1,
				sy = POST_HEIGHT,
				sz = 1,
				material = "Neon",
				color = color,
			})
		end
	end
end

local obstacles: { Types.ArenaObstacle } = {}

distanceLine(obstacles, 10, 1, { 240, 240, 240 })
distanceLine(obstacles, 25, 2, { 245, 205, 60 })
distanceLine(obstacles, 50, 3, { 80, 190, 225 })
distanceLine(obstacles, 100, 4, { 170, 120, 230 })

-- Jump staircase, left of the spawn. Heights are the movement ladder in BALANCE.md: 8 is an easy
-- single jump, 16 a full single jump, 24 needs the double jump. Adjacent steps are 8 apart, so the
-- stair also climbs one single jump at a time, and the 8 step is 10-15 studs from the crowd sets'
-- flank for a jump-off ground slam.
local stairs = {
	{ x = -26, height = 8 },
	{ x = -36, height = 16 },
	{ x = -46, height = 24 },
}
for _, step in stairs do
	table.insert(obstacles, {
		x = step.x,
		z = SPAWN_Z + 4,
		sx = 8,
		sy = step.height,
		sz = 8,
		material = "Concrete",
		color = FURNITURE,
	})
end

-- Stand-alone pillars right of the spawn: no step up, so 16 and 24 test the jump from the floor.
table.insert(obstacles, {
	x = 24,
	z = SPAWN_Z + 6,
	sx = 6,
	sy = 16,
	sz = 6,
	material = "Concrete",
	color = FURNITURE,
})
table.insert(obstacles, {
	x = 34,
	z = SPAWN_Z + 6,
	sx = 6,
	sy = 24,
	sz = 6,
	material = "Concrete",
	color = FURNITURE,
})

-- Shooting cover on the right flank, outside the lane: low walls (3, crouch-height for a 5-stud
-- character) to shoot over, tall walls and pillars (6-9) to peek around, staggered so a strafe
-- line always has a next piece.
local cover = {
	{ x = 32, z = 78, sx = 8, sy = 3, sz = 2 },
	{ x = 44, z = 70, sx = 3, sy = 9, sz = 3 },
	{ x = 32, z = 60, sx = 2, sy = 6, sz = 10 },
	{ x = 46, z = 52, sx = 8, sy = 3, sz = 2 },
	{ x = 34, z = 42, sx = 3, sy = 9, sz = 3 },
	{ x = 48, z = 32, sx = 10, sy = 6, sz = 2 },
}
for _, block in cover do
	table.insert(obstacles, {
		x = block.x,
		z = block.z,
		sx = block.sx,
		sy = block.sy,
		sz = block.sz,
		material = "Concrete",
		color = COVER,
	})
end

-- Backstop 120 studs out (the rifle's range): misses land on something visible instead of
-- vanishing, and it frames the 100-stud row.
table.insert(obstacles, {
	x = 0,
	z = SPAWN_Z - 120,
	sx = 80,
	sy = 10,
	sz = 4,
	material = "Concrete",
	color = BACKSTOP,
})

local layout: Types.ArenaLayout = {
	size = { x = 220, z = 220 },
	floor = { material = "SmoothPlastic", color = FLOOR },
	wall = { height = 4, material = "Concrete", color = { 100, 102, 110 } },
	lobbyPad = { x = 0, z = SPAWN_Z },
	-- Beside the pad and behind the 10-stud line, so a respawn never lands inside a dummy set.
	playerSpawns = {
		{ x = -8, z = SPAWN_Z + 4 },
		{ x = 8, z = SPAWN_Z + 4 },
		{ x = -8, z = SPAWN_Z - 4 },
		{ x = 8, z = SPAWN_Z - 4 },
	},
	-- Required by the contract (8, round-robin) but unused by the range: the dummy sets place
	-- their own crowds. Kept on the far half, clear of every obstacle.
	enemySpawns = {
		{ x = 0, z = -95 },
		{ x = -60, z = -95 },
		{ x = 60, z = -95 },
		{ x = -95, z = -60 },
		{ x = 95, z = -60 },
		{ x = -95, z = 0 },
		{ x = 95, z = 0 },
		{ x = 0, z = -60 },
	},
	obstacles = obstacles,
}

return layout
