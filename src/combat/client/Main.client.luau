--!strict
-- Boot for the Expeditions place client (C0). Same contract as the hub's Main: Init every
-- controller, then Start every controller, in order. SoundController is a verbatim copy of
-- the hub's (the two client trees never require across each other), so the ambient bed and
-- the ui click behave identically in both places — and stay silent while every id in
-- Sounds.json is 0.

type Controller = {
	Init: () -> (),
	Start: () -> (),
}

-- Cast keeps this strict-clean whether the analyzer types Parent as Instance or Instance?.
local controllersFolder = (script.Parent :: Instance):WaitForChild("Controllers")

local controllers: { Controller } = {
	require(controllersFolder:WaitForChild("CombatUIController") :: ModuleScript) :: Controller,
	require(controllersFolder:WaitForChild("SoundController") :: ModuleScript) :: Controller,
}

for _, controller in controllers do
	controller.Init()
end

for _, controller in controllers do
	controller.Start()
end

print("[CombatClient] booted")
