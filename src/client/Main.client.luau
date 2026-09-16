--!strict
-- Boot order is frozen in docs/INTERFACES.md: Init all controllers, then Start all,
-- in the order UIController, SoundController, PlotVisualsController. M9 appends
-- CityDressingController, which only reads replicated plot attributes and never blocks boot.

type Controller = {
	Init: () -> (),
	Start: () -> (),
}

-- Cast keeps this strict-clean whether the analyzer types Parent as Instance or Instance?.
local controllersFolder = (script.Parent :: Instance):WaitForChild("Controllers")

local controllers: { Controller } = {
	require(controllersFolder:WaitForChild("UIController") :: ModuleScript) :: Controller,
	require(controllersFolder:WaitForChild("SoundController") :: ModuleScript) :: Controller,
	require(controllersFolder:WaitForChild("PlotVisualsController") :: ModuleScript) :: Controller,
	require(controllersFolder:WaitForChild("CityDressingController") :: ModuleScript) :: Controller,
}

for _, controller in controllers do
	controller.Init()
end

for _, controller in controllers do
	controller.Start()
end

print("[Client] booted")
