--!strict
-- The dungeon place's host of the run's tally card (docs/prompts/l4-w3-contract.md §4.2 "Hosts",
-- combat; the card itself is the shared UI/RunTally, which the city hosts too). Shown for a
-- RunState that carries a `result` where a card belongs (CombatUIController decides that): the
-- level and its difficulty, how the run ended and how far it got, one row per source of pay, the
-- wallet rolling in, and where the party goes next. Every number is the server's: the summary's
-- rows and totals, the last Snapshot's wallet.
--
-- Every run ends in the lobby camp, never in the city (L1 ruling 20): the countdown reads "Back
-- to camp in 8s". Back to camp ends the wait at once (the leader or a solo player; ruling 21), and
-- Return to your city goes home alone (ruling 22; not offered in a proving build, where the trip
-- home kicks from Studio).
--
-- A result whose reason is `leave` is the trip home itself: the session's totals under the map's
-- name, no countdown and no button.
--
-- RunState comes four times a second during the summary, so the card is shown again only when
-- what it shows changed (`key`); between broadcasts the countdown ticks here. The summary arrives
-- from the network: it is read by RunLines.ReadSummary, the one reader the city and its server use
-- too (the L4 W3 fix round's F7), and a summary it refuses shows no rows and no totals. The rows,
-- the totals, the wallet and Valor's purpose are UI/TallyRules' (F13). No sound (the combat
-- place's ids stay 0, and the card's buttons click silently like the Armory's).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Format = require(sharedFolder:WaitForChild("Format"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))
local RunLines = require(sharedFolder:WaitForChild("RunLines"))

local Theme = require(script.Parent:WaitForChild("Theme"))
local RunTally = require(script.Parent:WaitForChild("RunTally"))
local TallyRules = require(script.Parent:WaitForChild("TallyRules"))

export type Deps = {
	-- "Back to camp": RequestAbandon during the summary.
	onBack: () -> (),
	-- "Return to your city": RequestLeave.
	onReturn: () -> (),
	-- false = no Return button (a proving build).
	canReturn: boolean,
	-- The key that opens the Armory, named in a first clear's family note ("K", "Y"); nil = no
	-- key (touch: the HUD's button).
	armoryKey: string?,
}

-- What the RunState round the result adds. `canBack` = the local player may end the wait (the
-- leader, or the only human). `difficultyName` and `mapName` are the map's display names.
export type ShowInfo = {
	partySize: number,
	returnIn: number?,
	canBack: boolean,
	difficultyName: string,
	mapName: string,
}

export type Handle = {
	Show: (summary: any, result: Types.RunResult, info: ShowInfo) -> (),
	Hide: () -> (),
	IsVisible: () -> boolean,
	-- True while Back to camp is offered: the host's Enter key asks before it sends.
	CanBack: () -> boolean,
	-- The latest Snapshot's cash and `combat` (its materials, Valor and abilities).
	SetWallet: (cash: number, combat: Types.CombatProfile?) -> (),
	SetLayout: (scale: number, viewportSize: Vector2) -> (),
	Destroy: () -> (),
}

local WORDS = {
	runKicker = "RUN REPORT",
	homeKicker = "EXPEDITION REPORT",
	homeSubtitle = "On the way home",
	back = "Back to camp",
	backId = "back",
	returnText = "Return to your city",
	returnId = "return",
	countdown = "Back to camp in ",
	-- Keyboards only, and only for whoever may end the wait: the key the host binds to it.
	keyHint = " · Enter to go now",
	camps = "Camps ",
	of = " / ",
	sep = " · ",
	share = "Your share ",
	percent = "%",
	family = " is yours: equip it in the Armory",
	leave = "leave",
	-- How a run ended, in the player's words. An unknown reason says nothing rather than guess.
	reasons = {
		cleared = "Cleared",
		down = "You went down",
		wipe = "You went down",
		abandoned = "Abandoned",
		runCap = "Out of time",
	} :: { [string]: string },
}
local PERCENT = 100

local TallyHost = {}

-- L3-17: what a first clear gave beyond its row, from the network: a weapon family is the one
-- thing a row cannot say ("Warhammer is yours: equip it in the Armory (K)"). Its Valor is the
-- row "First Brutal clear" already. A family the config does not name shows its id.
local function familyNote(result: Types.RunResult, armoryKey: string?): string?
	local reward: any = result.firstClear
	if typeof(reward) ~= "table" then
		return nil
	end
	local family = reward.family
	if typeof(family) ~= "string" or family == "" then
		return nil
	end
	local config = Catalog.GetProvingGroundsConfig()
	local def = if config ~= nil then config.weapons[family] else nil
	return (if def ~= nil then def.name else family)
		.. WORDS.family
		.. (if armoryKey ~= nil then " (" .. armoryKey .. ")" else "")
end

-- How it ended, how far it got, how long it took and, in a party, this player's share.
local function subtitleOf(
	summary: Types.RunSummary?,
	result: Types.RunResult,
	partySize: number
): string
	local parts: { string } = {}
	local reason = WORDS.reasons[result.reason]
	if reason ~= nil then
		table.insert(parts, reason)
	end
	if result.camps > 0 then
		table.insert(
			parts,
			WORDS.camps .. Format.Cash(result.campsCleared) .. WORDS.of .. Format.Cash(result.camps)
		)
	end
	if summary ~= nil then
		table.insert(parts, Format.Duration(summary.seconds))
		if partySize > 1 then
			table.insert(
				parts,
				WORDS.share
					.. Format.Cash(math.round(math.min(summary.damageShare, 1) * PERCENT))
					.. WORDS.percent
			)
		end
	end
	return table.concat(parts, WORDS.sep)
end

function TallyHost.new(parent: Instance, deps: Deps): Handle
	local connections: { RBXScriptConnection } = {}
	local keyboard = UserInputService.KeyboardEnabled
	local state = {
		key = "",
		canBack = false,
		-- os.clock() the party is due back in the camp; nil while no return is pending. Ticked
		-- here between RunStates; every RunState re-anchors it.
		returnAt = nil :: number?,
		tick = 0,
		material = "",
		cash = 0,
		combat = nil :: Types.CombatProfile?,
	}

	local tally = RunTally.new(parent, {
		onButton = function(id: string)
			if id == WORDS.backId then
				deps.onBack()
			elseif id == WORDS.returnId then
				deps.onReturn()
			end
		end,
	})

	local function wallet(): RunTally.Wallet
		return TallyRules.Wallet(state.cash, state.combat, state.material)
	end

	local function paintCountdown(): ()
		local dueAt = state.returnAt
		if dueAt == nil then
			tally.SetCountdown(nil)
			return
		end
		local left = math.max(math.ceil(dueAt - os.clock()), 0)
		tally.SetCountdown(
			WORDS.countdown
				.. Format.Duration(left)
				.. (if state.canBack and keyboard then WORDS.keyHint else "")
		)
	end

	local function show(raw: any, result: Types.RunResult, info: ShowInfo): ()
		local summary = RunLines.ReadSummary(raw)
		local leaving = result.reason == WORDS.leave
		local canBack = not leaving and info.canBack
		local canReturn = not leaving and deps.canReturn
		local returnIn = info.returnIn
		state.canBack = canBack
		state.returnAt = if not leaving
				and returnIn ~= nil
				and returnIn > 0
			then os.clock() + returnIn
			else nil
		paintCountdown()
		local key = table.concat({
			result.reason,
			result.levelId,
			result.difficulty,
			tostring(result.star),
			if summary ~= nil
				then table.concat({
					tostring(summary.cash),
					tostring(summary.valor),
					tostring(summary.kills),
					tostring(#summary.lines),
				}, ",")
				else "-",
			tostring(canBack),
			tostring(canReturn),
		}, "|")
		if key == state.key and tally.IsVisible() then
			return
		end
		state.key = key
		local expeditions = Catalog.GetExpeditionsConfig()
		local totals: RunTally.Totals = if summary ~= nil
			then TallyRules.Totals(summary)
			else { cash = 0, material = "", materials = 0, valor = 0 }
		state.material = totals.material
		local buttons: { RunTally.Button } = {}
		if canBack then
			table.insert(buttons, { id = WORDS.backId, text = WORDS.back, accent = true })
		end
		if canReturn then
			table.insert(
				buttons,
				{ id = WORDS.returnId, text = WORDS.returnText, accent = not canBack }
			)
		end
		local combat = state.combat
		tally.Show({
			kicker = if leaving then WORDS.homeKicker else WORDS.runKicker,
			title = if leaving
				then (if summary ~= nil then summary.title else info.mapName)
				elseif info.difficultyName ~= "" then result.levelName
					.. WORDS.sep
					.. info.difficultyName
				else result.levelName,
			subtitle = if leaving
				then WORDS.homeSubtitle
				else subtitleOf(summary, result, info.partySize),
			star = not leaving and result.star,
			lines = TallyRules.Rows(if summary ~= nil then summary.lines else nil, expeditions),
			totals = totals,
			wallet = wallet(),
			note = if leaving then nil else familyNote(result, deps.armoryKey),
			nextAbility = TallyRules.NextAbility(
				expeditions,
				if combat ~= nil then combat.abilities else nil
			),
			buttons = buttons,
		})
	end

	table.insert(
		connections,
		RunService.Heartbeat:Connect(function(deltaTime: number)
			if state.returnAt == nil or not tally.IsVisible() then
				return
			end
			state.tick += deltaTime
			if state.tick < Theme.COMBAT_TIMER_TICK_SECONDS then
				return
			end
			state.tick = 0
			paintCountdown()
		end)
	)

	local handle: Handle = {
		Show = show,
		Hide = function()
			tally.Hide()
			state.returnAt = nil
			state.key = ""
		end,
		IsVisible = tally.IsVisible,
		CanBack = function(): boolean
			return tally.IsVisible() and state.canBack
		end,
		SetWallet = function(cash: number, combat: Types.CombatProfile?)
			state.cash = cash
			state.combat = combat
			if tally.IsVisible() then
				tally.SetWallet(wallet())
			end
		end,
		SetLayout = tally.SetLayout,
		Destroy = function()
			for _, connection in connections do
				connection:Disconnect()
			end
			table.clear(connections)
			tally.Destroy()
		end,
	}
	return handle
end

return TallyHost
