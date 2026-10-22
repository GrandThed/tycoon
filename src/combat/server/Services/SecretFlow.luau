--!strict
-- L2 W1 (docs/prompts/l2-w1-contract.md, L2-11 to L2-15): the rules of a level's secrets as
-- chests. Which chests a level has, when a standing root opens one, what opening it means for a
-- player (known, locked, nothing, pay), what a pay writes into the profile (Open) and the map
-- card's row. A sibling of StageFlow, pure for the same reason: tables, numbers and Vector3 values
-- only, no service, no Instance, no clock, so tools/crowd_harness loads it as it stands and
-- mutate.py mutates it. WaveService tests the roots and UnlockService hands Open the profile and
-- the key; both only execute what is decided here.
--
-- No secret pays without its key: Decide asks for the key before it looks at the reward, and the
-- key (Unlocks.HasKey) fails closed for anything W1 does not sell.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

-- What a chest pays: whole numbers, flat (no rewardMult, any difficulty); family = a weapon
-- family the player now holds. L4 W2 (docs/prompts/l4-w2-contract.md §0): key = a level key id the
-- chest gives ("castle"). Nothing writes it: the opened secret is the key (Unlocks.HasLevelKey).
export type Reward = { valor: number, materials: number, family: string?, key: string? }
-- One chest: the layout's `Secret_<id>` block and the level file's entry. x, z = its centre on
-- the flat and sx, sz its footprint's sizes (the fix round's s1: the trigger is measured to the
-- footprint, so a big chest opens from beside it); floorY = the block's bottom (where a player
-- stands to reach it); reward nil = the entry names it and pays nothing (W1's cache and shrine).
export type Site = {
	id: string,
	needs: string,
	x: number,
	z: number,
	sx: number,
	sz: number,
	floorY: number,
	name: string,
	reward: Reward?,
}
export type Verdict = "known" | "locked" | "nothing" | "pay"
-- What UnlockService.OpenSecret did: the verdict, and on "pay" what it credited (else 0 / nil),
-- and the key it gave (L4 W2).
export type Opening = {
	verdict: Verdict,
	valor: number,
	materials: number,
	family: string?,
	key: string?,
}
-- L2-36: one shortcut's trigger box, from the layout's `shortcuts`: centre and size, studs.
export type Shortcut = {
	id: string,
	name: string,
	x: number,
	y: number,
	z: number,
	sx: number,
	sy: number,
	sz: number,
}
-- The level file's (or the resolved level's) secrets block; LevelFile and LevelConfig both fit.
type SecretsHolder = { secrets: { [string]: Types.LevelSecretConfig }? }

local SecretFlow = {}

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function whole(value: any): number
	return if finite(value) and value >= 0 and value % 1 == 0 then value else 0
end

-- The entry's reward, or nil when it is not a reward entry (none of valor, materials, family,
-- key: L4 W2, so a key-only chest still pays). A malformed number pays 0: Validate refuses such a
-- level before it is ever played, so this is only the net.
local function rewardOf(entry: Types.LevelSecretConfig?): Reward?
	if
		entry == nil
		or (
			entry.valor == nil
			and entry.materials == nil
			and entry.family == nil
			and entry.key == nil
		)
	then
		return nil
	end
	local family = entry.family
	local key = entry.key
	return {
		valor = whole(entry.valor),
		materials = whole(entry.materials),
		family = if type(family) == "string" and family ~= "" then family else nil,
		key = if type(key) == "string" and key ~= "" then key else nil,
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
				and finite(secret.sx)
				and finite(secret.sy)
				and finite(secret.sz)
				and secret.sx >= 0
				and secret.sz >= 0
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
			sx = secret.sx,
			sz = secret.sz,
			floorY = secret.y - secret.sy / 2,
			name = name,
			reward = rewardOf(entry),
		})
	end
	return sites
end

-- True when a root opens the chest: within levels.secretReach on the flat of its footprint, the
-- axis-aligned sx by sz rectangle round its centre (closed; 0 inside it), and from secretBelow
-- under to secretAbove over its bottom (closed). Rules that are not finite numbers open nothing.
function SecretFlow.Triggered(site: Site, root: Vector3, rules: Types.CombatLevelsConfig): boolean
	local reach, below, above = rules.secretReach, rules.secretBelow, rules.secretAbove
	if not (finite(reach) and finite(below) and finite(above)) then
		return false
	end
	local dx = math.max(math.abs(root.X - site.x) - site.sx / 2, 0)
	local dz = math.max(math.abs(root.Z - site.z) - site.sz / 2, 0)
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

-- The profile's opened secrets of one level, and its families, each made when the profile lacks
-- it (v6 code may have saved one without them).
local function secretsOf(combat: Types.CombatProfile, levelId: string): { [string]: boolean }
	local byLevel = combat.secrets
	if byLevel == nil then
		local made: { [string]: { [string]: boolean } } = {}
		combat.secrets = made
		byLevel = made
	end
	local levels = byLevel :: { [string]: { [string]: boolean } }
	local own = levels[levelId]
	if own == nil then
		local made: { [string]: boolean } = {}
		levels[levelId] = made
		own = made
	end
	return own :: { [string]: boolean }
end

local function familiesOf(combat: Types.CombatProfile): { [string]: boolean }
	local existing = combat.families
	if existing ~= nil then
		return existing
	end
	local made: { [string]: boolean } = {}
	combat.families = made
	return made
end

-- The profile's families, made when it lacks them: the `grantFamily` lever (UnlockService) writes
-- through the same function a chest's pay does.
SecretFlow.FamiliesOf = familiesOf

-- L2-12 (the fix round's s3): one player opens the chest, decided and written in one call with no
-- yield. `hasKey` is Unlocks.HasKey on that player's profile (never the attribute); `material`
-- is the level's ("" = its materials go nowhere and are reported as 0). On "pay" the reward goes
-- into `combat` (Valor, the material, the family) and the secret is recorded, so a second call
-- reads "known"; any other verdict writes nothing. UnlockService only reads the profile and calls
-- this.
function SecretFlow.Open(
	combat: Types.CombatProfile,
	levelId: string,
	site: Site,
	hasKey: boolean,
	material: string
): Opening
	local byLevel = combat.secrets
	local opened = if byLevel ~= nil then byLevel[levelId] else nil
	local verdict = SecretFlow.Decide(site, hasKey, opened ~= nil and opened[site.id] == true)
	local reward = site.reward
	if verdict ~= "pay" or reward == nil then
		return { verdict = verdict :: Verdict, valor = 0, materials = 0, family = nil }
	end
	combat.valor += reward.valor
	local materials = if material ~= "" then reward.materials else 0
	if materials > 0 then
		combat.materials[material] = (combat.materials[material] or 0) + materials
	end
	local family = reward.family
	if family ~= nil then
		familiesOf(combat)[family] = true
	end
	secretsOf(combat, levelId)[site.id] = true
	return {
		verdict = "pay",
		valor = reward.valor,
		materials = materials,
		family = family,
		key = reward.key,
	}
end

-- L2-36: every shortcut of a layout, in its order. An entry whose id is not a string, or whose
-- numbers are not finite (or whose size is negative), is skipped: it can never be found. A
-- missing name reads as the id.
function SecretFlow.Shortcuts(layout: Types.LevelLayout): { Shortcut }
	local found: { Shortcut } = {}
	local list: any = layout.shortcuts
	if type(list) ~= "table" then
		return found
	end
	for _, entry: any in list do
		if
			type(entry) ~= "table"
			or type(entry.id) ~= "string"
			or entry.id == ""
			or not (
				finite(entry.x)
				and finite(entry.y)
				and finite(entry.z)
				and finite(entry.sx)
				and finite(entry.sy)
				and finite(entry.sz)
				and entry.sx >= 0
				and entry.sy >= 0
				and entry.sz >= 0
			)
		then
			continue
		end
		table.insert(found, {
			id = entry.id,
			name = if type(entry.name) == "string" and entry.name ~= ""
				then entry.name
				else entry.id,
			x = entry.x,
			y = entry.y,
			z = entry.z,
			sx = entry.sx,
			sy = entry.sy,
			sz = entry.sz,
		})
	end
	return found
end

-- L2-36: true when a root stands inside the shortcut's box (closed on every face).
function SecretFlow.InShortcut(box: Shortcut, root: Vector3): boolean
	return math.abs(root.X - box.x) <= box.sx / 2
		and math.abs(root.Y - box.y) <= box.sy / 2
		and math.abs(root.Z - box.z) <= box.sz / 2
end

-- L2-36: one player found the shortcut `id` of `levelId`: recorded in their profile's
-- `combat.shortcuts[levelId]` (each made when the profile lacks it). True when it is new; a second
-- call records nothing more and answers false. Pure, no yield, like Open.
function SecretFlow.RecordShortcut(
	combat: Types.CombatProfile,
	levelId: string,
	id: string
): boolean
	local byLevel = combat.shortcuts
	if byLevel == nil then
		local made: { [string]: { [string]: boolean } } = {}
		combat.shortcuts = made
		byLevel = made
	end
	local shortcutsByLevel = byLevel :: { [string]: { [string]: boolean } }
	local mine = shortcutsByLevel[levelId]
	if mine == nil then
		local made: { [string]: boolean } = {}
		shortcutsByLevel[levelId] = made
		mine = made
	end
	local found = mine :: { [string]: boolean }
	if found[id] == true then
		return false
	end
	found[id] = true
	return true
end

-- L2-36: the shortcuts of `levelId` a profile has found, as a set of its own (a find later in the
-- run cannot change a level already built). Empty when there is none.
function SecretFlow.FoundShortcuts(
	combat: Types.CombatProfile?,
	levelId: string
): { [string]: boolean }
	local open: { [string]: boolean } = {}
	local byLevel = if combat ~= nil then combat.shortcuts else nil
	local own = if byLevel ~= nil then byLevel[levelId] else nil
	if type(own) == "table" then
		for id, found in own do
			if found == true then
				open[id] = true
			end
		end
	end
	return open
end

-- The map card's row for one player: every chest of the level in order, found from their own
-- profile's `combat.secrets[levelId]`. L4 W2: a chest that gives a key names it (the key glyph).
function SecretFlow.MapRow(sites: { Site }, found: { [string]: boolean }?): { Types.MapSecretState }
	local row: { Types.MapSecretState } = {}
	for _, site in sites do
		local reward = site.reward
		table.insert(row, {
			id = site.id,
			name = site.name,
			needs = site.needs,
			found = found ~= nil and found[site.id] == true,
			key = if reward ~= nil then reward.key else nil,
		})
	end
	return row
end

return SecretFlow
