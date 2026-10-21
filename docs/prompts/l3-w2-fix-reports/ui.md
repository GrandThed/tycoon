# L3 W2 fix round: ui-engineer report (C1 to C5)

Worktree `C:\Users\benja\Desktop\tycoon-p5`, branch `l3-w2`. Nothing is committed. I edited only the four files in my row.

## Files changed

- `src/combat/client/Controllers/HeldWeapons.luau`: C1 and C4.
- `src/client/UI/ArmoryStage.luau`: C1 and C3.
- `src/client/UI/ArmoryShelf.luau`: C2.
- `src/client/UI/Theme.luau`: C2, the C3 constants, and C5.

## What each ruling became

**C1 (1-m3): Base by name.**
- Both clones now find `Base` by name and set `PrimaryPart = base` before any weld or `PivotTo`, as PlotService and PropFactory do. Each file has its own `local TEMPLATE_BASE_NAME = "Base"`, like those two.
- Both `templateOf` functions refuse a template with no `Base` BasePart. Nothing is cloned for such a template, and it counts as a missing template, so it stays silent.
- The clone is checked a second time and destroyed if `Base` is missing.
- Neither file reads `template.PrimaryPart` or `model.PrimaryPart` any more.

**C2 (3-m2): the ghost tone.**
- The value is `Theme.ARMORY_SCREEN_ICON_GHOST = Color3.fromRGB(140, 155, 190)`. It is read only by the shelf: `card.icon.ImageColor3 = if owned then WHITE else Theme.ARMORY_SCREEN_ICON_GHOST`.
- The stage keeps `ARMORY_STAGE_SILHOUETTE` on its light band, and that constant's Theme comment now says "the stage only".
- **The contrast:** the tone itself, as a flat colour, is **6.0:1** against `ARMORY_SCREEN_CARD_DARK` (22, 29, 50). That is WCAG contrast, with the sRGB colours linearised.
- **Read this before judging it: `ImageColor3` multiplies the icon's own colours.** It cannot paint a flat shape lighter than black.
  - The rendered pixel is (icon colour × tone).
  - So the unowned icon shows as the weapon itself, dimmed and cooled toward blue-grey, with its shading and some of its hue (the Smg's green, the Launcher's orange).
  - A flat ghost-tone shape would need a white mask image, which means an upload, so I did not make one.
  - A tone near 2:1, which is what a flat ghost would have used (for example (62, 76, 108)), renders darker than the card on most pixels. That is why the tone is this light.
- **Measured on the real 256 px icons** (Pillow, LANCZOS down to the 40 px the card draws, composited on (22, 29, 50) with each pixel's alpha, over pixels with alpha ≥ 0.5):

| Icon | Median contrast | Pixels at ≥ 1.5 |
|---|---|---|
| Spear | 1.59 | 59% |
| Rifle | 1.65 | 67% |
| Flamethrower | 1.74 | 65% |
| Warhammer | 1.82 | 82% |
| Shotgun | 1.95 | 79% |
| Longbow | 2.08 | 86% |
| Splitbow | 2.09 | 86% |
| Broadsword | 2.15 | 93% |
| Greataxe | 2.30 | 78% |
| Launcher | 2.59 | 87% |
| FrostHammer | 2.77 | 96% |
| Beam | 3.05 | 91% |
| Smg | 3.12 | 90% |
| Spinblade | 3.20 | 100% |
| Chaingun | 3.57 | 99% |

  - The old near-black silhouette measured the same way gives a median of 1.15 to 1.20, with 0% of pixels at 1.5 (the reviewer's 1.14).
  - A preview, with the owned icon on the light card, then the old silhouette, then the ghost, is at `C:\Users\benja\AppData\Local\Temp\claude\c--Users-benja-Desktop-tycoon\f6c03e29-23c5-4dc8-ba99-ba7296a3858e\scratchpad\ui\ghost_preview.png`.
- **For the lead:** if Ben wants a flat silhouette rather than a dimmed weapon, the only flat option without an upload is the reviewer's (a): the black silhouette on a lighter plate behind the icon (`icon.BackgroundColor3` plus a corner). That is two lines in ArmoryShelf and one Theme colour.

**C3 (3-s2, 3-s3, 3-s4): the stage's turn, drag and stick.**
- **One `syncTurn()`** runs on `SetActive(true)`, on `Show(nil)` and after each `selectFamily` in `Show`.
  - The stage's live connections exist **only while the screen is open on Weapons with a model shown**: the slow turn (`RenderStepped`, behind `not Theme.lowEndDevice`), the right stick's `InputChanged`, and `WindowFocusReleased`.
  - Otherwise it calls `stop()`, which drops all three, zeroes the stick and ends any drag.
  - `SetActive(false)` still calls `stop()` directly.
  - Before the paste (no templates) there is now no `RenderStepped` connection at all (3-s2).
- **A drag ends** in four cases:
  - on any `InputEnded` of its own input (a touch's InputObject, or the mouse button's type);
  - on a mouse movement while `IsMouseButtonPressed(MouseButton1)` is false (a release that was lost);
  - on `WindowFocusReleased`;
  - on close, on the Abilities tab, on no model, and on `Destroy`, all through `stop()`.
- **Gamepad right stick on every device.**
  - Past `ARMORY_STAGE_STICK_DEADZONE` (0.2), the stick's X sets a rate of up to `ARMORY_STAGE_STICK_DEGREES_PER_SECOND` (120). It turns the same way a drag does.
  - Off low-end, the per-frame turn uses that rate in place of the slow turn.
  - On a low-end device each stick event moves the camera once, by the time since the stick last moved, capped at `ARMORY_STAGE_STICK_STEP_SECONDS` (0.1). The first event off rest only arms it, so the view does not jump. There is no per-frame work.
  - A drag in progress beats the stick.
- The yaw changes in one place, `turnBy(degrees)` (drag, stick, slow turn).

**C4 (3-s7): one show per character per batch.**
- Every event-driven show goes through `queueShow(rig)`: the three attribute signals, a mount part arriving and an attachment arriving.
  - `queueShow` sets `rig.pending` and calls `task.defer(flush, rig)` once.
  - `flush` clears `pending` and shows the rig if it is still bound. `unbind` sets `rig.bound = false`, so a deferred show of a rig that is gone does nothing.
  - One server write (three attributes) is now one show, and a flood of `WeaponHeld` flips is at most one show per batch.
- The direct calls stay direct: `show(rig)` at the end of `bind`, in `SetLocalStance` (the local switch stays on its own frame), and `refreshAll`.
- **An addition the ruling did not name: `Muzzle` calls `flush(rig)` first.**
  - Without it, C4 would bring 3-m1 back on the client even after S6.
  - The teammate's attribute handler and the remote that follows it in the same batch are queued in that order. The deferred show goes to the back of the queue, so the remote's effect would read a stale `rig.inHand` and start at the other weapon's tip.
  - With the flush, the effect reads the weapon now in the hand.
  - `flush` is a no-op unless a change is pending, so FlameFx's and the beams' per-frame `Muzzle` calls cost nothing more. A flood still gets at most one show per frame.

**C5 (3-s6).** The comment now reads `COMBAT_WEAPON_WAIT_SECONDS = 3, -- WaitForChild budget for the arm that holds the shoulder joint`. Its only reader is WeaponController's `SHOULDER_PARENTS` wait.

## The harness: two checks need re-aiming (luau-engineer)

`HARNESS: FAIL (2 of 3,972 checks)`. Both failures are T14 counts, and both are expected from C3:
- `activeFrames` reads 0 (expected 1);
- `gatedFrames` reads 0 (expected 1).

Both read the `stageActive` body, which is `SetActive`, and the `RenderStepped` connection moved to `syncTurn` because the ruling ties it to a shown model.

The one-line re-aim in `run_harness.py`:

```python
"stageActive": (ARMORY_STAGE, re.compile(r"(?ms)^\tlocal function syncTurn\(.*?^\tend$")),
```

I proved it on a scratch copy of the repo, with the harness patched only there: `HARNESS: PASS (3,972 checks)`. The copy is deleted, and the real harness is untouched.

The case labels in `tests_l3_w2.luau` ("... in SetActive ...") would want new wording. `SetActive` still reaches `syncTurn()`; that line is pinned below.

**Stale `mutate.py` targets** (their text is gone):
- `"l3w2 T14: the stage turns on reducedMotion"` and `"l3w2 T14: the stage turns on a low-end device"` both aim at `"\t\t\tif not Theme.lowEndDevice then\n\t\t\t\tlook.turn = RunService.RenderStepped:Connect("`.
  - The new text is `"\t\tif look.turn == nil and not Theme.lowEndDevice then\n\t\t\tlook.turn = RunService.RenderStepped:Connect("`.
  - Replace `not Theme.lowEndDevice` with `not Theme.reducedMotion`, and with `true`, respectively.
- `"l3w2 T14: the model is posed every frame"` aims at `"\t\t\t\t\t\t% 360\n\t\t\t\t\tplace()\n"`.
  - The new text is `"\t\t\t\tturnBy(rate * deltaTime)\n"`.
  - For example, replace it with `"\t\t\t\t(look.model :: any):PivotTo(CFrame.identity)\n\t\t\t\tturnBy(rate * deltaTime)\n"`.
- Every HeldWeapons mutant target is unchanged: the T11 cache and clone, every T12 seal line, T13 and the ruling 6 texts.

## Exact final text of the client lines to pin

These are Python string literals as the harness writes them (`\t` is a tab, `\n` a newline). Each occurs **exactly once** in its file (checked by script).

**S3's named lines**

| What | File | Text |
|---|---|---|
| the stage's `stop()` in `SetActive(false)` | ArmoryStage | `"\t\t\tif not active then\n\t\t\t\tstop()\n\t\t\t\treturn\n\t\t\tend\n"` |
| `clear()` as `selectFamily`'s first line | ArmoryStage | `"\tlocal function selectFamily(family: string): ()\n\t\tclear()\n"` |
| `entry.model:Destroy()` in `show`'s cleanup | HeldWeapons | `"\t\t\t\tcache[family] = nil\n\t\t\t\tentry.model:Destroy()\n"` |
| `names.held` among the watched names | HeldWeapons | `"\tfor _, name in { names.melee, names.ranged, names.held } do\n"` |
| the attribute handler (now queued, C4) | HeldWeapons | `"\t\t\tcharacter:GetAttributeChangedSignal(name):Connect(function()\n\t\t\t\tqueueShow(rig)\n\t\t\tend)\n"` |
| `show(rig)` at the end of `bind` | HeldWeapons | `"\t\t)\n\tend\n\tshow(rig)\nend\n"` |
| `show(rig)` in `SetLocalStance` | HeldWeapons | `"\tlocal rig = rigs[Players.LocalPlayer]\n\tif rig ~= nil then\n\t\tshow(rig)\n\tend\nend\n"` |
| the PlayerAdded watch | HeldWeapons | `"\ttable.insert(connections, Players.PlayerAdded:Connect(watchPlayer))\n"` |
| the mount re-show (now queued) | HeldWeapons | `"\t\t\tif isMountPart(child.Name) then\n\t\t\t\twatchPart(rig, child)\n\t\t\t\tqueueShow(rig)\n\t\t\tend\n"` |
| the attachment re-show (now queued) | HeldWeapons | `"\t\t\tif child.Name == GRIP_ATTACHMENT or child.Name == BACK_ATTACHMENT then\n\t\t\t\tqueueShow(rig)\n\t\t\tend\n"` |
| unowned on the stage | ArmoryStage | `"\t\t\tviewport.ImageColor3 = if owned then WHITE else Theme.ARMORY_STAGE_SILHOUETTE\n"` |
| unowned on the shelf (C2) | ArmoryShelf | `"\t\t\tcard.icon.ImageColor3 = if owned then WHITE else Theme.ARMORY_SCREEN_ICON_GHOST\n"` |
| `setRest`'s ease (not my file, unchanged) | WeaponController | `"\trigPoseTo(rig, degrees, Theme.COMBAT_SWING_SETTLE_SECONDS, Enum.EasingStyle.Quad)\n"` |
| `remotePoseFor`'s raised write (not my file, unchanged) | WeaponController | `"\tfresh.rest = restOf(rigModel)\n\tlocal freshMotor = fresh.motor\n\tif freshMotor ~= nil and fresh.rest ~= 0 then\n\t\tfreshMotor.C0 = restFrame(fresh)\n\tend\n"` |

**New lines worth pinning (C1, C3, C4)**

| What | File | Text |
|---|---|---|
| C1: the name, once per file | HeldWeapons, ArmoryStage | `'local TEMPLATE_BASE_NAME = "Base"\n'` |
| C1: `templateOf` needs Base | HeldWeapons | `"\tlocal base = template:FindFirstChild(TEMPLATE_BASE_NAME)\n\tif base == nil or not base:IsA(\"BasePart\") then\n\t\treturn nil\n\tend\n\treturn template\n"` |
| C1: the clone's Base becomes PrimaryPart (before the WeldConstraints and the Weld) | HeldWeapons (`modelFor`) | `"\tlocal model = template:Clone()\n\tlocal base = model:FindFirstChild(TEMPLATE_BASE_NAME)\n\tif base == nil or not base:IsA(\"BasePart\") then\n\t\tmodel:Destroy()\n\t\treturn nil\n\tend\n\tmodel.PrimaryPart = base\n"` |
| C1: `templateOf` needs Base | ArmoryStage | `"\tlocal base = template:FindFirstChild(TEMPLATE_BASE_NAME)\n\tif base == nil or not base:IsA(\"BasePart\") then\n\t\treturn nil, nil\n\tend\n\treturn template, def\n"` |
| C1: PrimaryPart before the PivotTo | ArmoryStage (`selectFamily`) | `"\t\tlocal model = template:Clone() :: Model\n\t\tlocal base = model:FindFirstChild(TEMPLATE_BASE_NAME)\n\t\tif base == nil or not base:IsA(\"BasePart\") then\n\t\t\tmodel:Destroy()\n\t\t\treturn\n\t\tend\n\t\tmodel.PrimaryPart = base\n"` |
| C3: not live, then stop | ArmoryStage (`syncTurn`) | `"\tlocal function syncTurn(): ()\n\t\tif not look.active or look.model == nil then\n\t\t\tstop()\n\t\t\treturn\n\t\tend\n"` |
| C3: the gate and the one RenderStepped | ArmoryStage (`syncTurn`) | `"\t\tif look.turn == nil and not Theme.lowEndDevice then\n\t\t\tlook.turn = RunService.RenderStepped:Connect(function(deltaTime: number)\n"` |
| C3: the per-frame step | ArmoryStage (`syncTurn`) | `"\t\t\t\tturnBy(rate * deltaTime)\n"` |
| C3: the stick's listener | ArmoryStage (`syncTurn`) | `"\t\tif #look.inputs == 0 then\n\t\t\ttable.insert(look.inputs, UserInputService.InputChanged:Connect(onStick))\n"` |
| C3: focus loss | ArmoryStage (`syncTurn`) | `"\t\t\t\tUserInputService.WindowFocusReleased:Connect(function()\n\t\t\t\t\tlook.stickX = 0\n\t\t\t\t\tendDrag()\n\t\t\t\tend)\n"` |
| C3: `stop` drops the inputs, the stick and the drag | ArmoryStage (`stop`) | `"\t\tfor _, connection in look.inputs do\n\t\t\tconnection:Disconnect()\n\t\tend\n\t\ttable.clear(look.inputs)\n\t\tlook.stickX = 0\n\t\tendDrag()\n\tend\n"` |
| C3: `SetActive(true)` syncs | ArmoryStage | `"\t\t\t\twarm()\n\t\t\tend\n\t\t\tsyncTurn()\n\t\tend,\n"` |
| C3: `Show(nil)` syncs | ArmoryStage | `"\t\t\t\tclear()\n\t\t\t\tlook.family = nil\n\t\t\t\tsyncTurn()\n"` |
| C3: a selection syncs | ArmoryStage | `"\t\t\t\tselectFamily(view.family)\n\t\t\t\tsyncTurn()\n"` |
| C3: right stick only | ArmoryStage (`onStick`) | `"\t\tif input.KeyCode ~= Enum.KeyCode.Thumbstick2 then\n"` |
| C3: low-end stick, once per event | ArmoryStage (`onStick`) | `"\t\tif Theme.lowEndDevice and look.stickX ~= 0 and stickX ~= 0 and look.drag == nil then\n"` |
| C3: a lost mouse release | ArmoryStage (drag) | `"\t\t\t\tif not touch and not UserInputService:IsMouseButtonPressed(kind) then\n\t\t\t\t\tendDrag()\n\t\t\t\t\treturn\n\t\t\t\tend\n"` |
| C3: the drag's own end | ArmoryStage (drag) | `"\t\t\t\tif ended == input or (not touch and ended.UserInputType == kind) then\n\t\t\t\t\tendDrag()\n\t\t\t\tend\n"` |
| C4: queue once | HeldWeapons (`queueShow`) | `"\tif rig.pending then\n\t\treturn\n\tend\n\trig.pending = true\n\ttask.defer(flush, rig)\nend\n"` |
| C4: the flush | HeldWeapons (`flush`) | `"\tif not rig.pending then\n\t\treturn\n\tend\n\trig.pending = false\n\tif rig.bound then\n\t\tshow(rig)\n\tend\nend\n"` |
| C4: unbind unbinds | HeldWeapons (`unbind`) | `"\trigs[player] = nil\n\trig.bound = false\n"` |
| C4 + m1: Muzzle flushes first | HeldWeapons (`HeldWeapons.Muzzle`) | `"\tif rig ~= nil and rig.character == character then\n\t\tflush(rig)\n\tend\n"` |

Counts the luau-engineer may want:
- Lowercase `show(rig)` appears 4 times in HeldWeapons: in `flush`, at the end of `bind`, in `SetLocalStance`, and in `refreshAll`.
- `queueShow(rig)` appears 3 times.
- `= model.PrimaryPart` and `PrimaryPart ~= nil` appear 0 times in both files.
- `RenderStepped:Connect(` appears once in ArmoryStage, inside `syncTurn`'s gate branch.

## Remotes and state consumed

- No remotes, and no new state.
- HeldWeapons reads the same three character attributes as before (`WeaponLook.ATTRIBUTES`).
- The stage reads the `UserInputService` signals `InputChanged` (`Thumbstick2`), `WindowFocusReleased` and `IsMouseButtonPressed`.

## Assumptions

- Roblox applies a replicated attribute's value at once and queues its handler in arrival order. The `Muzzle` flush rests on that ordering; without the flush, C4 would undo S6 on other clients.
- A gamepad thumbstick may fire no `InputChanged` while it is held perfectly still. On a low-end device the stick then turns only while it moves (the price of "per stick event"). Off low-end, the per-frame turn keeps going at the last rate.
- The right stick is read, not sunk. Whatever the lobby camera does with it behind the open screen is unchanged from W1.
- No sound was added.

## Required changes outside my files

- **luau-engineer (`run_harness.py`, `tests_l3_w2.luau`, `mutate.py`):**
  - the `stageActive` re-aim above;
  - the three stale T14 mutant targets above;
  - S3's pins from the tables above.
- **Lead, design only:** C2's ghost is a dimmed weapon, not a flat shape (see C2). Keep it, or take option (a) on Ben's look.

## Gates (my four files)

| Gate | Result |
|---|---|
| stylua `--check` | clean |
| selene | 0 errors, 0 warnings |
| luau-lsp with `tools/types/globalTypes.d.luau`, default sourcemap (`src/client src/server src/shared`) | 0 diagnostics |
| luau-lsp, combat sourcemap (`src/combat src/shared` plus the three UI files) | 0 diagnostics |
| `py tools/check_compile.py` | PASS, 180 files |
| harness | FAIL, 2 of 3,972: the two re-aims above. PASS (3,972) with the re-aim, on a scratch copy |
| `rojo build`, both trees, into scratch | builds |
| line endings | LF, 0 CR |

Both sourcemaps were regenerated into my scratchpad only.

## What to check in Studio

**Before the paste**, which is today's state (no templates, no icons):
- Open the lobby Armory (K) and the hub Armory. The screen must look exactly like W1: the text stage and the text cards.
- Hands are empty, arms hang, and Output has no `[HeldWeapons]` line.
- With no model shown the stage holds no per-frame connection, so there is nothing to see.

**After the paste:**
1. Select an owned weapon. It turns slowly.
   - Drag it: it turns, and the slow turn carries on when you let go.
   - Alt-tab away mid-drag, then move the mouse with no button down: the weapon must not follow the mouse, and the slow turn resumes.
2. Gamepad: with the Weapons tab open, the right stick turns the weapon both ways and the slow turn resumes at rest. The d-pad still browses the cards.
3. Graphics quality 1 to 3 (`lowEndDevice`): no slow turn; a drag and the right stick still turn the weapon.
4. Shelf: the unowned cards show a dimmed, blue-grey weapon on the dark card. Judge it on a phone (preview path in C2). The owned cards are unchanged.
5. Two clients (*Prueba → Clientes y servidores*, 2 players):
   - Player 1 switches slot and casts Volley or Blade Storm. On player 2's screen the effect leaves from the weapon now in player 1's hand (S6 together with this report's `Muzzle` flush).
   - Player 1 holds a bow draw and spams it: player 2's view of player 1's arm stays steady, with no jitter.

**Mobile emulator.**
- At 375 × 667 (the hub's portrait grid, 68 × 56 cards) and 640 × 360 or 667 × 375 landscape: card and stage sizes are unchanged from W2, every tap target is still ≥ 48 design px, and a touch drag turns the stage.
- At 1920 × 1080 (frame capped at 880 × 420, stage 285 × 280): the layout is unchanged.
- Reasoning only: no size, position or new tap target changed in this round, only colours, connections and input handling.
