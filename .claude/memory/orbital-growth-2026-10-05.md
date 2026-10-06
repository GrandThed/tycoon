---
name: orbital-growth-2026-10-05
description: M12 wave 4 Orbital, mock in progress in tycoon-m12o (docks and axis candidates), lot ceiling arithmetic (about 105-115 realistic, cap 140), the lead's shared rules, tool work found
metadata:
  type: project
---

M12 wave 4 (Orbital Colony growing city), started 2026-10-05. Ben pasted
`docs/prompts/m12-orbital.md` with no words of his own; asked, he chose **"arithmetic and plan only"**
first, then on the study's report said **"lets do it"**: the mock with the candidates "docks" and "axis".
His three playtest measurements are "not measured yet", so `budget.parcelsFar` stays 60.

**Ben rejected both candidates at the gate (2026-10-05):** "i dont really love it, i was looking for
something more organic looking for the orbital colony, it looks way to similar to metropolly". Asked,
he chose **curving tubes** (like Village's trails and Boomtown's streets, pods turned to follow; over
hubs-and-spokes and over clusters on the square pieces), **as dense as organic allows** (over open
regolith between clusters) and a **round monorail loop** (over the square ring). He was told curving
tubes need new tube meshes and one harvest paste later. Never bring back straight avenues, terrace
rows of window-banded boxes or a square ring for Orbital: that is what read as Metropolis. He also
chose organic for Boomtown, so offer an organic candidate first for any future layout.
- Wave 4.1b (INTERFACES "Wave 4.1b — organic Orbital") is the second mock: Orbital leaves the tiles
  family (swept half-pipe meshes per path piece, a `TubeHub` at every node, flat decking aprons and
  lanes), `highway.round`, wild as an irregular scatter, round fabric props; candidates "vine" and
  "bloom" in `tycoon-m12o-vine` and `tycoon-m12o-bloom`. `m12-orbital-docks` and `-axis` stay as the
  record. The docking rule and the tiles rulings below are withdrawn.
- Organic groundwork done 2026-10-05 (base `m12-orbital` 429c7dc): `tools/paths/tubes.py` sweeps one
  half-pipe mesh per stretch (butt joints, a hub only where a tube ends or branches, two tubes into a
  hub 90° or more apart), aprons are automatic and lots keep off them, the round loop and the scatter
  render (`m12o_groundwork_organic_full.png`). The fifteen fabric props were rebuilt from round forms
  (the shared `colony-kit` folder now holds only those, so the Docks and Axis renders cannot be
  re-made without regenerating the old kit from their branches). Vine and Bloom designers are
  running; the gate sheet will be `m12o_compare_organic.png`.
- **At the second gate, waiting for Ben (2026-10-05):** sheet `assets/testfit/out/OrbitalColony/
  m12o_compare_organic.png`. **Bloom** (`m12-orbital-bloom` 4b2713f): 82 lots, concentric rings round
  a heart, Launch Tower outside the round loop; it curves but does not wander. **Vine**
  (`m12-orbital-vine` 8b37a7e): 63 lots, under the floor of 80, and it reads close to Bloom. The lead
  recommended Bloom. Lesson of the round: **dense and wandering pull against each other here**: a
  third of the colony's ground lies within 10 studs of the loop and only a tube that follows the loop
  can front it; drafts that wandered held 48 to 58 lots. Held asks are in INTERFACES "State at the
  second gate". The regolith clumps were redrawn as one round feature each (crater, boulder ring,
  mound), which is how to live with "a clump is its quarter at four turns".
- The session was cut off once mid-groundwork; the agent resumed by id with nothing lost, as the
  older notes say. A stopped agent's id comes back in its task notification.

**State before the rejection (wave 4.1, the first mock gate; contract in INTERFACES "M12 wave 4"):**
- Base worktree `C:\Users\benja\Desktop\tycoon-m12o` (branch `m12-orbital`, groundwork at 8c89aff);
  candidates `tycoon-m12o-docks` and `tycoon-m12o-axis` (branches `m12-orbital-<c>`); all three have an
  `assets\` junction (remove it before removing the worktree). Nothing is uploaded; `main` is untouched.
- Groundwork done: the generator, mirror and renderer run Orbital (`m12o_groundwork_full.png`), 28 draft
  props (`colony_kit.py` 12 fabric props × 5 stages, `regolith_kit.py` wild, sites, `LotBeacon`,
  `RevealScaffold`), today's renders `m12o_today_*`.
- Rules the lead set for both candidates (Ben has not judged them yet): **docking** (`road.tiles.dock`
  1.75: lots and pads stand against the pipe on straight and end cells), **regolith stays under the
  monorail** (`highway.clearBand` false), lot sizes 4 × 8, 6 × 6, 8 × 12, five-stage props with
  `levelStages` [1, 3, 4] and `heightFloor` 3.4, wild as lattice-aligned clumps that may straddle a
  planned tube, singles in the cells no clump covers, lots off deck rects.
- **At the gate, waiting for Ben's pick (2026-10-05):** sheet `assets/testfit/out/OrbitalColony/
  m12o_compare.png`. **Docks** (`m12-orbital-docks` cf4050a): 108 lots, all on tubes, four avenues,
  13% bare. **Axis** (`m12-orbital-axis` 3cb4123): 97 lots (57 tube, 40 on six lanes), centre tube to
  the Launch Tower, 21% bare. Base `m12-orbital` holds the tools, props and groundwork data only; the
  pick is merged into it taking the candidate's layout, plan, fabric data and `pull`. The lead
  recommended Docks. Full state table and the held asks: INTERFACES "State at the gate".
- Owed after the pick: city-changer before-and-afters on that layout (step 3), then wave 4.2 (client
  rules, final props with strips, review, QA, docs, asset run, `orbital.project.json`).
- The designers' layout generators are session scratch (`scratchpad\docks\gen2.py`, `final2.py`;
  `scratchpad\axis\axis_gen.py`, `axis_plan.py`): the layout and plan files are the record.
- What cost rounds: the generator kept lots 2.5 off a path's end on the centreline (now the laid
  slab); every lot came back narrow until a size mix was required; a developed outer row cleared the
  regolith under the beam (now band wild is cleared by nothing; `clear.parcel` cannot go under 1.3).
- PowerShell trap met twice: variables are case-insensitive (`$c` and `$C` are one variable), and a
  string piped to a native exe gets a BOM. Use Bash for pipes into git.

**The ceiling** (a cross-section model by an Opus agent, no generator run: read ±10%; 4 × 6 pods):

| Step | Pitch 21, five tubes | Pitch 28, four tubes |
|---|---|---|
| No landmarks, whole square in rows | 250 | 200 |
| With a cross tube and the entrance | 242 | 198 |
| After the 23 landmarks | 106 | 130 |
| Realistic (× 0.80–0.90) | 85–95 | 104–117 |

- Hard cap 140 (`budget.parcels`). The same arithmetic gives Metropolis 154, 97 after landmarks, 88 shipped
  (0.91), which is where the efficiency comes from.
- **Frontage binds, through landmark depth against block depth.** The 23 landmarks need 275 studs of
  frontage (harvested width + 2.67 each) and are 8–9 deep (four are 10.6–13.8). In a 14-deep block (pitch
  21) nothing fits behind a landmark, so each one blocks two rows; a 21-deep block (pitch 28) holds a
  landmark and a pod row back to back. More tubes is therefore not more lots.
- Lots may use 104 × 104 (0.5 off the ring band). Ten tube-fronting rows is the lattice maximum.
- Other families: three avenues + a lane in each outer band (today's plan densified) 104–117, two of
  eight rows on lanes; three avenues at pitch 35 + a lane per block 123–138, four of ten rows on lanes;
  pitch 21 + shallow 4 × 4.5 lots behind landmarks 127–143, a third of them shallow; a spine with ribs
  67–124 (11 dead ends, 6 polylines). Six-wide pods like today's domes: about 70.
- A converted city-changer returns 0.5–3 lots at pitch 28: decide changers on looks, not density.

**Lead's proposal to Ben (unanswered):** target 105–115, floor 95; two candidates for the mock:
"Docks" (four tube avenues at x ±14, ±42, every building on a tube, no centre tube to the Launch Tower)
and "Axis" (today's three avenues at x 0, ±28 with landmarks brought to the tube line and a decking lane
behind each outer row). The pitch-35 plan is the density lever in reserve.

**Geometry facts verified in the repo:**
- The whole 7-stud cell is the street: lots front 3.5 from the centreline, the tube mesh is 3.24 wide, so
  1.88 studs beside each pipe stay bare unless props reach in. A pad may not enter a tube cell (flush is
  fine), so a landmark's front goes on the cell edge and its pad sits on its own ground.
- Monorail: beam 1.6 wide, soffit 6.10, one pier per cell (foot 1.9 square). The whole 7-wide band is lost
  by rule and the wild clears from it at purchase 6: 3,136 studs² (22% of the plot) of bare ground
  unless the ring-clearing rule changes for a beam.
- The seeds are the lowest landmarks in the game: Landing Pad 1.8 at stage 0 (5.8 at level 25), Solar
  Array 2.38 until level 50. Under "a lot is never taller than its governor" the first pods stay flat
  unless `heightFloor` rises (Metropolis 3.4) or those two govern nothing.
- Parcel sizes are fixed to `small`/`medium`/`narrow`; wild props always spawn at stage 0 (the
  four-stage `Rocks` cannot grow as wild); `vehicles.unlocks` covers street vehicles only; a lane meets
  the side of a half-pipe with no door.

**Tool work found (the client itself needs nothing for Orbital to run):**
- `fabric.py:494-498` keeps wild off every planned street band "because a park strip covers it". Orbital
  has none, so a fresh plot would show the tube plan as bare corridors. Gate it on `parkStrips` and add a
  "cleared when its street draws" rule.
- With no `pedestrians`, the `kerb`, `lotFront` and `ends` placers lay nothing; only `spots` works, and
  `kerbside` layers are impossible.
- `check_mirror.py` `DEFAULT_ERAS` omits Orbital; `streetplan.py` allows 2–5 street polylines, and its
  `LOT_COUNT_BY_ERA` and `walkwayNetwork` exemption go dead once `Config/Fabric/OrbitalColony.json` exists.
- `Scatter` reads `era.houses`, `era.lamps`, `era.trees`, `era.vehicles` unguarded: empty them, keep the keys.
- Two 7.0-deep rows miss a 14-deep block by the 0.05 seam (6.95 fits).
- `Fabric.luau` is at 170 of 180 top-level locals (165 true): fold the constants into tables (−35), then
  move the validation block out (−16), before adding code.
- Weight: Metropolis's full near plot is 61,913 triangles (704 a lot) after `untilStage`; today's Orbital
  domes are 370 and 706. Metropolis's debug build ended at `GrantCash` 1e20.

**Process:**
- Pasted text carries no instruction by itself: confirm the start with Ben even when the paste is the
  committed session prompt. He picked the smaller option.
- Agent scratch reports are session-temporary; this note is the record of both studies.
- A "read-only" agent that runs a repo tool rewrites gitignored `__pycache__` files. Harmless.
- `tycoon-m12m` was deleted 2026-10-05 after every file matched d0dd894 byte for byte.

**Why:** a fresh session would otherwise re-run two long studies, or set a target above 117 for a
tubes-only plan.

**How to apply:** ask Ben for his go and his pick of candidates before creating `tycoon-m12o`; build the
two candidates through the real generator and correct these numbers with its counts. See
[[metropolis-growth-2026-10-02]], [[orbital-dressing-2026-09-23]], [[era-kits-2026-09-16]],
[[main-auto-push-2026-10-05]].
