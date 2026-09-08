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
		tentSmall = { position = Vector3.new(-40, 0, -20), rotationY = 270 },
		watchtower = { position = Vector3.new(-42, 0, -44), rotationY = 225 },

		-- industry lane along the west edge, doors opening east onto the village
		woodcutterHut = { position = Vector3.new(-44, 0, 6), rotationY = 270 },
		blacksmith = { position = Vector3.new(-44, 0, -8), rotationY = 270 },
		bakery = { position = Vector3.new(-28, 0, 10), rotationY = 270 },

		-- village square: well and fountain face each other across the plaza
		well = { position = Vector3.new(-10, 0, 0), rotationY = 270 },
		villageSquare = { position = Vector3.new(12, 0, 8), rotationY = 90 },
		marketStall = { position = Vector3.new(2, 0, 26), rotationY = 0 },
		tavern = { position = Vector3.new(26, 0, 24), rotationY = 90 },
		flowerBed = { position = Vector3.new(-16, 0, 20), rotationY = 270 },

		-- homes clustered across the back, looking south over the square
		houseSmallA = { position = Vector3.new(-34, 0, 30), rotationY = 270 },
		houseSmallB = { position = Vector3.new(-18, 0, 42), rotationY = 0 },
		houseLargeA = { position = Vector3.new(0, 0, 44), rotationY = 0 },
		chapel = { position = Vector3.new(22, 0, 44), rotationY = 0 },
		treeOak = { position = Vector3.new(-44, 0, 44), rotationY = 315 },

		-- farmland and traffic along the east edge
		farmPlot = { position = Vector3.new(40, 0, -16), rotationY = 90 },
		windmill = { position = Vector3.new(44, 0, -34), rotationY = 90 },
		stables = { position = Vector3.new(42, 0, 10), rotationY = 90 },
		tradeRoute = { position = Vector3.new(36, 0, -44), rotationY = 90 },

		-- monument approach: road leads in past the banner to the keep, wall gate
		-- rising beside it at the front edge
		dirtRoad = { position = Vector3.new(-14, 0, -46), rotationY = 0 },
		bannerPole = { position = Vector3.new(12, 0, -18), rotationY = 90 },
		townWall = { position = Vector3.new(16, 0, -48), rotationY = 180 },
		castleKeep = { position = Vector3.new(0, 0, -30), rotationY = 0 },
	},
}
