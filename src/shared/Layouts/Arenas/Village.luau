--!strict
-- Raider Woods, the Village expedition arena (docs/INTERFACES.md "C1 contracts" → "Arena").
-- A data file, like the era plot layouts: plain numbers, Enum.Material NAMES and RGB triples, so
-- ArenaService owns every Instance and this module stays requireable from anywhere.
--
-- Geometry rules that matter to the run:
-- * origin = arena centre, floor TOP face at y = 0; obstacles sit on that face.
-- * the lobby pad is the centre, because this is a defence: the party holds the middle and the
--   eight rim spawns feed inward from every side, so no seat is safe and no side is ignored.
-- * enemies walk with Humanoid:MoveTo and have no pathfinding, so obstacles are small, low and
--   sit BETWEEN the eight radial spawn lines (22.5 degrees off each) — a blocker parked on a
--   spawn line would jam a whole wave against it.

local RIM = 46
local DIAGONAL = 32.5

return {
	size = { x = 110, z = 110 },
	floor = { material = "Grass", color = { 106, 127, 63 } },
	wall = { height = 4, material = "WoodPlanks", color = { 112, 84, 56 } },
	lobbyPad = { x = 0, z = 0 },
	-- Respawns, round-robin: a ring just off the pad so a returning player lands next to the
	-- fight rather than inside the enemy that killed them.
	playerSpawns = {
		{ x = -12, z = -12 },
		{ x = 12, z = -12 },
		{ x = 12, z = 12 },
		{ x = -12, z = 12 },
	},
	-- Eight compass points on the rim, used round-robin per spawn so a wave arrives spread out.
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
	-- Cover to break line of sight for the archers and to make the melee take corners.
	obstacles = {
		-- boulders, mid ring
		{
			x = 9.2,
			z = 22.3,
			sx = 5,
			sy = 3.5,
			sz = 5,
			material = "Slate",
			color = { 110, 110, 105 },
		},
		{
			x = 22.3,
			z = -9.2,
			sx = 6,
			sy = 4,
			sz = 5,
			material = "Slate",
			color = { 102, 104, 100 },
		},
		{
			x = -9.2,
			z = -22.3,
			sx = 5,
			sy = 3.5,
			sz = 6,
			material = "Slate",
			color = { 110, 110, 105 },
		},
		{
			x = -22.3,
			z = 9.2,
			sx = 5,
			sy = 3,
			sz = 5,
			material = "Slate",
			color = { 102, 104, 100 },
		},
		-- felled logs, outer ring
		{ x = 12.6, z = -30.4, sx = 12, sy = 2, sz = 3, material = "Wood", color = { 96, 70, 45 } },
		{
			x = -30.4,
			z = -12.6,
			sx = 3,
			sy = 2,
			sz = 12,
			material = "Wood",
			color = { 86, 62, 40 },
		},
		{ x = -12.6, z = 30.4, sx = 12, sy = 2, sz = 3, material = "Wood", color = { 96, 70, 45 } },
		{ x = 30.4, z = 12.6, sx = 3, sy = 2, sz = 12, material = "Wood", color = { 86, 62, 40 } },
	},
}
