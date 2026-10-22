--!strict
-- Boot for the Expeditions place client (C1). Same contract as the hub's Main: Init every
-- controller, then Start every controller, in order. SoundController is a verbatim copy of
-- the hub's (the two client trees never require across each other), so the ambient bed and
-- the ui click behave identically in both places — and stay silent while every id in
-- Sounds.json is 0.
--
-- Order matters only for Init: SoundController builds its SoundGroups before anything can
-- Play, and CombatUIController comes last because its Start wires the other controllers
-- together (the run phase, the floors, the banner's frame, the toasts) once the HUD exists.
--
-- P1: CrowdRenderer and FeedbackController boot in every build but their Start is inert
-- unless the range's combat runs. MovementController is started by InputController's range
-- path, so it is not listed here. P3: AbilityFx (every player's lasting ability visuals) is
-- gated the same way. P4: so is VitalsController (being hit: health bar, hurt feedback,
-- knockback, down and up), which comes before CombatUIController, which mounts its HUD. And so
-- is ThreatFx (wave 2: the enemy's lanes, lines, circles and shots).
-- P5: that gate is CameraController.IsCrowdCombat, true in the range AND in every crowd
-- mission. The mode itself (the shared CombatMode, "range" or "mission") is read once in
-- CameraController.Init, which is why CameraController comes before every controller that asks.
-- L4 W2: LevelScenery draws a dressed level (the forest, its props and fires) and its mood on the
-- server's word (Workspace.Level's Dress attributes); without that word it does nothing, so the
-- range and the lobby boot it inert. It comes before CombatUIController, which hands it the toast.

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
	require(controllersFolder:WaitForChild("CrowdRenderer") :: ModuleScript) :: Controller,
	require(controllersFolder:WaitForChild("FeedbackController") :: ModuleScript) :: Controller,
	require(controllersFolder:WaitForChild("AbilityFx") :: ModuleScript) :: Controller,
	require(controllersFolder:WaitForChild("ThreatFx") :: ModuleScript) :: Controller,
	require(controllersFolder:WaitForChild("VitalsController") :: ModuleScript) :: Controller,
	require(controllersFolder:WaitForChild("LevelScenery") :: ModuleScript) :: Controller,
	require(controllersFolder:WaitForChild("CombatUIController") :: ModuleScript) :: Controller,
}

for _, controller in controllers do
	controller.Init()
end

for _, controller in controllers do
	controller.Start()
end

print("[CombatClient] booted")
