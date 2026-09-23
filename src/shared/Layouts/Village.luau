--!strict
-- Era 1 (Village) plot layout. Positions are studs relative to plot center, Y at
-- ground level. rotationY is Roblox-native CFrame.Angles(0, rad(r), 0): 0 faces -Z
-- (the plot's front/hub edge, so the monument greets arriving players), positive
-- turns counterclockwise seen from above (90 faces -X, 270 faces +X).
-- Pads spawn padOffset studs along that facing; every building keeps clear ground
-- there. Clusters, not a grid, so the village reads organically: campsite at the
-- front-west, industry lane along the west edge, well and square in the middle,
-- homes across the back, farmland east, and the keep front-and-center.
return {
	plotSize = Vector3.new(120, 1, 120),
	baseColor = Color3.fromRGB(106, 127, 63),
	padSize = Vector3.new(6, 0.5, 6),
	padOffset = 8,
	placeholderSize = Vector3.new(8, 8, 8),
	slots = {
		-- starter campsite, front-west corner where the player first walks in
		campfire = { position = Vector3.new(-28, 0, -28), rotationY = 225 },
		-- spur: the campfire's pad sits across the door, so the path angles past it
		tentSmall = {
			position = Vector3.new(-40, 0, -20),
			rotationY = 270,
			spur = { Vector3.new(-40, 0, -20), Vector3.new(-25, 0, -10.5) },
		},
		-- spur: one straight path to the entrance lane; the square-on route would clip the campfire
		watchtower = {
			position = Vector3.new(-42, 0, -44),
			rotationY = 225,
			spur = { Vector3.new(-42, 0, -44), Vector3.new(-24, 0, -42) },
		},

		-- industry lane along the west edge, doors opening east onto the village
		-- spur: the bakery stands across the door; the path angles past its corner
		woodcutterHut = {
			position = Vector3.new(-44, 0, 6),
			rotationY = 270,
			spur = { Vector3.new(-44, 0, 6), Vector3.new(-29.5, 0, -1.5) },
		},
		blacksmith = { position = Vector3.new(-44, 0, -8), rotationY = 270 },
		-- spur: its door faces the well's back wall with no room for a lane, so the path leaves by the
		-- side
		bakery = {
			position = Vector3.new(-28, 0, 10),
			rotationY = 270,
			spur = { Vector3.new(-28, 0, 10), Vector3.new(-29.5, 0, -1.5) },
		},

		-- village square: well and fountain face each other across the plaza
		-- spur: straight out from the door onto the lane instead of an L
		well = {
			position = Vector3.new(-10, 0, 0),
			rotationY = 270,
			spur = { Vector3.new(-10, 0, 0), Vector3.new(0, 0, -8) },
		},
		-- spur: the fountain faces the well across its pad; the path angles to a crossing with the
		-- banner's path
		villageSquare = {
			position = Vector3.new(12, 0, 8),
			rotationY = 90,
			spur = { Vector3.new(12, 0, 8), Vector3.new(7, 0, -8) },
		},
		-- spur: the fountain blocks the front, so the path angles to the east lane
		marketStall = {
			position = Vector3.new(2, 0, 26),
			rotationY = 0,
			spur = { Vector3.new(2, 0, 26), Vector3.new(10, 0, 18) },
		},
		tavern = { position = Vector3.new(26, 0, 24), rotationY = 90 },
		-- spur: the market stall hems the bed in; a short angled hop onto the cottage lane
		flowerBed = {
			position = Vector3.new(-16, 0, 20),
			rotationY = 270,
			spur = { Vector3.new(-16, 0, 20), Vector3.new(-9, 0, 27.8) },
		},

		-- homes clustered across the back, looking south over the square
		-- spur: the cottage's pad blocks the square-on route
		houseSmallA = {
			position = Vector3.new(-34, 0, 30),
			rotationY = 270,
			spur = { Vector3.new(-34, 0, 30), Vector3.new(-19.8, 0, 27.8) },
		},
		-- spur: the flower bed blocks the front; the path angles onto the cottage lane
		houseSmallB = {
			position = Vector3.new(-18, 0, 42),
			rotationY = 0,
			spur = { Vector3.new(-18, 0, 42), Vector3.new(-12, 0, 27.8) },
		},
		-- spur: the market stall blocks the front; the path angles onto the east lane
		houseLargeA = {
			position = Vector3.new(0, 0, 44),
			rotationY = 0,
			spur = { Vector3.new(0, 0, 44), Vector3.new(10, 0, 33) },
		},
		-- spur: the tavern blocks the front; the path angles onto the east lane
		chapel = {
			position = Vector3.new(22, 0, 44),
			rotationY = 0,
			spur = { Vector3.new(22, 0, 44), Vector3.new(10, 0, 35) },
		},
		-- spur: the oak faces the cottage's back wall, so its path leaves behind it
		treeOak = {
			position = Vector3.new(-44, 0, 44),
			rotationY = 315,
			spur = { Vector3.new(-44, 0, 44), Vector3.new(-38, 0, 52) },
		},

		-- farmland and traffic along the east edge
		farmPlot = { position = Vector3.new(40, 0, -16), rotationY = 90 },
		windmill = { position = Vector3.new(44, 0, -34), rotationY = 90 },
		stables = { position = Vector3.new(42, 0, 10), rotationY = 90 },
		-- spur: one straight path between the gate and the windmill to the farm track
		tradeRoute = {
			position = Vector3.new(36, 0, -44),
			rotationY = 90,
			spur = { Vector3.new(36, 0, -44), Vector3.new(25.5, 0, -37) },
		},

		-- monument approach: road leads in past the banner to the keep, wall gate
		-- rising beside it at the front edge
		-- spur: its pad faces the plot edge; the path angles onto the entrance lane
		dirtRoad = {
			position = Vector3.new(-14, 0, -46),
			rotationY = 0,
			spur = { Vector3.new(-14, 0, -46), Vector3.new(-25.92, 0, -55) },
		},
		-- spur: straight onto the lane, crossing it to meet the fountain's path
		bannerPole = {
			position = Vector3.new(12, 0, -18),
			rotationY = 90,
			spur = { Vector3.new(12, 0, -18), Vector3.new(7, 0, -8) },
		},
		-- spur: one straight path to the farm track instead of an L
		townWall = {
			position = Vector3.new(16, 0, -48),
			rotationY = 180,
			spur = { Vector3.new(16, 0, -48), Vector3.new(25.5, 0, -37) },
		},
		-- spur: the road slot and the wall gate close the keep's front, so the path leaves the door
		-- and turns west to the lane
		castleKeep = {
			position = Vector3.new(0, 0, -30),
			rotationY = 0,
			spur = { Vector3.new(0, 0, -39), Vector3.new(-12, 0, -38) },
		},
	},
	-- Street plan (M9 city dressing, wave 1b natural paths). The roads grow with the buildings:
	-- only the stretches from the entrance (the first point below) to each owned building's path
	-- are drawn, meandered on near plots. Lanes pass just in front of each cluster, so most paths
	-- are a short walk from the door; overrides above mark where a neighbour blocks the straight
	-- line. tools/streetplan.py checks every rule and draws
	-- assets/testfit/out/Village/streetplan.png.
	streets = {
		-- 1: the main lane. In from the hub edge through the gap beside the road slot (the keep's
		-- own front is walled in by that slot and the town wall), past the keep's door, north
		-- between the campsite and the keep, east along the square, up past the farms, round the
		-- tavern and north between the market and the homes to the oak.
		{
			points = {
				Vector3.new(-26, 0, -56),
				Vector3.new(-25, 0, -43),
				Vector3.new(-20, 0, -38),
				Vector3.new(-12, 0, -38),
				Vector3.new(-12, 0, -16),
				Vector3.new(-4, 0, -8),
				Vector3.new(25.5, 0, -8),
				Vector3.new(25.5, 0, 12),
				Vector3.new(20, 0, 15),
				Vector3.new(10, 0, 17.5),
				Vector3.new(10, 0, 48),
				Vector3.new(6, 0, 52),
				Vector3.new(-38, 0, 52),
			},
		},
		-- 2: the campsite lane, square in front of the campfire, on to the smithy's door and up
		-- to the woodcutter.
		{
			points = {
				Vector3.new(-12, 0, -23.5),
				Vector3.new(-27.5, 0, -8),
				Vector3.new(-29.5, 0, -8),
				Vector3.new(-29.5, 0, -1.5),
			},
		},
		-- 3: the farm track in front of the windmill, trade route and wall gate.
		{ points = { Vector3.new(25.5, 0, -8), Vector3.new(25.5, 0, -37) } },
		-- 4: the cottage lane between the cottages and the manor.
		{
			points = {
				Vector3.new(-9, 0, 52),
				Vector3.new(-9, 0, 27.8),
				Vector3.new(-19.8, 0, 27.8),
			},
		},
	},
	-- Filler cottages, each facing a drawn lane or a building's path. The early tiers sit by the
	-- entrance, the campsite and the farm track near the hub; the last take the keep's forecourt
	-- and the two back corners, the only other spots a 9x9 house clears every road.
	--
	-- Wave 2c: the rest are "small" lots (6x6 cap), because no other 9x9 clears every road. They
	-- follow the village outward tier by tier: huts by the campsite and the keep lane first, then
	-- the keep's side and the smithy, cottages round the square, then the farms and the stables,
	-- and last the lanes behind the market and the homes.
	lots = {
		{ position = Vector3.new(-34, 0, -53.5), rotationY = 270, tier = 2 },
		{ position = Vector3.new(-20.5, 0, -1), rotationY = 0, tier = 2 },
		{ position = Vector3.new(33.5, 0, -1), rotationY = 90, tier = 2 },
		{ position = Vector3.new(15.5, 0, -31), rotationY = 270, tier = 3 },
		{ position = Vector3.new(27.5, 0, -53.5), rotationY = 180, tier = 3 },
		{ position = Vector3.new(18.5, 0, 54.5), rotationY = 0, tier = 4 },
		{ position = Vector3.new(-50.5, 0, 53), rotationY = 270, tier = 5 },
		{ position = Vector3.new(1, 0, -50.5), rotationY = 180, tier = 5 },
		-- 9-10: behind the campfire and beside the keep lane
		{ position = Vector3.new(-39, 0, -28), rotationY = 180, tier = 1, kind = "small" },
		{ position = Vector3.new(-18, 0, -31), rotationY = 270, tier = 1, kind = "small" },
		-- 11-12: the keep's east flank and the smithy's back
		{ position = Vector3.new(7, 0, -42), rotationY = 90, tier = 2, kind = "small" },
		{ position = Vector3.new(-48, 0, -18), rotationY = 270, tier = 2, kind = "small" },
		-- 13-15: round the square and at the head of the farm track
		{ position = Vector3.new(17, 0, -1), rotationY = 0, tier = 3, kind = "small" },
		{ position = Vector3.new(-6, 0, 8), rotationY = 0, tier = 3, kind = "small" },
		{ position = Vector3.new(35, 0, -25), rotationY = 90, tier = 3, kind = "small" },
		-- 16-18: by the farm, the stables and the woodcutter
		{ position = Vector3.new(43, 0, 1), rotationY = 90, tier = 4, kind = "small" },
		{ position = Vector3.new(39, 0, 20), rotationY = 0, tier = 4, kind = "small" },
		{ position = Vector3.new(-40, 0, 15), rotationY = 0, tier = 4, kind = "small" },
		-- 19-21: behind the homes, and a pair behind the tavern
		{ position = Vector3.new(-30, 0, 20), rotationY = 270, tier = 5, kind = "small" },
		{ position = Vector3.new(29, 0, 32), rotationY = 90, tier = 5, kind = "small" },
		{ position = Vector3.new(30, 0, 40), rotationY = 90, tier = 5, kind = "small" },
	},
	-- Parked carts (wave 2c): mostly beside the cottages that own them (`lot` = index above), plus
	-- one on the keep lane and one on the market square. Each stands off the trail and off the
	-- walkers' line along its edge.
	parking = {
		{ position = Vector3.new(-3, 0, -18), rotationY = 0, tier = 2 },
		{ position = Vector3.new(-42, 0, -34), rotationY = 0, tier = 2, lot = 9 },
		{ position = Vector3.new(30, 0, -25), rotationY = 0, tier = 3, lot = 15 },
		{ position = Vector3.new(4, 0, 1), rotationY = 0, tier = 3 },
		{ position = Vector3.new(32, 0, 17), rotationY = 90, tier = 4, lot = 17 },
		{ position = Vector3.new(-24, 0, 20), rotationY = 0, tier = 5, lot = 19 },
	},
	-- Trade yard in the open front corner beside the trade route's cart, seen from the hub.
	plazas = {
		{ position = Vector3.new(50, 0, -50.5), rotationY = 0, tier = 4, prop = "PlazaA" },
	},
	-- Groves on the ground no slot uses: the west meadow, the open quarter east of the tavern, the
	-- west strip, the farm edge, behind the watchtower and beside the oak. Counts favour the zones
	-- where most of the circle is plantable, because rejected candidates are not redrawn.
	treeZones = {
		{ center = Vector3.new(-48, 0, 20), radius = 8, count = 10 },
		{ center = Vector3.new(42, 0, 36), radius = 10, count = 12 },
		{ center = Vector3.new(-52, 0, -32), radius = 5, count = 5 },
		{ center = Vector3.new(50, 0, -24), radius = 5, count = 5 },
		{ center = Vector3.new(-51, 0, -46), radius = 5, count = 4 },
		{ center = Vector3.new(-33, 0, 44), radius = 4, count = 4 },
	},
	-- Bushes, flower beds and hedges (wave 2c): cottage gardens by the square and the campsite
	-- lane, the hedgerows along the farms on the east edge, and the smithy's back fence. None
	-- overlaps a grove, whose trees would crowd the pieces out.
	greeneryZones = {
		{ center = Vector3.new(-15, 0, -9), radius = 5, count = 5 },
		{ center = Vector3.new(-11, 0, 11), radius = 5, count = 5 },
		{ center = Vector3.new(-53, 0, -9), radius = 5, count = 5 },
		{ center = Vector3.new(51, 0, -7), radius = 5, count = 4 },
		{ center = Vector3.new(53, 0, 7), radius = 5, count = 4 },
		{ center = Vector3.new(49, 0, 21), radius = 5, count = 5 },
		{ center = Vector3.new(33, 0, 51), radius = 5, count = 5 },
	},
}
