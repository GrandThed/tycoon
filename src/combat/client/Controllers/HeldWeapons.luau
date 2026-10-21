--!strict
-- Weapons in hand, on every player's character in the combat place (docs/prompts/l3-w2-contract.md,
-- L3-51 and L3-52). Display only: a model is never a ray start or an arc centre, and nothing a hit
-- is judged on reads it (InputController's shot and melee origins, FeedbackController.PredictSwing
-- and the server's rules stay exactly where W1 put them).
--
--  * What a character holds comes from the three attributes WeaponService writes on it
--    (WeaponLook.ATTRIBUTES: the melee family, the ranged family, the slot in use). The local
--    character's slot in use is the local stance instead (SetLocalStance, called by
--    WeaponController.SetStance on the frame of the switch): the server hears of a pure switch
--    only at that player's next attack, draw or cast, which is when everyone else sees it (L3-65).
--  * The weapon in use hangs from RightGripAttachment by its grip, the other from
--    BodyBackAttachment by its holster, each by one Weld to the template's Base. The template's
--    frame is the weapon generator's and Base is its pivot (L3-47), so a config point p sits at
--    base.CFrame:PointToWorldSpace(p). A model is cloned once per character and family; a switch
--    only re-points the two welds. Nothing here runs per frame.
--  * Rest poses (contract section 11, ruling 6): no one grip fits a hanging arm and a drawn bow,
--    so a melee weapon is held tip forward from the hanging hand (COMBAT_HOLD_GRIP_MELEE) and a
--    ranged one along the arm (COMBAT_HOLD_GRIP_RANGED), which WeaponController raises forward
--    while a ranged model is in the hand. OnHold tells it when that changes, per character.
--  * Muzzle is the one place a tracer, a flame or an ability effect leaves from: the tip of the
--    model in the hand, else W1's chain (the right hand, then the root).
--  * Anything missing (WeaponModels.json, a family in it, a template before the harvest paste, an
--    attachment) leaves that slot empty, exactly as in W1. Only a family the config does not know
--    warns, once a session. No sound (combat has none).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))
local WeaponLook = require(sharedFolder:WaitForChild("WeaponLook"))

local uiFolder = script.Parent.Parent:WaitForChild("UI")
local Create = require(uiFolder:WaitForChild("Create"))
local Theme = require(uiFolder:WaitForChild("Theme"))

local MELEE_SLOT = "melee"
local RANGED_SLOT = "ranged"
local MODEL_PREFIX = "HeldWeapon_"
local WELD_NAME = "HeldWeaponWeld"
-- One look for everyone in W2 (L3-55): the template's first stage.
local SHOWN_STAGE = "Stage0"
-- The right hand, R15 first and R6 second: where the weapon in use hangs, and where W1's fallback
-- chain starts when no model is in it (then ROOT_PART).
local HAND_PARTS = { "RightHand", "Right Arm" }
local BACK_PARTS = { "UpperTorso", "Torso" }
local ROOT_PART = "HumanoidRootPart"
local GRIP_ATTACHMENT = "RightGripAttachment"
local BACK_ATTACHMENT = "BodyBackAttachment"

-- One clone: its pivot part (the grip), the weld that hangs it, its config entry and its tip.
type Held = {
	model: Model,
	base: BasePart,
	weld: Weld,
	def: Types.WeaponModelDef,
	tip: Vector3?,
}

-- One watched character. `watched` holds the body parts whose ChildAdded is already connected;
-- `raised` is whether a ranged model is in its hand, as last told to the hold listener.
type Rig = {
	character: Model,
	isLocal: boolean,
	inHand: Held?,
	raised: boolean,
	watched: { [Instance]: boolean },
	connections: { RBXScriptConnection },
}

-- WeaponController's arm pose: told when a character's hand starts or stops holding a ranged model.
export type HoldListener = (character: Model, isLocal: boolean, raised: boolean) -> ()

local HeldWeapons = {}

local started = false
local localStance = MELEE_SLOT
local connections: { RBXScriptConnection } = {}
local playerConnections: { [Player]: { RBXScriptConnection } } = {}
local rigs: { [Player]: Rig } = {}
-- models[character][family]. Weak-keyed, so a character that is gone takes its records with it.
local models: { [Model]: { [string]: Held } } = setmetatable({}, { __mode = "k" }) :: any
local warned: { [string]: boolean } = {}
local holdListener: HoldListener? = nil

local function templateOf(folder: string, name: string): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local props = if assets ~= nil then assets:FindFirstChild("Props") else nil
	local set = if props ~= nil then props:FindFirstChild(folder) else nil
	local template = if set ~= nil then set:FindFirstChild(name) else nil
	if template ~= nil and template:IsA("Model") and template.PrimaryPart ~= nil then
		return template
	end
	return nil
end

-- Decoration only (L3-52): never a physics body and never in a query, so the camera beside the
-- shoulder and every client ray pass through it, and it never weighs on the rig.
local function seal(model: Model): ()
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
		end
	end
end

-- The character's clone of `family`, made once: the shown stage only, sealed, every other part
-- welded to Base, and the one Weld that hangs it (its Part0 is set by `hang`).
local function modelFor(character: Model, family: string): Held?
	local cache = models[character]
	local cached = if cache ~= nil then cache[family] else nil
	if cached ~= nil then
		return cached
	end
	local config = Catalog.GetWeaponModelsConfig()
	if config == nil then
		return nil
	end
	local def = WeaponLook.Def(config, family)
	if def == nil then
		if not warned[family] then
			warned[family] = true
			warn(`[HeldWeapons] no WeaponModels.json entry for '{family}': it is not drawn`)
		end
		return nil
	end
	local template = templateOf(config.folder, def.model)
	if template == nil then
		return nil -- before the harvest paste: that slot stays empty, as in W1
	end
	local model = template:Clone()
	local base = model.PrimaryPart
	if base == nil then
		model:Destroy()
		return nil
	end
	for _, child in model:GetChildren() do
		if
			child:IsA("Model")
			and child.Name ~= SHOWN_STAGE
			and string.match(child.Name, "^Stage%d+$")
		then
			child:Destroy()
		end
	end
	seal(model)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part ~= base then
			Create("WeldConstraint", { Part0 = base, Part1 = part, Parent = base })
		end
	end
	local weld = Create("Weld", {
		Name = WELD_NAME,
		Part1 = base,
		C1 = CFrame.identity,
		Parent = base,
	}) :: Weld
	model.Name = MODEL_PREFIX .. family
	model.Parent = character
	local entry: Held = {
		model = model,
		base = base,
		weld = weld,
		def = def,
		tip = WeaponLook.Point(def, "tip"),
	}
	if cache == nil then
		models[character] = { [family] = entry }
	else
		cache[family] = entry
	end
	return entry
end

-- The body part and attachment a slot hangs from. Direct children only: accessory handles carry
-- attachments of the same names.
local function mountOf(character: Model, inHand: boolean): (BasePart?, Attachment?)
	local attachmentName = if inHand then GRIP_ATTACHMENT else BACK_ATTACHMENT
	local names: { string } = if inHand then HAND_PARTS else BACK_PARTS
	for _, name in names do
		local part = character:FindFirstChild(name)
		local attachment = if part ~= nil then part:FindFirstChild(attachmentName) else nil
		if
			part ~= nil
			and part:IsA("BasePart")
			and attachment ~= nil
			and attachment:IsA("Attachment")
		then
			return part, attachment
		end
	end
	return nil, nil
end

-- Hangs `family` in the hand by its grip (held as its slot holds, `ranged`) or on the back by its
-- holster. A slot whose attachment is not there yet takes its model (if any) off the character
-- until it appears.
local function hang(rig: Rig, family: string?, inHand: boolean, ranged: boolean): Held?
	if family == nil then
		return nil
	end
	local character = rig.character
	local part, attachment = mountOf(character, inHand)
	if part == nil or attachment == nil then
		local cache = models[character]
		local cached = if cache ~= nil then cache[family] else nil
		if cached ~= nil then
			cached.model.Parent = nil
		end
		return nil
	end
	local held = modelFor(character, family)
	if held == nil then
		return nil
	end
	local point = WeaponLook.Point(held.def, if inHand then "grip" else "holster") or Vector3.zero
	local hold = if not inHand
		then Theme.COMBAT_HOLD_BACK
		elseif ranged then Theme.COMBAT_HOLD_GRIP_RANGED
		else Theme.COMBAT_HOLD_GRIP_MELEE
	held.weld.Part0 = part
	held.weld.C0 = attachment.CFrame * hold * CFrame.new(-point)
	held.model.Parent = character
	return held
end

-- Puts a character's two weapons where its loadout and slot in use say. Runs on events only.
local function show(rig: Rig): ()
	local character = rig.character
	if character.Parent == nil then
		return
	end
	local melee, ranged, held = WeaponLook.Read(function(name: string): any
		return character:GetAttribute(name)
	end)
	local slot = if rig.isLocal then localStance else held
	local rangedInUse = slot == RANGED_SLOT
	local inUse = if rangedInUse then ranged else melee
	local other = if rangedInUse then melee else ranged
	local cache = models[character]
	if cache ~= nil then
		for family, entry in cache do
			if family ~= melee and family ~= ranged then
				cache[family] = nil
				entry.model:Destroy()
			end
		end
	end
	rig.inHand = hang(rig, inUse, true, rangedInUse)
	hang(rig, other, false, not rangedInUse)
	local raised = rangedInUse and rig.inHand ~= nil
	if raised ~= rig.raised then
		rig.raised = raised
		local listener = holdListener
		if listener ~= nil then
			listener(character, rig.isLocal, raised)
		end
	end
end

local function unbind(player: Player): ()
	local rig = rigs[player]
	if rig == nil then
		return
	end
	rigs[player] = nil
	for _, connection in rig.connections do
		connection:Disconnect()
	end
	local cache = models[rig.character]
	models[rig.character] = nil
	if cache ~= nil then
		for _, entry in cache do
			entry.model:Destroy()
		end
	end
end

local function isMountPart(name: string): boolean
	return table.find(HAND_PARTS, name) ~= nil or table.find(BACK_PARTS, name) ~= nil
end

-- A hand or torso that has no attachment yet hangs its slot when the attachment arrives.
local function watchPart(rig: Rig, part: Instance): ()
	if rig.watched[part] then
		return
	end
	rig.watched[part] = true
	table.insert(
		rig.connections,
		part.ChildAdded:Connect(function(child: Instance)
			if child.Name == GRIP_ATTACHMENT or child.Name == BACK_ATTACHMENT then
				show(rig)
			end
		end)
	)
end

local function bind(player: Player, character: Model): ()
	unbind(player)
	local rig: Rig = {
		character = character,
		isLocal = player == Players.LocalPlayer,
		inHand = nil,
		raised = false,
		watched = {},
		connections = {},
	}
	rigs[player] = rig
	local names = WeaponLook.ATTRIBUTES
	for _, name in { names.melee, names.ranged, names.held } do
		table.insert(
			rig.connections,
			character:GetAttributeChangedSignal(name):Connect(function()
				show(rig)
			end)
		)
	end
	table.insert(
		rig.connections,
		character.ChildAdded:Connect(function(child: Instance)
			if isMountPart(child.Name) then
				watchPart(rig, child)
				show(rig)
			end
		end)
	)
	for _, child in character:GetChildren() do
		if isMountPart(child.Name) then
			watchPart(rig, child)
		end
	end
	-- A dead rig's joints break: its weapons go with it rather than drop through the floor.
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil then
		table.insert(
			rig.connections,
			humanoid.Died:Connect(function()
				if rigs[player] == rig then
					unbind(player)
				end
			end)
		)
	end
	show(rig)
end

local function watchPlayer(player: Player): ()
	if playerConnections[player] ~= nil then
		return
	end
	playerConnections[player] = {
		player.CharacterAdded:Connect(function(character: Model)
			bind(player, character)
		end),
		player.CharacterRemoving:Connect(function(character: Model)
			local rig = rigs[player]
			if rig ~= nil and rig.character == character then
				unbind(player)
			end
		end),
	}
	local character = player.Character
	if character ~= nil then
		bind(player, character)
	end
end

local function forgetPlayer(player: Player): ()
	local list = playerConnections[player]
	playerConnections[player] = nil
	if list ~= nil then
		for _, connection in list do
			connection:Disconnect()
		end
	end
	unbind(player)
end

local function refreshAll(): ()
	for _, rig in rigs do
		show(rig)
	end
end

local function firstPart(character: Model, names: { string }): BasePart?
	for _, name in names do
		local part = character:FindFirstChild(name)
		if part ~= nil and part:IsA("BasePart") then
			return part
		end
	end
	return nil
end

-- Public -------------------------------------------------------------------------------

function HeldWeapons.Start(): ()
	if started then
		return
	end
	started = true
	local config = Catalog.GetWeaponModelsConfig()
	local proving = Catalog.GetProvingGroundsConfig()
	if config ~= nil and proving ~= nil then
		local problems = WeaponLook.Problems(config, proving.weapons)
		if #problems > 0 then
			warn("[HeldWeapons] WeaponModels.json: " .. table.concat(problems, "; "))
		end
	end
	table.insert(connections, Players.PlayerAdded:Connect(watchPlayer))
	table.insert(connections, Players.PlayerRemoving:Connect(forgetPlayer))
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	-- A template that had not replicated at boot is looked up again once the game is in.
	if not game:IsLoaded() then
		table.insert(connections, game.Loaded:Connect(refreshAll))
	end
end

-- WeaponController's arm pose (ruling 6). Every character whose hand already holds a ranged model
-- is told at once, so a listener set after Start misses nothing.
function HeldWeapons.OnHold(listener: HoldListener?): ()
	holdListener = listener
	if listener == nil then
		return
	end
	for _, rig in rigs do
		if rig.raised then
			listener(rig.character, rig.isLocal, true)
		end
	end
end

-- The local slot in use, on the frame of the switch (the server is not told of a pure switch).
function HeldWeapons.SetLocalStance(slot: string): ()
	local nextStance = if slot == RANGED_SLOT then RANGED_SLOT else MELEE_SLOT
	if nextStance == localStance then
		return
	end
	localStance = nextStance
	local rig = rigs[Players.LocalPlayer]
	if rig ~= nil then
		show(rig)
	end
end

-- Where that player's shot, flame or ability effect leaves from (L3-52): the tip of the model in
-- the hand and true; with none, W1's chain (the right hand, then the root) and false; with no
-- character, nil and false.
function HeldWeapons.Muzzle(userId: number): (Vector3?, boolean)
	local player = Players:GetPlayerByUserId(userId)
	local character = if player ~= nil then player.Character else nil
	if player == nil or character == nil then
		return nil, false
	end
	local rig = rigs[player]
	local held = if rig ~= nil and rig.character == character then rig.inHand else nil
	local tip = if held ~= nil then held.tip else nil
	if held ~= nil and tip ~= nil and held.model.Parent == character then
		return held.base.CFrame:PointToWorldSpace(tip), true
	end
	local hand = firstPart(character, HAND_PARTS)
	if hand ~= nil then
		return hand.Position, false
	end
	local root = character:FindFirstChild(ROOT_PART)
	if root ~= nil and root:IsA("BasePart") then
		return root.Position, false
	end
	return nil, false
end

function HeldWeapons.Destroy(): ()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	for player, list in playerConnections do
		playerConnections[player] = nil
		for _, connection in list do
			connection:Disconnect()
		end
	end
	for player in rigs do
		unbind(player)
	end
	holdListener = nil
	started = false
end

return HeldWeapons
