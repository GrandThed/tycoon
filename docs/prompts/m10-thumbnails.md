# Next-session prompt: M10 thumbnails + icon

Paste everything below the line into a fresh Claude Code session at the repo root. Run the
session on Opus; every subagent that composes or judges images runs on Opus too.

---

Start **M10 — Thumbnails and icon** (the store-art half of M10; the like-prompt is a separate
task). Produce the experience thumbnails and the icon described in
`docs/DISCOVERY_CHECKLIST.md` §1–§3 from the game's **real assets**, so that Roblox's
"metadata must match the game" rule is satisfied and Ben can approve them without Studio.
No stock art, no AI-generated imagery, no kit pieces the game does not ship.

Read, in this order, before delegating anything:

1. `CLAUDE.md` (project rules and memory imports, especially `assets-direction-2026-09-15.md`,
   `era-kits-2026-09-16.md`, `city-dressing-2026-09-16.md`).
2. `docs/DISCOVERY_CHECKLIST.md` §1, §2, §3 and "Penalties to avoid" — the deliverable spec.
3. `tools/testfit/README.md` in full (Blender path, render orientation, kit facts, colour caveats).
4. `tools/testfit/testfit.py` and `tools/testfit/strip.py` (the existing Blender renderer and
   the Pillow compositor you will extend, not replace).
5. `src/shared/Layouts/Village.luau` and `src/shared/Layouts/Boomtown.luau` (slot positions,
   streets, lots, plazas, tree zones) and `tools/streetplan.py` (how the Lua layout is parsed
   from Python — reuse its parser).
6. `docs/ASSET_MANIFEST.md` (which slots and props exist as templates per era).

Facts that bound the work:

- Only **Village** and **Boomtown** have shipped blueprints and templates. Metropolis exists as
  drafts in `tools/testfit/blueprints/_drafts/`; Orbital Colony has nothing. The "eras" beat is
  Village vs Boomtown now; leave a documented re-render step for Metropolis.
- Combat (C0) has not shipped. The combat beat is deferred; deliver four thumbnails now, the
  fifth when C0 has a playable fight. Thumbnail personalization needs 2–5, so four is enough.
- Buildings are one merged mesh per stage at scale 4; growth stages are `[10, 25, 50, 100]`
  levels, i.e. stage 0–4. Roads are plain Parts on the client; Village paths are baked meshes.
  A Blender render composes the same GLB pieces the templates were merged from, so it is an
  honest picture of the game.
- Avatars cannot be rendered by the Blender pipeline. Any beat that needs players (social,
  later combat) is captured in Studio by Ben with a camera script the session provides, then
  composited here.

## Environment (verify first, ~1 minute)

```
$env:PATH = "$HOME\.rokit\bin;$env:PATH"      # PowerShell; Bash: export PATH="$HOME/.rokit/bin:$PATH"
py -V                                          # only `py` works; `python`/`python3` are Store stubs
Test-Path "C:\Program Files\Blender Foundation\Blender 5.2\blender.exe"
py -c "import PIL; print(PIL.__version__)"
git ls-files --eol | Select-String w/crlf       # must be empty; files the Write tool creates are CRLF — convert to LF
```

Put the PATH line and `py` in every subagent prompt. Blender's bundled Python has no Pillow;
render in Blender, composite under `py`, exactly as `testfit.py` and `strip.py` split it today.

## Deliverables

Working renders go under `assets/thumbs/` (already ignored: `.gitignore` ignores all of
`/assets/`). Tooling and the final approved files are committed; the approved files live under
`assets/store/`, which needs a `!/assets/store/` negation added to `.gitignore`:

| File | Size | Notes |
|---|---|---|
| `assets/store/icon.png` | 512×512 | one landmark building, saturated sky, readable at 64 px |
| `assets/store/thumb_01_growth.png` | 1920×1080 | the same building at stage 0 and stage 4 side by side |
| `assets/store/thumb_02_eras.png` | 1920×1080 | Village plot left, Boomtown plot right, era names on top |
| `assets/store/thumb_03_scale.png` | 1920×1080 | full Boomtown plot, every slot stage 4, roads, trees, vehicles, lamps |
| `assets/store/thumb_04_social.png` | 1920×1080 | Studio capture: two avatars on a plot, composited here |
| `assets/store/thumb_05_combat.png` | 1920×1080 | **deferred to after C0**; keep the slot in the compositor |
| `assets/thumbs/contact.png` | any | all of the above on one sheet, plus the icon at 512, 150 and 64 px |

Every thumbnail: 16:9, under 3 MB, PNG, bottom 15% free of anything that matters (the tile
overlay covers it), text of at most four words, one typeface across the set, the same sky and
light across the set so they read as one game. No prices, no "free", no "Robux", no arrows,
no fake UI.

## Tooling to build (new folder `tools/thumbs/`)

1. **`scene.py`** (runs inside Blender, like `testfit.py`): renders a *whole plot*, not one
   building. Inputs: `--era`, `--stage <n | per-slot json>`, `--camera <preset>`,
   `--size 3840x2160`, `--out`. It parses the era layout with the `streetplan.py` parser, places
   every slot's blueprint at the requested stage using `blueprint.py`'s loader (so anything that
   renders in testfit renders here), lays roads as flat dark planes along the layout streets
   (Village: the baked path meshes if `tools/paths/` can emit OBJ cheaply, otherwise a
   pebble-coloured ribbon), scatters `TreeGrowing` stage 3 in the tree zones, `HouseA–D` on
   lots, `PlazaA` on plazas, `VehicleA–C` on Boomtown streets, `LampPost` at junctions. Ground:
   the plot's grass colour from `CityDressing.json`, a gradient sky, one warm key light plus soft
   fill, no hard black shadows. Camera presets: `hero` (three-quarter, slightly above, 35 mm),
   `wide` (higher, 24 mm, whole plot), `duo` (two plots side by side with a gap). Render at 4K;
   the compositor downsamples.
2. **`compose.py`** (system `py`, Pillow): takes rendered PNGs and a small JSON per thumbnail
   (layers, crops, text, position, font size) and emits the 1920×1080 files, the icon crops and
   `contact.png`. Text uses one OFL typeface committed under `tools/thumbs/fonts/` with its
   licence file. Adds a subtle top-edge darkening so white text reads; never touches the bottom
   15%. Enforces the 3 MB limit and warns if any text box enters the safe zone.
3. **`capture.luau`**: a Studio command-bar script for Ben. It disables CoreGui and every
   ScreenGui, sets `Lighting` to the same time of day and colour as the Blender sky, moves the
   camera to a given plot's `hero` CFrame and FOV, and prints the exact CFrame so the composited
   scene matches the render. Ben uses Studio's screenshot at 4K (MANUAL_STEPS documents the
   Studio setting). The `GrantCash` Workspace attribute is the lever to fill a plot to stage 4.
4. **`README.md`** in `tools/thumbs/` with the three commands and the re-render steps for
   Metropolis, Orbital Colony and the combat beat.

## Waves

**Wave 1 — fan out in one message, disjoint files**

1. **pipeline-engineer** (`general-purpose`, `model: "opus"`) — `tools/thumbs/scene.py`,
   `tools/thumbs/compose.py`, `tools/thumbs/README.md`, the `!/assets/store/` negation in
   `.gitignore`. Definition of done: `scene.py --era Boomtown --stage 4 --camera wide`
   renders the whole plot with props in under five minutes on this machine; `compose.py`
   produces a 1920×1080 PNG under 3 MB from it and a contact sheet; both commands in the README
   run as written.
2. **studio-capture author** (`general-purpose`) — `tools/thumbs/capture.luau` and the
   `MANUAL_STEPS.md` M10 section (Studio 4K screenshot setting, `GrantCash` to fill a plot, a
   second account or a friend for the social beat, where to save the capture). Must not touch
   any file under `src/`.

**Wave 2 — after wave 1 passes, one agent**

3. **thumb-artist** (`general-purpose`, `model: "opus"`) — owns the per-thumbnail JSON in
   `tools/thumbs/shots/*.json` and the art direction. Renders every beat, looks at every output
   (Read the PNG), iterates camera, stage mix, text size and colour until each thumbnail passes
   this checklist: subject obvious at 300 px wide, text legible at 300 px, nothing important in
   the bottom 15%, sky and light consistent across the set, no cyan `stone_*` pieces, no red
   footprint frame, no clipped geometry at the crop edges. Picks the icon subject from the tall
   Boomtown landmarks (Clock Tower 25.8 studs, Radio Station, Fire Station) or Village's
   Castle Keep / Windmill, renders it at `hero`, crops square, checks it at 64 px. Emits
   `assets/thumbs/contact.png`. Reserves `thumb_04_social.json` with a placeholder layer that
   `compose.py` fills from Ben's Studio capture path.

Do not run the roblox-reviewer on Python tooling. Run **qa-runner** only for `stylua --check`
and `selene` on `capture.luau` and `rojo build -o build/test.rbxl` (the Lua file lives outside
`src/`, so the build must be unaffected). It MUST end with the report.

## After wave 2

1. Show Ben `assets/thumbs/contact.png` and stop for his verdict. Iterate the thumb-artist on
   his notes (SendMessage, keep its context) until he approves each beat.
2. Copy approved files to `assets/store/` and commit tooling, shot JSONs and the approved PNGs.
3. **docs-keeper**: `MANUAL_STEPS.md` M10 — upload the icon and thumbnails in Creator Hub in
   the order of the table above, enable thumbnail personalization, then walk
   `docs/DISCOVERY_CHECKLIST.md` §4–§12 (name, description, genre, maturity, devices);
   `PLAN.md` M10 ticks; `PLAYTEST.md` gets no new section (nothing changes in game).
4. Add a memory file `.claude/memory/thumbnails-<date>.md` with what Ben approved or rejected
   about the look (camera, text, colour), so the Metropolis and combat re-renders match.

Stop after the hand-off. The like-prompt (first Advance Era) and the Metropolis, Orbital and
combat thumbnails are separate tasks that start only when Ben says so.

## Report to Ben at the end, in a few lines

Which four thumbnails and the icon are in `assets/store/`, what he must capture in Studio for
the social beat and the exact command to composite it, and the Creator Hub upload order.
