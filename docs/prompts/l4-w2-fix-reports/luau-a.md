# L4 W2 fix round: luau-engineer A's report (K7, the server half)

Worktree `tycoon-p5`, branch `l4-w2`, base 96cee96. Nothing committed. 2026-10-22. Python numbers: the harness through
`py` (its shebang: 3.12 64-bit); my scratch runners under `py -3.12 -B`.

## State

- [x] `LevelDress.luau`: the decision is one pure function, `Decide`, whose answer carries the word (`word = { layout,
  planHash }`), so "dressed with no hash" cannot be written; `Accept` behind Decide's pcall (a throw is a refusal);
  `Present` (a template counts only with a MeshPart whose MeshId names an asset); `Lay` (what is built, grey or dressed);
  `Accept` refuses `props` and `effects` that are not lists or hold a malformed entry.
- [x] `LevelService.luau`: `dressOf` only gathers and calls `Decide`; `Build` lays `Lay`'s answer and sets `DressHash`
  BEFORE `Dress`, both from the answer's word; `construct`, `place` and `raise` take a `LevelDress.Laid`; `templatesOf`
  hands Decide each Model's MeshIds; the hidden-piece comment says "the shoulder camera" (slice 1 m3).
- [x] `Types.luau`: the LevelDress comment names Decide and the K7 shape rule (no type change).
- [x] `tests_l4w2.luau`: groups `shapes`, `decide`, `lay`; the accept and shipped groups extended.
- [ ] D2: re-aim the 18 failing pins and the 5 stale mutate entries, add the new ones (below).
- `Catalog.luau`, `WeaponService.luau`: untouched (K7 did not need them).

## Contracts as built (signatures)

```luau
-- LevelDress (pure; src/combat/server/Services/LevelDress.luau)
export type Word = { layout: string, planHash: string }
export type Accepted = { walls: { LevelGeometry.Piece }, hidden: { [string]: boolean }, looks: Looks, word: Word }
export type Ask = {
	dress: Types.LevelDress?, uploadedHash: string?, failLever: boolean,
	templates: { [string]: { string } }, -- Model name -> its MeshParts' MeshIds
	layout: Types.LevelLayout, pieces: { LevelGeometry.Piece }, found: { [string]: boolean }?, -- shortcut ids
	groupsOk: boolean, maxParts: number, layoutName: string,
}
export type Laid = { pieces: { LevelGeometry.Piece }, hidden: { [string]: boolean }, looks: Looks?, word: Word? }
LevelDress.FAILED_HASH = "(the dressFail lever)"   -- moved here from LevelService's CONST
LevelDress.Accept(dress, uploadedHash, haveMeshes, pieces, open, groupsOk, maxParts, layout): (Accepted?, string?) -- unchanged args
LevelDress.Present(templates: { [string]: { string } }): { [string]: boolean }
LevelDress.Decide(ask: Ask): (Accepted?, string?)
LevelDress.Lay(pieces: { LevelGeometry.Piece }, base: Looks?, accepted: Accepted?): Laid
-- LevelService (internal)
dressOf(layout, layoutName, pieces, open, maxParts): LevelDress.Accepted?
construct(folder, laid: LevelDress.Laid, expeditions, reactive, ice)
place(folder, laid: LevelDress.Laid, expeditions, reactive?, ice?)
```

- **Decide:** Accept is called inside `pcall(function() ... end)` with `if ask.failLever then FAILED_HASH else
  ask.uploadedHash`, `Present(ask.templates)` and `LeftOut(ask.layout, ask.found)`, so the lever, the templates' rule and
  the shortcut's names are all inside the tested call. A throw answers `nil, "the dress could not be read (<error>)"`.
- **Present:** a Model name counts when one of its MeshIds is a string other than `""` and `"rbxassetid://0"` (what
  gen_templates.py writes for an id never uploaded). A Model with no MeshPart is no template.
- **Accept's new refusals** (after the meshes, before hide): `its props are not a list`; `prop <i> is not a table` / `names
  no piece` (nil or "") / `has a place or a turn that is not a number` (x, y, z, yaw finite) / `has a scale that is not
  above 0` (finite and > 0) / `stands with something that is not a Part's name` (`with` nil or a non-empty string); `its
  effects are not a list`; `effect <i> is not a table` / `has no kind` (nil or "") / `has a place that is not a number`.
  The mesh refusal now reads `the mesh "<name>" has no template with a mesh`. The shipped ForestRoad dress passes (23 props,
  scales 1.0-1.448; 8 effects).
- **Lay:** grey = `{ pieces = pieces (the same table), hidden = {}, looks = base, word = nil }`; dressed = a clone of
  `pieces` with the walls appended, `accepted.hidden`, `Overlay(base, accepted.looks)`, `accepted.word`.

## Assumptions (the lead may overrule)

1. **The pcall sits in `LevelDress.Decide`, which LevelService calls**, not in LevelService itself: the ruling's "LevelService
   calls Accept under pcall" is kept by construction and the pcall becomes testable (a throwing dress and a nameless piece
   are refused in the harness). The gathering around it (Catalog lookups, `FindFirstChild`, `BarrierGroups.Ensure`, which
   pcalls itself) cannot throw; `uploadedHash` now tolerates an `Assets.json levels` that is not a table.
2. **A missing `props` or `effects` is refused**, as the ruling says ("not the right shape"): a later level with no fires
   must write `"effects": []` (forest.py always writes both). Written into the Types comment.
3. **`"rbxassetid://0"` counts as no mesh** beside the empty MeshId. A moderated asset keeps its id, so this is the cheap
   partial fix the reviewer described (slice 1 s2), not the `PreloadAsync` one.
4. **MeshId reads the template's MeshContent URI.** The templates carry only `MeshContent` (rbx-dom canonical); the engine
   mirrors a URI MeshContent into `MeshId`. If Studio ever read it as "", the forest would be grey with the warn `the mesh
   "..." has no template with a mesh`: safe, and step 1 of "What to check in Studio" catches it.
5. **The lever is spent unconditionally** by the first level that asks for a dress (`local failLever =
   state.failNextDress` then `state.failNextDress = false`), the same behaviour as before with no `if` to mutate.
6. The grey `hidden` is an empty table, not nil, so construct reads `if hidden[piece.name] then` with no nil test.

## For the other owners

### D2 (run_harness.py L4W2_LINES / L4W2_ORDER, tests_l3_w2.luau L4BP.W2, mutate.py)

**Harness on the worktree with my edits: FAIL (18 of 4,472 checks), every failure one of your pins on a line I changed;
every case of tests_l4w2.luau passes.** Old key -> new text (whole lines, comments blanked as `luau_code` does; counts 1
unless said):

| Key | Body | New text |
|---|---|---|
| `constructHidden` | construct | `\tlocal hidden = laid.hidden` (add `\tlocal looks = laid.looks` and `\tfor _, piece in laid.pieces do`) |
| `constructSkinnedIf` | construct | `\t\tif hidden[piece.name] then` |
| `dressUploaded` | dressOf | `\t\tuploadedHash = uploadedHash(layoutName),` |
| `dressFailSpent` | dressOf | `\tstate.failNextDress = false` (indent now one tab) |
| `dressFailHash` | dressOf | gone (the lever's hash is in `LevelDress.Decide`, tested). Pin instead `\tlocal failLever = state.failNextDress` and `\t\tfailLever = failLever,` |
| `dressAccept` | dressOf | text `LevelDress.Decide({\n\t\tdress = Catalog.GetLevelDress(layoutName),\n\t\tuploadedHash = uploadedHash(layoutName),\n\t\tfailLever = failLever,\n\t\ttemplates = templatesOf(layoutName),\n\t\tlayout = layout,\n\t\tpieces = pieces,\n\t\tfound = open,\n\t\tgroupsOk = BarrierGroups.Ensure(),\n\t\tmaxParts = maxParts,\n\t\tlayoutName = layoutName,\n\t})` |
| `buildDressOf` | Build | `\t\taccepted = dressOf(layout, layoutName, pieces, open, rules.maxParts)` |
| `buildOverlay` | Build | gone (in `LevelDress.Lay`, tested). Pin instead `\tlocal laid = LevelDress.Lay(pieces, expeditions.looks, accepted)` |
| `buildWalls` | Build | gone (in `LevelDress.Lay`, tested) |
| `buildPlace` | Build | `\tlocal camps, problem = place(folder, laid, expeditions, reactive, ice)` |
| `buildLooks` | Build | `\tstate.looks = laid.looks` |
| `buildDress` | Build | `\t\tfolder:SetAttribute(CONST.DRESS_ATTRIBUTE, word.layout)` |
| `buildDressHash` | Build | `\t\tfolder:SetAttribute(CONST.DRESS_HASH_ATTRIBUTE, word.planHash)` |

Order pins: `piecesThenDress` -> second text `accepted = dressOf(`; `hiddenThenSkinned` -> first text `if
hidden[piece.name] then`; `failThenAccept` -> `local failLever = state.failNextDress` before `state.failNextDress = false`
before `LevelDress.Decide(`; `builtThenDress` -> `state.built = true` before `folder:SetAttribute(CONST.DRESS_HASH_ATTRIBUTE,
word.planHash)`; **`dressThenHash` is reversed (K7, slice 2 s2): `folder:SetAttribute(CONST.DRESS_HASH_ATTRIBUTE,
word.planHash)` before `folder:SetAttribute(CONST.DRESS_ATTRIBUTE, word.layout)`.**

**New deciding lines to pin (whole lines, with indentation, count 1 in the body named):**
- Build: `\tif layoutName ~= nil then` (slice 4 P3); `\tlocal accepted: LevelDress.Accepted? = nil`; `\tlocal word = laid.word`;
  `\tif word ~= nil then` (P1: the old `:778`); order `local laid = LevelDress.Lay(` before `local camps, problem = place(`.
- dressOf: `\tif accepted == nil then` then `\t\twarn(...)` (P6: now only the warn; the answer is returned as is);
  `\t\tdress = Catalog.GetLevelDress(layoutName),`, `\t\ttemplates = templatesOf(layoutName),`, `\t\tlayout = layout,`,
  `\t\tpieces = pieces,`, `\t\tfound = open,`, `\t\tgroupsOk = BarrierGroups.Ensure(),`, `\t\tmaxParts = maxParts,`,
  `\t\tlayoutName = layoutName,` (or the one `dressAccept` text above, which holds them all).
- construct: `\tlocal looks = laid.looks` (slice 1 m1's looks probe), `\tlocal hidden = laid.hidden`, `\tfor _, piece in
  laid.pieces do`; **the wall branch's look as one text** (slice 1 m1's `:448` probe, unchanged code):
  `\t\telseif isWall then\n` + its two comment lines (blanked) + `\t\t\tpart.CollisionGroup = BarrierGroups.BARRIER\n\t\t\tpart.Transparency = 1\n\t\t\tpart.CanTouch = false\n\t\t\tpart.CastShadow = false\n\t\t\tpart.CanCollide = true`
  (on the comment-blanked code, the five property lines in a row are unique to this branch).
- place: `\tlocal ok, camps = pcall(construct, folder, laid, expeditions, made, cells)`.
- raise (the lobby): `\tlocal base = if expeditions ~= nil then expeditions.looks else nil` and `\treturn place(folder,
  LevelDress.Lay(pieces, base, nil), expeditions, reactive, ice)`.
- templatesOf (slice 1 s2's gathering; the rule itself is `Present`, tested): `\t\t\t\tlocal meshIds: { string } = {}`,
  `\t\t\t\t\tif part:IsA("MeshPart") then`, `\t\t\t\t\t\ttable.insert(meshIds, part.MeshId)`, `\t\t\t\tfound[child.Name] =
  meshIds`.
- Unchanged and still owed from the ruling: WeaponService `gather`'s `\tlocal restDrop = config.crowd.restDrop` (slice 1
  m1, slice 4 P4).

**Five mutate.py entries are stale** (my scratch scan of all 1,914 entries; no other entry of my files is):
- `"l4w2 pins: no wall appended"` -> now a LevelDress entry, test-caught: `(LEVEL_DRESS, "\ttable.move(accepted.walls, 1,
  #accepted.walls, #built + 1, built)\n", "")` (= my `"k7 lay: no wall appended"`; keep one of the two labels).
- `"l4w2 pins: the dress's looks not laid"` -> `(LEVEL_DRESS, "\t\tlooks = LevelDress.Overlay(base, accepted.looks),\n",
  "\t\tlooks = base,\n")` (= `"k7 lay: the dress's looks not laid"`).
- `"l4w2 pins: Dress never set"` -> `(LEVEL_SERVICE, "\t\tfolder:SetAttribute(CONST.DRESS_ATTRIBUTE, word.layout)\n", "")`
  (pin-caught).
- `"l4w2 pins: the Z lever's hash never wrong"` -> `(LEVEL_DRESS, "\t\t\tif ask.failLever then FAILED_HASH else
  ask.uploadedHash,\n", "\t\t\task.uploadedHash,\n")` (test-caught; = `"k7 decide: the lever's hash never given"`).
- `"l4w2 pins: the shortcut's left-out names not given"` -> `(LEVEL_DRESS, "\t\t\tLevelDress.LeftOut(ask.layout,
  ask.found),\n", "\t\t\t{},\n")` (test-caught; = `"k7 decide: the found shortcut not left out"`).

**New mutate.py entries:** the two dicts in the appendix. `K7_A_MUTATIONS` (39, LevelDress) are caught by tests_l4w2.luau
(see Gates). `K7_PIN_MUTATIONS` (25, LevelService) are caught only once your pins read the lines above; every text occurs
exactly once in the worktree now. mutate.py's FILES already holds LevelDress and LevelService.

### ui-engineer A (LevelScenery, ScenePlan)

- The word is unchanged in name and meaning, but **`DressHash` is now set before `Dress`** (K7, slice 2 s2): on a build, the
  name arrives last; on Build's start and in Clear, `Dress` goes first as before.
- The server refuses everything your `jobsOf` iterates: `props` and `effects` must be lists; each prop has a non-empty
  string `piece`, finite `x y z yaw`, a finite `scale > 0`, `with` nil or a non-empty string; each effect a non-empty string
  `kind` and finite `x y z`. A dress the server accepted is therefore one your build can read; your pcall stays the
  backstop for what the server cannot see (a clone failing, a template only the client misses).
- `LevelDress.Present`'s rule (a Model counts only with a MeshPart whose MeshId is not `""` or `"rbxassetid://0"`) is the
  server's; if you want the client to judge a template the same way, the predicate is that one line.
- The comment over the hidden piece in `construct` now says the default camera does not stop at it and cites your K9.

### D1, ui-engineer B

Nothing from K7. Neither has asked me for a Types change in this round (re-read before finishing).

## Gates (2026-10-22)

- `stylua --check` on `LevelDress.luau`, `LevelService.luau`, `Types.luau`, `tests_l4w2.luau`: clean. `selene` on the three
  sources: 0 errors, 0 warnings (the test file shows only the harness's concatenated globals, `check`, `FIXTURES` and the
  like, the same kinds as on HEAD).
- `luau-lsp analyze` (definitions `tools/types/globalTypes.d.luau`, sourcemaps written to my scratch folder) on
  `src/combat/server`, `src/shared` with the combat sourcemap and on `Types.luau`, `Catalog.luau` with the default one: 0
  diagnostics.
- `py tools/check_compile.py`: PASS, 182 files.
- Harness (worktree, other owners' work in progress included): **FAIL (18 of 4,472 checks)**: the 18 pins listed above, no
  other failure; HEAD's base was PASS (4,412).
- Client type-check: `luau-lsp analyze` on `src/combat/client` (ui A's and ui B's work in progress) is also 0
  diagnostics, so nobody's new code reads a Types field that is not there.
- **Mutants** (my scratch runner, `C:/Users/benja/AppData/Local/Temp/claude/c--Users-benja-Desktop-tycoon/3f855f00-eb33-4bab-adb5-c937f685030c/scratchpad/luaua/runmut.py`: copies of the tree, each running its own
  run_harness.py; never mutate.py, never this worktree's `mutant/`): the 39 `K7_A_MUTATIONS` below, **39 caught**, each by
  a tests_l4w2.luau case and none only by a pin. The scratch baseline failed the 18 pins above and 4 Part-count checks
  that need `tools/check_levels.py` beside the harness (my copies did not carry it); a mutant counted as caught only with a
  failure outside those 22.
- The 25 `K7_PIN_MUTATIONS` and every re-aimed text: each occurs exactly once in the worktree (scratch scan). They are
  caught once D2's pins are in.
- Review probes on my files, where each now stands: slice 1 m1 `:778` -> `if word ~= nil then` (pin) and the word on the
  answer (tested); `:714` -> gone, the hash rides on `Accepted.word` (tested); `:448` the wall's Transparency (pin, text
  above); `:696` -> gone, the lever's hash is Decide's (tested), the spend is two pinned lines; Build's `if layoutName ~=
  nil then` (pin); construct's looks -> `local looks = laid.looks` (pin) over Lay's looks (tested); WeaponService `:828`
  restDrop (pin, D2, untouched). Slice 1 m2's three guards (tested: shapes group) and the missing pcall (Decide, tested);
  slice 1 s2 (Present, tested; the gathering pinned); slice 2 m1 (tested); slice 2 s2 (order pin, reversed); slice 4 m2 P1-P6
  as slice 1 m1, P5 -> gone (Lay, tested: "grey is dressed with nothing"), P6 -> the warn alone (pin).

## Appendix: the proposed mutate.py entries (D2 pastes them; constants are mutate.py's)

```python
# luau-engineer A's proposed mutate.py entries for the L4 W2 fix round (K7), each caught by
# tests_l4w2.luau. Constants as in mutate.py.
LEVEL_DRESS = "src/combat/server/Services/LevelDress.luau"

K7_A_MUTATIONS = {
    # Accept: props and effects have the client's shape (slice 2 m1).
    "k7 dress: props need not be a list": (LEVEL_DRESS, '\tif type(props) ~= "table" then\n', "\tif false then\n"),
    "k7 dress: a bad prop is taken": (LEVEL_DRESS, "\t\t\treturn nil, `prop {index} {problem}`\n", "\t\t\tcontinue\n"),
    "k7 dress: a prop that is no table is taken": (LEVEL_DRESS, '\tif type(entry) ~= "table" then\n\t\treturn "is not a table"\n\tend\n\tif type(entry.piece)', '\tif false then\n\t\treturn "is not a table"\n\tend\n\tif type(entry.piece)'),
    "k7 dress: a prop's empty piece is taken": (LEVEL_DRESS, 'if type(entry.piece) ~= "string" or entry.piece == "" then', 'if type(entry.piece) ~= "string" then'),
    "k7 dress: a prop with no piece is taken": (LEVEL_DRESS, 'if type(entry.piece) ~= "string" or entry.piece == "" then', 'if entry.piece == "" then'),
    "k7 dress: a prop's turn is not checked": (LEVEL_DRESS, "finite(entry.z) and finite(entry.yaw)) then", "finite(entry.z)) then"),
    "k7 dress: a prop's place is not checked": (LEVEL_DRESS, "\tif not (finite(entry.x) and finite(entry.y) and finite(entry.z) and finite(entry.yaw)) then\n", "\tif not finite(entry.yaw) then\n"),
    "k7 dress: a prop of scale 0 is taken": (LEVEL_DRESS, "\tif not finite(entry.scale) or entry.scale <= 0 then\n", "\tif not finite(entry.scale) or entry.scale < 0 then\n"),
    "k7 dress: a prop of any finite scale is taken": (LEVEL_DRESS, "\tif not finite(entry.scale) or entry.scale <= 0 then\n", "\tif not finite(entry.scale) then\n"),
    "k7 dress: a prop of no scale is taken": (LEVEL_DRESS, "\tif not finite(entry.scale) or entry.scale <= 0 then\n", '\tif type(entry.scale) == "number" and entry.scale <= 0 then\n'),
    "k7 dress: a prop's empty with is taken": (LEVEL_DRESS, 'if with ~= nil and (type(with) ~= "string" or with == "") then', 'if with ~= nil and type(with) ~= "string" then'),
    "k7 dress: a prop's with is not checked": (LEVEL_DRESS, 'if with ~= nil and (type(with) ~= "string" or with == "") then', "if false then"),
    "k7 dress: effects need not be a list": (LEVEL_DRESS, '\tif type(effects) ~= "table" then\n', "\tif false then\n"),
    "k7 dress: a bad effect is taken": (LEVEL_DRESS, "\t\t\treturn nil, `effect {index} {problem}`\n", "\t\t\tcontinue\n"),
    "k7 dress: an effect that is no table is taken": (LEVEL_DRESS, '\tif type(entry) ~= "table" then\n\t\treturn "is not a table"\n\tend\n\tif type(entry.kind)', '\tif false then\n\t\treturn "is not a table"\n\tend\n\tif type(entry.kind)'),
    "k7 dress: an effect's empty kind is taken": (LEVEL_DRESS, 'if type(entry.kind) ~= "string" or entry.kind == "" then', 'if type(entry.kind) ~= "string" then'),
    "k7 dress: an effect with no kind is taken": (LEVEL_DRESS, 'if type(entry.kind) ~= "string" or entry.kind == "" then', 'if entry.kind == "" then'),
    "k7 dress: an effect's place is not checked": (LEVEL_DRESS, '\tif not (finite(entry.x) and finite(entry.y) and finite(entry.z)) then\n\t\treturn "has a place', '\tif not finite(entry.x) then\n\t\treturn "has a place'),
    # Accept's word (the answer carries the hash).
    "k7 dress: the word's hash dropped": (LEVEL_DRESS, "\t\tword = { layout = layout, planHash = uploadedHash },\n", '\t\tword = { layout = layout, planHash = "" },\n'),
    "k7 dress: the word names another layout": (LEVEL_DRESS, "\t\tword = { layout = layout, planHash = uploadedHash },\n", '\t\tword = { layout = "", planHash = uploadedHash },\n'),
    # Present (slice 1 s2).
    "k7 dress: an empty MeshId is a mesh": (LEVEL_DRESS, 'if type(meshId) == "string" and NO_MESH[meshId] ~= true then', 'if type(meshId) == "string" then'),
    "k7 dress: the never-uploaded id is a mesh": (LEVEL_DRESS, '\t["rbxassetid://0"] = true,\n', ""),
    "k7 dress: no template is present": (LEVEL_DRESS, "\t\t\t\tpresent[name] = true\n", "\t\t\t\tpresent[name] = nil\n"),
    "k7 dress: a Model with no MeshPart is present": (LEVEL_DRESS, "\tfor name, meshIds in templates do\n\t\tfor _, meshId: any in meshIds do\n", "\tfor name, meshIds in templates do\n\t\tpresent[name] = true\n\t\tfor _, meshId: any in meshIds do\n"),
    # Decide (slice 1 m2: the pcall; the lever; the inputs).
    "k7 decide: a throw is no refusal": (LEVEL_DRESS, "\tif not ok then\n\t\treturn nil, `the dress could not be read", "\tif false then\n\t\treturn nil, `the dress could not be read"),
    "k7 decide: the lever's hash never given": (LEVEL_DRESS, "\t\t\tif ask.failLever then FAILED_HASH else ask.uploadedHash,\n", "\t\t\task.uploadedHash,\n"),
    "k7 decide: the lever's hash is the uploaded one": (LEVEL_DRESS, 'local FAILED_HASH = "(the dressFail lever)"\n', 'local FAILED_HASH = "plan-1"\n'),
    "k7 decide: every Model is a template": (LEVEL_DRESS, "\t\t\tLevelDress.Present(ask.templates),\n", "\t\t\t(function(): any\n\t\t\t\tlocal all = {}\n\t\t\t\tfor name in ask.templates do\n\t\t\t\t\tall[name] = true\n\t\t\t\tend\n\t\t\t\treturn all\n\t\t\tend)(),\n"),
    "k7 decide: the found shortcut not left out": (LEVEL_DRESS, "\t\t\tLevelDress.LeftOut(ask.layout, ask.found),\n", "\t\t\t{},\n"),
    "k7 decide: the groups not asked": (LEVEL_DRESS, "\t\t\task.groupsOk,\n", "\t\t\ttrue,\n"),
    "k7 decide: maxParts not asked": (LEVEL_DRESS, "\t\t\task.maxParts,\n", "\t\t\tmath.huge,\n"),
    "k7 decide: a refusal names nothing": (LEVEL_DRESS, '\t\treturn nil, reason or "the dress was refused"\n', '\t\treturn nil, "the dress was refused"\n'),
    # Lay.
    "k7 lay: no wall appended": (LEVEL_DRESS, "\ttable.move(accepted.walls, 1, #accepted.walls, #built + 1, built)\n", ""),
    "k7 lay: the walls written into the layout's pieces": (LEVEL_DRESS, "\tlocal built = table.clone(pieces)\n", "\tlocal built = pieces\n"),
    "k7 lay: nothing hidden": (LEVEL_DRESS, "\t\thidden = accepted.hidden,\n", "\t\thidden = {},\n"),
    "k7 lay: the dress's looks not laid": (LEVEL_DRESS, "\t\tlooks = LevelDress.Overlay(base, accepted.looks),\n", "\t\tlooks = base,\n"),
    "k7 lay: no word": (LEVEL_DRESS, "\t\tword = accepted.word,\n", "\t\tword = nil,\n"),
    "k7 lay: grey takes no base looks": (LEVEL_DRESS, "\t\treturn { pieces = pieces, hidden = {}, looks = base, word = nil }\n", "\t\treturn { pieces = pieces, hidden = {}, looks = nil, word = nil }\n"),
    "k7 lay: grey is dressed with nothing": (LEVEL_DRESS, "\tif accepted == nil then\n\t\treturn { pieces = pieces", '\tif accepted == nil then\n\t\taccepted = { walls = {}, hidden = {}, looks = {}, word = { layout = "", planHash = "" } }\n\tend\n\tif false then\n\t\treturn { pieces = pieces'),
}

# luau-engineer A's proposed mutate.py entries on LevelService for the L4 W2 fix round (K7). They are
# caught only once D2's whole-line pins (run_harness.py L4W2_LINES / L4W2_ORDER) read the new lines.
LEVEL_SERVICE = "src/combat/server/Services/LevelService.luau"

K7_PIN_MUTATIONS = {
    # Build (slice 4 P3, P1; slice 2 s2).
    "k7 pins: no level is dressed": (LEVEL_SERVICE, "\tif layoutName ~= nil then\n\t\taccepted = dressOf(", "\tif false then\n\t\taccepted = dressOf("),
    "k7 pins: the dress asked of no level": (LEVEL_SERVICE, "\t\taccepted = dressOf(layout, layoutName, pieces, open, rules.maxParts)\n", ""),
    "k7 pins: the answer not laid": (LEVEL_SERVICE, "\tlocal laid = LevelDress.Lay(pieces, expeditions.looks, accepted)\n", "\tlocal laid = LevelDress.Lay(pieces, expeditions.looks, nil)\n"),
    "k7 pins: built from the grey pieces": (LEVEL_SERVICE, "\tlocal camps, problem = place(folder, laid, expeditions, reactive, ice)\n", "\tlocal camps, problem = place(folder, LevelDress.Lay(pieces, expeditions.looks, nil), expeditions, reactive, ice)\n"),
    "k7 pins: SetCamp's looks not the laid ones": (LEVEL_SERVICE, "\tstate.looks = laid.looks\n", "\tstate.looks = expeditions.looks\n"),
    "k7 pins: hidden, but the word never set": (LEVEL_SERVICE, "\tif word ~= nil then\n", "\tif false then\n"),
    "k7 pins: DressHash never set": (LEVEL_SERVICE, "\t\tfolder:SetAttribute(CONST.DRESS_HASH_ATTRIBUTE, word.planHash)\n", ""),
    "k7 pins: Dress never set": (LEVEL_SERVICE, "\t\tfolder:SetAttribute(CONST.DRESS_ATTRIBUTE, word.layout)\n", ""),
    "k7 pins: Dress before DressHash": (LEVEL_SERVICE, "\t\tfolder:SetAttribute(CONST.DRESS_HASH_ATTRIBUTE, word.planHash)\n\t\tfolder:SetAttribute(CONST.DRESS_ATTRIBUTE, word.layout)\n", "\t\tfolder:SetAttribute(CONST.DRESS_ATTRIBUTE, word.layout)\n\t\tfolder:SetAttribute(CONST.DRESS_HASH_ATTRIBUTE, word.planHash)\n"),
    # construct (slice 1 m1's looks probe; the hidden branch; the wall's look).
    "k7 pins: construct builds in the base looks": (LEVEL_SERVICE, "\tlocal looks = laid.looks\n", "\tlocal looks = if expeditions ~= nil then expeditions.looks else nil\n"),
    "k7 pins: construct reads no hidden names": (LEVEL_SERVICE, "\tlocal hidden = laid.hidden\n", "\tlocal hidden = {}\n"),
    "k7 pins: construct builds the grey pieces": (LEVEL_SERVICE, "\tfor _, piece in laid.pieces do\n", "\tfor _, piece in laid.pieces do\n\t\tif piece.role == LevelDress.WALL_ROLE then\n\t\t\tcontinue\n\t\tend\n"),
    "k7 pins: no hidden piece is hidden": (LEVEL_SERVICE, "\t\tif hidden[piece.name] then\n", "\t\tif false then\n"),
    "k7 pins: the dress wall drawn": (LEVEL_SERVICE, "\t\t\tpart.CollisionGroup = BarrierGroups.BARRIER\n\t\t\tpart.Transparency = 1\n\t\t\tpart.CanTouch = false\n\t\t\tpart.CastShadow = false\n\t\t\tpart.CanCollide = true\n", "\t\t\tpart.CollisionGroup = BarrierGroups.BARRIER\n\t\t\tpart.Transparency = 0\n\t\t\tpart.CanTouch = false\n\t\t\tpart.CastShadow = false\n\t\t\tpart.CanCollide = true\n"),
    "k7 pins: the lobby built with no looks": (LEVEL_SERVICE, "\treturn place(folder, LevelDress.Lay(pieces, base, nil), expeditions, reactive, ice)\n", "\treturn place(folder, LevelDress.Lay(pieces, nil, nil), expeditions, reactive, ice)\n"),
    # dressOf (slice 4 P2, P6; the gathered ask).
    "k7 pins: the lever latched on": (LEVEL_SERVICE, "\tlocal failLever = state.failNextDress\n", "\tlocal failLever = true\n"),
    "k7 pins: the lever never spent": (LEVEL_SERVICE, "\tlocal failLever = state.failNextDress\n\tstate.failNextDress = false\n", "\tlocal failLever = state.failNextDress\n"),
    "k7 pins: the lever not handed on": (LEVEL_SERVICE, "\t\tfailLever = failLever,\n", "\t\tfailLever = false,\n"),
    "k7 pins: the uploaded hash not asked": (LEVEL_SERVICE, "\t\tuploadedHash = uploadedHash(layoutName),\n", "\t\tuploadedHash = nil,\n"),
    "k7 pins: the dress file not read": (LEVEL_SERVICE, "\t\tdress = Catalog.GetLevelDress(layoutName),\n", "\t\tdress = nil,\n"),
    "k7 pins: the found shortcuts not handed on": (LEVEL_SERVICE, "\t\tfound = open,\n", "\t\tfound = nil,\n"),
    "k7 pins: the groups never asked": (LEVEL_SERVICE, "\t\tgroupsOk = BarrierGroups.Ensure(),\n", "\t\tgroupsOk = true,\n"),
    "k7 pins: the grey level not warned": (LEVEL_SERVICE, "\t\twarn(`[LevelService] the level is grey: {reason}`)\n", ""),
    # templatesOf (slice 1 s2): a Model counts by its MeshParts' MeshIds, not its name.
    "k7 pins: a template counted by its name": (LEVEL_SERVICE, "\t\t\t\t\t\ttable.insert(meshIds, part.MeshId)\n", '\t\t\t\t\t\ttable.insert(meshIds, "rbxassetid://1")\n'),
    "k7 pins: a template with no MeshPart counted": (LEVEL_SERVICE, '\t\t\t\tlocal meshIds: { string } = {}\n', '\t\t\t\tlocal meshIds: { string } = { "rbxassetid://1" }\n'),
}
```

## What to check in Studio

1. Forest Road on Normal: the forest draws, Output shows no `[LevelService] the level is grey` line. (This is also the
   proof that `MeshPart.MeshId` reads the templates' `MeshContent` URI; if it did not, the warn would read `the mesh "..."
   has no template with a mesh` and the level would be grey.)
2. Press Z, then start a level: grey, one warn naming `(the dressFail lever)`; the next start is dressed again.
3. In the Explorer, during a dressed run: `Workspace.Level` carries `DressHash` and `Dress`; in the lobby both are empty.

## Follow-up: K3's server half, the lobby's prewarm (the lead's routing of ui-b.md)

Files: `src/combat/server/Services/WaveService.luau`, `src/combat/server/Services/StageFlow.luau` (neither had another
owner this round; the lead routed this here), `tools/crowd_harness/tests_l4w2.luau`. No remote, payload or config change:
`RunState.prewarm` already exists and ArenaService already sends it with a floor set's first RunState per member.

- **`StageFlow.MostKinds(kinds: { { [string]: number } }): { [string]: number }?`** (pure): each kind's most over the
  plans' `kinds`, a new table; nil when no entry fields a body.
- **WaveService:**
  - `boot.lobbyKinds` / `boot.lobbyKindsSeq`.
  - `refreshLobbyKinds()` reads and plans every built level (`builtLevels()`) at every difficulty of `map.difficulties`
    exactly as `startLevel` does (`resolveLevel`, then `StageFlow.Plan` with `LevelGeometry.Bounds(layout,
    rules.floorThickness)` and `Tuning.Get().crowd.kinds`, behind a pcall), and merges the plans with `MostKinds`.
    - It is made once, since the files are static.
    - While none can be made, it is tried again once per floor set, so a broken file warns once per lobby.
    - It never yields.
  - It is called in `Boot` and on each broadcast tick before `broadcast()`.
  - `pushRunFields`: `prewarm = if phase == "lobby" then boot.lobbyKinds else run.prewarm,`.
  - So the lobby RunState that carries a floor set's cells (the boot lobby, every return, every admit and rejoin)
    carries the envelope, once per member, like the cells.
- **Shipped value** (harness, the three Forest Road plans): `armoured 13, brute 32, chief 1, fodder 50, lobber 2,
  marksman 3, slinger 26` (127 bodies). The client splits it under `crowd.maxAlive` (ui B).

**Assumptions:**
1. "The level the lobby would start" is read as **every built level at every difficulty**: the lobby cannot know the
   leader's pick. Today that is Forest Road's three plans, as ui B's sketch has it. Once a second level is built, the
   envelope spans both. If the lead wants only the leader's open nodes, that is a filter on `builtLevels()` plus a
   recompute on a leader change.
2. If the first try fails at boot and a later tick succeeds within the same lobby, the members already sent that floor
   set's cells get no lobby prewarm. The run's own prewarm still fills the pools at the start.

**Tests** (`tests_l4w2.luau`, group "lobby kinds"):
- the per-kind most;
- a new table, with the inputs unchanged;
- the order of the plans does not matter;
- no plan, or none fielding a body, gives nil;
- the shipped levels' plans at every difficulty equal an independent per-kind max (3 plans) and cover every plan's own
  counts.

All pass.

**For D2:**
- **One more failing pin:**
  - `pushPrewarm` (WAVE_SERVICE, PUSH_RUN_FIELDS_BODY, text `prewarm = run.prewarm,`) is now
    `\t\tprewarm = if phase == "lobby" then boot.lobbyKinds else run.prewarm,` (whole line).
  - The harness is now **FAIL (19 of 4,478)**: the 18 K7 pins above plus this one. Every tests_l4w2 case passes.
- **New pins** (whole lines, count 1, in `body_of("refreshLobbyKinds")`):
  - `\tif boot.lobbyKinds ~= nil or boot.lobbyKindsSeq == boot.floorsSeq then`
  - `\tboot.lobbyKindsSeq = boot.floorsSeq`
  - `\tfor levelId in builtLevels() do`
  - `\t\tfor _, difficulty in map.difficulties do`
  - `\t\t\tlocal level, layout = resolveLevel(levelId, difficulty, combatConfig, map)`
  - `\t\t\t\t\tLevelGeometry.Bounds(layout, rules.floorThickness),`
  - `\t\t\t\t\tTuning.Get().crowd.kinds`
  - `\t\t\t\ttable.insert(found, plan.kinds)`
  - `\tboot.lobbyKinds = StageFlow.MostKinds(found)`
- **In `body_of("WaveService.Boot")`:**
  - `\trefreshLobbyKinds()` (count 1, before `boot.loop = `);
  - `\t\t\trefreshLobbyKinds()` (count 1);
  - order `refreshLobbyKinds()` before `broadcast()`.
- **ArenaService:** the existing `sendPrewarm` / `cellsWentThenPrewarm` pins already hold the once-per-member send.
- **mutate.py:**
  - `K3_A_MUTATIONS` (5, StageFlow): caught by tests_l4w2, 5 of 5 in my scratch runner.
  - `K3_PIN_MUTATIONS` (8, WaveService): caught once the pins above are in.
  - Every text occurs exactly once. The scan of all 1,914 existing entries still shows only the 5 stale K7 ones listed
    above. mutate.py's FILES already holds StageFlow and WaveService.

**Gates:**
- `stylua` and `selene` on StageFlow, WaveService and the test file: clean. The test file shows only the harness globals.
- `luau-lsp analyze` on `src/combat/server` and `src/shared` against the combat sourcemap: 0 diagnostics.
- `check_compile.py`: PASS, 182 files.
- Harness: FAIL (19 of 4,478), all of them pins (above).

**What to check in Studio:**
- Open `proving.rbxl` with Play and wait in the lobby camp before starting.
- Then start Forest Road: the first raiders show as models at once, with no placeholder second.
- It shows best with ui B's Figures change in.

```python
# luau-engineer A's proposed mutate.py entries for K3's server half (the lobby's prewarm).
FLOW = "src/combat/server/Services/StageFlow.luau"

# Caught by tests_l4w2.luau ("lobby kinds").
K3_A_MUTATIONS = {
    "k3 lobby: MostKinds sums the plans": (FLOW, "\t\t\tif count > (most[kind] or 0) then\n\t\t\t\tmost[kind] = count\n", "\t\t\tif count > 0 then\n\t\t\t\tmost[kind] = (most[kind] or 0) + count\n"),
    "k3 lobby: MostKinds keeps the last plan's count": (FLOW, "\t\t\tif count > (most[kind] or 0) then\n", "\t\t\tif count > 0 then\n"),
    "k3 lobby: MostKinds sends an empty table": (FLOW, "\treturn if any then most else nil\n", "\treturn most\n"),
    "k3 lobby: MostKinds sends nothing": (FLOW, "\treturn if any then most else nil\n", "\treturn nil\n"),
    "k3 lobby: MostKinds writes into a plan's kinds": (FLOW, "\tlocal most: { [string]: number } = {}\n\tlocal any = false\n", "\tlocal most: { [string]: number } = kinds[1] or {}\n\tlocal any = false\n"),
}
# luau-engineer A's proposed mutate.py entries on WaveService for K3's server half. Caught once
# D2's pins read the lines (run_harness.py: pushRunFields, refreshLobbyKinds, WaveService.Boot).
WAVE_SERVICE = "src/combat/server/Services/WaveService.luau"

K3_PIN_MUTATIONS = {
    "k3 pins: the lobby sends no prewarm": (WAVE_SERVICE, '\t\tprewarm = if phase == "lobby" then boot.lobbyKinds else run.prewarm,\n', "\t\tprewarm = run.prewarm,\n"),
    "k3 pins: the lobby kinds not made at boot": (WAVE_SERVICE, "\trefreshLobbyKinds()\n\tboot.loop = ", "\tboot.loop = "),
    "k3 pins: the lobby kinds never tried again": (WAVE_SERVICE, "\t\t\trefreshLobbyKinds()\n\t\t\tbroadcast()\n", "\t\t\tbroadcast()\n"),
    "k3 pins: the lobby kinds made on every broadcast": (WAVE_SERVICE, "\tif boot.lobbyKinds ~= nil or boot.lobbyKindsSeq == boot.floorsSeq then\n", "\tif false then\n"),
    "k3 pins: a failed try retried every broadcast": (WAVE_SERVICE, "\tboot.lobbyKindsSeq = boot.floorsSeq\n", ""),
    "k3 pins: one difficulty planned": (WAVE_SERVICE, "\t\tfor _, difficulty in map.difficulties do\n\t\t\tlocal level, layout = resolveLevel(", "\t\tfor _, difficulty in { map.difficulties[1] } do\n\t\t\tlocal level, layout = resolveLevel("),
    "k3 pins: no plan kept": (WAVE_SERVICE, "\t\t\t\ttable.insert(found, plan.kinds)\n", ""),
    "k3 pins: the plans not merged": (WAVE_SERVICE, "\tboot.lobbyKinds = StageFlow.MostKinds(found)\n", "\tboot.lobbyKinds = found[1]\n"),
}
```
