# INTERFACES — frozen contracts

Updated by the lead at the start of each milestone. Agents conform to this document exactly.
If your task needs a change to a file or contract you don't own, **report it in your final
message** — never edit across an ownership boundary.

Current milestone: **M5 — Hardening** (data-load safe mode, leave/shutdown edge cases,
session-lock contention UX, rate-limit audit, confirmed receipt saves, persisted `DoubleOffline`
reservation, `--rebirth`/`--laps` in the sim, second balance pass, full-codebase audit). M1–M4
contracts below remain standing — read the M4 "Post-review amendments" as the current contract,
not history — and the **M5 contracts** section at the end defines this milestone's additions.

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

---

# M4 contracts — Monetization & analytics

Goal: passes, dev products, Premium, and analytics — all optional, all restrained (spec §6).
**With every id in `Monetization.json` left at `0` the game must show no monetization anywhere
and error nowhere.** Nothing here changes balance, persistence keys, or the M1–M3 payload
shapes; everything is additive unless marked **AMENDED**.

## M4 ownership

| Owner | Files |
|-------|-------|
| luau-engineer | `src/server/**` (incl. new `Services/AnalyticsService.luau`), `src/shared/{Types,Economy,Catalog}.luau` |
| ui-engineer | `src/client/**` (new `src/client/UI/ShopPanel.luau` allowed) |
| economy-designer | `src/shared/Config/Monetization.json` (new), `tools/sim_economy.py`, `docs/BALANCE.md` |
| docs-keeper (after QA) | `docs/PLAYTEST.md`, `docs/MANUAL_STEPS.md`, `README.md`, status ticks in `docs/PLAN.md` |

`src/shared/Layouts/**`, `src/shared/Config/{Game,Sounds}.json`, `src/shared/Config/Eras/**`
and `src/shared/Format.luau` are **frozen** this milestone — no balance, era, layout or audio
edits, and `Format.Cash`/`Rate`/`Duration` already cover every M4 label.
`default.project.json` is frozen.

Constant homes are unchanged: gameplay/monetization numbers in `Config/*.json`, client-only
sizing/timing in `src/client/UI/Theme.luau`, tool-only bands in the sim source.

## Monetization.json schema v1 (economy-designer authors; everyone consumes)

`src/shared/Config/Monetization.json`. Arrays, not maps, so shop display order is data.

```json
{
	"version": 1,
	"multipliers": { "doubleCash": 2.0, "vip": 1.1, "premium": 1.1 },
	"packCapFractionOfEraSlotCost": 0.25,
	"receiptHistoryLimit": 200,
	"passes": [
		{
			"key": "DoubleCash",
			"id": 0,
			"name": "Double Cash",
			"description": "Doubles all income, forever."
		},
		{ "key": "OfflinePro", "id": 0, "name": "Offline Pro", "description": "..." },
		{ "key": "VIP", "id": 0, "name": "VIP", "description": "..." }
	],
	"products": [
		{
			"key": "Cash30m",
			"id": 0,
			"name": "30 Minutes of Cash",
			"description": "Instantly earn 30 minutes of your current income.",
			"minutes": 30,
			"capFraction": 0.10,
			"shopVisible": true
		},
		{ "key": "Cash2h", "id": 0, "name": "…", "description": "…", "minutes": 120, "capFraction": 0.25, "shopVisible": true },
		{ "key": "Cash8h", "id": 0, "name": "…", "description": "…", "minutes": 480, "capFraction": 0.50, "shopVisible": true },
		{
			"key": "DoubleOffline",
			"id": 0,
			"name": "Double it",
			"description": "Doubles the cash you just earned while away.",
			"shopVisible": false
		}
	]
}
```

Frozen semantics:

- **Pass keys** are exactly `DoubleCash`, `OfflinePro`, `VIP`; **product keys** exactly
  `Cash30m`, `Cash2h`, `Cash8h`, `DoubleOffline`. They are persistence keys (`state.passes`)
  and analytics SKUs — never rename. Keys are unique across both tables, so a single
  `RequestPrompt(key)` namespace resolves passes first, then products.
- `id`: the Roblox game-pass / developer-product id. **`0` means "not created yet": the item is
  hidden in every UI, `RequestPrompt` for it is dropped, and no Marketplace call is ever made.**
- `minutes`: cash packs only; `DoubleOffline` has no `minutes` (its grant comes from the
  session's recorded offline grant). `shopVisible: false` keeps `DoubleOffline` out of the Shop
  list — it is only ever offered on the welcome-back card (spec §6 rule 3: one contextual offer).
- `capFraction` (**AMENDED mid-wave**, see "Per-pack caps" below): cash packs only; the pack's
  own anti-skip ceiling as a fraction of the era's total slot cost. Absent ⇒ fall back to
  `packCapFractionOfEraSlotCost`.
- `multipliers`: the whole paid stack. `doubleCash × vip × premium = 2.42` — economy-designer
  verifies and records the ≤ ~2.4× check (spec §6 rule 5) in `docs/BALANCE.md`.
- `packCapFractionOfEraSlotCost`: the anti-skip cap, see "Pack grant" below.
- `receiptHistoryLimit`: max `PurchaseId`s kept in `state.processedReceipts` (FIFO trim).

Types (luau-engineer):

```lua
export type PassKey = "DoubleCash" | "OfflinePro" | "VIP"
export type ProductKey = "Cash30m" | "Cash2h" | "Cash8h" | "DoubleOffline"
export type PassDef = { key: string, id: number, name: string, description: string }
export type ProductDef = {
	key: string,
	id: number,
	name: string,
	description: string,
	minutes: number?,
	capFraction: number?,
	shopVisible: boolean,
}
export type MonetizationMultipliers = { doubleCash: number, vip: number, premium: number }
export type MonetizationConfig = {
	version: number,
	multipliers: MonetizationMultipliers,
	packCapFractionOfEraSlotCost: number,
	receiptHistoryLimit: number,
	passes: { PassDef },
	products: { ProductDef },
}
```

`Catalog.GetMonetizationConfig(): Types.MonetizationConfig` (cached, same pattern as
`GetGameConfig`), plus `Catalog.GetPassDef(key: string): Types.PassDef?` and
`Catalog.GetProductDef(key: string): Types.ProductDef?`. Usable from both realms — the client
reads ids itself, so **no remote publishes the monetization config**.

## Economy.luau additions (pure; the sim mirrors them)

```lua
Economy.EraSlotCostTotal(eraConfig): number
	-- sum of baseCost over every slot in the era (owned or not)
Economy.PackGrant(minutes, incomePerSecond, eraSlotCostTotal, capFraction): number
	-- math.min(minutes * 60 * incomePerSecond, capFraction * eraSlotCostTotal); never < 0
Economy.PassMult(passes: { [string]: boolean }, monetizationConfig): number
	-- (DoubleCash and doubleCash or 1) * (VIP and vip or 1)
Economy.PremiumMult(isPremium: boolean, monetizationConfig): number
	-- isPremium and premium or 1
```

**Pack grant (spec §6 rule 6 + the BALANCE.md M2 flag).** Packs stay priced in minutes of the
player's *current* income, computed server-side at purchase time, and are additionally capped
at `packCapFractionOfEraSlotCost` × the current era's total slot cost. Lead ruling: the cap is
against the era's **total** slot cost, not its *remaining* cost — remaining-cost degrades to a
near-zero grant for a player who is nearly done with an era, i.e. Robux for nothing. A flat
era-relative ceiling makes "a pack can never skip an era" literally true (one purchase buys at
most 25% of an era) while always granting something meaningful. This replaces the BALANCE.md
alternative of hiding the big packs before Era 3 — packs stay visible at every era and the cap
does the work.

Because a capped pack grants less than its name implies, **every UI that offers a pack must
show the real predicted grant** (`Format.Cash(Economy.PackGrant(...))`) next to the label, and
the label copy must read as "up to N minutes". The client's preview uses the same pure function
against the snapshot's `incomePerSecond`; the server's computation at receipt time is
authoritative and may differ (income changed meanwhile) — expected, not an error.

The `incomePerSecond` the server passes to `PackGrant` is the **persisted-rate** flavour (no
Studio debug multiplier, neighbors pinned to 1) so a Studio playtest cannot inflate a purchase.

**Per-pack caps (AMENDED mid-wave — lead ruling on the economy-designer's `--packs` finding).**
A single global cap makes all three packs converge: past roughly the first 10–20% of every era
every pack delivers the *identical* capped amount, so a player paying the `Cash8h` price
receives exactly what `Cash30m` buys. That is a fair-value defect, not a balance nit, and spec
§6 ("Robux buys convenience", "fair monetization") does not permit it. The cap therefore
becomes per-product:

- `capFraction` on each cash pack: `Cash30m` 0.10, `Cash2h` 0.25, `Cash8h` 0.50.
- `Monetization.packCapFractionOfEraSlotCost` stays as the **default** for any pack that omits
  `capFraction` (and is the value the sim and docs cite as the family default).
- Every caller of `Economy.PackGrant` — the server at receipt time and the client's shop
  preview — passes `def.capFraction or cfg.packCapFractionOfEraSlotCost`. `Economy.PackGrant`
  itself is unchanged: it already takes `capFraction` as an argument.

Rule 6 still holds literally: the largest single purchase possible is half an era's slot cost,
so no one pack skips an era. The packs are now genuinely differentiated (1 : 2.5 : 5) while
each stays honestly described by its "up to N minutes" copy.

## Multipliers go live (EconomyService) — **AMENDED**

`Types.Multipliers` keeps its shape. `pass` and `premium` stop being hardcoded `1`:

- `mults.pass = Economy.PassMult(state.passes, monetizationConfig)`
- `mults.premium = Economy.PremiumMult(player.MembershipType == Enum.MembershipType.Premium,
  monetizationConfig)`

Both apply to the live rate, the reported rate, **and** the persisted rate
(`computePersistedIncomePerSecond`) — passes and Premium are account properties, not session
state, so offline earnings carry them. Neighbors stays pinned to 1 in the persisted rate as
before. A pass with id `0`, or a pass the player doesn't own, contributes exactly `1`.

`computePersistedIncomePerSecond` therefore needs the `Player`, not just the state: change its
signature (and `RefreshPersistedRate`'s internals) accordingly — every caller already has the
player in hand.

## Offline Pro (EconomyService.ApplyOfflineGrant) — **AMENDED**

Select cap and efficiency by pass, from the Game.json keys that already exist:

```lua
local pro = state.passes.OfflinePro == true
local cap = if pro then offline.capSecondsOfflinePro else offline.capSeconds
local efficiency = if pro then offline.efficiencyOfflinePro else offline.efficiency
```

The Studio diagnostic print stays (it is what makes the grant checkable in a playtest); extend
it with the cap/efficiency actually used. The grant is still never multiplied by the Studio
debug income multiplier.

**Offline grant record (for `DoubleOffline`).** `ApplyOfflineGrant` records
`{ amount = granted, used = false }` per player for the whole session (not just until the first
snapshot — the welcome-back card can be tapped a moment later). New API:

```lua
EconomyService.ReserveDoubleOfflineGrant(player): number? -- claims the offer for one dialog
EconomyService.ReleaseDoubleOfflineGrant(player): ()      -- returns an unsold reservation
EconomyService.ConsumeDoubleOfflineGrant(player): number  -- settles it, returns the amount (0 if none)
```

(**AMENDED**, see post-review amendment 3: the original `GetDoubleOfflineOffer` read allowed two
chargeable dialogs for one grant and has been removed — reserving *is* the check, and a
read-only accessor with no caller is dead code under the project rules.)

Single use per session; `Cleanup` clears it. `RequestPrompt("DoubleOffline")` is dropped when
`ReserveDoubleOfflineGrant` returns nil, so a receipt for it can only exist when a grant is
pending. If a receipt nonetheless arrives with nothing recorded (only reachable via a Roblox
retry after the player rejoined), grant `0`, `warn` with the player and PurchaseId, and still
return `PurchaseGranted` — the alternative is an infinite retry loop.

## MonetizationService (luau-engineer) — the whole service is new

Every `MarketplaceService` call is wrapped in `pcall` with retry + logging (spec §11); a
failure never errors a player's session.

**Pass ownership.** On join, called from `Main`'s orchestration after `LoadAsync` and **before**
`ApplyOfflineGrant` (so the offline grant already reflects Offline Pro):
`MonetizationService.RefreshPassesAsync(player)` — for each pass with a non-zero id, one
`UserOwnsGamePassAsync` behind pcall+retry; write the result into `state.passes[key]`. Cached
for the session: never re-queried per tick. **On API failure keep the persisted value** (never
downgrade `true → false` on an error); on success write the API's answer verbatim, including
`false` (refunds/revokes must take effect).

`PromptGamePassPurchaseFinished` applies a pass immediately: set `state.passes[key] = true`,
then `EconomyService.RefreshPersistedRate(player)`, `EconomyService.MarkDirty(player,
{ income = true })`, `PlotService.RefreshCosmetics(player)` (VIP only, but calling it always is
harmless), then the `passGranted` `FxEvent`. Roblox may also deliver the same pass state via
the next session's join refresh — both paths must be idempotent.

**ProcessReceipt** (`MarketplaceService.ProcessReceipt`, assigned exactly once, in `Init`):

1. Resolve `receiptInfo.ProductId` to a product key via `Monetization.json`. Unknown id ⇒
   `warn` + `Enum.ProductPurchaseDecision.NotProcessedYet` (a product created on the Creator
   Hub before its id is pasted into the config must not be silently eaten).
2. `local state = DataService.GetState(player)` — `nil` (player absent, or data not loaded yet)
   ⇒ `NotProcessedYet`.
3. `local id = tostring(receiptInfo.PurchaseId)`; if `id` is already in
   `state.processedReceipts` ⇒ `PurchaseGranted` immediately (idempotency; no second grant).
4. Grant (below), then append `id` to `state.processedReceipts` and FIFO-trim to
   `receiptHistoryLimit`, then `DataService.SaveAsync(player)`. **Return `PurchaseGranted` only
   if the save succeeded**; otherwise `NotProcessedYet` so Roblox retries. The grant and the
   receipt id land in the same profile write, so a retry after a failed save finds the id
   absent and re-grants against a profile that never persisted the first grant — consistent
   either way.
5. Any error inside the handler ⇒ caught, logged, `NotProcessedYet`.

Grants:
- `Cash30m` / `Cash2h` / `Cash8h`: `granted = Economy.PackGrant(def.minutes, persistedIps,
  Economy.EraSlotCostTotal(eraConfig), def.capFraction or cfg.packCapFractionOfEraSlotCost)`; then
  `state.cash += granted`, `state.stats.totalCashAllTime += granted`, `MarkDirty { cash = true }`.
- `DoubleOffline`: `granted = EconomyService.ConsumeDoubleOfflineGrant(player)`; same cash
  bookkeeping.
- Every grant fires the `purchase` `FxEvent` and one analytics source event (below).

**VIP name tag** (the M3 carry-over): a `BillboardGui` named `VipTag` on the character's
`Head`, text `VIP` in the plot sign's gold, created on `CharacterAdded` when `state.passes.VIP`
is true and on the `passGranted` path for an already-spawned character; removed if VIP is ever
false. Sizing constants live in code beside it (a server-side world cosmetic, not client
`Theme`) — mirror the existing plot-sign constants block.

`MonetizationService` keeps `Init()`/`Start()` and stays in the slot it already occupies in the
frozen boot order. `AnalyticsService` is a **new** service and goes **last** in the ordered list
in `Main.server.luau` (it depends on nothing, and nothing depends on its `Start`).

## RequestPrompt (RemoteService validator + MonetizationService handler)

`RequestPrompt(key: string)` — shape unchanged from M1's reservation.

- Validator: `args.n == 1 and typeof(args[1]) == "string"`. Standard token bucket.
- Handler: resolve `key` in passes, then products. Drop silently when the key is unknown, when
  the resolved `id == 0`, when the player has no loaded state, when it is a pass the player
  already owns, or when it is `DoubleOffline` with no pending offer.
- Otherwise `MarketplaceService:PromptGamePassPurchase(player, id)` /
  `:PromptProductPurchase(player, id)` inside a pcall.
- **The server never prompts on its own initiative** (spec §6 rule 2): a prompt exists only as
  a direct response to this remote.

## FxEvent — M4 additions (additive to the M3 union)

```lua
export type FxPurchase = { kind: "purchase", productKey: string, grantedCash: number }
export type FxPassGranted = { kind: "passGranted", passKey: string }
export type FxEvent = FxReveal | FxLevelUp | FxEraAdvance | FxRebirth | FxPurchase | FxPassGranted
```

Owner only, fired after the state mutation. `UIController` handles both new kinds (toast +
`purchase` sound); `PlotVisualsController` keeps ignoring everything but `reveal`/`levelUp`.
No new sound keys — `Sounds.json` is frozen; reuse the existing `purchase` key.

## DataService addition

```lua
DataService.SaveAsync(player): boolean   -- explicit profile save (pcall + retry + warn); false on failure
```

`state.processedReceipts` is already in schema v1 — no migration and no schema bump this
milestone. Trimming the list is the receipt handler's job, not DataService's.

## PlotService addition

```lua
PlotService.RefreshCosmetics(player): ()
```

Re-runs the plot-sign refresh and re-spawns the owned buildings through the existing VIP-aware
template lookup, **silently** (bulk-restore rules: no `FxEvent`s, no tweens, no sounds). No-op
when the player holds no plot. Called on the pass-grant path only.

## Analytics taxonomy (frozen here; luau-engineer implements, economy-designer documents)

New `src/server/Services/AnalyticsService.luau`, a thin wrapper over Roblox's
`AnalyticsService`. Rules:

- **Every call inside `pcall`.** If the service or an enum is unavailable the wrapper degrades
  to a no-op — analytics must never break a purchase or a build. Verify exact signatures
  against `tools/types/globalTypes.d.luau`; do not guess and find out at runtime.
- Balances passed to Roblox are integers (`math.floor(state.cash)`); currency names are exactly
  `"cash"` and `"legacy"`.
- **Income ticks are never logged** (1 Hz per player would swamp the quota). A `RequestLevelUp`
  granting `n` levels logs **one** event, not `n`.

| Event | Flow | Currency | Transaction type | itemSku |
|-------|------|----------|------------------|---------|
| slot bought | Sink | cash | `Shop` | `slot:<eraName>:<slotId>` |
| level-up (per action) | Sink | cash | `Shop` | `level:<eraName>:<slotId>` |
| offline grant | Source | cash | `TimedReward` | `offline` |
| product grant | Source | cash | `IAP` | `product:<productKey>` |
| legacy on advance/rebirth | Source | legacy | `Gameplay` | `era:<eraIndex>` |

Progression: one `LogProgressionEvent` per era advance and per rebirth (category
`"EraProgression"`, the completed era index as the level). If that API is not available in this
engine version, log nothing and say so in the report — do not invent a substitute.

`AnalyticsService` public API (called by PlotService / EconomyService / MonetizationService):

```lua
AnalyticsService.LogCashSink(player, amount, endingBalance, itemSku): ()
AnalyticsService.LogCashSource(player, amount, endingBalance, transactionType, itemSku): ()
AnalyticsService.LogLegacySource(player, amount, endingBalance, itemSku): ()
AnalyticsService.LogEraProgression(player, eraIndex, isRebirth): ()
```

## Client contracts (M4) — ui-engineer

**Everything monetization-facing is driven by `Catalog.GetMonetizationConfig()` ids.** With all
ids `0` the client must look exactly like it does at the end of M3.

- **Shop button**: `bottomBar.SetShopVisible(anyNonZeroId)`, where `anyNonZeroId` is true iff
  any pass or product in the config has `id ~= 0`. Evaluated once at boot (the config is static).
- **`ShopPanel`** (new; docks like the other panels in both orientations): sections `Passes`
  then `Packs`, in config array order, skipping any item with `id == 0` and any product with
  `shopVisible == false`. Each row: name, description, and for packs the predicted grant
  (`Economy.PackGrant` against the current snapshot `incomePerSecond`, re-rendered as income
  changes) with "up to N minutes" copy. Owned passes render as an `Owned` state and are not
  tappable. Tapping fires `RequestPrompt(key)` and nothing else — no client-side optimism, no
  local grant, no blocking spinner. If every item filters out, the panel shows the same dim
  "nothing here yet" line pattern the Legacy panel uses (and the Shop button is hidden anyway).
- **Welcome-back "Double it"**: when the snapshot carries `welcomeBack` **and** the
  `DoubleOffline` product id is non-zero, call `SetDoubleOffer({ label = "Double it",
  onTap = ... RequestPrompt("DoubleOffline") })`; otherwise pass `nil`. Tapping fires the prompt
  and closes the offer (the card itself may stay); the resulting cash arrives as a normal delta.
  Never auto-open anything.
- **`passGranted` / `purchase` FxEvents**: a brief toast (`+$X` for `purchase`, `<Pass> active`
  for `passGranted`) and the `purchase` sound. Authoritative state arrives in the snapshot/delta.
- **Indicators**: a compact multiplier readout — VIP badge when `state.passes.VIP`, `Premium`
  when `Players.LocalPlayer.MembershipType == Enum.MembershipType.Premium`, and the neighbors
  bonus (`Economy.NeighborsMult(#Players:GetPlayers(), gameConfig)`, spec §4: shown so players
  understand why friends help). Top bar or Legacy panel — your judgment; keep the top bar
  uncluttered at 375×667 and say what you chose in the report.

**M3 carry-overs assigned to ui-engineer this milestone** (from PLAN.md's M3 list):

1. Landscape viewports narrower than ~690 px (e.g. 640×360): the right-docked panel overlaps
   the top-left top bar by ~9 px. Clamp the panel width (preferred) or document the accepted
   overlap.
2. Toggling a setting before the first snapshot arrives doesn't call
   `SoundController.ApplySettings` immediately — apply locally on toggle whether or not state
   has loaded.
3. Hoist inline insets into `Theme`: `Panel.luau` header `+2` / `-16`, and `BuildPanel.luau`
   `ScrollBarThickness 4` and the empty-label height `40`.

## tools/sim_economy.py (economy-designer)

- Mirror `Economy.EraSlotCostTotal`, `PackGrant`, `PassMult`, `PremiumMult` function-for-function
  and read the new `Monetization.json` from the repo root (never duplicate a constant).
- The **default run and `--check` behaviour must not change** — no passes, no Premium, so every
  number in the existing BALANCE.md table stays byte-identical. QA re-runs `--check` to prove it.
- Add `--passes doublecash,vip` / `--premium` flags that switch the multipliers on, so the paid
  stack's effect on pacing is measurable, plus a small `--packs` report: per era and per pack,
  the uncapped minute-value, the cap, and the delivered grant at a mid-era income — the evidence
  for the §6 rule-6 claim in BALANCE.md.

## docs/BALANCE.md additions (economy-designer)

- The paid multiplier stack table and the ≤ ~2.4× verification (spec §6 rule 5).
- The pack-cap section: replace the M2 "Cash packs (M4 heads-up)" recommendation with what was
  actually decided (era-total cap, packs visible at every era), including the `--packs` table.
- The analytics taxonomy table above, restated for the human who will read the dashboards.
- How much faster a fully-paid player finishes each era (from the `--passes`/`--premium` run),
  so the "convenience, never progress gates" claim is backed by a number.

## Post-review amendments (M4 wave 2 — lead rulings on the reviewer's findings)

These are frozen additions made after the first implementation wave. They override anything
above that conflicts.

**1. The join critical section may not yield (Critical).** `MonetizationService.RefreshPassesAsync`
introduced a yield between `LoadAsync` returning and `ApplyOfflineGrant`, and the 1 Hz
`grantIncome` loop restamps `state.lastSeen`/`incomeAtSave` for every loaded profile — so a tick
landing inside that window zeroes `elapsed` and silently destroys the player's entire offline
grant, welcome-back card and `DoubleOffline` offer. Invisible in the all-ids-0 default, ~10–30%
per join once a real pass id exists.

Fix (chosen): **gate the income tick on join completion.** `EconomyService` gets a per-player
`joinComplete` flag, set at the end of `ApplyOfflineGrant` and cleared in `Cleanup`;
`grantIncome` skips (`continue`) any player not yet marked. This also stops income accruing
into a plot the player has not been given yet, which was always latent. The passes-before-
offline-grant ordering in the join orchestration is unchanged and still required.

**2. A failed receipt save must not leave a grantable mutation in memory (Major, money).**
`grantProduct` mutates `state.cash` before `SaveAsync`. When `SaveAsync` fails while the session
is still active, ProfileStore's autosave can still persist the cash, but the `PurchaseId` never
lands — so Roblox's retry grants a second time. On a `false` from `SaveAsync`, **roll the
in-memory mutation back** (`cash`, `stats.totalCashAllTime`, and un-consume the `DoubleOffline`
record) before returning `NotProcessedYet`. Correct the "consistent either way" comment: it is
only true once the rollback exists.

**3. `DoubleOffline` is consumed at prompt time, not receipt time (Major, money).** The current
drop condition lets a modified client open two dialogs; completing both charges Robux twice and
grants once. `EconomyService` gains `ReserveDoubleOfflineGrant(player): number?` — marks the
record reserved and returns the amount, or nil when there is no unreserved offer.
`RequestPrompt("DoubleOffline")` reserves before prompting and **releases the reservation** if
the prompt is declined (`PromptProductPurchaseFinished` with `isPurchased == false`) or the
prompt call itself fails. `ConsumeDoubleOfflineGrant` then settles a reserved record.

**4. The shop preview must use the persisted rate (Major, fair value).** `ShopPanel` previews
against the snapshot's `incomePerSecond`, which is the *reported* rate (Studio debug multiplier
applied, neighbors up to ×1.27), while the server prices packs off `state.incomeAtSave`. In a
full server the shop advertises up to **+27% more cash than the player receives**, every time —
a permanent one-directional overstatement on a real-money item, which is the same class of
defect as the converging caps. The contract's sanctioned divergence covers incidental drift
("income changed meanwhile"), not a systematic bias.

Fix: the server publishes the persisted rate explicitly. `Types.Snapshot` and `Types.Delta` gain
`persistedIncomePerSecond: number` (Snapshot: always present; Delta: present whenever the
`income` dirty flag flushes, alongside `incomePerSecond`). `ShopPanel` previews against it and
never reconstructs it client-side. This keeps the three-rate discipline (live / reported /
persisted) explicit on both realms.

**5. `RequestPrompt` gets its own rate-limit bucket (Minor, exploit).** A prompt is a modal OS
dialog, not a gameplay action; the shared 10/s budget lets a modified client make the game
unusable and hammer `MarketplaceService`. `Game.json` is **unfrozen for exactly one key**:
`remotes.promptCallsPerSecond` (schema v1.4, value `1`), added by the lead. `Types.RemotesConfig`
gains `promptCallsPerSecond: number`, and `RemoteService` uses it for `RequestPrompt`'s bucket
instead of `callsPerSecond`. Every other remote is unchanged.

**6. Smaller rulings.**
- `Catalog`'s missing-file monetization fallback must use the schema default
  `receiptHistoryLimit = 200`, never `0` — a `0` would trim the idempotency log to empty.
- `BottomBar.SetShopVisible` excludes products with `shopVisible == false` from the
  "any non-zero id" test, so a lone `DoubleOffline` id cannot show a Shop button that opens an
  empty panel. (Reviewer was right that the literal contract said otherwise; this is better.)
- The client suppresses the purchase toast when `grantedCash <= 0`.
- Shop row descriptions size to their content (`AutomaticSize`) rather than a fixed 4-line box:
  the shipped copy is 137–139 chars against a ~140-char budget, and the copy is owned by an
  agent with no visibility of the client's layout constants.
- `DataService.SaveAsync`'s guarantee — ProfileStore's `Save()` is non-yielding, so `true` means
  "accepted into an active session", not "durably written" — is accepted as the strongest
  guarantee available, but it is a **documented** residual risk: docs-keeper records it in
  `MANUAL_STEPS.md` and it becomes an M5 hardening item. Nothing else may read the boolean as
  durability.

**7. The published persisted rate must be computed live, not read from `state.incomeAtSave`
(playtest fix, 2026-09-09).** Amendment 4 said the server publishes `state.incomeAtSave`. That
was wrong: `incomeAtSave` is a *persistence* field, restamped only by the 1 Hz income tick,
while the delta's `incomePerSecond` beside it is computed fresh at flush time. The consequences
in Studio were that every shop pack previewed the rate from before the player's last purchase,
and read **$0 for an entire era after an advance** — the advance restamps `incomeAtSave`
against the new era's empty slots, and nothing marks income dirty when the tick recomputes it,
so the client kept the zero until a second purchase happened to flush a delta.

`EconomyService.GetPersistedIncomePerSecond(player): number` is now the single source: the
snapshot, the delta, and `MonetizationService`'s receipt pricing all call it, so the row cannot
advertise one amount and the grant deliver another. `state.incomeAtSave` keeps its original and
only job — the rate persisted for the offline grant.

**8. A pack row states which limit produced its number (playtest fix, 2026-09-09).** The
contract said pack copy reads "up to N minutes". Once the cap binds that label is false by
orders of magnitude — at Era 2 with 55M/s the 30-minute pack advertised "Up to 30m" while
granting 0.4% of that, because the cap ($1.28B) is far below 30 minutes of income ($99B). And
the cap binds for nearly the whole of every era: about 4:28 into Era 2's 1h44m, per BALANCE.md's
cap-onset table. So for ~96% of an era the minutes on the label were decorative.

`ShopPanel` now names whichever of the two limits is smaller — `30m of income — $4.5M` while
minutes bind, `10% of this era — $1.2B` once the cap does. The grant itself is unchanged; only
the description of it is. Per-pack `capFraction` values and the anti-skip guarantee stand.

## Definition of done (M4)

`stylua --check src`, `selene src`, `luau-lsp analyze` (committed definitions +
`--sourcemap sourcemap.json`), `rojo build -o build/test.rbxl` all green;
`py tools/sim_economy.py --check` passes with the M2 numbers unchanged;
`py tools/gen_asset_manifest.py --check` passes. With every id `0`: no Shop button, no Double
it, no prompts, no warnings, and the M3 playtest still passes unchanged. With ids set: the Shop
lists exactly the created items, a test purchase grants the capped amount once and only once
(replayed receipts are no-ops), a pass applies within the session (income, VIP sign, VIP skins,
VIP name tag), Offline Pro widens the offline cap and efficiency, and Premium shows and
multiplies. Reviewer verdict SHIP.

---

# M5 contracts — Hardening

Goal (spec §12 M5, PLAN M5 + the M4 "Carried forward" block): the MVP definition of done holds
end-to-end under failure. Nothing here changes gameplay numbers except the designer's balance
pass; every server change is about what happens when DataStores, sessions, or players misbehave.

## M5 ownership

| Owner | Files |
|-------|-------|
| luau-engineer | `src/server/**`, `src/shared/{Types,Economy,Catalog}.luau` |
| ui-engineer | `src/client/**` (new `src/client/UI/LoadScreen.luau` allowed) |
| economy-designer | `tools/sim_economy.py`, `docs/BALANCE.md`, `src/shared/Config/Eras/**` (unfrozen for the balance pass only) |
| lead | `docs/INTERFACES.md`, `src/shared/Config/Game.json` (v1.5 — already applied: `remotes.snapshotCallsPerSecond = 2`; any further key an agent needs is **reported**, not edited) |
| docs-keeper (after QA) | `docs/PLAYTEST.md`, `docs/MANUAL_STEPS.md`, `README.md`, status ticks in `docs/PLAN.md`, regenerated `docs/ASSET_MANIFEST.md` |

Frozen this milestone: `src/shared/Layouts/**`, `Config/{Sounds,Monetization}.json`,
`src/shared/Format.luau`, `default.project.json`, `wally.toml`. `Economy.luau` may not change
shape (the sim mirrors it); the balance pass is config-only. If the designer needs a `Game.json`
balance key changed (`levelIncomeBonus`, `levelCost.*`, `legacy.*`), report the exact key and
value and the lead applies it.

Infrastructure retry policy (attempt counts, backoffs, confirmation timeouts, retry cooldowns)
stays **in code** beside the call it governs, per the ruling already recorded in
`DataService.luau` — `Config/*.json` is for gameplay constants. The one new config key is a
rate limit, which has always lived in `Game.json`.

## Game.json v1.5 (lead, applied)

`remotes.snapshotCallsPerSecond: 2` — `RequestSnapshot` gets its own bucket: each call answers
with a full state snapshot (the most expensive reply the server makes), so it must not share the
10/s gameplay budget. `Types.RemotesConfig` gains `snapshotCallsPerSecond: number`;
`RemoteService.bucketCallsPerSecond` returns it for `RequestSnapshot`.

## Types.luau — M5 additions (luau-engineer authors; the client consumes by name)

```lua
-- Sent on StateChanged while a player has no loaded state. The client boots blank otherwise.
export type LoadStatus = {
	kind: "loadStatus",
	phase: "loading" | "failed",
	attempt: number,          -- 1-based count of load attempts this session (retries included)
	retryAvailableIn: number, -- seconds until RequestRetryLoad is honored; 0 = now. Always 0 while loading.
}
-- StateChanged payload union is now Snapshot | Delta | LoadStatus.

export type PlayerState = { ... , pendingDoubleOfflineAmount: number, ... } -- schema v2, see below
export type RemotesConfig = { ..., snapshotCallsPerSecond: number, ... }
```

## Profile schema v2 (luau-engineer)

`PROFILE_TEMPLATE` gains `pendingDoubleOfflineAmount = 0` and `SCHEMA_VERSION` becomes `2`.
`Migrations[1]` sets `state.pendingDoubleOfflineAmount = 0` when the field is `nil`. This is the
first real migration and deliberately exercises the M2 mechanism; ProfileStore's `Reconcile`
would also fill the field, but the version stamp must advance so a v1 profile is provably
upgraded once, not reconciled forever. Migrations remain additive and idempotent.

`0` means "no reservation". Nothing else in the schema changes.

## Data-load safe mode (replaces the M2 "kick on load failure" rule)

**Ruling.** A player whose profile cannot be loaded is no longer kicked. They stay in the server
with **no state, no plot, and no writes**, see a clear explanation, and can retry or leave.
Session-lock contention (the common cause — a previous server still holds the session; ProfileStore
waits and steals after 40 s) therefore resolves itself while the player watches a loading card
instead of a kick screen. The kick from `OnSessionEnd` (another server took the session while this
one held it) is unchanged: that player is playing elsewhere.

"No writes" is structural, not a flag: without a profile there is nothing to save. The existing
nil-tolerance of every `GetState` call site is what makes safe mode free — the audit below
verifies it path by path.

**DataService.** Owns the per-player load status and publishes it; Main only orchestrates.

```lua
DataService.LoadAsync(player): Types.PlayerState?      -- unchanged signature
DataService.RetryLoadAsync(player): Types.PlayerState? -- honors the cooldown; nil without an attempt when refused
DataService.IsLoading(player): boolean
DataService.GetLoadStatus(player): Types.LoadStatus?   -- nil once state is loaded (or the player never joined)
DataService.SaveAsync(player, confirm: ((saved: Types.PlayerState) -> boolean)?): boolean -- see receipts
```

- Every attempt (first load or retry) publishes `{ phase = "loading", attempt = n,
  retryAvailableIn = 0 }` on `StateChanged` before it yields. A nil result with the player still
  present publishes `{ phase = "failed", attempt = n, retryAvailableIn = LOAD_RETRY_COOLDOWN_SECONDS }`.
  Publishing goes through `RemoteService.FireClient(player, "StateChanged", status)` (no cycle:
  RemoteService requires only Catalog). Success publishes nothing — the join snapshot follows.
- `RetryLoadAsync` returns nil **without** publishing or attempting when: state is already
  loaded, a load is in flight, or fewer than `LOAD_RETRY_COOLDOWN_SECONDS` (`10`, code constant
  beside `LOAD_RETRY_ATTEMPTS`) have passed since the last failure. Otherwise it is `LoadAsync`
  with the attempt counter continued.
- `RequestSnapshot` with no loaded state replies with `GetLoadStatus(player)` when non-nil (the
  client's boot request may land before, during, or after the first attempt — every ordering
  must end with the client seeing either a status or a snapshot). Nothing is sent when it is nil.
- **The duplicate-load busy-wait is gone** (M2 carry-over). Concurrent `LoadAsync` callers for
  the same player park on a per-player completion signal (a waiter list resumed with
  `task.spawn`, or the Wally `Signal` package — engineer's choice) and receive the same result the
  in-flight load produced. No `while … task.wait()` polling anywhere in DataService after this
  milestone.

**RemoteService.** New client → server remote `RequestRetryLoad()` (no args; validator
`args.n == 0`; standard `callsPerSecond` bucket for shape — the real throttle is DataService's
cooldown). Added to `REMOTE_NAMES`; the client `WaitForChild`s it like the others.

**Main.** The join sequence becomes a named function `runJoinSequence(player, loader)` used by
both `PlayerAdded` (with `LoadAsync`) and the `RequestRetryLoad` handler (with
`RetryLoadAsync`): load → left-during-yield guard → `RefreshPassesAsync` → guard →
`ApplyOfflineGrant` → `ClaimPlot` → `SendSnapshot`. On a nil load Main does **nothing** (no kick;
DataService already published the status). The `RequestRetryLoad` handler drops silently when
`GetState` is non-nil or `IsLoading` is true — `RetryLoadAsync` re-checks anyway.

## Leave-mid-purchase and shutdown (luau-engineer: audit, fix, and report)

Required behaviour per path — the engineer verifies each against the code, fixes what fails,
and lists the verdict per row in the final report (the reviewer re-checks the same table):

| Path | Required behaviour |
|------|--------------------|
| `RequestBuy` / pad `Touched` / `RequestLevelUp` / ProximityPrompt / `RequestAdvanceEra` / `RequestRebirth` | No yield between validation and mutation; a call landing after `PlayerRemoving` teardown sees `GetState == nil` and drops. |
| `ProcessReceipt` while the player leaves | Grant + receipt id are appended before `SaveAsync`; if the session ends during the confirmation wait, `SaveAsync` returns false → rollback → `NotProcessedYet`. Whether or not ProfileStore's final save captured the grant, the persisted `cash` and `processedReceipts` are always consistent with each other, so the next-session retry is exactly-once. Engineer confirms this reasoning holds for the confirmed-save implementation below, and that a `ProcessReceipt` arriving with no player/state returns `NotProcessedYet` without touching anything. |
| `PromptGamePassPurchaseFinished` / `PromptProductPurchaseFinished` after leave | No-op when state is nil or the player is gone; no error, no orphaned reservation (the pending amount is persisted — see below). |
| `RequestPrompt("DoubleOffline")` then leave with the dialog open | Reservation persists (`pendingDoubleOfflineAmount`); a later-session receipt grants it. |
| Server shutdown | `Main` registers `game:BindToClose` running the `PlayerRemoving` teardown (`PlotService.Release` → `EconomyService.Cleanup` → `DataService.Release`) for every player that still has a profile, idempotently with the `PlayerRemoving` connection (both may run; `Release` on a released profile is a no-op). ProfileStore's own `BindToClose` (registered at require time) blocks shutdown until its final saves land — Main's callback must not busy-wait for that. Skipped when `RunService:IsStudio()` **only** if ProfileStore is in mock mode; otherwise it runs in Studio too. |
| Income tick during teardown/shutdown | `Cleanup` clears `joinComplete`, so no grant lands on a released profile. Engineer confirms `grantIncome` cannot observe a profile between `DataService.Release` and `Cleanup` in either call order. |

## Confirmed receipt saves (resolves the M4 accepted risk)

**Ruling: a stronger guarantee is worth the latency.** ProfileStore exposes
`Profile.OnAfterSave(last_saved_data)`, fired after each write actually lands, so the receipt path
can wait for durability instead of trusting the non-yielding `Save()`. The cost is one DataStore
round-trip (typically well under 2 s) before `PurchaseGranted`, on a path where Roblox already
tolerates a yielding handler. The M4 caveat in `MANUAL_STEPS.md` M4 §8 item 14 is retired by
docs-keeper once this ships.

`DataService.SaveAsync(player, confirm?)`:
- Without `confirm`: unchanged (accepted-into-session semantics; no remaining caller relies on it
  as durability, and the engineer removes any that does).
- With `confirm`: connect `profile.OnAfterSave` **before** calling `profile:Save()`; park the
  calling thread (no polling) until an `OnAfterSave` fires whose `last_saved_data` satisfies
  `confirm`, or `SAVE_CONFIRM_TIMEOUT_SECONDS` (`10`, code constant) elapses, or the session ends.
  Return `true` only on a satisfying fire; disconnect in every exit. An earlier-started autosave
  landing after the call does not satisfy `confirm` unless it actually contains the mutation —
  that is why the predicate exists.
- Retry policy: `LOAD_RETRY_ATTEMPTS` re-issues `Save()` on a thrown call as today; a timeout is
  **not** retried (the write may still be queued) — return false and let Roblox retry the receipt.

`MonetizationService.ProcessReceipt` step 4 becomes: `DataService.SaveAsync(player, function(saved)
return table.find(saved.processedReceipts, id) ~= nil end)`. Rollback on `false` is unchanged
(amendment 2) and remains correct in every interleaving: memory and the persisted profile agree
on whether the id is present, and the id is only ever written together with the cash.

Engineer must confirm from `ProfileStore.luau` that mock-mode saves (Studio without API access)
also fire `OnAfterSave`; if they do not, `SaveAsync` treats a mock profile's `Save()` as confirmed
so Studio test purchases still complete, and says so in the report.

## Persisted `DoubleOffline` reservation (resolves the M4 open edge)

`EconomyService`:
- `ReserveDoubleOfflineGrant` also writes `state.pendingDoubleOfflineAmount = amount`.
- `ReleaseDoubleOfflineGrant` clears it to `0`.
- `ConsumeDoubleOfflineGrant` settles, in order: the session record if reserved; else the persisted
  `pendingDoubleOfflineAmount` when `> 0` (a receipt from an earlier session's dialog); else `0`
  with the existing `warn`. Every settle path writes `pendingDoubleOfflineAmount = 0`. Rollback
  (amendment 2) restores whichever source it consumed.
- `ApplyOfflineGrant` never touches the pending field: a new session's offer only replaces the
  persisted amount when it is itself reserved.

The remaining theoretical double (an old receipt and a new reservation both settling in one
session) grants the reserved amount once and `0` for the other with a warn; docs-keeper records
that as the residual, replacing `MANUAL_STEPS.md` M4 §8 item 15.

## Rate-limit audit (luau-engineer implements the table; reviewer confirms it)

| Intent path | Budget |
|-------------|--------|
| `RequestSnapshot` | `remotes.snapshotCallsPerSecond` (2/s) — new bucket |
| `RequestBuy`, `RequestLevelUp`, `RequestAdvanceEra`, `RequestRebirth`, `RequestSetSetting`, `RequestRetryLoad` | `remotes.callsPerSecond` (10/s) |
| `RequestPrompt` | `remotes.promptCallsPerSecond` (1/s) |
| Pad `Touched` | `padTouchDebounce` **and** the `RequestBuy` bucket via `TryConsumeToken` |
| ProximityPrompt level-up | the `RequestLevelUp` bucket via `TryConsumeToken` |
| `ProcessReceipt`, `PromptGamePassPurchaseFinished`, `PromptProductPurchaseFinished` | Roblox-originated, no bucket; must be nil-tolerant for absent state/player |

Plus: `RemoteService.Init` warns and clamps any configured rate below `1` (a fractional refill
rate starts every bucket empty, silently disabling the remote); `RequestSetSetting` handled in
Main keeps the shared bucket; the `Touched`/ProximityPrompt rows are verified, not assumed —
report the line numbers.

## Client contracts (M5) — ui-engineer

**`LoadScreen`** (new `src/client/UI/LoadScreen.luau`, wired in `UIController`): a centered card
over a light dim, shown from boot until the first `Snapshot` arrives, driven by `LoadStatus`.
It never blocks movement or the camera (the player may walk the hub and look at other plots —
spec §5). All sizing/timing constants in `Theme`.
- Before any payload: "Loading your city…" (so a slow first status still isn't a blank HUD).
- `phase == "loading"`: same copy; after `Theme.LOAD_SLOW_SECONDS` (8) on screen, a second
  line: "Still working — another server may be finishing your last save."
- `phase == "failed"`: title "We couldn't load your save", body "Nothing you do now will be
  saved. Try again in a moment, or rejoin.", buttons **Retry** (fires `RequestRetryLoad`;
  disabled with a live countdown until `retryAvailableIn` has elapsed since the payload
  arrived, then enabled; on tap, shows "Retrying…" until the next status/snapshot) and **Leave**
  (`Players.LocalPlayer:Kick("Rejoin to load your save.")` — allowed on the local player).
  Tap targets ≥ 44 px; verified at 375×667 portrait and 667×375 landscape.
- Hidden permanently on the first `Snapshot` (`Hide()`; later `LoadStatus` payloads are ignored
  once a model exists — none should arrive).
- While no model exists: bottom bar and Shop button hidden, top bar shows nothing misleading (no
  "$0 / 0/s" on a failed load — blank or dashes). Existing "delta before snapshot" handling stays.
- `onStateChanged` dispatches `kind == "loadStatus"` to the screen; unknown kinds stay ignored.
- Reuse `Panel`/`ConfirmDialog` primitives where they fit; no new sound keys (`Sounds.json` is
  frozen) — Retry uses the existing UI click.

**Feedback audit.** Every player-initiated action has a visible success or failure response.
Produce the table (action → success feedback → failure feedback → file:line) in the final report
and fix any gap found. Known-acceptable: `RequestPrompt` drops that the client can never trigger
(id 0, already owned, no offer) need no feedback because the client hides those controls; a
declined OS purchase dialog is its own feedback.

**Reduce-motion verification.** List every tween/particle/animation call site and the
`Motion`/reduce-motion check that gates it; fix any unguarded one. Report the list.

## tools/sim_economy.py — M5 additions (economy-designer)

- `--rebirth N` (default 0): the starting `rebirthCount` for the run, applied to `LegacyGain`
  exactly as `Economy.luau` does (the M2 carry-over: the sim hardcoded 0).
- `--laps K` (default 1): simulate K consecutive laps of eras 1..4, rebirthing between laps with
  `legacy` and `rebirthCount` carried, printing the per-era table for every lap. Lap 1 output with
  defaults must be byte-identical to today's, so `--check` keeps its meaning.
- `--check` semantics unchanged (lap 1 in band). If the balance pass moves any era config, the
  new numbers become the `--check` baseline and BALANCE.md says what moved and why.

**Second balance pass (config-only):** targets are spec §4's bands for lap 1; for lap 2 the
designer decides and documents a target (recommendation: lap 2 should be noticeably faster but
not degenerate — no era under half its lap-1 band floor), and checks the fully-paid stack still
reads as convenience (BALANCE.md "Paid vs. free pacing"). Any `Game.json` key change is reported,
not applied. Final `docs/BALANCE.md` carries every table the spec §4 simulation requirement asks
for, the lap-2 table, and the unchanged 1 : 2.2 : 4.2 pricing-ladder note for Ben.

## Definition of done (M5)

`stylua --check src`, `selene src`, `luau-lsp analyze` (committed definitions +
`--sourcemap sourcemap.json`, regenerated because `LoadScreen.luau` is new), `rojo build -o
build/test.rbxl` all green; `py tools/sim_economy.py --check` passes; `py tools/gen_asset_manifest.py
--check` passes. Full-codebase reviewer audit (not a diff review) returns SHIP. In Studio: a
forced load failure shows the card, Retry recovers without a rejoin, the player is never kicked
for a load failure; a test purchase completes with a visible confirmation delay and grants once;
shutdown (Stop in Studio with API access on) persists the last tick's state; the M0–M4 playtests
still pass, re-swept by docs-keeper's final PLAYTEST section against spec §12's definition of done.

## Post-review amendments (M5)

**1. Reviewer Warnings, fixed.** `DataService`'s `OnSessionEnd` handler skips the "loaded on
another server" kick while `ProfileStore.IsClosing` is true (ProfileStore's own `BindToClose` ends
sessions before Main's flush runs), and Main's flush runs the teardown for every player
unconditionally. `ReserveDoubleOfflineGrant` stashes the prior persisted amount on the record and
`ReleaseDoubleOfflineGrant` restores it instead of writing `0`, so a declined second dialog cannot
zero an earlier session's paid reservation; `Release` no longer resets `used`; a reservation is
queued to the DataStore immediately via the unconfirmed `SaveAsync`.

**2. Studio lever for the load-failure playtest (lead).** A real load failure cannot be forced
from Studio — ProfileStore retries throttled DataStore calls internally and never surfaces them —
so `DataService.attemptLoad` returns nil immediately (with a warn) when `RunService:IsStudio()`
and the Workspace boolean attribute `ForceLoadFailure` is true. Read on every attempt, so it can
be toggled live from the Properties pane to exercise failed → Retry → recovered without a rejoin.
Ignored outside Studio; not a config key because it is a live toggle, not a constant.
