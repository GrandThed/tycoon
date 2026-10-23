--!strict
-- L4 W3 (docs/prompts/l4-w3-contract.md §4.1 and §5): what one credit writes on a member's card,
-- and which era a member's run cash is paid at. Pure, as StageFlow and SecretFlow are: tables,
-- strings and numbers only, no service, no Instance, no clock, so tools/crowd_harness loads it as it
-- stands. ArenaService keeps the cards and calls Credit and Mentor; WaveService names each credit's
-- source with the keys below and reads PayEra at the one cash choke point.
--
-- The totals are the truth (L4W3-5); `lines` are display, merged by source (RunLines.Add). Every
-- credit adds 1 to its line's count: for raiders and a boss that is one body whose reward this
-- member shared (their own kills in a solo run), for the other kinds one event.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local RunLines = require(sharedFolder:WaitForChild("RunLines"))

-- What one credit adds to its line's count.
local CREDIT_COUNT = 1
-- The pay era of a member whose profile names no usable era: the first (Village, x1).
local FIRST_ERA = 1

local RunCredit = {}

-- A card with nothing on it yet: a run's under its level's name, the session's under the map's
-- (ArenaService), and the zero card a refused arrival carries home (ReturnService).
function RunCredit.Empty(title: string): Types.RunSummary
	return {
		title = title,
		wavesCleared = 0,
		bestWave = 0,
		died = false,
		cash = 0,
		materials = {},
		valor = 0,
		kills = 0,
		seconds = 0,
		mentorValor = 0,
		damageShare = 0,
		lines = {},
	}
end

-- One credit on one card: its totals as before L4 W3, and the line of `key` (RunLines.Add). Nothing
-- is negative here (every caller pays whole units of at least 0); `kills` counts on the totals only.
function RunCredit.Credit(
	summary: Types.RunSummary,
	key: Types.RunLineKey,
	cash: number,
	material: string,
	materials: number,
	valor: number,
	kills: number
): ()
	summary.cash += cash
	summary.valor += valor
	summary.kills += kills
	if materials > 0 and material ~= "" then
		summary.materials[material] = (summary.materials[material] or 0) + materials
	end
	RunLines.Add(summary.lines, key, CREDIT_COUNT, cash, material, materials, valor)
end

-- The Mentor bonus is part of `valor` AND shown on its own, so the total, mentorValor and the
-- mentor line move together.
function RunCredit.Mentor(summary: Types.RunSummary, valor: number): ()
	summary.valor += valor
	summary.mentorValor += valor
	RunLines.Add(summary.lines, RunCredit.MentorKey(), CREDIT_COUNT, 0, "", 0, valor)
end

-- The credit keys of contract §4.1, one per source. Names come from config; an empty name is a
-- line whose words are the client's ("Raiders ×112", "First Hard clear", "Mentor").

-- A kill: the run's boss (the body whose death pays the boss's Valor) by its kind, named by the
-- run (else its kind); every other body on the one raiders line.
function RunCredit.KillKey(boss: boolean, kind: string, bossName: string?): Types.RunLineKey
	if boss then
		return { kind = "boss", id = kind, name = bossName or kind }
	end
	return { kind = "raiders", id = "raiders", name = "" }
end

-- A camp's clear bonus, by the camp's id and name (StageFlow.Zone).
function RunCredit.CampKey(id: string, name: string): Types.RunLineKey
	return { kind = "camp", id = id, name = name }
end

-- A difficulty's first-clear reward: one line per level and difficulty (45 bytes at most).
function RunCredit.FirstClearKey(levelId: string, difficulty: string): Types.RunLineKey
	return { kind = "firstClear", id = levelId .. ":" .. difficulty, name = "" }
end

-- A chest's pay, by the secret's id and name (MapRules.Site).
function RunCredit.ChestKey(id: string, name: string): Types.RunLineKey
	return { kind = "chest", id = id, name = name }
end

-- A key a chest gave, named by Expeditions.json `keys` (else its id). The line pays nothing.
function RunCredit.KeyKey(
	key: string,
	keys: { [string]: { name: string, text: string } }?
): Types.RunLineKey
	local def = if keys ~= nil then keys[key] else nil
	local name = if def ~= nil
			and type(def.name) == "string"
			and def.name ~= ""
		then def.name
		else key
	return { kind = "key", id = key, name = name }
end

function RunCredit.MentorKey(): Types.RunLineKey
	return { kind = "mentor", id = "mentor", name = "" }
end

-- L4W3-7: the era a member's run cash is paid at, frozen at ArenaService.Admit: their profile's
-- `era` then, a whole number of at least 1 (anything else reads as the first era, x1).
function RunCredit.EraOf(state: { era: any }?): number
	local era = if state ~= nil then state.era else nil
	if
		type(era) ~= "number"
		or era ~= era
		or era < FIRST_ERA
		or era % 1 ~= 0
		or era == math.huge
	then
		return FIRST_ERA
	end
	return era
end

-- The era a credit pays a member at: the Studio P lever's session override when it is set, else
-- the era frozen at their admit. Never the profile's era now (Advance and Rebirth are hub-only, and
-- a visit's pay never moves under it).
function RunCredit.PayEra(cashEra: number, override: number?): number
	return override or cashEra
end

-- The P lever's next era after `current`: 1 -> 2 -> ... -> `eraCount` -> 1 (with no eras known,
-- always the first).
function RunCredit.NextPayEra(current: number, eraCount: number): number
	local era = RunCredit.EraOf({ era = current })
	if era >= eraCount then
		return FIRST_ERA
	end
	return era + 1
end

return RunCredit
