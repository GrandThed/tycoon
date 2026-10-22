# L4 W2 code wave — kickoff (read with the contract)

**Contract of record:** `docs/prompts/l4-w2-contract.md` (rulings L4W2-1..15; **§0 is the lead's amendments and overrides
the text below it**: the generator items already landed, the boss rename has no ordering constraint, the mountain and the
Castle Key join W2). Decisions: `docs/MISSIONS_DESIGN.md` §26-§28 and the approvals after them.

**Where:** worktree `C:\Users\benja\Desktop\tycoon-p5`, branch **`l4-w2`** (from `l4-real-forest` 5abc72f, which holds W1b
merged, the mountain, the reworked forest, all 81 assets harvested and their templates). Its `assets\` is the main
checkout's (junction). The second worktree `tycoon-p5b` (branch `l4-verify`) runs the lead's long gates on the merged base:
never edit there.

**What changed since the contract was drafted (2026-10-21):**
- **The assets are uploaded and harvested** (MANUAL_STEPS runbook `docs/prompts/l4-w2-asset-run.md`, 9ad3cb5..148dacd):
  `templates/_levels/ForestRoad/` (37 meshes), `templates/_props/Forest/` (Bramble, Campfire, ChiefTent, SpawnTent),
  `templates/_props/Raiders/` (7 models, Base + Stage0..Stage4, one MeshPart per kit folder). So §10's "Wave A with
  placeholders" and "the asset run" are one step now: build against the real templates, and keep every placeholder
  fallback (L4W2-8) because a missing template must still degrade.
- **The forest data** is `src/shared/Config/LevelDress/ForestRoad.json` (plan hash `23851a6f417491c1`; 37 meshes, 4 props,
  62+ barriers incl. the mountain yard's, `hide`, `looks`, `effects`); `Assets.json` v6 `levels.ForestRoad` holds the same
  hash. Read `docs/prompts/l4-w2-reports/forest2.md` for the mountain dressing and the yard walls.
- **The raider config** is `tools/assets/out/RaiderModels.json` **version 2** (`cue`, `posedReach`, `rig.throwShare`,
  `whirl`, `steady`, the `raider-plate` → `plate` role): read `docs/prompts/l4-w2-reports/raiders.md` (the arm rules and
  the plate role as numbers). `raider_frames.py` does not exist yet (D2 writes it, §3.1).
- **The mountain climb** is in the layout (`check_parkour.py`; MISSIONS_DESIGN §28); its secret `mountain` gives the
  Castle Key (`Config/Levels/1_ForestRoad.json secrets.mountain.key = "castle"`).
- **W1b is merged:** the old mission code is gone; the dash is proven by the server's ring and covered hits are held
  (`DashProof`, `VitalsService.Step` driven from `WeaponService.step` under `xpcall`, `HasWaiting`, WaveService's
  `fieldHeld`). Read `docs/prompts/l4-w1b-contract.md` §10 before touching `VitalsService`, `WeaponService` or `WaveService`.
- **The project files** already map `templates/_levels` to `ReplicatedStorage.Assets.Levels` in the combat place and
  ignore it in every hub place (§2.5 is done).

**Owners (contract §9, plus):** ui A also owns the Castle Key's client side (`src/client/UI/MapScreen.luau`, the chest
reward card wherever it is drawn: find it; if it lives in a ui B file, relay the change to ui B). D1 also owns
`Expeditions.json keys` and the `key` validation mirror in `sim_range.py`. Nobody else edits a file another owner holds.

**Every agent:** `git status` and `git diff` first (your work may be partly done after a cut-off); commit nothing; kill
only your own PIDs, never by image name; LF files. Report to `docs/prompts/l4-w2-code-reports/<role>.md` (`luau-a.md`,
`ui-a.md`, `ui-b.md`, `d1.md`, `d2.md`) and keep it current as you go, with a **"For the other owners"** section (file,
old text, new text for every line a pin or a mutate entry reads; signatures; config keys). The lead relays between you;
re-read the other owners' reports before you finish. If your tools refuse to write the report, put it in your final
message.

**Tools:** Git Bash; `export PATH="$HOME/.rokit/bin:$PATH"`; `py` only (`py -3.12` for `sim_range.py` and `check_levels*`;
a `#!/usr/bin/env python` script runs 3.12 without Pillow, otherwise 3.14 with Pillow; say which Python gave a number);
Luau CLI `C:/Users/benja/Desktop/tycoon/tools/bin/luau.exe`; harness
`py tools/crowd_harness/run_harness.py C:/Users/benja/Desktop/tycoon-p5 <luau>`; luau-lsp with
`--definitions=tools/types/globalTypes.d.luau` and sourcemaps written to your own scratch folder. Run `mutate.py` only
filtered (`files:`), and never two at once in this worktree (one shared `mutant/` root): D2 owns it; others ask D2 in
their report. Never run an asset tool that writes `Assets.json`.

**Done (each owner):** stylua, selene, luau-lsp on both sourcemaps, `py tools/check_compile.py`, the harness, your own
tests and gates from contract §11 for your files; your report. The full §11 run is QA's after the review.
