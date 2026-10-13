--!strict
-- The Proving Grounds bench (docs/INTERFACES.md "P1 contracts", docs/COMBAT_DESIGN.md §8): the
-- proving arena, dummy sets and their respawns, live tuning, the range commands and the
-- range-only readout fields (clear time, alive, server frame, damage taken, downs, god).
--
-- P5 (INTERFACES "P5 contracts" → "Wave 1", ruling 6): everything a mission also needs moved to
-- WeaponService: the per-player loadout and variants, attacks, bow draws, projectiles, dash
-- i-frames, the slam, aim checks, the AbilityService hooks, TuneState and the attack readouts.
-- This file wraps WeaponService.AddPlayer / RemovePlayer, places the body at a range spawn, adds
-- its fields to every RangeStats through WeaponService's stats provider and starts its clear
-- clock on WeaponService.OnDamageDealt. In the range every number is the P4 one: WeaponService
-- scales nothing here (ruling 8) and no act gate is set (ruling 21).
--
-- P4: groups whose behaviour is `fight` attack; a fight slot's respawn is held while a player
-- stands on it.
--
-- Studio only and opt-in: Main calls Configure(true) when CombatMode.Get() is "range".
-- Otherwise every entry point here returns at once, so missions never touch this file. Nothing
-- in the Heartbeat step yields.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Tuning = require(sharedFolder:WaitForChild("Tuning"))

local ArenaService = require(script.Parent:WaitForChild("ArenaService"))
local CrowdService = require(script.Parent:WaitForChild("CrowdService"))
local VitalsService = require(script.Parent:WaitForChild("VitalsService"))
local WeaponService = require(script.Parent:WaitForChild("WeaponService"))

-- Lead ruling: a group of up to this many is one row along x; larger groups are a square grid.
local ROW_MAX_COUNT = 10
-- A slot the crowd refuses this many times in a row (crowd.maxAlive lowered mid-set) is dropped
-- from the set instead of being retried forever.
local MAX_SPAWN_ATTEMPTS = 3
-- The lost-dummy sweep runs with the 2 Hz readouts, as it did beside them in P4.
local SWEEP_INTERVAL_SECONDS = 0.5

type Slot = {
	kind: string,
	behaviour: string,
	position: Vector3,
	respawnSeconds: number,
	cleared: boolean,
	-- Consecutive refusals by CrowdService.Spawn.
	refusals: number,
}
type Respawn = { at: number, slot: Slot }
type Member = { connections: { RBXScriptConnection } }

local isStudio = RunService:IsStudio()
local active = false
local started = false
local members: { [Player]: Member } = {}
local slotById: { [number]: Slot } = {}
local setSlots: { Slot } = {}
local respawns: { Respawn } = {}
local currentSet = ""
-- os.clock() of the first damage since the set loaded; 0 = nobody has hit it yet.
local clearStartedAt = 0
local clearSeconds: number? = nil
local sweepAccumulator = 0
-- The floor's half-size (X, Z) from the arena build, so dummies stay on it.
local floorHalfSize = Vector3.zero

local RangeService = {}

local function kindDef(config: Types.ProvingGroundsConfig, kind: string): Types.CrowdKindDef?
	return config.crowd.kinds[kind]
end

-- The root of a living character, nil otherwise.
local function livingRoot(player: Player): BasePart?
	local character = player.Character
	if character == nil or character.Parent == nil then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if root == nil or not root:IsA("BasePart") or humanoid == nil or humanoid.Health <= 0 then
		return nil
	end
	return root
end

-- Dummy sets ---------------------------------------------------------------------------------

local function spawnSlot(slot: Slot): ()
	local id = CrowdService.Spawn(slot.kind, slot.position, slot.behaviour, slot.position)
	if id ~= 0 then
		slot.refusals = 0
		slotById[id] = slot
		return
	end
	-- Refused (crowd.maxAlive reached): a few retries after the group's respawn delay, then the
	-- slot leaves the set so the clear clock and the respawn queue never wait on it.
	slot.refusals += 1
	if slot.refusals >= MAX_SPAWN_ATTEMPTS then
		local index = table.find(setSlots, slot)
		if index ~= nil then
			table.remove(setSlots, index)
		end
		warn(
			`[RangeService] dropped a {slot.kind} dummy: the crowd refused it {slot.refusals} times`
		)
		return
	end
	table.insert(respawns, { at = os.clock() + math.max(slot.respawnSeconds, 1), slot = slot })
end

-- `at` is an absolute arena point (lead ruling). A small group is one row along x; a larger one
-- a packed square grid; both centred on `at` and clamped inside the floor.
local function groupPositions(
	group: Types.DummyGroupDef,
	count: number,
	radius: number
): { Vector3 }
	local positions: { Vector3 } = {}
	local limitX = math.max(0, floorHalfSize.X - radius)
	local limitZ = math.max(0, floorHalfSize.Z - radius)
	local centerX = group.at[1] or 0
	local centerZ = group.at[2] or 0
	local columns = if count <= ROW_MAX_COUNT then count else math.ceil(math.sqrt(count))
	local rows = math.ceil(count / math.max(columns, 1))
	for index = 0, count - 1 do
		local column = index % columns
		local row = index // columns
		local x = centerX + (column - (columns - 1) / 2) * group.spacing
		local z = centerZ + (row - (rows - 1) / 2) * group.spacing
		table.insert(
			positions,
			Vector3.new(math.clamp(x, -limitX, limitX), 0, math.clamp(z, -limitZ, limitZ))
		)
	end
	return positions
end

-- The first death of every slot since the set loaded ends the clear clock.
local function markCleared(slot: Slot): ()
	if slot.cleared then
		return
	end
	slot.cleared = true
	if clearSeconds ~= nil or clearStartedAt == 0 then
		return
	end
	for _, other in setSlots do
		if not other.cleared then
			return
		end
	end
	clearSeconds = os.clock() - clearStartedAt
end

local function slotGone(id: number): ()
	local slot = slotById[id]
	if slot == nil then
		return
	end
	slotById[id] = nil
	markCleared(slot)
	table.insert(respawns, { at = os.clock() + slot.respawnSeconds, slot = slot })
end

-- `countOverride` replaces the first group's count (the stress command's crowd.stressCount).
local function loadSet(name: string, countOverride: number?): ()
	local config = Tuning.Get()
	local groups = config.dummySets[name]
	if groups == nil then
		warn(`[RangeService] no dummy set "{name}"`)
		return
	end
	CrowdService.Clear()
	slotById = {}
	setSlots = {}
	respawns = {}
	WeaponService.AbandonProjectiles()
	VitalsService.OnSetLoaded()
	currentSet = name
	clearStartedAt = 0
	clearSeconds = nil
	-- Never ask for more dummies than the crowd will hold; later groups get what is left.
	local budget = math.max(0, math.floor(config.crowd.maxAlive))
	for groupIndex, group in groups do
		local def = kindDef(config, group.kind)
		if def == nil then
			warn(`[RangeService] set {name}: unknown crowd kind "{group.kind}"`)
			continue
		end
		local count = if groupIndex == 1 and countOverride ~= nil
			then countOverride
			else group.count
		count = math.clamp(math.floor(count), 0, budget)
		budget -= count
		for _, position in groupPositions(group, count, def.radius) do
			local slot: Slot = {
				kind = group.kind,
				behaviour = group.behaviour,
				position = position,
				respawnSeconds = group.respawnSeconds,
				cleared = false,
				refusals = 0,
			}
			table.insert(setSlots, slot)
			spawnSlot(slot)
		end
	end
	print(`[RangeService] loaded set "{name}" ({#setSlots} dummies)`)
end

-- Kills arrive through OnKilled; this catches any enemy CrowdService dropped another way.
local function sweepSlots(): ()
	for id in table.clone(slotById) do
		if CrowdService.Get(id) == nil then
			slotGone(id)
		end
	end
end

-- P4: a fight slot does not respawn while a player stands within crowd.threat.spawnClear of
-- its home (on the flat), so an enemy never appears on top of someone.
local function playerNear(home: Vector3, clear: number): boolean
	for player in members do
		local root = livingRoot(player)
		if root ~= nil then
			local offset = root.Position - home
			if offset.X * offset.X + offset.Z * offset.Z <= clear * clear then
				return true
			end
		end
	end
	return false
end

local function tickRespawns(config: Types.ProvingGroundsConfig, now: number): ()
	if #respawns == 0 then
		return
	end
	local due: { Slot } = {}
	local waiting: { Respawn } = {}
	local clear = math.max(config.crowd.threat.spawnClear, 0)
	for _, entry in respawns do
		local slot = entry.slot
		if
			now >= entry.at and not (slot.behaviour == "fight" and playerNear(slot.position, clear))
		then
			table.insert(due, slot)
		else
			table.insert(waiting, entry)
		end
	end
	respawns = waiting
	for _, slot in due do
		spawnSlot(slot)
	end
end

local function step(deltaTime: number): ()
	tickRespawns(Tuning.Get(), os.clock())
	sweepAccumulator += deltaTime
	if sweepAccumulator >= SWEEP_INTERVAL_SECONDS then
		sweepAccumulator = 0
		sweepSlots()
	end
end

-- The bench's readout fields on every RangeStats WeaponService assembles.
local function provideStats(player: Player, stats: Types.RangeStats): ()
	local damageTaken, downs, god = VitalsService.Readout(player)
	stats.clearSeconds = clearSeconds
	stats.alive = CrowdService.AliveCount()
	stats.serverFrameMs = CrowdService.StepMs()
	stats.damageTaken = damageTaken
	stats.downs = downs
	stats.god = god
end

-- Players ------------------------------------------------------------------------------------

-- Placed at a spawn, then handed to WeaponService (air state, and the body is VitalsService's).
local function prepareCharacter(player: Player, character: Model): ()
	local spawnLocation, spawnCFrame = ArenaService.ProvingSpawn()
	if spawnLocation ~= nil then
		player.RespawnLocation = spawnLocation
	end
	character:PivotTo(spawnCFrame)
	WeaponService.PrepareCharacter(player, character)
end

-- Must be called before Init. `proving` is Main's boot decision (CombatMode.Get() == "range");
-- the range also needs Studio and Config/ProvingGrounds, and stays off without either.
function RangeService.Configure(proving: boolean): ()
	if not proving then
		active = false
		return
	end
	if not isStudio then
		return
	end
	if not Tuning.IsAvailable() then
		warn(
			"[RangeService] DebugProving is set but Config/ProvingGrounds is missing; booting missions"
		)
		return
	end
	active = true
end

function RangeService.IsActive(): boolean
	return active
end

-- A loaded player enters the range: WeaponService gives the default weapons and variants and
-- sends the tuning; here the body is placed at a spawn, now and on every respawn. Idempotent.
function RangeService.AddPlayer(player: Player): ()
	if not active or members[player] ~= nil or player.Parent == nil then
		return
	end
	WeaponService.AddPlayer(player)
	local member: Member = { connections = {} }
	members[player] = member
	table.insert(
		member.connections,
		player.CharacterAdded:Connect(function(character: Model)
			prepareCharacter(player, character)
		end)
	)
	local character = player.Character
	if character ~= nil then
		prepareCharacter(player, character)
	end
end

function RangeService.RemovePlayer(player: Player): ()
	local member = members[player]
	if member == nil then
		return
	end
	for _, connection in member.connections do
		connection:Disconnect()
	end
	members[player] = nil
	WeaponService.RemovePlayer(player)
end

-- Studio only. The path must name a scalar in the base config and keep its type; an override
-- equal to the base is dropped rather than stored. WeaponService resends TuneState on the
-- change.
function RangeService.OnTune(_player: Player, path: string, value: Types.TuneValue): ()
	if not active or not isStudio or not Tuning.Validate(path, value) then
		return
	end
	local updated = Tuning.GetOverrides()
	if Tuning.BaseValue(path) == value then
		updated[path] = nil
	else
		updated[path] = value
	end
	Tuning.SetOverrides(updated)
end

function RangeService.OnCommand(player: Player, command: string, argument: string?): ()
	if not active or not isStudio or members[player] == nil then
		return
	end
	local config = Tuning.Get()
	if command == "set" and argument ~= nil then
		loadSet(argument)
	elseif command == "reset" then
		loadSet(if currentSet ~= "" then currentSet else config.defaultSet)
	elseif command == "stress" then
		-- The stress set at crowd.stressCount (its first group's count is replaced).
		loadSet("stress", config.crowd.stressCount)
	elseif command == "weapon" and argument ~= nil then
		-- `weapon <familyId>`: the family goes into its own slot.
		if not WeaponService.SetFamily(player, argument) then
			warn(`[RangeService] no weapon family "{argument}"`)
			return
		end
	elseif command == "variant" and argument ~= nil then
		-- `variant <familyId> <key>` arrives as one argument string.
		local family, key = string.match(argument, "^(%S+)%s+(%S+)$")
		if family == nil or key == nil or not WeaponService.SetVariant(player, family, key) then
			warn(`[RangeService] bad variant command "{argument}" (want: <family> <key>)`)
			return
		end
	elseif command == "export" then
		print(`[RangeService] ProvingGrounds.json with the current tuning:\n{Tuning.Export()}`)
	elseif command == "clearTune" then
		Tuning.SetOverrides({})
	elseif command == "god" then
		-- P4 ruling 14: a toggle; the readout below carries the new setting.
		VitalsService.ToggleGod(player)
	else
		warn(`[RangeService] unknown or incomplete range command "{command}"`)
		return
	end
	WeaponService.SendStats(player)
end

function RangeService.Init(): () end

-- Builds the range and loads the default set. Only when Configure(true) took effect; after
-- WeaponService.Start, which has already started VitalsService.
function RangeService.Start(): ()
	if not active or started then
		return
	end
	started = true
	local config = Tuning.Get()
	local center, halfSize = ArenaService.BuildProvingArena(config.arena)
	floorHalfSize = halfSize
	CrowdService.SetBounds(center, halfSize)
	CrowdService.OnKilled(function(id: number, _byUserId: number)
		slotGone(id)
	end)
	WeaponService.SetStatsProvider(provideStats)
	WeaponService.OnDamageDealt(function(_player: Player, _dealt: number)
		if clearStartedAt == 0 then
			clearStartedAt = os.clock()
		end
	end)
	RunService.Heartbeat:Connect(step)
	loadSet(config.defaultSet)
	print("[RangeService] Proving Grounds ready")
end

return RangeService
