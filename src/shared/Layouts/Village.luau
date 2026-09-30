--!strict
-- Era 1 (Village) plot layout: the M12 growth layout (docs/CITY_GROWTH.md section 2.5,
-- INTERFACES "M12 contracts" -> "Village layout"). Positions are studs relative to the plot
-- centre, Y at ground level. rotationY is Roblox-native CFrame.Angles(0, rad(r), 0): 0 faces -Z
-- (the plot's front/hub edge), positive turns counterclockwise seen from above. Pads spawn
-- padOffset studs along that facing, placed unrotated.
--
-- One village grown along one winding high street. The camp just inside the entrance is the
-- heart; the farm lane crosses the high street at its edge (fields and the mill east, a craft
-- lane west); the square halfway up has the well and the fountain facing each other across the
-- street, with the tavern and the market on its cross lane; the upper lane runs out past the
-- chapel and the manor and rises to the back corners, where the watchtower and the stables
-- stand; the castle keep closes the high street and looks down it. Slot k stands roughly k-th
-- along the streets from the entrance, so each purchase extends the town rather than filling a
-- grid, and landmarks alternate with parcel frontage (tools/fabric.py lays the parcels and the
-- woods; tools/streetplan.py checks every rule).
--
-- Every slot faces its street square on, set back so its unrotated pad clears the trail. The plan
-- is a tree: every street end is a landmark's path, so no stretch is drawn without a building.
-- `district` is the fabric district a landmark pulls its neighbours toward; the street upgrade
-- (dirtRoad) has none.
return {
	plotSize = Vector3.new(120, 1, 120),
	baseColor = Color3.fromRGB(106, 127, 63),
	padSize = Vector3.new(6, 0.5, 6),
	padOffset = 8,
	placeholderSize = Vector3.new(8, 8, 8),
	slots = {
		-- the heart: the camp fire just inside the entrance, across the high street from the tent
		campfire = { position = Vector3.new(-16.24, 0, -46.87), rotationY = 262, district = "camp" },
		-- the other half of the camp
		tentSmall = { position = Vector3.new(12.95, 0, -42.76), rotationY = 82, district = "camp" },
		-- next up the high street, backing onto the west woods
		woodcutterHut = {
			position = Vector3.new(-18.7, 0, -29.34),
			rotationY = 262,
			district = "craft",
		},
		-- the farm at the edge of the heart, just above the farm lane; its fields grow along it
		farmPlot = { position = Vector3.new(10.07, 0, -22.26), rotationY = 82, district = "farm" },
		-- the first house, on the corner below the square
		houseSmallA = {
			position = Vector3.new(-19.07, 0, -15.32),
			rotationY = 280,
			district = "home",
		},
		-- streetOnly: no model and no path (one-point spur). Its pad stands on the craft lane's
		-- north side just west of the heart, on a spot no street or parcel uses
		dirtRoad = {
			position = Vector3.new(-31.77, 0, -23.58),
			rotationY = 3.9,
			spur = { Vector3.new(-31.77, 0, -23.58) },
		},
		-- the square: the well on the west side, facing the fountain across the high street
		well = { position = Vector3.new(-17.62, 0, 2.62), rotationY = 259.8, district = "home" },
		-- streetOnly Plant Flowers: no model, no path, no district; its pad is by the craft lane
		flowerBed = {
			position = Vector3.new(-32.75, 0, -52.68),
			rotationY = 183.9,
			spur = { Vector3.new(-32.75, 0, -52.68) },
		},
		-- the farmhouse at the end of the farm lane
		houseSmallB = {
			position = Vector3.new(48.53, 0, -23.11),
			rotationY = 7.9,
			district = "farm",
		},
		-- by the fields, on the way to the mill
		bakery = { position = Vector3.new(23.2, 0, -49.33), rotationY = 187.9, district = "craft" },
		-- the mill at the end of the farm lane, out in the fields
		windmill = {
			position = Vector3.new(44.47, 0, -52.29),
			rotationY = 187.9,
			district = "farm",
		},
		-- the fountain, facing the well across the square
		villageSquare = {
			position = Vector3.new(11.58, 0, 7.87),
			rotationY = 79.8,
			district = "market",
		},
		-- the market on the square's east lane
		marketStall = {
			position = Vector3.new(24.22, 0, 2.24),
			rotationY = 358,
			district = "market",
		},
		-- streetOnly Plant Trees: no model, no path, no district. Its pad stands on the square's
		-- south-east corner by the high street; its rect only clears the woods
		treeOak = {
			position = Vector3.new(6, 0, 4),
			rotationY = 0,
			spur = { Vector3.new(6, 0, 4) },
		},
		-- the smithy at the end of the craft lane, by the woodcutter's woods
		blacksmith = {
			position = Vector3.new(-55.69, 0, -51.11),
			rotationY = 183.9,
			district = "craft",
		},
		-- the tavern closing the square's west lane
		tavern = { position = Vector3.new(-35.7, 0, 8.1), rotationY = 0, district = "market" },
		-- the trade cart at the east end of the square's lane: the road out
		tradeRoute = {
			position = Vector3.new(46.19, 0, 2.99),
			rotationY = 358,
			district = "market",
		},
		-- flanks the keep's approach; its path joins the high street's end with the keep's
		chapel = { position = Vector3.new(-17.66, 0, 31.31), rotationY = 275.9, district = "civic" },
		-- the manor, across the approach from the chapel
		houseLargeA = {
			position = Vector3.new(11.46, 0, 28.29),
			rotationY = 95.9,
			district = "home",
		},
		-- streetOnly Hang Banners: no model, no path; its pad is on the high street above the square
		bannerPole = {
			position = Vector3.new(-12, 0, 6),
			rotationY = 180,
			spur = { Vector3.new(-12, 0, 6) },
		},
		-- the back-east corner, at the top of the upper lane
		stables = { position = Vector3.new(41.35, 0, 40.84), rotationY = 345.9, district = "farm" },
		-- the back-west corner, at the top of the upper lane, over the woods
		watchtower = {
			position = Vector3.new(-46.01, 0, 48.55),
			rotationY = 21.9,
			district = "camp",
		},
		-- the wall gate on the upper lane's west arm, behind the chapel
		townWall = {
			position = Vector3.new(-27.48, 0, 41.08),
			rotationY = 21.9,
			district = "civic",
		},
		-- crowns the high street and faces the entrance down its last leg
		castleKeep = {
			position = Vector3.new(-1.57, 0, 44.56),
			rotationY = 5.9,
			district = "civic",
		},
	},
	streets = {
		-- 1: the high street, in from the hub edge through the camp to the farm lane. Then it winds
		-- west of north past the heart, east through the square, west beyond it, east to the keep
		{
			points = {
				Vector3.new(0, 0, -56.5),
				Vector3.new(-3, 0, -35.2),
				Vector3.new(-5, 0, -20.9),
				Vector3.new(-3, 0, -9.5),
				Vector3.new(-1.7, 0, -2.1),
				Vector3.new(-4.7, 0, 14.6),
				Vector3.new(-4, 0, 21.1),
				Vector3.new(-3.1, 0, 29.8),
			},
		},
		-- 2: the farm lane, crossing the high street at the heart: craft lane west, fields east
		{
			points = {
				Vector3.new(-54.7, 0, -36.6),
				Vector3.new(-26.8, 0, -38.5),
				Vector3.new(-3, 0, -35.2),
				Vector3.new(12.8, 0, -33),
				Vector3.new(46.5, 0, -37.7),
			},
		},
		-- 3: the square's lane, crossing halfway up: the tavern closes it west, the market east
		{
			points = {
				Vector3.new(-35.7, 0, -6.4),
				Vector3.new(-20.7, 0, -6.4),
				Vector3.new(-3, 0, -9.5),
				Vector3.new(14.7, 0, -12.6),
				Vector3.new(46.7, 0, -11.5),
			},
		},
		-- 4: the upper lane, crossing below the keep and rising to the back corners
		{
			points = {
				Vector3.new(-51.7, 0, 34.4),
				Vector3.new(-23.9, 0, 23.2),
				Vector3.new(-4, 0, 21.1),
				Vector3.new(15.9, 0, 19),
				Vector3.new(45, 0, 26.3),
			},
		},
	},
}
