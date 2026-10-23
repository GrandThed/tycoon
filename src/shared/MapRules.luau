--!strict
-- L4 W3 (docs/prompts/l4-w3-contract.md §2.1, L4W3-1): the map's rules, in one module both places
-- read. The hub's Depart and the dungeon's RequestStartLevel ask the same Startable, and both send
-- the same MapState. Moved verbatim from StageFlow (the map section, Stars; rulings 25 and 28 of
-- "L1 contracts") and SecretFlow (the chest list and the map card's row, L2-11 to L2-15; the key
-- of L4 W2 §0), so the hub needs no combat-place module. The W3 fix round added the secret rows
-- both places send (SecretRows, F9) and the pick both maps open on (FirstPick, F13).
--
-- Pure for the same reason they were: tables and numbers only, no service, no Instance, no clock
-- and no yield, so tools/crowd_harness loads it as it stands and mutate.py mutates it. The Types
-- require is for annotations alone.

local Types = require(script.Parent:WaitForChild("Types"))

-- levelId -> difficulty -> cleared
export type Stars = { [string]: { [string]: boolean } }
-- What a chest pays: whole numbers, flat (no rewardMult, any difficulty); family = a weapon
-- family the player now holds. L4 W2 (docs/prompts/l4-w2-contract.md §0): key = a level key id the
-- chest gives ("castle"). Nothing writes it: the opened secret is the key (Unlocks.HasLevelKey).
export type Reward = { valor: number, materials: number, family: string?, key: string? }
-- One chest: the layout's `Secret_<id>` block and the level file's entry. x, z = its centre on
-- the flat and sx, sz its footprint's sizes (the L2 W1 fix round's s1: the trigger is measured to
-- the footprint, so a big chest opens from beside it); floorY = the block's bottom (where a player
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
-- Startable's answer: the reasons are the ActionResult's in both places.
export type StartVerdict = "ok" | "locked" | "unavailable"
-- The level file's (or the resolved level's) secrets block; LevelFile and LevelConfig both fit.
type SecretsHolder = { secrets: { [string]: Types.LevelSecretConfig }? }

local MapRules = {}

-- Structural caps, in bytes (Luau's `#`), with one home here: the hub's RequestExpedition, the
-- dungeon's RequestStartLevel, the Studio bridge's arrival and the Python mirrors all read these.
MapRules.MAX_LEVEL_ID_LENGTH = 32
MapRules.MAX_DIFFICULTY_LENGTH = 12

local function nodeOf(map: Types.ExpeditionsConfig, id: string?): Types.MapNode?
	if id == nil then
		return nil
	end
	for _, node in map.nodes do
		if node.id == id then
			return node
		end
	end
	return nil
end

local function hasStar(stars: Stars, levelId: string?): boolean
	local own = if levelId ~= nil then stars[levelId] else nil
	return own ~= nil and next(own) ~= nil
end

local function starCount(stars: Stars): number
	local count = 0
	for _, difficulties in stars do
		for _ in difficulties do
			count += 1
		end
	end
	return count
end

-- One node for one player (rulings 25 and 28). Whether it is open is the LEADER's doing; the
-- stars shown are the player's own. "notBuilt" wins over every other reason. nil for no such
-- node. L2-15: `secrets` = the player's own secret rows by level id (SecretRow); the node's
-- level's row rides on its state whether it is open or not (nil = none).
function MapRules.NodeState(
	map: Types.ExpeditionsConfig,
	built: { [string]: boolean },
	leader: Stars,
	own: Stars,
	nodeId: string,
	secrets: { [string]: { Types.MapSecretState } }?
): Types.MapNodeState?
	local node = nodeOf(map, nodeId)
	if node == nil then
		return nil
	end
	local levelId = node.level
	local stars: { string } = {}
	local earned = if levelId ~= nil then own[levelId] else nil
	if earned ~= nil then
		for _, difficulty in map.difficulties do
			if earned[difficulty] then
				table.insert(stars, difficulty)
			end
		end
	end
	local state: Types.MapNodeState = {
		id = node.id,
		open = false,
		reason = nil,
		needs = nil,
		stars = stars,
		secrets = if secrets ~= nil and levelId ~= nil then secrets[levelId] else nil,
	}
	if levelId == nil or built[levelId] ~= true then
		state.reason = "notBuilt"
		return state
	end
	local requires = node.requires
	local needsNode = if requires ~= nil then requires.node else nil
	if needsNode ~= nil then
		local required = nodeOf(map, needsNode)
		if not hasStar(leader, if required ~= nil then required.level else nil) then
			state.reason = "needsNode"
			state.needs = if required ~= nil then required.name else needsNode
			return state
		end
	end
	local needsStars = if requires ~= nil then requires.stars else nil
	if needsStars ~= nil and starCount(leader) < needsStars then
		state.reason = "needsStars"
		state.needs = tostring(needsStars)
		return state
	end
	state.open = true
	return state
end

-- Every node, in the config's order, for one player (`secrets`: their rows by level id).
function MapRules.MapState(
	map: Types.ExpeditionsConfig,
	built: { [string]: boolean },
	leader: Stars,
	own: Stars,
	leaderUserId: number,
	secrets: { [string]: { Types.MapSecretState } }?
): Types.MapState
	local nodes: { Types.MapNodeState } = {}
	for _, node in map.nodes do
		local state = MapRules.NodeState(map, built, leader, own, node.id, secrets)
		if state ~= nil then
			table.insert(nodes, state)
		end
	end
	return { kind = "map", leaderUserId = leaderUserId, nodes = nodes }
end

-- The star of one difficulty of one level, for the run that was just cleared at it. True when
-- it is new.
function MapRules.Award(stars: Stars, levelId: string, difficulty: string): boolean
	local own = stars[levelId]
	if own == nil then
		own = {}
		stars[levelId] = own
	end
	if own[difficulty] then
		return false
	end
	own[difficulty] = true
	return true
end

-- Ruling 28: a node is built when a level file with its `level` id exists. `levelIds` is
-- Catalog.GetLevelIds().
function MapRules.Built(levelIds: { string }): { [string]: boolean }
	local built: { [string]: boolean } = {}
	for _, id in levelIds do
		built[id] = true
	end
	return built
end

-- L4W3-1: may the leader start `levelId` at `difficulty`? The node is the first one whose
-- `level` names the level; it must be open for the leader (C2 ruling 4: host-gated, so only the
-- leader's stars count). The difficulty must be one the map ranks and one the level FILE has a
-- table for (`levelDifficulties` = Catalog.GetLevelFile(levelId).difficulties; nil = none).
function MapRules.Startable(
	map: Types.ExpeditionsConfig,
	built: { [string]: boolean },
	leaderStars: Stars,
	levelId: string,
	difficulty: string,
	levelDifficulties: { [string]: any }?
): StartVerdict
	local nodeId: string? = nil
	for _, node in map.nodes do
		if node.level == levelId then
			nodeId = node.id
			break
		end
	end
	local state = if nodeId ~= nil
		then MapRules.NodeState(map, built, leaderStars, leaderStars, nodeId)
		else nil
	if state == nil or not state.open then
		return "locked"
	end
	if table.find(map.difficulties, difficulty) == nil then
		return "unavailable"
	end
	local scales = if levelDifficulties ~= nil then levelDifficulties[difficulty] else nil
	if type(scales) ~= "table" then
		return "unavailable"
	end
	return "ok"
end

-- The pick a session's first MapState opens the map on: the first open node, in config order,
-- that has no star, at its lowest difficulty (nil); failing that the first open node with a
-- difficulty still to clear, at the lowest such, else at its first. nil = no node is open.
-- `difficulties` = the map's, easiest first. The fix round's F13: moved verbatim from MapScreen,
-- so the city's map and the dungeon's open on the same pick by one rule the harness runs.
function MapRules.FirstPick(difficulties: { string }, state: Types.MapState): (string?, string?)
	local fallback: Types.MapNodeState? = nil
	for _, node in state.nodes do
		if typeof(node) == "table" and node.open == true and typeof(node.stars) == "table" then
			if #node.stars == 0 then
				return node.id, nil
			end
			fallback = fallback or node
		end
	end
	if fallback == nil then
		return nil, nil
	end
	for _, difficulty in difficulties do
		if table.find(fallback.stars, difficulty) == nil then
			return fallback.id, difficulty
		end
	end
	return fallback.id, nil
end

-- The chests ----------------------------------------------------------------------------------

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function whole(value: any): number
	return if finite(value) and value >= 0 and value % 1 == 0 then value else 0
end

-- The entry's reward, or nil when it is not a reward entry (none of valor, materials, family,
-- key: L4 W2, so a key-only chest still pays). A malformed number pays 0: StageFlow.Validate
-- refuses such a level before it is ever played, so this is only the net.
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
function MapRules.Sites(layout: Types.LevelLayout, levelFile: SecretsHolder?): { Site }
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

-- The map card's row for one player: every chest of the level in order, found from their own
-- profile's `combat.secrets[levelId]`. L4 W2: a chest that gives a key names it (the key glyph).
function MapRules.SecretRow(
	sites: { Site },
	found: { [string]: boolean }?
): { Types.MapSecretState }
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

-- The fix round's F9: every built level's row for one player, by level id, the one copy the hub's
-- SendMap and the dungeon's map both send. `sitesOf` is the caller's cached reader (Sites of the
-- level's files, behind its own pcall and warn, because only the caller reads Catalog); it must
-- not throw or yield. `opened` = the player's profile `combat.secrets`. A level with no chests
-- carries no row.
function MapRules.SecretRows(
	built: { [string]: boolean },
	sitesOf: (levelId: string) -> { Site },
	opened: { [string]: { [string]: boolean } }?
): { [string]: { Types.MapSecretState } }
	local rows: { [string]: { Types.MapSecretState } } = {}
	for levelId in built do
		local sites = sitesOf(levelId)
		if #sites > 0 then
			rows[levelId] =
				MapRules.SecretRow(sites, if opened ~= nil then opened[levelId] else nil)
		end
	end
	return rows
end

return MapRules
