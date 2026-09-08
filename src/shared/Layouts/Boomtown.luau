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
		paveMainStreet = { position = Vector3.new(0, 0, -46), rotationY = 0 },
		streetlampRow = { position = Vector3.new(0, 0, -8), rotationY = 0 },
		trafficLights = { position = Vector3.new(0, 0, 24), rotationY = 0 },
		fireHydrant = { position = Vector3.new(-8, 0, -24), rotationY = 0 },

		-- civic back row looking down the street toward the hub
		cinema = { position = Vector3.new(-32, 0, 44), rotationY = 0 },
		bank = { position = Vector3.new(-16, 0, 44), rotationY = 0 },
		departmentStore = { position = Vector3.new(0, 0, 44), rotationY = 0 },
		radioStation = { position = Vector3.new(16, 0, 44), rotationY = 0 },
		fireStation = { position = Vector3.new(32, 0, 44), rotationY = 0 },

		-- west service lane: car businesses with bays facing the street
		carDealership = { position = Vector3.new(-40, 0, -32), rotationY = 270 },
		autoRepair = { position = Vector3.new(-40, 0, -12), rotationY = 270 },
		bowlingAlley = { position = Vector3.new(-40, 0, 8), rotationY = 270 },

		-- east service lane: transit and signage
		busLine = { position = Vector3.new(40, 0, -32), rotationY = 90 },
		neonDistrict = { position = Vector3.new(40, 0, 8), rotationY = 90 },
		billboardSign = { position = Vector3.new(40, 0, 20), rotationY = 90 },

		-- monument at the mouth of main street, facing arriving players
		clockTower = { position = Vector3.new(0, 0, -30), rotationY = 0 },
	},
}
