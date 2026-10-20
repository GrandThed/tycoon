# L3 study, Part B: the Armory screen and the weapon models (report)

Branch `l3-armory`, read at `b0a0769`. No code was written. Part A (tiers, economy, profile, loadout) is covered
elsewhere; this report uses its results only where the screen needs them (each family's window, its cost, the
Forest drops, the remotes). Line numbers refer to that commit.

## 1. The Armory UI today

**Two separate panels, one per place. They share no code.**

| | Hub `src/client/UI/ArmoryPanel.luau` | Lobby `src/combat/client/UI/ArmoryPanel.luau` + `ArmoryWeapons` + `ArmoryAbilities` |
|---|---|---|
| Size / top-level locals | 651 lines / 14 | 518 / 22, 646 / 24, 372 / 16 |
| Shows | Max HP and a wallet chip per material band. One row per **slot**: name, tier, damage, HP, the next tier's cost and income gate; Ascend rows after a rebirth (`:1-12`, `paintRow :457-585`) | Weapons tab: two columns of **owned** family cards (name, element chip, one 48 px button per variant), **no tier and no damage** (`ArmoryWeapons :6-23`). Abilities tab: Double Jump rows with Buy (`ArmoryAbilities :1-12`) |
| What is listed | the two slots | owned families plus unowned ones a secret or `Expeditions.json found` names (`Columns :149-211`, filter `:167-171`, `HiddenWhere :111-144`): 4 of the 15 today |
| Remotes | `RequestBuyGear(slot)`, `RequestAscend(slot)` (`UIController.luau:676-691`) | `RequestSetFamily(slot, family, variant)`, `RequestBuyAbility(id)` (`CombatUIController.luau:1549-1590`) |
| Frame | `Panel` + `PanelDock`: portrait a 340 × ≤430 bottom sheet, landscape a right column 260–340 wide (`PanelDock.luau:25-65`, `Theme.luau:89-98`) | one 340-wide sheet over a scrim, centred; height fits the page, the page scrolls (`ArmoryPanel :18-22`, `Theme.luau:1332-1341, 1392-1412`) |
| Input | Bottom-bar tap only; the hub binds no keys or pad buttons (no `KeyCode` in `UIController.luau`) | **K** (`CombatUIController.luau:2224-2226`), the phone HUD's "Armory" button (`:1650-1661`), pad **Y** toggles (lobby only), **B** closes, **LB/RB** tabs (`ArmoryPanel :12-17, 83-87`). Lobby only (`SetLobby`); closes the map; unlocks the cursor (`HOLD_ARMORY`, `:1572-1580`) |

- **Sharing between places.** `combat.project.json:65-73` maps `src/combat/client/UI` and adds six hub files as
  explicit children (Create, Motion, Toast, LoadScreen, Theme, MapScreen). Rojo does not merge an explicit child
  into a `$path` folder holding a same-named file; it makes two instances (memory coop-2026-09-23). A shared
  screen needs names absent from `src/combat/client/UI` (`ArmoryPanel` is taken). MapScreen is the precedent:
  pure, shared, handed config and state, intents out through `Deps` (`MapScreen.luau:1-14`).
- **Compile gate** (`py tools/check_compile.py --counts`: PASS, 174 files). Host modules: FeedbackController 162,
  InputController 158, CombatFxController 126, CombatUIController 106, WeaponController 76, hub UIController 51
  (budget 180). The screen goes in new modules; Feedback and Input gain no top-level locals.
- **Design space.** Scale = `clamp(min(w/375, h/667), 0.9167, 1.8)` (`CombatUIController.luau:363-372`; `MIN_SCALE`
  44/48, `Theme.luau:41-49`). With a 58 px top inset and 8 px margins: 667×375 → **712 × 330** design px;
  640×360 → **682 × 313**; 375×667 → 393 × 648; 1920×1080 → about 1253 × 667. Neither project sets
  `ScreenOrientation`, so phones run Roblox's default landscape; portrait matters only for the hub's sheets.
  MapScreen does not lay out portrait (`MapScreen.luau:22-26`).

## 2. The L0 picture (Ben, 2026-10-13: "a screen in both experiences")

`assets/research/2026-10-13-missions/expeditions-mockups.html` (CSS `:62-75`, markup `:228-256`, script
`:263, 365-417`).
- **Shows:** a stage (SVG weapon art on a radial blue gradient, name, slot, a big "T3"); a track of 20 pips in
  five bands of four coloured by level theme (Forest, Castle, Underworld, Planet, Dream), arrival tier outlined;
  a detail list (Next "more damage, more health"; Cost `[10, 40, 100, 180]` band drops, the 4th also "the boss's
  trophy (Hard)"; Drops in; Styles "free to switch"; Ability); for unowned "Found …" and "Arrives at Tier N";
  an Upgrade button; a shelf grid (art, name, "Tier N" / "Not found yet"); an Abilities tab of three cards.
- **Out of date:** every track runs to 20 (wrong since 2026-10-20); the Flamethrower from a "First Hard clear"
  (now the lookout chest); Double Jump at 20 Valor (now 10).
- **Cheap:** tabs, pips, text, buttons, the gradient (`UIGradient`), the Abilities cards (they exist).
- **Not cheap:** the art (15 real models, §5); a turning stage (no ViewportFrame anywhere in `src/`); a thumbnail
  per shelf card; the start/top marks, costs and trophy rule (all Part A's numbers).

## 3. The weapon shown large, in 3D, turning

**ViewportFrame.**
- API: `Ambient`, `LightColor`, `LightDirection`, `ImageColor3`, `CurrentCamera`, `CaptureSnapshotAsync`
  (`tools/types/globalTypes.d.luau:12928-12937`). One directional light plus ambient. The Lighting service,
  shadows, PointLights, particles, Beams and Trails are not drawn: a pilot flame or frost glow must be mesh.
- Palette colours read flat, and Blender strips will not predict the look: expect one Studio round on Theme
  light constants (no re-upload).
- Cost: one viewport, one model ≤ 4k triangles, re-rendered every frame while it turns. Small next to the world
  behind the scrim, but unmeasured. Turn only while open; turn the camera, not the model; drag-to-turn is cheap
  and suits "contemplative". Gate the turn on `Theme.lowEndDevice`, **never** `reducedMotion`, which is true on
  every touch device (`Theme.luau:1516-1518`): no phone would ever see it turn.
- Dark steel vanishes on the panel colour (30, 41, 70) (`Theme.MAP_COLOR_PANEL`), the dark-pitch trap again
  (memory assets-direction). Keep the L0 lighter radial behind the stage and judge the strips on it.

**Before models exist** ("missing degrades to a placeholder"): with no `Assets/Props/Weapons/<family>`, the stage
shows the family name large with its element chip, shelf cards are text, hands stay empty as today. No Part
blockouts: dead code once models land.

**The shelf of 15.**
- Unowned = dark: `ImageColor3` near-black on a viewport or an icon is a free silhouette. The hint is the
  existing `found` text (`Expeditions.json:12-14`, `ArmoryWeapons.HiddenWhere`). 11 of 15 families have no
  source, so each needs a `found` entry from Part A, else the `Columns` filter hides it.
- Thumbnails: 15 live viewports on a phone are the unmeasured risk. Use **15 Blender-rendered icons uploaded as
  Decals** in the same run. The route exists (`upload_paths.upload_decal :106-123`; the harvest resolves a Decal
  to its image id, `harvest.py:123-128`). It needs an icon kind and its own alpha check, since the path check
  rejects alpha (`upload_paths.py:99-100`). `CaptureSnapshotAsync` at open could replace the uploads: unverified,
  try it in Studio.

**The tier track shows a window.** Lit = owned, open = in the window not yet bought, dashed = outside it; start
and top marked; at the top "At its peak"; a relic is one lit pip at 20. Next tier: "T5: 45 → 58 dmg · +HP 30 →
40", its cost, the level that drops the material, the trophy. The screen needs one pure shared function from
Part A for damage and HP per (family, tier); the client colours buttons with it, never decides, as `Armory.CanBuy`
does today (`hub ArmoryPanel.luau:8-12`).

**Layout A, "Showcase"** (the L0 order; recommended). Fits 682 × 313: header 48, middle 175, shelf 64.

```
+--------------------------------------+
|[Weapons][Abilities]               [X]|
|+-----------+ LONGBOW   ranged   T4   |
||           | |####|##..|----|----|   |
||  3D bow,  | Next T5: 45 -> 58 dmg   |
||  turning  | 120 Timber, Forest Road |
||           | Ability: Arrow Rain     |
|+-----------+                         |
|[A Pierce][B Quick] [Equip][UPGRADE]  |
|--------------------------------------|
|<[Swd][Ham][Bow][Spl][Flm][ ? ][ ? ]> |
+--------------------------------------+
```

**Layout B, "Rack"**: the shelf as a scrolling rack on the left, stage and details on the right; smaller stage.

```
+--------------------------------------+
|[Weapons][Abilities]               [X]|
| MELEE  RANGED |+--------+ LONGBOW T4 |
| [Swd]  [Bow]  ||        | |####|##..||
| [Ham]  [Spl]  || 3D bow | Next T5    |
| [Spn]  [Flm]  ||        | 45->58 dmg |
| [Axe]  [ ? ]  |+--------+ 120 Timber |
| [Spr]  [ ? ]  | [A][B] [Eqp][UPGRD]  |
| [Frz]  [ v ]  | Arrow Rain           |
+--------------------------------------+
```

**Layout C, "Two steps"**: the shelf fills the screen; a card opens a big stage; Back returns. Biggest stage,
one more tap per weapon, pad B means Back.

```
+--------------------------------------+
|[Weapons][Abilities]               [X]|
| MELEE                                |
| [Sword][Hammer][Spin][Axe][Spear][?] |
| RANGED                               |
| [Bow][Split][Flame][ ? ][ ? ][ ? ] > |
+--------------------------------------+
   tap a card:
+--------------------------------------+
|[< Back]   LONGBOW   T4            [X]|
| +-------------+ |####|##..|----|     |
| |  3D bow,    | Next T5: 45 -> 58    |
| |  big, turns | 120 Timber           |
| +-------------+ [Equip] [UPGRADE]    |
+--------------------------------------+
```

Portrait stacks every layout: stage 393 × 200, details, a 5 × 3 shelf (about 620 of 648 px). In the hub the
screen covers the bottom bar like a card and closes with X.

## 4. Weapons in hand today

- **Empty hands.** `WeaponController` clones `Assets/Props/<band eraName>/<model>`, named by the old C0 **slot
  tier** (`:5-7, 138-163, 233-252`; `WeaponSwordI` … `WeaponRailI` in `Armory.json slots.*.tiers[].model`). No such
  template exists (`templates/_props` holds only the four eras' dressing), so every tier is bare-handed,
  silently. These names die with the slot tiers.
- **Drawing.** A trail between two hand attachments marks a swing; the procedural pose turns the right shoulder's
  Motor6D C0 (windup −55°, strike 95°, draw 80°, kick; `:5-14, 455-525`, Theme `COMBAT_SWING_*`). Tracers and
  flashes start at **RightHand**, in three copies: `WeaponController.muzzlePoint :629-633`,
  `FeedbackController.muzzleOf :838-852` (flight blended from hand to shot line, `:231`), `FlameFx.muzzleOf :99-112`.
- **Others see nothing.** WeaponController is local-only: "nothing written here replicates" (`:20-23`), and a
  client-set C0 does not replicate. The remote arm pose `SwingOther` is fed only by the old `CombatService` swing
  effect (`CombatFxController.luau:1126-1133`, `CombatService.luau:336`), which is no longer booted
  (`combat Main.server.luau:14-16`): today **no other player's arm ever swings**. The server does not know the
  held slot (no stance remote; `RequestRangeAttack` carries the family, `CombatRemotes.luau:221-233`).

**Proposal (lead ruling, not Ben's).** WeaponService writes character attributes `WeaponMelee`/`WeaponRanged`
(families, on each loadout change) and `WeaponHeld` (slot, from each accepted attack, draw or ability). Every
client hangs the held model on `RightGripAttachment` and the other on UpperTorso's `BodyBackAttachment` (standard
R15). The local player follows its own stance at once (`InputController.setStance :895-910` →
`WeaponController.SetStance :793-801`). FeedbackController calls `SwingOther` on another player's weapon strike, so
visible weapons do not hang still. Cost: one luau-engineer file, about 4 attribute writes per stance change; at
most 8 models on screen (party ≤ 4, `Combat.json:38`).

**What must not move.**
- **The shot origin** is `shotRay`, the crosshair line at the head's depth (`InputController.luau:1101-1105`, sent
  at `:1695`), judged against walls on the server (`WorldReact.AimClear`, `shooting.originWallChord`; INTERFACES
  "L2 W2 contracts").
- **The melee swing** resolves at `rig.root.Position` along the flat camera heading (`:1729-1731`);
  `FeedbackController.PredictSwing` draws its hitbox from exactly that (`:60-71`).
- The model is decoration, never a ray start or an arc centre. A `Muzzle` attachment may replace RightHand as
  where a tracer starts, through **one** shared helper so the three copies cannot disagree. Parts stay
  CanCollide/CanQuery/CanTouch false and Massless, as `attachTo` does (`WeaponController.luau:196-231`); that
  matters with the camera 1.75 studs right of the shoulder (`Combat.json:199`).

**Limits of the pose.** Two-handers (Warhammer, Greataxe, Spear) and the bow are posed by the right arm alone
(`findShoulder :518-525`): acceptable for L3; an animation pass waits on the unverified ids in `Combat.json`. The
grip offsets (`COMBAT_GRIP_*`) were written for a prop that never existed: expect one tuning round from a
screenshot.

## 5. A generated weapon kit

**Route, no project change.** `templates/_props/<Folder>/` is mapped to `ReplicatedStorage/Assets/Props` in
**both** places (`default.project.json:14-18`, `combat.project.json:14-19`). For props, `--era` is only a folder
name: `merge_stages.py:521-522` skips the era config, `upload_models.py:229-244` and `assets_config.ensure_prop
:141-153` key by the name, `gen_templates.py:398-413` takes any key. So `--props --era Weapons` should give
`Assets/Props/Weapons/<Family>` in both places; prove it with `--dry-run` first, which **writes `Assets.json`**
(memory street-upgrades), so nobody else may own that file then.

**Template facts.** A prop template is a Model with an invisible 1 × 0.2 × 1 `Base` and one `Stage<n>` per stage
(`gen_templates.py:85, 197-234`), so the client can pick a look by tier with no new route. Props are Plastic
(`:184`): a glowing crystal or nozzle needs a small per-kit material change.

**Generator pattern.**
- A committed Blender script (`tools/assets/weapon_kit*.py`) writes GLBs into the gitignored
  `assets/kenney3d/weapon-kit/Models/GLB format/`; the folder convention is the registration. Colour-only
  materials go through `palette.py`; after a colour redesign delete `assets/build/palettes/weapon-kit.*`
  (memory orbital-dressing).
- **1 glTF unit = 1 stud** (`people_kit.py:24`); one-piece blueprints like the walkers. Frame contract: grip centre
  at the origin, point or muzzle along −Z, top +Y. `gen_templates` handles the 180° template turn; the client
  never compensates (memory template-turn).
- `testfit` renders one three-quarter camera on a ground card (`testfit.py:208-215, 476-482`). Weapons need a
  side view, a 5-stud R15 silhouette for scale and the panel colour behind: a small testfit option.

**Scale and budget.** The R15 avatar is about 5 studs (`people_kit.py:21`). Proposed lengths: sword 3.6–4.0,
hammer/axe haft 3.8–4.5, spear 6–7, bow 3.6–4.0 tall, guns 2.4–3.4, launcher ~3.6, flamethrower ~3.2 plus a tank.
Today's 479 prop stages run median 592, max 5,164 triangles (merge sidecars, `assets/build/stages/_props`).
Proposed for "detailed": 1,500–3,500 per weapon, cap 5,000; worst case on screen ~28k, against 61,913 for a full
Metropolis near plot (memory metropolis-growth). Flat palette means no metal sheen: detail comes from shape
(bevels, wraps, fletching, rivets).

**How many.** Every option is **one harvest paste**:

| Option | Model uploads | Icons | Builder effort |
|---|---|---|---|
| One look per family | 15 | 15 | ~3 Opus builder sessions |
| Grows over its window: 3 additive stages (start, middle, top), like the buildings | 45 | 15 | ~2.5× |
| A look per band crossed | ~25–35 (Part A's windows) | 15 | ~2× |
| 15 × 5, every band | 75: rejected, most windows cross 1–2 bands | | |

Names fit Open Cloud's 50-character cap ("EraCityTycoon_Prop_Weapons_flamethrower_S0" is 43). `upload_models` skips
any stage with a non-zero id: changed geometry needs its id cleared via `assets_config.save_assets` (memory
assets-direction).

**Who builds.** Three Opus builders (`general-purpose`, `model: "opus"`), disjoint families, each with its own
generator file (`weapon_kit_blades.py`, `_bows.py`, `_guns.py`) and one shared committed colour module, briefed
from a file in the build-assets pattern; own scratch folders. Ben approves a contact sheet of strips before any
upload (`.claude/skills/build-assets/SKILL.md` §2.5). The lead runs merge, upload, the paste and templates, and
saves the clipboard to a file first (memory orbital-growth).

## 6. Decisions for Ben

**B1. Screen layout** (sketches in §3). **A, Showcase** (recommended): what he saw at L0, all on one screen.
B, Rack: smaller stage. C, Two steps: biggest stage, one more tap per weapon. All cost about one ui-engineer wave.

**B2. Tier track for a window.** **1, the full ladder with the window lit** (recommended): "tier 9 is the same
strength for every weapon" is his rule, and this shows where each weapon sits. 2, only the window's pips:
bigger, but no comparison at a glance. 3, both: 24 more px of height on a phone.

```
1. Full ladder, window lit
  Forest Castle Under Planet Dream
 |####|##..|----|----|----| Longbow 1-6
 |----|----|##..|....|----| Rifle  9-16
 |----|----|----|----|---#| Relic   20
2. Window only, big pips
 Longbow  [1][2][3][4][5][6]
           #  #  #  #  .  .
 Relic    [20] at its peak
```

**B3. Models: how many, when.** **1, all 15, one look each** (recommended): 15 uploads + 15 icons, one paste; the
code picks `Stage<n>` by tier from the start, so option 2 can follow as content only (uploads and a paste, no
code). 2, all 15 grow over their window in 3 looks: 45 uploads, ~2.5× builder time, 45 strips to judge. 3, only
what the Forest gives now (Broadsword, Longbow, Flamethrower, Frost Hammer, plus any Part A adds), the rest "?"
cards until their level exists: cheapest, but the shelf's dark outlines become question marks.

```
1. One look        T1 ------------ T6
                   [  same sword   ]
2. Grows (3)       T1     T3-4    T6
                   plain  +guard  +gold
                   blade  +wraps  +runes
3. Forest only     [Swd][Bow][Flm][Frz]
                   [ ? ][ ? ][ ? ] ...
```

**B4. House style** (same cost; option 2 adds swatches to one palette). 1, one style for all 15: steel, leather,
brass; fire orange, ice blue crystal. **2, dressed by where it is found** (recommended): Forest wood, bone, rope,
flint; Castle steel, crest, gold; Underworld black iron, embers; Planet alloy, glow strips; Dream crystal,
pastels. The shelf then reads as the path of five levels. Option 2 needs Part A's home level per family;
without it, ask for 1.

Lead rulings, not asked: others see your weapons; held in the right hand, the other on the back; icons on the
shelf, not live viewports; K in the hub too, pad Y in the lobby; the hub screen is a full-screen card.

## 7. Risks, said plainly

1. **ViewportFrame is new here** and the lead cannot see Studio: how palette models read in it is unknown until
   Ben looks; Blender strips do not predict it.
2. **The turning stage on a phone** is unmeasured. Gate on `lowEndDevice`, never `reducedMotion`.
3. **Grip and facing** rest on the template turn and R15 attachment frames, unchecked outside Studio: one tuning
   round expected.
4. **Assets are the critical path:** Ben's strip approval, then a paste; each fix after upload costs a cleared id,
   a re-upload and a paste; the palette cache trap.
5. **The hub is live.** The shared screen reaches players only when Ben publishes the hub, which waits for Part
   A's profile step. Explicit Rojo child names must not collide with `src/combat/client/UI`.
6. **Compile budget:** FeedbackController 162, InputController 158: the muzzle helper and the remote swing add no
   top-level locals there.
7. **Gamepad A on a screen button may also jump**, still open from L2 (PLAN "L2 W2" carried: "gamepad A on Equip
   must not walk the character"). Sink A while the screen is open.
8. **"Detailed" without sheen:** flat palette may read as toys. Show strips on the panel colour beside the R15
   silhouette before upload.
9. **Visible weapons expose two things already true:** other players' arms never swing; two-handers are held in
   one hand.
10. **11 of 15 families have no source yet:** the shelf hints and B4 depend on Part A.

## 8. Wave split (Part B's side; each wave playable alone in Studio)

| Wave | What | Owner | Playable as |
|---|---|---|---|
| **S1 the screen, grey** (with Part A's tier wave) | Shared `src/client/UI/ArmoryScreen.luau` + `ArmoryStage`/`ArmoryShelf`/`ArmoryTrack` (new names), Abilities page moved in, Theme `ARMORY_SCREEN_*`; placeholder stage; window track, upgrade, styles, equip; lobby `ArmoryPanel`/`ArmoryWeapons` retired; explicit children in `combat.project.json` | ui-engineer (+ lead for the project file) | K in the lobby: windows shown, a weapon upgraded with Forest drops |
| **S2 the kit** (day 1, in parallel) | `weapon_kit_*.py`, 15 one-piece blueprints under `_props/Weapons/`, testfit side view + R15 silhouette, strips → **Ben's approval** → merge, upload, icons, **one paste**, templates | 3 Opus builders; lead runs the pipeline | strips and a contact sheet (approval due around the end of S1) |
| **S3 models in the game** | ViewportFrame stage (turn, drag, light constants, silhouettes), shelf icons, `WeaponController` per-family templates + holster from attributes, one muzzle helper, `SwingOther` from strikes; server attributes in `WeaponService` | ui-engineer (client), luau-engineer (one server file + Types) | Studio look: the stage, in hand, a teammate's weapon |
| **S4 the hub** (after Part A's profile/hub wave) | Shared screen in the hub (bottom-bar Armory, K); hub `ArmoryPanel` retired | ui-engineer | same screen in the hub; live only when Ben publishes the hub |

Order: S1 and S2 together, then S3, then S4. Each step that passes review and QA merges to `main`, as in L1 and
L2. The Expeditions publish freeze holds until L4.
