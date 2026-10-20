# L3 Wave 1 fix round — the lead's rulings and owners (2026-10-20)

The four slice reviews of L3 W1 (`docs/prompts/l3-w1-review/1-saving.md`, `2-combat-server.md`, `3-hub-hosts.md`,
`4-screen.md`) found **0 Critical, 1 Major, 13 Minor** and 13 suggestions. Read the finding in its file before you fix
it; this file says what the lead decided and who owns each fix. The contract of record is
`docs/prompts/l3-w1-contract.md` (its §12 overrides the text above it). Branch `l3-armory` in
`C:\Users\benja\Desktop\tycoon-p5`, at a2628da plus this file.

## Rulings

**R1 (1-m5) A band's top tier opens with that level's Hard star or a harder one.** A Brutal clear also opens T4. The map's
stars are unchanged (one star per difficulty cleared; no easier star is handed out). Data: `Armory.json ladder` keeps
`starDifficulty: "hard"` (the star the screen names and the U lever grants) and gains `starAlso: ["brutal"]`.
`Armory.luau` exports one `Armory.StarHeld(cfg, combat, levelId): boolean` (starDifficulty or any `starAlso`), which
`UpgradeVerdict` and `ArmoryModel` both use (ArmoryModel's private copy at `:463` goes: 4-s4). `Problems` checks
`starAlso` (an array of non-empty strings, or absent). Mirrors move with it.

**R2 (2-M1) The range simulator scales a weapon by its own tier, as the game does.** `sim_range`'s hit, pair, slam,
cast/breath scales and `gear_max_hp` use held tiers: starters at the gear tier, a non-starter at its window start
(clamped as `Armory.TierOf` does). Add the row to L3-27's mirror table (designer's report says where).
- **The Frost Hammer's Forest balance rows (clear time, cash a minute, the Colossus) become reported, not gated, until
  the Castle.** It is a Castle weapon arriving at T5, lever-only in the Forest. Every frost-crossing and geometry gate
  stays gated.
- **The Flamethrower pair is rated like with like:** both pairs at the gear a player holds when the Flamethrower first
  arrives (run 2: starters at T2, the Flamethrower at its start, T2). Every pair limit becomes a ratio to the starter pair
  at that same gear, keeping today's ratio limits; the absolute 4.0-minute floor becomes the same ratio to the starter
  pair's T2 clear that 4.0 minutes was to its T1 clear. Report the numbers before and after.

**R3 (2-m1) The server lines that apply L3's rules get a test.** One pure `Armory.StrikeTier(cfg, combat, family,
overrideTier: number?): number` (the override clamped into the family's window, else `TierOf`), called by both
`WeaponService.damageScale` and `gearOf`, tested in `tests_l3` (this also does 2-s1: G's override is clamped into each
window). For the lines that stay in services (the slam passes the held melee family, `OnUpgradeWeapon`'s gate, the
`GrantFirstClear` call in `EndRun`, `starsOf`'s profile branch, `readLevel`'s two new `Validate` arguments) add text checks
in `run_harness.py`, the L2 pattern, and `mutate.py` entries that break each one.

**R4 (2-m2) The U lever behaves like a Hard clear:** `GrantStars` pays each NEW star's `firstClear` reward through the same
`UnlockService.GrantFirstClear` path `EndRun` uses (Studio only, as the lever is). So U gives T4 and the Warhammer.

**R5 (1-m1) One migration runner.** The loop moves into a pure `ProfileSchema.Run(state)` (or the name that fits) that
`DataService` and the harness both call; the harness drops its copy. Mutants: "runs a step twice", "does not stamp the
version". The header comment at `ProfileSchema.luau:64-66` says plainly that step 7 pays and is not idempotent.

**R6 (1-m2, 1-m3, 1-m4) Gates that prove themselves:** single-rule breaks for the three unproven `Armory.Problems` rules
(`bandSize 4.5`, one band removed, `ranged[1] = -1`) in `tests_l3` and `ARMORY_BREAKS`, with mutants; the four Armory
entries in `mirror_mutants.py` (luau A's W1 report has the text) and `"Armory": "src/shared/Armory.luau"` in `PATHS`;
`tests_l2.luau:122` pinned to its literal value.

**R7 (3-m1) The hub's profile copy and Power are pure and tested.** `copyCombatProfile` moves into a pure shared module
(new; the owner names it) that `EconomyService` calls; a harness check walks ProfileSchema's template `combat` keys and
fails on any key the copy drops or aliases. Power becomes a pure `Armory.SavedPower(cfg, combat, weapons, starters)`
pinned at 64 for a fresh profile; the hub and the combat Snapshot read it.

**R8 (3-m2) A party invite draws above the hub's Armory:** its z sits between `Theme.ZINDEX_CARD` and `ZINDEX_DIALOG`.

**R9 (4-m1) While the Armory is open, Roblox's touch controls are hidden** (`GuiService.TouchControlsEnabled = false`,
restored on close and in teardown) in both places: nobody walks or jumps while the screen covers the world.

**R10 (4-m2) A gamepad always has a selection while the screen is open:** A with nothing selected selects the first
button; re-select on `LastInputTypeChanged` and when `SelectedObject` leaves the screen.

**R11 (4-m3)** a test case and a mutant for the style buttons' one-equip-in-flight rule.

**R12 (1-m6) The L4 publish includes "Shut down all servers"** after both places are published. Lead: PLAN, MANUAL_STEPS
(docs-keeper at the end of this wave).

**Suggestions taken:** 3-s1 (resolve the hub's remotes at send time), 3-s2 (one home for the grant-star wildcard
`Unlocks.ALL_STARS`; the strips' caption built from the built levels), 3-s3 (`ARMORY_KEY` and its hint exported by
`ArmoryScreen`), 3-s4 (the stale comment at `Types.luau:999-1001`), 4-s1 (portrait cards: the dot clears "Not found",
names never below the bottom bar's 8 design px floor), 4-s2 (after a press the selection stays on the pressed button),
4-s3 (the Abilities offers re-read at open), 4-s4 (with R1), 4-s5 (a style switch on the held weapon toasts
"Longbow: B · Quick shot"), 4-s7 (the new 48/56 px targets in Theme's MIN_SCALE list). **Not taken:** 4-s6 (568 × 320 is
outside L3-23). **To Ben at the playtest, not a fix:** 3-s5 (the hub no longer shows total Max HP; the next-tier line
shows the HP step) and the `m11-unlocks` branch must be re-keyed to L3's Armory when it merges (PLAN carried).

## Owners (fresh agents; disjoint files)

| Owner | Rulings | Files |
|---|---|---|
| **luau-engineer A'** | R1 (code), R3 (StrikeTier, its tests, every text check, every mutate entry), R5, R6, R7, 3-s2 (`ALL_STARS`), 3-s4 | `src/shared/Armory.luau`, `Unlocks.luau`, `Types.luau`, `Combat.luau` (type copies), `src/server/Services/ProfileSchema.luau`, `DataService.luau`, `EconomyService.luau`, `ArmoryService.luau`, the new shared copy module; `tools/crowd_harness/` (`tests_l3.luau`, `tests_l2.luau`, `run_harness.py`, `mutate.py`, `stage_mirror.luau`, `mirror_mutants.py`), `tools/check_stage_mirror.py` |
| **luau-engineer B'** | R3 (the call sites), R4, 2-s1 via R3 | `src/combat/server/Services/WeaponService.luau`, `WaveService.luau`, `UnlockService.luau`, `DebugService.luau`, `src/combat/server/Main.server.luau` (the Snapshot's Power through `Armory.SavedPower`) |
| **ui-engineer** | R1 (ArmoryModel), R8, R9, R10, R11 (the case), 3-s1, 3-s2 (captions, the constant), 3-s3, 4-s1, 4-s2, 4-s3, 4-s5, 4-s7 | the seven `src/client/UI/Armory*.luau`, `Theme.luau`, `tools/crowd_harness/tests_l3_ui.luau`; `src/client/Controllers/UIController.luau`, `src/client/UI/DebugPanel.luau`; `src/combat/client/Controllers/CombatUIController.luau`, `src/combat/client/UI/DebugPanel.luau` |
| **economy-designer** | R1 (data, mirrors), R2 | `src/shared/Config/Armory.json`, `tools/sim_range.py`, `tools/sim_combat.py`, `tools/check_levels.py`, `docs/BALANCE.md` |

- **Mutate entries:** luau A' owns `mutate.py`. B', the ui-engineer and the designer write theirs (label, file, the exact
  text, the replacement) in their reports; the lead adds them after all four report.
- **Order inside the round:** A' first lands `StrikeTier`, `StarHeld`, `SavedPower` and `ALL_STARS` with their signatures
  in its report as soon as they exist (the others code against the signatures in this file meanwhile).
- **Every agent:** run `git status` and `git diff` first; commit nothing; kill only your own PIDs; write your report to
  `docs/prompts/l3-w1-fix-reports/<role>.md` and reply with it; run your own gates (stylua, selene, luau-lsp on both
  sourcemaps, `py tools/check_compile.py`, the harness
  `py tools/crowd_harness/run_harness.py C:/Users/benja/Desktop/tycoon-p5 C:/Users/benja/Desktop/tycoon/tools/bin/luau.exe`);
  `export PATH="$HOME/.rokit/bin:$PATH"`; `py` only; LF files; ignore `tools/assets/`, `tools/testfit/` and `assets/`.
