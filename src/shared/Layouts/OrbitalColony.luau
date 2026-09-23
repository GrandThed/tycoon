--!strict
-- Era 4 (OrbitalColony) plot layout. Positions are studs relative to plot center,
-- Y at ground level. rotationY is Roblox-native CFrame.Angles(0, rad(r), 0): 0
-- faces -Z (the plot's front/hub edge), positive turns counterclockwise seen from
-- above (90 faces -X, 270 faces +X). Pads spawn padOffset studs along that facing.
--
-- Personality: a colony of modules on the Metropolis lattice (4x4 grid at x, z =
-- +/-14, +/-42), strung together by enclosed glass tubes and ringed by a monorail.
-- The low landing pads, solar racks and domes greet the hub; the tall science and
-- industry modules stand at the back; the Launch Tower closes the central tube from
-- the back of the plot, facing arriving players down it. Dark regolith base.
--
-- Wave 2b geometry (INTERFACES "Wave 2b"), and why the numbers are what they are:
--  * Tubes are kit tiles on the 7-stud lattice, so every street point is a multiple of
--    7 and every segment is axis-aligned. A tube is 4 wide in a 7 cell and has no
--    pavement, so pads stand flush against the cell edge (centreline +/- 3.5) and
--    nothing but a spur ever sits on a cell.
--  * padOffset is 7.5 as in Metropolis: a 9x9 face is 4.5 from its anchor and the cell
--    edge 10.5, so a 6-deep pad exactly fills the gap.
--  * A 12x12 face is 6 from its anchor, which leaves only 4.5 to the cell edge -- too
--    little for a pad. The three 12x12 modules therefore sit 1.5 studs outboard of
--    their grid spot (x = +/-43.5; the outer face at 49.5 still clears the monorail
--    band at 52.5) and name their pad explicitly on the cell edge.
return {
	plotSize = Vector3.new(120, 1, 120),
	baseColor = Color3.fromRGB(56, 53, 60),
	padSize = Vector3.new(6, 0.5, 6),
	padOffset = 7.5,
	placeholderSize = Vector3.new(8, 8, 8),
	slots = {
		-- Front row (z = -42): the lowest modules, all under 9.5 studs. The inner two face
		-- the central tube, so the first purchase joins the entrance tube itself.
		habitatPod = { position = Vector3.new(-42, 0, -42), rotationY = 270 },
		landingPad = { position = Vector3.new(-14, 0, -42), rotationY = 270 },
		solarArray = { position = Vector3.new(14, 0, -42), rotationY = 90 },
		hydroponicsDome = { position = Vector3.new(42, 0, -42), rotationY = 90 },

		-- Second row (z = -14). The rover bay's 12-stud side runs along the tube, so its
		-- 9-deep front keeps the standard pad.
		roverBay = { position = Vector3.new(-42, 0, -14), rotationY = 270 },
		oxygenGenerator = { position = Vector3.new(-14, 0, -14), rotationY = 270 },
		researchLab = { position = Vector3.new(14, 0, -14), rotationY = 90 },
		mineralExtractor = { position = Vector3.new(42, 0, -14), rotationY = 90 },

		-- Third row (z = 14): the inner two face the central tube, so buying the Observation
		-- Dome (tier 3) is what draws that tube past the platform and the domes beside it.
		crewQuarters = { position = Vector3.new(-42, 0, 14), rotationY = 270 },
		observationDome = { position = Vector3.new(-14, 0, 14), rotationY = 270 },
		medicalBay = { position = Vector3.new(14, 0, 14), rotationY = 90 },
		fusionReactor = {
			position = Vector3.new(43.5, 0, 14),
			rotationY = 90,
			padPosition = Vector3.new(34.5, 0, 14),
		},

		-- Back row (z = 42): the tallest modules, flanking the Launch Tower.
		terraformStation = {
			position = Vector3.new(-43.5, 0, 42),
			rotationY = 270,
			padPosition = Vector3.new(-34.5, 0, 42),
		},
		dockingBay = { position = Vector3.new(-14, 0, 42), rotationY = 90 },
		commsArray = { position = Vector3.new(14, 0, 42), rotationY = 270 },
		spaceportTerminal = {
			position = Vector3.new(43.5, 0, 42),
			rotationY = 90,
			padPosition = Vector3.new(34.5, 0, 42),
		},

		-- Installations and decor in the outer corridor bays, each facing its side tube,
		-- each beside the module it depends on or guards.
		planetaryDefense = { position = Vector3.new(-42, 0, -29), rotationY = 270 },
		lifeSupport = { position = Vector3.new(42, 0, -28), rotationY = 90 },
		colonyFlag = { position = Vector3.new(-42, 0, 1), rotationY = 270 },
		rockGarden = { position = Vector3.new(42, 0, -1), rotationY = 90 },
		holoBeacon = { position = Vector3.new(-42, 0, 27), rotationY = 270 },
		orbitalUplink = { position = Vector3.new(42, 0, 28), rotationY = 90 },

		-- Build the Monorail is streetOnly (era JSON): no model spawns, so only the pad is
		-- real. It stands in the corner where the entrance tube meets the cross tube,
		-- flush with both cells, and a one-point spur draws no path (amendment P2).
		walkwayNetwork = {
			position = Vector3.new(6.5, 0, -34.5),
			rotationY = 90,
			padPosition = Vector3.new(6.5, 0, -34.5),
			spur = { Vector3.new(6.5, 0, -34.5) },
		},

		-- Monument: 14x14 in the back band between the back-row modules, facing down the
		-- central tube. The pad stands on the tower's front face and the auto spur is a
		-- short decking strip from there to the airlock at the tube's end.
		launchTower = {
			position = Vector3.new(0, 0, 42),
			rotationY = 0,
			padPosition = Vector3.new(0, 0, 32),
		},
	},
	-- Tube plan. Tubes grow with the modules (wave 1b): only the stretches from the entrance
	-- (polyline 1's first point) to each owned module's join are drawn, and a junction exists
	-- only where a polyline point sits on another polyline -- hence the mid-points at z = -28.
	-- It is a tree on purpose: a closed loop would lose one stretch to the shortest-path tree
	-- and leave a permanent gap in a tube.
	streets = {
		-- 1: the central tube, from the outermost lattice row inside the monorail band
		-- (z = -49) up the middle of the colony to the airlock in front of the Launch Tower.
		{ points = { Vector3.new(0, 0, -49), Vector3.new(0, 0, -28), Vector3.new(0, 0, 21) } },
		-- 2: the cross tube joining the side tubes to the central one.
		{ points = { Vector3.new(-28, 0, -28), Vector3.new(28, 0, -28) } },
		-- 3 and 4: the side tubes, front row to back row.
		{
			points = { Vector3.new(-28, 0, -42), Vector3.new(-28, 0, -28), Vector3.new(-28, 0, 42) },
		},
		{ points = { Vector3.new(28, 0, -42), Vector3.new(28, 0, -28), Vector3.new(28, 0, 42) } },
	},
	-- Small domes (HouseA/B, 6x6) in the middle and back corridors, each facing a tube or the
	-- Launch Tower's spur, 1.5 studs clear of the cell edge. Each appears at the tier the greedy
	-- player first draws the tube it faces (sim buy order), so no dome fronts bare ground.
	lots = {
		{ position = Vector3.new(-21, 0, 0), rotationY = 90, tier = 2 },
		{ position = Vector3.new(8, 0, 0), rotationY = 90, tier = 3 },
		{ position = Vector3.new(20, 0, 0), rotationY = 270, tier = 3 },
		{ position = Vector3.new(-20, 0, 28), rotationY = 90, tier = 4 },
		{ position = Vector3.new(20, 0, 28), rotationY = 270, tier = 4 },
		{ position = Vector3.new(-8, 0, 28), rotationY = 270, tier = 5 },
		{ position = Vector3.new(8, 0, 28), rotationY = 90, tier = 5 },
	},
	-- Observation platform (12x12) in the middle corridor, its front flush with the central
	-- tube's cell edge (x = -3.5) so it opens straight off the tube.
	plazas = {
		{ position = Vector3.new(-9.5, 0, 0), rotationY = 270, tier = 3, prop = "PlazaA" },
	},
	-- Rock fields on the bare regolith between the decking: the gaps past the side tubes' ends,
	-- front and back, and the open middle and back corridors between the domes. Every circle
	-- keeps 3 studs off any footprint and pad, stays off the tube cells and stops short of the
	-- monorail band.
	treeZones = {
		{ center = Vector3.new(-26, 0, -49.5), radius = 2.5, count = 5 },
		{ center = Vector3.new(26, 0, -49.5), radius = 2.5, count = 5 },
		{ center = Vector3.new(14, 0, 0), radius = 2, count = 4 },
		{ center = Vector3.new(-14, 0, 28), radius = 2, count = 4 },
		{ center = Vector3.new(-26, 0, 50), radius = 2, count = 4 },
		{ center = Vector3.new(26, 0, 50), radius = 2, count = 4 },
	},
	-- Decking (INTERFACES "Paved blocks"): one slab per module cluster, shown once any listed
	-- slot is owned. Each rect covers its modules' footprints and pads plus about 2 studs, keeps
	-- half a stud off every tube cell (centreline +/- 4), off the platform and off its
	-- neighbours. The plot rim, the gaps between clusters and the middle corridor stay bare
	-- regolith, which is where the rocks and the domes stand.
	blocks = {
		-- west outer column
		{
			min = Vector3.new(-48.5, 0, -48.5),
			max = Vector3.new(-32, 0, -22.5),
			slots = { "habitatPod", "planetaryDefense" },
		},
		{
			min = Vector3.new(-48.5, 0, -22),
			max = Vector3.new(-32, 0, 20.25),
			slots = { "roverBay", "colonyFlag", "crewQuarters" },
		},
		{
			min = Vector3.new(-51.5, 0, 20.75),
			max = Vector3.new(-32, 0, 50),
			slots = { "holoBeacon", "terraformStation" },
		},

		-- front row either side of the central tube; the east one takes the monorail pad
		{
			min = Vector3.new(-20.5, 0, -48.5),
			max = Vector3.new(-4, 0, -35.5),
			slots = { "landingPad" },
		},
		{
			min = Vector3.new(4, 0, -48.5),
			max = Vector3.new(20.5, 0, -32),
			slots = { "solarArray", "walkwayNetwork" },
		},

		-- second and third rows either side of the central tube
		{
			min = Vector3.new(-20.5, 0, -20.5),
			max = Vector3.new(-4, 0, -7.5),
			slots = { "oxygenGenerator" },
		},
		{
			min = Vector3.new(4, 0, -20.5),
			max = Vector3.new(20.5, 0, -7.5),
			slots = { "researchLab" },
		},
		{
			min = Vector3.new(-20.5, 0, 7.5),
			max = Vector3.new(-4, 0, 20.5),
			slots = { "observationDome" },
		},
		{
			min = Vector3.new(4, 0, 7.5),
			max = Vector3.new(20.5, 0, 20.5),
			slots = { "medicalBay" },
		},

		-- back row: the Launch Tower and its pad, flanked by the two back modules
		{
			min = Vector3.new(-24, 0, 35.5),
			max = Vector3.new(-9.5, 0, 48.5),
			slots = { "dockingBay" },
		},
		{ min = Vector3.new(-9, 0, 27), max = Vector3.new(9, 0, 51), slots = { "launchTower" } },
		{
			min = Vector3.new(9.5, 0, 35.5),
			max = Vector3.new(24, 0, 48.5),
			slots = { "commsArray" },
		},

		-- east outer column
		{
			min = Vector3.new(32, 0, -48.5),
			max = Vector3.new(48.5, 0, -21.25),
			slots = { "hydroponicsDome", "lifeSupport" },
		},
		{
			min = Vector3.new(32, 0, -20.75),
			max = Vector3.new(51.5, 0, 21.5),
			slots = { "mineralExtractor", "rockGarden", "fusionReactor" },
		},
		{
			min = Vector3.new(32, 0, 22),
			max = Vector3.new(51.5, 0, 50),
			slots = { "orbitalUplink", "spaceportTerminal" },
		},
	},
	-- Monorail loop (loop mode: no ramp). ring = 56 puts the track on the outermost lattice
	-- ring (cells 52.5..59.5), clear of every module (the 12x12s reach 49.5), inside the plot,
	-- and over the plot entrance, which the 6-stud soffit lets players walk under.
	highway = { ring = 56 },
}
