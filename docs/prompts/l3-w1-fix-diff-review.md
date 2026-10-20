# L3 W1 fix diff review (`git diff f6c426d 32d7893`)

Reviewer: roblox-reviewer (fix-diff pass), 2026-10-20. Read only. The rulings are `docs/prompts/l3-w1-fix-round.md`
(R1–R12 and the taken suggestions), the findings `docs/prompts/l3-w1-review/*.md`, the owners' reports
`docs/prompts/l3-w1-fix-reports/`.

**Result: 0 Critical, 0 Major, 2 Minor, 5 Suggestions.** No fix introduced a runtime defect that I could find. Both
Minors are gaps: one in the new gates, one in a sibling lever that R4 did not reach.

## What I ran

Every run used a `git archive 32d7893` copy in my scratchpad. The worktree was only read; `tycoon-p5b` was not touched.

| Gate or probe | Result |
|---|---|
| Harness on the worktree and on the copy | `HARNESS: PASS (3,654 checks)` |
| `check_stage_mirror.py --luau …` | `CHECK: PASS` (`Armory.StarHeld` compared on 5 configs) |
| `mirror_mutants.py --only Armory` | 10 of 10 caught |
| `check_levels.py` | `CHECK: PASS`, including the new R1 trophy rule |
| `sim_combat.py --check` | `CHECK: PASS`, all 23 assertions. Assertion 2: the Flamethrower comes at T2/T2, which is `PAIR_FLAME_GEAR` |
| `sim_range.py --check --levels-only --level forest` (64-bit 3.12) | `CHECK (levels only): PASS` in 19 min 46 s: 157 PASS lines, 0 FAIL. The Flamethrower pair at T2/T2 clears in 3.20 / 3.16 / 3.20 min against a band of 3.04–4.37; seed 23 is 0.12 min above the floor. It earns x1.02 the cash and takes x1.00 the Colossus time. The Frost Hammer rows are reported only: 2.22–2.30 min, x1.83 the cash, bar 290 |
| stylua `--check` and selene on the changed `src` files; `check_compile.py` | clean; 0 / 0 / 0; PASS (178 files) |
| luau-lsp analyze, both trees, fresh sourcemaps in scratch, `tools/types/globalTypes.d.luau` | no diagnostics |
| 19 review-only probe mutants (`probe.py`: one exact-text change, then the harness, then restore) | 5 caught, 14 survive. The 11 that would ship a regression are in m1. The other 3 are low value: DataService's warn branch, SavedPower's NaN guard, and GrantStars resolving the level at Normal, which is equivalent because the reward is still read at `difficulty` |

## Minor

**m1. The new text checks pin each service call, but not the lines that feed its arguments.** Files:
`tools/crowd_harness/run_harness.py:452-513` (`L3_BODIES`, `L3_LINES`) and `tools/crowd_harness/tests_l3.luau`
(`L3.LINES`).

- **What is wrong.**
  - Each L3_LINES entry does fail when its own text breaks. I checked A's 63 `l3fix` mutants by reading them, and
    four of my probes on checked lines were caught.
  - But every check counts a call's text. Where its arguments come from, and whether the call is reached at all,
    are not checked.
- **Failure scenarios.** Each of the 11 probes below is one exact-text change. Each one gives `HARNESS: PASS (3,654
  checks)`, so `mutate.py` would also score it as not caught. Each would also ship a real regression:

| Probe | Where | What breaks in play |
|---|---|---|
| `local combat = nil` in `damageScale` | `WeaponService.luau:658` | No bought tier ever reaches a hit: every family strikes at its window start. This is the whole of L3-6. |
| `local combat = nil` in `gearOf` | `WeaponService.luau:619` | The bar ignores every upgrade. |
| `gearOf`'s `held` always read from the saved loadout | `WeaponService.luau:622` | The bar no longer follows the shooter's live pair. |
| The pre-fix raw-override early return put back at the top of `gearOf`, or before `StrikeTier` in `damageScale` | `WeaponService.luau:618`, `:676` | 2-s1 is undone: G's T1 fields the Flamethrower at T1 again. Every count is unchanged: `strikeTierCalls` stays 3 and `scaleTier` stays 1. |
| Swap the slots' Ascension in `damageScale` | `WeaponService.luau:672-675` | A melee hit takes the ranged slot's Ascension. |
| Delete `runMigrations(profile.Data, player)` | `DataService.luau:212` | No profile ever migrates. A v7 profile is never paid its refund and stays v7. R5's runner is proved, and so is the claim that `runMigrations` calls it, but not that a load reaches it. |
| `local level = if false` in `GrantStars` | `WaveService.luau:2379` | U pays nothing again (R4 undone). `leverReward` counts the line that reads `level`, not the line that makes it. |
| `local difficulty = "normal"` in `grantStar` | `DebugService.luau:341` | U stars and pays Normal, not Hard. |
| SavedPower's `weapons` argument set to `nil` | `Main.server.luau:115`, `EconomyService.luau:104` | The Power in both places is always the starters' (a held Warhammer reads as the Broadsword). `mainPower` and `hubPower` stop matching after the second argument. |

- **Also: the five count-0 checks depend on spelling.**
  - The checks are `debugLiteral`, `hubLiteral` (`== "*"`), `hubFrozenGear` (`combat.gear`), `runnerSteps`
    (`Migrations[`) and `mainGearOf`.
  - Any of these passes them: `'*'`, `"*" == which`, `state.combat["gear"]`, `local m = ProfileSchema.Migrations;
    m[v]`.
  - Every one of those files also has a positive count, so a missing or moved file cannot pass vacuously.
- **Fix (luau-engineer A', with B' for the text).**
  1. Count the input lines in their bodies:
     - `local combat = if profile ~= nil then profile.combat else nil`, in `gearOf` and in `damageScale`;
     - the `held` line;
     - `damageScale`'s `local level` block;
     - `runMigrations(profile.Data, player)`, in the function that loads (add that body to `L3_BODIES`);
     - GrantStars' `then resolveLevel(levelId, difficulty, combatConfig, map)`;
     - grantStar's `local difficulty = ladder.starDifficulty`;
     - the two `provingConfig.weapons` / `provingConfig.loadout` lines, in Main's `sendSnapshot` and in
       `computeGearPower`.
  2. Count `return` in the `gearOf` and `damageScale` bodies (today 2 and 3), so an early return cannot hide.
  3. Add one `mutate.py` entry per new line. The probes in the table above can serve as the entries.

**m2. The hub's star lever still swallows the first-clear reward: R4 reached only the dungeon's U.**
File: `src/server/Services/ArmoryService.luau:211-238` (`grantStarTo`, reached from the strip's button and from
`DebugGrantStar`).

- **What is wrong.**
  - `grantStarTo` writes `stars[level][starDifficulty] = true` and pays nothing.
  - The hub strip's button now has the dungeon's caption, "★ Hard: Forest Road" (3-s2). The dungeon's U now pays
    the Warhammer and 20 Valor; the same caption in the hub pays nothing.
- **Failure scenario.** This is 2-m2's scenario, entered from the hub.
  1. With Studio API access on (the C1 bridge needs it, so the profile is shared), press the hub strip's star to
     test T4 on the hub's screen.
  2. Go to the dungeon and clear Hard.
  3. `EndRun`'s `StageFlow.Award` finds the star already held, so the card shows no new star, no Warhammer and no
     Valor. The shelf still reads "First Hard clear of Forest Road".
  4. Only `resetArmory` (L) gives the reward back.
- **Fix (pick one).**
  - The hub pays the new star's reward the same way. The level file's `difficulties[<star>].firstClear` is readable
    in the hub through `Catalog.GetLevelFile`. Move `StageFlow.FirstClear`'s reading, which is pure, to a shared
    module so both places use it. Then grant the family and the Valor as `UnlockService.GrantFirstClear` does.
  - Or caption the hub's button "★ Hard (no reward)" and have PLAYTEST L3-33 say it.
  - Check every entry point of a lever whenever a ruling changes what that lever does.

## Suggestions

**s1. `GrantStars` awards the star before it knows it can pay** (`WaveService.luau:2375-2385`).
- A level that does not resolve still gets the star but no reward. `readLevel` returns nil on any Validate
  problem, a missing layout, or `WeaponService.IsActive()` false, and it warns.
- A later Hard clear then pays nothing. This is Studio only.
- Resolve the level first, and call `StageFlow.Award` only when the level resolved (or when its file has no
  `firstClear`).

**s2. `Armory.luau:3-4` still says sim_combat mirrors it "function for function".**
- `StrikeTier`, `HeldFamily` and `SavedPower` have no Python mirror.
- `check_stage_mirror` notes the StageFlow functions it does not mirror, but no such Armory functions.
- R2's simulator reads the held pair through its own `held_pair`, not through a mirror of `HeldFamily`'s ownership
  and slot rule.
- Either list the three in a `note` line, as for StageFlow, or mirror them and add them to `ARMORY_MIRRORS`.

**s3. With the Armory open, the invite now drawn above it (R8) still cannot be reached on a gamepad.**
- R10's deferred `reselect` (`ArmoryScreen.luau:563-577`, `:784-786`) pulls any selection outside `frame` back
  inside. `onPadPress` (`:728`) also turns A into "select inside the screen".
- The ui-engineer reported this. B closes the screen, and the toast lives 30 s.
- If it matters, a host could pass the invite's root as an allowed selection while the screen is open, or close the
  screen when an invite arrives with the pad as the last input.

**s4. A late ProvingGrounds config shows the hub's Armory key, but nothing sends the screen its state**
(`UIController.luau:571-576`, `:951-958`).
- `refreshCombatKeys` can find the config through a remote `ChildAdded` after the Snapshot. The key then shows.
- But `pushArmory` returned early on every Snapshot or Delta before that, so the screen opens with no profile (an
  empty wallet) until the next Delta that carries `combat`.
- When `refreshCombatKeys` first resolves the config, replay `pushArmory(model.state.combat)`.
- This is rare: the old code built no screen at all in that case.

**s5. The new "the fire sniper casts at least once" gate is pooled over every fire course, so CaveMouth's breath
check proves nothing** (`tools/sim_range.py:10433-10446`).
- `cast` collects the breath scales of every `" + "` course together. In the run above, only the CaveExit courses
  cast (6 runs).
- CaveMouth + Dragon's Breath and its nearest-point course never cast, on Normal or on Hard. Their `armed` lines
  carry no `breath`, and `armed_problems` skips a run with none.
- So for those courses the R2 tier check is vacuous. They also earn less than the plain CaveMouth sniper.
- Hold the "casts at least once" check per spot, or name in its line the spots that never cast, so a course that
  stops casting is seen.

## Fix-specific checks asked for (all clean)

- **The clamped override and `GearOverride`.**
  - `StrikeTier` is TierOf without an override. With one, it is held inside the family's own window: a fraction,
    NaN or infinity reads the start, and a family with no window reads 1.
  - `gearOf` and `damageScale` both call it.
  - G compares against the override as it was set. Without one, it compares against the clamped bar, so the first
    G press with a Flamethrower held says "Gear T1" and changes nothing visible (B reported this). The next press
    steps on; the presets cannot get stuck.
  - `setGear` keeps an unnamed slot's override as set.
  - Without a profile, a starter reads T1 and a non-starter its window start. A non-starter cannot be held without
    a profile.
- **`GrantStars` pays.**
  - It pays only a NEW star, through the same `GrantFirstClear` that EndRun uses. An owned family is not given
    twice.
  - It is Studio-gated inside the function as well. Its only caller is DebugService.
  - The notice dedupes family names and shows the highest Valor any one player got.
- **`ProfileSchema.Run`.**
  - A `for` loop from the version the profile has. Each step runs once, and the stamp after each step is the
    version it produced.
  - Its answers match the old while loop for every version shape: a current one, an old one, nil (both error),
    NaN, a fraction, a negative, ahead.
  - DataService's verdict branches match the old `return` / ahead order.
  - It is the only runner: nothing else indexes `Migrations`.
- **`ProfileCopy.Combat`.**
  - Fresh tables at every depth. `copyTests` checks this by table identity, against a template whose every map has
    an entry.
  - Profiles are decoded DataStore data with no cycles.
  - Cost per Delta is that of the old copy. `FireClient` serializes anyway, so the copy is defensive.
  - The `variants` default writes only to the copy (a probe that pointed it at the profile was caught).
- **`SavedPower` and `HeldFamily`.**
  - `HeldFamily` equals the old `held()` closure: same slot rule, and ownership through starters or `families ==
    true`. The harness compares 36 saved shapes.
  - The `finite` guard on Ascension only drops NaN or infinity.
  - In the dungeon, `gearPower` is read by no client: only the hub's TopBar and ExpeditionPanel read it.
- **`Unlocks` → `Armory`.**
  - `Armory.luau` requires nothing, so there is no cycle.
  - Both project files map `src/shared` to `ReplicatedStorage.Shared`.
  - The harness bundle, `stage_mirror.luau` and `rojo build` all resolve it.
- **Touch controls (R9).**
  - Nothing else in `src` writes `TouchControlsEnabled`.
  - Every way the screen closes goes through `setOpen(false)`, which restores the saved value: Close, Esc and the
    menu, B, the scrim, `SetAvailable(false)`, and `teardown` on `Destroying`.
  - There is one screen per place, so two screens cannot save and restore over each other.
  - ControlModule only toggles `TouchGui.Enabled` on that property (`ControlModule/init.lua:879-888`), and it
    disables the thumbstick controller, so the character stops.
  - The dungeon's own Dash button sits in `RangeMovement` (DisplayOrder 0), under the HUD's DisplayOrder 1 scrim.
- **Gamepad re-selection (R10).**
  - The listeners live in `openConnections` and are disconnected on every close.
  - `reselect` acts only while the screen is open and the pad was the last input. It stops on any selectable,
    visible object inside `frame`.
  - No other client code writes `SelectedObject`, so the deferred reselect cannot ping-pong with another screen.
- **The invite's z (R8).** `ZINDEX_INVITE` 17 sits between CARD 15 and DIALOG 20. The hub ScreenGui is Sibling, so
  the toast's children follow its root. No other hub UI uses 16 to 19.
- **The simulator mirrors and `check_trophy`.**
  - `star_held` and `problems` match `StarHeld` and `namesList` on lists, `{}`, objects and words.
  - `check_trophy` and its four mutants are in place.
  - Every new `check_levels_mutants` SIM_CASE target occurs exactly once.
  - R2's views refuse to run a pair they were not built for, and `armed_problems` recomputes each run's held pair,
    bar and scales.

## Rulings

- **R1:** done. Code (`StarHeld`, `Problems`), data (`starAlso: ["brutal"]`), the screen through `StarHeld`, the
  mirrors, `check_trophy`, mutants.
- **R2:** done. Every strike is scaled by its own family's tier. The Frost Hammer's Forest pair rows are reported
  only. The Flamethrower pair is rated at T2/T2, as ratios to the starter pair. BALANCE gives the before and after.
- **R3:** done. `StrikeTier` is tested, and the service lines are counted with mutants. See m1 for the gaps.
- **R4:** done for the dungeon's U. See m2 for the hub's lever.
- **R5:** done. One runner, `ProfileSchema.Run`. The harness copy is gone. Mutants "runs a step twice" and "does not
  stamp the version". The header comment is rewritten.
- **R6:** done. Single-rule breaks in `tests_l3` and `ARMORY_BREAKS`, with mutants. Ten Armory mirror mutants
  (10/10 caught). `tests_l2` is pinned to `12 + 80`.
- **R7:** done. `ProfileCopy.Combat` and `Armory.SavedPower` (64 for a fresh profile) are used by both places, and
  the template walk is in place.
- **R8:** done. `ZINDEX_INVITE` 17.
- **R9:** done. Touch controls are off while the screen is open and restored on every close path.
- **R10:** done. A with nothing selected selects; the screen reselects on `LastInputTypeChanged` and on a
  `SelectedObject` change.
- **R11:** done. The pending-equip case and the "l3 ui: a style is live during another equip" mutant.
- **R12:** not in this diff. It is docs-keeper's, at the end of the wave. PLAN and MANUAL_STEPS do not say "Shut
  down all servers" yet.
- **Suggestions taken:**
  - 3-s1: done. The screen is built on `Armory.json` alone, the key follows the config, and remotes are resolved at
    send time.
  - 3-s2: done. `Unlocks.ALL_STARS`, and the caption is built from the built bands.
  - 3-s3: done. `ArmoryScreen.KEY` and `KEY_HINT`.
  - 3-s4: done. The comment is rewritten.
  - 4-s1: done. The tier line shrinks beside the dot, with an 8 px floor.
  - 4-s2: done. A pending button stays selectable.
  - 4-s3: done. `SetOffers` runs at every open, and rows are rebuilt only when they change.
  - 4-s4: done, through R1.
  - 4-s5: done. The style toast.
  - 4-s7: done. The new heights are in the `MIN_SCALE` list.
