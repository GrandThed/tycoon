# L2 Wave 2 contract: fire, the Flamethrower, the cave and the shortcut (draft for the lead, 2026-10-18)

Branch `l2-w2` in `C:\Users\benja\Desktop\tycoon-p5`. Ben's decisions are in `docs/MISSIONS_DESIGN.md` §22; the W1
contract `docs/prompts/l2-w1-contract.md` (L2-1 to L2-28, §10, §11) and its fix rounds stay in force. W2 delivers:
the Flamethrower as a family, a lobby loadout picker, brambles that fire burns, the Raiders' Cache as a roofed cave,
and a shortcut that stays open once found. Rulings are numbered **L2-29** on. Every number is a starting value its
owner measures and may move within the rule it serves. **One question is for Ben: the cave's placement (§5).**

## What today's code gives us (checked 2026-10-18 on `l2-w2`, 805a6e2)

- **Profile v7 already holds what W2 saves** (`ProfileSchema.luau:14`, template :45–48): `families`, `shortcuts`.
  `SecretFlow.luau:199` writes `families[reward.family] = true` (the lookout pays `flamethrower`,
  `Config/Levels/1_ForestRoad.json:10`). Nothing ever sets a shortcut. `UnlockService.ResetSecrets` (:200–205)
  clears secrets and shortcuts, keeps families. **No schema step in W2.**
- **Weapons:** `ProvingGrounds.json` `weapons` :100–199, loadout `{broadsword, longbow}` :200. Only Beam is
  `continuous` (:186–187). `Tuning.luau` structural paths :45–52, shapes :77–80; there is no `element` anywhere.
- **`WeaponService` (2,865 lines, 94 top-level locals):** `resolveRanged` :1254–1439. The ranged origin is the
  crosshair line at the head's depth (`InputController.shotRay` :1071, server `aimAllowed` :492, `originPad` 6),
  so a capsule starts at the shooter. The arc/capsule branch (:1413–1438) cuts its reach at walls (`worldReach`
  :412–423) and hits everything inside up to `cap`, **but sets no `tick`** (only the ray branch does, :1389).
  `finish(player, weapon, variantKey, tally, fx, totals?, ability?)` :760–811 sees every resolved shape, knows the
  player and the family; `StrikeFx` (:204–219) has shape, origin, direction, size, width?, endPoint?.
  `SetFamily` :2447–2473 / `SetVariant` :2477–2492 check nothing but existence; `SetFamily` resends TuneState with
  the loadout (`tuneStateFor` :598), which the client already follows (`InputController` :2472–2483).
- **`AbilityService.MECHANICS`** :701–715; `launchSlugBurst` :510–531 fires `count` cones every `tickSeconds`
  from the muzzle. `sim_range.plan_ability` :1157–1281 raises on an unknown id (:1281). Client:
  `InputController.busySecondsOf` :1630–1645, `AbilityFx/init.luau` `BUILDERS` :79–93.
- **No family picker in missions.** Only RangeService's Studio `weapon` / `variant` commands call SetFamily (:370,
  :377). Remotes: `CombatRemotes.luau` (RequestBuyAbility :137–143, bucket `calls`).
- **Levels:** `LevelGeometry.Piece` (:41–55) and `LevelService.construct` (:276–355) make named Parts with no
  attributes or tags and keep no per-run list. `Build(layout, expeditions, rules)` :493–518, `Clear` :521–529.
  WaveService `startLevel` :1785 builds at :1852–1853 from a fixed layout; the leader is
  `ArenaService.LeaderUserId()` (:565–577). `StageFlow.Validate` never reads `blocks` or `route`.
- **The cache today:** solid 12×10×12 at (100, 13, −4) on the dead-end `CacheSpur` (block :299, cell :20) with
  `CacheSignPad` (:300, cell :21), between Main Camp and the clearing. Its cells are a leaf of the plateau region:
  both go together or neither (`Region.Problems`, `check_levels.py:2143–2186`).
- **Gates that move:** route band 900–1,100 (today 1,079, 21 to spare; `walk_route` reads only `layout.route`);
  R8 pinned `sniperSpots` (`check_levels.py:106–107`, equality 2325–2336) contain `Secret_cache`; sim
  `SNIPER_KNOWN_LIMIT_L4` (:6772) = LookoutLedge, Secret_lookout, Secret_cache; `fielded_lifts` (:773–776) reads
  the fixed loadout and `LIFT_KNOWN_LIMIT_W2` (:242) is True; (b)–(d) skip unsold keys and a sold key other than
  doubleJump fails (:988–992); `check_sneak` :3168–3256; `stray_reach` 46.6 (49.3 with the walk-off grace).
- **Two facts that shape the cave:** the crowd never raycasts, so **sight is distance only, through walls**; and
  roofed floors may be invisible to R8, since `standable_points` (:2045–2053) drops covered points.
- **Finding (not W2's to fix):** RoadAB1 ends at x −122 and RoadAB5 starts at −116, so the AB bend has a 6-stud
  gap a player hops (raiders walk round it; check_levels, the sneak and the sim all take the bend).

## 1. The Flamethrower family

**L2-29. `weapons.flamethrower`** (ProvingGrounds.json, economy-designer), one variant, house style of Shotgun and
Rifle (single-variant families exist; a B waits for Ben's taste):
```json
"flamethrower": { "name": "Flamethrower", "slot": "ranged", "era": 1, "default": "A", "element": "fire",
  "variants": { "A": { "label": "Flame stream", "kind": "ranged", "shape": "capsule", "range": 16, "width": 5,
    "pad": 0.8, "cap": 0, "damage": 5, "rate": 10, "knockback": 2, "launch": 0, "projectileSpeed": 0,
    "bloomMult": 0, "continuous": true } },
  "ability": { "id": "dragonBreath", "name": "Dragon's Breath", "cooldownSeconds": 10, "minCooldownSeconds": 4,
    "killRefundSeconds": 0.3, "damage": 30, "count": 4, "tickSeconds": 0.15, "range": 20, "arcDegrees": 50,
    "pad": 0.8, "cap": 0, "knockback": 24, "launch": 4 } }
```
- Targets (sim `FAMILY_TARGETS`): single ≈ 50, crowd6 ≈ 280 (Shotgun's band: a crowd weapon you must stand close
  to). **It must not beat the Broadsword on either boss** (L2-37). A 5-damage tick is never `heavyHit` (40): it
  cannot break a plate (the slam does, as for SMG and Beam).
- **`element`** is new on the family: `Types.RangeWeaponDef.element: ("fire" | "ice")?`; `Tuning` adds
  `weapons.*.element` to `STRUCTURAL_PATHS` and an enum check. Read by the reaction hook (L2-34) and by keys
  (L2-31) only. Elements stay keys first (§9): no burning enemies.
- **The stream ticks.** WeaponService's arc/capsule branch sets `tick = if variant.continuous then true else nil`
  as the ray branch does, so Feedback merges the numbers. Held fire is the existing continuous path
  (`wantsRangeAttack` :1325–1348; `rangeAttackCallsPerSecond` 40; the credit-based rate check).
- **`dragonBreath` reuses the Slug Burst launcher**: four flame cones in 0.45 s. Every place that chooses by
  ability id treats it as `slugBurst`: `MECHANICS.dragonBreath = MECHANICS.slugBurst` (same entry), the
  `slugBurst` branch of `busySecondsOf`, `plan_ability`'s `slugBurst` branch. Its own visual
  `AbilityFx/DragonBreath.luau`. Cones ignore walls, as Slug Burst's do; they do not burn brambles (L2-34).
- **Visuals (no sound):** `FlameFx.luau` (new, client) draws a held stream per shooter from the muzzle to the
  strike's `size` (the wall-cut reach): particles in a widening cone, a translucent tapered core on
  `Theme.lowEndDevice`. The local player's stream starts on the press frame from the input state (the P3.1
  lesson); others' from their strikes. FeedbackController gains only the routing call (it is at 166 locals).

## 2. Owning and choosing weapons

**L2-30. Owned = a starter or a written family.** Starters are the config `loadout` values (Broadsword, Longbow),
never written (L2-1). `Unlocks.OwnsFamily(families, id, starters): boolean`. In the range every family is owned
(RangePanel keeps its Studio commands).

**L2-31. Element keys.** `Unlocks.HasElement(families, weapons, starters, element)`: true when an owned family has
that `element`. `UnlockService.HoldsKey` asks abilities first, then elements, from the profile. So `fire` is held
once the lookout chest has paid the Flamethrower, **whatever the player carries that run**. Unknown words fail
closed.

**L2-32. `RequestSetFamily(slot, family, variant)`** (CombatRemotes, bucket `calls`): `args.n == 3`, slot
`"melee"`/`"ranged"`, family ≤ `Unlocks.MAX_FAMILY_LENGTH`, variant ≤ 8 bytes. Server
`UnlockService.OnSetFamily`, pure verdict `Unlocks.FamilyVerdict(state, weapons, starters, slot, family, variant,
gateOpen)` in order: `"unavailable"` (no profile), `"invalid"` (unknown family or variant, or its slot ≠ `slot`),
`"locked"` (not owned), `"busy"` (gate closed: the shop gate `WaveService.MayLeave`), else ok →
`WeaponService.SetFamily` + `SetVariant` (TuneState carries the loadout back). `ActionResult { action =
"setFamily", slotId = family, ok, reason }`; Types add `"setFamily"`. Ignored in the range.

**L2-33. The choice lives in session memory** (WeaponService already holds it). Recommendation: no save in W2.
L3's Armory designs the whole loadout shape once (20 tiers per weapon, start tiers), and saving `{family,
variant}` now would be reshaped there. Cost to say to Ben: back from the city, a player starts on Broadsword +
Longbow and re-picks. A lever that removes a held family puts that slot back on its starter.

**The panel (ui-engineer).** The lobby's Abilities panel becomes the **Armory** panel with two tabs, **Weapons**
and **Abilities** (MISSIONS_DESIGN §10 calls it the Armory screen). Same button slot on the HUD ("Armory [K]"),
so W1's ActionRows packing at 667×375, 640×360, 375×667 does not change; K and gamepad Y open it on the last tab;
LB/RB switch tabs; B or Esc close. Weapons tab: two columns (Melee, Ranged); each owned family a card (name, a
"FIRE" chip for an element, its variants as buttons when it has two), the held one marked; tapping sends the
intent and greys the card until the `setFamily` result (3 s at most). **The Flamethrower shows before it is
owned**, locked, "Hidden on Forest Road" (you see a secret before you reach it, §7); no other unowned family is
listed. SecretFx's family note becomes "Flamethrower is yours: equip it in the Armory (K)".

## 3. World reactions

**L2-34. Layout and rule.**
- A `blocks` entry may carry `react = "fire" | "ice"` and `opens = "<shortcutId>"` (Types `LevelBlock`).
  `StageFlow.Validate` (and the sim mirror): `react` is one of the two words and the block collides; `opens`
  names a `layout.shortcuts` id.
- `src/shared/WorldReact.luau` (new, pure, `--!strict`): `Touches(fx, box, pad): boolean` for `capsule` and
  `ray` (the segment origin → `endPoint` or origin + direction × size, against the box grown by width / 2 +
  pad); every other shape false in W2 (W3 adds the hammer's arc). `Heat(heat, need): (number, boolean)`.
- A colliding bramble stops `worldReach` at its face, so the stream's segment ends on it and touches it.
- `Combat.json levels.react = { "fireHits": 6, "pad": 0.5 }`: six ticks (0.6 s of flame) burn a bramble.

**L2-35. The server.**
- `LevelService` keeps a per-run list `{ name, part, box, react, heat, opens }` of the reactive pieces it built.
  `LevelService.React(player, weapon, fx, abilityId)`: the family's `element` (Tuning) must equal `react`, and
  `WorldReact.Touches` must hold; then `heat` goes up and the Part's attribute `Heat` (0–1) is set, which the
  client sees. At `fireHits` the Part is destroyed and `LevelService` fires `OnReacted({ name, react, box })`.
- `WeaponService.OnStrikeResolved(callback)` is a listener list called at the end of `finish()` with
  `(player, weapon, fx, abilityId?)`. The lead wires it to `LevelService.React` (§8). Empty
  `abandonProjectiles` finishes are skipped. A burn needs no "in play" rule (a bramble is not loot).
- WaveService registers on `OnReacted` and broadcasts CombatFx `{ kind = "react", event = "burnt", name,
  react, x, y, z, sx, sy, sz }` (Types `CombatFxReact`). Shared in a party: one burn opens it for all (R2).
- Reset per run: `LevelService.Clear` empties the list. The crowd is untouched (bramble and cave are not cells).

**ReactFx.luau (new, client):** embers and darkening while `Heat` rises; on `burnt`, a flash and a short-lived
local ghost that shrinks, smoke gated on `Theme.lowEndDevice`. No sound.

## 4. The shortcut: found, saved and applied

**L2-36.**
- `layout.shortcuts = [{ id = "cave", name = "Raiders' Tunnel", x, y, z, sx, sy, sz }]`: a trigger box at the
  cave's far end, inside the exit bramble. Validate: unique short ids, finite numbers.
- **Found:** in `tickSecrets` (the same live-phase, standing, fighting filter), a root inside a shortcut box
  (pure `SecretFlow.InShortcut(box, root)`) calls `UnlockService.FindShortcut(player, levelId, id)` → pure
  `SecretFlow.RecordShortcut(combat, levelId, id): boolean`, true when new. A new find: CombatFxSecret event
  `"shortcut"` to that player, whose card reads "SHORTCUT FOUND — Raiders' Tunnel stays open on runs you lead";
  a toast to the others. Once per run per player (`run.secretSeen`).
- **Applied by the leader's save, as for the map:** `startLevel` passes the leader's
  `combat.shortcuts[levelId]` to `LevelService.Build(layout, map, rules, open)`, and `LevelGeometry.Pieces`
  leaves out every block whose `opens` is in `open`. Whatever the leader has found, each player records their
  own; a guest's find opens the tunnel only on runs that guest leads (party rules are L5).
- The chest keeps its own key: a player without `fire` meets "Needs FIRE" at the cache even when the tunnel
  stands open.

## 5. The cave's placement (the one question for Ben)

On today's road, the walk is about 41 s of a 5-minute clear (825 road studs at `walkSpeed` 20), and a cave can
save at most a few seconds of walking anywhere. **A shortcut makes runs faster only if it skips a camp.** (Measured
on a scratch copy, `sim_range --levels-only --level forest`, Normal 2 / 2: Pickets cleared at 36–39 s, Main Camp at
161–191 s, clear 4.69–5.26 min. An exit past Main Camp would save about 2.5 min and leave a run that is mostly the
boss; not proposed, since Ben said "to Main Camp".)

```
TODAY  (north up, the road runs west to east, about 1 char = 10 studs)
                       LOOKOUT [$] (2x JUMP)
                       ledge, top 34
START ==Road1/2==+  Road4 ==climb== Road5 ==[ A PICKETS ]==AB1=+ +=AB5==[ B MAIN CAMP ]==BC1=+--+     +=BC5=GATEHOUSE=+
          creek ~|  Road3            +8     [   85x85    ]     | |      [  141x133    ]      :  |     |     (bent)    |
                ~+==+                                         AB2 AB4   (gap 6, hops)  CacheSpur  BC2   BC4     [ C CHIEF'S   ]
         pond ~[$] shrine (ICE)                                +AB3+                   [$]cache   +=BC3=+       [  CLEARING   ]
                                                                                       (FIRE)                   [  wall 64    ]
route 1,079 (band 900-1,100)                     the cache: a solid box on a dead-end spur, one jump up
```

```
OPTION 1, recommended: "the Pickets bypass" (the tunnel skips camp A)
    ####################### THE RIDGE: walls and roof, top 84, unclimbable #########################
    # t==================== RAIDERS' TUNNEL (roofed, 12 wide, floor 8) ======================t   #
    # t                     [$] Raiders' Cache in an alcove (needs FIRE)                       t   #
    # t step +8                                                                         bend t   #
    ##%#####  LOOKOUT [$]                                                                 ##%##
      bramble  ledge                                                                    bramble
START ...Road4 ==climb== Road5 ==[ A PICKETS ]==AB1=+ +=AB5==[ B MAIN CAMP ]==BC1=========+ ... C as today
                                 [   85x85    ]     | |       [  141x133    ]  (spur and old cache removed)
```

```
OPTION 2: "the bend cave" (the literal picture: a cave between A and Main Camp)
                                           ######## bramble cave, roofed, chest inside ########
START ... Road5 ==[ A PICKETS ]==AB1=%===t============================t===%=AB5==[ B MAIN CAMP ]== ... as today
                  [   85x85    ]       |  AB2  AB4  (the bend it skips) |
```

| | Option 1, the Pickets bypass | Option 2, the bend cave |
|---|---|---|
| Mouth | Road4's north edge (x −340..−328), floor 0, below the lookout: both chain secrets in one view | RoadAB1's north edge, just past A's east gate |
| Tunnel | north, under a ridge 16+ studs behind the ledge (the ledge keeps camera room); one step of +8; ~320 studs | ~110 studs north of the bend |
| Exit | a bent mouth onto RoadAB5 by Main Camp's west gate; second bramble | onto RoadAB5; second bramble |
| What a found tunnel saves | **camp A entirely**: about 25 s at Normal 2 / 2 (A falls 36–39 s into the run, 13 s of it walking), 30–35 s on Hard; forgoes A's 30 residents (about 7,300 cash, 5.5%, and 10 Timber) | about 5 s of walking, **less than hopping the bend's 6-stud gap today** |
| Walk length | about the same as the road it replaces (~350) | ~110 shorter |
| Cost | the ridge, the tunnel, the sight rules | small |

**Recommendation: Option 1.** Ben's words were "a hidden path skips ahead to Main Camp; once found, later runs are
faster"; only Option 1 makes later runs faster. Its mouth sits under the lookout, so the chain reads in one
glance (ledge → chest → bramble below). If Ben keeps the picture literally, Option 2 is cheap and the AB gap is
the next thing to close.

**The layout (Option 1, economy-designer; grey blocks):**
- Remove `CacheSpur` and `CacheSignPad` (blocks and region cells together) and the old chest site.
- Tunnel interior 12 wide × 14 high: a mouth leg north from Road4 (floor 0), the step of +8, a long leg west →
  east (interior z about −98..−86, so the ridge's south face stands ≥ 16 behind the ledge's back at z −66), an
  exit leg south with **one turn** within 12 studs of its mouth (the L1c gatehouse idea), out onto RoadAB5's
  north edge (x −116..−70). Brambles (look `bramble`, new colour look) fill both mouths flush, overlapping the
  walls by ≥ 0.5, `react = "fire"`, `opens = "cave"`.
- The cache chest (6×4×6) in an alcove off the long leg, its sign on Road4 beside the mouth ("RAIDERS' CACHE -
  needs FIRE"). The shortcut box in the exit leg.
- Walls and roof are `wall` look with tops ≥ 43 + 3 over every standable top within `stray_reach` 49.3 (the
  ledge at 34 → 80; 84 near it, 64 elsewhere is enough), so nothing stands on the ridge.
- The tunnel stays farther from every Pickets group than its sight radius (sight goes through walls; guard 30,
  patrol 24, fire 16 in `Combat.json`; the 2× wake chain is group to group): the nearest, fireN at z −26, would be about 60 away.
- Not a region cell (it would close a loop A–B, which `Region.Problems` refuses), so raiders never enter; a player
  chased into it is lost by them (the Wave 4 rule).

**L2-37. check_levels for both variants** ("closed": brambles stand; "open": blocks with `opens` removed):
- **(f) Behind fire:** in the closed variant, no tunnel floor and no point within the cache's trigger is reachable
  from `start` (one jump + double jump + dash, stray reach, every lifting arc stopped by the roof). In the open
  variant both are, along `layout.shortcutRoute` (a new polyline that leaves the main route on Road4 and rejoins
  it on RoadAB5): one jump, climbs ≤ 10, gaps ≤ 15, width ≥ 12, every point beyond every open-camp group's sight
  (the sneak rule). The main `route` is unchanged and keeps its band. Report the shortcut run's length.
- **(a)** the cache's trigger is met from the alcove floor (and its chest top), from nowhere outside.
  For a `fire` secret, (f) replaces (b)–(d), and `fire` stops failing as "a sold key with no reach rule" (:988–992).
- **(e) and the chain:** a reward on a `fire` secret is allowed once a family with `element = "fire"` is
  obtainable; every secret's key must be a sold ability or a family another secret pays whose key resolves first
  (doubleJump → lookout → flamethrower → cache), no cycles; the cache pays `valor` 2..9 and Timber in the chest band.
- **R8:** a point under a roof counts as standable when the headroom over it is ≥ the body height; a candidate spot
  whose eye has no plan-view line to any cell within 110 (walls block, reuse `sight_points`) is dropped. Re-pin
  `sniperSpots` for both variants (`Secret_cache` leaves). The exit's bend must leave no spot.
- **`fielded_lifts` = every family in `weapons`** (the lever can field any; L3 will sell more), and
  `LIFT_KNOWN_LIMIT_W2` goes. F1 + F2 already give 0 lookout routes; (c) also runs against the tunnel.
- Mutants: a 1-stud gap beside a bramble → (f) red; the ridge 60 high by the ledge → (f) red; the exit without its
  turn → R8 red; the tunnel 20 from fireN → sneak red; the cache paying 10 Valor → (e) red; `opens` naming nothing
  → Validate red; the lookout paying nothing → chain red; a control for each.

## 6. Studio levers (both entry points; inert outside Studio and in the range)

**L2-38.**
| Lever (`RequestDebug`) | Workspace attribute (Combat.json `debug`) | Effect |
|---|---|---|
| `grantFamily`, value an id | `grantFamilyAttribute`: `"DebugGrantFamily"` (string, consumed) | written to `families`; notice "Flamethrower is yours" |
| `removeFamily`, value an id | `removeFamilyAttribute`: `"DebugRemoveFamily"` (string, consumed) | cleared; a held one goes back to its starter |
| `resetSecrets` (W1) | `DebugResetSecrets` (W1) | unchanged: secrets **and shortcuts**; also forgets the run's shortcut finds; notice "(from the next run)" |

Studio key **F** toggles the Flamethrower for the caller (like J); **H** already resets secrets and shortcuts.
`DEBUG_HINT` and the DebugPanel ("Flamethrower on/off (F)") follow. Starters cannot be removed.

## 7. Balance (economy-designer, `docs/BALANCE.md` "L2 W2")

- **Family rows:** single and crowd6 inside FAMILY_TOLERANCE of L2-29's targets; the ability gates (burst 3–5 s,
  busy, floor).
- **L2-39. Bosses:** in the range, the Flamethrower's Colossus and Warlord kills (with and without Dragon's
  Breath) are **never faster than the Broadsword's** under the same policy (a new gate), within
  RANGED_KILL_SECONDS 150, no hit taken; the Warlord's plate breaks (by the slam).
- **Forest Road with Broadsword + Flamethrower** at Normal 2 / 2: clear inside 4.5–5.75 min, 0 downs for the
  reacting player, cash a minute ≤ 1.10 × the Broadsword + Longbow run, Colossus not shorter by over 10%.
- **The shortcut run** (open variant, the reacting player and the human): its clear, pay and cash a minute
  against the full run. Expect the clear about 25 s shorter (30–35 s on Hard). Gate: cash a minute ≤ 1.15 × the full
  run on Normal and Hard; past it, report to the lead (no camp change).
- **The cache chest:** 4 Valor, 60 Timber to start (28% of a first clear's 211, band 15–30%; under the 10-Valor
  price).
- `SNIPER_KNOWN_LIMIT_L4.normal` loses `Secret_cache`; any new Normal spot needs the lead's OK, never Hard.

## 8. Owners (disjoint; the gates run after all three)

- **luau-engineer:** `src/shared/Types.luau`, `Unlocks.luau` (OwnsFamily, HasElement, FamilyVerdict, starters),
  `WorldReact.luau` (new), `Tuning.luau` (element); in `src/combat/server/Services/`: `CombatRemotes.luau`,
  `UnlockService.luau` (OnSetFamily, FindShortcut, GrantFamily, RemoveFamily, HoldsKey), `SecretFlow.luau`
  (InShortcut, RecordShortcut), `WeaponService.luau` (capsule tick, OnStrikeResolved), `AbilityService.luau`
  (alias), `LevelService.luau`, `LevelGeometry.luau` (`open`, `react` on Piece), `StageFlow.luau` (Validate),
  `WaveService.luau` (open set, shortcut tick, react fx), `DebugService.luau`; `tools/crowd_harness/**` (new
  `tests_l2w2.luau`: every FamilyVerdict reason in order, OwnsFamily/HasElement, Touches at each edge and pad,
  Heat, InShortcut, RecordShortcut twice, Pieces with and without `open`, Validate on bad `react`/`opens`;
  mutate entries; `stage_mirror`) and `tools/check_stage_mirror.py`. Done: harness and check_stage_mirror green
  against the designer's data, `check_compile` passes (WaveService and WeaponService grow by calls only), and the
  report confirms TuneState reaches the client after OnSetFamily in a mission and that no require cycle appears.
- **ui-engineer:** `src/combat/client/**` (new `FlameFx.luau`, `ReactFx.luau`, `AbilityFx/DragonBreath.luau`,
  `UI/ArmoryPanel.luau` or the Abilities panel grown into it; `InputController` alias; `CombatUIController` K,
  `setFamily` results, F, `react` routing; `CombatHud` button text; `DebugPanel`; `SecretFx` texts and shortcut
  card; `CameraController` only if the tunnel needs it), `src/client/UI/Theme.luau`. Must check: the camera inside
  a 12 × 14 tunnel and at its bends (`clearDistance` must stop at the roof), phone auto-fire with a 16-stud stream
  (fires only with a target in range), the panel at the three screen sizes and on gamepad. Done: check_compile,
  stylua, selene, luau-lsp clean; report the camera finding.
- **economy-designer:** `src/shared/Config/ProvingGrounds.json` (`weapons.flamethrower` only),
  `Config/Expeditions.json` (look `bramble`), `Config/Combat.json` (`levels.react`, two `debug` attributes),
  `Config/Levels/1_ForestRoad.json` (`secrets.cache`), `src/shared/Layouts/Levels/ForestRoad.json` (§5),
  `tools/check_levels.py`, `tools/check_levels_mutants.py`, `tools/sim_range.py` (targets, alias, L2-39, forest
  loadout and shortcut runs, known limits, Validate mirror), `docs/BALANCE.md`. Done: §5, L2-37 and §7 in, every
  new rule red on its mutant, `check_levels` and `sim_range --check` green on 64-bit Python 3.12.
- **Lead:** INTERFACES "# L2 W2 contracts"; combat `Main.server.luau`:
  1. Handler `RequestSetFamily`: `if RangeService.IsActive() then return end; UnlockService.OnSetFamily(player,
     slot, family, variant)`.
  2. `WeaponService.OnStrikeResolved(LevelService.React)` after both are required, before the Init loop.
  Nothing changes in `runJoinSequence`. Then review in slices (server; client; data and tools), QA (as W1 §8,
  `mutate` in the background, about 2 h), docs. Every agent: `git status`/`git diff` first, commit nothing, kill
  only its own PIDs, report to `docs/prompts/l2-w2-reports/<role>.md`.

## 9. Risks, and what needs Ben

- **L2-40. For Ben: the cave's placement (§5).** Option 1 recommended. Ask with the two plans as pictures.
- **L2-41. Tight bosses.** L2-39 is the guard; any Flamethrower number change re-runs the boss rows.
- **L2-42. Sight through walls.** The crowd wakes by distance, so the tunnel's distance from the Pickets is the
  only thing that keeps it quiet; the sneak rule on `shortcutRoute` gates it.
- **L2-43. A covered nest.** Before the R8 change, check_levels could not see a sniper inside a roofed place. The
  exit's turn and the sight test close it; Hard stays without known limits.
- **L2-44. The camera in a roofed place** is new. If the boom pokes through the roof, the ui-engineer fixes it
  in CameraController (the L1c pattern).
- **L2-45. A leader without the tunnel** shuts it for the party; a guest's find counts on runs he leads. L5.
- **L2-46. Session-only loadout** (L2-33): one line to Ben.
- **L2-47. The AB bend can be hopped** (6 studs): reported, not changed in W2.
- **L2-48. Phones:** held fire on auto-fire at 16 studs and the bramble burn on touch are unmeasured.
- Ask Ben at his look (not blocking): the Flamethrower's feel, the burn time (0.6 s), the chest's pay.

## 10. Ben's answers and the lead's rulings (2026-10-18)

- **Cave: Option 1, the Pickets bypass [Ben].** Build §5 Option 1 (ridge, roofed tunnel, cache alcove, both
  bramble mouths, the old cache spur and sign pad removed). Option 2 is dropped.
- **Loadout: for this visit [Ben].** Session memory only, as §2 recommends; no profile change.
- **The bend gap (L2-47): close it now [Ben].** The designer makes the RoadAB1/RoadAB5 gap unhoppable (wider
  or walled) in this wave, with a check_levels rule and a mutant (a gap within `stray_reach` that lets a player
  skip the bend fails); route, sneak and sim stay green.
- **Accepted as written otherwise**, including one Flamethrower variant, Dragon's Breath on the Slug Burst
  launcher, ticks never heavy, six ticks to burn, the leader's save deciding the shortcut, cache chest 4 Valor +
  60 Timber, the Abilities panel grown into an "Armory" panel with Weapons and Abilities tabs.
- The lead does the two `Main.server.luau` wiring steps after the engineers report, and writes INTERFACES.

## 11. Lead's rulings on the designer's four questions (2026-10-18)

1. CaveMouth and CaveExit are accepted as new Normal sniper spots (both earn under the mission player on Normal
   and Hard); making the cave part of the raiders' region is rejected.
2. The Flamethrower-run bands are accepted: compare the Flamethrower pair with the Longbow pair; clear band
   4.0–5.75 min.
3. The cache sign stands on Road4 beside the mouth.
4. A shortcut found from the exit end (burn the exit bramble from RoadAB5 and step in) counts as found.
