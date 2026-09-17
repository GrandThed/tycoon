# Era City Tycoon — Manual Steps

Cumulative log of everything that requires Roblox Studio or the Creator Hub (Claude Code cannot
do these). Newest milestone at the bottom. Items already done are checked off — leave them
checked as a record; don't uncheck on re-read.

Commands below are written for **PowerShell** (the toolchain is on the PowerShell PATH).
From Git Bash instead, prefix each command with:
```
export PATH="$HOME/.rokit/bin:$PATH"
```

---

## M0 — Scaffold

### 1. One-time toolchain setup

- [x] 1. If you haven't already, install Rokit, then from the repo root run:
      ```
      rokit install
      ```
      This restores the pinned versions from `rokit.toml`: rojo 7.7.0, wally 0.3.2,
      stylua 2.5.2, selene 0.31.0, luau-lsp 1.69.0.
- [x] 2. Install the **Rojo plugin** in Roblox Studio, matching **Rojo 7.7**:
      - Studio → Toolbox → search "Rojo" → install the plugin by CodeKu / Rojo team, OR
      - In Studio: Plugins tab → Manage Plugins → get the Rojo plugin from the Creator Store.
      - Confirm the plugin's version shows 7.7.x when you open it (Plugins tab → Rojo icon).
      Mismatched plugin/CLI major versions will refuse to connect.

### 2. First build

- [x] 3. From the repo root, if `Packages/` is missing (first checkout, or after pulling changes
      to `wally.toml`), run:
      ```
      wally install
      ```
      This installs Signal (sleitnick) into `Packages/`. ProfileStore is intentionally not
      installed yet — it lands at M2 (see `docs/PLAN.md`).
- [x] 4. Build the place file:
      ```
      rojo build -o build/test.rbxl
      ```
      Already verified green by QA for M0 — you only need to re-run this if you've pulled new
      changes and want a fresh `.rbxl`.

### 3. Opening the project in Studio (pick one)

- [x] 5a. **Quick check:** double-click `build/test.rbxl` (or File → Open in Studio) to open the
      built place directly. Rebuild first (step 4) if you've synced new changes.
- [x] 5b. **Live sync (optional, for poking around while iterating):**
      1. From the repo root, run `rojo serve`.
      2. In Studio, open a place (any new baseplate is fine), open the Rojo plugin, click
         **Connect** (default `localhost:34872`).
      3. Leave the terminal running `rojo serve` open while Studio is connected.

### 4. Nothing else to do in Studio for M0

- [x] 6. No meshes, audio, game passes, or developer products yet — those start at M3/M4. The
      `ServerStorage/Assets/{Village,Boomtown,Metropolis,OrbitalColony}` folders already exist
      from the Rojo sync; leave them empty for now.

---

## M1 — Playable loop

**Nothing new is required in Studio or the Creator Hub for M1.** No meshes to import, no audio
to upload, no game passes or developer products to create, no IDs to paste anywhere. Mesh
import starts at M3; passes/products start at M4.

- [x] 1. If you pulled new changes since M0, rebuild: `rojo build -o build/test.rbxl` (or re-run
      `rojo serve` and reconnect the Rojo plugin if you're using live sync). Exact commands are
      in the M0 section above (§2-3).
- [x] 2. That's it — go run `docs/PLAYTEST.md` M1 section.

---

## M2 — Persistence & eras

### 1. Enable Studio API access (do this first — most important new step)

Progress now saves via ProfileStore, but Studio blocks real DataStore calls by default. Without
this enabled, ProfileStore silently falls back to an in-memory mock: the game still behaves
correctly for a single Play session but **wipes on every Stop** — you will not see true
persistence or offline earnings without doing this.

- [x] 1. In Studio, open the place (`build/test.rbxl` or via `rojo serve`).
- [x] 2. Home tab → **Game Settings**.
- [x] 3. **Security** tab (left sidebar of the Game Settings window).
- [x] 4. Toggle **"Enable Studio Access to API Services"** to ON.
- [x] 5. Click **Save**.
- [x] 6. This setting is per-place and persists across Studio sessions once saved — you only
      need to do this once per place file, not before every Play.
- [x] 7. How to tell mock vs real at any time: Press Play, open **Output**, look for one line
      printed once by ProfileStore:
      - `[ProfileStore]: Roblox API services available - data will be saved` = real, persists.
      - `[ProfileStore]: Roblox API services unavailable - data will not be saved` = mock,
        wipes on Stop. If you see this after enabling the setting above, try re-saving Game
        Settings, or check you're not in a Team Create session without publish rights (a known
        cause of Studio API access being blocked regardless of the setting).

### 2. Install the new server dependency

- [x] 8. From the repo root, run:
      ```
      wally install
      ```
      This now also populates **`ServerPackages/`** with ProfileStore (in addition to
      `Packages/` for Signal, as before). Re-run this any time `wally.toml`/`wally.lock`
      change — safe to re-run even if nothing changed.
- [x] 9. Rebuild: `rojo build -o build/test.rbxl` (or reconnect `rojo serve` if using live
      sync). Confirm it succeeds with no errors — this is also QA's build gate.

### 3. Nothing needed on Creator Hub for M2

- [x] 10. No game passes, developer products, meshes, or audio yet — those start at M3
      (meshes/audio) and M4 (passes/products). Nothing to create or paste IDs for this
      milestone.
- [x] 11. That's it — go run `docs/PLAYTEST.md` M2 section (run it together with the M0 and M1
      sections per the combined playtest gate).

---

## M3 — Presentation

### 1. Rebuild first

- [x] 1. If you pulled new changes since M2, rebuild: `rojo build -o build/test.rbxl` (or
      re-run `rojo serve` and reconnect the Rojo plugin). Full commands in the M0 section above.
      No new dependencies this milestone (`wally install` not required unless `wally.toml`
      changed).

### 2. Kenney mesh import (optional this milestone — the game works with placeholders)

The game is fully playable and presentable with **zero** imported models — every slot falls
back to a tinted placeholder box automatically. Import meshes whenever you have time; nothing
breaks if you stop partway. Full list of what to import: `docs/ASSET_MANIFEST.md` (regenerate
it any time with `py tools/gen_asset_manifest.py` after editing an era config).

- [ ] 2. **Import scale — pick ONE and record it here before importing anything:**
      `1 Kenney unit = _____ studs` (fill in once you've imported a standard house and confirm
      it looks about **8 studs wide** in Studio; reuse the exact same scale for every kit and
      every era so all four eras sit at a consistent size).
- [ ] 3. For each model in `docs/ASSET_MANIFEST.md`:
      1. Studio → **Avatar** tab (or Insert) → **3D Importer**.
      2. Load the kit's **FBX or OBJ** file (from the suggested Kenney pack in the manifest's
         `Kit` column).
      3. Confirm the kit's **colormap texture** is applied (the importer usually auto-detects
         it if the texture file sits next to the mesh — verify the model isn't grey/untextured
         before importing).
      4. Apply the import scale from step 2.
      5. Import as a single **`Model`**.
      6. Set the model's **`PrimaryPart`** to a part at the **base-center** (so it sits flush on
         the plot with no floating/sinking).
      7. Select every part inside the model and set **`Anchored = true`**.
      8. Set **`CanCollide = true`** only for large structures (buildings, walls, the monument);
         small props/decor can stay `CanCollide = false`.
      9. Rename the `Model` to **exactly** the manifest's `modelName` column (PascalCase, no
         spaces — e.g. `HouseSmallA`, not `House Small A` or `housesmalla`).
      10. Place it at `ServerStorage/Assets/<EraName>/<modelName>` — `<EraName>` is the era's
          folder name from the manifest header (`Village`, `Boomtown`, `Metropolis`,
          `OrbitalColony`), NOT the display name.
      11. Tick the checkbox in that row of `docs/ASSET_MANIFEST.md` once done (regenerating the
          manifest later will reset checkboxes — re-tick after any regeneration, or import in a
          batch right before your next docs-keeper pass).
- [ ] 4. **VIP variants (optional, can skip entirely for now):** same process, placed at
      `ServerStorage/Assets/<EraName>_VIP/<modelName>` with the same name. A missing VIP variant
      silently falls back to the normal model — never an error. VIP skins aren't driven by
      anything yet (`passes.VIP` flips at M4); import these later if at all.
- [ ] 5. Ground/roads/props (optional, spec §8): Nature Kit trees/rocks for Era 1–3 edges, City
      Kit Roads for Era 2–3, Space Kit floor tiles for Era 4. These aren't config-driven slots —
      place them by hand around the plot ring however looks good; no naming convention applies.

### 3. Audio upload — **DONE (2026-09-09), scripted**

The nine event sounds are uploaded and their ids are committed in
`src/shared/Config/Sounds.json`. This is no longer a manual Studio task: it is done by
`py tools/upload_audio.py`, which uploads through Roblox Open Cloud and writes the ids back.

- [x] 6. Kenney packs downloaded to `assets/` (CC0, kenney.nl/assets): Interface Sounds,
      Casino Audio, Impact Sounds, Music Jingles. The folder is gitignored — the zips are
      re-downloadable, so they stay out of the repo.
- [x] 7. Uploaded via Open Cloud. Credentials live in `.env` (gitignored; `.env.example` is the
      template): an API key scoped to **Assets → write** for the creator that owns the place,
      plus `ROBLOX_CREATOR_TYPE`/`ROBLOX_CREATOR_ID`. The **experience id is not used** for
      audio — asset creation is scoped to the creator, not a place.
- [x] 8. The nine ids are in `Sounds.json`. Which file went where is recorded in
      `tools/audio_map.json`.

**Upload quota — read before uploading anything else.** Open Cloud allows **10 audio uploads
per calendar month** on an account that is not ID-verified, **100** on one that is. This
account is ID-verified (Settings → Account Info shows age group and birth date verified), so
13 of 100 slots are spent for September 2026 (the nine event sounds plus the four ambient loops). The tool never re-uploads a key whose id is already non-zero, so
re-running it is safe and cheap.

**To change a sound you do not like:**

1. `py tools/upload_audio.py --audition` extracts each pick plus three alternates to
   `assets/audition/<soundKey>/` so you can listen. Spends no quota.
2. Edit that key's `pick` in `tools/audio_map.json`.
3. Set that key's `"id"` back to `0` in `src/shared/Config/Sounds.json`.
4. `py tools/upload_audio.py` — it uploads only keys sitting at `0` and leaves the rest alone.

`--dry-run` shows exactly what would upload without calling anything.

- [x] 9. **Ambient loops — DONE (2026-09-09).** Four CC0 loops from OpenGameArt (RandomMind
      "Medieval: The Bard's Tale" loop, Tozan "Old West Style", TinyWorlds "Scifi City - Ambient
      Loop", wipics "Outer Space Loop") uploaded via `py tools/upload_audio.py`, which now also
      handles loose files listed under `ambient` in `tools/audio_map.json`. The Kenney packs
      above are all one-shots, which is why the loops came from a different source. Not yet
      heard in Studio — `docs/PLAYTEST.md` "Post-M6 — Ambient era loops" is the check.

**If a sound is silent in Studio:** uploaded audio starts private and is moderated, so give it
a few minutes. If it never plays, check the asset on create.roblox.com — if it was rejected,
set that id back to `0` rather than leaving the config pointing at a dead asset. An id of `0`
is silent by design and never an error.

### 4. Credits line

- [ ] 10. Kenney assets are CC0 — legally no attribution is required. Still add one line to the
      game's Creator Hub description crediting Kenney (e.g. "3D models and sound from
      kenney.nl"). README already carries this credit; this step is just the in-game
      description.

### 5. Nothing else needed for M3

- [x] 11. No game passes or developer products yet — those start at M4 (next section, once M4
      ships). Nothing to create or paste IDs for on Creator Hub this milestone beyond audio
      (step 3) and the optional mesh imports (step 2).
- [x] 12. That's it — go run `docs/PLAYTEST.md` M3 section.

---

## M4 — Monetization & analytics

The game ships with every game-pass/product `id` at `0`. **`id: 0` means "hidden, never
prompted, never granted"** — no Shop button, no "Double it" button, no prompts anywhere, no
errors. You can create the three passes and four products **one at a time, in any order**, paste
each id in, and the game stays correct at every step (test the ones you've created, the rest
stay invisible). You do **not** have to create all seven before testing any of this milestone.

### 1. Rebuild first

- [x] 1. If you pulled new changes since M3, rebuild: `rojo build -o build/test.rbxl` (or
      re-run `rojo serve` and reconnect the Rojo plugin). No new dependencies this milestone
      (`wally install` not required unless `wally.toml` changed).

### 2. Read the pricing guidance before creating anything

`docs/BALANCE.md` ("Cash packs and the era cap") derives this from the actual sim numbers —
worth reading before you pick Robux prices:

- The three cash packs (`Cash30m`, `Cash2h`, `Cash8h`) are *nominally* 30/120/480 minutes of
  income, a 1 : 4 : 16 ratio. But each pack is also capped at a fraction of the current era's
  total slot cost (10% / 25% / 50%) so a purchase can never skip an era. For all but the first
  2–14% of every era, that cap is what actually pays out — and the capped ratio is **1 : 2.5 : 5**,
  not 1 : 4 : 16.
- If you price the packs at the nominal 1 : 4 : 16 ratio (e.g. the big pack 16× the small one),
  the big packs are **worse value than the small one** for 86–98% of every era — the opposite of
  normal "bigger bundle, better value" pricing, and it stays that way for almost the whole game.
- **Recommendation: price roughly 1 : 2.2 : 4.2** (`Cash2h` at most 2.5× `Cash30m`'s price,
  `Cash8h` at most 5×). That keeps "bigger bundle is slightly better value" true in every era
  phase. This is a ratio, not an absolute price — pick whatever base Robux amount feels right for
  `Cash30m` and scale the other two from it.
- `DoubleCash`, `OfflinePro`, and `VIP` are permanent passes with no cap math — price those
  however feels right for a one-time permanent perk (typical Roblox tycoon pass pricing).

### 3. Create the game passes (Creator Hub)

For each of the three passes below: Creator Hub → your experience → **Monetization** → **Passes**
→ **Create a Pass**. Upload any icon (placeholder is fine, swap later), set a name/price, save,
then copy the numeric **Pass ID** from the pass's page URL or the passes list.

- [x] 2. Create **`DoubleCash`** ("Double Cash" — 2× income forever). Paste the id into
      `src/shared/Config/Monetization.json` → `passes` → the entry with `"key": "DoubleCash"` →
      `"id"`. Leave `"key"` exactly as it is — only edit `"id"`.
- [x] 3. Create **`OfflinePro`** ("Offline Pro" — offline cap 8h→24h, efficiency 50%→100%). Paste
      the id into the `"key": "OfflinePro"` entry's `"id"`.
- [x] 4. Create **`VIP`** ("VIP" — +10% income, VIP name tag, gold plot sign, VIP building
      skins). Paste the id into the `"key": "VIP"` entry's `"id"`.

### 4. Create the developer products (Creator Hub)

For each of the four products below: Creator Hub → your experience → **Monetization** →
**Developer Products** → **Create a Product**. Same flow — name, price, icon, save, copy the
numeric **Product ID**.

- [x] 5. Create **`Cash30m`** ("30 Minutes of Cash"). Paste the id into `products` → the
      `"key": "Cash30m"` entry's `"id"`.
- [x] 6. Create **`Cash2h`** ("2 Hours of Cash", priced ~2.2× `Cash30m` per the guidance above).
      Paste into `"key": "Cash2h"`'s `"id"`.
- [x] 7. Create **`Cash8h`** ("8 Hours of Cash", priced ~4.2× `Cash30m`). Paste into
      `"key": "Cash8h"`'s `"id"`.
- [x] 8. Create **`DoubleOffline`** ("Double it" — doubles the most recent offline grant; only
      ever offered on the welcome-back card, never in the Shop). Paste into
      `"key": "DoubleOffline"`'s `"id"`. Price this low — it's a small impulse buy tied to one
      welcome-back moment, not a bundle.
- [x] 9. Double-check every pasted value is a **numeric id**, not `0`, and that you did not touch
      any `"key"`, `"minutes"`, or `"capFraction"` field — those are frozen contract values, not
      yours to edit.

### 5. Enable Premium payouts (optional but recommended)

- [x] 10. **Nothing to do for the Premium multiplier.** (Corrected 2026-09-09 — an earlier
      version of this step told you to enable "Premium Payouts". That was wrong twice.)
      - There is no such setting any more. "Premium Payouts" became Engagement-Based Payouts,
        which Roblox deprecated on 2025-07-24 and replaced with **Creator Rewards**
        (`Recompensas del creador` in the Monetization sidebar). It is automatic; that page
        only reports earnings.
      - It was never related to our multiplier anyway. Creator Rewards is Roblox paying **you**
        for Premium engagement. Our 1.1× is the game paying **the player**, decided in-game by
        `player.MembershipType == Enum.MembershipType.Premium` (`EconomyService.luau`), and it
        works regardless of any payout program.
      - The only Monetization sidebar entries M4 needs are **`Pases`** (game passes) and
        **`Productos del desarrollador`** (developer products), both covered above.

### 6. Rebuild and test in Studio

- [x] 11. After pasting ids, rebuild: `rojo build -o build/test.rbxl` (or resync via
      `rojo serve`). Ids are read from config, not remotes — no server-side redeploy step beyond
      a normal rebuild/sync.
- [x] 12. Run `docs/PLAYTEST.md` M4 Phase A first (all ids still `0`, i.e. before this section —
      already true if you're doing this for the first time) to confirm the baseline is silent,
      then Phase B once you've pasted at least one real id.

### 7. Testing purchases — read this before you tap "Buy" in Studio

- [x] 13. **Developer product purchases inside Studio Play-testing are real-ish**: Studio uses
      your live Roblox account and can prompt a real Robux confirmation for a real product (game
      passes in Studio are typically mocked/free for the owner, but don't assume — the safest
      assumption is that any purchase you complete in Play mode may actually charge Robux).
      Use an account you're comfortable spending test Robux from, and don't leave a test session
      unattended near a purchase prompt. If you want to avoid any charge, create the products but
      don't tap through the purchase confirmation — just confirm the prompt appears and cancel it.

### 8. Accepted risks (recorded here per the lead's ruling — not bugs, don't report them)

- [x] 14. **`DataService.SaveAsync` durability caveat — RETIRED by M5.** ~~`SaveAsync` wraps
      ProfileStore's `Profile:Save()`, which is non-yielding — a `true` return means "accepted
      into an active session", not "durably written to the DataStore yet".~~ Replaced this
      milestone: `SaveAsync(player, confirm)` now waits on ProfileStore's `OnAfterSave` (up to a
      10 s timeout) before returning `true`, and `ProcessReceipt` only reports
      `PurchaseGranted` once the grant + purchase id are confirmed durably written. The cost is a
      visible ~1–2 s delay on a test purchase (`docs/PLAYTEST.md` M5 section 5) — that delay is
      expected, not a bug.
- [x] 15. **Open `DoubleOffline` reservation — RETIRED by M5, narrowed to a smaller residual.**
      ~~If a player leaves with a "Double it" offer reserved but not completed, the reservation
      was simply dropped.~~ Replaced this milestone: the reservation is now persisted to the
      profile (`pendingDoubleOfflineAmount`, schema v2) and survives a session boundary — a
      receipt that arrives in a later session grants correctly. See item 17 below for the new,
      smaller residual risk this leaves.
- [x] 16. **Analytics events are silent in Studio by design.** `slot bought`, `level-up`,
      `offline grant`, `product grant`, and `legacy on advance/rebirth` events only actually
      appear on the Creator Hub analytics dashboards for a **published** place with analytics
      enabled. You will not see anything on a dashboard from Studio Play-testing — that's
      expected, not a bug to report.
- [x] 17. **New (M5): residual `DoubleOffline` double-settle edge.** In the rare case where an
      old receipt (from a session before the one where the reservation was made) and a new
      reservation both try to settle in the same session, only one grants — the other grants `0`
      with a `warn` logged server-side, not an error. Lower-frequency than the M4 risk it
      replaces (item 15) since the common "leave with the dialog open" case is now handled
      correctly. Not reproducible on demand in Studio; don't chase it in a normal playtest.
- [x] 18. **New (M5): neighbours bonus doesn't exclude safe-mode players.** A player stuck in
      safe mode (load failure, no plot, no state) still counts toward `neighborsMult` for other
      players in the server (+3% each, capped at +27%) even though they aren't really playing.
      Reviewer-flagged nit, deferred by the lead as low-impact (safe mode is rare and the bonus
      is small and uncapped-in-practice-only-at-9-players); not a bug to report, and not planned
      for a fix this milestone.

<!-- M4 section complete. Do not delete completed sections above. -->

---

## M5 — Hardening

Nothing new to create on the Creator Hub this milestone — all passes/products already exist
from M4. This section is a rebuild, a note on how to exercise the new failure-handling UX in
Studio, and two reminders carried forward from earlier milestones.

### 1. Rebuild first

- [x] 1. If you pulled new changes since M4, rebuild: `$env:PATH = "$HOME\.rokit\bin;$env:PATH"`
      (PowerShell) then `rojo build -o build/test.rbxl` (or reconnect `rojo serve`). No new
      dependencies this milestone (`wally install` not required — `wally.toml` is frozen for
      M5). `luau-lsp analyze` needs a fresh sourcemap since `LoadScreen.luau` is new:
      `rojo sourcemap default.project.json -o sourcemap.json`.

### 2. Forcing a load failure for the playtest

`docs/PLAYTEST.md` M5 section 2 has the exact steps. Summary: this is a **Studio-only debug
attribute**, not a DataStore trick — ProfileStore retries its own throttled calls internally and
never lets a throttle reach our code, so there is no reliable way to fail a load from outside
it. `DataService` instead reads a boolean **`ForceLoadFailure`** attribute on **Workspace**:
while it is `true`, every load attempt for every player fails **immediately** (before any
DataStore call is even made — no multi-second backoff to wait out), landing on the "failed"
card. It is ignored entirely in a published game. Set it to `false` (or delete it) and tap
**Retry** to recover without a rejoin — the load then succeeds normally. **Always remove the
attribute before continuing to any other playtest section**, or every subsequent load will fail
too. Output logs a `[DataService] ForceLoadFailure attribute set — simulating a load failure
for <name>` warn line each time it triggers, which is expected, not an error.

Session-lock contention (a second overlapping Studio session on the same account) is a separate,
gentler check that does **not** use this attribute — that one should resolve itself within ~40 s
without ever reaching "failed", and is the case that actually exercises the "Still working…"
line (the forced-failure lever above fails too fast to show it).

### 3. Robux pricing ladder — still your call, still 1 : 2.2 : 4.2

Carried forward from M4, unchanged by the M5 balance pass (`docs/BALANCE.md` "M5 — rebirth laps
and the second balance pass" confirms nothing moved). Whenever you actually set or revisit Robux
prices for `Cash30m` / `Cash2h` / `Cash8h` on the Creator Hub, keep roughly the **1 : 2.2 : 4.2**
ratio (`Cash2h` at most 2.5× `Cash30m`, `Cash8h` at most 5×) — see `docs/BALANCE.md` "Cash packs
and the era cap" for why a steeper ladder (e.g. the nominal 1 : 4 : 16) makes the big packs worse
value than the small one for most of every era.

### 4. Ambient era loops — resolved after M6

At M5 sign-off the four ambient loop ids in `src/shared/Config/Sounds.json` were still `0`.
They were uploaded on 2026-09-09, after M6 — see M3 §3 item 9.

### 5. Nothing else needed for M5

- [x] 2. No new Kenney meshes, audio, passes, or products required this milestone. Mesh import
      (`docs/MANUAL_STEPS.md` M3 §2) remains fully optional at any pace.
- [x] 3. That's it — go run `docs/PLAYTEST.md` M5 section, including the Final sweep.

<!-- M5 section complete. Do not delete completed sections above. -->

---

## M6 — Legacy shop (Phase 2)

Nothing new to create on the Creator Hub this milestone — the Legacy shop is entirely Legacy-
currency, no Robux anywhere near it. This section is a rebuild, the new `GrantLegacy` Studio
lever (with an important persistence warning), and the same two reminders carried forward again.

### 1. Rebuild first

- [x] 1. If you pulled new changes since M5, rebuild: `$env:PATH = "$HOME\.rokit\bin;$env:PATH"`
      (PowerShell) then `rojo build -o build/test.rbxl` (or reconnect `rojo serve`). No new
      dependencies (`wally install` not required — `wally.toml` is frozen for M6).
      `luau-lsp analyze` needs a fresh sourcemap since a new module landed
      (`Services/LegacyShopService.luau`): `rojo sourcemap default.project.json -o sourcemap.json`.

### 2. The `GrantLegacy` lever, and a warning about it

`docs/PLAYTEST.md` M6 section 2 has the exact playtest steps. Summary: `DataService`/the income
tick reads a **numeric** Workspace attribute named `GrantLegacy`. While it holds a value > 0, in
Studio only, every loaded player's Legacy increases by that amount once (server's 1 Hz tick),
their persisted rate refreshes, and the attribute resets itself to `0` with a warn line in
Output. Same pattern as M5's `ForceLoadFailure`. It is ignored entirely in a published game.

- **This is real, not sandboxed.** With "Enable Studio Access to API Services" ON (the same
  toggle from M2/M3/M5), Legacy granted through this attribute is written to your actual saved
  profile permanently, the same as if you'd earned it by playing. There is no separate "test
  Legacy" pool. Don't grant huge numbers on a save you want to stay representative of real
  progress — a fresh/throwaway profile is the cleanest way to exercise every perk tier.

### 3. Robux pricing ladder — still your call, still 1 : 2.2 : 4.2

Carried forward unchanged from M4/M5 (`docs/BALANCE.md` "Cash packs and the era cap" and this
milestone's M6 paid-stack re-verification both confirm nothing about the ladder moved — the
Legacy shop never touches `PassMult`/`PremiumMult`). Whenever you actually set or revisit Robux
prices for `Cash30m` / `Cash2h` / `Cash8h` on the Creator Hub, keep roughly the **1 : 2.2 : 4.2**
ratio (`Cash2h` at most 2.5× `Cash30m`, `Cash8h` at most 5×).

### 4. Ambient era loops — uploaded, listen once

The four ambient loops (`Village`, `Boomtown`, `Metropolis`, `OrbitalColony`) were uploaded on
2026-09-09, after this milestone's playtest, and their ids are in
`src/shared/Config/Sounds.json` (M3 §3 item 9 has the sources).

- [ ] 22. Rebuild, then run `docs/PLAYTEST.md` "Post-M6 — Ambient era loops". If a loop never
      plays, check the asset's moderation status on create.roblox.com; a rejected asset's id
      goes back to `0` (silent, never an error).

### 5. Accepted risks (recorded here per the lead's ruling — not bugs, don't report them)

- [x] 19. **New (M6): Legacy granted via the `GrantLegacy` lever in Studio with API access on is
      real and permanent for that account.** See section 2 above. Not a bug — it's the intended
      behaviour of a Studio-only testing lever that writes through the same save path as real
      play; just don't do it on a profile you want to keep representative.

### 6. Nothing else needed for M6

- [x] 20. No new Kenney meshes, audio, passes, or developer products this milestone. Mesh import
      (`docs/MANUAL_STEPS.md` M3 §2) remains fully optional at any pace.
- [x] 21. That's it — go run `docs/PLAYTEST.md` M6 section.

<!-- M6 section complete. Do not delete completed sections above. -->

---

## M7 — Growing buildings: pipeline + Village

Meshes are no longer hand-imported. Every Village model is produced by a scripted pipeline —
blueprint -> merge -> upload -> the one Studio step -> template -> `rojo build`. The old M3 "Kenney
mesh import" instructions (M3 section 2 above) are retired for eras this pipeline has reached;
left in place as history, not to be followed again for Village. `templates/` and
`src/shared/Config/Assets.json` are **generated-only** — never hand-edit them, they're overwritten
by the tools below.

### 1. One-time setup — `.env`

- [x] 1. The pipeline reuses the same Open Cloud credentials as `tools/upload_audio.py`
      (`docs/MANUAL_STEPS.md` M3 section 3): `.env` at the repo root (gitignored;
      `.env.example` is the template) needs `ROBLOX_API_KEY` (an Assets → write key scoped to the
      creator that owns the place), `ROBLOX_CREATOR_TYPE`, `ROBLOX_CREATOR_ID`. Already set up as
      of M3 — nothing new to create here unless the key was revoked/expired.

### 2. Running the pipeline for an era (already done for Village; repeats per-era at M8)

Run in this order from the repo root. Every step is idempotent — re-running skips anything
already built/uploaded, so it's safe to re-run after fixing a blueprint.

- [x] 2. **Blueprints** (already authored for all 24 Village slots): author/edit
      `tools/testfit/blueprints/<Era>/<ModelName>.json`, preview with
      `"/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b -P tools/testfit/testfit.py -- --blueprint <json>`
      (one blueprint per run), and check the
      strip render — no floating/clipping pieces, footprint respected.
- [x] 3. **Stage merge** (Blender, headless):
      `"/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b -P tools/assets/merge_stages.py -- --era <Era>`
      (add `--model <ModelName>` to rebuild just one). Writes GLBs to `assets/build/` — gitignored,
      not committed.
- [x] 4. **Upload** — dry run first, then for real:
      `py tools/assets/upload_models.py --era <Era> --dry-run`
      `py tools/assets/upload_models.py --era <Era>`
      Writes asset ids into `src/shared/Config/Assets.json`. Safe to re-run — already-uploaded
      stages (non-zero id) are skipped.
- [x] 5. **The one Studio step** — harvesting mesh/texture ids that only Studio can read:
      1. `py tools/assets/harvest.py --emit` — regenerates `tools/assets/harvest.luau` from
         whatever in `Assets.json` still needs harvesting (uploaded but not yet harvested).
      2. In Studio (Edit mode, not Play), open the **Command Bar** and paste the entire contents
         of `tools/assets/harvest.luau`, then run it.
      3. Select all of the Output panel's `[HARVEST] {...}` lines and copy them (Ctrl+A, Ctrl+C in
         Output, or drag-select just those lines).
      4. `py tools/assets/harvest.py` — reads the Windows clipboard automatically
         (`powershell Get-Clipboard`) and merges the harvested `meshId`/`imageId`/`size`/`offset`
         values into `Assets.json`. (`--file <path>` if you saved the Output text to a file
         instead of using the clipboard.) Any asset the paste didn't cover is listed and left
         untouched — re-run steps 1–4 to pick up the rest.
- [x] 6. **Templates**: `py tools/assets/gen_templates.py` — writes
      `templates/<Era>/<ModelName>.rbxmx` from `Assets.json`. `py tools/assets/gen_templates.py
      --check` diffs without writing (same pattern as the asset manifest's `--check`) — QA runs
      this.
- [x] 7. **Build**: `rojo build -o build/test.rbxl` (or resync `rojo serve`). Confirm in Studio
      that `ServerStorage.Assets.<Era>.<ModelName>` exists with `Stage0`…`Stage4` (or just
      `Stage0` for non-`building` slots) and that the mesh previews textured in Edit mode.

### 3. Open Cloud upload quota — read before uploading a new era

- [x] 8. The **100 uploads/month cap is audio only** (M3 section 3). Models have no documented
      monthly cap, and the evidence agrees: 91 model uploads (Tavern proof + the Village run) went
      through on 2026-09-15/16 on top of the 13 audio uploads already spent this month, with no
      quota error. Expect M8's three eras at roughly 85 uploads each. One upload failed with
      Roblox's transient "Unknown Error"; the tool never re-uploads an id that is already
      non-zero, so simply re-run it (`--model <Name>` to target one slot).

### 4. Nothing new to create on the Creator Hub

- [x] 9. No new game passes or developer products this milestone — M7 doesn't touch
      monetization. VIP building skins ride the existing `VIP` pass (already created and pasted,
      M4 section 3) as a texture swap; nothing to recreate.

### 5. If a template doesn't show a mesh

- [x] 10. Confirm `Assets.json` has non-zero `modelAssetId`/`meshId`/`imageId` for that stage
      (open the file, search the model name) — `0` means it hasn't been uploaded/harvested yet,
      re-run the relevant pipeline step above.
- [x] 11. Uploaded meshes are moderated like audio — give it a few minutes if it's freshly
      uploaded. Check the asset on create.roblox.com if it never appears.
- [x] 12. `$ignoreUnknownInstances` stays OFF for `ServerStorage.Assets` now — nothing is
      hand-placed there any more. If you ever need to test something by hand-placing a Model
      under `ServerStorage/Assets`, expect Rojo to delete it on the next sync; that's the
      generated-only contract working as intended, not a bug.

### 6. Nothing else needed for M7

- [x] 13. That's it — go run `docs/PLAYTEST.md` M7 section, including the `GrantCash` lever setup
      and the two-player check.

<!-- M7 section complete. Do not delete completed sections above. -->

---

## M9 — City dressing: roads, trees, filler, squares, vehicles

Same pipeline as M7/M8 (`tools/assets/`), extended with a **`--props`** mode: instead of a slot's
building stages, it merges/uploads/templates a **city-dressing prop** (tree, filler house, plaza,
junction, bend, lamp, vehicle). Props are per-era too, but templates land under
`templates/_props/<Era>/` → `ReplicatedStorage/Assets/Props/<Era>/<PropName>` (not
`ServerStorage`, so the client can clone them itself). `Assets.json` gains a `props` table
alongside the existing per-slot table — still generated-only, never hand-edit it.

### 1. Nothing new to set up

- [x] 1. Same Open Cloud credentials as M3/M7 (`.env` at the repo root) — nothing new to create.

### 2. Running the props pipeline for an era

Run in this order from the repo root; every step is idempotent, same as M7.

- [x] 2. **Blueprints** (already authored, Village + Boomtown): author/edit
      `tools/testfit/blueprints/_props/<Era>/<PropName>.json`, preview with
      `"/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b -P tools/testfit/testfit.py -- --blueprint tools/testfit/blueprints/_props/<Era>/<PropName>.json`
      (output PNG lands under `assets/testfit/out/<Era>/props/`) and check the strip render.
- [x] 3. **Street-plan check** (before uploading anything, whenever a layout's `streets`/`lots`/
      `plazas`/`treeZones` change): `py tools/streetplan.py` (Village + Boomtown; pass an era name,
      e.g. `py tools/streetplan.py Metropolis`, once it exists) — writes
      `assets/testfit/out/<Era>/streetplan.png` and exits non-zero on a clearance-rule violation
      (P1/P2 amendments included). Look at the PNG before approving a layout.
- [x] 4. **Stage merge** (Blender, headless):
      `"/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b -P tools/assets/merge_stages.py -- --props --era <Era>`
- [x] 5. **Upload** — dry run first, then for real:
      `py tools/assets/upload_models.py --props --era <Era> --dry-run`
      `py tools/assets/upload_models.py --props --era <Era>`
      (re-run on Roblox's transient "Unknown Error" — the tool never re-uploads a non-zero id, so
      it's safe to repeat.)
- [ ] 6. **The one Studio step** — one harvest paste covers **both** eras already uploaded:
      1. `py tools/assets/harvest.py --emit --props && cat tools/assets/harvest.luau | clip`
         (copies the generated snippet straight to the clipboard).
      2. In Studio (**Edit mode, not Play**), open the **Command Bar**, paste, run it, and wait for
         the `[HARVEST-DONE]` line in Output.
      3. In the Output panel: right-click → **Select All** → **Ctrl+C** (copies every
         `[HARVEST] {...}` line since the last clear).
      4. `py tools/assets/harvest.py --props` — reads the clipboard and merges `meshId`/`imageId`/
         `size`/`offset` into `Assets.json`. Anything the paste didn't cover is listed and left
         untouched — re-run steps 1–4 to pick up the rest.
- [ ] 7. **Templates**: `py tools/assets/gen_templates.py --props` — writes
      `templates/_props/<Era>/<PropName>.rbxmx`. `py tools/assets/gen_templates.py --check` covers
      both the building and prop template roots — QA runs this.
- [ ] 8. **Build**: `rojo build -o build/test.rbxl` (or resync `rojo serve`), then
      `py tools/gen_asset_manifest.py && py tools/gen_asset_manifest.py --check`. Confirm in Studio
      that `ReplicatedStorage.Assets.Props.<Era>.<PropName>` exists with a `Stage0` (trees also
      have `Stage1`–`Stage3`) and previews textured in Edit mode.

### 3. Status

- [x] 9. **Village + Boomtown props merged and uploaded 2026-09-16** (24 stages total across both
      eras: Village's growing pine [4 stages] + 3 filler cottages + plaza + cart; Boomtown's tree +
      4 filler houses + pocket park + junction + bend + lamp + 3 vehicles). `Assets.json` v2's
      `props` table holds a non-zero `modelAssetId` per stage already; `meshId`/`imageId` are still
      `0` (search the file to confirm) until step 6 below runs.
- [x] 10. Harvest paste and `gen_templates.py --props` done 2026-09-16 for Village + Boomtown
      (24 stages harvested, 0 failed; 18 templates in `templates/_props/`). `docs/PLAYTEST.md`
      "M9" is ready to run after a Rojo sync.

### 4. Nothing new to create on the Creator Hub

- [x] 11. No new game passes or developer products this milestone — M9 doesn't touch
      monetization.

### 6. Wave 1c — ribbon paths (EditableMesh)

- [x] 13. Path texture generated, uploaded and harvested 2026-09-17 (Village: asset
      129735535354317, image 115163704776256). To regenerate or add an era:
      ```bash
      "/c/Program Files/Blender Foundation/Blender 5.2/5.2/python/bin/python.exe" tools/paths/texture.py --era Village
      py tools/assets/upload_path_texture.py --era Village --dry-run
      py tools/assets/upload_path_texture.py --era Village
      py tools/assets/harvest.py --emit && cat tools/assets/harvest.luau | clip
      ```
      Paste in the Studio command bar (Edit mode), wait for `[HARVEST-DONE]`, copy Output, then
      `py tools/assets/harvest.py` and `py tools/gen_asset_manifest.py`. A brand-new Decal can sit in
      moderation for a few minutes; re-run the paste if the merge says so.
- [ ] 14. **Creator Dashboard — required for ribbons in the published game.** Studio does not
      enforce this, so ribbons work in Studio either way. The experience owner (for a group game,
      the group owner) must be **13+ and ID verified**. Then: create.roblox.com → Creator
      Dashboard → the experience (or your account/group settings) → turn on **Enable Mesh / Image
      APIs**. Without it, the published game silently draws Beam paths instead.

### 5. Wave 2 (Metropolis, Orbital Colony, `cityDetail` setting) — not started

- [ ] 12. Repeats sections 2–3 above for Metropolis and Orbital Colony once their buildings ship
      (M8's remaining eras), plus a `SettingsPanel` row for `cityDetail` — no manual/Studio steps
      beyond the same pipeline run.

