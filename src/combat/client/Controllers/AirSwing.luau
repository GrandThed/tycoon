--!strict
-- L1b Wave 2 (docs/INTERFACES.md "Wave 2 — the long road", L1b-W2-13 and -14): one melee
-- swing per jump, the client's half. The server judges every melee swing at the origin it is
-- sent from (WeaponService.OnAttack) and refuses a second airborne one before a landing; this
-- asks the same question first, so InputController never sends a swing the server would
-- refuse and never draws an effect it would take back.
--
-- Fix round ui-1 (docs/prompts/l1b-w2-fix-round.md A-1): "has landed" and "is grounded" are
-- one pure rule, SwingGate, fed here with exactly the server's samples (WeaponService.trackAir):
-- * Every Heartbeat: the local root's Y, its vertical velocity, the footprint's floor and the
--   knockdown (MovementController.IsDown) go to SwingGate.Observe. That is what clears `used`
--   on a landing, on a held-Space hop whose one-frame contact a sample can step over, and on a
--   down and its get-up. The turn window is the client's (SwingGate.CLIENT_TURN_WINDOW_SECONDS),
--   stricter than the server's by one step of its 20 Hz copy, so a double jump close to the
--   floor is never a landing here that the server's coarser copy does not also see. Nothing else clears it: a Humanoid state the server cannot see (its
--   Landed, Running or GettingUp) would let a swing through for the server to refuse.
-- * The footprint probe is the server's: SwingGate.PROBE_POINTS rays from GROUND_PROBE_LIFT
--   above each of SwingGate.ProbePoint (the root's centre and its four corners), down
--   GROUND_PROBE_DEPTH, collidable world only, every character skipped; the highest floor wins,
--   so a ledge's lip, a fence top or a cover block under any corner reads grounded.
-- * At a swing, Judge probes at the swing's origin (the root's position, which is what is sent)
--   and asks SwingGate.Judge with no lag: the samples here are the swinger's own, not a copy, so
--   Judge never counts a landing ahead of them; only the touchdown's own sample clears.
-- * A new character starts clear (SwingGate.Landed). The Heartbeat connection is this module's;
--   it starts at the first Judge and Destroy drops it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local HitShapes = require(sharedFolder:WaitForChild("HitShapes"))
local SwingGate = require(sharedFolder:WaitForChild("SwingGate"))

local MovementController = require(script.Parent:WaitForChild("MovementController"))

local CONST = {
	HALF = 0.5,
	-- How often the probe's character filter is rebuilt. Characters come and go rarely; a
	-- rebuild per frame would allocate for nothing.
	FILTER_SECONDS = 0.25,
	-- The local swinger's samples are its own, so nothing trails the swing.
	LAG_SECONDS = 0,
}

local state = {
	gate = SwingGate.New(),
	-- The character whose root is sampled, and its parts as last found.
	character = nil :: Model?,
	root = nil :: BasePart?,
	humanoid = nil :: Humanoid?,
	sampler = nil :: RBXScriptConnection?,
	params = nil :: RaycastParams?,
	filteredAt = -math.huge,
}

local AirSwing = {}

-- The world as the server's floor probe sees it: players skipped, collidable parts only (the
-- tent's marker and every walk-through piece are not floors).
local function probeParams(): RaycastParams
	local now = os.clock()
	local params = state.params
	if params ~= nil and now - state.filteredAt < CONST.FILTER_SECONDS then
		return params
	end
	local fresh = params or RaycastParams.new()
	fresh.FilterType = Enum.RaycastFilterType.Exclude
	fresh.RespectCanCollide = true
	local ignored: { Instance } = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character ~= nil then
			table.insert(ignored, character)
		end
	end
	fresh.FilterDescendantsInstances = ignored
	state.params = fresh
	state.filteredAt = now
	return fresh
end

-- The highest floor under the root's footprint placed at `at` (nil = none), as
-- WeaponService.footprintFloor probes it.
local function footprintFloor(at: Vector3, root: BasePart): number?
	local params = probeParams()
	local right = root.CFrame.RightVector
	local size = root.Size
	local halfX, halfZ = size.X * CONST.HALF, size.Z * CONST.HALF
	local depth = Vector3.new(0, -HitShapes.GROUND_PROBE_DEPTH, 0)
	local liftY = at.Y + HitShapes.GROUND_PROBE_LIFT
	local floorY: number? = nil
	for index = 1, SwingGate.PROBE_POINTS do
		local x, z = SwingGate.ProbePoint(index, at.X, at.Z, right.X, right.Z, halfX, halfZ)
		local hit = Workspace:Raycast(Vector3.new(x, liftY, z), depth, params)
		floorY = SwingGate.Higher(floorY, if hit ~= nil then hit.Position.Y else nil)
	end
	return floorY
end

local function standOffset(root: BasePart, humanoid: Humanoid): number
	return humanoid.HipHeight + root.Size.Y * CONST.HALF
end

-- The local character's root and Humanoid, refound only when the character changes or a part
-- left it; a new character starts the gate clear.
local function localRig(): (BasePart?, Humanoid?)
	local player = Players.LocalPlayer
	local character = if player ~= nil then player.Character else nil
	if character ~= state.character then
		state.character = character
		state.root = nil
		state.humanoid = nil
		SwingGate.Landed(state.gate)
	end
	if character == nil then
		return nil, nil
	end
	local root = state.root
	if root == nil or root.Parent ~= character then
		local found = character:FindFirstChild("HumanoidRootPart")
		root = if found ~= nil and found:IsA("BasePart") then found else nil
		state.root = root
	end
	local humanoid = state.humanoid
	if humanoid == nil or humanoid.Parent ~= character then
		humanoid = character:FindFirstChildOfClass("Humanoid")
		state.humanoid = humanoid
	end
	return root, humanoid
end

-- One sample, every frame, exactly the server's: with no root or Humanoid there is none.
local function sample(): ()
	local root, humanoid = localRig()
	if root == nil or humanoid == nil then
		return
	end
	local position = root.Position
	SwingGate.Observe(
		state.gate,
		position.Y,
		root.AssemblyLinearVelocity.Y,
		footprintFloor(position, root),
		standOffset(root, humanoid),
		MovementController.IsDown(),
		SwingGate.CLIENT_TURN_WINDOW_SECONDS
	)
end

-- Started on the first swing, with one sample at once, so the swing that starts it is judged
-- against this frame's verdict as the server's continuous samples would be.
local function ensureSampling(): ()
	if state.sampler == nil then
		state.sampler = RunService.Heartbeat:Connect(sample)
		sample()
	end
end

-- (allowed, airborne) for a melee swing sent from `origin` by this rig. Not allowed = the
-- second airborne swing of a jump: drop it (no effect, no send, nothing queued).
function AirSwing.Judge(origin: Vector3, root: BasePart, humanoid: Humanoid): (boolean, boolean)
	ensureSampling()
	-- A character swapped since the last frame starts clear before it is judged.
	localRig()
	return SwingGate.Judge(
		state.gate,
		origin.Y,
		footprintFloor(origin, root),
		standOffset(root, humanoid),
		CONST.LAG_SECONDS
	)
end

-- A swing was sent: an airborne one spends the jump's swing, a grounded one clears it.
function AirSwing.Took(airborne: boolean): ()
	SwingGate.Took(state.gate, airborne)
end

function AirSwing.Destroy(): ()
	local sampler = state.sampler
	if sampler ~= nil then
		sampler:Disconnect()
	end
	state.sampler = nil
	state.character = nil
	state.root = nil
	state.humanoid = nil
	state.params = nil
	state.filteredAt = -math.huge
	SwingGate.Landed(state.gate)
end

return AirSwing
