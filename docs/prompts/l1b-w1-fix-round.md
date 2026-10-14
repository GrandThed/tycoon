# L1b Wave 1 — fix round (the lead's rulings on the four-slice review)

Review files: `docs/prompts/l1b-w1-review/{crowd,run,client,data}.md` (findings with file:line and
failure scenarios). The base is `e2479c3`. The contract (`docs/INTERFACES.md` from line 11369)
stands except where a ruling below changes it. Totals: Critical 0, Major 4, Minor 15.

Same rules as the contract's "Ownership": your files only; "For the other owner" lists; no git;
kill only your own PIDs; every new rule pure with a harness case and a mutation. Check `git status`
and `git diff e2479c3` first: the work may be partly done. Write your report to
`docs/prompts/l1b-w1-reports/fix-<owner>.md` section by section as you go.

## A — the crowd (`src/shared/Types.luau` for `CampRulesConfig.engagedHoldSeconds: number` only, `CampBrain.luau`, `CrowdService.luau`, `CrowdBrain.luau`, `tests_l1b_crowd.luau`)

1. **Major (crowd.md, `CampBrain.luau:297-302`): in-play with rounded corners.** A target is in
   play when its flat distance to the camp's floor RECTANGLE is at most `camps.chaseMargin` (0
   inside), not when it is inside the rectangle grown by the margin. Same height band. Harness
   cases at an edge and off a corner; a mutation back to the square test must be caught.
2. **Minor (crowd.md): engaged holds.** `Engaged` (and the in-play memory behind L1b-20's rescue
   rule) stays true for `camps.engagedHoldSeconds` (new key, 1.5 s, on the crowd's step clock)
   after the player was last in play for a group in `rise`/`fight`. A fall from a fighting camp
   (0.4–0.6 s to `killY`) then gets no get-up i-frames, and the phone Abandon button stops
   flickering at a camp's edge (the client needs no hold of its own). Harness case + mutation.
3. **Minor (crowd.md): `home` untested.** Cases reading `Awake`, `Busy`, `Engaged` while a group
   is `home`; the three surviving mutations named in crowd.md must be caught.
4. Give B the exact text of every new or changed mutation (B owns `mutate.py`).

## B — the run (`StageFlow`, `WaveService`, `ArenaService`, `LevelService`, `LevelGeometry`, `DebugService`, `src/shared/Combat.luau`, harness runner, `mutate.py`, `tests_l1*.luau` except A's)

1. **Major (run.md): a downed member stands up when the road's field is clear** (L1b-19's
   definition: no group in `rise`/`fight`/`home`, nothing queued), outside the locking camp's
   fight. Pure rule in StageFlow, harness case, mutation. Revive by a teammate stays L5.
2. **Minor (run.md): a Studio skip pays nothing.** A skip's `open` neither pays `clearBonus` nor
   adds to `stats.wavesCleared`.
3. **Minor (run.md): pin progress in every live phase.** A case + mutation that catches limiting
   `progress()` to travel/armed.
4. **Minor (data.md 1): the safe point skips a checkpoint within reach.** `StageFlow.SafePoint`
   skips a checkpoint within the longest attack reach (flat) of a living member of any group in
   `rise`/`fight`, plus that group's floor rule already in L1b-18. Case + mutation.
5. Register A's new and changed mutations in `mutate.py` (A sends the text through the lead; if
   it is in `fix-A.md` when you get there, take it from there). Run the harness, then mutate.py.

## ui-engineer (`src/combat/client/**`, `Theme.luau` add-only)

1. **Major (client.md 1): phone auto-fire never wakes a camp from range.** `targetOnAuto`
   (InputController) picks a body whose spawn info has a camp floor only when the local player is
   in play for that floor: flat distance from the root to the floor rectangle ≤ `camps.chaseMargin`
   (read the config; same rounded-corner test as A's rule 1), in the height band
   (`camps.sightBelow`/`sightAbove`). Bodies without a camp floor (boss room waves, range) are
   unchanged. L1b-4 stands for deliberate shots.
2. **Major (client.md 2): the header text is "Camps 1 / 3"** (fits the 74 px label).
3. **Minors:** release CampFx's Heartbeat connection when it has nothing to draw (or on teardown);
   clear the "Checkpoint" notice when the phase becomes `summary` or `lobby`. The Abandon flicker
   is fixed server-side by A's rule 2: add nothing for it.

## economy-designer (`Config/*.json`, `Layouts/Levels/ForestRoad.json`, `sim_range.py`, `sim_combat.py`, `check_levels.py`, `check_stage_mirror.py`, `stage_mirror.luau`, `BALANCE.md` "L1b")

1. **Major (crowd.md) + Minor (data.md 2): the chaseMargin gate.** With rounded in-play corners, a
   body clamped in a corner stands `√2 × radius` from the corner, so the gate is
   `chaseMargin ≤ reach − √2 × radius` for every resting rusher kind at every difficulty
   (fodder: 4.5 − 1.84 = 2.66). Set `camps.chaseMargin` to 2.5. Also gate perches (any standable
   top) inside the margin band. Mirror the rounded test in `sim_range.py` and `stage_mirror`.
2. Add `camps.engagedHoldSeconds` 1.5 to `Combat.json` and the mirrors (A's rule 2).
3. **Minor (data.md 1): a gate** that every checkpoint lies outside every resident shooter's
   attack reach from its post (and patrol points), at every difficulty; move A's checkpoint if
   it fails.
4. **Minor (data.md 3): mirror `clearBonus` fully** in `sim_range.on_open` and
   `sim_combat.level_pay`; prove it with a non-zero bonus in a scratch run (assertion 21 green).
5. **Minors:** BALANCE "L1b" shows the Wave 1 clear band 2.5–4 min as the lead's ruling, PASS;
   the Hard patrol in B walks at its slowest member's pace (data if possible, else "For the other
   owner"); flag Timber per minute (+~75% on L1) in BALANCE for Ben.
6. Carried to Wave 2 (write it in BALANCE's open list): post spacing gated beyond fires.
7. Run every gate of yours after the others' edits land if you can; report what is red and whose.
