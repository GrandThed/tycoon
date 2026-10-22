---
name: l4-real-forest-2026-10-21
description: L4 "the real forest" started 2026-10-21 on Ben's "lets start L4" — branch, study brief, three study parts; record of decisions as they come
metadata:
  type: project
---

L4 "the real forest" (MISSIONS_DESIGN §14: scenery, the Camp Chief, the map in the hub, rewards balanced; the first
version that may be published) started 2026-10-21 on Ben's "lets start L4". Work is on branch `l4-real-forest` in the
worktree `C:\Users\benja\Desktop\tycoon-p5` (reused; it was parked on a detached `main` at 443c704).

Same order as L2 and L3: a groundwork study from `docs/prompts/l4-study.md`, three Opus agents in parallel (Part A
the forest → `l4-study-report-forest.md`; Part B the Camp Chief and the raiders' looks → `l4-study-report-chief.md`;
Part C the hub map, rewards, the end screen and the publish → `l4-study-report-publish.md`), then Ben's decisions as
click questions with previews, pictures of the dressed forest before any upload, then contracts from files, fresh
agents per round.

Bound by earlier rulings (in the brief): natural barriers instead of fenced squares, the sniper perches fixed
(`SNIPER_KNOWN_LIMIT_L4` empty, Normal and Hard), the Camp Chief from the existing boss rules with a new model, the
end screen with coins flying in, both places publish together from `main`, R15-only avatar setting before it.

**Why:** a fresh session would otherwise restart the study or miss that L4 is the publish milestone.

**How to apply:** check the branch's `docs/prompts/l4-*` files for what is done before delegating. See
[[l3-armory-2026-10-20]], [[missions-replan-2026-10-13]], [[agent-context-cost-2026-10-13]].

**Ben's eight decisions (2026-10-21, click questions with sketches; the lead's recommendation on all eight; record:
MISSIONS_DESIGN §26 on the branch):** lookout to the trailhead (study variant V3, empties the sniper list by data);
natural camp edges on today's outlines (no crowd change; organic outlines not in L4); real models for all seven looks
(fodder, slinger, marksman, lobber, brute, plated elite, the Camp Chief); the Chief's own move a war-club sweep; the
city map departs straight into the level (lobby countdown, fallback = lobby with it picked); the Raider Arena hidden
for the publish; the end screen = tally rows then coins flying in and Timber piling; **run cash grows with the city's
era** (fixed per kill × an era multiplier, a clear worth a few minutes of that era's income; this bends C0's "fixed cash
per enemy", which he chose knowing a clear was ~15 s of Village income). Still his later: the forest mood (two-mood
renders), the Chief's look (A skull mask + Warhammer vs B antlers), how to publish (staging first recommended).
Lead rulings: baked ground and cliff skins; dressing never changes collision; invisible tree-line walls; tell surfaces
on raiders are untextured pieces painted by `Color` (a textured MeshPart may ignore Color; no Studio check needed).

**W1 "the forest on paper" running (2026-10-21):** three Opus agents from briefs `docs/prompts/l4-w1-{lookout,forest,
raiders}.md`, reports into `docs/prompts/l4-w1-reports/`. No uploads in W1. Then Ben's look at the pictures, W1b
(old mission code removed, after the designer's track), W2 in the game with one harvest paste, W3 city map / end screen
/ rewards, W4 publish readiness.

**Picture gate passed the same day (MISSIONS_DESIGN §27):** Ben approved the dressed forest as rendered
(`assets/testfit/out/Levels/ForestRoad/_L4_forest_overview.png`, `_L4_moods.png`), **mood B** (haze, dungeon place only),
the Chief **look A** (skull mask + Warhammer), the raider style, and **R8 "judged fairly"** (whole run snipe-then-fight vs
fight-all with the same gear over 30 seeds; the Road3 Hard sword-T1/bow-T4 burst was red before L4 on 12 of 30 seeds).
Pictures were shown as local PNG sheets linked in the chat (made with a scratch Pillow script), then click questions.
W1 is committed on `l4-real-forest`: the lookout at the trailhead (`SNIPER_KNOWN_LIMIT_L4` removed), the forest generator
`tools/levels/forest.py` + `forestcheck.py` (149,761 triangles, 62 invisible walls, 38 baked meshes, 4 textures, 4 props),
the raider kit prototypes. The layout is `src/shared/Layouts/Levels/ForestRoad.json`, not `Config/Levels/1_ForestRoad.json`.
W1b (old mission code out, the dash proven by the server's ring, RunState cells once) runs in a second worktree
`tycoon-p5b`, branch `l4-w1b`; W2 tracks running: the other four raiders, the asset route (forest meshes land in
`templates/_levels/ForestRoad` → `ReplicatedStorage.Assets.Levels`), the W2 contract draft. One session-limit cut on
2026-10-21 (reset 14:10); four agents resumed by SendMessage with nothing lost.

**Rocks redone (2026-10-21, after the gate):** Ben came back with two reference images (bevelled standing stones; cliffs
of clustered stacked bevelled blocks) and "the stones leave so much to offer". Saved in
`assets/research/2026-10-21-l4/ref_rocks_*.png`; a fresh rock builder redoes every rock from `docs/prompts/l4-w2-rocks.md`
before any upload. Lesson: the noisy triangulated cliff skins passed his first look at the whole-level renders but not a
second one; for any generated natural surface, show a close-up kit sheet of the pieces beside the level views.

**Mountain climb added to L4 (2026-10-21, Ben's own idea, MISSIONS_DESIGN §28):** a double-jump parkour of about 8 hops
round a mountain behind the trailhead, built now with the forest (one paste); the summit chest is a fourth secret
`mountain` giving **the Castle Key** (= the opened secret in `combat.secrets`, no profile change); the Castle's plan owes a
room this key opens. Designer brief `docs/prompts/l4-w2-mountain.md` (designs on an in-memory layout copy, writes the real
layout after the lead's `mountain-go.md`, new gate `tools/check_parkour.py`); then the forest is dressed round it and the
W2 contract gets the `key` reward.

**State 2026-10-22: uploads and harvest done.** (Was: paste pending.) Ben approved the rocks rework, the mountain and the less
regular walls ("yes, as it is"; he declined climb markers: finding the way up is part of the challenge) and all seven
raiders. 81 uploads first try (`l4-real-forest` 9ad3cb5: 37 level meshes, 5 level images, 4 forest props, 35 raider
stages; Assets.json v6 `levels.ForestRoad`, plan hash `23851a6f417491c1`); `harvest.luau` holds 81 records, put on Ben's
clipboard; he pastes in `tycoon\build\test.rbxl` (Edit mode). After "done": save the clipboard to a file, count 81
`[HARVEST] {`, then runbook `docs/prompts/l4-w2-asset-run.md` steps 8+ (`raider_frames.py` does not exist yet: it is
W2's D2 tool; templates do not wait for it). The L3 session `tycoon-87` acked the upload announcement; tell it when the
harvest is done. W1b (old mission code out, the dash hold) is in its fix round in `tycoon-p5b`.
**Harvest done 2026-10-22 00:43** (Ben pasted the Output into the chat; his clipboard also held it: 81 records, saved to
scratch first): merged with no SIZE/FRAME/ROTATED line, 41 new templates (617 in all), manifest `ForestRoad ... in game`,
six place files rebuilt on `l4-real-forest` (148dacd). `raider_frames.py` (W2 D2) still owed before W2 merges. The L3
session was told the asset tools are free; Assets.json v6 lives only on this branch until it merges.

**State 2026-10-22 (after the weekly limit on the first account; Ben switched accounts and said "continue"):** W1b is
done and merged into `l4-real-forest` (37ccfe4): three fix rounds (F1 the dash hold; G1 a held hit keeps the knock rules,
found by the fix-diff review as a Major; H1 a clear waits for a held blow; H2/H3 error containment and gates), QA green
except the known R8 row (the qa-runner died on the limit after its runs finished: its logs in the scratchpad's `qa-w1b/`
were read by the lead). **Every fix round needed its own fix-diff review again: round 1's hold introduced the Major.**
W2's code wave runs on branch `l4-w2` in `tycoon-p5` (kickoff `docs/prompts/l4-w2-kickoff.md`, five Opus owners: luau A,
ui A scenery + Castle Key UI, ui B raiders, D1 Chief/mood/R8 fair, D2 tools/gates/pins); `tycoon-p5b` is branch
`l4-verify` (the merged base) for the lead's long gates; `tycoon-p5c` holds the merged `l4-w1b-fix2` (removable).

**W2 code wave built 2026-10-22** (`l4-w2` afdce67 in `tycoon-p5`; five owners; harness 4,412; mirror 16,806 cases):
LevelDress/LevelScenery (all-or-nothing grey fallback, 70 tree-line walls in `ArenaBarrier`), mood B per client, raider
models on crowd bodies (`Raiders/Figures`, pure `Raiders/RaiderPose` mirrored by `check_raider_mirror.py`), the crowd kind
`chief` (sweep arc range 17, damage 30; dies in 80-86 s), the seated head on the server, the Castle Key (UI on SecretFx and
MapScreen), Studio keys Y/O/X/Z. **R8 judged against the same gear (the pair player): PASS**; against the sword alone Road3
Hard reads x1.014 (printed, ungated) — the lead's reading of §27.5, recorded in MISSIONS_DESIGN for Ben to overrule. R8 is
now its own gate `sim_range.py --r8 --check` (~54 min). Four-slice review running; full `mutate.py` (1,914 entries) runs in
`tycoon-p5b` (detached at afdce67). A second session limit (5 h window) cut D1/D2 once; resumed by SendMessage.
