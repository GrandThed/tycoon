# L1b Wave 1 fix round — B (the run)

## Done so far
- B1 (Major, downed member): `StageFlow.StandsUp(plan, state, input): boolean` (pure): steps travel/armed/gate,
  `FieldClear` true, some `input.standing[i] == false`. WaveService `advance` asks it after `execute` and
  `standUpOnRoad` stands every downed fighting member up AT THE SAFE POINT (not where they fell: beside the group
  that downed them, which would see them and wake again). Chose a query, not a new Action kind, so
  `check_stage_mirror.py`'s Advance comparison (its "downed root, quiet road" tick) is unaffected.
- B2 (skip pays nothing): `Action.skipped: boolean?` on `open`; set by `Skip` ("stage" in a fight, and "boss" for
  every camp it passes). WaveService `campCleared(zone, skipped)`: a skipped open does SetCamp + banner only.
- B4 (safe point out of reach): `StageFlow.SafePoint(plan, state, busy?, threats?: { CampBrain.Shooter }?)` skips a
  checkpoint within a threat's reach (flat). `StageFlow.LongestReach(def)` (pure). WaveService tracks
  `run.awakeGroups` from `DrainGroupEvents` (`to` rise/fight = the event's ids) and builds threats from
  `CrowdService.Get` (living) + `Tuning.Get().crowd.kinds`; one `safePoint()` helper for all five call sites.
- B3 (progress pinned in every live step): cases in C's countdown (a root on C's checkpoint: `reach`), C's fight
  (A empties: `campClear` zone 1) and C's breather (B empties: `campClear` zone 2).

## Harness cases (tests_l1b.luau, new group `l1b fixTests`, plus two checks in safeTests/walkTests)
StandsUp (road yes; awake / queued / nobody down / no standing list no; one of two down yes; countdown as road;
fight and breather no); progress in gate/fight/breather; SafePoint with threats (edge counts, 9.99 does not, flat
not 3D, both in reach -> start, mixed with busy, countdown entry); LongestReach; the stage skip's open is
`skipped`, a played clear's is not; a boss skip passing a second locking camp marks its open `skipped`.

## Mutations (FIX_B_MUTATIONS in mutate.py, 11, all caught on a filtered run)
StandsUp in the boss room's fight; StandsUp ignores the field; StandsUp with nobody down; a stage skip's open not
skipped; a cleared camp's open skipped; a boss skip's passed camps not skipped; progress only on the road (the
review's exact mutation); SafePoint ignores the threats; a threat's reach judged in 3D; reach edge left out;
LongestReach takes the last attack.

## Gates on my files
stylua --check, selene (0/0/0), check_compile PASS (152 files), luau-lsp src/combat on a fresh combat sourcemap:
clean.

## For the other owner / the lead
- Contract text (lead): `StageFlow.SafePoint(plan, state, busy?, threats?: { CampBrain.Shooter }?)`; new
  `StageFlow.StandsUp(plan, state, input): boolean` and `StageFlow.LongestReach(def?): number`;
  `Action.skipped: boolean?` on `open`. LongestReach counts every attack in the list (CrowdService's own
  `longestReach` stops at CrowdCodec.MAX_ATTACK): the safe point can only be more careful.
- economy-designer: `check_stage_mirror.py` needs nothing (StandsUp is a query, not an Advance action; SafePoint's
  new argument is optional). If `sim_range`'s skip mirror routes through the full `on_open` you are writing, a
  skipped `open` must pay no clear bonus (the server's `campCleared(zone, true)` pays and counts nothing).
- Design choice to confirm (lead): the stand-up MOVES the member to the safe point rather than standing them where
  they fell (next to the group that downed them, which would see them and wake at once).

## B5: A's mutations registered
`FIX_A_MUTATIONS` in mutate.py: A's seven entries verbatim from fix-A.md (square corners, no engaged hold, the hold
never ends, Engaged reads the last step only, and crowd.md's three `home` survivors). No existing entry changed.

## Verdicts (run one after the other, worktree state including A's, ui's and the economy-designer's edits)
- `HARNESS: PASS (1,571 checks, C:\Users\benja\Desktop\tycoon-p5\tools\crowd_harness)`
- `MUTATIONS: 513 run, 0 not caught` (495 before + 11 B + 7 A)
