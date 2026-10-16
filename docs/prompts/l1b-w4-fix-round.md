# L1b Wave 4 — fix round (lead's rulings and the fix list, 2026-10-15)

The four review slices are in `docs/prompts/l1b-w4-review/` (`crowd.md`, `run.md`, `client.md`,
`data.md`): 0 Critical, 4 Major, 12 Minor. Read your slice's file and every item below that names
you. These rulings are binding and amend the contract (`docs/INTERFACES.md` "L1b Wave 4").

Process: the common rules of `docs/prompts/l1b-w4-build.md` hold (worktree, own paths only,
`git commit -- <paths>`, no `mutate.py`, LF, kill only your own processes). Every fix gets a harness
case or a gate that fails without it, and a mutation (texts to B for `mutate.py`, or to the designer
for `mirror_mutants.py`). Report to `docs/prompts/l1b-w4-fix-reports/<owner>.md`; if the Write tool
refuses it, put the whole report in your final message.

**Order:** A goes first on R1, R2, R4 and R7 (the designer mirrors them). B and the ui-engineer start
at once. The designer starts once A's commits for R1, R2, R4 and R7 have landed (check `git log`).

## Rulings

**R1 — `closing` means progress (crowd Major M1; luau-engineer A; designer mirrors).** A body stamps
`closing` only while its flat distance to its routed goal shrank by more than a small epsilon since
its last step (one number field per enemy, no allocation). Bodies pressed against one clamped point
by separation stop closing, so the leash and the stand-down run. Harness case: 4 rushers against a
hitter below a road end and a seen player past the road's end, both stand down within leash + a
margin. Mutation: stamp from desired speed again.

**R2 — the close lets a blow finish (crowd m1; A).** `ForgetOthers` sends a group home, but a member
in windup, attack or charge keeps thinking until its blow resolves (as a stood-down rusher does). No
frozen mind holds a `perPlayer` place. Case + mutation.

**R3 — restore the engagement check (crowd m2; A).** A reachable player outside every member's cone
is not engaged with a group walking home; the old mutation `l1b crowd: a group walking home engages`
is caught again.

**R4 — heal once at the post (crowd m3; A; designer mirrors).** A stood-down rusher is healed once on
arriving at its post (plate and `damageBy` included), with a latch cleared when `standDown` clears;
never every camp step. Case + mutation.

**R5 — brutes walk round the U-bend (crowd m4; A; designer mirrors).** A brute does not start a lane
whose region runway along its facing is shorter than its distance to the target minus the lane's
width; it walks the routed way. Case + mutation.

**R6 — no hits through a cliff (data Major 1; A owns `VitalsService.luau` for this fix only;
designer mirrors and gates).** Every ground shape gets the lob's lower bound: a strike lands only if
`feet − strike.floorY ≥ −height` as well as `≤ height`. Mirror it in `sim_range.py` and run one
sniper course at the foot of the climb. The designer adds the `check_levels` gate "no standable
ground below the region within a rusher's shape range minus its radius of a cell edge" — after R6 it
must pass on Forest Road; prove it fails with the rule removed. The range's bands and the bosses must
stay green.

**R7 — the tent's pace starts again after rest (data Major 2; A for `CampBrain`, B for WaveService's
call, designer mirrors).** When every group of a camp is back at rest, its tent's pace measure starts
afresh: busy time 0, and kills and residents counted from the camp's living residents at that moment,
as if it were a fresh camp. A defines the signature (`TentClock` / `Ahead` / `TentState`) and states it
in the commit message and the report; B adapts `WaveService.tickTents`. The designer adds a band run in
the playtest checklist's order (chase out, lose, then a fast clear at 4 / 4) in which the tent sends.

**R8 — the sniper must not pay (data Major 3, data m1, data m2; designer, with a stop).**
- The designer lists, by a `check_levels` gate, every standable top that no rusher can reach (off the
  region by more than `chaseMargin`, or over `meleeAbove`, including tops above `sightAbove`) and that
  lies within the Longbow's range of an open camp's floor. Today that includes the lookout ledge, the
  secret lookout (38), the foot of the climb, the LookoutSignPad strip and RoadBC6.
- `sim_range.py` rates a straight sniper course from each listed spot (no idling, a double jump where
  the game allows it), after R1, R4 and R6 are in. Each must earn **less cash per minute than the
  `mission` player** at 2 / 2 on Normal and Hard. The band is gated.
- Fix by data only: shooters (slinger, marksman) posted so their reach covers the spot ("shooters
  answer high ground"), cell edges, `sightAbove`. Do not move the Chief's Clearing.
- **Stop rule:** if a spot cannot be brought under the mission's pay by data alone, stop work on that
  spot, report its numbers and what you tried, and leave the band red for that spot only. The lead
  will ask Ben.

**R9 — the simulator's height rule and retreat (data m3, m4; designer).** Measure heights from the
crowd's floor as the game does; route a keepAway retreat through `Region.Toward` as the server does.

**R10 — the rescue judges danger by position (run m1; B).** For region floors, the safe point is chosen
by where bodies stand: `threats()` lists every member of a group in rise, fight or home; `busy[index]`
applies only to zones without a region. Cases: (a) a fall at the U-bend while A's group chases far off
lands at A's checkpoint, not the trailhead; (b) a fall while A's group walks home through its
checkpoint does not land among them. Mutations.

**R11 — two untested rules (run m2, m3; B).** A case where only the tent fields the widest kind and
the longest reach (doors and lock clearance must count it), and a fixture with an open zone after the
locking camp (N must stop before the locking camp). A mutation for each.

**R12 — a refused tent spawn is not "sent" (data, for run; B).** `Fielded` counts only bodies that
spawned; the designer drops the simulator's deliberate copy. Case + mutation.

**R13 — auto-fire never wakes a camp through a pierce (client m1; ui-engineer).** Touch auto-fire
does not fire when the first body the crosshair ray meets (`HitShapes.Ray`) is one `autoMayTake`
refuses; for melee arcs and cone guns, not when a refused body is inside the padded shape. No new
top-level local (CrowdRenderer 154, InputController 149 are at their caps). Give B the CampAim-side
test cases if any, and the mutation texts.

**Carried, not fixed now (lead):**
- RunState resends `floors[i].cells` every state send (client review, for run): about 30 records per
  send, data that never changes. Carried to L4 with the "snapshot bytes" item.
- The playtest's "a bonus for the Pickets only" cannot be seen (no per-camp bonus on screen): the
  docs-keeper rewrites that step; the per-camp bonus display goes to L4's end screen.

## Reports

Each owner: the commits, each fix → file:function, the cases and mutations added (verbatim texts for
B's `mutate.py` and the designer's `mirror_mutants.py`), each verify command's verdict line, and for
the designer the sniper table (spot, cash per minute, Timber per minute, against `mission`) with R8's
stop applied where it had to be.

## Added during the round (lead)

**R14 — a player below the floor is not melee-reachable (A; designer mirrors and sets the key).**
`CampBrain.Melee` gains a lower bound, `camps.meleeBelow` (measured as `meleeAbove` is), so the foot of
the climb (8 below) is out of melee reach while the road and the rim's step are in. `CrowdBrain.begin`
never starts a ground-shape blow at a target whose feet lie outside the shape's vertical band (R6), so
no windup at an unhittable player holds the leash. The designer adds `meleeBelow` to `Combat.json`
(A's report names the value it needs) and mirrors both rules.
- tests_w2's pinned arc check now expects R6 (lead, cef3d38).

**R14 delivered (A, f72e244):** `meleeBelow` **1.5** (must satisfy `0 ≤ meleeBelow ≤ min(sightBelow,
lowest rusher height − root height − 0.5)`; the designer adds that `check_levels` gate). `CrowdBrain`'s
new `reaches` applies on every floor: a boss no longer starts a slam or charge at a player on a block
taller than the shape's height; the designer's boss sims confirm the bands. **`Combat.json` must carry
`"meleeBelow": 1.5` before anything ships** (else `CampBrain.Problems` refuses the camp rules).

**R15 — ThreatField's moving charge and ring get R6's lower bound (A).**

**Ruled after the designer's report (2026-10-16):**
- **R8's stop, Ben's ruling ("Accept, fix in L4"):** on Normal the snipers from the lookout ledge, the
  secret lookout and the cache block out-earn the mission (cash per minute ×1.0–1.7; Hard is under it).
  Bounded: camps never refill, so the total is the same and a camp only clears faster. Reported as a
  known limit, not gated; L4 re-places the perches with the real forest and the gate must pass on every
  spot before L4 ships.
- **"The tent when fast: B at least 3"** (was 4): under R7 the pace restarts between groups; accepted.
