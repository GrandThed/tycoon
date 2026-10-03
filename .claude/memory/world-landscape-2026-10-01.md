Ben asked on 2026-10-01 what the environment outside the plots could look like ("low poly mountains,
rivers and such"). An offline mock was rendered and **Ben chose A, the Valley** the same day
("i love A valley"), judged on the renders as they stand (peaks estimated 270–290 studs, taller
than the brief). The lead's A + C mix (lake in the centre) was not taken.

**Milestone M13 "The Valley", started 2026-10-01** in the worktree
`C:\Users\benja\Desktop\tycoon-m13`, branch `m13-valley`, alongside the live Boomtown session.
Ben's rulings: start now; three steps, each one a Studio look (1 sky, haze, green ground, hub
and dirt roads from Parts only, no uploads; 2 mountains, foothills, forest and waterfall as a
generated kit with one harvest paste, invisible wall at the foothills; 3 river, lake, bridges);
step 2's upload waits until Boomtown's harvest is committed. **The river is shallow and
wade-through, with solid wooden bridges** — an agreed exception to the M9 no-collision rule,
and no swim or respawn rule.

**Wave 1 built 2026-10-02** (commits `7389467`, `1d5cfcc` on `m13-valley`; QA green; awaiting
Ben's Studio look, PLAYTEST "M13 wave 1"). Contract: `docs/INTERFACES.md` "M13 contracts".
- Server-built and static, unlike M9's client dressing: pure `src/shared/WorldPlan.luau` (ring
  maths, moved out of `PlotService.buildWorld`), `src/server/World/Landscape.luau` (not a
  service, not mounted in combat), `Config/World.json`. Without `World.json` the world is as before.
- `World.json` ships **haze only**: no `lighting` block and no `clouds`. Every look Ben approved
  was judged under default Lighting, so brightness and ambient are left alone until he asks; the
  mock's clouds are low-poly meshes (wave 2). The Atmosphere numbers are an unverified first
  guess (target about 20% haze at 500 studs), so expect one tuning round from his screenshots.
- Levels are frozen: plot and hub tops Y 0, ground top Y −1. `CityDressingController`
  `groundDrop`, `tools/cityfabric.py` and `plotrender.py` all assume it, and Village woods stand
  on the world ground up to 19 studs past the plot sides and back.
- Every gate is green, including `streetplan.py`, `bake.py --list` and `gen_templates.py --check`
  (run after the Boomtown session finished its pipeline, harvest `82b5d53` on `m12-boomtown`).
  From a worktree, give `streetplan.py --out-dir <scratch>`: by default it writes PNGs into the
  shared `assets/testfit/out` and would overwrite another session's pictures. Asset tools are
  free again; still announce the first M13 upload to that session.
- Wave 2 must rethink era aprons: in the second mock pass the dark Metropolis and Orbital base
  colour bleeding outward read as scorch marks. Mock numbers for waves 2–3 (river path, bridges,
  peaks 297.8 studs at r 675, foothills from r 362) are in `out/A2_numbers.json`.

**Ben's first Studio look at wave 1 (2026-10-02):** he sent one screenshot (green ground, roads,
haze all showing) with no complaint and said "we didnt do step A2 yet? do it". Taken as the go
for **the whole A2 Valley in one wave** (the old waves 2 and 3 together: mountains, forest,
waterfall, river, pond, lake, bridges, groves, aprons, clouds), so he pastes one harvest, not
two. He gave no haze letter and no formal sign-off of the wave 1 checklist.

**Wave 2 built 2026-10-02** (commits `3f2e863` … `e71987d` on `m13-valley`; review and QA green;
awaiting Ben's playtest, PLAYTEST "M13 wave 2"). Contract: INTERFACES "Wave 2 — the Valley meshes".
- **28 generated meshes, 131,768 triangles**, uploaded and harvested in one paste; Roblox kept
  every size. Open Cloud accepts 16,037 triangles and 1,444 studs in one mesh (largest before:
  12,044 and 61).
- **The floor is flat and collision is Parts only.** The river is a bed colour under a translucent
  sheet 0.35 above the ground (wade, never swim). The wall, bridge decks and wedge ramps and the
  stepping stones are invisible server Parts built from the generated `Config/Valley.json`. Trees,
  rocks and fences are walk-through. The plots keep their 1-stud kerb.
- **One generator is the source of truth:** `tools/world/valley.py` (pure `py`, deterministic,
  about 10 s) bakes the GLBs and writes `Valley.json`; Luau never recomputes the river or bridges.
  `valley.py check` is the QA gate. The world pipeline copies the baked-paths route
  (`upload_world.py`, harvest kinds `worldMesh`/`worldTexture`, `gen_templates.py --world` →
  `templates/_world/Valley/` → `ServerStorage.Assets.World.Valley`), not the props route.
- **Baked for 10 plots.** When `m11-unlocks` (6 plots) merges, re-bake and re-upload: one more
  harvest paste. `planHash` ties `Valley.json` to the uploaded meshes (server and QA both check);
  `World.json` `ground`, `hub`, `roads` and `valley.wall.segments` are in the hash, so changing
  them costs a re-bake and a paste. Haze, lighting, apron colours and wall height are config-only.
- **Aprons** are two flat untextured bands per plot that the server tints by `EraName`
  (`World.json valley.aprons`), in light gravel; the dark base colour bleeding out was rejected.
- The client hides skirt entries in the river (`WorldBlock`, hooked into `Fabric.syncWild`), only
  once `Workspace.Landscape.Valley` exists. Not mirrored in `cityfabric.py`/`plotrender.py`.
- Per-face palette colour cannot blend: the first meadow mosaic read as a busy pattern and its
  contrast was halved before upload. Fix looks before uploading; each re-bake costs Ben a paste.
- Hazards: an `assets_config.py` without this branch's change erases the `world` block from
  `Assets.json` on its next save (merge it first); `assets/build/world` is shared by every
  worktree, so a build that is not the one being uploaded needs `--out-root`.
- Never answered: whether far meshes are culled at low graphics quality, how the water sheet
  renders, flicker between the flat layers on a phone, and the haze over the peaks.

**Approved and merged 2026-10-02.** Ben's verdict on the Valley in Studio: "approved!", with no
checklist letters or screenshots, so the questions above stay open; ask before a public launch
rather than assuming they passed. `main` was merged into `m13-valley` first (the p3 load fix and
the new `check_compile.py` gate, which the Valley code passes), then `main` fast-forwarded to
`0f4258d`. Asked afterwards, Ben said "yes, everything looks good"; the worktree `tycoon-m13`
and the branch `m13-valley` were then removed (2026-10-02), so M13 work continues on `main` or a
new worktree. `docs/MANUAL_STEPS.md` and `docs/PLAYTEST.md` "M13" still tell him to open
`tycoon-m13\build\test.rbxl`: the build is now `tycoon\build\test.rbxl`. Still owed: the 6-plot re-bake
when `m11-unlocks` merges, and the wave 1 follow-ups (plotrender's ground colour, SHOTLIST's
lighting note). `m12-boomtown` merges `main` next; the notes for that merge were sent to its
session and are in INTERFACES "Review rulings" under wave 2.

**Mock:** `assets/research/2026-10-01-worldmock/` (gitignored): `wm_plots.py`, `wm_world.py`,
`wm_land.py`, `wm_concepts.py`, `wm_post.py`; sheets in `out/sheet_{plot,aerial,hub,back}.png`.
It places ten real plotrender plots on the ring and generates the landscape from `plotCount`
(a 6-plot render proves it follows M11's ring). The ring cache lives in a session scratchpad
(`SCRATCH` in `wm_common.py`); the first run rebuilds it in about 8 minutes.

**Three candidates:** A Valley (mountain ring, waterfall, river through two plot gaps, lake),
B Island (sea, volcano, lighthouse), C Lake (the dead centre becomes a lake, hub on an island,
causeways, shore promenade, docks). The lead's read: A wins the outward view (town with peaks
behind), C wins the inward view (lakefront toward the hub), B is weak from player height. The
lead recommended A's backdrop plus C's lake.

**Facts found:**
- Ring radius is about 277 studs at 10 plots (184 at 6). Plot inner edges are at r 217, so
  **187 studs of empty grey ground** lie between the hub and the plots; that dead centre, not the
  horizon, is most of what a player sees looking inward.
- No code sets Lighting, Atmosphere or a Sky: the game runs on Roblox defaults.
- The gap between neighbouring plots is 20 studs at the inner corners and about 94 at the outer.
- A landscape of 15 meshes came to 73k–111k triangles, each mesh under 20k.
- Anything players walk on (bridges, causeways) must collide, which the M9 "no collisions on any
  connective part" rule forbids as written; water players can step into needs a rule too. Both
  are open design points for a contract.
- `plotscene.py` on `main` still lacks the sRGB decode (it is on `m12-boomtown`); the mock decodes
  in its own script.

**Why:** a fresh session would otherwise re-run the mock or miss that the centre is the weak spot.

**How to apply:** build the Valley, never re-open B or C or a deep river. Read the INTERFACES
"M13 contracts" section first. The Boomtown session is live, so the upload and harvest
announce-and-ack protocol applies. World geometry is static, built once, generated from
`plotCount`. See
[[growing-city-2026-09-28]], [[city-dressing-2026-09-16]], [[boomtown-growth-2026-10-01]].
