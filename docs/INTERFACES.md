# INTERFACES — frozen contracts

Updated by the lead at the start of each milestone. Agents conform to this document exactly.
If your task needs a change to a file or contract you don't own, **report it in your final
message** — never edit across an ownership boundary.

Current milestone: **M3 — Presentation** (mobile UI pass, sounds, reveal/level-up feedback,
era-advance ceremony, welcome-back card, asset manifest generator, VIP skin support). M1 and M2
contracts below remain standing; the **M3 contracts** section at the end defines this
milestone's additions and the amendments called out there.

## Environment notes (all agents)

- Repo root is `C:\Users\benja\Desktop\tycoon`; it IS a git repository since 2026-09-08 (one
  commit). Do not commit; the lead commits.
- Toolchain is Rokit-managed at `~/.rokit/bin` (restored 2026-09-08; repo-root `rokit.toml`
  pins versions). Neither PowerShell nor Bash has it on PATH by default:
  - PowerShell: `$env:PATH = "$HOME\.rokit\bin;$env:PATH"`
  - Bash: `export PATH="$HOME/.rokit/bin:$PATH"`
- **Python is `py`** (3.14). `python` and `python3` resolve to Windows Store stubs that print
  "Python was not found" — never invoke them. Every doc/tool command uses `py tools/...`.
- Typecheck: `luau-lsp analyze --definitions=tools/types/globalTypes.d.luau --ignore "Packages/**"
  --ignore "ServerPackages/**" src` — the definitions file is committed; **never re-download it**.
- Line endings are LF everywhere (`.gitattributes`); stylua checks fail on CRLF.
- You may create empty directories anywhere; create files only inside your ownership.

## M2 ownership

| Owner | Files |
|-------|-------|
| luau-engineer | `src/server/**`, `src/shared/{Types,Economy,Format,Catalog}.luau`, `wally.toml`, `default.project.json` (both unfrozen this milestone for the ServerPackages change) |
| ui-engineer | `src/client/**` |
| economy-designer | `src/shared/Config/**` (Game.json; era JSONs 2–4 new; 1_Village re-tune allowed), `src/shared/Layouts/{Boomtown,Metropolis,OrbitalColony}.luau` (new), `tools/sim_economy.py` (new), `docs/BALANCE.md` (new) |
| docs-keeper (after QA) | `docs/PLAYTEST.md`, `docs/MANUAL_STEPS.md`, `README.md`, status ticks in `docs/PLAN.md` |

M0 rules still in force: `--!strict` everywhere; PascalCase modules/methods, camelCase locals,
UPPER_SNAKE constants; no `wait()`/`spawn()`/`delay()`/`_G`/`Instance.new` parent arg; every
service/controller keeps `Init()`/`Start()`; boot order and boot prints unchanged.
**No numeric or geometric constant may live in Luau logic** — numbers live in `Config/*.json`,
geometry/visual constants in the era's layout module.

## Game.json — schema v1.2 (additions over v1, everything else unchanged)

- `"plotMargin": 20` — studs of gap between adjacent plots on the ring.
- `"hubRadius": 30` — radius in studs of the central hub platform players spawn on.
- `remotes` gains `"padTouchDebounce": 0.5` — seconds between accepted touches per buy pad.
- `levelCost` gains `"minBase"` (v1.2) — floor substituted for `baseCost` in the level-up cost
  formula so zero-cost starter slots don't get free level-ups. Value owned by economy-designer.

Values shown are the defaults; economy-designer owns final values.

## Era config JSON schema (frozen) — `Config/Eras/<eraIndex>_<Name>.json`

```json
{
  "eraIndex": 1,
  "name": "Village",
  "slots": [
    {
      "id": "campfire",
      "type": "building",
      "name": "Campfire",
      "modelName": "Campfire",
      "description": "small campfire with logs",
      "baseCost": 0,
      "baseIncome": 1,
      "requires": "optionalSlotId",
      "multiplier": 0.05
    }
  ]
}
```

Semantics (all frozen):

- **File/module name** is `<eraIndex>_<Name>` (e.g. `1_Village`). The layout ModuleScript name
  equals the era's `name` field (e.g. `Layouts/Village.luau`).
- `id`: camelCase, unique within the era, **stable forever** — ids become persistence keys at
  M2 and may never be renamed after that.
- `slots` array order **is** the purchase order and the pad-reveal order.
- `requires`: optional slotId. Omitted ⇒ the previous slot in the array. First slot ⇒ no
  requirement. The **first slot must have `baseCost: 0`** (players start with cash 0).
- `type` semantics:
  - `building` — `baseIncome > 0`, levelable 1..`maxLevel`. `multiplier` absent.
  - `unlock` — `baseIncome: 0`, not levelable, `multiplier` = era-wide bonus (e.g. `0.10`).
  - `decor` — `baseIncome: 0`, not levelable, `multiplier` tiny (`0.01`–`0.02`).
  - `monument` — exactly one, **last in the array**; `baseIncome: 0`, no multiplier, not
    levelable. Owning it completes the era (Advance Era lands at M2).
- Era-wide multiplier stacking is **additive**: `eraMult = 1 + Σ multiplier` over owned
  unlock/decor slots.

## Layout module shape (frozen) — `Layouts/<Name>.luau`

Layout modules are the era's *visual/geometric* config (Luau because JSON can't hold
Vector3/Color3). Shape:

```lua
--!strict
return {
	plotSize = Vector3.new(120, 1, 120),      -- the plot base part
	baseColor = Color3.fromRGB(106, 127, 63), -- plot base tint (per-era, spec §5)
	padSize = Vector3.new(6, 0.5, 6),
	padOffset = 8,                            -- studs in front of the anchor (along facing)
	placeholderSize = Vector3.new(8, 8, 8),   -- spec §5 fallback part size
	slots = {
		-- one entry per slot id in the era config; position relative to plot center,
		-- Y is ground level offset; padPosition overrides the default "padOffset studs
		-- in front of the building" rule when set.
		-- rotationY: degrees, Roblox-native CFrame.Angles(0, rad(r), 0) — 0 faces −Z
		-- (the plot's front/hub edge), positive turns COUNTERCLOCKWISE seen from above.
		campfire = { position = Vector3.new(0, 0, -40), rotationY = 0 },
		-- padPosition = Vector3.new(...) (optional)
	},
}
```

Every slot id in the era config must have a layout entry (QA-checkable 1:1). The monument
belongs visually front-and-center.

## Types.luau (frozen at M1)

Exact exported types (field-for-field):

```lua
export type SlotType = "building" | "unlock" | "decor" | "monument"

export type SlotConfig = {
	id: string, type: SlotType, name: string, modelName: string, description: string,
	baseCost: number, baseIncome: number, requires: string?, multiplier: number?,
}

export type EraConfig = { eraIndex: number, name: string, slots: { SlotConfig } }

export type SlotState = { level: number }

-- Full profile schema v1 (spec §7), held in memory this milestone, persisted at M2.
export type PlayerState = {
	version: number,
	cash: number, era: number, rebirthCount: number, legacy: number,
	slots: { [string]: SlotState },
	passes: { [string]: boolean }, processedReceipts: { string },
	lastSeen: number, incomeAtSave: number,
	stats: { totalCashAllTime: number, erasCompleted: number, playtimeSeconds: number },
	settings: { music: boolean, sfx: boolean },
}

export type Multipliers = { legacy: number, pass: number, premium: number, neighbors: number }

export type Snapshot = {
	kind: "snapshot", plotIndex: number, eraName: string,
	state: PlayerState, incomePerSecond: number,
	-- M2: present only on the first snapshot after an offline grant (elapsed >= 60 s).
	welcomeBack: { grantedCash: number, elapsedSeconds: number }?,
}

export type Delta = {
	kind: "delta",
	cash: number?, incomePerSecond: number?, slots: { [string]: SlotState }?,
}

export type ActionResult = {
	-- M2 adds the era actions; for them slotId is "" (no slot involved).
	action: "buy" | "levelUp" | "advanceEra" | "rebirth", slotId: string, ok: boolean,
	reason: ("insufficientFunds" | "locked" | "invalid")?,
}
```

Config types (`GameConfig` etc. mirroring Game.json v1.1) also live in Types.luau; their
fields follow the JSON keys exactly.

## Economy.luau — pure API (frozen; sim_economy.py mirrors this at M2)

No Roblox globals of any kind (no `script`, no services). Config arrives as arguments.

```lua
Economy.MilestoneMult(level, milestoneLevels, milestoneMultiplier): number
	-- milestoneMultiplier ^ (count of milestoneLevels <= level)
Economy.SlotIncome(baseIncome, level, gameConfig): number
	-- baseIncome * (1 + levelIncomeBonus * (level - 1)) * MilestoneMult(level, ...)
Economy.LevelUpCost(baseCost, targetLevel, gameConfig): number
	-- max(baseCost, levelCost.minBase) * levelCost.factor * levelCost.growth ^ (targetLevel - 1)
	-- (minBase floor added post-wave: with the mandated free first slot, a raw baseCost of 0
	--  made all its level-ups free — instant max level. Spec deviation documented per §12.6.)
Economy.LevelUpCostTotal(baseCost, fromLevel, toLevel, gameConfig): number
	-- sum of LevelUpCost for targetLevel = fromLevel+1 .. toLevel
Economy.EraMult(slots, eraConfig): number
	-- 1 + sum of slot.multiplier over OWNED unlock/decor slots
Economy.LegacyMult(legacy, gameConfig): number       -- 1 + legacy.incomePerPoint * legacy
Economy.NeighborsMult(playerCount, gameConfig): number
	-- 1 + min(neighbors.perPlayer * (playerCount - 1), neighbors.maxBonus)
Economy.IncomePerSecond(slots, eraConfig, gameConfig, mults: Multipliers): number
	-- (sum of SlotIncome over owned building slots) * EraMult * mults.legacy * mults.pass
	--   * mults.premium * mults.neighbors
Economy.LegacyGain(eraIndex, totalLevelsThisEra, rebirthCount, gameConfig): number
	-- floor(gainBase * eraIndex * (1 + totalLevels/gainLevelsDivisor)
	--       * (1 + rebirthCount * gainRebirthBonus))
	-- NOTE: floor wraps the WHOLE product (spec's formula floors only the first factor and
	-- can yield fractional legacy; flooring the product keeps legacy integral — documented
	-- spec clarification per §12.6).
Economy.OfflineGrant(elapsedSeconds, incomePerSecond, capSeconds, efficiency): number
	-- clamp(elapsed, 0, cap) * ips * efficiency  (used at M2; frozen now)
```

In M1 the caller passes `Multipliers` of all 1s (legacy/neighbors activate M2, pass/premium M4).

## Format.luau (frozen)

- `Format.Cash(n: number): string` — `n < 1000` ⇒ plain floored integer. Otherwise divide by
  1000^tier; show one decimal when the leading value is < 100 (`1.2K`, `45.6M`), none at ≥ 100
  (`123K`); strip trailing `.0`. Suffix order: `K, M, B, T, aa, ab, ac, …` (tier 5 = `aa`).
- UI composes rates itself (e.g. `Format.Cash(ips) .. "/s"`).

## Catalog.luau (new, luau-engineer) — shared config lookup

Instance traversal + caching lives here once, used by server and client:

```lua
Catalog.GetGameConfig(): Types.GameConfig
Catalog.GetEraConfig(eraIndex: number): Types.EraConfig?   -- by module name "<i>_<Name>"
Catalog.GetLayout(eraName: string): EraLayout?             -- Layouts/<Name>
Catalog.GetEraCount(): number                              -- M2: number of era configs; the
                                                           -- max era is never hardcoded
```

## Remotes (frozen for M1)

`RemoteService` creates a `Remotes` folder in ReplicatedStorage at `Init()` containing ALL
reserved RemoteEvents (M2+ ones exist but have no handlers yet). Client `WaitForChild`s.

Client → server:
- `RequestSnapshot()` — no args; client fires when ready; server replies with a full Snapshot.
  (Also send one proactively on join; duplicate snapshots must be harmless to the client.)
- `RequestBuy(slotId: string)`
- `RequestLevelUp(slotId: string, count: number)` — count is an integer 1..100. Server grants
  `n = min(count, levels affordable, maxLevel − currentLevel)` and charges
  `LevelUpCostTotal` for exactly `n`; `n = 0` ⇒ ActionResult failure. ("Max" = client sends 100.)
- Reserved, no M1 handler: `RequestAdvanceEra`, `RequestRebirth`, `RequestPrompt`.

Server → client:
- `StateChanged(Snapshot | Delta)` — snapshot on join/request; deltas batched at
  ≤ `remotes.stateDeltaHz`; only changed fields present.
- `ActionResult(ActionResult)` — sent **only on failure** in M1 (client shows feedback).
  Successes are visible via StateChanged.

Validation on every intent (server, in this order): rate limit → payload types → player has a
plot → slotId exists in the player's current era → ownership/level rules → `requires` chain →
affordability. Never trust client amounts.

Rate limiting: token bucket per player per remote, `remotes.callsPerSecond`, **silent drop**
on overflow (no kick, no ActionResult).

## Server runtime contracts (M1)

- **DataService** owns in-memory `PlayerState` (API: `GetState(player): PlayerState?`; creates
  schema-v1-shaped state on join, discards on leave). M2 swaps internals to ProfileStore behind
  the same API. State is lost on leave in M1 — by design.
- **EconomyService** owns the income loop: one Heartbeat accumulator per server at 1 Hz per
  spec (grant whole elapsed seconds, carry the remainder — no drift), cash mirrored to a player
  attribute `Cash` each grant, dirty-flag delta batching flushed at ≤ `stateDeltaHz`, snapshot
  emission. Applies `debug.studioIncomeMultiplier` to income **only** when `RunService:IsStudio()`.
- **PlotService** owns world geometry and purchases: at `Init()` builds the hub platform +
  SpawnLocation at origin and `plotCount` plot bases on a ring (radius computed from plotSize,
  plotMargin, plotCount — formula in code, numbers from config/layout). Structure per plot:

  ```
  Workspace/Plots/Plot_<i>/
    Base            -- plotSize part, baseColor, anchored; Attachments named Slot_<slotId>
    Buildings/      -- spawned models/placeholders
    Pads/           -- generated buy pads
  ```

  Claim lowest free plot on PlayerAdded; on leave, release + destroy spawned content + disconnect
  everything (no connection leaks). Pad lifecycle: a pad exists iff its slot is unowned AND its
  `requires` slot is owned; pad shows slot name + cost on a BillboardGui; `Touched` (debounced
  `padTouchDebounce`, owner-validated) triggers the same buy path as `RequestBuy`. Buying spawns
  the model: try `ServerStorage/Assets/<EraName>/<modelName>` clone to the anchor; if missing,
  placeholder part (`placeholderSize`, neutral color, BillboardGui with `modelName`) — never an
  error. Owned buildings get a ProximityPrompt (owner-validated) = level-up ×1.
  `debug.studioFreeBuy` (Studio only) skips the affordability check, never the `requires` chain.
- **MonetizationService** stays an empty stub.

## Client contracts (M1)

- HUD top bar: cash (`Format.Cash`), income/s, era badge (name + index). Bind cash to the
  `Cash` attribute or StateChanged — either, but never compute cash client-side.
- Build panel: toggled by a Build button (bottom bar position, mobile-first, tap targets
  ≥ 44 px). Lists every slot of the current era in order with: name, state (locked / cost /
  owned+level), Buy or Level Up ×1 button, income-delta preview (via shared `Economy`), and a
  "next affordable" highlight. Locked = `requires` not owned. Panel fires `RequestBuy` /
  `RequestLevelUp(slotId, 1)`.
- Consume `StateChanged` (snapshot replaces local model; delta merges), fire `RequestSnapshot`
  once on boot. Handle duplicate snapshots gracefully.
- `ActionResult` failures ⇒ brief non-blocking feedback (e.g. cost label flash); no sounds yet
  (M3).
- No camera work, no plot visuals work this milestone (server renders pads/buildings).

## Definition of done (M1) — met

`stylua --check .`, `selene src`, `rojo build` all green; `luau-lsp analyze` clean; era config
and layout 1:1 on slot ids; a player joining in Studio gets a plot, buys the free first slot on
a pad, watches income tick, buys/levels through all 24 slots (placeholders only), and the Build
panel mirrors it all. Reviewer verdict SHIP.

---

# M2 contracts — Persistence & eras

## Dependency changes (luau-engineer; shapes unfrozen for exactly this)

- `wally.toml` gains `[server-dependencies]` with `ProfileStore = "lm-loleris/profilestore@1.0.3"`
  (shared `[dependencies]` keeps Signal). `wally install` produces `ServerPackages/`.
- `default.project.json` maps `ServerPackages/` → `ServerScriptService/ServerPackages`.
- `rojo build` must succeed with both in place.

## Join/leave orchestration (replaces the M1 implicit flow)

`Main.server.luau` becomes the explicit per-player orchestrator — no service henceforth
assumes any PlayerAdded/PlayerRemoving ordering:

1. PlayerAdded → `task.spawn`: `state = DataService.LoadAsync(player)` (yields; ProfileStore
   with session lock; pcall + retry + logging inside). If load fails or the session is locked:
   polite `player:Kick("Your data couldn't be loaded — please rejoin in a minute.")` and stop.
   If the player left during the yield (`player.Parent == nil`): release the profile and stop.
2. Then `EconomyService.ApplyOfflineGrant(player)` (see below), then `PlotService.ClaimPlot(player)`
   (builds pads/buildings from persisted `state.slots`), then the proactive snapshot (carries
   `welcomeBack` when applicable).
3. PlayerRemoving → `PlotService.Release(player)`, `EconomyService.Cleanup(player)`,
   `DataService.Release(player)` (final save via ProfileStore; lastSeen/incomeAtSave are already
   fresh — see tick rule). ProfileStore's own BindToClose handling covers shutdown flushes.
- `DataService.EnsureState` (M1) is retired; `GetState` remains and returns nil until LoadAsync
  completes — all existing nil-tolerant call sites keep working. Claim rebuilds owned buildings
  WITHOUT tweens/sounds (bulk restore, not 24 reveal effects).

## Persistence (DataService internals)

- ProfileStore store name `"PlayerData"`, key `"p_<UserId>"`. Profile template = schema v1
  (the exact `PlayerState` shape in Types.luau; `version = 1`).
- `Migrations`: table keyed by version, `Migrations[n](state)` upgrades n → n+1; on load, run
  sequentially while `state.version < CURRENT_VERSION`. Ships empty at M2 (v1 is current) but
  the mechanism must exist and be exercised by a unit-style guard (loading a v1 profile is a
  no-op).
- Every DataStore-touching call: pcall, retry with backoff, `warn` with player + attempt on
  failure (spec §7/§11).
- Studio: ProfileStore falls back to its mock when API access is off — playtest doc covers
  enabling Studio API access for real persistence tests.

## Offline progress (EconomyService)

- Tick rule (persistence freshness): every income tick also writes `state.lastSeen = os.time()`
  and `state.incomeAtSave = <current ips>` (cheap in-memory writes; whatever save fires next is
  always fresh). `stats.playtimeSeconds` accrues on the same tick; `stats.totalCashAllTime`
  accrues on every cash grant (income, offline) — not on spending.
- `ApplyOfflineGrant(player)`, before first snapshot: `elapsed = clamp(os.time() − lastSeen,
  0, offline.capSeconds)` (OfflinePro variants are M4; use the defaults), `granted =
  Economy.OfflineGrant(elapsed, state.incomeAtSave, cap, offline.efficiency)`, add to cash +
  totalCashAllTime. When `elapsed >= offline.welcomeBackMinSeconds` (Game.json v1.3 key,
  default 60) and `granted > 0`, attach `welcomeBack = { grantedCash, elapsedSeconds }` to the
  join snapshot. First-ever join (lastSeen == 0): no grant, no card.
- The offline grant is NOT multiplied by the Studio debug income multiplier.

## Advance Era / Rebirth (PlotService handlers; validation via the standard chain)

- `RequestAdvanceEra()`: valid iff player owns **every** slot of the current era (levels
  irrelevant) AND `state.era < Catalog.GetEraCount()`. Effects, atomically, in order:
  `state.legacy += Economy.LegacyGain(state.era, totalLevelsThisEra, state.rebirthCount, cfg)`
  where `totalLevelsThisEra = Σ state.slots[id].level over all owned slots`; `state.era += 1`;
  `state.cash = 0`; `state.slots = {}`; `stats.erasCompleted += 1`; plot torn down and rebuilt
  for the new era (base recolored from the new layout, pads regenerated, buildings cleared);
  fresh full Snapshot sent (client rebuilds the panel — a snapshot with a different era must
  rebuild rows, which the M1 client already treats as the non-same-era path).
- `RequestRebirth()`: valid iff `state.era == Catalog.GetEraCount()` AND every slot owned.
  Effects (AMENDED post-wave — lead ruling on a spec ambiguity, §12.6): rebirth is the
  final era's "advance": FIRST `state.legacy += Economy.LegacyGain(state.era,
  totalLevelsThisEra, state.rebirthCount, cfg)` (rebirthCount before increment), THEN
  `state.rebirthCount += 1`; existing legacy KEPT; `state.era = 1`; cash 0; slots {};
  `stats.erasCompleted += 1`; plot rebuild + fresh Snapshot. Rationale: "legacy earned on
  advance" alone would make the longest era (8–12 h) pay zero prestige currency; the
  formula's eraIndex factor exists to reward it. Cosmetic rank visuals are M3+.
- Failures → ActionResult with `action = "advanceEra" | "rebirth"`, `slotId = ""`,
  `reason = "locked"` (not all owned / wrong era) — same failure-only convention.
- Multipliers activate now: EconomyService computes `mults.legacy = Economy.LegacyMult(...)`
  and `mults.neighbors = Economy.NeighborsMult(#Players:GetPlayers(), cfg)` every tick
  (pass/premium stay 1 until M4).

## Eras 2–4 content (economy-designer)

- Files `2_Boomtown.json`, `3_Metropolis.json`, `4_OrbitalColony.json` + layout modules
  `Boomtown.luau`, `Metropolis.luau`, `OrbitalColony.luau` — same frozen schemas, ~24 slots
  each, same slot-mix guidance, monument last (TownHall / SkyscraperA / LaunchTower or similar
  PascalCase Kenney-plausible names).
- **Every era's first slot costs 0** (cash resets to 0 on advance/rebirth).
- Magnitudes roughly ×100 per era (spec §4). Pacing targets WITH the legacy earned from a
  first playthrough of prior eras: E2 1.5–2.5 h, E3 4–6 h, E4 8–12 h.
- Per-era `baseColor` distinct enough that an era advance is visually obvious even with
  placeholder parts.
- `plotSize` must be IDENTICAL across all era layouts (the plot ring is built once at boot
  from era 1's layout and never resized; era changes only recolor/re-anchor).

## tools/sim_economy.py (economy-designer)

- Mirrors `Economy.luau` function-for-function (incl. the minBase floor and whole-product
  LegacyGain floor). Reads `src/shared/Config/Game.json` + `Config/Eras/*.json` from the repo
  root — never duplicates a constant.
- Default run (`python tools/sim_economy.py`): simulates a full first playthrough, eras 1→4
  sequentially at 1 s resolution, greedy buy-cheapest strategy, carrying legacy across
  advances (neighbors/pass/premium = 1). Prints per era: completion time, longest wait between
  purchases, unlock beat times; plus the legacy carried into each era.
- `--era N` runs one era in isolation with a given `--legacy` (default 0). `--strategy rusher`
  buys slots only (the M1 spread metric). `--check` exits nonzero if any era in the default
  run misses its target band (bands live in the sim source with a comment — tool-only
  constants are sanctioned there). QA runs `--check`.
- Final output tables land in `docs/BALANCE.md` (designer-authored).

## Client additions (ui-engineer)

- Top bar: Legacy count (visible from era 1 so the first advance means something).
- Advance Era: when the monument is owned and era < GetEraCount(), show an "Advance Era"
  affordance (panel row/banner — your judgment); tapping opens a minimal confirm dialog: next
  era name, legacy to gain (compute client-side via `Economy.LegacyGain` from state), a static
  resets-vs-persists list, explicit Confirm → `RequestAdvanceEra()`. Full ceremony screen is M3.
- Rebirth: same pattern when era == GetEraCount() and monument owned → confirm →
  `RequestRebirth()`.
- Welcome-back: on a snapshot with `welcomeBack`, show a small non-blocking toast
  ("You earned $X while away — <t> offline"), auto-dismiss; polished into the real card at M3.
- Era change: a snapshot whose era differs from the local model rebuilds the Build panel rows
  and era badge (verify the M1 rebuild path actually covers this).

## Definition of done (M2)

Lint/analyze/build green; `wally install` green with ServerPackages; `python tools/sim_economy.py
--check` passes with all four eras in band; leave/rejoin restores state (mock or real API);
offline grant correct, capped, and toasted; a full accelerated playthrough (Studio levers)
reaches Era 4, rebirths, and keeps Legacy; reviewer verdict SHIP.

---

# M3 contracts — Presentation

Goal: the game looks and sounds like a real game on a phone, with or without imported Kenney
assets. Nothing in this milestone changes balance, persistence keys, or the M1/M2 remotes'
payloads; everything below is additive unless marked **AMENDED**.

## M3 ownership

| Owner | Files |
|-------|-------|
| luau-engineer | `src/server/**`, `src/shared/{Types,Economy,Format,Catalog}.luau`, `default.project.json` (unfrozen only to add the `<Era>_VIP` asset folders) |
| ui-engineer | `src/client/**` (new UI modules allowed under `src/client/UI/`) |
| economy-designer | `src/shared/Config/**` (`Sounds.json` new; era JSONs gain `displayName` + per-slot `kit`; **no balance changes** — `baseCost`/`baseIncome`/`multiplier` are frozen this milestone), `tools/gen_asset_manifest.py` (new), first generation of `docs/ASSET_MANIFEST.md` |
| docs-keeper (after QA) | `docs/PLAYTEST.md`, `docs/MANUAL_STEPS.md`, `README.md`, `docs/ASSET_MANIFEST.md` (regenerate), status ticks in `docs/PLAN.md` |

`src/shared/Layouts/**` are frozen this milestone (no owner edits them).

Presentation constants: `src/client/UI/Theme.luau` remains the sanctioned home for client-only
sizing, colors, and **presentation timings** (tween durations, particle counts, card auto-dismiss
seconds, reduce-motion factors) — this extends the M1 exemption and is the only place such
numbers may live. Audio ids/volumes live in `Config/Sounds.json`. Gameplay numbers stay in
`Game.json`/era configs; nothing new is added to `Game.json` this milestone.

## Era config schema v1.1 (economy-designer authors; everyone consumes)

Two additive fields, both **required** in every era file:

```json
{
  "eraIndex": 4,
  "name": "OrbitalColony",
  "displayName": "Orbital Colony",
  "slots": [
    { "id": "landingPad", "...": "...", "kit": "Space Kit" }
  ]
}
```

- `displayName`: human copy for the era (spaces allowed). `name` stays the frozen module/folder
  key (`Layouts/<name>`, `ServerStorage/Assets/<name>`). **All UI copy uses `displayName`**;
  `Snapshot.eraName` is unchanged (still `name`) — the client resolves display copy through
  `Catalog.GetEraConfig(era).displayName`.
- `kit`: the Kenney kit the model should be imported from (free text, e.g. `"Fantasy Town Kit"`,
  `"Nature Kit"`, `"City Kit (Commercial)"`). Consumed only by the manifest generator; Luau
  never reads it. Every slot's `modelName` must be PascalCase `[A-Z][A-Za-z0-9]*`, unique
  within its era, and `description` non-empty — the generator's `--check` enforces all three.

`Types.EraConfig` gains `displayName: string`; `Types.SlotConfig` gains `kit: string?` (optional
in the type so old configs still typecheck; required by the generator).

## Sounds.json schema v1 — `Config/Sounds.json` (economy-designer authors; client consumes)

```json
{
  "version": 1,
  "groups": { "SFX": 0.6, "Music": 0.35, "UI": 0.5 },
  "sounds": {
    "uiClick":           { "id": 0, "group": "UI",    "volume": 1.0 },
    "purchase":          { "id": 0, "group": "SFX",   "volume": 1.0 },
    "reveal":            { "id": 0, "group": "SFX",   "volume": 0.8 },
    "levelUp":           { "id": 0, "group": "SFX",   "volume": 0.8, "pitchPerMilestone": 0.08 },
    "levelUpMilestone":  { "id": 0, "group": "SFX",   "volume": 1.0 },
    "insufficientFunds": { "id": 0, "group": "UI",    "volume": 0.8 },
    "eraAdvance":        { "id": 0, "group": "Music", "volume": 1.0 },
    "rebirth":           { "id": 0, "group": "Music", "volume": 1.0 },
    "welcomeBack":       { "id": 0, "group": "Music", "volume": 0.8 }
  },
  "ambient": {
    "Village":       { "id": 0, "group": "Music", "volume": 0.25 },
    "Boomtown":      { "id": 0, "group": "Music", "volume": 0.25 },
    "Metropolis":    { "id": 0, "group": "Music", "volume": 0.25 },
    "OrbitalColony": { "id": 0, "group": "Music", "volume": 0.25 }
  }
}
```

- `groups`: the three `SoundGroup`s the client creates under `SoundService` with these default
  volumes. `UI` and `SFX` follow the `sfx` setting; `Music` follows `music`.
- `sounds` keys are **frozen event names** (exactly the nine above); `id` is a numeric Roblox
  asset id, `0` = silent (skip, never warn). `volume` is a 0–1 multiplier inside the group;
  `pitchPerMilestone` (levelUp only) adds that much `PlaybackSpeed` per milestone already
  reached by the building's level, so higher tiers tick higher (spec §9).
- `ambient` keyed by era `name`; loops at low volume while the player's era is that era;
  toggled by the `music` setting. All ids ship as `0` (uploads are a MANUAL_STEPS item).
- Types (luau-engineer): `SoundGroupName = "SFX" | "Music" | "UI"`,
  `SoundDef = { id: number, group: SoundGroupName, volume: number, pitchPerMilestone: number? }`,
  `SoundsConfig = { version: number, groups: { [string]: number }, sounds: { [string]: SoundDef },
  ambient: { [string]: SoundDef } }`. `Catalog.GetSoundsConfig(): Types.SoundsConfig` (cached,
  same pattern as `GetGameConfig`).

## Remotes — M3 additions (RemoteService owns creation + validation)

Server → client, fire-and-forget, owner only, **never** on bulk restore (join/claim/era rebuild):

- `FxEvent(payload: Types.FxEvent)` — one RemoteEvent, discriminated by `kind`:

```lua
export type FxReveal = { kind: "reveal", slotId: string, slotType: SlotType, modelName: string }
export type FxLevelUp = {
	kind: "levelUp", slotId: string, fromLevel: number, toLevel: number,
	milestone: boolean, -- true iff a milestoneLevels entry lies in (fromLevel, toLevel]
}
export type FxEraAdvance = { kind: "eraAdvance", fromEra: number, toEra: number, legacyGained: number }
export type FxRebirth = {
	kind: "rebirth", fromEra: number, toEra: number, legacyGained: number, rebirthCount: number,
}
export type FxEvent = FxReveal | FxLevelUp | FxEraAdvance | FxRebirth
```

Firing points (PlotService), all AFTER the state mutation succeeds:
- `tryBuy` success (pad touch or `RequestBuy`): `reveal`, fired after `spawnBuilding` +
  `refreshPads` + `MarkDirty` so the instance replicates ahead of the event.
- `tryLevelUp` success: `levelUp` with the granted range.
- `tryAdvanceEra` / `tryRebirth` success: `eraAdvance` / `rebirth` fired **before** the fresh
  Snapshot (the ceremony overlay opens first; the snapshot rebuilds the panel behind it).

Client → server:
- `RequestSetSetting(key: string, value: boolean)` — `key` must be `"music"` or `"sfx"`, `value`
  a boolean; anything else is dropped silently. Same token-bucket rate limit as every remote.
  The state write is `DataService.SetSetting(player, key, value): boolean` (false when state
  isn't loaded); the remote handler is wired in **`Main.server.luau`** (AMENDED post-wave:
  DataService cannot require EconomyService without a cycle), which calls `SetSetting` then
  `EconomyService.MarkDirty(player, { settings = true })`.

Amendments to existing payloads (**AMENDED**, additive):
- `Types.Delta` gains `settings: { music: boolean, sfx: boolean }?`; `EconomyService.DirtyFields`
  gains `settings: boolean?` and `flushDeltas` includes the whole settings table when dirty.
- `ActionResult` unchanged; the client now branches on `reason` (see client contracts).

## Server runtime contracts (M3)

- **VIP skin resolution** (`PlotService.spawnBuilding`): template lookup order is
  `ServerStorage/Assets/<EraName>_VIP/<modelName>` when `state.passes.VIP == true`, then
  `ServerStorage/Assets/<EraName>/<modelName>`, then the placeholder part. Only `Model`
  instances count as templates. `passes.VIP` is never set until M4; the branch must simply
  exist and be exercised by the fallback path. `default.project.json` adds
  `ServerStorage/Assets/<Era>_VIP` folders for all four eras (same `$className: Folder`).
- **Plot sign** (`PlotService`): each plot gets `Workspace/Plots/Plot_<i>/Sign` — an anchored
  part at the plot's front-edge center (geometry derived from the layout's `plotSize`/`padSize`;
  formula in code, numbers from the layout) with a BillboardGui: line 1 `<DisplayName>'s
  <era displayName>`, line 2 `Rebirth ×<n>` only when `rebirthCount > 0` (spec §3 cosmetic
  rank). Text set on claim and refreshed on era advance/rebirth; gold text when `passes.VIP`
  (M4 flips it), neutral otherwise. Cleared (empty text) on release. This is the rebirth
  cosmetic rank visual; name tags are M4 with the VIP tag.
- **Format** (`src/shared/Format.luau`, additive):
  - `Format.Cash(n)` unchanged.
  - `Format.Rate(n: number): string` — for per-second values: `n < 10` ⇒ up to 2 decimals
    (`0.35`, `2.5`, `7`), `10 ≤ n < 1000` ⇒ up to 1 decimal (`12.5`, `340`), else
    `Format.Cash(n)`. Trailing zeros stripped; floors, never rounds up. UI appends `/s` itself.
  - `Format.Duration(seconds: number): string` — `3h 12m`, `12m 5s`, `45s`; negative/zero ⇒
    `0s`. (Replaces the client's local `humanizeDuration`.)
- Bulk restore (`rebuildPlotForEra`, `ClaimPlot`) stays silent: no `FxEvent`s.
- `Catalog.GetSoundsConfig()` added (see above). `Catalog` remains usable from both realms.

## Client contracts (M3) — ui-engineer

World naming the client relies on (frozen since M1, restated): the local player's plot index
is the `PlotIndex` player attribute; buildings live at
`Workspace/Plots/Plot_<i>/Buildings/Building_<slotId>` (a `Model` cloned from Assets, pivoted
to the anchor, or a placeholder `Part`). The client may modify its **local** copies freely
(scale, transparency, attachments) — nothing replicates back.

Controller wiring (Main.client order unchanged: UIController, SoundController,
PlotVisualsController; `Init` all, then `Start` all):
- `SoundController.Init()` builds the three SoundGroups and pre-creates one `Sound` per
  non-zero id **synchronously, without yielding**. Public API:
  `SoundController.Play(key: string, opts: { milestones: number? }?)` (unknown key or id 0 ⇒
  no-op), `SoundController.ApplySettings(settings: { music: boolean, sfx: boolean })`,
  `SoundController.SetAmbientEra(eraName: string?)` (nil stops). Other controllers `require`
  it directly (`script.Parent.SoundController`); calling `Play` before `Init` is a harmless no-op.
- `PlotVisualsController` connects to `FxEvent` and handles `reveal` and `levelUp`; it ignores
  other kinds. `UIController` also connects to `FxEvent` and handles `eraAdvance` and `rebirth`
  only. (Two listeners on one RemoteEvent, disjoint kinds — no cross-controller bus needed.)
- Reveal: locate `Building_<slotId>` under the local plot (`WaitForChild` with a short timeout;
  give up silently if absent). `Model` ⇒ `ScaleTo` from a small start scale to 1 with a
  Back-out tween; `Part` ⇒ tween `Size` from small to the current size keeping the bottom face
  fixed. Play `purchase` then `reveal`. Reduce-motion ⇒ shorter linear tween, no particles.
- Level-up: floating text at the building (`+N` levels, or `MILESTONE` styling when
  `milestone`), brief highlight, `levelUp` sound with `opts.milestones` = number of
  milestoneLevels ≤ `toLevel` (for pitch), `levelUpMilestone` sound additionally when
  `milestone`. Particles only when not reduce-motion.
- Reduce-motion: `Theme.reducedMotion` stays the single source; it is
  `UserInputService.TouchEnabled` OR a low-end signal (your judgment, documented in the report).

HUD (all copy through `Format`; era copy through `displayName`):
- **Top bar**: cash (`Format.Cash`), income (`Format.Rate(ips) .. "/s"`), era badge
  (`ERA n` + displayName), Legacy count. Sub-1/s incomes must never render `0/s`.
- **Bottom bar** (spec §10): four ≥ 44 px targets — `Build`, `Legacy`, `Shop`, `Settings`.
  `Shop` is built but **hidden** this milestone (`SetShopVisible(false)`; M4 shows it when any
  Monetization id is non-zero — spec §6 says items with id 0 are hidden, and an empty shop is
  the same thing). Every button press plays `uiClick`.
- **Build panel**: rows as in M1/M2 plus, on levelable rows, three buttons `×1 / ×10 / Max`
  sending `RequestLevelUp(slotId, 1 | 10 | gameConfig.maxLevel)`. Cost labels: ×1 =
  `LevelUpCost`, ×10 = `LevelUpCostTotal(level, min(level+10, maxLevel))`, Max = total cost of
  the largest affordable `n` (greedy over `LevelUpCost`, display prediction only — the server
  computes the real grant). Income-delta preview per button via shared `Economy`. "Next
  affordable" highlight = the cheapest affordable action (buy or ×1 level) in purchase order.
  Row buttons with cost > cash are dimmed but still tappable (server answers with
  `insufficientFunds`).
- **Legacy panel**: legacy count, current multiplier (`Economy.LegacyMult`), rebirth count,
  and the Advance Era / Rebirth entry when eligible (same eligibility rules as M2; the Build
  panel banner stays too). Legacy shop is Phase 2 — one dim line "Legacy perks: coming later"
  is acceptable, nothing more.
- **Settings panel**: `Music` and `SFX` toggles bound to `state.settings`. Toggling applies
  locally at once (`SoundController.ApplySettings`) and fires `RequestSetSetting(key, value)`;
  the next snapshot/delta is authoritative and re-applies. No other settings this milestone.
- **Era-advance screen** (replaces the M2 minimal dialog for `advance`; `rebirth` uses the same
  screen with rebirth copy): next era displayName + `ERA n+1`, a preview list (first three
  building names and the monument name of the next era config), resets-vs-persists columns,
  `+X Legacy` (client preview via `Economy.LegacyGain`), explicit `Confirm` + `Cancel`. Scrim
  blocks input only while this screen is open.
- **Ceremony** on `FxEvent.eraAdvance`/`rebirth`: full-screen overlay, `ERA n — <displayName>`
  (rebirth: `REBIRTH ×n` then `ERA 1 — <displayName>`), `+X Legacy`, `eraAdvance`/`rebirth`
  sound, auto-dismiss after a Theme-defined duration or on tap; reduce-motion shortens it.
  `SoundController.SetAmbientEra(newEraName)` after the overlay.
- **Welcome-back card** (replaces the M2 toast): non-blocking card under the top bar, title
  `Welcome back!`, body `You earned $<Format.Cash> while away (<Format.Duration>)`, dismiss
  `X`, auto-dismiss after a Theme duration, `welcomeBack` sound. Reserve (hidden) a secondary
  button slot via `SetDoubleOffer(nil | { label, onTap })` for M4's "Double it".
- **Feedback on `ActionResult`**: `insufficientFunds` ⇒ row flash + `insufficientFunds` sound;
  `locked`/`invalid` ⇒ row flash only; era actions ⇒ toast as in M2.
- **Layout**: one uniform `UIScale` model as today, plus `UIAspectRatioConstraint` on the
  fixed-aspect cards (era-advance screen, ceremony title block, welcome-back card). **Real
  landscape layout**: when viewport width > height, the Build/Legacy/Settings panels dock to a
  side column (full available height, fixed design width) instead of the portrait bottom
  sheet, and the bottom bar stays bottom-center. Verify mentally at 375×667, 667×375, and
  1920×1080 and say so in the report. All tap targets ≥ 44 px at `MIN_SCALE`.
- `Toast` stays for transient errors; `ConfirmDialog` stays for anything not covered above.

## tools/gen_asset_manifest.py (economy-designer)

- `py tools/gen_asset_manifest.py` reads `src/shared/Config/Eras/*.json` and writes
  `docs/ASSET_MANIFEST.md`: a header explaining the naming rule
  (`ServerStorage/Assets/<name>/<modelName>` must equal the config `modelName`; VIP variants in
  `Assets/<name>_VIP/`), then one section per era (`## Era n — <displayName>`, sorted by
  eraIndex, listing the era's kits) with a table in purchase order: `#`, `modelName`, slot
  `name`, `type`, `kit`, `description`, and a checkbox column for the human to tick as imported.
  A closing "Totals" line gives model count per era. Output is deterministic (stable ordering,
  no timestamps) so `--check` can diff it.
- `--check`: exits non-zero and prints one line per problem when any era lacks `displayName`,
  any slot lacks `kit`/`description`/`modelName`, a `modelName` is not PascalCase or is
  duplicated within an era, or the committed `docs/ASSET_MANIFEST.md` differs from the
  regenerated text. QA runs `--check`.
- The script is stdlib-only, mirrors the sim's config-loading path (repo-root relative), and
  never duplicates a game constant.

## Definition of done (M3)

`stylua --check src`, `selene src`, `luau-lsp analyze` (committed definitions), `rojo build`
all green; `py tools/sim_economy.py --check` still passes untouched (no balance edits);
`py tools/gen_asset_manifest.py --check` passes with the manifest committed. With every sound
id 0 and no assets imported, Studio shows: reveal tween + placeholder on buy, floating level-up
text (milestone variant at 10), ×1/×10/Max, bottom bar with Build/Legacy/Settings (Shop hidden),
settings toggles that survive rejoin, the welcome-back card, the era-advance screen and the
ceremony overlay, the plot sign, and a usable layout in portrait, landscape, and 1920×1080.
Reviewer verdict SHIP.
