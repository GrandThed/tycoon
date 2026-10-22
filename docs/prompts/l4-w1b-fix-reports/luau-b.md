# L4 W1b fix round — luau-engineer B's report

Status: done for my files. Nothing committed. My rulings in `docs/prompts/l4-w1b-fix-round.md`: F3 (confirm the
server's cells-once lines), F6 (confirm `payMentors`' deciding lines) and the suggestion taken from slice 2 s1 (check
`cellsSent[userId] ~= seq` before calling `Attach`).

## What changed

`src/combat/server/Services/ArenaService.luau`, `sendRunState` only (slice 2 s1):
- A member already noted for the current floor set no longer reaches `RunFloors.Attach`. Before, every send called
  Attach, which clones every floor (3 on Forest Road), and dropped the copy unless the cells went. That was 12 clones a
  second per member at `combatStateHz` 4.
- What goes on the wire is unchanged on every path:
  - a noted member gets `runState` itself, whose floors BuildRunState built bare;
  - an un-noted member gets exactly what it got before, and the note is written in the same branch.
- `if cellsWent then` stays as Attach's verdict. Inside the new branch it is always true today. If Attach's rule ever
  narrows, the inner test still follows it.
- The header comment above the function now says when Attach is reached and why.

`src/combat/server/Services/WaveService.luau`: unchanged. F6 needs no code change. `payMentors`' lines are confirmed
below as they stand.

`tools/crowd_harness/tests_l4b_run.luau`:
- `L4R.Server.send` (the hand copy of sendRunState) now has the same shape:
  - it skips Attach for a noted member and returns BuildRunState's floors;
  - it counts its Attach calls (`attaches`).
- Two new checks in `attachTests`:
  - "and Attach ran for the first of those 22 sends only" (on the copy);
  - "Attach sends the cells exactly when the member's note is not the set: sendRunState's skip test". This one runs the
    real RunFloors for four notes: nil, the set before, this set, the set after. It is the condition under which the
    skip loses nothing.
- I proved the second check is live with a scratch mutant on a copy. With RunFloors' `local withCells = sentSeq ~= seq`
  changed to `sentSeq == nil`, it fails along with 7 others.

## Gates (all run from the worktree)

- `stylua --check` on my three files: clean. `selene` on the two services: 0 errors, 0 warnings.
- `luau-lsp analyze` on both sourcemaps, written to my scratch folder: 0 diagnostics.
  - hub: `src/client src/server src/shared`;
  - combat: `src/combat src/shared`.
- `py tools/check_compile.py`: `CHECK: PASS -- 176 files compile with Studio settings (-O1 -g2)`.
- Harness in the worktree: `HARNESS: FAIL (2 of 4,077 checks)`. The two failures are the whole-line pins on the two
  lines I re-indented. The designer re-aims both (below):
  - `and sends the floors Attach answered (sendFloors: 0, expected 1)`
  - `and records the set it sent (sendNote: 0, expected 1)`
- Harness on a scratch copy of the worktree, with only those two pins re-aimed in `run_harness.py`:
  `HARNESS: PASS (4,077 checks)`. That is 4,075 plus my 2. The copy held the ui-engineer's in-progress edits as they
  stood. luau-engineer A had no edits in the tree yet.
- I did not run `mutate.py`. The task's definition of done did not ask for it. Its `mutant/` root is shared, and A and
  ui are working in this checkout.
- Stale check by hand: every mutate entry and harness pin that reads `sendRunState` still finds its text, exactly once.
  Two old texts now match inside a deeper line (rows 2 and 3 of the table below). They mutate the right line but leave
  a stray tab, so re-aim them too.
- Pre-check of everything proposed below (scratch `premut.py`):
  - It imports `run_harness.py`'s own `luau_code` and `whole_lines` and counts each proposed pin on the worktree's files
    with comments blanked. Every baseline count is 1.
  - It then applies each proposed mutant alone. Every old text is found exactly once, and every mutant moves at least
    one pin: 19 of 19 caught.

## Correction to my W1b report

My W1b report said the `CombatArena` collision group "was never registered since P5". That was wrong:
`EnemyService.ArenaCollisionGroup()` registered it (slice 2's "Checked and found clean"). Nothing changes in behaviour.
A fresh group collides with every group, and `BarrierGroups` copies Default's rule.

## For the other owners

### Designer: re-aim (old text, then new text; `\t` = one tab)

`src/combat/server/Services/ArenaService.luau`, inside `local function sendRunState(`:

| Reader | Old | New |
|---|---|---|
| `run_harness.py` `L4B_LINES["sendFloors"]` (lines) | `\t\tsent.floors = floors` | `\t\t\tsent.floors = floors` |
| `run_harness.py` `L4B_LINES["sendNote"]` (lines) | `\tplay.cellsSent[userId] = seq` | `\t\tplay.cellsSent[userId] = seq` |
| `mutate.py` "l4b: a first send drops its cells" | `"\t\tsent.floors = floors\n"` → `""` | `"\t\t\tsent.floors = floors\n"` → `""` |
| `mutate.py` "l4b: a member's note is never written" | `"\tplay.cellsSent[userId] = seq\n"` → `""` | `"\t\tplay.cellsSent[userId] = seq\n"` → `""` |

Unchanged and still green:
- `sendAttach` (text): `local floors, cellsWent = RunFloors.Attach(runFields.floors, seq, play.cellsSent[userId])`.
  The text is unchanged and now sits at two tabs, so a whole-line pin would be `\t\tlocal floors, cellsWent = ...`.
- `sendOrder` (Attach, then `play.cellsSent[userId] = seq`). The new `~=` test does not contain the note's substring.
- `noteWrites`: still 3. The regex does not match `~=`.
- `attachCalls`, `runStateSpelled`, `sendRunStateCalls`.
- mutate "l4b: a send asks Attach with the set".
- All of WaveService.

### Designer: F3, the server's final lines (whole lines with their indentation)

The function as it now stands (`ArenaService.luau:651-663`):

```lua
local function sendRunState(player: Player, userId: number, runState: Types.RunState): ()
	local seq = runFields.floorsSeq
	local sent = runState
	if play.cellsSent[userId] ~= seq then
		local floors, cellsWent = RunFloors.Attach(runFields.floors, seq, play.cellsSent[userId])
		if cellsWent then
			sent = table.clone(runState)
			sent.floors = floors
		end
		play.cellsSent[userId] = seq
	end
	RemoteService.FireClient(player, "RunState", sent)
end
```

Pins I propose, all in `SEND_RUN_STATE_BODY`, each counted 1. The names are suggestions.

| Pin | How | Text |
|---|---|---|
| `sendSkip` (new, s1) | lines | `\tif play.cellsSent[userId] ~= seq then` |
| `sendAttach` (optional: make it whole-line) | lines | `\t\tlocal floors, cellsWent = RunFloors.Attach(runFields.floors, seq, play.cellsSent[userId])` |
| `sendCellsWent` (new, F3) | lines | `\t\tif cellsWent then` |
| `sendClone` (new, F3) | lines | `\t\t\tsent = table.clone(runState)` |
| `sendFloors` (re-aimed) | lines | `\t\t\tsent.floors = floors` |
| `sendFloorsWrites` (new; catches review mutant 6) | regex | `\bsent\.floors\s*=(?!=)` |
| `sendNote` (re-aimed) | lines | `\t\tplay.cellsSent[userId] = seq` |
| `sendFires` (new) | lines | `\tRemoteService.FireClient(player, "RunState", sent)` |

Mutants I propose, each `(ARENA_SERVICE, old, new)`, and the pin that catches it:

| Mutant | Old → new | Effect | Caught by |
|---|---|---|---|
| the skip never passes | `"\tif play.cellsSent[userId] ~= seq then\n"` → `"\tif false then\n"` | no member ever gets a cell or a note | `sendSkip` |
| the skip always passes | same old → `"\tif true then\n"` | s1 undone: Attach's copy on every send. Wire-equivalent, so only the pin can see it | `sendSkip` |
| the skip reads "never sent" | same old → `"\tif play.cellsSent[userId] == nil then\n"` | a noted member never gets a new set's cells. The lobby's `{}` set leaves everyone noted, so no run would ever send cells. This is the likeliest "simplification" | `sendSkip` |
| review 5 | `"\t\tif cellsWent then\n"` → `"\t\tif false then\n"` | no client ever gets a cell | `sendCellsWent` |
| review 6 | `"\t\t\tsent.floors = floors\n"` → `"\t\t\tsent.floors = floors\n\t\t\tsent.floors = runState.floors\n"` | no client ever gets a cell | `sendFloorsWrites` |
| review 7 | `"\t\tif cellsWent then\n"` → `"\t\tif cellsWent or true then\n"` | equivalent now that the skip stands; only the pin sees it | `sendCellsWent` |
| the shared payload mutated | `"\t\t\tsent = table.clone(runState)\n"` → `"\t\t\tsent = runState\n"` | Broadcast's one payload gains the cells, and every later member in the loop is sent them too | `sendClone` |
| the note never written | `"\t\tplay.cellsSent[userId] = seq\n"` → `""` | cells on every send: review 7's harm, now that the skip stands | `sendNote` (this is the re-aimed existing entry) |
| the bare payload fired | `"\tRemoteService.FireClient(player, \"RunState\", sent)\n"` → `"\tRemoteService.FireClient(player, \"RunState\", runState)\n"` | no client ever gets a cell | `sendFires` |

### Designer: F6, `payMentors`' deciding lines (WaveService, unchanged; body regex `(?ms)^local function payMentors\(.*?^end$`)

| Pin | How | Text (line in file) |
|---|---|---|
| `mentorNone` | lines | `\tif total <= 0 then` (:730) |
| `mentorFloor` | lines | `\t\tif mentor.waiting or (tally[mentor.userId] or 0) / total < coop.mentorMinDamageShare then` (:739) |
| `menteeOther` | lines | `\t\t\t\tother ~= mentor` (:749) |
| `menteeFloor` | lines | `\t\t\t\tand (tally[other.userId] or 0) / total >= coop.mentorMinDamageShare` (:750) |
| `menteeRate` | lines | `\t\t\t\ttable.insert(menteeRates, other.incomeRate)` (:752) |
| `mentorBonusCall` | lines | `\t\tlocal bonus = Combat.MentorBonus(combatConfig, mentor.incomeRate, menteeRates)` (:755) |
| `mentorValor` | lines | `\t\tstate.combat.valor += bonus` (:759) |
| `mentorCard` | lines | `\t\tArenaService.CreditMentor(mentor.userId, bonus)` (:760) |
| `bossPaysMentors` (whole file, in `onCrowdKilled`) | lines | `\t\tpayMentors(combatConfig, tally)` (:957) |

Mutants I propose, each `(WAVE_SERVICE, old, new)`:

| Mutant | Old → new | Caught by |
|---|---|---|
| review 1: a waiting mentor paid | `"if mentor.waiting or (tally[mentor.userId]"` → `"if (tally[mentor.userId]"` | `mentorFloor` |
| an idle mentor paid | the whole `:739` line + `\n` → `"\t\tif mentor.waiting then\n"` | `mentorFloor` |
| a mentor at the floor unpaid | `"(tally[mentor.userId] or 0) / total < coop.mentorMinDamageShare"` → `"... <= coop.mentorMinDamageShare"` | `mentorFloor` |
| review 2: mentees under the floor | `"\t\t\t\tand (tally[other.userId] or 0) / total >= coop.mentorMinDamageShare\n"` → `""` | `menteeFloor` |
| a mentee at the floor dropped | `"(tally[other.userId] or 0) / total >= coop.mentorMinDamageShare"` → `"... > coop.mentorMinDamageShare"` | `menteeFloor` |
| the mentor's own rate as the mentee's | `"table.insert(menteeRates, other.incomeRate)"` → `"table.insert(menteeRates, mentor.incomeRate)"` (nobody is ever carried) | `menteeRate` |
| the bonus against rate 0 | `"Combat.MentorBonus(combatConfig, mentor.incomeRate, menteeRates)"` → `"Combat.MentorBonus(combatConfig, 0, menteeRates)"` | `mentorBonusCall` |
| the wallet unpaid | `"\t\tstate.combat.valor += bonus\n"` → `""` (the card says paid) | `mentorValor` |
| the boss pays no mentor | `"\t\tpayMentors(combatConfig, tally)\n"` → `""` | `bossPaysMentors` |

Notes:
- `menteeOther` mutated to `true` is equivalent under the shipped `mentorRatio` 0.125: a rate is never below an eighth
  of itself. Pin it, but do not expect a behaviour test to see it.
- `mentorNone` mutated to `< 0` is also equivalent: a zero tally reads 0/0 = NaN, so no mentee is counted and the bonus
  is 0. The pin is cheap, and the guard is worth keeping as text.
- Review mutant 3 is in A's file, `src/shared/Combat.luau`, inside `function Combat.MentorBonus(`. The deciding line is
  `\t\tif rate < threshold then`; the mutant is `<` → `<=`. It is for the designer's `check_stage_mirror.py`
  MentorBonus comparison (fixture rates plus the `hostRate × mentorRatio` edge). A text pin on that line is my
  pre-check only.

### Nothing for the lead, ui or A

No remote, config key, project file or hub file changes. The ui's `applyFloors` lines (F3's client half) are the
ui-engineer's to confirm.
