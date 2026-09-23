--!strict
-- The hub party (docs/INTERFACES.md "C2 contracts" → "Hub party"): invite + accept among players
-- in the same hub server, one leader who picks the mission, and a re-form after the group comes
-- home. Memory only: nothing here is persisted, so a party never outlives the server it formed in.
--
-- Hub only. This module sits in the Services folder the combat place also maps, but only the hub
-- Main calls Init, so in the combat place it connects nothing and holds no state.
--
-- A player who has sent invites but has no accepted member yet holds a one-member party (the
-- "proto" party): that is what carries the pending list the inviter's strip shows. It is not a
-- party for anyone else's rules — `inParty` below needs two members.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))
local RemoteService = require(script.Parent:WaitForChild("RemoteService"))

-- Studio stand-ins (contract: fake members −1…−n named "Fake N", fake leader −9). Local Server
-- test players also have negative ids, so a fake is marked in its party rather than recognised
-- by sign, and a fake id that a real player in the server already has is skipped.
local FAKE_LEADER_ID = -9
local FAKE_NAME_PREFIX = "Fake "

export type Hooks = {
	-- ExpeditionService's in-flight guard: a departing player can be neither invited nor join.
	isBusy: (player: Player) -> boolean,
}

type PendingInvite = { userId: number, name: string, expiresAt: number, seq: number }
type Party = {
	leaderUserId: number,
	-- Join order, leader included; handover goes to the earliest remaining member.
	members: { number },
	names: { [number]: string },
	fakes: { [number]: boolean },
	pending: { [number]: PendingInvite },
}
type ReformGroup = { startedAt: number, arrived: { number }, party: Party? }

local isStudio = RunService:IsStudio()
local hooks: Hooks? = nil
-- Real players only (members and proto leaders). Fakes are never indexed: their ids repeat
-- across players' fake parties.
local partyOf: { [number]: Party } = {}
-- invitee userId → inviting leader's userId → the party the invite is for.
local offers: { [number]: { [number]: Party } } = {}
-- Identical return hints share a key; see OfferReform.
local reformGroups: { [string]: ReformGroup } = {}
local inviteSeq = 0

local function coopConfig(): Types.CombatCoopConfig?
	local combatConfig = Catalog.GetCombatConfig()
	return if combatConfig ~= nil then combatConfig.coop else nil
end

local function sendResult(
	player: Player,
	slotId: string,
	ok: boolean,
	reason: ("invalid" | "full" | "busy" | "expired" | "notLeader")?
): ()
	local result: Types.ActionResult =
		{ action = "party", slotId = slotId, ok = ok, reason = reason }
	RemoteService.FireClient(player, "ActionResult", result)
end

local function realPlayer(userId: number): Player?
	return Players:GetPlayerByUserId(userId)
end

local function isBusy(player: Player): boolean
	local serviceHooks = hooks
	return serviceHooks ~= nil and serviceHooks.isBusy(player)
end

local function pendingCount(party: Party): number
	local count = 0
	for _ in party.pending do
		count += 1
	end
	return count
end

-- In a party for every rule that says "already in a party": a proto party does not count.
local function inParty(userId: number): boolean
	local party = partyOf[userId]
	return party ~= nil and #party.members >= 2
end

local function snapshot(party: Party): Types.HubParty
	local now = os.clock()
	local members: { Types.HubPartyMember } = {
		{ userId = party.leaderUserId, name = party.names[party.leaderUserId] or "" },
	}
	for _, userId in party.members do
		if userId ~= party.leaderUserId then
			table.insert(members, { userId = userId, name = party.names[userId] or "" })
		end
	end
	local invites: { PendingInvite } = {}
	for _, invite in party.pending do
		table.insert(invites, invite)
	end
	table.sort(invites, function(a: PendingInvite, b: PendingInvite): boolean
		return a.seq < b.seq
	end)
	local pending: { Types.HubPartyInvite } = {}
	for _, invite in invites do
		table.insert(pending, {
			userId = invite.userId,
			name = invite.name,
			expiresIn = math.max(0, math.ceil(invite.expiresAt - now)),
		})
	end
	return { leaderUserId = party.leaderUserId, members = members, pending = pending }
end

local function broadcast(party: Party): ()
	local state = snapshot(party)
	for _, userId in party.members do
		local player = realPlayer(userId)
		if player ~= nil and not party.fakes[userId] then
			RemoteService.FireClient(player, "PartyState", state)
		end
	end
end

local function sendNoParty(userId: number): ()
	local player = realPlayer(userId)
	if player ~= nil then
		RemoteService.FireClient(player, "PartyState", nil)
	end
end

local function withdrawInvite(party: Party, inviteeUserId: number): ()
	party.pending[inviteeUserId] = nil
	local byLeader = offers[inviteeUserId]
	if byLeader ~= nil and byLeader[party.leaderUserId] == party then
		byLeader[party.leaderUserId] = nil
		if next(byLeader) == nil then
			offers[inviteeUserId] = nil
		end
	end
end

-- Invites belong to the leader who sent them, so a handover or a dissolve takes them back; the
-- invitee's toast then answers `expired` on a late accept.
local function withdrawAll(party: Party): ()
	local invitees: { number } = {}
	for userId in party.pending do
		table.insert(invitees, userId)
	end
	for _, userId in invitees do
		withdrawInvite(party, userId)
	end
end

local function dissolve(party: Party): ()
	withdrawAll(party)
	for _, userId in party.members do
		if not party.fakes[userId] and partyOf[userId] == party then
			partyOf[userId] = nil
			sendNoParty(userId)
		end
	end
	party.members = {}
end

-- After an invite resolves: a lone leader with nothing pending is no party at all.
local function settle(party: Party): ()
	if #party.members <= 1 and next(party.pending) == nil then
		dissolve(party)
	else
		broadcast(party)
	end
end

local function setLeader(party: Party, userId: number): ()
	if party.leaderUserId == userId then
		return
	end
	withdrawAll(party)
	party.leaderUserId = userId
end

local function removeMember(party: Party, userId: number, notify: boolean): ()
	local index = table.find(party.members, userId)
	if index == nil then
		return
	end
	table.remove(party.members, index)
	local wasFake = party.fakes[userId] == true
	party.fakes[userId] = nil
	if partyOf[userId] == party then
		partyOf[userId] = nil
	end
	-- A fake's id can be a Local Server player's id, who must not be told they left anything.
	if notify and not wasFake then
		sendNoParty(userId)
	end
	-- Contract: a party that drops to one member dissolves, pending invites included.
	if #party.members <= 1 then
		dissolve(party)
		return
	end
	if party.leaderUserId == userId then
		setLeader(party, party.members[1])
	end
	broadcast(party)
end

local function newParty(leaderUserId: number, leaderName: string): Party
	return {
		leaderUserId = leaderUserId,
		members = { leaderUserId },
		names = { [leaderUserId] = leaderName },
		fakes = {},
		pending = {},
	}
end

local function addMember(party: Party, player: Player): ()
	table.insert(party.members, player.UserId)
	party.names[player.UserId] = player.DisplayName
	partyOf[player.UserId] = party
end

-- A player about to take a seat elsewhere gives up everything that points at them: their own
-- proto party and every other invite they hold.
local function clearOwnTies(player: Player, keep: Party?): ()
	local own = partyOf[player.UserId]
	if own ~= nil and own ~= keep and #own.members <= 1 then
		dissolve(own)
	end
	local byLeader = offers[player.UserId]
	if byLeader == nil then
		return
	end
	local others: { Party } = {}
	for _, party in byLeader do
		if party ~= keep then
			table.insert(others, party)
		end
	end
	for _, party in others do
		withdrawInvite(party, player.UserId)
		settle(party)
	end
end

local function addInvite(party: Party, userId: number, name: string, seconds: number): PendingInvite
	inviteSeq += 1
	local invite: PendingInvite =
		{ userId = userId, name = name, expiresAt = os.clock() + seconds, seq = inviteSeq }
	party.pending[userId] = invite
	local byLeader = offers[userId]
	if byLeader == nil then
		byLeader = {}
		offers[userId] = byLeader
	end
	byLeader[party.leaderUserId] = party
	task.delay(seconds, function()
		-- A re-sent invite replaces the record, so only the newest timer may expire it.
		if party.pending[userId] == invite then
			withdrawInvite(party, userId)
			settle(party)
		end
	end)
	return invite
end

local function sendInviteEvent(player: Player, party: Party, seconds: number): ()
	local event: Types.PartyInviteEvent = {
		leaderUserId = party.leaderUserId,
		leaderName = party.names[party.leaderUserId] or "",
		expiresIn = seconds,
	}
	RemoteService.FireClient(player, "PartyInvite", event)
end

local function isUserId(value: any): boolean
	return typeof(value) == "number"
		and value == math.floor(value)
		and value ~= 0
		and math.abs(value) < 2 ^ 53
		and (value > 0 or isStudio)
end

local PartyService = {}

function PartyService.Invite(leader: Player, userId: number): ()
	local slotId = tostring(userId)
	local coop = coopConfig()
	if coop == nil then
		sendResult(leader, slotId, false, "invalid")
		return
	end
	local party = partyOf[leader.UserId]
	if party ~= nil and party.leaderUserId ~= leader.UserId then
		sendResult(leader, slotId, false, "notLeader")
		return
	end
	local target = realPlayer(userId)
	if target == nil or target == leader then
		sendResult(leader, slotId, false, "invalid")
		return
	end
	if party ~= nil and table.find(party.members, userId) ~= nil then
		sendResult(leader, slotId, false, "busy")
		return
	end
	if inParty(userId) or isBusy(target) or isBusy(leader) then
		sendResult(leader, slotId, false, "busy")
		return
	end
	local seconds = coop.inviteSeconds
	-- A re-sent invite restarts its clock; it does not take a second seat.
	local resend = party ~= nil and party.pending[userId] ~= nil
	if not resend then
		local seats = if party ~= nil then #party.members + pendingCount(party) else 1
		if seats >= coop.maxParty then
			sendResult(leader, slotId, false, "full")
			return
		end
	end
	local owned: Party = party or newParty(leader.UserId, leader.DisplayName)
	partyOf[leader.UserId] = owned
	addInvite(owned, userId, target.DisplayName, seconds)
	sendResult(leader, slotId, true, nil)
	sendInviteEvent(target, owned, seconds)
	broadcast(owned)
end

function PartyService.Respond(player: Player, leaderUserId: number, accept: boolean): ()
	local slotId = tostring(leaderUserId)
	local byLeader = offers[player.UserId]
	local party = if byLeader ~= nil then byLeader[leaderUserId] else nil
	local invite = if party ~= nil then party.pending[player.UserId] else nil
	if party == nil or invite == nil then
		if accept then
			sendResult(player, slotId, false, "expired")
		end
		return
	end
	if os.clock() >= invite.expiresAt then
		withdrawInvite(party, player.UserId)
		settle(party)
		if accept then
			sendResult(player, slotId, false, "expired")
		end
		return
	end
	-- A decline needs no reply to the decliner: the leader's strip updating is the answer.
	if not accept then
		withdrawInvite(party, player.UserId)
		settle(party)
		return
	end
	local coop = coopConfig()
	if inParty(player.UserId) or isBusy(player) then
		withdrawInvite(party, player.UserId)
		settle(party)
		sendResult(player, slotId, false, "busy")
		return
	end
	if coop == nil or #party.members >= coop.maxParty then
		withdrawInvite(party, player.UserId)
		settle(party)
		sendResult(player, slotId, false, "full")
		return
	end
	clearOwnTies(player, party)
	withdrawInvite(party, player.UserId)
	addMember(party, player)
	sendResult(player, slotId, true, nil)
	broadcast(party)
end

function PartyService.Leave(player: Player): ()
	local party = partyOf[player.UserId]
	if party == nil then
		return
	end
	if #party.members <= 1 then
		-- A proto party: leaving cancels the invites it was holding.
		dissolve(party)
		return
	end
	removeMember(party, player.UserId, true)
end

function PartyService.Kick(leader: Player, userId: number): ()
	local slotId = tostring(userId)
	local party = partyOf[leader.UserId]
	if party == nil then
		sendResult(leader, slotId, false, "invalid")
		return
	end
	if party.leaderUserId ~= leader.UserId then
		sendResult(leader, slotId, false, "notLeader")
		return
	end
	-- Kick on a pending row withdraws the invite, so the strip needs only one button.
	if party.pending[userId] ~= nil then
		withdrawInvite(party, userId)
		settle(party)
		sendResult(leader, slotId, true, nil)
		return
	end
	if userId == leader.UserId or table.find(party.members, userId) == nil then
		sendResult(leader, slotId, false, "invalid")
		return
	end
	sendResult(leader, slotId, true, nil)
	removeMember(party, userId, true)
end

function PartyService.Get(player: Player): Types.HubParty?
	local party = partyOf[player.UserId]
	return if party ~= nil then snapshot(party) else nil
end

-- Real players in this server only, leader first; a solo player is a party of one.
function PartyService.Members(player: Player): { Player }
	local party = partyOf[player.UserId]
	if party == nil then
		return { player }
	end
	local result: { Player } = {}
	local leader = if party.fakes[party.leaderUserId] then nil else realPlayer(party.leaderUserId)
	if leader ~= nil then
		table.insert(result, leader)
	end
	for _, userId in party.members do
		if userId ~= party.leaderUserId and not party.fakes[userId] then
			local member = realPlayer(userId)
			if member ~= nil then
				table.insert(result, member)
			end
		end
	end
	return result
end

function PartyService.IsLeader(player: Player): boolean
	local party = partyOf[player.UserId]
	return party == nil or party.leaderUserId == player.UserId
end

-- True for a party member id that is a Studio stand-in rather than a player.
function PartyService.IsFake(player: Player, userId: number): boolean
	local party = partyOf[player.UserId]
	return party ~= nil and party.fakes[userId] == true
end

-- The party hint arrives in teleport data, which a client can forge. A forged hint can only
-- ever match hints that agree with it exactly, so the party re-forms only among players whose
-- OWN hints name the same leader and the same members.
function PartyService.OfferReform(player: Player, hint: Types.PartyHint): ()
	local coop = coopConfig()
	if coop == nil or typeof(hint) ~= "table" or not isUserId(hint.leaderUserId) then
		return
	end
	local memberIds = hint.memberIds
	if typeof(memberIds) ~= "table" or #memberIds < 2 or #memberIds > coop.maxParty then
		return
	end
	local sorted: { number } = {}
	for _, userId in memberIds do
		if not isUserId(userId) or table.find(sorted, userId) ~= nil then
			return
		end
		table.insert(sorted, userId)
	end
	if table.find(sorted, player.UserId) == nil then
		return
	end
	if inParty(player.UserId) or isBusy(player) then
		return
	end
	table.sort(sorted)
	local key = `{hint.leaderUserId}|{table.concat(sorted, ",")}`

	local now = os.clock()
	local group = reformGroups[key]
	if group == nil or now - group.startedAt > coop.reformSeconds then
		local fresh: ReformGroup = { startedAt = now, arrived = {}, party = nil }
		group = fresh
		reformGroups[key] = fresh
		task.delay(coop.reformSeconds, function()
			if reformGroups[key] == fresh then
				reformGroups[key] = nil
			end
		end)
	end
	local current = group :: ReformGroup
	if table.find(current.arrived, player.UserId) == nil then
		table.insert(current.arrived, player.UserId)
	end

	-- A later arrival joins the party the earlier ones already re-formed, if it still stands.
	local formed = current.party
	if formed ~= nil and #formed.members >= 2 and partyOf[formed.members[1]] == formed then
		if #formed.members + pendingCount(formed) >= coop.maxParty then
			return
		end
		clearOwnTies(player, nil)
		addMember(formed, player)
		if player.UserId == hint.leaderUserId then
			setLeader(formed, player.UserId)
		end
		broadcast(formed)
		return
	end

	local eligible: { Player } = {}
	for _, userId in current.arrived do
		local arrival = realPlayer(userId)
		if arrival ~= nil and not inParty(userId) and not isBusy(arrival) then
			table.insert(eligible, arrival)
		end
	end
	if #eligible < 2 then
		return
	end
	local leader = eligible[1]
	for _, arrival in eligible do
		if arrival.UserId == hint.leaderUserId then
			leader = arrival
		end
	end
	clearOwnTies(leader, nil)
	local party = newParty(leader.UserId, leader.DisplayName)
	partyOf[leader.UserId] = party
	for _, arrival in eligible do
		if arrival ~= leader then
			clearOwnTies(arrival, nil)
			addMember(party, arrival)
		end
	end
	current.party = party
	broadcast(party)
end

-- PlayerRemoving. Same as Leave, minus the reply, plus every invite the player was holding.
function PartyService.Forget(player: Player): ()
	local userId = player.UserId
	local party = partyOf[userId]
	if party ~= nil then
		if #party.members <= 1 then
			dissolve(party)
		else
			removeMember(party, userId, false)
		end
	end
	local byLeader = offers[userId]
	if byLeader ~= nil then
		local holding: { Party } = {}
		for _, offered in byLeader do
			table.insert(holding, offered)
		end
		for _, offered in holding do
			withdrawInvite(offered, userId)
			settle(offered)
		end
	end
end

-- Studio lever `fakeParty` (RequestDebug and the Workspace attribute): n stand-in members in
-- the caller's own party, 0 removes them. Refused for a member of someone else's party, whose
-- roster is not theirs to pad.
function PartyService.DebugFakeParty(player: Player, count: number): ()
	local coop = coopConfig()
	if not isStudio or coop == nil or count ~= count then
		return
	end
	local party = partyOf[player.UserId]
	if party ~= nil and party.leaderUserId ~= player.UserId then
		warn(`[PartyService] fakeParty: {player.Name} is not the leader; lever ignored`)
		return
	end
	local owned: Party = party or newParty(player.UserId, player.DisplayName)
	partyOf[player.UserId] = owned
	local stale: { number } = {}
	for userId in owned.fakes do
		table.insert(stale, userId)
	end
	for _, userId in stale do
		local index = table.find(owned.members, userId)
		if index ~= nil then
			table.remove(owned.members, index)
		end
		owned.fakes[userId] = nil
	end
	local wanted = math.clamp(math.floor(count), 0, coop.maxParty - 1)
	local candidate = -1
	local added = 0
	while added < wanted and #owned.members + pendingCount(owned) < coop.maxParty do
		if realPlayer(candidate) == nil and table.find(owned.members, candidate) == nil then
			table.insert(owned.members, candidate)
			owned.names[candidate] = FAKE_NAME_PREFIX .. tostring(-candidate)
			owned.fakes[candidate] = true
			added += 1
		end
		candidate -= 1
	end
	warn(`[PartyService] fakeParty lever: {added} Studio-only member(s) for {player.Name}`)
	settle(owned)
end

-- Studio lever `fakeInvite`: an invite from a leader nobody plays, so the toast, its countdown and
-- a fake-led party (where Depart answers notLeader) can be seen solo.
function PartyService.DebugFakeInvite(player: Player): ()
	local coop = coopConfig()
	if not isStudio or coop == nil then
		return
	end
	if inParty(player.UserId) then
		warn(`[PartyService] fakeInvite: {player.Name} is already in a party; lever ignored`)
		return
	end
	local party = newParty(FAKE_LEADER_ID, FAKE_NAME_PREFIX .. tostring(-FAKE_LEADER_ID))
	party.fakes[FAKE_LEADER_ID] = true
	local previous = offers[player.UserId]
	local stale = if previous ~= nil then previous[FAKE_LEADER_ID] else nil
	if stale ~= nil then
		withdrawInvite(stale, player.UserId)
	end
	addInvite(party, player.UserId, player.DisplayName, coop.inviteSeconds)
	sendInviteEvent(player, party, coop.inviteSeconds)
end

function PartyService.Init(serviceHooks: Hooks): ()
	hooks = serviceHooks
	-- Payload shapes are validated by HubRemotes; the casts narrow the varargs. None of these
	-- yield, so each runs on the dispatch thread.
	RemoteService.SetHandler("RequestPartyInvite", function(player: Player, userId: any)
		PartyService.Invite(player, userId :: number)
	end)
	RemoteService.SetHandler(
		"RequestPartyRespond",
		function(player: Player, leaderUserId: any, accept: any)
			PartyService.Respond(player, leaderUserId :: number, accept :: boolean)
		end
	)
	RemoteService.SetHandler("RequestPartyLeave", function(player: Player)
		PartyService.Leave(player)
	end)
	RemoteService.SetHandler("RequestPartyKick", function(player: Player, userId: any)
		PartyService.Kick(player, userId :: number)
	end)
end

function PartyService.Start(): () end

return PartyService
