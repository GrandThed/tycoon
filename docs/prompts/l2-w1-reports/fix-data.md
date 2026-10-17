# L2 W1 fix round: data agent report (2026-10-17)

Branch `l2-secrets` in `C:\Users\benja\Desktop\tycoon-p5`. Nothing is committed. I killed only my own processes.

## Files changed

- `src/shared/Config/Combat.json`: `levels.secretReach` 5 -> **2.5**. `secretBelow` 1 and `secretAbove` 9 are unchanged.
- `tools/check_levels.py`
  - New `TRIGGER_MODEL` switch: `"footprint"` ships; `"centre"` exists only for the mutant.
  - New `trigger_gap`, `secret_triggered`, `footprint_ring`, `standing_roots`, `trigger_tops` and `trigger_region`.
  - `secret_triggered` mirrors the server's `SecretFlow.Triggered` term for term: `dx = max(|x − cx| − sx/2, 0)`, the same for z, `dx² + dz² ≤ reach²`, and the band `−below ≤ y − floorY ≤ above`, all closed.
  - L2-18 (a) now runs for every secret, sold key or not. It requires a standable top where a standing root opens the chest. A body standing on a top lower than the collidable chest's top stays at least its radius (1) off the chest's side.
  - For a secret with a sold key, (a) also requires the point to be on its ledge or on the chest.
  - (d) uses the same footprint rule: no other top opens the chest, and all ground within the reach of the footprint lies over the ledge or an unclimbable wall.
  - `ABILITY_ID_MAX` is now read from `Unlocks.luau` (`MAX_ID_LENGTH`) and counted in bytes.
  - The docstring of `check_secret_reach` now says that every rule models one body (d1).
- `tools/check_levels_mutants.py`
  - Seven new data cases and one changed control (list below).
  - New `SIM_CASES` with a runner, `sim_case`. It runs `sim_range.py` from a temporary copy with one line swapped, and must see the check go red.
- `tools/sim_range.py`
  - d3: every jump press goes through `take_off`, which refuses a press in the air and counts it. This covers the timed press and the hop's press during a launch.
  - A timed press that a knock's launch overtook is still lost, as before. This is now judged by the new `jump_planned`: the launch began after he planned the jump.
  - `SECRET_FAMILY_MAX` is read from `Unlocks.luau` (`unlocks_cap("MAX_FAMILY_LENGTH")`) and counted in bytes.
- `docs/BALANCE.md`
  - d4: the 937-route table is labelled "before F1 + F2".
  - New section "L2 W1 fix round" with tables and reasoning.

## s1 + d2: the trigger from the footprint, and `secretReach` 2.5

Why 2.5:
- **The lower bound is the body's radius.** A body pressed against a chest has its root at least 1 off the face, so the reach must be more than 1. The case "secretReach 0.9" is red.
- **The margin:** 2.5 leaves 1.5 studs for a body side-on to the chest (arms) and for an Rthro rig.
- **The upper bound is the ledge** (4 studs from the chest to the front and back edges).
  - The ground within 2.5 of the lookout's 6 × 6 chest is x −288.5..−277.5, z −64.5..−53.5.
  - That lies inside the ledge (x −295..−271, z −66..−52), 1.5 inside both its front edge and its back edge.
  - Above 4, the ground within reach passes the front edge, over Road5, and (d) goes red. The shipped 5 did, which I checked before the change.

Where a standing root opens each chest (a 0.5-stud scan of every standable top):

| Secret | Opens from | Not from |
|---|---|---|
| The Lookout | LookoutLedge against the chest (3 over its foot); the chest's top (7) | Road5: 5 off on the flat and −23 (−5 at the top of a jump). Not from the sign pad or from A's fence (16 off) |
| Raiders' Cache | CacheSpur beside it (3 over its foot) | Its top (13 over, above `secretAbove` 9) |
| Island Shrine | The Pond beside it (3); its top (6) | — |

- I kept the band at 1 / 9. The cache now triggers from beside it. That is what the ruling asks for. Opening it from its top would need `secretAbove` at least 14, and W2 rebuilds the cache as a cave anyway.
- The server's harness (`tests_l2`) already tests the shipped numbers. Its "against the chest" and "the cache from beside" cases hold at 2.5.

## d3: the one-jump gate can fail

- I ran the reviewer's mutant: `can_jump = True` in the planner.
- The forest check went red: "forest, Normal: one jump (L2-20) ... asked for **1** jump(s) in the air". Before the fix it stayed green.
- The red comes from a single press in 78 Normal runs. The mutant is thin, but it is deterministic: the seeds are fixed. A full run takes about 5 minutes.
- The shipped runs do not move. The forest check's output is byte-identical to the baseline taken before any of my changes (first run 4.23 / 4.25 / 4.31 min; 0 air presses in every row). The full `sim_range.py --check` is identical before and after the cap change.

## c3: confirmation (no tool change; one caveat on the flat)

**The height is unchanged.**
- The client takes the grace jump only while the root is at or below the height where it left the floor.
- So the peak over the floor walked off is never above `jumpHeight`.
- Every vertical rule therefore holds:
  - the lookout's 1-stud margin at A's fence;
  - `climb_max`;
  - L2-18 b and c.

**On the flat it carries further.**
- The jump can leave up to `walkSpeed × coyoteSeconds` = 2.4 studs past the edge and 1.4 studs lower.
- That makes `stray_reach` 49.3 instead of 46.6.
- I re-ran every `check_levels` gate with that longer reach and with `reach_at_rise` widened the same way: 168 of 168 verdicts are the same.
- A dash off an edge gains nothing the models do not already count:
  - the models count a dash's 20 studs once either way;
  - a ground dash drives only the plane, so the body falls.

**`sim_range` has no edges to walk off.** A player's floor changes in the frame he crosses it, and he only jumps from the floor.

**Caveat.** If a later layout comes within about 3 studs of a `stray_reach` line, model the grace in `stray_reach` and `reach_at_rise`.

## d1: the Python side

- No rule in `check_levels.py` or `sim_range.py` relied on players colliding with each other:
  - every reach rule models one body;
  - `startSpacing` only spaces spawns.
- The server agent says that NUDGE's "a road player never lands on a nudged one" no longer guards a physical clash. The rule stays true and harmless, so I left it.
- The "owners of doubleJump only" labels stay.

## Mutants (`check_levels_mutants.py`)

New or changed cases. All behave as expected.

| Case | Expected |
|---|---|
| s1: the centre rule back (`TRIGGER_MODEL` centre, `secretReach` 5) | the cache's (a) red |
| s1: the centre rule at 2.5 | red |
| s1: `secretReach` 0.9 | red |
| s1: the cache raised 5 off the road | red |
| s1 control: the footprint rule | green (CacheSpur) |
| s1 control: the centre rule keeps the lookout | green (the chest's top) |
| L2-18d control: the chest at z −60.5 (was "z −61, green") | green |
| L2-18d: the chest at z −61 (the trigger over the void behind the ledge) | red |
| d3: `can_jump` always true | sim_range one-jump gate red |

## Gates (run on the working tree as it stood after the server agent's SecretFlow, Unlocks and StageFlow changes)

- `py tools/check_levels.py`: **CHECK: PASS**.
- `py tools/check_levels_mutants.py --luau C:/Users/benja/Desktop/tycoon/tools/bin/luau.exe` (3.12): **MUTANTS: PASS**, 79 lines ok: the shipped data, 73 data cases, 4 stage-mirror cases and 1 simulator case. The run takes about 14 minutes.
- `py -3.12 tools/sim_range.py --check`: **CHECK: PASS**. Its output is identical to the run before the cap change.
- `py -3.12 tools/sim_range.py --check --levels-only --level forest`: **PASS**, and its output is identical to the baseline before any of my changes.
- `py -3.12 tools/sim_combat.py --check`: **PASS**, 23 of 23.
- `py tools/check_stage_mirror.py --luau ...`: **CHECK: PASS**, with the server's change in (`Unlocks` among the modules).

## For other owners

- **Docs (PLAN), for W3:** the Island Shrine needs a "without ice" reach rule and a pond that is not solid. Today the shrine opens from the solid Pond.
- **Docs (PLAYTEST):**
  - Without Double Jump, try A's fence corner and a wall hop at the ledge face. This is the unchanged single-player margin of 1 stud.
  - Walk up to the lookout and to the cache side-on, and check that the chest opens: `secretReach` 2.5 from the footprint.
- **Lead:** the d3 mutant is a full forest check, so `check_levels_mutants.py` now takes about 15 minutes. `--only` skips it.
