--!strict
-- Era 2 (Boomtown) plot layout. Positions are studs relative to plot center, Y at
-- ground level. rotationY is Roblox-native CFrame.Angles(0, rad(r), 0): 0 faces -Z
-- (the plot's front/hub edge), positive turns counterclockwise seen from above
-- (90 faces -X, 270 faces +X). Pads spawn padOffset studs along that facing.
-- Personality: a 1950s main street running front-to-back along x = 0. Storefronts
-- line both sides at x = +/-16 and face the street, civic buildings fill the back
-- row, service lots sit on the outer lanes, and the clock tower greets players at
-- the street's mouth. Dusty-brown base so the era swap reads instantly.
return {
	plotSize = Vector3.new(120, 1, 120),
	baseColor = Color3.fromRGB(173, 138, 93),
	padSize = Vector3.new(6, 0.5, 6),
	padOffset = 8,
	placeholderSize = Vector3.new(8, 8, 8),
	slots = {
		-- west storefront column, doors opening east onto main street
		newsstand = { position = Vector3.new(-16, 0, -16), rotationY = 270 },
		diner = { position = Vector3.new(-16, 0, 0), rotationY = 270 },
		motel = { position = Vector3.new(-16, 0, 16), rotationY = 270 },
		groceryStore = { position = Vector3.new(-16, 0, 28), rotationY = 270 },

		-- east storefront column, doors opening west onto main street
		hotDogStand = { position = Vector3.new(16, 0, -16), rotationY = 90 },
		gasStation = { position = Vector3.new(16, 0, 0), rotationY = 90 },
		barberShop = { position = Vector3.new(16, 0, 16), rotationY = 90 },
		laundromat = { position = Vector3.new(16, 0, 28), rotationY = 90 },

		-- street furniture down the median
		-- spur: the road tile lies on main street itself, so a single point draws nothing (INTERFACES
		-- amendment P2)
		paveMainStreet = {
			position = Vector3.new(0, 0, -46),
			rotationY = 0,
			spur = { Vector3.new(0, 0, -57) },
		},
		-- spur: stands on main street itself, so a single point draws nothing (INTERFACES amendment
		-- P2)
		streetlampRow = {
			position = Vector3.new(0, 0, -8),
			rotationY = 0,
			spur = { Vector3.new(0, 0, -19) },
		},
		trafficLights = { position = Vector3.new(0, 0, 24), rotationY = 0 },
		-- spur: stands against main street beside the clock tower, so a single point draws nothing
		-- (INTERFACES amendment P2)
		fireHydrant = {
			position = Vector3.new(-8, 0, -24),
			rotationY = 0,
			spur = { Vector3.new(-8, 0, -24) },
		},

		-- civic back row looking down the street toward the hub
		-- spur: out across the pad, then along the pad's edge to the ring road
		cinema = {
			position = Vector3.new(-32, 0, 44),
			rotationY = 0,
			spur = { Vector3.new(-32, 0, 44), Vector3.new(-32, 0, 35.5), Vector3.new(-51, 0, 35.5) },
		},
		-- spur: hemmed in by its own front, the grocery and both neighbouring pads, so no legal spur
		-- exists (INTERFACES amendment P2)
		bank = {
			position = Vector3.new(-16, 0, 44),
			rotationY = 0,
			spur = { Vector3.new(-16, 0, 33) },
		},
		departmentStore = { position = Vector3.new(0, 0, 44), rotationY = 0 },
		-- spur: hemmed in like the bank, by the laundromat and both neighbouring pads (INTERFACES
		-- amendment P2)
		radioStation = {
			position = Vector3.new(16, 0, 44),
			rotationY = 0,
			spur = { Vector3.new(16, 0, 33) },
		},
		-- spur: out across the pad, then along the pad's edge to the ring road
		fireStation = {
			position = Vector3.new(32, 0, 44),
			rotationY = 0,
			spur = { Vector3.new(32, 0, 44), Vector3.new(32, 0, 35.5), Vector3.new(51, 0, 35.5) },
		},

		-- west service lane: car businesses with bays facing the street
		-- spur: driveway to the boulevard; the building itself blocks the ring side
		carDealership = {
			position = Vector3.new(-40, 0, -32),
			rotationY = 270,
			spur = {
				Vector3.new(-40, 0, -32),
				Vector3.new(-31, 0, -32),
				Vector3.new(-31, 0, -54.5),
			},
		},
		-- spur: side street between the dealership and the repair shop out to the ring
		autoRepair = {
			position = Vector3.new(-40, 0, -12),
			rotationY = 270,
			spur = {
				Vector3.new(-40, 0, -12),
				Vector3.new(-31, 0, -12),
				Vector3.new(-31, 0, -22),
				Vector3.new(-51, 0, -22),
			},
		},
		-- spur: side street between the repair shop and the alley out to the ring
		bowlingAlley = {
			position = Vector3.new(-40, 0, 8),
			rotationY = 270,
			spur = {
				Vector3.new(-40, 0, 8),
				Vector3.new(-31, 0, 8),
				Vector3.new(-31, 0, -2),
				Vector3.new(-51, 0, -2),
			},
		},

		-- east service lane: transit and signage
		-- spur: driveway to the boulevard, mirroring the car dealership
		busLine = {
			position = Vector3.new(40, 0, -32),
			rotationY = 90,
			spur = { Vector3.new(40, 0, -32), Vector3.new(31, 0, -32), Vector3.new(31, 0, -54.5) },
		},
		-- spur: side street across the empty east lot out to the ring
		neonDistrict = {
			position = Vector3.new(40, 0, 8),
			rotationY = 90,
			spur = {
				Vector3.new(40, 0, 8),
				Vector3.new(31, 0, 8),
				Vector3.new(31, 0, -2),
				Vector3.new(51, 0, -2),
			},
		},
		-- spur: side street between the billboard and the fire station out to the ring
		billboardSign = {
			position = Vector3.new(40, 0, 20),
			rotationY = 90,
			spur = {
				Vector3.new(40, 0, 20),
				Vector3.new(31, 0, 20),
				Vector3.new(31, 0, 29),
				Vector3.new(51, 0, 29),
			},
		},

		-- monument at the mouth of main street, facing arriving players
		-- spur: stands on main street at its mouth, so a single point draws nothing (INTERFACES
		-- amendment P2)
		clockTower = {
			position = Vector3.new(0, 0, -30),
			rotationY = 0,
			spur = { Vector3.new(0, 0, -30) },
		},
	},
	-- Street plan (M9 city dressing, wave 1b). Roads grow with the buildings: only the stretches
	-- from
	-- the entrance (the first point below) to each owned building's path are drawn, straight
	-- asphalt
	-- with kit tiles. Main street is exactly one road wide between the storefront pads
	-- (road.width/2
	-- + 1 either side) and its median slots (paveMainStreet, streetlampRow, trafficLights) are
	-- road
	-- pieces meant to stand on it (INTERFACES amendment P1). The monument and the service lots
	-- fill
	-- the rest of the town, so the other roads run as a ring behind them.
	streets = {
		-- 1: the entrance beside the Sign, the boulevard east and the east ring road up to the fire
		-- station. Roads grow with the buildings, so the ring stops where the last path joins it.
		{
			points = {
				Vector3.new(0, 0, -54.5),
				Vector3.new(51, 0, -54.5),
				Vector3.new(51, 0, 35.5),
			},
		},
		-- 2: main street, from the boulevard over Pave Main Street's tile and under the clock
		-- tower at its mouth, up to the department store (INTERFACES amendment P3).
		{ points = { Vector3.new(0, 0, -54.5), Vector3.new(0, 0, 28) } },
		-- 3: the boulevard west and the west ring road up to the cinema, mirroring the east.
		{
			points = {
				Vector3.new(0, 0, -54.5),
				Vector3.new(-51, 0, -54.5),
				Vector3.new(-51, 0, 35.5),
			},
		},
	},
	-- Frontage houses face the boulevard first, where arriving players see them, then the empty
	-- pockets beside the service lots fill in.
	lots = {
		{ position = Vector3.new(-21, 0, -45.5), rotationY = 0, tier = 2 },
		{ position = Vector3.new(22.5, 0, -45.5), rotationY = 0, tier = 2 },
		{ position = Vector3.new(-41, 0, -45.5), rotationY = 0, tier = 3 },
		{ position = Vector3.new(41, 0, -45.5), rotationY = 0, tier = 3 },
		{ position = Vector3.new(42, 0, -21.5), rotationY = 270, tier = 4 },
		{ position = Vector3.new(-42, 0, 18.5), rotationY = 90, tier = 4 },
		{ position = Vector3.new(42, 0, -11), rotationY = 270, tier = 5 },
		{ position = Vector3.new(12.5, 0, -45.5), rotationY = 0, tier = 5 },
	},
	-- A park on the empty lot behind the motel and grocery.
	plazas = {
		{ position = Vector3.new(-29.5, 0, 23), rotationY = 0, tier = 3, prop = "PlazaA" },
	},
	-- A full main street leaves only small gaps: beside the clock tower, the empty east lot, the
	-- west
	-- park's corner and the two back corners inside the ring.
	treeZones = {
		{ center = Vector3.new(-20, 0, -33), radius = 4, count = 4 },
		{ center = Vector3.new(17, 0, -31), radius = 5, count = 6 },
		{ center = Vector3.new(29, 0, -16), radius = 5, count = 6 },
		{ center = Vector3.new(-44, 0, 27), radius = 3, count = 3 },
		{ center = Vector3.new(-42, 0, 45), radius = 3, count = 3 },
		{ center = Vector3.new(42, 0, 45), radius = 3, count = 3 },
	},
}
