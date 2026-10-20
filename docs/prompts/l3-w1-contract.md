# L3 Wave 1 contract — tiers per weapon, the saved loadout, and the Armory screen in grey (draft for the lead, 2026-10-20)

Branch `l3-armory` in `C:\Users\benja\Desktop\tycoon-p5`. Ben's decisions are in `docs/MISSIONS_DESIGN.md` §24 and §10
(the 2026-10-20 restatement); they override the studies (`docs/prompts/l3-study-report-systems.md`,
`l3-study-report-screen.md`) wherever the two differ. The lead's rulings come from `docs/prompts/l3-w1-brief.md`.

W1 delivers this, playable alone in Studio: every weapon has its own tier on one ladder of 20 inside its own window;
Forest drops pay the upgrades; the loadout is saved; stars are saved; profile v8 converts old profiles; and the new
Armory screen opens in grey in both places (the dungeon lobby and the city hub). There are no models yet: the stage
shows a placeholder. **Ben's test:** boot `proving.rbxl` into the lobby, open the Armory, clear Forest Road on Normal,
buy T2 for both starters, feel it on the next run, then see the same screen in the hub.

Rulings are numbered **L3-n**. Every number is a starting value that its owner measures, and it may move within the
rule it serves. Two places where a brief ruling meets the code are marked **(conflict)** (L3-11, L3-25); each comes
with a proposed resolution for the lead.

## What today's code gives us (checked 2026-10-20 at 773f37d)

- **The tier belongs to the slot.** `Armory.json slots.melee/ranged` each hold a starter and 12 tiers with `band, cost,
  unlockRate, damage, hp` (`Armory.json:34-69`). `Armory.DamageScale` is the slot tier's damage × Ascension ÷ the
  slot's tier-1 damage (`Armory.luau:183-201`). `MaxHp` is `baseHp` + hp(melee tier) + hp(ranged tier) (`:214-218`).
  `CanBuy` checks, in order, a next tier, then income ≥ `unlockRate`, then materials (`:282-300`).
  - Today's 2/2 is ×1.5 / ×1.5 (18/12 and 15/10) with 155 HP; 4/4 gives 230 HP and 6/6 gives 380
    (`Armory.json:39-43, 56-60`).
- **The choke point** (P5 ruling 8, INTERFACES 8809).
  - `WeaponService.gearOf` returns, in order: the range's 1/1; the Studio override; `debug.provingGear` in a
    proving build; the profile's `combat.gear` (`WeaponService.luau:603-633`).
  - `damageScale(player, slot, ability)` reads the **slot's** tier (`:635-650`). Its callers pass the striking
    family's slot (`:1145, 1360, 2825, 2909`) or `"melee"` for the slam (`:2563`).
  - Heavy, plate, interrupt and armour read the unscaled amount; only the HP loss is scaled
    (`CrowdService.luau:2031-2038, 2086-2091`; P5 ruling 9).
- **Health.**
  - In missions: `WaveService.maxHpOf` → `Armory.MaxHp(WeaponService.GearOf(player))` (`WaveService.luau:394-401`).
  - In the range: `MaxHp({1,1})` = 130 (`VitalsService.luau:764-774`), pinned by `tests.luau:620`.
  - `RefreshMaxHp` keeps the bar's share (`VitalsService.luau:845-856`).
- **`provingGear` replaces the profile in a proving build** (`WeaponService.luau:611-621`; P5 ruling 12, INTERFACES
  8813). Today it is 2/2 (`Combat.json` `debug`).
  - G steps `gearPresets` 2/2, 4/4, 6/6 as a session override (`DebugService.luau:165-199`;
    `WeaponService.SetGearOverride :2228-2246`; L1 ruling 34, INTERFACES 9846).
  - `setGear` writes that override in a proving build and `combat.gear` elsewhere (`DebugService.luau:120-160`).
- **The loadout lives for the session only** (L2-33).
  - `WeaponService.AddPlayer` starts everyone on the config `loadout` (Broadsword + Longbow, `ProvingGrounds.json:214`)
    through `startingFamily` (`WeaponService.luau:2124-2185, 364-378`).
  - The path of a change: `RequestSetFamily` → `UnlockService.OnSetFamily` → `Unlocks.FamilyVerdict` →
    `WeaponService.SetVariant` + `SetFamily` (`UnlockService.luau:184-211`, `Unlocks.luau:248-274`,
    `WeaponService.luau:2597-2645`).
  - Owned = the starters + `combat.families` (`Unlocks.luau:167-190`). The gate is `WaveService.MayLeave`
    (`WaveService.luau:2237-2243`, wired at `Main.server.luau:253`).
- **The profile is v7** (`ProfileSchema.luau:14, 20-50`).
  - `Migrations[6]` is add-only (`:110-124`).
  - The runner runs each step once and bumps the version after it (`DataService.luau:90-109`).
  - A profile newer than the code warns and plays untouched (`:103-108`).
  - `Types.CombatProfile` (`Types.luau:969-990`) and Armory.luau's structural copy of it (`Armory.luau:96-113`) must
    match field for field.
- **Stars are session memory.**
  - They live in `boot.stars[userId]` (`WaveService.luau:229-230, 440-447`), are awarded by `StageFlow.Award`
    (`StageFlow.luau:2863-2874`) in `EndRun` (`WaveService.luau:1326-1339`), and are read by the map's `requires.node`.
  - Their shape `{ [levelId]: { [difficulty]: boolean } }` (`StageFlow.luau:209`) is the one v8 saves.
- **One `rewardMult` multiplies cash, materials and the boss's Valor.**
  - The readers are `Combat.KillReward` (`Combat.luau:856-866`), `ClearBonus` (`:871-886`) and the boss's Valor
    (`WaveService.luau:665`). The map card says "×N cash and drops" (`MapScreen.luau:1065`).
  - Forest Road, Normal / Hard / Brutal: `hpScale` 1.5 / 5.2 / 11.5, `rewardMult` 1 / 2 / 4, `recommendedTier`
    2 / 4 / 6 (`1_ForestRoad.json:14-40`). The arena's `recommendedTier` is 2 (`0_RaiderArena.json`).
- **The hub.**
  - `ArmoryService.Init` registers `RequestBuyGear` and `RequestAscend` itself (`ArmoryService.luau:319-326`).
  - `tryBuyGear` reads the persisted income (`:85-119`). GrantMaterials pays the band of the player's era (`:190-203`).
  - `EconomyService.copyCombatProfile` drops the v7 maps (`EconomyService.luau:102-127`), so every hub Delta erases
    them on the client.
  - `computeGearPower` reads `combat.gear` (`:92-98`); so does the combat Snapshot (`Main.server.luau:107-109`).
  - The hub client keys its Armory and Expedition buttons and its Power readout on `RequestBuyGear` existing
    (`UIController.luau:418-431, 545-546, 858`).
  - It opens `ArmoryPanel` from the bottom bar (`UIController.luau:676-691`, `BottomBar.luau:33`) and binds no key.
- **The lobby Armory.**
  - Files: `ArmoryPanel` + `ArmoryWeapons` + `ArmoryAbilities` in `src/combat/client/UI` (518 / 646 / 372 lines).
  - Inputs: K (`CombatUIController.luau:2224-2226`); the HUD button (`:1650-1661`); pad Y / B / LB / RB
    (`ArmoryPanel.luau:12-17, 83-86`).
  - Results are routed at `CombatUIController.luau:2129-2135`.
  - The hints come from `ArmoryWeapons.HiddenWhere`: a level whose secret pays the family first, then
    `Expeditions.json found` (`ArmoryWeapons.luau:111-144`). `Columns` drops an unowned family that has no hint
    (`:167-171`). Only `frostHammer` has a `found` entry (`Expeditions.json:12-14`).
- **Rojo.**
  - `combat.project.json:65-73` maps `src/combat/client/UI` plus six hub UI files as explicit children.
  - An explicit child whose name already exists in the `$path` folder makes two instances (coop memory).
  - `.proving.project.json` is generated from it (`tools/proving_project.py`).
- **Old readers of slot tiers that stay until L4** (they read the kept `combat.gear` and `slots`): `Combat.luau:686-750`,
  `CombatService.luau:135-136, 565`, `InputController.luau:425`, `WeaponController.luau:143`,
  `CombatUIController.luau:1042-1092` (`abilityInfo`, `SetGear`).
- **Keys.**
  - Taken in the combat client: N, B, G, H, V, J, F, I, K, M, P, C, E, Q, One, Two, Backspace, LeftShift, LeftAlt,
    RightAlt, Escape, Return and the arrows (every `Enum.KeyCode` in `src/combat/client`).
  - The hub client binds none.
  - Free, and unused by Roblox's defaults: **T, U, L** (also R, X, Y, Z).
- **check_levels.**
  - `ownedFamilies` = the starters ∪ the families a secret pays (`check_levels.py:5203-5208`).
  - The sniper reach is the default ranged family's default variant (`:5051-5054`).
  - The `found` rule refuses a family that a secret pays (`:4878-4900`).
- **Compile budget** (`py tools/check_compile.py --counts`, PASS, 174 files): FeedbackController 162, InputController
  158, CrowdRenderer 154, CombatFxController 126, CombatUIController 106 top-level locals (cap 180). WeaponService is
  3,015 lines.

## 1. The ladder and the windows

**L3-1. The damage ladder** (`Armory.json` new block `ladder`; every number lives there, never in code).
- `ladder.damage` holds 20 numbers, the multiplier of the range's tier-1 numbers at each tier: `1.5 × 1.65^(t−1)`,
  written to 4 decimals.
  - The values: 1.5, 2.475, 4.0837, 6.7382, 11.118, 18.3447, 30.2688, 49.9435, 82.4068, 135.9711, 224.3524, 370.1814,
    610.7994, 1007.819, 1662.9013, 2743.7872, 4527.2488, 7469.9606, 12325.435, 20336.9677.
- **T1 = today's 2/2 exactly** (×1.5 on both slots), so Normal plays as tuned.
- The range keeps scale 1 (`WeaponService.damageScale` already returns 1 there).

**L3-2. The HP ladder.**
- `ladder.hp.melee` and `ladder.hp.ranged` hold 20 numbers each. MaxHp = `baseHp` + hp.melee[tier of the melee
  family] + hp.ranged[tier of the ranged family], each × the slot's Ascension `hpMult`.
- **T1–T11 take the old slot tiers 2–12 one for one:**
  - melee 35, 50, 80, 120, 170, 250, 350, 480, 700, 950, 1300;
  - ranged 20, 30, 50, 80, 110, 160, 230, 320, 450, 620, 850.
  - That pins MaxHp at (T1,T1) 155, (T3,T3) 230 and (T5,T5) 380, with melee keeping the larger share.
- T12–T20 are the designer's: rising, melee ≥ ranged.
- `ladder.rangeHp: 130` is the range's own body, read by `VitalsService` in place of `MaxHp({1,1})`.

**L3-3. The windows, as drawn** (Ben, §24). `Armory.json windows` maps each family to `{ start, top }`:

| Family id | Window | Found (shelf hint) |
|---|---|---|
| `broadsword`, `longbow` | 1–12 | starters |
| `flamethrower` | 2–8 | the lookout (its secret) |
| `warhammer` | 3–16 | Forest Road, first Hard clear (L3-17) |
| `frostHammer` | 5–12 | the Castle (lever-only until then) |
| `greataxe` | 6–18 | the Castle |
| `splitbow` | 8–8 | a Castle secret (relic) |
| `spear`, `shotgun` | 9–20, 9–16 | the Underworld |
| `rifle` | 11–18 | an Underworld secret |
| `launcher`, `smg` | 13–20, 14–20 | the Planet |
| `beam` | 16–20 | a Planet secret |
| `chaingun` | 17–20 | the Dream |
| `spinblade` | 20–20 | a Dream secret (relic) |

- `Armory.TierOf(cfg, combat, family)` = clamp(`tiers[family]` or start, start, top). A later window change therefore
  never strands a profile.
- A family with no window, or a malformed one, fights at T1 and cannot be upgraded. The Init validator warns about it
  (L3-5).

**L3-4. Bands, costs and the trophy.**
- `ladder.bandSize: 4`. `ladder.bands` lists five entries `{ levelId, material }`:
  - `forestRoad` / `Timber`;
  - then `castle`, `underworld`, `planet`, `dream`, with placeholder materials that the designer names and marks as
    placeholders in BALANCE. They are never shown (L3-21).
- A tier's band = ceil(t / 4), and its position = (t − 1) % 4 + 1. The validator requires 5 × 4 = #damage.
- `ladder.costs: [100, 100, 250, 500]`, by position. This is Timber 100 / 250 / 500 for T2 / T3 / T4.
  - Position 1 is never charged in band 1: no window starts below T1.
  - Position 1 of the later bands is a placeholder (Ben decides it with the Castle).
- A weapon whose window starts mid-band pays only from its start. That falls out of the rule: tiers below the start
  are never bought.
- `ladder.starDifficulty: "hard"`. A band's top position (T4, T8, …) also needs `stars[band.levelId].hard`: **the
  Hard star is the trophy.**
- **No city income gate.** `unlockRate` is no longer read; `slots` stays, unread by this path, for the old readers
  until L4.

**L3-5. The pure rules** (`src/shared/Armory.luau`; it stays require-free with structural types, and
`tools/sim_combat.py` mirrors it function for function):

```luau
Armory.LadderSize(cfg): number                                  -- #ladder.damage; 0 without a ladder
Armory.Window(cfg, family): (number, number)?                   -- start, top clamped into 1..LadderSize; nil = none
Armory.TierOf(cfg, combat, family): number                      -- L3-3; 1 without a window
Armory.HeldTiers(cfg, combat, melee: string, ranged: string): SlotTiers
Armory.Multiplier(cfg, tier): number                            -- ladder.damage[clamped tier]; 1 without a ladder
Armory.DamageScale(cfg, tier, ascLevel, ability): number        -- Multiplier × (abilityMult | damageMult | 1)
Armory.WeaponHp(cfg, slot, tier, ascLevel): number              -- ladder.hp[slot][tier] × hpMult; 0 for an unknown slot
Armory.MaxHp(cfg, tiers: SlotTiers, ascension: SlotTiers): number
Armory.RangeHp(cfg): number                                     -- ladder.rangeHp (baseHp without one)
Armory.GearPower(cfg, tiers, ascension): number                 -- L3-6
Armory.BandOf(cfg, tier): (number, number)                      -- band index, position
Armory.NextTier(cfg, combat, family): number?                   -- TierOf + 1 while it is <= top
Armory.TierCost(cfg, tier): (string, number)                    -- (band material, costs[position]); ("", 0) outside
Armory.Preview(cfg, slot, tier, baseDamage): (number, number)   -- round(baseDamage × Multiplier), WeaponHp(slot, tier, 0)
Armory.UpgradeVerdict(cfg, combat, family, owned: boolean, gateOpen: boolean,
                      built: { [string]: boolean }): UpgradeRefusal?
Armory.Upgrade(...same args...): UpgradeRefusal?                -- the verdict, then the write, in one call, no yield
Armory.LegacyRefund(cfg, gear: SlotTiers): { [string]: number } -- L3-8
Armory.Problems(cfg, families: { string }): { string }          -- the validator; warned at Init in both places
```

- `UpgradeRefusal` = `"invalid"` (no such family or no window) | `"locked"` (not owned) | `"peak"` (at its top) |
  `"busy"` (the gate is shut) | `"notBuilt"` (the next tier's band level has no level file) | `"needsStar"` (a band
  top without that level's Hard star) | `"insufficientFunds"`. They are tested **in that order**.
- `"unavailable"` (no profile, no Armory config) is the caller's.
- `Upgrade` on success spends `TierCost` from `combat.materials` (never below 0) and writes `combat.tiers[family] =
  next`, making the table when it is nil.
- **Kept** for the C1 readers and the hub's Ascension: `TierDef`, `WeaponDamage`, `ClassDef`, `AbilityDef`,
  `AscensionCost`, `AscensionCap`, `CanAscend`.
- **Deleted with their last caller**, together with their sim_combat mirrors: `CanBuy`, `TierUnlockRate`,
  `BandMaterial`, and the old slot-shaped `NextTier`, `TierCost`, `WeaponHp`, `MaxHp`, `GearPower` and `DamageScale`
  (each is replaced by the signature above).
- The header comment's "unlock on the city's persisted income" goes.

**L3-6. Where tiers act.**
- **Damage** (`WeaponService`): `damageScale(player, family, ability)` takes the striking **family**.
  - The tier is `TierOf(family)`, or the Studio override's tier for that family's slot. The Ascension level is that
    slot's.
  - The five callers pass the family; the slam passes the held melee family.
  - The range stays at 1. Heavy, plate and armour stay unscaled (P5 ruling 9, unchanged).
- **Health.**
  - `gearOf` returns the **held families'** tiers behind the same slot-shaped API: the override, else
    `Armory.HeldTiers(cfg, combat, shooter.loadout.melee, shooter.loadout.ranged)`.
  - With no shooter yet, the saved loadout is used (L3-10). With no profile, 1/1.
  - So `WaveService.maxHpOf` is unchanged, and `VitalsService.maxHpFor` reads `Armory.RangeHp` in the range.
- **Gear Power** (not in the brief: the hub's Power readout and the expedition tiles read it, and it would freeze at
  the old `gear`).
  - `GearPower = round((Multiplier(tm)·dm + Multiplier(tr)·dr) × power.tierWeight + MaxHp × power.hpWeight)`, where
    `power.tierWeight` is new in `Armory.json` and `dm` / `dr` are the slots' Ascension damageMult (1 at level 0).
  - With `tierWeight` 11 a fresh T1/T1 reads 64, today's 2/2 value (33 + 31), so the hub's old Village tile (60) still
    reads "ready".
  - The hub computes it from the saved loadout (L3-14); the combat Snapshot from `WeaponService.GearOf(player)`.

## 2. Saving: profile v8

**L3-7. Three new fields, add-only** (`ProfileSchema.luau` `SCHEMA_VERSION` 8, the template, `Types.CombatProfile` and
Armory.luau's structural copy):

| Field | Shape | Template | Written by |
|---|---|---|---|
| `combat.tiers` | `{ [familyId]: number }`, only families upgraded past their start | `{}` | an upgrade, `setTier`, `resetArmory` |
| `combat.loadout` | `{ melee: string?, ranged: string?, variants: { [familyId]: string } }`; nil = the slot's starter | `{ variants = {} }` | an equip (both places), `removeFamily`, `resetArmory` |
| `combat.stars` | `{ [levelId]: { [difficulty]: boolean } }` | `{}` | a cleared run (`StageFlow.Award`), `grantStar`, `resetArmory` |

- All three are optional in the type, like the v7 maps (old code and the hub's copy).
- `gear` is **frozen**: kept, never written or read by new code (the live places read it).
- `ascension`, `missions` and `highestEra` are kept.
- The template names no family id: the starters come from `ProvingGrounds.json loadout` at read time.

**L3-8. `Migrations[7]`.**
- It adds each field only when it is nil, always as a fresh table, never the template's (aliasing). It adds
  `loadout.variants` when a loadout lacks it.
- **Then it refunds:** for each slot, for t = 1 … min(`gear[slot]`, #legacy), `materials[legacy[t].material] +=
  legacy[t].amount`.
  - `Armory.json legacy.gearCosts` is a **frozen** copy of today's 12 slot-tier prices as `{ material, amount }`:
    Timber 10, 60, 180, then Steel, Circuits and Alloy at 10, 60, 180 each.
  - It is frozen because the step must never read `slots`, which L4 deletes. Live profiles hold at most 3 / 3, so in
    practice the refund is Timber only, at most 500.
- The starters start at their window start by **leaving `tiers` empty** (`TierOf` defaults to the start); `gear` is
  untouched.
- Unlike L2-1, the refund is **not** safe to run twice. The version stamp runs it once (`DataService.luau:90-102`), and
  the harness proves that the runner applies it exactly once and that a v8 profile is untouched.
- The step reads the frozen list through `Armory.LegacyRefund(Catalog.GetArmoryConfig(), gear)`. With no Armory
  config it adds the maps, refunds nothing and warns once (the stamp still moves: a broken build is the only way
  there).
- The harness pins `legacy` byte for byte, so an edit fails a gate.

**L3-9. Stars leave session memory.**
- `starsOf(userId)` returns the member's profile `combat.stars` through `Unlocks.StarsOf(combat)` (made when nil, like
  `AbilitiesOf`). A member without a loaded profile (a bot) keeps today's session table.
- The map (`requires.node`), the T4 gate and the summary's star all read the same table.

## 3. The saved loadout

**L3-10. One pure reading, used by both places** (`src/shared/Unlocks.luau`):

```luau
Unlocks.LoadoutOf(combat: Types.CombatProfile?, weapons, fallback: { melee: string, ranged: string }): Types.RangeLoadout
Unlocks.SaveLoadout(combat: Types.CombatProfile, slot: string, family: string, variant: string): ()
Unlocks.StarsOf(combat: Types.CombatProfile): { [string]: { [string]: boolean } }
```

- **`LoadoutOf`.**
  - Each slot takes the saved family when it exists in `weapons`, fills that slot, and is owned (`OwnsFamily`);
    otherwise `fallback[slot]`, **the slot's starter**.
  - `variants` keeps only saved entries whose family and key both exist, so an unknown style falls back to the
    family's `default`.
- **`SaveLoadout`** runs only after `FamilyVerdict` has said nil. It writes `loadout[slot]` and
  `loadout.variants[family]`.
- **Where it changes:** the lobby's Armory and the hub's Armory. Never inside a live fight, because the combat gate is
  `WaveService.MayLeave` and the hub has no fight.
- **At admit**, in mission mode only, `WeaponService.AddPlayer` builds the shooter's loadout with
  `Unlocks.LoadoutOf(profile.combat, weapons, { melee = startingFamily(config, "melee"), ranged =
  startingFamily(config, "ranged") })`. The range keeps today's starters.
- Every server path that changes a held family in a mission also saves: `OnSetFamily`, the `removeFamily` lever and
  `resetArmory`.
- `OnSetFamily` now also calls `VitalsService.RefreshMaxHp` (a family switch changes the tier and so the bar) and sends
  a Snapshot. UnlockService may require VitalsService: VitalsService requires only CrowdBrain, CrowdService and
  ThreatField (`VitalsService.luau:56-58`), so there is no cycle.
- **Closed by this rule:** "a cooldown carried across a family switch" (INTERFACES 9385, 11153; PLAN 1878). Nobody can
  switch mid-fight. Also PLAN 4054-4055: the loadout is no longer kept for the visit only.

**L3-11. (conflict) `provingGear` stops replacing the profile.**
- The brief makes `debug.provingGear` T1. As the code stands, a proving build reads `provingGear` **instead of** the
  profile (`WeaponService.luau:611-621`). The T2 Ben buys in `proving.rbxl` would never reach a hit or the bar, so his
  test would feel nothing.
- **Proposed:** `gearOf` drops the `provingGear` branch, and in a proving build the profile's tiers rule, as
  everywhere.
  - A fresh mock profile is T1/T1 by construction (both starters' windows start at 1), which is exactly what P5
    ruling 12 protected.
  - `provingGear` stays in Combat.json as `{ melee = 1, ranged = 1 }`, read only by the simulators as the first-run
    gear (`sim_range.mission_gear`, `sim_range.py:5267`); its Types comment says so.
  - With "Enable Studio Access to API Services" on, a real Studio profile keeps what was bought, and L resets it
    (L3-28).
  - P5 ruling 25's carried "setGear is inert in a proving mission" closes too: `setGear` writes the override in
    every Studio build.
- **Lead to confirm.**

## 4. Upgrading and equipping

**L3-12. Remotes (lead).**
- `RequestUpgradeWeapon(family)` in **both** places: bucket `calls`, validator `args.n == 1 and
  isShortString(args[1], Unlocks.MAX_FAMILY_LENGTH)`.
- `RequestSetFamily(slot, family, variant)` in the **hub** too, with the combat validator
  (`CombatRemotes.luau:148-156`).
- `RequestBuyGear` is removed from `HubRemotes` (no handler, no sender). `RequestAscend` stays: Ascension is kept and
  unreachable.
- The client sends a family, a slot and a style key, never an amount or a tier.
- Types:
  - `ActionResult.action` gains `"upgradeWeapon"` (its `slotId` is the family id);
  - `reason` gains `"peak"`, `"notBuilt"` and `"needsStar"`.

**L3-13. The combat place** (`UnlockService.OnUpgradeWeapon(player, family)`, new):
1. The range is ignored. A player not admitted, no profile, or no Armory config answers `unavailable`.
2. `owned = Unlocks.OwnsFamily(families, family, starters())`, `gateOpen = gate(player)`, and `built` = a set of
   `Catalog.GetLevelIds()` made at Init.
3. `Armory.Upgrade(...)`. On nil: the caller's Studio override is cleared, `VitalsService.RefreshMaxHp(player)` runs,
   the ActionResult is ok, and `ArenaService.SendSnapshot(player)` is sent. A refusal sends the ActionResult with its
   reason.
4. Nothing yields between the verdict and the write.

**L3-14. The hub** (`src/server/Services/ArmoryService.luau`).
- `tryBuyGear` goes. In its place, in the same `Init` (the hub's pattern; hub `Main.server.luau` needs no change):
  - `RequestUpgradeWeapon`: `Armory.Upgrade` with `gateOpen = true` and `built` from `Catalog`.
  - `RequestSetFamily`: `Unlocks.FamilyVerdict(state, weapons, starters, slot, family, variant, true)`, then
    `Unlocks.SaveLoadout`.
  - Both use `Catalog.GetProvingGroundsConfig()` for the weapons and the starters. Both end with
    `EconomyService.MarkDirty(player, { combat = true })` and an ActionResult.
- `tryAscend` stays.
- `Init` warns `Armory.Problems`.
- **`EconomyService.copyCombatProfile`** deep-copies `abilities`, `secrets`, `families`, `shortcuts`, `tiers`,
  `loadout` and `stars`, each nil-safe. Today it drops the v7 maps (`EconomyService.luau:102-127`).
- **`computeGearPower`** reads the held tiers of `Unlocks.LoadoutOf(combat, weapons, config.loadout)`.

## 5. Forest Road on the new ladder

**L3-15. The remap** (`Config/Levels/1_ForestRoad.json`, `0_RaiderArena.json`).
- Recommended tiers become Normal / Hard / Brutal **1 / 3 / 5**. The arena becomes 1.
- **Normal** is unchanged: T1 = 2/2, ×1.5 and 155 HP.
- **Hard**: `hpScale` is re-measured so that the mission player's Hard clear at T3 keeps today's clock at 4/4.
  - Today's clock is 5:06, 5:19 and 5:11, and today's multipliers are ×5.0 melee / ×4.5 ranged against T3's ×4.08.
  - The study expects 4.3–4.7.
  - `damageScale` 2 is unchanged (230 HP either way).
- **Brutal** keeps its tuning: T5 is ×11.12 against today's ×10.8 / ×11.5 at 6/6, with 380 HP either way. It waits for
  Castle gear.
- `Combat.json debug`: `gearPresets` "T1", "T3", "T5" (melee = ranged = 1, 3, 5); `provingGear` T1 (L3-11).

**L3-16. Hard pays ×2.5: data only (lead's ruling, 2026-10-20). Superseded by §12.8: Hard stays ×2.**
- Hard's `rewardMult` goes from 2 to **2.5** (`1_ForestRoad.json`). One `rewardMult` multiplies cash, materials and the
  boss's Valor together (`Combat.luau:856-886`, `WaveService.luau:665`), so cash is ×2.5 too; that is +25% of a number
  that is 0.9% of the Village's price at 12:21 (systems report §3.4), and it saves a new key and three mirrors.
- **No `dropMult`, no code change** in `Combat.luau`, `StageFlow`, `WaveService` or `MapScreen` for this ruling. The map
  card keeps "×2.5 cash and drops".
- Normal (1) and Brutal (4) are unchanged.

**L3-17. First clears.**
- New optional difficulty key `firstClear: { family: string?, valor: number? }`. Forest Road:
  - `hard.firstClear = { family = "warhammer" }`: the Warhammer, which by its window arrives at T3.
  - `brutal.firstClear = { valor = 25 }`. Its map mark waits for L4.
  - **The Hard star itself is the trophy** (L3-4); it needs no entry.
- `StageFlow.FirstClear(level, difficulty): Types.LevelFirstClear?` is pure.
- `StageFlow.Validate`: `family` is a short string naming a non-starter weapons family; `valor` is a whole number ≥ 0.
- In `EndRun`, when `StageFlow.Award` returns true (a **new** star) for a member with a profile:
  `UnlockService.GrantFirstClear(player, reward)`.
  - It writes `families[f] = true` (skipping, with a warn, an unknown family or a starter) and `valor += v`, then sends
    a Snapshot. It returns what it gave.
  - WaveService credits the Valor with `ArenaService.CreditSummary(userId, 0, "", 0, valor, 0)` **before**
    `BroadcastSummary`.
  - `Types.RunResult` gains `firstClear: { family: string?, valor: number }?`, so the summary card can say "Warhammer
    is yours: equip it in the Armory (K)" or "+25 Valor, first Brutal clear".

## 6. The Armory screen, in grey, in both places

**L3-18. One shared module set** (ui-engineer A), all `--!strict` and all new to `src/combat/client/UI` (`ArmoryPanel`
is taken until it is deleted):

| File (`src/client/UI/`) | What |
|---|---|
| `ArmoryScreen.luau` | The shell: scrim, frame, the Weapons and Abilities tabs, close, the key line, landscape and portrait layout, pad bindings, selection confinement, `SetLayout`. |
| `ArmoryStage.luau` | Placeholder stage: the family name large, slot, element chip (FIRE / ICE from `Unlocks.ElementOf`), a big "T3", dark when unowned. W2 puts a ViewportFrame behind the same API. |
| `ArmoryTrack.luau` | The ladder of 20 (L3-20). |
| `ArmoryShelf.luau` | The 15 cards. |
| `ArmoryDetail.luau` | The next tier, its cost and level, the ability, the styles, Equip and Upgrade. |
| `ArmoryAbilityPage.luau` | The Abilities tab: `ArmoryAbilities` moved and renamed. Read-only when `deps.onBuyAbility` is nil (the hub: "Bought in the dungeon's lobby"). |
| `ArmoryModel.luau` | **Pure**, no Instances: the shelf cards, the pips, the next-tier line and the button states, from (Armory config, weapons, Expeditions config, level files, combat profile, held loadout, gateOpen, built). Tested by `tests_l3_ui.luau`. |

- These files may require Shared modules (Types, Catalog, Armory, Unlocks, Format, Tuning) and the siblings that exist
  in **both** trees: Create, Motion, Theme, Toast, and each other. Never Panel, PanelDock, SoundController or anything
  under Controllers. **No sound in the combat place** (Ben, 2026-09-24).
- The handle the hosts code against:

```luau
ArmoryScreen.new(parent: Instance, deps: {
	onUpgrade: (family: string) -> boolean,                              -- false = could not send
	onEquip: (slot: string, family: string, variant: string) -> boolean,
	onBuyAbility: ((abilityId: string) -> boolean)?,                      -- nil in the hub
	onOpenChanged: (open: boolean) -> (),
	toast: (text: string, seconds: number?, isError: boolean?) -> (),
	keyHint: string?,
	padToggle: boolean,                                                  -- the lobby: pad Y toggles while available
}): {
	Open: () -> (), Close: () -> (), Toggle: () -> (), IsOpen: () -> boolean,
	SetAvailable: (available: boolean) -> (),   -- the lobby: the phase is "lobby"; the hub: always true
	SetGate: (open: boolean) -> (),             -- UpgradeVerdict / FamilyVerdict's gateOpen
	SetState: (combat: Types.CombatProfile) -> (),
	SetHeld: (loadout: Types.RangeLoadout) -> (),
	OnResult: (result: Types.ActionResult) -> (),   -- upgradeWeapon, setFamily, buyAbility
	SetLayout: (scale: number, size: Vector2) -> (),
}
ArmoryScreen.PAD_TOGGLE_NAME: string; ArmoryScreen.PAD_TAB_NAMES: string
```

**L3-19. Layout A, "Showcase"** (Ben, §24).
- **Header** (48): the [Weapons] [Abilities] tabs, the wallet (Timber · Valor) and [X].
- **Middle**:
  - the stage on the left;
  - on the right: name, slot and big tier; the track; the next line; the cost line; "Ability: Arrow Rain"; the style
    buttons; [Equip] [UPGRADE].
- **Shelf** (64): one scrolling row of 15 cards in landscape, a 5 × 3 grid in portrait.
- **The next line** reads "T5: 303 → 500 dmg · HP +120 → +170". dmg is `Armory.Preview` of the held (else default)
  style's per-hit `damage`; HP is the slot's `ladder.hp`.
- **The cost line** reads "500 Timber · Forest Road · needs ★ Hard". The level name comes from the level file, else the
  map node.
- **Shelf order**: by window start, then melee before ranged, then name. The shelf reads as the path of levels.
- **An unowned card** is dark. Selected, it shows the stage dark, the window lit on the track, and the hint in place
  of the next and cost lines ("Not found yet · First Hard clear of Forest Road"), with no buttons.

**L3-20. The track: the full ladder of 20 with the window lit** (Ben, §24).
- Five bands of four pips, each tinted by its level's theme colour (`Expeditions.json themes` through the band's map
  node).
- Pip states: **lit** = at or below the tier; **open** = in the window, above the tier; **dim** = outside the window.
- The start and top are marked. At the top: "At its peak". A relic is one lit pip.

**L3-21. Buttons are coloured from the shared rules, and never decide.**
- **Upgrade** is live when `Armory.UpgradeVerdict(...) == nil`; otherwise disabled with its words:
  - peak "At its peak";
  - notBuilt "Comes with <level>": the cost is hidden for an unbuilt band, so placeholder materials never show;
  - needsStar "Needs ★ Hard on <level>";
  - insufficientFunds "Need N more Timber";
  - busy "Only in the lobby";
  - locked: hidden.
- **Equip** is live when `Unlocks.FamilyVerdict(...) == nil`; the held family shows "Equipped".
- **A style button** on the held family switches the style; on another family it reads "Equip A" / "Equip B".
- **A press** disables its button until its ActionResult (3 s at most).
  - On ok: toast "Longbow: T2" / "Warhammer equipped".
  - On a refusal: the same words as above; anything else "Try again".

**L3-22. Inputs.**
- **The lobby**: K, gamepad Y (lobby only; in a run Y is the weapon swap) and the HUD's Armory button, as today.
- **The hub**: K (the host's `UserInputService` handler, ignored when `gameProcessed`) and the bottom bar's Armory key.
- **In both places**:
  - Esc, its close button or a tap on the scrim closes it; pad B closes it; LB / RB switch tabs;
  - the d-pad and the stick move the selection, which cannot leave the screen;
  - opening it closes the map (lobby) or the open dock panel (hub).
- **Gamepad A is sunk while it is open:**
  - an action bound at a priority above the jump returns Sink;
  - if that also stops A pressing the selected button (unverified outside Studio), the action presses
    `GuiService.SelectedObject` itself.
  - It closes the carried PLAN item "gamepad A on Equip must not walk the character".

**L3-23. Fit.**
- **Landscape** 682 × 313 design px (a 640 × 360 phone) and 712 × 330 (667 × 375): header 48, middle about 175, shelf
  64 (screen report §3).
- **Portrait** 375 × 667 (393 × 648 design px): stage about 393 × 180, then the details, then the 5 × 3 shelf.
- Theme's touch minimum holds (48 design px at `MIN_SCALE`, 44 physical).
- One `UIScale` from the host's `SetLayout(scale, size)`, the same formula in both places (`CombatUIController.luau:
  363-372`, `UIController.luau:1324-1335`).

**L3-24. The hosts** (ui-engineer B).
- **Combat** (`CombatUIController.luau`):
  - `ArmoryPanel` becomes `ArmoryScreen` with the same rules (lobby only through `SetAvailable`, the map closed,
    `HOLD_ARMORY`, the DebugPanel hidden while it is open);
  - `SetState` takes each Snapshot's `state.combat`, and `SetHeld` the TuneState loadout
    (`FeedbackController.GetLoadout`);
  - `upgradeWeapon` results go to `OnResult`;
  - the pad and key names come from `ArmoryScreen`;
  - `DEBUG_KEYS` and `DEBUG_HINT` per L3-28.
  - `SummaryCard.luau` shows `firstClear`; `MapScreen.luau` shows the recommended tier as "T3" from the new ladder
    (no reward change, L3-16); `DebugPanel.luau` shows the held families' tiers instead of `gear`.
  - The three lobby panel files are deleted.
- **Hub** (`UIController.luau`):
  - `ArmoryScreen` is a full-screen card over the bottom bar, opened by K and the bottom bar's Armory key;
  - `SetState` takes the Snapshot and every Delta's `combat`; `SetHeld` takes `Unlocks.LoadoutOf(state.combat,
    weapons, config.loadout)`;
  - `SetGate(true)`;
  - `upgradeWeapon` and `setFamily` results route to the screen; the hub may keep its insufficientFunds sound;
  - **the readiness key moves from `RequestBuyGear` to `RequestUpgradeWeapon`** (`UIController.luau:431`), in the
    same commit as the lead's remote change, or the hub hides its Armory and Expedition keys.
  - The hub `DebugPanel.luau` gains the hub levers (L3-28). `src/client/UI/ArmoryPanel.luau` is deleted. The Power
    readout is unchanged (the server computes it).

## 7. Carried into W1

**L3-25. `check_levels`** (designer).
- `ownedFamilies` counts every family source: the starters, the secrets, and **every `firstClear.family`** (the
  Warhammer).
- The sniper reach is **the longest range of any ownable ranged family's variants**, in place of `longbow_range`
  (`check_levels.py:5051-5054`). Today that is still 110 (Longbow A; the Flamethrower reaches 20).
- **(conflict)** The brief gives every non-starter family a `found` entry, but the L2-51 rule refuses a `found` entry
  for a family a secret pays (`check_levels.py:4891-4892`): the Flamethrower.
  - **Proposed:** "every non-starter family has a shelf hint". That is a `found` entry, or the secret that pays it.
    The Flamethrower keeps its secret's "Hidden on Forest Road".
  - The 11 families with neither get `found` entries (node and a text of 1–40 characters, table L3-3; the Warhammer's
    node is `forestRoad`, "First Hard clear of Forest Road").
  - A new rule: every non-starter family has a hint. Another: a `firstClear.family` that has a `found` entry names
    that level's node.
  - The alternative is relaxing L2-51 to "a secret-paid family's `found` node is that secret's level". **Lead to
    pick.**
- The bend-hop gate (`:4715-4730`) keeps its known limit: no carrying family (Greataxe, Spear) is ownable in L3.

**L3-26. R8 sniper gates** (`sim_range.py:7078-7099`) also rate **bow T4 with sword T1** (the case where only the bow
was upgraded), on Normal and Hard, against the mission player at the same gear.
- A spot outside `SNIPER_KNOWN_LIMIT_L4` that out-earns is red.
- Judge on the 64-bit Python (chief-clearing memory: the Hard LookoutLedge row is +1.6%, and the Hard `hpScale`
  change moves it).

**L3-27. Every mirror moves in the same commit as what it mirrors** (systems report §2.5):

| Mirror | Mirrors | Owner |
|---|---|---|
| `sim_combat.py` Armory section (247-421) | `Armory.luau` (new functions; the deleted ones go) | designer |
| `sim_combat.py` unlock table (1916-1970), C0 check 1 (2765-2801) | the income gate: **retired**, with a BALANCE line | designer |
| `sim_range.py` `THREAT_TIER` (180), `armory_max_hp` (1582), `hpByTier` (3605), `gear_max_hp` / `mission_gear` (5257-5275), `level_view` (7013), `preset_gears` / `recommended_gear` / `preset_below` (8971-8983), the Validate mirror | the ladder, `rangeHp`, presets, `firstClear` | designer |
| `check_stage_mirror.py`, `stage_mirror.luau` | the new `Armory` functions it compares (`:155`) and `StageFlow.FirstClear` | luau-engineer A |
| crowd harness `tests_l2.luau` (its v6 profile reaches v8) and `tests.luau:620` (130, now `rangeHp`) | `ProfileSchema`, the range body | luau-engineer A |

## 8. Studio levers (Studio only, both entry points, inert in the live game and in the range)

**L3-28.**

| Lever (`RequestDebug`) | Workspace attribute (`Combat.json debug`) | Effect | Combat key |
|---|---|---|---|
| `grantMaterials` (exists) | `GrantMaterials` (exists) | A live level pays its material, as today. **In the lobby and in the hub** it pays the material of every band whose `levelId` has a level file (Timber today). This replaces the hub's era rule (`ArmoryService.luau:190-203`). | **T** = `Theme.COMBAT_DEBUG_GRANT_TIMBER` (500) |
| `setTier`, value `"<family>=<tier>"` | `setTierAttribute`: `"DebugSetTier"` (string, consumed) | `tiers[family]` = the tier clamped into its window (owning it is not required); the caller's override cleared; bar refreshed; Snapshot (Delta in the hub); notice "Longbow T4" | — (DebugPanel: "Melee tier +1", "Ranged tier +1" for the held pair) |
| `grantStar`, value a level id or `"*"` (every built band level) | `grantStarAttribute`: `"DebugGrantStar"` (string, consumed) | the `starDifficulty` star of that level, saved; MapState resent (combat); notice "★ Hard: Forest Road" | **U** = `"*"` |
| `resetArmory` | `resetArmoryAttribute`: `"DebugResetArmory"` (number > 0, consumed) | `tiers`, `loadout` and `stars` emptied (session stars too); held families back to the starters; override cleared. Materials, Valor, families and secrets stay (F, I and `removeFamily` handle families). | **L** |
| `gear` (G, exists) | — | the presets T1 / T3 / T5 as a session override on both slots; a successful upgrade or `resetArmory` clears it | G |
| `setGear` (exists) | `DebugSetGear` (exists) | the session override in **every** Studio build, never the frozen `gear`; a tier outside 1..`LadderSize` is refused with a warn | — |

- **Combat place.**
  - `DebugService` (`applyLever` and `pollAttributes`): the preset check moves from `Armory.TierDef` to the ladder
    (`DebugService.luau:190-192`).
  - `DEBUG_HINT` adds "T +500 Timber · U ★ Hard · L reset Armory".
  - The DebugPanel gains the two tier buttons, "★ Forest Hard" and "Reset Armory".
- **Hub.**
  - `ArmoryService.HandleDebug` and `consumeStudioLevers` take `setTier`, `grantStar` and `resetArmory`.
  - The hub DebugPanel gets the same buttons, with "Grant 500 Timber" in place of 25. The hub gets no new key but K.
- **Why a key for each:** Ben plays from keys and the Play button (p4 memory). The mock profile resets every Studio
  session, so without T, U and L the T4 gate needs a Hard clear in every session. PLAYTEST says so plainly.

## 9. Balance (economy-designer; written up in `docs/BALANCE.md` "L3 W1")

**L3-29.**
- `Armory.json`: `ladder` (L3-1, L3-2, L3-4), `windows` (L3-3), `legacy` (L3-8), `power.tierWeight` (L3-6, so that
  T1/T1 reads 64).
- **Normal at T1 is byte-identical** to today's 2/2 in every simulator row (the gate).
- **Hard at T3**, re-measured `hpScale`:
  - the mission player's clear is within ±5% of today's at 4/4 with 0 downs;
  - the human gate ("one preset below" = T1: a down, or ×1.8 the time) holds;
  - the Colossus row at T3 is reported.
- **Brutal at T5**, tuning unchanged: within ±5% of today's at 6/6.
- **The arena at T1**: its row is re-run and reported. Ranged is ×1.5 against the 2/1 it was tuned at in P5.
- **The range's bosses** are unchanged (scale 1).
- **Economy, solo:**
  - one Normal clear ≥ 200 Timber (T2 for both on the first clear; today 211);
  - both starters T1 → T4 (lookout and cache included, Hard at ×2.5) in **5–7 runs, 25–40 min** (Ben: three runs per
    weapon, about 31 minutes for both);
  - a Hard clear pays 25 Valor; the Brutal first clear 25.
- **The Init validator's rules in Python** (sim_combat): 20 strictly rising damage entries starting at 1.5; HP
  non-decreasing with melee ≥ ranged; 5 × 4 = 20; every family in `ProvingGrounds.json weapons` has 1 ≤ start ≤ top
  ≤ 20; `legacy` equals today's slot prices.

## 10. Owners (disjoint; one wave; the gates run after every owner has reported)

**luau-engineer A — the shared rules, saving, the hub server.**
- Owns:
  - `src/shared/Armory.luau` (L3-5, L3-6 formulas, L3-8 refund) and `src/shared/Unlocks.luau` (L3-10);
  - `src/shared/Types.luau` (every type change in this contract);
  - `src/server/Services/ProfileSchema.luau` (L3-7, L3-8), `ArmoryService.luau` (L3-14, hub levers) and
    `EconomyService.luau` (copy, Power);
  - in `tools/crowd_harness/`: a new `tests_l3.luau`; `run_harness.py`, which registers `tests_l3.luau`,
    `tests_l3_run.luau`, `tests_l3_ui.luau` and `ArmoryModel` in `SOURCES`; `mutate.py` (its own entries and the ones
    B and ui A report); `stage_mirror.luau`; `tests_l2.luau`; and `tools/check_stage_mirror.py`.
- `tests_l3` covers:
  - `TierOf` clamps (below the start, above the top, a window changed under a saved tier);
  - `UpgradeVerdict`, every reason in order, plus the band top with and without the star;
  - `Upgrade` writes once;
  - `TierCost` by position;
  - `MaxHp` at (1,1) 155, (3,3) 230 and (5,5) 380; `RangeHp` 130; `GearPower` 64 at T1/T1;
  - `Migrations[7]`: fresh, reconciled, no aliasing, a 3 / 3 profile refunded 500 Timber, exactly once through the
    runner, a v8 profile untouched, and `legacy` pinned;
  - `LoadoutOf`'s fallbacks (unknown, unowned, wrong slot, unknown style).
- Done when the harness and `check_stage_mirror` are green against the designer's data and `py tools/check_compile.py`
  passes. Report the exact forward-compatibility answer for v8: what v7 code does with a v8 profile, with file:line
  (L2 W1 §10's rule).

**luau-engineer B — the combat place server.**
- Owns, in `src/combat/server/Services/`:
  - `WeaponService.luau` (`damageScale` by family, `gearOf` held tiers, no `provingGear` branch, `AddPlayer` reading
    the saved loadout; new logic goes in helpers in `Armory` and `Unlocks`, not new locals here);
  - `UnlockService.luau` (`OnUpgradeWeapon`, the saving `OnSetFamily`, `GrantFirstClear`, the lever helpers);
  - `WaveService.luau` (`starsOf` from the profile, `firstClear` in `EndRun`);
  - `StageFlow.luau` (`FirstClear`; `Validate` for `firstClear`);
  - `VitalsService.luau` (`RangeHp`) and `DebugService.luau` (L3-28).
- Also a new `tools/crowd_harness/tests_l3_run.luau` (`StageFlow.FirstClear`, the `Validate` lines). Its `mutate.py`
  entries are written in the report for A.
- Done when the harness is green, `check_compile` passes, and nothing else on the server changes. Report the exact
  `damageScale` and `gearOf` expressions, and every new require (no cycle).

**ui-engineer A — the screen.**
- Owns the seven `src/client/UI/Armory*.luau` files (L3-18) and `src/client/UI/Theme.luau` (`ARMORY_SCREEN_*`,
  `COMBAT_DEBUG_GRANT_TIMBER`; it removes the Theme constants that only the deleted panels read, from B's list).
- Also a new `tools/crowd_harness/tests_l3_ui.luau` (`ArmoryModel`: shelf order, pip states, next and cost lines, every
  button state).
- Done when it fits L3-23's sizes, stays under the compile cap, and stylua, selene and luau-lsp are clean (both
  sourcemaps).

**ui-engineer B — the two hosts.**
- Owns:
  - `src/combat/client/Controllers/CombatUIController.luau`;
  - `src/combat/client/UI/DebugPanel.luau` and `SummaryCard.luau`;
  - the deletion of `src/combat/client/UI/ArmoryPanel.luau`, `ArmoryWeapons.luau` and `ArmoryAbilities.luau`;
  - `src/client/UI/MapScreen.luau`;
  - `src/client/Controllers/UIController.luau`, `src/client/UI/DebugPanel.luau`, and the deletion of
    `src/client/UI/ArmoryPanel.luau`.
- It codes against the handle in L3-18 and the types above.
- Done when no new behaviour sits in CombatUIController beyond wiring (106 locals now), and the hub hides nothing it
  showed before.
- **Why two ui-engineers:** the new screen is about 1,500 new lines, and the two hosts are 2,371 + 1,539 lines that
  must be read. One agent carrying all three is the context cost the agent-context memory warns about. The split keeps
  the hub in W1, which is what Ben's test needs. *Fallback if the lead prefers one ui-engineer:* move the hub host
  (`UIController.luau`, hub `DebugPanel`, the hub panel's deletion) to W2. The server side of the hub stays in W1.

**economy-designer.**
- Owns:
  - `src/shared/Config/Armory.json`, `Config/Combat.json` (`debug`: presets, `provingGear`, the three attributes),
    `Config/Expeditions.json` (`found`, L3-25), and `Config/Levels/1_ForestRoad.json` and `0_RaiderArena.json`;
  - `tools/sim_combat.py`, `tools/sim_range.py`, `tools/check_levels.py`, `tools/check_levels_mutants.py`;
  - `docs/BALANCE.md`.
- Done when L3-15, L3-16 (data), L3-17 (data), L3-25, L3-26, L3-27 (its rows) and L3-29 are in; every new rule fails
  on its own mutant; and `check_levels`, `sim_range --check` (64-bit) and `sim_combat` are green.

**Lead.**
- Owns `src/combat/server/Services/CombatRemotes.luau` and `src/server/Services/HubRemotes.luau` (L3-12),
  `combat.project.json`, `.proving.project.json` (`py tools/proving_project.py`), the sourcemaps, and INTERFACES
  "# L3 W1 contracts" (a pointer to this file).
- Combat `Main.server.luau`, exactly:
  1. `RemoteService.SetHandler("RequestUpgradeWeapon", function(player: Player, family: string) if
     RangeService.IsActive() then return end; UnlockService.OnUpgradeWeapon(player, family) end)`.
  2. `sendSnapshot`'s `gearPower`: `local tiers, ascension = WeaponService.GearOf(player)` then
     `Armory.GearPower(armoryConfig, tiers, ascension)` (`Main.server.luau:107-109`).
- The hub `Main.server.luau` needs no change: `ArmoryService.Init` registers the hub's handlers, as today.
- `combat.project.json` gets the seven `Armory*` files as explicit children of `Client.UI`.

**Hand-offs ("for the other owner"):**
- luau A → designer: the `Armory.json` and difficulty shapes as typed.
- B → luau A: its `mutate.py` entries, and any `Types` gap.
- ui A → luau A: the `ArmoryModel` path for `SOURCES`.
- ui B → ui A: the dead Theme constants.
- designer → luau A and B: the three attribute names.
- Anyone → lead: a needed remote or a project-file change.

**Every agent:**
- Run `git status` and `git diff` first; commit nothing; kill only your own PIDs.
- Write your report to `docs/prompts/l3-w1-reports/<role>.md` as well as replying.
- Ignore `tools/assets/`, `tools/testfit/` and `assets/`: another agent is building the weapon kit there.

**QA after the review** (PATH `export PATH="$HOME/.rokit/bin:$PATH"`, Python `py`):
- stylua, selene, luau-lsp with `tools/types/globalTypes.d.luau` on both sourcemaps;
- `rojo build` for the six place files and `py tools/check_compile.py`;
- the harness: `py tools/crowd_harness/run_harness.py C:/Users/benja/Desktop/tycoon-p5
  C:/Users/benja/Desktop/tycoon/tools/bin/luau.exe` (the repo root first; the worktree has no `luau.exe`);
- `check_stage_mirror` and `mirror_mutants`;
- `check_levels` with its mutants (about 2 h 10 min, in the background);
- `mutate.py` (about 2 h, in the background, in a second worktree while fixes go on);
- `sim_range --check` (64-bit), `sim_combat`, `sim_economy --check` (unchanged).

## 11. Risks, and what needs Ben

- **L3-30. (needs lead, then one line to Ben) The hub joins the publish freeze.**
  - `ProfileSchema` is shared with the live hub. Publishing the hub alone after this merge would refund live players'
    Timber while the live Expeditions place (C0/C1 code) still fights at their old `gear`.
  - It would also replace the only shop whose tiers that place reads.
  - Proposed: both places publish together at L4.
- **L3-31. (conflict, lead) `provingGear`** (L3-11).
- **L3-32. (conflict, lead) The Flamethrower's hint** (L3-25).
- **L3-33. T4 needs a Hard clear at T3.** Without U, Ben meets T4 only after a Hard win in the same Studio session (the
  mock profile). The playtest opens with T, U and L.
- **L3-34. The grind.**
  - A family you have not upgraded is weaker (×0.61 one tier below).
  - A duo splits Timber by damage share, so each player needs about twice the runs (party rules are L5).
  - Valor has nothing to buy after Double Jump; Ascension is unreachable (it needs Steel, Circuits and Alloy).
- **L3-35. R8 on Hard.** The thinnest gate (+1.6%) moves with Hard's `hpScale`. If it turns red, the designer reports
  it; no layout change in W1 without the lead.
- **L3-36. Gamepad A** (L3-22) is unverified: Studio only.
- **L3-37. Placeholders.**
  - The materials and position-1 costs of bands 2–5, and every window above the Forest, are data for later levels.
  - The screen hides unbuilt costs (L3-21).
  - Ben decides the Castle's band with the Castle.
- **L3-38. Old Studio profiles above 3 / 3** (from old levers, with API access) get Steel, Circuits or Alloy back from
  the same frozen list. Harmless.
- **L3-39. Numbers grow fast** (T12 ×370, T20 ×20,337). Not reachable in L3; damage numbers and HP text use `Format`.
- **For Ben (not blocking), at his look:**
  - did the T2 upgrade feel like a step;
  - are three Forest runs per weapon "about right";
  - is the screen readable on a phone.
- The conversion rule (refund) was already told to him on 2026-10-20.

**Rulings: L3-1 to L3-39** (29 rulings, 10 risks): two conflicts with the brief, each with a proposed resolution
(L3-11, L3-25); one optional data-only alternative (L3-16); and one publish rule for the lead and Ben (L3-30).

## 12. Lead's rulings (2026-10-20, after reading the draft)

1. **L3-11 (`provingGear`): accepted as proposed.** `gearOf` drops the `provingGear` branch; the profile's tiers rule in
   a proving build too, so the T2 Ben buys in `proving.rbxl` reaches his hits and his bar. `provingGear` stays T1 for the
   simulators only.
2. **L3-25 (the Flamethrower's hint): accepted as proposed.** The rule is "every non-starter family has a shelf hint":
   a `found` entry or the secret that pays it. L2-51 stands unchanged.
3. **L3-16: the data-only option.** Hard's `rewardMult` 2.5 (cash too); no `dropMult` key. Already written into L3-16,
   L3-27 and §10 above.
4. **L3-30: the hub joins the publish freeze.** Both places publish together at L4. The lead tells Ben in one line.
5. **Owners: two luau-engineers (A shared + hub server, B combat server) and two ui-engineers (A the screen, B the two
   hosts), as proposed.** Every agent runs on Opus. The hub stays in W1.
6. Every other ruling (L3-1 to L3-29) stands as drafted.
7. **`src/shared/Combat.luau` goes to luau-engineer A**, for its private structural copies of `CombatProfile` and
   `ArmoryConfig` only (the v8 fields; ui B's report has the diff). No behaviour change there.
8. **Hard stays ×2** (after the designer's measure, 2026-10-20). At ×2.5 both starters reached T4 in 5 runs and 19.8
   minutes: faster than Ben's pick, "three runs a weapon", because each tier shortens the next clear. ×2 gives 6 runs
   and about 24.6 minutes. `sim_combat`'s climb band is 5–7 runs and 20–40 minutes; a Hard clear pays 20 Valor.
9. **R8 on Hard: the same known limit as Normal until L4.** Hard's re-measured `hpScale` (4.25) and a bow upgraded
   alone tip LookoutLedge, LookoutSignPad and Secret_lookout over the mission player. Ben accepted those perches on
   Normal on 2026-10-16 ("fix in L4" when the real forest re-places them); the lead extends that to Hard
   (`SNIPER_KNOWN_LIMIT_L4["hard"]`). Their rates stay reported, every hit landing stays gated, and the set must be
   empty before L4 ships. The lead tells Ben in one line.
