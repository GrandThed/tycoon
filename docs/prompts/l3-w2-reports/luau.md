# L3 W2 — luau-engineer report

Branch `l3-w2` in `C:\Users\benja\Desktop\tycoon-p5`. Nothing committed. The lead's rulings 6 and 7 (§11) are included.

## Gates (final, 2026-10-21)

| Gate | Result |
|---|---|
| Harness (`run_harness.py`, with the shipped `WeaponModels.json`) | `HARNESS: PASS (3,950 checks)` |
| `mutate.py … l3w2` | **138 run, 0 not caught**: 41 in `"l3w2: "` (WeaponLook) and 97 in `"l3w2 "` (T1–T14 and ruling 6), each with a passing baseline |
| `py tools/check_compile.py` | PASS, 180 files |
| stylua | clean on my files |
| selene | clean on my files |
| luau-lsp, both trees (scratch sourcemaps, `tools/types/globalTypes.d.luau`) | 0 diagnostics |

- Every pure mutant is caught by a pure case, never only by a text count.
- Every file is LF.
- On the server only WeaponService (+52/−3) and AbilityService (+1) changed. Nothing else on the server moved.

## Files created or changed

**Source**
- `src/shared/WeaponLook.luau` (new). Pure. Its only require is `Types`.
- `src/shared/Types.luau`:
  - `WeaponModelDef` and `WeaponModelsConfig`, after `RangeLoadout`;
  - `AssetIcon`, and `AssetsConfig.icons` with a v5 comment.
- `src/shared/Catalog.luau`: `GetWeaponModelsConfig()`. It is optional and cached like `GetAssetsConfig`.
- `src/combat/server/Services/WeaponService.luau`:
  - the `WeaponLook` require;
  - `Shooter.held`, set to `"melee"` in `AddPlayer`;
  - `showWeapons` and `noteHeld`, under the "Players" header;
  - the calls in `PrepareCharacter`, `SetFamily`, `OnAttack` and `OnDraw`;
  - `WeaponService.NoteHeld`, among the AbilityService hooks.
- `src/combat/server/Services/AbilityService.luau`: the one `NoteHeld` line.

**Harness**
- `tools/crowd_harness/tests_l3_w2.luau` (new). It runs last and prints the verdict.
- `tools/crowd_harness/run_harness.py`:
  - `WeaponLook` in `SOURCES`;
  - the test file in `TESTS`;
  - the fixture `weaponModels`, read through `read_optional`, so a missing file fails a case instead of crashing;
  - `l3w2_reading` (`L3W2_BODIES`, `L3W2_LINES`, `L3W2_PATTERNS`, `L3W2_ORDER`, the `branch` helper), exposed as `source.l3w2`;
  - the docstring.
- `tools/crowd_harness/mutate.py`:
  - `L3W2_MUTATIONS`, with 138 entries;
  - new files in `FILES`: `WeaponLook`, `Config/WeaponModels.json`, `RangeService`, `HeldWeapons`, `WeaponController`, `FlameFx`, `AbilityFx/Shared`, `AbilityFx/MagDump`, `ArmoryStage`, `ArmoryScreen`.

## Contracts implemented

```luau
-- WeaponLook (L3-48)
WeaponLook.ATTRIBUTES: { melee: string, ranged: string, held: string }  -- frozen: WeaponMelee / WeaponRanged / WeaponHeld
WeaponLook.ModelName(family: string): string
WeaponLook.Def(models: Types.WeaponModelsConfig?, family: string): Types.WeaponModelDef?
WeaponLook.Point(def: Types.WeaponModelDef, name: string): Vector3?
WeaponLook.IconId(assets: Types.AssetsConfig?, models: Types.WeaponModelsConfig?, family: string): number
WeaponLook.Values(loadout: { melee: string, ranged: string }, held: string): { [string]: string }
WeaponLook.Read(get: (name: string) -> any): (string?, string?, string?)
WeaponLook.Problems(models: Types.WeaponModelsConfig?, weapons: { [string]: any }): { string }
-- Catalog
Catalog.GetWeaponModelsConfig(): Types.WeaponModelsConfig?
-- WeaponService (L3-49, L3-50)
local function showWeapons(shooter: Shooter, character: Model?): ()   -- the contract's body, verbatim
local function noteHeld(shooter: Shooter, slot: SlotName): ()          -- verbatim
function WeaponService.NoteHeld(player: Player, slot: string): ()      -- verbatim
```

**New requires.** WeaponService now requires `Shared/WeaponLook`, and WeaponLook requires only `Types`. AbilityService
needed no new require (it already required WeaponService). There is no cycle.

The harness also checks the client's require graph as text:
- WeaponController requires neither FeedbackController nor InputController;
- HeldWeapons requires none of the controllers that call it.

## Pinned lines, exact text (`\t` = tab, `\n` = newline)

**T1, `showWeapons`:**
- `\tlocal target = character or shooter.player.Character\n\tif target == nil then\n\t\treturn\n\tend\n`
- `\tfor name, value in WeaponLook.Values(shooter.loadout, shooter.held) do\n\t\ttarget:SetAttribute(name, value)\n\tend\n`
- `local function showWeapons(shooter: Shooter, character: Model?): ()`
- Counts:
  - 1 exit;
  - 4 `showWeapons(` in the file (the definition and 3 calls);
  - 1 `WeaponLook.`;
  - 2 writes to `.loadout.melee/ranged`, both in SetFamily.

**T2, `PrepareCharacter`:**
- `\tlocal shooter = state.shooters[player]\n\tif shooter ~= nil then\n\t\tresetAir(shooter)\n\t\tshowWeapons(shooter, character)\n\tend\n`
- `\tif not state.active then\n\t\treturn\n\tend\n`, its only exit (1).
- How it is reached, three places:
  - AddPlayer's `\t\tif character ~= nil then\n\t\t\tWeaponService.PrepareCharacter(player, character)\n\t\tend\n`;
  - RangeService `prepareCharacter`'s `\tWeaponService.PrepareCharacter(player, character)\n`;
  - WaveService's `ArenaService.SetCharacterHook(WeaponService.PrepareCharacter)`.

**T3, `SetFamily`:**
- `\tif slot == "melee" then\n\t\tshooter.loadout.melee = family\n\telse\n\t\tshooter.loadout.ranged = family\n\tend\n\tshooter.drawStartedAt = 0\n\tshowWeapons(shooter, nil)\n\ttuneStateFor(shooter)\n\tif previous ~= family then\n`
- The slot line `local slot: SlotName = if def.slot == "melee" then "melee" else "ranged"`.
- 3 exits.

**T4, `OnAttack`:** `\tshooter.lastSeq[slot] = seq\n\tnoteHeld(shooter, slot)\n`, plus the slot line. 12 exits, all of them refusals
before the acceptance.

**T5, `OnDraw`:** `\tshooter.drawWeapon = weapon\n\tnoteHeld(shooter, slot)\nend`, plus the slot line. 3 exits.

**T6, `AbilityService.OnCast`:**
- `\tcaster.lastSeq = seq\n\tWeaponService.NoteHeld(player, slotName)\n`
- `local slotName: SlotName = if slot == "melee" then "melee" else "ranged"`
- 1 `WeaponService.NoteHeld(` in the file.
- 9 exits.

**T7:**
- `noteHeld`: `\tif shooter.held == slot then\n\t\treturn\n\tend\n\tshooter.held = slot\n\tshowWeapons(shooter, nil)\nend` (1 exit).
- `NoteHeld`:
  - `\tlocal shooter = state.shooters[player]\n\tif not state.active or shooter == nil or (slot ~= "melee" and slot ~= "ranged") then\n\t\treturn\n\tend\n`
  - `\tnoteHeld(shooter, if slot == "melee" then "melee" else "ranged")\n` (1 exit).
- 4 `noteHeld(` in the file.
- 1 write to `.held` (in noteHeld).
- AddPlayer's `\t\theld = "melee",\n`.

**T8:** the pattern `\.held\b|\bshowWeapons\b|\b[nN]oteHeld\b|\bWeaponLook\b` counts 0 in each of `damageScale`,
`meleeOrigin`, `aimAllowed`, `claimSlack`, `resolveMelee`, `resolveRanged` and `strike`. It reads the code with comments
blanked, and every one of those bodies must be found.

**T9, the lead's ruling 7:**
- `WeaponController.SwingOther(strike.userId, strike.step or 1)` sits inside the `\telseif swing and not mine then`
  block. The block is read up to the next `elseif`, `else` or `end` at the same indentation.
- That call appears once in the file.
- The `local WeaponController = require(` line appears once.
- The inputs `\tlocal mine = strike.userId == localUserId()\n` and the `local swing = …` line are pinned.
- The wiring in `applyFx` (`onStrike(strike)`) is pinned.
- **`strikeExits` = 1**: the exits of `onStrike` *before the SwingOther call*.

**T10, aligned with ui B's diff and report:**
- FeedbackController:
  - no `"RightHand"`;
  - no `local function muzzleOf(`;
  - 7 `(HeldWeapons.Muzzle(` and 7 `HeldWeapons.Muzzle(` in all.
- FlameFx:
  - no `"RightHand"`;
  - `\tlocal point, fromModel = HeldWeapons.Muzzle(userId)\n`;
  - `\tif point == nil or fromModel then\n\t\treturn point\n\tend\n\treturn point + aim * MUZZLE_FORWARD\n`.
- AbilityFx/Shared:
  - `"RightHand"` once in the file, and that once is in `handOf`;
  - `muzzleOf` holds `\tlocal point, fromModel = HeldWeapons.Muzzle(userId)\n\tif point == nil then\n\t\treturn fallback\n\tend\n`
    and `\treturn if fromModel then point else point + aim * MUZZLE_FORWARD\n`.
- MagDump:
  - 2 `muzzle =` lines, both calling `muzzleOf(`;
  - `local muzzleOf = Shared.muzzleOf\n`;
  - no `handPoint + look * MUZZLE_FORWARD`.
- WeaponController's `muzzlePoint` is exactly
  `local function muzzlePoint(fallback: Vector3): Vector3 / return HeldWeapons.Muzzle(Players.LocalPlayer.UserId) or fallback / end`.
  It is checked on code with comments blanked.
- HeldWeapons:
  - `"RightHand"` once, in `local HAND_PARTS = { "RightHand", "Right Arm" }\n`. This is B's shape: one list for the
    grip mount and the start of the fallback;
  - `Muzzle` holds `\tlocal hand = firstPart(character, HAND_PARTS)\n` and
    `return held.base.CFrame:PointToWorldSpace(tip), true`.
- Reached:
  - WeaponController's `\tHeldWeapons.Start()\n`;
  - `\tcancelPose()\n\tHeldWeapons.SetLocalStance(nextStance)\n`.

**T11 to T13, HeldWeapons:**
- T11:
  - exactly 1 `:Clone()` in the file and 1 in `modelFor`;
  - `\tlocal cached = if cache ~= nil then cache[family] else nil\n\tif cached ~= nil then\n\t\treturn cached\n\tend\n`;
  - `return cached` comes before `:Clone()`;
  - 0 `RunService` in the code.
- T12:
  - `seal(` once in `modelFor`;
  - `seal(model)` comes before `model.Parent = character`;
  - in `seal`: `\tfor _, part in model:GetDescendants() do\n\t\tif part:IsA("BasePart") then\n` and each of
    `.Anchored = false`, `.CanCollide = false`, `.CanQuery = false`, `.CanTouch = false`, `.Massless = true` once.
- T13: 0 matches of `\bFindFirst\w*\([^()\n]*,\s*true\s*\)|\bFindFirstDescendant\b`.

**T14, aligned with ui A's diff:**
- ArmoryStage:
  - 0 `Theme.reducedMotion` in the code;
  - 1 `RenderStepped:Connect(` in the file;
  - 1 inside `\t\tSetActive = function(` … `\t\tend,`;
  - 1 inside the `if … not Theme.lowEndDevice … then` block.
- 1 `:PivotTo(` in the file, and 1 in `\tlocal function selectFamily(` … `\tend`. This is ui A's name, chosen because
  selene flags `select`.
- The select path holds
  `\t\tlocal pose = CFrame.Angles(math.rad(Theme.ARMORY_STAGE_TILT_DEGREES), 0, 0)\n\t\tmodel:PivotTo(pose)\n`.
- ArmoryScreen has `stage.SetActive(view.open and shown == "weapons")` once and `stage.SetActive(false)` once.

**Ruling 6, rest poses (the lead's relay of ui B's lines). Inputs and reach are pinned with each line.**
- HeldWeapons `hang`:
  - `\tlocal hold = if not inHand\n\t\tthen Theme.COMBAT_HOLD_BACK\n\t\telseif ranged then Theme.COMBAT_HOLD_GRIP_RANGED\n\t\telse Theme.COMBAT_HOLD_GRIP_MELEE\n`;
  - the `local point = WeaponLook.Point(held.def, if inHand then "grip" else "holster") or Vector3.zero` line;
  - `\theld.weld.Part0 = part\n\theld.weld.C0 = attachment.CFrame * hold * CFrame.new(-point)\n\theld.model.Parent = character\n\treturn held\n`;
  - 4 exits.
- HeldWeapons `show`:
  - the slot lines (`local slot = if rig.isLocal then localStance else held` through `local other = …`);
  - `\trig.inHand = hang(rig, inUse, true, rangedInUse)\n\thang(rig, other, false, not rangedInUse)\n\tlocal raised = rangedInUse and rig.inHand ~= nil\n`;
  - the change-and-tell block ending in `listener(character, rig.isLocal, raised)`;
  - 2 exits (one is the attribute reader's closure).
- `HeldWeapons.OnHold`: `\tholdListener = listener\n` and the replay `listener(rig.character, rig.isLocal, true)`
  for raised rigs; 1 exit.
- WeaponController:
  - `restOf`'s raise-or-0;
  - `restFrame`'s `return rig.base * CFrame.Angles(math.rad(rig.rest), 0, 0)`;
  - `cancelRig` ends `\t\tmotor.C0 = restFrame(rig)\n\tend\nend`, with 0 exits;
  - `setRest`'s write;
  - the swing's `rigPoseTo(rig, rig.rest, Theme.COMBAT_SWING_SETTLE_SECONDS, Enum.EasingStyle.Quad)`, with 5 exits;
  - `Release`'s `\tcancelPose()\n\tposeTo(localPose.rest, …)\nend`, with 1 exit;
  - the kick `localPose.rest + Theme.COMBAT_SHOOT_KICK_DEGREES,` and its `WeaponController.Release()`;
  - `Start`'s `\tHeldWeapons.OnHold(onHold)\n\tHeldWeapons.Start()\n`;
  - `onHold`'s body, with 0 exits;
  - `bindCharacter`'s `\t\tlocalPose.rest = restOf(rig)\n\t\tmotor.C0 = restFrame(localPose)\n`;
  - `\tfresh.rest = restOf(rigModel)\n`;
  - 6 writes to `.rest` in the file;
  - 1 write to `raisedRigs[…]`.

## Pure tests (`tests_l3_w2.luau`)

- **`ModelName`** for all 15 ids, and those ids are exactly ProvingGrounds' families.
- **`ATTRIBUTES`**: the three names, frozen.
- **`Def`:**
  - refuses: no config; an unknown family; families that are not a table; a family that is not a string; the model in
    lower case, another family's model, or no model; no points; no grip, tip or holster; a point of 2 or 4 numbers; NaN,
    +inf, −inf or a string in a point; no bounds; `min` of two numbers; `max` with a NaN; min above max on x, y and z;
  - accepts a flat axis;
  - a malformed extra point leaves the entry standing.
- **`Point`:** present; absent; malformed (2 numbers, NaN, inf, not a table); no points; no entry.
- **`IconId`:**
  - 0 for: no assets; no icons; no set; no model; a set keyed by the family id; `imageId` 0, negative, fractional, a
    string, NaN, inf or absent; no models file; no entry; an entry Def refuses;
  - the id when all is there;
  - the set is the file's `folder` and only it.
- **`Values`:** the pair and the slot; any other held word reads melee.
- **`Read`:**
  - the pair and the slot;
  - a round trip with `Values`;
  - numbers, empty strings, tables, booleans and bad held words read nil;
  - it asks for exactly the three names.
- **`Problems`** on built copies. Each of these faults gives exactly one problem, with the exact message: a missing
  family; an extra family; grip off the origin; a point outside below and above; a malformed extra; a model that breaks
  the name rule; no tip; bounds turned over; no folder. Also:
  - a point 0.005 outside stays inside the slack;
  - two faults come back sorted by family.
- **The shipped file:** version 1, folder `Weapons`, `Problems` empty, 15 whole entries, every tip at least 0.3 studs
  from its grip.

## Assumptions made

- **`Problems(nil, …)`** returns one line ("WeaponModels.json has no families: every hand stays empty"), not 15.
  HeldWeapons warns only when the config exists.
- **Def's rules:**
  - "Grip is the origin" is exact zero, as in `weapon_frames.py`.
  - `Def` checks only grip, tip and holster.
  - A malformed extra point is a `Problems` line, and `Point` refuses it.
- **IconId** needs a whole `Def` first. A family whose entry is refused has no icon.
- **`held` lasts across a respawn**, like the client's `rangeState.activeSlot` (InputController never resets it).
  `PrepareCharacter` therefore writes the last slot on the new character.
- **`SetFamily` shows the pair on every call**, as the contract says, even when nothing changed. Setting an attribute to
  the same value fires no change.
- **Placement and fixtures:**
  - `NoteHeld` sits among the AbilityService hooks.
  - The fixture uses `read_optional`, so the harness still runs, and fails a case, if `WeaponModels.json` is missing.
- **The filtered mutation run:** `mutate.py … l3w2` matches all 138 entries. The labels are `l3w2: …` (pure) and
  `l3w2 T…` / `l3w2 L3-…` / `l3w2 R6: …` (text). The run takes about 25 minutes. I ran it in two halves (`"l3w2: "` and
  `"l3w2 "`) because I widened the text checks between them.
- **A killed run:** I stopped a first background run by its PID tree, because it had started before I changed the
  harness mid-run. The leftover `tools/crowd_harness/mutant/` was removed. Both reported runs started from a clean,
  passing baseline.

## Required changes outside my files

None.

QA's full `mutate.py` now copies the client files listed above into each mutant root, and they all exist. The text-read
files are not loaded, only counted.

## What to check in Studio

- **Attributes in the lobby.** Select your character in Explorer.
  - It carries `WeaponMelee` = `broadsword`, `WeaponRanged` = `longbow` and `WeaponHeld` = `melee` on every spawn,
    respawns included.
  - F: equip the Flamethrower, and `WeaponRanged` reads `flamethrower` at once.
- **The slot in use.**
  - A shot or a bow draw flips `WeaponHeld` to `ranged`. A swing flips it back.
  - A cast of the other slot's ability flips it too.
  - A pure 1 / 2 switch does not change it (L3-65).
- **Two clients** ("Clients and Servers", 2 players): the other player's weapons follow those three attributes, and their
  arm moves on their swings.
