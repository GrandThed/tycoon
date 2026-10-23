# L4 W2 fix round: the fix diff (afdce67..46fd98f), review

Reviewer: roblox-reviewer, 2026-10-22. Read only. Every probe ran on a `git archive 46fd98f` copy in the reviewer's
scratch folder (its `assets` a junction to the main checkout's), never in the worktree. Python is named per number:
`py -3.12` for raiderpose, check_levels*, check_stage_mirror and the sims; the harness by its shebang (3.12).

**Count: 0 Critical, 0 Major, 3 Minor, 4 Suggestions.** K1-K10 are fixed as ruled. The lead's accepted decisions are
taken as given: the 3.44 floor, sweep 12.7 / reach 10.5, the lobby prewarm from every built level, camp C's barrier tops
in the failed view, the summary camera on the server's word, and the new plan hash.

## Minor

**m1. K3's client half and three LevelScenery predicates sit under no gate: 11 of 11 probes pass `HARNESS: PASS (4,656)`.**
This is the "pins hold the calls, not the deciding line" family again, one level down. The pins hold every call site
(`showChild`, `ScenePlan.Show`, the K3 server lines). They do not hold the client lines that decide.

Each mutant below was applied alone to the copy's source, and the harness stayed green:

| File | Mutant | What breaks |
|---|---|---|
| `CrowdRenderer.luau:2672` | `local built = Figures.Build()` → `local built = 0` | No pool ever fills. Every raider stays a placeholder for the whole session. |
| `Figures.luau:733` | `Take` builds again: `... else build(look)` | The spawn handler builds a hundred models in one frame (slice 3 m1 returns). |
| `Figures.luau:800` | `local share = 1` | No split over the cap. The kinds walked first take the whole pool. |
| `Figures.luau:836` | `budget = math.huge` | The whole envelope (127 models) is built in one frame. |
| `CrowdRenderer.luau:1013` | `entity.wants = nil` | A body that met an empty pool stays a placeholder for life. |
| `CrowdRenderer.luau:2699` | `wear(entity, wanted)` → `Figures.Wait(wanted)` | Same as the row above. |
| `CombatUIController.luau:1716` | `local kinds = nil` | The lobby fill never starts. |
| `LevelScenery.luau:249` | `isSkinned` → `return false` | A failed client leaves every hidden rock and path invisible but solid. This undoes slice 2 m2. |
| `LevelScenery.luau:253` | `isWall` → `return false` | A failed client draws no tree-line wall: invisible walls fence the player again. |
| `LevelScenery.luau:649` | `teardown` drops `state.failed = false` | One failure greys every later dressed level for the session. |
| `LevelScenery.luau:476-479` | `bodyInLobby` → `return false` | Mood B in the lobby camp (K8 undone). |

**Fix:** pin each line whole, with its indentation, and add a mutate entry for each. The better fix: move K3's two
rules into a pure module the harness loads, as ScenePlan did for K7:
- the goals: `Prewarm`'s floor, remainders and tie order;
- what `Build` makes next from waiting, spares, goals and the budget.

**m2. K2's 15° sector gate passes a 10° hole at the Chief's far left: no part of the hammer ever enters −65..−75°, which
the server's wedge hits.**
- **Where:** `tools/testfit/raiderpose.py:956, 1018, 1028-1030` (`SECTOR_DEGREES` 15) and the arc keys in `RaiderModels.json`.
- **What the probe shows:** the same sampling as `impact_reach` (120 steps, enraged or not), binned at 5° (scratch
  `sector5.py`). From his left: **0.0 0.0** 12.4 12.5 12.8 … 13.0. At or past range − 0.5 (12.2), the hammer's span
  ends at −60.6°. The 15° slot −75..−60 is "swept" at 12.4 only by vertices between −60.6° and −60°.
- **Against the ground tell:** traced over the strike, the hammer lags the tell's leading edge by 7-14° from u 0.40 to
  0.55. It parks at −60° while the tell runs on to −75°.
- **Failure:** a player at the Chief's left, about 70° off his facing and 10 studs out, is hit on the impact. No hammer
  is drawn anywhere near him. The red wedge does cover him, so this is a weaker version of the review's m1 (30° then,
  10° now).
- **Fix:**
  - Make the gate test the swept span's ends: the angles reached at range − 0.5 must come within about 5° of each
    edge. Or bin at 5°.
  - Then either turn the `follow` yaw further left (ui-b's table says up to 12.46 is drawable in −75..−60), or narrow
    `arcDegrees` to about 130 and have D1 re-measure the bands.

**m3. The plan hash's float32 guard (`tools/levels/forest.py:3303-3321`, `kit_geometry`) does not cover the failure it was
written for.**
- **How the guard works:** it refuses a corner within 16 float64 ulps of a float32 rounding edge, and the ulp is taken
  relative to the corner's own value.
- **Why that misses:**
  - The hash broke because a value that is about 1e-16 on one Python is exactly 0 on the other.
  - Float32 stores tiny values exactly, and **721 of the 45,567 shipped corners are tiny and non-zero**. For example,
    Banner has 6.123233995736766e-18, from cos(π/2) × 0.1. The count is the same on 3.14-32 and 3.12, scratch
    `tiny.py`.
  - So a corner that is 6e-18 on one Python and 0.0 on the other packs to different bytes, and the guard never trips.
  - −0.0 and 0.0 also pack differently, and the guard does not see that either.
- **Today:** the hash is the same on both Pythons (`forest.py check` PASS on the copy under `py -3.14-32` and
  `py -3.12`). The comment's "so this stays true" does not hold.
- **Failure:** a later kit piece built by cancellation (a − b with a ≈ b) gives a hash that depends on the Python again.
  The other Python then reports the plan stale, and a rebuild there costs a re-bake, a re-upload and a paste.
- **Fix:** before packing, snap every |v| < 1e-6 to 0.0 and turn −0.0 into 0.0 (or round corners to a fixed grid). This
  gives a one-time new hash, written as D2 did. Nothing re-uploads.

## Suggestions

- **s1. A swap drops the camp's "!" mark.**
  - Where: `src/combat/client/Controllers/CampFx.luau:134`, which ends a mark when `GetHead(id)` changes.
  - With K3, a waiting placeholder swaps its anchor for the model's `Head`, so a wake mark shown on that body ends at
    once.
  - It is rare once the lobby has filled the pools. Re-hang the mark on the new head instead of giving it back.
- **s2. The crosshair stays up in a dressed summary.**
  - With K9 the shoulder camera stays active through a dressed level's 10 s summary and `ended`. `FeedbackController`
    shows the crosshair whenever `CameraController.IsActive()` (`marker.Update`, :3255), so it stays drawn at screen
    centre, under the summary card (`ExpeditionHUD`, DisplayOrder 1).
  - Attacks are refused by phase (`InputController:204`), so this is cosmetic. Gate the crosshair on the phase too.
- **s3. `docs/MISSIONS_DESIGN.md`'s new correction paragraph quotes this reviewer's pre-K2 numbers.**
  - It names "x0.987 (Hard T1/T1, Road3)" as the tightest spot.
  - After the sweep change, the gate's tightest Hard T1/T1 spot is Road2 at x0.982 (D1's run; `sim_range.py`'s
    `R8_FIGHT` comment).
  - The other three figures also moved by 0.001-0.002. Copy D1's four rows.
- **s4. Check in Studio that `MeshPart.MeshId` reads a MeshContent-only template.**
  - `templatesOf` now judges templates by `MeshPart.MeshId`. The level templates carry only `<Content
    name="MeshContent">` (for example, `templates/_levels/ForestRoad/BridgeDeck.rbxmx`).
  - If the engine does not mirror the URI into MeshId, every build is grey with "has no template with a mesh". That is
    safe, but it hides the whole wave.
  - No offline proof exists: the hub's `PlotVisualsController` also reads MeshId, but it treats "" as fetched, so it
    proves nothing. Keep luau-a's Studio step 1 as the first step of the playtest.

## Checked and clean

- **K1, the slide.**
  - `slide = max(thrust, 0) × 0.6` starts at 0 in the windup's snap (u ≈ 0.88) and rises continuously to 1.55 at the
    impact. It is continuous across the windup → attack switch (thrust 2.59 on both sides) and falls to 0 exactly at
    the strike's end. The recover is 0.
  - At 60 Hz the largest per-frame body step is about 0.36 studs (scratch `trace.py`).
  - Trailing foot: its target −slide plus the shift leaves it where it stood. Leading foot: step + slide = the full
    thrust. Anchor: unslid, unturned, as before (`root * frameOf(anchor)` equals the old `CFrame.new(0, anchorY, 0)`).
  - The only one-frame jumps are inherited: ruling 9's cancel to recover in the snap or the first half-strike, the stagger
    to "none", and a late sighting's shortened windup snap the model back up to 1.55. The placeholder snapped 2.59, so
    this is "as the placeholder did".
- **K1 gate is not vacuous.** With `slideShare` 0, `raiderpose.py --check` reads "lunge 2.43 … >= 3.44 FAIL", exit 1.
  Shipped: 3.86 ≥ 3.44 and ≤ 5.5; the in-head check passes at 0.758 against 0.75.
- **K2 ceiling.** The in-arc maximum is 13.03, under 12.7 + 0.5. Between the windup's end and the impact the hammer jumps
  1.76 studs (14.07 with the old keys). The red wedge's leading edge and the hammer sweep the same way, right to left.
- **K3, server.**
  - `kindsOf` counts tents and summons, so the envelope covers the Chief's call of 12.
  - The lobby envelope is 127 bodies, under `crowd.maxAlive` 160. `RunFloors.Attach` reports `cellsWent` per floor set
    even with no cells, so the lobby's first RunState carries `prewarm`.
  - `refreshLobbyKinds` never yields; its plan is under a pcall.
- **K3, client.**
  - `Take` never builds. `Build` runs at the top of `step` in the lobby too. Waiting bodies are built for first, then the
    goals, 4 a frame. The split uses floors, then the largest remainder, the larger count, then the name.
  - A swap re-runs `applyKind`: cues, plate bar, paint and dirty. `release` clears `wants`. `Destroy` clears the goals
    and the waiting counts.
- **K4 and K5.**
  - `check_raider_mirror.py --mutants`: CHECK PASS, 20 of 20 red, in 74 s. It runs the real `RaiderPose.luau`, and the
    new slide, anchor and Lean fields are compared.
  - The K5 checks: Figures' `lookOf` against the def; `raider_frames.py` against the entry, which is equivalent given its
    size checks.
- **K6.** The K6 mutant scales only `r8_rate`, the sniper's whole run. The reference's `pay_rate` is untouched, so the
  mutant is asymmetric and sized to the 1.8% margin. `r8_check` reads `runs[report["fight"]]`. The printed sword tables
  stay ungated.
- **K7, server.**
  - `Decide` pcalls `Accept`. A throw or refusal → `Lay(nil)`: the same pieces, `hidden = {}`, the base looks, no word.
    `Build` clears both attributes first and writes `DressHash` before `Dress`.
  - Nothing else in `dressOf` can throw: `require` of a JSON module, `FindFirstChild`, `BarrierGroups.Ensure` (which
    pcalls).
  - Accept's new prop and effect refusals match what `ScenePlan.Jobs` and `spawnProp` read.
  - ScenePlan's `isList` is "is a table", as the server's check is.
- **K7, client.**
  - One pcall covers the build thread; `start` has its own. `fail` always ends with `state.failed = true` and
    `applyView`, and `teardown` resets it on the next word.
  - "wait" and nil answers are never kept. `awaitLoaded` re-reads after `game.Loaded`.
  - Both attribute signals defer to one `evaluate`, so the hash-first order is never read half-way.
- **K8.**
  - `inLobby` follows `MoveMember`'s `Placed` and the camera's pick-up. The lobby box (z about −365..−315, plus 40) is
    over 100 studs from the forest (z −134..128).
  - `onPlaced` runs only on a placement, not every frame, with `syncMood` inside a pcall. `applyMood` is idempotent per
    level.
- **K9.**
  - `DEFAULT_CAMERA_PHASES` is only {summary, ended}, so the lobby camera is unchanged.
  - The cursor is free in summary and ended (`freeCursorPhases`). A dead rig still hands the camera back.
- **K10.** The kept entry's kind is re-read by `drawn_body` for `drawn`, so the reach is never counted twice.
  `check_levels.py` (copy, 52 s): CHECK PASS, eyes +1.73, cameras +2.84.
- **Seat mirror.** `check_stage_mirror.py --luau` (copy, 13 s): CHECK PASS, `HitShapes.SeatStep` compared against the
  real HitShapes.
- **s1, the sphere drop.** `math.max(height/2 − drop, radius)` leaves every standing kind unchanged: radius < height/2
  for all 11 kinds.
- **s2, the hammer grip.** `base.CFrame * CFrame.new(grip * scale)` follows the same convention as HeldWeapons'
  `C0 * CFrame.new(-point)`: the point is in the Base's frame. The Warhammer's grip is 0, so nothing moves today.
- **Gates on the copy.**
  - Harness: PASS, 4,656 checks.
  - `mutate.py` stale check: 2,068 entries, 0 stale.
  - `forest.py check`: PASS under both Pythons.
  - `raiderpose.py --check`: exit 0.
  - `check_compile`: PASS, 182 files; CrowdRenderer 165 of 180.
  - stylua and selene: clean on all 15 changed Luau files.
  - luau-lsp, combat sourcemap: 0 diagnostics.
  - `--!strict` everywhere, no `wait`, `spawn` or `delay`, and every file is LF.
