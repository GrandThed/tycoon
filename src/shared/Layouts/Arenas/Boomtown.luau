--!strict
-- Rail Yard Outlaws, the Boomtown expedition arena (docs/INTERFACES.md
-- "C2.5 + C3 contracts - Stop 1", "Missions 2-4 and arenas"). The same data-file rules as
-- Arenas/Village.luau: plain numbers, Enum.Material NAMES and RGB triples, so ArenaService owns
-- every Instance and this module stays requireable from anywhere.
--
-- The ground: a dusty rail yard: crate stacks and barrels in the middle ring, boxcars and lumber
-- piles on the outer ring, two hay-bale piles by the fence.
--
-- Geometry kept from Village on purpose, because the run simulator's 45-stud spawn distance
-- and every mission number assume it: 110 x 110, floor top at y = 0, lobby pad at the centre,
-- eight rim spawns on the compass points, and every obstacle 22.5 degrees OFF a spawn line with
-- its long side across the lane. C2.5 enemies pathfind round cover, but a blocker on a spawn
-- line would still funnel a whole wave into one detour. Cover is 2-6 studs tall, so a player
-- can break a shooter's line (they hold 18-30 studs out) by stepping behind it.

local RIM = 46
local DIAGONAL = 32.5

return {
	size = { x = 110, z = 110 },
	floor = { material = "Ground", color = { 156, 128, 92 } },
	wall = { height = 5, material = "WoodPlanks", color = { 104, 78, 54 } },
	lobbyPad = { x = 0, z = 0 },
	-- Respawns, round-robin: a ring just off the pad, as in Village.
	playerSpawns = {
		{ x = -12, z = -12 },
		{ x = 12, z = -12 },
		{ x = 12, z = 12 },
		{ x = -12, z = 12 },
	},
	enemySpawns = {
		{ x = 0, z = -RIM },
		{ x = DIAGONAL, z = -DIAGONAL },
		{ x = RIM, z = 0 },
		{ x = DIAGONAL, z = DIAGONAL },
		{ x = 0, z = RIM },
		{ x = -DIAGONAL, z = DIAGONAL },
		{ x = -RIM, z = 0 },
		{ x = -DIAGONAL, z = -DIAGONAL },
	},
	obstacles = {
		-- crate stacks and barrels, mid ring
		{
			x = 22.2,
			z = 9.2,
			sx = 5,
			sy = 4.5,
			sz = 5,
			material = "Wood",
			color = { 146, 104, 62 },
		},
		{
			x = -9.2,
			z = 22.2,
			sx = 4,
			sy = 3.5,
			sz = 4,
			material = "CorrodedMetal",
			color = { 118, 84, 60 },
		},
		{
			x = -22.2,
			z = -9.2,
			sx = 5,
			sy = 4.5,
			sz = 5,
			material = "Wood",
			color = { 138, 98, 58 },
		},
		{
			x = 9.2,
			z = -22.2,
			sx = 4,
			sy = 3.5,
			sz = 4,
			material = "CorrodedMetal",
			color = { 118, 84, 60 },
		},
		-- boxcars and lumber piles, outer ring
		{
			x = 12.6,
			z = 30.5,
			sx = 14,
			sy = 5,
			sz = 4,
			material = "Metal",
			color = { 128, 54, 42 },
		},
		{
			x = -30.5,
			z = 12.6,
			sx = 3,
			sy = 2.5,
			sz = 12,
			material = "WoodPlanks",
			color = { 122, 92, 60 },
		},
		{
			x = -12.6,
			z = -30.5,
			sx = 14,
			sy = 5,
			sz = 4,
			material = "Metal",
			color = { 96, 70, 52 },
		},
		{
			x = 30.5,
			z = -12.6,
			sx = 3,
			sy = 2.5,
			sz = 12,
			material = "WoodPlanks",
			color = { 122, 92, 60 },
		},
		-- hay bales by the fence
		{
			x = 37,
			z = 15.3,
			sx = 3,
			sy = 2.5,
			sz = 6,
			material = "Fabric",
			color = { 196, 170, 96 },
		},
		{
			x = -37,
			z = -15.3,
			sx = 3,
			sy = 2.5,
			sz = 6,
			material = "Fabric",
			color = { 196, 170, 96 },
		},
	},
}
