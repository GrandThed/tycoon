--!strict
-- Era 4 (OrbitalColony) plot layout: "bloom", the layout picked at the second gate of the organic
-- mock (INTERFACES "M12 wave 4 -- Orbital Colony", "Wave 4.1b -- organic Orbital"), reseated for
-- the four street-only city-changers ("Wave 4.1c -- city-changers on Bloom"). Positions are studs
-- relative to the plot centre, Y at ground level. rotationY is Roblox-native
-- CFrame.Angles(0, rad(r), 0): 0 faces -Z (the plot's front/hub edge), positive turns
-- counterclockwise seen from above (90 faces -X, 270 faces +X). Every pad is placed by
-- padPosition, unrotated.
--
-- A flower seen from above. A short stem runs in from the entrance to the heart: a ring of tube
-- with six landmarks inside it, their fronts on the ring and their backs to a small court. The
-- outer ring curves round the heart at twice its distance and echoes the monorail outside it; rows
-- of pods stand back to back between the two rings and against the loop. Behind the heart the
-- heart ring unwinds: its west arm leaves the circle, swings north and bends east into the back
-- arc, a third crescent that the Observation Dome closes. The outer ring never closes either: its
-- two ends flare out under the monorail, the west one to the Launch Tower in the back-left corner,
-- the east one to the spaceport in the back-right, and two short tubes cross the loop at the
-- front to the outposts in the front corners.
--
-- What shapes it:
--  * A tube is a `streets` polyline; the tools round every corner at two tube widths (6.48) and
--    sweep the half-pipe along that curve. The rings are written as corners 22.5 degrees apart
--    (outer) and 30 degrees apart (heart), so no tube runs straight for more than 16.5 studs
--    outside the stem and the four crossings of the loop.
--  * The plan is a tree: the stem crosses the outer ring and ends on the heart ring, and each
--    ring is an open crescent, so every stretch lies on a shortest path from the entrance.
--  * A branch leaves square off a straight leg (the stem's two crossings, the front corner
--    tubes), so the tubes into every hub stand 90 degrees apart.
--  * The outer ring's corners stand 42.2 from the centre: its outer row of pods (8 deep) ends
--    half a stud inside the monorail's band. The heart ring's corners stand 20 out: two rows of
--    pods fit back to back between the rings, and six landmarks fit inside the heart.
--  * A landmark inside the outer ring blanks 16 to 20 studs of its inner row, so only two stand
--    there, the Docking Bay and the Terraform Station on the east arm. Eight stand past the loop,
--    two in each corner, on the hub a tube ends at: a big one square in the corner and one on a
--    wing beside it. Every tube end has a landmark.
--  * The five street-only slots (the monorail and the four city-changers) are pads in the same
--    corners, on ground no pod can front: two in the front-right corner, one in each other.
--  * Slot k stands roughly k-th along the tubes. Tier 1 is the gate and the stem (the Landing Pad
--    and the Solar Array at the gate, the Habitat Pod closing the stem, the Hydroponics Dome
--    beside it); tier 2 the heart's west arm (Crew Quarters), its east arm (Research Lab, Comms
--    Array) and both front arcs of the outer ring, drawn by the outposts in the front corners
--    (Oxygen Generator, Rover Bay); tier 3 the west arm (the Mineral Extractor at the Launch
--    Tower's hub, which draws the west flare too) and the spiral (the Observation Dome); tier 4
--    the east arm (the Docking Bay); tier 5 only the last of the east arm, its flare and the
--    back-right corner. Along every arm the later landmark is the farther one, so a landmark
--    never takes over pods another has already grown.
--  * `district` is the fabric district a landmark pulls its neighbours toward
--    (eras.OrbitalColony.fabric.districts); a slot without one pulls nothing. The Landing Pad and
--    the Solar Array carry none: they are the lowest landmarks in the game, and without them the
--    stem's four domes and the gate answer to the Habitat Pod. Habitat holds the stem and the
--    heart ring's rows but for their far end, science that end and the back arc, industry the
--    west arm and the last of the east arm, port the rest of the east arm. The Orbital Uplink in
--    the heart carries none either, so the heart ring's west arm stays habitat all the way up.
--  * The skyline inside the loop rises away from the entrance: the Landing Pad (7.2) and the
--    Solar Array (6.4) at the gate and nothing over 11 on the front arcs, the Comms Array (21.2)
--    as the heart's spire on its far side, the Observation Dome (13.0) on the back arc, the
--    Terraform Station (23.0) at the back of the east arm. Past the loop the corners carry the
--    rest: the Fusion Reactor (16.9) front-left, the spaceport (16.5) back-right, the Launch
--    Tower (42.8) back-left, last.
return {
	plotSize = Vector3.new(120, 1, 120),
	baseColor = Color3.fromRGB(56, 53, 60),
	padSize = Vector3.new(6, 0.5, 6),
	-- every slot sets padPosition; the default is never used
	padOffset = 7.5,
	placeholderSize = Vector3.new(8, 8, 8),
	slots = {
		-- the seed: left of the gate, between the outer ring and the loop, facing the ring. No
		-- district: the lowest landmark in the game governs no pods
		landingPad = {
			position = Vector3.new(-7.15, 0, -45.6),
			rotationY = 180,
			padPosition = Vector3.new(-7.15, 0, -44.1),
			spur = { Vector3.new(-7.15, 0, -45.6), Vector3.new(-7.15, 0, -39.1) },
		},
		-- right of the gate, across the stem from the Landing Pad. No district either
		solarArray = {
			position = Vector3.new(8.15, 0, -45.6),
			rotationY = 180,
			padPosition = Vector3.new(8.15, 0, -44.1),
			spur = { Vector3.new(8.15, 0, -45.6), Vector3.new(8.15, 0, -39.1) },
		},
		-- the heart's first dome: inside the heart ring at the stem's end, closing the view up the
		-- stem. The stem's four domes and the gate answer to it
		habitatPod = {
			position = Vector3.new(0, 0, -9.8),
			rotationY = 0,
			padPosition = Vector3.new(0, 0, -11.3),
			spur = { Vector3.new(0, 0, -9.8), Vector3.new(0, 0, -17) },
			district = "habitat",
		},
		-- the heart's east side, the dome nearest the camera
		hydroponicsDome = {
			position = Vector3.new(10.97, 0, -6.33),
			rotationY = 300.03,
			padPosition = Vector3.new(11.32, 0, -6.53),
			spur = { Vector3.new(10.97, 0, -6.33), Vector3.new(16.73, 0, -9.66) },
			district = "habitat",
		},
		-- the first outpost: past the loop in the front-left corner, on the wing by the front edge.
		-- Its join is the corner tube's hub, so it draws the west front arc and closes that tube
		oxygenGenerator = {
			position = Vector3.new(-40, 0, -54.4),
			rotationY = 180,
			padPosition = Vector3.new(-40, 0, -51.4),
			spur = { Vector3.new(-40, 0, -54.4), Vector3.new(-44.12, 0, -44.12) },
			district = "industry",
		},
		-- streetOnly (Build the Monorail): no model and no path. Its pad stands outside the loop it
		-- buys, in the front-right corner, the one nearest the camera
		walkwayNetwork = {
			position = Vector3.new(49, 0, -55),
			rotationY = 270,
			padPosition = Vector3.new(49, 0, -55),
			spur = { Vector3.new(49, 0, -55) },
		},
		-- the heart's north-west. Its join draws the heart ring's west arm, and with no governing
		-- landmark between it and the stem that whole arm is habitat
		crewQuarters = {
			position = Vector3.new(-10.97, 0, 6.33),
			rotationY = 120.03,
			padPosition = Vector3.new(-11.32, 0, 6.53),
			spur = { Vector3.new(-10.97, 0, 6.33), Vector3.new(-16.73, 0, 9.66) },
			district = "habitat",
		},
		-- streetOnly (Raise the Colony Flags): no model and no path. Its pad stands beside the
		-- monorail's pad in the front-right corner
		colonyFlag = {
			position = Vector3.new(56, 0, -55),
			rotationY = 270,
			padPosition = Vector3.new(56, 0, -55),
			spur = { Vector3.new(56, 0, -55) },
		},
		-- the heart's north-east, the next join up the heart ring's east arm
		researchLab = {
			position = Vector3.new(10.97, 0, 6.33),
			rotationY = 239.97,
			padPosition = Vector3.new(11.32, 0, 6.53),
			spur = { Vector3.new(10.97, 0, 6.33), Vector3.new(16.73, 0, 9.66) },
			district = "science",
		},
		-- past the loop in the front-right corner, on the wing by the side edge, facing the hub.
		-- Its join draws the east front arc and closes that tube
		roverBay = {
			position = Vector3.new(54.4, 0, -41),
			rotationY = 90,
			padPosition = Vector3.new(52.9, 0, -38.5),
			spur = { Vector3.new(54.4, 0, -41), Vector3.new(44.12, 0, -44.12) },
			district = "port",
		},
		-- the heart's spire: inside the heart ring at its far side, where the east arm ends
		commsArray = {
			position = Vector3.new(0, 0, 12.12),
			rotationY = 180,
			padPosition = Vector3.new(0, 0, 13.62),
			spur = { Vector3.new(0, 0, 12.12), Vector3.new(0, 0, 19.32) },
			district = "science",
		},
		-- streetOnly (Green the Domes): no model and no path. Its pad stands past the loop in the
		-- front-left corner, on the wing by the side edge
		lifeSupport = {
			position = Vector3.new(-54, 0, -39),
			rotationY = 270,
			padPosition = Vector3.new(-54, 0, -39),
			spur = { Vector3.new(-54, 0, -39) },
		},
		-- past the loop beside the Launch Tower; its path runs round the tower's corner to the hub
		-- the west arm ends on, so its join draws the whole west arm
		mineralExtractor = {
			position = Vector3.new(-40.4, 0, 54.4),
			rotationY = 0,
			padPosition = Vector3.new(-40.4, 0, 51.4),
			spur = {
				Vector3.new(-40.4, 0, 54.4),
				Vector3.new(-42.5, 0, 45.5),
				Vector3.new(-49.51, 0, 37.99),
			},
			district = "industry",
		},
		-- streetOnly (Tend the Rock Gardens): no model and no path. Its pad stands past the loop in
		-- the back-left corner, on the far side of the Launch Tower's hub
		rockGarden = {
			position = Vector3.new(-56, 0, 36),
			rotationY = 90,
			padPosition = Vector3.new(-56, 0, 36),
			spur = { Vector3.new(-56, 0, 36) },
		},
		-- closes the back arc, facing back down it; its join draws the spiral
		observationDome = {
			position = Vector3.new(14.28, 0, 39.81),
			rotationY = 98.52,
			padPosition = Vector3.new(13.2, 0, 39.97),
			spur = { Vector3.new(14.28, 0, 39.81), Vector3.new(7.21, 0, 40.87) },
			district = "science",
		},
		-- the front-left corner itself, past the loop, facing the back; the Oxygen Generator's hub
		-- stands at its corner
		fusionReactor = {
			position = Vector3.new(-53, 0, -53),
			rotationY = 180,
			padPosition = Vector3.new(-50.1, 0, -50.1),
			spur = { Vector3.new(-53, 0, -53), Vector3.new(-44.12, 0, -44.12) },
			district = "industry",
		},
		-- the heart's south-west. No district, so it takes no pods from the Crew Quarters
		orbitalUplink = {
			position = Vector3.new(-10.97, 0, -6.33),
			rotationY = 59.97,
			padPosition = Vector3.new(-11.32, 0, -6.53),
			spur = { Vector3.new(-10.97, 0, -6.33), Vector3.new(-16.73, 0, -9.66) },
		},
		-- inside the outer ring's east corner; its join draws the east arm
		dockingBay = {
			position = Vector3.new(33.89, 0, 6.74),
			rotationY = 258.75,
			padPosition = Vector3.new(34.84, 0, 6.93),
			spur = { Vector3.new(33.89, 0, 6.74), Vector3.new(41.39, 0, 8.23) },
			district = "port",
		},
		-- inside the outer ring just before the east arm turns out toward the spaceport: the
		-- tallest thing inside the loop, at the back
		terraformStation = {
			position = Vector3.new(28.58, 0, 18.26),
			rotationY = 247.51,
			padPosition = Vector3.new(30.5, 0, 19.06),
			spur = { Vector3.new(28.58, 0, 18.26), Vector3.new(35.97, 0, 21.32) },
			district = "industry",
		},
		-- streetOnly (Light the Holo Beacons): no model and no path. Its pad stands past the loop
		-- in the back-right corner, on the spaceport's south side
		holoBeacon = {
			position = Vector3.new(53, 0, 40),
			rotationY = 90,
			padPosition = Vector3.new(53, 0, 40),
			spur = { Vector3.new(53, 0, 40) },
		},
		-- past the loop in the back-right corner, on the spaceport's west side. Its path meets the
		-- tube just short of the hub, so the pod nearest that hub stays the Medical Bay's when the
		-- spaceport is bought
		medicalBay = {
			position = Vector3.new(40, 0, 54.4),
			rotationY = 0,
			padPosition = Vector3.new(40, 0, 51.4),
			spur = { Vector3.new(40, 0, 54.4), Vector3.new(43.56, 0, 43.56) },
			district = "habitat",
		},
		-- the back-right corner itself, facing the hub the east arm ends on
		spaceportTerminal = {
			position = Vector3.new(53, 0, 53),
			rotationY = 0,
			padPosition = Vector3.new(50.1, 0, 50.1),
			spur = { Vector3.new(53, 0, 53), Vector3.new(44.12, 0, 44.12) },
			district = "port",
		},
		-- the turret: past the loop in the front-right corner, on the wing by the front edge
		planetaryDefense = {
			position = Vector3.new(40, 0, -54.4),
			rotationY = 180,
			padPosition = Vector3.new(40, 0, -51.4),
			spur = { Vector3.new(40, 0, -54.4), Vector3.new(44.12, 0, -44.12) },
		},
		-- the monument: the back-left corner, outside the loop, facing the entrance. The west arm's
		-- hub stands at its foot
		launchTower = {
			position = Vector3.new(-52.4, 0, 52.4),
			rotationY = 0,
			padPosition = Vector3.new(-55.4, 0, 48.4),
			spur = { Vector3.new(-52.4, 0, 52.4), Vector3.new(-49.51, 0, 37.99) },
			district = "port",
		},
	},
	-- Tube plan. Tubes grow with the modules (wave 1b): only the stretches from the entrance
	-- (polyline 1's first point) to each owned module's join are drawn, and a junction exists only
	-- where a polyline point sits on another polyline. It is a tree on purpose: a closed ring would
	-- lose one stretch to the shortest-path tree, so every ring here is open.
	streets = {
		-- 1: the stem: in from the entrance hub, square across the outer ring, and on to the heart
		-- ring, where it ends on the Habitat Pod. The four biggest lots (8 x 12) line it between
		-- the two rings
		{
			points = {
				Vector3.new(0, 0, -49),
				Vector3.new(0, 0, -39.1),
				Vector3.new(0, 0, -17),
			},
		},
		-- 2: the outer ring, written from its west end to its east end. It starts at the Launch
		-- Tower's hub in the back-left corner, comes in under the monorail, swings round the west
		-- side, crosses the stem in front of the heart (its front leg is pulled 2 studs in, so the
		-- Landing Pad and the Solar Array stand between it and the loop), swings round the east
		-- side and flares out under the monorail again to the spaceport's hub in the back-right
		-- corner
		{
			points = {
				Vector3.new(-49.51, 0, 37.99),
				Vector3.new(-37.76, 0, 28.98),
				Vector3.new(-36.55, 0, 21.1),
				Vector3.new(-41.39, 0, 8.23),
				Vector3.new(-41.39, 0, -8.23),
				Vector3.new(-35.09, 0, -23.45),
				Vector3.new(-23.45, 0, -35.09),
				Vector3.new(-8.23, 0, -39.1),
				Vector3.new(8.23, 0, -39.1),
				Vector3.new(23.45, 0, -35.09),
				Vector3.new(35.09, 0, -23.45),
				Vector3.new(41.39, 0, -8.23),
				Vector3.new(41.39, 0, 8.23),
				Vector3.new(35.09, 0, 23.45),
				Vector3.new(33.66, 0, 33.66),
				Vector3.new(44.12, 0, 44.12),
			},
		},
		-- 3: the heart ring and its spiral, written from the east arm's end. From the Comms Array
		-- at the top it runs clockwise round the heart, past the stem's end at the bottom and up
		-- the west side; at the north-west it leaves the circle, swings north past the heart and
		-- bends east into the back arc, which the Observation Dome closes
		{
			points = {
				Vector3.new(0, 0, 19.32),
				Vector3.new(5.18, 0, 19.32),
				Vector3.new(14.14, 0, 14.14),
				Vector3.new(19.32, 0, 5.18),
				Vector3.new(19.32, 0, -5.18),
				Vector3.new(14.14, 0, -14.14),
				Vector3.new(5.18, 0, -17),
				Vector3.new(-5.18, 0, -17),
				Vector3.new(-14.14, 0, -14.14),
				Vector3.new(-19.32, 0, -5.18),
				Vector3.new(-19.32, 0, 5.18),
				Vector3.new(-14.14, 0, 14.14),
				Vector3.new(-17.5, 0, 25),
				Vector3.new(-17.1, 0, 36.7),
				Vector3.new(-1.47, 0, 42.17),
				Vector3.new(7.21, 0, 40.87),
			},
		},
		-- 4: the front-left corner tube: square off the outer ring and out under the monorail to
		-- the hub the Oxygen Generator and the Fusion Reactor stand on
		{
			points = {
				Vector3.new(-29.27, 0, -29.27),
				Vector3.new(-44.12, 0, -44.12),
			},
		},
		-- 5: the front-right corner tube: square off the outer ring and out under the monorail to
		-- the hub the Rover Bay and the defence turret stand on
		{
			points = {
				Vector3.new(29.27, 0, -29.27),
				Vector3.new(44.12, 0, -44.12),
			},
		},
	},
	-- Monorail loop: a circle of radius 56 (`highway.round`), 48 segments, a pier at each one's
	-- middle. The plot's way in passes under it between two piers, and so do the four tubes that
	-- cross it: at 45, 142.5, 225 and 315 degrees, each halfway between two piers.
	highway = { ring = 56 },
}
