--!strict
-- Boot for the Expeditions place client (C1). Same contract as the hub's Main: Init every
-- controller, then Start every controller, in order. SoundController is a verbatim copy of
-- the hub's (the two client trees never require across each other), so the ambient bed and
-- the ui click behave identically in both places — and stay silent while every id in
-- Sounds.json is 0.
--
-- Order matters only for Init: SoundController builds its SoundGroups before anything can
-- Play, and CombatUIController comes last because its Start wires the other controllers
-- together (stance, gear, health, banners) once the HUD exists.

type Controller = {
	Init: () -> (),
	Start: () -> (),
}

-- Cast keeps this strict-clean whether the analyzer types Parent as Instance or Instance?.
local controllersFolder = (script.Parent :: Instance):WaitForChild("Controllers")

local controllers: { Controller } = {
	require(controllersFolder:WaitForChild("SoundController") :: ModuleScript) :: Controller,
	require(controllersFolder:WaitForChild("CameraController") :: ModuleScript) :: Controller,
	require(controllersFolder:WaitForChild("WeaponController") :: ModuleScript) :: Controller,
	require(controllersFolder:WaitForChild("InputController") :: ModuleScript) :: Controller,
	require(controllersFolder:WaitForChild("CombatFxController") :: ModuleScript) :: Controller,
	require(controllersFolder:WaitForChild("CombatUIController") :: ModuleScript) :: Controller,
}

for _, controller in controllers do
	controller.Init()
end

for _, controller in controllers do
	controller.Start()
end

print("[CombatClient] booted")
