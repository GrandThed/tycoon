--!strict
-- Boot + join orchestration for the Expeditions place (docs/INTERFACES.md "C0 contracts" →
-- "Combat place server"). The same Services folder as the hub is mounted here, so this script
-- requires only DataService and RemoteService from it: PlotService, EconomyService,
-- MonetizationService, LegacyShopService and ArmoryService are hub-only and stay inert.
--
-- The teleport data is a HINT, never an entitlement: every arrival goes through
-- ArenaService.CheckAdmission (C2: the host gate comes from the server-written RunTicket, never
-- from teleport data), and a refusal sends the player straight home with the reason.
--
-- P1: with the DebugProving Workspace attribute true at boot (Studio only), the place boots the
-- Proving Grounds instead: no run, no admission, no waves; RangeService owns every player.
--
-- P5 (docs/INTERFACES.md "P5 contracts" → "Boot sequence"): one mode, decided once by
-- CombatMode. Missions fight with the range's weapons (WeaponService, AbilityService) against
-- the crowd (WaveService); EnemyService and CombatService are no longer booted here, and the
-- four C1 hit intents have no handlers.
--
-- L1 (docs/INTERFACES.md "L1 contracts" → "Flow"): the place boots into a lobby camp. Any
-- admitted party lands there, whatever mission its hub departure named: that id and the Overdrive
-- flag are read as before and used for one thing, the key the hub's ticket is verified against.
-- The party's leader starts a level (RequestStartLevel); every run ends back in the lobby camp;
-- the only way to the city is the player's own Return. A proving build boots the same lobby
-- unless Combat.json debug.provingBoots says "range".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Armory = require(sharedFolder:WaitForChild("Armory"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))
local Combat = require(sharedFolder:WaitForChild("Combat"))
local CombatMode = require(sharedFolder:WaitForChild("CombatMode"))

local servicesFolder = script.Parent:WaitForChild("Services")
local combatFolder = script.Parent:WaitForChild("Combat")

local DataService = require(servicesFolder:WaitForChild("DataService"))
local RemoteService = require(servicesFolder:WaitForChild("RemoteService"))
local StudioBridge = require(servicesFolder:WaitForChild("StudioBridge"))
local CombatRemotes = require(combatFolder:WaitForChild("CombatRemotes"))
local RunRegistry = require(combatFolder:WaitForChild("RunRegistry"))
local ArenaService = require(combatFolder:WaitForChild("ArenaService"))
local WaveService = require(combatFolder:WaitForChild("WaveService"))
local DebugService = require(combatFolder:WaitForChild("DebugService"))
local ReturnService = require(combatFolder:WaitForChild("ReturnService"))
local RangeService = require(combatFolder:WaitForChild("RangeService"))
local WeaponService = require(combatFolder:WaitForChild("WeaponService"))
local AbilityService = require(combatFolder:WaitForChild("AbilityService"))
local CrowdService = require(combatFolder:WaitForChild("CrowdService"))
local VitalsService = require(combatFolder:WaitForChild("VitalsService"))
local LevelService = require(combatFolder:WaitForChild("LevelService"))

type Service = {
	Init: () -> (),
	Start: () -> (),
}

type Loader = (player: Player) -> Types.PlayerState?
-- "arrival" = a fresh join or a safe-mode retry (admission applies); "rejoin" = a player who was
-- a member moments ago and whose trip home failed. Re-running admission on a rejoin could refuse
-- them (`over`: a run is live and they are not on the ticket's expected list; `full`: their seat
-- was taken meanwhile) and bounce them through the failing teleport forever.
type JoinKind = "arrival" | "rejoin"

-- The session key of an arrival that carries no hint at all (Studio, a standalone boot): no
-- mission, so the session is private.
local NO_MISSION = ""
-- The away clock ticks once a second (the Studio levers moved to DebugService in C1).
local TICK_INTERVAL_SECONDS = 1

local tickAccumulator = 0

-- Ruling 5: decided once, before anything else; flipping an attribute mid-session must not turn
-- a live mission into a range.
local mode: Types.CombatMode = CombatMode.Get()
-- A proving build's lobby (L1 ruling 22): the trip home is the Studio bridge's kick, so
-- RequestLeave is ignored there.
local provingLobby = mode == "mission" and CombatMode.IsProving()

-- The combat place sends the same Snapshot shape as the hub so the client model is identical,
-- with the city fields zeroed: there is no plot and no income here. persistedIncomePerSecond is
-- the rate the hub last saved, which is what the Armory readout compares unlock rates against.
local function sendSnapshot(player: Player): ()
	local state = DataService.GetState(player)
	if state == nil then
		-- Safe mode: the client's boot request may land before, during or after the first load
		-- attempt; whichever it is, it must end with a status or a snapshot.
		local status = DataService.GetLoadStatus(player)
		if status ~= nil then
			RemoteService.FireClient(player, "StateChanged", status)
		end
		return
	end
	local armoryConfig = Catalog.GetArmoryConfig()
	local snapshot: Types.Snapshot = {
		kind = "snapshot",
		plotIndex = 0,
		-- Nothing in the dungeon place is tied to an era (L1).
		eraName = "",
		state = state,
		incomePerSecond = 0,
		persistedIncomePerSecond = state.incomeAtSave,
		gearPower = if armoryConfig ~= nil
			then Armory.GearPower(armoryConfig, state.combat.gear, state.combat.ascension)
			else 0,
		welcomeBack = nil,
	}
	RemoteService.FireClient(player, "StateChanged", snapshot)
end

-- Integer and non-zero; negative only in Studio, where Local Server test players have
-- negative ids and a party handoff names one as host.
local function isHostId(value: any): boolean
	if typeof(value) ~= "number" or value ~= math.floor(value) or value == 0 then
		return false
	end
	return value > 0 or RunService:IsStudio()
end

-- The hub's teleport data: { missionId, overdrive, hostUserId }. It never carries the reserved
-- access code (the teleporting client can read teleport data) — the code comes from the
-- server-only MemoryStore hash map that RunRegistry verifies. Wrapped in pcall because
-- GetJoinData throws for a player who has already left.
local function readTeleportHint(player: Player): (string?, boolean, number?)
	local ok, joinData = pcall(function(): any
		return player:GetJoinData()
	end)
	if not ok or typeof(joinData) ~= "table" then
		return nil, false, nil
	end
	local data = (joinData :: any).TeleportData
	if typeof(data) ~= "table" then
		return nil, false, nil
	end
	local missionId = if typeof(data.missionId) == "string" then data.missionId else nil
	local hostUserId = if isHostId(data.hostUserId) then data.hostUserId else nil
	return missionId, data.overdrive == true, hostUserId
end

-- C1: in Studio the hub cannot teleport, so it leaves a handoff record instead (docs/INTERFACES.md
-- "Studio bridge"). The record is consumed once and validated EXACTLY like live teleport data —
-- it is a hint from another session, not an entitlement.
local function readArrival(player: Player): (string?, boolean, number?)
	local ok, hint = pcall(StudioBridge.ReadArrival, player)
	if not ok or typeof(hint) ~= "table" then
		return nil, false, nil
	end
	local data = hint :: any
	local missionId = if typeof(data.missionId) == "string" then data.missionId else nil
	local hostUserId = if isHostId(data.hostUserId) then data.hostUserId else nil
	return missionId, data.overdrive == true, hostUserId
end

-- The hub departure's hint: live teleport data, then the Studio handoff record. With neither
-- (Studio, build/combat.rbxl on its own) there is no mission, no Overdrive, and this player is the
-- host of the session they open. L1 ruling 4: the hint chooses nothing here; it is the key the
-- hub's ticket is verified against (ArenaService.OpenSession).
local function readHint(player: Player): (string, boolean, number)
	local missionId, overdrive, hostUserId = readTeleportHint(player)
	if missionId == nil then
		missionId, overdrive, hostUserId = readArrival(player)
	end
	if missionId == nil then
		return NO_MISSION, false, player.UserId
	end
	return missionId, overdrive, hostUserId or player.UserId
end

-- Shared by the first join (LoadAsync), a safe-mode retry (RetryLoadAsync) and a rejoin after a
-- failed trip home. Yields.
local function runJoinSequence(player: Player, loader: Loader, kind: JoinKind): ()
	local state = loader(player)
	if state == nil then
		-- Load failure, still-locked session, refused retry, or the player left mid-load. No
		-- kick (M5 safe mode): DataService has already published the load status, and the
		-- client's card offers Retry.
		return
	end
	if not player:IsDescendantOf(Players) then
		DataService.Release(player)
		return
	end
	if RangeService.IsActive() then
		-- The range writes nothing to the profile; it is loaded only so the client's boot
		-- sequence (the Snapshot) runs exactly as in a mission.
		RangeService.AddPlayer(player)
		AbilityService.AddPlayer(player)
		sendSnapshot(player)
		return
	end
	Combat.TouchHighestEra(state)

	local missionId, overdrive, hostUserId = readHint(player)
	if Catalog.GetCombatConfig() == nil then
		-- Without Combat.json there is no session to open.
		ReturnService.Refuse(player, "locked")
		return
	end
	-- The first arrival opens the session and reads the hub's ticket; everyone else joins the
	-- session already here. Yields on that MemoryStore read.
	ArenaService.OpenSession(missionId, overdrive, hostUserId, player.Name)
	if not player:IsDescendantOf(Players) then
		-- Left during the ticket read: PlayerRemoving has already run, so undo what it could not.
		ArenaService.ResetIfEmpty()
		DataService.Release(player)
		return
	end
	-- The bypass is only for someone who really was a member of THIS session a moment ago; anyone
	-- else (a refused arrival, or a rejoin into a session that ended meanwhile) is judged afresh.
	if kind == "arrival" or not ArenaService.WasAdmitted(player.UserId) then
		local verdict = ArenaService.CheckAdmission(player, { probe = false })
		if verdict ~= "ok" then
			ReturnService.Refuse(player, verdict)
			return
		end
	end
	-- A down belongs to the run that caused it: a rejoin after a failed trip home still holds its
	-- body record, and must not come back lying down (in a live fight they wait in the lobby camp).
	-- Before the admit, so the first RunState it announces already says so.
	if VitalsService.IsDown(player) then
		VitalsService.StandUp(player)
	end
	-- No yield between the verdict and the admit, so the seat it counted is still free.
	ArenaService.Admit(player)
	-- WeaponService also prepares the character Admit placed (its body record did not exist
	-- then); every later character goes through ArenaService's character hook.
	WeaponService.AddPlayer(player)
	AbilityService.AddPlayer(player)
	sendSnapshot(player)
	-- The map, after the snapshot: this player's own stars, and to everyone, since an arrival
	-- may change who leads.
	WaveService.OnAdmitted(player)
end

-- Configure before Init: RemoteService refuses to create any remote without its definitions.
RemoteService.Configure(CombatRemotes)
WeaponService.Configure(mode)
RangeService.Configure(mode == "range")

-- There is no Delta pipeline in this place (EconomyService is hub-only), so a fresh Snapshot is
-- how a reward flush or a debug grant reaches the client. Main owns the Snapshot shape;
-- WaveService and DebugService reach it through ArenaService.
ArenaService.SetSnapshotSender(sendSnapshot)

-- ReturnService needs the join sequence to re-admit a player whose teleport home failed, and
-- only Main has it; handing it over as a hook keeps the service free of Main's requires.
local returnBoot: Service = {
	Init = function()
		ReturnService.Init({
			-- Not task.spawn'd: the failure path calls this on its own thread and the profile
			-- must be back before it re-admits the player.
			rejoin = function(player: Player)
				runJoinSequence(player, DataService.LoadAsync, "rejoin")
			end,
		})
	end,
	Start = ReturnService.Start,
}

-- WaveService's loop is its Boot, not a Start, so the boot pass gets its own adapter (same shape
-- as returnBoot above).
local waveBoot: Service = {
	Init = WaveService.Init,
	Start = WaveService.Boot,
}

-- L1: the lobby camp, mission mode only (the range builds its own arena through ArenaService).
-- Built in the Init pass, before any service above it reads it, and before any player is in.
local levelBoot: Service = {
	Init = function()
		if mode ~= "mission" then
			return
		end
		LevelService.Init()
		LevelService.BuildLobby()
		ArenaService.SetLobby(LevelService.LobbySpawn())
	end,
	Start = function() end,
}

-- Boot order per contract (L1): data, remotes, registry, arena, the lobby, weapons, range,
-- abilities, the run, debug, return. In mission mode ArenaService builds nothing (the fallback
-- arena is the range's) and LevelService builds the lobby camp; WeaponService starts
-- VitalsService (the body) in both modes; RangeService builds the range arena (range only);
-- AbilityService needs WeaponService's hooks; WaveService wires the run's hooks and the placer
-- (inert in the range).
local orderedServices: { Service } = {
	DataService,
	RemoteService,
	RunRegistry,
	ArenaService,
	levelBoot,
	WeaponService,
	RangeService,
	AbilityService,
	waveBoot,
	DebugService,
	returnBoot,
}

for _, service in orderedServices do
	service.Init()
end

for _, service in orderedServices do
	service.Start()
end

RemoteService.SetHandler("RequestSnapshot", function(player: Player)
	sendSnapshot(player)
	-- The map rides with it: the client listens for MapState from boot but cannot ask for it,
	-- so a client that booted late or reloaded its UI gets its stars here.
	WaveService.SendMap(player)
end)

-- Safe-mode retry. Silent drops here are a courtesy; RetryLoadAsync re-checks the same
-- conditions plus the cooldown, so a modified client gains nothing by skipping the card.
RemoteService.SetHandler("RequestRetryLoad", function(player: Player)
	if DataService.GetState(player) ~= nil or DataService.IsLoading(player) then
		return
	end
	task.spawn(function()
		runJoinSequence(player, DataService.RetryLoadAsync, "arrival")
	end)
end)

-- L1 ruling 7: the leader starts a level. RequestReady has no handler any more (its definition
-- stays in CombatRemotes until L4, and no client sends it). Every check is WaveService's; the
-- range has no run.
RemoteService.SetHandler(
	"RequestStartLevel",
	function(player: Player, levelId: string, difficulty: string)
		if RangeService.IsActive() then
			return
		end
		WaveService.OnStartLevel(player, levelId, difficulty)
	end
)

-- L1 ruling 21: end the live run with what was banked, or cut the summary's wait short.
RemoteService.SetHandler("RequestAbandon", function(player: Player)
	if RangeService.IsActive() then
		return
	end
	WaveService.OnAbandon(player)
end)

-- L1 ruling 22: to the city alone, as before. Ignored from a fighting member of a live run (the
-- client shows Abandon there) and in a proving build, where the trip home is the Studio
-- bridge's kick. Yields (the teleport retries), so it gets its own thread.
RemoteService.SetHandler("RequestLeave", function(player: Player)
	if provingLobby or not WaveService.MayLeave(player) then
		return
	end
	task.spawn(ReturnService.SendHome, player, "leave")
end)

-- P5 ruling 20: RequestAttack, RequestFire, RequestDraw and RequestAbility have no handler any
-- more (their definitions stay in CombatRemotes until L4). Every attack, in the range and in a
-- run, is one of the intents below. WeaponService and AbilityService refuse them outside the
-- five live phases, from a member who waits and from a downed player; tune and command stay
-- RangeService's, inert outside the range and outside Studio.
RemoteService.SetHandler(
	"RequestRangeAttack",
	function(
		player: Player,
		weapon: string,
		seq: number,
		origin: Vector3,
		direction: Vector3,
		ads: boolean,
		charge: number
	)
		WeaponService.OnAttack(player, weapon, seq, origin, direction, ads, charge)
	end
)

RemoteService.SetHandler("RequestRangeDraw", function(player: Player, weapon: string)
	WeaponService.OnDraw(player, weapon)
end)

RemoteService.SetHandler(
	"RequestRangeAbility",
	function(player: Player, slot: string, seq: number, origin: Vector3, direction: Vector3)
		AbilityService.OnCast(player, slot, seq, origin, direction)
	end
)

RemoteService.SetHandler("RequestDash", function(player: Player, direction: Vector3)
	WeaponService.OnDash(player, direction)
end)

RemoteService.SetHandler("RequestSlam", function(player: Player)
	WeaponService.OnSlam(player)
end)

RemoteService.SetHandler(
	"RequestTune",
	function(player: Player, path: string, value: Types.TuneValue)
		RangeService.OnTune(player, path, value)
	end
)

RemoteService.SetHandler(
	"RequestRangeCommand",
	function(player: Player, command: string, argument: string?)
		RangeService.OnCommand(player, command, argument)
	end
)

-- Studio levers, the remote half (the attribute half is DebugService's own 1 Hz poll). The
-- handler itself refuses everything outside Studio.
RemoteService.SetHandler("RequestDebug", function(player: Player, lever: string, value: any)
	DebugService.OnRequest(player, lever, value)
end)

-- The away clock: every second an admitted player spends here is a second the hub pays at
-- Combat.json's expeditionEfficiency when they get back.
local function tickExpeditionSeconds(seconds: number): ()
	for _, player in Players:GetPlayers() do
		if not ArenaService.IsAdmitted(player) then
			continue
		end
		local state = DataService.GetState(player)
		if state == nil then
			continue
		end
		state.combat.expeditionSeconds += seconds
	end
end

RunService.Heartbeat:Connect(function(deltaTime: number)
	tickAccumulator += deltaTime
	local ticks = 0
	while tickAccumulator >= TICK_INTERVAL_SECONDS do
		tickAccumulator -= TICK_INTERVAL_SECONDS
		ticks += 1
	end
	if ticks == 0 then
		return
	end
	tickExpeditionSeconds(ticks * TICK_INTERVAL_SECONDS)
end)

local function onPlayerAdded(player: Player): ()
	task.spawn(function()
		runJoinSequence(player, DataService.LoadAsync, "arrival")
	end)
end

-- Teardown: leave the party (which clears the registry entry with the last member), then the
-- final save. Both steps are idempotent, so PlayerRemoving and the shutdown flush may both run.
local function releasePlayer(player: Player): ()
	AbilityService.RemovePlayer(player)
	RangeService.RemovePlayer(player)
	WeaponService.RemovePlayer(player)
	ArenaService.Remove(player)
	-- A refused first arrival opened a session but was never a member, so Remove did nothing.
	-- Either reset also puts the run machine back in the lobby (ArenaService's reset hook).
	ArenaService.ResetIfEmpty()
	DataService.Release(player)
end

-- A real leave: the trip home is over one way or the other, so its guard goes with it.
local function onPlayerRemoving(player: Player): ()
	ReturnService.Forget(player)
	releasePlayer(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in Players:GetPlayers() do
	-- Studio edge: a player can exist before this script connects. LoadAsync dedupes the rare
	-- overlap with the PlayerAdded connection, and the follow-up steps are idempotent.
	onPlayerAdded(player)
end

-- Shutdown flush, same contract as the hub's: ProfileStore's own BindToClose already blocks
-- shutdown until every final save has landed, so this must not yield.
game:BindToClose(function()
	-- First: registry writes must not yield in the backoff ahead of the final saves. The entry
	-- expires on its TTL, so skipping it costs nothing.
	RunRegistry.MarkClosing()
	if RunService:IsStudio() and DataService.IsMockMode() then
		return
	end
	for _, player in Players:GetPlayers() do
		onPlayerRemoving(player)
	end
end)

-- Ruling 26: the crowd's [Perf] line, Studio only, in both modes.
local combatConfig = Catalog.GetCombatConfig()
if RunService:IsStudio() and combatConfig ~= nil then
	CrowdService.SetPerfLog(combatConfig.debug.perfLogSeconds)
end

-- The levels this build can play, in the map's order (a node with a level file); without a map,
-- in the order of the files.
local function playableLevels(): { string }
	local expeditions = Catalog.GetExpeditionsConfig()
	if expeditions == nil then
		return Catalog.GetLevelIds()
	end
	local ids: { string } = {}
	for _, node in expeditions.nodes do
		local levelId = node.level
		if levelId ~= nil and Catalog.GetLevelFile(levelId) ~= nil then
			table.insert(ids, levelId)
		end
	end
	return ids
end

if RangeService.IsActive() then
	print("[Combat] booted — Proving Grounds (range)")
else
	local line = `[Combat] booted — lobby (levels: {table.concat(playableLevels(), ", ")})`
	if provingLobby and combatConfig ~= nil then
		local debugConfig = combatConfig.debug
		line ..= `; proving: {debugConfig.provingLevel} {debugConfig.provingDifficulty},` .. ` autoStart {debugConfig.provingAutoStart}`
	end
	print(line)
end
