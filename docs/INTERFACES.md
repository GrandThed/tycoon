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

## Wave 2b — Orbital Colony dressing (Ben, 2026-09-23)

Orbital reuses the Metropolis machinery: the **tile renderer** (with generated tube props), the
**Highway module in loop mode** (monorail), **paved blocks** (decking), tree zones (rocks). Ben's
choices: **enclosed corridor tubes** as the walkways, **only the monorail train** moves (no ground
vehicles), **decking pads under module clusters + rocks/craters** on the open regolith.

### Layout — relaid on the Metropolis lattice
`src/shared/Layouts/OrbitalColony.luau` is **re-authored** (positions are not persisted): the 16
building slots on the 4×4 block grid at x,z ∈ {±14, ±42} (12×12 slots keep the contract's
footprint rules), the monument `launchTower` on the x = 0 axis, unlock/decor slots on corridor
edges as Metropolis did; `streets` (tube runs) on the 7-stud lattice, axis-aligned, a tree;
`blocks` (decking rects, to the plot edge under the monorail band), `treeZones` (rock fields on the
open regolith), 6–10 `lots` (small domes), 1 plaza, `highway = { ring = 56 }` with **no `ramp`**
(loop mode), no `subwayEntrances`. `tools/streetplan.py` gains OrbitalColony in `DEFAULT_ERAS`
and must be green; the tree-budget gate counts rocks.

### Tubes (`road.tiles`, generated `tube-kit`)
- Props `TubeStraight / TubeEnd / TubeBend / TubeTee / TubeCross` (no `crossing`), one per cell,
  same canonical orientations as the Metropolis tiles (straight along X, end open +X, bend −X↔+Z,
  tee closed −Z), pitch 7, from a committed generator `tools/assets/tube_kit.py` (space-kit
  palette): a pressurised glass corridor **4 studs wide × ~4.5 tall** on a 7-long decking strip,
  white frames, light-blue "glass" (opaque colour, no transparency), an airlock cap on `TubeEnd`,
  ≤ 400 tris per piece. Tubes stand on the regolith/decking; there is **no pavement band**
  (`pavement` absent) and **no park strips** (`parkStrips` absent — an undrawn arm is simply a
  capped tube end, which reads fine).
- `road.width` 4; spurs are Metal decking strips (`tiles.spur`) from the tube to the module door.
- Tubes are dressing: no collisions, characters walk through them like trees.

### Monorail (`highway` in loop mode)
- `walkwayNetwork` keeps its id and cost, becomes `streetOnly`, is renamed **"Build the Monorail"**.
- Config `eras.OrbitalColony.highway`: `props` has only `deck` (`MonorailTrack`, straight beam +
  pier, runs along X) and `corner` (`MonorailCorner`, −X↔+Z); **`junction` and `ramp` are optional
  in the type**; `vehicleProps: ["MonorailTrain"]` (new optional key, default = era `vehicles.props`),
  `vehicles.count` 1, `deckHeight` 7.07 (train wheel plane), soffit ≥ 6.0 so characters pass under.
  Generated `tools/assets/monorail_kit.py` (space-kit palette; space-kit's own monorail pieces are
  not pitch-7 and stay unused): track straight 7 long, corner, pier; train = one prop, ≤ 8 studs
  long, origin bottom-centre at the wheel plane, nose −Z like every vehicle.
- Client `Highway`: when `layout.highway.ramp` is nil, build the plain loop (no junction/ramp),
  reveal outward both ways from the loop cell nearest the plot entrance; vehicles = `vehicleProps`.
  Far plots: track only.

### Decking, rocks, domes, lights
- `road.tiles.blocks`: Metal decking (96,98,108) with **`treeSpacing` 0 = no edge trees** (new rule,
  any era).
- `trees`: `prop: "Rocks"` — a 4-stage prop (S0 pebbles → S3 crystal outcrop) so the existing
  stage-by-tier growth reads as a rock garden filling in; `maxCount` 30; zones on the open regolith.
- `houses.props ["HouseA","HouseB"]` = small orbital-kit domes on `lots`; `plazas.props ["PlazaA"]`
  = an observation platform; `lamps.prop "LampPost"` = light panel on a mast (tier/junction rule).
- `vehicles.props []`, `perPlot` 0 — nothing drives; `cityDetail`'s vehicle rule is moot here.

### `cityDetail` (contract below, amended)
Profile schema goes to the **next version** (combat already took v5); everything else as written.

### Ownership (wave 2b)
- lead: this section, `Types.luau`, `CityDressing.json`.
- economy-designer: `Layouts/OrbitalColony.luau`, `Eras/4_OrbitalColony.json`, `tools/streetplan.py`.
- luau-engineer: `ProfileSchema`/`DataService` migration, `RemoteService` validator, settings delta.
- ui-engineer: `src/client/City/*` (Highway loop mode, `treeSpacing` 0, no-pavement tiles path),
  `CityDressingController` (cityDetail live re-evaluation), `UI/SettingsPanel.luau` row.
- prop-builders: A `tube_kit.py` + Tube props; B `monorail_kit.py` + track/corner/train; C Rocks
  S0–S3, HouseA/B, PlazaA, LampPost (`_props/OrbitalColony/`). Renders on the (56,53,60) base.
- plotrender: OrbitalColony renders (tube tiles, loop, decking, rocks).

### Done when
Fresh Orbital plot: bare regolith (nothing drawn); each module grows the tube network with correct
ends/bends/tees/crosses and a decking spur; decking appears under a block with its first module;
rocks fill the zones by tier; Build the Monorail spawns no building and the loop builds out with
one train circling at 7.07; domes and the platform appear by tier; `cityDetail` off halves rocks,
removes lamps, keeps the train on the local plot only, live; other eras unchanged;
`streetplan.py` green for all four eras.

## Wave 2 — `cityDetail` setting (after wave 1 is in Studio)

Same pattern as the VIP-skins amendment: `settings.cityDetail: boolean`, default `true`;
`Types.SettingKey` gains `"cityDetail"`; profile schema v6 (combat took v5) with an additive migration;
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
  props: {string}, clearance }`. Walk lanes are **clipped at every solid on their line** (lots,
  plazas, kiosks, lamp posts, signals, slot footprints, pads) with `clearance`; a clip end is a dead
  end, so no walker ever enters a building (review, 2026-09-23). Offsets: Metropolis on the pavement (road half-width + pavement/2 ≈ 5.5),
  Boomtown on the asphalt edge (≈ 3.4; 4.8 was the row-lamp line), Village at the trail edge (≈ 1.3, clear of the carts at 0).
- `budget.walkersPerPlot` = **8**, `budget.walkersMap` = **24**; walkers run on the same nearest
  `lod.vehiclePlots` plots as cars.
- Props: generated **`people-kit`** (`tools/assets/people_kit.py`, Blender, 1 unit = 1 stud):
  chunky flat-shaded toy figures, one merged MeshPart each, **≈ 1.6–2.0 studs tall** (under a kit
  door), era outfits via colour factors: `WalkerA–D` per era (Village smocks/aprons, Boomtown
  casual, Metropolis suits). Motion = walk along the lane + vertical bob; no rig, no animation IDs.

### Ambient (smoke, birds)
- New module `src/client/City/Ambient.luau`, one Heartbeat only while something is live.
- `ambient.smoke = { firstTier, eras: {string}, props: { [propName]: {number} }, rate, lifetime,
  size: {number}, color: {number} }`. `props` maps `"<Era>/<Prop>"` (or a bare prop name) to a chimney offset
  `[x, y, z]` in the prop frame; a placed house of that prop gets one ParticleEmitter there
  (`smoke_main.dds`, like Dust). Village and Boomtown only.
- `ambient.birds = { firstTier, eras: {string}, flocksPerTier: {number}, birdsPerFlock, radius,
  height, speed, prop }`; a missing `eras` list means no birds. A flock circles over a `treeZones` centre with seeded phase; birds are a generated
  `Bird` prop (people-kit) in each era's `_props`. All three eras (Metropolis = pigeons, grey).
- `budget.birdsMap` = **18**; near plots only.

### Budget and LOD
- New near-plot maximum per plot: lots ≤ 45 filler, greenery 48, parked 16, walkers 8, birds 6.
  Far plots keep lots and houses (they are city silhouette) and drop greenery, parked, walkers,
  smoke and birds. The PLAN target is re-cut from measurement in the playtest; the step for
  Traffic + Walkers + Ambient together must stay **< 0.3 ms** with every map cap reached.
- **`cityDetail` (wave 2b, lands on main first):** when false, wave 2c also halves greenery and
  drops parked vehicles, walkers, smoke and birds (lots stay). Wired at merge in `detailPolicy`
  (`greeneryShare` = `detail.treeShare`, even thinning by plan index; `living` false).

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

## Wave 2d — small cars, dense traffic (Ben, 2026-09-23)

Ben, after the wave 2c playtest: "make the cars 50% smaller and place 300% more cars". Rulings:
Boomtown **and** Metropolis; moving cars ×4, parked cars ×2 (two per existing bay, no layout
change). Client + config only, **no re-upload**: the scale is applied at runtime.

- Per era, optional: `vehicles.scale`, `parked.scale`, `pedestrians.scale` (default 1). A
  spawned vehicle/walker template is scaled with `Model:ScaleTo(scale)` about its base pivot
  before it is placed, so it stays on the ground. Everything that reads a vehicle's harvested
  extents (lane spacing, bay packing, clearance) multiplies by the same scale. Metropolis deck
  cars (`Highway`, `highway.vehicleProps` else `vehicles.props`) use `vehicles.scale` too.
- Boomtown and Metropolis: `vehicles.scale` 0.5, `parked.scale` 0.5; `pedestrians.scale` 1.
- `parked.perBay` (default 1): cars per bay, packed end to end along the bay's long axis, centred,
  with `parked.gap` (default 0.3) between them, using scaled harvested lengths; a bay whose cars do
  not fit keeps one car. Boomtown and Metropolis: 2. `perTier` still counts bays.
  `parked.bayLength` (default: the full-size parked footprint length) is the packing length;
  Boomtown 7.5, Metropolis 6.0 (the layout's bays), so every two-car combination fits.
- Counts: `vehicles.perPlot` Boomtown 6 → 24, Metropolis 8 → 32; `budget.vehiclesPerPlot` 8 → 32,
  `budget.vehiclesMap` 24 → 96, `budget.parked` 16 → 32. Traffic, Walkers and Ambient together must
  still stay **< 0.3 ms** per frame with every map cap reached (PLAYTEST).
- Village carts, Orbital rovers/monorail and every other prop are unchanged.


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

---

# C2 contracts — Co-op: party, join-in-progress, contribution, Mentor (Ben, 2026-09-23)

The game is published (both place ids live in `Places.json`), so C2 is verified **twice**: the
Studio bridge + debug levers for every path, and a published round trip with two accounts.
Ben's rulings (2026-09-23):

1. **Boss HP scales with party size**: `× (1 + coop.bossHpPerExtraPlayer × (partySize − 1))`,
   0.75 to start. Regular enemies still scale by count only; tempo still never touches HP/damage.
2. **The run list shows runs in this hub server, friends' runs, and public runs from any
   server.** A host can make a run friends-only with the "Open to public" toggle (default
   `coop.publicByDefault` = true). Private runs are visible only to friends and same-server players.
3. **Hub party = invite + accept** among players in the same hub server. The leader picks the
   mission; Depart sends the whole party to one reserved server in ONE `TeleportAsync`.
4. **Missions are host-gated.** A guest may fight any mission its host unlocked (the design's
   "the newbie still brings home Steel"). The gate is enforced through the server-only
   `RunTicket`, never through teleport data.
5. Nothing new is persisted: **no schema change** (ProfileSchema stays v6). The hub party lives in
   memory only and re-forms after the group return from agreeing teleport hints.

Lead-applied before fan-out (do not redo): the five UI copies + `SoundController` copy in
`src/combat/client` are deleted and `combat.project.json` maps the hub originals into the combat
client (`Client/UI/{Create,Motion,Toast,LoadScreen,Theme}`, `Client/Controllers/SoundController`);
the combat Theme block moved verbatim into `src/client/UI/Theme.luau`. All `Types.luau` additions
below, and the new `Combat.json` / `Armory.json` / `Missions/1_Village.json` keys, are in.

## Ownership (one wave, disjoint)

| Owner | Files |
|-------|-------|
| lead | this section, `Types.luau`, config keys (applied), `combat.project.json` (applied), routing |
| luau-engineer **A** (combat server) | `src/combat/server/**` (Main, ArenaService, WaveService, CombatService, EnemyService, DebugService, CombatRemotes, ReturnService, RunRegistry), `src/shared/Combat.luau` |
| luau-engineer **B** (hub server) | `src/server/Services/{PartyService (new), ExpeditionService, HubRemotes, StudioBridge, ArmoryService}.luau`, `src/server/Main.server.luau` |
| ui-engineer **A** (combat client) | `src/combat/client/**` |
| ui-engineer **B** (hub client) | `src/client/UI/**` (incl. the now-shared `Theme.luau`), `src/client/Controllers/UIController.luau`, new `src/client/UI/PartyInviteToast.luau` |
| economy-designer | values of `Combat.json coop.*`, `Armory.json partyEffects` + `partyEffect` tier keys (keys frozen), `tools/sim_combat.py`, `docs/BALANCE.md` "C2" |
| roblox-reviewer → qa-runner → docs-keeper | after wave 1 |

A calls B's `StudioBridge` by the API below; B's `ExpeditionService` writes the `RunTicket` A's
`RunRegistry` reads. **`Theme.luau` is shared by both clients:** ui-engineer B owns it; ui-engineer
A may only add constants inside a block headed `-- C2 combat client` placed directly after the
"C0 combat place" block, and must re-read the file before each edit. Nobody touches
`src/client/City/**` or `src/client/Controllers/{CityDressingController,PlotVisualsController}`
(another session, M9 wave 2d, owns them). Frozen: everything frozen at C1, `Economy.luau`,
`Catalog.luau`, `Armory.luau`, `ProfileSchema`, `DataService`, `EconomyService`, `RemoteService`.

## Types (applied, `src/shared/Types.luau`)

`ActionResult.action` + `"party"`; `reason` + `"full" | "over" | "busy" | "expired" | "notLeader"`.
`WeaponTierDef.partyEffect: string?`, `PartyEffectDef`, `ArmoryConfig.partyEffects`.
`CombatCoopConfig` + `bossHpPerExtraPlayer, mentorMinDamageShare, inviteSeconds, lobbyWaitSeconds,
returnGroupSeconds, reformSeconds, publicByDefault`. `CombatRegistryConfig` + `listCacheSeconds,
listMax, friendChecksPerCall` (replaces the `MAX_FRIEND_CHECKS_PER_CALL` code constant).
`CombatEnemyConfig` + `defaultColor, bossColor, botColor`; `EnemyDef.color?` (replaces the colour
constants in `EnemyService` and `ArenaService.BOT_COLOR`). `CombatDebugConfig` + `botIncomeRate,
fakePartyAttribute, fakeInviteAttribute`. `PartyMember` + `host, waiting, damageShare`.
`RunMember` + `waiting, incomeRate, drawStartedAt, empoweredUntil, empowerMult`. `RunSummary` +
`mentorValor, damageShare`. `RunState` + `returnIn?`. `CombatFx` + `swing`, `partyEffect`,
`mentor`; `refused.reason` + `"waiting"`. `ActiveRun` + `public, memberIds`. New: `RunTicket`
(with `privateServerId`), `RunRelation`, `RunListEntry`, `HubPartyMember`, `HubPartyInvite`,
`HubParty`, `PartyInviteEvent`, `PartyHint`, `ReturnData`.

## Remotes

Hub intents (all validated in `HubRemotes`; userIds must be integers ≠ 0, negative only in Studio):

| Remote | Payload | Bucket |
|---|---|---|
| `RequestExpedition` | `(missionId: string, overdrive: boolean, public: boolean)` — **changed** | prompt |
| `RequestPartyInvite` | `(userId: number)` | calls |
| `RequestPartyRespond` | `(leaderUserId: number, accept: boolean)` | calls |
| `RequestPartyLeave` | `()` | calls |
| `RequestPartyKick` | `(userId: number)` | calls |

Hub events: **`PartyState`** `(party: HubParty?)` to every member (and `nil` to anyone who just
left); **`PartyInvite`** `(PartyInviteEvent)` to the invitee only; `RunList` payload becomes
`{ runs: { RunListEntry } }` (no `ActiveRun` ever reaches a client). `RequestDebug` gains levers
`fakeParty` (number 0–3) and `fakeInvite` (true).

Combat intents: **`RequestDraw`** `()` bucket `attack` — the bow's draw start. `RequestDebug`
gains lever `admitCheck` (true). Combat events unchanged; `CombatFx` gains the three kinds above.

## Hub party (`PartyService`, B, hub only; inert in the combat place)

```luau
PartyService.Invite(leader: Player, userId: number): ()          -- ActionResult{party, tostring(userId), ok, reason}
PartyService.Respond(player: Player, leaderUserId: number, accept: boolean): ()
PartyService.Leave(player: Player): ()
PartyService.Kick(leader: Player, userId: number): ()
PartyService.Get(player: Player): Types.HubParty?
PartyService.Members(player: Player): { Player }                 -- real players only, leader first
PartyService.IsLeader(player: Player): boolean                   -- true when solo too
PartyService.OfferReform(player: Player, hint: Types.PartyHint): ()
PartyService.Forget(player: Player): ()                          -- PlayerRemoving
```

- Invite: sender is solo or the leader (else `notLeader`); target is another player in this
  server (else `invalid`), not in a party and not departing (`busy`), and members + pending <
  `coop.maxParty` (`full`). The invite expires after `coop.inviteSeconds` (`expired` on a late
  accept). Accepting while in another party → `busy`. A solo inviter becomes leader when the first
  invite is accepted; a party that drops to one member dissolves; a leaving leader passes
  leadership to the next member in join order.
- `PartyState` goes to every member after each change; pending invites carry `expiresIn`.
- Studio levers (Workspace attribute `debug.fakePartyAttribute` / `fakeInviteAttribute`, and the
  `RequestDebug` levers): `fakeParty n` gives the player's party n fake members (ids −1…−n,
  names "Fake 1"…), `fakeInvite` sends the player an invite from a fake leader (id −9). Fake
  members are skipped at Depart with a toast; in a fake-led party Depart answers `notLeader`.
  Inert outside `RunService:IsStudio()`.

## Departure, join and the run list (`ExpeditionService`, B)

- **Depart** (`RequestExpedition`): a party member who is not the leader → `notLeader`. The
  mission gate is the **leader's** `MissionUnlocked`. Members not loaded or already departing are
  left behind with `busy`. One `ReserveServer` → `(accessCode, privateServerId)`; the hub writes
  `RunTicket{ accessCode, privateServerId, missionId, overdrive, public, expected = departing
  userIds }` to the existing `ActiveRunsCodes` hash map (key `code_<leaderUserId>`), then for each
  member: stamp, `RefreshPersistedRate`, release; then ONE `TeleportAsync(combatPlaceId, players,
  options)` with the C1 teleport data `{ missionId, overdrive, hostUserId = leader }`. Any failure
  → the C1 recovery for **every** member. Bridge mode: `privateServerId = "studio"`, one
  `WriteDeparture` per member, and every member is kicked.
- **Join** (`RequestJoinRun`): personal. The requester leaves their hub party first. The hub
  pre-filters against the registry snapshot (`full` if `partySize >= maxParty`, `over` if
  `wave > joinUntilWave`) and visibility (public, or a friend, or a member in this server, else
  `unavailable`). **No mission-unlock check for joiners** (host-gated). The combat place re-checks
  everything on arrival.
- **Run list** (`RequestRunList`): one `GetRangeAsync(Ascending, 50)` per hub server per
  `registry.listCacheSeconds`, shared by every requester. Per requester: drop their own run,
  drop runs that are not joinable, tag `relation` (`server` if a `memberIds` entry is in this
  server, else `friend` via cached `IsFriendsWithAsync` capped at `registry.friendChecksPerCall`,
  else `public` if `run.public`, else hidden), order server → friend → public then by wave, cap at
  `registry.listMax`. `DebugFakeRuns` fakes alternate `public` true/false with relation
  `public`/`friend`.
- **Arrival home** (hub `Main.server.luau`): `ReturnData` from `TeleportData` (validated shape)
  or `StudioBridge.ReadReturn`. `summaries[tostring(userId)]` → `ExpeditionSummary` (C1 card);
  `refused` → `ActionResult{ joinRun, "", false, refused }`; `party` → `PartyService.OfferReform`.
  A party re-forms only among members who arrive within `coop.reformSeconds` with **identical**
  hints (same leader, same memberIds); leader = the hint's leader if present, else the first
  arrival. A forged hint can therefore only pull in players whose own hints agree.

## Studio bridge (B)

`WriteReturn(player, data: Types.ReturnData): boolean` and `ReadReturn(player): Types.ReturnData?`
replace the summary-only forms (record `{ kind = "return", data, stamp }`, every field
type-checked on read). Everything else is unchanged.

## Combat place (A)

- **Ticket**: `RunRegistry.ResolveTicket(hostUserId, missionId, overdrive): Types.RunTicket?`
  replaces `ResolveAccessCode`: same read and checks, plus `ticket.privateServerId ==
  game.PrivateServerId` (`"studio"` in bridge mode). No ticket → the run is private, has no
  expected list, and every arrival is unlock-checked as at C1.
- **Admission** — one function `ArenaService.CheckAdmission(player, hint): "ok" | "full" | "over" | "locked"`,
  run for every arrival before `Admit`: `over` if phase is `summary`/`ended`, or the player is not
  in `ticket.expected` and the wave is past `coop.joinUntilWave`; `full` if seats (humans + bots)
  ≥ `coop.maxParty` and the player is not already a member; `locked` if there is no ticket and
  `MissionUnlocked` fails for this player (with a ticket, only the host is checked). Refusal →
  `ReturnService.Refuse(player, reason)` (a `ReturnData` with no summaries and `refused`).
- **Wave boundary entry**: a player (or debug bot) admitted during `wave`/`boss` is `waiting`:
  placed on the LobbyPad, not targetable, takes no damage, attacks refused with `refused
  "waiting"`. A co-op death (another non-waiting human still alive) respawns onto the LobbyPad as
  `waiting`. At each wave boundary (the breather after a cleared wave/merged group, and
  `beginWave`) every waiting member is pivoted to a player spawn at full HP. A death with no other
  fighting human alive is a wipe (C1 rule). Arrivals in `lobby`/`breather` enter immediately.
- **Lobby start**: all humans ready **and** every `ticket.expected` userId admitted, or
  `coop.lobbyWaitSeconds` since the first arrival with all present humans ready.
- **Boss HP**: `Combat.WaveSpec` returns `bossHpMult = 1 + coop.bossHpPerExtraPlayer × extras`
  (same `extras = max(partySize, 1) − 1` it uses for count); `Combat.EnemyStats(..., isBoss =
  true)` multiplies HP by it after the boss and Overdrive multipliers. Non-bosses ignore it.
  `sim_combat.py` mirrors both exactly.
- **Contribution**: `CombatService` keeps a run-wide damage map next to the per-flush tally;
  `PartyMember.damageShare` and `RunSummary.damageShare` are raw shares of it.
- **Mentor bonus**: at the flush of a cleared group that contained a boss, for each human h:
  mentees = other members present (humans and bots) whose raw share of THAT flush's tally ≥
  `coop.mentorMinDamageShare`; `bonus = Combat.MentorBonus(cfg, h.incomeRate, menteeRates)`.
  Pays Valor to h's profile, adds to `summary.valor` and `summary.mentorValor`, and emits
  `CombatFx mentor`. `incomeRate` = the profile's `incomeAtSave` at admit (the hub refreshed it at
  departure); bots use `debug.botIncomeRate` and are never mentors.
- **Party effects**: when a `RequestAbility("melee")` cast succeeds and the caster's melee tier
  has `partyEffect`, apply `Armory.json partyEffects[key]` to every other alive, non-waiting
  member within `radius`: `rally` heals `healFraction × MaxHp` (clamped); `warcry` sets
  `empoweredUntil = now + seconds`, `empowerMult = damageMult`, and every `DealDamage` by an
  empowered member multiplies by it. Emit `CombatFx partyEffect`.
- **Swing replication**: every swing `OnAttack` validates (even with zero targets) queues
  `CombatFx swing{ userId, step }` to every member except the swinger.
- **Bow charge fix**: `RequestDraw` stamps `drawStartedAt` for a `fire == "charge"` class;
  `OnFire` caps charge at `(now − drawStartedAt) / chargeSeconds` only when `drawStartedAt >
  lastShotAt`, else 0; the stamp resets after each shot.
- **Registry**: `ActiveRun.public` from the ticket (false without one), `memberIds` = humans;
  `RunRegistry.Publish` sets the sort key to `wave` while joinable and `1000 + wave` once full or
  past `joinUntilWave`, so an ascending range returns joinable runs first.
- **Group return**: `RunState.returnIn` counts `coop.returnGroupSeconds` down on the summary;
  then `ReturnService.SendHomeGroup(players, reason)` releases every remaining human and sends
  them in ONE `TeleportAsync(hubPlaceId, players, options)` with `ReturnData{ summaries, party =
  { leaderUserId = host if present else first, memberIds } }`. `RequestLeave` before that goes
  home alone (`ReturnData` with only its own summary, no party). Bridge mode: one `WriteReturn` per
  member, then kick each.
- **Colours** from `Combat.json enemy.*Color` and `EnemyDef.color`.
- **Studio lever** `admitCheck` (`RequestDebug`, Studio only) runs `CheckAdmission` for the
  calling player and toasts the verdict without sending anyone home — the same function a real
  arrival runs. Bots added mid-wave wait for the boundary like joiners.

## Combat client (ui-engineer A)

Party rows: ★ for the host, "joins next wave" / "back next wave" when `waiting`, damage share
as a percentage. Local waiting banner "You'll join at the next wave". Other players' `swing` fx
play the procedural combo pose on their characters. `RequestDraw` fires on draw start for charge
weapons. `partyEffect` fx: radius ring at the caster, a pulse on each target, toast "Rally from
<name>" / "War cry from <name>" for the local target. `mentor` fx: "+N Valor · Mentor" on the
local mentor. Summary card: damage share, the Mentor line when `mentorValor > 0`, "Returning
together in Ns" from `returnIn`, plus the existing Return button (goes alone). DebugPanel:
an `admitCheck` button.

## Hub client (ui-engineer B)

`ExpeditionPanel`: a party strip (members with ★ leader, pending invites with countdown, Invite →
picker of other players in the server, Leave, Kick for the leader); non-leaders see mission tiles
disabled with "Your party leader picks the mission"; an "Open to public" toggle beside Overdrive
(default `coop.publicByDefault`) → `RequestExpedition(missionId, overdrive, public)`. Run list
grouped "In this server" / "Friends" / "Open runs" by `relation`; rows show the mission's display
name, host, Wave N, n/max, Overdrive. Empty text "No runs to join right now." New
`PartyInviteToast`: non-blocking, "<leader> invited you to an expedition party", Accept / Decline
(≥ 44 px), auto-dismiss at `expiresIn`. `UIController` wires `PartyState` / `PartyInvite` and the
new refusal copy (full: "That run is full", over: "That run has moved past joining", busy:
"They're already in a party", expired: "That invite expired", notLeader: "Only the party leader
can do that"). Hub `DebugPanel`: `fakeParty` (+1 up to 3, then clear) and `fakeInvite` buttons.

## Balance (economy-designer)

`sim_combat.py` mirrors `bossHpMult` and uses `mentor_bonus` in the run model. New `--check`
assertions: (11) a boss wave at party N ∈ {2, 3, 4}, equal per-player recommended power, lasts
within ±35 % of solo; (12) a 10:1-rate duo at a boss clear pays the mentor exactly
`mentorValor`, an equal-rate duo pays 0; (13) the mentee floor: a member under
`mentorMinDamageShare` earns its mentor nothing. Tune `bossHpPerExtraPlayer`, `partyEffects`
values and `mentorMinDamageShare`; `sim_economy.py --check` unchanged. `docs/BALANCE.md` "C2":
the party table (1–4 players: run time, boss time, per-player cash), Mentor Valor per run.

## Definition of done (C2)

- Both builds, both sourcemaps, `luau-lsp analyze`, stylua, selene, `sim_economy.py --check`
  unchanged, `sim_combat.py --check` green (13 assertions), manifest/template checks green; the
  combat build contains exactly one `Client/UI` and one `Client/Controllers`.
- Studio hub, Local Server with 2 players: invite → toast → Accept → both see the party strip;
  decline, expiry, kick and leave all update both; a non-leader's Depart → "Only the party
  leader…"; the leader's Depart writes a handoff for both and kicks both.
- Studio hub, solo: `fakeParty` / `fakeInvite` drive every party UI state; `DebugFakeRuns` shows
  grouped rows.
- Studio combat: a bot added mid-wave waits on the pad and enters at the boundary; with 3 bots
  `admitCheck` says `full`; at `DebugWave 10` it says `over`; a boss with 2 bots has 2.5× the
  solo HP; bots at income 0 make the player earn the Mentor Valor at wave 5; another Local Server
  player's combo is animated; a bow shot after waiting without a draw is a weak shot.
- Published, two accounts: party Depart lands both in one server; account A's public run is
  joinable by non-friend account B mid-run (B enters at the next wave); a friends-only run is
  hidden from B; after the run both return together and the party re-forms.

---

# M10 contracts — Icons and thumbnails, testfit round (Ben, 2026-09-23)

Offline marketing art rendered in Blender from the shipped blueprints and generated kits, judged by
Ben before anything is uploaded. **No Luau, config or Assets.json change; no Open Cloud upload.**
Requirements are `docs/DISCOVERY_CHECKLIST.md` §1–§2.

## Deliverables (candidates, not finals)

| Kind | Size | Count | Rules |
|---|---|---|---|
| Experience icon | 512×512 PNG | ≥ 6 candidates | one clear subject, saturated sky, strong silhouette, readable at 64 px on a dark tile, no text (or text ≥ ¼ icon height) |
| Thumbnails | 1920×1080 PNG, < 3 MB | ≥ 2 per hook | bottom 15 % free of anything important; hooks Growth, Eras, Scale, Social (combat hook skipped: combat feel pass is parked) |
| Pass icons | 512×512 PNG | ≥ 2 per pass | DoubleCash, OfflinePro, VIP; subject inside the centred circle of diameter 512 (store crops to a circle) |
| Product icons | 512×512 PNG | ≥ 2 per product | Cash30m, Cash2h, Cash8h, DoubleOffline; same circle rule; the three cash tiers must read as small < medium < large |

Only real game content: buildings, props and plots exactly as blueprints/`plotrender` build them.
No fake mechanics, no invented UI, no Roblox logos or third-party characters. Text overlays use one
OFL font (downloaded into `assets/marketing/fonts/`), never a system font baked into a final.

## Ownership (one wave, disjoint)

| Agent | Owns | Output |
|---|---|---|
| icon builder | `tools/marketing/icon.py`, `tools/marketing/icon_scene.py` | `assets/marketing/icon/` |
| thumbnail builder | `tools/marketing/thumbs.py`, `tools/marketing/thumb_scene.py` | `assets/marketing/thumbs/` |
| store-icon builder | `tools/marketing/store_icons.py`, `tools/marketing/store_scene.py`, `tools/assets/coin_kit.py` (if a generated kit is needed) | `assets/marketing/store/` |
| lead | `tools/marketing/README.md` | — |

`tools/testfit/*`, `tools/streetplan.py` and every blueprint are **read-only** (import, never edit).
`/assets/` is gitignored, so the scripts are the committed artifact and the PNGs regenerate.

## Definition of done (M10 testfit round)

Each builder: its PNGs, one labelled `contact_sheet.png` in its output folder (the icon sheet also
shows every candidate at 64 px on (24,24,28)), a one-command rerun line, and a list of what each
candidate is meant to sell. Ben picks; finals, uploads and the Creator Hub steps are the next round.

---

# C2.5 + C3 contracts — Stop 1: combat feel (Ben, 2026-09-23)

Ben's C2 verdict: the flow works but the fight is "pretty outdated and simply bad" — looks, hit
feel, enemy behaviour and controls. He asked for C3 **and** a feel pass, split into three stops:

- **Stop 1 (this section):** camera + controls, impact, enemy AI, animations and sounds, judged on
  Village; in parallel the Boomtown / Metropolis / Orbital mission configs and arena blockouts are
  drafted (placeholder rigs, draft balance).
- **Stop 2:** detailed enemy and weapon models for all four eras + arena dressing.
- **Stop 3:** Overdrive, the Ascension forge UI, full-lap + one-rebirth balance, the C2 reward
  carry-overs (per-head co-op rewards, idle-alt floor).

Rulings (2026-09-23):
1. **Over-the-shoulder camera** on every device. PC: mouse-locked shoulder camera, character faces
   the camera yaw, crosshair at screen centre, click = attack. Touch: Roblox thumbstick on the
   left, drag on the right half to aim the camera, on-screen attack/ability buttons, aim assist
   inside `camera.touchAimAssistDegrees`. Gamepad: left stick move, right stick aim, R2 attack,
   L1/R1 abilities, Y stance.
2. **One evolving horde.** Every mission has the same three roles — melee **grunt**, ranged
   **shooter**, **charger** brute — plus two bosses at waves 5 and 10; each era upgrades their gear
   and numbers. Village keeps its keys (`raider`, `archer`, `brute`); missions 2–4 use `grunt`,
   `shooter`, `brute`. Templates: Village `Raider`/`Archer`/`Brute`/`RaiderChief`/`Warlord`;
   others `<EraName>Grunt`, `<EraName>Shooter`, `<EraName>Brute`, `<EraName>Chief`,
   `<EraName>Warlord` (models are Stop 2; placeholder rigs until then).
3. **Detailed models** (Stop 2, not now).
4. Server authority is unchanged: all damage still goes through `CombatService`; the camera and
   visuals are client-only; aim is still a direction the server raycasts itself.

## Ownership (one wave, disjoint)

| Owner | Files |
|-------|-------|
| lead | this section, `Types.luau` + `Combat.json` keys (applied), audio upload (`tools/upload_audio.py`), routing |
| luau-engineer **A** (combat server) | `src/combat/server/**`, `src/shared/Combat.luau` |
| ui-engineer **A** (combat client) | `src/combat/client/**` incl. new `Controllers/CameraController.luau`, and the combat blocks of `src/client/UI/Theme.luau` |
| economy-designer | values of `Combat.json camera/ai/feel/animations` (keys frozen), `Missions/1_Village.json` (brute → `charger`, boss `patterns`), new `Missions/{2_Boomtown,3_Metropolis,4_OrbitalColony}.json`, new `Layouts/Arenas/{Boomtown,Metropolis,OrbitalColony}.luau`, `tools/sim_combat.py`, `docs/BALANCE.md` "C2.5" |
| sound picker (general-purpose) | `tools/audio_map.json` combat entries only (no upload) |
| roblox-reviewer → qa-runner → docs-keeper | after wave 1 |

Frozen: every hub file, `Types.luau`, `Armory.json`, `Armory.luau`, `ProfileSchema` (no schema
change), `StudioBridge`, remotes (no new remote in Stop 1).

## Types and config (applied)

`CombatConfig` + `camera: CombatCameraConfig`, `ai: CombatAiConfig`, `feel: CombatFeelConfig`;
`CombatAnimationsConfig` + `enemyRun, enemyHit, playerSlash, playerLunge`; `BossDef.patterns?:
{BossPatternDef}`; `EnemyDef.kind` documented as `"melee" | "ranged" | "charger"`;
`CombatFxHit.direction?`; new `CombatFxTelegraph` (`attack: "strike" | "slam" | "charge"`).

Animation ids in `Combat.json` are Roblox's own default R15 animations (idle 507766666, walk
507777826, run 507767714, tool slash 522635514, tool lunge 522638767), **written from memory and
unverified**: every load goes through `pcall` and a failed or 0 id falls back to the procedural
pose silently (one `warn` per id per server/client).

## Combat server (luau-engineer A)

- **Steering** (`EnemyService`, 10 Hz tick, no yields): separation from other enemies within
  `ai.separationRadius`; melee enemies claim one of `ai.maxMeleeAttackers` slots evenly spaced
  around their target at reach distance, the rest circle (strafe at `strafeSpeedMult`) at
  `ai.holdRadius`; shooters keep `[rangedMinDistance, rangedMaxDistance]`, back off or close in,
  and strafe while reloading; when the direct line to the goal is blocked by an arena obstacle use
  `PathfindingService` (pcall, recompute at most every `ai.pathRecomputeSeconds`, per enemy,
  off the tick thread). `MoveTo` targets the steered point, never the player's root.
- **Telegraphs**: every enemy attack emits `CombatFx telegraph` `ai.telegraphSeconds` before the
  damage check (strike), boss slams/charges use their pattern `windupSeconds`. The damage check
  re-reads positions at impact time, so a telegraph is dodgeable.
- **Chargers** (`kind "charger"`, Village `brute`): wind up `ai.chargeWindupSeconds`, dash
  `ai.chargeDistance` at `speed × ai.chargeSpeedMult` along the telegraphed lane; players in the
  lane take the hit once.
- **Bosses**: cycle `patterns` on their own cooldowns alongside the normal attack; `summon`
  spawns through the normal spawn path (counts toward `maxAlive`, pays normal rewards).
- **Reactions**: every hit staggers the enemy `ai.staggerSeconds` (finisher/heavy
  `finisherStaggerSeconds`; bosses half) and sends `CombatFxHit.direction`. Death: the rig
  ragdolls server-side (BallSocketConstraints, impulse `feel.ragdollImpulse` along the killing
  hit), then is removed after `feel.ragdollSeconds` — the reaper rules from C1 still apply.
- **Animations**: load `animations.*` on each enemy Animator (pcall, fallback as above); walk vs
  run by speed; `enemyHit` on stagger.
- Keep `Combat.luau` pure; if steering needs maths, put it in `EnemyService`.

## Combat client (ui-engineer A)

- **CameraController** (new): over-the-shoulder per ruling 1, reading `Combat.json camera`.
  `Humanoid.CameraOffset = shoulderOffset`, `AutoRotate = false` with the root yawed to the camera
  on RenderStep, zoom clamped to `[minZoom, maxZoom]`, FOV `fieldOfView`, mouse locked except in
  `freeCursorPhases` and while any modal/debug strip is open (Alt toggles the cursor on PC).
  Restores the default camera when the character dies or the run ends.
- **InputController**: aim = the camera's centre ray (touch: plus the soft assist cone); gamepad
  bindings per ruling 1; keep sending the same intents.
- **HUD** (`CombatHud`): centre crosshair, hit marker (`feel.hitMarkerSeconds`), bow charge ring
  around the crosshair, touch buttons re-laid for the right thumb (attack largest, abilities and
  stance around it), ≥ 44 px.
- **Impact** (`CombatFxController`, `WeaponController`): hit sparks along `direction`
  (`feel.hitSparkCount`), camera shake `feel.shakeLight` / `shakeHeavy` (finisher, taking damage),
  existing hitstop, weapon trail (`feel.trailSeconds`), a visible arrow/bolt that flies at
  `feel.arrowSpeed` to the server-confirmed point, muzzle flash for guns, telegraph visuals
  (red ground ring for slam, red lane for charge, glow on the attacker for strike), kill pop.
  Heavy particles gate on `Theme.lowEndDevice`, never on `reducedMotion` (true on every phone).
- **Animations**: `playerSlash` / `playerLunge` override the procedural swing when they load;
  procedural pose remains the fallback. Remote players' swings (`CombatFx swing`) use the same.
- **Sounds**: play the existing `Sounds.json` combat keys at the right moments (they become
  audible once the lead uploads them; id 0 stays silent).

## Missions 2–4 and arenas (economy-designer, draft balance)

Same shape as `1_Village.json`: ids `boomtown`, `metropolis`, `orbital`; `era` 2/3/4; `arena` =
era name; `material` Steel / Circuits / Alloy; `bossWaves [5, 10]`; enemies `grunt` (melee),
`shooter` (ranged), `brute` (`charger`, elite); bosses with `patterns`. Numbers follow
`docs/BALANCE.md` "What C2 should re-check" §4 (cash ×100 per era, HP on the gear ladder,
materials flat) — marked draft; Stop 3 re-balances. Arena layouts follow the `ArenaLayout` type,
110×110 like Village with era-appropriate floor/wall materials and colours and 6–10 obstacles
that give cover to shooters. Village: brute becomes `charger`; Chief and Warlord get 2–3 patterns.
`sim_combat.py`: `MELEE_CONTACT_SLOTS` reads `ai.maxMeleeAttackers`; model charger and boss
patterns coarsely; `--check` stays green; new missions get the run-length assertion at their
recommended power.

## Sounds (sound picker + lead)

Pick one Kenney file per combat key (`swing, finisher, bowDraw, bowFire, gunFire, laser,
abilityCast, enemyHit, enemyDeath, playerHit, playerDown, waveStart, waveClear, bossStart,
bossDown, runEnd, lowHp, partyRally, partyWarcry, mentor`) from `assets/kenney_impact-sounds.zip`,
`kenney_interface-sounds.zip`, `kenney_music-jingles.zip`, `kenney_casino-audio.zip`, by filename,
with two alternates each, in `tools/audio_map.json`'s existing entry shape. The lead runs the
upload (20 of the account's 100 monthly uploads).

## Definition of done (Stop 1)

- Both builds, both sourcemaps + `luau-lsp analyze`, stylua, selene, `sim_economy.py --check`
  unchanged, `sim_combat.py --check` green, manifest/template checks green.
- Studio combat (Village): shoulder camera on PC and in the phone emulator; enemies spread
  around you (never more than `maxMeleeAttackers` hitting at once), shooters keep distance,
  the brute telegraphs and charges, both bosses show their patterns with a readable wind-up; hits
  spark, stagger and shake; kills ragdoll; the bow shows its charge ring and a flying arrow; every
  combat sound plays; animations load or fall back without errors.
- `DebugMission boomtown / metropolis / orbital` boots each new arena with placeholder rigs and a
  full 10-wave run.

**Rulings after Ben's look (2026-09-24):** the experience icon is the **era stack**
(`py tools/marketing/icon.py --final erastack_v2b` → `assets/marketing/final/icon_512.png`); the
store icons are the **A set** (`assets/marketing/final/store/<key>.png`). The rendered thumbnails
were rejected: thumbnails are **real Studio screenshots** shot from `tools/marketing/SHOTLIST.md`
and captioned by `py tools/marketing/caption.py` (shots in `tools/marketing/shots.json`, output
`assets/marketing/final/thumbs/`). The Blender thumbnail scripts were deleted.

---

# P1 contracts — Proving Grounds, movement, controls, crowd prototype (Ben, 2026-09-24)

Plan of record: `docs/COMBAT_DESIGN.md` (read it in full). P1 = section 10 step 2. Everything in
P1 runs **only in the Proving Grounds** (Workspace boolean `DebugProving` = true at boot, Studio
only); missions keep today's code untouched until P5. Gate: movement and feedback feel good on
PC **and phone**, and 100+ crowd enemies run smoothly.

## Architecture decisions (lead)

1. **Crowd enemies are not Humanoids.** The server simulates them as plain Luau records
   (position, velocity, yaw, state, hp) and never creates an Instance for them. Hit tests use a
   body sphere (centre `height/2`, `radius`) plus a head sphere (top, `headRadius`, the crit weak
   point). Clients learn of an enemy on `CrowdSpawn` (reliable), receive positions on
   `CrowdSnapshot` (an **UnreliableRemoteEvent** carrying a `buffer` from `CrowdCodec`) at
   `crowd.snapshotHz`, interpolate ~1 snapshot behind, and draw pooled placeholder bodies.
   `CrowdRemove` (reliable) ends one. Budget: 160 alive at 15 Hz under 1.5 ms server step.
2. **The server resolves every attack shape itself.** Melee: the client sends only a look
   direction; the server builds the arc/sphere/capsule from the character root. Ranged: the
   client sends camera origin + direction (Fortnite camera-ray aim, spread already applied); the
   server checks the origin is within `shooting.originPad` of the character's head, then tests
   the shape against crowd spheres (and world geometry for rays). Pure geometry lives in
   `src/shared/HitShapes.luau` (no Roblox globals except Vector3 maths) so the client can draw
   exactly the same shapes.
3. **Tuning.** `src/shared/Tuning.luau` returns `ProvingGroundsConfig` merged with Studio
   overrides (`TuneOverrides`, dot paths). The server owns the overrides (`RequestTune`, Studio
   only) and broadcasts them on `TuneState`; clients apply the same merge. **Every P1 system
   reads its numbers through `Tuning.Get()` each time it needs them** (cheap: cached merge,
   invalidated on change), so a slider moves the game immediately.
4. **Movement is client-simulated, server-checked**, as Roblox character physics already is:
   high/double jump and dash run on the client; `RequestDash` opens the server-side i-frame window
   (rate-limited by `dashCooldown`); `RequestSlam` makes the server apply the slam sphere at the
   character's **server-side** root position if it fell at least `slamMinHeight` since leaving the
   ground (server tracks airborne peak height per character).

## Ownership (one wave, disjoint)

| Owner | Files |
|-------|-------|
| lead | this section, `Types.luau` P1 types, `Config/ProvingGrounds.json` keys, `Catalog.GetProvingGroundsConfig`, `Combat.json debug.provingAttribute` (all applied) |
| luau-engineer **Crowd** | new `src/combat/server/Services/CrowdService.luau`, new `src/shared/CrowdCodec.luau`, `src/server/Services/RemoteService.luau` (add UnreliableRemoteEvent support: `unreliableEvents: {string}` in `RemoteDefs` + `FireClientUnreliable`/`FireAllUnreliable`) |
| luau-engineer **Range** | new `src/shared/HitShapes.luau`, new `src/shared/Tuning.luau`, new `src/combat/server/Services/RangeService.luau` (attacks, dash, slam, tuning, readouts, dummy sets), `CombatRemotes.luau`, `ArenaService.luau` + `Main.server.luau` (Proving mode boot), `DebugService.luau` |
| ui-engineer **Render** | new `src/combat/client/Controllers/CrowdRenderer.luau` (pooled bodies, interpolation, flash/flinch/knockback/launch/death visuals driven by strikes) |
| ui-engineer **Motion** | new `src/combat/client/Controllers/MovementController.luau`, `InputController.luau` (range input path: shooting with bloom/ADS/first-shot, melee swings, touch auto-fire / auto-swing / tap-fire, no attack button in the range), `CameraController.luau` (ADS zoom, air handling) |
| ui-engineer **Feedback** | new `src/combat/client/Controllers/FeedbackController.luau` (the six layers + hitbox effects), new `src/combat/client/UI/Crosshair.luau`, new `src/combat/client/UI/RangePanel.luau` (tuning panel + readouts), `CombatUIController.luau` (mounting), `Main.client.luau`, combat blocks of `src/client/UI/Theme.luau` |
| economy-designer | values in `Config/ProvingGrounds.json` (keys frozen), new `src/shared/Layouts/Arenas/ProvingGrounds.luau` |
| roblox-reviewer → qa-runner → docs-keeper | after wave 1 |

Frozen: `Types.luau`, every hub file except `RemoteService`, `EnemyService`, `WaveService`,
`CombatService` (missions untouched), `ProfileSchema` (no persistence in the range).
`Theme.luau` combat blocks belong to ui **Feedback**; Render and Motion report constants they need
or keep them as named module constants **only if** purely visual (colours of placeholder
bodies come from config).

## APIs between owners

```luau
-- CrowdService (server, Crowd)
CrowdService.Spawn(kind: string, position: Vector3, behaviour: string, anchor: Vector3?): number   -- returns id
CrowdService.Remove(id: number): ()
CrowdService.Clear(): ()
CrowdService.Query(center: Vector3, radius: number): { number }             -- ids whose body sphere may overlap
CrowdService.Get(id: number): { position: Vector3, velocity: Vector3, kind: string, hp: number, maxHp: number, state: Types.CrowdState }?
CrowdService.Damage(id: number, amount: number, byUserId: number, push: Vector3?, launch: number?): (number, boolean)  -- (dealt, killed); armour, knockbackMult applied inside
CrowdService.OnKilled(callback: (id: number, byUserId: number) -> ()): ()
CrowdService.AliveCount(): number
CrowdService.StepMs(): number                                                -- last server step cost
-- behaviours idle/walk/strafe/jump/chase per DummyGroupDef; chase = nearest player, simple
-- separation; no attacks in P1 (dummies never hurt players).

-- CrowdCodec (shared, Crowd)
CrowdCodec.Encode(entries: { Types.CrowdSnapshotEntry }, origin: Vector3): buffer
CrowdCodec.Decode(data: buffer, origin: Vector3): { Types.CrowdSnapshotEntry }

-- HitShapes (shared, Range): each returns true if a sphere (c, r) overlaps the shape padded by pad
HitShapes.Arc(origin: Vector3, forward: Vector3, range: number, arcDegrees: number, pad: number, c: Vector3, r: number): boolean
HitShapes.Sphere(center: Vector3, radius: number, pad: number, c: Vector3, r: number): boolean
HitShapes.Capsule(a: Vector3, b: Vector3, radius: number, pad: number, c: Vector3, r: number): boolean
HitShapes.Cone(origin: Vector3, forward: Vector3, range: number, halfAngleDegrees: number, pad: number, c: Vector3, r: number): boolean
HitShapes.Ray(origin: Vector3, direction: Vector3, range: number, width: number, pad: number, c: Vector3, r: number): number?  -- distance along the ray, nil = miss

-- Tuning (shared, Range)
Tuning.Get(): Types.ProvingGroundsConfig      -- base merged with current overrides
Tuning.SetOverrides(o: Types.TuneOverrides): ()
Tuning.GetOverrides(): Types.TuneOverrides
Tuning.Changed: RBXScriptSignal-like { Connect: (self, () -> ()) -> { Disconnect: (self) -> () } }
Tuning.Export(): string                        -- merged config as pretty JSON (for "Save winner")
```

## Remotes (combat place; all intents rate-limited, validated, inert outside the range)

| Intent | Payload | Notes |
|---|---|---|
| `RequestRangeAttack` | `(weapon: "sword" \| "gun", seq: int, origin: Vector3, direction: Vector3, ads: boolean)` | origin ignored for melee; server enforces `rate` per weapon |
| `RequestDash` | `(direction: Vector3)` | opens i-frames, enforces `dashCooldown` |
| `RequestSlam` | `()` | server-checked airborne height, `slamCooldown` |
| `RequestTune` | `(path: string ≤ 96, value: number \| boolean \| string ≤ 32)` | Studio only; path must exist in the base config and keep its type |
| `RequestRangeCommand` | `(cmd: string ≤ 24, arg: string? ≤ 32)` | Studio only: `set <name>` (load a dummy set), `reset`, `stress`, `weapon <sword\|gun>`, `variant <A\|B\|C>`, `export` (server prints `Tuning.Export()` to Output), `clearTune` |

| Event | Payload |
|---|---|
| `CrowdSpawn` | `{ Types.CrowdSpawnInfo }` (batched) |
| `CrowdSnapshot` (unreliable) | `buffer` |
| `CrowdRemove` | `{ number }` (batched) |
| `CombatFx` (existing) | gains `CombatFxStrike` — one per resolved attack, to everyone in the range |
| `TuneState` | `(overrides: TuneOverrides, weapon: string, variant: string)` — on change and on join |
| `RangeStats` | `(RangeStats)` to the attacker after each attack and at 2 Hz |

## Behaviour rules

- **Melee:** swings every `1/rate` s while held; combo index cycles `chain`; shape from the root at
  chest height along the flattened look direction; cap = nearest-first. Air swing: client holds the
  character for `movement.airAttackHangSeconds`.
- **Ranged:** hitscan resolves at once; projectiles (`projectileSpeed > 0`) are simulated by the
  server (step with the crowd tick, max 3 s) and explode (`splashRadius`) on contact/ground; the
  strike fx is sent at impact (with `endPoint`). Cone guns: `pellets` rays spread inside
  `spreadDegrees`, each pellet hits one enemy; the server uses its own pellet pattern seeded by
  `seq`. Crit = ray/pellet passes the head sphere first → × `shooting.critMult`.
- **Bloom (client):** grows by moving/jumping/firing, shrinks at rest, min/max from config, ×
  `adsBloomMult` in ADS; the first shot after `firstShotSeconds` idle has zero spread.
- **Touch:** `autoFire` = attack runs while an enemy sphere is within `autoFireAssistDegrees` of the
  crosshair ray (ranged) or inside the melee shape + `autoSwingPad` (melee), respecting `rate`;
  `tapFire` = tap on the right half attacks; drag still aims. No attack button in the range. Jump,
  dash and slam are small buttons; slam = the dash button while airborne above `slamMinHeight`.
- **Feedback layers** (strength from `feedback.*`, 0 = off): crosshair hit marker / crit / kill X
  and kick; numbers (one combined burst per strike: total + "×N"); enemy white flash; enemy
  reaction (flinch, knockback, launch, death burst — Render owns the body motion, Feedback asks it
  via `CrowdRenderer.React(id, kind, direction, strength)`); hitbox effect (exact shape from the
  strike, drawn for ~0.15 s, matching `HitShapes`); screen (hitstop scaled by hits, shake,
  edge flash on 5+ kills, `HapticService` pulse where supported); counters (combo + kills).
  Wireframe toggle draws the true padded shape.
- **Readouts** (RangePanel): last hits / kills per attack, DPS (5 s window), time to clear the
  current set, alive count, server step ms, client FPS.

## Definition of done (P1)

- Both builds, both sourcemaps + luau-lsp, stylua, selene, `sim_economy.py --check` and
  `sim_combat.py --check` unchanged (missions untouched), manifest/template checks green.
- Studio: `DebugProving = true`, Play → the Proving Grounds with the default set; RangePanel
  switches sets, weapons, variants; sliders change values live; `export` prints JSON.
- High jump, double jump, dash (with i-frame flag), ground slam damaging a crowd.
- Sword A/B/C and gun A/B/C each hit crowds per their shape; hitbox effect matches the wireframe.
- Phone emulator: no attack button; auto-fire and auto-swing work; tapFire alternative works.
- `stress` set: 150 chasing enemies, smooth client, server step shown < 2 ms in Studio.

---

# P2 contracts — weapon families + bows in the range (Ben, 2026-09-28)

Plan of record: `docs/WEAPONS.md` (approved 2026-09-28) and `docs/COMBAT_DESIGN.md`. Ben's P1
verdict: "I really love all the alternatives, the combo melee is great, it lacks the bow."
Still range-only (`build/proving.rbxl`); missions untouched until P5. **Abilities are P3**, not P2.

## Rulings

1. **Families replace sword/gun.** `ProvingGrounds.json weapons` is now keyed by family id, and
   each family has `name`, `slot` (melee|ranged), `era`, `default` and `variants`. The six P1
   variants became six families with identical numbers: broadsword = old sword A, spinblade = B,
   warhammer = C, shotgun = gun A, rifle = B, launcher = C. New families: **greataxe** (A/B),
   **spear** (A/B, capsule thrust), **longbow** (A/B, charged piercing arrow; A bursts on a full
   charge) and **splitbow** (A/B, the arrow splits into a fan).
2. **Loadout:** each player holds one melee family and one ranged family (`RangeLoadout`),
   starting from `ProvingGrounds.json loadout`. **1 = melee slot, 2 = ranged slot** (gamepad Y
   toggles). The panel picks the family per slot and the variant per family.
3. **Arrows are real projectiles.** A ranged `ray` with `projectileSpeed > 0` flies with
   `gravity`, and the server steps it, hitting along its path up to `pierce`. A `sphere`
   projectile explodes on contact, as the launcher does. Every projectile is announced to all
   clients at fire time (`CombatFxShot`), so everyone sees it fly; damage still arrives as
   `CombatFxStrike`. This also closes the P1 carry-over "other players' shots have no fx".
4. **Charge (bows):** hold to draw, release to fire. The client sends `charge` 0–1. The server
   caps it with its own clock: `(now − drawStart) / chargeSeconds`, with
   `controls.comboResetSeconds` style tolerance. `RequestRangeDraw` starts that clock. Damage
   scales from `minChargeFraction` to 1 of `damage`. A **full** charge also bursts `blastRadius`
   at the arrow's end point for `damage × blastDamageMult`.
5. **Split arrows:** after `splitDistance` studs the arrow becomes `splitCount` arrows, fanned
   evenly across `splitArcDegrees` around its direction. The pattern is deterministic
   (`seq`-seeded jitter via `HitShapes.Pellets`). Each child hits one enemy plus `pierce`.
6. **Phones, still no attack button.** With `autoFire`, a charge weapon draws automatically while
   an enemy is in the assist cone and releases at a full charge, or at ≥ `minChargeFraction`
   when the target leaves. With `tapFire`, a short tap fires a minimum-charge arrow and a held
   press draws until release.

## Types (applied)

- `RangeWeaponVariant` gains `gravity`, `chargeSeconds`, `minChargeFraction`, `blastRadius`,
  `blastDamageMult`, `splitCount`, `splitDistance` and `splitArcDegrees` (all optional).
- `RangeWeaponDef` gains `name`, `slot` and `era`.
- New `RangeLoadout`.
- `ProvingGroundsConfig.weapons` is `{ [string]: RangeWeaponDef }`, plus `loadout`.
- New `CombatFxShot` in the `CombatFx` union.

## Remotes (changed or new; all range-only, validated, rate-limited)

| Intent | Payload |
|---|---|
| `RequestRangeAttack` | `(weapon: string ≤ 24 (family id; must be the player's family for that slot), seq: int, origin: Vector3, direction: Vector3, ads: boolean, charge: number [0,1])` |
| `RequestRangeDraw` | `(weapon: string ≤ 24)`: starts the server draw clock (bucket `attack`) |
| `RequestRangeCommand` | `weapon <familyId>` puts that family into its slot; `variant <familyId> <key>` (one arg string, space-separated); the others are unchanged |

| Event | Payload |
|---|---|
| `TuneState` | `(overrides: TuneOverrides, loadout: RangeLoadout)` (**changed**) |
| `CombatFx` | + `CombatFxShot` at fire time for every projectile (arrows, split children announced as ONE shot, the launcher shell) |

`Tuning.Validate`: `weapons.*.slot` must be melee|ranged. The enum and path rules follow the new
layout (`weapons.<family>.variants.<key>.<field>`).

## Ownership (one wave, disjoint)

| Owner | Files |
|---|---|
| lead | this section, `Types.luau`, the `ProvingGrounds.json` restructure (applied) |
| luau-engineer **Range** | `RangeService.luau`, `HitShapes.luau`, `Tuning.luau`, `CombatRemotes.luau` |
| ui-engineer **Motion** | `InputController.luau`, `MovementController.luau`, `CameraController.luau` |
| ui-engineer **Feedback** | `FeedbackController.luau`, `Crosshair.luau` (draw-charge ring), `RangePanel.luau`, `CombatUIController.luau`, combat blocks of `Theme.luau` |
| economy-designer | values in `ProvingGrounds.json weapons` (keys frozen), `docs/BALANCE.md` "P2" |
| roblox-reviewer → qa-runner → docs-keeper | after wave 1 |

Cross-owner API:
- `InputController.SetLoadout(loadout: Types.RangeLoadout)` replaces `SetLoadout(weapon, variant)`.
  FeedbackController is still the only TuneState listener and calls it.
- `InputController.GetCharge(): number` (0–1, 0 when not drawing) feeds the crosshair draw ring.
- `InputController.GetActiveSlot(): "melee" | "ranged"`.

## Definition of done (P2)

- Both builds + `build/proving.rbxl`, both sourcemaps + luau-lsp, stylua, selene,
  `sim_economy.py --check` and `sim_combat.py --check` unchanged, manifest/template checks green.
- In `proving.rbxl`:
  - 1/2 switch slots, and the panel lists all 10 families by slot and their variants.
  - Longbow draw ring fills, the arrow visibly flies and drops, pierces a row, and a full
    charge bursts.
  - Splitbow fans after ~10 studs and hits up to 7.
  - Greataxe cleaves 200°; the spear thrust hits a line.
  - Other players see arrows fly (Local Server, 2 players).
  - Phone: bows auto-draw and release on a target; tapFire tap/hold works.

---

# P3 contracts — abilities, phone slot button, SMG / Beam / Chain Gun (Ben, 2026-09-28)

Plan of record: `docs/WEAPONS.md` §2 (the ability list) and `docs/COMBAT_DESIGN.md` §10 step 4.
Ben's P2 verdict: everything works and the strengths are fine. His favourites were Longbow A and B,
Splitbow A, Greataxe A and B, and Spear B, so the **Spear default is now B**. Still range-only
(`build/proving.rbxl`). Missions stay untouched until P5. **No sound. No attack button on phones.**

## Rulings (lead)

1. **One ability per family**, defined at family level in `weapons.<family>.ability`
   (`Types.RangeAbilityDef`). **Q** casts the melee slot's ability and **E** the ranged slot's.
   On a gamepad, **L1** and **R1**. On touch, two buttons. Casting also makes that slot the active
   one, so the weapon you see matches the ability.
2. **Cooldowns are the server's.** The effective cooldown is `cooldownSeconds × abilities.cooldownScale`,
   and the floor is `minCooldownSeconds × cooldownScale`. **Every kill by the caster, from any source
   including abilities, takes `killRefundSeconds` off BOTH slots' remaining cooldowns.** A refund
   never goes below that slot's floor (`floorAt = castAt + floor`). A cast is accepted when
   `now ≥ readyAt − abilities.earlySeconds`. Changing a slot's family (range command) cancels that
   slot's running ability and makes its new ability ready at once.
3. **Busy lock.** Some abilities occupy the caster (column "busy" below). While busy, the server
   refuses normal attacks on both slots and the other ability. The one exception is Mag Dump,
   whose ranged attacks are the ability. Jump and dash are always allowed, except that the client
   does not start them during Leap Smash or Impale Dash, because those own the character's motion.
4. **Aim.** Every cast sends the camera ray (`origin`, `direction`), the same as a ranged attack,
   and the server checks the origin exactly as it does for attacks (`RangeService.CheckAim`).
   Aimed abilities resolve a **ground point**. Server `RangeService.GroundPoint` and the client
   mirror in InputController follow the same four steps:
   1. Raycast the world from `origin` along `direction` for `castRange + |origin − root|`.
   2. P = the hit, or the ray's end.
   3. If P is more than `castRange` from the root horizontally, pull it back along the flat line
      to `castRange`, keeping its Y.
   4. Drop P onto the floor: a down-ray from P + 3 studs for 250 studs. With no floor, use the
      root's floor Y.

   The ground point always uses the **raw** camera ray, melee abilities included: a flattened
   ray would always land at full `castRange`. Melee abilities use the flattened `direction` for
   their shapes and for `CombatFxCast.direction`.
5. **Server-owned motion damage.** Leap Smash and Impale Dash move the character on the client
   (MovementController), as the dash does. The server grants i-frames for `delaySeconds` and
   resolves the damage from **its own** numbers: the landing sphere at the server's ground point
   after `delaySeconds`, and the dash capsule from the server root at cast. If the client ends up
   somewhere else, the hit still lands where the server said.
6. **What you see is what you hit.**
   - One-off ability hits (Earthquake rings, landings, dash, slug blasts, the overcharged ray,
     cluster blasts) are ordinary strikes, so FeedbackController draws their exact shape.
   - Lasting abilities (Whirlwind, zones, Overload Sweep, held beams) send `tick = true` strikes.
     AbilityFx draws the area for the whole duration at its exact size (`radius` / `range`, no pad).
     Feedback skips the generic flash on ticks and softens hitstop and shake on them.
7. **Zones are vertical capsules**: from the ground point up `radius` studs, with radius `radius`.
8. **Three new families**, each with A/B variants: **SMG** (era 3), **Beam** (era 4) and
   **Chain Gun** (era 4). They reuse the hitscan ray path:
   - SMG adds a per-variant `bloomMult`.
   - Beam is a held `continuous` ray at rate 10 that pierces 30.
   - Chain Gun adds `chainCount`, `chainRadius` and `chainFalloff`. Every enemy the ray hits
     starts a chain, and the chain's hits do **not** count against `cap` or `pierce`. The strike
     carries `links` so clients draw the lightning.
9. **Phone slot button.** A touch button toggles melee and ranged, labelled with the other slot's
   family name. This closes the P2 known limit.
10. **Range rate buckets.** `RequestRangeAttack` and `RequestRangeDraw` move to bucket
    `rangeAttack` (`Combat.json remotes.rangeAttackCallsPerSecond` 40). `RequestRangeAbility` is on
    `rangeAbility` (4). The per-weapon `rate` is still enforced by RangeService.
11. **Numbers are tier 1.** An ability's `damage` is per hit or per tick and is tier-1 absolute,
    so it scales by the slot tier like weapon damage (P5). Mag Dump deals the SMG variant's damage.

## Ability table (tier-1 starting values in `ProvingGrounds.json`; economy-designer tunes them)

"cast" = the server root at the cast. "ground" = the ground point (ruling 4). Every strike
carries `ability = id`. Fields not named for an ability are absent.

| id (family) | mechanic | fields | busy |
|---|---|---|---|
| `whirlwind` (broadsword) | Channel. Every `tickSeconds` for `durationSeconds`, a 360° **arc** of reach `range` around the **current** server root (tick). Movement is ×`moveSpeedMult`. | damage, range, pad, cap, knockback, launch, durationSeconds, tickSeconds, moveSpeedMult | durationSeconds |
| `earthquake` (warhammer) | `count` **spheres** centred on the floor below the cast root (sent as the cast fx `target`). Ring k (from 1) lands at `delaySeconds + (k−1)·tickSeconds` with radius `radius + (k−1)·spacing` and damage `damage·falloff^(k−1)`. Inner enemies are hit by every ring. Not ticks. | damage, delaySeconds, count, radius, spacing, tickSeconds, falloff, pad, cap, knockback, launch | delaySeconds |
| `bladeStorm` (spinblade) | Zone at ground (castRange). From `delaySeconds`, every `tickSeconds` until `delaySeconds + durationSeconds`, a vertical capsule of `radius` (tick) **pulls** toward the centre (`pull`). | damage, castRange, delaySeconds, radius, durationSeconds, tickSeconds, pull, pad, cap, knockback, launch | — |
| `leapSmash` (greataxe) | Leap to ground (castRange, apex `height` above the higher end). At `delaySeconds`, a **sphere** of `radius` at the server's ground point. I-frames for delaySeconds. | damage, castRange, height, delaySeconds, radius, pad, cap, knockback, launch | delaySeconds |
| `impaleDash` (spear) | Dash along the flat aim for `range` studs (stopped by world geometry at chest height) over `delaySeconds`. At the cast, a **capsule** of full `width` from cast to the dash end, pushing along the dash. I-frames. The cast fx `target` = the dash end. | damage, range, width, delaySeconds, pad, cap, knockback, launch | delaySeconds |
| `arrowRain` (longbow) | Zone at ground (castRange). Same timing as bladeStorm, no pull (tick). | damage, castRange, radius, delaySeconds, durationSeconds, tickSeconds, pad, cap, knockback, launch | — |
| `volley` (splitbow) | One projectile through `RangeService.FireProjectile` that splits after `spacing` studs into `count` (≤ `HitShapes.MAX_FAN`) arrows over `arcDegrees`. Each arrow hits `pierce` enemies. Shares the P2 volley rules (one cap, no double hits; cap 0 = count × pierce). | damage, count, arcDegrees, spacing, pierce, range, width, pad, cap, speed, gravity, knockback, launch | — |
| `slugBurst` (shotgun) | `count` true **cones** (`range`, full angle `arcDegrees`), `tickSeconds` apart, starting at the cast. Each fires from the character's Head (root if none) at that moment, along the cast aim. Not ticks. | damage, count, tickSeconds, range, arcDegrees, pad, cap, knockback, launch | count × tickSeconds |
| `overchargedShot` (rifle) | After `delaySeconds`, one **ray** from the cast origin along the cast aim. Full `width`, reach `range`, stopped by world geometry, **unlimited pierce** (cap 0 = all), crits ×`shooting.critMult` on heads. | damage, delaySeconds, range, width, pad, cap, knockback, launch | delaySeconds |
| `magDump` (smg) | Buff (`RangeService.SetAttackBuff`). For `durationSeconds` the SMG's rate is ×`rateMult` and each bullet hits `pierce` enemies. The client fires on its own for the whole duration (no hold, no bloom), aiming at the crosshair. | durationSeconds, rateMult, pierce | durationSeconds (ranged attacks allowed) |
| `clusterShell` (launcher) | A shell through `FireProjectile` (`speed`, `gravity`, `range`), exploding on contact: a **sphere** of `radius` for `damage`. In `onImpact`, `count` bomblets land at `HitShapes.Scatter(impact, count, spacing, seq)`, and each explodes `delaySeconds` later: a sphere of `blastRadius` for `damage·blastDamageMult`. Not ticks. | damage, range, speed, gravity, radius, count, spacing, delaySeconds, blastRadius, blastDamageMult, pad, cap, knockback, launch | — |
| `overloadSweep` (beam) | Over `durationSeconds`, `count` slices, left to right across `arcDegrees` centred on the flat aim. Slice i is an **arc** from the current server root, reach `range`, opening `arcDegrees/count`, forward rotated to the slice centre. One shared `exclude` hits each enemy once per sweep (tick). | damage, durationSeconds, count, arcDegrees, range, pad, cap, knockback, launch | durationSeconds |
| `stormCoil` (chaingun) | Zone at ground (castRange). Every `tickSeconds` from `delaySeconds` for `durationSeconds`, it zaps the `targets` nearest enemies within `radius` (a sphere with cap = targets). Each zapped enemy starts a chain of `count` jumps (`spacing` jump radius, `falloff`). The strikes carry `links` (tick). | damage, castRange, delaySeconds, durationSeconds, tickSeconds, radius, targets, count, spacing, falloff, pad, cap, knockback, launch | — |

## Types (applied)

- `RangeWeaponVariant` gains `chainCount`, `chainRadius`, `chainFalloff`, `bloomMult` and
  `continuous` (all optional).
- `RangeAbilityDef` is new. `RangeWeaponDef.ability` is new (optional).
- `RangeAbilitiesConfig` is new, and `ProvingGroundsConfig.abilities` is new.
- `CombatFxStrike` gains `ability`, `tick` and `links`.
- `CombatFxShot` gains `ability`.
- `CombatFxCast` is new and is in the `CombatFx` union.
- `RangeAbilitySlotState` and `RangeAbilityState` are new.
- `AbilityStrikeSpec` is new (server only).
- `RangeStats` gains `ability`, `abilityHits` and `abilityKills`.
- `CombatRemotesConfig` gains `rangeAttackCallsPerSecond` and `rangeAbilityCallsPerSecond`.

Config (applied):
- In `ProvingGrounds.json`: an `ability` block on all 13 families; families `smg`, `beam` and
  `chaingun` with A/B; `abilities { cooldownScale 1, earlySeconds 0.15 }`; spear `default` "B".
- In `Combat.json`: `remotes.rangeAttackCallsPerSecond` 40 and `remotes.rangeAbilityCallsPerSecond` 4.

## Remotes (range-only, validated, rate-limited)

| Intent | Payload | Bucket |
|---|---|---|
| `RequestRangeAbility` | `(slot: "melee" \| "ranged", seq: int, origin: Vector3, direction: Vector3 (non-zero))` | `rangeAbility` |
| `RequestRangeAttack`, `RequestRangeDraw` | unchanged payloads | **`rangeAttack`** (was `attack`) |

| Event | Payload |
|---|---|
| `RangeAbility` (new, reliable, to the caster) | `(state: RangeAbilityState)`. Sent on join, on every cast, on a family change, and after kill refunds (coalesced, ≤ 4 Hz). |
| `CombatFx` | adds `CombatFxCast` (to everyone, at the cast and on a cancel). Strikes and shots from abilities carry `ability`. |
| `RangeStats` | adds the ability totals. |

`Tuning.Validate`: `weapons.*.ability.id` and `weapons.*.ability.name` are structural (untunable),
like `name`, `slot` and `era`. Every numeric ability field is tunable at
`weapons.<family>.ability.<field>`. `abilities.*` is tunable.

## Server APIs

```luau
-- RangeService (Range): hooks for AbilityService. All are range-only; none of them yields.
RangeService.LoadoutOf(player: Player): Types.RangeLoadout?                  -- nil = not a range player
RangeService.RootOf(player: Player): BasePart?
RangeService.CheckAim(player: Player, origin: Vector3): boolean              -- same test as ranged attacks
RangeService.GroundPoint(player: Player, origin: Vector3, direction: Vector3, castRange: number): Vector3?  -- ruling 4
RangeService.FloorBelow(position: Vector3): Vector3                          -- step 4 of ruling 4 alone
RangeService.SeedFor(player: Player, seq: number): number                    -- the salted seed (pelletSeed)
-- One ability hit: gather → cap nearest-first → damage/push/launch → optional chains → ONE
-- CombatFxStrike (weapon = family, variant = the player's key for it, ability = id, tick, links)
-- → ability readout totals for spec.cast + the DPS log. Returns (distinct enemies hit, kills).
RangeService.Strike(player: Player, family: string, ability: string, spec: Types.AbilityStrikeSpec): (number, number)
-- An ability projectile on the normal projectile path, announced with CombatFxShot{ability}. Its
-- strikes carry `ability` and add to cast `cast`. onImpact runs inside the server step (it must
-- not yield) at the detonation point of a sphere projectile, or where an arrow flight ends.
RangeService.FireProjectile(player: Player, family: string, ability: string, cast: number,
	variant: Types.RangeWeaponVariant, origin: Vector3, direction: Vector3, seed: number,
	onImpact: ((point: Vector3) -> ())?): boolean                                  -- false = refused (budget)
-- Normal-attack modifiers. A buff (nil clears it) changes the slot's rate and hitscan pierce until
-- `untilClock` (os.clock). A lock refuses attacks on both slots until `untilClock`, except slot
-- `allow`. A cleared or expired buff/lock is a no-op.
RangeService.SetAttackBuff(player: Player, slot: "melee" | "ranged", buff: { rateMult: number, pierce: number, untilClock: number }?): ()
RangeService.SetAbilityLock(player: Player, untilClock: number, allow: ("melee" | "ranged")?): ()
RangeService.GrantIframes(player: Player, seconds: number): ()             -- extends, never shortens
RangeService.OnLoadoutChanged(callback: (player: Player, slot: "melee" | "ranged") -> ()): ()

-- HitShapes (Range): the cluster bomblet pattern. count points evenly spaced on a flat circle
-- of radius spacing around center, the whole ring turned by a Park–Miller angle from seed (no
-- other jitter), so the server and every client scatter the same bomblets.
HitShapes.Scatter(center: Vector3, count: number, spacing: number, seed: number): { Vector3 }

-- AbilityService (Abilities, new): the cast pipeline, cooldowns, refunds, busy lock, timelines.
AbilityService.Init(): ()
AbilityService.Start(): ()                                  -- after RangeService.Start; inert off the range
AbilityService.AddPlayer(player: Player): ()                -- sends the first RangeAbility state
AbilityService.RemovePlayer(player: Player): ()             -- drops the timelines, no fx
AbilityService.OnCast(player: Player, slot: string, seq: number, origin: Vector3, direction: Vector3): ()
```

AbilityService runs every timeline on its own Heartbeat connection. Nothing in it yields, and a
timeline of a player who left is dropped. Each cast gets a server cast id (an increasing
integer), which is the `cast` in every spec. `seq` has the same replay guard as attacks.

## Client APIs

```luau
-- InputController (Motion)
InputController.CastAbility(slot: "melee" | "ranged"): ()      -- = pressing Q / E
InputController.ToggleSlot(): ()                                -- = 1/2 toggle, gamepad Y, touch slot button
InputController.GetAbilityState(): Types.RangeAbilityState?     -- latest RangeAbility event
InputController.IsBusy(): boolean                               -- local mirror of busyUntil
```

AbilityBar (Feedback) reads those getters. AbilityFx reads the tuning, CombatFx and the characters.
Nobody else listens to `RangeAbility` (Motion owns it).

## Ownership (one wave, disjoint)

| Owner | Files |
|---|---|
| lead | this section, `Types.luau`, the `ProvingGrounds.json` keys and `Combat.json` remotes (applied), and `src/combat/server/Main.server.luau` wiring after the wave: the `RequestRangeAbility` handler, AbilityService Init, Start, AddPlayer and RemovePlayer |
| luau-engineer **Range** | `RangeService.luau` (new families, chains, buff/lock, the hook API above), `HitShapes.luau` (`Scatter`), `Tuning.luau` (ability paths), `CombatRemotes.luau` (new intent and event, the two buckets) |
| luau-engineer **Abilities** | new `src/combat/server/Services/AbilityService.luau` |
| ui-engineer **Motion** | `InputController.luau` (Q/E, L1/R1, touch ability and slot buttons with cooldown sweeps, cast pipeline, busy mirror, Mag Dump auto-fire, beam hold, SMG `bloomMult`, the ground-point mirror), `MovementController.luau` (leap, lunge, the Whirlwind speed multiplier, new satellite buttons), `CameraController.luau` |
| ui-engineer **Feedback** | `FeedbackController.luau` (tick strikes, chain `links`, continuous beam, ability numbers), new `src/combat/client/UI/AbilityBar.luau` (PC/gamepad cooldown HUD, hidden on touch), `Crosshair.luau`, `RangePanel.luau` (ability rows, the cooldowns on/off button, ability readout), `CombatUIController.luau`, the combat blocks of `Theme.luau` |
| ui-engineer **AbilityFx** | new `src/combat/client/Controllers/AbilityFx.luau` (lasting visuals for all 13 abilities from `CombatFxCast`, plus ability strikes and shots), `src/combat/client/Main.client.luau` (start it) |
| economy-designer | values in `ProvingGrounds.json` (keys frozen), `docs/BALANCE.md` "P3", new `tools/sim_range.py` (the scratch range simulator, made permanent) |
| roblox-reviewer → qa-runner → docs-keeper | after the wave |

Frozen: every file not listed above. That includes CrowdService, CrowdRenderer, CrowdCodec,
missions, the hub and `ProfileSchema`. Theme constants that AbilityFx needs are reported to Feedback,
or kept as named module constants when they are purely visual.

## Review round (lead, after roblox-reviewer)

- **Air reach:** an ability arc around the caster's own root (Whirlwind, Overload Sweep) sets
  `AbilityStrikeSpec.airReach`. While the caster is airborne, `Strike` reaches down
  `movement.airSwingReachDown` like a melee swing, and the strike's `endPoint` carries the band
  bottom as melee arcs do. AbilityFx draws the Whirlwind ring on the real floor.
- **Refused casts:** the state sent in answer to a refused cast carries `refusedSeq` = that
  cast's seq. The client cancels that cast's local effects at once.
- **Tolerances move to config:** `shooting.rateBurstShots` (was `RATE_BURST_SHOTS`),
  `abilities.busyEarlySeconds` and `abilities.dashWallClearance`.
- **Separate seeds:** ability seeds are salted apart from attack seeds (`SeedFor`), so a Volley
  or Cluster Shell never shares a flight key with an arrow or shell in flight.
- **Deferred to P5 (live only):** the caster's own ability visuals and held beam wait one round
  trip. This is the same carry-over as local prediction of your own shots.
- **Note for P5:** a family switch resetting the slot's cooldown is a range convenience. Missions
  must carry the remaining cooldown across a switch.

## Definition of done (P3)

- Both builds and `build/proving.rbxl`, both sourcemaps + luau-lsp, stylua, selene;
  `sim_economy.py --check` and `sim_combat.py --check` unchanged; manifest and template checks
  green; `py tools/sim_range.py` runs.
- In `proving.rbxl`:
  - Q/E cast every family's ability as its table row says.
  - The AbilityBar shows both cooldowns, and kills visibly shorten them.
  - The panel's "Cooldowns off" makes every ability castable at once.
  - The ability rows tune live.
- The pickers list SMG under Metropolis and Beam and Chain Gun under Orbital, each with A/B.
- Chain lightning draws between enemies, and the beam is one continuous line while held.
- Phone emulator:
  - there is still no attack button;
  - two ability buttons with cooldown sweeps and a slot button work;
  - Mag Dump fires by itself.
- Local Server with 2 players: each sees the other's casts, zones, leaps and beams.

---

# M12 contracts — Growing city (wave 1: Village)

Plan of record: `docs/CITY_GROWTH.md` (approved 2026-09-29). Ben's rulings: **growth layouts (mock
B)**, and **Village gets an organic street plan**, shown to him as renders before anything is
built. M12 is built in the worktree `C:\Users\benja\Desktop\tycoon-m12` on branch
`m12-growing-city`. A second session works on combat in the main checkout: never touch it.

The reference for every rule below is the Village mock in
`assets/research/2026-09-28-growthmock/` (`gmb_core.py`: `develop_b`, `plant_woods`,
`kept_woods`). Where this contract and the mock differ, the contract wins.

## Principles

- **Client-only dressing, as in M9.** No server file, remote, attribute or profile change. The
  only thing the server sees change is layout data (slot positions), which PlotService already
  reads.
- Every dressing part: `Anchored` true; `CanCollide`, `CanQuery` and `CanTouch` false.
- **Deterministic.** Every client and the Python mirror derive the same fabric from: the era, the
  owned slots, each owned building's visible stage, `GrowthTier`, the layout and the fabric data.
  Construction timing is local animation and is never mirrored.
- **Everything degrades.**
  - An era without fabric data keeps its M9/wave 2c dressing unchanged.
  - A missing prop means that item is absent.
  - A missing config key means that feature is off.
  - None of these raise an Output error.
- **Generic code, Village data only.** Boomtown, Metropolis and Orbital are untouched in wave 1.
- **Only adds within an era.** The owned set, stages and tier only grow, so levels are monotonic.
  An era change rebuilds everything.

## Data

### Village layout (`src/shared/Layouts/Village.luau`)

- A new **organic growth layout** (see "Village layout" below) with the same slot ids, config and
  models.
- `SlotLayout` gains `district: string?`: a key of `fabric.districts`. Absent means the slot pulls
  nothing (street upgrades such as `dirtRoad`).
- Village drops `lots`, `treeZones`, `greeneryZones` and `parking`, because the fabric replaces
  them. `plazas` is optional.

### Fabric data (`src/shared/Config/Fabric/<Era>.json`)

Generated by `tools/fabric.py`; never hand-edited. Rojo turns it into a ModuleScript.

```json
{
  "version": 1,
  "parcels": [
    { "x": 12.5, "z": -30.0, "rotationY": 90, "size": "small", "stretch": "L1_3", "along": 7.25, "row": 1, "front": 0 }
  ],
  "wild": [
    { "kind": "clump", "variant": 2, "x": 30.1, "z": 14.8, "rotationY": 37.5, "scale": 1.04, "skirt": false,
      "quads": [[31.9, 16.2], [28.6, 16.9], [28.3, 13.4], [31.6, 12.7]] },
    { "kind": "single", "prop": "WoodsPine", "x": -41.2, "z": 3.3, "rotationY": 211, "scale": 0.95, "skirt": false }
  ]
}
```

- All coordinates are plot-local studs: origin at the plot centre, Y 0.
- **Parcel `i`** is its 1-based index in the list.
  - `size` is `"small"` or `"medium"`; the footprint in studs is `fabric.sizes[size]`.
  - `rotationY` follows the slot convention: front is −Z, and the front faces the parcel's street.
- **A parcel's address:**
  - `stretch` is the RoadGraph piece id (`"L<polyline>_<ordinal>"`) of the street stretch the
    parcel fronts.
  - `along` is the distance in studs from that stretch's `a` end (polyline order) to the foot of
    the perpendicular from the parcel's front-centre.
- **Rows:**
  - A row-1 parcel has `row: 1` and `front: 0`.
  - A row-2 parcel has `row: 2`, stands behind a row-1 parcel, and sets `front` to that parcel's
    index. It repeats that parcel's `stretch` and `along`.
- **Wild entries:**
  - `clump` draws the merged prop `fabric.wild.clumps[variant]` at (x, z), turned `rotationY` and
    scaled by `scale`.
  - A clump is modelled as four copies of one quarter design. Its quarter prop
    `fabric.wild.quarters[variant]` shares the clump's origin, with its trees in the local
    (+X, +Z) quadrant. Quarter q (1 to 4) is that prop turned `rotationY + 90·(q − 1)`, and
    `quads[q]` is that quarter's centre.
  - `quads` holds the four quarter centres in plot coordinates, used only for clearing tests.
  - `single` draws the prop named by `prop`.
  - `skirt: true` marks an entry that stands outside the plot base.
  - `variant` is 1-based (1 to #clumps), because the client indexes the Luau lists directly.
- **Rotation maths** (the generator and every mirror use exactly Roblox's `CFrame.Angles(0, a, 0)`
  mapping): local (x, z) → (x·cos a + z·sin a, −x·sin a + z·cos a).

### Config (`CityDressing.json` v4)

The lead applies the schema and Village's first values; the economy-designer then owns the values.

Each era gains an optional `fabric` block:

```json
"fabric": {
  "sizes": { "small": [6, 6], "medium": [8, 8] },
  "pull": { "radius": 24, "tierTerm": 0.14, "thresholds": [0.9, 1.4, 1.7, 2.1], "reach": 13, "levelsOverTier": 1, "smallMaxLevel": 3 },
  "heightFloor": 4.2,
  "districts": { "home": { "small": ["…"], "medium": ["…"] } },
  "sites": { "small": "SiteSmall", "medium": "SiteMedium" },
  "wild": { "clumps": ["WoodsClumpA", "…"], "quarters": ["WoodsQuarterA", "…"], "quarterRadius": 3.0, "singleRadius": 1.0 },
  "clear": { "slot": 6, "pad": 1.5, "street": 4.5, "parcel": 2 },
  "construction": { "minSeconds": 10, "maxSeconds": 30, "stagger": 0.4, "stageSeconds": 1.2, "riseSeconds": 0.6, "revealSeconds": 1.5 },
  "marker": { "prop": "NoticeBoard", "offset": [5, 0, -0.5], "stakeColor": [120, 84, 52], "stringColor": [235, 225, 200] },
  "padLook": { "material": "Ground", "color": [150, 118, 82] },
  "reveal": "RevealScaffold"
}
```

- Every district must list props for both sizes. A small-footprint prop may appear in a `medium`
  list; it is centred on the parcel.
- `budget` gains `parcels` (70 per plot), `wild` (110 per near plot) and `wildFar` (45 per far
  plot).

## `src/shared/CityFabric.luau` (new; pure)

Numbers, strings and tables only: no Vector3 and no Roblox globals. `tools/cityfabric.py` mirrors
it one to one.

```lua
export type FabricStretch = { from: number, to: number, length: number } -- visible stretches only
export type FabricLandmark = { slotId: string, node: number, district: string }
export type FabricInput = {
	tier: number,
	stretches: { [string]: FabricStretch }, -- keyed by piece id
	landmarks: { FabricLandmark }, -- owned slots that have a district and a join node
	parcels: { Types.FabricParcel },
}
export type FabricParcelState = { level: number, district: string?, governor: string? }
CityFabric.Develop(input: FabricInput, pull: Types.FabricPullConfig): { FabricParcelState }
```

### `Develop` (normative)

1. **Graph.** Every entry of `stretches` is an undirected edge `from`–`to` with weight `length`.
2. **Distances from each landmark.** For each landmark L, `dist_L` is Dijkstra from `L.node`
   (distance 0) over that graph.
3. **Drawn parcels.** A parcel is *drawn* iff `stretches[parcel.stretch]` exists. Its distance
   from L is `d = min(dist_L[from] + along, dist_L[to] + (length − along))`, or ∞ if neither end is
   reachable.
4. **Pull and score.**
   - `pull_L = max(0, 1 − d / radius)`.
   - `influence = Σ pull_L`.
   - `score = influence + tierTerm · tier` if any `pull_L > 0`, otherwise 0.
5. **Level.**
   - `level = #{ t in thresholds : score ≥ t }`.
   - Then `level = min(level, tier + levelsOverTier)`.
   - A `"small"` parcel is also capped: `level = min(level, smallMaxLevel)`.
   - A parcel that is not drawn has `level = 0`.
6. **Governor and district.**
   - `governor` is the landmark with the largest `pull_L`. Ties go to the larger `slotId` in
     byte-wise string order, which matches the mock's `max(pulls, key=(pull, id))`.
   - `district` is the governor's district.
   - With no pull, both are nil.
7. **Contiguity (row 1 only).**
   - Start with `accepted` empty.
   - Each pass computes one multi-source Dijkstra. Every landmark node is a source at distance 0.
     Each accepted parcel adds its `from` node at `along` and its `to` node at `length − along`,
     keeping the minimum per node.
   - Still within the pass, check every row-1 parcel in index order that is not yet accepted and
     has `level ≥ 1`. If `min(dist[from] + along, dist[to] + (length − along)) ≤ reach`, it joins
     `accepted`.
   - Passes repeat until one accepts nothing.
   - Any row-1 parcel that was never accepted gets `level = 0`.
8. **Row 2.**
   - `level = max(0, min(level, levels[front] − 1))`.
   - `district` and `governor` are copied from the front parcel.

**Mirror notes** (from the implementation, 2026-09-29):

- Pulls are summed over the landmarks sorted by `slotId` (byte order), then by node, one `+=`
  at a time. Floating-point addition is order-dependent, and Python 3.12+ `sum()` uses a
  compensated sum, so the mirror must use an explicit loop in that order.
- Distances use `sqrt(x·x + z·z)`, never `hypot`.
- Contiguity only measures through a stretch's end nodes. Two parcels on the same stretch
  never see each other directly; mock B behaves the same.

### What a parcel shows (renderer rule; the mirror copies it)

- **Height cap.**
  - `cap = max(heightFloor, H)`.
  - H is the governor's harvested height at its visible stage: from `Assets.json`
    `eras.<Era>.<modelName>.stages[stage + 1].parts`, max(offset.y + size.y/2) minus
    min(offset.y − size.y/2).
  - A landmark with no template gives H = 0.
- **By level:**
  - Level 0 shows nothing; the land stays wild.
  - Level 1 shows `sites[size]`.
  - Level 2 and up shows the prop `list[((i − 1) % #list) + 1]`, where
    `list = districts[district][size]`.
- **Stage shown** (level 2 and up):
  - Start from `s = min(level − 2, #stages − 1)`.
  - While `s > 0` and stage s's harvested height exceeds `cap`, lower s by 1.
  - Stage 0 is always allowed, because builders keep stage 0 at or under `heightFloor`.
- **Placement:** pivot at bottom-centre at (x, 0, z), facing `rotationY`, like lot houses.

### Clearing (renderer rule; the mirror copies it)

- **The mask.**
  - Every owned slot's footprint rect, grown by `clear.slot`. This is the same rect Scatter uses
    as that slot's keep-out.
  - Every slot that currently has a pad: its footprint rect and its pad rect, grown by
    `clear.pad`.
  - Every parcel at `level ≥ 1`: its footprint rect, grown by `clear.parcel`.
  - Every visible plaza's rect, grown by `clear.parcel`.
  - Every visible stretch and every drawn spur, as a segment.
- **A point with radius r is cleared if:**
  - its distance to any mask rect, minus r, is under that rect's margin (distance to an oriented
    rect: take the point into the rect's frame, then `hypot(max(|lx| − hx, 0), max(|lz| − hz, 0))`);
    or
  - its distance to any mask segment, minus r, is under `clear.street`.
- **Clumps and singles.**
  - A clump draws whole if none of its `quads` (radius `quarterRadius`) is cleared.
  - Otherwise each uncleared quad draws its quarter prop.
  - A single draws if its point (radius `singleRadius`) is not cleared.
- Put the geometry helpers in `CityFabric` too, so the mirror copies one module:
  `CityFabric.RectDistance(px, pz, rect)` and `CityFabric.SegmentDistance(px, pz, seg)`.

## Client (ui-engineer)

- **`src/client/City/Fabric.luau` (new).** Per-plot fabric state. The API is the ui-engineer's
  call; the behaviours below are binding.
  1. **Levels.**
     - Call `CityFabric.Develop` whenever the owned set, a building's stage, the tier or the visible
       stretches change.
     - Stages come from each `Building_<slotId>`'s child named `Stage<n>` (`^Stage(%d+)$`, as in
       PlotService). A missing child means stage 0.
  2. **Parcels** are drawn by the rules above.
  3. **Transitions.** They play only when the sync is animated (the existing `animate` flag: never
     on join, rejoin or rebuild) and the plot is near.
     - 0 → 1: the site appears with a `Dust` burst. Starts are staggered by `stagger` seconds per
       rank, ranked by distance from the building that triggered the change.
     - 0 or 1 → 2 and up: the site stands for a duration seeded per parcel in
       [`minSeconds`, `maxSeconds`], then the building replaces it with a `riseSeconds` rise and
       dust.
     - 2 → 3 or 3 → 4: after `stageSeconds`, the stage swaps with a pop and dust.
     - If the target rises while a timer is pending, the timer keeps running and shows the newest
       target when it fires.
     - Without animation, the final state is placed at once.
  4. **Wild.**
     - Near plots draw every uncleared clump, quarter and single, up to `budget.wild`.
     - Far plots draw uncleared whole clumps only (the skirt included), up to `budget.wildFar`.
     - Each sync removes newly cleared items, with a dust puff on near plots.
     - With city detail off, the wild layer is thinned evenly by index to `detail.treeShare`.
  5. **Next-pad dressing.** For each `Pad_<slotId>` in the plot's `Pads` folder:
     - the `marker.prop` stands at the pad centre + `marker.offset` (plot frame), facing −Z;
     - four stake Parts and four string Parts outline that slot's footprint rect, except for
       `streetOnly` slots;
     - `padLook` recolours the pad locally (Material and Color, client-side only; the server Part is
       otherwise untouched);
     - all of it is removed when the pad goes.
  6. **Landmark reveal.** When a `Building_<slotId>` appears during an animated sync on a near
     plot:
     - `reveal` is cloned at the slot, uniformly scaled (`Model:ScaleTo`) by
       `max(footprint X, footprint Z) / 9`;
     - it is removed after `revealSeconds` with dust.
  7. **Budgets.** `budget.parcels` applies to near and far plots. Far plots skip transitions.
- **`CityDressingController`.**
  - Creates the fabric state only for eras whose `Catalog.GetFabric(era)` exists and whose config
    has a `fabric` block.
  - Syncs it after RoadGraph in the same pass, so visible stretches are current.
  - Watches stage swaps (`ChildAdded` on each `Building_`) and the `Pads` folder.
  - Adds developed parcels to the walk solids, so walkers never cross a house.
- **`RoadGraph`** exports the logical network, for example
  `RoadGraph.FabricNetwork(state): ({ [string]: CityFabric.FabricStretch }, { [string]: number })`.
  - The first map holds the visible stretches (`state.visible`, never the near budget), keyed by
    `pieceId`, using `fromNode`, `toNode` and `length`.
  - The second map gives each routable slot's join node (`routes[slotId].junction.node`).
- **`Ambient` birds.** When a layout has no `treeZones` but has fabric wild, flocks circle over the
  first surviving clumps (by index).

### Client decisions (ui-engineer, 2026-09-29; the mirror copies them exactly)

- **Budgets are a fixed prefix of the data list.** Near plots draw wild entries with index
  ≤ `budget.wild`; far plots draw whole clumps whose clump number is ≤ `budget.wildFar`; every plot
  draws parcels with index ≤ `budget.parcels`. Clearing one item never makes another appear.
  The data order is set by the "Wild order" amendment below. A partly cleared clump counts as one
  entry but can draw up to three quarters.
- **Skirt entries stand on the world ground**, at Y = −(plot base height), because the plot base
  rests on the Ground part and the ground past the edge is lower.
- **The clearing mask's street segments are the straight polyline geometry**: each visible
  stretch's chord and each leg of every drawn spur, never the meandered trail.
  `RoadGraph.FabricNetwork` returns them as a third value.
- **Plaza rects** come from `Scatter.Solids`. A plaza is visible by the existing filler rule.
- **Owned slots and stages only accumulate within a build.** A VIP-skin respawn must not demolish
  the town; a real removal already rebuilds the plot through the controller.
- **Walk solids** are every in-budget parcel whose street is drawn, developed or not. They change
  only when a street appears, which is exactly when the walk lanes rebuild.
- **A district or governor change at level 2 or above** is shown as a stage swap: a pop after
  `stageSeconds`.
- **With no purchase in a sync** (a tier-only or pad-only change), sites ripple out from the last
  purchase seen, or else from the plot entrance.
- **Owned or padded `streetOnly` slots clear land** at their layout rect, exactly as the
  contract's mask says. The reveal scaffold and the stakes skip them.

### Review amendments (2026-09-29; client and mirror both follow them)

- **A bulk change is a restore.** A sync that adds more than one owned slot animates nothing: no
  reveal, ripple or dust. This covers a plot claim restoring a returning player's town, and data
  arriving late on your own plot. A tier jump alone is not a restore, because Buy Max can cross
  two tiers and must still animate.
- **Birds** circle the surviving clumps on the plot itself, and only fall back to skirt clumps once
  every on-plot clump is felled. The skirt is almost never cleared, so a flock over it would never
  move.
- **Config is validated once, in `Fabric.new`.** `pull` is used only if all six fields are finite
  numbers and `thresholds` is an array of numbers; otherwise every parcel stays at level 0. A
  missing `clumps` or `quarters` list counts as empty. A bad key never raises an error.
- **The mask's pad part follows ownership, not the live Pads folder.** Every *buyable* slot
  contributes its footprint rect and its pad rect, grown by `clear.pad`. A slot is buyable when it
  is unowned and its effective `requires` is owned (the config's `requires`, else the previous
  slot in purchase order; the first slot is always buyable), exactly `PlotService.refreshPads`'
  rule. An owned slot also keeps its pad rect (+`clear.pad`), because its footprint and path do not
  always cover that ground (`dirtRoad` has no spur). So the mask depends only on the owned set and
  never shrinks. The next-pad *dressing*
  (marker, stakes, `padLook`) still follows the live `Pads` folder, and a pad's dressing is kept
  for one `lod.refreshSeconds` after the pad disappears, to ride out a cosmetics refresh.
- **`marker.offset` is in the slot's frame.** The offset is turned by the slot's `rotationY` and
  added to the pad centre, and the marker faces the slot's front. `fabric.py check` fails if any
  marker's 2×2 footprint overlaps a slot footprint (+0.5), a pad, or a street or spur strip.
- **Wild order.** `fabric.py` writes the skirt clumps first (by z, then x), then the on-plot clumps
  farthest-first by straight-line distance from the entrance (the first point of polyline 1), then
  the singles. The woods that survive longest therefore fill the far-plot prefix. `check` fails unless the whole list fits `budget.wild`, and the first `budget.wildFar`
  clumps include every skirt clump.
- **At most `construction.maxPuffs` dust puffs play at once per plot.** A new puff reuses the
  oldest.
- **A ripple's origin** is only updated by animated syncs.

## Tools

- **`tools/fabric.py`** (new):
  - `py tools/fabric.py build <Era>` writes `Config/Fabric/<Era>.json` from the layout and
    `tools/fabric/<Era>.plan.json`, which holds the generator's inputs: parcel rules, the wild
    density plan and the seeds.
  - `py tools/fabric.py check <Era>` fails if:
    - the committed JSON differs from a fresh build;
    - a parcel overlaps a slot footprint (+1), a pad (+0.5), a plaza (+1), another parcel, the Sign,
      a street or spur strip (road width/2 + 1), or the plot edge (+1);
    - a row-1 parcel's `along` is outside `[0, length]`, or its front is more than 2 studs off the
      setback line.
  - Its JSON output is deterministic, with rounded numbers.
- **`tools/cityfabric.py`** (new, wave 1b): a one-to-one mirror of `Develop`, the clearing rule
  and the "what a parcel shows" rules.
- **`tools/streetplan.py`:** for an era with fabric data, it drops the lot, greenery, tree-zone and
  parking minimums, runs `fabric.py check`'s rules, and draws parcels in its PNG.
- **`tools/testfit/plotrender.py`** (wave 1b) draws the fabric exactly as the client does.
- **`tools/sim_economy.py`** (wave 1b) prints the fabric timeline: parcels by level at each tier.

## Village props (`tools/testfit/blueprints/_props/Village/`)

### Rules

- **Kits.** fantasy-town-kit and nature-kit, plus a generated `village-extras-kit`
  (`tools/assets/village_extras_kit.py`: crates, ladder, hoist, stone pile, haystack), coloured from
  the fantasy-town and nature colormaps.
- **Placement.** Front −Z faces the street. The origin is at bottom-centre at the parcel centre,
  and everything stays inside the parcel footprint. Yards, fences and garden garnish are part of
  the model.
- **Heights per stage:** stage 0 (level 2) ≤ **4.2** studs, stage 1 (level 3) ≤ **6.5**,
  stage 2 (level 4) ≤ **10.5**.
- **Silhouettes.** Never copy a Village landmark's silhouette. Landmark signature details
  (banners, lanterns, shutters) must not dominate a filler model. Prefer the slot-unused pieces:
  `wall-block`, `wall-wood-block`, `-block-half`, `wall-rounded`, `roof-window`, `roof-high-point`,
  `balcony-wall`, `stairs-wood`.
- **Stages are additive,** like a landmark's. Strips go to Ben before anything is uploaded.

### Props

| Prop | Size | Stages |
|---|---|---|
| `FabricHomeSmallA`, `FabricHomeSmallB` | small | 2: hut → cottage |
| `FabricHomeMediumA`, `FabricHomeMediumB` | medium | 3: hut → cottage → two-storey house |
| `FabricCampSmall` | small | 2: lean-to or tent with fire pit → log hut |
| `FabricCampMedium` | medium | 3 |
| `FabricCraftSmall` | small | 2: woodpile and chopping block → shed |
| `FabricCraftMedium` | medium | 3: shed → workshop → yard with kiln or sawpit |
| `FabricFarmSmall` | small | 2: tilled → crops with a fence |
| `FabricFarmMedium` | medium | 3: tilled → crops → crops, haystacks and a small barn (must not read as the FarmPlot slot) |
| `FabricMarketSmall` | small | 2: booth → double booth |
| `FabricMarketMedium` | medium | 3: booth → stalls → shop-house with a stall |
| `FabricCivicSmall` | small | 2: garden → green with a tree and a bench |
| `FabricCivicMedium` | medium | 3: garden → green → green with a feature (not the Well's look) |
| `SiteSmall`, `SiteMedium` | small, medium | 1, ≤ 6.5: stakes or fence, timber scaffold, plank and log piles, crates, hoist or ladder |
| `RevealScaffold` | 9×9 | 1, ≤ 8: an open timber scaffold ring with a hollow middle |
| `WoodsClumpA/B/C` | clump | 1: four quarters merged |
| `WoodsQuarterA/B/C` | quarter | 1 (see "Fabric data") |
| `WoodsPine`, `WoodsRound`, `MeadowRock` | single | 1 |
| `NoticeBoard` | ≤ 2×2 | 1, ≤ 4 |

## Village layout (economy-designer)

- **Street plan.** mock B's growth rules on an **organic** street plan:
  - the campsite just inside the entrance (front, −Z);
  - a curving high street (2 to 4 bends) up to the castle keep at the far end, facing the entrance
    down it;
  - a green or square halfway, with the well, fountain, market and tavern around it;
  - lanes branching at natural angles;
  - the farm at the edge of the heart, with a farm lane and fields;
  - the chapel and manor flanking the keep's approach.
  - The plan stays a tree (no loops).
- **Order.** Slot k is roughly k-th in network distance from the entrance; the exceptions are
  documented. At tier 1 only the first stretches near the entrance are drawn.
- **Frontage.**
  - Landmarks alternate with 1 to 3 parcels on both sides of the streets.
  - At least 40 parcels, at least 75% of them row 1, and at least 12 medium.
- **Existing Village rules stay:**
  - streets ≥ width/2 + 1 clear of footprints, pads and the Sign;
  - spurs;
  - pad reachability;
  - segments long enough for the baked-path pipeline.
- **Wild plan** (mock B `plant_woods`):
  - woods over the interior except the heart clearing, low and sparse in the front 10 to 18 studs;
  - a 16-stud skirt behind and at the sides, tapering toward the hub corners;
  - clumps on a jittered hex grid, singles and meadow at the margins.
- **Gate renders for Ben** (`assets/testfit/out/Village/m12_*.png`):
  - tier 1, tier 3, full and the entrance view;
  - a sheet comparing them with mock B's straight streets.
  - They come from the research mock renderer, pointed at the real layout and `Fabric/Village.json`
    (stand-in props until the real ones exist).

## Pipeline and gates (lead)

1. Ben approves the layout renders.
2. The Village path re-bake: `bake.py`, `upload_paths.py`, `harvest.py --emit`,
   `gen_templates.py --paths`.
3. Ben approves the prop strips; then merge and upload `_props/Village`. Timing allows **one
   harvest paste** for paths and props together.
4. Every upload and harvest is announced to the other session first and never runs at the same
   time as one of theirs.

## Ownership (wave 1a, disjoint)

| Owner | Files |
|---|---|
| lead | this section, `docs/CITY_GROWTH.md`, `CityDressing.json` (schema and first Village values), pipeline runs |
| economy-designer | `src/shared/Layouts/Village.luau`, `tools/fabric.py` (new), `tools/fabric/Village.plan.json` (new), `src/shared/Config/Fabric/Village.json` (generated), `tools/streetplan.py`, gate-render scratch under `assets/research/2026-09-28-growthmock/m12/` |
| luau-engineer | `src/shared/Types.luau` (M12 types), `src/shared/CityFabric.luau` (new), `src/shared/Catalog.luau` (`GetFabric`) |
| ui-engineer | `src/client/City/Fabric.luau` (new), `src/client/Controllers/CityDressingController.luau`, `src/client/City/RoadGraph.luau` (`FabricNetwork` only), `src/client/City/Scatter.luau` (walk solids only), `src/client/City/Ambient.luau` (birds only), `src/client/Controllers/AssetPreloader.luau` |
| prop-builder "homes" | `FabricHome*`, `FabricCamp*`, `Woods*` blueprints |
| prop-builder "trades" | `FabricCraft*`, `FabricMarket*`, `FabricCivic*` blueprints |
| prop-builder "sites" | `tools/assets/village_extras_kit.py`; `Site*`, `RevealScaffold`, `FabricFarm*`, `NoticeBoard`, `MeadowRock` blueprints |

- **Wave 1b:** mirror-engineer (`tools/cityfabric.py`, `plotrender.py`); economy-designer (sim
  timeline, streetplan PNG); then review, QA and docs.
- **Frozen:** everything else. In particular `Config/Eras/**`, `Economy.luau`, remotes, server
  services, and other eras' layouts and config blocks.

### Types (luau-engineer)

- New types: `FabricParcelSize`, `FabricParcel`, `FabricWild`, `FabricData`, `FabricPullConfig`,
  `FabricDistrictProps`, `FabricWildConfig`, `FabricClearConfig`, `FabricConstructionConfig`,
  `FabricMarkerConfig`, `FabricPadLookConfig` and `FabricConfig`. Each mirrors the JSON above
  exactly.
- `SlotLayout.district: string?`.
- `CityEraDressingConfig.fabric: FabricConfig?`.
- `CityBudgetConfig` gains `parcels`, `wild` and `wildFar`, all `number?`.
- `Catalog.GetFabric(eraName: string): Types.FabricData?`, nil-safe like the other getters.

## Done when (wave 1)

- Studio:
  - Buying a slot shows the reveal scaffold, then building sites around it, then buildings 10 to
    30 seconds later.
  - Levelling a landmark lets its neighbours grow taller.
  - The woods recede, and the next pad is dressed.
  - Other eras look exactly as today.
  - Missing props or data stay silent.
- `plotrender.py Village --tier N` matches the approved gate renders.
- Checks: stylua, selene, luau-lsp and `rojo build` are clean; `fabric.py check`, `streetplan.py`,
  `bake.py --list` and `gen_templates.py --check` are green.

## Wave 1c — Ben's first look (2026-09-29)

Ben on the gate renders: "looks really good! but i would love to see waaay more houses filling the
terrain and the trees placement seems to be lacking and the tree building seems silly right now,
maybe make it so it fills the city". He also pointed to the street-upgrade idea: some slots are not
buildings but change the city (`dirtRoad` = Pave the Road).

Rulings:
- **Way more houses.** Village gets **≥ 100 parcels** (was ≥ 40), filling the terrain between the
  streets: row 1 frontage, row 2 behind it, row 3 behind row 2. A finished Village keeps woods only
  as a thin border and the skirt.
- **The tree slot changes the city.** `treeOak` becomes `streetOnly`, like `dirtRoad`: there is no oak
  model. It is renamed "Plant Trees". Buying it plants town trees across the developed village.
- **A more natural forest.** No visible rows: variable spacing, clump scales, singles and round trees
  mixed in at the woods edge, and small glades.
- **More home variants,** so 100+ lots don't repeat.

Nothing is uploaded yet, so this round costs no extra harvest paste.

### Rows (CityFabric, normative; the mirror follows)

- `row` may be 1, 2 or 3; client validation treats any other value as a malformed parcel.
  - A row-k parcel (k ≥ 2) sets `front` to the index of the parcel directly in front of it (row
    k − 1), and repeats that parcel's `stretch` and `along`.
  - The data lists every parcel after its front, so one pass in index order works.
- Step 8 becomes: for every parcel with row ≥ 2, in index order,
  `level = max(0, min(level, levels[front] − rowLag))`. `district` and `governor` are copied from the
  front.
  - `rowLag` is `pull.rowLag`, optional; when absent it is 1.
  - Validation accepts a missing `rowLag`. A present one that isn't a non-negative whole number makes
    the pull block invalid, like any other bad pull field.
  - The mirror defaults it with an explicit None check, because Python's `or` treats 0 as missing.
- Contiguity (step 7) still applies to row 1 only.

### Order and budgets

- `fabric.py` writes all row-1 parcels first, ordered by straight-line distance from the entrance
  point (the first point of polyline 1). Then come row 2, then row 3, each in the order of their
  fronts.
- `budget.parcels` rises from 70 to **140** and applies to near plots.
- New `budget.parcelsFar` (**60**): far plots draw parcels with index ≤ `parcelsFar`, which is the
  row-1 frontage nearest the heart. A near plot draws index ≤ `parcels`.

### Town trees (new)

Fabric data gains an optional `trees` list:

```json
"trees": [
  { "x": 3.2, "z": -20.5, "rotationY": 40, "scale": 1.05, "variant": 1, "anchor": "stretch", "stretch": "L1_4" },
  { "x": 14.8, "z": 9.1, "rotationY": 200, "scale": 0.95, "variant": 2, "anchor": "parcel", "parcel": 57 }
]
```

- **Config:** `fabric.townTrees = { "requiresSlot": "treeOak", "props": ["TownTreeA", "TownTreeB",
  "TownTreeC"], "tierOffset": 3 }`. `budget.townTrees` is 70, near plots only, a prefix in index
  order.
- **Planted:** a tree is planted when `requiresSlot` is owned and its anchor is developed.
  - A `stretch` tree needs that stretch drawn.
  - A `parcel` tree needs that parcel at level ≥ 2, meaning the house is built.
- **Look:**
  - Its stage is `clamp(tier − tierOffset, 0, #stages − 1)`.
  - Its prop is `props[variant]` (1-based).
  - It stands at (x, 0, z), turned `rotationY` and scaled by `scale` (`Model:ScaleTo` about its base).
- **Placement, by `fabric.py`:**
  - street trees along the lanes, in gaps of the frontage;
  - yard trees in the gaps behind houses, anchored to the nearest parcel;
  - orchard trees near farm-district landmarks;
  - green trees near civic landmarks.
  - Every tree stays off the car and walker lanes and at least 1 stud from any parcel, slot
    footprint, pad and marker.
  - At full build, Village has **at least 50** planted trees.
- Trees don't clear woods and aren't walk solids.
- **Animation (client):** on the animated sync that buys `requiresSlot`, the planted trees appear as
  saplings in a stagger that spreads out from its pad, each with a dust puff (`maxPuffs` applies).
  Later growth steps swap stages with a pop. Unanimated syncs place the final state.
- A missing `trees` list, `townTrees` block or prop means that feature is off, silently.

### Client rulings (2026-09-29, after the wave 1c client report)

- **Planting-wave pace.** `townTrees.stagger` (optional; absent means `construction.stagger`)
  sets the planting wave's seconds per tree. Village uses 0.12, so about 70 trees plant in about
  8 seconds instead of 28.
- **Yard trees wait for their house.** A `parcel` tree's *final state* is unchanged (planted at
  level ≥ 2, so the mirror is unaffected). In animation it appears together with its house: when
  the building rises out of its site, not when the goal level changes.
- **City detail off** thins the town trees evenly by index to `detail.treeShare`, like the woods.
- **Walk solids** are the in-budget **row-1** parcels whose street is drawn. Back rows can never
  touch a walker lane, so this only removes work.
- **Far plots may show bare cleared patches** where developed parcels past `parcelsFar` are not
  drawn. `parcelsFar` is tuned after the Studio measurement.

### Review rulings (2026-09-29, wave 1c review; client and mirror follow)

- **Growth steps are staggered.** A stage change caused by a tier-up (trees and parcels) waits
  `stageSeconds + rank × stagger`, ranked by distance from the plot's last trigger, or else its
  entrance. `stagger` is `townTrees.stagger` for trees and `construction.stagger` for parcels, so a
  tier-up never pops 70 trees in one frame.
- **Stricter validation (final states, mirrored):**
  - `townTrees.tierOffset` must be a whole number; otherwise the town-tree block is off. The stage
    is `clamp(tier − tierOffset, 0, #stages − 1)` with no floor needed.
  - A row-k parcel (k ≥ 2) whose `front` is not an earlier index of a row-(k − 1) parcel is
    malformed: a blank that keeps its index.
- **Street-only slots are not walk solids.** Their layout rect still clears woods in the fabric
  mask; the client's walk clip matches streetplan's, which already skips them.
- **Back rows and walkers.** Back rows are not walk solids, so `fabric.py check` keeps every row-2
  and row-3 parcel at least walker offset + meander amplitude + clearance from any street (2.9)
  or spur (2.8).
- **A yard tree waits for its house only while a rise can still come.** That means the parcel's
  goal is a building that is not yet shown.

### Props (builders)

- **Town trees:** `TownTreeA` (round broadleaf), `TownTreeB` (orchard tree with fruit) and
  `TownTreeC` (tall narrow street tree).
  - Each has 3 stages: a staked sapling ≤ 2.5 studs, a young tree ≤ 5, and a full tree ≤ 8.
  - Planted trees are a green distinct from the forest conifers, never the teal nature-kit
    broadleaves.
  - Origin at the trunk base; blueprint scale is the builder's call.
- **Homes:** `FabricHomeSmallC`, `FabricHomeSmallD`, `FabricHomeMediumC` and `FabricHomeMediumD`,
  under the same rules as the other homes. The `home` district lists grow to four variants per size.

### Slot change (lead)

`Config/Eras/1_Village.json`, `treeOak`:
- `streetOnly: true`;
- name "Plant Trees";
- description "plants trees along the lanes, in the yards and on the green".

Cost, income, multiplier, `requires` and type are unchanged, so the economy is untouched. The layout
drops `treeOak`'s district: a `streetOnly` slot has no building to pull with.

### Ownership (wave 1c; resumed agents keep their files)

| Owner | Files |
|---|---|
| lead | this section; `CityDressing.json` (`rowLag`, budgets, `townTrees`, home lists); `Config/Eras/1_Village.json` (`treeOak` only) |
| economy-designer | `Village.luau`, `tools/fabric.py`, `tools/fabric/Village.plan.json`, `Config/Fabric/Village.json`, `tools/streetplan.py`; gate renders `m12c_*` |
| luau-engineer | `Types.luau` (the types for rows, trees and budgets), `CityFabric.luau` (rows) |
| ui-engineer | `Fabric.luau`, `CityDressingController.luau` (town trees, `parcelsFar`, validation) |
| prop-builder "sites" | `TownTreeA/B/C` (may extend `village_extras_kit.py`) |
| prop-builder "homes" | `FabricHomeSmallC/D`, `FabricHomeMediumC/D` |
| mirror-engineer (after the code and data land) | `tools/cityfabric.py`, `tools/testfit/plotrender.py` |

## Wave 1c, round 2 — denser lots (2026-09-29)

The first wave 1c pass placed 70 town trees but only **32 houses**, fewer than the 39 before.
Frontage is the bottleneck:
- lots must front a street, and back rows sit only directly behind a front lot;
- every landmark reserves its declared 9×9 (the keep 14×14) plus margins;
- the new street trees took frontage gaps.

Ben asked for the terrain to be filled with houses, so the lot model changes. The goal is **at least
70 houses at full build**, with no large empty lawn inside the town.

### Narrow terraced lots (contract change)

- **Size.** A third parcel size, `"narrow"`, with `fabric.sizes.narrow = [4, 6]`: 4 studs of
  frontage, 6 deep.
  - Narrow lots stand shoulder to shoulder along a street, like a terrace, with a gap of 0 to 0.2
    studs.
  - `smallMaxLevel` caps `"small"` only. A narrow lot may reach level 4: a tall, thin townhouse.
- **Props.** A district's props for a size may be missing. The parcel then uses the list for that
  size from `fabric.fallbackDistrict` (Village: `"home"`). A narrow lot's site is `sites.narrow`.
  `FabricDistrictProps.narrow`, `sizes.narrow` and `sites.narrow` are all optional; without them no
  narrow lot draws.
- **Validation.** `size` must be `"small"`, `"medium"` or `"narrow"`; anything else is a blank.

### Where lots go (`fabric.py`)

- **Infill.** A row-2 or row-3 parcel may stand anywhere in the block interior behind the frontage,
  not only directly behind its front. `front` is the nearest earlier parcel of row k − 1 on the same
  side of the same street, and the parcel repeats its `stretch` and `along`.
- **Measured landmark clearance.** Lots keep clear of each landmark's harvested extents: the union of
  all its stages, the same rects Scatter uses, plus 0.5, instead of the declared 9×9. Streets keep
  every existing rule. Pads, markers and spur strips keep their margins.
- **Houses get the frontage first.** Street trees take only leftover frontage gaps too short for any
  lot, and junction corners. The greens, orchards and yards carry the rest of the tree count (at least
  50 still apply).
- **Gaps.** At least 0.6 studs between lots of different sizes. Terraced narrow lots use 0 to 0.2.

### Props

| Prop | Size | Stages |
|---|---|---|
| `FabricHomeNarrowA`, `FabricHomeNarrowB`, `FabricHomeNarrowC` | 4×6 | 3: stage 0 ≤ 4.2, stage 1 ≤ 6.5, stage 2 ≤ 10.5 |
| `SiteNarrow` | 4×6 | 1, ≤ 6.5 |

- Narrow homes are 1 kit cell wide at the homes' scale (2.5). Their front faces the street. They read
  as a terrace when placed side by side: side walls may touch, and all garnish stays front and back.
- Three variants with different roofs and colours, so a row of five doesn't repeat.

### Ownership (round 2)

| Owner | Files |
|---|---|
| lead | this section; `Types.luau` (size, district and site types); `CityDressing.json` (`sizes.narrow`, `fallbackDistrict`, home narrow list, `sites.narrow`) |
| economy-designer | `fabric.py`, the plan, the generated data, `streetplan.py`; renders `m12d_*` |
| ui-engineer | `Fabric.luau`: size by key, narrow validation, district fallback, narrow site |
| prop-builder "homes" | `FabricHomeNarrowA/B/C` |
| prop-builder "sites" | `SiteNarrow` |
| mirror-engineer (after the code and data land) | `tools/cityfabric.py`, `plotrender.py` |

## Wave 1c, round 3 — city upgrade layers (2026-09-29)

Ben on round 2: "looks really good". The density is "perfecto", the alleys between narrow homes
are fine, and **yes**: Flower Bed and Banner Pole also become city-changers, like Plant Trees.

### Slots (lead, `Config/Eras/1_Village.json`)

Both slots become `streetOnly`, with a new name and description. Type, cost, income, multiplier
and `requires` are unchanged, so the economy is untouched. Both lose their `district`, because a
street-only slot has no building to pull with.
- `flowerBed` → "Plant Flowers": flower beds and planters across the village.
- `bannerPole` → "Hang Banners": banners along the streets and bunting across them.

### Generic upgrade layers (replaces `townTrees` and `trees`; nothing is released, so no migration)

**Config:** `fabric.upgrades` maps a layer name to
`{ requiresSlot, props, tierOffset, stagger?, budget }`:

```json
"upgrades": {
  "trees":   { "requiresSlot": "treeOak",    "props": ["TownTreeA", "TownTreeB", "TownTreeC"], "tierOffset": 3, "stagger": 0.12, "budget": 70 },
  "flowers": { "requiresSlot": "flowerBed",  "props": ["FlowerPlanterA", "FlowerBorderA", "FlowerBedA", "FlowerBedB"], "tierOffset": 0, "stagger": 0.08, "budget": 60 },
  "banners": { "requiresSlot": "bannerPole", "props": ["StreetBannerA", "StreetBannerB", "BuntingA"], "tierOffset": 0, "stagger": 0.15, "budget": 30 }
}
```

- `budget` is the near-plot cap for that layer, as an index prefix. `budget.townTrees` is removed.
- Layers draw on near plots only.
- A layer with a bad or missing field is off, silently. That includes a `tierOffset` that is not a
  whole number, or a `budget` that is not a non-negative whole number.

**Data:** `upgrades` maps a layer name to a list of entries. Each entry has exactly the old tree
shape: `{ x, z, rotationY, scale, variant, anchor: "stretch" | "parcel", stretch?, parcel? }`.

**Rules (normative, identical for every layer; the mirror copies them):**
- **Placed** when `requiresSlot` is owned and the anchor is developed: a stretch entry needs that
  stretch drawn; a parcel entry needs that parcel at level ≥ 2.
- **Stage** = `clamp(tier − tierOffset, 0, #stages − 1)`. Single-stage props always show stage 0.
- **Prop** = `props[variant]` (1-based). It is placed at (x, 0, z), turned `rotationY`, and scaled by
  `scale` with `Model:ScaleTo` about its base.
- Entries don't clear woods and aren't walk solids.
- City detail off thins every layer evenly by index to `detail.treeShare`.
- **Animation:** buying a layer's slot runs that layer's planting wave: stagger by that layer's
  `stagger`, spreading out from the slot's pad, with puffs (`maxPuffs` applies). Parcel-anchored
  entries appear with their house when a rise can still come. Later stage changes are staggered
  with a pop. Unanimated syncs and bulk restores place the final state.

**Placement (`fabric.py`):**
- **Flowers:**
  - planters in front of houses in the front setback, clear of the walker reach (at least 2.9 from
    a street centreline, 2.8 from a spur);
  - borders at lane corners and junctions;
  - beds around the greens, the square and civic landmarks.
  - At least 40 placed at full. Colourful but low: at most 1.5 studs tall.
- **Banners:**
  - `StreetBannerA/B` (a pole with a hanging banner, red or blue) along the high street and the
    square's lane, alternating sides, every 10–14 studs, clear of lanes and lots;
  - `BuntingA`, a string of pennants between two posts spanning the lane, at 3–5 spots on the high
    street and the square. Its posts stand outside the walker reach; the string crosses over the lane
    at 3 to 4 studs up. It is exempt from lane clearance, because it is overhead and nothing collides.
  - At least 15 placed at full.
- The existing tree rules move to `upgrades.trees`, unchanged.

### Props

| Prop | Builder | Rules |
|---|---|---|
| `FlowerPlanterA` | trades | a wooden planter box of flowers, ≤ 1 deep × ≤ 3 long, ≤ 1.2 tall |
| `FlowerBorderA` | trades | a long low flower border, ≤ 1.5 × 4, ≤ 1 tall |
| `FlowerBedA`, `FlowerBedB` | (existing) | the wave 2c greenery props, reused |
| `StreetBannerA`, `StreetBannerB` | sites | a wooden pole with a heraldic banner (red or blue with an emblem), ≤ 1 × 1 footprint, 5–6 tall |
| `BuntingA` | sites | two posts 8 studs apart along local X with a sagging string of 8–12 coloured pennants between them, the string's lowest point at 3.2+; origin at the midpoint |

- The castle-kit banner pieces may be used: this is the Banner slot's own effect.
- Keep everything single-stage and low-poly.

### Ownership (round 3)

| Owner | Files |
|---|---|
| lead | this section; `Types.luau`; `CityDressing.json`; `Config/Eras/1_Village.json` |
| economy-designer | `Village.luau` (districts), `fabric.py`, the plan, the generated data; renders `m12e_*` (flowers and banners before and after) |
| ui-engineer | `Fabric.luau` (generic layers), `CityDressingController.luau` (detail share for all layers) |
| prop-builder "trades" | `FlowerPlanterA`, `FlowerBorderA` |
| prop-builder "sites" | `StreetBannerA`, `StreetBannerB`, `BuntingA` |
| mirror-engineer (after the code and data land) | `tools/cityfabric.py`, `plotrender.py` |

### Review ruling (2026-09-30, rounds 2–3 review)

- **Unanimated spawns are spread over frames.** A far-to-near switch or a join places up to about
  290 fabric clones at once on a full Village. Unanimated spawns (parcels, layer entries, wild
  items) go through per-plot queues that together place at most `construction.spawnsPerFrame`
  (Village: 40) per frame across all plots: nearest plot first, and nearest to the camera first
  within a plot. Destroys stay immediate. Final states are unchanged,
  so the mirror needs no change.

# M12 wave 2 — Boomtown (2026-10-01)

Village is merged to `main` (Ben: "the village looks amazing"). Wave 2 is built in the worktree
`C:\Users\benja\Desktop\tycoon-m12` on branch `m12-boomtown`; `assets/` there is a junction to
the main checkout's `assets/`. Everything in "M12 contracts" above still holds and the code stays
era-generic.

## Wave 2.0 — Village chimney smoke and carts (regression from wave 1)

Village lost its wave 2c chimney smoke and parked carts: they hung off `lots` and `parking`, which
the fabric replaced. Bushes and hedges are **not** brought back as a separate layer: the Plant
Flowers layer and the houses' own garnish carry the greenery (lead's call, reported to Ben).

Client-only, as always: no server, remote, profile or economy change.

### Chimney smoke on fabric houses

**Config.** `ambient.smoke` gains two optional keys:

```json
"fabricProps": { "Village/FabricHomeMediumA": [[], [1.2, 5.9, 0.4], [1.2, 9.6, 0.4]] },
"every": 6
```

- `fabricProps` maps `"<Era>/<Prop>"` to a list indexed by **shown stage + 1**. Each entry is the
  chimney top `[x, y, z]` in the prop frame: studs, origin at the parcel centre on the ground,
  front −Z, exactly the frame `ambient.smoke.props` already uses for lot houses.
  - An entry that is not three finite numbers (`[]` by convention) means that stage has no
    chimney. A stage past the end of the list has none either.
- `every` is a whole number ≥ 1. Missing or invalid `fabricProps` or `every` turns fabric smoke
  off, silently.

**Rule (final state, normative; the mirror copies it).**
- Fabric smoke is active under exactly the wave 2c gates: `Ambient.Enabled()`, a near plot, the
  detail policy's `living` true, the era listed in `smoke.eras`, and `tier ≥ smoke.firstTier`.
- **Candidates** are the parcels whose 1-based index `i` satisfies `(i − 1) % every == 0` and
  `i ≤ budget.parcels`. Nothing else is ever a candidate, so one house changing never moves
  another's plume.
- A candidate **smokes** iff it shows a building (level ≥ 2) and
  `fabricProps[era .. "/" .. prop][stage + 1]` is a valid offset, for the prop and stage given by
  "What a parcel shows".
- The plume stands at the parcel's frame times the offset: pivot (x, 0, z), turned `rotationY`,
  then `CFrame.new(ox, oy, oz)`. It rises upright, as wave 2c plumes do (`Ambient.AddSmoke`).
- `rate`, `lifetime`, `size` and `color` are shared with the lot plumes.

**Lifecycle (client only, never mirrored).**
- A plume appears when the stage that carries it is actually shown: after the rise out of the
  site, or after the stage pop. A building site never smokes.
- When the shown prop or stage changes, the old plume goes and the new stage's plume (if any)
  is placed.
- A plume lives inside the house model, so it goes when the house does. Far plots, detail off and
  low-end devices have none; turning those back on restores them without a rebuild.
- Unanimated syncs place the final state.

**Mirror.** `tools/cityfabric.py` returns the final-state plume positions, and
`tools/testfit/plotrender.py` draws each as a scene-only puff (a few pale spheres rising from the
chimney), so a render shows which houses smoke.

### Parked carts: one more upgrade layer

No new client code. Carts are a `fabric.upgrades` layer whose slot is bought early:

```json
"carts": { "requiresSlot": "farmPlot", "props": ["CartParked"], "tierOffset": 0, "stagger": 0.3, "budget": 12 }
```

- **Data:** `upgrades.carts` in `Config/Fabric/Village.json`, laid by `fabric.py` from a new
  `carts` block in `tools/fabric/Village.plan.json`. **6 to 10 carts** at full build
  (`require.carts`), in two kinds:
  - *kerb carts*, stretch-anchored: beside a street, parallel to it, in frontage nothing else took;
  - *yard carts*, parcel-anchored: beside a farm, market or craft-district lot, so the cart arrives
    with its building.
- **Clearances** (`fabric.py check` enforces them, using `CartParked`'s harvested extents):
  - the body keeps the walker reach from every street centreline (2.9) and spur (2.8);
  - at least 0.5 from every parcel, landmark extent, pad, marker, lamp, the Sign, and every entry
    of the other layers; at least 1 from the plot edge;
  - at least 12 studs between two carts, and carts on at least three different streets;
  - every cart stands on land the clearing mask has always cleared by the time its anchor is
    developed (inside `clear.street` of its stretch, or inside `clear.parcel` of its parcel), so
    no cart ever stands in the woods.
- **Nothing else moves.** `parcels`, `wild` and the `trees`, `flowers` and `banners` lists stay
  byte-identical: carts are placed last, in what is left.
- The Village `parked` config block stays as it is and stays unused (the layout has no `parking`).

### Client decisions (ui-engineer, 2026-10-01; the mirror copies the final-state ones)

- **A valid offset is a list of exactly three finite numbers.** Only `"<Era>/<Prop>"` keys are
  read for `fabricProps`; a bare prop name is not accepted (unlike `smoke.props`).
- **A candidate must also be drawable:** well formed, with a footprint in `fabric.sizes`, and
  `i ≤ max(floor(budget.parcels), 0)`.
- **Plume position, plot-local,** with `a = radians(rotationY)`:
  `X = x + ox·cos a + oz·sin a`, `Y = oy`, `Z = z − ox·sin a + oz·cos a`.
- **"After the rise" means after the rise or pop animation ends** (about `riseSeconds` later).
  An emitter attached while the house is still scaling would stay displaced.
- **Fabric smoke does not need `smoke.props`;** lot smoke still does.
- **City detail off thins the carts to `detail.treeShare`,** like every upgrade layer. The wave
  2c parked carts were dropped entirely; the lead accepts the difference rather than fork the
  generic layer code.
- `Fabric.Context.smoke` carries the raw `ambient.smoke`; `Fabric.SyncInput.smoke` is the five
  gates, computed by the controller (`smokeFor`).

### Data rulings (economy-designer's report, 2026-10-01)

- **Carts shipped:** 8 at full build (3 kerb, 5 yard), 0 / 2 / 2 / 4 / 8 by tier, drawn at scale
  0.85 to 0.95 (the plan's `carts.scale`): at full size only one kerb gap survives.
- **The clearing rule, as `check` enforces it.** A whole cart body cannot lie inside
  `clear.street` or `clear.parcel` (a kerb body spans 2.9 to about 5.0 studs from the centreline).
  So: the cart's *position* is inside its anchor's margin, and its *body* touches no wood disc
  (`quarterRadius`, `singleRadius`) that the anchor alone would leave standing. Both depend only
  on the anchor, so they hold in every ownership state.
- **Chimneys today.** Measured from the kit GLBs: most homes only gain a chimney at their last
  stage, and 93 of the 116 lots are narrow homes whose chimney arrives at stage 2 (level 4). So
  with the models as uploaded, **no house smokes before tier 5** (13 plumes at full with `every`
  1). The two camp props smoke from their fire pits (the lead keeps those entries).
- **Open, Ben's call:** give `FabricHomeNarrowA/B/C` a chimney from stage 0. That is a blueprint
  change and a re-upload, which would ride the Boomtown harvest paste; `every` is then re-tuned
  to about 7 or 8 (4 plumes at tier 2, 13 to 16 at full). Until then `every` stays 1 and the
  offsets describe the uploaded models exactly.

### Review rulings (2026-10-01, wave 2.0 review: 0 Critical, 1 Major, 5 Minor)

- **Major, accepted with a caveat: this branch's Boomtown is not today's Boomtown.**
  `eras.Boomtown.road.width` 6 and `pedestrians.offset` 3.35 are live for the current layout,
  whose uploaded path meshes are still 8 wide: lanes, lamps, signals and walkers move inward and
  `py tools/paths/bake.py --era Boomtown --list` is red. The lead keeps the values, because both
  layout candidates are generated against them and the re-bake lands with the chosen layout in
  wave 2.2. Until then **nobody judges Boomtown in Studio on `m12-boomtown`**, and the branch does
  not merge to `main`. The Village fix can still go to `main` on its own if Ben wants it sooner,
  but not as a clean cherry-pick range: `7c6e49f` also carries the (inert) Boomtown `fabric`
  block, `60a5e6a` sits between the fix commits, and the review fixes in `a6cf170` were written
  on top of `80bfb78`. Port it file by file (the wave 2.0 client files, `Fabric/Village.json`,
  the Village plan, the `carts` and `ambient.smoke` config keys, the mirror), leaving
  `eras.Boomtown.road.width` and `pedestrians.offset` at their `main` values.
- **Smoke and carts depend on the Well and on houses, not on the tier as such** (docs-keeper,
  from the mirror): the 11 house plumes need the Well at level 50 and tier ≥ 3; the two camp
  fire pits are governed by the Watchtower and smoke from the Town Wall (purchase 23); the first
  cart arrives with the Cottage (purchase 9), not when the Farm Plot is bought. The greedy
  timeline's 0 plumes through tier 4 is a pacing fact, not a rule.
- **The plume uses the stage that actually stands.** If a template lacks the wanted stage,
  `PropFactory` falls back to a lower one; the chimney top is then that stage's entry, or none.
  With every stage present the final state is unchanged.
- **Carts: at least `require.carts` (6), within the layer's `budget` (12).** The "6 to 10" above
  is the laid count today (8), not a checked ceiling.
- **`budget.plumes` (20) is a tools-only gate:** `py tools/cityfabric.py timeline <Era>` fails
  when any tier or the full build shows more fabric plumes. `every` is the only limiter in the
  client, so a chimney change must retune `every` in the same commit.
- `ambient` is type-guarded everywhere it is read.
- **Noted for wave 2.2:** with the marker exempt from its own slot's path, a marker can stand on
  the freshly drawn path for the pad's 0.5 s grace after a purchase.

### Ownership (wave 2.0, disjoint)

| Owner | Files |
|---|---|
| lead | this section; `CityDressing.json` `eras.Village.fabric.upgrades.carts` |
| economy-designer | `tools/fabric.py` (carts), `tools/fabric/Village.plan.json`, `Config/Fabric/Village.json` (generated), `CityDressing.json` **only** `ambient.smoke.fabricProps` and `ambient.smoke.every` |
| ui-engineer | `src/client/City/Fabric.luau`, `src/client/Controllers/CityDressingController.luau`, `src/client/City/Ambient.luau`, `src/shared/Types.luau` (`SmokeConfig.fabricProps`, `SmokeConfig.every`, both optional) |
| mirror-engineer (after both land) | `tools/cityfabric.py`, `tools/testfit/plotrender.py`; renders `assets/testfit/out/Village/m12f_*` |

### Done when (wave 2.0)

- A near Village shows a plume on every house whose shown stage has a chimney (with the models
  as uploaded: 13 at full build and none before tier 5, see "Data rulings"), and carts beside the
  lanes and the farm and market lots once the farm is bought.
- `py tools/fabric.py check Village`, `py tools/cityfabric.py selftest` and
  `py tools/streetplan.py Village` are green; stylua, selene, luau-lsp and `rojo build` are clean.
- Before and after renders exist for Ben: `m12f_before_*.png`, `m12f_after_*.png`.

## Wave 2.1 — Boomtown growth-layout mock (a gate for Ben, not yet a contract)

Ben judges looks only on renders, and a mock comes before contracts. This wave produces **two
candidate street plans** for Boomtown, each as a real layout run through the real generator and
the real mirror, so the pick becomes wave 2.2's starting point with nothing thrown away.

- **Candidate "grid":** a period-correct 1950s Main Street grid. Straight streets at right
  angles, Main Street on the entrance axis, numbered side streets.
- **Candidate "organic":** the Village treatment. A Main Street that bends, side streets at
  natural angles, curving suburban closes.

### What both candidates share

- **Untouched:** the 24 slot ids, their order, config and models (`Config/Eras/2_Boomtown.json`
  is frozen). Only positions, rotations, spurs, streets and client dressing change.
- **The growth rules of mock B** (`docs/CITY_GROWTH.md` §2.5): one heart at the entrance, slot k
  roughly k-th in street distance from the entrance, frontage reserved between landmarks, the plan
  a **tree** (roads grow with buildings as a shortest-path tree, so every side street is a dead end
  that a landmark's path grows).
- **Seed:** Main Street's mouth at the entrance. Shops fill the gaps between the storefront
  landmarks until Main Street is one continuous frontage; suburbs spread down the side streets;
  industry gathers by the service lanes; farmland covers everything else and retreats.
- **"Lower, wider"** (Ben, era-kits ruling): filler never rises above its landmark, and only the
  Fire Station, Radio Station and Clock Tower are tall.
- **Districts** (a key per slot in the layout; the layout owner may move a slot between districts
  and says why): `main` (Main Street shops), `suburb` (houses), `industry` (sheds, yards),
  `civic` (greens, small parks). Boomtown has no house landmark, so the landmarks that stand out on
  the side streets carry `suburb`.
- **Street upgrades stay street upgrades:** `paveMainStreet`, `streetlampRow` and `trafficLights`
  are `streetOnly`; their pads stand beside the street on ground nothing else uses (the Village
  `dirtRoad` pattern: a one-point spur, no district).
- **City-changer candidates are not decided:** `fireHydrant`, `billboardSign`, `neonDistrict` and
  `busLine` keep their models and get ordinary positions in the mock. Ben decides after the gate.
- **Wild land is farmland:** crop fields in a patchwork, hay, fences, telegraph poles, and a
  farmstead (barn and silo) in the landscape band past the plot edge. A field is a fabric
  `clump`: four quarter-fields of one design, cleared quarter by quarter as the town spreads.
- **Density:** Ben wants the terrain filled ("waaay more houses"; 116 on Village was "perfecto").
  Frontage is the bottleneck, not land: use terraced `narrow` shop lots on Main Street, back-row
  infill and measured landmark extents. Target **at least 90 lots** at full build, with building
  sites visible at every tier.
- **Stand-in models.** The real fabric props come in wave 2.3, with strips for Ben. The mock uses
  the existing Boomtown filler (`HouseA`–`HouseF`, `ShedA`, `ShedB`) plus draft props.

### Groundwork rulings (lead, 2026-10-01, after the generator and prop drafts)

- **Lot sizes:** small 6 × 6, medium 8 × 8, narrow 5 × 8. Suburb lots are mostly small: fabric
  homes are built at a smaller kit scale than the landmarks, as on Village, so a kit bungalow fits
  a 6 × 6 lot. Narrow lots are terraced Main Street shops.
- **Road width 6** (was 8), with `pedestrians.offset` 3.35. The cars were halved in wave 2d, so
  an 8-stud road is oversized, and frontage and block depth are what limit the lot count. Shown to
  Ben in the gate renders; a config value, easy to put back.
- **Density:** with 8-stud roads and 9 × 9 house lots a 120-stud plot holds 55 to 70 lots. 90 is
  the target the candidates report against; what binds is frontage, not land.
- **Field-pattern wild** (`plan.wild.pattern: "fields"` in `tools/fabric.py`): fields on a square
  grid at scale 1 and in quarter turns, crops chosen by low-frequency noise so neighbours share a
  crop, a fallow share that holds the singles, fields continuing into the skirt, and skirt
  landmarks from a plan list. `Windbreak` is skirt-only: one clearing point cannot cover its three
  trunks. A plan without `pattern` lays woods exactly as before.
- **A pad marker is exempt from its own slot's path** in `fabric.py check`: the marker exists only
  while the pad does, and the path is drawn only after the purchase.
- **A fabric era has no street-furniture exemptions** in `streetplan.py`: every pad and footprint
  rule applies to `paveMainStreet`, `streetlampRow`, `trafficLights`, `fireHydrant` and the
  monument too, because their pads now stand beside the street.
- **Layout facts** (generator's report): entrance at (0, −54.5); street points within ±55; a slot
  centre sits 16 studs from the centreline it faces; pads at least 5 from every centreline; a
  landmark join at most about 40 studs from the next along a street, or the lots between them
  never develop; lots are only laid on stretches some landmark's path draws.
- **Far plots** draw whole fields only, so they never show the farmstead or the wind pumps.

### Gate renders (`assets/testfit/out/Boomtown/`)

For each candidate `<c>` in `grid`, `organic`: `m12b_<c>_tier1.png`, `m12b_<c>_tier3.png`,
`m12b_<c>_full.png`, `m12b_<c>_full_entrance.png`; and one sheet `m12b_compare.png` with today's
Boomtown and both candidates at tier 1, tier 3 and full.

### Ownership (wave 2.1)

| Owner | Files |
|---|---|
| lead | this section; `CityDressing.json` `eras.Boomtown.fabric` (schema and first values) |
| economy-designer (groundwork) | `tools/fabric.py` (field-pattern wild, any Boomtown-only generator rule), `tools/streetplan.py`, `CityDressing.json` `eras.Boomtown.fabric` values |
| prop-builder "farmland" | `tools/assets/farmland_kit.py` (new), draft blueprints under `tools/testfit/blueprints/_props/Boomtown/` (new files only) |
| layout-designer "grid" (own worktree `tycoon-m12-grid`) | `src/shared/Layouts/Boomtown.luau`, `tools/fabric/Boomtown.plan.json`, `Config/Fabric/Boomtown.json`, renders `m12b_grid_*` |
| layout-designer "organic" (own worktree `tycoon-m12-organic`) | the same files in its worktree, renders `m12b_organic_*` |

Frozen: every server file, remotes, `Config/Eras/**`, `Economy.luau`, the other eras' layouts
and config blocks, and the client (the code is generic; a candidate that needs a client change
reports it instead).

## Wave 2.2 — Boomtown: the organic layout, city-changers, narrow driveways (Ben, 2026-10-01)

Ben's answers at the mock gate:
1. **Organic** ("organic looks better"), with the bolder pass the lead proposed.
2. **All four candidates stop being a sole building:** `fireHydrant`, `billboardSign`,
   `neonDistrict` and `busLine` become city-changers.
3. **Roads stay 6 studs wide.**
4. **Yes** to chimneys from the first stage on the three narrow Village homes.
5. His PLAYTEST step-37 numbers are still owed; budgets stay as they are until they arrive.

The organic candidate is merged into `m12-boomtown` (20df3ed) and is the starting point.

### Slots (lead, `Config/Eras/2_Boomtown.json`, applied)

The four slots are `streetOnly`. Type, cost, income, multiplier, `requires` and `modelName` are
unchanged, so the economy is untouched (`sim_economy.py`: 16:20:04, legacy 887, as before).

| Slot | Name | What buying it does |
|---|---|---|
| `fireHydrant` | Install Fire Hydrants | red hydrants along every drawn street |
| `billboardSign` | Put Up Billboards | billboards by the roads and behind the shop rows |
| `neonDistrict` | Light the Neon District | a neon sign in front of every Main Street shop, neon arches over Main Street |
| `busLine` | Open the Bus Line | bus shelters along the streets, and buses among the traffic |

In the layout each of the four gets a pad beside a street on ground nothing else uses, a
one-point spur and no `district` (the `dirtRoad` pattern).

### Upgrade layers (`eras.Boomtown.fabric.upgrades`, config applied; generic rules unchanged)

| Layer | `requiresSlot` | Props | Entries | At full build |
|---|---|---|---|---|
| `parked` | `gasStation` | `ParkedA`, `ParkedB`, `ParkedC` (entry `scale` 0.5) | kerb bays beside streets (stretch) and driveways beside homes (parcel) | 10 to 16 |
| `hydrants` | `fireHydrant` | `Hydrant` | stretch-anchored, on the lamp line between the walkers and the lots, every 12.5 to 14 studs, on either side (`check` enforces 8 apart and the minimum) | at least 20 |
| `busStops` | `busLine` | `BusStopA` | stretch-anchored kerbside shelters facing the street, on at least three streets | 4 to 8 |
| `billboards` | `billboardSign` | `BillboardA`, `BillboardB` (roadside), `BillboardC` (large) | stretch-anchored: street ends, the plot edges facing a street, gaps behind the shop rows | at least 8 |
| `neon` | `neonDistrict` | `NeonSignA`, `NeonSignB`, `NeonSignC`, `NeonArch` | a sign at the front edge of every terrace-street shop lot (parcel-anchored); 2 or 3 arches over Main Street (stretch-anchored; posts outside the walker reach, the span at least 4 studs up, exempt from lane clearance like the Village bunting) | at least 15 |

- `parked` is the wave 2c parked cars, back as a layer (the layout dropped `parking`). The
  gas station is the 4th purchase, so cars arrive early.
- Clearances are the cart rules, with each prop's footprint from the plan (`footprints`) until
  it is harvested: the walker reach from centrelines and spurs; 0.5 from parcels (a neon sign and
  a driveway car may stand inside their own lot's front or side margin, as planters do), from
  landmark extents, pads, markers, lamps, signals and every other layer's entries; 1 from the plot
  edge.
- `fabric.py` lays every layer from a plan block of the same name, and `check` enforces the
  minimums through `require.<layer>`. Each layer has its own random stream, in the order of the
  table, after the parcels and the wild.

### Buses in the traffic (`vehicles.unlocks`, new; ui-engineer)

```json
"vehicles": { "unlocks": [ { "slot": "busLine", "props": ["VehicleBus"], "share": 0.15 } ] }
```

- While `slot` is owned, each of the plot's vehicles takes a prop from `props` with probability
  `share`, decided by a seeded draw per vehicle index from a stream of its own, so the other
  vehicles keep the props they had. At least one vehicle is a bus once the plot has any vehicle.
- `scale`, speed, lanes and budgets are the plot's ordinary vehicle values. A missing prop or a
  malformed entry means that unlock is off, silently. `VehiclesConfig.unlocks` is optional.
- The mirror draws the same picks in `plotrender.py`.

### Narrow driveways (`road.paths.spurWidth`, new)

- `eras.<Era>.road.paths.spurWidth: number?`, in studs. Absent means `road.width`, so Village is
  unchanged and `py tools/paths/bake.py --era Village --list` stays green. Boomtown: **3**.
- It is the width of every drawn spur (a landmark's path from its join to its slot): the baked
  `SP_<slotId>` pieces (fill and rim) and the parts fallback. The clearing mask's spur segments
  keep `clear.street`, as today.
- Walk lanes on a spur keep the same distance from the edge as on a street:
  `offset − (road.width − spurWidth) / 2`. Vehicles keep to the streets wherever a spur is narrower
  than the road.
- `streetplan.py` and `fabric.py` take a spur strip's half-width from `spurWidth`; the plan's
  `spur` clearance follows.
- The spur's mouth still runs to the street's centreline, hidden by the planar UVs as today.
- Mirrored by `tools/paths` (network, bake), `plotrender.py` and `streetplan.py`. `bake.py --list`
  must agree with the client for both eras.

### Layout, bolder pass (layout-designer, in `tycoon-m12-organic`, then merged)

- `fabric.marker.offset` is now `[5.3, 0, -0.5]` (config applied), which clears a pad at any
  slot rotation: **landmarks turn to face their streets**, and streets may leave the crossroads
  at natural angles.
- Keep: Main Street in from (0, −54.5), the Clock Tower closing it, a tree, slot k roughly k-th
  from the entrance, the lot arithmetic that made 101.
- Change:
  - **Industry out of the foreground.** The service road goes to the east or back side; the front
    of the plot, nearest the hub, is Main Street's mouth and houses.
  - **A civic green:** `PlazaA` beside or in front of the Clock Tower.
  - **More Main Street:** at least 20 terraced shop lots; a second terrace street is fine.
  - **Fewer backs to the camera:** landmarks face −Z or sideways where their street allows.
  - The four city-changer slots lose their building sites; 17 landmarks remain to pull.
- Targets: **at least 95 lots** (floor 90), sites at every tier, and a tier 4 → full jump no
  larger than today's.

### Village chimneys (prop-builder; config by the lead after measuring)

`FabricHomeNarrowA/B/C` (Village) gain a chimney from stage 0, raised with each storey.
`ambient.smoke.fabricProps` gets the new per-stage tops and `ambient.smoke.every` becomes 7 in the
same commit (`budget.plumes` 20 gates it). The three props' stages are re-uploaded with the
Boomtown batch: clear their `modelAssetId` and `parts` through `assets_config.save_assets` first,
because `upload_models.py` skips a non-zero id.

### Boomtown props, final (wave 2.3; strips to Ben before any upload)

Heights are measured against the landmarks (a City Kit storey is 1.6 studs at scale 4).

| Props | Lot | Stages |
|---|---|---|
| `FabricShopNarrowA/B/C/D` | 5 × 8 | 3: 2.3 / 3.4 / 4.5; roof detail and finished side walls |
| `FabricHomeSmallA–F` | 6 × 6 | 2: ≤ 3.4 |
| `FabricHomeMediumA/B` | 8 × 8 | 3: ≤ 2.2 / 2.4 / 3.7 |
| `FabricWorksSmallA/B` | 6 × 6 | 2: shed and yard → workshop, ≤ 3.4 (replace the `ShedA/B` stand-ins) |
| `FabricWorksMediumA` | 8 × 8 | 3: ≤ 5.8 |
| `FabricCivicSmall`, `FabricCivicMedium` | 6 × 6, 8 × 8 | 2 and 3: a green → a small park with a feature |
| `SiteSmall/Medium/Narrow`, `RevealScaffold`, `LotSign` | | 1 |
| `FieldClumpA/B/C`, `FieldQuarterA/B/C`, `PastureClump`, `PastureQuarter` | clump, quarter | 1 |
| `HayBale`, `PrairieTree`, `TelegraphPole`, `Windbreak`, `Farmstead`, `Windpump` | single | 1 |
| `Hydrant`, `BusStopA`, `BillboardA/B/C`, `NeonSignA/B/C`, `NeonArch`, `VehicleBus` | layer props | 1 |

- `PastureClump` is a fenced grass paddock with the same quarter geometry as a field, so a
  fallow cell reads as pasture, not bare dirt.
- `VehicleBus` is built like `VehicleA–C` (same scale convention, front −Z).
- Filler never copies a landmark's silhouette and stays plainer and lower than the landmarks.

### Ownership (wave 2.2, disjoint)

| Owner | Where | Files |
|---|---|---|
| lead | base | this section; `Config/Eras/2_Boomtown.json`; `CityDressing.json` schema and first values; merges; pipeline runs |
| economy-designer "generator" | base (`tycoon-m12`) | `tools/fabric.py`, `tools/streetplan.py`, `tools/fabric/Boomtown.plan.json` (layer and field blocks only, until the layout merges), `CityDressing.json` `eras.Boomtown.fabric` values |
| layout-designer | `tycoon-m12-organic` | `src/shared/Layouts/Boomtown.luau`, `tools/fabric/Boomtown.plan.json` (`parcels`, `require`, `seed`, `wild.grid`), `Config/Fabric/Boomtown.json`, `eras.Boomtown.fabric.pull` |
| ui-engineer | base | `src/client/City/RoadGraph.luau`, `PathRibbon.luau`, `Traffic.luau`, `Walkers.luau`, `src/client/Controllers/CityDressingController.luau`, `AssetPreloader.luau`, `src/shared/Types.luau` |
| mirror-engineer | base | `tools/paths/**`, `tools/cityfabric.py`, `tools/testfit/plotrender.py`, `plotscene.py` |
| prop-builders | base | new and changed blueprints under `tools/testfit/blueprints/_props/{Boomtown,Village}/`, `tools/assets/{farmland,boomtown_extras}_kit.py`, a new `tools/assets/boomtown_street_kit.py` |

### Rulings after the wave 2.2 reports (lead, 2026-10-01)

- **Laying order is the plan's `layers` list, pickiest first:** `busStops`, `billboards`,
  `parked`, `neon`, `hydrants`. In the table's order the cars and hydrants took the few
  shelter-sized gaps. Each layer still has its own random stream.
- **Small kerbside posts may lean into a lot's front.** The corridor between the walkers' reach
  (3.95) and the lot fronts (4.5) is 0.55 wide, so `check` lets a stretch-anchored entry no larger
  than 1 x 1 lean up to 0.6 into the front of the lot it stands before (hydrants 0.37, arch posts
  0.3). Shelters, cars and billboards get no allowance.
- **A billboard behind a shop row is parcel-anchored** to the lot it stands behind and rises with
  it; roadside boards stay stretch-anchored.
- **"Stands on cleared land" is checked for carts and the five Boomtown layers.** Village's trees,
  flowers and banners keep their own rules.
- **Plan keys** (`tools/fabric/<Era>.plan.json`): `layers` (laying order), `footprints` (a prop's
  ground size until it is harvested; a span lists its posts), one block per layer with `placers`
  of kind `kerb` (modes `gaps`, `spaced`), `lotFront`, `driveway`, `span`, `ends`, `edges`,
  `backs`; `parcels.keepClear` (rectangles the lots stay off, to hold a gap for a shelter);
  `parcels.infill.frontReach`; `parcels.terraceFill`; `wild.fallow.paddock` (the share and caps of
  fallow cells that become pasture).
- **`heightFloor` is 3.4:** every first and second stage is free; the tall last stages (shop 4.45,
  civic medium 4.42, medium works 5.39) wait for their landmark.
- **The spur rules apply only when `spurWidth` is set** (a positive finite number, no
  `road.tiles`): spur fillet radius and minimum leg scale with it, walk lanes on a spur run at
  `max(offset - (W - S)/2, 0)`, and no spur carries a vehicle lane. An era without the key keeps
  every earlier rule, so Village and Metropolis do not move.
- **The bus draw:** one stream `Seed(plotIndex, era) + 7007`; for each unlock in config order and
  each vehicle index, draw `roll` then `pick`; an unlock takes vehicle i when `i == j` (its own
  position in the list, which forces at least one bus) or `roll < share`. Python cannot reproduce
  Roblox's picks, so renders show the rule, not the game's exact cars.
- **`bake.py --list` exit codes:** 0 all agree; 1 client and bake disagree, or a mesh folds
  visibly; 2 they agree but the meshes on disk are stale. A real bake refuses a visible fold.
- **The marker at 5.3 costs about a stud of frontage per landmark** (96 lots on the first organic
  layout, was 101). Accepted: it is what lets landmarks turn.
- **The smoke config runs ahead of the uploaded Village models** from this commit until the
  harvest: `fabricProps` lists stage-0 chimneys the templates do not have yet.

### Review rulings (2026-10-01, wave 2.2 review: 0 Critical, 1 Major, 10 Minor)

- **Major, fixed: lane holds count both vehicles' lengths.** A lane is free for a vehicle once the
  one ahead has moved its own half-length plus `followGap` plus the follower's half-length, so a
  bus never enters a lane inside the car ahead; `Traffic.Swap` re-claims the lane at the new
  length. Equal lengths behave as before.
- **A placer that lays nothing, or a layer prop no entry uses at full build, is a `check`
  violation** (unless the plan marks the placer `optional`). `BillboardC` now stands behind the
  shop rows, parcel-anchored.
- **Driveway details:** the reveal dust is sized by the piece's own width; spur curves are sampled
  `spurWidth` apart; the meander taper also scales with `spurWidth` (client and mirror agree).
  Row lamps and tree keep-outs still measure a driveway at road width, in client and mirror alike.
- **Unlocks read the sticky owned set,** so a cosmetics refresh does not flick buses to cars.
- **The preloader loads only what an era can spawn:** for a fabric era, the props its fabric
  config names plus the features that still run. Boomtown's `houses`, `trees`, `greenery` and
  `parked` config blocks and the `Boomtown/House*` smoke entries are now unread, like Village's
  `parked`; they stay until the old filler props are retired from `Assets.json`.
- **Open until Ben's step-37 numbers:** far Boomtown plots draw only 45 of 85 fields (`wildFar`),
  so a tier-0 far plot shows its hub-side fields bare. The fix is a larger or per-era far budget.
- **The harvest moves the generator's inputs:** plan `footprints` give way to harvested extents,
  so the harvest commit rebuilds `Fabric/Boomtown.json` and re-runs the gates.
- **Fewer than before, by layout:** `streetlampRow` gives 8 lamps (spacing 24 on 314 studs) and
  `trafficLights` 2 signals (the plan has two crossroads).
- **On this branch before the upload:** Boomtown's fabric props have no templates, so its plot
  shows landmarks, parked cars and Parts roads only; Village's early plumes rise over chimney-less
  roofs. Nobody judges either in Studio until the harvest.

### Done when (wave 2.2 gate, renders for Ben)

- `assets/testfit/out/Boomtown/m12c_{tier1,tier3,full,full_entrance}.png` from the merged
  branch, a before/after pair for each city-changer layer, and a strip for every final prop.
- `fabric.py check`, `streetplan.py`, `cityfabric.py selftest` and `timeline` are green for
  Village and Boomtown; `bake.py --list` agrees with the client for both eras (Boomtown stays
  "stale mesh" until the re-bake that follows Ben's approval); stylua, selene, luau-lsp and
  `rojo build` are clean.

## Wave 2.4 — back lanes: every house on a road (Ben, 2026-10-01)

Ben at the second gate: "it seems good, but the fact that the houses are not connected to any road
bothers me, can we create at least smaller roads that lead to the houses and connects them between
them?" About 70 of Boomtown's 102 lots are back-row infill with no road. Ruling: the props and the
street plan stand; block interiors get **lanes**.

Client-only, as always. Streets, slots, pads and landmark paths do not move, so the baked path
pieces are unaffected.

### The idea

- A **lane** is a small road, 3 studs wide, that leaves a street through a gap in the frontage and
  runs into the block. Lots line it on both sides and face it. Two lanes may meet in the middle of
  a block, which connects two streets.
- **Every lot of row 2 or 3 fronts a lane.** No lot stands in a block interior without one.
- A lane **grows with its houses**: it is drawn from its mouth as far as the farthest lot on it
  that has at least a building site.
- Lots deeper along a lane develop later, so a lane fills from the street inward and its far end
  shows building sites.

### Fabric data (`Config/Fabric/<Era>.json`)

```json
"lanes": [
  { "points": [[12.0, -27.6], [12.0, -14.0], [20.5, -14.0]], "stretch": "L2_3", "along": 12.4 }
],
"parcels": [
  { "x": 14.9, "z": -20.0, "rotationY": 90, "size": "small", "stretch": "L2_3", "along": 12.4,
    "row": 2, "front": 31, "lane": 1, "laneAlong": 7.6 }
]
```

- `lanes` is optional. Lane `k` is its 1-based index. `points` is a polyline of 2 to 4 points in
  plot coordinates; the first is the **mouth**, on the centreline of the street the lane leaves.
  `stretch` and `along` are the mouth's address on that street, as for a parcel.
- A parcel may carry `lane` (a lane index) and `laneAlong` (studs along the lane from the mouth to
  the foot of the perpendicular from the lot's front-centre). It is then a row-2 or row-3 lot whose
  `stretch` and `along` are the lane's, and whose `front` is the row-1 lot nearest the mouth, as
  the infill rule already requires. Its `rotationY` faces the lane.
- A parcel with a malformed `lane` or `laneAlong` is a blank that keeps its index. A malformed lane
  is not drawn and its lots are blanks.

### `CityFabric.Develop` (normative change; the mirror follows)

Step 3 gains one rule: **a parcel with `lane` adds its `laneAlong` to its distance from every
landmark** (`d = min(...) + laneAlong`). Everything else is unchanged: contiguity is still row 1
only, and a back-row lot's level is still capped by its front's.

New pure function, mirrored one to one:

```lua
CityFabric.LaneReach(lane: Types.FabricLane, laneIndex: number, parcels: { Types.FabricParcel },
	levels: { number }, sizes: { [string]: { number } }, budget: number): number
```

- The lane's length is the sum of its legs (`sqrt`, never `hypot`).
- Its reach is the largest `laneAlong + frontage / 2` over its lots with `level ≥ 1`, where
  `frontage` is `sizes[size][1]`, capped at the length; 0 when no lot has a site yet.
- Lots are visited in index order; only in-budget, well-formed lots count.

### Drawing a lane (client `Fabric.luau`; the mirror copies the final state)

- Near plots only. A lane is drawn from its mouth to its reach when the reach is above 0.
- **Shape:** width `fabric.lanes.width`; a rim `fabric.lanes.rim` wider on each side; a disc of the
  same width at every interior point and at the growing tip. Tops: fill at `fabric.lanes.fillHeight`
  and rim at `fabric.lanes.rimHeight` above the plot, both **under** the street's fill
  (`paths.fillHeight` 0.07) so the street covers the mouth, and the lane's fill **over** the
  street's rim (`paths.rimHeight` 0.02) so no kerb line crosses the mouth.
- **Surface:** the plot's live street surface. In the baked renderer the fill and rim carry the
  same images as the baked pieces (the fill and rim textures of the current surface variant) as
  `Texture` instances tiled every `paths.tileStuds` studs and offset so that they line up in plot
  coordinates, as the baked pieces' planar UVs do; when the variant changes (Pave Main Street), the
  lanes change with the streets. Without those images (the parts renderer, a missing asset) the
  lane takes the road's live material and colour, the rim a darker shade.
- **Instances:** anchored Parts; `CanCollide`, `CanQuery`, `CanTouch` false. One fill and one rim
  per leg, resized as the reach grows, so a lane never adds parts per house.
- **Animation:** on an animated sync on a near plot the lane extends to its new reach over
  `fabric.lanes.growSeconds` with one dust puff at the tip (`maxPuffs` applies). Unanimated syncs
  and restores place the final state.
- **Clearing mask:** every drawn lane leg is a segment with margin `clear.lane`.
- Lanes are not walk solids and carry no walk or vehicle lanes. Walkers on the street cross a lane
  mouth as open ground.
- A missing `lanes` list or `fabric.lanes` block means no lane is drawn, silently; the lots still
  develop.

Config (`eras.Boomtown.fabric`, lead-applied):

```json
"lanes": { "width": 3, "rim": 0.4, "fillHeight": 0.05, "rimHeight": 0.02, "growSeconds": 0.5 },
"clear": { "lane": 2.0 }
```

### Generator (`tools/fabric.py`, plan block `parcels.lanes`)

- Lays lanes in every block interior that can hold at least three lots: straight, or with one or
  two bends; from a mouth on a drawn street; two lanes may meet end to end.
- A mouth is a gap in the row-1 frontage as wide as the lane and its rims, with no kerb-side layer
  entry, lamp or signal in it, and clear of crossings.
- Lots line each lane on both sides, fronts `parcels.lanes.setback` from its centreline, facing it,
  with the usual gaps. Sizes are small, with a medium now and then.
- **No lot of row 2 or 3 is laid without a lane.** `rows` and `infill` keep their meaning for
  Village, whose plan has no `lanes` block and must build byte-identical.
- Lanes keep clear of landmark extents, pads, markers, spur strips, the plaza, other lanes (except
  where two meet) and the plot edge.
- The layer placers treat a lane as a street for their clearances; driveway cars may stand beside
  lane lots.
- `check` enforces: the rules above; every `laneAlong` within its lane's length; every lane lot's
  front within 0.5 of the lane's setback line; at least two lots per lane; every lane lot reaches
  level 2 at full build (no lane to nowhere); `require.parcels`.
- **Targets:** at least 95 lots (floor 90), at least 20 terraced shops kept, building sites at
  every tier, and a tier 4 → full jump no larger than 15. `pull` may be re-tuned for the added
  lane distances.

### Ownership (wave 2.4, disjoint)

| Owner | Files |
|---|---|
| lead | this section; `CityDressing.json` `fabric.lanes` and `clear.lane`; the asset run |
| economy-designer "generator" | `tools/fabric.py`, `tools/streetplan.py`, `tools/fabric/Boomtown.plan.json`, `Config/Fabric/Boomtown.json`, `eras.Boomtown.fabric.pull` |
| ui-engineer | `src/shared/CityFabric.luau`, `src/shared/Types.luau` (`FabricLane`, parcel `lane` and `laneAlong`, `FabricLanesConfig`, `clear.lane`), `src/client/City/Fabric.luau`, `src/client/Controllers/CityDressingController.luau` |
| mirror-engineer | `tools/cityfabric.py`, `tools/testfit/plotrender.py`, `plotscene.py` |
| luau-engineer | the Studio start-era switch (below) |

### Studio start-era switch (luau-engineer)

Ben's Studio playtests of later eras need Village bought out first. A Studio-only switch starts a
fresh save in a chosen era, in the style of the Proving Grounds build (a place file with the switch
baked in, because adding an attribute by hand is hard for Ben in a Spanish Studio).

- Workspace attribute `DebugStartEra` (a whole number 2 to 4), read once per player on load, only
  under `RunService:IsStudio()`, and only for a profile that is still at its fresh defaults (era 1,
  no slots, no rebirths). It sets the era index, nothing else: cash, Legacy and stats stay at their
  defaults, and the normal Advance Era path is not run (no Legacy gain, no analytics event).
- A second place build bakes it in: `build/boomtown.rbxl` from a project file that differs from
  `default.project.json` only by that Workspace attribute set to 2. `GrantCash` works as before.
- Inert outside Studio and when the attribute is absent or invalid. No remote, no config constant
  duplicated in code.

### Rulings after the wave 2.4 reports and review (lead, 2026-10-02)

- **Ben accepted the lanes at 75 lots** ("the houses look fantastic!", on `m12d_compare.png` and
  the block render, told that Boomtown went from 102 lots to 75). The contract's targets above
  give way: `require.parcels` and `require.houses` are **74**, `require.medium` **3**, and bus
  shelters stand on at least **two** streets. A lane lot needs its frontage plus half a lane, four
  street lots became mouths, and two pockets have no way in while the layout is frozen (its street
  meshes are uploaded). Ways back to density, if Ben asks: move landmarks to open the two pockets
  (about +8 lots, a re-bake and a second harvest paste) or a narrower lane house (new props).
- **Lanes are plan-authored:** `parcels.lanes.lines` (polylines, mouth first; `through: true` for
  a line that ends on a street, which the generator cuts into two lanes that meet). A plan with a
  `lanes` block lays no infill rows. Boomtown: 8 lanes, 330 studs, 47 lane lots, all row 2.
- **`pull` for Boomtown:** radius 120, `tierTerm` 0.35, thresholds [2.2, 3.4, 3.8, 4.3]. With
  `laneAlong` added to every distance the old radius left every lane empty. The governor is still
  the nearest landmark, so height caps and districts keep their meaning.
- **A lane arrives whole.** With that radius every lot on a lane gets at least a site as soon as
  its front lot develops, so each lane appears at full length in one purchase and fills with
  houses from the street inward. Accepted for the playtest; if Ben wants the road to creep, the
  reach should count lots at level 2.
- **Review (0 Critical, 2 Major, 8 Minor):**
  - *Major, fixed:* an axis-aligned lane leg is laid as an unturned Part with its `Texture`
    offsets taken from its corner in plot coordinates, so it shows the same texels as the baked
    streets and the discs; only a diagonal leg carries a turned tiling.
  - *Major, ruled:* the lot target, as above.
  - `fabric.lanes.rimHeight` 0.02 (was 0.01: too close to the ground) and `clear.lane` 2.0 (was
    1.5: a field edge stood on a lane's kerb).
  - `FabricCivicSmall` and `FabricCivicMedium` never draw: no lot's nearest landmark is the Clock
    Tower or the Fire Station. Open: give those landmarks lots to govern, or retire the props.
  - `build/boomtown.rbxl` is for local Studio use only and must never be published: with API
    access on, the lever would move a fresh real save to era 2.
- **`LaneReach`** takes `laneIndex` and the near parcel budget as well. The mask's lane segments
  use the final-state reach on near and far plots alike, and need a valid `fabric.lanes` block.

### Done when (wave 2.4 gate, renders for Ben)

- `assets/testfit/out/Boomtown/m12d_{tier1,tier3,full,full_entrance}.png`, a close shot of one
  block's lanes, and `m12d_compare.png` against `m12c_full.png`.
- `fabric.py check`, `streetplan.py`, `cityfabric.py selftest` and `timeline` green for Village and
  Boomtown, Village data byte-identical; stylua, selene, luau-lsp and `rojo build` clean.

## Wave 2.5 — baked lanes (Ben's first Studio look at Boomtown, 2026-10-02)

Ben, with two Studio screenshots: "it seems like this street is glitching with the texture. it
seems like there is a texture above each other and renders them depending on how you are seeing
it. but if you get close enough it renders it well". That is z-fighting: wave 2.4 drew a lane as
a rim Part under a fill Part 0.02 to 0.03 studs apart, each with a `Texture`, and at a distance
the depth buffer cannot separate them. Part-based paths failed the same way on Village (M9 wave
1c). **Lanes become baked meshes, the approved recipe of wave 1d**, exactly like a landmark's
driveway.

### Pieces

- Every lane in `Config/Fabric/<Era>.json` is one baked path piece, id **`LN_<k>`** (k = the
  lane's 1-based index): a fill mesh and a rim mesh with world-planar UVs, the irregular edge and
  the heights of every other piece (`paths.rimHeight`, `paths.fillHeight`). Overlaps with the
  street at the mouth, and with another lane where two meet, are invisible for the same reason
  junctions are.
- Geometry is a spur's: the lane's polyline at width `fabric.lanes.width`, bends filleted as a
  spur's are, the mouth running under the street as a spur's does, and a round end at the far
  point (two lanes that meet simply overlap).
- `tools/paths/bake.py --era <Era>` bakes them from the fabric data together with the street and
  spur pieces. Existing pieces must come out byte-identical, so only the lane meshes upload.
  `--list` checks the lane pieces against the fabric data (ids, count, the polyline) as it checks
  the others against the client.
- Templates land in `templates/_paths/<Era>/LN_<k>.rbxmx` like every piece.
- `budget.pathPieces` covers them (Boomtown: 38 + 8).

### Client

- **A lane is drawn whole once its reach is above 0** (any lot on it has at least a building
  site). `CityFabric.LaneReach` and the clearing mask are unchanged; only the drawing changes.
  With Boomtown's pull every lane reached its full length in one purchase anyway.
- In the baked renderer the lane is its `LN_<k>` template, shown by the same code that shows
  spur pieces: rim, then fill, then the dust burst on an animated sync; the plot-wide surface swap
  (Pave Main Street) reaches it with every other piece. Near and far plots follow the path
  pieces' own rule.
- Without the template (the parts renderer, a missing asset) the lane is a single layer of flat
  Parts in the road's live material and colour: fill only, no rim, no `Texture`, so nothing lies
  on anything else. The wave 2.4 texture code goes.
- `fabric.lanes.rim`, `fillHeight` and `rimHeight` are no longer read by the baked renderer; the
  fallback uses `width` and `fillHeight`. `growSeconds` is unused and is removed from the config.

### Rulings after the wave 2.5 reports (lead, 2026-10-02)

- **A lane's bends turn on one lane width (3 studs), not a spur's two.** At a spur's radius the
  centreline cut each right-angle bend by 2.49 studs and the fill reached 0.96 studs into the lot
  inside the bend (lots stand 2.2 from the data polyline). At one width the fill stays off every
  lot and no outline folds. `LANE_FILLET_WIDTHS` in `tools/paths/network.py`.
- **A lane's far end** runs 2.4 studs (fill) and 2.85 (rim) past its last point as a round cap;
  its mouth runs 2.7 studs under the street like a spur's. The street it leaves gets no junction
  and no rounded end, which is what keeps every existing street mesh byte-identical.
- **Far plots** keep a lane's fill and drop its rim, as for every path piece. A far plot can
  therefore show a lane whose houses are past `parcelsFar`.
- **The piece budget:** lane k is requested as `LN_<k>` while
  `k <= budget.pathPieces - (stretch pieces + spur pieces)`; a lane past it, or one whose template
  is missing, is drawn as the flat Parts fallback on near plots only.
- **`fabric.lanes` is `{ width, rim, fillHeight }`.** The client reads `width` and `fillHeight`
  (the fallback); the generator and `streetplan.py` read `rim` for a lane's ground footprint.
  `rimHeight` and `growSeconds` are gone.
- The fabric sync now runs before `RoadGraph.Flush` in fabric eras, so a purchase's driveway and
  the lanes it opens reach the renderer in one update.
- The layout hash covers the lane polylines and width when an era has lanes; the stale test is
  per piece, so adding lanes left the 38 existing Boomtown pieces "fresh".

### Review rulings (2026-10-02, wave 2.5 review: 0 Critical, 0 Major, 6 Minor)

- **No z-fight source remains in the baked renderer.** All 93 path templates share rim and fill
  heights; the eight `LN_*` templates are placed, turned and textured like every other piece; at
  every mouth the street's rim lies under the lane's fill and the lane's rim under the street's.
- **`clear.lane` is 2.8** (was 2.0). The baked lane is wider than its data polyline (rim out to
  2.2 to 2.75 studs), and two field quarters stood on a lane's kerb for a few purchases.
- **Open, lead to route:** the Parts fallback for a lane still sits 0.02 to 0.03 studs from a
  street mesh where it runs under one, and stacks coplanar pieces at bends. Players never see it
  (all eight templates exist and 82 piece slots are spare), only `road.renderer = "parts"` or a
  partial upload does. Fix when next in `Fabric.luau`: start the first slab at the street's edge,
  raise `fabric.lanes.fillHeight` to 0.12, drop the discs.
- **Open, for the next Boomtown street re-bake:** polylines 3 and 4 meet end to end at (22.0,
  24.9) without joining, so their two street meshes end in round caps that only touch. Lanes 6
  and 8 leave that point and their fills cover it, so it reads as a crossroads. Do not move that
  mouth until the two polylines are one.
- **Open:** lane clearances in `fabric.py check` use the data polyline plus `rim`; they should use
  the bake's own half-width and cap overrun. `fabric.lanes.fillHeight` should not be required for
  a baked lane.
- **`GrantCash`** pays whoever is loaded on the tick it fires and then resets, so in a Local
  Server usually one player is paid.

### Ownership (wave 2.5, disjoint)

| Owner | Files |
|---|---|
| lead | this section; `CityDressing.json` `fabric.lanes`; the bake, upload, harvest and templates |
| mirror-engineer | `tools/paths/**`, `tools/cityfabric.py`, `tools/testfit/plotrender.py`, `tools/assets/upload_paths.py` and `gen_templates.py` only if lane ids need it |
| ui-engineer | `src/client/City/Fabric.luau`, `PathRenderer.luau`, `RoadGraph.luau`, `src/client/Controllers/CityDressingController.luau`, `AssetPreloader.luau`, `src/shared/Types.luau` |

### Done when

- `py tools/paths/bake.py --era Boomtown --list` exits 2 before the bake (agrees, 16 new meshes
  missing) and 0 after the harvest; Village's stays 0 and its meshes byte-identical.
- In Studio: lanes look like the streets and driveways from every distance, with no flicker.

---

# M13 contracts — The Valley (wave 1: sky, ground, hub, roads)

Ben, 2026-10-01: "can you imagine what the environment outside the city squares could look like?
low poly mountains, rivers and such". Three landscapes were rendered around the real plots
(`assets/research/2026-10-01-worldmock/`, sheets in `out/`); Ben chose **A, the Valley** ("i love
A valley"). M13 is built in the worktree `C:\Users\benja\Desktop\tycoon-m13` on branch
`m13-valley`. The M12 Boomtown session works in `tycoon-m12` at the same time: never touch it,
and announce every upload or harvest to it first.

Ben's rulings:

1. The Valley: a meadow basin ringed by snow-capped low-poly mountains, forest on the foothills,
   a waterfall, a river through the ring and a small lake. The Island and the Lake are closed.
2. Three waves, each one a Studio look:
   - **Wave 1 (this section):** sky, haze, green ground, hub and dirt roads. Parts and Lighting
     only, **no uploads**.
   - **Wave 2:** mountains, foothills, forest and waterfall as a generated kit (one upload, one
     harvest paste), an invisible wall at the foothills, the ground ramped up to the plot edges,
     era aprons.
   - **Wave 3:** river, lake and bridges.
3. **The river is shallow and wade-through, with solid wooden bridges** (wave 3). Bridges are
   server geometry that collides. That is a new category next to the M9 rule "no dressing part
   collides", not a change to it: client dressing still never collides.

The reference for looks is the mock (`wm_land.py`, and the `step1_*` renders for this wave).
Where this contract and the mock differ, the contract wins.

## Principles

- **Static and server-built.** The landscape is the same for every player and never changes with
  game state, so the server builds it once at boot, next to the plots. No remote, attribute,
  profile, economy or client change in wave 1.
- **Derived from the ring, never hand-placed.** Every position comes from `Game.json`
  (`plotCount`, `plotMargin`, `hubRadius`) and the layout's `plotSize`. `plotCount` is 10 on
  `main` and 6 on the unmerged `m11-unlocks`; both must come out right with no code change.
- **Levels are frozen.** Plot tops and the hub top are at Y = 0. The ground top is at
  Y = −`plotSize.Y` (−1). The client (`CityDressingController` `groundDrop`), `tools/cityfabric.py`
  and `tools/testfit/plotrender.py` all assume that level, and Village woods stand on the world
  ground up to about 19 studs past each plot's sides and back. Nothing in M13 may raise, lower
  or cover the ground inside that band without changing those three together.
- **Everything degrades.** Without `World.json` the world is built exactly as before M13: the
  default-grey `Ground` square and `Hub`, no roads, and Lighting untouched. A missing block in the
  file switches that one feature off. A bad material or colour warns once and falls back to the
  Part default. Nothing raises an Output error.
- **Every number in config.** Colours, materials, sizes and Lighting values live in `World.json`.
  Code holds only derived geometry.
- **Never two visible coplanar faces.** New parts sink into or stand proud of their neighbours.

## `World.json` — schema v1 (`src/shared/Config/World.json`, lead-applied)

Colours are RGB 0–255 and materials are `Enum.Material` names, as in `FabricPadLookConfig`.
Every block is optional; absent means "leave as before M13".

```json
{
  "version": 1,
  "lighting": {
    "clockTime": 14.5,
    "geographicLatitude": 35,
    "brightness": 2.5,
    "ambient": [110, 116, 128],
    "outdoorAmbient": [150, 156, 166],
    "exposureCompensation": 0
  },
  "atmosphere": {
    "density": 0.3,
    "offset": 0.25,
    "color": [199, 215, 235],
    "decay": [106, 132, 170],
    "glare": 0,
    "haze": 0.6
  },
  "clouds": { "cover": 0.45, "density": 0.35, "color": [255, 255, 255] },
  "ground": { "material": "SmoothPlastic", "color": [106, 153, 78], "side": 2048 },
  "hub": {
    "material": "SmoothPlastic",
    "color": [205, 200, 188],
    "surround": { "radius": 40, "height": 0.5, "material": "SmoothPlastic", "color": [150, 118, 84] }
  },
  "roads": { "width": 8, "lift": 0.1, "material": "SmoothPlastic", "color": [150, 118, 84] }
}
```

The values above show the shape. The values in the committed file are the mock's (`step1_*`
renders, `out/step1_numbers.json`) and win over this listing.

**First values (lead, 2026-10-01).** The committed file has **no `lighting` and no `clouds`
block**, on purpose:
- Every building and plot Ben approved was judged under the default Lighting. Brightness and
  ambient values taken from an offline render are guesses, so wave 1 leaves them alone and adds
  only the haze. The `lighting` block exists for tuning after his Studio look.
- The mock's clouds are low-poly meshes (wave 2). Roblox's volumetric `Clouds` are a different
  look and are not in the `step1_*` renders Ben was shown.
- The `atmosphere` numbers are a first guess that cannot be checked offline. The target is the
  mock's haze: about 20% at 500 studs, so the far side of the ring stays readable.
- Ground, hub and roads use `Plastic`, the material the plot bases already have.

Keys:

- `lighting`: each key, when present, is written to the `Lighting` property of the same name
  (`ClockTime`, `GeographicLatitude`, `Brightness`, `Ambient`, `OutdoorAmbient`,
  `ExposureCompensation`). An absent key leaves that property alone.
- `atmosphere`: one `Atmosphere` under `Lighting` (`Density`, `Offset`, `Color`, `Decay`, `Glare`,
  `Haze`). An existing `Atmosphere` child is reused, never duplicated.
- `clouds`: one `Clouds` under `Workspace.Terrain` (`Cover`, `Density`, `Color`). If the place has
  no `Terrain`, clouds are skipped silently.
- `ground`: `material`, `color`, and `side`, the square's side in studs. The side used is
  `min(2048, max(side, 2 × (ringRadius + plotSize.Z)))`, so the ground never shrinks below today's.
- `hub`: `material` and `color` for the existing `Hub` cylinder. `surround` adds one wider, lower
  cylinder around it: `radius` (> `hubRadius`, else it is skipped with a warning) and `height`,
  how far its top stands above the ground top (0 < `height` < `plotSize.Y`).
- `roads`: one flat strip from the hub to each plot's front edge. `width` in studs; `lift`, how
  far the strip's top stands above the ground top. A strip starts at the hub wall and runs under
  the surround, so **`lift` must be lower than `hub.surround.height`** (equal tops would z-fight
  in that band; a higher road would lie on top of the ring).

## `src/shared/WorldPlan.luau` (new; pure, no Roblox globals)

The ring maths, moved out of `PlotService.buildWorld` so the server, later waves and a Python
mirror (wave 2) share one definition. Angles are radians; plot `index` is 1-based.

```lua
export type Ring = {
	plotCount: number,
	radius: number,      -- plot centres
	halfSector: number,  -- pi / plotCount
	frontRadius: number, -- radius - plotSizeZ / 2: the hub-side edge
	backRadius: number,  -- radius + plotSizeZ / 2
}
export type Road = { angle: number, innerRadius: number, outerRadius: number, width: number }

WorldPlan.Ring(plotCount, plotMargin, hubRadius, plotSizeX, plotSizeZ): Ring
WorldPlan.PlotAngle(ring: Ring, index: number): number            -- (index - 1) / plotCount * 2π
WorldPlan.GroundSide(ring: Ring, plotSizeZ: number, wantedSide: number?): number
WorldPlan.Roads(ring: Ring, hubRadius: number, width: number): { Road }
```

- `Ring` is today's formula, unchanged:
  `radius = max(plotSizeZ / 2 + (plotSizeX / 2 · cos(halfSector) + plotMargin / 2) / sin(halfSector),
  hubRadius + plotMargin + plotSizeZ / 2)`. A plot's centre is `(cos(angle), sin(angle)) · radius`
  in X, Z.
- `GroundSide` is the rule under `ground` above; with `wantedSide` nil it returns today's
  `2 × (radius + plotSizeZ)`.
- `Roads` returns one road per plot, on the plot's radial. `outerRadius = frontRadius`.
  `innerRadius = max(hubRadius, width / (2 · tan(halfSector)))`: the second term is where two
  neighbouring strips would start to overlap, so strips never share a coplanar top at any
  `plotCount`. A road whose `innerRadius ≥ outerRadius` is left out.

## Server — `src/server/World/Landscape.luau` (new) and `PlotService.buildWorld`

`Landscape` is a plain module, not a service: it has no `Init`/`Start` and is not added to
`orderedServices`. It lives outside `src/server/Services`, so the combat place never mounts it.

```lua
Landscape.Build(ring: WorldPlan.Ring, layout: Types.EraLayout, gameConfig: Types.GameConfig): ()
```

`PlotService.buildWorld` calls `WorldPlan.Ring` and `WorldPlan.PlotAngle` for the ring it used
to compute inline, and calls `Landscape.Build` where it used to create `Ground` and `Hub`. `Spawn`,
the `Plots` folder and everything per plot stay in PlotService, byte-for-byte in behaviour.

`Landscape.Build` reads `Catalog.GetWorldConfig()` and creates:

| Instance | Parent | Geometry | Collision |
|---|---|---|---|
| `Ground` (Part) | `Workspace` | square of `GroundSide`, thickness `plotSize.Y`, top at −`plotSize.Y` | collides, as today |
| `Hub` (cylinder) | `Workspace` | exactly today's: radius `hubRadius`, top at 0 | collides, as today |
| `HubSurround` (cylinder) | `Workspace.Landscape` | radius `surround.radius`, top at −`plotSize.Y` + `height`, bottom inside the ground | collides |
| `Road_<index>` (Part) | `Workspace.Landscape` | `width` × (`outerRadius` − `innerRadius`), centred on the plot's radial, top at −`plotSize.Y` + `lift`, bottom `lift` below the ground top | none: `CanCollide`, `CanQuery`, `CanTouch` false |

- Every part is `Anchored`. Roads and the surround have `CastShadow` false (a flat strip gains
  nothing from casting); roads also have smooth `TopSurface`/`BottomSurface`.
- With `World.json` absent: `Ground` and `Hub` exactly as before M13 (default colour and material,
  today's side), no `Landscape` folder, Lighting untouched.
- Lighting, atmosphere and clouds are applied in the same call, before the parts are parented.
- Colour and material parsing is local to `Landscape` (warn once per bad value, fall back to the
  Part default). `ArenaService`'s helpers are combat's and are not touched.

### Types and Catalog (luau-engineer)

- `Types.WorldConfig` and its block types (`WorldLightingConfig`, `WorldAtmosphereConfig`,
  `WorldCloudsConfig`, `WorldGroundConfig`, `WorldHubConfig`, `WorldHubSurroundConfig`,
  `WorldRoadsConfig`), mirroring the JSON exactly; every block and every `lighting` key is `T?`.
  Add them after `ProvingGroundsConfig`, away from the regions `m11-unlocks` and `m12-boomtown`
  change.
- `Catalog.GetWorldConfig(): Types.WorldConfig?`, the nil-is-the-signal shape of
  `GetCityDressingConfig`. Add it at the end of the getters, **not** next to
  `GetProvingGroundsConfig` (`m11-unlocks` inserts `GetUnlocksConfig` there).

## Ownership (wave 1, disjoint)

| Owner | Files |
|---|---|
| lead | this section, `src/shared/Config/World.json` |
| luau-engineer | `src/shared/WorldPlan.luau` (new), `src/server/World/Landscape.luau` (new), `src/server/Services/PlotService.luau` (`buildWorld` only), `src/shared/Types.luau` (World types only), `src/shared/Catalog.luau` (`GetWorldConfig` only) |
| docs-keeper | `docs/PLAN.md`, `docs/PLAYTEST.md`, `docs/MANUAL_STEPS.md` |

- **Frozen:** everything else. In particular every client file, `Main.server.luau`, both project
  files, `Game.json`, the layouts, and every tool under `tools/` (the plot renderer's apron colour
  is updated in wave 2, after `m12-boomtown` merges, because that branch edits the same files).

### Review rulings (2026-10-02, roblox-reviewer: no Critical, one Warning)

- **`roads.lift` ≥ `hub.surround.height` builds no roads.** With a surround built, that
  combination warns once, naming both keys, and the roads are left out.
- **The new work cannot stop the boot.** `Landscape.Build` runs inside `PlotService.Init` before
  the spawn, the plots and the remote handlers. Lighting, atmosphere and clouds, and the surround
  and roads, each run under `pcall`: a failure warns and costs only that feature, and leaves no
  half-built `Landscape` folder. `Ground` and `Hub` stay unguarded, as before M13.
- **PlotService resolves `Landscape` inside `buildWorld`,** not at module scope. The combat place
  has no `Server/World`, and a module-scope wait there would hang any future combat-side require.
- **A road's inner end reaches the hub wall at its corners.** The strip is lengthened inward by
  `hubRadius − √(hubRadius² − (width / 2)²)`, hidden inside the hub, so roads look right with or
  without a surround. `WorldPlan.Roads` is unchanged; this is a rendering detail in `Landscape`.
- **Open for the Studio look, no code in wave 1:**
  - With `glare` 0, `decay` may have no visible effect. If the sky shows no blue fall-off away
    from the sun, raise `glare` slightly before re-tuning `decay`.
  - `lift` 0.1 is the only separation between a road and the ground, and roads are seen from 300
    to 500 studs at grazing angles. If a far road shimmers, raise `lift` and
    `hub.surround.height` together.
  - A road ends at the plot's front face; each era's first street starts 3.5 (Village), 5.5
    (Boomtown) or 11 (Metropolis, Orbital) studs further in, and the Sign post stands on the
    road's centreline. If the gap reads badly it is a wave 2 item (ground ramp and entrance).

## Done when (wave 1)

- Studio, `build/test.rbxl` from this worktree: a blue hazed sky, a green ground to the horizon,
  a pale stone hub with an earth ring, and a dirt road from the hub to every plot's front edge.
  Plots, pads, signs, buildings and all city dressing look and behave exactly as before. Village
  woods past the plot edge still stand on the ground.
- With `World.json` removed, the place builds and looks as it did before M13, with no Output error.
- `WorldPlan.Ring` returns a radius of about 277.0 for 10 plots and 183.9 for 6.
- Checks: stylua, selene, luau-lsp (both trees) and both `rojo build`s are clean; the existing
  gates (`sim_economy`, `streetplan`, `fabric.py check Village`, `cityfabric.py selftest`,
  `gen_templates.py --check`, `gen_asset_manifest.py --check`, `bake.py --era Village --list`) are
  unchanged and green.

## Wave 2 — the Valley meshes (Ben, 2026-10-02)

Ben's first Studio look at wave 1 (one screenshot, no complaint): "we didnt do step A2 yet? do
it". Rulings:

1. **The whole A2 Valley in one wave** (the old waves 2 and 3 together): mountains, foothills,
   forest, waterfall, far hills, the ground with its patches and baked roads, river, pond, lake,
   bridges, stepping stones, groves, aprons, clouds. One upload batch, **one harvest paste**.
2. The look reference is the mock's A2 renders (`out/A2_*.png`, `wm_valley2.py`,
   `out/A2_numbers.json`), with two changes the lead announced: **aprons are light era gravel in
   two flat bands** (the dark base colour bleeding outward read as scorch marks), and no signposts
   (each plot already has its Sign).

### Principles

- **Collision stays flat and made of Parts.** The `Ground` Part at Y = −`plotSize.Y` stays the
  only floor, visible, in the meadow green. Every mesh is visual: `Anchored`, with `CanCollide`,
  `CanQuery` and `CanTouch` false. Nothing depends on a MeshPart's collision geometry.
- **So the walkable basin is flat.** Inside the wall the visual ground never rises more than
  `overlayLift` above the Ground Part. The 1-stud kerb at the plot edges stays (no visual ramp:
  feet would sink into it). The river is not carved: its bed is coloured faces in the ground
  overlay and its water is a translucent sheet `water.lift` above the ground, so a player wades
  ankle-deep on the flat floor.
- **What collides, as server Parts built from data:** the wall, each bridge (deck and two ramps)
  and each stepping stone. These are world structures, a category next to client dressing; the
  M9 rule "no dressing part collides" is unchanged.
- **One source of truth for geometry: the generator.** A Python tool derives everything from the
  ring and writes both the meshes and `src/shared/Config/Valley.json`. Luau reads that data and
  never recomputes the river, the bridges or the wall. (`WorldPlan` keeps only the ring and the
  wave 1 roads.)
- **Baked for one `plotCount`.** The meshes fit the ring they were generated for. `Valley.json`
  records `plotCount`; if it differs from the live ring, the server warns once and builds the
  wave 1 look. When `m11-unlocks` (6 plots) merges, the Valley is regenerated and re-uploaded:
  one more harvest paste.
- **Everything degrades to wave 1.** No `Valley.json`, no `ServerStorage.Assets.World.Valley`, a
  `plotCount` mismatch, or a missing **required** mesh → the wave 1 world, with one warning. A
  missing optional mesh is left out, named in one warning.
- **Levels stay frozen** (wave 1). The skirt band around each plot stays at ground level.

### Frames

- **World frame** (`"frame": "world"`): X and Z are Roblox world studs (plot `i` centre at
  `(cos, sin)(angle_i) · radius`); generator Y = 0 is the **ground top**. The server places a world
  mesh with `PivotTo(CFrame.new(0, -plotSize.Y, 0))`.
- **Plot frame** (`"frame": "plot"`): the plot's local frame, origin at the plot centre, −Z toward
  the hub, generator Y = 0 at the ground top. One template, cloned once per plot with
  `PivotTo(base.CFrame * CFrame.new(0, -plotSize.Y / 2, 0))`.
- Blender is Z-up: Blender `(x, y, z)` is glTF/Roblox `(x, z, −y)`. A sign slip mirrors the
  valley; the preview gate below exists to catch it.
- 1 glTF unit = 1 stud, no scale anywhere. A template places a mesh at its generator coordinates
  with its facing preserved (verified on all 94 Village path meshes).

### The generator — `tools/world/valley.py` (landscape-builder)

```
py tools/world/valley.py build            # GLBs, palette, bake record, Valley.json
py tools/world/valley.py check            # QA gate: committed Valley.json == a fresh build
py tools/world/valley.py build --count 6 --out-root <scratch> --data <scratch>/Valley.json
```

- Reads `Game.json` (`plotCount`, `plotMargin`, `hubRadius`), the Village layout's `plotSize`,
  `World.json` (road width, colours it shares with wave 1) and its own art numbers in
  `tools/world/Valley.plan.json` (palette, noise, river widths, densities). The ring comes from
  `tools/worldplan.py`, a line-for-line mirror of `WorldPlan.Ring` with a `selftest` (277.0217
  and 183.9230).
- Writes, under the shared `assets/build/world/`: `Valley/<Mesh>.glb`, `Valley/palette.png`,
  `Valley.json` (the bake record). Writes `src/shared/Config/Valley.json` in the worktree.
- **Deterministic.** Two `build` runs give byte-identical GLBs, PNG and JSON (seeded noise, the
  pure-Python GLB writer of `tools/paths/planargeom.py`, no Blender exporter). It may run under
  `py` or under Blender's bundled Python (for numpy), like `tools/paths/texture.py`.
- **GLB shape:** one scene, one node, one mesh, **one primitive, no material, no image**:
  `POSITION`, per-face `NORMAL`, `TEXCOORD_0`, uint32 indices. Front faces are counter-clockwise
  seen from outside; nothing is double-sided. A flat sheet gets a hair of height (the importer
  rejects a zero-height bounding box).
- **Colour:** a `palette` mesh maps each face's UVs to the centre of its colour's swatch in
  `palette.png` (16-px swatches, opaque, one PNG for the whole set). A `flat` mesh has one colour,
  set on the MeshPart by the template or at runtime, and no texture.
- **Hard limits, asserted at build:** ≤ 20,000 triangles per mesh (aim ≤ 18,000); every bounding
  box side ≤ 1,500 studs; terrain outer radius ≤ 1,600; mesh names `[A-Za-z0-9_]`, ≤ 24
  characters; ≤ 32 meshes in the set.

Mesh set (names are a guide; the builder may split or merge within the limits):

| Mesh | Frame | Look | Required | Contents |
|---|---|---|---|---|
| `Basin_<k>` | world | palette | yes | the flat ground overlay inside the foothills at `overlayLift`: two-tone meadow, darker and wildflower patches, the earth ring, the bent dirt roads with rims, river and pond bed, banks, sand; holes under the hub and the plots are not needed (they sit above it) |
| `Details` | world | palette | no | stepping stones, hub kerb and bollards, flowers and tufts |
| `Groves` | world | palette | no | the tree clumps between the roads |
| `Water` | world | flat | no | river, pond and lake surface, translucent |
| `Bridge_<n>` | world | palette | no | plank deck, ramps and rails, one mesh per bridge |
| `Foothills_<k>`, `Mountains_<k>`, `FarHills_<k>` | world | palette | no | terrain outside the wall, rock and snow lines as in A2, the lake shore |
| `Forest_<k>` | world | palette | no | generated pines on the foothills |
| `Waterfall` | world | palette | no | the two-tier fall above the river's source |
| `Clouds` | world | flat | no | the flat low-poly clusters |
| `ApronInner`, `ApronOuter` | plot | flat | no | two flat bands around a plot, irregular outer edge, 16–40 studs reach where the wedge has room; clipped to the plot's own sector (0.3 studs short of the bisector, so neighbours never overlap) and cut open for the road corridor; `ApronOuter` lies outside `ApronInner`, never under it |
| `Entrance` | plot | palette | no | two short fence runs flanking the road at the plot's front edge |

- Roads bend gently as in A2 and still end at the centre of each plot's front edge (plot-local
  `(0, −plotSize.Z / 2)`) and at the hub. The river uses the mock's gaps (it enters between plot
  N and plot 1 and leaves after plot `round(N / 2) + 1`), widths and pond.
- Stacking above the ground top, so no two visible faces are coplanar: `overlayLift` 0.10 (basin),
  aprons 0.16, water `water.lift` 0.35, bridge deck 0.70. Trees, stones and fences start at the
  overlay.
- Trees, fences, stones and bridges are generated geometry in the set's palette (colours sampled
  from the Village kits so they sit with the skirt woods). No kit GLB is baked in.

### `Valley.json` — generated data (`src/shared/Config/Valley.json`, never hand-edited)

Heights are studs above the ground top. `yaw` is radians about +Y, 0 = the bridge's long axis
along +X, turning toward +Z.

```json
{
  "version": 1,
  "plotCount": 10,
  "ringRadius": 277.0217,
  "planHash": "9c1f0a7e2b6d4c35",
  "overlayLift": 0.1,
  "wallRadius": 358.3,
  "meshes": [
    { "name": "Basin_1", "frame": "world", "required": true },
    { "name": "ApronInner", "frame": "plot", "tint": "apronInner" },
    { "name": "ApronOuter", "frame": "plot", "tint": "apronOuter" }
  ],
  "bridges": [
    { "x": -141.9, "z": -98.6, "yaw": 0.61, "length": 23.7, "width": 7, "deckTop": 0.7, "deckThickness": 0.5, "rampLength": 3.5 }
  ],
  "stones": [ { "x": 0, "z": -67, "radius": 1.75, "top": 0.62 } ],
  "river": [ [221.0, -71.8, 5.5] ]
}
```

- `meshes`: every template to place, in order. `required` (default false). `tint` (plot frame
  only): the mesh is recoloured per plot from `World.json valley.aprons` by the plot's era.
- `bridges`: `length` is the deck (ramps add `rampLength` at each end); the deck's top is at
  `deckTop` and the ramps fall from it to the ground top.
- `stones`: an upright cylinder each, top at `top`.
- `river`: channel samples `[x, z, halfWidth]` in world studs along the centreline, pond included,
  from the wall inward only. It exists for the client's skirt rule below. `halfWidth` covers the
  visible water plus its bank.

### `World.json` additions (lead-applied)

```json
"valley": {
  "wall": { "height": 160, "thickness": 4, "segments": 36 },
  "aprons": {
    "Village": { "inner": [114, 142, 66], "outer": [120, 149, 71] },
    "Boomtown": { "inner": [178, 160, 102], "outer": [152, 158, 89] },
    "Metropolis": { "inner": [150, 150, 144], "outer": [138, 153, 110] },
    "OrbitalColony": { "inner": [136, 134, 138], "outer": [131, 145, 107] }
  },
  "skirtMargin": 1.5
}
```

- `wall`: `segments` flat invisible Parts in a ring, their inner faces tangent to
  `Valley.json wallRadius`, standing from the ground top to `height`, `thickness` deep.
- `aprons.<EraName>`: `inner` and `outer` colours (`outer` is halfway to the meadow). An era with
  no entry hides both bands.
- `skirtMargin`: extra studs around the river channel in the client's skirt rule.

### Pipeline — a copy of the baked-paths route (pipeline-engineer)

The props route is not used (it needs kits, blueprints, a Blender join and has no hash).

- `tools/assets/assets_config.py`: a `world` block that `render_assets` serialises (today unknown
  top-level keys are erased on the next save). Shape, key order fixed like `render_path_era`:
  ```json
  "world": { "Valley": {
    "plotCount": 10, "planHash": "9c1f0a7e2b6d4c35", "triangles": 103084,
    "paletteAssetId": 0, "paletteImageId": 0, "paletteSha256": "",
    "meshes": { "Basin_1": {
      "assetId": 0, "meshId": 0, "size": [0, 0, 0], "offset": [0, 0, 0], "sha256": "",
      "triangles": 17500, "look": "palette" },
      "Water": { "assetId": 0, "meshId": 0, "size": [0, 0, 0], "offset": [0, 0, 0], "sha256": "",
      "triangles": 900, "look": "flat", "color": [58, 144, 200], "transparency": 0.25 } } } }
  ```
- `tools/assets/upload_world.py` (new), modelled on `upload_paths.py`: reads the bake record,
  uploads each GLB as a Model and the palette as a Decal, sha256 skip, `Assets.json` saved after
  every upload, resumable, the 50-character display-name guard (`EraCityTycoon_World_<Set>_<Mesh>`
  else `ECT_World_…`), `--only <Mesh>` for the trial upload, `--dry-run` that writes **nothing**,
  and the scratch flags (`--assets-json`, `--bake-root`). Meshes no longer in the bake record are
  dropped. The palette PNG check: opaque, any size.
- `tools/assets/harvest.py`: kinds `worldMesh` and `worldTexture` ride along with whichever paste
  comes next, like the path kinds (the Decal branch must accept `worldTexture`). `merge` requires
  exactly one MeshPart per mesh and **checks the harvested `size` against the bake record's**
  (tolerance 0.01 studs or 0.1%): a mismatch means the importer rescaled the mesh; it is reported
  per mesh and exits non-zero after merging the rest.
- `tools/assets/gen_templates.py`: `--world`, `GROUP_DIRNAMES["world"] = "_world"`, and the world
  tree in `--check`. Output `templates/_world/<Set>/<Mesh>.rbxmx` (two levels, so a branch
  without this change never mistakes it for an era folder): a `Model "<Mesh>"`, `WorldPivot`
  identity, one MeshPart `Mesh` with `Anchored` true, `CanCollide`/`CanQuery`/`CanTouch` false,
  `CastShadow` false, `CollisionFidelity` Box, `RenderFidelity` Precise, `Material`
  SmoothPlastic, `harvested_cframe` with lift 0. `palette`: white, `TextureContent` = the palette
  image. `flat`: `Color3uint8` = `color`, `Transparency` = `transparency`, no texture.
- `tools/gen_asset_manifest.py`: a "World" table (set, meshes, triangles, uploaded/templated).
- The bake record (`assets/build/world/Valley.json`), written by the generator, read by the
  uploader and by harvest:
  ```json
  { "set": "Valley", "plotCount": 10, "ringRadius": 277.0217, "planHash": "9c1f0a7e2b6d4c35",
    "palette": { "file": "Valley/palette.png", "sha256": "…", "size": [112, 96] },
    "meshes": { "Basin_1": { "file": "Valley/Basin_1.glb", "sha256": "…", "triangles": 17500,
      "vertices": 52500, "centre": [0, 0.05, 0], "size": [754.6, 0.11, 754.6],
      "look": "palette" } } }
  ```
  A `flat` mesh adds `"color"` and `"transparency"`.

### Rojo (luau-engineer)

`default.project.json`: add `"templates/_world"` to `globIgnorePaths` and a child
`"World": { "$className": "Folder", "$path": { "optional": "templates/_world" } }` under
`ServerStorage.Assets`. `combat.project.json`: the ignore entry only. No `templates/World` folder
may ever exist (Rojo does not merge an explicit child into a same-named directory).

### Server — `Landscape` (luau-engineer)

- `Catalog.GetValleyPlan(): Types.ValleyPlan?` (nil is the signal) and the `ValleyPlan` types,
  placed like the wave 1 additions. `WorldConfig.valley` types.
- **Mesh mode** when `Valley.json` exists, `ServerStorage.Assets.World.Valley` exists,
  `plotCount` matches the ring and every `required` mesh has a template. Otherwise wave 1, with
  one warning saying which condition failed (no warning when `Valley.json` or the folder is
  simply absent).
- In mesh mode `Landscape.Build`:
  - builds `Ground` and `Hub` as in wave 1, and **no** `HubSurround` and **no** `Road_<i>` (both
    are baked into the basin);
  - clones every world-frame mesh once into `Workspace.Landscape.Valley`;
  - builds `Wall_<k>` (invisible, `CanCollide` true, `CanTouch` false),
    `Bridge_<n>` collision (one deck Part and two `WedgePart` ramps each, invisible) and
    `Stone_<n>` collision (invisible cylinders) under `Workspace.Landscape.Collision`.
- `Landscape.AttachPlot(plotFolder: Folder, base: BasePart): ()`, called by
  `PlotService.buildWorld` once per plot inside its loop (the only PlotService change): in mesh
  mode it clones every plot-frame mesh for that plot into `Workspace.Landscape.Valley` and, for
  `tint` meshes, sets the colour from the plot folder's `EraName` attribute now and on every
  change of it. Outside mesh mode it does nothing.
- All of it runs under the wave 1 boot guard: a failure costs the Valley, never the plots.

### Client — skirt entries in the river (ui-engineer)

Village woods (and any later era's `skirt` entries) stand up to 19 studs past a plot's sides, and
the river runs through two 20-stud gaps. A `skirt` entry whose world position lies within
`halfWidth + valley.skirtMargin` of a `Valley.json river` segment is absent: not drawn, and not
a bird flock centre. A segment's `halfWidth` is the larger of its two ends. A **clump** is also
absent if any of its `quads` lies within that reach plus the fabric's `quarterRadius` (a clump's
trees stand up to 6 studs from its centre).

- New `src/client/City/WorldBlock.luau`: `WorldBlock.Blocked(worldX, worldZ, extraRadius?)`. It
  builds the test lazily from `Catalog.GetValleyPlan()` and `Catalog.GetWorldConfig()`, and only
  once all three hold: the plan exists, its `plotCount` equals the number of plots in
  `Workspace.Plots`, and **`Workspace.Landscape.Valley` exists** (the server's sign that it is
  in mesh mode; in every fallback there is no river and the woods stay). Until then it blocks
  nothing and caches nothing.
- `Fabric.luau` changes only by the hook that asks it, for `skirt` entries only (`syncWild` and
  `SurvivingClumps`). The wild budgets stay positional: a blocked entry keeps its place in them.
  The file is being edited on `m12-boomtown`: keep the hunks minimal. After that merge, any new
  list that carries `skirt` entries needs the same gate.
- Not mirrored in `tools/cityfabric.py` or `plotrender.py`: the rule depends on where a plot sits
  in the world, which a single-plot render does not have. This is the one sanctioned difference
  between the mirror and the client.

### Gates and order (lead)

1. `valley.py build`, then the builder's preview renders of **the baked GLBs** with back-face
   culling on, from the mock's cameras, on the real ring of plots. The lead compares them with
   `A2_*.png` before anything is uploaded.
2. Announce to the Boomtown session and wait for its ack. Trial: `upload_world.py --only` the
   mesh with the most triangles and the mesh with the largest bounding box (18,000 triangles and
   1,000 studs are both untested through Open Cloud; the largest so far are 12,044 and 61).
3. The batch upload, **one harvest paste** by Ben, `harvest.py` (size check), `gen_templates.py
   --world`, `gen_asset_manifest.py`, `rojo build`.
4. Review, QA, docs.

### Ownership (wave 2a, disjoint)

| Owner | Files |
|---|---|
| lead | this section, `World.json` (`valley`), pipeline runs, `src/shared/Config/Assets.json`, `templates/_world/**`, `tools/assets/harvest.luau` |
| landscape-builder | `tools/world/**` (new: `valley.py`, `Valley.plan.json`, `preview.py`, helpers), `tools/worldplan.py` (new), `src/shared/Config/Valley.json` (generated), `assets/build/world/**` |
| pipeline-engineer | `tools/assets/assets_config.py`, `tools/assets/upload_world.py` (new), `tools/assets/harvest.py`, `tools/assets/gen_templates.py`, `tools/gen_asset_manifest.py` |
| luau-engineer | `src/server/World/Landscape.luau`, `src/server/Services/PlotService.luau` (`buildWorld`: the `AttachPlot` call only), `src/shared/Types.luau` (Valley and `WorldConfig.valley` types only), `src/shared/Catalog.luau` (`GetValleyPlan` only), `default.project.json`, `combat.project.json` |
| ui-engineer | `src/client/City/WorldBlock.luau` (new), `src/client/City/Fabric.luau` and `src/client/Controllers/CityDressingController.luau` (the skirt hook only) |

- **Frozen:** everything else, and every existing tool's behaviour for buildings, props and paths
  (their templates and `--check` output must stay byte-identical).

### Preview gate rulings (lead, 2026-10-02)

The baked GLBs were rendered from the mock's cameras with back-face culling on
(`assets/research/2026-10-01-worldmock/out/sheetV_*.png`, A2 | baked) and accepted. Where the
text above differs, these win:

- **28 meshes, about 132,000 triangles.** `Basin_1..2` (required), `Mountains_1..4` (one per
  world quadrant; each holds foothills, mountains and far hills, so there is no `Foothills_` or
  `FarHills_` mesh), `Forest_1..6`, `Groves`, `Details`, `RiverBed`, `Waterfall`, `Water`,
  `Bridge_1..4`, `Clouds_1..4`, `ApronInner`, `ApronOuter`, `Entrance`.
- **`RiverBed` is new** (palette, world, optional), at 0.22. Both neighbours' aprons reach their
  shared bisector, which in the two river gaps is the river's centreline, so the aprons (0.16)
  lay over the painted bed; `RiverBed` repeats the bed and banks above them there. Stacking is
  now: basin 0.10, aprons 0.16, river bed 0.22, water 0.35, bridge deck 0.70.
- **Terrain ends at radius 1,400** (a quadrant must fit the 1,500-stud box). Clouds stand 900 to
  1,260 studs out for the same reason.
- `wallRadius` is 358.9; the foothills start at 362.3. The tallest summit is 310.5 studs above
  the ground top at radius 722.6.
- `Valley.json` `river` starts at the foothills, 3.4 studs outside the wall. `yaw` is folded into
  (−π/2, π/2]. Positions are rounded to 3 decimals and `yaw` to 4.
- A `--count` scratch build writes the game data to `--data` and the bake record next to it as
  `Valley.bake.json`.
- The trial meshes are `Details` (most triangles) and `Mountains_3` (largest box, 1,444 studs).
- The meadow's facet contrast was halved after the first preview (the mosaic read as a pattern).
- Known and accepted: trees and boulders inside the wall do not collide; a straight seam shows
  where two aprons meet at the inner corners; the terrain's outer edge is visible from high above.

### Review rulings (2026-10-02, roblox-reviewer: no Critical, two Warnings)

Placement, the wall, the bridge decks and wedges, the stones, the aprons, the client rule and the
Rojo mapping were verified against the real templates and data. Taken:

- **Mesh mode also needs the `valley` config and a wall.** No `World.json` or no `valley` block:
  not mesh mode, silently. A `valley.wall` that fails validation: not mesh mode, one warning.
  (Without a wall, players could walk through the foothills and off the ground's edge.)
- **`planHash` ties the data to the meshes.** `Valley.json planHash` must equal
  `Assets.json world.Valley.planHash` (written at upload). The server checks it: a mismatch is one
  warning and the wave 1 world. `valley.py check` checks it too, so a re-bake that was never
  uploaded turns QA red. The hash covers the plan file, the ring, `plotSize` and `World.json`
  `ground`, `hub`, `roads` and `valley.wall.segments`: **changing any of those needs a re-bake, an
  upload and a harvest paste.** Haze, lighting, apron colours, wall height and thickness and
  `skirtMargin` are config-only.
- **A collider is built only when its mesh was placed:** `Bridge_<n>` collision needs the
  `Bridge_<n>` mesh, the stones need `Details`.
- `CanQuery = false` has no effect on a part that collides, so the wall, decks, ramps and stones
  still answer raycasts. Nothing in the hub raycasts; the flags stay as written above.
- `WorldBlock` tests for `Workspace.Landscape.Valley` before it counts the plots.
- **A build that is not the one being uploaded must use `--out-root`.** `assets/build/world` is
  shared by every worktree; a 6-plot bake from another worktree would overwrite this branch's
  bake record.
- Open for the Studio look: `Water` is one large translucent MeshPart, so smoke and dust seen
  across the river may sort wrongly (the fix is splitting it); mountains and clouds have centres
  930 to 1,000 studs out and may be culled at low graphics quality; a skirt tree can stand in the
  river until a plot's next sync if the Valley folder replicates late (accepted).

### Done when (wave 2)

- Studio: the A2 Valley around the ring. Mountains, forest and waterfall behind the plots; the
  river, pond and lake; bridges you walk over and a river you wade through; stepping stones you
  stand on; groves and flower patches in the centre; a light gravel apron around each plot that
  changes with its era; a wall you cannot pass at the foothills. Plots and city dressing are
  unchanged, except that no skirt tree stands in the river.
- With `templates/_world` or `Valley.json` removed: the wave 1 world, no Output error.
- `valley.py check`, `worldplan.py selftest`, `gen_templates.py --check` and
  `gen_asset_manifest.py --check` are green; every existing gate is unchanged and green.
