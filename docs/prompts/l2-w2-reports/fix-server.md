# L2 W2 fix round: server agent report (2026-10-18)

Slice: s-m1, s-m2, s-m3, d-m3 and the pure half of c-M1 (`docs/prompts/l2-w2-fix-round.md`). Nothing committed.

## Files changed

- `src/shared/WorldReact.luau`: new `Entry` type; `StrikeElement`, `Apply`, `BoxOf`, `OriginClear`, `Wants`.
- `src/shared/Unlocks.luau`: `IsElement`.
- `src/combat/server/Services/LevelService.luau`: `React` only executes (StrikeElement, then Apply). `Reactive`
  is now `{ name, part, opens, cell: WorldReact.Entry }`. Dropped the unused `Unlocks` require.
- `src/combat/server/Services/WeaponService.luau`: `aimAllowed` adds the wall rule (d-m3).
  `CONST.ORIGIN_WALL_CHORD = 1.5`. `state.warnedAimWall` (one Studio warn per player, cleared in RemovePlayer).
- `src/combat/server/Services/StageFlow.luau`: `reactProblems` refuses a shortcut `sx`, `sy` or `sz` of 0 or below (s-m3).
- `tools/crowd_harness/run_harness.py`: `source_reading` gains `wiring`. It checks Main's
  `OnStrikeResolved(LevelService.React)`, finish()'s listeners inside `if not fx.abandoned`, React's StrikeElement
  and Apply calls with no loop of its own, and aimAllowed's two rays plus OriginClear.
- `tools/crowd_harness/tests_l2w2.luau`: new groups `applyTests`, `wiringTests` and `originTests`, plus the s-m3
  refusals. The harness went from 2,758 to 2,809 checks.
- `tools/crowd_harness/mutate.py`: `L2W2_FIX_MUTATIONS` has 36 entries. Main and LevelService are copied for the source checks.
- `tools/check_stage_mirror.py`: three s-m3 refusals and one accepted case (sx 0.01).
- AbilityService needed nothing: casts go through `WeaponService.CheckAim`, which calls `aimAllowed`.

## WorldReact for the client agent (c-M1)

```lua
WorldReact.Wants(element: string?, react: any, heat: any, fx: WorldReact.Strike, box: WorldReact.Box, pad: number): boolean
WorldReact.BoxOf(position: Vector3, size: Vector3): WorldReact.Box
WorldReact.Pad(rules: WorldReact.Rules?): number   -- existing; Combat.json levels.react.pad
Unlocks.IsElement(word: any): boolean
```

- What to pass:
  - `element`: `Unlocks.ElementOf(weapons, heldFamily)`.
  - `react`: `part:GetAttribute("React")`.
  - `heat`: `part:GetAttribute("Heat")`. nil reads as 0. NaN or a non-number reads as burnt.
  - `fx`: `{ shape = "capsule", origin = <ShotRay origin>, direction = look, size = <range cut at the first wall>, width = <variant width> }`.
  - `box`: `WorldReact.BoxOf(part.Position, part.Size)`. Level blocks are never rotated.
- Wants returns true only when all three hold:
  - `react == element`, and element is "fire" or "ice";
  - heat is under 1;
  - `Touches(fx, box, pad)`.
- Resting bodies remain the client's own rule (CampAim).

The server uses:

```lua
WorldReact.StrikeElement(weapons, weapon: string, ability: string?): Types.Element?   -- nil for any ability strike (s-m2)
WorldReact.Apply(entries: { WorldReact.Entry }, element: string?, fx, pad: number, need: number): ({ number }, { number })
	-- (gone, heated) indices, highest first; writes entry.heat
WorldReact.OriginClear(distance: number, forward: number?, backward: number?, tolerance: number): boolean
```

## d-m3: the origin wall rule, and the lead's corner ruling

- **How it decides:**
  - The distance test is unchanged.
  - One ray goes from the head to the origin, and only if that ray hits, one more goes back from the origin to the
    head. Both use `worldParams()`: characters excluded, `RespectCanCollide`.
  - The solid between the two hits, `distance - back - forward`, may be up to 1.5 studs.
  - If the forward ray hits and the back ray does not, the origin is inside a solid and the shot is refused.
    A shot from inside a part would leave through its far face.
  - The thinnest colliding wall in ForestRoad is 2 studs, so every origin behind a wall is still refused.
- **Visible in Studio:** the first wall refusal per player warns once, naming the distance and the part the ray hit.
  The client then gets the normal `sendRefused`.
- **The corner case tested** (`originTests`, mirrored by a slab ray-caster in the test):
  - Setup: the inner corner of a bend made of two 2-stud walls meeting at (0, 0), solid where x < 0 and z < 0.
    The honest origin is at (-1.2, 3.6, 0.9): 1.75 to the shoulder side, 0.6 up, 0.7 off the walls.
  - Head at (1, 3, -1.2), standing still: 0.36 studs of wall crossed, **allowed**.
  - Server head 1 stud behind: 0.97, **allowed**.
  - 1.5 studs behind: 1.25, **allowed**.
  - 2 studs behind: 1.52, **refused**.
- **Forged origins still refused:**
  - 4 studs away, beyond a 2-stud wall: refused.
  - Beyond the other wall at a slant: refused.
  - Inside the wall: refused.
  - 0.3 studs into the wall: refused.
- **Legitimate shots it would still refuse:**
  1. Hugging the inner corner of a 2-stud bend while the server's copy of the head trails 2 or more studs, so the
     solid crossed exceeds 1.5. This is rounding the bend at full speed with ping (walkSpeed 20 at 100 ms is about
     2 studs; a dash is more). It costs one shot or cast; the next shot after the server catches up passes.
  2. Shoulder-cam origins are always pulled clear of walls by the camera's spherecast, so a straight wall, a floor
     or a ceiling never refuses.
  3. A camera at the shoulder inside the 12 × 14 tunnel's straight runs passes: both points are on the open side of a flat wall.
- **Known limit:** a forged origin inside a wall piece whose back ray meets an *overlapping* piece's face could read
  as a short chord. The shot would then leave that piece's far face. This needs overlapping wall pieces and a
  modified client. Not closed.
- **Proposed config key, not added:** `shooting.originWallChord` (1.5) in `ProvingGrounds.json`, replacing
  `CONST.ORIGIN_WALL_CHORD`. It is the data agent's file. I kept a CONST with its reason in the meantime.

## Required change outside my files

- The s-m3 mirror in `tools/sim_range.py` (data agent) has landed (line 5446), and `check_stage_mirror` passes.
- Optional: `SecretFlow.Shortcuts` keeps a size of 0 (`>= 0`). Validate now refuses it before a level loads.
- Optional: the `shooting.originWallChord` config key proposed above.

## Gates (final code, 2026-10-18)

- harness: PASS (2,809 checks; was 2,758).
- Filtered mutate `"l2w2 fix"`: 36 run.
  - First pass: 35 caught. The Main mutant survived because a commented-out line still matched.
  - Fix: the check now needs a live top-level line (a regex).
  - Re-run of that mutant: caught.
- Stale count over all 972 entries: 0.
- check_stage_mirror: PASS.
- check_compile: PASS (172 files).
- stylua, selene, luau-lsp: clean on WorldReact, Unlocks, LevelService, WeaponService, StageFlow, AbilityService, Main.
