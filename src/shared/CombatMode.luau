--!strict
-- What the Expeditions place is this session: the Proving Grounds bench ("range") or a mission
-- (docs/INTERFACES.md "P5 contracts", ruling 5). Decided once and cached: flipping an attribute
-- mid-session must not turn a live mission into a range. Server and client compute it with this
-- one function, so both always agree.
--
-- Not pure (RunService, Workspace) and deliberately not required by CrowdService or
-- VitalsService: the crowd harness loads those two without any of this.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Types = require(script.Parent:WaitForChild("Types"))
local Catalog = require(script.Parent:WaitForChild("Catalog"))
local Tuning = require(script.Parent:WaitForChild("Tuning"))

local RANGE_BOOT = "range"
-- Typed once: the old solver widens a returned literal to `string`.
local RANGE: Types.CombatMode = "range"
local MISSION: Types.CombatMode = "mission"

-- Decided once, both answers together: nil until the first question.
local decided: { proving: boolean, range: boolean }? = nil

local CombatMode = {}

-- Studio only: is the proving switch baked in (tools/proving_project.py), and does it boot the
-- range? Read once, after the first replication on a client, so a Workspace attribute flipped
-- mid-session changes nothing (ruling 5).
local function decide(): { proving: boolean, range: boolean }
	local known = decided
	if known ~= nil then
		return known
	end
	local answer = { proving = false, range = false }
	local cfg = Catalog.GetCombatConfig()
	if RunService:IsStudio() and cfg ~= nil then
		if RunService:IsClient() and not game:IsLoaded() then
			-- Workspace attributes arrive with the first replication; only Studio ever waits here.
			game.Loaded:Wait()
		end
		local debugConfig = cfg.debug
		answer.proving = Workspace:GetAttribute(debugConfig.provingAttribute) == true
		answer.range = answer.proving
			and debugConfig.provingBoots == RANGE_BOOT
			and Tuning.IsAvailable()
	end
	-- A second caller may have decided during the wait: the first answer stands.
	local raced = decided
	if raced ~= nil then
		return raced
	end
	decided = answer
	return answer
end

-- Studio, and the place was built with the proving switch baked in. Yields like Get.
function CombatMode.IsProving(): boolean
	return decide().proving
end

-- Yields once on a Studio client until the game has loaded; never on a server or a live client.
function CombatMode.Get(): Types.CombatMode
	return if decide().range then RANGE else MISSION
end

return CombatMode
