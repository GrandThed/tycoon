# L4 W3 relay from ui-engineer B — the RunTally API (for ui-engineer A's hub host)

**Fix round (2026-10-23, F13, F14): nothing you call changed.** The rules moved into the new pure
`src/client/UI/TallyRules.luau` (a sibling of `RunTally` in both places). `RunTally.Rows`, `Totals`, `Owned`,
`NextAbility` and `WithText` keep their signatures and answers; they now hand `TallyRules` the Expeditions config from
`Catalog`. `RunTally.Row`, `Totals` and `Wallet` are re-exported from `TallyRules`, so your type annotations still
resolve. Two changes in behaviour, both safer: `Owned` (and `Wallet`) read NaN and infinity as 0 (Format.Cash never
returns on infinity), and `NextAbility` skips an `abilities.upcoming` entry that is not a table or misses a string `id`,
`name`, `text` or `with` (slice 3 s4: it used to throw on a missing name). The Valor badge in the rows is now a "◆"
glyph, not a turned Frame (F14).

**Optional, additive: `RunTally.Wallet(cash, combat, material)`** = `TallyRules.Wallet`, the wallet line both hosts
build: `{ cash = cash, materials = Owned(combat.materials, material), valor = combat.valor }`, any count that is not a
finite number above 0 read as 0, `combat` nil or not a table read as none. The combat host now builds its wallet with
it. If the hub's `tallyWallet` used it too (`RunTally.Wallet(current.state.cash, current.state.combat, tallyMaterial)`),
the review's p6 (the wallet's cash source) would be one call line for the designer to pin; your call.

```lua
RunTally.Wallet(cash: number, combat: any, material: string): Wallet
```

**Changed since the first version (all additive, the module is built to this text):** `Row.glyph` is gone (a `key`
row draws its key icon from its `kind`); `Deps.modal` added (the hub's scrim takes taps); `RunTally.WithText(nodeId)`
added (the "with the Castle" words, for ArmoryAbilityPage if you want them shared).

Contract §4.2. The module is `src/client/UI/RunTally.luau` (ui B owns it; the combat place maps it beside
`MapScreen` in `combat.project.json`). The hub already sees it as `script.Parent.RunTally` from any `src/client/UI`
module (it lives in that folder). It requires `Shared/Types`, `Shared/Format`, `Shared/Catalog` and its siblings
`Create`, `Theme`, `Motion`. It plays no sound; play your own click in `onButton` if the hub wants one.

```lua
local RunTally = require(script.Parent:WaitForChild("RunTally"))

-- One display row, built by RunTally.Rows from RunSummary.lines (never by hand: both hosts agree).
export type Row = {
	kind: string,       -- the RunLine's kind ("raiders" | "camp" | "boss" | "chest" | "key" | "firstClear" | "mentor")
	label: string,      -- the row's words: "Raiders ×112", "Pickets", "The Camp Chief", "First Hard clear", ...
	cash: number,
	material: string,   -- "" = none
	materials: number,  -- the amount of `material`
	valor: number,      -- a `key` row draws a key icon and its label, no amounts
}
-- The run's (or the session's) totals: the material is the main one (RunTally.Totals picks it).
export type Totals = { cash: number, material: string, materials: number, valor: number }
-- What the player owns NOW, after the run (the latest Snapshot / hub state). `materials` = the amount of
-- Totals.material. The card rolls cash from max(0, cash − totals.cash) up to cash.
export type Wallet = { cash: number, materials: number, valor: number }
export type Button = { id: string, text: string, accent: boolean? }
export type View = {
	kicker: string,        -- "EXPEDITION REPORT" (hub), "RUN REPORT" (combat)
	title: string,         -- RunSummary.title in the hub
	subtitle: string?,
	star: boolean,         -- a new star (a ★ beside the title); the hub passes false
	lines: { Row },        -- RunTally.Rows(summary.lines)
	totals: Totals,        -- RunTally.Totals(summary)
	wallet: Wallet,
	note: string?,         -- one small line under the totals (combat: the first clear's family); nil = none
	nextAbility: string?,  -- RunTally.NextAbility(combat.abilities); nil = no line
	buttons: { Button },   -- hub: { { id = "dismiss", text = "Dismiss", accent = true } }
}
export type Deps = {
	onButton: (id: string) -> (),
	-- true = the dim behind the card takes every tap (the city: a stray tap must not buy a building),
	-- and a tap on it skips like one on the card; false / nil = it takes none (the dungeon place's
	-- camera drag must reach the world). The hub should pass true.
	modal: boolean?,
}
export type Handle = {
	Show: (view: View) -> (),            -- restarts the tally from the first row; call once per summary
	SetWallet: (wallet: Wallet) -> (),   -- retargets the roll when a later Snapshot / state lands
	SetCountdown: (text: string?) -> (), -- one small line in the header (combat: "Back to camp in 8"); nil hides it
	Skip: () -> (),                      -- jump to the end state (a tap on the card does the same)
	Hide: () -> (),
	IsVisible: () -> boolean,
	SetLayout: (scale: number, viewportSize: Vector2) -> (), -- the HUD's scale and the parent ScreenGui's AbsoluteSize
	Destroy: () -> (),
}

RunTally.new(parent: Instance, deps: Deps): Handle
RunTally.Rows(lines: { Types.RunLine }?): { Row }       -- the words; nil or {} gives {}
RunTally.Totals(summary: Types.RunSummary): Totals       -- cash, valor, main material (largest amount, ties by name)
RunTally.Owned(materials: { [string]: any }?, material: string): number  -- a profile map's amount, 0 if absent
RunTally.NextAbility(owned: { [string]: boolean }?): string?
	-- "next: Double Jump · 10 Valor" (first of Unlocks.Sellable not owned, by `order`), else
	-- "next: Glide · with the Castle" (first `abilities.upcoming` not owned, the node's name), else nil
RunTally.WithText(nodeId: string): string
	-- "with the Castle"; a node name that starts with The / A / An / Another keeps its own article
```

Hub host sketch (contract §4.2 "Hub"):

```lua
local tally = RunTally.new(screenGui, { modal = true, onButton = function(id) if id == "dismiss" then tally.Hide() --[[ + your chaining ]] end end })
local totals = RunTally.Totals(summary)
tally.Show({
	kicker = "EXPEDITION REPORT",
	title = summary.title,
	star = false,
	lines = RunTally.Rows(summary.lines),
	totals = totals,
	wallet = { cash = state.cash, materials = RunTally.Owned(state.combat.materials, totals.material), valor = state.combat.valor },
	nextAbility = RunTally.NextAbility(state.combat.abilities),
	buttons = { { id = "dismiss", text = "Dismiss", accent = true } },
})
-- on each later Snapshot while tally.IsVisible(): tally.SetWallet({ ... the same three ... })
-- on each layout pass: tally.SetLayout(scale, screenGui.AbsoluteSize)
```

Behaviour you can rely on: the card sits at `Theme.ZINDEX_CARD` on a non-Active scrim (it never swallows a drag behind
it); the card itself is Active and a tap on it outside a button skips to the end; buttons answer at any moment; every
tween goes through `Motion`; the flying-icon count follows `Theme.lowEndDevice`; it fits 640×360 under the top bar
(a two-column card when the parent is short and wide, one column otherwise; the rows scroll, the totals never do).

## Asked of ui-engineer A (MapScreen, your file) — done by ui A (`Selected`, and `FirstPick`, which the combat host now uses too)

The Studio **R** key (contract §9) sends `"<levelId>:<difficulty>"` from the map's current selection. `MapScreen`
has no getter, so please add one to `MapScreenHandle` (read-only, no behaviour change):

```lua
	-- The selected node's level and difficulty (nil, "" when nothing or a node without a level is selected).
	Selected: () -> (string?, string),
```

implemented as `local current = selectedView(); return if current ~= nil then current.node.level else nil, view.difficulty`.
Until it lands the combat host falls back to `debug.provingLevel` / `provingDifficulty` (it reads the field through a
guarded lookup, so neither order of landing breaks the build).

## Theme (your file) after SummaryCard goes

`SummaryCard.luau` was the only combat reader of `Theme.COMBAT_SUMMARY_WIDTH` and `COMBAT_SUMMARY_LINE_GAP`; RunTally
keeps its own presentation table, so once `ExpeditionSummaryCard.luau` is gone too, check those two (and anything else
only the old cards read) for other readers before deleting them.
