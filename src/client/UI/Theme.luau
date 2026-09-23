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
	-- M6 playtest: the legacy field reads "LEGACY <spendable> / <total>", so it takes the
	-- larger share of the 204 px text column and scales its text down (never below
	-- TOP_LEGACY_MIN_TEXT) before it would truncate.
	TOP_INCOME_WIDTH = 84,
	TOP_LEGACY_WIDTH = 120,
	TOP_LEGACY_MIN_TEXT = 9,
	-- C0: Gear Power ("⚔ 480") rides between income and Legacy on the same line, so the
	-- 204 px text column is re-split while it is visible. Without an Armory config the
	-- power label is hidden and the other two keep their pre-C0 widths, which makes a
	-- build with Expeditions switched off pixel-identical to M9.
	TOP_POWER_WIDTH = 54,
	TOP_POWER_GAP = 4,
	TOP_INCOME_WIDTH_POWER = 56,
	TOP_LEGACY_WIDTH_POWER = 84,
	TOP_POWER_MIN_TEXT = 9,

	-- M3 bottom bar: Build / Legacy / Shop (hidden until M4) / Settings, centered.
	BOTTOM_BAR_BUTTON_WIDTH = 78,
	BOTTOM_BAR_BUTTON_HEIGHT = BOTTOM_BAR_BUTTON_HEIGHT,
	BOTTOM_BAR_GAP = 6,
	-- C0 adds Armory and Expedition, so six keys must share a 375 px portrait canvas: each
	-- button is an icon glyph over a word that scales down instead of truncating, and the
	-- width shrinks with the number of visible keys. The floor is 48 design px because
	-- 48 x MIN_SCALE is exactly the 44 physical px tap target.
	BOTTOM_BAR_BUTTON_MIN_WIDTH = 48,
	BOTTOM_BAR_ICON_Y = 4,
	BOTTOM_BAR_ICON_HEIGHT = 20,
	BOTTOM_BAR_LABEL_Y = 26,
	BOTTOM_BAR_LABEL_HEIGHT = 16,
	BOTTOM_BAR_LABEL_MIN_TEXT = 8,

	PANEL_WIDTH = 340,
	-- M4 carry-over (a): in landscape the panel docks right while the top bar sits
	-- top-left, so on narrow viewports (640x360) the two overlapped by ~9 px. PanelDock
	-- clamps the docked width to what is left beside the top bar, down to this floor.
	PANEL_MIN_WIDTH = 260,
	PANEL_TOP_BAR_GAP = 8, -- clear space between the top bar and a landscape-docked panel
	PANEL_HEIGHT = 430,
	PANEL_HEIGHT_COMPACT = 300, -- Legacy/Settings hold a handful of lines; no empty sheet
	PANEL_MIN_HEIGHT = 140, -- header + one row + paddings; floor for absurdly short viewports
	PANEL_BOTTOM_MARGIN = 76, -- clears the bottom bar below the panel
	PANEL_SLIDE_OFFSET = 16,
	HEADER_HEIGHT = 48,
	-- M4 carry-over (c): the panel header's title insets, hoisted out of Panel.luau.
	PANEL_TITLE_INSET = 2, -- extra left inset so the title clears the sheet's corner radius
	PANEL_TITLE_TRIM = 16, -- gap kept between the title column and the close button
	CLOSE_BUTTON_SIZE = CLOSE_BUTTON_SIZE,
	ROW_HEIGHT = 64,
	ROW_BUTTON_WIDTH = 96,
	ROW_BUTTON_HEIGHT = ROW_BUTTON_HEIGHT,
	ROW_SPACING = 8,
	-- M4 carry-over (c): hoisted out of BuildPanel.luau.
	SCROLLBAR_THICKNESS = 4,
	EMPTY_LABEL_HEIGHT = 40,
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

	-- M4: Shop panel rows (Passes then Packs). One row height for both sections; only
	-- pack rows fill the third line with the predicted grant.
	SHOP_SECTION_HEIGHT = 22,
	SHOP_GRANT_Y = 30,
	-- The description spans the full row width UNDER the Buy button and sizes to its own
	-- content (wave-2 ruling): pack copy is owned by an agent with no view of these
	-- numbers, so the row grows with the text instead of clipping it at a fixed height.
	SHOP_DESC_Y = 58,
	SHOP_ROW_PAD_BOTTOM = 10,

	-- M6: Legacy shop rows (Perks then Cosmetics). Same silhouette as a Shop row: name,
	-- one "Tier n/N · next effect" line beside the Buy button, wrapped description under
	-- it. The header's breakdown row and softcap note use TEXT_SMALL because
	-- "Legacy ×19.10 · Perks ×1.16 · Passes ×2.42" overflows a 340 px sheet at TEXT_MEDIUM.
	PERK_TIER_Y = 30,
	PERK_DESC_Y = 58,
	PERK_ROW_PAD_BOTTOM = 10,
	PERK_NOTE_LINE_HEIGHT = 18,
	-- Gap between the pinned Legacy header block (total, spendable, breakdown, softcap)
	-- and the scrolling list beneath it (M6 playtest: the balance must never scroll away).
	LEGACY_HEADER_GAP = 8,

	-- C0 Armory panel: a pinned Max HP line plus one material chip per band above a list of
	-- weapon rows. A row is a Shop-style row (name, stats, Buy button) whose third line —
	-- "Tier 4 · 20 Steel · unlocks at 1K/s (you: 620/s)" — spans the full width under the
	-- button and wraps, so the row grows with the text instead of clipping it.
	ARMORY_MAX_HP_HEIGHT = 24,
	ARMORY_CHIP_HEIGHT = 40,
	ARMORY_CHIP_GAP = 6,
	ARMORY_CHIP_VALUE_Y = 18,
	ARMORY_CHIP_MIN_TEXT = 8,
	ARMORY_HEADER_GAP = 8,
	ARMORY_STAT_Y = 30,
	ARMORY_NEXT_Y = 50,
	ARMORY_ROW_PAD_BOTTOM = 10,

	-- C0 Expedition panel: mission tiles with the same silhouette, an Overdrive toggle above
	-- them and the "Active runs" list below. The list is refreshed by a RequestRunList intent
	-- on open and on this interval while the panel stays open (never when it is closed).
	EXPEDITION_META_Y = 30,
	EXPEDITION_POWER_Y = 46,
	EXPEDITION_TILE_PAD_BOTTOM = 10,
	EXPEDITION_RUNS_REFRESH_SECONDS = 10,
	EXPEDITION_RUN_ROW_HEIGHT = 56,
	-- Readiness colouring of "Recommended ⚔ N — you ⚔ M": green at or above the recommended
	-- power, amber within this fraction of it, red below.
	POWER_READY_RATIO = 1,
	POWER_RISKY_RATIO = 0.7,

	-- C2 hub party (ExpeditionPanel party strip + PartyInviteToast). Member, pending-invite
	-- and picker rows are one line tall with a 48 px action button (48 x MIN_SCALE = 44
	-- physical px). The countdowns on pending invites and on the invite card repaint on the
	-- tick; the deadline itself comes from the server's `expiresIn`.
	PARTY_ROW_HEIGHT = 52,
	PARTY_TICK_SECONDS = 1,
	PARTY_INVITE_CARD_WIDTH = 312,
	PARTY_INVITE_TITLE_HEIGHT = 20,
	PARTY_INVITE_BODY_HEIGHT = 36,
	PARTY_INVITE_GAP = 8,

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

	-- M7: stage growth pop on a milestone (PlotVisualsController) — shrink, overshoot,
	-- settle — and the Build panel's "grows at" hint. levelUp(milestone) and stageUp
	-- describe one crossing and arrive back to back, so the shared fanfare (sound, flash,
	-- burst) is played once per slot inside the dedupe window.
	STAGE_POP_SECONDS = 0.5,
	STAGE_POP_START_SCALE = 0.85,
	STAGE_POP_PEAK_SCALE = 1.08,
	STAGE_POP_PEAK_FRACTION = 0.6, -- share of STAGE_POP_SECONDS spent growing to the peak
	MILESTONE_FX_DEDUPE_SECONDS = 0.25,
	-- Level-row status fragments: (multiplier, level) / (level) / (multiplier, level) when
	-- the next income milestone and the next growth stage are the same level.
	MILESTONE_HINT_FORMAT = "×%s at Lv %d",
	GROW_HINT_FORMAT = "Grows at Lv %d",
	MILESTONE_GROW_HINT_FORMAT = "×%s & grows at Lv %d",

	-- Asset preload gate (PlotVisualsController): a freshly replicated template building or
	-- stage stays locally hidden until its meshes and textures load, but never longer than
	-- this, so a failed or slow download shows grey rather than nothing.
	ASSET_LOAD_TIMEOUT_SECONDS = 3,

	-- M9 city dressing (CityDressingController + src/client/City). Client-owned names only;
	-- every tunable lives in Config/CityDressing.json. The folder is created by the client and
	-- is never inside the server's Workspace/Plots, so server watchers never see dressing.
	CITY_DRESSING_FOLDER = "CityDressing",
	CITY_PLOT_FOLDER_PREFIX = "Plot",
	-- Startup waits for the first Snapshot so the local era's props preload before dressing,
	-- but never longer than this: a snapshot consumed before our listener connected (or a
	-- failed data load) must not leave every plot undressed.
	CITY_SNAPSHOT_WAIT_SECONDS = 5,

	-- M5: data-load safe-mode card (LoadScreen). The dim is lighter than a modal scrim
	-- because the world stays playable behind it (spec section 5).
	LOAD_CARD_WIDTH = 320,
	LOAD_SCRIM_TRANSPARENCY = 0.7,
	LOAD_SLOW_SECONDS = 8, -- "still working" line after this long in the loading phase
	LOAD_TICK_SECONDS = 0.25, -- countdown / slow-line refresh cadence
	LOAD_RETRY_ACK_SECONDS = 5, -- "Retrying…" re-arms to Retry if no status answers by then

	-- C0 combat place (src/combat/client): lobby/wave HUD and the summary card. The HP bar
	-- reads the local Humanoid, the party list mirrors RunState.party, and the tempo dot
	-- colours the director's pace — no combat input exists yet.
	COMBAT_TEMPO_DOT_SIZE = 14,
	COMBAT_TEMPO_CALM = 0.9, -- below this the director is holding back
	COMBAT_TEMPO_HOT = 1.3, -- at or above this it is merging waves
	COMBAT_HP_BAR_WIDTH = 200,
	COMBAT_HP_BAR_HEIGHT = 18,
	COMBAT_HP_LABEL_HEIGHT = 16,
	COMBAT_PARTY_WIDTH = 160,
	COMBAT_PARTY_ROW_HEIGHT = 34,
	COMBAT_PARTY_BAR_HEIGHT = 6,
	COMBAT_PARTY_NAME_HEIGHT = 16,
	COMBAT_SUMMARY_WIDTH = 320,
	-- Portrait cannot fit the HP block and both buttons on one line, so the HP block lifts
	-- above the button row whenever their combined design width does not fit.
	COMBAT_HP_BUTTONS_GAP = 8,

	-- C2 combat client (src/combat/client, ui-engineer A): co-op party rows, the waiting
	-- banner and party fx. Presentation only; every co-op number arrives in RunState/CombatFx.
	COMBAT_PARTY_SHARE_WIDTH = 36, -- right edge of a party row, fits "100%"
	COMBAT_PARTY_STATUS_HEIGHT = 14, -- "joins next wave" line that replaces a waiting HP bar
	-- Mid screen, under the tallest (4-row) party list in portrait and clear of both thumb
	-- corners at 375x667, 812x375 and 1920x1080.
	COMBAT_WAITING_TOP_FRACTION = 0.55,
	COMBAT_WAITING_WIDTH = 260,
	COMBAT_WAITING_HEIGHT = 40,
	COMBAT_WAITING_TOAST_COOLDOWN = 3, -- seconds between "waiting" refusal toasts
	-- Another player's swing: their weapon class is not sent, so one fixed pose window.
	COMBAT_REMOTE_SWING_SECONDS = 0.35,
	COMBAT_PARTY_RING_SECONDS = 0.6,
	COMBAT_PARTY_RING_TRANSPARENCY = 0.35,
	COMBAT_PARTY_PULSE_SECONDS = 0.5,
	COMBAT_PARTY_PULSE_FILL = 0.45,

	-- C1 combat controls. Touch-first: the attack button owns the bottom-right thumb arc,
	-- the two ability buttons stack immediately left of it and the stance pill sits above
	-- them. Every one of these is at or above TAP_TARGET_MIN / MIN_SCALE (44 / 0.9167 = 48
	-- design px), so nothing shrinks below a 44 physical px target on the smallest viewport.
	COMBAT_ATTACK_BUTTON_SIZE = 80,
	COMBAT_ABILITY_BUTTON_SIZE = 56,
	COMBAT_CONTROL_GAP = 8,
	COMBAT_STANCE_WIDTH = 116,
	COMBAT_STANCE_HEIGHT = 48,
	COMBAT_ABILITY_KEY_HEIGHT = 12,
	COMBAT_ABILITY_NAME_HEIGHT = 12,
	COMBAT_ABILITY_MIN_TEXT = 8,
	-- No image asset exists for a radial sweep (every id in the project is still 0), so a
	-- cooldown "ring" is a dark wipe that falls from the top of the round button plus the
	-- remaining whole seconds. Same information, zero assets.
	COMBAT_ABILITY_COOLDOWN_TRANSPARENCY = 0.35,

	-- Wallet strip (cash, mission material, Valor) under the run header, and the boss bar
	-- under that. Both are centred in portrait and left-aligned in landscape, like the header.
	COMBAT_WALLET_WIDTH = 352,
	COMBAT_WALLET_HEIGHT = 26,
	COMBAT_WALLET_GAP = 6,
	COMBAT_WALLET_MIN_TEXT = 9,
	COMBAT_BOSS_WIDTH = 300,
	COMBAT_BOSS_BAR_HEIGHT = 14,
	COMBAT_BOSS_LABEL_HEIGHT = 16,
	COMBAT_HEADER_TIMER_WIDTH = 74,
	COMBAT_PARTY_DOWN_TRANSPARENCY = 0.55,
	COMBAT_TIMER_TICK_SECONDS = 0.25,

	-- C1 feedback (CombatFxController). Durations that the server owns arrive in
	-- Combat.json `feedback`; only the presentation shape lives here.
	COMBAT_DAMAGE_TEXT_SIZE = 20,
	COMBAT_DAMAGE_FINISHER_TEXT_SIZE = 30,
	COMBAT_DAMAGE_BILLBOARD_WIDTH = 140,
	COMBAT_DAMAGE_BILLBOARD_HEIGHT = 40,
	COMBAT_DAMAGE_RISE = 4.5,
	COMBAT_DAMAGE_JITTER = 1.2, -- studs of sideways offset so stacked numbers stay readable
	COMBAT_DAMAGE_MAX_ACTIVE = 24, -- a merged wave can land dozens of hits in one frame
	COMBAT_KILL_PARTICLES = 10,
	COMBAT_HIT_HIGHLIGHT_SECONDS = 0.16,
	COMBAT_HIT_HIGHLIGHT_FILL = 0.55,
	COMBAT_TELL_HIGHLIGHT_FILL = 0.75,
	COMBAT_KNOCKBACK_STUDS = 1.6,
	COMBAT_KNOCKBACK_SECONDS = 0.18,
	COMBAT_CAMERA_KICK_DECAY = 9, -- per second; the kick is gone inside ~0.2 s
	COMBAT_ABILITY_RING_SECONDS = 0.35,
	COMBAT_ABILITY_RING_HEIGHT = 0.4,
	COMBAT_BANNER_WIDTH = 340,
	COMBAT_BANNER_HEIGHT = 58,
	COMBAT_BANNER_TEXT = 28,
	COMBAT_BANNER_SUB_TEXT = 14,
	COMBAT_BANNER_TOP_FRACTION = 0.22,
	-- Vignette: four edge bars with a UIGradient fade, because there is no vignette image
	-- asset. Pulses while the local HP is under feedback.lowHpFraction.
	COMBAT_VIGNETTE_THICKNESS = 96,
	COMBAT_VIGNETTE_TRANSPARENCY = 0.35,
	COMBAT_VIGNETTE_PULSE_SECONDS = 1.1,
	COMBAT_HURT_FLASH_TRANSPARENCY = 0.75,
	COMBAT_HURT_FLASH_SECONDS = 0.25,

	-- C1 weapon visuals (WeaponController): procedural Motor6D poses on the local rig and a
	-- tracer per shot. Angles are degrees; the pose engine converts.
	COMBAT_SWING_WINDUP_FRACTION = 0.35, -- share of the class window spent winding up
	COMBAT_SWING_WINDUP_DEGREES = -55,
	COMBAT_SWING_STRIKE_DEGREES = 95,
	COMBAT_SWING_SETTLE_SECONDS = 0.12,
	COMBAT_DRAW_DEGREES = 80,
	COMBAT_SHOOT_KICK_DEGREES = 25,
	COMBAT_SHOOT_KICK_SECONDS = 0.1,
	COMBAT_TRACER_SECONDS = 0.06,
	COMBAT_BEAM_SECONDS = 0.16,
	COMBAT_TRACER_WIDTH = 0.12,
	COMBAT_BEAM_WIDTH = 0.35,
	COMBAT_WEAPON_WAIT_SECONDS = 3, -- WaitForChild budget for the hand and the prop folder
	-- Grip placement of a weapon prop in the right hand. No weapon prop has been authored
	-- yet (empty hands are the shipped C1 default), so these are the neutral "held blade"
	-- values a first prop will be modelled against, not measurements.
	COMBAT_GRIP_FORWARD = 0.6,
	COMBAT_GRIP_UP = -0.4,
	COMBAT_GRIP_PITCH_DEGREES = -90,

	-- C1 input. The dash a burst ability performs locally; the server already resolved the
	-- damage along the same segment, so this is presentation that never changes a hit.
	COMBAT_DASH_SECONDS = 0.18,
	COMBAT_DASH_MAX_FORCE = 100000,
	COMBAT_REMOTE_WAIT_SECONDS = 10, -- a remote C1 adds may be missing in an older build
	-- Workspace/Enemies is built by ArenaService at server boot, so it is normally already
	-- replicated; the budget only covers a slow join. Missing means "safe mode, no arena".
	COMBAT_ARENA_WAIT_SECONDS = 20,

	-- C1 Studio debug strip. Parked mid-left, the one screen edge no HUD element uses in
	-- either orientation.
	-- Rows are 48 design px like the hub's DebugPanel, because 48 x MIN_SCALE is exactly
	-- the 44 physical px tap target; the strip wraps into two columns and scrolls rather
	-- than scaling itself down to fit a short landscape viewport.
	COMBAT_DEBUG_WIDTH = 196,
	COMBAT_DEBUG_ROW_HEIGHT = 48,
	COMBAT_DEBUG_GAP = 6,
	COMBAT_DEBUG_COLUMNS = 2,
	COMBAT_DEBUG_TOGGLE_SIZE = 48,
	COMBAT_DEBUG_TEXT = 11,
	COMBAT_DEBUG_GRANT_MATERIALS = 25,
	COMBAT_DEBUG_GRANT_VALOR = 10,
	COMBAT_DEBUG_MAX_SPAWN_KEYS = 3,

	-- Sibling ZIndex tiers so modal layers never depend on instance creation order.
	ZINDEX_CARD = 15,
	ZINDEX_DIALOG = 20,
	ZINDEX_LOAD = 22, -- above dialogs (none can open without a model), below toasts
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
	-- Particles and ambient city life drop only on this, not on touch alone (spec section 10).
	lowEndDevice = isLowEndDevice(),
}

return Theme
