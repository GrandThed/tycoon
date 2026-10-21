--!strict
-- Studio-only lever strip for the Expeditions place (C1 contract, docs/INTERFACES.md
-- "Combat client" → DebugPanel). Every button sends one `RequestDebug(lever, value)`; the
-- server ignores the remote outside Studio, and CombatUIController never builds this panel
-- unless `RunService:IsStudio()`, so a live client has no such GUI at all.
--
-- The panel holds no game knowledge: the wave it increments and the gear tier it raises
-- come from the RunState and the Snapshot that CombatUIController pushes in, and the spawn
-- keys are the level's rewarded crowd kinds, which it is handed. Nothing here is a constant
-- that belongs in JSON.
--
-- L1 (docs/INTERFACES.md "L1 contracts", ruling 33): the three Studio keys have a button each
-- (N = skip the stage, B = skip to the boss, G = the next gear preset), so the phone emulator,
-- which has no keys, can do what the keys do. The wave stepper stays and forces a wave of the
-- live camp.
--
-- L2 Wave 1 (docs/prompts/l2-w1-contract.md, L2-19): "Double Jump on/off" (the J key: grant or
-- remove the caller's own, the way to flip it asked of the host when pressed, the caption from
-- SetAirJump) and "Reset secrets" (the H key). The mission HUD passes `deps.airJump`; without it
-- neither button is built.
--
-- L2 Wave 2 (docs/prompts/l2-w2-contract.md, L2-38): "Flamethrower on/off" (the F key: grant or
-- remove the caller's fire family, the lever and the family asked of the host when pressed, the
-- caption from SetFireFamily). The mission HUD passes `deps.fireFamily`; without it, no button.
--
-- L2 Wave 3 (docs/prompts/l2-w3-contract.md, L2-61): "Frost Hammer on/off" (the I key), the same
-- for the caller's ice family, from `deps.iceFamily` and SetIceFamily.
--
-- L3 Wave 1 (docs/prompts/l3-w1-contract.md, L3-28): tiers belong to families, so the two "+1"
-- buttons raise the HELD families' saved tiers (`setTier "<family>=<tier>"`, the server clamps it
-- into the window) and their captions show those tiers, which the host reads from the Snapshot
-- and the TuneState (SetTiers). They replace the slot override's "Melee +1" / "Ranged +1": the
-- override (`setGear`) is still G's presets and the DebugSetGear attribute. Three buttons mirror
-- the new keys: "+500 Timber" (T, in place of the old 25), the star lever (U: Unlocks.ALL_STARS,
-- captioned from the built levels, "★ Hard: Forest Road (U)") and "Reset Armory" (L).
--
-- Geometry matches the hub's DebugPanel: 48 design px buttons (the 44 physical px tap
-- target at MIN_SCALE), here wrapped into two columns (the hub's three). A short landscape
-- viewport makes the body SCROLL rather than shrink, because a lever that is 27 px tall is a
-- lever no one can hit.
-- It parks in the left column between the run header and the bottom-left controls, the one
-- band no other HUD element uses in either orientation, and collapses to a single tab.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Format = require(sharedFolder:WaitForChild("Format"))
local Unlocks = require(sharedFolder:WaitForChild("Unlocks"))

local ArmoryScreen = require(script.Parent:WaitForChild("ArmoryScreen"))
local Create = require(script.Parent:WaitForChild("Create"))
local Theme = require(script.Parent:WaitForChild("Theme"))

-- C2.5: onToggle tells the shoulder camera the strip is open, so the mouse unlocks for it.
export type Deps = {
	onLever: (lever: string, value: any) -> (),
	onToggle: ((open: boolean) -> ())?,
	-- L2-19: the air jump's ability id and the lever that flips it for the caller now
	-- ("grantAbility" or "removeAbility"); nil = no Double Jump or Reset secrets buttons.
	airJump: { id: string, lever: () -> string }?,
	-- L2-38: the lever ("grantFamily" or "removeFamily") and the family it flips for the caller
	-- now; nil = no Flamethrower button.
	fireFamily: { lever: () -> (string, string) }?,
	-- L2-61: the same for the ice family; nil = no Frost Hammer button.
	iceFamily: { lever: () -> (string, string) }?,
}

-- L3-28: a held family and the tier it fights at (Armory.TierOf), for one slot.
export type HeldTier = { family: string, tier: number }

export type DebugPanelHandle = {
	-- The crowd kinds the spawn buttons name: the live level's rewarded kinds, sorted; none
	-- in the lobby.
	SetKinds: (kinds: { string }) -> (),
	SetWave: (wave: number) -> (),
	-- L3-28: the held families' tiers; nil = none known (the tier button does nothing).
	SetTiers: (melee: HeldTier?, ranged: HeldTier?) -> (),
	-- L2-19: whether the caller owns the double jump now (the button's caption).
	SetAirJump: (owned: boolean) -> (),
	-- L2-38: whether the caller holds the fire family now (the button's caption).
	SetFireFamily: (owned: boolean) -> (),
	-- L2-61: whether the caller holds the ice family now (the button's caption).
	SetIceFamily: (owned: boolean) -> (),
	-- false = the whole strip, its tab included, is off the screen (the map is open: it is a
	-- full-screen sheet of the strip's own ZIndex tier, and the tab drew over it). What was open
	-- is open again when it comes back.
	SetVisible: (visible: boolean) -> (),
	SetLayout: (scale: number, viewportSize: Vector2) -> (),
	Destroy: () -> (),
}

-- Mirrors CombatHud's own stacking so the strip lands in the gap between them: the header
-- block it starts below, and the HP + Ready/Return column it must stay above.
local HEADER_BLOCK = Theme.TOP_BAR_HEIGHT
	+ Theme.COMBAT_WALLET_HEIGHT
	+ Theme.COMBAT_BOSS_LABEL_HEIGHT
	+ Theme.COMBAT_BOSS_BAR_HEIGHT
	+ Theme.SCREEN_MARGIN * 3
local BOTTOM_BLOCK = Theme.PADDING
	+ Theme.COMBAT_HP_LABEL_HEIGHT
	+ Theme.COMBAT_HP_BAR_HEIGHT
	+ Theme.ROW_SPACING
	+ Theme.ROW_BUTTON_HEIGHT
	+ Theme.COMBAT_CONTROL_GAP
local CELL_WIDTH = (
	Theme.COMBAT_DEBUG_WIDTH
	- Theme.COMBAT_DEBUG_GAP * 3
	- Theme.SCROLLBAR_THICKNESS
) / Theme.COMBAT_DEBUG_COLUMNS
-- L3-28, 3-s2: the star lever's caption is ArmoryScreen.StarLeverText() and this key.
local STAR_KEY_SUFFIX = " (U)"

local DebugPanel = {}

function DebugPanel.new(parent: Instance, deps: Deps): DebugPanelHandle
	local connections: { RBXScriptConnection } = {}
	local spawnButtons: { TextButton } = {}
	local wave = 0
	local held: { melee: HeldTier?, ranged: HeldTier? } = { melee = nil, ranged = nil }
	local godMode = false
	local bots = 0

	local root = Create("Frame", {
		Name = "DebugPanel",
		-- Inactive container: only the tab and the buttons take input, so the transparent
		-- area beside a collapsed tab never swallows a tap meant for the HUD behind it.
		Active = false,
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromOffset(Theme.SCREEN_MARGIN, Theme.SCREEN_MARGIN),
		Size = UDim2.fromOffset(Theme.COMBAT_DEBUG_WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ZIndex = Theme.ZINDEX_CARD,
		Parent = parent,
	}) :: Frame
	local uiScale = Create("UIScale", { Parent = root }) :: UIScale
	Create("UIListLayout", {
		Padding = UDim.new(0, Theme.COMBAT_DEBUG_GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = root,
	})

	-- ScrollingFrame, not an auto-sized Frame: SetLayout gives it whatever height the band
	-- allows and the canvas scrolls past that, so the buttons keep their full size.
	local body = Create("ScrollingFrame", {
		Name = "Body",
		LayoutOrder = 2,
		Active = true, -- the sheet behind the buttons sinks taps that miss a button
		Size = UDim2.new(1, 0, 0, Theme.COMBAT_DEBUG_ROW_HEIGHT),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = Theme.SCROLLBAR_THICKNESS,
		BackgroundColor3 = Theme.COLOR_BG,
		BackgroundTransparency = Theme.BG_TRANSPARENCY,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = Theme.ZINDEX_CARD,
		Parent = root,
	}) :: ScrollingFrame
	Create("UICorner", { CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = body })
	Create("UIPadding", {
		PaddingTop = UDim.new(0, Theme.COMBAT_DEBUG_GAP),
		PaddingBottom = UDim.new(0, Theme.COMBAT_DEBUG_GAP),
		PaddingLeft = UDim.new(0, Theme.COMBAT_DEBUG_GAP),
		PaddingRight = UDim.new(0, Theme.COMBAT_DEBUG_GAP),
		Parent = body,
	})
	Create("UIGridLayout", {
		CellSize = UDim2.fromOffset(CELL_WIDTH, Theme.COMBAT_DEBUG_ROW_HEIGHT),
		CellPadding = UDim2.fromOffset(Theme.COMBAT_DEBUG_GAP, Theme.COMBAT_DEBUG_GAP),
		FillDirectionMaxCells = Theme.COMBAT_DEBUG_COLUMNS,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = body,
	})

	local order = 0
	local function leverButton(text: string, onClick: (TextButton) -> ()): TextButton
		order += 1
		local button = Create("TextButton", {
			Name = "Lever" .. tostring(order),
			LayoutOrder = order,
			BackgroundColor3 = Theme.COLOR_BG_LIGHT,
			BorderSizePixel = 0,
			Font = Theme.FONT,
			TextSize = Theme.COMBAT_DEBUG_TEXT,
			TextColor3 = Theme.COLOR_TEXT,
			TextWrapped = true,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = text,
			ZIndex = Theme.ZINDEX_CARD,
			Parent = body,
		}) :: TextButton
		Create("UICorner", {
			CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS),
			Parent = button,
		})
		table.insert(
			connections,
			button.Activated:Connect(function()
				onClick(button)
			end)
		)
		return button
	end

	-- The star lever, made with the others below; its caption is read again at every open.
	local starButton: TextButton? = nil

	-- The tab stays a full tap target so a phone in the Studio emulator can open it.
	local toggle = Create("TextButton", {
		Name = "Toggle",
		LayoutOrder = 1,
		Size = UDim2.fromOffset(Theme.COMBAT_DEBUG_TOGGLE_SIZE * 2, Theme.COMBAT_DEBUG_TOGGLE_SIZE),
		BackgroundColor3 = Theme.COLOR_HIGHLIGHT,
		BorderSizePixel = 0,
		Font = Theme.FONT_BOLD,
		TextSize = Theme.COMBAT_DEBUG_TEXT,
		TextColor3 = Theme.COLOR_TEXT_DARK,
		Text = "⚙ debug",
		ZIndex = Theme.ZINDEX_CARD,
		Parent = root,
	}) :: TextButton
	Create("UICorner", { CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = toggle })
	table.insert(
		connections,
		toggle.Activated:Connect(function()
			body.Visible = not body.Visible
			local star = starButton
			if body.Visible and star ~= nil then
				-- The level files may have come after boot.
				star.Text = ArmoryScreen.StarLeverText() .. STAR_KEY_SUFFIX
			end
			local onToggle = deps.onToggle
			if onToggle ~= nil then
				onToggle(body.Visible)
			end
		end)
	)

	-- Labels are short because a cell is half the strip: the lever each one drives is named
	-- in the RequestDebug call, not in the caption.
	leverButton("Wave +1", function()
		deps.onLever("wave", wave + 1)
	end)
	leverButton("Skip stage (N)", function()
		deps.onLever("skip", "stage")
	end)
	leverButton("To boss (B)", function()
		deps.onLever("skip", "boss")
	end)
	leverButton("Gear next (G)", function()
		deps.onLever("gear", "next")
	end)
	-- Spawn buttons are created up front and named from the level's config, so the kind
	-- keys stay in JSON where they belong.
	for _ = 1, Theme.COMBAT_DEBUG_MAX_KIND_KEYS do
		local button = leverButton("Spawn —", function(source: TextButton)
			local key = source:GetAttribute("EnemyKey")
			if typeof(key) == "string" then
				deps.onLever("spawn", key)
			end
		end)
		button.Visible = false
		table.insert(spawnButtons, button)
	end
	local godButton = leverButton("God: off", function(source: TextButton)
		godMode = not godMode
		source.Text = if godMode then "God: ON" else "God: off"
		deps.onLever("godMode", godMode)
	end)
	godButton.Name = "God"
	leverButton("Kill all", function()
		deps.onLever("killAll", 1)
	end)
	-- L3-28: the held family's next saved tier; the server also drops any override G put on.
	local function tierButton(caption: string, slot: "melee" | "ranged"): TextButton
		return leverButton(caption .. " tier +1", function()
			local entry = held[slot]
			if entry ~= nil then
				deps.onLever("setTier", entry.family .. "=" .. tostring(entry.tier + 1))
			end
		end)
	end
	local meleeButton = tierButton("Melee", "melee")
	local rangedButton = tierButton("Ranged", "ranged")
	leverButton("Bots +1", function()
		bots += 1
		deps.onLever("bots", bots)
	end)
	leverButton("Bots −1", function()
		bots = math.max(bots - 1, 0)
		deps.onLever("bots", bots)
	end)
	leverButton("+" .. Format.Cash(Theme.COMBAT_DEBUG_GRANT_TIMBER) .. " Timber (T)", function()
		deps.onLever("grantMaterials", Theme.COMBAT_DEBUG_GRANT_TIMBER)
	end)
	leverButton("+" .. Format.Cash(Theme.COMBAT_DEBUG_GRANT_VALOR) .. " Valor (V)", function()
		deps.onLever("grantValor", Theme.COMBAT_DEBUG_GRANT_VALOR)
	end)
	-- Every built band level's star, named from those levels (the caption follows the Castle).
	starButton = leverButton(ArmoryScreen.StarLeverText() .. STAR_KEY_SUFFIX, function()
		deps.onLever("grantStar", Unlocks.ALL_STARS)
	end)
	leverButton("Reset Armory (L)", function()
		deps.onLever("resetArmory", true)
	end)
	-- C2: runs the server's CheckAdmission for this player and toasts the verdict; nobody
	-- is sent home.
	leverButton("Admit check", function()
		deps.onLever("admitCheck", true)
	end)
	-- L2-19: the bought double jump and the secrets, so a chest can be seen without clearing a
	-- level twice (the Studio store starts fresh every session).
	local airJump = deps.airJump
	local airJumpButton: TextButton? = nil
	if airJump ~= nil then
		airJumpButton = leverButton("Double Jump (J)", function()
			deps.onLever(airJump.lever(), airJump.id)
		end)
		leverButton("Reset secrets (H)", function()
			deps.onLever("resetSecrets", true)
		end)
	end
	local fireFamily = deps.fireFamily
	local fireButton: TextButton? = nil
	if fireFamily ~= nil then
		fireButton = leverButton("Flamethrower (F)", function()
			local lever, family = fireFamily.lever()
			deps.onLever(lever, family)
		end)
	end
	local iceFamily = deps.iceFamily
	local iceButton: TextButton? = nil
	if iceFamily ~= nil then
		iceButton = leverButton("Frost Hammer (I)", function()
			local lever, family = iceFamily.lever()
			deps.onLever(lever, family)
		end)
	end

	local handle: DebugPanelHandle = {
		SetKinds = function(kinds: { string })
			-- Sorted so the buttons never swap places between two identical sessions.
			local keys = table.clone(kinds)
			table.sort(keys)
			for index, button in spawnButtons do
				local key = keys[index]
				button.Visible = key ~= nil
				if key ~= nil then
					button:SetAttribute("EnemyKey", key)
					button.Text = "Spawn " .. key
				end
			end
		end,
		SetWave = function(nextWave: number)
			wave = nextWave
		end,
		SetTiers = function(melee: HeldTier?, ranged: HeldTier?)
			held.melee = melee
			held.ranged = ranged
			meleeButton.Text = if melee ~= nil
				then "Melee T" .. Format.Cash(melee.tier) .. " +1"
				else "Melee tier +1"
			rangedButton.Text = if ranged ~= nil
				then "Ranged T" .. Format.Cash(ranged.tier) .. " +1"
				else "Ranged tier +1"
		end,
		SetAirJump = function(owned: boolean)
			local button = airJumpButton
			if button ~= nil then
				button.Text = if owned then "Double Jump: ON (J)" else "Double Jump: off (J)"
			end
		end,
		SetFireFamily = function(owned: boolean)
			local button = fireButton
			if button ~= nil then
				button.Text = if owned then "Flamethrower: ON (F)" else "Flamethrower: off (F)"
			end
		end,
		SetIceFamily = function(owned: boolean)
			local button = iceButton
			if button ~= nil then
				button.Text = if owned then "Frost Hammer: ON (I)" else "Frost Hammer: off (I)"
			end
		end,
		SetVisible = function(visible: boolean)
			root.Visible = visible
		end,
		SetLayout = function(scale: number, viewportSize: Vector2)
			uiScale.Scale = scale
			-- The band between the run header and the bottom-left controls, in design px.
			local designHeight = viewportSize.Y / scale
			local top = Theme.SCREEN_MARGIN + HEADER_BLOCK
			local band = designHeight - BOTTOM_BLOCK - top
			local rows = math.ceil(order / Theme.COMBAT_DEBUG_COLUMNS)
			local natural = rows * Theme.COMBAT_DEBUG_ROW_HEIGHT
				+ (rows - 1) * Theme.COMBAT_DEBUG_GAP
				+ Theme.COMBAT_DEBUG_GAP * 2
			local room = band - Theme.COMBAT_DEBUG_TOGGLE_SIZE - Theme.COMBAT_DEBUG_GAP
			-- One row is the floor: a viewport too short for even that scrolls the rest.
			local height =
				math.clamp(math.min(natural, room), Theme.COMBAT_DEBUG_ROW_HEIGHT, natural)
			body.Size = UDim2.new(1, 0, 0, height)
			root.Position = UDim2.fromOffset(Theme.SCREEN_MARGIN * scale, top * scale)
		end,
		Destroy = function()
			for _, connection in connections do
				connection:Disconnect()
			end
			table.clear(connections)
			root:Destroy()
		end,
	}
	return handle
end

return DebugPanel
