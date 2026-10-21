# L3 Wave 2 brief — the models in the game (for the contract drafter)

You draft the contract for L3 Wave 2 of a Roblox project. Work in `C:\Users\benja\Desktop\tycoon-p5`, branch `l3-w2`
(from `main` at 0fb03be, where W1 is merged). **Write no code.** Your output is one file, `docs/prompts/l3-w2-contract.md`,
in the shape of `docs/prompts/l3-w1-contract.md`: "What today's code gives us (checked)", numbered rulings **L3-40** on,
owners with disjoint files, gates, risks, what needs Ben. Every claim about the code with file:line, checked by you.
LF line endings. Do not commit. Kill only your own PIDs. Do not run any upload, harvest or `--dry-run` tool (a dry run
writes `Assets.json`). Tools: `py`; `export PATH="$HOME/.rokit/bin:$PATH"`.

Ben, 2026-10-20: *"lets do wave 2, i will test later"*. His look covers W1 and W2 together, after one harvest paste.

## Read

- `docs/MISSIONS_DESIGN.md` §24 and its last paragraph (the 15 models approved), `docs/PLAN.md` "L3 — the Armory"
  (lines ~4243–4473, the W2 plan at ~4441).
- `docs/prompts/l3-study-report-screen.md` §3, §4, §5, §8 (the stage, weapons in hand, the asset route, S3).
- `docs/prompts/l3-w1-contract.md` L3-18 (the `ArmoryStage` API W2 keeps) and §12.
- `tools/testfit/README.md`, the "weapon kit" section (the frame contract, names); the generators'
  `<Model>.frame.json` files in `assets/kenney3d/weapon-kit/Models/GLB format/`.
- The asset pipeline: `docs/MANUAL_STEPS.md` M7 and the M12 asset runs (grep "harvest"), `tools/assets/merge_stages.py`,
  `upload_models.py`, `upload_paths.py` (`upload_decal`), `harvest.py`, `harvest.luau`, `gen_templates.py`,
  `assets_config.py`, `tools/gen_asset_manifest.py`, `default.project.json` / `combat.project.json` (Props mapping).
- Project memory facts (in `CLAUDE.md`'s imports): every harvested model arrives turned 180° about Y and
  `gen_templates` compensates (never compensate in the client); Open Cloud names cap at 50 characters;
  `upload_models.py` skips a stage with a non-zero id; the palette cache trap; save Ben's harvest Output from the
  clipboard to a file before anything else.
- `CLAUDE.md` code rules; the compile gate (`py tools/check_compile.py`, 180 top-level locals; FeedbackController and
  InputController are near it).

## Lead's rulings to write in (flag a real conflict with the code)

1. **One asset run, one harvest paste:** the 15 models (props route, era folder `Weapons`, `Assets/Props/Weapons/<Model>`
   in both places) and the 15 shelf icons (512 px renders with alpha, uploaded as Decals through `upload_paths`' decal
   route with an icon kind and its own alpha check; the path check rejects alpha today). Harvest records the icon image
   ids. Routing is proven before any upload. `gen_asset_manifest` covers the weapons. MANUAL_STEPS gets the commands.
2. **Frame points come from config, never from measuring a mesh:** a committed, generated config (name it) carries,
   per family, the model name and its frame points (`grip`, `tip`, `holster`, and the extras the builders added:
   `nock`, `bladeBase`, `support`, `sight`, `head`, `edge`, `pilot`, `splitUp`/`splitDown`) **in the template's own
   frame** after `gen_templates`' turn and pivot. State the transform from the generator's frame (grip at the origin,
   tip along −Z, up +Y) to the template's, from `gen_templates.py`'s code, and have the generator prove it on one model.
3. **Others see your weapons:** the server writes character attributes for the two held families and the slot in use
   (`WeaponService`, on every loadout change and on each accepted attack, draw or ability); every client draws every
   character's weapons from them (its own may follow the local stance at once). The one in use hangs at
   `RightGripAttachment` by its `grip`, the other at UpperTorso's `BodyBackAttachment` by its `holster`. Two-handers are
   held by the right hand alone in L3.
4. **Models are decoration only:** never a ray start or an arc centre. The shot origin (`InputController` shotRay) and
   the melee origin (the root along the flat camera heading) do not move. Parts: CanCollide, CanQuery, CanTouch false,
   Massless, never a physics body. One muzzle helper (from the `tip` point) replaces the three copies that start
   tracers at RightHand (`WeaponController.muzzlePoint`, `FeedbackController.muzzleOf`, `FlameFx.muzzleOf`).
5. **Other players' arms move:** a teammate's weapon strike drives `SwingOther` (FeedbackController hears the strikes),
   so visible weapons do not hang still.
6. **The stage:** a ViewportFrame behind `ArmoryStage`'s existing API; one viewport; the camera orbits, never the model;
   drag to turn; the slow turn only while the screen is open and only when not `Theme.lowEndDevice` (never
   `reducedMotion`); light and ambient constants in Theme; an unowned family is a near-black silhouette; the text
   placeholder stays when a template is missing.
7. **The shelf** shows each family's icon (ImageLabel from the harvested id), with today's text card when it is missing.
8. **Missing assets degrade, never error:** no template → empty hands and the text stage; no icon → the text card.
9. **Cost:** at most 8 weapon models on screen in a party of four; a model is cloned once per character and family and
   reparented on a stance change, never per frame. The old slot-tier model lookup (`WeaponSwordI`…) goes.
10. No sound. Phones first. Keys free in both places if any new lever is needed (none expected).

## Owners (propose; disjoint files)

A **pipeline engineer** (general-purpose, Opus: `tools/assets/*`, `harvest.luau`, `Assets.json`, the frame-config
generator and its data, `gen_asset_manifest.py`, MANUAL_STEPS commands; the lead runs the upload and the paste), a
`luau-engineer` (WeaponService's attributes, Types, any pure shared module), `ui-engineer` A (the stage and the shelf,
Theme), `ui-engineer` B (`WeaponController`, `FeedbackController`, `FlameFx`, `CombatFxController`, the muzzle helper,
`SwingOther`). Respect the compile budget: new behaviour in new modules. Tests: pure rules in the harness, text checks for
service lines **that pin each pinned call's inputs and that it is reached** (W1's fix-diff lesson), mutate entries.

End your reply with a ten-line summary, the rulings count, and anything you think needs Ben.
