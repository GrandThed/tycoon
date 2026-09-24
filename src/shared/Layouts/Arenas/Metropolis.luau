--!strict
-- Blackout Blocks, the Metropolis expedition arena (docs/INTERFACES.md
-- "C2.5 + C3 contracts - Stop 1", "Missions 2-4 and arenas"). The same data-file rules as
-- Arenas/Village.luau: plain numbers, Enum.Material NAMES and RGB triples, so ArenaService owns
-- every Instance and this module stays requireable from anywhere.
--
-- The ground: a dead intersection: abandoned cars in the middle ring, a stalled bus, jersey
-- barriers and a dumpster on the outer ring, two newsstands by the kerb.
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
	floor = { material = "Asphalt", color = { 58, 60, 64 } },
	wall = { height = 5, material = "Concrete", color = { 132, 132, 128 } },
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
		-- abandoned cars, mid ring
		{
			x = 21.2,
			z = 8.8,
			sx = 4.5,
			sy = 3,
			sz = 9,
			material = "Metal",
			color = { 168, 44, 44 },
		},
		{
			x = -8.8,
			z = 21.2,
			sx = 9,
			sy = 3,
			sz = 4.5,
			material = "Metal",
			color = { 46, 82, 150 },
		},
		{
			x = -21.2,
			z = -8.8,
			sx = 4.5,
			sy = 3,
			sz = 9,
			material = "Metal",
			color = { 206, 196, 176 },
		},
		{
			x = 8.8,
			z = -21.2,
			sx = 9,
			sy = 3,
			sz = 4.5,
			material = "Metal",
			color = { 70, 72, 76 },
		},
		-- bus, barriers and a dumpster, outer ring
		{
			x = 12.6,
			z = 30.5,
			sx = 14,
			sy = 5,
			sz = 5,
			material = "Metal",
			color = { 222, 172, 40 },
		},
		{
			x = -30.5,
			z = 12.6,
			sx = 1.5,
			sy = 2.5,
			sz = 10,
			material = "Concrete",
			color = { 176, 174, 168 },
		},
		{
			x = -12.6,
			z = -30.5,
			sx = 6,
			sy = 4,
			sz = 3.5,
			material = "Metal",
			color = { 46, 92, 62 },
		},
		{
			x = 30.5,
			z = -12.6,
			sx = 1.5,
			sy = 2.5,
			sz = 10,
			material = "Concrete",
			color = { 176, 174, 168 },
		},
		-- newsstands by the kerb
		{ x = -15.3, z = 37, sx = 4, sy = 5, sz = 4, material = "Brick", color = { 122, 62, 48 } },
		{ x = 15.3, z = -37, sx = 4, sy = 5, sz = 4, material = "Brick", color = { 122, 62, 48 } },
	},
}
