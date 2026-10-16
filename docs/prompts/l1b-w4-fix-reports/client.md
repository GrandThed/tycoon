# L1b Wave 4 fix round — ui-engineer (R13)

## R13 — auto-fire never wakes a camp through a pierce

| Rule | Code |
|---|---|
| A ray shot or arrow does not fire while a refused body is on the crosshair line within the shot's hits. This includes the ruling's case, "first body on the line is refused". | `InputController.luau` `enemyInSights` (1102–1149), via the new pure `CampAim.ShotSpares(refusedEntry, takenEntries, pierce)` |
| A melee arc or a cone gun does not fire while any refused body is inside the padded shape. | `InputController.luau` `enemyInReach` (1178–1213): returns `found and not refused` |

- **What `enemyInSights` does now.** It makes one `CrowdRenderer.ForEach` pass, as before.
  - For every body it computes the entry along the crosshair ray (`shotRay`) out to `variant.range`, using `HitShapes.CrowdRay` with the variant's `width` and `pad`.
  - For a takeable body, the entry goes into a small list. For a refused body, only the nearest entry is kept.
  - The trigger itself is unchanged: a takeable body in the assist cone.
  - The shot fires only when `CampAim.ShotSpares` says it spends its `pierce` hits on takeable bodies before it reaches the nearest refused one.
- **What `ShotSpares` decides.**
  - It returns false whenever the refused body is first in line, so it covers the ruling as written.
  - It also covers the review's concrete case: a Longbow arrow passes through an A raider into a resting B fire member.
  - It reads `pierce` the way WeaponService's `pierceOf` does: `max(1, floor(pierce or 0))`.
  - A tie counts against the shot.
- **Lag pad for refused bodies.** A refused body gets `assistLagPad` on top of the variant pad. Holding the shot costs one frame; a wrong shot wakes a camp.
- **Melee and cones** use the same padded shape as the trigger (`autoSwingPad` + lag pad for melee, lag pad for cones). Any refused body in that shape holds the swing or the shot.
- **Deliberate shots are untouched.** Mouse, gamepad and a touch tap never ask this; only touch auto-fire does.
- **Top-level locals unchanged:** InputController 149, CrowdRenderer 154 (`check_compile --counts`). CampAim gained a field, not a local.

**A deviation from the ruling's wording.** I used `HitShapes.CrowdRay`, not `HitShapes.Ray`. CrowdRay is the shape the server's `rayCandidates` uses for hitscan rays and projectile segments: the upright body capsule plus the head sphere, built on `Ray`/`RayUpright`. A bare `Ray` against the body sphere would miss tall bodies' upper halves, which is the L1b-W2 headshot bug.

**Known limits (not fixed; for the lead):**
- **Arrows drop under gravity and split fans spread.** The test uses the straight crosshair line, and the extra lag pad only partly covers the drop. A Splitbow side arrow could still reach a refused body beside the line.
- **Mag Dump's buff pierce is unknown to the client.** A buffed SMG pierces more than `variant.pierce`.
- **The client ignores world geometry.** This errs toward holding the shot, which is safe.

## Test cases for luau-engineer B (`tools/crowd_harness/tests_l1b_w2.luau`)

Paste these inside the existing `do local Aim = load("CampAim") ... end` block, after the last `Takes` check:

```lua
	check(Aim.ShotSpares(nil, {}, 1), "CampAim R13: no refused body on the line, the shot fires")
	check(
		not Aim.ShotSpares(10, {}, 5),
		"CampAim R13: the first body on the line is refused, the shot holds"
	)
	check(
		Aim.ShotSpares(20, { 10 }, 1),
		"CampAim R13: a one-hit shot stops in the awake body before the refused one"
	)
	check(
		not Aim.ShotSpares(20, { 10 }, 5),
		"CampAim R13: a pierce through the awake raider into a resting member holds the shot"
	)
	check(
		Aim.ShotSpares(20, { 10, 12 }, 2),
		"CampAim R13: the shot spends its pierce on awake bodies before the refused one"
	)
	check(
		not Aim.ShotSpares(20, { 10, 30 }, 2),
		"CampAim R13: an awake body behind the refused one does not stop the shot"
	)
	check(
		not Aim.ShotSpares(10, { 10 }, 1),
		"CampAim R13: a tie between an awake and a refused body holds the shot"
	)
	check(
		Aim.ShotSpares(20, { 10 }, nil) and Aim.ShotSpares(20, { 10 }, 0),
		"CampAim R13: a missing or zero pierce is one hit"
	)
	check(
		Aim.ShotSpares(20, { 10, 12 }, 2.9),
		"CampAim R13: a fractional pierce is floored, as WeaponService's pierceOf"
	)
	check(
		not Aim.ShotSpares(10, {}, nil) and not Aim.ShotSpares(10, {}, 0),
		"CampAim R13: a missing or zero pierce still hits the refused body first in line"
	)
```

## Mutations for B (`tools/crowd_harness/mutate.py`, file `CAMP_AIM`)

I checked each one in scratch against the cases above with `luau.exe`. Every mutant fails at least one case, and the original passes all ten.

```python
W4_FIX_UI_MUTATIONS = {
    "l1b w4 fix ui: a refused body on the line is ignored": (
        CAMP_AIM,
        "if refusedEntry == nil then\n\t\treturn true",
        "if true then\n\t\treturn true",
    ),
    "l1b w4 fix ui: the shot ignores its pierce": (
        CAMP_AIM,
        "local hits = math.max(1, math.floor(pierce or 0))",
        "local hits = 1",
    ),
    "l1b w4 fix ui: a tie favours the shot": (
        CAMP_AIM,
        "if entry < refusedEntry then",
        "if entry <= refusedEntry then",
    ),
    "l1b w4 fix ui: awake bodies behind the refused one count": (
        CAMP_AIM,
        "if entry < refusedEntry then",
        "if true then",
    ),
    "l1b w4 fix ui: pierce is not floored": (
        CAMP_AIM,
        "math.max(1, math.floor(pierce or 0))",
        "math.max(1, pierce or 0)",
    ),
    "l1b w4 fix ui: a zero pierce hits nothing": (
        CAMP_AIM,
        "math.max(1, math.floor(pierce or 0))",
        "math.floor(pierce or 0)",
    ),
}
MUTATIONS.update(W4_FIX_UI_MUTATIONS)
```

**Not covered by any gate:** the wiring in `InputController` (`enemyInSights` feeding `ShotSpares`, and `enemyInReach`'s `refused` flag). The harness does not load client controllers, so a Studio look on touch is the only test.

## Verify

- `stylua --check src`: clean.
- `selene src/combat/client`: 0 errors, 0 warnings, 0 parse errors.
- `py tools/check_compile.py --counts`: `CHECK: PASS -- 157 files compile with Studio settings (-O1 -g2)`. CrowdRenderer 154, InputController 149.
- `luau-lsp analyze --definitions=tools/types/globalTypes.d.luau --sourcemap=sourcemap.combat.json src/combat/client`: exit 0, no diagnostics.
- Harness: `HARNESS: PASS (2,252 checks, C:\Users\benja\Desktop\tycoon-p5\tools\crowd_harness)`. B's new cases are not in it yet.

## Layout

Nothing on screen changed, so the 375 × 667 phone and 1920 × 1080 layouts are unaffected.

## In Studio (mobile emulator, touch auto-fire)

1. On RoadAB5, aim a Longbow along a line that passes an awake A raider and then a resting Main Camp fire member. Auto-fire holds and the camp stays asleep.
2. Turn so that only the awake raider is on the line. Auto-fire resumes.
3. With a melee weapon next to a resting group's member and an awake raider, auto-swing holds.

## For other owners

- luau-engineer B: the ten cases and six mutations above.

# Fix-diff round — ui-engineer (R17, R18)

Worktree `tycoon-p5b`, branch `l1b-wave4-fix`.

## R17 — a shot that bursts is held near a refused body

| Rule | Code |
|---|---|
| Launcher A (`splashRadius`) and Longbow A (`blastRadius`) are held when a refused body sphere lies within burst + sphere radius + variant `pad` + `assistLagPad` of the predicted stop span. | `InputController.luau` `enemyInSights`, via the new pure `CampAim.StopSpan` and `CampAim.BurstSpares` |
| The stop span. With enough takeable bodies on the line, it is the entry of the body that spends the hits, nearest first. With fewer bodies than hits, it runs from the last body passed (or the muzzle) to `variant.range`. The client knows neither the ground nor walls, so it assumes the shot may stop anywhere in that span. | `CampAim.StopSpan(takenEntries, pierce, range)`. It sorts `takenEntries` in place. |
| The distance test: a body is spared only beyond `reach` from every point of the span. A tie holds the shot, matching the server's `HitShapes.Sphere` `<=`. | `CampAim.BurstSpares(from, to, along, off, reach)` |

- **Which spheres are tested.** Both spheres of each refused body (body at height/2, head) go in as flat triples (along, off, reach). The nearer one decides.
- **The Longbow's blast always counts.** Auto-fire releases a bow at a full draw while the target holds, so the full-draw blast applies.
- **One shared expression.** `hitsOf(pierce)` is now one local helper used by `ShotSpares` and `StopSpan`, so each mutation text stays unique.
- **Added beyond the ruling (my own R13 gap; the lead may rule).** A hold used to read as "the target left".
  - A bow mid-draw then released its under-charged arrow at `>= minChargeFraction`, straight through the refused body the hold was guarding.
  - A held beam rode its `beamHoldUntil` buffer into the refused body.
  - **Fix:** `enemyInSights` and `enemyInReach` now set `rangeState.aimHeld`, meaning a takeable target was found but a refused body held the shot.
  - In `stepCharge`, an `aimHeld` draw does not release. It waits `tapBufferSeconds`, then drops.
  - In `wantsRangeAttack`, the beam buffer stops on `aimHeld`.

## R18 — no per-frame table

`enemyInSights` refills `rangeState.aimTaken` and `rangeState.aimRefused` (`table.clear`) instead of building a table each call. These are new fields in the `RangeState` type, not new top-level locals.

## Cases (`tools/crowd_harness/tests_l1b_w2.luau`, inside the CampAim block, after R13)

There are 15 cases labelled "CampAim R17: …":
- 6 for `StopSpan`: none on the line, one-hit shell, pierce sorted, pierce left over, zero pierce, fractional pierce.
- 9 for `BurstSpares`: beside the stop, on the line before it, beyond the burst, a tie at reach, a diagonal just outside, the middle of a passing span, behind the span's start, past the range beyond reach, past the range within reach.

## Mutations (`tools/crowd_harness/mutate.py`)

- **Re-aimed:** "l1b w4 fix ui: the shot ignores its pierce" now targets `"local hits = hitsOf(pierce)"` → `"local hits = 1"`, with the same label and rule.
- **New table:** `W4_FIX_UI_R17_MUTATIONS`, with 10 entries labelled "l1b w4 fix ui r17: …":
  - the stop ignores its pierce
  - the stop span is read unsorted
  - a shot with exactly its hits on the line flies on
  - a passing shot's span stops short of its range
  - a passing shot's span starts at the muzzle
  - a tie at the burst's reach favours the shot
  - the burst ignores the distance off the line
  - a body behind the span's start counts as inside it
  - a body past the span's end counts as inside it
  - a burst never holds the shot
- **Commit note:** luau-engineer A's commit 8341f8b committed the whole `mutate.py`, so these entries landed in A's commit. The `CampAim` texts they target land in mine.

## Verify

- `stylua --check src/combat/client`: clean.
- `selene src/combat/client`: 0 errors, 0 warnings, 0 parse errors.
- `py tools/check_compile.py --counts`: `CHECK: PASS -- 157 files compile with Studio settings (-O1 -g2)`. InputController is still at 149.
- `luau-lsp analyze --definitions=tools/types/globalTypes.d.luau --sourcemap=sourcemap.combat.json src/combat/client`: exit 0, no diagnostics.
- Harness: `HARNESS: PASS (2,361 checks, C:\Users\benja\Desktop\tycoon-p5b\tools\crowd_harness)`. This includes A's R16 work.
- Filtered `mutate.py … "l1b w4 fix ui"`: `MUTATIONS: 16 run, 0 not caught`. That is the 6 R13 entries, one of them re-aimed, plus the 10 new R17 entries.

## Known limits (unchanged from R13)

- **Straight line only.** The test uses the straight crosshair line: no arrow drop and no Splitbow fan.
- **No world geometry.** The client ignores walls and terrain. For a shot that does not stop in a body, it therefore holds over the whole rest of its line. This errs toward holding.
- **Gate coverage.** The `InputController` wiring (`aimTaken`, `aimRefused`, `aimHeld`) is not covered by any gate. The touch emulator is the test.

## Layout

Nothing on screen changed, so the 375 × 667 and 1920 × 1080 layouts are unaffected.

## In Studio (mobile emulator, touch auto-fire)

1. **Launcher A:** an awake raider stands within about 10 studs of a resting group member. Auto-fire holds and the camp stays asleep. Step away until the raider is clear of the member by more than about 12 studs: auto-fire resumes.
2. **Longbow A:** the same setup at 5 studs. The draw starts and is dropped after the tap buffer. No under-charged arrow flies.
