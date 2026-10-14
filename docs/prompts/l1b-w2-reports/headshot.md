# Headshots on big bodies: investigation report (L1b Wave 2)

Read-only investigation on branch `l1b-wave2`. Nothing under `src/`, `tools/` or `docs/` was
edited except this file. The probe is scratch, kept in
`C:\Users\benja\AppData\Local\Temp\claude\l1b-w2-headshot\` (`probe.luau`, `run_probe.py`).

## Cause

The server treats the head sphere only as a **crit qualifier, never as a hit volume**. A ray
must first touch the **body sphere**, then it is checked against the head
(`src/combat/server/Services/WeaponService.luau:1080-1085`, `rayCandidates`; the candidate
list is built in `gather`, `:692-697`). The body sphere sits at `height/2` and has radius
`radius`, so it ends at `height/2 + radius`. On a tall, narrow kind that is well below the
drawn head. A ray through the upper half of a brute's or the Colossus's head touches neither
volume the server accepts, so the shot is a **plain miss**: no damage and no marker.

The drawn head is exactly where the server's head is, so the gap is not in placement. It is
the server refusing to look at the head unless the body was touched first. The Colossus is the
worst case: from 30 studs, a Longbow arrow aimed at the dead centre of its head misses outright.

**How sure:** verified by a probe that runs the real `src/shared/HitShapes.luau` (under
`C:\Users\benja\Desktop\tycoon\tools\bin\luau.exe` with the harness's Vector3 shim) through the
same body-then-head test as `rayCandidates`, with the real `ProvingGrounds.json` kinds and
weapons. The client placement and the other suspects were checked by reading only.

The same rule is written into the contract (`docs/INTERFACES.md:4266`, P1 decision 1) and into
the mirror (`tools/sim_range.py:762-767`). That is why no simulator ever showed the problem.

## Table

These are the server's numbers (`WeaponService.luau:693-694`) and the client's placement
(`src/combat/client/Controllers/CrowdRenderer.luau:894-918`: `headY = height - headRadius`,
pivot at the feet), with the body at rest. All values are in studs above the body's ground point.

The probe aims uniformly over the drawn head disc as the shooter sees it. The camera is 5 studs
up and 30 studs from the body. The weapon is Longbow A (width 0.8, pad 0.6). Columns 7 to 10
come from the probe; "today" is the current server rule and "fix" is the proposed one.

| kind | server head centre / radius | drawn head centre | gap | body sphere top (`h/2 + r`) | drawn head span | today: crit / miss | fix: crit / miss | Rifle A today: crit / miss | SMG A today: crit / miss |
|---|---|---|---|---|---|---|---|---|---|
| raider (fodder) | 4.30 / 0.70 | 4.30 | 0 | 3.80 | 3.60-5.00 | 90% / 10% | 100% / 0% | 74% / 26% | 60% / 40% |
| slinger | 4.35 / 0.65 | 4.35 | 0 | 3.70 | 3.70-5.00 | 80% / 20% | 100% / 0% | 61% / 39% | 46% / 54% |
| plated elite (`armoured`; `guard` is the same size) | 5.70 / 0.80 | 5.70 | 0 | 4.95 | 4.90-6.50 | 67% / 33% | 100% / 0% | 51% / 49% | 39% / 61% (centre aim misses) |
| brute | 6.60 / 0.90 | 6.60 | 0 | 5.95 | 5.70-7.50 | 72% / 28% | 100% / 0% | 58% / 42% | 47% / 53% |
| Warlord | 7.90 / 1.10 | 7.90 | 0 | 7.10 | 6.80-9.00 | 59% / 41% | 100% / 0% | 48% / 52% | 39% / 61% (centre aim misses) |
| Colossus | 12.40 / 1.60 | 12.40 | 0 | 11.00 | 10.80-14.00 | 37% / 63% (centre aim misses) | 100% / 0% | 29% / 71% (centre misses) | 24% / 76% (centre misses) |

- With the camera 8 studs up, or from 15 studs, the numbers move by a few points. The Colossus
  is then 40-55% with the Longbow.
- In every case, a shot that registers on the head is a crit ("body" share 0%). The head's crit
  test includes `width/2` (`HitShapes.luau` `Ray`: `reach = width/2 + pad + r`, called with
  pad 0).
- The probe has two limits: the target stands still, and arrow drop (Longbow A `gravity` 18:
  0.3 studs at 30, 0.8 studs at 50) is ignored. Drop pulls the arrow down into the body, which
  helps slightly.

**Why Ben saw small raiders crit but never the big ones:** on a raider only the top tenth of
the head is dead. On a brute it is the top quarter to third, and on the Colossus it is most of
the head, including its centre. Every miss up there also lands nothing at all, which reads as
"the head doesn't count". Moving targets (see "other findings") make a small head harder still.

## Suspects ruled in or out

- **Ruled in: the body sphere is tested first, and the head only after a body hit.**
  `WeaponService.luau:1080-1085` (rays and every arrow step through `rayCandidates`, `:1606`).
  The cone has the same structure (`:1254-1258`), but a cone is wide, so it matters little
  there.
- **Ruled out: crits refused for plated kinds, while the plate stands, or for bosses.**
  `StrikeTally.Add` keeps `crit` on every entry (`src/combat/server/Services/StrikeTally.luau:85,100`).
  `CrowdService.Damage` only receives `amount`, which already carries `critMult`
  (`WeaponService.luau:1263,1293,1695`). It never sees a crit flag.
- **Partly ruled in, for plated kinds only: the client hides the crit on plate hits.**
  On a plate hit the number takes the plate colour, not crit yellow
  (`src/combat/client/Controllers/FeedbackController.luau:1723-1727`, with the `"plate"` tone
  passed at `:3012`). The crosshair still shows the crit (`:2992`). This does not affect
  brutes or the Colossus, which have no plate.
- **Ruled out: the head test uses one small radius for every kind.** It uses each kind's
  `def.headRadius` (`WeaponService.luau:694-695`).
- **Ruled out: the camera ray and the muzzle ray differ.** `shotRay` slides the origin along
  the camera ray itself (`src/combat/client/Controllers/InputController.luau:1038-1042`), and
  the server accepts a camera origin near the head (`WeaponService.luau:466-477`). The aim
  line and the shot line are the same line.
- **Ruled out: the broad phase drops tall bodies.** `CrowdService.Query` uses a bounding
  sphere of `max(radius, height/2)` around half height
  (`src/combat/server/Services/CrowdService.luau:1603-1606`), which already contains the head.
- **Melee never crits, by design.** Swings, blasts, chains and the Arc/Capsule areas all call
  `strike(..., false, ...)` (`WeaponService.luau:858, 971, 1042, 1359`). The contract defines
  a crit as "ray/pellet passes the head sphere" (`docs/INTERFACES.md:4371`).

## Proposed fix

**Owner: luau-engineer A** (hit shapes and the crowd hit path).

1. Add a pure rule to `src/shared/HitShapes.luau`, for example:

   `HitShapes.CrowdRay(origin, direction, reach, width, pad, feet, radius, height, headRadius) -> (entry: number?, crit: boolean)`

   - **Hit:** the padded ray touches the body sphere (centre `feet + height/2`, radius
     `radius`) **or** the head sphere (centre `feet + height - headRadius`, radius
     `headRadius`), both grown by `width/2 + pad`.
   - **Entry:** the smaller of the two entries.
   - **Crit:** the ray with pad 0 (still `width/2`) touches the head sphere. This keeps the
     existing ruling that the pad forgives a miss but does not make a headshot.
   - `rayCandidates` (`WeaponService.luau:1065-1088`) becomes one call to it. The cone's crit
     line stays as it is.
   - The head is fully inside `Query`'s bounding sphere, so the broad phase needs no change.
2. **economy-designer:** mirror the rule in `tools/sim_range.py:762-767`, that is, add the
   head entry to the ray test. Re-run `py tools/sim_range.py --check` and the boss tables.
   Headshots on tall kinds now land, so the bow and rifle boss-time numbers will go down. That
   is a balance re-read, not a weapon-number change.
3. **lead:** amend P1 decision 1 in `docs/INTERFACES.md:4266` to read: "a ray hits if it
   touches the body or the head; it crits if it touches the head unpadded".
4. **Harness case** (a new file such as `tests_w2_headshot`, or appended to `tests_l1b_crowd.luau`;
   HitShapes is already bundled). For every kind in the real `FIXTURES.proving.crowd.kinds`,
   with origin `(0, 5, 30)` and Longbow A's width and pad:
   - (a) a ray aimed at `feet + (0, height - 0.25 * headRadius, 0)` (the top of the head)
     returns an entry and `crit == true`;
   - (b) a ray aimed at the head centre returns `crit == true` (the Colossus fails this today);
   - (c) a ray aimed `headRadius + width/2 + pad + 0.3` above the head top returns nil;
   - (d) a ray at body centre returns `crit == false`;
   - (e) a ray that grazes the head only within `pad` is a hit but not a crit.
5. **Mutations** (`tools/crowd_harness/mutate.py`, on `HITSHAPES`):
   - Drop the head term from the hit test. This is today's rule; (a) and (b) must fail.
   - Pass `pad` instead of 0 to the crit test. (e) must fail.
   - Swap `height - headRadius` for `height / 2` in the head centre. (a) must fail.

**Optional second step** (a balance call for economy-designer and the lead, not needed for the
complaint): the body sphere also leaves the drawn legs and shoulders of tall kinds outside
every shape. On the Colossus the lowest 3 studs of its 4.65-stud legs and the corners of its
torso box are dead to rays. A vertical capsule from `y = radius` to `y = neck`, radius
`radius`, would match the figure. It changes every melee and area test on tall bodies, so it
needs a `sim_range.py` pass. If it is done, put the figure's neck proportion in one shared place
so the renderer and the server read the same number. Today `HEAD_OVERLAP` and `LEG_SHARE` exist
only in `CrowdRenderer.luau:406-412`.

## Other findings (one line each)

- Phone auto-fire and aim checks treat the head as a target (`InputController.luau:1109-1116`).
  The server does not, so on tall kinds auto-fire can fire at heads it cannot hit. The fix
  above makes the two agree.
- The cosmetic shotgun pellets stop on head spheres (`FeedbackController.luau:1271-1277`), which
  the server ignores. They are tracers only, but they show "hits" the server did not count. The
  fix makes them agree as well.
- Enemies are not rewound for hitscan or arrows: the server tests `CrowdService.Get`'s current
  position (`WeaponService.luau:685-694`), while the client draws bodies interpolated about one
  snapshot (15 Hz) plus delivery lag behind. A 0.9-radius head on a moving brute (speed 10)
  loses that first.
- Leans pivot at the feet (`CrowdRenderer.luau:1836-1840`; windup 0.22 rad, stagger 0.32,
  airborne 0.35, `:368-371`). A tall body's drawn head therefore swings away from the server's
  upright head, by about 2.7 studs on the Colossus in a windup and about 1.4 on a brute. The
  swing is along its facing, so it costs most from the side or at steep camera angles. Owner:
  ui-engineer. Shrink the lean by height, or lean at mid-body.
- On plated kinds, a crit on the plate shows the plate colour and plate text size, not the crit
  yellow (`FeedbackController.luau:1723-1735`). The plated elite and the Warlord's headshots
  therefore look like plain hits apart from the crosshair. Owner: ui-engineer.
- The `rayCandidates` comment (`WeaponService.luau:1065-1066`) says the head test is
  "unpadded", but it still includes `width/2`. That is fine, but the wording misleads.
- `tools/sim_range.py` `measure_boss(head=True)` (`:1239`) aims level at the boss's head
  centre (y 12.4). Under today's rule a Longbow-sized ray there misses the `boss` kind outright
  (5.4 > 5.0 reach). The sim faithfully mirrors the bug, so its head numbers will move after
  the fix.
