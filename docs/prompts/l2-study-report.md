# L2 study report: secrets and keys

Branch `l2-secrets` (574c1c4), worktree `tycoon-p5`. A read-only study; no code was written. Paths are
relative to the worktree. `py -B tools/check_levels.py` was run once and passes.

## 0. What matters most

- **No key works today, and two of the three secrets need none.** The cache is a solid box 10 studs
  above the road (one plain jump), and the water is solid (walk to the shrine). Only the lookout needs
  the double jump, and one jump plus the Greataxe's Leap Smash also reaches it. No code reads
  `secret.needs`.
- **Double jump runs on the client only and is always on.** The server never counts air jumps. The
  honest place to enforce a key is the server, at the moment the reward is given.
- **Nothing from L2 can be saved without a schema bump.** The profile is at v6 and stars are kept in
  session memory. Valor is saved, so selling a session-only ability for it would lose that Valor.
- **The lobby has no loadout picker and no shop.** Every level is played with Broadsword and Longbow.
- **A weapon family is mostly data,** plus one ability mechanic (server, client effects and
  `sim_range.py` all require one) and one visual.
- **World reactions have one clean server choke point** (`WeaponService.finish`). Levels are rebuilt
  every run, so burnt or frozen blocks reset for free.

## 1. The three secret sites today

Heights in `src/shared/Layouts/Levels/ForestRoad.json`:

| Where | Top height |
|---|---|
| Start road (`Road1`–`Road4`, lines 283–289) | 0 |
| Plateau (`Road5` 290, `RoadAB*`/`RoadBC*` 293–304, camps A and B) | 8 |
| Gatehouse, camp C | 12 |
| Water | −1 |
| `killY` (line 4) | −13 |

`secrets` is at lines 314–348. Every secret is a purple block, look `secret` (`Expeditions.json:31`,
the only coloured look), with a dark sign whose text names the key it needs.

| Site | Layout | Walk | 1 jump + dash | Double jump |
|---|---|---|---|---|
| **Lookout** (`doubleJump`) | Purple 6×4×6 at (−283, 36, −59) (315–325), on `LookoutLedge`, top **34** (291), 26 above `Road5`; `LookoutSignPad` (292) | no | no (18 + 3 step-up = 21; the best take-off, `Camp_A_Fence_north`, falls 1 stud short) | **yes** (30, 4 to spare); **also jump + Leap Smash = 28** |
| **Cache** (`fire`) | Solid purple 12×10×12 at (100, 13, −4), top 18 (326–336), at the end of the dead-end `CacheSpur` (299); `CacheSignPad` (300). **No cave and no bramble:** no hit in `src` or `tools` | no | **yes, one plain jump** (10 up) | yes |
| **Shrine** (`ice`) | Purple slab 12×3×12 on `Pond` (286); `Creek` (285) runs under `Road2` into the pond; `ShrineSignPad` (287) | **almost:** step onto the solid creek, walk about 70 studs on water, hop 3 ("Water is solid in L1", `docs/BALANCE.md:3685`) | yes | yes |

**Code that touches secrets.**
- `LevelGeometry.luau`: `SecretBox`/`SignBox` 423-445; secrets hold blocks up (485) and set the bounds
  (568); it builds a colliding `Secret_<id>` and its sign at 821-840.
- `LevelService.luau:199-205` sets the sign size.
- `Types.luau:2598-2609` defines `LevelSecret`.
- `MapScreen.luau:27` says "icons are L2".
- `Region.luau` ignores secrets, but the plateau region's cells include `LookoutSignPad`, `CacheSpur`
  and `CacheSignPad` (ForestRoad 13, 20, 21).

**`check_levels.py`.**
- 900–925: exactly three secrets; each sign names its key; each sign stands on solid ground.
- 926–963: the lookout band, `jump + STEP_UP` (21) < rise ≤ `jump + double − 4` (26). Today's rise is
  26, exactly on the limit, and no surface may be within one jump + step-up + dash.
- 964–979: the creek **must be solid** and at most 1 below the road.
- 3179–3184: the Leap Smash note left for L2.

**Simulator gates that depend on the sites.**
- **R8 sniper spots** (`check_levels.py:1588-1640`, pinned 98–101, equality 1852–1863). The pinned set
  includes `Secret_cache`, `Secret_lookout`, `LookoutLedge`, `LookoutSignPad`, `Creek` and
  `ShrineSignPad`. Any change to a secret, its pads or the water fails the check until it is re-pinned.
- **Perches** (1808–1851): `LookoutLedge` (34) and `Secret_cache` (18).
- **The three Normal snipers accepted until L4** (`sim_range.py:6677-6681`, `SNIPER_KNOWN_LIMIT_L4` =
  LookoutLedge, Secret_lookout, Secret_cache). Every other spot and every Hard row is gated at
  9607–9631. Two of the three are secret blocks: **turning the cache into a roofed cave removes one L4
  sniper for free.**

## 2. Double jump today

**Client** (`src/combat/client/Controllers/MovementController.luau`):
- `onJumpRequest` (428-457): a fresh press in the air sets `JumpHeight = doubleJumpHeight` and writes
  the velocity (449-456).
- One air jump per airtime: the `airJumpUsed` flag (134) resets on landing (634, 645-647) and on
  respawn (842).
- Phones use the stock jump button.
- Config is `ProvingGrounds.json:243-266`: jump 18, double 12, dash 20, `airJumpDelay` 0.12. There is
  no `airJumps` key.
- It runs in every combat-place build (`Start` returns unless `IsCrowdCombat`, 816-819). The hub does
  not map `src/combat`. No per-player flag exists.

**Server: nothing checks vertical movement.**
- The client owns its character's physics; `SetNetworkOwner(nil)` is called only for enemies
  (`EnemyService.luau:854`).
- `WeaponService.trackAir` (1834-1887) keeps `peakY` and dive speed for the slam and `SwingGate`, but
  no take-off floor and no jump count.
- `OnDash` (2336-2352) only opens i-frames.
- `StageFlow.IsOut` has no ceiling.

**Making it owned per player.**
- The server sets a Player attribute (e.g. `AbilityDoubleJump`) from the profile at join and on
  purchase, as for `Cash` (`EconomyService.luau:242`). A Player attribute survives respawn.
  `onJumpRequest` adds it to its refusals (433-443).
- **Limit:** a modified client ignores the attribute. A detection heuristic
  (`peakY − takeoffFloor > jumpHeight + margin`) would have to excuse Leap Smash, knock launches,
  `MoveMember` and lag. **Not recommended.**
- **The enforcement that matters is the reward:** only an owner gets the lookout's chest. That one
  check also closes the Leap Smash route.
- Optionally, a per-player `WallClip.Rise`: 18 without the double jump, 30 with it, in
  `WeaponService.GroundPoint` (2560) and `InputController.luau:1868`. Then a non-owner's Leap Smash
  cannot target the ledge either.

**Rules that assume double jump.**
- **Hold without it:** route climbs ≤ 10 and gaps ≤ 15 (INTERFACES 10872-10873; `check_levels.py:107-108,
  371-378, 555-583`); "the main path never needs it" (INTERFACES 11144); the sneak path
  (`check_levels.py:2701-2742`).
- **Need it as the key:** the lookout band (INTERFACES 10879, 10888; `check_levels.py:116-121, 926-963`).
- **Use it as a worst case, so they only gain margin:**
  - camp barriers (INTERFACES 9488-9497, 11088);
  - `stray_reach` 46.6 and `climb_max` 43 (`check_levels.py:392-408`);
  - L1c's walled clearing ("not even from the top of a double jump", wall 64, `check_walled` 2259-2317);
  - the trigger ceiling (`StageFlow.luau:61-65`);
  - `WallClip.Rise` (141-145, `tests_l1c.luau:142-150`);
  - the camera boom (`CameraController.luau:79`).
- **Nothing in L1, L1b or L1c breaks for a player without it.**
- **Feel risk:** the double jump is part of the P1 movement Ben approved. `sim_range`'s reacting
  players assume it ("a climb or a double jump costs nothing more", 6668), and no one-jump policy row
  exists yet.

## 3. Saving

- **Schema v6** (`src/server/Services/ProfileSchema.luau:14`; template 20-46).
- `combat` (35-45) holds materials, valor, gear{melee,ranged}, ascension, missions, highestEra,
  expeditionSince/Seconds and stats. **There is no `loadout`.** v7 `combat.loadout` was P5 Wave 2,
  which is suspended (`docs/PLAN.md:2566-2570`).
- Types: `PlayerState` `Types.luau:36-59`, `CombatProfile` 960-970.
- **Migrations:**
  - `Migrations[n]` is add-only and safe to run twice (48-100).
  - Trap (88-92): Reconcile runs **before** migrations, so a step must patch an existing table.
  - Runner: `DataService.luau:90-110`. A profile ahead of the code warns and plays untouched (103-108).
  - Both places mount the same Services folder. `WaveService` is the only combat writer of the profile.
- **Stars** are session memory: `WaveService.luau:207-208`, awarded 1247-1248 ("Ruling 25").
- **Cost of a bump:** one add-only step plus template, Types and levers, about the size of v5→v6
  (`settings.cityDetail`).
  - The real cost is the rule that both places publish together (`MANUAL_STEPS.md:1229-1230`), which
    the Expeditions freeze until L4 already forces.
  - Live profiles are v6 (`MANUAL_STEPS.md:1098-1100`).
- **`proving.rbxl` is a local file and almost certainly runs ProfileStore's mock** (Output: "data will
  not be saved", `MANUAL_STEPS.md:97-100`). Ben cannot tell saved from session data in L2, so saving is
  a correctness matter, not a playtest step.
- **L3 owns the profile shape, "designed once"** (INTERFACES 11150-11151).
- **What L2 needs saved:** owned abilities, opened secrets per level, and owned families if weapons are
  earned (D2). All three are maps keyed by id, which L3 would not reshape.

## 4. Currency and a place to buy

**Valor.**
- Earned only from bosses (`Combat.luau:449-461`). The Forest Road Colossus pays 10
  (`Config/Levels/1_ForestRoad.json:63`) × `rewardMult` 1/2/4 (WaveService 594-595), split by damage
  (732). There is also a mentor bonus (676).
- Stored in `state.combat.valor`.
- Spent only by the hub's Ascension forge (`ArmoryService.luau:121-156`, 50/120/250 after rebirths).
- Shown on the dungeon HUD (`CombatHud.luau:402, 1393-1398`).
- **A Normal clear pays exactly 10**, so "about what the first boss pays" means a price of 10 Valor.

**The lobby camp.**
- Server: `LevelService.BuildLobby` (410-464) builds a 48×48 floor from `Layouts/Levels/Lobby.json`
  with a "MAP - press M" sign.
- Client (`CombatUIController.bootMission`): MapScreen (1381-1404, M or the lobby phase), CombatHud
  (Map, "Return to your city"), SummaryCard, and the Studio-only DebugPanel (it has `+Valor`).
- **No Armory, loadout or family picker.** The only picker is the Studio-only RangePanel
  (`RangeService:353-354`).
- The hub's `ArmoryPanel.luau` is the old tier shop (`RequestBuyGear(slot)`, `HubRemotes.luau:141-148`),
  which L3 replaces.

**The smallest honest buy flow.**
- Config: an `abilities` block in `Config/Expeditions.json`, e.g.
  `doubleJump = { name, price = { valor = 10 }, order }`.
- Remote: `RequestBuyAbility(abilityId)` in `CombatRemotes.luau`, bucket `calls` (10/s, token bucket
  `RemoteService.luau:65-85`), validated with `isShortString` (96-98).
- Server checks, in order, with no yield between check and write:
  1. the profile is loaded;
  2. the id is in the config;
  3. it is not already owned;
  4. the player is in the lobby phase;
  5. `valor ≥ price`.
- Then: deduct, mark owned, set the attribute, mark the profile dirty as `WaveService` does
  (`EconomyService` is not booted in this place), and reply with `ActionResult`.
- Client: a small "Abilities" panel in the lobby, which becomes the Armory's second tab in L3
  (MISSIONS_DESIGN §10).
- Studio levers, with both entry points: `grantAbility`, `clearAbilities`, `resetSecrets`.

## 5. New weapon families

**The yardstick is P3's Beam.** Commits `be7dba2` (config) and `93efcbb` (27 files, +9,887 lines, but
that was all 13 abilities at once). The Beam-specific part is about 230 lines: FeedbackController's held
beam ~100, `AbilityFx/OverloadSweep.luau` 187, InputController ~15, Theme 18, and a few lines in
WeaponService, AbilityService, Tuning and sim_range.

| Area | Cost of one family |
|---|---|
| Config | One `weapons.<id>` block, ~8 lines (`ProvingGrounds.json:183-190`). `Armory.json` has no families. |
| Registry | None beyond that block; `Tuning.luau:45-52` (structural) and 76-90 (shape ∈ arc, sphere, capsule, cone, ray). |
| Server | Nothing for an existing shape. **An ability id is mandatory:** `AbilityService` `MECHANICS` (700-715) plus a launcher. |
| Client | The stream or shot visual (FeedbackController), `AbilityFx/<Name>.luau`, ability special cases in InputController (205, 1632-1638, 1894). |
| Tools | `sim_range.py` loops families itself, but `plan_ability` (1157-1281) **raises on an unknown ability**; `FAMILY_TARGETS` (143-147) is optional. Harness, `check_stage_mirror`, `check_levels` and dummy sets need nothing. |
| Ownership | **None.** `era` only groups RangePanel buttons. Everyone gets `{broadsword, longbow}` (`ProvingGrounds.json:200`, `WeaponService.luau:335-349, 2010-2021`), held in memory (`SetFamily`/`SetVariant` 2447-2492). |
| Lobby picker | **Missing, and needed before any other family reaches a level:** `RequestSetFamily(slot, family, variant)`, refused outside the lobby or for a family the player does not own. |

**Flamethrower:** a ranged variant with `shape: "capsule"` and `continuous: true`.
- The area branch of `resolveRanged` (1413-1438) already builds a capsule on the camera ray, cut at
  walls by `worldReach` (1336), and hits everything inside up to its cap.
- `continuous` gives held fire (`InputController:1333-1347`); `rangeAttackCallsPerSecond` is 40.
- Gaps: `tick = continuous` is set only in the ray branch (1389); a flame visual; an ability (mapping a
  new id onto an existing launcher keeps it small, but `sim_range` still needs its branch).
- Not the Shotgun cone path (1294): it ignores walls.

**Frost weapon:**
- Melee reuses the Spear capsule (`resolveMelee` 1059-1089) or the Broadsword arc.
- Ranged reuses the Beam/SMG ray (1337-1393).
- An `element` field on the variant is new (`Types.luau:1755-1769`, plus a structural path).
- The crowd has no slow or freeze status, which fits §9: elements are keys first.

**Both bosses are tightly tuned**, so each family needs a `sim_range` row against the Colossus and a
cash-per-minute check.

## 6. World reactions

**Hit paths.**
- Every crowd hit goes through `strike()` (`WeaponService.luau:745-758`).
- **Every resolved shape goes through `finish()`** (760-811) with its `StrikeFx` (shape, origin,
  direction, size, arc, width, endPoint, family, ability), including empty swings, slams and ability
  ticks.
- Only rays (`worldReach` 412-423, which discards the Instance hit) and projectiles (a raycast per step,
  1673) see world geometry.

**Proposed reaction rule.**
- In `finish()`, take the family's `element`. If the shape touches a reactive box of that element, the
  level reacts.
- A colliding bramble already stops rays and arrows at its face, so their `endPoint` lands on it; a
  melee arc or capsule overlaps it.
- This is a pure box-against-shape test the harness can run. Skip the empty `abandonProjectiles`
  finishes (815-840).

**Tagging.**
- Today `LevelGeometry` builds `Piece {name, role, box, look, collide}` (41-55, 680-851), and
  `LevelService.construct` (276-355) makes Parts that carry a name only: no CollectionService tags and
  no attributes.
- Proposal: layout entries take `react = "fire" | "ice"`, and `LevelService` keeps a per-run list
  `{name, box, react, part, state}` and applies the change:
  - **Fire:** remove the bramble Part (or make it non-colliding and invisible) and send one burn cue.
  - **Ice:** add a walkable Part of look `ice` over the water, either the whole strip at once or one
    disc per hit, so the player freezes their way across.
- Parts replicate by themselves; the client only adds the effect.

**Reset.** `startLevel` does `LevelService.Clear()` then `Build` (WaveService 1791-1792), and
`backToLobby` clears again (1296). The world resets every run; only the per-player "opened" record
persists (§3).

**Crowd.**
- Bodies are clamped to region rectangles; the crowd never raycasts.
- The region is built once in `StageFlow.Plan` (1559-1574), and `CrowdService.SetFloors` refuses while
  any body is alive (1546-1552): **the region is static per run.**
- Burnt bramble needs no region change.
- The creek and pond (x ≈ −400) lie outside every floor (cells span x ≈ −302…198), so ice is for
  players only. Letting raiders onto it would need a mid-run `SetFloors`, which does not exist and is
  not proposed.

**Deep water.** For ice to be a key, the water must stop being solid. Then:
- `check_levels.py:964-979` is rewritten, and `Creek` leaves the pinned sniper list.
- A fall goes below `killY` −13 and gets the free rescue (`StageFlow.IsOut`/`Rescue` 2430-2477).
- The island must lie beyond `stray_reach` 46.6 (with Leap Smash and dash) of every standable surface.
  Today the slab is 20 studs from the pond's edge, so the pond grows or the shrine moves. Grey blocks
  make that cheap.

## 7. The second exit and the side node

**What exists.**
- Nodes: `Expeditions.json:7-14`.
- `MapNode` (`Types.luau:2633-2644`) supports `requires {node?, stars?}`. `MapNodeState` (2733-2740)
  has no field for secrets or exits.
- `StageFlow.luau:2549-2599` decides open, `notBuilt`, `needsNode` and `needsStars` from the
  **leader's** session stars.
- `MapScreen` already draws branches (dots to each node's `from`, 1059-1084).
- `raiderArena` is a bonus node `from forestRoad` with no `requires`, so it is open today.
- **No exit trigger exists:** no `Touched` and no `GetPartsInPart`. The only spatial tests are the
  checkpoint reach (`StageFlow.progress` 1889-1916) and the camp band. A run ends only as `cleared`,
  `down`, `wipe`, `runCap` or `abandoned`.

**Options, cheapest first.**
1. **Loot only:** the chest trigger, which every secret needs anyway.
2. **The cache gates the Raider Arena** (a finished node with its own numbers). Cost:
   - a `requires.secret = "forestRoad.cache"` kind in Types, `StageFlow.NodeState`, a reason string and
     the MapScreen text (152-155, 332-338);
   - the record comes from the saved secrets map;
   - opening the chest "finds the raiders' trail". A walk-out door instead would need a new run-end
     reason (`RunResult.reason` and `EarnsStar` know only `cleared`).
3. **A new side level:** option 2 plus a layout, a level file and a balance pass. L4-sized.
4. **A shortcut on later runs:** the layout changes per leader, `check_levels` must cover both
   variants, and it changes stars, sniping and the run length Ben approved.

## 8. Rulings the lead can take

1. **R1. Save in L2** with one add-only v7 step: `combat.abilities = {}` and `combat.secrets = {}`, plus
   `combat.families = {}` if D2 earns weapons. L3 adds v8 if it needs more. Stars stay in session
   memory unless Ben asks (a one-line addition to the same step).
2. **R2. Keys are checked server-side where the reward is given, per player.**
   - The chest's trigger is a pure flat-distance and height-band test run in the run loop, like
     `progress`.
   - It pays only an owner of the key, once (saved).
   - In a party, burnt bramble and frozen sheets are shared, and each player opens their own chest.
3. **R3. Per-player `WallClip.Rise`** (18 / 30), so a non-owner's Leap Smash cannot target the ledge.
   The lookout's band (26) stays.
4. **R4. No movement anti-cheat;** R2 is the enforcement.
5. **R5. The cache becomes a roofed cave** with a bramble mouth (`react = "fire"`), unreachable within
   `climb_max` 43 any other way, and with no standable top in Longbow range of a region. That removes
   `Secret_cache` from the L4 sniper list.
6. **R6. Deep water:** non-solid, with the rescue. The pond grows so the island lies beyond
   `stray_reach`. The `check_levels` rule and the sniper pins are rewritten.

## 9. Decisions for Ben (with a picture first: lobby panel, cave mouth, frozen creek, gated arena)

**D1. What each secret gives in L2.**

| Option | Cost |
|---|---|
| A. Loot only: chests of Valor and Timber, the lookout smallest and the shrine biggest | Chests only |
| **B. A, and the cache also opens the Raider Arena on the map** (free today) | + one `requires.secret` kind and the map text |
| C. B with a new small side level instead of the arena | + a layout, a level file and balance; L4-sized |
| D. A shortcut on later runs | A per-player layout, both variants gated, changes the run length |

*Recommend B:* the map becomes a tree for the price of one rule.

**D2. How a player gets the Flamethrower and the frost weapon.**

| Option | Cost |
|---|---|
| A. Free for everyone in the new lobby picker; owning weapons waits for L3 | Picker only; the fire and ice secrets open on a first visit |
| **B. Flamethrower on the first Hard clear (the L0 mock); frost weapon by Studio lever until the Castle** | + the saved `families` map, and the picker filters by it |
| C. Both found in forest secrets (lookout → Flamethrower, cache → frost) | As B; it chains the keys, but moves the frost weapon's home from the Castle to the Forest |

*Recommend B:* it keeps "the forest is the first place you return to". Ben tests the shrine through
the lever.

**D3. The frost weapon: melee or ranged (MISSIONS_DESIGN §11.2).**

| Option | Cost |
|---|---|
| **A. Melee** (Spear capsule or Broadsword arc): swing at the water to freeze your way across | Data + a frost visual + an ability |
| B. Ranged (Beam ray): freeze from afar | Same cost; fire and ice share the ranged slot, so one run carries one element |
| C. One of each, later | Double the cost |

*Recommend A:* it pairs with the Flamethrower in one run and needs no new shape. Pick B if elements
should force separate runs.

**D4. Where to buy the double jump.**

| Option | Cost |
|---|---|
| **A. An "Abilities" panel in the lobby** (a key and a button), which becomes the Armory's second tab | One small screen |
| B. A walk-up stall in the lobby with a prompt | + a prop; still needs a panel |
| C. On the map's level card | Clutters the card |

*Recommend A,* at 10 Valor (one Normal clear).

## 10. Risks, said plainly

1. **The first run loses the double jump everywhere.** Hops over fodder, dodging lobs and the boss feel
   all change. There is no one-jump policy in `sim_range` yet. Ben should play camp A without it before
   the price is set.
2. **Client physics:** a cheater can double-jump without owning it. Only the rewards are safe (R2).
3. **The sniper gates move:** the cache, the creek and the pads are pinned. Every layout change re-pins
   `check_levels` and the L4 known-limit list in `sim_range`.
4. **Deep water adds a fall:** the creek bridge becomes an edge. The rescue is free, but the gap and the
   sneak path must keep clear of it.
5. **Party rules are L5:** the map is gated on the leader, so a guest's own cache does not open the
   arena for the party.
6. **Phones:** a held stream on auto-fire and a precise ledge jump are both unmeasured.
7. **Gate time:** `mutate.py` takes about 2 hours. Plan one full run per wave and filtered runs for
   fixes.
8. **Tight bosses:** a family that beats the Broadsword on the Colossus re-opens boss tuning.

## 11. Proposed waves (each playable alone in `proving.rbxl`)

**W1: the bought double jump and the lookout.**
- Ben sees: a first run with one jump; a Normal clear paying 10 Valor; buying Double Jump in the lobby;
  the lookout chest; the three secret icons on the map card.
- luau-engineer: the v7 step; the attribute; `RequestBuyAbility`; secret triggers and chests (a pure
  `SecretFlow`); per-player Rise; levers; harness checks.
- ui-engineer: the MovementController refusal; the Abilities panel; the chest cue; the card's secrets
  row; the Rise mirror in `castAbility`.
- economy-designer: the `abilities` config and price; chest contents; a one-jump policy in
  `sim_range`; `check_levels` for chests.

**W2: fire, the Flamethrower and the cave.**
- Ben sees: the lobby loadout picker; the Flamethrower (first Hard clear, or the lever); burning the
  bramble mouth; the cache chest opening the Raider Arena.
- luau-engineer: `element`; the reactive-block list; the `finish()` hook; `RequestSetFamily`; the
  `families` map; `requires.secret`.
- ui-engineer: the picker; the flame stream and ability effect; the burn cue; the map lock text.
- economy-designer: the Flamethrower's numbers (sim against both bosses); the cave layout; the
  re-pinned sniper sets.

**W3: ice, the frost weapon and the creek.**
- Ben sees: water you sink into; the frost weapon (lever) freezing a path; the island shrine paying
  out.
- luau-engineer: deep water and the rescue; ice sheets.
- ui-engineer: the frost visuals.
- economy-designer: the frost family and ability; the pond and island layout; the creek rules; the
  sniper pins.

W3 can start once W2's reactive-block list is merged. The lead owns `docs/INTERFACES.md` and the wiring
in combat `Main.server.luau` for the new remotes (the P2 lesson).
