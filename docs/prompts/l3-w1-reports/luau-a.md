# L3 W1: luau-engineer A's report (shared rules, saving, hub server)

Worktree `C:\Users\benja\Desktop\tycoon-p5`, branch `l3-armory`. Nothing is committed. Every gate is green against
the designer's data, which landed during the wave.

## Files changed or created

- `src/shared/Armory.luau`: rewritten tier path (L3-1 to L3-8). It is still require-free. The C1 readers keep
  `TierDef`, `WeaponDamage`, `ClassDef` and `AbilityDef`, and the hub keeps the Ascension trio.
- `src/shared/Unlocks.luau`: added `LoadoutOf`, `SaveLoadout`, `StarsOf` and the lever pieces `ResetArmory` and
  `TierLever`.
- `src/shared/Types.luau`: every type change in the contract (listed below).
- `src/shared/Combat.luau`: the structural copies of `CombatProfile` and `ArmoryConfig` only, per the lead's ruling.
  No behaviour change.
- `src/server/Services/ProfileSchema.luau`: v8, the template and `Migrations[7]`.
- `src/server/Services/ArmoryService.luau`: `tryBuyGear` is gone. Added `RequestUpgradeWeapon`, `RequestSetFamily`
  and the hub levers.
- `src/server/Services/EconomyService.luau`: the deep copy and Gear Power.
- `tools/crowd_harness/tests_l3.luau` (new, 225 checks).
- `tools/crowd_harness/run_harness.py`:
  - registers `tests_l3`, `tests_l3_run` and `tests_l3_ui`;
  - adds `Format` and `ArmoryModel` to SOURCES.
- `tools/crowd_harness/tests_l2.luau`: its v6 profile now runs on to v8.
- `tools/crowd_harness/mutate.py`:
  - added my 71 entries, B's 16 and ui A's 22;
  - re-aimed three stale entries;
  - added `Format.luau` and `ArmoryModel.luau` to FILES.
- `tools/check_stage_mirror.py` and `tools/crowd_harness/stage_mirror.luau`:
  - the Armory comparisons;
  - `StageFlow.FirstClear`;
  - Validate's firstClear refusals;
  - every Validate is now handed the weapons and the starters on both sides.

## API as built

`src/shared/Armory.luau`:

```luau
Armory.LadderSize(cfg): number
Armory.Window(cfg, family): (number?, number?)           -- nil, nil = none (no ladder, no window, malformed)
Armory.TierOf(cfg, combat: CombatProfile?, family): number
Armory.HeldTiers(cfg, combat?, melee, ranged): SlotTiers
Armory.Multiplier(cfg, tier): number
Armory.DamageScale(cfg, tier, ascLevel, ability): number
Armory.WeaponHp(cfg, slot, tier, ascLevel): number
Armory.MaxHp(cfg, tiers: SlotTiers, ascension: SlotTiers): number
Armory.RangeHp(cfg): number
Armory.GearPower(cfg, tiers, ascension): number
Armory.BandOf(cfg, tier): (number, number)               -- (0, 0) outside 1..LadderSize, or not whole
Armory.NextTier(cfg, combat?, family): number?
Armory.TierCost(cfg, tier): (string, number)             -- ("", 0) outside, for a band without level/material, or no cost
Armory.Preview(cfg, slot, tier, baseDamage): (number, number)
Armory.UpgradeVerdict(cfg, combat, family, owned, gateOpen, built): UpgradeRefusal?
Armory.Upgrade(cfg, combat, family, owned, gateOpen, built): UpgradeRefusal?
Armory.SetTier(cfg, combat, family, tier): number?       -- the L3-28 lever: held to the window, the tier written
Armory.BuiltBands(cfg, built): ({ string }, { string })  -- built band level ids, their materials (each once)
Armory.LegacyRefund(cfg, gear: SlotTiers): { [string]: number }
Armory.Problems(cfg, families: { string }): { string }
export type UpgradeRefusal = "invalid" | "locked" | "peak" | "busy" | "notBuilt" | "needsStar" | "insufficientFunds"
```

Deleted, as the contract asks: `CanBuy`, `TierUnlockRate`, `BandMaterial`, and the slot-shaped versions of `NextTier`,
`TierCost`, `WeaponHp`, `MaxHp`, `GearPower` and `DamageScale`.

How the tier rules read their inputs:
- **Not a whole number.** These degrade the same way as the sim_combat mirror:
  - a saved tier reads the window's start;
  - `Multiplier` reads ×1;
  - `WeaponHp` reads 0;
  - a slot tier in `LegacyRefund` pays nothing.
- **A whole number outside the ladder** is held inside it.
- **A bad config entry.** A multiplier that is not above 0 reads ×1. An HP entry below 0 reads 0. A `rangeHp` that is
  not above 0 falls back to `baseHp`.
- **`notBuilt`** also covers a tier that has no price, so nothing can be bought for free.
- **`Problems`** also reports:
  - a window that names no family;
  - a missing or broken `legacy.gearCosts`;
  - a `tierWeight` that is not a number;
  - an empty `starDifficulty`.

`src/shared/Unlocks.luau`:

```luau
Unlocks.LoadoutOf(combat: Types.CombatProfile?, weapons?, fallback: { melee: string, ranged: string }): Types.RangeLoadout
Unlocks.SaveLoadout(combat, slot, family, variant): ()     -- makes loadout/variants when missing; other slots write nothing
Unlocks.StarsOf(combat): { [string]: { [string]: boolean } }
Unlocks.ResetArmory(combat): ()                            -- tiers, loadout, stars emptied (fresh tables)
Unlocks.TierLever(value: any): (string?, number?)          -- "<family>=<tier>", ^[%w_]+=%d+$, id <= 24 bytes
```

In `LoadoutOf`, "owned" means a starter of `fallback` or a family the profile's `families` holds true for. The
function always returns fresh tables.

`src/shared/Types.luau`:
- New types:
  - `ActionReason`, which is `ActionResult.reason` and adds `peak`, `notBuilt` and `needsStar`;
  - `SavedLoadout`;
  - `ArmoryLadderBand`, `ArmoryLadder`, `ArmoryWindow`, `ArmoryLegacyCost` and `ArmoryLegacy`;
  - `LevelFirstClear` and `FirstClearGrant`.
- Changed types:
  - `ActionResult.action` gains `"upgradeWeapon"` and loses `"buyGear"`;
  - `CombatProfile` gains `tiers?`, `loadout?` and `stars?`;
  - `ArmoryConfig` gains `ladder?`, `windows?`, `legacy?` and `power.tierWeight?`;
  - `LevelDifficulty.firstClear?`;
  - `RunResult.firstClear?`;
  - `CombatDebugConfig` gains `setTierAttribute?`, `grantStarAttribute?` and `resetArmoryAttribute?`.
- B confirmed that Types has no gap.

`ProfileSchema` (v8):
- **The template** adds `tiers = {}`, `loadout = { variants = {} }` and `stars = {}`. It names no family id.
- **`Migrations[7]`:**
  - adds each of the three only when it is nil, always as a fresh table;
  - adds `loadout.variants` when a loadout lacks it;
  - then refunds through `Armory.LegacyRefund(Catalog.GetArmoryConfig(), combat.gear)`.
- **Without Armory.json** it adds the fields, refunds nothing and warns once. The version stamp still moves.
- `gear` is never touched.

Hub `ArmoryService`:
- **`RequestUpgradeWeapon(family)`:**
  - `unavailable` when there is no profile, no Armory.json or no ProvingGrounds.json;
  - otherwise `Armory.Upgrade(...)` with `gateOpen = true` and `built` = `Catalog.GetLevelIds()`, read at Init.
- **`RequestSetFamily(slot, family, variant)`:** `Unlocks.FamilyVerdict(..., true)`, then `Unlocks.SaveLoadout`.
- **Results:** both reply with `MarkDirty({ combat = true })` and an ActionResult. Reasons are narrowed through one
  `Types.ActionReason` table.
- **Unchanged:** `RequestAscend`.
- **At Init:** warns every `Armory.Problems` line.
- **Levers.** `HandleDebug` and the 1 Hz attribute poll both take three new levers:
  - `setTier`: `Unlocks.TierLever`, then `Armory.SetTier`;
  - `grantStar`: a level id with a level file, or `"*"` for `Armory.BuiltBands`. It writes the ladder's
    `starDifficulty` star.
  - `resetArmory`: `Unlocks.ResetArmory`.
- **`grantMaterials`** now pays every built band's material (Timber today) instead of the era band.
- **Feedback:** hub levers log with `warn`, because the hub has no notice channel.

`EconomyService`:
- `copyCombatProfile` deep-copies `abilities`, `secrets`, `families`, `shortcuts`, `tiers`, `loadout` and `stars`.
  Each is nil-safe.
- `computeGearPower` = `Armory.GearPower(HeldTiers(LoadoutOf(combat, weapons, config.loadout)), ascension)`. Without
  ProvingGrounds.json it reads T1/T1.

## Tests added

`tests_l3.luau` has 225 checks in 10 groups. They run on a fixture built from the contract's own numbers, so a data
change cannot hide a rule change. The shipped data is then pinned to the same numbers.

- **Ladder and windows:**
  - `Window`: held inside the ladder; every malformed shape;
  - `TierOf`: below the start, above the top, a window narrowed or moved under a saved tier, not whole, NaN or
    infinite, no window, no ladder;
  - `HeldTiers`, `NextTier`.
- **Strength:**
  - `Multiplier`, `DamageScale` with Ascension, `WeaponHp`;
  - `MaxHp` (1,1) 155, (3,3) 230, (5,5) 380;
  - `RangeHp` 130;
  - `GearPower` 64 at T1/T1;
  - `Preview`.
- **Costs:** `BandOf`, and `TierCost` by position (T2 100, T3 250, T4 500 Timber; T5 Iron).
- **The verdict:** every reason in order, each case set up so that every later reason applies too. Also the band top
  with and without the star, a Normal star, a false star, the Castle's own star, a priceless tier and a band with no
  level.
- **`Upgrade`:**
  - it writes once and spends once;
  - a refusal leaves the profile deep-equal;
  - it creates the `tiers` table when there is none;
  - the wallet never goes below 0.
- **Lever pieces:** `SetTier`, `BuiltBands`, `TierLever`, and `LegacyRefund` (3/3 → 500 Timber, 4/2 → 320 Timber +
  10 Steel, the cap, a fresh table each call).
- **`Problems`:** sound on the fixture, and 25 single-rule breaks each named.
- **`LoadoutOf`:** each fallback (no profile, unknown, unowned, wrong slot, unknown style, not a table, no weapons
  config); fresh tables. Also `SaveLoadout`, `StarsOf` and `ResetArmory`.
- **`Migrations[7]`:**
  - a fresh template;
  - a v7 3/3 profile reaches v8 with +500 Timber, `gear` untouched and no aliasing;
  - run through the runner again, it is not paid twice. Calling the step alone twice does pay twice, which proves
    the stamp is the guard;
  - Reconcile first; a loadout without its variants;
  - 4/2 refunds 320 Timber and 10 Steel;
  - a v8 profile is untouched by the runner, and by a v7 template's Reconcile;
  - no Armory config.
- **As shipped:**
  - the ladder, HP T1–T11, rangeHp, bands, costs, starDifficulty and tierWeight;
  - the 15 windows of table L3-3;
  - `legacy.gearCosts` pinned byte for byte, and checked against the old `slots` prices;
  - `Problems` finds nothing;
  - both starters start at T1;
  - the first band's level has a level file.

## Gate results

| Gate | Result |
|---|---|
| Harness | `HARNESS: PASS (3,539 checks, …tycoon-p5\tools\crowd_harness)`. Baseline before the wave: 3,154. |
| `py tools/check_stage_mirror.py` | `CHECK: PASS`, against the designer's mirrors (details below). |
| mutate.py, filter `l3` (my 71 + B's 16 + ui A's 22) | 109 run, 0 not caught |
| mutate.py, the three re-aimed entries | 3 run, 0 not caught |
| mutate.py, the whole list | 1,298 entries, 0 out of date. The full run was not done here; QA owns it. |
| `py tools/check_compile.py` | PASS, 177 files. None of my files is in the top ten by locals. |
| stylua `--check` and selene on my 7 Luau files | clean |
| luau-lsp, both sourcemaps (fresh `rojo sourcemap` in scratch, `tools/types/globalTypes.d.luau`) | No error in any file of mine, or anywhere on the hub sourcemap. The combat sourcemap shows one error, in `PlotService:1388`: a hub-only service whose `World` folder is not mapped. That error predates this wave. |
| `rojo build` default and combat, into scratch | OK |

`check_stage_mirror` details:
- **Armory:** 19 functions compared (17 rules plus `SetTier` and `BuiltBands`). The configs are the shipped one, one
  without a ladder, one with narrowed windows and one of edge cases, over grids of tiers, 11 saved profiles,
  owned/gate flags and 4 built sets. That is 2,816 `UpgradeVerdict` rows per config.
- **Problems:** 20 cases.
- **`StageFlow.FirstClear`:** 10 cases.
- **Validate's firstClear lines:** 13 cases, refused alike.

Two ways I checked the new comparisons themselves (`mirror_mutants.py` is not my file):
- Four Armory mutants run with `--module Armory=` all fail the check: BandOf's position, TierOf's start, the band-top
  star, and SetTier's clamp.
- A stand-in `first_clear` with `valor >= 0` fails it too.

## v8 forward compatibility (L2 W1 §10's rule)

v7 code, today's `main`, loading a v8 profile:
- `profile:Reconcile()` runs first (`DataService.luau:217`). That is `Profile:Reconcile` → `ReconcileTable`
  (`ProfileStore.luau:1086-1087`, `408-422`). It only fills string keys that are nil, from v7's own template, and
  deletes nothing. So `tiers`, `loadout` and `stars` survive.
- `runMigrations` (`DataService.luau:90-110`) then skips its loop (`:91`, 8 < 7 is false). It warns "ahead" and
  leaves the profile untouched (`:103-108`).
- The version stays 8 and the whole profile is saved back.

The live places run v6 code (study §4.2, at 2b15570). It follows the same rule:
- `ProfileSchema.luau:14` is `SCHEMA_VERSION = 6`;
- `DataService.luau:84` is the loop, `:96` the "ahead" warning, and `:165` the Reconcile.

The refund cannot repeat. Only `Migrations[7]` pays, and only the stamp from 7 to 8 runs it. The harness proves both
halves:
- a runner pass on a v8 profile changes nothing;
- calling the step alone twice pays twice.

The remaining risk is L3-30: old hub code can still spend Timber on slot `gear`, which v8 code ignores. Both places
should publish together at L4.

## For the other owners

**Lead:**
- **Combat.luau is done** as ruled. The same diff closed the luau-lsp errors in `ExpeditionPanel.luau:816` and
  `ExpeditionService.luau:659/674` (a fresh hub-sourcemap pass is clean).
- **Proposed `mirror_mutants.py` entries** (your file or QA's) to prove the new Armory comparisons. Each is one
  module, `"Armory"`, with this path in `PATHS`: `"Armory": "src/shared/Armory.luau"`.
  - `("Armory: BandOf from 0", "Armory", "(tier - 1) % bandSize + 1", "tier % bandSize + 1")`
  - `("Armory: TierOf no start", "Armory", "return math.min(math.max(saved, start), top)", "return math.min(saved, top)")`
  - `("Armory: no band-top star", "Armory", "position == ladder.bandSize and not starHeld(", "false and not starHeld(")`
  - `("Armory: SetTier unclamped", "Armory", "local held = math.min(math.max(math.floor(tier), start), top)", "local held = math.floor(tier)")`
- **`tests.luau:620`** (not in my list) still checks 130 and still passes, now through `rangeHp`. Its label says
  "the tier-1 body (130 from the real Armory.json)", which is still true. No change is needed.

**B (received and taken):**
- The re-aim of "17: the body keeps the profile's health", to `\treturn nil\n`.
- 15 StageFlow entries.
- My own extra entry, "l3: the range's body is the held pair's MaxHp", also proves the range reads `RangeHp`.

**ui A:** the 22 `L3_UI_MUTATIONS` are taken; every one is caught.

**Designer:**
- **Nothing is owed.** The mirror now follows Armory.luau guard for guard, plus `first_clear`, and check_stage_mirror
  passes.
- I aligned four guards to the mirror's reading of a tier that is not a whole number: `TierOf`, `Multiplier`,
  `WeaponHp` and `LegacyRefund`.
- `check_stage_mirror` fails by name if any of the 19 Python mirrors or `sim_range.first_clear` goes missing.

**ui B:**
- `ActionResult.action` no longer has `"buyGear"`. The hub client already typechecks clean.
- Hub deltas' `combat` now carries `abilities`, `secrets`, `families`, `shortcuts`, `tiers`, `loadout` and `stars`.
- The hub levers take `setTier` as `"<family>=<tier>"` (no spaces), `grantStar` as `"*"` or a level id, and
  `resetArmory` with any value.

## What to check in Studio

1. **Hub, with Studio API access on.** An old profile with slot tiers (for example via `DebugSetGear` on an older
   build) loads at v8 with Timber refunded, 3/3 → +500. Output shows no ProfileSchema warning.
2. **Hub Armory upgrade.** Press K and upgrade the Longbow with Timber (the GrantMaterials lever pays Timber).
   - The Power readout moves (64 at T1/T1).
   - T4 says "Needs ★ Hard" until the DebugGrantStar attribute `*` is set (or the panel's star button is used).
3. **Hub equip.** Equip the Flamethrower in the hub, then Depart. The dungeon lobby holds it. This needs a real
   profile; the mock profile resets every session.
4. **Hub reset lever.** DebugResetArmory > 0 empties tiers, loadout and stars. Materials, Valor and families stay.
