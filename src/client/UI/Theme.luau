--!strict
-- HUD look and feel: colors, fonts, and pixel sizing for a 375x667 design canvas that
-- one UIScale per HUD component stretches to the real viewport. These are UI-only
-- constants (sizing/padding is explicitly allowed in code); gameplay numbers always
-- arrive through Catalog config and server state, never from here.

local UserInputService = game:GetService("UserInputService")

-- Interactive element sizes are hoisted so MIN_SCALE can be derived from them below.
local TAP_TARGET_MIN = 44 -- spec section 10 minimum physical tap target
local BUILD_BUTTON_HEIGHT = 52
local CLOSE_BUTTON_SIZE = 48
local ROW_BUTTON_HEIGHT = 48
local PRESTIGE_ROW_HEIGHT = 52
local DIALOG_BUTTON_HEIGHT = 48

local Theme = {
	DESIGN_WIDTH = 375,
	DESIGN_HEIGHT = 667,
	-- M1 review decision: never let the scale clamp shrink the smallest tap target below
	-- 44 physical px (Roblox mobile is landscape-first; the panel adapts its height
	-- instead of scaling the whole portrait canvas down). Ceiling stops comically large
	-- UI on desktop monitors.
	MIN_SCALE = TAP_TARGET_MIN / math.min(
		BUILD_BUTTON_HEIGHT,
		CLOSE_BUTTON_SIZE,
		ROW_BUTTON_HEIGHT,
		PRESTIGE_ROW_HEIGHT,
		DIALOG_BUTTON_HEIGHT
	),
	MAX_SCALE = 1.8,
	TAP_TARGET_MIN = TAP_TARGET_MIN,
	SCREEN_MARGIN = 8,

	TOP_BAR_WIDTH = 352,
	TOP_BAR_HEIGHT = 56,
	ERA_BADGE_WIDTH = 118,
	-- M2: the income/legacy line splits the top-bar text column between these two widths.
	TOP_INCOME_WIDTH = 100,
	TOP_LEGACY_WIDTH = 96,

	BUILD_BUTTON_WIDTH = 148,
	BUILD_BUTTON_HEIGHT = BUILD_BUTTON_HEIGHT,

	PANEL_WIDTH = 340,
	PANEL_HEIGHT = 430,
	PANEL_MIN_HEIGHT = 140, -- header + one row + paddings; floor for absurdly short viewports
	PANEL_BOTTOM_MARGIN = 76, -- clears the Build button below the panel
	PANEL_SLIDE_OFFSET = 16,
	HEADER_HEIGHT = 48,
	CLOSE_BUTTON_SIZE = CLOSE_BUTTON_SIZE,
	ROW_HEIGHT = 64,
	ROW_BUTTON_WIDTH = 96,
	ROW_BUTTON_HEIGHT = ROW_BUTTON_HEIGHT,
	ROW_SPACING = 8,
	ROW_TEXT_LEFT = 10, -- left inset of the row's text column
	ROW_TEXT_GAP = 16, -- gap between the text column and the action button
	ROW_NAME_Y = 8,
	ROW_NAME_HEIGHT = 18,
	ROW_STATUS_Y = 28,
	ROW_PREVIEW_Y = 44,
	ROW_LINE_HEIGHT = 14, -- status/preview/cost line height
	BUTTON_TEXT_PAD = 4, -- horizontal inset of labels inside the action button
	BUTTON_TITLE_Y = 7, -- title offset when the button shows a second (cost) line
	BUTTON_TITLE_HEIGHT = 16,
	BUTTON_COST_Y = 25,
	PADDING = 12,
	CORNER_RADIUS = 12,
	ROW_CORNER_RADIUS = 8,
	STROKE_THICKNESS = 2,

	-- M2: prestige banner (Build panel), confirm dialog, toast.
	PRESTIGE_ROW_HEIGHT = PRESTIGE_ROW_HEIGHT,
	DIALOG_WIDTH = 320,
	DIALOG_PADDING = 16,
	DIALOG_LINE_GAP = 8,
	DIALOG_BUTTON_HEIGHT = DIALOG_BUTTON_HEIGHT,
	DIALOG_BUTTON_GAP = 10,
	DIALOG_BUTTON_TOP_GAP = 8,
	SCRIM_TRANSPARENCY = 0.45,
	TOAST_WIDTH = 312,
	TOAST_PADDING = 12,
	TOAST_GAP = 8, -- vertical gap between the top bar and the toast
	TOAST_SECONDS = 5,
	TOAST_ERROR_SECONDS = 2.5,
	TOAST_FADE_SECONDS = 0.25,
	-- Sibling ZIndex tiers so modal layers never depend on instance creation order.
	ZINDEX_DIALOG = 20,
	ZINDEX_TOAST = 30,

	TEXT_LARGE = 22,
	TEXT_HEADER = 17,
	TEXT_MEDIUM = 15,
	TEXT_SMALL = 12,

	FONT = Enum.Font.GothamMedium,
	FONT_BOLD = Enum.Font.GothamBold,

	COLOR_BG = Color3.fromRGB(24, 26, 32),
	COLOR_BG_LIGHT = Color3.fromRGB(45, 49, 60),
	COLOR_ROW = Color3.fromRGB(34, 37, 46),
	COLOR_ROW_LOCKED = Color3.fromRGB(28, 30, 37),
	COLOR_TEXT = Color3.fromRGB(235, 238, 245),
	COLOR_TEXT_DIM = Color3.fromRGB(148, 155, 170),
	COLOR_TEXT_DARK = Color3.fromRGB(16, 18, 22),
	COLOR_ACCENT = Color3.fromRGB(96, 190, 125),
	COLOR_ACCENT_ALT = Color3.fromRGB(92, 155, 235),
	COLOR_HIGHLIGHT = Color3.fromRGB(255, 200, 87),
	COLOR_ERROR = Color3.fromRGB(230, 92, 92),
	COLOR_SCRIM = Color3.fromRGB(0, 0, 0),
	BG_TRANSPARENCY = 0.08,

	FLASH_SECONDS = 0.5,
	OPEN_TWEEN_SECONDS = 0.15,
	ACTION_DEBOUNCE_SECONDS = 0.2,

	-- Spec section 10: reduce motion on touch devices. Low-end device heuristics arrive
	-- with the M3 presentation pass; TouchEnabled is the M1 signal.
	reducedMotion = UserInputService.TouchEnabled,
}

return Theme
