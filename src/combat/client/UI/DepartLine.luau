--!strict
-- The lobby camp's depart line (docs/prompts/l4-w3-contract.md §3 "Client"). A party that came
-- from the city's map is started into its level by the server once it stands in the lobby:
-- RunState.depart says how far that has got, and this turns it into the HUD's notice line.
--  * `waiting`: "Waiting for your party · 25" (the seconds left of the cap, coop.lobbyWaitSeconds);
--  * `counting`: "Forest Road · Normal starts in 5" (the names are the map's);
--  * `picked`: no line. The host opens the map on that level and difficulty, once per arrival,
--    and the leader departs from it as from any map.
-- The server sends the state at every whole second of either count, so the line shows what the
-- last RunState said and does not count by itself. Nothing here decides anything.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Format = require(sharedFolder:WaitForChild("Format"))

local WORDS = {
	waiting = "Waiting for your party",
	startsIn = " starts in ",
	sep = " · ",
}
local STATES: { [string]: boolean } = { waiting = true, counting = true, picked = true }

local DepartLine = {}

local function seconds(value: any): number?
	if typeof(value) ~= "number" or value ~= value or value < 0 or value >= math.huge then
		return nil
	end
	return value
end

-- RunState.depart off the network: nil unless the level, the difficulty and a known state are
-- there; a count that is not a number is left out.
function DepartLine.Read(raw: any): Types.RunDepart?
	if
		typeof(raw) ~= "table"
		or typeof(raw.levelId) ~= "string"
		or typeof(raw.difficulty) ~= "string"
		or typeof(raw.state) ~= "string"
		or STATES[raw.state] ~= true
	then
		return nil
	end
	-- Checked above against STATES; read through `any` again so the check does not narrow it to a
	-- plain string.
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
function DepartLine.NodeOf(expeditions: Types.ExpeditionsConfig?, levelId: string): Types.MapNode?
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

-- The notice line's words for a depart state; nil = no line (`picked`).
function DepartLine.Text(depart: Types.RunDepart, expeditions: Types.ExpeditionsConfig?): string?
	if depart.state == "waiting" then
		local left = depart.waitIn
		return WORDS.waiting
			.. (if left ~= nil then WORDS.sep .. Format.Cash(math.ceil(left)) else "")
	elseif depart.state == "counting" then
		local node = DepartLine.NodeOf(expeditions, depart.levelId)
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

return DepartLine
