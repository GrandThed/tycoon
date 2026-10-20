# L3 W1 fix round — luau-engineer B' (the combat place server): report

Worktree `C:\Users\benja\Desktop\tycoon-p5`, branch `l3-armory`. Nothing committed. Coded against A's
signatures (`docs/prompts/l3-w1-fix-reports/luau-a.md`). They landed during the round and match what is used here.

## Files changed

- `src/combat/server/Services/WeaponService.luau`:
  - `damageScale` and `gearOf` both call `Armory.StrikeTier` (R3, 2-s1).
  - New `WeaponService.GearOverride`.
- `src/combat/server/Services/WaveService.luau`: `GrantStars` pays the first-clear reward of each new star (R4).
- `src/combat/server/Services/DebugService.luau`:
  - `grantStar` uses `Unlocks.ALL_STARS`, and its notice names the reward.
  - G and `setGear` compare against the override as it was set.
- `src/combat/server/Main.server.luau`: the Snapshot's `gearPower` is `Armory.SavedPower` (R7).
- `UnlockService.luau`: **no change needed.**
  - `GrantFirstClear` already handles a family that is already owned (not given again), and Valor.
  - `OnUpgradeWeapon`'s gate line is unchanged, so A's text check can target it as it stands.

## Contracts implemented

**`damageScale(player, family, ability)`** (the range gives 1; no Armory.json gives 1):

```luau
overrideTier = override and (slot == "melee" and override.gear.melee or slot == "ranged" and override.gear.ranged) or nil
ascension    = override.ascension, else combat.ascension, else {0,0}
local tier = Armory.StrikeTier(armoryConfig, combat, family, overrideTier)
return Armory.DamageScale(armoryConfig, tier, level, ability)
```

**`gearOf(player)`** (the range and no Armory.json give 1/1, 0/0):

```luau
held = shooter.loadout, else Unlocks.LoadoutOf(combat, config.weapons, {startingFamily melee, startingFamily ranged})
local meleeOverride = if gear ~= nil then gear.melee else nil
local rangedOverride = if gear ~= nil then gear.ranged else nil
return {
	melee = Armory.StrikeTier(armoryConfig, combat, held.melee, meleeOverride),
	ranged = Armory.StrikeTier(armoryConfig, combat, held.ranged, rangedOverride),
}, { melee = ascension.melee, ranged = ascension.ranged }   -- the override's ascension, else the profile's, else 0/0
```

So the bar and the hits always read one tier.
- G at T1 with the Flamethrower held: T2. With the Frost Hammer held: T5.
- The bar follows the same rule. With the Flamethrower held it is 165 at G T1.

**`WeaponService.GearOverride(player): SlotTiers?`** (new) returns the override's raw tiers as set, or nil when no override is set.
- **Why it is needed.** With the clamp in place, G's T1 fights a held Flamethrower at T2. That matches no preset, so `nextGear` would set T1 on every press.
- `nextGear` now reads `GearOverride(player) or GearOf(player)`.
- `setGear` keeps an unnamed slot at `GearOverride(target) or fought`.

**`WaveService.GrantStars(player, levelIds, difficulty): (number, { Types.FirstClearGrant })`**:
- The return type is now a pair. Its only caller is DebugService.
- For each new star (`StageFlow.Award` true):
  1. `level = resolveLevel(levelId, difficulty, combatConfig, map)`, the same read a run makes;
  2. `reward = StageFlow.FirstClear(level, difficulty)`;
  3. `grant = UnlockService.GrantFirstClear(player, reward)`, the same path EndRun uses.
- An old star pays nothing.
- It now returns at once unless `boot.mission and RunService:IsStudio()`, so the payer itself is Studio only.
- The local is named `grant`, not `given`, so EndRun's line `local given = if reward ~= nil then UnlockService.GrantFirstClear(player, reward) else nil` stays unique.

**DebugService `grantStar`:**
- It compares `which == Unlocks.ALL_STARS`.
- The notice reads `★ Hard: Forest Road · Warhammer`: each family given, by name, plus `+N Valor` when any was paid.

**Main `sendSnapshot`:**

```luau
gearPower = Armory.SavedPower(armoryConfig, state.combat, provingConfig.weapons or nil, provingConfig.loadout or { melee = "", ranged = "" })
```

This is the hub's inputs (`Catalog.GetProvingGroundsConfig()`). `WeaponService.GearOf` is no longer read in Main.

**Requires:** none new. Main already had Armory and Catalog; WaveService already had RunService, Catalog and UnlockService.

## Assumptions

- **R7: the dungeon's Power readout no longer moves with G or `setGear`.** It shows the saved pair, as the hub's readout does. Tell Ben if he reads Power after pressing G.
- **The override and the window.**
  - An override set while Armory.json is absent reads 1/1 in `gearOf`. Every reader needs Armory.json anyway.
  - `damageScale` without a loaded profile gives a family's window start. That is T1 for a starter, and a non-starter cannot be held without a profile.
- **G's presets.**
  - With no override, the presets are matched against `GearOf` (clamped).
  - Holding the Flamethrower, the first G press therefore says "Gear T1" and changes nothing visible (it fights at T2 either way). The next press goes to T3.

## Required changes outside my files

**luau-engineer A' (or the lead): text checks in `run_harness.py`** (exact lines, each counted once in the body named):
- **WeaponService `gearOf`:**
  - `melee = Armory.StrikeTier(armoryConfig, combat, held.melee, meleeOverride),`
  - `ranged = Armory.StrikeTier(armoryConfig, combat, held.ranged, rangedOverride),`
  - `local meleeOverride = if gear ~= nil then gear.melee else nil`
  - `local rangedOverride = if gear ~= nil then gear.ranged else nil`
- **WeaponService `damageScale`:**
  - `local tier = Armory.StrikeTier(armoryConfig, combat, family, overrideTier)`
  - `then gear.melee`
  - `elseif slot == "ranged" then gear.ranged`
- **WeaponService, the whole file:** `Armory.StrikeTier(` occurs 3 times.
- **WaveService `function WaveService.GrantStars`:**
  - `if not StageFlow.Award(stars, levelId, difficulty) then`
  - `local reward = if level ~= nil then StageFlow.FirstClear(level, difficulty) else nil`
  - `local grant = if reward ~= nil then UnlockService.GrantFirstClear(player, reward) else nil`
  - `if not boot.mission or not RunService:IsStudio() then`
- **WaveService, the whole file:** `UnlockService.GrantFirstClear(` now occurs **twice** (EndRun and GrantStars). Count EndRun's call inside EndRun's body, or by its own `local given = …` line.
- **DebugService:**
  - `if which == Unlocks.ALL_STARS then`;
  - no `== "*"` anywhere in the file;
  - in `nextGear`: `local gear = WeaponService.GearOverride(player) or WeaponService.GearOf(player)`;
  - in `setGear`: `local gear = WeaponService.GearOverride(target) or fought`.
- **Main:**
  - `then Armory.SavedPower(` followed by `state.combat,`;
  - `WeaponService.GearOf(` occurs 0 times.

**`mutate.py` entries** (label, file, exact text, replacement). Each target occurs exactly once; I counted them all. DebugService is not yet in `FILES`: add `DEBUG_SERVICE = "src/combat/server/Services/DebugService.luau"` with `FILES.append(DEBUG_SERVICE)`. `WEAPON`, `WAVE_SERVICE` and `MAIN_SERVER` exist.

```python
"l3fix R3: a hit ignores its family's tier": (WEAPON, "local tier = Armory.StrikeTier(armoryConfig, combat, family, overrideTier)", "local tier = 1"),
"l3fix R3: a hit ignores the Studio override": (WEAPON, "local tier = Armory.StrikeTier(armoryConfig, combat, family, overrideTier)", "local tier = Armory.StrikeTier(armoryConfig, combat, family, nil)"),
"l3fix 2-s1: the override reaches a hit unclamped": (WEAPON, "local tier = Armory.StrikeTier(armoryConfig, combat, family, overrideTier)", "local tier = overrideTier or Armory.TierOf(armoryConfig, combat, family)"),
"l3fix R3: a melee hit reads the ranged override": (WEAPON, "\t\t\tthen gear.melee\n", "\t\t\tthen gear.ranged\n"),
"l3fix R3: the bar's melee tier is T1": (WEAPON, "melee = Armory.StrikeTier(armoryConfig, combat, held.melee, meleeOverride),", "melee = 1,"),
"l3fix R3: the bar's ranged tier is the melee family's": (WEAPON, "ranged = Armory.StrikeTier(armoryConfig, combat, held.ranged, rangedOverride),", "ranged = Armory.StrikeTier(armoryConfig, combat, held.melee, rangedOverride),"),
"l3fix 2-s1: the bar reads the override unclamped": (WEAPON, "melee = Armory.StrikeTier(armoryConfig, combat, held.melee, meleeOverride),", "melee = meleeOverride or Armory.TierOf(armoryConfig, combat, held.melee),"),
"l3fix R3: the bar ignores the override": (WEAPON, "local meleeOverride = if gear ~= nil then gear.melee else nil", "local meleeOverride = nil"),
"l3fix R4: a lever star pays nothing": (WAVE_SERVICE, "local grant = if reward ~= nil then UnlockService.GrantFirstClear(player, reward) else nil", "local grant = nil"),
"l3fix R4: a lever star reads no reward": (WAVE_SERVICE, "local reward = if level ~= nil then StageFlow.FirstClear(level, difficulty) else nil", "local reward = nil"),
"l3fix R4: a lever star pays the Normal reward": (WAVE_SERVICE, "local reward = if level ~= nil then StageFlow.FirstClear(level, difficulty) else nil", 'local reward = if level ~= nil then StageFlow.FirstClear(level, "normal") else nil'),
"l3fix R4: an old lever star pays again": (WAVE_SERVICE, "\t\tif not StageFlow.Award(stars, levelId, difficulty) then\n\t\t\tcontinue\n\t\tend\n", "\t\tStageFlow.Award(stars, levelId, difficulty)\n"),
"l3fix R4: the lever pays on a live server": (WAVE_SERVICE, "if not boot.mission or not RunService:IsStudio() then", "if not boot.mission then"),
"l3fix 3-s2: the star wildcard is spelled in DebugService": (DEBUG_SERVICE, "if which == Unlocks.ALL_STARS then", 'if which == "*" then'),
"l3fix 2-s1: G matches its presets against the clamped bar": (DEBUG_SERVICE, "local gear = WeaponService.GearOverride(player) or WeaponService.GearOf(player)", "local gear = WeaponService.GearOf(player)"),
"l3fix 2-s1: setGear keeps the clamped tier of an unnamed slot": (DEBUG_SERVICE, "local gear = WeaponService.GearOverride(target) or fought", "local gear = fought"),
"l3fix R7: the dungeon Power reads a fresh profile": (MAIN_SERVER, "then Armory.SavedPower(\n\t\t\t\tarmoryConfig,\n\t\t\t\tstate.combat,\n", "then Armory.SavedPower(\n\t\t\t\tarmoryConfig,\n\t\t\t\tnil,\n"),
```

- The six R3 lines the fix-round file lists are A's entries, on unchanged text:
  - the slam, `StrikeTally.New(damageScale(player, shooter.loadout.melee, false))`;
  - `OnUpgradeWeapon`'s `gate ~= nil and gate(player)`;
  - EndRun's `local given = …`;
  - `starsOf`'s profile branch;
  - `readLevel`'s `tuned.weapons,` / `Unlocks.Starters(tuned.loadout)`.
- The harness never loads these services, so only the text checks above can kill these mutants. The 3-s2 mutant changes no behaviour at all.

**docs-keeper (through the lead): PLAYTEST L3-33.**
- U now pays the Warhammer: the notice reads "★ Hard: Forest Road · Warhammer".
- A Hard clear after U therefore shows no new star and no Warhammer on the card. That is expected.
- To see the card itself pay the Warhammer, clear Hard in a fresh session without pressing U first. L takes the star but not the family. So after U, L and a Hard clear, the card shows the star and no Warhammer, unless the `removeFamily` lever took the Warhammer back first.

## Checks run

| Check | Result |
|---|---|
| stylua `--check` and selene, on my five files | clean |
| luau-lsp, `src/combat` + `src/shared` (scratch combat sourcemap) | 0 diagnostics |
| luau-lsp, `src/server` + `src/shared` + `src/client` (scratch default sourcemap) | 0 diagnostics |
| `py tools/check_compile.py` | PASS (178 files) |
| `rojo build combat.project.json` to scratch | OK |
| Harness, before A's new `ProfileCopy` landed | `HARNESS: PASS (3,539 checks)` |
| Harness, last run | FAIL: `bundle.luau: no source for ProfileCopy` |

The last harness failure is A's new module, not yet in `SOURCES`. None of my files is in the harness bundle.

## What to check in Studio

1. **Upgrades and G.**
   - Lobby, fresh profile: buy Longbow T2. The bar is 165 and the Power is 77, the same number in the hub and in the dungeon.
   - Press G (T3), then buy an upgrade. The override clears.
2. **The clamp.**
   - Hold the Flamethrower (F, then equip) and press G until "Gear T1". The bar stays 165 and the flame hits ×2.475: T2, not T1.
   - Further G presses step T3 → T5 → T1 and do not stick at T1.
3. **The Frost Hammer.** With it held (I), every G preset fights at T5 or above. The bar is at least 290 with the Longbow at T1.
4. **U.**
   - The notice reads "★ Hard: Forest Road · Warhammer".
   - The Armory shows the Warhammer owned, and T4 opens for a weapon at T3.
   - Press U again: the star is already held, so the notice names no reward.
5. **U, then a Hard clear.** The card shows no new star and no Warhammer.
6. **G and Power.** Power in the dungeon does not change with G (it shows the saved pair).
