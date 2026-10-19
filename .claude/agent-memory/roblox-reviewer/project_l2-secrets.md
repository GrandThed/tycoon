---
name: l2-secrets-review
description: L2 W1 review (bought Double Jump, lookout chest, v7) - server slice 2026-10-17 0C/0M/4m (v7 forward-compat recipe, trigger-from-centre vs a big solid, unharnessed verdict-acting lines); client slice 0C/0M/7m (HUD-row overlap across ScreenGuis, proving hides Return, lost walk-off forgiveness, unmirrored client copy); fix diff 0C/1M/3m (AbsolutePosition origin trap undoes c1; shared call with copied args); L2 W2 slices 2026-10-18 (server, client, data-tools: stray_reach lacks ability travel, roof reachable by a mid-air Leap Smash); W2 fix diffs (origin chord vs generated fence; lag lead pointed by client velocity passes wall ends)
metadata:
  type: project
---

L2 W1 lives on branch `l2-secrets` in worktree `tycoon-p5`. It covers:
- the bought double jump, keyed on the Player attribute `Ability_doubleJump`;
- the Abilities panel (K, or a HUD button);
- SecretFx chests;
- the map secrets row;
- the leap fixes F1 and F2 (`WallClip.CasterFloor` and `LeapApex`).

Brief: `docs/prompts/l2-w1-review.md`. Findings go to `docs/prompts/l2-w1-review/<slice>.md`.

**Several slice reviewers share this file. Re-read it and Edit only your own section. Never Write it
whole.** On 2026-10-17 the client reviewer overwrote the server section with Write. The section below was
rebuilt from `server.md` and the index line.

**Why:** later L2 waves add Glide, the Jetpack, more HUD buttons and more chests. These patterns recur.

**How to apply:** for any new HUD button, element or movement rule, run the probes below before trusting the
engineer's "layouts checked mentally".

## Server slice (rebuilt; 2026-10-17, e39215b): 0 Critical, 0 Major, 4 Minor

**v7 forward-compat recipe (reusable for any schema bump):**
- ProfileStore 1.0.3 `ReconcileTable` only fills nil keys with deep copies and never deletes.
- `DataService.runMigrations` has an ahead guard (`version > SCHEMA_VERSION` warns and leaves the profile
  untouched), present since d166a9a (`git log -S`).
- So a hub publish adds empty maps, and a frozen older place loads them, warns, plays and saves them back. No
  loss either way.

**Minors (patterns):**
- **Trigger measured from a chest's centre against a big collidable chest.** The cache is 12×12×10 with reach 5
  and above 9, so no root ever triggers it. The gate (L2-18a) ran only for sold keys.
- **A duplicated constant** (`MAX_FAMILY_LENGTH` 24 in both StageFlow and CombatRemotes).
- **The service lines that act on a tested verdict are unharnessed** (`UnlockService.OnBuyAbility` debit/own,
  `OpenSecret`'s write). Proposed fix: a pure `Unlocks.Apply`.
- **Two rules for a repeated config id:** Init skips a malformed entry, while `Find` returns the first entry.

## Client slice (2026-10-17, 6feb088): 0 Critical, 0 Major, 7 Minor

**Patterns:**
- **Widening a HUD row: check it against every bottom element in EVERY ScreenGui, not only its own.**
  - The mission HUD (ExpeditionHUD) sits under the inset with DisplayOrder 1.
  - The health bar sits bottom centre in the inset-free `rangeGui`, shown in the lobby.
  - MovementController's Dash button lives in `RangeMovement`, DisplayOrder 0, always shown on touch.
  - At 667x375 the 280-px row's Return covered the HP bar's left 22 px. In portrait it covered the Dash
    button's left 48 px, so a dash tap fires `RequestLeave` with no confirm.
  - Probe numbers:
    - scale = clamp(min(w/375, (h − inset)/667), MIN_SCALE 0.9167, 1.8);
    - row bottom = h − 12·scale;
    - jump button (small, ≤ 500 axis) 70 px at (w − 95, h − 90);
    - Dash 56 px, its centre 8.4 + 28 left of the jump button;
    - the vitals bar is 200·scale wide, its bottom h − 10·scale.
- **`proving.rbxl` hides Return** (`runButtons = not proving`), so Ben's emulator look cannot show any overlap
  that involves Return. Say so whenever a layout claim depends on it.
- **Removing a forgiving mechanic removes its side effect.** The always-on air jump was the accidental coyote
  time.
  - `airJumpDelay` 0.12 already dropped presses under 0.12 s.
  - Without the air jump, a late press at Forest Road's first gap (Road1 → Road2, void below) is lost, and the
    once-per-session "buy Double Jump" hint fires there, on the main path.
- **A client copy of a pure server rule is ungated** even when every helper inside it is tested
  (groundPoint against GroundPoint step 4). Ask for one pure function both sides call.
- **Enemy launches are a vertical "means".** `MovementController.ApplyKnock` sets
  `vel.Y = max(vel.Y, jumpSpeed(3))`, so two launches at an apex reach 27, over the ledge's 26. check_levels
  models jumps, dash and abilities only.

**Verified, safe to reuse:**
- `onJumpRequest` is the only air-jump path. No other client file writes Jump, JumpHeight or the Jumping state.
- `Workspace.Level` is one folder that lives all session. `Secret_*` Parts are its direct children.
- RunFx batches arrive on `CombatFx`. `CombatFxController.applyFx` ignores unknown kinds.

## Data-tools slice (2026-10-17, 6feb088): 0 Critical, 0 Major, 4 Minor

Findings: `docs/prompts/l2-w1-review/data-tools.md`.

**Patterns:**
- **Players collide with players in the dungeon place.** `BarrierGroups` copies Default/Default, which is
  true. So any "needs X" ledge is reachable by standing on a partner's head: feet + 5 to 6, then one jump.
  The lookout falls to it by check_levels' own rule (34 − 13 − 3 = 18). Rewards stay safe (the key is read
  from the profile), but "out of reach by every means" and the "owners only" sniper labels are false in a
  party.
- **Enemy launches cannot lift a body to a ledge.** This corrects the client section above.
  - Every launching shape (arc 6, lob 4, lane 5) is a ground shape with a height band, so a body at a jump's
    apex is never hit by one.
  - `knockIframes` 0.4 outlasts the 0.175 s peak of a 3-stud launch, so launches cannot stack.
  - The best case is 21 + 3 step = 24.
- **A gate that counts inside a guarded function can be vacuous.** The sim's `airAsked` is incremented only
  where the planner's `can_jump` already forbids it. The mutation `can_jump = True` still gives 0 and the
  same 4.23 min.
- **Solo lookout margin:** camp A's NW fence corner (top 12, 6–7 studs from the ledge) is 1 stud short with
  `STEP_UP` 3.

**Recipes:**
- `sim_range.py` must run WITHOUT `-I`, because it imports `sim_combat` from its own folder:
  `py -3.12 tools/sim_range.py --check --levels-only --level forest` takes about 3 minutes.
- `check_stage_mirror.py` in a snapshot needs `--luau <main>\tools\bin\luau.exe`.
- To prove a refusal-alike set is not vacuous, early-return the rule on BOTH sides (StageFlow plus the py
  mirror). Every case must flip to "accepted on both sides".
- To count jumps in level runs, monkeypatch `S.ThreatRun.take_off` from a probe script, then run
  `S.LevelRun(view, hp, ctx, level, layout, "normal", S.THREAT_POLICIES["human"], seed).run()`.
  Each run takes about 3 s.
- The session scratchpad is shared with the parallel slice reviewers: put snapshots in a subfolder with a
  unique name.

## Fix-diff review (2026-10-17, a21f153..d6b3777): 0 Critical, 1 Major, 3 Minor

Findings: `docs/prompts/l2-w1-review/fix-diff.md`.

**Patterns:**
- **The `screenGui.AbsolutePosition` origin trap.**
  - `GuiObject.AbsolutePosition` is measured from below the top bar, so a default ScreenGui reads (0, 0). An
    IgnoreGuiInset one reads (0, −inset).
  - The c1 rows converted viewport-px obstacles (the vitals bar, the touch cluster) by subtracting
    AbsolutePosition. Two lines later the same function used `viewport − inset` for the crosshair.
  - With an origin of 0, the landscape HP-bar overlap comes back unchanged. The agent's table only
    matches an origin of 58.
  - For any viewport↔HUD conversion, demand ONE convention (`GetGuiInset()`).
- **Port the layout to prove it.** A Python port of a pure row packer plus the real cluster formulas
  (MovementController JumpButtonRect/SatelliteRect/ClusterRect, VitalsHud.BarPlace) reproduced the
  engineer's table to the tenth. Flipping one assumption then showed the failure. Probe: scratch
  `fixdiff_probe/rows.py`.
- **"One shared function" still leaves the call-site arguments as copies.** A source check that counts
  `GroundFloor(` calls passed with the client arg changed to `GetAttribute(...) ~= false` and the server's
  movement table swapped. Mutate the ARGUMENTS of a shared call, not only the call's name.
- **A walk-off detector keyed on take-off speed is passed by enemy launches.** A 3-stud launch is
  34.3 studs/s, under half of an 18-stud jump's 84.
- **A fixed-height `TextWrapped` label hides a second line from any height model.** The lookout card's
  family note (57 characters) always wraps.

**Verified, safe to reuse:**
- WeaponService.worldParams excludes every Player character, so overlapping bodies never read each other
  as a floor.
- The hop policy is in no level row that the L2-20 airAsked gate sums.
- c3's grace apex is bounded by a surface the Humanoid stood on: it needs FloorMaterial ≠ Air, then Air.

## W2 server slice (2026-10-18, 0f78d30 on `l2-w2`): 0 Critical, 0 Major, 3 Minor

Findings: `docs/prompts/l2-w2-review/server.md`.

**Patterns:**
- **A world-reaction hook keyed on strike shape.** `WeaponService.finish` hands every strike to listeners. `LevelService.React` burns only when the family's element matches and the shape is a segment. Ability capsules (`WeaponService.Strike`) have NO `worldReach` cut, unlike ranged capsules. So "abilities never burn" holds only while every ability of an element family stays a cone. Ask for an explicit refusal of abilities.
- **The pure parts are mutated; the service lines that apply them are not** (again). The element lookup, the `react ~= element` test and Main's wiring line are under no tool. Making `element` a constant lets Longbow rays burn, and every gate stays green. Grep `tools/` for the wiring name to prove a line is ungated.
- **Validate vs runtime on one entry**: a shortcut size ≤ 0 passes Validate, and the runtime skips it silently.

**Verified, safe to reuse:**
- `WeaponService.OnAttack` refuses a family the slot does not hold. `RequestSetFamily` (owned-only, `MayLeave` gate) is the only way to change a family in a mission.
- `WaveService.tick` runs every Heartbeat, so a 10-deep trigger box is not skipped by a dash.
- `LevelGeometry.Pieces(open)` measures a clone, so `BlockBoxes` deepening never reads a dropped block.
- `startLevel` checks `notLeader` before reading the leader's save. A level is built once per run.

## L2 W2 client slice (2026-10-18, 0f78d30): 0 Critical, 2 Major, 8 Minor

W2 is on branch `l2-w2` in worktree `tycoon-p5`. Findings: `docs/prompts/l2-w2-review/client.md`.

**Patterns:**
- **A world interaction keyed to a weapon needs a touch route.** Touch is `autoFire`, so a phone fires only when
  `targetOnAuto` sees a crowd body. A bramble (a Part) is never one, so the whole fire chain was out of reach on
  phones. For any later react/ice/lever object, ask: "how does auto-fire take this?"
- **A local display ray cast from `GetAimRay()` starts at the CAMERA.** That is about `defaultZoom` 11 behind the
  head. The server measures from the shot origin at head depth (`shotRay`). FlameFx's local flame came out about 8 of
  20 studs. Grep any new local "cut at the wall" draw for `GetAimRay` with no head-depth offset.
- **A spherecast starting inside a part ignores that part.** A ray-based pull-back of 0.7 meets an oblique surface
  only 0.7·sin θ away. Pull back with a Spherecast from a known-open point instead.
- **`Theme.reducedMotion` = every touch device** (still true, Theme :1486). New effects gated on it vanish on phones.

**Verified, safe to reuse:**
- Armory sheet at MIN_SCALE: fixed part 74 design px on touch (94 with the key line), plus the page. At 667×375,
  640×360 and 375×667 a 190 page fits without scrolling.
- Panel pad bindings at High+1 beat the run's High bindings (R1/L1/Y, dash B/X). ButtonX still dashes under an open
  panel.
- In a mission, the only `SetTuneStateHandler` is the Armory's.

## L2 W2 data-tools slice (2026-10-18, 0f78d30): 0 Critical, 1 Major, 4 Minor

Findings: `docs/prompts/l2-w2-review/data-tools.md`.

**Patterns:**
- **`stray_reach` has no horizontal ability travel.** `unclimbable`, the ridge rule, the bend rule (L2-47) and the
  walled gate all lean on it.
  - It covers jump, double jump and dash: 46.6 studs, or 49.3 with the walk-off grace.
  - Leap Smash, cast mid-air at the double-jump apex, adds castRange 32. Over a void the caster's floor is
    feet − Rise, so the target can sit exactly Rise (30) above it.
  - An airborne Impale Dash holds altitude for 30 more studs.
  - Result: the cave roof (64) is reachable from the lookout ledge (34) with a Greataxe and Double Jump, an
    unrated perch over Main Camp. The open BC bend (54 of void) can be cut.
  - `lift_routes` (L2-18c) models players WITHOUT the double jump and runs only for sold-key secrets. Ask that
    every "nobody stands there" claim run it with the double jump's Rise.
- **Probe recipe:** call `cl.lift_routes(solids, [(x0, x1, z0, z1, top, name)], set(), tall, dj, ctx["lifts"])`.
  - Set `dj = move` with `jumpHeight` 30.
  - Raise `walkSpeed` to about 28.2 to get the real 15.6-stud reach of a jump plus double jump.
  - The routes it finds hug the corners of the routing walls. Hand-trace a route clear of them before reporting.
- **A family that is not ownable yet is still in scope.** The contract made `fielded_lifts` = every family,
  because the lever and L3 can field any. Rate the finding on that and say it is unreachable from today's saves.
- **R8's plan-view sight rule trusts walls.** Two ways past them:
  - `aimAllowed` is distance-only (originPad 6), so any wall thinner than 6 lets a forged origin through.
  - Wall-ignoring cones (Slug Burst, Dragon's Breath) pass the wall outright. The sniper course rates the bow
    only.

**Verified, safe to reuse:**
- `check_cave`'s Enclosure (a 3D flood fill on the blocks' own coordinates) is sound for "sealed at any width".
  It leaves fences out, which is conservative.
- Dash, leap and lunge are LinearVelocity movers, not CFrame writes, so a 2-stud part holds.
- Ranged capsules never crit: `resolveRanged` passes `false`.
- Run `sim_range --check` on 64-bit 3.12.10, without `-I`. It takes about 12 min.

## L2 W2 fix-diff review (2026-10-18, e14fb78..78463a0): 0 Critical, 0 Major, 3 Minor, 1 Suggestion

Findings: `docs/prompts/l2-w2-review/fix-diff.md`.

**Patterns:**
- **"Thinner than the thinnest wall" must count the GENERATED pieces.** `originWallChord` 1.5 was argued
  against the layout blocks (2 studs). But `levels.fenceThickness` is 1, and camp C's 64-high wall is a fence.
  For any tolerance of this kind, grep the config for `*Thickness` and ask for a gate that compares the two.
- **Head-to-origin wall rays are judged from the LAGGING server head.** Refusals cluster on corners and edges
  during fast moves (dash, leap, a fall off a ledge). Convex fight floors are immune when the head's centre
  (root + 1.5) clears every cover or fence top: 3.5 and 4 here.
- **Bloom applies to continuous families too.** `bloomMult` 0 stops only the per-shot bloom. Moving bloom
  (up to 7°) still bends the sent direction, so anything drawn or tested along the un-spread `look` (the local
  flame, the phone's burn test) is identical to the server only while standing still.
- The W1 pattern held again: the source check matched the call `OriginClear(` and left its tolerance argument
  free.

**Verified, safe to reuse:**
- The honest origin is `shoulderPoint + look·dot(head − shoulderPoint, look)`. The boom term cancels. The
  shoulder point is at least 0.5 off every solid, so the origin is never inside one.
- RaycastParams default to the Default collision group, which `ArenaBarrier` ignores. Server rays never see
  the invisible walls.
- `check_levels_mutants.py --only <text>` runs a subset (about 20 s per case).

## L2 W2 second fix-diff review (2026-10-18, d98b85d..aca232d in `tycoon-p5b`): 0 Critical, 0 Major, 1 Minor, 2 Suggestions

Findings: `docs/prompts/l2-w2-review/fix2-diff.md`.

**Patterns:**
- **A lag lead capped in LENGTH by a server measure still takes its DIRECTION from the client.**
  - `LeadHead(head, root.AssemblyLinearVelocity, ringSpeed, lag)` is that case. The ring speed is 3D, so a
    hop (about 74) or a slam (140) at lag 0.3 buys 22 to 42 studs in any claimed direction.
  - A cut-back at the first wall on the lead's line does not stop the lead from passing a wall's END. The rule
    becomes two-segment visibility.
  - Ask for the lead along the ring's own displacement.
- **A "carried point" rule needs an honest case that goes THROUGH the cut branch.** `leadTests`' honest lead
  never hit a wall, so `then head` and `LEAD_STANDOFF = 50` survived the full harness. The gatehouse L (a lead
  into the outer wall, an origin round the inner corner) depends on exactly that branch.
- **A per-camp thickness: check the joins.** Walls built flush to the old fence face must move with it, or
  coplanar same-facing faces z-fight. Here they were moved. Also check that `chaseMargin` is at most the fence,
  so a root outside the fence is out of play.
- **A fence stands outside the floor and touches it along one edge only.** Below the fence there is a slit, so a
  line from under it can clip that edge with 0 chord. It is harmless only while nothing below the floor's top
  can be stood on near the camp (true for C).

**Recipes:**
- Add review-only mutants to a SECOND `git archive` copy, appending a dict after the last `MUTATIONS.update`.
  Run `mutate.py <copy> <luau> "probe:"`. It needs its own copy, because `mutant/` is per checkout.
- Port WorldReact's AimClear to Python with the harness's box caster (`firstHit` slab test, skipping a box
  that holds `from`). It answers forged and honest cases on real layout boxes in seconds.

See [[l1c-chief-clearing-review]] and [[l1b-living-road-review]].
