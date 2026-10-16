---
name: l1b-living-road-review
description: L1b "the living road" reviews (resident camp groups, open camps, per-kill pay) - wave 1 slice 4 (data and tests) verdict, how to run the gates read-only, and the open-camp geometry patterns to recheck in Wave 2
metadata:
  type: project
---

L1b = residents in open camps (CampBrain groups: guard/patrol/fire, rest/rise/fight/home), only the
boss room locks, every kill pays at once (Combat.SplitCarry). Contract: INTERFACES "# L1b contracts"
(~line 11369) on branch `l1b-living-road`, worktree `C:\Users\benja\Desktop\tycoon-p5`. Reviewed
in four slices from `docs/prompts/l1b-w1-review.md`; findings go to `docs/prompts/l1b-w1-review/<slice>.md`.

**Wave 1 slice 4, data and tests (2026-10-14): 0 Critical, 0 Major, 8 Minor.** All gates green.

**Why:** Wave 2 (the 1,000-stud road, camps twice the size, tents, sneak paths) reuses these gates.
Each pattern below is latent at Wave 1's sizes and becomes real with new terrain.

**How to apply (read-only gate recipe, from the worktree):**
- `py tools/check_levels.py --no-plan | grep -E "PASS|FAIL"` (0.5 s).
- `py tools/check_stage_mirror.py` (2 s; it finds the main checkout's luau.exe itself).
- `py tools/sim_combat.py --check` (about 20 s).
- `py tools/sim_range.py --check --levels-only --level forest` (run it in the background).
- To prove mutate.py's texts without running it: exec its source up to `def harness(` with a
  fake argv, then count each `old` text in its file (495 entries at wave 1).

**Open-camp patterns to recheck:**
- The in-play area is the floor grown on each axis (a rectangle). A clamped rusher's reach is a
  circle. So `chaseMargin` ≤ reach − radius protects edges but not corners, where √2 × (m + r)
  exceeds the reach. Any standable top within the margin is in play up to `sightAbove` 30, and
  melee misses feet above its `height`. The cover gate checks only obstacles on the floor; open
  camps leave the fence top and surrounding ground standable.
- A safe point must also be out of reach of a busy NEIGHBOUR camp's keepAway shooters. A's
  checkpoint on the 44-stud RoadAB sat 44.6 studs from B.fire1's Hard marksman (reach 48).
- A group can only finish `home` if every post is reachable. Overlapping posts (guards, or posts
  of different groups) leave it evading forever and keep `Awake` above 0. Only fire neighbours
  were gated.
- A mirror can pay a bonus on one of the two clear paths only. Check `on_open` against
  `campClear` whenever WaveService has one helper behind both.
- A patrol that mixes kinds walks each body at pace × its own speed, so it bunches.
- After a lead ruling, BALANCE's band rows and flags often stay stale. Compare them with the
  constant in sim_range.

**Several slice reviewers share this file at once. Never Write it whole: re-read it and Edit
only your own section.** On 2026-10-14 it was overwritten twice that way. The run and crowd
sections below were restored from the agents' transcripts.

## Wave 1, run slice (2026-10-14, diff 8e8990c..e2479c3): 0 Critical, 1 Major, 2 Minor
- **Major: a downed party member stays down for the whole road.** A down sets
  `downUntil = math.huge`. Only a `boundary` action (`standUpDowned`) or the return to the lobby
  stands anyone up, and the open camps lost their stages, so they lost their boundaries too.
- **Minor:** a skip's `open` still runs `campCleared`, which pays the bonus and writes stats.
- **Minor:** no gate pins "`progress()` runs in every live step". A mutation passes both the
  harness and `check_stage_mirror`.
- **Pattern: removing a structural event removes everything that rode on it.** When a contract
  deletes an action, stage or phase, grep every handler of it and list what each one did besides
  its headline job.
- **Proving a test vacuous without touching the worktree:**
  1. Copy `src/`, `tools/crowd_harness/` and `tools/check_levels.py` to the scratchpad and mutate
     the copy.
  2. Run `py tools/crowd_harness/run_harness.py <scratch> <main>\tools\bin\luau.exe`. The cases
     come from the worktree and the sources from the scratch copy.
  3. Run `check_stage_mirror.py --luau <exe> --module StageFlow=<scratch file>`.

## Wave 1, crowd slice (2026-10-14, same diff): 0 Critical, 1 Major, 2 Minor
- **Major: the in-play area has square corners** (the margin-at-corner pattern above).
  - Probed on the real CrowdService: a fodder clamped at the corner, 5.94 from the player, never
    winds up, and every hit lands.
  - Suggested fix: rounded in-play (distance to the rectangle) and a gate of
    `reach − √2 × radius` (fodder 2.66).
- **Pattern: a per-step state read at an event that has already left it.** `Engaged` has a height
  band, and the fall rescue fires at killY after several crowd steps out of the band, so "no
  i-frames while engaged" never applies to a fall. Ask of any "while X" rule: is X still true
  when the consumer reads it?
- The tests read `Awake`, `Busy` and `Engaged` in rest, rise and fight, never in `home`.
- What held:
  - CampBrain matches the contract rule for rule.
  - A resident that is not fighting never thinks and holds no turn (`Commit` counts striking
    minds only).
  - No stuck fight (striking always ends); no stuck home on the shipped posts.
  - The fence top (4) is under the lunge's height (5).
- **A probe that writes nothing in the worktree.** `run_harness.py` and `mutate.py` write
  `bundle.luau` and `mutant/` in the worktree's harness folder. Instead:
  1. `import run_harness as R`.
  2. Write `R.prelude(repo)`, the chosen `R.TESTS` (VERDICT stripped) and the probe to the
     scratchpad. The L1BC helpers are in scope after `tests_l1b_crowd.luau`.
  3. Run the main checkout's luau.exe on it.

  Wrap the probe in a pcall: an error otherwise ends the run silently.
- **Old-code fixtures:** `git archive <base> src tools/crowd_harness | tar -x -C <scratch>/old`,
  then build with the old run_harness (`gate_reading` stubbed). This proved that the range hash
  2948329570 (2,400 bytes) really is pre-L1b.

## Wave 1, fix-diff check (2026-10-14, diff 9deef26..5ff333b): 0 Critical, 0 Major, 2 Minor
Findings are in `docs/prompts/l1b-w1-review/fix-diff.md`.

All four fixes held: rounded in-play, the engaged hold, stand-up on a clear road, and the safe
point kept out of a threat's reach.

**Patterns:**
- **A client-side gate that is stricter than the server's rule takes a fight away from touch
  players.** The client's auto-fire in-play test dropped the keepAway-reach clause. A phone
  player can therefore never return fire from where a slinger keeps him in play. Ask of any
  client "only stricter" gate: does it also apply where the action is harmless (an awake group)?
- **A pure query that the mirror does not compare drifts.** `StageFlow.StandsUp` allows `gate`;
  the simulator's own copy allows only travel/armed. Check `check_stage_mirror` `NEEDED` for
  every new pure function.

**Verified and safe to reuse:**
- `OnDown` runs after VitalsService's flush, so a stand-up from `advance` is not re-entrant.
- `canTarget` drops downed players.
- Crowd ids wrap at 65,535, so stale id lists are safe within a run.
- WaveService is covered by no gate. Only the pure rules carry tests.

## Wave 2, run slice (2026-10-14, diff main..f40509a, branch `l1b-wave2`): 0 Critical, 0 Major, 2 Minor
Findings are in `docs/prompts/l1b-w2-review/run.md`. Tents, the clear bonus, the population rule
(boss reserve 13) and DeadFraction all matched the contract. Harness 1,896; B's 24 mutations were
all caught.

**Patterns:**
- **An id list taken at a state change goes stale when bodies join without one.**
  `run.awakeGroups` holds ids from the GroupEvent. A tent body sent into a group that is already
  fighting fires no event, so `threats()` never sees it. Ask of any list snapshotted at a
  transition: can members be added between transitions?
- **A ring sampled at n points certifies the circle only on the axes when 4 divides n.** Validate
  checks posts at the top difficulty only, so a smaller lower-difficulty ring can stand posts past
  the clamp. That leaves a group stuck in `home`, evading and Awake.
- Before calling a tent "self-sustaining", compare `leashSeconds` (3) with the tent's `every` (6).
  Here a lone roused tent goes home before its next body.

**Recipes:**
- Snapshot without touching the worktree: `git archive <sha> src tools | tar -x -C <scratch>`.
  Then run `py -I <scratch>/tools/crowd_harness/run_harness.py <scratch> <main>\tools\bin\luau.exe`.
  For mutations, run `mutate.py <scratch> <exe> "l1b w2:"` (24 mutations in about 1 minute).
- To count mutation texts, exec `mutate.py` up to `def harness(` with
  `sys.argv = [x, root, "x"]`, since it reads argv[1] and argv[2] at the top.

## Wave 2, crowd slice (2026-10-14, diff main..f40509a): 0 Critical, 1 Major, 2 Minor
Findings are in `docs/prompts/l1b-w2-review/crowd.md`.

- **Major: the client and the server clear the air swing by different evidence.**
  - The client clears on a `Landed` event. The server clears only when one Heartbeat sample of
    the replicated root reads within 0.75 of standing.
  - At jumpHeight 18 the touchdown is about 84 studs/s, so the band lasts about 9 ms each way.
    A held-jump bunny-hop can pass between samples, and the server then refuses an honest swing.
- **Pattern: any "until X happens" gate kept on both sides.** Ask how each side detects X. An
  event on one side against a sampled state on the other diverges on short events. The server
  should look for X in its own history, for example a fall turning into a rise near the floor.
- **Pattern: a single centre ray as "on the ground".** A Humanoid stands on a lip with its centre
  past the edge, so the ray says airborne and the gate fires. Prefer a cast as wide as the root.
- **Harness trap:** the RemoteService stub stores payloads by reference. A case that reads
  `risen` sees the live `spawnInfo` table, not what was sent, so an "info at send" case can pass
  vacuously. Copy the values at the time, as the infos case does.
- **Probe without writing the worktree:** a script in the scratchpad that imports
  `run_harness`, writes `R.bundle(repo)` to `bundle.luau` in the scratchpad, and runs
  `tycoon\tools\bin\luau.exe` on it (PASS, 1,896 checks at f40509a).
- **Verified, safe to reuse:**
  - `RayUpright`'s `firstIn` matches `Ray`'s segment-to-sphere test exactly.
  - No shipped kind is squat (`top − r > r`).
  - A dormant group is still stepped, so sight wakes it every step.
  - An empty group stuck in `fight` is harmless: `Busy`, `Awake` and engaged all need a living
    member.

## Wave 2, client slice (2026-10-14, diff main..f40509a): 0 Critical, 1 Major, 2 Minor
Findings are in `docs/prompts/l1b-w2-review/client.md`.

- **Major:** the playtest checklist's order defeats itself. The headshot step in "the next camp"
  wakes Main Camp, through a blocked shot from outside or a real one inside, plus the join-in.
  The next step is then the sneak past that camp.
- **Pattern: walk the checklist against the rules.** For each step ask:
  - Which rule does this action trigger (a hit wakes; out of play reads BLOCKED)?
  - Does the next step need that rule not to have fired?
  - Is a step's "Bug:" text exactly what correct behaviour looks like? Example: raiders "pop in"
    from behind a fence that hides them.
- **Pattern: check checklist sight lines with numbers.** Compare camp floor top + fence height
  with feet + about 2.1 (the shoulder pivot). Forest Road: start Y 0, camp A floor Y 8, fence
  top Y 12, so nothing in the camp shows from the arrival point except the tent.
- **Pattern: client gate and server gate must clear on the same event.** Here the client clears
  on Humanoid `Landed` and the server on its root probe crossing the margin.
  - They diverge after a PlatformStand down and get-up (no `Landed`).
  - They diverge on a ledge edge (`Landed` fires, both probes still read air).
  - At 84 studs/s a held-Space hop's ground contact may never reach the server's replicated
    copy.
- **Verified and safe to reuse:**
  - `dueShots` advances even when a swing is dropped, so a gated swing probes once per interval.
  - Every client-made Part is `CanCollide = false`, so client and server floor probes see the
    same world.
  - The spawn-info seed is accepted by the first snapshot: its stamp is pulled under the packet.

## Wave 2, data slice (2026-10-14, diff main..f40509a): 0 Critical, 1 Major, 3 Minor
Findings are in `docs/prompts/l1b-w2-review/data.md`. All four gates green.

- **Major:** the same checklist Major as the client slice (step 4's headshots "in the next camp"
  wake Main Camp before step 5's sneak), found on its own from the data side: A has no plated
  raider below Hard, so the checklist can only mean B.
- **Minor:** C.south's guards stand on C's tent-marker wall. The marker clearance gate checks only
  a tent's own ring.
- **Minor:** the `check_levels` line "tent marker is walk-through" tests a key no layout has, so it
  can never fail.
- **Minor:** the 39 mirror mutants live only in the economy designer's temp folder.
- **Pattern: check the data side of every "refuse alike" or "equal" comparison.** Run each refusal
  case through the Python mirror alone. If both sides miss a refusal, the comparison still reads
  "equal". In Wave 2 all 43 refused.
- **Pattern: a layout object that does not collide is invisible to every gate built on
  `solids_of`.** Check every post of the camp against it by hand, not only the posts of its own
  group.
- **Pattern: a claim of "proved by N mutants" needs the driver in the repo.** Otherwise nobody can
  re-run it.
- **Probe recipe:**
  - Import `check_stage_mirror` / `check_levels` / `sim_range` from a scratchpad script (each guards
    `__main__`).
  - Get the context from `sr.level_context()`.
  - Get the layout from `sr.load_level_layout(name, combat.player.rescue.below)`.
  - Get the posts and kinds from `sr.group_posts(d)` and `check_levels.member_kinds(d)`.
- **Verified:**
  - The population rule really bounds the peak: the queue is held to
    `AliveOn(floor) < stage.maxAlive`, summons top up, and `aliveCount` drops at death.
  - The sim omits the director's elite from `wave_stock` safely, because `check_levels` refuses
    `eliteKind` in a level file.

## Wave 2, fix-diff check (2026-10-14, diff f40509a..cdad4f4): 0 Critical, 1 Major, 2 Minor
Findings are in `docs/prompts/l1b-w2-review/fix-diff.md`.

- **Major: the server-only leniency also runs on the client.**
  - `SwingGate.Judge`'s "landing ahead" branch was meant only for the server's trailing copy.
    It has no `lag > 0` guard, and the client calls it with lag 0.
  - A swing in the last `fallSpeed × 0.1` of any fall is therefore allowed as a second air
    swing. The touchdown then does not clear, so the next jump's swing is dropped.
  - With held Space, 20–35% of hops get no swing at all. That is exactly the checklist's
    "Bug:" line.
- **Pattern: a leniency parameter (lag, slack) that one side passes as 0.** Check that "0" really
  turns the lenient branch off. The fixer's claim "an honest client's gate refuses it" was untrue.
  The harness only swung at the apex, so it never reached the window.
- **Minor:** the same turn window on both sides lets a double jump 6–7 studs up clear the client
  but not the server's 20 Hz copy. The client's window must be stricter by one server sampling
  step.
- **Minor:** `StageFlow.TentOwesRouse` is not in `check_stage_mirror` `NEEDED` (the Wave 1
  pattern again).
- **Probe recipe (pure modules, nothing in the worktree):**
  1. `git show <sha>:src/shared/SwingGate.luau > <scratch>/SwingGate.luau`.
  2. Write a probe with `require("./SwingGate")` and run `tycoon\tools\bin\luau.exe probe.luau`
     from the scratch dir. Luau CLI resolves the relative require.
  3. Integrate a jump at 240 Hz (g 196.2, v0 √(2·g·18)) and sample it at 60 Hz. Model the
     server copy as 20 Hz linear interpolation plus a buffer.
  4. To compare the fix, patch a copy with `sed` and run the same probe on it.
- **mutate.py texts:** exec the source up to `def harness(` with `__file__` set in the namespace
  (line 20 reads it) and `sys.argv = [x, root, "x"]`. At cdad4f4: 619 texts, all exactly once.
- **Verified, safe to reuse:**
  - `refreshInfo` returns the live `spawnInfo` table. Clearing `rises` after `fireAll` is
    safe, because a remote serializes at the call.
  - The client's `MovementController.IsDown` is the server's health down, relayed by
    VitalsController, not a knock.
  - `CampBrain.Step` returns before writing `inPlay` for an empty group. A tent body is added
    before the step, so `TentRouse` reads a current set.

## Wave 3, the bow (2026-10-15, diff main...l1b-wave3): 0 Critical, 0 Major, 5 Minor
Findings are in `docs/prompts/l1b-w3-reports/review.md`. Longbow damage ×0.9 (A 45, B 40 = heavyHit);
a `--bow` report and a ranged "step inside the fence" in `LevelRun.wanted`.

**Patterns:**
- **A damage number sitting exactly on a threshold is heavy only at full charge.** Bow damage is
  `minChargeFraction + (1 - min) * charge` times `damage` (`WeaponService.resolveCharge`), and the
  sim fires only full or minimum charge. Whenever a cut lands a value on `heavyHit`, give the
  charge at which it stops being heavy, before and after.
- **A sim "course" fix that moves no band also has no gate.** Ask which `expect` would go red if the
  fix were reverted. Here none would: the only ranged level row stops at camp A, and the bug was in
  camp B.
- **Compare the sim's in-play step with CampBrain's rule:** `chaseMargin` OUTSIDE the floor rect,
  rounded, or a keepAway member's reach. It is not "on the floor".

**Recipes:**
- `py` is 3.14 32-bit, and the designers' gate is `py -3.12`, 64-bit. Level runs drift about 1% per
  seed between them (PLAN:2266), so recompute a quoted ratio on both before calling a band edge.
- To get a level run's per-camp times without the report mode: `sys.path.insert(0, <wt>\tools)`,
  `import sim_range as S`, then build it the way `bow_report` does. `r["clearedAt"]` is keyed by camp
  id, and "C" on Forest Road is the locked boss room. 9 runs take about 5 minutes.
- A full `sim_range.py --check` takes about 10 minutes in the background and writes nothing.

## Wave 4, client slice (2026-10-15, diff main...l1b-wave4 at 2ec9da9): 0 Critical, 0 Major, 1 Minor
Findings are in `docs/prompts/l1b-w4-review/client.md`. Wave 4 is "no waits, no walls": regions,
the chase out of camp, every hit lands, and CampAim keeps only the gate and resting clauses.

**Minor:** touch auto-fire triggers on an awake body inside the 5° assist cone, but the shot flies
along the crosshair and pierces. It can therefore hit, and wake, a resting body of another camp
(an A chaser in front of B.fire1).

**Pattern: when a server rule stops blocking something, re-ask every client "only target X" gate
about collateral.** Wave 2's L1b-7 (BLOCKED out of play) silently covered pierce, blast, arcs
and near misses. With it gone, a gate on the trigger no longer bounds what the shot hits.

**Verified, safe to reuse:**
- The wire's `resting` bit is `held or state == "rest"` (`CrowdService` about :1270).
  - Homeward bodies and stood-down rushers are takeable.
- `applyFloors` runs before `SetPhase` in `onRunState`. A run leaves `lobby` only in a RunState
  that carries the floors, so a "floor not yet told" body is never shootable.
- RunState is sent at `stateHz` with whole `floors` every time, so per-floor data costs
  bandwidth all run long. In Wave 4 that is 15 cells twice.
- Read-only client gates: `py tools/check_compile.py --counts`, then `luau-lsp analyze
  --sourcemap sourcemap.combat.json` on the named files. Both write nothing in the worktree.

## Wave 4, crowd slice (2026-10-15, diff main..l1b-wave4 at 2ec9da9): 0 Critical, 1 Major, 4 Minor
Findings are in `docs/prompts/l1b-w4-review/crowd.md`.

**Major: `closing` is stamped from the desired seek speed, so it never clears.** Several rushers
seek one region-clamped edge point with stop 0, and separation keeps all but one off it. They seek
forever, so the group never stands down or leashes. This happens below a drop (with a hit every
under 8 s) and under the lookout ledge (known by sight).
- With 1 fodder the group goes home at 5.9 s. With 2 or more it never does.
- The sim never showed it: the stand-down was "proved on Step timelines" only.

**Patterns:**
- **A "still moving" flag built from desired velocity is wrong whenever bodies share a goal.**
  Separation makes desire permanent. Judge "arrived or still closing" from progress toward the
  goal, and probe with 2, 4 and 6 bodies, not 1. Every single-body harness case passed.
- **A forced state change that skips the "not striking" guard freezes a mind.** Here `Forget`
  sent a group home mid-windup.
  - `integrate` stops thinking for a group not in `fight`.
  - `CrowdBrain.Commit` counts striking minds even while they rest, so the frozen mind holds a
    `perPlayer` place for good. The probe showed 1 of 2 strikes allowed against that player.
  - Grep every new path into home or rest for the leash's `not striking` guard.
- **A non-convex region breaks "in flat reach ⇒ go".** A brute with lane reach 22 charges into
  the U-bend's 6-stud void, with a runway of about 0, and never walks round.
- **A deleted case can leave an OLD mutation alive.** Here "a group walking home engages" passes
  without it. Apply old mutation texts to a snapshot whenever a wave deletes checks.
- **A per-step heal at the post is invulnerability** when the group stays in `fight`, here a
  stood-down rusher while its shooters fight.

**Probe recipe (CrowdService internals, nothing in the worktree):**
1. A scratch `build.py` imports `run_harness`.
2. It takes `R.prelude(WT)` and replaces `"\nreturn CrowdService\n"` with `CrowdService._camp = camp`
   added before the return.
3. It appends every `R.TESTS` file with `VERDICT` stripped, then the probe, wrapped in
   `L1BC.crowdGroup`.
4. `W4C.enter()` gives the U-region fixture. `W4C.uBend()` is the real RoadAB1–5.
5. To place a group: `W4C.place(posture, points, kinds, over)`.
6. To read a group's brain: `Crowd._camp.groups[g].brain`.
7. To hit as a player: `Crowd.Damage(id, amount, userId, nil, nil)`.

## Wave 4, run slice (2026-10-15, diff main..2ec9da9, branch `l1b-wave4`): 0 Critical, 0 Major, 3 Minor
Findings are in `docs/prompts/l1b-w4-review/run.md`. Wave 4 is the shared chase region, the pace
tent, the clear on fielded raiders and N's approaches. B's code matched the contract, the harness
passed 2,252 checks, and all 21 of B's mutations were caught.

**Patterns:**
- **A rule kept "unchanged" can rest on assumptions the wave broke.** `SafePoint` reads
  "a group of floor i is busy" as "there is a fight at checkpoint i", and treats `home` as
  harmless. Once groups chase along the road and `home` turns back, both readings are wrong.
  Grep every consumer of `Busy()` and `awakeGroups` whenever group location or state semantics
  change.
- **A bound or clause that the shipped data never exercises is unpinned.** Two cases here:
  - "before the locking camp", when the lock is always the last zone;
  - "tent units count", when the residents already field the widest and longest kind.

  Prove each with a one-line mutation on a scratch copy.

**Forest Road facts:**
- The plateau roads are 16 wide over void down to `killY` −13, so a fall during a road chase
  triggers the rescue, which goes to `SafePoint`.
- Checkpoints: A (−150, −44) on RoadAB1, B (110, −44) on RoadBC1. Walking the road always
  reaches them (`checkpointReach` 8).
- `Begin` puts the party in step "armed" when the first stage is the locking camp.

**Recipe:** to run mutations, use `mutate.py <scratch-snapshot> <exe> "l1b w4:"`, which takes
about 2 minutes. The verdict is "MUTATIONS: n run, 0 not caught".

## Wave 4, data slice (2026-10-15, diff main..2ec9da9): 0 Critical, 3 Major, 4 Minor
Findings are in `docs/prompts/l1b-w4-review/data.md`. Every gate was green, and the Region and
CampBrain mirrors matched rule for rule. All three Majors came from probes the gates never ran.

**Majors:**
- **Lunges through the cliff.** Road5's cell runs to the lip of the climb.
  - Think measures reach on the flat. VitalsService's height test (`feet − floorY ≤ height`) has
    no lower bound except for the lob.
  - So the fodder at the lip hit a player standing at the foot, 8 below. Checklist step 2 says
    "stand below".
- **The tent's pace clock was spent before the step that tests it.**
  - `busySeconds` is cumulative. With A's pace 15 s and lead 0.2, the camp is never ahead again
    after 12 s of busy time.
  - The checklist's walk-out and lose (steps 2–3) burn 17+ s, so step 4's "at 4/4 a raider comes
    out" cannot happen.
- **The sniper band passed only on its script.** The scripted sniper idles 10 s below the drop.
  Going straight to the ledge earned 35–42k cash a minute against the mission's 24–26k.

**Patterns:**
- **A scripted adversary in a "must earn less" band:** run its strongest course (no wasted
  phases) before believing the band.
- **A cumulative clock in a checklist:** replay the checklist's order in the simulator. Bands
  measured on a fresh camp miss the state that earlier steps leave behind.
- **A chase region that ends at a drop or a ledge:** check every ground-shape hit rule against
  feet above and below the crowd floor. Rules written as "nothing stands below the floor"
  break first.
- **Perch gates:** check what they skip, not only what they test. Two gaps here:
  - tops over `sightAbove` were skipped, though no shooter answers there (Reachable needs the
    band);
  - floor-height ground off the region was skipped.

**Probe recipe:** the flow is the same as `bow_report`.
1. `sys.path.insert(0, <wt>\tools)`, then `import sim_range as S`.
2. Build the run: `S.level_context()`, `S.resolve_level(...)`, `S.load_level_layout(...)`,
   `S.level_view(...)`.
3. Make a policy: `dict(S.THREAT_POLICIES["sniper"], weapon=(bow, None))`.
4. Patch module constants (`S.SNIPER_BACK`, `S.SNIPER_BELOW_SECONDS`) to move the course.
5. Run `S.LevelRun(view, hp, ctx, level, layout, diff, policy, seed).run()`.
6. Read `run.tents[*]["state"]["busySeconds"]`, `run.log` (hits on him) and `r["scene"]`.

For gate mutations, `git archive HEAD src tools | tar -x` into the scratchpad, edit the copied
JSON, and run `py -I <copy>/tools/check_levels.py --no-plan`. The 3.12 and 3.14 Pythons gave
identical lose distances here.

## Wave 4, fix-diff check (2026-10-16, diff 2ec9da9..e428e85): 0 Critical, 1 Major, 2 Minor
Harness 2,337 PASS, mirror_mutants 90/90 caught (11 min), mutate.py 724 texts all exactly once,
check_levels / stage mirror / sim_combat / compile / luau-lsp / stylua / selene clean.

- **Major: two rules for one question read different heights.** `CampBrain.Melee` judges the
  LIVE root (`Seen.root`), `CrowdBrain.reaches` judges the rest surface (`restY − lift`). A player
  hopping at the foot of the climb enters the melee band for ~4 steps a hop: no stand-down
  (anyMelee), no leash (anyReach), and no windup (reaches). Probe: still player, home at step
  112; hopping (with or without hits), never home in 30 s, 4 of 4 packed at the lip.
- **Pattern: when a fix splits one judgement across two modules, check both read the same
  sample** (live vs rested, server vs client). Probe the "player jumps" variant of every
  still-player case; jumping is constant in this game.
- **Minor:** R13 covered pierce along the line but not splash (Launcher `splashRadius` 10,
  Longbow A full-draw burst `blastRadius` 5).
- **Verified:** R2 cannot block rest forever (a resting member never Thinks; a blow ends in
  recover; dormancy only at rest). goalGap is stale only across goal-less steps (one false
  step). Range hash case still passes, so R6/R14/R15 did not move the P4 range set.
- **Recipe (hop probe):** scratch `build.py` = `R.prelude(snap)` + every `R.TESTS` file with
  VERDICT stripped + probe; inside `L1BC.crowdGroup`, `W4C.enter()`, `W4C.place(...)`, set
  `root.Position` per step on a parabola (v0 84, g 196.2 at 15 Hz), count `seen(id).state`.

See [[p5-missions-review]] and [[p4-enemy-roles-review]].
