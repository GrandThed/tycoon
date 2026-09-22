--!strict
-- Hit resolution (docs/INTERFACES.md "C1 contracts" → "Hits"). Every point of damage in the
-- place goes through this service: the melee combo, the ranged raycast, the two abilities, the
-- enemies hitting back, and the debug bots. That is what makes god mode, contribution tracking,
-- kill credit and the effect feed impossible to bypass.
--
-- The client sends INTENTS only — a swing counter, an aim ray, a slot name. It never sends
-- damage, never names an amount, and every id it does send is re-resolved against the live wave
-- and re-checked for range, arc and cooldown on the server clock.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Armory = require(sharedFolder:WaitForChild("Armory"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))
local Combat = require(sharedFolder:WaitForChild("Combat"))

local servicesFolder = script.Parent.Parent:WaitForChild("Services")
local DataService = require(servicesFolder:WaitForChild("DataService"))
local RemoteService = require(servicesFolder:WaitForChild("RemoteService"))
local ArenaService = require(script.Parent:WaitForChild("ArenaService"))
local EnemyService = require(script.Parent:WaitForChild("EnemyService"))

-- Degrade values, used only when a class omits the optional field for its family.
local DEFAULT_MELEE_ARC_DEGREES = 120
local DEFAULT_COMBO_RESET = 1
local DEFAULT_RANGED_COOLDOWN = 0.5
local DEFAULT_CHARGE_SECONDS = 1
local MELEE_STEPS = 3
-- A burst ability with no `radius` still has to find something: the class range is its reach.
local DEFAULT_ABILITY_RANGE = 40

type Attacker = {
	seq: number,
	step: number,
	lastSwingAt: number,
	-- False once a swing lands outside its window: step 3 then deals its damage without the
	-- finisher knockback and without the fat damage number.
	chainOk: boolean,
	shotSeq: number,
	lastShotAt: number,
}

local attackers: { [number]: Attacker } = {}
-- Per-wave damage tally, drained by WaveService at every wave clear.
local damageTally: { [number]: number } = {}
-- Batched once per Heartbeat frame: one FireClient per player instead of one per hit.
local broadcastQueue: { Types.CombatFx } = {}
local privateQueue: { [Player]: { Types.CombatFx } } = {}
local killHandler: ((enemy: EnemyService.Enemy, byUserId: number) -> ())? = nil
local fxConnection: RBXScriptConnection? = nil

local CombatService = {}

local function attackerFor(userId: number): Attacker
	local attacker = attackers[userId]
	if attacker == nil then
		attacker = {
			seq = 0,
			step = 0,
			lastSwingAt = 0,
			chainOk = true,
			shotSeq = 0,
			lastShotAt = 0,
		}
		attackers[userId] = attacker
	end
	return attacker
end

function CombatService.PushFx(fx: Types.CombatFx): ()
	table.insert(broadcastQueue, fx)
end

local function pushFxTo(player: Player, fx: Types.CombatFx): ()
	local queue = privateQueue[player]
	if queue == nil then
		queue = {}
		privateQueue[player] = queue
	end
	table.insert(queue, fx)
end

local function refuse(player: Player, reason: "cooldown" | "dead" | "lobby"): ()
	pushFxTo(player, { kind = "refused", reason = reason })
end

local function rootOf(member: Types.RunMember): BasePart?
	local character = member.character
	if character == nil then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root ~= nil and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function slotReadyAt(member: Types.RunMember, slot: string): number
	if slot == "ranged" then
		return member.abilityReadyAt.ranged
	end
	return member.abilityReadyAt.melee
end

local function setSlotReadyAt(member: Types.RunMember, slot: string, value: number): ()
	if slot == "ranged" then
		member.abilityReadyAt.ranged = value
	else
		member.abilityReadyAt.melee = value
	end
end

-- Resolves the weapon a slot is holding right now. nil means "no such weapon", which every
-- caller reads as "this intent does nothing" rather than as an error.
local function equipped(
	state: Types.PlayerState,
	armoryConfig: Types.ArmoryConfig,
	slot: string
): (Types.WeaponClassDef?, string)
	local tier = if slot == "ranged" then state.combat.gear.ranged else state.combat.gear.melee
	local def = Armory.TierDef(armoryConfig, slot, tier)
	if def == nil then
		return nil, ""
	end
	return Armory.ClassDef(armoryConfig, def.class), def.ability
end

-- The single place enemy HP goes down. Bots and enemies-hitting-back excepted, every path into
-- here started as a validated client intent.
function CombatService.DealDamage(
	enemy: EnemyService.Enemy,
	amount: number,
	byUserId: number,
	finisher: boolean
): boolean
	if amount <= 0 or enemy.dead then
		return false
	end
	local rounded = math.max(1, math.round(amount))
	damageTally[byUserId] = (damageTally[byUserId] or 0) + rounded
	local position = enemy.root.Position
	local killed = EnemyService.Damage(enemy, rounded, byUserId)
	CombatService.PushFx({
		kind = "hit",
		enemyId = enemy.id,
		amount = rounded,
		finisher = finisher,
		position = position,
		byUserId = byUserId,
	})
	return killed
end

-- Damage TO a party member (enemies only; there is no friendly fire). God mode zeroes it.
function CombatService.DamagePlayer(member: Types.RunMember, amount: number): ()
	if member.godMode or amount <= 0 then
		return
	end
	local humanoid = member.humanoid
	if humanoid == nil or humanoid.Health <= 0 then
		return
	end
	local rounded = math.max(1, math.round(amount))
	humanoid.Health = math.max(0, humanoid.Health - rounded)
	CombatService.PushFx({ kind = "playerHit", userId = member.userId, amount = rounded })
	if humanoid.Health > 0 then
		return
	end
	local combatConfig = Catalog.GetCombatConfig()
	local respawnIn = if combatConfig ~= nil then combatConfig.player.respawnSeconds else nil
	ArenaService.MarkDied(member.userId)
	CombatService.PushFx({ kind = "playerDown", userId = member.userId, respawnIn = respawnIn })
end

-- WaveService owns what a kill is worth; this service owns what a kill does to the killer.
function CombatService.SetKillHandler(
	handler: (enemy: EnemyService.Enemy, byUserId: number) -> ()
): ()
	killHandler = handler
end

local function onEnemyKilled(enemy: EnemyService.Enemy, byUserId: number): ()
	local combatConfig = Catalog.GetCombatConfig()
	local member = ArenaService.GetMember(byUserId)
	if combatConfig ~= nil and member ~= nil then
		-- Kills shorten both cooldowns: the reward for pressure is more pressure.
		local refund = combatConfig.player.killCooldownRefundSeconds
		member.abilityReadyAt.melee -= refund
		member.abilityReadyAt.ranged -= refund
	end
	local handler = killHandler
	if handler ~= nil then
		handler(enemy, byUserId)
	end
end

-- Drained by WaveService at every wave clear; the shares are computed from exactly this map, so
-- bots (negative user ids) are included here and discarded at the flush.
function CombatService.TakeDamageTally(): { [number]: number }
	local tally = damageTally
	damageTally = {}
	return tally
end

function CombatService.ResetDamageTally(): ()
	damageTally = {}
end

local function canAct(player: Player): (Types.RunMember?, Types.PlayerState?, Types.ArmoryConfig?)
	local member = ArenaService.GetMemberFor(player)
	if member == nil then
		return nil, nil, nil
	end
	if not ArenaService.InRun() then
		refuse(player, "lobby")
		return nil, nil, nil
	end
	if not ArenaService.IsAlive(member) then
		refuse(player, "dead")
		return nil, nil, nil
	end
	local state = DataService.GetState(player)
	local armoryConfig = Catalog.GetArmoryConfig()
	if state == nil or armoryConfig == nil then
		return nil, nil, nil
	end
	return member, state, armoryConfig
end

-- Melee: the client names the ids it believes it hit; the server keeps only the ones inside the
-- class arc and range, so a forged list is a list of misses.
function CombatService.OnAttack(player: Player, swingSeq: number, targetIds: { number }): ()
	local member, state, armoryConfig = canAct(player)
	local combatConfig = Catalog.GetCombatConfig()
	if member == nil or state == nil or armoryConfig == nil or combatConfig == nil then
		return
	end
	local class = equipped(state, armoryConfig, "melee")
	if class == nil or class.kind ~= "melee" then
		return
	end
	local root = rootOf(member)
	if root == nil then
		return
	end

	local attacker = attackerFor(member.userId)
	-- A replayed swing counter is the cheapest duplicate-packet exploit there is.
	if swingSeq <= attacker.seq then
		return
	end
	attacker.seq = swingSeq

	local windows = class.windows or {}
	local now = os.clock()
	local elapsed = now - attacker.lastSwingAt
	local tolerance = combatConfig.player.comboTimingTolerance
	local previous = attacker.step
	if previous > 0 then
		local window = windows[previous] or 0
		if elapsed < window * tolerance then
			refuse(player, "cooldown")
			return
		end
	end
	local comboReset = class.comboReset or DEFAULT_COMBO_RESET
	local step: number
	if previous == 0 or elapsed > comboReset then
		step = 1
		attacker.chainOk = true
	else
		step = previous % MELEE_STEPS + 1
		local window = windows[previous] or 0
		-- Inside the window means "on the beat": too slow still chains, but never finishes.
		if tolerance > 0 and elapsed > window / tolerance then
			attacker.chainOk = false
		end
	end
	attacker.step = step
	attacker.lastSwingAt = now
	-- The stance the HUD draws is inferred from what the player actually does, so no extra
	-- remote is needed to keep the party row honest.
	member.stance = "melee"

	local finisher = step == MELEE_STEPS and attacker.chainOk
	local damage = Combat.MeleeDamage(armoryConfig, state, step)
	if damage <= 0 then
		return
	end
	local reach = class.range + combatConfig.player.hitDistancePad
	local halfArc = (class.arcDegrees or DEFAULT_MELEE_ARC_DEGREES) / 2
	local look = root.CFrame.LookVector
	local seen: { [number]: boolean } = {}
	for _, enemyId in targetIds do
		if seen[enemyId] then
			continue
		end
		seen[enemyId] = true
		local enemy = EnemyService.GetById(enemyId)
		if enemy == nil then
			continue
		end
		local delta = enemy.root.Position - root.Position
		local flat = Vector3.new(delta.X, 0, delta.Z)
		if delta.Magnitude > reach or flat.Magnitude <= 0 then
			continue
		end
		local angle = math.deg(math.acos(math.clamp(look:Dot(flat.Unit), -1, 1)))
		if angle > halfArc then
			continue
		end
		CombatService.DealDamage(enemy, damage, member.userId, finisher)
		if finisher and class.finisherKnockback ~= nil then
			EnemyService.Knockback(enemy, flat, class.finisherKnockback)
		end
	end
end

-- Ranged: the client sends an aim ray, the server casts it. Spread and aim assist are client
-- side by contract, so a perfectly straight ray from a scripted client is the honest case.
function CombatService.OnFire(
	player: Player,
	seq: number,
	origin: Vector3,
	direction: Vector3,
	charge: number
): ()
	local member, state, armoryConfig = canAct(player)
	local combatConfig = Catalog.GetCombatConfig()
	if member == nil or state == nil or armoryConfig == nil or combatConfig == nil then
		return
	end
	local class = equipped(state, armoryConfig, "ranged")
	if class == nil or class.kind ~= "ranged" then
		return
	end
	local character = member.character
	if character == nil or direction.Magnitude <= 0 then
		return
	end

	local attacker = attackerFor(member.userId)
	if seq <= attacker.shotSeq then
		return
	end
	attacker.shotSeq = seq

	local head = character:FindFirstChild("Head")
	local muzzle = if head ~= nil and head:IsA("BasePart") then head.Position else nil
	if muzzle == nil then
		local root = rootOf(member)
		muzzle = if root ~= nil then root.Position else nil
	end
	if muzzle == nil or (origin - muzzle).Magnitude > combatConfig.player.hitDistancePad then
		return
	end

	local now = os.clock()
	local cooldown = class.cooldown or DEFAULT_RANGED_COOLDOWN
	local elapsed = now - attacker.lastShotAt
	if elapsed < cooldown * combatConfig.player.comboTimingTolerance then
		refuse(player, "cooldown")
		return
	end
	attacker.lastShotAt = now
	member.stance = "ranged"

	local resolvedCharge = math.clamp(charge, 0, 1)
	if class.fire == "charge" then
		-- The draw cannot be longer than the time actually spent holding.
		local chargeSeconds = class.chargeSeconds or DEFAULT_CHARGE_SECONDS
		resolvedCharge = math.clamp(math.min(resolvedCharge, elapsed / chargeSeconds), 0, 1)
	end
	local damage = Combat.RangedDamage(armoryConfig, state, resolvedCharge)
	if damage <= 0 then
		return
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignored: { Instance } = {}
	for _, other in ArenaService.GetMembers() do
		local otherCharacter = other.character
		if otherCharacter ~= nil then
			table.insert(ignored, otherCharacter)
		end
	end
	params.FilterDescendantsInstances = ignored

	local unit = direction.Unit
	local shots = 1 + (class.pierce or 0)
	local from = origin
	local budget = class.range
	for _ = 1, shots do
		if budget <= 0 then
			break
		end
		local result = workspace:Raycast(from, unit * budget, params)
		if result == nil then
			break
		end
		local enemy = EnemyService.FromInstance(result.Instance)
		if enemy == nil then
			-- World geometry: the shot stops at the boulder, which is the point of cover.
			break
		end
		CombatService.DealDamage(enemy, damage, member.userId, false)
		table.insert(ignored, enemy.model)
		params.FilterDescendantsInstances = ignored
		budget -= (result.Position - from).Magnitude
		from = result.Position
	end
end

local function enemiesInRadius(
	center: Vector3,
	radius: number,
	limit: number?
): { EnemyService.Enemy }
	local found: { EnemyService.Enemy } = {}
	for _, enemy in EnemyService.GetEnemies() do
		if not enemy.dead and (enemy.root.Position - center).Magnitude <= radius then
			table.insert(found, enemy)
		end
	end
	if limit == nil or #found <= limit then
		return found
	end
	table.sort(found, function(a: EnemyService.Enemy, b: EnemyService.Enemy): boolean
		local da = (a.root.Position - center).Magnitude
		local db = (b.root.Position - center).Magnitude
		if da == db then
			return a.id < b.id
		end
		return da < db
	end)
	local trimmed: { EnemyService.Enemy } = {}
	for index = 1, limit do
		table.insert(trimmed, found[index])
	end
	return trimmed
end

local function applyAbilityHit(
	enemy: EnemyService.Enemy,
	ability: Types.AbilityDef,
	damage: number,
	member: Types.RunMember,
	from: Vector3
): ()
	local dots = ability.dotTicks
	local dotSeconds = ability.dotSeconds
	if dots ~= nil and dots > 0 and dotSeconds ~= nil and dotSeconds > 0 then
		-- A damage-over-time ability pays its damageMult across the whole burn, not per tick.
		local perTick = damage / dots
		local interval = dotSeconds / dots
		for index = 1, dots do
			task.delay(interval * index, function()
				if enemy.dead then
					return
				end
				CombatService.DealDamage(enemy, perTick, member.userId, false)
			end)
		end
	else
		CombatService.DealDamage(enemy, damage, member.userId, false)
	end
	local knockback = ability.knockback
	if knockback ~= nil and knockback > 0 then
		EnemyService.Knockback(enemy, enemy.root.Position - from, knockback)
	end
	local stun = ability.stunSeconds
	if stun ~= nil and stun > 0 then
		EnemyService.Stun(enemy, stun)
	end
end

function CombatService.OnAbility(player: Player, slot: string): ()
	local member, state, armoryConfig = canAct(player)
	local combatConfig = Catalog.GetCombatConfig()
	if member == nil or state == nil or armoryConfig == nil or combatConfig == nil then
		return
	end
	local class, abilityKey = equipped(state, armoryConfig, slot)
	if class == nil or abilityKey == "" then
		return
	end
	local ability = Armory.AbilityDef(armoryConfig, abilityKey)
	local root = rootOf(member)
	if ability == nil or root == nil then
		return
	end
	local now = os.clock()
	if now < slotReadyAt(member, slot) then
		refuse(player, "cooldown")
		return
	end
	setSlotReadyAt(member, slot, now + Combat.AbilityCooldown(armoryConfig, state, slot))

	local damage = Combat.AbilityDamage(armoryConfig, state, slot)
	local from = root.Position
	local targets: { EnemyService.Enemy } = {}
	local effectRadius: number? = ability.radius
	if ability.kind == "aoe" then
		targets = enemiesInRadius(from, ability.radius or DEFAULT_ABILITY_RANGE, ability.shots)
	elseif ability.dashStuds ~= nil and ability.dashStuds > 0 then
		-- The client performs the dash visually; the server sweeps the segment it would cover.
		local look = root.CFrame.LookVector
		local radius = combatConfig.player.dashHitRadius
		local dash = ability.dashStuds
		effectRadius = radius
		for _, enemy in EnemyService.GetEnemies() do
			if enemy.dead then
				continue
			end
			local delta = enemy.root.Position - from
			local along = math.clamp(delta:Dot(look), 0, dash)
			if (delta - look * along).Magnitude <= radius then
				table.insert(targets, enemy)
			end
		end
	else
		local cone = combatConfig.player.burstConeDegrees / 2
		local look = root.CFrame.LookVector
		local reach = class.range
		local candidates: { EnemyService.Enemy } = {}
		for _, enemy in enemiesInRadius(from, reach, nil) do
			local delta = enemy.root.Position - from
			local flat = Vector3.new(delta.X, 0, delta.Z)
			if flat.Magnitude <= 0 then
				continue
			end
			if math.deg(math.acos(math.clamp(look:Dot(flat.Unit), -1, 1))) <= cone then
				table.insert(candidates, enemy)
			end
		end
		table.sort(candidates, function(a: EnemyService.Enemy, b: EnemyService.Enemy): boolean
			local da = (a.root.Position - from).Magnitude
			local db = (b.root.Position - from).Magnitude
			if da == db then
				return a.id < b.id
			end
			return da < db
		end)
		-- `pierce` is how many extra bodies one shot carries through.
		local wanted = (ability.shots or 1) + (ability.pierce or 0)
		for index = 1, math.min(wanted, #candidates) do
			table.insert(targets, candidates[index])
		end
	end

	for _, enemy in targets do
		applyAbilityHit(enemy, ability, damage, member, from)
	end
	CombatService.PushFx({
		kind = "ability",
		userId = member.userId,
		key = abilityKey,
		slot = if slot == "ranged" then "ranged" else "melee",
		position = from,
		radius = effectRadius,
	})
end

local function flushFx(): ()
	if #broadcastQueue == 0 and next(privateQueue) == nil then
		return
	end
	local shared = broadcastQueue
	broadcastQueue = {}
	local personal = privateQueue
	privateQueue = {}
	for _, member in ArenaService.GetMembers() do
		local player = member.player
		if player == nil then
			continue
		end
		local own = personal[player]
		local batch = shared
		if own ~= nil then
			batch = table.clone(shared)
			table.move(own, 1, #own, #batch + 1, batch)
		end
		if #batch > 0 then
			RemoteService.FireClient(player, "CombatFx", batch)
		end
	end
end

function CombatService.Init(): ()
	-- Wiring the bottom of the stack to the middle: EnemyService may not require this service
	-- (it is loaded first), so it is handed the roster and the damage sink here.
	EnemyService.SetHooks({
		targets = ArenaService.GetMembers,
		damagePlayer = CombatService.DamagePlayer,
		onKilled = onEnemyKilled,
	})
	Players.PlayerRemoving:Connect(function(player: Player)
		attackers[player.UserId] = nil
		privateQueue[player] = nil
	end)
end

function CombatService.Start(): ()
	if fxConnection ~= nil then
		return
	end
	fxConnection = RunService.Heartbeat:Connect(flushFx)
end

return CombatService
