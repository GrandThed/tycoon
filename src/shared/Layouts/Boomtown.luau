--!strict
-- Era 2 (Boomtown) plot layout: the M12 growth layout, candidate "organic" (docs/CITY_GROWTH.md
-- section 2.5 and 3, INTERFACES "Wave 2.1 -- Boomtown growth-layout mock"). Positions are studs
-- relative to the plot centre, Y at ground level. rotationY is Roblox-native
-- CFrame.Angles(0, rad(r), 0): 0 faces -Z (the plot's front/hub edge), positive turns
-- counterclockwise seen from above (90 faces -X, 270 faces +X). Pads spawn padOffset studs along
-- that facing, placed unrotated.
--
-- A prairie town that grew along two old farm roads. Main Street comes in from the entrance,
-- leans 12 degrees west between its two crossroads and straightens again for the last block up to
-- the clock tower, which closes it and looks back down it. The old farm road crosses first: west it
-- dips a lot row on its way out to the cinema, east it is the service road, with the gas station,
-- the dealership and the billboard in a row before it curls down to the repair shop in the front
-- corner. Second Street crosses next: west it runs out to the bowling alley, with Radio Lane, the
-- one curving close, climbing off it to the radio station; east it rises a lot row to the fire
-- station and the bus yard at the edge of town.
--
-- Three rules shape it, and each is why it looks the way it does:
--  * Slot k stands roughly k-th along the streets from the entrance, so the town spreads from Main
--    Street's mouth: the heart at tier 1, both crossroads and the inner half of every arm at tier
--    2, the farm road's two ends at tier 3, Second Street's ends and the last block at tier 4, the
--    clock tower and Radio Lane at tier 5. The exceptions: the grocery and the laundromat stand
--    out on Second Street (see the grocery), the billboard and the neon sign fill sites on streets
--    already drawn, and the clock tower, bought last, is nearer than Second Street's ends.
--  * Roads are drawn only on shortest paths from the entrance to owned landmarks' joins, so the
--    plan is a tree: every arm is a dead end, and each ends at the join of the landmark that grows
--    it. Lots stand only on stretches some landmark draws.
--  * Lot rows are 6.6 studs deep. The two crossroads sit 41.5 apart and every bend moves a street
--    by exactly one row (14.1 along, 6.6 across, 25 degrees), so the rows on both sides of a
--    street stay whole wherever it goes. The bends are where no landmark stands.
--
-- Every landmark is square to the compass. The next-pad marker (fabric.marker.offset 4.1) only
-- clears an unrotated pad while its slot is within about 3.5 degrees of an axis, so a landmark
-- cannot turn to face an angled street. The two on Main Street's leaning leg (diner, barber shop)
-- therefore keep their compass facing and send their path square to the street instead; every
-- other landmark stands on a leg that runs north or east.
--
-- `district` is the fabric district a landmark pulls its neighbours toward; the three street
-- upgrades have none, a one-point spur and a pad on ground nothing else uses.
return {
	plotSize = Vector3.new(120, 1, 120),
	baseColor = Color3.fromRGB(173, 138, 93),
	padSize = Vector3.new(6, 0.5, 6),
	padOffset = 8,
	placeholderSize = Vector3.new(8, 8, 8),
	slots = {
		-- the heart: the newsstand at Main Street's mouth, facing the hot dog stand across it
		newsstand = {
			position = Vector3.new(-15.05, 0, -49.1),
			rotationY = 270,
			district = "main",
		},
		-- the other half of the heart, a step further in so its marker clears the paving pad
		hotDogStand = {
			position = Vector3.new(15.05, 0, -48.7),
			rotationY = 90,
			district = "main",
		},
		-- first on the leaning leg, just above the crossroads. Compass-square (see the header), so
		-- its path runs square to the street rather than straight out of the door
		diner = {
			position = Vector3.new(-17.81, 0, -18.09),
			rotationY = 270,
			district = "main",
			spur = { Vector3.new(-17.81, 0, -18.09), Vector3.new(-2.7, 0, -14.88) },
		},
		-- the corner of the service road: first in its row, fronts to the south
		gasStation = {
			position = Vector3.new(21.5, 0, -12.55),
			rotationY = 0,
			district = "industry",
		},
		-- the roadside motel on the farm road west, where the houses begin
		motel = { position = Vector3.new(-29.5, 0, -12.55), rotationY = 0, district = "suburb" },
		-- streetOnly: no model and no path (one-point spur). Its pad stands at the plot's front
		-- edge east of the entrance, ahead of the hot dog stand's own pad, where no lot fits
		paveMainStreet = {
			position = Vector3.new(7.05, 0, -49),
			rotationY = 0,
			spur = { Vector3.new(7.05, 0, -49) },
		},
		-- top of the leaning leg, across from the diner's terrace; compass-square with a path
		-- square to the street, like the diner
		barberShop = {
			position = Vector3.new(8.89, 0, 4.95),
			rotationY = 90,
			district = "main",
			spur = { Vector3.new(8.89, 0, 4.95), Vector3.new(-6.22, 0, 1.75) },
		},
		-- a hydrant on the farm road's south side, between the motel and the heart, where two joins
		-- already pull the lots round it
		fireHydrant = {
			position = Vector3.new(-25.5, 0, -42.65),
			rotationY = 180,
			district = "suburb",
		},
		-- the grocery on Second Street east. It stands 32 studs out on purpose: lots only build on
		-- a stretch that is drawn, and a stretch is drawn up to a join, so this far out its block
		-- starts building with it at tier 2
		groceryStore = { position = Vector3.new(23, 0, 28.95), rotationY = 0, district = "suburb" },
		-- Second Street west, south side: the bank's lot takes the north side here
		laundromat = {
			position = Vector3.new(-28, 0, -1.15),
			rotationY = 180,
			district = "suburb",
		},
		-- second in the service road's row
		carDealership = {
			position = Vector3.new(32, 0, -12.55),
			rotationY = 0,
			district = "industry",
		},
		-- streetOnly: its pad is on Second Street's south side just east of the crossroads it
		-- signals, past Main Street's last shop
		trafficLights = {
			position = Vector3.new(18, 0, 14.9),
			rotationY = 0,
			spur = { Vector3.new(18, 0, 14.9) },
		},
		-- closes the farm road west; its path is what draws that arm to its end
		cinema = { position = Vector3.new(-54.5, 0, -19.15), rotationY = 0, district = "suburb" },
		-- streetOnly: its pad is on the farm road's south side at the heart, between Main Street's
		-- shops and the hydrant
		streetlampRow = {
			position = Vector3.new(-16, 0, -42.65),
			rotationY = 180,
			spur = { Vector3.new(-16, 0, -42.65) },
		},
		-- closes the service road in the front corner, facing back up it; its path is what draws
		-- the curl, at tier 3
		autoRepair = {
			position = Vector3.new(48, 0, -54.05),
			rotationY = 180,
			district = "industry",
		},
		-- closes Second Street west, on its south side at the plot's edge
		bowlingAlley = {
			position = Vector3.new(-54.5, 0, -1.15),
			rotationY = 180,
			district = "suburb",
		},
		-- the bus yard at Second Street's east end, backing onto the service road's block; its path
		-- draws that arm to its end at tier 4, a tier before the fire station
		busLine = { position = Vector3.new(54.5, 0, 5.45), rotationY = 180, district = "industry" },
		-- flanks the clock tower's approach, at the head of Main Street
		bank = { position = Vector3.new(-23.85, 0, 31.1), rotationY = 270, district = "main" },
		-- across the approach from the bank
		departmentStore = {
			position = Vector3.new(6.25, 0, 31.1),
			rotationY = 90,
			district = "main",
		},
		-- third in the service road's row, where the road starts to curl: a roadside billboard on a
		-- stretch the repair shop already draws
		billboardSign = {
			position = Vector3.new(42.5, 0, -12.55),
			rotationY = 0,
			district = "industry",
		},
		-- heads Radio Lane in the back-west corner, where its mast stands clear of everything
		radioStation = {
			position = Vector3.new(-41, 0, 48.05),
			rotationY = 0,
			district = "suburb",
		},
		-- Second Street's east end, north side, at the plot's edge: tall against the fields
		fireStation = { position = Vector3.new(54.5, 0, 35.55), rotationY = 0, district = "civic" },
		-- the neon sign across the road from the cinema
		neonDistrict = {
			position = Vector3.new(-54.5, 0, -49.25),
			rotationY = 180,
			district = "suburb",
		},
		-- the monument: closes Main Street and faces the entrance down its last block
		clockTower = { position = Vector3.new(-8.8, 0, 51.55), rotationY = 0, district = "civic" },
	},
	streets = {
		-- 1: Main Street. In from the entrance beside the Sign and north to the first crossroads,
		-- 12 degrees west of north up to Second Street, then north again for the last block; the
		-- clock tower stands past its end.
		{
			points = {
				Vector3.new(0, 0, -54.5),
				Vector3.new(0, 0, -27.6),
				Vector3.new(-8.8, 0, 13.9),
				Vector3.new(-8.8, 0, 36.5),
			},
		},
		-- 2: the old farm road, crossing at the heart. West: level past the motel, down one lot row
		-- on a diagonal and out to the cinema, whose path ends it. East: the service road, level
		-- past the gas station, the dealership and the billboard, then curling down toward the
		-- front corner, where the repair shop closes it.
		{
			points = {
				Vector3.new(-54.5, 0, -34.2),
				Vector3.new(-46.1, 0, -34.2),
				Vector3.new(-32, 0, -27.6),
				Vector3.new(0, 0, -27.6),
				Vector3.new(43, 0, -27.6),
				Vector3.new(48, 0, -39),
			},
		},
		-- 3: Second Street, crossing where Main Street straightens. West: level out to the bowling
		-- alley. East: level past the grocery, up one lot row on a diagonal and out to the fire
		-- station and the bus yard.
		{
			points = {
				Vector3.new(-54.5, 0, 13.9),
				Vector3.new(-8.8, 0, 13.9),
				Vector3.new(30, 0, 13.9),
				Vector3.new(44.1, 0, 20.5),
				Vector3.new(54.5, 0, 20.5),
			},
		},
		-- 4: Radio Lane, the suburban close: off Second Street west, leaning in and then north,
		-- with the radio station past its end.
		{
			points = {
				Vector3.new(-38, 0, 13.9),
				Vector3.new(-41, 0, 25),
				Vector3.new(-41, 0, 33),
			},
		},
	},
}
