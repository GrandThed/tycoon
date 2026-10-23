# L4 W1b fix round (the lead's rulings on the three-slice review)

Worktree `C:\Users\benja\Desktop\tycoon-p5b`, branch `l4-w1b` (review base 1ae8bfb). Findings:
`docs/prompts/l4-w1b-review/1-server.md`, `2-run-client.md`, `3-data.md` (0 Critical, 0 Major, 9 Minor, 9 suggestions).
The contract is still `docs/prompts/l4-w1b-contract.md`; these rulings override it where they differ. Every agent:
`git status` and `git diff` first (work may be partly done), commit nothing, kill only its own PIDs, report to
`docs/prompts/l4-w1b-fix-reports/<role>.md` with a "For the other owners" section (file, old text, new text for every
line a pin or a mutate entry reads). Tools and the Luau CLI as in the contract §7-§8.

## Rulings

**F1. The dash keeps today's feel: hold the decision (slice 1 m2, m3; slice 3 m1).** The review measured that proving
a dash on the server's ring moves the latest press that still dodges 45-126 ms earlier at ping 0.1 (Studio cannot show
it), and that the outcome depends on the order of two Heartbeat handlers. Ruling, the contract's own §4.5 follow-up:
- **A hit whose decision falls while a dash claim of that player is pending, and which that claim's window would cover
  if proven, is held** until the claim resolves: proven → voided as today, lapsed → it lands. The hold never exceeds the
  claim's lapse time (`dashSeconds + lookback` after the claim). Nothing else about a hit changes (the commit rule, the
  shape at T, the lag).
- **One order every frame:** pending claims are proven before hits are decided, in the same Heartbeat, by one handler
  (or Vitals asking WeaponService to prove first); never two handlers on one signal.
- **The per-frame decision moves into pure `DashProof`** (a `Step` over the pending claim, the ring, now) so the harness
  runs the real thing (slice 1 m1, slice 3 m2).
- Result to prove in the harness (tests in `tests_l4b.luau`): at ping 0 and 0.1, at 60 Hz, 20 Hz and 20 Hz bunched,
  over phases, a dash pressed at or before the impact on the player's screen dodges, as before W1b; a forged still dash
  never does; a wall dash never does; a held hit lands at the lapse when unproven.
- Owners: **luau-engineer A** (`DashProof`, `WeaponService`, `VitalsService`, `tests_l4b.luau`); **designer** mirrors it in
  `sim_range.py` (a dash's proof time = start + the ring's latency, and the hold), then reports the R8 row and every
  Forest Road gate line that moved, in `BALANCE.md` (the claim "byte-identical" is withdrawn unless it is true again).

**F2. Pin what makes L4B-7 hold (slice 1 m1, slice 3 m2).** With F1's pure `Step` most of this is tested for real; pin and
mutate what stays in `WeaponService` and `OnDash` as whole lines (with indentation): the verdict branch, the lapse branch,
the no-root clear, `OnDash` granting nothing (neither `openIframes(` nor `GrantIframes`), the down refusal. The four
review mutants of slice 3 m2 and the two of slice 1 m1 must each be caught. Owners: A writes the lines, **designer** the
pins and mutants.

**F3. Pin the cells-once lines (slice 2 m1).** Whole-line pins and mutants for the client's `applyFloors` (the
`RunFloors.Merge` line, `st.floorsSeq = seq`, the seq it is called with, merging against the held list) and the server's
`if cellsWent then` and `sent = table.clone(runState)` lines. The seven review mutants must each be caught. Owners: ui and
B confirm their final lines in their reports; **designer** writes the pins and mutants.

**F4. Apply the floors first (slice 2 m2).** `onRunState` applies the floors right after `isRunState`, before the
new-level branch, so an error there cannot lose a run's cells. Owner: **ui**.

**F5. Say what L4B-7 stops (slice 1 m4).** It stops a request-only forger and a dash into a wall, not a modified client
that moves its own root (there is no movement anti-cheat in this game; such a client can already step out of any shape).
Owner: **lead** (contract and PLAN).

**F6. Tie the mentor pay to the game (slice 3 m3).** `check_stage_mirror.py` compares the real `Combat.MentorBonus`
against the Python `mentor_pay` on a grid, and `WaveService.payMentors`' deciding lines are pinned and mutated (the
three review mutants caught). Owners: B confirms the lines; **designer** writes the mirror, pins and mutants.

**Suggestions taken:** B checks `cellsSent[userId] ~= seq` before calling `Attach` (slice 2 s1); ui adds one hint line to
the Studio debug strip's bottom reserve (slice 2 s2); A tests DashProof's edges (exactly the threshold, a negative
lookback, proof against lapse in one frame) and pins its docstring promises as tests ("a proof beats a lapse"; RunFloors'
"every floor is new") (slice 1 S2, slice 3 S1); the designer turns the two real-map checks that pin today's map into rules
(slice 3 S2) and sets the hub stub's `waves` to 2, what a Forest Road clear counts (slice 3 S4). **Left:** the hub's stale
DebugBots comment (W3's hub pass); the fixture copies' missing guard price (no rule reads it); Leap Smash and Impale Dash
keep their server-granted i-frames at the cast (server-validated casts with cooldowns; told to Ben).

## Order

luau-engineer A, luau-engineer B and the ui-engineer in parallel; the designer after all three have reported (it needs
their final lines). Then one fix-diff reviewer, then QA (full gates, the full `mutate.py` run alone in this worktree).
