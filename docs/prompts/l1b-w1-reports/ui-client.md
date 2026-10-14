# L1b Wave 1 — ui-engineer report (client)

Contract: `docs/INTERFACES.md` "L1b contracts — the living road" -> "Client (ui-engineer)".
Every point of "Client" is done. No git was run.

## What I built

**`src/combat/client/Controllers/CrowdRenderer.luau`** (151 -> **152** top-level locals)
- One floor became a floor list: `floors` (:457), `floorY(entity, feetY)` (:513). The list is
  indexed by floor index.
- Each body carries `floorIndex`, taken from its spawn info's `floor` (:1725). nil, non-numbers
  and anything under 1 count as 1. A re-announce updates it.
- The four floor readers now read the body's own floor:
  - `loadThreat`: the threat origin height.
  - `pushSample`: the windup origin height.
  - `drawTell`: the tell height.
  - `laneReach` (:2104): the charge clamp.
- A body whose floor has not arrived yet uses its own feet height and gets no clamp.
- `SetFloors(list: { Types.RunFloor })` (:2572) is new. A malformed entry ends the list there.
- `SetFloor(center, half)` (:2560) now means "one floor at index 1". The range's `SetArena` still
  calls it, and an unknown arena still gives height 0 and no bound, the same as before.
- Poses, all procedural:
  - `seat` runs from 0 to 1. It eases toward 1 while the wire says `rest` and toward 0 otherwise,
    at a fixed pace of `Theme.COMBAT_RISE_BLEND_SECONDS` (:2191).
  - A body first seen at rest is drawn seated at once (:1528).
  - `queuePose` (:1767) lowers everything above the legs by `COMBAT_REST_DROP` × height. It lays
    the legs forward on the ground with a quarter turn about X and slerps between the two poses.
  - The figure has no arms, so "arms down" needs nothing.
  - A guard's one-step `rise` changes nothing, because it was already standing.
  - Dying and vanishing bodies keep their seat, so a sitter killed where it sits does not pop up.
- `GetHead(id)` (:2711) is new. It returns the head part of a living, drawn body; the alert hangs
  on it.
- `Prewarm(run.maxAlive)` is unchanged; `maxAlive` is now the population.

**`src/combat/client/Controllers/CampFx.luau`** (new, about 15 top-level locals)
- `Alert(ids)` (:154): a pooled BillboardGui with a "!" over each body's head part.
  - Its foot sits `COMBAT_ALERT_STUDS` (3) above the top of the head.
  - It is always on top and lasts `COMBAT_ALERT_SECONDS` (1.5).
  - It pops in (skipped where `reducedMotion` is on) and fades out over the last 0.3 s.
  - It restarts on a repeat wake rather than stacking a second mark.
  - A body not drawn is skipped. A mark is dropped as soon as its body dies, leaves or is pooled
    to another id.
- `Checkpoint()` (:202) calls the host's notice handler with "✓ Checkpoint" for
  `COMBAT_CHECKPOINT_NOTICE_SECONDS` (2).
- It has no sound. Its Heartbeat starts on the first alert, and `Destroy` disconnects it.

**`src/combat/client/Controllers/CombatFxController.luau`** (125 -> **126**)
- `onCamp` (:1264) sends `alert` and `checkpoint` to CampFx.
- `closed` shows the name banner and `cleared` shows "\<name\> cleared". There is no `saved`.
- `Destroy` also calls `CampFx.Destroy`.

**`src/combat/client/Controllers/CombatUIController.luau`**
- `isRunState` (:215) checks for a `floors` table instead of `banked`. `isRunResult` no longer
  checks `savedAt`.
- `applyFloors` (:1611, called at :1701) replaces `applyFloor`:
  - it compares the floors by value against a held copy;
  - it calls `CrowdRenderer.SetFloors` only when they differ;
  - the lobby's `{}` empties them.
- The wallet request on a bank is gone. Only the request at the end of a run is left (:1810).
- `CampFx.SetNoticeHandler(hud.ShowNotice)` (:1927).
- `placeBanner` reads `edges.noticeBottom`.

**`src/combat/client/UI/CombatHud.luau`**
- "Progress saved" and its `banked` watch are gone.
- That slot under the wallet is now a notice line, `ShowNotice(text, seconds)` (:133, :1312). It is
  never a tap target, and the banner still keeps clear of it.
- The dim line reads "Camps cleared X / Y" (:1025). A level of one camp keeps L1's "N left".
- The objective line is unchanged: in `travel` it shows the stage name ("Follow the road").
- Buttons and Abandon are unchanged.

**`src/combat/client/UI/SummaryCard.luau`**
- The "Saved at" / "Nothing was saved" line is gone.
- Progress and reward rows are as before.

**`src/client/UI/Theme.luau`**
- Added `COMBAT_REST_DROP` (0.35), `COMBAT_RISE_BLEND_SECONDS` (0.5) and `COMBAT_REST_HIP_SHARE`.
- Added the alert's seconds, studs, sizes (studs plus px), colour, stroke, pop, fade and
  maximum distance.
- Added `COMBAT_CHECKPOINT_NOTICE_SECONDS` (2) and its width and height.
- Removed `COMBAT_SAVED_NOTICE_SECONDS`, `_WIDTH` and `_HEIGHT`; a grep found no other reader.

## Gates (my files)
- `stylua --check` and `selene` are clean on all seven files.
- `py tools/check_compile.py` passes. The largest of my files are CrowdRenderer at 152 and
  CombatFxController at 126.
- `luau-lsp`: the combat client files are clean on the combat sourcemap, and the hub
  (`src/shared src/server src/client`) is clean.
  - The remaining combat errors are in CrowdService, StageFlow, WaveService and ArenaService. They
    are A's and B's work in progress.
- `rojo build` of default, combat and `.proving` succeeded. I built into a temp folder, so
  `build/` was not touched.
- Gate 12: `git diff --stat main -- src/server src/client` lists only `Theme.luau`.

## Layouts, worked out on paper (Studio cannot run here, so the DoD's screenshots are not in this report)
- **The "!" mark** is sized as 1 × 1.5 studs plus 16 × 24 px.
  - At 60 studs it is about 31 px tall on a 667 × 375 landscape phone (FOV 70: about 4.5 px per
    stud) and about 43 px on a 1080p monitor.
  - Its foot is 3 studs above the head. That clears the plate bar, which is 0.9 studs plus 7 px.
- **A seated fodder** is 3.25 studs tall against 5 standing, with its legs about 1.1 studs out in
  front.
  - At 50 studs that is about 17 px against 27 px on the phone and about 37 px against 64 px on a
    1080p monitor.
  - The torso bottom ends 0.12 to 0.26 studs under the floor for every kind (hidden).
- **The notice line** is 128 × 24 design px in the old "Progress saved" slot, which the fix round
  checked at 667 × 375 and 1920 × 1080. It is narrower than before.
- **The summary card** is one line shorter: about 250 design px solo against the 329 px limit.

## For the other owner (through the lead)
1. **The seated head is not the server's head** (lead / luau-engineer, a decision).
   - The server's hit shapes do not sit. A sitter is drawn with its head 35% of its height lower
     than the head the server judges crits on.
   - A shot at the drawn seated head scores a body hit. Aim assist (`CrowdRenderer.ForEach`
     height) pulls toward the standing head, above the drawn one.
   - `FeedbackController` places damage numbers at `GetHeight`, about 1.75 studs over a seated
     fodder's head.
   - Melee first strikes are not affected. If this should match, either the server lowers a
     `rest` body's head, or I report the seated height in `ForEach` and `GetHeight` (my file;
     that would make the client disagree with the server instead). I changed neither.
2. **Abandon under the left thumb on the road** (lead, a decision).
   - CombatHud hides Abandon on touch only in `wave` and `boss`, as the fix round ruled. The
     contract says "Buttons and Abandon unchanged".
   - In L1b the resident fights happen in `travel`, so the thumb hazard the fix round removed is
     back for every open-camp fight on a phone.
   - RunState carries no "engaged" flag, so the client cannot tell a road fight from a quiet walk.
   - Hiding it in all of `travel` would leave a phone player no Abandon on the road.
   - Options:
     - a RunState `engaged` boolean per member (B), which the HUD would read; or
     - accept the hazard (Abandon still asks twice).
3. Nothing is needed from A or B for the client to run. I consume `CrowdSpawnInfo.floor`,
   `RunState.floors` (RunFloor `{x,y,z,hx,hz}`), `RunState.maxAlive` and the CombatFx
   `camp {event, name, ids}` events (`alert`, `checkpoint`, `closed`, `cleared`).

## Where I went beyond or against the contract's wording
- **"The toast 'Checkpoint'"**: I put it on the HUD's notice line under the wallet, not in the
  `Toast` module. Reasons:
  - The fix round's "one message per event" keeps the toast for personal notices.
  - That slot's place on a landscape phone is already checked and kept clear by the banner.
- **The seat sits down too**: the seat eases the same 0.5 s when a group comes home to a fire, not
  only when it rises. Only a body first seen seated appears seated at once.
- **The "!" is always on top**, because raiders see through the palisade and the mark is the only
  sign that they did.
