# L3 W1 fix round 2: luau-engineer (F1 to F7)

Worktree `C:\Users\benja\Desktop\tycoon-p5`, branch `l3-armory`. Nothing is committed. The tracked `build/*.rbxl`
files and sourcemaps were already modified by QA when I started; I left them. `tycoon-p5b` was not touched.

## Rulings, and what I did

- **F1 (m1): the text checks pin what feeds each pinned call, and that it is reached.**
  - `run_harness.py` gains 53 counts and `tests_l3.luau` `L3.LINES` holds each one (90 keys in all).
    - The input lines the review's probes broke are pinned in the body they live in: the profile and `combat` reads
      in `gearOf` and in `damageScale`, `held` from the shooter (with the saved loadout over the starters), the
      override reads, each slot's own Ascension (`scaleLevel`, `gearAscensionOut`), DataService's
      `runMigrations(profile.Data, player)` in `attemptLoad`, GrantStars' level read, DebugService's star
      difficulty (and its ladder, levels, players and call), and SavedPower's `weapons` and `starters` arguments
      in Main's `sendSnapshot` and in `computeGearPower`, with the config reads that feed them.
    - The guards in front of each pinned call are pinned too: `if state.mode == "range" or armoryConfig == nil` in
      `gearOf`, both early returns of `damageScale`, the hub's `armoryConfig == nil` return, grantStar's two.
      An `if true then` there would leave every count but the guard's unchanged.
    - `loadMigrates` is the call held between its two neighbouring lines, so it cannot be wrapped in an `if`
      unseen.
  - **Exits.** A new `L3_PATTERNS` table counts `return`, `continue` and `break` in a body, on the code with its
    comments blanked: `gearOf` 2 and `damageScale` 3 as ruled. I also count the bodies of every other pinned call:
    `GrantFirstClear` 3, `GrantStars` 4, `grantStar` 2, `sendSnapshot` 1, `computeGearPower` 2, `attemptLoad` 5
    (its session hook's own `return` included), `grantStarTo` 4, `fileFirstClear` 1.
  - **The count-0 checks are robust to spelling.** They moved from plain text to patterns in `L3_PATTERNS`, read
    by the new `luau_code(source)`. That function blanks every comment (line and long) and keeps every string, so
    a comment never counts and a spelling inside a string the code runs does.
    - `debugLiteral`, `hubLiteral`: any `"*"`, `'*'`, `` `*` `` or `[[*]]` literal. This covers the reversed
      compare and a local alias.
    - `hubFrozenGear`: `.gear` or `["gear"]` (never a `..` before a local named gear).
    - `runnerSteps`: the word `Migrations` (not `runMigrations`), so `local m = ProfileSchema.Migrations` fails.
    - `mainGearOf`: the word `GearOf`, so `WeaponService["GearOf"]` fails.
  - `mainPower` is now counted in `sendSnapshot`'s body, not the whole file. `leverReward`'s text follows F3.
  - 74 new `mutate.py` entries (`L3_FIX2_MUTATIONS`, labels `l3fix2 …`): the review's eleven probes verbatim, one
    or more for every other new count, one per spelling the review named, and the F2 and F5 entries below. Two
    existing entries were re-aimed for F3 (`l3fix R4: a lever star reads no reward`, `… pays the Normal reward`).
- **F2 (m2): the hub's star lever pays the first-clear reward too.**
  - `Unlocks.ApplyFirstClear(combat, reward, weapons, starters): Types.FirstClearGrant` holds the write.
    - The family is written unless it is not a string, not a family of `weapons`, or already owned. A starter is
      owned through `OwnsFamily`, so it is never written (L2-1).
    - The Valor is added when it is a whole number above 0.
    - It returns what it gave, `{ family = nil, valor = 0 }` for nothing. A reward that is no table gives nothing.
  - `UnlockService.GrantFirstClear` calls it and keeps the warn for a family that is no family to give.
  - The hub's `ArmoryService.grantStarTo` now does this:
    - It reads `difficulties[starDifficulty].firstClear` from the level file through `Catalog.GetLevelFile`, in the
      new `fileFirstClear`, for each NEW star only. An old star pays nothing.
    - It pays through `ApplyFirstClear` and marks `combat` dirty as before.
    - Its warn (the hub's only notice) names what was given, as the dungeon's does:
      `grantStar: <name> holds the hard star of forestRoad · Warhammer`.
    - It is Studio only, as the lever is.
  - The hub passes the file's raw entry. `ApplyFirstClear` refuses everything `StageFlow.FirstClear` leaves out,
    so the hub's reading and the dungeon's agree.
    - A test proves it on 12 raw shapes: the grant and the profile after are the same either way.
    - So `StageFlow.FirstClear` stays where it is, and its mirror and its mutants are untouched.
  - The tests are the new `tests_l3` group "l3 firstClearTests" (12 checks):
    - fresh, a family and Valor, owned, a starter, Valor only, an unknown family;
    - a profile with no families map, no weapons config;
    - seven refused Valors, four refused family shapes, a reward that is no table (no throw);
    - and the raw-against-FirstClear comparison above.
- **F3 (s1).** `GrantStars` resolves the level first. A level that does not resolve hits `continue` before
  `StageFlow.Award`, so it gets neither a star nor a reward. The reward line reads it plain. Pinned by `leverLevel`
  (the resolve, the guard and the Award in that order), with a mutant for the old order.
- **F4 (s2).**
  - `Armory.luau`'s header now says the mirror is function for function "three aside", and names `StrikeTier`,
    `HeldFamily` and `SavedPower` with the reason for each.
  - `check_stage_mirror.py` has `ARMORY_UNMIRRORED` with the same reasons and prints them in a note. A listed name
    that is no longer an Armory export fails the run, so the list cannot go stale. I proved that once from a
    copy with `SavedPower` misspelled: `FAIL (1)`, "Armory.SavedPowr is listed as deliberately unmirrored but is
    not in the Luau".
  - A second note lists the Armory exports not compared there (the slot ladder, `Upgrade`, the forge).
- **F5 (s4).**
  - `UIController`'s `refreshCombatKeys` remembers whether the families were missing. The first time it finds them
    with a model whose `combat` is a profile, it replays `pushArmory(model.state.combat)`.
  - `pushArmory` is now forward-declared. When the families are missing it calls `refreshCombatKeys` and returns,
    so a push is never made twice.
  - Read as text too: `uiWaiting`, `uiReplay`, `uiPushWaits`, each with a mutant.
- **F6 (s5).** `sim_range`'s gate is judged per fire course.
  - A course that never casts fails by name, unless its spot is in the new `BREATH_OUT_OF_REACH` for that
    difficulty.
  - A listed course is held to its reason instead: no run casts, and no living body's edge ever comes within
    Dragon's Breath's reach (range 20 + pad 0.8). A listing that has gone stale fails too.
  - `breath_step` records the nearest body's edge each time it is asked. It only watches, so no number moved.
  - **Why CaveMouth cannot cast** (measured on both difficulties, both of its points, every seed):
    - It stands on Road4 at the ground (y 0), west of the height-8 plateau camp A stands on.
    - The residents who come for him stop at the plateau's west edge, x about -300 (he is not reachable, L1b-W4).
    - So the nearest body's edge stays 25.7 to 27.2 studs off on the flat, past the 20.8 the ability reaches.
    - Making it cast would need a layout or ability change. That is not mine, so it is listed.
  - Two `check_levels_mutants.py` SIM_CASES prove the rule, each in one run:
    - "F6: CaveMouth out of BREATH_OUT_OF_REACH": its courses go red by name. The pooled rule passed them on
      CaveExit's casts.
    - "F6: CaveExit listed … though it casts": red as a stale listing.
- **F7.** `tests_l3.luau` is stylua-formatted. Stylua needed three passes to settle (it is not idempotent on one
  nested call); `stylua --check` is clean now.
- **Not fixed (s3)**, as ruled: nothing done.

## Files changed

- `src/shared/Unlocks.luau`: `ApplyFirstClear`.
- `src/shared/Armory.luau`: the header only.
- `src/combat/server/Services/UnlockService.luau`: `GrantFirstClear` calls `ApplyFirstClear`; header line.
- `src/combat/server/Services/WaveService.luau`: `GrantStars` (F3).
- `src/server/Services/ArmoryService.luau`: `fileFirstClear`, `grantStarTo` (F2).
- `src/client/Controllers/UIController.luau`: `refreshCombatKeys` and `pushArmory` (F5).
- `tools/crowd_harness/run_harness.py`: `L3_BODIES` (8 more bodies), `L3_LINES`, `L3_PATTERNS`, `luau_code`,
  `l3_reading`, docstring.
- `tools/crowd_harness/tests_l3.luau`: "l3 firstClearTests", `L3.LINES`, header; stylua.
- `tools/crowd_harness/mutate.py`: `L3_FIX2_MUTATIONS` (74), two re-aimed entries, `UIController` into `FILES`.
- `tools/check_stage_mirror.py`: `ARMORY_UNMIRRORED`, the stale check, two notes, docstring.
- `tools/sim_range.py`: `BREATH_OUT_OF_REACH`, `breath_step`'s `nearest`, the per-spot gate.
- `tools/check_levels_mutants.py`: two F6 SIM_CASES, docstring.

## Contracts

```luau
Unlocks.ApplyFirstClear(
	combat: Types.CombatProfile,
	reward: Types.LevelFirstClear,
	weapons: { [string]: Types.RangeWeaponDef }?,
	starters: { [string]: boolean }
): Types.FirstClearGrant
```

No remote, config key or type changed. `UnlockService.GrantFirstClear` and `WaveService.GrantStars` keep their
signatures.

## Gates (all on the final tree unless noted)

| Gate | Result |
|---|---|
| stylua `--check` on every changed Luau file | clean |
| selene on the changed `src` files | 0 errors, 0 warnings |
| selene on `tests_l3.luau` | 375 `undefined_variable` only: the bundle's shared locals (`check`, `load`, `L1`, `FIXTURES`). A harness file is not linted standalone; HEAD's copy, linted from scratch, gives 356, and the new group adds the rest |
| luau-lsp analyze, hub (`src/client src/server src/shared`) and combat (`src/combat src/shared`), fresh relative sourcemaps in scratch, `tools/types/globalTypes.d.luau` | no diagnostics, exit 0 both |
| `py tools/check_compile.py` | `CHECK: PASS -- 178 files` |
| `rojo build` both projects (to scratch) | built |
| Harness (`run_harness.py … luau.exe`) | `HARNESS: PASS (3,719 checks)` (was 3,654) |
| `check_stage_mirror.py --luau …` | `CHECK: PASS`, with the F4 notes |
| `mutate.py "l3fix2"` | `MUTATIONS: 74 run, 0 not caught` |
| `mutate.py "files:Unlocks.luau,Armory.luau,UnlockService.luau,WaveService.luau,ArmoryService.luau,UIController.luau"` | `MUTATIONS: 169 run, 0 not caught` (baseline `HARNESS: PASS (3,719 checks)`) |
| `py -3.12 tools/check_levels.py` | `CHECK: PASS` |
| `py -3.12 tools/sim_range.py --check --levels-only --level forest` (64-bit) | `CHECK (levels only): PASS`, 163 PASS lines, 0 FAIL (157 before: the two pooled lines became eight per-course lines) |
| `py -3.12 tools/check_levels_mutants.py --only "F6: CaveMouth"` and `--only "F6: CaveExit"` | `MUTANTS: PASS`, each red as expected (`FAIL (4)`: two courses on two difficulties) |

Of the review's 19 probes, the 11 m1 regressions are now `mutate.py` entries and every one is caught. One of the 3
low-value probes is also caught now: GrantStars resolving at Normal (`leverLevel`). Two are left as the review rated
them: DataService's warn branch and SavedPower's NaN guard.

## Assumptions

- The hub reads the level file's raw `firstClear` and relies on `ApplyFirstClear` to refuse what
  `StageFlow.FirstClear` drops. `StageFlow.FirstClear` itself did not move: a test pins the two readings equal.
- "The hub notice" is the hub's Output warn. The hub has no notice remote, and I added none.
- `ApplyFirstClear`'s `type(family) == "string"` guard has no mutant. Removing it changes nothing a `weapons`
  table keyed by strings can show, so its mutant would be equivalent. The same goes for the dropped
  `valor < math.huge`, since `% 1` refuses both infinities.
- After F3, DebugService's notice still names every level asked for, even one that did not resolve (Studio only;
  `readLevel` warns in Output). I left it.

## Required changes outside my files

- `docs/BALANCE.md:6423`: the row "R2: the fire sniper casts at least once … — (6 casts on each difficulty)"
  should read "judged per course (F6): CaveExit's two courses cast on each difficulty; CaveMouth's never can,
  listed in `sim_range.BREATH_OUT_OF_REACH` (nearest body 25.7 studs, reach 20.8)" (docs-keeper or designer).
- `src/shared/Types.luau:999-1001` (optional comment): "Only the combat place writes them" should add "(and the
  hub's Studio star lever, `families` through `Unlocks.ApplyFirstClear`)".
- PLAYTEST (lead, docs-keeper): the hub strip's "★ Hard" now pays the Warhammer as the dungeon's U does, and a
  later Hard clear then pays nothing new. Add the s3 gamepad note as ruled.

## What to check in Studio

- Hub, Studio API access on:
  1. Press the strip's ★ (or set `DebugGrantStar` to `*`). Output names the Warhammer. The Armory shows it owned
     and the T4 cost line opens.
  2. Press ★ again: Output names nothing new.
  3. In the dungeon, a Hard clear then shows no new star and no Warhammer on the card.
- Hub with a slow Config replication (hard to force): the Armory key appears and the screen opens with the wallet
  filled. A normal boot must not change.
- Dungeon: U behaves as before on Forest Road (the Hard star and the Warhammer, once). A level that does not resolve now
  gets no star either (Output warns from `readLevel`).
