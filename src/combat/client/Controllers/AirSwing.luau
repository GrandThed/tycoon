--!strict
-- L1b Wave 2 (docs/INTERFACES.md "Wave 2 — the long road", L1b-W2-13 and -14): one melee
-- swing per jump, the client's half. The server judges every melee swing at the origin it is
-- sent from (WeaponService.OnAttack) and refuses a second airborne one before a landing; this
-- asks the same question first, so InputController never sends a swing the server would
-- refuse and never draws an effect it would take back.
--
-- * The question is the server's, on the same numbers: the origin's height over the floor
--   under it, probed as WeaponService.floorUnder probes (HitShapes.GROUND_PROBE_LIFT above
--   it, GROUND_PROBE_DEPTH down, collidable world only, every character skipped), against
--   the standing offset (HipHeight plus half the root) plus SwingGate.AIR_MARGIN_STUDS.
-- * One ray per swing attempt, never per frame: Judge runs only when a swing is due.
-- * `used` clears on a grounded swing (Took) and on the local Humanoid's landing (its
--   StateChanged to Landed). A double jump is no landing. A new character starts clear.
-- * The landing connection is this module's; Destroy drops it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local HitShapes = require(sharedFolder:WaitForChild("HitShapes"))
local SwingGate = require(sharedFolder:WaitForChild("SwingGate"))

local HALF = 0.5

local state = {
	gate = SwingGate.New(),
	-- The Humanoid whose landings are watched, and that watch.
	humanoid = nil :: Humanoid?,
	landed = nil :: RBXScriptConnection?,
}

local AirSwing = {}

local function watch(humanoid: Humanoid): ()
	if state.humanoid == humanoid then
		return
	end
	local previous = state.landed
	if previous ~= nil then
		previous:Disconnect()
	end
	state.humanoid = humanoid
	SwingGate.Landed(state.gate)
	state.landed = humanoid.StateChanged:Connect(
		function(_old: Enum.HumanoidStateType, new: Enum.HumanoidStateType)
			if new == Enum.HumanoidStateType.Landed then
				SwingGate.Landed(state.gate)
			end
		end
	)
end

-- The world as the server's floor probe sees it: players skipped, collidable parts only (the
-- tent's marker and every walk-through piece are not floors). Built per attempt, which is
-- per swing, so a character that came or went is always current.
local function probeParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	local ignored: { Instance } = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character ~= nil then
			table.insert(ignored, character)
		end
	end
	params.FilterDescendantsInstances = ignored
	return params
end

-- (allowed, airborne) for a melee swing sent from `origin` by this rig. Not allowed = the
-- second airborne swing of a jump: drop it (no effect, no send, nothing queued).
function AirSwing.Judge(origin: Vector3, root: BasePart, humanoid: Humanoid): (boolean, boolean)
	watch(humanoid)
	local result = Workspace:Raycast(
		origin + Vector3.new(0, HitShapes.GROUND_PROBE_LIFT, 0),
		Vector3.new(0, -HitShapes.GROUND_PROBE_DEPTH, 0),
		probeParams()
	)
	local height = if result ~= nil then origin.Y - result.Position.Y else nil
	local airborne = SwingGate.IsAir(height, humanoid.HipHeight + root.Size.Y * HALF)
	return SwingGate.Allows(state.gate, airborne), airborne
end

-- A swing was sent: an airborne one spends the jump's swing, a grounded one clears it.
function AirSwing.Took(airborne: boolean): ()
	SwingGate.Took(state.gate, airborne)
end

function AirSwing.Destroy(): ()
	local connection = state.landed
	if connection ~= nil then
		connection:Disconnect()
	end
	state.landed = nil
	state.humanoid = nil
	SwingGate.Landed(state.gate)
end

return AirSwing
