# Next-session prompt: M9 city dressing (roads, trees, filler, squares, vehicles)

Paste everything below the line into a fresh Claude Code session at the repo root. Run the
session on Opus; the prompt tells the lead which subagents to use and which to run on Opus.

---

Start milestone **M9 — City dressing**. The contracts are frozen; do not redesign them. Read, in
this order, before delegating anything:

1. `CLAUDE.md` (project rules, memory imports — especially `.claude/memory/city-dressing-2026-09-16.md`).
2. `docs/INTERFACES.md` from the heading `# M9 contracts` to the end. This is the source of truth
   for every file, type, attribute, config key and definition of done.
3. `docs/PLAN.md` "M9" and `docs/SPEC.md` §8 (the "City dressing" bullet).
4. `docs/ASSET_RESEARCH.md` §4 (kit inventory, era kit decision, the "Props and vehicles" note).
5. `src/shared/Config/CityDressing.json` (already committed, v1 values) and
   `src/shared/Layouts/Village.luau` (slot positions the street plan must respect).

Ben's three rulings (2026-09-16), non-negotiable:
- **Client-side only.** The server adds exactly two attributes per plot folder (`EraName`,
  `GrowthTier`); no new remote, no persistence, no balance change in wave 1.
- **No collisions on any dressing part:** `Anchored true`, `CanCollide false`, `CanQuery false`,
  `CanTouch false` — roads, junctions, trees, houses, plazas, lamps, vehicles, all of them.
- **car-kit belongs to Boomtown and Metropolis.** Village uses nature-kit (trees, cart) and
  fantasy-town-kit (filler houses, plaza). Never mix a building kit into the other era.

## Environment (verify first, ~1 minute)

```
$env:PATH = "$HOME\.rokit\bin;$env:PATH"      # PowerShell; Bash: export PATH="$HOME/.rokit/bin:$PATH"
py -V                                          # only `py` works; `python`/`python3` are Store stubs
Test-Path ~/.rokit/bin/rojo.exe
git ls-files --eol | Select-String w/crlf       # must be empty; files the Write tool creates are CRLF — convert to LF
```

Put the PATH line and `py` in every subagent prompt. `luau-lsp analyze` must use the committed
`tools/types/globalTypes.d.luau` and `--sourcemap sourcemap.json` (never let an agent download
definitions). If qa-runner ends without its report, SendMessage it "finish and report"; never treat
a missing report as a pass.

## Wave 1 — fan out in one message, disjoint files (see the M9 ownership table)

Every delegation must include: the INTERFACES sections to read (by heading), the files the agent
owns, the contracts it must conform to, the code rules from `CLAUDE.md`, the environment lines
above, and the definition of done. Subagents have no memory of this conversation.

1. **luau-engineer** — `src/shared/Types.luau` (M9 additions), new pure
   `src/shared/CityGrowth.luau` (`Score`, `TierFor`; no Roblox globals), `Catalog.GetCityDressingConfig`,
   and `PlotService` attributes `EraName`/`GrowthTier` on the plot folder (parent of `Buildings`),
   written only on change, at every path listed in "Server behaviour". Nothing else on the server.
2. **economy-designer** — `streets`, `lots`, `plazas`, `treeZones` (and `spur` overrides where
   needed) in `Layouts/Village.luau` and `Layouts/Boomtown.luau` per the "Layouts" section; a
   top-down `streetplan.png` per era in `assets/testfit/out/<Era>/` for Ben; `tools/sim_economy.py`
   mirrors `CityGrowth` and prints the tier timeline; check the thresholds against the tuning
   target and propose changes to `CityDressing.json` (report them; the lead applies).
3. **pipeline-engineer** (`general-purpose`) — `--props` mode across `tools/assets/*.py` and
   `tools/testfit/{blueprint,testfit}.py`: blueprint root `tools/testfit/blueprints/_props/<Era>/`,
   `Assets.json` v2 `props.<Era>.<PropName>`, templates in `templates/_props/<Era>/` with the
   no-collision flags, Rojo mapping `ReplicatedStorage.Assets.Props` → `templates/_props`
   (optional path), `gen_templates.py --check` covering both roots. Prove it with a fixture
   blueprint end to end in dry-run; `rojo build` must pass with `templates/_props` absent and present.
4. **prop-builder Village** and **prop-builder Boomtown** (`general-purpose`, `model: "opus"`) —
   blueprints in `tools/testfit/blueprints/_props/<Era>/` per the "Props" section. Village:
   `TreeGrowing` (4 stages), `HouseA/B/C`, `PlazaA`, `Cart`. Boomtown: `TreeGrowing`, `HouseA–D`,
   `PlazaA`, `Junction`, `Bend`, `LampPost`, `VehicleA/B/C` (car-kit, `scale 2.5`, front −Z).
   Each blueprint must render clean with `testfit.py`; the builder looks at every strip. Reuse the
   `/build-assets` skill's builder brief for the measured kit facts (`tools/testfit/README.md`).
   Give each builder a distinct scratch filename. Strips go to `assets/testfit/out/<Era>/props/`.
5. **ui-engineer** — `src/client/City/{RoadGraph,Scatter,Traffic}.luau`,
   `src/client/Controllers/CityDressingController.luau`, props preload in `AssetPreloader`,
   registration in `Main.client.luau`, constants in `Theme`. Must work with roads only (no prop
   templates yet), a missing config, and missing templates — silently. One Heartbeat connection
   for all traffic; `BulkMoveTo` once per frame; near/far LOD with hysteresis; dressing in
   `Workspace/CityDressing/Plot<n>`; never touches server folders.

The pipeline-engineer and ui-engineer both need the `Assets.json` v2 `props` shape and the prop
template shape — both are in INTERFACES; neither may change them. If an agent needs a change in
another agent's file, it reports it and you route it.

## After wave 1

1. Show Ben the two `streetplan.png` files and the prop contact sheets before uploading anything.
2. Run `merge_stages.py --props --era <Era>` and `upload_models.py --props --era <Era>` for
   Village and Boomtown (`.env` holds the Open Cloud key; uploads occasionally fail with
   "Unknown Error" — the uploader is idempotent, re-run). Then hand Ben the harvest step
   (`harvest.py --emit --props`, paste `harvest.luau` in the Studio command bar, copy Output,
   `harvest.py --props`), then `gen_templates.py --props`, then commit templates.
3. **roblox-reviewer** on the whole diff. Focus list: no client-built instance can influence
   server state; every dressing part has the three collision flags false (grep it); part budgets
   from the contract; Heartbeat cost; `Random` seeding identical across clients; no constants in code.
4. **qa-runner** with the exact command list (stylua, selene, luau-lsp analyze with the committed
   definitions and sourcemap, `rojo build -o build/test.rbxl`, `py tools/sim_economy.py`,
   `py tools/assets/gen_templates.py --check`). It MUST end with the report.
5. **docs-keeper**: `PLAYTEST.md` M9 section (include the MicroProfiler check for the traffic
   step and the "delete a template, game still runs" check — confirm every failure-path step is
   actually reachable from Studio), `MANUAL_STEPS.md` M9 (harvest paste per era), PLAN ticks,
   regenerate `ASSET_MANIFEST.md` with the props table.
6. Commit in sensible slices (contracts already committed; code; blueprints; templates).

Stop after the playtest hand-off. Wave 2 (Metropolis + OrbitalColony dressing, the `cityDetail`
setting) starts only when Ben says so.

## Report to Ben at the end, in a few lines

What was built, what the reviewer flagged and how it was resolved, the tier timeline from the sim,
and exactly what he must do in Studio: paste the harvest for each era, then the PLAYTEST M9 steps.
