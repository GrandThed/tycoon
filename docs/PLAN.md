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
- [x] M7 — Growing buildings: pipeline + Village (review SHIP after two Warnings fixed, QA green;
  all 24 Village slots harvested, uploaded, and templated; **playtest pending**)
- [x] M8 — Growing buildings: the other three eras (**complete 2026-09-22**; content waves;
  **Boomtown shipped 2026-09-16**, approved in Ben's Studio look with one fix; **Metropolis
  shipped 2026-09-18** — 24 blueprints, 89 assets uploaded and harvested, 24 templates, Stadium at
  a new 12×12 footprint; **Orbital Colony shipped 2026-09-22** — 24 blueprints, 90 assets uploaded
  90/90 first try and harvested in one paste, 24 templates, a generated `orbital-kit`, three 12×12
  landmarks and a 12×9 Rover Bay. **All 4 eras / 96 models now have real meshes**; Boomtown was approved
  in a Studio look, the Metropolis and Orbital Colony **PLAYTEST sections are pending** — see
  "M8" below)
- [~] M9 — City dressing: roads, trees, filler, squares, vehicles (wave 1 review SHIP, QA green;
  contracts, layouts, pipeline, blueprints, client and prop uploads, harvest and 18 prop
  templates shipped 2026-09-16; **wave 1d baked paths shipped and approved in Studio
  2026-09-18** — 91 pieces for Village + Boomtown; **wave 1e street upgrades shipped
  2026-09-18** — Pave the Road / Pave Main Street / Streetlamp Row / Traffic Lights now change
  the streets, review no Criticals, QA green, harvest paste done 2026-09-18, **Studio playtest (PLAYTEST 4b) pending**
  (`docs/MANUAL_STEPS.md` M9 §7); **wave 2a Metropolis streets shipped 2026-09-22** — tile
  streets, elevated ring highway, subway kiosks and Found City Hall, review SHIP after two
  Majors fixed, both harvest pastes done 2026-09-22; **wave 2a fix round shipped 2026-09-22**
  after Ben's first Studio look — the glTF importer's 180° Y turn is now compensated for
  **buildings and props in every era**, plus per-cell pavement, paved blocks with street trees,
  14×14 plazas and a ramp on pillars, both pastes done 2026-09-22; **wave 2a third round
  shipped 2026-09-22** after Ben's second Studio look — park strips (grass + planters) on every
  planned-but-undrawn street cell, the highway rebuilt on a custom `highway-kit` (box girder on
  piers), `ParkingGarage` rebuilt on a custom `garage-kit` and City Hall rebuilt **kit-only**;
  both pastes done and templated 2026-09-23 (commit `3613cfc`), signed off; **wave 2b Orbital
  Colony dressing + `cityDetail` shipped 2026-09-23** — tube corridors, monorail loop, decking,
  rock fields, domes and the persisted "City detail" setting, review no Criticals (two Majors
  fixed); Orbital props uploaded, harvested and templated 2026-09-23 (commit `9202896`), PLAYTEST
  M9 sections 4f + 4g pending; **wave 2c "living city" built 2026-09-23** (Village, Boomtown,
  Metropolis) — more houses, greenery, parked cars, more traffic, walkers, chimney smoke and bird
  flocks, all keyed to `GrowthTier`; 48 props uploaded, harvested (48/48) and templated; **main fast-forwarded to the
  merged tree 2026-09-23 (`3769c2a`) and Ben signed off waves 2b and 2c the same day ("looks
  good, lets finish this") — M9 is complete**; **wave 2d (half-size cars at runtime, 4× traffic with a lane-hold rule, two parked per bay in Boomtown + Metropolis) and the mirrored-kit-node winding fix (19 stages re-uploaded) signed off 2026-09-23 ("looks good!")**; carried forward: the 12cx MicroProfiler number and
  the 12cy part counts were not reported, so the part-budget re-cut stays a lead watch item)

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

**Shipped (wave 2a — Metropolis streets, highway, subway, 2026-09-22):** Metropolis gets its own
street language and three slots change meaning. Still client-only apart from the era JSON (one
renamed slot, two `streetOnly`); Village and Boomtown are untouched. Contracts:
`docs/INTERFACES.md` "Wave 2a — Metropolis streets, highway, subway".

- **Three slots change meaning:** `cityGrid` keeps its id (no profile migration) but becomes
  **"Found City Hall"** — a real kit building, `modelName` `CityHall`, one stage because it is an
  `unlock` slot, `rotationY` 0 at the plot centre facing the entrance. `subwayLine` and
  `highwayRamp` become **`streetOnly`**: the server spawns an empty `Building_<id>` marker and the
  client draws the infrastructure. The old `RoadIntersection` / `HighwayRamp` / `SubwayEntrance`
  blueprints and templates stay in the repo, unused (same ruling as wave 1e).
- **Tile streets (`road.tiles`, new `src/client/City/TileRenderer.luau`):** Ben chose Kenney
  `city-kit-roads` tiles at **7 studs** (four per 28-stud block pitch) over baked meshes for this
  era. The renderer rasterises the *visible* spine to cells and picks each cell's prop from its
  **visible 4-neighbour connectivity** — `end` → `straight` → `bend` → `tee` → `cross` as the
  network grows — with a zebra **`crossing`** cell at junction mouths on runs of ≥ 3 cells. Plain
  **pavement Parts** run either side of each stretch, and a building's **footpath spur is clipped
  at the pavement edge** so it never overlaps the asphalt. `budget.tileCells` 180; Metropolis uses
  **38** at full ownership.
- **Elevated ring highway (`highway`, new `Highway.luau`):** owning **Build the Highway Ramp**
  draws a ring at `ring` **56** (deck road surface **7.07** studs, soffit **6.65**, so characters
  walk under it — including at the plot entrance) with a single **3-cell ramp** descending east
  into the arterial's west end at (−35, −28). On purchase the ring **builds outward from the ramp
  in both directions** at `revealCellsPerSecond` 12 (≈ 5 s); joins, era rebuilds and far plots get
  it instantly. **Two cars** loop the deck and never take the ramp. `budget.highwayCells` 72;
  Metropolis uses **66**. The `HighwaySign` gantry is **skipped when it would clip a footprint** —
  with today's 7-stud-wide sign that means it never appears on Metropolis.
- **Subway (`subway`):** owning **Dig the Subway Line** places up to **5 `MetroEntrance` kiosks**
  at street corners, each tied to its nearest spine stretch so it appears as that street becomes
  visible; the kiosk nearest the plot entrance is exempt, so buying the slot always shows one. The
  kiosk is **custom Blender geometry** (`tools/assets/metro_kit.py` → `assets/kenney3d/metro-kit/`,
  colour-only materials routed through `palette.py`, the `stadium_kit.py` pattern) because no City
  Kit has stairs going down.
- **Layout (`src/shared/Layouts/Metropolis.luau`):** the **x = 0 civic axis is car-free** (entrance
  avenue → City Hall at (0, 0, 0) → the Skyscraper monument moved to (0, 0, 28)); traffic avenues
  at x = ±28 and the arterial at z = −28 make **4 polylines that form a tree** (a closed block
  would leave one stretch never drawn). Moved slots: `financeDistrict` (14, 0, 28), `cityPark`
  (−13, 0, 0), `rooftopGarden` (13, 0, 0), `busStop` (37, 0, 0), `subwayLine` (6.5, 0, −41),
  `highwayRamp` (−35, 0, −21.5), Stadium pad at (−42, 0, 33) with `rotationY` 0; `padOffset` 7.5.
  `py tools/streetplan.py Metropolis` now checks the lattice, the highway band, the ramp foot, the
  entrance spots and the tree zones and is **green (0 violations)** — PNG at
  `assets/testfit/out/Metropolis/streetplan.png`.
- **Config (`CityDressing.json`):** `budget.tileCells` 180 and `budget.highwayCells` 72;
  Metropolis `road.tiles`, `road.laneOffsetFraction` 0.2, `highway` (incl. `deckHeight` 7.07),
  `subway`, and `houses.props` `[]` (the blocks are already full of buildings). A shared
  `Dust.luau` now owns the burst effect for paths, tiles and surfaces.
- **Degrades silently:** a missing `templates/_props/Metropolis` draws **grey placeholder cells**
  and nothing else; a missing highway/subway prop or layout key draws nothing; no Output error in
  any case.
- **Assets:** 21 Metropolis props (`RoadStraight/End/Bend/Tee/Cross/Crossing`,
  `HighwayDeck/Corner/Junction/Ramp/Sign`, `MetroEntrance`, `LampPost`, `TrafficLight`,
  `VehicleA–D` at blueprint scale **1.8** so two 2.7-stud-wide cars pass on 5.6 studs of asphalt,
  `TreeGrowing` S0–S3, `PlazaA/B`) plus `CityHall` merged and uploaded (commit `c9f7f37`) —
  **not harvested yet**, that is Ben's one manual step below.
- **Review (roblox-reviewer): no Criticals, verdict SHIP after the harvest.** Two Majors fixed —
  the spur colour snapshot regressed Boomtown's gravel spurs, and the Metropolis footpath
  overlapped the asphalt instead of stopping at the kerb — plus 9 minors and 3 tool nits.

**Shipped (wave 2a fix round — after Ben's first Studio playtest, 2026-09-22):**

> **Cross-era change, affects every era since M7.** Roblox's glTF import turns every harvested
> model **180° about Y** (+Z-forward becomes −Z-forward). `tools/assets/gen_templates.py`
> compensated only path meshes; commit `b17718e` moves that compensation into one code path
> (`harvested_cframe`) used by **buildings and props too**. Consequence: **every building in
> every era now faces its buy pad** (the blueprint −Z front), props sit as authored, and cars
> drive **nose-first** (Boomtown's drove tail-first before). Templates were regenerated from the
> existing harvest — **no re-upload and no new harvest paste were needed for this**. Village and
> Boomtown need a spot check in the playtest (PLAYTEST §4d).

- **Client fixes (`TileRenderer`, `RoadGraph`, `Scatter`, `CityDressingController`):** pavement is
  now **per cell** — strips only on a cell's closed sides, corner squares at bends, never a strip
  over asphalt, crossroad cells bare, street ends closed with a U; the highway ramp and its sign
  use the measured ramp descent for placement; **spur footpaths are clipped at the kerb** so they
  stop at the pavement edge. Templates now carry the importer turn, so the client places props
  unturned.
- **Paved blocks + street trees (Ben's choice; contract: INTERFACES "### Paved blocks"):** the
  Metropolis layout gains `blocks` — **12 rectangles** of ground between the streets, each listing
  the slots standing on it. A block's slab appears as soon as **any** of its slots is owned (with
  the dust burst on a near plot). **Street trees** are posted every **9 studs** along each block
  edge that faces a *visible* street, `treeInset` 1.5 studs in, skipping footprints, pads, spurs
  and kiosks; `trees.maxCount` rises **24 → 40** and zone trees take the remainder of the budget.
  Config: `road.tiles.blocks` (`Concrete`, colour 148/152/168, `treeSpacing` 9, `treeInset` 1.5).
- **Plazas:** `PlazaA` / `PlazaB` rebuilt at **14×14** with a street apron and placed **flush
  against an avenue** — PlazaA on the west avenue at z = 0, PlazaB on the east avenue at z = −28.
  Both **re-uploaded**; `tools/streetplan.py` now checks plaza clearance and the flush edge.
- **City Hall rebuilt:** white body plus a custom **`cityhall-kit`** (dome, drum, lantern, clock,
  columns, pediment) generated by `tools/assets/cityhall_kit.py` (Blender, deterministic,
  1 unit = 4 studs — the `stadium_kit.py` / `metro_kit.py` pattern). **20.7 studs tall, 1,742
  tris**; **re-uploaded**. `HighwayRamp` **re-uploaded** with mid-span pillars, because every
  slant piece in `city-kit-roads` is a **zero-thickness sheet** and the deck showed daylight
  under it.
- **New tool — offline plot render (`tools/testfit/plotrender.py` + `plotscene.py`, README
  "Plot render"):** assembles a whole plot (buildings at final stage, streets, pavements, spurs,
  pads, highway, kiosks, plazas, trees, traffic) from the same layout and config the game reads,
  and renders it from the tycoon camera:
  `py tools/testfit/plotrender.py <Era> --camera overview|entrance|ramp|plaza|cityhall` →
  `assets/testfit/out/<Era>/plot_<camera>.png`, ~1–2 min per render. It mirrors the contract
  rather than re-deriving it, and it is now **the reference Ben compares Studio against** — the
  M9 lead renders and reviews the PNGs **before asking for any Studio look**.
- **Assets owed:** `PlazaA`, `PlazaB`, `HighwayRamp` (props) and `CityHall` (building) were
  re-uploaded; both pastes were run 2026-09-22 (commits `08643ef`, `ad67484`).

**Shipped (wave 2a third round — after Ben's second Studio playtest, 2026-09-22):** four notes
from Ben — a junction whose other street had not grown showed a **dead-end sidewalk beside bare
ground**; the parking garage was "streets stacked up"; the highway was "just some street below it
to raise it"; the dome City Hall was "way too big, way off, ugly". Still client-only apart from
the era JSON `kit` strings. Contracts: `docs/INTERFACES.md` "Wave 2a" → "### Park strips in
undrawn corridors", "### Elevated highway", "### Paved blocks".

- **Park strips (`road.tiles.parkStrips`, Ben: "fill with a small park strip"):** every
  **planned-but-undrawn** street cell now carries a **Grass slab** (104, 146, 92) covering the
  cell and its unlaid pavement band, plus one **`TreeGrowing` stage-1 planter per cell** along the
  run's centreline (cap **24** per plot, thinned evenly). When the stretch draws, its strips and
  planters are removed **in the same update the tiles land**, so the dust burst covers the swap.
  A fresh Metropolis plot therefore shows the **whole future street grid as green strips** instead
  of bare ground — that is the intended look. Client only (`TileRenderer`, `Scatter`, `RoadGraph`,
  `CityDressingController`); mirrored offline by `py tools/testfit/plotrender.py Metropolis
  --tier 2` → `assets/testfit/out/Metropolis/plot_tier2.png`.
- **Highway rebuilt on a custom kit (`tools/assets/highway_kit.py` → `highway-kit`):** a real
  **box-girder deck on concrete piers**, with barriers and lane lines, at blueprint scale **1.0**
  — road surface **7.07**, soffit **6.10** (characters still walk under it, including at the plot
  entrance). Same prop names, origins and orientations as before, so the **client is unchanged**
  except one fix: the ramp's first cell now sits **fully inward** from the junction cell.
  Re-uploaded: `HighwayDeck`, `HighwayCorner`, `HighwayJunction`, `HighwayRamp`.
- **ParkingGarage rebuilt on a custom kit (`tools/assets/garage_kit.py` → `garage-kit`):** lot,
  deck, ramp, column, core, booth, barrier, sign and cars — **5 stages, 2.35 → 13.8 studs,
  ≤ 3,000 tris**, so it grows from a surface lot to a four-deck garage instead of reading as
  stacked streets.
- **City Hall rebuilt kit-only** (Ben: "modern civic, kit only"): **12.3 studs**, three white
  bays, a canopy entrance, **3 flag masts**, planters and lamps, **9.6k tris**. The generated
  `tools/assets/cityhall_kit.py` was **deleted** and the slot's description/`kit` strings updated.
  **Honest caveat:** `city-kit-commercial` has no civic piece, so it reads as a *white civic block
  with flags*, not a landmark town hall.
- **Config/manifest:** era JSON `kit` strings for custom-kit slots now read `Custom (<kit>)`;
  `docs/ASSET_MANIFEST.md` regenerated (4 eras, 96 models).
- **Review (roblox-reviewer):** one Critical — the **harvest sequencing** below. Two Majors fixed:
  duplicate planters at cells shared by two junctions, and the ramp origin half a cell inside the
  junction. Minors fixed: a nil guard, deterministic strip ordering, the kiosk cut and a coplanar
  spur top.
- **Assets owed:** the four highway props, `ParkingGarage` ×5 stages, `CityHall` and the
  `garage-kit` VIP swatch were re-uploaded (commit `a0763f9`), so their `meshId` / `imageId` are
  zeroed until Ben runs **one props paste (4 records) and one buildings paste (7 records)** —
  `docs/MANUAL_STEPS.md` "M9" §10.

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

## M7 — Growing buildings: pipeline + Village

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

**First proof before fan-out (lead + one agent) — passed 2026-09-16:** the approved tavern went
through steps 2–5 alone — merge, upload, rbxmx, `rojo build` — and Ben confirmed in Studio that
all five Tavern stages load their mesh and texture, correctly sized, sitting on the ground, from
a Rojo-built `.rbxmx` (`ServerStorage.Assets.Village.Tavern`). The `InsertService:LoadAsset`
fallback was not needed. Bonus finding: Roblox deduplicates the texture across stage uploads (all
five returned the same `imageId`), so a kit's texture id is stable. This was the one unverified
link (rbxmx MeshParts via Rojo) and it gated everything else — resolved, fan-out proceeded.

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

**Shipped (2026-09-16):** all 24 Village slots (blueprints in `tools/testfit/blueprints/Village/`,
authored by three disjoint builders and verified with `tools/testfit/testfit.py` strip renders)
went through the full pipeline — `merge_stages.py` (Blender, one mesh per kit per stage, palette
bake for material-colour kits), `upload_models.py` (79 stage models + 2 VIP swatches uploaded to
Open Cloud, idempotent/resumable), the one Studio step (`harvest.py --emit` → paste
`harvest.luau` into the command bar → copy Output → `harvest.py`), `gen_templates.py`
(`templates/Village/<ModelName>.rbxmx`, generated-only). `src/shared/Config/Assets.json` v1 holds
every id/size. Server: `PlotService.stageForLevel` (base milestones 10/25/50/100 only — the
Legacy `milestone75` perk changes income, not the visual), stage swap on milestone crossing,
`FxEvent stageUp`, VIP as a per-kit `TextureID` swap, Golden Roads/Monument Glow redesigned for
meshes (`Highlight` instead of `Neon`), `LevelUpPrompt` moved onto a `PromptAnchor` attachment at
half the visible stage's height (review fix — it was parented to the Model, inert on a real
template). Client: growth pop on `stageUp` implemented as a snapshot-based scale animation (not
`Model:ScaleTo`, review fix), the Build-panel hint merged to "×2 & grows at Lv 25" (review fix),
FX origin moved to `PromptAnchor` (review fix). New Studio-only `GrantCash` lever (same pattern as
`GrantLegacy`, consumed once by the 1 Hz tick; does not bump `stats.totalCashAllTime`) for the
stage-growth playtest. `tools/gen_asset_manifest.py` is now a per-slot pipeline coverage report
(blueprint / stage GLBs / uploaded / harvested / templated); `docs/ASSET_MANIFEST.md` regenerated.
Spec §8 amended the same day to match (merged-stage meshes, not runtime piece composition).

Reviewer found two Warnings on the first pass — both fixed before sign-off: the `LevelUpPrompt`
parented to a template's inert Model instead of its `Base` BasePart, and the client using
`Model:ScaleTo` for the growth pop where the codebase's established pattern is snapshot-driven
tweening. QA green (`stylua`, `selene`, `luau-lsp analyze` with a regenerated sourcemap,
`rojo build`, `sim_economy.py --check` unchanged, `gen_asset_manifest.py --check`,
`gen_templates.py --check`). **Playtest pending** — `docs/PLAYTEST.md` "M7 — Growing buildings
(Village)".

**Carried forward (owners assigned):**
- **pipeline-engineer / lead, M8:** the same pipeline (blueprints → merge → upload → harvest →
  templates) repeats for Boomtown, Metropolis, and Orbital Colony — no new tooling expected,
  content only. **Kit decision 2026-09-16:** Boomtown = city-kit-suburban + city-kit-industrial,
  Metropolis = city-kit-commercial (drafts in `tools/testfit/blueprints/_drafts/`); see
  `docs/ASSET_RESEARCH.md` §4. Boomtown authoring restarts in a fresh session from
  `docs/prompts/boomtown-suburban-industrial.md`. **Now tracked in the M8 section below**
  (Boomtown and Metropolis shipped; Orbital Colony open).
- **lead, M9:** city dressing (roads, trees, filler, squares, vehicles) is now the M9 section
  below (contracts frozen 2026-09-16). Icons and the experience thumbnail move to M10.
- **lead / economy-designer, open idea:** monument growth tied to era completion, raised at M7
  scoping, not designed or scheduled.
- **economy-designer / Ben:** cash-pack Robux pricing still must follow the 1 : 2.2 : 4.2 ladder
  (`docs/BALANCE.md`) whenever real prices are set — unchanged since M4/M5/M6, M7 doesn't touch
  monetization at all.
- **economy-designer / lead:** the ambient-loop items and the long-run lap-6+ sink (both carried
  from M6) remain open, untouched by M7.

**Not in M7:** the other three eras (M8), ground/roads/props/icons (M9), monument growth tied to
era completion (open idea, M8 at the earliest), runtime piece composition (rejected).

---

## M8 — Growing buildings: Boomtown, Metropolis, Orbital Colony

**Goal:** run M7's pipeline (blueprints → merge → upload → harvest → templates) over the remaining
three eras. Content only — no new tooling, no balance change, no Luau except fixes found in
Studio. One era per wave; each wave is 24 blueprints authored by three Opus builders on disjoint
slot sets, verified with `tools/testfit/testfit.py` strip renders and a per-era contact sheet Ben
approves, then one upload run, one Studio harvest paste, and `gen_templates.py`.

**Kit decision (2026-09-16, `docs/ASSET_RESEARCH.md` §4):** Boomtown = `city-kit-suburban` +
`city-kit-industrial`, Metropolis = `city-kit-commercial`; `city-kit-roads` supplies street props
to both. Each building kit belongs to exactly one era, so the eras differ by building type and
height, not palette. `retro-urban-kit` was built and rejected by Ben (22 tiling textures the
one-texture merge can't handle).

| Owner | Tasks |
|-------|-------|
| lead | per-wave INTERFACES amendments (footprint rule, kit assignment), contact-sheet reviews |
| asset builders (general-purpose ×3, Opus, disjoint slot sets) | 24 blueprints per era, each verified by strip render |
| pipeline (lead) | `merge_stages.py` → `upload_models.py` → `harvest.py` → `gen_templates.py` per era |
| docs-keeper | PLAYTEST section per era, MANUAL_STEPS status, `ASSET_MANIFEST.md` |

**Wave 1 — Boomtown, shipped 2026-09-16** (Ben, on the contact sheet: "looks fantastic"): 24
blueprints in `tools/testfit/blueprints/Boomtown/`, 88 stage models + 3 VIP swatches uploaded and
harvested, 24 templates in `templates/Boomtown/`. Direction is **"lower, wider"** — ordinary
slots top out around 13 studs and grow by width and clutter; only Fire Station (18.7) < Radio
Station (21.3) < Clock Tower (25.8) are tall, leaving height to Metropolis. Ben's Studio look
produced one content fix (Gas Station rebuilt with the fuel tank on the ground, `31310d2` /
`f2c41e0`) plus two engine fixes shipped alongside: buildings sinking into plots, the VIP skin
toggle and hiding buildings until assets load (`6498cc1`), and the plot ring resized so radial
plot corners never overlap (`0a25412`). Checklist: `docs/PLAYTEST.md` "M8 — Growing buildings
(Boomtown)"; known approximations and known minor flaws are recorded there so they aren't
re-filed.

**Wave 2 — Metropolis, shipped 2026-09-18 (playtest pending):** 24 blueprints in
`tools/testfit/blueprints/Metropolis/`, **89 assets uploaded** (88 model stages + the
`city-kit-commercial` VIP swatch), harvested on the first paste, 24 templates in
`templates/Metropolis/`. This is the **tall commercial** era: stage-4 heights run Food Truck 3.3 →
Office Tower 16.3 → Hotel Tower 18.8 → Bank Tower 21.5 → Broadcast Tower 28.6 → Skyscraper 35.6
(monument), i.e. the price ramp is also the height ramp.

**The one contract change this wave: Stadium is 12×12.** `city-kit-commercial` has no seating or
terrace piece, and a 9×9 slot is 2.25 kit units against 1×1 tiles, so a ring of stands around a
readable pitch always left a 1-stud hole; Stadium was rebuilt three times before Ben ruled it gets
a **12×12 footprint** — the first non-monument slot to exceed 9×9. `docs/INTERFACES.md` (blueprint
schema) now permits max `[12, 12]` **only where the kit cannot express the subject at 9×9**, and
notes that clearance comes from harvested extents while the buy pad still sits `padOffset` studs
off the front. Stadium is 12.00 × 12.91 × 10.40 studs, 52 pieces at stage 4. The M9 street-plan
contract already carries the exception (`Metropolis stadium 12×12`).

**No Luau or config logic changed in wave 2**, so there was no review or QA wave: `rojo build -o
build/test.rbxl` succeeds, `gen_templates.py --check` and `gen_asset_manifest.py --check` both
PASS, and `docs/ASSET_MANIFEST.md` reported **72/96 slots** complete at that point (Village,
Boomtown and Metropolis at 24/24 blueprints/uploaded/harvested/templated; Orbital Colony 0/24 —
closed by wave 3 below).

**Wave 3 — Orbital Colony, shipped 2026-09-22 (playtest pending): M8 is complete.** 24
blueprints in `tools/testfit/blueprints/OrbitalColony/`, **90 assets uploaded** (88 model stages +
2 VIP swatches, 90/90 on the first run), harvested in **one paste** (91 loaded, 0 failed), 24
templates in `templates/OrbitalColony/`. `docs/ASSET_MANIFEST.md` now reports **4 eras / 96
models**, every slot of every era blueprinted, uploaded, harvested and templated. Commits:
`8fa99d3` (orbital-kit generator), `bf39ee4` / `8cd589b` / `bf3e9d8` (blueprints), `faa9aae`
(palette fix), `18a7024` (upload), plus the harvest/templates commit.

**Three things were new this wave:**
1. **A second generated kit, `orbital-kit`** (`tools/assets/orbital_kit.py`, 21 pieces: domes,
   drums, telescope, planter tray, solar panels and tracker, flag, holo beacon, mast, tanks,
   energy core, drill rig, lit window strip, pad marking). `space-kit` simply lacks these
   subjects. Same `stadium_kit.py` pattern as Metropolis: the **script** is the committed
   artifact and the GLBs regenerate under the gitignored `/assets/`, so a fresh checkout must run
   the generator before any Orbital merge or re-render (`docs/MANUAL_STEPS.md` M8 section 5).
2. **Contract changes** (already in `docs/INTERFACES.md`, Blueprints subsection): FusionReactor,
   TerraformStation and SpaceportTerminal use **`scale 3.6` with footprint `[12, 12]`** —
   space-kit's hex and long hangars are 12–13 studs at scale 4.0 and fit nothing — and RoverBay
   uses **`[12, 9]`**, the kit's only garage filling 8 of 9 studs; depth stays 9 so the buy pad is
   untouched.
3. **A palette fix with an era-wide effect** (`faa9aae`): space-kit's glTF colour factors are
   **sRGB-encoded, not linear**, so the baked swatches came out pale. `palette.py` now carries
   `SRGB_FACTOR_KITS = {"space-kit"}` and the swatches are the true Kenney colours (orange
   255, 160, 52; dark 70, 76, 87). PLAYTEST section 9 checks this in Studio deliberately —
   "orange trim, not pale amber" — because it is the one fix a contact sheet can't fully prove.

**Direction: silhouette by function, on a near-black plot.** The Orbital plot base is RGB
(56, 53, 60), so every model was judged on a **dark-plot contact sheet**
(`assets/testfit/out/OrbitalColony/_contact_OrbitalColony_dark.png`) as well as the white strip
(`_contact_OrbitalColony.png`) — a white-card-only review would have hidden low-contrast models,
the lesson already learned on the Metropolis Stadium. Stage-4 heights (studs): LaunchTower 42.8
(monument) > TerraformStation 23.0 > CommsArray 21.2 > FusionReactor 16.9 ≈ SpaceportTerminal 16.5
> DockingBay 13.4 = MedicalBay 13.4 > ObservationDome 13.0 > CrewQuarters 12.9 > ResearchLab 12.2
> MineralExtractor 12.0 > OxygenGenerator 10.8 > RoverBay 10.4 > SatelliteDish 9.7 > TurretBase 9.2
> HabitatPod 9.0 > ColonyFlag 8.8 = HoloBeacon 8.8 > HydroponicsDome 8.2 > OxygenTanks 7.4 >
LandingPad 7.2 > SolarArray 6.4 > WalkwayTube 6.0 > RocksLarge 3.2. The Launch Tower clears the
next-tallest by 19.8 studs, so the rocket is the unmistakable landmark of the last era.

**No Luau or config logic changed in wave 3** (content only), so no review or QA wave:
`rojo build -o build/test.rbxl` succeeds and `gen_templates.py --check` /
`gen_asset_manifest.py --check` both PASS.

**Done when:** all three eras' slots spawn as merged-stage meshes from Rojo-built templates, each
era's silhouette direction holds, VIP is a per-kit texture swap, placeholders still work with
`Assets.json` absent, and each era's PLAYTEST section passes. **All the build work is done as of
2026-09-22**; the two open playtest gates are:
- **Wave 2:** Ben buys out a Metropolis plot, grows one building 0→100, checks the Stadium and the
  skyline — `docs/PLAYTEST.md` "M8 — Growing buildings (Metropolis)".
- **Wave 3:** Ben buys out an Orbital Colony plot, grows one building 0→100, and checks the dark
  plot contrast, the three 12×12 landmarks plus the 12×9 Rover Bay, the Launch Tower silhouette
  and the kit colours — `docs/PLAYTEST.md` "M8 — Growing buildings (Orbital Colony)".

**Carried forward (owners assigned):**
- **lead, pipeline gap (unchanged, still open):** `upload_models.py` **skips any stage whose
  `modelAssetId` is non-zero** — no content hash, no `--force` — so changed geometry is silently
  never re-uploaded. Workaround is clearing that stage's `modelAssetId`/`parts` via
  `assets_config.save_assets`. A sha256 check is still worth adding; it bit nobody this wave but
  it will.
- [x] **lead / all eras, closed 2026-09-22 (M9 wave 2a fix round):** the glTF importer's 180° Y
  turn is now compensated in `gen_templates.py` for buildings and props, not just paths, so M7 and
  M8 buildings face their pads. Templates were regenerated from the existing harvest — no
  re-upload. Details in the M9 "wave 2a fix round" block.
- **lead, M9 wave 2 leftover (not M8's):** `props/Metropolis/VehicleD S0` is uploaded but **not
  harvested** — it belongs to the M9 wave 2 harvest paste (`docs/MANUAL_STEPS.md` M9 §8). The
  Metropolis `CityHall` template came through in this wave's paste and is committed.
- [x] **lead, M9 wave 2b (closed 2026-09-23, code shipped; props paste owed in M9):** **Orbital Colony city dressing** (street plan in
  `src/shared/Layouts/*.luau`, props under `templates/_props/`, baked paths) plus the persisted
  `cityDetail` setting. With M8 complete, the Orbital buildings now exist, so wave 2b is fully
  unblocked; until it ships an Orbital Colony plot is deliberately bare (PLAYTEST M8 Orbital
  Colony section 10). Metropolis dressing shipped as M9 wave 2a on 2026-09-22.
- **lead / economy-designer, open idea:** monument growth tied to era completion — raised at M7,
  still not designed or scheduled.
- **economy-designer / Ben:** cash-pack Robux pricing still follows the 1 : 2.2 : 4.2 ladder
  (`docs/BALANCE.md`) whenever real prices are set — M8 doesn't touch monetization.
- **economy-designer / lead:** the ambient-loop listen and the long-run lap-6+ sink (carried from
  M6/M7) remain open, untouched by M8.

**Not in M8:** city dressing (M9), icons and the experience thumbnail (M10), any balance or
income change, runtime piece composition (rejected at M7).

**M8 is the last content era.** Nothing further is planned here; new building work would be a new
milestone, not another M8 wave.

---

## M9 — City dressing: roads, trees, filler, squares, vehicles

**Goal:** make each plot read as a growing town rather than 24 buildings on a lawn. Roads connect
the buildings, trees sprout and grow with the city, filler houses and a square fill the gaps, and
a few vehicles move along the roads — without a measurable frame cost. Decided with Ben
2026-09-16 (contracts: `docs/INTERFACES.md` "M9 contracts"; spec §8 amended the same day).

**Three rulings that shape everything:**
1. **Client-side cosmetics.** The server publishes two attributes per plot (`EraName`,
   `GrowthTier` 0–5) and nothing else. Every client builds identical dressing from
   `(era, tier, owned slots, plot seed)`. No new remotes, no persistence, no balance change.
2. **No collisions.** Every dressing part is `Anchored`, `CanCollide false`, `CanQuery false`,
   `CanTouch false`. Players walk through trees and over roads; prompts and clicks pass through.
3. **car-kit belongs to Boomtown and Metropolis.** Village gets carts (nature-kit), Orbital a
   rover only if space-kit has one.

**Growth tier.** `score = owned × 50 + Σ levels` (`ownedWeight`); tier = number of thresholds
`[50, 400, 950, 1350, 1600]` reached (pure `CityGrowth.luau`, mirrored in the sim; constants in
`Config/CityDressing.json`). Tuning target: tier 1 on the first purchase, tier 3 at ~40 % and
tier 5 at ~80 % of the era's target duration.

**Layers (in build order):**
- **Roads / paths** — hand-drawn "spine" polylines per era in the layout, plus a spur from each
  owned building. *Amended in wave 1b:* roads **grow with buildings** (the visible network is the
  shortest paths from the plot entrance to every owned building's join), and a spur starts under
  its building, not at the pad edge. *Amended in wave 1d:* the surfaces are **baked meshes**
  (Village dirt, Boomtown asphalt + concrete kerb), one Model per piece, cloned from
  `ReplicatedStorage/Assets/Paths`; ≤ 120 pieces per plot; kit junction/bend tiles are dropped for
  Boomtown. Plain Parts remain as the silent fallback. *Amended in wave 1e:* the slots that are
  **named** as street improvements now change the streets — surface variants (Village cobble,
  Boomtown gravel → asphalt), lamp rows and crossing signals, all client-side.
- **Trees** — one 4-stage `TreeGrowing` prop per era (nature-kit for Village, suburban tree/planter
  for the city eras; none in Orbital). Seeded scatter inside layout `treeZones`, rejecting points
  near slots, roads, lots and edges; each tree has a birth tier and grows a stage per tier after
  it. ≤ 40 per plot, near plots only.
- **Filler houses and squares** — 3–4 single-stage house props per era on layout `lots` (8–12,
  each with an appearance tier), 1–2 `Plaza` props at layout anchors. Never a slot's silhouette.
- **Vehicles** — anchored car-kit models (`scale 2.5`, ≈ 6 studs) moved along the road graph in
  one Heartbeat loop with a single `BulkMoveTo`; only on the 3 plots nearest the camera,
  2–6 per plot by era and tier. Random turns at junctions, U-turn at dead ends.

**Performance envelope:** ≤ ~1300 static anchored parts and ≤ ~20 moving parts for 10 plots at
tier 5; identical meshes per era so Roblox batches them. Near/far LOD (250 studs, 40 hysteresis)
drops trees, lamps and vehicles on far plots. Dressing only adds as a plot grows; full rebuild
only on era change. Wave 2 adds a persisted "City detail" setting (same pattern as VIP skins)
that halves trees, drops lamps and keeps vehicles to the local plot.

**Props pipeline:** blueprints in `tools/testfit/blueprints/_props/<Era>/`, the existing tools gain
`--props`, ids land in `Assets.json.props` (schema v2), templates in `templates/_props/<Era>/`
mapped to `ReplicatedStorage/Assets/Props` (the client must clone them; MeshIds are not
scriptable). Prop templates carry the no-collision flags. One harvest paste per era, as in M7.

**Waves:**
1. Parallel, disjoint: luau-engineer (types, `CityGrowth`, attributes), economy-designer
   (Village + Boomtown street plans, sim tier timeline), pipeline-engineer (`--props` mode),
   two Opus prop-builders (Village, Boomtown), ui-engineer (controller, road graph, scatter,
   traffic — roads work before any prop exists).
2. Lead approves street-plan PNGs and prop strips; merge → upload; Ben pastes the harvest;
   templates committed.
3. roblox-reviewer (server untouched by client state; collision flags; budgets; Heartbeat cost),
   qa-runner, docs-keeper.
4. Wave 2: Metropolis + OrbitalColony dressing once their buildings ship (M8), and the
   `cityDetail` setting.

**Done when** (full list in INTERFACES): a Village plot goes from bare ground to roads, growing
trees, cottages, a plaza and two moving carts by tier 5; a Boomtown plot has asphalt, kerbs,
lamps and four cars; nothing blocks the player or a prompt; deleting the config or any
template leaves the game playable; era advance rebuilds; the map stays within the part budget and
the traffic step under 0.2 ms; format, lint, build, `gen_templates.py --check` and the sim are
clean.

**Shipped (wave 1, 2026-09-16):** contracts (`docs/INTERFACES.md` "M9 contracts", incl. the
`tier.ownedWeight`/`thresholds` retune and the P1/P2 street-plan amendments); `CityGrowth.luau`
(pure score/tier) and its `sim_economy.py` mirror with a per-era tier timeline in
`docs/BALANCE.md`; `PlotService` publishing `EraName`/`GrowthTier` attributes on every plot
folder; Village and Boomtown street/lot/plaza/tree-zone layouts (`tools/streetplan.py`-checked);
the client stack (`RoadGraph`, `Scatter`, `Traffic`, `CityDressingController`) built and gated on
a missing `CityDressing.json`; the `--props` pipeline mode (`merge_stages.py`, `upload_models.py`,
`harvest.py`, `gen_templates.py`) and `Assets.json` v2; Village prop blueprints (growing pine, 3
filler cottages, plaza, cart) and Boomtown prop blueprints (tree, 4 filler houses, pocket park,
junction, bend, lamp, 3 vehicles), all uploaded to Open Cloud (24 stages). Reviewer verdict SHIP,
QA green (stylua/selene/luau-lsp/`rojo build`/`sim_economy.py --check`).

**The path look took four Studio rounds with Ben** (1b straight Parts → 1b meandering Pebble trail
→ 1c EditableMesh ribbon → **1d baked meshes**). The ribbon died on a platform blocker: EditableMesh
and EditableImage need the experience owner to be 13+ and **ID verified** in published games, and
Ben will not verify — both APIs are now **banned in this project**, and any account/platform gate
must be raised as a blocker before a design depends on it. The approved recipe is the `tools/pathtest/`
bake-off winner **"C3"** (Ben: "C3 is excellent", then "looks really good, lets commit and close it"):
baked meshes uploaded as Models, **world-planar UVs** (u = x/11, v = z/11 in plot coords, the same on
every piece) over a **fully opaque, 2D-seamless** stylised dirt/asphalt texture, so overlaps sample the
same texel and junction seams and z-fighting are invisible; the irregular edge is cut into the mesh
outline, and a darker **rim** ribbon 0.4 studs wider sits under the fill.

**Shipped (wave 1d — baked paths, 2026-09-18):**
- **Pipeline:** `tools/paths/{texture,bake,network,planargeom}.py` and
  `tools/assets/upload_paths.py`; `harvest.py`/`gen_templates.py --paths`/`gen_asset_manifest.py`
  extended; `Assets.json` v3 `paths` table. The wave-1c `upload_path_texture.py` and the
  `tools/pathtest/` bake-off harness are deleted.
- **Assets:** 91 pieces (58 Village, 33 Boomtown), 186 assets uploaded and harvested in one paste
  on 2026-09-18; templates in `templates/_paths/<Era>/<pieceId>.rbxmx` →
  `ReplicatedStorage/Assets/Paths`. Piece ids are `L<polylineIndex>_<stretchIndex>` (lane stretches)
  and `SP_<slotId>` (building paths), derived from the layout so every client agrees.
- **Client:** `PathRenderer` keeps two modes, `baked` and `parts`; the EditableMesh ribbon and the
  Beam fallback are gone, and `PathRibbon` is centreline-only. A new path appears **rim first, fill
  after `paths.rimLeadSeconds`, with a dust burst over `paths.dustSeconds`**; far plots drop rims
  (`paths.rimNearOnly`) and `budget.pathPieces` is 120 per plot. A missing `templates/_paths`, era
  folder or single piece template, or `road.renderer: "parts"`, silently falls back to the Pebble
  Parts trail.
- **Boomtown dropped the kit junction/bend tiles** (`junctionProp`/`bendProp` → `null`): a kit
  tile's own texture cannot match the planar asphalt. The blueprints stay in the repo, unused;
  Metropolis still names them and will need the same ruling in wave 2.
- **Watch item:** path triangles are ~33k (Village) / ~37k (Boomtown) per fully-owned plot, so
  ~350k at ten plots — the number to watch before wave 2 doubles the era count.

**Shipped (wave 1e — street upgrades, 2026-09-18):** four slots that were only names now change
the streets. Still **client-only**: no server, remote, attribute or profile change — the input is
the owned-slot set the controller already derives from `Buildings/Building_<slotId>`, and every
tunable is in `CityDressing.json` (v3). Contracts: `docs/INTERFACES.md` "Wave 1e — street upgrades".

- **Village `dirtRoad` ("Pave the Road"):** every trail swaps to the **`cobble`** surface — a
  runtime `MeshPart.TextureID` swap on the baked pieces, **no re-bake** — with one cobble-coloured
  dust puff along every visible trail on a near plot. **`Lantern`** props (fantasy-town-kit
  `lantern`, blueprint scale 3.2, 4.98 studs) line the visible spine trails: spacing 16, offset
  1.2, ≈ 15 on a fully grown plot (11 main lane, 1 campsite lane, 1 farm track, 2 cottage lane),
  cap `budget.lampPosts` 24.
- **Boomtown `paveMainStreet`:** streets are **`gravel`** until it is owned, then today's asphalt +
  concrete kerb (`default`). A fresh Boomtown plot never shows a frame of asphalt.
- **Boomtown `streetlampRow`:** now gates **all** Boomtown lamps — the tier-3 junction rule no
  longer applies to that era (Metropolis and Orbital Colony are unchanged). `LampPost` row,
  spacing 24, offset 0.8, ≈ 8 posts.
- **Boomtown `trafficLights`:** a **`TrafficLight`** prop (city-kit-roads, blueprint scale 9, 4.63
  studs) at every node where three or more spine streets meet. Ben asked for real cross streets
  (2026-09-18): the Boomtown plan now has 5 polylines (main street, the ring, a cross street at
  z −42, west and east service lanes) and **six** crossings; every lane is a dead end because the
  drawn network is a spanning tree (a closed block would leave one stretch never drawn). All 38
  Boomtown path pieces were re-baked, uploaded, harvested and templated. After Ben's Studio looks
  the four street slots became `streetOnly` (no kit model) and buildings gained
  `paths.buildingLift` 0.1 so floors clear the spur beneath them.
- **Degrades silently, as everywhere else in M9:** missing variant image ids (still `0`), a missing
  prop template or a missing `Assets.Paths` folder means default texture / no lamps / no signals and
  no error. The Parts fallback repaints from `road.paths.variants.<name>.material/color`.
- **Pipeline:** `tools/paths/texture.py` grew per-era `variants` (`assets/paths/<Era>_<variant>_fill.png`
  / `_rim.png`, `--variant`, `--default-only`); `upload_paths.py` uploads and records
  `Assets.json paths.<Era>.variants.<name>`; `harvest.py` routes a `pathTexture` record carrying a
  `variant`; `assets_config.py` renders the variants block. **Already uploaded:** the 4 variant
  textures (Village cobble fill/rim, Boomtown gravel fill/rim — image ids still `0`) and the
  `Lantern` + `TrafficLight` props.
- **Review (roblox-reviewer): no Criticals.** One Major fixed — the lamp cap was applied to a
  string-sorted plan, so Village's main lane ate the whole budget; posts are now ordered numerically
  by `(polyline, stretch, step)` and thinned evenly to the cap of 16. Minors fixed: the surface
  burst now supersedes the reveal burst, the variant is gated on its texture actually being
  uploaded, dust colour follows the variant, an explicit row-mode flag, `PieceVisible` vs the near
  budget in parts mode, and the Village lantern offset 0.6 → 1.2. QA green (known, not new: the
  selene `LegacyPanel` warning, `src/combat` luau-lsp diagnostics that need the combat sourcemap,
  and `gen_asset_manifest.py --check` stale until the harvest paste below).

**Shipped (wave 2b — Orbital Colony dressing + `cityDetail`, 2026-09-23):** Orbital reuses the
Metropolis machinery. Contracts: `docs/INTERFACES.md` "Wave 2b — Orbital Colony dressing" and
"Wave 2 — `cityDetail` setting". Ben's choices (2026-09-23): **enclosed corridor tubes** as the
walkways, **only the monorail train moves** (no ground vehicles), **decking pads under module
clusters + rocks/craters** on the regolith. He approved the full-plot render with three tweaks:
decking only under clusters, rocks clear of buildings, entrance pier moved.

- **Layout re-laid on the Metropolis lattice** (`src/shared/Layouts/OrbitalColony.luau`): 4×4
  blocks at x,z ∈ {±14, ±42}; `launchTower` at (0, 42) on the x = 0 axis; the 12×12 slots at
  ±43.5 with explicit pads; `walkwayNetwork` pad at (6.5, −34.5). Tubes: central x = 0 (z −49 →
  21), cross tube z = −28, side tubes x = ±28 — a tree, not a loop. 7 dome lots, one observation
  platform (`PlazaA`) at (−9.5, 0), 6 rock zones (30 rocks), 12 decking rects. `streetplan.py`
  green for all four eras.
- **Tubes** = `road.tiles` with generated `tube-kit` props (`TubeStraight/End/Bend/Tee/Cross`,
  `tools/assets/tube_kit.py`): a 4-wide glass corridor, capped airlock on every dead end, Metal
  decking spurs to each module door. **No pavement and no park strips** by design.
- **Monorail** = the Highway module in **loop mode** (no ramp, no junction): `walkwayNetwork` is
  now **"Build the Monorail"**, `streetOnly`; ring 56, beam top 7.07, soffit 6.10; the loop reveals
  both ways from the cell nearest the entrance; **one two-car `MonorailTrain`** rides the beam
  centreline (`tools/assets/monorail_kit.py`, new optional `highway.vehicleProps`).
- **Decking** = paved blocks in Metal (96, 98, 108) with the new `treeSpacing` 0 rule (no edge
  trees, any era). **Rocks** = a 4-stage `Rocks` prop (pebbles → crystal outcrop) in the tree
  slot, `maxCount` 30. `HouseA/B` domes, `PlazaA` platform, `LampPost` light mast. No vehicles.
- **`cityDetail` setting:** profile **schema v6** (additive; old saves get `true`),
  `RequestSetSetting("cityDetail")` on the same validator and rate limit, Settings panel row
  **"City detail"** (the panel's four rows now scroll). Off = trees, rocks and park planters
  thinned to `detail.treeShare` 0.5, no lamps, vehicles (street + deck/monorail) on the local plot
  only; re-evaluated live through one policy function `detailPolicy`. **Publish the hub and
  Expeditions places together** (an old place only warns on a v6 profile).
- **Review (roblox-reviewer): no Criticals.** Majors fixed: the train left the beam at monorail
  corners (its lane now follows the arc); rock zones sat on decking (layout inset).
- **Render reference:** `assets/testfit/out/OrbitalColony/plot_overview.png`, `plot_entrance.png`,
  `plot_tier2.png` (`py tools/testfit/plotrender.py OrbitalColony`).
- **Known, not bugs:** tubes are dressing (players walk through them); the train overhangs the
  beam slightly on corners; the future tube grid is **not** pre-drawn (unlike Metropolis park
  strips) — a fresh Orbital plot is bare regolith.

**Shipped (wave 2c — living city, 2026-09-23; built, awaiting Ben's Studio playtest):** Ben: "make
the cities more alive, with more houses and trees and vehicles when the cities progress".
Contract: `docs/INTERFACES.md` "Wave 2c — living city". Branch `m9-wave2c-living-city`
(worktree `C:\Users\benja\Desktop\tycoon-wave2c`), merged with main's wave 2b.

- **Scope:** Village, Boomtown, Metropolis only (Orbital untouched). Client only — no server,
  remote, attribute or profile change. Growth keyed to `GrowthTier` (no clock).
- **Lots:** Village **21**, Boomtown **18**, Metropolis **10**, ≥ 2 new per tier 1–5. New lot
  `kind` `"small"` (≤ 6×6, ≤ 6.0 tall) next to `"house"` (≤ 9×9); footprints measured per kind.
  - Village: `CottageA/B` (small, 6×6 lots).
  - Boomtown: `HouseE/F` (house), `ShedA/B` (small).
  - Metropolis: `ApartmentA–C` (house), `TownhouseA/B` (small; any lot under the ring deck).
  - `budget.fillerPieces` 25 → 45.
- **Greenery:** layout `greeneryZones` + garnish around each visible lot. Cumulative
  `greenery.perTier`: Village [4, 9, 14, 19, 24], Boomtown [4, 8, 12, 16, 20], Metropolis
  [2, 5, 8, 11, 14]; `budget.greenery` 48, near plots only.
- **Parked vehicles:** kerb bays and driveways (layout `parking`), shown only beside a drawn
  street; max 6 / 12 / 16 (Village carts / Boomtown cars / Metropolis cars); `budget.parked` 16.
- **Moving vehicles:** `perPlot` Village 2 → 3, Boomtown 4 → 6, Metropolis 6 → 8;
  `budget.vehiclesPerPlot` 8, `budget.vehiclesMap` 20 → 24.
- **Walkers** (`src/client/City/Walkers.luau`): from tier 2, ≤ 8 per near plot, 24 per map, on the
  3 nearest plots. Offsets: Village 1.6 (trail edge), Boomtown 4.35 (asphalt edge, clear of cars),
  Metropolis 5.5 (pavement). Walk lanes are **clipped at every solid except pads**; walkers turn
  back there.
- **Ambient** (`src/client/City/Ambient.luau`): chimney smoke from tier 2 on Village + Boomtown
  houses (offsets keyed `"Era/Prop"`); bird flocks from tier 2 over tree zones in all three eras
  (`budget.birdsMap` 18).
- **Device rules:** smoke and birds are off **only** on low-end devices (`Theme.lowEndDevice`,
  saved graphics quality 1–3); phones keep them. Walkers glide without bob under `reducedMotion`
  (every touch device).
- **City detail OFF** (wave 2b setting): greenery halved (`detail.treeShare`); parked cars,
  walkers, smoke and birds off; houses stay. Far plots drop the same set.
- **Generated kits (Blender):** `tools/assets/garden_kit.py` (`garden-kit`: bushes, hedges, flower
  beds, planters for Boomtown/Metropolis) and `tools/assets/people_kit.py` (`people-kit`: walkers
  ≈ 1.75 studs, birds at blueprint scale 1.4).
- **Assets:** 48 props (Village 13, Boomtown 17, Metropolis 18) uploaded, harvested (Ben's paste
  2026-09-23, 48/48) and templated (commits `0b5d08d`, `d02e38a`).
- **`tools/streetplan.py`** now checks lots per kind, parking bays, greenery yield (120-seed Monte
  Carlo, p10 ≥ `perTier[5]`) and walk-lane clipping; green for all three eras.
- **Review fixes:** walkers passed through lots, kiosks and lamps (lanes now clip); a missing wave
  2c key disables its feature instead of throwing; Boomtown walker offset 4.35.
- **Visible changes to approved looks (Ben to eyeball, PLAYTEST 12cz–12dc):**
  - Boomtown `lamps.offset` 0.8 → 1.2, `signals.offset` 0.8 → 1.5;
  - Boomtown ring lots 1, 2, 5, 6, 7 nudged 0.5–0.6 studs back;
  - Boomtown and Metropolis tree zones re-planned (existing trees move once);
  - Village parking bay 3 and lot 15 moved 1 stud.

**Carried forward (owners assigned):**
- [x] **Ben, wave 2a:** both Metropolis pastes done 2026-09-22 — props (24 records) and buildings
  (`CityHall`); 21 prop templates committed (commits `b0ce9ab`, `33b2b54`, `f6556d8`).
- [x] **Ben, wave 2a fix round:** both pastes done 2026-09-22 — props (`PlazaA`, `PlazaB`,
  `HighwayRamp`) and buildings (`CityHall`); templates committed (commits `08643ef`, `ad67484`).
- [x] **Ben, before the wave 2a playtest (third round), done 2026-09-23 (commit `3613cfc`):** **two more pastes**, because the highway,
  the parking garage and City Hall were rebuilt and re-uploaded — props (**4 records**:
  `HighwayDeck`, `HighwayCorner`, `HighwayJunction`, `HighwayRamp`), then buildings (**7
  records**: `ParkingGarage` stages 0-4, `CityHall`, the `garage-kit` VIP swatch) — then
  `gen_templates.py --props`, `gen_templates.py`, `--check`, `rojo build`, the manifest, and
  commit `Assets.json` **with** the templates. Ordered steps: `docs/MANUAL_STEPS.md` "M9" §10.
  Until then those show as **grey placeholders** (a placeholder deck, corner, junction and ramp,
  a placeholder parking garage, no City Hall mesh) — the designed degrade, not a bug — and
  `docs/ASSET_MANIFEST.md` counts them as un-harvested on purpose.
- **lead, standing rule from the fix round:** render the plot offline
  (`py tools/testfit/plotrender.py <Era> --camera overview|entrance|ramp|plaza|cityhall`) and
  review `assets/testfit/out/<Era>/plot_*.png` **before** asking Ben for a Studio look. The first
  wave 2a Studio pass found orientation, pavement, plaza and ramp faults that the render shows.
- [x] **Ben, wave 1e:** harvest paste done 2026-09-18 (2 props + 4 path variant textures);
  `Village/Lantern` and `Boomtown/TrafficLight` templated, both surface variants have non-zero
  image ids.
- [x] **Ben, before playtest:** prop harvest paste done 2026-09-16 (24 stages, 0 failed); 18 prop
  templates generated and committed.
- [x] **Ben, wave 1d:** path harvest paste done 2026-09-18 (186 assets, 91 pieces); templates
  generated and committed; baked paths seen and approved in Studio.
- [x] **lead, wave 2b — upload** (done 2026-09-23, commit `d21c3dd`): 13 Orbital props
  (16 stages) merged and uploaded.
- [x] **Ben, wave 2b — one props paste (16 records)** (done 2026-09-23, commit `9202896`):
  harvested, templated, manifest regenerated.
- [x] **Ben, wave 2c — one props paste (48 records)** (done 2026-09-23, commit `d02e38a`):
  harvested 48/48 and templated.
- [x] **lead, wave 2c:** `m9-wave2c-living-city` fast-forwarded into main 2026-09-23 (`3769c2a`);
  worktree removed, branch kept.
- [x] **Ben, wave 2c:** PLAYTEST M9 section 4h played and signed off 2026-09-23 (12cx/12cy numbers
  not reported — re-measure whenever a performance question comes up).
- **lead, wave 2c watch items:** Traffic + Walkers + Ambient Heartbeat must stay < 0.3 ms with
  every map cap reached (PLAYTEST 12cx); re-cut the part budget with lots 21/18/10 plus up to
  48 greenery and 16 parked per near plot (PLAYTEST 12cy).
- **Ben, wave 2b — publish both places together** (hub + Expeditions): the profile is now v6.
- [x] **Ben:** PLAYTEST M9 sections 4f (Orbital) and 4g (`cityDetail`) signed off 2026-09-23 (tubes
  redone once as half-pipes, commit `379786d`).
- ~~**Ben, next:** PLAYTEST M9 **sections 4f (Orbital) and 4g (`cityDetail`)**, then the rest of M9~~
  end to end.
- **lead, wave 2b watch items:** the train's slight overhang on corners; tubes are walk-through;
  if Ben wants the future tube grid pre-drawn like Metropolis park strips, that is a new rule.
- **Ben, earlier (still open):** after the two pastes, run `docs/PLAYTEST.md` "M9 — City dressing" **sections 4c,
  4d and 4e (wave 2a, Metropolis)** and then the rest of M9 end to end (the path steps 5b–5f, 20b,
  23b–23c and section 4b for wave 1e are still open); this ticks M9 `[x]` above once passed.
- **Ben / lead, wave 2a third round — two looks to judge, not bugs:** (a) a **fresh** Metropolis
  plot is now covered in green park strips (the whole future street grid) until the streets grow;
  (b) City Hall is kit-only, so it reads as a white civic block with flags — `city-kit-commercial`
  has no dome, portico or clock piece. If either misses, the lever is the blueprint
  (`tools/testfit/blueprints/Metropolis/CityHall.json`) or `road.tiles.parkStrips` in
  `CityDressing.json`.
- [x] **Ben / lead, closed (wave 1e):** Ben chose real cross streets, so the Boomtown plan has 5
  polylines and **six** crossings — Install Traffic Lights now buys up to six signals.
- **lead, before wave 2b:** re-cut the ≤ ~1300-part budget line, which predates baked paths and
  tile streets (PLAYTEST step 25 now asks Ben to report counts instead of pass/fail). Wave 1e adds
  up to `budget.lampPosts` (now 24) lamps plus signals per near plot; **a full near Metropolis plot was
  ≈ 220 dressing pieces** (38 tile cells + pavements, 66 highway cells, 5 kiosks, trees, plazas,
  lamps, cars) — the highest of any era, and the number to re-cut against. The fix round adds up
  to **12 block slabs** and raises `trees.maxCount` **24 → 40**, and pavement is now per cell, so
  re-measure with PLAYTEST step 12ag rather than trusting 220. Wave 2b adds the Orbital count
  (tube cells, the monorail loop cells, 12 decking slabs, 30 rocks) — PLAYTEST step 12bt.
- **lead, wave 2a watch item:** `HighwaySign` is uploaded but never placed on Metropolis (the
  7-stud-wide gantry always clips a footprint). Either narrow the blueprint or drop the prop —
  leaving it uploaded and unused costs nothing, but it is dead weight in the manifest. The third
  round's `highway-kit` covers **deck, corner, junction and ramp only**, so the sign is still the
  old kit piece.
- [x] **lead, wave 2b (closed 2026-09-23):** Orbital Colony now has `tiles` (tubes), `highway`
  (monorail loop), decking blocks and rocks; still no `surface`, `variants` or `signals` — none
  needed.
- [x] **lead / economy-designer, wave 2b (closed 2026-09-23):** Orbital street plan, 13 prop
  blueprints and the persisted `cityDetail` setting shipped — see the wave 2b block above.

**Not in M9:** icons and the experience thumbnail (M10), ground textures on the plot base (the
base stays a tinted part), interactive NPCs (wave 2c walkers are cosmetic only), day-night
lighting, lit windows, any server-side dressing.

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

## C0 — Expeditions foundation: second place, Armory, teleport handoff

**Goal:** the plumbing for combat. A second Roblox place ("Expeditions") built from
`combat.project.json` shares `src/shared` and the same ProfileStore profile; the hub gains the
Armory (weapons only, two slots, weapons set max HP, tiers unlock by persisted income/s and cost
era materials) and an Expedition panel (mission tiles, Overdrive toggle, active-runs list); the
hub releases the profile and teleports to a reserved server; the combat place loads the profile,
shows a lobby HUD and returns. No enemies until C1. Decided with Ben 2026-09-17 (contracts:
`docs/INTERFACES.md` "C0 contracts"; memory: `.claude/memory/combat-2026-09-17.md`).

**Rulings that shape everything:**
1. Server owns everything; teleport data is a hint, never an entitlement.
2. One profile, two places: hub releases before `TeleportAsync`, combat place loads; never `Steal`.
3. Weapons only, no armor; `MaxHp = baseHp + hp(melee) + hp(ranged)`.
4. Cash and materials are fixed per enemy (C1); no RNG anywhere.
5. Every subagent on the combat milestones runs on Opus.

**Milestones:** C0 foundation → C1 Village expedition (arena, enemies, combo/ranged/abilities,
pacing director, feedback) → C2 co-op (party, join-in-progress, contribution split, Mentor
bonus) → C3 other eras, Ascension forge, Overdrive, full-lap balance. Stop after each for Ben's
playtest. M10 stays reserved for icons/thumbnail.

**Tasks (wave 1, parallel):** luau-engineer — Rojo second project, `ProfileSchema`, schema v5,
`RemoteService.Configure`, `HubRemotes`, `ExpeditionService`, `ArmoryService`, `EconomyService`
additions, `src/combat/server/**`, `Types`, `Catalog`, pure `Armory.luau` + `Combat.luau`.
ui-engineer — Power readout, `ArmoryPanel`, `ExpeditionPanel`, BottomBar keys, `src/combat/client/**`.
economy-designer — `tools/sim_combat.py`, Armory/mission values, `docs/BALANCE.md` "C0".
**Wave 2:** roblox-reviewer → qa-runner → docs-keeper.

**Shipped (2026-09-17):** `combat.project.json` → `build/combat.rbxl`, a second place sharing
`src/shared` and `src/server/Services` with `src/combat/{server,client}`; `ProfileSchema.luau`
(schema v5, `combat` profile table, `highestEra`) + the `Migrations[4]` step; `RemoteService.Configure`
and `HubRemotes`; `ExpeditionService` (Depart/Join/RunList, reserved-server access code kept in a
server-only MemoryStore hash map `ActiveRunsCodes`); `ArmoryService` (RequestBuyGear/RequestAscend,
income/s gate on the persisted rate, Studio levers `GrantMaterials`/`GrantValor`); `EconomyService`
(`gearPower` in Snapshot/Delta, `combat` delta, expedition offline efficiency); pure `Armory.luau`
and `Combat.luau` mirrored by `tools/sim_combat.py` (`--check`, six assertions, green). Combat
place: `Main.server.luau` (join → same profile → mission from profile, Studio attributes
`DebugMission`/`DebugOverdrive`), `ArenaService` (code-built lobby pad, HP = `Armory.MaxHp`,
`RunState` lobby/summary, Ready), `ReturnService` (summary → release → teleport home; stays with a
toast when `hubPlaceId` is 0 or in Studio), `RunRegistry` (MemoryStore sorted map `ActiveRuns`,
Studio no-op). Hub UI: "⚔ power" top-bar readout, six-key bottom bar (icon over word), `ArmoryPanel`,
`ExpeditionPanel` (tiles disabled with "Publish the Expeditions place first" while
`Places.json combatPlaceId` is 0); combat client lobby HUD, summary card, load screen. Configs:
`Config/{Armory,Combat,Places}.json` + `Config/Missions/1_Village.json`; balance in `docs/BALANCE.md`
"C0" (Village run 7:58 at recommended power 60, 151,981 cash ≈ 1 % of the era's remaining cost,
full tier unlock ladder).

**Review outcome:** 1 Critical — `TeleportInitFailed` was handled synchronously; 5 Majors —
missing in-flight guards, re-entrant leave, the access code travelling on a client-visible
channel, no fan-out cap on `RequestRunList`, and teleport-hint values trusted without re-validating
against the run actually in progress. **All six fixed in wave 2**; reviewer verdict SHIP, QA green
(stylua, selene, luau-lsp, both `rojo build`s, `sim_economy.py --check`, `sim_combat.py --check`,
`gen_templates.py --check`).

**Carried forward (owners assigned):**
- **Ben, before C1:** publish the Expeditions place and paste both ids into
  `src/shared/Config/Places.json` (`docs/MANUAL_STEPS.md` "C0"), then run `docs/PLAYTEST.md` "C0".
- **lead, before C1:** dedupe the five UI modules copied under `src/combat/client/UI` (verbatim
  copies of the hub's; scheduled as the first C1 task).
- **lead, open rulings for C2:** boss HP vs party size (waves scale count only today, so a
  4-player party kills a boss ~4× faster — `docs/BALANCE.md` "One boss per boss wave"); and
  whether the hub's active-runs list stays same-server + friends or widens.

**Known limits at C0:** no enemies or combat until C1; `TeleportInitFailed` paths are
code-review-only (not reachable from Studio); a working Depart needs both ids in `Places.json`
plus MemoryStore access; join-in-progress registry entries exist but the hub Join button only
works on a published pair *and* after C2 wires party logic.

- [x] C0 built and reviewed (definition of done in INTERFACES "C0 contracts")
- [~] Ben's Studio playtest (`docs/PLAYTEST.md` "C0") — **superseded by C1.** C0 sections 1-8 still
      apply and are folded into the C1 pass; section 9 (the published round trip) is replaced by
      the C1 Studio bridge round trip, which Ben can actually run.

## C1 — Studio bridge + Village expedition

**Goal:** make the whole expedition loop playable **from Studio**, and fill it with the Village
fight. Ben cannot reach the published pair (audience-reach block, `docs/DISCOVERY_CHECKLIST.md`),
so C1 ships a **Studio bridge** that replaces the one thing Studio cannot do — `TeleportAsync` —
with a DataStore handoff record plus a kick, and leaves every other platform path (profile
release, run registry, retries, failure recovery) running for real. On top of that: the Raider
Woods arena, three enemy types, ten waves with two bosses, melee combo / ranged / abilities, the
pacing director, hit feedback, and a debug strip in both places. Contracts:
`docs/INTERFACES.md` "C1 contracts — Studio bridge + Village expedition" (2026-09-22).

**Rulings that shape everything:**
1. Every C1 feature must be reachable from Studio. Levers are `RunService:IsStudio()`-gated
   Workspace attributes or the Studio-only debug strips — never a trick against the platform.
2. The handoff record is a **hint, never an entitlement**: the combat place re-validates the
   mission against the loaded profile exactly as it validates live teleport data.
3. Nothing in `StudioBridge` or `DebugService` runs outside Studio; a published server behaves
   exactly as it did at C0.
4. **No enemy or weapon model is required.** Placeholder R15 rigs and empty hands are the
   shipped default; models are a later props pass.
5. All damage in both directions goes through `CombatService` — never Roblox touch/physics.
6. Every subagent on the combat milestones runs on Opus.

**Tasks (wave 1, parallel, disjoint):** luau-engineer A — combat core (`WaveService`,
`EnemyService`, `CombatService`, `DebugService`, `ArenaService`, `Village` arena layout, `Types`,
pure `Combat.luau`). luau-engineer B — Studio bridge (`StudioBridge`, `ExpeditionService`,
`HubRemotes`, hub `Main.server.luau`, `ReturnService`, `RunRegistry`). ui-engineer A —
`src/combat/client/**` (`InputController`, `WeaponController`, `CombatFxController`, `CombatHud`,
`SummaryCard`, `DebugPanel`). ui-engineer B — hub client (`ExpeditionSummaryCard`, `DebugPanel`,
`UIController`, `ExpeditionPanel`). economy-designer — `tools/sim_combat.py` run simulator,
Village values, `docs/BALANCE.md` "C1". **Wave 2:** roblox-reviewer → qa-runner → docs-keeper.

**Shipped (2026-09-22):**
- **Studio bridge** — `src/server/Services/StudioBridge.luau` (shared Services folder, so both
  places see it): DataStore `StudioHandoff`, key `p_<userId>`, records `depart` / `join` /
  `return`, pcall + 3 retries + warn, records older than `handoffMaxAgeSeconds` (900 s) ignored
  and removed, every field type-checked on read. `Depart(player, message)` warns and kicks after
  1 s so the toast lands first.
- **Hub** — `ExpeditionService.Depart`/`Join` run in bridge mode in Studio (no `ReserveServer`,
  access code `"studio"`, real profile release, real failure recovery); `ForceTeleportFailure`
  re-admits the player with `unavailable` and clears the record; hub `Main.server.luau` fires the
  new `ExpeditionSummary` event from `TeleportData.summary` **or** `StudioBridge.ReadReturn`;
  `HubRemotes` gains `ExpeditionSummary` and the `RequestDebug(lever, value)` intent (bucket
  `calls`), handled by `ArmoryService` and ignored outside Studio (`grantCash`, `grantMaterials`,
  `grantValor`, `fakeRuns`, `forceTeleportFailure`).
- **Combat place** — `Village` arena layout (110x110 Grass floor, 4-stud fence, 8 rim spawns,
  obstacles, `LobbyPad`) built by `ArenaService`; `EnemyService` (placeholder R15 rigs from
  `CreateHumanoidModelFromDescription`, recoloured per key, boss/elite scaling, server-side
  Motor6D windup and walk bob, `EnemyId`/`EnemyKey`/`DisplayName`/`IsBoss`/`Elite`/`Attacking`/
  `Dead` attributes, AI at `tickHz` 10 inside `aggroRange` 80); `WaveService` (lobby → 10 waves →
  summary, trickle spawns at `SpawnInterval`, `maxAlive` 24, tempo with a 15 s warmup, merges,
  breathers with regen, bosses at waves 5 and 10, per-wave-clear pool split through
  `ContributionShares`/`SplitPool` flushed to the profile plus a fresh Snapshot, run cap 1200 s);
  `CombatService` (three-hit melee combo with server-clock windows and a finisher, ranged
  `RequestFire` with server raycast and charge clamp, `RequestAbility` per slot with kill refunds,
  `DamagePlayer` with god mode); `DebugService` (attribute poll + `RequestDebug`, bots up to 8);
  `ReturnService` writes the return record and kicks in Studio; `RunRegistry` is no longer a
  Studio no-op (real MemoryStore, in-memory stand-in under mock mode, `ForceRegistryFailure`).
- **Combat client** — `InputController` (stance `1`/`2`, click/tap attack, hold-to-draw, `Q`/`E`
  abilities, touch soft-lock inside `aimAssistDegrees` 20), `WeaponController` (prop when present,
  procedural Motor6D poses otherwise), `CombatFxController` (damage numbers, Highlight flash,
  hitstop, camera kick, dissolve, wave/merge/boss banners, low-HP vignette, attack tells, reduced
  motion), `CombatHud` (wave line, boss bar, alive/left, tempo dot, wallet strip, party rows,
  stance + ability buttons, run timer), `SummaryCard`, Studio-only `DebugPanel`.
- **Hub client** — `ExpeditionSummaryCard` ("EXPEDITION REPORT") shown once on `ExpeditionSummary`
  and **chained behind** the welcome-back card; Studio-only `DebugPanel` strip.
- **Config/balance** — `Combat.json` gains `enemy`, `feedback`, the nine new `debug` keys and
  `player`/`director` additions; `Sounds.json` gains 17 combat keys (all id 0 = silent);
  `Missions/1_Village.json` retuned (enemy HP/damage/cooldowns, `countPerWave` 0.3, `hpGrowth`
  and `damageGrowth` 0.03, boss multipliers); `director.windowSeconds` 15 → 10, `tempoMin` 0.7,
  `mergeTempo` 1.25. `tools/sim_combat.py` replaces the closed-form DPS model with a full run
  simulator; `--check` is green on **ten** assertions. Numbers: `docs/BALANCE.md` "C1".

**Review outcome:** 1 Critical — a MemoryStore publish yielded inside the wave loop (now
serialized off-thread). 4 Majors — Ready could be flapped mid-run, enemies idled outside aggro
range, the expedition report covered the welcome-back "Double it" offer, and there was no reaper
for enemies destroyed out of band. **All five fixed**; reviewer verdict SHIP AFTER FIXES → fixed.
qa-runner: ALL GREEN for C1 (stylua, selene, both builds, both sourcemaps + luau-lsp, `sim_economy.py --check` unchanged, `sim_combat.py --check` 10/10, manifest). The only red is pre-existing at HEAD: `gen_templates.py --check` reports four M9 wave-2a Metropolis stages (CityHall, HighwayRamp, PlazaA, PlazaB) uploaded but never harvested — Ben's harvest paste, see MANUAL_STEPS M9.

**Carried forward (owners assigned):**
- **Ben, now:** run `docs/PLAYTEST.md` "C1" with **Enable Studio Access to API Services ON**
  (`docs/MANUAL_STEPS.md` "C1"). Nothing to publish or upload this milestone.
- **lead, C2:** other players' melee swings are not animated (only the local character poses).
- **lead, C2:** the bow's charge is measured from time since the last shot, not from a separate
  draw start — a player who waits between shots can fire an instant full-charge arrow.
- **lead, C2:** the five UI modules copied verbatim into `src/combat/client/UI` are still copies
  (carried from C0); dedupe when the combat client stops moving.
- **lead, C2:** enemy colours are code constants in `EnemyService`, not config.
- **economy-designer, C2:** re-measure `MELEE_CONTACT_SLOTS`, the enemy land rate and tempo-as-lag
  against what Studio actually does (`docs/BALANCE.md` "What C2 should re-check").
- **lead, open rulings for C2 (from C0):** boss HP vs party size, and whether the hub's
  active-runs list stays same-server + friends or widens.

**Known limits at C1:** no enemy or weapon models (placeholder rigs, empty hands — by design);
all 17 combat sound ids are `0`, so the fight is silent; the Studio bridge replaces the teleport
with a **kick**, so a Studio round trip is Stop Play → open the other `.rbxl`; without API access
the bridge is inert (Depart answers `unavailable` and warns once) and the two places use separate
mock profiles; co-op is only observable through `DebugBots` and a Local Server pair — party from
the hub, join-in-progress and the Mentor bonus are C2; missions 2-4, the Ascension forge and
Overdrive balance are C3.

- [x] C1 built and reviewed (definition of done in INTERFACES "C1 contracts")
- [x] Ben's Studio playtest (`docs/PLAYTEST.md` "C1") — passed as part of the C2 pass (2026-09-23)

## C2 — Co-op: party, join-in-progress, contribution, Mentor

**Goal:** play expeditions together. A hub party (invite + accept, same server) departs as one
group to one reserved server; anyone can join a run in progress from a grouped run list (this
server, friends, public runs from any server); late arrivals and co-op deaths wait for the next
wave boundary; boss HP scales with party size; a high-income player carrying a newcomer earns a
Mentor Valor bonus; band-4 melee tiers get party effects; the party returns home together and
re-forms. The game is published (both ids live in `Places.json`), so C2 is verified **twice**:
Studio bridge + levers, and a published two-account round trip. Contracts: `docs/INTERFACES.md`
"C2 contracts — Co-op" (2026-09-23); balance: `docs/BALANCE.md` "C2"; memory:
`.claude/memory/coop-2026-09-23.md`.

**Rulings that shape everything (Ben, 2026-09-23):**
1. Boss HP × `(1 + coop.bossHpPerExtraPlayer × extras)`, 0.75. Regular enemies still scale by count only.
2. Run list = this hub server + friends + public runs from any server. Host toggle "Open to
   public" (default `coop.publicByDefault` true); a private run shows only to friends and
   same-server players.
3. Hub party = invite + accept, same server. The leader picks the mission. One `ReserveServer`,
   ONE group `TeleportAsync`.
4. Missions are host-gated: a guest may fight any mission the host unlocked. The gate is the
   server-only `RunTicket` (its `privateServerId` must equal `game.PrivateServerId`), never
   teleport data.
5. Nothing new persisted (ProfileSchema stays v6). The party lives in memory and re-forms from
   agreeing teleport hints only.

**Tasks (one wave, parallel, disjoint):** lead — contracts, `Types.luau`, config keys, combat
client UI dedupe via `combat.project.json`. luau-engineer A — combat server (`ArenaService`,
`WaveService`, `CombatService`, `EnemyService`, `DebugService`, `ReturnService`, `RunRegistry`,
`CombatRemotes`, `Main`), pure `Combat.luau`. luau-engineer B — hub server (new `PartyService`,
`ExpeditionService`, `HubRemotes`, `StudioBridge`, `ArmoryService`, `Main`). ui-engineer A —
`src/combat/client/**`. ui-engineer B — hub client (`ExpeditionPanel`, new `PartyInviteToast`,
`UIController`, `DebugPanel`, shared `Theme`). economy-designer — `coop.*` and `partyEffects`
values, `sim_combat.py`, `BALANCE.md` "C2". **Wave 2:** roblox-reviewer → qa-runner → docs-keeper.
Ran in worktree `C:\Users\benja\Desktop\tycoon-c2` (branch `c2-coop`); main (M9 wave 2d) merged in.

**Shipped (2026-09-23):**
- **Hub party** — `PartyService`: invite + accept; invites expire after `inviteSeconds` 30;
  re-invite cooldown `inviteCooldownSeconds` 10; a decline blocks that leader → target for
  `declineBlockSeconds` 60; leader handover in join order; a party of one dissolves. Studio
  levers `fakeParty` (attribute `DebugFakeParty`, sticky number 0–3) and `fakeInvite` (attribute
  `DebugFakeInvite`, boolean, consumed once), plus hub debug strip buttons.
- **Party Depart** — one `ReserveServer`, a `RunTicket` (`privateServerId`, `public`,
  `expected`) in `ActiveRunsCodes`, then ONE group `TeleportAsync`; any failure runs the C1
  recovery for every member. Bridge mode writes one handoff per member and kicks each.
- **Join** — personal (leaves your hub party first); hub pre-filters `full` / `over` /
  visibility; no unlock check for guests (host-gated). "Open to public" toggle beside Overdrive.
  Run list grouped IN THIS SERVER / FRIENDS / OPEN RUNS, one `GetRangeAsync` per hub server per
  `listCacheSeconds` 5, capped at `listMax` 20, friend checks capped at 8 per call.
- **Combat admission** — `ArenaService.CheckAdmission` → `ok` / `full` / `over` / `locked` for
  every arrival; a refusal goes home with its reason. Studio lever `admitCheck` (combat debug
  strip "Admit check") runs the same function and toasts the verdict.
- **Wave-boundary entry** — joiners, co-op deaths and bots added mid-wave wait on the LobbyPad
  (untargetable, no damage, attacks refused) and enter at the next boundary. The lobby waits for
  every expected member, or `lobbyWaitSeconds` 30 after the first arrival once all present are ready.
- **Boss HP** × (1 + 0.75 × extras), mirrored in `sim_combat.py`.
- **Mentor bonus** — at a boss-group flush, a human earns `mentorValor` 5 per member whose
  income is below `mentorRatio` 0.125 of theirs (mentor earns 8× or more). Mentor and mentee
  both need ≥ `mentorMinDamageShare` 1 % of that flush. Bots count as income 0, never mentor.
- **Party effects** — melee tiers 10–11 `rally` (heal 0.15 × MaxHp, radius 20), tier 12
  `warcry` (1.25× damage for 6 s, radius 20), on a successful melee ability.
- **C1 carry-overs closed** — other players' swings replicate (`CombatFx swing`); the bow's
  charge counts from a new `RequestDraw` stamp (no free full-charge shot after waiting); enemy
  colours moved to `Combat.json enemy.*Color` / `EnemyDef.color`; the combat client UI copies
  are gone (`combat.project.json` maps the hub originals: one `Client/UI`, one `Client/Controllers`).
- **Group return** — summary counts down `returnGroupSeconds` 15, then one `TeleportAsync` home
  with a party hint; the party re-forms (`reformSeconds` 60) only among the original hub party
  whose hints agree. Return before the countdown goes home alone.
- **Client** — hub party strip, invite picker, Kick / Leave, `PartyInviteToast`, co-op refusal
  copy; combat HUD ★ host, "joins next wave" / "back next wave", damage %, waiting banner,
  rally / war cry / Mentor fx, summary damage share + Mentor line + "Returning together in …".

**Review outcome:** 0 Critical, 3 Majors — admission bypass through a failed refusal/return, an
idle mentor still paid, invite spam — plus 6 Minors. **All fixed** in commit `0362634`.
qa-runner: ALL GREEN — stylua, selene (known `LegacyPanel` warning only), both `rojo build`s,
both luau-lsp runs, `sim_economy.py --check` unchanged, `sim_combat.py --check` 13/13,
`gen_templates.py --check` + manifest after merging main (wave 2d).

**Carried forward (owners assigned):**
- **Ben, now:** republish **both** places (`docs/MANUAL_STEPS.md` "C2"), then run
  `docs/PLAYTEST.md` "C2". That pass **folds in the still-open C1 playtest**; C1's box stays
  unticked until Ben confirms it.
- **lead, C3 (`BALANCE.md` "C2"):** co-op pays ~40 % of solo cash per head at 4 players (23 % of
  Valor). Suggestion: scale boss cash / materials / Valor by `bossHpMult` (→ 81 % per head).
- **lead, C3:** an idle alt still collects the `contributionFloor` share (3 Valor/run); a floor
  that requires damage > 0 would close it (`ContributionShares`).
- **economy-designer, C3:** co-op is much safer than solo (HP floor 68–85 % vs 15 %) — measure
  real damage taken in the published test before touching `countPerExtraPlayer`; Overdrive party
  outcomes are not monotonic at recommended power; re-run party effects on a real band-4 mission.
- **lead, later:** remote swings play on a fixed 0.35 s window, not the swinger's real timing.
- **lead, later:** "back next wave" needs the client to have seen that member fight; a client
  that arrived after the death shows "joins next wave" instead.

**Known limits at C2:** Studio Local Server test players have **negative ids** (−1, −2 …), so
friend checks never match there — the FRIENDS group is only visible with `DebugFakeRuns`; a
`full` refusal needs 4 seats (Studio: bots + `admitCheck`; published: four accounts); the Mentor
check needs the player's saved income > 0 (buy something in the hub first); combat sounds still
id 0 (silent); enemies and weapons still placeholders; missions 2–4, Ascension and Overdrive
balance are C3.

- [x] C2 built and reviewed (definition of done in INTERFACES "C2 contracts")
- [x] Ben's playtest (`docs/PLAYTEST.md` "C2") — 2026-09-23: the flow works end to end; Ben judged the combat itself "extreme trash" (looks, hit feel, enemy behaviour, controls) → a combat feel pass comes before C3

## C2.5 + C3 — Stop 1: combat feel

**Goal:** make the fight feel modern before C3. Ben judged C2's combat "outdated, like a child's
project": looks, hit feel, enemy behaviour and controls. Stop 1 fixes camera and controls, impact,
enemy AI, animations and sounds, and judges them on Village. Missions 2–4 and their arenas are
drafted at the same time (placeholder rigs, draft balance). Contracts: `docs/INTERFACES.md`
"C2.5 + C3 contracts — Stop 1"; balance: `docs/BALANCE.md` "C2.5"; memory:
`.claude/memory/feel-pass-2026-09-23.md`.

**Rulings (Ben, 2026-09-23):**
1. **Over-the-shoulder camera on every device** (chosen over a top-down ARPG camera). PC =
   mouse-locked shoulder cam; touch = thumbstick + right-half drag + aim assist; gamepad =
   twin-stick, R2 attack, L1/R1 abilities, Y stance.
2. **One evolving horde:** every mission has a melee grunt, a ranged shooter and a charger
   brute, plus bosses on waves 5 and 10. Village keeps `raider` / `archer` / `brute`; missions 2–4
   use `grunt` / `shooter` / `brute`.
3. **Detailed models** (not chunky low-poly) come in Stop 2, as generated Blender geometry.
4. Server authority unchanged. The camera and all fx are client-only. Aim is still a direction
   the server raycasts itself. No new remote and no schema change.

**Tasks (one wave, disjoint):**
- lead: contracts, `Types.luau`, `Combat.json` keys, audio upload (pending).
- luau-engineer A: combat server (`EnemyService`, `WaveService`, `CombatService`,
  `ArenaService`) and `Combat.luau`.
- ui-engineer A: `src/combat/client/**` with the new `CameraController`, and the combat blocks
  of `Theme`.
- economy-designer: `Combat.json` camera/ai/feel/animations values, `Missions/1_Village.json`,
  new `Missions/{2_Boomtown,3_Metropolis,4_OrbitalColony}.json`, new
  `Layouts/Arenas/{Boomtown,Metropolis,OrbitalColony}.luau`, `sim_combat.py`, `BALANCE.md`.
- sound picker: combat entries in `tools/audio_map.json`.
- Wave 2: roblox-reviewer, then qa-runner, then docs-keeper.

**Shipped (2026-09-23, commits `52d8683`, `fa08dcf`, `980e7b2`):**
- **Camera** (`CameraController`, Scriptable; the deviation is explained in its header):
  - Shoulder offset, zoom 7–16, FOV 72.
  - PC: mouse locked. **Alt** frees the cursor. The cursor is free in the lobby, the summary
    and while the debug strip is open.
  - Touch: drag on the right half to aim, the finger on the attack button also aims, pinch zooms.
  - Gamepad: right stick aims; R2 / L1 / R1 / Y.
- **HUD:**
  - Centre crosshair and hit marker.
  - 20-dot bow charge ring.
  - Right-thumb touch cluster that stays clear of the jump button.
- **Impact:**
  - Sparks along the hit direction, camera shake, hitstop, weapon trails.
  - Flying arrows and bolts.
  - Muzzle flash. Machine-gun spread is now actually applied.
- **Telegraphs:**
  - Strike: "!" and a glow on the attacker.
  - Slam: red ground ring.
  - Charge: red lane.
  - Summon: violet circle.
  - A cancelled telegraph clears.
- **Enemy steering:**
  - Enemies keep apart (separation).
  - At most **3 melee attackers** per player, in slots; the rest circle at 14 studs.
  - Shooters keep 18–30 studs and strafe.
  - Pathfinding around cover.
- **Chargers** (brute): approach, wind up, dash, recover 4 s. They never take a melee slot and do
  not count toward the 3-attacker cap.
- **Bosses:**
  - Chief and Warlord both slam and charge.
  - The Warlord also summons raiders on wave 10.
  - A stun (`groundSlam`) cancels a boss wind-up.
- **Reactions:**
  - Stagger on every hit.
  - Server ragdolls on death. They collide only with the arena.
- **Animations:**
  - Roblox default R15 idle / walk / run / tool slash / tool lunge ids in `Combat.json`,
    **unverified**.
  - A bad id prints Roblox's load error and falls back to the procedural pose.
  - Setting an id to `0` disables it.
- **Missions 2–4 (draft):** `boomtown` Rail Yard Outlaws, `metropolis` Blackout Blocks, `orbital`
  Crater Breach, each with its own 110×110 arena and cover. Placeholder rigs, draft balance.
- **Sounds:** 20 combat picks in `tools/audio_map.json`. **Not uploaded yet.** Ben is auditioning
  `assets/audition/<key>/`.

**Review outcome:** 0 Critical, 3 Majors, 10 Minors. The Majors were the charger/slot rule, stun
versus boss wind-up, and the sim's charger model. **All fixed** in `980e7b2`. qa-runner: ALL
GREEN. `sim_combat.py --check` passed 14/14; `sim_economy.py --check` output is unchanged.

**Carried forward to Stop 3 (owners):**
- **economy-designer + lead:** the tempo director cannot tell strong players apart outside
  Village; at 2× power, missions 2–4 never merge. Fix: measure tempo as kill lag, then restore
  `MERGE_ASSERTED_MISSIONS` in `sim_combat.py` for every mission.
- **lead (design call):** in later eras combat cash is a tiny share of the era's cost (0.17 /
  0.03 / 0.01 %).
- **lead:** co-op per-head rewards (C2 carry-over).
- **lead:** idle-alt `contributionFloor` (C2 carry-over).
- **economy-designer:** stun strength (`groundSlam` against bosses), and the land rates
  `CHARGE_LAND_RATE` / `PATTERN_LAND_RATE`, measured from Ben's dodges.
- **ui-engineer:** other players' ranged shots show no fx.
- **lead, now:** the audio upload after Ben's audition (`docs/MANUAL_STEPS.md` "C2.5 Stop 1" §3).

**Known limits at Stop 1:**
- Enemies and weapons are placeholder rigs with empty hands; the arenas are blockouts.
- Combat is still silent until the upload.
- Animation ids are unverified.
- Missions 2–4 have never been fought.
- In Studio, `DebugMission` skips the era lock (Studio-only bypass in `ArenaService.CheckAdmission`);
  live, missions 2–4 still need the era (or a host who has it).

- [x] Stop 1 built and reviewed (definition of done in INTERFACES "C2.5 + C3 contracts — Stop 1")
- [ ] Ben's playtest (`docs/PLAYTEST.md` "C2.5 Stop 1")

### Next stops (outline)

- **Stop 2: models.**
  - Detailed horde models for all four eras (grunt, shooter, brute, Chief, Warlord).
  - Detailed weapon models for all tiers.
  - Arena dressing.
  - All generated in Blender (no Kenney character or weapon kit exists).
- **Stop 3 (= C3):**
  - Overdrive.
  - The Ascension forge UI.
  - Full-lap and one-rebirth balance.
  - The tempo-as-lag director fix.
  - The C2 reward carry-overs (per-head co-op rewards, idle-alt floor).
  - Everything listed under "Carried forward" above.
