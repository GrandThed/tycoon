# L1b Wave 1 fix round — ui-engineer report

Brief: `docs/prompts/l1b-w1-fix-round.md` "ui-engineer"; findings `docs/prompts/l1b-w1-review/client.md`.
Client files only, no git. Base `e2479c3` had none of this section done.

## 1. Major: phone auto-fire never wakes a camp from range (client.md 1)

- `src/combat/client/Controllers/CrowdRenderer.luau`: `Floor` gains `camp: boolean` (true from
  `SetFloors`, false from the range's `SetFloor`). New `CrowdRenderer.CampFloor(id): (Vector3?, Vector3?)`
  returns the body's camp floor (top centre, half extents) or nil for the range, an unknown body or a
  floor not yet arrived. No new top-level local (152).
- `src/combat/client/Controllers/InputController.luau`: new `campInPlay(id, root)`. A body on a camp
  floor counts for `targetOnAuto` (auto-fire, bow auto-draw, auto-swing, cone gun) only when the local
  root is in the height band (`camps.sightBelow` / `sightAbove` from the floor top) and its flat distance
  to the floor RECTANGLE is at most `camps.chaseMargin` (rounded corners, the same test as A's rule 1).
  Read from `Combat.json` at runtime, so the economy-designer's 2.5 applies with no client change.
  `enemyInSights` / `enemyInReach` take the root (they have no other caller). Bodies with no camp floor
  (the range) and a missing config keep the old rule. Deliberate shots are untouched (L1b-4 stands).
  147 top-level locals.
- Boss room waves spawn on camp C's floor (`floor = zone.floor`), so they get the same test; a player
  fighting them is inside the locked room and so in play. The client cannot tell a held resident from a
  wave body on that floor, so a phone player standing inside camp C during the countdown can still
  auto-fire at held residents ("BLOCKED"): out of this ruling's scope, noted for the lead.
- No harness: the rule lives in a client controller. It mirrors CampBrain's rule 1 by reading; if A puts
  the rounded test in a shared pure module, the client should call it (one function swap).

## 2. Major: header text (client.md 2)

- `src/combat/client/UI/CombatHud.luau` `campText`: "Camps 1 / 3" (about 70 px at 12 px Gotham, fits
  the 74 px `aliveLabel`; the header's UIScale scales box and text together, so 375×667 and 1920×1080
  read the same). One-camp levels keep "N left".

## 3. Minors

- `src/combat/client/Controllers/CampFx.luau` `step`: disconnects its Heartbeat when no mark is left;
  `Alert` reconnects on demand.
- `CombatHud.luau`: `setRunState` hides the notice line and zeroes `noticeUntil` when the phase is
  `summary`, `ended` or `lobby`; `ShowNotice` ignores a call that arrives while the run is not in a live
  phase (a late checkpoint event).
- Abandon flicker: nothing added (A's rule 2, `engagedHoldSeconds`).

## Gates

- stylua (check clean), selene 0/0/0 on the four files.
- `py tools/check_compile.py --counts`: PASS (CrowdRenderer 152, InputController 147).
- `luau-lsp analyze` combat (fresh `rojo sourcemap combat.project.json`,
  `--definitions=tools/types/globalTypes.d.luau`, `src/combat src/shared`): no diagnostics.

## For the other owner

- None required. Optional (A): a shared pure `flat distance to rect` helper both CampBrain and the
  client could call.
