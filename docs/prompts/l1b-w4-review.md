# L1b Wave 4 — review brief (four slices)

Read-only review of `git diff main l1b-wave4` at the branch head 2ec9da9, in the worktree
`C:\Users\benja\Desktop\tycoon-p5` (branch `l1b-wave4`). Every Bash call starts with
`cd /c/Users/benja/Desktop/tycoon-p5 && `. Edit no source file. Write your findings to
`docs/prompts/l1b-w4-review/<slice>.md` as you go; if the Write tool refuses a report file, put the
whole findings list in your final message instead. Python is `py`; the harness needs
`C:\Users\benja\Desktop\tycoon\tools\bin\luau.exe` as its second argument. Do not run `mutate.py`.

## Read first

- `CLAUDE.md` (code rules), `docs/MISSIONS_DESIGN.md` §19 with its last paragraph (Ben's rulings).
- The contract: `docs/INTERFACES.md` from `# L1b Wave 4 — no waits, no walls` to the end: the lead's
  rulings L1b-W4-1…13, the contract (14–33), "Lead's answers to the draft points" and "Lead's
  rulings on the build reports". All binding. Earlier L1b contracts bind where Wave 4 does not change
  them.
- The owners' reports in `docs/prompts/l1b-w4-reports/` (`crowd.md`, `run.md`, `client.md`,
  `data.md`): judge every decision they took beyond the contract.

## What to look for

Correctness first:
- a rule the executor gets wrong against the contract;
- a state that can stick: a group that never goes home, a rusher frozen at a door or a region edge,
  a stand-down that never clears, a body that leaves the region or walks through a fence, a camp that
  never clears because a body stands off its floor, a tent that sends after the residents are dead,
  a boss room that never closes, N that strands a party or moves it backwards, a run that never ends;
- a farm: pay from where nothing can answer, a bonus paid twice or on stock never fielded, a hit
  memory that never expires;
- `Region` (clamp, runway, door routing on the U-bends, doors on both axes, the tree) against what
  the server, the client and the simulator mirror each do with it;
- the close's forget, held residents (still BLOCKED until the close), home taking hits and turning
  back only for a reachable player, `meleeAbove`, `chaseMargin ≤ reach − √2·radius`;
- phone auto-fire (`CampAim`): never a resting body, never in the countdown, never waking a camp
  from the road by itself;
- a yield in a Heartbeat path; a remote without validation or rate limit; a crash on a nil the wire
  can deliver; the compile gate (~180 top-level locals);
- a pure rule the harness or a mutation does not actually pin (prove a test vacuous with a concrete
  mutation); a mirror that disagrees with the module it mirrors; a gate that cannot fail.

Then the code rules of `CLAUDE.md`. Ignore style that stylua/selene own.

Severity: **Critical** (breaks the playtest or loses/duplicates rewards), **Major** (a real bug a
player can meet, or a gate that cannot catch what it claims), **Minor** (the rest). Every finding:
file:line, a concrete failure scenario, a suggested fix in one or two sentences. Verify each against
the code before writing it; drop what you cannot make concrete.

## Slices

1. **crowd** — `src/shared/Types.luau` (the Wave 4 block), `src/shared/Region.luau`,
   `src/combat/server/Services/CampBrain.luau`, `CrowdService.luau`, `CrowdBrain.luau`,
   `tools/crowd_harness/tests_l1b_w4_crowd.luau`, the changed cases in `tests_l1b_crowd.luau` and
   `tests_l1b_w2_crowd.luau`, and A's mutations in `mutate.py`.
2. **run** — `src/combat/server/Services/StageFlow.luau`, `WaveService.luau`,
   `tools/crowd_harness/tests_l1b_w4.luau`, `tests_l1b_w2.luau`, `tests_l1b.luau`, `tests_l1.luau`,
   `run_harness.py`, `mutate.py` (B's and the ui-engineer's mutations, the replaced and retired ones).
3. **client** — everything under `src/combat/client` in the diff (`CrowdRenderer`, `CampAim`,
   `InputController`, `CombatUIController`). Phones at about 667 × 375 landscape; no attack button;
   no sound; the playtest checklist in the contract must be what Ben sees when he presses Play and N.
4. **data and tests** — `src/shared/Config/Combat.json`, `Config/Levels/1_ForestRoad.json`,
   `Layouts/Levels/ForestRoad.json`, `tools/sim_range.py`, `tools/sim_combat.py`,
   `tools/check_levels.py`, `tools/check_stage_mirror.py`, `tools/crowd_harness/stage_mirror.luau`,
   `mirror_mutants.py`, `docs/BALANCE.md` "L1b Wave 4". Do the mirrors copy the Luau rules exactly
   (Region, the chase, the stand-down, closing, the tent's clock, Fielded, N); do the gates fail when
   the thing they guard breaks (doors, the lock clearance, perches, the sniper's pay); does the layout
   make the checklist work (the chase out of the Pickets, the sneak past Main Camp, N's stops).

Read neighbouring slices' files when a call crosses into them, but report only findings whose fix
lies in your slice (name the other slice for anything else, in one line at the end).

End with a one-line count: `Critical n, Major n, Minor n`.
