--!strict
-- Era 4 (OrbitalColony) plot layout. Positions are studs relative to plot center,
-- Y at ground level. rotationY is Roblox-native CFrame.Angles(0, rad(r), 0): 0
-- faces -Z (the plot's front/hub edge), positive turns counterclockwise seen from
-- above (90 faces -X, 270 faces +X). Pads spawn padOffset studs along that facing.
-- Personality: a radial colony. The fusion reactor sits at the core, habitat and
-- science modules orbit it in two rings (r ~ 20 and r ~ 36-42) all facing inward
-- (diagonal spots use 45-degree rotations, so pads land between module and core),
-- edge installations guard the rim, and the launch tower flanked by the terminal
-- buildings greets arriving players. Dark regolith base for the era swap.
return {
	plotSize = Vector3.new(120, 1, 120),
	baseColor = Color3.fromRGB(56, 53, 60),
	padSize = Vector3.new(6, 0.5, 6),
	padOffset = 8,
	placeholderSize = Vector3.new(8, 8, 8),
	slots = {
		-- colony core
		fusionReactor = { position = Vector3.new(0, 0, 0), rotationY = 0 },

		-- inner ring (r ~ 20): first essentials, all facing the core
		landingPad = { position = Vector3.new(-14, 0, -14), rotationY = 225 },
		solarArray = { position = Vector3.new(14, 0, -14), rotationY = 135 },
		habitatPod = { position = Vector3.new(-20, 0, 0), rotationY = 270 },
		hydroponicsDome = { position = Vector3.new(20, 0, 0), rotationY = 90 },
		oxygenGenerator = { position = Vector3.new(14, 0, 14), rotationY = 45 },
		crewQuarters = { position = Vector3.new(-14, 0, 14), rotationY = 315 },
		walkwayNetwork = { position = Vector3.new(0, 0, 20), rotationY = 0 },

		-- outer ring (r ~ 36): industry and science, facing the core
		researchLab = { position = Vector3.new(0, 0, 36), rotationY = 0 },
		roverBay = { position = Vector3.new(-30, 0, -30), rotationY = 225 },
		commsArray = { position = Vector3.new(30, 0, -30), rotationY = 135 },
		mineralExtractor = { position = Vector3.new(-36, 0, 0), rotationY = 270 },
		observationDome = { position = Vector3.new(36, 0, 0), rotationY = 90 },
		dockingBay = { position = Vector3.new(30, 0, 30), rotationY = 45 },
		terraformStation = { position = Vector3.new(-30, 0, 30), rotationY = 315 },

		-- decor tucked between the rings
		colonyFlag = { position = Vector3.new(-30, 0, -12), rotationY = 270 },
		rockGarden = { position = Vector3.new(30, 0, 12), rotationY = 90 },
		holoBeacon = { position = Vector3.new(-44, 0, -20), rotationY = 270 },

		-- rim installations
		lifeSupport = { position = Vector3.new(44, 0, -16), rotationY = 90 },
		orbitalUplink = { position = Vector3.new(-44, 0, 44), rotationY = 315 },
		planetaryDefense = { position = Vector3.new(44, 0, 44), rotationY = 45 },

		-- front gateway: terminal buildings flank the monument at the rim
		medicalBay = { position = Vector3.new(-16, 0, -44), rotationY = 0 },
		spaceportTerminal = { position = Vector3.new(16, 0, -44), rotationY = 0 },

		-- monument front-and-center, rocket facing arriving players
		launchTower = { position = Vector3.new(0, 0, -34), rotationY = 0 },
	},
}
