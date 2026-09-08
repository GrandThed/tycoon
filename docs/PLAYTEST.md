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

- [ ] 1a. Open `build/test.rbxl` directly in Roblox Studio (File → Open, or double-click).
- [ ] 1b. OR: run `rojo serve` from the repo root in a terminal, then in Studio use the Rojo
      plugin → Connect (default port 34872). Use this path if you want live-sync while poking
      around; use 1a if you just want a quick boot check.

If `Packages/` is missing or the build is stale, run `wally install` then rebuild with
`rojo build -o build/test.rbxl` before opening (see `docs/MANUAL_STEPS.md` for exact commands).

### 2. Desktop boot check

- [ ] 2. Press **Play** (F5) in Studio, desktop/default view.
- [ ] 3. Open the **Output** window (View → Output).
- [ ] 4. Confirm you see `[Server] booted — tickRate=1` somewhere in the log.
- [ ] 5. Confirm you see `[Client] booted` somewhere in the log.
      (These two lines may appear in either order, interleaved with normal Studio noise —
      that's fine. Both must appear.)
- [ ] 6. Confirm there are **zero red error lines** in Output. Yellow warnings from Studio itself
      (not from our scripts) are OK; anything printed by our code should not be a warning either.
- [ ] 7. Confirm nothing renders on screen — no HUD, no buttons, no plots, no visible parts beyond
      the default baseplate/sky. This is expected for M0.
- [ ] 8. Stop Play (Shift+F5).

### 3. ServerStorage asset folders exist

- [ ] 9. In the **Explorer** window, expand `ServerStorage` → `Assets`.
- [ ] 10. Confirm four empty folders exist, named exactly: `Village`, `Boomtown`, `Metropolis`,
      `OrbitalColony`.
- [ ] 11. These folders should still be there even after re-running `rojo build` or reconnecting
      `rojo serve` — Rojo is configured to never delete unknown instances inside `ServerStorage`.
      (Nothing to hand-place yet at M0 — this just confirms the folders exist ahead of later
      milestones.)

### 4. Mobile emulation pass (required every milestone)

- [ ] 12. In Studio, open the **Device Emulator** (Test tab → Device, or the phone/tablet icon
      next to Play).
- [ ] 13. Pick a phone preset sized **375×667** (iPhone SE) — or set a custom resolution to
      375×667 if that exact preset isn't listed.
- [ ] 14. Press **Play** with the emulator active.
- [ ] 15. Repeat checks 4–7 above: both boot lines present, zero red errors, nothing renders.
- [ ] 16. Stop Play.

### What a bug looks like here

- Any red error in Output (missing ModuleScript, `require` failure, `--!strict` type error
  surfaced at runtime, etc).
- Either boot line missing or misspelled.
- `Assets` folders missing, renamed, or containing something unexpected.
- Anything visibly rendering (a sign this milestone accidentally shipped UI/plot code).

### Sign-off

- [ ] 17. All boxes above checked, on both desktop and 375×667 emulation.
- [ ] 18. Tell Claude Code "M0 playtest passed" (or report the exact failure) so `docs/PLAN.md`
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

- [ ] 1. From the repo root: `rojo build -o build/test.rbxl`. Confirm it succeeds with no errors.
      (Or: run `rojo serve` and connect via the Rojo plugin in Studio — see
      `docs/MANUAL_STEPS.md`.)
- [ ] 2. Open the built place (or the connected Studio session) and press **Play Solo** (F5).
- [ ] 3. Confirm `[Server] booted` and `[Client] booted` still print in Output with zero red
      errors (same check as M0 steps 4-6).

### 2. Claim a plot and buy the free first slot

- [ ] 4. Confirm your character spawns on the central hub platform (a round area near the middle
      of the map) — not directly on a plot.
- [ ] 5. Confirm the HUD top bar is visible: cash, income/s, and an era badge reading "Village"
      (Era 1).
- [ ] 6. Walk from the hub to any open plot on the ring around it. Confirm you see exactly one
      buy pad on your plot, labelled "Campfire", cost 0.
- [ ] 7. Walk onto the campfire pad. Confirm it buys automatically on touch (no confirm dialog)
      and a placeholder box (8x8x8 part with a floating name label reading "Campfire") appears
      in its place. This placeholder look is expected — no Kenney models are imported yet.
- [ ] 8. Confirm the campfire pad disappears and the HUD's cash/income figures update.

### 3. Income ticks

- [ ] 9. Stand still and watch the HUD cash number for 5-10 seconds. Confirm it climbs roughly
      once per second.
- [ ] 10. Remember: in Studio, income is multiplied **x100** for testing speed (a Studio-only
      debug lever; production has no such multiplier). Numbers will feel very fast next to the
      ~30-45 min design target for a full era — that's correct for this milestone.

### 4. Buy more slots — both methods

- [ ] 11. Tap the **Build** button to open the Build panel. Confirm slots are listed in a fixed
      order, and only the slot(s) whose `requires` you already own show a cost/Buy button —
      everything further down reads "Requires <slot name>" with no Buy button, and has no pad on
      the plot yet.
- [ ] 12. Buy 2-3 more slots using ONLY the Build panel's Buy button. Confirm each becomes owned
      (a new placeholder appears on the plot), cash drops by the listed cost, and the next slot's
      pad appears on the plot in the same order the panel lists it.
- [ ] 13. Buy 1-2 more slots by walking onto their pads on the plot instead of using the panel.
      Confirm the panel's row flips to "owned" without needing to reopen the panel.
- [ ] 14. Confirm pads only ever appear for the slot(s) currently unlocked by the `requires`
      chain, one step at a time, in the exact order the Build panel lists them — never a pad for
      a still-locked slot.

### 5. Level up — both methods

- [ ] 15. Walk close to a building you own. Confirm a **ProximityPrompt** appears (a key/button
      prompt hovering over it). Trigger it. Confirm the building's level increases by 1 and cash
      drops by the shown cost.
- [ ] 16. In the Build panel, find that owned building's row. Confirm it shows a "Level Up x1"
      button with a cost. Tap it several times. Confirm level increases and cash drops each time.
- [ ] 17. Keep leveling one building until it crosses a milestone level (10, 25, 50, or 100 —
      10 is reachable fastest with the x100 debug income). Confirm income visibly jumps by more
      than a normal level-up would right at that level (milestone levels double income).

### 6. Insufficient funds

- [ ] 18. Find a row (Buy or Level Up) you can't currently afford. Tap it anyway. Confirm the
      row/cost flashes red briefly and **nothing** is charged or purchased — cash and ownership
      unchanged.

### 7. Income-preview caveat (expected, not a bug)

- [ ] 19. In the Build panel, note a row's "income delta" preview (the "+X/s" next to Buy/Level
      Up). Buy or level that row, then compare against how much the HUD's income/s actually
      jumps. In Studio the real jump will be **about 100x bigger** than the preview said. This is
      expected — the preview doesn't apply the Studio-only x100 debug multiplier; in production
      (no debug multiplier) the two numbers match exactly. Do not report this mismatch as a bug.

### 8. Locked-row labeling

- [ ] 20. Scroll the Build panel to a slot several steps ahead of what you own. Confirm its row
      reads "Requires <name of the slot it needs>" (not just "Locked") and has no Buy button.

### 9. Mobile emulation pass (required every milestone)

- [ ] 21. Open the **Device Emulator** (Test tab → Device icon). Set the resolution to
      **375x667** (portrait, iPhone SE preset or custom).
- [ ] 22. Press Play. Open the Build panel. Confirm every button (Build toggle, Buy, Level Up)
      looks comfortably tappable (at least roughly 44x44 px, not a tiny sliver) and the panel
      does not overlap or hide the top HUD bar.
- [ ] 23. Switch the emulator to **667x375** (landscape). Confirm the Build panel is still fully
      on-screen and every button is reachable/tappable. (A polished landscape layout isn't
      required until M3 — for now the bar is just "nothing cut off, nothing untappable.")
- [ ] 24. Stop Play.

### 10. Two-player test (multiplayer isolation) — Local Server mode

- [ ] 25. In Studio, use **Test → Start** with **2 Players** (Local Server — not Play Solo).
- [ ] 26. Confirm each of the two player windows spawns on the hub, then claims a DIFFERENT plot
      on the ring (not the same one).
- [ ] 27. As Player 1, walk onto Player 2's plot and try touching one of Player 2's buy pads (or
      open the Build panel while standing there and hit Buy). Confirm nothing happens — no
      purchase goes through and Player 2's cash/ownership is unaffected.
- [ ] 28. Close Player 2's client window (have them leave). Confirm Player 2's plot resets: its
      pads and placeholder buildings disappear and the plot becomes free again.
- [ ] 29. If Player 2 rejoins, confirm they start over completely (0 cash, no owned slots, a
      freshly claimed plot) — expected, persistence isn't built until M2.
- [ ] 30. Stop the test session.

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

- [ ] 31. All boxes above checked (M0 checklist re-run + all M1 sections), on desktop, 375x667
      emulation, 667x375 landscape emulation, and the 2-player Local Server test.
- [ ] 32. Tell Claude Code "M0 and M1 playtest passed" (or report the exact failure and step
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

- [ ] 1. In Studio: **Game Settings** (Home tab) → **Security** tab.
- [ ] 2. Turn **"Enable Studio Access to API Services"** ON. Click Save.
- [ ] 3. Press **Play** (F5). Open **Output**.
- [ ] 4. Look for one of these two lines (printed once, from ProfileStore):
      - `[ProfileStore]: Roblox API services available - data will be saved` → real
        persistence is ON, continue with confidence.
      - `[ProfileStore]: Roblox API services unavailable - data will not be saved` → still
        mocked (setting didn't take, or you're in a context Studio blocks — e.g. Team Create
        without publish rights). Fix this before trusting sections 3 and 4 below.
- [ ] 5. Stop Play.

### 2. Persistence — buy, stop, rejoin, restored instantly

- [ ] 6. Press Play. Claim a plot, buy 3-4 slots (pads or panel), level one of them up twice.
      Note your cash, which slots you own, and that building's level.
- [ ] 7. Stop Play (Shift+F5) immediately — no need to wait.
- [ ] 8. Press Play again (same Studio session or a fresh one, doesn't matter).
- [ ] 9. Confirm: the moment your plot loads, cash matches what you noted, the same slots are
      already owned with their placeholders in place, and the leveled building shows the same
      level — **no reveal tweens or sounds play** (bulk restore, not 24 individual reveals).
- [ ] 10. Confirm the Build panel opens already showing everything as owned/leveled, matching
      the plot.

### 3. Offline earnings toast

Requires real API access (section 1, step 4 showed the "available" line).

- [ ] 11. Press Play, own at least 3-4 income-producing slots so income/s is clearly nonzero.
      Note the income/s shown in the HUD.
- [ ] 12. Stop Play. Wait at least **65 seconds** real time (a coffee-break pause, not a rush).
- [ ] 13. Press Play again. Confirm a small toast appears near the top of the screen reading
      something like "You earned $X while away — <time> offline" and auto-dismisses after a
      few seconds without blocking any taps underneath it.
- [ ] 14. Confirm the granted amount is plausible: roughly (income/s at the moment you stopped)
      × (seconds away) × 0.5 (50% offline efficiency) — it will not be exact since income/s
      may have changed right before you stopped, but it should be the right order of magnitude,
      not the full 100% rate and not zero.
- [ ] 15. Immediately press Play a second time (rejoin again right away, well under 60 s this
      time). Confirm **no toast appears** — too little time passed.
- [ ] 16. If this is a brand-new profile's very first-ever join (never played before), confirm
      no toast appears on that first join even if `lastSeen` logic is new — nothing was earned
      before you existed.

### 4. Era advance — Village to Boomtown

Use a fresh or near-complete profile. With the ×100 debug multiplier, owning all 24 Era 1 slots
should take well under the ~40 min real-time design target.

- [ ] 17. Buy and own **all 24 slots** of Era 1 (Village), including the **monument** (last
      slot in the Build panel list).
- [ ] 18. Confirm a gold **"Advance Era → Boomtown"** banner appears pinned at the top of the
      Build panel's slot list, above all the slot rows.
- [ ] 19. Tap the banner. Confirm a confirm dialog pops up titled "Advance to Boomtown?"
      showing:
      - a highlighted "Earn +N Legacy" line with a specific number (not zero, not blank)
      - "Resets: cash, buildings, levels, and your plot"
      - "Keeps: Legacy, era progress, rebirth count, and stats"
      - Cancel and "Advance Era" buttons
- [ ] 20. Tap **Cancel** (or tap outside the card). Confirm nothing changes — still Era 1, still
      24/24 owned, banner still there.
- [ ] 21. Reopen and tap **Confirm** ("Advance Era"). Confirm:
      - the plot rebuilds with a visibly different base color (Boomtown = dusty brown, vs
        Village's green)
      - cash resets to 0
      - the Build panel now lists a fresh set of 24 rows for Boomtown, all locked/unowned
        except the free first slot's pad
      - the top bar's **Legacy** number increased by exactly the amount the dialog showed
      - the era badge reads "ERA 2" / "Boomtown"

### 5. Repeat to Era 4 and Rebirth

- [ ] 22. Repeat step 17-21's pattern to advance Boomtown → Metropolis (base recolors to
      asphalt gray) and Metropolis → OrbitalColony (base recolors to dark regolith/near-black).
      Confirm Legacy keeps climbing each time and never resets.
- [ ] 23. Own all 24 OrbitalColony slots including its monument. Confirm the banner now reads
      **"Rebirth → Era 1"** instead of "Advance Era".
- [ ] 24. Tap it. Confirm the confirm dialog titled "Rebirth?" shows:
      - a highlighted "Earn +N Legacy" line
      - "Your <current Legacy> Legacy is KEPT"
      - a "Rebirths: 0 → 1 — future eras grant more Legacy" line
      - "Start over in Era 1 with your permanent bonuses"
      - Resets/Keeps lines (cash/buildings/levels/plot reset; Legacy/rebirth count/stats kept)
- [ ] 25. Tap **Rebirth**. Confirm you land back in Era 1 (Village, green base, "ERA 1" badge),
      cash 0, all 24 Village slots locked again except the free first one, and the top bar's
      Legacy number is the PRE-rebirth Legacy **plus** the amount the dialog showed (Legacy is
      never lost on rebirth).
- [ ] 26. Open the Build panel and confirm the prestige info reflects rebirth count 1 (visible
      the next time you reach the Rebirth dialog again — its "Rebirths: 1 → 2" line — or via
      any rebirth-count display the build has).

### 6. Exploit spot-check (advance-then-disconnect)

This targets the fix for a reviewed Critical: advancing/rebirthing then disconnecting before
the next income tick used to let a rejoin pay offline earnings at the OLD (just-completed)
era's income rate into the NEW, empty era.

- [ ] 27. With real API access on (section 1), get to a point where you're one tap away from
      Advance Era or Rebirth and your income/s is clearly high (ideally the highest income/s
      you've had all session — e.g. right after finishing OrbitalColony).
- [ ] 28. Tap Confirm on the Advance Era / Rebirth dialog, then **immediately** Stop Play
      (within a second or two — before you'd see even one income tick land in the new era).
- [ ] 29. Wait at least 65 seconds real time, then Press Play again.
- [ ] 30. Confirm: **no welcome-back toast appears, or if one appears the amount is ~0** — not
      the old era's high income rate applied to the elapsed time. Cash should read 0 (or
      whatever the tiny post-advance amount is), never a large windfall.
- [ ] 31. If a large offline grant appears here, this is a regression of the fixed exploit —
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

<!-- M3 section appended here once M3 ships. Do not delete completed sections above. -->
