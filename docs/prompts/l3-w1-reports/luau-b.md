# L3 W1 — luau-engineer B (the combat place server): report

Worktree `C:\Users\benja\Desktop\tycoon-p5`, branch `l3-armory`. Nothing committed.

## Files changed or created

- `src/combat/server/Services/WeaponService.luau`: `damageScale` by family, `gearOf` reads the held tiers with no `provingGear` branch, `AddPlayer` takes up the saved loadout. `slotOfFamily` is gone and `CombatMode` is no longer required, so the file has one top-level local fewer than before.
- `src/combat/server/Services/UnlockService.luau`: `OnUpgradeWeapon`, the saving `OnSetFamily`, `GrantFirstClear`, `SetTier`, `ResetArmory`, and a `RemoveFamily` that saves.
- `src/combat/server/Services/WaveService.luau`: `starsOf` reads the profile; `EndRun` gives the first-clear reward; `readLevel` passes the weapons and starters to Validate; new `GrantStars` and `ForgetStars`.
- `src/combat/server/Services/StageFlow.luau`: `FirstClear`; Validate takes two optional trailing arguments and gains `firstClearProblems`.
- `src/combat/server/Services/VitalsService.luau`: the range body is `Armory.RangeHp`.
- `src/combat/server/Services/DebugService.luau`: L3-28, all levers.
- `tools/crowd_harness/tests_l3_run.luau` (new, 51 checks). A has already registered it in `run_harness.py`.

## Contracts implemented

**The exact `damageScale` expression** (`WeaponService.luau`, `damageScale(player, family, ability)`):

```luau
-- range: 1; no Armory.json: 1
slot  = (familyDef(Tuning.Get(), family) or {}).slot or ""
tier  = override ~= nil and override.gear[slot] (1 for no slot)
     or profile ~= nil and Armory.TierOf(armoryConfig, profile.combat, family)
     or 1
level = (override.ascension or profile.combat.ascension or {0,0})[slot] (0 for no slot)
return Armory.DamageScale(armoryConfig, tier, level, ability)
```

- The callers now pass:
  - `weapon` in resolveMelee and resolveRanged;
  - `family` in Strike and FireProjectile;
  - `shooter.loadout.melee` for the slam.
- Heavy, plate and armour are untouched: they stay unscaled.
- `WeaponService.DamageScale(player, family, ability)` now takes a family. It has no external callers.

**The exact `gearOf` expression:**

```luau
-- range: {1,1}, {0,0}
-- the Studio override, if any: clone(override.gear), clone(override.ascension)
-- no profile or no Armory.json: {1,1}, {0,0}
held = shooter ~= nil and shooter.loadout
    or Unlocks.LoadoutOf(combat, config.weapons, { melee = startingFamily(config,"melee"), ranged = startingFamily(config,"ranged") })
return Armory.HeldTiers(armoryConfig, combat, held.melee, held.ranged),
       { melee = combat.ascension.melee, ranged = combat.ascension.ranged }
```

- `WaveService.maxHpOf` is unchanged.

**AddPlayer** (mission only): the shooter's loadout is `Unlocks.LoadoutOf(profile.combat or nil, config.weapons, {startingFamily melee, startingFamily ranged})`, copied: `variants` is cloned. The range keeps its starters.

**UnlockService:**
- `OnUpgradeWeapon(player, family)`.
  - The range is ignored.
  - It answers `unavailable` when the player is not admitted, has no profile, or there is no Armory.json.
  - Otherwise it calls `Armory.Upgrade(cfg, combat, family, Unlocks.OwnsFamily(combat.families, family, starters()), gate(player), state.built)`. `state.built` is the set of `Catalog.GetLevelIds()` made at Init.
  - On nil, in this order: `SetGearOverride(player, nil)`, `RefreshMaxHp`, ActionResult ok (`action = "upgradeWeapon"`, `slotId = family`), Snapshot.
  - A refusal sends its reason. No yield sits between the verdict and the write.
- `OnSetFamily`: after the verdict and the hold it runs `Unlocks.SaveLoadout(combat, slot, family, variant)`, `RefreshMaxHp`, the ActionResult, then a Snapshot.
- `GrantFirstClear(player, reward: Types.LevelFirstClear): Types.FirstClearGrant?`
  - The family goes into `families`. An unknown family or a starter is skipped with a warn. A family already owned is not reported as given.
  - A whole Valor above 0 goes into `valor`.
  - It sends a Snapshot. It returns nil when there is no profile or nothing was given.
- `SetTier(player, family, tier): number?` uses `Armory.SetTier`, then clears the override, refreshes the bar and sends a Snapshot.
- `ResetArmory(player?): { Player }` uses `Unlocks.ResetArmory`. It puts both starters back in their slots at their default styles, clears the override, refreshes the bar and sends a Snapshot.
- `RemoveFamily`, when the removed family is held: it holds the starter (keeping its session style), runs `SaveLoadout` and `RefreshMaxHp`. When the family is only in the save, it clears that slot (nil = the starter).

**WaveService:**
- `starsOf(userId)` returns `Unlocks.StarsOf(profile.combat)` for a human member with a loaded profile, and the session table otherwise.
- In `EndRun`, when Award returns true: `reward = StageFlow.FirstClear(level, difficulty)`, then `given = UnlockService.GrantFirstClear(player, reward)`. If `given.valor > 0`, it calls `ArenaService.CreditSummary(userId, 0, "", 0, valor, 0)` before `BroadcastSummary`. `RunResult.firstClear = given`.
- `WaveService.GrantStars(player, levelIds, difficulty): number` sends MapState to everyone.
- `WaveService.ForgetStars(player?)` clears the session stars and sends MapState.

**StageFlow:**
- `StageFlow.FirstClear(level, difficulty): Types.LevelFirstClear?` returns a fresh table. A family that is not a non-empty string, or a Valor that is not a whole number above 0, is left out; nil when nothing is left.
- `StageFlow.Validate(level, layout, kinds, ranks, rules, crowdMax, weapons?, starters?)`. Without the two new arguments, the family is checked as an id only, so every existing caller still works. The lines, in difficulty-name order:
  - `difficulties.<d>.firstClear is not a table`
  - `….family is <x>, not a family id`
  - `….family names "<x>", which is no weapons family`
  - `….family names the starter "<x>", which everyone owns`
  - `….valor is <x>, not a whole number of at least 0`

**VitalsService:** the range's `maxHpFor` returns `Armory.RangeHp(armoryConfig)`.

**DebugService (L3-28):**
- `setGear`:
  - always writes the session override, never `gear`;
  - refuses with a warn any tier outside 1..`Armory.LadderSize`.
- `gear` (G):
  - the presets are checked against the ladder;
  - the remembered preset counts only while it still matches what the player fights at (an upgrade or reset clears the override behind it).
- `grantMaterials` in the lobby pays each built band's material, from `Armory.BuiltBands`.
- `setTier` reads its value with `Unlocks.TierLever`.
- `grantStar` takes a level id or `"*"` (the built band levels) and gives `ladder.starDifficulty`. Its notice reads "★ Hard: Forest Road".
- `resetArmory` calls `UnlockService.ResetArmory`, clears the G memory, and calls `WaveService.ForgetStars`.
- The attribute path reads `setTierAttribute`, `grantStarAttribute` and `resetArmoryAttribute`; each is optional, and nil turns that lever off.

**New requires:**
- WeaponService → Unlocks (it no longer requires CombatMode).
- UnlockService → Armory, VitalsService.
- WaveService → Unlocks.
- DebugService → Unlocks (it no longer requires CombatMode).

None of them adds a cycle:
- Unlocks requires only Types; Armory requires nothing.
- VitalsService requires only CrowdBrain, CrowdService and ThreatField, and none of those requires UnlockService, WaveService or DebugService.
- UnlockService already required WeaponService, which requires VitalsService.

## Assumptions

- A family already owned when its first clear lands (a Studio lever, or `resetArmory` followed by a new Hard clear) is not reported as given. The summary card then says nothing about the family.
- `resetArmory` puts the starters back at their default styles and leaves the session styles of other families alone, because an equip always carries a style.
- `RequestDebug "resetArmory"` ignores its value.
- I used A's shared helpers (`Armory.SetTier`, `Armory.BuiltBands`, `Unlocks.TierLever`, `Unlocks.ResetArmory`) and types (`Types.ActionReason`, `Types.FirstClearGrant`, `Types.LevelFirstClear`). The levers therefore follow one rule in both places.

## For the other owners

**luau-engineer A, `mutate.py`.**

Re-aim one entry. My VitalsService change made it stale:

```python
"17: the body keeps the profile's health": (VITALS, "\treturn Armory.RangeHp(armoryConfig)\n", "\treturn nil\n"),
```

Add these, all with `FLOW` (StageFlow). StageFlow is already in `FILES`.

```python
"l3: Validate skips the first clears": (FLOW, "\tfirstClearProblems(level, weapons, starters, problem)\n", ""),
"l3: a firstClear that is no table is accepted": (FLOW, "\t\t\tproblem(`{where} is not a table`)\n", ""),
"l3: a first-clear family of any length is accepted": (FLOW, " or #id > Unlocks.MAX_FAMILY_LENGTH", ""),
"l3: an empty first-clear family is accepted": (FLOW, 'if type(id) ~= "string" or id == "" or #id > Unlocks.MAX_FAMILY_LENGTH then', 'if type(id) ~= "string" or #id > Unlocks.MAX_FAMILY_LENGTH then'),
"l3: a first clear may name an unknown family": (FLOW, "elseif weapons ~= nil and weapons[id] == nil then", "elseif false then"),
"l3: a first clear may name a starter": (FLOW, "elseif starters ~= nil and starters[id] == true then", "elseif false then"),
"l3: a fractional first-clear Valor is accepted": (FLOW, "valor ~= nil and not (isFinite(valor) and valor >= 0 and valor % 1 == 0)", "valor ~= nil and not (isFinite(valor) and valor >= 0)"),
"l3: a negative first-clear Valor is accepted": (FLOW, "valor ~= nil and not (isFinite(valor) and valor >= 0 and valor % 1 == 0)", "valor ~= nil and not (isFinite(valor) and valor % 1 == 0)"),
"l3: the first-clear lines come in the table's order": (FLOW, "\ttable.sort(names)\n", ""),
"l3: FirstClear keeps an empty family": (FLOW, 'family = if type(family) == "string" and family ~= "" then family else nil,', 'family = if type(family) == "string" then family else nil,'),
"l3: FirstClear keeps a fractional Valor": (FLOW, "valor = if isFinite(valor) and valor > 0 and valor % 1 == 0 then valor else nil,", "valor = if isFinite(valor) and valor > 0 then valor else nil,"),
"l3: FirstClear keeps a Valor of 0": (FLOW, "valor = if isFinite(valor) and valor > 0 and valor % 1 == 0 then valor else nil,", "valor = if isFinite(valor) and valor >= 0 and valor % 1 == 0 then valor else nil,"),
"l3: FirstClear gives an empty reward": (FLOW, "\tif given.family == nil and given.valor == nil then\n\t\treturn nil\n\tend\n", ""),
"l3: FirstClear hands out the level file's table": (FLOW, "\treturn given\nend\n", "\treturn reward\nend\n"),
"l3: FirstClear reads the hard difficulty whatever is asked": (FLOW, "then difficulties[difficulty] else nil", "then difficulties.hard else nil"),
```

- Each target occurs exactly once in its file. Each entry fails at least one check: I ran all 16 against a scratch copy of `src/`, and all were caught.
- `mutate.py` also has two stale entries in A's own files: "l2: the schema stays at v6" (ProfileSchema) and "l2w2: HasElement ignores ownership" (Unlocks, now 2 occurrences).

**luau-engineer A, Types.** There is no gap: `ActionReason`, `FirstClearGrant`, `LevelFirstClear`, `LevelDifficulty.firstClear`, `RunResult.firstClear` and the three attribute keys are all as I code against them.

**economy-designer.**
- `sim_range`'s Validate mirror (L3-27) may want the five firstClear lines above, word for word.
- `check_stage_mirror.py` calls Validate with 6 arguments, so the family is checked as an id only, and it passes. It lists `FirstClear` among the functions the simulators do not mirror.

**ui-engineer B.**
- The DebugPanel's tier buttons must send `setTier` with a value matching `^[%w_]+=%d+$` (no spaces), because `Unlocks.TierLever` reads it.
- `grantStar` takes `"*"` or a level id.
- `resetArmory` takes any value.

## Checks run

- stylua `--check` and selene: clean on all seven files.
- `luau-lsp analyze` on `src/combat` and `src/shared`, against a scratch sourcemap of `combat.project.json`: clean.
- `py tools/check_compile.py`: PASS (177 files).
- Harness: `HARNESS: PASS (3,537 checks)`. That includes `tests_l3_run.luau`, 51 checks.
- `check_stage_mirror.py`: PASS.
- `rojo build combat.project.json` to scratch: OK.
- Nothing outside my files was edited.

## What to check in Studio

1. In `proving.rbxl`, buy T2 for the Longbow in the lobby Armory.
   - The bar grows on the spot: 155 → 165 at T2/T1.
   - Its hits are ×2.475 on the next run.
   - The Sword stays ×1.5.
2. Press G (T3), then buy an upgrade. The override clears, and the tiers you bought rule again.
3. Equip a family in the lobby and leave. On the next admit, with Studio API access and a real profile, the saved family is held. With the mock profile, it resets each session.
4. Clear Forest Road on Hard.
   - The summary reports the Warhammer and the Hard star.
   - The map shows the star.
   - T4 opens for an owned weapon at T3.
5. Press U: "★ Hard: Forest Road", and the map updates.
6. Press L:
   - tiers, loadout and stars are gone;
   - the starters are held again;
   - the bar is 155.
7. In the range (DebugProving bench), the body is still 130.
