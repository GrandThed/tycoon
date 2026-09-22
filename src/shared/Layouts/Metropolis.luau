--!strict
-- Era 3 (Metropolis) plot layout. Positions are studs relative to plot center, Y at
-- ground level. rotationY is Roblox-native CFrame.Angles(0, rad(r), 0): 0 faces -Z
-- (the plot's front/hub edge), positive turns counterclockwise seen from above
-- (90 faces -X, 270 faces +X). Pads spawn padOffset studs along that facing.
--
-- Personality: a downtown on a 4x4 grid of blocks (x, z = +/-14, +/-42) with two
-- traffic avenues on x = +/-28, one arterial cross street on z = -28, and the whole
-- x = 0 corridor kept car-free as a civic axis: the entrance avenue runs up to City
-- Hall's forecourt, City Hall sits dead centre, and the Skyscraper closes the axis
-- from the back so the skyline reads deepest from the hub. Asphalt-gray base.
--
-- Wave 2a geometry (INTERFACES "Wave 2a"), and why every number here is forced:
--  * The road is kit tiles on a 7-stud lattice, so every street point is a multiple
--    of 7 and every segment is axis-aligned (tools/streetplan.py enforces it).
--  * A corridor between two block faces is 19 studs (28 pitch - 9 footprint). Road 7
--    + pavement 4 either side = 15, leaving 2 studs of verge: nothing else fits
--    beside a street, so every non-block slot lives in a corridor stretch that has no
--    street, and the only legal street lines are x, z in {0, +/-28}.
--  * padOffset is 7.5, not 8: a block face sits 4.5 studs from its anchor and the
--    kerb 10.5, so a 6-deep pad at 7.5 exactly fills the sidewalk -- at 8 it would
--    hang half a stud over the asphalt.
return {
	plotSize = Vector3.new(120, 1, 120),
	baseColor = Color3.fromRGB(88, 90, 94),
	padSize = Vector3.new(6, 0.5, 6),
	padOffset = 7.5,
	placeholderSize = Vector3.new(8, 8, 8),
	slots = {
		-- The 16 block slots never move (INTERFACES "Moving the avenue slots"). Each faces
		-- the nearer traffic avenue, so both sides of every avenue are frontage and each
		-- spur is a single 14-stud leg from under the building to the kerb.

		-- front row of blocks (z = -42)
		cornerShop = { position = Vector3.new(-42, 0, -42), rotationY = 270 },
		foodTruck = { position = Vector3.new(-14, 0, -42), rotationY = 90 },
		coffeeShop = { position = Vector3.new(14, 0, -42), rotationY = 270 },
		apartmentBlockA = { position = Vector3.new(42, 0, -42), rotationY = 90 },

		-- second row (z = -14)
		apartmentBlockB = { position = Vector3.new(-42, 0, -14), rotationY = 270 },
		officeLowRise = { position = Vector3.new(-14, 0, -14), rotationY = 90 },
		supermarket = { position = Vector3.new(14, 0, -14), rotationY = 270 },
		parkingGarage = { position = Vector3.new(42, 0, -14), rotationY = 90 },

		-- third row (z = 14)
		officeTowerA = { position = Vector3.new(-42, 0, 14), rotationY = 270 },
		shoppingMall = { position = Vector3.new(-14, 0, 14), rotationY = 90 },
		hospital = { position = Vector3.new(14, 0, 14), rotationY = 270 },
		hotelTower = { position = Vector3.new(42, 0, 14), rotationY = 90 },

		-- back row (z = 42)
		-- The stadium is the one 12x12 block (era-kits memory, 2026-09-18): its face is 6
		-- studs out, which leaves only 4.5 studs to the avenue kerb -- too little for a
		-- 6-deep pad -- so it turns to face the open z = 28 corridor instead, takes an
		-- explicit pad on its forecourt, and walks its path out to the avenue. The join is
		-- held at z = 33 so the path never runs alongside the skyscraper's at z = 28.
		stadium = {
			position = Vector3.new(-42, 0, 42),
			rotationY = 0,
			padPosition = Vector3.new(-42, 0, 33),
			spur = { Vector3.new(-42, 0, 42), Vector3.new(-42, 0, 33), Vector3.new(-28, 0, 33) },
		},
		conventionCenter = { position = Vector3.new(-14, 0, 42), rotationY = 90 },
		bankTower = { position = Vector3.new(14, 0, 42), rotationY = 270 },
		broadcastTower = { position = Vector3.new(42, 0, 42), rotationY = 90 },

		-- Civic axis (x = 0), the corridor with no street in it: the entrance avenue ends
		-- at City Hall's forecourt, City Hall faces the arriving player, and the monument
		-- closes the axis from the back.
		cityGrid = { position = Vector3.new(0, 0, 0), rotationY = 0 },

		-- Finance District: the east half of the z = 28 corridor, turned to the east
		-- avenue so its pad stands on that sidewalk and its spur is one 14-stud leg.
		financeDistrict = { position = Vector3.new(14, 0, 28), rotationY = 270 },

		-- Two green squares flanking City Hall in the z = 0 corridor, each facing its own
		-- avenue (the only direction with room for a pad: their own footprints and City
		-- Hall's take the rest of the 19-stud corridor).
		cityPark = { position = Vector3.new(-13, 0, 0), rotationY = 90 },
		rooftopGarden = { position = Vector3.new(13, 0, 0), rotationY = 270 },

		-- Shelter on the corner ground east of the east avenue, clear of the 4.5-stud
		-- spine clearance its 9x9 footprint needs; the pad goes behind it (padOffset would
		-- put it on the asphalt), so the path leaves the shelter straight at the kerb.
		busStop = {
			position = Vector3.new(37, 0, 0),
			rotationY = 90,
			padPosition = Vector3.new(42, 0, 0),
		},

		-- streetOnly slots (era JSON): no model spawns, so only the pad is real.
		-- Dig the Subway Line: pad on the corner sidewalk beside the entrance nearest the
		-- plot entrance, and a one-point spur so no footpath is drawn (amendment P2).
		subwayLine = {
			position = Vector3.new(6.5, 0, -41),
			rotationY = 90,
			padPosition = Vector3.new(6.5, 0, -41),
			spur = { Vector3.new(6.5, 0, -41) },
		},
		-- Build the Highway Ramp: pad on the sidewalk corner at the foot of the ramp. It
		-- keeps its auto spur on purpose -- the 6.5-stud path is what puts the ramp's foot
		-- cell on a shortest path, so buying the ramp is what draws the tile it lands on.
		highwayRamp = {
			position = Vector3.new(-35, 0, -21.5),
			rotationY = 0,
			padPosition = Vector3.new(-35, 0, -21.5),
		},

		-- Monument: 14x14, so the only room for it is a corridor crossing. It stands at the
		-- head of the civic axis facing back down it (City Hall, then the entrance), where
		-- it is the deepest thing on the plot instead of a wall at the front edge. Its path
		-- has to leave sideways: the axis south of it is City Hall's.
		skyscraper = {
			position = Vector3.new(0, 0, 28),
			rotationY = 0,
			spur = { Vector3.new(0, 0, 28), Vector3.new(-28, 0, 28) },
		},
	},
	-- Street plan. Roads grow with the buildings (wave 1b): only the stretches from the
	-- entrance (polyline 1's first point) to each owned building's join are drawn, and a
	-- junction only exists where a polyline *point* sits on another polyline -- hence the
	-- mid-line points at z = -28 on the three avenues.
	--
	-- The plan is a tree on purpose: a closed block would lose exactly one stretch to the
	-- shortest-path tree and leave a permanent gap in a street, so the two avenues are
	-- joined by one arterial and nothing else.
	streets = {
		-- 1: the entrance avenue. It starts on the outermost lattice row the pavement can
		-- sit on (z = -49; z = -56 would hang the sidewalk off the plot) and stops at
		-- z = -21, City Hall's forecourt. The elevated ring passes over the approach.
		{ points = { Vector3.new(0, 0, -49), Vector3.new(0, 0, -28), Vector3.new(0, 0, -21) } },
		-- 2: the arterial, the one cross street, carrying the highway traffic across the
		-- city. Its west end is the ramp foot (one cell past the west avenue); its east end
		-- is the T with the east avenue.
		{ points = { Vector3.new(-35, 0, -28), Vector3.new(28, 0, -28) } },
		-- 3 and 4: the traffic avenues. They stop at z = +/-42, the last block row that
		-- joins them, so no stretch is reserved that nothing ever draws.
		{
			points = { Vector3.new(-28, 0, -42), Vector3.new(-28, 0, -28), Vector3.new(-28, 0, 42) },
		},
		{ points = { Vector3.new(28, 0, -42), Vector3.new(28, 0, -28), Vector3.new(28, 0, 42) } },
	},
	-- No lots: every block is already a building slot and eras.Metropolis.houses.props is
	-- empty (INTERFACES "Wave 2a").
	-- Public squares at the open ends of the z = 0 and z = 28 corridors, the only pockets
	-- wide enough for a 12x12 plaza that no street, pad or ramp wants.
	plazas = {
		{ position = Vector3.new(-45, 0, 0), rotationY = 0, tier = 3, prop = "PlazaA" },
		{ position = Vector3.new(45, 0, 28), rotationY = 0, tier = 5, prop = "PlazaB" },
	},
	-- Greenery is whatever the grid leaves: the four corners inside the ring, the pocket
	-- west of the stadium, the corridor behind the east avenue and the back verge on the
	-- civic axis. Sum 24 = eras.Metropolis.trees.maxCount.
	treeZones = {
		{ center = Vector3.new(-49, 0, -49), radius = 3, count = 4 },
		{ center = Vector3.new(49, 0, -49), radius = 3, count = 4 },
		{ center = Vector3.new(44, 0, -30), radius = 6, count = 4 },
		{ center = Vector3.new(-48.5, 0, 24), radius = 3, count = 4 },
		{ center = Vector3.new(0, 0, 48), radius = 4, count = 4 },
		{ center = Vector3.new(49, 0, 49), radius = 3, count = 4 },
	},
	-- Elevated ring highway. ring = 56 puts the deck centreline on the outermost lattice
	-- ring (cells 52.5..59.5): clear of the 46.5 block faces and the stadium at 48, inside
	-- the 120 plot, and over the plot entrance, which the deck's 6-stud soffit lets players
	-- walk under. The ramp leaves the ring's west leg and descends east along the arterial
	-- corridor (no street, no footprint under it) for three 7-stud cells, touching down on
	-- the arterial's west end cell at x = -35.
	highway = {
		ring = 56,
		ramp = { cell = Vector3.new(-56, 0, -28), direction = "+X" },
	},
	-- Subway entrances: kiosks 6.5 studs off a street centreline, which centres the built
	-- MetroEntrance (4.90 x 5.79, front on -Z) in the 6-stud sidewalk between the asphalt
	-- and the block faces -- 0.1 stud of slack, so each one also sits in a corridor mouth
	-- where nothing else comes within half a stud. One per quadrant plus the one beside the
	-- plot entrance, which is the entrance the client always shows once the slot is owned.
	subwayEntrances = {
		{ position = Vector3.new(6.5, 0, -34.5), rotationY = 90 },
		{ position = Vector3.new(-21.5, 0, -21.5), rotationY = 90 },
		{ position = Vector3.new(34.5, 0, -21.5), rotationY = 90 },
		{ position = Vector3.new(-21.5, 0, 34), rotationY = 90 },
		{ position = Vector3.new(34.5, 0, 28), rotationY = 90 },
	},
}
