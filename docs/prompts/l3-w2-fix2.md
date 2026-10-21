# L3 Wave 2 fix round 2 — after the fix-diff review (2026-10-21)

The fix-diff review (`docs/prompts/l3-w2-fix-diff-review.md`, on `git diff 5c0958b 31b1947`) found **0 Critical,
0 Major, 3 Minor, 3 suggestions**. One fresh agent does all of it. Branch `l3-w2` in `C:\Users\benja\Desktop\tycoon-p5`.
Read the review first (its probes: `C:\Users\benja\AppData\Local\Temp\claude\c--Users-benja-Desktop-tycoon\f6c03e29-23c5-4dc8-ba99-ba7296a3858e\scratchpad\l3w2fd\`).

## Rulings

**G1 (m1) A teammate's swing after a switch plays whole.** `HeldWeapons.Flush(userId)` (public; `Muzzle` calls it too)
runs any pending show of that player's rig at once; FeedbackController's `elseif swing and not mine then` branch calls it
as its first line, before `SwingOther`, so the arm is lowered before the swing starts. Pinned (whole line, order before
the `SwingOther` line) with a mutant.

**G2 (m2) Order and constructor pins.** An order pin that `Muzzle` flushes before it reads `rig.inHand`
(`L3W2_ORDER`), whole-line pins for `bound = false,` and `pending = false,` (or what they are) in `bind`'s new rig, one
mutant each (the review's three).

**G3 (m3, s1-stick, s2) The right stick no longer turns the stage.** C3's stick part is withdrawn: it also turned the
world camera behind the screen (CameraController and the hub's PlayerModule read the stick unsunk), Ben rarely uses a
pad, and the stage turns by itself and by drag. Remove the stick listener, `onStick`, `look.stickX` and the three
`ARMORY_STAGE_STICK_*` Theme constants, and every pin and mutant that named them. The drag ends and `syncTurn` stay.

**Not taken:** s1's ghost-tone pin (a Theme value is judged in Studio at Ben's look). **s3** goes to docs-keeper
(PLAYTEST's two-client step: "P1 holds the bow, presses 1 and swings at once: P2 sees the arm swing").

## Owner and gates

One `ui-engineer` (Opus) owns, for this round only: `src/combat/client/Controllers/HeldWeapons.luau`,
`FeedbackController.luau` (the one line; it stays at or under 163 top-level locals), `src/client/UI/ArmoryStage.luau`,
`Theme.luau`, and in `tools/crowd_harness/`: `run_harness.py`, `tests_l3_w2.luau`, `mutate.py`. Never touch
`C:\Users\benja\Desktop\tycoon-p5b`. `git status` and `git diff` first (the tracked `build/*.rbxl` and sourcemaps show as
modified from QA: leave them); commit nothing; kill only your own PIDs. Gates: stylua, selene, luau-lsp on both
sourcemaps (scratch), `py tools/check_compile.py`, the harness
(`py tools/crowd_harness/run_harness.py C:/Users/benja/Desktop/tycoon-p5 C:/Users/benja/Desktop/tycoon/tools/bin/luau.exe`),
and `mutate.py` filtered to `l3w2` (every entry caught, none stale). `export PATH="$HOME/.rokit/bin:$PATH"`; `py`; LF.
Report to `docs/prompts/l3-w2-fix-reports/fix2.md` and reply with it.
