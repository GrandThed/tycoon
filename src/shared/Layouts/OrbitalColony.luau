--!strict
-- Era 4 (OrbitalColony) plot layout: the GROUNDWORK of the organic mock (INTERFACES "M12 wave 4 --
-- Orbital Colony", "Wave 4.1b -- organic Orbital"). It proves the tools end to end -- swept tubes,
-- hubs, aprons, a lane, the round monorail, a tube out to a corner -- and the candidate layouts
-- "vine" and "bloom" replace it. Positions are studs relative to the plot centre, Y at ground
-- level. rotationY is Roblox-native CFrame.Angles(0, rad(r), 0): 0 faces -Z (the plot's front/hub
-- edge), positive turns counterclockwise seen from above (90 faces -X, 270 faces +X). Every pad is
-- placed by padPosition, unrotated.
--
-- How an organic colony is written:
--  * A tube is a `streets` polyline. The tools and the client round every corner with an arc two
--    tube widths in radius (6.48) and sweep the half-pipe along that curve, so a tube curves where
--    its polyline turns: a few points, each leg long enough to hold its corner's arc (about 2
--    studs of leg for a 30 degree turn, 4 for 60), or the bend is refused as tighter than 6.
--  * A hub stands at every node where tubes branch or end. Two tubes into one hub leave it at
--    least 90 degrees apart, so a branch leaves from the outside of a bend of the tube it joins
--    (the three pipes share the turn) or square off a straight run. The plan stays a tree.
--  * A landmark is turned to face its tube: its path is two points, the anchor and the join on
--    the polyline, square to the tube there. The pad lies between, its near corner 2 studs from
--    the centreline (a tube keeps 1.75), and the building stands behind the pad. The path, the pad
--    and the building's ground are the landmark's apron: decking that arrives with the purchase.
--  * The monorail is a circle of radius 56. Nothing stands in its band (52.5 to 59.5 from the
--    centre) but a tube that crosses it steeply, clear of the pier feet. The corners of the plot
--    outside the loop are ground like any other.
--  * `district` is the fabric district a landmark pulls its neighbours toward
--    (eras.OrbitalColony.fabric.districts); a slot without one pulls nothing.
return {
	plotSize = Vector3.new(120, 1, 120),
	baseColor = Color3.fromRGB(56, 53, 60),
	padSize = Vector3.new(6, 0.5, 6),
	-- every slot sets padPosition; the default is never used
	padOffset = 7.5,
	placeholderSize = Vector3.new(8, 8, 8),
	slots = {
		landingPad = {
			position = Vector3.new(-6.5, 0, -42.5),
			rotationY = 270,
			padPosition = Vector3.new(-5, 0, -42.5),
			spur = { Vector3.new(-6.5, 0, -42.5), Vector3.new(0, 0, -42.5) },
			district = "port",
		},
		solarArray = {
			position = Vector3.new(6.5, 0, -42.5),
			rotationY = 90,
			padPosition = Vector3.new(5, 0, -42.5),
			spur = { Vector3.new(6.5, 0, -42.5), Vector3.new(0, 0, -42.5) },
			district = "industry",
		},
		habitatPod = {
			position = Vector3.new(-9.39, 0, -29.48),
			rotationY = 249.44,
			padPosition = Vector3.new(-8.79, 0, -29.26),
			spur = { Vector3.new(-9.39, 0, -29.48), Vector3.new(-3.3, 0, -27.2) },
			district = "habitat",
		},
		hydroponicsDome = {
			position = Vector3.new(2.79, 0, -24.92),
			rotationY = 69.44,
			padPosition = Vector3.new(2.19, 0, -25.14),
			spur = { Vector3.new(2.79, 0, -24.92), Vector3.new(-3.3, 0, -27.2) },
			district = "habitat",
		},
		oxygenGenerator = {
			position = Vector3.new(-12.5, 0, -12),
			rotationY = 270,
			padPosition = Vector3.new(-11, 0, -12),
			spur = { Vector3.new(-12.5, 0, -12), Vector3.new(-6, 0, -12) },
			district = "industry",
		},
		walkwayNetwork = {
			position = Vector3.new(15, 0, -38.1),
			rotationY = 0,
			padPosition = Vector3.new(15, 0, -38.1),
			spur = { Vector3.new(15, 0, -38.1) },
		},
		crewQuarters = {
			position = Vector3.new(0.5, 0, -12),
			rotationY = 90,
			padPosition = Vector3.new(-1, 0, -12),
			spur = { Vector3.new(0.5, 0, -12), Vector3.new(-6, 0, -12) },
			district = "habitat",
		},
		colonyFlag = {
			position = Vector3.new(16.14, 0, -23.02),
			rotationY = 317.29,
			padPosition = Vector3.new(16.32, 0, -23.22),
			spur = { Vector3.new(16.14, 0, -23.02), Vector3.new(20.55, 0, -27.8) },
		},
		researchLab = {
			position = Vector3.new(26.91, 0, -30.78),
			rotationY = 137.29,
			padPosition = Vector3.new(26.73, 0, -30.58),
			spur = { Vector3.new(26.91, 0, -30.78), Vector3.new(22.5, 0, -26) },
			district = "science",
		},
		roverBay = {
			position = Vector3.new(24.69, 0, -10.42),
			rotationY = 284.04,
			padPosition = Vector3.new(25.53, 0, -10.63),
			spur = { Vector3.new(24.69, 0, -10.42), Vector3.new(31, 0, -12) },
			district = "port",
		},
		commsArray = {
			position = Vector3.new(37.31, 0, -13.58),
			rotationY = 104.04,
			padPosition = Vector3.new(36.47, 0, -13.37),
			spur = { Vector3.new(37.31, 0, -13.58), Vector3.new(31, 0, -12) },
			district = "science",
		},
		lifeSupport = {
			position = Vector3.new(34.73, 0, 2.94),
			rotationY = 14.04,
			padPosition = Vector3.new(34.53, 0, 2.1),
			spur = { Vector3.new(34.73, 0, 2.94), Vector3.new(33, 0, -4) },
		},
		mineralExtractor = {
			position = Vector3.new(-12.61, 0, 4.65),
			rotationY = 15.95,
			padPosition = Vector3.new(-12.83, 0, 3.89),
			spur = { Vector3.new(-12.61, 0, 4.65), Vector3.new(-14.4, 0, -1.6) },
			district = "industry",
		},
		rockGarden = {
			position = Vector3.new(-21.51, 0, 11.96),
			rotationY = 50.19,
			padPosition = Vector3.new(-21.72, 0, 11.79),
			spur = { Vector3.new(-21.51, 0, 11.96), Vector3.new(-26.5, 0, 7.8) },
		},
		observationDome = {
			position = Vector3.new(-36.5, 0, 20),
			rotationY = 270,
			padPosition = Vector3.new(-35, 0, 20),
			spur = { Vector3.new(-36.5, 0, 20), Vector3.new(-30, 0, 20) },
			district = "science",
		},
		fusionReactor = {
			position = Vector3.new(-31.15, 0, 0.88),
			rotationY = 230.19,
			padPosition = Vector3.new(-29.78, 0, 2.01),
			spur = { Vector3.new(-31.15, 0, 0.88), Vector3.new(-25, 0, 6) },
			district = "industry",
		},
		orbitalUplink = {
			position = Vector3.new(-22.8, 0, 28),
			rotationY = 90,
			padPosition = Vector3.new(-24.3, 0, 28),
			spur = { Vector3.new(-22.8, 0, 28), Vector3.new(-30, 0, 28) },
		},
		dockingBay = {
			position = Vector3.new(11, 0, 3.5),
			rotationY = 180,
			padPosition = Vector3.new(11, 0, 5),
			spur = { Vector3.new(11, 0, 3.5), Vector3.new(11, 0, 10) },
			district = "port",
		},
		terraformStation = {
			position = Vector3.new(32.06, 0, 17.88),
			rotationY = 120.96,
			padPosition = Vector3.new(30.44, 0, 18.85),
			spur = { Vector3.new(32.06, 0, 17.88), Vector3.new(25.2, 0, 22) },
			district = "industry",
		},
		holoBeacon = {
			position = Vector3.new(11, 0, 16.5),
			rotationY = 0,
			padPosition = Vector3.new(11, 0, 15),
			spur = { Vector3.new(11, 0, 16.5), Vector3.new(11, 0, 10) },
		},
		medicalBay = {
			position = Vector3.new(-4.68, 0, 17.33),
			rotationY = 255.07,
			padPosition = Vector3.new(-3.88, 0, 17.54),
			spur = { Vector3.new(-4.68, 0, 17.33), Vector3.new(1.6, 0, 19) },
			district = "habitat",
		},
		spaceportTerminal = {
			position = Vector3.new(20.74, 0, 30.12),
			rotationY = 300.96,
			padPosition = Vector3.new(22.36, 0, 29.15),
			spur = { Vector3.new(20.74, 0, 30.12), Vector3.new(27.6, 0, 26) },
			district = "port",
		},
		planetaryDefense = {
			position = Vector3.new(53.5, 0, 50.5),
			rotationY = 0,
			padPosition = Vector3.new(46.2, 0, 50.5),
			spur = {
				Vector3.new(53.5, 0, 50.5),
				Vector3.new(46.2, 0, 50.5),
				Vector3.new(44.5, 0, 44.5),
			},
		},
		launchTower = {
			position = Vector3.new(0, 0, 41.7),
			rotationY = 0,
			padPosition = Vector3.new(0, 0, 31.5),
			spur = { Vector3.new(0, 0, 41.7), Vector3.new(0, 0, 25) },
			district = "port",
		},
	},
	-- Tube plan. Tubes grow with the modules (wave 1b): only the stretches from the entrance
	-- (polyline 1's first point) to each owned module's join are drawn, and a junction exists only
	-- where a polyline point sits on another polyline. It is a tree on purpose: a closed loop would
	-- lose one stretch to the shortest-path tree.
	streets = {
		-- 1: the main tube: in from the entrance and up the middle in a long S to the Launch Tower's
		-- forecourt. It bends at each junction, so the three pipes there share the turn
		{
			points = {
				Vector3.new(0, 0, -49),
				Vector3.new(0, 0, -36),
				Vector3.new(-6, 0, -20),
				Vector3.new(-6, 0, -4),
				Vector3.new(4, 0, 10),
				Vector3.new(0, 0, 25),
			},
		},
		-- 2: the east curl, off the first bend
		{
			points = {
				Vector3.new(0, 0, -36),
				Vector3.new(16, 0, -32),
				Vector3.new(29, 0, -20),
				Vector3.new(33, 0, -4),
			},
		},
		-- 3: the west curl, off the third bend
		{
			points = {
				Vector3.new(-6, 0, -4),
				Vector3.new(-20, 0, 0),
				Vector3.new(-30, 0, 12),
				Vector3.new(-30, 0, 28),
			},
		},
		-- 4: the corner tube, off the fourth bend: east, then out along the plot's diagonal, under
		-- the monorail between two piers and into the back corner
		{
			points = {
				Vector3.new(4, 0, 10),
				Vector3.new(18, 0, 10),
				Vector3.new(30, 0, 30),
				Vector3.new(44.5, 0, 44.5),
			},
		},
	},
	-- Monorail loop: a circle of radius 56 (`highway.round`), 48 segments, a pier at each one's
	-- middle. The plot's way in passes under it between two piers.
	highway = { ring = 56 },
}
