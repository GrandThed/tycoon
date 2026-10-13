--!strict
-- Studio levers for the Expeditions place (docs/INTERFACES.md "C1 contracts" → "Debug levers").
-- Every lever is reachable two ways — a Workspace attribute polled at 1 Hz, and the
-- RequestDebug intent the client DebugPanel fires — and BOTH are dead outside
-- RunService:IsStudio(). A live server never reaches a single line of the apply table.
--
-- Two lever shapes:
-- * ACTIONS (wave, spawn, killAll, setGear, grantMaterials, grantValor) are consumed: the
--   attribute is reset the moment it is read, so one edit fires exactly once.
-- * STATES (godMode, bots) are read every tick and left alone, because "god mode is on" and
--   "there are two bots" are conditions, not events.
--
-- C2 adds `admitCheck` (remote only): the caller is judged by the SAME CheckAdmission a real
-- arrival runs, as a stranger arriving now, and gets the verdict as a toast; nobody is sent home.
--
-- P1: in the Proving Grounds every mission lever is inert. They would start waves inside the
-- range, or write the profile, which the range never does; the range has its own Studio
-- commands (RequestRangeCommand, RangeService).
--
-- P5 (docs/INTERFACES.md "P5 contracts", ruling 25): the levers point at the crowd. `wave`
-- starts that wave at once, `skip` ("next" | "boss") is the B and N keys, `spawn` raises a crowd
-- kind at the rim, `godMode` and `setGear` go through VitalsService, `killAll` kills the crowd
-- with its rewards. Debug bots are Humanoid rigs the crowd cannot target: until Wave 4 the
-- `bots` lever only warns.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Armory = require(sharedFolder:WaitForChild("Armory"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))

local servicesFolder = script.Parent.Parent:WaitForChild("Services")
local DataService = require(servicesFolder:WaitForChild("DataService"))
local RemoteService = require(servicesFolder:WaitForChild("RemoteService"))
local ArenaService = require(script.Parent:WaitForChild("ArenaService"))
local WaveService = require(script.Parent:WaitForChild("WaveService"))
local RangeService = require(script.Parent:WaitForChild("RangeService"))
local VitalsService = require(script.Parent:WaitForChild("VitalsService"))

local TICK_INTERVAL_SECONDS = 1

local isStudio = RunService:IsStudio()
local tickAccumulator = 0
local levelConnection: RBXScriptConnection? = nil
local warnedRange = false
local warnedBots = false
-- The godMode attribute is a state, applied when it changes, so the remote lever's own setting
-- for one player is not overwritten by the poll a second later.
local lastGodAttribute: boolean? = nil

local DebugService = {}

local function eachState(player: Player?, apply: (Player, Types.PlayerState) -> ()): ()
	if player ~= nil then
		local state = DataService.GetState(player)
		if state ~= nil then
			apply(player, state)
		end
		return
	end
	for _, other in Players:GetPlayers() do
		local state = DataService.GetState(other)
		if state ~= nil then
			apply(other, state)
		end
	end
end

local function grantMaterials(player: Player?, amount: number): ()
	local mission = ArenaService.GetMission()
	if mission == nil or amount <= 0 then
		return
	end
	eachState(player, function(target: Player, state: Types.PlayerState)
		local owned = state.combat.materials[mission.material] or 0
		state.combat.materials[mission.material] = owned + amount
		ArenaService.SendSnapshot(target)
	end)
end

local function grantValor(player: Player?, amount: number): ()
	if amount <= 0 then
		return
	end
	eachState(player, function(target: Player, state: Types.PlayerState)
		state.combat.valor += amount
		ArenaService.SendSnapshot(target)
	end)
end

-- "melee=3,ranged=2": a tier that does not exist is ignored rather than written, so a typo in
-- the attribute can never leave a profile holding a weapon the Armory has no definition for.
local function setGear(player: Player?, spec: string): ()
	local armoryConfig = Catalog.GetArmoryConfig()
	if armoryConfig == nil then
		return
	end
	local wanted: { [string]: number } = {}
	for slot, tierText in string.gmatch(spec, "(%a+)%s*=%s*(%d+)") do
		local tier = tonumber(tierText)
		if tier ~= nil and (slot == "melee" or slot == "ranged") then
			if Armory.TierDef(armoryConfig, slot, tier) ~= nil then
				wanted[slot] = tier
			else
				warn(`[DebugService] setGear: no {slot} tier {tier}`)
			end
		end
	end
	if next(wanted) == nil then
		return
	end
	eachState(player, function(target: Player, state: Types.PlayerState)
		if wanted.melee ~= nil then
			state.combat.gear.melee = wanted.melee
		end
		if wanted.ranged ~= nil then
			state.combat.gear.ranged = wanted.ranged
		end
		-- Weapons decide max HP: VitalsService, the bar's only writer, resizes it from the new
		-- gear (a proving mission keeps its baked gear, ruling 12).
		VitalsService.RefreshMaxHp(target)
		ArenaService.SendSnapshot(target)
	end)
end

local function setGodMode(player: Player?, enabled: boolean): ()
	if player ~= nil then
		VitalsService.SetGod(player, enabled)
		return
	end
	for _, member in ArenaService.GetMembers() do
		local target = member.player
		if target ~= nil then
			VitalsService.SetGod(target, enabled)
		end
	end
end

-- Ruling 24: the crowd targets Players only, so a bot would stand in the arena doing nothing.
local function refuseBots(): ()
	if not warnedBots then
		warnedBots = true
		warn("[DebugService] debug bots are not supported in crowd missions until Wave 4")
	end
end

-- Spelled out so the literal types survive: a singleton union returned across modules reaches
-- the caller as plain `string` under the old solver.
local function refusalReason(verdict: string): ("full" | "over" | "locked")?
	if verdict == "full" then
		return "full"
	elseif verdict == "over" then
		return "over"
	elseif verdict == "locked" then
		return "locked"
	end
	return nil
end

-- The verdict as the ActionResult the combat client toasts (slotId "admitCheck" marks it as the
-- lever's answer, not a real refusal), plus a line in Output for the playtest notes.
local function admitCheck(player: Player?): ()
	if player == nil then
		return
	end
	local verdict = ArenaService.CheckAdmission(player, { probe = true })
	print(`[DebugService] admitCheck for {player.Name}: {verdict}`)
	local result: Types.ActionResult = {
		action = "joinRun",
		slotId = "admitCheck",
		ok = verdict == "ok",
		reason = refusalReason(verdict),
	}
	RemoteService.FireClient(player, "ActionResult", result)
end

-- The lever table itself. `player` is nil for the attribute path (everyone) and the caller for
-- the remote path.
local function applyLever(player: Player?, lever: string, value: any): ()
	if RangeService.IsActive() then
		if not warnedRange then
			warnedRange = true
			warn(`[DebugService] mission levers are off in the Proving Grounds (ignored "{lever}")`)
		end
		return
	end
	if lever == "wave" and typeof(value) == "number" then
		WaveService.ForceWave(value)
	elseif lever == "skip" and (value == "next" or value == "boss") then
		WaveService.Skip(value)
	elseif lever == "spawn" and typeof(value) == "string" and value ~= "" then
		WaveService.SpawnOne(value)
	elseif lever == "godMode" then
		setGodMode(player, value == true)
	elseif lever == "killAll" then
		WaveService.KillAll()
	elseif lever == "setGear" and typeof(value) == "string" then
		setGear(player, value)
	elseif lever == "bots" and typeof(value) == "number" then
		refuseBots()
	elseif lever == "grantMaterials" and typeof(value) == "number" then
		grantMaterials(player, value)
	elseif lever == "grantValor" and typeof(value) == "number" then
		grantValor(player, value)
	elseif lever == "admitCheck" then
		admitCheck(player)
	else
		warn(`[DebugService] unknown or mistyped lever "{lever}"`)
	end
end

-- The RequestDebug intent. Validated for shape by CombatRemotes; refused entirely outside
-- Studio, so a published server cannot be talked into god mode.
function DebugService.OnRequest(player: Player, lever: string, value: any): ()
	if not isStudio then
		return
	end
	applyLever(player, lever, value)
end

local function consumeNumber(attribute: string): number?
	local value = workspace:GetAttribute(attribute)
	-- NaN/inf are refused too: Studio with API access writes a real profile, and a corrupted
	-- materials or Valor field would survive the session.
	if typeof(value) ~= "number" or value <= 0 or value ~= value or value == math.huge then
		return nil
	end
	workspace:SetAttribute(attribute, 0)
	return value
end

local function consumeString(attribute: string): string?
	local value = workspace:GetAttribute(attribute)
	if typeof(value) ~= "string" or value == "" then
		return nil
	end
	workspace:SetAttribute(attribute, "")
	return value
end

local function pollAttributes(debugConfig: Types.CombatDebugConfig): ()
	local waveNumber = consumeNumber(debugConfig.waveAttribute)
	if waveNumber ~= nil then
		applyLever(nil, "wave", waveNumber)
	end
	local spawnKey = consumeString(debugConfig.spawnAttribute)
	if spawnKey ~= nil then
		applyLever(nil, "spawn", spawnKey)
	end
	if consumeNumber(debugConfig.killAllAttribute) ~= nil then
		applyLever(nil, "killAll", true)
	end
	local gear = consumeString(debugConfig.setGearAttribute)
	if gear ~= nil then
		applyLever(nil, "setGear", gear)
	end
	local materials = consumeNumber(debugConfig.grantMaterialsAttribute)
	if materials ~= nil then
		applyLever(nil, "grantMaterials", materials)
	end
	local valor = consumeNumber(debugConfig.grantValorAttribute)
	if valor ~= nil then
		applyLever(nil, "grantValor", valor)
	end

	-- States, read but never reset. God mode is applied when the attribute changes (and to
	-- whoever is in the run at that moment); a new arrival starts mortal.
	local god = workspace:GetAttribute(debugConfig.godModeAttribute) == true
	if god ~= lastGodAttribute then
		lastGodAttribute = god
		setGodMode(nil, god)
	end
	local bots = workspace:GetAttribute(debugConfig.botsAttribute)
	if typeof(bots) == "number" and bots > 0 then
		refuseBots()
	end
end

function DebugService.Init(): () end

function DebugService.Start(): ()
	if not isStudio or levelConnection ~= nil then
		return
	end
	local combatConfig = Catalog.GetCombatConfig()
	if combatConfig == nil then
		return
	end
	local debugConfig = combatConfig.debug
	levelConnection = RunService.Heartbeat:Connect(function(delta: number)
		-- The range has no run, no bots and no waves; its attributes stay untouched too.
		if RangeService.IsActive() then
			return
		end
		tickAccumulator += delta
		if tickAccumulator < TICK_INTERVAL_SECONDS then
			return
		end
		tickAccumulator = 0
		pollAttributes(debugConfig)
	end)
end

return DebugService
