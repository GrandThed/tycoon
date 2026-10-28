---
name: art-direction-2026-10-26
description: Ben started generating assets with Tripo 3D (BotW-like low-poly fantasy test); enemies come rigged on the Mixamo preset and animate from the Quaternius UAL through the /animate skill; nothing in the game uses them yet
metadata:
  type: project
---

On 2026-10-26 Ben began generating assets with **Tripo 3D** to define an art style: "close to low poly and
fantasy, some of Breath of the Wild". The lead's style prefix and eight test prompts (Camp Chief, Colossus,
Frost Hammer, Flamethrower, Windmill small/grand, cliff rocks, oak, Launch Tower) were the start. Ben: the
items came out "fantastic"; the enemies lost body parts behind hair and held weapons.

- **Enemies: T-pose, empty hands, Mixamo skeleton preset** (Tripo also offers ActorCore, UE5 Mannequin,
  VRM, Unity Humanoid). Weapons are separate items, as the game already hangs them from the hand.
  Triangles for static assets; quads only for models that will be edited or rigged.
- **Animation: Ben chose the Quaternius Universal Animation Library (CC0)** over Mixamo's clips. The free
  Standard pack (43 clips, one weapon attack) is in `assets/3d-test/Universal Animation Library[Standard]/`.
  Retargeting onto the Mixamo rig is exact (both T-pose, facing −Y). Ben on the first retarget: "wow, they
  look amazing".
- **`/animate <character.glb> <role>`** (`.claude/skills/animate/`, tools in `tools/anim/`) picks clips per
  enemy kind (`roles.json`), pins each attack's contact to the windup in `ProvingGrounds.json`, renders a
  sheet with the library mannequin beside the character, exports a rig GLB plus one FBX per clip.
  First character: the bandit boss `assets/3d-test/fantasy+warrior+3d+model.glb` (5,447 triangles,
  0.93 tall) → `assets/anim/bandit_chief/`.
- **Gaps in Standard:** a horizontal sweep (the Chief's own move), a ground slam, a charge wind-up, an
  overhand throw, a bow, a block. Recorded as `gap` per slot.

- **Ben asked to redo every Expeditions asset with Tripo** (2026-10-26): the prompt list is
  `docs/TRIPO_PROMPTS.md` (raiders in T-pose, their gear and the Chief's own hammer separate, 15
  weapons by level family, forest props; the generated ground, hills and canopy stay generated). The
  plated elite's planks are a separate item because the client hides them when the plate breaks.
- **Studio test without menus:** `animate.py studio <name> --upload` uploads the rig (Open Cloud took
  the skinned GLB; the Chief is asset 87002081908838) and writes Bone.Transform clip data;
  `animtest.project.json` → `build/animtest.rbxl` stands him in front of the hub spawn, cycling clips.

- **Verified in Studio 2026-10-27** (two Plays in `build/animtest.rbxl`, Ben: "wow, incredible!" after the
  cross-fade): runtime `InsertService:LoadAsset` works from the running game (no paste needed), the Open
  Cloud upload kept the skin (MeshPart skinned, 22 Bones, plus an AnimationController the importer adds),
  scale x15.0 to 14 studs. Bone.Transform playback with a smoothstep cross-fade (0.12 s into an attack,
  0.25 s otherwise, `F` toggles) is the approved feel.

**Not done:** nothing in `src/` plays these clips
(raiders are still rigid pieces posed by `RaiderPose`). Wiring animated enemies into the crowd renderer,
with a cheap look for far bodies, is a future milestone, only on Ben's word. Whether the new style
replaces the shipped Kenney look everywhere or only in the missions is undecided.

**First batch and self-rigging (2026-10-27/28).** Ben's credits ran out after one batch (23 models: all seven
raiders, all their gear but the plate, 8 player weapons, one fir), sorted into `assets/tripo/{raiders,gear,weapons,
props}/` (gitignored); the plate was shown as an image but never exported. Only the Chief came rigged. Ben chose
"lets see what you are capable of in blender" over Mixamo's free auto-rigger: `animate.py rig`
(`tools/anim/autorig_blender.py`) measures the joints from a surface sample and takes weights from a closed proxy
(solidify + voxel remesh, heat weights, data transfer), because heat weighting fails on Tripo's hundreds of open
shells. All six built clean (feet sink 4-5% on the slinger's run and the armoured's run/attack: leg proportions,
not visible on the sheets). Ben on the hand-fitted fodder: "looks excellent". Tripo's rigged Chief arrives facing
+X; `rig` only turns it. Textures are 4096 px (Roblox caps at 1024: shrink before upload). The sphere seen on
every import is Blender's glTF importer, not Tripo.
- **MCP for Blender** (`mcp-for-blender` 2.2.4, user scope, `DISABLE_TELEMETRY=true`) drives Ben's live Blender;
  register it at user scope (local scope keys the folder as `C:/` from a terminal and `c:/` from VS Code, so it
  never shows), from Bash (PowerShell's `claude` shim eats `--` and `--%`). Blender Lab's own "MCP" extension
  uses the same port 9876: keep it disabled. The add-on's server stops when Blender restarts (Start MCP Server).
- **Crowd bench (2026-10-28, `build/animbench.rbxl`, Ben's PC, graphics Automatic):** 160 skinned Chiefs (crowd.maxAlive,
  5,447 tris each) held 60 fps in every phase; client script cost 1.8 ms with every body posed every frame, 0.6 ms with
  LOD (near every frame, past 35 studs every 3rd, past 70 every 10th, unblended), ~0.44 us per bone. A rig built into
  the place file by Rojo (`animate.py template`, hand-written rbxmx with HasSkinnedMesh + Bones) skins and animates
  ("they where moving", with a screenshot): no runtime LoadAsset needed. Phones unmeasured (assume 3-5x): LOD is the
  plan. Studio caps at 60 fps and reports no GPU time. The 1,328 "Asset type does not match" lines come from the hub
  content the bench place copies (same count with and without the template), not from the rig.

**Why:** a fresh session would otherwise re-run the style and retarget experiments or wire clips into the
game without a contract.

**How to apply:** for any new Tripo enemy run `/animate`; for a style question start from the prompts'
prefix in this session's record and ask Ben. See [[l4-real-forest-2026-10-21]], [[assets-direction-2026-09-15]].
