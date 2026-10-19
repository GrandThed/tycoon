# L2 Wave 3 contract: ice, the frost hammer, deep water and the island shrine (draft for the lead, 2026-10-19)

Branch `l2-w3` in `C:\Users\benja\Desktop\tycoon-p5`. Decisions: `docs/MISSIONS_DESIGN.md` §22 (the frost weapon is a
melee frost hammer whose swings freeze the water ahead; built now, found later: a Studio lever until the Castle).
The W1 and W2 contracts (L2-1 to L2-48, their §10/§11 and every fix round) stay in force. Rulings here are
**L2-49 on**. Every number is a starting value its owner measures and may move inside the rule it serves.
**Three questions are for Ben (§11); the contract is written for the recommended answer of each.**

## What today's code gives us (checked 2026-10-19 on `l2-w3`, eba729a)

- **Weapons:** `ProvingGrounds.json` `weapons` (13 families + `flamethrower`); melee shapes are `arc` (Broadsword
  10/160°, Spinblade, Greataxe), `sphere` (Warhammer), `capsule` (Spear). `element` is already structural with the
  enum fire/ice (`Tuning.luau:53`, `:93`); `Types.Element = "fire" | "ice"`. A melee swing ends in `finish()` with
  `StrikeFx { shape, origin = the clamped claim (meleeOrigin :567), direction = flat heading, size = range,
  arcDegrees }` (`WeaponService.resolveMelee` :1096–1180), and `finish()` calls every strike listener outside
  `fx.abandoned` (:855–867). Main already wires `WeaponService.OnStrikeResolved(LevelService.React)`
  (`Main.server.luau:255`).
- **WorldReact.luau** (pure): `Segment`/`Touches` know `capsule` and `ray` only (:63, :94); `Need` reads
  `fireHits`/`iceHits` (:152; `iceHits` is a W2 placeholder nothing sets: `Combat.json:160` is
  `{fireHits 6, pad 0.5}`); `StrikeElement` gives no element to an ability strike (:194); `Apply` removes a block
  after `need` strikes (:212); `Wants` serves phone auto-fire (:341). `Strike` has no `arcDegrees` (:22).
- **LevelService:** `construct` (:304–398) tags every `react` block with `React`/`Heat` and lists it in `reactive`;
  `React` (:598–650) heats and destroys. `OnReacted` → `WaveService.onReacted` (:2106–2120) already maps
  `react == "ice"` to event `"frozen"`. Reactive state is per run (`Clear` :569).
- **Validate:** `StageFlow.reactProblems` (:958–1009) refuses a `react` block that does not collide (:1002–1004);
  `sim_range.react_problems` (:5423) mirrors it; `check_stage_mirror` compares both.
- **Keys:** `Unlocks.HoldsKey` (:233) holds `ice` once an owned family carries it; checked at the reward
  (`WaveService.tickSecrets` :2079). `UnlockService.GrantFamily`/`RemoveFamily` (:255, :268) and the levers
  `grantFamily`/`removeFamily` + `DebugGrantFamily`/`DebugRemoveFamily` take **any** non-starter id, notice
  `"<Name> is yours"` (`DebugService.luau:258`). **No server lever is missing for W3.**
- **Armory:** `ArmoryWeapons.HiddenWhere` (:107) lists only families a level's secret pays, and `Columns` (:130)
  hides every other unowned family, so today the hammer would never show. Theme already has the ICE word and chip
  colour (`Theme.luau:1364`, `:1409–1412`).
- **Phones:** `InputController.targetOnAuto` (:1402): the capsule branch falls through to `reactOnAuto` (:1353);
  the melee branch (:1424–1426) answers bodies only.
- **Abilities by id:** `AbilityService.MECHANICS` (:701–718; `dragonBreath` aliases `slugBurst` at :718),
  `InputController.busySecondsOf` (:1769–1785), `AbilityFx/init.luau` `BUILDERS` (:79–93),
  `sim_range.plan_ability` (:1176; `earthquake` branch :1197). `launchEarthquake` (:382) = rings round the
  caster's floor (`target = "floor"`), no lift, no dash.
- **The water today** (`Layouts/Levels/ForestRoad.json:283–285`): `Creek` 20×90 (x −410..−390, z −30..60, top −1),
  `Pond` 52×44 (x −426..−374, z 60..104, top −1), both **solid**; `Road2` (x −424..−340, z −8..8, top 0) is a
  bridge the creek runs under; `ShrineSignPad` (x −390..−380, z 8..18). The shrine is a 12×3×12 purple slab
  lying on the pond (`secrets` :363–373, bottom −1 = the pond's top), so with deep water it would float.
  `killY` −13; nothing lies under the roads (the void). Level file: `shrine` pays nothing
  (`Config/Levels/1_ForestRoad.json:12`).
- **The main path never touches water:** the route runs along Road2 over the creek; its one gap (Road1→Road2,
  x −436..−424) is over the void. **A one-jump first run is unchanged by deep water.**
- **Rescue:** `StageFlow.Rescue`/`IsOut` (:2581/:2550): below `killY` → `"level"` → `WaveService.rescueFallen`
  (:1146) moves the body to `StageFlow.SafePoint` (:2453): the latest quiet reached checkpoint, else the start.
  A fall into the pond after camp A is reached lands at A's checkpoint, ~250 studs away.
- **Tools:** check_levels drops non-colliding blocks from `solids` (:362). The creek rule (:1628–1643) demands
  solid water ≤ 1 under the road. `key_chain` (:1190) resolves an element only through a family a secret pays,
  so a shrine reward behind `ice` fails (e) today. Reach: `wall_reach_of` 49.3 (:482), `lift_routes(air=True)`
  (:1024), `air_carry` + `dashing_abilities` (:835–857). R8 pins `Creek` and `ShrineSignPad` (:113–121).
  `part_count` (:427) is held to `LevelGeometry.Pieces` by the harness. L2-39 (sim :4941–4954) already gates
  **every** family with an `element` against the default melee on both bosses.

## 1. The frost hammer family

**L2-49. `weapons.frostHammer`** (ProvingGrounds.json, economy-designer), one variant:
```json
"frostHammer": { "name": "Frost Hammer", "slot": "melee", "era": 1, "default": "A", "element": "ice",
  "variants": { "A": { "label": "Frost swing", "kind": "melee", "shape": "arc", "range": 9, "arcDegrees": 140,
    "pad": 1.5, "cap": 8, "damage": 36, "rate": 1.5, "knockback": 22, "launch": 6, "chain": [1.0, 1.0, 1.8] } },
  "ability": { "id": "frostQuake", "name": "Frost Quake", "cooldownSeconds": 12, "minCooldownSeconds": 5,
    "killRefundSeconds": 0.25, "damage": 50, "delaySeconds": 0.25, "count": 3, "radius": 8, "spacing": 6,
    "tickSeconds": 0.3, "falloff": 0.85, "pad": 1.0, "cap": 0, "knockback": 18, "launch": 8 } }
```
- **Arc, not sphere:** the water must freeze *ahead* (a sphere would freeze behind and to the sides too).
- Single DPS 36 × 1.27 × 1.5 ≈ 68 against the Broadsword's 76; crowd6 ≈ 410 against 456. Targets in sim
  `FAMILY_TARGETS.frostHammer = {"single": 68, "crowd6": 410}`. The finisher (64.8) is over `crowd.heavyHit` 40, so
  it breaks plates like the Broadsword's finisher (43); the first two swings are not heavy.
- **L2-50. Frost Quake is the Earthquake launcher:** `MECHANICS.frostQuake = MECHANICS.earthquake` (same entry),
  `frostQuake` joins `earthquake` in `busySecondsOf` and in `plan_ability`. No `height`, no `castRange`, not a
  `target = "dash"` row, so check_levels' lift and dash rules never field it. Its own visual
  `AbilityFx/FrostQuake.luau` (Earthquake's rings in the ice palette may be built on Earthquake's code).
- **Abilities never freeze** (`WorldReact.StrikeElement`, the W2 s-m2 rule): only the swings are a key.
- **Visuals (no sound):** an ice family's swing hitbox effect takes the ice colour, with a frost puff along the arc
  (`FrostFx.luau`, new; FeedbackController gains only the routing call, it is at 160 locals). Particles gate on
  `Theme.lowEndDevice`, never `reducedMotion`.

## 2. Owned only by the lever until the Castle

**L2-51. `Expeditions.json "found"`** (economy-designer): `{ "frostHammer": { "node": "castle", "text": "Found in
the Castle" } }`. Types: `ExpeditionsConfig.found: { [string]: { node: string, text: string } }?`. Nothing on the
server reads it: the family stays `locked` in `FamilyVerdict` until the lever writes it.
- **Armory (ui-engineer):** `HiddenWhere` becomes "where it is found": secrets give "Hidden on <level>", `found`
  gives its `text`; a `found` family shows locked with its text and the ICE chip. Rule as W2: an unowned family is
  listed only when one of the two names it.
- **check_levels (`check_map`):** each `found` family exists in `weapons`, is not a starter, is paid by no secret,
  names an existing map node, and its text is 1–40 characters. `key_chain` (e): a `found` family resolves at step 1
  with root `found:<node>`; the Valor cap for a chain whose root is not a sold ability is the dearest sold
  ability's price (10 today). The d-m2 "owned" set (starters + secret-paid) gains `found` families.

## 3. Freezing water

**L2-52. Deep water is a block with `react = "ice"` and `collide = false`.** Validate (both sides, check_stage_mirror):
`fire` must collide (today's line); `ice` must **not** collide (new line `"<where> is ice and collides"`); an ice
block opens nothing (`"<where> is ice and opens <id>"`). A deep water block without `react` is allowed (decorative).

**L2-53. Ice cells are pieces built with the level** (no Part is made mid-run):
- `levels.react.ice = { "cell": 7, "lift": 0.2, "thickness": 1, "reachDown": 6, "ahead": 4 }` (Combat.json;
  Types `CombatReactConfig.ice`). LevelService's `sizesOf` passes it as `Sizes.ice`; nil = no cells (the water is
  only deep).
- Pure `WorldReact.Cells(box, cell)`: the block's footprint divided evenly, `ceil(side / cell)` per axis.
  `LevelGeometry.Pieces` emits one piece per cell, **role `"ice"`**, name `Ice_<block>_<k>`, look `ice`,
  `collide = false`, box = the cell's footprint, top at the water's top + `lift`, `thickness` deep. A cell whose
  **centre** lies under a colliding block or secret that reaches above the water's top (Road2, the island) gets no
  piece. check_levels `part_count` counts the same pieces (the harness holds the two equal).
- `LevelService.construct`: an ice piece is a Part with `Transparency` 1, CanCollide/CanQuery/CanTouch false,
  attribute `Ice = false`; listed in a per-run `ice` list `{ name, part, cell: { box, frozen } }`. Ice blocks carry
  no `React`/`Heat` and are not in `reactive` (ReactFx and `reactOnAuto` never see them).

**L2-54. What a swing freezes** (pure, harness-tested; both the server and the phone call it):
- `WorldReact.Chills(fx, box, reachDown, ahead): boolean`: true when `fx.shape == "arc"`, the cell's top lies
  between `fx.origin.Y − reachDown` and `fx.origin.Y`, and the cell's centre lies in the swing's sector in plan:
  flat distance from the origin ≤ `fx.size + ahead`, angle from the flat direction ≤ `arcDegrees / 2` (≥ 360 = any).
  Non-finite numbers are false. `Strike` gains `arcDegrees: number?`.
- `WorldReact.Freeze(cells, element, fx, reachDown, ahead): { number }`: with `element == "ice"`, every unfrozen
  cell `Chills` holds is set frozen; returns their indices, ascending. Any other element, or nil, changes nothing.
- `LevelService.React`: element `"fire"` runs W2's path unchanged; `"ice"` runs `Freeze`, and for each new cell
  sets the look's Transparency, CanCollide and CanQuery true (Default group: players stand on it, rays and the
  camera meet it as ground; the crowd never comes here), `Ice = true`, and fires `OnReacted({ name, react = "ice",
  box })`, which WaveService already broadcasts as `"frozen"`. One swing freezes about two rows (§9).
- **The ice stays until the run ends** (Ben's question 2) and is shared by the party (W2's R2). `Clear` resets it.
- "A hit on water" is exactly `Chills`: the swing reaches down over the edge by `reachDown` (bank 0 → water −1 is
  4 under a standing origin; ice −0.8 → 3.2), so a high jump's swing or a swing from the plateau freezes nothing.
- `iceHits` leaves `Types.CombatReactConfig`, `WorldReact.Rules` and `Need` (fire only); the harness case "ice takes
  iceHits" goes with it.

**L2-55. Phones.** In `targetOnAuto`'s melee branch: `local onBody, refused = enemyInReach(...)`; a body (taken or
refused) decides as today; with none, `iceOnAuto` swings when the held family's element is ice and `WorldReact.
Chills` holds for an unfrozen cell Part (`ReactFx.ForEachIce`, the Parts with `Ice == false`), with the strike
built as the server builds it (root, flat camera look, the variant's range and arc). A frozen cell never triggers.

**L2-56. Feel (ui-engineer):** on the local player's own ice swing, a predicted frost ghost (local, non-colliding,
translucent) on every unfrozen cell `Chills` names, from the press frame, replaced by the real Part when its
`Ice` turns true, gone after 0.5 s otherwise (`InputController.SetSwingHandler`, as W2's stream handler). On
`"frozen"`: a frost burst over the cell (ReactFx; particles gated on `Theme.lowEndDevice`).

## 4. Deep water and the rescue

**L2-57.** `Creek` and `Pond` become `collide = false, react = "ice"`. A fall goes through the water to `killY`
−13 and gets the free rescue (`IsOut`, unchanged).

**L2-58. Landing (lead's ruling, recommended).** A deep water block may carry `landing = { x, y, z }`. Pure
`StageFlow.Landing(plan, position, margin): Vector3?`: the landing of the first water whose footprint, grown by
`rescue.outside`, holds the position in plan; `Plan` carries `waters = { { rect, landing } }`. `rescueFallen` uses
it only for a `"level"` verdict outside a closed camp's `fight`/`breather`, else `SafePoint` as today. Validate:
`landing` only on an ice block, finite numbers. check_levels: it stands on solid ground at its height, outside every
camp, reachable from `start`. Without it, every slip off the ice sends the player back to his last checkpoint.

## 5. The creek, the pond and the island (plans for Ben; north up, x to the right, 1 char ≈ 4 studs, 1 row ≈ 12 studs)

```
TODAY: the water is solid; walk on it to the shrine (no key needed)
 x:   -480     -440      -400      -360
 z-30                    ~~~~~         RR    Road3 to Road4, the climb, camp A
 z -8  TTTTTT=====   ====~~~~~=========RR    TT Trailhead, Road1, gap 12, Road2 (the bridge)
 z  8  TTTTTT            ~~~~~SSS            SSS ShrineSignPad: "ISLAND SHRINE - needs ICE"
 z 24                    ~~~~~               ~ Creek, solid, top -1
 z 48                    ~~~~~
 z 60                ~~~~~~~~~~~~~~
 z 82                ~~~~~[$$$]~~~~          [$] the shrine slab, lying on the solid pond
 z104                ~~~~~~~~~~~~~~
```
```
OPTION A, recommended: "the frozen creek" (the creek leads south to a pond; the island is ~102 from any ground)
 z-30                    :::::         RR    : CreekUp, deep, no ice (passes under the bridge)
 z -8  TTTTTT=====   ====:::::=========RR
 z  8  TTTTTT            ~~~~~SSS     L      L landing on Road2 (-385, 0, 2): a fall comes back here
 z 24                    ~~~~~               ~ Creek, deep, freezes: 3 cells across, 13 down
 z 48                    ~~~~~
 z 72                    ~~~~~
 z 96             ~~~~~~~~~~~~~~~~~~         Pond, deep, 72 x 60, freezes: 11 x 9 cells
 z120             ~~~~~~~%%$%%~~~~~~         %$% ShrineIsland 16x16 (ground, top 0), the chest 6x4x6 on it
 z144             ~~~~~~~~~~~~~~~~~~
 z156  freeze ~112 studs from the sign pad: about 9 swings, 12-15 s; the ice stays for the run
```
```
OPTION B: "the lake" (one wide lake against the road's south edge; the island ~100 out)
 z -8  TTTTTT=====   ==========SSS=====RR
 z  8           ~~~~~~~~~~~~~~~~~~~~~~~~     a 110 x 130 lake: free choice of path, ~270 cells,
 z 48           ~~~~~~~~~~~~~~~~~~~~~~~~     and 110 studs of the road's edge falls into it
 z108           ~~~~~~~~~%%$%%~~~~~~~~~~
```
Recommendation **A**: it is the picture of record ("creek bend: freeze the water, cross to an island shrine"), a
readable lane, half the cells, and only 20 studs of road edge over water. B is a layout-only change.

**The layout (Option A, economy-designer; grey blocks, ForestRoad.json):**
- `CreekUp` (x −410..−390, z −30..8, top −1, deep, no `react`); `Creek` (x −410..−390, z 8..96, deep, ice, landing);
  `Pond` (x −436..−364, z 96..156, deep, ice, the same landing); the old `Pond`/`Creek` entries go.
- `ShrineIsland` (look `ground`, 16×4×16, top 0, centre (−400, 128)); `secrets.shrine` becomes a 6×4×6 chest on it
  (x −400, y 2, z 128). Sign and `ShrineSignPad` unchanged.
- Rule, not coordinates: the island's flat gap to every other standable top ≥ the worst means of §7 (g) + 15. The
  hand estimate of the worst is the Spear's air Impale Dash, ~79 (`air_carry` 49 + 30); Leap Smash with the double
  jump ~71. At (−400, 128) the nearest ground is the sign pad, 102 away. The designer may move the island or the pond
  within the rule.

## 6. The shrine chest

**L2-59. `secrets.shrine` = `{ "name": "Island Shrine", "valor": 6, "materials": 63 }`** (key `ice`): the biggest of
the three (lookout 3 Valor + 50 + the Flamethrower, cache 4 + 60). Bands: Valor 5–9 (under the cap of L2-51), Timber
inside `SECRET_MATERIAL_SHARE` (63 is the 30% top of today's stock; the designer reads the exact stock). No family.

## 7. check_levels and the simulator

**L2-60.**
- **Deep water (replaces `creek`, `EXPECTED.deepWater`):** every `water` block is non-colliding; `Creek` and `Pond`
  carry `react = "ice"`; every route sample over a water footprint stands on a solid top at the route's height (the
  bridge), and the water's top is ≥ 0.5 under it; water tops at one height; the creek rule's old line goes.
- **(g) Behind ice, dry variant** (water as built): the island's and chest's key tops are not in `reachable_solids`
  from `start` (jump, double jump, dash, grace); `lift_routes(..., air=True)` with every family's lift finds none;
  no dashing family's air carry (`air_carry` + `range`) reaches them; and the island's flat gap to every other
  standable top is ≥ the largest of those + `ICE_MARGIN` 15. (a) holds on the island, and (d)'s rule holds: the
  trigger's ground lies over the island only.
- **(h) Frozen variant** (each ice block standable at its top + `lift`): the island is reachable from `start`; the
  chest opens from the island; and a swing can always extend the ice: for every ice variant `cell ≤ (range + ahead −
  BODY_RADIUS) / 1.5` (two rows a swing), `reachDown ≥` (bank top + `ROOT_HEIGHT`) − water top, the open cells of
  the creek and pond form one 4-connected chain from a cell touching a bank on the route's side to a cell touching
  the island.
- **Landing (L2-58)** and the **origin chord** gate are unaffected otherwise; `part_count` + ice cells ≤
  `levels.maxParts` (about 114 + 1 + 133 ≈ 250 of 600).
- **R8:** `Creek` leaves `sniperSpots` and `sniperSpotsOpen`; the frozen variants pin the same lists plus `Creek`
  (rated before W3 and earning under the mission player); any other new name needs the lead's OK, never on Hard.
  `SNIPER_KNOWN_LIMIT_L4` unchanged.
- **sim_range:** the Validate mirror (ice and landing lines); deep water is no floor; `frostQuake` in `plan_ability`;
  `FAMILY_TARGETS.frostHammer`; the hammer + Longbow pair on Forest Road (§9); frozen-variant sniper rows.
- **Mutants (each red, with a control):** Creek solid again (deep water); the island 70 from the sign pad (g, jumps);
  the island 85 away (g, the Spear's air dash, or whatever the designer measures as worst); `ice.cell` 12 (h);
  a gap in the cell chain (h); `found` naming no node (map); the shrine paying 10 Valor (e); a landing over the
  void (landing); an ice block that collides and a fire block that does not (Validate, mirror case too).

## 8. Studio levers (both entry points; inert outside Studio and in the range)

**L2-61.** No server change: `RequestDebug("grantFamily" | "removeFamily", "frostHammer")` and the attributes
`DebugGrantFamily` / `DebugRemoveFamily` already work for any family. Client (ui-engineer): Studio key **I** toggles
the first family by id whose element is ice (as F does for fire; the camera is Scriptable, so the default I zoom is
inert); the DebugPanel gains "Frost Hammer: ON/off (I)"; `DEBUG_HINT` adds "I frost hammer". **H** already resets
secrets (the shrine included); the ice resets with every run.

## 9. Balance (economy-designer, `docs/BALANCE.md` "L2 W3")

- **Family rows:** single and crowd6 inside `FAMILY_TOLERANCE` of L2-49's targets; Frost Quake's burst 3–5 s of crowd
  DPS, busy, floor and the effective-cooldown share.
- **Bosses:** L2-39 (already generic: never faster than the Broadsword's slowest seed, ≤ 150 s, no hit taken), with
  and without Frost Quake; the hammer meets every melee family's gates (siege share 35–55% on the Warlord, the plate
  within `PLATE_COMBOS`). **These are tight:** any hammer number change re-runs the boss rows.
- **Forest Road, Frost Hammer + Longbow, Normal 2/2** (the pair player): clear 4.0–5.75 min, 0 downs, cash a minute
  ≤ 1.10 × the Broadsword + Longbow pair, its Colossus ≥ 0.90 of that run's.
- **The crossing:** with cell 7, range 9 and ahead 4 a swing from the ice's edge freezes two rows (~13.5 studs):
  ~9 swings and 12–15 s from the sign pad to the island. Report the numbers; the lead's band is 8–20 s.
- **The chest:** L2-59 in its bands; report its share of a first clear.

## 10. Owners (disjoint; the gates run after all three)

- **luau-engineer:** `src/shared/Types.luau` (found, ice config, landing, `iceHits` out), `WorldReact.luau` (Cells,
  Chills, Freeze, `arcDegrees`, Need fire-only); in `src/combat/server/Services/`: `LevelGeometry.luau` (ice pieces,
  `Sizes.ice`), `LevelService.luau` (sizesOf, the ice list, React's ice branch), `StageFlow.luau` (Validate lines,
  `Plan.waters`, `Landing`), `WaveService.luau` (rescue landing only), `AbilityService.luau` (alias);
  `WeaponService.luau` only if the listener type needs it; `tools/crowd_harness/**` (new `tests_l2w3.luau`: Cells'
  division and the covered centre, Pieces' ice pieces and count on ForestRoad, Chills at each edge (radius, angle,
  band top and bottom, 360, non-arc shapes, non-finite), Freeze (ice only, frozen skipped, ascending, an ability
  strike freezes nothing through StrikeElement), Validate's new refusals, Landing in/out/margin; W1/W2 cases that
  name the shrine's empty reward or `iceHits` re-aimed; mutate entries), `tools/check_stage_mirror.py`. Done:
  harness and check_stage_mirror green on the designer's data, `check_compile` passes, and the report confirms that a
  swing on the road outside every camp reaches `finish()` (so the listener runs) and that no require cycle appears.
- **ui-engineer:** `src/combat/client/**` (new `FrostFx.luau`, `AbilityFx/FrostQuake.luau`; `ReactFx` ForEachIce,
  frozen burst, the predicted ghost; `InputController` alias, `iceOnAuto`, `SetSwingHandler`; `ArmoryWeapons` found
  hints; `CombatUIController` I key and hint; `DebugPanel`; FeedbackController routing only), `src/client/UI/Theme.luau`
  (`COMBAT_FROST_*`, `REACT_ICE_*`). Must check: phone auto-swing at the creek's edge (fires on unfrozen water ahead,
  never on frozen cells, never past a resting body), walking along Road2's south edge does not swing at water beside
  the road unless the arc faces it, the Armory card (locked, ICE chip, "Found in the Castle") at the three screen
  sizes. Done: check_compile, stylua, selene, luau-lsp clean.
- **economy-designer:** `ProvingGrounds.json` (`weapons.frostHammer` only), `Expeditions.json` (look `ice`:
  material `Ice`, a pale blue colour, in `REQUIRED_LOOKS` and `COLOUR_LOOKS`; `found`), `Combat.json`
  (`levels.react.ice`), `Config/Levels/1_ForestRoad.json` (`secrets.shrine`), `Layouts/Levels/ForestRoad.json` (§5),
  `tools/check_levels.py`, `tools/check_levels_mutants.py`, `tools/sim_range.py`, `docs/BALANCE.md`. Done: §5, §7 and
  §9 in, every new rule red on its mutant, `check_levels` and `py -3.12 tools/sim_range.py --check` green.
- **Lead:** INTERFACES "# L2 W3 contracts". **No `Main.server.luau` change:** the W2 strike listener carries ice,
  no remote and no server lever is new. Then review in slices (server; client; data and tools), QA (as W2, `mutate`
  in the background, about 2 h, one full run, filtered runs for fixes), docs. Every agent: `git status`/`git diff`
  first, commit nothing, kill only its own PIDs, report to `docs/prompts/l2-w3-reports/<role>.md`.

## 11. Questions for Ben (ask with the §5 pictures)

1. **How a swing freezes.** *Patches* (each swing freezes the water just ahead; you freeze your way across) or
   *all at once* (one swing freezes the whole creek and pond). **Recommended: patches**, his own words "freeze your
   way across"; all at once makes the key a formality. (All at once = `Freeze` takes every open cell of a touched
   block; no other change.)
2. **How long ice lasts.** *For the run* or *melts ~30 s after it freezes*. **Recommended: for the run**: the way
   back is free and nothing punishes a slow player. (Melting adds `ice.meltSeconds`, a pure `Thaw` called from
   WaveService's tick, a `"melted"` event and cue, and an (h) line that the crossing beats the melt.)
3. **The shape.** *Option A, the frozen creek* or *Option B, the lake*. **Recommended: A.**

## 12. Risks

- **L2-62. Tight bosses:** the hammer is a new melee family in every boss gate; numbers move only with the boss rows.
- **L2-63. Falls:** Road2 crosses 20 studs of deep creek and the first run walks it; a slip is a rescue (with
  L2-58, back to the road in a second). Ben should see that the bridge reads as a bridge.
- **L2-64. Reach models:** the island's safety rests on check_levels' jump, lift and dash models (LIFT_MODEL,
  `air_carry`); `ICE_MARGIN` 15 is the slack. A new carrying ability later re-runs (g).
- **L2-65. Prediction:** the ghost shows on the press frame, the walkable cell one round trip later; a player who
  swings and steps at once on a slow link may fall. Studio only.
- **L2-66. Party keys:** a guest without an ice family can walk the leader's ice and still meets "Needs ICE" at the
  chest (keys are per player). One line to Ben.
- **L2-67. Built now, found later:** in the live game nobody can open the shrine until the Castle exists; the
  publish freeze holds anyway. A cheater's claimed origin can push his freeze ~4 studs further; ice is not loot.
- **L2-68. Phones:** auto-swing at water and the ice under touch movement are unmeasured; the Ice material's feel
  (no slide expected for a Humanoid) is a Studio check.
- Ask Ben at his look (not blocking): the hammer's feel, the crossing's length, the chest's pay.

## 13. Ben's answers and the lead's rulings (2026-10-19)

- **Patches per swing [Ben]** (freeze your way across), **ice lasts the whole run [Ben]**, **Option A, the creek
  into a pond [Ben]**. Option B and melting are dropped.
- Lead: accepted as written — L2-58 (a fall comes back to Road2 by the creek), the shrine pays 6 Valor + 63
  Timber (L2-59), Frost Quake on the Earthquake launcher (L2-50), Studio key I (L2-61), `iceHits` dropped.
- Lead, from the W2 lessons: every new world-object interaction must work on phones (auto-swing at unfrozen
  water ahead, the same pure rule as the server); frozen cells must not open any new sniper perch or ledge route
  (check_levels with the frozen layout, every lifting arc); frozen sheets are floor, not walls, for the
  shot-origin chord gate — say so in the report.

## 14. Lead's rulings after the build (2026-10-19)

- Accepted from the designer: Frost Hammer swing 38 dmg, 1.55/s, 120°; Frost Quake one ring (count 1, radius 32,
  damage 30). INTERFACES' L2-49/L2-50 numbers are superseded by the data.
- The crossing band (8–20 s) is judged at the human pace (9.0 s); the ideal 5.8 s is fine.
- **Queued for the fix round (known; reviewers need not re-find them):**
  - Q1: phone auto-swing at water uses a narrower cone than the swing (`controls.iceAutoDegrees` in config,
    e.g. 60), so walking along Road2's south half does not swing at the creek beside it; it can only remove
    swings.
  - Q2: frozen cells keep normal grip (CustomPhysicalProperties or a non-slippery material with the ice look):
    no sliding into the water.
  - Q3: any deep (non-colliding) water block may carry a `landing`, not only ice; CreekUp lands on Road2 by the
    creek, not SafePoint (Validate + mirror + check_levels).
  - Q4: the Frost Quake visual draws the configured ring count (one ring at radius 32).
