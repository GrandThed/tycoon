# Era City Tycoon — Build Spec

You are a senior Roblox engineer and incremental-game designer. You are building a complete, shippable Roblox experience from this spec using **Luau**, **Rojo** (filesystem → Studio sync), and **Kenney** CC0 3D/audio assets. You cannot run Roblox Studio yourself, so everything you write must run cleanly the first time it is synced, degrade gracefully when assets or IDs are missing, and come with clear manual steps and playtest checklists for the human.

Read this whole document before writing code. Then follow the **Working agreement** at the end.

---

## 1. Game summary

**Working title:** Era City Tycoon
**Genre:** Classic Roblox plot tycoon + incremental upgrades, with **era progression as the prestige loop**.
**Platform target:** Mobile-first (most players are on phones), must also work on PC and console.
**Session shape:** 5–20 minute sessions, several per day, with meaningful offline progress.

**One-line pitch:** Claim a plot, grow a medieval village into a boomtown, a metropolis, and finally an orbital colony. Every time you complete an era, your city is reborn in the next age with a permanent bonus.

**Design pillars**
1. **Always something to buy in the next 30–90 seconds** during active play (early game), stretching to a few minutes later on.
2. **Prestige is visually dramatic.** Advancing an era swaps the entire art set. Players should want to see the next era.
3. **Fair monetization.** Everything gameplay-relevant is earnable. Robux buys convenience, cosmetics, and time, never progress gates.
4. **Zero-trust server.** The client is a display and input device; the server owns all state.

---

## 2. Core loop

1. Player joins → assigned an empty plot for their **current era** (persisted).
2. Cash accrues **automatically** every second from owned buildings (no collector to tap; keep it frictionless on mobile).
3. Player walks onto **buy pads** (classic tycoon pads) or uses the **Build panel** to purchase the next slot. Buying a building reveals its model on the plot and adds income.
4. Player taps an owned building (or its panel entry) to **level it up** — this is the incremental layer.
5. When every slot in the era is owned, the **Monument** unlocks the **Advance Era** button.
6. Advance Era → plot resets, art set changes, player earns **Legacy** (prestige currency) and a permanent multiplier.
7. After the final era, **Rebirth** returns to Era 1 with a higher Legacy multiplier and a cosmetic rank (endless loop).

---

## 3. Eras & prestige

Four eras at launch, data-driven so more can be added by adding a config file.

| # | Era name | Kenney kits (primary) | Monument (final slot) |
|---|----------|-----------------------|-----------------------|
| 1 | Village | Fantasy Town Kit and/or Retro Medieval Kit, Nature Kit, Castle Kit | Castle keep |
| 2 | Boomtown | Retro Urban Kit, Car Kit / Toy Car Kit | Town hall / clock tower |
| 3 | Metropolis | City Kit (Commercial, Suburban, Industrial, Roads), Modular Buildings, Car Kit | Skyscraper |
| 4 | Orbital Colony | Space Kit | Launch tower / rocket |

**Advance Era requirements:** all slots in the current era owned (levels do not matter).
**What resets:** cash, slots, levels, plot visuals.
**What persists:** Legacy, era index, rebirth count, cosmetics, game passes, stats.

**Legacy earned on advance**
```
legacyGain = floor(10 * eraIndex * (1 + totalLevelsThisEra / 100)) * (1 + rebirthCount * 0.5)
```
**Legacy effect:** permanent income multiplier `1 + 0.01 * effectiveLegacy` (multiplicative with everything else), where `effectiveLegacy = legacy` up to `legacy.softcap` (Game.json, 1000) and `softcap + softcap * ln(legacy / softcap)` above it — continuous at the cap, so laps 3+ plateau instead of collapsing (amended at M6, see `docs/LEGACY_SHOP.md`).
**Phase 2 — Legacy shop (shipped at M6):** permanent perks and cosmetics bought with Legacy. Legacy is never consumed: `spendable = legacy − legacyShop.spent`, and the passive multiplier keeps reading the full total. Perks and prices live in `src/shared/Config/LegacyShop.json`; Legacy is never sold for Robux and no perk touches the paid multiplier stack.

**Rebirth (after Era 4):** era → 1, rebirthCount += 1, Legacy kept, grants a cosmetic rank shown on the plot sign and name tag.

---

## 4. Economy & balancing

All constants live in config, never in logic code.

**Currencies**
- `cash` — era-scoped, resets on advance. Displayed with suffixes (1.2K, 3.4M, 5.6B, 7.8T, then aa/ab…).
- `legacy` — permanent prestige currency.

**Income**
```
incomePerSecond = Σ(slotIncome(slot, level)) × eraBase × legacyMult × passMult × premiumMult × neighborsMult
slotIncome(slot, level) = slot.baseIncome × (1 + 0.10 × (level − 1)) × milestoneMult(level)
milestoneMult(level) = 2^(number of milestones reached among {10, 25, 50, 100})
```

**Costs**
```
slotCost         = slot.baseCost                     (one-time, from era config)
levelUpCost(n)   = slot.baseCost × 0.25 × 1.15^(n−1)  (n = level being bought, max level 100)
```
Each era's `baseCost`/`baseIncome` magnitudes are roughly ×100 the previous era so numbers keep growing.

**Slot types** (each era config lists ~24 slots in purchase order)
- `building` — costs cash, adds income, reveals a model, can be leveled.
- `unlock` — a gate (e.g., "Pave the road", "Found the guild"); reveals a model, grants an era-wide `+X%` multiplier, cannot be leveled. Use 3–4 per era to create pacing beats.
- `decor` — cheap cosmetic with a tiny +1–2% multiplier. 3–5 per era.
- `monument` — always last; unlocks Advance Era.

Each slot may declare `requires = "<slotId>"` (defaults to the previous slot) so the human can branch the layout later.

**Pacing targets (active play, no passes)**
- Era 1: 30–45 min
- Era 2: 1.5–2.5 h
- Era 3: 4–6 h
- Era 4: 8–12 h

**Offline progress**
```
elapsed  = clamp(now − lastSeen, 0, offlineCapSeconds)   -- cap 8h default, 24h with Offline Pro pass
granted  = incomePerSecondAtSave × elapsed × offlineEfficiency  -- 0.5 default, 1.0 with Offline Pro
```
Show a non-blocking "Welcome back — you earned X" card on join.

**Neighbors bonus (social, non-monetized):** `neighborsMult = 1 + 0.03 × (players in server − 1)`, capped at +27%. Shown in the UI so players understand why friends help.

**Simulation requirement:** write `tools/sim_economy.py` that loads the same era JSON configs and simulates a greedy "buy the cheapest affordable thing" player at 1-second resolution, printing time-to-complete per era and a table of the longest wait between purchases. Use it to tune constants until the pacing targets are met, and include the final output in `docs/BALANCE.md`.

---

## 5. Plot system (data-driven tycoon)

- A server holds **10 plots** arranged around a central hub. Plots are claimed on join and released on leave.
- Each plot has a `PlotRoot` model with a fixed grid of **anchor points** (`Attachment`s named `Slot_<slotId>`) and a matching **buy pad** per slot. Anchors are laid out per era in a **layout module** (position + rotation per slotId), so the plot geometry is code, not hand-placed parts.
- Buy pads are generated at runtime from the era config: a pad shows the slot name and cost, is visible only when its `requires` slot is owned, and disappears when bought.
- Buying reveals the model: clone from `ServerStorage/Assets/<EraName>/<modelName>` to the anchor with a short scale-up tween and a sound.
- **Placeholder fallback (required):** if the model is missing, spawn a colored `Part` sized ~8×8×8 studs with a `BillboardGui` showing `modelName`. The game must be fully playable before a single Kenney asset is imported.
- Other players can walk through and look at any plot; only the owner can interact. No griefing vectors.
- Level-ups are triggered by a `ProximityPrompt` on the building **and** from the Build panel.

---

## 6. Monetization (deliberately restrained)

**Rules**
1. No building, era, or feature is ever gated behind Robux.
2. No purchase prompts on join. One quiet **Shop** button in the bottom bar.
3. At most **one** contextual offer per session: the welcome-back card may show a small "Double it" button (dev product). Never a blocking modal.
4. No random/loot mechanics of any kind.
5. Total paid income multiplier stack must stay ≤ ~2.4× (2× pass × VIP 1.1 × Premium 1.1).
6. Cash packs are priced in **time**, not absolute cash: the server computes the grant as `N minutes × current incomePerSecond` at purchase time, so a pack can never skip an era or break the curve.

**Game passes (permanent)**
| Key | Effect |
|-----|--------|
| `DoubleCash` | 2× income |
| `OfflinePro` | Offline cap 8h → 24h, efficiency 50% → 100% |
| `VIP` | +10% income, VIP name tag, cosmetic building skin set per era, gold plot sign |

**Developer products (consumable)**
| Key | Grant |
|-----|-------|
| `Cash30m` | 30 minutes of current income |
| `Cash2h` | 2 hours of current income |
| `Cash8h` | 8 hours of current income |
| `DoubleOffline` | Doubles the most recent offline grant (only offered on the welcome-back card) |

**Premium:** Roblox Premium members get a 1.1× multiplier (shown in the UI, encourages Premium payouts).

**Implementation notes**
- All IDs live in `src/shared/Config/Monetization.json`. If an ID is `0`, hide that item from the UI so the game works before the human creates the products.
- `MarketplaceService.ProcessReceipt` must be idempotent: store processed `PurchaseId`s in the profile; return `NotProcessedYet` if data isn't loaded.
- Cache `UserOwnsGamePassAsync` per session; also listen to `PromptGamePassPurchaseFinished` to apply passes immediately.
- Log economy events with `AnalyticsService` (source/sink) so the human can tune later.

---

## 7. Architecture & tech

**Repo layout (Rojo)**
```
default.project.json
wally.toml                      -- ProfileStore (loleris) + optional Signal lib
src/
  server/                       -- ServerScriptService/Server
    Main.server.luau
    Services/
      DataService.luau          -- ProfileStore wrapper, migrations, session lock
      PlotService.luau          -- claim/release, build, level-up, era advance
      EconomyService.luau       -- income tick, multipliers, offline calc
      MonetizationService.luau  -- passes, products, ProcessReceipt
      RemoteService.luau        -- remote creation, validation, rate limiting
  shared/                       -- ReplicatedStorage/Shared
    Config/
      Game.json                 -- global constants (tick rate, plot count, caps)
      Monetization.json
      Sounds.json
      Eras/
        1_Village.json
        2_Boomtown.json
        3_Metropolis.json
        4_OrbitalColony.json
    Layouts/                    -- per-era anchor positions (Luau modules)
    Economy.luau                -- pure functions: costs, income, legacy (no Roblox APIs; unit-testable)
    Format.luau                 -- number formatting
    Types.luau
  client/                       -- StarterPlayer/StarterPlayerScripts/Client
    Main.client.luau
    Controllers/
      UIController.luau
      SoundController.luau
      PlotVisualsController.luau
    UI/                         -- UI built in code (Rojo-friendly, versionable)
tools/
  sim_economy.py
  gen_asset_manifest.py         -- reads era configs → docs/ASSET_MANIFEST.md
docs/
  PLAN.md  PLAYTEST.md  MANUAL_STEPS.md  ASSET_MANIFEST.md  BALANCE.md
```
- Rojo syncs `*.json` under `Config/` as ModuleScripts that return the decoded table, so Luau and Python read the same files. Never duplicate constants.
- In `default.project.json`, set `"$ignoreUnknownInstances": true` on `ServerStorage` (and anywhere the human places hand-imported assets) so syncs never delete imported meshes.
- Hand-imported assets live in `ServerStorage/Assets/<EraName>/<modelName>` and are **not** managed by Rojo.

**Server authority**
- Remotes: `RequestBuy(slotId)`, `RequestLevelUp(slotId, count)`, `RequestAdvanceEra()`, `RequestRebirth()`, `RequestPrompt(productKey)`. Server validates types, ownership, affordability, and `requires` chain; never trusts amounts from the client.
- Rate-limit each remote per player (e.g., 10 calls/s) and drop, don't kick, on overflow.
- Income tick: one server loop at 1 Hz per player, using accumulated delta time (no drift).
- Replication: push a full state snapshot on join, then batched deltas (≤ 4/s) via a single `StateChanged` remote. Cash may additionally be mirrored to a player attribute for cheap UI binding.

**Data**
- Use **ProfileStore** via Wally. If Wally is unavailable in the environment, write a minimal DataStore module with session locking, `UpdateAsync`, exponential-backoff retries, and `BindToClose` flushing — and say so in `docs/PLAN.md`.
- Schema v1:
```lua
{
  version = 1,
  cash = 0, era = 1, rebirthCount = 0, legacy = 0,
  slots = { [slotId] = { level = n } },   -- presence = owned
  passes = {}, processedReceipts = {},
  lastSeen = 0, incomeAtSave = 0,
  stats = { totalCashAllTime = 0, erasCompleted = 0, playtimeSeconds = 0 },
  settings = { music = true, sfx = true },
}
```
- Include a `Migrations` table keyed by version; run sequentially on load.

---

## 8. Asset pipeline (Kenney)

The human imports meshes; you generate the list of what to import.

- Run `tools/gen_asset_manifest.py` to produce `docs/ASSET_MANIFEST.md`: every `modelName` referenced by every era config, grouped by era, with the suggested Kenney kit and a one-line description (e.g., "small house with red roof").
- Naming convention: `modelName` in config **must equal** the Model name in `ServerStorage/Assets/<EraName>/`. Use PascalCase without spaces (`HouseSmallA`, `Blacksmith`, `Windmill`, `Diner`, `GasStation`, `SkyscraperA`, `DomeHabitat`).
- Import rules for the human (write these into `docs/MANUAL_STEPS.md`):
  - Use Studio's 3D Importer with the kit's FBX/OBJ; make sure the kit's `colormap` texture is applied.
  - Choose one import scale so a standard house is ~8 studs wide; use the same scale for every kit and record it in the doc.
  - Each asset is a `Model` with a `PrimaryPart` at the base-center, all parts `Anchored`, `CanCollide` on for large structures only.
  - Kenney assets are CC0; no attribution required, but add a credits line in the game description anyway.
- Ground/roads/props: Nature Kit trees and rocks for Era 1–3 edges, City Kit Roads for Era 2–3, Space Kit floor tiles for Era 4. The plot base itself is a plain part tinted per era.
- VIP skins: a second folder `ServerStorage/Assets/<EraName>_VIP/` with recolored or alternate variants; fall back to the normal model if a VIP variant is missing.

---

## 9. Audio (Kenney sound packs)

Sound asset IDs live in `src/shared/Config/Sounds.json`; an ID of `0` means "silent, don't error". Route everything through `SoundService` `SoundGroup`s (`SFX`, `Music`, `UI`) with per-player volume settings.

| Event | Suggested Kenney pack |
|-------|-----------------------|
| UI click / hover | UI Audio, Interface Sounds |
| Purchase confirmed | Casino Audio (coin) |
| Level up | Interface Sounds (short rising tick); pitch up slightly with milestone levels |
| Building reveal | Impact Sounds (soft thud) + a pop |
| Insufficient funds | Interface Sounds (error) |
| Era advance / rebirth | Music Jingles (fanfare) |
| Welcome back | Music Jingles (short) |
| Ambient loop per era | optional, low volume, toggleable |

Keep SFX short and quiet by default; mobile players often have sound off, so nothing may depend on audio.

---

## 10. UI / UX

- Build UI in Luau (no `.rbxm`), scaled with `UIScale` + `UIAspectRatioConstraint`; verify at 375×667 and 1920×1080 in the playtest checklist.
- **Top bar:** cash, income/s, era badge (name + number), Legacy count.
- **Bottom bar:** Build (slot list with buy/level buttons and "next affordable" highlight), Legacy, Shop, Settings.
- **Build panel** shows: slot name, cost, income delta, "Buy ×1 / ×10 / Max" for levels. Big tap targets (≥ 44 px).
- **Advance Era screen:** preview the next era name and kit, list what resets vs. persists, show Legacy to be gained, require an explicit confirm.
- **Welcome-back card:** non-blocking toast with offline earnings and (only if the dev product ID is set) a small "Double it" button.
- **Number formatting:** `Format.luau` (1.2K, 3.4M, …), never raw floats in the UI.
- Reduce motion when `UserInputService.TouchEnabled` and low-end signals are detected (fewer particles, shorter tweens).

---

## 11. Coding standards

- `--!strict` in every file; typed public functions; `Types.luau` for shared types.
- PascalCase for modules/services, camelCase for locals, `UPPER_SNAKE` for constants.
- No `wait()`, `spawn()`, `delay()`, `_G`, or `Instance.new` with the parent argument. Use `task.*`.
- Every DataStore / Marketplace / HTTP call wrapped in `pcall` with retry and logging.
- `Economy.luau` is pure (no Roblox globals) so it can be reasoned about and mirrored in the Python sim.
- Comments explain *why*, not *what*. No dead code.
- Run `stylua` and `selene` if available; include configs for both.

---

## 12. Working agreement

1. **First response:** read this spec and produce `docs/PLAN.md` with milestones, assumptions, and any *blocking* questions. Ask only what actually blocks Milestone 0–1; otherwise choose sensible defaults and document them.
2. **Milestones** (stop after each for a human playtest; do not proceed until told):
   - **M0 — Scaffold:** `default.project.json`, folder layout, Wally setup, README, `Game.json`, empty services that boot without errors.
   - **M1 — Playable loop:** plot claim, Era 1 config (24 slots), buy pads, income tick, level-ups, placeholder buildings, minimal HUD. Playable end-to-end with no Kenney assets.
   - **M2 — Persistence & eras:** ProfileStore, migrations, offline progress, all four era configs and layouts, Advance Era, Rebirth, Legacy multiplier, `sim_economy.py` + first balance pass.
   - **M3 — Presentation:** full mobile UI, sounds, reveal/level-up feedback, era-advance screen, welcome-back card, asset manifest generator, VIP skin support.
   - **M4 — Monetization & analytics:** passes, products, `ProcessReceipt`, Premium bonus, Analytics events, Shop UI.
   - **M5 — Hardening:** rate limits audit, edge cases (leave mid-purchase, server shutdown, data load failure UX), second balance pass, `docs/BALANCE.md`.
3. After every milestone update `docs/PLAYTEST.md` (step-by-step checks the human performs in Studio, including mobile emulation) and `docs/MANUAL_STEPS.md` (anything requiring Studio or Creator Hub: mesh import, audio upload, creating passes/products and pasting IDs into config).
4. Never write code that assumes an asset or ID exists. Missing things degrade to placeholders, never errors.
5. Keep changes small and reviewable; explain notable design decisions in one or two sentences, not essays.
6. If something in this spec conflicts with a Roblox platform constraint or a current Roblox policy, say so and propose the closest compliant alternative before implementing.

**Definition of done (MVP):** a new player can join on a phone, complete Era 1 in roughly 30–45 minutes without spending, leave, come back to offline earnings, reach Era 4, rebirth, and never see a purchase prompt they didn't open themselves.
