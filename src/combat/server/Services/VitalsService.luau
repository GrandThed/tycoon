--!strict
-- The player's body in the Proving Grounds (docs/INTERFACES.md "P4 contracts": rulings 4-7, 11,
-- 14, 17, 18, 22-24 and 26, "The commit rule" and "Wave 2 — roles"). Until P4 nothing in the
-- range could hurt a player. This is where an enemy's attack meets one: health, regen, dodges,
-- going down and getting up, the `god` switch and the `hurt` effects.
--
-- RangeService owns the players and drives this module (AddPlayer, PrepareCharacter, the set
-- reset, the readout). It hands its i-frame clock over as hooks at Start, so this file never
-- requires it. CrowdService calls the threat hooks set here: `canTarget`, `impact` with every
-- enemy attack at its impact, and `step` once per crowd step.
--
-- The commit rule. An attack's shape is frozen at its impact T, but whether it hits a player is
-- decided at T + lag (ping + shooting.originLagSeconds, capped) against the server's copy of
-- their root at that moment: the copy trails the player's own screen by about that lag, so it
-- is where their screen had them at T. Enemy shapes get no pad, and a position a client claims
-- is never taken. The decisions wait in a queue walked every Heartbeat (Step; the
-- crowd step is too coarse a clock for a dash); nothing here yields. What a frame decides
-- leaves in that frame, as one CombatFx batch per player, so the health bar and the flash move
-- together (ruling 23).
--
-- Wave 2. A lunge, an arc and a line are judged from the queue as above; a lob too, its impact
-- being its landing. A shot and a charge travel: ThreatField sweeps them every crowd step and
-- hands each contact back to be settled here by the same rules (i-frames, `god`, the knock
-- window, down), so one attack never sends one player two effects.
--
-- Stop 2 (the Colossus). A ring travels too (ThreatField). A lob with `count` is a barrage:
-- that many circles thrown at once, each landing as a lob of its own, and one player takes at
-- most one of them. When a boss dies, what it had in the air goes with it (onGone).
--
-- Health is Humanoid.Health. Its maximum is pinned to the range's own body (ruling 17; since L3
-- Armory.json `ladder.rangeHp`, the 130 of the old tier-1 pair), whatever the Studio profile
-- holds: the range's weapon numbers are tier-1 values, and the body they are balanced against
-- must be too. It never reaches 0 here: the hit that would do it puts the player down instead.
--
-- P5 (INTERFACES "P5 contracts", rulings 11, 13 and 18): the same body fights in missions, told
-- so by SetMission. There the maximum is the held tiers' (`maxHpOf`), enemy hits are scaled
-- by the mission (`damageScale`), regen is a share of the bar, a player the mission rules out
-- (`mayJudge`: waiting on the pad) is neither a target nor judged by any shape, and a down never
-- ends by itself: `onDown` is told once, after the frame's batch has left, and the run decides.
-- This module still requires nothing of the mission: everything comes through SetMission.
--
-- L4 W1b (docs/prompts/l4-w1b-fix-round.md F1). A dash's window opens only once the server's ring
-- has seen the dash (DashProof), a few frames after its request. A decision that falls while the
-- player's dash claim is pending, and that the claim's window would cover, is held: the shape's
-- verdict on the root is taken at its moment as always and kept, and only whether an i-frame
-- voids it waits, until the claim is proven (voided, as before L4) or lapses (it lands), never
-- past the lapse. One order every frame: WeaponService's Heartbeat samples the rings and proves
-- the claims, then runs Step here, so a claim proven this frame counts in this frame's decisions.
--
-- G1 (docs/prompts/l4-w1b-fix2.md): a dash that never proves never costs more than not dashing.
-- A held decision keeps the moment it was first due (`hold.at`), and while it waits every later
-- decision of that player waits behind it (`waiting`), so nothing of theirs lands out of turn.
-- On release they are decided in the order they fell due, each as of its own moment: the knock
-- windows (rulings 6 and 18), the down's clock and the regen delay are the ones an unheld
-- decision taken then would have met and left. Only the effect leaves late.
--
-- H1 and H2 (docs/prompts/l4-w1b-fix3.md): HasWaiting tells WaveService that a decision waits, so
-- a stage's clear waits for it rather than dropping a blow that would have landed with no claim;
-- and every decision leaves its list before it is decided, so a throw drops that one alone.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Armory = require(sharedFolder:WaitForChild("Armory"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))
local HitShapes = require(sharedFolder:WaitForChild("HitShapes"))
local Tuning = require(sharedFolder:WaitForChild("Tuning"))

local servicesFolder = script.Parent.Parent:WaitForChild("Services")
local RemoteService = require(servicesFolder:WaitForChild("RemoteService"))
local CrowdBrain = require(script.Parent:WaitForChild("CrowdBrain"))
local CrowdService = require(script.Parent:WaitForChild("CrowdService"))
local ThreatField = require(script.Parent:WaitForChild("ThreatField"))

-- P5: the mission's rules. nil = the range's (P4, unchanged).
export type MissionRules = {
	-- Ruling 13: may enemies target this player, and may their shapes hit them?
	mayJudge: (player: Player) -> boolean,
	-- Ruling 18: called once per down, after the frame's batch has been sent.
	onDown: (player: Player) -> (),
	-- Armory.MaxHp of the player's held tiers; nil = leave the Humanoid's maximum alone.
	maxHpOf: (player: Player) -> number?,
	damageScale: number,
	regenShare: number,
}

-- RangeService's side of the i-frames, both on os.clock().
export type Hooks = {
	-- The player's latest i-frame window and the one before it: (from, until, previous from,
	-- previous until), still readable after they have lapsed.
	iframeWindow: (player: Player) -> (number, number, number, number),
	-- A window of `seconds` from `from` (default now; G1: a released knock's own moment).
	grantIframes: (player: Player, seconds: number, from: number?) -> (),
	-- F1: the player's pending dash claim: the window it opens if the ring proves it, (from,
	-- until), and the last moment it can still be proven; 0, 0, 0 = none (DashProof.Pending).
	dashClaim: (player: Player) -> (number, number, number),
}

type Vitals = {
	player: Player,
	god: boolean,
	-- Since the set was loaded.
	damageTaken: number,
	downs: number,
	-- os.clock() of the last hit that landed; regen waits player.regenDelay from it.
	lastHurtAt: number,
	-- The latest down, [downFrom, downUntil) on os.clock(), kept after the get-up: an impact
	-- that fell inside it may only be raised afterwards. `down` = it is still running.
	down: boolean,
	downFrom: number,
	downUntil: number,
	-- os.clock() until which the last knockback voids every other hit (ruling 18).
	knockUntil: number,
	-- Roblox may add its regen script after CharacterAdded: this watches the character for it.
	watch: RBXScriptConnection?,
	-- G1: the decisions due and not yet released, in the order they fell due. The first waits for
	-- a dash claim; the rest wait behind it.
	waiting: { Pending },
}
-- F1: what the commit rule found at a held decision's moment, kept until it is released.
type Hold = {
	-- G1: os.clock() of the frame it was first due (for what travels, of the step that found it):
	-- its moment, as of which it is judged when released.
	at: number,
	-- The shape held the root (plan and height), and where that root was.
	inShape: boolean,
	position: Vector3,
	-- The body it was judged on: a new character is not hit by what the old one was.
	humanoid: Humanoid,
}
-- One player's test against one frozen strike, waiting for its moment.
type Pending = {
	strike: CrowdBrain.Strike,
	vitals: Vitals,
	-- os.clock() of the decision: the impact plus this player's lag.
	decideAt: number,
	-- Voided already: an i-frame has covered some moment between the impact and the decision,
	-- or a knockback landed while this hit was waiting.
	covered: boolean,
	-- F1 and G1: its moment has come and it waits, for a dash claim that would cover it or behind
	-- an earlier decision of its player's that does.
	hold: Hold?,
	-- G1: os.clock() when it joined the queue. A knock voids what was waiting at its moment only.
	queuedAt: number,
}

-- What a downed player's Humanoid holds. At 0 it would die, and the range has no respawn.
local DOWN_HEALTH = 1
-- Regen lands in steps of this length, so Health replicates ten times a second, not every frame.
local REGEN_STEP_SECONDS = 0.1
-- Roblox's own regen runs from the Script of this name that every character is given.
local REGEN_SCRIPT_NAME = "Health"
local FULL_CIRCLE_DEGREES = 360
local EPSILON = 1e-4

local vitalsByPlayer: { [Player]: Vitals } = {}
local pending: { Pending } = {}
-- Effects raised this frame; they leave at its end as one CombatFx batch per player.
local raised: { Types.CombatFx } = {}
local hooks: Hooks? = nil
local mission: MissionRules? = nil
-- Players who went down since the last flush; their onDown runs after that flush.
local downed: { Player } = {}
local started = false
local regenAccumulator = 0
-- Scratch for the crowd step: who is on their feet, records and all, reused step after step.
local standing: { ThreatField.Standing } = {}

local VitalsService = {}

local function bodyOf(player: Player): (BasePart?, Humanoid?)
	local character = player.Character
	if character == nil or character.Parent == nil then
		return nil, nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if root == nil or not root:IsA("BasePart") or humanoid == nil or humanoid.Health <= 0 then
		return nil, nil
	end
	return root, humanoid
end

-- R15's HipHeight is measured to the root's underside.
local function feetOf(root: BasePart, humanoid: Humanoid): number
	return root.Position.Y - (humanoid.HipHeight + root.Size.Y / 2)
end

-- How far the server's copy of a character trails that player's own screen: the lag, and the
-- ceiling on it, that RangeService excuses on a claimed attack origin and a shot is led by.
local function lagOf(player: Player, shooting: Types.RangeShootingConfig): number
	return Tuning.CommitLag(shooting, player:GetNetworkPing())
end

local function grantIframes(player: Player, seconds: number, from: number?): ()
	local range = hooks
	if range ~= nil then
		range.grantIframes(player, seconds, from)
	end
end

local function raise(fx: Types.CombatFx): ()
	table.insert(raised, fx)
end

-- Ruling 5: Roblox's own regen is off. A disabled script's threads stop. P5: in missions too,
-- where this module's regen is the only healing.
local function silenceRegen(child: Instance): ()
	if child.Name == REGEN_SCRIPT_NAME and child:IsA("Script") then
		child.Enabled = false
	end
end

-- Did the i-frame window [from, untilClock) meet the span [impact, limit]?
local function met(from: number, untilClock: number, impact: number, limit: number): boolean
	return untilClock > math.max(from, impact) and from <= limit
end

-- Did either of the player's last two i-frame windows meet [impact, limit]?
local function shielded(player: Player, impact: number, limit: number): boolean
	local range = hooks
	if range == nil then
		return false
	end
	local from, untilClock, wasFrom, wasUntil = range.iframeWindow(player)
	return met(from, untilClock, impact, limit) or met(wasFrom, wasUntil, impact, limit)
end

-- F1: must a decision on [impact, limit] that is not shielded wait at `now`? Yes while the player's
-- dash claim is pending (up to its lapse) and its window, once proven, would meet that span.
local function awaitsDash(player: Player, impact: number, limit: number, now: number): boolean
	local range = hooks
	if range == nil then
		return false
	end
	local from, untilClock, lapseAt = range.dashClaim(player)
	return now <= lapseAt and met(from, untilClock, impact, limit)
end

-- Is `point` inside the strike's shape, seen from above? The root is tested as a point (enemy
-- shapes get no pad) lowered or raised to the shape's own level: height is the `height` rule's
-- business alone.
local function inPlan(strike: CrowdBrain.Strike, point: Vector3): boolean
	local attack = strike.def
	local shape = attack.shape
	local origin = strike.origin
	local level = Vector3.new(point.X, origin.Y, point.Z)
	local range = math.max(attack.range or 0, 0)
	if shape == "lunge" then
		-- A thrust `width` across, along the locked heading. `range` is how far the hit
		-- reaches from the body centre, so the capsule's round tip ends there.
		local radius = math.max(attack.width or 0, 0) / 2
		local tip = origin + strike.facing * math.max(range - radius, 0)
		return HitShapes.Capsule(origin, tip, radius, 0, level, 0)
	elseif shape == "arc" then
		local arcDegrees = attack.arcDegrees or FULL_CIRCLE_DEGREES
		return HitShapes.Arc(origin, strike.facing, range, arcDegrees, 0, level, 0)
	elseif shape == "line" then
		-- A lane with square ends from the body centre, as far as world geometry let it go.
		local width = math.max(attack.width or 0, 0)
		return HitShapes.Lane(origin, strike.facing, strike.length or range, width, 0, level, 0)
	elseif shape == "lob" then
		local centre = strike.aim
		local radius = math.max(attack.radius or 0, 0)
		if centre == nil then
			return false
		end
		local dx = point.X - centre.X
		local dz = point.Z - centre.Z
		return dx * dx + dz * dz <= radius * radius
	end
	return false
end

-- Where a landed hit sends its victim: a sweep and a ring throw them away from the attacker
-- and a lob away from where it landed; a thrust, a line, a shot and a charge push along
-- themselves.
local function pushOf(strike: CrowdBrain.Strike, point: Vector3): Vector3
	local shape = strike.def.shape
	local centre = if shape == "arc" or shape == "ring"
		then strike.origin
		elseif shape == "lob" then strike.aim
		else nil
	if centre ~= nil then
		local away = Vector3.new(point.X - centre.X, 0, point.Z - centre.Z)
		if away.Magnitude > EPSILON then
			return away.Unit
		end
	end
	return strike.facing
end

-- Ruling 18's "struck and waiting": had `other` struck by the moment `at`, and was it in the queue
-- then (G1)? A contact that travels, or an impact a later step raised, joins the queue after its own
-- impact: a knock decided in between did not void it, so a released one does not either.
local function struckBy(other: Pending, at: number): boolean
	return other.strike.at <= at and other.queuedAt <= at
end

-- One standing player's outcome of one attack, against the root as the server had it at the
-- decision (`position`). `held` = the attack's shape holds them; `voided` = an i-frame met its
-- judging span, or it was decided inside a knockback's window (ruling 18, judged by the caller
-- at the decision's own moment). At most one `hurt` is raised: for a hit, landed or voided, and
-- for a miss the player it was aimed at dodged. Any other miss is silent. Returns what was sent,
-- if anything. `at` is the decision's moment and `now` the frame its effect leaves in: the same
-- unless the decision waited (G1), when everything it starts runs from `at`.
local function rule(
	config: Types.ProvingGroundsConfig,
	vitals: Vitals,
	strike: CrowdBrain.Strike,
	held: boolean,
	voided: boolean,
	position: Vector3,
	humanoid: Humanoid,
	at: number,
	now: number
): ThreatField.Verdict?
	local player = vitals.player
	local attack = strike.def
	-- Ruling 26: a dash carries the player far out of a lunge, so the shape rarely still holds
	-- them when it is judged. A miss by the player the attack was aimed at, under an i-frame,
	-- is their dodge and says so. Walking out is not a dodge, and a bystander dodged nothing.
	if not held and not (voided and strike.targetUserId == player.UserId) then
		return nil
	end

	local fx: Types.CombatFxHurt = {
		kind = "hurt",
		userId = player.UserId,
		amount = 0,
		from = strike.origin,
		enemyKind = strike.enemyKind,
		attack = strike.attack,
	}
	table.insert(raised, fx)
	if not held or voided or vitals.god then
		-- Rulings 7 and 14: a voided hit still says so, so a dash reads as a dodge and `god`
		-- lets the tells be studied. Ruling 18: so does a hit decided inside a knockback's
		-- window, even one whose impact was only noticed after that knockback landed.
		fx.dodged = true
		return "dodged"
	end

	local amount = math.max(attack.damage, 0)
	local rules = mission
	if rules ~= nil and amount > 0 then
		-- Ruling 10: the mission's enemies hit as hard as its era asks, never for nothing.
		amount = math.max(math.round(amount * rules.damageScale), 1)
	end
	local knockback = math.max(attack.knockback or 0, 0)
	local launch = math.max(attack.launch or 0, 0)
	fx.amount = amount
	if knockback > 0 then
		fx.push = pushOf(strike, position) * knockback
	end
	if launch > 0 then
		fx.launch = launch
	end
	vitals.damageTaken += amount
	-- G1: a hit that waited was taken at its moment, so regen waits from there.
	vitals.lastHurtAt = math.max(vitals.lastHurtAt, at)
	if humanoid.Health - amount <= 0 then
		-- Ruling 4: the hit that would empty the bar puts the player down instead.
		humanoid.Health = math.min(DOWN_HEALTH, humanoid.MaxHealth)
		vitals.downs += 1
		vitals.down = true
		vitals.downFrom = at
		fx.down = true
		if rules ~= nil then
			-- P5 ruling 18: no get-up timer. The run decides, after this frame's batch.
			vitals.downUntil = math.huge
			table.insert(downed, player)
		else
			local downSeconds = math.max(config.player.downSeconds, 0)
			vitals.downUntil = at + downSeconds
			-- On server time, from the moment: the effect leaves `now - at` after it.
			fx.upAt = Workspace:GetServerTimeNow() + downSeconds - (now - at)
		end
		return "landed"
	end
	humanoid.Health -= amount
	if knockback > 0 or launch > 0 then
		-- Ruling 6: thrown by one hit, the player cannot be caught by the next while in the air.
		-- G1: the window runs from the decision's moment, as it would have had it not waited.
		local knockIframes = math.max(config.player.knockIframes, 0)
		grantIframes(player, knockIframes, at)
		-- Ruling 18: nor by the ones decided with it. Enemies that wound up in the same step
		-- would otherwise land as one hit, and stay in step for good. Every other hit of theirs
		-- that had struck and was waiting for its decision at this one's moment is voided here (a
		-- lob still in the air has not struck), those waiting behind it (G1) among them;
		-- `knockUntil` voids the ones decided inside its window from then on.
		vitals.knockUntil = at + knockIframes
		for _, other in pending do
			if other.vitals == vitals and struckBy(other, at) then
				other.covered = true
			end
		end
		for _, other in vitals.waiting do
			if struckBy(other, at) then
				other.covered = true
			end
		end
	end
	return "landed"
end

-- P5 ruling 13: in a mission, a player the run rules out (waiting on the pad) is in no shape.
local function judged(player: Player): boolean
	local rules = mission
	return rules == nil or rules.mayJudge(player)
end

-- Was the player down at `impact`? Then the attack is not theirs to take or to dodge (24a).
local function wasDown(vitals: Vitals, impact: number): boolean
	return impact >= vitals.downFrom and impact < vitals.downUntil
end

-- The decision of the commit rule for an instant shape, taken at the pending entry's moment.
-- True when it must wait: a pending dash claim would cover it (F1), or its player has an earlier
-- decision still waiting (G1: it queues behind, so nothing of theirs lands out of turn). The
-- shape's verdict on the root is taken at the first try and kept (`hold`) with that moment, and
-- each later try is judged as of that moment, with the knock state its predecessors left.
local function decide(config: Types.ProvingGroundsConfig, entry: Pending, now: number): boolean
	local vitals = entry.vitals
	local player = vitals.player
	local strike = entry.strike
	-- Gone, or down: a downed player takes no further hits. Down now, or down when it struck
	-- (ruling 24a): an impact that fell just before a get-up is judged after it, and a lob may
	-- land in a down that began after it was thrown.
	if
		vitalsByPlayer[player] ~= vitals
		or vitals.down
		or wasDown(vitals, strike.at)
		or not judged(player)
	then
		return false
	end
	-- A barrage is one attack: a player another of its circles has already answered is done.
	local volley = strike.volley
	if volley ~= nil and volley[player.UserId] then
		return false
	end
	local root, humanoid = bodyOf(player)
	if root == nil or humanoid == nil then
		return false
	end
	local hold = entry.hold
	local position = root.Position
	local held = false
	local at = now
	if hold ~= nil then
		-- The body it was judged on is gone (a respawn while it waited).
		if hold.humanoid ~= humanoid then
			return false
		end
		held, position, at = hold.inShape, hold.position, hold.at
	else
		-- Ruling 11: a jump clears a ground shape; the feet come from the same sample as the plan
		-- test. A line is a wall, not a ground shape: being in the air does not avoid it.
		local attack = strike.def
		local shape = attack.shape
		local height = if shape == "line" then nil else attack.height
		held = inPlan(strike, position)
		if held and height ~= nil then
			-- A lob's floor is the surface under its target, which may be a block's top: a player
			-- on the arena floor beside that block is under the circle, not in it. The other
			-- ground shapes lie on the crowd's floor, and since L1b Wave 4 a region floor ends at
			-- a drop with standable ground below it (R6): a lunge at the lip must not land
			-- through the cliff.
			local above = feetOf(root, humanoid) - strike.floorY
			held = above <= height and above >= -height
		end
	end
	-- Ruling 18: a knockback's window voids what is decided inside it, judged at the decision's
	-- own moment (G1): nothing of the player lands while one of theirs waits, so the knocks that
	-- count are those decided before it, the released ones among them. Kept once found.
	if at < vitals.knockUntil then
		entry.covered = true
	end
	local voided = entry.covered
	if
		(hold == nil and #vitals.waiting > 0)
		or (not voided and awaitsDash(player, strike.at, entry.decideAt, now))
	then
		if hold == nil then
			entry.hold = { at = now, inShape = held, position = position, humanoid = humanoid }
		end
		return true
	end
	local verdict = rule(config, vitals, strike, held, voided, position, humanoid, at, now)
	if volley ~= nil and verdict ~= nil then
		volley[player.UserId] = true
	end
	return false
end

-- The same decision for an attack that travels, asked by ThreatField at the step that saw it:
-- `impactAt` = when the shot or the charging body was where it touched them (their lag ago),
-- or, with `held` false, when it reached the point it was aimed at without touching them.
local function judgeTravelling(
	strike: CrowdBrain.Strike,
	player: Player,
	impactAt: number,
	held: boolean
): ThreatField.Verdict?
	local vitals = vitalsByPlayer[player]
	if vitals == nil or vitals.down or wasDown(vitals, impactAt) or not judged(player) then
		return nil
	end
	local root, humanoid = bodyOf(player)
	if root == nil or humanoid == nil then
		return nil
	end
	local config = Tuning.Get()
	local now = os.clock()
	local limit = math.min(now, impactAt + lagOf(player, config.shooting))
	-- Ruling 18 as in decide.
	local voided = shielded(player, impactAt, limit) or now < vitals.knockUntil
	-- F1: a contact the pending claim would cover is decided in the queue once the claim
	-- resolves, as the strike met them (its `at` is this impact) with what was found now. G1: so
	-- is one that finds an earlier decision of theirs waiting, behind it, as of this moment.
	-- ThreatField hears "dodged": the attack is done with them and a shot flies on, as past a
	-- dodge; if it lands from the queue the shot is not stopped on them (a forged or walled dash
	-- only). A voided contact and an aimed miss land nothing and are answered now: had an aimed
	-- miss waited, the attack would be done with them, and a claim that lapses would have let
	-- them walk through it after.
	if
		held
		and not voided
		and (#vitals.waiting > 0 or awaitsDash(player, impactAt, limit, now))
	then
		local struck = table.clone(strike)
		struck.at = impactAt
		local entry: Pending = {
			strike = struck,
			vitals = vitals,
			decideAt = limit,
			covered = false,
			hold = {
				at = now,
				inShape = held :: boolean,
				position = root.Position,
				humanoid = humanoid,
			},
			queuedAt = now,
		}
		table.insert(vitals.waiting, entry)
		return "dodged"
	end
	return rule(config, vitals, strike, held, voided, root.Position, humanoid, now, now)
end

-- G1: one player's waiting decisions, first to last, each decided as of its own moment until one
-- still waits for a dash claim: it goes back to the front, and those behind it stay. A released
-- knock's window, voids and down are in place before the next is judged, as they would have been
-- at its moment. H2 (docs/prompts/l4-w1b-fix3.md): each is taken out of the list before it is
-- decided, so a throw while deciding one drops that one alone (WeaponService warns once) and
-- never decides again the ones before it.
local function release(config: Types.ProvingGroundsConfig, vitals: Vitals, now: number): ()
	local list = vitals.waiting
	local entry = list[1]
	while entry ~= nil do
		table.remove(list, 1)
		if not entry.covered then
			-- Its whole span is past; asked again now, the windows a proof or a released knock
			-- opened from earlier moments count.
			entry.covered = shielded(vitals.player, entry.strike.at, entry.decideAt)
		end
		if decide(config, entry, now) then
			table.insert(list, 1, entry)
			return
		end
		entry = list[1]
	end
end

-- Walks the queue: first each player's waiting decisions (release), then the queue in order:
-- notes any i-frame that has covered an entry so far, decides the entries whose moment has come
-- and keeps the rest; one that must wait (F1, G1) joins its player's waiting. H2: an entry whose
-- moment has come leaves the queue before anything about it is asked, so a throw drops that one
-- alone; the queue stays whole and in order for the next frame, the ones before it decided once.
local function settle(config: Types.ProvingGroundsConfig, now: number): ()
	for _, vitals in vitalsByPlayer do
		if #vitals.waiting > 0 then
			release(config, vitals, now)
		end
	end
	local index = 1
	local entry = pending[1]
	while entry ~= nil do
		local due = now >= entry.decideAt
		if due then
			table.remove(pending, index)
		else
			index += 1
		end
		if not entry.covered then
			-- Asked every frame, not only at the decision, and of the window before the current
			-- one as well: a dash that covered the impact may have lapsed and been replaced by
			-- then, or even before the step that raised the strike.
			entry.covered =
				shielded(entry.vitals.player, entry.strike.at, math.min(now, entry.decideAt))
		end
		if due and decide(config, entry, now) then
			table.insert(entry.vitals.waiting, entry)
		end
		entry = pending[index]
	end
end

local function getUp(config: Types.ProvingGroundsConfig, vitals: Vitals, now: number): ()
	-- This frame runs a moment after the get-up fell due. The window is cut by that much so it
	-- ends getUpIframes after `upAt`, where every client's shimmer ends.
	local late = now - vitals.downUntil
	vitals.down = false
	vitals.knockUntil = 0
	vitals.lastHurtAt = now
	local _root, humanoid = bodyOf(vitals.player)
	if humanoid ~= nil then
		humanoid.Health = humanoid.MaxHealth
	end
	grantIframes(vitals.player, config.player.getUpIframes - late)
end

-- Health per second: the range's flat rate, or the mission's share of the bar.
local function regenRate(vitals: Vitals, rangeRate: number): number
	local rules = mission
	if rules == nil then
		return math.max(rangeRate, 0)
	end
	local _root, humanoid = bodyOf(vitals.player)
	if humanoid == nil then
		return 0
	end
	return math.max(rules.regenShare, 0) * humanoid.MaxHealth
end

local function regen(vitals: Vitals, amount: number): ()
	local _root, humanoid = bodyOf(vitals.player)
	if humanoid ~= nil and amount > 0 and humanoid.Health < humanoid.MaxHealth then
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + amount)
	end
end

-- One remote call per player, and only in a frame that raised something.
local function flush(): ()
	if #raised > 0 then
		local batch = raised
		raised = {}
		for _, player in Players:GetPlayers() do
			RemoteService.FireClient(player, "CombatFx", batch)
		end
	end
	-- After the batch: the down has reached every client before the run reacts to it.
	if #downed == 0 then
		return
	end
	local list = downed
	downed = {}
	local rules = mission
	if rules == nil then
		return
	end
	for _, player in list do
		local vitals = vitalsByPlayer[player]
		if vitals ~= nil and vitals.down then
			rules.onDown(player)
		end
	end
end

-- F1: one frame of this module (get-ups, regen, the decisions that fell due and their batch),
-- run by WeaponService's Heartbeat right after it has sampled every root and judged every pending
-- dash claim, so a claim proven this frame counts in this frame's decisions. Two handlers on one
-- signal run in no set order.
function VitalsService.Step(deltaTime: number): ()
	local config = Tuning.Get()
	local now = os.clock()
	local body = config.player
	regenAccumulator += deltaTime
	local regenSeconds = 0
	if regenAccumulator >= REGEN_STEP_SECONDS then
		regenSeconds = regenAccumulator
		regenAccumulator = 0
	end
	for _, vitals in vitalsByPlayer do
		if vitals.down then
			if now >= vitals.downUntil then
				getUp(config, vitals, now)
			end
		elseif regenSeconds > 0 and now - vitals.lastHurtAt >= body.regenDelay then
			regen(vitals, regenRate(vitals, body.regenPerSecond) * regenSeconds)
		end
	end
	settle(config, now)
	flush()
end

-- CrowdService threat hooks --------------------------------------------------------------------

local function canTarget(player: Player): boolean
	local vitals = vitalsByPlayer[player]
	return (vitals == nil or not vitals.down) and judged(player)
end

-- A frozen shape waits for each player's decision, at their own lag after its impact.
local function await(strike: CrowdBrain.Strike): ()
	local shooting = Tuning.Get().shooting
	local impact = strike.at
	local queuedAt = os.clock()
	for player, vitals in vitalsByPlayer do
		table.insert(pending, {
			strike = strike,
			vitals = vitals,
			decideAt = impact + lagOf(player, shooting),
			covered = false,
			queuedAt = queuedAt,
		})
	end
end

-- One lob's throw at `centre`, the surface point it lands on: the circle is shown now and
-- lands after its flight. From here on the strike is that landing, the impact the commit rule
-- judges. It no longer needs its lobber, and walls do not stop it. On a block, the circle lies
-- on the block and `height` is measured from there.
local function throw(
	strike: CrowdBrain.Strike,
	centre: Vector3,
	id: number,
	serverOffset: number
): ()
	local attack = strike.def
	local seconds = math.max(attack.seconds or 0, 0)
	strike.aim = centre
	strike.floorY = centre.Y
	table.insert(raised, {
		kind = "area",
		id = id,
		enemyKind = strike.enemyKind,
		enemyId = strike.bodyId,
		center = centre,
		radius = math.max(attack.radius or 0, 0),
		startsAt = strike.at + serverOffset,
		endsAt = strike.at + seconds + serverOffset,
		from = strike.origin,
	})
	strike.at += seconds
	await(strike)
end

-- An enemy attack's impact. A shot, a charge and a ring go to ThreatField, which sweeps them
-- step by step. Every other shape is frozen here and each player gets a decision at their own
-- lag. Nothing is judged now, not even who was down: the root the rule wants is the one the
-- server will hold then.
local function onImpact(strike: CrowdBrain.Strike): ()
	local attack = strike.def
	local shape = attack.shape
	-- Effects carry server time; the strike's clock is os.clock().
	local serverOffset = Workspace:GetServerTimeNow() - os.clock()
	if shape == "shot" then
		local shot = ThreatField.Fire(strike, serverOffset)
		if shot ~= nil then
			table.insert(raised, shot)
		end
	elseif shape == "lane" then
		ThreatField.Charge(strike)
	elseif shape == "ring" then
		ThreatField.Ring(strike)
	elseif shape == "lob" then
		local target = strike.aim or strike.origin
		local count = attack.count or 1
		local first = ThreatField.NextId()
		if count >= 2 then
			-- A barrage: the first circle on the target, the others scattered round them from
			-- the first circle's id. The circles answer each player once between them, the first
			-- circle first: so only that one can be the dodge of the player it was thrown at.
			local volley: { [number]: boolean } = {}
			local spread = math.max(attack.spread or 0, 0)
			local points = HitShapes.Barrage(target, count, spread, first)
			-- Copied before any is thrown: a throw moves its strike on to its landing.
			local circles = table.create(#points, strike)
			for index = 2, #points do
				circles[index] = table.clone(strike)
			end
			local floorY = strike.floorY
			for index, point in points do
				local circle = circles[index]
				circle.volley = volley
				if index == 1 then
					throw(circle, ThreatField.Below(point, floorY), first, serverOffset)
				else
					-- Nobody stood there: it comes down on whatever is highest at that point.
					local centre = ThreatField.Landing(point, floorY)
					throw(circle, centre, ThreatField.NextId(), serverOffset)
				end
			end
		else
			-- It lands on whatever its target stood on: its one ray, straight down from their root.
			throw(strike, ThreatField.Below(target, strike.floorY), first, serverOffset)
		end
	elseif shape == "line" then
		-- Its one ray, cast at the body it locked on: world geometry between the two cuts the
		-- lane short, the block that body stands on does not.
		local range = math.max(attack.range or 0, 0)
		strike.length = ThreatField.Reach(strike.origin, strike.aim, strike.facing, range)
		await(strike)
	elseif shape ~= "summon" then
		-- A summon hurts nobody: CrowdService raises its bodies and never sends it here.
		await(strike)
	end
end

-- The bodies in `ids` are gone for good: a boss has died, and what it summoned went with it.
-- Nothing of theirs lands any more: decisions still waiting (a barrage in the air among them),
-- shots, charges and rings. F1 and G1: a decision in a player's `waiting` stays, its moment came
-- before.
local function onGone(ids: { [number]: boolean }): ()
	local count = #pending
	local kept = 0
	for index = 1, count do
		local entry = pending[index]
		if not ids[entry.strike.bodyId] then
			kept += 1
			pending[kept] = entry
		end
	end
	for index = kept + 1, count do
		pending[index] = nil
	end
	ThreatField.Drop(ids, raise)
end

-- Once per crowd step, after its impacts: the shots and charges under way are swept against
-- everyone on their feet. Costs nothing while none is.
local function onCrowdStep(clock: number): ()
	if not ThreatField.Busy() then
		return
	end
	local shooting = Tuning.Get().shooting
	local count = 0
	for player, vitals in vitalsByPlayer do
		if vitals.down or not judged(player) then
			continue
		end
		local root, humanoid = bodyOf(player)
		if root ~= nil and humanoid ~= nil then
			count += 1
			local who = standing[count]
			if who == nil then
				standing[count] = {
					player = player,
					userId = player.UserId,
					position = root.Position,
					feetY = feetOf(root, humanoid),
					lag = lagOf(player, shooting),
				}
			else
				who.player = player
				who.userId = player.UserId
				who.position = root.Position
				who.feetY = feetOf(root, humanoid)
				who.lag = lagOf(player, shooting)
			end
		end
	end
	for index = #standing, count + 1, -1 do
		standing[index] = nil
	end
	local maxLag = math.max(shooting.originLagMaxSeconds, 0)
	ThreatField.Step(clock, standing, maxLag, judgeTravelling, raise)
end

-- Public -----------------------------------------------------------------------------------------

-- Called by WeaponService.Start, in the range and in missions alike (P5). Idempotent. This module
-- connects no Heartbeat of its own: WeaponService's runs Step (F1).
function VitalsService.Start(rangeHooks: Hooks): ()
	if started then
		return
	end
	started = true
	hooks = rangeHooks
	CrowdService.SetThreatHooks({
		canTarget = canTarget,
		impact = onImpact,
		gone = onGone,
		step = onCrowdStep,
		shotsAlive = ThreatField.ShotsAlive,
	})
end

function VitalsService.AddPlayer(player: Player): ()
	if vitalsByPlayer[player] ~= nil then
		return
	end
	vitalsByPlayer[player] = {
		player = player,
		god = false,
		damageTaken = 0,
		downs = 0,
		lastHurtAt = 0,
		down = false,
		downFrom = 0,
		downUntil = 0,
		knockUntil = 0,
		watch = nil,
		waiting = {},
	}
end

-- Decisions still queued for the player are dropped as they fall due; those waiting (G1) go with
-- the record.
function VitalsService.RemovePlayer(player: Player): ()
	local vitals = vitalsByPlayer[player]
	if vitals == nil then
		return
	end
	if vitals.watch ~= nil then
		vitals.watch:Disconnect()
	end
	vitalsByPlayer[player] = nil
end

-- The maximum this body should have: the mission's gear (nil = leave it), or ruling 17's range
-- body, Armory.json's own `ladder.rangeHp` since L3 (L3-2: the ladder's tier 1 is a mission's 2/2,
-- not the range's). nil also without Armory.json.
local function maxHpFor(player: Player): number?
	local rules = mission
	if rules ~= nil then
		return rules.maxHpOf(player)
	end
	local armoryConfig = Catalog.GetArmoryConfig()
	if armoryConfig == nil then
		return nil
	end
	return Armory.RangeHp(armoryConfig)
end

-- A player's fresh character: its body at full health, Roblox's regen silenced, and whatever the
-- last character was in the middle of over. In the range a respawn also ends a down; in a
-- mission (ruling 18) only the run ends one, so a downed player's new body is down too.
function VitalsService.PrepareCharacter(player: Player, character: Model): ()
	local vitals = vitalsByPlayer[player]
	if vitals == nil then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local stayDown = mission ~= nil and vitals.down
	if humanoid ~= nil then
		local maxHp = maxHpFor(player)
		if maxHp ~= nil then
			humanoid.MaxHealth = maxHp
		end
		humanoid.Health = if stayDown
			then math.min(DOWN_HEALTH, humanoid.MaxHealth)
			else humanoid.MaxHealth
	end
	if vitals.watch ~= nil then
		vitals.watch:Disconnect()
	end
	for _, child in character:GetChildren() do
		silenceRegen(child)
	end
	vitals.watch = character.ChildAdded:Connect(silenceRegen)
	local now = os.clock()
	if vitals.down and not stayDown then
		-- A respawn ends the down early: impacts from here on meet a standing player.
		vitals.down = false
		vitals.downUntil = math.min(vitals.downUntil, now)
	end
	vitals.knockUntil = 0
	vitals.lastHurtAt = now
end

-- P5: the mission's rules from here on (rulings 11, 13 and 18); nil = the range's. WaveService
-- sets them at every run start.
function VitalsService.SetMission(rules: MissionRules?): ()
	mission = rules
	if rules == nil then
		table.clear(downed)
	end
end

-- Ruling 18's stand-in for the Wave 4 revive: the down ends now, the bar fills and the get-up
-- i-frames run, as at a get-up in the range. A player who is not down is just healed in full.
function VitalsService.StandUp(player: Player): ()
	local vitals = vitalsByPlayer[player]
	if vitals == nil then
		return
	end
	local now = os.clock()
	local wasDownNow = vitals.down
	vitals.down = false
	vitals.downUntil = math.min(vitals.downUntil, now)
	vitals.knockUntil = 0
	vitals.lastHurtAt = now
	local _root, humanoid = bodyOf(player)
	if humanoid ~= nil then
		humanoid.Health = humanoid.MaxHealth
	end
	if wasDownNow then
		grantIframes(player, Tuning.Get().player.getUpIframes)
	end
end

-- The tiers changed (an upgrade, a family switch, L3-10 and L3-13, or a Studio lever): the new
-- maximum, keeping the share of the bar the player had. A downed player stays at the down's
-- health.
function VitalsService.RefreshMaxHp(player: Player): ()
	local vitals = vitalsByPlayer[player]
	local _root, humanoid = bodyOf(player)
	local maxHp = maxHpFor(player)
	if vitals == nil or humanoid == nil or maxHp == nil then
		return
	end
	local share = if humanoid.MaxHealth > 0 then humanoid.Health / humanoid.MaxHealth else 1
	humanoid.MaxHealth = maxHp
	humanoid.Health = if vitals.down
		then math.min(DOWN_HEALTH, maxHp)
		else math.clamp(share * maxHp, DOWN_HEALTH, maxHp)
end

-- Down players attack nothing, are no enemy's target and take no hits. Read off the clock, not
-- off the frame that stands them up: the client lets them act at `upAt`, and an attack sent
-- then must not be refused because that frame has not run yet.
function VitalsService.IsDown(player: Player): boolean
	local vitals = vitalsByPlayer[player]
	return vitals ~= nil and vitals.down and os.clock() < vitals.downUntil
end

-- P5 ruling 18, judged from state rather than from the moment of a down: the run is lost when a
-- human is in the fight (not waiting on the pad) and none of them is standing (a live body that
-- is not down). A partner who leaves, dies to a reset or respawns onto the pad after the last
-- down therefore ends it too, with no down of their own to report it.
-- `fieldClear` (the wave's last body is dead, nothing left to spawn): a clear field wins. A blow
-- decided in the frame of the last kill does not lose a wave that was already beaten.
-- Returns the verdict and the userIds of the fighters, who are all fallen when it is true.
function VitalsService.RunLost(
	members: { Types.RunMember },
	fieldClear: boolean?
): (boolean, { number })
	local fighters: { number } = {}
	local anyStanding = false
	for _, member in members do
		local player = member.player
		if member.waiting then
			continue
		end
		table.insert(fighters, member.userId)
		local root = bodyOf(player)
		if root ~= nil and not VitalsService.IsDown(player) then
			anyStanding = true
		end
	end
	return fieldClear ~= true and #fighters > 0 and not anyStanding, fighters
end

-- RunLost reads a human with no living body as fallen, which is right in a run and wrong before
-- one: a character that has not spawned yet would end the run in its first frame. A run may
-- only start once this is true: every member has a living body.
function VitalsService.AllHaveBodies(members: { Types.RunMember }): boolean
	for _, member in members do
		if bodyOf(member.player) == nil then
			return false
		end
	end
	return true
end

-- The `god` range command (ruling 14); Readout carries the setting.
function VitalsService.ToggleGod(player: Player): ()
	local vitals = vitalsByPlayer[player]
	if vitals ~= nil then
		vitals.god = not vitals.god
	end
end

-- The `godMode` mission lever (P5 ruling 25): the same switch, set rather than flipped.
function VitalsService.SetGod(player: Player, on: boolean): ()
	local vitals = vitalsByPlayer[player]
	if vitals ~= nil then
		vitals.god = on
	end
end

-- H1 (docs/prompts/l4-w1b-fix3.md): has the player (nil = anyone) a decision whose moment has
-- come and that still waits (G1)? With no dash claim it would have landed already, so a clear that
-- would drop it (ClearThreats) waits while this is true; it stays true until the claim is proven
-- or lapses, at most the claim's lapse after the request. A pure query.
function VitalsService.HasWaiting(player: Player?): boolean
	if player ~= nil then
		local vitals = vitalsByPlayer[player]
		return vitals ~= nil and #vitals.waiting > 0
	end
	for _, vitals in vitalsByPlayer do
		if #vitals.waiting > 0 then
			return true
		end
	end
	return false
end

-- RangeStats: (damage taken, downs, god). Damage counts every landed hit in full, the one
-- that put the player down included.
function VitalsService.Readout(player: Player): (number, number, boolean)
	local vitals = vitalsByPlayer[player]
	if vitals == nil then
		return 0, 0, false
	end
	return vitals.damageTaken, vitals.downs, vitals.god
end

-- The attacks of enemies that no longer exist land on nobody: queued decisions (lobs in the air
-- among them, and those waiting, G1), shots and charges all go. A run's end and a forced wave
-- call this (P5).
function VitalsService.ClearThreats(): ()
	table.clear(pending)
	for _, vitals in vitalsByPlayer do
		table.clear(vitals.waiting)
	end
	ThreatField.Clear(raise)
end

-- A dummy set was loaded: the counters start over, and the threats go (ClearThreats). A player
-- who is down stays down for the rest of their time.
function VitalsService.OnSetLoaded(): ()
	VitalsService.ClearThreats()
	for _, vitals in vitalsByPlayer do
		vitals.damageTaken = 0
		vitals.downs = 0
	end
end

return VitalsService
