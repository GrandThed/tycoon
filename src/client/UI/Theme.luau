--!strict
-- HUD look and feel: colors, fonts, pixel sizing for a 375x667 design canvas that one
-- UIScale per HUD component stretches to the real viewport, and (M3) every presentation
-- timing — tween durations, particle counts, auto-dismiss seconds, reduce-motion factors.
-- This is the only sanctioned home for such numbers on the client (docs/INTERFACES.md,
-- M3 "Presentation constants"); gameplay numbers always arrive through Catalog config and
-- server state, never from here.

local UserInputService = game:GetService("UserInputService")

-- Interactive element sizes are hoisted so MIN_SCALE can be derived from them below.
local TAP_TARGET_MIN = 44 -- spec section 10 minimum physical tap target
local BOTTOM_BAR_BUTTON_HEIGHT = 52
local CLOSE_BUTTON_SIZE = 48
local ROW_BUTTON_HEIGHT = 48
local LEVEL_BUTTON_HEIGHT = 52
local PRESTIGE_ROW_HEIGHT = 52
local DIALOG_BUTTON_HEIGHT = 48
local TOGGLE_HEIGHT = 48

-- Spec section 10: reduce motion on touch devices and on low-end signals. The low-end
-- signal is the player's saved graphics quality: anyone who has dialed quality down to
-- LOW_END_QUALITY_LEVEL or below (or whose device did it for them) gets shorter tweens
-- and no particles. Automatic (0) is not a signal. Read once at boot; pcall because
-- UserGameSettings is client-only and its surface has shifted before.
local LOW_END_QUALITY_LEVEL = 3
local function isLowEndDevice(): boolean
	local ok, level = pcall(function()
		return UserSettings():GetService("UserGameSettings").SavedQualityLevel.Value
	end)
	return ok and typeof(level) == "number" and level > 0 and level <= LOW_END_QUALITY_LEVEL
end

local Theme = {
	DESIGN_WIDTH = 375,
	DESIGN_HEIGHT = 667,
	-- M1 review decision: never let the scale clamp shrink the smallest tap target below
	-- 44 physical px (Roblox mobile is landscape-first; panels adapt their height instead
	-- of scaling the whole portrait canvas down). Ceiling stops comically large UI on
	-- desktop monitors.
	MIN_SCALE = TAP_TARGET_MIN / math.min(
		BOTTOM_BAR_BUTTON_HEIGHT,
		CLOSE_BUTTON_SIZE,
		ROW_BUTTON_HEIGHT,
		LEVEL_BUTTON_HEIGHT,
		PRESTIGE_ROW_HEIGHT,
		DIALOG_BUTTON_HEIGHT,
		TOGGLE_HEIGHT
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

	-- M3 bottom bar: Build / Legacy / Shop (hidden until M4) / Settings, centered.
	BOTTOM_BAR_BUTTON_WIDTH = 78,
	BOTTOM_BAR_BUTTON_HEIGHT = BOTTOM_BAR_BUTTON_HEIGHT,
	BOTTOM_BAR_GAP = 6,

	PANEL_WIDTH = 340,
	PANEL_HEIGHT = 430,
	PANEL_HEIGHT_COMPACT = 300, -- Legacy/Settings hold a handful of lines; no empty sheet
	PANEL_MIN_HEIGHT = 140, -- header + one row + paddings; floor for absurdly short viewports
	PANEL_BOTTOM_MARGIN = 76, -- clears the bottom bar below the panel
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
	-- M3: levelable rows grow to hold the ×1 / ×10 / Max strip under the name line.
	LEVEL_ROW_HEIGHT = 108,
	LEVEL_BUTTONS_Y = 50,
	LEVEL_BUTTON_HEIGHT = LEVEL_BUTTON_HEIGHT,
	LEVEL_BUTTON_GAP = 6,
	LEVEL_BUTTON_TITLE_Y = 5,
	LEVEL_BUTTON_COST_Y = 19,
	LEVEL_BUTTON_DELTA_Y = 33,
	DIM_TRANSPARENCY = 0.5, -- unaffordable buttons stay tappable but read as dimmed
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

	-- M3: Legacy + Settings panels.
	INFO_LINE_HEIGHT = 24,
	INFO_LINE_GAP = 6,
	SETTINGS_ROW_HEIGHT = 56,
	TOGGLE_WIDTH = 72,
	TOGGLE_HEIGHT = TOGGLE_HEIGHT,

	-- M3: era-advance screen. A fixed-aspect card that still fits a 320 px tall viewport
	-- at MIN_SCALE (340x300 -> 312x275 physical) so nothing clips in landscape.
	ERA_SCREEN_WIDTH = 340,
	ERA_SCREEN_HEIGHT = 300,
	ERA_SCREEN_PADDING = 14,
	ERA_SCREEN_GAP = 6,
	ERA_KICKER_HEIGHT = 14,
	ERA_TITLE_HEIGHT = 28,
	ERA_PREVIEW_HEIGHT = 44,
	ERA_COLUMNS_HEIGHT = 74,
	ERA_COLUMN_GAP = 10,
	ERA_LEGACY_LINE_HEIGHT = 22,

	-- M3: ceremony overlay.
	CEREMONY_SECONDS = 4,
	CEREMONY_FADE_SECONDS = 0.4,
	CEREMONY_TITLE_WIDTH = 330,
	CEREMONY_TITLE_HEIGHT = 150,
	CEREMONY_TITLE_START_SCALE = 0.85,
	CEREMONY_SCRIM_TRANSPARENCY = 0.2,

	-- M3: welcome-back card. Two heights: without and with the (M4) secondary offer.
	WELCOME_CARD_WIDTH = 312,
	WELCOME_CARD_HEIGHT = 92,
	WELCOME_CARD_OFFER_HEIGHT = 148,
	WELCOME_CARD_PADDING = 12,
	WELCOME_TITLE_HEIGHT = 20,
	WELCOME_BODY_HEIGHT = 34,
	WELCOME_SECONDS = 8,
	WELCOME_FADE_SECONDS = 0.25,

	-- M3: plot presentation (PlotVisualsController).
	REVEAL_WAIT_SECONDS = 2, -- WaitForChild timeout for the just-replicated building
	REVEAL_SECONDS = 0.45,
	REVEAL_START_SCALE = 0.05,
	REVEAL_PARTICLES = 14,
	LEVELUP_FLOAT_SECONDS = 1.1,
	LEVELUP_FLOAT_RISE = 4, -- studs the +N text rises
	LEVELUP_OFFSET_Y = 1.5, -- studs above the building's top where the text starts
	LEVELUP_BILLBOARD_WIDTH = 160,
	LEVELUP_BILLBOARD_HEIGHT = 44,
	LEVELUP_TEXT_SIZE = 24,
	LEVELUP_MILESTONE_TEXT_SIZE = 30,
	LEVELUP_HIGHLIGHT_SECONDS = 0.5,
	LEVELUP_HIGHLIGHT_FILL = 0.6,
	LEVELUP_PARTICLES = 8,
	PARTICLE_LIFETIME_MIN = 0.6,
	PARTICLE_LIFETIME_MAX = 1.2,
	PARTICLE_SPEED_MIN = 6,
	PARTICLE_SPEED_MAX = 12,
	PARTICLE_SIZE = 0.6,
	PARTICLE_SPREAD = 180,
	REDUCED_MOTION_FACTOR = 0.5,

	-- Sibling ZIndex tiers so modal layers never depend on instance creation order.
	ZINDEX_CARD = 15,
	ZINDEX_DIALOG = 20,
	ZINDEX_CEREMONY = 25,
	ZINDEX_TOAST = 30,

	TEXT_TITLE = 34,
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

	reducedMotion = UserInputService.TouchEnabled or isLowEndDevice(),
}

return Theme
