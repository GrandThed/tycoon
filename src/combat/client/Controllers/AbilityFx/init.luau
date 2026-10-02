--!strict
-- Ability visuals for the Proving Grounds (P3, docs/INTERFACES.md "P3 contracts": ruling 6, the
-- ability table and CombatFxCast). There is no sound, so a cast must read from its visuals alone,
-- for the caster and for everyone watching (COMBAT_DESIGN pillar 2: what you see is what you hit).
--
-- Division of labour. Damage never comes from here: every ability hit is a CombatFxStrike that
-- FeedbackController draws (exact shape, numbers, reactions), and Feedback also flies every ability
-- projectile (volley arrows, the cluster shell) and draws chain lightning from `links`. It skips
-- its generic flash on `tick` strikes because this module draws the lasting area. So this module
-- adds only what lasts, or what one strike cannot show:
--   * the whole-duration area of a lasting ability at its exact server size, no pad (Whirlwind
--     ring = range, zone circles = radius, the Overload Sweep beam and sector = range);
--   * the build-up before a delayed hit (the Earthquake front, the Leap Smash landing marker, the
--     Overcharged Shot charge, the cluster bomblets blinking over their blast radius);
--   * caster flourishes (bow flash, muzzle blasts, Mag Dump heat, dash afterimages, trails).
--
-- Timing. A cast and its strikes reach this client with the same lag, so visuals run on the
-- receipt clock and land together with the damage the player sees. Only a cast later than
-- CATCH_UP_GRACE past its server `startsAt` (a stall, a join mid-cast) skips ahead by the excess, so
-- a zone never outlives the server's. The ability def is frozen at receipt: a slider moved mid-cast
-- changes the next cast, as it does on the server. Tick strikes pulse their zone, so the damage
-- rhythm shows too.
--
-- Budget. Everything is pooled (parts, wedges, beams, emitters, trails, lights) under one Workspace
-- folder, and per-frame moves go through one Workspace:BulkMoveTo. The crowd is never iterated.
-- Theme.lowEndDevice halves every particle rate and burst and drops the extras (fills, streaks,
-- debris, lights, reticle notches, some blades and afterimages). The areas always draw, because
-- they are information. Theme.reducedMotion is deliberately unused: it is true on every touch
-- device (living-city ruling), and phones are where these reads matter most.
--
-- Layout. This is a folder module because a module's top level is one function, and Studio's
-- debug compile gives every top-level local a register (limit 200): `Shared` holds the types,
-- look constants and maths, `Pool` everything that owns instances, and each ability is its own
-- child with its own constants. This file is only the controller: the CombatFx listener, the
-- list of live visuals and their per-frame step.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Tuning = require(sharedFolder:WaitForChild("Tuning"))

local uiFolder = script.Parent.Parent:WaitForChild("UI")
local Theme = require(uiFolder:WaitForChild("Theme"))
local CameraController = require(script.Parent:WaitForChild("CameraController"))
local Shared = require(script:WaitForChild("Shared"))
local Pool = require(script:WaitForChild("Pool"))

type Def = Shared.Def
type Cast = Shared.Cast
type AbilityStrike = Shared.AbilityStrike
type Kit = Shared.Kit
type Step = Shared.Step
type StrikeHook = Shared.StrikeHook
type Builder = Shared.Builder

local newKit = Pool.newKit
local releaseKit = Pool.releaseKit
local flushMoves = Pool.flushMoves
local isReady = Pool.isReady

type Visual = {
	userId: number,
	ability: string,
	kit: Kit,
	clock0: number,
	step: Step,
	onStrike: StrikeHook?,
}

-- Visuals alive at once. Past this the oldest ends, which only happens with cooldowns off.
local MAX_VISUALS = 24
-- Seconds of one-way lag plus batching that still count as on time (strikes lag the same).
local CATCH_UP_GRACE = 0.2

local BUILDERS: { [string]: Builder } = {
	whirlwind = require(script:WaitForChild("Whirlwind")),
	earthquake = require(script:WaitForChild("Earthquake")),
	bladeStorm = require(script:WaitForChild("BladeStorm")),
	leapSmash = require(script:WaitForChild("LeapSmash")),
	impaleDash = require(script:WaitForChild("ImpaleDash")),
	arrowRain = require(script:WaitForChild("ArrowRain")),
	volley = require(script:WaitForChild("Volley")),
	slugBurst = require(script:WaitForChild("SlugBurst")),
	overchargedShot = require(script:WaitForChild("OverchargedShot")),
	magDump = require(script:WaitForChild("MagDump")),
	clusterShell = require(script:WaitForChild("ClusterShell")),
	overloadSweep = require(script:WaitForChild("OverloadSweep")),
	stormCoil = require(script:WaitForChild("StormCoil")),
}

local AbilityFx = {}

local connections: { RBXScriptConnection } = {}
local visuals: { Visual } = {}
local started = false
local destroyed = false

local function retire(visual: Visual): ()
	local index = table.find(visuals, visual)
	if index == nil then
		return
	end
	table.remove(visuals, index)
	releaseKit(visual.kit)
end

-- Ends at once every visual of `userId` (a cancel names one ability; a leave ends them all).
local function stopWhere(userId: number, ability: string?): ()
	for index = #visuals, 1, -1 do
		local visual = visuals[index]
		if visual.userId == userId and (ability == nil or visual.ability == ability) then
			table.remove(visuals, index)
			releaseKit(visual.kit)
		end
	end
end

-- The family's ability as tuned right now, copied so the visual keeps these numbers.
local function defFor(weapon: string, ability: string): Def?
	local family: Types.RangeWeaponDef? = Tuning.Get().weapons[weapon]
	local def = if family ~= nil then family.ability else nil
	if def == nil or def.id ~= ability then
		return nil
	end
	return table.clone(def)
end

local function parseCast(fx: { [string]: any }): Cast?
	if
		typeof(fx.userId) ~= "number"
		or typeof(fx.weapon) ~= "string"
		or typeof(fx.ability) ~= "string"
		or typeof(fx.origin) ~= "Vector3"
		or typeof(fx.direction) ~= "Vector3"
		or typeof(fx.startsAt) ~= "number"
		or typeof(fx.seq) ~= "number"
	then
		return nil
	end
	return {
		userId = fx.userId,
		weapon = fx.weapon,
		ability = fx.ability,
		origin = fx.origin,
		direction = fx.direction,
		target = if typeof(fx.target) == "Vector3" then fx.target else nil,
		startsAt = fx.startsAt,
		seq = fx.seq,
	}
end

local function parseStrike(fx: { [string]: any }): AbilityStrike?
	if
		typeof(fx.ability) ~= "string"
		or typeof(fx.userId) ~= "number"
		or typeof(fx.shape) ~= "string"
		or typeof(fx.origin) ~= "Vector3"
		or typeof(fx.direction) ~= "Vector3"
		or typeof(fx.size) ~= "number"
	then
		return nil
	end
	return {
		userId = fx.userId,
		ability = fx.ability,
		shape = fx.shape,
		origin = fx.origin,
		direction = fx.direction,
		size = fx.size,
		endPoint = if typeof(fx.endPoint) == "Vector3" then fx.endPoint else nil,
		tick = fx.tick == true,
	}
end

local function onCast(fx: { [string]: any }): ()
	if fx.cancel == true then
		if typeof(fx.userId) == "number" and typeof(fx.ability) == "string" then
			stopWhere(fx.userId, fx.ability)
		end
		return
	end
	local cast = parseCast(fx)
	if cast == nil or not isReady() then
		return
	end
	local builder = BUILDERS[cast.ability]
	local def = defFor(cast.weapon, cast.ability)
	if builder == nil or def == nil then
		return
	end
	local kit = newKit()
	local ok, step, hook = pcall(builder, cast, def, kit)
	if not ok or step == nil then
		if not ok then
			warn(`[AbilityFx] {cast.ability} failed to build: {step}`)
		end
		releaseKit(kit)
		return
	end
	if #visuals >= MAX_VISUALS then
		retire(visuals[1])
	end
	local late = math.max(Workspace:GetServerTimeNow() - cast.startsAt - CATCH_UP_GRACE, 0)
	table.insert(visuals, {
		userId = cast.userId,
		ability = cast.ability,
		kit = kit,
		clock0 = os.clock() - late,
		step = step,
		onStrike = hook,
	})
end

-- Oldest visual first, so a zone that was cast earlier claims its own ticks and a cluster
-- shell's splash goes to the cast that is still waiting for one.
local function onStrike(strike: AbilityStrike): ()
	for _, visual in visuals do
		local hook = visual.onStrike
		if hook ~= nil and visual.userId == strike.userId and visual.ability == strike.ability then
			local ok, taken = pcall(hook, strike)
			if ok and taken then
				return
			end
		end
	end
end

local function applyFx(fx: any): ()
	if typeof(fx) ~= "table" then
		return
	end
	if fx.kind == "cast" then
		onCast(fx :: { [string]: any })
	elseif fx.kind == "strike" and fx.ability ~= nil then
		local strike = parseStrike(fx :: { [string]: any })
		if strike ~= nil then
			onStrike(strike)
		end
	end
end

-- CombatFx carries a batch (an array of fx); a lone fx table is accepted too.
local function onCombatFx(payload: any): ()
	if typeof(payload) ~= "table" then
		return
	end
	if payload.kind ~= nil then
		applyFx(payload)
		return
	end
	for _, fx in payload :: { any } do
		applyFx(fx)
	end
end

-- Nothing here yields: every step is plain maths and property writes.
local function onRenderStep(dt: number): ()
	local now = os.clock()
	local finished: { Visual } = {}
	for _, visual in visuals do
		local ok, alive = pcall(visual.step, now - visual.clock0, dt)
		if not ok then
			warn(`[AbilityFx] {visual.ability} visual failed: {alive}`)
			table.insert(finished, visual)
		elseif not alive then
			table.insert(finished, visual)
		end
	end
	flushMoves()
	for _, visual in finished do
		retire(visual)
	end
end

function AbilityFx.Init(): ()
	-- Remotes are replicated instances: everything happens in Start.
end

-- Inert outside the Proving Grounds, like every range controller (CameraController.IsRange).
function AbilityFx.Start(): ()
	if started or destroyed or not CameraController.IsRange() then
		return
	end
	started = true
	Pool.start()
	table.insert(connections, RunService.RenderStepped:Connect(onRenderStep))
	table.insert(
		connections,
		Players.PlayerRemoving:Connect(function(player: Player)
			stopWhere(player.UserId, nil)
		end)
	)
	task.spawn(function()
		local remotes = ReplicatedStorage:WaitForChild("Remotes")
		local combatFx =
			remotes:WaitForChild("CombatFx", Theme.COMBAT_REMOTE_WAIT_SECONDS) :: RemoteEvent?
		if combatFx == nil then
			warn("[AbilityFx] CombatFx missing — ability visuals are disabled")
			return
		end
		if destroyed then
			return
		end
		table.insert(connections, combatFx.OnClientEvent:Connect(onCombatFx))
	end)
end

function AbilityFx.Destroy(): ()
	destroyed = true
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	table.clear(visuals)
	Pool.destroy()
end

return AbilityFx
