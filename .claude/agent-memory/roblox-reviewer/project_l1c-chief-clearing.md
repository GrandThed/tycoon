---
name: l1c-chief-clearing-review
description: L1c walled Chief's Clearing reviews (2026-10-16) - data-tools 1C/0M/6m and code 1C/3M/3m, both Criticals the same camera-in-the-gate-mouth leak; hiding-things patterns (doorway, reset camera, BLOCKED over held bodies, gate countdown), 2D doorway probe, C geometry facts
metadata:
  type: project
---

L1c is a fix of L1 on branch `l1c-chief-clearing` in the worktree `tycoon-p5`.
- Camp C is walled: fence 64, tops at y 76.
- There is a one-turn gatehouse: GatehouseWalk, then GatehouseTurn into the north gate.
- The ambush is the held flank residents: `ambushW` and `ambushE` at z −22.5, 10/12/12 bodies.
- The waves are [empty, Colossus].
- `WallClip.Reach` clips the camera, and `WallClip.TooHigh` refuses ground points more than
  30 above the caster's floor.

The review was split into slices from `docs/prompts/l1c-review.md`. Findings are in
`docs/prompts/l1c-review/<slice>.md`.

**Several slice reviewers write this file at once. Never Write it whole: re-read it, then Edit
only your own section.** On 2026-10-16 the code reviewer overwrote the data-tools section. The
section below was rebuilt from `data-tools.md` and the index line.

**Why:** later levels will hide more things behind walls (castle, secrets). Each pattern here
generalises.

**How to apply:** for anything that must stay unseen, check the doorway, the dead-camera path,
the feedback words and the countdown before trusting a sight gate.

## Data-tools slice (rebuilt): 1 Critical, 0 Major, 6 Minor

**Critical.** `check_levels.py`'s doorway exemption applies to camera points whatever the root,
so the camera sits in the gate mouth with the root 9–15 studs back.
- The proof mutant is `exempt = doorway(px, pz) and what == "eye"`. It turns the gate red on the
  shipped data.
- The fix proposed: grow the camera clip by `levels.cameraClear` 3, and exempt eyes only.
- **The code slice's caveat:** the root "inside" test must keep the TRUE fenced rectangle. If it
  uses the grown one, a root within 3 studs releases the clip, and the boom can enter the camp
  through the gate.

**Minors:**
- **m1.** The 2-stud grid and `radius` overstate the margin. The true margin is +0.41, not +1.31,
  and the drawn torso half-diagonal is 1.151 r.
- **m2.** The maxAlive refusal in `check_stage_mirror` is also refused by "38 guards on 6 posts",
  so a two-sided mutant passes. Refusal-alike comparisons go vacuous when a second rule refuses
  first.
- **m3.** `lockedResidents` (8, 12) is not per difficulty.
- **m4.** The Floors shadow model ignores the gates and the boom's 5.5 studs.
- **m5.** The Hard and Brutal ambush bands start at 0.
- **m6.** The `check_levels` mutants have no driver in the repo.

**C geometry facts:**
- Only the corner square and leg 2 see the north gate.
- The void strip between WallS and the fence is closed by WallW.
- The east gate is unreachable: `TrailEnd` is 50.1 from GatehouseTurn against a `stray_reach`
  of 46.6.
- Cameras reach y 72.49 against the wall's 76.
- A post is visible through the opening only from an eye within 2.2 studs of the fence's outer
  face (fodder), or 2.83 (brute).

## Code slice: 1 Critical, 3 Major, 3 Minor

All gates were green: harness 2,423, `mutate "l1c:"` 16/16, compile, lsp, stylua, selene.

**Critical:** the same camera-in-the-gate-mouth leak, found independently.
- The boom (7–16 studs) carries the eye to an open gate's mouth whenever the player faces away
  from or across the gate.
- The frustum is ±52° wide (FOV 72 vertical, 16:9) and ±57° on a phone, so its side edges see
  in through the opening.
- At the default zoom, 5 studs before the trigger, 11% of the (x, yaw) samples show a post.
- Fix: a margin on the cut only (hold test on the true rectangle) of at least 3.5, which also
  covers shake (0.35 sideways), or a baffle inside the gate.

**Majors (patterns):**
- **Health 0 hands the view to the default Roblox camera.**
  - Reset Character is enabled (no `ResetButtonCallback`).
  - `CameraMaxZoomDistance` is the default 128.
  - A clear field keeps a solo run alive after a reset.
  - So a reset gives 8 s of free orbit over any wall.
- **AoE strikes (sphere, capsule, arc) have no world occlusion.**
  - A held resident answers `"blocked"`.
  - The caster then gets an AlwaysOnTop "BLOCKED ×N" over the hidden bodies.
  - TooHigh refuses only a point ON a wall top; ground beyond a wall is accepted.
- **A "stepping in shuts it" design meets the global `levels.gateSeconds` 3.** There is no
  per-stage override, and the HUD reads "Gates close in 3".

**Minors:**
- The clip is released on X/Z alone, but the trigger also needs `triggerHeight`, so the
  double-jump apex gives a free look.
- `GROUND_AIMED` re-types AbilityService's ground set.
- Studio B from the road fields the ambush and the Colossus together.

**Verified:**
- Leap Smash is a LinearVelocity mover, so walls stop it.
- Client and server `GroundPoint` use identical probes and params.
- `EndRun` calls `clearField` before the summary.

**2D doorway probe (no Studio):**
1. Model the walls as boxes, the fence band with its gap, and the posts as discs (fodder 1.3,
   brute 2.2).
2. Model the camera:
   - shoulder 1.75 to the right;
   - boom = zoom × cos(pitch) behind;
   - spherecast as walls grown by 0.5, minus pad 0.2;
   - then the Reach rectangle cut.
3. Visible means an unblocked segment within the half-FOV.
4. Scan root positions × yaw. 2D is enough when every wall is taller than the camera's top
   (about 72).

## Fix-diff review (2a58134..ef6fe6b): 0 Critical, 2 Major, 2 Minor

Gates green on a `git archive HEAD` copy: harness 2,455, check_levels, check_stage_mirror,
`mirror_mutants --only "L1c M3"` 5/5.

**Majors (patterns worth reusing):**
- **A height ceiling on "the root is inside" also fires for players already inside.** The m1 fix
  (release only within `triggerHeight` 30) made the grown clip collapse the camera into the head
  at the apex of every late double jump inside C during the fight. The root reaches 33, 36.5 off
  cover, 43 with a Leap Smash. The harness even asserts it. Proposed fix: the ceiling for a
  walled camp is its fence height (trigger and clip both), or latch "held" once inside.
- **A 0 s countdown meets the close's move rule.** The triggering root is always inside the fence
  band or the `closeInset` 2 strip, so `moveFighters` yanks it to `entry`, 10 studs ahead, every
  run. Whenever a countdown shrinks, check who the close's move catches.

**Minors:**
- The apex head-peek remains: no trigger above 30, and the head itself sits in the opening.
- Held bodies still take the strike cap and seed Storm Coil chain links; walls hide the bolts.

## Second fix-diff review (ef6fe6b..71fba13): 0 Critical, 0 Major, 3 Minor

F1–F4 fixed (walled-camp ceiling = fence top 64; gate-lane nudge via PivotTo + ForgetMotion, no `Placed`;
pure `StrikePick` passes held bodies). Patterns worth reusing:
- **Parallel agents break each other's mutant anchors.** The data agent's mutant text matched once when it
  ran; the code agent's new mirror function in the same file made it match twice, so `check_levels_mutants`
  was red at HEAD while both reports said PASS. Always run every mutant driver on the merged HEAD.
- **A lane-only nudge leaves the strip beside the opening.** A root first sampled in the inset strip beside
  the gate (diagonal dash, 20–60 Hz replication) is in no lane and still gets the entry yank. Clamp anything
  inside the fenced rectangle to `inner` instead.
- **Moving an entry next to the nudge line stacks co-op bodies** (road player placed feet+4 one stud from
  the nudged lane player).
- Verifying "identical non-held behaviour": check cap 0/NaN/∞/fractional, the `"gone"` verdict, the
  endPoint condition and push/order, each against the old loop.

See [[l1b-living-road-review]] and [[p5-missions-review]].
