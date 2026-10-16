# L1c ui-engineer report (2026-10-16)

Worktree `C:\Users\benja\Desktop\tycoon-p5`, branch `l1c-chief-clearing`. Nothing is committed.

## What changed

- `src/combat/client/Controllers/CameraController.luau` (L1c-5a)
  - New state lives in one table, `wallClip = { rects, fence }`. `fence` is read in Init from
    Combat.json `levels.fenceThickness`.
  - New `CameraController.SetFloors(floors: { Types.RunFloor })`. It keeps only the floors with
    `locks == true`, each grown by `fence` into its fenced rectangle (`{ x, z, hx, hz }`, which is
    `WallClip.Rect`). A floor list of `{}` (the lobby) empties the list, and so does Destroy.
  - New local `campReach(from, offset, root)` returns
    `|offset| * clamp01(WallClip.Reach(from.X, from.Z, offset.X, offset.Z, rects, root.X, root.Z, Theme.COMBAT_CAMERA_COLLISION_PAD))`,
    or the full length when there are no rects.
  - Both legs of the boom are clipped:
    - the shoulder: pivot to shoulder point;
    - the boom: shoulder point to camera.
  - Each leg is `math.min(spherecast reach, campReach)`. The root used for "inside" is the live
    local root.
  - I clipped the shoulder leg as well because the contract says the boom from the pivot never
    enters. In the open gate the shoulder (1.75 to the side) could otherwise start the boom inside
    the camp.
  - Nothing else in the camera changed. Top-level locals: 102 (cap about 180).
- `src/combat/client/Controllers/CombatUIController.luau` (`applyFloors` only)
  - Each floor now also copies `locks` (`true` or nil).
  - `locks` counts in the by-value comparison.
  - `CameraController.SetFloors(fresh)` is called right after `CrowdRenderer.SetFloors(fresh)`.
- `src/combat/client/Controllers/InputController.luau` (§8)
  - `groundPoint` now returns `Vector3?`. nil means refused.
  - `castAbility` resolves the Leap Smash target before sending. When the target is refused, the
    cast is never sent: no token, no cooldown prediction, no predicted leap. The press does
    nothing, exactly like a press on cooldown.
  - `applyCast` takes the resolved `leapTarget` instead of `rig` and `origin`.
  - The camera ray is now taken before `takeCastToken`. It is the same frame and `shotRay` does
    not depend on the slot, so the values are the same.

## The groundPoint expression (client)

```lua
local casterFloor = floorHit(root, params)
	or root.Y - rig.root.Size.Y * HALF - rig.humanoid.HipHeight
local floorY = floorHit(point + Vector3.new(0, GROUND_PROBE_LIFT, 0), params) or casterFloor
if WallClip.TooHigh(casterFloor, floorY, WallClip.Rise(Tuning.Get().movement)) then
	return nil
end
```

This is the same as the server's `WeaponService.GroundPoint` in the luau-engineer's diff. There,
`casterFloor = floorBelow(root, params) or rootPosition.Y - standingOffset(root, humanoid)` and
`floorY = floorUnder(point, params) or casterFloor`, with the same `WallClip.TooHigh(...)` line.
The probes match one for one: depth `HitShapes.GROUND_PROBE_DEPTH`, lift `GROUND_PROBE_LIFT`, and
the root probe from the root position. The limit is `jumpHeight + doubleJumpHeight` (30) from
ProvingGrounds.json `movement`, read through `WallClip.Rise`. It is never re-typed.

## Gates (my files)

- stylua, then `stylua --check`: clean.
- selene: 0 errors, 0 warnings.
- `py tools/check_compile.py`: PASS (158 files). Top-level locals: InputController 150,
  CameraController 102.
- `luau-lsp analyze --definitions=tools/types/globalTypes.d.luau`:
  - with `--sourcemap=sourcemap.combat.json`: clean (exit 0).
  - with `--sourcemap=sourcemap.json`: "Unknown require" only, on `script.Parent.Parent.UI`
    requires that existed before this change. The default project does not map the combat client,
    so the combat sourcemap is the right one for these files.
- I regenerated `sourcemap.json` and `sourcemap.combat.json` with rojo. They are tracked and now
  include `WallClip`.
- `rojo build combat.project.json` to scratch: OK.

## For other owners / the lead

- The contract says `RangeService.GroundPoint`. The real function is
  `WeaponService.GroundPoint`, and the luau-engineer edited that one. The rule is identical.
- The server rule lives in `GroundPoint`, so it also refuses **Blade Storm, Arrow Rain and Storm
  Coil** aimed at ground more than 30 above the caster's floor, not only Leap Smash.
  - The client computes `groundPoint` only for Leap Smash, as before.
  - For the other three abilities the client still sends the cast. The server refuses it and its
  RangeAbility state rolls the prediction back, which is today's refusal path.
  - If the lead wants the rule only for leaps, the luau-engineer should gate it on the mechanic in
    `AbilityService`. If the lead wants it for every ground ability, I can move the check into
    `castAbility` for every ground ability. Lead's call; nothing is needed for L1c.
- Sourcemaps were regenerated (see above). The lead regenerates them again at the merge anyway.

## What Ben must check in Studio (`build/proving.rbxl`, Forest Road, Normal)

1. Walk the gatehouse to the Chief's Clearing. In leg 2, the last 10 studs before the north gate,
   turn the camera all the way round on the mouse, and zoom fully out with the wheel.
   - The camera must never show the inside of the clearing.
   - Swung toward the gate, it stops at the gate line instead of passing through the open gate.
2. Same as step 1 at the lowest pitch (camera high, looking down) and with right-drag on a phone in
   the emulator (iPhone SE landscape). The touch camera uses the same clip.
3. Step through the gate. Once the root is in the gate's opening the camera is free again and
   behaves as before.
4. Inside the clearing, back against the tall inner wall and swing the camera into it. The boom
   pulls in close; this is the expected effect of a 64-stud wall (contract §7).
5. With a Leap Smash weapon:
   - aim over a tall gatehouse wall from about 30 studs away: Q does nothing (no cooldown, no
     leap);
   - aim at ordinary ground or a low ledge: it leaps as before.
6. On a phone the ability button behaves the same way: a refused leap does nothing and leaves the
   cooldown ring untouched.

No UI layout changed, so 375x667 and 1920x1080 are unaffected.

## Ruling applied (lead, 2026-10-16)

- The height rule now covers **every ground-aimed ability**, as on the server.
  - `InputController` has a new constant, `GROUND_AIMED = { leapSmash, bladeStorm, arrowRain, stormCoil }`. It is the same set as AbilityService's `target = "ground"`.
  - `castAbility` resolves `groundPoint` for all four before anything is spent.
  - When the point is refused, the press does nothing: no token is spent, no cooldown is predicted and nothing is sent.
  - `applyCast`'s parameter is renamed `groundTarget`. Only the leap uses it, as before.
- Studio step 5 now covers all four abilities. Aimed over a tall gatehouse wall from about 30 studs, Q/E should do nothing, and the cooldown ring should stay as it was.
- Gates, re-run after the change:
  - stylua and selene are clean.
  - `check_compile` passes: 158 files, and InputController has 151 top-level locals.
  - `luau-lsp` with the combat sourcemap is clean (exit 0).
