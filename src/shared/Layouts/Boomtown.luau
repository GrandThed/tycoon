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
		-- spur: driveway south onto the cross street, which is what makes the cross street's west
		-- arm grow (nothing else joins it)
		carDealership = {
			position = Vector3.new(-40, 0, -32),
			rotationY = 270,
			spur = {
				Vector3.new(-40, 0, -32),
				Vector3.new(-31, 0, -32),
				Vector3.new(-31, 0, -42),
			},
		},
		-- spur: out of the bay and onto the head of its own service lane (z = -22); the lane, not
		-- the ring, is now the nearest street, so the path is half as long as the old dogleg
		autoRepair = {
			position = Vector3.new(-40, 0, -12),
			rotationY = 270,
			spur = {
				Vector3.new(-40, 0, -12),
				Vector3.new(-31, 0, -12),
				Vector3.new(-31, 0, -22),
			},
		},
		-- spur: out of the bay and onto the head of the other west service lane (z = -2)
		bowlingAlley = {
			position = Vector3.new(-40, 0, 8),
			rotationY = 270,
			spur = {
				Vector3.new(-40, 0, 8),
				Vector3.new(-31, 0, 8),
				Vector3.new(-31, 0, -2),
			},
		},

		-- east service lane: transit and signage
		-- spur: driveway south onto the cross street, mirroring the car dealership, and the only
		-- thing that grows the cross street's east arm
		busLine = {
			position = Vector3.new(40, 0, -32),
			rotationY = 90,
			spur = { Vector3.new(40, 0, -32), Vector3.new(31, 0, -32), Vector3.new(31, 0, -42) },
		},
		-- spur: driveway onto the head of the east service lane
		neonDistrict = {
			position = Vector3.new(40, 0, 8),
			rotationY = 90,
			spur = {
				Vector3.new(40, 0, 8),
				Vector3.new(31, 0, 8),
				Vector3.new(31, 0, -2),
			},
		},
		-- spur: straight out behind the hoarding onto the back lane; the old three-leg dogleg round
		-- the front was the plot's longest path (38 studs) and joined the ring where nothing else did
		billboardSign = {
			position = Vector3.new(40, 0, 20),
			rotationY = 90,
			spur = { Vector3.new(40, 0, 20), Vector3.new(40, 0, 29.5) },
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
	-- Street plan (M9 city dressing, wave 1b, cross streets added in wave 1e). Roads grow with the
	-- buildings: only the stretches from the entrance (polyline 1's first point) to each owned
	-- building's path are drawn, straight asphalt. Main street is exactly one road wide between the
	-- storefront pads (road.width/2 + 1 either side) and its median slots (paveMainStreet,
	-- streetlampRow, trafficLights) are road pieces meant to stand on it (INTERFACES amendment P1).
	--
	-- Two rules shape the grid, and both are why it looks the way it does:
	--  * A street is only ever drawn where it is on a *shortest path* from the entrance to an
	--    owned building's join, so what a finished plot shows is a spanning tree. A closed block
	--    would lose exactly one of its stretches to that tree and leave a permanent gap in a road,
	--    so no street below closes a loop: each is either the ring or a dead end that stops at the
	--    driveway which grows it.
	--  * The storefront rows (x = +/-16) and their pads (x = +/-8) wall main street in from
	--    z = -25.5 to z = 36 -- nothing can clear both by road.width / 2 + 1 in that band, the
	--    Install Traffic Lights slot at (0, 24) included -- and the dealership and bus yard close
	--    z = -41.5 to -22.5 out to the ring. z = -42 is the one line left, which is why the town
	--    has exactly one four-way and it sits at the clock tower's block.
	streets = {
		-- 1: main street, from the entrance beside the Sign over Pave Main Street's tile and under
		-- the clock tower, up to the department store (INTERFACES amendment P3).
		{ points = { Vector3.new(0, 0, -54.5), Vector3.new(0, 0, 28) } },
		-- 2: the ring, one road: up the west side past the cinema, back down to the front edge,
		-- across the front through the entrance and up the east side to the fire station. Written
		-- as one polyline so the two crossing lanes below still fit in the 5-polyline budget; the
		-- entrance is the T where main street meets it.
		{
			points = {
				Vector3.new(-51, 0, 35.5),
				Vector3.new(-51, 0, -54.5),
				Vector3.new(0, 0, -54.5),
				Vector3.new(51, 0, -54.5),
				Vector3.new(51, 0, 35.5),
			},
		},
		-- 3: the cross street, the town's one four-way: west and east out of main street at
		-- z = -42, each arm ending at the dealership / bus yard driveway that grows it. It stops
		-- 20 studs short of the ring on purpose: reaching it would close a block (see above).
		{ points = { Vector3.new(-31, 0, -42), Vector3.new(0, 0, -42), Vector3.new(31, 0, -42) } },
		-- 4: the two west service lanes off the ring, one polyline: in to the repair shop's
		-- driveway at z = -22, down the ring (a run it shares with polyline 2, so it draws once),
		-- and in again to the bowling alley's at z = -2. Two T crossings for one polyline.
		{
			points = {
				Vector3.new(-31, 0, -2),
				Vector3.new(-51, 0, -2),
				Vector3.new(-51, 0, -22),
				Vector3.new(-31, 0, -22),
			},
		},
		-- 5: the east service lanes, one polyline like 4: in to the neon district's driveway at
		-- z = -2, up the ring (shared run, drawn once) and in again behind the hoarding at
		-- z = 29.5, the last strip the fire station's pad leaves clear.
		{
			points = {
				Vector3.new(31, 0, -2),
				Vector3.new(51, 0, -2),
				Vector3.new(51, 0, 29.5),
				Vector3.new(40, 0, 29.5),
			},
		},
	},
	-- Frontage houses: the pair the ring's front leg still has room for either side of the cross
	-- street, two more facing the cross street from the clock tower's block, the east lay-by and
	-- the two quiet corners by the bowling alley and the cinema.
	lots = {
		{ position = Vector3.new(-41, 0, -45.5), rotationY = 0, tier = 2 },
		{ position = Vector3.new(41, 0, -45.5), rotationY = 0, tier = 2 },
		{ position = Vector3.new(-20, 0, -32), rotationY = 0, tier = 3 },
		{ position = Vector3.new(20, 0, -32), rotationY = 0, tier = 3 },
		{ position = Vector3.new(42, 0, -21.5), rotationY = 270, tier = 4 },
		{ position = Vector3.new(-42, 0, 18.5), rotationY = 90, tier = 4 },
		{ position = Vector3.new(42, 0, -11), rotationY = 270, tier = 5 },
		{ position = Vector3.new(-44, 0, 44), rotationY = 0, tier = 5 },
	},
	-- A park on the empty lot behind the motel and grocery.
	plazas = {
		{ position = Vector3.new(-29.5, 0, 23), rotationY = 0, tier = 3, prop = "PlazaA" },
	},
	-- Main street, the cross street and the service lanes fill the town centre, so the greenery is
	-- the east lot, the two pockets beside the west park, and the treeline along the back fence
	-- behind the civic row. The clock tower's block, which used to hold two groves, is now the
	-- cross street and the two houses that face it.
	treeZones = {
		{ center = Vector3.new(31, 0, -16), radius = 5, count = 6 },
		{ center = Vector3.new(-25, 0, 12), radius = 3, count = 3 },
		{ center = Vector3.new(-44, 0, 27), radius = 3, count = 3 },
		{ center = Vector3.new(-23, 0, 53), radius = 5, count = 5 },
		{ center = Vector3.new(14, 0, 53), radius = 5, count = 5 },
		{ center = Vector3.new(46, 0, 46), radius = 4, count = 4 },
	},
}
