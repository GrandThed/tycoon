# L1c review: data and tools slice (2026-10-16)

**Scope.** `main..l1c-chief-clearing` at 2a58134. Files reviewed:
- data: `ForestRoad.json`, `1_ForestRoad.json`;
- tools: `check_levels.py`, `sim_range.py`, `check_stage_mirror.py`;
- harness: `tests_l1c.luau`, `tests_l1.luau`, `tests_l1b_w2.luau`;
- `docs/BALANCE.md` "L1c".

**Verdict: 1 Critical, 0 Major, 6 Minor.**

**Gates run read-only (nothing written in the worktree):**

| Gate | How | Result |
|---|---|---|
| `check_levels.py --no-plan` | worktree | PASS |
| harness | `git archive` snapshot in the scratchpad | PASS, 2,423 checks |
| `check_stage_mirror.py` | snapshot | PASS |
| `sim_range.py --levels-only --level forest --check` | `py -3.12` | PASS |

The full `py -3.12 tools/sim_range.py --check` also passes, with the same R8 row. The ±10%
run-order swing that BALANCE warns about does not move the gate's own order.

The sim run reproduces the designer's numbers exactly:
- Normal clears in 4.86–5.27 min.
- The ambush takes 20.4 / 22.2 / 21.7 s on Normal, 26.4–26.7 s on Hard and on Brutal.
- On the Hard 2 / 2 R8 row, the mission pays 19,063 and the LookoutLedge sniper 18,313.

All geometry below was worked out from the JSON. The probes are scratch scripts that import
`check_levels` and call its own `visible_arcs`, `walled_bodies` and `seg_hits_rect`.

## Critical

### C1. `tools/check_levels.py:2142` (`exempt = doorway(px, pz)`, `DOORWAY` at :180): the doorway exemption also covers camera points, wherever their root stands

**What the gate assumes.** A point within 2.5 studs of the fence, in a gate's lane, is exempt from
the sight rule, whether it is an eye or a camera. The lead accepted only the glimpse from a
**root** within about 2 studs of the trigger line ("one more step triggers the camp").

**What the client allows.** The client clip stops the boom 0.2 short of the fenced rectangle
(`CameraController.SetFloors`, :901, grows the floor by the fence only; `WallClip.Reach` uses pad
0.2). So the camera can sit in the gate's mouth while the root is 9–15 studs back in the corner
square:
- The boom goes back down leg 2 whenever the player faces between north-west and north-east.
- The open gate is `CanQuery` false, so the spherecast does not stop it.

**Failure, Normal at the default zoom of 11, on a 16:9 screen:**
- The root is at (313.5, −36.5), the south edge of the corner square, 9.5 studs before the trigger
  line. The player faces yaw −45° (toward the corner of WallE).
- The camera ends at (306.96, −27.48).
- The line to Normal's east brute at (353, −22.5) crosses z −27 at x 311.4 and z −26 at x 320.6,
  so it passes through the gate.
- The brute lies 51° off the look direction. The half field of view is 52.2° at 16:9 and 57.6° on
  a 19.5:9 phone. The whole brute (margin −2.2) is in frame at the right edge, and well inside the
  frame on a phone.

**At the maximum zoom of 16:**
- Roots up to 13 studs back see a whole brute.
- Roots up to 15 studs back still see a sliver.
- Facing −132° (looking back toward the road from the corner), a west brute shows at the left edge
  of a phone screen.

A player who turns to check behind him for B's chasers before the gate does exactly this. It breaks
requirement 1 well beyond the accepted doorway glimpse.

**Proof the gate is blind to it.** Mutating the line to `exempt = doorway(px, pz) and what == "eye"`
turns the gate red on the shipped data: the camera at (306, −28) sees Brutal's east brute at −1.64
and both innermost east fodder.

**Fix.** It touches the client and the tool together:
- **Client.** Grow the camera clip's rectangle by a doorway depth, a new Combat.json key such as
  `levels.cameraClear` = 3, in `CameraController.SetFloors`:
  `hx = floor.hx + wallClip.fence + clear`, and the same for `hz`. The "root inside" test uses the
  same grown rectangle. The camera then never comes within 3 studs of the fence unless the root
  does.
- **Tool.** In `check_walled`:
  - exempt eye points only;
  - drop camera points inside the grown rectangle unless their eye is inside it;
  - read the key from Combat.json.

**Verified by probe.** With a 3-stud grown clip:
- No root more than 3 studs before the trigger line frames any body, on a phone, at any yaw or zoom.
- The worst margin for any camera at z ≤ −30.2 is **+1.48**, even against the drawn torso corner
  (see m1).

## Minor

### m1. `tools/check_levels.py:2008–2151` and `docs/BALANCE.md:5077–5086`: "exact in plan" is a 2-stud grid against the radius

There are two gaps in what the gate measures.

**The grid.** Eye and camera points sit on a 2-stud grid, so the reported "tightest +1.31 at
(306, −30)" is a grid value.
- Sampled at 0.05 studs, outside the doorway band, the true minimum is **+0.41 to +0.48** at
  z −29.55, on the wall faces.
- It is +0.72 once the camera keeps its 0.7 stand-off from the walls.
- Between samples, the gate can pass a layout whose true margin is about −0.9.

**The radius.** The targets are `radius`, but `CrowdRenderer` draws a torso of 1.9 r × 1.3 r
(`TORSO_WIDTH` / `TORSO_DEPTH`). Its half-diagonal is 1.151 r, so a fodder's corner overhangs its
radius by about 0.2 studs.

**Today.** The margin is still positive, about +0.2 at the band's edge. After C1 it becomes +1.48.

**Fix.**
- Evaluate the camera region's extreme points exactly: the band's edge and the faces of the walls
  less the 0.7 stand-off. Or sample at 0.25 studs near the gates.
- Subtract `radius × 1.151`, read from CrowdRenderer the way Theme is read.
- Reword BALANCE ("exact in plan" → "a 2-stud grid; the true minimum is ...").

### m2. `tools/check_stage_mirror.py:202` (`boss_room_full`, used at :239): the maxAlive refusal is now refused for another reason

`boss_room_full` adds 32 fodder to `ambushW`, a guard spot with 6 posts. Python's `level_problems`
answers with four problems:
- "group C.ambushW holds 38 guards and has 6 posts";
- the maxAlive lines (Normal 42 against 42, Hard and Brutal already 44).

So both sides refuse even without the maxAlive rule, and "refused alike" compares booleans only.

**Two-sided mutant.** I removed the rule from both `StageFlow.luau:1235` and `sim_range.py:5640`
(`>= cap` → `>= cap + 999999`). `check_stage_mirror`: **CHECK: PASS**.
- The Luau line is still pinned, by message, in `tests_l1b.luau:271`. The harness fails on the
  Luau-only mutant.
- The Python line is now unpinned.
- The docstring's "the least that refuses" is also untrue on Hard and Brutal.

Before L1c this case was live: `chiefFire` was a fire spot and took any count.

**Fix.** Leave the groups alone and set C's stage `maxAlive` to Normal's resident count (10). That
refuses on maxAlive only, at every difficulty. Re-run the two-sided mutant to show it red.

### m3. `tools/check_levels.py:88`: `lockedResidents` (8, 12) at every difficulty

The comment says "8 to 10 on Normal by Ben's word", but the band lets Normal field 12 and still
pass.

**Fix.** Per-difficulty bands: `{"normal": (8, 10), "hard": (8, 12), "brutal": (8, 12)}`.

### m4. `tools/check_levels.py:2107–2108` ("Floors"): the shadow model ignores the gates and the boom's reach

**What it measures.** `inward = (wall_top − head) · d / (cam − wall_top)`, with `d` the surface's
gap to the fenced rectangle. That assumes the line passes over the wall's top at the fence.

**Where that is wrong.**
- Through a gate, the line clears only the gatehouse wall nearest the camera, then falls through
  the gap.
- The camera can also stand about 16 · cos 70° = 5.5 studs nearer than the surface's edge.

**Today.** It cannot bite. No outside surface near C tops the wall (RoadBC6 is 3.51 under), and a 3D
segment-against-box probe of ledges up to top 30 just north of WallN sees no ambusher.

**Later.** A future perch near a gatehouse, or a body in the gate's line such as the Colossus, would
pass this rule unseen.

**Fix.** For a surface whose camera tops the wall within reach + boom of any gatehouse wall,
measure `d` to the nearest tall wall, less 5.5, and compare it with that wall's distance to the
far side of the floor. Or refuse any such surface outright.

### m5. `tools/sim_range.py:5006`: `FOREST_AMBUSH_SECONDS` on Hard and Brutal has a lower bound of 0

If the ambush never happened, the empty wave 1 would clear at the close and read 0 s. That passes
the Hard and Brutal rows. Only Normal's 15 s floor would catch it, and that floor runs on the
same data.

**Fix.** A lower bound of 15 s on every difficulty. The measured values are 26.4 s and up.

### m6. `docs/BALANCE.md:5090`: the 12 check_levels mutants were run in memory, with no driver in the repo

This is the L1b W2 pattern again: nobody can re-run "every new rule red on a mutated copy".

**Fix.** Add a small driver (or a `check_levels.py --mutants` mode) that applies each JSON edit and
expects the named rule red. Add C1's "exempt eyes only" and m2's two-sided case to it.

## Verified, holds

- **Sealed in plan.** Every line into the north gate from outside must cross x 305.5 at
  z ≤ −36 (WallW's corner), so only the corner square and leg 2 look at the gate.
  - The corridor's west mouth (x 256, z −52…−36) cannot see the gate. A line from (256, −36) would
    have to run level or downward to clear WallS and WallW.
  - The void strip between WallS and the north fence (x 256…303.5, z −34…−27) is closed by WallW,
    whose face is flush with the fence's outer face at z −27.
  - The fence corners close: `LevelGeometry.FenceBoxes` runs north and south past the sides, the
    same as `fence_strips`.
- **The east gate.** It is open as built (`setGate` at the start), but nothing reaches it.
  `TrailEnd` is 50.1 studs from `GatehouseTurn` against a `stray_reach` of 46.6, and WallE and the
  fence stand between them.
- **Height.**
  - Every camera near C stays under the wall's top: 12 + 60.49 = 72.49 against 76.
  - The lookout's camera at 98.5 drops to a head only after 1,191 studs.
  - Two stacked players (+5) put a camera 1.5 over the top, but its line falls 0.5 a stud and cannot
    reach a body within the floor. Stacked players cannot climb either: 60 against 76.
- **Out of the passage's line.** Away from the doorway, nothing is seen from any eye in the corridor
  (fine grid, every difficulty, +0.41 at worst). The ambush hides as the contract says, except for
  the camera case in C1.
- **Leap Smash.** It cannot land on a wall top. Even with `floorBelow` nil (feet at most 42 over the
  void), 76 − 42 = 34 > 30.
- **The ambush data.**
  - Posts are spaced for the mix (fodder–fodder 3.5 ≥ 2.6, fodder–brute 4 ≥ 3.5, brute–brute 4.9 ≥
    4.4).
  - Brutes are on the outside, and the outermost posts clear the fence (257.1 > 256, 369.9 < 371).
  - Facing ∓98° matches atan2(−dx, −dz) toward the entry.
  - Bodies are 10 / 12 / 12, with no plated kind.
- **The pay.**
  - C's stock on Normal is 400 + 12,000 = 12,400, so the bonus is 1,240.
  - A clear pays 155,130 − 46,600 − 4,660 − 29,000 + 12,400 + 1,240 + 41,000 = **129,510**, as
    BALANCE says.
  - The Colossus stands 77.5 from the entry; the farthest spawn is 74.1.
- **`ambush_seconds`.** `r["camps"][0]` is C (only a gated stage makes a camp record), and wave 1's
  clear minus `closedAt` is the ambush.
- **The tests.**
  - `tests_l1.luau`'s exemption is narrowed to wave 1 of a locking camp with residents.
  - `tests_l1b_w2`'s `markers == 2` is right.
  - The new beside, band and unclimbable rules are sound for C: `GatehouseTurn` and `TrailEnd` are
    gate roads, and the unclimbable walls are the four gatehouse walls and C's fence strips.

## The list (as reported)

- **Critical C1.** `check_levels.py:2142`. The doorway exemption covers camera points whatever the
  root. The client clip lets the camera sit in the gate's mouth with the root 9–15 studs back. On
  Normal at default zoom, facing −45° from (313.5, −36.5), a whole east brute shows at the screen's
  edge, inside the frame on phones. Fix: grow the camera clip by `levels.cameraClear` 3 and exempt
  eyes only. Probe: no glimpse remains, and the margin is +1.48.
- **Minor m1.** `check_levels.py:2008–2151`. The 2-stud grid and the radius overstate the margin.
  It is +0.41 against the reported +1.31, and the drawn torso corner overhangs by 0.2. Fix: exact
  extremes, and `radius × 1.151`.
- **Minor m2.** `check_stage_mirror.py:202`. The maxAlive refusal is refused for "38 guards on 6
  posts", and a two-sided mutant passes. Fix: set C's `maxAlive` to 10 instead of adding bodies.
- **Minor m3.** `check_levels.py:88`. `lockedResidents` (8, 12) lets Normal reach 12. Fix:
  per-difficulty bands.
- **Minor m4.** `check_levels.py:2107`. The Floors shadow ignores the gates and the boom's 5.5
  studs. It is latent today. Fix: measure to the nearest tall wall.
- **Minor m5.** `sim_range.py:5006`. The Hard and Brutal ambush bands start at 0. Fix: 15 s floor.
- **Minor m6.** `BALANCE.md:5090`. The check_levels mutants have no driver in the repo.
