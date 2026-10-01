--!strict
-- Era 2 (Boomtown) plot layout: the M12 growth layout, organic, bolder pass (docs/CITY_GROWTH.md
-- sections 2.5 and 3; INTERFACES "Wave 2.2 -- Layout, bolder pass"). Positions are studs relative
-- to the plot centre, Y at ground level. rotationY is Roblox-native CFrame.Angles(0, rad(r), 0): 0
-- faces -Z (the plot's front/hub edge), positive turns counterclockwise seen from above (90 faces
-- -X, 270 faces +X). Pads spawn padOffset studs along that facing, placed unrotated.
--
-- A prairie town that grew along an old road. Main Street comes in from the entrance, swings 16
-- degrees west between its two crossroads and straightens for the last block up to the clock
-- tower, which closes it with the fire station at its side and the green at its foot. The old
-- farm road crosses first: west it runs level past the motel and then swings up to the cinema,
-- east it climbs 12 degrees past the gas station and the barber to the grocery, and the front of
-- the plot on both sides of it is houses. Second Street crosses next and is the second shop
-- street: west to the bowling alley, east up to the car dealership, where the service road takes
-- over and curls away to the back-east corner, past the repair shop to the radio station. The
-- car yards and their sheds are all up there, behind the town.
--
-- What shapes it:
--  * Every landmark faces its street square on, whatever the street's angle, and none has its
--    back to the hub: the ones on the cross streets stand on the far side and look back at it,
--    the ones on Main Street look across it.
--  * Slot k stands roughly k-th along the streets from the entrance: the heart at tier 1, both
--    crossroads and the inner half of every arm at tier 2, the farm road's west end and the
--    service road at tier 3, Second Street's west end and Main Street's last block at tier 4, and
--    at tier 5 only the service road's last few studs and two driveways. The exceptions: the
--    grocery, bought ninth, closes the farm road east, because lots only build on a stretch that
--    is drawn and a stretch is drawn up to a join; the department store, bought late, fills a
--    site near the heart; the clock tower, bought last, is nearer than the radio station.
--  * Roads are drawn only on shortest paths from the entrance to owned landmarks' joins, so the
--    plan is a tree: each arm ends at the join of the landmark that grows it.
--  * Lot rows are 6.6 studs deep. The two crossroads are 43.5 apart measured square to the west
--    arms (a house row, three back rows and a shop row), and the arms on each side of Main
--    Street run parallel, so the rows between them stay whole. The west arms run level because a
--    landmark at the end of an arm that dips west would hang over the plot's edge.
--
-- `district` is the fabric district a landmark pulls its neighbours toward. The gas station is
-- tagged "main": it stands a block from the heart, and a shed yard does not belong there. The
-- seven street upgrades and city-changers have no model, no district and no path (a one-point
-- spur); each has a pad beside a street.
return {
	plotSize = Vector3.new(120, 1, 120),
	baseColor = Color3.fromRGB(173, 138, 93),
	padSize = Vector3.new(6, 0.5, 6),
	padOffset = 8,
	placeholderSize = Vector3.new(8, 8, 8),
	slots = {
		-- the heart: the newsstand at Main Street's mouth, facing the hot dog stand across it
		newsstand = {
			position = Vector3.new(-15.05, 0, -49.3),
			rotationY = 270,
			district = "main",
		},
		-- the other half of the heart, a little further in so its marker clears the paving pad
		hotDogStand = {
			position = Vector3.new(15.05, 0, -46.9),
			rotationY = 90,
			district = "main",
		},
		-- halfway up the leaning block, on the far side so its front shows from the hub; its join
		-- is what the shops above and below it grow on
		diner = { position = Vector3.new(-21.21, 0, -9.11), rotationY = 253.97, district = "main" },
		-- on the farm road east, a block from the heart. Tagged main, not industry: the lots round
		-- it grow homes and shops, and the sheds stay up by the service road
		gasStation = {
			position = Vector3.new(23.16, 0, -5.02),
			rotationY = 347.98,
			district = "main",
		},
		-- the roadside motel on the farm road west, just before the road swings up
		motel = { position = Vector3.new(-33, 0, -10.55), rotationY = 0, district = "suburb" },
		-- streetOnly: no model and no path (one-point spur). Its pad stands at the plot's front
		-- edge east of the entrance, ahead of the hot dog stand's own pad, where no lot fits
		paveMainStreet = {
			position = Vector3.new(7.05, 0, -49),
			rotationY = 0,
			spur = { Vector3.new(7.05, 0, -49) },
		},
		-- next along the farm road east; its join keeps the houses between the gas station and the
		-- grocery building
		barberShop = {
			position = Vector3.new(33.92, 0, -2.73),
			rotationY = 347.98,
			district = "main",
		},
		-- streetOnly city-changer (Install Fire Hydrants): its pad is on the farm road's near side,
		-- west of the heart
		fireHydrant = {
			position = Vector3.new(-31, 0, -40.95),
			rotationY = 180,
			spur = { Vector3.new(-31, 0, -40.95) },
		},
		-- closes the farm road east. Bought ninth and the farthest of its tier on purpose: its path
		-- draws the whole east arm at tier 2, so that side builds early
		groceryStore = {
			position = Vector3.new(51.33, 0, 0.56),
			rotationY = 347.98,
			district = "suburb",
		},
		-- Second Street west, the join its shops grow on
		laundromat = { position = Vector3.new(-36, 0, 32.65), rotationY = 0, district = "suburb" },
		-- the end of the shop street and the start of the service road: the first of the car yards
		carDealership = {
			position = Vector3.new(11.34, 0, 38.59),
			rotationY = 348.05,
			district = "industry",
		},
		-- streetOnly: its pad is on the farm road's near side just east of the crossroads it
		-- signals
		trafficLights = {
			position = Vector3.new(22.12, 0, -36.96),
			rotationY = 180,
			spur = { Vector3.new(22.12, 0, -36.96) },
		},
		-- closes the farm road west; its path draws that arm to its end
		cinema = {
			position = Vector3.new(-52.38, 0, -8.05),
			rotationY = 8.05,
			district = "suburb",
		},
		-- streetOnly: its pad is on the farm road's near side between Main Street's shops and the
		-- hydrant pad
		streetlampRow = {
			position = Vector3.new(-21, 0, -40.95),
			rotationY = 180,
			spur = { Vector3.new(-21, 0, -40.95) },
		},
		-- the repair shop on the service road, at its bend
		autoRepair = {
			position = Vector3.new(36.34, 0, 44.13),
			rotationY = 348.08,
			district = "industry",
		},
		-- closes Second Street west; its path draws that arm to its end at tier 4
		bowlingAlley = {
			position = Vector3.new(-54.49, 0, 32.65),
			rotationY = 0,
			district = "suburb",
		},
		-- streetOnly city-changer (Open the Bus Line): its pad is on the service road's near side,
		-- opposite the car yards
		busLine = {
			position = Vector3.new(35.31, 0, 11.94),
			rotationY = 180,
			spur = { Vector3.new(35.31, 0, 11.94) },
		},
		-- the last block's east side, across Main Street from the green
		bank = { position = Vector3.new(2.55, 0, 31.6), rotationY = 90, district = "main" },
		-- the corner above the first crossroads. Bought late on a block drawn since tier 1, so it
		-- adds no street
		departmentStore = {
			position = Vector3.new(12.38, 0, -11.94),
			rotationY = 73.97,
			district = "main",
		},
		-- streetOnly city-changer (Put Up Billboards): its pad is on the service road's near side
		-- past the bend
		billboardSign = {
			position = Vector3.new(48.13, 0, 15.08),
			rotationY = 180,
			spur = { Vector3.new(48.13, 0, 15.08) },
		},
		-- ends the service road in the back-east corner, its mast clear of everything
		radioStation = {
			position = Vector3.new(49.74, 0, 48.05),
			rotationY = 342.04,
			district = "suburb",
		},
		-- beside the clock tower, facing the hub; its driveway runs down and across to the head of
		-- Main Street, behind the green
		fireStation = { position = Vector3.new(-27, 0, 52), rotationY = 0, district = "civic" },
		-- streetOnly city-changer (Light the Neon District): its pad is at the head of Main Street,
		-- east of the clock tower's own pad
		neonDistrict = {
			position = Vector3.new(-2, 0, 49.6),
			rotationY = 0,
			spur = { Vector3.new(-2, 0, 49.6) },
		},
		-- the monument: closes Main Street and faces the entrance down its last block
		clockTower = { position = Vector3.new(-12.5, 0, 51.95), rotationY = 0, district = "civic" },
	},
	streets = {
		-- 1: Main Street. In from the entrance beside the Sign and north to the first crossroads,
		-- 16 degrees west of north up to Second Street, then north again for the last block; the
		-- clock tower stands past its end.
		{
			points = {
				Vector3.new(0, 0, -54.5),
				Vector3.new(0, 0, -25.9),
				Vector3.new(-12.5, 0, 17.6),
				Vector3.new(-12.5, 0, 36.9),
			},
		},
		-- 2: the old farm road, crossing at the heart. West it runs level past the motel, then
		-- swings up to the cinema at the plot's edge; east it climbs 12 degrees past the gas
		-- station and the barber to the grocery. Houses line its near side all the way.
		{
			points = {
				Vector3.new(-54.5, 0, -23),
				Vector3.new(-34, 0, -25.9),
				Vector3.new(0, 0, -25.9),
				Vector3.new(54.5, 0, -14.3),
			},
		},
		-- 3: Second Street, the second shop street, crossing where Main Street straightens. West,
		-- level, to the bowling alley; east up to the car dealership, where the service road takes
		-- over.
		{
			points = {
				Vector3.new(-54.5, 0, 17.6),
				Vector3.new(-12.5, 0, 17.6),
				Vector3.new(22, 0, 24.9),
			},
		},
		-- 4: the service road. On from Second Street's end past the repair shop, then curling
		-- toward the back-east corner, where the radio station ends it.
		{
			points = {
				Vector3.new(22, 0, 24.9),
				Vector3.new(40, 0, 28.7),
				Vector3.new(54.5, 0, 33.4),
			},
		},
	},
	-- The civic green: on the last block's west side at the foot of the clock tower and the fire
	-- station, in the corridor the entrance looks up. Tier 4, when that block is drawn.
	plazas = {
		{ position = Vector3.new(-23.8, 0, 27.1), rotationY = 0, tier = 4, prop = "PlazaA" },
	},
}
