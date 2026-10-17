# L2 W1 second fix round (2026-10-17)

Branch `l2-w1-fix2` in `C:\Users\benja\Desktop\tycoon-p5b`. Nothing is committed. Brief:
`docs/prompts/l2-w1-fix2.md`; findings: `docs/prompts/l2-w1-review/fix-diff.md`.

## Files

- `src/combat/client/Controllers/CombatUIController.luau`: Major 1.
- `src/shared/GroundRule.luau` (new), `src/combat/client/Controllers/InputController.luau`,
  `src/combat/server/Services/WeaponService.luau`, `src/shared/WallClip.luau` (header comment only): Minor 1.
- `tools/crowd_harness/run_harness.py`, `tools/crowd_harness/tests_l2.luau`, `tools/crowd_harness/mutate.py`: Minor 1.
- `src/combat/client/Controllers/SecretFx.luau`: Minor 2.
- `src/combat/client/Controllers/MovementController.luau`: Minor 3.
- `sourcemap.json`, `sourcemap.combat.json`: regenerated with rojo (they now list GroundRule).

## Major 1: the HUD's offset is the GUI inset

`applyLayout` now passes `inset` (`GuiService:GetGuiInset()`, the HUD ScreenGui's top-left in the
viewport) to `bottomObstacles`, not `screenGui.AbsolutePosition`. The crosshair's centre
(`viewport.Y / 2 - inset.Y`) already used that convention. `bottomObstacles`'s comment now says
why AbsolutePosition is wrong: it is measured from under the top bar, so it reads (0, 0).

**Probe.** A bundle under `tools\bin\luau.exe` built from the real sources:
- the whole of `ActionRows`;
- `JumpButtonRect`, `SatelliteRect` and `ClusterRect` cut verbatim out of MovementController;
- `VitalsHud.BarPlace`;
- `hudScale`, `touchCluster` and `bottomObstacles` cut verbatim out of CombatUIController;
- the Theme numbers read from Theme.luau.

It models the lobby with Map, Abilities and Return on a touch device. The AbilityBar is hidden on
touch, so it is passed as (math.huge, 0, 0). All values are viewport px, at scale 0.9167
(MIN_SCALE). Script: scratchpad `fix2/rows_probe.py`.

| Viewport (inset 58) | Rows, top to bottom | Return | Clearance |
|---|---|---|---|
| 667x375 | `[Map]` / `[Abilities][Return]` | x 95.3-190.7, y 320-364 | **51.2 px** to the health bar (x 241.8, y 349.3-365.8). Dash (x 507.6) is not in Return's reach |
| 640x360 | `[Map]` / `[Abilities][Return]` | x 95.3-190.7, y 305-349 | **37.4 px** to the health bar (x 228.0, y 334.3-350.8) |
| 375x667 | `[Map]` / `[Abilities]` / `[Return]` | x 7.3-102.7, y 612-656 | **55.5 px** to the slot button (x 158.2); Dash starts at x 215.6 (112.9 px). Map is 80.4 px from the melee ability and the health bar (y 490-507) is above it |

- **Inset 36:** the same rows in both landscapes. In portrait the scale rises to 0.946 and Map
  stands 17.2 px clear of the health bar. Return is 52.2 px clear of the slot button.
- **The old origin (0, 0), for comparison:** one row at 667x375. Return reaches x 264.0 over a bar
  that starts at 241.8 (−22.2 px). At 640x360, −36.0 px. This is the reviewer's result exactly,
  so the probe reproduces his port.
- **1920x1080, PC:** one row, Return ends at x 441.3. The health bar starts at x 806.8. The
  AbilityBar edge was not modelled; the earlier report put it at 758.

## Minor 1: one shared helper, a source check scoped to the two functions

- **`src/shared/GroundRule.luau` (new).**
  - `GroundRule.OwnsAirJump(player)` returns `player:GetAttribute(Unlocks.Attribute(Unlocks.AIR_JUMP)) == true`.
  - `GroundRule.Floor(player, probedCaster, feetY, probedTarget)` returns
    `WallClip.GroundFloor(probedCaster, feetY, probedTarget, Tuning.Get().movement, GroundRule.OwnsAirJump(player))`.
  - It requires Tuning, Unlocks and WallClip only. WallClip stays pure.
- **The call sites.**
  - `InputController.groundPoint` makes one call, `GroundRule.Floor(Players.LocalPlayer, <caster probe>, <feet>, <target probe>)`.
  - `WeaponService.GroundPoint` makes the same call with `player`.
  - Neither file requires WallClip or Unlocks any more.
- **The harness.** `run_harness.py` `source_reading`:
  - It reads only the text of `local function groundPoint(` (InputController) and
    `function WeaponService.GroundPoint(` (WeaponService), each up to its closing `end` at column 0.
  - Per side it reports `found`, `rule` (`GroundRule.Floor(` calls), `calls` (`WallClip.GroundFloor(`),
    `parts` (`Rise(` / `TooHigh(` / `CasterFloor(`) and `reads` (`GetAttribute(`, `Tuning.Get(`, `.movement`).
  - The case requires found, rule 1, and 0 for each of the others.
  - The rest of WeaponService may now call WallClip freely.
- **`tests_l2.luau` `groundFloorTests`: five new checks.**
  - They load GroundRule with a stub player.
  - They swap Tuning's live `movement` to heights no other case uses (7 + 5, then 9 + 4), and restore it after.
  - Checks: an owner rises 12 and no more; anyone else rises 7; only `true` owns (false, "true", 1
    and a table do not, and nil does not); a void gives the feet less the rise; the heights are read
    from Tuning on every call.
- **`mutate.py` `L2_FIX2_MUTATIONS`: nine entries, plus `GroundRule.luau` in FILES.**
  - The reviewer's two probes, written against the new call sites:
    - the client writes its own inputs with `GetAttribute(...) ~= false`;
    - the server writes its own inputs with `{ jumpHeight = 30, doubleJumpHeight = 0 }`.
  - The server calls the rule but overrides the result on a raw attribute read.
  - The server's function is renamed, so the check cannot find it.
  - Inside GroundRule: `~= false`, typed heights, heights cached from the first call, the double
    jump ignored, another attribute name.
  - The two existing "keeps its own copy" entries are re-pointed at `GroundRule.Floor(`.

## Minor 2: the card measures its rows

- **Measuring.** `fitRow` measures each row with
  `TextService:GetTextSize(text, TextSize, Font, Vector2.new(SECRET_CARD_WIDTH − 2·padding, ∞))`.
  This is the label's real width in design px; the card's UIScale applies on top. It sets the
  label's height to the measured height (at least one line) + `CARD_LINE_PAD`.
- **Placing.** `showCard` fits all four rows, then calls `placeCard`. `placeCard` sums the visible
  rows' `Size.Y.Offset`, plus padding and gaps. That is the same set of heights the card's
  UIListLayout stacks, so the note can never overlap the reward line, and the card is placed from
  its real height.
- **Safety net.** Every row keeps `AutomaticSize.Y`. Size is the floor, so if the engine ever wraps
  one line more than TextService said, the row still grows instead of overlapping.

**Placement at 667x375 for the lookout card** (title, Valor, Timber, and a two-line note). The
heights assume Gotham's measured line height equals TextSize, which needs Studio to confirm. The
rows are 26 + 21 + 21 + 30, plus 24 padding and 6 of gaps: 128 design px, 117.3 px at 0.9167.

| Viewport, inset | Card | Against the reticle |
|---|---|---|
| 667x375, 58 | Pinned at the margin: y 7.3-124.7 (HUD px) | Covers the top tick (112.1-120.3). Ends 4.8 px above the crosshair's centre (129.5) |
| 667x375, 36 | y 9.4-126.7 | 7.4 px clear of the top tick (134.1) |
| 640x360, 58 | Pinned: y 7.3-124.6 | **Reaches 2.6 px past the crosshair's centre (122.0)** |
| 375x667, 1920x1080 | Placed above the ticks with the full margin | Clear |

- On screens where the card is pinned, the measurement changes nothing on screen. AutomaticSize
  already grew the note, and the old top formula pinned the card too.
- The fix matters on the in-between heights: there the old one-line count put the card's bottom
  one note line (about 11 px) lower than placed, onto the ticks.
- **Residual, the lead's call.** The four-row card cannot stand clear of the reticle on a 640x360 or
  667x375 phone under a 58 px top bar. Two ways out:
  - a one-line note (copy that fits 276 design px at 12 pt, about 45 characters);
  - or, when the card is pinned and would reach the ticks, send the family note to the toast instead.

  I changed neither, because both are UX/copy decisions outside the ruling.

## Minor 3: a launch is no walk-off

- **Why speed cannot tell them apart.** Every launch in `ProvingGrounds.json` is 3 studs: 34.3
  studs/s, under the walk-off line of 42.0. So `ApplyKnock` marks the launch itself.
- **What `ApplyKnock` does now.** When it lifts, it sets `takeoff.walkedOff = false` and
  `takeoff.launchedAt = os.clock()`.
- **What `noteTakeoff` does now.** It counts a walk-off only if the body leaves its floor more than
  `LAUNCH_TAKEOFF_SECONDS` (0.25, a local infrastructure constant beside `WALK_OFF_RISE_SHARE`)
  after the last launch, and slower than the line.
- **Why both are needed.** A grounded body's take-off is noted by `step` one frame after the
  launch, and that note would otherwise set `walkedOff` again.
- **Already airborne.** Clearing the flag is enough.
- `CharacterAdded` resets `launchedAt`.
- **Result.**
  - No grace jump comes from a launch, including a press in the launch's own frame.
  - The first deliberate air press after a launch shows the "buy Double Jump" hint again.
- The constant's comment no longer says a launch leaves faster.

## Gates

All run in `tycoon-p5b`. `tycoon-p5` was never touched.

- **Harness:** `HARNESS: PASS (2,630 checks, C:\Users\benja\Desktop\tycoon-p5b\tools\crowd_harness)`
  (was 2,625), run with `C:\Users\benja\Desktop\tycoon\tools\bin\luau.exe`.
- **mutate.py, filtered to entries whose file I changed** (InputController, WeaponService,
  WallClip, GroundRule): `MUTATIONS: 46 run, 0 not caught` (baseline `HARNESS: PASS (2,630 checks)`; all 9 new and both re-pointed c4 entries caught). Run through a scratch wrapper (`fix2/mutate_files.py`)
  that executes the repo's own mutate.py with its label filter swapped for a file filter. The
  mutant root was `tools/crowd_harness/mutant/` in this worktree, which is gitignored and removed
  at the end.
- **Stale-text count over all entries:** 879 entries, 0 stale (870 + the 9 new).
- **check_compile:** `CHECK: PASS -- 166 files compile with Studio settings (-O1 -g2)`.
- **stylua --check:** clean on the seven changed Luau files (it reformatted SecretFx and
  CombatUIController once).
- **selene:** 0 errors, 0 warnings.
- **luau-lsp analyze** with `tools/types/globalTypes.d.luau`, after regenerating both sourcemaps
  with rojo: the combat map over `src/combat src/shared` exits 0; the hub map over
  `src/server src/client src/shared` exits 0.
- **rojo build combat.project.json** to scratch: built.
- **LF:** all files are LF.

## For other owners

None. `MovementController`'s own air-jump check (`GetAttribute(...) ~= true`) could also read
`GroundRule.OwnsAirJump`. It is a jump rule, not the ground point, so I left it alone.

## Studio

1. **Phone emulator, 667x375, in a non-proving build so Return shows.** In the lobby, Map sits
   above Abilities and Return. Return ends well short of the health bar. Then 640x360 and portrait
   375x667: three stacked buttons, none on the Dash or slot button. One print of
   `GuiService:GetGuiInset()` confirms the 58 (or 36) the numbers assume.
2. **The lookout card at 667x375 and 640x360.** The family note sits under "+50 Timber" with no
   overlap. Note where the card ends against the crosshair (the residual above).
3. **Get launched by an enemy, then press jump.** You get no full ground jump. Without Double Jump,
   the first deliberate air press shows the hint.
4. **A Leap Smash aimed at the ledge from Road5 without Double Jump:** refused on both sides, as
   before. With it: allowed.
