# L1b Wave 4 — fix-diff review (git diff 2ec9da9 e428e85; saved by the lead)

Critical 0, Major 1, Minor 2. Gates on a snapshot: harness PASS (2,337), mirror_mutants 90/90,
mutate texts 724 all present once, check_levels PASS, check_stage_mirror PASS, sim_combat PASS,
check_compile PASS, luau-lsp 0 errors, stylua/selene clean.

**Major — a hopping player at the foot of the climb holds the rushers at the lip for good.**
`CampBrain.luau:426` (Melee) reads the live root (`Seen.root`, CrowdService.luau:629/632) but
`CrowdBrain.reaches` (:506) reads the surface last stood on (`restY − lift`). At root −5 an 18-stud jump
passes `meleeBelow` for about 4 crowd steps per hop: `anyMelee` fires, `standDown` never sets, `anyReach`
holds the leash; `reaches` refuses every blow. Probe: still player home at step 112; hopping every 20
steps never home in 450 steps, 0 windups, 4 of 4 at the lip. Fix: Melee judges height on the same rest
sample (`Seen.rest` from the track's `restY`); mirror in `sim_range cb_melee`; a harness case with a
hopping hitter and a mutation putting the live root back.

**Minor 1 — R13 ignores splash and burst.** `InputController.luau:1148`: a shot is held for a refused
body on the pierce line but not within Launcher A's `splashRadius` 10 or Longbow A's full-draw
`blastRadius` 5 at the arrow's stop (WeaponService.luau:1369, :1507). Fix: also hold when a refused body
lies within the variant's splash/burst radius (+ its radius + lag pad) of the predicted stop point.

**Minor 2 — per-frame allocation.** `InputController.luau:1114`: `enemyInSights` builds a new
`takenEntries` table every call (every frame on touch). Reuse one kept in an existing state table.

Verified, holds: R1 `goalGap`, R2 (no group unable to rest), R4 latch, R5/R6/R14/R15 (no-ops off a
region; bosses not regressed), R7 `Stirred`, R10 `threatGroups`, R12 indexing, `meleeBelow` accepted by
`CampBrain.Problems`, no new yields in Heartbeat paths.
