--!strict
-- The pure rules of the run's tally card and of the dungeon lobby's depart line
-- (docs/prompts/l4-w3-fix-round.md F13, F15; the L4 W3 review, slice 3 m3 and s4), so
-- tools/crowd_harness/tests_l4w3_tally.luau runs the very functions the hosts act on. No Instance,
-- no service, no clock: the hosts read Catalog, Theme and the RunState and hand the readings in.
-- RunTally, TallyHost and CombatUIController call these; the city's host reaches them through
-- RunTally's wrappers, which read Catalog for it.
--  * Rows, Totals, Owned, Wallet: the card's rows from RunSummary.lines, its totals with the main
--    material, what a profile holds of it.
--  * WithText, NextAbility: Valor's purpose ("next: Double Jump · 10 Valor", "next: Glide · with
--    the Castle"). An `abilities.upcoming` entry is read the way the Armory's tab reads it
--    (ArmoryAbilityPage.Offers), so a malformed entry is left out here as there, never thrown on.
--  * Flights: how many coins and logs fly. The host hands in Theme.lowEndDevice, never
--    reducedMotion (true on every touch device: gating on it would hide the flight from phones).
--  * IsRunResult: a RunState's `result` a card may be built from (the host's show key reads its
--    level id, so a result without one is none).
--  * ReadDepart, NodeOf, DepartText, Depart: RunState.depart off the wire, the map node a level
--    has, the lobby's notice line, and what the map does on each RunState (opens, holds, closes,
--    selects).
-- Every number shown is the server's; nothing here computes pay.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Format = require(sharedFolder:WaitForChild("Format"))
local Unlocks = require(sharedFolder:WaitForChild("Unlocks"))

-- Every word these rules write. A name the server sends empty takes the card's word.
local WORDS = {
	raiders = "Raiders",
	times = " ×",
	camp = "Camp",
	campSuffix = " bonus",
	boss = "The boss",
	chest = "A chest",
	key = "A key",
	keySuffix = " found",
	firstClear = "First ",
	firstClearSuffix = " clear",
	mentor = "Mentor bonus",
	valor = " Valor",
	next = "next: ",
	sep = " · ",
	withThe = "with the ",
	with = "with ",
	waiting = "Waiting for your party",
	startsIn = " starts in ",
	pickSep = ":",
}
-- The RunState phase the depart belongs to (the server sends none elsewhere).
local LOBBY = "lobby"
local DEPART_STATES: { [string]: boolean } = { waiting = true, counting = true, picked = true }

-- One display row (both hosts build them here, so they agree).
export type Row = {
	kind: string,
	label: string,
	cash: number,
	material: string,
	materials: number,
	valor: number,
}
export type Totals = { cash: number, material: string, materials: number, valor: number }
-- What the player owns now; `materials` is the amount of Totals.material.
export type Wallet = { cash: number, materials: number, valor: number }
-- How many icons fly on a device that is not low end, and on one that is.
export type FlightCounts = { coins: number, coinsLowEnd: number, logs: number, logsLowEnd: number }
-- What the lobby host keeps between RunStates: the auto-start held the screen at the last one,
-- and the "<levelId>:<difficulty>" a `picked` already opened the map on (once per arrival).
export type DepartMemory = { holding: boolean, picked: string }
-- What one RunState does to the lobby's map and notice line.
export type DepartStep = {
	-- The notice line (nil = none).
	line: string?,
	-- The auto-start waits or counts: it has the screen.
	holding: boolean,
	-- Open the map (after `select`, when there is one).
	open: boolean,
	-- Close the map if it is open: the wait or the count began on this RunState.
	close: boolean,
	-- Select this node and difficulty: a `picked` new to this arrival. nil = leave the selection.
	select: { node: string, difficulty: string }?,
	memory: DepartMemory,
}

local TallyRules = {}
TallyRules.WORDS = WORDS

local function finite(value: any): boolean
	return typeof(value) == "number" and value == value and math.abs(value) < math.huge
end

-- A count the card may show: finite and above 0, else 0 (Format.Cash never returns on infinity).
local function amount(value: any): number
	return if finite(value) and value > 0 then value else 0
end

local function nodeName(expeditions: Types.ExpeditionsConfig?, nodeId: string): string
	if expeditions ~= nil then
		for _, node in expeditions.nodes do
			if node.id == nodeId then
				return node.name
			end
		end
	end
	return nodeId
end

-- "with the Castle": the words for an ability or a weapon that comes with a later map node. A
-- name that already starts with an article keeps its own ("with another Planet", "with the Dream").
function TallyRules.WithText(expeditions: Types.ExpeditionsConfig?, nodeId: string): string
	local name = nodeName(expeditions, nodeId)
	local first, rest = string.match(name, "^(%a+) (.+)$")
	if first == "The" and rest ~= nil then
		return WORDS.withThe .. rest
	end
	if (first == "A" or first == "An" or first == "Another") and rest ~= nil then
		return WORDS.with .. string.lower(first) .. " " .. rest
	end
	return WORDS.withThe .. name
end

-- The row words for each kind of line (RunSummary.lines, read through RunLines.Read).
function TallyRules.Rows(lines: { Types.RunLine }?, expeditions: Types.ExpeditionsConfig?): { Row }
	local rows: { Row } = {}
	if lines == nil then
		return rows
	end
	for _, line in lines do
		local kind = line.kind
		local name = line.name
		local label: string
		if kind == "raiders" then
			label = (if name ~= "" then name else WORDS.raiders)
				.. (if line.count > 0 then WORDS.times .. Format.Cash(line.count) else "")
		elseif kind == "camp" then
			label = (if name ~= "" then name else WORDS.camp) .. WORDS.campSuffix
		elseif kind == "boss" then
			label = if name ~= "" then name else WORDS.boss
		elseif kind == "chest" then
			label = if name ~= "" then name else WORDS.chest
		elseif kind == "key" then
			label = (if name ~= "" then name else WORDS.key) .. WORDS.keySuffix
		elseif kind == "firstClear" then
			-- The id is "<levelId>:<difficulty>"; the difficulty's display name is the map's.
			local difficulty = string.match(line.id, ":([^:]+)$") or ""
			local word = if expeditions ~= nil then expeditions.difficultyNames[difficulty] else nil
			label = WORDS.firstClear .. (word or difficulty) .. WORDS.firstClearSuffix
		elseif kind == "mentor" then
			label = WORDS.mentor
		else
			label = if name ~= "" then name else kind
		end
		table.insert(rows, {
			kind = kind,
			label = label,
			cash = line.cash,
			material = line.material,
			materials = line.materials,
			valor = line.valor,
		})
	end
	return rows
end

-- The summary's totals, with its main material: the largest amount, ties by name (the table came
-- over the network, so its order is undefined and the same run must read the same twice).
function TallyRules.Totals(summary: Types.RunSummary): Totals
	local material, most = "", 0
	for name, value in summary.materials do
		if
			typeof(name) == "string"
			and amount(value) > 0
			and (value > most or (value == most and name < material))
		then
			material, most = name, value
		end
	end
	return { cash = summary.cash, material = material, materials = most, valor = summary.valor }
end

-- What a profile's material map holds of `material` (0 for anything that is not a count).
function TallyRules.Owned(materials: { [string]: any }?, material: string): number
	if materials == nil or material == "" then
		return 0
	end
	return amount(materials[material])
end

-- The card's wallet line: the cash the host names (the latest Snapshot's, or the city's state),
-- and the main material's count and Valor from the profile's `combat` (nil = none).
function TallyRules.Wallet(cash: number, combat: any, material: string): Wallet
	local profile = if typeof(combat) == "table" then combat else nil
	local materials = if profile ~= nil then profile.materials else nil
	return {
		cash = amount(cash),
		materials = TallyRules.Owned(
			if typeof(materials) == "table" then materials else nil,
			material
		),
		valor = amount(if profile ~= nil then profile.valor else nil),
	}
end

-- An `abilities.upcoming` entry as the Armory's tab takes it: a table whose id, name, text and
-- `with` are strings.
local function upcomingEntry(def: any): boolean
	return typeof(def) == "table"
		and typeof(def.id) == "string"
		and typeof(def.name) == "string"
		and typeof(def.text) == "string"
		and typeof(def.with) == "string"
end

-- Valor's purpose on the card (contract §7): the first ability on sale the player does not own,
-- in the Armory's order (`order`, then id; what Unlocks.Sellable sells): "next: Double Jump · 10
-- Valor". Failing that the first well-formed coming one not owned: "next: Glide · with the
-- Castle". Else nil (no Expeditions config, or everything owned). The Armory's tab also leaves out
-- an upcoming entry with the id of one on sale or of an earlier entry; here every ability on sale
-- is owned by the time `upcoming` is read, and a repeated id is owned or not with its first, so
-- that rule could not change the answer and is not repeated.
function TallyRules.NextAbility(
	expeditions: Types.ExpeditionsConfig?,
	owned: { [string]: boolean }?
): string?
	local sellable = Unlocks.Sellable(expeditions)
	local best: Types.UnlockAbilityDef? = nil
	for _, def in sellable do
		if
			not Unlocks.Owns(owned, def.id)
			and (
				best == nil
				or def.order < best.order
				or (def.order == best.order and def.id < best.id)
			)
		then
			best = def
		end
	end
	if best ~= nil then
		return WORDS.next .. best.name .. WORDS.sep .. Format.Cash(best.price.valor) .. WORDS.valor
	end
	local abilities: any = if expeditions ~= nil then expeditions.abilities else nil
	local upcoming: any = if typeof(abilities) == "table" then abilities.upcoming else nil
	if typeof(upcoming) ~= "table" then
		return nil
	end
	for _, def in upcoming do
		if upcomingEntry(def) and not Unlocks.Owns(owned, def.id) then
			return WORDS.next .. def.name .. WORDS.sep .. TallyRules.WithText(expeditions, def.with)
		end
	end
	return nil
end

-- How many coins and logs fly (contract §4.2 "Phones"): `lowEnd` is Theme.lowEndDevice, never
-- reducedMotion. No cash, no coins; no main material, no logs. Never more logs than the pile has
-- places (`counts.logs`).
function TallyRules.Flights(lowEnd: boolean, totals: Totals, counts: FlightCounts): (number, number)
	local coins = 0
	if totals.cash > 0 then
		coins = if lowEnd then counts.coinsLowEnd else counts.coins
	end
	local logs = 0
	if totals.material ~= "" and totals.materials > 0 then
		logs = math.min(if lowEnd then counts.logsLowEnd else counts.logs, counts.logs)
	end
	return coins, logs
end

-- A RunState's `result` off the network that a card may be built from: the level's id and name,
-- the difficulty and the reason as strings (the show key joins the first three, F15), the camps as
-- finite numbers (the subtitle formats them), the star as a boolean.
function TallyRules.IsRunResult(payload: any): boolean
	return typeof(payload) == "table"
		and typeof(payload.levelId) == "string"
		and typeof(payload.levelName) == "string"
		and typeof(payload.difficulty) == "string"
		and typeof(payload.reason) == "string"
		and finite(payload.campsCleared)
		and finite(payload.camps)
		and typeof(payload.star) == "boolean"
end

local function seconds(value: any): number?
	return if finite(value) and value >= 0 then value else nil
end

-- RunState.depart off the network: nil unless the level, the difficulty and a known state are
-- there; a count that is not a finite number of seconds is left out.
function TallyRules.ReadDepart(raw: any): Types.RunDepart?
	if
		typeof(raw) ~= "table"
		or typeof(raw.levelId) ~= "string"
		or typeof(raw.difficulty) ~= "string"
		or typeof(raw.state) ~= "string"
		or DEPART_STATES[raw.state] ~= true
	then
		return nil
	end
	-- Checked above against DEPART_STATES; read through `any` again so the check does not narrow
	-- it to a plain string.
	local fields: any = raw
	return {
		levelId = raw.levelId,
		difficulty = raw.difficulty,
		state = fields.state,
		startsIn = seconds(raw.startsIn),
		waitIn = seconds(raw.waitIn),
	}
end

-- The first map node that names the level (the one the map selects for it), nil for none.
function TallyRules.NodeOf(expeditions: Types.ExpeditionsConfig?, levelId: string): Types.MapNode?
	if expeditions == nil then
		return nil
	end
	for _, node in expeditions.nodes do
		if node.level ~= nil and node.level == levelId then
			return node
		end
	end
	return nil
end

-- The lobby's notice line for a depart (contract §3 "Client"): "Waiting for your party · 25" (the
-- seconds left of coop.lobbyWaitSeconds), "Forest Road · Normal starts in 5" (the map's names).
-- `picked` has no line: the map shows it. The server sends the state at every whole second of
-- either count, so the line shows what the last RunState said.
function TallyRules.DepartText(
	depart: Types.RunDepart,
	expeditions: Types.ExpeditionsConfig?
): string?
	if depart.state == "waiting" then
		local left = depart.waitIn
		return WORDS.waiting
			.. (if left ~= nil then WORDS.sep .. Format.Cash(math.ceil(left)) else "")
	elseif depart.state == "counting" then
		local node = TallyRules.NodeOf(expeditions, depart.levelId)
		local name = if node ~= nil then node.name else depart.levelId
		local difficulty = if expeditions ~= nil
			then expeditions.difficultyNames[depart.difficulty] or depart.difficulty
			else depart.difficulty
		local left = depart.startsIn
		return name
			.. WORDS.sep
			.. difficulty
			.. WORDS.startsIn
			.. (if left ~= nil then Format.Cash(math.ceil(left)) else "")
	end
	return nil
end

-- What the lobby's map does on one RunState (contract §3 "Client"; the review's m3 p1 and p2):
--  * the depart is read in the lobby only;
--  * while it waits or counts it holds the screen: the map does not open when the phase becomes
--    `lobby`, and an open map closes on the RunState the hold began on (a RunState after the
--    lobby's first, or R pressed with the map open). The leader may open it again by hand;
--  * `picked` selects that level's node and difficulty and opens the map, once per arrival (per
--    "<levelId>:<difficulty>"; a level no node names is no pick, and is asked again next time);
--  * with neither, the map opens when the phase becomes `lobby`, as it always has.
-- `memory` is the last step's; the answer carries the next one (the argument is never written).
function TallyRules.Depart(
	raw: any,
	phase: string,
	last: string,
	expeditions: Types.ExpeditionsConfig?,
	memory: DepartMemory
): DepartStep
	local depart = if phase == LOBBY then TallyRules.ReadDepart(raw) else nil
	local holding = depart ~= nil and (depart.state == "waiting" or depart.state == "counting")
	local entered = phase == LOBBY and last ~= LOBBY
	local picked = memory.picked
	local select: { node: string, difficulty: string }? = nil
	if depart ~= nil and depart.state == "picked" then
		local pick = depart.levelId .. WORDS.pickSep .. depart.difficulty
		local node = TallyRules.NodeOf(expeditions, depart.levelId)
		if pick ~= picked and node ~= nil then
			picked = pick
			select = { node = node.id, difficulty = depart.difficulty }
		end
	end
	return {
		line = if depart ~= nil then TallyRules.DepartText(depart, expeditions) else nil,
		holding = holding,
		open = (entered and not holding) or select ~= nil,
		close = holding and not memory.holding,
		select = select,
		memory = { holding = holding, picked = picked },
	}
end

return TallyRules
