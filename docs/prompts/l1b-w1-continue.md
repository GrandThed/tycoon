# L1b Wave 1 — continuing B (the run) and the economy-designer

The first two agents for these roles were cut off by the session limit mid-task on 2026-10-14.
Their partial work is committed in `55dcca0` ("work in progress"). The contract is unchanged:
`docs/INTERFACES.md` from `# L1b contracts — the living road` (line 11369) to the end.

**Find what is done:** `git diff 8e8990c 55dcca0 -- <your files>` shows everything written since
the contract, by all owners. Compare your files against the contract's sections for your role
and the "Definition of done (Wave 1)"; finish what is missing, fix what is wrong. Do not redo
what is right.

Already finished by others (read their reports in `docs/prompts/l1b-w1-reports/`, do not edit
their files): luau-engineer A (Types, CrowdCodec, CampBrain, CrowdService, CrowdBrain,
`tests_l1b_crowd.luau`, `tests.luau` call site) and the ui-engineer (client).

## Items routed by the lead (both agents had received them; check they are in)

For **B (the run)**:
1. `mutate.py`: add `CampBrain.luau` to `FILES`, paste A's 36 new entries, replace the 11 stale
   entries A names (8 CrowdBrain, 3 CrowdService), update the `FLOOR` and `DIED` constants. The
   exact Python is in `A-crowd.md`. StageFlow, Combat and LevelGeometry entries that your own
   edits made stale are yours to fix.
2. `Types.PartyMember.engaged: boolean?` exists (the lead added it). Set it in
   `ArenaService.memberEntry` from `CrowdService.Engaged` for that member (true while in play for a
   camp group in `rise` or `fight`; false in the lobby). The ui-engineer hides Abandon on touch
   while it is true (routed after you finish).
3. A's rulings, accepted: `Busy` / `Engaged` count only groups with a living member; CampBrain runs
   on the crowd's `simTime`.

For the **economy-designer**:
1. Mirror A's executor details in `sim_range.py` and `stage_mirror.luau` where they apply: a body
   walking home or patrolling stops at half of `camps.homeTolerance`; a held group is stepped first
   (only its in-play set refreshes), then released, with no transition that step; CampBrain's clock
   is the crowd's step clock; the heal is applied before `Step`; `Busy` / `Engaged` count only
   groups with a living member.

## Known state at the cut-off

- The full harness ran 1,397 checks with 1 failing: the Forest Road Part count (LevelGeometry
  against `check_levels.py`). Settle it between LevelGeometry (B) and the layout/`check_levels.py`
  (economy-designer): whichever side is wrong against the contract fixes it; if you cannot tell,
  report it.
- B was writing mutations for StageFlow (the population cap in `Plan` and `Validate`) when cut off.
- The economy-designer was about to run the level sections of `sim_range.py` for the first time.

## Report

Write to `docs/prompts/l1b-w1-reports/B-run.md` or `econ-data.md` as you go (a section at a time),
so another cut-off loses nothing. Same rules as the contract's "Ownership": your files only,
"For the other owner" lists, no git, kill only your own PIDs.
