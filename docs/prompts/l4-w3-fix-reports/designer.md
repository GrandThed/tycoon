# L4 W3 fix round — economy-designer report

Rulings F17, F18, F19, the `resetOpened` re-aim (F1) and "Pins and mutants for everyone's lists"
(`docs/prompts/l4-w3-fix-round.md`); findings `docs/prompts/l4-w3-review/4-data.md` (m1, m2, s1, s3, s4) and the probe
lists of `1-hub.md` m1, `2-combat.md` m2, `3-clients.md` m3. Nothing committed or staged. No config or layout number
moved.

Python: tools with the `#!/usr/bin/env python` line (`sim_combat.py`, `sim_economy.py`, `check_stage_mirror.py`) and
`py -3.12 tools/check_levels.py` ran on **3.12.10 64-bit**; `run_harness.py`, `mutate.py`, `mirror_mutants.py` (which
runs `check_stage_mirror.py` under its own interpreter) and my `py -c` probes on **3.14.7 32-bit**.

## F17: what assertion 24 proves (`tools/sim_combat.py`, `docs/BALANCE.md`)

- Assertion 24's label is now **"24 back to back"** and its line opens "back-to-back runs on Normal or Hard never finish
  an era sooner than building"; its comment and the module docstring say it gates that one course. `BALANCE.md`'s two
  claims (the W3 section's opening, the table note) and the assertion bullet are reworded; the "no way of running beats
  building" text is gone from BALANCE (MISSIONS_DESIGN §30 untouched, as told).
- `run_pause(run_seconds, clear_cash, stop_after=None)`: with `stop_after` k the runner stays after his k-th return and
  builds every second (the review's `never_faster.py` "stop-after-k", same behaviour; `trip["runs"]` still counts
  departures).
- `--check` prints, ungated, one explanatory line and one line per era: the best "k runs right after the Advance, then
  build" (min over every k up to the back-to-back run's count). The numbers equal the review's probe to the second:

| Era | City | Normal | Hard |
|---|---|---|---|
| Village x1.00 | 41:50 | 40:03 -4.3% (k = 1) | 39:00 -6.8% (k = 1) |
| Boomtown x1,192.60 | 1:44:15 | 1:43:23 -0.8% (k = 1) | 1:41:44 -2.4% (k = 1) |
| Metropolis x122,740 | 4:28:49 | 4:29:02 +0.1% (k = 1) | 4:24:59 -1.4% (k = 8) |
| Orbital x8,806,000 | 9:25:10 | 9:26:58 +0.3% (k = 3) | 9:22:09 -0.5% (k = 12) |

- BALANCE's sentence: the wallet is empty after an Advance, so those runs cost almost no purchases while the city earns
  on, and any `eraCashMult` entry of at least 1 keeps that (Village does it at x1). Stated honestly: on the shipped
  entries it beats the city on Hard in every era, and on Normal only in Village and Boomtown.
- `sim_combat.py --check` (3.12): **PASS, all thirteen assertions**, 7 min 06 s (was about 5 min 20 s: the scan costs
  about a minute and a half). Every gated line reads as before.

## F18: the note rule's Python twin (`tools/sim_range.py`, `tools/check_levels.py`, `tools/check_stage_mirror.py`)

- `sim_range.NOTE_MAX_BYTES` 24, `note_dropped(note)`, `kept_notes(level)` and `note_problems(level, problem)` mirror
  luau B's `StageFlow.Notes` (not a string, "", over 24 bytes; difficulty-name order). `level_problems(..., notes=True)`
  reports them by default, so `check_levels.py`, `sim_range.py`'s and `sim_combat.py`'s own level checks fail on shipped
  data carrying one; `check_levels`' line now names the rule.
- **Shown failing:** a scratch copy (`...\scratchpad\l4-w3-fixD\notep`) with the shipped Brutal note set to "Castle gear
  and a long note" (27 bytes): `py -3.12 tools/check_levels.py` -> `CHECK: FAIL (1)`, the one line "difficulties.brutal.note
  is 'Castle gear and a long note' (27 bytes), not a string of 1 to 24 bytes: the game drops it and the map shows no
  note (F6)". On the real tree: `CHECK: PASS`. `py -c` (3.14) on the rule: 24 bytes kept; 25 bytes, "", 5, true, a table
  dropped; an absent note neither.
- `check_stage_mirror.py`: `vet` carries `notes=False`, so every comparison of Validate's list or verdict leaves the note
  lines out (Validate names none since F6). New family **"F6: a bad note is dropped, the level kept (StageFlow.Notes,
  Validate)"**, 8 cases on the shipped level (as shipped, 24 bytes, 25 bytes, "", a number, `true`, a table, a kept
  note beside a dropped one): each accepted on both sides, `StageFlow.Notes`' kept notes equal to `kept_notes`, as many
  dropped as `note_problems` names; a case whose Python drops the wrong count is itself a DIFF; `Notes` joins `NEEDED`.
  The driver (`stage_mirror.luau`) runs Validate and Notes on each copy.
- `mirror_mutants.py` +4: "Notes F6: a 25-byte note kept", "... an empty note kept", "... a good note dropped too",
  "Validate F6: a bad note refuses the level again": **4 of 4 caught** (1, 1, 3 and 6 of 8 differ).

## F19

- `tests_l3.luau`: the 36-shape loop is labelled "LoadoutOf hands out HeldFamily's slots", with a comment that
  `L3.loadoutTests`' explicit pairs hold the rule.
- `sim_range.py`: the `Config/Missions` and `Armory.HeldTiers` text is gone (`is_catalog_name`, `gear_max_hp`,
  `armed_problems`, `armed`); docstrings and a comment only.
- `check_stage_mirror.py`: the blank line in `armory_cases` is gone.
- `mutate.py` "l3fix2 F1: the dungeon's Snapshot returns before it is sent" now inserts `if state.combat ~= nil then
  return end` (every loaded profile carries `combat`, so it returns at run time); caught by `mainSnapshotExits` (2,
  expected 1).

## Pins and mutants

### run_harness.py

- `SOURCES` += `TouchHold` (ui A), `TallyRules` (ui B). `TESTS` += `tests_l4w3_hub.luau` (ui A's), `tests_l4w3_tally.luau`
  (ui B's, the ruling's), and my new **`tests_l4w3_pins.luau`** last (it keeps the verdict line).
- **luau B's pins** (`docs/prompts/l4-w3-fix-reports/luau-b-pins.py`) pasted after `L4W3B_ORDER`: 6 re-aimed, among them
  **`resetOpened` -> "Reset keeps it"** (a regex `\bdepartOpened\b` over Reset's code, expected 0) with `openedWrites`
  (0) and `bootOpened` (1); the conditions round every call of the auto-start, the ticket, the hint, the P lever, the
  note and the secret rows; the counts are B's (`tests_l4w3_run.luau`).
- **New family `L4W3FIX_LINES` / `L4W3FIX_ORDER`** (`source.l4w3fix`, counted on the code with comments blanked, in the
  one function each lives in), expectations in `tests_l4w3_pins.luau` (64 pins and 1 order chain over 10 bodies; 68 checks with the found / unknown
  guards):
  - hub (A's 5.4 plus `departLeader`): `departStars`, `departVerdict`, `departReason`, `departLeader`, `sendMapLeader`,
    `sendMapSolo`, `sendMapArgs`, `bridgeReads`, `bridgeCards`, `bridgeNoOwnReader` (0), `arrivalCaps`,
    `expeditionArgs`, `shortName`;
  - dungeon lobby and card (ui B's): `uiDepart*` (step, memory kept and written once, line, close, pick, select, open,
    one open), `uiResult`, `uiNoLocalResult` (0), `uiFirstPick`, `uiWallet`, `tallyFlights` on `Theme.lowEndDevice`,
    `tallyLowEnd`, `tallyNoReduced` (0), coins, logs, pile, `tallyGlyph`, `tallyNoTurn` (0), `tallyOneTurn`,
    `hostSummary`, `hostNoReader` (0), `hostWallet`; order `uiDepartOrder` (Depart, memory, close, pick, open, then the
    card);
  - city (ui A's): `mapDepartArgs` (`deps.isPublic()`, read once), `mapFirstPick`, the hold after the Armory closes,
    the release first, Destroy's release, Hold 1 / Release 2, the F16 toast; `cityWallet` (the city's cash),
    `citySummary`, `cityNoStar`, `cityReportShown`, the map and the Armory never over the report, the map letting go
    before the Armory, the map's open closing the Armory, the report's close-hold-show, Dismiss's release, the error
    toast, and one each of Hold, Release, `screen.Toggle()`, `map.Toggle()`, `card.Hide()`.

### mutate.py

- `FILES` += TouchHold, TallyRules, StudioBridge, HubRemotes, RunTally, TallyHost, RunRegistry, HubMap (every file a new
  pin reads, so a mutant root never misses one).
- New blocks (labels `l4w3fix ...` and B's `l4w3b-fix ...`):

| Block | Entries | What |
|---|---|---|
| `L4W3FIX_HUB_MUTATIONS` | 10 | the 7 hub probes re-aimed at the fixed text (verdict, stars, difficulties, SendMap's leader, the bridge's card, both arrival caps, the remote's difficulty cap), F9's rows, and a guest let through Depart |
| `L4W3FIX_A_MUTATIONS` | 48 | A's `probes_a.py` label for label: F7 ReadSummary 31, F8 both halves of Read 6 (the review's m2 probes), F9 SecretRows 4, F13 FirstPick 7 (p3 among them) |
| `L4W3FIX_UIB_MUTATIONS` | 18 | TallyRules 12 (p1, p2, close, open, memory, lobby-only, F15, s4, tie-break, p5 rule, logs cap, no cash) and the hosts 6 (p5 host, p1/p2 host, F15 host, p3 host, the dungeon card unread) |
| `L4W3FIX_UIA_MUTATIONS` | 23 | TouchHold 6, HubMap 6 (p4 among them), UIController 11 (p6 among them) |
| luau B's (pasted whole) | 59 + 2 re-aimed | F1 (the ruling's "Reset clears the opening" among them), s2, s3, F2, F3, F4, F6, F9 and probes 3-20 of slice 2 m2; "l4w3b note: never checked" and "l4w3b credit: no line" re-aimed |

- The list is **2,382 entries, 0 stale** (exec of `mutate.py` up to `# mutate_shards.py asks`, 3.14).
- Filtered runs (3.14, seven private roots `mutant_designer0..6`, removed by mutate.py; my bundles removed): every
  entry whose label holds `l4w3` (2107-2381: W3's own 117 and this round's 158) plus the re-aimed snapshot entry:
  **276 run, 0 not caught**. One mutant, "l4w3b era: 0 kept", came back `HARNESS: REFUSED` because luau A's
  `tests_l4w3.luau` changed under it mid-run (16:44); re-run alone it is caught (2 checks). The first try of the 99
  `l4w3fix` entries refused to start (B's pins were not yet pasted, so the baseline failed); nothing ran then.

## Gates

| Gate (Python) | Result |
|---|---|
| `py tools/sim_combat.py --check` (3.12) | **PASS, all thirteen assertions**, F17's lines printed (7 min 06 s) |
| `py tools/sim_economy.py` / `--check` (3.12) | **byte-identical to `l4-w3-qa\econ_base.txt`** (`cmp`) / exit 0 |
| `py -3.12 tools/check_levels.py` | **PASS**; the 27-byte scratch copy **FAIL (1)** on the note line |
| `py tools/check_stage_mirror.py` (3.12) | **PASS** (F6 family 8 compared), 27 s, on the final tree |
| `py tools/crowd_harness/mirror_mutants.py` (3.14) | **151 of 151 caught** (full run, 75 min beside the other owners' runs) |
| `py tools/crowd_harness/run_harness.py <repo> <luau>` (3.14) | **PASS, 5,402 checks** on the final tree (17:38; nothing in `src` or `tools` changed after) |
| `mutate.py` (3.14) | **0 stale of 2,382**; filtered **276 run, 0 not caught** |

Not run by me: `sim_range.py --check` (20 min) and its R8; my `sim_range.py` edits are docstrings, a comment, three new
functions and `level_problems`' default-on note lines (the shipped note passes), so QA's run should read as before.

## For the other owners

- **Lead:** F17's numbers and sentence are in BALANCE "L4 W3 fix round"; MISSIONS_DESIGN §30 untouched. For QA's sharded
  run the list is 2,382 entries (`mutate_shards.py`), 0 stale at my last check.
- **Lead, for the fix-diff review:** the pin family's reader counts on comment-blanked code inside one function each, so
  a comment that quotes a pinned line never counts; `tests_l4w3_pins.luau` also fails on a key read with no expected
  count. My `sim_combat.py` comment and docstring were softened after the last `--check` ("can finish sooner"); no
  output changed.
- **luau B:** your two files are pasted verbatim (the pins after `L4W3B_ORDER`, the mutants before `def harness`, with the
  usual no-overlap assert added); `L4W3B_FIX_MUTATIONS` holds 59 entries (your report says 57). If you change either
  file again, tell me and I re-paste (my scratch `repaste_b.py` / `repaste_b_mut.py` are idempotent).
- **luau A, ui A, ui B:** your lists are in as given (A's hub entries with one more of mine: a guest let through Depart).
