---
name: p4-enemy-roles-review
description: P4 "enemies that fight back" reviews (range only) - wave 1 verdict, what held, recurring timing patterns, how to run the checks from the tycoon-p4 worktree
metadata:
  type: project
---

P4 = crowd enemies attack and the player has health, in the Studio-only Proving Grounds. Contract:
`docs/INTERFACES.md` "# P4 contracts" (grep the heading; the file is ~585 KB). Worktree
`C:\Users\benja\Desktop\tycoon-p4`, branch `p4-enemy-roles`. See [[review-workflow]] for P1-P3.1.

**Wave 1 "they hurt you" (2026-10-07, uncommitted tree vs 0d00565): FIX, then ship.** New server
`CrowdBrain` (pure-ish AI, os.clock timeline, strikes only queued) and `VitalsService` (health on
Humanoid.Health, commit rule queue on its own Heartbeat, down/up, regen, god); client
`VitalsController`, `VitalsHud`, shared `Haptics`; codec v2 (state nibble + plated bit + 3-bit attack).
stylua clean, selene only the old LegacyPanel:200 warning, `check_compile.py --counts` PASS
(FeedbackController 159, InputController 144, CrowdRenderer 138), luau-lsp 0 errors, `sim_range.py
--check` PASS. Every finding came from reading.

**Why:** a later wave (roles, plate, boss) builds on these modules; the same timing traps return.

**How to apply:**
- **The contract grew during the review.** Rulings 16-20 were appended to INTERFACES 6 minutes after
  the Luau was last saved; two of them (17 health pinned to tier 1, 18 hits decided together do not
  stack through a knock) were not in the code. Before reporting, re-read the contract section and
  compare `ls -la --time-style=full-iso` mtimes of contract, config and Luau.
- **A green sim is not evidence for the Luau.** `sim_range.py` mirrors the rules by hand (its
  "[together]" tag implemented ruling 18 while the server did not). Unlike CityFabric there is no
  Luau cross-check; diff each sim tag against the code.
- **Recurring pattern (new): a grant stamped with a fresh `os.clock()` inside a pass that compares
  against the pass's captured `now`.** `settle` decides hit 1, which opens knock i-frames at a fresh
  clock; hit 2 in the same pass tests `from <= min(now, decideAt)` and never sees it. Enemies that
  start a windup in the same crowd step share an impact time exactly, so same-pass is the common
  case, and they stay in lockstep afterwards.
- **Recurring pattern (new): an event raised on a coarse step, judged against a deadline shorter
  than the step.** Impacts reach VitalsService up to one crowd step (67 ms) after T; lag can be
  50 ms. Consequences: the root is sampled late, a hit or kill in that gap cancels a blow the client
  already drew, and a "latest window only" record (`RangeService.IframeWindow`) can lose the window
  that covered T. Ask of every "decide at T + x": when does the decider first hear of T?
- **Design hole to re-check each wave:** the `height` rule plus a free 18-stud jump (0.86 s
  airtime, above 5 studs for ~86% of it) makes a hopping player nearly immune to ground attacks;
  the sim has no hopping player.
- What held and need not be re-derived: passive sets take the old code paths (mind == nil);
  every CombatFx listener ignores unknown kinds; range handlers stay behind `active` + IsStudio;
  `CrowdRenderer.followThreat` (start, confirm, cancel, overlay) agrees with the server's state
  timing; the client never shows a blow later than the server except on a body first seen
  mid-windup (a player joining mid-fight).
- Run checks without dirtying the tree: `rojo sourcemap combat.project.json -o <scratch>/sourcemap.combat.json`
  and pass that path to luau-lsp (the tracked sourcemap stays untouched).
- Wave 2 must be judged on: keepAway brain, shot/line/lob/lane, plate (`heavy` is judged per
  `CrowdService.Damage` call, before armour), enemy-shot raycast budget, `Controllers/ThreatFx/`.
