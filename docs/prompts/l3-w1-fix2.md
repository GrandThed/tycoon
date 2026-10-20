# L3 Wave 1 fix round 2 — after the fix-diff review (2026-10-20)

The fix-diff review (`docs/prompts/l3-w1-fix-diff-review.md`, on `git diff f6c426d 32d7893`) found **0 Critical, 0 Major,
2 Minor, 5 suggestions**. One fresh agent does all of it. Branch `l3-armory` in `C:\Users\benja\Desktop\tycoon-p5`. Read
the review first; its probe script is
`C:\Users\benja\AppData\Local\Temp\claude\c--Users-benja-Desktop-tycoon\f6c03e29-23c5-4dc8-ba99-ba7296a3858e\scratchpad\l3fix\probe.py`.
Contract: `docs/prompts/l3-w1-contract.md` (§12 overrides); rules: `CLAUDE.md`.

## Rulings

**F1 (m1) The text checks also pin what feeds each pinned call, and that it is reached.** Add counts in
`run_harness.py` / `tests_l3.luau` `L3.LINES` for every input line the review's probes broke (the `combat` reads in
`damageScale` and `gearOf`, `held` from the shooter, no raw-override early return, each slot's own Ascension,
DataService's `runMigrations(profile.Data, player)` call in the load function, `GrantStars`' level read, DebugService's
star difficulty, SavedPower's `weapons` argument in `Main.server.luau` and `EconomyService.luau`), and the `return`
count of the `gearOf` body (2) and the `damageScale` body (3). Make the count-0 checks robust to spelling where the
review says they are not (`'*'`, a reversed compare, a local alias). Add one `mutate.py` entry per new count (the
review's probes can be the entries; each text must occur exactly once) and run them filtered: every one caught.

**F2 (m2) The hub's star lever pays the first-clear reward too**, as the dungeon's U does (R4). Move the pure part of the
grant into `src/shared/Unlocks.luau`: `Unlocks.ApplyFirstClear(combat, reward, weapons, starters): Types.FirstClearGrant`
(families written unless a starter or already owned, Valor added; returns what it gave), called by
`UnlockService.GrantFirstClear` and by the hub's `ArmoryService.grantStarTo`, which reads the reward from the level file
(`Catalog`) for each NEW star only. Studio only, as the lever is. The hub notice names what was given, as the dungeon's
does. Tests in `tests_l3` (fresh, owned, starter, Valor only).

**F3 (s1)** `GrantStars` resolves the level before it awards the star: a level that fails to resolve gets neither.

**F4 (s2)** `Armory.luau`'s header says which functions have no Python mirror (`StrikeTier`, `HeldFamily`,
`SavedPower`) and why (the simulators need only their parts), and `check_stage_mirror.py` lists them as deliberately
unmirrored.

**F5 (s4)** The hub replays `pushArmory` (the profile and the held pair into the screen) when the ProvingGrounds config
first resolves, so a late config never leaves the screen's wallet empty.

**F6 (s5)** `sim_range`'s "the fire sniper casts at least once" gate is judged per spot; a spot whose course never casts
fails it by name, unless that spot is listed with the reason it cannot cast (CaveMouth with Dragon's Breath on Normal and
Hard: say why, or make it cast). Add a `check_levels_mutants.py` SIM_CASE for the per-spot rule if it can be proven in
one run; otherwise report why.

**Not fixed (s3):** a gamepad cannot reach the party invite while the Armory is open; B closes the screen first. The lead
puts it in PLAYTEST.

## Owner and gates

One `luau-engineer` (Opus) owns every file named above, for this round only. Run `git status` and `git diff` first; commit
nothing; kill only your own PIDs; never touch `C:\Users\benja\Desktop\tycoon-p5b` (a long mutation run). Gates: stylua,
selene, luau-lsp on both sourcemaps, `py tools/check_compile.py`, the harness
(`py tools/crowd_harness/run_harness.py C:/Users/benja/Desktop/tycoon-p5 C:/Users/benja/Desktop/tycoon/tools/bin/luau.exe`),
`check_stage_mirror`, `mutate.py` filtered to your new entries plus `files:` for every file you changed, `check_levels`,
and the forest part of `sim_range --check` (`--levels-only --level forest`). `export PATH="$HOME/.rokit/bin:$PATH"`;
`py` only; LF. Report to `docs/prompts/l3-w1-fix-reports/fix2.md` and reply with it.
