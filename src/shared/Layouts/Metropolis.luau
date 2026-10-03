--!strict
-- Era 3 (Metropolis) plot layout: the M12 growth layout, candidate "avenues" (INTERFACES "M12 wave
-- 3 -- Metropolis", wave 3.1). Positions are studs relative to the plot centre, Y at ground level.
-- rotationY is Roblox-native CFrame.Angles(0, rad(r), 0): 0 faces -Z (the plot's front/hub edge),
-- positive turns counterclockwise seen from above (90 faces -X, 270 faces +X). Pads spawn padOffset
-- studs along that facing, placed unrotated, unless padPosition says otherwise.
--
-- Downtown on three avenues. The entrance runs two cells in to a cross-town street (z = -35), the
-- retail high street, where City Hall and the supermarket face the arriving player across it. Three
-- parallel avenues leave it for the back, each a dead end closed by a tower: the centre avenue
-- (offices, with a corner shop at its foot) by the Skyscraper on the main vista, the west avenue
-- (homes, the convention centre and the hospital) by the Bank Tower, the east avenue (the park,
-- the stadium, the finance tower) by the Broadcast Tower. The low early landmarks stand round the
-- entrance crossroads and the towers at the back, so the skyline rises away from the hub.
--
-- What shapes it:
--  * Kit tiles on the 7-stud lattice: a street's hard surface (road 3.5 + pavement 4) reaches 7.5
--    from its centreline and lots front it at 7.8. Only 105 x 105 studs lie inside the ring deck,
--    so the avenues sit 35 apart (x = -35, 0, 35): each block between them is 20 deep and holds two
--    8-deep lot rows back to back, and the outer avenues leave exactly one 8-deep row before the
--    deck. No other spacing carries more frontage on this plot; every lot fronts a street.
--  * The plan is a tree (roads grow as shortest paths from the entrance, so a loop would lose one
--    stretch for ever): the avenues meet only the cross-town street.
--  * Landmarks stand in the frontage like lots, 14 from the centreline they face so the pad sits on
--    the pavement off the asphalt. Rows are packed so the gap between two landmarks is a whole
--    terrace of 4-wide narrow lots (tools/fabric/Metropolis.plan.json walks at 0.05 to keep it),
--    and landmarks back to back across a block are staggered so their footprints and paths never
--    meet. Landmarks on the outer rows stand 12.5 out with the pad set on the pavement, or they
--    would reach under the deck.
--  * Every landmark that can stand off the frontage does: the three closers at the avenue ends, a
--    tower either side of the Skyscraper (their paths come down to the centre avenue's end), the
--    bus stop at the cross-town's east end and the two street-only pads in the front-west corner.
--  * A next-pad marker stands 5.3 to its landmark's right of the pad. Several pads sit off their
--    landmark's centre so each marker clears its own footprint, the next pad, a kiosk and the deck.
--  * Slot k stands roughly k-th along the streets: the stalls flank the entrance, the corner shops
--    and City Hall face the crossroads, the side avenues fill from tier 2 on and their last blocks
--    are drawn by the closers at tier 5. The Skyscraper is the exception the vista needs: bought
--    last, it closes the shortest avenue.
--
-- `district` is the fabric district a landmark pulls its neighbours toward (eras.Metropolis.fabric
-- .districts); the bus stop and the two street-only slots pull nothing.
return {
	plotSize = Vector3.new(120, 1, 120),
	baseColor = Color3.fromRGB(88, 90, 94),
	padSize = Vector3.new(6, 0.5, 6),
	padOffset = 7.5,
	placeholderSize = Vector3.new(8, 8, 8),
	slots = {
		-- the heart: the two stalls flank the entrance, facing it. The food truck's pad sits in its
		-- own lot, because a pad on the pavement would put its marker on the metro kiosk there
		foodTruck = {
			position = Vector3.new(-14.35, 0, -47),
			rotationY = 270,
			padPosition = Vector3.new(-12.85, 0, -46.3),
			district = "retail",
		},
		-- nearer the entrance than the food truck (no kiosk on this side), so the cross-town's south
		-- row east of it takes five narrow lots; the pad sits a stud north so its marker clears the
		-- deck
		coffeeShop = {
			position = Vector3.new(12.7, 0, -47),
			rotationY = 90,
			padPosition = Vector3.new(6.5, 0, -46),
			district = "retail",
		},
		-- the centre avenue's first shop, its path the avenue's first stretch: bought third, so the
		-- avenue's foot is the first ground that builds
		cornerShop = { position = Vector3.new(14, 0, -0.9), rotationY = 90, district = "retail" },
		-- the corner of the west avenue's mouth, facing the cross-town. The four landmarks along the
		-- cross-town's north side stand close behind its pavement, pads on it, so the rows behind
		-- them start as early as they can
		apartmentBlockA = {
			position = Vector3.new(-23, 0, -23.4),
			rotationY = 0,
			padPosition = Vector3.new(-22.3, 0, -28.5),
			district = "residential",
		},
		officeLowRise = {
			position = Vector3.new(-14, 0, -2),
			rotationY = 270,
			district = "office",
		},
		-- Found City Hall faces the entrance across the cross-town street, at the crossroads
		cityGrid = {
			position = Vector3.new(-12.5, 0, -22.9),
			rotationY = 0,
			padPosition = Vector3.new(-11.5, 0, -28.5),
			district = "civic",
		},
		-- City Hall's partner across the centre avenue's mouth; its pad sits west so its marker
		-- clears the shopping mall's pad
		supermarket = {
			position = Vector3.new(12.5, 0, -23),
			rotationY = 0,
			padPosition = Vector3.new(9.5, 0, -28.5),
			district = "retail",
		},
		-- closes the cross-town's east end from the corner ground past the bend, where no lot
		-- fronts a street; its path runs round the bend's pavement to the corner
		busStop = {
			position = Vector3.new(47.5, 0, -40),
			rotationY = 90,
			padPosition = Vector3.new(41.5, 0, -40),
			spur = {
				Vector3.new(47.5, 0, -40),
				Vector3.new(38.5, 0, -40),
				Vector3.new(38.5, 0, -35),
			},
		},
		apartmentBlockB = {
			position = Vector3.new(-47.5, 0, -18.15),
			rotationY = 270,
			padPosition = Vector3.new(-41.5, 0, -18.15),
			district = "residential",
		},
		parkingGarage = { position = Vector3.new(14, 0, 8.6), rotationY = 90, district = "office" },
		-- the east avenue's mouth, beside the supermarket; half a stud back and its pad 3 west so
		-- the metro kiosk at the corner keeps its daylight and the marker misses it
		shoppingMall = {
			position = Vector3.new(22, 0, -21.5),
			rotationY = 0,
			padPosition = Vector3.new(19, 0, -28.5),
			district = "retail",
		},
		-- streetOnly (Dig the Subway Line): no model and no path. Its pad and the ramp's share the
		-- corner past the cross-town's west end, below the ramp, ground no lot can front
		subwayLine = {
			position = Vector3.new(-42.9, 0, -47),
			rotationY = 270,
			padPosition = Vector3.new(-42.9, 0, -47),
			spur = { Vector3.new(-42.9, 0, -47) },
		},
		-- the last tier-3 join on the west avenue, so only its final block waits for tier 5
		hospital = { position = Vector3.new(-21, 0, 7.25), rotationY = 90, district = "civic" },
		-- the east avenue's first landmark, at the head of its inner row
		cityPark = { position = Vector3.new(21, 0, -11.6), rotationY = 270, district = "civic" },
		-- the two towers flank the Skyscraper on ground no street fronts; their paths come down to
		-- the centre avenue's end, which draws that avenue to its end in tier 3. The pads sit off
		-- centre so each marker clears the next row and the Skyscraper
		officeTowerA = {
			position = Vector3.new(13.5, 0, 46),
			rotationY = 0,
			padPosition = Vector3.new(11.5, 0, 38.5),
			spur = { Vector3.new(13.5, 0, 46), Vector3.new(13.5, 0, 30.5), Vector3.new(2, 0, 30.5) },
			district = "office",
		},
		hotelTower = {
			position = Vector3.new(-13.5, 0, 46),
			rotationY = 0,
			padPosition = Vector3.new(-14.5, 0, 38.5),
			spur = {
				Vector3.new(-13.5, 0, 46),
				Vector3.new(-13.5, 0, 30.5),
				Vector3.new(-2, 0, 30.5),
			},
			district = "office",
		},
		-- streetOnly (Build the Highway Ramp): its pad stands by the ramp foot. The slot's position
		-- is 2.5 in from the pad so its nominal 9x9 stays off the deck band
		highwayRamp = {
			position = Vector3.new(-46.9, 0, -47),
			rotationY = 270,
			padPosition = Vector3.new(-49.4, 0, -47),
			spur = { Vector3.new(-49.4, 0, -47) },
		},
		-- 12 x 12, 1.5 further back than a 9 x 9 so its front stays behind the pavement; the pad
		-- sits toward its far end so the marker clears the stadium's own footprint
		stadium = {
			position = Vector3.new(22.5, 0, 20.2),
			rotationY = 270,
			padPosition = Vector3.new(28.5, 0, 22.45),
			district = "civic",
		},
		-- at the head of the west avenue's inner row, staggered from the office block behind it
		conventionCenter = {
			position = Vector3.new(-21, 0, -14.1),
			rotationY = 90,
			district = "civic",
		},
		rooftopGarden = {
			position = Vector3.new(-47.5, 0, 18.75),
			rotationY = 270,
			padPosition = Vector3.new(-41.5, 0, 18.75),
			district = "residential",
		},
		-- the side closers stand 12 past their avenue's end, pads beside the end on the pavement,
		-- opposite the metro kiosk
		bankTower = {
			position = Vector3.new(-35, 0, 47),
			rotationY = 0,
			padPosition = Vector3.new(-28.5, 0, 41.5),
			district = "office",
		},
		broadcastTower = {
			position = Vector3.new(35, 0, 47),
			rotationY = 0,
			padPosition = Vector3.new(41.5, 0, 41.5),
			district = "office",
		},
		financeDistrict = {
			position = Vector3.new(47.5, 0, 18.9),
			rotationY = 90,
			padPosition = Vector3.new(41.5, 0, 18.9),
			district = "office",
		},
		-- Monument, 14 x 14: closes the centre avenue, the main vista from the entrance. The avenue
		-- ends at z = 28 because the tower must stay inside the deck. Its pad is half a stud forward
		-- of the default so the next-pad marker clears the tower's own footprint
		skyscraper = {
			position = Vector3.new(0, 0, 45),
			rotationY = 0,
			padPosition = Vector3.new(0, 0, 37),
			district = "office",
		},
	},
	-- Street plan. Roads grow with the buildings: only the stretches from the entrance (polyline
	-- 1's first point) to each owned building's join are drawn, and a junction only exists where a
	-- polyline point sits on another polyline. Every point is on the 7-stud lattice.
	streets = {
		-- 1: the entrance (the outermost lattice row; the plot entrance passes under the deck) and
		-- the centre avenue, one run to the Skyscraper
		{ points = { Vector3.new(0, 0, -49), Vector3.new(0, 0, -35), Vector3.new(0, 0, 28) } },
		-- 2: the cross-town street. Its west end is the ramp foot
		{ points = { Vector3.new(-35, 0, -35), Vector3.new(0, 0, -35), Vector3.new(35, 0, -35) } },
		-- 3 and 4: the side avenues, from the cross-town's ends to their closers
		{ points = { Vector3.new(-35, 0, -35), Vector3.new(-35, 0, 35) } },
		{ points = { Vector3.new(35, 0, -35), Vector3.new(35, 0, 35) } },
	},
	-- Elevated ring highway, ring 56 (deck 52.5..59.5, inside the plot, over the entrance). The ramp
	-- leaves the west leg level with the cross-town and comes down three cells onto its west end,
	-- so the highway's traffic lands on the high street.
	highway = {
		ring = 56,
		ramp = { cell = Vector3.new(-56, 0, -35), direction = "+X" },
	},
	-- Subway entrances: kiosks on the pavement at street corners and ends, front to the street. The
	-- one by the entrance is the one the client always shows once the slot is owned.
	subwayEntrances = {
		-- (-,-): the entrance's west pavement at the crossroads
		{ position = Vector3.new(-6.45, 0, -41), rotationY = 270 },
		-- (+,-): the east avenue's mouth, beside the shopping mall
		{ position = Vector3.new(28.55, 0, -29), rotationY = 270 },
		-- (-,+): beside the west avenue's end, outside; (+,+): beside the east avenue's end, inside,
		-- where it costs the inner row nothing and leaves the outer row its last lot
		{ position = Vector3.new(-41.5, 0, 38), rotationY = 270 },
		{ position = Vector3.new(28.5, 0, 38), rotationY = 270 },
	},
}
