# L3 study, Part A: systems (tiers, economy, profile, loadout)

Study agent, 2026-10-20, worktree `tycoon-p5`, branch `l3-armory` (b0a0769). Read only; no code changed. Figures come
from `py tools/sim_combat.py` (2 min on this branch) and a scratch cost model. Part B covers the screen and the models.

## 0. In five lines

- Today the tier belongs to the **slot**: one multiplier per slot, applied to whatever family sits in it. Only the hub
  sells tiers, and only once the city earns enough per second. The dungeon place sells none.
- **No one has ever played a fresh profile.** A new player has gear 0/0 (×0.67 / ×0.6 damage, 100 HP); every band and
  every look of Ben's ran at 2/2 (×1.5, 155 HP). L3 must fix the starting point.
- Proposal: a ladder of 20 with **T1 = today's 2/2** and ×1.65 per tier. Normal stays exactly as tuned and Brutal within
  3%; only Hard's `hpScale` needs re-measuring. Windows for all 15 families are in §2.3.
- Profile **v8**, add-only: `tiers`, `loadout`, `stars`. `gear` is left alone because the live places read it. Live
  players hold at most 3/3 (Timber was the only live material). Recommended conversion: refund the Timber.
- Six decisions for Ben (§7); three waves, each playable alone (§9).

## 1. The Armory today, end to end

**Config** (`src/shared/Config/Armory.json`):
- `bands` (4-9): Village/Timber, Boomtown/Steel, Metropolis/Circuits, Orbital/Alloy.
- `slots.melee` and `slots.ranged` (31-70): a starter at tier 0 (Stick 8, Sling 6, 0 HP), then 12 tiers. Each tier has
  `band, cost, unlockRate, name, class, damage, hp, ability, model`; costs are 10 / 60 / 180 per band.
- The multiplier is a tier's `damage` over tier 1's: melee ×1, 1.5, 2.17, 5, 7.5, 10.8, 25, 37.5, 54, 125, 183, 267;
  ranged ×1, 1.5, 2.2, 4.5, 8, 11.5, 20, **11**, 16, 90, 130, 260. Ranged tier 8 (the machine gun's per-bullet damage)
  is weaker than tier 7, a latent bug no live player can reach.
- `ascension` (72-79): ×2 / 3.5 / 6, each needing a Rebirth, all four materials and Valor. `classes` and `abilities`
  (11-30) are C1 data read only by dead C1 paths (§8, risk 7).

**Pure rules** (`src/shared/Armory.luau`):
- `TierDef` (147-160). `DamageScale` (183-201) is slot tier damage × Ascension over slot tier-1 damage.
- `MaxHp` (214-218) is base 100 + hp(melee slot tier) + hp(ranged slot tier). `GearPower` (221-226).
- `CanBuy` (282-300) checks, in order: a next tier exists; **income per second ≥ `unlockRate`**; materials.

**Hub** (hub-only, `src/combat/server/Main.server.luau:5`): `ArmoryService` handles `RequestBuyGear` and
`RequestAscend` (321-326; `HubRemotes.luau:143-155`), checks the city's persisted rate (100-101), spends the band
material and writes `combat.gear` (111-116). Levers: `GrantMaterials` (current era's band material, 190-200), `GrantValor`.

**Dungeon place** (no tier purchase anywhere):
- `RequestBuyAbility` (Main 424-430 → `UnlockService` 153-171) sells Double Jump for 10 Valor (`Expeditions.json:8-11`).
  `RequestSetFamily` (Main 432-441 → `UnlockService` 184-211 → `WeaponService` 2597-2645) holds a family for the session
  only (L2-33); every character starts on Broadsword + Longbow (`WeaponService.AddPlayer` 2128-2133).
- Owned = starters + `combat.families` (`Unlocks.OwnsFamily` 184-190). The lookout pays the Flamethrower
  (`1_ForestRoad.json:10`); the Frost Hammer is lever-only, "Found in the Castle" (`Expeditions.json:13-15`). The other
  11 families have no source in the game.

**From tier to damage (the P5 choke point):**
- `WeaponService.gearOf` (603-633) picks, in order: the range's 1/1; the Studio override; a proving build's
  `debug.provingGear` 2/2 (`Combat.json:123`); the profile's `combat.gear`. `damageScale` (636-650) passes the
  **slot's** tier to `Armory.DamageScale`.
- `CrowdService.Damage` (2028-2100) judges the plate, `heavyHit` 40, the interrupt and armour on the unscaled amount and
  scales only the HP loss (2092-2097): plates never break faster at a higher tier.
- Max HP: `WaveService.maxHpOf` (394-401) → `Armory.MaxHp(gear)`; the range pins {1,1} = 130 (`VitalsService.luau:773`).

**Studio gear and levers:** `gearPresets` 2/2, 4/4, 6/6 (`Combat.json:124-128`), stepped by G (`DebugService` 163-199);
`setGear` writes the override in a proving build, the profile otherwise (125-160); `grantMaterials` pays the live
level's material only, so nothing in the lobby (94-106); keys V, J, F, I, H (`CombatUIController` 190-209).

## 2. Per-weapon tier windows on a ladder of 20

### 2.1 The curve

The proposal: **T1 = ×1.5 of the range's numbers (today's 2/2), then ×1.65 per tier.**

| T | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 12 | 14 | 16 | 18 | 20 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| × range numbers | 1.5 | 2.5 | 4.1 | 6.7 | 11 | 18 | 30 | 50 | 82 | 136 | 370 | 1,008 | 2,744 | 7,470 | 20,337 |
| today's point | 2/2 | | ≈4/4 | | ≈6/6 | | | | | | | | | | |

**Why the fights stay the same:** kill time depends only on enemy HP over the player's multiplier. The plate, heavy
hits, the interrupt and armour read the unscaled amount (CrowdService 2028-2097), and regen is a share of max health, so
each difficulty can be moved onto the new ladder without changing a fight:
- **Normal** at T1 is exactly today's 2/2.
- **Brutal** at T5 gives ×11.1 against ×10.8 melee / ×11.5 ranged today; no change.
- **Hard** at T3 gives ×4.08 against ×5.0 melee / ×4.5 ranged. To keep its clock, `hpScale` goes from 5.2 to about
  4.3-4.7 (the designer re-measures); left at 5.2, Hard runs about 16% longer.
- **Health:** fix the HP ladder at MaxHp (T1,T1) 155, (T3,T3) 230, (T5,T5) 380, today's 2/2, 4/4 and 6/6, so no
  `damageScale` changes. Melee keeps the larger share (35/80/170 against ranged 20/50/110).
- **The range** keeps scale 1 (WeaponService 637-640) but needs its own pinned 130 HP: VitalsService 773 reads
  `MaxHp{1,1}`, which would become 155.
- **An equal alternative:** keep T1 = ×1 and divide every Forest `hpScale` by 1.5. The fights are the same, with more
  data edits; not recommended.

### 2.2 Bands and recommended tiers

Five bands of four tiers, one per level: Forest 1-4 (Timber), Castle 5-8, Underworld 9-12, Planet 13-16, Dream 17-20.
A band's top tier also needs **that level's Hard star** (the trophy). §6's recommended tiers (first, +2, +4):

| | Forest | Castle | Underworld | Planet | Dream |
|---|---|---|---|---|---|
| Normal / Hard / Brutal | 1 / 3 / 5 | 5 / 7 / 9 | 9 / 11 / 13 | 13 / 15 / 17 | 17 / 19 / 20 (capped) |

- A level's Brutal shares a tier with the next level's Normal, so **Brutal Forest needs Castle gear**, which nobody has
  in L3 or L4 (D5).
- Today's 2/4/6 (`1_ForestRoad.json:21,29,37`) become 1/3/5, with `gearPresets` T1/T3/T5 and `provingGear` T1.

### 2.3 The 15 windows (start–top)

At ×1.65 per tier, a weapon one tier below is ×0.61 and two below ×0.37. At every level each slot has at least two
families, usually three to five, that reach the level's Normal tier.

| Family | Window | Found | Why |
|---|---|---|---|
| Broadsword | 1–12 | start | The weapon you learn on lasts three levels; one tier short (still usable) at the Planet. |
| Longbow | 1–12 | start | The same, for the bow Ben judged "right". |
| Flamethrower | 2–8 | Forest lookout | A fire key works at any tier, and it is weak in a fight (Colossus 110 s against 75 s). Arrives at T2, where the starters are by run 2. |
| Warhammer | 3–16 | Forest, first Hard clear | Hard pays a weapon at Hard's tier. No air carry, so no bend hop opens. |
| Frost Hammer | 5–12 | Castle (ruling) | An ice key; reaches the Underworld, whose mechanic is ice. |
| Greataxe | 6–18 | Castle | Leap Smash carries the caster: the Forest bends must close when it ships (§6). |
| Splitbow | 8–8 | Castle, hardest secret | An early relic: already at the Castle's top, never upgraded. |
| Spear | 9–20 | Underworld | Impale Dash carries the caster. Melee's long finisher. |
| Shotgun | 9–16 | Underworld | |
| Piercing Rifle | 11–18 | Underworld secret | Range 120 (Longbow 110): the sniper rule must follow it (§6). |
| Launcher | 13–20 | Planet | |
| SMG | 14–20 | Planet | The boss shredder arrives late. |
| Beam | 16–20 | Planet secret | |
| Chain Gun | 17–20 | Dream | |
| Spinblade | 20–20 | Dream, hardest secret | Ben's relic: found at the top and stays there. |

Per level: Forest 4, Castle 4, Underworld 4, Planet 3, Dream 2. Six families never reach 20.

### 2.4 What changes in each file

- `Config/Armory.json` [economy-designer]: new `ladder` (20), `hp.melee` / `hp.ranged` (20 each), five `bands`
  (`levelId`, material), `costs` by position in a band, `windows` by family, and a frozen `legacy` price list for the
  conversion (§4.4). `unlockRate` stops being read. `slots`, `classes` and `abilities` stay until L4 deletes their C1
  readers.
- `src/shared/Armory.luau` [luau-engineer]:
  - `TierOf(cfg, combat, family)` = clamp(`tiers[f]` or start, start, top), so a window change can never strand a profile;
  - `Multiplier(tier)`; `DamageScale(cfg, tier, asc, ability)`, by tier, not slot; `MaxHp(cfg, tiers, ascension)`;
  - `NextTier`, `TierCost`, and `CanUpgrade(state, family, stars)`: owned → next tier in the window → the band top's
    Hard star → materials. No income check.
- `Types.luau` (`CombatProfile` v8, the new `ArmoryConfig`, `ActionResult` `upgrade` / `equip`); `ProfileSchema.luau`
  (v8, template, `Migrations[7]`, §4).
- Combat server: `WeaponService.gearOf` (603-633) returns the held families' tiers behind the same slot-shaped API, and
  `AddPlayer` (2128-2133) reads the saved loadout; `UnlockService.OnSetFamily` saves, plus a new `OnUpgrade`;
  `WaveService` reads and writes stars in the profile (`starsOf` 440-446, `Award` 1329-1330); `DebugService` levers (§9).
- Hub server: `ArmoryService` swaps `tryBuyGear` for the same upgrade and equip handlers (Ascension stays).
  `EconomyService.copyCombatProfile` (102-127) must carry `tiers`, `families`, `loadout`, `stars` and `abilities`: it
  drops the v7 maps today, so a hub screen could not show what a player owns.
- Remotes: `RequestUpgradeWeapon(family)` in both places and `RequestSetFamily` in the hub, rate-limited.
- Data: `Levels/1_ForestRoad.json` (tiers 1/3/5, Hard `hpScale`, rewards §3.3); `Combat.json debug` (presets,
  `provingGear`); `Expeditions.json found` (a hint for every non-starter family).

### 2.5 Everything that reads tier numbers (each must move with the ladder)

- **`sim_combat.py`:** the Armory mirror (247-421); the unlock table (1916-1970) and C0 check 1 (2765-2801), gone with
  the gate. **`check_stage_mirror.py`:** mirrors the real `Armory` (155).
- **`sim_range.py`:** `THREAT_TIER = 1`, `armory_max_hp`, `hpByTier` (180, 1582-1588, 3602-3606); `gear_max_hp`,
  `mission_gear` (5257-5275); `level_view` (7013-7027); `preset_gears` / `recommended_gear` / `preset_below`
  (8971-8983), which run the Hard and Brutal bands and the human's "one preset below" gate (5084-5087).
- **Crowd harness:** bundles `Armory.luau` (`run_harness.py:78`); `tests_p5` RefreshMaxHp (257-263); `tests_l2`'s v6
  profile (55, 122) needs a v8 case. **`check_levels.py`:** `fielded_lifts` (894), the bend gate (4704-4730),
  `longbow_range` (5051-5054).
- **Bosses:** the range's Colossus and Warlord run at scale 1; the Forest Colossus is unchanged if T1 = old 2/2; the
  Warlord fights only in the Raider Arena (`recommendedTier` 2 → T1). **R8 sniper gates** are rated at the proving gear
  (`sim_range` 7078-7099); with per-weapon tiers, also rate bow T4 with sword T1 (§8, risk 3).

## 3. Economy

### 3.1 What Forest Road pays today (sim_combat, solo, about 5 min a clear)

| | Cash | Timber | Valor | Measured clears |
|---|---|---|---|---|
| Normal | 131,733 | 211 | 10 | at 2/2: 5:15, 4:41, 5:02 |
| Hard | 283,800 | 454 | 20 | at 4/4: 5:06, 5:19, 5:11 |
| Brutal | 569,333 | 906 | 40 | at 6/6: 5:05, 5:21, 5:07 |

- **Normal by part:** Pickets 6,600 cash / 9 Timber; Main Camp 57,000 / 95; ambush 12,400 / 18; the Colossus wave
  48,133 / 76 + 10 Valor; camp bonuses 7,600 / 13. Every kill pays as it falls and camps never refill, so a replay pays
  what a first clear pays.
- **Chests pay once per player** (`SecretFlow.Decide` 201-205): lookout 3 Valor + 50 Timber + the Flamethrower (run 2
  at the earliest, after Double Jump); cache 4 + 60 (needs fire); shrine 6 + 60 (needs ice: not before the Castle).
- A shortcut run pays 124,040 cash and 201 Timber in 4.3-4.5 min (PLAN L2 W2). Valor comes only from the Colossus. The
  Raider Arena pays 144,250 cash, 258 Timber and 35 Valor in about 10-11.5 min.

### 3.2 Runs to take weapons from T1 to T4 (Timber only)

The model: Normal runs until the weapon reaches T3, then Hard runs (the Hard star opens T4). The lookout and cache pay
on runs 2 and 3. Normal is counted as 5 min at every tier, which is pessimistic.

| Cost of T2 / T3 / T4 | Per weapon | One weapon | Both starters |
|---|---|---|---|
| A, quick: 60 / 150 / 300 | 510 | 2 runs (10 min) | 4 runs (20 min) |
| **B, medium: 100 / 250 / 500** | 850 | **3 runs (15 min)** | **6 runs (31 min)** |
| C, slow: 150 / 450 / 900 | 1,500 | 5 runs (25 min) | 10 runs (51 min) |

Each family a player switches to adds its own cost. Recommendation: B. The first clear buys T2 for both weapons, so the
upgrade is felt at once; T4 on one weapon takes about three runs.

### 3.3 Hard and Brutal (placeholders today: PLAN 3052-3055, INTERFACES 11264)

- **Hard:** at T3, a Normal replay clears in about 3.3 min (the walk is fixed at 1,055 studs), about 64 Timber/min.
  Hard at ×2 pays 89 Timber/min, and a down ends the run. Proposal: materials and Valor `rewardMult` 2.5, cash left at
  2 (it barely matters, §3.4). The first Hard clear gives the trophy (T4 for every Forest weapon) and the **Warhammer at
  T3**.
- **Brutal:** recommended at T5, so it comes after the Castle (D5), when Timber is no use. Proposal: once the Castle
  exists, Brutal Forest also pays the Castle's material. Its "only Brutal" first-clear reward: 25 Valor and a map mark.
- **Valor** has nothing to buy after Double Jump until the Glide (§8, risk 9).

### 3.4 The city income gate (§11.1), and what the city gets from a level

- **The gate** lives only in `Armory.CanBuy` (282-300), called from the hub `ArmoryService` (100-101), against
  `unlockRate` (T2 15K/s, T3 120K/s; a greedy Village player crosses them at 12:21 and 26:45). The dungeon place never
  checks it (it only shows `incomeAtSave`, Main 106). Dropping it: materials and the Hard star limit tiers, a
  dungeon-first player progresses without the city, sim_combat check 1 and the unlock table go.
- **Cash** goes to `state.cash` × the Legacy perks (WaveService 789-807). Normal's 131,733 is 0.9% of what the Village
  still costs at 12:21, about 2 s of median Village income (64K/s), and nothing later. **Time in the dungeon** earns the
  city's offline income at 100% instead of 50% (`Combat.json offline.expeditionEfficiency`, `Combat.AwayEfficiency`
  541-552, Main 460): the one real tie. Income-scaled combat cash was rejected by Ben in C0 and is not proposed.

## 4. The profile

### 4.1 v7 today (`ProfileSchema.luau:14,35-49`; `Types.luau:969-990`)

`combat` holds `materials`, `valor`, `gear` and `ascension` {melee, ranged}, C1's `missions` and `highestEra`,
`expeditionSince` / `expeditionSeconds` (the hub's offline grant), `stats`, and the v7 maps `abilities`, `secrets`,
`families` (starters implicit) and `shortcuts`. Stars are session memory (`WaveService` 229-230).

### 4.2 What is live, and what it does with a v8 profile

- **The last recorded publish of both places** is M9 wave 2b, schema v6, around 2026-09-23 (`MANUAL_STEPS.md`
  1097-1100 and 1222-1229 ticked; the C2 republish at 1381-1388 is not). So the live Expeditions place runs C0/C1 code.
- **At that commit** (2b15570), `Config/Missions` held only `1_Village.json` (Timber), and tier 4 needed Steel. So live
  players hold **`gear` ≤ 3/3** (at most 250 Timber per slot) and no Ascension. Caveat: an unrecorded publish would change
  this; the Creator Hub's "last updated" date settles it.
- **Old code on a newer profile:** `Reconcile` only fills nil keys and deletes nothing (L2 W1 luau-engineer report,
  ProfileStore 408-422); `runMigrations` warns "ahead" and plays untouched (`DataService.luau:103-108`). Old code keeps
  every new key; the old hub could still sell slot tiers into `gear`, which new code ignores (§8, risk 6).
- Live profiles are v6, so at the L4 publish one load runs v6 → v7 → v8.

### 4.3 The v8 shape, settled once

Add-only; nothing renamed or removed.

```
combat.tiers   = { [familyId]: number }   -- only families upgraded past their start; read via Armory.TierOf (clamped)
combat.loadout = { melee: familyId, ranged: familyId, variants: { [familyId]: variantKey } }
combat.stars   = { [levelId]: { [difficulty]: true } }  -- leaves session memory; the Hard star IS the trophy
```

Kept: the v7 maps; `ascension` (per slot, multiplying whatever family sits there); `gear`, frozen (live code reads it,
new code does not); `missions` and `highestEra` until the L4 dead-code pass. Stars move into the profile now: the T4
gate must survive a session, and the map's `requires.node` already reads stars (`StageFlow` 2822-2831).

### 4.4 The v7 → v8 step and the conversion

`Migrations[7]` adds `tiers = {}`, `loadout = {broadsword, longbow, {}}` and `stars = {}`, each only when nil and each
a fresh table (the v6 step's pattern, 110-124), then applies the rule Ben picks (D4). Recommended: refund every tier
bought in `gear` at frozen `legacy` prices (tiers 1-3 in Timber: 10 + 60 + 180 per slot), start the starters at their
window start, leave `gear` untouched. The prices are frozen because the step must not read live `slots` costs, which L3
or L4 may change; the version stamp runs the step once.

## 5. The saved loadout

- **Where it changes:** the dungeon lobby's Armory (`RequestSetFamily` now writes `combat.loadout`: PLAN 4054-4055's
  visit-only choice becomes the saved one) and the hub's screen (same verdict, `Unlocks.FamilyVerdict` 248-278, gate open).
- **Never inside a live fight:** `WaveService.MayLeave` (2237-2243) is false for a fighting member. P5's "between waves"
  rule (2026-10-12) was for the ten-wave arena; levels have no waves, and nothing needs it.
- **At admit** `WeaponService.AddPlayer` reads it; an unowned or unknown family falls back to the slot's starter, an
  unknown variant to the family's default.
- **Both screens do the same things** (lead ruling proposed): view, upgrade, equip, abilities. The pure rules (`Armory`,
  `Unlocks`) are shared, so each place needs only a thin handler.
- **"A cooldown carried across a family switch"** (INTERFACES 9385, PLAN 1878) can close: nobody can switch mid-fight.

## 6. Carried items that name L3

1. **Hard's and Brutal's rewards are placeholders** (PLAN 3052-3055, INTERFACES 11264) → §3.3.
2. **Ability-arc hops at both U-bends** (PLAN 4048-4050). The carriers are the Greataxe (Leap Smash) and the Spear
   (Impale Dash) (`check_levels` 4704-4712). Under §2.3 both come from later levels, so the hops stay a known limit in L3.
   But the gate's `ownedFamilies` counts only starters and secret-paid families (4721-4723): it **must also count L3's new
   sources** (first-clear rewards, any sale), or it cannot see the day it turns red. When the Castle ships the Greataxe:
   a wall at BC and the BendWall run south (data).
3. **The saved loadout** (PLAN 4054-4055) → §5.
4. **"Profile shape designed once, stars and unlocks from the profile, the city tie, models, free variants, the
   loadout, the cooldown across a switch"** (INTERFACES 11150-11153; P5 Wave 2 at 9378-9385; PLAN 2813) → §4, §3.4, §5.
   Free variants already ride `RequestSetFamily` (L2 W2); models are Part B.
5. **"A longer-range weapon reaching B's floor"** 127 studs from RoadBC5-6 (INTERFACES 15599-15601). No family reaches
   127 (Rifle 120, Longbow A 110, Launcher and Beam B 100: `ProvingGrounds.json`), and tiers never change range (WEAPONS
   §3). The real follow-up: `check_levels` takes the sniper reach from the Longbow alone (5051-5054); once the Rifle can be
   owned it must use the longest range of any ownable ranged family.

## 7. Decisions for Ben (each can be a click question)

1. **"Weapon windows: is the table right?"** (§2.3, drawn as bars) — data only in every case.
   - **As proposed (rec):** starters 1–12, two relics, six never reach 20.
   - **Longer:** every window runs to 16 or more; favourites last nearly the whole game, switching matters less.
   - **Shorter:** 6–8 tiers each; a new weapon every level or two, grind spread over more families.
2. **"How many Forest runs to take one weapon from T1 to T4?"** — data only; slower deepens the switching penalty.
   - **2:** both starters in about 20 min. **3 (rec):** about 31 min. **5:** about 51 min.
3. **"Should the city's income still gate weapon tiers?"**
   - **Drop it (rec):** levels gate tiers; the city keeps the cash and full offline income while you fight.
   - **One city era per band** (e.g. the Castle band needs Boomtown): brings back the tie Ben cut on 2026-10-13.
   - **Keep per-tier rates:** needs rates for 20 tiers, and a dungeon-first player stalls.
4. **"Players who already bought tiers in the live game?"** (at most tier 3 per slot, at most 500 Timber)
   - **Refund their Timber (rec):** fair at any new prices; small code.
   - **Keep their strength:** old 1-2 → T1, old 3 → T2; no wallet change, a rough mapping.
   - **Nothing:** they keep the Timber still in their wallet; simplest, and old buyers lose a little.
5. **"Brutal Forest: when can it be beaten?"**
   - **With Castle gear (rec):** recommended T5, a goal to come back for; its tuning is unchanged.
   - **With Forest gear:** recommended T4; Brutal's `hpScale` drops about 40% and its "only Brutal" reward comes early.
6. **"What does Forest's first Hard clear give?"**
   - **The trophy and the Warhammer (rec):** a fourth Forest weapon that carries no one through the air.
   - **The trophy only:** three Forest weapons until the Castle.
   - **The trophy and a Timber prize:** no new weapon in L3.

## 8. Risks, said plainly

1. **A new player's first run has never been played** (gear 0/0, ×0.67, 100 HP). L3's T1 must be today's 2/2; the proving
   build's baked `provingGear` hides the gap.
2. **The grind doubles with two slots** and grows with every switch; start tiers soften it, D2 decides the feel.
3. **Sniping gets better:** upgrading only the bow makes perch sniping pay relatively more; R8 should rate bow T4 + sword T1.
4. **Plates never break faster at a higher tier** (P5 ruling 9). At T20 a player still needs an unscaled heavy hit of 40+;
   the Longbow sits at 45/42 against `heavyHit` 40. As built, but more visible with 20 tiers.
5. **Live veterans hold Timber** (the Village mission paid about 258 a run) and could buy T2-T3 at once; T4 is bounded by
   the Hard star. The live player base is small (the audience-reach block).
6. **An old server still running after the publish** can sell slot tiers into the dead `gear` field. Restart servers after
   publishing (MANUAL_STEPS C2 step 8).
7. **Dead C1 paths read `slots` by slot:** InputController 425, WeaponController 143, CombatUIController 1048, `Combat.luau`
   698-735, CombatService 136/565. Keep `slots` until L4 deletes them, or delete them together.
8. **The range's 130 HP and every band move** if `MaxHp(1,1)` or the presets are relabelled carelessly; the gates catch it
   only if the mirrors move in the same commit. WeaponService is 3,015 lines: new code goes in new modules (`check_compile`).
9. **Valor has nothing to buy** after Double Jump until the Glide. **Ascension cannot be reached:** it needs Steel,
   Circuits and Alloy, which nothing pays.

## 9. Wave split (each playable alone in Studio)

- **W1, tiers per weapon** (no new screen):
  - **luau-engineer:** `Armory.luau`, Types, ProfileSchema v8 with the conversion, `gearOf` / `AddPlayer`, `UnlockService`
    (save, upgrade), the hub `ArmoryService`, the `EconomyService` copy, `WaveService` stars, `DebugService` levers
    (Timber in the lobby on T, `setTier`, the Hard star, reset Armory).
  - **economy-designer:** `Armory.json`; the Forest remap with the Hard `hpScale` re-measure and the rewards; presets;
    `found`; every mirror and gate in §2.5, including `ownedFamilies`.
  - **ui-engineer:** a tier line and an Upgrade button on the lobby Weapons tab. **lead:** remotes and Main wiring.
  - **Ben plays:** clear Normal, buy T2 in the lobby, feel it on the next run; G steps T1/T3/T5.
- **W2, the Armory screen in both places** (ui-engineer; Part B): shelf of 15, tier tracks, next tier and cost, the
  abilities tab; upgrade and equip in the hub; placeholder art.
- **W3, weapon models** (asset builders, then ui-engineer; Part B): a generated kit, strips Ben approves before any
  upload, one harvest paste, models in hand and on the screen.
- **Every wave:** review, then QA (harness, mutants, sims, `check_compile`); merged on the P5 rule; publish freeze to L4.
