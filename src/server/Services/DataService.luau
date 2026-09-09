--!strict
-- ProfileStore-backed PlayerState persistence (spec §7, docs/INTERFACES.md "M2 contracts").
-- Internals (session locking, retries, BindToClose flushing) live in ProfileStore; this module
-- exposes LoadAsync/GetState/Release and owns the schema template + migration mechanism.
-- GetState returns nil until LoadAsync completes — all call sites are nil-tolerant by contract.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

-- ProfileStore is plain (non-strict) Luau; narrow interfaces below cover the surface we use.
local ProfileStoreModule =
	require(ServerScriptService:WaitForChild("ServerPackages"):WaitForChild("ProfileStore")) :: any

type SessionSignal = { Connect: (self: SessionSignal, listener: () -> ()) -> any }

type Profile = {
	Data: Types.PlayerState,
	OnSessionEnd: SessionSignal,
	AddUserId: (self: Profile, userId: number) -> (),
	Reconcile: (self: Profile) -> (),
	EndSession: (self: Profile) -> (),
	IsActive: (self: Profile) -> boolean,
}

type StartSessionParams = { Cancel: (() -> boolean)? }

type PlayerStore = {
	StartSessionAsync: (self: PlayerStore, key: string, params: StartSessionParams?) -> Profile?,
}

local SCHEMA_VERSION = 1
local STORE_NAME = "PlayerData"
local PROFILE_KEY_PREFIX = "p_"
-- Infrastructure retry policy, not game balance (ProfileStore retries the underlying DataStore
-- calls itself; this only re-attempts a thrown StartSessionAsync). Kept in code deliberately —
-- Config/*.json is for gameplay constants.
local LOAD_RETRY_ATTEMPTS = 3
local LOAD_RETRY_BASE_SECONDS = 1

-- Template = schema v1, the exact PlayerState shape in Types.luau. lastSeen = 0 marks a
-- first-ever join (no offline grant, no welcome-back card).
local PROFILE_TEMPLATE: Types.PlayerState = {
	version = SCHEMA_VERSION,
	cash = 0,
	era = 1,
	rebirthCount = 0,
	legacy = 0,
	slots = {},
	passes = {},
	processedReceipts = {},
	lastSeen = 0,
	incomeAtSave = 0,
	stats = { totalCashAllTime = 0, erasCompleted = 0, playtimeSeconds = 0 },
	settings = { music = true, sfx = true },
}

-- Migrations[n](state) upgrades schema n → n+1; the runner bumps state.version afterwards.
-- Empty at v1 (current) — the mechanism exists so future schema bumps are additive here.
local Migrations: { [number]: (state: Types.PlayerState) -> () } = {}

local playerStore: PlayerStore? = nil
local profiles: { [Player]: Profile } = {}
local loadingPlayers: { [Player]: boolean } = {}

-- Unit-style guard exercised on every load: a v1 profile takes zero iterations (no-op), and a
-- schema bump without its migration function is a loud warn instead of silent corruption.
local function runMigrations(state: Types.PlayerState, player: Player): ()
	while state.version < SCHEMA_VERSION do
		local migrate = Migrations[state.version]
		if migrate == nil then
			warn(
				`[DataService] missing migration v{state.version}→v{state.version + 1}`
					.. ` for {player.Name}; profile left at v{state.version}`
			)
			return
		end
		migrate(state)
		state.version += 1
	end
	if state.version > SCHEMA_VERSION then
		-- A newer server wrote this profile; keep the data untouched and let it play.
		warn(
			`[DataService] profile v{state.version} for {player.Name} is ahead of v{SCHEMA_VERSION}`
		)
	end
end

local function startSessionWithRetry(player: Player, key: string): Profile?
	local store = playerStore
	if store == nil then
		warn(`[DataService] store not initialized; cannot load {player.Name}`)
		return nil
	end
	for attempt = 1, LOAD_RETRY_ATTEMPTS do
		local ok, result = pcall(function(): Profile?
			-- Cancel stops ProfileStore's internal session-acquisition loop once the player is
			-- gone, so a locked profile never keeps a dead join thread burning DataStore budget.
			return store:StartSessionAsync(key, {
				Cancel = function(): boolean
					return player.Parent == nil
				end,
			})
		end)
		if ok then
			-- nil here is terminal by ProfileStore's contract: the load was canceled (player
			-- left) or another server won a same-moment session race — retrying won't help.
			return result :: Profile?
		end
		warn(
			`[DataService] StartSessionAsync failed for {player.Name} (attempt {attempt}): {result}`
		)
		if attempt < LOAD_RETRY_ATTEMPTS then
			task.wait(LOAD_RETRY_BASE_SECONDS * 2 ^ (attempt - 1))
		end
	end
	return nil
end

local DataService = {}

-- Yields. Returns nil when the load failed, the session stayed locked, or the player left
-- mid-load (the profile is released internally in that case). Main decides kick vs stop.
function DataService.LoadAsync(player: Player): Types.PlayerState?
	local existing = profiles[player]
	if existing ~= nil then
		return existing.Data
	end
	if loadingPlayers[player] then
		-- A second orchestration thread for the same player (PlayerAdded + existing-players
		-- sweep overlap): starting a second ProfileStore session on the same key errors, so
		-- wait for the in-flight load instead.
		while loadingPlayers[player] do
			task.wait()
		end
		local settled = profiles[player]
		return if settled ~= nil then settled.Data else nil
	end
	loadingPlayers[player] = true

	local profile = startSessionWithRetry(player, PROFILE_KEY_PREFIX .. player.UserId)
	if profile == nil then
		loadingPlayers[player] = nil
		return nil
	end
	if player.Parent == nil then
		-- Player left during the yield: release the session before anyone can reference it.
		profile:EndSession()
		loadingPlayers[player] = nil
		return nil
	end

	profile:AddUserId(player.UserId) -- GDPR right-to-erasure association
	profile:Reconcile() -- fill fields added to the template since this profile was created
	runMigrations(profile.Data, player)

	profiles[player] = profile
	profile.OnSessionEnd:Connect(function()
		-- Fires for our own Release too; profiles[player] is cleared there first, so this
		-- branch only handles an external end (another server stole the session lock).
		if profiles[player] == profile then
			profiles[player] = nil
			player:Kick("Your data was loaded on another server — please rejoin.")
		end
	end)

	loadingPlayers[player] = nil
	return profile.Data
end

function DataService.GetState(player: Player): Types.PlayerState?
	local profile = profiles[player]
	if profile == nil then
		return nil
	end
	return profile.Data
end

-- M3 settings write behind RequestSetSetting (key/value already validated by RemoteService).
-- Returns false while state isn't loaded so the caller skips the delta mark. The remote
-- handler itself is wired in Main: marking dirty needs EconomyService, which already requires
-- this module, so registering it here would be a require cycle.
function DataService.SetSetting(player: Player, key: Types.SettingKey, value: boolean): boolean
	local state = DataService.GetState(player)
	if state == nil then
		return false
	end
	if key == "music" then
		state.settings.music = value
	elseif key == "sfx" then
		state.settings.sfx = value
	else
		-- Only the remote validator whitelists keys today; a future direct caller must not be
		-- able to write an unknown key into the profile.
		return false
	end
	return true
end

-- Final save + session release. lastSeen/incomeAtSave are already fresh via the tick rule.
function DataService.Release(player: Player): ()
	local profile = profiles[player]
	if profile == nil then
		return
	end
	profiles[player] = nil
	local ok, err = pcall(function()
		profile:EndSession()
	end)
	if not ok then
		warn(`[DataService] EndSession failed for {player.Name}: {err}`)
	end
end

function DataService.Init(): ()
	local store = (ProfileStoreModule :: any).New(STORE_NAME, PROFILE_TEMPLATE) :: PlayerStore
	playerStore = store
	-- ProfileStore retries/queues internally; surface its DataStore errors for spec §11 logging.
	local onError = (ProfileStoreModule :: any).OnError
	onError:Connect(function(message: string, storeName: string, profileKey: string)
		warn(`[DataService] DataStore error (store {storeName}, key {profileKey}): {message}`)
	end)
end

function DataService.Start(): () end

return DataService
