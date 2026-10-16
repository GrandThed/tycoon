# L1c luau-engineer report (2026-10-16)

Worktree `C:\Users\benja\Desktop\tycoon-p5`, branch `l1c-chief-clearing`. Nothing is committed.

## What changed

- `src/shared/WallClip.luau` (new, pure, `--!strict`, no requires)
  - `export type Rect = { x: number, z: number, hx: number, hz: number }` (Types.CampRect's shape).
  - `WallClip.Reach(fromX, fromZ, dx, dz, rects: { Rect }, rootX, rootZ, pad): number`, exactly the
    contract's signature.
    - Returns the share 0..1 of the flat boom that stays outside every rect that does not hold the
      root, pulled back `pad` along the boom from the first edge it would cross.
    - Rects are closed, so a root on the edge counts as inside, as the trigger does.
    - A boom that starts inside such a rect gets 0.
    - A NaN or infinite boom or start gets 1 (the camera is left as it was).
    - A NaN root is held by no rect, so every rect cuts.
    - A NaN, infinite or negative-half rect is skipped.
    - A negative, NaN or infinite pad counts as no pad.
  - Added beyond the contract, for the §8 rule (reported, not a change to Reach):
    - `WallClip.Rise(movement): number` = `jumpHeight + doubleJumpHeight`.
    - `WallClip.TooHigh(floorY, targetY, rise): boolean` = `targetY - floorY > rise`.
    - Exactly `rise` above is allowed.
    - They are in a pure module so the harness can test the rule. The ui-engineer's
      `InputController.groundPoint` already calls the same two functions.
- `src/combat/server/Services/WeaponService.luau`: the §8 rule in `GroundPoint`, plus one require.
  - **Deviation from the brief:** `RangeService.GroundPoint` no longer exists. Since the P5 split,
    the server's ground point is `WeaponService.GroundPoint`; `AbilityService` calls it and
    `RangeService` has none. So the rule is there, and `RangeService.luau` is untouched.
- `src/shared/Types.luau`: `RunFloor.locks: boolean?`, with a comment.
- `src/combat/server/Services/WaveService.luau`: `locks = zone.locks` in `runFloors`. Nothing else.
  - The RunFloor rect is the floor. The client grows it by `levels.fenceThickness`, and the
    ui-engineer does.
- `tools/crowd_harness/run_harness.py`
  - Adds `WallClip` to SOURCES and `tests_l1c.luau` (last) to TESTS.
  - Updates the docstring.
- `tools/crowd_harness/tests_l1c.luau` (new)
  - Reach: inside and outside, the edge, the gate gap, the corner, slants, parallel booms, the
    pad, several rects, zero length, NaN, broken rects.
  - TooHigh and Rise, with the limit read from the ProvingGrounds fixture.
  - The shipped wall:
    - C's 2 gates and 6 fence pieces are solid and reach y 76.
    - There is no `Camp_C_Tent`.
    - The six gatehouse blocks are built as solid blocks.
    - The four walls have the wall look, reach at least y 76, and are refused as ground points.
  - The shipped plan:
    - Waves are [empty, Colossus].
    - C has 10 / 12 / 12 residents, all held guards, on both flanks.
    - No plated kind at any difficulty.
    - There are 2 waves, no tent stock, and the boss is in wave 2.
    - Wave 1 holds while an ambusher lives, clears on the tick the last one dies, then comes the
      breather and the Colossus.
- `tools/crowd_harness/tests_l1.luau`
  - "each wave fields a body or a boss": an empty wave is allowed only as wave 1 of a locking camp
    with residents (`zone.locks and zone.residents > 0`). The label says so.
  - The camp numbers by hand are relabelled as the 2026-10-13 copy. The arithmetic is unchanged.
- `tools/crowd_harness/tests_l1b_w2.luau`: `markers == 2`, labelled "A's and B's; L1c took C's".
- `tools/check_stage_mirror.py`
  - The refusal "the boss room's residents at its maxAlive" now uses `boss_room_full`.
  - That function raises `ambushW` until C holds exactly its stage's maxAlive on Normal (+32 fodder
    with the shipped data). That is the least that "not fewer than maxAlive" refuses.
- `tools/crowd_harness/mutate.py`: an `L1C_MUTATIONS` block, and `FILES.append(WALL_CLIP)`.
  - It has 16 entries: 14 on WallClip, StageFlow `held = camp.locks == true` → false, and
    LevelGeometry GateBoxes height capped at 6.

## The exact GroundPoint expression (server, `WeaponService.GroundPoint` step 4)

```lua
local casterFloor = floorBelow(root, params) or rootPosition.Y - standingOffset(root, humanoid)
local floorY = floorUnder(point, params) or casterFloor
if WallClip.TooHigh(casterFloor, floorY, WallClip.Rise(Tuning.Get().movement)) then
	return nil
end
return Vector3.new(point.X, floorY, point.Z)
```

- That is `floorY - casterFloor > movement.jumpHeight + movement.doubleJumpHeight` (30), and nil
  means refused.
- The fallback chain is the one it had before: target floor, else caster floor, else feet.
- The client is the same line for line (its `floorHit(root)` / `floorHit(point + LIFT)` / `Size.Y*HALF + HipHeight`).
- **Side effect for the lead:** `GroundPoint` serves every `target = "ground"` ability: Leap Smash,
  Blade Storm, Arrow Rain and Storm Coil.
  - Those four are now refused too when aimed at ground more than 30 above the caster's floor.
  - Refused means AbilityService sends `refused`, and no cooldown is spent.
  - Nothing a crowd body stands on is that high, so they lose nothing.
  - The client mirror only resolves the leap, so for the other three the client sends and the
    server refuses. Narrowing it to Leap Smash alone would take a flag on `GroundPoint` and a
    branch in AbilityService. Say if you want that.

## Gates (run 2026-10-16 on the designer's data as it stood in the worktree)

- `py tools/crowd_harness/run_harness.py . C:\Users\benja\Desktop\tycoon\tools\bin\luau.exe`:
  **HARNESS: PASS (2,423 checks)**. It was 2,361 before; `tests_l1c` adds about 60.
- `py tools/check_stage_mirror.py`: **CHECK: PASS**. The same was true earlier on my scratch copy of
  the contract's data.
- `py tools/crowd_harness/mutate.py . <luau.exe> "l1c:"`: **16 run, 0 not caught**.
  - The first run left one uncaught ("a broken box is judged"). A case was added for it, and that
  entry was re-run: caught.
  - About 3 min for all 16.
- `py tools/check_compile.py`: **PASS** (158 files).
- `stylua --check` and `selene` on WallClip, Types, WaveService and WeaponService: clean (0 / 0 / 0).
  The harness case files are not stylua-formatted, like their peers.
- `luau-lsp analyze` (sourcemap.combat.json, `tools/types/globalTypes.d.luau`) on the same four: no
  diagnostics.

## For other owners

- **economy-designer**
  - The contract says "five posts" per ambush spot, but Hard and Brutal put 6 bodies on each spot,
    and a guard spot needs one post per member. Your data already has 6 posts each; the contract
    text is stale there.
  - If C's data moves again, re-run the harness: `tests_l1c` reads the shipped layout and level
    (wall top = `camp.y + fence.height`, the gatehouse block names, 10/12/12).
- **lead**
  - The INTERFACES "# L1c contracts" should name `WeaponService.GroundPoint`, not
    `RangeService.GroundPoint`, and list `WallClip.Rise` and `WallClip.TooHigh` beside `Reach`.
  - `sourcemap.json` and `sourcemap.combat.json` show as modified in the worktree. I did not
    regenerate them.
  - The WaveService `locks` line and the call in WeaponService are wiring that the harness cannot
    load, so they were checked by reading only. The rule they call is WallClip's, which the harness
    tests and the mutants prove.
