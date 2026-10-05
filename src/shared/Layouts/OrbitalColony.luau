--!strict
-- Era 4 (OrbitalColony) plot layout: the GROUNDWORK of the M12 growth-layout mock (INTERFACES
-- "M12 wave 4 -- Orbital Colony", "Wave 4.1"). It is today's colony with the fabric switched on, so
-- the generator, the checks, the mirror and the renderer can be proved end to end; the candidate
-- layouts "docks" and "axis" replace this file. Positions are studs relative to the plot centre, Y
-- at ground level. rotationY is Roblox-native CFrame.Angles(0, rad(r), 0): 0 faces -Z (the plot's
-- front/hub edge), positive turns counterclockwise seen from above (90 faces -X, 270 faces +X).
-- Pads spawn padOffset studs along that facing unless a slot names its padPosition.
--
-- What is kept from wave 2b: the tubes (kit tiles on the 7-stud lattice, a tree), the 4x4 grid of
-- modules at x, z = +/-14, +/-42 with the low ones at the front and the Launch Tower closing the
-- central tube, and the monorail loop. What is gone: `lots`, `plazas`, `treeZones` and the cluster
-- decking, which the city fabric replaces (lots dock on the tubes, wild regolith covers the rest).
--
-- What the new rules ask of it:
--  * `road.tiles.dock` 1.75: a straight or end tube cell is a solid only 1.75 either side of its
--    centreline, so a lot fronts the pipe there and a deck rect runs up to that line. The modules
--    keep their wave 2b seats (pad flush with the cell edge, 3.5 out), which is legal and leaves
--    1.75 of decking between pad and pipe. A bend, tee or cross cell stays whole.
--  * One `blocks` rect per module (one slot each): the decking under its pad and building, from
--    the dock line back. Decking arrives with the purchase; no slab paves a cluster ahead of it.
--  * A next-pad marker stands 5.3 to a module's right of its pad, so the monorail's pad is
--    turned: facing the tube its marker stood on the Solar Array's pad.
--  * `district` is the fabric district a module pulls its neighbours toward
--    (eras.OrbitalColony.fabric.districts); a slot without one pulls nothing. The six decor and
--    unlock installations carry none: each is one low stage and would cap the pods beside it.
return {
	plotSize = Vector3.new(120, 1, 120),
	baseColor = Color3.fromRGB(56, 53, 60),
	padSize = Vector3.new(6, 0.5, 6),
	padOffset = 7.5,
	placeholderSize = Vector3.new(8, 8, 8),
	slots = {
		-- Front row (z = -42): the lowest modules. The inner two face the central tube, so the
		-- first purchase joins the entrance tube itself.
		habitatPod = { position = Vector3.new(-42, 0, -42), rotationY = 270, district = "habitat" },
		landingPad = { position = Vector3.new(-14, 0, -42), rotationY = 270, district = "port" },
		solarArray = { position = Vector3.new(14, 0, -42), rotationY = 90, district = "industry" },
		hydroponicsDome = {
			position = Vector3.new(42, 0, -42),
			rotationY = 90,
			district = "habitat",
		},

		-- Second row (z = -14). The rover bay's 12-stud side runs along the tube.
		roverBay = { position = Vector3.new(-42, 0, -14), rotationY = 270, district = "port" },
		oxygenGenerator = {
			position = Vector3.new(-14, 0, -14),
			rotationY = 270,
			district = "industry",
		},
		researchLab = { position = Vector3.new(14, 0, -14), rotationY = 90, district = "science" },
		mineralExtractor = {
			position = Vector3.new(42, 0, -14),
			rotationY = 90,
			district = "industry",
		},

		-- Third row (z = 14).
		crewQuarters = { position = Vector3.new(-42, 0, 14), rotationY = 270, district = "habitat" },
		observationDome = {
			position = Vector3.new(-14, 0, 14),
			rotationY = 270,
			district = "science",
		},
		medicalBay = { position = Vector3.new(14, 0, 14), rotationY = 90, district = "habitat" },
		-- 12x12: 1.5 outboard of its grid spot, pad named on the cell edge (as in wave 2b)
		fusionReactor = {
			position = Vector3.new(43.5, 0, 14),
			rotationY = 90,
			padPosition = Vector3.new(34.5, 0, 14),
			district = "industry",
		},

		-- Back row (z = 42): the tallest modules, flanking the Launch Tower.
		terraformStation = {
			position = Vector3.new(-43.5, 0, 42),
			rotationY = 270,
			padPosition = Vector3.new(-34.5, 0, 42),
			district = "industry",
		},
		dockingBay = { position = Vector3.new(-14, 0, 42), rotationY = 90, district = "port" },
		commsArray = { position = Vector3.new(14, 0, 42), rotationY = 270, district = "science" },
		spaceportTerminal = {
			position = Vector3.new(43.5, 0, 42),
			rotationY = 90,
			padPosition = Vector3.new(34.5, 0, 42),
			district = "port",
		},

		-- Installations and decor in the outer bays, each facing its side tube. No district.
		planetaryDefense = { position = Vector3.new(-42, 0, -29), rotationY = 270 },
		lifeSupport = { position = Vector3.new(42, 0, -28), rotationY = 90 },
		colonyFlag = { position = Vector3.new(-42, 0, 1), rotationY = 270 },
		rockGarden = { position = Vector3.new(42, 0, -1), rotationY = 90 },
		holoBeacon = { position = Vector3.new(-42, 0, 27), rotationY = 270 },
		orbitalUplink = { position = Vector3.new(42, 0, 28), rotationY = 90 },

		-- Build the Monorail is streetOnly (era JSON): no model spawns, so only the pad is real.
		-- It stands beside the entrance tube on ground nothing else uses, and a one-point spur
		-- draws no path. Turned to face the front (it faced the tube in wave 2b), so its next-pad
		-- marker stands east of it and not on the Solar Array's pad.
		walkwayNetwork = {
			position = Vector3.new(6.5, 0, -34.5),
			rotationY = 0,
			padPosition = Vector3.new(6.5, 0, -34.5),
			spur = { Vector3.new(6.5, 0, -34.5) },
		},

		-- Monument: 14x14 in the back band between the back-row modules, facing down the
		-- central tube. The pad stands on the tower's front face.
		launchTower = {
			position = Vector3.new(0, 0, 42),
			rotationY = 0,
			padPosition = Vector3.new(0, 0, 32),
			district = "port",
		},
	},
	-- Tube plan. Tubes grow with the modules (wave 1b): only the stretches from the entrance
	-- (polyline 1's first point) to each owned module's join are drawn, and a junction exists
	-- only where a polyline point sits on another polyline -- hence the mid-points at z = -28.
	-- It is a tree on purpose: a closed loop would lose one stretch to the shortest-path tree.
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
	-- Decking (INTERFACES "Paved blocks", "Wave 4.1"): one rect per module, shown once that module
	-- is owned. Each covers the module's pad and its harvested extents and runs out to the dock
	-- line (1.75 from the centreline) where the cell it faces is a straight or an end; the
	-- installations beside the cross tube's tees stop at the cell edge, because a tee cell is
	-- whole. No pod stands on a rect (the generator cuts lots round them), and rects keep 0.5
	-- apart, so no two slabs share a plane.
	blocks = {
		{
			min = Vector3.new(-18.18, 0, -46.4),
			max = Vector3.new(-1.75, 0, -37.64),
			slots = { "landingPad" },
		},
		{
			min = Vector3.new(1.75, 0, -46.48),
			max = Vector3.new(18.48, 0, -37.52),
			slots = { "solarArray" },
		},
		{
			min = Vector3.new(-46.5, 0, -46),
			max = Vector3.new(-29.75, 0, -38),
			slots = { "habitatPod" },
		},
		{
			min = Vector3.new(29.75, 0, -46.48),
			max = Vector3.new(46.46, 0, -37.56),
			slots = { "hydroponicsDome" },
		},
		{
			min = Vector3.new(-18.2, 0, -18.2),
			max = Vector3.new(-1.75, 0, -9.94),
			slots = { "oxygenGenerator" },
		},
		{
			min = Vector3.new(-46.4, 0, 10),
			max = Vector3.new(-29.75, 0, 18.28),
			slots = { "crewQuarters" },
		},
		{
			min = Vector3.new(-46, 0, -3.2),
			max = Vector3.new(-29.75, 0, 5.5),
			slots = { "colonyFlag" },
		},
		{
			min = Vector3.new(1.75, 0, -18.2),
			max = Vector3.new(18.43, 0, -10),
			slots = { "researchLab" },
		},
		{
			min = Vector3.new(-46.5, 0, -20),
			max = Vector3.new(-29.75, 0, -8),
			slots = { "roverBay" },
		},
		{
			min = Vector3.new(9.7, 0, 38),
			max = Vector3.new(26.25, 0, 46.26),
			slots = { "commsArray" },
		},
		{
			min = Vector3.new(31.5, 0, -32),
			max = Vector3.new(46.4, 0, -23.98),
			slots = { "lifeSupport" },
		},
		{
			min = Vector3.new(29.75, 0, -18.4),
			max = Vector3.new(46.48, 0, -9.6),
			slots = { "mineralExtractor" },
		},
		{
			min = Vector3.new(29.75, 0, -5.48),
			max = Vector3.new(46.48, 0, 3.48),
			slots = { "rockGarden" },
		},
		{
			min = Vector3.new(-17.8, 0, 9.88),
			max = Vector3.new(-1.75, 0, 18.37),
			slots = { "observationDome" },
		},
		{
			min = Vector3.new(29.75, 0, 8.11),
			max = Vector3.new(49.28, 0, 19.89),
			slots = { "fusionReactor" },
		},
		{
			min = Vector3.new(29.75, 0, 23.92),
			max = Vector3.new(46, 0, 32.02),
			slots = { "orbitalUplink" },
		},
		{
			min = Vector3.new(-26.25, 0, 37.6),
			max = Vector3.new(-9.6, 0, 46.4),
			slots = { "dockingBay" },
		},
		{
			min = Vector3.new(-49.28, 0, 36.11),
			max = Vector3.new(-29.75, 0, 47.89),
			slots = { "terraformStation" },
		},
		{
			min = Vector3.new(-46.2, 0, 22.6),
			max = Vector3.new(-29.75, 0, 31.2),
			slots = { "holoBeacon" },
		},
		{
			min = Vector3.new(1.75, 0, 10),
			max = Vector3.new(18.43, 0, 18.38),
			slots = { "medicalBay" },
		},
		{
			min = Vector3.new(29.75, 0, 36.06),
			max = Vector3.new(48.72, 0, 47.87),
			slots = { "spaceportTerminal" },
		},
		{
			min = Vector3.new(-46.39, 0, -33.23),
			max = Vector3.new(-31.5, 0, -24.84),
			slots = { "planetaryDefense" },
		},
		{
			min = Vector3.new(-6.8, 0, 25),
			max = Vector3.new(6.8, 0, 48.89),
			slots = { "launchTower" },
		},
	},
	-- Monorail loop (loop mode: no ramp). ring = 56 puts the track on the outermost lattice
	-- ring (cells 52.5..59.5), over the plot entrance, which the 6-stud soffit lets players
	-- walk under. `highway.clearBand` false: the regolith stays under the beam.
	highway = { ring = 56 },
}
