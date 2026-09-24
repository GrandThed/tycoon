# Thumbnail shot list (M10)

Five real Studio screenshots become the experience thumbnails. Save each one as a PNG in
`assets/marketing/screenshots/` under the file name given, then run from the repo root:

```
py tools/marketing/caption.py --check
```

Finals land in `assets/marketing/final/thumbs/<id>.png` (1920×1080, under 3 MB). Each `<id>_check.png` beside a final
shades the bottom 15 % that Roblox's tile overlay covers: nothing important may sit there. The crop point and
captions live in `tools/marketing/shots.json`; change a `focus` there (0..1 of the screenshot) if the crop cuts the
subject, and rerun. A shot whose screenshots are missing is skipped, so you can shoot them one at a time.

Roblox rule for all five: real gameplay only. No mock-ups, no fake UI, no mechanics the game does not have. The
captions below only name things the game really does.

## Setup, once per session

1. **Levers that exist** (all Studio-only, inert live; Workspace → Properties → Attributes → **+**, type
   **number**, consumed on the server's 1 Hz tick and reset to `0`):
   - `GrantCash`: cash to every loaded player (`EconomyService`). `10000000000000` (10T) buys out
     Village–Metropolis; Orbital needs `3000000000000000` (3 quadrillion), re-added as needed.
   - Studio income is already ×100 (`Game.json` `debug.studioIncomeMultiplier`).
   - There is **no** level or era lever. Level with the Build panel's **×1 / ×10 / Max** buttons. Advance with the
     gold **"Advance Era → …"** banner, which appears at the top of the Build panel once all 24 slots of the era
     are owned.
2. **Advancing an era rebuilds the plot**, and without "Enable Studio Access to API Services" every Play session
   starts from a fresh mock profile. So shoot each era **before** you advance past it, in one session: Growth and
   Village first, then Boomtown, Metropolis and Orbital.
3. **Graphics quality:** leave Roblox's graphics quality on **Automatic** or at **4 and up** before pressing Play.
   The client reads it once at start (`Theme.lowEndDevice`), and at 1–3 it drops the birds, smoke and other
   ambient life.
4. **Lighting:** leave the place's default Lighting. The game does not set time of day, and a thumbnail must look
   like what players see. Orbital has the normal blue sky in game (there is no space skybox), so frame Orbital
   with little sky.
5. **Capture size:** maximise Studio, close the side panels so the 3D viewport is as large as possible, and
   capture the viewport only (Win+Shift+S, rectangle), at least **1920 px wide** if the monitor allows.
   `caption.py` cover-crops any size to 16:9, but upscaling a small capture looks soft.

## Hiding everything that is not the world (every shot)

Do this after pressing Play, in the window you will capture:

- **Game HUD and the Studio debug strip:** in Explorer, open **Players → *your player* → PlayerGui**, select
  **EraCityHUD** and untick **Enabled**. The debug strip ("⚙ debug") lives inside that ScreenGui, so it goes too.
  In a Local Server test, do it in the client window you capture, not the server window.
- **Roblox core UI and top bar:** switch the command bar to the **client** context (the Client/Server toggle on
  the Test ribbon during Play), then run:
  ```lua
  local sg = game:GetService("StarterGui"); sg:SetCoreGuiEnabled(Enum.CoreGuiType.All, false); sg:SetCore("TopbarEnabled", false)
  ```
  If the top-bar buttons still show, crop them out. The caption covers the top ~20 % of the frame anyway.
- **Keep:** buy-pad price boards and player name tags. They are real in-game UI, not fake.
- **Camera:** **Shift+P** toggles Roblox's developer freecam in a Studio playtest (WASD + right mouse; Q/E to
  go down/up). Use it for every shot except Social, and leave it on and unmoved between the two Growth
  captures. If Shift+P does nothing, use the normal camera: right-drag to orbit, mouse wheel to zoom.

## 1. Growth — `growth_low.png` + `growth_high.png` (2-up)

- **Era:** Village.
- **Owned:** the **Tavern** plus enough neighbours that it is not alone in a field (the free first slots are fine).
- **Capture:**
  1. Put the camera about 30–40 studs from the Tavern at roughly 30° down, with its front and the pad in view,
     and the Tavern slightly above centre.
  2. Save `growth_low.png` with the Tavern at **level 1**, just bought (stage 0).
  3. Without moving the camera, `GrantCash` and press **Max** on the Tavern row until it reads **level 100**
     (stage 4: two storeys, red roofs, tower).
  4. Wait for the growth pop to finish, then save `growth_high.png`.
- **Not in frame:** the HUD, the Build panel (reopen it only to level, close it before capturing), your own
  avatar in front of the building. Step off the pad first, or keep the avatar at the frame edge.
- **Caption:** **LEVEL IT UP!**, with the halves labelled **LEVEL 1** and **LEVEL 100**. `caption.py` draws the
  divider and the arrow between them. The 2-up layout is used because two identical camera positions make the
  growth unmistakable at thumbnail size.
- **Alternative with a bigger jump:** Metropolis **Bank Tower** (a 4-storey block that becomes a glass tower at
  stage 3). It costs an era advance, and the Village Tavern is the quickest to reach.

## 2. Eras — `eras_village.png`, `eras_boomtown.png`, `eras_metropolis.png`, `eras_orbital.png` (4 slices)

- **Era:** all four, one screenshot each, shot as you go (see Setup 2).
- **Owned:** all 24 slots of that era, levelled with **Max** so the monument and the landmarks are at full size.
  `GrowthTier` 5 gives the most cars, trees and life. The plot then shows its "Advance Era" banner. Close the
  Build panel and hide the HUD before capturing.
- **Camera:** the same angle for all four: freecam behind the plot's entrance corner, about 45° to the side and
  30° down. Frame the era's tallest building (Castle Keep, Clock Tower, Skyscraper, Launch Tower) near the centre
  of the image. Each screenshot becomes a tall column, so only the middle third of it survives the crop.
- **Not in frame:** the HUD, the Advance Era dialog, other players' plots in the middle of the shot.
- **Labels:** **VILLAGE · BOOMTOWN · METROPOLIS · ORBITAL** across the top, one per column; this shot has no
  caption.

## 3. Scale — `scale_metropolis.png`

- **Era:** Metropolis.
- **Owned:** all 24 slots, all levelled to **Max**, `GrowthTier` 5. That gives the full street grid, the
  elevated ring highway with its ramp and deck cars, the subway kiosks, traffic, lamps and park trees.
- **Camera:** freecam outside the ring at the entrance corner, 25–30° down, close enough that the ring highway
  runs out of the frame at the bottom corners. The skyline (Skyscraper, Broadcast Tower, Bank Tower, Stadium)
  should fill the upper middle. A low, close angle sells size better than a whole-plot overview.
- **Not in frame:** the HUD, the Advance Era banner, your avatar in the foreground.
- **Caption:** **BUILD A METROPOLIS**.

## 4. Scale 2 — `scale_orbital.png`

- **Era:** Orbital Colony.
- **Owned:** all 24 slots at **Max**, with the monorail running ("Build the Monorail" owned) and the Launch
  Tower bought.
- **Camera:** as in shot 3, from the entrance corner, 25–30° down, with the Launch Tower and the tube corridors
  in the upper middle. Keep the sky to a thin strip: the in-game sky is a normal blue day sky.
- **Not in frame:** the HUD, the Advance/Rebirth banner.
- **Caption:** **BUILD A SPACE COLONY**.

## 5. Social — `social.png` (two real avatars)

- **Setup:** **Test → Start** with **2 Players** (Local Server). Player 1 uses `GrantCash` and buys and levels a
  handful of Village or Boomtown buildings, with one at **level 25–50** so it is visibly mid-growth. Player 2
  walks from their own plot onto Player 1's plot.
- **What the game really has:** every player grows their own city on their own plot in the same server, and
  friends can walk each other's plots. Building together happens in Expeditions, which is skipped until the
  combat rework. So the caption says **play** with friends, not **build** together.
- **Camera:** in Player 1's client window, normal camera (not freecam, so it looks like play). Stand both avatars
  on or beside the mid-growth building's pad, facing roughly toward the camera. Put the camera at chest-to-head
  height, 12–18 studs away, with the building filling the upper half behind them. Keep both avatars above the
  bottom 15 %.
- **Not in frame:** the HUD (hide it in the capturing window), chat bubbles, the debug strip.
- **If both test players show the same default avatar:** take this shot on the published game with Ben's second
  account instead (the C2 two-account setup), where each account wears its own avatar.
- **Caption:** **PLAY WITH FRIENDS**.
