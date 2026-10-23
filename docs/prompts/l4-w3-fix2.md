# L4 W3 fix round 2 — the lead's rulings on the fix-diff review

Fix-diff review of `36b54c0..3503134` (`docs/prompts/l4-w3-review/5-fix-diff.md`): **0 Critical, 0 Major, 4 Minor,
2 Suggestions.** Small enough for **one agent across owners** (no parallel owners this round, so ownership cannot collide).
Read each finding in `5-fix-diff.md` before fixing it.

- **G1 (m1). A Reset before the level started keeps the party's pick.** When `WaveService.Reset` (through
  `StageFlow.DepartForget`) finds the depart still `waiting` or `counting`, it carries that `levelId` / `difficulty` so the
  next admit on this server opens it as **`picked`** (the map on their choice; never `waiting` or `counting` again, so
  nothing auto-starts). A Reset after `done` or `picked` carries nothing (F1 unchanged). Pure, in `StageFlow`; a harness
  case for the reviewer's scenario (member admitted, leaves, Reset, the host arrives with the same ticket → `picked` on
  Hard) and for F1's (run, Reset, rejoin → nothing).
- **G2 (m2). Pin the five lines** the reviewer's probes passed: `lateAtZero`'s `userId = member.userId,` and its
  `GetMembers()` loop (`WaveService.luau` ~:2139-2141), the dungeon `secretRows`' `sitesOf,` argument (~:570),
  `st.mapSeeded = true` and `armoryScreen.Close()` in the pick branch (`CombatUIController.luau` ~:1787-1789). Whole-line
  pins with indentation, each also a `mutate.py` entry that fails the harness.
- **G3 (m3). One note rule.** A pure `MapRules.Note(difficultyDef): string?` (a string of 1 to 24 bytes, else nil) and the
  cap `MapRules.MAX_NOTE_LENGTH = 24` as the only home of the number; `StageFlow.Notes` calls it (its warn stays, worded to
  match), and `MapScreen` shows only what it returns. `sim_range.level_problems`' twin keeps 24 and its message says the
  note is dropped and not shown; `check_stage_mirror`'s F6 family still passes. Cases in `tests_l4w3.luau`.
- **G4 (m4). The zero card always has a title.** `ReturnService`'s zero card falls back to the same default as
  `ArenaService.sessionName()` (`DEFAULT_SESSION_NAME`) when `Config/Expeditions` is missing, so `RunLines.ReadSummary`
  never drops a card the server built. Share the one default (do not copy the string). A case for it.
- **G5 (s1).** The auto-start's start runs under `xpcall(…, debug.traceback)`; the warn carries the traceback; a throw
  refuses (→ `picked`, the toast) **only while the run is still in the lobby**; after the level went live it only warns.
- **s2 (pins matching one spelling): no change.**

## Done

One fresh agent. `git status` / `git diff` first; commit nothing; kill only your own PIDs; filtered `mutate.py` in your own
named mutant folder only; report to `docs/prompts/l4-w3-fix-reports/fix2.md`. Gates: stylua, selene, luau-lsp on both
sourcemaps, `check_compile.py`, `check_stage_mirror.py`, `py -3.12 tools/check_levels.py`, the harness green, each G1-G5
case or pin shown failing without its fix, `mutate.py` 0 stale with the new entries run filtered (0 not caught). The lead
reads the diff afterwards (no third review unless it grows).
