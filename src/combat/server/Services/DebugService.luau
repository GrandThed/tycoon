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
local EnemyService = require(script.Parent:WaitForChild("EnemyService"))
local CombatService = require(script.Parent:WaitForChild("CombatService"))
local WaveService = require(script.Parent:WaitForChild("WaveService"))

local TICK_INTERVAL_SECONDS = 1
local MAX_BOTS = 8
local BOT_TICK_SECONDS = 0.5
local BOT_REACH_STUDS = 8

local isStudio = RunService:IsStudio()
local tickAccumulator = 0
local botAccumulator = 0
local botCount = 0
local levelConnection: RBXScriptConnection? = nil

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
		-- Weapons decide max HP, so the Humanoid has to be resized from the new loadout.
		local character = target.Character
		if character ~= nil then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid ~= nil then
				local maxHp = Armory.MaxHp(armoryConfig, state.combat.gear, state.combat.ascension)
				humanoid.MaxHealth = maxHp
				humanoid.Health = maxHp
			end
		end
		ArenaService.SendSnapshot(target)
	end)
end

local function setGodMode(player: Player?, enabled: boolean): ()
	if player ~= nil then
		local member = ArenaService.GetMemberFor(player)
		if member ~= nil then
			member.godMode = enabled
		end
		return
	end
	for _, member in ArenaService.GetMembers() do
		member.godMode = enabled
	end
end

-- Bots exist so party scaling, aggro and the contribution split can be seen from one client.
function DebugService.SetBots(count: number): ()
	local wanted = math.clamp(math.floor(count), 0, MAX_BOTS)
	while botCount < wanted do
		botCount += 1
		ArenaService.AddBot(botCount)
	end
	while botCount > wanted do
		ArenaService.RemoveBot(botCount)
		botCount -= 1
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
	if lever == "wave" and typeof(value) == "number" then
		WaveService.ForceWave(value)
	elseif lever == "spawn" and typeof(value) == "string" and value ~= "" then
		WaveService.SpawnOne(value)
	elseif lever == "godMode" then
		setGodMode(player, value == true)
	elseif lever == "killAll" then
		WaveService.KillAll()
	elseif lever == "setGear" and typeof(value) == "string" then
		setGear(player, value)
	elseif lever == "bots" and typeof(value) == "number" then
		DebugService.SetBots(value)
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

	-- States, read but never reset.
	setGodMode(nil, workspace:GetAttribute(debugConfig.godModeAttribute) == true)
	local bots = workspace:GetAttribute(debugConfig.botsAttribute)
	if typeof(bots) == "number" and math.floor(bots) ~= botCount then
		DebugService.SetBots(bots)
	end
end

-- Bots walk at the nearest enemy and chip at it through CombatService, so their damage lands in
-- the same tally the contribution split reads.
local function tickBots(debugConfig: Types.CombatDebugConfig, delta: number): ()
	if botCount == 0 then
		return
	end
	botAccumulator += delta
	if botAccumulator < BOT_TICK_SECONDS then
		return
	end
	local elapsed = botAccumulator
	botAccumulator = 0
	local damage = debugConfig.botDamagePerSecond * elapsed
	for _, member in ArenaService.GetMembers() do
		-- A bot parked on the pad for the wave boundary sits it out like a waiting joiner.
		if not member.bot or not ArenaService.IsFighting(member) then
			continue
		end
		local character = member.character
		local humanoid = member.humanoid
		local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
		if humanoid == nil or root == nil or not root:IsA("BasePart") then
			continue
		end
		local nearest: EnemyService.Enemy? = nil
		local nearestDistance = math.huge
		for _, enemy in EnemyService.GetEnemies() do
			if enemy.dead then
				continue
			end
			local distance = (enemy.root.Position - root.Position).Magnitude
			if distance < nearestDistance then
				nearestDistance = distance
				nearest = enemy
			end
		end
		if nearest == nil then
			continue
		end
		humanoid:MoveTo(nearest.root.Position)
		if nearestDistance <= BOT_REACH_STUDS then
			CombatService.DealDamage(nearest, damage, member.userId, false)
		end
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
		tickBots(debugConfig, delta)
		tickAccumulator += delta
		if tickAccumulator < TICK_INTERVAL_SECONDS then
			return
		end
		tickAccumulator = 0
		pollAttributes(debugConfig)
	end)
end

return DebugService
