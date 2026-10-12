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

**Wave 2 "roles" (2026-10-08, uncommitted tree vs e14c4cb): SHIP WITH FIXES, 0 Critical, 1 Major.**
Wave 1's findings were all fixed or ruled (rulings 21-26; the hopper became ruling 21: reach on
the flat, shooters answer height). New server `ThreatField` (shots and charges swept per crowd
step, "root now vs shape lag ago"), `StrikeTally` (the one StrikeHit builder), keepAway brain,
plate in `CrowdService.Damage`; client `Controllers/ThreatFx/` (Pool, Shots, Areas, Tells, Cues,
PlateBar). stylua clean, selene unchanged, compile PASS (FeedbackController 159, CrowdRenderer 145),
luau-lsp 0 errors, `sim_range.py --check` PASS.

- **Recurring pattern (new): "in the air" judged by height above the crowd's floor.** The range
  has furniture to stand on (stairs 8/16/24, pillars, cover 3-9, a 10-high backstop). `ahead()`
  leads a target as falling whenever its root is over standY + 0.75, so a player standing on a
  block is aimed at 1.1 x the block's height too low; the line's one ray is horizontal at the
  marksman's chest, so the block's own face cuts the lane; every ground shape has a `height`
  rule. Result: any block top of 8+ studs is immune to all six attacks. Whenever a rule says
  "airborne", "floor" or "height", test it against a player standing ON geometry, not only
  jumping; the sim has no geometry and cannot see it.
- **Recurring pattern (confirmed): WYSIWYG against the server's actual test.** The charge is a
  capsule (distance to the swept body centre <= width/2); the lane tell is a square-ended
  rectangle `range` long, so the server reaches width/2 past the drawn far end.
- **A thing announced when the server notices it, not when it happened**, shows late on a
  client that draws on the server clock: a shot's wall end is found by one ray per crowd step, so
  the orb is drawn up to a step plus latency past the wall. A deterministic path can carry its
  own end time in the opening effect instead.
- Stop 2 notes are at the end of this file.
- What held: `CrowdRenderer.laneReach` mirrors `CrowdBrain.runway` exactly (config radius, layout
  size / 2, wire-snapped yaw); locked facings are snapped to the 1/256 yaw step and integrate
  rewrites a fight body's yaw before every snapshot, so a shove never reaches the wire; every hit
  goes through `RangeService.strike` -> `StrikeTally.Add`; blocked hits return before any side
  effect; shot ends are raised exactly once; `fight` never has more than 3 shots alive (cap 24).

**Stop 2 "the Colossus" (2026-10-12, uncommitted tree vs b4c3a01): SHIP, 0 Critical, 0 Major, Minors only.**
Wave 2's Major was fixed (shots led only for a target moving vertically, the line's ray cast in 3D,
lobs land on the surface under the target; a shot's path is cut once at fire). New: attack choice
(`CrowdBrain.choose`/`begin`), enrage latch and chain, `ring` (ThreatField), `summon` and the
top-up rule, `dismiss` on a boss's death, `shoulder()` for bodies of radius >= 3, barrage
(`HitShapes.Barrage`, one shared `volley` map), client `ThreatFx/Rings`, `UI/BossBar`. All gates
green (FeedbackController 159, CrowdRenderer 149), sim PASS.

- **Recurring pattern (new): a client-side drop keyed by something coarser than the server's.**
  The server takes back a dead boss's attacks by body id; the client drops circles and shots by
  KIND (`area`/`enemyShot` carry `enemyKind`, no id). Two bosses of one kind: the survivor's
  circles vanish and still land. Check before Stop 3 (the Warlord and his guard).
- **Recurring pattern (new): fixing z-fight by stacking lifts moves the tell off the floor.**
  Lob rims went from 0.21 to 0.71 studs and the slam's rim to 0.92; a raised mark reads about
  distance x h / (H - h) further from the camera (over a stud at the player's own feet). Parts
  only need distinct top faces (0.01 apart), not stacked thicknesses.
- A removal inside `CrowdService.Damage` (a boss's summons at its death) leaves later candidates
  of the same strike as ids that take 0: `StrikeTally` books them as hits of 0.
- What held: one-attack kinds go through `choose` to exactly the old result (cooldown nil = 0,
  `last` only blocks when another is ready); the enrage latch reads `CrowdCodec.SnapHp` on the
  server and the same byte on the client, and the client rescales a recover already running;
  `separate()` is unchanged without a large body; `dismiss` -> `CrowdBrain.Recall` + hooks.gone
  covers queued, pending and travelling attacks; BossBar clears the panel, crosshair and vitals
  bar at 375x667, 667x375 and 1920x1080 (portrait: under the panel's readouts).
