# L1b Wave 4 review — slice 3, client

Diff `main...l1b-wave4` at 2ec9da9, files under `src/combat/client` (`CampAim`, `InputController`,
`CrowdRenderer`, `CombatUIController`), read in full where they changed, plus `Region.luau`,
`CrowdBrain`'s `runway`/`inArena`, `WaveService`'s floors and RunState, `CombatHud`'s `engaged`
and key line, `CampFx` and the `resting` bit on the wire.

## What holds (checked, not assumed)

- **L1b-W4-32.** `CampAim.Takes(onCampFloor, resting, phase)` is the contract's three rules.
  `InputController.autoMayTake` feeds it `CampFloor(id) ~= nil`, `entity.resting` and the run
  phase. The root, `engaged` and `camps` are gone from it.
- **`resting` on the wire is `held or state == "rest"`** (`CrowdService.luau:1270`). So:
  - a homeward body is taken (checklist step 2, "shoot them as they walk home");
  - a stood-down rusher is taken (its group is in `fight`);
  - a dormant or held body is never taken.
- **Floors arrive before the client may act.** `applyFloors` runs in `onRunState` before
  `SetPhase`. The run leaves `lobby` only in a RunState that carries the floors. So a
  "floor not yet told" body (taken) cannot be shot at the run's start.
- **L1b-W4-33.** `laneReach` cuts with `Region.Runway` over the same list the server uses
  (`RunFloor.cells` = `zone.region.cells` = `CrowdFloor.region.cells`). It uses the same
  `from` rule as before and the kind's config radius, which is what `CrowdBrain.runway` uses
  (`CrowdBrain.luau:666`).
  - The extra `Region.Clamp` moves the decoded origin at most 1/64 stud. `Clamp` returns an
    exact inset edge, which `Inside` (edge + EPS) accepts.
  - No other client code bounds a body by its floor's rectangle. `floorY` reads only
    `centre.Y`, and every region cell is at 8.
- **`applyFloors` carrying `cells`.** It is needed (the owner's find): without it, -33 would do
  nothing. `sameCells` compares by value and is safe on equal lengths, because `ReadCells`
  returns dense lists.
- **Gates.**
  - `check_compile --counts`: PASS. CrowdRenderer 154 and InputController 149, both at the cap.
  - `luau-lsp analyze` on the four files plus Region: 0 errors.
  - `stylua --check` and `selene` on `src/combat/client`: clean.
  - `git diff main -- src/server src/client`: empty.
- **CampAim tests and mutations.** The new cases are in `tests_l1b_w2.luau:604-634`, and the
  four `l1b w4 ui:` mutations in `mutate.py:2699-2718`. The old six are listed as replaced.
- **The checklist, client side.**
  - `DEBUG_HINT` matches the checklist's keys.
  - "Pickets cleared" is a plain banner on the `cleared` event, with no distance gate, so it
    shows wherever the last raider died.
  - Nothing on the client says "BLOCKED" except from the server's `hit.blocked`.
  - The Server line is Wave 3's.
  - Nothing changed in layout. The key line shows only with a keyboard in Studio, so the
    667 × 375 phone layout is untouched.

## Findings

### Minor

1. **Touch auto-fire can wake a resting group of another camp with a shot it fired for an
   awake body.** Where: `src/combat/client/Controllers/InputController.luau:1098-1119`
   (`enemyInSights`) and `:1148-1168` (`enemyInReach`).
   - **The mechanism.**
     - The trigger is "a takeable body lies within `autoFireAssistDegrees` (5) + `assistLagPad`
       (1.5) of the crosshair line".
     - The shot is fired along the crosshair line itself (`shotRay`), and it pierces: Longbow
       A 5, Longbow B 3.
     - So the first body the arrow meets, or the next one along the line, can be a resting
       body that `CampAim` refuses as a target.
     - In Waves 1–2 the server answered such a hit from out of play with BLOCKED (L1b-7).
       Since L1b-W4-6, every hit lands and wakes.
   - **Concrete, on Forest Road.**
     - A's raiders may follow the player to Main Camp's west gate and into Main Camp
       (Ben's ruling).
     - The player stands on RoadAB5 at (−95, −44) with the crosshair on B.fire1's resting
       member at about (−55, −29): bearing 20.6°, 43 studs, outside the fire's sight of 16.
     - An A raider walks in at (−75, −37): bearing 19.3°, 1.3° off the line, so it triggers.
     - The arrow hits the A raider, pierces on into the B member, and Main Camp wakes. No
       touch of the player's chose that.
   - **Same camp: rarely matters.** The join-in (2 × sight) has usually woken the neighbours
     already.
   - **Why it matters.** The contract's promise "a phone still never wakes a camp by itself"
     (L1b-W4-32) holds only for the trigger, not for what the shot hits.
   - **Suggested fix:**
     - In `enemyInSights`, do not fire when the nearest body the crosshair ray actually meets
       within the weapon's range (`HitShapes.Ray` with the variant's width and pad) is one
       `autoMayTake` refuses.
     - In `enemyInReach`, do not swing or fire a cone when any refused body lies in the padded
       shape. That costs no top-level local: it is one extra test inside the existing
       `ForEach` callbacks.
   - Or rule it accepted for L1b and carry it to L4 (phones).

## For other slices (one line each)

- **run:** every 1 / `stateHz` RunState now sends `floors[i].cells` in full, and the same 15
  cells go out twice (A's floor and B's). That is about 30 four-number records per send, to
  every player, all run long, for data that never changes in a run. Send `cells` once (on the
  level's first RunState, or only when the floors change), or once per region instead of per
  floor. This is the "snapshot bytes" item in "Never measured".

Critical 0, Major 0, Minor 1
