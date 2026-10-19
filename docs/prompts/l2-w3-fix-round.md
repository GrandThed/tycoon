# L2 W3 fix round (lead's rulings, 2026-10-19)

Findings: `docs/prompts/l2-w3-review/server.md` (s-M1, s-m1, s-s1..s3), `client.md` (c-m1..m4, c-s1, c-s2),
`data-tools.md` (d-m1..m6, three suggestions), plus the queued Q1–Q4 in `docs/prompts/l2-w3-contract.md` §14.
Read the file(s) for your slice in full and the contract (§13, §14). Branch `l2-w3` in `C:\Users\benja\Desktop\tycoon-p5`.

## Rulings

- **s-M1 + Q3 (falls land on the road):** the rescue judges a fall by where the member last stood (the last
  grounded position the server saw), not only by the current position: a walk-off or a dash-off from the ice,
  the bridge or the bank lands on that water's `landing`. Any deep (non-colliding) water block may carry a
  `landing`; CreekUp lands on Road2 by the creek. Harness cases (walk-off 9 studs out, dash-off 29 out, a fall
  far from any water still goes to the checkpoint), Validate + mirror, a check_levels line.
- **Q1:** phone auto-swing at water uses `controls.iceAutoDegrees` (60, config) — narrower than the swing, can
  only remove swings. **c-m4:** no auto-swing at water while airborne.
- **Q2:** frozen cells keep normal grip (no Ice-material slide). **Q4 + c-s1:** Frost Quake draws the configured
  ring count; shards scale with the ring's circumference and are dropped where no floor is under them.
- **c-m1 + c-s2:** the client's water test caches each cell's box on adoption, keeps an unfrozen list updated
  from the `Ice` signal, returns early when the player is far from the ice's bounding rectangle, and the
  iterator can stop early. Report the cost per frame before/after.
- **c-m2:** ghosts are keyed by the swing's `seq`, dropped on that seq's refusal, otherwise held until the
  strike arrives plus a short grace, with a safety cap.
- **c-m3:** one pure `WorldReact.SwingStrike(variant, step, origin, heading)` built by the server's
  `resolveMelee` and by both client copies; harness cases and mutants.
- **s-m1 + d-m5:** the ice-applying lines (iceOf, the React guard, the `Ice` attribute, the frozen transparency,
  the `react ~= "ice"` filter, the `reachDown`/`ahead` reads) are covered: move logic into pure functions the
  harness loads where possible, otherwise source checks; one mutant each.
- **s-s2:** ice footprints may touch but not overlap (Validate + check_levels + mirror). **s-s3:** the `Ice`
  attribute name is exported once from `WorldReact`. **s-s1:** record as a known limit in the report (cover
  counts colliding blocks and secrets by their top).
- **d-m1 (unfreezable slits):** a cell is skipped only when a cover holds all of it; a gate that frozen pieces
  plus covers fill each ice block; harness + mutants re-aimed.
- **d-m2:** `FAMILY_TARGETS.frostHammer` set to the measured rows. **d-m3:** Leap Smash reach gets its fall
  term (+ mutant). **d-m4:** an "island at 48" mutant proves the walk-off grace term. **d-m6:** ice thickness 4
  (config) and "ice" judged by the floor-depth rule in the frozen check.
- **Suggestions taken:** `dashing_abilities` follows `MECHANICS.x = MECHANICS.y` aliases; the frozen layout is
  also run through the bend rule, the cave's sealed-air rule and the walled-camp gate; the shrine pays 60 Timber.

## Owners (disjoint)

- **Server agent (luau-engineer):** `src/shared/WorldReact.luau`, `Types.luau`, `src/combat/server/Services/
  LevelGeometry.luau`, `LevelService.luau`, `StageFlow.luau`, `WaveService.luau`, `WeaponService.luau`,
  `tools/crowd_harness/**`, `tools/check_stage_mirror.py`. (s-M1/Q3 code, Q2, c-m3 server half and the pure
  function, s-m1, d-m5, s-s2 Validate, s-s3, d-m1 code.)
- **Client agent (ui-engineer):** `src/combat/client/**`, `src/client/UI/Theme.luau`. (Q1, c-m4, Q4, c-s1, c-m1,
  c-s2, c-m2, c-m3 client half.) Code against the server agent's `SwingStrike` and `Ice` name as they land.
- **Data agent (economy-designer):** `src/shared/Config/ProvingGrounds.json` (`controls.iceAutoDegrees`),
  `Combat.json` (ice thickness, any rescue key), `Config/Levels/1_ForestRoad.json` (shrine 60),
  `Layouts/Levels/ForestRoad.json` (CreekUp landing), `tools/check_levels.py`, `tools/check_levels_mutants.py`,
  `tools/sim_range.py`, `docs/BALANCE.md`. (Q3 data and checks, d-m1 mirror and gate, d-m2..d-m4, d-m6, s-s2
  check, the three suggestions, the s-M1 check_levels line.)

Each agent: `git status`/`git diff` first; commit nothing; kill only your own PIDs; scratch scripts in your own
scratchpad subfolder, Python with `py -I`; changes needed in another's files go in your report. Report to
`docs/prompts/l2-w3-reports/fix-<server|client|data>.md`. Gates as the contract §10 for your role (harness
`py tools/crowd_harness/run_harness.py C:/Users/benja/Desktop/tycoon-p5 C:/Users/benja/Desktop/tycoon/tools/bin/luau.exe`,
filtered mutate + stale count, check_levels + mutants with --only then one full run, check_stage_mirror,
`py -3.12` sim_range --check, check_compile, stylua, selene, luau-lsp).
