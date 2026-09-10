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

- [x] 25. With income/s clearly nonzero, Stop Play. Wait at least **65 seconds** real time.
      Press Play again. Confirm a **card** (not a bare toast) appears under the top bar: title
      "Welcome back!", body text with the dollar amount and a duration like "12m 5s" or "3h
      12m" (never a raw number of seconds), and an **X** button.
- [x] 26. Tap the **X**. Confirm the card dismisses immediately.
- [x] 27. Trigger another welcome-back card (Stop, wait 65+ s, Play). This time don't tap
      anything — confirm it auto-dismisses on its own after a few seconds.
- [x] 28. Confirm there is no "Double it" button visible on the card — that's an M4 feature,
      hidden until a dev product ID is set.

### 9. Silence check

- [x] 29. Across everything above (buy, level up, milestone, era advance, rebirth, welcome
      back, button taps), confirm you never hear any audio (expected — all sound IDs are 0) AND
      Output never prints a warning/error about a missing or invalid sound. A warning here is a
      bug (id-0 must be treated as "silent, skip" — never an error).

### 10. Mobile emulation pass — portrait AND landscape (required every milestone)

- [x] 30. Open the **Device Emulator**. Set **375×667** (portrait). Press Play. Open Build,
      Legacy, and Settings panels one at a time. Confirm every button (including the new ×1/×10/
      Max buttons) is comfortably tappable (~44×44 px) and nothing overlaps the top bar or
      bottom bar.
- [x] 31. Rotate the emulator to **667×375** (landscape). Confirm the panels now dock to a
      column on the **right** side of the screen (not the portrait bottom sheet), the top bar
      moves to the **top-left**, and the bottom bar stays centered at the bottom. Confirm all
      tap targets are still ≥ 44 px and nothing is cut off.
      - Known nit (not a bug to report, already tracked): on very narrow landscape sizes below
        about 640×360, the right-docked panel may overlap the top-left top bar by a few pixels.
        If you see this on 667×375 specifically (wider than that), it IS worth reporting.
- [x] 32. Switch to a **desktop 1920×1080** view (Device Emulator off, or a custom 1920×1080
      preset). Confirm the layout still looks reasonable — panels not stretched edge-to-edge,
      text not tiny, nothing overlapping.
- [x] 33. Stop Play.

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

- [x] 1. Press Play. Confirm the bottom bar shows exactly **Build, Legacy, Settings** — **no
      Shop button**.
- [x] 2. Get a welcome-back card (Stop, wait 65+ s with nonzero income, Play again — same as M3
      section 8). Confirm it shows the offline amount and an **X**, and there is **no "Double
      it" button**.
- [x] 3. Confirm Output has **zero warnings or errors** related to monetization, passes,
      products, or analytics across the whole session.
- [x] 4. Re-run the M3 checklist's sections 1–9 (reveal, level-up, ×1/×10/Max, bottom bar,
      settings, era advance, plot sign, welcome-back, silence) and confirm every one still passes
      exactly as before — M4 must not have changed any M3 behavior when nothing is configured.
- [x] 5. Stop Play.

### Phase B — with real ids pasted in

Do `docs/MANUAL_STEPS.md` M4 sections 2–5 first (create at least one pass and one product, paste
the ids into `src/shared/Config/Monetization.json`, rebuild). You do not need all seven created
to start — test what you have.

- [x] 6. Press Play. Confirm the bottom bar now shows a **Shop** button.
- [x] 7. Open **Shop**. Confirm it lists **exactly** the items you created (and only those —
      anything still at id `0` is absent), in two sections **Passes** then **Packs**, in the same
      order as `Monetization.json`. `DoubleOffline` should **never** appear in the Shop list even
      if its id is set (it's welcome-back-only).
- [x] 8. For each pack row (`Cash30m` / `Cash2h` / `Cash8h` you created), note the previewed
      "up to N minutes" grant amount shown next to the label.
- [x] 9. Confirm the three pack previews are **visibly different amounts**, roughly in a
      **1 : 2.5 : 5** ratio (not identical, and not the nominal 1 : 4 : 16) — this is the
      per-pack cap working. If two pack rows show the same number, that's a bug.
- [x] 10. Buy one pack (see MANUAL_STEPS.md M4 section 7 about real charges before you tap
      through). Confirm the cash that actually lands in your balance **matches the previewed
      amount** from step 8 (small drift is fine if your income changed between preview and
      purchase; a large systematic overstatement — historically up to +27% too high in a full
      server — is the bug this milestone fixed. Testing solo, preview and actual should match
      almost exactly).
- [x] 11. Immediately try to buy the same pack again (or, if Studio lets a receipt replay,
      trigger it twice). Confirm cash is **not** double-granted — one purchase, one grant.
- [x] 12. Buy a pass (e.g. `DoubleCash` or `VIP`). Confirm it applies **within the same
      session, without rejoining**:
      - `DoubleCash`: income/s roughly doubles immediately.
      - `VIP`: a gold plot sign, a `VIP` name tag floating above your character's head, and (if
        VIP variants were imported) VIP building skins — all without leaving and rejoining.
- [x] 13. Buy `OfflinePro`. Stop Play, wait 65+ s, Press Play again. Confirm the Studio
      diagnostic print in Output now reads something like
      `away Ns, saved rate R/s, cap Cs, efficiency E, granted G` with **cap = 86400** (24h) and
      **efficiency = 1** — not the default 8h/0.5. Confirm the welcome-back card's amount is
      correspondingly larger than a non-Pro grant would be.
- [x] 14. If you have Roblox Premium on your test account, confirm a **Premium** indicator shows
      in the UI and income/s reflects the extra 1.1× multiplying with anything else you own
      (e.g. `DoubleCash` × `VIP` × `Premium` ≈ 2.42× if you have all three).
- [x] 15. Confirm a compact **VIP / Premium / neighbors-bonus** indicator is visible somewhere in
      the top bar or Legacy panel and doesn't crowd the top bar at 375×667 (checked again in the
      mobile pass below).
- [x] 16. Buy `DoubleOffline` if you have it: get a welcome-back card, tap "Double it" (only
      visible now that the id is set), confirm the resulting cash delta roughly doubles what the
      card originally showed, and confirm the card's "Double it" button does not reappear for
      that same grant.

### Join-race check (the milestone's Critical bug — do this one carefully)

- [x] 17. With a real pass id set (e.g. `VIP` or `OfflinePro`) and the pass owned: stop Play, wait
      65+ s with nonzero income, then Press Play again **several times in a row** (5+ rejoins) to
      exercise the join sequence under repeated load. Confirm **every single join** still shows a
      correct welcome-back card with a nonzero, plausible amount (per M2 step 14's formula) —
      never a missing card, a silently-zeroed grant, or a warning in Output about the offline
      grant. (This used to be able to silently zero the grant on the join right after a real pass
      id was configured; it's now gated so the income tick can't race the join.)

### M3 carry-over fixes — re-verify these are actually fixed now

- [x] 18. Device Emulator, landscape **640×360**. Open a panel (Build/Legacy/Settings/Shop).
      Confirm the right-docked panel does **not** overlap the top-left top bar anymore (this was
      a known ~9 px overlap at M3, fixed this milestone).
- [x] 19. Rejoin so the very first `StateChanged` snapshot hasn't arrived yet, and within that
      first second or two, tap the **Music** or **SFX** toggle in Settings. Confirm it applies
      **audibly at once** (if you have sound IDs set) rather than waiting for the first
      snapshot/delta to "heal" it.

### Mobile emulation pass (required every milestone)

- [x] 20. Device Emulator, **375×667** portrait. Open the Shop panel (with at least one real id
      set). Confirm every row (pass or pack) is comfortably tappable (~44×44 px), text isn't
      truncated oddly, and nothing overlaps the top or bottom bar. Confirm the VIP/Premium/
      neighbors indicator doesn't crowd the top bar at this width.
- [x] 21. Rotate to landscape (either 667×375 or the 640×360 case from step 18). Confirm the Shop
      panel docks the same way the other panels do and remains usable.
- [x] 22. Stop Play.

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

- [x] 28. All boxes above checked: Phase A silence, Phase B Shop contents/pricing/purchase
      correctness/idempotency/pass application/Offline Pro/Premium/Double-it, the join-race
      check across 5+ rejoins, both M3 carry-over fixes, 375×667 portrait, a landscape pass, and
      the 2-player test.
- [x] 29. Tell Claude Code "M4 playtest passed" (or report the exact failure and step number).
      Ticking this box marks `M4` `[x]` in `docs/PLAN.md`. If the combined M0–M3 checklist above
      hasn't been signed off yet, mention that separately — it's still tracked as pending.

---

## M5 — Hardening

**Goal:** the game survives failure — a save that can't load, a session that's contested by
another server, a shutdown mid-earn, a Robux purchase that needs a confirmed write — without
ever kicking a player for something that isn't their fault, and without ever losing a real
purchase. Nothing about the economy or the UI you already tested changed on the happy path;
this section is entirely about the unhappy paths plus one final end-to-end sweep.

The combined M0–M4 checklist above is still pending full sign-off (M2 has 15 unchecked steps,
M3 has 24 — see the status lines at the top of `docs/PLAN.md`). Those are stale long-haul
persistence/prestige/two-player runs, not known failures — the "Final sweep" subsection at the
end of this M5 section re-covers that same ground in one pass instead of asking you to redo
every individual box. If you'd rather close the old boxes literally one-by-one first, that's
fine too; either path satisfies the spec §12 definition of done.

### 1. Rebuild first

- [x] 1. From the repo root (PowerShell): `$env:PATH = "$HOME\.rokit\bin;$env:PATH"` then
      `rojo build -o build/test.rbxl`. Confirm it succeeds with no errors. (Or reconnect
      `rojo serve` if you're using live sync.)
- [x] 2. Confirm **"Enable Studio Access to API Services"** is still ON (Game Settings →
      Security — same toggle as M2/M3). Almost every check below needs real persistence.

### 2. Force a load failure and confirm safe mode (not a kick)

Use the **`ForceLoadFailure` Studio lever**, not a DataStore trick: ProfileStore retries its own
throttled calls internally and never lets a throttle reach our code, so there's no reliable way
to make a real load fail from outside it. The lead added a Studio-only debug attribute instead —
it is read by `DataService`, ignored entirely in a published game, and lets every load attempt
fail on command without touching real DataStore traffic.

- [ ] 3. **Before** pressing Play: in the **Explorer** window, select **Workspace**. In the
      **Properties** window, scroll to **Attributes**, click **+**, add a new attribute named
      exactly `ForceLoadFailure`, type **boolean**, value **true**.
- [x] 4. Press **Play**. Confirm the **loading card** appears immediately: a centered card
      titled "Loading your city…", over a light dim that does **not** block movement — walk
      your character around the hub while the card is up and confirm you can move and look
      around normally.
- [x] 5. Confirm the **top bar shows dashes** (not "$0" / "0/s") while no snapshot has arrived,
      and the **bottom bar (Build/Legacy/Shop/Settings) is completely hidden** — not greyed out,
      not present-but-disabled, just absent.
- [x] 6. The lever check runs **before** any DataStore call, so the load fails **immediately**
      (well under a second) — no multi-attempt backoff to wait out. Confirm the card changes to
      the **failed** state right away: title "We couldn't load your save", body "Nothing you do
      now will be saved. Try again in a moment, or rejoin.", and two buttons **Retry** and
      **Leave**, both ≥ 44 px tap targets.
      - The lever fails fast, so you will **not** see the "Still working…" line here — that
        line only appears once a load is still genuinely yielding after 8 seconds, which
        section 3's session-lock test below exercises instead. Not seeing it in this section is
        correct, not a bug.
- [x] 7. Check **Output**. Confirm you see a warn line reading
      `[DataService] ForceLoadFailure attribute set — simulating a load failure for <your name>`
      for this attempt, and confirm there is **no `Kick` line** anywhere for this player — the
      M2-era behaviour ("kick on load failure") is gone. Any red error is a bug; only that warn
      and DataService's normal retry logging are expected.
- [x] 8. Confirm **Retry** is disabled with a visible countdown (e.g. "Retry (10s)") that counts
      down live, then becomes tappable once it hits zero.
- [x] 9. With the attribute still `true`, tap **Retry** once it's enabled. Confirm the card
      fails again immediately (same as step 6 — no backoff to wait out), the attempt count
      visibly increments, and Output shows another `ForceLoadFailure` warn line for the new
      attempt.
- [x] 10. Now, while still in Play, go back to **Workspace**'s Attributes and set
      `ForceLoadFailure` to **false** (or delete the attribute). Tap **Retry** again. Confirm
      the load now succeeds: the card disappears, your normal HUD/snapshot arrives, and you get
      your plot — all **without stopping or rejoining**.
- [x] 11. To see **Leave** instead: Stop Play, set `ForceLoadFailure` back to `true` on
      Workspace, Press Play, wait for the failed card, then tap **Leave**. Confirm you are
      kicked with the message "Rejoin to load your save." (this is the one legitimate kick path
      left — something the player chose, not something the server decided for them).
- [x] 12. **Remove the `ForceLoadFailure` attribute from Workspace** (or set it `false`) before
      continuing to any other section below — leaving it `true` will fail every subsequent load,
      including the sections that expect a normal one.

### 3. Session-lock contention — two overlapping sessions

This is the everyday cause of a slow load (a previous server, or a second Studio window, still
holding your session) — it should resolve on its own, not fail.

- [x] 13. Press Play (Play Solo is fine) and stay in that session — don't stop it.
- [x] 14. With that session still running, open a **second** Studio window on the same place
      file (File → Open the same `.rbxl`, or a second `rojo serve`-connected Studio instance)
      and press **Play** there too, on the same Roblox account.
- [x] 15. In the second session, confirm the **loading card** appears (same as section 2) and
      stays in the "loading" phase — not "failed" — while the first session still holds the
      lock. Confirm the "Still working…" line appears after ~8 s.
- [x] 16. Within roughly 40 seconds, confirm the second session's card resolves on its own to
      your normal HUD (the server-side session lock steals after 40 s) — no tap required, no
      failed card, no kick.
- [x] 17. Stop both sessions.

### 4. Shutdown flush (Stop, not Leave)

- [x] 18. Press Play with API access on. Own at least one income-producing building so cash is
      visibly ticking up. Note the exact cash figure at a specific second.
- [x] 19. Press **Stop** (Shift+F5) — not a graceful leave, just Stop, ideally right after you
      see a tick land.
- [x] 20. Press Play again. Confirm the cash you rejoin with is at least the value you noted in
      step 18 (the last tick before Stop was flushed to the DataStore, not lost).
- [x] 21. Now turn API access **OFF** (Game Settings → Security), press Play, and press **Stop**
      immediately. Confirm Stop is not noticeably slower than normal — the shutdown flush only
      waits on real ProfileStore saves; in mock mode (API access off) it must not hang. Turn API
      access back **ON** before continuing to the rest of this checklist.

### 5. Confirmed receipt saves — visible delay, no double grant

Requires at least one real developer product id pasted in (`docs/MANUAL_STEPS.md` M4 §4).

- [x] 22. Open the Shop, buy a pack. Confirm there is now a small but noticeable delay
      (roughly 1–2 seconds) between completing the purchase and the confirmation toast/cash
      landing — this is new this milestone (the server now waits for a confirmed DataStore
      write before telling Roblox the purchase is granted). A total freeze longer than a few
      seconds, or no toast ever arriving, is a bug.
- [x] 23. If Studio lets you replay the same receipt (or just try buying the identical product
      again right away), confirm cash is **not** granted a second time for the same purchase.

### 6. DoubleOffline persists across a session boundary

Requires the `DoubleOffline` product id set.

- [x] 24. Stop Play, wait 65+ seconds with nonzero income, Press Play to get a welcome-back
      card. Tap **"Double it"** to open its confirm/purchase flow, but **do not complete the
      purchase** — instead, immediately Stop Play with that dialog still open.
- [x] 25. Press Play again (new session). If the purchase from step 24 arrives as a receipt in
      this new session (Roblox may deliver it shortly after, even though you "left" mid-flow),
      confirm it grants correctly — the reservation survived the session boundary. This is hard
      to force on demand in Studio (it depends on receipt timing you don't fully control) — if
      no receipt ever arrives, that's not a failure of this check, just note in your report
      whether you observed a grant or observed nothing (inconclusive is fine here).
- [x] 26. What IS checkable directly: after step 24's Stop, if you have DataStore browsing
      access (Creator Hub → your experience → a DataStore viewer, or a Command Bar `GetAsync`
      against the `PlayerData` store for your UserId), confirm the saved profile's
      `pendingDoubleOfflineAmount` field is a **nonzero** number, not `0` — that's the
      persisted reservation this milestone added, and it's the part you can verify without
      waiting on Roblox's receipt delivery timing.

### 7. v1 → v2 migration (silent, no warning)

- [x] 27. Using an existing save from an earlier milestone's testing (any profile that existed
      before this session), press Play and check Output. Confirm there is **no** warning or
      error mentioning migration, schema version, or `pendingDoubleOfflineAmount`. The migration
      is silent and additive — you should see nothing about it in Output at all, just a normal
      clean load.
- [x] 28. If you have DataStore viewing access (same as step 26), confirm the profile's
      `version` field now reads `2`.

### 8. Pad spam and rate limits

- [x] 29. Stand on an unowned pad. Rapidly touch it on and off many times in a couple of seconds
      (walk back and forth across the edge, or nudge repeatedly). Confirm it buys **at most
      once** — no double-charge, no duplicate placeholder, no error in Output from spamming it.

### 9. Pad-touch / prompt failure toast (Build panel closed)

- [x] 30. **Close** the Build panel (tap it again to collapse it, or tap another bottom-bar
      button). Walk onto a pad you can't afford, or trigger a ProximityPrompt level-up you can't
      afford, with the Build panel closed. Confirm you still get a clear **toast/feedback**
      (not just silence) telling you the purchase failed — this is new this milestone; before,
      failure feedback only showed inside the open Build panel.

### 10. Mobile emulation — LoadScreen portrait and landscape (required every milestone)

- [x] 31. Device Emulator, **375×667** portrait. Repeat section 2's forced-failure steps (or at
      minimum, catch the loading card on a normal join). Confirm the card, its title/body text,
      and the Retry/Leave buttons are fully on-screen, not clipped, and comfortably tappable.
- [x] 32. Rotate to **667×375** landscape. Confirm the same card is still fully visible and
      usable — it should stay centered regardless of the panel-docking rules the other panels
      follow (the LoadScreen is not one of the docked panels).
- [x] 33. Stop Play.

### 11. Two-player test — Local Server mode (safe-mode isolation)

- [x] 34. Before starting: set the `ForceLoadFailure` attribute on **Workspace** to `true` (same
      as section 2, step 3). Then **Test → Start** with **2 Players** (Local Server mode). Both
      Player1 and Player2 should land on the failed card, since the attribute is on for every
      load attempt server-side.
- [x] 35. In the **server** window's Explorer (Local Server mode gives you a separate Server
      view plus one Client view per player), set `ForceLoadFailure` back to **false** on
      Workspace.
- [x] 36. As **Player2 only**, tap **Retry**. Confirm Player2's load succeeds and they get a
      normal HUD and plot. **Do not** tap Retry for Player1 — leave Player1 sitting on the
      failed card.
- [x] 37. Confirm **Player1 stays in safe mode**: still showing the failed card, **no plot**
      assigned to them (walk Player2's camera around the hub and confirm no plot on the ring
      belongs to Player1), and no HUD.
- [x] 38. Confirm **Player2** is completely unaffected by Player1's stuck load — normal HUD,
      normal plot, no delay, able to buy/level/etc. normally.
- [x] 39. Remove the `ForceLoadFailure` attribute (same as section 2, step 12) and Stop the test
      session.

### What a bug looks like here

- Any red error in Output at any point above (warnings from DataService's own retry logging are
  expected during a forced failure; errors are not).
- A `Kick` in Output for a load failure (should never happen — only the explicit "Leave" button
  and the pre-existing "loaded on another server" kick are allowed to disconnect a player).
- The loading/failed card blocking movement or the camera.
- The top bar showing "$0 / 0/s" (rather than dashes/blank) before the first snapshot.
- The bottom bar visible or tappable before the first snapshot.
- The "Still working…" line never appearing after 8+ seconds of loading, or appearing instantly.
- Retry usable before its countdown reaches zero, or Retry requiring a full rejoin to work.
- Leave not kicking with the "Rejoin to load your save." message.
- Session-lock contention (section 3) resolving in a "failed" card instead of quietly steal-
  ing after ~40 s.
- Cash from the last tick before Stop missing on rejoin (section 4), or Stop hanging with API
  access off.
- No visible delay before a purchase confirms (section 5) — suggests the confirmed-save wait
  isn't actually happening — or, worse, a double grant on a replay.
- `pendingDoubleOfflineAmount` staying `0` after reserving an offer and leaving (section 6, if
  you have DataStore viewing access to check).
- A migration warning/error in Output (section 7), or `version` not reading `2` on an old save.
- A pad or prompt granting more than once from rapid spam (section 8).
- No failure toast when the Build panel is closed (section 9) — this was the specific gap fixed
  this milestone.
- The LoadScreen clipped, untappable, or missing entirely at 375×667 or 667×375 (sections 10).
- A safe-mode player still getting a plot, or their trouble delaying/affecting the other player
  (section 11).

**Not reproducible in Studio — trust the code path, don't try to force these:**
- A server crash mid-write between a confirmed DataStore save call and the actual write landing
  (the specific scenario `SaveAsync`'s confirmed-write change closes off) — Studio can't crash a
  live server mid-call on demand. The reviewer's full-codebase audit is the check for this, not
  a playtest step.
- The residual DoubleOffline double-settle edge (an old receipt and a new reservation both
  settling in the same session) — needs precise receipt-delivery timing you don't control in
  Studio. Section 6 above is the closest checkable proxy.

### Final sweep — spec §12 definition of done

Run this once, start to finish, in a single sitting if you can. It is the actual bar for
shipping: *"a new player can join on a phone, complete Era 1 in roughly 30–45 minutes without
spending, leave, come back to offline earnings, reach Era 4, rebirth, and never see a purchase
prompt they didn't open themselves."* Use the Studio debug levers (×100 income, per
`docs/BALANCE.md`) to compress the real-time targets — the spec's minutes/hours are the ×1
targets already verified by `sim_economy.py`; this sweep is about the *experience*, not
re-timing it with a stopwatch.

- [x] 40. **Device Emulator, 375×667 portrait** (phone-first, per spec pillar "mobile-first").
      Press Play. Confirm a new/fresh profile loads straight to the hub with no unrequested
      prompt, dialog, or purchase screen of any kind on join — this closes the loop on M0 step
      15, M1 steps 21–24, and M3 step 30's mobile checks without re-running them individually.
- [x] 41. **Complete Era 1** (all 24 Village slots including the monument) using pads and the
      Build panel, spending no Robux. This re-covers M1 sections 2–8 (steps 4–20) and M2 section
      4 (steps 17–21) in one continuous play session rather than as isolated boxes.
- [x] 42. **Leave** (Stop Play) mid-session, with income/s clearly nonzero.
- [x] 43. Wait 65+ seconds real time, then **rejoin**. Confirm the welcome-back card appears
      with a plausible offline amount — this re-covers M2 section 3 (steps 11–16) and M3 section
      8 (steps 25–28).
- [x] 44. **Advance through Era 2, 3, and reach Era 4**, using the debug income multiplier to
      compress the real time. Confirm each advance shows the full-screen era-advance screen,
      ceremony overlay, and plot sign update — this re-covers M2 section 5 (steps 22–26) and M3
      section 6–7 (steps 17–24).
- [x] 45. **Rebirth** once you complete Era 4 (all 24 OrbitalColony slots + monument). Confirm
      the Rebirth confirm dialog and the resulting Era 1 restart with Legacy kept and rebirth
      count incremented — closes M2 section 5 steps 23–26 fully.
- [x] 46. Across the **entire** sweep above (steps 40–45), confirm you **never once saw a
      purchase prompt, Shop nudge, or "Double it" button you didn't tap into yourself** — no
      prompts on join, no blocking modals, at most the one contextual "Double it" offer on a
      welcome-back card you already triggered on purpose. This is the monetization restraint
      rule (spec §6 rules 1–3) held for a whole session, not just a single Phase A/B check.
- [x] 47. Confirm nothing in this whole sweep produced a red Output error.

### Sign-off

- [x] 48. All M5 boxes above checked (sections 1–11: rebuild, forced load failure and safe mode,
      session-lock contention, shutdown flush, confirmed receipt delay, DoubleOffline
      persistence, migration, pad spam, closed-panel failure toast, mobile portrait/landscape,
      two-player isolation) plus the Final sweep (steps 40–47).
- [x] 49. Tell Claude Code "M5 playtest passed" (or report the exact failure and step number).
      Ticking this box marks `M5` `[x]` in `docs/PLAN.md`. If you're treating the Final sweep as
      also closing out the stale M2 (15 boxes) and M3 (24 boxes) sign-offs, say so explicitly —
      otherwise those remain separately tracked as pending in `docs/PLAN.md`.

---

## M6 — Legacy shop (Phase 2)

**Goal:** the Legacy panel becomes a real shop. Legacy is never spent away — buying a perk only
lowers your **Spendable** balance, the total Legacy (and its passive multiplier) never drops.
Twelve perks: seven change gameplay, five are pure cosmetics. Everything below uses a new
Studio-only lever, `GrantLegacy`, so you don't have to grind hours of real play to reach the
shop's later tiers. `docs/BALANCE.md` "M6 — Legacy shop" has the exact numbers cited here if you
want to cross-check.

The combined M0–M5 checklist above is still pending full sign-off on some long-haul boxes (see
the status lines at the top of `docs/PLAN.md`) — that's unchanged by M6 and not part of this gate.

### 1. Rebuild first

- [ ] 1. `$env:PATH = "$HOME\.rokit\bin;$env:PATH"` (PowerShell) then
      `rojo build -o build/test.rbxl` (or reconnect `rojo serve`). `luau-lsp analyze` needs a
      fresh sourcemap — a new module (`LegacyShopService.luau`) landed this milestone:
      `rojo sourcemap default.project.json -o sourcemap.json`.
- [ ] 2. Confirm **"Enable Studio Access to API Services"** is still ON (Game Settings →
      Security). You need real persistence for the rejoin/v3-migration checks in section 9.

### 2. The `GrantLegacy` lever

- [ ] 3. **Before** pressing Play: select **Workspace** in Explorer, Properties → Attributes →
      **+**, add `GrantLegacy`, type **number**, value **3000**.
- [ ] 4. Press Play. Within a second or two (the lever is consumed on the server's 1 Hz tick),
      confirm your Legacy total jumps by 3000 and Output shows a warn line naming the attribute
      and the amount granted.
- [ ] 5. Check Workspace's Attributes again: confirm `GrantLegacy` has reset itself to `0` on its
      own — it is consumed once, not held.
- [ ] 6. **Read this before you close Studio today:** if real API access is on (step 2 above),
      Legacy granted this way is written to your actual saved profile, permanently — it is not a
      sandboxed test value. That's fine for testing the shop, but don't grant huge numbers on an
      account/profile you care about keeping "clean."

### 3. Legacy panel becomes the shop

- [ ] 7. Open the **Legacy** panel (bottom bar). Confirm the header shows **Legacy** (your total,
      unaffected by anything you buy) and **Spendable** (Legacy minus what you've spent — right
      now these should be equal, since you haven't bought anything).
- [ ] 8. Confirm a breakdown row reads `Legacy ×a · Perks ×b · Passes ×c` with real numbers (not
      placeholders), and a one-line note explaining Legacy grows slower past 1,000 (the softcap).
- [ ] 9. Confirm perk rows appear in this exact order: Founder's Blessing, Master Builders,
      Inheritance, Level Floor, Extra Milestone, Good Neighbours, Long Memory, then a cosmetics
      section: Sign Title, Name-Tag Colour, Monument Glow, Advance Fireworks, Golden Roads.
- [ ] 10. Confirm each row shows `Tier n/N`, the next tier's effect description, its cost, and a
      **Buy** button (≥ 44 px tap target).

### 4. Buy Founder's Blessing tier 1 — the full purchase loop

- [ ] 11. Note your current income/s. Tap **Buy** on Founder's Blessing tier 1 (cost 80).
      Confirm: a toast/confirmation appears, the purchase sound plays (if sound IDs are set),
      income/s rises by roughly **5%**, **Spendable drops by 80**, **Legacy total is unchanged**,
      and the breakdown row now reads `Perks ×1.05`.
- [ ] 12. Tap **Buy** on the same row again (still showing tier 1, or now offering tier 2 if you
      have enough — if you don't have 160 spendable yet, this naturally tests the refusal case;
      otherwise grant more Legacy with the lever first to force testing it at tier 1 again by
      trying to double-buy). To specifically test **double-buy refusal**: if the tier already
      advanced past 1, skip to step 13; otherwise this step confirms nothing else to check.
- [ ] 13. Confirm you can never see or tap a tier out of order — only the next tier is ever
      offered on a row; there is no way to jump from tier 1 to tier 3.

### 5. Gameplay perks — verify each one's effect

Grant more Legacy with the lever (section 2) as needed to afford these.

- [ ] 14. **Master Builders** — buy a tier. Open the **Build** panel on an owned, levelable
      building. Confirm the level-up cost shown is **10% lower** per tier owned, and the
      ProximityPrompt's charge (walk up and trigger it) matches the discounted panel price exactly.
- [ ] 15. **Level Floor** — buy tier 1. Buy a brand-new building slot you didn't own before.
      Confirm it spawns **already at level 5** (not level 1). Buy tier 2; the next new building
      should open at **level 8**.
- [ ] 16. **Extra Milestone** — buy it (350). Level a building up past **75**. Confirm its income
      **doubles again** right at 75 (on top of the existing 10/25/50/100 milestones), and its
      Build-panel row label shows something like "×2 at Lv 75".
- [ ] 17. **Inheritance** — buy at least tier 1. Using the debug era-advance/rebirth levers,
      advance an era or rebirth. Confirm your starting cash on the new era is **not zero** —
      it should equal the combined `baseCost` of the first N slots (N = 3/5/8 depending on tier
      owned) in that new era's Build-panel order.
- [ ] 18. **Long Memory** — buy a tier. Stop Play, wait 65+ seconds with nonzero income, Press
      Play again. Confirm the Studio welcome-back diagnostic print in Output shows the offline
      cap **increased by the tier's amount** (e.g. +7200 s = +2h for tier 1) on top of whatever
      pass cap you have.
- [ ] 19. **Good Neighbours** — buy it (250). **Test → Start** with **2 Players** (Local Server
      mode). Confirm the neighbours-bonus display shows **4% per player** (not the default 3%)
      once both players are loaded in, capped at 36%.

### 6. Cosmetics — verify each one appears, and persists

- [ ] 20. Buy all five cosmetics (Sign Title, Name-Tag Colour, Monument Glow, Advance Fireworks,
      Golden Roads) as Legacy allows (grant more with the lever if needed — whole cosmetics set
      is 2050 Legacy).
- [ ] 21. **Sign Title**: walk to your plot sign. Confirm a third line appears with a title (e.g.
      "Founder") — the title should change if your rebirth count is higher (index picks from
      Founder/Magnate/Tycoon/Sovereign/Eternal by rebirth count).
- [ ] 22. **Name-Tag Colour**: look at your own character. Confirm a teal name tag floats over
      your head. Confirm you see **only one** name tag (no duplicate default overhead name
      showing underneath/behind it) — if you also own VIP, confirm the two tags stack vertically
      rather than overlapping.
- [ ] 23. **Monument Glow**: walk to your monument slot. Confirm it visibly glows (emissive/Neon
      look plus a light source), day or night.
- [ ] 24. **Advance Fireworks**: trigger an era-advance or rebirth (debug levers). Confirm a
      particle burst plays at your monument for roughly 2 seconds.
- [ ] 25. **Golden Roads**: confirm your `unlock`-type slots (roads, rails, etc. — not buildings)
      show a gold tint. Confirm your VIP building skins (if VIP owned) are **not** recolored gold
      — Golden Roads should never touch the VIP skin set.
- [ ] 26. **Two-player visibility**: with 2 Players (Local Server), confirm Player 2 can see all
      five of Player 1's cosmetics on Player 1's plot (sign title, name tag, monument glow,
      golden roads) from Player 2's own client.
- [ ] 27. **Fireworks visible to others**: as Player 1, trigger an advance/rebirth. Confirm
      Player 2's client also sees the fireworks burst at Player 1's monument.
- [ ] 28. **Persistence**: Stop Play, Press Play again (real API access on). Confirm every
      cosmetic is still visible immediately on rejoin — no re-purchase needed.

### 7. Auto-open after the ceremony

- [ ] 29. With enough Spendable to afford at least one more tier, trigger an era-advance or
      rebirth ceremony. Confirm that once the ceremony overlay closes, the **Legacy panel opens
      automatically once** (not a blocking modal — you can dismiss it like any other panel).
- [ ] 30. Repeat with **zero** Spendable (spend it all first, or don't grant extra Legacy).
      Confirm the panel does **not** auto-open this time (nothing affordable).

### 8. Reduce-motion / mobile emulator

- [ ] 31. Device Emulator, **375×667** portrait. Turn on reduce-motion (TouchEnabled emulation
      already implies it, or lower Studio's quality level 1–3). Trigger an advance/rebirth with
      Advance Fireworks owned. Confirm the fireworks particle burst is **suppressed locally**
      (you personally don't see it) — but a second, non-reduced-motion player still would
      (covered by step 27).
- [ ] 32. Still at 375×667: open the Legacy panel. Confirm every perk/cosmetic row is
      comfortably tappable (≥ 48 px) and every description wraps cleanly instead of being cut
      off or overlapping the Buy button.
- [ ] 33. Rotate to **667×375** landscape. Confirm the Legacy panel rows are still all reachable,
      tap targets still comfortable, nothing clipped.
- [ ] 34. Stop Play.

### 9. Persistence and schema v3

- [ ] 35. With at least one perk owned, Stop Play, Press Play again. Confirm all owned perks and
      tiers persist exactly as bought — no reset.
- [ ] 36. Check Output on that rejoin. Confirm **no** migration warning/error prints (the v2→v3
      migration is silent and additive, same pattern as v1→v2 in M5).
- [ ] 37. If you have DataStore viewing access, confirm the saved profile's `version` field now
      reads `3` and `legacyShop.perks` contains the ids you bought.

### 10. Missing config — graceful degrade

- [ ] 38. Stop Play. Temporarily rename `src/shared/Config/LegacyShop.json` (e.g. to
      `LegacyShop.json.bak`) and rebuild/resync. Press Play. Confirm the Legacy panel shows
      **no shop** (just Legacy total, or an empty/hidden shop section) and Output has **zero**
      errors. Stop Play, rename the file back, rebuild/resync before continuing.

### What a bug looks like here

- Legacy **total** ever decreasing when you buy something — only Spendable should drop.
- A perk tier being buyable twice, or a later tier being offered/buyable before an earlier one.
- Buying a perk not updating the breakdown row, income/s, or Build-panel prices immediately.
- Master Builders' Build-panel preview and the ProximityPrompt's actual charge disagreeing.
- A new building NOT spawning at the Level Floor level after that perk is owned.
- Extra Milestone not doubling income at level 75, or doubling at the wrong level.
- Inheritance not granting cash on era-advance/rebirth, or granting the wrong amount.
- Long Memory's offline cap increase missing from the diagnostic print.
- Good Neighbours still showing 3%/player after being bought.
- Any cosmetic not appearing on the plot, not visible to a second player, or not surviving a
  rejoin.
- Two overlapping name tags (default + `TitleTag`) instead of one combined/stacked display.
- Golden Roads recoloring a VIP-skinned building.
- Fireworks not visible to a second player, or NOT suppressed locally under reduce-motion.
- The Legacy panel failing to auto-open after a ceremony when something is affordable, or
  auto-opening when nothing is affordable.
- Any migration warning/error in Output, or `legacyShop` not persisting across a rejoin.
- Any error (not just silence) with `LegacyShop.json` removed/renamed.
- `GrantLegacy` not resetting to `0` after being consumed, or not warning in Output.
- Legacy panel rows cramped, overlapping, or un-tappable at 375×667 or 667×375.

### Balance visibility (playtest fix, 2026-09-09)

- [ ] a. Top bar reads `LEGACY <spendable> / <total>`; buy a perk and the first number drops while the second holds.
- [ ] b. Open Legacy and scroll to the bottom of the list: the Legacy total, Spendable, breakdown row and softcap note stay pinned above the list.
- [ ] c. Force a refusal at the boundary (e.g. two quick taps on a tier you can afford only once): a toast reads "Not enough spendable Legacy (have X, need Y)".
- [ ] d. Rename `LegacyShop.json` away: the top bar shows the single total and the panel header collapses to two lines.

### Sign-off

- [ ] 39. All boxes above checked: the `GrantLegacy` lever, the full shop UI (header/breakdown/
      softcap note/row order), the Founder's Blessing buy-and-refuse loop, all seven gameplay
      perks' effects individually verified, all five cosmetics verified on-plot and to a second
      player and across a rejoin, the ceremony auto-open (both affordable and not), reduce-motion
      fireworks suppression, 375×667 portrait, 667×375 landscape, schema v3 persistence with no
      migration warning, and the missing-config graceful degrade.
- [ ] 40. Tell Claude Code "M6 playtest passed" (or report the exact failure and step number).
      Ticking this box marks `M6` `[x]` in `docs/PLAN.md`.
