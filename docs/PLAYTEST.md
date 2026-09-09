# Era City Tycoon — Playtest Checklist

Source of truth for what "done" looks like each milestone: `docs/SPEC.md`. Run every box below
in Roblox Studio. If anything fails, note the exact Output line/error and which step you were on,
then stop — don't keep testing past a red error.

---

## M0 — Scaffold

**Goal:** the empty project boots clean. Nothing renders yet — no UI, no plots. That is correct
for this milestone; do not report "nothing shows up" as a bug.

### 1. Get the place open in Studio

Pick ONE of these two:

- [x] 1a. Open `build/test.rbxl` directly in Roblox Studio (File → Open, or double-click).
- [x] 1b. OR: run `rojo serve` from the repo root in a terminal, then in Studio use the Rojo
      plugin → Connect (default port 34872). Use this path if you want live-sync while poking
      around; use 1a if you just want a quick boot check.

If `Packages/` is missing or the build is stale, run `wally install` then rebuild with
`rojo build -o build/test.rbxl` before opening (see `docs/MANUAL_STEPS.md` for exact commands).

### 2. Desktop boot check

- [x] 2. Press **Play** (F5) in Studio, desktop/default view.
- [x] 3. Open the **Output** window (View → Output).
- [x] 4. Confirm you see `[Server] booted — tickRate=1` somewhere in the log.
- [x] 5. Confirm you see `[Client] booted` somewhere in the log.
      (These two lines may appear in either order, interleaved with normal Studio noise —
      that's fine. Both must appear.)
- [x] 6. Confirm there are **zero red error lines** in Output. Yellow warnings from Studio itself
      (not from our scripts) are OK; anything printed by our code should not be a warning either.
- [x] 7. Confirm nothing renders on screen — no HUD, no buttons, no plots, no visible parts beyond
      the default baseplate/sky. This is expected for M0.
- [x] 8. Stop Play (Shift+F5).

### 3. ServerStorage asset folders exist

- [x] 9. In the **Explorer** window, expand `ServerStorage` → `Assets`.
- [x] 10. Confirm four empty folders exist, named exactly: `Village`, `Boomtown`, `Metropolis`,
      `OrbitalColony`.
- [x] 11. These folders should still be there even after re-running `rojo build` or reconnecting
      `rojo serve` — Rojo is configured to never delete unknown instances inside `ServerStorage`.
      (Nothing to hand-place yet at M0 — this just confirms the folders exist ahead of later
      milestones.)

### 4. Mobile emulation pass (required every milestone)

- [x] 12. In Studio, open the **Device Emulator** (Test tab → Device, or the phone/tablet icon
      next to Play).
- [x] 13. Pick a phone preset sized **375×667** (iPhone SE) — or set a custom resolution to
      375×667 if that exact preset isn't listed.
- [x] 14. Press **Play** with the emulator active.
- [x] 15. Repeat checks 4–7 above: both boot lines present, zero red errors, nothing renders.
- [x] 16. Stop Play.

### What a bug looks like here

- Any red error in Output (missing ModuleScript, `require` failure, `--!strict` type error
  surfaced at runtime, etc).
- Either boot line missing or misspelled.
- `Assets` folders missing, renamed, or containing something unexpected.
- Anything visibly rendering (a sign this milestone accidentally shipped UI/plot code).

### Sign-off

- [x] 17. All boxes above checked, on both desktop and 375×667 emulation.
- [x] 18. Tell Claude Code "M0 playtest passed" (or report the exact failure) so `docs/PLAN.md`
      can be marked `[x]`.

---

## M1 — Playable loop

**Goal:** the full Era 1 loop works end-to-end with placeholders only — no Kenney assets, no
persistence. **Leaving the game discards ALL progress by design** (persistence lands in M2).
Expect a fresh start every time you press Play. Don't report "my buildings are gone" as a bug
unless it happens *before* you leave/rejoin.

Run the M0 checklist above first (its steps 1-16) as an implicit part of this gate — confirm a
clean boot before testing the loop below. If M0 fails, stop there; don't continue into M1.

### 1. Rebuild and open

- [x] 1. From the repo root: `rojo build -o build/test.rbxl`. Confirm it succeeds with no errors.
      (Or: run `rojo serve` and connect via the Rojo plugin in Studio — see
      `docs/MANUAL_STEPS.md`.)
- [x] 2. Open the built place (or the connected Studio session) and press **Play Solo** (F5).
- [x] 3. Confirm `[Server] booted` and `[Client] booted` still print in Output with zero red
      errors (same check as M0 steps 4-6).

### 2. Claim a plot and buy the free first slot

- [x] 4. Confirm your character spawns on the central hub platform (a round area near the middle
      of the map) — not directly on a plot.
- [x] 5. Confirm the HUD top bar is visible: cash, income/s, and an era badge reading "Village"
      (Era 1).
- [x] 6. Walk from the hub to any open plot on the ring around it. Confirm you see exactly one
      buy pad on your plot, labelled "Campfire", cost 0.
- [x] 7. Walk onto the campfire pad. Confirm it buys automatically on touch (no confirm dialog)
      and a placeholder box (8x8x8 part with a floating name label reading "Campfire") appears
      in its place. This placeholder look is expected — no Kenney models are imported yet.
- [x] 8. Confirm the campfire pad disappears and the HUD's cash/income figures update.

### 3. Income ticks

- [x] 9. Stand still and watch the HUD cash number for 5-10 seconds. Confirm it climbs roughly
      once per second.
- [x] 10. Remember: in Studio, income is multiplied **x100** for testing speed (a Studio-only
      debug lever; production has no such multiplier). Numbers will feel very fast next to the
      ~30-45 min design target for a full era — that's correct for this milestone.

### 4. Buy more slots — both methods

- [x] 11. Tap the **Build** button to open the Build panel. Confirm slots are listed in a fixed
      order, and only the slot(s) whose `requires` you already own show a cost/Buy button —
      everything further down reads "Requires <slot name>" with no Buy button, and has no pad on
      the plot yet.
- [x] 12. Buy 2-3 more slots using ONLY the Build panel's Buy button. Confirm each becomes owned
      (a new placeholder appears on the plot), cash drops by the listed cost, and the next slot's
      pad appears on the plot in the same order the panel lists it.
- [x] 13. Buy 1-2 more slots by walking onto their pads on the plot instead of using the panel.
      Confirm the panel's row flips to "owned" without needing to reopen the panel.
- [x] 14. Confirm pads only ever appear for the slot(s) currently unlocked by the `requires`
      chain, one step at a time, in the exact order the Build panel lists them — never a pad for
      a still-locked slot.

### 5. Level up — both methods

- [x] 15. Walk close to a building you own. Confirm a **ProximityPrompt** appears (a key/button
      prompt hovering over it). Trigger it. Confirm the building's level increases by 1 and cash
      drops by the shown cost.
- [x] 16. In the Build panel, find that owned building's row. Confirm it shows a "Level Up x1"
      button with a cost. Tap it several times. Confirm level increases and cash drops each time.
- [x] 17. Keep leveling one building until it crosses a milestone level (10, 25, 50, or 100 —
      10 is reachable fastest with the x100 debug income). Confirm income visibly jumps by more
      than a normal level-up would right at that level (milestone levels double income).

### 6. Insufficient funds

- [x] 18. Find a row (Buy or Level Up) you can't currently afford. Tap it anyway. Confirm the
      row/cost flashes red briefly and **nothing** is charged or purchased — cash and ownership
      unchanged.

### 7. Income-preview caveat (expected, not a bug)

- [x] 19. In the Build panel, note a row's "income delta" preview (the "+X/s" next to Buy/Level
      Up). Buy or level that row, then compare against how much the HUD's income/s actually
      jumps. In Studio the real jump will be **about 100x bigger** than the preview said. This is
      expected — the preview doesn't apply the Studio-only x100 debug multiplier; in production
      (no debug multiplier) the two numbers match exactly. Do not report this mismatch as a bug.

### 8. Locked-row labeling

- [x] 20. Scroll the Build panel to a slot several steps ahead of what you own. Confirm its row
      reads "Requires <name of the slot it needs>" (not just "Locked") and has no Buy button.

### 9. Mobile emulation pass (required every milestone)

- [x] 21. Open the **Device Emulator** (Test tab → Device icon). Set the resolution to
      **375x667** (portrait, iPhone SE preset or custom).
- [x] 22. Press Play. Open the Build panel. Confirm every button (Build toggle, Buy, Level Up)
      looks comfortably tappable (at least roughly 44x44 px, not a tiny sliver) and the panel
      does not overlap or hide the top HUD bar.
- [x] 23. Switch the emulator to **667x375** (landscape). Confirm the Build panel is still fully
      on-screen and every button is reachable/tappable. (A polished landscape layout isn't
      required until M3 — for now the bar is just "nothing cut off, nothing untappable.")
- [x] 24. Stop Play.

### 10. Two-player test (multiplayer isolation) — Local Server mode

- [x] 25. In Studio, use **Test → Start** with **2 Players** (Local Server — not Play Solo).
- [x] 26. Confirm each of the two player windows spawns on the hub, then claims a DIFFERENT plot
      on the ring (not the same one).
- [x] 27. As Player 1, walk onto Player 2's plot and try touching one of Player 2's buy pads (or
      open the Build panel while standing there and hit Buy). Confirm nothing happens — no
      purchase goes through and Player 2's cash/ownership is unaffected.
- [x] 28. Close Player 2's client window (have them leave). Confirm Player 2's plot resets: its
      pads and placeholder buildings disappear and the plot becomes free again.
- [x] 29. If Player 2 rejoins, confirm they start over completely (0 cash, no owned slots, a
      freshly claimed plot) — expected, persistence isn't built until M2.
- [x] 30. Stop the test session.

### What a bug looks like here

- Any red error in Output at any point above.
- A pad appearing for a slot whose `requires` slot isn't owned yet, or pads appearing out of
  order.
- A Buy or Level Up succeeding without enough cash (no red flash, cash goes negative, or the
  purchase/level-up goes through anyway).
- A purchase or level-up on **another player's** plot succeeding.
- The Build panel and HUD disagreeing about what's owned, its cost, or its level after a
  purchase.
- Buttons in Device Emulation you can't reliably tap, or a panel that covers/hides the top bar.
- A player's plot NOT resetting after they leave (leftover pads/buildings, or the plot can't be
  reclaimed by a new player).

### Sign-off

- [x] 31. All boxes above checked (M0 checklist re-run + all M1 sections), on desktop, 375x667
      emulation, 667x375 landscape emulation, and the 2-player Local Server test.
- [x] 32. Tell Claude Code "M0 and M1 playtest passed" (or report the exact failure and step
      number). Ticking this box marks **both** `M0` and `M1` `[x]` in `docs/PLAN.md`.

---

## M2 — Persistence & eras

**Goal:** progress survives leaving the game, offline earnings pay out on rejoin, and all four
eras plus Advance Era / Rebirth / Legacy work end to end. Studio income is still multiplied
**×100** (debug lever) so a full era takes minutes, not hours — see `docs/BALANCE.md` for real
(×1) timings.

Run the M0 checklist (steps 1-16) and the M1 checklist (steps 1-30) first. If either fails,
stop there — don't continue into M2.

### 1. Enable Studio API access (do this first)

Real persistence testing requires Studio to be allowed to talk to DataStores. Without this,
ProfileStore silently falls back to a mock: progress still works for buy/level/era tests below
but is **wiped every time you stop Play** — the offline-earnings and true-rejoin checks need
the real thing.

- [x] 1. In Studio: **Game Settings** (Home tab) → **Security** tab.
- [x] 2. Turn **"Enable Studio Access to API Services"** ON. Click Save.
- [x] 3. Press **Play** (F5). Open **Output**.
- [x] 4. Look for one of these two lines (printed once, from ProfileStore):
      - `[ProfileStore]: Roblox API services available - data will be saved` → real
        persistence is ON, continue with confidence.
      - `[ProfileStore]: Roblox API services unavailable - data will not be saved` → still
        mocked (setting didn't take, or you're in a context Studio blocks — e.g. Team Create
        without publish rights). Fix this before trusting sections 3 and 4 below.
- [ ] 5. Stop Play.

### 2. Persistence — buy, stop, rejoin, restored instantly

- [x] 6. Press Play. Claim a plot, buy 3-4 slots (pads or panel), level one of them up twice.
      Note your cash, which slots you own, and that building's level.
- [x] 7. Stop Play (Shift+F5) immediately — no need to wait.
- [x] 8. Press Play again (same Studio session or a fresh one, doesn't matter).
- [x] 9. Confirm: the moment your plot loads, cash matches what you noted, the same slots are
      already owned with their placeholders in place, and the leveled building shows the same
      level — **no reveal tweens or sounds play** (bulk restore, not 24 individual reveals).
- [x] 10. Confirm the Build panel opens already showing everything as owned/leveled, matching
      the plot.

### 3. Offline earnings toast

Requires real API access (section 1, step 4 showed the "available" line).

- [x] 11. Press Play, own at least 3-4 income-producing slots so income/s is clearly nonzero.
      Note the income/s shown in the HUD.
- [x] 12. Stop Play. Wait at least **65 seconds** real time (a coffee-break pause, not a rush).
- [x] 13. Press Play again. Confirm a small toast appears near the top of the screen reading
      something like "You earned $X while away — <time> offline" and auto-dismisses after a
      few seconds without blocking any taps underneath it.
- [x] 14. Confirm the granted amount is plausible. **The offline grant deliberately ignores the
      Studio debug income multiplier, while the HUD income/s does not** — so divide the HUD
      figure out first: roughly (HUD income/s at the moment you stopped ÷
      `debug.studioIncomeMultiplier`) × (seconds away) × 0.5 (50% offline efficiency; this
      becomes 1.0 instead of 0.5 once you own the Offline Pro pass, from M4 onward). It will not
      be exact since income/s may have changed right before you stopped, but it should be the
      right order of magnitude, not the full 100% rate and not zero.
- [x] 15. Immediately press Play a second time (rejoin again right away, well under 60 s this
      time). Confirm **no toast appears** — too little time passed.
- [x] 16. If this is a brand-new profile's very first-ever join (never played before), confirm
      no toast appears on that first join even if `lastSeen` logic is new — nothing was earned
      before you existed.

### 4. Era advance — Village to Boomtown

Use a fresh or near-complete profile. With the ×100 debug multiplier, owning all 24 Era 1 slots
should take well under the ~40 min real-time design target.

- [x] 17. Buy and own **all 24 slots** of Era 1 (Village), including the **monument** (last
      slot in the Build panel list).
- [x] 18. Confirm a gold **"Advance Era → Boomtown"** banner appears pinned at the top of the
      Build panel's slot list, above all the slot rows.
- [x] 19. Tap the banner. Confirm a confirm dialog pops up titled "Advance to Boomtown?"
      showing:
      - a highlighted "Earn +N Legacy" line with a specific number (not zero, not blank)
      - "Resets: cash, buildings, levels, and your plot"
      - "Keeps: Legacy, era progress, rebirth count, and stats"
      - Cancel and "Advance Era" buttons
- [x] 20. Tap **Cancel** (or tap outside the card). Confirm nothing changes — still Era 1, still
      24/24 owned, banner still there.
- [x] 21. Reopen and tap **Confirm** ("Advance Era"). Confirm:
      - the plot rebuilds with a visibly different base color (Boomtown = dusty brown, vs
        Village's green)
      - cash resets to 0
      - the Build panel now lists a fresh set of 24 rows for Boomtown, all locked/unowned
        except the free first slot's pad
      - the top bar's **Legacy** number increased by exactly the amount the dialog showed
      - the era badge reads "ERA 2" / "Boomtown"

### 5. Repeat to Era 4 and Rebirth

- [x] 22. Repeat step 17-21's pattern to advance Boomtown → Metropolis (base recolors to
      asphalt gray) and Metropolis → OrbitalColony (base recolors to dark regolith/near-black).
      Confirm Legacy keeps climbing each time and never resets.
- [x] 23. Own all 24 OrbitalColony slots including its monument. Confirm the banner now reads
      **"Rebirth → Era 1"** instead of "Advance Era".
- [x] 24. Tap it. Confirm the confirm dialog titled "Rebirth?" shows:
      - a highlighted "Earn +N Legacy" line
      - "Your <current Legacy> Legacy is KEPT"
      - a "Rebirths: 0 → 1 — future eras grant more Legacy" line
      - "Start over in Era 1 with your permanent bonuses"
      - Resets/Keeps lines (cash/buildings/levels/plot reset; Legacy/rebirth count/stats kept)
- [x] 25. Tap **Rebirth**. Confirm you land back in Era 1 (Village, green base, "ERA 1" badge),
      cash 0, all 24 Village slots locked again except the free first one, and the top bar's
      Legacy number is the PRE-rebirth Legacy **plus** the amount the dialog showed (Legacy is
      never lost on rebirth).
- [x] 26. Open the Build panel and confirm the prestige info reflects rebirth count 1 (visible
      the next time you reach the Rebirth dialog again — its "Rebirths: 1 → 2" line — or via
      any rebirth-count display the build has).

### 6. Exploit spot-check (advance-then-disconnect)

This targets the fix for a reviewed Critical: advancing/rebirthing then disconnecting before
the next income tick used to let a rejoin pay offline earnings at the OLD (just-completed)
era's income rate into the NEW, empty era.

- [x] 27. With real API access on (section 1), get to a point where you're one tap away from
      Advance Era or Rebirth and your income/s is clearly high (ideally the highest income/s
      you've had all session — e.g. right after finishing OrbitalColony).
- [x] 28. Tap Confirm on the Advance Era / Rebirth dialog, then **immediately** Stop Play
      (within a second or two — before you'd see even one income tick land in the new era).
- [x] 29. Wait at least 65 seconds real time, then Press Play again.
- [x] 30. Confirm: **no welcome-back toast appears, or if one appears the amount is ~0** — not
      the old era's high income rate applied to the elapsed time. Cash should read 0 (or
      whatever the tiny post-advance amount is), never a large windfall.
- [x] 31. If a large offline grant appears here, this is a regression of the fixed exploit —
      report it with the exact cash amount shown and how long you waited.

### 7. Two-player: neighbors bonus

- [ ] 32. **Test → Start** with **2 Players** (Local Server mode).
- [ ] 33. As Player 1 alone (before Player 2 finishes loading in), note Player 1's income/s in
      the HUD.
- [ ] 34. Once Player 2 has also claimed a plot and is fully loaded in, confirm Player 1's
      income/s display updates to roughly **+3% higher** than the step 33 value (neighbors
      bonus, live-only — it is not saved and does not apply to offline earnings).
- [ ] 35. Have Player 2 leave (close their window). Confirm Player 1's income/s drops back down
      by roughly that same 3%.

### 8. Quick regression of M1 checks

- [ ] 36. Buy a slot via a pad and via the Build panel (M1 section 4) — still works.
- [ ] 37. Level up a building via ProximityPrompt and via the panel (M1 section 5) — still
      works, and hitting a milestone level (10/25/50/100) still visibly jumps income.
- [ ] 38. Try to Buy/Level Up something you can't afford (M1 section 6) — still red-flashes,
      nothing charged.
- [ ] 39. Landscape 667×375 emulation (M1 section 9, step 23) — Build panel including the new
      gold prestige banner is still fully on-screen and tappable, nothing clipped.

### 9. Mobile emulation pass (required every milestone)

- [ ] 40. Open the **Device Emulator**, set resolution to **375×667** (portrait).
- [ ] 41. Press Play. Open the Build panel, complete an era (or use a near-complete save from
      section 4/5 above) and confirm the gold prestige banner and the confirm dialog (Cancel /
      Confirm buttons) are both comfortably tappable (~44×44 px) and fully on-screen — dialog
      isn't clipped top/bottom, buttons aren't crowded together.
- [ ] 42. Confirm the welcome-back toast (if you trigger one) doesn't cover the top bar and
      doesn't block taps on anything beneath it.
- [ ] 43. Stop Play.

### What a bug looks like here

- Any red error in Output at any point above.
- Cash, owned slots, or levels NOT matching after a stop/Play rejoin with real API access on.
- A welcome-back toast on a brand-new profile's first-ever join.
- A welcome-back toast (or a large one) after waiting less than the ~60 s minimum.
- An offline grant using the wrong era's income rate (section 6) — the regression this
  milestone specifically fixed.
- The Advance Era / Rebirth dialog's Legacy number being 0, blank, or obviously wrong.
- Legacy decreasing at any point, ever (advance and rebirth both only ever add to it).
- The plot base color NOT changing on era advance, or changing to the wrong era's color.
- The Build panel not rebuilding to the new era's 24 slots after advance/rebirth.
- Neighbors bonus not appearing (or not disappearing) within a few seconds of a second player
  joining/leaving.
- Anything from the M0/M1 regression checks (section 8) failing.

### Sign-off

- [ ] 44. All boxes above checked: Studio API access confirmed real (or explicitly noted as
      mock with a reason), persistence, offline toast (including the no-toast cases), a full
      Era 1→4 advance chain, one rebirth, the exploit spot-check, the two-player neighbors
      check, the M0/M1 regression pass, and 375×667 mobile emulation.
- [ ] 45. Tell Claude Code "M0, M1, and M2 playtest passed" (or report the exact failure and
      step number). Ticking this box marks `M0`, `M1`, **and** `M2` `[x]` in `docs/PLAN.md`.

---

## M3 — Presentation

**Goal:** the game looks and sounds like a real game on a phone — reveal/level-up feedback, an
era-advance ceremony, a welcome-back card, a real landscape layout, and settings that persist.
All sound IDs ship as `0` this milestone (no Kenney audio imported yet) — **silence is
correct**, not a bug. See `docs/BALANCE.md` for real (×1) era timings; Studio income is still
multiplied **×100** (debug lever) to make this checklist practical.

The combined M0–M2 checklist above is still pending sign-off — run it in the same session as
this one if you haven't yet (steps 1-16, 1-30, 1-45 above). This M3 section assumes a clean
boot and doesn't repeat those checks.

### 1. Reveal feedback — pad buy and panel buy

- [x] 1. Press Play. Claim a plot. Walk onto the free first slot's pad. Confirm the placeholder
      does **not** just pop into existence: it grows from a small sliver up to full size (its
      bottom stays fixed to the ground — it doesn't grow from the middle or float up).
- [x] 2. Open the Build panel, buy the next slot with the **Buy** button instead of a pad.
      Confirm the same grow-in reveal plays for that slot's placeholder too.
- [x] 3. With sound IDs at 0 there is no audible pop/thud — that's expected. Confirm Output has
      **no warnings** about missing sounds (a warning here would mean id-0 isn't being treated
      as silent).

### 2. Level-up feedback and milestones

Use `debug.studioIncomeMultiplier` (already ×100) plus rapid Level Up taps to reach level 10
quickly on one building.

- [x] 4. Level up an owned building once (ProximityPrompt or Build panel ×1). Confirm floating
      `+1` text rises briefly at the building, then fades.
- [x] 5. Keep leveling the same building until it crosses **level 10** (the first milestone).
      Confirm the floating text at that specific level-up looks different from a normal one
      (gold/larger "MILESTONE" styling) and income visibly jumps by more than a normal level
      would.

### 3. ×1 / ×10 / Max level buttons

- [x] 6. Open the Build panel on an owned, levelable building. Confirm you see three buttons:
      **×1**, **×10**, **Max**, each with its own cost label.
- [x] 7. Tap **×10**. Confirm the level jumps by up to 10 (fewer if you can't afford 10, or if
      it would exceed max level) and the cost charged matches the ×10 cost label shown before
      tapping.
- [x] 8. Tap **Max**. Confirm it buys as many levels as you can currently afford in one tap
      (not just 1), and the building never exceeds `maxLevel`.
- [x] 9. Find a row you can't afford (any of ×1/×10/Max/Buy). Confirm the button is visibly
      dimmed but **still tappable** — tap it and confirm it flashes red and charges nothing
      (same insufficient-funds behavior as M1/M2, now on all four button types).

### 4. Bottom bar and panels

- [x] 10. Confirm the bottom bar shows exactly three buttons: **Build**, **Legacy**,
      **Settings**. There is **no Shop button** yet — that's correct, Shop ships hidden until
      M4.
- [x] 11. Tap **Build**, then tap **Legacy** without closing Build first. Confirm only one panel
      is open at a time (opening Legacy closes Build, not both stacked).
- [x] 12. Open **Legacy**. Confirm it shows your Legacy count, current Legacy income multiplier,
      and rebirth count. If eligible, confirm the Advance Era / Rebirth entry is present here
      too (in addition to the Build panel banner).

### 5. Settings persist across rejoin

Requires real Studio API access (Game Settings → Security → "Enable Studio Access to API
Services" — same toggle as the M2 checklist; check Output for the ProfileStore
"available"/"unavailable" line as in M2 section 1).

- [ ] 13. Open **Settings**. Confirm **Music** and **SFX** toggles are shown, both default ON
      (or matching your last-saved state).
- [ ] 14. Turn **Music** off. Confirm the toggle visibly flips immediately (no lag waiting on
      the server).
- [ ] 15. Stop Play, then Press Play again (same profile). Open **Settings**. Confirm **Music**
      is still OFF — the setting survived the rejoin. (If Studio is on the ProfileStore mock,
      this will reset every Stop — same caveat as M2's persistence checks; note which mode
      you're in.)
- [ ] 16. Turn **Music** back on for the rest of this checklist.

### 6. Full era advance → ceremony → new era

Use a near-complete or fresh profile with the ×100 debug multiplier; owning all 24 Village slots
should take well under the real ~40 min target.

- [ ] 17. Own all 24 Era 1 (Village) slots including the monument. Confirm the gold "Advance
      Era" banner appears in the Build panel (as in M2).
- [ ] 18. Tap the banner. Confirm a **full-screen era-advance screen** opens (not the smaller M2
      dialog): next era name "Boomtown" / "ERA 2", a preview list of the next era's first few
      building names and its monument name, a two-column **Resets** vs **Persists** list, and a
      highlighted **+N Legacy** line with a specific number.
- [ ] 19. Tap **Cancel**. Confirm the screen closes and nothing changed (still Era 1).
- [ ] 20. Reopen and tap **Confirm**. Confirm a **full-screen ceremony overlay** appears next:
      "ERA 2 — Boomtown" and the same "+N Legacy" amount. Confirm it either auto-dismisses after
      a couple seconds or dismisses immediately when you tap it.
- [ ] 21. After the ceremony closes, confirm the Build panel is rebuilt for Boomtown: 24 fresh
      rows, all locked except the free first slot, era badge reads "ERA 2" / "Boomtown", plot
      base recolored.

### 7. Plot sign

- [ ] 22. Walk to the front edge of your plot (the side facing the hub). Confirm a sign/board is
      there showing your player name and the current era's display name (e.g. "YourName's
      Village" before advancing, "YourName's Boomtown" after).
- [ ] 23. Confirm the sign text updates immediately after the era-advance in section 6 (still
      your name, new era's display name, still no "Rebirth" line — rebirth count is 0).
- [ ] 24. If you can reach Rebirth this session (repeat section 6's advance pattern through
      Metropolis and OrbitalColony, then Rebirth as in M2 section 5), confirm the sign gains a
      second line reading **"Rebirth ×1"** after rebirthing once.

### 8. Welcome-back card

Requires real Studio API access (section 5 above).

- [ ] 25. With income/s clearly nonzero, Stop Play. Wait at least **65 seconds** real time.
      Press Play again. Confirm a **card** (not a bare toast) appears under the top bar: title
      "Welcome back!", body text with the dollar amount and a duration like "12m 5s" or "3h
      12m" (never a raw number of seconds), and an **X** button.
- [ ] 26. Tap the **X**. Confirm the card dismisses immediately.
- [ ] 27. Trigger another welcome-back card (Stop, wait 65+ s, Play). This time don't tap
      anything — confirm it auto-dismisses on its own after a few seconds.
- [ ] 28. Confirm there is no "Double it" button visible on the card — that's an M4 feature,
      hidden until a dev product ID is set.

### 9. Silence check

- [ ] 29. Across everything above (buy, level up, milestone, era advance, rebirth, welcome
      back, button taps), confirm you never hear any audio (expected — all sound IDs are 0) AND
      Output never prints a warning/error about a missing or invalid sound. A warning here is a
      bug (id-0 must be treated as "silent, skip" — never an error).

### 10. Mobile emulation pass — portrait AND landscape (required every milestone)

- [ ] 30. Open the **Device Emulator**. Set **375×667** (portrait). Press Play. Open Build,
      Legacy, and Settings panels one at a time. Confirm every button (including the new ×1/×10/
      Max buttons) is comfortably tappable (~44×44 px) and nothing overlaps the top bar or
      bottom bar.
- [ ] 31. Rotate the emulator to **667×375** (landscape). Confirm the panels now dock to a
      column on the **right** side of the screen (not the portrait bottom sheet), the top bar
      moves to the **top-left**, and the bottom bar stays centered at the bottom. Confirm all
      tap targets are still ≥ 44 px and nothing is cut off.
      - Known nit (not a bug to report, already tracked): on very narrow landscape sizes below
        about 640×360, the right-docked panel may overlap the top-left top bar by a few pixels.
        If you see this on 667×375 specifically (wider than that), it IS worth reporting.
- [ ] 32. Switch to a **desktop 1920×1080** view (Device Emulator off, or a custom 1920×1080
      preset). Confirm the layout still looks reasonable — panels not stretched edge-to-edge,
      text not tiny, nothing overlapping.
- [ ] 33. Stop Play.

### 11. Two-player test — Local Server mode (owner-only FX)

- [ ] 34. **Test → Start** with **2 Players** (Local Server mode).
- [ ] 35. As Player 1, buy a slot (pad or panel). Confirm Player 1 sees the reveal tween
      (section 1's grow-in effect).
- [ ] 36. As Player 2, look at Player 1's plot at the moment Player 1 buys. Confirm Player 2
      sees the building **appear instantly with no tween** — FX events are owner-only, so a
      bystander only sees the final state replicate, not the animation.
- [ ] 37. As Player 2, try to touch one of Player 1's buy pads or trigger Player 1's building's
      ProximityPrompt. Confirm nothing happens (same isolation as M1/M2).
- [ ] 38. Stop the test session.

### What a bug looks like here

- Any red error in Output at any point above.
- A placeholder popping into existence with no grow-in tween, or the reveal tween starting from
  the wrong anchor (floating, growing from the middle, etc).
- Level-up floating text missing, or the level-10 milestone looking identical to a normal
  level-up.
- ×10 or Max charging a different amount than their cost labels showed, or granting levels past
  `maxLevel`.
- A dimmed unaffordable button that does nothing when tapped (should still flash red / fire
  `ActionResult`), or one that silently succeeds without enough cash.
- A Shop button visible in the bottom bar this milestone.
- More than one panel open at once.
- A Settings toggle that doesn't survive a Stop/Play rejoin with real Studio API access on.
- The era-advance screen missing the resets/persists list or the Legacy amount.
- The ceremony overlay never appearing, never dismissing (stuck), or showing the wrong era name.
- The plot sign missing, showing the wrong name/era, or not updating after an advance/rebirth.
- No "Rebirth ×1" line on the sign after an actual rebirth.
- The welcome-back card missing its X button, or auto-dismiss never firing.
- Any audible sound (should be silent with all IDs 0) or any Output warning about sounds.
- Landscape 667×375 NOT docking panels to the right / top bar NOT moving to the top-left.
- Player 2 seeing Player 1's reveal tween (FX should be owner-only) or being able to interact
  with Player 1's plot.

### Sign-off

- [ ] 39. All boxes above checked: reveal feedback, level-up + milestone feedback, ×1/×10/Max,
      bottom bar/panels, settings persistence, a full era advance with ceremony, the plot sign
      (including rebirth if reached), the welcome-back card, the silence check, 375×667 portrait,
      667×375 landscape, 1920×1080 desktop, and the 2-player owner-only-FX test.
- [ ] 40. Tell Claude Code "M3 playtest passed" (or report the exact failure and step number).
      Ticking this box marks `M3` `[x]` in `docs/PLAN.md`. If the combined M0–M2 checklist above
      hasn't been signed off yet, mention that separately — it's still tracked as pending.

## M4 — Monetization & analytics

**Goal:** passes, dev products, Premium, and analytics — all optional, restrained, and invisible
until you create them. Two phases: **Phase A** proves the all-ids-0 default is silent; **Phase
B** proves real purchases work once you've created things per `docs/MANUAL_STEPS.md` M4.

The combined M0–M3 checklist above is still pending sign-off — run it in the same session if you
haven't yet. This section assumes a clean boot and doesn't repeat those checks.

### Phase A — all ids still `0` (do this before creating anything on Creator Hub)

- [ ] 1. Press Play. Confirm the bottom bar shows exactly **Build, Legacy, Settings** — **no
      Shop button**.
- [ ] 2. Get a welcome-back card (Stop, wait 65+ s with nonzero income, Play again — same as M3
      section 8). Confirm it shows the offline amount and an **X**, and there is **no "Double
      it" button**.
- [ ] 3. Confirm Output has **zero warnings or errors** related to monetization, passes,
      products, or analytics across the whole session.
- [ ] 4. Re-run the M3 checklist's sections 1–9 (reveal, level-up, ×1/×10/Max, bottom bar,
      settings, era advance, plot sign, welcome-back, silence) and confirm every one still passes
      exactly as before — M4 must not have changed any M3 behavior when nothing is configured.
- [ ] 5. Stop Play.

### Phase B — with real ids pasted in

Do `docs/MANUAL_STEPS.md` M4 sections 2–5 first (create at least one pass and one product, paste
the ids into `src/shared/Config/Monetization.json`, rebuild). You do not need all seven created
to start — test what you have.

- [ ] 6. Press Play. Confirm the bottom bar now shows a **Shop** button.
- [ ] 7. Open **Shop**. Confirm it lists **exactly** the items you created (and only those —
      anything still at id `0` is absent), in two sections **Passes** then **Packs**, in the same
      order as `Monetization.json`. `DoubleOffline` should **never** appear in the Shop list even
      if its id is set (it's welcome-back-only).
- [ ] 8. For each pack row (`Cash30m` / `Cash2h` / `Cash8h` you created), note the previewed
      "up to N minutes" grant amount shown next to the label.
- [ ] 9. Confirm the three pack previews are **visibly different amounts**, roughly in a
      **1 : 2.5 : 5** ratio (not identical, and not the nominal 1 : 4 : 16) — this is the
      per-pack cap working. If two pack rows show the same number, that's a bug.
- [ ] 10. Buy one pack (see MANUAL_STEPS.md M4 section 7 about real charges before you tap
      through). Confirm the cash that actually lands in your balance **matches the previewed
      amount** from step 8 (small drift is fine if your income changed between preview and
      purchase; a large systematic overstatement — historically up to +27% too high in a full
      server — is the bug this milestone fixed. Testing solo, preview and actual should match
      almost exactly).
- [ ] 11. Immediately try to buy the same pack again (or, if Studio lets a receipt replay,
      trigger it twice). Confirm cash is **not** double-granted — one purchase, one grant.
- [ ] 12. Buy a pass (e.g. `DoubleCash` or `VIP`). Confirm it applies **within the same
      session, without rejoining**:
      - `DoubleCash`: income/s roughly doubles immediately.
      - `VIP`: a gold plot sign, a `VIP` name tag floating above your character's head, and (if
        VIP variants were imported) VIP building skins — all without leaving and rejoining.
- [ ] 13. Buy `OfflinePro`. Stop Play, wait 65+ s, Press Play again. Confirm the Studio
      diagnostic print in Output now reads something like
      `away Ns, saved rate R/s, cap Cs, efficiency E, granted G` with **cap = 86400** (24h) and
      **efficiency = 1** — not the default 8h/0.5. Confirm the welcome-back card's amount is
      correspondingly larger than a non-Pro grant would be.
- [ ] 14. If you have Roblox Premium on your test account, confirm a **Premium** indicator shows
      in the UI and income/s reflects the extra 1.1× multiplying with anything else you own
      (e.g. `DoubleCash` × `VIP` × `Premium` ≈ 2.42× if you have all three).
- [ ] 15. Confirm a compact **VIP / Premium / neighbors-bonus** indicator is visible somewhere in
      the top bar or Legacy panel and doesn't crowd the top bar at 375×667 (checked again in the
      mobile pass below).
- [ ] 16. Buy `DoubleOffline` if you have it: get a welcome-back card, tap "Double it" (only
      visible now that the id is set), confirm the resulting cash delta roughly doubles what the
      card originally showed, and confirm the card's "Double it" button does not reappear for
      that same grant.

### Join-race check (the milestone's Critical bug — do this one carefully)

- [ ] 17. With a real pass id set (e.g. `VIP` or `OfflinePro`) and the pass owned: stop Play, wait
      65+ s with nonzero income, then Press Play again **several times in a row** (5+ rejoins) to
      exercise the join sequence under repeated load. Confirm **every single join** still shows a
      correct welcome-back card with a nonzero, plausible amount (per M2 step 14's formula) —
      never a missing card, a silently-zeroed grant, or a warning in Output about the offline
      grant. (This used to be able to silently zero the grant on the join right after a real pass
      id was configured; it's now gated so the income tick can't race the join.)

### M3 carry-over fixes — re-verify these are actually fixed now

- [ ] 18. Device Emulator, landscape **640×360**. Open a panel (Build/Legacy/Settings/Shop).
      Confirm the right-docked panel does **not** overlap the top-left top bar anymore (this was
      a known ~9 px overlap at M3, fixed this milestone).
- [ ] 19. Rejoin so the very first `StateChanged` snapshot hasn't arrived yet, and within that
      first second or two, tap the **Music** or **SFX** toggle in Settings. Confirm it applies
      **audibly at once** (if you have sound IDs set) rather than waiting for the first
      snapshot/delta to "heal" it.

### Mobile emulation pass (required every milestone)

- [ ] 20. Device Emulator, **375×667** portrait. Open the Shop panel (with at least one real id
      set). Confirm every row (pass or pack) is comfortably tappable (~44×44 px), text isn't
      truncated oddly, and nothing overlaps the top or bottom bar. Confirm the VIP/Premium/
      neighbors indicator doesn't crowd the top bar at this width.
- [ ] 21. Rotate to landscape (either 667×375 or the 640×360 case from step 18). Confirm the Shop
      panel docks the same way the other panels do and remains usable.
- [ ] 22. Stop Play.

### Two-player test — Local Server mode

- [ ] 23. **Test → Start** with **2 Players**.
- [ ] 24. As Player 1 (with a real pass id owned), confirm Player 1's VIP sign/skins/name tag (if
      applicable) and income multiplier are visible/correct to Player 1.
- [ ] 25. As Player 2, look at Player 1's plot. Confirm Player 2 sees Player 1's gold sign and
      VIP building skins (world state replicates to everyone) but Player 2's own Shop/pass state
      is unaffected by Player 1's purchases — passes and products are per-player.
- [ ] 26. As Player 2, confirm Player 2's own Shop panel only reflects Player 2's own ownership
      (no owned/greyed state leaking from Player 1).
- [ ] 27. Stop the test session.

### What a bug looks like here

- A Shop button, a "Double it" button, or any prompt appearing while every id is still `0`.
- Any Output warning/error mentioning monetization, passes, products, or analytics in Phase A.
- Two pack rows showing the identical predicted grant (the per-pack-cap bug this milestone
  fixed) or a purchase crediting a noticeably different amount than its own preview showed.
- Buying the same product twice granting cash twice, or a replayed receipt granting again.
- A pass not applying until a rejoin (should be immediate, same session).
- Offline Pro not widening the cap/efficiency in the diagnostic print.
- A missing or zeroed welcome-back card on any of the repeated rejoins in the join-race check —
  this was the milestone's Critical bug; a single failure here is worth reporting precisely
  (which rejoin number, and the exact Output around it).
- The landscape panel/top-bar overlap still present at 640×360.
- A Settings toggle tapped before the first snapshot not applying audibly right away.
- Player 2 seeing Player 1's Shop/pass ownership state, or vice versa.

### Sign-off

- [ ] 28. All boxes above checked: Phase A silence, Phase B Shop contents/pricing/purchase
      correctness/idempotency/pass application/Offline Pro/Premium/Double-it, the join-race
      check across 5+ rejoins, both M3 carry-over fixes, 375×667 portrait, a landscape pass, and
      the 2-player test.
- [ ] 29. Tell Claude Code "M4 playtest passed" (or report the exact failure and step number).
      Ticking this box marks `M4` `[x]` in `docs/PLAN.md`. If the combined M0–M3 checklist above
      hasn't been signed off yet, mention that separately — it's still tracked as pending.
