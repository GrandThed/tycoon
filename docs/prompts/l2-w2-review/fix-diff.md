# L2 W2 fix-diff review (e14fb78..78463a0, 2026-10-18)

Reviewer: roblox-reviewer. Scope: the W2 fix round only (28 files). Read against `l2-w2-review.md`, the three
slice findings, `l2-w2-fix-round.md`, the lead's corner ruling (`shooting.originWallChord` in config) and the
three fix reports.

Gates, run on a `git archive 78463a0` copy in the scratchpad (never in the worktree):

| Gate | Result |
|---|---|
| harness | PASS, 2,809 checks |
| `check_levels.py` | PASS, about 20 s. The d-M1 line reads "22 tops, none". The d-m2 line reads "KNOWN LIMIT until L3, 6 hops". |
| `check_levels_mutants.py --only d-M1` | PASS: 3 red, 2 green controls, shipped data green |

I did not re-run `mutate.py` or the full mutant suite; QA is running both. I read their new entries instead.

**Result: 0 Critical, 0 Major, 3 Minor, 1 Suggestion.**

## Minor

**m1. Camp C's wall is 1 stud thick, so `originWallChord` 1.5 still lets a forged origin through it. Nothing
checks the tolerance against the level, and nothing checks the argument.**

- **Where:**
  - `src/shared/Config/ProvingGrounds.json:286` sets `originWallChord` to 1.5.
  - `src/shared/Types.luau:2021-2023` says it is "under the thinnest wall a level builds (2)".
  - `src/shared/Config/Combat.json:147` sets `fenceThickness` to 1. LevelGeometry builds every camp fence that
    thick, camp C's 64-high wall included (ForestRoad.json camp C `fence.height` 64).
  - `src/combat/server/Services/WeaponService.luau:533-538` is the call.
- **What:**
  - The server report counted only layout blocks ("the thinnest colliding wall in ForestRoad is 2 studs").
    The generated fences are 1 stud.
  - A line from the head through a 1-stud wall crosses about 1.0 to 1.4 studs of solid. `OriginClear` allows
    that.
  - No tool reads `originWallChord`. The source check (`run_harness.py:218` `AIM_RAYS`) matches only
    `local clear = WorldReact.OriginClear(`, not its arguments. `mutate.py` has no entry for the fourth argument.
  - So swapping in `config.shooting.originPad` (6) or setting the config value to 6 leaves every gate green.
    This is the W1 pattern: a shared call's arguments are copies.
- **Scenario:**
  - A party member on a modified client stays outside camp C's wall after the gate closes. Their root is about
    2 studs off the floor rectangle (fence 1 plus body 1), inside `chaseMargin` 2.5, so `CampBrain.InPlay`
    counts their hits.
  - They send shot origins (or an Arrow Rain ground ray) 1.5 to 2 studs from the head, on the clearing's side
    of the wall, and fight the Colossus from behind a wall that every honest camera is kept out of.
  - check_levels' walled-camp and R8 sight rules assume that wall stops shots.
  - The scope is a modified client in the boss room only, the same class as d-m3. A modified client in the
    open tunnel, which d-m3 named, is closed.
- **Fix, either:**
  - build a walled camp's fence at least 2 thick (a per-camp `fence.thickness`, threaded through the trigger
    rectangle, `WallClip`'s fence and check_levels); or
  - set `originWallChord` under 1 (0.9). This refuses corner shots from about 1 stud of lag instead of 2.
- **And, either way:**
  - add a check_levels gate: `originWallChord` < the thinnest colliding piece a level builds whose top is over
    head height (blocks, and the fences of walled camps). Prove it with a mutant (today's 1-stud fence must go
    red with 1.5).
  - add a mutate entry that replaces `config.shooting.originWallChord` with `config.shooting.originPad`.

**m2. An honest origin is refused while the server's copy of the head trails a fast move round a corner or
off an edge.**

- **Where:** `WeaponService.luau:527-549` (`aimAllowed`), used by every ranged shot and, through `CheckAim`
  (`AbilityService.luau:944`), by every ability cast, melee ones included.
- **What:**
  - The line runs from the server's head, which lags, to the client's shoulder origin.
  - The server agent's own case refuses at 2 studs of lag on an inner corner. Hand-traced on the gatehouse
    bend (WallS/WallW corner at x 305.5, z −36), hugging the corner 1 stud off both faces:
    - at walk speed with 2 to 3 studs of lag, nothing is refused;
    - with about 6.5 studs of lag (a dash, Leap Smash or Impale Dash at 60 to 100 studs/s), the line crosses
      1.96 studs of wall and the shot is refused.
  - Dropping off a ledge edge (the lookout) while falling fast works the same way vertically.
- **Where it does NOT happen:** every fight floor is convex. Camp floors carry cover of at most 3.5 and fences
  of 4, and the head's centre (root + 1.5) always stands above both tops. Inside camp C a line between two
  interior points never crosses the wall. So fights lose nothing. Only traversal does: the tunnel bends, the
  gatehouse and ledge edges.
- **Cost:** a refused shot, or a refused cast (`sendState(refused)` after the client's prediction). The first
  refusal in Studio warns once, which is good.
- **Fix (optional):** give the wall test the same lag slack the distance test already grants. Accept when the
  line is clear from the server's head OR from `head + rootVelocity × lag`, using claimSlack's speed and lag.
  Or keep the rule and add one PLAYTEST note: "a cast mid-dash at a tunnel or gatehouse bend may be refused
  (one Studio warn names the wall)".

**m3. The drawn flame and the phone's burn test use the crosshair line. A moving player's stream shots leave
up to 7° off it.**

- **Where:**
  - `InputController.luau:1573`: every non-Mag-Dump shot takes `spreadDirection(look, nextSpreadDegrees(cfg))`.
  - `bloomMult` 0 stops only the per-shot bloom. Moving or airborne bloom still grows to `bloomMaxDegrees` 7
    (ProvingGrounds.json:277-278).
  - `FlameFx.luau:291-292` and `reactOnAuto` (`InputController.luau:1334`) both build along the un-spread
    `look`.
- **What:**
  - The server's capsule runs along the sent, spread direction (WeaponService :1473-1497).
  - At 20 studs its tip sits up to 2.4 studs from the drawn tip, so the flame is "identical" only for a
    player standing still.
  - The bramble still burns, because the capsule radius 3.5 + 0.8 pad is more than 2.4.
  - But a body at the flame's edge can show the flame on it with no tick, or a tick with no flame.
  - The Beam has had the same spread since P3, so this is not a regression of the fix. It is the one gap in
    "drawn from ShotRay, identical to the server".
- **Fix:** give continuous families no spread (`steady` when `variant.continuous`). A 7-wide capsule gains
  nothing from bloom. Or draw the local flame along the last direction sent (`stream.aim`, already stored by
  `onLocalShot`).

## Suggestion

**s1. Each world query allocates new raycast params.** `InputController.luau:1093-1120` (`worldParams` inside
`streamReach`) builds new RaycastParams and walks every player on each call. Touch auto-fire calls it every
frame a stream is held, and FlameFx every frame the local flame shows. That is two allocations a frame, which
is cheap, but WeaponService already caches the same query (`state.worldParams`, rebuilt on a stale flag).
Cache it, and rebuild it on PlayerAdded, PlayerRemoving and CharacterAdded.

## Checked and sound

**The origin rule (d-m3).**
- Honest origins:
  - The origin is `shoulderPoint + look × dot(head − shoulderPoint, look)`. The boom term cancels.
  - The shoulder point is swept from the open pivot with the 0.5 sphere, so it lies at least 0.5 from every
    solid.
  - The along-look shift is −0.6·look.Y. That is always downward and at most 0.3 sideways, so an honest
    origin is never inside a solid, and a standing player is never refused, by any wall, floor or ceiling.
- **ADS** changes only the FOV.
- **Phones and gamepads** use the same camera.
- **The invisible barrier:** the server's rays run in the Default group, which `ArenaBarrier` does not collide
  with, so it is never read as a wall.
- **The lookout ledge, doorways and camp gates:** both points lie inside the opening's band, so the line
  cannot cross a jamb.
- **Forged origins:** refused through every 2-stud cave wall, every gatehouse wall and both brambles (chord
  ≥ 2). The one exception is m1.
- **Cost:** one ray of at most about 8 studs per shot, and a second only when the first hits. The params are
  cached.
- **Missing config:** a missing `originWallChord` reads as 0, which is strict. It fails safe.

**Phone auto-fire at brambles (c-M1).**
- The capsule is cut at the first wall with the server's own query (RespectCanCollide, players excluded).
- Bodies are tested first. A refused (resting) body anywhere in the capsule holds fire, and `aimHeld =
  refused` also stops the ride-out. Only an empty capsule falls through to `WorldReact.Wants`.
- `Wants` requires `React` = the held family's element (only fire or ice), `Heat` < 1 and `Touches`, which is
  the server's test with the same `levels.react.pad`.
- A burnt Part is destroyed by the server, ReactFx forgets it, and the scan stops.
- `ForEachPart` walks only the Parts that carry `React` (2 on Forest Road), so the scan costs nothing.
- The client capsule's fields match the server's (`shape`, `size` = the wall-cut reach, `width` = the
  variant's).

**The local flame (c-M2, c-m6).**
- `ShotRay()` is the very `shotRay` that `rangeAttack` sends, and `StreamReach` is the server's cut. One
  function each, no copied formula.
- Own server strikes now correct only the width, so the flame goes out one linger after release.

**`WorldReact.Apply` against the old loop.**
- It keeps the same descending walk, the same element and Touches tests, and the same heat write-back.
- Heated entries are painted before the gone entries are removed. The gone entries are removed highest
  first, so the indices stay right, and listeners are told in the old order.
- The new `heat == entry.heat` skip only fires when `need` is not a count, and React has already returned in
  that case.
- `StrikeElement` returns nil for any ability strike. `finish` passes `ability.id` to every listener, inside
  `if not fx.abandoned`.

**The 84-high pieces (d-M1).**
- S2 and RoofE split at x −180 against S3 and RoofE2, flush, with no gap. Feet are unchanged (walls −4, roofs
  22), so the inside section (14 high, roof foot 22) and the camera clearance are untouched.
- CaveWallN2 (64) sits inside RoofE's volume for x −204..−180, so there is no exposed ledge at the step. The
  alcove's walls and roof are all at 84.
- The coplanar faces at z −82 and −100 existed in W2 too. They are the same SmoothPlastic and colour, so they
  show no flicker.
- The new rule is not vacuous (mutants above). It takes Leap Smash from every standable surface with
  double-jump take-offs, and it models Impale Dash held in the air.

**The rest.**
- s-m3 is mirrored, with its mutants.
- The d-m2 known limit turns red once a carrying family is owned without a lever.
- The d-m4 fire course ran.
- c-m1: `openPivot` now uses the boom's own sphere from the head.
- c-m2: re-select runs on every repaint, on SetState and on an Abilities result, and only while open and with
  the pad last.
- c-m3: a result frees the pending pick only when it matches `slotId`.
- c-m5: both effects are gated on `lowEndDevice`.
- c-m7: one timeout constant.
- c-m8: comments fixed.
