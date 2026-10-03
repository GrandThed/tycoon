--!strict
-- Era 3 (Metropolis) plot layout: the M12 growth layout "avenues" (INTERFACES "M12 wave 3 --
-- Metropolis", "Wave 3.1b -- avenues, denser"). Positions are studs relative to the plot centre,
-- Y at ground level. rotationY is Roblox-native CFrame.Angles(0, rad(r), 0): 0 faces -Z (the
-- plot's front/hub edge), positive turns counterclockwise seen from above (90 faces -X, 270 faces
-- +X). Every pad is placed by padPosition, unrotated.
--
-- Downtown on three avenues. The entrance runs one cell in to a cross-town street (z = -42), where
-- City Hall and the shopping mall face the arriving player across it. Three parallel avenues leave
-- it for the back, each closed by a tower: the centre avenue by the Skyscraper on the main vista,
-- behind a short T with the Hotel and the Broadcast Tower either side of it; the west avenue by
-- the Bank Tower; the east avenue by Office Tower A. The low early landmarks stand round the
-- entrance crossroads and the towers at the back, so the skyline rises away from the hub and peaks
-- at the Skyscraper.
--
-- What shapes it (wave 3.1b: 2-stud pavements, four lanes, less empty ground):
--  * Kit tiles on the 7-stud lattice: a street's hard surface (road 3.5 + pavement 2) reaches 5.5
--    from its centreline, and lots front it at 5.5 with no strip between. The avenues stand 28
--    apart (x = -28, 0, 28), so a block is 17 deep between two pavements and holds two 8-deep rows
--    back to back with a 1-stud seam.
--  * Outside the side avenues 19 studs are left before the ring deck (52.5): an 8-deep street row,
--    a lane at x = +-44 and a row of 6 x 6 lots between the lane and the deck. Each side has a
--    front lane and a back lane (tools/fabric/Metropolis.plan.json, `parcels.lanes`); the back
--    lanes also fill the plot's back corners. The back mouths are at z = 17.45, the front ones at
--    z = -33.4 (east, behind the stadium) and z = -26.4 (west, behind the low-rise office).
--  * The plan is a tree (roads grow as shortest paths from the entrance, so a loop would lose one
--    stretch for ever): the avenues meet only the cross-town street.
--  * Landmarks stand on the street line like lots: a row landmark's harvested front is on the
--    pavement's outer edge (its centre at least 9 out, so the declared 9 x 9 keeps 4.5 off the
--    centreline), and its pad sits 6.5 out, flush with the road cell and on the landmark's own
--    ground, so nothing is left bare in front once the pad goes. A pad is moved along the row,
--    away from the side its next-pad marker stands on (5.3 to the landmark's right), so pad and
--    marker both stay inside the landmark's own frontage and cost its neighbours no lot.
--  * Two landmarks back to back in a block fit only if their depths add up to under 28. A deep
--    one stands behind a shallow one (convention centre and apartment block B, coffee shop and
--    supermarket), opposite the T where the block has no second row (hospital), or takes a 6 x 6
--    lot behind it (corner shop, parking garage). Landmarks on the outer rows are the shallow
--    ones, because the lane runs behind them.
--  * A lot is as tall as the nearest landmark with a district allows, and a lane's lots follow
--    the street lot beside its mouth. So four low landmarks carry no district (bus stop, city
--    park, rooftop garden, convention centre): each would cap its neighbours at one or two
--    storeys, and the two bought last would cut down buildings already standing. They stand where
--    nothing is built in front of them instead: the park and the roof garden at the heads of the
--    inner rows beside the mall and City Hall, the bus stop first after a lane mouth, the
--    convention centre behind the food truck. Along each avenue the landmarks with a district
--    stand level or rise toward the back, so no lot is taller than a landmark it stands in front
--    of.
--  * The hospital is in the `office` district, not `civic`: it governs the ten lots of the west
--    back lane, and civic has no narrow prop and a 2.3-stud plaza for small lots.
--  * Growth by tier: the centre avenue's foot and the east avenue as far as apartment block A
--    (tier 1); the cross-town's west half and the west avenue as far as apartment block B (2);
--    both side avenues to the back, drawn by the hospital and Office Tower A (3); the centre
--    avenue's head and the T, drawn by the Hotel (4); the west avenue's last block, by the Bank
--    Tower (5).
--
-- `district` is the fabric district a landmark pulls its neighbours toward (eras.Metropolis.fabric
-- .districts); a slot without one pulls nothing.
return {
	plotSize = Vector3.new(120, 1, 120),
	baseColor = Color3.fromRGB(88, 90, 94),
	padSize = Vector3.new(6, 0.5, 6),
	-- every slot sets padPosition; this default puts a pad's far edge 6.5 from a landmark 9 out
	padOffset = 3.5,
	placeholderSize = Vector3.new(8, 8, 8),
	slots = {
		-- the centre avenue's west side, behind City Hall. The explicit two-point paths of the row
		-- landmarks join their street level with the landmark, not with the moved pad, so each
		-- governs the lots beside it
		foodTruck = {
			position = Vector3.new(-9.92, 0, -23.95),
			rotationY = 270,
			padPosition = Vector3.new(-6.5, 0, -25.15),
			spur = { Vector3.new(-9.92, 0, -23.95), Vector3.new(0, 0, -23.95) },
			district = "retail",
		},
		-- the centre avenue's east side, behind the mall; the supermarket stands at its back
		coffeeShop = {
			position = Vector3.new(9.92, 0, -21.83),
			rotationY = 90,
			padPosition = Vector3.new(6.5, 0, -20.53),
			spur = { Vector3.new(9.92, 0, -21.83), Vector3.new(0, 0, -21.83) },
			district = "retail",
		},
		-- bought third: its path draws the centre avenue's foot. Too deep for a narrow lot behind
		-- it, so the east avenue's inner row has a 6 x 6 lot there
		cornerShop = {
			position = Vector3.new(9.82, 0, -3.03),
			rotationY = 90,
			padPosition = Vector3.new(6.5, 0, -1.63),
			spur = { Vector3.new(9.82, 0, -3.03), Vector3.new(0, 0, -3.03) },
			district = "retail",
		},
		-- the only tier-1 landmark off the centre avenue, half way down the east avenue's outer row:
		-- it draws the cross-town's east half and 47 studs of avenue, so tier 1 has building sites
		-- on both rows and on the east front lane. It stays more than 13.9 from the back lane's
		-- first lot, which Office Tower A then governs
		apartmentBlockA = {
			position = Vector3.new(37.32, 0, 5.5),
			rotationY = 90,
			padPosition = Vector3.new(34.5, 0, 6.72),
			spur = { Vector3.new(37.32, 0, 5.5), Vector3.new(28, 0, 5.5) },
			district = "residential",
		},
		-- on the corner south of the cross-town's west end, facing it: the foot of the highway ramp.
		-- Only this path uses the cross-town's last cell, so without it the ramp would land on a
		-- park strip for ever; bought in tier 2, it draws that cell two tiers before the ramp comes.
		-- The pad stands half a stud off the ramp's cells and a stud west, so the marker keeps 4.5
		-- off the west avenue's centreline
		officeLowRise = {
			position = Vector3.new(-37.75, 0, -32.25),
			rotationY = 0,
			padPosition = Vector3.new(-38.85, 0, -35),
			spur = {
				Vector3.new(-37.75, 0, -32.25),
				Vector3.new(-36, 0, -38),
				Vector3.new(-35, 0, -42),
			},
			district = "office",
		},
		-- Found City Hall faces the entrance across the cross-town street, at the crossroads, its
		-- front on the pavement's edge. The pad sits a stud west so the marker keeps 4.5 off the
		-- centre avenue
		cityGrid = {
			position = Vector3.new(-10, 0, -31.98),
			rotationY = 0,
			padPosition = Vector3.new(-11, 0, -35.5),
			district = "civic",
		},
		-- back to back with the coffee shop, behind the city park: the park is all that stands in
		-- front of it, and it governs the east front lane (shops)
		supermarket = {
			position = Vector3.new(18.41, 0, -21.6),
			rotationY = 270,
			padPosition = Vector3.new(21.5, 0, -22.9),
			spur = { Vector3.new(18.41, 0, -21.6), Vector3.new(28, 0, -21.6) },
			district = "retail",
		},
		-- first on the east avenue's outer row, right after the front lane's mouth, so no lot stands
		-- in front of a 4-stud shelter
		busStop = {
			position = Vector3.new(37.52, 0, -26.4),
			rotationY = 90,
			padPosition = Vector3.new(34.5, 0, -25),
			spur = { Vector3.new(37.52, 0, -26.4), Vector3.new(28, 0, -26.4) },
		},
		-- back to back with the convention centre; it governs the west avenue's front and the west
		-- front lane (homes)
		apartmentBlockB = {
			position = Vector3.new(-18.08, 0, -13.85),
			rotationY = 90,
			padPosition = Vector3.new(-21.5, 0, -12.69),
			spur = { Vector3.new(-18.08, 0, -13.85), Vector3.new(-28, 0, -13.85) },
			district = "residential",
		},
		-- the deepest row landmark: the west avenue's inner row has a 6 x 6 lot behind it
		parkingGarage = {
			position = Vector3.new(-10.01, 0, 1),
			rotationY = 270,
			padPosition = Vector3.new(-6.5, 0, -0.4),
			spur = { Vector3.new(-10.01, 0, 1), Vector3.new(0, 0, 1) },
			district = "office",
		},
		-- City Hall's partner across the centre avenue's mouth. It stands 0.3 off the avenue's
		-- pavement so the city park behind it keeps its daylight, and its pad sits west so the
		-- marker clears the park
		shoppingMall = {
			position = Vector3.new(9.35, 0, -32.07),
			rotationY = 0,
			padPosition = Vector3.new(6.72, 0, -35.5),
			district = "retail",
		},
		-- streetOnly (Dig the Subway Line): no model and no path, a pad on the front strip between
		-- the cross-town street and the deck, ground too shallow for a lot
		subwayLine = {
			position = Vector3.new(18, 0, -48.5),
			rotationY = 0,
			padPosition = Vector3.new(18, 0, -48.5),
			spur = { Vector3.new(18, 0, -48.5) },
		},
		-- opposite the T, where the block has no second row for its depth to take. The last tier-3
		-- join on the west avenue: only the avenue's final block waits for the Bank Tower. Not
		-- further back than 24.5, or the Hotel's path would pass too close
		hospital = {
			position = Vector3.new(-18, 0, 24.02),
			rotationY = 90,
			padPosition = Vector3.new(-21.5, 0, 25.22),
			spur = { Vector3.new(-18, 0, 24.02), Vector3.new(-28, 0, 24.02) },
			district = "office",
		},
		-- the head of the east avenue's inner row, on the cross-town's corner beside the mall: a
		-- 3-stud garden with only the street in front of it
		cityPark = {
			position = Vector3.new(18.16, 0, -32.16),
			rotationY = 270,
			padPosition = Vector3.new(21.5, 0, -33.48),
			spur = { Vector3.new(18.16, 0, -32.16), Vector3.new(28, 0, -32.16) },
		},
		-- closes the east avenue. Bought in tier 3, it draws the avenue's whole back half then and
		-- governs the east back lane; the pad sits a stud west so its marker leaves the lane its
		-- first narrow lot
		officeTowerA = {
			position = Vector3.new(28, 0, 45),
			rotationY = 0,
			padPosition = Vector3.new(27, 0, 41.5),
			district = "office",
		},
		-- the Hotel and the Broadcast Tower flank the Skyscraper on ground no street fronts. Their
		-- paths come down to the T's ends; the Hotel's, in tier 4, draws the centre avenue to its
		-- head. The Hotel's pad sits off centre so its marker clears the Skyscraper
		hotelTower = {
			position = Vector3.new(-11.25, 0, 42.5),
			rotationY = 0,
			padPosition = Vector3.new(-13.8, 0, 40.5),
			spur = {
				Vector3.new(-11.25, 0, 42.5),
				Vector3.new(-11.25, 0, 35),
				Vector3.new(-10, 0, 30.5),
				Vector3.new(-9, 0, 28),
			},
			district = "office",
		},
		-- streetOnly (Build the Highway Ramp): the subway pad's twin on the front strip
		highwayRamp = {
			position = Vector3.new(-18, 0, -48.5),
			rotationY = 0,
			padPosition = Vector3.new(-18, 0, -48.5),
			spur = { Vector3.new(-18, 0, -48.5) },
		},
		-- 12 x 12: closes the cross-town's east end from the corner ground past the bend, where no
		-- lot can front a street
		stadium = {
			position = Vector3.new(45.5, 0, -42),
			rotationY = 90,
			padPosition = Vector3.new(41.5, 0, -42),
			district = "civic",
		},
		-- directly behind the food truck, the one thing lower than it on the avenue
		conventionCenter = {
			position = Vector3.new(-9.95, 0, -13.85),
			rotationY = 270,
			padPosition = Vector3.new(-6.5, 0, -14.95),
			spur = { Vector3.new(-9.95, 0, -13.85), Vector3.new(0, 0, -13.85) },
		},
		-- the head of the west avenue's inner row, beside City Hall. It stands 5.3 behind the
		-- cross-town's pavement so its marker, on the street side of the pad, keeps 4.5 off the
		-- cross-town's centreline
		rooftopGarden = {
			position = Vector3.new(-19, 0, -31.2),
			rotationY = 90,
			padPosition = Vector3.new(-21.5, 0, -31.2),
			spur = { Vector3.new(-19, 0, -31.2), Vector3.new(-28, 0, -31.2) },
		},
		-- closes the west avenue, 10 past its end with the pad on the end's pavement
		bankTower = {
			position = Vector3.new(-28, 0, 45),
			rotationY = 0,
			padPosition = Vector3.new(-28, 0, 41.5),
			district = "office",
		},
		-- 8.9 wide: a quarter of a stud further from the Skyscraper than the Hotel
		broadcastTower = {
			position = Vector3.new(11.5, 0, 42.5),
			rotationY = 0,
			padPosition = Vector3.new(10.5, 0, 39),
			spur = {
				Vector3.new(11.5, 0, 42.5),
				Vector3.new(11.5, 0, 35),
				Vector3.new(10, 0, 30.5),
				Vector3.new(9, 0, 28),
			},
			district = "office",
		},
		-- far enough behind the corner shop for its marker to clear the shop's ground; shallow
		-- enough for narrow lots behind it
		financeDistrict = {
			position = Vector3.new(9.62, 0, 7.3),
			rotationY = 90,
			padPosition = Vector3.new(6.5, 0, 8.3),
			spur = { Vector3.new(9.62, 0, 7.3), Vector3.new(0, 0, 7.3) },
			district = "office",
		},
		-- Monument, 14 x 14: closes the centre avenue, the main vista from the entrance, behind the
		-- T. Its pad stands on the T's far pavement
		skyscraper = {
			position = Vector3.new(0, 0, 40),
			rotationY = 0,
			padPosition = Vector3.new(0, 0, 36.5),
			district = "office",
		},
	},
	-- Street plan. Roads grow with the buildings: only the stretches from the entrance (polyline
	-- 1's first point) to each owned building's join are drawn, and a junction only exists where a
	-- polyline point sits on another polyline. Every point is on the 7-stud lattice.
	streets = {
		-- 1: the entrance (the outermost lattice row; the plot entrance passes under the deck) and
		-- the centre avenue, one run to the T
		{ points = { Vector3.new(0, 0, -49), Vector3.new(0, 0, -42), Vector3.new(0, 0, 28) } },
		-- 2: the cross-town street. Its west end is the ramp foot, its east end the stadium's door
		{
			points = {
				Vector3.new(-35, 0, -42),
				Vector3.new(-28, 0, -42),
				Vector3.new(0, 0, -42),
				Vector3.new(28, 0, -42),
				Vector3.new(35, 0, -42),
			},
		},
		-- 3 and 4: the side avenues, from the cross-town to their closers
		{ points = { Vector3.new(-28, 0, -42), Vector3.new(-28, 0, 35) } },
		{ points = { Vector3.new(28, 0, -42), Vector3.new(28, 0, 35) } },
		-- 5: the T at the centre avenue's head, one cell either way: the Skyscraper's forecourt and
		-- the foot of the two flanking towers' paths
		{ points = { Vector3.new(-7, 0, 28), Vector3.new(0, 0, 28), Vector3.new(7, 0, 28) } },
	},
	-- Elevated ring highway, ring 56 (deck 52.5..59.5, inside the plot, over the entrance). The ramp
	-- leaves the west leg level with the cross-town and comes down three cells onto its west end,
	-- so the highway's traffic lands on the cross-town street.
	highway = {
		ring = 56,
		ramp = { cell = Vector3.new(-56, 0, -42), direction = "+X" },
	},
	-- Subway entrances. A kiosk no longer fits on a 2-stud pavement, so each stands at a street
	-- corner beside it, in a gap the lots keep clear, its front to the street: two either side of
	-- the entrance facing the cross-town, two at the T's corners facing the T. The first is the one
	-- the client always shows once the slot is owned.
	subwayEntrances = {
		{ position = Vector3.new(-7.95, 0, -48.4), rotationY = 180 },
		{ position = Vector3.new(7.95, 0, -48.4), rotationY = 180 },
		{ position = Vector3.new(-7.95, 0, 21.59), rotationY = 180 },
		{ position = Vector3.new(7.95, 0, 21.59), rotationY = 180 },
	},
}
