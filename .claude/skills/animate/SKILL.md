---
name: animate
description: "Give a Tripo character (Mixamo skeleton) its combat animations from the Quaternius Universal Animation Library: pick clips per game state, retime each attack to the game's windup, retarget, self-check the renders, export for Studio. Usage: /animate <character.glb> <role>"
---

# animate — one character's clip set, end to end

Arguments: `<character.glb>` (a Tripo export) and `<role>`, a key of `tools/anim/roles.json`
(`fodder`, `armoured`, `guard`, `brute`, `slinger`, `lobber`, `marksman`, `chief`, `colossus`,
`warlord`). A role is an enemy kind in `src/shared/Config/ProvingGrounds.json` `crowd.kinds`.

This skill makes animation **files**. It never edits `src/`: playing clips in the game (the crowd's
client figures choosing a clip from each body's state, with a cheaper look for far bodies) is a
milestone of its own, with contracts, started only on Ben's word.

## 0. Pre-flight

1. `"/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --version` runs.
2. The library is under `assets/` (gitignored): `UAL1_Standard.glb` from Quaternius' download
   (today `assets/3d-test/Universal Animation Library[Standard]/Unreal-Godot/`). Use the file
   **without** `_RM` (root motion makes the hips leave the spot; the game moves the body itself).
3. `tools/anim/ual_clips.json` and `tools/anim/CLIPS.md` exist. Re-run
   `py tools/anim/animate.py catalogue` only when the library file changes (about 10 s).
4. Read `tools/anim/CLIPS.md` and `tools/anim/roles.json` before choosing anything.

## 1. What the character must be

- Generated in Tripo with the **Mixamo skeleton preset**, resting in a **T-pose**, facing front,
  **empty hands** (weapons are separate models the game hangs from the hand, `WeaponModels.json`),
  hair and capes short enough not to hide the arms.
- The tool refuses anything else with an `ANIM-FAIL` line. Say it to Ben in plain words ("regenerate
  it with the Mixamo preset", "it is not in a T-pose") rather than working around it.

## 2. Choosing clips (the reasoning part)

The game already defines when each thing happens. Read the kind's `attacks` in `ProvingGrounds.json`
(`shape`, `windup`, `recover`) and pick from `CLIPS.md` by what the body is doing:

| Game state / shape | Clip family | Notes |
|---|---|---|
| rest, guard | `Sword_Idle` armed, `Idle_Loop` unarmed, `Pistol_Idle_Loop` for a gun | loops |
| chase / walk | `Jog_Fwd_Loop`, `Walk_Loop` | in place: the crowd moves the body |
| `lunge`, `arc`, `ring` | `Sword_Attack` | contact pinned to the windup |
| `shot`, `lob`, `summon` | `Spell_Simple_Shoot` with lead `Spell_Simple_Enter` | the clip starts at its release |
| `line` (marksman) | `Pistol_Shoot` with lead `Pistol_Aim_Neutral` | the lead fills the aim |
| `lane` (charge) | `Sprint_Loop` | travel only; no wind-up clip in Standard |
| hurt, headshot, death | `Hit_Chest`, `Hit_Head`, `Death01` | shared by every role (`common`) |

Rules:
- **The contact lands on the windup.** The tool stretches or squeezes the source's lead-up so its
  contact (peak hand speed, measured in `ual_clips.json`) falls exactly at `windup` seconds; the
  follow-through keeps its own speed. The windup is read from the game config at build time: never
  copy a timing into `roles.json`.
- **A clip with contact near 0 s starts at its release** and needs a `lead` clip stretched over the
  windup (the tool refuses to retime it otherwise).
- **A weapon clip must match the weapon carried.** Punches never go on an armed enemy.
- **Say every stand-in.** When Standard has no faithful clip, write a `gap` on that slot. The tool
  prints them; Ben decides whether to fill them (UAL Pro or UAL 2, Mixamo clips fit the rig directly,
  or a hand-keyed clip).
- A new role or a new clip choice is a `roles.json` edit, not code. Override a measured contact with
  `"contact": <seconds>` only after looking at the frames.

## 3. Build

```
py tools/anim/animate.py build <character.glb> --role <role> [--name <name>]
```

About a minute for ten slots. Output in `assets/anim/<name>/`: `sheet.png` (six frames per slot, the
library mannequin beside the character as the retarget check), `<slot>.gif`, `<name>_rig.glb` (rig
only), `<name>_all.glb` (every clip, any viewer), `<name>_<slot>.fbx` (one per clip, for Studio) and
`report.json`. `--clips A,B` builds ad-hoc clips with no retiming; `--no-render` skips the previews.

## 4. Review it yourself before Ben sees it

Read `sheet.png` (you see stills, not motion; say so). Check:
- the character mirrors the mannequin in every frame (a mismatch is a retarget bug, not a style issue);
- feet on the floor, no limb or the placeholder hammer through the body in a way the game would show;
- each attack's fastest, lowest frame sits at the windup; the `CHECK` lines (sink, drift, stand-ins).

Fix by changing the role (clip, `lead`, `contact`) and building again.

## 5. Show Ben

Give full absolute paths to `sheet.png` and the attack GIFs, list the stand-ins, and ask with click
questions about **feel** (heavy or snappy, which stand-ins to replace first). His eye on the motion
is the verdict; yours is the stills.

## 6. See it in Roblox (no menus for Ben)

```
py tools/anim/animate.py studio <name> --upload     # rig up as a Model (hash-checked), clip data out
rojo build animtest.project.json -o build/animtest.rbxl
```

Ben opens `build/animtest.rbxl` and presses Play: the hub with the character in front of the spawn
at its crowd kind's height, cycling every clip with a label (red HIT at the windup); `]` / `[` step,
`P` holds one clip. The clips are Bone.Transform data played by a client script
(`tools/anim/studio/`), so no Animation asset or Animation Editor step is needed. If Studio refuses
`LoadAsset` from the running game, the Output prints a one-line command-bar paste that does it in
Edit mode. The Output's `[AnimTest]` lines list what the upload holds (Bones, skinned MeshPart):
read them back if it looks wrong. The test build is never published.

The FBX files remain for Studio's own route (Avatar → Animation Editor → Import → From FBX
Animation) once clips must become Animation assets.

## Facts

- Library: CC0, 43 clips in Standard, UE-style skeleton (`pelvis`, `upperarm_l`…), T-pose rest facing
  −Y, 1.65 tall, 24 fps. Output clips are baked at 30 fps.
- The rig is slimmed to 22 bones (finger weights fold into the hands, end bones go): the game never
  animates fingers and every bone costs per raider.
- Retarget: each bone copies its source bone's world rotation change from rest; hips' travel scales by
  hip height. Exact while both rigs rest in a T-pose facing the same way (the tool checks both).
- The sheet and GIFs need Pillow: run `py tools/anim/animate.py` (no shebang, so `py` picks the Python
  that has it).
