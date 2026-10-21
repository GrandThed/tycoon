# L3 W2 fix round — luau-engineer report (S1 to S6)

Branch `l3-w2` in `C:\Users\benja\Desktop\tycoon-p5`. Nothing committed. I edited only the files in my row.

## Gates

| Gate | Result |
|---|---|
| Harness (worktree, client files final) | `HARNESS: PASS (4,024 checks)` (was 3,950) |
| `mutate.py … "l3w2 fix"`, the 81 new or re-aimed mutants | **81 run, 0 not caught** (all inside the full run below; the server 31 also alone, first) |
| `mutate.py … l3w2`, every l3w2 mutant (218) | **218 run, 0 not caught**, from a passing baseline (`HARNESS: PASS (4,024 checks)`) |
| `py tools/check_compile.py` | PASS, 180 files |
| stylua `--check` | clean on my four Luau files |
| selene | 0 / 0 / 0 on WeaponService, AbilityService, WeaponLook |
| luau-lsp (`tools/types/globalTypes.d.luau`, both sourcemaps regenerated into my scratchpad) | 0 diagnostics |
| Line endings | LF on all six files |

- Both mutation runs ran on a scratch snapshot of the worktree (tracked `src`, `tools` and the two project files), so
  no edit in the worktree could land mid-run. The server half (31) ran first on HEAD plus my files; all 31 were
  caught. The full run then ran on the snapshot taken after the ui-engineer's report. Every changed file in
  the worktree is byte-identical to that snapshot, except a docstring paragraph added to `run_harness.py`
  afterwards; the worktree's own harness passes at 4,024 after it.
- selene on `tests_l3_w2.luau` reports 83 `undefined_variable`, as before (82 at HEAD): the case files share
  the bundle's locals (`check`, `L1`, `FIXTURES`). `tests_l3.luau` reports 375 the same way.

## Files changed

- `src/combat/server/Services/WeaponService.luau`: S4, and two comments (`Shooter.held`, `NoteHeld`).
- `src/combat/server/Services/AbilityService.luau`: S6.
- `src/shared/WeaponLook.luau`: S5's `Problems` sort, and the 2-s3 comment naming `weapon_frames.py`'s `POINT_SLACK`.
- `tools/crowd_harness/run_harness.py`, `tests_l3_w2.luau`, `mutate.py`.

## What each ruling became

**S1 (2-m1).** Two file-wide counts on the code with comments blanked, spelling-robust (`(?<![.])\.\s*held\b`):
`heldReads` = 3 in WeaponService (the `Values` call, noteHeld's compare and write), `abilityHeld` = 0 in
AbilityService. T8's per-function pattern takes the same spelling. Mutants: the review's P1 (`slotFamily`) and P2
(`variantFor`), and an AbilityService read.

**S2 (2-m2).** Each caller, as it reaches `PrepareCharacter`, pinned as whole lines in its own function:
- WaveService `Init`: `\tArenaService.SetCharacterHook(WeaponService.PrepareCharacter)\n` (`missionHook`, was
  file-wide with no indentation); `initExits` = 3 (the range's return and the two sources' answers);
  `hookSetters` = 1 in the file.
- ArenaService `SetCharacterHook`: `\thooks.character = hook\n`; `hookWrites` = 1 in the file (no other writer).
- ArenaService `Admit`: the whole CharacterAdded handler from `player.CharacterAdded:Connect(` through
  `hook(player, character)` and its `end`, at its tabs (inputs: `live`, `watchCharacter`, `placeBody`).
- RangeService `AddPlayer`: `\tWeaponService.AddPlayer(player)\n`, the respawn handler
  `\t\tplayer.CharacterAdded:Connect(function(character: Model)\n\t\t\tprepareCharacter(player, character)\n\t\tend)\n`,
  the first character `\tlocal character = player.Character\n\tif character ~= nil then\n\t\tprepareCharacter(player, character)\n\tend\nend`;
  `rangeAddExits` = 1, and `rangePrepareExits` = 0 in `prepareCharacter`.
- WeaponService `AddPlayer`: `addMission`, a pattern on the code that pins
  `\tif state.mode == "mission" then` … `\t\tlocal character = player.Character` … `PrepareCharacter(player, character)` …
  `\tend\n` exactly, the comment lines inside read as blank; `addExits` = 1.
- Mutants: the review's P3 to P6, plus Init leaving early, a second hook setter, the admit's handler leaving
  before the hook, a cleared or second-written hook, the range's first character, its AddPlayer giving no
  weapons or leaving early, its `prepareCharacter` leaving, and AddPlayer leaving before the mission prepare.

**S3 (2-m3, 3-m3), server side and the harness.**
- `L3W2_LINES` are now counted as **whole lines** (`whole_lines`): a pinned text counts only where it starts a
  line and ends one. A pinned line wrapped in a new block is indented further and no longer counts. Every pin
  that started mid-line now carries its indentation and newline: the three `slot` lines, `castSlot`,
  `missionHook`, `heldTip`, `restRaise`, `restAngle`, `screenActive`, `screenClosed`. `magOldMuzzle` (a
  count-0 fragment) moved to a spelling-robust pattern.
- T9: `\t\tWeaponController.SwingOther(strike.userId, strike.step or 1)` as a whole line in the branch, and
  `otherBlocks` = 0 (no line opening a block between the branch head and the call). Mutants: the review's P7 and
  a misindented wrapper.
- T12: `sealUndone` = 0 in HeldWeapons, any of `.CanCollide/.CanQuery/.CanTouch/.Anchored = true` or
  `.Massless = false`, by field or by index. Mutant: the review's P13.
- T14 now reads `syncTurn` (C3): the gate is the exact whole line pair
  `\t\tif look.turn == nil and not Theme.lowEndDevice then\n\t\t\tlook.turn = RunService.RenderStepped:Connect(function(deltaTime: number)\n`
  (`gatedFrames`, replacing the old "any `if` containing `not Theme.lowEndDevice`" pattern, so the review's P8
  is caught). The three stale T14 mutants are re-aimed at the new text.

**S4 (2-m5).** `OnDraw` refuses `def.slot ~= "ranged"` as the first clause of its existing refusal (no new
`return`, `drawExits` stays 3, T5 untouched). Pinned as the whole refusal (`drawRanged`); mutant removes the clause.
Only the Longbow's variants charge, so no honest client sends a melee draw.

**S5.**
- 2-s1: `lookLiterals` = 0, the attribute names spelled as a string literal (any quote or a long bracket) in
  any `.luau` under `src` but `WeaponLook.luau`; `heldIndexed` = 0 (`["held"]` in WeaponService);
  `loadoutWhole` = 0 (`.loadout =` or `["loadout"] =`); `loadoutWrites` also counts the pair by index.
  Mutants: the review's P9, P10, P12, and the pair by index.
- 2-s2: `attackExitsAfter` = 0 and `castExitsAfter` = 1 (the projectile budget's refusal), the exits after the
  noted line. The totals (12, 9) stay. Mutants: the review's P11 (OnAttack's credit refusal moved past the note,
  12 exits kept) and the cast's note and send moved above its aim refusal (9 exits kept). Both moves are built
  from the file as it stands by two small helpers in `mutate.py` (`moved_down`, `moved_up`): a block or anchor
  that disappears gives an entry found 0 times, which the stale check reports.
- 2-s4: `Problems` sorts its whole result before returning; its comment says so. A new pure case (a missing
  family plus an earlier family's file fault) holds the order; mutant drops the sort.

**S6 (3-m1).** `WeaponService.NoteHeld(player, slotName)` now stands right before `broadcastFx(fx)` in `OnCast`,
after every refusal but the projectile budget's. T6 re-pinned as
`\tWeaponService.NoteHeld(player, slotName)\n\tbroadcastFx(fx)\n`; the old "a refused cast is noted" mutant is
re-aimed (a note before the aim refusal), plus "the effect leaves before the note" and "noted after
acceptance, as before".

**S3, the client pins** (against the ui-engineer's final text, each checked to occur once and against
`git diff`). Every one is a whole line with its indentation, in the function it belongs to, with an `l3w2 fix`
mutant:
- ArmoryStage: `stageStops` (`stop()` in SetActive's close branch), `activeSyncs`, `setActiveExits` = 2,
  `selectClears` (`clear()` as selectFamily's first line), `stageSilhouette`, C1 (`selectBase`,
  `baseBeforePose`, `stageTemplateBase`, `stageBaseName`, `stagePrimaryReads` = 0), C3 (`syncStops`,
  `gatedFrames`, `syncStep`, `syncStick`, `syncFocus`, `syncExits` = 2, `syncCalls` = 4, `stopDrops`,
  `showNilSyncs`, `selectSyncs`, `stickOnly`, `stickLowEnd`, `dragLost`, `dragEnds`).
- ArmoryShelf: `shelfGhost` (C2's line), `shelfSilhouette` = 0.
- HeldWeapons: `heldCleanup` (the whole cleanup block with `entry.model:Destroy()`), `heldWatched` (the three
  names and their queued handler), `heldMountShows`, `attachShows`, `bindShows`, `bindExits` = 0,
  `stanceShows`, `stanceExits` = 1, `playerWatch`, `playersNow`, `startExits` = 1; C4 (`queueOnce`,
  `flushShows`, `unbindUnbinds`, `muzzleFlushes`, `heldDirectShows` = 4, `heldQueues` = 3); C1 (`heldBase`,
  `baseBeforeWelds`, `heldTemplateBase`, `heldBaseName`, `heldPrimaryReads` = 0).
- WeaponController (unchanged this round): `setRestEase` with `setRestExits` = 2, `remoteSnap` with
  `remotePoseExits` = 2.
- The exact texts are the `L3W2_LINES` entries of those keys in `run_harness.py` (the ui report's table,
  with a body's last `end` taking no newline).
- One harness choice differs from the relayed one-line re-aim: rather than point `stageActive` at `syncTurn`,
  the bodies are now `stageSetActive` (SetActive, for its stop and sync), `stageSync` (syncTurn, for T14),
  `stageShow`, `stageStop`, `stageStick` and `stageDrag`. Same effect for `activeFrames` and `gatedFrames`.

## Contracts implemented

No signature changed. `WeaponService.NoteHeld(player: Player, slot: string): ()` keeps its contract; only its
caller's position moved. No new require.

## Assumptions

- A cast refused by the projectile budget after the note still shows its slot, as the review accepted: the
  caster's own client switched on the press anyway.
- `initExits` = 3 counts the two `return`s of Init's source closures; a new one there would fail the count
  (deliberately).
- 2-s3 ("not taken"): read as "no JSON key; a comment in each file names the other". My half is in WeaponLook.

## Required changes outside my files

1. **Lead, `docs/prompts/l3-w2-contract.md`** (L3-50 and §9 T6): the cast's line is now "just before
   `broadcastFx(fx)`, after every refusal but the projectile budget's", and T6 pins
   `WeaponService.NoteHeld(player, slotName)` on the line before `broadcastFx(fx)`.
2. **Pipeline engineer, `tools/assets/weapon_frames.py`** (2-s3, the Python half):

```diff
-POINT_SLACK = 0.01
+# src/shared/WeaponLook.luau's BOUNDS_SLACK is this number on the reading side: change the two
+# together, or one writes what the other warns of.
+POINT_SLACK = 0.01
```

## What to check in Studio

- A Longbow draw still charges (hold, release: the arrow's charge shows). Nothing else changed for an honest client.
- Two clients: P1 holds the sword, presses E (Volley). On P2's screen the effect starts at P1's bow, not the sword
  tip (S6 with the ui-engineer's `Muzzle` flush). Blade Storm from a gun in hand starts at the blade.
- The attributes: `WeaponHeld` flips on a shot, a draw, a swing and a cast, as in W2; a pure 1 / 2 switch does not.
