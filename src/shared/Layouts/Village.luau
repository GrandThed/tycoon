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
		-- spur: straight down to the avenue so the very first purchase is connected at tier 1
		campfire = {
			position = Vector3.new(-28, 0, -28),
			rotationY = 225,
			spur = { Vector3.new(-22.3, 0, -18.1), Vector3.new(-22.3, 0, -8) },
		},
		-- spur: leaves from the pad's far corner so the path clears the campfire
		tentSmall = {
			position = Vector3.new(-40, 0, -20),
			rotationY = 270,
			spur = { Vector3.new(-29, 0, -17), Vector3.new(-29, 0, -8) },
		},
		-- spur: under the campfire to the west entry; the auto route cuts the campfire
		watchtower = {
			position = Vector3.new(-42, 0, -44),
			rotationY = 225,
			spur = { Vector3.new(-32.1, 0, -38.3), Vector3.new(-25, 0, -38.3) },
		},

		-- industry lane along the west edge, doors opening east onto the village
		-- spur: the bakery stands across the door, so the path slips past its corner
		woodcutterHut = {
			position = Vector3.new(-44, 0, 6),
			rotationY = 270,
			spur = { Vector3.new(-33, 0, 3), Vector3.new(-29.5, 0, 3), Vector3.new(-29.5, 0, -8) },
		},
		blacksmith = { position = Vector3.new(-44, 0, -8), rotationY = 270 },
		bakery = { position = Vector3.new(-28, 0, 10), rotationY = 270 },

		-- village square: well and fountain face each other across the plaza
		well = { position = Vector3.new(-10, 0, 0), rotationY = 270 },
		-- spur: the fountain faces the well; the auto route would run back through the fountain
		villageSquare = {
			position = Vector3.new(12, 0, 8),
			rotationY = 90,
			spur = { Vector3.new(4, 0, 5), Vector3.new(4, 0, -8) },
		},
		-- spur: the stall's front opens onto the square, so its road leaves by the side to the east
		-- lane
		marketStall = {
			position = Vector3.new(2, 0, 26),
			rotationY = 0,
			spur = { Vector3.new(5, 0, 18), Vector3.new(11, 0, 18) },
		},
		tavern = { position = Vector3.new(26, 0, 24), rotationY = 90 },
		-- spur: the market stall hems the bed in; a short hop onto the back lane's end
		flowerBed = {
			position = Vector3.new(-16, 0, 20),
			rotationY = 270,
			spur = { Vector3.new(-9, 0, 23), Vector3.new(-9, 0, 27) },
		},

		-- homes clustered across the back, looking south over the square
		-- spur: under the cottage's pad to the back lane; the auto route cuts that pad
		houseSmallA = {
			position = Vector3.new(-34, 0, 30),
			rotationY = 270,
			spur = { Vector3.new(-23, 0, 28), Vector3.new(-9, 0, 28) },
		},
		houseSmallB = { position = Vector3.new(-18, 0, 42), rotationY = 0 },
		-- spur: the market stall sits in front, so the manor's road leaves by the side
		houseLargeA = {
			position = Vector3.new(0, 0, 44),
			rotationY = 0,
			spur = { Vector3.new(3, 0, 35.5), Vector3.new(11, 0, 35.5) },
		},
		-- spur: side exit onto the same lane as the manor
		chapel = {
			position = Vector3.new(22, 0, 44),
			rotationY = 0,
			spur = { Vector3.new(19, 0, 36), Vector3.new(11, 0, 36) },
		},
		-- spur: no spine fits behind the houses, so the oak's path doubles as the back-west lane
		treeOak = {
			position = Vector3.new(-44, 0, 44),
			rotationY = 315,
			spur = {
				Vector3.new(-34.1, 0, 38.3),
				Vector3.new(-26, 0, 38.3),
				Vector3.new(-26, 0, 52),
				Vector3.new(-9, 0, 52),
			},
		},

		-- farmland and traffic along the east edge
		-- spur: onto the avenue (tier 1) rather than the tier-2 east lane, since it is bought fourth
		farmPlot = {
			position = Vector3.new(40, 0, -16),
			rotationY = 90,
			spur = { Vector3.new(32, 0, -13), Vector3.new(32, 0, -8) },
		},
		windmill = { position = Vector3.new(44, 0, -34), rotationY = 90 },
		stables = { position = Vector3.new(42, 0, 10), rotationY = 90 },
		tradeRoute = { position = Vector3.new(36, 0, -44), rotationY = 90 },

		-- monument approach: road leads in past the banner to the keep, wall gate
		-- rising beside it at the front edge
		-- spur: its pad faces the plot edge, so the path runs along it to the castle approach
		dirtRoad = {
			position = Vector3.new(-14, 0, -46),
			rotationY = 0,
			spur = { Vector3.new(-11, 0, -54), Vector3.new(5, 0, -54) },
		},
		-- spur: from the pad's side so the cottage lot beside the banner stays clear
		bannerPole = {
			position = Vector3.new(12, 0, -18),
			rotationY = 90,
			spur = { Vector3.new(4, 0, -15), Vector3.new(4, 0, -8) },
		},
		townWall = { position = Vector3.new(16, 0, -48), rotationY = 180 },
		castleKeep = { position = Vector3.new(0, 0, -30), rotationY = 0 },
	},
	-- Street plan (M9 city dressing). Spine i appears at growth tier i, so the order follows the
	-- purchase order: each spine arrives about when the buildings along it are bought. Every spine
	-- keeps road.width/2 + 1 studs from every footprint, pad and the Sign, and spurs that the auto
	-- route would push through something carry an override above. tools/streetplan.py checks all
	-- of
	-- it and draws assets/testfit/out/Village/streetplan.png.
	streets = {
		-- 1: the castle approach from the hub edge beside the Sign, along the front past the gate and
		-- trade route, up the farm edge and back across the village as the main avenue. The road slot
		-- and the town wall hem the keep in, so its approach can only open onto the front edge.
		{
			points = {
				Vector3.new(5, 0, -44),
				Vector3.new(5, 0, -56.5),
				Vector3.new(52, 0, -56.5),
				Vector3.new(52, 0, -8),
				Vector3.new(-29.5, 0, -8),
			},
		},
		-- 2: east lane from the town wall past the windmill and stables, round the fountain to the
		-- market, then the back lane behind the manor down to the cottages.
		{
			points = {
				Vector3.new(10.5, 0, -33),
				Vector3.new(24, 0, -33),
				Vector3.new(24, 0, 16),
				Vector3.new(11, 0, 16),
				Vector3.new(11, 0, 52),
				Vector3.new(-9, 0, 52),
				Vector3.new(-9, 0, 27),
			},
		},
		-- 3: a second way in from the hub, past the watchtower and campfire onto the avenue.
		{
			points = {
				Vector3.new(-25, 0, -56.5),
				Vector3.new(-25, 0, -38),
				Vector3.new(-13, 0, -38),
				Vector3.new(-13, 0, -8),
			},
		},
		-- 4: the new quarter east of the tavern, the only open ground left late in the era.
		{ points = { Vector3.new(11, 0, 52), Vector3.new(44, 0, 52), Vector3.new(44, 0, 18) } },
	},
	-- Filler cottages, each facing its road. The early tiers line the avenue near the hub, where
	-- they
	-- are seen, and the last ones fill the new quarter behind the tavern.
	lots = {
		{ position = Vector3.new(31.5, 0, 0), rotationY = 0, tier = 2 },
		{ position = Vector3.new(-5, 0, -15.5), rotationY = 180, tier = 2 },
		{ position = Vector3.new(44, 0, -0.5), rotationY = 0, tier = 3 },
		{ position = Vector3.new(-32.5, 0, -52), rotationY = 270, tier = 3 },
		{ position = Vector3.new(36.5, 0, 23.5), rotationY = 270, tier = 4 },
		{ position = Vector3.new(51.5, 0, 24), rotationY = 90, tier = 4 },
		{ position = Vector3.new(51.5, 0, 34.5), rotationY = 90, tier = 5 },
		{ position = Vector3.new(51.5, 0, 44.5), rotationY = 90, tier = 5 },
	},
	-- Tavern square at the head of the new quarter, arriving with its road.
	plazas = {
		{ position = Vector3.new(35, 0, 35.5), rotationY = 270, tier = 4, prop = "PlazaA" },
	},
	-- Groves on the ground no slot uses: the west meadow, the back corner, both front corners, the
	-- farm edge and the lawn between the keep and the banner. Counts favour the zones where most
	-- of
	-- the circle is plantable, because rejected candidates are not redrawn.
	treeZones = {
		{ center = Vector3.new(-48, 0, 20), radius = 8, count = 10 },
		{ center = Vector3.new(-46, 0, 52), radius = 7, count = 8 },
		{ center = Vector3.new(-50, 0, -54), radius = 6, count = 6 },
		{ center = Vector3.new(48, 0, -24), radius = 5, count = 5 },
		{ center = Vector3.new(17, 0, -27), radius = 6, count = 5 },
		{ center = Vector3.new(-52, 0, -32), radius = 5, count = 6 },
	},
}
