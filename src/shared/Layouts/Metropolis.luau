--!strict
-- Era 3 (Metropolis) plot layout. Positions are studs relative to plot center, Y at
-- ground level. rotationY is Roblox-native CFrame.Angles(0, rad(r), 0): 0 faces -Z
-- (the plot's front/hub edge), positive turns counterclockwise seen from above
-- (90 faces -X, 270 faces +X). Pads spawn padOffset studs along that facing.
-- Personality: dense downtown blocks on a 4x4 grid (columns x = +/-14, +/-42; rows
-- z = +/-14, +/-42) with two crossing avenues at x = 0 and z = 0 for transit
-- unlocks and green space. Every block faces its nearest avenue; the skyscraper
-- rises front-and-center. Asphalt-gray base for the era swap.
return {
	plotSize = Vector3.new(120, 1, 120),
	baseColor = Color3.fromRGB(88, 90, 94),
	padSize = Vector3.new(6, 0.5, 6),
	padOffset = 8,
	placeholderSize = Vector3.new(8, 8, 8),
	slots = {
		-- front row of blocks (z = -42)
		cornerShop = { position = Vector3.new(-42, 0, -42), rotationY = 270 },
		foodTruck = { position = Vector3.new(-14, 0, -42), rotationY = 270 },
		coffeeShop = { position = Vector3.new(14, 0, -42), rotationY = 90 },
		apartmentBlockA = { position = Vector3.new(42, 0, -42), rotationY = 90 },

		-- second row (z = -14)
		apartmentBlockB = { position = Vector3.new(-42, 0, -14), rotationY = 270 },
		officeLowRise = { position = Vector3.new(-14, 0, -14), rotationY = 270 },
		supermarket = { position = Vector3.new(14, 0, -14), rotationY = 90 },
		parkingGarage = { position = Vector3.new(42, 0, -14), rotationY = 90 },

		-- third row (z = 14)
		officeTowerA = { position = Vector3.new(-42, 0, 14), rotationY = 270 },
		shoppingMall = { position = Vector3.new(-14, 0, 14), rotationY = 270 },
		hospital = { position = Vector3.new(14, 0, 14), rotationY = 90 },
		hotelTower = { position = Vector3.new(42, 0, 14), rotationY = 90 },

		-- back row (z = 42)
		stadium = { position = Vector3.new(-42, 0, 42), rotationY = 270 },
		conventionCenter = { position = Vector3.new(-14, 0, 42), rotationY = 270 },
		bankTower = { position = Vector3.new(14, 0, 42), rotationY = 90 },
		broadcastTower = { position = Vector3.new(42, 0, 42), rotationY = 90 },

		-- avenue medians: transit unlocks and green space between the blocks
		cityGrid = { position = Vector3.new(0, 0, 0), rotationY = 180 },
		subwayLine = { position = Vector3.new(-28, 0, 0), rotationY = 0 },
		highwayRamp = { position = Vector3.new(28, 0, 0), rotationY = 0 },
		financeDistrict = { position = Vector3.new(0, 0, 28), rotationY = 180 },
		busStop = { position = Vector3.new(-28, 0, -28), rotationY = 0 },
		cityPark = { position = Vector3.new(28, 0, 28), rotationY = 0 },
		rooftopGarden = { position = Vector3.new(-28, 0, 28), rotationY = 0 },

		-- monument on the front avenue, crowning the skyline toward the hub
		skyscraper = { position = Vector3.new(0, 0, -30), rotationY = 0 },
	},
}
