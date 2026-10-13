---
name: p5-missions-review
description: P5 "back into the missions" reviews (crowd combat in the Expeditions place) - wave 1 verdict, how to run the gates from tycoon-p5, what held, and the state-rule-as-event pattern
metadata:
  type: project
---

P5 = the range's combat (crowd, 13 weapon families, abilities, VitalsService body) replaces the C1
mission combat. Contract: `docs/INTERFACES.md` "# P5 contracts" (~line 8727). Worktree
`C:\Users\benja\Desktop\tycoon-p5`, branch `p5-missions`. See [[p4-enemy-roles-review]].

**Wave 1 "crowd in a mission" (2026-10-12, uncommitted tree vs 0866571): SHIP WITH FIXES, 0 Critical, 1 Major.**
RangeService split into place-agnostic `WeaponService` (+ bench-only RangeService), `RunFx`
(CombatService.PushFx moved), shared `CombatMode` (range only in Studio + DebugProving +
`debug.provingBoots == "range"`), WaveService rewritten for crowd bursts, VitalsService
`SetMission` (mayJudge/onDown/maxHpOf/damageScale/regenShare), CrowdService `SetScales`/
`hpMult`/`scale`/`damageBy`/`KillAll`/[Perf], `Armory.DamageScale`. Every gate green, findings
from reading.

**Why:** waves 2-4 build on these seams (revive replaces the boundary stand-up; all eras get
crowd blocks; EnemyService/CombatService deleted in wave 3).

**How to apply:**
- Gates that run from the worktree: `py tools/crowd_harness/run_harness.py <worktree> C:\Users\benja\Desktop\tycoon\tools\bin\luau.exe`
  (FIRST arg is the repo root, second luau.exe; the worktree has no luau.exe), `mutate.py` same
  args (copies into `mutant/` and cleans it; 217 mutations, ~3 min), `sim_range.py --check`
  ~5 min (run in background), `sim_combat.py --check` ~30 s.
- The economy-designer edited `1_Village.json` mid-review (burst 12 -> 10): re-stat config mtimes
  at the end and re-run the sims on the final values.
- **Recurring pattern (new): a rule stated over STATE implemented as an EVENT.** Ruling 18 "when
  no fighting human is left standing, end the run" runs only from VitalsService's onDown. A
  partner who leaves, or dies and respawns as `waiting`, after the other went down leaves a
  downed sole fighter: no new down, `humanCounts` sees Health 1 as alive, the crowd can target
  nobody, the waiting player cannot act, the run hangs until `runCapSeconds` (1200). Whenever a
  rule is "when nobody is X", check every transition into that state (leave, death, waiting),
  not just the one event that usually causes it.
- What held: one strike choke point (`strike()` -> `CrowdService.Damage(..., tally.scale)`), every
  `StrikeTally.New` carries a scale (melee, ranged, projectiles + split children via
  `projectile.tierScale`, slam = melee slot, abilities with `abilityMult`); heavy/plate/armour/
  interrupt read the unscaled amount; `damageBy` capped at HP left; `die()` shared by kills and
  KillAll; Clear/dismiss call no kill callback; `judged()` in decide, judgeTravelling,
  onCrowdStep and canTarget; MaxHealth writers are VitalsService + bot-only applyMaxHp; act gate
  on attack/draw/dash/slam/cast; RequestReady/RequestLeave inert in a proving mission; debug
  levers IsStudio + range-inert; no yields in WaveService tick or the onDown->EndRun path;
  CombatFxController kinds disjoint from the range kinds; phone layout (Ready/Return bottom-left
  vs vitals bar beside the thumb cluster) clears at 375x667 and 667x375.
- `CombatService` is now required by nobody (fine); EnemyService setters used by ArenaService are
  plain assignments or lazy (`ensureCollisionGroups`), safe without Init.
- Carried for later waves: the pellet seed is broadcast (`seq = seed` in shot fx) and
  invertible to the salt, so a client could pick seqs with tight patterns (P1 note, now live
  once the publish freeze lifts); `WeaponService.SetArena` state is write-only.
