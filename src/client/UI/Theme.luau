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
-- L3 W1's Armory screen: its tabs and close button, its detail buttons and Buy, its shelf cards
-- (at least 68 wide, so the height is the small side).
local ARMORY_SCREEN_HEADER_HEIGHT = 48
local ARMORY_SCREEN_BUTTON_HEIGHT = 48
local ARMORY_SCREEN_CARD_HEIGHT = 56
-- The smallest label text that still reads at MIN_SCALE (7.3 physical px): the bottom bar's
-- words and the Armory shelf's names shrink to this and never further.
local LABEL_MIN_TEXT = 8

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
		TOGGLE_HEIGHT,
		ARMORY_SCREEN_HEADER_HEIGHT,
		ARMORY_SCREEN_BUTTON_HEIGHT,
		ARMORY_SCREEN_CARD_HEIGHT
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
	BOTTOM_BAR_LABEL_MIN_TEXT = LABEL_MIN_TEXT,

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

	-- The smallest text a squeezed chip label may scale down to (C0's Armory panel chips, now
	-- the hub's debug strip).
	ARMORY_CHIP_MIN_TEXT = 8,

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
	-- C2.5: one right-thumb cluster; the attack button grew (the thumb's resting target) and
	-- the stance pill became a round button on the arc between the two abilities.
	COMBAT_ATTACK_BUTTON_SIZE = 88,
	COMBAT_ABILITY_BUTTON_SIZE = 56,
	COMBAT_CONTROL_GAP = 8,
	COMBAT_STANCE_SIZE = 52,
	COMBAT_STANCE_GLYPH_TEXT = 20,
	COMBAT_CLUSTER_GAP = 10, -- ring gap between the attack button and its satellites
	COMBAT_CLUSTER_STROKE_TRANSPARENCY = 0.6,
	-- Roblox's touch jump button, mirrored from the PlayerModule's TouchJump sizing so the
	-- cluster never covers it: small screens (shorter side <= 500 px) get a 70 px button
	-- 95 px from the right and 90 px from the bottom, larger ones 120 px, 170 / 210 px in.
	COMBAT_JUMP_SMALL_AXIS = 500,
	COMBAT_JUMP_SMALL_SIZE = 70,
	COMBAT_JUMP_LARGE_SIZE = 120,
	COMBAT_JUMP_RIGHT_FACTOR = 1.5,
	COMBAT_JUMP_RIGHT_TRIM = 10,
	COMBAT_JUMP_SMALL_BOTTOM_PAD = 20,
	COMBAT_JUMP_LARGE_BOTTOM_FACTOR = 1.75,
	COMBAT_ALT_HINT_HEIGHT = 16,
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
	COMBAT_ABILITY_RING_TRANSPARENCY = 0.4,
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
	COMBAT_BEAM_SECONDS = 0.16,
	COMBAT_BEAM_WIDTH = 0.35,
	COMBAT_FINISHER_STRIKE_MULT = 1.25, -- the finisher's pose travels further than a slash
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
	COMBAT_AIM_MIN_STUDS = 1, -- a crosshair point closer than this to the head aims along the view
	COMBAT_DASH_MAX_FORCE = 100000,
	COMBAT_REMOTE_WAIT_SECONDS = 10, -- a remote C1 adds may be missing in an older build
	-- Workspace/Enemies is built by ArenaService at server boot, so it is normally already
	-- replicated; the budget only covers a slow join. Missing means "safe mode, no arena".
	COMBAT_ARENA_WAIT_SECONDS = 20,

	-- C2.5 shoulder camera (CameraController). Config owns offset, FOV, zoom range and the
	-- per-device sensitivities; these are the feel of the rig itself. Rotation rates follow the
	-- stock PlayerModule (0.5 deg per mouse px, 240 deg/s on a full stick) so the camera feels
	-- familiar; pitch runs a bit slower than yaw, as there.
	COMBAT_CAMERA_PIVOT_HEIGHT = 1.5, -- studs above the root: head height on an R15 rig
	COMBAT_CAMERA_START_PITCH_DEGREES = -12,
	COMBAT_CAMERA_MIN_PITCH_DEGREES = -70,
	COMBAT_CAMERA_MAX_PITCH_DEGREES = 55,
	COMBAT_CAMERA_MOUSE_DEGREES_PER_PIXEL = 0.5,
	COMBAT_CAMERA_TOUCH_DEGREES_PER_PIXEL = 0.4,
	COMBAT_CAMERA_GAMEPAD_DEGREES_PER_SECOND = 240,
	COMBAT_CAMERA_GAMEPAD_DEADZONE = 0.2,
	COMBAT_CAMERA_PITCH_RATIO = 0.77,
	COMBAT_CAMERA_ZOOM_RATE = 12, -- per second, towards the target zoom
	COMBAT_CAMERA_WHEEL_STEP = 1.5, -- studs per wheel notch
	COMBAT_CAMERA_TOUCH_SPLIT = 0.5, -- touches starting right of this viewport fraction aim
	COMBAT_CAMERA_COLLISION_RADIUS = 0.5,
	COMBAT_CAMERA_COLLISION_PAD = 0.2,
	-- Trauma shake: feel.shakeLight / shakeHeavy add trauma (0-1); the view moves by trauma
	-- squared times these maxima and trauma drains at the decay rate.
	COMBAT_SHAKE_MAX_DEGREES = 3,
	COMBAT_SHAKE_MAX_STUDS = 0.35,
	COMBAT_SHAKE_ROLL_RATIO = 0.5,
	COMBAT_SHAKE_FREQUENCY = 18,
	COMBAT_SHAKE_DECAY_PER_SECOND = 2.2,
	COMBAT_FINISHER_KICK_MULT = 1.6,

	-- C2.5 reticle (CombatHud): centre crosshair, hit marker and the bow's draw ring, in
	-- design px scaled with the HUD.
	COMBAT_RETICLE_SIZE = 72,
	COMBAT_CROSSHAIR_LENGTH = 8,
	COMBAT_CROSSHAIR_THICKNESS = 2,
	COMBAT_CROSSHAIR_GAP = 5,
	COMBAT_RETICLE_STROKE_TRANSPARENCY = 0.5,
	COMBAT_HIT_MARKER_OFFSET = 12,
	COMBAT_HIT_MARKER_LENGTH = 8,
	COMBAT_CHARGE_RING_DOTS = 20,
	COMBAT_CHARGE_RING_RADIUS = 26,
	COMBAT_CHARGE_DOT_SIZE = 5,
	COMBAT_CHARGE_DOT_IDLE_TRANSPARENCY = 0.7,

	-- C2.5 weapon feel (WeaponController): swing trail, animation fit, shots in flight.
	COMBAT_TRAIL_NEAR = 0.3, -- studs down the hand's -Y (toward the fingers)
	COMBAT_TRAIL_FAR = 2.8, -- an empty hand still draws a blade-length arc
	COMBAT_TRAIL_LIGHT_EMISSION = 0.6,
	COMBAT_TRAIL_TRANSPARENCY = 0.25,
	COMBAT_ANIMATION_FADE_SECONDS = 0.05,
	COMBAT_ANIMATION_MIN_SPEED = 0.6,
	COMBAT_ANIMATION_MAX_SPEED = 3,
	COMBAT_ARROW_COLOR = Color3.fromRGB(150, 110, 70),
	COMBAT_ARROW_LENGTH = 2.4,
	COMBAT_ARROW_THICKNESS = 0.12,
	COMBAT_ARROW_TRAIL_WIDTH = 0.06,
	COMBAT_ARROW_TRAIL_SECONDS = 0.12,
	COMBAT_ARROW_STICK_SECONDS = 1,
	COMBAT_BOLT_LENGTH = 3,
	COMBAT_BOLT_THICKNESS = 0.1,
	-- Gun bolts fly this many times feel.arrowSpeed: a bullet slower than an arrow reads wrong.
	COMBAT_BOLT_SPEED_FACTOR = 3,
	COMBAT_PROJECTILE_FADE_SECONDS = 0.3,
	COMBAT_PROJECTILE_CLAIM_RADIUS = 5, -- studs off a shot's line a hit may be and still be its
	COMBAT_HIT_DELAY_MAX_SECONDS = 0.4, -- a hit is never shown later than this after the server
	COMBAT_MUZZLE_FLASH_SIZE = 0.6,
	COMBAT_MUZZLE_FLASH_GROWTH = 2,
	COMBAT_MUZZLE_FLASH_TRANSPARENCY = 0.15,
	COMBAT_MUZZLE_FLASH_SECONDS = 0.07,
	COMBAT_MUZZLE_LIGHT_BRIGHTNESS = 3,
	COMBAT_MUZZLE_LIGHT_RANGE = 10,

	-- C2.5 impact and telegraphs (CombatFxController). Counts come from feel.hitSparkCount;
	-- these shape the spray.
	COMBAT_SPARK_SURFACE_OFFSET = 0.8, -- studs back toward the attacker from the enemy root
	COMBAT_SPARK_LIFETIME_MIN = 0.12,
	COMBAT_SPARK_LIFETIME_MAX = 0.3,
	COMBAT_SPARK_SPEED_MIN = 14,
	COMBAT_SPARK_SPEED_MAX = 28,
	COMBAT_SPARK_SPREAD = 35,
	COMBAT_SPARK_GRAVITY = 40,
	COMBAT_SPARK_DRAG = 4,
	COMBAT_SPARK_SIZE = 0.25,
	COMBAT_KILL_POP_START = 0.6,
	COMBAT_KILL_POP_END = 4,
	COMBAT_KILL_POP_SECONDS = 0.18,
	COMBAT_KILL_POP_TRANSPARENCY = 0.3,
	-- Warmer and brighter than the red attack tell, so "about to hit" reads apart from it.
	COMBAT_TELEGRAPH_COLOR = Color3.fromRGB(255, 120, 60),
	COMBAT_TELEGRAPH_SUMMON_COLOR = Color3.fromRGB(170, 100, 235),
	COMBAT_TELEGRAPH_HIGHLIGHT_FILL = 0.35,
	COMBAT_TELEGRAPH_AREA_TRANSPARENCY = 0.75,
	COMBAT_TELEGRAPH_FILL_TRANSPARENCY = 0.4,
	COMBAT_TELEGRAPH_THICKNESS = 0.1,
	COMBAT_TELEGRAPH_LIFT = 0.05, -- studs above the floor, doubled for the fill on top
	COMBAT_TELEGRAPH_MIN_SIZE = 0.2,
	COMBAT_TELEGRAPH_LINGER_SECONDS = 0.12,
	COMBAT_TELEGRAPH_GROUND_PROBE = 12,
	COMBAT_TELEGRAPH_FLOOR_Y = 0, -- arena floor top face, when the probe finds nothing
	-- Used only when the server omits a radius; the server's number is the real one.
	COMBAT_TELEGRAPH_DEFAULT_RADIUS = 10,
	COMBAT_TELEGRAPH_DEFAULT_HALF_WIDTH = 2.5,
	COMBAT_TELEGRAPH_SUMMON_RADIUS = 6,
	COMBAT_TELEGRAPH_MARK_SIZE = 44,
	COMBAT_TELEGRAPH_MARK_RISE = 2.2,

	-- P1 Proving Grounds feedback (FeedbackController, Crosshair, RangePanel). There is no
	-- sound, so every hit must be seen. How strong each layer is comes from
	-- ProvingGrounds.json `feedback.*` through Tuning (0 = off); these are only the shape of
	-- each layer at strength 1.
	-- Crosshair: a centre dot, four ticks pushed out by the live bloom, the bloom ring for
	-- ranged weapons, and the hit / crit / kill markers.
	COMBAT_RANGE_CROSSHAIR_SIZE = 120,
	COMBAT_RANGE_CROSSHAIR_DOT = 4,
	COMBAT_RANGE_CROSSHAIR_TICK_LENGTH = 9,
	COMBAT_RANGE_CROSSHAIR_TICK_THICKNESS = 2,
	COMBAT_RANGE_CROSSHAIR_MIN_GAP = 5, -- design px; bloom never pulls the ticks closer
	COMBAT_RANGE_CROSSHAIR_MAX_GAP = 56, -- half the crosshair box
	COMBAT_RANGE_CROSSHAIR_MELEE_GAP = 10, -- fixed tick gap for a melee weapon (no bloom)
	COMBAT_RANGE_BLOOM_RING_TRANSPARENCY = 0.55,
	COMBAT_RANGE_MARKER_OFFSET = 9,
	COMBAT_RANGE_MARKER_LENGTH = 10,
	COMBAT_RANGE_MARKER_THICKNESS = 3,
	COMBAT_RANGE_MARKER_SECONDS = 0.2,
	COMBAT_RANGE_CRIT_MARKER_SCALE = 1.5,
	COMBAT_RANGE_KILL_X_LENGTH = 30,
	COMBAT_RANGE_KILL_X_THICKNESS = 4,
	COMBAT_RANGE_KILL_X_SECONDS = 0.4,
	COMBAT_RANGE_KICK_SCALE = 1.35, -- the reticle's pop on a hit, at hitMarker strength 1
	COMBAT_RANGE_KICK_SECONDS = 0.12,
	COMBAT_RANGE_MARKER_MIN_SCALE = 0.5,
	COMBAT_RANGE_MARKER_MAX_SCALE = 2,
	COMBAT_RANGE_CRIT_COLOR = Color3.fromRGB(255, 214, 64), -- Fortnite-style crit yellow
	COMBAT_RANGE_KILL_COLOR = Color3.fromRGB(240, 70, 70),
	-- Damage numbers: ONE burst per strike (total + "×N") that pops, arcs up and falls.
	COMBAT_RANGE_NUMBER_WIDTH = 190,
	COMBAT_RANGE_NUMBER_HEIGHT = 64,
	COMBAT_RANGE_NUMBER_TEXT = 26,
	COMBAT_RANGE_NUMBER_CRIT_TEXT = 32,
	COMBAT_RANGE_NUMBER_GROWTH_PER_DOUBLING = 3, -- text px added each time the hit count doubles
	COMBAT_RANGE_NUMBER_MAX_TEXT = 44,
	COMBAT_RANGE_NUMBER_COUNT_TEXT = 16,
	COMBAT_RANGE_NUMBER_POP_SCALE = 1.8,
	COMBAT_RANGE_NUMBER_REDUCED_POP_SCALE = 1.3,
	COMBAT_RANGE_NUMBER_POP_SECONDS = 0.1,
	COMBAT_RANGE_NUMBER_SECONDS = 0.8,
	COMBAT_RANGE_NUMBER_RISE = 3, -- studs; the arc peaks at ~0.6 of this and ends below the start
	COMBAT_RANGE_NUMBER_DRIFT = 1.5, -- studs sideways over the life of the burst
	COMBAT_RANGE_NUMBER_FADE_FROM = 0.6, -- share of the life spent fully opaque
	COMBAT_RANGE_NUMBER_HEAD_CLEARANCE = 1, -- studs above the tallest hit body
	COMBAT_RANGE_NUMBER_FALLBACK_HEIGHT = 5, -- when the renderer has no body to measure
	COMBAT_RANGE_NUMBER_MAX_ACTIVE = 12,
	COMBAT_RANGE_NUMBER_MIN_STRENGTH = 0.5,
	COMBAT_RANGE_NUMBER_MAX_STRENGTH = 2,
	-- Hitbox effect: the strike's exact shape, drawn as neon parts for ~0.15 s.
	COMBAT_RANGE_HITBOX_SECONDS = 0.15,
	COMBAT_RANGE_HITBOX_MAX_SECONDS = 0.6,
	COMBAT_RANGE_HITBOX_HOLD_FRACTION = 0.35, -- fully shown before the fade starts
	COMBAT_RANGE_HITBOX_COLOR = Color3.fromRGB(255, 244, 214),
	COMBAT_RANGE_HITBOX_CRIT_COLOR = Color3.fromRGB(255, 214, 64),
	COMBAT_RANGE_HITBOX_EDGE_WIDTH = 0.45,
	COMBAT_RANGE_HITBOX_EDGE_TRANSPARENCY = 0.05,
	COMBAT_RANGE_HITBOX_FILL_TRANSPARENCY = 0.72,
	COMBAT_RANGE_HITBOX_SPHERE_TRANSPARENCY = 0.85,
	COMBAT_RANGE_HITBOX_THICKNESS = 0.08,
	COMBAT_RANGE_HITBOX_SEGMENT_DEGREES = 10,
	COMBAT_RANGE_HITBOX_LOW_END_SEGMENT_DEGREES = 20,
	COMBAT_RANGE_HITBOX_GROW_FROM = 0.7, -- a sphere shockwave grows from this share of its size
	COMBAT_RANGE_HITBOX_DEFAULT_WIDTH = 1, -- capsule / ray with no width in the strike
	COMBAT_RANGE_CONE_SPOKES = 8,
	COMBAT_RANGE_TRACER_WIDTH = 0.3,
	COMBAT_RANGE_TRACER_COLOR = Color3.fromRGB(255, 236, 170),
	COMBAT_RANGE_IMPACT_SIZE = 1.4,
	COMBAT_RANGE_PELLET_IMPACT_SIZE = 0.6, -- where a cosmetic pellet tracer stops
	-- A refused attack greys the crosshair once, for this long.
	COMBAT_RANGE_REFUSED_COLOR = Color3.fromRGB(128, 128, 128),
	COMBAT_RANGE_REFUSED_SECONDS = 0.25,
	-- P3.1: a swing drawn and predicted on the swinger's own client waits this long for the
	-- strike or refusal that answers it; past that the server dropped it without a word.
	COMBAT_RANGE_SWING_ANSWER_SECONDS = 2,
	-- The server pulls back a swing origin that lag cannot explain. An early effect drawn
	-- further than this (studs) from where the strike resolved is replaced by the strike's.
	COMBAT_RANGE_SWING_ORIGIN_TOLERANCE = 0.5,
	COMBAT_RANGE_TRAIL_MIN_STUDS = 3, -- a launcher trail is drawn only past this distance
	-- P2 projectiles in flight (CombatFxShot) and the bow effects on their strikes.
	COMBAT_RANGE_SHELL_SIZE = 0.9,
	COMBAT_RANGE_SHELL_COLOR = Color3.fromRGB(70, 72, 80),
	COMBAT_RANGE_SHELL_TRAIL_COLOR = Color3.fromRGB(205, 205, 210),
	COMBAT_RANGE_ARROW_LENGTH = 2.6,
	COMBAT_RANGE_ARROW_THICKNESS = 0.14,
	COMBAT_RANGE_ARROW_COLOR = Color3.fromRGB(230, 214, 184),
	COMBAT_RANGE_ARROW_TRAIL_WIDTH = 0.3,
	COMBAT_RANGE_ARROW_GLOW_TRAIL_WIDTH = 0.7,
	COMBAT_RANGE_ARROW_TRAIL_SECONDS = 0.22,
	COMBAT_RANGE_ARROW_TRAIL_TRANSPARENCY = 0.1,
	COMBAT_RANGE_ARROW_LIGHT_BRIGHTNESS = 3,
	COMBAT_RANGE_ARROW_LIGHT_RANGE = 10,
	COMBAT_RANGE_CHARGE_COLOR = Color3.fromRGB(255, 196, 56), -- full draw: arrow, ring, blast
	COMBAT_RANGE_FLIGHT_BLEND_SECONDS = 0.12, -- the shaft eases from the hand onto the aim path
	COMBAT_RANGE_FLIGHT_SLACK_SECONDS = 0.5, -- past range / speed before a flight times out
	-- The fallback split waits this long past splitDistance / speed for the server's split shot.
	COMBAT_RANGE_SPLIT_GRACE_SECONDS = 0.25,
	-- Studs beyond the arrow's width + pad in which a blast strike's hit counts as pierced.
	COMBAT_RANGE_PIERCE_TUBE_PAD = 1.5,
	COMBAT_RANGE_PIERCE_SHARDS = 4,
	COMBAT_RANGE_PIERCE_SPREAD_DEGREES = 30,
	COMBAT_RANGE_PIERCE_SHARD_LENGTH = 1.8,
	COMBAT_RANGE_PIERCE_SPARKS = 8,
	COMBAT_RANGE_BLAST_COLOR = Color3.fromRGB(255, 150, 60),
	COMBAT_RANGE_BLAST_CORE_SCALE = 0.45, -- core flash diameter as a share of the blast's
	COMBAT_RANGE_BLAST_SPARKS = 30,
	COMBAT_RANGE_BLAST_LIGHT_BRIGHTNESS = 6,
	COMBAT_RANGE_BLAST_SECONDS = 0.35,
	COMBAT_RANGE_THRUST_WIDTH = 0.4, -- the spear's streak; speed lines are half as wide
	COMBAT_RANGE_THRUST_LINE_OFFSET = 0.6, -- speed lines sit this share of the radius aside
	-- Draw-charge ring around the crosshair (bows): dots fill clockwise, gold when full.
	COMBAT_RANGE_CHARGE_DOTS = 24,
	COMBAT_RANGE_CHARGE_RADIUS = 24,
	COMBAT_RANGE_CHARGE_DOT_SIZE = 4,
	COMBAT_RANGE_CHARGE_IDLE_TRANSPARENCY = 0.75,
	COMBAT_RANGE_CHARGE_FULL_SCALE = 1.15,
	COMBAT_RANGE_FX_POOL_MAX = 600,
	COMBAT_RANGE_FX_FOLDER = "RangeFx",
	-- Wireframe (RangePanel toggle): the true padded shape the server tests, held longer.
	COMBAT_RANGE_WIRE_COLOR = Color3.fromRGB(80, 230, 255),
	COMBAT_RANGE_WIRE_THICKNESS = 0.12,
	COMBAT_RANGE_WIRE_SECONDS = 0.8,
	COMBAT_RANGE_WIRE_TRANSPARENCY = 0.1,
	COMBAT_RANGE_WIRE_CIRCLE_SEGMENTS = 28,
	-- Screen layer: hitstop grows with the number of enemies hit, shake and haptics are
	-- heavier on kills and heavy weapons, the edge flash marks a crowd kill.
	COMBAT_RANGE_HITSTOP_BASE = 0.035,
	COMBAT_RANGE_HITSTOP_PER_HIT = 0.007,
	COMBAT_RANGE_HITSTOP_MAX = 0.12,
	COMBAT_RANGE_SHAKE_LIGHT = 0.12,
	COMBAT_RANGE_SHAKE_PER_KILL = 0.05,
	COMBAT_RANGE_SHAKE_HEAVY = 0.45,
	COMBAT_RANGE_HEAVY_KNOCKBACK = 20, -- a weapon knocking back at least this is "heavy"
	COMBAT_RANGE_EDGE_FLASH_KILLS = 5,
	COMBAT_RANGE_EDGE_FLASH_TRANSPARENCY = 0.35,
	COMBAT_RANGE_EDGE_FLASH_SECONDS = 0.35,
	COMBAT_RANGE_EDGE_FLASH_THICKNESS = 140,
	COMBAT_RANGE_HAPTIC_LIGHT = 0.25,
	COMBAT_RANGE_HAPTIC_HEAVY = 0.7,
	COMBAT_RANGE_HAPTIC_SECONDS = 0.07,
	COMBAT_RANGE_HAPTIC_HEAVY_SECONDS = 0.14,
	-- P3: hitstop never exceeds this share of a weapon's attack interval, so a 12/s SMG does
	-- not freeze the rig for 40% of every second.
	COMBAT_RANGE_HITSTOP_INTERVAL_SHARE = 0.3,
	-- P3 lasting hits (tick strikes of zones, channels, sweeps, and every held-beam strike): no
	-- hitstop, a softer shake and pulse, and ONE running damage burst per shooter + ability
	-- instead of one per tick. The next tick joins the open burst while it arrives within the
	-- tick interval plus MERGE_SECONDS; a burst that has been open MERGE_MAX_SECONDS closes and
	-- falls, so a long channel still pops a new number every so often.
	COMBAT_RANGE_TICK_MERGE_SECONDS = 0.25,
	COMBAT_RANGE_TICK_MERGE_MAX_SECONDS = 1.2,
	COMBAT_RANGE_TICK_POP_SCALE = 1.25,
	COMBAT_RANGE_TICK_REDUCED_POP_SCALE = 1.1,
	COMBAT_RANGE_TICK_SHAKE_SCALE = 0.25,
	COMBAT_RANGE_TICK_HAPTIC_SCALE = 0.5,
	COMBAT_RANGE_NUMBER_FOLLOW_RATE = 10, -- per second: an open burst drifts to its latest hits
	-- A held beam marks the crosshair (and pulses) at most this often; a kill always marks.
	COMBAT_RANGE_BEAM_MARKER_SECONDS = 0.2,
	-- P3 ability colour block, shared with AbilityFx so a lasting area and the hits it lands
	-- read as one thing. ABILITY = the hitbox effect of one-off ability strikes (earthquake rings,
	-- landings, dash, slug cones, the overcharged ray, cluster blasts); crits stay crit yellow.
	COMBAT_RANGE_ABILITY_COLOR = Color3.fromRGB(130, 205, 255),
	COMBAT_RANGE_ABILITY_RAY_CORE_WIDTH = 0.5, -- bright core inside an ability ray's full-width tube
	COMBAT_RANGE_LIGHTNING_COLOR = Color3.fromRGB(140, 200, 255),
	COMBAT_RANGE_LIGHTNING_CORE_COLOR = Color3.fromRGB(240, 248, 255),
	COMBAT_RANGE_BEAM_COLOR = Color3.fromRGB(90, 220, 255),
	COMBAT_RANGE_BEAM_CORE_COLOR = Color3.fromRGB(235, 252, 255),
	-- Chain lightning (Chain Gun, Storm Coil): one jagged bolt per link, held ~0.15 s. A bolt
	-- kinks every KINK_STUDS (at most MAX_KINKS), sideways by up to JITTER studs, or JITTER_SHARE
	-- of a short bolt's length.
	COMBAT_RANGE_LIGHTNING_SECONDS = 0.15,
	COMBAT_RANGE_LIGHTNING_WIDTH = 0.18,
	COMBAT_RANGE_LIGHTNING_GLOW_WIDTH = 0.55,
	COMBAT_RANGE_LIGHTNING_GLOW_TRANSPARENCY = 0.6,
	COMBAT_RANGE_LIGHTNING_KINK_STUDS = 2.5,
	COMBAT_RANGE_LIGHTNING_MAX_KINKS = 7,
	COMBAT_RANGE_LIGHTNING_JITTER = 0.9,
	COMBAT_RANGE_LIGHTNING_JITTER_SHARE = 0.15,
	COMBAT_RANGE_LIGHTNING_MAX_LINKS = 48, -- pairs drawn per strike; the rest are skipped
	COMBAT_RANGE_LIGHTNING_SPARKS = 6,
	-- Storm Coil: its bolts leave the coil's glowing top, this high above the ground point
	-- (AbilityFx draws the coil to the same height).
	COMBAT_RANGE_COIL_TOP_HEIGHT = 4.4,
	-- Held beam (Beam family, `continuous`): ONE lasting beam per shooter from the hand to the
	-- latest strike's end, alive while strikes keep coming within LINGER_INTERVALS / rate (never
	-- under MIN_LINGER_SECONDS). The glow is the ray's true width (the hitbox without its pad);
	-- the core a share of it. It is the weapon's visual, so feedback.hitboxEffect never hides it.
	COMBAT_RANGE_BEAM_GLOW_TRANSPARENCY = 0.45,
	COMBAT_RANGE_BEAM_CORE_SHARE = 0.35,
	COMBAT_RANGE_BEAM_MIN_WIDTH = 0.3,
	COMBAT_RANGE_BEAM_TIP_SIZE = 1.6,
	COMBAT_RANGE_BEAM_MUZZLE_SIZE = 0.7,
	COMBAT_RANGE_BEAM_LINGER_INTERVALS = 2,
	COMBAT_RANGE_BEAM_MIN_LINGER_SECONDS = 0.3, -- floor under that, so jitter never blinks it off
	COMBAT_RANGE_BEAM_FOLLOW_RATE = 25, -- per second: another player's beam end eases to the latest
	COMBAT_RANGE_BEAM_FLICKER = 0.18, -- width wobble share (off under reduced motion)
	COMBAT_RANGE_BEAM_FLICKER_HZ = 9,
	-- A server stop within this many studs of the world hit along the same ray was the wall,
	-- not a spent pierce, so the local beam may reach past it as the aim sweeps.
	COMBAT_RANGE_BEAM_STOP_TOLERANCE = 1,
	-- Pooled spark emitters: a spray is skipped (the parts still carry the hit) when all are busy.
	COMBAT_RANGE_SPARK_POOL = 24,
	-- Counters: hits in the running combo and kills of the last attack, right of the crosshair.
	COMBAT_RANGE_COMBO_WINDOW_SECONDS = 2.5,
	COMBAT_RANGE_COUNTER_OFFSET_X = 60,
	COMBAT_RANGE_COUNTER_OFFSET_Y = 40,
	COMBAT_RANGE_COUNTER_WIDTH = 116,
	COMBAT_RANGE_COMBO_TEXT = 30,
	COMBAT_RANGE_COMBO_LABEL_TEXT = 11,
	COMBAT_RANGE_KILLS_TEXT = 16,
	COMBAT_RANGE_COUNTER_POP_SCALE = 1.3,
	COMBAT_RANGE_COUNTER_POP_SECONDS = 0.12,
	COMBAT_RANGE_KILLS_SECONDS = 1.2,
	COMBAT_RANGE_COUNTER_FADE_SECONDS = 0.3,
	-- RangePanel (Studio only). Rows are 48 design px (44 physical px at MIN_SCALE); the body
	-- scrolls instead of shrinking on a short phone viewport.
	COMBAT_RANGE_PANEL_WIDTH = 300,
	COMBAT_RANGE_PANEL_ROW_HEIGHT = 48,
	COMBAT_RANGE_PANEL_LABEL_HEIGHT = 16,
	COMBAT_RANGE_PANEL_GAP = 6,
	COMBAT_RANGE_PANEL_TEXT = 12,
	COMBAT_RANGE_PANEL_VALUE_WIDTH = 64,
	COMBAT_RANGE_PANEL_STEP_WIDTH = 48,
	COMBAT_RANGE_PANEL_KNOB = 16,
	COMBAT_RANGE_PANEL_TRACK = 6,
	COMBAT_RANGE_PANEL_TOGGLE_WIDTH = 120,
	-- The panel docks right, centred between this top clearance (the player list drops down
	-- top-right) and the bottom reserve; the open sheet is capped so it stays centred on a
	-- tall monitor instead of running the full height.
	COMBAT_RANGE_PANEL_TOP_CLEARANCE = 64,
	COMBAT_RANGE_PANEL_MAX_BODY_HEIGHT = 380,
	COMBAT_RANGE_PANEL_HINT_TEXT = 11,
	COMBAT_RANGE_PANEL_READOUT_LINE = 15,
	COMBAT_RANGE_PANEL_READOUT_LINES = 4,
	COMBAT_RANGE_PANEL_COMMAND_COLUMNS = 3,
	COMBAT_RANGE_PANEL_SEND_SECONDS = 0.1, -- slider drags send at most this often
	-- Slider span: feedback strengths run 0..FEEDBACK_MAX; everything else 0..max(base x
	-- RANGE_FACTOR, MIN_SPAN) so a zero default (cap, launch) can still be dragged up.
	COMBAT_RANGE_PANEL_FEEDBACK_MAX = 3,
	COMBAT_RANGE_PANEL_FEEDBACK_STEP = 0.05,
	COMBAT_RANGE_PANEL_RANGE_FACTOR = 3,
	COMBAT_RANGE_PANEL_MIN_SPAN = 10,
	-- P3: a base under 1 (tick seconds, refunds, falloffs, fractions) gets this span floor
	-- instead, so its steps are hundredths rather than tenths.
	COMBAT_RANGE_PANEL_SMALL_SPAN = 1,
	COMBAT_RANGE_PANEL_FINE_STEPS = 100,
	-- A typed value is kept to this many decimals (a slider drag and +/- still use the step).
	COMBAT_RANGE_PANEL_TYPED_DECIMALS = 4,
	COMBAT_RANGE_FPS_SAMPLE_SECONDS = 0.5,

	-- P3 AbilityBar (PC and gamepad; touch shows Motion's ability buttons instead): two tiles at
	-- the bottom centre, melee (Q / LB) then ranged (E / RB). 64 design px tall so the name and
	-- the seconds read at a glance; the bar slides left of the RangePanel column when a narrow
	-- window would put them together. The cooldown sweep is two clipped halves whose UIGradient
	-- edge turns (no image asset exists for a radial wipe).
	COMBAT_ABILITY_BAR_TILE_WIDTH = 128,
	COMBAT_ABILITY_BAR_TILE_HEIGHT = 64,
	COMBAT_ABILITY_BAR_GAP = 8,
	COMBAT_ABILITY_BAR_BOTTOM = 20,
	COMBAT_ABILITY_BAR_INSET = 6,
	COMBAT_ABILITY_BAR_BG_TRANSPARENCY = 0.3,
	COMBAT_ABILITY_BAR_SWEEP_TRANSPARENCY = 0.25,
	COMBAT_ABILITY_BAR_BUSY_TRANSPARENCY = 0.45,
	COMBAT_ABILITY_BAR_KEY_WIDTH = 28,
	COMBAT_ABILITY_BAR_KEY_HEIGHT = 18,
	COMBAT_ABILITY_BAR_KEY_TEXT = 12,
	COMBAT_ABILITY_BAR_SECONDS_TEXT = 24,
	COMBAT_ABILITY_BAR_NAME_HEIGHT = 16,
	COMBAT_ABILITY_BAR_NAME_TEXT = 12,
	COMBAT_ABILITY_BAR_NAME_MIN_TEXT = 9,
	COMBAT_ABILITY_BAR_ACTIVE_STROKE = 3,
	COMBAT_ABILITY_BAR_IDLE_STROKE = 1,
	COMBAT_ABILITY_BAR_IDLE_STROKE_TRANSPARENCY = 0.5,
	COMBAT_ABILITY_BAR_PULSE_SCALE = 1.12,
	COMBAT_ABILITY_BAR_PULSE_SECONDS = 0.3,
	-- A kill refund floats "−N.Ns" over the tile; drops under REFUND_MIN seconds are clock noise.
	COMBAT_ABILITY_BAR_REFUND_SECONDS = 0.8,
	COMBAT_ABILITY_BAR_REFUND_TEXT = 13,
	COMBAT_ABILITY_BAR_REFUND_RISE = 14,
	COMBAT_ABILITY_BAR_REFUND_MIN = 0.05,

	-- P4 "they hurt you" (docs/INTERFACES.md "P4 contracts"): enemy tells (CrowdRenderer) and
	-- being hit (VitalsController, VitalsHud). Timing, reach and damage come from
	-- ProvingGrounds.json (`crowd.kinds.*.attacks`, `crowd.threat`, `player`); these are only
	-- the shape of each cue at strength 1.
	-- Danger is hot red, in the world and on the HUD. Nothing the player's own weapons draw is
	-- (hitbox effect cream, crits yellow, blasts and charge orange, abilities and the
	-- wireframe blue), so an enemy's tell can never be taken for the player's own effect.
	COMBAT_RANGE_TELL_COLOR = Color3.fromRGB(255, 48, 72),
	-- Recover: the spent body goes dull, the opposite of the heat that built it up.
	COMBAT_RANGE_TELL_SPENT_COLOR = Color3.fromRGB(52, 54, 64),
	COMBAT_RANGE_TELL_HEAT_SHARE = 0.75, -- how far a body's own colour has gone to red by the impact
	COMBAT_RANGE_TELL_SPENT_SHARE = 0.6,
	COMBAT_RANGE_TELL_TINT_STEPS = 8, -- a windup repaints its body this many times, not every frame
	-- Body pose. A lunge rears back over COIL_SHARE of its windup and throws itself forward in
	-- the rest, so the figure is fully out exactly at the impact. Leans are radians.
	COMBAT_RANGE_TELL_COIL_SHARE = 0.8,
	COMBAT_RANGE_TELL_LEAN_BACK = 0.45,
	COMBAT_RANGE_TELL_LEAN_FORWARD = 0.5,
	COMBAT_RANGE_TELL_PULL_BACK = 0.35, -- share of its own radius the figure draws back while it coils
	COMBAT_RANGE_TELL_LUNGE_SHARE = 0.7, -- share of the lunge's reach past the body that the figure jabs
	COMBAT_RANGE_TELL_ARC_TWIST_SHARE = 0.5, -- share of the half arc the figure turns back, then through
	COMBAT_RANGE_TELL_ARC_SWEEP_SHARE = 0.6, -- share of the strike spent sweeping across the wedge
	COMBAT_RANGE_TELL_SPENT_LEAN = 0.3,
	COMBAT_RANGE_TELL_SPENT_SQUASH = 0.84,
	COMBAT_RANGE_TELL_SPENT_SETTLE_SECONDS = 0.15,
	COMBAT_RANGE_TELL_SPENT_WAKE_SECONDS = 0.3,
	-- The elite's ground wedge. It lies just above the player's own ground marks (ability rings
	-- top out at 0.12 studs), so those never cover it; its fill is see-through, so it never
	-- covers them either.
	COMBAT_RANGE_TELL_LIFT = 0.16,
	COMBAT_RANGE_TELL_THICKNESS = 0.06,
	COMBAT_RANGE_TELL_SEGMENT_DEGREES = 20,
	COMBAT_RANGE_TELL_LOW_END_SEGMENT_DEGREES = 30,
	COMBAT_RANGE_TELL_EDGE_WIDTH = 0.4,
	COMBAT_RANGE_TELL_EDGE_HEIGHT = 0.1,
	COMBAT_RANGE_TELL_EDGE_TRANSPARENCY = 0.05,
	COMBAT_RANGE_TELL_FILL_TRANSPARENCY = 0.55,
	COMBAT_RANGE_TELL_STRIKE_TRANSPARENCY = 0.15, -- the whole wedge at the instant of the blow
	COMBAT_RANGE_TELL_MIN_FILL = 0.12, -- the fill starts at this share of the reach, visible from frame one

	-- Being hit. HURT is the HUD's danger red; DODGE the green of a hit an i-frame voided and
	-- of the get-up shimmer (both say "nothing can touch you").
	COMBAT_RANGE_HURT_COLOR = Color3.fromRGB(235, 40, 64),
	COMBAT_RANGE_DODGE_COLOR = Color3.fromRGB(120, 240, 170),
	-- Screen-edge flash: four bars fading inward, as the kill flash is built. Its strength is the
	-- share of max health the hit took over FULL_SHARE, never under MIN.
	COMBAT_RANGE_HURT_FLASH_THICKNESS = 150,
	COMBAT_RANGE_HURT_FLASH_TRANSPARENCY = 0.3,
	COMBAT_RANGE_HURT_FLASH_SECONDS = 0.45,
	COMBAT_RANGE_HURT_FLASH_FULL_SHARE = 0.25,
	COMBAT_RANGE_HURT_FLASH_MIN = 0.4,
	COMBAT_RANGE_HURT_KICK_DEGREES = 2.5, -- camera kick at a full-strength hit (feedback.shake scales it)
	COMBAT_RANGE_HURT_SHAKE = 0.35,
	-- The number lost (or "DODGED"), over the player's own head: pops, rises and fades. Hits
	-- of one kind landing within MERGE_SECONDS share one number (a total, or one "DODGED")
	-- instead of stacking on one spot; 0.4 s of rise is about one line of text on a phone.
	COMBAT_RANGE_HURT_NUMBER_MERGE_SECONDS = 0.4,
	COMBAT_RANGE_HURT_NUMBER_WIDTH = 180,
	COMBAT_RANGE_HURT_NUMBER_HEIGHT = 44,
	COMBAT_RANGE_HURT_NUMBER_TEXT = 30,
	COMBAT_RANGE_HURT_DODGE_TEXT = 22,
	COMBAT_RANGE_HURT_NUMBER_SECONDS = 0.9,
	COMBAT_RANGE_HURT_NUMBER_RISE = 2.5, -- studs
	COMBAT_RANGE_HURT_NUMBER_DRIFT = 0.8, -- studs sideways in the camera's frame, alternating sides
	COMBAT_RANGE_HURT_NUMBER_HEAD_CLEARANCE = 3.4, -- studs above the root where the number starts
	COMBAT_RANGE_HURT_NUMBER_POP_SCALE = 1.6,
	COMBAT_RANGE_HURT_NUMBER_POP_SECONDS = 0.1,
	COMBAT_RANGE_HURT_NUMBER_FADE_FROM = 0.55,
	COMBAT_RANGE_HURT_NUMBER_MAX_ACTIVE = 4,
	-- Where it came from: a bar with a point on a ring round the screen centre, turned to the
	-- attacker's bearing (straight down = behind the camera). The ring is a share of the shorter
	-- screen side and is pulled in so its bottom never reaches the health bar.
	COMBAT_RANGE_HURT_POINTERS = 4,
	COMBAT_RANGE_HURT_POINTER_SECONDS = 1.4,
	COMBAT_RANGE_HURT_POINTER_FADE_FROM = 0.5,
	COMBAT_RANGE_HURT_POINTER_RADIUS_SHARE = 0.26,
	COMBAT_RANGE_HURT_POINTER_WIDTH = 84,
	COMBAT_RANGE_HURT_POINTER_THICKNESS = 10,
	COMBAT_RANGE_HURT_POINTER_TIP = 14, -- a square turned 45 degrees, half hidden behind the bar
	COMBAT_RANGE_HURT_POINTER_TRANSPARENCY = 0.1,
	COMBAT_RANGE_HURT_POINTER_MERGE_DEGREES = 25, -- a hit from within this of a live pointer renews it
	-- P5: the ring never shrinks under this (design px), whatever sits above or below it: a
	-- pointer drawn on the crosshair dot has no bearing, and it is the only cue for a hit from
	-- behind. 48 keeps the blade clear of the crosshair's ticks.
	COMBAT_RANGE_HURT_POINTER_MIN_RADIUS = 48,
	-- Another player's hit: a short red flash on their character, nothing on this screen's edges.
	COMBAT_RANGE_FLINCH_SECONDS = 0.16,
	COMBAT_RANGE_FLINCH_FILL = 0.45,
	COMBAT_RANGE_FLINCH_POOL = 4,
	-- Health bar (range): bottom centre, over the AbilityBar on PC and gamepad; on touch beside
	-- the thumb cluster, or above it where the screen is too narrow for both.
	COMBAT_RANGE_VITALS_WIDTH = 200,
	COMBAT_RANGE_VITALS_HEIGHT = 18,
	COMBAT_RANGE_VITALS_TEXT = 12,
	COMBAT_RANGE_VITALS_GAP = 8,
	COMBAT_RANGE_VITALS_BOTTOM = 10, -- design px above the screen's bottom edge when nothing sits under it
	COMBAT_RANGE_VITALS_BG_TRANSPARENCY = 0.35,
	COMBAT_RANGE_VITALS_FILL_COLOR = Color3.fromRGB(96, 200, 120),
	COMBAT_RANGE_VITALS_LOW_COLOR = Color3.fromRGB(240, 170, 60),
	COMBAT_RANGE_VITALS_LOW_SHARE = 0.5, -- the fill turns amber under this share, red under CRITICAL
	COMBAT_RANGE_VITALS_CRITICAL_SHARE = 0.25,
	-- A loss shows at once; the chunk just lost stays behind it for HOLD seconds, then drains.
	COMBAT_RANGE_VITALS_LOST_COLOR = Color3.fromRGB(255, 205, 210),
	COMBAT_RANGE_VITALS_LOST_HOLD_SECONDS = 0.35,
	COMBAT_RANGE_VITALS_LOST_DRAIN_PER_SECOND = 1.2, -- shares of the bar
	COMBAT_RANGE_VITALS_GAIN_RATE = 10, -- per second, toward a higher health (regen, the get-up)
	COMBAT_RANGE_VITALS_POP_SCALE = 1.15, -- the bar's pop on a hit and on the get-up
	COMBAT_RANGE_VITALS_POP_SECONDS = 0.18,
	-- Knocked down: a one-line banner with the time left over a line that runs out with it,
	-- the edge flash held and pulsing, then a green shimmer on the character while the
	-- get-up i-frames last.
	COMBAT_RANGE_DOWN_WIDTH = 200,
	COMBAT_RANGE_DOWN_HEIGHT = 36,
	COMBAT_RANGE_DOWN_TEXT = 18,
	COMBAT_RANGE_DOWN_BAR_HEIGHT = 4,
	COMBAT_RANGE_DOWN_FLASH = 0.55, -- the edge flash's floor while down
	COMBAT_RANGE_DOWN_PULSE_SECONDS = 0.9,
	COMBAT_RANGE_DOWN_PULSE_DEPTH = 0.25,
	COMBAT_RANGE_GETUP_FILL_MIN = 0.45, -- the shimmer's Highlight fill swings between these
	COMBAT_RANGE_GETUP_FILL_MAX = 0.85,
	COMBAT_RANGE_GETUP_PULSE_HZ = 3,
	-- RangePanel: one more readout line (damage taken, downs) under the P3 four.
	COMBAT_RANGE_PANEL_VITALS_LINES = 1,

	-- P4 wave 2 "roles" (docs/INTERFACES.md "P4 contracts" -> "Wave 2"): the shooters, the
	-- brute and the plate. Reach, width, speed and every time come from the kind's `attacks`
	-- and the effects themselves; these are only how each one looks. Everything an enemy warns
	-- with or throws is the tell red above.
	-- The marksman's line. It is a vertical plane (a jump does not clear it), so it is drawn
	-- standing up: a floor strip of the shot's true width, a beam at chest height, and a sheet
	-- over them in three bands, each fainter than the one below and the top one well above a
	-- double jump (18 + 12 studs). Until the lock only a thin strip and beam follow the aim.
	COMBAT_RANGE_TELL_LINE_THIN_WIDTH = 0.3,
	COMBAT_RANGE_TELL_LINE_THIN_TRANSPARENCY = 0.35,
	COMBAT_RANGE_TELL_LINE_BEAM_HEIGHT = 3,
	COMBAT_RANGE_TELL_LINE_BEAM_THIN = 0.12,
	COMBAT_RANGE_TELL_LINE_BEAM_LOCKED = 0.4,
	COMBAT_RANGE_TELL_LINE_BEAM_SHOT = 1,
	COMBAT_RANGE_TELL_LINE_LOW_TOP = 8,
	COMBAT_RANGE_TELL_LINE_MID_TOP = 18,
	COMBAT_RANGE_TELL_LINE_HIGH_TOP = 34,
	COMBAT_RANGE_TELL_LINE_LOW_TRANSPARENCY = 0.72,
	COMBAT_RANGE_TELL_LINE_MID_TRANSPARENCY = 0.86,
	COMBAT_RANGE_TELL_LINE_HIGH_TRANSPARENCY = 0.94,
	COMBAT_RANGE_TELL_LINE_SHOT_LIFT = 0.35, -- how much more solid every band is at the shot
	COMBAT_RANGE_TELL_LINE_FOLLOW_RATE = 18, -- per second: the thin line eases after the wire's yaw steps
	-- The brute's charge is drawn on the server clock, ahead of its delayed snapshots; at the
	-- lane's end the body waits for them and takes over once they are this close (studs).
	COMBAT_RANGE_TELL_RUSH_ARRIVE = 1,
	-- A shooter walks through its recover. The spent slump is a standing body's: it lifts with
	-- the body's pace and is gone at this many studs/s (every keepAway kind walks faster). The
	-- dull tint stays, which is what says "spent".
	COMBAT_RANGE_TELL_SPENT_WALK_SPEED = 4,
	-- The slinger's shot: an orb of its true radius in a larger halo, a short tapering tail
	-- behind it, and a flash where it ends (bright on a player, small and dull on a wall).
	COMBAT_RANGE_SHOT_HALO_SCALE = 1.8,
	COMBAT_RANGE_SHOT_HALO_TRANSPARENCY = 0.7,
	COMBAT_RANGE_SHOT_HALO_PULSE = 0.15,
	COMBAT_RANGE_SHOT_HALO_PULSE_HZ = 6,
	COMBAT_RANGE_SHOT_TAIL = 3, -- fading copies behind the orb (none on a low-end device)
	COMBAT_RANGE_SHOT_TAIL_SECONDS = 0.05, -- how far apart in flight time
	COMBAT_RANGE_SHOT_TAIL_TRANSPARENCY = 0.5,
	COMBAT_RANGE_SHOT_HIT_COLOR = Color3.fromRGB(255, 196, 206),
	COMBAT_RANGE_SHOT_HIT_SCALE = 3.2,
	COMBAT_RANGE_SHOT_HIT_SECONDS = 0.22,
	COMBAT_RANGE_SHOT_WALL_COLOR = Color3.fromRGB(128, 58, 70),
	COMBAT_RANGE_SHOT_WALL_SCALE = 1.6,
	COMBAT_RANGE_SHOT_WALL_SECONDS = 0.14,
	-- A hit's end arrives after the orb was drawn through its victim: it fades over this long,
	-- still flying, and is never pulled back to the flash.
	COMBAT_RANGE_SHOT_SPENT_SECONDS = 0.1,
	-- The lobber's circle: a faint disc and a bright rim at its full reach, a brighter disc
	-- growing to the rim, the shot arcing in, and a flash on landing.
	COMBAT_RANGE_AREA_SEGMENTS = 24,
	COMBAT_RANGE_AREA_LOW_END_SEGMENTS = 12,
	COMBAT_RANGE_AREA_BASE_TRANSPARENCY = 0.82,
	COMBAT_RANGE_AREA_LAND_SECONDS = 0.3,
	COMBAT_RANGE_LOB_BALL_SIZE = 1.4,
	COMBAT_RANGE_LOB_APEX_SHARE = 0.35, -- the arc's height as a share of the flat distance thrown
	COMBAT_RANGE_LOB_APEX_MIN = 4,
	COMBAT_RANGE_LOB_APEX_MAX = 14,
	-- Role cues on the bodies (ThreatFx/Cues). A shooter's lit piece swells to this share of its
	-- body's height by the end of the windup: at forty studs that is still a clear red ball.
	COMBAT_RANGE_CUE_CHARGE_SHARE = 0.6,
	COMBAT_RANGE_CUE_AIM_CHARGE_SHARE = 0.3, -- the marksman's barrel tip: its line is the tell
	COMBAT_RANGE_CUE_DARK_COLOR = Color3.fromRGB(26, 28, 34),
	COMBAT_RANGE_CUE_HORN_COLOR = Color3.fromRGB(238, 228, 204),
	COMBAT_RANGE_CUE_BREAK_SECONDS = 0.3, -- the shell's burst when the plate breaks
	COMBAT_RANGE_CUE_BREAK_GROW = 0.6,
	COMBAT_RANGE_CUE_GLINT_SECONDS = 0.1, -- the shell's flash when it turns a hit
	-- The plate: a steel blue that is neither the white and yellow of ordinary numbers nor any
	-- enemy red. Its shell, its bar and the numbers of the damage it takes all share it.
	COMBAT_RANGE_PLATE_COLOR = Color3.fromRGB(120, 175, 240),
	COMBAT_RANGE_ENEMY_HEALTH_COLOR = Color3.fromRGB(235, 84, 84),
	COMBAT_RANGE_PLATE_BAR_WIDTH = 68, -- px, the same at any distance
	COMBAT_RANGE_PLATE_BAR_HEIGHT = 6, -- each of the two rows
	COMBAT_RANGE_PLATE_BAR_GAP = 2,
	COMBAT_RANGE_PLATE_BAR_RISE = 0.9, -- studs above the top of the head
	COMBAT_RANGE_PLATE_BAR_BG_TRANSPARENCY = 0.35,
	COMBAT_RANGE_PLATE_BAR_MAX_DISTANCE = 160,
	-- The reel after a plate breaks: the opening. Slumped and dull like a spent body, but
	-- thrown further back and swaying.
	COMBAT_RANGE_REEL_LEAN = 0.5,
	COMBAT_RANGE_REEL_SWAY = 0.35, -- radians of twist either way
	COMBAT_RANGE_REEL_SWAY_HZ = 2.5,
	COMBAT_RANGE_REEL_SQUASH = 0.88,
	-- Hit numbers on a plate (FeedbackController). A blocked hit is a small grey word, never a
	-- 0; plate damage is its amount in the plate's colour; the break has its own line.
	COMBAT_RANGE_BLOCKED_COLOR = Color3.fromRGB(150, 156, 170),
	COMBAT_RANGE_BLOCKED_TEXT = 17,
	COMBAT_RANGE_BLOCKED_LABEL = "BLOCKED",
	COMBAT_RANGE_PLATE_BROKEN_LABEL = "PLATE BROKEN",
	-- A body whose plate broke can carry three lines at once (health number, plate number,
	-- "PLATE BROKEN"). Each sits one row above the last: a share of a number's own height, in
	-- pixels, so the rows hold apart at any distance and on any screen.
	COMBAT_RANGE_NUMBER_ROW_SHARE = 0.5,

	-- P4 Stop 2, the Colossus (docs/INTERFACES.md "P4 contracts" -> "Stop 2"). Radius, width,
	-- speed and every time come from the kind's `attacks`; these are only the look.
	-- The slam's ring (ThreatFx/Rings): the whole circle it will reach from the windup's first
	-- frame, drawn as a lob's circle is, then a low bright crest that runs out to the rim. Low
	-- and flat is the point: this one is jumped, where the marksman's line is a wall.
	COMBAT_RANGE_RING_SEGMENTS = 32,
	COMBAT_RANGE_RING_LOW_END_SEGMENTS = 16,
	COMBAT_RANGE_RING_FRONT_HEIGHT = 1, -- studs: a crest, far under any jump
	COMBAT_RANGE_RING_FRONT_TRANSPARENCY = 0.1,
	COMBAT_RANGE_RING_BASE_RUNNING = 0.9, -- the reach's disc, fainter still while the front runs
	-- Flat marks that can lie over one another (a barrage is several circles at once, and a
	-- chain can lay its slam's circle under them) must not show two top faces at one height,
	-- or the two fight for the same pixels. Only the TOP faces need telling apart, so the marks
	-- are not stacked: each takes a top face of its own, MARK_STEP above the last, starting at
	-- MARK_FLOOR, just over the player's own ground marks (ThreatFx/Pool.MarkTop skips the
	-- three heights the lane, the line and the elite's wedge already use). In order: each lob
	-- circle's faint disc on one of AREA_LEVELS, their growing discs on as many more, every
	-- circle's rim, then a slam's disc, its fill and its rim. Everything stays under 0.4 studs:
	-- a mark that floats reads further from the camera than it is, on exactly the question
	-- "am I inside it". Heights are studs above the surface the mark lies on.
	COMBAT_RANGE_MARK_FLOOR = 0.13,
	COMBAT_RANGE_MARK_STEP = 0.01,
	COMBAT_RANGE_AREA_LEVELS = 10,
	-- The slam itself: the body stretches up through the windup and comes down flat at the
	-- impact (squash shares of the torso; lean in radians).
	COMBAT_RANGE_RING_SLAM_RISE = 0.12,
	COMBAT_RANGE_RING_SLAM_SQUASH = 0.76,
	COMBAT_RANGE_RING_SLAM_LEAN = 0.3,
	-- The call: head thrown back, shaking, and a circle where the summoned will rise. That
	-- circle hurts nobody, so it is never the danger's red.
	COMBAT_RANGE_CALL_COLOR = Color3.fromRGB(190, 120, 255),
	COMBAT_RANGE_CALL_TRANSPARENCY = 0.2,
	COMBAT_RANGE_CALL_PULSE = 0.4, -- how much more see-through the circle swings, at PULSE_HZ
	COMBAT_RANGE_CALL_PULSE_HZ = 3,
	COMBAT_RANGE_CALL_LEAN = 0.5,
	COMBAT_RANGE_CALL_SHAKE = 0.12, -- radians of twist either way
	COMBAT_RANGE_CALL_SHAKE_HZ = 9,
	COMBAT_RANGE_CALL_STRETCH = 0.08,
	-- A body a boss called comes up out of the floor instead of appearing, over this long.
	COMBAT_RANGE_RISE_SECONDS = 0.45,
	-- A boss's cue set (ThreatFx/Cues): shoulders, a crown, back spines and a core in the chest
	-- that charges through every windup, to this share of the body's height.
	COMBAT_RANGE_CUE_BOSS_CHARGE_SHARE = 0.3,
	-- A boss breathes: the torso swells by this share, this many times a second. Enraged, it
	-- heaves.
	COMBAT_RANGE_BOSS_BREATH = 0.02,
	COMBAT_RANGE_BOSS_BREATH_HZ = 0.35,
	COMBAT_RANGE_ENRAGE_BREATH = 0.035,
	COMBAT_RANGE_ENRAGE_BREATH_HZ = 0.9,
	-- Enraged for good: the body's own colours go this far toward hot red, and the crown, the
	-- spines and the core are lit.
	COMBAT_RANGE_ENRAGE_COLOR = Color3.fromRGB(255, 60, 40),
	COMBAT_RANGE_ENRAGE_SHARE = 0.4,
	COMBAT_RANGE_ENRAGE_GLOW_COLOR = Color3.fromRGB(255, 170, 70),
	COMBAT_RANGE_ENRAGE_CORE_SCALE = 1.35,
	-- The boss bar (UI/BossBar): one row, the name and the phase written on the bar itself, a
	-- mark where the enrage begins. Top centre where the RangePanel's column leaves room,
	-- beside it on a landscape phone, under its readouts on a portrait one.
	COMBAT_RANGE_BOSS_BAR_WIDTH = 300,
	COMBAT_RANGE_BOSS_BAR_MIN_WIDTH = 200,
	-- P5: in a mission the bar shrinks to the top strip between the run header and the party
	-- list, down to this (design px): "WARLORD" plus four guard pips needs about 133. A 640 px
	-- landscape phone leaves 154.
	COMBAT_MISSION_BOSS_BAR_MIN_WIDTH = 140,
	COMBAT_RANGE_BOSS_BAR_HEIGHT = 20,
	COMBAT_RANGE_BOSS_BAR_TEXT = 12,
	COMBAT_RANGE_BOSS_BAR_FILL_COLOR = Color3.fromRGB(206, 56, 64),
	COMBAT_RANGE_BOSS_BAR_ENRAGED_COLOR = Color3.fromRGB(255, 128, 24),
	COMBAT_RANGE_BOSS_BAR_MARK_WIDTH = 2,
	COMBAT_RANGE_BOSS_BAR_ENRAGED_LABEL = "ENRAGED",
	COMBAT_RANGE_BOSS_BAR_SHOW_SECONDS = 0.25,
	COMBAT_RANGE_BOSS_BAR_POP_SCALE = 1.3, -- the enrage beat: the bar jumps and flashes white
	COMBAT_RANGE_BOSS_BAR_POP_SECONDS = 0.4,
	COMBAT_RANGE_BOSS_BAR_FLASH_SECONDS = 0.6,
	COMBAT_RANGE_BOSS_BAR_DEATH_SECONDS = 0.7, -- emptied, it flashes and fades out over this long
	COMBAT_RANGE_BOSS_BAR_DEATH_HOLD_SHARE = 0.55, -- of that, spent emptied before it folds shut
	COMBAT_RANGE_BOSS_BAR_FLASH_TRANSPARENCY = 0.15, -- the white flash over the bar at its strongest

	-- P4 Stop 3, the Warlord and his guard (docs/INTERFACES.md "P4 contracts" -> "Stop 3").
	-- One colour is the guard's and everything that comes of it: the circle they are called
	-- up in, the pennant each of them carries, the tether from each to the Warlord, his shell
	-- while they protect it, the word a hit on him earns then, and their pips on his bar. It
	-- is the call's violet, so the player meets it first as "this is his guard arriving".
	COMBAT_RANGE_WARD_COLOR = Color3.fromRGB(190, 120, 255),
	COMBAT_RANGE_WARD_SHELL_SCALE = 1.14, -- the guarded shell stands this much prouder of the plate
	COMBAT_RANGE_WARD_OPEN_SECONDS = 0.5, -- the shell's white flash when the last guard falls
	-- The tether from each living guard to the Warlord: a thin lit bar, breathing slowly.
	COMBAT_RANGE_LINK_THICKNESS = 0.24,
	COMBAT_RANGE_LINK_TRANSPARENCY = 0.3,
	COMBAT_RANGE_LINK_PULSE = 0.4, -- how much more see-through it swings, at PULSE_HZ
	COMBAT_RANGE_LINK_PULSE_HZ = 1.5,
	-- A hit his guard turned away: its own word, in the guard's colour, never "BLOCKED".
	COMBAT_RANGE_GUARDED_LABEL = "GUARDED",
	COMBAT_RANGE_GUARDED_TEXT = 19,
	-- The commander's standard: the orb on its pole charges through every windup to this share
	-- of his height, high over his guard's heads, so a barrage reads from across his band.
	COMBAT_RANGE_CUE_COMMANDER_CHARGE_SHARE = 0.55,
	-- The boss bar of a plated boss: the plate as a thin row over the health row (the elite's
	-- overhead bar, written large), and a pip per guard on the health row's right end.
	COMBAT_RANGE_BOSS_BAR_PLATE_HEIGHT = 6,
	COMBAT_RANGE_BOSS_BAR_PLATE_GAP = 2,
	COMBAT_RANGE_BOSS_BAR_PLATE_FOLD_RATE = 12, -- per second: the row eases open, and folds away when it breaks
	COMBAT_RANGE_BOSS_BAR_PIP = 9,
	COMBAT_RANGE_BOSS_BAR_PIP_GAP = 5, -- a pip stands on its point, so its diagonal needs the room
	COMBAT_RANGE_BOSS_BAR_PIP_DEAD_TRANSPARENCY = 0.8,
	COMBAT_RANGE_BOSS_BAR_MAX_PIPS = 8,
	-- The second phase of a boss with a guard is the turn from siege to duel, and says so.
	COMBAT_RANGE_BOSS_BAR_DUEL_LABEL = "DUEL",

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
	-- L3-28: T (and the DebugPanels' "Grant 500 Timber") pays this much of every built band's
	-- material: one press pays T2 and T3 (100 + 250) for one weapon.
	COMBAT_DEBUG_GRANT_TIMBER = 500,
	COMBAT_DEBUG_GRANT_VALOR = 10,
	COMBAT_DEBUG_MAX_SPAWN_KEYS = 3,

	-- L1 (docs/INTERFACES.md "L1 contracts"): the expeditions map (UI/MapScreen) and the run
	-- layer's new pieces. The map's colours are the ones of the picture Ben approved
	-- (assets/research/2026-10-13-missions): one navy look for the screen, each node in its
	-- theme's colour, which comes from Config/Expeditions.json.
	-- The whole screen (map and card) never grows past this, in design px; it fills the
	-- viewport less a margin on anything smaller.
	MAP_MAX_WIDTH = 960,
	MAP_MAX_HEIGHT = 540,
	MAP_GAP = 8,
	MAP_CARD_WIDTH = 232,
	MAP_CARD_PADDING = 10,
	MAP_CARD_LINE_GAP = 6,
	MAP_CARD_CHIP_HEIGHT = 20,
	MAP_CARD_NAME_HEIGHT = 24,
	MAP_CARD_ROW_HEIGHT = 16, -- one info row ("Rewards x2 cash and drops")
	MAP_CARD_REASON_HEIGHT = 48, -- a locked node's reason, up to three lines
	MAP_CARD_LABEL_WIDTH = 62, -- the dim caption column of an info row
	MAP_CARD_HINT_HEIGHT = 14,
	MAP_CARD_HINT_TEXT = 10,
	-- Every tap target of the map is at least 48 design px: 44 physical px at MIN_SCALE.
	MAP_NODE_SIZE = 64,
	MAP_BONUS_NODE_SIZE = 48,
	MAP_NODE_RING = 5, -- the ring round a node: gold on the selected one
	MAP_NODE_GAP = 2, -- between a node, its stars above and its name below
	MAP_NODE_NAME_WIDTH = 76,
	MAP_NODE_NAME_HEIGHT = 28, -- two lines: "Another / Planet"
	MAP_NODE_NAME_TEXT = 12,
	MAP_NODE_PAD_X = 44, -- from the map's side edges to the outermost node centres
	MAP_NODE_PAD_EDGE = 6, -- from the map's top and bottom edges to a node's stars and name
	MAP_STAR_SIZE = 18,
	MAP_STAR_TEXT = 17,
	MAP_LOCK_COLOR = Color3.fromRGB(170, 183, 216),
	MAP_PATH_DOT_SIZE = 7,
	MAP_PATH_DOT_SPACING = 16,
	MAP_PATH_CLEARANCE = 6, -- the dots stop this far short of a node's ring
	MAP_BAND_TRANSPARENCY = 0.72, -- each theme's band behind the path
	-- The spread that keeps nodes off each other on a small map: footprints end up at least
	-- this far apart, in at most this many passes over every pair.
	MAP_SPREAD_GAP = 2,
	MAP_SPREAD_PASSES = 16,
	MAP_DIFFICULTY_HEIGHT = 52,
	MAP_DIFFICULTY_NAME_TEXT = 13,
	MAP_DIFFICULTY_SUB_TEXT = 11,
	MAP_DEPART_HEIGHT = 48,
	MAP_RETURN_HEIGHT = 48,
	MAP_CLOSE_SIZE = 48,
	MAP_SCRIM_TRANSPARENCY = 0.35,
	MAP_SELECT_POP_SCALE = 1.12,
	MAP_SELECT_POP_SECONDS = 0.14,
	-- A Depart nobody answered (no refusal, no phase change) is live again after this long.
	MAP_DEPART_TIMEOUT_SECONDS = 6,
	MAP_COLOR_INK = Color3.fromRGB(20, 27, 46),
	MAP_COLOR_PANEL = Color3.fromRGB(30, 41, 70),
	MAP_COLOR_PANEL_LIGHT = Color3.fromRGB(43, 58, 97),
	MAP_COLOR_PANEL_SELECTED = Color3.fromRGB(53, 72, 122),
	MAP_COLOR_TEXT = Color3.fromRGB(243, 246, 255),
	MAP_COLOR_DIM = Color3.fromRGB(170, 183, 216),
	MAP_COLOR_GOLD = Color3.fromRGB(255, 200, 61),
	MAP_COLOR_OFF = Color3.fromRGB(85, 100, 140), -- an unearned star, a theme with no colour
	MAP_COLOR_LOCKED = Color3.fromRGB(58, 70, 102),
	MAP_COLOR_PATH = Color3.fromRGB(233, 215, 166),
	-- The shoulder camera follows its character through a short clamped lag. A root that moved
	-- further than this in one frame was moved by the server (the lobby camp to a level, a
	-- camp's entry, a rescue): the camera is there at once, with no lag left to close. No move
	-- a player makes covers this in a frame (a slam is 120 studs a second).
	COMBAT_CAMERA_SNAP_STUDS = 40,
	-- The run layer (CombatHud): the first press of Abandon asks for a second one within this
	-- long.
	COMBAT_ABANDON_CONFIRM_SECONDS = 3,
	-- The summary card's lines sit closer than a dialog's: with two buttons and a party's two
	-- extra lines it must still fit 329 design px of height (640x360 under a 58 px top bar).
	COMBAT_SUMMARY_LINE_GAP = 6,
	-- The bottom-left buttons: Map, and a two-line button (Return to your city / Abandon).
	COMBAT_MAP_BUTTON_WIDTH = 72,
	COMBAT_RUN_BUTTON_WIDTH = 104,
	COMBAT_RUN_BUTTON_TEXT = 13,
	-- The Studio strip's spawn buttons: one per rewarded kind of the level (the C1 cap of
	-- three enemy keys is too few for a level's seven).
	COMBAT_DEBUG_MAX_KIND_KEYS = 10,
	-- L1 fix round (docs/prompts/l1-fix-round.md, part U).
	-- The server says when it has placed a body and where (the character's `Placed` and
	-- `PlacedSeq` attributes, ArenaService.MoveMember); the body's new position reaches the
	-- client a moment before or after that word. The speed the body carried is dropped once
	-- its root is seen within NEAR studs of the feet point named, and the word is forgotten
	-- after TIMEOUT seconds. NEAR sits between two numbers of the server's: the root is put 4
	-- studs above the feet point (and stands 3 above it), and a kill height is at least 8
	-- studs under any ground (tools/check_levels.py), so a faller is never "there" before it
	-- is moved. The same TIMEOUT is how long a look asked of the camera waits for the camera
	-- to pick the body up.
	COMBAT_PLACED_NEAR_STUDS = 6,
	COMBAT_PLACED_TIMEOUT_SECONDS = 1,
	-- CameraController.LookToward: a point this near where the look starts, on the flat, gives
	-- it no direction to turn to.
	COMBAT_LOOK_MIN_STUDS = 1,
	-- A body the server placed faces along its level's route. Within this many studs of the
	-- end of the stretch it stands on, forward is the next stretch's way (a camp's entry is
	-- the end of the road into it, and forward there is into the camp).
	COMBAT_FORWARD_NEAR_STUDS = 4,
	-- The run header's difficulty chip (CombatHud): it holds the right end of the title's row,
	-- and the level's name shrinks down to this text size before it would truncate.
	COMBAT_HEADER_CHIP_WIDTH = 60,
	COMBAT_HEADER_CHIP_HEIGHT = 18,
	COMBAT_HEADER_CHIP_GAP = 6,
	COMBAT_HEADER_TITLE_MIN_TEXT = 14,
	-- The banner's smallest title: a long camp name shrinks to its frame down to this.
	COMBAT_BANNER_MIN_TEXT = 14,
	-- With no MapState in hand the client asks for its snapshot again (the map rides with it)
	-- this often, at most this many times.
	MAP_STATE_RETRY_SECONDS = 2,
	MAP_STATE_RETRIES = 5,
	-- L1b (docs/INTERFACES.md "L1b contracts" -> Client). A raider resting at a fire sits: its
	-- body lowered by this share of its kind's height, legs out in front. Rising, it blends
	-- from seated to standing over RISE_BLEND (and sits down again over the same time).
	COMBAT_REST_DROP = 0.35,
	COMBAT_RISE_BLEND_SECONDS = 0.5,
	-- The seated legs: where they leave the body, as a share of the kind's radius in front of
	-- its centre line (they then run forward their own standing length).
	COMBAT_REST_HIP_SHARE = 0.3,
	-- A woken group: a "!" over each of its bodies for this long, its foot this many studs
	-- above the top of the head. Its size is studs plus pixels, so it grows near and keeps a
	-- floor of pixels far away (about 31 px tall at 60 studs on a 375 px tall phone, 43 px on
	-- a 1080 px monitor). It pops in (not where motion is reduced) and fades out.
	COMBAT_ALERT_SECONDS = 1.5,
	COMBAT_ALERT_STUDS = 3,
	COMBAT_ALERT_WIDTH_STUDS = 1,
	COMBAT_ALERT_HEIGHT_STUDS = 1.5,
	COMBAT_ALERT_WIDTH_PX = 16,
	COMBAT_ALERT_HEIGHT_PX = 24,
	COMBAT_ALERT_STROKE = 3,
	COMBAT_ALERT_COLOR = Color3.fromRGB(255, 196, 40),
	COMBAT_ALERT_POP_SECONDS = 0.15,
	COMBAT_ALERT_POP_FROM = 0.4,
	COMBAT_ALERT_FADE_SECONDS = 0.3,
	COMBAT_ALERT_MAX_DISTANCE = 200,
	-- A checkpoint reached: "Checkpoint" under the wallet for this long (CombatHud.ShowNotice).
	COMBAT_CHECKPOINT_NOTICE_SECONDS = 2,
	COMBAT_CHECKPOINT_NOTICE_WIDTH = 128,
	COMBAT_CHECKPOINT_NOTICE_HEIGHT = 24,
	-- L1b Wave 2: Studio's "Server 1.4 ms" line (the crowd step's p95), dim, over the run's
	-- bottom-left buttons and hints. Never a tap target.
	COMBAT_PERF_TEXT_SIZE = 12,
	COMBAT_PERF_TRANSPARENCY = 0.35,
	COMBAT_PERF_WIDTH = 140,
	COMBAT_PERF_HEIGHT = 16,

	-- L2 Wave 1 (docs/prompts/l2-w1-contract.md, L2-3, L2-10, L2-14, L2-15).
	-- The run layer's "Abilities" button, between Map and Return in the lobby. Map 72 +
	-- Abilities 88 + Return 104 and two gaps make a 280 design px row: 257 px at MIN_SCALE on a
	-- 667 x 375 phone, 280 of 375 in portrait.
	COMBAT_ABILITIES_BUTTON_WIDTH = 88,
	-- The first refused air jump of a session says where to get it, for this long.
	AIR_JUMP_HINT_SECONDS = 4,
	-- The map card's secrets row (MapScreen): one icon per secret with its key under it. 30
	-- design px keeps the open card inside 330 design px of height (667 x 375 under a 58 px top
	-- bar) with Return and no key line; with a keyboard as well it ends 6 px into the margin.
	MAP_SECRET_ROW_HEIGHT = 30,
	MAP_SECRET_ICON_SIZE = 16,
	MAP_SECRET_ICON_TEXT = 11,
	MAP_SECRET_CELL_WIDTH = 50,
	-- The fix round's c6: the keys are the only place the map says what to bring, so they read at
	-- 11 (10 physical px at MIN_SCALE). 16 icon + 11 + 3 fills the 30 px row; "2× JUMP" is about
	-- 47 design px wide in GothamBold 11, inside the 50 px cell.
	MAP_SECRET_KEY_TEXT = 11,
	-- What each key reads under its icon, and in a "Needs ..." toast (tools/check_levels.py
	-- NEED_WORDS). A key not listed reads in capitals.
	MAP_SECRET_KEY_WORDS = { doubleJump = "2× JUMP", fire = "FIRE", ice = "ICE" } :: {
		[string]: string,
	},
	SECRET_NEED_WORDS = { doubleJump = "DOUBLE JUMP", fire = "FIRE", ice = "ICE" } :: {
		[string]: string,
	},
	-- SecretFx: a light column over every unfound chest, so a chest is seen before it is reached
	-- (non-colliding and never queried: no ray, camera or touch meets it).
	SECRET_COLUMN_WIDTH = 2.5,
	SECRET_COLUMN_HEIGHT = 60,
	SECRET_COLUMN_TRANSPARENCY = 0.55,
	SECRET_COLUMN_COLOR = Color3.fromRGB(214, 160, 255),
	-- The chest's tint once found when Expeditions.json has no `secretOpen` look.
	SECRET_OPEN_FALLBACK_COLOR = Color3.fromRGB(255, 200, 61),
	-- The find: a burst (not on low-end devices) and a centre card for this long.
	SECRET_CARD_SECONDS = 3,
	SECRET_CARD_WIDTH = 300,
	SECRET_CARD_PADDING = 12,
	SECRET_CARD_TITLE_TEXT = 20,
	SECRET_CARD_LINE_TEXT = 15,
	SECRET_CARD_NOTE_TEXT = 12,
	SECRET_CARD_TRANSPARENCY = 0.1,
	SECRET_BURST_COUNT = 40,
	SECRET_BURST_SECONDS = 1.5,
	SECRET_BURST_SPEED = 18,
	SECRET_BURST_SPREAD = 60, -- degrees off straight up
	SECRET_BURST_SIZE = 0.6, -- studs, shrinking to nothing
	SECRET_BURST_COLOR = Color3.fromRGB(255, 214, 92),
	SECRET_TOAST_SECONDS = 3,

	-- L3 W1 (docs/prompts/l3-w1-contract.md, L3-18 to L3-23): the Armory screen (UI/ArmoryScreen
	-- and its Armory* parts), one for the dungeon's lobby and the hub. Layout A, "Showcase": a 48
	-- header, the stage beside the detail column, the shelf under them. All in design px under
	-- one UIScale. At 682 x 313 (640 x 360 under a 58 px top bar) that is 8 + 48 + 6 + a 173
	-- middle + 6 + a 64 shelf + 8; the detail's content is 163 (24 title + 3 + 28 track + 3 +
	-- three 16 lines with 3 gaps + 48 buttons). Portrait 393 x 648 (375 x 667): the stage takes
	-- what the detail (163) and a 5 x 3 shelf (180) leave, 223. On a monitor the frame stops at
	-- MAX_WIDTH x MAX_HEIGHT. Every tap target is at least 48 (44 physical at MIN_SCALE).
	ARMORY_SCREEN_MAX_WIDTH = 880,
	ARMORY_SCREEN_MAX_HEIGHT = 420,
	ARMORY_SCREEN_PORTRAIT_MAX_HEIGHT = 720,
	ARMORY_SCREEN_PADDING = 8,
	ARMORY_SCREEN_GAP = 6,
	ARMORY_SCREEN_SCRIM_TRANSPARENCY = 0.35,
	ARMORY_SCREEN_HEADER_HEIGHT = ARMORY_SCREEN_HEADER_HEIGHT, -- the tabs and the close button
	ARMORY_SCREEN_TAB_WIDTH = 104,
	-- The wallet ("1.2K Timber · 25 Valor") wraps to two lines on a portrait phone (103 wide).
	ARMORY_SCREEN_WALLET_TEXT = 13,
	ARMORY_SCREEN_HINT_HEIGHT = 14,
	ARMORY_SCREEN_HINT_TEXT = 10,
	-- The stage: at least STAGE_MIN_WIDTH, else this share of the frame's inner width.
	ARMORY_SCREEN_STAGE_MIN_WIDTH = 220,
	ARMORY_SCREEN_STAGE_SHARE = 0.33,
	ARMORY_SCREEN_STAGE_PORTRAIT_MIN_HEIGHT = 120,
	ARMORY_SCREEN_STAGE_LINE_GAP = 4,
	ARMORY_SCREEN_STAGE_SLOT_TEXT = 12,
	ARMORY_SCREEN_STAGE_NAME_TEXT = 22,
	ARMORY_SCREEN_STAGE_TIER_TEXT = 34,
	-- Lighter in the middle, behind where a weapon will stand (the L0 picture's radial): dark
	-- steel vanishes on the panel colour itself (the study's warning). Darker for an unowned one.
	ARMORY_SCREEN_STAGE_GRADIENT = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(36, 49, 84)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(76, 102, 162)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(36, 49, 84)),
	}),
	ARMORY_SCREEN_STAGE_DARK_GRADIENT = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(20, 25, 40)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(34, 42, 66)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 25, 40)),
	}),
	-- A new selection pops the stage's text in from this scale (not on low-end devices).
	ARMORY_SCREEN_STAGE_POP_SCALE = 0.94,
	ARMORY_SCREEN_STAGE_POP_SECONDS = 0.14,
	-- An element's chip (stage) and dot (card); the words are SECRET_NEED_WORDS'.
	ARMORY_SCREEN_CHIP_HEIGHT = 16,
	ARMORY_SCREEN_CHIP_TEXT = 10,
	ARMORY_SCREEN_CHIP_PAD = 6,
	ARMORY_SCREEN_DARK_CHIP = 0.6, -- an unowned family's chip and dot, faded
	ARMORY_SCREEN_ELEMENT_COLORS = {
		fire = Color3.fromRGB(255, 122, 40),
		ice = Color3.fromRGB(110, 196, 255),
	} :: { [string]: Color3 },
	-- The detail column.
	ARMORY_SCREEN_TITLE_HEIGHT = 24,
	ARMORY_SCREEN_TITLE_TEXT = 17,
	ARMORY_SCREEN_TIER_TEXT = 22, -- the big "T3" at the title's right
	ARMORY_SCREEN_TIER_WIDTH = 64,
	ARMORY_SCREEN_LINE_HEIGHT = 16,
	ARMORY_SCREEN_LINE_GAP = 3,
	ARMORY_SCREEN_LINE_TEXT = 12,
	ARMORY_SCREEN_BUTTON_HEIGHT = ARMORY_SCREEN_BUTTON_HEIGHT,
	-- Up to four buttons share the row (two styles, Equip, Upgrade at 1.5 shares): 93, 93, 93
	-- and 140 in a 440 column, 79 and 119 in portrait's 377.
	ARMORY_SCREEN_BUTTON_MAX_WIDTH = 150,
	ARMORY_SCREEN_UPGRADE_SHARE = 1.5,
	ARMORY_SCREEN_BUTTON_TEXT_PAD = 4,
	-- The track: 20 pips in five bands; 19 wide in a 440 column, 16 in portrait's 377.
	ARMORY_SCREEN_PIP_HEIGHT = 14,
	ARMORY_SCREEN_PIP_GAP = 2,
	ARMORY_SCREEN_PIP_BAND_GAP = 6,
	ARMORY_SCREEN_PIP_MIN_WIDTH = 8,
	ARMORY_SCREEN_PIP_MAX_WIDTH = 26,
	ARMORY_SCREEN_PIP_CORNER = 3,
	ARMORY_SCREEN_PIP_OPEN_TRANSPARENCY = 0.6,
	ARMORY_SCREEN_PIP_DIM_TRANSPARENCY = 0.35,
	-- The window's start and top numbers under their pips, spilling past a narrow pip.
	ARMORY_SCREEN_PIP_MARK_GAP = 2,
	ARMORY_SCREEN_PIP_MARK_HEIGHT = 12,
	ARMORY_SCREEN_PIP_MARK_TEXT = 10,
	ARMORY_SCREEN_PIP_MARK_SPILL = 6,
	-- The shelf: landscape one row of cards (56 + the 4 px scroll bar inside 64), portrait a
	-- grid of five columns showing three rows.
	ARMORY_SCREEN_SHELF_HEIGHT = 64,
	ARMORY_SCREEN_CARD_WIDTH = 92,
	ARMORY_SCREEN_CARD_HEIGHT = ARMORY_SCREEN_CARD_HEIGHT,
	ARMORY_SCREEN_CARD_GAP = 6,
	ARMORY_SCREEN_CARD_PAD = 5,
	ARMORY_SCREEN_CARD_NAME_TEXT = 11,
	-- A portrait card is 68 wide (58 for the name): a long word scales down to this, the bottom
	-- bar's floor (BOTTOM_BAR_LABEL_MIN_TEXT), instead of truncating. The tier line ("Not
	-- found") shrinks to it too beside an element's dot.
	ARMORY_SCREEN_CARD_NAME_MIN_TEXT = LABEL_MIN_TEXT,
	ARMORY_SCREEN_CARD_NAME_HEIGHT = 26, -- two lines: "Piercing / Rifle"
	ARMORY_SCREEN_CARD_TIER_TEXT = 14,
	ARMORY_SCREEN_CARD_DOT = 8,
	ARMORY_SCREEN_CARD_DOT_GAP = 3, -- between the tier line's end and the dot
	ARMORY_SCREEN_CARD_HELD_BAR = 3,
	ARMORY_SCREEN_CARD_DARK = Color3.fromRGB(22, 29, 50),
	ARMORY_SCREEN_PORTRAIT_COLUMNS = 5,
	ARMORY_SCREEN_PORTRAIT_ROWS = 3,
	-- The Abilities tab: the lobby panel's rows (L2 W2), centred and capped.
	ARMORY_SCREEN_ABILITY_MAX_WIDTH = 520,
	ARMORY_SCREEN_ABILITY_ROW_HEIGHT = 68, -- name, two lines of text, the price
	ARMORY_SCREEN_ABILITY_NAME_TEXT = 15,
	ARMORY_SCREEN_ABILITY_BUTTON_WIDTH = 104,
	ARMORY_SCREEN_ABILITY_NOTE_WIDTH = 132, -- the hub's "Bought in the dungeon's lobby"
	ARMORY_SCREEN_VALOR_ROW_HEIGHT = 20,
	-- A press the server never answered is live again after this long (L3-21: 3 s at most).
	ARMORY_SCREEN_RESULT_TIMEOUT_SECONDS = 3,
	ARMORY_SCREEN_TOAST_SECONDS = 2.5,

	-- FlameFx: a held fire stream, per shooter, from the hand to the reach the server cut at the
	-- first wall (the strike's size). Particles in a widening cone, and a tapered core that is
	-- the whole look on low-end devices (and fainter over the particles elsewhere). The stream
	-- stays this long after its last tick (2 intervals at rate 10, floored as the Beam's is).
	COMBAT_FLAME_LINGER_INTERVALS = 2,
	COMBAT_FLAME_MIN_LINGER_SECONDS = 0.25,
	COMBAT_FLAME_CORE_START_WIDTH = 0.6,
	COMBAT_FLAME_CORE_TRANSPARENCY = 0.55, -- over the particles
	COMBAT_FLAME_CORE_LOW_END_TRANSPARENCY = 0.25, -- alone
	COMBAT_FLAME_CORE_COLOR = Color3.fromRGB(255, 226, 140),
	COMBAT_FLAME_EDGE_COLOR = Color3.fromRGB(255, 104, 28),
	COMBAT_FLAME_TAIL_COLOR = Color3.fromRGB(150, 40, 20),
	COMBAT_FLAME_PARTICLE_RATE = 70, -- per second, per stream
	COMBAT_FLAME_PARTICLE_LIFETIME = 0.3, -- particles cross the reach in this long
	COMBAT_FLAME_PARTICLE_START_SIZE = 0.5,
	COMBAT_FLAME_PARTICLE_END_SHARE = 0.55, -- end size = width x this
	COMBAT_FLAME_WOBBLE = 0.12, -- core width flicker (not under reducedMotion)
	COMBAT_FLAME_WOBBLE_HZ = 9,
	COMBAT_FLAME_LIGHT_RANGE = 12,
	COMBAT_FLAME_LIGHT_BRIGHTNESS = 2,
	-- Fallback width when neither the strike nor the config has one.
	COMBAT_FLAME_DEFAULT_WIDTH = 4,

	-- ReactFx: a bramble heating (the server's Heat attribute, 0 to 1) darkens toward charcoal
	-- and throws embers; when it burns, a flash and a ghost of its box that shrinks away, with
	-- smoke (not on low-end devices).
	REACT_CHAR_COLOR = Color3.fromRGB(42, 28, 20),
	REACT_EMBER_COLOR = Color3.fromRGB(255, 140, 40),
	REACT_EMBER_RATE = 36, -- per second at full heat
	REACT_EMBER_LOW_END_RATE = 10,
	REACT_FLASH_COLOR = Color3.fromRGB(255, 190, 90),
	REACT_FLASH_SECONDS = 0.25,
	REACT_GHOST_SECONDS = 0.7,
	REACT_GHOST_TRANSPARENCY = 0.15,
	REACT_SMOKE_COUNT = 30,
	REACT_SMOKE_SECONDS = 1.6,
	-- L2-56: a water cell the server froze gets a pale glint over its box and a burst of frost
	-- motes (not on low-end devices, where the glint alone says it).
	REACT_ICE_FLASH_COLOR = Color3.fromRGB(226, 246, 255),
	REACT_ICE_FLASH_SECONDS = 0.35,
	REACT_ICE_FLASH_TRANSPARENCY = 0.25,
	REACT_ICE_BURST_COLOR = Color3.fromRGB(205, 238, 255),
	REACT_ICE_BURST_COUNT = 10,
	REACT_ICE_BURST_SECONDS = 0.9,

	-- FrostFx (L2-49, L2-56): an ice family's swing draws its hitbox effect in the frost colour and
	-- throws a frost puff along its arc (no puff on low-end devices). On the local player's own
	-- swing, every unfrozen water cell the server's rule (WorldReact.Chills) names shows a ghost
	-- of ice at once; the real cell replaces it. Otherwise (fix round c-m2) the swing's answer
	-- decides: a refusal takes it at once, the answering strike lets it stand
	-- COMBAT_FROST_GHOST_GRACE_SECONDS more (the server freezes right after it broadcasts the
	-- strike, so `Ice` replicates within a step), and an unanswered swing loses it after
	-- COMBAT_RANGE_SWING_ANSWER_SECONDS.
	COMBAT_FROST_HITBOX_COLOR = Color3.fromRGB(140, 214, 255),
	COMBAT_FROST_PUFF_COLOR = Color3.fromRGB(214, 240, 255),
	COMBAT_FROST_PUFF_POINTS = 7, -- along the arc
	COMBAT_FROST_PUFF_PER_POINT = 3,
	COMBAT_FROST_PUFF_SECONDS = 0.6,
	COMBAT_FROST_PUFF_REACH_SHARE = 0.8, -- puffs sit this share of the swing's range out
	COMBAT_FROST_PUFF_DROP = 1, -- studs under the swing's origin (toward the ground)
	COMBAT_FROST_GHOST_COLOR = Color3.fromRGB(176, 224, 250),
	COMBAT_FROST_GHOST_TRANSPARENCY = 0.5,
	COMBAT_FROST_GHOST_GRACE_SECONDS = 0.3,
	-- Frost Quake (AbilityFx/FrostQuake): Earthquake's rings in ice, with shards for cracks.
	COMBAT_FROST_QUAKE_RING_COLOR = Color3.fromRGB(120, 200, 255),
	COMBAT_FROST_QUAKE_SHARD_COLOR = Color3.fromRGB(196, 236, 255),
	COMBAT_FROST_QUAKE_FROST_COLOR = Color3.fromRGB(226, 244, 255),

	-- Sibling ZIndex tiers so modal layers never depend on instance creation order.
	ZINDEX_CARD = 15,
	-- R8 of the L3 W1 fix round: the hub's party invite is a small card that takes its own taps,
	-- so it stays above the full-screen cards (the Armory screen) and below the dialogs.
	ZINDEX_INVITE = 17,
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
