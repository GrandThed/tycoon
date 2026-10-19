# L2 W2 second fix-diff review (d98b85d..aca232d, 2026-10-18)

Reviewer: roblox-reviewer. Scope: the second fix round only (23 files), read against `l2-w2-review.md`, the
findings it answers (`fix-diff.md` m1-m3, s1), the rulings `l2-w2-fix2.md` and the report
`l2-w2-reports/fix2.md`. Accepted beyond the ruling: the lead stops 0.5 short of the first solid; GatehouseWallE/W
1.5 shorter at their south end.

Gates, run on a `git archive aca232d` copy in the scratchpad (never in the worktree):

| Gate | Result |
|---|---|
| harness | PASS, 2,835 checks |
| `check_levels.py` | PASS. Camp C eyes +4.09, cameras +5.20, doorway glimpse -0.87; origin chord "30 pieces, the thinnest CaveBrambleE 2" |
| `check_levels_mutants.py --only fix2` | PASS: 7 red, 2 green controls, the mirror case red, shipped data green |
| `check_levels_mutants.py --only L1c` | PASS, 20 cases ok (the re-aimed `l1c_wall` cases and their shipped-wall twins) |
| `check_stage_mirror.py` | PASS (FenceThickness 9 compared) |
| `mutate.py` filtered to "fix2" | 36 run, 0 not caught |
| `mutate.py`, three review probes on WorldReact (scratch copy only) | 2 of 3 not caught (Suggestion s1 below) |
| `py -3.12 tools/sim_range.py --check` (3.12.10, 64-bit) | PASS |
| `check_compile`, stylua and selene (changed sources), luau-lsp (changed sources, combat sourcemap) | PASS / clean / 0 0 0 / no errors |

**Result: 0 Critical, 0 Major, 1 Minor, 2 Suggestions.**

## Minor

**m1. The lead runs along the client's velocity at the ring's 3D speed, so a forged origin round a wall's end is
accepted.**

- **Where:**
  - `src/combat/server/Services/WeaponService.luau:545`: `WorldReact.LeadHead(anchor, root.AssemblyLinearVelocity,
    speed, lag)`.
  - `src/shared/WorldReact.luau:276-284` (LeadHead) caps the velocity's length at `speed` and keeps its direction.
  - `src/combat/server/Services/PositionRing.luau:104`: `speed` is a 3D displacement, so falls and jumps count.
    `Tuning.FastestMove` caps it at 140 (`slamFallSpeed`), and `CommitLag` at 0.3 (`originLagMaxSeconds`).
- **What:**
  - The cap holds the lead's LENGTH to the server-measured speed. Its DIRECTION is the client's: the server's
    `AssemblyLinearVelocity` of a client-owned character is whatever the client replicates.
  - A forger hopping in place gets a ring speed of about 74 and can claim a horizontal velocity. With a slam
    fall it gets 140. At lag 0.3 that is 22 or 42 studs of lead in any direction.
  - The cut-back (LEAD_STANDOFF) keeps the carried head on the head's side of the first wall ON THE LEAD'S LINE.
    It does not stop the lead from running PAST a wall's end and seeing the wall's far side from there.
  - So the rule is now two-segment visibility: "seen from any point a straight free line of up to speed x lag
    reaches". It used to be "seen from the head". The report's claim ("a forged origin beyond a wall ... stays
    refused however the velocity was claimed") holds only for a wall with no end inside that reach.
- **Probe** (a port of LeadHead/AimClear/OriginClear with the harness's box caster:
  `scratchpad/fix2rev/leadprobe.py`):
  - The wall is free-standing, 20 long, 2.5 thick and 76 high. The head stands 1.5 off its south face, at its
    middle.
  - The origin is 10.2 away, beyond the wall near its east end, inside a slack of 28.2.
  - No lead: refused. A claimed velocity of (74, 0, 0) at speed 74 and lag 0.3: the lead reaches x 32.2, past the
    end, and the shot is allowed.
- **Scope today:** I found no damage path in Forest Road.
  - Camp C's ring is closed to every standing head. Every surface outside it (GatehouseWalk, GatehouseTurn,
    TrailEnd) has its top at the floor's y 12, so a line from any head there into the camp crosses at least 2.5
    of fence or gate. The ring's corners are filled, it stands 76 high, and the Turn fills the north gate's foot.
  - One caveat. The fence stands outside the floor and touches the 4-deep floor slab only along an edge. A line
    from UNDER the fence's foot can clip that edge with a chord of 0. Only a body falling into the void beside
    the gatehouse is ever there, so this is no finding.
  - Camps A and B have 4-high fences, which are shot over anyway.
  - Damage needs in-play.
  - So this is a hole in what the rule promises, not an exploit yet. Any later level with a free-standing tall
    wall in or beside a fight floor inherits it (internal walls of a walled camp, a parapet at a sniper spot).
- **Fix:**
  - Lead along the server's own measure of the motion: the displacement over the ring's newest
    `originSpeedSeconds` stretch, which is the same stretch `PositionRing.Speed` already walks.
  - Or keep the velocity but scale the lead by its component along that displacement (0 when they disagree).
  - Add a harness case: a velocity at right angles to the ring's motion leads nowhere. Add a mutant that restores
    `AssemblyLinearVelocity`.

## Suggestion

**s1. The honest path through the cut-back is untested. Mutating it keeps the harness green, and the gatehouse
needs it.**

- **Where:** `src/shared/WorldReact.luau:45` (`LEAD_STANDOFF`) and `:318-320` (`carried`);
  `tools/crowd_harness/tests_l2w2.luau:639` (`leadTests`).
- **What:**
  - `leadTests`' only honest case leads along a leg that never meets a wall, so `hit` is nil there. Every case
    where the lead does hit is a forged one, where any carried point on the near side is refused.
  - Two scratch mutants survive the full harness (2,835 checks green):
    - `then head + reach * (...)` changed to `then head`, so a lead that meets a wall counts for nothing;
    - `LEAD_STANDOFF = 50`.
- **Why it matters:** the honest gatehouse case runs through exactly that branch.
  - Hand-traced on ForestRoad: the head trails at (299, 16.5, -37), hugging WallS, dashing east (133, lag
    0.3). The client has turned into the passage, origin at (306.7, 17, -33).
  - The head's line crosses WallS/WallW's corner and is refused.
  - The lead meets WallE at 22.5 and is carried to x 321. From there the line runs inside the turn's column
    and is allowed.
  - With either mutant this case is refused again, which is the m2 complaint.
- **Fix:**
  - Add this case, with a lead that meets an outer wall and an origin round the inner corner, to `leadTests`.
  - Add `mutate.py` entries for `then head` and for a large `LEAD_STANDOFF`.

**s2. The Beam loses its moving bloom too. Say so at the playtest.**

- **Where:** `src/combat/client/Controllers/InputController.luau:1056-1061`.
- **What:**
  - `variant.continuous` is true for `beam` A (55 studs, width 1.4) and `beam` B (100 studs, width 0.5), not only
    the Flamethrower.
  - Moving or airborne bloom (up to `bloomMaxDegrees` 7) used to put Beam B up to 12 studs off at full range. It
    now goes exactly down the crosshair.
  - This is a feel change to a P3 weapon Ben approved. The ruling's "continuous (stream) families" covers it, and
    no simulator ever modelled bloom, so the sims and the Warlord tuning are unchanged.
- **Fix:** a PLAYTEST line for Beam B while moving, or keep the bloom for a variant under some width if Ben
  wants it back.

## Checked and sound

**The 2.5 fence against L1c.**
- **The trigger, the camera clip and the close.**
  - The trigger, `RunFloor.fence` and the camera clip all read the zone's own thickness.
  - The clip now keeps the boom 6 off the floor's edge.
  - The close nudges at most 2.5 + 2 = 4.5. The harness entry test runs every root on the trigger line and over
    the fence band.
  - The nudge lands 8 studs clear of the entry and 19.5 clear of cover.
- **Ceiling, chase margin and the barrier.**
  - The ceiling (64) and `inner` are unchanged.
  - `chaseMargin` 2.5 now equals the fence. A root outside it sits 3.5 or more off the floor's rectangle, so it
    is out of play by the floor rule.
  - The barrier is `max(8, 2.5)`, still 8 deep from the floor's edge (z -34..-26), as the L1c contract states.
- **The gatehouse joins** (Walls E and W end at z -28.5, flush with the fence's outer face):
  - Every remaining contact is back-to-back faces, or WallW/WallE meeting the fence and gate side by side.
  - Before the shortening, WallW's east face and the fence's east face beside the gate were coplanar and faced
    the same way over z -28.5..-27. That would z-fight, and it is gone.
  - Below y 12, WallE's south face now shows at z -28.5 instead of -27, over the void. No player sees it.
- **The east exit:** Gate_C_2 is now 371..373.5, still over TrailEnd (371..387).
- **The rest of L1c:**
  - The route and sneak legs are unchanged, and check_levels' route band passes.
  - Sight margins improved (eyes +1.57 to +4.09, cameras +2.73 to +5.20, doorway glimpse -2.53 to -0.87).
  - No outside camera sees in.

**The thickness in every tool.**
- check_levels (`fence_strips`, `gate_rect`, `layout_bounds`, the camp rules, `check_walled`'s fenced rectangle and
  lockers, `sight_points` through `gate_rect`) and sim_range (`plan_level`, the scene walls) take
  `sim_range.fence_thickness`.
- `check_stage_mirror` compares it with `LevelGeometry.FenceThickness`.
- The server's only other reads of `levels.fenceThickness` are `Pieces`' default (LevelService :195) and the
  client's fallback.

**The origin chord gate.**
- It is not vacuous: fence 1, chord 2.5, chord 6 and a 1-stud wall 6 high all go red; chord 1.9 and a 4-high rail
  stay green.
- The source check now reads the tolerance argument, and the "chord is originPad" mutant is caught (the W1/fix-diff
  pattern, closed).

**The forged cases the ruling names.**
- A velocity into a wall or along it, an origin inside the wall, a lead claimed inside the wall: all refused,
  checked in the harness and by hand.
- The port, on camp C closed (2.5 fence and gate, floor slab, Turn, gatehouse walls), at slam speed 140 and lag
  0.3: from three heads in the passage against the gate, with five lead directions, every origin on a 2-stud grid
  inside the camp (x 300..328, z -25.5..-22, y 13..20) within slack was refused.
- Grazing incidence cannot put the carried point inside a wall through float32 rounding: the head's centre is at
  least about 0.5 off any face, so the standoff's perpendicular part is at least about 0.006 studs.

**Honest fast travel.**
- The lead accepts the gatehouse L in both directions: east then south as traced in s1, and north then west, where
  the lead stops at WallN and the line runs inside the corridor.
- It also accepts falls off ledge edges.

**No bloom on streams.**
- `nextSpreadDegrees` is 0 for continuous variants. So the sent direction, FlameFx's line and `reactOnAuto`'s
  capsule are one line, and the crosshair shows no bloom.
- No server check assumes bloom: WeaponService has none.

**s1, the client cache.**
- `rangeState.worldParams` is rebuilt after `watchPlayer` / `forgetPlayer`. They cover CharacterAdded for every
  player, the local one included, plus PlayerAdded and PlayerRemoving.
- The range and old-mission paths are exclusive, so the connections are never doubled. `Destroy` disconnects them.
- Exclude filters match descendants at query time, so a respawned character's accessories are covered once it is
  rebuilt.
- The server's cache already rebuilds on CharacterAdded and CharacterRemoving.
