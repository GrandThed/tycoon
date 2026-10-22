--!strict
-- Studio levers for the Expeditions place (docs/INTERFACES.md "C1 contracts" → "Debug levers").
-- Every lever is reachable two ways — a Workspace attribute polled at 1 Hz, and the
-- RequestDebug intent the client DebugPanel fires — and BOTH are dead outside
-- RunService:IsStudio(). A live server never reaches a single line of the apply table.
--
-- Two lever shapes:
-- * ACTIONS (wave, spawn, killAll, setGear, grantMaterials, grantValor) are consumed: the
--   attribute is reset the moment it is read, so one edit fires exactly once.
-- * STATES (godMode) are read every tick and left alone, because "god mode is on" is a
--   condition, not an event.
--
-- C2 adds `admitCheck` (remote only): the caller is judged by the SAME CheckAdmission a real
-- arrival runs, as a stranger arriving now, and gets the verdict as a toast; nobody is sent home.
--
-- P1: in the Proving Grounds every mission lever is inert. They would start waves inside the
-- range, or write the profile, which the range never does; the range has its own Studio
-- commands (RequestRangeCommand, RangeService).
--
-- P5 (docs/INTERFACES.md "P5 contracts", ruling 25): the levers point at the crowd. `wave`
-- forces a wave of the live camp, `spawn` raises a crowd kind at the camp's next spawn point,
-- `godMode` and `setGear` go through VitalsService, `killAll` kills the crowd with its rewards.
-- L4 W1b (L4B-4) deleted the debug bots and their lever: Humanoid rigs the crowd never targeted.
--
-- L1 (docs/INTERFACES.md "L1 contracts", rulings 33 and 34): `skip` takes "stage" (the N key:
-- finish this part of the level) and "boss" (the B key); `gear` "next" (the G key) steps the
-- caller through Combat.json debug.gearPresets as a Studio-only session override, which is also
-- what `setGear` sets in a proving build (there the baked gear wins over the profile, so writing
-- the profile changed nothing where Ben plays).
--
-- L2 W1 (docs/prompts/l2-w1-contract.md, L2-19): `grantAbility` / `removeAbility` (value an
-- ability id) and `resetSecrets` go through UnlockService; the Studio mock store starts every
-- session at a fresh profile, so these are how a bought Double Jump or a found chest is seen
-- without clearing a level twice. The remote path acts on the caller, the attribute path on
-- everyone admitted. `resetSecrets` keeps the families found.
--
-- L2 W2 (docs/prompts/l2-w2-contract.md, L2-38): `grantFamily` / `removeFamily` (value a weapon
-- family id) write or clear the profile's families through UnlockService (a removed family that
-- is held goes back to its slot's starter; starters cannot be removed); `resetSecrets` also
-- forgets the found shortcuts, which open again from the next run.
--
-- L3 W1 (docs/prompts/l3-w1-contract.md, L3-28): the gear levers move to the ladder of 20 and
-- `setGear` is the session override in every Studio build (no profile has a slot gear any more);
-- `grantMaterials` in the lobby pays every built band's material; `setTier` ("<family>=<tier>"),
-- `grantStar` (a level id or "*") and `resetArmory` reach a T4, its Hard star and a fresh Armory
-- without a Hard clear in every Studio session (the mock profile starts fresh each time).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Armory = require(sharedFolder:WaitForChild("Armory"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))
local Unlocks = require(sharedFolder:WaitForChild("Unlocks"))

local servicesFolder = script.Parent.Parent:WaitForChild("Services")
local DataService = require(servicesFolder:WaitForChild("DataService"))
local RemoteService = require(servicesFolder:WaitForChild("RemoteService"))
local ArenaService = require(script.Parent:WaitForChild("ArenaService"))
local WaveService = require(script.Parent:WaitForChild("WaveService"))
local RangeService = require(script.Parent:WaitForChild("RangeService"))
local VitalsService = require(script.Parent:WaitForChild("VitalsService"))
local WeaponService = require(script.Parent:WaitForChild("WeaponService"))
local UnlockService = require(script.Parent:WaitForChild("UnlockService"))
local RunFx = require(script.Parent:WaitForChild("RunFx"))

local TICK_INTERVAL_SECONDS = 1

local isStudio = RunService:IsStudio()
local tickAccumulator = 0
local levelConnection: RBXScriptConnection? = nil
local warnedRange = false
-- The godMode attribute is a state, applied when it changes, so the remote lever's own setting
-- for one player is not overwritten by the poll a second later.
local lastGodAttribute: boolean? = nil
-- The `gear` lever: which of debug.gearPresets each player holds (0 = none yet).
local gearPreset: { [Player]: number } = {}

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

-- Armory.json's bands (L3-4) whose level this build has a file for (Armory.BuiltBands, the hub's
-- rule too): their levels and their materials, each once, in the ladder's order. Empty without
-- Armory.json or a ladder.
local function builtBands(): ({ string }, { string })
	local armoryConfig = Catalog.GetArmoryConfig()
	if armoryConfig == nil then
		return {}, {}
	end
	local built: { [string]: boolean } = {}
	for _, id in Catalog.GetLevelIds() do
		built[id] = true
	end
	return Armory.BuiltBands(armoryConfig, built)
end

-- The live level's material. In the lobby (L3-28), where no level says which one: the material of
-- every Armory band whose level this build has a file for, so the T key pays what the built tiers
-- cost (Timber while only the Forest is built).
local function grantMaterials(player: Player?, amount: number): ()
	if amount <= 0 then
		return
	end
	local materials: { string } = {}
	local level = ArenaService.GetLevel()
	if level ~= nil then
		if level.material ~= "" then
			table.insert(materials, level.material)
		end
	else
		local _levels, built = builtBands()
		materials = built
	end
	if #materials == 0 then
		return
	end
	eachState(player, function(target: Player, state: Types.PlayerState)
		for _, material in materials do
			local owned = state.combat.materials[material] or 0
			state.combat.materials[material] = owned + amount
		end
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

-- True for a tier on the ladder: a whole number in 1..Armory.LadderSize.
local function onLadder(armoryConfig: Types.ArmoryConfig, tier: number): boolean
	return tier >= 1 and tier <= Armory.LadderSize(armoryConfig) and tier % 1 == 0
end

-- "melee=3,ranged=2": the session override (L1 ruling 34) in every Studio build, never the
-- profile (L3-28: its slot `gear` is frozen). A slot the lever did not name keeps the override's
-- tier as it was set (a window may hold what is fought at above it, 2-s1), else the tier the
-- player fights at now; a tier off the ladder is warned and ignored.
local function setGear(player: Player?, spec: string): ()
	local armoryConfig = Catalog.GetArmoryConfig()
	if armoryConfig == nil then
		return
	end
	local wanted: { [string]: number } = {}
	local size = Armory.LadderSize(armoryConfig)
	for slot, tierText in string.gmatch(spec, "(%a+)%s*=%s*(%d+)") do
		local tier = tonumber(tierText)
		if tier ~= nil and (slot == "melee" or slot == "ranged") then
			if onLadder(armoryConfig, tier) then
				wanted[slot] = tier
			else
				warn(`[DebugService] setGear: {slot} tier {tier} is off the ladder (1 to {size})`)
			end
		end
	end
	if next(wanted) == nil then
		return
	end
	eachState(player, function(target: Player, _state: Types.PlayerState)
		local fought, ascension = WeaponService.GearOf(target)
		local gear = WeaponService.GearOverride(target) or fought
		WeaponService.SetGearOverride(target, {
			melee = wanted.melee or gear.melee,
			ranged = wanted.ranged or gear.ranged,
		}, ascension)
		-- Weapons decide max HP: VitalsService, the bar's only writer, resizes it from the tiers.
		VitalsService.RefreshMaxHp(target)
		ArenaService.SendSnapshot(target)
	end)
end

-- L1 ruling 33, the G key: the caller's next entry of debug.gearPresets becomes their session
-- gear, and the party is told which.
local function nextGear(player: Player?): ()
	local combatConfig = Catalog.GetCombatConfig()
	local armoryConfig = Catalog.GetArmoryConfig()
	if player == nil or combatConfig == nil or armoryConfig == nil then
		return
	end
	local presets = combatConfig.debug.gearPresets
	if presets == nil or #presets == 0 then
		return
	end
	-- A press steps past the preset the player holds now (a fresh profile holds the first one),
	-- so every press is a visible change. The one remembered counts only while it is still the
	-- override: an upgrade, setTier or resetArmory clears the override behind it. The override is
	-- read as it was set, not as fought (2-s1: G's T1 fights a held Flamethrower at its T2, which
	-- matches no preset, so every press would set T1 again); without one, what is fought at.
	local gear = WeaponService.GearOverride(player) or WeaponService.GearOf(player)
	local current = gearPreset[player]
	local held = if current ~= nil then presets[current] else nil
	if held == nil or held.melee ~= gear.melee or held.ranged ~= gear.ranged then
		current = 0
		for at, entry in presets do
			if entry.melee == gear.melee and entry.ranged == gear.ranged then
				current = at
				break
			end
		end
	end
	local index = (current or 0) % #presets + 1
	local preset = presets[index]
	if not onLadder(armoryConfig, preset.melee) or not onLadder(armoryConfig, preset.ranged) then
		warn(`[DebugService] gear preset "{preset.name}" names a tier off the ladder`)
		return
	end
	gearPreset[player] = index
	WeaponService.SetGearOverride(player, { melee = preset.melee, ranged = preset.ranged }, nil)
	VitalsService.RefreshMaxHp(player)
	RunFx.Push({ kind = "notice", text = "Gear " .. preset.name })
end

local function setGodMode(player: Player?, enabled: boolean): ()
	if player ~= nil then
		VitalsService.SetGod(player, enabled)
		return
	end
	for _, member in ArenaService.GetMembers() do
		VitalsService.SetGod(member.player, enabled)
	end
end

-- L2-19: owned (or not) for the caller, or for everyone admitted on the attribute path; the
-- party is told once when anybody's changed.
local function setAbility(player: Player?, id: string, owned: boolean): ()
	local targets: { Player } = if player ~= nil then { player } else UnlockService.Admitted()
	local changed = false
	for _, target in targets do
		local done = if owned
			then UnlockService.GrantAbility(target, id)
			else UnlockService.RemoveAbility(target, id)
		changed = changed or done
	end
	if changed then
		RunFx.Push({
			kind = "notice",
			text = `{UnlockService.NameOf(id)} {if owned then "on" else "off"}`,
		})
	else
		warn(`[DebugService] {if owned then "grant" else "remove"}Ability "{id}": nobody changed`)
	end
end

local function resetSecrets(player: Player?): ()
	UnlockService.ResetSecrets(player)
	WaveService.ForgetSecrets(player)
	RunFx.Push({ kind = "notice", text = "Secrets and shortcuts reset (from the next run)" })
end

-- L2-38: a weapon family owned (or not) by the caller, or by everyone admitted on the attribute
-- path; the party is told once when anybody's changed.
local function setFamily(player: Player?, id: string, owned: boolean): ()
	local targets: { Player } = if player ~= nil then { player } else UnlockService.Admitted()
	local changed = false
	for _, target in targets do
		local done = if owned
			then UnlockService.GrantFamily(target, id)
			else UnlockService.RemoveFamily(target, id)
		changed = changed or done
	end
	local name = UnlockService.FamilyName(id)
	if changed then
		RunFx.Push({
			kind = "notice",
			text = if owned then `{name} is yours` else `{name} removed`,
		})
	else
		warn(`[DebugService] {if owned then "grant" else "remove"}Family "{id}": nobody changed`)
	end
end

-- L3-28, `setTier` "<family>=<tier>" (read by Unlocks.TierLever, the hub's reading too): that
-- family's tier, clamped into its window, for the caller or everyone admitted
-- (UnlockService.SetTier); the party is told the tier written.
local function setTier(player: Player?, spec: string): ()
	local family, tier = Unlocks.TierLever(spec)
	if family == nil or tier == nil then
		warn(`[DebugService] setTier "{spec}": write it as <family>=<tier>`)
		return
	end
	local targets: { Player } = if player ~= nil then { player } else UnlockService.Admitted()
	local written: number? = nil
	for _, target in targets do
		written = UnlockService.SetTier(target, family, tier) or written
	end
	if written ~= nil then
		RunFx.Push({ kind = "notice", text = `{UnlockService.FamilyName(family)} T{written}` })
	else
		warn(`[DebugService] setTier "{spec}": no family with a window, or nobody to set it for`)
	end
end

-- L3-28, `grantStar`: Armory.json's star difficulty (the band top's trophy) of a level, or of every
-- built band's level for Unlocks.ALL_STARS, saved for the caller or everyone admitted; the map is
-- resent. R4: a new star pays its first-clear reward as a cleared run's does
-- (WaveService.GrantStars), and the notice names what it gave ("★ Hard: Forest Road · Warhammer").
local function grantStar(player: Player?, which: string): ()
	local armoryConfig = Catalog.GetArmoryConfig()
	local ladder = if armoryConfig ~= nil then armoryConfig.ladder else nil
	if ladder == nil then
		warn("[DebugService] grantStar: Armory.json has no ladder, so no star difficulty")
		return
	end
	local levelIds: { string } = {}
	if which == Unlocks.ALL_STARS then
		levelIds = builtBands()
	elseif Catalog.GetLevelFile(which) ~= nil then
		table.insert(levelIds, which)
	end
	if #levelIds == 0 then
		warn(`[DebugService] grantStar "{which}": no such level in this build`)
		return
	end
	local difficulty = ladder.starDifficulty
	local targets: { Player } = if player ~= nil then { player } else UnlockService.Admitted()
	-- What the new stars gave, each item once: a family by name, and the most Valor one player got.
	local gifts: { string } = {}
	local valor = 0
	for _, target in targets do
		local _new, grants = WaveService.GrantStars(target, levelIds, difficulty)
		local paid = 0
		for _, grant in grants do
			local family = grant.family
			local name = if family ~= nil then UnlockService.FamilyName(family) else nil
			if name ~= nil and table.find(gifts, name) == nil then
				table.insert(gifts, name)
			end
			paid += grant.valor
		end
		valor = math.max(valor, paid)
	end
	if valor > 0 then
		table.insert(gifts, `+{valor} Valor`)
	end
	local map = Catalog.GetExpeditionsConfig()
	local named = if map ~= nil then map.difficultyNames[difficulty] else nil
	local levelNames: { string } = {}
	for _, levelId in levelIds do
		local file = Catalog.GetLevelFile(levelId)
		table.insert(levelNames, if file ~= nil then file.name else levelId)
	end
	local label = `★ {named or difficulty}: {table.concat(levelNames, ", ")}`
	if #gifts > 0 then
		label ..= ` · {table.concat(gifts, ", ")}`
	end
	RunFx.Push({ kind = "notice", text = label })
end

-- L3-28, `resetArmory`: tiers, the saved loadout and the stars emptied for the caller or everyone
-- admitted (the session's stars too), the held pair back to the starters, the override and the
-- G key's place gone. Materials, Valor, families and secrets stay.
local function resetArmory(player: Player?): ()
	local reset = UnlockService.ResetArmory(player)
	for _, target in reset do
		gearPreset[target] = nil
	end
	WaveService.ForgetStars(player)
	RunFx.Push({ kind = "notice", text = "Armory reset: tiers, loadout and stars" })
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
	elseif lever == "skip" and (value == "stage" or value == "boss") then
		WaveService.Skip(value)
	elseif lever == "gear" and value == "next" then
		nextGear(player)
	elseif lever == "spawn" and typeof(value) == "string" and value ~= "" then
		WaveService.SpawnOne(value)
	elseif lever == "godMode" then
		setGodMode(player, value == true)
	elseif lever == "killAll" then
		WaveService.KillAll()
	elseif lever == "setGear" and typeof(value) == "string" then
		setGear(player, value)
	elseif lever == "grantMaterials" and typeof(value) == "number" then
		grantMaterials(player, value)
	elseif lever == "grantValor" and typeof(value) == "number" then
		grantValor(player, value)
	elseif lever == "admitCheck" then
		admitCheck(player)
	elseif lever == "grantAbility" and typeof(value) == "string" and value ~= "" then
		setAbility(player, value, true)
	elseif lever == "removeAbility" and typeof(value) == "string" and value ~= "" then
		setAbility(player, value, false)
	elseif lever == "resetSecrets" then
		resetSecrets(player)
	elseif lever == "grantFamily" and typeof(value) == "string" and value ~= "" then
		setFamily(player, value, true)
	elseif lever == "removeFamily" and typeof(value) == "string" and value ~= "" then
		setFamily(player, value, false)
	elseif lever == "setTier" and typeof(value) == "string" and value ~= "" then
		setTier(player, value)
	elseif lever == "grantStar" and typeof(value) == "string" and value ~= "" then
		grantStar(player, value)
	elseif lever == "resetArmory" then
		resetArmory(player)
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
	-- L2-19: a Combat.json without these keys leaves the attribute levers off.
	local grantAttribute = debugConfig.grantAbilityAttribute
	local granted = if grantAttribute ~= nil then consumeString(grantAttribute) else nil
	if granted ~= nil then
		applyLever(nil, "grantAbility", granted)
	end
	local removeAttribute = debugConfig.removeAbilityAttribute
	local removed = if removeAttribute ~= nil then consumeString(removeAttribute) else nil
	if removed ~= nil then
		applyLever(nil, "removeAbility", removed)
	end
	local resetAttribute = debugConfig.resetSecretsAttribute
	if resetAttribute ~= nil and consumeNumber(resetAttribute) ~= nil then
		applyLever(nil, "resetSecrets", true)
	end
	-- L2-38: the same, for weapon families.
	local grantFamilyAttribute = debugConfig.grantFamilyAttribute
	local grantedFamily = if grantFamilyAttribute ~= nil
		then consumeString(grantFamilyAttribute)
		else nil
	if grantedFamily ~= nil then
		applyLever(nil, "grantFamily", grantedFamily)
	end
	local removeFamilyAttribute = debugConfig.removeFamilyAttribute
	local removedFamily = if removeFamilyAttribute ~= nil
		then consumeString(removeFamilyAttribute)
		else nil
	if removedFamily ~= nil then
		applyLever(nil, "removeFamily", removedFamily)
	end
	-- L3-28: the Armory's three. A Combat.json without these keys leaves them off.
	local setTierAttribute = debugConfig.setTierAttribute
	local tierSpec = if setTierAttribute ~= nil then consumeString(setTierAttribute) else nil
	if tierSpec ~= nil then
		applyLever(nil, "setTier", tierSpec)
	end
	local grantStarAttribute = debugConfig.grantStarAttribute
	local starLevel = if grantStarAttribute ~= nil then consumeString(grantStarAttribute) else nil
	if starLevel ~= nil then
		applyLever(nil, "grantStar", starLevel)
	end
	local resetArmoryAttribute = debugConfig.resetArmoryAttribute
	if resetArmoryAttribute ~= nil and consumeNumber(resetArmoryAttribute) ~= nil then
		applyLever(nil, "resetArmory", true)
	end

	-- States, read but never reset. God mode is applied when the attribute changes (and to
	-- whoever is in the run at that moment); a new arrival starts mortal.
	local god = workspace:GetAttribute(debugConfig.godModeAttribute) == true
	if god ~= lastGodAttribute then
		lastGodAttribute = god
		setGodMode(nil, god)
	end
end

function DebugService.Init(): ()
	Players.PlayerRemoving:Connect(function(player: Player)
		gearPreset[player] = nil
	end)
end

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
		-- The range has no run and no waves; its attributes stay untouched too.
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
