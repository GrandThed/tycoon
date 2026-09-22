--!strict
-- ProfileStore-backed PlayerState persistence (spec §7, docs/INTERFACES.md "M2 contracts" +
-- "M5 contracts — Hardening"). Internals (session locking, retries, BindToClose flushing) live
-- in ProfileStore; this module exposes LoadAsync/RetryLoadAsync/GetState/SaveAsync/Release,
-- runs the migration mechanism over the schema ProfileSchema owns (C0: shared with the
-- Expeditions place), and owns each player's load status while they sit in safe mode (no
-- profile, no plot, no writes) after a failed load.
-- GetState returns nil until a load completes — all call sites are nil-tolerant by contract.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))
local ProfileSchema = require(script.Parent:WaitForChild("ProfileSchema"))
local RemoteService = require(script.Parent:WaitForChild("RemoteService"))

-- ProfileStore is plain (non-strict) Luau; narrow interfaces below cover the surface we use.
local ProfileStoreModule =
	require(ServerScriptService:WaitForChild("ServerPackages"):WaitForChild("ProfileStore")) :: any

type Connection = { Disconnect: (self: Connection) -> () }
type SessionSignal = { Connect: (self: SessionSignal, listener: () -> ()) -> Connection }
type AfterSaveSignal = {
	Connect: (self: AfterSaveSignal, listener: (saved: Types.PlayerState) -> ()) -> Connection,
}

type Profile = {
	Data: Types.PlayerState,
	OnSessionEnd: SessionSignal,
	OnAfterSave: AfterSaveSignal,
	AddUserId: (self: Profile, userId: number) -> (),
	Reconcile: (self: Profile) -> (),
	Save: (self: Profile) -> (),
	EndSession: (self: Profile) -> (),
	IsActive: (self: Profile) -> boolean,
}

type StartSessionParams = { Cancel: (() -> boolean)? }

type PlayerStore = {
	StartSessionAsync: (self: PlayerStore, key: string, params: StartSessionParams?) -> Profile?,
}

type LoadPhase = "loading" | "failed"

-- The schema itself (version, store name, key prefix, template, migrations) lives in
-- ProfileSchema so the combat place loads byte-identical profiles from the same store.
local SCHEMA_VERSION = ProfileSchema.SCHEMA_VERSION
local STORE_NAME = ProfileSchema.STORE_NAME
local PROFILE_KEY_PREFIX = ProfileSchema.PROFILE_KEY_PREFIX
local PROFILE_TEMPLATE = ProfileSchema.PROFILE_TEMPLATE
local Migrations = ProfileSchema.Migrations
-- Infrastructure retry policy, not game balance (ProfileStore retries the underlying DataStore
-- calls itself; this only re-attempts a thrown StartSessionAsync/Save). Kept in code
-- deliberately — Config/*.json is for gameplay constants.
local LOAD_RETRY_ATTEMPTS = 3
local LOAD_RETRY_BASE_SECONDS = 1
-- Safe mode: how long after a failed load a RequestRetryLoad is honored. Long enough that a
-- modified client cannot turn Retry into a DataStore budget drain; short enough that the
-- common cause (a previous server still finishing its final save) has usually cleared.
local LOAD_RETRY_COOLDOWN_SECONDS = 10
-- Confirmed saves (receipts): how long to wait for OnAfterSave before handing the purchase back
-- to Roblox. A DataStore round-trip is normally well under 2 s; a timeout is NOT retried because
-- the write may still be queued and a second Save() would not make it land sooner.
local SAVE_CONFIRM_TIMEOUT_SECONDS = 10
-- Studio-only playtest lever: a real load failure cannot be forced from Studio (ProfileStore
-- retries throttled DataStore calls internally and never surfaces them), so a boolean attribute
-- on Workspace, toggled live in the Properties pane, stands in for one. Ignored outside Studio.
local FORCE_LOAD_FAILURE_ATTRIBUTE = "ForceLoadFailure"

local playerStore: PlayerStore? = nil
local profiles: { [Player]: Profile } = {}
-- Present exactly while a load is in flight; concurrent LoadAsync callers park here and are
-- resumed with the in-flight result (replaces the M2 busy-wait).
local loadWaiters: { [Player]: { thread } } = {}
local loadAttempts: { [Player]: number } = {}
local loadPhases: { [Player]: LoadPhase } = {}
local lastLoadFailure: { [Player]: number } = {}

-- Unit-style guard exercised on every load: a current-version profile takes zero iterations,
-- and a schema bump without its migration function is a loud warn instead of silent corruption.
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

local function publishLoadStatus(player: Player, phase: LoadPhase, retryAvailableIn: number): ()
	local status: Types.LoadStatus = {
		kind = "loadStatus",
		phase = phase,
		attempt = loadAttempts[player] or 1,
		retryAvailableIn = retryAvailableIn,
	}
	RemoteService.FireClient(player, "StateChanged", status)
end

-- One attempt: session start, left-during-yield guard, reconcile + migrate, session-end hook.
local function attemptLoad(player: Player): Types.PlayerState?
	if RunService:IsStudio() and workspace:GetAttribute(FORCE_LOAD_FAILURE_ATTRIBUTE) == true then
		warn(
			`[DataService] {FORCE_LOAD_FAILURE_ATTRIBUTE} attribute set — simulating a load failure`
				.. ` for {player.Name}`
		)
		return nil
	end
	local profile = startSessionWithRetry(player, PROFILE_KEY_PREFIX .. player.UserId)
	if profile == nil then
		return nil
	end
	if player.Parent == nil then
		-- Player left during the yield: release the session before anyone can reference it.
		profile:EndSession()
		return nil
	end

	profile:AddUserId(player.UserId) -- GDPR right-to-erasure association
	profile:Reconcile() -- fill fields added to the template since this profile was created
	runMigrations(profile.Data, player)

	profiles[player] = profile
	profile.OnSessionEnd:Connect(function()
		-- Fires for our own Release too; profiles[player] is cleared there first, so this
		-- branch only handles an external end. ProfileStore's own BindToClose also ends every
		-- session (possibly before Main's flush runs): that is a shutdown, not a steal, so
		-- leave the entry in place for Main's teardown and do not kick with a false message.
		if profiles[player] ~= profile or (ProfileStoreModule :: any).IsClosing == true then
			return
		end
		profiles[player] = nil
		player:Kick("Your data was loaded on another server — please rejoin.")
	end)
	return profile.Data
end

-- Runs one load attempt, publishes its status, and resumes every parked duplicate caller with
-- the same result. Callers guarantee no load is in flight for this player.
local function runLoad(player: Player): Types.PlayerState?
	loadWaiters[player] = {}
	loadAttempts[player] = (loadAttempts[player] or 0) + 1
	loadPhases[player] = "loading"
	-- Before the yield: the client's boot RequestSnapshot may land at any point of the attempt
	-- and must always be answerable with a status.
	publishLoadStatus(player, "loading", 0)

	local state = attemptLoad(player)

	-- A nil result with the player gone needs no status: nobody is there to read it.
	loadPhases[player] = nil
	if state == nil and player.Parent ~= nil then
		-- Safe mode: the player stays with no state and no writes, sees the card, may retry.
		loadPhases[player] = "failed"
		lastLoadFailure[player] = os.clock()
		publishLoadStatus(player, "failed", LOAD_RETRY_COOLDOWN_SECONDS)
	end

	local waiters = loadWaiters[player]
	loadWaiters[player] = nil
	if waiters ~= nil then
		for _, waiter in waiters do
			task.spawn(waiter, state)
		end
	end
	return state
end

local DataService = {}

-- Yields. Returns nil when the load failed, the session stayed locked, or the player left
-- mid-load (the profile is released internally in that case). On a nil with the player still
-- present the "failed" status has already been published; Main does nothing further.
function DataService.LoadAsync(player: Player): Types.PlayerState?
	local existing = profiles[player]
	if existing ~= nil then
		return existing.Data
	end
	local waiters = loadWaiters[player]
	if waiters ~= nil then
		-- A second orchestration thread for the same player (PlayerAdded + existing-players
		-- sweep overlap): starting a second ProfileStore session on the same key errors, so
		-- park until the in-flight load resumes us with its result.
		table.insert(waiters, coroutine.running())
		local settled: any = coroutine.yield()
		return settled :: Types.PlayerState?
	end
	return runLoad(player)
end

-- Yields. Safe-mode retry behind RequestRetryLoad: refused (nil, no attempt, nothing published)
-- while state is loaded, a load is in flight, or the cooldown since the last failure has not
-- elapsed. Otherwise a fresh attempt with the attempt counter continued.
function DataService.RetryLoadAsync(player: Player): Types.PlayerState?
	if profiles[player] ~= nil or loadWaiters[player] ~= nil then
		return nil
	end
	local failedAt = lastLoadFailure[player]
	if failedAt ~= nil and os.clock() - failedAt < LOAD_RETRY_COOLDOWN_SECONDS then
		return nil
	end
	return runLoad(player)
end

function DataService.IsLoading(player: Player): boolean
	return loadWaiters[player] ~= nil
end

-- nil once state is loaded or when the player never started a load. retryAvailableIn is the
-- live remainder of the cooldown, so a late RequestSnapshot gets an accurate countdown.
function DataService.GetLoadStatus(player: Player): Types.LoadStatus?
	if profiles[player] ~= nil then
		return nil
	end
	-- Optional annotation: map indexing is non-optional under the old solver.
	local phase: LoadPhase? = loadPhases[player]
	if phase == nil then
		return nil
	end
	local retryAvailableIn = 0
	if phase == "failed" then
		local failedAt = lastLoadFailure[player] or 0
		retryAvailableIn =
			math.max(0, math.ceil(LOAD_RETRY_COOLDOWN_SECONDS - (os.clock() - failedAt)))
	end
	local status: Types.LoadStatus = {
		kind = "loadStatus",
		phase = phase,
		attempt = loadAttempts[player] or 1,
		retryAvailableIn = retryAvailableIn,
	}
	return status
end

-- Whether ProfileStore is writing to its in-memory mock (Studio without API access, or no
-- internet). Main uses it to skip the shutdown flush in Studio only when nothing would persist.
-- Reads the field live: ProfileStore probes access asynchronously after require.
function DataService.IsMockMode(): boolean
	return (ProfileStoreModule :: any).DataStoreState ~= "Access"
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
	elseif key == "vipSkins" then
		state.settings.vipSkins = value
	else
		-- Only the remote validator whitelists keys today; a future direct caller must not be
		-- able to write an unknown key into the profile.
		return false
	end
	return true
end

-- Issues one Save() and parks the calling thread until a write lands that satisfies `confirm`,
-- the session ends, or the confirmation timeout elapses. Never polls: the three exits each
-- resume the parked thread exactly once. Returns (confirmed, threw): a thrown Save() is the
-- only outcome the caller may retry.
local function saveAndConfirm(
	player: Player,
	profile: Profile,
	confirm: (saved: Types.PlayerState) -> boolean
): (boolean, boolean)
	local thread = coroutine.running()
	local parked = false
	local outcome: boolean? = nil
	local timedOut = false

	local function settle(result: boolean): ()
		if outcome ~= nil then
			return
		end
		outcome = result
		if parked then
			task.spawn(thread, result)
		end
	end

	-- Connected BEFORE Save() so the write we are about to queue can never be missed. An earlier
	-- autosave landing during the wait only counts if it actually carries the mutation — that
	-- is what the predicate checks.
	local afterSave = profile.OnAfterSave:Connect(function(saved: Types.PlayerState)
		if confirm(saved) then
			settle(true)
		end
	end)
	local sessionEnd = profile.OnSessionEnd:Connect(function()
		settle(false)
	end)
	local timeout = task.delay(SAVE_CONFIRM_TIMEOUT_SECONDS, function()
		timedOut = true
		settle(false)
	end)

	local ok, err = pcall(function()
		profile:Save()
	end)
	if not ok then
		afterSave:Disconnect()
		sessionEnd:Disconnect()
		task.cancel(timeout)
		warn(`[DataService] Save threw for {player.Name}: {err}`)
		return false, true
	end

	-- ProfileStore's write runs on its own thread and yields before any signal fires, but a
	-- settle before the park would otherwise be lost, so check once more before yielding.
	local result: boolean
	if outcome ~= nil then
		result = outcome :: boolean
	else
		parked = true
		local resumed: any = coroutine.yield()
		result = resumed == true
	end

	afterSave:Disconnect()
	sessionEnd:Disconnect()
	if not timedOut then
		task.cancel(timeout)
	end
	if not result then
		warn(
			`[DataService] confirmed save for {player.Name} did not land`
				.. ` ({if timedOut then "timeout" else "session ended"})`
		)
	end
	return result, false
end

-- Explicit profile save. Without `confirm`: ProfileStore's Save queues the write on its own
-- thread and retries the underlying DataStore itself, so `true` means "accepted into an active
-- session", NOT "durably written" — nothing may read the boolean as durability. With `confirm`
-- (the receipt path): `true` means an OnAfterSave fired whose persisted data satisfied the
-- predicate, i.e. the mutation is durably written. `false` (no profile, inactive session, a
-- thrown call after retries, a confirmation timeout, or the session ending mid-wait) makes the
-- receipt caller roll back and return NotProcessedYet so Roblox retries the receipt.
function DataService.SaveAsync(
	player: Player,
	confirm: ((saved: Types.PlayerState) -> boolean)?
): boolean
	local profile = profiles[player]
	if profile == nil then
		warn(`[DataService] SaveAsync with no loaded profile for {player.Name}`)
		return false
	end
	for attempt = 1, LOAD_RETRY_ATTEMPTS do
		if not profile:IsActive() then
			warn(`[DataService] SaveAsync on an inactive session for {player.Name}`)
			return false
		end
		if confirm ~= nil then
			local confirmed, threw = saveAndConfirm(player, profile, confirm)
			if not threw then
				-- A timeout is not retried: the write may still be queued, and a second
				-- Save() cannot make it land sooner. Roblox's receipt retry covers it.
				return confirmed
			end
		else
			local ok, err = pcall(function()
				profile:Save()
			end)
			if ok then
				return true
			end
			warn(`[DataService] Save failed for {player.Name} (attempt {attempt}): {err}`)
		end
		if attempt < LOAD_RETRY_ATTEMPTS then
			task.wait(LOAD_RETRY_BASE_SECONDS * 2 ^ (attempt - 1))
		end
	end
	return false
end

-- Final save + session release. lastSeen/incomeAtSave are already fresh via the tick rule.
-- Idempotent: a released (or never-loaded) player is a no-op, so PlayerRemoving and the
-- shutdown flush may both run it. Also forgets safe-mode bookkeeping for the leaving player.
function DataService.Release(player: Player): ()
	loadAttempts[player] = nil
	loadPhases[player] = nil
	lastLoadFailure[player] = nil
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
