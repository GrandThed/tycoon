# L3 W1 fix round, economy-designer report (2026-10-20)

Worktree `C:\Users\benja\Desktop\tycoon-p5`, branch `l3-armory`. Nothing is committed. I own R1 (data and mirrors) and
R2 (review 2-M1, with its two pair-gate rulings). The full tables are in `docs/BALANCE.md` under "L3 W1 fix round".
Every number below comes from 64-bit `py -3.12`.

## Files changed

- `src/shared/Config/Armory.json`: `ladder.starAlso: ["brutal"]`. `starDifficulty` stays `"hard"`.
- `tools/sim_combat.py`:
  - `star_held(cfg, combat, level_id)` mirrors `Armory.StarHeld`: starDifficulty or any starAlso; false without a
    ladder or a profile.
  - `upgrade_verdict` calls `star_held`.
  - `problems` adds A's line "ladder.starAlso is not a list of difficulty names", using Armory.luau's `namesList`
    rule. An empty JSON object passes, as Luau decodes it to the same table as `[]`.
  - Assertion 1 pins `starAlso` (`LADDER_STAR_ALSO`).
  - `climb_runs(fire=)`: run 3 holds Broadsword + Flamethrower. `gear` is now always the starters' tiers. The numbers
    are the same.
  - Assertion 2 also requires that the run whose chest pays the fire family is at `sim_range.PAIR_FLAME_GEAR`.
- `tools/sim_range.py`:
  - New helpers: `gear_profile`, `held_pair` (with a `holds` key), `held_scale`.
  - `level_view(..., held=)` stores `_scales` per family (hit and cast), `_tiers`, `_held` and `_hp`. The bar and
    the regen are the held pair's.
  - `gear_max_hp(armory, gear, cfg, held)`.
  - `ThreatRun` scales the hit, the pair kit and the cast by the striking family. The slam uses the held melee.
  - A run on a view built for another held pair, or with another bar, raises `ValueError`.
  - The fire sniper's cast uses the fire family's own tier.
  - Every run records `armed`; `armed_problems` and `armed_line` check it.
  - The Flamethrower rows run at `PAIR_FLAME_GEAR` (T2/T2) with ratio limits (`PAIR_CLEAR_SHARE`).
  - The Frost Hammer rows are reported, not gated.
  - Also: `print_cave`, `check_cave_runs` and the header paragraph.
- `tools/check_levels.py`: `ctx["armory"]`, and the new `check_trophy` rule (R1, details below).
- `docs/BALANCE.md`: the "L3 W1 fix round" section.

## R1: the trophy

- **Data:** `starAlso: ["brutal"]`.
- **Mirror:** `sim_combat.star_held` is the function `check_stage_mirror` calls (A's `"StarHeld": "star_held"`).
  `check_stage_mirror` PASSES against A's current `Armory.luau`: StarHeld 5 compared, Problems 26 compared.
- **Diff check:** I checked `git diff src/shared/Armory.luau` at the end, and its Problems text matches mine
  word for word.
- **New data gate (`check_levels` `check_trophy`):** starDifficulty is a difficulty in Expeditions.json, and
  starAlso lists exactly the difficulties after it, in order. That makes "or a harder one" a property of the data:
  no easier star can open a band top, and a difficulty added later cannot be left out.
- **Mutants:** all ran through the harness's own `run()`:
  - `[]`: red;
  - `["normal"]`: red;
  - a difficulty added after Brutal and not listed: red;
  - control, that difficulty listed: green.

## R2: the pair rows, before and after (Forest Road Normal, seeds 11 / 23 / 37)

| Row | Before (the sim as shipped, slot gear) | Game rule at T1 (reviewer's probe) | After |
|---|---|---|---|
| **Flamethrower + Broadsword** | T1/T1, Flamethrower x1.5, bar 155: 4.06 / 4.24 / 4.17 min; cash x1.02; Colossus x0.99 (75.3 against 76.4 s) | 4.04 / 3.93 / 4.03 min, seed 23 under the 4.0 floor; x1.07; x0.96 | **T2/T2, Flamethrower T2, bar 180: 3.20 / 3.16 / 3.20 min**. The band is 3.04-4.37 min (x0.939-x1.350 of the starter pair's 3.23). **Cash x1.02** (40,991 against 40,344; limit x1.10). **Colossus x1.00** (46.2 against 46.2 s; limit x0.90). No down. **PASS** |
| its yardstick, Broadsword + Longbow | T1/T1: 4.14 / 4.32 / 4.32 min; 30,859 cash/min; Colossus 76.4 s | same | **T2/T2, bar 180: 3.34 / 3.16 / 3.20 min**; 40,344 cash/min; Colossus 46.2 s |
| **Frost Hammer + Longbow** | T1/T1, Frost Hammer x1.5, bar 155: 4.46 / 4.69 / 4.43 min; x0.95; Colossus x1.08 (82.1 s) | 2.22 / 2.30 / 2.27 min; x1.83; Colossus x0.18 (13.9 s) | **Frost Hammer T5 (x11.118), bar 290: 2.22 / 2.30 / 2.27 min; x1.83 (56,507 against 30,859); Colossus 13.9 against 76.4 s, x0.18. Reported until the Castle** (it would fail all three of the old limits) |
| Fire sniper (Dragon's Breath, tunnel open; R8, L2-37) | the cast at the bow's x1.5 | identical | the cast at the Flamethrower's T2 (x2.475). Every Normal and Hard row is unchanged (CaveMouth 799 / 3,994 / 533, CaveExit 2,037 / 2,037 / 582 cash a minute on Normal). There were 6 casts on each difficulty. **PASS** |

Pair-gate rulings, as applied:

- The clear floor is the same ratio as before. 4.0 min was x0.939 of the starter pair's mean T1 clear: 255.544 s
  (248.1, 259.2, 259.4 s) on a2628da, whose T1 is the old 2/2 the band was set at. Applied to the starter pair's
  T2 clear, that floor is 3.04 min.
- I converted the 5.75 ceiling the same way (x1.350), reading "every pair limit becomes a ratio" as covering it.
  At T2 that ceiling is 4.37 min.
- Cash and the Colossus keep x1.10 and x0.90, now against the starter pair at T2/T2.
- I dropped the old "the pair against the Broadsword alone" note: the gears now differ.
- The armed checks stay gated on the Frost Hammer rows. Every frost-crossing and geometry gate is untouched.

## Gates (final tree)

| Gate | Result |
|---|---|
| `py -3.12 tools/sim_range.py --check` | **PASS**, 561 checks (Python 3.12.10, 64-bit). The diff against a clean copy of `f6c426d` touches only the cave and pair section (71 lines). Every Normal, Hard, Brutal, arena, R8 and range row is byte-identical; the PASS count went from 549 to 561 (6 old pair gates out, 18 new in) |
| `py -3.12 tools/sim_combat.py --check` | **PASS**, 23 of 23. The climb takes 6 runs and 24.6 min; "the flamethrower comes at T2/T2 (sim_range PAIR_FLAME_GEAR T2/T2)"; T4 needs the hard or brutal star |
| `py tools/check_levels.py` | **PASS**, including the new R1 trophy line |
| `py -3.12 tools/check_stage_mirror.py --luau C:/Users/benja/Desktop/tycoon/tools/bin/luau.exe` | **PASS** (against A's Luau, re-run at the end) |
| `py tools/crowd_harness/run_harness.py C:/Users/benja/Desktop/tycoon-p5 C:/Users/benja/Desktop/tycoon/tools/bin/luau.exe` | **PASS**, 3,654 checks (with the other owners' work as it stood) |
| `py tools/check_compile.py` | **PASS**, 178 files |
| `py tools/sim_economy.py --check` | **PASS**, unchanged. Village 41:50, Boomtown 1:44:15, Metropolis 4:28:49, Orbital 9:25:10; the longest wait in the first 10 min is 14 s |

I changed no Luau, so stylua, selene and luau-lsp have nothing of mine to check.

## For the lead

### 1. `check_levels_mutants.py` CASES (R1)

All four were run through `clm.run` and came out as expected:

```python
TROPHY = "Armory.json ladder (R1)"
    ("R1: starAlso [] (a Brutal clear no longer opens a band top)",
     lambda d: d["ctx"]["armory"]["ladder"].__setitem__("starAlso", []), {}, TROPHY, True),
    ("R1: starAlso ['normal'] (an easier star opens a band top)",
     lambda d: d["ctx"]["armory"]["ladder"].__setitem__("starAlso", ["normal"]), {}, TROPHY, True),
    ("R1: a difficulty after Brutal that starAlso leaves out",
     lambda d: d["expeditions"]["difficulties"].append("overdrive"), {}, TROPHY, True),
    ("R1 control: that difficulty listed in starAlso",
     lambda d: (d["expeditions"]["difficulties"].append("overdrive"),
                d["ctx"]["armory"]["ladder"].__setitem__("starAlso", ["brutal", "overdrive"])), {}, TROPHY, False),
```

### 2. `check_levels_mutants.py` SIM_CASES (R2)

- Each takes `("--check", "--levels-only", "--level", "forest")`.
- All five were run through `clm.sim_case`, and each went red on its own line.
- Each takes about 15 minutes, or about 30 under load.

| Label | Text | Replacement | `want` |
|---|---|---|---|
| R2: every family's scale from its slot's gear again (the pre-fix rule) | `    view["_scales"] = {key: {family: sc.damage_scale(armory, tier, 0, ability) for family, tier in tiers.items()}` | `    view["_scales"] = {key: {family: sc.damage_scale(armory, gear[cfg["weapons"][family]["slot"]], 0, ability) for family, tier in tiers.items()}` | `fights at each family's own tier` |
| R2: the bar from the gear, not the held pair | `    hp = gear_max_hp(armory, gear, cfg, held)` | `    hp = gear_max_hp(armory, gear)` | `the bar the held pair's (R2` |
| R2: the fire sniper's cast at the bow's scale | `        self.world.scale = self.armed["breath"] = held_scale(self.cfg, family, True)` | `        self.world.scale = self.armed["breath"] = self.cast_scale` | `Dragon's Breath fights at each family's own tier` |
| R2: the slam as the starter melee, not the held one | `        self.slam_scale = held_scale(cfg, held[0], False)` | `        self.slam_scale = held_scale(cfg, cfg["loadout"]["melee"], False)` | `fights at each family's own tier` |
| R2: the Flamethrower's pair at T1 again (unlike with like) | `PAIR_FLAME_GEAR = {"melee": 2, "ranged": 2}` | `PAIR_FLAME_GEAR = {"melee": 1, "ranged": 1}` | `the starter pair's mean clear with no down` |

What each mutant did:

- **Slot's gear again:** FAIL (5). The Frost Hammer fought at x1.5 instead of x11.118, and so did its slam.
- **Bar from the gear:** FAIL (1). The bar was 155 instead of 290.
- **Cast at the bow's scale:** FAIL (4). The cast was x1.5 instead of x2.475.
- **Slam as the starter melee:** FAIL (1). The slam was x1.5 instead of x11.118.
- **Pair back at T1:** FAIL (1). Seed 23 cleared in 3.93 min against a band of 4.00-5.75: the reviewer's finding.

### 3. The committed L3-26 SIM_CASE is stale

- **Cause:** the §12.9 edit made `SNIPER_KNOWN_LIMIT_L4` a multi-line dict, so its swap text
  `SNIPER_KNOWN_LIMIT_L4 = {"normal": ("LookoutLedge", "Secret_lookout")}` no longer occurs in `sim_range.py`. The
  case reports itself stale.
- **Fix:** replace its text with `    "normal": ("LookoutLedge", "Secret_lookout"),  # L2 W2: the cache moved into the cave`
  and its replacement with `    "normal": ("Secret_lookout",),  # L2 W2: the cache moved into the cave`, keeping
  the same `want`. I ran the corrected case through `sim_case`: it goes red on its own line ("Normal at gear 1/4
  (only the bow upgraded, L3-26): the sniper from LookoutLedge earns less ...", for example seed 11 at 34,216 /
  44.1 against 24,986 / 40.1).

### 4. The sim_combat hand mutant

`PAIR_FLAME_GEAR` at T3/T3 turns assertion 2 red, and only assertion 2. There is no committed harness for
sim_combat's assertions; if you want one, it is a scratch runner.

### 5. The row for L3-27's mirror table

The contract is your file, so this row is not in it yet. It is in BALANCE.

| Mirror | Mirrors | Owner |
|---|---|---|
| `sim_range.py` `gear_profile`, `held_pair`, `held_scale`, `level_view(held=)`, `gear_max_hp(held=)` (the level player's hit, pair-kit, slam, cast and breath scales; his bar and regen), held to the game by `armed_problems`; `sim_combat.py` `climb_runs(fire=)` | `WeaponService.damageScale` (TierOf of the striking family; the slam passes the held melee) and `gearOf` (`Armory.HeldTiers`) | designer |

### 6. A suggestion for A's file

`check_stage_mirror`'s Armory Problems op compares only `bool(problems)`, not the lines. During this round A's text
changed under mine, and the gate stayed green. Comparing the lines would catch that kind of drift.

### 7. One line for Ben (from the reviewer's M1)

In Studio, the I lever now puts a T5 weapon into the Forest: the Frost Hammer clears Forest Road in about 2.3 min
and the Colossus falls in about 14 s. That is a four-tier jump, and the Castle re-bands it.

### 8. Economy.luau

No formula change is needed.

### mutate.py

I need no entries: I changed no Luau.
