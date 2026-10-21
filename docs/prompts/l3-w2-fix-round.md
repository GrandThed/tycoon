# L3 Wave 2 fix round — the lead's rulings and owners (2026-10-21)

The three slice reviews of L3 W2 (`docs/prompts/l3-w2-review/1-pipeline.md`, `2-server.md`, `3-client.md`) found
**0 Critical, 0 Major, 11 Minor** and 15 suggestions. Read each finding in its file before fixing it. Contract of
record: `docs/prompts/l3-w2-contract.md` (§11 overrides). Branch `l3-w2` in `C:\Users\benja\Desktop\tycoon-p5`. The
15 models and 15 icons are uploaded; Ben's harvest paste is pending: **never run an uploader, the real harvest, or a dry
run against the real `Assets.json`** (scratch copies only).

## Rulings

**Pipeline (slice 1)**
- **P1 (1-m1)** Regenerate `docs/ASSET_MANIFEST.md` now; MANUAL_STEPS adds `py tools/gen_asset_manifest.py` beside both
  "commit `Assets.json`" steps.
- **P2 (1-m2)** The harvest merge **refuses** a rotated MeshPart for a weapon (exit 1, naming it), so the turn proof's
  precondition is enforced; MANUAL_STEPS step 8 says "no rotated warning".
- **P3 (1-s1)** MANUAL_STEPS "L3 W2" catches up: steps 3–6 ticked with their commits (084a14f, d1c2f59, 4154715), the
  "none of the 15 is in Assets.json" line corrected, the moderation repeat says it emits fewer than 30 (not "stop"), and
  step 9 says what to do when the proof fails (stop; report; no templates).
- **P4 (1-s2)** `upload_icons.py` hashes the decoded RGBA pixels, not the file bytes, so a re-encode never re-uploads.
  The 15 recorded hashes are migrated in place (recomputed from the same files; no upload).
- **P5 (1-s3)** The proof's line says what it proves (one offset and one size check per weapon, and the points it carries).
- **P6 (1-s4)** The props description keeps "Kenney kit pieces, CC0" when every kit named is a Kenney kit, and names
  generated kits as generated ("…; kits: weapon-kit (generated)"). Only future uploads change.

**Server and shared (slice 2, plus 3-m1)**
- **S1 (2-m1)** T8 also counts every `.held` read across WeaponService (expect 3) and AbilityService (0), with mutants.
- **S2 (2-m2)** T2 pins the three callers that reach `PrepareCharacter` as exact lines with their indentation (WaveService's
  hook, ArenaService's `hook(player, character)`, RangeService's respawn handler) and AddPlayer's mission test, with the
  four mutants the review proved.
- **S3 (2-m3, 3-m3)** Pinned lines are whole lines with their indentation; a file-wide count of 0 for any line that turns a
  sealed property back on in HeldWeapons; the client wiring lines the review listed (the stage's `stop()` in
  `SetActive(false)`, `clear()` in `selectFamily`, `entry.model:Destroy()` in `show`'s cleanup, `names.held` among the
  watched attributes, and the 8 more in 3-client.md) each pinned with an `l3w2:` mutant. **Write the client pins last,
  after the ui-engineer reports** (the lead relays), against the client files as they end.
- **S4 (2-m5)** `OnDraw` refuses a draw whose family is not in the ranged slot (beside the refusals at
  `WeaponService.luau:2556-2562`), with a text check and a mutant.
- **S5 (2-s1, 2-s2, 2-s4)** Spelling-robust counts for `shooter["held"]`, a literal `SetAttribute("WeaponHeld"`, a
  whole-table `shooter.loadout =`; T4 and T6 count the exits after the noted line (ruling 7's form); `Problems` sorts its
  whole result (or its comment says what it does).
- **S6 (3-m1)** `WeaponService.NoteHeld(player, slotName)` moves to just before `broadcastFx(fx)` in
  `AbilityService.OnCast` (after every refusal, before anything is sent), so other clients see the right weapon at the
  cast's first frame; T6 re-pinned, its mutant re-aimed.
- **Not taken:** 2-s3 (the 0.01 slack lives in Luau and its Python mirror; a comment in each names the other).

**Client (slice 3, plus 1-m3)**
- **C1 (1-m3)** HeldWeapons and ArmoryStage find the clone's `Base` **by name** and set `PrimaryPart = base` before any
  weld or `PivotTo` (as PlotService and PropFactory do); a clone with no `Base` is treated as a missing template.
- **C2 (3-m2)** Unowned shelf icons use a **shelf-only ghost tone** (`Theme.ARMORY_SCREEN_ICON_GHOST`), lighter than the
  card, contrast at least 1.5 against `ARMORY_SCREEN_CARD_DARK`; report the value and the contrast. The stage keeps the
  near-black silhouette on its light band.
- **C3 (3-s2, 3-s3, 3-s4)** The stage's turn connection exists only while a model is shown; a drag ends on any
  `InputEnded` of its input, on window focus loss and on close (no stuck drag); on every device the gamepad's right stick
  turns the stage while the Weapons tab is open (on a low-end device it re-places the camera per stick event, no
  per-frame work). **The right-stick part was withdrawn in fix round 2 (G3, `l3-w2-fix2.md`).**
- **C4 (3-s7)** HeldWeapons coalesces a character's attribute changes into one `show` per frame (`task.defer`, one pending
  flag per character), which also bounds a flood of `WeaponHeld` flips.
- **C5 (3-s6)** `COMBAT_WEAPON_WAIT_SECONDS`' comment no longer mentions the prop folder.
- **Settled, no code:** 3-s1, the bow's draw stays at its absolute angle (80 from the hanging arm; from a raised arm it
  shows no further movement); 3-s5, the combat code assumes R15 (it has since P1): the lead checks the experience's avatar
  setting is R15-only (MANUAL_STEPS, Creator Hub); 2-m4, in the lobby a teammate's slot switch shows only once a level
  starts (the lobby refuses attacks): PLAYTEST runs the two-client check inside a level.

## Owners (fresh agents; disjoint files)

| Owner | Rulings | Files |
|---|---|---|
| **pipeline engineer** (general-purpose, Opus) | P1–P6 | `tools/assets/harvest.py`, `upload_icons.py`, `upload_models.py`, `weapon_frames.py`, `src/shared/Config/Assets.json` (P4's hashes only, through `assets_config`), `docs/ASSET_MANIFEST.md`, `docs/MANUAL_STEPS.md` "L3 W2" |
| **luau-engineer** | S1–S6 | `src/combat/server/Services/WeaponService.luau`, `AbilityService.luau`, `src/shared/WeaponLook.luau`; `tools/crowd_harness/run_harness.py`, `tests_l3_w2.luau`, `mutate.py`; read-only pins of `WaveService`, `ArenaService`, `RangeService` and the client files |
| **ui-engineer** | C1–C5 | `src/combat/client/Controllers/HeldWeapons.luau`, `src/client/UI/ArmoryStage.luau`, `ArmoryShelf.luau`, `Theme.luau` |

- The ui-engineer reports the exact final text of every client line S3 pins; the lead relays it to the luau-engineer.
- **Every agent:** `git status` and `git diff` first; commit nothing; kill only your own PIDs; report to
  `docs/prompts/l3-w2-fix-reports/<role>.md` and reply with it; gates: stylua, selene, luau-lsp on both sourcemaps
  (regenerated into your scratchpad), `py tools/check_compile.py`, the harness
  (`py tools/crowd_harness/run_harness.py C:/Users/benja/Desktop/tycoon-p5 C:/Users/benja/Desktop/tycoon/tools/bin/luau.exe`),
  and for the pipeline `weapon_frames.py --check`, `gen_templates.py --check`, `gen_asset_manifest.py --check`;
  `export PATH="$HOME/.rokit/bin:$PATH"`; `py`; LF.
