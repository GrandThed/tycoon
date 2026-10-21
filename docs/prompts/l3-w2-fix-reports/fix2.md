# L3 W2 fix round 2: ui-engineer report (G1 to G3)

Worktree `C:\Users\benja\Desktop\tycoon-p5`, branch `l3-w2`. Nothing is committed. I edited only the seven files the
round names. The tracked `build/*.rbxl` and both `sourcemap*.json` were already modified from QA, and I left them
alone. `C:\Users\benja\Desktop\tycoon-p5b` was not touched.

## Files changed

- `src/combat/client/Controllers/HeldWeapons.luau`: G1 (the public `Flush`; `Muzzle` calls it).
- `src/combat/client/Controllers/FeedbackController.luau`: G1. One call plus a two-line comment. It stays at
  **163** top-level locals (`check_compile.py --counts`).
- `src/client/UI/ArmoryStage.luau`: G3.
- `src/client/UI/Theme.luau`: G3 (three constants and their comment removed).
- `tools/crowd_harness/run_harness.py`, `tests_l3_w2.luau`, `mutate.py`: the pins and mutants for G1 to G3.

## What each ruling became

**G1 (m1): a teammate's swing after a switch plays whole.**
- Added `HeldWeapons.Flush(userId: number): ()`.
  - It looks up the player and that player's rig. It runs the private `flush(rig)` only when the rig is bound to the
    player's current character, which is the same guard `Muzzle` had.
  - It does nothing unless a show is pending, so it costs one `GetPlayerByUserId` and a boolean test.
- `Muzzle`'s first line is now `HeldWeapons.Flush(userId)`, as the ruling asks ("`Muzzle` calls it too"). Its own
  flush block is gone.
- FeedbackController: the first code line of `elseif swing and not mine then` is `HeldWeapons.Flush(strike.userId)`.
  It comes before `FrostFx.OnStrike` and `SwingOther`. A plain call opens no block, so T9's `otherBlocks` stays 0.
- Why this order works (read in WeaponController, unchanged):
  1. Flush runs `show`, and the hold listener's `setRest(…, 0)` starts the ease down and bumps `rig.token`.
  2. Then `SwingOther` → `swingRig` → `cancelRig` snaps the arm to the new rest 0 and bumps the token again.
  3. The windup and its `task.delay` continuation then hold the live token, so the strike leg and the settle play.
  4. The deferred flush that follows finds nothing pending.
  - The weapon in the hand is also the melee model when the swing starts.

**G2 (m2): order and constructor pins.**
- `L3W2_ORDER` has `"muzzleFlushFirst": ("heldMuzzle", "HeldWeapons.Flush(userId)", "rig.inHand")`. The flush call
  is the anchor rather than `flush(rig)`, because `Muzzle` now calls the public one.
- `rigPending` pins `"\t\tpending = false,\n"` and `rigBound` pins `"\t\tbound = true,\n"`, each as a whole line in
  `bind`.
- One mutant each: the review's three, re-aimed at today's text (see the mutant table).

**G3 (m3, s1-stick, s2): the right stick no longer turns the stage.**
- Removed from ArmoryStage: the `InputChanged` stick listener, `onStick`, `look.stickX` and `look.stickAt` (used only by
  the stick).
- Removed from Theme: `ARMORY_STAGE_STICK_DEADZONE`, `ARMORY_STAGE_STICK_DEGREES_PER_SECOND` and
  `ARMORY_STAGE_STICK_STEP_SECONDS`, and their sentence in the comment.
- The per-frame turn is back to the plain `turnBy(Theme.ARMORY_STAGE_TURN_DEGREES_PER_SECOND * deltaTime)`.
- With the stick gone, `look.inputs` would have held only the focus listener, so it became one optional connection,
  `look.focus`.
  - `syncTurn` connects it once: `look.focus = UserInputService.WindowFocusReleased:Connect(endDrag)`.
  - `stop()` disconnects it and clears it, then ends any drag.
- These stay as they were: every drag end (its own `InputEnded`, a lost mouse release, focus loss, `stop()`),
  `syncTurn` with its three callers, and the low-end gate on the one `RenderStepped`.
- The header comment now says why the stick does not turn the stage: the world camera behind the screen reads it
  unsunk.
- s2 (zero the stick on `InputEnded` or a gamepad disconnect) is moot, because there is no stick state left.
- I added one pin the ruling did not name. `stageSticks` = 0 means no `Thumbstick1` or `Thumbstick2` appears anywhere
  in ArmoryStage's code, strings included, so m3 cannot come back unseen. It has one mutant.

## Pins (harness)

Removed (they named the stick): the body `stageStick` (`onStick`); the lines `syncStick`, `stickOnly` and
`stickLowEnd`.

Re-aimed:

| Key | Text now (whole lines, in its function) |
|---|---|
| `syncStep` | `"\t\t\t\tturnBy(Theme.ARMORY_STAGE_TURN_DEGREES_PER_SECOND * deltaTime)\n"` (syncTurn) |
| `syncFocus` | `"\t\t\tlook.focus = UserInputService.WindowFocusReleased:Connect(endDrag)\n"` (syncTurn) |
| `stopDrops` | `"\t\tlocal focus = look.focus\n\t\tif focus ~= nil then\n\t\t\tlook.focus = nil\n\t\t\tfocus:Disconnect()\n\t\tend\n\t\tendDrag()\n\tend"` (stop) |
| `muzzleFlushes` | `"function HeldWeapons.Muzzle(userId: number): (Vector3?, boolean)\n\tHeldWeapons.Flush(userId)\n"` (Muzzle: its first line) |

New:

| Key | Expected | What it holds |
|---|---|---|
| `otherFlush` | 1 | `\t\tHeldWeapons.Flush(strike.userId)` as a whole line in T9's branch |
| `otherFlushFirst` | 1 | it is the branch's first code line (comments blanked) |
| `otherFlushBefore` | 1 | it stands before the `SwingOther` line |
| `flushPublic` | 1 | Flush's whole body (lookup, current-character guard, `flush(rig)`), body `heldFlushPublic` |
| `flushPublicExits` | 0 | Flush has no way out |
| `muzzleFlushFirst` | 1 | `L3W2_ORDER`: the flush before `rig.inHand` in Muzzle |
| `rigPending` | 1 | `\t\tpending = false,` in `bind`'s new rig |
| `rigBound` | 1 | `\t\tbound = true,` in `bind`'s new rig |
| `syncFocusOnce` | 1 | `\t\tif look.focus == nil then` in syncTurn |
| `stageSticks` | 0 | no gamepad stick in ArmoryStage's code |

Unchanged and still green: `syncCalls` 4, `syncExits` 2, `gatedFrames`, `activeFrames`, `stageFrames`,
`otherBlocks` 0, `strikeExits` 1, `heldDirectShows` 4, `heldQueues` 3, `flushShows`, `queueOnce`.

Harness: **`HARNESS: PASS (4,031 checks)`**. It was 4,024: three removed, ten added.

## Mutants (`mutate.py`)

Removed (they named the stick):
- "the right stick is never heard";
- "any stick turns the stage";
- "the stick turns per event off low-end too".

Re-aimed at today's text, each caught:

| Mutant | Caught by |
|---|---|
| l3w2 T14: the model is posed every frame | `stagePoses` |
| l3w2 fix C3: the slow turn never turns | `syncStep` |
| l3w2 fix C3: a lost focus keeps the drag (`Connect(function() end)`) | `syncFocus` |
| l3w2 fix C3: a low-end device keeps no focus listener (was "... gets no stick") | `syncExits` 3 |
| l3w2 fix C3: stop leaves the focus listener set (was "... the listeners counted") | `stopDrops` |
| l3w2 fix C4: Muzzle reads before the pending show (drops `HeldWeapons.Flush(userId)`) | `muzzleFlushes`, `muzzleFlushFirst` |

New, `L3W2_FIX2_MUTATIONS` (run alone with `"l3w2 fix2"`): **11 run, 0 not caught**.

| Mutant | Checks that fail |
|---|---|
| G1: another player's swing flushes nothing | `otherFlush`, `otherFlushFirst`, `otherFlushBefore` |
| G1: the flush after the arm swings (moved below `SwingOther`) | `otherFlushFirst`, `otherFlushBefore` |
| G1: the swing flushes my own rig (`localUserId()`) | `otherFlush`, `otherFlushFirst`, `otherFlushBefore` |
| G1: the flush inside a block (`if strike.tick then`) | `otherBlocks`, `otherFlush`, `otherFlushFirst`, `otherFlushBefore` |
| G1: Flush shows nothing | `flushPublic` |
| G1: Flush shows a character the player has left | `flushPublic` |
| G1: Flush leaves early | `flushPublic`, `flushPublicExits` |
| G2: Muzzle reads the hand before the flush (the review's first) | `muzzleFlushFirst`, `muzzleFlushes` |
| G2: a new rig starts unbound (the review's second) | `rigBound` |
| G2: a new rig starts pending (the review's third) | `rigPending` |
| G3: the right stick turns the stage (a Thumbstick2 listener in syncTurn) | `stageSticks` |

**Full run, every `l3w2` mutant: `MUTATIONS: 226 run, 0 not caught`.**
- The count is 218, minus the 3 removed, plus the 11 new.
- The stale check passed: every entry's text occurs exactly once.
- The baseline was `HARNESS: PASS (4,031 checks)`.

## Gates

| Gate | Result |
|---|---|
| stylua `--check` (the four sources and `tests_l3_w2.luau`) | clean |
| selene on the four sources | 0 errors, 0 warnings |
| selene on `tests_l3_w2.luau` | 83 `undefined_variable`, the same 83 as before: the bundle's shared locals |
| luau-lsp `analyze`, `tools/types/globalTypes.d.luau`, default sourcemap regenerated into my scratchpad | 0 diagnostics (ArmoryStage, Theme, ArmoryScreen, ArmoryShelf) |
| luau-lsp, combat sourcemap regenerated into my scratchpad | 0 diagnostics (HeldWeapons, FeedbackController, WeaponController, ArmoryStage, Theme) |
| `py tools/check_compile.py` | PASS, 180 files. FeedbackController is at 163 top-level locals |
| `rojo build`, both projects, into my scratchpad | builds |
| Harness | `HARNESS: PASS (4,031 checks)` |
| `mutate.py … "l3w2"` | see above |
| Line endings | LF, 0 CR in all seven files |

The mutation runs ran on a scratch snapshot of the worktree (the tracked `src`, `tools` and both project files, copied
after my last edit and checked byte-identical for the seven files). They did not run in `tycoon-p5`, so its
`tools/crowd_harness/mutant/` was never used.

## Remotes and state consumed

- No new remote, attribute or state.
- `Flush` reads the same `rigs` table and the same three character attributes (through `show`).
- The stage reads `WindowFocusReleased`, `InputChanged` (the drag only) and `IsMouseButtonPressed`.

## Assumptions

- Roblox applies a replicated attribute's value at once, and queues its handler ahead of the strike remote that
  follows it, as C4 already assumed. So a flush at the head of the swing branch sees the slot change.
- Only the swing path needed it. The review names this branch as the one ordering-sensitive reader that `Muzzle`'s
  flush did not cover.
- The right stick still drives the world camera behind the open screen, in both places, exactly as in W1. Sinking it
  was the review's other option, and the lead did not take it.
- With no templates and no icons, nothing differs from W1:
  - `Flush` shows nothing when there is no model;
  - the stage has no model, so `syncTurn` stops and connects nothing;
  - W1 had no stick.

## Required changes outside my files

- **docs-keeper (s3, as ruled):** add to PLAYTEST's two-client step: "P1 holds the bow, presses 1 and swings at once:
  on P2's screen the arm swings (windup, strike, settle), not a drop to hanging." PLAYTEST already says (line 5904)
  that the right stick does not turn the stage.
- **Lead, `docs/prompts/l3-w2-fix-round.md` line 52**, if that file is kept as a record: it still describes C3's stick.
  The round file `l3-w2-fix2.md` supersedes it.

## What to check in Studio

**Before the paste** (today: no templates, no icons):
- Open the lobby Armory (K) and the hub Armory. Each must look exactly like W1: the text stage and the text cards.
- Hands are empty, arms hang, and Output has no `[HeldWeapons]` line.

**After the paste:**
1. **Two clients** (*Prueba → Clientes y servidores*, 2 players):
   - P1 holds the Longbow (arm raised), presses 1 and clicks at once. On P2's screen, P1's arm drops to hanging, winds
     up, strikes and settles. The sword is in the hand from the first frame.
   - Every later swing looks the same.
   - P1 switches slot and casts Volley or Blade Storm: on P2's screen the effect leaves from the weapon now in P1's
     hand.
2. **Gamepad, Weapons tab:**
   - The right stick does not turn the weapon.
   - The d-pad still browses the cards.
   - The weapon still turns slowly by itself, and a mouse or touch drag turns it.
3. **Alt-tab mid-drag**, then move the mouse with no button down: the weapon does not follow, and the slow turn
   resumes.
4. **Graphics quality 1 to 3:** no slow turn; a drag still turns the weapon.

**Mobile emulator:** no size, position or tap target changed in this round, only connections and one call. The layouts
at 375 × 667 portrait, 667 × 375 landscape and 1920 × 1080 are W2's, unchanged (reasoned, not re-measured). A touch
drag still turns the stage, and a phone never had the stick.
