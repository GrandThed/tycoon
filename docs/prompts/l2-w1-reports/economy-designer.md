# L2 W1: economy-designer report (2026-10-17)

## Files changed

- `src/shared/Config/Expeditions.json`: `abilities.list` (doubleJump, 10 Valor), look `secretOpen` (240, 190, 40)
- `src/shared/Config/Combat.json`: `levels.secretReach` 5 / `secretBelow` 1 / `secretAbove` 9; `debug.grantAbilityAttribute`
  "DebugGrantAbility", `removeAbilityAttribute` "DebugRemoveAbility", `resetSecretsAttribute` "DebugResetSecrets"
- `src/shared/Config/Levels/1_ForestRoad.json`: `secrets` (lookout 3 Valor, 50 Timber, flamethrower; cache and shrine
  name only)
- `src/shared/Layouts/Levels/ForestRoad.json`: **unchanged**. I did not build the L2-17 notch (see the finding below).
- `tools/check_levels.py`: L2-18 (a)–(e), the abilities and price gate, the secret numbers, the levers, `secretOpen`
  in the colour looks. The new switches are `LIFT_MODEL` and `LIFT_KNOWN_LIMIT_W2`.
- `tools/check_levels_mutants.py`: 25 new cases. There are now 66 data cases and 4 stage-mirror cases, all as expected.
- `tools/sim_range.py`:
  - an explicit `airJump: False` on every reacting policy;
  - `ThreatRun.take_off`, which counts any jump asked for in the air;
  - the first-run gate and the chest gate (`check_first_run`);
  - the Resolve mirror (`secrets`) and the Validate mirror (`secret_problems`, `SECRET_FAMILY_MAX` 24);
  - "owners only" labels on the sniper rows.
- `docs/BALANCE.md`: section "L2 W1".

## Gates (all green)

- `py tools/check_levels.py`: PASS, with 167 gates (158 before).
- `py tools/check_levels_mutants.py --luau C:/Users/benja/Desktop/tycoon/tools/bin/luau.exe`: PASS. Every L2 rule is
  red on its mutant, and every control is green.
- `py -3.12 tools/sim_range.py --check` (the 64-bit gate interpreter): PASS. The 32-bit run also passes.
- `py tools/sim_combat.py --check`: 23 of 23.
- `py tools/check_stage_mirror.py`: PASS against the luau-engineer's StageFlow as it stood at 17:30.

## Measured

- **First run** (the human, 0.55 s reaction, one jump, Normal 2 / 2): 4.23 / 4.25 / 4.31 min, 0 downs.
  - It takes 0 air jumps in all 114 forest runs.
  - A clear pays 211 Timber and 10 Valor, so **one solo Normal clear = 10 Valor = Double Jump**.
- **Chest**: 50 Timber is 24% of a clear (band 15–30%), plus 3 Valor.
- **Sniper re-pin**: none needed, because no layout changed.
  - `sniperSpots`, the perches and Parts (86) are unchanged.
  - The LookoutLedge row (×1.34) and the Secret_lookout row (×1.59) are now labelled "owners of doubleJump only".
  - R8 on Hard at 2 / 2 is unchanged. The thinnest margin is LookoutLedge at +1.6%; Road2 is at +3.0%.

## Constants changed, and why

- **The first-run band is 4.0–5.75 min, not the contract's 4.5–5.75** (`FOREST_FIRST_RUN_SECONDS`).
  - The human clears 0.2–0.5 min sooner than the reacting player, with the same kills and pay, because he dodges less.
  - Moving him into 4.5 would need a camp or weapon change, which the contract rules out.
- **The simulator now drops a timed jump that a knock's launch overtook.** Nobody jumps off the air without the double
  jump. Every number is identical to L1c fix 3.

## Finding: the L2-17 notch does not close the Leap route (lead decision)

`check_levels` (c) models every lifting ability worst case. Today that is the Greataxe's Leap Smash. It counts the
take-offs from which an arc of a player without Double Jump ends on the ledge:

| Lift model | Shipped ledge | With the contract's notch |
|---|---|---|
| Today | 937 | 429 |
| F1 only | 443 | 159 |
| F2 only | 653 | 258 |
| **F1 + F2** | **0** | **0** |

There are two holes, and no geometry closes either:
1. **Off a void.** Over a void, `GroundPoint` takes the caster's feet as his floor. A jump off Road4 or Road5 (with an air
   dash) therefore makes the ledge's top (34) a legal target.
2. **At the top of a jump.** `Leap` adds its height over an airborne root: 26 + 10 = 36. A sky-aimed cast past the walls is
   pulled back over the void behind them, where it is legal, and the arc crosses the open face onto the ledge.

**It is not a W1 risk.** No family that lifts can enter a level in W1 (`loadout` is Broadsword and Longbow). `check_levels`
reports this as a known limit until W2 (`LIFT_KNOWN_LIMIT_W2`). It goes red by itself if a lifting family reaches the
loadout.

**Formula changes I need, for the lead to route.** Both are needed: each alone leaves hundreds of routes.

- **F2: the caster's floor over a void.** The luau-engineer changes `WeaponService.GroundPoint`; the ui-engineer changes
  `InputController.groundPoint`:
  ```lua
  local casterFloor = floorBelow(root, params)
      or (rootPosition.Y - standingOffset(root, humanoid) - WallClip.Rise(Tuning.Get().movement, airJump))
  ```
  This means nobody targets ground above his own feet while over a void.
- **F1: the leap's apex.** The ui-engineer changes `MovementController.Leap`, which needs the caster's floor passed in
  from InputController:
  ```lua
  local apex = math.max(from.Y, to.Y + lift, casterFloor + standingOffset(rig) + lift)  -- lift = math.max(height, 0)
  ```
  Ground casts are unchanged. A cast at the top of a jump no longer adds `height` over the root.
- **Suggested home:** make both pure in `WallClip`, for example `CasterFloor(probed, feetY, rise)` and
  `LeapApex(fromY, toY, floorY, standing, height)`, with tests in `tests_l2`. Client and server would then share one rule.
- **When they land:** set `LIFT_MODEL = "floor"` in `tools/check_levels.py`. That is one line, and the mutants already pin
  their own model.
- **The margin after the change:** with F1 + F2 the lookout holds for a Leap height up to 18. The limit is camp A's fence top,
  12. The mutant at 20 is red.
- **If F1 + F2 are adopted, the notch adds nothing**, so I left the layout as it is. If the lead still wants the notch for its
  look, the walls pass (b): the mutant "unclimbable wall (84) on the east side" is green.

## For other owners

- **luau-engineer:**
  - F2 above.
  - `StageFlow.Resolve` must keep `secrets = file.secrets` on both branches. `sim_range.resolve_level` now mirrors it, and
    `check_stage_mirror` is green.
  - My Validate mirror copies `MAX_FAMILY_LENGTH` 24. If that number changes, tell me.
- **ui-engineer:** F1 and F2 above, in MovementController and InputController.
- **Lead / W2:**
  - W2's loadout picker must update `check_levels.fielded_lifts`, which today reads `ProvingGrounds.json loadout` only.
    Without that, the known-limit guard stops seeing families that enter a level through the profile.
  - A duo needs about two clears each for Double Jump (L2-24). This is unchanged and worth one line to Ben.
