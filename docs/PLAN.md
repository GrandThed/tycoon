# Era City Tycoon — Delivery Plan

Source of truth: `docs/SPEC.md`. This plan maps the spec's milestones (§12) onto the subagent
team, with file ownership and the contracts each wave shares. Detailed, frozen contracts for a
milestone are written into `docs/INTERFACES.md` by the lead at the *start* of that milestone;
this document only sketches them so the shape of the work is visible up front.

Status legend: `[ ]` not started · `[~]` in progress · `[x]` done & playtested.

- [x] M0 — Scaffold (QA-green; Rojo connect verified; playtest 19/19)
- [x] M1 — Playable loop (review SHIP after fixes, QA green; playtest 32/32)
- [x] M2 — Persistence & eras (review SHIP after exploit fix, QA+sim green; playtest 30/45 boxes
  ticked individually; the 15 long-haul persistence/prestige steps were closed by the M5 Final
  sweep, `docs/PLAYTEST.md` steps 40–47, rather than box by box)
- [x] M3 — Presentation (review SHIP, QA green; playtest 21/40 plus 7/12 carry-over boxes ticked
  individually; the remaining steps were closed by the M5 Final sweep, same as M2)
- [x] M4 — Monetization & analytics (reviewer SHIP after a Critical join-race fix and four
  Major findings; QA green; **playtest 17/17**, with real pass/product ids live in
  `Monetization.json` and the nine event sounds uploaded. Three further bugs were found *by*
  that playtest and fixed after the review — see "Shipped" below)
- [x] M5 — Hardening (review SHIP after two Warnings fixed, QA green; **playtest passed 2026-09-09**
  — Ben reported everything correct, including the final sweep that re-covers the M2/M3 long-haul
  steps. MVP definition of done (spec §12) met.)
- [x] M6 — Legacy shop (review SHIP after two Warnings fixed, QA green; **playtest passed
  2026-09-09**, one UX fix from the playtest: pinned balance header + spendable/total in the top bar)
- [ ] M7 — Assets (research only, not started: Kenney buildings assembled from kit pieces that grow
  with the player's levels; scripted Open Cloud pipeline. Handoff: `docs/ASSET_RESEARCH.md`)

---

## 1. Environment (verified 2026-09-08)

Repo now lives at `C:\Users\benja\Desktop\tycoon` and **is** a git repository.

| Tool | Status | Notes |
|------|--------|-------|
| rojo | ✅ `~/.rokit/bin/rojo.exe` 7.7.0 | Rokit-managed; **not** on PATH by default in either shell |
| wally | ✅ `~/.rokit/bin/wally.exe` 0.3.2 | ProfileStore via Wally is the plan of record |
| stylua | ✅ `~/.rokit/bin/stylua.exe` 2.5.2 | requires LF line endings (`.gitattributes`) |
| selene | ✅ `~/.rokit/bin/selene.exe` 0.31.0 | |
| luau-lsp | ✅ `~/.rokit/bin/luau-lsp.exe` 1.69.0 | needs `--sourcemap sourcemap.json`; regenerate with `rojo sourcemap default.project.json -o sourcemap.json` whenever modules are added |
| python | ✅ `py` (3.14) | **`python` and `python3` do NOT exist on this machine** — every doc/tool command invokes `py tools/...` |
| Roblox type defs | ✅ `tools/types/globalTypes.d.luau` | committed at end of M2 session; use for `luau-lsp analyze --definitions=...` — do NOT re-download (the obvious URL 404s) |

Toolchain reinstalled 2026-09-08 (rokit was missing on this machine/profile) at `~/.rokit/bin`,
pinned by the repo-root `rokit.toml`. Not on PATH by default in either shell:
- PowerShell: `$env:PATH = "$HOME\.rokit\bin;$env:PATH"`
- Bash: `export PATH="$HOME/.rokit/bin:$PATH"`

Agent note: subagents running toolchain commands must set one of the two PATH lines above first
— neither shell has `~/.rokit/bin` on PATH out of the box.

## 2. Standing assumptions & defaults

Chosen per spec §12.1 ("choose sensible defaults and document them"). None of these block M0–M1;
flag disagreement at any playtest gate and we adjust.

1. **Data layer (resolved at M0):** ProfileStore exists on Wally as
   `lm-loleris/profilestore@1.0.3` but is `realm = "server"`, so it cannot sit in the shared
   `[dependencies]` table. Plan of record for M2: add it under `[server-dependencies]` in
   `wally.toml` and map `ServerPackages/` into ServerScriptService in `default.project.json`.
   No vendoring, no DataStore fallback needed.
2. **Studio playtest levers:** eras take hours by design, which makes playtesting M2+ impractical.
   `Game.json` gets a `debug` block (income multiplier + free-buy toggle) that the server honors
   **only** when `RunService:IsStudio()` is true. Documented in `PLAYTEST.md` per milestone.
3. **Income formula rollout:** `Economy.luau` implements the full §4 formula from M1, with every
   multiplier defaulting to 1. Legacy and neighbors multipliers activate in M2, pass/Premium
   multipliers in M4. The formula itself never changes shape after M1.
4. **Era 1 slot mix** (of the ~24 slots): 16 `building`, 4 `unlock`, 3 `decor`, 1 `monument`.
   Same proportions for later eras unless balancing says otherwise.
5. **Rate limit default:** 10 calls/s per player per remote, drop on overflow (spec §7).
6. **Placeholder visuals:** per-era tinted 8×8×8 Part + BillboardGui with `modelName` (spec §5);
   plot base is a plain part tinted per era.
7. **Welcome-back UI timing:** a bare functional toast ships in M2 (so offline progress is
   playtestable), polished into the real card in M3.
8. **Root tool configs** (`default.project.json`, `wally.toml`, `stylua.toml`, `selene.toml`)
   are owned by luau-engineer even though they sit outside `src/` — they are inseparable from
   the scaffold.
9. **`tools/gen_asset_manifest.py`** is owned by economy-designer (same skill set and inputs as
   `sim_economy.py`); docs-keeper only *runs* it to regenerate the manifest.

## 3. Ownership map (steady state)

No two agents touch the same file in the same wave. Cross-boundary needs are reported to the
lead and routed, never edited directly.

| Owner | Files |
|-------|-------|
| **lead (this conversation)** | `docs/INTERFACES.md`, `docs/PLAN.md` (structure), trivial one-file fixes routed from review |
| **luau-engineer** | `src/server/**`, `src/shared/Types.luau`, `src/shared/Economy.luau`, `src/shared/Format.luau`, `default.project.json`, `wally.toml`, `stylua.toml`, `selene.toml`, `rokit.toml` |
| **ui-engineer** | `src/client/**` |
| **economy-designer** | `src/shared/Config/**`, `src/shared/Layouts/**`, `tools/sim_economy.py`, `tools/gen_asset_manifest.py`, `docs/BALANCE.md` |
| **docs-keeper** | `docs/PLAYTEST.md`, `docs/MANUAL_STEPS.md`, `docs/ASSET_MANIFEST.md` (generated), `README.md`, status ticks in `docs/PLAN.md` |
| **roblox-reviewer** | read-only; findings routed by lead to owners |
| **qa-runner** | runs stylua/selene/rojo build/sim; reports failures only |

## 4. Shared contracts (sketch — frozen per milestone in INTERFACES.md)

1. **`Types.luau`** (luau-engineer authors, everyone consumes): `SlotConfig`, `EraConfig`,
   `SlotState`, `PlayerState`, `StateDelta`, profile schema type.
2. **Remotes** (server creates, client consumes; names fixed now, payloads frozen at M1):
   - Client → server intents: `RequestBuy(slotId)`, `RequestLevelUp(slotId, count)`,
     `RequestAdvanceEra()`, `RequestRebirth()`, `RequestPrompt(productKey)`. No amounts, ever.
   - Server → client: single `StateChanged` (full snapshot on join, batched deltas ≤ 4/s),
     plus fire-and-forget FX events added in M3 (reveal, level-up, era-advance, welcome-back).
3. **Era config JSON schema** (economy-designer authors files, luau-engineer + Python consume):
   per era `{ eraIndex, name, slots: [{ id, type, name, modelName, description, baseCost,
   baseIncome, requires?, multiplier? }] }` — exact schema frozen in INTERFACES.md at M1 start.
4. **Layout module shape** (economy-designer authors, PlotService + client visuals consume):
   per era, `slotId → { position, rotationY }` relative to `PlotRoot`, plus pad placement rule.
5. **`Economy.luau` pure API** mirrored function-for-function by `sim_economy.py`:
   `slotIncome`, `incomePerSecond`, `levelUpCost`, `milestoneMult`, `legacyGain`, `offlineGrant`.
   Any change to one side must land with the matching change to the other in the same milestone.
6. **Profile schema v1 + `Migrations` table** (spec §7 Data) — owned by luau-engineer, frozen at M2.

## 5. Per-milestone process

Every milestone runs the same wave sequence (CLAUDE.md “Orchestration”):

1. Lead updates `docs/INTERFACES.md` (contracts + ownership for this milestone).
2. Fan out to engineers/designer in parallel (tasks below are already disjoint).
3. `roblox-reviewer` on the diff → Critical findings routed back to owners.
4. `qa-runner`: stylua, selene, `rojo build -o build/test.rbxl`, sim (M2+).
5. `docs-keeper`: PLAYTEST.md, MANUAL_STEPS.md, ASSET_MANIFEST.md (M3+), status tick here.
6. Lead reports to Ben; **stop for Studio playtest**.

---

## M0 — Scaffold

**Goal:** repo builds and boots empty. `rojo build` succeeds; syncing into Studio and pressing
Play produces zero errors and a "services booted" log line.

**Contracts frozen first:** folder tree, service names, remote *names*, `Game.json` schema,
Types.luau skeleton.

| Owner | Tasks |
|-------|-------|
| luau-engineer | `default.project.json` (incl. `$ignoreUnknownInstances: true` on ServerStorage), `wally.toml` (ProfileStore + Signal), `stylua.toml`, `selene.toml`, `Main.server.luau`, empty-but-booting `Services/{Data,Plot,Economy,Monetization,Remote}Service.luau`, stub `Types.luau` / `Economy.luau` / `Format.luau` |
| ui-engineer | `Main.client.luau` + stub `Controllers/{UI,Sound,PlotVisuals}Controller.luau` that boot silently |
| economy-designer | `Config/Game.json`: tick rate, plotCount=10, offline cap/efficiency, rate limits, maxLevel=100, milestone levels, neighbors params, `debug` block |
| docs-keeper | README refresh, PLAYTEST.md (M0 checks), MANUAL_STEPS.md (install Rojo plugin, `wally install`, Rojo connect) |

**Done when:** `wally install` + `rojo build -o build/test.rbxl` succeed; stylua/selene clean;
Studio boots error-free. **Playtest gate:** Ben syncs and confirms clean boot.

## M1 — Playable loop

**Goal:** full Era 1 loop with zero Kenney assets: claim plot → buy via pads or panel →
placeholder buildings appear → income ticks → level-ups work → all 24 slots ownable.

**Contracts frozen first:** era config JSON schema, layout module shape, `StateChanged`
payload, `Economy.luau` signatures, buy-pad behavior (visibility follows `requires`).

| Owner | Tasks |
|-------|-------|
| luau-engineer | Real `Types.luau`; pure `Economy.luau` (full §4 formula, multipliers default 1); `Format.luau` (suffixes incl. aa/ab…); `RemoteService` (creation, type validation, rate limiting); `PlotService` (claim/release on join/leave, pad generation from config, `RequestBuy`/`RequestLevelUp` validation incl. `requires` chain, placeholder spawn with tween+sound hook, ProximityPrompt level-up); `EconomyService` (1 Hz accumulated-delta tick, cash attribute mirror, snapshot + batched deltas). In-memory state only — persistence is M2. |
| ui-engineer | Top bar (cash, income/s, era badge); Build panel v1 (slot list, cost, income delta, Buy, next-affordable highlight); `StateChanged` consumption; insufficient-funds feedback |
| economy-designer | `Eras/1_Village.json` (24 slots per assumption #4, draft numbers aimed at 30–45 min), `Layouts/Village.luau` (grid + monument placement) |
| docs-keeper | PLAYTEST.md M1 (incl. mobile emulation at 375×667), MANUAL_STEPS.md updates |

**Done when:** end-to-end loop playable in Studio with placeholders only; build/lint clean.
**Playtest gate:** Ben completes a sped-up Era 1 (debug multiplier) on desktop + mobile emu.

## M2 — Persistence & eras

**Goal:** leave/return persists everything; offline earnings; all four eras; Advance Era,
Rebirth, and Legacy working; economy simulated and first-pass balanced.

**Contracts frozen first:** profile schema v1 + migrations, offline formula I/O, Advance/Rebirth
flow (what resets vs persists), eras 2–4 config schemas (same as era 1), sim CLI interface.

| Owner | Tasks |
|-------|-------|
| luau-engineer | `DataService` (ProfileStore, session lock, migrations, pcall+retry, `BindToClose`); offline calc on join (`lastSeen`/`incomeAtSave`); `RequestAdvanceEra` + `RequestRebirth` (validate all-slots-owned; reset/persist per spec §3); legacy multiplier + neighbors multiplier live in income; stats tracking |
| economy-designer | `Eras/{2_Boomtown,3_Metropolis,4_OrbitalColony}.json`, `Layouts/{Boomtown,Metropolis,OrbitalColony}.luau`, `tools/sim_economy.py` (greedy player, 1 s resolution, per-era time + longest-wait table), tune all four eras to §4 pacing targets, initial `docs/BALANCE.md`. Carry-over from M1: narrow the slot-rusher spread (slots-only run finishes Era 1 in 10.7 min vs 40.5 greedy) |
| ui-engineer | Legacy count in top bar; Advance Era confirm dialog (minimal — full screen is M3); bare welcome-back toast (assumption #7); rebirth confirm |
| docs-keeper | PLAYTEST.md M2 (persistence, offline, advance, rebirth — using debug levers), MANUAL_STEPS.md |

**Done when:** rejoin restores state; offline grant correct and capped; player can reach Era 4
and rebirth (debug-accelerated); `sim_economy.py` output meets pacing targets and is committed
to BALANCE.md. **Playtest gate:** Ben verifies persistence + a full accelerated prestige loop.

## M3 — Presentation

**Goal:** looks and sounds like a real game on a phone. Full mobile UI, feedback for every
action, era-advance ceremony, welcome-back card, asset manifest for the Kenney import.

**Contracts frozen first:** FX remote events (reveal/level-up/era-advance payloads),
`Sounds.json` schema, VIP skin folder convention + fallback rule, manifest generator I/O,
and a `displayName` era-schema field (M2 nit: "OrbitalColony" reads unspaced in UI copy;
ids/module names stay frozen, only display strings change).

| Owner | Tasks |
|-------|-------|
| ui-engineer | Full mobile-first pass (bottom bar Build/Legacy/Shop/Settings, ≥44 px targets, UIScale + aspect constraints, 375×667 and 1920×1080); Build panel ×1/×10/Max; era-advance screen (next-era preview, resets-vs-persists, legacy gain, explicit confirm); welcome-back card (polished, non-blocking); `SoundController` (SoundGroups SFX/Music/UI, settings toggles, ID-0 = silent); `PlotVisualsController` (reveal tween, level-up + milestone feedback, reduce-motion per spec §10); `Format.luau` used everywhere. Carry-over from M1: a real landscape layout (M1 only guarantees 44 px targets + on-screen panel at 667×375; the aspect-ratio constraint was removed to allow viewport-derived panel height) |
| luau-engineer | Server-side FX event firing; VIP skin resolution (`Assets/<Era>_VIP/` with normal-model fallback); settings persistence; any server support the UI contract needs. Carry-over from M1: `Format` decimal mode so sub-1/s income deltas don't render as "+0/s" |
| economy-designer | `Config/Sounds.json` (all IDs 0 until upload); `tools/gen_asset_manifest.py` (era configs → `docs/ASSET_MANIFEST.md` with kit suggestions + descriptions); ensure every slot's `modelName`/`description` is manifest-ready |
| docs-keeper | Run manifest generator; MANUAL_STEPS.md Kenney import guide (3D Importer, colormap, ~8-stud house scale recorded, PrimaryPart at base-center, anchoring/collision rules, audio upload + ID pasting); PLAYTEST.md M3 |

**Done when:** game is presentable with *or without* imported assets; manifest lists every model
per era. **Playtest gate:** Ben plays on mobile emulation, then optionally starts Kenney imports.

**Shipped (2026-09-08):** `FxEvent` remote (reveal/levelUp/eraAdvance/rebirth, owner-only,
never on bulk restore); `RequestSetSetting` (music/sfx persisted in the profile); VIP skin
lookup at `ServerStorage/Assets/<Era>_VIP/<modelName>` with fallback; plot sign
(`Plot_<i>/Sign`, owner name + era displayName, `Rebirth ×n` line); `Format.Rate`/
`Format.Duration`; `Catalog.GetSoundsConfig`. Client: bottom bar Build/Legacy/Settings (Shop
built but hidden until M4); Build panel ×1/×10/Max; Legacy panel; Settings panel; era-advance
screen; ceremony overlay; welcome-back card; `SoundController` (SoundGroups, `Config/Sounds.json`,
id 0 = silent); `PlotVisualsController` (reveal tween, floating level-up text, milestone
styling, particles off under reduce-motion); landscape docking (panels dock right, top bar
top-left); reduce-motion = `TouchEnabled` OR `SavedQualityLevel` 1–3. Config/tools: era configs
v1.1 (`displayName`, per-slot `kit`), `Sounds.json`, `tools/gen_asset_manifest.py` (+ `--check`),
`docs/ASSET_MANIFEST.md`. Repo hygiene: `.gitattributes` (LF), `.gitignore`, sourcemap
regenerated. Reviewer verdict SHIP; QA green.

**Carried forward (owners assigned):**
- ui-engineer, M4: landscape viewports narrower than ~690 px (e.g. 640×360) — the right-docked
  panel overlaps the top-left top bar by ~9 px. Clamp panel width or accept the overlap on very
  narrow landscape devices — decide at M4.
- ui-engineer, M4: toggling a setting before the first `StateChanged` snapshot arrives doesn't
  call `SoundController.ApplySettings` immediately (the next snapshot/delta heals it, so it's
  cosmetic — a toggle tapped in the first second of a session may not audibly apply until data
  loads).
- ui-engineer, M4: hoist inline insets into `Theme` — `Panel.luau` header `+2`/`-16`, and
  `BuildPanel.luau` `ScrollBarThickness 4` and the empty-label height `40`.
- ui-engineer, M4: show the Shop button via `BottomBar.SetShopVisible(true)` when any
  Monetization id is non-zero; wire `WelcomeBackCard.SetDoubleOffer`; flip `passes.VIP` to
  drive the gold plot sign and VIP skins.
- ui-engineer, M4: VIP name tag (the plot sign is the rebirth cosmetic rank visual; the VIP
  name tag itself is still open).

## M4 — Monetization & analytics

**Goal:** passes, dev products, Premium, and analytics — all optional, all restrained per §6.

**Contracts frozen first:** `Monetization.json` schema (IDs default 0 = hidden), receipt
idempotency rule, time-priced grant computation, analytics event taxonomy.

| Owner | Tasks |
|-------|-------|
| luau-engineer | `MonetizationService`: cached `UserOwnsGamePassAsync` + `PromptGamePassPurchaseFinished`; idempotent `ProcessReceipt` (processedReceipts in profile, `NotProcessedYet` until data loaded); time-priced cash grants computed server-side at purchase time; `DoubleOffline` (welcome-back only); Premium 1.1×; `RequestPrompt` remote; AnalyticsService source/sink events |
| economy-designer | `Config/Monetization.json` (pass/product keys, IDs 0, pack minutes); verify paid multiplier stack ≤ 2.4×; document analytics taxonomy in BALANCE.md. Carry-over from M2 (BALANCE.md flag): `Cash8h` (480 min of income) exceeds the length of eras 1–2 — hide big packs before Era 3 or cap the grant |
| ui-engineer | Shop UI (quiet bottom-bar entry, items with ID 0 hidden, no join prompts); "Double it" button on welcome-back card (only when ID set); pass/VIP/Premium indicators; neighbors-bonus display |
| docs-keeper | MANUAL_STEPS.md: create passes/products on Creator Hub, paste IDs into Monetization.json; PLAYTEST.md M4 (incl. test purchases) |

**Done when:** with all IDs 0 the game shows no monetization anywhere and errors nowhere; with
IDs set, purchases grant correctly and receipts are idempotent. **Playtest gate:** Ben creates
real passes/products and test-buys in Studio.

**Shipped (2026-09-09):** `Config/Monetization.json` v1 (3 passes, 4 products, all ids `0`,
per-pack `capFraction` 0.10/0.25/0.50 — see "Per-pack caps" amendment below); `Economy.luau`
additions (`EraSlotCostTotal`, `PackGrant`, `PassMult`, `PremiumMult`), pure and mirrored by
`sim_economy.py`'s new `--passes`/`--premium`/`--packs` flags. Server: `MonetizationService`
(cached `UserOwnsGamePassAsync` refresh on join, `PromptGamePassPurchaseFinished` applies a pass
mid-session, idempotent `ProcessReceipt` with a rollback on failed save, VIP name tag);
`AnalyticsService` (sink/source/progression events, all `pcall`-wrapped no-ops on failure);
`EconomyService` passes/Premium live in the live/reported/persisted rate trio, Offline Pro
cap/efficiency switch, `Reserve/Release/ConsumeDoubleOfflineGrant`; `PlotService.RefreshCosmetics`
(silent VIP re-skin); `DataService.SaveAsync`; `RequestPrompt` remote with its own rate-limit
bucket (`remotes.promptCallsPerSecond`, Game.json v1.4). Client: `ShopPanel` (Passes then Packs,
id-0 items hidden, previews the persisted rate so the shown grant matches what's actually
credited), Shop button gated on any non-zero id, welcome-back "Double it", VIP/Premium/neighbors
indicator, `purchase`/`passGranted` toasts. `docs/BALANCE.md`'s M4 half: paid-stack verification
(2.42×, the exact number spec §6's own multiplier table implies — satisfies rule 5's "≤ ~2.4×"),
the per-pack-cap decision and `--packs` tables, the analytics taxonomy, and the 1 : 2.2 : 4.2
pricing ladder recommendation.

Reviewer found one Critical (a join-sequence yield that could silently zero a player's offline
grant once a real pass id existed) and four Major/Minor findings (receipt-save rollback,
`DoubleOffline` reserve-at-prompt-time instead of drop-at-receipt-time, the shop preview using
the reported rate instead of the persisted rate — up to +27% overstated in a full server — and
`RequestPrompt`'s own rate bucket). All five are fixed; see INTERFACES.md's "Post-review
amendments (M4 wave 2)" for the exact rulings. QA green (`stylua`, `selene`, `luau-lsp analyze`,
`rojo build`, `sim_economy.py --check` unchanged from M2, `gen_asset_manifest.py --check`).

**Carried forward (owners assigned):**
- **Done this milestone** (were assigned to ui-engineer at M4, from the M3 list): Shop button
  visibility wired to any non-zero id; "Double it" wired to the welcome-back card; `passes.VIP`
  driving the gold plot sign and VIP building skins; the VIP name tag on the character's head;
  the landscape-panel/top-bar overlap clamp at narrow widths; the pre-snapshot settings-toggle
  fix; the `Theme` inset hoist (`Panel.luau`, `BuildPanel.luau`).
- **New, M5 — luau-engineer:** `DataService.SaveAsync`'s durability caveat is an accepted risk,
  not a fix, for M4 (see `docs/MANUAL_STEPS.md` M4 §8 and INTERFACES.md amendment 6) — `Save()`
  is non-yielding, so a `true` return means "accepted into an active session", not "durably
  written"; a server crash in that window loses Robux with no retry. M5 should evaluate whether
  a stronger guarantee (e.g. waiting on a confirmed write, or a reconciliation job) is worth the
  added latency on a real-money path.
- **New, M5 — luau-engineer:** the open `DoubleOffline` reservation edge (a player leaving with
  an offer reserved but not completed causes a later-session receipt, if one somehow arrives, to
  grant `0` with a `warn` instead of a value) — low-frequency, documented, not fixed this
  milestone.
- **New, M5 — economy-designer / Ben:** cash-pack Robux pricing must follow the **1 : 2.2 : 4.2**
  ladder derived in `docs/BALANCE.md` (`Cash2h` at most 2.5× `Cash30m`, `Cash8h` at most 5×) —
  applies whenever real Robux prices are actually set on the Creator Hub, tracked here so it
  isn't lost before M5's final balance pass.

## M5 — Hardening

**Goal:** ship-ready. Edge cases, exploit surface, load-failure UX, final balance.

| Owner | Tasks |
|-------|-------|
| luau-engineer | Edge cases: leave mid-purchase, server shutdown flush, data-load failure (safe mode, no writes, clear player messaging), session-lock contention; rate-limit audit fixes; receipt replay defense. Carry-over from M2: replace DataService's per-frame duplicate-load busy-wait with a completion signal |
| ui-engineer | Data-load-failure client UX; feedback audit (every action has success/failure feedback); low-end reduce-motion verification |
| economy-designer | Second balance pass with sim; final `docs/BALANCE.md` (sim output tables per §4). Carry-over from M2: add `--rebirth N` to sim_economy.py (currently hardcodes rebirthCount 0, so second-lap balance has no tooling) |
| roblox-reviewer | Full-codebase audit (not just diff): server authority, exploit surface, DataStore/receipt safety, mobile UI, Rojo compat |
| qa-runner | Full suite |
| docs-keeper | Final PLAYTEST.md sweep against the spec §12 definition of done |

**Done when:** the spec's MVP definition of done holds end-to-end.

**Shipped (2026-09-09):** Server: data-load **safe mode** replaces the M2 kick-on-load-failure
rule — a player whose profile can't load stays in the server with no state/plot/writes, sees a
`loadStatus` payload (loading/failed, attempt, retryAvailableIn) on `StateChanged`, and can
retry via a new `RequestRetryLoad` remote (10 s server-side cooldown) or leave; session-lock
contention (ProfileStore waits, steals after 40 s) now shows the same loading card instead of a
kick. `DataService`'s per-frame duplicate-load busy-wait replaced by a waiter list (M2
carry-over, done). `DataService.SaveAsync(player, confirm)` now waits on ProfileStore's
`OnAfterSave` (10 s timeout) so `ProcessReceipt` reports `PurchaseGranted` only once the grant +
purchase id are durably written — retires M4 accepted risk #14 (`docs/MANUAL_STEPS.md` M4 §8);
expect a visible ~1–2 s delay on a test purchase. Profile schema **v2**: new
`pendingDoubleOfflineAmount` field with the first real migration (v1→v2); the DoubleOffline
reservation now persists so a player who leaves with the "Double it" dialog open and gets the
receipt in a later session is granted — retires M4 accepted risk #15; residual: if an old
receipt and a new reservation both settle in one session, one grants and the other grants `0`
with a `warn` (new accepted risk, `MANUAL_STEPS.md` M4 §8 item 17). `game:BindToClose` shutdown
flush now runs the leave teardown for every player still holding a profile (skipped in Studio
only when ProfileStore is in mock mode); the "loaded on another server" kick is suppressed
during shutdown. Rate-limit audit: `RequestSnapshot` gets its own 2/s bucket (`Game.json` v1.5
`remotes.snapshotCallsPerSecond`), pad touches now also spend from the `RequestBuy` bucket (a
real hole, fixed), and `RemoteService` clamps any configured rate below 1. Leave-mid-purchase
and shutdown paths audited row by row against the INTERFACES M5 tables.

Client: new `LoadScreen` card (loading copy, "Still working — another server may be finishing
your last save." after 8 s, failed state with Retry countdown + Leave, never blocks movement,
44 px tap targets); top bar shows dashes instead of "$0 / 0/s" before the first snapshot; bottom
bar (and Shop) hidden until the first snapshot; pad-touch and ProximityPrompt failures now show
a toast even with the Build panel closed (feedback-audit gap, fixed); every tween/particle
verified gated by reduce-motion.

Economy: `sim_economy.py --rebirth N` and `--laps K` (M2 carry-over, done); second balance pass
moved **nothing** — lap 1 unchanged and in band (41:50 / 1:44:15 / 4:28:49 / 9:25:10), lap 2 =
0.30× lap 1 (4:20 / 16:54 / 1:10:29 / 3:19:46), paid stack unchanged at 2.42×. Lead accepted the
designer's recommendation to keep `legacy.incomePerPoint = 0.01` and let a Phase 2 Legacy shop
handle lap-3+ runaway rather than shrink lap-1 Legacy's payoff. Cash-pack Robux pricing must
still follow the 1 : 2.2 : 4.2 ladder (`docs/BALANCE.md`) whenever real prices are set — carried
forward again below.

Still open by design at M5 sign-off: the four ambient era loops in `Sounds.json` were id `0`
(resolved 2026-09-09 after M6 — see the M6 carried-forward list); Kenney meshes never imported (placeholders by
design, per spec §5). Reviewer suggestion deferred: safe-mode players still count toward the
neighbours bonus (+3% each) for other players in the server — recorded as a known nit, not fixed
this milestone (`MANUAL_STEPS.md` M4 §8 item 18).

Reviewer verdict: full-codebase audit (not a diff review) found two Warnings, both fixed before
sign-off (see `docs/INTERFACES.md` M5 section for the exact rulings and the rate-limit/leave-
mid-purchase/shutdown audit tables). QA green: `stylua`, `selene`, `luau-lsp analyze` (fresh
sourcemap for the new `LoadScreen.luau`), `rojo build`, `sim_economy.py --check` (lap 1
unchanged from M2/M4), `gen_asset_manifest.py --check`.

**Carried forward (owners assigned):**
- **economy-designer / Ben:** cash-pack Robux pricing must follow the **1 : 2.2 : 4.2** ladder
  (`docs/BALANCE.md` "Cash packs and the era cap") whenever real Robux prices are set or revised
  on the Creator Hub — unchanged since M4, still not applied to anything (ids exist, prices are
  Ben's call).
- ~~**Ben / whoever finds a CC0 loop pack:** the four ambient era loops in `Sounds.json` remain
  `0`.~~ Resolved 2026-09-09 (see M6 below).
- **economy-designer / lead, Phase 2:** the neighbours-bonus nit (safe-mode players count toward
  `neighborsMult`) is deferred, not fixed — low priority, revisit if it ever matters in practice.
- **economy-designer / lead, Phase 2:** the Legacy shop (spec §3 "Phase 2") is the intended lever
  for lap-3+ runaway income instead of shrinking `legacy.incomePerPoint` — `docs/BALANCE.md`'s
  "M5 — rebirth laps" section has the quantified alternative (`incomePerPoint` 0.01 → 0.002 +
  era cost retuning) fully worked out if the lead ever wants that path instead.

## M6 — Legacy shop (Phase 2)

**Goal:** spec §3's Phase 2 — Legacy becomes a currency with choices. Model C from
`docs/LEGACY_SHOP.md` (Ben approved 2026-09-09): Legacy is never consumed (a spendable balance =
earned − spent), the passive multiplier soft-caps at 1000 so laps 3+ plateau near 1.5 h instead of
collapsing, seven gameplay perks (Founder's Blessing, Master Builders, Inheritance, Level Floor
5/8, Extra Milestone 75, Good Neighbours, Long Memory +2 h/tier stacking above OfflinePro) and
five cosmetic sinks. Contracts: INTERFACES.md "M6 contracts".

| Owner | Tasks |
|-------|-------|
| economy-designer | `Config/LegacyShop.json` v1; sim reads the config and mirrors the softcap + every new pure helper; BALANCE.md M6 section |
| luau-engineer | Types + schema v3 migration; `Economy.luau` softcap and perk helpers; `RequestBuyPerk`; all perk effects server-side; cosmetics in PlotService; `GrantLegacy` Studio lever; analytics |
| ui-engineer | Legacy panel becomes the shop (balance, breakdown row, perk/cosmetic rows); Build panel uses discount + per-player milestones; auto-open after ceremony; perk feedback |
| roblox-reviewer | diff review with a full pass over the Legacy/purchase path |
| qa-runner | full suite |
| docs-keeper | PLAYTEST M6 (with the `GrantLegacy` lever), MANUAL_STEPS, README |

**Done when:** the M6 definition of done in INTERFACES.md holds. **Playtest gate:** Ben buys
through the shop with the lever and sees every effect.

**Shipped (2026-09-09):** `Config/LegacyShop.json` v1, twelve perks in display order — seven
gameplay (Founder's Blessing 5 tiers +5%/tier income, Master Builders 3 tiers −10%/tier level
cost applied only inside `Economy.LevelUpCost`, Inheritance 3 tiers cash for the first 3/5/8
slots on advance/rebirth, Level Floor 2 tiers new buildings at level 5/8, Extra Milestone level
75, Good Neighbours 3%→4%/player cap 36%, Long Memory 3 tiers +2 h/tier stacked on top of the
pass's offline cap) and five cosmetics (Sign Title, Name-Tag Colour, Monument Glow, Advance
Fireworks, Golden Roads). `Game.json` v1.6 `legacy.softcap = 1000`: `Economy.LegacyMult` grows
linearly to 1000 Legacy then logarithmically (`s + s·ln(L/s)`), so laps 3+ plateau near 1:15
instead of collapsing — Model C from `docs/LEGACY_SHOP.md`, adopted. Legacy is never consumed;
`legacyShop.spent` tracks what's been bought and `Spendable = legacy − spent`. New
`Economy.luau` pure helpers (`PerkTier`, `PerkValue`, `PerkIncomeMult`, `LevelCostDiscount`,
`LevelFloor`, `MilestoneLevels`, `NeighborsParams`, `OfflineCapSeconds`, `InheritanceCash`,
`LegacySpendable`, `NextPerkTier`), all mirrored in `sim_economy.py`. Server: new
`RequestBuyPerk(perkId)` remote and `Services/LegacyShopService.luau` (boot order `DataService →
RemoteService → EconomyService → PlotService → LegacyShopService → MonetizationService →
AnalyticsService`); profile schema **v3** (`legacyShop = { spent, perks }`, silent v2→v3
migration); cosmetics applied server-side in `PlotService` (third sign line, `TitleTag`
BillboardGui stacking above the VIP tag, monument `PointLight` + Neon highlight, a ~2 s server
particle burst on advance/rebirth visible to everyone, gold tint restricted to `unlock`-type
placeholders/base-colour parts, never VIP skins); Studio-only `GrantLegacy` Workspace attribute
(numeric, consumed by the 1 Hz tick, same pattern as `ForceLoadFailure`). Client: Legacy panel is
now the shop (header Legacy/Spendable, `Legacy ×a · Perks ×b · Passes ×c` breakdown, softcap
note, perk/cosmetic rows with Tier n/N, next effect, cost, Buy, "Maxed"); Build panel reads
`LevelCostDiscount`/`MilestoneLevels` per player instead of the global config; unowned building
previews note "(opens at Lv 5)" once Level Floor is owned; the Legacy panel auto-opens once after
an advance/rebirth ceremony when any tier is affordable; `perkBought` toast + the existing
purchase sound; refusal flashes the row red. Balance (`docs/BALANCE.md` M6 section): lap 1
unchanged and in every band (41:50 / 1:44:06 / 4:15:55 / 8:37:40 with the shop in play); laps 1–6
totals 15:19:31 / 4:15:21 / 2:29:14 / 1:49:34 / 1:35:31 / 1:26:33; paid stack unchanged at 2.42×;
whole shop costs 6960 Legacy across 23 purchases. With `LegacyShop.json` removed or renamed: no
shop, no errors. Reviewer verdict SHIP after two Warnings fixed; QA green (`stylua`, `selene`,
`luau-lsp analyze` with a regenerated sourcemap for the new service, `rojo build`,
`sim_economy.py --check`, `gen_asset_manifest.py --check`). **Playtest passed 2026-09-09**
(`docs/PLAYTEST.md` M6 section). One UX fix came out of it: the Legacy panel's balance header is
pinned above the scrolling list, and the top bar reads `LEGACY <spendable> / <total>`.

**Carried forward (owners assigned):**
- **economy-designer / Ben:** cash-pack Robux pricing must still follow the **1 : 2.2 : 4.2**
  ladder (`docs/BALANCE.md` "Cash packs and the era cap") whenever real Robux prices are set or
  revised on the Creator Hub — unchanged since M4, the M6 shop doesn't touch this at all.
- **Ben:** the four ambient era loops were uploaded 2026-09-09 (CC0, OpenGameArt; real ids in
  `Sounds.json`, 13 of 100 monthly Open Cloud upload slots used) but have not been heard in
  Studio yet — `docs/PLAYTEST.md` "Post-M6 — Ambient era loops".
- **economy-designer / lead:** the safe-mode-players-count-toward-neighbours-bonus nit (M5
  carried forward, `MANUAL_STEPS.md` M4 §8 item 18) remains deferred, not fixed.
- **Ben / whoever imports meshes:** Kenney mesh import (`MANUAL_STEPS.md` M3 §2) remains fully
  optional at any pace — unchanged.
- **economy-designer / lead, next milestone:** the long-run lap sink is still open past the whole
  shop being bought out (~lap 6, `docs/BALANCE.md`/`docs/LEGACY_SHOP.md` §8) — a fifth era or a
  second cosmetic wave is the proposed answer, not scoped yet.

---

## M7 — Growing buildings: pipeline + Village (proposed 2026-09-15, awaiting Ben's go)

**Goal:** replace placeholder Parts with Kenney-kit buildings that **grow through five stages**
(stage 0 on purchase, then one stage at each base milestone 10 / 25 / 50 / 100), produced by a
fully scripted pipeline with no hand-importing. Decisions behind it: `docs/ASSET_RESEARCH.md` §1
(4 studs per kit unit, toy proportions; each stage merged into one mesh; Village tavern prototype
approved). Supersedes spec §8 (amended the same day).

**Scope — this milestone is the pipeline plus one era.** Village's 24 slots ship; Boomtown,
Metropolis and Orbital Colony are content waves in M8 (same pipeline, blueprints only); ground,
roads, props, icons and the experience thumbnail are M9. Nothing here touches balance.

**The pipeline (each step is a tool, each output is committed or generated deterministically):**
1. **Blueprints** — `tools/testfit/blueprints/<Era>/<ModelName>.json`, one per slot, file name
   equal to the era config's `modelName`. `building` slots have pieces at stages 0–4; `unlock`,
   `decor` and `monument` slots are single-stage in M7 (stage 0 only). Authored against the
   Blender test-fit renders (`tools/testfit/testfit.py`); Ben approves each era's contact sheet
   of strips before anything is uploaded.
2. **Stage merge** — Blender headless: per blueprint, per stage, join the placed pieces into one
   mesh, bake the kit colormap in (material-colour kits get a generated palette texture), scale
   ×4, origin at bottom-centre, front facing −Z, export `<ModelName>_S<n>.glb`.
3. **Upload** — Open Cloud (same key and polling as `tools/upload_audio.py`); one Model asset
   per stage, one Image asset per kit colormap (Roblox splits the texture out on import, so a
   whole kit shares one texture id, and a **VIP skin is one recoloured colormap per kit**, not
   per building). Ids and mesh sizes are written to `src/shared/Config/Assets.json` (schema in
   INTERFACES); re-runs skip anything already uploaded.
4. **Templates** — `Assets.json` → `.rbxmx` files under a Rojo-mapped folder →
   `ServerStorage/Assets/<Era>/<ModelName>`: a Model whose PrimaryPart is an invisible base Part
   at bottom-centre (so today's `PivotTo` spawn keeps working) with children `Stage0`…`Stage4`
   MeshParts (anchored, `CanCollide` only on the base). `MeshId` cannot be set by scripts, which
   is why templates are files, not runtime code. `$ignoreUnknownInstances` comes off
   `ServerStorage.Assets`; nothing is hand-placed there any more.
5. **Runtime** — `PlotService.spawnBuilding` shows the stage for the slot's current level (base
   milestones only; the Legacy `milestone75` perk changes income, not the visual), swaps to the
   next stage when `crossesMilestone` fires, and applies VIP by setting `TextureID` on the visible
   stage. Placeholder fallback is unchanged when a template or `Assets.json` entry is missing.
   Cosmetics that assumed placeholder Parts (Golden Roads tint, Monument Glow Neon) are
   redesigned for meshes.

**First proof before fan-out (lead + one agent):** the approved tavern goes through steps 2–5
alone — merge, upload, rbxmx, `rojo build`, and Ben confirms in Studio that a file-defined
MeshPart loads its mesh and texture and that the five stages swap in Play. This is the one
unverified link (rbxmx MeshParts via Rojo) and it gates everything else.

| Owner | Tasks |
|-------|-------|
| lead | INTERFACES "M7 contracts": blueprint conventions, `Assets.json` schema, template shape, stage rules, ownership; the tavern proof |
| pipeline engineer (general-purpose) | `tools/assets/`: stage merge (Blender), palette bake for material-colour kits, upload with resume, `Assets.json` writer, rbxmx generator; `default.project.json` mapping |
| asset builders (general-purpose ×3, disjoint slot sets) | 23 remaining Village blueprints, each verified by strip render; a per-era contact sheet for Ben |
| luau-engineer | Stage selection and swap in `PlotService`; VIP texture swap; cosmetic redesign; `Types`/`Catalog` additions; part-count guard |
| ui-engineer | Stage-growth animation on milestone (pop + particles reuse), Build panel "grows at Lv 25" hint, VIP preview if cheap |
| economy-designer | `gen_asset_manifest.py` reads blueprints + `Assets.json` and reports coverage per era; `ASSET_MANIFEST.md` regenerated |
| roblox-reviewer / qa-runner / docs-keeper | usual gate; PLAYTEST M7 with a cash lever to level a building through all stages; MANUAL_STEPS lists the one `.env` upload run |

**Done when:** the M7 definition of done in INTERFACES.md holds — all 24 Village slots spawn as
merged-stage meshes from Rojo-built templates, buildings grow at each base milestone with
feedback, VIP is a texture swap, placeholders still work with `Assets.json` absent, a full-stage
Village plot stays under ~40 building parts, QA green. **Playtest gate:** Ben levels a tavern
0→100 and watches it grow, then checks a VIP plot.

**Not in M7:** the other three eras (M8), ground/roads/props/icons (M9), monument growth tied to
era completion (open idea, M8 at the earliest), runtime piece composition (rejected).

---

## 6. Risks & watch items (non-blocking)

- **ProfileStore on Wally:** resolved — see assumption #1. The M2 INTERFACES update must
  unfreeze `wally.toml` and `default.project.json` shapes for the `[server-dependencies]` +
  `ServerPackages/` change. A repo-root `rokit.toml` (added at M0) pins toolchain versions so
  Rokit shims resolve from any shell.
- **Pacing targets vs playtest reality:** sim models a greedy player, not a human. Expect a
  tuning round after Ben's M2 playtest; constants live only in config, so tuning is data-only.
- **OneDrive path — stale, corrected 2026-09-09:** this line originally warned the repo lived
  under OneDrive. It does not — the repo has lived at `C:\Users\benja\Desktop\tycoon` (plain
  Desktop, not OneDrive-synced) since the environment drift noted in §1 (2026-09-08). No
  file-lock/sync risk has bitten the toolchain; nothing to watch here.
- **Era art direction:** manifest quality (kit suggestions per model) drives Ben's import effort;
  reviewed at M3 gate before any importing starts.

## 7. Blocking questions

**None.** The spec is complete enough to start M0 with the defaults in §2. If any default above
is wrong, say so at the M0 gate and it's a config/doc change, not a rework.
