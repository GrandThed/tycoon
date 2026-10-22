# L4 W2 review, slice 3: the raiders and the pose

Diff `37ccfe4..afdce67`, slice files: `Raiders/RaiderPose.luau`, `Raiders/Figures.luau` (new), `CrowdRenderer.luau`,
`ThreatFx/Cues.luau`, `InputController.luau`, `CombatUIController.luau`, `src/client/UI/Theme.luau`,
`tools/testfit/raiderpose.py`, `tools/check_raider_mirror.py` (new). Reviewer: roblox-reviewer (Opus), 2026-10-22.
Read only; probes ran on scratch copies (`--source/--out` into the session scratchpad, `py -B`), nothing in the worktree
was written but this file.

**Count: 0 Critical, 1 Major, 3 Minor, 4 Suggestions.**

## Findings

### Major

**M1. The fodder's lunge is now drawn 2.8 studs short of where it hits, and no gate has a lower bound.**
`src/combat/client/Controllers/CrowdRenderer.luau:2387-2391`, `tools/testfit/raiderpose.py:953` (`impact_reach`).

- What is wrong:
  - A model body no longer takes the lunge's thrust as a slide. Only its leading foot steps (`stepShare` 0.4) and its
    arm takes the strike key.
  - `raiderpose.py --check` prints `fodder: weapon at impact PASS ... lunge 2.24 of 5`: at the blow the club reaches
    2.24 studs from the body's axis.
  - The server's lunge (`VitalsService.inPlan`, `shape == "lunge"`) is a capsule 3 wide whose round tip ends 5 studs
    from the body centre. It hits any player root inside it.
  - The placeholder slid `(range 5 - radius 1.3) x COMBAT_RANGE_TELL_LUNGE_SHARE 0.7` = 2.59 studs. Its torso front
    reached about 3.4 studs (2.59 + 1.3 x TORSO_DEPTH 1.3 / 2).
  - So the drawn reach drops by about a third (3.4 to 2.24). The gap to the hit's edge grows from 1.6 to 2.8 studs.
  - The W1 rig rule says "the arm's strike pose carries the reach". It carries 2.24 of 5.
  - The weapon rule added to `--check` (contract 3.4) is an upper bound only ("no farther than the attack + 0.5"), so it
    cannot see a blow drawn short.
- Failure scenario:
  - A player kites a fodder with the root 4.5 studs away. The visible body edge is about 3.5 studs away.
  - The fodder's windup starts (its `reach` is 4.5) and the lunge lands for 8 x damageScale.
  - On screen the club stops 2.24 out: about 1.3 studs of air between the club and the player. With the placeholder
    the gap was about 0.1 stud.
  - The fodder is the commonest body (about 30 of Normal's residents, plus every Chief summon). Its lunge has no ground
    tell (only an arc gets a wedge, `setThreat` `wantsTell`), so the drawn reach is the only spatial cue.
  - This is exactly the "dodging still feels the same?" question of contract 12.9.
- Suggested fix (a choice for the lead; any one of the first three, plus the gate):
  - (a) Keep part of the slide for model bodies: `offset = facing * math.max(thrust - jabShortfall, 0)`, with the
    shortfall read from config (the arm's reach at impact against the placeholder's front). Exempt the lunge's blow
    from the head rule, as the reactions are. The placeholder already moved its head that far.
  - (b) Re-key the fodder's strike, or lengthen the club, so the arm reaches at least about 3.4. This means a generator
    re-run and one paste.
  - (c) Shorten the lunge's `range` and `width` to what is drawn. That is D1's data and needs a re-measure.
  - Gate: give `impact_reach` a lower bound for shapes with no ground tell (`lunge`): drawn reach >= the placeholder's
    front (or `range` - a player's half width - slack). The gap then fails by name.

### Minor

**m1. The model prewarm cannot get ahead of the residents, so the first run builds about 95 models in one frame.**
`src/combat/client/Controllers/CombatUIController.luau:1713-1718`, `CrowdRenderer.luau:2854-2869`,
`Raiders/Figures.luau:706-735`.

- What is wrong:
  - `WaveService.startLevel` places every resident and `broadcast()`s the RunState that carries `prewarm`.
  - `CrowdService.flushLifecycle` announces all pending spawns in ONE `CrowdSpawn` batch at the crowd's next step, at
    most 67 ms later.
  - `Figures.Prewarm` builds `COMBAT_RAIDER_PREWARM_PER_FRAME` = 4 a frame, so 0 to about 16 figures exist when the
    batch lands.
  - `onSpawn` then runs `spawnEntity` -> `applyKind` -> `Figures.Take` -> `build` synchronously for every other
    resident: about 95 clones of 11-13 MeshParts (about 1,200 parts) in one remote handler, on the first run of a
    session. Pools persist, so later runs are fine.
- Second problem: when a plan's total exceeds the cap (`crowd.maxAlive` 160; likely on Hard and Brutal with the tents'
  stock and the Chief's summon), the cap is spent in alphabetical kind order. Slingers, last, are cut first.
- Failure scenario: departing Forest Road the first time on a phone shows a hitch of several hundred ms at the
  trailhead. That is contract risk 2, and the prewarm meant to soften it saves about 15%.
- Suggested fix, either of:
  - fill the model pools in the lobby (CrowdRenderer.Start, or when the map shows the level), at the 4-a-frame pace,
    from the level config's counts or a fixed share per RaiderModels kind;
  - or have `spawnEntity` dress the placeholder when its kind's pool is empty, and swap to the model (`dressFigure`
    already swaps live bodies) as Prewarm catches up.
- Also split the cap in proportion to the counts, not in name order.

**m2. Nothing pins the model's head point to the scored head.** `Raiders/Figures.luau:366-371` (lookOf),
`tools/assets/raider_frames.py:148-153`, `tools/testfit/raiderpose.py:1133-1138`.

- What is wrong:
  - The client's anchor (`Head`: GetHead, the plate bar, CampFx's "!") sits at `points.head.y - SeatDrop`, and the
    drawn head is placed about `points.head`.
  - The server's crit sphere is at `height - headRadius - SeatDrop`.
  - Every check compares `height`, `radius` and `headRadius` with the kind, but none compares `points.head` with
    `(0, height - headRadius, 0)`.
  - raiderpose's head rule measures the drawn head against `r.anchor`, which is built from `points.head` itself.
- Probe: a copy of the config with the fodder's `points.head`, `headMeshCentre` and head `pivot` at y 4.6 (the scored
  head is 4.3), written through `raider_frames.py --source/--out` in scratch.
  - `raiderpose.py --check --no-extent --models <copy>`: `fodder: head rule PASS ... worst 0.400`.
  - `raider_frames.py --check --require-harvest --source <copy> --out <copy>`: `CHECK: PASS`.
  - Figures would accept it too.
  - All seven shipped entries are exact today.
- Failure scenario: a builder re-models a head 0.3 higher (hat, crest) and re-runs the generator. Every gate stays
  green, and headshots aimed at the drawn head pass over the server's crit sphere by 0.3 studs (0.43 head radii).
- Suggested fix: assert `points.head == (0, height - headRadius, 0)` (and `headMeshCentre` within a small epsilon of
  it) in `raider_frames.check`. In `Figures.lookOf`, refuse it with one warning, so the body becomes a placeholder.

**m3. The client half of the pose and of the seated head is under no gate.** `Raiders/Figures.luau:752-755`
(`leanParts`), `:853` (the anchor), `:859-864` (the hammer), `CrowdRenderer.luau:3025` (ForEach's drop),
`InputController.luau:651, 663, 680, 760` (the three `- drop` lines and CrowdRay's `drop`).

- What is wrong:
  - `check_raider_mirror.py` runs only `RaiderPose.luau`, and no other tool reads Figures, CrowdRenderer or Cues: a grep
    of `tools/` for them finds only prose in `raider_frames.py` and `check_levels.py`.
  - `run_harness.py` and `mutate.py` name none of them.
  - mutate's 21 InputController entries predate the drop and touch none of its lines.
  - So the glue between RaiderPose and the parts is unguarded:
    - the lean split along facing and right;
    - the twist (`drawnYaw - entity.yaw`);
    - the anchor's height;
    - which threat and attack Pose is handed;
    - the cue's carrier;
    - ForEach's `HitShapes.SeatDrop(...)` argument, the client half of L4W2-11.
  - This is the pattern of the W1b review: the server half of a rule is pinned, the client half sits under nothing.
- Failure scenario: ForEach passes `0` for the drop, or `leanParts` swaps its two returns. Every gate stays green.
  - With the drop at 0, the phone's auto-fire and aim assist read a seated raider's head at standing height again.
  - With the returns swapped, every windup leans sideways and the marksman's `steady` aim tilts.
- Suggested fix:
  - Move `leanParts` and the anchor height into RaiderPose (pure), so the mirror covers them.
  - Add mutate entries (or text pins) for ForEach's drop argument and InputController's three `height - headRadius -
    drop` lines.

### Suggestions

**s1.** `InputController.luau:679` (and `:662`, `:759`): the assist's body sphere stays at `height / 2` for a seated
body. The
server's seated capsule is lowered by `drop`: for the fodder, CrowdRay's top becomes 2.05, so the body is the sphere at
its foot (0 to 2.6) and the head spans 1.85 to 3.25. The assist sphere spans 1.2 to 3.8 (+ lagPad).

- So auto-fire can trigger 0.55 studs over a seated raider's head (the server's pad forgives part of it) and never at
  its lower half.
- Lower the body sphere with the seat, or judge taken bodies with CrowdRay as refused ones are.

**s2.** `Raiders/Figures.luau:456-483` (`addHold`): the hold is placed by the template's `Base`, on the assumption that
Base is the grip.

- WeaponModels.json's `points.grip` is ignored.
- It holds for the Warhammer (`grip` [0, 0, 0]), but a future `hold` with a non-zero grip would sit off the hand.
- Offset by `WeaponLook.Point(def, "grip")`, or have `raider_frames.py` assert that the held model's grip is its origin.

**s3.** Duplicated constants: `Figures.SETTLE` = 0.002 is `CrowdRenderer.SETTLE_EPSILON`, and `HELD_STAGE "Stage0"` is
`HeldWeapons.SHOWN_STAGE`. Pass them in (Configure already takes CrowdRenderer's colours) or move them to Theme.

**s4.** Out of slice, cosmetic: `FeedbackController.drawPellets` (`:1277-1284`) still stops tracers at the standing
head on seated bodies (its ForEach callback ignores the new `drop`).

## Checked and clean

- RaiderPose is pure (no `game`, no require, no Roblox type).
- The mirror is live: `check_raider_mirror.py --mutants` gave CHECK PASS on 16,806 cases, MUTANTS 14 of 14 red. The 14
  are the contract's four (lean sign, head clamp, snap, leg shade) plus whirl, steady, throw path, lock aim, short-way
  blend, walk ease, near radius, seat drop, the leading step and the skin's half tint.
  - The worst difference is 3.1e-8: an `asin` near ±1 in `placeLeg` at yaw -2.3. The reports said 7.1e-15. It is
    within the 1e-6 tolerance.
- `raiderpose.py --check`: head rule PASS for all seven (worst 0.400 hr); in-head PASS; `posedReach` matches; weapon at
  impact PASS (the Chief's sweep 17.10 of 17 + 0.5). The stand-in Chief is gone, and `restDrop` /
  `riseBlendSeconds` are read from ProvingGrounds.
- The threatPose port is equivalent to the old code branch by branch:
  - windup: lunge, ring, summon, the rest;
  - attack: lunge, lane, ring, the rest;
  - recover: held, settle, wake, stride, unwind;
  - the charge only in the windup;
  - the tint stepped twice, which is idempotent;
  - `drawTell` only for arcs, as before.
- The shared `threatIn` / `threatOut` scratch: Figures.Pose reads it only after threatPose ran for the same body in the
  same frame. The only branch that leaves a threat set calls it, and `stepRush` never sets one. Pose, Queue and
  QueueRest each rewrite every scratch pose field they use.
- The seat:
  - The client steps it with `HitShapes.SeatStep` on `crowd.riseBlendSeconds`.
  - The first sample seeds 1 at rest (`CrowdRenderer:1682`), as the server seeds (`CrowdService:2335`).
  - The placeholder sinks by `HitShapes.SeatDrop`, which is equivalent to the old smoothstep.
  - The model's anchor and drawn head drop by the same amount, and ForEach hands it on.
  - InputController lowers the head sphere in the cone, the refused spheres and the melee test.
- TextureID is cleared once per clone on every non-gear MeshPart, plate and glow included. Gear is never painted.
  - Paint writes only the roles that changed. Flash, heat, the dull spent body, enraged and the Chief's eyes all follow
    RaiderPose.Paint.
  - The glow role is repainted on `setVisorHot`.
- The plate:
  - hidden at build and on Give, shown while plated;
  - a white Neon glint for 0.1 s;
  - the burst grows about each part's centre with Transparency = share, then hides for good;
  - it composes with the body's fade.
- Cues:
  - A model kind gets only its lit piece, riding the arm or torso at its config point (`QueueRig` only).
  - The Chief's core goes 1.6 -> 2.6; enraged it is 2.16, with the charged size max(2.6, 2.16).
  - Fodder, brute and elite get no set.
  - A re-dress detaches and re-attaches the set.
- Pools are kept per kind:
  - Give resets the walk, the arm, the paint cache, the plate and the fade.
  - `release` gives the figure back and restores `model` and `anchor`.
  - Destroy destroys every figure.
  - No new connections.
- X:
  - `ToggleModels` re-dresses every alive body through `applyKind` (cues, bar and paint taken again).
  - Dying bodies keep their look and give it back at release.
  - Prewarm stops while models are off.
  - X is Studio-gated in `onKey`. Z goes through the existing Studio-gated RequestDebug path. The free keys don't
    clash with anything else in the combat client.
- The Warhammer:
  - A missing template or a malformed `hold` draws the Chief without it, with one warning per kind.
  - It is scaled once at build (Base = grip holds: `grip` [0, 0, 0]).
  - Every part is sealed, never painted, and fades with the body.
- Missing assets: no config, no rig, a kind without an entry, a size mismatch, or a missing template or stage MeshPart
  all give a placeholder, with one warning only for kinds the config names. `lookOf` validates everything RaiderPose
  reads.
- The walk:
  - the phase runs per stride, and the amplitude eases;
  - it is 0 past `rig.walkNearStuds` (140), or past `COMBAT_RAIDER_WALK_NEAR_LOW` 60 on `lowEndDevice`;
  - idle and far bodies are not redrawn for it.
- Shadows come only from the torso piece, and none on `lowEndDevice`. `reducedMotion` is used nowhere in the new code.
- Gates on the slice files:
  - `check_compile.py --counts`: PASS (181 files); CrowdRenderer is at 164 of 180.
  - luau-lsp: clean on the slice files (combat sourcemap).
  - stylua and selene: clean.
  - Line endings: LF.
- Theme: every new key has a reader. The two removed keys have none, in the hub or the combat place.
  `Types.RaiderPartRole` now includes `clothLeg`.
