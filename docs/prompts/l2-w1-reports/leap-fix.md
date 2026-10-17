# L2 W1: leap fix report, F1 + F2 (2026-10-17)

The lead's ruling in contract §11. Nothing is committed. Branch `l2-secrets`, worktree `tycoon-p5`.

## Files changed

- `src/shared/WallClip.luau`: two new pure functions, `CasterFloor` (F2) and `LeapApex` (F1). The header comment says why.
- `src/combat/server/Services/WeaponService.luau`: `GroundPoint` now uses `WallClip.CasterFloor`.
- `src/combat/client/Controllers/InputController.luau`:
  - `groundPoint` uses `WallClip.CasterFloor`.
  - It now returns `(Vector3?, number)`: the target and the caster's floor it measured from.
  - `castAbility` passes that floor to `applyCast`, and `applyCast` passes it to `Leap`.
- `src/combat/client/Controllers/MovementController.luau`:
  - `Leap` takes a fourth argument, `casterFloor`.
  - The apex comes from `WallClip.LeapApex`.
  - New require: `WallClip`.
- `tools/crowd_harness/tests_l2.luau`: the group `L2.leapTests`, 18 checks.
- `tools/crowd_harness/mutate.py`: five entries labelled `l2 leap: …`, in `L2_MUTATIONS`. `WALL_CLIP` was already in `FILES`.
- `tools/check_levels.py`: `LIFT_MODEL = "floor"`. One line, nothing else.

**No server mirror of the leap arc exists.**
- The server never moves the caster. `AbilityService.launchLeapSmash` only strikes at `c.target` after `delaySeconds`.
- `sim_range.py` explodes at the ground point and has no arc.
- The only other arc is `check_levels.py`'s, which already models `"floor"`.

## Contracts (signatures)

```lua
-- F2: probed floor when there is one, else the feet less the caster's own rise.
function WallClip.CasterFloor(probed: number?, feetY: number, rise: number): number
	return if probed ~= nil then probed else feetY - rise
end

-- F1: root heights; lift = height when > 0, else 0 (NaN and negative heights lift nothing).
function WallClip.LeapApex(fromY: number, toY: number, floorY: number, standing: number, height: number): number
	local lift = if height > 0 then height else 0
	return math.max(fromY, toY + lift, floorY + standing + lift)
end

function MovementController.Leap(ground: Vector3, seconds: number, height: number, casterFloor: number): boolean
```

### Server: `WeaponService.GroundPoint`, step 4

```lua
local airJump = player:GetAttribute(Unlocks.Attribute(Unlocks.AIR_JUMP)) == true
local rise = WallClip.Rise(Tuning.Get().movement, airJump)
local casterFloor = WallClip.CasterFloor(
	floorBelow(root, params),
	rootPosition.Y - standingOffset(root, humanoid),
	rise
)
local floorY = floorUnder(point, params) or casterFloor
if WallClip.TooHigh(casterFloor, floorY, rise) then
	return nil
end
```

### Client: `InputController.groundPoint`, step 4

It is the same rule on the client's own numbers, and it also returns the floor:

```lua
local casterFloor = WallClip.CasterFloor(
	floorHit(root, params),
	root.Y - rig.root.Size.Y * HALF - rig.humanoid.HipHeight,
	rise
)
...
return Vector3.new(point.X, floorY, point.Z), casterFloor   -- (nil, casterFloor) when refused
```

### Client: `MovementController.Leap`

```lua
local standing = standingOffset(rig)
local to = ground + Vector3.new(0, standing, 0)
local apex = WallClip.LeapApex(from.Y, to.Y, casterFloor, standing, height)
```

A ground cast is unchanged.
- The root stands at `casterFloor + standing`, so the apex is `max(from.Y, to.Y) + lift`, as before.
- A harness case proves this over 4 floors × 5 targets × 4 heights.

## Assumptions and behaviour worth knowing

- **An owner's floor over a void is the feet less both jumps.** `Rise(movement, airJump)` follows the ruling's "the player's own rise", and an owner's rise includes the double jump.
  - At a single jump's top off a cliff, an owner therefore cannot yet target ground 26 above the cliff's foot.
  - At the top of his double jump he can, as from the road.
  - This is conservative and matches the ruling.
  - `check_levels` models non-owners only (`Rise(movement, false)`), so it is unaffected.
- **A NaN height now lifts nothing.** `LeapApex` uses `if height > 0 then height else 0` instead of `math.max(height, 0)`. Any positive height behaves the same as before.
- **`casterFloor` starts at 0 in `castAbility` for abilities that are not ground-aimed.** It is only read when `groundTarget ~= nil`, which means a ground-aimed cast that `groundPoint` resolved.

## Gates

- **Harness:** `py tools/crowd_harness/run_harness.py . C:\Users\benja\Desktop\tycoon\tools\bin\luau.exe` gives `HARNESS: PASS (2,586 checks)`.
- **Filtered mutations:** `mutate.py . <luau> "l2 leap"` gives `MUTATIONS: 5 run, 0 not caught`. The five mutations:
  - over a void the floor is the feet (F2 undone)
  - the probed floor is ignored
  - the height stacks on an airborne root (F1 undone)
  - the caster's floor never lifts the apex
  - a negative height lowers the apex
- **Stale texts:** 840 entries, 0 stale. Checked with a scratch script that runs `mutate.py`'s list and counts each text once per file.
- **`py tools/check_levels.py`:** `CHECK: PASS`.
  - L2-18c reports "no arc of a player without it ends on its ledge" under `LIFT_MODEL "floor"`.
  - So the lookout shows 0 leap routes without Double Jump.
- **`py tools/check_levels_mutants.py --luau C:/Users/benja/Desktop/tycoon/tools/bin/luau.exe`:** `MUTANTS: PASS`.
  - The L2-18c "today" mutant is red.
  - The "floor" control is green.
  - Height 18 is green; heights 20 and 24 are red.
- **`py tools/check_compile.py`:** PASS, 164 files.
- **`stylua --check`** on the four Luau sources: clean.
- **`selene`:** 0 errors, 0 warnings.
- **`luau-lsp analyze`** (committed definitions, `sourcemap.combat.json`): 0 diagnostics in `src/combat` or `src/shared`.
  - The sourcemap was regenerated with `rojo sourcemap combat.project.json` into scratch, and it is byte-identical to the committed one.
  - The only errors are the hub's own requires, which are expected under the combat map.

## What to check in Studio

1. (Leap Smash is the Greataxe's, which no level fields in W1: test in the range bench or with a Greataxe loadout.) Leap Smash from flat ground and up a step should feel as it did.
2. Leap Smash cast at the top of a jump should arc no higher than the jump itself, unless the target or the floor plus the leap height is higher.
3. Without Double Jump, jump off Road4 or Road5 toward the lookout and aim at the ledge. The cast should be refused (no leap, no cooldown).
4. With Double Jump (`DebugGrantAbility`), the same cast from the road should still reach the ledge.
