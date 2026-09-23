# INTERFACES — frozen contracts

Updated by the lead at the start of each milestone. Agents conform to this document exactly.
If your task needs a change to a file or contract you don't own, **report it in your final
message** — never edit across an ownership boundary.

Current milestone: **M6 — Legacy shop** (see the "M6 contracts" section at the end; M5 below is shipped and playtested). M5 was: (data-load safe mode, leave/shutdown edge cases,
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

---

# M6 contracts — Legacy shop (Phase 2)

Source design: `docs/LEGACY_SHOP.md` (Ben approved Model C "invest + softcap", softcap 1000,
Level Floor tier 2 = 8, Long Memory sells cap hours only, the seven perks and five cosmetics as
tabled there). This section turns that document into frozen contracts; where the two disagree,
this section wins.

## M6 ownership

| Owner | Files |
|-------|-------|
| luau-engineer | `src/server/**`, `src/shared/{Types,Economy,Catalog}.luau` |
| ui-engineer | `src/client/**`, `sourcemap.json` (regenerate if a module is added) |
| economy-designer | `src/shared/Config/LegacyShop.json` (new), `tools/sim_economy.py`, `docs/BALANCE.md`, `docs/LEGACY_SHOP.md` (mark as adopted) |
| lead | `docs/INTERFACES.md`, `docs/PLAN.md`, `src/shared/Config/Game.json` (v1.6 — applied: `legacy.softcap = 1000`) |
| docs-keeper (after QA) | `docs/PLAYTEST.md`, `docs/MANUAL_STEPS.md`, `README.md`, status ticks in `docs/PLAN.md` |

Frozen: `Config/Eras/**`, `Layouts/**`, `Config/{Sounds,Monetization}.json`, `Format.luau`,
`default.project.json`, `wally.toml`. Every other constant in this milestone lives in
`LegacyShop.json` or `Game.json`; client-only sizing/copy timing in `Theme`.

## Game.json v1.6 (lead, applied)

`legacy.softcap: 1000`. `Types.LegacyConfig` gains `softcap: number?` (optional so an older
Game.json still typechecks and behaves linearly).

## LegacyShop.json v1 (economy-designer authors; everyone consumes via Catalog)

```json
{
  "version": 1,
  "perks": [
    {
      "id": "founders", "name": "Founder's Blessing", "cosmetic": false,
      "description": "Your legacy inspires everyone: +5% income per tier.",
      "effect": "incomeMult",
      "tiers": [ { "cost": 80, "value": 1.05 }, ... ]
    },
    ...
  ]
}
```

- `effect` is a closed enum: `"incomeMult" | "levelCostDiscount" | "startingSlots" | "levelFloor"
  | "extraMilestone" | "neighbours" | "offlineCapSeconds" | "cosmetic"`. Every tier of a perk
  shares it. `value` is the **total** effect once that tier is owned (never per-tier). The
  `neighbours` tier additionally carries `maxBonus`. Cosmetic perks have `cosmetic: true`,
  `effect: "cosmetic"`, exactly one tier, `value: 0`, and may carry cosmetic-specific fields:
  `signTitle.titles: { string }` (indexed by `min(rebirthCount + 1, #titles)`),
  `nameTagColour.color: "#RRGGBB"`, `goldenRoads.color: "#RRGGBB"`. `monumentGlow` and
  `advanceFireworks` carry nothing extra.
- Perk ids (frozen, persistence keys): `founders`, `builders`, `inheritance`, `levelFloor`,
  `milestone75`, `neighbours`, `longMemory`, `signTitle`, `nameTagColour`, `monumentGlow`,
  `advanceFireworks`, `goldenRoads`. Array order is display order. Tier costs and values are the
  LEGACY_SHOP.md §2/§3 numbers (Level Floor 5 / 8).
- Tiers are bought in order: the server accepts only `ownedTier + 1`. A perk present in a profile
  but absent from the config is ignored, never an error. `Catalog.GetLegacyShopConfig()` returns
  the module, or `{ version = 1, perks = {} }` when the file is missing (the shop then hides).

## Types.luau — M6 additions

```lua
export type PerkEffect = "incomeMult" | "levelCostDiscount" | "startingSlots" | "levelFloor"
	| "extraMilestone" | "neighbours" | "offlineCapSeconds" | "cosmetic"
export type PerkTier = { cost: number, value: number, maxBonus: number? }
export type PerkDef = {
	id: string, name: string, description: string, cosmetic: boolean, effect: PerkEffect,
	tiers: { PerkTier }, titles: { string }?, color: string?,
}
export type LegacyShopConfig = { version: number, perks: { PerkDef } }
export type LegacyShopState = { spent: number, perks: { [string]: number } } -- perkId -> tier owned

-- PlayerState (schema v3, additive): legacyShop: LegacyShopState
-- Multipliers gains perk: number (Founder's Blessing; 1 when none)
-- LegacyConfig gains softcap: number?
-- Delta gains legacyShop: LegacyShopState?  (present whenever the legacyShop dirty flag flushes)
-- EconomyService.DirtyFields gains legacyShop: boolean?
-- ActionResult.action gains "buyPerk"; slotId carries the perkId; reasons reuse
--   insufficientFunds (Legacy balance) | locked (not the next tier / no such perk) | invalid
```

## Profile schema v3 (luau-engineer)

Template gains `legacyShop = { spent = 0, perks = {} }`; `SCHEMA_VERSION = 3`; `Migrations[2]`
fills the field when nil. Additive and idempotent, same rules as v2.

## Economy.luau — exact signatures (luau-engineer implements; the sim mirrors 1:1)

All pure. Existing functions keep their current parameters and gain trailing optionals so every
current caller and the sim's lap-1 output stay byte-identical when the new arguments are absent.

```lua
Economy.LegacyMult(legacy: number, game: GameConfig): number
	-- softcap: s = game.legacy.softcap; eff = if s and legacy > s then s + s*math.log(legacy/s) else legacy
Economy.IncomePerSecond(slots, era, game, mults)   -- mults.perk multiplied in beside mults.legacy
Economy.LevelUpCost(baseCost, level, game, discount: number?)        -- cost * (1 - (discount or 0))
Economy.LevelUpCostTotal(baseCost, fromLevel, count, game, discount: number?)
Economy.SlotIncome(baseIncome, level, game, milestoneLevels: { number }?)  -- overrides game.milestoneLevels
Economy.NeighborsMult(playerCount, game, perPlayer: number?, maxBonus: number?)

-- New helpers (all take the shop config so both realms and the sim read one source):
Economy.PerkTier(shopState: LegacyShopState?, perkId: string): number        -- 0 when unowned/nil
Economy.PerkValue(shop: LegacyShopConfig, shopState, perkId): number?        -- tier's value, nil when unowned
Economy.PerkIncomeMult(shop, shopState): number                              -- founders value or 1
Economy.LevelCostDiscount(shop, shopState): number                           -- builders value or 0
Economy.LevelFloor(shop, shopState): number                                  -- levelFloor value or 1
Economy.MilestoneLevels(shop, shopState, game): { number }                   -- game list + 75 when owned, sorted
Economy.NeighborsParams(shop, shopState, game): (number, number)             -- perPlayer, maxBonus
Economy.OfflineCapSeconds(passes, shopState, shop, game): number             -- pass cap + longMemory value
Economy.InheritanceCash(eraConfig, shop, shopState): number                  -- sum baseCost of first N slots (array order); 0 when unowned
Economy.LegacySpendable(state: PlayerState): number                          -- legacy - legacyShop.spent
Economy.NextPerkTier(shop, shopState, perkId): (PerkTier?, number)           -- next tier def + its index, nil when maxed/unknown
```

`OfflineGrant`, `LegacyGain`, `PackGrant`, `PassMult`, `PremiumMult` are unchanged. The discount
is applied in `LevelUpCost` ONLY — never at a call site — so the Build panel preview and the
server charge cannot disagree. Level Floor levels count toward `LegacyGain` (LEGACY_SHOP.md §8).

## Server behaviour (luau-engineer)

- **`RequestBuyPerk(perkId: string)`** — new remote, validator `args.n == 1 and typeof(args[1]) == "string"`, shared `callsPerSecond` bucket. Handler chain: state loaded → perk exists in config → next tier exists (else `locked`) → `LegacySpendable >= cost` (else `insufficientFunds`) → `legacyShop.perks[id] = tier`, `legacyShop.spent += cost` → `RefreshPersistedRate` → `MarkDirty { income = true, legacyShop = true }` → `PlotService.RefreshCosmetics(player)` (cosmetics and `goldenRoads`/`monumentGlow` take effect at once) → `FxEvent { kind = "perkBought", perkId, tier }` → analytics Sink (`legacy`, `Shop`, `perk:<id>:<tier>`). Failure ⇒ `ActionResult { action = "buyPerk", slotId = perkId, ok = false, reason }`. No Robux anywhere near this path.
- **Founder's**: `mults.perk = Economy.PerkIncomeMult(...)` in the live, reported and persisted rates.
- **Master Builders**: `tryLevelUp` passes `Economy.LevelCostDiscount(...)` into `LevelUpCostTotal`.
- **Inheritance**: on successful `tryAdvanceEra` and `tryRebirth`, after the reset, `state.cash += Economy.InheritanceCash(newEra, ...)`; counts toward `totalCashAllTime`; analytics Source (`Gameplay`, `inheritance`). Cash only — slots are still bought in order.
- **Level Floor**: `tryBuy` creates `building`-type slots at `level = Economy.LevelFloor(...)`; unlock/decor/monument stay at 1. The reveal `FxEvent` is unchanged (no levelUp event for the floor).
- **Extra Milestone**: every `SlotIncome` call and the `FxLevelUp.milestone` flag use `Economy.MilestoneLevels(...)` for that player.
- **Good Neighbours**: `NeighborsMult` receives `Economy.NeighborsParams(...)` of the plot owner.
- **Long Memory**: `ApplyOfflineGrant` uses `Economy.OfflineCapSeconds(...)`; efficiency logic unchanged; the Studio diagnostic print includes the cap used.
- **Cosmetics** (all server-side world cosmetics in `PlotService`, applied on spawn, `ClaimPlot`, `RefreshCosmetics`, silently): `signTitle` adds a third sign line with the title indexed by rebirth count; `nameTagColour` recolours the player's name — implement as a `BillboardGui` beside the VIP tag pattern (`MonetizationService` owns the VIP tag; put this one in `PlotService` and name it `TitleTag`; when both exist they stack vertically); `monumentGlow` = a `PointLight` plus `Material = Neon`-style highlight on the monument building/placeholder; `goldenRoads` = colour override on `unlock`-type buildings/placeholders (never on VIP skin models — placeholder or base-colour parts only); `advanceFireworks` = a server-side `ParticleEmitter` burst at the monument on advance/rebirth, ~2 s, `Enabled` toggled with `task.delay`, visible to everyone. Missing perk ⇒ nothing spawned; never an error.
- **Studio lever**: in Studio only, a numeric Workspace attribute `GrantLegacy` > 0 is consumed by the 1 Hz tick: every loaded player's `legacy += value`, `RefreshPersistedRate`, `MarkDirty { income = true }` plus a fresh snapshot (legacy is a snapshot field), then the attribute is reset to 0 with a `warn`. Same pattern as `ForceLoadFailure`.
- `FxEvent` union gains `FxPerkBought = { kind: "perkBought", perkId: string, tier: number }`.

## Client contracts (M6) — ui-engineer

- **Legacy panel becomes the shop.** Header: `Legacy <total>` and `Spendable <legacy − spent>`, a multiplier breakdown row `Legacy ×a · Perks ×b · Passes ×c` (values from `Economy.LegacyMult`, `PerkIncomeMult`, `PassMult × PremiumMult`), and a one-line softcap note ("Legacy grows slower past 1,000" — from `Game.json`, formatted). Then one row per perk in config order: name, description, `Tier n/N`, the next tier's effect and cost, **Buy** (disabled with the cost in red when unaffordable; "Maxed" when complete). Cosmetics section below with the same row shape. Long Memory copy must say "+2 h on your offline cap", never a total. Tap targets ≥ 44 px, portrait and landscape.
- **Build panel** uses `Economy.LevelUpCost/Total` with `Economy.LevelCostDiscount(...)` and `Economy.MilestoneLevels(...)` for "next milestone" labels — it may never read `Game.milestoneLevels` directly for the owner's plot. Level Floor: a row's post-purchase preview reflects the floor level.
- `StateChanged` delta merges `legacyShop`; `FxEvent.perkBought` ⇒ toast + the existing `purchase` sound (no new sound keys). `ActionResult.buyPerk` failures ⇒ the row flashes and the `insufficientFunds` sound when that is the reason.
- After the era-advance/rebirth ceremony closes, if `LegacySpendable` can afford any next tier, open the Legacy panel once (not a modal; a panel, dismissable) — spec §6 rule 3 concerns Robux, this is earned currency.
- Client-side cosmetics: none (all world cosmetics are server-side); `PlotVisualsController` may skip the fireworks' local particle load under reduce-motion by setting the emitter's `Enabled = false` on its local copy.
- Welcome-back card: unchanged (the sum is visible via elapsed time).

## tools/sim_economy.py (economy-designer)

Replace the hardcoded `PERK_DEFS` with `Config/LegacyShop.json`; `legacy_mult` gains the softcap
from `Game.json` (mirroring the exact Lua expression); every mirrored helper above exists with the
same name in snake_case. Default output and `--check` stay byte-identical (softcap never binds in
lap 1). `--shop softcap` becomes the default shop model when `--perks auto` is given; drop the
`spend`/`invest` models from the CLI (they were decision tooling; keep the numbers in BALANCE.md).
`docs/BALANCE.md` gains an M6 section: Model C lap 1–6 table from the real config, the purchase
timeline, the paid-stack re-verification, and any deviation from LEGACY_SHOP.md.

## Definition of done (M6)

Standard suite green (`stylua`, `selene`, `luau-lsp analyze` with a regenerated sourcemap if
modules were added, `rojo build`, `sim_economy.py --check`, `gen_asset_manifest.py --check`).
Reviewer SHIP. In Studio with the `GrantLegacy` lever: every perk tier is buyable in order and
only in order, the balance and breakdown row update at once, a second buy of the same tier is
refused, Founder's/Master Builders/Level Floor/Extra Milestone visibly change income, level costs,
new-building levels and milestone labels, Inheritance grants cash on advance, cosmetics appear on
the plot and for a second player, and with the config file absent the Legacy panel shows no shop
and nothing errors.

## Post-wave amendments (M6)

**1. Signatures as shipped (override the printed ones above).** `Economy.IncomePerSecond(slots,
era, game, mults, milestoneLevels: { number }?)` — the trailing list is the only route for Extra
Milestone to reach income, since `SlotIncome` is called inside its loop. `Economy.LevelUpCostTotal`
keeps its existing third parameter `toLevel` (the contract wrote `count`; "existing functions keep
their current parameters" wins). The sim mirrors both.

**2. Buy handler lives in a new `Services/LegacyShopService.luau`**, boot order `DataService →
RemoteService → EconomyService → PlotService → LegacyShopService → MonetizationService →
AnalyticsService`.

**3. Multi-lap sim output without perks changes from lap 2 Era 3 on** (the softcap now lives in
`LegacyMult` itself and lap 2 enters Era 2 above 1000 Legacy). Lap 1, `--check`, packs, rusher and
paid outputs are byte-identical to M5; BALANCE.md's M6 section is the new multi-lap baseline.

---

# M7 contracts — growing buildings: pipeline + Village (2026-09-15)

Read `docs/PLAN.md` "M7" and `docs/SPEC.md` §8 (amended) first; `docs/ASSET_RESEARCH.md` §1–§4 for
the measured facts behind every number here. Scope: the pipeline plus Village's 24 slots.

## M7 ownership

| Owner | Files |
|-------|-------|
| pipeline-engineer (general-purpose) | `tools/assets/**` (new), `tools/testfit/{testfit.py,strip.py,README.md,blueprint.py}`, `templates/**` (generated `.rbxmx`, committed), `src/shared/Config/Assets.json` (generated), `default.project.json` (only the `ServerStorage.Assets` mapping), `.gitignore` (add `assets/build/`) |
| asset-builder A/B/C (general-purpose ×3) | `tools/testfit/blueprints/Village/<ModelName>.json` for their slot set only (table below); read-only on everything else |
| luau-engineer | `src/server/**`, `src/shared/{Types,Catalog}.luau` |
| ui-engineer | `src/client/**`, `sourcemap.json` |
| economy-designer | `tools/gen_asset_manifest.py`, `docs/ASSET_MANIFEST.md` |
| lead | `docs/INTERFACES.md`, `docs/PLAN.md`, the tavern proof, routing |
| docs-keeper (after QA) | `docs/PLAYTEST.md`, `docs/MANUAL_STEPS.md`, `README.md`, PLAN ticks |

Frozen: `Config/Eras/**`, `Layouts/**`, `Config/{Game,Sounds,Monetization,LegacyShop}.json`,
`Economy.luau`, `Format.luau`, `tools/sim_economy.py`, `wally.toml`. No balance change in M7.

## Blueprints (asset-builders author; pipeline-engineer's tools consume)

Path `tools/testfit/blueprints/<EraName>/<ModelName>.json`; the file name **equals** the era
config's `modelName` (PascalCase). The approved prototype is `Village/Tavern.json`.

```json
{
  "id": "Tavern",                 // == modelName == file stem
  "era": "Village",
  "scale": 4.0,                   // studs per kit unit; fixed at 4.0 for every M7 blueprint.
                                  // Exception (Ben, 2026-09-18): at most three OrbitalColony
                                  // landmarks (FusionReactor, TerraformStation, SpaceportTerminal)
                                  // use 3.6 with footprint [12, 12], because space-kit's hex and
                                  // long hangars are 13.1 / 12 studs at 4.0 and fit nothing.
  "footprint": [9, 9],            // optional, studs; default [9, 9]. Monument may use up to [14, 14].
                                  // A non-monument slot may exceed [9, 9] (max [12, 12]) only where
                                  // the kit cannot express the building's subject at 9x9 -- so far
                                  // Metropolis Stadium, which needs a bowl around a readable pitch.
                                  // Also OrbitalColony RoverBay [12, 9] (Ben, 2026-09-22): the
                                  // kit's only garage fills 8 of 9 studs, so the rover yard needs
                                  // the width; depth stays 9 so the buy pad is untouched.
                                  // Clearance is computed from harvested extents, not from this
                                  // number, so a wider slot needs no dressing change; but the buy
                                  // pad sits padOffset studs off the front (-Z), so keep the front
                                  // face within ~4.5 studs of the origin whatever the footprint.
  "pieces": [
    { "kit": "fantasy-town-kit", "model": "wall-door", "pos": [0, 0, 0], "rotY": 0, "stage": 0 }
  ]
}
```

- `pos` in kit units before scaling, Y up; the origin is the slot anchor at ground level; the
  front faces **−Z**. `rotY` degrees about Y. `stage` 0–4 is the first stage the piece appears in;
  stages are additive (a piece never disappears). Buried pieces are fine when no outward face
  lands on a cell boundary (see `tools/testfit/README.md`).
- `building` slots use all five stages: 0 buy, 1 L10, 2 L25, 3 L50, 4 L100, humble → imposing,
  growing **up**. `unlock`, `decor`, `monument` slots put every piece at stage 0.
- Pieces may come from more than one kit, but keep the era's palette: Village = `fantasy-town-kit`,
  `castle-kit`, `nature-kit` only. One kit per building where possible (each kit adds one MeshPart
  per stage, see below). OrbitalColony = `space-kit` plus the generated `orbital-kit`
  (`tools/assets/orbital_kit.py`: domes, solar panels, flag, hologram, tanks, mast, derrick, lit
  window strips — subjects space-kit lacks; Ben, 2026-09-18). Generated kits follow the
  `stadium_kit.py` pattern: the script is committed, the GLBs under `/assets/` regenerate.
- Every blueprint must render clean with `testfit.py` (no footprint warning, no floating or
  clipping piece) and the builder looks at the strip before reporting. Piece budget ≤ 60 at stage 4.

Village slot sets (id → ModelName, type):

| Builder | Slots |
|---|---|
| A — houses and shops | HouseSmallA, HouseSmallB, HouseLargeA, Bakery, Blacksmith, MarketStall, Stables, Chapel (all `building`) |
| B — structures and unlocks | Windmill, Well, Watchtower (`building`); Fountain, RoadCobblestone, CartWagon, WallGate (`unlock`); CastleKeep (`monument`, footprint up to 14×14, must be the plot's most imposing silhouette) |
| C — early slots and nature | Campfire, TentSmall, WoodcutterHut, FarmPlot (`building`, modest growth: more tents, stacked logs, more crops, a fence); FlowerBed, TreeOak, BannerPole (`decor`) |

Slot order in `Config/Eras/1_Village.json` is the price ramp; earlier slots must read humbler than
later ones at the same stage.

## tools/assets — the pipeline (pipeline-engineer)

All Python runs with `py`; Blender is `"/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b -P <script> -- <args>`.
Every tool is idempotent and deterministic (stable ordering, no timestamps in outputs), prints a
one-line summary per item, and never raises on a missing input — it warns and skips.

1. **`tools/testfit/blueprint.py`** — shared loader/validator (schema above), used by `testfit.py`
   and `merge_stages.py`. Rename the prototype to `Tavern.json` (done by lead).
2. **`tools/assets/merge_stages.py`** (Blender) — `--era Village [--model Tavern]`. For each
   blueprint and stage: place pieces (linked data, as testfit does), **join into one mesh per kit**,
   apply scale ×4 with the origin kept at the blueprint origin (bottom-centre of the footprint,
   front −Z), and export `assets/build/stages/<Era>/<ModelName>_S<n>.glb` with one node and one
   material per kit, texture **embedded** (the kit's `colormap.png`). Kits whose GLBs use material
   colours instead of a texture (nature-kit and space-kit do; verify per kit at import: a primitive
   with no `baseColorTexture`) get a deterministic **palette texture** per kit
   (`assets/build/palettes/<kit>.png`, one swatch per distinct base colour across the whole kit,
   generated by `tools/assets/palette.py`) and UVs remapped onto their swatch, so every piece of a
   kit shares one image and one UV convention. Also writes `assets/build/stages/<Era>/<ModelName>.json`
   with per-stage, per-kit bounds in studs (for the manifest and for sanity checks). Non-building
   slots produce only `_S0`.
3. **`tools/assets/upload_models.py`** — `--era Village [--model Tavern] [--dry-run]`. Open Cloud
   Model upload of every stage GLB, reusing `tools/upload_audio.py`'s env/credential/polling code
   (import or copy; `.env` key `ROBLOX_API_KEY` etc. exactly as that tool reads them). Writes
   `modelAssetId` into `Assets.json` (schema below) and skips any stage whose id is already
   non-zero. Also uploads, once per kit, a **VIP swatch**: one small kit piece with the VIP
   recoloured colormap embedded (`tools/assets/vip_palette.py` from the research folder's
   `vip_palette.py` — a warm gold gradient map), as `assets/build/vip/<kit>_swatch.glb`, recorded
   under `textures.<kit>.vipSwatchAssetId`.
4. **`tools/assets/harvest.luau` + `tools/assets/harvest.py`** — the one Studio step. The Luau file
   is pasted into the Studio command bar (Edit mode); it reads the id list embedded at its top
   (regenerated by `harvest.py --emit` from `Assets.json` so it never has to be edited by hand),
   `InsertService:LoadAsset`s each model and swatch, and prints one `[HARVEST] {json}` line per
   asset: for every MeshPart — `kit` (the node name), `meshId`, `imageId` (from `TextureID`),
   `size` (studs) and `offset` (part position relative to the inner model's pivot, which is the
   glTF origin). Then it destroys what it loaded. `py tools/assets/harvest.py` reads the Windows
   clipboard (`powershell Get-Clipboard`) or `--file`, parses only `[HARVEST]` lines, and merges
   them into `Assets.json`. Missing lines leave entries untouched and are listed.
5. **`tools/assets/gen_templates.py`** — `Assets.json` → `templates/<Era>/<ModelName>.rbxmx`
   (Rojo XML model format). Template shape is frozen below. `--check` regenerates to memory and
   diffs, like the manifest tool.
6. **`default.project.json`** — `ServerStorage.Assets` becomes `{"$path": "templates"}` so
   `templates/Village/Tavern.rbxmx` builds to `ServerStorage.Assets.Village.Tavern`.
   `$ignoreUnknownInstances` stays on `ServerStorage` itself only. The `<Era>_VIP` folders are
   removed (VIP is a texture swap now; `findTemplate`'s VIP branch simply finds nothing). Each era
   directory needs at least one file, so `templates/<Era>/.gitkeep`-style placeholders are not
   valid for Rojo — create the four era directories only when they have a template; the server
   already tolerates a missing era folder.

## Assets.json — schema v1 (`src/shared/Config/Assets.json`, generated; Rojo → ModuleScript)

```json
{
  "version": 1,
  "textures": {
    "fantasy-town-kit": { "vipSwatchAssetId": 0, "vipImageId": 0 }
  },
  "eras": {
    "Village": {
      "Tavern": {
        "stages": [
          {
            "modelAssetId": 0,
            "parts": [
              { "kit": "fantasy-town-kit", "meshId": 0, "imageId": 0,
                "size": [8.5, 4.2, 4.0], "offset": [0.0, 2.1, 0.0] }
            ]
          }
        ]
      }
    }
  }
}
```

`stages` has 5 entries for `building` slots and 1 otherwise. `0` means "not yet" everywhere and
never errors. Sizes and offsets are studs. The file is optional at runtime: `Catalog.GetAssetsConfig()`
returns `nil` when the ModuleScript is absent and every consumer treats that as "no assets".

## Template shape (frozen; gen_templates.py writes it, PlotService consumes it)

```
Model "<ModelName>"                      PrimaryPart = Base
  Part "Base"                            Size (1, 0.2, 1), CFrame identity (origin = anchor, ground level),
                                         Transparency 1, Anchored, CanCollide false, CanQuery false, CanTouch false
  Model "Stage0" … "Stage4"              one per stage present in Assets.json
    MeshPart "<kit>"                     MeshId rbxassetid://<meshId>, TextureID rbxassetid://<imageId>,
                                         Size = size, CFrame = CFrame.new(offset), Anchored,
                                         CanCollide true, CollisionFidelity Box, CanTouch false,
                                         Material Plastic, Color (255,255,255)
```

- `PivotTo(anchorCFrame)` on the Model therefore puts the footprint's bottom-centre on the anchor,
  exactly as the placeholder does today.
- `MeshId` is not scriptable at runtime, which is the whole reason templates are files.
- Part budget: a spawned building is `Base` + the MeshParts of one stage (1–2). A full Village plot
  stays ≤ 60 parts from buildings.

## Server behaviour (luau-engineer)

- **`Types.luau`**: `AssetsConfig`, `AssetStage`, `AssetPart` mirroring the schema; `FxEvent`
  gains `{ kind: "stageUp", slotId: string, stage: number }`.
- **`Catalog.GetAssetsConfig(): Types.AssetsConfig?`** — nil-safe like the LegacyShop lookup.
- **Stage rule** (pure helper `PlotService.stageForLevel(level, milestoneLevels)`; base milestones
  from `Game.json.milestoneLevels` only — the Legacy `milestone75` perk affects income, never the
  visual): stage = count of base milestones `<= level`, so L1–9 → 0, 10–24 → 1, 25–49 → 2,
  50–99 → 3, 100 → 4. Non-`building` slots are always stage 0. If `Stage<n>` is missing in the
  template, use the highest present stage `<= n`; if none, the placeholder path.
- **`spawnBuilding`**: clone the template, delete every `Stage*` except the chosen one, pivot,
  parent. The `LevelUpPrompt` must be parented to `Base` (a ProximityPrompt needs a BasePart
  parent; today it is parented to the Model and would be inert on a real template).
- **Milestone crossing** (`tryLevelUp` → `crossesMilestone`): when the stage changes, clone the new
  `Stage<n>` from the template into the live model, destroy the old one, re-apply VIP/cosmetics,
  and fire `FxEvent stageUp` to the owner (in addition to the existing level-up FX).
  `RefreshCosmetics` and rebuilds go through the same path.
- **VIP**: when `state.passes.VIP` is true, for each MeshPart in the visible stage set
  `TextureID = "rbxassetid://" .. textures[kit].vipImageId` if that id is non-zero; otherwise leave
  the normal texture. Losing/gaining VIP mid-session goes through `RefreshCosmetics`.
- **Cosmetics redesign**: Golden Roads tints `unlock` slots' MeshParts with `Color` = the perk
  colour (texture is multiplied, so it reads as gilded); placeholders keep today's behaviour.
  Monument Glow keeps the `PointLight` and replaces Neon with a `Highlight` (FillColor perk colour,
  FillTransparency 0.6, OutlineTransparency 0.2) on the model; never touches `Material`.
- Everything degrades: missing `Assets.json`, missing template, missing stage, id `0` — placeholder
  or plain texture, never an error. Rate limits and validation order unchanged.

## Client contracts (ui-engineer)

- `FxEvent stageUp`: play a growth pop on the building model (`Model:ScaleTo` 0.85 → 1.08 → 1.0
  over ~0.5 s with the existing reveal easing), reuse the milestone particles/flash, and the
  existing `levelUpMilestone` sound (no new sound). No new remotes.
- Build panel: for `building` slots owned below stage 4, the row's hint line reads
  "Grows at Lv <next base milestone>" (client computes from `Game.json.milestoneLevels`); at
  stage 4 nothing extra. Copy lives in `Theme`.
- Nothing else changes; placeholders keep their billboard labels.

## tools/gen_asset_manifest.py (economy-designer)

Becomes a coverage report per era: for every `modelName` — slot type, blueprint present
(`tools/testfit/blueprints/<Era>/<ModelName>.json`), stages defined, stage GLBs built
(`assets/build/...`, may be absent on a fresh clone → "n/a"), uploaded (`Assets.json`
`modelAssetId` non-zero per stage), harvested (`meshId` non-zero), template present
(`templates/<Era>/<ModelName>.rbxmx`). Keeps `--check` and the deterministic-output rule; still
validates the era configs as today. The Kenney-kit suggestion column is dropped (blueprints are
the suggestion now).

## Waves

- **Wave 0 (parallel, disjoint):** pipeline-engineer builds tools 1–6 and runs the **tavern
  proof** through merge → upload → `harvest.py --emit`; asset-builders A/B/C author blueprints;
  luau-engineer implements the server side against the frozen template shape; ui-engineer the
  client; economy-designer the manifest.
- **Ben:** pastes the harvest script, copies Output back, then after `gen_templates.py` +
  `rojo build` confirms in Studio that the Tavern template shows its mesh and texture and grows
  in Play. **No further uploads until this passes.** If a file-defined MeshPart does not load, the
  fallback is building templates at server boot with `InsertService:LoadAsset(modelAssetId)`
  into the same shape (verified loadable in Edit mode on 2026-09-15).
- **Wave 1:** upload + harvest the remaining Village blueprints (one harvest paste), templates,
  manifest, review, QA, docs.

## Definition of done (M7)

Standard suite green (`stylua`, `selene`, `luau-lsp analyze` with a regenerated sourcemap,
`rojo build`, `sim_economy.py --check`, `gen_asset_manifest.py --check`, `gen_templates.py --check`).
Reviewer SHIP. All 24 Village slots have blueprints that render clean, uploaded and harvested
stages, and committed templates. In Studio: buying any Village slot reveals its stage-0 mesh at
the anchor, facing the pad; levelling a `Tavern` with the cash lever to 10 / 25 / 50 / 100 swaps
the stage each time with the pop; a VIP plot shows the gold texture; with `Assets.json` and
`templates/` removed, every slot is a placeholder and nothing errors; a full-stage Village plot has
≤ 60 building parts.

## Post-proof amendment (M7, 2026-09-16)

**Rojo-built `.rbxmx` MeshParts work.** Ben previewed all five Tavern stages from
`ServerStorage.Assets.Village.Tavern` in Edit mode: textured, correct size, sitting on the ground.
The `InsertService` fallback is not needed. Roblox also **deduplicated the texture**: all five stage
uploads returned the same `imageId`, so a kit's texture id is stable across uploads. The
`ServerStorage.Assets` mapping is `{"$path": {"optional": "templates"}}` (Rojo 7.7), which makes
`.gitkeep` placeholders unnecessary. A Studio-only `GrantCash` Workspace attribute (number,
consumed once by the 1 Hz tick like `GrantLegacy`) was added by the lead for the growth playtest.

---

# Amendment — VIP skins toggle (2026-09-16)

Ben asked for a way to switch the VIP building skin off. It is a persisted player setting, not a
Studio lever. The VIP pass keeps every other benefit (income bonus, gold sign text) regardless.

## Contract

- **Setting:** `settings.vipSkins: boolean`, default `true`. `Types.PlayerState.settings` and the
  `settings` delta become `{ music: boolean, sfx: boolean, vipSkins: boolean }`;
  `Types.SettingKey = "music" | "sfx" | "vipSkins"`.
- **Profile schema v4:** `SCHEMA_VERSION` 3 → 4; `Migrations[3]` sets `state.settings.vipSkins =
  true` when nil (additive, idempotent). Template default includes `vipSkins = true`.
- **Remote:** `RequestSetSetting(key, value)` — validator accepts `"vipSkins"`; same boolean check
  and rate limit. `DataService.SetSetting` writes it. In `Main.server.luau`, after a successful
  write of `vipSkins`, call `PlotService.RefreshCosmetics(player)` (silent bulk rebuild — no FX)
  in addition to the existing `MarkDirty(player, { settings = true })`. A write whose value equals
  the current one does not rebuild. **Review fix:** the rebuild runs only for a VIP owner, and
  flips are coalesced — the first change schedules one `RefreshCosmetics` after
  `Game.json remotes.skinRefreshDelaySeconds` (0.75); later flips inside that window share it;
  the pending flag is cleared on PlayerRemoving.
- **Server skin rule:** one helper in PlotService, `usesVipSkins(state) = state.passes.VIP == true
  and state.settings.vipSkins ~= false`, replaces `state.passes.VIP == true` in the three
  skin decisions: `dressStage` (VIP texture swap), `spawnBuilding` (`findTemplate` vipSkins arg),
  `swapStage` (`findTemplate` vipSkins arg). The sign colour keeps reading `passes.VIP`.
- **EconomyService:** the settings delta carries `vipSkins` alongside music/sfx.
- **Client:** SettingsPanel gains a third row `{ key = "vipSkins", label = "VIP building skins" }`,
  visible only while `state.passes.VIP == true` (hidden, not disabled, otherwise; re-evaluated when
  passes change, including the local mirror after a mid-session VIP grant). UIController carries
  `vipSkins` in `localSettings`, snapshot/delta parsing, and the optimistic write; the toggle fires
  `RequestSetSetting("vipSkins", value)` like the others. SoundController ignores the key.

## Ownership (one wave, disjoint)

| Agent | Files |
|---|---|
| luau-engineer | `src/shared/Types.luau`, `src/server/Main.server.luau`, `src/server/Services/{DataService,RemoteService,EconomyService,PlotService}.luau` |
| ui-engineer | `src/client/UI/SettingsPanel.luau`, `src/client/Controllers/{UIController,SoundController}.luau` |

**Done when:** a VIP owner toggles "VIP building skins" off and every building on their plot
rebuilds with the normal textures (and back on with VIP textures); the setting survives rejoin; a
non-VIP player never sees the row; an old v3 profile loads as v4 with `vipSkins = true`; stylua,
selene, luau-lsp analyze and `rojo build` are clean.

---

# Amendment — asset preload, no grey flash (2026-09-16)

Ben saw template buildings appear grey/untextured and colour in a moment later: MeshParts are
parented before their MeshContent/TextureContent have downloaded on the client. Client-only fix;
no server, remote or config change.

## Contract

- **New module `src/client/Controllers/AssetPreloader.luau`:**
  - `AssetPreloader.PreloadEra(eraName: string, includeVip: boolean): ()` — non-yielding; spawns
    one `ContentProvider:PreloadAsync` pass over `rbxassetid://` content strings read from
    `Catalog.GetAssetsConfig()`: first every distinct `imageId` of the era's parts (plus each
    kit's `vipImageId > 0` when `includeVip`), then every `meshId`, stage 0 first then ascending
    stages. Ids already requested are skipped (module-level set), so repeat calls are cheap. A
    missing config/era is a silent no-op. PreloadAsync runs inside `pcall`; failures are ignored
    (the building is shown anyway).
  - `AssetPreloader.AwaitInstance(instance: Instance, timeoutSeconds: number): ()` — yields until
    `PreloadAsync` over the instance's MeshParts finishes or the timeout elapses, whichever first.
    Never errors.
- **Hide until loaded:** the client watches every plot's `Buildings` folder (all plots, not only
  the local one — other players' plots flash too). When a template building Model or a new
  `Stage<n>` child appears, its BaseParts get `LocalTransparencyModifier = 1`, then
  `AwaitInstance(..., Theme.ASSET_LOAD_TIMEOUT_SECONDS)` (new Theme constant, 3), then the
  modifier returns to 0. Placeholder Parts (no MeshParts) are not hidden. Parts that stream in
  later under an already-hidden stage are handled the same way.
- **FX ordering (local owner):** the existing reveal tween on buy and the stage pop on `stageUp`
  start only after the building/stage is visible, so the animation never plays on an invisible or
  grey model. If the Fx event arrives before the Model replicates, keep today's behaviour for
  finding it, then wait on the same load gate.
- **Kick-off:** `UIController` (or `Main.client`) calls `PreloadEra(state.era's era name,
  state.passes.VIP == true)` on the first Snapshot and again whenever the era or VIP pass changes
  (and for the next era once the player can advance, if cheap to detect).

## Ownership

| Agent | Files |
|---|---|
| ui-engineer | new `src/client/Controllers/AssetPreloader.luau`, `src/client/Controllers/PlotVisualsController.luau`, `src/client/Controllers/UIController.luau`, `src/client/Main.client.luau`, `src/client/UI/Theme.luau` |

**Done when:** on a fresh join and on buy/level-up, Village buildings appear already textured (or
after at most the timeout); nothing stays invisible when an asset fails; other players' plots
behave the same; stylua, selene, luau-lsp analyze and `rojo build` are clean.

---

# M9 contracts — city dressing: roads, trees, filler, squares, vehicles (2026-09-16)

Read `docs/PLAN.md` "M9" and `docs/SPEC.md` §8 (amended) first, then `docs/ASSET_RESEARCH.md` §4
for the kit facts. Decided by Ben 2026-09-16: **everything in this milestone is client-side
cosmetics**, derived deterministically from replicated facts; **no dressing part collides**;
**car-kit belongs to Boomtown and Metropolis**. Balance, remotes and the economy are untouched.

## Principles

- The server publishes two attributes per plot and nothing else. Every client builds the same
  dressing from `(eraName, growthTier, owned slots, plotIndex)`; nothing about it is persisted,
  replicated or validated. Two clients may see different vehicle positions; that is fine.
- **No collisions, no queries, no touch** on any dressing instance (roads, junctions, trees,
  houses, plazas, lamps, vehicles): `CanCollide false`, `CanQuery false`, `CanTouch false`,
  `Anchored true`. Players walk through trees and over roads; prompts and clicks pass through.
- Dressing only ever **adds** as a plot grows; it is cleared and rebuilt only on era change.
- Everything degrades: a missing prop template skips that feature silently; roads are plain Parts
  and never depend on an asset; a missing `CityDressing.json` disables the controller.
- Budget at tier 5, per plot: roads + junctions ≤ 60 parts, houses + plazas + lamps ≤ 25,
  trees ≤ 40 (near plots only), vehicles ≤ 6 (nearest plots only). Whole map ≤ ~1300 static
  anchored parts and ≤ ~20 moving parts.

## M9 ownership

| Owner | Files |
|-------|-------|
| lead | `docs/INTERFACES.md`, `docs/PLAN.md`, `docs/SPEC.md` §8, `docs/ASSET_RESEARCH.md` §4, `src/shared/Config/CityDressing.json` v1 (applied), routing |
| luau-engineer | `src/shared/Types.luau` (M9 additions), `src/shared/CityGrowth.luau` (new, pure), `src/shared/Catalog.luau` (`GetCityDressingConfig`), `src/server/Services/PlotService.luau` (attributes only) |
| economy-designer | `src/shared/Layouts/*.luau` (streets/lots/plazas/treeZones), `CityDressing.json` tuning after v1, `tools/sim_economy.py` (tier timeline), `docs/BALANCE.md` (tier section) |
| pipeline-engineer (general-purpose) | `tools/assets/**` (props mode), `tools/testfit/{blueprint,testfit}.py` (prop blueprints), `default.project.json` (`ReplicatedStorage.Assets` mapping only), `templates/_props/**` (generated) |
| prop-builder Village / Boomtown (general-purpose, `model: "opus"`) | `tools/testfit/blueprints/_props/<Era>/*.json` for their era only |
| ui-engineer | `src/client/City/**` (new), `src/client/Controllers/CityDressingController.luau` (new), `src/client/Controllers/AssetPreloader.luau` (props preload), `src/client/Main.client.luau` (registration), `src/client/UI/Theme.luau` (constants) |
| docs-keeper (after QA) | `docs/PLAYTEST.md`, `docs/MANUAL_STEPS.md`, `README.md`, PLAN ticks, `docs/ASSET_MANIFEST.md` regeneration |

Frozen: `Config/Eras/**`, `Config/{Game,Sounds,Monetization,LegacyShop,Assets}.json` (Assets.json
changes only through the pipeline), `Economy.luau`, every remote, `DataService`, `RemoteService`.
Wave 2 unfreezes `Types.SettingKey`, `DataService`, `RemoteService`, `SettingsPanel` for the
`cityDetail` setting (below).

## CityDressing.json — schema v2 (`src/shared/Config/CityDressing.json`, lead-applied; Rojo → ModuleScript)

**v2 (wave 1b):** `road.spineTierStep` removed; `budget.roadPiecesNear`, `eras.*.road.meander` and
`eras.*.road.laneOffsetFraction` added. The shape below is v1; the amendments follow it.

The file is committed with these values; the shape is:

```json
{
  "version": 1,
  "tier": { "ownedWeight": 10, "thresholds": [10, 80, 250, 600, 1200] },
  "lod": { "nearRadius": 250, "hysteresis": 40, "vehiclePlots": 3, "refreshSeconds": 0.5 },
  "road": { "thickness": 0.2, "laneOffsetFraction": 0.25, "spineTierStep": 1 },
  "trees": { "stages": 4, "edgeMargin": 3 },
  "lamps": { "firstTier": 3, "everyNthJunction": 2, "maxPerPlot": 10 },
  "vehicles": { "firstTier": 2, "turnSeconds": 0.5 },
  "eras": {
    "Village": {
      "road": { "width": 5, "material": "Ground", "color": [126, 99, 66], "junctionProp": null, "bendProp": null },
      "trees": { "maxCount": 40, "clearance": 7, "prop": "TreeGrowing" },
      "houses": { "props": ["HouseA", "HouseB", "HouseC"] },
      "plazas": { "props": ["PlazaA"] },
      "lamps": { "prop": null },
      "vehicles": { "props": ["Cart"], "perPlot": 2, "speed": 5 }
    }
  }
}
```

Boomtown, Metropolis and OrbitalColony follow the same per-era shape (see the committed file):
asphalt 8-stud roads with `Junction`/`Bend`/`LampPost` kit props and car-kit `VehicleA..D` for
the two city eras; Orbital has 6-stud metal roads, no trees, a `Rover` only if space-kit has one.

- `material` is an `Enum.Material` name; `color` is RGB 0–255. Every `*Prop`/`props` entry is a
  prop name under `Assets.json.props.<Era>`; `null` or a missing template means "feature off".
- `tier.thresholds` has exactly 5 entries (tiers 1–5); economy-designer tunes them (below).
- Lead amendment (wave 1): `"budget": { "roadPieces": 60, "fillerPieces": 25, "trees": 40,
  "vehiclesPerPlot": 6, "vehiclesMap": 20 }` holds the part ceilings from Principles, and
  `trees.roadClearance: 2` is the extra clearance beyond `width / 2`, so neither lives in code.
  `trees.footprintMargin: 1`: tree spots are also rejected inside every slot, pad, lot and plaza
  footprint (from `Assets.json` part bounds) grown by this margin.
- Budgets count **placed pieces** (one Part or one cloned prop model), not MeshParts; a two-kit
  prop is one piece. `lod.refreshSeconds` must be ≥ 0.1 (the LOD pass is not a per-frame step).
- Ben 2026-09-16 (wave 1 tuning): `tier.ownedWeight` 10 → **50**, `tier.thresholds` →
  **[50, 400, 950, 1350, 1600]** (v1 never reached tier 5; the sim timeline is in `docs/BALANCE.md`).

**Street-plan amendments (Ben, 2026-09-16, wave 1).** Boomtown's main street at x = 0 is exactly one
road wide between the storefront pads and holds the median road-piece slots, so the strict rules
left 9 slots unreachable:
- **P1:** a spine may cover the slots whose model is itself a road piece (Boomtown
  `paveMainStreet`, `streetlampRow`, `trafficLights`) and their pads; every other clearance rule
  stays strict.
- **P2:** a `spur` override with exactly **one** point means "no spur for this slot": no Part, no
  junction, no lamp, no graph edge. Used where the building already sits on or against a road.
- **P3 (Ben, wave 1b):** a spine may also pass under a **monument** standing on a street centreline
  and under a decor slot whose footprint overlaps that monument (Boomtown `clockTower`,
  `fireHydrant`); both take one-point spurs. The tower becomes the main street's centrepiece.
`tools/streetplan.py` checks these rules by default.
- Ben's "city detail" setting (wave 2) halves `trees.maxCount`, disables lamps and restricts
  vehicles to the local plot; no extra config key is needed for that.

## Growth tier — `src/shared/CityGrowth.luau` (luau-engineer; pure, no Roblox globals)

```lua
CityGrowth.Score(ownedCount: number, totalLevels: number, ownedWeight: number): number
  -- ownedCount * ownedWeight + totalLevels
CityGrowth.TierFor(score: number, thresholds: { number }): number
  -- count of thresholds <= score, so 0..5. Monotonic in both inputs.
```

`tools/sim_economy.py` mirrors both 1:1 (economy-designer) and prints the tier timeline per era
(first minute each tier is reached for the greedy player). Tuning target: tier 1 on the first
purchase, tier 3 by ~40 % and tier 5 by ~80 % of the era's target duration in `docs/BALANCE.md`.

## Server behaviour (luau-engineer) — attributes only

- On the **plot folder** (`Workspace/Plots/Plot_<n>`, the parent of `Buildings`; not the Base, so the
  client has one place to watch): `EraName: string` (the era config `name`) and
  `GrowthTier: number` (0–5). Set both whenever the plot is configured for an era (claim, load,
  advance, rebirth) and `GrowthTier` after every buy, level-up and rebuild path that changes
  `totalLevelsThisEra` or the owned count; write only when the value changes. On plot release
  set `GrowthTier` 0 and `EraName` to the lobby era (`Village`).
- Score uses the same owned/levels numbers the sign and `totalLevelsThisEra` use.
- `Catalog.GetCityDressingConfig(): Types.CityDressingConfig?` — nil-safe like the others.
- **`Types.luau` additions:**

```lua
export type StreetLayout = { points: { Vector3 } }            -- polyline, studs rel. plot centre, Y 0
export type LotLayout = { position: Vector3, rotationY: number, tier: number }
export type PlazaLayout = { position: Vector3, rotationY: number, tier: number, prop: string }
export type TreeZoneLayout = { center: Vector3, radius: number, count: number }
-- EraLayout gains (all optional so untouched layouts stay valid):
--   streets: { StreetLayout }?, lots: { LotLayout }?, plazas: { PlazaLayout }?, treeZones: { TreeZoneLayout }?
-- SlotLayout gains spur: { Vector3 }?   (hand-authored spur override, pad edge → spine)
export type CityDressingConfig = { ... }                      -- mirrors the JSON above
```

Nothing else on the server changes: no remote, no rate-limit entry, no profile field in wave 1.

## Layouts (economy-designer) — the street plan per era

Every `src/shared/Layouts/<Era>.luau` gains:

- **`streets`** — 2 to 5 polylines (the "spine") in unlock order; polyline `i` (1-based) becomes
  visible at tier `i * road.spineTierStep`. Segments axis-aligned where possible; points at Y 0;
  ≥ `road.width / 2 + 1` studs clear of every slot footprint (9×9; monument 14×14; Metropolis
  `stadium` 12×12), pad and
  the `Sign`. The first polyline must pass the monument approach and the plot's front edge
  (−Z, the hub side) so an early plot reads as "a road into town".
- **`lots`** — 8 to 12 filler-house positions along the streets, facing the road (front −Z
  convention, `rotationY` like slots), each with the tier it appears at (2–5), ≥ 6 studs from any
  slot footprint.
- **`plazas`** — 1 or 2, each naming a prop from `eras.<Era>.plazas.props`, tier 3–5.
- **`treeZones`** — 3 to 6 circles covering the empty ground between clusters; `count` per zone,
  Σ count ≤ `eras.<Era>.trees.maxCount`.
- Optional **`slots.<id>.spur`** where the auto-route (below) would cut through something.

Village first (wave 1); Boomtown next; Metropolis and OrbitalColony in wave 2. economy-designer
checks the plan against the slot positions with a quick top-down plot (matplotlib to
`assets/testfit/out/<Era>/streetplan.png`) so Ben can approve it without Studio.

## Road routing (ui-engineer implements in `src/client/City/RoadGraph.luau`)

- **Spine:** each visible polyline segment becomes one Part: length = segment length + width
  (so corners overlap), `Size (width, road.thickness, length)`, top face at Y `road.thickness`,
  `Material`/`Color` from config, `TopSurface Smooth`, no collision (principles above).
- **Spur per owned slot** (a `Building_<slotId>` child exists in the plot's `Buildings`): start at
  the pad's outer edge (`padPosition or position + facing * padOffset`, plus `facing * padSize.Z/2`),
  leg 1 along the slot's facing until the projection onto the nearest spine segment is reached on
  that axis, leg 2 perpendicular to join; if a `spur` override exists, use its points verbatim.
  A spur to a not-yet-visible spine still draws. Spurs use the same width and material.
- **Junctions and bends** (Boomtown/Metropolis): where a spur meets the spine and at spine bends,
  clone `junctionProp`/`bendProp` from the props templates, rotated to the incoming directions;
  skip when the template is missing. Never more than one piece per junction point.
- **Graph:** nodes at every polyline point, junction and spur end; edges along the road centrelines
  with `laneOffsetFraction * width` as the right-hand lane offset. The vehicle loop reads this
  graph; it is rebuilt when a spur or spine appears and vehicles re-seat on the nearest edge.

## Trees, houses, plazas, lamps (ui-engineer, `src/client/City/Scatter.luau` + controller)

- **Seed:** `Random.new(plotIndex * 7919 + hash(eraName))`; identical on every client.
- **Trees:** for each zone, draw `count` candidate points uniformly in the circle, reject any point
  within `trees.clearance` of a slot anchor, lot, plaza, `Sign` or pad, within `width/2 + 2` of a
  road centreline, or within `trees.edgeMargin` of the plot edge; keep up to `count`. Tree `i`
  (0-based, across all zones) has birth tier `1 + floor(i * 5 / total)`; its visible stage is
  `clamp(growthTier - birthTier, 0, trees.stages - 1)`. The tree prop is a 4-stage template
  (below); the `Stage<n>` is chosen the same way `spawnBuilding` does. Trees exist only on
  **near** plots.
- **Houses:** each lot with `tier <= growthTier` gets one clone of a prop chosen from
  `houses.props` by the seed, pivoted like a building (bottom-centre on the lot position, front −Z
  rotated by `rotationY`). Always present (near and far).
- **Plazas:** clone the named prop at `tier <= growthTier`. Always present.
- **Lamps:** from `lamps.firstTier`, at every `everyNthJunction`-th spur junction of owned slots
  (seeded order), capped at `maxPerPlot`, offset to the right-hand road edge. Near plots only.
- **Hide-until-loaded:** every cloned prop goes through the existing `AssetPreloader.AwaitInstance`
  gate exactly like buildings; `AssetPreloader.PreloadEra` also walks `Assets.json.props.<Era>`.

## Vehicles (ui-engineer, `src/client/City/Traffic.luau`)

- Only on the **`lod.vehiclePlots`** plots nearest the camera (the local plot always counts); count
  per plot = `ceil(perPlot * growthTier / 5)` from `vehicles.firstTier`; models from
  `vehicles.props` by the seed; a plot leaving the nearest set despawns its vehicles.
- Anchored single-Model clones, no physics, no Humanoid, no collision. One `RunService.Heartbeat`
  connection for the whole map: advance each vehicle `speed * dt` along its edge (Y = road top),
  at a node choose a random outgoing edge that is not the one it came from (dead end → U-turn,
  blending the facing over `vehicles.turnSeconds`), then apply every CFrame with a single
  `workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)`.
- Vehicles start spaced evenly along the graph so they never spawn on top of each other; no
  collision avoidance between vehicles (toy scale, opposite lanes).
- Vehicle blueprints use **`scale: 2.5`** (≈ 6 studs long, fits the 8-stud road) and face −Z.

## LOD and lifecycle (ui-engineer, `CityDressingController`)

- Watches `Workspace/Plots/*`: `EraName`/`GrowthTier` attribute changes and `Buildings` child
  add/remove. `GrowthTier` up → add the newly qualifying pieces only. `EraName` change (or
  `GrowthTier` dropping) → clear the plot's dressing and rebuild.
- All dressing lives in a client-owned folder `Workspace/CityDressing/Plot<n>` (never inside the
  server's plot folder, so server watchers and the reveal gate are unaffected).
- **Near/far:** every `lod.refreshSeconds` compute camera distance to each plot centre; a plot is
  near when `< lod.nearRadius`, far when `> nearRadius + hysteresis`, unchanged in between. Far
  plots keep roads, junctions, houses and plazas; trees, lamps and vehicles are removed.
- Startup: on the first Snapshot the controller preloads the local era's props, then dresses every
  plot already present; plots added later are dressed on `ChildAdded`.
- `Theme` gains the copy/constants the controller needs (folder name); numbers that are tunables
  go in `CityDressing.json`, never in code.

## Props — blueprints, pipeline, templates (pipeline-engineer + prop-builders)

- **Blueprint path:** `tools/testfit/blueprints/_props/<Era>/<PropName>.json`, same schema as
  buildings (`id` == file stem; `era`; `scale` default 4.0; `footprint` optional; `pieces` with
  `stage`). Prop stages: `TreeGrowing` uses stages 0–3 (4 stages, each visibly taller/fuller);
  every other prop is single-stage (stage 0 only). Vehicles: `scale: 2.5`, front −Z, origin
  bottom-centre, wheels included in the merge (they do not spin). Junction/Bend: pick `scale` so
  the kit tile's road surface matches `road.width` (measure with `testfit.py --dump-bounds
  city-kit-roads`); footprint may be `[width, width]`.
- **Kit rules:** Village props = `nature-kit` (trees, cart), `fantasy-town-kit` (houses, plaza);
  Boomtown = `city-kit-suburban` (houses, trees, planters), `city-kit-roads` (junction, bend,
  lamps), `car-kit` (vehicles); Metropolis = `city-kit-commercial` (low filler shops, plaza),
  suburban trees/planters (existing exception), `city-kit-roads`, `car-kit`; OrbitalColony =
  `space-kit` only (no trees; `Rover` only if the kit has a vehicle, otherwise omit the file).
  Filler houses must not reuse a slot's silhouette (a filler `HouseA` is not the Village
  `HouseSmallA`).
- **Pipeline:** `merge_stages.py`, `upload_models.py`, `harvest.py --emit`/`harvest.py` and
  `gen_templates.py` gain `--props`, which switches the blueprint root to `_props/<Era>`, the
  Assets.json target to `props.<Era>.<PropName>` and the template output to
  `templates/_props/<Era>/<PropName>.rbxmx`. Stage count comes from the blueprint, not the era
  config (props are not slots). Same scale, same texture baking, same idempotent upload.
- **Assets.json v2:** adds `"props": { "<Era>": { "<PropName>": { "stages": [ … ] } } }` with the
  exact `AssetStage` shape; `version` 1 → 2; every reader tolerates a missing `props` key.
- **Prop template shape:** identical to the building template **except** every MeshPart has
  `CanCollide false`, `CanQuery false`, `CanTouch false` (Ben's rule). Rojo maps
  `ReplicatedStorage.Assets.Props` → `{ "$path": { "optional": "templates/_props" } }` so the client
  can clone them (`ServerStorage` is not replicated). `gen_templates.py --check` covers both roots.
- `docs/ASSET_MANIFEST.md` gains a props table per era (same columns).

## Wave 1b — natural paths (Ben's playtest, 2026-09-16)

Ben's first Studio look: "the paths idea is great, but they don't line up with anything, they are
way too wide and straight". Decided the same day. **This section supersedes the conflicting parts
of "Road routing", "Layouts" and "CityDressing.json" above.**

- **Roads grow with buildings (all eras).** Spines are no longer revealed by tier, and
  `road.spineTierStep` is removed. All spine polylines together form one road network. The plot
  **entrance** is point 1 of polyline 1. The visible spine is the union of the **shortest paths
  along that network from the entrance to the join point of every drawn spur** (owned slots,
  excluding P2 one-point spurs). Only those stretches exist: no road ever leads nowhere. When a
  building is bought, the missing stretch is added; nothing already drawn moves. Every join point
  must be reachable from the entrance (`streetplan.py` checks this).
- **Spurs start under their building (all eras).** A spur's first point is the slot anchor
  (`position`), not the pad's outer edge, so the path visibly runs out from under the building
  front, across the pad, to the spine. Leg 1 still runs along the facing. A multi-point `spur`
  override is prefixed with the anchor automatically when its first point is not already the
  anchor. Crossing its own footprint and pad is allowed; crossing any other footprint, pad, lot
  or plaza is not.
- **Meander (per era, `eras.<Era>.road.meander`, optional; Village only in wave 1):**
  `{ "amplitude": 0.7, "wavelength": 18, "segmentLength": 5, "widthJitter": 0.5 }`.
  - Every drawn centreline (spine stretch or spur) is cut into pieces of about `segmentLength`.
  - Each cut point moves sideways by `amplitude * taper * noise(arcLength)`. `noise` is a sum of
    two sines, with phases from the plot seed and the polyline index (spurs use the sorted slot
    id), so it is a pure function of arc length and never depends on draw order or which
    stretches are visible. Each piece's width is `width + widthJitter * noise2(arcLength)`.
  - `taper` goes 0 → 1 over one `width` from every graph node: polyline points, every
    potential join point of every slot (owned or not), and spur ends. Connections therefore
    always line up.
  - Pieces overlap by half a width so joints stay closed. A spine bend of ≥ 30° also gets one
    `Cylinder` disc (diameter = width, same material) so corners are round.
  - Eras without `meander` keep straight Parts and kit tiles as before.
- **Near/far roads.** Near plots draw meandered roads. Far plots draw the straight version (one
  Part per centreline segment) of the same visible network. A near/far flip rebuilds only the
  road Parts, and the lane graph is unaffected. Budgets: `budget.roadPieces` (60) applies to far
  and straight roads, `budget.roadPiecesNear` (160) to meandered near roads.
- **Lanes.** Vehicles follow the drawn centreline (meandered on near plots).
  `eras.<Era>.road.laneOffsetFraction` optionally overrides the global value. Village sets `0`,
  so carts drive single-file down the middle of the 3-stud trail; carts passing through each
  other is accepted.
- **Trees** keep `width/2 + amplitude + trees.roadClearance` from every potential road
  centreline.
- **Village road config:** `width` 5 → **3**, `material` `Ground` → **`Pebble`**, `color` stays a
  warm dirt brown. The Village street plan may use diagonal segments; no kit tiles need axis
  alignment there. Boomtown keeps its straight 8-stud asphalt grid and kit tiles, but gets the
  growth rule and the under-building spur start.

## Wave 1c — ribbon paths (Ben's second playtest, 2026-09-17)

Ben's second Studio look: the part-based trail is better, but "many textures are glitching". The
glitching comes from coplanar Part overlaps (z-fighting) and Pebble material seams on every
piece, and the curves read as angled rectangles. Ben approved the offline mock
(`tools/pathmock/`, renders in `assets/testfit/out/Village/paths/`). **This section supersedes
the drawing parts of "Wave 1b" for eras with `road.ribbon`.** The network rules from Wave 1b stay
unchanged: grow-with-buildings shortest paths, spurs from the slot anchor, P1–P3, and
determinism.

### Rendering, per plot, by availability
1. **`ribbon`** (primary) uses `AssetService:CreateEditableMesh` and then
   `AssetService:CreateMeshPartAsync(Content.fromObject(mesh))`. Each **layer** gets one
   EditableMesh and one MeshPart: layer 0 is polyline 1, layer 1 is the other polylines, layer 2
   is spurs. Separate parts per layer make higher layers sort above lower ones. Every create goes
   through a nil check and `pcall`: the API returns nil when the memory budget is exhausted, and
   fails in published games unless the owner is ID verified with "Enable Mesh / Image APIs" on.
   Any failure drops that plot to the next renderer silently.
2. **`beam`** (fallback) draws one flat Beam per spline span between Attachments on a single
   client anchor Part per plot. `CurveSize0/1` comes from the Catmull-Rom tangents converted to
   Bézier form. It uses the same texture, `TextureMode Wrap`, and
   `TextureLength = ribbon.textureLength`.
3. **`parts`**: the Wave 1b Part renderer, used when neither of the above works or the texture
   id is missing.
- `road.renderer` in `CityDressing.json` is `"auto"` (default), `"beam"` or `"parts"`. It forces
  a renderer for Studio testing.
- The MeshParts, the anchor Part and every Part keep `Anchored true` and `CanCollide`,
  `CanQuery` and `CanTouch` false. MeshParts also use `CollisionFidelity Box`, `CastShadow false`
  and `DoubleSided false`.

### Geometry — `src/client/City/PathRibbon.luau` (pure: numbers, tables and arrays only, no Roblox globals or services)
It ports `tools/pathmock/pathgeom.py`:
- **Control points:**
  - Drop collinear points.
  - Merge legs shorter than one width.
  - Put a circular fillet of radius `ribbon.cornerRadiusWidths × width` at each corner, with
    the tangent clamped to 0.95 of the incoming leg and 0.48 of the outgoing leg.
- **Spline:** centripetal Catmull-Rom (alpha 0.5) with mirrored phantom ends, then an arc-length
  resample.
- **Joins:** a joiner's end snaps to the nearest point on the host's **smoothed** curve, and the
  joiner is re-splined.
- **Meander:**
  - `offset = amplitude × taper × wave(s)` with
    `wave = 0.62 sin(ks + φ) + 0.38 sin(2.13ks + 1.71φ + 0.9)` and `k = 2π / wavelength`.
  - `φ = (key × 2.399963) mod 2π`, where `key` is the polyline index or, for spurs, the byte sum
    of the slot id.
  - `taper = smoothstep(distance to the nearest chain end or join / (2 × width))`.
  - Arc length is re-measured after the offset.
- **Cross-section:** 4 columns with v = 0, 0.265k, 1 − 0.265k, 1.
  - Mesh half-width = `ribbon.meshWidthFactor × (width + widthJitter × wave2) / 2 × flare × cap`.
  - The soft band stays a constant world width.
  - `u = arc / ribbon.textureLength + (key × 0.618) mod 1`.
  - Sample spacing is `ribbon.sampleSpacing`, dropping to 0.25 inside caps.
  - Winding is counter-clockwise seen from +Y.
- **Ends:**
  - A joined end extends 0.45 widths past the host centreline, flares by `ribbon.flare` over the
    last 3 studs, and gets a rounded cap.
  - A free dead end, or a growth tip, gets a cap `ribbon.capLength` long with profile
    `sqrt(1 − (1 − x)²)`.
  - **The plot entrance end stays full width** (no cap, no taper).
- **Height:** layer `i` sits at `road.thickness + i × ribbon.layerLift` above the plot top.
- Output per path: arrays of positions (plot-local), UVs and triangle indices, plus the
  smoothed centreline polyline with cumulative arc length.
- Everything is a pure function of `(layout, visible set)` (meander phases come from the
  polyline index or slot id, not the plot seed, so every plot of an era shares one shape, as in
  the approved mock), so a path is identical on every client. Adding a path never changes another path's geometry, because joins snap to
  the host's full smoothed curve, which is computed from the whole network.
- Magic numbers that are part of the look (0.62/0.38/2.13/1.71/0.9, 2.399963, 0.618, 0.265,
  0.45, 0.95/0.48) are named constants in PathRibbon with a why-comment pointing here. Tunables
  live in config.

### Texture
- `tools/paths/texture.py` (moved from `tools/pathmock/texture.py`) generates
  `village_path.png` deterministically: 1024×512 RGBA, tiling along u, soft irregular alpha
  edge.
- `tools/assets/upload_path_texture.py --era Village` uploads it the same way the VIP swatches
  are uploaded, and is idempotent.
- The harvest paste resolves the image id, as it does for swatches.
- The result lands in `Assets.json` as an optional additive key:
  `"pathTextures": { "Village": { "assetId": <n>, "imageId": <n> } }`.
- A missing key or an `imageId` of 0 means no texture, so the plot uses the `parts` renderer.

### Growth animation
- When a path is revealed **after** the plot's initial dressing (a purchase, not a join, rejoin
  or era rebuild), its ribbon grows from the host toward the building over
  `ribbon.growSeconds`. It is rebuilt over `[total − g, total]` with the tip cap.
- Ribbon renderer: vertex positions are updated in place on the layer's EditableMesh. Edits
  show immediately; no new MeshPart.
- Beam renderer: spans are revealed in order along the path, with `Width0/Width1` tweened from 0.
- Parts renderer: no animation.
- One extra `RunService.Heartbeat` connection may exist **only while a growth is running**, and
  is disconnected when none remain. Nothing grows on far plots, which draw instantly.

### Lanes, trees, near/far
- On ribbon and beam eras vehicles follow the smoothed, meandered centreline from PathRibbon.
  The Wave 1b lane-offset rule still applies.
- Trees keep `width/2 + meander.amplitude + trees.roadClearance` from the **smoothed**
  centreline. Scatter must use PathRibbon's centreline for every *potential* path so the tree
  plan never depends on ownership.
- Ribbons are drawn on near and far plots alike; there is no near/far rebuild for ribbon or beam
  roads. `budget.ribbonTriangles` caps triangles per plot. Past the cap, the plot uses `beam`.

### Config (`CityDressing.json`, lead-applied)
- `road.renderer: "auto"`.
- `budget.ribbonTriangles: 18000`.
- `eras.Village.road.ribbon: { "textureLength": 8, "meshWidthFactor": 1.4,
  "cornerRadiusWidths": 2, "sampleSpacing": 0.6, "capLength": 2.4, "flare": 0.4,
  "layerLift": 0.012, "growSeconds": 1.0 }`.
- Boomtown has no `ribbon` in wave 1c. It keeps straight asphalt Parts and kit tiles.

### Ownership (wave 1c)
| Owner | Files |
|-------|-------|
| lead | `docs/INTERFACES.md`, `CityDressing.json` |
| ui-engineer | `src/client/City/PathRibbon.luau` (new), `src/client/City/PathRenderer.luau` (new: ribbon/beam/parts selection and growth), `RoadGraph.luau`, `Scatter.luau`, `Traffic.luau` if needed, `CityDressingController.luau`, `src/shared/Types.luau` (the `CityRibbonConfig`, `road.renderer`, `budget.ribbonTriangles` and `AssetsConfig.pathTextures` additions only) |
| pipeline-engineer | `tools/paths/**` (texture generator moved from pathmock), `tools/assets/upload_path_texture.py` (new), the `harvest.py` path-texture support, `tools/gen_asset_manifest.py` (a path-texture row), `src/shared/Config/Assets.json` (pipeline writes only) |

### Done when
- In Studio, Village trails render as one smooth textured ribbon per layer: no z-fighting, soft
  edges, rounded corners, a full-width entrance.
- Buying a building grows its path in about 1 s.
- Setting `road.renderer` to `"beam"` or `"parts"` switches renderer with no errors.
- Deleting `pathTextures` gives the parts renderer silently.
- Heartbeat stays one traffic connection plus a growth connection only while a growth is running.
- stylua, selene, luau-lsp, rojo build, `streetplan.py`, the template checks and the manifest
  check are all clean.

## Wave 1d — baked paths (approved 2026-09-17: the C3 bake-off winner)

Ben ran the `tools/pathtest/` bake-off in Studio (A/B/C/C2/C3) and approved **C3**: "C3 is
excellent". **This section replaces Wave 1c's renderer entirely.** EditableMesh and EditableImage
are **banned in this project**: they need the owner to be 13+ and ID verified in published
experiences, and Ben will not verify. Wave 1b's network rules (grow-with-buildings shortest paths,
anchor-start spurs, P1–P3, determinism) still hold unchanged.

### The approved recipe (do not re-litigate)
- **Baked meshes, uploaded as Model assets** through the existing pipeline; the client clones
  templates. Geometry comes from `tools/pathmock/pathgeom.py` plus `tools/pathtest/planar.py`.
- **World-planar UVs:** `u = x / tileStuds`, `v = z / tileStuds` in plot-local coordinates,
  identical on every piece (`tileStuds` 11 for Village). Overlapping pieces then sample the same
  texel, which is what makes junction overlaps and any z-fighting invisible.
- **Fully opaque, 2D-seamless texture.** No alpha anywhere. Stylised flat dirt: bold simple
  pebbles, no fine grain, no directional features (a path crosses a tile in any direction), and
  dirt luminance well above the grass (155 against 118; a washed-out match is what failed before).
- **The irregular edge is cut into the mesh outline**, not into texture alpha: three sines
  (3.7, 2.6, 1.9 stud wavelengths), amplitude 0.35 studs, independent per side, sampled every
  0.25 studs, tapering to 0 within 1.3 studs of a tip so caps stay round.
- **Rim ribbon** per path: the same ribbon widened by 0.4 studs with its own 0.2-stud noise, in a
  darker desaturated copy of the same texture. Rims sit at `paths.rimHeight` (0.02) above the plot
  top and fills at `paths.fillHeight` (0.07), so a rim never shows across a path mouth.
- Every path MeshPart: `Anchored true`, `CanCollide`/`CanQuery`/`CanTouch` false, `CastShadow`
  false, `CollisionFidelity Box`, `Material SmoothPlastic`, `Color` white.

### Pieces (`pieceId`)
A piece is the smallest unit that can appear on its own, and it matches the Wave 1b network:
- **`L<polylineIndex>_<stretchIndex>`** for each spine stretch (a segment between two network
  nodes), and
- **`SP_<slotId>`** for each spur.

Both a `Fill_<pieceId>` and a `Rim_<pieceId>` mesh are baked per piece. Piece ids are derived from
the layout only, so they are stable across clients and runs; the bake fails loudly if a piece id
would change for an unchanged layout.

### Pipeline (pipeline-engineer)
- `tools/paths/bake.py --era <Era>` writes one GLB per mesh to
  `assets/build/paths/<Era>/{Fill,Rim}_<pieceId>.glb`, plus `<Era>.json` listing each piece's
  bbox centre, size, triangle count and the layout hash. Geometry is plot-local, `y = 0`, with the
  existing 0.005-stud centre crown so no bbox is flat.
- `tools/paths/texture.py --era <Era>` writes `assets/paths/<Era>_fill.png` and
  `<Era>_rim.png`, deterministically.
- `tools/assets/upload_paths.py --era <Era> [--dry-run] [--piece <id>]` uploads meshes and both
  textures, idempotently, and records them in `Assets.json` (v3, additive):
  `"paths": { "<Era>": { "tileStuds": 11, "fillImageId": n, "rimImageId": n,
  "pieces": { "<pieceId>": { "fill": { "assetId": n, "meshId": n, "size": [x,y,z],
  "offset": [x,y,z] }, "rim": { … } } } } }`.
- `harvest.py --emit` covers path pieces and path textures in the same paste as everything else.
- `gen_templates.py --paths` writes `templates/_paths/<Era>/<pieceId>.rbxmx`: a Model holding
  `Rim` and `Fill` MeshParts already at their relative heights, textured and sealed, positioned by
  bbox centre with the **180° Y turn** the Open Cloud import applies (`R00 = R22 = -1`; see
  `tools/pathtest/gen_display.py`). Rojo maps `ReplicatedStorage.Assets.Paths` →
  `{ "$path": { "optional": "templates/_paths" } }`.
- `gen_templates.py --check` and the manifest cover paths too.

### Client (ui-engineer)
- `PathRenderer` keeps two modes only: **`baked`** and **`parts`**.
  - **Remove the `ribbon` (EditableMesh) and `beam` code paths entirely, and delete
    `PathRibbon.luau`'s mesh-building half if nothing else uses it.** No dead code.
  - `baked` clones `ReplicatedStorage.Assets.Paths.<Era>.<pieceId>` per visible piece, pivots it
    onto the plot frame, and seals it. A missing template, era folder or `Assets.Paths` → `parts`.
  - `road.renderer` is `"auto"` or `"parts"`.
- **Appear effect (Ben's choice: dust puff, path pops in).** For a piece revealed after the plot's
  initial dressing, on a near plot: parent the `Rim` first, then the `Fill` after
  `paths.rimLeadSeconds` (0.15), and run a dust burst travelling from the piece's join end to its
  far end over `paths.dustSeconds` (0.8). Dust is one pooled `ParticleEmitter` per plot on a
  client part, moved along the piece's centreline, using a built-in texture
  (`rbxasset://textures/particles/smoke_main.dds`) so nothing needs uploading; `Enabled` only
  while a burst runs. At most one extra `RunService.Heartbeat` connection, alive only while a
  burst runs. Joins, rejoins, era rebuilds and far plots skip the effect and appear instantly.
- **Vehicles** follow the same smoothed centreline as before (`PathRibbon`'s centreline half
  stays). Trees keep using the smoothed centrelines of every potential path.
- **Budgets:** `budget.pathPieces` (per plot, 120) counts cloned piece Models. Far plots drop the
  `Rim` parts (`paths.rimNearOnly` true) to halve the part count; the fill is what reads at
  distance. Past the budget, further pieces are skipped in sorted order, as the parts renderer
  does today.

### Boomtown
- Same recipe with its own textures: asphalt fill, a lighter concrete **kerb** rim, `tileStuds` 11.
- **Lead ruling 2026-09-17: Boomtown drops the kit junction and bend tiles**
  (`eras.Boomtown.road.junctionProp`/`bendProp` → `null`). A kit tile's own texture cannot match
  the planar asphalt, so it would reintroduce exactly the overlap seam this wave removes. `Junction`
  and `Bend` blueprints stay in the repo, unused. `LampPost`, trees, houses, plazas and vehicles are
  unaffected.
- Boomtown's straight grid keeps its authored geometry; only the drawing changes.

### Config (`CityDressing.json`, lead-applied)
- `road.renderer`: `"auto"` | `"parts"`.
- `budget.pathPieces`: 120 (replaces `budget.ribbonTriangles`).
- `paths`: `{ "rimHeight": 0.02, "fillHeight": 0.07, "rimLeadSeconds": 0.15,
  "dustSeconds": 0.8, "rimNearOnly": true }`.
- `eras.<Era>.road.paths`: `{ "tileStuds": 11 }`; an era without it uses the parts renderer.
- `eras.<Era>.road.meander` stays: the bake reads it, and the parts fallback still draws it.
- `eras.Village.road.ribbon` and `eras.*.road.junctionProp`/`bendProp` for Boomtown are removed.

### Done when
- A Village plot and a Boomtown plot draw every owned building's path as baked meshes with rims,
  with **no visible seam at any junction** from any camera angle, and no z-fighting.
- Buying a building pops its path in with the dust burst; nothing flickers elsewhere.
- Deleting `templates/_paths`, or setting `road.renderer` to `"parts"`, silently falls back.
- Part counts stay within `budget.pathPieces`, far plots drop rims, and there is one traffic
  Heartbeat plus a dust Heartbeat only while a burst runs.
- **Part budget, re-cut for baked paths (lead, 2026-09-18).** The Principles line "≤ ~1300 static
  anchored parts for the whole map" predates them. A fully-owned Village plot is ≈ 174 path
  instances (58 pieces × Model + Fill + Rim) near, ≈ 116 far once rims drop; Boomtown is ≈ 99/66.
  New whole-map target: **≤ ~2600 static instances** with 10 plots at tier 5 (about half of it
  paths), still ≤ ~20 moving parts. If a MicroProfiler check says the path share costs frames, the
  lever is a coarser bake (`planargeom.STEP`), which changes the look and so needs Ben.
- stylua, selene, luau-lsp, rojo build, `streetplan.py`, the template checks and the manifest check
  are clean, and `tools/pathtest/**` plus its `Workspace.PathTest` mapping are removed once Ben has
  seen the real thing.

## Wave 1e — street upgrades (Ben, 2026-09-18)

Slots that are *named* as street improvements now change the streets. Still client-only: the
input is the owned-slot set the controller already derives from `Buildings/Building_<slotId>`.
No server change, no remote, no attribute, no profile field. Everything is config-driven and
nil-safe: a missing key, variant, image id or prop means "today's behaviour", never an error.

| Era | Slot | Effect |
|---|---|---|
| Village | `dirtRoad` ("Pave the Road") | every trail swaps to the **`cobble`** surface; **`Lantern`** posts line the visible trails |
| Boomtown | `paveMainStreet` | streets are **`gravel`** until it is owned, then today's asphalt + kerb (`default`) |
| Boomtown | `streetlampRow` | no lamps before it; then `LampPost`s line the visible streets (the tier-3 junction rule no longer applies to Boomtown) |
| Boomtown | `trafficLights` | a **`TrafficLight`** prop at street crossings |

### `streetOnly` slots (amended after Ben's first Studio look, 2026-09-18)
The one server change of the wave. `SlotConfig.streetOnly: boolean?` (era JSON; mirrored in
`Economy.luau`'s type): the slot's visual **is** the street, so `PlotService.spawnBuilding` spawns
an empty `Model` named `Building_<slotId>` at the slot anchor instead of `modelName` (no parts,
no prompt, no cosmetics). The marker keeps every client contract intact (ownership scan, spur,
reveal sound). Set on Village `dirtRoad` and Boomtown `paveMainStreet`, `streetlampRow` and `trafficLights`
(Ben, second look: the street props are the whole effect), whose kit models otherwise duplicate,
or sit on top of, the real street. Their blueprints/templates stay, unused.

### Surfaces (texture swap, no re-bake)
- A **surface variant** is one fill + one rim image using the approved C3 recipe (opaque,
  2D-seamless, stylised flat, bold simple shapes, no directional features, luminance well above
  the ground). UVs are world-planar, so every piece takes any variant unchanged.
- `"default"` is the texture baked into the templates (Village dirt, Boomtown asphalt + kerb).
- The whole plot has **one** surface at a time (a per-piece mix would bring the junction seam back).
- `eras.<Era>.road.paths.surface`: `{ "base": string, "upgrades": [{ "slot": string, "variant": string }] }`.
  Active variant = the **last** entry of `upgrades` whose slot is owned, else `base`. Absent
  `surface` = `"default"`.
- `eras.<Era>.road.paths.variants`: `{ [name]: { "material": string, "color": [r,g,b] } }` is the
  look the **parts fallback** uses for that variant (`"default"` uses `road.material`/`color`).
- `Assets.json` → `paths.<Era>.variants.<name>`: `{ fillAssetId, fillImageId, fillSha256,
  rimAssetId, rimImageId, rimSha256 }`, written by `upload_paths.py`. A variant whose image ids
  are missing or 0 resolves to `"default"`.
- Client: `PathRenderer.SetSurface(handle, fillImageId: number?, rimImageId: number?)` (nil =
  the template's own texture) writes `MeshPart.TextureID` on every live `Fill`/`Rim` and on every
  later clone (`addPiece`, `showRim`). `RoadGraph.SetSurface(state, owned: { [string]: boolean }, animate: boolean?)`
  (`animate` as in `AddSpur`) resolves the variant (uniformly for both renderers, so a variant
  without image ids is `"default"` in `parts` mode too), drives `PathRenderer` in `baked` mode and material/colour in `parts` mode.
  The controller calls it in `sync` after the spur loop, with `owned` computed once per sync.
  A surface change after the plot's initial dressing, on a near plot, replays the dust burst
  over the visible pieces; joins, era rebuilds and far plots switch instantly.
  `AssetPreloader.PreloadEra` queues every variant image.

### Lamps
- `eras.<Era>.lamps`: `{ prop, requiresSlot: string?, placement: "junction" | "row"?, spacing: number?, offset: number? }`.
  - `requiresSlot` set → lamps exist only while that slot is owned, and the slot **replaces**
    `lamps.firstTier`. Unset → today's tier rule.
  - `placement` `"junction"` (default) is today's rule. `"row"`: posts every `spacing` studs of
    arc length along each **spine** centreline (never spurs), alternating sides, `offset` studs
    outside the road edge (`width / 2 + offset`), facing the road; a post inside a slot footprint,
    pad, lot or plaza, or within `width / 2` of another centreline, is dropped.
  - The plan (`Scatter.Plan`) is ownership-independent and seeded as before; each post carries
    the spine piece id it sits on and spawns only while that piece is visible. Near plots only.
  - Cap: `budget.lampPosts` (row placement only; junction placement keeps sharing
    `budget.fillerPieces`). Posts are ordered **numerically** by `(polyline, stretch, step)`,
    never by id string; when the plan exceeds the cap it is thinned **evenly** over that whole
    order (keep candidate `i` of `n` iff `floor(i * cap / n)` differs from `i - 1`'s), so every
    trail keeps its share instead of the first polyline taking the budget.
- `eras.<Era>.signals`: `{ prop: string?, requiresSlot: string?, offset: number, maxPerPlot: number }?`.
  One prop at each graph node where **three or more spine stretches** meet, on the corner
  `offset` studs outside both road edges, spawned while the slot is owned and at least two of the
  node's stretches are visible. Absent key, nil prop or missing template = none.
- All of it obeys the M9 no-collision rule through `PropFactory` as lamps do today.

### Assets
- Textures: `tools/paths/texture.py` gains a per-era `variants` table → `assets/paths/<Era>_<variant>_fill.png`
  / `_rim.png`; `upload_paths.py` uploads and records them (displayName ≤ 50 chars guard applies).
- Props (`_props` pipeline → `ReplicatedStorage/Assets/Props`): `Village/Lantern`
  (fantasy-town-kit lantern on a post, ≈ 4–5 studs tall) and `Boomtown/TrafficLight`
  (city-kit-roads, may start from `blueprints/Boomtown/TrafficLight.json`).

### Ownership (wave 1e)
- lead: this section, `CityDressing.json`, `Types.luau` city types.
- ui-engineer: `src/client/City/{PathRenderer,RoadGraph,Scatter}.luau`,
  `src/client/Controllers/{CityDressingController,AssetPreloader}.luau`.
- pipeline-engineer: `tools/paths/texture.py`, `tools/assets/upload_paths.py`, `assets/paths/*`,
  `Assets.json` `paths.*.variants`, any tool mirror of the new budget key.
- prop-builder: `tools/testfit/blueprints/_props/Village/Lantern.json`,
  `tools/testfit/blueprints/_props/Boomtown/TrafficLight.json` and their strips. Uploads run
  after the pipeline-engineer's, never concurrently (`Assets.json`).

### Done when
- Fresh Village plot: dirt trails, no lanterns. Buying Pave the Road turns every trail to cobble
  with a dust burst and lanterns appear along drawn trails; later trails arrive cobbled and lit.
- Fresh Boomtown plot: gravel streets, no lamps at any tier. Pave Main Street → asphalt;
  Streetlamp Row → lamp rows on drawn streets; Install Traffic Lights → signals at crossings.
- Other players' plots show the same state; rejoining shows it instantly with no burst.
- Missing variant ids / props / `Assets.Paths` degrade silently (default texture, no lamps).

## Wave 2a — Metropolis streets, highway, subway (Ben, 2026-09-18)

Metropolis dressing, and three slots change meaning. Still client-only and config-driven; every
missing key, prop or layout table means "nothing drawn", never an error. The only server-visible
change is era JSON (`streetOnly`, one renamed slot).

| Slot | Was | Becomes |
|---|---|---|
| `cityGrid` | `RoadIntersection` crossroad tile | a real building: **City Hall** (`modelName: "CityHall"`, name "Found City Hall", still `type: "unlock"`, one stage, same cost/multiplier). The slot **id stays `cityGrid`** so no profile migration is needed. Layout `rotationY` becomes 0 (a facade, not a symmetric tile). |
| `highwayRamp` | `HighwayRamp` building | `streetOnly`. Owning it draws an **elevated ring highway** on pillars around the plot with one ramp down to the streets and cars on the deck. |
| `subwayLine` | `SubwayEntrance` building | `streetOnly`. Owning it places small **`MetroEntrance`** props at street corners around the city. |

The old `RoadIntersection` / `HighwayRamp` / `SubwayEntrance` blueprints, templates and
`Assets.json` entries stay, unused (same ruling as wave 1e).

### Tile streets (`road.tiles`) — Metropolis only
Ben chose Kenney **city-kit-roads** tiles for Metropolis. Boomtown keeps baked asphalt, Village trails.

- `eras.<Era>.road.tiles`: `{ "tileStuds": number, "props": { "straight", "end", "bend", "tee", "cross", "crossing": string }, "pavement": { "width": number, "material": string, "color": [r,g,b] }?, "spur": { "width": number, "material": string, "color": [r,g,b] }, "blocks": {…}? }` (see "Paved blocks").
  Presence of `tiles` selects the tile renderer; it is mutually exclusive with `road.paths` and `road.meander`.
  Metropolis: `tileStuds` **7** (= 28 / 4, four tiles per block pitch; Ben's choice over 9.33),
  `road.width` becomes 7, and `junctionProp` / `bendProp` are removed.
- **Grid rule (layout):** every `streets` point of a tiles era lies on the lattice
  `(7i, 0, 7j)`, every segment is axis-aligned, so a street is a run of whole cells.
  `tools/streetplan.py` enforces it.
- **Growth is unchanged:** `RoadGraph` still decides which spine stretches are visible (shortest
  paths from the entrance to each owned building's join). The tile renderer rasterises the
  *visible* stretches to cells and picks each cell's prop from its **visible** 4-neighbour
  connectivity (neighbours joined by a stretch, not merely adjacent), so a street end shows `end`
  and becomes `straight` / `tee` / `cross` as the network grows. A changed cell swaps its prop
  without a burst; a new cell drops in with the existing dust burst on near plots.
- **Canonical prop orientation at `rotationY` 0** (the kit's own; prop blueprints must keep it):
  `straight` and `crossing` run along **X**; `end` is open to **+X**; `bend` joins **−X ↔ +Z**;
  `tee` is open −X, +X, +Z (closed **−Z**); `cross` open on all four. The rotation table is code
  in the renderer (geometry, not a tunable).
- `crossing` replaces `straight` on the cell adjacent to a `cross`/`tee` cell when the run to the
  next junction is ≥ 3 cells (zebra at junction mouths), purely cosmetic.
- **Pavement (per cell, 2026-09-22):** for every drawn road cell, one plain Part strip
  `tileStuds × pavement.width` flush against each side **without** an arm, plus a
  `pavement.width` square at each corner whose two adjacent sides are both closed; a corner shared
  with a diagonal drawn cell has exactly **one owner** (the strip toward it is trimmed), no slab ever
  intersects a road cell's `tileStuds²`, and no two slabs are coplanar — top `road.thickness / 2`.
  A crossroads gets no pavement; a street end gets a U. Slabs are keyed by their rounded rect and
  reconciled every update (a cell that gains an arm drops that side's strip).
- **Spurs:** drawn by the existing parts renderer as a footpath with `tiles.spur` look from the
  kerb to the slot anchor (slot `spur` overrides still apply). Spurs never get tiles.
- Surfaces (`SetSurface`), signals and row lamps work as in wave 1e; `road.paths.*` keys are
  ignored in a tiles era. Lane graph for Traffic is unchanged (centreline ± `laneOffsetFraction`).
- Budget: `budget.tileCells` (180) caps cells per plot; far plots render cells without pavement.

### Elevated highway (`highway`)
- Layout (`EraLayout.highway: HighwayLayout?`):
  `{ ring: number, ramp: { cell: Vector3, direction: "+X"|"-X"|"+Z"|"-Z" } }` —
  `ring` is the centreline half-extent (Metropolis **56** = 8 cells: deck spans 52.5…59.5, clears
  the 46.5 block faces and the 12×12 Stadium at 48, stays inside the 120 plot). `ramp.cell` is the
  ring cell that carries the deck T-junction; `direction` points from that cell **into the
  city**; the ramp foot must land on a lattice cell that is the end of a `streets` polyline.
- Config `eras.<Era>.highway`: `{ "requiresSlot": string, "props": { "deck", "corner", "junction", "ramp", "sign": string? }, "vehicles": { "count": number, "speed": number }, "revealCellsPerSecond": number, "deckHeight": number? }`.
  `deckHeight` is the deck props' road-surface height in studs (Metropolis 7.07): a merged prop is
  one MeshPart, so the client cannot measure the slab apart from its rails; absent = no deck cars.
- Props (all `tileStuds` pitch, origin bottom-centre at ground level, pillars included so the
  client places one prop per cell): `HighwayDeck` (runs along **X**), `HighwayCorner` (joins
  −X ↔ +Z), `HighwayJunction` (deck T, closed −Z side faces outward), `HighwayRamp` (whole ramp as
  one prop, high end at the origin cell edge, descending toward **+X**, length = whole cells),
  `HighwaySign` optional. Soffit must be ≥ 6 studs so characters walk under it; the plot entrance
  passes beneath the deck.
- Client: drawn only while `requiresSlot` is owned. On purchase (near plot, after initial
  dressing) the ring builds outward from the ramp in both directions at `revealCellsPerSecond`;
  joins, era rebuilds and far plots show it instantly. Far plots: deck props only, no vehicles.
- Traffic: `highway.vehicles.count` cars loop the ring at deck height on the lane graph's usual
  offset (they never take the ramp). They count toward `budget.vehiclesPerPlot` / `vehiclesMap`.
- Budget: `budget.highwayCells` (72).

### Paved blocks (`road.tiles.blocks`, Ben 2026-09-22: "paved blocks + street trees")
- Layout `EraLayout.blocks: { BlockLayout }?`, `BlockLayout = { min: Vector3, max: Vector3, slots: { string } }`:
  axis-aligned ground rectangles (Y ignored) covering the ground between streets and out to the plot
  edge, inset so they never overlap a road cell, a pavement strip, a plaza or a kiosk (they may run
  under building footprints, pads and the elevated highway — its pillars stand on the slab, and the
  slab top 0.08 stays under the ramp foot's tile); `slots` lists the building slots standing on the block.
- Config `eras.<Era>.road.tiles.blocks: { "material": string, "color": [r,g,b], "treeSpacing": number, "treeInset": number, "treeClearance": number }?`
  (`treeClearance` = studs a street tree keeps from any footprint, pad, spur or kiosk).
- **Harvested offsets are in the template frame**: `Assets.json` `parts[].offset` carries the
  importer's 180° turn and `gen_templates.harvested_cframe` places the mesh at `−offset`; every
  client reader of those offsets (`Scatter.modelExtents`, `PropFactory.StageParts`) negates X and Z
  the same way, and ignores stages whose parts have no `meshId` (pre-harvest offsets are unturned).
- Street trees spawn only while **both** their block's slab is down and their spine piece is drawn.
- A tiles layout needs parallel streets ≥ `2 × (road.width / 2 + pavement.width) + 1` studs apart
  (`streetplan.py` checks it), or their pavement bands overlap.
- Client: a block's slab (one Part, top `road.thickness / 2 - 0.02` so it never shares a plane with
  pavement or pads) appears when **any** of its `slots` is owned; on a near plot after initial dressing
  it appears with the dust burst, else instantly. Street trees: `trees.prop` posts every `treeSpacing`
  studs along each slab edge that faces a **visible** street, `treeInset` studs inside the edge,
  skipping spots inside any footprint/pad/spur/kiosk; they count toward `trees.maxCount` and
  `budget.trees`, ordered numerically (block, edge, step) and thinned evenly like lamp rows. They are
  planned by `Scatter` alongside zone trees (zones keep the remainder of the budget).
- Absent `blocks` key or layout table = no slabs, no street trees (today's behaviour).

### Park strips in undrawn corridors (`road.tiles.parkStrips`, Ben 2026-09-22)
A junction whose other street has not grown yet must not show a dead-end sidewalk beside bare
ground. Every planned street cell that is **not yet drawn** carries a park strip: one paved slab
(`parkStrips.material/color`, same top as a block slab) covering the cell's `tileStuds²` plus its
pavement band where that band is not already laid, and `trees.prop` at stage `parkStrips.treeStage`
every `parkStrips.treeSpacing` studs along the cell run's centreline (a planter row), capped at
`parkStrips.maxTrees` per plot and thinned evenly. When the stretch draws, its strip cells and
trees are removed in the same update the tiles land (the dust burst covers the swap). Strips
never overlap a drawn cell, a laid pavement slab, a block slab or a kiosk. Far plots draw the slabs
only. Config: `{ "material": string, "color": [r,g,b], "treeSpacing": number, "treeStage": number, "maxTrees": number }`;
absent = today's behaviour. `tools/testfit/plotrender.py --tier N` shows them for undrawn streets.

### Subway entrances (`subway`)
- Layout (`EraLayout.subwayEntrances: { { position: Vector3, rotationY: number } }?`): 4–6 spots on
  pavement at street corners, spread over the whole plot, front (−Z convention) facing the
  street, clear of slot footprints, pads, lots, plazas, road cells and highway pillars.
- Config `eras.<Era>.subway`: `{ "requiresSlot": string, "prop": string, "maxPerPlot": number }`.
- Each entrance is tied to its nearest spine stretch (as row lamps are tied to a piece) and
  spawns while the slot is owned **and** that stretch is visible; the entrance nearest the plot
  entrance is exempt from the visibility rule so buying the slot always shows at least one.
- Prop `Metropolis/MetroEntrance`: **custom Blender geometry** (the kit cannot show stairs going
  down; Ben chose custom) from a committed generator `tools/assets/metro_kit.py`, same pattern as
  `stadium_kit.py`: colour-only materials sampled from the city-kit `colormap.png`, a raised
  kiosk with canopy, visible steps and a large "M" sign, footprint ≤ 5 × 6 studs, ≤ 1,200 tris.

### Moving the avenue slots
`cityGrid`, `subwayLine`, `highwayRamp`, `financeDistrict`, `busStop` and the monument sit on the
corridor centrelines (x, z ∈ {0, ±28}) where streets must run. The economy-designer may move
these six slots (positions are not persisted) so that: streets run on the corridors; City Hall
stays central and faces the entrance; the `highwayRamp` pad stands by the ramp foot and the
`subwayLine` pad on a pavement beside an entrance; no pad is on a road cell. Building-block slots
(x, z ∈ {±14, ±42}) do not move.

### Metropolis props (the era has none today)
`templates/_props/Metropolis/` via the `_props` pipeline: `RoadStraight`, `RoadEnd`, `RoadBend`,
`RoadTee`, `RoadCross`, `RoadCrossing` (blueprint `scale` 7, one kit piece each); the four
highway props (+ sign); `MetroEntrance`; `LampPost`, `TrafficLight` (city-kit-roads); `VehicleA–D`
(car-kit at a scale that makes the body **≤ 2.7 studs wide**, ≈ 1.8, so two fit the 5.6-stud
asphalt; Boomtown's stay 2.5); `TreeGrowing`, `PlazaA`, `PlazaB`. Metropolis `houses.props` becomes
`[]` and its layout has no `lots` — the blocks are already full of buildings.

### Types (`Types.luau`, lead)
`RoadTilesConfig`, `HighwayConfig`, `SubwayConfig`, `HighwayLayout`, `SubwayEntranceLayout`;
`EraLayout` gains `highway: HighwayLayout?`, `subwayEntrances: { SubwayEntranceLayout }?`.

### Ownership (wave 2a)
- lead: this section, `CityDressing.json`, `Types.luau`.
- economy-designer: `src/shared/Layouts/Metropolis.luau`, `src/shared/Config/Eras/3_Metropolis.json`,
  `tools/streetplan.py` (Metropolis `STREET_FURNITURE`, lattice check, highway/subway checks, PNG).
- ui-engineer: `src/client/City/*` (new `TileRenderer.luau`, `Highway.luau`; `RoadGraph`,
  `Scatter`, `Traffic`), `src/client/Controllers/{CityDressingController,AssetPreloader}.luau`.
- prop-builder A: `_props/Metropolis/Road*.json`, `Highway*.json`. prop-builder B:
  `tools/assets/metro_kit.py`, `_props/Metropolis/MetroEntrance.json`. prop-builder C: the rest.
- `Assets.json` writers (merge → upload → harvest → templates, props and `CityHall`) run **one at
  a time, by the lead**, and only when no other session is uploading.

### Done when
- Fresh Metropolis plot: bare ground; each purchase grows tile streets with correct ends, bends,
  tees and crossroads, pavements and a footpath to the building; cars keep to their lanes.
- Found City Hall spawns the hall at the centre facing the entrance, pad in front.
- Build the Highway Ramp: no building; the ring builds out from the ramp, cars loop on it, and
  the player can walk under it everywhere including the plot entrance.
- Dig the Subway Line: no building; entrances appear at corners along drawn streets, more as the
  streets grow.
- Other players' plots match; rejoin is instant; missing props/layout keys draw nothing, silently.
- `py tools/streetplan.py Metropolis` is green; Village and Boomtown are pixel-for-pixel unchanged.

## Wave 2 — `cityDetail` setting (after wave 1 is in Studio)

Same pattern as the VIP-skins amendment: `settings.cityDetail: boolean`, default `true`;
`Types.SettingKey` gains `"cityDetail"`; profile schema v5 with an additive migration;
`RequestSetSetting` accepts the key (same validator and rate limit); the settings delta carries
it; SettingsPanel gains a row "City detail" visible to everyone; the controller treats `false` as
"halve `trees.maxCount`, no lamps, vehicles on the local plot only" and re-evaluates live.

## Wave 2c — living city (Ben, 2026-09-23)

Ben: "make the cities more alive, with more houses and trees and vehicles when the cities
progress". Rulings: growth stays keyed to `GrowthTier` (purchases and levels, no clock); scope is
**Village, Boomtown, Metropolis** (OrbitalColony is wave 2b, another session); all four kinds of
life ship: more lots, greenery, parked + more moving vehicles, pedestrians + ambient (chimney
smoke, birds). No day-night cycle, no lit windows. Built on branch `m9-wave2c-living-city` in the
worktree `C:\Users\benja\Desktop\tycoon-wave2c`, merged after wave 2b.

### Principles (unchanged from M9, restated because every new piece must obey them)
- Client only. No server file, remote, attribute or profile change. Every client derives the same
  dressing from `(era, tier, owned slots, plot seed)`.
- Every dressing part: `Anchored` true, `CanCollide`/`CanQuery`/`CanTouch` false.
- Every number in `CityDressing.json`. Missing prop, layout key or config key → that feature is
  absent, silently. Far plots (LOD) drop every new category.
- **Stable streams:** each new category draws from its own `Random.new(plotSeed + SALT)` (salts are
  module constants in `Scatter`: greenery 7001, parked 7002, walkers 7003, ambient 7004), after
  the existing plan. Only the lot count may shift existing lamp/vehicle picks, which is cosmetic.
- `Theme.lowEndDevice` true → no smoke, no birds (spec §10: low-end = no particles; touch alone
  keeps them, most players are on phones). `Theme.reducedMotion` (touch or low-end) → walkers
  glide without bob.

### Lots (more houses)
- `LotLayout` gains `kind: ("house" | "small")?`, default `"house"`. Per era,
  `houses.smallProps: { string }` (new) lists the props a `"small"` lot draws from; `houses.props`
  stays the `"house"` list. `Scatter.footprintsFor` takes extents **per kind** (union of that
  kind's harvested props), so a small lot reserves a small footprint.
- Footprint caps: `"house"` ≤ 9×9 studs; `"small"` ≤ 6×6 studs and ≤ 6.0 studs tall. The
  Metropolis contract line "`houses.props` becomes `[]` and its layout has no `lots`" is
  superseded: Metropolis now has lots in the outer bands and corners; any lot whose footprint
  lies under the ring deck (soffit 6.65) must be `"small"`.
- Targets (economy-designer places as many as clear every road, pad, slot and plaza — these are
  minimums): Village **≥ 18** lots (8 existing kept, same positions and tiers), Boomtown **≥ 18**
  (8 kept), Metropolis **≥ 10**. New lots spread over tiers 1–5 with **≥ 2 new lots per tier**, so
  every tier step adds visible houses. A lot's `rotationY` faces its nearest street.
- `budget.fillerPieces` 25 → **45** (plazas + lots + junction lamps, as today).
- Props: Village `CottageA`, `CottageB` (small; Village kits). Boomtown `HouseE`, `HouseF`
  (house; suburban `building-type-f`/`-h`, the two Boomtown has not used) and `ShedA`, `ShedB`
  (small; suburban/industrial). Metropolis `ApartmentA–C` (house; `low-detail-building-*` /
  `building-n` from city-kit-commercial that no slot uses) and `TownhouseA`, `TownhouseB` (small,
  ≤ 6.0 tall). Filler must not reuse a slot's silhouette (M9 props rule).

### Greenery (bushes, hedges, flower beds)
- Per era: `greenery = { props: {string}, perTier: {number}, lotGarnish: number, clearance:
  number, roadClearance: number }`. `perTier[t]` (length 5) is the cumulative zone-piece count at
  tier t (tier 0 → none). `lotGarnish` = pieces placed around each **visible** lot (seeded
  offsets just outside the lot footprint, never on a road or path strip).
- Layouts gain `greeneryZones: { TreeZoneLayout }?` (same shape as `treeZones`; may reuse the
  same centres). Pieces keep `clearance` from each other and `roadClearance` from road strips,
  and never enter a slot footprint or pad.
- Single-stage props, one merged MeshPart each, no growth animation (a pop-in with the existing
  dust burst is fine).
- `budget.greenery` = **48** per plot, near plots only.
- Props: Village `BushA`, `BushB`, `FlowerBedA`, `FlowerBedB`, `HedgeA` (nature-kit bushes and
  flowers, fantasy-town-kit hedges). Boomtown/Metropolis `BushA`, `BushB`, `FlowerBedA`, `HedgeA`,
  `PlanterA` from a generated **`garden-kit`** (`tools/assets/garden_kit.py`, colours sampled from
  the City Kits' `colormap.png`, 1 unit = 1 stud) plus suburban `planter`/`fence-low` (the existing
  Metropolis exception for suburban planters covers them).

### Parked vehicles, and more moving ones
- Layouts gain `parking: { { position: Vector3, rotationY: number, tier: number, lot: number? } }?`.
  A spot with `lot = n` (index into `lots`) shows only when that lot does (driveways); others are
  kerb bays. A spot must sit fully off every lane strip (≥ 0.5 stud clear of the drawn road edge)
  and show only once the street beside it is drawn (the controller checks the spot's nearest
  road segment is visible; if not, skip).
- Per era: `parked = { props: {string}, perTier: {number} }` (cumulative, like greenery).
  `budget.parked` = **16** per plot, near only.
- Props: Village `CartParked` (cart-high or the Cart reused — builder's call). Boomtown
  `ParkedA–C` (car-kit `hatchback-sports`, `suv`, `sedan-sports` at scale 2.5). Metropolis
  `ParkedA–C` (car-kit `hatchback-sports`, `suv`, `garbage-truck` at ≈ 1.8, body ≤ 2.7 wide).
  Bays: Boomtown ≈ 4×7 studs, Metropolis ≈ 3×5.
- Moving: `vehicles.perPlot` Village 2 → 3, Boomtown 4 → 6, Metropolis 6 → 8;
  `budget.vehiclesPerPlot` 6 → 8, `budget.vehiclesMap` 20 → 24.

### Pedestrians (walkers)
- New module `src/client/City/Walkers.luau`: its own pool and Heartbeat (BulkMoveTo), same
  shape as `Traffic` (`SpawnPlot`, `SetLanes`, `ClearPlot`, `Count`), budgeted separately.
- New `RoadGraph.WalkLanes(state, offset): Lanes` builds lanes over the same visible stretches and
  spurs at lateral offset `pedestrians.offset` on **both** sides of each street. At a node a
  walker takes a random outgoing walk lane; crossing a carriageway at a junction is allowed.
- Per era `pedestrians = { firstTier, perTier: {number}, offset, speed, bobHeight, bobHz,
  props: {string} }`. Offsets: Metropolis on the pavement (road half-width + pavement/2 ≈ 5.5),
  Boomtown on the verge (≈ 4.8), Village at the trail edge (≈ 1.3, clear of the carts at 0).
- `budget.walkersPerPlot` = **8**, `budget.walkersMap` = **24**; walkers run on the same nearest
  `lod.vehiclePlots` plots as cars.
- Props: generated **`people-kit`** (`tools/assets/people_kit.py`, Blender, 1 unit = 1 stud):
  chunky flat-shaded toy figures, one merged MeshPart each, **≈ 1.6–2.0 studs tall** (under a kit
  door), era outfits via colour factors: `WalkerA–D` per era (Village smocks/aprons, Boomtown
  casual, Metropolis suits). Motion = walk along the lane + vertical bob; no rig, no animation IDs.

### Ambient (smoke, birds)
- New module `src/client/City/Ambient.luau`, one Heartbeat only while something is live.
- `ambient.smoke = { firstTier, eras: {string}, props: { [propName]: {number} }, rate, lifetime,
  size: {number}, color: {number} }`. `props` maps a house prop name to a chimney offset
  `[x, y, z]` in the prop frame; a placed house of that prop gets one ParticleEmitter there
  (`smoke_main.dds`, like Dust). Village and Boomtown only.
- `ambient.birds = { firstTier, flocksPerTier: {number}, birdsPerFlock, radius, height, speed,
  prop }`. A flock circles over a `treeZones` centre with seeded phase; birds are a generated
  `Bird` prop (people-kit) in each era's `_props`. All three eras (Metropolis = pigeons, grey).
- `budget.birdsMap` = **18**; near plots only.

### Budget and LOD
- New near-plot maximum per plot: lots ≤ 45 filler, greenery 48, parked 16, walkers 8, birds 6.
  Far plots keep lots and houses (they are city silhouette) and drop greenery, parked, walkers,
  smoke and birds. The PLAN target is re-cut from measurement in the playtest; the step for
  Traffic + Walkers + Ambient together must stay **< 0.3 ms** with every map cap reached.
- **`cityDetail` (wave 2b, lands on main first):** when false, wave 2c also halves greenery and
  drops parked vehicles, walkers, smoke and birds (lots stay). Wired by the lead at merge, since the
  setting does not exist on this branch.

### Types (`Types.luau`, ui-engineer this wave)
`LotKind`, `LotLayout.kind`, `ParkingSpotLayout`, `EraLayout.greeneryZones`/`parking`,
`GreeneryConfig`, `ParkedConfig`, `PedestrianConfig`, `SmokeConfig`, `BirdsConfig`,
`AmbientConfig`; `CityEraDressingConfig` gains `greenery`, `parked`, `pedestrians`,
`houses.smallProps`; `CityDressingConfig` gains `ambient`; `CityBudgetConfig` gains `greenery`,
`parked`, `walkersPerPlot`, `walkersMap`, `birdsMap`. All new fields optional.

### Ownership (wave 2c, disjoint)
- lead: this section; the merge → upload → harvest → templates run (announced to the wave 2b
  session first, never concurrent with it).
- economy-designer: `src/shared/Layouts/{Village,Boomtown,Metropolis}.luau` (lots, greeneryZones,
  parking), `src/shared/Config/CityDressing.json` (all wave 2c keys for the three eras, top-level
  `ambient`, budget keys; **never** `eras.OrbitalColony`), `tools/streetplan.py` (lot/parking
  clearance checks + the new layers in its PNG, three eras only).
- ui-engineer: `src/shared/Types.luau` (the types above only), `src/client/City/{Scatter,RoadGraph,
  Walkers,Ambient}.luau`, `src/client/Controllers/{CityDressingController,AssetPreloader}.luau`.
  `Traffic.luau` is read-only unless a shared helper must move out of it.
- kit-builder: `tools/assets/{garden_kit,people_kit}.py`; `_props/*/Walker*.json`, `Bird.json`,
  and the Boomtown/Metropolis greenery blueprints.
- prop-builders Village / Boomtown / Metropolis: that era's new lot and parked-vehicle blueprints
  (+ Village greenery) under `tools/testfit/blueprints/_props/<Era>/`, strips in
  `assets/testfit/out/<Era>/`.

### Done when
- Village, Boomtown, Metropolis at tier 1…5: each tier step visibly adds houses, greenery and
  (from tier 2) parked vehicles, walkers and birds; Village/Boomtown chimneys smoke from their
  tier. Nothing overlaps a road, pad or building; no walker walks through a house.
- Tier 0 plots look exactly as today; Orbital Colony is untouched by this wave.
- Removing any new prop template or config key removes that feature only, no Output error.
- `py tools/streetplan.py <Era>` green for all three; stylua, selene, luau-lsp, `rojo build`,
  `gen_templates.py --check` clean; reviewer greps the collision flags on every new part.

## Waves

1. **Wave 1 (parallel, disjoint):** luau-engineer (types, CityGrowth, attributes, Catalog);
   economy-designer (Village + Boomtown layouts, sim tier timeline, threshold check);
   pipeline-engineer (props mode end to end, dry-run on a fixture); prop-builders Village and
   Boomtown (blueprints + strips); ui-engineer (controller, road graph, scatter, traffic,
   preload) built against roads-only until props exist.
2. **Lead:** approve the street plans and prop strips; run merge → upload; Ben pastes the harvest
   once per era; `gen_templates.py --props`; commit.
3. **Review + QA:** roblox-reviewer on the diff (focus: nothing client-built can affect server
   state; no collision flags; part budgets; Heartbeat cost), qa-runner, docs-keeper.
4. **Wave 2:** Metropolis + OrbitalColony layouts and props when their building sets have shipped
   (M8), and the `cityDetail` setting.

## Definition of done (M9)

- A fresh Village plot shows bare ground; the first purchase draws a spur and the first spine
  segment; by tier 5 the plot has roads, ≤ 40 growing trees, filler cottages, a plaza and two
  carts moving along the roads; a Boomtown plot has asphalt roads with kit junctions, lamps and
  four car-kit vehicles. Other players' plots dress identically from their attributes.
- Walking through any tree, house, vehicle or over any road never blocks the player or a
  ProximityPrompt; `CanCollide`/`CanQuery`/`CanTouch` are false on every dressing part
  (reviewer greps it).
- With all 10 plots at tier 5 the map holds ≤ ~1300 static dressing parts; the Heartbeat traffic
  step stays under 0.2 ms with 20 vehicles (MicroProfiler in Studio, PLAYTEST step).
- Deleting `CityDressing.json`, `templates/_props`, or any single prop template leaves the game
  playable with that feature absent and no error in Output.
- Era advance and rebirth clear and rebuild the dressing; rejoin reproduces the same layout.
- stylua, selene, luau-lsp analyze, `rojo build`, `gen_templates.py --check` and the sim are clean.


# C0 contracts — Expeditions foundation: second place, Armory, teleport handoff (2026-09-17)

Read `docs/PLAN.md` "C0" and `.claude/memory/combat-2026-09-17.md` first. Decided by Ben
2026-09-17: combat ("Expeditions", co-op wave defense) lives in a **second place of the same
experience**; the **Armory is weapons only** (melee + ranged; **weapons determine max HP**), tiers
cost the era material and **unlock by the city's persisted income per second**; **cash and
materials are fixed per enemy**; friends can **join a run in progress**; Rebirth unlocks
**Ascension** and **Overdrive**. Milestones are C0–C3 (M10 stays reserved for icons). C0 ships
the plumbing and the Armory; no enemy is fought until C1.

## Principles

- **Server owns everything.** The hub validates every Armory purchase against the profile and
  `EconomyService.GetPersistedIncomePerSecond`; the combat place validates every hit and writes
  every reward. Teleport data is a hint, never an entitlement.
- **One profile, two places.** Same ProfileStore name and key. The hub **releases the session
  before** `TeleportAsync`; the combat place loads it on join; neither place ever passes `Steal`.
- **No RNG anywhere.** Rewards, unlocks and drops are deterministic functions of config + state.
- **Pure shared modules.** `src/shared/Armory.luau` and `src/shared/Combat.luau` take config as
  arguments, use no Roblox globals, and are mirrored 1:1 by `tools/sim_combat.py`.
- **Everything degrades.** `Places.json` ids of `0` disable the Expedition tiles with a message;
  missing `Armory.json` / `Combat.json` / mission configs hide the feature; missing weapon
  models leave the character's hands empty; the combat place boots standalone in Studio.
- **Every tunable lives in JSON:** `Config/{Armory,Combat,Places}.json`, `Config/Missions/*.json`.
  Nothing under `src/combat` may require `PlotService`, `EconomyService`, `MonetizationService`,
  `LegacyShopService` or `ArmoryService`.
- **Every subagent on this milestone runs on Opus** (Ben's ruling).

## C0 ownership (one wave, disjoint)

| Owner | Files |
|-------|-------|
| lead | this section, `docs/PLAN.md` C0, `src/shared/Config/{Armory,Combat,Places}.json` and `Config/Missions/1_Village.json` (schemas, applied), routing |
| luau-engineer | `combat.project.json` (new), `default.project.json` (`globIgnorePaths` only), `src/server/Services/ProfileSchema.luau` (new), `DataService.luau`, `RemoteService.luau` (`Configure`), `src/server/Services/HubRemotes.luau` (new), `ExpeditionService.luau` (new), `ArmoryService.luau` (new), `EconomyService.luau`, `src/server/Main.server.luau`, `src/combat/server/**` (new), `src/shared/Types.luau`, `src/shared/Catalog.luau`, `src/shared/Armory.luau` (new), `src/shared/Combat.luau` (new) |
| ui-engineer | `src/client/UI/TopBar.luau`, `src/client/UI/Theme.luau`, `src/client/UI/BottomBar.luau`, `src/client/Controllers/UIController.luau`, `src/client/UI/ArmoryPanel.luau` (new), `src/client/UI/ExpeditionPanel.luau` (new), `src/combat/client/**` (new) |
| economy-designer | values inside `Armory.json` (costs, unlockRate, damage, hp) and `Missions/1_Village.json` (keys are frozen), `tools/sim_combat.py` (new), `docs/BALANCE.md` "C0" |
| roblox-reviewer (after wave 1) | read-only review of the diff |
| qa-runner, docs-keeper (after review) | format/lint/build/sim; `PLAN.md`, `PLAYTEST.md`, `MANUAL_STEPS.md`, manifest |

Frozen: `Config/Eras/**`, `Config/{Game,Sounds,Monetization,LegacyShop,Assets,CityDressing}.json`,
`Economy.luau`, `PlotService`, `LegacyShopService`, `MonetizationService`, every existing remote's
payload, `src/client/City/**`. The JSON **keys** of the four combat configs are frozen by this
section; only the economy-designer changes their values.

## Rojo — two places, one shared tree

`default.project.json` is unchanged except `"globIgnorePaths": ["templates/_props", "templates/_enemies"]`.
New `combat.project.json`:

```
name: EraCityTycoonExpeditions
ReplicatedStorage
  Shared            ← src/shared            (same folder as the hub)
  Packages          ← Packages
  Assets/Props      ← templates/_props      (optional)
ServerScriptService
  Server (Folder)
    Main            ← src/combat/server/Main.server.luau
    Services        ← src/server/Services   (same folder as the hub; hub-only services are inert)
    Combat          ← src/combat/server/Services
  ServerPackages    ← ServerPackages
ServerStorage       ($ignoreUnknownInstances)
  Enemies           ← templates/_enemies    (optional)
Workspace           ($ignoreUnknownInstances: true — the arena is code-built; Ben may add scenery)
StarterPlayer/StarterPlayerScripts
  Client            ← src/combat/client
```

`DataService` keeps `script.Parent:WaitForChild("RemoteService")`, which resolves in both trees.
Builds: `rojo build -o build/test.rbxl` and `rojo build combat.project.json -o build/combat.rbxl`;
sourcemaps `sourcemap.json` and `sourcemap.combat.json` (`rojo sourcemap combat.project.json -o sourcemap.combat.json`).

## Profile schema v5 (`DataService`, `ProfileSchema.luau`)

`src/server/Services/ProfileSchema.luau` (new, required by `DataService` in both places) owns
`SCHEMA_VERSION = 5`, `STORE_NAME = "PlayerData"`, `PROFILE_KEY_PREFIX = "p_"`, `PROFILE_TEMPLATE`
and the `Migrations` table, moved verbatim from `DataService.luau:45-107`. `DataService` keeps its
public API unchanged and gains nothing else. `PlayerState` gains:

```luau
export type CombatProfile = {
	materials: { [string]: number },       -- material name ("Timber") -> integer, never negative
	valor: number,                          -- consumed by Ascension
	gear: { melee: number, ranged: number },        -- tier per slot; 0 = starter weapon
	ascension: { melee: number, ranged: number },   -- Ascension level per slot; 0 = none
	missions: { [string]: MissionRecord },  -- keyed by mission id ("village")
	highestEra: number,                     -- highest era index ever reached; survives Rebirth
	expeditionSince: number,                -- os.time() stamped by the hub on departure; 0 = not away
	expeditionSeconds: number,              -- seconds spent in the combat place since departure
	stats: { kills: number, wavesCleared: number, expeditions: number, cashFromCombat: number },
}
export type MissionRecord = { bestWave: number, bossClears: number, overdriveBest: number }
```

`PlayerState.combat: CombatProfile`. Template default:
`{ materials = {}, valor = 0, gear = { melee = 0, ranged = 0 }, ascension = { melee = 0, ranged = 0 }, missions = {}, highestEra = 1, expeditionSince = 0, expeditionSeconds = 0, stats = { kills = 0, wavesCleared = 0, expeditions = 0, cashFromCombat = 0 } }`.
`Migrations[4]` adds `combat` when nil and seeds `highestEra = math.max(1, state.era)`; additive
and idempotent like `[2]`. `PlotService.tryAdvanceEra` is frozen this milestone, so `highestEra`
is also raised lazily: `ArmoryService`/`ExpeditionService` call `Combat.TouchHighestEra(state)`
(`highestEra = max(highestEra, era)`) before any check that reads it.

## Config schemas (lead-applied; Rojo → ModuleScripts under `ReplicatedStorage/Shared/Config`)

- **`Places.json`** `{ version: 1, hubPlaceId: number, combatPlaceId: number }`. `0` = not
  published: the hub disables expedition tiles with "Publish the Expeditions place first"; the
  combat place's `ReturnService` shows "Hub place id not set" and keeps the player in the lobby.
- **`Combat.json`** (keys frozen, see file): `offline.expeditionEfficiency`; `player{ respawnSeconds, hitDistancePad, breatherRegenPerSecond, killCooldownRefundSeconds }`;
  `remotes{ attackCallsPerSecond, abilityCallsPerSecond, runListCallsPerSecond, combatStateHz }`;
  `director{ windowSeconds, tempoMin, tempoMax, mergeThreshold, mergeTempo, eliteTempo,
  breatherSeconds, breatherMaxSeconds, maxAlive, runCapSeconds }`; `coop{ maxParty, joinUntilWave,
  contributionFloor, countPerExtraPlayer, mentorRatio, mentorValor }`; `overdrive{ requiresRebirth,
  countMult, hpMult, damageMult, spawnRateMult, rewardMult }`; `registry{ mapName, ttlSeconds }`;
  `animations{ enemyIdle, enemyWalk, enemyAttack, enemyDeath }` (asset ids, 0 = none);
  `debug{ missionAttribute, overdriveAttribute, grantMaterialsAttribute, grantValorAttribute }`.
- **`Armory.json`**: `baseHp`; `power.hpWeight`; `bands[{ band, eraName, material }]`;
  `classes{ <class>: { kind: "melee"|"ranged", … } }` — melee classes carry `range, arcDegrees,
  chain[3], windows[3], comboReset, finisherKnockback`; ranged carry `fire: "charge"|"semi"|"auto"|"beam"`,
  `cooldown, range` and optionally `chargeSeconds, minDamageFraction, spreadDegrees, pierce`;
  `abilities{ <key>: { kind: "aoe"|"burst", cooldown, damageMult, radius?, shots?, knockback?,
  stunSeconds?, dashStuds?, dotSeconds?, dotTicks?, pierce? } }`;
  `slots{ melee|ranged: { starter{ name, class, damage, hp, ability, model }, tiers[{ tier, band,
  cost, unlockRate, name, class, damage, hp, ability, model }] } }` — `tiers` is ordered 1..12,
  `cost` is in the band's material, `unlockRate` is the persisted income/s required, `model` is a
  prop name under `ReplicatedStorage/Assets/Props/<band eraName>/` ("" = no model);
  `ascension{ requiresRebirth, levelsPerRebirth, levels[{ level, materials{name→n}, valor,
  damageMult, hpMult, abilityMult }] }`.
- **`Missions/<eraIndex>_<EraName>.json`** (resolved like eras, by numeric prefix): `{ version, id,
  era, eraName, name, arena, material, waves, bossWaves[], recommendedPower, targetMinutes,
  targetWaveSeconds, enemies{ <key>: { template, kind: "melee"|"ranged", hp, damage, speed, reach,
  attackCooldown, cash, materials, elite } }, waveTable{ baseCount, countPerWave, hpGrowth,
  damageGrowth, rewardGrowth, composition[{ fromWave, weights{key→w} }] }, bosses{ "<wave>": {
  template, enemy, hpMult, damageMult, cashMult, materialsMult, valor } } }`.

`Types.luau` gains `ArmoryConfig`, `WeaponClassDef`, `AbilityDef`, `WeaponTierDef`, `WeaponStarterDef`,
`AscensionLevelDef`, `CombatConfig`, `MissionConfig`, `EnemyDef`, `PlacesConfig`, `CombatProfile`,
`MissionRecord`, `RunState`, `RunSummary`, `ActiveRun` (shapes below). `Catalog.luau` gains
`GetArmoryConfig(): ArmoryConfig?`, `GetCombatConfig(): CombatConfig?`, `GetPlacesConfig(): PlacesConfig`
(missing → `{ version = 1, hubPlaceId = 0, combatPlaceId = 0 }`), `GetMissionConfig(eraIndex): MissionConfig?`
and `GetMissionById(id): MissionConfig?` (scans `Config/Missions`, cached). Armory/Combat use the
**nil-is-the-signal** pattern (like `GetAssetsConfig`): nil hides the whole feature.

## `src/shared/Armory.luau` (pure)

```luau
Armory.TierDef(cfg, slot, tier): WeaponTierDef | WeaponStarterDef   -- tier 0 = starter
Armory.WeaponDamage(cfg, slot, tier, ascLevel): number   -- tierDef.damage × ascension.levels[ascLevel].damageMult (1 when 0)
Armory.WeaponHp(cfg, slot, tier, ascLevel): number       -- tierDef.hp × hpMult
Armory.MaxHp(cfg, gear, ascension): number               -- baseHp + WeaponHp(melee) + WeaponHp(ranged)
Armory.GearPower(cfg, gear, ascension): number           -- round(WeaponDamage(melee) + WeaponDamage(ranged) + MaxHp × power.hpWeight)
Armory.NextTier(cfg, gear, slot): number?                -- gear[slot] + 1, nil past the last tier
Armory.TierCost(cfg, slot, tier): (material: string, amount: number)
Armory.TierUnlockRate(cfg, slot, tier): number
Armory.CanBuy(cfg, state, slot, incomePerSecond): (ok: boolean, reason: "locked"|"insufficientFunds"|"invalid"|nil)
   -- invalid: bad slot / no next tier; locked: incomePerSecond < unlockRate; insufficientFunds: materials short
Armory.AscensionCost(cfg, level): { materials: {[string]: number}, valor: number }?
Armory.AscensionCap(cfg, rebirthCount): number           -- 0 below requiresRebirth, else min(#levels, (rebirthCount − requiresRebirth + 1) × levelsPerRebirth)
Armory.CanAscend(cfg, state, slot): (ok, reason)          -- locked: cap reached / rebirth too low; insufficientFunds: materials or valor short
Armory.ClassDef(cfg, class): WeaponClassDef?  Armory.AbilityDef(cfg, key): AbilityDef?
```

## `src/shared/Combat.luau` (pure)

```luau
Combat.TouchHighestEra(state): ()                          -- state.combat.highestEra = max(highestEra, state.era)
Combat.MissionUnlocked(state, mission, overdrive, combatCfg): boolean   -- mission.era ≤ highestEra; overdrive needs rebirthCount ≥ overdrive.requiresRebirth
Combat.WaveSpec(mission, wave, partySize, overdrive, combatCfg): { count, hpMult, damageMult, rewardMult, boss: BossDef?, weights }
   -- count = round((baseCount + countPerWave×(wave−1)) × (1 + countPerExtraPlayer×(partySize−1)) × (overdrive and countMult or 1))
   -- hpMult = (1+hpGrowth)^(wave−1) × (overdrive and overdrive.hpMult or 1); damage/reward likewise with their growth and mults
Combat.EnemyStats(mission, key, spec, isBoss: boolean?): { hp, damage, cash, materials }?   -- rounded; boss mults apply ONLY when isBoss (never to ordinary enemies of the same key)
Combat.BossValor(mission, wave, overdrive, combatCfg): number
Combat.RecommendedPower(mission, overdrive, combatCfg): number   -- recommendedPower × (overdrive and hpMult or 1)
Combat.CombatCashMult(state, gameConfig, shopConfig): number      -- Economy.LegacyMult × Economy.PerkIncomeMult; NO pass/premium/neighbors
Combat.ContributionShares(damageByUser: {[number]: number}, floor): {[number]: number}   -- share_i = floor + (1 − floor·n) × dmg_i/total; equal split when total = 0
Combat.MentorBonus(combatCfg, hostRate, partyRates: {number}): number   -- mentorValor per member with rate < hostRate × mentorRatio
Combat.AwayEfficiency(elapsed, expeditionSeconds, efficiency, expeditionEfficiency): number
   -- time-weighted: (min(expeditionSeconds, elapsed) × expeditionEfficiency + max(elapsed − expeditionSeconds, 0) × efficiency) / elapsed; = efficiency when elapsed ≤ 0
Combat.Tempo(killsInWindow, windowSeconds, expectedKillsPerSecond, director): number   -- clamp(actual/expected, tempoMin, tempoMax); tempoMin when expected = 0
```
(C1 adds hit/ability math here; C0 ships the functions above with unit-style checks in the sim.)

## Snapshot / Delta / ActionResult additions (hub)

- `Snapshot` gains `gearPower: number` (server-computed via `Armory.GearPower`; 0 when Armory
  config is missing). `state.combat` rides inside `state`.
- `Delta` gains `combat: CombatProfile?` (a **copy**, never aliased, whenever the `combat` dirty
  flag flushes) and `gearPower: number?` alongside it. `EconomyService.DirtyFields` gains
  `combat: boolean?`; `MarkDirty(player, { combat = true })` is the only way combat changes reach
  the client.
- `ActionResult.action` gains `"buyGear" | "ascend" | "expedition" | "joinRun"`; `slotId` carries
  the weapon slot (`"melee"`/`"ranged"`), the mission id, or the host userId as a string.
  `reason` gains `"unavailable"` (place id 0, Studio, teleport failed after retries, run full/
  gone). `insufficientFunds` = materials/Valor short; `locked` = income/s below `unlockRate`,
  Ascension cap, or mission era above `highestEra`.

## Remotes

`RemoteService.Configure(defs)` must be called before `Init` (both places). Shape:

```luau
export type RemoteDefs = {
	intents: { [string]: { validate: (args: PackedArgs) -> boolean, bucket: string } },  -- client → server
	events: { string },                                   -- server → client, no validator, never rate limited
	rates: { [string]: number },                          -- bucket name → calls per second (clamped ≥ 1 with the existing warn)
}
```
`Init` creates every intent and event RemoteEvent under `ReplicatedStorage/Remotes`, connects
`OnServerEvent` only for intents, and reads bucket refill from `rates[bucket]`. The old
hard-coded tables move verbatim into `src/server/Services/HubRemotes.luau`, which exports the
hub `RemoteDefs` with buckets `calls` (Game.json `callsPerSecond`), `prompt`, `snapshot`, and adds:

| Remote | Args | Bucket | Handler |
|---|---|---|---|
| `RequestBuyGear` | `(slot: "melee"\|"ranged")` | calls | `ArmoryService` — `Armory.CanBuy` with `EconomyService.GetPersistedIncomePerSecond(player)`; on ok: subtract materials, `gear[slot] += 1`, `MarkDirty{combat}`, `ActionResult{buyGear, slot, ok}`; every refusal → `ActionResult` with the reason |
| `RequestAscend` | `(slot)` | calls | `ArmoryService` — `Armory.CanAscend`; subtract materials + valor, `ascension[slot] += 1` |
| `RequestExpedition` | `(missionId: string, overdrive: boolean)` | prompt | hub `Main` → `ExpeditionService.Depart` (below) |
| `RequestJoinRun` | `(hostUserId: number)` | prompt | hub `Main` → `ExpeditionService.Join` (C0: validates and replies `unavailable` unless a registry entry exists; full join flow is C2) |
| `RequestRunList` | `()` | runList (`Combat.json remotes.runListCallsPerSecond`) | `ExpeditionService` → `RunList` event with `{ ActiveRun }` from the registry, filtered to same-server players and friends (`IsFriendsWith` in pcall) |

New hub events: `RunList` (`{ runs: { ActiveRun } }`). `ActiveRun = { hostUserId: number, hostName: string, missionId: string, era: number, wave: number, overdrive: boolean, partySize: number, accessCode: string }` — the access code is **never** sent to clients; the server strips it in `RunList`.

`src/combat/server/Services/CombatRemotes.luau` exports the combat place `RemoteDefs`:

| Remote | Args | Bucket |
|---|---|---|
| `RequestSnapshot` | `()` | snapshot |
| `RequestRetryLoad` | `()` | calls |
| `RequestReady` | `()` | calls |
| `RequestLeave` | `()` | calls |
| `RequestAttack` | `(swingSeq: number, targetIds: { number })` | attack (`Combat.json remotes.attackCallsPerSecond`) — C0 validator only; handler is C1 |
| `RequestAbility` | `()` | ability — C0 validator only |
| events | `StateChanged` (Snapshot/LoadStatus as in the hub, no Deltas needed in C0), `ActionResult`, `RunState`, `CombatFx` | |

`RunState = { kind: "run", phase: "lobby"|"wave"|"breather"|"boss"|"summary"|"ended", missionId: string, overdrive: boolean, wave: number, waves: number, alive: number, tempo: number, party: { { userId: number, name: string, hp: number, maxHp: number, ready: boolean } }, breatherEndsIn: number?, summary: RunSummary? }`.
`RunSummary = { missionId, overdrive, wavesCleared, cash, materials: {[string]: number}, valor, kills, seconds }`.
C0 sends `RunState` on join (phase `lobby`, party list) and on `RequestReady`/`RequestLeave`
(phase `summary` with zeros); `CombatFx` exists but is unused until C1.

## Expedition handoff (hub `ExpeditionService`, called from `Main.server.luau`)

`ExpeditionService.Depart(player, missionId, overdrive)`:
1. `state = DataService.GetState(player)`; nil → drop. `Combat.TouchHighestEra(state)`.
2. Mission = `Catalog.GetMissionById(missionId)`; nil or `not Combat.MissionUnlocked(...)` → `ActionResult{expedition, missionId, false, "locked"}`.
3. `Places.combatPlaceId == 0` or `RunService:IsStudio()` → `ActionResult{…, "unavailable"}` (Studio toast: "Studio can't teleport — open build/combat.rbxl").
4. `ReserveServer(combatPlaceId)` in pcall with 3 attempts (backoff 1 s, 2 s, 4 s; the
   `MonetizationService.callWithRetry` shape); failure → `unavailable`.
5. Stamp `state.combat.expeditionSince = os.time()`, `expeditionSeconds = 0`,
   `stats.expeditions += 1`; `EconomyService.RefreshPersistedRate(player)`; `ActionResult{…, true}`.
6. Teardown in the frozen order `PlotService.Release`, `EconomyService.Cleanup`, `DataService.Release`
   (Main exposes this as `Main`'s existing `onPlayerRemoving` body, factored into a local
   `releasePlayer(player)` that both callers use).
7. `TeleportAsync(combatPlaceId, {player}, options)` with `ReservedServerAccessCode` and
   `SetTeleportData({ missionId, overdrive, hostUserId = player.UserId })`, pcall, 3 attempts.
   Final failure → `task.spawn(runJoinSequence, player, DataService.LoadAsync)` and
   `ActionResult{expedition, missionId, false, "unavailable"}`.

`ExpeditionService.Join(player, hostUserId)`: C0 reads the registry entry; missing, full
(`partySize ≥ coop.maxParty`) or `wave > coop.joinUntilWave` → `unavailable`; otherwise the same
steps 3–7 with the entry's `accessCode` and teleport data `{ missionId, overdrive, hostUserId }`.

Offline: in `EconomyService.ApplyOfflineGrant`, after the existing efficiency line,
`efficiency = Combat.AwayEfficiency(elapsed, state.combat.expeditionSeconds, efficiency, combatCfg.offline.expeditionEfficiency)`
(skipped when Combat config is nil); then `expeditionSince = 0`, `expeditionSeconds = 0`.

## Combat place server (`src/combat/server`)

`Main.server.luau` boot order: `DataService.Init/Start`, `RemoteService.Configure(CombatRemotes) + Init/Start`,
`RunRegistry`, `ArenaService`, `ReturnService`. Join sequence: `DataService.LoadAsync` → if nil,
safe mode as in the hub → read `player:GetJoinData().TeleportData` (hint) → in Studio, or when
the hint is missing, use Workspace attributes `DebugMission` (string, default `"village"`) and
`DebugOverdrive` (boolean) → `Combat.MissionUnlocked` against the **profile**; refused →
`ReturnService.SendHome(player, "locked")` → otherwise `ArenaService.Admit(player, mission, overdrive)`
(spawns at the lobby pad, sets `Humanoid.MaxHealth/Health = Armory.MaxHp`, fires `RunState lobby`),
`EconomyService`-style snapshot: the combat place sends `StateChanged` Snapshot with
`plotIndex = 0`, `eraName = mission.eraName`, `incomePerSecond = 0`, `persistedIncomePerSecond = state.incomeAtSave`, `gearPower`.
A 1 Hz Heartbeat accumulator adds to `state.combat.expeditionSeconds` for every admitted player.
`RequestLeave` / `ReturnService.SendHome`: fire `RunState summary`, `DataService.Release(player)`,
then `TeleportAsync(hubPlaceId, {player})` with teleport data `{ summary = RunSummary }` (pcall, 3
attempts; `hubPlaceId == 0` or Studio → stay, toast). PlayerRemoving → `DataService.Release`.
`RunRegistry`: MemoryStore sorted map `Combat.json registry.mapName`, key `tostring(hostUserId)`,
value `ActiveRun` (with `accessCode` from `TeleportData`/`game.PrivateServerId` when available),
`SetAsync` with `ttlSeconds` on admit and every wave, `RemoveAsync` when the last player leaves;
every call pcall + 3 retries + warn; Studio → no-op. Studio levers (combat place, 1 Hz tick,
`RunService:IsStudio()` only): `GrantMaterials` (number → that many of the mission's material to
every loaded player), `GrantValor` (number). Hub gets the same two levers in `ArmoryService`.
Nothing in `src/combat` writes `lastSeen`, `incomeAtSave`, `cash` (C0) or `slots`.

## Hub client (ui-engineer)

- `TopBar.SetPower(power: number?)` draws `⚔ <Format.Cash-style short number>` beside income;
  nil hides it (no Armory config). Fed from `UIController.refreshAll` via the model's `gearPower`
  (Snapshot and Delta both carry it).
- `BottomBar` gains keys `armory` and `expedition` (icons ⚔ and 🗺), hidden when the respective
  config is nil. `PanelKey` gains `"armory" | "expedition"`.
- `ArmoryPanel.new(screenGui, { armoryConfig, onBuy(slot), onAscend(slot), onClose })` with
  `Refresh(state: PlayerState, persistedIncomePerSecond: number)`, `FlashSlot(slot)`; two rows
  (Melee, Ranged): current weapon name + tier, damage, "+HP", next tier's line
  `"Tier 4 · 20 Steel · unlocks at 1K/s (you: 620/s)"`, Buy button (disabled state + reason
  colour: locked = amber, insufficient = red), materials wallet strip (one chip per band), a Max
  HP readout above the rows, Ascend row only when `rebirthCount ≥ ascension.requiresRebirth`.
  All intents fire the remotes; the panel never computes affordability for the server — it uses
  `Armory.CanBuy` only to colour the button.
- `ExpeditionPanel.new(screenGui, { missions, placesConfig, combatConfig, onDepart(missionId, overdrive), onJoin(hostUserId), onRefreshRuns(), onClose })`
  with `Refresh(state, gearPower)`, `SetRuns(runs)`: one tile per mission (locked above
  `highestEra`), "Recommended ⚔ N — you ⚔ M" coloured green (≥ 1.0), amber (≥ 0.7), red;
  Overdrive toggle visible when `rebirthCount ≥ overdrive.requiresRebirth`; "Active runs" list
  with Join buttons (asks `RequestRunList` on open and every 10 s while open). All tiles disabled
  with the message when `combatPlaceId == 0`.
- `onActionResult` handles the four new actions (flash + toast + `insufficientFunds` sound).
- Layout checked at 375×667 portrait and 812×375 landscape, one panel open at a time via the
  existing dock.

## Combat client (ui-engineer, `src/combat/client`)

`Main.client.luau` registers `CombatUIController` and reuses `SoundController` from the hub tree
**by copy** (`src/combat/client/Controllers/SoundController.luau` is a verbatim copy; report the
dedupe as a follow-up). `CombatUIController`: `LoadScreen` copy for safe mode, `CombatHud` (top:
mission name, wave "Lobby" / "Wave 3 / 10", tempo dot; bottom-left: HP bar from
`Humanoid.Health/MaxHealth`; party list with HP bars; Ready button in lobby; Return button always),
`SummaryCard` (fires on `RunState summary`; Return button → `RequestLeave`). No combat input in C0.

## `tools/sim_combat.py` (economy-designer)

Mirrors `Armory.luau` and `Combat.luau` function-for-function (same names in snake_case), loads
the four configs, and imports `simulate_era`/config loaders from `sim_economy.py` to obtain the
greedy player's income/s over time per era. `--check` prints one verdict line per assertion and
exits 1 on any failure:
1. For every tier: `unlockRate` is non-decreasing with tier and each band's first tier unlocks
   inside its era (the greedy player's income/s crosses it before the era ends).
2. At each era's median greedy income/s, the highest unlocked weapons give a Gear Power ≥ that
   era's `recommendedPower` (only Village exists in C0; skip missing missions with a note).
3. A modelled run (DPS = melee damage × chain avg / window avg × 0.7 hit rate + ranged damage /
   cooldown × 0.5 uptime; TTK per enemy = hp / DPS; wave time = count × TTK / party) at
   recommended power finishes waves 1–10 inside `targetMinutes` ±50 %.
4. Total run cash at recommended power (fixed per enemy × rewardMult × bosses) ≤ 25 % of the
   era's remaining slot cost at that point in the greedy run.
5. `ContributionShares` with a 10:1 damage duo gives the veteran ≥ 75 %.
6. `AwayEfficiency` equals the base efficiency at 0 expedition seconds and the expedition
   efficiency when the whole absence was an expedition.
`docs/BALANCE.md` gains a "C0 — Armory unlocks" table (tier → unlock time in the greedy run).

## Waves

1. luau-engineer ∥ ui-engineer ∥ economy-designer (all Opus). ui-engineer codes against the
   types in this section; `Types.luau` is luau-engineer's, so any missing field is reported, not
   added.
2. roblox-reviewer → qa-runner (`stylua --check src`, `selene src`, both `rojo build`s, both
   sourcemaps + `luau-lsp analyze` with `tools/types/globalTypes.d.luau`, `py tools/sim_economy.py --check`,
   `py tools/sim_combat.py --check`, `py tools/assets/gen_templates.py --check`,
   `py tools/gen_asset_manifest.py --check`) → docs-keeper.

## Definition of done (C0)

- Both builds succeed; hub behaviour with `Places.json` ids at 0 is unchanged except the new
  Power readout, Armory and Expedition panels (tiles disabled with the message).
- A fresh profile migrates to v5; a v4 profile gains `combat` with `highestEra = era`.
- Buying Wooden Sword with 10 Timber (via the `GrantMaterials` lever) raises Gear Power and the
  Armory's Max HP readout; buying above the income gate returns `locked`; Ascend is hidden at
  rebirth 0 and refused server-side.
- `build/combat.rbxl` opened in Studio with `DebugMission = "village"`: loads the same profile
  (mock in Studio), shows the lobby HUD with the player's HP = `Armory.MaxHp`, Ready and Return
  work, `expeditionSeconds` ticks, and Return with `hubPlaceId = 0` stays with a toast.
- On a published pair of places: Depart → arrive → Return round-trip keeps cash and levels, and
  the welcome-back card pays the away time at `expeditionEfficiency`.
- `py tools/sim_combat.py --check` passes; `sim_economy.py --check` output is unchanged.

---

# C1 contracts — Studio bridge + Village expedition (Ben, 2026-09-22)

Ben cannot reach the published pair (audience-reach block, `docs/DISCOVERY_CHECKLIST.md`), so C1
ships two things at once: a **Studio bridge** that makes every C0 platform path (teleport
payloads, summary home, run registry, teleport failures) executable from Studio, and the **Village
expedition** itself (arena, enemies, waves, melee/ranged/abilities, director, feedback). Every C0
principle above still holds. Every subagent runs on Opus. Read the C0 contracts first; this
section only adds to them.

## Ownership (one wave, disjoint)

| Owner | Files |
|-------|-------|
| lead | this section, `Config/Combat.json` + `Config/Sounds.json` keys (applied), the config-type additions in `Types.luau` (applied before fan-out), routing |
| luau-engineer **A** (combat core) | `src/combat/server/Main.server.luau`, `src/combat/server/Services/{ArenaService,CombatRemotes}.luau`, new `src/combat/server/Services/{WaveService,EnemyService,CombatService,DebugService}.luau`, new `src/shared/Layouts/Arenas/Village.luau`, `src/shared/Types.luau` (everything except the lead-applied config types), `src/shared/Combat.luau` |
| luau-engineer **B** (Studio bridge) | new `src/server/Services/StudioBridge.luau`, `src/server/Services/ExpeditionService.luau`, `src/server/Services/HubRemotes.luau`, `src/server/Main.server.luau`, `src/server/Services/ArmoryService.luau` (hub debug remote only), `src/combat/server/Services/{ReturnService,RunRegistry}.luau` |
| ui-engineer **A** (combat client) | `src/combat/client/**` |
| ui-engineer **B** (hub client) | `src/client/Controllers/UIController.luau`, `src/client/UI/ExpeditionPanel.luau`, new `src/client/UI/{ExpeditionSummaryCard,DebugPanel}.luau`, `src/client/UI/BottomBar.luau` (only if a key is needed) |
| economy-designer | values in `Missions/1_Village.json`, `Combat.json`, `Armory.json` (keys frozen), `tools/sim_combat.py`, `docs/BALANCE.md` "C1" |
| roblox-reviewer → qa-runner → docs-keeper | after wave 1 |

A and B both touch the combat place: A owns `Main.server.luau` and calls B's `StudioBridge` by
the API below; B owns `ReturnService`/`RunRegistry` and calls A's `ArenaService`/`WaveService`
by the APIs below. Neither edits the other's files; a needed change is reported to the lead.
Frozen: everything frozen at C0, `DataService`, `ProfileSchema`, `EconomyService`, `RemoteService`.

## Studio bridge (`src/server/Services/StudioBridge.luau`, B; lives in the shared Services folder so both places see it)

Purpose: in Studio, replace the one thing Studio cannot do (`TeleportAsync`) with a **handoff
record** and a kick, and let every other platform path run for real. Nothing in this module
runs outside `RunService:IsStudio()`; every public function returns the "inactive" value
immediately when not in Studio.

```luau
export type TeleportHint = { missionId: string, overdrive: boolean, hostUserId: number, accessCode: string? }

StudioBridge.IsActive(): boolean                         -- RunService:IsStudio()
StudioBridge.WriteDeparture(player, hint: TeleportHint, kind: "depart" | "join"): boolean
   -- DataStore `Combat.json debug.handoffStoreName`, key "p_<userId>", value
   -- { kind, missionId, overdrive, hostUserId, accessCode, stamp = os.time() }. pcall + 3 retries + warn.
   -- Returns false (and warns "[StudioBridge] handoff needs API access" once) when DataService.IsMockMode().
StudioBridge.ClearDeparture(player): ()                  -- RemoveAsync, used by the simulated teleport failure
StudioBridge.ReadArrival(player): TeleportHint?          -- combat place: GetAsync then RemoveAsync (consumed once); nil when absent, mock, or kind == "return"
StudioBridge.WriteReturn(player, summary: Types.RunSummary): boolean   -- value { kind = "return", summary, stamp }
StudioBridge.ReadReturn(player): Types.RunSummary?       -- hub: consumed once; nil when absent/mock/other kind
StudioBridge.TeleportShouldFail(): boolean               -- Workspace boolean attribute debug.forceTeleportFailureAttribute; read once and reset to false
StudioBridge.RegistryShouldFail(): boolean               -- Workspace boolean attribute debug.forceRegistryFailureAttribute; sticky (not reset)
StudioBridge.Depart(player, message: string): ()         -- task.delay(1, player.Kick) so the ActionResult/toast lands first; the kick is the Studio stand-in for leaving the server
```

A record older than `debug.handoffMaxAgeSeconds` is ignored and removed (a stale handoff from
an aborted session must not hijack the next boot). Records are validated on read exactly like
`readTeleportHint` validates `TeleportData` today (types, integer userId > 0, string ids).

### Hub side (B: `ExpeditionService`, `Main.server.luau`)

`ExpeditionService.Depart` step 3 becomes: `combatPlaceId == 0` → `unavailable` (unchanged);
`StudioBridge.IsActive()` → steps 4–7 run in **bridge mode**: no `ReserveServer` (accessCode
`"studio"`), step 5 as today, then `StudioBridge.WriteDeparture` (false → `unavailable`, nothing
released), step 6 release, then `if StudioBridge.TeleportShouldFail()` → the **same** recovery the
live `TeleportInitFailed` handler runs (re-load via `runJoinSequence`, `ActionResult{expedition,
false, "unavailable"}`, `StudioBridge.ClearDeparture`) else `ActionResult{expedition, missionId,
true}` and `StudioBridge.Depart(player, "Handoff saved — Stop Play, then open build/combat.rbxl")`.
`Join` does the same with `kind = "join"` and the registry entry's access code; an entry whose
`accessCode == "fake"` (see `DebugFakeRuns`) answers `unavailable`.

Hub `Main.server.luau` join sequence, after a successful load: `summary = TeleportData.summary`
(validated shape) `or StudioBridge.ReadReturn(player)`; when present fire the new hub event
**`ExpeditionSummary`** `(summary: RunSummary)` to that player. Rewards are already in the
profile; the event is presentation only. `HubRemotes` adds the event and the intent
`RequestDebug(lever: string, value: any)` (bucket `calls`; validator: `args.n == 2`, string lever
≤ 32 chars, value nil/boolean/number/string ≤ 64 chars). `ArmoryService` handles it and **ignores
it outside Studio**: levers `grantCash`, `grantMaterials`, `grantValor` (same effect as the
attributes, for the calling player only), `fakeRuns` (number N → `RunRegistry`-style entries via
`ExpeditionService.PublishFakeRuns(N)`: hostUserId −1…−N, hostName "Fake N", `village`, wave N,
partySize 1, accessCode `"fake"`, TTL from config), `forceTeleportFailure` (boolean → sets the
Workspace attribute). The attribute path stays; the remote exists so the hub `DebugPanel` can
drive it with buttons.

### Combat side (A: `Main.server.luau`; B: `ReturnService`, `RunRegistry`)

`resolveRun` order in Studio: `readTeleportHint` (never present in Studio) → `StudioBridge.ReadArrival`
→ Workspace attributes → `DEFAULT_DEBUG_MISSION_ID`. A hint from the bridge is validated exactly
like a live hint (mission exists, `Combat.MissionUnlocked` against the profile, host id). Outside
Studio nothing changes.

`ReturnService.SendHome` in Studio with `hubPlaceId ~= 0`: summary `RunState` as today, then
`StudioBridge.WriteReturn`, `DataService.Release`, then `if StudioBridge.TeleportShouldFail()` →
the same re-admit path as a live `TeleportInitFailed` (toast "couldn't send you home, try again")
else `StudioBridge.Depart(player, "Run over — Stop Play, then reopen build/test.rbxl")`.
`hubPlaceId == 0` keeps the C0 behaviour (stay + toast).

`RunRegistry`: Studio is no longer a no-op. It uses the real MemoryStore unless
`DataService.IsMockMode()`, in which case a module-level table with the same TTL semantics
(expiry checked on read) stands in, so Local Server tests in one Studio still see their own run.
When `StudioBridge.RegistryShouldFail()` every call raises inside the pcall body, so the retry
backoff and warns are exercised. The hub's `SendRunList` reads through the same module (it
already does; keep it so).

## Combat core (A)

### Arena — `src/shared/Layouts/Arenas/Village.luau`

```luau
export type ArenaLayout = {
	size: { x: number, z: number },            -- floor, studs; origin at the centre, floor top at y = 0
	floor: { material: string, color: { number } },   -- Enum.Material name, RGB 0–255
	wall: { height: number, material: string, color: { number } }?,   -- nil = open edges
	lobbyPad: { x: number, z: number },        -- C0's pad moves here (6×6 as today)
	playerSpawns: { { x: number, z: number } },   -- ≥ 4, used round-robin
	enemySpawns: { { x: number, z: number } },    -- ≥ 8 on the rim, used round-robin per spawn
	obstacles: { { x: number, z: number, sx: number, sy: number, sz: number, material: string, color: { number } } },
}
```
Village: 110 × 110 Grass floor, 4-stud wooden fence, 8 rim spawns, a handful of rock/log
obstacles (plain Parts, `CanCollide` true so they block movement; enemies walk with `MoveTo`,
no pathfinding, so obstacles stay small and off the spawn lines). `ArenaService.Init` builds all
of it under `Workspace/Arena` (floor, walls, obstacles, `LobbyPad`); `Workspace/Enemies` is the
enemy folder. Missing layout module → C0's bare pad (the run still works).

### Types (A adds to `Types.luau`)

```luau
export type EnemyState = "idle" | "chasing" | "attacking" | "stunned" | "dead"
export type RunPhase = "lobby" | "wave" | "breather" | "boss" | "summary" | "ended"   -- as C0
export type PartyMember = { userId: number, name: string, hp: number, maxHp: number, ready: boolean,
	alive: boolean, bot: boolean, abilityReadyIn: { melee: number, ranged: number }, stance: "melee" | "ranged" }
export type RunState = { kind: "run", phase: RunPhase, missionId: string, overdrive: boolean,
	wave: number, waves: number, alive: number, remaining: number,   -- remaining = still to spawn this wave
	tempo: number, merged: boolean,                                     -- merged: this wave started as "Waves N + N+1"
	party: { PartyMember }, breatherEndsIn: number?, runEndsIn: number,
	boss: { name: string, hp: number, maxHp: number }?, summary: RunSummary? }
export type CombatFx =
	{ kind: "hit", enemyId: number, amount: number, finisher: boolean, position: Vector3, byUserId: number }
	| { kind: "kill", enemyId: number, position: Vector3, cash: number, materials: number, byUserId: number }
	| { kind: "playerHit", userId: number, amount: number }
	| { kind: "ability", userId: number, key: string, slot: "melee" | "ranged", position: Vector3, radius: number? }
	| { kind: "wave", wave: number, merged: boolean, boss: boolean }
	| { kind: "bossDown", name: string, valor: number }
	| { kind: "playerDown", userId: number, respawnIn: number? }
	| { kind: "refused", reason: "cooldown" | "dead" | "lobby" }
```
`RunSummary` (C0) gains `bestWave: number` and `died: boolean`.

### Enemy models (`EnemyService`)

`EnemyService.Spawn(key, stats, isBoss, spawnIndex): Enemy` builds the rig from
`ServerStorage/Enemies/<eraName>/<template>` when present, else a **placeholder**:
`Players:CreateHumanoidModelFromDescription(HumanoidDescription.new(), Enum.HumanoidRigType.R15)`
in pcall (failure → a 4-part block rig built in code), all BaseParts recoloured per key (Raider
rust, Archer olive, Brute/bosses dark red), scaled by `enemy.eliteScale` / `enemy.bossScale`
via `Humanoid` scale values. Model attributes the client reads: `EnemyId` (number, 1-based
per run), `EnemyKey`, `DisplayName` (template name, "Raider Chief" for bosses), `IsBoss`,
`Elite`, `Attacking` (true during the windup), `Dead` (set true `player.corpseSeconds` before
`Destroy`). `Humanoid.MaxHealth/Health` = server HP (health replicates for free;
`HealthDisplayDistance = 0`, `NameDisplayDistance = 0`, `BreakJointsOnDeath = false`),
`WalkSpeed = speed`, root `SetNetworkOwner(nil)`. Enemies never damage Humanoids through Roblox
touch/physics: **all damage in both directions goes through `CombatService`**. Enemy AI ticks
at `enemy.tickHz`: target = nearest alive party member (players and bots) within
`enemy.aggroRange`, re-picked every `enemy.retargetSeconds`; melee walks (`MoveTo`) until
`distance ≤ reach` then attacks every `attackCooldown` with an `enemy.attackWindupSeconds` tell;
ranged stops at `reach` and fires a server raycast at the target every `attackCooldown`, damage
only on a hit. `stunUntil` freezes movement and attacks. Server-side procedural motion: a small
Motor6D `C0` tween on the arms during the windup and a walk bob, so every client sees it (Roblox
replicates server-set joints); `Combat.json animations.*` ids, when non-zero, play through an
`Animator` instead.

### Waves (`WaveService`)

Run lifecycle, all on the server clock, one run per server:
1. **lobby** → starts when every admitted, non-bot member is Ready (`ArenaService.SetReady`);
   `WaveService.Start()`.
2. Per wave `w`: `spec = Combat.WaveSpec(mission, w, partySize, overdrive, cfg)`,
   `order = Combat.WaveComposition(spec.count, spec.weights)` (+1 elite when `tempo ≥ eliteTempo`
   and the composition has an `elite = true` key; boss waves prepend `bosses[w]` with
   `EnemyStats(…, isBoss = true)`); spawns are trickled every
   `Combat.SpawnInterval(mission, spec, tempo, overdrive, cfg)` seconds at the next rim spawn,
   never exceeding `director.maxAlive` alive; `partySize` counts players and bots.
3. Tempo: `Combat.Tempo(killsInLastWindow, windowSeconds, spec.count / targetWaveSeconds, director)`,
   but `1.0` until `director.tempoWarmupSeconds` have elapsed in the run.
4. **Merge:** once the wave has finished spawning, if `Combat.ShouldMerge(tempo, deadFraction, director)`,
   wave `w + 1` starts spawning immediately (`merged = true`, banner "Waves w + w+1");
   otherwise the wave ends when all its enemies are dead → **breather** of
   `Combat.BreatherSeconds(tempo, director)` with `player.breatherRegenPerSecond` HP regen.
5. Boss waves show phase `boss` while the boss lives (`RunState.boss` filled).
6. **Rewards** are credited per kill to the wave pool (`cash`, `materials`, `valor` from
   `EnemyStats`/`BossValor`, kills) with per-user damage tracked; **at every wave clear** the
   pool is split with `Combat.ContributionShares(damageByUser, coop.contributionFloor)` and
   flushed to each player's profile via `Combat.SplitPool`: `cash += floor(cash × share × Combat.CombatCashMult(state, gameCfg, shopCfg))`,
   `materials[mission.material] += floor(materials × share)`, `valor += floor(valor × share)`,
   `stats.kills/wavesCleared/cashFromCombat`, `missions[id].bestWave = max`, `bossClears`.
   Bots' shares are discarded. After each flush the player gets a fresh `StateChanged`
   Snapshot so the HUD wallet is current. Nothing else in `src/combat` writes the profile.
7. **End:** all waves cleared, `director.runCapSeconds` elapsed, or every non-bot member dead
   → phase `summary` (per-player `RunState` with that player's `RunSummary`, `FireClient`),
   `RunRegistry.Clear(host)`; the Return button (`RequestLeave`) works from any phase.
8. Death: a dead player respawns at a player spawn after `player.respawnSeconds` if any other
   member is alive; otherwise the run ends (rewards kept). `Humanoid.MaxHealth` is re-applied
   from `Armory.MaxHp` on every spawn.

`RunState` broadcasts at `remotes.combatStateHz` and immediately on phase changes.
`CombatFx` are batched per Heartbeat frame into one `FireAllClients(list)`.
`WaveService` exposes `Start()`, `GetPhase()`, `GetWave()`, `EndRun(reason)`, `ForceWave(n)`,
`SpawnOne(key)`, `KillAll()`; `ArenaService` keeps `Admit/Remove/SetReady/BuildRunState/Broadcast`
and gains `GetMembers(): { PartyMember }`, `AddBot(i)`, `RemoveBot(i)`, `GetSummary(userId): RunSummary`.

### Hits (`CombatService`)

- **Melee** `RequestAttack(swingSeq, targetIds)`: per player `{ step, lastSwingAt, seq }`.
  `swingSeq ≤ seq` → drop. Elapsed since last swing `< windows[step] × player.comboTimingTolerance`
  → drop with `refused cooldown`. Elapsed `> comboReset` → step 1, else step + 1 (wraps to 1
  after 3). Damage `Combat.MeleeDamage(armoryCfg, state, step)`; each target: exists, alive,
  distance from the attacker's root ≤ `class.range + player.hitDistancePad`, angle from the
  root's look vector ≤ `arcDegrees / 2`. Step 3 is a **finisher** only if steps 1–2 landed
  inside their windows on the server clock; a finisher also applies `finisherKnockback` as a
  root velocity away from the attacker.
- **Ranged** new intent `RequestFire(seq, origin: Vector3, direction: Vector3, charge: number)`
  (bucket `attack`; validator: finite vectors, `charge` in [0, 1]). Origin within
  `player.hitDistancePad` of the shooter's head; elapsed since last shot ≥ `class.cooldown ×
  comboTimingTolerance`; for `fire == "charge"` the server clamps `charge ≤ elapsed / chargeSeconds`.
  `Workspace:Raycast(origin, direction.Unit × range)` filtering party characters; hit enemy →
  `Combat.RangedDamage(armoryCfg, state, charge)`; `pierce` continues the ray past up to `pierce`
  enemies. No hit = miss, silently. Spread and aim assist are client-only.
- **Abilities** `RequestAbility(slot)` (validator becomes `args.n == 1`, slot ∈ melee/ranged).
  Cooldown per slot on the server clock (`abilityReadyAt`); every kill by that player refunds
  `player.killCooldownRefundSeconds` on both. `aoe`: all enemies within `radius` of the root
  (or the nearest `shots` when set) take `Combat.AbilityDamage(armoryCfg, state, slot)`;
  `knockback` → velocity away; `stunSeconds` → `stunUntil`; `dotSeconds/dotTicks` → damage
  spread over ticks. `burst`: `dashStuds` → damage every enemy within `player.dashHitRadius`
  of the segment root → root + look × dashStuds (the client performs the dash visually);
  otherwise the nearest `shots or 1` enemies inside `class.range` and a
  `player.burstConeDegrees` cone (`pierce` lets one shot continue through that many).
- Player damage: `CombatService.DamagePlayer(member, amount)`; god mode (debug) zeroes it.
  Every enemy damage call records `damageByUser[enemyId][userId]`; the kill goes to the last hitter.

### Pure additions (`Combat.luau`, A; mirrored by `sim_combat.py`)

```luau
Combat.WaveComposition(count, weights): { string }
   -- quota_k = count × w_k / Σw; n_k = floor(quota_k); leftover to the largest fractions (ties: key name asc);
   -- order: count picks, each time the key with the smallest placed_k / n_k (ties: key name asc). No RNG.
Combat.SpawnInterval(mission, spec, tempo, overdrive, cfg): number   -- targetWaveSeconds / spec.count / tempo / (overdrive and spawnRateMult or 1)
Combat.BreatherSeconds(tempo, director): number   -- breatherSeconds + (breatherMaxSeconds − breatherSeconds) × clamp((1 − tempo) / (1 − tempoMin), 0, 1)
Combat.ShouldMerge(tempo, deadFraction, director): boolean            -- tempo ≥ mergeTempo and deadFraction ≥ mergeThreshold
Combat.MeleeDamage(armoryCfg, state, step): number                    -- Armory.WeaponDamage(melee) × class.chain[step]
Combat.RangedDamage(armoryCfg, state, charge): number                 -- WeaponDamage(ranged) × (charge class: minDamageFraction + (1 − minDamageFraction) × charge; else 1)
Combat.AbilityDamage(armoryCfg, state, slot): number                  -- WeaponDamage(slot) × ability.damageMult × ascension.levels[level].abilityMult (1 at 0)
Combat.AbilityCooldown(armoryCfg, state, slot): number                -- ability.cooldown
Combat.SplitPool(pool, shares): { [userId]: { cash, materials, valor } }   -- floors, as in Waves §6
```

### Debug levers (`DebugService`, A; names in `Combat.json debug`, Studio only)

Attributes on Workspace, consumed on the C0 1 Hz tick, **and** the intent `RequestDebug(lever, value)`
(added to `CombatRemotes`, bucket `calls`, same validator as the hub's) whose handler applies the
same table; outside Studio the handler returns. Levers: `wave` (number → the next wave to start
is N; in lobby, the run starts at N), `spawn` (enemy key → one now, at the next rim spawn),
`godMode` (boolean, per player for the remote, all players for the attribute), `killAll`
(≥ 1 → every alive enemy dies with normal rewards), `setGear` (string `"melee=3,ranged=2"` →
profile gear set, HP re-applied; the tier must exist), `bots` (number → that many bots),
`grantMaterials`, `grantValor` (as C0). **Bots**: `DebugService.SetBots(n)` keeps n server
rigs (placeholder rig, blue), fake userIds −1000 − i, names "Bot i", `PartyMember.bot = true`,
HP `debug.botHp`, always Ready, walk toward the nearest enemy and deal `debug.botDamagePerSecond`
in 0.5 s ticks within 8 studs through `CombatService`; enemies target them; they respawn like
players. They exist so party scaling, shares and aggro can be seen from one client.

## Combat client (ui-engineer A, `src/combat/client`)

- **`InputController`** (new): a **stance** toggle (melee/ranged; keys `1`/`2`, HUD button).
  Melee: tap/click → `RequestAttack(seq, ids)` with the enemy ids the client sees inside the
  class arc (hint only). Ranged: `bow`/charge classes hold-to-draw (charge = held / chargeSeconds),
  `semi` one shot per tap, `auto` fires while held at `cooldown`, `beam` semi with a visible
  beam; all → `RequestFire(seq, origin = head, direction, charge)`. Touch: soft-lock on the
  nearest enemy inside a `player.aimAssistDegrees` camera cone; PC: mouse direction with the
  same assist. Abilities: two HUD buttons with cooldown rings (`Q`/`E`), → `RequestAbility(slot)`;
  a local dash for `dashStuds` burst abilities. Never send damage.
- **`WeaponController`** (new): attaches `ReplicatedStorage/Assets/Props/<eraName>/<model>` to
  the right hand when present, else nothing (empty hands are the C1 default); procedural
  Motor6D `C0` swing/draw poses on the local character timed to `class.windows`; other
  players' swings are not animated in C1 (report as follow-up).
- **`CombatFxController`** (new): consumes `CombatFx` batches — floating damage numbers
  (finisher larger), `Highlight` flash, hitstop as a `feedback.hitstopSeconds` local freeze of
  the enemy's visual (not physics), camera kick `feedback.cameraKickDegrees`, client-only
  knockback nudge, death dissolve on `Dead` (transparency tween over `player.corpseSeconds`),
  wave / merged / boss banners (`feedback.bannerSeconds`), low-HP vignette below
  `feedback.lowHpFraction`, enemy attack tell from the `Attacking` attribute. Copy `floatText`
  / `flashHighlight` / `burst` from `PlotVisualsController.luau` (:497 / :546 / :357) and
  report the dedupe. Reduced motion: honour the hub `settings` the same way `PlotVisuals` does.
- **`CombatHud`**: wave line ("Wave 3 / 10", "Waves 4 + 5", "Boss — Raider Chief" + boss bar),
  alive/remaining, tempo dot, wallet strip (cash, mission material, Valor from the Snapshot),
  party rows with alive/down state, stance and ability buttons, run timer.
- **`SummaryCard`**: waves cleared, best wave, cash, materials, Valor, kills, time, "died"
  line; Return → `RequestLeave`.
- **`DebugPanel`** (new, `RunService:IsStudio()` only): collapsible strip of buttons for every
  `RequestDebug` lever (Wave +1, Spawn raider/archer/brute, God, Kill all, Gear +1 melee /
  ranged, Bots +1/−1, Grant 25 material, Grant 10 Valor).
- Sounds: new `Sounds.json` keys (below) through the copied `SoundController`; id 0 = silent.
- Layout checked at 375×667 and 812×375. Touch first: attack button bottom-right, abilities
  beside it, stance toggle above; PC uses the same HUD with keys.

## Hub client (ui-engineer B)

- `ExpeditionSummaryCard.new(screenGui, { onClose })` shown on the new `ExpeditionSummary`
  event: mission name, waves cleared / best wave, cash, materials, Valor, kills, time.
- `DebugPanel.new(screenGui, { onLever(lever, value) })`, Studio only: Grant cash 10K, Grant
  25 Timber, Grant 10 Valor, Fake runs ×3, Force teleport failure (toggle); `UIController` wires
  it to `RequestDebug`. The Expedition panel's Depart handler shows "Handoff saved — Stop Play,
  then open build/combat.rbxl" from the `ActionResult` in Studio (the kick follows 1 s later).

## Config keys (lead-applied; values are economy-designer's)

`Combat.json`: `player` gains `comboTimingTolerance, aimAssistDegrees, corpseSeconds,
dashHitRadius, burstConeDegrees`; `director` gains `tempoWarmupSeconds`; new `enemy{ tickHz,
aggroRange, retargetSeconds, attackWindupSeconds, eliteScale, bossScale }`; new `feedback{
hitstopSeconds, cameraKickDegrees, damageNumberSeconds, bannerSeconds, lowHpFraction }`; `debug`
gains `waveAttribute, spawnAttribute, godModeAttribute, killAllAttribute, setGearAttribute,
botsAttribute, fakeRunsAttribute, forceTeleportFailureAttribute, forceRegistryFailureAttribute,
handoffStoreName, handoffMaxAgeSeconds, botHp, botDamagePerSecond`. `remotes.attackCallsPerSecond`
rises to 12 (the machine gun fires at 10/s). `Sounds.json sounds` gains `swing, finisher, bowDraw,
bowFire, gunFire, laser, abilityCast, enemyHit, enemyDeath, playerHit, playerDown, waveStart,
waveClear, bossStart, bossDown, runEnd, lowHp` (id 0 until uploaded; `SoundController` skips 0).

## `tools/sim_combat.py` (economy-designer)

Mirror every new pure function above (same names in snake_case). Replace assertion 3's DPS
model with a **run simulator** that plays the director: composition, trickle spawns, tempo,
merges, breathers, boss waves, the player's DPS from the melee chain/windows and ranged
cooldown with hit rates 0.7 / 0.5 and an ability cast whenever ready, damage taken from enemies
in reach, breather regen. `--trace` prints the wave timeline. Assertions (`--check`, exit 1 on any):
1–2, 4–6 as C0; 3. recommended power clears 10 waves inside `targetMinutes` ±50 %;
7. 2 × recommended power triggers ≥ 1 merge; 8. 0.6 × recommended dies at wave 6 ± 2;
9. `WaveComposition` returns exactly `count` keys and matches the weights within 1 per key;
10. Overdrive at recommended × 3 cash ≥ 3 × the normal run. `docs/BALANCE.md` "C1": the wave
timeline at recommended power, kill counts per key, run cash vs era cost.

## Definition of done (C1)

- Both builds, both sourcemaps, `luau-lsp analyze`, stylua, selene, `sim_economy.py --check`
  unchanged, `sim_combat.py --check` green (10 assertions), manifest/template checks green.
- Studio, hub (`build/test.rbxl`, API access on): Depart on Raider Woods → toast "Handoff
  saved…" → kicked after 1 s; `ForceTeleportFailure` instead re-admits with `unavailable` and
  clears the handoff; `DebugFakeRuns` fills the ACTIVE RUNS list; Join on a fake → `unavailable`.
- Studio, combat (`build/combat.rbxl`): boots from the handoff (mission and Overdrive from the
  record, record consumed), else from `DebugMission`; Ready → wave 1 spawns 5 raiders that chase
  and hit; melee combo, bow draw, Volley and Whirlwind all deal server-validated damage; wave
  clears flush cash/Timber to the profile (wallet strip updates); boss at wave 5 and 10; run
  ends on death (rewards kept) or wave 10 with the summary; Return writes the return record and
  kicks; reopening the hub shows the `ExpeditionSummaryCard` with the same numbers.
- `DebugBots = 2` adds two rows, scales wave count, and the summary shows only the player's share.
- Every lever works from both the attribute and the `DebugPanel`; none does anything outside Studio.
- No enemy or weapon model is required: placeholder rigs and empty hands are the shipped default.
