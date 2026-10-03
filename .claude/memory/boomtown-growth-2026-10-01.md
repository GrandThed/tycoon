M12 wave 2 (Boomtown growing city), session of 2026-10-01. Contract: `docs/INTERFACES.md`
"M12 wave 2 — Boomtown". Built in the worktree `C:\Users\benja\Desktop\tycoon-m12`, branch
`m12-boomtown` (the old `m12-growing-city` worktree and branch were merged and removed).

**Ben's rulings at the mock gate (2026-10-01):**
1. **Organic** ("organic looks better"), with the bolder pass (landmarks turn to face streets).
2. **All four** of `fireHydrant`, `billboardSign`, `neonDistrict`, `busLine` "stop being a sole
   building": street-only city-changers driving upgrade layers (hydrants, billboards, neon signs
   on shops, bus stops plus buses in the traffic through `vehicles.unlocks`).
3. **Roads stay 6 studs wide** ("i prefer 6 studs wide").
4. **Yes** to chimneys from stage 0 on the three narrow Village homes.
5. Still owed: his numbers from PLAYTEST M12 step 37 (instance count, frame time).

Wave 2.2 (contract in INTERFACES "Wave 2.2") follows from those: the bolder organic layout,
the five Boomtown layers (parked cars come back as a layer gated on `gasStation`), 3-stud
driveways (`road.paths.spurWidth`), and final props with strips for Ben before any upload.

**State at the second gate (same day):** the bolder organic layout is merged into
`m12-boomtown`: 102 lots (23 terraced shops), houses by tier 11 / 36 / 66 / 89 / 102, layers at
full build 22 hydrants, 26 neon, 10 billboards, 4 bus shelters, 14 parked cars. 46 final prop
blueprints (three generated kits: `farmland`, `boomtown_extras`, `boomtown_street`), none
uploaded. Review 0 Critical, QA green. Ben must approve `m12c_*` renders and
`assets/testfit/out/Boomtown/strips/` before the pipeline run (re-bake 38 path pieces, merge and
upload props for Boomtown and the three Village narrow homes, **one harvest paste**, templates,
rebuild `Fabric/Boomtown.json` from harvested extents). The run's steps are in MANUAL_STEPS M12.

**State 2026-10-02: built, uploaded, harvested, awaiting Ben's Studio playtest.** At that gate
Ben said "i love everything else" and asked for one thing: houses in block interiors were "not
connected to any road". Wave 2.4 added **back lanes** (8 lanes, 330 studs; every back lot fronts
one; drawn by `Fabric.luau` as Parts on the street's surface, growing with the lots). Cost:
102 → **75 lots**. Ben on the lanes render: "the houses look fantastic!". The asset run is done
(76 path meshes, 80 prop stages, one harvest paste, templates; `bake.py --list` exits 0 for both
eras). Ben opens `C:\Users\benja\Desktop\tycoon-m12\build\boomtown.rbxl` (never publish it): the
`DebugStartEra` lever starts a fresh save in Boomtown with 1e14 cash baked in. Checklist:
PLAYTEST "M12 wave 2 — Boomtown growing city". After sign-off: merge `m12-boomtown` to `main`,
then Metropolis. Open: Ben's step-37 numbers (far plots draw 45 of 85 fields), the civic greens
never draw (no lot's nearest landmark is the Clock Tower or Fire Station), lanes arrive whole in
one purchase, density (two pockets need landmarks moved: a re-bake and a second paste).

**Ben's first Studio look (2026-10-02): the lanes flickered.** Wave 2.4 drew lanes as a rim
Part under a fill Part with `Texture` instances; at a distance they z-fight ("a texture above
each other... if you get close enough it renders it well"). This repeated the M9 wave 1c failure
that [[city-dressing-2026-09-16]] already records. Wave 2.5 bakes each lane as a path piece
`LN_<k>` (16 meshes, one more short harvest paste). **Any ground surface a player sees from the
tycoon camera is a baked planar-UV mesh, never stacked Parts.**

**Ben signed off Boomtown 2026-10-02** after the baked lanes: "looks really good! lets send it".
**Merged the same day: `main` is at 86d1d99** (Boomtown plus M13 Valley, the p3 load fix and the
compile gate; every gate green). The three M12 worktrees are removed and `m12-boomtown` is
deleted; `m12-boomtown-grid` and `m12-boomtown-organic` are kept as the record of the candidates.
Not pushed (Ben was asked). The Boomtown debug build is `build/boomtown.rbxl` in the main
checkout. His sign-off was a Studio look, not the 60-step checklist: phone, low graphics, two
players and the step-37 measurement are unreported. **Next: Metropolis** (a lattice layout study
comes first, CITY_GROWTH §3), in a new session and a new worktree.

**Another session's uncommitted work in the main checkout blocks a fast-forward** when it
touches the same files. Ask that session to park its work (it kept a patch outside the repo);
never stash or overwrite it.

**Merging two long-running branches:** both appended sections to the same docs. Resolve with
`git checkout --conflict=diff3` and keep ours plus what theirs added to the base; a plain union
would repeat stale base lines. Regenerate `sourcemap*.json`, `build/*.rbxl`, `harvest.luau` and
`boomtown.project.json` (a copy of `default.project.json` plus two Workspace attributes).

**Lessons from the lanes and the asset run:**
- A lane lot costs frontage plus half a lane: fronting every house on a road took a quarter of
  the lots. Tell Ben the count next to the render; he chose roads over density.
- `laneAlong` added to the pull distance needs a plot-wide radius (120), or lanes stay empty.
- A `Texture` on a Part cannot be turned: lay axis-aligned lane legs unturned so they tile with
  the baked streets. Roblox's face-UV conventions were never verified outside Studio.
- No lane can exist on gravel: the first lane needs purchase 7 and Pave Main Street is purchase 6.
- A baked-in Workspace lever must survive a tick with no player loaded (`GrantCash` now does).
- The session limit kills subagents mid-task; `SendMessage` "run git status and continue"
  resumed both with nothing lost.

**More facts from wave 2.2:**
- Lawns, pasture and cottonwoods use an off-colormap leaf green (112, 168, 88) / (134, 186, 100) /
  (86, 146, 76): the City Kits only have one mint-to-teal ramp, which fought the green roofs.
- `fabric.marker.offset` 5.3 is what lets a landmark turn to any angle; it costs about a stud of
  frontage per landmark. Narrow driveways fix the look, not the lot count.
- Every curving close cost 6 to 13 lots; the shipped plan has none.
- Mixed vehicle lengths need lane holds that count both vehicles (a bus rode into cars).
- A `check` rule can be vacuous: prove each new rule by mutating the data (two were found dead).
- Two other Claude sessions were open in the main checkout that day (one mocking the world
  landscape outside the plots). Announce before any upload or harvest.

**Candidates at the first gate** (each a real layout through the real generator, on its own branch):
- `tycoon-m12-grid`, branch `m12-boomtown-grid` (452059d): 93 lots. It also carries two generator
  options to port if it wins: `parcels.infill.frontReach` and `parcels.terraceFill`.
- `tycoon-m12-organic`, branch `m12-boomtown-organic` (0fd20be): 101 lots. It reads as a kinked
  grid, because `fabric.marker.offset` 4.1 only clears a pad within 3.5° of a compass axis, so no
  landmark could turn to face an angled street. Offset 5.3 allows any angle.
- Renders: `assets/testfit/out/Boomtown/m12b_compare.png` and `m12b_{grid,organic,today}_*.png`.

**Facts found:**
- **Frontage binds harder on Boomtown than on Village.** With 8-stud roads and 9 × 9 house lots a
  plot held 55 to 70 lots. What got it past 90: road width 6, small 6 × 6 house lots (fabric homes
  at kit scale 2.8 against the landmarks' 4), terraced 5 × 8 shop lots, landmarks at both ends of
  every cross street, and gaps between landmarks cut to whole lots.
- **City Kit storeys are low** (1.6 studs at scale 4). The first shop drafts at 3.5-stud storeys
  towered over the Barber Shop. Give builders heights measured from the era's landmarks, never
  Village's height bands. Shops are now 2.25 / 3.3 / 4.45 studs.
- **The plot renderer drew flat colours too pale until this session.** `plotscene.py` wrote 0–255
  values straight into a linear colour, so Boomtown's base (173, 138, 93) came out (214, 198, 171).
  Fixed by decoding once where the scene file is read. Every plot render made before 2026-10-01
  shows paler ground than Studio, in every era, including the ones Ben approved.
- **Village smoke shows late.** Most fabric homes gain a chimney only at their last stage, and 11
  of the 13 plumes on a full Village need the Well at stage 3 (level 50), because its height caps
  the houses around it. Chimneys from stage 0 on the narrow homes fix that; `ambient.smoke.every`
  must go to 7 in the same commit (`budget.plumes` 20 is a tools gate that enforces it).
- **Carts are an upgrade layer** switched on by `farmPlot`: no client code. An always-on dressing
  kind fits the generic layers by naming an early slot.
- **A farmland field is a fabric clump:** four fenced 6 × 6 quarter-fields, grid pitch 13.3,
  quarter turns only, scale 1. `Windbreak` is skirt-only (one clearing point cannot cover three
  trunks).
- **Path-limited checkout beats merge for feeding candidate worktrees:**
  `git -C <candidate> checkout m12-boomtown -- <paths>` works while the candidate has uncommitted
  edits; a merge that touches a file the candidate edited is refused.
- `git worktree remove` on a worktree with an `assets` junction: remove the junction first
  (`cmd /c rmdir <worktree>\assets`), so nothing can follow it into the shared folder.
- Subagents share one session scratchpad; two designers overwrote each other's `frontage.py`.
  Give each agent its own scratch subfolder.

**Branch caveat.** `m12-boomtown` has Boomtown `road.width` 6 ahead of the re-bake, so Boomtown
looks wrong in Studio there (meshes are still 8 wide) and `bake.py --era Boomtown --list` is red.
Village is fine. The branch merges only after wave 2.2's re-bake; the Village fix (commits up to
6573b0c plus a6cf170's client fixes) can be cherry-picked to `main` alone.

**Weak points both candidates share, for wave 2.2:** road-wide landmark driveways read as a comb
(a narrower driveway needs RoadGraph, bake and mirror changes); the industrial lots sit in the
foreground as rows of dark sheds; no civic green by the Clock Tower; blank shop side walls; when
the layout drops `lots` and `parking`, Boomtown loses lot smoke and parked cars as Village did.

**Why:** a fresh session would otherwise re-run the mock, re-derive the density levers, or judge
Boomtown in Studio on a branch whose roads are mid-change.

**How to apply:** read the INTERFACES section first, then ask Ben for the five decisions before
any contract. See [[growing-city-2026-09-28]], [[era-kits-2026-09-16]],
[[street-upgrades-2026-09-18]], [[template-turn-2026-09-22]].
