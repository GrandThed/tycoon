--!strict
-- The enemy's side of the Proving Grounds' effects (docs/INTERFACES.md "P4 contracts" ->
-- "Wave 2 — roles", "The client"; docs/COMBAT_DESIGN.md sections 4 and 7). Everything an enemy
-- warns with or throws that is not its own body is drawn here, as AbilityFx draws the
-- player's lasting ability visuals:
--
--   Tells   the brute's lane and the marksman's line, from the crowd snapshot alone
--   Areas   the lobber's ground circle and the shot arcing into it, from `area`
--   Shots   the slinger's slow orbs, from `enemyShot` / `enemyShotEnd`
--   Pool    the pooled parts and the frame's one batched move
--   Cues, PlateBar   what CrowdRenderer hangs on a body (role cues, the plate's bar); they
--                    live in this folder but are that module's, and this one never calls them
--
-- Rules that hold for all of it:
--  * Drawn against server time. A lane and a line take their clock from CrowdRenderer, which
--    runs each attack on the server clock from the windup's first sighting; a shot and a
--    circle carry server times in their own effect. Nothing is simulated or timed locally,
--    so no tell can drift, and none shows its impact later than the server's.
--  * The client decides nothing. Who is hit arrives as `hurt` (VitalsController).
--  * Tells are information: nothing here is gated on Theme.reducedMotion (true on every
--    touch device) or thinned on Theme.lowEndDevice. Low-end loses only decoration: a shot's
--    tail and its halo's pulse, and half the bars of a circle's rim.
--  * One RenderStepped connection, no per-effect connection, no table per frame. The
--    snapshot-driven tells are pulled through one module-level callback.
--
-- Inert outside the range (CameraController.IsRange): missions keep CombatFxController's
-- `telegraph`, which this module never touches.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local CameraController = require(script.Parent:WaitForChild("CameraController"))
local CrowdRenderer = require(script.Parent:WaitForChild("CrowdRenderer"))
local Pool = require(script:WaitForChild("Pool"))
local Shots = require(script:WaitForChild("Shots"))
local Areas = require(script:WaitForChild("Areas"))
local Tells = require(script:WaitForChild("Tells"))

local ThreatFx = {}

local started = false
local connections: { RBXScriptConnection } = {}
-- The frame being drawn, read by onThreat (a module function, so a frame allocates no
-- closure).
local frameServerNow = 0
local frameDelta = 0

local function isNumber(value: any): boolean
	return typeof(value) == "number" and value == value and math.abs(value) < math.huge
end

-- A NaN in a position would poison the frame's whole batched move.
local function isPoint(value: any): boolean
	return typeof(value) == "Vector3" and value == value and value.Magnitude < math.huge
end

local function onThreat(
	id: number,
	shape: string,
	striking: boolean,
	phaseAt: number,
	impactAt: number,
	origin: Vector3,
	yaw: number,
	range: number,
	width: number,
	lockSeconds: number,
	strikeSeconds: number
): ()
	Tells.Feed(
		id,
		shape,
		striking,
		phaseAt,
		impactAt,
		origin,
		yaw,
		range,
		width,
		lockSeconds,
		strikeSeconds,
		frameServerNow,
		frameDelta
	)
end

-- Only an effect with every field its drawing needs, each of its type, is acted on.
local function applyFx(fx: any): ()
	if typeof(fx) ~= "table" then
		return
	end
	local kind = fx.kind
	if kind == "enemyShot" then
		if
			isNumber(fx.id)
			and isPoint(fx.from)
			and isPoint(fx.velocity)
			and isNumber(fx.radius)
			and isNumber(fx.firedAt)
			and isNumber(fx.seconds)
		then
			Shots.Fire(fx.id, fx.from, fx.velocity, fx.radius, fx.firedAt, fx.seconds)
		end
	elseif kind == "enemyShotEnd" then
		if isNumber(fx.id) and isPoint(fx.at) then
			Shots.End(fx.id, fx.at, fx.hit == true)
		end
	elseif kind == "area" then
		if
			isNumber(fx.id)
			and isPoint(fx.center)
			and isNumber(fx.radius)
			and isNumber(fx.startsAt)
			and isNumber(fx.endsAt)
		then
			Areas.Open(
				fx.id,
				fx.center,
				fx.radius,
				fx.startsAt,
				fx.endsAt,
				if isPoint(fx.from) then fx.from else nil
			)
		end
	end
end

-- CombatFx carries a batch (an array of effects); a lone effect table is accepted too. A batch
-- is taken strictly in its own order: a shot's end may ride in the batch that fired it, after
-- it.
local function onCombatFx(payload: any): ()
	if typeof(payload) ~= "table" or not Pool.IsReady() then
		return
	end
	if payload.kind ~= nil then
		applyFx(payload)
		return
	end
	for index = 1, #payload do
		applyFx(payload[index])
	end
end

local function step(deltaTime: number): ()
	if not Pool.IsReady() then
		return
	end
	frameServerNow = Workspace:GetServerTimeNow()
	frameDelta = deltaTime
	CrowdRenderer.ForEachThreat(onThreat)
	Tells.Sweep()
	Shots.Step(frameServerNow, os.clock())
	Areas.Step(frameServerNow)
	Pool.Flush()
end

function ThreatFx.Init(): ()
	-- Remotes are replicated instances: everything happens in Start.
end

function ThreatFx.Start(): ()
	if started or not CameraController.IsRange() then
		return
	end
	started = true
	Pool.Start()
	table.insert(connections, RunService.RenderStepped:Connect(step))
	task.spawn(function()
		local remotes = ReplicatedStorage:WaitForChild("Remotes")
		local combatFx =
			remotes:WaitForChild("CombatFx", Theme.COMBAT_REMOTE_WAIT_SECONDS) :: RemoteEvent?
		if not started then
			return -- destroyed while waiting
		end
		if combatFx == nil then
			warn("[ThreatFx] CombatFx missing — enemy shots and circles will not be drawn")
			return
		end
		table.insert(connections, combatFx.OnClientEvent:Connect(onCombatFx))
	end)
end

-- The local player loaded or reset a dummy set: the server drops the crowd's circles without a
-- word and ends each shot where it is. Both go here at once, ahead of those ends (which then
-- find no shot), so the screen is clean the moment the command is sent. The snapshot-driven
-- tells go by themselves with their bodies.
function ThreatFx.Clear(): ()
	if not Pool.IsReady() then
		return
	end
	Shots.Clear()
	Areas.Clear()
end

function ThreatFx.Destroy(): ()
	started = false
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	if Pool.IsReady() then
		Shots.Clear()
		Areas.Clear()
		Tells.Clear()
	end
	Pool.Destroy()
end

return ThreatFx
