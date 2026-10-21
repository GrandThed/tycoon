# L3 W1 review, slice 1: saving and the shared rules

Reviewer: roblox-reviewer, 2026-10-20. Branch `l3-armory` at a2628da. Diff `main...l3-armory` on this slice's files:
`src/shared/Armory.luau`, `Unlocks.luau`, `Types.luau`, `Combat.luau`, `src/server/Services/ProfileSchema.luau`,
`Config/Armory.json`, `tools/crowd_harness/tests_l3.luau`, `tests_l2.luau`, `stage_mirror.luau`,
`tools/check_stage_mirror.py`, and the Armory mirror in `tools/sim_combat.py`. Read against the contract (§12 rulings
included), MISSIONS_DESIGN §10 and §24, and the luau-a and designer reports.

**0 Critical, 0 Major, 6 Minor.**

Probes ran on a `git archive` copy of HEAD in my scratchpad. The worktree was not touched.

## Minor

**m1. The "exactly once through the runner" proof runs a copy of the runner, not the real one.**
`tools/crowd_harness/tests_l2.luau:68-78` (`L2.migrate`), used by `tests_l3.luau:607-631` and `:664-671`.
The real runner is `src/server/Services/DataService.luau:90-110`.
- No gate loads `DataService`: `run_harness.py` SOURCES has no entry for it, and `mutate.py` has no mutant for it
  (0 matches for "DataService").
- Step 7 is the first step whose safety depends on the runner. Every earlier step is if-nil and safe to repeat; this
  one pays. The contract (L3-8) states that "the harness proves that the runner applies it exactly once".
- `ProfileSchema.luau:64-66` still tells the next reader that every step is "Additive and idempotent". Only the
  comment on step 7 (`:142`) says otherwise.
- **Failure (probe):** I changed the real loop to call `migrate(state)` twice per version. A v7 3/3 profile then
  gains 1,000 Timber instead of 500. The harness still passes (3,539 checks), and so does `check_stage_mirror`.
- **Fix:**
  - Move the loop into ProfileSchema as a pure `ProfileSchema.Run(state): "missing" | "ahead" | nil`. DataService
    calls it and warns on the answer; the harness calls it in place of `L2.migrate`.
  - Add two mutants: "the runner runs a step twice" and "the runner does not stamp".
  - Change the header comment to say: "Additive; every step but [7] is idempotent; the version stamp is what runs
    each one once".

**m2. Three `Armory.Problems` rules are proven by no gate.**
The rules are at `src/shared/Armory.luau`:
- `:646`, a bandSize that is not a whole number above 0;
- `:650`, bands × bandSize does not cover the ladder;
- `:617`, an HP entry below 0.

Every break that should name one of them is also named by a second rule:
- "bandSize 3" (`tests_l3.luau:470`, `check_stage_mirror.py:224`) also breaks `#costs ~= bandSize` (`:663`).
- "bandSize 0" (`:471`) also breaks the costs rule and the cover rule.
- "a negative HP entry" (`:468`, melee[1] = −1) also breaks melee ≥ ranged (`:632`).

Mutate.py covers only three other Problems rules.
- **Failure (probes):** I replaced each of the three rules with `if false` / `elseif false`, one at a time. Each time
  the harness passed (3,539) and so did `check_stage_mirror`. If the cover rule regresses, an Armory.json that loses
  a band (4 bands of 4 for 20 tiers) boots with no warning, and T17–T20 read `notBuilt` for ever.
- **Fix:** add one break per rule that only that rule can name, both in `tests_l3` and in `ARMORY_BREAKS`, plus the
  three matching mutate entries:
  - `bandSize = 4.5`: the costs rule is skipped when bandSize is not whole, and the cover rule sits behind it;
  - `table.remove(c.ladder.bands)`: the cover rule only;
  - `ladder.hp.ranged[1] = -1`: the negative rule only, because melee stays above it.

**m3. The 19 new Armory comparisons in `check_stage_mirror` have no committed mirror mutants.**
`tools/crowd_harness/mirror_mutants.py` has no `Armory` entry in `PATHS` or `MUTANTS`. The four entries luau-engineer A
proposed in "For the other owners" were not added. So QA's `mirror_mutants` gate says nothing about this slice's
mirror, and whether these comparisons catch anything rests on A's hand run.
- **Check:** today they do catch changes. I flipped the funds edge (`have >= cost` to `have > cost`) and got
  `DIFF Armory.UpgradeVerdict: 3 of 4 differ`, `CHECK: FAIL (3)`.
- **Fix:** add A's four entries (BandOf from 0, TierOf with no start, a band top with no star, SetTier unclamped) and
  one for UpgradeVerdict's order (busy before peak). This is the lead's or QA's file.

**m4. One `tests_l2` check computes its expected value with the function under test.**
`tools/crowd_harness/tests_l2.luau:122` reads `local refund = load("Armory").LegacyRefund(ARMORY, { melee = 2, ranged =
1 }).Timber or 0`. The check then expects `Timber == 12 + refund`.
- **Failure:** if LegacyRefund returns `{}`, the step pays nothing and the check expects nothing, so it stays green.
  `tests_l3` pins the refund with fixed numbers (80, 500, 320 + 10 Steel), so the gate as a whole holds. This check
  is green for the wrong reason.
- **Fix:** pin it to `12 + 80` (70 + 10 Timber at the frozen prices).

**m5. The trophy is the Hard star exactly, so a Brutal clear never opens a band top.**
- `Armory.luau:414-418` and `:455`: `starHeld(combat, levelId, ladder.starDifficulty)` reads only
  `stars[level].hard`.
- `StageFlow.Award` (`StageFlow.luau:2916-2927`) stars only the difficulty that was cleared.
- **Failure:** a T3/T3 player is carried through Forest Road Brutal by a party (one party per server, open camps).
  The profile gains `brutal = true` and the Brutal first-clear Valor. T4 still reads "Needs ★ Hard on Forest Road",
  and the Upgrade refuses `needsStar`. A player will read that as a bug. Solo it is out of reach today: Brutal at T3
  goes down on every seed.
- **Fix:** choose one of these, and write the ruling into the contract:
  - starHeld accepts `starDifficulty` or any difficulty after it in `Expeditions.json difficulties` order, mirrored
    in `sim_combat._star_held`;
  - Award also writes every easier difficulty;
  - the lead rules it intentional, and the screen's needsStar line says "Clear Forest Road on Hard".

**m6. "Both places publish together" (L3-30, §12.4) still leaves old v6 servers running beside v8 ones.**
- Roblox keeps running servers on the old version after a publish until they empty or are restarted. Old v6 code
  plays a v8 profile, by the ahead guard. Its `tryBuyGear` (live 2b15570 `ArmoryService.luau:81-112`) still sells
  slot `gear`, which new code never reads again.
- **Failure:** a player converts on a new server and keeps their Timber, refund included. A friend-join lands them on
  an old hub server, where they buy slot tier 2 for 60 Timber. Back on new code, that Timber is gone and buys nothing.
  This is a loss, never a gain: the stamp stops a second refund.
- **Fix:** add one line to the L4 publish steps in MANUAL_STEPS: after publishing both places, use the Creator
  Dashboard's "Shut down all servers" or "Restart servers for updates", so that no v6 server outlives the first
  conversion.

## Checked and clean

- **Ladder:** every `ladder.damage` value equals round(1.5 × 1.65^(t−1), 4).
- **HP:**
  - HP T1–T11 are the old slot tiers 2–12. T12–T20 rise, with melee ≥ ranged.
  - MaxHp is 155 / 230 / 380 at (1,1) / (3,3) / (5,5), RangeHp is 130, and GearPower at T1/T1 is 64. Recomputed in
    Python from Armory.json.
- **The frozen price list:**
  - `legacy.gearCosts` equals the slot prices in every committed Armory.json (ac46d13, 2b6a9bb, 3d8f99d, ff7a910),
    including live 2b15570.
  - The template `gear` has been 0/0 since C0. Only `tryBuyGear` and Studio levers ever wrote `gear`, on live and
    on main. So the refund pays back exactly what was spent.
- **Migration step 7:**
  - It adds fresh tables only when a field is nil.
  - It runs after Reconcile (`DataService.luau:217-218`) and never yields (Catalog uses FindFirstChild).
  - The template is v8, so a new profile skips the step.
  - ProfileStore deep-copies the template (`ProfileStore.luau:1497, 1766`), and its Reconcile only fills
    (`:408-422`). No aliasing.
  - `gear` is never written. On the branch, only the C1 readers, the hub's Snapshot copy and the refund read it.
- **v8 on old code:**
  - Live v6 (2b15570: SCHEMA 6, ahead guard since d166a9a, an ancestor) and v7 main both keep every v8 field.
  - No old code reads `combat.tiers`, `loadout` or `stars` (git grep on both).
  - No old code rebuilds `combat` wholesale.
- **UpgradeVerdict and Upgrade:**
  - UpgradeVerdict tests invalid → locked → peak → busy → notBuilt → needsStar → insufficientFunds.
  - Upgrade is the verdict, then one write, with no yield. It never takes a wallet below 0, it makes `tiers` when
    missing, and a refusal leaves the profile deep-equal.
  - Mid-band window starts (Flamethrower 2, Warhammer 3) pay only from their start.
- **Clamps:** `Window` holds start and top inside the ladder, and `TierOf` holds a saved tier inside the window. A
  window that is narrowed, moved or removed never strands a saved tier, and non-whole or NaN values read the start.
- **Unlocks:**
  - `LoadoutOf` falls back on an unknown, unowned or wrong-slot family and on an unknown style, and returns fresh
    tables.
  - `SaveLoadout` writes only melee and ranged.
  - `StarsOf` and `ResetArmory` behave as specified. `TierLever` requires `^[%w_]+=%d+$` and at most 24 bytes.
- **Types:**
  - The Armory.luau and Combat.luau copies of CombatProfile, SavedLoadout and ArmoryConfig match Types field for
    field, and no other copy exists.
  - `buyGear` has no reader left.
  - Every `UpgradeRefusal` is in `ActionReason`.
  - Combat.luau changed types only.
- **sim_combat's Armory mirror:**
  - It matches the Luau guard for guard (read side by side; only `upgrade` itself is not compared, and it is
    trivially the same).
  - `sim_combat --check` passes 23/23: the climb is 6 runs, 24.6 min, Hard ×2.
  - `LEVEL_REWARD_MULT.hard` 2 matches `1_ForestRoad.json`.
- **Gates:**
  - harness PASS (3,539);
  - `check_stage_mirror` PASS;
  - stylua and selene clean on the five Luau files;
  - `check_compile` PASS (177 files).

**Count: 0 Critical, 0 Major, 6 Minor.** File: `C:\Users\benja\Desktop\tycoon-p5\docs\prompts\l3-w1-review\1-saving.md`.
