# L4 W3 — economy-designer report

Contract `docs/prompts/l4-w3-contract.md` §2.1 (harness re-pointing), §3, §5, §6 (my rows), §7 (the data); study
`docs/prompts/l4-w3-cash-study.md` §2, §5.4, §6; Ben's pick (c) at M = 3 (MISSIONS_DESIGN §30). Nothing committed or
staged. **Done.**

Python: every tool with a `#!/usr/bin/env python` line (`sim_combat.py`, `sim_economy.py`, `check_stage_mirror.py`,
`check_levels.py`, `sim_range.py`) ran on **3.12.10 64-bit**; `run_harness.py`, `mutate.py` and `mirror_mutants.py`
(no shebang) on **3.14.7 32-bit** (`mirror_mutants.py` runs `check_stage_mirror.py` under its own interpreter, so 3.14
there).

## L4W3-14: the sim_economy baseline

Saved before any edit:
`C:\Users\benja\AppData\Local\Temp\claude\c--Users-benja-Desktop-tycoon\259ecf10-ad47-49f7-9d11-55e5c7db6b5a\scratchpad\l4-w3-qa\econ_base.txt`
(39 lines; identical to the cash study's run). After the hook, and again at the end: `cmp` identical;
`py tools/sim_economy.py --check` exit 0.

## What I changed

### Config
- `Combat.json`: `rewards.eraCashMult = [1, 670, 34000, 1400000]` (where `overdrive` was);
  `levels.departCountdownSeconds` 5; `debug.fakeDepartAttribute` "DebugFakeDepart", `debug.cashEraAttribute`
  "DebugCashEra"; **`debug.provingAutoStart` true** (L4W3-12, the lead's relay: `boot.proving` is
  `CombatMode.IsProving()`, which needs `RunService:IsStudio()` and the baked DebugProving attribute, so no live server
  reads it as a start; the combat `Main.server.luau` reads it only into its boot log line); `overdrive` and
  `debug.provingStartDelay` deleted.
- `Config/Missions/` deleted (its one file), left unstaged.
- `Armory.json`: `power` deleted (row 6: A deleted `GearPower`, `SavedPower`, `HeldTiers` and `ArmoryConfig.power`).
- `Expeditions.json`: `abilities.upcoming` = Glide ("Float down from any height.", with `castle`).
- `Levels/1_ForestRoad.json`: `difficulties.brutal.note` "Castle gear" (`forest.py`'s plan hash reads the layout and
  stage geometry, not `difficulties`: no re-bake).

### tools/sim_economy.py (the hook only)
`simulate_era(..., pause=None)`: called `pause(t)` once a second before buying, answers `(skip, cash)`; the cash lands
first, then `skip` True buys nothing that second. Five lines of code, three of docstring; default output
byte-identical. **The lead relays this to M11; whoever merges second resolves it.**

### tools/sim_combat.py
- `era_cash_mult(rewards, era)` mirrors A's `Combat.EraCashMult` line for line (no block, a list that is not a non-empty
  list, an era that is not finite, an entry that is not a finite number >= 1 -> 1; past the list -> last; under 1 ->
  first). `combat_cash_mult(state, game, shop, rewards=None, era=1)` = LegacyMult x PerkIncomeMult x it. Never in
  `level_pay`.
- New helpers: `greedy_curves(..., legacy, rebirth_count)` (lap 2), `Curve.legacy_gained`, `run_pause` (the hook's
  back-to-back runner, the study's runner.py "nonstop"), `era_state`, `forest_clears`.
- Assertion 4 for every era plus the 2% first-clear line; new 24 "never faster" and 25 "a few minutes"; 22 at era
  scale with an honest allowance (`math.fsum` + one ulp per credit; the old 1e-6 fails a correct split by 0.0156 at
  x2.27e7); the spot check at era 3 (x122,740). "thirteen assertions".
- Row 6: `gear_power`, `LADDER_POWER_T1`, `problems`' tierWeight line and their prints went; `held_tiers` stays as a
  helper (`sim_range.py` calls it), no longer a mirror.

### tools/check_stage_mirror.py + tools/crowd_harness/stage_mirror.luau
`Combat.EraCashMult` vs `era_cash_mult` (143 cases: shipped + ten broken copies x 13 eras incl. 0, -1, 1.5, 3.99, past
the list, NaN, +-inf, which travel as strings the driver decodes); `Combat.CombatCashMult` vs `combat_cash_mult` (120
cases: legacy 0 / 78 / 261 / 529 / 1680 / 9000 x Founder's off / top x shipped / no rewards x eras 1, 2, 3, 4, 7);
`DATA` carries `gameConfig` and `legacyShopConfig`. Row 6: the GearPower and HeldTiers comparisons, SavedPower's
unmirrored entry and the tierWeight Problems break went. (`stage_mirror.luau` is the tool's own driver.)

### tools/crowd_harness
- `run_harness.py`: `SOURCES` += MapRules, RunLines, RunCredit; `TESTS` += `tests_l4w3.luau`, `tests_l4w3_run.luau`
  (last); `unread` reads `Config/Levels` only; B's `luau-b-pins.py` pasted (`source.l4w3b`); `leverAward` /
  `leverLevel` read `MapRules.Award`; the 12 Power pins, the `hubPower` body and the count-0 `mainGearOf` /
  `hubFrozenGear` went (their rule was the Power's source); **new**: A's stamp check (5.4) as six L3 pins on
  `ExpeditionService.luau` (`stampThenBridge`, `stampOnce`, `okInHandOff`, `okInFile`, `departHandsOff`,
  `joinHandsOff`; bodies `hubHandOff`, `hubDepart`, `hubJoin`), expected counts in `tests_l3.luau`.
- `tests_l1.luau`: `L1.Map = load("MapRules")`; map calls re-pointed; the unread message names only Config/Levels;
  `levels.departCountdownSeconds` joins the numbers a run reads, `debug.provingStartDelay` leaves.
- `tests_l2`, `tests_l2w2`, `tests_l2w3`, `tests_l4w2`: `Sites` / `MapRow` / `MapState` / `NodeState` -> `L1.Map.*`
  (`MapRow` -> `SecretRow`); `tests_l3_run`: a comment.
- `tests_l3.luau`: the GearPower, SavedPower, HeldTiers cases and the Power pins' counts went (L4B-6); `powerTests` ->
  `heldFamilyTests` (HeldFamily vs LoadoutOf, 36 shapes); the shipped Armory.json case says "no power block"; the
  stamp pins' counts added. `tests_l3_ui.luau`: the fixture drops `power`.
- `mutate.py` (2,224 entries, was 2,129): `MAP_RULES`, `RUN_LINES`, `RUN_CREDIT`, `HUB_EXPEDITION` in `FILES`; 17
  entries re-pointed to MapRules; 22 dropped with Gear Power (Armory 6, combat Main 7, hub EconomyService 9); the
  `Config/Missions` glob dropped; the `StageFlow.Award` texts -> `MapRules.Award`; the snapshot-exit mutant's
  replacement no longer names `gearPower`. New blocks: `L4W3_MUTATIONS` (9 EraCashMult / CombatCashMult),
  `L4W3B_MUTATIONS` (B's 75, verbatim), `L4W3A_MUTATIONS` (30 of A's 36; six duplicated mine), `STAMP_MUTATIONS` (3).
- `mirror_mutants.py`: 9 L4W3-7 mutants.
- Equivalent breaks found and not kept (noted in both files): dropping `#list == 0` (A then removed the test) and
  dropping `era ~= era` alone (a NaN era indexes `list[NaN]`, nil, which reads 1).

### docs/BALANCE.md
New section "L4 W3: run cash by era, and the tools after the map's move": the changed keys and why, the per-era
table, the simulators, the tools, the gates.

## Assertion values (sim_combat.py --check, 3.12.10 64-bit)

| Assertion | Village | Boomtown | Metropolis | Orbital |
|---|---|---|---|---|
| 4: clear / owed at the middle (<= 25%) | 0.92% | 1.36% | 0.27% | 0.05% |
| 4: first clear / owed when it lands (<= 2%) | 0.88% | 1.23% | 0.25% | 0.05% |
| 24: back-to-back Normal vs the city (>= 0) | +28.8% | +8.1% | +3.9% | +2.3% |
| 24: back-to-back Hard vs the city (>= 0) | +22.7% | +3.4% | +1.2% | +0.8% |
| 25: first clear, minutes of income (1-6) | 4.3 | 3.0 | 2.3 | 1.7 |
| CombatCashMult (first lap) | x1.00 | x1,192.60 | x122,740 | x8,806,000 |

22: 400 runs x 60 kills, multipliers x1.00 .. x22,663,113 (lap 2 Orbital): never over, never a unit under. Every value
equals the study's. Spot check: "legacy 261, era 3 -> x3.61 x 34,000 = x122,740".

**Bites** (scratch `C:\Users\benja\AppData\Local\Temp\claude\c--Users-benja-Desktop-tycoon\259ecf10-ad47-49f7-9d11-55e5c7db6b5a\scratchpad\l4-w3-designer\bite.py`,
in-memory copies, 3.12): option (b) M=3 -> 4, 24, 25 fail; Boomtown 1,500 -> 4 on the 2% line alone (2.75%, mid
3.05%); option (a) M=3 -> 24 only (Metropolis Hard 4:26:56 < 4:28:49, Orbital 9:19:32 < 9:25:10); Village 2 /
Boomtown 200 / three entries / no block -> 25; the cash carry dropped / the multiplier on the carry -> 22. **10 of 10
as wanted**; the shipped file passes.

## Gates

| Gate (Python) | Result |
|---|---|
| `py tools/sim_combat.py --check` (3.12) | **PASS, all thirteen assertions** |
| `py tools/sim_economy.py` / `--check` (3.12) | **byte-identical to econ_base.txt** / exit 0 |
| `py tools/check_stage_mirror.py` (3.12) | **PASS**, 99 kinds (EraCashMult 143, CombatCashMult 120) |
| `py tools/crowd_harness/mirror_mutants.py` (3.14) | **147 of 147 caught** (full run, 40 min) |
| `py tools/crowd_harness/run_harness.py <repo> <luau>` (3.14) | **PASS, 4,994 checks** |
| `mutate.py` filtered (3.14) | **0 stale of 2,224**; 139 run here (17 MapRules, 5 re-aimed, my 9, B's 75, A's 30, 3 stamp), **0 not caught** |
| `py -3.12 tools/check_levels.py` | **PASS**, identical to the branch base `dce50da` |
| `py -3.12 tools/sim_range.py --check` | **PASS**, byte-identical to `dce50da` |

The base comparisons ran on a `git archive dce50da` export in my scratch (`...\l4-w3-designer\base`). Filtered mutate
runs used private roots (`mutant_designer*`, removed) and bundles (`bundle_designer*.luau`, removed). I did not start
`mutate_shards.py`.

## The lead's relays (answered)

- **`provingAutoStart`**: set to `true`; Studio-only (above).
- **ui B's 15 failing pins**: all cleared before the relay arrived. The 12 Power pins and the `hubPower` body went
  with row 6, and `leverAward` / `leverLevel` read `MapRules.Award`. The harness passes at 4,994.
- **A's mutants (`mutants_a.py`)**: all 8 MapRules and all **17 RunLines** entries are in `mutate.py` (`L4W3A_MUTATIONS`),
  text identical to A's file and 0 stale against the final source. 5 of A's 11 EraCashMult entries are in too; the
  other 6 are the same breaks as my `l4w3 era` / `l4w3 cash` entries. All 30 were run here: 30 of 30 caught.
- **The empty list in `era_cash_mult`**: it returns 1 explicitly (`not isinstance(mults, list) or not mults` -> 1, so
  Python never reads `mults[-1]`). `era_cash_mult({"eraCashMult": []}, 3)`, the same list at era 0, `{}` and `None` all
  give 1, and the 143 mirror cases include the empty list.
- **Row 6, the tool side**: retired, confirmed. `Armory.HeldTiers`, `GearPower`, `SavedPower`, `ArmoryConfig.power` and
  Validate's `power.tierWeight` line now have no mirror, comparison, grid op, Problems break, harness case, pin or
  mutate entry left (a grep of my tools finds only "went in L4 W3" notes). The Python `held_tiers` helper stays, because
  `sim_range.py` reads it. `Armory.json power` is deleted.
- **Mutant folders**: every filtered run used a named root (`mutant_designer`, `mutant_designer_0..3`, `_x`; all
  removed by mutate.py when it finished), never the shared `mutant/`.

## For the other owners

- **Lead:**
  - `debug.provingAutoStart` is now `true` (your relay, L4W3-12); Studio-only by `CombatMode.IsProving()`.
  - The `sim_economy.simulate_era(..., pause=None)` hook is the one to relay to M11.
  - `Armory.json power` is gone with Gear Power (row 6), beyond the contract's Config list.
  - **Untracked and not ignored:** `tools/crowd_harness/bundle-luauB.luau` (luau-engineer B's scratch bundle, a
    hyphenated name that `.gitignore`'s `bundle_*.luau` does not cover). Ignored leftovers of other owners' runs:
    `mutant_luauB_0..3`, `mutant_uiA`, `bundle_0..2.luau`, `bundle_luauA_*`, `bundle_luauB_*`, `bundle_uiA.luau`.
  - QA's sharded full run: the list is 2,224 entries, 0 stale at my last check.
- **luau-engineer A:** nothing required. Your stamp check is in (six pins, three mutants, all caught); 30 of your 36
  mutants are in (six were the same breaks as mine). `#list == 0` was equivalent, as you found.
- **luau-engineer B:** nothing required. `luau-b-pins.py` and all 75 of `luau-b-mutants.py` are pasted and caught here.
- **ui-engineer A / B:** nothing required.
- **Ben judges** (risk 2): the 5 s countdown (solo included). Risk 3 stands: the "never faster" check gates Normal and
  Hard only; back-to-back Brutal would beat the city by 1.8 / 2.9 / 1.3% past Village. Re-run 24 with Brutal when T5
  exists (economy-designer, the Castle).
