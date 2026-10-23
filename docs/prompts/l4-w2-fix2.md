# L4 W2 fix round 2 (the lead's rulings on the fix-diff review)

Worktree `C:\Users\benja\Desktop\tycoon-p5`, branch `l4-w2` (review base 46fd98f; the sharded runner 88eeae5 is on top).
Findings: `docs/prompts/l4-w2-review/5-fix-diff.md` (0 Critical, 0 Major, 3 Minor, 4 suggestions; K1-K10 fixed). A sharded
full `mutate.py` run on 88eeae5 is going in `tycoon-p5b`: never touch that worktree. Every agent: `git status` and `git diff`
first, commit nothing, kill only its own PIDs, LF files, report to `docs/prompts/l4-w2-fix-reports/<role>-2.md` with "For
the other owners" (file, old text, new text; the deciding lines whole with indentation, a mutant for each).

## Rulings

**L1 (m2). The Chief's sweep has no blind slice.** `raiderpose.py`'s sweep check bins at 5° and requires the drawn span to
reach each edge of the wedge (within one bin), plus the hammer not lagging the tell's leading edge by more than one bin.
First turn the `follow` key's yaw further left so the hammer reaches the −75°..−60° edge at ≥ range − 0.5 (ui-b's table
says 12.46 is drawable there); if that cannot hold the range, narrow `arcDegrees` to what is swept (about 130) and say so
for D1, who re-measures the bands. Owner: **ui-engineer B** (both pose sides, as in the fix round). Re-render the Chief
strip.

**L2 (s1). The "!" follows the head.** `CampFx` moves a camp's "!" mark to the new head part when a placeholder swaps to its
model (or back with X), never drops it. Owner: **ui-engineer B** (`ThreatFx/CampFx.luau` or wherever the mark lives).

**L3 (s2). No crosshair behind the summary.** In a dressed level's `summary` and `ended` phases the crosshair hides while the
shoulder camera stays (K9). Owner: **ui-engineer A**.

**L4 (m1). Gates on the lines that decide (K3 client, LevelScenery helpers).** Whole-line pins, each with a mutant, on the
reviewer's eleven probes (`Figures.Build` call and its per-frame budget, `Take` never building, the cap split, the swap of a
waiting body, the lobby fill start, `isSkinned`, `isWall`, `teardown`'s state, `bodyInLobby`), re-aimed to ui A's and ui
B's final lines. Owner: **D2**, after ui A and ui B report.

**L5 (m3). The plan hash survives both Pythons.** Before packing, any value under 1e-6 in magnitude snaps to 0 and −0.0
becomes 0.0; a test proves a 6e-18 corner and a −0.0 corner pack like 0.0. The hash takes one new value: write it with
`forest.py build` (under plain `py`) into the dress file and into `Assets.json` only through `assets_config.save_assets`;
`upload_level.py --dry-run` must read 0 pending; the manifest re-generated. Owner: **D2**.

**Left:** s4 (whether `MeshPart.MeshId` reads the level templates' `MeshContent`) is checked only in Studio: it stays the
first step of Ben's look; a grey level with the warning `[LevelService] the level is grey` there means it does not.

## Order

ui-engineer A and ui-engineer B in parallel; D2 after both (L4 depends on their lines; L5 is independent). D1 only if L1
narrows the arc. Then the lead reads the diff; filtered `mutate.py` on the changed files plus the stale check.
