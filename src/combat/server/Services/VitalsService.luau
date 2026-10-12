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
-- is never taken. The decisions wait in a queue this module's Heartbeat walks every frame (the
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
-- Health is Humanoid.Health. Its maximum is pinned to tier-1 weapons in both slots (ruling 17),
-- whatever the Studio profile holds: the range's weapon numbers are tier-1 values, and the body
-- they are balanced against must be too. It never reaches 0 here: the hit that would do it puts
-- the player down instead.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
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

-- RangeService's side of the i-frames, both on os.clock().
export type Hooks = {
	-- The player's latest i-frame window and the one before it: (from, until, previous from,
	-- previous until), still readable after they have lapsed.
	iframeWindow: (player: Player) -> (number, number, number, number),
	grantIframes: (player: Player, seconds: number) -> (),
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

local function grantIframes(player: Player, seconds: number): ()
	local range = hooks
	if range ~= nil then
		range.grantIframes(player, seconds)
	end
end

local function raise(fx: Types.CombatFx): ()
	table.insert(raised, fx)
end

-- Ruling 5: Roblox's own regen is off in the range. A disabled script's threads stop. Mission
-- characters keep theirs: only RangeService sends a character through PrepareCharacter.
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

-- One standing player's outcome of one attack, judged now against the root as the server has
-- it. `held` = the attack's shape holds them; `covered` = an i-frame met its judging span.
-- At most one `hurt` is raised: for a hit, landed or voided, and for a miss the player it was
-- aimed at dodged. Any other miss is silent. Returns what was sent, if anything.
local function rule(
	config: Types.ProvingGroundsConfig,
	vitals: Vitals,
	strike: CrowdBrain.Strike,
	held: boolean,
	covered: boolean,
	root: BasePart,
	humanoid: Humanoid,
	now: number
): ThreatField.Verdict?
	local player = vitals.player
	local attack = strike.def
	-- Ruling 18: a knockback's window voids what is decided inside it.
	local voided = covered or now < vitals.knockUntil
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

	local position = root.Position
	local amount = math.max(attack.damage, 0)
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
	vitals.lastHurtAt = now
	if humanoid.Health - amount <= 0 then
		-- Ruling 4: the hit that would empty the bar puts the player down instead.
		local downSeconds = math.max(config.player.downSeconds, 0)
		humanoid.Health = math.min(DOWN_HEALTH, humanoid.MaxHealth)
		vitals.downs += 1
		vitals.down = true
		vitals.downFrom = now
		vitals.downUntil = now + downSeconds
		fx.down = true
		fx.upAt = Workspace:GetServerTimeNow() + downSeconds
		return "landed"
	end
	humanoid.Health -= amount
	if knockback > 0 or launch > 0 then
		-- Ruling 6: thrown by one hit, the player cannot be caught by the next while in the air.
		local knockIframes = math.max(config.player.knockIframes, 0)
		grantIframes(player, knockIframes)
		-- Ruling 18: nor by the ones decided with it. Enemies that wound up in the same step
		-- would otherwise land as one hit, and stay in step for good. Every other hit of theirs
		-- that has struck and is waiting for its decision is voided here (a lob still in the
		-- air has not struck); `knockUntil` voids the ones not yet raised.
		vitals.knockUntil = now + knockIframes
		for _, other in pending do
			if other.vitals == vitals and other.strike.at <= now then
				other.covered = true
			end
		end
	end
	return "landed"
end

-- Was the player down at `impact`? Then the attack is not theirs to take or to dodge (24a).
local function wasDown(vitals: Vitals, impact: number): boolean
	return impact >= vitals.downFrom and impact < vitals.downUntil
end

-- The decision of the commit rule for an instant shape, taken at the pending entry's moment.
local function decide(config: Types.ProvingGroundsConfig, entry: Pending, now: number): ()
	local vitals = entry.vitals
	local player = vitals.player
	local strike = entry.strike
	-- Gone, or down: a downed player takes no further hits. Down now, or down when it struck
	-- (ruling 24a): an impact that fell just before a get-up is judged after it, and a lob may
	-- land in a down that began after it was thrown.
	if vitalsByPlayer[player] ~= vitals or vitals.down or wasDown(vitals, strike.at) then
		return
	end
	-- A barrage is one attack: a player another of its circles has already answered is done.
	local volley = strike.volley
	if volley ~= nil and volley[player.UserId] then
		return
	end
	local root, humanoid = bodyOf(player)
	if root == nil or humanoid == nil then
		return
	end
	-- Ruling 11: a jump clears a ground shape; the feet come from the same sample as the plan
	-- test. A line is a wall, not a ground shape: being in the air does not avoid it.
	local attack = strike.def
	local shape = attack.shape
	local height = if shape == "line" then nil else attack.height
	local held = inPlan(strike, root.Position)
	if held and height ~= nil then
		-- A lob's floor is the surface under its target, which may be a block's top: a player
		-- on the arena floor beside that block is under the circle, not in it. The other
		-- ground shapes lie on the crowd's floor, where nothing stands below them.
		local above = feetOf(root, humanoid) - strike.floorY
		held = above <= height and (shape ~= "lob" or above >= -height)
	end
	local verdict = rule(config, vitals, strike, held, entry.covered, root, humanoid, now)
	if volley ~= nil and verdict ~= nil then
		volley[player.UserId] = true
	end
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
	if vitals == nil or vitals.down or wasDown(vitals, impactAt) then
		return nil
	end
	local root, humanoid = bodyOf(player)
	if root == nil or humanoid == nil then
		return nil
	end
	local config = Tuning.Get()
	local now = os.clock()
	local limit = math.min(now, impactAt + lagOf(player, config.shooting))
	return rule(
		config,
		vitals,
		strike,
		held,
		shielded(player, impactAt, limit),
		root,
		humanoid,
		now
	)
end

-- Walks the queue: notes any i-frame that has covered an entry so far, decides the entries
-- whose moment has come and keeps the rest, in order.
local function settle(config: Types.ProvingGroundsConfig, now: number): ()
	local count = #pending
	if count == 0 then
		return
	end
	local kept = 0
	for index = 1, count do
		local entry = pending[index]
		if not entry.covered then
			-- Asked every frame, not only at the decision, and of the window before the current
			-- one as well: a dash that covered the impact may have lapsed and been replaced by
			-- then, or even before the step that raised the strike.
			entry.covered =
				shielded(entry.vitals.player, entry.strike.at, math.min(now, entry.decideAt))
		end
		if now >= entry.decideAt then
			decide(config, entry, now)
		else
			kept += 1
			pending[kept] = entry
		end
	end
	for index = kept + 1, count do
		pending[index] = nil
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

local function regen(vitals: Vitals, amount: number): ()
	local _root, humanoid = bodyOf(vitals.player)
	if humanoid ~= nil and amount > 0 and humanoid.Health < humanoid.MaxHealth then
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + amount)
	end
end

-- One remote call per player, and only in a frame that raised something.
local function flush(): ()
	if #raised == 0 then
		return
	end
	local batch = raised
	raised = {}
	for _, player in Players:GetPlayers() do
		RemoteService.FireClient(player, "CombatFx", batch)
	end
end

local function step(deltaTime: number): ()
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
			regen(vitals, math.max(body.regenPerSecond, 0) * regenSeconds)
		end
	end
	settle(config, now)
	flush()
end

-- CrowdService threat hooks --------------------------------------------------------------------

local function canTarget(player: Player): boolean
	local vitals = vitalsByPlayer[player]
	return vitals == nil or not vitals.down
end

-- A frozen shape waits for each player's decision, at their own lag after its impact.
local function await(strike: CrowdBrain.Strike): ()
	local shooting = Tuning.Get().shooting
	local impact = strike.at
	for player, vitals in vitalsByPlayer do
		table.insert(pending, {
			strike = strike,
			vitals = vitals,
			decideAt = impact + lagOf(player, shooting),
			covered = false,
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
-- shots, charges and rings.
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
		if vitals.down then
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

-- Called by RangeService.Start, so only when the range booted. Idempotent.
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
	RunService.Heartbeat:Connect(step)
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
	}
end

-- Decisions still queued for the player are dropped as they fall due.
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

-- A range player's fresh character: the tier-1 body at full health, Roblox's regen silenced,
-- and whatever the last character was in the middle of over. Without Armory.json the Humanoid
-- keeps its own maximum, as in missions.
function VitalsService.PrepareCharacter(player: Player, character: Model): ()
	local vitals = vitalsByPlayer[player]
	if vitals == nil then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local armoryConfig = Catalog.GetArmoryConfig()
	if humanoid ~= nil then
		if armoryConfig ~= nil then
			-- Ruling 17: tier 1 in both slots, no Ascension.
			humanoid.MaxHealth = Armory.MaxHp(
				armoryConfig,
				{ melee = 1, ranged = 1 },
				{ melee = 0, ranged = 0 }
			)
		end
		humanoid.Health = humanoid.MaxHealth
	end
	if vitals.watch ~= nil then
		vitals.watch:Disconnect()
	end
	for _, child in character:GetChildren() do
		silenceRegen(child)
	end
	vitals.watch = character.ChildAdded:Connect(silenceRegen)
	local now = os.clock()
	if vitals.down then
		-- A respawn ends the down early: impacts from here on meet a standing player.
		vitals.down = false
		vitals.downUntil = math.min(vitals.downUntil, now)
	end
	vitals.knockUntil = 0
	vitals.lastHurtAt = now
end

-- Down players attack nothing, are no enemy's target and take no hits. Read off the clock, not
-- off the frame that stands them up: the client lets them act at `upAt`, and an attack sent
-- then must not be refused because that frame has not run yet.
function VitalsService.IsDown(player: Player): boolean
	local vitals = vitalsByPlayer[player]
	return vitals ~= nil and vitals.down and os.clock() < vitals.downUntil
end

-- The `god` range command (ruling 14); Readout carries the setting.
function VitalsService.ToggleGod(player: Player): ()
	local vitals = vitalsByPlayer[player]
	if vitals ~= nil then
		vitals.god = not vitals.god
	end
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

-- A dummy set was loaded: the counters start over, and the attacks of enemies that no longer
-- exist land on nobody: queued decisions (lobs in the air among them), shots and charges all
-- go. A player who is down stays down for the rest of their time.
function VitalsService.OnSetLoaded(): ()
	table.clear(pending)
	ThreatField.Clear(raise)
	for _, vitals in vitalsByPlayer do
		vitals.damageTaken = 0
		vitals.downs = 0
	end
end

return VitalsService
