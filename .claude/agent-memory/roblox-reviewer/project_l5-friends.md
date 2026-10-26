---
name: l5-friends-review
description: L5 "Friends" reviews (parties in a level, branch l5-friends in tycoon-p5) - W1 slice 2 server 0C/1M/2m/4s (rebuilt after an overwrite: failed trip home launders down/out; 9 unpinned executor holes); W1 slice 1 pure rules 2026-10-26 0C/1M/2m/2s (gatehouse hold band = triggerHeight while the walled camp uses zone.ceiling: a double-jump apex is "out" at the close, same as slice 2 M1; armed-start and B-reset hold rules unreached by any fixture; Mentor floor shared with the loot floor); W1 slice 4 data/sims/gates 0C/1M/2m/5s (same band Major seen as a gate gap: check_hold has no band-vs-highest-root rule; W1 step 3's 338-Timber reference is a full clear's while step 3 skips camp B, ~170; entry spread "on the floor" never tested); W1 slice 3 client 0C/0M/3m/4s (client half ungated, 11/11 probes pass incl. Return-on-a-tap; held Return in the thumbstick corner beats the hold with a still thumb; name list truncates the hold line's countdown); Forest Road gatehouse facts; bundle-prefix probe and review-mutant recipe; SHARED file: Edit only, never Write
metadata:
  type: project
---

L5 W1 ("Two in Forest Road") was reviewed in four slices from `docs/prompts/l5-w1-review.md`. The code diff is
b87ad5f..b98b2ff. Findings are in `docs/prompts/l5-w1-review/<n>-<slice>.md`. Several reviewers write in that folder,
so write only your own file.

**SHARED FILE: Edit only, never Write.** Slice 2 created this file at about 12:30 on 2026-10-26. Slice 1's Write at 12:33
overwrote it. Slice 2's section below was rebuilt by slice 1 from `2-server.md` and slice 2's index line, so slice 2's
own wording of its patterns and recipe is lost. Re-read the file and the index right before any change: the slices
finish minutes apart.

## W1 slice 2, server executors (2026-10-26): 0 Critical, 1 Major, 2 Minor, 4 Suggestions (rebuilt from `2-server.md`)

- **M1 is the same defect as slice 1 M1; count it once.**
  - `TakeIn` / `InHold` judge the gatehouse by `triggerHeight` 30, but the root peaks at 33 on a double jump.
  - So a hopping member is marked `out` at the 0 s close.
  - The same band gates `releaseAtBoundary`.
- **m1. A failed trip home launders down and out.**
  - `trySendHome` calls `ArenaService.Remove` before it teleports.
  - On a refused teleport, the rejoin skips admission (`WasAdmitted`). `runJoinSequence` calls `StandUp`, and `Admit`
    sets `out = false`.
  - So an out member comes back waiting and is released into the boss room. A downed member comes back at full health.
  - Reachable in Studio with `build/combat.rbxl`, the bridge and `ForceTeleportFailure`.
- **m2. Nine unpinned executor holes pass PASS 5,930.**
  - The out member's rescue `continue`. Without it, an out member is rescued into the shut room.
  - The `continue` after `member.out = true`.
  - `LevelService`'s `state.holds[zoneId] = part` write. Without it, the door never goes.
  - The door's Size and Position.
  - `outPoint`'s waiting flag.
  - `downFrom` in `ForceDown`.
  - `ToLeader`'s fence block.
- **Suggestions:**
  - `downMe` accepts a waiting member, and `ReleaseWaiting` keeps `vitals.down`.
  - `ForceDown` copies the real down.
  - A holding camp that is not the last never lets the gatehouse in on its last boundary, because `entrySpread` is nil
    in `travel`.
  - `Reset` keeps `boot.pick`.
- **Pattern (as at L4):** the pins hold the calls, not the conditions or `continue`s between them. The fix that sticks
  is a pure rule. One example: the out member's rescue as a `StageFlow.Rescue` case.
- **Verified clean:**
  - `credit` multiplies materials and valor only.
  - Every count excludes out members: `fightingIds`, the clear bonus, the star, `RunLost`, `mayJudge`, `mayAct` and
    `tickSecrets`.
  - `raiderHpMult` is set once, before `placeResidents`.
  - The door is in the Default group with `CanQuery` on, and never in `ArenaBarrier`.
  - `RequestMapPick` is validated, rate-limited, leader-only and lobby-only.
  - The levers are inert outside Studio.
  - The tick does not yield.
- **Recipe:** `scratchpad/rev-w1-2/drv/probe.py`. Review mutants go in a second archive copy.

## W1 slice 1, pure rules (2026-10-26): 0 Critical, 1 Major, 2 Minor, 2 Suggestions

The slice covers Types, Combat (RaiderHpMult, PartyLootMult, LootFighters, MentorBonus), StageFlow (hold, InHold,
HoldView, TakeIn, EntrySpread, Skip's hold stop), LevelGeometry.HoldDoorBox and `tests_l5w1.luau`.

**Patterns:**
- **The L1c "height ceiling on inside" recurred in a new rect.**
  - The hold's band is `levels.triggerHeight` (30). The walled camp it opens onto uses `zone.ceiling` (64).
  - A root at a double jump's apex (3 + 18 + 12 = 33) in the gatehouse is "out" at the 0 s close.
  - The harness pinned 30 the wrong way (`tests_l5w1.luau:233/238/319`), and the py mirror copies it.
  - Slice 2 found the same thing independently. Count it once.
  - Probe: for every new "is the body in X" rect, compare its height band against the band of whatever it hands off to.
- **A rule every fixture reaches from one step only.**
  - The hold start in step `armed` survived as travel-only, because every fixture's holding camp follows a travel
    stage.
  - That mutant locks a party out of any camp that directly follows another camp.
  - B's later-camp reset of `holdDone` also survived.
  - Probe: list the steps a new branch accepts, then check that some case enters it from each.
- **A floor key shared by two rules.** `LootFighters` reads `coop.mentorMinDamageShare`. A missing or 0 floor reads 0,
  and then a zero-damage alt counts (the harness asserts it). A tuning of the Mentor silently reopens the idle-alt loot.

**Verified facts:**
- **Forest Road gatehouse:**
  - The walk is x 256..321.5, z −52..−36. The turn is x 305.5..321.5, z −36..−26. The floor top is y 12. The walls top
    out at 76.
  - Camp C is x 256..371, z −26..89, fence 64 / thickness 2.5. The trigger starts at z −28.5 and `inner` at z −24.
  - Hold rects: the walk, and the turn to z −28.5. The door is z −30.5..−28.5, y 12..76.
  - The entry is (309.5, −16). EntrySpread k1–k4: (309.5, −16), (305.5, −16), (313.5, −16), (309.5, −12).
- **Numbers:** `L1.real.ROOT` 3, `triggerHeight` 30, `triggerBelow` 4, `holdSeconds` 20, `startSpacing` 4.
  Forest Road stages: 1 is travel, 2 is camp C (the only hold).
- **LootFighters' denominator:**
  - It is the whole run book. A leaver's damage is in it.
  - Harness alone: a share among the fighters only survives.
  - `check_stage_mirror`'s leaver book under the 0.3 floor catches it.
- Baseline on a git archive of b98b2ff: harness `PASS (5,930)` in 31 s; 131 `l5w1` mutate entries, 0 stale.

**Recipe (scratch `rev-w1-1/drv/`):**
- `probe.py <tree> <luau> <chunk.luau>`:
  - It imports the copy's `run_harness.py`.
  - It bundles `prelude` plus TESTS up to `tests_l5w1.luau`, with the verdict stripped, then appends the chunk.
  - It prints the `PROBE` lines.
  - Inside the chunk, the case files' locals (`L1.real.resolve/plan/rules/ROOT`, `vec`, `L5A`) are in scope.
  - One run takes about 10 s, faster than a full harness.
- `mut.py <tree> <luau> <mutants.py>`:
  - It applies `(name, relpath, old, new)` one at a time and runs the copy's own harness: about 40 s each.
  - It writes with `write_bytes`.
  - Double-check that a mutant is not an equivalent rewrite before reading "SURVIVED".
- `stale.py`: exec mutate.py up to "# Run from one checkout against another", then count each entry's old text.

## W1 slice 4, data, sims and gates (2026-10-26, b98b2ff): 0 Critical, 1 Major, 2 Minor, 5 Suggestions

Findings: `docs/prompts/l5-w1-review/4-data.md`. Several slice reviewers share THIS memory file: re-read it and Edit
only your own section, never Write it whole. A Write of mine was overwritten here once.

**Patterns:**
- **The same hold-band Major, seen from the gate side.** `check_walled` proves the camp's trigger covers the highest
  root (`check_levels.py:3598`: jump + double jump + `abilityHeight` 10 + root, so +43 over a floor). `check_hold` has no
  such rule.
  - Mirror, harness, mutate and mirror_mutants all pin the 30: `tests_l5w1.luau:233/238/319`,
    `check_stage_mirror.py:1455`, `mutate.py:10668`, `mirror_mutants.py:389`.
  - So every gate is green.
- **A playtest reference copied from a full clear onto a script that skips camps.**
  - W1 step 3 uses N to pass camp B, and an N approach pays nothing.
  - So the "338 Timber for two" claim should read about 170.
  - Compute the route's own stock: `sim_range.groups_of` per camp × `rewards[kind].materials` × `rewardMult`.
  - Normal Timber of resident stock: A 9, B 95, C 18 + Chief 76.
- **A check message that claims more than the code tests.** `check_hold`'s entry spread prints "stands on the floor" but
  never looks up the ground.

**Verified, safe to reuse:**
- `check_hold`'s door, flood, perch and sight rules are real, and the mutants are sized right.
- Without the door, the walled `doorway` row's exempt eye (321.49, −28.55) lies inside the door's footprint.
- The sim_range hold mirror equals StageFlow row for row.
- mutate.py: 2,628 entries, 0 stale. The 4 re-aims are equivalent, and the owners' blocks are pasted verbatim.
- Gate results on the archive copy:
  - `check_levels`: 31 s;
  - `check_stage_mirror`: 9.6 s (copy `luau.exe` into the copy's `tools/bin`);
  - `forest.py check`: PASS, plan hash `5792c659ca2e772e`.

**Recipes (scratch `rev-w1-4/py/`):**
- `stale.py <tree> <out.json>` needs the whole `git archive`, because run_harness reads `combat.project.json`.
- `mdiff.py` compares two dumps.
- `blockcmp.py <owner file> <target>` checks that a pasted block is verbatim.
- `apex.py` runs `sim_range.in_hold` / `take_in` at jump heights on the shipped plan.
- `campstock.py` gives the per-camp resident stock.

## W1 slice 3, the client (2026-10-26, b98b2ff): 0 Critical, 0 Major, 3 Minor, 4 Suggestions

Findings: `docs/prompts/l5-w1-review/3-client.md`. Files: CombatUIController, CombatHud, MapScreen (HubMap is its other
host) and Theme.

**Patterns:**
- **The client half is ungated again**, as at L4 W1b/W3. Eleven one-line probes all pass `PASS 5,930`, including:
  - `local share = 1`, which turns the lead's 1 s hold rule (ruling 11.10) into a single tap;
  - `SetPhase(phase, waiting)`, which lets an out member's client attack again;
  - `not isLeader()` dropped from SetPick.

  ui-b had proposed pins in its report, and nobody adopted them. Check the "For the other owners" lists of the ui
  reports against `run_harness.py`.
- **A hold-to-confirm button in the thumbstick corner.** A 1 s hold plus a drag slop stops taps and drags, but not a
  thumb that rests still. The contract placed Return on the DOWN banner (bottom centre on a phone); ui moved it to the
  bottom-left run rows. For any "never by accident" control, ask where a resting thumb lands, not only where a tap
  lands.
- **A line that grows by names truncates its countdown.** The seconds were the last token. Two ordinary 10-character
  names give 299 design px at the 11 px floor, against 273 px at 640×360.
- A routing note in an owner's report can be stale against the final code. ui-b said `downMe` refuses an out member;
  DebugService accepts it. Check report claims about another owner's file before passing them to docs.

**Verified, safe to reuse:**
- Pad Y priorities:
  - Return's hold: High+2;
  - ArmoryScreen's toggle: High+1, bound only while the Armory is available (the lobby);
  - InputController's `RANGE_SWAP`: High.
- InputController's `cannotAct` covers attacks, draws, casts and the slot switch; movement and dash stay free.
- CampFx's "Checkpoint" is the only ShowNotice caller. Lever notices go to CombatFxController's toast.
- Portrait 375×667 thumb cluster, in viewport px: clusterLeft 153.7 and clusterTop 514.1. The bar is re-seated above the
  cluster: x 96–279, y 490–507.
- 640×360: the bar starts at x 228. The run rows' room is 232.7 design px on row 1.
- ★ (U+2605) is not in Montserrat-Bold; it renders from Roblox's fallback font. It was already in use (STAR,
  LEADER_MARK).

**Recipes (scratch `rev-w1-3/`):**
- `probe.py <tree> <luau> [indices]` holds `(label, file, old, new)` probes built with `chr(9)`, runs the copy's harness
  and restores with `write_bytes`. About 39 s a probe.
- `measure.py <fontsDir>` measures widths in Montserrat Bold and Medium. Run it with `PYTHONIOENCODING=utf-8`, or ★
  crashes the cp1252 console.

See [[l1c-chief-clearing-review]], [[l4-real-forest]], [[m11-port]], [[review-workflow]].
