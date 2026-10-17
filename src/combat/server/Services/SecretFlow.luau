--!strict
-- L2 W1 (docs/prompts/l2-w1-contract.md, L2-11 to L2-15): the rules of a level's secrets as
-- chests. Which chests a level has, when a standing root opens one, what opening it means for a
-- player (known, locked, nothing, pay) and the map card's row. A sibling of StageFlow, pure for
-- the same reason: tables, numbers and Vector3 values only, no service, no Instance, no clock,
-- so tools/crowd_harness loads it as it stands and mutate.py mutates it. WaveService tests the
-- roots and UnlockService writes the profile; both only execute what is decided here.
--
-- No secret pays without its key: Decide asks for the key before it looks at the reward, and the
-- key (Unlocks.HasKey) fails closed for anything W1 does not sell.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

-- What a chest pays: whole numbers, flat (no rewardMult, any difficulty); family = a weapon
-- family the player now holds.
export type Reward = { valor: number, materials: number, family: string? }
-- One chest: the layout's `Secret_<id>` block and the level file's entry. x, z = its centre on
-- the flat; floorY = the block's bottom (where a player stands to reach it); reward nil = the
-- entry names it and pays nothing (W1's cache and shrine).
export type Site = {
	id: string,
	needs: string,
	x: number,
	z: number,
	floorY: number,
	name: string,
	reward: Reward?,
}
export type Verdict = "known" | "locked" | "nothing" | "pay"
-- What UnlockService.OpenSecret did: the verdict, and on "pay" what it credited (else 0 / nil).
export type Opening = { verdict: Verdict, valor: number, materials: number, family: string? }
-- The level file's (or the resolved level's) secrets block; LevelFile and LevelConfig both fit.
type SecretsHolder = { secrets: { [string]: Types.LevelSecretConfig }? }

local SecretFlow = {}

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function whole(value: any): number
	return if finite(value) and value >= 0 and value % 1 == 0 then value else 0
end

-- The entry's reward, or nil when it is not a reward entry (none of valor, materials, family).
-- A malformed number pays 0: Validate refuses such a level before it is ever played, so this is
-- only the net.
local function rewardOf(entry: Types.LevelSecretConfig?): Reward?
	if entry == nil or (entry.valor == nil and entry.materials == nil and entry.family == nil) then
		return nil
	end
	local family = entry.family
	return {
		valor = whole(entry.valor),
		materials = whole(entry.materials),
		family = if type(family) == "string" and family ~= "" then family else nil,
	}
end

-- Every chest of a level, in the layout's order. A layout secret whose numbers are missing is
-- skipped (it can never be reached, so it is never shown as reachable either).
function SecretFlow.Sites(layout: Types.LevelLayout, levelFile: SecretsHolder?): { Site }
	local sites: { Site } = {}
	local list: any = layout.secrets
	if type(list) ~= "table" then
		return sites
	end
	local entries = if levelFile ~= nil then levelFile.secrets else nil
	for _, secret: any in list do
		if
			type(secret) ~= "table"
			or type(secret.id) ~= "string"
			or type(secret.needs) ~= "string"
			or not (
				finite(secret.x)
				and finite(secret.y)
				and finite(secret.z)
				and finite(secret.sy)
			)
		then
			continue
		end
		local entry = if entries ~= nil then entries[secret.id] else nil
		local name = if entry ~= nil
				and type(entry.name) == "string"
				and entry.name ~= ""
			then entry.name
			else secret.id
		table.insert(sites, {
			id = secret.id,
			needs = secret.needs,
			x = secret.x,
			z = secret.z,
			floorY = secret.y - secret.sy / 2,
			name = name,
			reward = rewardOf(entry),
		})
	end
	return sites
end

-- True when a root opens the chest: within levels.secretReach of its centre on the flat
-- (closed), and from secretBelow under to secretAbove over its bottom (closed). Rules that are
-- not finite numbers open nothing.
function SecretFlow.Triggered(site: Site, root: Vector3, rules: Types.CombatLevelsConfig): boolean
	local reach, below, above = rules.secretReach, rules.secretBelow, rules.secretAbove
	if not (finite(reach) and finite(below) and finite(above)) then
		return false
	end
	local dx, dz = root.X - site.x, root.Z - site.z
	local rise = root.Y - site.floorY
	return dx * dx + dz * dz <= (reach :: number) * (reach :: number)
		and rise >= -(below :: number)
		and rise <= (above :: number)
end

-- What opening the chest means for one player, in this order: already found = known; no key =
-- locked; no reward entry = nothing; otherwise pay.
function SecretFlow.Decide(site: Site, hasKey: boolean, found: boolean): Verdict
	if found then
		return "known"
	elseif not hasKey then
		return "locked"
	elseif site.reward == nil then
		return "nothing"
	end
	return "pay"
end

-- The map card's row for one player: every chest of the level in order, found from their own
-- profile's `combat.secrets[levelId]`.
function SecretFlow.MapRow(sites: { Site }, found: { [string]: boolean }?): { Types.MapSecretState }
	local row: { Types.MapSecretState } = {}
	for _, site in sites do
		table.insert(row, {
			id = site.id,
			name = site.name,
			needs = site.needs,
			found = found ~= nil and found[site.id] == true,
		})
	end
	return row
end

return SecretFlow
