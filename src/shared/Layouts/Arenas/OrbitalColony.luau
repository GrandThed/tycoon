--!strict
-- Crater Breach, the Orbital Colony expedition arena (docs/INTERFACES.md
-- "C2.5 + C3 contracts - Stop 1", "Missions 2-4 and arenas"). The same data-file rules as
-- Arenas/Village.luau: plain numbers, Enum.Material NAMES and RGB triples, so ArenaService owns
-- every Instance and this module stays requireable from anywhere.
--
-- The ground: a breached landing field: cargo containers in the middle ring, boulders, a fuel
-- tank and a solar rack on the outer ring, two rim rocks by the fence. Space-kit
-- orange and white on a regolith lighter than the plot's (56, 53, 60) so rigs read on it.
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
	floor = { material = "Basalt", color = { 84, 80, 90 } },
	wall = { height = 5, material = "DiamondPlate", color = { 176, 182, 190 } },
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
		-- cargo containers, mid ring
		{ x = 22.2, z = 9.2, sx = 5, sy = 5, sz = 8, material = "Metal", color = { 255, 160, 52 } },
		{
			x = -9.2,
			z = 22.2,
			sx = 8,
			sy = 5,
			sz = 5,
			material = "Metal",
			color = { 225, 228, 232 },
		},
		{
			x = -22.2,
			z = -9.2,
			sx = 5,
			sy = 5,
			sz = 8,
			material = "Metal",
			color = { 255, 160, 52 },
		},
		{
			x = 9.2,
			z = -22.2,
			sx = 8,
			sy = 5,
			sz = 5,
			material = "Metal",
			color = { 225, 228, 232 },
		},
		-- boulders, a fuel tank and a solar rack, outer ring
		{ x = 12.6, z = 30.5, sx = 7, sy = 5, sz = 6, material = "Rock", color = { 112, 102, 98 } },
		{
			x = -30.5,
			z = 12.6,
			sx = 5,
			sy = 6,
			sz = 5,
			material = "Metal",
			color = { 214, 218, 224 },
		},
		{
			x = -12.6,
			z = -30.5,
			sx = 7,
			sy = 5,
			sz = 6,
			material = "Rock",
			color = { 104, 96, 94 },
		},
		{
			x = 30.5,
			z = -12.6,
			sx = 4,
			sy = 2,
			sz = 10,
			material = "SmoothPlastic",
			color = { 44, 62, 112 },
		},
		-- rim rocks by the fence
		{ x = -15.3, z = 37, sx = 6, sy = 3, sz = 5, material = "Rock", color = { 98, 92, 90 } },
		{ x = 15.3, z = -37, sx = 6, sy = 3, sz = 5, material = "Rock", color = { 98, 92, 90 } },
	},
}
