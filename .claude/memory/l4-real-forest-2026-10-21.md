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
