# L2 W2 fix round: data agent report (2026-10-18)

Slice: d-M1, d-m1, d-m2, d-m4 and the s-m3 mirror (`docs/prompts/l2-w2-fix-round.md`). Branch `l2-w2` in
`tycoon-p5`. Nothing committed. Numbers and reasoning: `docs/BALANCE.md` "L2 W2 fix round".

## Files changed (all mine)

- `src/shared/Layouts/Levels/ForestRoad.json`: CaveWallS2 split into S2 (x −221..−180, top **84**) and a new
  **CaveWallS3** (x −180..−118, top 64); CaveRoofE split into RoofE (x −221..−180, top **84**) and a new
  **CaveRoofE2** (x −180..−102, top 64); CaveWallAlcoveW/E/N and CaveRoofAlcove 64 → **84**. Feet unchanged.
  Parts 112 → 114.
- `tools/check_levels.py`: the d-M1 rule, d-m1 grace, d-m2 known limit, `near` on sniper spots, two bounds that
  keep the run at about 20 s.
- `tools/check_levels_mutants.py`: 13 new cases (12 data, 1 stage-mirror).
- `tools/sim_range.py`: the s-m3 mirror line; the d-m4 fire sniper course.
- `docs/BALANCE.md`: a new section "L2 W2 fix round".

No config number moved.

## Gates

| Gate | Result |
|---|---|
| `py tools/check_levels.py` | PASS (about 20 s) |
| `py -3.12 tools/sim_range.py --check` (64-bit 3.12.10) | PASS: 498 checks, 10.4 min |
| `py -3.12 tools/sim_combat.py --check` | PASS, 23 of 23 |
| `py tools/check_stage_mirror.py --luau ...` | PASS, with the server's s-m3 line in |
| `py tools/check_levels_mutants.py --luau ...`, full run | MUTANTS: PASS: 114 data cases, 5 stage-mirror cases and 1 simulator case, every one as expected (40 min) |

## What each ruling became

**d-M1, the ridge.**
- The new gate is "behind fire: no ability that carries a player with the double jump puts him on a wall that
  faces the sealed air". It covers both carrying abilities:
  - Leap Smash: `lift_routes(..., air=True)`. Take-offs are at jump + double jump, with 18.0 studs of carry
    (both climbs plus the walk-off grace) plus a dash. Over a void, the caster's floor is his feet minus 30.
    `TooHigh` uses Rise 30.
  - Impale Dash, held in the air for its 30 studs. The dashing families are read from AbilityService's
    `target = "dash"` rows, through `air_carry`. This is the reviewer's Spear follow-up, folded in.
- On W2's data the gate is red: 10 Leap take-offs off the ledge reach CaveWallS2.
- Where the split has to sit:
  - Leap Smash is clean from x −205.
  - The Spear's air dash still reaches CaveWallS3 at −205 (67.9 studs off the ledge) and is clean at −195.
  - The split is shipped at **−180**, about 20 studs clear of both.
- Unaffected, because only the tops moved:
  - the inside (every roof's foot is still 22, the 12 × 14 section);
  - the camera clearance;
  - R8's sight;
  - the walled gate;
  - the routes.
- From outside, the 84-to-64 step now sits 41 studs further east.

**d-m1, the grace.** `wall_reach_of` = `stray_reach` after 0.12 s walked off the edge, which is 2.4 studs out
and 1.4 lower, giving **49.3**. It is used by `unclimbable`, by the ridge's line and by the walled gate's reach
(the reviewer's line 2974). Every rule stays green.

**d-m2, the bend.** A second L2-47 line covers the same hop search with the longest carrying ability's travel
(32) added.
- While no carrying family can be owned without a lever, it reads "KNOWN LIMIT until L3". "Owned" means the
  starters plus every family a secret pays. Today that is Broadsword, Longbow and Flamethrower.
- Once one can be owned, the line goes red. The mutant "the cache pays the Spear" shows it.
- The known-limit hops, listed in gate 16:
  - BC1/BC2 → BC4: hop 54.0, saves 104 studs.
  - BC1/BC2 → BC5: saves 96 studs.
  - **AB1/AB2 → AB5 round BendWall's south end: hop 80.4, saves 61–63 studs.** This is new against the
    review, which named only BC.
- No camp is skipped.

**d-m4, the fire sniper.** I added a sniper course that also casts Dragon's Breath through walls, at the nearest
body its cones reach, the moment it is ready. Kills refund it. The course waits out the cooldown, so its idle
time is 10 s + 10 s. It runs from each open spot's own point and from its nearest point. It is gated like the
bow rows.
- Best rate: CaveExit on Normal, **2,037 against 25,104 cash a minute (8%)**; on Hard, 1,646 against 20,512.
- CaveMouth's nearest point is 27 studs off the region, beyond the cones' reach.
- **Neither spot out-earns the mission player, so the corridor is not moved.**
- The thinnest R8 margin is unchanged: the bow on Hard at CaveMouth, seed 23, −6.6%.

**s-m3 mirror.** `react_problems` now refuses a shortcut `sx`, `sy` or `sz` of 0 or below. Its message is
`shortcut "<id>": <key> is <n>, not a size above 0`, which is the server's line. Mutants:
- data: sz 0 and sx −12 are red; the control (sy 0.01) is green;
- mirror alone: check_stage_mirror goes red on "a shortcut with an sz of 0".

## For other owners and the lead

- **Lead, a hazard in the shared scratchpad.** It has a `types.py` from another agent (an ArmoryWeapons.luau
  edit script). It shadows the standard library for any Python run from that folder: my first patch run
  imported it. It asserted on its first replace and wrote nothing, because that edit was already in
  ArmoryWeapons.luau. Every script of mine now lives in `scratchpad/fixdata/` and runs with `py -I`. Ask its
  owner to rename it.
- **Server agent:** I mirrored your s-m3 line exactly, and check_stage_mirror is green. There is nothing else
  for you.
- **Formula changes in `Economy.luau`:** none.
- **Known limits for the lead to record:**
  - d-m2 now lists the AB bend (61–63 studs, about 3 s) as well as BC.
  - Both close with data when L3 sells a carrying family: a wall at BC, and BendWall run south. The rule turns
    red on its own then.
