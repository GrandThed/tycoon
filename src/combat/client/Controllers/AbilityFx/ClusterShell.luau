--!strict
-- AbilityFx child: the `clusterShell` visual. Returns its builder; the parent module explains the
-- division of labour with FeedbackController, the timing rule and the low-end gate.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Tuning = require(sharedFolder:WaitForChild("Tuning"))
local HitShapes = require(sharedFolder:WaitForChild("HitShapes"))

local uiFolder = script.Parent.Parent.Parent:WaitForChild("UI")
local Theme = require(uiFolder:WaitForChild("Theme"))
local Shared = require(script.Parent:WaitForChild("Shared"))
local Pool = require(script.Parent:WaitForChild("Pool"))

type Def = Shared.Def
type Cast = Shared.Cast
type AbilityStrike = Shared.AbilityStrike
type Kit = Shared.Kit
type Step = Shared.Step
type StrikeHook = Shared.StrikeHook

local lowEnd = Shared.lowEnd
local TAU = Shared.TAU
local UP = Shared.UP
local FLAT_U = Shared.FLAT_U
local FLAT_V = Shared.FLAT_V
local RING_WIDTH = Shared.RING_WIDTH
local RING_HEIGHT = Shared.RING_HEIGHT
local ABILITY_COLOR = Shared.ABILITY_COLOR
local lerp = Shared.lerp
local clamp01 = Shared.clamp01
local positive = Shared.positive
local nonNegative = Shared.nonNegative
local takePart = Pool.takePart
local takeParts = Pool.takeParts
local place = Pool.place
local show = Pool.show
local showAll = Pool.showAll
local layCircle = Pool.layCircle

type Bomblet = { shell: BasePart, blink: BasePart, ring: { BasePart }, point: Vector3 }

-- Cluster Shell: bomblets hop out of the splash and blink over their exact blast radius.
local CLUSTER_SHELL_COLOR = Theme.COMBAT_RANGE_SHELL_COLOR
local CLUSTER_BLINK_COLOR = Color3.fromRGB(255, 50, 40)
local CLUSTER_RING_COLOR = ABILITY_COLOR
local CLUSTER_PENDING_SLACK = 1
local CLUSTER_MATCH_STUDS = 1
local CLUSTER_HOP_SECONDS = 0.25
local CLUSTER_HOP_SHARE = 0.6 -- a short fuse still leaves time to blink after the hop
local CLUSTER_HOP_HEIGHT = 4
local CLUSTER_SIZE = 0.8
local CLUSTER_BLINK_SIZE = 1.1
local CLUSTER_BLINK_TRANSPARENCY = 0.1
local CLUSTER_BLINK_SLOW = 0.22
local CLUSTER_BLINK_FAST = 0.06
local CLUSTER_RING_SEGMENTS = 12
local CLUSTER_RING_SEGMENTS_LOW_END = 8
local CLUSTER_RING_ON = 0.2
local CLUSTER_RING_OFF = 0.7
local CLUSTER_TAIL_SECONDS = 0.03

-- Cluster Shell: nothing until the shell bursts (Feedback flies it). The first sphere strike
-- with an end point from this caster's clusterShell is the splash: bomblets hop out to exactly
-- HitShapes.Scatter(impact, count, spacing, seq), the server's points at the impact's height,
-- and blink ever faster over a ring of their exact blastRadius until delaySeconds after the
-- splash, when Feedback draws their blasts. Bomblet blasts (sphere strikes on those points, no
-- end point) are claimed here so they never start a second cast's bomblets.
local function buildClusterShell(cast: Cast, def: Def, kit: Kit): (Step?, StrikeHook?)
	local count = positive(def.count)
	local spacing = nonNegative(def.spacing)
	local delay = nonNegative(def.delaySeconds)
	local blastRadius = positive(def.blastRadius)
	if count == nil or spacing == nil or delay == nil or blastRadius == nil then
		return nil, nil
	end
	local fuse: number = delay
	local blast: number = blastRadius
	local pending = Tuning.Get().shooting.projectileMaxSeconds + CLUSTER_PENDING_SLACK
	local hop = math.min(CLUSTER_HOP_SECONDS, fuse * CLUSTER_HOP_SHARE)
	local impact: Vector3? = nil
	local abandoned = false
	local points: { Vector3 } = {}
	local splashAt: number? = nil
	local bomblets: { Bomblet } = {}
	local blinkPhase = 0

	local function spawnBomblets(): ()
		local segments = if lowEnd then CLUSTER_RING_SEGMENTS_LOW_END else CLUSTER_RING_SEGMENTS
		for _, point in points do
			local shell =
				takePart(kit, Enum.PartType.Ball, CLUSTER_SHELL_COLOR, Enum.Material.SmoothPlastic)
			shell.Size = Vector3.one * CLUSTER_SIZE
			local blink = takePart(kit, Enum.PartType.Ball, CLUSTER_BLINK_COLOR, Enum.Material.Neon)
			blink.Size = Vector3.one * CLUSTER_BLINK_SIZE
			local ring = takeParts(
				kit,
				segments,
				Enum.PartType.Block,
				CLUSTER_RING_COLOR,
				Enum.Material.Neon
			)
			layCircle(ring, point, FLAT_U, FLAT_V, blast, 0, TAU, RING_WIDTH, RING_HEIGHT, true)
			table.insert(bomblets, { shell = shell, blink = blink, ring = ring, point = point })
		end
	end

	local function step(t: number, dt: number): boolean
		if abandoned then
			return false
		end
		local burstAt = splashAt
		local origin = impact
		if burstAt == nil then
			if origin == nil then
				return t < pending
			end
			splashAt = t
			burstAt = t
			spawnBomblets()
		end
		if origin == nil or burstAt == nil then
			return false
		end
		local age = t - burstAt
		if age >= fuse + CLUSTER_TAIL_SECONDS then
			return false
		end
		local u = if fuse > 0 then clamp01(age / fuse) else 1
		blinkPhase += dt / lerp(CLUSTER_BLINK_SLOW, CLUSTER_BLINK_FAST, u)
		local on = blinkPhase % 1 < 0.5
		local h = if hop > 0 then clamp01(age / hop) else 1
		for _, bomblet in bomblets do
			local position = origin:Lerp(bomblet.point, h)
				+ UP * (CLUSTER_HOP_HEIGHT * 4 * h * (1 - h))
			place(bomblet.shell, CFrame.new(position))
			show(bomblet.shell, 0, 1)
			place(bomblet.blink, CFrame.new(position))
			show(bomblet.blink, CLUSTER_BLINK_TRANSPARENCY, if on then 1 else 0)
			local ringV = if h >= 1 then 1 else 0
			showAll(bomblet.ring, if on then CLUSTER_RING_ON else CLUSTER_RING_OFF, ringV)
		end
		return true
	end

	local function onStrike(strike: AbilityStrike): boolean
		if impact == nil then
			if strike.shape == "sphere" and strike.endPoint ~= nil then
				local centre = strike.endPoint :: Vector3
				impact = centre
				points = HitShapes.Scatter(centre, count, spacing, cast.seq)
				return true
			end
			-- An empty end strike: a set or reset dropped the shell before it burst.
			if strike.shape == "ray" and strike.size <= 0 then
				abandoned = true
				return true
			end
			return false
		end
		for _, point in points do
			if (point - strike.origin).Magnitude <= CLUSTER_MATCH_STUDS then
				return true
			end
		end
		return false
	end

	return step, onStrike
end

return buildClusterShell
