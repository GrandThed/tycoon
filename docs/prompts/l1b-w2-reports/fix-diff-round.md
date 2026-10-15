# L1b Wave 2 fix-diff round (luau-engineer, fresh)

Brief: `docs/prompts/l1b-w2-fix-diff-round.md`. Findings: `docs/prompts/l1b-w2-review/fix-diff.md`.
Branch `l1b-wave2` at 1d53ee0, tree clean at start. No git writes.

## State: DONE (M1, m1, m2; every gate green)

## M1: the landing ahead only with a lag (DONE)

- `src/shared/SwingGate.luau` `Judge`: the lag is sanitised first, and the "ahead" branch now
  reads `if lag > 0 and airborne and state.used and state.falling and not state.ahead then`.
  The client (lag 0) never takes it: its own touchdown sample clears `used` as an ordinary
  landing. A NaN lag reads as 0, so it takes no landing ahead either.
- The false comment is replaced (the header bullet and the branch comment both say the branch is
  the server's only). fix-A.md's "an honest client's own gate, lag 0, never sends that second
  swing" was false; fix-A.md now says so in place ("Corrected in the fix-diff round").
- **A second defect the new held-hop case found (fixed here):** at the lag ceiling (0.3 s) the
  server's copy can be early in its fall, still slow, when the client sends the swing on the frame
  after its bounce. The old reach `fallSpeed x (0.1 + lag)` extrapolated today's speed, so the
  copy 0.25 s from its floor at 34 studs/s "could not" reach it inside 0.3 s: the server refused
  a swing the client had drawn (12 hops x 20 phases x 3 intervals: 1 refusal at 0.5 s / lag 0.3;
  the low double jump at 4 studs, lag 0.3: 1 refusal). The reach now counts gravity over the lag
  and the turn window at the speed the copy will have then:
  `within = fallSpeed x (W + lag) + G x lag x (W + lag / 2)`, `G` = new
  `SwingGate.FALL_GRAVITY` 196.2 (Roblox's default Workspace.Gravity; no place changes it).
  What a cheating client can gain is unchanged in kind: one swing in the last lag (+ window) of a
  fall, now counted in time rather than at the copy's current speed.
- Existing harness case re-pointed (not deleted): "a copy falling slowly far up (a double jump's
  claim) finds no landing" now runs at lag 0.1 (where it still holds); a new check states the
  ruling that at the 0.3 s ceiling the same copy (16.15 over the band, falling at 6) is inside the
  last lag of its fall and is allowed. The NaN-lag check's label now says there is no landing
  ahead without a lag.

## m1: the client's stricter turn window (DONE)

- `SwingGate.CLIENT_TURN_WINDOW_SECONDS = 0.05` beside `TURN_WINDOW_SECONDS = 0.1` (the server's).
  `Observe` gains a 7th optional parameter `turnWindow: number?` (nil = the server's), so
  `WeaponService` (not my file) is unchanged and still the server's 0.1.
- `src/combat/client/Controllers/AirSwing.luau` passes `SwingGate.CLIENT_TURN_WINDOW_SECONDS`
  to `Observe`; its header says why.

## m2: TentOwesRouse in the mirror; group_up on the drained state (DONE)

- `tools/check_stage_mirror.py`: `TentOwesRouse` added to `NEEDED["StageFlow"]`; new
  `tent_owes_cases` compares all 8 combinations of (owed, busy, awake) against
  `sim_range.tent_owes_rouse`; driver loop `data.tentOwesCases` in
  `tools/crowd_harness/stage_mirror.luau` (the driver had to change for the comparison to exist).
- `tools/sim_range.py`: `group_up` removed. `LevelRun` keeps `awake_groups`, filled by a new
  `drain_group_events()` (WaveService.onGroupEvent's rule: to rise/fight = awake, anything else
  = not) called at the start of every frame, before that frame's crowd step; `send_tents` reads
  `tent["group"] in self.awake_groups`. Why trailing: WaveService connects its Heartbeat at boot
  and CrowdService connects its own lazily at the first run, so the server's tick (drain, then
  tents) runs before the crowd step of the same Heartbeat. Roblox does not promise the order of
  two connections; the sim passed every check with the live state before this change too.
- `tools/crowd_harness/mirror_mutants.py`: three mutants on `TentOwesRouse`.

## Harness cases (tools/crowd_harness/tests_l1b_w2_crowd.luau)

New helpers on W2A: `jumpsAt` (jumps from the ground at given times), `client` (AirSwing's
samples at 60 Hz with the client window, attack held at an interval or a click at each apex,
lag 0), `server` (the copy replicated at 20 Hz, read `lag` behind, Heartbeat at 60 Hz, server
window, each sent swing judged at its claim with that lag), `airCount`, `LAGS` {0.05, 0.1, 0.2, 0.3}.

- group "swing gate: the client's late fall" (M1):
  - lag 0, 20 phases: apex swing allowed, a swing at most 4.5 studs above the band late in the
    fall refused, touchdown, walk, new jump, apex swing allowed.
  - held Space, 12 hops, attack held at 0.25 / 0.35 / 0.5 s, 20 phases: never two air swings in
    one hop, never a hop with none, and the server at every lag in LAGS refuses none of the 1,380
    swings the client sent.
- group "swing gate: the client's turn window" (m1):
  - CLIENT window = server window - 1/20.
  - double jump 6 / 6.5 / 7 studs up into 12, held attack and apex clicks, 20 phases: the client
    sends one air swing in the whole jump.
  - sweep 3.0 to 9.0 studs by 0.5, both click styles, 20 phases, every lag: the server never
    refuses a swing the client sent (and the client does count a low double jump as a landing:
    110 runs).

## Mutations (tools/crowd_harness/mutate.py, `L1B_W2_FIX_DIFF_MUTATIONS`)

1. the client takes the landing ahead too (no lag guard)
2. the client's turn window is the server's (0.05 -> 0.1)
3. Observe ignores the window it is passed
4. the landing ahead without gravity
5. the landing ahead's turn window at today's speed

All five caught on a first `"fix diff"` run.

## Gates (run one after the other, final tree)

- stylua `--check src`: clean (also `stage_mirror.luau`). The harness case files are not
  stylua-formatted at HEAD either; left as they were.
- selene `src`: 0 errors, 1 warning (shadowing `header` in `src/client/UI/LegacyPanel.luau:200`,
  not touched by this round, there at HEAD).
- luau-lsp analyze (`tools/types/globalTypes.d.luau`, fresh sourcemaps in scratch): combat
  sourcemap on `src/combat` + `src/shared`: 0 diagnostics; default sourcemap on `src/shared`:
  0 diagnostics.
- `py tools/check_compile.py`: `CHECK: PASS -- 156 files compile with Studio settings (-O1 -g2)`
- harness: `HARNESS: PASS (2,004 checks, C:\Users\benja\Desktop\tycoon-p5\tools\crowd_harness)`
- `mutate.py`: `MUTATIONS: 624 run, 0 not caught` (baseline the same 2,004 PASS; 619 + 5 new,
  none stale)
- `py tools/check_stage_mirror.py`: `CHECK: PASS` (new line `StageFlow.TentOwesRouse: 1 compared`,
  the one case holding all 8 rows)
- `py tools/sim_range.py --check`: `CHECK: PASS`; its whole output is byte-identical to a run on
  the tree before the m2 change (the trailing `awakeGroups` changes no result).
- `py tools/sim_combat.py --check`: `CHECK: PASS -- all twenty-three assertions hold`
- `py tools/check_levels.py`: `CHECK: PASS` (136 PASS lines, 0 FAIL)
- `py tools/crowd_harness/mirror_mutants.py`: `49 of 49 mutants caught` (46 + 3 new, none stale)

## For the lead / contract

- New `SwingGate` exports, not in the contract: `CLIENT_TURN_WINDOW_SECONDS` (0.05),
  `FALL_GRAVITY` (196.2), and `Observe`'s optional 7th parameter `turnWindow: number?`
  (nil = `TURN_WINDOW_SECONDS`). Module constants like `AIR_MARGIN_STUDS`; propose `Combat.json`
  keys only if Ben should tune them. `FALL_GRAVITY` must follow `Workspace.Gravity` if a place
  ever changes gravity.
- `WeaponService` is unchanged: it passes no window and gets the server's.
- Ruling taken here: the landing-ahead reach counts gravity over the lag (see M1). It is more
  lenient than before only early in a fall at large lags; for an honest client the only change is
  that the server no longer refuses the frame-after-bounce swing at the 0.3 s ceiling.

## What to check in Studio

1. Held Space + held attack with a sword: one swing per hop, no "swing that shows and vanishes",
   also with the network simulator at 150-300 ms.
2. One jump, click at the apex and again just before landing: the second is not drawn; the next
   jump's apex swing comes out.
3. A double jump about 6-7 studs up: no second swing in the double jump's air. A double jump just
   off the floor (3-4 studs) may give one, and the server keeps it.
