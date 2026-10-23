# L4 W2 fix round (the lead's rulings on the four-slice review)

Worktree `C:\Users\benja\Desktop\tycoon-p5`, branch `l4-w2` (review base afdce67). Findings:
`docs/prompts/l4-w2-review/1-server.md`, `2-scenery.md`, `3-raiders.md`, `4-data.md` (0 Critical, 2 Major, 14 Minor, 14
suggestions; two Minors are the same finding twice). The contract `docs/prompts/l4-w2-contract.md` and the kickoff stand;
these rulings override them where they differ. A full `mutate.py` run on afdce67 is going in `tycoon-p5b`: never edit
there and never run `mutate.py` anywhere but in this worktree, filtered, by D2 only. Every agent: `git status` and `git diff`
first, commit nothing, kill only its own PIDs, LF files, report to `docs/prompts/l4-w2-fix-reports/<role>.md` with a "For
the other owners" section (file, old text, new text; signatures; the deciding lines to pin, whole, with indentation, and a
mutant for each). Tools as in the kickoff.

## Rulings

**K1. A model's blow reaches where it hits (slice 3 M1).** For an attack shape with no ground tell (the lunge, any `jab`),
the drawn weapon's flat reach at impact is **at least the placeholder's drawn front at impact** (the look Ben played with),
and never more than the attack's reach + 0.5. First try a longer step and a forward lean below the neck so the head rule
holds; if that cannot reach, the body may slide forward during the strike window only (from the blow's start to its
recover), as the placeholder did, and the head rule is waived for that window alone (say so in the rule). `raiderpose.py
--check` gains the lower bound for every no-tell shape of every kind; the mirror covers the new keys.

**K2. The Chief's sweep is drawn where it hits (slice 4 m1).** Re-key the Chief's sweep arm (config arm keys) so the
hammer sweeps the whole wedge (every 15° sector of the 150°) at a reach of at least `range` − 0.5 inside the arc;
`impact_reach` measures inside the arc only and checks every sector. If the keys cannot reach 17, D1 sets the sweep's
`range` (and if needed its angle) to what is drawn and re-measures the bands.

Owner of K1 and K2: **ui-engineer B**, who for this round holds both sides of the pose: `RaiderPose.luau`,
`tools/testfit/raiderpose.py`, and the arm keys and rig numbers in `tools/assets/out/RaiderModels.json` and
`src/shared/Config/RaiderModels.json` (no mesh changes: nothing re-uploads). The other raider items too:
- **K3 (slice 3 m1):** fill the model pools in the lobby camp before a run (from the level's `Plan.kinds`, spread over
  frames); a body whose model is not built yet draws the placeholder and switches when it is; when the plan exceeds the cap,
  split it in proportion to the counts, never alphabetically.
- **K4 (slice 3 m3):** move the lean split and the anchor height into `RaiderPose` so the mirror covers them.
- **K5 (slice 3 m2):** `Figures.lookOf` refuses a kind whose head point is not the server's crit head (`height -
  headRadius`, within 0.01): placeholder and one warn.
- Suggestions taken: aim-assist and auto-fire use the dropped body sphere for a seated body (slice 3 s1); the held weapon's
  grip comes from `WeaponModels.json`, not from `Base` (s2); `SETTLE` and `HELD_STAGE` read the one constant each (s3).

**K6. The faithful R8 (slice 4 M1).** `R8_FIGHT = "pair"`: the sniper fights the rest with the same gear as the fighter, so
the two runs differ only by the spot (Ben's "against fighting it all with the same gear"). It passes today with margins of
1.3-5.7%. Add one `check_levels_mutants` SIM_CASE sized to that margin (a spot that earns a few percent more must turn red)
and keep the two clock mutants. Print the sword-alone and the old gated tables ungated. Owner: **D1**; update BALANCE.md.
D1 also: K2's range if needed; the simulator's seat uses the mirrored `cb_shows` and `HitShapes.SeatStep` is compared in
`check_stage_mirror.py` (slice 4 m4).

**K7. A dressed level is all or nothing, on the server and the client (slice 1 m1, m2, s2; slice 2 m1, s2; slice 4 m2).**
- **luau-engineer A:** the dress decision is one pure function in `LevelDress` whose answer carries the hash (so "dressed
  with no hash" cannot be written), tested in `tests_l4w2.luau`; `Accept` refuses a dress whose `props`, `effects`,
  `hide.blocks`, `hide.camps` or a camp's role list is not the right shape (tests for each, the three untested guards
  included); `LevelService` calls `Accept` under `pcall` and treats a throw as a refusal (grey, one warn); `DressHash` is set
  before `Dress`; a mesh counts as present only if its template holds a MeshPart with a non-empty MeshId.
- **ui-engineer A:** the whole build thread runs under one `pcall` that calls `fail()` on any throw; in the failed view the
  server's tree-line walls are drawn (the grey level's look) so no invisible wall fences a player; `evaluate` waits for
  `game.Loaded` and never caches a nil answer; a pure decision module for `evaluate` with tests in a new
  `tools/crowd_harness/tests_l4w2_scenery.luau` (ui A owns it this round).
- **D2:** whole-line pins and mutants on every deciding line both reviews list (`LevelService` :696, :710, :714, :751, :756,
  :778, the wall's `Transparency`, `WeaponService` :828's `restDrop`, `state.failNextDress`, `layoutName`, the
  `InputController` drop lines, the scenery's fail path and its four `seal` flags), re-aimed to the engineers' final lines.

**K8. Mood B only in the level (slice 2 m4).** The forest's light applies while the local character is in the level, not
while waiting in the lobby camp during a run (Ben: "the lobby and the hub untouched"); re-checked on `Placed`. Owner: ui A.

**K9. The camera never passes the hidden rock (slice 1 m3).** In a dressed level the shoulder camera's collision stays on
during the `summary` and `ended` phases (or the zoom is capped there). Owner: **ui A** (`CameraController.luau` joins its
files this round).

**K10. The sight gate measures the widest drawn body (slice 4 m3).** `walled_bodies` takes the largest drawn reach over every
kind sharing a post, not the widest radius's model. Owner: **D2**. D2 also asserts the head point in `raider_frames.py`
(K5's offline half).

**Left, with reasons:** the areas', cones' and blasts' standing sphere on a seated body (slice 1 s3: generous to the player);
FeedbackController's pellet tracers (slice 3 s4: cosmetic); the map row's phone text (slice 2 s3: Ben's emulator look
decides); the prop set map in Theme (slice 2 s4); the walls' redundant "can" checks and `path_blocked`'s lenient dropping
legs (slice 4: no shipped leg drops; noted for later levels); the open tunnel at Hard bow T4 passes at x0.964 (noted).

## Order

luau-engineer A, ui-engineer A, ui-engineer B and D1 in parallel (D1's `--r8 --check` takes about 54 minutes: run it in the
background once K6 is in; re-run K2's bands after ui B's report if the range moves). D2 after the four have reported. Then
one fix-diff reviewer, then QA (the full `mutate.py` on afdce67 covers the untouched entries; filtered runs and the stale
check cover the fixes).
