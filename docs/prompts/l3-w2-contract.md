# L3 Wave 2 contract — the models in the game (draft for the lead, 2026-10-20)

Branch `l3-w2` in `C:\Users\benja\Desktop\tycoon-p5` (from `main` at 0fb03be, where W1 is merged). Ben's decisions are in
`docs/MISSIONS_DESIGN.md` §24 (the 15 models approved, one look each, dressed by their level) and its last paragraph
(*"lets do wave 2, i will test later"*: his look covers W1 and W2 together, after one harvest paste). The lead's rulings
come from `docs/prompts/l3-w2-brief.md`. W1's contract (`docs/prompts/l3-w1-contract.md`, with its §12) stands.

W2 delivers this, playable alone in Studio once the paste is in: the 15 weapon models and their 15 shelf icons are
uploaded and templated in one run; the Armory stage shows the selected weapon in 3D, turning, in both places; the shelf
shows each family's icon; every player holds the weapon in use in the right hand and wears the other on the back, and
every other client sees it; a teammate's arm swings with their strikes. Nothing a hit is judged on moves.

**Ben's test:** boot `proving.rbxl` into the lobby; a sword in the hand, a bow on the back; press 2: they swap. K: the
Longbow turns on the stage, a drag turns it faster, the shelf shows 15 icons (the unowned ones as black silhouettes).
F (the Flamethrower lever), equip it: the bow on the back becomes the flamethrower; fire it in a run: the flame leaves
the nozzle. Then the same screen in the hub. A teammate's weapons need a second client (L3-61).

Rulings are numbered **L3-40** on. Every number is a starting value its owner may move within the rule it serves.
Four places where a brief ruling meets the code are marked **(code)** (L3-42, L3-50, L3-52, L3-56); one is marked
**(needs lead → Ben)** (L3-55).

## What today's code gives us (checked 2026-10-20 at d7960b9)

- **Hands are empty, by design.**
  - `WeaponController` clones `Assets/Props/<band eraName>/<tierDef.model>` for the **slot tier**
    (`WeaponController.luau:138-163, 233-250`); the names are `Armory.json slots.*.tiers[].model` ("WeaponSwordI" …,
    `Armory.json:90-93`), typed at `Types.luau:1061, 1074` and `Armory.luau:59, 71`. No such template exists
    (`templates/_props/` holds Boomtown, Metropolis, OrbitalColony, Village), so every hand is bare.
  - The tiers arrive through `WeaponController.SetGear` (`:785-791`), whose one caller reads the frozen `combat.gear`
    (`CombatUIController.luau:1107-1111`; the require is `:179`).
  - `attachTo` already welds a prop massless and non-colliding (`WeaponController.luau:196-231`) at `gripCFrame`, an
    offset from the **hand part**, not from `RightGripAttachment` (`:188-192`; `Theme.COMBAT_GRIP_*`,
    `Theme.luau:441-443`, read nowhere else).
- **Tracers start at the hand, in four copies, not three:**
  - `WeaponController.muzzlePoint` (`:629-633`), used by `Shoot` (`:871`);
  - `FeedbackController.muzzleOf` (`FeedbackController.luau:840-852`), used at `:1058, 1074, 1183, 1309, 1391, 2465,
    2656`;
  - `FlameFx.muzzleOf` (`FlameFx.luau:99-112`, the hand + `aim × MUZZLE_FORWARD` 1, `:71`);
  - **a fourth the brief does not list:** `AbilityFx/Shared.luau` `muzzleOf` (`:355-361`, `handOf` + `aim ×
    MUZZLE_FORWARD` 1, `:109`; exported `:449-450`), used by `BladeStorm.luau:116` and `DragonBreath.luau:129`;
    `MagDump.luau` builds the same sum itself from `handOf` (`:89-90`) and also lights a glow at the hand point
    (`:102`), which is a hand, not a muzzle.
  - The server's `AbilityService.muzzleOf` (`AbilityService.luau:200-204`) is the caster's **head**, a rule, not a
    drawing: it stays.
- **No other player's arm moves.** `WeaponController.SwingOther` (`:811-833`) is fed only by
  `CombatFxController.onSwing` (`CombatFxController.luau:1126-1133`) on the C1 `swing` fx that only `CombatService`
  sends (`CombatService.luau:336`), which is not booted (`combat Main.server.luau:14-16`). `FeedbackController.onStrike`
  already has a branch for another player's weapon swing (`elseif swing and not mine then … FrostFx.OnStrike(strike)`,
  `:2876-2879`), and every strike carries its combo `step` (`:2776`). FeedbackController does not require
  WeaponController (`:91-109`).
- **The local stance** is `InputController.setStance` (`InputController.luau:896-910`), which calls
  `WeaponController.SetStance` (`:904`; `WeaponController.luau:793-800`). It changes through `setActiveSlot`
  (`:1859-1869`) on a player's switch (`requestSlot`, `:2228-2233`) or a cast (`:2203`). **The server is never told of a
  pure switch**: it sees a slot only in an attack, a draw or a cast.
- **The server's write points.**
  - Every family change goes through `WeaponService.SetFamily` (`WeaponService.luau:2647-2675`): the lobby equip and
    the levers (`UnlockService.luau:132-133, 292-293`), the range's `weapon` command (`RangeService.luau:370`).
  - Accepted actions: an attack at `shooter.lastSeq[slot] = seq` (`WeaponService.luau:2471`), a draw at
    `shooter.drawWeapon = weapon` (`:2532`), a cast at `caster.lastSeq = seq` (`AbilityService.luau:1035`, after
    `mechanic.launch` succeeded, `:1025-1034`). WeaponService never sees a cast's acceptance (`SeedFor`, `:2784-2790`,
    takes no slot).
  - Every fresh character passes `WeaponService.PrepareCharacter` (`:2245-2255`): in a mission through ArenaService's
    character hook (`WaveService.luau:2452`) and `AddPlayer` (`WeaponService.luau:2212-2218`), in the range through
    `RangeService` (`RangeService.luau:275-282, 313-325`). Lobby players are admitted shooters
    (`combat Main.server.luau:238-241`).
  - Precedents: server-written character attributes `RangeIframes` (`WeaponService.luau:2043`) and `Placed` /
    `PlacedSeq` (`ArenaService.luau:1031-1032`); attribute names shared through a pure module
    (`Unlocks.Attribute(Unlocks.AIR_JUMP)`, `CombatUIController.luau:747`; `WorldReact.ICE_ATTRIBUTE`).
- **What must not move.** The shot origin is `shotRay` (`InputController.luau:1101-1105`), sent at `:1695-1704`; the
  melee origin is `rig.root.Position` along `flatCameraLook()` (`:1729-1731`); `FeedbackController.PredictSwing`
  (`:3530-3539`) and the server's `aimAllowed` are pinned by the harness (`run_harness.py:252` `AIM_RAYS`, `:341-368`
  `CLIENT_STRIKES`).
- **The template's frame is the blueprint's frame** (the derivation is L3-47):
  - the merge keeps blueprint coordinates (`merge_stages.py:26-27`; `tools/testfit/README.md:588-596`: "merged bounds
    equal the generator's to the thousandth");
  - the harvest records each MeshPart's position minus the inner model's pivot, the glTF origin
    (`harvest.py:105-108, 129-139`);
  - `gen_templates.harvested_cframe` puts the part at (−x, y, −z) of that offset, turned 180° about Y
    (`gen_templates.py:141-154`), under a `Base` PrimaryPart at the identity (`:197-221`);
  - measured, in the committed `Assets.json` against the merge sidecars: Boomtown `LampPost` sidecar centre (0, 3.037,
    −0.788) → harvested offset (0, 3.0375, 0.7875); `BushA` (0.034, 0.419, 0.013) → (−0.0343, 0.4185, −0.0126); sizes
    equal.
  - All 15 weapon blueprints are one piece at `pos` [0, 0, 0], `rotY` 0, `scale` 1.0
    (`tools/testfit/blueprints/_props/Weapons/*.json`).
- **The assets on disk** (gitignored; `assets\` in this worktree is a junction to the main checkout's):
  - 15 frame files `assets/kenney3d/weapon-kit/Models/GLB format/<Model>.frame.json` with `grip` (always the origin),
    `tip`, `holster` and the builders' extras: `bladeBase` (Broadsword, Spear, Spinblade), `nock` (Longbow, Splitbow),
    `splitUp` / `splitDown` (Splitbow), `support` (Beam, Chaingun, Launcher, Rifle, Shotgun, Smg), `sight` (Rifle),
    `head` (FrostHammer, Warhammer), `edge` (Greataxe), `pilot` (Flamethrower); plus `bounds`, `length`, `triangles`;
  - 15 merged `assets/build/stages/_props/Weapons/<Model>_S0.glb` with sidecars (Broadsword's bounds equal its frame
    file's exactly; 3,448 triangles both), merged 10:41–11:32 on a palette cache written at 10:37
    (`assets/build/palettes/weapon-kit.{json,png}`);
  - 15 icons `assets/testfit/out/Weapons/<Model>_icon.png`, each 512 × 512, 8-bit RGBA (colour type 6).
- **The props route needs no project change.** `templates/_props` maps to `ReplicatedStorage/Assets/Props` in all six
  project files (`default.project.json:14-18`, `combat.project.json:14-19`, `boomtown`, `metropolis`, `orbital`,
  `.proving`). Nothing is waiting for a harvest today (`harvest.list_missing` is empty in both modes), so W2's paste
  holds exactly its own 30 records.
- **The uploaders.**
  - `upload_models.py --props` names a stage `EraCityTycoon_Prop_Weapons_<Model>_S0` (≤ 42 characters,
    `upload_models.py:265`), describes it "Kenney kit pieces, CC0" (`:266`, untrue for a generated kit), skips any stage
    with a non-zero id (`:251-253`) and **saves `Assets.json` on a dry run** (`:270-271`).
  - `upload_paths.upload_decal` (`upload_paths.py:106-123`) is generic, but `png_problems` rejects alpha (`:89-103`)
    and `main` needs a path bake record (`:272-275`).
  - `harvest.py` resolves a Decal to its image id only for `pathTexture` and `worldTexture` (`:124-128`), emits and
    merges kinds by name (`:172-215, 587-617`), and `harvest.luau` is generated ("Do not edit").
  - `assets_config.ensure_prop` rebuilds a prop entry as `{"stages": …}`, dropping any other key (`:141-152`), and
    `render_assets` writes only the top-level keys it knows (`:326-339`): an unknown block is erased by the next save
    of any tool. Versions: props 2, paths 3, world 4.
  - `gen_asset_manifest.py` lists props per era from `Config/Eras/*.json` (`collect_props`, `:235-276`): a `Weapons`
    folder appears nowhere.
- **The client's configs.** `Catalog.GetAssetsConfig` is optional and nil-safe (`Catalog.luau:154-168`);
  `Types.AssetsConfig` has no icons (`Types.luau:346-360`).
- **The stage and the shelf.** `ArmoryStage`'s API is `new`, `Show`, `SetSize`, `Destroy` (`ArmoryStage.luau:19-25`);
  the screen makes it at `ArmoryScreen.luau:477`, sizes it at `:615, 626`, shows at `:657`, destroys at `:969`, and
  `setOpen` (`:801-845`) never tells it the screen opened. A card is 92 × 56 on a 64-tall shelf (`Theme.luau:24,
  1458-1460`). `Theme.reducedMotion` is true on every touch device (`:1592`); `Theme.lowEndDevice` is the graphics gate
  (`:1594`).
- **Compile budget** (`py tools/check_compile.py --counts`, PASS, 178 files): FeedbackController 162, InputController
  158, CombatFxController 126 top-level locals (cap about 180); WeaponService and WeaponController are under 105.
- **Party size** is 4 at most (`Combat.json:38` `maxParty`): at most 8 held models on screen.

## 1. The asset run (pipeline engineer builds the tools; the lead runs the uploads; Ben pastes once)

**L3-40. One run, one paste.**
- 15 models + 15 icons = **30 uploads**, then **one harvest paste of 30 records** (`[HARVEST-DONE] 30 loaded, 0
  failed`), then templates. The order:
  1. the pipeline engineer's tools land and the routing is proven on scratch copies (L3-44);
  2. the lead announces to any other open session, then re-merges and uploads the models (L3-41) and the icons
     (L3-42), and commits `Assets.json` right after;
  3. Ben's paste (Studio, the **local** `C:\Users\benja\Desktop\tycoon\build\test.rbxl`, Edit mode, Command Bar);
  4. the lead saves the clipboard to a file **first**, merges from the file, commits `Assets.json`, writes the
     templates, runs the turn proof on all 15 (L3-47) and regenerates the manifest.
- The code wave does not wait for the paste: without templates and icons everything degrades (L3-59), so review and QA
  run in parallel with the run, and the paste may come whenever Ben is at Studio, before his look.

**L3-41. The models: the props route, era folder `Weapons`.**
- Blueprints `tools/testfit/blueprints/_props/Weapons/<Model>.json` (the folder holds exactly the 15), merged to
  `assets/build/stages/_props/Weapons/`, uploaded into `Assets.json props.Weapons.<Model>`, templated to
  `templates/_props/Weapons/<Model>.rbxmx` = `ReplicatedStorage/Assets/Props/Weapons/<Model>` in both places.
- **A fresh palette before the upload:** delete `assets/build/palettes/weapon-kit.*` and re-merge all 15 (the cache
  is older than the step-2 generators, and the cache trap snaps unknown colours silently). Then `weapon_frames.py`
  (L3-46) confirms every merged sidecar's bounds equal its frame file's (± 0.002) and its triangles equal the frame
  file's count.
- The props description drops "Kenney kit pieces, CC0" for the kits the sidecar names ("…; kits: weapon-kit."). It
  changes only what new uploads say.
- Commands (Git Bash for Blender):
  `blender -b -P tools/assets/merge_stages.py -- --props --era Weapons`, then
  `py tools/assets/upload_models.py --props --era Weapons`. On "Unknown Error" run the same line again.

**L3-42. (code) The icons: their own entry point on `upload_paths`' decal route.**
- `upload_paths.py`'s `main` needs a bake record, so the icons get **`tools/assets/upload_icons.py`** (new), which
  imports `upload_decal` from `upload_paths` and changes nothing there:
  `py tools/assets/upload_icons.py --set Weapons [--model <Model>] [--icons-dir <dir>] [--assets-json <file>] [--dry-run]`.
- The list of icons is `WeaponModels.json` (L3-46): one per family, `<icons-dir>/<model>_icon.png`, the default dir
  `assets/testfit/out/<set>/`.
- **Its own check** (`icon_problems`, never `png_problems`): PNG signature; 512 × 512; bit depth 8; colour type 6
  (RGBA); and, decoded with `zlib` and the PNG row filters in plain Python (no Pillow here), the four corner pixels are
  fully transparent and at least one pixel is fully opaque. A failing file is not uploaded.
- **`Assets.json` v5, a new top-level block** `icons.<Set>.<Model> = { assetId, imageId, sha256 }`, rendered in that
  key order, sets and models sorted. A file becomes v5 only once it carries icons. Not inside `props`: `ensure_prop`
  would drop it (`assets_config.py:141-152`).
- Idempotent and hash-checked like `upload_paths`: a non-zero `assetId` whose file still has the recorded `sha256` is
  skipped; a changed file goes up again and its `imageId` is cleared. `Assets.json` is saved after every upload.
- Display name `EraCityTycoon_Icon_<Set>_<Model>` (39 characters at most; the `ECT_` fallback and the 50-character cap
  as `upload_paths.display_name`). Description "Era City Tycoon shelf icon '<Model>' (<Set>). Rendered from the
  generated weapon kit (tools/testfit/weaponview.py)."
- **Its `--dry-run` writes nothing** (unlike the older uploaders): it validates and lists.

**L3-43. The harvest records the icons.**
- A new kind **`icon`** (`set`, `model`, `id`), emitted in **both** modes for every icon with an `assetId` and no
  `imageId`, like path textures (`harvest.py:188-192`), so `--emit --props` carries the 15 props and the 15 icons.
- `LUAU_TEMPLATE`'s Decal branch takes `asset.kind == "icon"` beside `pathTexture` and `worldTexture`
  (`harvest.py:124`); `merge_icon` writes `imageId` (a 0 means "still in moderation?": warned, skipped); `list_missing`
  names unharvested icons.
- `harvest.luau` stays generated: the lead's `--emit --props` at the run writes it; the engineer emits only to a
  scratch `--luau` path.
- The clipboard rule (memory orbital-growth): the lead saves the Output to a file before `harvest.py`, counts the
  `[HARVEST] {` records (30), and merges with `--file`.

**L3-44. The routing is proven before any upload, on scratch copies only.** The pipeline engineer runs this chain
in a scratch folder and puts the transcript in its report; nothing touches the real `Assets.json`, `templates/` or
`tools/assets/harvest.luau`:
1. copy `src/shared/Config/Assets.json` to the scratch folder;
2. `upload_models.py --props --era Weapons --dry-run --assets-json <scratch>/Assets.json` → 15 "would upload" lines, every name
   ≤ 50 characters;
3. `upload_icons.py --set Weapons --dry-run --assets-json <scratch>/Assets.json` → 15 valid icons, and the scratch file unchanged;
4. a fixture `tools/assets/fixtures/harvest_weapons_sample.txt` (fake ids, offsets = each sidecar centre with x and z
   negated, sizes = the sidecar's, 15 `prop` + 15 `icon` records), after fake `modelAssetId`/`assetId`s are written
   into the scratch file;
5. `harvest.py --emit --props --assets-json <scratch>/Assets.json --luau <scratch>/harvest.luau` → 30 entries;
6. `harvest.py --props --file <fixture> --assets-json <scratch>/Assets.json` → 15 prop stages and 15 icons merged;
7. `gen_templates.py --props --assets-json <scratch>/Assets.json --out <scratch>/templates` →
   `<scratch>/templates/_props/Weapons/<Model>.rbxmx`, each a Model with `Base` and `Stage0` holding one MeshPart
   `weapon-kit`, CanCollide and CanQuery false;
8. `weapon_frames.py --check --assets-json <scratch>/Assets.json` → the turn proof passes on the 15 fakes and on the real fixture
   (L3-47).

**L3-45. The manifest and the commands.**
- `gen_asset_manifest.py` gains a **"Weapons" section** (written when `WeaponModels.json` exists): per family the
  model, blueprint, GLB, uploaded, harvested, template, its points in `WeaponModels.json`, icon uploaded, icon
  harvested. `docs/ASSET_MANIFEST.md` is regenerated with the tool change (all "not yet") and again after the harvest.
- `docs/MANUAL_STEPS.md` gets **"L3 W2 — the asset run"** in the shape of M12 §19: the merge, both uploads, Ben's
  paste (the local file, View → Command Bar, Ctrl+V, Enter, wait for `[HARVEST-DONE] 30 loaded, 0 failed`, Output →
  Select All → Ctrl+C, say "done" and copy nothing else), the lead's save-and-merge lines, the templates, the proof, the
  manifest, the sourcemaps and the six place files. The engineer checks every flag against the tools.

## 2. Frame points come from config, never from a mesh

**L3-46. `src/shared/Config/WeaponModels.json`, generated by `tools/assets/weapon_frames.py`.**
- The shape (every list of numbers on one line, families sorted by id, LF, two-space indent):

```json
{
  "version": 1,
  "folder": "Weapons",
  "families": {
    "broadsword": {
      "model": "Broadsword",
      "points": {
        "bladeBase": [0.0, 0.0, -0.66],
        "grip": [0.0, 0.0, 0.0],
        "holster": [0.0, 0.0, -1.265],
        "tip": [0.0, 0.0, -3.18]
      },
      "bounds": { "min": [-0.143, -0.66, -3.18], "max": [0.155, 0.66, 0.65] }
    }
  }
}
```

- `folder` is the props folder and the icons set. `model` = the family id with its first letter capitalised
  (`frostHammer` → `FrostHammer`, `smg` → `Smg`), checked, never derived in Luau without the config. `points` is every
  point of the frame file: `grip`, `tip`, `holster` always, the extras where the builders wrote them. Coordinates are
  studs **in the template's frame** (L3-47). `bounds` frames the stage camera (L3-56); nothing measures a mesh.
- `py tools/assets/weapon_frames.py` reads the 15 frame files and `ProvingGrounds.json weapons`, then writes the file.
  It fails, writing nothing, when: a weapons family has no frame file; a `model` breaks the name rule; `grip` is not
  [0, 0, 0]; `tip` or `holster` is missing; a point lies outside `bounds` by more than 0.01; a blueprint is not one
  piece at `pos` [0, 0, 0], `rotY` 0, `scale` 1 (the identity precondition of L3-47); a merge sidecar exists and its
  bounds differ from the frame file's by more than 0.002 or its triangles differ.
- `--check` regenerates in memory and diffs against the committed file. On a checkout without the frame files (the
  `assets` folder is gitignored) it checks the committed file's shape and its families against `ProvingGrounds.json`,
  says "frame files absent: shape checked only", and passes. It always runs the turn proof (L3-47) on what it can.
- The generator is the committed record; the frame files regenerate with the kit's generators.

**L3-47. The transform from the generator's frame to the template's is the identity, and the generator proves it.**
- The derivation, from the code above. A point *p* of the generator frame (grip at the origin, tip along −Z, up +Y)
  sits at *p* in the blueprint, because each weapon's one piece is at the origin, unturned, at scale 1. The merge keeps
  it there. Let *c* be the merged mesh's bbox centre.
  1. The glTF import turns the model 180° about Y at the glTF origin: *p* becomes (−pₓ, p_y, −p_z), and the MeshPart's
     centre is (−cₓ, c_y, −c_z). The harvest records that centre as `offset` (the data above shows it), and the
     MeshPart is unrotated (`harvest.py` warns otherwise). So *p* in the MeshPart's own frame is
     L = (−pₓ + cₓ, p_y − c_y, −p_z + c_z).
  2. `harvested_cframe` places the MeshPart at (−offsetₓ, offset_y, −offset_z) = (cₓ, c_y, c_z), turned by R = the
     180° turn about Y, R·(a, b, c) = (−a, b, −c).
  3. In the template: (cₓ, c_y, c_z) + R·L = (pₓ, p_y, p_z). The template's frame **is** the generator's frame, and
     its pivot (`Base`, the PrimaryPart at the identity) **is the grip**. A point *p* of a cloned model is at
     `base.CFrame:PointToWorldSpace(p)`.
- **The proof, in `weapon_frames.py`**, through one pure helper that `harvested_cframe` itself uses (the
  engineer moves the position-and-turn arithmetic out of `harvested_cframe` into `template_placement(offset)`;
  `gen_templates.py --check` proves the bytes did not change):
  - **now**, on real Studio data: a committed fixture `tools/assets/fixtures/turn_proof.json` copies Boomtown
    `LampPost`'s sidecar centre and size and its harvested offset and size; every corner of its bounds goes through the
    import turn, the harvested offset and `template_placement`, and must come back to itself within 0.01;
  - **after the harvest**, on all 15 weapons: every point of `WeaponModels.json` the same way, using the real harvested
    offset, plus harvested size = sidecar size within 0.01. A failure stops the run before the templates are
    committed.

**L3-48. One pure shared module, `src/shared/WeaponLook.luau`** (luau-engineer; no service, no Instance; Vector3 only,
which the harness shims):

```luau
WeaponLook.ATTRIBUTES: { melee: string, ranged: string, held: string }
	-- table.freeze({ melee = "WeaponMelee", ranged = "WeaponRanged", held = "WeaponHeld" })
WeaponLook.ModelName(family: string): string                       -- first letter capitalised
WeaponLook.Def(models: Types.WeaponModelsConfig?, family: string): Types.WeaponModelDef?
	-- nil unless the entry exists, its model is ModelName(family), grip/tip/holster are three finite
	-- numbers each and bounds.min <= bounds.max on every axis
WeaponLook.Point(def: Types.WeaponModelDef, name: string): Vector3?  -- the named point; nil when absent or malformed
WeaponLook.IconId(assets: Types.AssetsConfig?, models: Types.WeaponModelsConfig?, family: string): number
	-- icons[models.folder][Def.model].imageId when a positive whole number; else 0
WeaponLook.Values(loadout: { melee: string, ranged: string }, held: string): { [string]: string }
	-- the three attribute values the server writes; held is "melee" or "ranged" (anything else reads "melee")
WeaponLook.Read(get: (name: string) -> any): (string?, string?, string?)
	-- melee, ranged, held as the client reads them: a non-empty string family, "melee" | "ranged"; else nil
WeaponLook.Problems(models: Types.WeaponModelsConfig?, weapons: { [string]: any }): { string }
	-- every weapons family has a Def, every entry names a weapons family, grip is the origin, every point
	-- inside bounds (0.01); warned once by HeldWeapons.Start
```

- **Types** (luau-engineer): `WeaponModelDef = { model: string, points: { [string]: { number } }, bounds: { min:
  { number }, max: { number } } }`; `WeaponModelsConfig = { version: number, folder: string, families: { [string]:
  WeaponModelDef } }`; `AssetIcon = { assetId: number, imageId: number, sha256: string }`; `AssetsConfig.icons:
  { [string]: { [string]: AssetIcon } }?` with a v5 comment.
- **Catalog**: `Catalog.GetWeaponModelsConfig(): Types.WeaponModelsConfig?`, optional and cached like
  `GetAssetsConfig`: nil means empty hands and the text stage.

## 3. Others see your weapons (server)

**L3-49. Three character attributes, written by `WeaponService` only.**
- `WeaponMelee` = the held melee family, `WeaponRanged` = the held ranged family, `WeaponHeld` = `"melee"` or
  `"ranged"`, the slot in use. Names and values come from `WeaponLook.ATTRIBUTES` and `WeaponLook.Values`.
- `Shooter` gains `held: SlotName`, `"melee"` in `AddPlayer` (the client's starting stance, `InputController.luau:347`).
- One local writer:

```luau
local function showWeapons(shooter: Shooter, character: Model?): ()
	local target = character or shooter.player.Character
	if target == nil then
		return
	end
	for name, value in WeaponLook.Values(shooter.loadout, shooter.held) do
		target:SetAttribute(name, value)
	end
end
```

- Called from: `PrepareCharacter`, as `showWeapons(shooter, character)` inside its `if shooter ~= nil then` (every
  fresh character, in both modes); `SetFamily`, as `showWeapons(shooter, nil)` right after `shooter.drawStartedAt = 0`
  and outside `if previous ~= family` (every loadout change, the levers included).
- In every mode (range and mission, the lobby included). No new remote: attributes replicate.

**L3-50. (code) The slot in use, from every accepted attack, draw or cast.**

```luau
local function noteHeld(shooter: Shooter, slot: SlotName): ()
	if shooter.held == slot then
		return
	end
	shooter.held = slot
	showWeapons(shooter, nil)
end

-- AbilityService's accepted cast (it alone knows the slot when a cast is accepted).
function WeaponService.NoteHeld(player: Player, slot: string): ()
	local shooter = state.shooters[player]
	if not state.active or shooter == nil or (slot ~= "melee" and slot ~= "ranged") then
		return
	end
	noteHeld(shooter, if slot == "melee" then "melee" else "ranged")
end
```

- `noteHeld(shooter, slot)` is the line right after `shooter.lastSeq[slot] = seq` in `OnAttack` (`:2471`) and right
  after `shooter.drawWeapon = weapon` in `OnDraw` (`:2532`).
- **(code)** WeaponService never sees a cast's acceptance, so `AbilityService.OnCast` gets one line,
  `WeaponService.NoteHeld(player, slotName)`, right after `caster.lastSeq = seq` (`AbilityService.luau:1035`). The
  luau-engineer owns AbilityService for that line only.
- A pure switch (1 / 2, pad Y, the touch slot button) tells the server nothing: **others see it at that player's next
  attack, draw or cast** (L3-65). The player's own client shows it at once (L3-51).
- **Never in a hit:** `shooter.held`, `showWeapons`, `noteHeld` and `WeaponLook` appear in no hit-deciding function (`damageScale`,
  `meleeOrigin`, `aimAllowed`, `claimSlack`, `resolveMelee`, `resolveRanged`, `strike`). Text check T8.

## 4. Weapons in hand (client, ui-engineer B)

**L3-51. A new controller module, `src/combat/client/Controllers/HeldWeapons.luau`** (new behaviour in a new module,
for the compile budget). Started by `WeaponController.Start` (Main.client stays unchanged):

```luau
HeldWeapons.Start(): ()
HeldWeapons.SetLocalStance(slot: string): ()          -- from WeaponController.SetStance, the same frame
HeldWeapons.Muzzle(userId: number): (Vector3?, boolean)  -- L3-52: (point, fromModel)
HeldWeapons.Destroy(): ()
```

- **Who:** every player's character in the combat place (`Players:GetPlayers()`, `PlayerAdded`, `CharacterAdded`),
  the local one included. Bots and departed players have none.
- **What it reads:** `WeaponLook.Read(function(name) return character:GetAttribute(name) end)` on the character, again
  on `GetAttributeChangedSignal` of each of the three names. For the **local** character the slot in use is the local
  stance (`SetLocalStance`), never `WeaponHeld`.
- **One clone per character and family:** a weak-keyed cache `models[character][family]`; `modelFor(character,
  family)` returns the cached model or clones `ReplicatedStorage.Assets.Props[<folder>][<Def.model>]` once, seals it
  (L3-52) and parents it to the character as `HeldWeapon_<family>`. A family that leaves the loadout is destroyed; the
  character's death takes the rest.
- **Hanging, by a `Weld` from the body part to the clone's `Base`** (the pivot, the grip; `C1` the identity):
  - **in use**: `Part0` = the part holding `RightGripAttachment`, `C0 = attachment.CFrame * Theme.COMBAT_HOLD_GRIP *
    CFrame.new(-grip)`;
  - **the other**: `Part0` = the part holding `BodyBackAttachment`, `C0 = attachment.CFrame * Theme.COMBAT_HOLD_BACK *
    CFrame.new(-holster)`.
  - A stance change only sets the two welds' `Part0` and `C0` (and each model's other parts stay welded to its `Base`
    by `WeldConstraint`s made once at the clone). **Never per frame:** HeldWeapons has no RunService connection.
  - Attachments are looked up **only as direct children** of `RightHand` / `Right Arm` and `UpperTorso` / `Torso`, never
    by a recursive search: accessory handles carry attachments of the same names. A missing part or attachment leaves
    that slot empty until it appears (`ChildAdded`, no yield in the handlers).
  - Two-handers (Warhammer, Greataxe, Spear) and bows are held by the right hand alone in L3.
- **Missing anything** (no models config, no `Def`, no template, no attachment): that slot is empty, as today; a family
  the config does not know warns once.

**L3-52. (code) Decoration only, and one muzzle.**
- `local function seal(model: Model): ()` sets, on every BasePart of a clone: `Anchored = false`, `CanCollide = false`,
  `CanQuery = false`, `CanTouch = false`, `Massless = true`, `CastShadow` unchanged. Called from `modelFor` before the
  first parent. Never a physics body, never in a query: the camera 1.75 studs right of the shoulder and every client
  ray pass through it.
- **The origins do not move:** `InputController.luau` is not edited in W2 (its `shotRay` and melee lines, `:1101-1105,
  1695-1704, 1729-1731`), nor `FeedbackController.PredictSwing`, nor the server's `meleeOrigin` / `aimAllowed`. A model is
  never a ray start or an arc centre.
- **`HeldWeapons.Muzzle(userId)`**: the world position of the `tip` of that player's model **in the hand** and
  `true`; with no model in the hand, the old fallback chain `RightHand`, `Right Arm`, `HumanoidRootPart` (direct
  children of the character) and `false`; with no character, `nil, false`.
- **(code)** It replaces **four** copies, not three:
  - `WeaponController.muzzlePoint(fallback)` → `HeldWeapons.Muzzle(Players.LocalPlayer.UserId) or fallback`;
  - FeedbackController's `muzzleOf` goes; its seven sites call `(HeldWeapons.Muzzle(userId))` (one less local, one more
    require: the count stays);
  - `FlameFx.muzzleOf(userId, aim)`: the helper's point, plus `aim * MUZZLE_FORWARD` **only when it is not from a
    model** (the nozzle is the tip);
  - `AbilityFx/Shared.luau`: `muzzleOf(userId, aim, fallback)` keeps its signature and the same rule (forward push only
    on the fallback). `handOf` stays for what is really a hand (MagDump's hand glow, `:102`); `MagDump.luau` takes its
    `muzzle` from `muzzleOf` instead of `handPoint + look * MUZZLE_FORWARD` (`:89-90`).

**L3-53. Other players' arms move.** In `FeedbackController.onStrike`, inside `elseif swing and not mine then`
(`:2876-2879`), beside the frost puff: `WeaponController.SwingOther(strike.userId, strike.step or 1)`. FeedbackController
requires WeaponController (no cycle: WeaponController requires neither it nor InputController). The C1 `onSwing` path in
CombatFxController stays until the C1 modules are deleted (carried).

**L3-54. The slot-tier model lookup goes.**
- From WeaponController: `gear`, `SetGear`, `tierDefFor`, `propFolderFor`, `refreshWeapon`, `attachTo`, `gripCFrame`,
  `clearWeapon`, `weapon`, `armoryConfig`, the `Armory` require and the `SlotTiers` export. `SetStance` keeps cancelling
  the pose and calls `HeldWeapons.SetLocalStance(nextStance)`. The swing pose, the trail, the shots, `SwingOther`,
  `Hitstop` and `ArrivalDelay` stay.
- From CombatUIController: the `WeaponController.SetGear(gear, ascension)` line (`:1111`) and the require (`:179`).
  Nothing else there changes (`InputController.SetGear` stays an old reader until L4).
- `Armory.json slots.*.tiers[].model` and `Types.WeaponTierDef.model` stay with `slots` until L4 deletes them together
  (one change, not two).
- The trail keeps its hand attachments (`COMBAT_TRAIL_NEAR` / `FAR`, along the line a held blade hangs); moving it to
  `bladeBase` → `tip` is a follow-up if Ben finds it off (L3-73).

**L3-55. (needs lead → Ben) One look: `Stage0`, for everyone.**
- Each template has `Stage0` only; the client shows it.
- §24 says "looks that grow with the tier can follow later as content only". That holds for the player's own weapon,
  the stage and the shelf (the client knows its own tiers), **but not for other players' weapons**: their tiers are not
  on the character. Growth later then needs a small code change (a pick rule and two look attributes), not content
  alone.
- **Recommended:** keep W2 at `Stage0` and tell Ben in one line. The alternative is two more attributes now
  (`WeaponMeleeLook`, `WeaponRangedLook`, written by `SetFamily`, `PrepareCharacter` and every upgrade), for looks that
  do not exist yet.

## 5. The stage and the shelf (ui-engineer A)

**L3-56. (code) The stage: a ViewportFrame behind `ArmoryStage`.**
- **The API gains one method, `SetActive(active: boolean)`**, which only `ArmoryScreen` calls: true while the screen is
  open on the Weapons tab, false on close, on the Abilities tab and on Destroy. Nothing else in the existing API tells
  the stage the screen is open. The hosts (`CombatUIController`, `UIController`) and `ArmoryScreen`'s handle do not
  change.
- **One ViewportFrame** (`BackgroundTransparency` 1, over the existing gradient), its own `Camera` as `CurrentCamera`,
  `Ambient`, `LightColor` and `LightDirection` from Theme (L3-58). Not selectable by a gamepad.
- **The model:** on a selection of a different family, the previous clone is destroyed and the template
  (`WeaponLook.Def` + `Catalog.GetWeaponModelsConfig`) is cloned once, anchored, and pivoted once to a **display
  pose**: `CFrame.Angles(math.rad(Theme.ARMORY_STAGE_TILT_DEGREES), 0, 0)` (the tip rising, as on the icons). After
  that it never moves.
- **The camera orbits; the model never turns.** The camera looks at the display pose's bounds centre (the config's
  `bounds`, turned by the pose) from `radius / sin(fov / 2) × ARMORY_STAGE_FIT`, where `radius` = half the bounds'
  diagonal (a turn never changes the framing), at `ARMORY_STAGE_PITCH_DEGREES` above, starting at
  `ARMORY_STAGE_START_YAW_DEGREES`.
  - **The slow turn** (`ARMORY_STAGE_TURN_DEGREES_PER_SECOND`) runs on one `RenderStepped` connection made in
    `SetActive(true)` **only when `not Theme.lowEndDevice`**, and dropped in `SetActive(false)`. Never gated on
    `reducedMotion` (true on every phone).
  - **Drag to turn** on every device: a press on the viewport (mouse or touch), then `UserInputService.InputChanged`
    moves the yaw by `ARMORY_STAGE_DRAG_DEGREES_PER_PIXEL` per pixel; release ends it; the slow turn carries on from
    there. On a low-end device each drag event re-places the camera once (no per-frame work).
- **Owned:** `ImageColor3` white. **Unowned: a near-black silhouette** (`ImageColor3 = Theme.ARMORY_STAGE_SILHOUETTE`)
  over the **light** gradient, so the outline reads (the dark gradient stays for the text placeholder only).
- **The text:** with a model shown, the name and the big tier (already in the detail column) hide; the slot word and
  the element chip stay as a small top line. **With no template** (or no config), today's placeholder exactly.
- **Warm-up:** on the first `SetActive(true)`, one `task.spawn` → `pcall(ContentProvider.PreloadAsync, …)` of the
  `Weapons` folder; nothing waits on it.

**L3-57. The shelf shows each family's icon.**
- `WeaponLook.IconId(Catalog.GetAssetsConfig(), Catalog.GetWeaponModelsConfig(), family)`; a non-zero id draws an
  `ImageLabel` (`rbxassetid://<imageId>`, `ScaleType.Fit`) at least `ARMORY_SCREEN_CARD_ICON` design px square; an
  unowned card's icon has `ImageColor3 = Theme.ARMORY_STAGE_SILHOUETTE` (the "unowned 64" sample in
  `assets/testfit/out/Weapons/<Model>_icon_check.png`).
- With id 0, **today's text card exactly**.
- Where the icon sits in a 92 × 56 card (and a 68-wide portrait card) is ui A's call, under three rules: touch ≥ 48
  design px; names never under `LABEL_MIN_TEXT` and "Flamethrower" never broken mid-word; the 682 × 313 and 712 × 330
  landscape fits and the 393 × 648 portrait fit of L3-23 still hold.
- `ArmoryModel` and `tests_l3_ui.luau` do not change.

**L3-58. Theme constants** (ui-engineer A adds all of them, ui B's included; starting values, one Studio round
expected):

| Constant | Start | Read by |
|---|---|---|
| `ARMORY_STAGE_AMBIENT` | `Color3.fromRGB(128, 128, 128)` (the weapon view's 0.5) | stage |
| `ARMORY_STAGE_LIGHT_COLOR` | `Color3.fromRGB(158, 158, 158)` (0.62) | stage |
| `ARMORY_STAGE_LIGHT_DIRECTION` | `Vector3.new(-1, -1, -1)` | stage |
| `ARMORY_STAGE_SILHOUETTE` | `Color3.fromRGB(14, 16, 22)` | stage, shelf |
| `ARMORY_STAGE_FOV` | 30 | stage |
| `ARMORY_STAGE_FIT` | 1.15 | stage |
| `ARMORY_STAGE_PITCH_DEGREES` | 12 | stage |
| `ARMORY_STAGE_TILT_DEGREES` | 30 | stage |
| `ARMORY_STAGE_START_YAW_DEGREES` | 35 (the strips' three-quarter view) | stage |
| `ARMORY_STAGE_TURN_DEGREES_PER_SECOND` | 20 | stage |
| `ARMORY_STAGE_DRAG_DEGREES_PER_PIXEL` | 0.5 | stage |
| `ARMORY_SCREEN_CARD_ICON` | 40 | shelf |
| `COMBAT_HOLD_GRIP` | `CFrame.identity`: the tip along `RightGripAttachment`'s look (down a hanging arm, forward when the swing or draw pose raises it), the top along its up | HeldWeapons |
| `COMBAT_HOLD_BACK` | `CFrame.new(0, 0, 0.3) * CFrame.Angles(0, 0, math.rad(35)) * CFrame.Angles(math.rad(90), 0, 0)`: the tip up, across the back, off its surface | HeldWeapons |

- `COMBAT_GRIP_FORWARD`, `COMBAT_GRIP_UP` and `COMBAT_GRIP_PITCH_DEGREES` go (their only reader goes, L3-54).
  `COMBAT_WEAPON_WAIT_SECONDS` stays (the shoulder wait).

## 6. Missing assets degrade, never error

**L3-59.**

| Missing | What shows |
|---|---|
| `WeaponModels.json`, or a family in it | empty hands for it; the text stage; the text card (no icon id can be found) |
| a template (`Assets/Props/Weapons/<Model>`) | that slot's hand empty; the text stage for it |
| an attachment (`RightGripAttachment`, `BodyBackAttachment`) | that slot empty until it appears |
| an icon, or its `imageId` (moderation) | today's text card |
| the attributes (a bot, a rig, a stopped WeaponService) | nothing held |
| a model's `tip` | the muzzle falls back to the hand |

No path errors; a family the config lacks warns once per session.

## 7. Cost, sound, phones, keys

**L3-60. Cost.** At most 8 held models on screen (party of 4, two each), about 1,700–3,500 triangles each. A model is
cloned once per character and family and re-hung on a stance change, never per frame. The stage holds one clone and
re-renders per frame only while it turns (open, Weapons tab, not low-end). The shelf holds 15 images.

**L3-61. No sound. Phones first. No new key or lever.** Every input above works by touch. Nothing needs a new key in
either place. The teammate check (a second player's weapons and arm) needs two clients: Studio's Test tab → "Clients and
Servers" with 2 players (*Prueba → Clientes y servidores*). PLAYTEST says so plainly; the debug bots are rigs and hold
nothing.

## 8. Owners (disjoint; one wave; the gates run after every owner has reported)

**Pipeline engineer** (`general-purpose`, Opus).
- Owns: `tools/assets/weapon_frames.py` (new), `tools/assets/upload_icons.py` (new), `tools/assets/assets_config.py`
  (v5 `icons`), `tools/assets/harvest.py` (the `icon` kind), `tools/assets/gen_templates.py` (only
  `template_placement`, bytes unchanged), `tools/assets/upload_models.py` (the description), `tools/gen_asset_manifest.py`,
  `docs/ASSET_MANIFEST.md` (regenerated), `src/shared/Config/WeaponModels.json` (generated; **its first deliverable**,
  the others read it), `tools/assets/fixtures/harvest_weapons_sample.txt` and `turn_proof.json` (new),
  `tools/testfit/README.md` ("weapon kit": the icons route and the config), `docs/MANUAL_STEPS.md` "L3 W2 — the asset
  run".
- Runs: the fresh palette and the re-merge of the 15 (L3-41), the scratch routing chain (L3-44). **Never** an upload,
  the real harvest, or a dry run against the real `Assets.json`. Kills only its own PIDs.
- Done when: `weapon_frames.py --check`, `gen_templates.py --check` and `gen_asset_manifest.py --check` pass; the
  L3-44 transcript is in its report; every MANUAL_STEPS flag is checked against the tools.

**luau-engineer** (Opus).
- Owns: `src/shared/WeaponLook.luau` (new), `src/shared/Types.luau`, `src/shared/Catalog.luau`,
  `src/combat/server/Services/WeaponService.luau`, `src/combat/server/Services/AbilityService.luau` (the `NoteHeld` line
  only); in `tools/crowd_harness/`: `tests_l3_w2.luau` (new), `run_harness.py` (`WeaponLook` in `SOURCES`, the new test
  file in `TESTS`, the shipped `WeaponModels.json` as a fixture, the text checks T1–T14), `mutate.py` (an `l3w2:` entry
  for every pure rule and every text check; the new files in `FILES`).
- Done when: the harness passes with the shipped `WeaponModels.json`, every `l3w2:` mutant is caught
  (`mutate.py … l3w2`), `check_compile` passes, and nothing else on the server changes. Report every new require (no
  cycle) and the exact text of each pinned line.

**ui-engineer A** (Opus).
- Owns: `src/client/UI/ArmoryStage.luau` (L3-56), `ArmoryShelf.luau` (L3-57), `ArmoryScreen.luau` (the `SetActive`
  calls only), `Theme.luau` (every constant of L3-58, the three removals).
- Done when: the screen fits L3-23's three sizes with icons, stays under the compile cap, and stylua, selene and
  luau-lsp are clean on both sourcemaps; with no templates and no icons it looks exactly like W1.

**ui-engineer B** (Opus).
- Owns: `src/combat/client/Controllers/HeldWeapons.luau` (new), `WeaponController.luau`, `FeedbackController.luau`,
  `FlameFx.luau`, `AbilityFx/Shared.luau`, `AbilityFx/MagDump.luau` (its muzzle lines), `CombatUIController.luau` (the
  two `SetGear` lines only), and `CombatFxController.luau` (no change expected).
- Codes against the Theme names of L3-58 before ui A lands them.
- Done when: FeedbackController stays at or under 163 top-level locals; no muzzle code is left outside HeldWeapons;
  InputController is untouched; stylua, selene and luau-lsp are clean.

**Lead.**
- The uploads, Ben's paste, the harvest from a saved file, templates, the post-harvest proof, sourcemaps
  (`rojo sourcemap` for both trees: there are new files) and the six place files; INTERFACES "# L3 W2 contracts" (a
  pointer to this file). No project file changes.

**Hand-offs ("for the other owner"):** the pipeline engineer → everyone: `WeaponModels.json` as soon as it is written;
ui A and ui B → luau-engineer: the exact text of their pinned lines (T9–T14) if it differs from §9; anyone → lead: a
needed Theme constant beyond L3-58, a project-file or remote change.

**Every agent:** `git status` and `git diff` first; commit nothing; kill only your own PIDs; write the report to
`docs/prompts/l3-w2-reports/<role>.md` as well as replying. PATH `export PATH="$HOME/.rokit/bin:$PATH"`; Python `py`;
the harness `py tools/crowd_harness/run_harness.py C:/Users/benja/Desktop/tycoon-p5
C:/Users/benja/Desktop/tycoon/tools/bin/luau.exe` (the repo root first).

## 9. Gates

**Text checks** (`run_harness.py`; each pins the call, the inputs it is given, and that it is reached; each has an
`l3w2:` mutant). The line texts here are binding for their owners; a reason to differ goes to the lead.

| # | File, function | Pinned |
|---|---|---|
| T1 | WeaponService `showWeapons` | `for name, value in WeaponLook.Values(shooter.loadout, shooter.held) do`, `target:SetAttribute(name, value)`, `local target = character or shooter.player.Character` |
| T2 | WeaponService `PrepareCharacter` | `showWeapons(shooter, character)` inside `if shooter ~= nil then` |
| T3 | WeaponService `SetFamily` | `showWeapons(shooter, nil)` after `shooter.drawStartedAt = 0`, outside `if previous ~= family` |
| T4 | WeaponService `OnAttack` | `noteHeld(shooter, slot)` on the line after `shooter.lastSeq[slot] = seq` |
| T5 | WeaponService `OnDraw` | `noteHeld(shooter, slot)` on the line after `shooter.drawWeapon = weapon` |
| T6 | AbilityService `OnCast` | `WeaponService.NoteHeld(player, slotName)` on the line after `caster.lastSeq = seq` |
| T7 | WeaponService `noteHeld`, `NoteHeld` | the same-slot return, `shooter.held = slot`, `showWeapons(shooter, nil)`; the slot check and `noteHeld(shooter, …)` |
| T8 | WeaponService hit functions | none of `.held` (the field; the word "held" is already a StrikePick verdict there), `showWeapons`, `noteHeld`, `WeaponLook` in `damageScale`, `meleeOrigin`, `aimAllowed`, `claimSlack`, `resolveMelee`, `resolveRanged`, `strike` |
| T9 | FeedbackController `onStrike` | `WeaponController.SwingOther(strike.userId, strike.step or 1)` inside `elseif swing and not mine then` |
| T10 | the muzzle | no `"RightHand"` in FeedbackController or FlameFx; in AbilityFx/Shared only inside `handOf`, and its `muzzleOf` body calls `HeldWeapons.Muzzle(`; MagDump's `muzzle =` lines call `muzzleOf(`; WeaponController's `muzzlePoint` body is the helper call; in HeldWeapons `"RightHand"` appears only in its fallback list |
| T11 | HeldWeapons | exactly one `:Clone()`, inside `local function modelFor(`, after the cache lookup; no `RunService` in the file |
| T12 | HeldWeapons `seal` | the five property lines of L3-52, called from `modelFor` |
| T13 | HeldWeapons | no `FindFirstChild(` with a `true` second argument |
| T14 | ArmoryStage | no `Theme.reducedMotion` (the header comment already names the word); the one `RenderStepped:Connect` inside `SetActive` behind `not Theme.lowEndDevice`; the model's `PivotTo` only in the select path |

**Pure tests** (`tests_l3_w2.luau`, luau-engineer): `ModelName` for all 15 ids; `Def` refusing an unknown family, a
model mismatch, a missing `grip` / `tip` / `holster`, a point of two numbers, a NaN or infinite number, `min > max`;
`Point` present and absent; `IconId` with no assets, no `icons`, no set, no model, `imageId` 0, negative, fractional or
not a number, and the id when all is there; `Values` and `Read` (bad types read nil, a bad `held` reads nil); `Problems`
empty on the shipped files and naming each fault on mutated copies (a missing family, an extra one, grip off the
origin, a point outside its bounds).

**QA after the review** (in the W1 list's form):
- stylua, selene, luau-lsp with `tools/types/globalTypes.d.luau` on both sourcemaps (regenerated); `rojo build` for the
  six place files; `py tools/check_compile.py`.
- The harness; `mutate.py … l3w2` (the filtered run; the full run only if the lead wants it); `check_stage_mirror` and
  `mirror_mutants` unchanged.
- `py tools/assets/weapon_frames.py --check`, `py tools/assets/gen_templates.py --check`,
  `py tools/gen_asset_manifest.py --check`.
- `git diff --exit-code main -- src/combat/client/Controllers/InputController.luau src/shared/Config/Armory.json
  src/shared/Config/Combat.json src/shared/Config/ProvingGrounds.json src/shared/Config/Levels src/shared/Layouts`:
  nothing a hit, a balance or a level reads has moved, so `sim_range`, `sim_combat` and `check_levels` need no re-run.
- After the paste: the harvest merges 30 records, `gen_templates.py --check` passes with 15 new templates,
  `weapon_frames.py --check` runs the turn proof on all 15.
- **Review:** three slices fit this wave (pipeline and data; server and shared; client hands, muzzle and stage). A
  four-slice Opus review cost about 1.9M tokens in L1 (memory agent-context-cost).

## 10. Risks, and what needs Ben

- **L3-62. The ViewportFrame look is unknown until Studio.** Palette meshes read flat; the light constants (L3-58)
  will take one round from Ben's screenshot. No re-upload: Theme only.
- **L3-63. The grip and back poses are starting values.** R15 attachment frames are unchecked outside Studio; the
  Spear's butt (2.1 behind the grip) may rise to the shoulder near the camera. One round from a screenshot, Theme only.
- **L3-64. The teammate check needs two Studio clients** (L3-61). Without it, "others see your weapons" and the moving
  arm are unseen at his look.
- **L3-65. A teammate's slot switch shows at their next attack, draw or cast**, not at the key press (no stance
  remote, L3-50).
- **L3-66. The `icons` block is erased by any `assets_config.py` that predates it.** The worktrees `tycoon-c2` and
  `tycoon-m11` hold older copies: never run an asset tool there before they merge `main`.
- **L3-67. `upload_models.py` has no hash:** a weapon re-generated after its upload is silently skipped. Clear its id
  through `assets_config.save_assets` first (memory assets-direction). The icons have a hash (L3-42).
- **L3-68. Icon memory on a phone:** 15 × 512² RGBA is about 15 MB while the shelf shows. A 256-px re-render is
  content only (a re-upload and a paste).
- **L3-69. Moderation:** a Decal still in moderation harvests image 0; its card stays text until a later paste.
- **L3-70. (needs lead → Ben) Growth looks are not content only for others' weapons** (L3-55).
- **L3-71. Compile budget:** FeedbackController 162 → 163 at most.
- **L3-72. Back accessories** (capes, backpacks) share `BodyBackAttachment` with the holstered weapon. Accepted.
- **L3-73. The swing trail** stays on the hand's line, not the blade's `bladeBase` → `tip`.
- **For Ben (not blocking), at his look:** does the turning weapon read on the stage; do the weapons in hand and on
  the back look right (a screenshot if not); the icons on a phone; a teammate's weapon, if he runs two clients.
- **What Ben must do:** the one harvest paste (L3-40, step 3), any time before his look; then his look covers W1 and
  W2 together.

**Rulings: L3-40 to L3-61** (22 rulings) and **12 risks (L3-62 to L3-73)**. Four places where a brief ruling meets the
code: the icons need their own entry point (L3-42), the cast's slot needs one AbilityService line (L3-50), the muzzle
has four copies and ui B two more files (L3-52, L3-54), the stage needs `SetActive` (L3-56). One point for the lead and
then Ben: growth looks are not content only for other players (L3-55, L3-70).

## 11. Lead's rulings (2026-10-20, after reading the draft)

1. **The four (code) points are accepted as drafted:** `upload_icons.py` (L3-42), the one `AbilityService` line
   (L3-50), four muzzle copies and ui-engineer B's extra files (L3-52, L3-54), `ArmoryStage.SetActive` (L3-56).
2. **L3-55: one look, `Stage0`, for everyone in W2.** The lead tells Ben in one line that growing looks will need two
   look attributes when they come.
3. **Icons are 256 × 256, not 512 (L3-68 settled now, before any upload).** `upload_icons.py` uploads 256 × 256 RGBA
   PNGs that the pipeline engineer makes from the 512 renders with Pillow (LANCZOS, alpha kept) into
   `assets/testfit/out/Weapons/icons256/<Model>_icon.png` (gitignored, regenerated by a committed script or a flag of
   `upload_icons.py`). `icon_problems` checks 256 × 256 and keeps every other rule. **Pillow is installed** in `py`
   (12.x; `weaponstrip.py` and the lead's overview use it), so the check may decode with Pillow instead of zlib.
   About 4 MB on a phone for the shelf, a quarter of the 512 set; the cards draw at 40 design px.
4. **Review:** three slices (pipeline and data; server and shared; client hands, muzzle and stage), on Opus.
5. Every other ruling (L3-40 to L3-61) stands as drafted.
6. **Rest poses (after ui-engineer B's report, 2026-10-21).** `COMBAT_HOLD_GRIP = CFrame.identity` points every weapon
   down a hanging arm (blades 1.2–2.5 studs into the floor, guns at the ground, tracers from the knee); no one grip fits
   both rest and draw. So:
   - `COMBAT_HOLD_GRIP` is replaced by **`COMBAT_HOLD_GRIP_MELEE` = `CFrame.Angles(math.rad(90), 0, 0)`** (the tip
     forward from a hanging arm; the swing poses are unchanged and carry it) and **`COMBAT_HOLD_GRIP_RANGED` =
     `CFrame.identity`**;
   - **while a ranged family is in hand the right arm is held raised forward** at
     **`COMBAT_HOLD_RANGED_RAISE_DEGREES` = 80** (the draw angle), on the local character and on every other character
     from `WeaponHeld`; the draw and shot kicks are measured from that raised arm; a melee family in hand leaves the arm
     hanging as today. WeaponController owns the pose (ui B); Theme owns the numbers (ui A).
   - **`COMBAT_HOLD_BACK`** takes ui B's fix: `* CFrame.Angles(0, math.rad(90), 0)` between the 35° turn and the 90° X
     turn, so a bow's limbs lie across the back (ui B's report has the diff).
   - Starting values; one screenshot round expected (L3-63).
7. **T9's exit count** pins the exits **before** the `SwingOther` call (1: the empty-flight return), not the whole
   `onStrike` (4 since before W2).
