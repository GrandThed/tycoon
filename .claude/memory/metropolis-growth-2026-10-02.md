---
name: metropolis-growth-2026-10-02
description: M12 wave 3 (Metropolis growing city), signed off and merged 2026-10-05 — avenues at 88 lots, density ceiling, tiles-era lanes, prop swaps, the gates it added
metadata:
  type: project
---

**Signed off and merged 2026-10-05.** Ben on his Studio look at `build/metropolis.rbxl`: "looks good!". `main`
is at d0dd894 (a fast-forward; on `origin/main` a minute later, see [[main-auto-push-2026-10-05]]). It was a look, not the 51-step checklist: phone, low graphics,
two players and the measurement (PLAYTEST "M12 wave 3" step 49) are unreported, like Village step 37 and
Boomtown step 59. Worktrees `tycoon-m12m-avenues` and `tycoon-m12m-boulevard` are removed; `tycoon-m12m`
is unregistered but its folder was left half-deleted because Studio had `build\metropolis.rbxl` open from
it (delete the folder once Studio is closed; nothing in it is unique). Branches kept as the record:
`m12-metropolis-avenues`, `m12-metropolis-boulevard`. The Studio build is `tycoon\build\metropolis.rbxl`
(never publish). **Next: Orbital (wave 4), only when Ben says so**; it has the same 7-stud lattice and
ring, so run the density arithmetic before setting any target.

M12 wave 3, Metropolis, started 2026-10-02 from `docs/prompts/m12-metropolis.md`. Contract: `docs/INTERFACES.md`
"M12 wave 3 — Metropolis" → "Wave 3.1" (a gate for Ben, not yet a contract). Base worktree
`C:\Users\benja\Desktop\tycoon-m12m` (branch `m12-metropolis`); candidates `tycoon-m12m-avenues` and
`tycoon-m12m-boulevard` (branches `m12-metropolis-<c>`), all with `assets\` junctions.

**The density ceiling is geometric.** A tile street costs a 15-stud band (7 road + 4 + 4 pavement), the
ring deck leaves 105 × 105 inside, and only three street lines with a row each side fit across. Rows of
lots on streets top out around 50–70; even the whole square tiled with rows holds ~136 narrow lots, ~93
after 22 landmarks. The contract's first target (110) was set from Village/Boomtown without that
arithmetic; both designers proved it impossible in step 1. Narrow lots became 4 × 8 (+25%).

**Candidates at the gate:** "avenues" (cross-town street + three avenues, lots on streets only, 67 lots)
and "boulevard" (axis to the Skyscraper, two cross streets, four pedestrian alleys, 75 lots: 13 street +
62 alley). Boulevard is denser but reads as uniform terrace superblocks (two narrow props per district);
the 3-stud alleys barely show from the tycoon camera. Sheet: `assets/testfit/out/Metropolis/m12m_compare.png`.

**Ben picked avenues (2026-10-03):** "i love avenues … but … more density … adding 4 lanes and removing some
empty space, specially what looks like sidewalk". Wave 3.1b: pavements 4 → 2 (walkers 4.5; a street band
is now 11, so pitch-28 blocks hold two 8-deep rows), four tiles-era lanes where they add lots, landmarks
brought to the street line, subway kiosks beside the (too narrow) pavement. Boulevard stays as a record.
Result: **85 lots** (50 on streets, 35 on four lanes; avenues at x −28/0/28, cross-town z −42), merged into
`m12-metropolis` (31d9d37); Ben has not judged the denser renders yet (`m12m_avenues_denser.png`).
`busStop`, `cityPark`, `rooftopGarden` and `conventionCenter` carry no district there, so the first three
cost no lots as city-changers; but a 2-stud pavement leaves no kerb room for shelters or street trees.

**Ben approved the 85-lot avenues on 2026-10-03** ("yeah, i love it") and answered the city-changer
recommendations with "lovely", read as: `rooftopGarden` → Green the Rooftops (prop swap) and `busStop` →
Open the Bus Line become street-only; `cityPark` stays a park (no street trees), `financeDistrict` stays
its tower (Crown twins dropped). Wave 3.2 (contract in INTERFACES) puts it in the game: client copies the
mirror-first rules, final props, then the asset run and `build/metropolis.rbxl` (`metropolis.project.json`,
DebugStartEra 3, GrantCash 1e18). He also said "commit everything": the earlier sessions' memory notes
are on `main` (2ed18af) and merged into `m12-metropolis`.

**Wave 3.2 state, 2026-10-04:** code, review and QA are done on `m12-metropolis` (b6891e8); **88 lots**
(52 street, 36 lane), Bus Line at no lot cost (5 shelters in ground no lot could use), 35 final props (18
towers incl. 7 Green twins; old town, crane sites, shelter, bus). Waiting on Ben: his OK on the final prop
sheets (`m12m_props/_contact_final_{towers,oldtown}.png`), then the asset run (merge, upload, **one harvest
paste**, templates, fabric rebuilt from harvested extents), then his Studio look in `build/metropolis.rbxl`.
Agents resume by id after a session limit or a restart (SendMessage "run git status and continue").

**Asset run done 2026-10-05** (`m12-metropolis` 18bdc0b): Ben approved the sheets ("looks good!", "upload
them"); 107/107 stages uploaded first try, harvest 107 loaded / 0 failed, 35 templates (444 in all), fabric
data unchanged on harvested sizes (88 lots), every gate green. **Waiting on Ben's Studio playtest** in
`C:\Users\benja\Desktop\tycoon-m12m\build\metropolis.rbxl` (never publish; fresh save starts in Metropolis
with $100ab), checklist in PLAYTEST "M12 wave 3". After sign-off: merge to `main`, remove the three
`tycoon-m12m*` worktrees (junctions first). Orbital (wave 4) only when Ben says so.
- Merge and upload only the new props with `--model` flags, so already-uploaded props are never touched.
- `upload_models.py` now shortens names over Open Cloud's 50 characters to an `ECT_` prefix.

Lessons from wave 3.2:
- **The review caught what renders could not:** five landmark footpaths ran onto the road (the client drops
  a last spur leg of `spurClip` or less), and buying the Supermarket shrank eight standing towers (a new,
  shorter governor). Both are now gates: `streetplan.py` (no footpath slab on a tile or pavement band) and
  `cityfabric.py timeline` (no standing building drops a stage or changes to a non-twin prop).
- **Low landmarks must not govern lots** bought after taller neighbours: give them no district.
- **2-stud pavements leave no kerb room**: shelters stand at the lot line in a `keepClear` gap (`spots`
  placer); street trees were dropped. Junction lamps are off (they fell inside landmarks).
- **`untilStage`** on a blueprint piece retires it after a stage: tower roofs leave when the next storeys
  cover them (stage-4 meshes 31% lighter, same look). Use it for any stacking prop.
- **`check_mirror.py --strict`** runs the real `CityFabric.luau` under a Luau CLI (fetched into `tools/bin/`)
  against the Python mirror; put new pure rules in `CityFabric.luau` so they are covered.
- The fabric is ~110k triangles on a full near plot before `untilStage` (2.5× Boomtown's plot); phone frame
  time is unmeasured. Far plots draw 60 of 88 lots until Ben's step-37 numbers arrive.

**Rulings taken by the lead for the mock** (the renders carried them; Ben approved the result):
- Block slabs dropped (a slab paved a whole block at its first purchase: a socket); every fabric prop
  carries its own paved forecourt. Street trees went with them → the `cityPark` changer proposal.
- Old town (generated `oldtown-kit`) is the wild: 13 × 13 clumps on a 14 grid, ≤ 3.6 tall; it may stand
  under the future highway and clears when `highwayRamp` is owned (mask adds the ring rects). No skirt.
- Tiles-era alleys = wave 2.4 lanes drawn exactly like a Metropolis spur footpath (flat Concrete Part,
  0.01 under the kerb, clipped at the pavement edge): the footpath look Ben approved in wave 2a, no bake.
- Mirror-first rules the client must copy in wave 3.2: `levelStages` [1, 3, 4] (five-stage towers grow
  floor by floor under the height cap), `siteVariants` (cranes on narrow/small sites), `swaps`
  (prop twins `…Green` / `…Crown`), the ring-rect mask, tiles-era alley drawing, `kerbside` layers.
- `LANDMARK_GAP` 0.25 (Boomtown's shipped carDealership/bank stand 0.30 apart).

**City-changer proposals** (renders `m12m_changers.png`, on avenues): busStop → Bus Line (no lot cost),
cityPark → Street Trees (−10 lots on avenues: the park governs a whole row), rooftopGarden → Green the
Rooftops (prop swap), financeDistrict → Finance crowns (prop swap, subtle) or stays OfficeTowerB.

**Why:** a fresh session would otherwise re-set a 100+ lot target for Metropolis or Orbital (same
lattice), re-litigate the slabs, or try to bake alleys in a tiles era.

**How to apply:** check `m12m_compare.png`, ask Ben for his pick and the four changer answers, then write
wave 3.2 contracts (client follows the mirror-first rules above; final props with strips; no uploads
until Ben approves). Orbital (wave 4) has the same 7-lattice and ring: run the density arithmetic first.
See [[growing-city-2026-09-28]], [[boomtown-growth-2026-10-01]], [[metropolis-streets-2026-09-22]].
