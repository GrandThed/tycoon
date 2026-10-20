--!strict
-- Studio-only debug strip (C1 contract, docs/INTERFACES.md "Hub client (ui-engineer B)").
-- It is a remote control for the levers `ArmoryService` already exposes as Workspace
-- attributes: every button fires RequestDebug(lever, value) and the server ignores the
-- intent outside Studio, so this panel carries no entitlement and grants nothing by itself.
-- UIController only builds it when RunService:IsStudio(), so a live client never has it.
-- C2 adds the party levers: `fakeParty` (fake members, stepped +1 to 3 then cleared) and
-- `fakeInvite` (an invite from a fake leader), which drive every party UI state solo.
--
-- Collapsed to a single "⚙ debug" tab by default: the hub HUD is the thing being tested,
-- and an expanded strip must not be what the tester is looking at. It sits above the bottom
-- bar on the left, clear of the top bar in both orientations.
--
-- L3 Wave 1 (docs/prompts/l3-w1-contract.md, L3-28): the dungeon strip's Armory levers, for the
-- hub's Armory screen. "Grant 500 Timber" (was 25: a tier now costs 100 to 500; the server pays
-- every built band's material, Timber today), "Melee T1 +1" / "Ranged T1 +1" (`setTier` on the
-- HELD families, their tiers from SetTiers), "★ Forest Hard" (`grantStar`) and "Reset Armory"
-- (`resetArmory`). SetVisible takes the strip away while the Armory screen covers its corner.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Format"))

local Create = require(script.Parent:WaitForChild("Create"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local SoundController =
	require(script.Parent.Parent:WaitForChild("Controllers"):WaitForChild("SoundController"))

export type Deps = { onLever: (lever: string, value: any) -> () }

-- L3-28: a held family and the tier it fights at (Armory.TierOf), for one slot.
export type HeldTier = { family: string, tier: number }

export type DebugPanelHandle = {
	SetForceTeleportFailure: (value: boolean) -> (),
	-- C2: how many fake members the player's party has now (from PartyState), so the
	-- fakeParty button always offers the next step from the server's truth.
	SetFakePartyCount: (count: number) -> (),
	-- L3-28: the held families' tiers; nil = none known (that tier button does nothing).
	SetTiers: (melee: HeldTier?, ranged: HeldTier?) -> (),
	-- false = the strip, its tab included, is off the screen (the Armory screen is open).
	SetVisible: (visible: boolean) -> (),
	SetLayout: (scale: number) -> (),
	Destroy: () -> (),
}

-- Design-pixel geometry. These live here rather than in Theme because the strip exists only
-- in Studio: no shipped layout depends on them (see the report's routing note if they ever
-- need to move).
-- L3: three columns, not two. Eleven buttons in two would stand 384 design px tall, off the top
-- of a 667 x 375 phone in landscape (scale 0.92 and the bottom margin leave about 330); in three
-- they keep the old four rows, and 333 px still fits a 375 px portrait canvas.
local STRIP_WIDTH = 333
local TAB_WIDTH = 104
local BUTTON_WIDTH = 109 -- three columns inside STRIP_WIDTH with BUTTON_GAP between them
local BUTTON_HEIGHT = 48 -- x Theme.MIN_SCALE = the 44 physical px tap target
local BUTTON_GAP = 6
local COLUMNS = 3

-- Grant sizes are the Studio levers' own values, named in the labels so a tester never has
-- to guess what a button did. They are debug amounts, not game balance.
local CASH_GRANT = 10000
local VALOR_GRANT = 10
local FAKE_RUNS = 3
-- C2 contract: `fakeParty` takes 0–3 fake members; the button steps +1 and wraps to clear.
local FAKE_PARTY_MAX = 3
-- L3-28: the grantStar value for every built band level; Forest Road is the only one until the
-- Castle is built, which is what the caption says.
local STAR_ALL = "*"
local STAR_TEXT = "★ Forest Hard"

local DebugPanel = {}

function DebugPanel.new(parent: Instance, deps: Deps): DebugPanelHandle
	local connections: { RBXScriptConnection } = {}
	local expanded = false
	local forceTeleportFailure = false
	local fakePartyCount = 0
	local held: { melee: HeldTier?, ranged: HeldTier? } = { melee = nil, ranged = nil }

	local root = Create("Frame", {
		Name = "DebugPanel",
		-- Inactive container: only the tab and the buttons take input, so the transparent
		-- area beside a collapsed tab never swallows a tap meant for the HUD behind it.
		Active = false,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, Theme.SCREEN_MARGIN, 1, -Theme.PANEL_BOTTOM_MARGIN),
		Size = UDim2.fromOffset(STRIP_WIDTH, BUTTON_HEIGHT),
		BackgroundTransparency = 1,
		ZIndex = Theme.ZINDEX_CARD,
		Parent = parent,
	}) :: Frame
	local uiScale = Create("UIScale", { Parent = root }) :: UIScale

	local body = Create("Frame", {
		Name = "Body",
		Active = true, -- the sheet behind the buttons sinks taps that miss a button
		Size = UDim2.new(1, 0, 1, -BUTTON_HEIGHT - BUTTON_GAP),
		BackgroundColor3 = Theme.COLOR_BG,
		BackgroundTransparency = Theme.BG_TRANSPARENCY,
		BorderSizePixel = 0,
		Visible = false,
		Parent = root,
	}) :: Frame
	Create("UICorner", { CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = body })
	Create("UIPadding", {
		PaddingTop = UDim.new(0, BUTTON_GAP),
		PaddingBottom = UDim.new(0, BUTTON_GAP),
		PaddingLeft = UDim.new(0, BUTTON_GAP),
		PaddingRight = UDim.new(0, BUTTON_GAP),
		Parent = body,
	})
	Create("UIGridLayout", {
		CellSize = UDim2.fromOffset(BUTTON_WIDTH - BUTTON_GAP, BUTTON_HEIGHT),
		CellPadding = UDim2.fromOffset(BUTTON_GAP, BUTTON_GAP),
		FillDirectionMaxCells = COLUMNS,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = body,
	})

	local tab = Create("TextButton", {
		Name = "Tab",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromOffset(TAB_WIDTH, BUTTON_HEIGHT),
		BackgroundColor3 = Theme.COLOR_BG_LIGHT,
		BorderSizePixel = 0,
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT_SMALL,
		TextColor3 = Theme.COLOR_TEXT_DIM,
		Text = "⚙ debug",
		Parent = root,
	}) :: TextButton
	Create("UICorner", { CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = tab })

	local buttonCount = 0
	local function makeButton(text: string, onTap: () -> ()): TextButton
		buttonCount += 1
		local button = Create("TextButton", {
			Name = "Lever" .. tostring(buttonCount),
			LayoutOrder = buttonCount,
			BackgroundColor3 = Theme.COLOR_ROW,
			BorderSizePixel = 0,
			Font = Theme.FONT_BOLD,
			TextSize = Theme.TEXT_SMALL,
			TextColor3 = Theme.COLOR_TEXT,
			TextWrapped = true,
			TextScaled = true,
			Text = text,
			Parent = body,
		}) :: TextButton
		Create("UICorner", { CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = button })
		-- TextScaled keeps a long label inside a 109 px cell; the floor stops it going
		-- unreadable on a phone.
		Create("UITextSizeConstraint", {
			MinTextSize = Theme.ARMORY_CHIP_MIN_TEXT,
			MaxTextSize = Theme.TEXT_SMALL,
			Parent = button,
		})
		Create("UIPadding", {
			PaddingLeft = UDim.new(0, Theme.BUTTON_TEXT_PAD),
			PaddingRight = UDim.new(0, Theme.BUTTON_TEXT_PAD),
			Parent = button,
		})
		table.insert(
			connections,
			button.Activated:Connect(function()
				SoundController.Play("uiClick")
				onTap()
			end)
		)
		return button
	end

	makeButton("Grant $10K", function()
		deps.onLever("grantCash", CASH_GRANT)
	end)
	-- L3-28: the server pays the material of every band whose level is built (Timber today).
	makeButton("Grant " .. Format.Cash(Theme.COMBAT_DEBUG_GRANT_TIMBER) .. " Timber", function()
		deps.onLever("grantMaterials", Theme.COMBAT_DEBUG_GRANT_TIMBER)
	end)
	makeButton("Grant 10 Valor", function()
		deps.onLever("grantValor", VALOR_GRANT)
	end)
	makeButton("Fake runs ×3", function()
		deps.onLever("fakeRuns", FAKE_RUNS)
	end)

	local teleportButton: TextButton
	local function paintTeleportButton(): ()
		teleportButton.Text = if forceTeleportFailure then "Tele fail: ON" else "Tele fail: OFF"
		teleportButton.BackgroundColor3 = if forceTeleportFailure
			then Theme.COLOR_ERROR
			else Theme.COLOR_ROW
	end
	teleportButton = makeButton("Tele fail: OFF", function()
		forceTeleportFailure = not forceTeleportFailure
		paintTeleportButton()
		deps.onLever("forceTeleportFailure", forceTeleportFailure)
	end)
	paintTeleportButton()

	local fakePartyButton: TextButton
	local function paintFakePartyButton(): ()
		fakePartyButton.Text = if fakePartyCount >= FAKE_PARTY_MAX
			then "Clear fake party"
			else "Fake party +1 (" .. tostring(fakePartyCount) .. ")"
	end
	fakePartyButton = makeButton("Fake party +1 (0)", function()
		local nextCount = if fakePartyCount >= FAKE_PARTY_MAX then 0 else fakePartyCount + 1
		-- Optimistic so rapid taps step; the next PartyState overwrites it with the truth.
		fakePartyCount = nextCount
		paintFakePartyButton()
		deps.onLever("fakeParty", nextCount)
	end)
	paintFakePartyButton()
	makeButton("Fake invite", function()
		deps.onLever("fakeInvite", true)
	end)
	-- L3-28: the held family's next saved tier (the server clamps it into the window).
	local function tierButton(slot: "melee" | "ranged"): TextButton
		return makeButton("", function()
			local entry = held[slot]
			if entry ~= nil then
				deps.onLever("setTier", entry.family .. "=" .. tostring(entry.tier + 1))
			end
		end)
	end
	local meleeButton = tierButton("melee")
	local rangedButton = tierButton("ranged")
	local function paintTierButtons(): ()
		local melee, ranged = held.melee, held.ranged
		meleeButton.Text = if melee ~= nil
			then "Melee T" .. Format.Cash(melee.tier) .. " +1"
			else "Melee tier +1"
		rangedButton.Text = if ranged ~= nil
			then "Ranged T" .. Format.Cash(ranged.tier) .. " +1"
			else "Ranged tier +1"
	end
	paintTierButtons()
	makeButton(STAR_TEXT, function()
		deps.onLever("grantStar", STAR_ALL)
	end)
	makeButton("Reset Armory", function()
		deps.onLever("resetArmory", true)
	end)

	local rowCount = math.ceil(buttonCount / COLUMNS)
	local bodyHeight = rowCount * BUTTON_HEIGHT
		+ math.max(rowCount - 1, 0) * BUTTON_GAP
		+ BUTTON_GAP * 2
	local expandedHeight = bodyHeight + BUTTON_GAP + BUTTON_HEIGHT

	local function setExpanded(value: boolean): ()
		expanded = value
		body.Visible = value
		root.Size = UDim2.fromOffset(STRIP_WIDTH, if value then expandedHeight else BUTTON_HEIGHT)
		tab.Text = if value then "⚙ debug ▾" else "⚙ debug"
	end
	setExpanded(false)

	table.insert(
		connections,
		tab.Activated:Connect(function()
			SoundController.Play("uiClick")
			setExpanded(not expanded)
		end)
	)

	local handle: DebugPanelHandle = {
		-- The server consumes (and resets) the teleport-failure attribute on the next
		-- Depart, so the strip is told to drop the toggle rather than lie about it.
		SetForceTeleportFailure = function(value: boolean)
			if forceTeleportFailure == value then
				return
			end
			forceTeleportFailure = value
			paintTeleportButton()
		end,
		SetFakePartyCount = function(count: number)
			fakePartyCount = math.clamp(count, 0, FAKE_PARTY_MAX)
			paintFakePartyButton()
		end,
		SetTiers = function(melee: HeldTier?, ranged: HeldTier?)
			held.melee = melee
			held.ranged = ranged
			paintTierButtons()
		end,
		SetVisible = function(visible: boolean)
			root.Visible = visible
		end,
		SetLayout = function(scale: number)
			uiScale.Scale = scale
			-- UIScale multiplies size, not position offsets, so the offsets scale by hand;
			-- PANEL_BOTTOM_MARGIN is what keeps the strip clear of the bottom bar.
			root.Position =
				UDim2.new(0, Theme.SCREEN_MARGIN * scale, 1, -Theme.PANEL_BOTTOM_MARGIN * scale)
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
