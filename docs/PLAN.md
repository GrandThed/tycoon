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
- [x] M12 — Growing city (**complete 2026-10-06: all four eras signed off by Ben on Studio
  looks and merged to `main`**; **wave 1 Village merged to `main` 2026-10-01**, Ben: "the village looks
  amazing": a client-only city fabric of 116 growing lots, receding woods, construction ripples
  and three city-changer slots; **wave 2 Boomtown signed off by Ben and merged to `main`
  2026-10-02** (merge commit `86d1d99`): an organic prairie-town layout, 75 lots on 8 baked back
  lanes, receding farmland, five city layers (parked cars, hydrants, bus shelters and buses,
  billboards, neon), chimneys on the narrow Village homes; the sign-off was a Studio look at the
  lanes and the town ("looks really good! lets send it"), not a report of the 60-step checklist,
  so the phone, low-graphics, two-player and measurement steps stay watch items, and Ben's
  step-37 numbers are still owed; **wave 3 Metropolis signed off by Ben and merged to `main`
  2026-10-05** (`d0dd894`, a fast-forward; on `origin/main` the same day): the "avenues" layout Ben picked on
  2026-10-03 ("i love avenues"), 88 lots on three avenues and four lanes, an old town that is
  redeveloped, towers that grow floor by floor, two city-changer slots (Open the Bus Line, Green
  the Rooftops), 35 props (107 stages) uploaded and harvested in one paste; the sign-off was a
  Studio look ("looks good!"), not a report of the 51-step checklist, so the step results, the
  phone, low-graphics and two-player checks and the measurement stay watch items, and the
  numbers for Village, Boomtown and Metropolis are owed; **wave 4 Orbital Colony signed off by
  Ben and merged to `main` 2026-10-06** (`c01ccfd`, a fast-forward): Ben rejected two
  straight-avenue layouts as too close to Metropolis and picked the organic "Bloom" ("lovely,
  lets go with bloom"): 89 lots on curving swept tubes with round hubs, a round monorail loop,
  regolith that recedes, four city-changer slots (Raise the Colony Flags, Green the Domes, Tend
  the Rock Gardens, Light the Holo Beacons; "looks good! lets keep all four"), 65 street pieces
  and 45 props (171 uploads) harvested in one paste; the sign-off was a Studio look ("looks
  good! lets ship it"), not a report of the 54-step checklist, so the lettered questions, the
  phone, low-graphics and two-player checks and the measurement stay watch items, and the
  numbers for all four eras are owed — see "M12" below)
- [~] M13 — The Valley (the landscape outside the plots; Ben chose mock A on 2026-10-01, "i love
  A valley"; **wave 1 built 2026-10-02**: hazed sky, green ground, stone hub, a dirt road to
  every plot, Parts and Lighting only, checks green; **Ben saw it in Studio 2026-10-02** (one
  screenshot, no complaint, no formal sign-off) and asked for the rest: "we didnt do step A2
  yet? do it"; **wave 2 built 2026-10-02**, the whole A2 Valley in one wave: mountains, forest,
  waterfall, river, pond, lake, 4 bridges, stepping stones, groves, era aprons and clouds as 28
  generated meshes (131,768 triangles), **uploaded, harvested in one paste and templated**;
  reviewed, checks green; **Ben approved it in Studio 2026-10-02 ("approved!") and it is merged
  into `main`**; there is no wave 3; open: the re-bake for 6 plots when `m11-unlocks` merges —
  see "M13" below)

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

> **Superseded 2026-09-24:** Ben's reset replaced Stops 2–3 with the P0–P6 build order in
> `docs/COMBAT_DESIGN.md` §10 (no combat sound; the range first). See "P1 — Proving Grounds" below.

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

## P1 — Proving Grounds

**Goal:** a Studio test range where movement, controls, hit feel and crowd enemies are built and
tuned before any mission uses them. Gate (COMBAT_DESIGN §10): movement and feedback feel good on
PC **and on a phone**, and 100+ enemies run smoothly. Plan of record: `docs/COMBAT_DESIGN.md`;
contracts: `docs/INTERFACES.md` "P1 contracts"; values: `docs/BALANCE.md` "P1 — Proving Grounds
starting values"; memory: `.claude/memory/feel-pass-2026-09-23.md` (reset + new direction).

**Rulings (Ben, 2026-09-24):**
1. Combat starts over: design first (`COMBAT_DESIGN.md`), then the range, then missions (P5).
2. **No sound** in combat. All combat sound ids stay 0.
3. Over-the-shoulder camera stays. **Ranged shooting like Fortnite** (camera-ray aim, bloom, ADS,
   crits).
4. **No attack button on phones.** Auto-fire and auto-swing, with tap-to-fire as the alternative.
   Phones must work from P1.
5. Most weapons hit many enemies: the game is a game of numbers.
6. The range is **Studio only**: Workspace boolean `DebugProving` = true at boot in
   `build/combat.rbxl`. Missions keep today's code until P5.

**Shipped (2026-09-24, commits `07f8908`, `69eab8f`, `de404ad`, `34d632a`):**
- **Crowd enemies** (`CrowdService`, `CrowdCodec`, `CrowdRenderer`):
  - no Humanoids; the server keeps plain records and sends compact buffer snapshots (15 Hz,
    unreliable);
  - the client draws pooled bodies; the head is the crit point;
  - kinds: fodder, armoured (flat armour 18), boss (10 000 HP).
- **Hit shapes** (`HitShapes`, server-resolved, forgiving pad): arc, sphere, capsule, cone, ray.
- **Sword A/B/C:** Wide arc; Spin finisher (360° third hit); Shockwave (sphere).
- **Gun A/B/C:** Shotgun (true cone, 8 pellets); Piercing rifle (up to 8 per shot); Launcher
  (visible shell, splash 10).
- **Movement** (`MovementController`, server-checked in `RangeService`):
  - big jump (18) and double jump (12);
  - dash 20 studs with i-frames;
  - ground slam that needs a real dive;
  - air sword swings hang briefly and reach 6 studs down.
- **Shooting:** camera-ray aim, bloom, exact first shot, ADS (FOV 50), head crits ×2.
- **Phone:** no attack button; `autoFire` (default) or `tapFire`; Dash button turns into Slam in
  the air; Aim button with the gun.
- **Feedback** (`FeedbackController`, `Crosshair`): hit marker, damage numbers, enemy flash,
  enemy reaction, hitbox effect, hitstop, shake, edge flash, haptics, counters. Each has a
  strength slider (0 = off).
- **RangePanel** (Studio, "⚙ Range", top-left):
  - dummy sets, Reset, Stress, Export, Clear tune, Wire, Touch mode;
  - weapon + variant switch;
  - live sliders for every number;
  - readouts: hits, kills, DPS, clear time, alive, server ms, FPS.
- **Live tuning:** `Tuning.luau` overrides through `RequestTune`; Export prints the merged
  `ProvingGrounds.json` to Output.

**Review outcome:** 0 Critical, 2 Majors, 11 Minors. **All fixed** in `34d632a`.
- Major 1: shots were refused while moving fast (origin check is now speed-aware; a refused
  shot drops its client fx).
- Major 2: the shotgun did not test the cone it drew (now a true cone).
- Minors included: air swings reaching down, salted pellets, dive-gated slam, combo reset,
  tunables moved to config, one `TuneState` listener, a panel leak, allocation-free decode.
- qa-runner: ALL GREEN. Missions untouched (`sim_combat.py --check`, `sim_economy.py --check`
  unchanged).

**Known limits at P1:**
- Silent by ruling.
- Placeholder bodies and empty hands; no models.
- Dummies never attack.
- Missions do not use the new combat yet (P5).
- Co-op in the range is untested (hits are broadcast to everyone in the range, but nobody has
  tried two players).

**Next (COMBAT_DESIGN §10):**
- **P2 (Ben + lead):** pick the winning sword and gun variants in the range, commit the exported
  values as the new defaults.
- **P3:** the remaining weapon classes and abilities, in batches.

- [x] P1 built, reviewed and QA green (definition of done in INTERFACES "P1 contracts")
- [x] Ben's playtest (2026-09-28): "I really love all the alternatives, the combo melee is great, it lacks the bow, but everything works great." Panel UX fixed after the first look (right edge, P key). Next: weapon roster in `docs/WEAPONS.md` (approved), P2 = bows + Greataxe + Spear in the range.

## P2 — Weapon families + bows

**Goal:** turn the P1 sword/gun variants into weapon families, add the bow and the first new
melee families, and give each player a melee slot and a ranged slot. Still range-only
(`build/proving.rbxl`); missions untouched until P5; abilities are P3. Plan of record:
`docs/WEAPONS.md` (approved 2026-09-28); contracts: `docs/INTERFACES.md` "P2 contracts"; values:
`docs/BALANCE.md` "P2 — new families".

**Shipped (2026-09-28, commits `9921c00`, `416dfb9`, `370c74d`):**
- **10 families** in `ProvingGrounds.json weapons`, each with `name`, `slot`, `era`, variants:
  - the six P1 variants, numbers unchanged: Broadsword, Spinblade, Warhammer, Shotgun,
    Piercing Rifle, Launcher;
  - new, each with A/B: **Greataxe** (Wide cleave / Fast chop), **Spear** (Pike thrust / Long
    lunge), **Longbow** (Pierce + blast / Quick shot), **Splitbow** (Fan of 7 / Wide fan of 5).
- **Loadout slots:** one melee family, one ranged family (`RangeLoadout`, default Broadsword +
  Longbow). **1** = melee, **2** = ranged, gamepad **Y** toggles.
- **Real arrows, stepped on the server:**
  - gravity drop over distance;
  - `pierce` = total enemies hit (same meaning on the hitscan rifle); the arrow stops at the cap;
  - a full charge bursts in the last enemy hit;
  - split fans are announced by the server (also at point blank, where the fan starts at the
    first enemy).
- **Hold to draw:** the crosshair's ring of dots fills and turns gold at full charge; a quick
  tap fires a weak arrow. The server caps the charge with its own draw clock.
- **Phone:** autoFire draws and releases by itself on a target; tapFire = tap for a weak arrow,
  hold still to draw.
- **Every player sees every shot fly** (`CombatFxShot`): arrows, split fans, launcher shells.
  Closes the P1 "other players' shots have no fx" carry-over.
- **Spear thrust streak** (bright core + speed lines out to the tip).
- **RangePanel Weapons section:** Melee and Ranged pickers grouped by era, then variant
  buttons; the "Tuning:" rows follow the active slot.

**Review outcome:** 0 Critical, 2 Majors, 11 Minors. **All fixed** in `370c74d`.
- Major 1: a point-blank split fan was never drawn (the server now announces the split).
- Major 2: `pierce` meant different things on arrows and the rifle, which left a ghost arrow
  and a misplaced burst (now pierce = total everywhere, and the arrow stops at the cap).
- qa-runner: ALL GREEN. Missions untouched (`sim_combat.py --check`, `sim_economy.py --check`
  unchanged).

**Balance notes (`docs/BALANCE.md` "P2"):**
- The Spear sits a little under the melee band on purpose (it hits from outside the crowd).
  Knob if Ben finds it weak: both damages +15%.
- The approved Piercing Rifle measures above the ranged band (556 crowd DPS). Knob if it
  outshines the bows: `pierce` 8 → 5.

**Known limits at P2:**
- Still silent, placeholder bodies, empty hands, dummies never attack.
- On a real phone the range has no slot-switch button (the Studio emulator takes the 1/2 keys).
  Owner: lead, decide in P3 with the ability buttons. **Closed in P3** (touch slot button).

**Next:**
- **P3 (lead):** an ability for every family, then the remaining families (Beam, Chain Gun, SMG).
- **Carry to P5 (lead):** local prediction of your own shots. Today your arrow appears one
  round trip after you fire.

- [x] P2 built, reviewed and QA green (definition of done in INTERFACES "P2 contracts")
- [x] Ben's playtest (2026-09-28): everything works, strengths fine. Favourites: Longbow A and B,
  Splitbow A, Greataxe A and B, Spear B, so the **Spear default is now B** (applied in P3).

## P3 — Abilities + SMG / Beam / Chain Gun

**Goal:** one ability per weapon family on Q (melee slot) and E (ranged slot), cooldowns that
kills shorten, the last three families (SMG, Beam, Chain Gun), and a phone slot button. Still
range-only (`build/proving.rbxl`); missions untouched until P5. **No sound. No attack button on
phones.** Plan of record: `docs/WEAPONS.md` §2; contracts: `docs/INTERFACES.md` "P3 contracts"
(with "Review round"); values: `docs/BALANCE.md` "P3".

**Shipped (2026-09-28, commits `be7dba2`, `93efcbb`):**
- **Abilities for all 13 families**, server-owned and tunable in the range:
  - Whirlwind, Earthquake, Blade Storm, Leap Smash, Impale Dash, Arrow Rain, Volley, Slug Burst,
    Overcharged Shot, Mag Dump, Cluster Shell, Overload Sweep, Storm Coil.
  - **Q** = melee slot's ability, **E** = ranged. Gamepad **L1 / R1**.
  - Cooldowns live on the server. Every kill takes a per-ability refund off **both** slots,
    never below a 40% floor.
  - Some abilities lock the caster while they run (busy).
  - Leap Smash and Impale Dash move the character on the client; the damage lands where the
    server resolved it.
- **New families, each with A/B:**
  - **SMG** (Metropolis): A Spray, B Heavy SMG.
  - **Beam** (Orbital Colony, a held continuous beam): A Sweep beam, B Lance.
  - **Chain Gun** (Orbital Colony, chain lightning): A Chain lightning, B Arc storm.
- **Phone:** two ability buttons with cooldown discs and a **slot button** (names the other
  slot's family). Closes the P2 known limit. Still no attack button.
- **PC / gamepad:** AbilityBar HUD (bottom centre) with cooldown sweeps, key hints and "−N.Ns"
  refund pop-ups.
- **RangePanel:**
  - "Cooldowns: normal · click for off" button at the top of Weapons;
  - "Ability: <name>" tuning rows under the variant rows;
  - an "Abilities" section (`abilities.*`);
  - an ability readout line (hits and kills of the last cast).
- **AbilityFx:** a lasting visual for every ability. Every player sees them; exact areas are
  drawn unpadded.
- **FeedbackController:** tick strikes merge into one growing number and skip hitstop; chain
  bolts; one held beam per shooter.
- **Server remote buckets:** `rangeAttack` 40/s, `rangeAbility` 4/s. A per-slot rate credit (one
  banked shot, `shooting.rateBurstShots`) replaced the frame-gap check and removed ~4% refused
  shots at high fire rates.
- **`tools/sim_range.py --check`:** permanent range simulator with design bands.
- **Spear default is now B** (Ben's P2 verdict).

**Review outcome:** 0 Critical, 2 Majors, 9 Minors. 8 Minors fixed, 1 deferred.
- Major 1: ability arcs ignored airborne reach, so a jumping Whirlwind lost ticks. Fixed with
  `AbilityStrikeSpec.airReach`; the Whirlwind ring is now drawn on the real floor.
- Major 2: Mag Dump fired 30/s instead of 36/s (client frame rounding). Fixed with a true
  accumulator.
- Minors fixed:
  - separate ability seeds;
  - dead tunables honoured;
  - `refusedSeq` cancels a refused cast's local effects at once;
  - `pcall` around timelines;
  - three tolerances moved to config (`shooting.rateBurstShots`, `abilities.busyEarlySeconds`,
    `abilities.dashWallClearance`);
  - Overcharged Shot no longer drawn twice;
  - Storm Coil bolts start at the pylon top;
  - the beam is always visible and lingers at least 0.3 s.
- Minor deferred to P5 (owner: lead): the caster's own ability visuals and held beam wait one
  round trip on live servers (Studio round trip ≈ 0). Joins "local prediction of your own
  shots".
- qa-runner: ALL GREEN. `sim_economy.py --check`, `sim_combat.py --check` and
  `sim_range.py --check` pass; missions untouched.

**Balance notes (`docs/BALANCE.md` "P3"):**
- One cast ≈ 4 s of the family's crowd DPS. In a busy crowd the effective cooldown is ≈ 50% of
  base.
- **Flag 1 for Ben — cross-slot refunds.** Heavy melee killing keeps the ranged abilities near
  their floor. Knob (contract change, not a value): refund a slot only from its own kills.
- **Flag 2 for Ben — SMG vs armour.** SMG and Beam ticks are below armour 18, so they barely hurt
  armoured dummies (they do shred bosses). WEAPONS.md calls the SMG an "elite shredder". Decide
  at P4 (enemy roles). Example knob: Heavy SMG 26 × 4.3/s.
- Whirlwind pays only when walked into the crowd; cast standing at the edge it loses to plain
  swings.

**Known limits at P3:**
- Silent, placeholder bodies, empty hands, dummies never attack.
- Ability visuals and the held beam wait one round trip on live servers.
- A family switch resets that slot's cooldown (range convenience). P5 must carry the cooldown
  across a switch.

**Next:**
- **P4 (lead):** enemy roles and bosses, in the range. Settle the SMG-vs-armour flag there.
- **Carry to P5 (lead):**
  - local prediction of your own shots and ability visuals;
  - cooldown carried across a family switch;
  - re-measure refunds against chasing crowds.

- [x] P3 built, reviewed and QA green (definition of done in INTERFACES "P3 contracts")
- [x] Ben's playtest (2026-10-06): "i love all the wapons, we can find a way to integrate them
  all". Read as: **all 13 weapon families stay.**
  - **Not answered, still open for P4:**
    - A or B for SMG, Beam and Chain Gun;
    - cross-slot refunds (flag 1);
    - SMG against armour (flag 2);
    - favourite and weakest ability.
  - His one request is the next section, P3.1.

## P3.1 — A swing lands where you stand

**Goal:** Ben's one request from the P3 playtest (2026-10-06): "make the melee weapons act
instantly or at least make it following you, because if you are moving forward, the weapon
hitbox stays behind and you dont hit the enemies in front of you". Still range-only
(`build/proving.rbxl`); missions untouched. Contracts: `docs/INTERFACES.md` "P3.1 — a swing
lands where you stand" (with its "Review round").

**Where it is (2026-10-06): merged to `main`.**
- Ben: "good! lets close it". Built on branch `p3-melee-follow` (worktree `tycoon-p3`) and
  merged the same day. "Build all" in VS Code builds it now.
- **His look at the fix running is not confirmed.** When he said it, the only Studio session of
  the day had `tycoon\build\proving.rbxl` open, built at 15:07 from `main` before the fix;
  Studio's log names no other range file. The playtest box below stays open until he has
  played a build made after the merge.
- **Confirmed 2026-10-12:** he played a build made after the merge. The box below is ticked.

**Cause (two lags):**
- The server swept a swing from its own copy of the character's position. That copy trails
  the player's screen, so the arc sat behind a moving player.
- The hitbox effect was drawn only when the server answered, then stayed fixed in the world.
  A player walking at 20 studs/s had left it behind before it faded.

**Shipped:**
- **Server (`RangeService`):**
  - A swing resolves at the position the player's client sends.
  - That position is trusted within 4 studs plus what lag explains. Beyond that it is pulled
    back to the limit, never refused.
  - The slack is capped: fastest legal move 140 studs/s, lag 0.3 s. The same cap now covers
    ranged shot origins.
  - A swing just after take-off counts as airborne.
  - A refusal names the attack it refuses.
- **Client (`InputController`, `FeedbackController`):**
  - The hitbox effect appears on the click's frame.
  - It moves with the swinger, sideways and forward only. A jump does not lift it, and it
    never turns.
  - Other players' arcs follow them too.
  - Numbers, reactions and the hit marker still come from the server.
  - An early effect that turns out wrong (for example a Spinblade spin the server did not do)
    is replaced by the server's.
  - The combo step is predicted by the server's rule, and the server's step corrects it.
  - The wireframe stays the server's shape, fixed in the world.
- **Config (`src/shared/Config/ProvingGrounds.json`):** `controls.meleeOriginPad` 4,
  `shooting.originLagMaxSeconds` 0.3.
- No remote added or changed.

**Review outcome:** 0 Critical, 2 Majors, 6 Minors. Both Majors and Minors 1–4 fixed.
- Major 1: a swing just after take-off passed over the crowd. Fixed: airborne is judged where
  the swing resolves.
- Major 2: the slack had no ceiling (speed and ping are the client's word). Fixed with the cap
  above. Extra reach, in studs: 4 standing, 7 walking at 100 ms ping, 46 at worst for a forged
  client.
- Minors fixed:
  - a refusal names its attack (`RangeStats.refusedSeq`), so only that swing is taken back;
  - an early effect that disagrees with the server's strike is replaced;
  - the server restarts a combo only when the family or variant really changed;
  - the `RangeService` header comment.
- Minor 5, carried to P5: `FeedbackController` is at about 168 of 180 top-level locals.
- Minor 6, waits for a phone measurement: the follow moves the effect's parts one by one.
- qa-runner: ALL GREEN (2026-10-06). stylua; selene (only the old `LegacyPanel` warning); hub
  and combat luau-lsp with fresh sourcemaps; `check_compile.py` (124 files); the hub, combat and
  proving builds; `sim_economy.py --check`, `sim_combat.py --check` and `sim_range.py --check`.
  Asset gates not run: no asset or template changed.

**Not in this wave:**
- Melee abilities (Whirlwind, Earthquake, Leap Smash, Impale Dash) still resolve at the
  server's copy of the position.
- Early effects for guns and bows (P5).
- The phone auto-swing pads. An auto-swing can start up to 2 studs outside real reach, and
  the early arc now shows that miss. Config-only if Ben sees it.

**Carried (owner: lead, P5):**
- Take the speed for the slack from the server's own position history, before this path
  reaches missions.
- Group `FeedbackController`'s state into tables before early ranged effects are added.
- Measure the follow on a phone (with the first phone playtest). One `BulkMoveTo` per effect
  is the fix if it asks for one.
- Melee abilities at the server's position, if Ben feels it.

- [x] P3.1 built and reviewed (definition of done in INTERFACES "P3.1")
- [x] Ben's playtest (2026-10-12): "okey, everything feels great now, lets proceed". Studio's
  log for that day shows one six-minute session on a build made after the merge (the P4 Stop 1
  build), with no script error, on `crowd30`: the melee fix is confirmed in Studio.

## P4 — Enemies that fight back

**Goal:** the range's enemies attack and the player can be hurt. Fodder, three shooters, a brute
and a plated elite each fight their own way; then two bosses. Still range-only
(`build/proving.rbxl`); missions return at P5. **No sound. Phones must work.** Plan of record:
`docs/COMBAT_DESIGN.md` §7 and §10 step 5; contracts: `docs/INTERFACES.md` "P4 contracts"
(rulings 1–26, "Wave 2 — roles", "Stop 2 — the Colossus" and "Stop 3 — the Warlord and his
guard", each with its review round);
values: `docs/BALANCE.md` "P4".

**Ben's rulings (2026-10-07):**
- Go for P4: "feels good, lets start".
- **Armoured elites carry a breakable plate.** Only heavy hits damage it; once it breaks, every
  weapon hurts the elite in full. This settles P3's flag 2 (SMG against armour). Built in wave 2.
- **Three shooter enemies** ("lets make all of these"), one attack each. Built in wave 2.
  - Slinger: slow glowing shots you dodge.
  - Marksman: a warning line, then an instant hit.
  - Lobber: an arcing shot that lands in a ground circle.
- Still open from P3: A or B for SMG, Beam and Chain Gun; cross-slot refunds; favourite and
  weakest ability.

**Stops and waves:**
- **Stop 1:** the player can be hurt; fodder, the three shooters, the brute and the plated elite
  fight. Built in two waves, then Ben's playtest.
  - **Wave 1, "they hurt you":** fodder lunge, elite arc, health, down and up, hurt feedback.
    Ben was offered an **optional quick look, not a stop**. He did not report one, so Stop 1's
    checklist covers it.
  - **Wave 2, "roles":** slinger, marksman, lobber, brute, the plate; sets `shooters`, `brutes`,
    `fight`; `elites` gets plates.
- **Stop 2:** the Colossus, the first of two bosses (Ben, 2026-10-12: "Both, as two bosses").
- **Stop 3:** the Warlord and his guard, the second boss. It closes P4.

**Where it is (2026-10-12):** everything of P4 is merged to `main` and the place files are
rebuilt: waves 1 and 2 (2026-10-08), Stop 2 the Colossus (signed off by Ben) and Stop 3 the
Warlord and his guard, merged the day it was built after review and QA. Play opens on the
Warlord. Stop 3 waits for Ben's playtest (`docs/PLAYTEST.md` "P4 Stop 3"); P4 is complete
when he signs it off. The Stop 1 `fight` set is still not judged by him.
- "Build all" builds `main`, and Ben opens `tycoon\build\proving.rbxl` by habit (P3.1). Asked
  on 2026-10-08, he chose **"Merge each ready wave"**: every P4 wave that has passed review and
  QA is merged to `main` without asking again.
- The code is inert outside Studio's range.

**Wave 1 shipped (2026-10-07):**
- **What the player meets:**
  - **Fodder** close in and lunge: a 0.6 s windup shown on the body (it rears back and turns
    red), a thrust for 8, then 1.5 s spent. At most **2** attack one player at once; the rest
    crowd and wait.
  - **The armoured elite** swings a 120° arc: a 0.8 s windup with a red wedge on the ground
    that fills, 30 damage, a knock back of about 6 studs.
  - **Health:** 130, fixed in the range. Regen 10 a second after 4 s unhurt.
  - **Being hit** shows a red flash at the screen edges, a pointer to where the hit came from
    and the number lost.
  - **Avoiding:** a hit the dash's protection voids shows "DODGED"; a jump clears ground
    attacks; walking out of the shape works too.
  - **At zero:** down for 2 s, then up in place at full health with 1.5 s of protection. No
    respawn.
  - **Interrupts:** any hit cancels a fodder's attack; only a heavy hit (40 or more) cancels
    the elite's.
  - **God mode** (panel button): enemy hits miss and show as "DODGED".
  - Two new dummy sets: `fodderRush` (30 fodder that fight) and `elites` (3 armoured that
    fight). The P1–P3 sets are unchanged: their dummies never attack.
- **Server:**
  - New `CrowdBrain.luau`: the `rush` brain; an attack as a fixed timeline (windup, impact,
    strike, recover) for `lunge` and `arc`; the attacker cap; interrupts.
  - New `VitalsService.luau`: health, regen, dodges, down and up, `god`, the `hurt` effects,
    and the commit rule (a hit is judged a moment after its impact, against where the player's
    own screen had them).
  - `CrowdService`: a group whose behaviour is `fight` runs its kind's brain; a body in windup
    or attack is planted; impacts are queued and handed over after the step. The passive
    behaviours are untouched.
  - `RangeService`: drives `VitalsService`; the `god` range command; no attack, dash or slam
    while down; a fight slot does not respawn while a player stands on it; the range's
    invisible ForceField is gone.
  - `CrowdCodec` v2: the snapshot names the attack an enemy is in. Still 11 bytes an entry.
  - No new remote. `hurt` rides the existing `CombatFx` event; health replicates as
    `Humanoid.Health`.
- **Client:**
  - New `VitalsController.luau` and `UI/VitalsHud.luau`: the health bar, the edge flash, the
    pointer, the number lost, "DODGED", the "DOWN · up in …" banner, the green get-up shimmer.
    Another player's hit flashes their character.
  - New `Haptics.luau`: the motor pulse, shared with `FeedbackController`, whose own copy is
    gone (fewer top-level locals there, not more).
  - `CrowdRenderer`: codec v2; the fodder's tell on its body; the elite's ground wedge. Tells
    are timed on server time and never thinned on `reducedMotion` or `lowEndDevice`.
  - `MovementController`: `ApplyKnock`, `SetDown`. `InputController`: nothing is sent while
    down.
  - `RangePanel`: a **God mode** button at the top of "Dummies & commands"; a fifth readout
    line, "Taken N · Downs N".
- **Config (`src/shared/Config/ProvingGrounds.json`):** attacks for `fodder` and `armoured`;
  `crowd.heavyHit` 40; `crowd.threat`; `player`; the two sets.
- **Balance tools:** `tools/sim_range.py` has a threat section, the first where the crowd
  moves. `--check` guards its bands.

**Rulings the lead added during wave 1 (16–25; 26 came after its QA, below):**
- **Numbers (16, 19):**
  - The fodder cap is 2, not 4. At 4 a still player is down in about 5 s. Ben was told 4 first
    and has been told 2.
  - The lunge's windup is 0.6 s, not 0.5. At 0.5 a phone thumb had 0.01 s to step out.
- **Health pinned at 130 in the range (17):** the tier-1 body against tier-1 weapon numbers,
  whatever the Studio profile holds. P5 returns to the profile.
- **Hits decided together do not stack through a knock (18):** when a knocking hit lands, the
  other hits waiting on that player are voided and shown as "DODGED". Without it three elites
  landed as one hit of 60 or 90.
- **Flat for now (20):** enemy damage, regen and `crowd.heavyHit` do not scale with weapon tier.
- **A hopping player (21):** the Major below.
- **Timing (22, 23):**
  - A due impact is never lost when its enemy is hit or killed just after its impact time.
  - `hurt` leaves in the frame it is decided, so the bar and the flash move together.
- **Fixed as found (24):** a player down at an impact's time is skipped; the i-frame window
  before the current one is tested too; no bow draw while down; the bar shows full from the
  get-up.
- **Accepted (25):**
  - About a quarter of impacts test the player up to 33 ms late at Studio's ping.
  - Ability zones placed before going down keep resolving.
  - A player who joins mid-fight may see one blow late.
  - The pointer ring crosses the combo counters at some bearings on a 375-wide screen (for
    Ben's look).

**Review outcome, wave 1:** 2 Critical, 1 Major, 10 Minor.
- Both Criticals were rulings 17 and 18: added while the review ran, not yet in the code.
  Implemented.
- Major, ruled (21): holding jump voided about five fodder hits in six.
  - `reach` is now measured on the flat, so enemies gather and wind up under a player in the
    air and a landing is not free.
  - The answer to a player who stays in the air is wave 2's shooters, which aim at the body.
  - Ground shapes are still jumped over.
- Minors: fixed or accepted as rulings 22–25.
- qa-runner: ALL GREEN (2026-10-07). stylua; selene (only the old `LegacyPanel` warning); hub
  and combat luau-lsp with fresh sourcemaps; `check_compile.py` (129 files; highest top-level
  counts FeedbackController 159, InputController 144, EnemyService 140); the hub, combat and
  proving builds; `sim_economy.py --check`, `sim_combat.py --check`, `sim_range.py --check`
  (105 checks). Asset gates not run: no asset or template changed.
- After QA: ruling 26 (a dash away from an attack aimed at you reads as "DODGED"), server only,
  re-verified by the lead.

**Balance, wave 1 (`docs/BALANCE.md` "P4"; tier 1, from `sim_range.py`):**
- A player standing still goes down in **8.7 s** in `fodderRush` (target 6–12 s) and in
  **11.9 s** in `elites` (9.8 s since wave 2's turn rule).
- No single hit takes more than 25% of health: lunge 8 (6%), arc 30 (23%).
- Walking away takes no damage in either set. Both enemies are slower than the walk.
- A player who keeps swinging takes no hit in either set (all five melee families, 60 s).
- Nothing was tuned in real play. Every number is a starting value.

**Known limits at wave 1:**
- Health only drops while the player is not attacking: a sword outreaches a lunge and any hit
  cancels it. Wave 2's shooters and brute are what reach a busy player.
- Jumping again and again still avoids most fodder hits. The shooters are the answer (wave 2).
- The elite is soft until it has its plate (wave 2): a still player loses less to three elites
  than to the fodder.
- The 8-stud step is safe ground: both attacks pass under it and the crowd stays on the floor.
  Wave 2's shooters and lobber reach it.
- Enemies walk through cover (since P1).
- Placeholder bodies. No sound.
- **Unmeasured:** the server step time with `fodderRush` running. Only Ben can read it, off
  the panel in Studio. Budget 2 ms.

**Wave 2 shipped (2026-10-08):**
- **What the player meets:**
  - **Slinger** (amber, an orb held in one hand; keeps 18–30 studs away): the orb swells and
    reddens for 0.6 s, then flies as a slow glowing red orb aimed at where the player will be.
    12 damage. Answers: change direction after the throw, dash, or put cover between. Hopping
    on the spot is not safe.
  - **Marksman** (purple, a long barrel; keeps 28–45): a thin red line follows the player for
    0.45 s, locks and stands as a wall for 0.55 s, then the shot is instant along it. 22
    damage. Answer: step out of the wall after it locks. A jump does nothing.
  - **Lobber** (green, a pack on its back; keeps 22–40): a shot arcs in and lands 1.4 s later
    in a red ground circle 5 studs in radius. 18 damage and a short knock. Answer: walk out.
    It comes over cover and lands on a block the player stands on.
  - **Brute** (big, horned, 320 HP): a lane fills for 0.8 s, then it charges 30 studs in
    0.55 s. 28 damage and a knock of about 6 studs. Answers: sidestep, jump or dash. Then it
    stands spent for 1.5 s. A heavy hit cancels its windup; nothing stops the charge.
  - **Plated elite:** plate 80 over 160 HP, shown as a metal shell and a two-row bar over its
    head.
    - A hit under 40 shows a small grey "BLOCKED" and does nothing at all.
    - A heavy hit (40 or more) takes its amount off the plate, shown in the plate's blue.
    - The hit that empties it shows "PLATE BROKEN". The elite reels for 1.5 s, and after that
      every weapon hurts it.
  - **Turns:** at most 2 fodder, and 1 of every other kind, are in windup or attack against
    one player at once.
  - **High ground:** a stair or a pillar is safe from fodder, elites and brutes. The three
    shooters still reach it.
  - **Sets:** `shooters` (2 slingers, 2 marksmen, 2 lobbers), `brutes` (3), `fight` (100
    fodder, 3 slingers, 3 marksmen, 2 lobbers, 3 brutes, 3 elites). `elites` now has plates.
  - **An old set changed (ruling 13):** the passive `armoured` set's dummies carry the plate
    too. Light fire on them now reads "BLOCKED" where P3 showed tiny numbers. They still never
    attack.
- **Server:**
  - `CrowdBrain`: the `keepAway` brain; the shapes `shot`, `line`, `lob`, `lane`; the turn
    rule (`perPlayer`).
  - New `ThreatField.luau`: the two attacks that travel (a slinger's shot, a brute's charge),
    judged every crowd step; and the world queries of enemy attacks, one ray each (a shot's
    path cut at fire, a line at its impact, the surface under a lob's target).
  - New `StrikeTally.luau`: the one place a strike's hit list is built. Plate damage and
    health damage are separate entries; `blocked` is a hit of 0.
  - `CrowdService`: the plate (blocked, plate, broke) and the reel, worn in every set.
  - `VitalsService`: the line, the lob's landing, the high-ground rule, and ruling 26 (an
    aimed miss under an i-frame reads as "DODGED").
  - No new remote. `enemyShot`, `enemyShotEnd` and `area` ride the existing `CombatFx` event.
- **Client:**
  - New `Controllers/ThreatFx/` folder: `Tells` (the lane and the line, from the snapshot),
    `Areas` (the circle and the lob's arc), `Shots` (the orbs), `Cues` (one shape cue per
    role), `PlateBar` (the two-row bar), `Pool` (pooled parts, one batched move a frame).
  - `CrowdRenderer`: wears the cues and the plate's bar; the shell's burst and the reel; a
    brute's charge is drawn on the server clock, ahead of its snapshots.
  - `FeedbackController`: "BLOCKED" (one small grey word per stream of light fire, never a
    0), plate damage in the plate's blue, "PLATE BROKEN" on its own line.
  - Everything is drawn against server time. Tells are never thinned; a low-end device loses
    only decoration (the orb's tail, half the bars of a circle's rim).
- **Config (`src/shared/Config/ProvingGrounds.json`):** the kinds `slinger`, `marksman`,
  `lobber`, `brute`; `armoured.plate` 80 with `armor` 0; `crowd.plateBreakSeconds` 1.5;
  `perPlayer` on every kind that fights (replaces `crowd.threat.attackersPerPlayer`); the three
  sets.
- **Balance tools:** `tools/sim_range.py` gained the three shooters, the brute, the plate, the
  turns and five more players (hops on the spot, strafes one way, reacts to every tell, swings
  and never dodges, swings and reacts). Four more tables; `--check` guards the new bands.

**Rulings given during wave 2 (lead, 2026-10-08):**
- **A.** A locked facing is snapped to the snapshot's yaw step and judged with that value, and
  a shove never turns a body whose facing is locked. The wall the client draws and the lane
  the server tests are the same line.
- **B.** Plate and health are separate hit entries when one strike does both to one enemy.
- **26** (wave 1, after its QA): a dash away from an attack aimed at you reads as "DODGED".
  Walking out is not a dodge and shows nothing.

**Review outcome, wave 2:** 0 Critical, 1 Major, 7 Minor.
- Major, fixed: standing on range furniture voided every attack. High ground now protects
  from melee and ground shapes only; the three shooters reach it.
  - Shot: a player standing on a block is aimed at where they stand.
  - Line: its ray goes at the body it locked on, so the block under the target does not cut
    it. A wall between the two still does.
  - Lob: it lands on the surface under its target.
- Minors, fixed:
  - A shot's path is cut once, at fire. The client fizzles the orb at the wall on its own
    clock.
  - The lane's tell is drawn to the rounded end the server tests.
  - A line whose target is gone before the lock is still snapped.
  - The speed the led aim trusts is capped at the fastest legal move.
  - The travelling attacks reuse their per-step scratch tables.
- Minors, accepted:
  - The marksman's wall is drawn at full range, also through cover.
  - `maxShots` can be passed by one on a catch-up frame.
  - A player's own shots at a charging brute are tested up to 3.7 studs behind where it is
    drawn (for Ben's look).
- After the review, from the balance report:
  - **Enemies of one kind take turns.** Three marksmen had fired as one: 66 damage at once.
  - **A shot is led over its flight plus the player's lag,** in six passes. `lead` is 1.0.
  - **The marksman's lock is 0.55 s before the hit,** so a phone thumb keeps 0.14 s.
- qa-runner: ALL GREEN (2026-10-08). stylua; selene (only the old `LegacyPanel` warning); hub
  and combat luau-lsp with fresh sourcemaps; `check_compile.py` (138 files; highest top-level
  counts FeedbackController 159, CrowdRenderer 145, InputController 144); the hub, combat and
  proving builds; `sim_economy.py --check`, `sim_combat.py --check`, `sim_range.py --check`
  (176 checks). The server's own harness: 310 checks, 104 mutations, none surviving. Asset
  gates not run: no asset or template changed.

**Balance, wave 2 (`docs/BALANCE.md` "P4" → "Wave 2"; tier 1, from `sim_range.py`):**
- **Standing still, down at:** `fodderRush` 8.7 s, `elites` 9.8 s, `shooters` 7.3 s, `brutes`
  8.3 s, `fight` **5.8 s** (target 4–8 s).
- **The worst quarter second in `fight`, standing still:** 102 damage (78% of the bar) before
  the turn rule, **66 (51%)** now. By the rules alone one instant can cost at most 80 (62%).
- **A player who reacts to every tell takes no hit in any set,** fodder included. Swinging and
  reacting in `fight` takes nothing and kills 397 in 30 s.
- **Swinging without dodging in `fight` is down at 6.6 s.** Strafing one way without looking,
  at 17.1 s.
- **No single hit over 25%:** shot 12 (9%), line 22 (17%), lob 18 (14%), charge 28 (22%).
- **Blind movement is answered:** in `shooters` the marksmen take a hopper down at 11.6 s and
  the slingers a one-way strafer at 22.5 s.
- **The plate:**
  - Break it in 2 hits: Warhammer, Greataxe A, Spear A, Longbow A and B, Splitbow B, Shotgun,
    Piercing Rifle, Launcher, Chain Gun A.
  - Need two combos (6 hits; the finisher is their one heavy hit): Broadsword, Spinblade,
    Greataxe B, Spear B.
  - Cannot alone: Splitbow A, SMG A and B, Beam A and B, Chain Gun B. They use the melee slot
    or two ground slams. Splitbow A and Chain Gun B can with head shots.
  - After the break an SMG kills the elite in 1.42 s (A) or 1.29 s (B), against a 1.5 s reel.
- Nothing was tuned in real play. Every number is a starting value.

**Known limits at P4 Stop 1:**
- **Kiting heals.** A player who runs a big circle takes no damage in `shooters`, `brutes` or
  `fight`, and regenerates. Every enemy is slower than the walk.
- **Elites are slow work, not danger,** for a player who keeps swinging: every combo has a
  heavy hit, and a heavy hit cancels the arc.
- **Hopping is still the cheapest defence against ground attacks:** one lunge in four, one
  charge in three and one lob in four or five land on a hopper. The marksman is the answer,
  and `fodderRush` and `brutes` have none.
- **Six weapon variants cannot break a plate alone** (the list above).
- Enemies walk through cover (since P1). Shots and the marksman's line are stopped by it; a
  lob is not.
- The marksman's wall is drawn at full length through cover: it can look dangerous where the
  player is safe, never the reverse.
- A player's own shots at a brute in mid-charge are judged a little behind where it is drawn.
- **Not in the simulator:** cover and the stairs. Nothing about them is measured.
- `fight`'s simulator rows move a few percent between Python 3.12 and 3.14. Every band holds
  on both.
- Placeholder bodies with one shape cue per role. No sound.
- **Unmeasured, only Ben can:** the server step time with `fight` running (budget 2 ms), and
  how it runs on a phone-sized screen.

**Stop 2 — the Colossus (2026-10-12):**
- **Ben's word:** "okey, everything feels great now, lets proceed" (2026-10-12).
  - Studio's log for that day: one six-minute session on the Stop 1 build, no script error,
    and only `crowd30` (the passive dummies) was loaded.
  - So it confirms the P3.1 melee fix and that the build loads. It does not judge the Stop 1
    enemies.
  - `defaultSet` became `fight` the same day, so Play alone shows them. At Stop 2's merge it
    becomes `colossus`.
  - Stop 2 was started on his word.
- **His two answers (asked with previews):**
  - "Both, as two bosses": the Colossus now, then the Warlord and his guard (Stop 3).
  - "Two phases": a boss enrages at half health.
- **What the player meets:**
  - **The Colossus:** a giant (4,700 health) that cannot be pushed, launched, staggered or
    interrupted. Hits only take its health.
  - **Boss bar** at the top of the screen: its name, its health, a mark at half.
  - **Slam:** a circle on the floor shows how far it reaches (40 studs), then a low crest
    runs out from its feet. 26 damage. Jump it, or dash through it ("DODGED"). The player it
    is aimed at cannot walk out of it.
  - **Charge:** a wide lane (10 studs) fills, then it runs. 32 damage. Sidestep, jump or dash.
  - **Call:** it roars and fodder rise from the floor on a circle round it, up to 12. A call
    only replaces the ones killed.
  - **Enraged** at half health, for good: the bar and the body change, tells are shorter, two
    attacks follow each other with no pause, and a **Barrage** of five ground circles lands
    at once. A player takes at most one of the five (18 damage).
  - Every attack leaves an opening of about a second or more.
  - **The kill is clean:** its death takes back everything it had in the air and removes its
    fodder. It comes back 12 s later.
  - Play opens on it: `defaultSet` is `colossus`.
- **Server:**
  - `CrowdBrain`: an enemy with several attacks chooses among those off `cooldown`, in reach
    and allowed in its phase, the one used longest ago, never the same twice running. The
    enrage latch, the scaled windups and recovers, and the chain.
  - `ring` (the slam): a travelling shape in `ThreatField`, judged like a shot or a charge.
    Each player is hit at most once per ring.
  - `summon` (the call): the summoned fight with their kind's brain, never respawn, and fall
    with their boss.
  - The barrage: a `lob` with `count` and `spread`, one `area` per circle.
  - `CrowdService`: large bodies (`crowd.largeRadius` 3 or more) are never pushed by smaller
    ones, and `separate()` no longer widens its search for every body because one giant is
    alive.
  - No new effect kind, no new remote. `area` and `enemyShot` carry the thrower's `enemyId`.
- **Client:**
  - New `UI/BossBar.luau`: one row with the name on the health, the mark, the "ENRAGED" beat
    and the death beat.
  - New `ThreatFx/Rings.luau`: the slam's circle and crest, and the call's circle in a colour
    that is not the danger's red.
  - `ThreatFx/Cues`: a boss's silhouette (shoulders, a crown, back spines, a core in the chest
    that charges through every windup). Enraged, they are lit for good.
  - `CrowdRenderer`: the slam and call poses, the enraged look, summoned bodies rising through
    the floor.
  - `ThreatFx/Areas`: overlapping circles stay readable; a dead boss's circles go at once.
- **Config (`src/shared/Config/ProvingGrounds.json`):** kind `colossus`, set `colossus`,
  `crowd.largeRadius`, `defaultSet`. The passive `boss` dummy kind is unchanged.
- **Balance tools:** `tools/sim_range.py` prints a BOSS table; `--check` guards its bands.

**Rulings after the Stop 2 reports (lead, 2026-10-12):**
- A boss's death takes back everything it had in the air. Ruling 22 (a due impact is never
  lost) stays for ordinary kinds.
- A call tops up, it does not stack.
- A player takes at most one circle of a barrage.
- Large bodies are never pushed by smaller ones.

**Review outcome, Stop 2:** 0 Critical, 0 Major, 7 Minor.
- Fixed:
  - A dead boss's circles and shots are dropped by its own id, not by kind.
  - `crowd.largeRadius` replaces a code constant.
  - A strike that kills a boss no longer books its vanished summons as hits of 0.
  - Ground marks sit near the floor again (nothing informational above about 0.4 studs).
  - The enrage haptic obeys `feedback.haptics`; the boss bar's last two visual constants
    moved to Theme.
- Accepted:
  - Summoned bodies are told from a set's own by a heuristic (kind, time, place).
  - On a portrait phone the open panel covers the boss bar.
- The server's own harness: 440 checks, 176 mutations, none surviving.
- qa-runner: ALL GREEN (2026-10-12). stylua; selene (only the old `LegacyPanel` warning); hub
  and combat luau-lsp with fresh sourcemaps; `check_compile.py` (140 files; highest top-level
  counts FeedbackController 159, CrowdRenderer 149, InputController 144); the hub, combat and
  proving builds; `sim_economy.py --check`, `sim_combat.py --check`, `sim_range.py --check`
  (239 checks). The server's own harness: 440 checks, 176 mutations, none surviving. Asset
  gates not run: no asset or template changed.

**Balance, Stop 2 (`docs/BALANCE.md` "P4" → "Stop 2"; solo, tier 1, from `sim_range.py`):**
- **A player who reacts to every tell takes no hit** and kills it in about **64 to 82 s** with
  any melee family, without abilities (target 60 to 90 s).
- **A player who only jumps the slam and sidesteps the charge survives:** no down, about 86
  damage taken in the whole fight.
- **Standing still is down in under 9 s** (target: inside 10 s). The fodder do most of it,
  which is why the fight opens with the call.
- **No hit over 25% of health:** slam 26 (20%), charge 32 (25%), one barrage circle 18 (14%).
  The most one instant can cost is 48 (37%).
- **Every attack leaves a window of 1.08 to 2.20 s,** in both phases.
- **Ranged:** every family kills it. Piercing Rifle and SMG take under a minute. **The bows
  are slow: about 2.5 minutes with the Longbow (142 s) and close to 4 with the Splitbow
  (226 s).** A weapon question for Ben, not a bug.
- **Enraged tells are 0.8 s where the calm ones are 1.0 s** (`windupScale` 0.8, set for
  phones). The enraged charge is the tightest: a 0.35 s thumb keeps 0.13 s.
- Nothing was tuned in real play. Every number is a starting value.

**Known limits at P4 Stop 2:**
- **Boss health does not scale with a second player in the range.** Two players finish in
  about half the time (32 to 41 s for two melee players).
- **Kiting works here too.** A ranged player who keeps far away meets only the call and, when
  it is enraged, the barrage.
- Abilities take a melee kill under the 60 s floor (the band is measured without them).
- Fodder are shoved aside when it walks or charges through them.
- The barrage is the gentlest of the four attacks: ignoring it costs little.
- Placeholder bodies. No sound. The Stop 1 limits still apply.
- **Unmeasured, only Ben can:** the server step time during the boss fight with its fodder up
  (budget 2 ms).

**Stop 3 — the Warlord and his guard (2026-10-12):**
- **Ben on the Colossus (2026-10-12):** a six-minute session in the `colossus` set, then
  "Great, on to the Warlord", "Nothing, all clear" on the tells, "About right" on the length.
  Stop 2 is signed off; it was also his first fight against enemies that hit back.
- **What the player meets, a siege then a duel:**
  - **Guarded from the first moment.** The Warlord stands back inside a shimmering shell.
    Hits on him say "GUARDED".
  - **The call, once:** after about a second four plated guards rise round him and rush the
    player. A lit line ties each living guard to him.
  - **Barrages** of three ground circles while the guard fights.
  - **The guard:** one heavy hit breaks a guard's plate (the sword's third swing, a hammer, a
    full bow draw, or the ground slam). Two attack one player at a time.
  - **Chasing him while his guard lives gets nowhere:** his plate cannot be hurt and the guard
    catches the player.
  - **Guard dead:** his shell opens. Heavy hits now break his plate, which has its own row on
    the boss bar, while he backs away slowly.
  - **The plate shatters:** he staggers for a second and a half, the bar reads "DUEL", and he
    comes at the player: a wide half-circle swing, a charge, a four-circle barrage, two
    attacks back to back.
  - Killing him removes anything left. He comes back 12 s later.
  - Play opens on him: `defaultSet` is `warlord`. The Colossus stays in the panel.
- **Server (four new keys, each general):**
  - `CrowdAttackDef.calm`: an attack chosen only before the second phase.
  - `CrowdAttackDef.uses`: the most times one enemy may land an attack in its life (the call:
    once).
  - `CrowdKindDef.guarded`: the plate takes no damage while the body has a living summon or
    still owes its call. A guarded hit is flagged `guarded` on the strike.
  - `enrage.brain`: the brain it fights with once enraged (`rush`). His phase turns when the
    plate breaks (`enrage.at` 1, the existing latch).
  - `CrowdSpawnInfo.summonerId` names the boss that called a body. Stop 2's heuristic for
    summoned bodies is gone.
  - **The reel:** a plate break always staggers, whatever the `knockbackMult`, and cancels a
    windup he was in. Ordinary hits still never move him.
  - Summons rise on a circle turned half a step for an even count, so none is stuck straight
    behind its summoner.
  - `crowd.largeRadius` is 2.5: his guard cannot push him.
- **Client:**
  - New `ThreatFx/Links.luau`: the tether from each living guard to him.
  - `UI/BossBar`: a plate row over the health row (the guard's colour while guarded, the
    plate's colour once it can be broken), a pip per guard, and "DUEL" for a boss with a
    guard ("ENRAGED" otherwise).
  - `ThreatFx/Cues`: the Warlord as a commander (a cloak, a crest, a standard whose orb
    charges through every windup); a pennant on each guard; the shell drawn as a ward while
    guarded.
  - `FeedbackController`: "GUARDED" as its own word in the guard's colour, never "BLOCKED".
- **Config (`src/shared/Config/ProvingGrounds.json`):** kinds `guard` (plate 40) and `warlord`
  (plate 385, nine Broadsword finishers); set `warlord`; `defaultSet`.
- **Balance tools:** `tools/sim_range.py` prints the Warlord after the Colossus, with tables
  for the guard, the way through the plates and the siege. `--check` makes 353 checks.

**Rulings after the Stop 3 reports and review (lead, 2026-10-12):**
- Guarded from the first moment (before the call too), or a rifle at the start takes half
  his plate before the guard rises.
- A plate break always reels.
- **The fight was retargeted** after the first balance pass (two minutes, 38 s of it on a
  retreating plate): a reacting melee player wins in 75 to 115 s; the plate phase is at most
  20 s and 60 studs of ground; the siege is 35 to 55% of the fight; every ranged family that
  is not a bow wins inside 150 s. The contract's first 90 to 150 s target is superseded.
- The turns band counts one hit when an attack knocks (ruling 18), so the guard keeps two at
  a time.
- Accepted: a late joiner reads him as guarded until the first unflagged hit; a passive-set
  Warlord would show a ward the server never applies.

**Review outcome, Stop 3:** 0 Critical, 0 Major, 5 Minor, fixed or accepted as above.
- qa-runner: ALL GREEN (2026-10-12). stylua; selene (only the old `LegacyPanel` warning); hub
  and combat luau-lsp with fresh sourcemaps; `check_compile.py` (141 files; highest top-level
  counts FeedbackController 159, CrowdRenderer 151, InputController 144); the hub, combat and
  proving builds; `sim_economy.py --check`, `sim_combat.py --check`, `sim_range.py --check`
  (353 checks). The server's own harness: 492 checks, 203 mutations, none surviving. Asset
  gates not run: no asset or template changed.

**Balance, Stop 3 (`docs/BALANCE.md` "P4" → "Stop 3"; solo, tier 1, from `sim_range.py`):**
- **A player who reacts to every tell takes no hit** and wins in about **77 to 101 s** with
  any melee family, without abilities (target 75 to 115 s).
- **Where the time goes:** the guard 23 to 27 s, his plate 10 to 19 s, the duel 40 to 59 s.
  The siege is 37 to 50% of the fight.
- **Standing still is down in about 9 s** (target: inside 10 s).
- **The chaser gets nowhere:** after 90 s his plate is whole and the guard alive. He is down
  first at about 18 s and 5 to 8 times in the 90 s.
- **No hit over 25% of health:** the guard's swing 28 (22%), his swing 30 (23%), his charge
  30 (23%), one barrage circle 18 (14%). One instant costs at most 30 (23%).
- **Every attack leaves a window of 1.52 to 2.40 s.** The tightest tell leaves a phone thumb
  0.21 s.
- **Ranged:**
  - Quick: Piercing Rifle (about 74 s) and Chain Gun (about 88 s).
  - SMG and Beam have no heavy hit: they break plates with the ground slam and spend long on
    the guard (about 108 s and 146 s).
  - **The bows are slow:** about 2.6 minutes with the Longbow (159 s) and 3.5 with the
    Splitbow (208 s). A weapon question for Ben, as on the Colossus.
- **What is tight** (four targets bind at once; no single value buys room):
  - Melee kill of 75 s or more: the Spear's fastest seed is 77.4 s.
  - Siege of 35% or more: Greataxe 37.0%, Warhammer 37.1%.
  - Ranged that is not a bow, 150 s or less: the Beam's slowest seed is 146.7 s.
  - Plate phase of 20 s or less: the Broadsword's longest is 18.6 s.
- The Colossus's rows moved by 4 s at the most (its fodder rise where the server puts them);
  every Stop 2 band still passes.
- Nothing was tuned in real play. Every number is a starting value.

**Known limits at P4 Stop 3:**
- **Light weapons cannot break plates.** SMG, Beam and Splitbow use the ground slam.
- **He is slow (3 studs a second), in the duel too.** A player who walks away is never caught
  on foot, only by his charge.
- **The duel is gentle on a player who keeps his distance:** every melee family reaches him
  from outside his swing.
- Boss health does not scale with a second player in the range.
- With its ability the Spear wins under the 75 s floor (the band is measured without them).
- The plate is counted in Broadsword finishers: a change to that weapon moves the plate phase
  by a whole finisher (about 2 s).
- Placeholder bodies. No sound. The Stop 1 and Stop 2 limits still apply.
- **Unmeasured, only Ben can:** the server step time with the guard up (budget 2 ms).

**Carried:**
- **To P5 (owner: lead):**
  - **Boss health scaling with party size,** as missions already do (C2).
  - **The bows' time on a boss** (a weapon number; Ben's call first). The Spear and the Beam
    are the two ends of the Warlord's bands, and both are weapon numbers too.
  - **Kiting:** a reason to stay (an objective, a timer), a smaller arena, or an enemy faster
    than the walk.
  - **Flat values against tiered health:** enemy damage, regen, `heavyHit` and now `plate` do
    not scale while health grows ×17 over the tiers (ruling 20; table in BALANCE "What scales
    with weapon tier").
  - Health comes from the profile again (ruling 17).
  - **Server-measured speed:** the melee slack still needs it (from P3.1). The slinger's led
    aim already reads the server's own measure, capped at the fastest legal move.
  - **Cover and the stairs are not in the simulator** (owner of the model: economy-designer).
- **Done in wave 2:** `sim_range.py` has its hopping player (ruling 21).
- **Done in Stop 2:** large bodies in `separate()` (from the groundwork study).
- **Still open from P3, for Ben:** A or B for SMG, Beam and Chain Gun; cross-slot refunds;
  favourite and weakest ability.

**Next:**
- **Ben's Stop 3 playtest** (`docs/PLAYTEST.md` "P4 Stop 3 — The Warlord and his guard"), with
  the server step time read with the guard up.
- **After it P4 is complete.** P5 (back into the missions) starts only on his word.
- **Still open for Ben, besides the P3 questions above:** the Stop 1 `fight` set (shooters,
  brutes, plated elites), never seen; the bows on bosses.

- [x] Wave 1 built and reviewed (INTERFACES "P4 contracts", rulings 1–26)
- [ ] Wave 1 quick look by Ben, **optional**: not reported; covered by Stop 1.
- [x] Wave 2 built and reviewed (INTERFACES "Wave 2 — roles" with its review round)
- [ ] Stop 1 playtest (Ben). Not judged yet: his 2026-10-12 session loaded only `crowd30`.
  The range was changed to open on `fight` that day, and opens on the boss from Stop 2's
  merge; the Stop 2 checklist asks about the fodder and offers `fight` as an optional step.
- [x] Stop 2 built and reviewed (INTERFACES "Stop 2 — the Colossus" with its review round)
- [x] Stop 2 playtest (Ben, 2026-10-12): a six-minute session in the `colossus` set (Studio's
      log), then "Great, on to the Warlord", "Nothing, all clear" on the tells, "About right" on
      the length. No measurement reported. Stop 3 started the same day.
- [x] Stop 3 built and reviewed (INTERFACES "Stop 3 — the Warlord and his guard" with its
  rulings and review)
- [ ] Stop 3 playtest (Ben)

**P4 is complete when the Stop 3 playtest box is ticked.**

## P5 — Back into the missions

**Goal:** the range's combat replaces the old mission combat. Crowd enemies, the 13 weapon
families, abilities and the player's body go into the Expeditions missions, era by era.
**No sound. Phones must work.**
- Plan of record: `docs/COMBAT_DESIGN.md` §9 and §10 step 6.
- Contracts: `docs/INTERFACES.md` "P5 contracts" → "Wave 1 — crowd in a mission" (rulings
  5–28, with "Review round and state" and "Second review round (2026-10-13)").
- Values: `docs/BALANCE.md` "P5".
- Branch `p5-missions`, worktree `C:\Users\benja\Desktop\tycoon-p5`.

**Ben's rulings (2026-10-12):**
1. **Free variant styles in the Armory.** Every owned family offers all its variants; switch in
   the lobby and between waves. (Wave 2.)
2. **One 10-wave skeleton for every era,** scaled per era by config. Colossus = boss of wave 5,
   Warlord and his guard = boss of wave 10.
3. **A teammate standing near revives you,** no button. Solo, the first down ends the run.
   (Revive = Wave 4.)
4. **`proving.rbxl` boots into a mission.** The range stays as a Studio-only bench behind a
   config switch.

**Waves (each ends in a playtest stop):**

| Wave | Scope |
|---|---|
| 1 | Crowd in a mission: Village, solo, the range loadout. **Merged 2026-10-13, second-review fixes merged the same day (bf074f3).** |
| 2 | Loadout and progression: variant styles in the Armory, profile schema v7. |
| 3 | All four eras, both bosses everywhere, reward garnish; old mission code deleted. |
| 4 | Co-op: revive by a teammate, party scaling checked, debug bots as crowd targets. |

**Where it is (2026-10-13):**
- **Wave 1 merged 2026-10-13; the second-review fixes merged the same day (bf074f3), the six place files rebuilt.**
- Wave 1 is on `main` (`7968a24`; the six place files rebuilt in `1bd191e`). Ben chose
  "Merge now"; the same OK covers later P5 waves once they pass review and QA.
- Ben then asked for a review with Opus. It found 2 Major. Every fix is done on
  `p5-missions`; QA is running; not merged yet.
- **The build on `main` today has no wall at the fence:** jumping out ends a solo run. Ben
  waits for the lead's word, then "Build all", before he tests jumping.
- Ben has not reported a look at Wave 1 yet.
- P4's last box (Stop 3, the Warlord) is still open. Wave 1 shows the Warlord at wave 10, so
  Ben meets him here either way.

**Wave 1 shipped (2026-10-12):**
- **What the player meets (`build/proving.rbxl`, Play):**
  - Raider Woods: a grassy 110 × 110 arena with a wooden fence. No range, no panel.
  - Wave 1 starts by itself about 3 s after joining. No Ready button.
  - Fodder rise from the fence in bursts of up to 10.
  - Ten waves on the skeleton: fodder (1–2), slingers (3), brutes (4), the **Colossus** (5),
    marksmen and lobbers (6–7), plated elites (8–9), the **Warlord and his guard** (10).
  - Loadout: Broadsword + Longbow. Health **145** (gear 2/1 baked for Studio).
  - Breathers between waves. No healing but regen.
  - Solo, the first down ends the run. The summary card shows waves, kills, cash, Timber and
    Valor, no Return button, and "Next run in …". About 15 s later a new run starts at wave 1.
  - Rewards are paid to the Studio profile.
  - Studio keys: **B** = next boss wave, **N** = next wave. A corner hint shows them.
  - Phone: the range's touch controls (auto-swing, auto-fire, ability and slot buttons). No
    Attack button.
- **Server:**
  - New `WeaponService.luau`: weapons, projectiles, dash, slam, aim, i-frames and the ability
    hooks, split out of `RangeService`. The range keeps sets, respawns, the panel's commands.
  - New `src/shared/CombatMode.luau`: `"range"` or `"mission"`, decided once at boot, same on
    server and client.
  - New `RunFx.luau`: the run effects (`wave`, `bossDown`, `mentor`), moved from
    `CombatService`.
  - `CrowdService`: mission scales (`SetScales`), `OnKilled` with who did the damage,
    `KillAll`, a `[Perf]` step-time line in Studio's log every 10 s.
  - `VitalsService`: mission rules (health from the Armory, enemy damage scale, regen share, a
    down that never ends by itself, one targeting filter), `StandUp`, `SetGod`, `RunLost`.
  - `WaveService`: crowd waves in bursts, kill rewards per kind, the solo down rule, the proving
    loop, `Skip`.
  - `ArenaService`: arena bounds, spawn points, the character hook, `PartyMember.down`.
  - `DebugService`: levers pointed at the crowd, plus `skip`.
  - `Main`: the new boot. **`EnemyService` and `CombatService` are no longer booted** (still
    in the tree until Wave 3).
  - Weapon damage follows the Armory tier; heavy hits, plates and armour still read the tier-1
    amount.
  - Melee slack uses the server's own position history (carried from P3.1: done).
  - No new remote.
- **Client:**
  - One mode gate (`CombatMode.Get()`) replaces `CameraController.IsRange()` checks.
  - `CombatUIController.bootMission`: the range HUD plus the run layer of `CombatHud`, without
    its old Attack, stance and ability cluster.
  - `VitalsHud`: a "DOWN" banner with no countdown in missions.
  - `SummaryCard`: a `nextRun` option (no Return button, "Next run in …").
- **Config:**
  - `Combat.json`: `crowdSkeleton`; debug keys `provingBoots` "mission", `provingMission`
    "village", `provingStartWave` 1, `provingStartDelay` 3, `provingGear` {2, 1},
    `perfLogSeconds` 10.
  - `Missions/1_Village.json`: a `crowd` block; `targetWaveSeconds` 30 → 45; `targetMinutes`
    8 → 12. The old `enemies`, `waveTable`, `bosses` stay until Wave 3.
  - `ProvingGrounds.json`: unchanged at the first merge. The second review added one key
    (below).
- **Tools:**
  - `sim_range.py`: a MISSION section, 11 more checks (`--mission-only`).
  - `sim_combat.py`: pure mirrors of the crowd functions, assertions 15–18.
  - `tools/crowd_harness/tests_p5.luau`; `mutate.py` extended.
  - `proving_project.py` also bakes `DebugMission`.

**Review outcome, Wave 1:** 0 Critical, 1 Major, 5 Minor.
- **Major, fixed:** a run could hang up to 1,200 s when a downed player's partner left or
  died. The run's end is now judged from state every frame (`VitalsService.RunLost`, called by
  `WaveService.endIfLost`).
- Minors:
  - Fixed: the proving summary card had a dead Return button (now `SummaryCard` `nextRun`).
  - Fixed: warn spam from the start and skip levers, and a lost reward pool on that path.
  - Fixed: the pellet seed is a fresh server-side draw per shot.
  - Fixed: dead `SetArena` state removed (a no-op stub stays; `WaveService` calls it).
  - Accepted as design: after a boss wave the breather is always the longest, 14 s
    (`breatherMaxSeconds`).
- qa-runner: ALL GREEN (2026-10-12). stylua; selene; hub and combat luau-lsp; `check_compile.py`;
  the hub, combat and proving builds; `sim_economy.py --check` (unchanged), `sim_combat.py
  --check` (18 assertions), `sim_range.py --check`; the server's own harness 546 checks,
  `mutate.py` 221 mutations, none surviving.
- Skipped: `streetplan.py` and `check_mirror.py` (Pillow is not installed). Wave 1 touches no
  city file.

**Second review (Opus), 2026-10-13** (INTERFACES "Second review round (2026-10-13)"):
- Asked for by Ben after the merge. Three independent Opus reviewers read the merged code in
  three slices: weapons and damage; the mission run; the client.
- **0 Critical, 2 Major, 22 Minor.** Fixed by the same four owners.
- An independent check of the fix diff: **1 more Major (in a fix), 11 Minor.** Fixed too.
- **Major 1, fixed twice over: leaving the floor ended a solo run.** The Village fence is 4
  studs; a jump, double jump and dash clear it; nothing lies outside the floor.
  - An invisible wall behind each fence side, 80 studs high and 8 deep (`wall.barrierHeight`,
    `wall.barrierThickness`). Only characters collide with it (collision groups
    `ArenaBarrier` and `ArenaPlayers`); camera and shot rays pass through.
  - A rescue: a player 8 studs under the floor or 4 past its edge is put back on a spawn
    with the get-up i-frames (`player.rescue.below`, `player.rescue.outside`). Not a down, no
    cost.
  - The fix check's Major was in this wall: its first version used `CanQuery = false`, which
    the engine ignores on a collidable part. The camera would have snapped in along the rim
    and shots stopped in mid-air.
- **Major 2, fixed: small landscape phones (about 667 × 375 and below).** The boss bar landed
  on the crosshair and the hurt pointers collapsed onto the dot.
  - The mission's boss bar sits in the top strip between the run header and the party list,
    down to 140 px wide. Narrower still, it goes under the header, clear of the crosshair.
  - The pointer ring keeps under the bar only while a boss exists, and never shrinks under a
    radius of 48 px.
- **Other changes that shipped with the fixes:**
  - Melee and aim slack: the server reads the fastest 0.1 s stretch of the last 0.3 s from a
    ring of root positions (new `PositionRing.luau`, new key `shooting.originSpeedSeconds`).
    A dash reads its full 133 studs/s by its seventh server frame; the first version never
    did. Cost accepted by the lead: one legal dash buys 40 + 4 studs of slack at the lag
    ceiling (before 20 + 4), 17 at an honest 50 ms.
  - **A clear field wins:** a down decided when the wave's last body is already dead does not
    end the run. The player stands up at that boundary; on wave 10 the run ends "cleared".
  - A wave clear removes what the dead still had in the air (server and client).
  - A run starts only once every human member has a living body.
  - Downed players stand up before a cleared end, when the proving loop resets, and on a
    rejoin.
  - A crowd kind the config does not know is dropped with one warn, instead of holding the
    queue until the run cap.
  - `director.runCapSeconds` 1200 → **1800** (2.5 × the 12-minute target). A tier-1 Longbow
    clear takes 19.2–20.0 min and was being cut off in wave 10.
  - Client: the down follows the server's `PartyMember.down` both ways; no attacks, casts or
    slot switch while waiting on the pad; on touch, Return is hidden while you fight; the
    crowd pool is pre-warmed to the mission's own `maxAlive`; the HUD boot no longer depends
    on a layout pass.
- **Gates, as reported by the engineers** (QA still running when written): the harness 574
  checks; `mutate.py` 231 mutations, 0 not caught; `sim_range.py --check` 363 passes;
  `sim_combat.py --check` 18 assertions (17 now also needs the run cap to be at least twice
  `targetMinutes`).
- **Checked by reading only** (no test can load them): all of `WaveService`, `ArenaService`,
  `Main`, and every client file.
- **Needs Studio (Ben):** the wall's behaviour, the camera at the rim, the rescue teleport.
  PLAYTEST "P5 Wave 1" step 2; MANUAL_STEPS "P5 Wave 1" step 6 (optional).

**Balance, Wave 1 (`docs/BALANCE.md` "P5"; gear 2/1, solo, Broadsword, from `sim_range.py`):**
- **A run pays 144,250 cash (+1.5%), 258 Timber (+0.8%) and 35 Valor.** Target 142,185 / 256 /
  35.
- **A reacting player clears all ten waves in 11.5 to 11.8 min** (target 10–15).
- **The Colossus alone: 76.8 s. The Warlord alone: 97.7 s.** Both as in the range. No hit taken.
- **Standing still in wave 1: down at 10.6 to 10.8 s** (target 6–12).
- **No hit over 25%:** the worst is the Colossus's charge, 36 of 145 (24.8%).
- Mission scales: `hpScale` 1.5, `plateScale` 1, `damageScale` 1.12, `regenShare` 0.077,
  `maxAlive` 60, `burst` 10.
- A player who never dodges is down in wave 5.
- Nothing was tuned in real play. Every number is a starting value.

**Known limits at Wave 1:**
- **The Longbow is weaker in missions.** Bodies have 1.5× HP and the bow is still tier 1: the
  Longbow alone takes 276 s on the Colossus and 227 s on the Warlord. A bow-only run takes
  19.2–20.0 min (it now finishes: the run cap is 1,800 s).
- **After a boss wave the breather is always the longest, 14 s.**
- **No wall outside Village.** The other three arenas have no `barrierHeight` yet (they are
  refused anyway until Wave 3).
- **Cash per minute is down about a quarter:** 144k in about 12 min, against the old run's 142k
  in 8.5 min.
- **Co-op is unchecked.** A party of 4 makes wave 9 hold 354 bodies; `maxAlive` 60 queues them.
- **Two humans in Studio:** a downed player stands up at the next wave boundary. A stand-in
  until the Wave 4 revive.
- **Debug bots do nothing in missions** (the lever warns once).
- No per-kill cash pops (Wave 3). No sound. Placeholder bodies.
- The crowd walks through boulders and fence posts. The keepAway bands span most of a
  110-stud floor. Kiting still avoids most hits.
- **Boomtown, Metropolis and Orbital missions are refused** ("locked"): they have no `crowd`
  block until Wave 3.
- **Unmeasured:** the `[Perf]` step time in real play (budget p95 under 2 ms in waves 1–4). The
  lead reads it from Studio's log after Ben's session.

**Carried:**
- **Publish freeze (owner: lead):** do not publish the Expeditions place from `main` until
  Wave 3 is merged. Until then it plays only Village.
- **To Wave 2 (owner: lead; luau-engineer, ui-engineer):** loadout and variant styles in the
  lobby and between waves; profile schema v7 (`combat.loadout`); the cooldown carried across a
  family switch.
- **To Wave 3 (owner: lead; economy-designer for the numbers):**
  - `crowd` blocks for Boomtown, Metropolis and Orbital; lift the publish freeze.
  - Per-kill cash pops and big-kill callouts.
  - Delete `EnemyService`, `CombatService`, the four old remotes, the C1 mission client paths,
    the old mission JSON blocks and `director.maxAlive`.
  - Era tuning of the mission scales; Overdrive numbers.
- **To Wave 4 (owner: lead; luau-engineer, ui-engineer, economy-designer):**
  - Revive by a teammate standing near (replaces the wave-boundary stand-up).
  - Party scaling checked in play (party of 4: wave 9 = 354 bodies, `maxAlive` 60).
  - Debug bots as crowd targets, or retired.
  - A two-account published round trip.
- **From the second review (2026-10-13):**
  - **BEFORE THE PUBLISH FREEZE LIFTS (Wave 3), owner: luau-engineer.** `OnDash` grants
    i-frames on the request alone. A modified client that requests a dash every 0.64 s
    without moving voids about 56% of enemy hits at 60 ms ping, and about 86% at the 0.3 s
    lag ceiling. Fix: judge the dash against the position ring at hit time.
  - **Wave 3, owner: lead + economy-designer.** The Boomtown, Metropolis and Orbital arenas
    have 5-stud fences and no `barrierHeight`. There the free rescue could be repeated every
    1.5 s for near-permanent i-frames. Each era needs `barrierHeight` (gate: a `crowd` block
    implies `barrierHeight`) or a rescue cooldown before it gets crowd waves.
  - **Wave 3, owner: economy-designer:**
    - One run cap serves all four eras: keep targets near 12 minutes, or make the cap per
      mission.
    - Mag Dump scales by `damageMult` while the other abilities scale by `abilityMult`
      (×6.0 against ×2.8 at Ascension 3).
    - The breather after a boss wave is always the 14 s maximum.
    - A dropped boss (unknown kind) counts as a clear.
  - **Wave 4, owner: luau-engineer:**
    - No timeout on the wait for a member's body before a run starts.
    - Breaking a plate earns no reward share.
    - The bot functions in `ArenaService`.
  - **Any wave, owner: luau-engineer:**
    - The Studio `setGear` lever is inert in a proving mission (`provingGear` wins).
    - A same-wave `ForceWave` leaves the client's circles.
  - **Owner: ui-engineer:**
    - The portrait lobby overlap (phones are landscape-only).
    - The boss bar's end near a hurt pointer at 568 × 320.
    - The C1 fallback `boot()` is dead; delete it in Wave 3.
- **Weapon numbers (owner: lead, Ben's call first):** the Longbow in missions and the bows on
  bosses; cash per minute down a quarter.
- **Still unjudged by Ben (owner: lead):** the Warlord (P4 Stop 3) and the `fight` set. Wave 1
  shows both enemies' kinds in waves 3–10.
- **Still open from P3, for Ben:** A or B for SMG, Beam and Chain Gun; cross-slot refunds;
  favourite and weakest ability.
- **Unscheduled (owner: lead):** melee abilities still resolve at the server's position; early
  drawing of own shots and ability visuals; refunds against chasing crowds; cover and stairs
  not in the simulator (economy-designer); kiting.

**Next:**
1. QA finishes on the second-review fixes.
2. The lead merges `p5-missions` to `main` and rebuilds the six place files.
3. **Ben's Wave 1 playtest** (`docs/PLAYTEST.md` "P5 Wave 1 — Crowd in a mission"; setup in
   `docs/MANUAL_STEPS.md` "P5 Wave 1"). Not before step 2: the wall is in that build.
4. The lead reads the `[Perf]` lines from Studio's log.
5. Wave 2 only on Ben's word.

- [x] Wave 1 built and reviewed (INTERFACES "Wave 1 — crowd in a mission" with its review round)
- [x] Second review (Opus): fixes built on `p5-missions` (INTERFACES "Second review round
  (2026-10-13)")
- [x] Wave 1 merged to `main` (lead): Wave 1 merged 2026-10-13; second-review fixes merged the same day (bf074f3).
- [ ] Wave 1 playtest (Ben)
- [ ] Wave 2 — loadout and progression
- [ ] Wave 3 — all four eras
- [ ] Wave 4 — co-op

## M12 — Growing city

**Goal:** the city should feel "alive and like a growing city, not a grid being filled" (Ben,
2026-09-28). The 24 slots stay the landmarks; around them the client grows a town by itself.
Core gameplay is untouched.
- Plan of record: `docs/CITY_GROWTH.md` (approved 2026-09-29).
- Contracts: `docs/INTERFACES.md` "M12 contracts" (wave 1 through round 3 and every review
  ruling), "M12 wave 2 — Boomtown", "M12 wave 3 — Metropolis" and "M12 wave 4 — Orbital
  Colony".
- Memory: `.claude/memory/growing-city-2026-09-28.md`, and in the same folder
  `boomtown-growth-2026-10-01.md`, `metropolis-growth-2026-10-02.md` and
  `orbital-growth-2026-10-05.md`.
- Where:
  - Wave 1 (Village) is on `main` (`e5df035`). Its branch `m12-growing-city` and its worktree
    were merged and removed on 2026-10-01.
  - Wave 2 (Boomtown) is on `main` too, merged on 2026-10-02 (merge commit `86d1d99`). Its worktree
    and branch are removed. See "Wave 2 — Boomtown" below.
  - Wave 3 (Metropolis) is on `main` too, merged on 2026-10-05 (a fast-forward to `d0dd894`).
    Its branch `m12-metropolis` is deleted and its worktrees are removed. See "Wave 3 —
    Metropolis" below.
  - Wave 4 (Orbital Colony) is on `main` too, merged on 2026-10-06 (a fast-forward to
    `c01ccfd`). Its branch `m12-orbital` is deleted and its worktree `tycoon-m12o` is removed.
    See "Wave 4 — Orbital Colony" below.
  - **M12 is complete:** all four eras are in the main checkout, `C:\Users\benja\Desktop\tycoon`.
  - (M11 is the unmerged feature-unlocks milestone on branch `m11-unlocks`.)

**Rulings (Ben):**
1. 2026-09-29: growth layouts (mock B), with an **organic street plan** for Village.
2. One era per wave, Village first. Each era gets its own layout mock before contracts.
3. First look: "waaay more houses filling the terrain". Village needs ≥ 100 lots in rows, and
   `treeOak` becomes **Plant Trees**.
4. Round 2: the density is "perfecto"; narrow terraced lots with alleys between them are fine.
5. Round 3: `flowerBed` becomes **Plant Flowers** and `bannerPole` becomes **Hang Banners**.

**Shipped (wave 1, Village, 2026-09-29 → 2026-10-01, commits `495c529` … `e747ebb`):**
- **Client-only.** No server, remote, profile, economy or balance change. Slots, order, prices,
  income and levels are unchanged.
- **New organic Village layout** (`src/shared/Layouts/Village.luau`):
  - a curving high street from the campsite at the entrance up to the Castle Keep;
  - a square halfway along it, and lanes at angles;
  - a district tag per slot (camp, home, craft, farm, market, civic).
  - Village dropped its old `lots`, `treeZones`, `greeneryZones` and `parking`.
- **City fabric:**
  - `src/shared/CityFabric.luau` (pure): pull along the drawn streets, level, governor and
    district per lot.
  - `src/client/City/Fabric.luau`: the renderer, hooked into `CityDressingController`,
    `RoadGraph.FabricNetwork`, walk solids and birds.
  - Data: `src/shared/Config/Fabric/Village.json`, generated.
- **116 lots** in three sizes: small 6×6, medium 8×8, narrow 4×6 terraced. They go in rows 1–3,
  and each develops wild land → building site → house that grows.
- **Wild land:** 109 woods entries (clumps, quarters, single trees, rocks), plus a landscape
  skirt past the plot edge. The woods recede as the town spreads.
- **Construction ripple:**
  - a reveal scaffold on each purchase;
  - building sites that ripple out from it;
  - houses rising 10–30 s later, and stage pops on growth.
  - Dust puffs, at most 4 at once per plot.
- **Next-pad dressing:** a notice board, stakes and string around the footprint, and a dirt-coloured
  pad.
- **Three city-changer slots** (`streetOnly`; cost, income and `requires` unchanged). Each runs a
  planting wave when bought:

  | Slot | # in order | At full build |
  |---|---|---|
  | Plant Flowers (`flowerBed`) | 8 | 43 flower beds and planters |
  | Plant Trees (`treeOak`) | 14 | 65 trees (sapling → young at tier 4 → full at tier 5) |
  | Hang Banners (`bannerPole`) | 20 | 16 banners and bunting |
- **Config:**
  - `CityDressing.json` v4 gains the Village `fabric` block, with `upgrades` for the three layers
    and `construction.spawnsPerFrame` 40.
  - Budgets: `parcels` 140 near, `parcelsFar` 60, `wild` 110 near, `wildFar` 45.
  - `Config/Eras/1_Village.json`: the three slots renamed and made `streetOnly`.
- **Models:**
  - 43 new prop blueprints in `tools/testfit/blueprints/_props/Village/`: homes, camp, craft,
    farm, market, civic, sites, reveal scaffold, notice board, woods, town trees, flowers and
    banners.
  - A generated `village-extras-kit` (`tools/assets/village_extras_kit.py`).
  - 82 prop stages uploaded.
- **Paths re-baked** for the new layout: 47 pieces (was 58), 94 meshes uploaded, 15 retired piece
  ids removed.
- **One harvest paste, 2026-10-01:** 82 prop stages and 94 path meshes. Templates: 43 props, 47
  paths.
- **Tools:**
  - `py tools/fabric.py build|check Village` generates and checks the fabric data.
  - `py tools/cityfabric.py selftest|timeline Village` is the Python mirror.
  - `tools/testfit/plotrender.py` draws the fabric, and its pad bug is fixed.
  - `tools/streetplan.py` checks fabric eras.

**Timeline** (`py tools/cityfabric.py timeline Village`, the sim's greedy player at the end of each
tier):

| Tier | Houses | Sites | Trees | Flowers | Banners |
|---|---|---|---|---|---|
| 1 | 0 | 8 | 0 | 0 | 0 |
| 2 | 20 | 1 | 0 | 15 | 0 |
| 3 | 21 | 20 | 33 | 17 | 0 |
| 4 | 54 | 10 | 44 | 30 | 16 |
| full | 116 | 0 | 65 | 43 | 16 |

**Rounds driven by Ben's feedback:**
1. **Wave 1 (1a + 1b):** contracts, layout, fabric, client and mirror, with ≥ 40 lots. Ben liked
   the gate renders but wanted far more houses.
2. **Wave 1c:** rows 1–3, town trees and Plant Trees. Only 32 houses fitted, because street
   frontage was the bottleneck.
3. **Round 2:**
   - narrow terraced lots, block infill and landmark clearance measured from harvested extents
     gave 97 houses;
   - re-pacing (`rowLag` 0, `tierTerm` 0.16) gave 109, with building sites at every tier.
4. **Round 3:** generic upgrade layers (trees, flowers, banners); Plant Flowers and Hang
   Banners; 116 houses.

**Review rulings (all applied; the text is in INTERFACES):**
- **Wave 1:**
  - a bulk change is a restore (no animation);
  - config validated once;
  - the puff cap;
  - the clearing mask follows ownership;
  - `marker.offset` is in the slot frame.
- **Wave 1c:**
  - growth steps are staggered;
  - street-only slots are not walk solids;
  - stricter row and `tierOffset` validation.
- **Rounds 2–3:** unanimated spawns go through a per-frame queue (`spawnsPerFrame`, nearest plot
  first).

**Status (wave 1):** merged to `main` on 2026-10-01. Ben's verdict in Studio: "the village looks
amazing". Still owed: Ben's numbers from PLAYTEST M12 step 37 (box 5 under "Wave 2 — Boomtown").

**Known follow-ups (wave 1):**
- **economy-designer:** `FlowerBorderA` is built and uploaded but never placed, because every lane
  corner is taken. Place it or drop it after the playtest.
- **economy-designer:** the house count jumps between tier 4 (54) and full (116), because the last
  four landmarks open the back streets. This is a layout matter, not config; only change it if
  Ben notices.
- **lead:** far plots show bare cleared patches where lots past `parcelsFar` (60) developed. Tune
  `parcelsFar` after Ben's Studio measurement.
- **lead → ui-engineer:** the `TreeOak`, `FlowerBed` and `BannerPole` meshes are still preloaded
  but never spawned (those slots are street-only now). Drop them from `AssetPreloader`.
- **Done (merge, 2026-10-01):** the shared `assets/build/paths/Village.json` holds the M12 bake,
  and `main` now has the M12 layout, so `py tools/paths/bake.py --era Village --list` is green
  again.
- **Ben → lead (open):** the budget baseline. Ben reports the instance count and frame time on a
  full Village with neighbours (PLAYTEST M12 step 37); the lead re-cuts the caps from those
  numbers.
- **Done (wave 2.0, 2026-10-01):** Village had lost its chimney smoke, parked carts, bushes and
  hedges. Smoke and carts are back (see "Wave 2 — Boomtown" below). Bushes and hedges do not come
  back as a layer (lead's call): Plant Flowers and the houses' own gardens carry the greenery.

- [x] Wave 1 (Village) built, review rulings applied, assets harvested and templated (2026-10-01)
- [x] Ben's Studio look at Village, 2026-10-01: "the village looks amazing"
- [x] lead: merged `m12-growing-city` into `main` (2026-10-01); branch and worktree removed
- The step 37 numbers are still owed; the open box is under "Wave 2 — Boomtown" (box 5).

### Wave 2 — Boomtown (2026-10-01 → 2026-10-02; signed off and merged to `main` 2026-10-02)

**Where:**
- **The work lives on `main`**, in the main checkout `C:\Users\benja\Desktop\tycoon` (`main` at
  `86d1d99`, which also holds M13 Valley, the P3 load fix and the compile gate).
- **The worktrees are gone:** `tycoon-m12`, `tycoon-m12-grid` and `tycoon-m12-organic` are removed,
  and the branch `m12-boomtown` is deleted. The last commit of the wave on that branch was
  `a78b4f1`, plus the docs commit `2f9fbc2`.
- **Kept as the record of the two layout candidates:** the branches `m12-boomtown-organic`
  (**chosen**; first candidate `0fd20be`, bolder pass `c58136f`, whose layout file was copied in
  by `4ebe5f1`) and `m12-boomtown-grid` (not chosen, `452059d`).
- Contract: `docs/INTERFACES.md` "M12 wave 2 — Boomtown", with "Wave 2.2" and its two rulings
  blocks, "Wave 2.4 — back lanes" with its rulings, and "Wave 2.5 — baked lanes" with its two
  rulings blocks.

**Status (2026-10-02): signed off by Ben and merged to `main`.**
- **Ben's sign-off:** "looks really good! lets send it", after re-checking the baked lanes.
- **What the sign-off was:** a look in Studio at the lanes and the town. It was **not** a report
  of the 60-step checklist. Not reported, and open as watch items: the phone at 375×667, low
  graphics, two players, and the measurement.
- **Still owed by Ben:** the step-37 numbers (and the same on Boomtown). He has not sent them.
- Boomtown is tested on `build/boomtown.rbxl` (a fresh save starts in era 2, with 100T cash).
  **That file is for local Studio use only and must never be published.**
- `py tools/paths/bake.py --list` exits 0 for both eras.
- The numbers in the wave 2.0, 2.1 and 2.2/2.3 blocks below are the record of each gate. **Today's
  numbers are in the wave 2.4 block**; wave 2.5 did not change them.

**Shipped to playtest (wave 2.0 — Village chimney smoke and parked carts, 2026-10-01):**
- **Client-only.** No server, remote, profile or economy change. No new assets, no upload, no
  harvest paste.
- **Parked carts** are one more upgrade layer (`fabric.upgrades.carts`), switched on by owning
  the Farm Plot (purchase 4). No new client code.
  - 8 at full build: 3 beside lanes, 5 beside farm, market and craft lots. Drawn at scale 0.85 to
    0.95.
  - By tier (the sim's player): 0 / 2 / 2 / 4 / 8.
  - A lane cart appears when its lane is drawn; a yard cart rises with its building.
  - City detail off thins them to half, like every layer (the wave 2c carts were dropped
    entirely).
- **Chimney smoke** on every fabric house whose shown stage has a chimney
  (`ambient.smoke.fabricProps`, `ambient.smoke.every` 1).
  - With the models as uploaded, most homes only gain a chimney at their last stage.
  - Full Village: **13 plumes** = 11 houses + the two camp fire pits by the Watchtower.
  - The 11 house plumes need the **Village Well at its 4th growth stage (level 50)**, because the
    Well's height caps the houses around it. The sim's player gets there at tier 5, so its
    timeline shows 0 plumes at tiers 1–4 and 13 at tier 5.
  - A plume is placed when its house has finished rising or popping (the rise takes about 0.6 s).
  - None on far plots, with City detail off, or at graphics quality ≤ 3. Phones keep them.
  - **Superseded from `d3d6427` (wave 2.2):** `every` is 7 and the narrow homes get chimneys. The
    counts above describe commit `a6cf170`. See "Village chimneys" under waves 2.2 and 2.3.
- **Mirror and renders:**
  - `tools/cityfabric.py` returns the plume positions, and `timeline` prints the plumes per tier.
  - `tools/testfit/plotrender.py` draws each plume as a row of pale spheres (a marker, not the
    look of the particle effect).
  - Before and after: `assets/testfit/out/Village/m12f_{before,after}_{full,close}.png` and
    `m12f_after_tier3.png`.
- **Renderer colour fix** (`tools/testfit/plotscene.py`): scene colours are now decoded from sRGB
  once.
  - Until 2026-10-01 flat colours (plot base, roads, pads) rendered much paler than the game:
    Boomtown's base (173, 138, 93) came out about (214, 198, 171).
  - **Every plot render made before 2026-10-01 shows paler ground than Studio, for every era.**
    Kit models were always right.
- **Commits on `m12-boomtown`:** `1fb2a46`, `7c6e49f`, `60a5e6a`, `6573b0c`, `80bfb78`, `9b72d92`,
  `a6cf170`, `04232de`, `5bd4227` (waves 2.0 and 2.1 together).

**Review (wave 2.0): 0 Critical, 1 Major, 5 Minor.** All Minors fixed (`a6cf170`). The Major is the
branch caveat above, accepted. Rulings (text in INTERFACES):
- the plume follows the stage that actually stands;
- carts: at least 6 (`require.carts`), within the layer budget of 12;
- `budget.plumes` 20 is a tools-only gate (`py tools/cityfabric.py timeline <Era>` fails above
  it), so any chimney change retunes `ambient.smoke.every` in the same commit;
- `ambient` is type-guarded wherever it is read.

**QA (wave 2.0): all green.**
- stylua, selene, both rojo builds, gen_templates, `fabric.py check`, `cityfabric.py selftest` and
  `timeline`, streetplan for all four eras, and the Village path gate.
- sim_economy, all four eras in band: 41:50, 1:44:15, 4:28:49, 9:25:10.
- luau-lsp is clean when the hub is analysed against the hub sourcemap and `src/combat` against a
  `combat.project.json` sourcemap. Analysing all of `src` against the hub sourcemap reports
  unresolved combat requires; that is a sourcemap-scope artefact.

**Gate answered (wave 2.1 — Boomtown growth-layout mock, 2026-10-01).** Ben chose from the renders:
1. **Organic**, with the bolder pass.
2. **All four** city-changer candidates "stop being a sole building".
3. Roads **stay 6 studs** wide.
4. **Yes** to chimneys on the three narrow Village homes.
5. His step-37 numbers are still owed.

What the mock was (kept as the record):
- **Draft props:** 27 blueprints in `tools/testfit/blueprints/_props/Boomtown/`, not uploaded.
  - A generated `farmland-kit` (`tools/assets/farmland_kit.py`): crop fields in three kinds as
    fabric clumps and quarters, hay bale, prairie tree, telegraph pole, windbreak, farmstead with
    barn and silo, wind pump.
  - A generated `boomtown-extras-kit` (`tools/assets/boomtown_extras_kit.py`): building sites in
    three sizes, three Main Street shops, four small homes, two medium homes, an industrial works,
    a "lot for sale" sign, a reveal scaffold.
- **Generator:** `tools/fabric.py` lays crop fields on a grid (`wild.pattern: "fields"`). Base plan:
  `tools/fabric/Boomtown.plan.json`.
- **Sizes:** small 6 × 6, medium 8 × 8, narrow 5 × 8 (terraced shops). Road width 6.
- **Finding:** with 8-stud roads and 9 × 9 house lots, a plot only held 55 to 70 lots.
- **Two candidates**, each with every gate green in its own worktree:

  | | Grid | Organic |
  |---|---|---|
  | Streets | Main Street straight on the entrance axis to the Clock Tower; three cross streets (First, Second, Third); every arm a dead end | Main Street leaning 12° between two crossroads; an old farm road and a Second Street that each jog one lot row; a service road curling to the front-east corner; one curving close (Radio Lane) |
  | Lots | 93 | 101 |
  | Narrow shops / small / medium | 28 / 62 / 3 | 15 / 82 / 4 |
  | Houses at tiers 1 / 2 / 3 / 4 / full | 0 / 25 / 45 / 59 / 93 | 8 / 27 / 53 / 88 / 101 |
  | Sites at tiers 1 / 2 / 3 / 4 / full | 3 / 8 / 7 / 11 / 0 | 4 / 18 / 10 / 10 / 0 |

- **Organic's constraint:** landmarks stay square to the compass, because the next-lot marker's
  offset only clears a pad within 3.5° of an axis. So it reads as a kinked grid. A bolder organic
  plan needs `fabric.marker.offset` raised (5.3 allows any angle).
- **Gate renders** in `assets/testfit/out/Boomtown/`:
  - `m12b_compare.png`: today, grid and organic at tier 1, tier 3 and full;
  - `m12b_grid_{tier1,tier3,full,full_entrance,streetplan}.png`;
  - `m12b_organic_{tier1,tier3,full,full_entrance,streetplan}.png`;
  - `m12b_today_{tier1,tier3,full}.png`;
  - prop drafts: `farmland_context.png`, `construction_context.png`,
    `construction_suburb_context.png`, `construction_scale_check.png`.
- **Known weak points of both candidates** (for wave 2.2):
  - landmark driveways are road-wide asphalt stubs (a narrower driveway needs a client and a bake
    change);
  - the industrial lots at the front are rows of identical dark sheds (stand-ins);
  - no civic green by the Clock Tower;
  - shop side walls are blank.

**Second render gate passed (waves 2.2 and 2.3, 2026-10-01, commits `20df3ed` … `d119ad2`).**
Ben: "it seems good ... i love everything else", with one request: the houses were not connected
to any road. That became wave 2.4. The lot, layer and plume numbers in this block are the ones
shown at that gate (102 lots); wave 2.4 changed them.
- **Client-only again.** No server, remote or profile change. The economy is unchanged:
  `sim_economy.py` total 16:20:04, legacy 887.
- **Four more city-changer slots** (`Config/Eras/2_Boomtown.json`). All are `streetOnly`; cost,
  income, multiplier, order and `requires` are unchanged.

  | Slot | # in order | Name | At full build |
  |---|---|---|---|
  | `fireHydrant` | 8 | Install Fire Hydrants | 22 hydrants along the streets |
  | `busLine` | 17 | Open the Bus Line | 4 bus shelters on 3 streets; buses in the traffic |
  | `billboardSign` | 20 | Put Up Billboards | 10 billboards (two large ones behind shop rows) |
  | `neonDistrict` | 23 | Light the Neon District | 26 neon pieces: a sign on each of the 23 shop lots, 3 arches |

- **Parked cars** are a fifth layer, switched on by the Gas Station (purchase 4): 14 at full build.
- **Buses:** about 15% of the traffic once the Bus Line is owned, and at least one
  (`vehicles.unlocks`, prop `VehicleBus`).
- **Driveways are 3 studs wide** (`road.paths.spurWidth`). Cars keep to the streets.
- **Layout** (`src/shared/Layouts/Boomtown.luau`, the bolder organic pass):
  - Main Street leans 16° between two crossroads and ends at the Clock Tower;
  - an old farm road; Second Street as the second shop street; a service road to the back-east
    for industry;
  - a civic green (`PlazaA`) at the tower's foot;
  - landmarks face their streets (`fabric.marker.offset` 5.3 allows any angle);
  - 17 building landmarks, 3 street upgrades, 4 city-changers.
- **Fewer by layout:** Streetlamp Row gives 8 lamps and Install Traffic Lights 2 signals (the plan
  has two crossroads).
- **Fabric** (`src/shared/Config/Fabric/Boomtown.json`, generated): **102 lots** = 23 terraced
  shops, 74 small homes, 5 medium. Wild land: 85 crop fields and pastures (73 on the plot, 12 past
  its edge) and 21 single items.
- **Timeline** (`py tools/cityfabric.py timeline Boomtown`, the sim's player at the end of each
  tier):

  | Tier | Houses | Sites | Plumes | Parked cars | Hydrants | Bus shelters | Billboards | Neon |
  |---|---|---|---|---|---|---|---|---|
  | 1 | 11 | 4 | 0 | 1 | 0 | 0 | 0 | 0 |
  | 2 | 36 | 20 | 5 | 3 | 15 | 0 | 0 | 0 |
  | 3 | 66 | 15 | 7 | 12 | 18 | 0 | 0 | 0 |
  | 4 | 89 | 9 | 11 | 13 | 21 | 4 | 0 | 0 |
  | full | 102 | 0 | 12 | 14 | 22 | 4 | 10 | 26 |

  The plume cap (`budget.plumes`) is 20.
- **Village chimneys:** the three narrow homes have a chimney from their first stage, and
  `ambient.smoke.every` is 7.
  - Plumes by tier: 0 / 2 / 2 / 9 / 16, all on narrow homes.
  - The two camp fire pits are no longer smoke candidates at `every` 7 (parcels 25 and 69).
    **lead:** confirm this is intended.
- **Props (wave 2.3; uploaded and harvested 2026-10-02):**
  - 46 Boomtown blueprints (71 stages) in `tools/testfit/blueprints/_props/Boomtown/`, plus the 3
    changed Village homes (9 stages);
  - generated kits: `farmland-kit`, `boomtown-extras-kit`, `boomtown-street-kit` (scripts in
    `tools/assets/`);
  - strips: `assets/testfit/out/Boomtown/strips/` (46 strips and `street_context.png`);
  - context shots in `assets/testfit/out/Boomtown/`: `construction_context.png`,
    `construction_suburb_context.png`, `construction_scale_check.png`, `farmland_context.png`,
    `farmland_civic_context.png`;
  - Village: `assets/testfit/out/Village/m12g_narrow_chimneys.png`.
- **Gate renders** in `assets/testfit/out/Boomtown/`:
  - `m12c_compare.png`: today against the new layout at tier 1, tier 3 and full;
  - `m12c_{tier1,tier3,full,full_entrance}.png`;
  - `m12c_changers_{before,after}.png`;
  - `m12c_streetplan.png`.

**Review (wave 2.2): 0 Critical, 1 Major, 10 Minor.** All fixed or ruled (`367faed`, `d119ad2`;
text in INTERFACES "Review rulings").
- **Major, fixed:** a bus rode into the car ahead. Lane holds now count both vehicles' lengths.
- A layer placer that lays nothing, or a layer prop nothing uses, fails `fabric.py check`.
- The large billboard now stands behind the shop rows, and rises with its lot.
- Bus picks read the sticky owned set; the preloader loads only what an era can spawn.

**QA (wave 2.2): all green.**
- At that gate `py tools/paths/bake.py --era Boomtown --list` exited **2** (client and bake agreed
  on 38 pieces; the meshes on disk were stale). It exits 0 since the re-bake.
- `py tools/cityfabric.py timeline` passes for Village and Boomtown; `py tools/gen_asset_manifest.py
  --check` passes.

**Shipped to playtest (wave 2.4 — back lanes, the asset run and the start-era switch, 2026-10-01
→ 2026-10-02, commits `241b36e` … `e109635`):**
- **Client-only again**, apart from one Studio-only lever in `DataService` (below).
- **Back lanes:** 8 lanes, 330 studs in all, each 3 studs wide. Every back lot fronts a lane, and
  47 of the lots are lane lots.
  - A lane leaves a street through a gap in the frontage. Two pairs of lanes meet end to end.
  - It is drawn on the plot's live street surface, so it changes with the streets.
  - **A lane arrives whole** in one purchase, then fills with houses from the street inward.
    Since wave 2.5 that is the contract: a lane is one baked piece.
- **75 lots** (was 102): 22 terraced shops, 50 small homes, 3 medium. Ben accepted this on the
  render: "the houses look fantastic!".
- **`pull` re-tuned** for the lane distances: radius 120, `tierTerm` 0.35, thresholds
  [2.2, 3.4, 3.8, 4.3].
- **Timeline** (`py tools/cityfabric.py timeline Boomtown`, the sim's player at the end of each
  tier):

  | Tier | Houses | Sites | Lanes | Plumes | Parked cars | Hydrants | Bus shelters | Billboards | Neon |
  |---|---|---|---|---|---|---|---|---|---|
  | 1 | 4 | 2 | 0 | 0 | 1 | 0 | 0 | 0 | 0 |
  | 2 | 31 | 4 | 2 | 5 | 6 | 14 | 0 | 0 | 0 |
  | 3 | 46 | 17 | 7 | 6 | 12 | 17 | 0 | 0 | 0 |
  | 4 | 65 | 9 | 8 | 7 | 14 | 20 | 4 | 0 | 0 |
  | full | 75 | 0 | 8 | 7 | 14 | 21 | 4 | 12 | 25 |

  Bus shelters stand on two streets. 4 of the 12 billboards are large. Neon is 22 signs and 3
  arches.
- **For a player buying in Build panel order:** the first lane comes with the Barber Shop
  (purchase 7), and all 8 are drawn by the Bowling Alley (purchase 16).
- **Village plumes by tier:** 0 / 2 / 2 / 9 / 16, on real chimneys since the harvest.
- **The asset run (done):**
  - kits regenerated;
  - 38 Boomtown path pieces re-baked and uploaded, 76 meshes (`98df960`, 2026-10-01);
  - 71 Boomtown prop stages and 9 Village narrow-home stages uploaded (`e823eab`, 2026-10-02);
  - **Ben's one harvest paste, 2026-10-02:** 156 assets (`82b5d53`);
  - templates for 49 props and 38 path pieces (8 retired), fabric data rebuilt from harvested
    extents (still 75 lots), manifest and place builds (`4e4253f`).
- **Studio start-era switch** (`3cb4add`): Workspace attribute `DebugStartEra`, Studio only, fresh
  saves only. A second place build bakes it in:
  `rojo build boomtown.project.json -o build/boomtown.rbxl`. **Never publish that file.**
- **Renders:** `assets/testfit/out/Boomtown/m12d_{tier1,tier3,full,full_entrance}.png`,
  `m12d_block.png`, `m12d_compare.png`, `m12d_streetplan.png`.

**Review (wave 2.4): 0 Critical, 2 Major, 8 Minor** (text in INTERFACES "Rulings after the wave 2.4
reports and review").
- **Major 1, fixed (`e109635`), then replaced by wave 2.5:** lane parts were turned, which broke
  the street texture's tiling at bends and ends. The fix laid axis-aligned legs unturned. Wave 2.5
  removed that texture path altogether.
- **Major 2, ruled:** the lot target. Ben accepted 75.
- Minors applied: `fabric.lanes.rimHeight` 0.02 and `clear.lane` 2.0.
- Minor open: the civic lot props never draw.
- Minor accepted for the playtest: each lane arrives whole.

**QA (2026-10-02): all gates green** (`4e4253f`). `bake.py --list` exits 0 for both eras;
`cityfabric.py timeline` passes for both; `gen_asset_manifest.py --check` passes.

**Shipped to playtest (wave 2.5 — baked lanes, 2026-10-02, commits `5a54b39` … `a78b4f1`):**
- **The defect:** on Ben's first Studio look at Boomtown the lanes flickered from a distance ("a
  texture above each other ... if you get close enough it renders it well"). That was z-fighting
  between the wave 2.4 lane Parts: a kerb Part and a surface Part 0.02 to 0.03 studs apart.
- **The fix:** every lane is a **baked path piece**, `LN_1` … `LN_8`, like a landmark's driveway.
  - Boomtown now bakes **46 pieces**: 21 stretches, 17 spurs, 8 lanes. The 38 older pieces came
    out byte-identical; only the 16 lane meshes were uploaded.
  - A lane is drawn whole once any lot on it has a building site: kerb, then surface, then dust.
  - Lane bends turn on one lane width (3 studs).
  - Far plots keep a lane's surface and drop its kerb, as for the streets.
  - Without its template a lane falls back to one layer of flat Parts named `Lane`. That is not
    reachable today: all eight templates exist.
  - `clear.lane` is 2.8 (was 2.0), so fields keep off the lane kerbs. `fabric.lanes` is now
    `{ width, rim, fillHeight }`.
- **Commits:** `5a54b39` (contract), `78e756d` (client), `e0e5651` (pipeline), `afcb43d` (bake
  and upload), `2827521` (harvest: **Ben's second, short paste**, 16 lane meshes), `ccc9dc9` (lane
  templates, manifest, builds), `a78b4f1` (rulings, `clear.lane` 2.8, builds).
- **Lot, layer and plume numbers are unchanged** from the wave 2.4 block.

**Review (wave 2.5): 0 Critical, 0 Major, 6 Minor.** No z-fight source remains in the baked
renderer. Three Minors are open (below). `bake.py --list` exits 0 for both eras (Boomtown: 46
pieces, 8 lane pieces match the fabric data); `gen_asset_manifest.py --check` passes.

**Known follow-ups (wave 2):**
- **lead (open, wave 2.5 review):** the Parts fallback for a lane still sits 0.02 to 0.03 studs
  from a street mesh where it runs under one, and stacks coplanar pieces at bends. Players never
  see it. Fix when next in `Fabric.luau`: start the first slab at the street's edge, raise
  `fabric.lanes.fillHeight` to 0.12, drop the discs.
- **lead (open, for the next Boomtown street re-bake):** the street pinch at (22.0, 24.9).
  Polylines 3 and 4 meet end to end there without joining, so their meshes end in round caps
  that only touch. Lanes 6 and 8 cover it, so it reads as a crossroads. Do not move that mouth
  until the two polylines are one. Ben did not report a pinch there at the sign-off.
- **lead (open, wave 2.5 review):** lane clearances in `fabric.py check` should use the bake's own
  half-width and cap overrun, not the data polyline plus `rim`; `fabric.lanes.fillHeight` should
  not be required for a baked lane.
- **Ben → lead (open, still not sent):** the numbers: Village step 37, and the same on a full
  Boomtown (step 59 of the Boomtown section).
- **Watch items (Ben, when convenient; lead to keep an eye):** the checklist steps the sign-off
  did not cover: the phone at 375×667 (step 41), low graphics (42), two players (43–45) and the
  measurement (58–59) of `docs/PLAYTEST.md` "M12 wave 2 — Boomtown growing city".
- **lead (after Ben's numbers):** the far-plot field budget. A far tier-0 Boomtown plot draws 45
  of its 85 fields (`budget.wildFar`), so its hub-side fields are bare.
- **lead (open):** `FabricCivicSmall` and `FabricCivicMedium` never draw, because no lot's nearest
  landmark is the Clock Tower or the Fire Station. Give those landmarks lots to govern, or retire
  the props.
- **lead (if Ben asks):** density. Moving landmarks could open two pockets (about 8 more lots; a
  re-bake and a second harvest paste), or a narrower lane house (new props).
- **lead (note from the docs pass):** no lane can be seen on gravel. The first lane needs the
  Barber Shop (purchase 7), which requires Pave Main Street (purchase 6). The gravel lane surface
  and "lanes turn to asphalt with the streets" cannot be checked in Studio.
- **lead (confirm intended):** Village's two camp fire pits no longer smoke at `every` 7.
- **lead:** Boomtown's `houses`, `trees`, `greenery` and `parked` config blocks and the
  `Boomtown/House*` smoke entries are unread now. Remove them when the old filler props are
  retired from `Assets.json`.
- **lead (watch in Studio):** row lamps and tree keep-outs still measure a driveway at road width.
- **lead (open since the wave 2.0 review):** a pad marker can stand on the freshly drawn path for
  the pad's 0.5 s grace after a purchase.
- **Done (housekeeping, 2026-10-02):** the three `tycoon-m12*` worktrees are removed. The
  branches `m12-boomtown-grid` and `m12-boomtown-organic` are kept as the record.

**Next (updated 2026-10-05):**
1. **Metropolis (wave 3): done.** Signed off by Ben and merged to `main` on 2026-10-05. See
   "Wave 3 — Metropolis" below, which holds the current "Next" list.
2. **Orbital (wave 4): started 2026-10-05**, on Ben's go. See "Wave 4 — Orbital Colony" below.
3. Alongside: the open follow-ups above, and Ben's numbers when they arrive.

The code is shared; each era adds data, config and models.

- [x] Wave 2.0 (Village smoke and carts) built, reviewed, QA green (2026-10-01)
- [x] Wave 2.1 mock built: two candidates, gate renders ready (2026-10-01)
- [x] Ben decided 1: organic, with the bolder pass (2026-10-01)
- [x] Ben decided 2: all four of `fireHydrant`, `billboardSign`, `neonDistrict`, `busLine` become
  city-changer slots (2026-10-01)
- [x] Ben decided 3: chimneys on the three narrow Village homes from their first stage
  (2026-10-01)
- [x] Ben decided 4: Boomtown roads stay 6 studs wide (2026-10-01)
- [ ] Ben → lead 5: the numbers from PLAYTEST M12 step 37 (instance counts and frame time on a
  full Village with neighbours), and now the same on a full Boomtown
- [x] Waves 2.2 and 2.3 built, reviewed, QA green (2026-10-01)
- [x] Ben at the second gate (2026-10-01): layout and props approved, with the request for roads
  to the houses
- [x] Wave 2.4 (back lanes) built and reviewed; Ben approved the lane renders at 75 lots
- [x] lead: kits, path re-bake and upload, props merge and upload (2026-10-01 → 2026-10-02)
- [x] Ben: the one harvest paste (2026-10-02)
- [x] lead: harvest, templates, rebuilt fabric data, gates, manifest (2026-10-02, `4e4253f`)
- [x] lead → ui-engineer: the lane-texture fix, with both place files rebuilt (2026-10-02,
  `e109635`)
- [x] Ben's first Studio look at Boomtown (2026-10-02): one defect, the lanes flicker from a
  distance
- [x] Wave 2.5 (baked lanes) built, reviewed, uploaded, harvested (Ben's second paste) and
  templated (2026-10-02, `a78b4f1`)
- [x] Ben: the Boomtown Studio playtest: signed off on a Studio look at the lanes and the town
  (2026-10-02, "looks really good! lets send it"); not a report of all 60 steps
- [x] lead: merged `m12-boomtown` into `main` (2026-10-02, merge commit `86d1d99`); worktrees removed
- [ ] Watch items: the unreported checklist steps (phone, low graphics, two players, measurement)
- [ ] Ben: the Village carts and smoke on `build/test.rbxl` ("M12 wave 2.0 — Village smoke and
  carts", and steps 49–57 of the Boomtown section): not reported
- [x] lead: wave 3, Metropolis, opened 2026-10-02 (the lattice study came first); its checklist
  is under "Wave 3 — Metropolis"

### Wave 3 — Metropolis (2026-10-02 → 2026-10-05; signed off and merged to `main` 2026-10-05, `d0dd894`)

**Where:**
- **The work lives on `main`**, in the main checkout `C:\Users\benja\Desktop\tycoon` (`main` at
  `d0dd894`, a fast-forward: `m12-metropolis` was 62 commits ahead). `origin/main` has it since 11:00 that day: the main checkout's editor sync pushed it, not the lead.
- **The worktrees are gone:** `tycoon-m12m-avenues` and `tycoon-m12m-boulevard` are removed
  (junctions first), and the branch `m12-metropolis` is deleted. The leftover folder
  `tycoon-m12m` was deleted on 2026-10-05, after every file in it matched `d0dd894`.
- Code, review and QA are done at `b6891e8` (QA ran at `1feb551`; `b6891e8` adds the place
  builds). After the QA run, `33261d4` adds the upload name guard and the larger baked cash, with
  `build/metropolis.rbxl` rebuilt.
- The asset run is `0a2258b` (upload), `aede7e3` (harvest) and `18bdc0b` (templates, manifest,
  place builds), all on 2026-10-05.
- **Kept as the record of the two layout candidates:** the branches `m12-metropolis-avenues`
  (**chosen**; last commit `2dff602`, merged in by `882b7ab`) and `m12-metropolis-boulevard`
  (not chosen, `a732dd6`).
- Contract: `docs/INTERFACES.md` "M12 wave 3 — Metropolis": "Wave 3.1" with its rulings blocks,
  "Wave 3.1b — avenues, denser", and "Wave 3.2 — Metropolis in the game" with its four rulings
  blocks.
- Memory: `.claude/memory/metropolis-growth-2026-10-02.md`.

**Status (2026-10-05): signed off by Ben and merged to `main`.**
- **Ben's sign-off:** "looks good!", after opening `build/metropolis.rbxl` in Studio.
- **What the sign-off was:** a look at the city in Studio. It was **not** a report of the
  51-step checklist. Not reported, and open as watch items: the step results, the phone at
  375×667, low graphics, two players, and the measurement (step 49).
- **Still owed by Ben:** the numbers: Village step 37, Boomtown step 59, Metropolis step 49. He
  has sent none of them.
- **The merge:** `main` fast-forwarded to `d0dd894`. The four place files and both sourcemaps
  were rebuilt in the main checkout, byte-identical to the committed ones. Re-run there, all
  passing: `fabric.py check Metropolis`, `check_mirror.py --strict`, `gen_templates.py --check`
  (444 templates), `check_compile.py` (122 files). `origin/main` has it since 11:00 that day: the main checkout's editor sync pushed it, not the lead.
- Metropolis is tested on `C:\Users\benja\Desktop\tycoon\build\metropolis.rbxl` (a fresh save
  starts in era 3, with 1e20 cash). **That file is for local Studio use only and must never be
  published.**
- The asset run was done the same day (`18bdc0b`): see "The asset run" below.
- Routine: `docs/MANUAL_STEPS.md` "M12" §12–§16. Checklist: `docs/PLAYTEST.md` "M12 wave 3 —
  Metropolis growing city".
- The counts below were re-checked on the harvested sizes on 2026-10-05: none moved.

**Goal:** Metropolis grows as a downtown. An old town of car parks, vacant lots and brick blocks
covers the plot at the start. As the landmarks arrive it is redeveloped, lot by lot, into
building sites with tower cranes and then into towers that add floors as the landmarks level
up. Slots, order, prices, income and levels are unchanged.

**Rulings (Ben):**
1. 2026-10-03, the layout: "i love avenues, lets go with that, but i would love to add a little
   bit more density to it, adding 4 lanes and removing some empty space, specially what looks
   like sidewalk". Avenues is the pick. The boulevard candidate is kept as a record.
2. 2026-10-03, the denser avenues (85 lots, four lanes, 2-stud pavements): "yeah, i love it".
3. 2026-10-03, the city-changers: "lovely", his answer to the lead's recommendations. The lead
   reads it as:
   - `busStop` becomes **Open the Bus Line** and `rooftopGarden` becomes **Green the Rooftops**;
   - `cityPark` stays a park (no street trees) and `financeDistrict` stays its tower.
4. Still owed from waves 1 and 2: his step-37 numbers.

**Rulings (lead; the renders Ben approved carry them):**
- **The density ceiling is geometric.** With 4-stud pavements a street line cost about 31.6
  studs of depth, so only three fit across the 105 studs inside the ring. The first target (110
  lots) was set from Village and Boomtown and could not be reached: about 93 at most after the
  landmarks. Orbital has the same lattice, so its arithmetic comes before its target.
- **Block slabs are gone.** A slab paved a whole block at its first purchase. Every tower now
  carries its own paved forecourt. The street trees went with the slabs.
- **The old town is the wild land.** It may stand under the future highway and clears when the
  Highway Ramp is bought. There is no skirt past the plot edge: the ring is the city's edge.
- **Lanes in a tiles era are drawn as footpaths**, the look Ben approved in wave 2a. Nothing is
  baked for Metropolis.
- **Narrow lots are 4 × 8** (were 5 × 8).
- **No junction lamps on Metropolis.** With landmarks at the street line, 14 of the 20 lamp
  spots fell inside a landmark. The approved renders have none.
- **Three low landmarks carry no district** (City Park, Supermarket, Convention Center), so a
  late purchase never takes over towers that already stand.

**The gate (wave 3.1, 2026-10-02, commits `46af0f1` … `390ce10`).** Two real layouts through the
real generator, as for Boomtown:

| | Avenues (**chosen**) | Boulevard |
|---|---|---|
| Streets | a cross-town street inside the entrance; three avenues to the back, each closed by a tall landmark | one grand avenue from the entrance to the Skyscraper; two cross streets; four pedestrian alleys |
| Lots at the gate | 67, all on streets | 75: 13 on streets, 62 on alleys |
| Reads as | three avenues of towers, open and varied | two massed alley superblocks and a tower row on the axis |

Avenues then grew to 85 lots (wave 3.1b, `9b5a138` … `6fb59e6`) and 88 (wave 3.2).

**Built (wave 3.2, 2026-10-03 → 2026-10-04, commits `bb34173` … `b6891e8`):**
- **Client-only**, apart from two slot names in `Config/Eras/3_Metropolis.json`. No server,
  remote, attribute or profile change.
- **Economy unchanged:** `py tools/sim_economy.py` total 16:20:04, legacy 887; Metropolis
  4:28:49.
- **Layout** (`src/shared/Layouts/Metropolis.luau`, "avenues"):
  - the entrance at (0, −49); a cross-town street at z −42; three avenues at x −28, 0 and 28;
    a short T at the head of the centre avenue;
  - the Skyscraper closes the centre avenue, the Bank Tower the west one, the Office Tower the
    east one; the Hotel and the Broadcast Tower flank the Skyscraper;
  - City Hall and the Shopping Mall face the entrance across the cross-town street;
  - landmarks stand with their front on the pavement's edge and their pad on their own ground;
  - 46 tile cells (`budget.tileCells` 180); the ring and the ramp are where they were (ring 56,
    ramp onto the cross-town's west end);
  - the layout has no `lots`, `parking`, `plazas`, `treeZones`, `greeneryZones` or `blocks` any
    more.
- **Pavements are 2 studs wide** (were 4); walkers walk 4.5 from the street's centre.
- **Fabric** (`src/shared/Config/Fabric/Metropolis.json`, generated from
  `tools/fabric/Metropolis.plan.json`): **88 lots**.
  - 52 on streets (50 narrow, 2 small) and 36 on lanes (9 narrow, 27 small): 59 narrow 4 × 8 and
    29 small 6 × 6 in all.
  - `pull`: radius 119, `tierTerm` 0.3, thresholds [0.6, 2.58, 2.88, 4.25], reach 30.
- **Four lanes**, 218 studs in all, 3 studs wide: a front and a back lane on each side, between
  the side avenue's outer row and the ring.
  - Each is drawn whole, as a flat footpath (at most 3 Parts), with one dust burst.
  - The front and back lane on a side stop 0.5 studs apart.
- **Old town:** 28 entries (24 blocks of 13 × 13 and 4 single items) on a 14-stud grid, at most
  3.6 studs tall. Three kinds of block: car park, fenced vacant lot, brick buildings.
- **Towers grow floor by floor:** five stages each (`fabric.levelStages` [1, 3, 4]), a storey is
  1.6 studs. A tower is never taller than the landmark that governs it.
- **Building sites with tower cranes** (`fabric.siteVariants`): about one narrow site in three
  and one small site in two carries a crane.
- **Next-pad marker:** a lot hoarding (`LotHoarding`) and stakes with string; a reveal scaffold
  on each purchase.
- **Two city-changer slots** (`streetOnly`; type, cost, income, multiplier and `requires`
  unchanged):

  | Slot | # in order | Name | At full build |
  |---|---|---|---|
  | `busStop` | 8 | Open the Bus Line | 5 bus shelters on 4 streets; city buses in the traffic (about 15%, at least one) |
  | `rooftopGarden` | 20 | Green the Rooftops | 45 home and shop towers swap to their roof-garden twin |

  - The Bus Line costs no lot: each shelter stands behind the pavement in ground no lot could
    use.
  - Green the Rooftops is a prop swap (`fabric.swaps`): the same tower with a garden roof.
- **Subway kiosks:** 4, each at a street corner beside the pavement (a kiosk no longer fits on
  one).
- **Traffic:** cars keep to the streets; a landmark's footpath carries no car lane.
- **Client rules** (`src/shared/CityFabric.luau`, `src/client/City/{Fabric,RoadGraph,Highway,
  Scatter,PropFactory,Ambient}.luau`, `CityDressingController`, `AssetPreloader`):
  - `levelStages`, `siteVariants`, `swaps`, the ring's own clearing, tiles-era lanes;
  - birds circle the owned landmarks, tallest first, once no old-town block is left;
  - every new key is optional: without them Village and Boomtown behave as before.
- **Props, final (uploaded, harvested and templated 2026-10-05):** 35 blueprints, 107 stages, in
  `tools/testfit/blueprints/_props/Metropolis/`.
  - 18 towers of 5 stages: 11 and the 7 `…Green` twins of the home and shop ones;
  - 17 single-stage props: 9 old-town pieces, 4 sites (2 with cranes), `RevealScaffold`,
    `LotHoarding`, `BusShelterM`, `VehicleCityBus`;
  - three generated kits: `tower-kit` (`tools/assets/tower_kit.py`), `oldtown-kit`
    (`oldtown_kit.py`), `metro-transit-kit` (`metro_transit_kit.py`);
  - `untilStage` on a blueprint piece: a tower's roof leaves the mesh when the next storeys
    cover it. The 18 towers' last stages went from 25,766 to 17,802 triangles in all.
- **Tools and gates:**
  - `py tools/check_mirror.py --strict`: the real `CityFabric.luau` under the Luau CLI against
    the Python mirror, every fabric era;
  - `py tools/cityfabric.py props <Era>`: what any lot can show, and what nothing refers to;
  - `py tools/cityfabric.py timeline <Era>` now fails if a purchase shrinks or re-skins a
    standing building;
  - `py tools/streetplan.py`: no footpath on a road tile or a pavement; the landmark gap rule;
  - `py tools/fabric.py`: tiles-era lanes, the `spots` placer for the bus shelters, the
    tiles-era keep-outs;
  - `py tools/testfit/compare_sheet.py` (comparison sheets); `--write-blueprints` on
    `oldtown_kit.py` and `tower_kit.py`.
- **Studio start file:** `metropolis.project.json` → `build/metropolis.rbxl`. It bakes in
  `DebugStartEra` 3 and `GrantCash` 1e20: a fresh save starts in Metropolis with cash. **Never
  publish that file.**
- **Renders** in `assets/testfit/out/Metropolis/`:
  - `m12m_compare.png`: today against avenues;
  - `m12m_avenues_{tier1,tier3,full,full_entrance,lane,streetplan}.png`;
  - `m12m_changers_final.png`: both city-changers, before and after;
  - prop sheets and strips in `m12m_props/`.

**Timeline** (`py tools/cityfabric.py timeline Metropolis`, the sim's greedy player at the end of
each tier):

| Tier | Towers | Sites | Lanes | Bus shelters | Green roofs | Old-town blocks left whole |
|---|---|---|---|---|---|---|
| 1 | 7 | 14 | 1 | 0 | 0 | 15 |
| 2 | 26 | 8 | 2 | 3 | 0 | 10 |
| 3 | 60 | 20 | 4 | 4 | 0 | 2 |
| 4 | 72 | 11 | 4 | 5 | 0 | 0 |
| full | 88 | 0 | 4 | 5 | 45 | 0 |

No chimney smoke in Metropolis (`ambient.smoke.eras` names Village and Boomtown only). A far
plot shows 60 of the 88 towers.

**For a player buying in Build panel order and levelling nothing** (the same mirror):
- the first building sites and the first lane come with the Coffee Shop (purchase 2), the first
  towers with the Apartment Block (4);
- lanes 2, 3 and 4 come with High-Rise Apartments (9), the Hospital (13) and the Office Tower
  (15);
- bus shelters: 3 at purchase 8, 4 after the Hospital (13), 5 after the Hotel Tower (16);
- subway kiosks: 2 at purchase 12, 3 after the Hotel Tower (16), 4 after the Broadcast Tower
  (22);
- the last old town goes with the Bank Tower (21);
- 75 towers and 13 sites after purchase 24 (`GrowthTier` 3); 88 towers once levelled to
  `GrowthTier` 5.

**Review (wave 3.2, at `7e63579`): 0 Critical, 2 Major, 9 Minor.** Both Majors were layout data
and are fixed (`1feb551`); the Minors are fixed or ruled (text in INTERFACES "Review rulings" and
"After the review round").
- **Major, fixed:** five landmark footpaths ran under the pavement and onto the road tiles
  (City Hall, Shopping Mall, Hotel Tower, Broadcast Tower, Low-Rise Office). Each now ends in a
  leg that meets its street square-on and stops at the pavement's edge. New `streetplan.py`
  gate.
- **Major, fixed:** buying the Supermarket cut eight standing towers down a storey and
  re-skinned them. The Coffee Shop and the Supermarket swapped places, and the Supermarket
  carries no district. New `timeline` gate. No fix cost a lot: still 88.
- Minors applied: footpath bends abut (no two flat Parts overlap); the lane's dust burst is not
  taken by the old town's; no lane without the footpath look; the mirror applies the tile-cell
  budget; birds over landmarks when no block stands; `untilStage`.
- Minor ruled: the lane pairs stay 0.5 studs apart.

**QA (at `1feb551`, the lead's summary): everything green, with two notes.**
- The gate list is INTERFACES "Done when (wave 3.2, before the asset run)": `fabric.py check`,
  `streetplan.py`, `cityfabric.py selftest` and `timeline` for Village, Boomtown and
  Metropolis; the Luau and Python fabric in agreement (`check_mirror.py --strict`); stylua,
  selene, luau-lsp, `check_compile.py`; `rojo build` for the default, combat, boomtown and
  metropolis project files.
- Note 1: one selene warning, older than this wave: `src/client/UI/LegacyPanel.luau:200` (a
  shadowed `header`).
- Note 2: `docs/ASSET_MANIFEST.md` was stale. It was regenerated in the docs pass of 2026-10-04
  and again by the lead after the asset run. It now reads 74/74 Metropolis props uploaded,
  harvested and templated, and `py tools/gen_asset_manifest.py --check` passes.
- Re-run in the docs pass (2026-10-04): `py tools/cityfabric.py timeline Metropolis` (0
  shrinking buildings over 63 moments), `py tools/cityfabric.py props Metropolis` (35 props
  shown, none unused) and `py tools/sim_economy.py` (16:20:04, legacy 887).

**The asset run (2026-10-05, commits `0a2258b`, `aede7e3`, `18bdc0b`): done.**
- **Ben approved the final prop sheets** ("looks good!") and said "upload them".
- **Kits:** the cached `tower-kit` palette was deleted and the three kits were regenerated from
  their committed scripts (`oldtown-kit` 28 pieces, `tower-kit` 147, `metro-transit-kit` 2). No
  script had changed, so `--write-blueprints` was not run.
- **Merge:** only the 35 new props, with `--model` flags, so the 39 Metropolis props that were
  already uploaded were not touched. `done: 35 blueprint(s), 0 with problems`; 107 stage GLBs.
  The only warnings were the two crane sites' jibs overhanging their lots, as designed.
- **Upload** (`0a2258b`): the same 35 props, `uploaded 107/107`, no failure and no retry. 55 of
  the stage names took the short `ECT_` prefix.
- **Ben's one harvest paste:** `[HARVEST-DONE] 107 loaded, 0 failed`. He pasted the Output into
  the chat; the clipboard still held it.
- **Harvest** (`aede7e3`): 107 prop stages merged into `Assets.json`.
- **Templates** (`18bdc0b`): 35 new ones; 74 in `templates/_props/Metropolis/`, 226 prop
  templates and 444 templates in all; `gen_templates.py --check` passes.
- **Fabric data:** `fabric.py build Metropolis` on the harvested sizes changed nothing. Still
  88 lots (59 narrow, 29 small), 4 lanes of 218 studs, 5 bus shelters.
- **Gates, all green on the harvested sizes:** `fabric.py check` for Village, Boomtown and
  Metropolis; `cityfabric.py selftest`; `timeline` for all three (Metropolis no longer prints
  "heights from blueprints", and shows 0 standing buildings that shrink or change prop over 63
  moments); `props Metropolis` (35 shown, 0 never shown, 0 unreferenced); `check_mirror.py
  --strict`; `streetplan.py` for all four eras (0 violations); `bake.py --list` for Village and
  Boomtown; `valley.py check`; `sim_economy.py` (16:20:04, legacy 887); `check_compile.py`; the
  manifest check; stylua; luau-lsp. selene still has its one old warning in
  `LegacyPanel.luau:200`.
- **Place files** (`18bdc0b`): all four rebuilt; `build/metropolis.rbxl` is dated 2026-10-05
  10:42.
- **No count in this section or in PLAYTEST moved.** The docs-keeper re-ran the tier table, the
  Build-panel-order table, the two levelling counts and the kiosk timing on the harvested
  sizes.

**Known follow-ups (wave 3):**
- **Done (Ben, 2026-10-05):** the two prop sheets approved: "looks good!", then "upload them".
- **Done (lead, 2026-10-04, `33261d4`; found in the docs pass):** the 50-character asset name
  guard in `tools/assets/upload_models.py` (`MAX_DISPLAY_NAME`, `model_display_name()`).
  - A stage name was `EraCityTycoon_Prop_Metropolis_<Prop>_S<n>`: 51 to 55 characters for 11 of
    the 18 towers (the four `FabricOffice…` towers and all seven `…Green` twins).
  - A name over 50 now takes the short prefix `ECT_`. 55 of the 107 Metropolis stages do; none
    is over 50; every name already uploaded is unchanged.
- **Done (lead and Ben, 2026-10-05):** the asset run and Ben's one harvest paste (MANUAL_STEPS
  "M12" §14).
- **Done (2026-10-05):** the counts here and in PLAYTEST re-checked on the harvested sizes.
  None moved.
- **Done (Ben, 2026-10-05):** the Studio look at `build/metropolis.rbxl`: "looks good!". A look,
  not a report of the checklist.
- **Watch items (Ben, when convenient; lead to keep an eye):** the checklist steps the sign-off
  did not cover: the step results in general, the phone at 375×667 (step 40), low graphics
  (41), two players (42–43) and the measurement (49) of `docs/PLAYTEST.md` "M12 wave 3 —
  Metropolis growing city".
- **Done (lead, 2026-10-04, `33261d4`; found in the docs pass):** the baked cash is **1e20**
  (was 1e18). Maxing all 16 buildings costs about 5.9e18, and 1e18 only reached the Hotel Tower.
  Ben can now max every landmark and compare the full skyline with the render.
- **Ben → lead (open since wave 1):** the numbers: Village step 37, Boomtown step 59, and now
  the same measurement on a full Metropolis (step 49 of the Metropolis section).
- **lead (after Ben's numbers):** `budget.parcelsFar`. A far plot draws 60 of the 88 lots and
  all four lanes, so three lanes run past bare ground there.
- **lead (watch):** the fabric is about 110k triangles on a full near plot before `untilStage`,
  about 2.5 times Boomtown's whole plot. The phone frame time is not measured.
- **Done (wave 4.2, 2026-10-06; on `main` since the merge):** `src/client/City/Fabric.luau` had 170
  top-level locals (the compile gate fails at about 180 and Studio at 200). Its constants are
  folded into tables and its validation moved to `FabricValidation.luau`: 130 now.
- **lead (open):** closing the last half stud between the lane pairs needs a rule in the tools
  and the client.
- **lead (known, accepted):** the kiosk east of the entrance stands 2 studs onto the cross-town
  street's south pavement, so that walker lane ends there; the highway sign finds no legal spot
  (as before); a ring pier stands in the entrance view; the City Park's edge stands 0.35 over
  the east avenue's pavement; a `…Green` twin may stand up to 1.2 studs above its original.
- **lead (open; confirmed by the lead 2026-10-04):** Metropolis's `houses`, `plazas`, `greenery`
  and `parked` config blocks and `road.tiles.blocks` place nothing on the new layout. Retire
  them together with the other eras' unread blocks. Their props
  (`ApartmentA–C`, `TownhouseA/B`, `PlazaA/B`, `BushA/B`, `HedgeA`, `FlowerBedA`, `PlanterA`,
  `ParkedA–C`) and `LampPost` are still uploaded and templated. The `BusStop` and
  `RooftopGarden` building models are no longer spawned either.
- **Done (lead, 2026-10-05):** `m12-metropolis` merged into `main` (`d0dd894`, on `origin/main`); the
  two candidate worktrees removed (junctions first); the branch deleted; the two candidate
  branches kept as the record.
- **Done (lead, 2026-10-05):** the leftover folder `C:\Users\benja\Desktop\tycoon-m12m` is
  deleted. Every file in it matched `d0dd894` byte for byte first.

**Next (updated 2026-10-06):**
1. **Orbital (wave 4): done.** Started 2026-10-05 on Ben's go, from the session prompt
   `docs/prompts/m12-orbital.md`; signed off and merged to `main` on 2026-10-06. See "Wave 4 —
   Orbital Colony" below, which holds the current "Next" list.
2. Alongside: the open follow-ups of waves 1 to 3 (each listed above with its owner), and Ben's
   numbers when they arrive.

- [x] Wave 3.1 mock built: lattice study, two candidates, gate renders (2026-10-02)
- [x] Ben decided 1: avenues, with more density, four lanes and narrower pavements (2026-10-03)
- [x] Wave 3.1b built: 85 lots on streets and four lanes (2026-10-03)
- [x] Ben decided 2: the denser avenues approved, "yeah, i love it" (2026-10-03)
- [x] Ben decided 3: the city-changer plan, "lovely" (2026-10-03)
- [x] Wave 3.2 built: client, layout at 88 lots, final props, gates (2026-10-03)
- [x] Review: 0 Critical, 2 Major fixed, 9 Minor fixed or ruled (2026-10-04, `1feb551`)
- [x] QA green at `1feb551`; place builds at `b6891e8` (2026-10-04)
- [x] docs-keeper: PLAN, PLAYTEST, MANUAL_STEPS, asset manifest (2026-10-04)
- [x] Ben: OK on the final prop sheets (`_contact_final_towers.png`, `_contact_final_oldtown.png`):
  "looks good!" (2026-10-05)
- [x] lead: the 50-character name guard in `upload_models.py`, and `GrantCash` 1e20 in the
  Metropolis build (2026-10-04, `33261d4`)
- [x] lead: kits, merge, upload of 35 props (107 stages) (2026-10-05, `0a2258b`)
- [x] Ben: the one harvest paste, 107 loaded, 0 failed (2026-10-05)
- [x] lead: harvest, templates, fabric data from harvested extents, gates, manifest, builds
  (2026-10-05, `aede7e3`, `18bdc0b`)
- [x] docs-keeper: the docs after the asset run; counts re-checked, none moved (2026-10-05)
- [x] Ben: the Metropolis Studio look in `build/metropolis.rbxl`: signed off, "looks good!"
  (2026-10-05); not a report of all 51 steps
- [ ] Ben → lead: the numbers (Village, Boomtown, Metropolis)
- [x] lead: merged `m12-metropolis` into `main` (2026-10-05, fast-forward to `d0dd894`; on
  `origin/main` the same day); candidate worktrees removed, branch deleted
- [x] lead: the leftover folder `tycoon-m12m` deleted (2026-10-05)
- [ ] Watch items: the unreported checklist steps (step results, phone, low graphics, two
  players, measurement)
- [x] lead: wave 4, Orbital, started on Ben's go (2026-10-05; the density arithmetic first).
  See "Wave 4 — Orbital Colony"

### Wave 4 — Orbital Colony (2026-10-05 → 2026-10-06; signed off and merged to `main` 2026-10-06, `c01ccfd`)

**Where:**
- **The work lives on `main`**, in the main checkout `C:\Users\benja\Desktop\tycoon` (`main` at
  `c01ccfd`, a fast-forward: `m12-orbital` was 46 commits ahead).
- **Whether `origin/main` has it: run `git status -sb`.** Right after the merge `main` was 49
  commits ahead of `origin/main`. The editor sync in the main checkout usually publishes
  `main` within a minute.
- **The worktree is gone:** `tycoon-m12o` is removed (its `assets` junction first) and the
  branch `m12-orbital` is deleted. Where a done step says it "ran from `tycoon-m12o`", that is
  the record of where it ran then.
- **Kept as the record of the four layout candidates:** the branches `m12-orbital-docks`
  (`cf4050a`) and `m12-orbital-axis` (`3cb4123`), both rejected; `m12-orbital-vine`
  (`8b37a7e`), not chosen; `m12-orbital-bloom` (**chosen**; merged in by `954e286`, then
  reseated). Their worktrees are removed.
- Commits: wave 4.1 `cc49f77` … `39766db`; wave 4.1b `64a5fec` … `7a5fd85`; wave 4.1c
  `1e83f18` … `fd13907`; wave 4.2 `a9fba4f` … `f0f0167`; the review fixes are `0f526ae`,
  `e0f0ab4` and `f0f0167`. The asset run is `88073d1` (upload), `89a8f99` (harvest), `e566676`
  (templates, manifest) and `c01ccfd` (the twin rule, fabric data, sourcemaps, place files).
- Contract: `docs/INTERFACES.md` "M12 wave 4 — Orbital Colony": "Wave 4.1" (the rejected
  mock), "Wave 4.1b — organic Orbital", "Wave 4.1c — city-changers on Bloom", and "Wave 4.2 —
  Orbital in the game" with "Rulings after the wave 4.2 reports" and "Review rulings".
- Memory: `.claude/memory/orbital-growth-2026-10-05.md`.

**Status (2026-10-06): signed off by Ben and merged to `main`. M12 is complete, all four eras.**
- **Ben's sign-off:** "looks good! lets ship it", after opening `build\orbital.rbxl` in Studio
  (from the worktree, before the merge; the build in the main checkout is byte-identical).
- **What the sign-off was:** a look at the colony in Studio. It was **not** a report of the
  54-step checklist. Not reported, and open as watch items:
  - the four lettered questions: the garden wave's pace (step 28), the weakest city-changer
    (31), colony or Metropolis in white (35), far tubes at quality 1 (42);
  - the step results in general, the phone at 375×667 (40), low graphics (41–42), two players
    (43–45) and the measurement (52).
- **Still owed by Ben:** the numbers: Village step 37, Boomtown step 59, Metropolis step 49,
  Orbital step 52. He has sent none of them.
- **The merge:** `main` fast-forwarded to `c01ccfd`. Re-run in the main checkout, all passing:
  `fabric.py check OrbitalColony`, `check_mirror.py --strict`, the Orbital list gate,
  `gen_templates.py --check` (554 templates), `check_compile.py`, the manifest check,
  `sim_economy.py` (16:20:04, legacy 887), stylua, and selene with its one old warning. Both
  sourcemaps and the five place files were regenerated there, byte-identical to the committed
  ones.
- Orbital is tested on `C:\Users\benja\Desktop\tycoon\build\orbital.rbxl` (a fresh save starts
  in era 4, with 3e21 cash). **That file is for local Studio use only and must never be
  published.**
- Review at `87de142`: 0 Critical, 1 Major, 4 Minor, all fixed or ruled. QA at `ccfae33`: green.
- The asset run was done the same day: see "The asset run" below.
- Routine: `docs/MANUAL_STEPS.md` "M12" §17–§21. Checklist: `docs/PLAYTEST.md` "M12 wave 4 —
  Orbital growing city".
- The counts below are on the harvested sizes (the pipeline's gate run after the harvest,
  2026-10-06).

**Goal:** Orbital grows as a colony. Raw regolith (craters, boulder rings, mounds, survey
beacons) covers the plot at the start. As the landmarks arrive, curving white tubes grow in
from the entrance, pods and domes rise along them, and the regolith recedes. Slots, order,
prices, income and levels are unchanged.

**Rulings (Ben):**
1. 2026-10-05, the start: asked how to begin, he chose "arithmetic and plan only"; on the
   study's report he said "lets do it" (a mock with two candidates, "Docks" and "Axis").
2. 2026-10-05, the first gate: **both rejected.** "i dont really love it, i was looking for
   something more organic looking for the orbital colony, it looks way to similar to
   metropolly". Asked what organic should mean, he chose:
   - **curving tubes** (over hubs and spokes, and over clusters on the square pieces);
   - **as dense as organic allows** (over open regolith between clusters);
   - **a round monorail loop** (over the square ring).
3. 2026-10-06, the second gate: "lovely, lets go with bloom". Bloom (82 lots) over Vine (63).
4. 2026-10-06, the third gate, the city-changers: "looks good! lets keep all four". The lead
   reads it as: flags, green domes, rock gardens and hub beacons stay; `orbitalUplink` and
   `planetaryDefense` stay buildings; the reseated Bloom (89 lots) is the layout.
5. 2026-10-06, the three final prop sheets: "lets do it".
6. 2026-10-06, the Studio look at `build\orbital.rbxl`: "looks good! lets ship it".
7. Still owed from waves 1 to 4: his numbers ("not measured yet").

**Rulings (lead; the renders Ben approved carry them):**
- **Never again for Orbital:** straight avenues, terrace rows of window-banded boxes, a square
  ring. That is what read as Metropolis.
- **Orbital leaves the tiles family.** A tube is one swept half-pipe mesh per stretch, with the
  ids the baked paths use, so it grows with the buildings. Two pieces butt on one
  cross-section; a round hub stands only where a tube ends or branches.
- **Landmark connections are flat decking, never tubes** (a buy pad must stay in view). Each
  landmark's piece is its apron: footpath, pad and building ground as one mesh.
- **Geometry rules:** a tube never curves tighter than a 6-stud radius; two tubes into one hub
  leave it 90° or more apart; a tube crosses the monorail's band at 60° or more to the track
  and 2 studs or more from a pier foot.
- **The regolith stays under the monorail for good** (`highway.clearBand` false). The beam is
  1.6 wide, and clearing the band left a fifth of the plot bare.
- **The colony spills past the loop:** eight landmarks stand in the plot's corners.
- **Dense and wandering pull against each other on this plot.** A third of the ground lies
  within 10 studs of the loop, and only a tube that follows the loop can front it. Drafts that
  wandered held 48 to 58 lots.
- **Four landmarks carry no district:** the Landing Pad and the Solar Array (the lowest
  landmarks in the game), the Orbital Uplink and Planetary Defense. They govern no pods.
- **City-changers must show from the whole-plot camera.** So the rock gardens became a swap of
  the standing regolith, the flags also hang on the monorail's piers, and habitat holds at
  least 20 lots.
- **Only what a lot can show is uploaded.** Four of the 19 pod and dome props are shown by no
  lot on this layout and stay out of the asset run (see "The asset run").

**The gates.** Four real layouts through the real generator, two at a time:

| | Docks | Axis | Vine | Bloom (**chosen**) |
|---|---|---|---|---|
| Gate | first, 2026-10-05: rejected | first: rejected | second, 2026-10-05 | second |
| Tubes | a cross tube and four straight avenues | three straight avenues, six decking lanes | an S trunk inside two runners, spurs and curls | a stem, a heart ring, an open outer ring, a spiral |
| Lots at the gate | 108 | 97 | 63 | 82 |
| Reads as | a comb of four white pipes | a town with a main street | an S in a horseshoe, close to Bloom | rings round a heart of landmarks |

Bloom was then reseated for the four street-only slots (wave 4.1c): **89 lots**.

**Built (wave 4.2, 2026-10-06, commits `a9fba4f` … `f0f0167`):**
- **Client-only**, apart from four slot names and `streetOnly` flags in
  `Config/Eras/4_OrbitalColony.json`. No server, remote, attribute or profile change.
- **Economy unchanged:** `py tools/sim_economy.py` total 16:20:04, legacy 887; Orbital
  9:25:10.
- **Layout** (`src/shared/Layouts/OrbitalColony.luau`, "bloom", reseated):
  - the entrance hub at (0, −49), and a short **stem** from it to the heart;
  - a **heart ring** of tube with six landmarks inside it; the Comms Array is its spire;
  - an **open outer ring** at twice the distance, which echoes the monorail; its two ends
    pass under the track to the two back corners;
  - a **spiral**: the heart ring unwinds into a back arc that the Observation Dome closes;
  - two short tubes cross under the track to the two front corners;
  - eight landmarks stand past the loop, two in each corner; the **Launch Tower** stands in a
    back corner, outside the loop;
  - the Landing Pad and the Solar Array stand at the gate, either side of the stem;
  - five tube polylines, a tree (every ring is open);
  - the layout has no `lots`, `plazas`, `treeZones` or `blocks` any more.
- **Orbital is a path era now** (it was a tiles era):
  - **45 swept tube pieces**, 450 studs, 23,206 triangles: white half-pipes with grey rings;
  - **20 flat decking pieces**, 896 triangles: 19 landmark aprons and the entrance apron
    `SP_entrance` (from the plot's front edge to the first hub, laid from the start);
  - **11 round tube hubs** (`TubeHub`), one where a tube ends or branches; a hub appears with
    the first tube at its node;
  - 65 pieces and 24,102 triangles in all; one mesh per piece, no rim, one palette texture.
- **Round monorail** (`highway.round`): 48 `MonorailArc` segments on a circle of radius 56,
  one pier at each segment's middle; the train rides the circle.
  - The entrance passes between two piers. Tubes cross under the track at four places, one
    toward each corner, each halfway between two piers.
  - `highway.segments` (48) and `highway.bandHalf` (3.5) are config.
- **Fabric** (`src/shared/Config/Fabric/OrbitalColony.json`, generated from
  `tools/fabric/OrbitalColony.plan.json`): **89 lots**.
  - 71 narrow 4 × 8, 14 small 6 × 6, 4 medium 8 × 12; no lanes.
  - By district: habitat 25, industry 31, port 19, science 14.
  - `pull`: radius 85, `tierTerm` 0.1, thresholds [0.3, 1.6, 1.84, 2.3], reach 30.
- **Wild regolith:** 90 entries (34 clumps, 56 single pieces) as an irregular scatter, at most
  3 studs tall: craters, boulder rings, mounds, boulders, survey beacons. No skirt past the
  plot edge. (92 before the harvest; see "The asset run".)
- **Pods and domes grow in five stages** (`fabric.levelStages` [1, 3, 4]); round forms only
  (capsules, drums, spheres, domes, vaults). A pod is never taller than the landmark that
  governs it.
- **Building sites with robot gantries** (`fabric.siteVariants`).
- **Next-pad marker:** a lot beacon (`LotBeacon`) and stakes with string; a reveal scaffold on
  each purchase.
- **Four city-changer slots** (`streetOnly`; type, cost, income, multiplier and `requires`
  unchanged):

  | Slot | # in order | Name | At full build |
  |---|---|---|---|
  | `colonyFlag` | 8 | Raise the Colony Flags | 24 flag masts beside the tubes and 24 banners on every other monorail pier |
  | `lifeSupport` | 12 | Green the Domes | 25 habitat pods and domes swap to their Green twin |
  | `rockGarden` | 14 | Tend the Rock Gardens | every standing piece of regolith becomes a raked garden (`fabric.wildSwaps`): 42 at the end of tier 3, 23 at full build |
  | `holoBeacon` | 20 | Light the Holo Beacons | a hologram over each of the 11 hubs |

  - `walkwayNetwork` "Build the Monorail" (6) was street-only already. `orbitalUplink` (17)
    and `planetaryDefense` (23) stay buildings.
  - The pads of the four stand in the corners past the loop, on ground no pod can front.
- **Client rules:**
  - `src/shared/CityFabric.luau`: `RoundLoop`, `RingBand`, `KeptInBand`, `RingGround`,
    `SwappedWild`, `UpgradeDeveloped` and their validators;
  - new `src/client/City/Tubes.luau` (pure: the hub rule and the entrance apron) and
    `FabricValidation.luau`; `Fabric.luau` went from 170 to 130 top-level locals;
  - `RoadGraph`, `PathRenderer`, `Highway`, `PropFactory`, `CityDressingController`,
    `AssetPreloader`;
  - every new key is optional: without them the other three eras behave as before;
  - a missing template draws a placeholder Part or nothing, with one warning per era and
    kind, never an error.
- **Props, final (45 uploaded, harvested and templated 2026-10-06; 4 kept as blueprints
  only):** 49 new blueprints in `tools/testfit/blueprints/_props/OrbitalColony/` (62 with the
  13 older ones).
  - 19 of 5 stages: 15 pods and domes and the 4 `…Green` twins of the habitat ones;
  - 30 single-stage props: 6 regolith clumps and quarters, 3 single pieces, their 9
    `…Garden` twins, 5 sites (2 with gantries), `LotBeacon`, `RevealScaffold`, `TubeHub`,
    `MonorailArc`, `ColonyFlagMast`, `PierBanner`, `HubBeacon`;
  - two new generated kits, `colony-kit` (`tools/assets/colony_kit.py`) and `regolith-kit`
    (`regolith_kit.py`), and new pieces in `tube-kit` and `monorail-kit`.
- **Asset route for the tubes** (`tools/paths/tubes.py`; `py tools/paths/bake.py --era
  OrbitalColony` hands the era to it): the baked-paths route, with one mesh per piece and a
  palette. `upload_paths.py`, `harvest.py`, `gen_templates.py --paths` and the manifest follow
  an era's own layers.
- **Tools and gates:**
  - `py tools/check_mirror.py --strict` now covers Orbital, and `Tubes.luau` against
    `tubes.py`;
  - `py tools/paths/bake.py --era OrbitalColony --list`: the list gate for tubes and decking;
  - `py tools/cityfabric.py props OrbitalColony` also names the hub, the track, the train and
    the uploads nothing refers to;
  - `py tools/fabric.py check`: regolith kept under the track keeps its ground off every lot,
    pad, apron and landmark.
- **Studio start file:** `orbital.project.json` → `build/orbital.rbxl`. It bakes in
  `DebugStartEra` 4 and `GrantCash` 3e21: a fresh save starts in Orbital with cash for every
  purchase and Max on every building (24 slots cost 2.346e15; 16 buildings to level 100 cost
  2.1584e21). **Never publish that file.**
- **Renders** in `assets/testfit/out/OrbitalColony/`:
  - `m12o_compare.png` (the rejected first gate) and `m12o_compare_organic.png` (Vine against
    Bloom);
  - `m12o_bloom2_{tier1,tier3,full,full_entrance,streetplan}.png`: the reseated Bloom;
  - `m12o_bloom_reseat.png`: Bloom as picked against reseated;
  - `m12o_changers.png`: the four city-changers, before and after;
  - prop sheets and strips in `m12o_props/`.

**Timeline** (`py tools/cityfabric.py timeline OrbitalColony`, the sim's greedy player at the end
of each tier; on the harvested sizes, the pipeline's run of 2026-10-06 after the harvest):

| Tier | Pods and domes | Sites | Tube stretches | Flags | Hub holograms | Green domes | Gardens | Regolith clumps left whole |
|---|---|---|---|---|---|---|---|---|
| 1 | 4 | 2 | 7 | 0 | 0 | 0 | 0 | 25 |
| 2 | 28 | 3 | 26 | 36 | 0 | 0 | 0 | 14 |
| 3 | 47 | 22 | 37 | 43 | 0 | 24 | 42 | 5 |
| 4 | 73 | 10 | 40 | 46 | 0 | 24 | 34 | 3 |
| full | 89 | 0 | 45 | 48 | 11 | 25 | 23 | 1 |

- Only the "Gardens" column moved with the harvest (it read 44, 36 and 25 before).

- "Flags" counts masts and pier banners together. "Gardens" counts the regolith pieces that
  stand and show their garden twin.
- No smoke, cars, walkers or birds in Orbital. Only the monorail train moves.
- A far plot shows 60 of the 89 pods.
- 0 standing buildings shrink or change prop over 63 moments.

**Review (wave 4.2, at `87de142`): 0 Critical, 1 Major, 4 Minor.** All fixed or ruled; the text
is in INTERFACES "Review rulings (2026-10-06 …)".
- **Major, fixed (`0f526ae`):** regolith kept under the monorail reached into lots, a pad and
  an apron (five cases). The generator and its check now keep that ground off every lot, pad,
  apron and landmark; the data was rebuilt (still 89 lots, 92 wild then). No standing regolith
  lies on a lot at any of the timeline's 63 moments.
- **Minor, fixed:** the client's hub rule and entrance apron (`Tubes.luau`) joined
  `check_mirror.py --strict`; `highway.segments` and `highway.bandHalf` moved from code to
  config; one shared `CityFabric.RoundLoop` predicate.
- **Minor, accepted:** the one-time missing-prop warning now applies in every era. It cannot
  fire while templates exist.
- **Not judged without Studio:** that nothing errors while Orbital has no templates; the
  arc's curve after the import turn; hub and tube heights; the train over 48 chords; the
  garden wave's pace; phone cost.

**QA (at `ccfae33`, before the asset run): green, with two exceptions that were expected
then.** Both are closed now.
- `py tools/paths/bake.py --era OrbitalColony --list` exited 2 until the asset run: the client
  and the plan agreed on 65 pieces, and 0 were baked. It exits 0 since the bake.
- `py tools/gen_asset_manifest.py --check` was stale until the docs pass regenerated the
  manifest. After the asset run Orbital reads: 24/24 buildings; props 62/62 blueprints, 58/62
  uploaded, harvested and templated; a baked-paths row with 65 pieces, "in game".
- Green: `fabric.py check` for the four eras; `cityfabric.py selftest`, `timeline` and
  `props`; `check_mirror.py --strict`; `streetplan.py`; the list gates for Village and
  Boomtown; `valley.py check`; `sim_economy.py`; `check_compile.py` (124 files);
  `gen_templates.py --check`; stylua; a Rojo build of all five project files.
- luau-lsp is clean both ways: `src` outside `src/combat` with `sourcemap.json`, and
  `src/combat` with `sourcemap.combat.json`.
- selene still has its one old warning (`src/client/UI/LegacyPanel.luau:200`).

**The asset run (2026-10-06, commits `88073d1`, `89a8f99`, `e566676`, `c01ccfd`): done.**
MANUAL_STEPS "M12" §19. It ran from the worktree `tycoon-m12o`, before the merge.
- **Ben approved the three final prop sheets:** "lets do it".
- **Bake:** 65 street pieces (45 tubes, 20 decking), 24,102 triangles, and the palette.
- **Upload** (`88073d1`): 66 path uploads and 45 props in 105 stages (15 of 5 stages: 12 pods
  and domes and 3 Green twins; 30 single-stage props). **171 uploads, all on the first try.**
- **Ben's one harvest paste:** `[HARVEST-DONE] 171 loaded, 0 failed`. It took two tries: the
  first time he pasted the Output into the chat, and his clipboard no longer held it.
  - The script ran in the **published** game's place, in a live editing session, not in a
    local build, and Studio saved to the live experience. The script parents nothing and
    destroys what it loads, so it left nothing in the place.
- **Harvest** (`89a8f99`): 105 prop stages, 65 path pieces and the palette merged into
  `Assets.json`.
- **Templates** (`e566676`): 45 new prop templates (58 in `templates/_props/OrbitalColony/`)
  and 65 in a new `templates/_paths/OrbitalColony/`; 554 templates in all;
  `gen_templates.py --check` passes. The manifest was regenerated.
- **One gate failed on the harvested sizes, and was fixed in the generator** (`c01ccfd`).
  Nothing was re-uploaded.
  - The three single Garden twins (`RegolithBoulderGarden`, `RegolithCraterGarden`,
    `SurveyBeaconGarden`) measure 0.12 to 0.23 wider than their originals' meshes.
  - The rule is now "a twin lies inside the ground reserved for its original", and the
    generator reserves the union of an entry's original and its twins. A single's ground also
    keeps off every pier foot.
- **Fabric data on the harvested sizes:** 89 lots, positions unchanged; two flag masts moved
  0.5; wild 90 (34 clumps, 56 singles; it was 92); the garden swap changes 42 entries at the
  end of tier 3 and 23 at full build.
- **Gates, all green on the harvested sizes:** `fabric.py check` for the four eras (the other
  three eras' data byte-identical); `cityfabric.py selftest`; `timeline` (Orbital no longer
  prints "heights from blueprints"; 0 standing buildings shrink or change prop over 63
  moments); `props OrbitalColony` (46 shown, 4 never shown, 12 uploads nothing refers to);
  `check_mirror.py --strict`; `streetplan.py` (0 violations); the list gates for Orbital,
  Boomtown and Village; `sim_economy.py` (16:20:04, legacy 887); `gen_templates.py --check`;
  the manifest check.
- **Place files** (`c01ccfd`): both sourcemaps and the five place files rebuilt;
  `build/orbital.rbxl` added.
- **Four props are not uploaded:** `FabricHabSmallA`, `FabricHabSmallAGreen`,
  `FabricIndMediumA`, `FabricPortMediumA`. No lot of that size falls in that district on
  Bloom. They stay in the repo as blueprints.
- `MonorailTrain` was uploaded already and was left alone.
- Names: 30 props (90 stages) and 18 decking pieces took the short `ECT_` form. No name is
  over 50 characters.
- Twelve uploaded Orbital props are no longer drawn: `HouseA`, `HouseB`, `LampPost`,
  `MonorailCorner`, `MonorailTrack`, `PlazaA`, `Rocks`, `TubeBend`, `TubeCross`, `TubeEnd`,
  `TubeStraight`, `TubeTee`.

**Lessons of the run (for the next asset run):**
- **Save the clipboard to a file before `harvest.py`.** The harvest Output lives only on
  Ben's clipboard, and one more copy loses it. Write it to a file first, then run
  `py tools/assets/harvest.py --props --file <that file>`. If Ben pastes the Output into the
  chat, do not count on the clipboard: ask him to copy the Output again.
- **Tell Ben which file to open for the paste:** a local build
  (`C:\Users\benja\Desktop\tycoon\build\test.rbxl`), not the published game.
- **A check that reads declared sizes before a harvest reads measured ones after it.** A rule
  that passes on blueprint sizes can fail on the harvested meshes (the Garden twins did). Run
  every size rule again after the harvest, and write rules about reserved ground, not about
  two meshes having the same footprint.

**Known follow-ups (wave 4):**
- **Done (Ben, 2026-10-06):** the three prop sheets approved: "lets do it".
- **Done (lead and Ben, 2026-10-06):** the asset run and Ben's one harvest paste (MANUAL_STEPS
  "M12" §19); sourcemaps and the five place files rebuilt.
- **Done (Ben, 2026-10-06):** the Studio look at `build\orbital.rbxl`: "looks good! lets ship
  it". A look, not a report of the checklist.
- **Done (lead, 2026-10-06):** `m12-orbital` merged into `main` (`c01ccfd`); the worktree
  removed (junction first); the branch deleted; the four candidate branches kept (§21 steps
  90 and 91).
- **lead (open; MANUAL_STEPS "M12" §21 step 92, left undone on purpose):** retire the 12
  uploaded props nothing draws (ids, templates, blueprints), and delete the unused GLBs in the
  shared kit folders: `colony-kit/sci-small-a-1-u1`; `regolith-kit/ground-a`, `ground-b`,
  `ground-c`, `boulder-large`, `rock-garden-a`, `rock-garden-b`, `hub-beacon`; the old tile
  pieces of `tube-kit` and `monorail-kit`.
- **docs-keeper (open):** the "after purchase N" table for PLAYTEST "M12 wave 4" (the other
  eras have one). The tier-end counts are re-checked on the harvested sizes; the table needs
  a mirror run in Build panel order.
- **Ben → lead (open since wave 1):** the numbers, instance count and frame time on a full
  plot: Village step 37, Boomtown step 59, Metropolis step 49, Orbital step 52.
- **lead (after Ben's numbers):** the far-plot budgets. `budget.parcelsFar` draws 60 of the 89
  pods, and `budget.wildFar` only whole clumps.
- **Watch items (Ben, when convenient; lead to keep an eye):** the checklist steps the sign-off
  did not cover: the step results in general, the phone at 375×667 (step 40), low graphics
  (41–42), two players (43–45) and the measurement (52) of `docs/PLAYTEST.md` "M12 wave 4 —
  Orbital growing city". The same three checks have never been reported for Boomtown or
  Metropolis either.
- **Ben → lead (unanswered):** the four lettered questions of that checklist: the pace of the
  garden wave, about 20 seconds (step 28); the weakest city-changer (31); colony or Metropolis
  in white (35); far tubes at quality 1 (42).
- **lead (watch):** the tubes are 23,206 triangles a plot with no far level of detail, and
  the cost of the fabric props is not measured.
- **Ben → lead (open, from the pipeline owner):** the tubes cast shadows. Change it only if Ben
  says so.
- **lead (not confirmed by a tool run):** four PLAYTEST steps are read from the rules, not
  from the mirror: the first sites after the Habitat Pod with nothing levelled (step 12), pods
  growing when the Habitat Pod is levelled to 51 (32), the train hidden on another player's
  plot with City detail off (45), and the missing-hub line (46). Confirm them with the
  purchase table.
- **lead (open):** four fabric props no lot shows on this layout (`FabricHabSmallA`,
  `FabricHabSmallAGreen`, `FabricIndMediumA`, `FabricPortMediumA`). They upload if a later
  layout or size rule uses them.
- **lead (held design asks, not built):** a marker offset mirrored per slot (about 6 lots); a
  per-run lot size list in `fabric.py`; a second small prop for industry, science and port;
  `wild.clumpQuarters`; a lone mound quarter reads as a cut wedge.
- **lead (known, accepted; from the third gate):** the reseated Bloom reads a little worse
  than the one Ben picked. The Fusion Reactor stands in a front corner outside the loop; the
  heart's south-west seat is an empty pad until purchase 17; the west arm shows 22 building
  sites at tier 3; no changer pad is near the entrance.
- **lead → ui-engineer (open):** `LANE.thickness` 0.2 in `src/client/City/Fabric.luau` is an
  older code constant. It belongs in config.
- **lead → economy-designer (open):** `tools/streetplan.py` reads a round loop with a ramp as
  round, and the shared rule reads it as a square ring. No config does it today.
- **lead → economy-designer (open):** `tools/streetplan.py` counts 64 Orbital path pieces
  where the list gate counts 65. It leaves out `SP_entrance`.
- **lead (record):** the branches `m12-orbital-docks`, `-axis`, `-vine` and `-bloom` are kept.
- **lead (open, listed under M13):** the Valley's re-bake for 6 plots when `m11-unlocks`
  merges.

**Next (updated 2026-10-06, after the merge):**
1. **M12 is complete.** No era is left.
2. **lead:** the cleanup of MANUAL_STEPS "M12" §21 step 92, when convenient.
3. **Ben, when convenient:** the numbers for the four eras, and the unreported checklist steps.
4. Alongside: the open follow-ups of waves 1 to 4 (each listed above with its owner).

- [x] Density study: the lot ceiling for the lattice (2026-10-05)
- [x] Wave 4.1 mock: Docks (108 lots) and Axis (97), gate renders (2026-10-05)
- [x] Ben decided 1: both rejected, "more organic"; curving tubes, dense, round loop
  (2026-10-05)
- [x] Wave 4.1b mock: Orbital as a path era, Vine (63) and Bloom (82) (2026-10-05)
- [x] Ben decided 2: Bloom, "lovely, lets go with bloom" (2026-10-06)
- [x] Wave 4.1c: four city-changers on Bloom, reseated to 89 lots (2026-10-06)
- [x] Ben decided 3: "looks good! lets keep all four" (2026-10-06)
- [x] Wave 4.2 built: shared rules, client, asset route, final props, `orbital.project.json`
  (2026-10-06, `f0f0167`)
- [x] Review: 0 Critical, 1 Major fixed, 4 Minor fixed or ruled (2026-10-06)
- [x] QA green at `ccfae33`, two expected exceptions (2026-10-06)
- [x] docs-keeper: PLAN, PLAYTEST, MANUAL_STEPS, CITY_GROWTH §3, asset manifest (2026-10-06)
- [x] Ben: OK on the three final prop sheets: "lets do it" (2026-10-06)
- [x] lead: bake and upload, 66 path uploads and 45 props in 105 stages (2026-10-06,
  `88073d1`)
- [x] Ben: the one harvest paste, 171 loaded, 0 failed (2026-10-06; two tries)
- [x] lead: harvest, templates, the twin rule, fabric data from harvested sizes, gates,
  sourcemaps, builds (2026-10-06, `89a8f99`, `e566676`, `c01ccfd`)
- [x] Ben: the Orbital Studio look in `build\orbital.rbxl`: signed off, "looks good! lets ship
  it" (2026-10-06); not a report of all 54 steps
- [x] lead: merged `m12-orbital` into `main` (2026-10-06, fast-forward to `c01ccfd`); worktree
  removed (junction first), branch deleted
- [x] docs-keeper: the docs after the merge; tier-end counts on the harvested sizes
  (2026-10-06)
- [ ] docs-keeper: the "after purchase N" table for PLAYTEST "M12 wave 4"
- [ ] lead: the cleanup, MANUAL_STEPS "M12" §21 step 92 (12 retired props, unused kit GLBs)
- [ ] Ben → lead: the numbers (Village, Boomtown, Metropolis, Orbital)
- [ ] Watch items: the unreported checklist steps (lettered questions, step results, phone,
  low graphics, two players, measurement)

## M13 — The Valley

**Goal:** give the world outside the plots a landscape (Ben, 2026-10-01: "low poly mountains,
rivers and such"). The target is a meadow basin ringed by snow-capped low-poly mountains, with
forest on the foothills, a waterfall, a river through the ring and a small lake. Core gameplay is
untouched.
- Contracts: `docs/INTERFACES.md` "M13 contracts — The Valley (wave 1: sky, ground, hub, roads)".
  Wave 1 runs through its "Review rulings". Wave 2 is "Wave 2 — the Valley meshes (Ben,
  2026-10-02)", through "Preview gate rulings" and "Done when (wave 2)".
- Memory: `.claude/memory/world-landscape-2026-10-01.md` (in the main checkout).
- Mock: `assets/research/2026-10-01-worldmock/` (gitignored), sheets in its `out/` folder.
- Where: on `main` since 2026-10-02, in the main checkout `C:\Users\benja\Desktop\tycoon`. It
  was built in the worktree `tycoon-m13` on branch `m13-valley` (off `main` `e5df035`), beside
  the M12 Boomtown session in `tycoon-m12`. Both worktrees and both branches are removed.

**Rulings (Ben):**
1. 2026-10-01: three landscapes were rendered around the real plots: A Valley, B Island, C Lake.
   Ben chose **A**: "i love A valley". The Island and the Lake are closed.
2. Start now, alongside the Boomtown session.
3. Three waves, each one a Studio look. **Replaced by ruling 5.**
4. **The river is shallow and wade-through, with solid wooden bridges.** Bridges are server
   geometry that collides. That is a new category next to the M9 rule "no dressing part
   collides", not a change to it.
5. 2026-10-02, after his first Studio look at wave 1: "we didnt do step A2 yet? do it". **The
   whole A2 Valley in one wave** (the old waves 2 and 3 together), so one upload batch and one
   harvest paste.

**Waves:**

| Wave | What | Assets | State |
|---|---|---|---|
| 1 | sky, haze, green ground, hub, dirt roads | Parts and Lighting only, **no uploads** | done; Ben saw it in Studio 2026-10-02 |
| 2 | the whole A2 Valley: mountains, foothills, forest, waterfall, far hills; ground with patches and baked roads; river, pond, lake; bridges and stepping stones; groves; era aprons; clouds; invisible wall at the foothills | 28 generated meshes, one upload batch, **one harvest paste (done)** | built, uploaded, harvested, templated; review, checks and playtest pending |

There is no wave 3. The river, pond, lake and bridges moved into wave 2.

**Wave 1**

**Shipped (wave 1, 2026-10-01 → 2026-10-02):**
- **Server-only and static.** The server builds the landscape once at boot, next to the plots. No
  client, remote, profile, economy or balance change.
- **Code:**
  - `src/shared/WorldPlan.luau` (new, pure): the ring maths, moved out of
    `PlotService.buildWorld`.
  - `src/server/World/Landscape.luau` (new): builds the sky, ground, hub, earth ring and roads.
    It sits outside `Services`, so the combat place never mounts it.
  - `src/shared/Config/World.json` (new), `Catalog.GetWorldConfig`, and the World types in
    `Types.luau`.
  - `PlotService.buildWorld` now calls `WorldPlan` and `Landscape.Build`. `Spawn`, the `Plots`
    folder and everything per plot are unchanged.
- **What `World.json` ships:**

  | Block | Result |
  |---|---|
  | `atmosphere` | haze: one `Atmosphere` under `Lighting` (density 0.25, offset 0.2, haze 1, glare 0) |
  | `ground` | green `Plastic` (126, 155, 76), 2048 studs square |
  | `hub` | pale stone (182, 176, 164) |
  | `hub.surround` | packed-earth ring (166, 138, 100), radius 38, 0.2 above the ground |
  | `roads` | one straight dirt road (158, 126, 88) per plot, 6 studs wide, 0.1 above the ground |
- **Left out on purpose** (reasons in the contract's "First values"):
  - no `lighting` block: brightness, ambient light and time of day are unchanged, because every
    building Ben approved was judged under the default Lighting;
  - no `clouds` block: the mock's clouds are low-poly meshes, which come in wave 2.
- **Collision:** roads are flat strips you walk through (`CanCollide`, `CanQuery`, `CanTouch`
  off). The ground, the hub and the earth ring collide.
- **Levels are unchanged:** plot and hub tops at Y = 0, ground top at Y = −1. The earth ring's top
  is at −0.8 and a road's top at −0.9.
- **Ring numbers** (from `Game.json` and the layout, no code change between them):

  | Plots | Ring radius | Road length |
  |---|---|---|
  | 10 (`main`) | 277.02 | 187 |
  | 6 (unmerged `m11-unlocks`) | 183.92 | 93.9 |
- **Everything degrades:**
  - without `World.json` the world is exactly as before M13;
  - a missing block switches off only that feature;
  - a bad material or colour warns once (`[Landscape]`) and falls back to the Part default.
- **No assets.** `docs/ASSET_MANIFEST.md` is unchanged.
- **Preview Ben was shown:** the STEP 1 panel of `sheet2_plot.png`, `sheet2_hub.png` and
  `sheet2_aerial.png` in the mock's `out/` folder.

**Review rulings (roblox-reviewer, 2026-10-02: no Critical, one Warning; all taken, text in
INTERFACES):**
- Roads are left out, with one warning, if `roads.lift` is not lower than `hub.surround.height`.
- The new work cannot stop the server boot: the sky, and the ring and roads, each run guarded. A
  failure warns and costs only that feature.
- `PlotService` resolves the `Landscape` module inside `buildWorld`, not at module scope.
- A road's inner end is closed against the hub wall.

**Open for the Studio look (config only, no code):**
- The haze values are a first guess that cannot be checked offline. The target is about 20% at
  500 studs, so the far side of the ring stays readable. **One tuning round is expected.**
- With `glare` 0, `decay` may have no visible effect. If the sky shows no blue fall-off, raise
  `glare` slightly before re-tuning `decay`.
- `lift` 0.1 is the only separation between a road and the ground. If a far road shimmers, raise
  `lift` and `hub.surround.height` together.

**Status (wave 1):** built, **checks green** (2026-10-02), committed on `m13-valley` (`7389467`,
`1d5cfcc`, `fef4b1c`). Merged into `main` with wave 2 on 2026-10-02.
- **Ben's Studio look, 2026-10-02:** one screenshot with the green ground, the roads and the haze
  all showing, and no complaint.
- He gave **no haze letter** and did **not formally sign off** the wave 1 checklist. The wave 2
  playtest asks the haze questions again.
- The wave 1 PLAYTEST section is kept as a record. The current build shows wave 2, so nobody runs
  it now.
- The wave 1 look is still what the game shows when the Valley meshes cannot be used (see "Baked
  for 10 plots" below).

Checks run by qa-runner on 2026-10-02, all passing: stylua, selene (only the known
`LegacyPanel.luau:200` warning), luau-lsp on both trees, both `rojo build`s, `sim_economy`,
`sim_combat`, `sim_range`, `gen_asset_manifest --check`, `fabric.py check Village` and
`cityfabric.py selftest`. `streetplan.py` (0 violations), `bake.py --era Village --list` and
`gen_templates.py --check` were held back while the Boomtown session ran the asset pipeline and
run by the lead once it finished, also on 2026-10-02: all green. (`streetplan.py` was given
`--out-dir` to a scratch folder so it did not overwrite that session's pictures in
`assets/testfit/out`.)

**Wave 2 — the Valley meshes**

**Shipped (wave 2, 2026-10-02; commits `3f2e863` code, tools, generator and `Valley.json`,
`6f1c415` uploaded, `e33d87f` harvested, `2179a21` templates and manifest):**
- **Generator:** `tools/world/valley.py` (with `valleyland.py`, `valleyprops.py`, `wgeom.py` and
  the art numbers in `tools/world/Valley.plan.json`), plus `tools/worldplan.py`, the Python mirror
  of `WorldPlan.Ring`.
  - Deterministic: two builds give byte-identical files.
  - Gates: `py tools/world/valley.py check` and `py tools/worldplan.py selftest`.
  - It writes the GLBs, the palette and the bake record under `assets/build/world/`, and
    `src/shared/Config/Valley.json` (generated; never hand-edit it).
- **28 meshes, 131,768 triangles, one palette image:**

  | Meshes | What |
  |---|---|
  | `Basin_1..2` (required) | the flat ground overlay: meadow, patches, earth ring, bent dirt roads, river and pond bed |
  | `Mountains_1..4` | foothills, mountains and far hills, one per world quadrant |
  | `Forest_1..6` | pines on the foothills |
  | `Groves`, `Details` | tree clumps between the roads; stepping stones, hub kerb and bollards, flowers and tufts |
  | `RiverBed`, `Water`, `Waterfall` | the bed repeated above the aprons in the two river gaps; the see-through water sheet; the two-tier fall |
  | `Bridge_1..4` | plank deck, ramps and rails |
  | `Clouds_1..4` | flat low-poly clusters |
  | `ApronInner`, `ApronOuter`, `Entrance` | per plot: two gravel bands tinted by era, and two short fence runs at the road |
- **World pipeline** (a copy of the baked-paths route):
  - `tools/assets/upload_world.py` (new);
  - `harvest.py` kinds `worldMesh` and `worldTexture`, with a check of each harvested size against
    the bake;
  - `gen_templates.py --world`, and a "World" table in `gen_asset_manifest.py`;
  - a `world` block in `Assets.json`, serialised by `assets_config.py`.
- **Templates:** 28 in `templates/_world/Valley/`, mapped to `ServerStorage.Assets.World.Valley`.
- **Server, mesh mode in `Landscape`:**
  - on when `Valley.json` exists, the template set exists, `plotCount` matches the ring and every
    required mesh has a template;
  - clones the world meshes once into `Workspace.Landscape.Valley`, and the aprons and entrance
    once per plot (`Landscape.AttachPlot`, the only PlotService change);
  - apron bands take the colour of the plot's era from `World.json` `valley.aprons`, and follow
    `EraName` when it changes;
  - builds the collision as invisible Parts under `Workspace.Landscape.Collision`: a wall of 36
    slabs at radius 358.9 and 160 studs tall, 4 bridges (a solid deck and two ramps each) and 7
    stepping stones;
  - builds **no** road Parts and **no** earth-ring Part: both are baked into the basin mesh.
- **Client:** `src/client/City/WorldBlock.luau` and a hook in `Fabric.luau`: no skirt tree, rock
  or bird flock centre stands in the river.
- **Config:** `World.json` gains a `valley` block (wall, apron colours per era, `skirtMargin`).
  `Catalog.GetValleyPlan` and the Valley types are new. No remote, profile, economy or balance
  change.

**Design facts (wave 2):**
- **The floor is flat and collision is Parts only.** The `Ground` Part stays the only floor. Every
  mesh is visual. The plots keep their 1-stud kerb (no ramp).
- **The river is not carved.** It is a coloured bed under a see-through water sheet 0.35 studs
  above the ground, so a player wades ankle-deep and never swims.
- **Solid:** the wall, the bridge decks and ramps, the stepping stones. **Walk-through:** trees,
  rocks, fences, bridge rails and every other mesh.
- **Behind the wall:** mountains, forest, lake and waterfall. The foothills start at radius 362.3.
- **Stacking above the ground top:** basin 0.10, aprons 0.16, river bed 0.22, water 0.35, bridge
  deck 0.70.
- **Sizes:** the tallest summit is 310.5 studs, at radius 722.6. The terrain ends at radius 1,400.
  Clouds stand 900 to 1,260 studs out.
- **Roads bend gently.** They still end at the hub and at the centre of each plot's front edge.
- **Baked for 10 plots.** `Valley.json` records `plotCount`. On any other ring the server warns
  once and builds the wave 1 look.
- **Everything degrades to wave 1:** no `Valley.json`, no templates, a `plotCount` mismatch or a
  missing required mesh. A missing optional mesh is left out and named in one warning.

**Preview gate (lead, 2026-10-02):** the baked GLBs were rendered from the mock's cameras with
back-face culling on, compared with the A2 renders and accepted (`sheetV_*.png` in the mock's
`out/` folder, A2 | baked). Rulings from it:
- Aprons are **light era gravel in two flat bands**. The dark base colour bleeding outward read as
  scorch marks.
- No signposts: each plot already has its Sign.
- `RiverBed` was added, because both neighbours' aprons lay over the painted bed in the two river
  gaps.
- The meadow's facet contrast was halved (the mosaic read as a pattern).
- Known and accepted: trees and boulders inside the wall do not collide; a straight seam shows
  where two aprons meet at the inner corners; the terrain's outer edge is visible from high above.

**Upload and harvest (done 2026-10-02):**
- Trial upload of 2 meshes first: `Details` (most triangles) and `Mountains_3` (largest box,
  1,444 studs). Then the batch.
- All 28 meshes and the palette were accepted first try.
- Ben's **one harvest paste** was merged at once. Every mesh's harvested size matched the bake, so
  Roblox rescaled nothing.
- `docs/ASSET_MANIFEST.md` was regenerated by the lead (the "World" table).

**Open for the Studio playtest** (things only Studio can show; PLAYTEST asks each one plainly):
- **Low graphics quality:** are the mountains and the forest still drawn? If far meshes vanish on
  weak devices, that is a design change, not a tuning number.
- **Water sheet:** water over the bed, or flicker, or the bed hidden.
- **Flicker between the stacked flat layers**, far away at a low angle, most of all on the phone
  emulator.
- **Bridge ramps:** up, across and down, or a ramp built backwards.
- **Haze over the mountains:** do the peaks still read? The wave 1 haze values are untuned.
- **Frame rate** against before M13.

**Status (wave 2):** built, uploaded, harvested, templated, reviewed, **checks green**
(2026-10-02), committed on `m13-valley`. **Ben approved it in Studio on 2026-10-02
("approved!")**, with no letters, screenshots or step results from the checklist
(`docs/PLAYTEST.md` "M13 wave 2 — The Valley: mountains, river, bridges"), so the Studio-only
questions (lowest graphics level, phone, water, flicker, haze) have no recorded answer. Merged
into `main` the same day.

**Review (roblox-reviewer, 2026-10-02): no Critical, two Warnings, both taken.** Placement, wall,
bridge decks and wedges, stones, aprons, the client rule and the Rojo mapping were verified
against the real templates and data. Rulings (INTERFACES "Review rulings" under wave 2):
- Mesh mode also needs the `valley` config and a wall that can be built; otherwise wave 1.
- `Valley.json planHash` must equal `Assets.json world.Valley.planHash`. The server checks it and
  so does `valley.py check`, so a re-bake that was never uploaded falls back to wave 1 and turns
  QA red. `World.json` `ground`, `hub`, `roads` and `valley.wall.segments` are in the hash:
  **changing them needs a re-bake, an upload and a harvest paste.**
- A bridge or stone collider is built only when its mesh was placed.

**Checks (qa-runner, 2026-10-02), all passing:** stylua, selene (only the known
`LegacyPanel.luau:200` warning), luau-lsp on both trees, both `rojo build`s, `sim_economy`,
`sim_combat`, `sim_range`, `worldplan.py selftest`, `valley.py check`, `gen_templates.py --check`
(355 templates), `gen_asset_manifest.py --check`, `fabric.py check Village`,
`cityfabric.py selftest`, `bake.py --era Village --list`, `streetplan.py` (0 violations, with
`--out-dir` to scratch) and `upload_world.py --dry-run` (0 pending).

**Known follow-ups:**
- **lead (known cost):** the meshes are baked for 10 plots. When `m11-unlocks` (6 plots) merges,
  the Valley must be regenerated and re-uploaded: **one more harvest paste** by Ben. Until then a
  6-plot ring shows the wave 1 look, with one warning.
- **lead:** tune the haze in `World.json` from Ben's screenshots (PLAYTEST M13 wave 2 step 22).
  The `lighting` block exists for this round if the haze alone is not enough.
- **lead:** `tools/testfit/plotrender.py` still draws the ground outside a plot as the darkened
  plot colour. Update it after `m12-boomtown` merges (that branch edits the same files).
- **lead:** `tools/marketing/SHOTLIST.md` item 4 says the game uses the default Lighting. That is
  no longer true; correct it before the next thumbnail shoot.
- **lead:** the client's river rule for skirt entries is deliberately **not** mirrored in
  `tools/cityfabric.py` or `plotrender.py` (a single-plot render does not know where the plot
  sits in the world). This is the one sanctioned difference between the mirror and the client.
- **lead (at the `m12-boomtown` merge):**
  - any new list that carries `skirt` entries needs the same river gate;
  - `tools/assets/assets_config.py` from this branch must be in place before any uploader or
    harvest runs on the merged tree. An older copy erases the `world` block of `Assets.json`.
- **lead:** the server has no load gate for the Valley, so meshes may pop in for a moment on
  join.
- **lead:** a road still ends at the plot's front face, and each era's first street starts
  further in: 3.5 studs (Village), 5.5 (Boomtown), 11 (Metropolis, Orbital). Wave 2 added the
  fence runs but no ground ramp. Open until Ben says how the entrance reads.
- **Closed by wave 2:** the scorch-mark aprons (now two light gravel bands); the Python mirror of
  `WorldPlan` (`tools/worldplan.py`).

**After the playtest:**
- A tuning round. Haze, wall and apron colours are `World.json` numbers. Anything in the meshes
  goes back through the generator and the pipeline.
- If far meshes vanish at low graphics quality: a design decision for Ben, before any tuning.
- Then the merge into `main`, the lead's call on timing against `m12-boomtown` and `m11-unlocks`.

- [x] Wave 1 built, review rulings taken (2026-10-02)
- [x] lead: checks green for wave 1 (2026-10-02, every gate)
- [x] lead: commit wave 1
- [x] Ben saw wave 1 in Studio (2026-10-02, one screenshot; no formal sign-off, no haze letter)
- [x] Wave 2 built, uploaded, harvested (one paste) and templated (2026-10-02)
- [x] lead: wave 2 review rulings taken and checks green (2026-10-02)
- [x] Ben's Studio playtest: "approved!" (2026-10-02; no checklist answers given)
- [~] lead: tuning round — nothing asked for; the haze is still the wave 1 first guess, and the
  low-graphics and phone questions are unanswered
- [ ] lead: re-bake for 6 plots when `m11-unlocks` merges (one more harvest paste)
- [x] lead: merge `m13-valley` into `main` (2026-10-02)
