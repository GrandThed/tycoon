# L4 W2 fix round 2: ui-engineer B (report)

Worktree `tycoon-p5`, branch `l4-w2`. Nothing is committed. This round covers rulings L1 and L2 of
`docs/prompts/l4-w2-fix2.md`, which answer m2 and s1 in `docs/prompts/l4-w2-review/5-fix-diff.md`. Python versions are
named per number: `py -3.12` for raiderpose and check_levels, and the shebang (3.12) for raider_frames and the mirror.

## Headline for the lead: L1 narrows the arc, so D1 runs

**The Chief's 150° sweep cannot meet the 5° rule.** No arm key can fix it; this is geometry.
- At the end of the sweep the body has turned its most, 37.5° (arc/2 x `ARC_TWIST_SHARE` 0.5).
- The farthest weapon vertex is 14.07 studs from the shoulder.
- So the farthest flat reach possible at -70° is **12.04 to 12.08**. The rule needs 12.2 (range 12.7 - 0.5).
- At -75° the best is 11.89 to 11.91.
- The old table's "12.46 is drawable in -75..-60" is true only at the -60° end of that slot.
- The scratch `bound.py` measured this from the real rig at u 0.6, 0.8 and 1.0. It assumes an ideal arm.

A narrower arc also turns the body less, so the left edge gains little. I searched the keys at each arc against all
three rules: 5° sectors, span ends within 5°, and the lag. I rounded keys to 0.01, kept the in-arc maximum ≤ 13.2,
and kept the hammer's jump at the windup's end small.

| arcDegrees | result |
|---|---|
| 150 | Impossible (above). |
| 130 | No keys found. The best lag is 5.5° with the floor at exactly 12.2. |
| 125 | Passes only on one vertex within 0.01 stud of the floor. With the floor 0.01 higher, the lag jumps from 4.65° to 7.8°. Rejected: it passes by accident. |
| **120** | **Passes.** The lag rule still holds with the floor raised by 0.03 stud. The numbers are below. |

**So L1 gives D1 `arcDegrees` 120, not "about 130".** The keys are tuned to 120. Any other arc moves the body's turn
and the tell's edges, and needs a new key search, not just a new number.

## Files changed

- `tools/testfit/raiderpose.py`: L1, the sweep gate.
- `tools/assets/out/RaiderModels.json` and `src/shared/Config/RaiderModels.json`: the Chief's arc `coil` and `follow`,
  and its `posedReach`. I edited the first by hand on those lines only. `py tools/assets/raider_frames.py` rewrote the
  second and then reported `CHECK: PASS ... up to date; turn proof holds`.
- `src/combat/client/Controllers/CampFx.luau`: L2, the "!" follows the head.
- Unchanged: `RaiderPose.luau`, `Figures.luau`, `CrowdRenderer.luau`, `Theme.luau`. The new keys are config only, and
  both pose sides read them.
- Render: `assets/testfit/out/Raiders/RaiderChief_strip.png` (9730 x 1181). The earlier one is kept in
  `assets/testfit/out/Raiders/_before_l4w2_fix2/`.
  - I rendered it from a scratch copy whose `ProvingGrounds.json` has the Chief's arc at 120, so the strip shows the
    sweep as it will play.
  - Path of the copy: `C:\Users\benja\AppData\Local\Temp\claude\c--Users-benja-Desktop-tycoon\3f855f00-eb33-4bab-adb5-c937f685030c\scratchpad\ui-b-2\tree`.
    Its `assets` is a junction to the main checkout's.

## L1: the sweep gate (`raiderpose.py`)

**What changed in the gate:**
- `SECTOR_DEGREES` 15 → **5**.
- The new `tell_lead(half, sweep)` is the ground tell's leading edge in `arc_angle` degrees, mirroring
  `CrowdRenderer.layTell`'s `start + arc * sweep`. It is +half at sweep 0 (his right) and -half at sweep 1 (his left).

`impact_reach` now also records:
- `span`: the angles inside the arc of the weapon vertices "at range", meaning a flat reach of at least range - 0.5;
- `lag`: over every sample of the strike, enraged or not, the most the weapon's leading end lies behind the tell's
  leading edge. The leading end is the leftmost angle among the vertices at range. A sample with nothing at range lags
  without end.

For `SWEEP_FLOOR_KINDS` (the Chief), the gate requires all of these:
- every 5° sector is at least range - 0.5;
- the span is ≤ -half + 5 and ≥ +half - 5;
- the lag is ≤ 5;
- the in-arc ceiling is unchanged.

The other arcs print the same numbers without failing.

**The new keys at arc 120** (`py -3.12`, patched copy):
- `coil` [-0.12, 0.86, 1.07] → **[0.17, 0.78, 1.05]**
- `follow` [-0.19, 1.71, 1.69] → **[-0.23, 1.93, 1.71]**
- `strike` and `steady` are unchanged.

| Measure | Value | Limit |
|---|---|---|
| Sectors, his left to his right (studs) | 12.25 12.35 12.42 12.48 12.54 12.57 12.57 12.57 12.55 12.53 12.50 12.46 12.42 12.39 12.36 12.36 12.38 12.41 12.47 12.54 12.62 12.76 12.94 13.11 | each ≥ 12.2 |
| Span at range | -57.5..+60.0 | ≤ -55 and ≥ +55 |
| Lag behind the tell | at most +4.3° (u 0.53) | ≤ 5 |
| In-arc maximum | 13.11 | ≤ 13.2 |
| Hammer jump from the windup's end to the strike's start | 2.15 studs | was 1.76 |
| `posedReach.out` | 14.53 → **14.82** (3.706 radii, arc windup) | — |

- `up` stays 24.13, so camp C's `tallest` is unchanged.
- `inHead` stays 0.82.
- The head rule passes at 0.400.

How the sweep looks in the strip: the hammer starts low at his right, swings low across his front, and ends level and
straight out at his left. Holding it level is the only way to reach 12.2 at -57°.

**The gate catches each failure.** Each mutant below ran on a copy:
- With `SECTOR_DEGREES` back at 15, the old keys at 150 pass every rule. At 5 they fail: the sectors read 0.00 0.00,
  the span ends at -60.6, and the lag is 14.8°. This is the reviewer's hole.
- With the lag clause removed (`and lag <= SECTOR_DEGREES + 1e-9)` → `and True)`), keys that fail only the lag pass. I
  used `follow` yaw 1.88: sectors ≥ 12.226, span -58.0, lag 6.65°. The real gate turns them red.
- With `tell_lead` reversed (`return -half + 2 * half * sweep`), the shipped keys fail at a lag of 115°.
- The tolerance is narrow. Changing the follow yaw by ±0.05 rad, or the pitch by -0.07, breaks the lag rule. Any drift in
  the rig or in Theme turns the gate red, which is the point of it.

**`raiderpose.py --check` in the worktree exits 1 until D1 sets 120. This is by design, as last round.** Two Chief rows
fail:
- `posedReach` is STALE, because the windup twist differs at 150;
- the sweep row: span -65.0, lag 11.4°.

On a copy at 120 it exits 0 with every row PASS.

## L2: the "!" follows the head (`CampFx.luau`)

- `step` now asks `CrowdRenderer.GetHead(mark.id)` once.
  - A nil answer ends the mark. That covers a body that died, left, was handed back to the pool (its old id answers
    nil), or is not drawn.
  - A different part re-hangs the mark: a waiting placeholder put its model on (K3), or X re-dressed it either way.
- The new local `hang(mark, head)` sets `head`, `Adornee` and `StudsOffsetWorldSpace`. `Alert` uses it too.
  - A model's anchor and the placeholder's head are the same sphere, `2 x headRadius`, so a re-hang does not move the
    mark.
- Crowd ids cycle through 65,535 (`CrowdService.nextId`), so the old id cannot come back during the mark's 1.5 s.

## Gates (mine)

| Gate | Result |
|---|---|
| `stylua --check`, `selene` on `CampFx.luau` | clean, 0 / 0 / 0 |
| luau-lsp, `src/combat src/shared`, combat sourcemap (scratch) | exit 0, no diagnostics |
| luau-lsp, `src/client src/server src/shared`, hub sourcemap (scratch) | exit 0, no diagnostics |
| `py tools/check_compile.py` | PASS, 182 files |
| Harness (`py`, 3.14) | **PASS, 4,668 checks** |
| `py -3.12 tools/testfit/raiderpose.py --check` | worktree exit 1 (the Chief, by design until D1); patched copy at 120: exit 0, every rule PASS |
| `py tools/assets/raider_frames.py --check --require-harvest` | PASS |
| `py tools/check_raider_mirror.py --luau <luau>` | CHECK: PASS, 16,842 cases, worst 7.11e-15 |
| the same with `--mutants` | MUTANTS: PASS, 20 of 20 red |
| `py -3.12 tools/check_levels.py` | CHECK: PASS; camp C eyes +1.73, cameras +2.84 (unchanged) |

- `raiderpose.py` compiles under 3.12 and 3.14.
- Every file is LF.

## For the other owners

### D1 (`src/shared/Config/ProvingGrounds.json`, the Chief's attack 4, line 71)

- old: `"range": 12.7, "arcDegrees": 150,`
- new: `"range": 12.7, "arcDegrees": 120,`

Then:
- re-measure the bands (R8, and anything else that reads the Chief's sweep);
- run `py -3.12 tools/testfit/raiderpose.py --check`, which then goes green;
- re-run `check_levels.py`. Its sight gate reads `posedReach`, which is already the 120 value (14.82).

Change only the number. Do not change the keys: they are tuned to 120. If the bands call for another arc, ask for a new
key search rather than editing the keys.

### D2: pins and mutate

**m1 probes in Figures and CrowdRenderer.** I did not change these files this round, so the reviewer's lines stand.
Whole, with indentation (`\t` = one tab):

- `Figures.luau:733`
  `\tlocal figure: Figure? = if pool ~= nil then table.remove(pool) else nil`
  Mutant (Take builds again):
  `\tlocal figure: Figure? = if pool ~= nil and #pool > 0 then table.remove(pool) else build(look)`.
- `Figures.luau:800`
  `\tlocal share = if total > room then room / total else 1`
  Mutant: `\tlocal share = 1`.
- `Figures.luau:836`
  `\tlocal budget = math.max(math.floor(Theme.COMBAT_RAIDER_PREWARM_PER_FRAME), 1)`
  Mutant: `\tlocal budget = math.huge`.
- `CrowdRenderer.luau:1013`
  `\tentity.wants = if figure == nil then look else nil`
  Mutant: `\tentity.wants = nil`.
- `CrowdRenderer.luau:2672`
  `\tlocal built = Figures.Build()`
  Mutant: `\tlocal built = 0`.
- `CrowdRenderer.luau:2699` (four tabs; it is unique in the file)
  `\t\t\t\twear(entity, wanted)`
  Mutant: `\t\t\t\tFigures.Wait(wanted)`.

**New deciding lines in `CampFx.luau` (L2).** No harness test or mutate entry touches CampFx today.

- line 145: `\t\tlocal head = CrowdRenderer.GetHead(mark.id)`
- line 146: `\t\tif age >= lasts or head == nil then`
  Mutant: `\t\tif age >= lasts or head ~= mark.head then` (s1 returns: a swap drops the mark).
- line 150: `\t\tif head ~= mark.head then`
- line 151: `\t\t\thang(mark, head)`
  Mutant: `\t\t\tmark.head = head` (the mark stays on the old, pooled part).
- line 112: `\tmark.gui.Adornee = head`
  Mutant: delete the line.
- line 211, in `Alert`: `\t\thang(shown, head)`

**`check_raider_mirror.py`: no new case is needed.** `RaiderPose.luau` and the functions it mirrors are untouched; the
keys are config that both sides read. The mirror and its 20 mutants pass as they stand.

**`raiderpose.py`.** Its gate lines, in case you pin text:
- 963: `SECTOR_DEGREES = 5.0`
- 987: `    return half - 2 * half * sweep`
- 1059-1061:
  ```
              ok = (ok and min(sectors) >= at_range - 1e-9
                    and span[0] <= -half + SECTOR_DEGREES + 1e-9 and span[1] >= half - SECTOR_DEGREES - 1e-9
                    and lag <= SECTOR_DEGREES + 1e-9)
  ```
- 1047: `                    behind = leading - tell_lead(half, t.sweep)`

The mutants above are proven to turn the Chief's row red.

**mutate.py:** run `files:CampFx.luau` once you have added entries.

### Generator owner (route via the lead): `tools/assets/raider_kit.py:570`

Without this, the next generator run brings the old keys back. It then computes `posedReach` from the kind's arc, which
gives 14.82 once D1 has set 120.

- old: `            "arc": {"coil": [-0.12, 0.86, 1.07], "strike": [0.4, -0.3, 1.45], "follow": [-0.19, 1.71, 1.69], "steady": True},`
- new: `            "arc": {"coil": [0.17, 0.78, 1.05], "strike": [0.4, -0.3, 1.45], "follow": [-0.23, 1.93, 1.71], "steady": True},`

### Lead

- Two alternatives to narrowing the arc exist outside this ruling. Neither is taken.
  - Raise `Theme.COMBAT_RANGE_TELL_ARC_TWIST_SHARE`. That changes the turn of every arc kind and of the placeholder.
  - Lower the range. Keeping 150° would need a range of about 12.5 or less (floor 12.0 against a best of 12.04 at
    -70°). That leaves no margin, and the in-arc ceiling falls with it. I did not search it.
- The plated elite's sweep is still ungated. At 5° it reads 0.00 for its left 40°, and it is never at range 7.

## Assumptions

- "The hammer at range" means weapon vertices at a flat reach of at least range - 0.5, the floor the sectors use. The
  lag is judged on the leftmost of them, which is the direction the sweep runs. This measure reproduces the reviewer's
  "7-14° from u 0.40 to 0.55" on the old keys.
- The lag is judged over the whole strike, not only while the sweep runs, because the reviewer's failure was the hammer
  "parked" at -60° while the tell stood at -75°.

## Remotes and state consumed

- No new remotes.
- CampFx reads `CrowdRenderer.GetHead`, as before.
- Config: `RaiderModels.json` (the Chief's arc keys) and `ProvingGrounds.json` (`arcDegrees`, D1's).

## What to check in Studio

1. Press **N** to reach the clearing (never B). The Chief winds the hammer low to his right, sweeps it low across his
   front and finishes level at his left.
   - The red wedge is narrower (120°) once D1's change lands.
   - The hammer stays at the wedge's rim as its leading edge runs, never parking short of the left edge.
2. Wake a camp group on a fresh session, before the pools have filled.
   - The "!" stays over each raider while its placeholder turns into its model.
   - Press **X** while marks are up: the marks stay.
3. Phone emulator at 667 x 375 and 375 x 667, and desktop at 1920 x 1080. The mark's size and offset are unchanged
   (studs plus pixels); nothing else on screen changed.
