# L4 W1b fix round — ui-engineer report

Worktree `C:\Users\benja\Desktop\tycoon-p5b`, branch `l4-w1b` (nothing committed). Rulings done: **F4**, **F3's final
client lines** (below), and the suggestion **s2** (the Studio strip's bottom reserve). Line numbers are the file as it
stands after this round.

## Files changed

- `src/combat/client/Controllers/CombatUIController.luau`
  - **F4.** `onRunState` now calls `applyFloors` straight after the `isRunState` guard and the `run` cast (line 1637).
    That is before the new-level branch (`SetKinds`, `SecretFx.SetLevel`, `faceFrom` → `routeForward`), the
    first-RunState `faceFrom`, `Prewarm` and `paintWallet`. The old call after `paintWallet` (old line 1676) is gone.
  - Nothing above the new position reads the floors: `applyFloors` reads only `st.floors`, `st.floorsSeq` and the
    payload. Nothing between the old and new positions writes them. `CameraController.SetFloors` touches only
    `wallClip.rects`, and `LookToward`, `SetPhase` and `CrowdRenderer.Prewarm` never read them. So this moves no
    behaviour except the error case the review named.
  - The header comment (the L4 W1b paragraph) and the comment at the call now say why: the cells come once, so they are
    kept before anything that can throw. The level block's comment no longer says it does the floors.
- `src/combat/client/UI/DebugPanel.luau` (s2)
  - `BOTTOM_BLOCK` now reserves CombatHud's third stacked line, the perf readout:
    `+ Theme.COMBAT_PERF_HEIGHT + Theme.ROW_SPACING`. It goes from 116 to 140 design px.
  - CombatHud's perf line top in Studio with a keyboard is 12 + 56 + 48 + 16 = 132 px, so the strip now clears it by 8 px.
    That is the same 8 px the old reserve kept over the key hint (108 against 116).
  - The comment says that a button row ActionRows wraps to two rows (56 px higher) is still not reserved. The review
    offered that as an alternative ("or read HudEdges"), and the ruling took the one-line fix.
- `src/client/UI/Theme.luau`: unchanged. No new constant was needed.

## Gates (run by me)

- `stylua` (format, then `--check`) and `selene` on both files: 0 errors, 0 warnings.
- luau-lsp analyze on both sourcemaps: 0 diagnostics.
  - The sourcemaps were regenerated into my scratchpad (`...\scratchpad\ui\sourcemap*.json`), not over the
    worktree's tracked ones.
  - Hub: `src/client src/server src/shared`. Combat: `src/combat src/shared`.
- `py tools/check_compile.py`: PASS, 176 files. I added no top-level local.
- `run_harness.py C:/Users/benja/Desktop/tycoon-p5b <luau>`: PASS, 4,075 checks.
  - That run includes B's in-progress `ArenaService` and `tests_l4b_run` edits as they stood then.
  - No harness or mutate entry reads either of my files yet, so I did not run `mutate.py`.
- Both files are LF and UTF-8.

## Remotes and state fields consumed

- `RunState` (`remotes.runState.OnClientEvent` → `onRunState`):
  - `floors` (with `cells`, `locks`, `ceiling` and `fence` on each floor);
  - `floorsSeq` (a missing one reads as 0);
  - `levelId`, `phase`, `maxAlive`, `material`, unchanged.
- No new remote and no new field.

## Assumptions

- `isRunState` already requires `floors` to be a table, so moving the call above the cast's other reads adds no new way
  for it to throw.
- `applyFloors` itself can still throw inside `CrowdRenderer.SetFloors` or `CameraController.SetFloors`. If that
  happens after `st.floors = fresh`, the next same-value RunState returns early and those two never get the list. That
  was already true before W1b and is outside F4. I note it for the lead and did not change it.
- F4's "before the new-level branch" is read as "first after the guard". The order pin below fails on any move to
  after the branch, and everything else in the handler comes after the branch.

## Required changes outside my files

None for luau-engineer A or B. The designer's pins and mutants are below.

## For the other owners

### Designer: F3 and F4 pins (client half), in the `run_harness.py` L4B_LINES / L4B_ORDER format

File: `src/combat/client/Controllers/CombatUIController.luau`. Proposed constant:
`UI_CONTROLLER = "src/combat/client/Controllers/CombatUIController.luau"`. Neither tool has a name for this file yet.
`INPUT_CONTROLLER` and `WEAPON_CONTROLLER` exist; none of the other names are taken.

Both functions are nested in `bootMission`, so their bodies are one tab in. The new body regexes are:

```python
APPLY_FLOORS_BODY = re.compile(r"(?ms)^\tlocal function applyFloors\(.*?^\tend$")   # 55 lines, matched
ON_RUN_STATE_BODY = re.compile(r"(?ms)^\tlocal function onRunState\(.*?^\tend$")    # 167 lines, matched
```

These are the exact whole lines, as they stand, with their indentation (`\t` = one tab):

| Line | Whole line (Python literal) | Body |
|---|---|---|
| 1574 | `"\t\tlocal held = st.floors"` | applyFloors |
| 1599 | `"\t\tfresh = RunFloors.Merge(held, st.floorsSeq, fresh, seq)"` | applyFloors |
| 1600 | `"\t\tst.floorsSeq = seq"` | applyFloors |
| 1601 | `"\t\tlocal same = #fresh == #held"` | applyFloors (order only) |
| 1624 | `"\t\tst.floors = fresh"` | applyFloors |
| 1630 | `"\t\tif not isRunState(payload) then"` | onRunState (order only) |
| 1637 | `'\t\tapplyFloors(run.floors, if typeof(run.floorsSeq) == "number" then run.floorsSeq else 0)'` | onRunState |
| 1645 | `"\t\tif run.levelId ~= st.levelId then"` | onRunState (order only) |
| 1970 | `"\tremotes.runState.OnClientEvent:Connect(onRunState)"` | whole file |

Proposed `L4B_LINES` entries. Each count is checked on the code with its comments blanked (`luau_code`). The expected
counts go in `tests_l3_w2.luau` L4BP.LINES:

```python
    # L4B-8, CombatUIController (the client's half; F3, F4).
    "uiHeld": (UI_CONTROLLER, APPLY_FLOORS_BODY, "lines", "\t\tlocal held = st.floors"),                       # 1
    "uiMerge": (UI_CONTROLLER, APPLY_FLOORS_BODY, "lines",
                "\t\tfresh = RunFloors.Merge(held, st.floorsSeq, fresh, seq)"),                                 # 1
    "uiSeq": (UI_CONTROLLER, APPLY_FLOORS_BODY, "lines", "\t\tst.floorsSeq = seq"),                             # 1
    "uiKeep": (UI_CONTROLLER, APPLY_FLOORS_BODY, "lines", "\t\tst.floors = fresh"),                             # 1
    "uiCall": (UI_CONTROLLER, ON_RUN_STATE_BODY, "lines",
               '\t\tapplyFloors(run.floors, if typeof(run.floorsSeq) == "number" then run.floorsSeq else 0)'),  # 1
    "uiApplyCalls": (UI_CONTROLLER, None, "text", "applyFloors("),                                              # 2: def + the call
    "uiMergeCalls": (UI_CONTROLLER, None, "text", "RunFloors.Merge("),                                          # 1
    "uiSeqWrites": (UI_CONTROLLER, None, "regex", r"\bst\.floorsSeq\s*=(?!=)"),                                 # 1
    "uiConnect": (UI_CONTROLLER, None, "lines", "\tremotes.runState.OnClientEvent:Connect(onRunState)"),        # 1: the handler is reached
```

Proposed `L4B_ORDER` entries:

```python
    "uiMergeThenSeq": (UI_CONTROLLER, APPLY_FLOORS_BODY,
                       "RunFloors.Merge(held, st.floorsSeq, fresh, seq)", "st.floorsSeq = seq"),
    "uiMergeThenSame": (UI_CONTROLLER, APPLY_FLOORS_BODY,
                        "RunFloors.Merge(held, st.floorsSeq, fresh, seq)", "local same = #fresh == #held"),
    "uiGuardThenFloors": (UI_CONTROLLER, ON_RUN_STATE_BODY,
                          "if not isRunState(payload) then", "applyFloors(run.floors, "),
    "uiFloorsFirst": (UI_CONTROLLER, ON_RUN_STATE_BODY,
                      "applyFloors(run.floors, ", "if run.levelId ~= st.levelId then"),   # F4
```

Suggested labels:
- uiHeld: "applyFloors merges against what it holds".
- uiMerge: "and through RunFloors.Merge with the held set's number".
- uiSeq: "then keeps the incoming set's number".
- uiKeep: "and keeps the merged floors".
- uiCall: "onRunState hands over the floors with the RunState's floorsSeq (0 when missing)".
- uiApplyCalls: "applyFloors( twice: its definition and onRunState".
- uiMergeCalls: "RunFloors.Merge( once".
- uiSeqWrites: "st.floorsSeq is written only there".
- uiConnect: "onRunState is the RunState listener".
- Orders:
  - uiMergeThenSeq: "the merge reads the held number before it is replaced";
  - uiMergeThenSame: "the comparison sees the merged floors";
  - uiGuardThenFloors: "the floors after the guard";
  - uiFloorsFirst: "and before the new-level branch (F4)".

Optional, not asked for: `"\t\tCrowdRenderer.SetFloors(fresh)"` and `"\t\tCameraController.SetFloors(fresh)"` in
applyFloors (1625, 1626). Both stand once.

### Designer: proposed mutants (`mutate.py` L4B_MUTATIONS format; `FILES += [UI_CONTROLLER]`)

I checked each one on the file as it stands. Every old text occurs exactly once (the stale check passes), and each
mutant fails the pins listed. This was a scratch replay of `luau_code`, `whole_lines` and the order test, using
`run_harness.py`'s own helpers.

```python
    # CombatUIController (ui): the source.l4b pins. r1-r4 are the review's slice 2 m1 mutants 1-4.
    "l4b: the client never merges": (UI_CONTROLLER, "\t\tfresh = RunFloors.Merge(held, st.floorsSeq, fresh, seq)\n", ""),
        # caught: uiMerge, uiMergeCalls, uiMergeThenSeq, uiMergeThenSame
    "l4b: the client never keeps the set's number": (UI_CONTROLLER, "\t\tst.floorsSeq = seq\n", ""),
        # caught: uiSeq, uiSeqWrites, uiMergeThenSeq
    "l4b: the client's call names no set": (
        UI_CONTROLLER,
        'applyFloors(run.floors, if typeof(run.floorsSeq) == "number" then run.floorsSeq else 0)',
        "applyFloors(run.floors, 0)",
    ),  # caught: uiCall
    "l4b: the client merges against the incoming list": (
        UI_CONTROLLER,
        "RunFloors.Merge(held, st.floorsSeq, fresh, seq)",
        "RunFloors.Merge(fresh, st.floorsSeq, fresh, seq)",
    ),  # caught: uiMerge, uiMergeThenSeq, uiMergeThenSame
    # F4: back where it was before this round, after the wallet (moves past the new-level branch).
    "l4b: the client takes the floors after the level branch": moved_down(
        UI_CONTROLLER,
        '\t\tapplyFloors(run.floors, if typeof(run.floorsSeq) == "number" then run.floorsSeq else 0)\n',
        "\t\t\tpaintWallet()\n\t\tend\n",
    ),  # caught: uiFloorsFirst (the span is 42 lines, 1637-1679)
    "l4b: the client keeps the number before it merges": moved_down(
        UI_CONTROLLER,
        "\t\tfresh = RunFloors.Merge(held, st.floorsSeq, fresh, seq)\n",
        "\t\tst.floorsSeq = seq\n",
    ),  # caught: uiMergeThenSeq (Merge would then always see the same set and carry old cells into a new one)
    "l4b: the client merges against nothing held": (UI_CONTROLLER, "\t\tlocal held = st.floors\n", "\t\tlocal held = {}\n"),
        # caught: uiHeld
    "l4b: the client never keeps the merged floors": (UI_CONTROLLER, "\t\tst.floors = fresh\n", ""),
        # caught: uiKeep
    "l4b: the client never listens for RunState": (
        UI_CONTROLLER, "\tremotes.runState.OnClientEvent:Connect(onRunState)\n", ""
    ),  # caught: uiConnect
```

What each mutant would break in play, so the labels can say it:
- **r1, r2, r4, n7, n8:** the first RunState's cells are lost on the next send. Plateau charges are then drawn clipped
  to the camp rectangle (the L1b-W4-33 mismatch).
- **r3:** every RunState reads as set 0, so a steady send keeps the cells only while the set really is 0.
- **n5:** F4 undone. One throw in the level branch on a set's first RunState loses the cells for the run.
- **n6:** Merge always sees "same set" and can carry one set's cells onto the next.
- **n9:** the HUD never hears a RunState.

### Luau-engineer B (server lines, for the designer)

F3's server lines (`if cellsWent then` / `sent = table.clone(runState)`, and the new `play.cellsSent[userId] ~= seq`
test from s1) are B's to confirm. `ArenaService.sendRunState` has changed under B's s1 fix (the diff shows the Attach
call and the note now sit inside `if play.cellsSent[userId] ~= seq then`). So the whole-line pins `sendFloors` and
`sendNote`, and their mutants' old texts, move by one tab. `sendAttach` is a text pin and only its line moves. That is
B's and the designer's to settle, not mine.

## What to check in Studio (and the phone emulator)

1. `proving.rbxl` → Play → Forest Road Normal → the plateau.
   - A brute that charges along the plateau must still run its full drawn lane past its camp's rectangle, as before.
   - Nothing visible should change: F4 only moves where the floors are taken.
2. Return to the lobby, then start Forest Road again.
   - The second run's plateau charges must also run full length. That is a new floor set, so the cells come again.
3. Open the Studio strip (top-left tab) with a keyboard and the perf readout on.
   - Its scrolling body must stop above the bottom-left stack: the Alt hint, the key hint and the `Server N ms` line,
     with a gap of about 8 px.
4. Phone emulator, mentally verified:
   - **375×667 portrait** (scale 1): band 667 − 140 − 144 = 383 px, body up to 329 px, scrolls.
   - **667×375 landscape** (scale 0.917, the 44 px tap floor): band 125 px, body 71 px. Still more than one 48 px row
     (the floor), and it scrolls.
   - **1920×1080** (scale 1.62): band 383 design px, as portrait.
   - The 48 px lever and tab sizes are unchanged.
