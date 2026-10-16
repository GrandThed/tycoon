# L1b Wave 4 — luau-engineer A (the crowd), report (saved by the lead)

Commits on `l1b-wave4`: `36ea31b` (Types block, alone), `c94f016` (`Region.luau`, `CampBrain` exports),
`e98923c` (`CrowdBrain`, `CrowdService`, `tests_l1b_w4_crowd.luau`, changed cases in `tests_l1b_crowd`
and `tests_l1b_w2_crowd`). Verify: stylua clean; selene 0 errors (LegacyPanel warning); check_compile
PASS (157 files; CrowdService 99 top-level locals); luau-lsp hub and combat clean; harness
`HARNESS: PASS (2,248 checks)`; 68 / 68 own mutations caught in a scratch copy. Gate 18 clean.

## Beyond the contract (the `sim_range` mirror must match 1–4)
1. A stood-down rusher finishes an attack it has started (resting only when not in windup, attack or
   charge); `CampBrain.Step` follows the contract, only the executor differs.
2. Stop distance of a routed goal: a door is walked onto with stop 0; a goal clamped onto the region's
   edge without a door gets `max(stop − flat distance(goal, clamped goal), 0)` (else a rusher halts 4.5
   short of the edge and breaks `chaseMargin ≤ reach − √2·radius`).
3. `closing` is true only for a living, thinking, non-keepAway resident that moved at its last step; a
   charging step stamps false.
4. At the close, the forget runs first, then the same camp step's `Step` (contract order).
5. Home's turn-back (L1b-W4-24) also applies to a group with no region (reachable = in play).
6. `Struck`'s `now` is the crowd's step clock.

## For other owners
- **B (`mutate.py`):** add `REGION = "src/shared/Region.luau"` to `FILES`; add
  `L1B_W4_CROWD_MUTATIONS` (53) and `L1B_W4_CROWD_REPLACED` (15) with `MUTATIONS.update` (the replaced
  table after the tables that define those labels); delete three retired mutations from
  `L1B_CROWD_MUTATIONS` with a comment naming the successor ("home takes damage", "home wakes on a
  hit", "a hit from out of play lands"). Verbatim texts: `crowd_mutations.py` beside this file.
- **economy-designer:** `stage_mirror.luau` bundles `Region.luau` before `CampBrain`; mirror points 1–4.

## Old cases changed (old → new)
See the commit `e98923c` diff of `tests_l1b_crowd.luau` and `tests_l1b_w2_crowd.luau`: out-of-play hits
land; `inPlay` → `reachable` / `known`; home takes hits and turns back only for a reachable player; the
tent timeline (always ahead) `{0,6,12,40,46,60,66,72}` → `{0,6,12,40,46}`, `left` 0 → 3.

## Studio checks
No raider walks through a fence or off the plateau or freezes at a door (watch the U-bend); raiders
follow out through a gate and give up about 3 s after losing the player; on the lookout ledge rushers
walk home and slingers keep shooting; a brute's charge runs on through the gate; after the Chief's
close no group of A or B stays awake; `[Perf]` p95 with both camps out (budget 2 ms).
