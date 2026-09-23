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

When M5 started, the M2 (15) and M3 (24) checklists above still had unchecked long-haul
persistence/prestige/two-player steps. Those were not known failures, and the "Final sweep"
subsection at the end of this M5 section re-covered the same ground in one pass. It passed on
2026-09-09, so M2 and M3 are closed in `docs/PLAN.md` even though their individual boxes above
stay unticked.

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

- [x] 1. `$env:PATH = "$HOME\.rokit\bin;$env:PATH"` (PowerShell) then
      `rojo build -o build/test.rbxl` (or reconnect `rojo serve`). `luau-lsp analyze` needs a
      fresh sourcemap — a new module (`LegacyShopService.luau`) landed this milestone:
      `rojo sourcemap default.project.json -o sourcemap.json`.
- [x] 2. Confirm **"Enable Studio Access to API Services"** is still ON (Game Settings →
      Security). You need real persistence for the rejoin/v3-migration checks in section 9.

### 2. The `GrantLegacy` lever

- [x] 3. **Before** pressing Play: select **Workspace** in Explorer, Properties → Attributes →
      **+**, add `GrantLegacy`, type **number**, value **3000**.
- [x] 4. Press Play. Within a second or two (the lever is consumed on the server's 1 Hz tick),
      confirm your Legacy total jumps by 3000 and Output shows a warn line naming the attribute
      and the amount granted.
- [x] 5. Check Workspace's Attributes again: confirm `GrantLegacy` has reset itself to `0` on its
      own — it is consumed once, not held.
- [x] 6. **Read this before you close Studio today:** if real API access is on (step 2 above),
      Legacy granted this way is written to your actual saved profile, permanently — it is not a
      sandboxed test value. That's fine for testing the shop, but don't grant huge numbers on an
      account/profile you care about keeping "clean."

### 3. Legacy panel becomes the shop

- [x] 7. Open the **Legacy** panel (bottom bar). Confirm the header shows **Legacy** (your total,
      unaffected by anything you buy) and **Spendable** (Legacy minus what you've spent — right
      now these should be equal, since you haven't bought anything).
- [x] 8. Confirm a breakdown row reads `Legacy ×a · Perks ×b · Passes ×c` with real numbers (not
      placeholders), and a one-line note explaining Legacy grows slower past 1,000 (the softcap).
- [x] 9. Confirm perk rows appear in this exact order: Founder's Blessing, Master Builders,
      Inheritance, Level Floor, Extra Milestone, Good Neighbours, Long Memory, then a cosmetics
      section: Sign Title, Name-Tag Colour, Monument Glow, Advance Fireworks, Golden Roads.
- [x] 10. Confirm each row shows `Tier n/N`, the next tier's effect description, its cost, and a
      **Buy** button (≥ 44 px tap target).

### 4. Buy Founder's Blessing tier 1 — the full purchase loop

- [x] 11. Note your current income/s. Tap **Buy** on Founder's Blessing tier 1 (cost 80).
      Confirm: a toast/confirmation appears, the purchase sound plays (if sound IDs are set),
      income/s rises by roughly **5%**, **Spendable drops by 80**, **Legacy total is unchanged**,
      and the breakdown row now reads `Perks ×1.05`.
- [x] 12. Tap **Buy** on the same row again (still showing tier 1, or now offering tier 2 if you
      have enough — if you don't have 160 spendable yet, this naturally tests the refusal case;
      otherwise grant more Legacy with the lever first to force testing it at tier 1 again by
      trying to double-buy). To specifically test **double-buy refusal**: if the tier already
      advanced past 1, skip to step 13; otherwise this step confirms nothing else to check.
- [x] 13. Confirm you can never see or tap a tier out of order — only the next tier is ever
      offered on a row; there is no way to jump from tier 1 to tier 3.

### 5. Gameplay perks — verify each one's effect

Grant more Legacy with the lever (section 2) as needed to afford these.

- [x] 14. **Master Builders** — buy a tier. Open the **Build** panel on an owned, levelable
      building. Confirm the level-up cost shown is **10% lower** per tier owned, and the
      ProximityPrompt's charge (walk up and trigger it) matches the discounted panel price exactly.
- [x] 15. **Level Floor** — buy tier 1. Buy a brand-new building slot you didn't own before.
      Confirm it spawns **already at level 5** (not level 1). Buy tier 2; the next new building
      should open at **level 8**.
- [x] 16. **Extra Milestone** — buy it (350). Level a building up past **75**. Confirm its income
      **doubles again** right at 75 (on top of the existing 10/25/50/100 milestones), and its
      Build-panel row label shows something like "×2 at Lv 75".
- [x] 17. **Inheritance** — buy at least tier 1. Using the debug era-advance/rebirth levers,
      advance an era or rebirth. Confirm your starting cash on the new era is **not zero** —
      it should equal the combined `baseCost` of the first N slots (N = 3/5/8 depending on tier
      owned) in that new era's Build-panel order.
- [x] 18. **Long Memory** — buy a tier. Stop Play, wait 65+ seconds with nonzero income, Press
      Play again. Confirm the Studio welcome-back diagnostic print in Output shows the offline
      cap **increased by the tier's amount** (e.g. +7200 s = +2h for tier 1) on top of whatever
      pass cap you have.
- [x] 19. **Good Neighbours** — buy it (250). **Test → Start** with **2 Players** (Local Server
      mode). Confirm the neighbours-bonus display shows **4% per player** (not the default 3%)
      once both players are loaded in, capped at 36%.

### 6. Cosmetics — verify each one appears, and persists

- [x] 20. Buy all five cosmetics (Sign Title, Name-Tag Colour, Monument Glow, Advance Fireworks,
      Golden Roads) as Legacy allows (grant more with the lever if needed — whole cosmetics set
      is 2050 Legacy).
- [x] 21. **Sign Title**: walk to your plot sign. Confirm a third line appears with a title (e.g.
      "Founder") — the title should change if your rebirth count is higher (index picks from
      Founder/Magnate/Tycoon/Sovereign/Eternal by rebirth count).
- [x] 22. **Name-Tag Colour**: look at your own character. Confirm a teal name tag floats over
      your head. Confirm you see **only one** name tag (no duplicate default overhead name
      showing underneath/behind it) — if you also own VIP, confirm the two tags stack vertically
      rather than overlapping.
- [x] 23. **Monument Glow**: walk to your monument slot. Confirm it visibly glows (emissive/Neon
      look plus a light source), day or night.
- [x] 24. **Advance Fireworks**: trigger an era-advance or rebirth (debug levers). Confirm a
      particle burst plays at your monument for roughly 2 seconds.
- [x] 25. **Golden Roads**: confirm your `unlock`-type slots (roads, rails, etc. — not buildings)
      show a gold tint. Confirm your VIP building skins (if VIP owned) are **not** recolored gold
      — Golden Roads should never touch the VIP skin set.
- [x] 26. **Two-player visibility**: with 2 Players (Local Server), confirm Player 2 can see all
      five of Player 1's cosmetics on Player 1's plot (sign title, name tag, monument glow,
      golden roads) from Player 2's own client.
- [x] 27. **Fireworks visible to others**: as Player 1, trigger an advance/rebirth. Confirm
      Player 2's client also sees the fireworks burst at Player 1's monument.
- [x] 28. **Persistence**: Stop Play, Press Play again (real API access on). Confirm every
      cosmetic is still visible immediately on rejoin — no re-purchase needed.

### 7. Auto-open after the ceremony

- [x] 29. With enough Spendable to afford at least one more tier, trigger an era-advance or
      rebirth ceremony. Confirm that once the ceremony overlay closes, the **Legacy panel opens
      automatically once** (not a blocking modal — you can dismiss it like any other panel).
- [x] 30. Repeat with **zero** Spendable (spend it all first, or don't grant extra Legacy).
      Confirm the panel does **not** auto-open this time (nothing affordable).

### 8. Reduce-motion / mobile emulator

- [x] 31. Device Emulator, **375×667** portrait. Turn on reduce-motion (TouchEnabled emulation
      already implies it, or lower Studio's quality level 1–3). Trigger an advance/rebirth with
      Advance Fireworks owned. Confirm the fireworks particle burst is **suppressed locally**
      (you personally don't see it) — but a second, non-reduced-motion player still would
      (covered by step 27).
- [x] 32. Still at 375×667: open the Legacy panel. Confirm every perk/cosmetic row is
      comfortably tappable (≥ 48 px) and every description wraps cleanly instead of being cut
      off or overlapping the Buy button.
- [x] 33. Rotate to **667×375** landscape. Confirm the Legacy panel rows are still all reachable,
      tap targets still comfortable, nothing clipped.
- [x] 34. Stop Play.

### 9. Persistence and schema v3

- [x] 35. With at least one perk owned, Stop Play, Press Play again. Confirm all owned perks and
      tiers persist exactly as bought — no reset.
- [x] 36. Check Output on that rejoin. Confirm **no** migration warning/error prints (the v2→v3
      migration is silent and additive, same pattern as v1→v2 in M5).
- [x] 37. If you have DataStore viewing access, confirm the saved profile's `version` field now
      reads `3` and `legacyShop.perks` contains the ids you bought.

### 10. Missing config — graceful degrade

- [x] 38. Stop Play. Temporarily rename `src/shared/Config/LegacyShop.json` (e.g. to
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

- [x] a. Top bar reads `LEGACY <spendable> / <total>`; buy a perk and the first number drops while the second holds.
- [x] b. Open Legacy and scroll to the bottom of the list: the Legacy total, Spendable, breakdown row and softcap note stay pinned above the list.
- [x] c. Force a refusal at the boundary (e.g. two quick taps on a tier you can afford only once): a toast reads "Not enough spendable Legacy (have X, need Y)".
- [x] d. Rename `LegacyShop.json` away: the top bar shows the single total and the panel header collapses to two lines.

### Sign-off

- [x] 39. All boxes above checked: the `GrantLegacy` lever, the full shop UI (header/breakdown/
      softcap note/row order), the Founder's Blessing buy-and-refuse loop, all seven gameplay
      perks' effects individually verified, all five cosmetics verified on-plot and to a second
      player and across a rejoin, the ceremony auto-open (both affordable and not), reduce-motion
      fireworks suppression, 375×667 portrait, 667×375 landscape, schema v3 persistence with no
      migration warning, and the missing-config graceful degrade.
- [x] 40. Tell Claude Code "M6 playtest passed" (or report the exact failure and step number).
      Ticking this box marks `M6` `[x]` in `docs/PLAN.md`.

---

## Post-M6 — Ambient era loops

The four ambient loops were uploaded after the M6 playtest (`docs/MANUAL_STEPS.md` M3 §3 item 9)
and have real ids in `src/shared/Config/Sounds.json`. Nothing else changed. Rebuild first
(`rojo build -o build/test.rbxl` or reconnect `rojo serve`), have Music ON in Settings, and use
the Studio debug income multiplier (`docs/BALANCE.md`) to move between eras quickly.

- [ ] 1. Press Play in Era 1. Within a few seconds a quiet medieval loop starts under the other
      sounds; clicks and purchase sounds stay clearly audible over it.
- [ ] 2. Let it run past its end once. It restarts on its own with no long silence.
- [ ] 3. Buy a slot and level something up. The loop keeps playing and does not restart.
- [ ] 4. Turn **Music** off in Settings: the loop goes silent at once, while SFX still play.
      Turn it back on: the loop is audible again.
- [ ] 5. Advance to Era 2, 3 and 4. After each ceremony the previous loop stops and that era's
      loop starts (Era 2 old-west, Era 3 sci-fi city, Era 4 outer space). Two loops never play
      together.
- [ ] 6. Rebirth. The Era 1 loop comes back.
- [ ] 7. Across the whole run, Output shows no warning or error about a sound. If one era stays
      silent, check that asset's moderation status on create.roblox.com before reporting it.
- [ ] 8. Tell Claude Code "ambient loops OK", or name the era and step that failed.

---

## M7 — Growing buildings (Village)

**Goal:** placeholder Parts are gone for Village — every slot is a Kenney-kit mesh that grows
through five stages (stage 0 on buy, then a swap at base milestones 10/25/50/100). A new
Studio-only lever, `GrantCash`, lets you level buildings fast without grinding real income.
`docs/BALANCE.md` and `docs/PLAN.md` M7 have the numbers/decisions behind this if you want to
cross-check.

### 1. Rebuild first

- [ ] 1. `$env:PATH = "$HOME\.rokit\bin;$env:PATH"` (PowerShell) then
      `rojo build -o build/test.rbxl` (or reconnect `rojo serve`). Regenerate the sourcemap before
      any `luau-lsp analyze` run: `rojo sourcemap default.project.json -o sourcemap.json`.
- [ ] 2. Confirm **"Enable Studio Access to API Services"** is still ON (Game Settings →
      Security) — you need real persistence for the rejoin check in section 6, and a real VIP
      pass purchase in section 4.

### 2. The `GrantCash` lever

- [ ] 3. **Before** pressing Play: select **Workspace** in Explorer, Properties → Attributes →
      **+**, add `GrantCash`, type **number**, value big enough to afford several building
      levels (e.g. `100000` — check the Tavern's level-up cost in the Build panel first if
      unsure).
- [ ] 4. Press Play. Within a second or two (the lever is consumed on the server's 1 Hz tick,
      same pattern as `GrantLegacy`), confirm your cash jumps by that amount and Output shows a
      warn line naming the attribute and the amount granted.
- [ ] 5. Check Workspace's Attributes again: confirm `GrantCash` has reset itself to `0` on its
      own. Re-add it with a new value any time you need more cash.
- [ ] 6. **Note, not a bug:** `GrantCash` does **not** increase your all-time-cash stat
      (`stats.totalCashAllTime`) — only real income and offline grants do. If you're
      cross-checking a stats display, a `GrantCash`-heavy session under-reporting all-time cash
      vs. wallet cash is expected.

### 3. First buy — mesh, not a placeholder

- [ ] 7. Open the Build panel, buy any Village slot (a fresh save has none owned yet). Confirm the
      building that appears at the anchor is a **textured, correctly proportioned mesh** — no
      grey/untextured box, no floating `BillboardGui` label. It should face the buy pad, roughly
      toy-proportioned (not huge, not miniature).
- [ ] 8. Confirm the reveal tween (pop-in from small) still plays as it did before M7, and the
      `purchase`/`reveal` sounds still fire.

### 4. Growing a Tavern through all five stages

- [ ] 9. Buy the **Tavern** if you haven't already. Use the `GrantCash` lever (section 2) and the
      Build panel's ×1/×10/Max level buttons to bring it to level **10**. Confirm: one growth
      pop plays on the building (a quick scale bounce) and one milestone sound plays — not two,
      not zero.
- [ ] 10. Repeat to level **25**, then **50**, then **100**. Confirm a stage swap (visibly more
      built-up model) with exactly one pop + one milestone sound at each crossing, and that the
      model never flashes back to a smaller stage.
- [ ] 11. **Double-crossing edge case:** get the Tavern to level 9. Tap **+10** twice quickly (so
      it jumps roughly L9 -> L19 -> L29, crossing both the 10 and the 25 milestones in quick
      succession). Confirm the building ends up at the correct **Stage2** model (not oversized,
      not undersized, not stuck at Stage1) and there's no visible glitch/flicker between stages.
- [ ] 12. Open the Build panel row for a `building` slot below stage 4: confirm the hint line
      reads something like "x2 & grows at Lv 25" (merged copy — one line, not two separate
      hints). At stage 4 (level 100) confirm the "grows at" part is gone.

### 5. VIP — texture swap, not a new model

- [ ] 13. If you don't already own the `VIP` pass on this profile, buy it now (same flow as
      `docs/PLAYTEST.md` M4 section 3, step 12 — Shop panel, `VIP`; read M4's note there about
      real-ish Studio purchases before you tap through).
- [ ] 14. With VIP owned, walk your plot and confirm buildings show a **gold-tinted colormap**
      instead of their normal texture — check all three kits used in Village
      (`fantasy-town-kit`, `castle-kit`, `nature-kit`), e.g. a house, the Watchtower, and a
      FlowerBed/TreeOak. It should look like a recoloured skin, not a different model.
- [ ] 15. If you were mid-session without VIP and just bought it, confirm the gold skin applies
      to every already-owned building **without a rejoin** (the existing `RefreshCosmetics`
      path, now driving a `TextureID` swap instead of a template swap).

### 6. Missing config — graceful degrade

- [ ] 16. Stop Play. Temporarily rename `src/shared/Config/Assets.json` (e.g. to
      `Assets.json.bak`) **and** temporarily rename the `templates/` folder (e.g.
      `templates_bak/`). Rebuild/resync. Press Play. Confirm **every** Village slot falls back to
      the old tinted-box placeholder with its `modelName` label, and Output has **zero** errors.
- [ ] 17. Stop Play, rename both back, rebuild/resync before continuing.

### 7. Part budget and prompt reachability

- [ ] 18. Using `GrantCash`, buy and fully level (to stage 4 where applicable) every slot on your
      plot — all 24. Once done, open the Explorer and confirm
      `Workspace/Plots/Plot_<i>/Buildings` holds **≤ 60 parts** total.
- [ ] 19. Walk up to the **CastleKeep** monument (the tallest, most imposing stage-4 model in
      Village) and confirm its ProximityPrompt (level-up, if it's a levelable type — otherwise
      skip) is easy to reach and trigger, not buried inside the mesh or floating far from it.
      Repeat for any other stage-4 building that looks unusually tall.

### 8. Walk the whole plot — placement sanity

- [ ] 20. With all 24 slots owned (from section 7), walk the entire plot ring and look at every
      building from a few angles. Confirm: every model faces its buy pad (not sideways or
      backwards), nothing floats above the ground, nothing sinks into the ground, and no building
      clips badly into a neighbour. **Known, accepted by design:** the Windmill's sails overhang
      its 9x9 footprint by about 0.5 studs — not a bug, don't report it.

### 9. Reduce-motion / mobile emulator

- [ ] 21. Device Emulator, **375x667** portrait. Turn on reduce-motion (TouchEnabled emulation
      already implies it, or lower Studio's quality level 1–3). Trigger a milestone crossing
      (`GrantCash` + level buttons). Confirm the growth pop is **shortened**, **no particles**
      play, and the milestone flash/highlight is still visible (feedback isn't silently lost,
      just toned down).
- [ ] 22. Still at 375x667: open the Build panel and confirm the merged growth hint reads cleanly
      without wrapping oddly or overlapping the Buy/Level buttons.
- [ ] 23. Stop Play.

### 10. Two-player — stage growth replicates

- [ ] 24. **Test -> Start** with **2 Players** (Local Server mode). As Player 1, use `GrantCash`
      and level a building through a milestone crossing. Confirm **Player 2's client** sees the
      stage swap and the growth pop on Player 1's plot too (world state replicates to everyone,
      same as reveal/level-up FX before M7).
- [ ] 25. As Player 1, confirm your VIP gold skins (if VIP owned) are visible from **Player 2's**
      client on Player 1's plot.
- [ ] 26. Stop Play.

### What a bug looks like here

- Any slot showing a grey/untextured mesh, or a mesh at the wrong scale (tiny or huge relative to
  its pad).
- A building not facing its pad after spawn.
- Two pops, or zero pops, at a single milestone crossing; a milestone sound playing more than
  once per crossing.
- The double-crossing edge case (step 11) landing on the wrong stage, or a visible flicker between
  stages.
- The growth hint showing two separate lines instead of one merged line, or not updating after a
  stage swap.
- VIP showing anything other than a texture/colour change (e.g. a different-shaped model), or not
  applying to every kit.
- VIP not applying live via `RefreshCosmetics` without a rejoin.
- Any error in Output with `Assets.json`/`templates/` renamed away — placeholders must appear
  silently.
- More than 60 parts under a fully-built plot's `Buildings` folder.
- A ProximityPrompt unreachable or buried inside a tall stage-4 mesh.
- Any building floating, sunk, or badly clipping a neighbour (the Windmill's sail overhang is not
  this — see section 8).
- Reduce-motion not shortening the pop or not suppressing particles, or suppressing the milestone
  flash entirely (it should stay visible, just less animated).
- Stage growth or VIP skins not visible from a second player's client.
- `GrantCash` not resetting to `0` after being consumed, or not warning in Output.

### Sign-off

- [ ] 27. All boxes above checked: the `GrantCash` lever, a first buy showing a real mesh, a full
      0->100 Tavern growth run including the double-crossing edge case, the merged growth hint,
      VIP as a texture swap on all three kits (including live re-skin), the missing-config
      graceful degrade, the <= 60-part budget with a full plot, prompt reachability on the tallest
      building, a full-plot placement walk, 375x667 reduce-motion, and the two-player replication
      check.
- [ ] 28. Tell Claude Code "M7 playtest passed" (or report the exact failure and step number).
      Ticking this box marks `M7` `[x]` playtested in `docs/PLAN.md`.

---

## M8 — Growing buildings (Boomtown)

**Goal:** all 24 Boomtown slots have real meshes, same pipeline as M7's Village pass — built from
`city-kit-suburban`, `city-kit-industrial`, and `city-kit-roads` for street props. Direction this
era is "lower, wider": ordinary buildings top out around 13 studs at level 100 and grow mostly by
width and clutter, not height. Only three landmarks are tall. This section assumes M7 already
passed — it doesn't repeat the `GrantCash` lever setup, growth-pop/sound mechanics, VIP-as-
texture-swap mechanics, or the missing-config degrade check in depth; it re-checks them briefly on
Boomtown's models and spends the rest of the time on placement/silhouette/approximation quality.

### 1. Rebuild first

- [ ] 1. `$env:PATH = "$HOME\.rokit\bin;$env:PATH"` (PowerShell) then
      `rojo build -o build/test.rbxl` (or reconnect `rojo serve`). Regenerate the sourcemap
      before any `luau-lsp analyze` run: `rojo sourcemap default.project.json -o sourcemap.json`.
- [ ] 2. Confirm **"Enable Studio Access to API Services"** is still ON (Game Settings →
      Security).

### 2. Reach Boomtown

- [ ] 3. Press Play. On a fresh or near-complete Village save, use the `GrantCash` Workspace
      attribute (M7 section 2 — add it, type number, big value) to afford and buy all 24 Village
      slots including the monument.
- [ ] 4. Tap the gold **"Advance Era → Boomtown"** banner at the top of the Build panel, then
      **Confirm** (M2/M3 behaviour — full-screen ceremony, ~40 min of design-target progress
      compressed by `GrantCash`). Confirm you land in Boomtown: era badge "ERA 2" / "Boomtown",
      plot base recolored, Build panel rebuilt to 24 fresh Boomtown rows, all locked except the
      free first slot (**Newsstand**, cost 0).
- [ ] 5. If you'd rather skip Village entirely on a throwaway profile, rebirthing back around
      also lands you in Boomtown after one lap — either path is fine, just note which you used.

### 3. Buy every slot — meshes, no placeholders

- [ ] 6. Re-add `GrantCash` with a large value as needed. In the Build panel, buy all 24 slots in
      the order listed (Newsstand → Hot Dog Stand → Diner → Gas Station → Motel → Pave Main
      Street → Barber Shop → Fire Hydrant → Grocery Store → Laundromat → Car Dealership →
      Traffic Lights → Cinema → Streetlamp Row → Auto Repair Shop → Bowling Alley → Bus Line →
      Bank → Department Store → Billboard → Radio Station → Fire Station → Neon District → Clock
      Tower).
- [ ] 7. As each one appears, confirm it's a **textured stage-0 mesh** — no grey/untextured box,
      no floating placeholder label, no red error in Output. Same check as M7 section 3.

### 4. Walk the plot — placement sanity

- [ ] 8. Walk the entire plot ring at a few angles. Confirm: every model faces its buy pad, no
      piece floats above the ground, nothing sinks into the ground, and no building clips badly
      into a neighbouring slot's footprint.
- [ ] 9. Confirm the **Clock Tower** (monument, last slot) sits at the mouth of main street and
      faces arriving players — it should read as the landmark you walk toward, not something
      tucked in a corner or facing away.

### 5. Grow one building through all five stages

- [ ] 10. Use `GrantCash` and the Build panel's ×1/×10/Max buttons to level the **Radio Station**
      from 0 to level 10, then 25, then 50, then 100. Confirm one growth pop + one milestone
      sound at each crossing (not two, not zero — same check as M7 section 4), the model visibly
      grows wider/more built-up at each stage, and it never flashes back to a smaller stage.
- [ ] 11. Confirm the Build panel's growth hint line updates/merges the same way it did for
      Village (M7 section 4, step 12).

### 6. Silhouette check — "lower, wider" holds up

- [ ] 12. With the Radio Station at level 100 (from section 5) and the Fire Station and Clock
      Tower also bought, stand back from the plot and compare heights by eye. Confirm the order,
      tallest to shortest: **Clock Tower** (25.8 studs, tallest) > **Radio Station** (21.3 studs,
      lattice mast) > **Fire Station** (18.7 studs, water tower). Everything else should read
      noticeably lower and squatter than these three — no ordinary slot should look taller than
      the Fire Station.
- [ ] 13. Confirm the Fire Station's water tower and the Radio Station's lattice mast are the
      features making them tall, not a tall building body — the "lower, wider" direction should
      still be visible in the base structure under each mast/tower.

### 7. Known approximations — eyeball, not blockers

None of the pieces below have a matching Kenney model; each is assembled from adjacent kit props.
Confirm each looks like a reasonable stand-in, not broken/misplaced:

- [ ] 14. **Bus Line** (`BusYellow`): the model is a **bus stop**, not an actual bus — confirm it
      reads as a bus stop (shelter/sign), not as a broken vehicle.
- [ ] 15. **Fire Hydrant**: stacked grey barriers with red disc caps standing in for a hydrant —
      confirm it reads as a curbside object roughly hydrant-sized, not a random barrier pile.
- [ ] 16. **Barber Shop** pole: a striped construction light stands in for the barber pole —
      confirm it's mounted near the shop entrance like a sign, not floating loose.
- [ ] 17. **Clock Tower** clock faces: rings of red stop-sign discs stand in for the clock faces —
      confirm all four faces (or however many are visible) show the same disc-ring treatment
      consistently, not just one face.
- [ ] 18. **Neon District** (`NeonSign`): a red disc arrow with beacon "bulbs" — confirm the front
      reads as a lit sign shape; the **back is expected to read as an unlit dark tube** — that's
      the known look, not a bug.
- [ ] 19. **Newsstand** paper rack: an A-board plus a fence board — confirm it sits beside the
      stand like a rack/display, not blocking the buy pad or a walkway.

### 8. Known minor flaws — confirm present, not blockers

These are recorded, accepted issues — check they look the way described, don't file them again:

- [ ] 20. **Bank** and **Laundromat**: both put a house-style piece on a flat industrial block, so
      they may look similar from a distance. Confirm this is the case (a similarity, not a
      complete duplicate) and move on.
- [ ] 21. **Gas Station**: the raised round fuel tank is a large mass roughly the same scale as
      the Fire Station's water tower. Confirm it doesn't actually exceed the Fire Station in
      height (section 6) — it's allowed to look chunky, not to break the silhouette order.
- [ ] 22. **Bank**: ground-floor garage doors are visible on its back side. Confirm the front
      (facing the pad) looks correct with columns and brass doors — the garage doors on the back
      are the known flaw, not a sign the wrong model loaded.

### 9. VIP skins

- [ ] 23. If you don't already own the `VIP` pass on this profile, buy it now (Shop panel, same
      flow as M4 section 3 / M7 section 5).
- [ ] 24. With VIP owned, walk the plot and confirm Boomtown buildings show a recoloured
      gold-tinted skin using the **three new city-kit swatches** uploaded for this era — check at
      least one `city-kit-suburban` piece, one `city-kit-industrial` piece, and one
      `city-kit-roads` prop. It should look like a colour swap, not a different model.
- [ ] 25. If you just bought VIP mid-session, confirm the gold skin applies to every already-owned
      Boomtown building without a rejoin.

### 10. Mobile emulation pass (required every milestone)

- [ ] 26. Device Emulator, **375×667** portrait. Walk the plot and open the Build panel. Confirm
      nothing about the growth hint text or button layout regressed from M7's mobile pass, and
      the plot itself renders/scales sensibly at this resolution (no obviously oversized or
      clipped-off-screen geometry from the wider Boomtown models).
- [ ] 27. Stop Play.

### What a bug looks like here

- Any slot showing a grey/untextured mesh, a red error in Output, or a mesh at the wrong scale.
- A building not facing its pad, floating, sunk, or badly clipping a neighbouring slot.
- The Clock Tower not at the mouth of main street, or not facing arriving players.
- Two pops or zero pops at a milestone crossing, or a milestone sound firing more than once.
- Silhouette order broken — any ordinary slot taller than the Fire Station, or the Radio Station
  taller than the Clock Tower.
- Any of the approximations (section 7) looking broken/misplaced rather than a reasonable
  stand-in — e.g. the bus stop reading as a mangled vehicle, the hydrant barrier stack floating,
  the neon sign's front unlit instead of just its back.
- The Bank's garage doors visible from the front, or the Gas Station's fuel tank taller than the
  Fire Station's water tower (that would be a real regression, not the known flaw).
- VIP showing a different-shaped model instead of a texture/colour change, or not applying live.

### Sign-off

- [ ] 28. All boxes above checked: reaching Boomtown, all 24 slots buying in as real meshes, a
      full plot placement walk including the Clock Tower's orientation, a full 0→100 growth run
      on the Radio Station, the silhouette order, every known approximation and known minor flaw,
      VIP skins, and 375×667 mobile emulation.
- [ ] 29. Tell Claude Code "M8 Boomtown assets playtest passed" (or report the exact failure and
      step number).

---

## M8 — Growing buildings (Metropolis)

**Goal:** all 24 Metropolis slots have real meshes, same pipeline as M7's Village pass and M8's
Boomtown pass — built from `city-kit-commercial`, with `city-kit-roads` and a few
`city-kit-suburban` pieces as props. Direction this era is the opposite of Boomtown's: Metropolis
is the **tall commercial** era — shops, offices and towers, topping out at a 35.6-stud skyscraper.
This section assumes M7 and M8 Boomtown already passed — it doesn't repeat the `GrantCash` lever
setup, growth-pop/sound mechanics, VIP-as-texture-swap mechanics, or the missing-config degrade
check in depth; it re-checks them briefly on Metropolis models and spends the rest of the time on
the new 12×12 Stadium, the skyline order, and telling Metropolis apart from Boomtown.
**No Luau or config logic changed this wave** (content only), so there is no two-player pass in
this section — M7 section 10 already covers stage replication.

**Expect a bare plot — Metropolis city dressing does not exist yet.** Roads, paths, trees, filler
houses, plazas and vehicles are **M9 wave 2**, and only Village and Boomtown have them today.
A Metropolis plot is buildings, buy pads and grass, nothing else. Missing paths and props here are
**not a bug** — see section 9.

### 1. Rebuild first

- [ ] 1. `$env:PATH = "$HOME\.rokit\bin;$env:PATH"` (PowerShell) then
      `rojo build -o build/test.rbxl` (or reconnect `rojo serve`). Regenerate the sourcemap
      before any `luau-lsp analyze` run: `rojo sourcemap default.project.json -o sourcemap.json`.
- [ ] 2. Confirm **"Enable Studio Access to API Services"** is still ON (Game Settings →
      Security).

### 2. Reach Metropolis

- [ ] 3. Press Play. Use the `GrantCash` Workspace attribute (M7 section 2 — select Workspace,
      Properties → Attributes → **+**, name `GrantCash`, type **number**) to buy out whatever era
      the save is in and advance until the era badge reads **"ERA 3" / "Metropolis"**. Metropolis
      prices run into the trillions (the Skyscraper alone is 1.25T), so grant
      `10000000000000` (10T) in one go rather than topping up per slot.
- [ ] 4. Confirm the advance ceremony plays, the plot base recolors, and the Build panel rebuilds
      to 24 fresh Metropolis rows — all locked except the free first slot (**Food Truck**,
      cost 0).

### 3. Buy every slot — meshes, no placeholders

- [ ] 5. Re-add `GrantCash` as needed. In the Build panel, buy all 24 slots in the order listed
      (Food Truck → Coffee Shop → Corner Shop → Apartment Block → Low-Rise Office → Found City
      Hall → Supermarket → Bus Stop → High-Rise Apartments → Parking Garage → Shopping Mall →
      Dig the Subway Line → Hospital → City Park → Office Tower → Hotel Tower → Build the Highway
      Ramp → Stadium → Convention Center → Rooftop Garden → Bank Tower → Broadcast Tower → Open
      the Finance District → Skyscraper).
- [ ] 6. As each one appears, confirm it's a **textured stage-0 mesh** that reads as the thing its
      row is named — no grey/untextured box, no floating placeholder label, no red error in
      Output. Same check as M7 section 3 and M8 Boomtown section 3.

### 4. Walk the plot — placement sanity

- [ ] 7. Walk the entire plot ring at a few angles. Confirm: every model faces its buy pad, no
      piece floats above the ground, nothing sinks into the ground, and no building clips badly
      into a neighbouring slot's footprint or pad.
- [ ] 8. Confirm the **Skyscraper** (monument, last slot) sits at the front of the plot facing
      arriving players — it should read as the landmark you walk toward, the same role the Clock
      Tower plays in Boomtown.

### 5. Stadium — the first 12×12 slot (check this one on its own)

The Stadium is the **first non-monument slot allowed to exceed 9×9** and the **only building not
assembled from a Kenney kit**: `city-kit-commercial` has no grass or seating piece, so the stands
and the green pitch are custom geometry generated by `tools/assets/stadium_kit.py` (8 modules,
colours sampled from the kit's own colormap). It is 12.00 × 12.32 × 10.40 studs at stage 4,
2298 tris in a single MeshPart. Give it its own pass.

- [ ] 9. Stand over the Stadium at stage 0 and confirm the **green marked pitch** in the middle is
      clearly visible, and that the white stands read against the plot's grey asphalt.
- [ ] 10. Level it 0 → 10 → 25 → 50 → 100 with `GrantCash` and the ×1/×10/Max buttons. At **every**
      stage including 100, confirm the pitch is still visible — stands must never close over it
      or roof it in.
- [ ] 11. Confirm the stands grow on the **back and far side**, leaving the front (pad side) open.
- [ ] 12. Confirm the floodlights sit **on the stands/roofs** — none free-standing on the ground
      next to the building.
- [ ] 13. Confirm the **buy pad in front is still reachable and walkable**: the building's front
      face is at z −4.40 and the pad sits 8 studs out, so there should be a clear gap. Walk your
      character onto the pad from outside the plot ring and confirm nothing blocks the approach
      and the level-up prompt still triggers from the pad.
- [ ] 14. Confirm the extra width doesn't overlap an adjacent slot's footprint or pad at any
      stage — the Stadium is the only slot that could, so check its two neighbours specifically.

### 6. Grow one building through all five stages

- [ ] 15. Use `GrantCash` and the ×1/×10/Max buttons to level the **Hotel Tower** from 0 to level
      10, then 25, then 50, then 100. Confirm one growth pop + one milestone sound at each
      crossing (not two, not zero — same check as M7 section 4), the model visibly grows taller
      and more built-up at each stage, and it never flashes back to a smaller stage.
- [ ] 16. Confirm the Build panel's growth hint line updates/merges the same way it did for
      Village and Boomtown (M7 section 4, step 12).

### 7. Skyline check — price order reads as height

- [ ] 17. Level the **Broadcast Tower** and the **Bank Tower** to 100 as well (the Skyscraper is a
      monument, single stage). Stand well back from the plot and compare heights by eye. Confirm
      the order, tallest to shortest: **Skyscraper** (35.6 studs) > **Broadcast Tower** (28.6) >
      **Bank Tower** (21.5) > **Hotel Tower** (18.8) > **Office Tower** (16.3).
- [ ] 18. Confirm the **Skyscraper visibly crowns the plot** — it must be unmistakably the tallest
      thing from every angle, not merely tied with the Broadcast Tower's mast. No cheaper slot
      should out-top a more expensive one.

### 8. Metropolis must not look like Boomtown

- [ ] 19. Look at the plot as a whole and confirm it reads as a **city centre**: shops, offices and
      towers, glass and concrete, things stacked upward. Boomtown is the "lower, wider" era —
      ordinary slots capped around 13 studs, with only the Fire Station (18.7), Radio Station
      (21.3) and Clock Tower (25.8) going higher. Metropolis's ordinary slots should read
      noticeably taller and denser than that.
- [ ] 20. If another player (or a second Local Server client) is on a Boomtown plot, compare the
      two plots side by side from the hub and confirm you can tell the eras apart at a glance.
      Otherwise compare against your memory of the M8 Boomtown pass — a Metropolis plot that
      looks like suburban houses and low industrial sheds is the failure this step is hunting.

### 9. City dressing — **superseded by M9 wave 2a (2026-09-22)**

- [ ] 21. **Stale step, skip it.** Metropolis now has a street plan and 21 props, so a Metropolis
      plot is *meant* to show tile streets, pavements, a highway, kiosks, trees and cars. Test all
      of that in "M9 — City dressing" **sections 4c and 4d** instead; this step only applies to a
      build from before 2026-09-22.
- [ ] 22. If you have a second player (or a spare save) on a **Village or Boomtown** plot, confirm
      their dressing still appears normally — Metropolis's content must not have disturbed M9
      wave 1.

### 10. VIP skins

- [ ] 23. If you don't already own the `VIP` pass on this profile, buy it now (Shop panel, same
      flow as M4 section 3 / M7 section 5).
- [ ] 24. With VIP owned, walk the plot and confirm Metropolis buildings show the recoloured
      gold-tinted skin. The new swatch this wave is **`city-kit-commercial`**; the era also uses
      `city-kit-roads` and `city-kit-suburban` pieces, whose swatches came from Boomtown — so
      check a tower body (commercial), the **Build the Highway Ramp** unlock (roads), and the
      **City Park** decor (suburban/roads). It should look like a colour swap, not a different
      model. If you just bought VIP mid-session, confirm it applies without a rejoin.

### 11. Mobile emulation pass (required every milestone)

- [ ] 25. Device Emulator, **375×667** portrait. Walk the plot and open the Build panel. Confirm
      the growth hint text and button layout haven't regressed from M7/M8's mobile passes, and
      that the plot renders sensibly at this resolution — in particular that the tall towers
      (Skyscraper, Broadcast Tower) don't clip the camera or push the UI off-screen when you
      stand next to them.
- [ ] 26. Stop Play.

### What a bug looks like here

- Any slot showing a grey/untextured mesh, a red error in Output, or a mesh at the wrong scale.
- A building that doesn't read as the thing its Build-panel row names.
- A building not facing its pad, floating, sunk, or badly clipping a neighbouring slot.
- The Skyscraper not at the front of the plot, not facing arriving players, or not the tallest
  thing on the plot.
- **Stadium:** the pitch hidden or roofed over at any stage, stands growing across the front,
  floodlights standing on the ground, or the buy pad unreachable/unwalkable.
- Stadium's 12×12 footprint overlapping a neighbouring slot's footprint or pad.
- Two pops or zero pops at a milestone crossing, or a milestone sound firing more than once.
- Skyline order broken — any cheaper slot taller than a more expensive one.
- The plot reading as Boomtown (low, wide, suburban) instead of a tall commercial city centre.
- Any error or warning in Output about missing Metropolis dressing/props/paths (their **absence**
  is expected; a complaint about it is not).
- VIP showing a different-shaped model instead of a texture/colour change, or not applying live.

### Sign-off

- [ ] 27. All boxes above checked: reaching Metropolis, all 24 slots buying in as real meshes, a
      full plot placement walk including the Skyscraper's position, the Stadium's own pass
      (pitch visible at every stage, stands at the back, roof-mounted floodlights, walkable pad),
      a full 0→100 growth run on the Hotel Tower, the skyline order, the Metropolis-vs-Boomtown
      read, dressing confirmed absent and silent, VIP skins, and 375×667 mobile emulation.
- [ ] 28. Tell Claude Code "M8 Metropolis assets playtest passed" (or report the exact failure and
      step number).

---

## M8 — Growing buildings (Orbital Colony)

**Goal:** all 24 Orbital Colony slots have real meshes — the **last era**, so after this pass every
era in the game (4 eras / 96 models) is built. Same pipeline as M7 Village and M8 Boomtown and
Metropolis, from `space-kit` plus a **generated `orbital-kit`** (21 pieces space-kit doesn't have:
domes, tanks, solar panels, flag, holo beacon, mast, drill rig, lit window strips, pad markings).
This section assumes M7 and the earlier M8 passes already ran — it doesn't re-explain the
`GrantCash` lever, growth pops, VIP-as-texture-swap or the missing-config degrade; it re-checks
them briefly and spends the time on the four things that are new here: **a near-black plot**,
**three 12×12 landmarks plus a 12×9 Rover Bay**, **the Launch Tower silhouette**, and **the
space-kit palette fix**.

**No Luau or config logic changed this wave** (content only), so there is no two-player pass in
this section — M7 section 10 already covers stage replication across clients.

**Expect a bare plot — Orbital Colony city dressing does not exist yet.** Streets, paths, props,
trees and vehicles for this era are **M9 wave 2b**, not started. Village, Boomtown and Metropolis
have dressing; an Orbital plot is buildings, buy pads and regolith, nothing else. Missing paths and
props here are **not a bug** — see section 10.

**Reference renders** (open these alongside Studio and compare as you go):
`assets/testfit/out/OrbitalColony/_contact_OrbitalColony.png` (white card) and
`assets/testfit/out/OrbitalColony/_contact_OrbitalColony_dark.png` (**the dark-plot sheet — the one
that matches what you'll see in Studio**).

### 1. Rebuild first

- [ ] 1. `$env:PATH = "$HOME\.rokit\bin;$env:PATH"` (PowerShell) then
      `rojo build -o build/test.rbxl` (or reconnect `rojo serve`). Regenerate the sourcemap
      before any `luau-lsp analyze` run: `rojo sourcemap default.project.json -o sourcemap.json`.
- [ ] 2. Confirm **"Enable Studio Access to API Services"** is still ON (Game Settings →
      Security).
- [ ] 3. In Edit mode, confirm `ServerStorage.Assets.OrbitalColony` has **24 models**, each with
      `Stage0`…`Stage4` (a single `Stage0` for the `unlock`/`decor`/`monument` slots: WalkwayTube,
      OxygenTanks, SatelliteDish, TurretBase, ColonyFlag, RocksLarge, HoloBeacon, LaunchTower),
      and that their mesh previews are **textured**, not grey.

### 2. Reach the Orbital Colony

- [ ] 4. Press Play. Use the `GrantCash` Workspace attribute (M7 section 2 — select Workspace,
      Properties → Attributes → **+**, name `GrantCash`, type **number**) to buy out whatever era
      the save is in and advance until the era badge reads **"ERA 4" / "Orbital Colony"**.
- [ ] 5. Confirm the advance ceremony plays, the plot base recolors to the **near-black regolith**
      (RGB 56, 53, 60), and the Build panel rebuilds to 24 fresh Orbital Colony rows — all locked
      except the free first slot (**Landing Pad**, cost 0).

### 3. Buy every slot — meshes, no placeholders

- [ ] 6. Orbital prices run into the **quadrillions** (buying out the era costs about 2,346T, the
      Launch Tower alone 460T). Set `GrantCash` to `3000000000000000` (3 quadrillion) in one go
      rather than topping up per slot; re-add it as needed.
- [ ] 7. In the Build panel, buy all 24 slots in the order listed (Landing Pad → Solar Array →
      Habitat Pod → Hydroponics Dome → Oxygen Generator → Connect the Walkways → Crew Quarters →
      Colony Flag → Research Lab → Rover Bay → Comms Array → Bring Life Support Online →
      Mineral Extractor → Rock Garden → Observation Dome → Fusion Reactor → Establish the Orbital
      Uplink → Docking Bay → Terraform Station → Holo Beacon → Medical Bay → Spaceport Terminal →
      Raise Planetary Defense → Launch Tower).
- [ ] 8. As each one appears, confirm it's a **textured stage-0 mesh** that reads as the thing its
      row is named — no grey/untextured box, no floating placeholder label, no red error in
      Output. Same check as M7 section 3 and the Boomtown/Metropolis section 3s.

### 4. Walk the plot — placement sanity

- [ ] 9. The layout is a **radial colony**: the Fusion Reactor is the core at plot centre, habitat
      and science modules orbit it in two rings all facing inward, rim installations guard the
      edge, and the Launch Tower flanked by the Spaceport Terminal and Medical Bay greets arriving
      players at the front. Walk the whole plot at a few angles and confirm it reads that way.
- [ ] 10. Confirm: every model faces its buy pad, no piece floats above the ground, nothing sinks
      into the regolith, and no building clips into a neighbouring slot's footprint or pad.
- [ ] 11. Confirm the **Launch Tower** (monument, last slot) sits at the front of the plot facing
      arriving players — the same role the Castle Keep plays in Village, the Clock Tower in
      Boomtown and the Skyscraper in Metropolis.

### 5. Reading against a near-black plot (this era's own risk)

The regolith base is RGB (56, 53, 60) — darker than any other era's plot, so anything dark or
low-contrast can disappear into it. Every model was signed off on the **dark** contact sheet; this
section confirms that survived into Studio.

- [ ] 12. Stand back and look at the plot as a whole. Confirm **nothing reads as a hole in the
      ground** — every building has a silhouette you can pick out against the base.
- [ ] 13. **Solar Array** (slot 2, 6.4 studs — the shortest *building* on the plot): confirm the
      **navy panels** are visibly distinct from the regolith under them, both from standing height
      and from a low camera angle. Panels vanishing into the base are the single most likely
      failure in this section.
- [ ] 14. **Rock Garden** (`RocksLarge`, 3.2 studs — the shortest thing on the plot): confirm the
      **salmon/orange rocks** read as objects sitting on the ground, not as a texture patch in it.
- [ ] 15. **Landing Pad** and every other **pad marking** (the orbital-kit pad-marking piece, also
      used around the Docking Bay and the Launch Tower): confirm the markings are legible from a
      walking camera, not washed out into the base.
- [ ] 16. Compare what you see against `_contact_OrbitalColony_dark.png`. Studio should look like
      that sheet. If Studio is noticeably flatter or darker than the sheet, note which model and
      report it — that's a real finding, not a rendering nitpick.

### 6. The wide slots — three 12×12 landmarks and the 12×9 Rover Bay

Four slots exceed the standard 9×9 footprint this era (`docs/INTERFACES.md`, Blueprints):
**Fusion Reactor**, **Terraform Station** and **Spaceport Terminal** at `scale 3.6` with
`[12, 12]` (space-kit's hex and long hangars are 12–13 studs at scale 4.0 and fit nothing
smaller), and **Rover Bay** at `[12, 9]` (the kit's only garage fills 8 of 9 studs; depth stays 9
so the buy pad is untouched). The tightest neighbour gaps anywhere on this plot are 13.4 studs
(Colony Flag ↔ Mineral Extractor) and 17.2 studs (Rover Bay ↔ Holo Beacon), so there **is** room —
this section proves it.

- [ ] 17. Level each of the four to **100** (`GrantCash` + the ×1/×10/Max buttons) before checking
      — a footprint only bites at stage 4.
- [ ] 18. **Fusion Reactor** (plot centre): walk a full lap around it. Confirm you can walk between
      it and each of its nearest neighbours (Landing Pad, Solar Array, Oxygen Generator, Crew
      Quarters — all ~19.8 studs out) without getting stuck, and that it touches none of their
      pads.
- [ ] 19. **Terraform Station** (back-left ring): same lap. Its nearest neighbour is the Orbital
      Uplink at ~19.8 studs — confirm a walkable lane between them.
- [ ] 20. **Spaceport Terminal** (front-right, beside the monument): confirm it does **not** touch
      the Launch Tower ~18.9 studs away, and that you can still walk between the two.
- [ ] 21. **Rover Bay** (back-left, `[12, 9]`): confirm the extra **width** doesn't reach the Holo
      Beacon (~17.2 studs) or the Colony Flag (~18 studs), and that its depth still leaves its pad
      clear.
- [ ] 22. **Buy pads on all four:** walk your character onto each pad from outside the plot ring.
      Confirm nothing blocks the approach, you can stand on the pad, and the level-up prompt still
      triggers from it. (Pads sit `padOffset` **8** studs off the front face this era.)

### 7. Grow one building through all five stages

- [ ] 23. Use `GrantCash` and the ×1/×10/Max buttons to level the **Research Lab** from 0 to level
      10, then 25, then 50, then 100. Confirm one growth pop + one milestone sound at each
      crossing (not two, not zero — same check as M7 section 4), the model visibly grows taller and
      more built-up at each stage, and it never flashes back to a smaller stage.
- [ ] 24. Confirm the Build panel's growth hint line updates/merges the same way it did for the
      earlier eras (M7 section 4, step 12).

### 8. Skyline check — the Launch Tower crowns the colony

- [ ] 25. Level the **Terraform Station** and the **Comms Array** to 100 as well. Stand well back
      and compare heights by eye. Confirm the order, tallest to shortest: **Launch Tower**
      (42.8 studs, monument, single stage) > **Terraform Station** (23.0) > **Comms Array** (21.2)
      > **Fusion Reactor** (16.9) ≈ **Spaceport Terminal** (16.5).
- [ ] 26. From the **plot entrance** (where you arrive, at the front/−Z edge), confirm the **Launch
      Tower's rocket is unobstructed** — nothing in front of it, and nothing tall enough beside it
      to compete. It clears the next-tallest building by nearly 20 studs, so it must be the
      unmistakable landmark of the final era from every angle.

### 9. Kit colours — the palette fix (check this deliberately)

space-kit's glTF colour factors turned out to be **sRGB-encoded, not linear**, so the baked palette
swatches came out pale until `palette.py` was fixed this wave. This step verifies the fix reached
the actual uploaded textures.

- [ ] 27. Look at the orange trim across the colony (Habitat Pod, Crew Quarters, Docking Bay, the
      Launch Tower's markings). Confirm it is **saturated Kenney orange (255, 160, 52)** — not a
      pale, washed-out amber. Darks should read as slate (70, 76, 87), not grey mush.
- [ ] 28. Compare against `_contact_OrbitalColony.png` and `_contact_OrbitalColony_dark.png`.
      Studio colours should match the sheets. Pale amber anywhere means the fix didn't reach that
      asset — report the model name.

### 10. City dressing — expected absent (M9 wave 2b)

**Superseded 2026-09-23:** M9 wave 2b now dresses the Orbital Colony. Skip steps 29–30 and run
`M9 — City dressing` sections 4f and 4g instead.

- [ ] 29. (superseded) Confirm the Orbital plot has **no** streets, paths, trees, plazas, lamps or vehicles, and
      that Output is **silent about it** — no warning, no error, no red line about missing Orbital
      props or paths. Their absence is by design until M9 wave 2b; a *complaint* about their
      absence is a bug.
- [ ] 30. If you have a second player (or a spare save) on a **Village, Boomtown or Metropolis**
      plot, confirm their dressing still appears normally — Orbital content must not have disturbed
      M9 waves 1 and 2a.

### 11. VIP skins

- [ ] 31. If you don't already own the `VIP` pass on this profile, buy it now (Shop panel, same
      flow as M4 section 3 / M7 section 5).
- [ ] 32. With VIP owned, walk the plot and confirm Orbital buildings show the recoloured skin.
      **Two new swatches shipped this wave** — one for `space-kit`, one for the generated
      `orbital-kit` — so check both: a space-kit body (**Habitat Pod**, **Docking Bay**) and an
      orbital-kit subject (**Solar Array** panels, **Colony Flag**, **Holo Beacon**). It should
      look like a colour swap, not a different model, and **both** kits should change — a building
      where only part of the mesh recolors means one swatch is missing. If you just bought VIP
      mid-session, confirm it applies without a rejoin.

### 12. Mobile emulation pass (required every milestone)

- [ ] 33. Device Emulator, **375×667** portrait. Walk the plot and open the Build panel. Confirm
      the growth hint text and button layout haven't regressed from the earlier passes, and that
      the plot renders sensibly at this resolution — in particular that the **Launch Tower** doesn't
      clip the camera or push the UI off-screen when you stand at its base, and that the dark plot
      doesn't crush the low models (Solar Array, Rock Garden) into the background at phone
      brightness.
- [ ] 34. Stop Play.

### What a bug looks like here

- Any slot showing a grey/untextured mesh, a red error in Output, or a mesh at the wrong scale.
- A building that doesn't read as the thing its Build-panel row names.
- A building not facing its pad, floating, sunk into the regolith, or clipping a neighbour.
- **Anything that disappears into the near-black plot** — especially the Solar Array's navy panels,
  the Rock Garden's rocks, or pad markings.
- **Wide slots:** a 12×12 landmark or the 12×9 Rover Bay overlapping a neighbour's footprint or
  pad, blocking the walkable lane between rings, or making its own buy pad unreachable.
- The Launch Tower not at the front, not facing arriving players, obstructed from the entrance, or
  not clearly the tallest thing on the plot.
- Skyline order broken — any cheaper slot taller than a more expensive one.
- **Pale, washed-out amber instead of saturated orange** — the palette fix didn't reach that asset.
- VIP recoloring only part of a building (one of the two swatches missing), showing a
  different-shaped model instead of a colour change, or not applying live.
- Any error or warning in Output about missing Orbital dressing/props/paths (their **absence** is
  expected; a complaint about it is not).

### Sign-off

- [ ] 35. All boxes above checked: reaching Orbital Colony, all 24 slots buying in as real meshes,
      a full plot placement walk including the Launch Tower's position, the dark-plot contrast
      pass, the four wide slots' own pass (walkable lanes and pads), a full 0→100 growth run on the
      Research Lab, the skyline order and the unobstructed rocket, the orange/slate palette check,
      dressing confirmed absent and silent, VIP on both new swatches, and 375×667 mobile emulation.
- [ ] 36. Tell Claude Code "M8 Orbital Colony assets playtest passed" (or report the exact failure
      and step number). That closes **M8 — every era now has real buildings**.

---

## M9 — City dressing (roads, trees, filler, squares, vehicles)

**Goal:** plots read as a growing town, not 24 buildings on a lawn — roads connect what you own,
trees grow with the city, filler houses and a square fill the gaps, and a few vehicles move along
the roads. Everything here is **client-side cosmetics**: the server only publishes `EraName` and
`GrowthTier` (0–5) attributes; nothing about it is persisted or validated, so two players can see
different vehicle positions on the same plot and that's fine. `docs/BALANCE.md` "M9 — City growth
tiers" has the tier-timeline numbers if you want to cross-check pacing.

**Before you start:** the M9 pipeline steps in `docs/MANUAL_STEPS.md` "M9 — City dressing" are
already done (props harvested 2026-09-16; baked paths for Village + Boomtown harvested and
templated 2026-09-18) — you only need a rebuild. If `templates/_props` is missing, every prop
(trees, houses, plaza, vehicles) is silently absent; if `templates/_paths` is missing, paths fall
back to the old Pebble Parts trail. Both are the designed degrade, not a bug (sections 12 and
steps 5e–5f).

**Paths are baked meshes (wave 1d).** After four Studio rounds Ben approved the "C3" recipe:
uploaded, world-planar-UV, fully opaque meshes, one Model per piece, cloned by the client.
EditableMesh/EditableImage are **banned in this project**, so nothing here needs ID verification or
a Creator Dashboard toggle.

**Wave 1e — street upgrades (section 4b).** Pave the Road, Pave Main Street, Streetlamp Row and
Install Traffic Lights change the streets. Their props and surface textures were harvested
2026-09-18, so nothing is owed: just rebuild and run section 4b.

**Wave 2a — Metropolis streets, highway, subway (section 4c).** Its two harvest pastes were done
2026-09-22. Metropolis uses **kit tile streets** (7-stud `city-kit-roads` tiles), not baked paths,
plus an elevated ring highway, subway kiosks and a real City Hall.

**Wave 2a fix round (section 4d).** Its two pastes were done 2026-09-22 — nothing owed.

**Wave 2a third round (section 4e).** Its two pastes were done 2026-09-23 — nothing owed.

**Wave 2b — Orbital Colony + City detail (sections 4f and 4g).** Its props paste was done
2026-09-23 (16 records) — nothing owed. Section 4g (City detail) needs no assets.

**Wave 2c — living city (section 4h).** Its props paste was done 2026-09-23 (48 records) —
nothing owed. More houses, greenery, parked cars, more traffic, walkers, chimney smoke and bird
flocks in Village, Boomtown and Metropolis, all growing with `GrowthTier`. It also **moves a few
approved Boomtown things** (lamp and signal offsets, five ring lots, tree zones) — steps 12cz–12dc.

**What changed in the third round:** park strips (grass + planters) fill every planned street cell
that has **not** grown yet, so no more dead-end sidewalk beside bare ground; the highway is a
box-girder deck on piers; the parking garage grows lot to four decks; City Hall is kit-only.

**One change touches every era.** Roblox's glTF import turns every model 180° about Y; the
template generator now compensates for **buildings and props**, not just paths. So after this
rebuild **every building in every era faces its buy pad**, props sit as authored, and Boomtown cars
drive nose-first. Spot-check it in **section 4d steps 12ah–12aj** — if a building's back faces its
pad, that is the bug to report.

### 1. Rebuild first

- [ ] 1. `$env:PATH = "$HOME\.rokit\bin;$env:PATH"` (PowerShell) then
      `rojo build -o build/test.rbxl` (or reconnect `rojo serve`). Regenerate the sourcemap before
      any `luau-lsp analyze` run: `rojo sourcemap default.project.json -o sourcemap.json`.
- [ ] 2. Confirm **"Enable Studio Access to API Services"** is still ON (Game Settings →
      Security).

### 2. Growth tiers on a fresh Village plot

- [ ] 3. Press Play on a fresh save. Before buying anything, select your plot in Explorer
      (`Workspace/Plots/Plot_<n>`, `<n>` matches your `PlotIndex` — check your player's
      Attributes if unsure) and open its **Attributes**. Confirm `GrowthTier` reads `0` and
      `EraName` reads `Village`. Walk the plot: bare ground, no roads, no trees, no houses.
- [ ] 4. Buy the first (free) slot. Within a second or two confirm `GrowthTier` ticks up to `1` on
      the plot's Attributes, and a narrow (about 3-stud) **pebble trail** runs out from *under* the
      new building, across its pad, and back along the shortest route to the plot entrance at the
      front-west gap. No other road is drawn yet: roads only exist where an owned building needs
      them (wave 1b).
- [ ] 5. Add the `GrantCash` Workspace attribute (same lever as M7/M8 — Workspace → Attributes →
      **+** → `GrantCash`, type number, a large value) and use the Build panel's ×1/×10/Max
      buttons to buy and level slots. Re-check `GrowthTier` after a few buys/levels — it should
      keep climbing (never jump backward) as you re-add `GrantCash` and spend it. Push it all the
      way to `5`. (Pacing note: per `docs/BALANCE.md`, a *real* greedy playthrough reaches tier 5
      around minute 36 of Village — `GrantCash` is what makes this a two-minute check instead.)

- [ ] 5b. **Baked paths — the look** (wave 1d; Village plot at tier 3+, standing on it). Paths are
      baked meshes cloned from `ReplicatedStorage/Assets/Paths/Village`, one Model per piece:
      - Drop the camera to **ground level** at a spot where a building's path meets a lane, and
        again at a lane corner. Confirm **one continuous dirt surface**: no seam line, no flicker,
        no darker bar running across the mouth of a path where it joins.
      - The dirt is **flat stylised pebbles, clearly lighter than the grass**, with a **wobbly,
        irregular edge** (not a straight-sided band) and a slightly **darker rim** hugging both
        sides.
      - Every building path runs out from **under its building** across the pad; the main lane
        stays **full width at the plot entrance** (no taper, no cap there).
      - Orbit the camera a full circle around a junction: no z-fighting or shimmer where two
        pieces overlap.
      - Carts (from tier 2) drive along the trail; no tree sits on one.
- [ ] 5c. **Buying a building — rim, then fill, then dust.** Stand on the plot, `GrantCash`, buy an
      unowned slot and watch its new path:
      - The **rim outline appears first**, the dirt **fill lands about 0.15 s later**
        (`paths.rimLeadSeconds`), and a **dust puff travels** from the lane end to the building
        over about 0.8 s (`paths.dustSeconds`).
      - **Nothing else on the plot flickers**: existing paths, trees, cottages and the plaza must
        not blink, rebuild or move, and a moving cart must not jump.
      - Buy two slots within a second of each other: both appear, one dust burst crosses them, and
        no cloud is left hanging afterwards.
      - In Explorer, `Workspace/CityDressing/Plot<n>/PathDust` (a ParticleEmitter on an invisible
        part) has **`Enabled` false** once the burst ends.
      - Rejoin the save and confirm the same paths come back **instantly, with no dust** — the
        effect is for purchases only.
- [ ] 5d. **Renderer attribute.** In Explorer select `Workspace/CityDressing/Plot<n>` (no
      underscore) → Attributes: `PathRenderer` reads **`baked`** on Village and Boomtown plots. Its
      children include one Model per visible piece, named `L<n>_<n>` (lane stretches) and
      `SP_<slotId>` (building paths), each holding a `Rim` and a `Fill` MeshPart.
- [ ] 5e. **Forced parts renderer.** Edit `src/shared/Config/CityDressing.json` → `road.renderer`
      from `"auto"` to `"parts"`, rebuild, Play. Confirm the attribute reads **`parts`**, the old
      Pebble-Part trail draws instead (visibly rougher, segmented), the game plays normally, and
      **Output shows zero errors**. Restore `"auto"` and rebuild before continuing.
- [ ] 5f. **Missing-template fallback (silent).** Two ways; do at least one:
      - *Explorer, Edit mode before Play:* rename `ReplicatedStorage/Assets/Paths/Village` to
        `Village_bak` (whole era), **or** rename a single piece inside it, e.g. `L1_1` → `L1_1_bak`.
      - *On disk:* rename the folder `templates/_paths` to `templates/_paths_bak` and
        `rojo build -o build/test.rbxl` again (the Rojo mapping is optional, so the build still
        succeeds).
      Press Play and buy a slot. Confirm the plot **silently drops to the Pebble Parts trail**
      (attribute flips to `parts`), everything else is unaffected, and **Output has zero errors**.
      (A renamed era folder falls back the moment the plot dresses; a single renamed piece falls
      back the moment that piece would be drawn — on join if it is already visible, otherwise on
      the purchase that needs it.) Restore the name and rebuild.

### 3. Tier 5 Village — the full look

- [ ] 6. With `GrowthTier` at `5` and your plot **near** the camera (stand on it), confirm: a
      network of pebble trails connects every owned building (each path starts under its
      building), with no road running anywhere no building needs it, up to
      **40 trees** are scattered around the plot (some short/young, some tall/full — trees grow in
      stages as the tier rises, so don't expect all 40 at full height if you just jumped to tier 5
      quickly), a few **filler cottages** sit along the roads that are not buy-pad buildings, one
      **plaza** (small square/gathering-spot prop), and **two carts** are visibly moving along the
      roads.
- [ ] 7. Watch a cart for 10–15 seconds: confirm it moves continuously along the road network and
      turns (not just at the same spot), and that it never clips through a building.

### 4. Boomtown — asphalt, kerbs, cars

- [ ] 8. Get a plot to Boomtown (Advance Era from a completed Village plot, or rebirth — same as
      M8 section 2) and repeat the `GrantCash` push to `GrowthTier` 5.
- [ ] 9. Confirm the streets are **baked meshes**, not dirt and not Parts: `PathRenderer` reads
      `baked`. **Wave 1e:** they are **gravel** (pale grey-brown, no kerb) until **Pave Main
      Street** is owned, and grey asphalt with a **lighter concrete kerb** rim after it — buy it now
      if you want the asphalt for this step. Walk a T-junction and a corner at ground-level camera:
      one road, **no seam, no gap, no z-fighting** where pieces overlap. **There are no kit
      junction/bend tiles in Boomtown any more** (wave 1d ruling: a kit tile's own texture cannot
      match the planar asphalt); seeing one is a bug.
- [ ] 10. Confirm **no lamp posts at any tier** until **Streetlamp Row** is owned (wave 1e replaced
      the old tier-3 rule for Boomtown — lamps at tier 3 without that slot is now a bug), and that
      up to **four cars** (not carts) move along the roads. Lamps themselves are section 4b.
- [ ] 11. Walk down **main street** (the road running through the middle of the plot, x = 0):
      confirm the spine passes directly over the **Pave Main Street** and **Streetlamp Row**
      slots — those two are road-piece buildings that sit *on* the road itself, so the road should
      run through/over them, not curve around them. It also runs under the **Clock Tower** and
      **Fire Hydrant** (amendment P3), so the tower stands in the middle of main street.
- [ ] 12. Confirm **Bank**, **Radio Station**, **Pave Main Street**, **Streetlamp Row**, **Clock
      Tower** and **Fire Hydrant** have
      **no driveway spur** connecting them sideways to the street (they sit directly against/on
      the road already) — every other owned building should have its own short spur.

### 4b. Wave 1e — street upgrades (buy the slot, the street changes)

Four slots that used to be names now change the streets. All client-side: nothing here is
persisted or validated, so nothing in this section can break the economy. Its harvest paste is
already done (`docs/MANUAL_STEPS.md` "M9" §7), so a rebuild is all you need. Use `GrantCash` as
everywhere else.

**Village — Pave the Road (`dirtRoad`)**

- [ ] 12b. On a Village plot with several buildings but **Pave the Road not yet owned**: trails are
      **dirt** and there are **no lanterns** anywhere.
- [ ] 12c. Buy **Pave the Road**. In one go: **every trail on the plot turns cobble** (all of it, not
      piece by piece), **one cobble-coloured dust puff** runs along every visible trail, and
      **lanterns** appear along the drawn spine trails. Nothing else on the plot flickers, rebuilds
      or moves, and a moving cart must not jump.
- [ ] 12d. Count the lanterns on a fully grown plot: expect **about 15** (roughly 11 on the main
      lane, 1 campsite lane, 1 farm track, 2 cottage lane) and **never more than 16**
      (`budget.lampPosts`). Every trail should have some — all 15 bunched on the main lane with the
      side trails dark is the bug this count is hunting.
- [ ] 12e. Buy another slot now. Its new trail arrives **already cobbled** (rim, then fill, then
      dust as in step 5c — no second plot-wide puff) and any lantern that belongs on it appears with
      it.
- [ ] 12f. Look at two or three lanterns up close: each stands **clear of the trail edge** (not in
      it, not floating away from it), they alternate sides, and none sits inside a building
      footprint, buy pad, lot or plaza. Levers if the spacing or the gap is wrong:
      `src/shared/Config/CityDressing.json` → `eras.Village.lamps.offset` (1.2) and `spacing` (16).
- [ ] 12g. Judge the lantern itself: **4.98 studs tall** — roughly your avatar's height (5 studs) —
      a thin post with a lamp head. If it reads too spindly or too chunky, the lever is
      `"scale"` in `tools/testfit/blueprints/_props/Village/Lantern.json` (3.2 today) — that's a
      re-render/re-upload, so just report the judgement.

**Boomtown — Pave Main Street, Streetlamp Row, Install Traffic Lights**

- [ ] 12h. On a **fresh** Boomtown plot (advance or rebirth into it, before buying road slots):
      streets are **gravel**, and **not for a single frame asphalt** — watch the plot as it first
      dresses, and again right after a rejoin. Asphalt flashing before gravel is a bug.
- [ ] 12i. Buy **Pave Main Street**. Every street turns **asphalt with the concrete kerb**, in one
      go, with one dust puff. Buy a further slot: its new street arrives already asphalt.
- [ ] 12j. Buy **Streetlamp Row**. Lamp posts appear along the **drawn** streets — expect about
      **8** (spacing 24, offset 0.8), standing clear of the kerb, alternating sides. Before this
      slot there were none, at any tier (step 10).
- [ ] 12k. Buy **Install Traffic Lights**. Expect a traffic light at every **drawn** crossing: the
      entrance T (0, −54.5), the four-way on main street (0, −42), and the ring T-junctions at
      (−51, −22), (−51, −2), (51, −2), (51, 29.5) — six on a fully grown plot (cross streets added
      2026-09-18). A crossing lights only once two of its streets are drawn, so the east pair
      arrives around tier 5. The slot itself spawns no model (`streetOnly`).
      Check the head: it stands on the corner outside both kerbs, about **4.6 studs** tall, and the
      lens faces the road rather than the pavement.

**Both eras — the checks that catch the client-only mistakes**

- [ ] 12l. **Another plot / another player.** Test → Start with **2 Players** (Local Server). Have
      Player 1 buy one of the four upgrades while Player 2 watches that plot. Player 2 must see the
      **same surface, the same lanterns/lamps and the same signal**. A remote viewer far from the
      plot may get it without the dust puff — expected; a different surface or missing posts is not.
- [ ] 12m. **Rejoin.** Stop, Play again on the same save. Upgrades come back **instantly**: cobble
      (or asphalt) already on, lanterns/lamps/signal already there, and **no dust puff** — the puff
      is for the moment of purchase only.
- [ ] 12n. **Near/far.** Walk or fly out past **~290 studs** and back. Lanterns, lamps and the
      traffic light drop with the other near-only dressing and come back; the **surface itself never
      reverts, blinks or re-lays** in either direction.
- [ ] 12o. **Forced parts renderer.** Edit `src/shared/Config/CityDressing.json` →
      `road.renderer` `"auto"` → `"parts"`, rebuild, Play. Confirm the Parts trail takes the
      variant's own look — Village after Pave the Road is **Cobblestone**, a Boomtown plot before
      Pave Main Street is **Ground** (pale grey-brown) — and that buying an upgrade repaints the
      roads **without vehicles respawning or jumping**. Output must show zero errors. Restore
      `"auto"` and rebuild.
- [ ] 12p. **Missing prop degrade.** In Edit mode rename
      `ReplicatedStorage/Assets/Props/Village/Lantern` to `Lantern_bak`, Play, buy Pave the Road.
      The trails still turn cobble, **no lanterns** appear, and **Output has zero errors**. Rename
      back. (The same is true of `Boomtown/TrafficLight`, and of a variant whose textures were
      never harvested: the surface silently stays the default.)

### 4c. Wave 2a — Metropolis streets, highway, subway

Metropolis is the only era with **kit tile streets**: 7-stud `city-kit-roads` tiles, four per
28-stud block, instead of baked path meshes. Three slots changed meaning — **Found City Hall**
(was "Lay the City Grid", same slot id, so an old save keeps its ownership), **Build the Highway
Ramp** and **Dig the Subway Line** (both now draw infrastructure and spawn **no building**). All
client-side; nothing here can break the economy.

**Do `docs/MANUAL_STEPS.md` "M9" §10 (two harvest pastes) before this section.** §8's and §9's
pastes are already done.

- [ ] 12q. **Reach Metropolis.** `GrantCash` `10000000000000` (10T), buy out the current era and
      advance until the badge reads **"ERA 3" / "Metropolis"** (same as PLAYTEST "M8 — Metropolis"
      section 2). Before buying anything, walk the plot: **bare ground** — no streets, no
      pavements, no highway, no kiosks — and `GrowthTier` reads `0`.
- [ ] 12r. **First purchase — one street, one footpath.** Buy the free **Food Truck**. Confirm: a
      run of **tile cells** runs from the plot entrance to the building; the cell at the far end is
      a **dead-end tile** (closed on three sides, not a straight piece hanging in the air); a
      **concrete pavement** strip runs along **both** sides of the street; and a narrow concrete
      **footpath** joins the building to the street and **stops at the pavement edge** — it must
      never lie on top of the asphalt (that overlap was a bug fixed in review).
- [ ] 12r2. **Pavement is per cell (fixed this round).** Walk the drawn street and look down:
      pavement appears **only on a cell's closed sides**, a bend gets a **corner square** on its
      outside, the **dead end is closed with a U**, and a **crossroads cell is bare** — pavement
      on all four sides. **No pavement may lie over asphalt anywhere.** A strip crossing a road
      mouth, a gap at a bend, or concrete on top of a tile is the bug to report.
- [ ] 12s. **Streets grow — watch the tile kinds change.** Keep buying with `GrantCash` and watch
      one junction cell in particular. As the network reaches it, its tile changes **end →
      straight → tee → cross**. A cell that changes kind **swaps in place with no dust puff**; a
      brand-new cell **drops in with a dust puff**. Nothing else on the plot may flicker or
      rebuild, and a moving car must not jump.
- [ ] 12t. **Zebra crossings.** Where a street runs **3 or more cells** into a tee/cross, the cell
      next to the junction is a **striped crossing tile**. Expect these at the avenue/arterial
      junctions once those streets are drawn. Purely cosmetic: a missing one is a bug only if the
      run is clearly ≥ 3 cells long.
- [ ] 12u. **Cars keep to their lane.** Up to **four** street cars drive the network. Two cars
      passing in opposite directions must stay on **their own side** of the 7-stud tile (they are
      scaled down to 1.8 so two 2.7-stud bodies fit on 5.6 studs of asphalt) — bodies overlapping
      the centreline is a bug. **No car ever drives the x = 0 civic axis** (entrance avenue → City
      Hall → Skyscraper): that corridor is car-free by design. **Every car drives nose-first** —
      windscreen leading, boot trailing. A car driving backwards means the template turn fix did
      not land (rebuild first, then report).
- [ ] 12v. **Found City Hall (rebuilt kit-only in the third round).** Buy it. Confirm a **white
      civic block** — three bays, a **canopy over the entrance**, **three flag masts**, planters
      and lamps, about **12.3 studs** tall — appears at the plot **centre**, facing back down the
      civic axis toward the plot entrance, with its **buy pad in front of it** and **no street cell
      underneath it**. A grey box, a road tile or nothing at all means the `CityHall` harvest paste
      (MANUAL §10 step 37) did not land. The old dome version is gone on purpose (you called it
      "way too big, way off, ugly").
- [ ] 12v2. **City Hall from the entrance.** Walk to the **plot entrance** and look up the civic
      axis: the hall must read as the **centre of the city** (flags visible over the street)
      without towering over the blocks. Judge the look in section 4e step 12az — the lever is the
      blueprint `tools/testfit/blueprints/Metropolis/CityHall.json`.
- [ ] 12w. **Build the Highway Ramp — the ring builds out.** Buy it and watch from a distance:
      **no building spawns** on the pad, and an **elevated ring** starts at the ramp on the west
      side and **grows outward in both directions** until it closes, in roughly **5 seconds** (12
      cells per second, 66 cells). The ramp is a single 3-cell slope descending **east** onto the
      end of the cross street at x = −35.
- [ ] 12w2. **Ramp on pillars (fixed this round).** Walk to the ramp and look at it from the side
      and from underneath: the slope is carried by **pillars along its whole span**, its top meets
      the deck and its toe meets the street. The kit's slant pieces are zero-thickness sheets, so
      **daylight under the middle of the ramp, or a pillar poking up through the road surface**,
      is the bug to report.
- [ ] 12x. **Walk under the deck.** Walk the whole ring line, and in particular **through the plot
      entrance**, which passes beneath the deck. Confirm you walk under it everywhere with no
      bump, no invisible wall and no camera clipping into a pillar. Getting stopped or having to
      jump is a bug.
- [ ] 12y. **Deck traffic.** Watch for 15 seconds: exactly **two** cars loop the ring on the deck,
      stay on the deck surface (they must not sink into it or float above it), and **never take
      the ramp** down to the streets.
- [ ] 12z. **Rejoin and far plot.** Stop, Play again on the same save: the ring is **already
      there, instantly, with no build-out animation**. Then fly out past ~290 studs: the far plot
      keeps its **deck** but drops its **cars**.
- [ ] 12aa. **Dig the Subway Line — kiosks appear with the streets.** Buy it. Confirm **no
      building** spawns, and that **one `MetroEntrance` kiosk appears straight away** — the one
      nearest the plot entrance always shows. Keep buying buildings: more kiosks appear **as their
      own street becomes visible**, up to **five** on a fully grown plot. Each stands on the
      pavement at a corner, facing the street, clear of pads, footprints and road cells.
- [ ] 12ab. **Judge the kiosk.** It is custom geometry (no kit has stairs going down): a small
      kiosk with a canopy, visible steps and a large **"M"** sign, about 5 × 6 studs. Report the
      look; the lever is `tools/assets/metro_kit.py`, which is a re-generate/re-upload.
- [ ] 12ac. **Two players (Local Server — multiplayer behaviour changed this wave).** Test →
      Start with **2 Players**. Get Player 1's plot to Metropolis. With Player 2 watching that
      plot, have Player 1 buy a building, then **Build the Highway Ramp**, then **Dig the Subway
      Line**. Player 2 must see the **same tiles, the same pavements, the same ring and the same
      kiosks**. A remote viewer far from the plot may get them without the build-out or the dust —
      expected. Different tiles, a missing ring or missing kiosks are not. Vehicle positions
      differing between the two clients is fine.
- [ ] 12ad. **Village and Boomtown are unchanged.** On a Village plot: baked dirt/cobble trails,
      `PathRenderer` reads `baked`. On a Boomtown plot: **gravel** before Pave Main Street,
      asphalt + concrete kerb after — and check the **driveway spurs match the street** in both
      states (a gravel street with asphalt spurs was a bug fixed in review, so look at it twice).
      Nothing in Metropolis may have changed either era.
- [ ] 12ae. **Missing props degrade silently.** In Edit mode rename
      `ReplicatedStorage/Assets/Props/Metropolis` to `Metropolis_bak`, Play, reach Metropolis and
      buy a few slots. Confirm the streets still draw as **plain asphalt-coloured `RoadTile`
      Parts** (flat cells, no kerbs or markings), **no highway, kiosks, trees, plazas, lamps or
      cars** appear, the game plays normally and **Output has zero errors**. Rename back.
- [ ] 12af. **Mobile pass on Metropolis.** Device Emulator, **375×667** portrait, on a grown
      Metropolis plot. Confirm the tiles, pavements and kiosks read at phone size (not a grey
      mush), buy one slot and confirm the new cell and its dust look right, and buy or look at the
      highway — the build-out must not visibly stall the frame rate. Open the Build panel and
      confirm nothing in its layout regressed.
- [ ] 12ag. **Counts.** On a fully owned near Metropolis plot, Command Bar:
      ```
      print(#workspace.CityDressing:FindFirstChild("Plot1"):GetChildren())
      ```
      (swap `Plot1` for your plot folder). The plan uses **38 of 180** tile cells
      (`budget.tileCells`) and **66 of 72** highway cells (`budget.highwayCells`); before the fix
      round a full plot was **≈ 220** children, and the round adds up to **12 block slabs** plus a
      higher tree cap (24 → **40**), so expect more. **Report the number rather than pass/fail.**

**Known caveats — confirm they are present, don't report them as bugs**

- The metro kiosk's stairwell **well is shallow**: at the game's camera angle a deep well shows
  its own floor, so it is deliberately shallow rather than a real hole.
- **No highway sign appears.** `HighwaySign` is uploaded but the client skips any sign that would
  clip a building footprint, and today's 7-stud-wide gantry always would. Seeing none is correct.
- Tile props are a hair wider than their 7-stud cell (**≈ 0.07 studs**), so neighbouring tiles
  overlap slightly on purpose — that is what hides the seam. A visible **dark line or flicker**
  between two tiles *is* a bug.

### 4d. Wave 2a fix round — orientation (all eras), paved blocks, street trees, plazas

Everything fixed after your **first** wave 2a Studio look. One item here is cross-era: the glTF
importer's 180° Y turn is now compensated for **buildings and props**, so Village, Boomtown,
Metropolis and Orbital Colony all changed facing. Its own pastes (§9) are done; do
`docs/MANUAL_STEPS.md` "M9" §10 first, then `rojo build -o build/test.rbxl`.

Optional reference: the same plot rendered offline is at
`assets/testfit/out/Metropolis/plot_overview.png` (and `plot_entrance/ramp/plaza/cityhall.png`).
Studio should look like those; a clear difference is worth reporting on its own.

- [ ] 12ah. **Village — buildings face their pads.** Fresh save, buy 4–5 Village slots. For each,
      stand on the **buy pad** and look at the building: its **front** (door, porch, signage, the
      side you'd walk into) faces **you**. Backs, blank walls or side walls facing the pad = the
      bug. Check the Chapel and the Bakery in particular.
- [ ] 12ai. **Boomtown — buildings and props.** Reach Boomtown (`GrantCash` `10000000000000`,
      buy out, advance). Confirm: shopfronts face their pads; the `Billboard`, `NeonSign`,
      `FireHydrant` and `Streetlamp` props sit the right way round (sign faces the street, not
      the building); and **cars drive nose-first** along the street (they drove **tail-first**
      before this fix — that is the regression to watch for).
- [ ] 12aj. **Metropolis + Orbital Colony — same spot check.** On each era, pick three slots with
      an obvious front (Metropolis: `CityHall`, `Supermarket`, `Hotel Tower`; Orbital: any dome
      with a door) and confirm the front faces the pad. Report any building you have to walk
      around to find its entrance.
- [ ] 12ak. **Paved blocks appear with the first purchase on them.** On a Metropolis plot, buy a
      building on an empty block. Confirm a **concrete slab** (grey-blue, flat with the ground)
      appears under that block **with a dust burst**, covering the ground between the streets.
      Buying a **second** building on the **same** block must **not** add another slab or a second
      burst.
- [ ] 12al. **Slabs stay off the streets.** Walk the edges of two or three slabs. A slab must never
      cover a road tile, a pavement strip, a plaza or a kiosk, and two neighbouring slabs must not
      **flicker** where they meet (they are half a stud apart on purpose). Slabs **do** run under
      buildings and pads — that is correct, not a bug.
- [ ] 12am. **Street trees line the blocks.** Confirm trees stand along each slab edge that faces a
      **drawn** street, roughly every **9 studs**, just inside the edge — and **none** inside a
      building footprint, a buy pad, a footpath or a kiosk. As more streets are drawn, more edges
      get trees. Total trees on the plot are capped at **40** (street trees first, the rest
      scattered in the zones), so on a full plot some edges will be thinner — expected.
- [ ] 12an. **Plazas sit on the avenue.** Find **PlazaA** on the **west** avenue at z = 0 and
      **PlazaB** on the **east** avenue at z = −28. Each is **14×14** with a paved apron whose
      edge is **flush against the avenue pavement** — no strip of bare ground between the plaza
      and the street, and no overlap onto the asphalt. Walk from the street onto each plaza.
- [ ] 12ao. **Mobile pass — Device Emulator, 375×667 portrait.** On a grown Metropolis plot:
      the slabs, street trees, plazas, the dome and the ramp all read at phone size (not grey
      mush); buy one slot and confirm the new slab/trees and their dust look right and the frame
      rate does not visibly stall; open the Build panel and confirm nothing in its layout
      regressed. Then switch to a **Village** plot and confirm buildings still face their pads at
      this size.
- [ ] 12ap. **Two players (Local Server — dressing changed this round).** Test → Start with
      **2 Players**. Get Player 1 to Metropolis. With Player 2 watching that plot, Player 1 buys a
      building on an empty block, then **Found City Hall**, then **Build the Highway Ramp**.
      Player 2 must see the **same slab, the same street trees, the same plazas, the same hall and
      the same ramp**. A far viewer may get them with no burst — expected. **Different** slabs or
      trees, or a building facing a different way on the two clients, is not.
- [ ] 12aq. **Stop Play.** Report: anything facing the wrong way, any concrete over asphalt, any
      flicker between slabs, and the child count from step 12ag.

**Known caveats for this section — don't report them as bugs**

- **No highway sign appears** (same as section 4c): the 7-stud gantry always clips a footprint, so
  the client skips it.
- The metro kiosk's **stairwell well is shallow** on purpose (a deep well shows its own floor at
  this camera angle).

### 4e. Wave 2a third round — park strips, girder highway, parking garage, kit-only City Hall

Everything fixed after your **second** wave 2a Studio look. Metropolis only; no other era changed.
Do `docs/MANUAL_STEPS.md` "M9" §10 (two pastes) first, then `rojo build -o build/test.rbxl`.

Optional reference: the same plot rendered offline at half growth is
`assets/testfit/out/Metropolis/plot_tier2.png` (`py tools/testfit/plotrender.py Metropolis
--tier 2`); the full-growth renders are `plot_overview/entrance/ramp/plaza/cityhall.png`. Studio
should look like those.

- [ ] 12ar. **A fresh Metropolis plot is green, not bare.** Reach Metropolis (`GrantCash`
      `10000000000000`, buy out, advance) and before buying anything walk the plot. Confirm the
      **whole future street grid reads as green park strips** — grass slabs on every planned
      street cell — with **planters** (small trees) spaced along each run. Bare brown ground where
      a street will later run is the bug.
- [ ] 12as. **No more dead-end sidewalk beside bare ground.** Buy 2-3 buildings and walk to a
      **junction where only one of the two streets has grown**. Confirm the ungrown arm continues
      as a **park strip**, not as a pavement stub next to nothing. A sidewalk running into bare
      ground is the exact fault this round fixes.
- [ ] 12at. **Strips swap to tiles as the street grows.** Stand where a park strip runs and buy the
      building that extends that street. Confirm the strip's slabs **and** its planters vanish in
      the **same moment** the tiles land, covered by the dust burst — never tiles on top of grass,
      never a planter left standing in the road, never a one-frame gap of bare ground.
- [ ] 12au. **Strips stay out of everything else.** Walk the edges: a park strip must never overlap
      a drawn road tile, a laid pavement strip, a paved block slab or a metro kiosk. Planters are
      capped at **24** per plot, so on a big plot some runs are thinner — expected.
- [ ] 12av. **Highway is a real girder deck now.** Buy **Build the Highway Ramp** and look at the
      ring from the side and from underneath. Confirm a **solid box-girder deck carried on
      concrete piers**, with **barriers** along the edges and **lane lines** on the surface — not
      a strip of street floating on a wall. Daylight through the deck, a missing pier, or a pier
      standing in mid-air is the bug.
- [ ] 12aw. **Walk under the deck again.** Walk the ring line and **through the plot entrance**
      beneath the deck: you must pass under everywhere with no bump, no invisible wall and no
      camera clipping into a pier (soffit is 6.10 studs, deck surface 7.07).
- [ ] 12ax. **Ramp meets the deck and the street.** Look at the ramp's **top**: it must sit flush
      against the junction deck, with its **first cell fully inward** from the junction — no
      overlap onto the ring, no step, no gap. Then look at its **toe**: it must meet the street
      surface flush. Cars on the deck still never take the ramp.
- [ ] 12ay. **Parking garage grows lot to decks.** Buy **ParkingGarage** and grow it through all
      five stages (keep buying upgrades with `GrantCash`). Confirm stage 1 is a **surface lot**
      (booth, barrier, painted bays, a few cars) and it grows to a **four-deck garage** about
      **13.8 studs** tall with ramps, columns and a sign. It must read as a garage, not as
      "streets stacked up" (your words last round).
- [ ] 12az. **City Hall, judged.** Stand on the buy pad and then at the plot entrance. Confirm the
      white civic block with its canopy and **three flags** reads as the centre of the city, at a
      size that fits the blocks around it. Report your verdict either way — this is the third
      version.
- [ ] 12ba. **Mobile pass — Device Emulator, 375×667 portrait.** On a Metropolis plot at **partial**
      growth (so strips and tiles are both visible): the park strips, planters, girder highway,
      garage and City Hall all read at phone size; buy one slot and confirm the strip-to-tile swap
      and its dust look right with no visible frame-rate stall; open the Build panel and confirm
      nothing in its layout regressed.
- [ ] 12bb. **Two players (Local Server — dressing changed this round).** Test -> Start with
      **2 Players**. Get Player 1 to Metropolis. With Player 2 watching that plot, Player 1 buys a
      building that extends a street, then **Build the Highway Ramp**, then **Found City Hall**.
      Player 2 must see the **same park strips, the same strip-to-tile swap, the same deck and
      ramp and the same hall**. A far viewer may get them with no burst — expected. Different
      strips, a planter left behind on one client, or a different deck is not.
- [ ] 12bc. **Stop Play.** Report: anything left behind after a strip swap, any daylight under the
      deck or gap at the ramp top, your verdict on the garage and on City Hall, and the child
      count from step 12ag (park strips add slabs and planters, so expect it higher on a partly
      grown plot).

**Known caveats for this section — don't report them as bugs**

- A **brand-new** Metropolis plot is covered in green: the whole future street grid shows as park
  strips before any street exists. That is the design, not a rendering fault.
- The planter uses the shared `TreeGrowing` prop, so it can look **tall** next to the two-storey
  blocks. Say so if it bothers you, but it is known.
- **City Hall reads as a white civic block with flags**, not a domed town hall:
  `city-kit-commercial` has no civic piece and you asked for kit-only.
- **No highway sign appears** (same as sections 4c/4d): the 7-stud gantry always clips a footprint.

### 4f. Wave 2b — Orbital Colony dressing (tubes, monorail, decking, rocks)

Orbital only. Do `docs/MANUAL_STEPS.md` "M9" §11 (one props paste) first, then
`rojo build -o build/test.rbxl`.

Reference renders (Studio should match): `assets/testfit/out/OrbitalColony/plot_overview.png`,
`plot_entrance.png`, `plot_tier2.png` (`py tools/testfit/plotrender.py OrbitalColony`).

- [ ] 12bd. **Reach Orbital.** Workspace attribute `GrantCash` = `10000000000000`, buy out and
      advance each era until the top bar reads **ERA 4**.
- [ ] 12be. **Fresh plot = bare regolith.** Before buying anything, walk the plot. Expect:
      - no tubes, decking, rocks, domes, lamps or monorail;
      - Output silent about Orbital props.
      A pre-drawn tube grid or green park strips here is the bug (Metropolis-only feature).
- [ ] 12bf. **First module grows a tube.** Buy one building on the central axis. Expect:
      - a glass tube (white frames, light-blue glass, ~4 wide × 4.5 tall) from the plot entrance
        up the middle to that module;
      - a Metal decking **spur** from the tube to the module door;
      - a capped **airlock** on every dead end;
      - the dust burst as it appears.
      **No pavement beside the tube — by design.**
- [ ] 12bg. **Tube pieces follow the connections.** Buy modules on the side tubes (x = ±28) and
      the cross tube (z = −28). Check each cell:
      - dead end → `TubeEnd` with airlock;
      - through run → straight;
      - a turn where only one arm has grown → bend;
      - three arms → tee; four arms (centre of the cross tube) → cross.
      Bug: an open tube mouth, the wrong piece, a gap or an overlap between cells.
- [ ] 12bh. **Decking under clusters.** Buy the first module of a cluster. Expect:
      - a dark-grey Metal decking slab under that cluster, appearing with the module;
      - no trees or rocks on its edge;
      - bare regolith between clusters (decking is **only** under clusters).
      Bug: a slab flickering against a tube or spur, or decking with no module on it.
- [ ] 12bi. **Rocks grow by tier.** Keep buying and watch the 6 rock fields (front corners, the
      middle and back corridors). Expect:
      - rocks appear tier by tier and grow pebbles → crystal outcrop;
      - never on decking, a tube, a pad or inside a building;
      - at most **30**.
- [ ] 12bj. **Domes and the platform by tier.**
      - tier 2: first small dome;
      - tier 3: the observation platform beside the central tube, two more domes;
      - tiers 4–5: the back-corridor domes (7 domes in all).
      Each dome faces a tube; none sits on a tube or footprint.
- [ ] 12bk. **Lamps.** From tier 3, a light panel on a mast at every second tube junction (max 10).
      None standing inside a tube.
- [ ] 12bl. **Build the Monorail.** Buy **Build the Monorail** (pad front-right of the entrance).
      Expect:
      - **no building** spawns;
      - the beam on piers builds out **both ways from the entrance side** and closes the loop
        around the plot (ring 56);
      - no ramp, no junction.
- [ ] 12bm. **The train.** Watch a full lap. Expect:
      - **one two-car train**, nose first, at beam height (7.07);
      - it **stays on the beam through all four corners** (the reviewer's fix) — a slight
        overhang on corners is known;
      - no jump when the lap wraps.
- [ ] 12bn. **Walk under the beam.** Walk out through the plot entrance and along the ring: no
      bump, no invisible wall, no camera stuck in a pier (soffit 6.10). Walk **through** a tube:
      you pass through (tubes are dressing — known).
- [ ] 12bo. **No ground vehicles** anywhere on the plot — by design.
- [ ] 12bp. **Rejoin.** Stop, Play again. The whole loop is there **at once** (no build-out), the
      train is running, and tubes/rocks/domes are in the same places.
- [ ] 12bq. **Mobile — Device Emulator, 375×667 portrait.** On a partly grown Orbital plot:
      tubes, decking, rocks, domes, the beam and the train all read at phone size; buy one module
      and confirm the tube reveal and dust with no visible stall; open the Build panel — no layout
      regression.
- [ ] 12br. **Two players (Local Server — dressing changed).** Test → Start, **2 Players**. Get
      Player 1 to Orbital. Player 2 watches while Player 1 buys a module, then Build the Monorail.
      Player 2 must see the **same tubes, decking, rocks, domes and loop**. Train position may
      differ; a far viewer may get no burst — both expected.
- [ ] 12bs. **Degrade.** Edit mode: rename `ReplicatedStorage/Assets/Props/OrbitalColony` →
      `OrbitalColony_bak`. Play, reach Orbital, buy a few modules and the monorail. Expect:
      - tubes draw as **grey slabs**;
      - no monorail, rocks, domes, platform or lamps;
      - buildings and economy normal;
      - **Output: zero errors.**
      Stop, rename it back, rebuild.
- [ ] 12bt. **Counts.** On a fully grown Orbital plot with the monorail, Command Bar:
      `print(#workspace.CityDressing:FindFirstChild("Plot1"):GetChildren())` (swap in your
      `Plot<n>`) and `print(#workspace.CityDressing:GetDescendants())`. Report both.
- [ ] 12bu. **Other eras unchanged.** Glance at a Village, Boomtown and Metropolis plot (second
      player or a spare save): same dressing as before this wave.

**Known caveats for this section — don't report them as bugs**

- Tubes are dressing: you walk straight through them.
- The train overhangs the beam slightly on corners.
- A fresh Orbital plot is bare: the future tube grid is **not** pre-drawn (unlike Metropolis park
  strips). An undrawn arm is just a capped tube end.
- Nothing drives on the ground; the train is the only mover.

### 4g. Wave 2b — "City detail" setting

A personal setting that thins the dressing on low-end devices. Needs no assets. **Do step 12bv
first**, on the first Play after the rebuild.

- [ ] 12bv. **Old save loads with it on.** Your Studio save predates this build (schema v5).
      First Play after the rebuild: open **Settings** (⚙ in the bottom bar). Expect:
      - **City detail** row reads **ON**;
      - cash, era, slots, Music/Sound effects and (VIP) VIP building skins unchanged;
      - Armory weapons and materials intact;
      - no Output error about the profile.
- [ ] 12bw. **Toggle off, live.** On a tier-5 plot with lamps (Village with Pave the Road,
      Boomtown with Streetlamp Row, or Orbital), and a second plot with cars in view, tap City
      detail **OFF**. Within a second, expect:
      - trees / rocks / Metropolis park planters drop to about **half**;
      - **all lamps and lanterns vanish**;
      - your **own** plot keeps its cars / deck cars / train; **other plots'** vehicles vanish;
      - roads, tubes, buildings and decking **do not flicker or rebuild**.
- [ ] 12bx. **Toggle back on.** The **same** trees/rocks return in the **same** spots, lamps and
      other plots' vehicles return. Nothing moves.
- [ ] 12by. **Persists.** Leave it OFF, Stop, Play. Settings still reads OFF and the plot is
      thinned from the first frame. Turn it back ON afterwards.
- [ ] 12bz. **Spam.** Tap the toggle ~10 times fast. It ends in the last state you tapped, the
      plot matches it, no Output error.
- [ ] 12ca. **Two players (Local Server).** 2 Players. Player 2 turns City detail OFF, Player 1
      leaves it ON. Player 1 still sees everything on both plots; only Player 2's view thins. The
      setting is per player.
- [ ] 12cb. **Mobile — Device Emulator, 375×667 portrait.** Open Settings. The row list
      **scrolls** (VIP owners see four rows) and City detail is reachable and tappable. Toggle it:
      same result as 12bw.
- [ ] 12cc. **Stop Play.** Report: any wrong tube piece or open mouth, the train leaving the beam,
      decking/rocks overlaps, the counts from 12bt, and whether City detail OFF visibly helps.

**Publishing note:** the setting moved the profile to schema v6. Publish the hub **and**
Expeditions together (`docs/MANUAL_STEPS.md` "M9" §11 step 51).

### 4h. Wave 2c — living city (houses, greenery, parked cars, walkers, smoke, birds)

Village, Boomtown and Metropolis only. Client-only cosmetics, all keyed to the plot's
`GrowthTier`. The 48 props are already harvested and templated (2026-09-23) — nothing owed, just
rebuild.

**What to expect per era at tier 5 (maximums):**

| | Village | Boomtown | Metropolis |
|---|---|---|---|
| Filler lots | 21 (cottages on small 6×6 lots) | 18 (`HouseE/F`, sheds) | 10 (apartments, townhouses) |
| Greenery (zones, + garnish per lot) | 24 | 20 | 14 |
| Parked | 6 carts | 12 cars | 16 cars |
| Moving vehicles | 3 carts | 6 cars | 8 cars |
| Walkers (from tier 2) | 5 | 7 | 8 |
| Walker line | trail edge | asphalt edge | pavement |
| Chimney smoke (from tier 2) | yes | yes | **no** |
| Bird flocks (from tier 2) | 1 at tiers 2–3, 2 at tiers 4–5 | same | same (grey pigeons) |

Greenery is capped at **48** pieces per plot. Reference street plans:
`assets/testfit/out/<Era>/streetplan.png` (`py tools/streetplan.py <Era>`).

**Setup**

- [ ] 12cd. **Rebuild.** `rojo build -o build/test.rbxl` (or resync `rojo serve`). In Edit mode,
      Explorer: `ReplicatedStorage.Assets.Props.Village.CottageA`,
      `ReplicatedStorage.Assets.Props.Boomtown.WalkerA` and
      `ReplicatedStorage.Assets.Props.Metropolis.Bird` all exist.
- [ ] 12ce. **Graphics not low-end.** Play → Esc → Settings → Graphics Mode **Automatic** (or
      Manual at **4 or higher**). Levels 1–3 count as low-end and hide smoke and birds (tested
      on purpose in 12cs).

**Village, tier by tier** (fresh save; watch `GrowthTier` on `Workspace/Plots/Plot_<n>`
Attributes; use the `GrantCash` Workspace attribute + Build panel ×1/×10/Max to climb)

- [ ] 12cf. **Tier 0 = unchanged.** Before buying: no cottages, bushes, flower beds, hedges, carts,
      walkers, smoke or birds. Same bare plot as before this wave.
- [ ] 12cg. **Tier 1** (first buy). Expect:
      - at least 2 new houses/cottages appear (dust burst);
      - about 4 greenery pieces (bushes, flower beds, hedges) plus 1 piece beside each visible lot;
      - **no** parked carts, walkers, smoke or birds yet.
- [ ] 12ch. **Tier 2.** Expect:
      - more cottages and greenery;
      - up to 2 **parked carts**, each beside a **drawn** trail (never beside bare grass);
      - walkers (≈ 1.75 studs, chunky toy figures in smocks/aprons) walking the trail edge, gently
        bobbing;
      - **chimney smoke** rising from `HouseA`, `HouseB` and the cottages;
      - **one bird flock** (3 birds) circling above a tree grove.
- [ ] 12ci. **Tiers 3 → 5.** Every tier step adds houses **and** greenery. At tier 5: 21 filler
      lots shown, up to 6 parked carts, 3 moving carts, 5 walkers, 2 flocks.
- [ ] 12cj. **No overlaps.** Walk the whole plot. Bug if any of these sits on a trail, a pad or
      inside a building/footprint:
      - a cottage, bush, flower bed, hedge or parked cart;
      - a walker walking **through** a house, lantern or building.

**Boomtown, tier by tier** (buy out Village, Advance Era)

- [ ] 12ck. **Tier 0 = unchanged** (right after advancing): no new houses, greenery, parked cars,
      walkers, smoke or birds.
- [ ] 12cl. **Tiers 1 → 5.** Expect by tier 5:
      - new `HouseE`/`HouseF` houses and small sheds, each facing a street;
      - bushes, hedges, flower beds and planters (garden-kit), tidy around lots;
      - up to 12 **parked cars** in kerb bays or driveways, fully off the asphalt;
      - 6 moving cars, 7 walkers on the asphalt edge (casual outfits), clear of the cars;
      - smoke from `HouseA`–`HouseE` chimneys (`HouseF` and sheds have none — by design);
      - 2 bird flocks.
- [ ] 12cm. **Parked only beside drawn streets.** At tier 2–3, find a bay on a street that is
      **not drawn yet** (bays are marked on `assets/testfit/out/Boomtown/streetplan.png`): empty.
      Buy the building whose street passes it: the bay can now fill. Bug: a parked car beside
      grass or in the carriageway.

**Metropolis, tier by tier** (advance again)

- [ ] 12cn. **Tier 0 = unchanged.** Then tiers 1 → 5. Expect by tier 5:
      - 10 filler lots: apartments (`ApartmentA–C`) and townhouses; townhouses under the ring
        deck **do not poke through** it (soffit 6.65);
      - greenery and planters in the outer bands and corners;
      - up to 16 parked cars beside drawn tile streets, none on a tile;
      - 8 moving cars; 8 walkers in suits **on the pavement**;
      - **no chimney smoke** (Metropolis is not a smoke era);
      - grey pigeon flocks over the groves.

**All three eras**

- [ ] 12co. **Walkers turn back.** Follow one walker to the end of its line. It **turns back** at a
      lamp, lantern, kiosk, signal, house or building — never walks through it. Crossing the
      carriageway at a junction is allowed.
- [ ] 12cp. **No collisions.** Walk your avatar through a walker, a parked car, a bush and a
      cottage: no bump, no prompt blocked.
- [ ] 12cq. **Far plot (LOD).** From a tier-5 plot, fly **> 290 studs** away. On that plot:
      greenery, parked cars, walkers, smoke and birds **vanish**; filler houses **stay**. Fly back:
      all return within ~1 s, same spots.
- [ ] 12cr. **City detail OFF / ON.** Settings → **City detail** OFF. Within a second:
      - greenery drops to about **half**;
      - parked cars, walkers, smoke and birds **gone**;
      - filler houses **stay**; roads and buildings don't flicker.
      Turn it ON: the **exact same** greenery, parked cars and houses come back in the **same**
      spots. Bug: anything in a new place after the round trip.
- [ ] 12cs. **Low-end device.** Esc → Settings → Graphics Mode **Manual**, quality **1–3**. Stop,
      Play again (read once at start). Expect: no smoke, no birds; walkers **glide without bob**;
      everything else unchanged. Put Graphics Mode back to **Automatic**, Stop, Play. If Studio
      does not keep the graphics setting between Plays, skip and say so.
- [ ] 12ct. **Mobile — Device Emulator, 375×667 portrait.** On a tier-5 Boomtown or Village plot:
      - walkers **glide without bob** (touch = reduced motion);
      - chimney smoke and birds **still show** (phones keep them);
      - buy one slot: no visible stall; Build panel and Settings unchanged.
- [ ] 12cu. **Two players (Local Server, 2 Players).** Player 1 at tier 3+ in any of the three eras.
      Player 2 looks at Player 1's plot: **same** houses, greenery and parked cars in the **same**
      spots. Positions of walkers, moving cars and birds may differ — expected.
- [ ] 12cv. **Tier-0 plot and Orbital unchanged.** A tier-0 plot looks as before. An Orbital plot
      (4f) has no walkers, greenery, parked cars, smoke or birds.
- [ ] 12cw. **Degrade.** Edit mode: rename `ReplicatedStorage/Assets/Props/Metropolis/Bird` →
      `Bird_bak`. Play a Metropolis plot at tier 2+: no pigeons, everything else normal,
      **Output: zero errors.** Stop, rename it back.
- [ ] 12cx. **MicroProfiler < 0.3 ms.** Local Server, **3 Players**, each pushes a plot to tier 5
      (mix of eras is fine). On one client stand where all 3 plots are near (< 250 studs), Ctrl+F6.
      In the client Heartbeat find the dressing connections: one each for Traffic (cars),
      Walkers and Ambient (birds) — rows may be labelled by the client script, not the module.
      Their **sum** must stay **under 0.3 ms** across several frames. Report the number.
- [ ] 12cy. **Counts.** Command Bar on a tier-5 plot:
      `print(#workspace.CityDressing:FindFirstChild("Plot1"):GetDescendants())` (swap in your
      `Plot<n>`) and `print(#workspace.CityDressing:GetDescendants())`. Report both per era.

**Boomtown look changes to eyeball (previously approved things moved)**

- [ ] 12cz. **Lamp row** (Streetlamp Row owned): lamps now stand **1.2** studs off the road edge
      (was 0.8) — on the verge, not in the kerb or the asphalt, and walkers pass inside them.
- [ ] 12da. **Traffic lights** (Install Traffic Lights owned): signals stand **1.5** off (was 0.8)
      on each corner, clear of the carriageway and the walkers.
- [ ] 12db. **Ring lots 1, 2, 5, 6, 7** sit 0.5–0.6 studs further back. No house touches a street;
      nothing looks misaligned with its neighbours.
- [ ] 12dc. **Trees moved once.** Boomtown and Metropolis tree zones were re-planned, so trees
      stand in **different** spots than your last session — expected, once. Village bay 3 and
      lot 15 moved 1 stud. Judge only: does anything now look worse?
- [ ] 12dd. **Stop Play. Report:** any overlap (12cj/12cm/12cn), a walker through a solid, the
      12cx number, the 12cy counts, and a yes/no on 12cz–12dc.

**Known caveats for this section — don't report them as bugs**

- Walkers are taller than kit doors on purpose (anything door-sized is a speck at this camera).
- Walkers cross the carriageway at junctions; they have no animation, only a bob.
- Walkers, moving cars and birds are in different positions for different players.
- Not every house smokes: Village `HouseC`, Boomtown `HouseF` and sheds have no chimney.
- Trees in Boomtown and Metropolis moved once after this rebuild.
- No day-night cycle and no lit windows — not in this wave.

### 5. No collisions — walk through everything

- [ ] 13. On either plot at tier 5: walk **through** a tree, **through** a filler house, and
      **through** a moving vehicle. Confirm your character passes through all three with no
      bump/stop.
- [ ] 14. Walk **over** a path piece (a `Fill` and a `Rim` MeshPart) and a lamp piece — confirm no
      bump, no rising up onto the geometry, just flat ground-level walking.
- [ ] 15. Stand so a tree or filler house is between you and one of your buy pads/owned buildings,
      then tap the ProximityPrompt through it — confirm the prompt still triggers (it isn't
      blocked by the dressing in front of it).
- [ ] 16. In Explorer, expand `Workspace/CityDressing/Plot<n>` (note: no underscore, unlike
      `Plots/Plot_<n>`) and spot-check a road Part, a tree model's parts, a filler house's parts,
      and (Boomtown) a vehicle's parts: Properties should show **`CanCollide` false, `CanQuery`
      false, `CanTouch` false, `Anchored` true** on all of them. Do the same for a path piece's
      `Fill` and `Rim` MeshParts (`CastShadow` false too) and for the wave 1e props — a `Lantern`
      (Village), a `LampPost` and the `TrafficLight` (Boomtown). Walk through all three as well.

### 6. Other players see the same dressing

- [ ] 17. **Test → Start** with **2 Players** (Local Server mode). Get both players' plots to
      `GrowthTier` 5 (Village or Boomtown, your choice, can be different eras). As Player 2, look
      at Player 1's plot: confirm the roads, trees (same growth stages), filler houses, and plaza
      look **identical** to what Player 1 sees on their own client. Vehicle positions may differ
      between the two clients — that's expected, not a bug.
- [ ] 17b. **Path parity.** Still in Local Server: have Player 1 buy a slot while Player 2 watches
      that plot. Both clients must end up with the **same path pieces in the same shape**. Player 2
      (a remote viewer) may see it appear without the rim/fill/dust effect if the plot is far from
      their camera — that is expected; a **different** path network is not.
- [ ] 18. Stop Play.

### 7. LOD — far plots simplify

- [ ] 19. Single-player Play, plot at tier 5 with trees/lamps/vehicles visible (on Boomtown that
      means Streetlamp Row is owned — wave 1e). Fly the camera
      (or walk) more than **~290 studs** away from the plot (past `lod.nearRadius` 250 +
      `hysteresis` 40). Confirm trees, lamps, and vehicles **disappear** from that plot, while the
      **path fills**, houses, and the plaza **stay**.
- [ ] 20. Move back within range. Confirm trees, lamps, and vehicles **reappear** within a second
      or two (no need to wait long — the LOD check runs every `lod.refreshSeconds`, 0.5s).
- [ ] 20b. **Path rims near/far** (`paths.rimNearOnly` true). Keep your eyes on the paths while you
      fly out past ~290 studs and back in:
      - The darker **rim outline vanishes** on the far plot and **comes back** when you return.
      - The **dirt/asphalt fill never blinks, moves or re-appears** — not once, in either direction.
      - The lane graph is untouched by the flip, so any vehicle still visible **keeps driving
        without a jump or reset** (the vehicles themselves still drop at the far threshold, per
        step 19, and resume when you come back).
      - Explorer check on the far plot: each piece Model still has its `Fill` and has **no `Rim`**;
        both are back once it is near.

### 8. MicroProfiler — vehicle cost, dust cost, path triangles

- [ ] 21. Get 3 plots near the camera to `GrowthTier` 5 (so vehicles are active on all three —
      `lod.vehiclePlots` is 3). Press **Ctrl+F6** to open the MicroProfiler.
- [ ] 22. In the profiler, find the **client thread's Heartbeat** bar for the current frame and
      expand it looking for the row driving vehicle movement (labelled by the script/module
      moving vehicles, e.g. `Traffic`) — it should show up as one connection with all ~20 vehicles
      moved in a single `BulkMoveTo` call, not one row per vehicle.
- [ ] 23. Confirm that row's time is **under 0.2 ms** per frame. (How to read it: click the row —
      the profiler shows the selected frame's time in milliseconds at the bottom/side; hover
      nearby frames to confirm it's consistently under 0.2 ms, not just a lucky frame.)
- [ ] 23b. **Dust Heartbeat only during a burst.** With the MicroProfiler open, buy a slot on a near
      plot, then **pause** the profiler (the Pause button in its toolbar) and scrub back through the
      last couple of seconds. Confirm a **second** Heartbeat row (the dust burst, alongside the
      traffic row) exists only for the ~0.8 s of the burst and is **gone before and after** it. A
      dust row still ticking when nothing is appearing is a leaked connection — report it.
- [ ] 23c. **Path triangle cost.** Open the render stats (**Shift+F2** → Render, or View → Stats →
      Rendering) and read the **triangle** count. With one fully-owned Village plot in view expect
      roughly **33k** path triangles, Boomtown roughly **37k**; with all ten plots built and on
      screen the paths alone are about **350k**. Note the number you see and report it if the frame
      rate drops noticeably when several built plots are in frame at once — this is the one number
      that scales badly and it is worth a baseline before wave 2 adds two more eras.

### 9. Part budget

- [ ] 24. With as many plots as you can reasonably get to `GrowthTier` 5 (10 plots at tier 5 is
      the target; fewer is fine, just note how many), open the **Command Bar** (View → Command
      Bar) and run:
      ```
      print(#workspace.CityDressing:GetDescendants())
      ```
- [ ] 25. Confirm the **non-path** dressing still fits the ≤ ~1300 target at 10 plots tier 5
      (≈ 130 per plot). Baked paths add instances on top of that: one Model plus a `Fill` (plus a
      `Rim` while near) per visible piece — up to 58 pieces on a fully-owned Village plot, 33 on
      Boomtown, capped by `budget.pathPieces` (120). Count the path share with:
      ```
      print(#workspace.CityDressing:FindFirstChild("Plot1"):GetChildren())
      ```
      (swap `Plot1` for your plot's folder name — `Plot<n>`, no underscore.)
      and report the totals rather than pass/fail — the pre-path budget line has not been re-cut
      for wave 1d yet (owner: lead, before wave 2).

### 10. Refresh stability

- [ ] 26. With VIP owned (or buy it now, same flow as M7 section 5) and a plot dressed at tier 5,
      toggle something that refreshes cosmetics — buy the VIP pass mid-session, or buy a Legacy
      perk if you have Legacy to spend. Confirm the roads/trees/houses/plaza **do not flicker,
      disappear-and-reappear, or reset**, and any moving vehicle **keeps moving smoothly** through
      the refresh (no visible teleport/reset of its position).

### 11. Lifecycle — advance, rebirth, rejoin

- [ ] 27. From a fully-dressed tier-5 Village plot, Advance Era to Boomtown (own every Village
      slot first, use `GrantCash`). Confirm the Village dressing (roads, trees, cottages, plaza,
      carts) is **fully cleared** and Boomtown dressing rebuilds fresh at tier 0 (bare, then
      growing again as you buy Boomtown slots).
- [ ] 28. Repeat once through a Rebirth (own every slot of the final era, `RequestRebirth`):
      confirm dressing clears and rebuilds for the fresh Village lap.
- [ ] 29. Get a plot to tier 3+ with some dressing visible, then **rejoin** (leave Play, Play
      again on the same save, or Stop → Play). Confirm the same plot **reproduces the same
      layout** (same roads, same tree positions/stages, same filler houses) — not a different
      random arrangement.
- [ ] 30. On a fresh join, confirm your own plot dresses (roads/trees/etc. for its current tier)
      within **about 1 second** of spawning in — not stuck bare for several seconds.

### 12. Failure paths — missing config/props degrade silently

Do each of these **in Edit mode, before pressing Play** (the controller reads config once at
`Start()` and does not retry if it was missing at boot):

- [ ] 31. In Explorer, find `ReplicatedStorage/Shared/Config/CityDressing` and temporarily rename
      it (e.g. `CityDressing_bak`). Press Play. Confirm: **no dressing at all** appears on any
      plot (no roads, no trees, nothing under `Workspace/CityDressing`), buildings/pads/economy
      work exactly as before, and **Output has zero errors**. Stop Play, rename it back.
- [ ] 32. Find `ReplicatedStorage/Assets/Props` and temporarily rename it (e.g. `Props_bak`).
      Press Play, get a plot to tier 5. Confirm: **paths still draw normally** (baked path
      templates live in the separate `Assets/Paths` folder) and a paved plot still shows its
      **cobble/asphalt surface** (that is a texture swap, not a prop), but **no trees, houses,
      plaza, lamps, lanterns, traffic lights or vehicles** appear anywhere, and **Output has zero
      errors**. Stop Play, rename it back.
- [ ] 33. Find `ReplicatedStorage/Assets/Props/Village/Cart` and temporarily rename it (e.g.
      `Cart_bak`). Press Play, get a Village plot to `GrowthTier` 2+ (carts start at
      `vehicles.firstTier` 2). Confirm: **no carts** appear on that plot, but roads, trees, houses,
      and the plaza are all still present and correct, and **Output has zero errors**. Stop Play,
      rename it back and rebuild (`rojo build`) before continuing.

### 13. Mobile emulation pass (required every milestone)

- [ ] 34. Device Emulator, **375×667** portrait. Walk a tier-5 plot (either era). Confirm the
      dressing renders at a sensible scale (trees/houses/paths not oversized or clipped off
      screen) and doesn't visibly tank the frame rate. Buy one slot here too and confirm the path
      appear effect and dust still look right at phone resolution. **Wave 1e:** buy one street
      upgrade here as well — the surface swap and its puff must look right at phone resolution, and
      lanterns/lamps must read as posts, not as specks or as poles blocking the view of the buy
      pads. Open the Build panel — confirm nothing about its layout regressed.
- [ ] 35. Stop Play.

### What a bug looks like here

- `GrowthTier` not appearing as a plot Attribute, staying at `0` after buys, or jumping backward.
- No road/spur appears after the first purchase, or the spine/spur never connects to a building
  you own.
- A visible **seam, gap, dark bar or z-fight** where two path pieces overlap, or a rim showing
  across the mouth of a path — the whole point of wave 1d is that overlaps are invisible.
- A kit junction/bend tile appearing in Boomtown (they were dropped in wave 1d).
- A new path appearing with fill before rim, with no dust, or with a dust cloud left hanging; any
  other dressing on the plot flickering or rebuilding when one path appears.
- `PathRenderer` reading `parts` on a Village or Boomtown plot when `templates/_paths` is intact
  and `road.renderer` is `"auto"` — or **any Output error** when it is not intact.
- The main-street spine curving around Pave Main Street/Streetlamp Row instead of running over
  them, or Bank/Radio Station/Pave Main Street/Streetlamp Row growing a driveway spur they
  shouldn't have.
- **Wave 1e:** a Boomtown plot showing asphalt (even for one frame) before Pave Main Street is
  owned, or lamps at any tier before Streetlamp Row; a Village plot still dirt, or half dirt and
  half cobble, after Pave the Road; lanterns bunched on one trail while the other trails stay dark,
  or more than 16 of them; a lantern/lamp standing in the trail, inside a building, or floating;
  the surface reverting, blinking or re-laying on a near/far flip or a rejoin; a vehicle
  respawning or jumping when the surface changes. Up to **six** Boomtown traffic lights are
  expected, one per drawn crossing.
- **Wave 2a (Metropolis):** a street cell showing the wrong tile for its connections (a straight
  piece at a dead end, a tee where four streets meet), a footpath lying on top of the asphalt, a
  missing pavement on one side, or a car driving the car-free x = 0 civic axis; Found City Hall
  spawning a grey box, off-centre, or facing away from the entrance; Build the Highway Ramp or Dig
  the Subway Line spawning a **building**; the ring appearing all at once on purchase (it must
  build out from the ramp) or **not** appearing instantly on a rejoin; a deck car taking the ramp,
  sinking into the deck or leaving it; being blocked or having to jump to pass under the deck,
  especially at the plot entrance; **no** kiosk after buying Dig the Subway Line, more than five,
  or a kiosk on a road cell or inside a footprint; a Village or Boomtown plot changed by this wave
  — especially Boomtown spurs that no longer match the street surface.
- The player, camera, or a ProximityPrompt blocked by a tree, house, vehicle, or road tile.
- Any dressing part with `CanCollide`/`CanQuery`/`CanTouch` true, or not `Anchored`.
- Another player's client showing different roads/trees/houses than the owner sees (vehicle
  position differences are fine).
- Trees/lamps/vehicles not disappearing on far plots, or not returning when the camera comes back.
- Path **fills** blinking, moving or rebuilding on a near/far flip (only the rims may drop).
- The Traffic Heartbeat step at or above 0.2 ms with ~20 vehicles active, or a dust Heartbeat row
  still running when no path is appearing.
- More than ~1300 total non-path descendants under `Workspace/CityDressing` at 10 plots tier 5 (or
  proportionally more for fewer plots), or more than `budget.pathPieces` (120) piece Models on one
  plot.
- Dressing flickering, clearing, or a vehicle teleporting/resetting on a VIP or Legacy-perk
  refresh.
- Dressing surviving an era advance/rebirth instead of clearing and rebuilding, or a rejoin
  producing a different layout on the same plot.
- A plot staying bare for more than a couple seconds after joining.
- **Any Output error** with `CityDressing`, `Assets/Props`, or a single prop template renamed
  away — every one of those must degrade silently.
- **Any building whose back or side faces its buy pad**, a prop turned away from the street, or a
  car driving tail-first (fix round, sections 4d 12ah–12ai — this one applies to every era).
- Pavement or a block slab lying **over asphalt**, a gap at a bend, a strip across a road mouth, or
  two slabs flickering where they meet.
- A plaza with bare ground between it and the avenue, or a ramp with daylight under its middle.
- **Third round (Metropolis):** a pavement stub running into bare ground at a half-grown junction;
  a park strip left under a drawn street tile, or a planter still standing in the road after the
  street grows; two planters on the same cell; bare ground where a planned street has not grown;
  daylight between the highway deck and its piers, or a gap/step where the ramp meets the deck;
  a parking garage that still reads as stacked streets; City Hall missing its flags or pad-facing
  front.
- **Wave 2b (Orbital):** a pre-drawn tube grid on a fresh plot; an open tube mouth or the wrong
  tube piece; decking under no module or between clusters; a rock on decking, a tube or inside a
  footprint, or more than 30; Build the Monorail spawning a building; the loop appearing all at
  once on purchase (or **not** at once on rejoin); the train leaving the beam, driving tail-first
  or jumping at the lap wrap; being blocked under the beam; any ground vehicle; any Output error
  with `Props/OrbitalColony` renamed.
- **City detail:** an old save loading with it OFF; lamps or other plots' vehicles still showing
  when OFF; your own plot's vehicles vanishing; roads/buildings rebuilding on a flip; different
  trees coming back when ON; the setting not surviving a rejoin; one player's setting changing
  another player's view.

### Sign-off

- [ ] 36. All boxes above checked: growth-tier attribute tracking, a full Village tier-5 look
      (baked dirt paths/trees/cottages/plaza/carts), a full Boomtown tier-5 look (baked gravel →
      asphalt + concrete kerb/lamps/cars, main-street spine, P1/P2 no-spur slots), the baked-path
      look and appear effect (5b–5c), `PathRenderer = baked` plus both silent fallbacks (5d–5f),
      all four wave 1e street upgrades with their surfaces, lanterns, lamp row and traffic
      lights (12b–12p), the whole wave 2a Metropolis pass — tile streets, crossings, pavements and
      footpaths, Found City Hall, the highway ring build-out and walking under it, the subway
      kiosks, the two-player parity check and the missing-props degrade (12q–12ag), the fix-round
      pass — buildings facing their pads in **every** era, nose-first cars, per-cell pavement,
      paved blocks and street trees, the flush plazas and the pillared ramp (12ah–12aq), the
      third-round pass — park strips and their swap to tiles, the girder highway on piers, the
      ramp meeting the deck, the grown parking garage and the kit-only City Hall (12ar–12bc), the
      wave 2b Orbital pass — bare start, tube pieces, decking, rocks, domes, lamps, the monorail
      loop and train, parity and the degrade (12bd–12bu), and the City detail setting — migration,
      live toggle, persistence, two players, 375×667 (12bv–12cc) — no
      collisions anywhere (including the Explorer flag check), identical dressing for a second
      player, near/far LOD and the rim drop, the traffic MicroProfiler check under 0.2 ms, the dust
      Heartbeat and path-triangle readings, the part counts, refresh stability, era-advance/
      rebirth/rejoin lifecycle, all three failure-path degrades, and 375×667 mobile emulation.
- [ ] 37. Tell Claude Code "M9 city dressing playtest passed" (or report the exact failure and step
      number).

---

## C0 — Expeditions foundation (second place, Armory, teleport handoff)

**Goal:** the plumbing for combat, not combat itself. The hub gains a **Power** readout, an
**Armory** (two weapon slots that set your Max HP) and an **Expedition** panel; a second place
(`build/combat.rbxl`) loads the same profile and shows a lobby HUD you can Ready up in and Return
from. **There are no enemies until C1** — an empty lobby pad with nothing to fight is the correct
result here, do not report it as a bug. Numbers to cross-check: `docs/BALANCE.md` "C0".

**Before you start:**

- Build **both** places. PowerShell, from the repo root:
  ```
  $env:PATH = "$HOME\.rokit\bin;$env:PATH"
  rojo build -o build/test.rbxl
  rojo build combat.project.json -o build/combat.rbxl
  ```
- Confirm **Game Settings → Security → Enable Studio Access to API Services** is ON. With it ON
  the hub and the Expeditions place share one real profile, which is what makes steps 31–40 work.
  With it OFF each Studio session gets its own mock profile and materials granted in one place
  will not show in the other — expected, not a bug.
- Studio levers used below (Workspace → Attributes → **+**, type **number** unless stated; each is
  consumed once per second and reset to `0`):

  | Attribute | Where | Effect |
  |---|---|---|
  | `GrantCash` | hub | cash, as in M7–M9 |
  | `GrantMaterials` | hub / Expeditions | that many units of the era's material (Village = Timber) |
  | `GrantValor` | hub / Expeditions | that much Valor |
  | `DebugMission` | Expeditions (**string**) | mission id to load, default `village` |
  | `DebugOverdrive` | Expeditions (**boolean**) | Overdrive on/off |

- `src/shared/Config/Places.json` still has `hubPlaceId` and `combatPlaceId` at `0`. Sections 1–8
  are all run that way; section 9 needs the published pair from `docs/MANUAL_STEPS.md` "C0".

### 1. Hub boots unchanged, with the new readout

- [ ] 1. Open `build/test.rbxl` (or resync `rojo serve`) and press **Play**.
- [ ] 2. Confirm **zero red errors** in Output, and that the plot, buy pads, income and Build panel
      behave exactly as in M9 — nothing about the city loop changed this milestone.
- [ ] 3. Look at the **top bar**: beside cash/income there is now a **`⚔ 34`** power readout
      (starter Stick + Sling: 8 + 6 damage + 20 % of 100 base HP). Missing, or reading `0`, is a bug.
- [ ] 4. Look at the **bottom bar**: **six** buttons, each an icon above its word —
      **Build · Armory (⚔) · Expedition (🗺) · Legacy · Shop · Settings**. The four old buttons
      deliberately changed look. Confirm nothing is clipped and each is comfortably tappable.

### 2. Armory — buying a weapon raises Power and Max HP

- [ ] 5. Tap **⚔ Armory**. Confirm the header reads **`Max HP 100`**, there is one material chip per
      band (Timber / Steel / Circuits / Alloy) all reading `0`, and two rows: **Melee** (Stick) and
      **Ranged** (Sling).
- [ ] 6. Confirm the Melee row's next-tier line reads **`Tier 1 · 10 Timber`** with a **red**
      `Buy` (you have no Timber — insufficient), and the Ranged row the same.
- [ ] 7. Confirm **no Ascend row is visible** at `rebirthCount` 0 (Ascension needs Rebirth 1).
- [ ] 8. Add the Workspace attribute **`GrantMaterials` = `10`**. Within ~1 s Output warns
      `[ArmoryService] GrantMaterials lever: granted 10 to 1 loaded player(s)` and the attribute
      resets to `0`. Confirm the **Timber chip now reads 10**.
- [ ] 9. Tap **Buy** on the Melee row (Wooden Sword, 10 Timber). Confirm all of:
      - the row flashes and the weapon name becomes **Wooden Sword**,
      - the header becomes **`Max HP 120`**,
      - the top bar's power readout becomes **`⚔ 42`**,
      - the Timber chip drops to **0**.
- [ ] 10. Confirm the Melee row's next line is now **`Tier 2 · 60 Timber · unlocks at 15K/s (you:
      …/s)`** and the button reads **`Locked`** in **amber** — not red. That is the income gate:
      your city earns far less than 15,000/s this early.
- [ ] 11. Set **`GrantMaterials` = `60`** so you can afford tier 2, then tap **Buy** again. Confirm
      it is **refused** (error toast, button stays `Locked`), the Timber chip **keeps its 60**, and
      the weapon does **not** change. The server refuses the gate, not just the UI.
- [ ] 12. Use **`GrantCash`** and the Build panel to push your Village income past **15K/s** (a real
      greedy run crosses it at ~12 minutes — see `docs/BALANCE.md` "C0"). Re-open the Armory: the
      Melee button goes from **amber `Locked`** to an **enabled `Buy`**, and buying it makes the
      weapon **Iron Sword**, `Max HP 135`, power `⚔ 51`.
- [ ] 13. Tap **Buy** on the **Ranged** row too (Short Bow, 10 Timber, no gate). Confirm Max HP and
      power rise again and the two rows upgrade independently.
- [ ] 14. Stop Play, press **Play** again. Confirm the weapons, Max HP and power **persisted**, and
      Output has **no** migration warning or error.

### 3. Expedition panel with the place ids at 0

- [ ] 15. Tap **🗺 Expedition**. Confirm one tile, **Raider Woods**, with the meta line
      `Era 1 · 10 waves · ~8 min · Timber`.
- [ ] 16. Confirm the readiness line reads **`Recommended ⚔ 60 — you ⚔ <your power>`** (green at
      ≥ 60, amber from 42, red below) and ends with **`· Publish the Expeditions place first`** in
      dim grey.
- [ ] 17. Confirm the tile's button reads **`Soon`** and is **not tappable**, and that the
      **Overdrive** toggle is **hidden** (it needs Rebirth 1).
- [ ] 18. Confirm the **ACTIVE RUNS** list shows **`No friends on an expedition right now.`** (the
      run registry is a no-op in Studio, so an empty list is correct here).
- [ ] 19. **Depart refusal in Studio.** Stop Play. In `src/shared/Config/Places.json` set
      `"combatPlaceId": 1` (any non-zero placeholder), rebuild `build/test.rbxl`, Play, open the
      Expedition panel: the button now reads **`Depart`** and is tappable. Tap it. Confirm a toast
      **"Studio can't teleport — open build/combat.rbxl"**, that you **stay** on your plot, that
      Output warns `[ExpeditionService] Studio can't teleport`, and that nothing about your city
      (cash, slots, income) changes.
- [ ] 20. Stop Play and **restore** `"combatPlaceId": 0` (or paste the real id once
      `docs/MANUAL_STEPS.md` "C0" is done), then rebuild.

### 4. Profile migration — an old save gains the combat table

- [ ] 21. Using a save from an **earlier milestone** (any profile that existed before this session,
      i.e. schema v4), press Play. Confirm Output has **no** warning or error mentioning migration,
      schema version, `combat` or `highestEra` — the v4 → v5 step is silent and additive, same as
      v1 → v2 in M5.
- [ ] 22. Confirm the old save's city is intact (cash, slots, era, Legacy, perks) and the Armory
      opens with `Max HP 100` and zeroed materials.
- [ ] 23. Verify `highestEra` seeded from your era. With Play running, open the **Command Bar**
      (View → Command Bar), switch its context dropdown to **Server**, and run:
      ```
      local s = require(game.ServerScriptService.Server.Services.DataService).GetState(game.Players:GetPlayers()[1]) print(s.version, s.era, s.combat.highestEra, s.combat.expeditionSeconds)
      ```
      Confirm it prints version **5** and `highestEra` **equal to your era** (e.g. `5 2 2 0` on a
      Boomtown save). `highestEra` lower than `era`, or `nil`, is a bug.
- [ ] 24. If you have DataStore viewing access, confirm the saved profile's `version` reads `5` and
      it has a `combat` table with `gear`, `materials` and `highestEra`.

### 5. Mobile emulation pass (required every milestone)

- [ ] 25. Device Emulator, **375×667 portrait**. Confirm the six bottom-bar buttons fit in one row
      without clipping or overlapping, each icon+word is readable, and each is ≥ 48 px tall.
- [ ] 26. Open the **Armory**: both rows, the Max HP header and the four material chips are fully on
      screen, the `Tier 2 · 60 Timber · unlocks at 15K/s (you: …/s)` line **wraps** instead of being
      cut off, and Buy is tappable without zooming.
- [ ] 27. Open the **Expedition** panel: the tile, the readiness line and the ACTIVE RUNS header all
      fit; the readiness line wraps rather than truncating.
- [ ] 28. Confirm the top bar's `⚔` readout does not push cash/income off screen.
- [ ] 29. Rotate to **667×375 landscape**. Repeat 26–27 — nothing clipped, one panel open at a time,
      the dock still closes the panel.
- [ ] 30. Stop Play.

### 6. The Expeditions place in Studio

- [ ] 31. **Stop the hub Play session first** (the profile is session-locked; the Expeditions place
      cannot load it while the hub holds it). Then File → Open **`build/combat.rbxl`**.
- [ ] 32. In Explorer select **Workspace** → Attributes → **+** → `DebugMission`, type **string**,
      value **`village`**. (Leave `DebugOverdrive` off, or add it as an unchecked **boolean**.)
- [ ] 33. Press **Play**. Confirm: zero red errors, you spawn on a **`LobbyPad`** part in
      `Workspace` (built by code — the otherwise empty arena is correct at C0), and the HUD shows
      **`Raider Woods`** with **`Lobby`** under it.
- [ ] 34. Confirm the bottom-left **HP bar** reads your Armory value, not 100 — `HP 135 / 135` if
      you bought Iron Sword + Short Bow above. Select your character's **Humanoid** in Explorer and
      confirm `MaxHealth` matches. A flat 100 here means the profile did not carry over (check API
      services, "Before you start").
- [ ] 35. Confirm the **party list** shows one row — your name with a full HP bar — and there is a
      **Ready** button and a **Return** button.
- [ ] 36. Tap **Ready**. Confirm your party row gains a **✓** after your name; tap again and the ✓
      clears. (Nothing else happens at C0 — waves are C1.)
- [ ] 37. **The away clock.** Wait ~30 s, then Command Bar → context **Server**:
      ```
      local s = require(game.ServerScriptService.Server.Services.DataService).GetState(game.Players:GetPlayers()[1]) print(s.combat.expeditionSeconds)
      ```
      Confirm it prints roughly the seconds you have been in the lobby, and that running it again
      10 s later prints a **larger** number. Stuck at `0` is a bug.
- [ ] 38. **GrantMaterials here.** Workspace → Attributes → **+** → `GrantMaterials` = `25`. Confirm
      Output warns `[Combat] GrantMaterials lever: granted 25 to 1 loaded player(s)` and the
      attribute resets to `0`. (This place has no Armory panel — the proof is step 40.)
- [ ] 39. Tap **Return**. Confirm the **summary card** appears (zeros for cash/kills — C1 fills it),
      a toast **"Studio can't teleport — reopen build/test.rbxl for the hub"**, that you **stay** in
      the lobby rather than being kicked or frozen, and that Output warns
      `[ReturnService] cannot send <you> home (leave): Studio cannot teleport`.
- [ ] 40. Stop Play (this releases and saves the profile). Re-open **`build/test.rbxl`**, Play, open
      the **Armory**: confirm the **Timber chip shows the 25 Timber granted in the other place** —
      one profile, two places. The old value means the profile did not save (API services again).
- [ ] 41. **Locked mission.** Back in `build/combat.rbxl`, set `DebugMission` to `metropolis` (a
      mission this profile cannot have unlocked) and Play. Confirm you are **not** admitted: no wave
      line in the HUD, a "locked" toast, and **no error** in Output. Set it back to `village`.
- [ ] 42. **Bad mission id.** Set `DebugMission` to `nonsense` and Play. Confirm the same graceful
      refusal and **zero errors**. Set it back to `village`.

### 7. Two players in the lobby (Local Server — multiplayer changed this milestone)

- [ ] 43. In `build/combat.rbxl`: **Test → Start** with **2 Players** (Local Server). Wait for both
      clients to spawn on the lobby pad.
- [ ] 44. On each client confirm the party list shows **both players**, each with their own HP from
      their own profile (the two can differ) and both bars full.
- [ ] 45. On client 1 tap **Ready**. Confirm **client 2 also sees the ✓** on client 1's row within a
      second. Ready up on client 2 too — both rows show ✓ on both clients.
- [ ] 46. On client 2 tap **Return**. Confirm client 2 gets the summary card and stays, and **client
      1's party list drops back to one row**.
- [ ] 47. Confirm **no errors** in either client's Output or the server's, then Stop.
- [ ] 48. In `build/test.rbxl`: **Test → Start** with **2 Players**. On each client open the
      **Armory** and confirm each player sees **their own** power, Max HP and materials; set
      `GrantMaterials` = `10` (it pays **both** loaded players) and confirm a Buy on client 1 does
      not spend client 2's Timber. Stop.

### 8. Failure paths reachable from Studio

- [ ] 49. **Missing Armory config.** Stop Play. In Explorer (Edit mode) rename
      `ReplicatedStorage/Shared/Config/Armory` to `Armory_bak`, press Play. Confirm: the **⚔
      Armory** bottom-bar button is **gone**, the top-bar power readout is **hidden**, the city loop
      still works, and Output has **zero errors**. Rename it back.
- [ ] 50. **Missing Combat config.** Same trick with `Config/Combat`: the **🗺 Expedition** button is
      gone, everything else works, zero errors. Rename it back.
- [ ] 51. **Missing mission.** Same trick with the `Config/Missions` folder: the Expedition button is
      hidden (or the panel opens with no tiles), zero errors. Rename it back, then rebuild
      `build/test.rbxl` before continuing.
- [ ] 52. **Buy spam.** With the Armory open and no materials, tap **Buy** as fast as you can for
      ~5 seconds. Confirm refusal toasts but **no** error, no double spend, and no kick.

### 9. Published pair — the real round trip (published only)

Do this only after `docs/MANUAL_STEPS.md` "C0" is complete (both places published, both ids pasted
into `src/shared/Config/Places.json`, API services on for the live game). **Nothing in section 9
can be done in Studio** — Studio never teleports.

- [ ] 53. Join the **published hub** from the Roblox app or website. Write down your **cash**,
      **era**, **Power**, **Max HP** and one owned slot's level.
- [ ] 54. Open **🗺 Expedition** → **Depart** on Raider Woods. Confirm you are teleported to the
      Expeditions place within a few seconds (loading screen, then the lobby pad and HUD) and that
      your **HP matches the Max HP** you wrote down.
- [ ] 55. Stay in the lobby ~2 minutes, then tap **Return**. Confirm the summary card, then a
      teleport back to the **hub** and your own plot, and that **cash, era, slot levels, Power and
      Max HP all match** what you wrote down (plus earnings).
- [ ] 56. Confirm the **welcome-back / offline card** on that return credits the away time at the
      **full** rate (`Combat.json offline.expeditionEfficiency` is `1.0`, so ~2 minutes away pays
      ~2 minutes of full income). A visibly reduced payout, or no card at all, is a bug.
- [ ] 57. Confirm the round trip did **not** duplicate or wipe anything: no doubled cash, no reset
      slots, materials unchanged in the Armory.
- [ ] 58. **Active runs from a second account.** On a second device/account that is **friends** with
      your main, join the published hub and Depart. Then on your main open **🗺 Expedition** →
      **ACTIVE RUNS** and confirm the friend's run is listed (host name, mission, wave, party size)
      within ~10 s (the list polls every 10 s while open). The list must **never** show an access
      code or any server id.
- [ ] 59. Tap **Join** on that run. At C0 the expected result is a refusal toast (**"That run is
      full or already over"**) — join-in-progress is wired in C2. No error, no teleport into a
      broken state.
- [ ] 60. Leave from the **Expeditions** place directly (close the app while in the lobby), then
      rejoin the hub. Confirm your profile loads normally with no "already in a session" error and
      the away time is credited.

### 10. Not testable this milestone (don't hunt for these)

- `TeleportInitFailed` handling on both sides (a teleport Roblox refuses **after** accepting the
  call) is **code-review-only** — Studio cannot trigger it and a healthy published pair won't
  either. It was found and fixed in review; no playtest step covers it.
- Enemies, waves, damage, rewards, the pacing director, the tempo dot changing colour: **C1**.
- Party from the hub, join-in-progress, contribution split, Mentor bonus: **C2**.
- Ascension rows and the Overdrive toggle appear only at **Rebirth 1**; on a rebirthed save,
  checking that they *appear* is welcome, but the forge is balanced in **C3**.

### What a bug looks like here

- No `⚔` power readout in the top bar, or a value that doesn't change after buying a weapon.
- Fewer or more than six bottom-bar buttons, clipped icons/words, or a button under 48 px at
  375×667.
- Max HP not equal to `100 + melee hp + ranged hp`, or the combat place giving you 100 HP when your
  weapons say otherwise.
- A Buy that succeeds above the income gate (must stay `Locked`), or one that charges materials
  without upgrading the weapon (or upgrades without charging).
- An Ascend row visible at Rebirth 0, or an Ascend that goes through there.
- An Expedition tile tappable while `combatPlaceId` is `0`, or a Studio Depart doing anything other
  than a toast (a kick, a frozen character, a lost profile).
- Any migration warning/error in Output on an old save, `version` not reading `5`, or
  `combat.highestEra` below `era`.
- `expeditionSeconds` stuck at `0` while you sit in the lobby.
- Materials granted in one place not visible in the other after a Stop/Play with API services on.
- The Expeditions place erroring, kicking you, or leaving you with no HUD when `DebugMission` is
  missing, misspelled, or a mission your profile hasn't unlocked.
- A party list that doesn't show both players, or a Ready ✓ that only one client sees.
- **Published only:** a round trip that loses cash/levels, an offline card paying a reduced rate for
  expedition time, an ACTIVE RUNS entry containing anything server-ish (access code, job id), or a
  "profile already in a session" error after Departing or Returning.
- **Any red error** in Output in any of the above, including with a config renamed away.

### Sign-off

- [ ] 61. All boxes above checked: hub power readout and six-button bar, the Armory
      buy/gate/persist loop, the Expedition panel with ids at 0 plus the Studio Depart toast, the
      v4 → v5 migration and `highestEra`, the 375×667 and 667×375 passes, the Expeditions place in
      Studio (HP, Ready, away clock, Return toast, cross-place materials, locked/bad mission), the
      two-player lobby in Local Server, the four Studio-reachable failure paths, and — once
      published — the round trip, the offline credit and the ACTIVE RUNS list.
- [ ] 62. Tell Claude Code "C0 expeditions playtest passed" (or report the exact failure and step
      number).

## C1 — Studio bridge + Village expedition

**Goal:** the whole expedition loop, **playable from Studio**. The hub can't teleport in Studio, so
Depart now writes a handoff record to a DataStore and **kicks you**; you Stop Play, open the other
`.rbxl`, and the run boots from that record. On the far side: Raider Woods, three enemy types, ten
waves, bosses at 5 and 10, melee combo / bow / abilities, and a debug strip in both places.
Numbers to cross-check: `docs/BALANCE.md` "C1". This section **replaces** C0 section 9 (the
published round trip); C0 sections 1-8 still stand.

### Before you start

- Rebuild **both** places. PowerShell, from the repo root:
  ```
  $env:PATH = "$HOME\.rokit\bin;$env:PATH"
  rojo build -o build/test.rbxl
  rojo build combat.project.json -o build/combat.rbxl
  ```
- **Game Settings → Security → Enable Studio Access to API Services must be ON.** The whole
  bridge is a DataStore; with it OFF Depart refuses and warns once (that is section 3, step 24).
- `src/shared/Config/Places.json` already holds the real ids (hub `140344407905104`, Expeditions
  `74210626673425`), so the Expedition tiles are live. Nothing to publish this milestone.
- Attributes go on **Workspace** (Explorer → Workspace → Properties → Attributes → **+**). Numbers
  are consumed once per second and reset to `0`; strings reset to `""`; booleans are read as a
  state unless the table says "consumed".

  **Hub levers (`build/test.rbxl`)**

  | Attribute | Type | Effect |
  |---|---|---|
  | `GrantCash` | number | pays that cash to every loaded player, once |
  | `GrantMaterials` | number | that many units of the era's material (Village = Timber) |
  | `GrantValor` | number | that much Valor |
  | `DebugFakeRuns` | number | fills ACTIVE RUNS with N invented runs (max 8) |
  | `ForceTeleportFailure` | boolean | **consumed once**: the next Depart fails the way a live `TeleportInitFailed` does |

  **Expeditions levers (`build/combat.rbxl`)**

  | Attribute | Type | Effect |
  |---|---|---|
  | `DebugMission` | string | mission id to load (`village`); only used when no handoff record |
  | `DebugOverdrive` | boolean | Overdrive on/off for that boot |
  | `DebugWave` | number | next wave to start is N (in the lobby: the run starts at N) |
  | `DebugSpawn` | string | one enemy now: `raider`, `archer` or `brute` |
  | `DebugGodMode` | boolean | **state**, not consumed: you take no damage |
  | `DebugKillAll` | number ≥ 1 | every alive enemy dies with normal rewards |
  | `DebugSetGear` | string | `melee=2,ranged=1` sets your weapons and re-applies Max HP |
  | `DebugBots` | number | **state**: keep that many bots in the party (max 8) |
  | `GrantMaterials` / `GrantValor` | number | as in the hub |
  | `ForceRegistryFailure` | boolean | **sticky**: every MemoryStore registry call fails through its 3 warned retries |

- Both places also have a Studio-only **`⚙ debug`** strip with a button per lever: bottom-left in
  the hub, top-left in the Expeditions place. Neither exists in a published server.

### 1. Hub debug strip and levers

- [ ] 1. Open `build/test.rbxl`, press **Play**. Confirm **zero red errors** and that the city loop
      (plot, buy pads, income, Build panel) behaves exactly as in M9.
- [ ] 2. Bottom-left, above the bottom bar, find the **`⚙ debug`** tab. Tap it: it expands to
      **`⚙ debug ▾`** and shows five buttons — **Grant $10K**, **Grant 25 Timber**,
      **Grant 10 Valor**, **Fake runs ×3**, **Tele fail: OFF**.
- [ ] 3. Tap **Grant $10K**. Confirm the top-bar cash rises by exactly 10,000 within a second.
- [ ] 4. Tap **Grant 25 Timber**, then open **⚔ Armory**. Confirm the **Timber chip reads 25**.
- [ ] 5. Tap **Grant 10 Valor**. (No Valor readout in the hub UI at C1 — the proof is the
      Expedition report later. No error is the check here.)
- [ ] 6. **Attribute path.** Add `GrantMaterials` = `10`. Within ~1 s Output warns
      `[ArmoryService] GrantMaterials lever: granted 10 to 1 loaded player(s); attribute reset to 0`
      and the attribute is back at `0`. The Timber chip reads **35**.
- [ ] 7. Set your loadout for the run: buy **Wooden Sword** (10 Timber) in the Armory, then
      **Short Bow** (10 Timber). Header reads `Max HP 130`, top bar reads `⚔ 48`. (Iron Sword is
      income-gated; you'll set the recommended loadout with `DebugSetGear` in step 34.)
- [ ] 8. Tap **Fake runs ×3**. Output warns
      `[ExpeditionService] fakeRuns lever: 3 Studio-only run(s) in the join list`.
- [ ] 9. Open **🗺 Expedition**. Confirm **ACTIVE RUNS** lists three rows — **Fake 1 / Fake 2 /
      Fake 3**, each with a meta line like `village · Wave 1 · 1/4` and a **Join** button. An entry
      must never show an access code or a server id.
- [ ] 10. Tap **Join** on **Fake 1**. Confirm a toast
      **"Departure failed — ForceTeleportFailure is on, or Studio has no API access"**, that you
      **stay** on your plot, and that Output has **no red error**. (A fake run is deliberately
      unjoinable; in Studio every refusal reads as that one message.)

### 2. The bridge round trip — the heart of this milestone

- [ ] 11. Still in `build/test.rbxl`, **🗺 Expedition** → **Depart** on **Raider Woods**.
- [ ] 12. Confirm, in order:
      - a toast **"Handoff saved — Stop Play, then open build/combat.rbxl"**,
      - Output warns `[StudioBridge] <your name>: Handoff saved — Stop Play, then open build/combat.rbxl`,
      - about **1 second later you are kicked**, with the same sentence in the kick dialog.
      The kick **is** the teleport here. Being kicked instantly (no toast) or not at all is a bug.
- [ ] 13. **Stop Play.** (Studio stays open; the profile is already released.)
- [ ] 14. Prove the record beats the attribute: File → Open **`build/combat.rbxl`**, and set
      Workspace attribute **`DebugMission`** to **`nonsense`**.
- [ ] 15. Press **Play**. Confirm you spawn on the **`LobbyPad`** inside a fenced **green arena**
      (110×110 with a few rocks/logs), the HUD title reads **`Raider Woods`** and the wave line
      reads **`Lobby`** — the handoff record won over the bad attribute. Zero red errors.
- [ ] 16. Confirm the bottom-left **HP** reads your Armory value (`HP 130 / 130` after step 7), not
      100. A flat 100 means the profile did not carry over — check API access.
- [ ] 17. **The record is consumed once.** Stop Play, press **Play** again. This time you should get
      the **refusal path for `nonsense`**: no wave line, a "locked"/refusal toast, and **zero
      errors**. Set `DebugMission` back to **`village`** and Play again — you are in Raider Woods.
- [ ] 18. Tap **Ready**, play at least two waves (see section 4 for what to watch), then tap
      **Return** — or let the run end and press **Return** on the summary card.
- [ ] 19. Confirm: the **summary card** appears, then Output warns
      `[StudioBridge] <your name>: Run over — Stop Play, then reopen build/test.rbxl` and you are
      **kicked ~1 s later** with that message.
- [ ] 20. **Stop Play**, re-open **`build/test.rbxl`**, press **Play**.
- [ ] 21. Confirm the **EXPEDITION REPORT** card appears once: title **`Raider Woods`**, a
      `Waves cleared N / 10 · best N` line, and rows for **Cash**, **Timber**, **Valor**, **Kills**
      and **Time** matching what the combat summary card said. Tap **Nice** to dismiss; it must
      **not** come back on the next Stop/Play.
- [ ] 22. Confirm the **cash and Timber are actually in your profile** (top bar, Armory chip), not
      just on the card — they were banked wave by wave during the run, before the trip home.
- [ ] 23. **Welcome-back chaining.** If a **welcome-back / offline card** also appears on this join
      (it will after a run of any length), confirm the order: **welcome-back card first**, its
      "Double it" offer fully visible and tappable, and the EXPEDITION REPORT only appears **after**
      you close it. The report covering the offer is the bug this check exists for.

### 3. Forced failures (each one is reachable from Studio)

- [ ] 24. **No API access.** Game Settings → Security → turn **Enable Studio Access to API
      Services OFF**, Play the hub, tap **Depart**. Confirm: Output warns **once**
      `[StudioBridge] handoff needs API access (Game Settings → Security → Enable Studio Access to
      API Services)`, a toast **"Departure failed — ForceTeleportFailure is on, or Studio has no
      API access"**, you **stay** on your plot with your city untouched, and you are **not**
      kicked. Turn API access back **ON** before continuing.
- [ ] 25. **`ForceTeleportFailure`, hub side.** Add Workspace boolean **`ForceTeleportFailure`** =
      **true** (or tap **Tele fail: OFF** on the debug strip so it reads **`Tele fail: ON`** in
      red). Tap **Depart**.
- [ ] 26. Confirm: the same "Departure failed…" toast, you **stay** in the hub with your profile
      re-loaded (cash/slots/income unchanged, no safe-mode card), the strip's button flips back to
      **`Tele fail: OFF`**, and the attribute is back at **false** (consumed once).
- [ ] 27. Tap **Depart** again with the lever now off. Confirm the normal handoff toast + kick, so
      the failure really was one-shot. Stop Play **without** opening the combat place — the record
      you just wrote is harmless (it expires after 15 minutes) but step 28 clears it.
- [ ] 28. **`ForceTeleportFailure`, return side.** Open `build/combat.rbxl`, Play (it boots from
      that record), tap **Ready** and then **Return**, having first set Workspace
      **`ForceTeleportFailure`** = **true**.
- [ ] 29. Confirm: the summary card appears, then a toast **"Studio can't teleport — reopen
      build/test.rbxl for the hub"**, and you are **put back into the run** (HUD still there, you
      are not kicked, not frozen, no error). Tap **Return** again — this time you are kicked
      normally.
- [ ] 30. **`ForceRegistryFailure`.** Back in `build/combat.rbxl`, add Workspace boolean
      **`ForceRegistryFailure`** = **true**, then Play and **Ready** up. Confirm Output shows
      repeated `[RunRegistry] … failed (attempt 1/2/3): …` warnings, that the **run still plays
      normally** (waves spawn, damage lands, rewards bank) and that **no red error** appears. This
      lever is sticky — set it back to **false** when you're done.
- [ ] 31. **Stale record.** Optional: leave a handoff unconsumed for **15+ minutes**
      (`handoffMaxAgeSeconds` 900) then open the combat place. Confirm it is ignored and the place
      falls back to `DebugMission`, with no error.

### 4. The Village run

Set up: `build/combat.rbxl`, `DebugMission` = `village`, Play, and use
**`DebugSetGear`** = **`melee=2,ranged=1`** (Iron Sword + Short Bow, power 57 — the recommended
loadout the balance table is written for). Expect **~8:26** and roughly **139K cash / 248 Timber /
35 Valor** for a full clear.

- [ ] 32. In the lobby confirm the HUD: title **`Raider Woods`**, wave line **`Lobby`**, a party row
      with your name and full HP, a **Ready** button and a **Return** button, and a wallet strip
      (cash · Timber · Valor).
- [ ] 33. Tap **Ready**. Confirm a **wave banner** and the wave line becoming **`Wave 1 / 10`**,
      with **`Alive n · Left m`** beside it.
- [ ] 34. Confirm **5 rust-coloured raiders** trickle in from the fence line (not all at once),
      walk at you, and telegraph each swing with a short windup before it lands.
- [ ] 35. **Melee.** Press **`1`** for the melee stance, then click three times in rhythm. Confirm
      damage numbers pop on each hit, the **third hit is bigger (the finisher)** and knocks the
      target back. Spamming faster than the combo window should simply drop hits — never an error.
- [ ] 36. **Ranged.** Press **`2`**, then **hold** the mouse button to draw and release. Confirm a
      longer hold does more damage than a tap, and that a shot into empty space does nothing (no
      error, no toast).
- [ ] 37. **Abilities.** Press **`Q`** (Whirlwind, 12 s) and **`E`** (Volley, 14 s) with enemies
      nearby (the **starter** Stick and Sling have no ability, so this needs the weapons from step 7).
      Confirm the ability button shows a **cooldown ring/timer**, that Whirlwind hits
      everything around you and knocks it back, and that **kills shorten both cooldowns**.
- [ ] 38. **Wave clear banks money.** When wave 1 clears, confirm a wave-clear banner, a
      **breather** (`Breather — wave 1 / 10`) with your HP regenerating, and that the **wallet strip
      cash and Timber go up at that moment**. Rewards are flushed per wave, not at the end.
- [ ] 39. **Tempo dot.** Watch the small dot by the wave line change colour as you clear faster or
      slower. At recommended power it should sit calm/neutral and **never** merge (a
      **`Waves 4 + 5`** line means you are out-pacing the stream — correct at high gear, unusual
      here).
- [ ] 40. **Boss.** Reach **wave 5**. Confirm the wave line becomes **`Boss — Raider Chief`**, a
      **boss health bar** appears at the top, the boss rig is visibly **bigger and dark red**, and
      on its death a boss-down banner plus a **Valor** bump in the wallet strip.
- [ ] 41. **Low HP.** When you drop below 30 % HP confirm a **red vignette** at the screen edges,
      and that it clears when you heal in the breather.
- [ ] 42. **Death.** Let yourself die (or set `DebugSetGear` = `melee=0,ranged=0` first). Alone,
      confirm the run **ends** with the summary card, that it carries the
      **"You went down — the rewards above are already banked"** line, and that the cash you had
      already earned is **still on the card**. Losing banked rewards on death is a bug.
- [ ] 43. **Full clear.** With `melee=2,ranged=1`, clear **wave 10** (Warlord). Confirm the summary
      card shows `Waves cleared 10 / 10`, kills, cash, Timber, Valor and a time near **8:26**.
- [ ] 44. **Mobile pass — 375×667 portrait.** Device Emulator, restart Play. Confirm: the attack
      button is bottom-right and comfortably thumb-sized, the two ability buttons sit beside it,
      the stance toggle is above them, the wave line / boss bar / party rows / wallet strip are all
      on screen and unclipped, and **nothing overlaps** the HP bar or the Return button.
- [ ] 45. At 375×667, fight a whole wave by **tapping only** (no keyboard). Confirm the soft-lock
      picks the nearest enemy in front of you and that a hold-to-draw works on touch.
- [ ] 46. **Mobile pass — 812×375 landscape.** Repeat 44-45. Confirm the HUD compresses rather than
      clipping, and the summary card fits with its Return button reachable.
- [ ] 47. On touch, confirm **reduced motion** is honoured: with Reduced motion ON in the hub's
      Settings panel, the camera kick and particle bursts are damped and nothing else changes.

### 5. Every lever, from the attribute and from the strip

Run these mid-fight in `build/combat.rbxl`.

- [ ] 48. Expand the top-left **`⚙ debug`** strip. Confirm the buttons: **Wave +1**,
      **Spawn raider / Spawn archer / Spawn brute**, **God: off**, **Kill all**, **Melee +1**,
      **Ranged +1**, **Bots +1**, **Bots −1**, **+25 mat**, **+10 Valor**.
- [ ] 49. `DebugWave` = `7` (or **Wave +1**). Confirm the next wave that starts is wave 7 and the
      wave line says so.
- [ ] 50. `DebugSpawn` = `brute` (or **Spawn brute**). Confirm one dark-red brute appears at a rim
      spawn and walks at you; the attribute resets to `""`.
- [ ] 51. `DebugGodMode` = **true** (or **God: off** → **God: ON**). Confirm you stop taking damage
      entirely; set it back to false and confirm damage resumes.
- [ ] 52. `DebugKillAll` = `1` (or **Kill all**). Confirm every alive enemy dies **with normal
      rewards** (wallet strip moves), not silently deleted.
- [ ] 53. `DebugSetGear` = `melee=4,ranged=4` (or **Melee +1** / **Ranged +1**). Confirm your **HP
      bar's maximum grows immediately** and your damage numbers jump. A tier that doesn't exist is
      ignored with `[DebugService] setGear: no melee tier N` and **no** error.
- [ ] 54. **`DebugBots` = `2`.** Confirm: two blue rigs named **Bot 1** and **Bot 2** join the
      party, **two extra rows** appear in the party list, they walk at enemies and deal damage,
      enemies target them, and the **wave count grows** (party of 3 spawns more enemies than a solo
      wave).
- [ ] 55. With the bots still in, clear a wave and then **Return**. Confirm the summary card shows
      **only your share** of the wave pools — bots' shares are discarded, so your cash is lower than
      the whole-wave total, never higher.
- [ ] 56. Set `DebugBots` = `0` and confirm both rows disappear cleanly.
- [ ] 57. `GrantMaterials` = `25` and `GrantValor` = `10` here (or **+25 mat** / **+10 Valor**).
      Confirm the wallet strip updates immediately and both attributes reset to `0`.

### 6. Two players in the arena (Local Server — multiplayer changed this milestone)

- [ ] 58. In `build/combat.rbxl`: **Test → Start** with **2 Players** (Local Server), `DebugMission`
      = `village`. Wait for both clients to spawn on the lobby pad.
- [ ] 59. Confirm each client's party list shows **both players** with their own Max HP, and that
      the run **only starts when both** have tapped **Ready** (Ready on one alone must not start
      wave 1).
- [ ] 60. Confirm a Ready **✓** set on client 1 is visible on client 2 within a second, and that
      once the run has started Ready can no longer be toggled.
- [ ] 61. Fight a wave on **both** clients. Confirm: each client sees the **same enemies in the same
      places**, damage numbers from the other player appear, enemies split their aggro, and the
      wave count is bigger than solo.
- [ ] 62. On wave clear, confirm **both** wallet strips update and that the two amounts **differ by
      damage done** — the player who did most of the damage gets most of the pool, and the one who
      did least still gets a floor, never zero.
- [ ] 63. Kill one player (let client 2 die). Confirm client 2 **respawns after ~8 s** at a player
      spawn while client 1 is alive, and that the run does **not** end.
- [ ] 64. Have both players die in the same wave. Confirm the run ends for both, each gets their
      **own** summary card with their **own** numbers, and rewards are kept.
- [ ] 65. On client 2 tap **Return** mid-run. Confirm client 2 is kicked (bridge) and **client 1's
      party list drops to one row** with the run continuing.
- [ ] 66. Confirm **no red errors** in either client's Output or the server's, then Stop.
- [ ] 67. In `build/test.rbxl`: **Test → Start** with **2 Players**. On each client open the
      **⚙ debug** strip and tap **Grant $10K**; confirm it pays **only the client that tapped it**
      (the remote is per player, unlike the attribute, which pays both).

### Report back

Tell Claude Code, in one message:

1. Did the round trip work end to end (Depart → kick → combat place from the record → Return →
   kick → hub → EXPEDITION REPORT with matching numbers)?
2. How long did a full 10-wave clear take at `melee=2,ranged=1`, and what cash / Timber / Valor did
   the summary show? (Expected ~8:26, ~139K / 248 / 35.)
3. Did the fight **feel** right — are waves 1-4 and 6-9 too empty, are the two boss waves the
   danger, did you ever merge waves?
4. Any lever that did nothing, any red error (with the step number), and anything clipped or
   untappable at 375×667 or 812×375.
5. Anything in the two-player pass that only one client saw.

### Not a bug — don't report these

- **Silence.** All 17 combat sound ids are `0` until the audio pass; the fight is meant to be mute.
- **Placeholder enemies.** Plain R15 rigs, recoloured by type (raider rust, archer olive,
  brute/boss dark red, bot blue). No enemy models exist yet.
- **Empty hands.** No weapon models yet — the swing and draw are procedural poses on your arms.
- **Other players' swings aren't animated.** Only your own character poses; the damage is real.
- **The kick.** Both Depart and Return end in a kick: that is the Studio stand-in for a teleport.
  Stop Play, open the other `.rbxl`.
- **The bow can fire a full-charge shot instantly** if you waited a while between shots — the
  charge is measured from your last shot. Known, fixed in C2.
- **The arena is plain.** Grass floor, fence and a few rocks; dressing is not part of C1.
- **ACTIVE RUNS is empty** unless you use `DebugFakeRuns`, and a fake run always refuses Join.
- **Boss HP does not scale with party size** — a duo kills a boss twice as fast. Open C2 ruling.

### Sign-off

- [ ] 68. All boxes above checked: the hub debug strip and levers, the bridge round trip with the
      EXPEDITION REPORT chained behind the welcome-back card, the four forced failures, a full
      Village run on desktop plus the 375×667 and 812×375 passes, every debug lever from both the
      attribute and the strip including `DebugBots = 2`, and the two-player Local Server pass.
- [ ] 69. Tell Claude Code "C1 expedition playtest passed" (or report the exact failure and step
      number).

## C2 — Co-op (party, join-in-progress, Mentor)

**Goal:** expeditions together. Hub party (invite + accept) departs as one group; anyone can join
a run mid-way from a grouped list; late arrivals and co-op deaths wait for the next wave; boss HP
grows with party size; carrying a newcomer pays a Mentor bonus; the party comes home together and
re-forms. Numbers: `docs/BALANCE.md` "C2". **This pass also covers the still-open C1 playtest** —
run C1 sections 2 and 4 once alongside it (or skim them if already done).

### Before you start

- Rebuild both places (`docs/MANUAL_STEPS.md` "C2" step 1). **Enable Studio Access to API
  Services** must be ON.
- Sections 1–4 and 6 are **Studio**. Section 5 is the **published game** with two accounts and
  needs both places republished first (`docs/MANUAL_STEPS.md` "C2" §4).
- **Local Server:** Studio **Test** tab → **Clients and Servers** → set players to **2** (or 3) →
  **Start**. One Server window + one window per player (`Player1`, `Player2`). Test players have
  **negative ids** (−1, −2), so they are never "friends" — expected.
- New levers (Workspace attributes; Studio only, inert when published):

  | Attribute | Place | Type | Effect | Debug strip button |
  |---|---|---|---|---|
  | `DebugFakeParty` | hub | number 0–3 | **sticky**: every player's party gets N fake members "Fake 1…N" | **Fake party +1 (n)** → after 3: **Clear fake party** |
  | `DebugFakeInvite` | hub | boolean | **consumed once**: an invite from fake leader "Fake 9" | **Fake invite** |
  | — | Expeditions | — | runs the real admission check on you and toasts the verdict | **Admit check** |

- Levers from C1 still used here: `GrantCash`, `DebugFakeRuns`, `ForceTeleportFailure` (hub);
  `DebugMission`, `DebugWave`, `DebugBots`, `DebugSetGear`, `DebugGodMode`, `DebugKillAll` (Expeditions).

### 1. Studio hub, solo — party UI through the levers (`build/test.rbxl`, Play)

- [ ] 1. Play. Zero red errors. Open **🗺 Expedition**. Top of the panel: **PARTY** header,
      hint "Invite players in this server to depart together.", buttons **Invite** and **Leave**.
- [ ] 2. Tap **Invite**. The picker says **"No one else is in this server."** and the button
      reads **Done**. Tap **Done** to close it.
- [ ] 3. Below Raider Woods: an **Open to public** toggle reading **ON** (default). Tap it → **OFF**,
      tap again → **ON**. (Overdrive stays hidden below Rebirth 1.)
- [ ] 4. Debug strip (bottom-left **⚙ debug**) → **Fake party +1 (0)**. Party strip shows
      **★ <you>** and **Fake 1**; the button now reads **Fake party +1 (1)**. Output warns
      `[PartyService] fakeParty lever: 1 Studio-only member(s) for <you>`.
- [ ] 5. Tap it twice more → 4 rows (you + Fake 1–3), button reads **Clear fake party**.
      Tap once more → strip back to just you.
- [ ] 6. **Attribute path:** Workspace attribute `DebugFakeParty` = `2` → two fakes appear within ~1 s;
      set it to `0` → they go. (It is sticky: the value stays until you change it.)
- [ ] 7. Set `DebugFakeParty` = `1`. As leader tap **Kick** on Fake 1's row → the row goes and the
      party dissolves to just you. Set the attribute back to `0`.
- [ ] 8. **Depart with fakes:** `DebugFakeParty` = `1`, then **Depart** on Raider Woods. Output
      warns `[ExpeditionService] Studio fake party member Fake 1 stays in the hub`, then the normal
      "Handoff saved — Stop Play, then open build/combat.rbxl" toast and a kick ~1 s later. Stop
      Play; set `DebugFakeParty` to `0` before the next Play. (The unused handoff expires in 15 min,
      or consume it by opening `build/combat.rbxl` once.)
- [ ] 9. Play again. Tap **Fake invite**. A card slides in: **"Party invite · 30s"**, body
      **"Fake 9 invited you to an expedition party"**, buttons **Decline** / **Accept**. The seconds
      count down; at 0 the card leaves by itself.
- [ ] 10. **Fake invite** again → **Accept**. Party strip: **★ Fake 9** and you. The Raider Woods
      tile is disabled with **"Your party leader picks the mission"**.
- [ ] 11. Tap **Leave** → strip back to just you, tile enabled again.
- [ ] 12. **Fake invite** → **Decline** → card closes, no party, no error.
- [ ] 13. **Grouped run list:** Workspace `DebugFakeRuns` = `3`. Under **JOIN A RUN**: an
      **OPEN RUNS** group with Fake 1 and Fake 3, a **FRIENDS** group with Fake 2. Each row: mission
      name, host, Wave N, 1/4, a **Join** button. No access code or server id anywhere.
- [ ] 14. **Join** on Fake 1 → toast "Departure failed — ForceTeleportFailure is on, or Studio has
      no API access", you stay (fakes are unjoinable by design). No red error.
- [ ] 15. Clear the fakes (wait, or Stop). With none: the list reads **"No runs to join right now."**

### 2. Studio hub, Local Server with 2 players — the real party

- [ ] 16. `build/test.rbxl` → Test → Clients and Servers → **2** players → Start.
- [ ] 17. Player1: Expedition → **Invite** → picker lists **Player2** → tap its **Invite** → it
      reads **Sent**. Player1's strip shows Player2 as pending with a countdown.
- [ ] 18. Player2: the invite card appears ("Player1 invited you…"). Tap **Accept**. **Both**
      windows now show **★ Player1** and **Player2** within ~1 s.
- [ ] 19. Player2: the tile is disabled with "Your party leader picks the mission".
- [ ] 20. Player1: **Kick** on Player2's row. Both strips update (Player2 back to solo, Player1 solo).
- [ ] 21. **Cooldown (be quick):** Player1 invites Player2, Player2 accepts at once, Player1 kicks
      at once, then re-invites **within 10 s of the first invite** → toast **"They can't be
      invited right now"**. After 10 s the invite goes through.
- [ ] 22. **Decline block:** Player2 taps **Decline**. Player1 re-invites at once → same
      "They can't be invited right now" toast; the invite only goes through after **60 s**.
- [ ] 23. **Expiry:** invite, let Player2 ignore it for 30 s. Card closes on Player2, the pending row
      disappears on Player1. (Kick on a pending row withdraws the invite early.)
- [ ] 24. **Leave:** re-form the party; Player2 taps **Leave** → both solo (a party of one dissolves).
- [ ] 25. Optional, 3 players: party of three; leader taps **Leave** → the next member who joined
      becomes ★ leader on every window.
- [ ] 26. **Group departure failure:** re-form Player1 + Player2. In the **Server** window's Explorer
      set Workspace `ForceTeleportFailure` = true. Player1 **Depart**. **Both** get the "Departure
      failed…" toast, **both** stay with cities intact, nobody kicked, attribute back to false.
- [ ] 27. **Group departure:** Player1 **Depart** again. **Both** get "Handoff saved — Stop Play,
      then open build/combat.rbxl" and **both** are kicked ~1 s later. Stop.

### 3. Studio Expeditions, Local Server with 2 players — the party run and group return

- [ ] 28. Open `build/combat.rbxl` → Clients and Servers → **2** players → Start (the two handoffs
      from step 27 are consumed). Both land in Raider Woods, party rows show **★ Player1** and Player2.
- [ ] 29. Player1 taps **Ready** alone → the run does **not** start. Player2 **Ready** → wave 1.
- [ ] 30. **Swings replicate:** Player1 does a 3-hit melee combo; on Player2's screen Player1's arms
      animate the combo (C1's "other swings aren't animated" is fixed).
- [ ] 31. **Co-op death:** let Player2 die while Player1 lives (Player1 can set `DebugGodMode`).
      Player2 reappears on the **LobbyPad**, banner **"You'll join at the next wave"**, party row
      **"back next wave"**; enemies ignore Player2 and Player2's attacks do nothing. At the next
      breather Player2 is moved into the arena at **full HP**. (This replaces C1 step 63's 8 s respawn.)
- [ ] 32. **Party effect:** Player1 `DebugSetGear` = `melee=10` (Plasma Edge). Stand next to Player2
      in a fight and press **Q**. A ring shows at Player1, a pulse on Player2, and Player2 gets the
      toast **"Rally from Player1"** with a visible heal. `melee=12` → **"War cry from Player1"** and
      Player2's damage numbers are ~25 % bigger for 6 s. Out of range (> 20 studs): nothing.
- [ ] 33. Each summary shows **"Your damage share N%"**. Finish or wipe the run.
- [ ] 34. **Group return:** the summary card counts **"Returning together in …"** from 15 s. At 0
      **both** are kicked with "Run over — Stop Play, then reopen build/test.rbxl". Stop.
- [ ] 35. Open `build/test.rbxl` → Clients and Servers → **2** → Start (within 15 min, before the
      handoff goes stale). Both get their EXPEDITION REPORT, and the **party re-forms**: both
      strips show ★ Player1 + Player2.
- [ ] 36. Repeat 27–29 once more, but this time Player2 taps **Return** on the summary **before**
      the countdown ends → Player2 goes home alone. In the hub afterwards: **no** party re-forms.

### 4. Studio Expeditions, solo — bots, admission, boss HP, Mentor, bow

Setup: in `build/test.rbxl` (Play, solo) buy at least one building, then **Depart** — the
departure saves your current income, which the Mentor check needs (> 0). Stop, open
`build/combat.rbxl`, Play (the handoff boots Raider Woods), `DebugSetGear` = `melee=2,ranged=1`.
To read server values: Test tab → **Client/Server** toggle → Server.

- [ ] 37. **Admit check** (combat debug strip, top-left) in the lobby → toast **"Admit check: ok"**.
- [ ] 38. `DebugBots` = `3` (Bot 1–3 join, 4 seats) → **Admit check** → **"Admit check: full"**.
      Set `DebugBots` = `2`.
- [ ] 39. **Boss HP:** `DebugWave` = `5`, **Ready**. When the Raider Chief spawns, select its
      **Humanoid** in the Server view: `MaxHealth` ≈ **2,476** (2.5× solo). Replay with
      `DebugBots` = `0` (and `DebugMission` = `village`): ≈ **990**.
- [ ] 40. **Mentor:** with 2 bots, kill the wave-5 boss while hitting it yourself. At the clear:
      **"+10 Valor · Mentor"** pops for you, and the summary later shows **"Mentor bonus +10 Valor
      (included above)"**. Nothing at all → check the setup (income must be > 0).
- [ ] 41. **Idle mentor gets nothing:** same setup, turn `DebugGodMode` on and do **not** attack
      during the boss wave; let the bots kill it (1–2 min). No Mentor popup.
- [ ] 42. **Bot added mid-wave waits:** during a wave set `DebugBots` +1. The new bot stands on the
      LobbyPad with **"joins next wave"** in its party row and enters at the next breather.
- [ ] 43. **Over:** `DebugWave` = `10`, let wave 10 start, **Admit check** → **"Admit check: over"**.
- [ ] 44. **Bow draw fix:** `DebugSetGear` = `ranged=1`, press **2**, wait 5 s without holding,
      then tap-release fast at an enemy → a **weak** shot (about half). Hold ~1 s and release → full
      damage. A strong shot from a quick tap after waiting is the old bug.
- [ ] 45. **Enemy colours** unchanged: raiders rust, archers olive, brutes/bosses dark red, bots blue.

### 5. Published game — two accounts (A = main, B = second, NOT friends)

Needs both places republished (`docs/MANUAL_STEPS.md` "C2" §4). Real teleports, no kicks.

- [ ] 46. **Solo round trip (C0 §9):** A joins the hub, notes cash / era / Power / Max HP / one slot
      level → **Depart** → teleported to Raider Woods, HP = Max HP. Ready, clear 1–2 waves,
      **Return** → back on A's plot, everything intact, EXPEDITION REPORT shown, welcome-back card
      pays the away time at full rate. No doubled or reset values.
- [ ] 47. **Public join mid-run:** A departs with **Open to public ON** and starts wave 1. B in the
      hub → Expedition → **OPEN RUNS** lists A's run (Raider Woods, A, Wave N, 1/4) within ~10 s.
      B taps **Join** during a wave → B lands on the LobbyPad with "You'll join at the next wave";
      A sees B as "joins next wave"; B enters at the next breather.
- [ ] 48. B taps **Return** mid-run → B goes home alone with a report; A's party list drops to 1.
- [ ] 49. **Friends-only hidden:** A departs again with **Open to public OFF**. B's list shows
      **"No runs to join right now."** for the whole run.
- [ ] 50. **Over:** with A's public run in B's list, once A reaches **wave 10** the row disappears
      from B's list within ~10 s. (If B taps Join on a stale row: toast "That run has moved past joining".)
- [ ] 51. **Party depart together:** get both in the same hub server (with no other players online
      they usually are; else friend B and use Join on A's profile). A invites B → B accepts →
      A **Depart**. Both land in **one** server with both party rows; the run starts only when both are Ready.
- [ ] 52. **Mentor (if A earns ≥ 8× B's income/s):** both hit the wave-5 boss. A gets
      "+5 Valor · Mentor"; B gets none.
- [ ] 53. **Group return:** let the run end. Both summaries count "Returning together in …"; at 0
      both land in the **same** hub server, each gets their report, and the party strip shows
      ★ A + B again.
- [ ] 54. **Crash exit:** B closes the app while in a run, then rejoins the hub → profile loads, no
      "already in a session" error, away time credited.
- [ ] 55. `full` (4 seats) cannot be reached with two accounts — covered by step 38.

### 6. Mobile (Device Emulator, Studio)

- [ ] 56. Hub at **375×667**: **Fake invite** → the card fits on screen, **Accept** and **Decline**
      are big enough to hit with a thumb (≥ 44 px), the countdown is readable, the city stays usable
      behind it.
- [ ] 57. `DebugFakeParty` = `3` → Expedition panel: 4 party rows, Kick buttons, **Invite** /
      **Leave**, **Open to public** toggle and the three run groups (`DebugFakeRuns` = `3`) all fit
      or scroll; nothing clipped.
- [ ] 58. Combat at **375×667** with `DebugBots` = `2`: party rows show ★, % and
      "joins next wave" without overlapping the HP bar; the waiting banner does not cover the
      attack button; the summary card's share, Mentor and "Returning together" lines fit with
      **Return** reachable.
- [ ] 59. Repeat 56–58 at **667×375 landscape**.

### Not a bug — don't report these

- Studio test players are never "friends" (negative ids); the FRIENDS group only shows fake runs.
- Every refusal of a fake run reads "Departure failed — ForceTeleportFailure is on…".
- A mid-run joiner is never in the re-formed party — only the original hub party re-forms.
- A joiner whose client never saw a member fight shows "joins next wave", not "back next wave".
- Other players' swings play a fixed-length pose (0.35 s), not their exact timing.
- Silence, placeholder rigs and empty hands (as C1).

### What a bug looks like here

- A party change seen by only one window; a pending invite that never expires.
- A non-leader able to Depart, or a fake-led party departing.
- One member teleported/kicked and the other left with no toast.
- A private run visible to a non-friend in another server; any access code or server id in a row.
- A joiner fighting (or being hit) before the next wave boundary.
- Boss HP not growing with party size; Mentor paid to an idle mentor or with zero saved income.
- A full-strength bow shot from a quick tap after waiting.
- After the group return: two different hub servers, or no party re-formed.
- **Any red error** in Output (client or server).

### Sign-off

- [ ] 60. Sections 1–4 and 6 in Studio, section 5 on the published game, plus the C1 pass.
- [ ] 61. Tell Claude Code "C2 co-op playtest passed" (and "C1 passed"), or the failing step number.
