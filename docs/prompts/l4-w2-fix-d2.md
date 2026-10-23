# L4 W2 fix round — D2's work list (the lead's routing)

You are D2 for the fix round (`docs/prompts/l4-w2-fix-round.md`: yours are K7's pins, K10, K5's offline half, and every
relay below). The four engineers and D1 have finished; their reports are in `docs/prompts/l4-w2-fix-reports/`
(`luau-a.md` with its "Follow-up: K3's server half", `ui-a.md`, `ui-b.md`, `d1.md`). Read each one's "For the other
owners" section and apply it; this list is the lead's index, the reports hold the exact texts.

1. **luau-engineer A (K7, K3):** re-aim the 19 failing `source.l4w2` pins (18 K7 + `pushPrewarm`); flip `dressThenHash`
   (DressHash before Dress now); the new whole-line pins on the deciding lines (LevelService, LevelDress), the
   `refreshLobbyKinds` / `Boot` pins and the order pin `refreshLobbyKinds()` before `broadcast()`; re-aim the five stale
   mutate entries (four now live in LevelDress and are test-caught); paste `K7_A_MUTATIONS` (39), `K7_PIN_MUTATIONS` (25),
   `K3_A_MUTATIONS` (5), `K3_PIN_MUTATIONS` (8). The WeaponService `restDrop` pin (`:828`) is still owed.
2. **ui-engineer A (K7 client, K8, K9):** `run_harness.py` SOURCES gains `"ScenePlan": "src/combat/client/Controllers/
   ScenePlan.luau",` after `LevelDress`; TESTS gains `"tests_l4w2_scenery.luau",` **last** (it ends with the verdict line);
   the pins for the four `seal` flags, the fail path in order, `showChild`, the build pcall lines,
   `task.spawn(build, ...)` (and `task.spawn(buildSteps` at count 0), `evaluate`'s Decide, `builtKey`, `SetDressed`,
   `awaitLoaded`, the K8 lines, CameraController's `\t\tand not levelDressed` and `\tlevelDressed = dressed`; its 17
   ScenePlan mutate entries. Also add `ScenePlan.luau` and `CameraController.luau` to `mutate.py` FILES if needed.
3. **ui-engineer B (K1-K5):** `check_raider_mirror.py` gains the `slide` and `anchor[1..12]` fields and a `Lean` case plus
   ui B's six mutants (four proven red); the K7 pins on the InputController drop lines (653, 664-665, 681-682, 761-762;
   the last two pairs occur twice: pin the count) and CrowdRenderer's ForEach line (3063); run `mutate.py` filtered to
   `files:InputController.luau,CombatUIController.luau`; `tools/assets/raider_kit.py` lines ~188 and ~565 get the new
   fodder and Chief arm keys (or the next generator run brings the old ones back: prove with a dry generation that the
   config's keys come out unchanged, no merge, no upload); `tools/testfit/raiderview.py` line ~624 uses
   `rp.head_rule_offset`, then re-render the fodder strip (`assets/testfit/out/Raiders/RaiderFodder_strip.png`).
4. **D1 (K6, K2, seat):** its new R8 SIM_CASE (sized to the faithful margin) into `check_levels_mutants.py`, keeping the
   two clock cases; the Chief's sweep range 12.7 / reach ≤ 12.7 lands in `ProvingGrounds.json` (D1's), so re-run
   `raiderpose.py --check` (every row must pass now) and `check_levels.py` (camp C's sight gate reads the posed reach);
   the SeatStep comparison D1 added to `check_stage_mirror.py` may need a mirror mutant (`mirror_mutants.py`).
5. **The lead's edits:** `src/shared/Tuning.luau` (two NON_NEGATIVE_PATHS lines, already relayed in W2's first pass),
   `src/combat/client/Controllers/HeldWeapons.luau` (`SHOWN_STAGE` now reads `Theme.COMBAT_WEAPON_SHOWN_STAGE`; no pin
   reads it).
6. **Yours from the rulings:** K10 (`walled_bodies` takes the largest drawn reach over every kind sharing a post);
   K5's offline half (`raider_frames.py` asserts each kind's head point is `(0, height - headRadius, 0)` within 0.01).

**Done:** the harness passes (name the count); `check_raider_mirror.py` and its mutants pass; `raiderpose.py --check` and
`raider_frames.py --check --require-harvest` exit 0; `check_levels.py` passes; `check_stage_mirror.py` and
`mirror_mutants.py` pass; `forest.py check` passes; `mutate.py` filtered to every file changed in the fix round reads 0 not
caught and the stale check over all entries reads 0 stale; every review probe named in the fix round is caught (by a test,
a pin or a mutant: name which). Report: `docs/prompts/l4-w2-fix-reports/d2.md`.

## Added after D1's report

7. **D1's relays** (exact texts in `d1.md`): the `seatStep` op in `stage_mirror.luau` (until it lands `check_stage_mirror.py`
   fails that one row); two `mirror_mutants.py` entries (SeatStep at twice the pace; with no pace it never moves); the K6
   SIM_CASE in `check_levels_mutants.py`, and `--r8-gate-only` appended to the two clock cases. The Chief's sweep is now
   range 12.7 / reach 10.5 in `ProvingGrounds.json`: re-run `raiderpose.py --check` and `check_levels.py`.
8. **The plan hash depends on the Python that runs `forest.py`** (D1: `forest.py check` passes under plain `py`, i.e. 3.14
   32-bit, and reports the hash stale under `py -3.12`). The shipped hash `23851a6f417491c1` was made by one of them and
   both `Config/LevelDress/ForestRoad.json` and `Assets.json levels.ForestRoad.planHash` hold it, so the game is consistent;
   but a rebuild under the other Python would read as a new plan. Find the cause (float formatting, rounding, dict order)
   and make the hash identical under both Pythons. If that keeps today's value, nothing else moves. If it cannot, write the
   new value into the dress file with `forest.py` and into `Assets.json` only through `assets_config.save_assets` (never by
   hand: a hand save reformats the file), prove nothing re-uploads (`upload_level.py --dry-run` reads 0 pending), and say so.
