# L3 W1 fix round: luau-engineer A' (shared rules, saving, the hub server, the harness)

Worktree `C:\Users\benja\Desktop\tycoon-p5`, branch `l3-armory`. Nothing is committed. B' and the ui-engineer had
finished when I ran my last gates, and their work is in every result below. The designer's `starAlso` data and
`sim_combat.star_held` were already in.

## The shared signatures (landed first)

`src/shared/Armory.luau` (still require-free):

```luau
Armory.StarHeld(cfg: ArmoryConfig, combat: CombatProfile?, levelId: string): boolean
-- R1: ladder.starDifficulty's star, or the star of any ladder.starAlso entry. False without a ladder
-- or a profile; a starAlso that is not a list adds nothing (sim_combat.star_held reads it the same way).

Armory.StrikeTier(cfg: ArmoryConfig, combat: CombatProfile?, family: string, overrideTier: number?): number
-- R3: overrideTier nil -> TierOf. Otherwise the override held inside the family's OWN window. An
-- override that is not whole reads the window's start; a family with no window reads 1.

Armory.SavedPower(cfg: ArmoryConfig, combat: CombatProfile?, weapons: any,
                  starters: { melee: string, ranged: string }): number
-- R7: Gear Power of the SAVED pair, with the slots' Ascension. weapons and starters are
-- ProvingGrounds.json `weapons` and `loadout` ({ melee = "", ranged = "" } with no config).

Armory.HeldFamily(combat: CombatProfile?, weapons: any, starters: { melee: string, ranged: string },
                  slot: string): string
-- L3-10's slot rule, moved here so it has ONE home: Unlocks.LoadoutOf and SavedPower both call it.
```

The other new signatures:
- `Unlocks.ALL_STARS = "*"`, the grantStar wildcard (3-s2).
- `ProfileSchema.Run(state: Types.PlayerState): RunVerdict?`, where `export type RunVerdict = "missing" | "ahead"`.
- `ProfileCopy.Combat(combat: Types.CombatProfile): Types.CombatProfile`, in the new `src/shared/ProfileCopy.luau`.
- `Types.ArmoryLadder`, and its copies in `Armory.luau` and `Combat.luau`, gain `starAlso: { string }?`.

## Rulings, and what I did

- **R1 (code).**
  - `Armory.StarHeld` is the only star reader. `UpgradeVerdict` calls it, and the private `starHeld` stays as its
    one-difficulty helper.
  - `Problems` gains: "ladder.starAlso is not a list of difficulty names". The text matches sim_combat's. A table
    with keys other than 1..n, or with an entry that is not a non-empty string, is refused. An absent or empty
    `starAlso` is sound.
  - Mirrors:
    - `check_stage_mirror` compares `StarHeld` against `sim_combat.star_held` (`ARMORY_MIRRORS`).
    - Added profiles that hold only a Brutal star, a config without `starAlso`, and an `edges` config whose
      `starAlso` is a word.
    - Added two `ARMORY_BREAKS` for `starAlso`.
- **R3.**
  - `Armory.StrikeTier`, with a new `strikeTests` group. It equals TierOf with no override, for every family and
    every saved shape. 2-s1: T0, T1, T20 and T30 overrides are held inside each of the 15 windows; G at T1 fields
    the Flamethrower at T2 and the Frost Hammer at T5. A fractional, NaN or infinite override reads the start. A
    family with no window reads 1, and so does every family without a ladder.
  - **Text checks for every service line.** `run_harness.py` has a new `L3_BODIES` / `L3_LINES` table and an
    `l3_reading` (`FIXTURES.source.l3`). The new `tests_l3` `sourceTests` group holds each count to its expected
    value. It fails when a function body is not found, and when the reading has a key the cases do not expect.
    - The 37 lines: B's 19 as written in its report, and 18 of mine:
      - the slam;
      - `OnUpgradeWeapon`'s gate and its ownership argument;
      - EndRun's `reward` and `given` lines, counted inside `WaveService.EndRun`. The file count of
        `UnlockService.GrantFirstClear(` is pinned at 2.
      - `starsOf`'s profile branch;
      - `readLevel`'s `tuned.weapons` and `Unlocks.Starters(tuned.loadout)`;
      - the ranged override and the Ascension in `damageScale`.
    - Lines that must be gone (count 0): `== "*"` in DebugService and in the hub's ArmoryService; `WeaponService.GearOf(`
      in Main; `combat.gear` in EconomyService; `Migrations[` in DataService.
    - The hub lines (R5/R7): DataService calls `ProfileSchema.Run`; EconomyService calls `SavedPower` and
      `ProfileCopy.Combat`, and `computeGearPower` feeds both the Delta and the Snapshot; the hub's
      `Armory.Upgrade(..., owned, true, built)` and its ownership line.
- **R4.** B's lines, under the same text checks: `leverAward`, `leverReward`, `leverGrant`, `leverStudio`.
- **R5.**
  - `ProfileSchema.Run` is a `for` loop from the profile's version. Each step runs once and the stamp is the
    version that step produced. It answers `"missing"` (no step, or a version that is not whole), `"ahead"`, or
    nil.
  - DataService's `runMigrations` only calls it and warns on the answer; its loop and its `Migrations` local are
    gone.
  - The harness keeps no copy: `L2.migrate` is now one line, `L2.Schema.Run(state)`.
  - New cases: a fresh profile, a v7 one, a v1 one (every step), version 0 (`missing`, untouched), 9 (`ahead`,
    untouched, no refund) and 7.5 (`missing`, no pay).
  - The header comment now says step 7 pays, is not idempotent, and is run once by the stamp.
  - The loop is a `for` on purpose: with a `while` loop, the "does not stamp" mutant would hang the harness, which
    `mutate.py` counts as not caught.
- **R6.**
  - `problemTests` now asks, for each of its 32 breaks, that the line of the rule it breaks is among the answers,
    not merely `#lines >= 1`.
  - The new breaks must also name exactly one line: bandSize 4.5, one band removed, `ranged[1] = -1`, and four
    `starAlso` shapes.
  - Those three breaks are also in `ARMORY_BREAKS`.
  - `mirror_mutants.py` gains `"Armory": "src/shared/Armory.luau"` in `PATHS`, plus 10 mutants:
    - A's four from W1, with the band-top one re-aimed to `Armory.StarHeld(`;
    - UpgradeVerdict's busy-before-peak order;
    - StarHeld ×2;
    - Problems' `starAlso`, cover and negative-HP rules.
  - The bandSize rule has no mirror mutant. Every break of it also trips the cover rule, and the mirror compares
    Problems as found or not found. The harness's mutant covers it instead.
  - `tests_l2.luau:122` is pinned to `12 + 80`.
- **R7.**
  - `ProfileCopy.Combat` is a whole-tree deep copy, not a list of fields. So a field a later schema adds rides
    along without an edit. A loadout without `variants` still gets `{}`, as the old copy gave it.
  - `copyTests`:
    - walks `ProfileSchema.PROFILE_TEMPLATE.combat` at every depth and fails on a missing key;
    - deep-equals a filled profile;
    - fails if any table of the copy is a table of the source (by identity);
    - checks that a v9-style map rides along and that a v7 profile's missing fields stay nil.
  - `Armory.SavedPower` is 64 for a fresh template profile on the shipped files, on the fixture, with no profile,
    and with no ProvingGrounds. It never reads the frozen `gear` (3 / 3 still reads 64).
  - Over 36 saved shapes it equals `GearPower(HeldTiers(LoadoutOf(...)))`, and `HeldFamily` equals LoadoutOf's
    slot.
  - EconomyService now calls `ProfileCopy.Combat` and `Armory.SavedPower`, and no longer requires Unlocks. B's
    Main does the same.
- **3-s2.** `Unlocks.ALL_STARS`. The hub's `grantStarTo` compares with it, and so does B's DebugService.
- **3-s4.** The stale comment in `Types.luau` (the v7 maps "optional because the hub copies the profile without
  them") is rewritten.

## Files changed

- `src/shared/Armory.luau`
- `src/shared/Unlocks.luau` (requires Armory now; no cycle, because Armory requires nothing)
- `src/shared/Types.luau`
- `src/shared/Combat.luau` (`starAlso` in the type copy only)
- **new** `src/shared/ProfileCopy.luau`
- `src/server/Services/ProfileSchema.luau`
- `src/server/Services/DataService.luau`
- `src/server/Services/EconomyService.luau`
- `src/server/Services/ArmoryService.luau`
- `tools/crowd_harness/tests_l3.luau`
- `tools/crowd_harness/tests_l2.luau`
- `tools/crowd_harness/run_harness.py` (`ProfileCopy` in SOURCES, plus the L3 text reading)
- `tools/crowd_harness/mutate.py`
- `tools/crowd_harness/stage_mirror.luau`
- `tools/crowd_harness/mirror_mutants.py`
- `tools/check_stage_mirror.py`

## Tests and mutate entries added

- **Harness:** 3,539 at W1, 3,654 now. That figure includes the ui-engineer's new UI cases.
- **New groups in tests_l3:** `starTests`, `strikeTests`, `powerTests`, `copyTests` and `sourceTests` (37 line
  checks). `verdictTests` gains the Brutal cases, `problemTests` was rewritten, `schemaTests` gains the runner's
  verdicts, and `shippedTests` pins `starAlso = { "brutal" }`.
- **mutate.py:** 1,298 entries before, 1,368 now, 0 out of date.
  - **Re-aimed (3):**
    - "l3: a band top needs no star", to `Armory.StarHeld(`;
    - the two "l3: LoadoutOf holds …", to `Armory.HeldFamily`. The `HELD_FAMILY` constant is gone.
  - **`L3_FIX_MUTATIONS` (46, mine):**
    - StarHeld and starAlso: 5;
    - StrikeTier: 5;
    - SavedPower: 3;
    - ProfileCopy: 4;
    - the runner: 5;
    - Problems: 3;
    - the service lines: 21.
  - **`L3_FIX_RUN_MUTATIONS` (B's 17), verbatim.**
  - **`L3_UI_FIX_MUTATIONS` (the ui-engineer's 7), verbatim.**
  - **`FILES` gains:** `UnlockService`, `DebugService`, the hub's `EconomyService`, `DataService` and
    `ArmoryService`, and `ProfileCopy`. The text reading counts lines in every one of these, so the mutant roots
    need them.

## Gate results

| Gate | Result |
|---|---|
| Harness (`run_harness.py C:/…/tycoon-p5 C:/…/tycoon/tools/bin/luau.exe`) | `HARNESS: PASS (3,654 checks, …tycoon-p5\tools\crowd_harness)` |
| `mutate.py … "l3fix"` (my 46 + B's 17) | `MUTATIONS: 63 run, 0 not caught`. Every one was caught by failing checks; no bundle stopped. |
| `mutate.py`, the three re-aimed entries | 2 run, 0 not caught; then 1 run, 0 not caught |
| `mutate.py … "l3 ui:"` (22 from W1 + the ui-engineer's 7) | `MUTATIONS: 29 run, 0 not caught` |
| `mutate.py`, the whole list | 1,368 entries, 0 out of date (checked; the full run is QA's) |
| `py tools/check_stage_mirror.py` | `CHECK: PASS`. `Armory.StarHeld` compared on 5 configs; Problems on 26 configs (21 breaks) |
| `mirror_mutants.py --only Armory` | 10 of 10 caught |
| `py tools/check_compile.py` | PASS, 178 files |
| stylua `--check` and selene, on my 9 Luau files | clean (0 / 0 / 0) |
| luau-lsp, both trees, fresh sourcemaps, `tools/types/globalTypes.d.luau` | no diagnostics |
| `rojo build`, default and combat, into scratch | OK |

## For the other owners

- **Designer (optional).** Armory's header says sim_combat mirrors it function for function. `StrikeTier`,
  `HeldFamily` and `SavedPower` have no Python mirror. The simulators do not need them: R2 uses `held_tiers` with a
  built profile, and nothing simulates the Studio override. If you add `strike_tier` / `saved_power`, I (or the
  lead) can add them to `ARMORY_MIRRORS`.
- **Lead.**
  - `mutate.py` now holds everyone's entries, B's and the ui-engineer's included, so nothing is left to add.
  - QA's full mutate run is about 1,368 entries.
  - Docs: `Armory.StarHeld` replaces "the Hard star exactly" (contract L3-4). MANUAL_STEPS' publish step (R12)
    is docs-keeper's.
- **Not taken, by design.** `HeldFamily` keeps the "a starter is owned" branch, for parity with
  `Unlocks.OwnsFamily`. On any sane config this branch never changes the answer: a starter saved in its own slot
  is the slot's fallback anyway. So no mutant is written for it; it would be an equivalent mutant.

## What to check in Studio

1. **Hub Power.** It reads 64 on a fresh profile, and 77 after buying Longbow T2. The dungeon lobby shows the same
   number.
2. **Hub Delta.** After an upgrade or an equip, the hub's Armory screen still shows found families, stars and
   shortcuts. The copy now carries the whole profile.
3. **Hub `DebugGrantStar = "*"`.** It still stars Forest Road on Hard (it is `Unlocks.ALL_STARS` now).
4. **Old profile, with Studio API access.** It still converts once: v7 → v8 with the refund, and a rejoin pays
   nothing more. Output shows no `[DataService] missing migration` line.
