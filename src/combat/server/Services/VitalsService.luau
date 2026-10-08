--!strict
-- The player's body in the Proving Grounds (docs/INTERFACES.md "P4 contracts": rulings 4-7, 11,
-- 14, 17, 18, 22-24 and 26, and "The commit rule"). Until P4 nothing in the range could hurt a
-- player. This is where an enemy's attack meets one: health, regen, dodges, going down and
-- getting up, the `god` switch and the `hurt` effects.
--
-- RangeService owns the players and drives this module (AddPlayer, PrepareCharacter, the set
-- reset, the readout). It hands its i-frame clock over as hooks at Start, so this file never
-- requires it. CrowdService calls the threat hooks set here: `canTarget`, and `impact` with
-- every enemy attack's frozen shape.
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

-- How far the server's copy of a character trails that player's own screen: the lag, and the
-- ceiling on it, that RangeService excuses on a claimed attack origin.
local function lagOf(player: Player, shooting: Types.RangeShootingConfig): number
	local ping = player:GetNetworkPing()
	-- A NaN ping fails every comparison, math.max included.
	ping = if ping == ping then math.max(ping, 0) else 0
	return math.min(
		ping + math.max(shooting.originLagSeconds, 0),
		math.max(shooting.originLagMaxSeconds, 0)
	)
end

local function grantIframes(player: Player, seconds: number): ()
	local range = hooks
	if range ~= nil then
		range.grantIframes(player, seconds)
	end
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

-- Is `point` inside the strike's shape, seen from above? The root is tested as a point (enemy
-- shapes get no pad) lowered or raised to the shape's own level: height is the `height` rule's
-- business alone.
local function inPlan(strike: CrowdBrain.Strike, point: Vector3): boolean
	local attack = strike.def
	local origin = strike.origin
	local level = Vector3.new(point.X, origin.Y, point.Z)
	local range = math.max(attack.range or 0, 0)
	if attack.shape == "lunge" then
		-- A thrust `width` across, along the locked heading. `range` is how far the hit
		-- reaches from the body centre, so the capsule's round tip ends there.
		local radius = math.max(attack.width or 0, 0) / 2
		local tip = origin + strike.facing * math.max(range - radius, 0)
		return HitShapes.Capsule(origin, tip, radius, 0, level, 0)
	elseif attack.shape == "arc" then
		local arcDegrees = attack.arcDegrees or FULL_CIRCLE_DEGREES
		return HitShapes.Arc(origin, strike.facing, range, arcDegrees, 0, level, 0)
	end
	return false
end

-- Where a landed hit sends its victim: a sweep throws them away from the attacker, a thrust
-- along itself.
local function pushOf(strike: CrowdBrain.Strike, point: Vector3): Vector3
	if strike.def.shape == "arc" then
		local away = Vector3.new(point.X - strike.origin.X, 0, point.Z - strike.origin.Z)
		if away.Magnitude > EPSILON then
			return away.Unit
		end
	end
	return strike.facing
end

-- The decision of the commit rule, taken at the pending entry's moment against the root as the
-- server has it now. It raises at most one `hurt`: for a hit, landed or voided, and for a miss
-- the player it was aimed at dodged. Any other miss is silent.
local function decide(config: Types.ProvingGroundsConfig, entry: Pending, now: number): ()
	local vitals = entry.vitals
	local player = vitals.player
	-- Gone, or down: a downed player takes no further hits.
	if vitalsByPlayer[player] ~= vitals or vitals.down then
		return
	end
	local root, humanoid = bodyOf(player)
	if root == nil or humanoid == nil then
		return
	end
	local strike = entry.strike
	local attack = strike.def
	local position = root.Position
	-- Ruling 11: a jump clears a ground shape. The feet come from the same sample as the plan
	-- test; R15's HipHeight is measured to the root's underside.
	local height = attack.height
	local feetY = position.Y - (humanoid.HipHeight + root.Size.Y / 2)
	local held = inPlan(strike, position) and not (height ~= nil and feetY - strike.floorY > height)
	-- An i-frame met the judging span, or (ruling 18) a knockback's window is open.
	local covered = entry.covered or now < vitals.knockUntil
	-- Ruling 26: a dash carries the player far out of a lunge, so the shape rarely still holds
	-- them when it is judged. A miss by the player the attack was aimed at, under an i-frame,
	-- is their dodge and says so. Walking out is not a dodge, and a bystander dodged nothing.
	if not held and not (covered and strike.targetUserId == player.UserId) then
		return
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
	if not held or covered or vitals.god then
		-- Rulings 7 and 14: a voided hit still says so, so a dash reads as a dodge and `god`
		-- lets the tells be studied. Ruling 18: so does a hit decided inside a knockback's
		-- window, even one whose impact was only noticed after that knockback landed.
		fx.dodged = true
		return
	end

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
		return
	end
	humanoid.Health -= amount
	if knockback > 0 or launch > 0 then
		-- Ruling 6: thrown by one hit, the player cannot be caught by the next while in the air.
		local knockIframes = math.max(config.player.knockIframes, 0)
		grantIframes(player, knockIframes)
		-- Ruling 18: nor by the ones decided with it. Enemies that wound up in the same step
		-- would otherwise land as one hit, and stay in step for good. Every other hit of theirs
		-- still waiting is voided here; `knockUntil` voids the ones not yet raised.
		vitals.knockUntil = now + knockIframes
		for _, other in pending do
			if other.vitals == vitals then
				other.covered = true
			end
		end
	end
end

-- Walks the queue: notes any i-frame that has covered an entry so far, decides the entries
-- whose moment has come and keeps the rest, in order.
local function settle(config: Types.ProvingGroundsConfig, now: number): ()
	local count = #pending
	if count == 0 then
		return
	end
	local range = hooks
	local kept = 0
	for index = 1, count do
		local entry = pending[index]
		if not entry.covered and range ~= nil then
			-- Asked every frame, not only at the decision, and of the window before the current
			-- one as well: a dash that covered the impact may have lapsed and been replaced by
			-- then, or even before the step that raised the strike.
			local from, untilClock, wasFrom, wasUntil = range.iframeWindow(entry.vitals.player)
			local impact = entry.strike.at
			local limit = math.min(now, entry.decideAt)
			entry.covered = met(from, untilClock, impact, limit)
				or met(wasFrom, wasUntil, impact, limit)
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

-- An enemy attack's impact: every player who was standing at that moment gets a decision at
-- their own lag. Nothing is judged here: the root the rule wants is the one the server will
-- hold then, not now.
local function onImpact(strike: CrowdBrain.Strike): ()
	local shooting = Tuning.Get().shooting
	local impact = strike.at
	for player, vitals in vitalsByPlayer do
		-- Down at the impact's own time, not at this later step's: an impact that fell just
		-- before a get-up is raised after it, and would land inside the get-up window.
		if impact >= vitals.downFrom and impact < vitals.downUntil then
			continue
		end
		table.insert(pending, {
			strike = strike,
			vitals = vitals,
			decideAt = impact + lagOf(player, shooting),
			covered = false,
		})
	end
end

-- Public -----------------------------------------------------------------------------------------

-- Called by RangeService.Start, so only when the range booted. Idempotent.
function VitalsService.Start(rangeHooks: Hooks): ()
	if started then
		return
	end
	started = true
	hooks = rangeHooks
	CrowdService.SetThreatHooks({ canTarget = canTarget, impact = onImpact })
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
-- exist land on nobody. A player who is down stays down for the rest of their time.
function VitalsService.OnSetLoaded(): ()
	table.clear(pending)
	for _, vitals in vitalsByPlayer do
		vitals.damageTaken = 0
		vitals.downs = 0
	end
end

return VitalsService
