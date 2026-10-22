# L4 W2 track M: the mountain climb and the Castle Key (economy-designer report)

Worktree `tycoon-p5`, branch `l4-real-forest`, 2026-10-21. **Not committed.** Written as the work goes.

**State:** designed and proved on an in-memory copy of the layout (the `perch_v3_study.py` pattern), then written into
the real files in one step at 19:08 after `mountain-go.md` appeared (the rock builder's track K committed at 7b3e07e;
none of my four files had moved since the brief). Files changed: `src/shared/Layouts/Levels/ForestRoad.json`,
`src/shared/Config/Levels/1_ForestRoad.json`, `tools/check_levels.py` (5 small hunks), `tools/check_levels_mutants.py`
(3), `docs/BALANCE.md` (a new section at the end); new: `tools/check_parkour.py`, this report.

## Summary

- **The climb:** a spiral staircase of 7 ledge pillars round a 28 x 28 core whose top is the summit, one lap
  counter-clockwise seen from above, **8 double jumps of 25 studs each** (yard 0 -> 25 -> ... -> 175 -> summit 200).
  Every hop is a cliff step: the next ledge's face rises straight off the end of the one you stand on (no gap), so a
  missed double jump drops you back onto the ledge you jumped from. Ledges are 24 x 20 (the lookout ledge is 24 x 14).
- **Where:** north-west of the start, behind the trailhead: a 96 x 96 yard at x -658..-562, z -158..-62, reached on
  foot by a path off the trailhead's west edge (96 x 16) and a trail north (16 x 54). The mountain is 116-181 studs from
  the trail's mouth, 123+ from the lookout's ledge, 182+ from the nearest region cell.
- **Why 25 per hop, not a gap:** horizontally a dash adds more than the double jump does (one jump and a dash carry
  34-41 studs at a small rise; the double jump without a dash 25-33), so only height can make a hop need the double
  jump and nothing else. One jump tops out at 18 (21 with check_levels' step up): every hop is 4 short. The double jump
  peaks at 30: 5 to spare (8 with the step up). Leap Smash without the double jump tops at 18 (its targets may be no
  higher than 18 over the caster's floor): 4 short.
- **Falls:** every ledge and the summit stand wholly over the yard, so any fall lands on a lower ledge or the yard.
  The yard's ground meets the level only at one mouth (the path's end at the trailhead), and every top is farther from
  it than its best flight (the jumps, a late double jump, a dash that stops the fall, the walk-off grace) plus the
  longest carrying ability (Leap Smash 32) plus 10. The forest generator must wall the yard, trail and path to y 280.
- **Pay:** 4 Valor + 50 Timber + the Castle Key (`key: "castle"`), once per player.
- **Gates on the real files (Python 3.12.10 64-bit unless said):** check_levels `CHECK: PASS`; check_parkour
  `PARKOUR: PASS` and its mutants 6 of 6 red; check_stage_mirror `CHECK: PASS`; the crowd harness `HARNESS: PASS (4,032
  checks)`; check_levels_mutants: the full run's one miss (an ice-thickness control the summit's height moved) re-aimed
  and green, every other case as expected; sim_range `CHECK: FAIL (1)`, the known Road3 Hard bow-T4 row, identical to
  HEAD's run but for the chest line. `forest.py check` is red as expected until the forest pass rebuilds for the
  mountain (stale planHash), and it must also raise the climb's walls to 280, drop a bogus designed drop the summit
  triggers, and fit 62k more triangles (below).

## The plan (one character = 4 studs; north at the top)

```
 x: -658                                   -562      -482 -458
  z -158 +------------------------------------+
         |  yard (ground, top 0)              |
         |     +--------+-------+------+      |
         |     | L6 150 | L5 125| L4 100      |
         |     |        |       |      |      |
         |     +--------+-------+------+      |
         |     | L7 175 |SUMMIT | L3 75|      |
         |     |        |  200  |      |      |
         |     |        |  [M]  +------+      |
         |     +--------+-------+ L2 50|      |
         |     |entrance| L1 25 |      |      |
         |     | notch 0|       |      |      |
         |     +--------+-------+------+      |
  z  -62 +---------------------------+  trail +
                                     |  (path)|
                                     |  16 x  |
                                     |   54   |
  z   -8                             +--------+--------------------+--------+
                                     |   MountainPath (16 wide)  [sign]  | Trail- |  start
  z    8                             +-----------------------------+ head   |  (-470,0,0)
                                                                   +--------+
 The climb runs counter-clockwise seen from above: from the yard (or the entrance notch) up onto L1, then east to L2,
 north to L3 and L4, west to L5 and L6, south to L7, and east onto the summit (the core's top). [M] = the chest.
 Mouth = MountainPath's east end at x -482 (z -8..8), the only place the climb's ground meets the level.
```

## Side view (the lap unrolled; one row = 25 studs)

```
 200                                                        [SUMMIT]
 175                                                 [L7]---|
 150                                          [L6]---|
 125                                   [L5]---|
 100                            [L4]---|
  75                     [L3]---|
  50              [L2]---|
  25       [L1]---|
   0  yard-|        each step: 25 up, flush, the next ledge's face straight off this one's end
```

## Every block (layout terms; bottoms at -4, inside the yard's 4-deep slab)

| Block | Look | Centre (x, y, z) | Size (sx, sy, sz) | Footprint x / z | Top |
|---|---|---|---|---|---|
| MountainPath | path | (-530, -2, 0) | 96 x 4 x 16 | -578..-482 / -8..8 | 0 |
| MountainTrail | path | (-570, -2, -35) | 16 x 4 x 54 | -578..-562 / -62..-8 | 0 |
| MountainYard | ground | (-610, -2, -110) | 96 x 4 x 96 | -658..-562 / -158..-62 | 0 |
| MountainLedge1 | ground | (-608, 10.5, -86) | 24 x 29 x 20 | -620..-596 / -96..-76 | 25 |
| MountainLedge2 | ground | (-586, 23, -88) | 20 x 54 x 24 | -596..-576 / -100..-76 | 50 |
| MountainLedge3 | ground | (-586, 35.5, -112) | 20 x 79 x 24 | -596..-576 / -124..-100 | 75 |
| MountainLedge4 | ground | (-588, 48, -134) | 24 x 104 x 20 | -600..-576 / -144..-124 | 100 |
| MountainLedge5 | ground | (-612, 60.5, -134) | 24 x 129 x 20 | -624..-600 / -144..-124 | 125 |
| MountainLedge6 | ground | (-634, 73, -132) | 20 x 154 x 24 | -644..-624 / -144..-120 | 150 |
| MountainLedge7 | ground | (-634, 85.5, -108) | 20 x 179 x 24 | -644..-624 / -120..-96 | 175 |
| MountainSummit (the core) | ground | (-610, 98, -110) | 28 x 204 x 28 | -624..-596 / -124..-96 | 200 |
| secret `mountain` (chest) | secret | (-610, 202, -110) | 6 x 4 x 6 | on the summit's centre | 204 |
| its sign | sign | (-490, 0, -5) | 6 x 4 x 6 (Expeditions sign.size) | on MountainPath, flush with its north edge | |

The entrance notch (x -644..-620, z -96..-76) is yard ground with no block: the eighth place of the ring.
Sign text: `MOUNTAIN - needs DOUBLE JUMP`. Parts: 251 -> 264 of 600 (11 blocks, the chest and its sign).

## The hop table

Rises are top to top. "One jump" = jumpHeight 18 plus check_levels' STEP_UP 3. "Double jump" = 18 + 12 at its
peak. "Its reach" = how far on the flat the double jump alone (no dash) still carries the feet at the rise less the
step up. "Best lift" = the highest feet any lifting ability puts a player without the double jump (LIFT_MODEL
"floor": Leap Smash's targets stand at most 18 over his floor, so its apex is never over a jump's top). Faces are
where the two tops meet (the first hop: the yard's whole run along L1's south and west sides).

| # | Hop | Gap | Face | Rise | One jump + step up | Double jump | Its flat reach | Best lift | Air time |
|---|---|---|---|---|---|---|---|---|---|
| 1 | yard -> L1 | 0 | 44 | 25 | 21 (4 short) | 30 (5 over, 8 with step) | 25.3 | 18 (4 short) | 1.00 s |
| 2 | L1 -> L2 | 0 | 20 | 25 | 21 (4 short) | 30 (5 over) | 25.3 | 18 (4 short) | 1.00 s |
| 3 | L2 -> L3 | 0 | 20 | 25 | 21 (4 short) | 30 (5 over) | 25.3 | 18 (4 short) | 1.00 s |
| 4 | L3 -> L4 | 0 | 20 | 25 | 21 (4 short) | 30 (5 over) | 25.3 | 18 (4 short) | 1.00 s |
| 5 | L4 -> L5 | 0 | 20 | 25 | 21 (4 short) | 30 (5 over) | 25.3 | 18 (4 short) | 1.00 s |
| 6 | L5 -> L6 | 0 | 20 | 25 | 21 (4 short) | 30 (5 over) | 25.3 | 18 (4 short) | 1.00 s |
| 7 | L6 -> L7 | 0 | 20 | 25 | 21 (4 short) | 30 (5 over) | 25.3 | 18 (4 short) | 1.00 s |
| 8 | L7 -> summit | 0 | 24 | 25 | 21 (4 short) | 30 (5 over) | 25.3 | 18 (4 short) | 1.00 s |

- **Margins stated:** without the double jump every hop is short by 4 studs of height under check_levels' generous
  model (one jump 18 plus a 3-stud step up; physically 7 short against a ~2-stud step), and no dash, walk-off grace or
  carrying ability adds height (the dash and Impale Dash hold altitude). With it, 5 studs of headroom at the peak; the
  double jump lands the hop when pressed with the first jump's feet 11 or more up: a **0.53 s window** (0.161-0.695 s
  after the jump), phone-friendly.
- **Skips:** two ledges up is 50, over anything the jumps reach (30 + 3); with the double jump and Leap Smash on top
  (the Castle's Greataxe; its target may stand up to 30 over his floor, apex 10 more) the most is one ledge skipped:
  cast in the air over the next ledge, it lands on the one after. Never two. The fewest double jumps to the summit: 8.
- The rise is L2-18a's band for every hop (over 21, at most 26), the band the lookout's 26 already sits in.

## The fall table (off the middle of each edge)

| Top | West | East | North | South |
|---|---|---|---|---|
| L1 25 | yard (25 down) | L2's face | summit's face | yard (25 down) |
| L2 50 | L1 (25 down) | yard (50) | L3's face | yard (50) |
| L3 75 | summit's face | yard (75) | L4's face | L2 (25 down) |
| L4 100 | L5's face | yard (100) | yard (100) | L3 (25 down) |
| L5 125 | L6's face | L4 (25 down) | yard (125) | summit's face |
| L6 150 | yard (150) | L5 (25 down) | yard (150) | L7's face |
| L7 175 | yard (175) | summit's face | L6 (25 down) | yard (175) |
| summit 200 | L7 (25 down) | L3 (125) | L5 (75) | L1 (175) |

A missed double jump hits the next ledge's face and drops back onto the ledge it left; stepping back off a ledge's
start lands on the ledge below; only walking off the outside drops to the yard. Nothing anywhere falls into the void.

**Flights, and the one mouth.** The yard, trail and path meet the rest of the level only where the path joins the
trailhead (x -482, z -8..8). Every flight is measured to it (flat, straight line: shorter than any real path):

| Top | Best flight to the yard | + Leap Smash 32 + 10 | 3 dashes (slam window) | To the mouth | Spare | To the lookout |
|---|---|---|---|---|---|---|
| L1 25 | 63.6 | 105.6 | 95.7 | 132.7 | +27.2 | 142.6 |
| L2 50 | 69.0 | 111.0 | 103.0 | 116.0 | **+5.1** | 123.4 |
| L3 75 | 73.6 | 115.6 | 109.8 | 131.5 | +16.0 | 132.4 |
| L4 100 | 77.6 | 119.6 | 117.6 | 149.3 | +29.7 | 144.8 |
| L5 125 | 81.3 | 123.3 | 122.5 | 165.5 | +42.2 | 165.0 |
| L6 150 | 84.7 | 126.7 | 126.6 | 180.9 | +54.2 | 184.3 |
| L7 175 | 87.9 | 129.9 | 130.1 | 167.1 | +37.2 | 175.2 |
| summit 200 | 90.8 | 132.8 | 133.3 | 144.0 | +11.2 | 148.9 |

- **The flight model is new and longer than check_levels' `stray_reach`** (66.2 from 200 up there): MovementController
  lets the double jump fire any time after airJumpDelay and it *sets* the rise (so a late one, low in a fall, buys
  most), and an air dash's flat mover leaves no rise or fall (it stops a fall). `check_parkour.flight_reach` optimises
  the jump or walk-off, the double jump's moment and one dash's moment.
- **The outer bound:** after a slam lands, the dash key dashes instead of slamming for `slamCooldown` 1.8 s, so a
  player who slams onto a ledge and jumps off at once can dash three times. Even that (third column) ends 10.8 or more
  short of the mouth from every top. Not gated (no other rule models it either); recorded here.
- Flights into the trail or the path are safe (walkable, walled); the yard's wall stops everything else.

## Climb time

Path 257 studs walked from the mouth (137 of it to L1's foot; straight lines), 8 hops at 1.00 s in the air:
**a perfect run 21 s; a first climb about 60 s** (walking at 0.75 of walk speed, 3 s per hop to read the face and line
up, one hop in three missed once). Ben's "1-2 minutes" fits a first climb; repeats get quick (the chest pays once).

## The pay (`Config/Levels/1_ForestRoad.json` `secrets.mountain`)

`{ "name": "Mountain Summit", "valor": 4, "materials": 50, "key": "castle" }`

- **Why:** the Forest's Normal clear pays about 10 Valor (Double Jump's price is "one clear") and its stock is 220
  Timber in about 5 minutes: roughly 2 Valor and 44 Timber a minute. A first climb is about a minute and is the
  hardest double-jump test in the game, so 4 Valor and 50 Timber (23% of the Normal stock) pay two minutes' Valor and a
  minute's Timber once. It sits between the lookout (3 + 50, a 15-second detour that also gives the Flamethrower) and
  the shrine (6 + 60, which needs Castle gear and stays the best-paying chest, Ben's W3 note). The key is the prize.
- Inside every rule: L2-13 / L2-37 (2 or more Valor and under Double Jump's 10; 15-30% of the Normal stock: 23%);
  sim_range's chest share is judged on the same 50 the lookout already pays.

## Gate verdict lines

In memory (scratch `variant.py`: the layout and the level file patched, check_levels' four hunks as monkeypatches),
Python 3.12.10 64-bit:

- `py -3.12 tools/check_levels.py --no-plan` on the variant: **`CHECK: PASS`** (every existing gate, the lookout's
  L2-18 lines unchanged, the mountain's L2-18 (a)-(d) on the layout and on the frozen layout, 264 Parts, the lobby 158
  studs off (needs 150)).
- `check_parkour` on the variant: **`PARKOUR: PASS`**; `--mutants`: **`MUTANTS: PASS (6 of 6 red)`**.

On the real files after the go (19:08), Python 3.12.10 64-bit unless said:

| Gate | Verdict |
|---|---|
| `py -3.12 tools/check_levels.py --no-plan` | `CHECK: PASS` (23.8 s): every existing line as before, plus "4 secrets", the mountain's sign, its L2-18 (a)-(d) on the layout and on the frozen layout ("the closest call: MountainLedge7, 4 studs short"; no lift arc; trigger only on the summit), the ten climb lines, "264 Parts", "Lobby: at least 150 studs from ForestRoad's bounds: 157" |
| `py -3.12 tools/check_parkour.py` | `PARKOUR: PASS` (2.7 s) |
| `py -3.12 tools/check_parkour.py --mutants` | `MUTANTS: PASS (6 of 6 red)`: a ledge lowered to one jump, a gap widened past the double jump, a ledge moved off the yard, the core given a shelf, a ledge raised past the double jump, a mouth within a flight |
| `py tools/check_stage_mirror.py` (shebang: 3.12) | `CHECK: PASS` (the `key` field is ignored by both Validate mirrors, as it should be until the game code adds it) |
| `py tools/crowd_harness/run_harness.py <repo> <main checkout's luau.exe>` (3.14) | `HARNESS: PASS (4,032 checks, C:\Users\benja\Desktop\tycoon-p5\tools\crowd_harness)` (Forest Road's sites: 4 of 4) |
| `py -3.12 tools/sim_range.py --check` | `CHECK: FAIL (1)` (9 min 30 s): the one known row, Hard sword T1 / bow T4 from Road3, seed 11 39,504 / 55.1 against 24,703 / 37.2, the W1 lookout report's numbers to the digit. **A clean copy of HEAD (7b3e07e, `git archive` of src and tools) gives the same `CHECK: FAIL (1)` and an output identical line for line but one**: the chest line, which now also reads "Mountain Summit: 50 Timber = 24%/24%/24% of the clear's 211/211/211" (PASS). The mountain moves no simulator number. |
| `py tools/levels/forest.py check` (3.14) | 9 FAIL, expected before the forest pass: the stale planHash, seven climb-outline walls the perch rule flags (they must be 280 high), and 212,093 triangles (see "For the forest generator") |
| `py -3.12 tools/check_levels_mutants.py --luau <main checkout's luau.exe>` | full run (194 min, every CASE, MIRROR and SIM case): 275 ok, **1 NOT**: "W3 fix3 fd-m2 control: ice.thickness 0.7". Cause and fix below. After the re-aim, `--only "fd-m2"`: **`MUTANTS: PASS`** (all seven fd-m2 cases as expected, 3 min 42 s). The seven L4 W2 cases (six red, one control green) were ok in the full run. |

**The one mutant the mountain moved.** check_levels' frozen-sheet rule (W3 third fix round, fd-m2) bounds the fastest
fall onto the ice by a free fall from the jumps' apex over *the highest top a player reaches anywhere*. That top is now
the summit: 234.8 down to the lowest sheet, 303.5 studs/s, 1.265 studs a physics step at 240 Hz (it was 0.644, over the
lookout). The shipped sheet (`levels.react.ice.thickness` 1.9) still passes (1.265 < 1.9 < the root's 2), but the
case pair around the old bound (0.6 red / 0.7 green) no longer straddled it. I re-aimed it in place to 1.2 red /
1.3 green with a comment (three lines in `check_levels_mutants.py`). Physically no flight from the mountain reaches
the ice (the walled yard, 170+ studs away), so the bound is now conservative by a factor of two; if the lead wants it
tight again, sheet_bounds could take only the tops whose flight (check_parkour.flight_reach) reaches a sheet. That is a
logic change in check_levels, so I did not make it.

Before the go, in memory: check_levels `CHECK: PASS` with the hunks as patches, and the first 82 of check_levels_mutants'
CASES on the variant all as expected (stopped there when the go came, to run on the real files instead).

## For the forest generator (tools/levels/forest.py, the rock builder; after the layout lands)

`check_parkour.CLIMBS["ForestRoad"]` names every piece (yard `MountainYard`, `MountainTrail`, `MountainPath`; ledges
`MountainLedge1..7` in order; summit and core `MountainSummit`; `wallTop` 280). Importing it (no side effects) is the
clean way to key these rules; otherwise match the names.

1. **The walls (must):** the yard's, the trail's and the path's outline (one walled cage) gets `TreeLine` walls from
   killY - 2 **up to y 280** (the summit 200 + `barrier.height` 80), everywhere except the mouth: the path's east end
   at x -482, z -8..8, where it joins the Trailhead. Today's rule (80 over the highest walkable top within 20 studs)
   gives only 105-255 along the yard: a flight off the summit crosses the south edge near L1 at about 200 and would
   clear it. Check: a test in `forest.py check` that every barrier on that outline has `y + sy/2 >= 280`.
   **Confirmed by `forest.py check` on the real layout:** today's walls there come out 130-230 high and the check's own
   perch rule calls seven of them new perches (TreeLine1, 2, 19, 20, 39, 40, 59: tops 30 over to 70 *under* a ledge
   within 49.3). At 280 every one is 80 over the summit, unclimbable by its 43.
2. **No walls on ledge or summit edges (falls are designed):** every ledge lies wholly over the yard, so the union
   outline the generator walls already passes outside them; keep it that way (do not treat the ledges as a separate
   walkable outline).
3. **The designed-drop rule mis-fires on the summit (must fix):** `find_drops` takes every `doubleJump` secret's pillar
   and the nearest walkable block "across" with a positive gap anywhere on the map. For the summit (x -624..-596,
   z -124..-96) every neighbour touches it (gap 0) and the yard contains it, so the first block across with more than
   4 studs of shared span is **CaveAlcove** (z -110..-98, 378 studs east): **confirmed on the real layout**, `Level().drops`
   now holds `x -596..-218, z -110..-98` beside the gap leg's and the lookout's: it would join the walkable whole and
   open a 378-stud hole in the walls through the forest. Skip the climb's secret (or only
   accept a block within the double jump's reach, about 50 studs; the lookout's Road1 is 18).
4. **Faces:** every side face of the eight mountain blocks is cliff (Ben's clustered, stacked bevelled blocks):
   - the core (`MountainSummit`): its four sides from each neighbouring top up to 200 (west face over L7 is the last
     hop's face, 25 tall; over L1 the south face is 175 tall);
   - each ledge's outer faces down to the yard (25-175 tall) and the step faces where a higher ledge rises off its end
     (each 25 tall: L1|L2 at x -596, L2|L3 at z -100, L3|L4 at z -124, L4|L5 at x -600, L5|L6 at x -624, L6|L7 at
     z -120); and the entrance notch's walls (L1's west face, L7's south face, the core's south-west corner).
   Rock must stay **inside each block's box** in plan where a body stands next to it on the ledge below (a face that
   bulges out narrows the ledge under it and moves the landing), and must not overhang a ledge (a lip over a hop face
   would catch the double jump's head).
5. **Tops:** every ledge top and the summit get flat cap stones flush with the block's top (the pillar-top lift,
   +0.06), covering the whole top: the cap is what reads as "stand here". No fir on a ledge (dress_pillars puts a
   `FirHeroB` on two corners of every pillar: keep the hop ends clear; low ferns or stones at the outer corners only).
   Keep each hop's take-off end and landing end (the 6 studs either side of each step face) free of props a camera
   would sit behind.
6. **The summit:** the chest at its centre; a small cairn or banner pole (walk-through, under 4 studs, outside the
   chest's 2.5-stud trigger ring) so the peak reads from the road; nothing taller (the view is the reward).
7. **The yard and the trail:** forest floor with low stones and scree at the mountain's foot (walk-through), trees
   beyond the walls; the trail and path in the road's look (they are `path` blocks). The entrance notch (yard level,
   x -644..-620, z -96..-76) reads as the climb's start: nothing blocks L1's west face there.
8. **Budget:** `forest.py check` on the real layout, with today's rock rules dressing the eight pillars: **212,093
   triangles** against the 150,000 budget (+10% gate): the mountain costs about 62k as dressed now (the rock builder's
   note guessed +20k for the dense style). The big-block sizes on the lower faces are the lever; the lead decides the
   rest. The pillar heights the forest pass asked for (bottoms all at -4, inside the yard's slab):

   | Pillar | Top | Footprint x / z | Outer faces (to the yard) | Step faces (to the ledge below) |
   |---|---|---|---|---|
   | MountainLedge1 | 25 | -620..-596 / -96..-76 | south 25, west 25 (the entrance notch) | |
   | MountainLedge2 | 50 | -596..-576 / -100..-76 | east 50, south 50 | west over L1: 25 |
   | MountainLedge3 | 75 | -596..-576 / -124..-100 | east 75 | south over L2: 25 |
   | MountainLedge4 | 100 | -600..-576 / -144..-124 | east 100, north 100 | south over L3: 25 |
   | MountainLedge5 | 125 | -624..-600 / -144..-124 | north 125 | east over L4: 25 |
   | MountainLedge6 | 150 | -644..-624 / -144..-120 | north 150, west 150 | east over L5: 25 |
   | MountainLedge7 | 175 | -644..-624 / -120..-96 | west 175, south 175 (over the notch) | north over L6: 25 |
   | MountainSummit | 200 | -624..-596 / -124..-96 | none (ringed by ledges) | over L7 25, L5 75, L3 125, L1 175 |

   Every face is a full-height cliff from its foot (yard 0 or the ledge below) to the top; only the 25-stud step faces
   (with L1's two 25-stud faces off the yard and the summit's west face over L7) are faces a player climbs.
9. `forest.py check` compares the data with a fresh build, so it goes red the moment the layout changes (planHash);
   it is green again after the rebuild that dresses the mountain.

## For the game code (W2 contract amendment; nothing of mine)

The key is the opened secret itself (`combat.secrets.forestRoad.mountain == true`): no profile change.

1. **Types:** `Types.LevelSecretConfig` gains `key: string?` (a key id, "castle").
2. **Validate:** `StageFlow.secretProblems` refuses a `key` that is not a short non-empty string (the
   `Unlocks.MAX_FAMILY_LENGTH` cap, like `family`), mirrored in `sim_range.secret_problems` and covered by
   `check_stage_mirror.py`; `rewardOf` counts `key` as a reward field (the mountain also pays Valor and Timber, so it
   pays today; a key-only chest must still pay).
3. **One reader of keys:** a pure `Unlocks.HasLevelKey(combat, keyId, levelFiles)` (or in SecretFlow): true when any
   level file's secret entry with `key == keyId` is opened in the profile. The Castle's locked room calls it later;
   nothing calls it in W2 but the map and the end screen.
4. **The toast:** when a chest that carries a key pays, the chest's reward card adds a line "Castle Key found" (the
   key's name from config; proposed `Expeditions.json keys: { "castle": { "name": "Castle Key", "text": "Opens a
   sealed room in the Castle" } }`, mine to add once the contract names the shape), and a key sound/flash beside the
   Valor and Timber counts.
5. **The map:** the Forest node's secret row shows the mountain like the others (found / not found) with a key glyph;
   once found, the Castle node (when it exists) shows "Castle Key: held". `MapSecretState` gains `key: string?`.
6. **The end screen:** the chests row lists "Mountain Summit: 4 Valor, 50 Timber, Castle Key" in the run it opens.
7. **Levers:** H (reset secrets) already clears the key with the secret; no new lever.
8. **Nothing in `Economy.luau`.**

## check_levels hunks (applied with the layout, at the go)

`tools/check_levels.py`, five small hunks: `import check_parkour` beside `import sim_range`; `"mountain": "doubleJump"`
in `EXPECTED["ForestRoad"]["secrets"]` (with a comment); the secrets line says `{len(wanted)} secrets` instead of
"three"; in `check_secret_reach` (L2-18a) `road, away = check_parkour.ledge_below(layout, secret) or
route_height_near(...)` (a climb's chest is held to the band over its last ledge, 25; the road under it is 200 below);
and one call after `check_secret_reach(...)` in `check_layout`: `check_parkour.check_climbs(sys.modules[__name__], ...)`.
`tools/check_levels_mutants.py`, three: `import check_parkour`; after `CASES` closes, `CASES +=` check_parkour's six
mutants (each through every gate) and one control; and the fd-m2 ice-thickness pair re-aimed from 0.6 / 0.7 to 1.2 /
1.3 (above).
