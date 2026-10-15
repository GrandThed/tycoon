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

See [[p5-missions-review]] and [[p4-enemy-roles-review]].
