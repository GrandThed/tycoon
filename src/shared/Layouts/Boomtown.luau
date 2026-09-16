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
		-- spur: from the pad's back corner so the stub clears the fire hydrant
		newsstand = {
			position = Vector3.new(-16, 0, -16),
			rotationY = 270,
			spur = { Vector3.new(-5, 0, -14), Vector3.new(0, 0, -14) },
		},
		diner = { position = Vector3.new(-16, 0, 0), rotationY = 270 },
		motel = { position = Vector3.new(-16, 0, 16), rotationY = 270 },
		groceryStore = { position = Vector3.new(-16, 0, 28), rotationY = 270 },

		-- east storefront column, doors opening west onto main street
		hotDogStand = { position = Vector3.new(16, 0, -16), rotationY = 90 },
		gasStation = { position = Vector3.new(16, 0, 0), rotationY = 90 },
		barberShop = { position = Vector3.new(16, 0, 16), rotationY = 90 },
		laundromat = { position = Vector3.new(16, 0, 28), rotationY = 90 },

		-- street furniture down the median
		-- spur: the road tile lies on the boulevard itself, so a single point draws nothing
		-- (INTERFACES amendment P2)
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
		-- spur: down the clock tower's west flank to the boulevard; the auto route cuts the tower
		fireHydrant = {
			position = Vector3.new(-8, 0, -24),
			rotationY = 0,
			spur = { Vector3.new(-11, 0, -35), Vector3.new(-11, 0, -54.5) },
		},

		-- civic back row looking down the street toward the hub
		-- spur: past the pad's corner out to the ring road
		cinema = {
			position = Vector3.new(-32, 0, 44),
			rotationY = 0,
			spur = { Vector3.new(-35, 0, 35.5), Vector3.new(-51, 0, 35.5) },
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
		-- spur: past the pad's corner out to the ring road
		fireStation = {
			position = Vector3.new(32, 0, 44),
			rotationY = 0,
			spur = { Vector3.new(35, 0, 35.5), Vector3.new(51, 0, 35.5) },
		},

		-- west service lane: car businesses with bays facing the street
		-- spur: driveway to the boulevard; the building itself blocks the ring side
		carDealership = {
			position = Vector3.new(-40, 0, -32),
			rotationY = 270,
			spur = { Vector3.new(-31, 0, -35), Vector3.new(-31, 0, -54.5) },
		},
		-- spur: side street between the dealership and the repair shop out to the ring
		autoRepair = {
			position = Vector3.new(-40, 0, -12),
			rotationY = 270,
			spur = { Vector3.new(-31, 0, -15), Vector3.new(-31, 0, -22), Vector3.new(-51, 0, -22) },
		},
		-- spur: side street between the repair shop and the alley out to the ring
		bowlingAlley = {
			position = Vector3.new(-40, 0, 8),
			rotationY = 270,
			spur = { Vector3.new(-31, 0, 5), Vector3.new(-31, 0, -2), Vector3.new(-51, 0, -2) },
		},

		-- east service lane: transit and signage
		-- spur: driveway to the boulevard, mirroring the car dealership
		busLine = {
			position = Vector3.new(40, 0, -32),
			rotationY = 90,
			spur = { Vector3.new(31, 0, -35), Vector3.new(31, 0, -54.5) },
		},
		-- spur: side street across the empty east lot out to the ring
		neonDistrict = {
			position = Vector3.new(40, 0, 8),
			rotationY = 90,
			spur = { Vector3.new(31, 0, 5), Vector3.new(31, 0, -2), Vector3.new(51, 0, -2) },
		},
		-- spur: side street between the billboard and the fire station out to the ring
		billboardSign = {
			position = Vector3.new(40, 0, 20),
			rotationY = 90,
			spur = { Vector3.new(31, 0, 23), Vector3.new(31, 0, 29), Vector3.new(51, 0, 29) },
		},

		-- monument at the mouth of main street, facing arriving players
		clockTower = { position = Vector3.new(0, 0, -30), rotationY = 0 },
	},
	-- Street plan (M9 city dressing). Spine i appears at growth tier i. Main street is exactly one
	-- road wide between the storefront pads (road.width/2 + 1 either side), and its median slots
	-- (paveMainStreet, streetlampRow, trafficLights) are road pieces meant to stand on it, so
	-- spines
	-- 1 and 2 cover them (INTERFACES amendment P1); every other clearance rule holds. The monument
	-- and the service lots fill the rest of the town, so the other roads run as a ring behind
	-- them.
	streets = {
		-- 1: front boulevard along the hub edge. Pave Main Street's road tile leads straight up from
		-- it
		-- to the clock tower, and that is the monument's own spur, so the approach reads as one road.
		{ points = { Vector3.new(-51, 0, -54.5), Vector3.new(51, 0, -54.5) } },
		-- 2: main street, from behind the clock tower to the department store.
		{ points = { Vector3.new(0, 0, -15), Vector3.new(0, 0, 28) } },
		-- 3: west ring road behind the service lots; their side streets are spurs.
		{ points = { Vector3.new(-51, 0, -54.5), Vector3.new(-51, 0, 54) } },
		-- 4: east ring road, mirroring the west.
		{ points = { Vector3.new(51, 0, -54.5), Vector3.new(51, 0, 54) } },
		-- 5: back lane closing the ring, so traffic loops instead of turning round at dead ends.
		{ points = { Vector3.new(-51, 0, 54), Vector3.new(51, 0, 54) } },
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
