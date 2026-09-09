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

- [ ] 1. If you haven't already, install Rokit, then from the repo root run:
      ```
      rokit install
      ```
      This restores the pinned versions from `rokit.toml`: rojo 7.7.0, wally 0.3.2,
      stylua 2.5.2, selene 0.31.0, luau-lsp 1.69.0.
- [ ] 2. Install the **Rojo plugin** in Roblox Studio, matching **Rojo 7.7**:
      - Studio → Toolbox → search "Rojo" → install the plugin by CodeKu / Rojo team, OR
      - In Studio: Plugins tab → Manage Plugins → get the Rojo plugin from the Creator Store.
      - Confirm the plugin's version shows 7.7.x when you open it (Plugins tab → Rojo icon).
      Mismatched plugin/CLI major versions will refuse to connect.

### 2. First build

- [ ] 3. From the repo root, if `Packages/` is missing (first checkout, or after pulling changes
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

- [ ] 5a. **Quick check:** double-click `build/test.rbxl` (or File → Open in Studio) to open the
      built place directly. Rebuild first (step 4) if you've synced new changes.
- [ ] 5b. **Live sync (optional, for poking around while iterating):**
      1. From the repo root, run `rojo serve`.
      2. In Studio, open a place (any new baseplate is fine), open the Rojo plugin, click
         **Connect** (default `localhost:34872`).
      3. Leave the terminal running `rojo serve` open while Studio is connected.

### 4. Nothing else to do in Studio for M0

- [ ] 6. No meshes, audio, game passes, or developer products yet — those start at M3/M4. The
      `ServerStorage/Assets/{Village,Boomtown,Metropolis,OrbitalColony}` folders already exist
      from the Rojo sync; leave them empty for now.

---

## M1 — Playable loop

**Nothing new is required in Studio or the Creator Hub for M1.** No meshes to import, no audio
to upload, no game passes or developer products to create, no IDs to paste anywhere. Mesh
import starts at M3; passes/products start at M4.

- [ ] 1. If you pulled new changes since M0, rebuild: `rojo build -o build/test.rbxl` (or re-run
      `rojo serve` and reconnect the Rojo plugin if you're using live sync). Exact commands are
      in the M0 section above (§2-3).
- [ ] 2. That's it — go run `docs/PLAYTEST.md` M1 section.

---

## M2 — Persistence & eras

### 1. Enable Studio API access (do this first — most important new step)

Progress now saves via ProfileStore, but Studio blocks real DataStore calls by default. Without
this enabled, ProfileStore silently falls back to an in-memory mock: the game still behaves
correctly for a single Play session but **wipes on every Stop** — you will not see true
persistence or offline earnings without doing this.

- [ ] 1. In Studio, open the place (`build/test.rbxl` or via `rojo serve`).
- [ ] 2. Home tab → **Game Settings**.
- [ ] 3. **Security** tab (left sidebar of the Game Settings window).
- [ ] 4. Toggle **"Enable Studio Access to API Services"** to ON.
- [ ] 5. Click **Save**.
- [ ] 6. This setting is per-place and persists across Studio sessions once saved — you only
      need to do this once per place file, not before every Play.
- [ ] 7. How to tell mock vs real at any time: Press Play, open **Output**, look for one line
      printed once by ProfileStore:
      - `[ProfileStore]: Roblox API services available - data will be saved` = real, persists.
      - `[ProfileStore]: Roblox API services unavailable - data will not be saved` = mock,
        wipes on Stop. If you see this after enabling the setting above, try re-saving Game
        Settings, or check you're not in a Team Create session without publish rights (a known
        cause of Studio API access being blocked regardless of the setting).

### 2. Install the new server dependency

- [ ] 8. From the repo root, run:
      ```
      wally install
      ```
      This now also populates **`ServerPackages/`** with ProfileStore (in addition to
      `Packages/` for Signal, as before). Re-run this any time `wally.toml`/`wally.lock`
      change — safe to re-run even if nothing changed.
- [ ] 9. Rebuild: `rojo build -o build/test.rbxl` (or reconnect `rojo serve` if using live
      sync). Confirm it succeeds with no errors — this is also QA's build gate.

### 3. Nothing needed on Creator Hub for M2

- [ ] 10. No game passes, developer products, meshes, or audio yet — those start at M3
      (meshes/audio) and M4 (passes/products). Nothing to create or paste IDs for this
      milestone.
- [ ] 11. That's it — go run `docs/PLAYTEST.md` M2 section (run it together with the M0 and M1
      sections per the combined playtest gate).

---

## M3 — Presentation

### 1. Rebuild first

- [ ] 1. If you pulled new changes since M2, rebuild: `rojo build -o build/test.rbxl` (or
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

### 3. Audio upload (optional this milestone — the game ships fully silent and correct)

Every sound ID in `src/shared/Config/Sounds.json` is `0` right now, which means **silent, not
broken** — buying, leveling, era-advancing, etc. all work with no audio and no errors. Upload
whenever convenient.

- [ ] 6. Download the suggested free Kenney sound packs (kenney.nl/assets, CC0, no account
      needed): **UI Audio** / **Interface Sounds**, **Casino Audio**, **Impact Sounds**,
      **Music Jingles**.
- [ ] 7. Creator Hub → your experience → **Audio** (or Studio → Toolbox → Inventory → Audio →
      **Upload**). Upload each clip you want to use. Wait for moderation approval (usually
      automatic, sometimes a short delay) — note the numeric **asset id** for each.
- [ ] 8. Paste each id into `src/shared/Config/Sounds.json` (`"id": 0` → `"id": 1234567890`).
      Nine event keys under `sounds`, suggested pack per spec §9:

      | Key | Suggested Kenney pack |
      |-----|------------------------|
      | `uiClick` | UI Audio / Interface Sounds |
      | `purchase` | Casino Audio (coin) |
      | `reveal` | Impact Sounds (soft thud) + a pop |
      | `levelUp` | Interface Sounds (short rising tick) |
      | `levelUpMilestone` | Interface Sounds (bigger sting) or Music Jingles (short) |
      | `insufficientFunds` | Interface Sounds (error) |
      | `eraAdvance` | Music Jingles (fanfare) |
      | `rebirth` | Music Jingles (bigger fanfare) |
      | `welcomeBack` | Music Jingles (short) |

      Plus four `ambient` keys (one loop per era, low volume, optional — leave at `0` if you'd
      rather skip ambient loops entirely):

      | Key | Notes |
      |-----|-------|
      | `Village` | medieval/pastoral loop |
      | `Boomtown` | jazzy/retro-urban loop |
      | `Metropolis` | modern-city loop |
      | `OrbitalColony` | sci-fi/space loop |
- [ ] 9. Leave any id at `0` to keep that specific event silent — no need to fill every row
      before testing again.

### 4. Credits line

- [ ] 10. Kenney assets are CC0 — legally no attribution is required. Still add one line to the
      game's Creator Hub description crediting Kenney (e.g. "3D models and sound from
      kenney.nl"). README already carries this credit; this step is just the in-game
      description.

### 5. Nothing else needed for M3

- [ ] 11. No game passes or developer products yet — those start at M4 (next section, once M4
      ships). Nothing to create or paste IDs for on Creator Hub this milestone beyond audio
      (step 3) and the optional mesh imports (step 2).
- [ ] 12. That's it — go run `docs/PLAYTEST.md` M3 section.

---

## M4 — Monetization & analytics

The game ships with every game-pass/product `id` at `0`. **`id: 0` means "hidden, never
prompted, never granted"** — no Shop button, no "Double it" button, no prompts anywhere, no
errors. You can create the three passes and four products **one at a time, in any order**, paste
each id in, and the game stays correct at every step (test the ones you've created, the rest
stay invisible). You do **not** have to create all seven before testing any of this milestone.

### 1. Rebuild first

- [ ] 1. If you pulled new changes since M3, rebuild: `rojo build -o build/test.rbxl` (or
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

- [ ] 2. Create **`DoubleCash`** ("Double Cash" — 2× income forever). Paste the id into
      `src/shared/Config/Monetization.json` → `passes` → the entry with `"key": "DoubleCash"` →
      `"id"`. Leave `"key"` exactly as it is — only edit `"id"`.
- [ ] 3. Create **`OfflinePro`** ("Offline Pro" — offline cap 8h→24h, efficiency 50%→100%). Paste
      the id into the `"key": "OfflinePro"` entry's `"id"`.
- [ ] 4. Create **`VIP`** ("VIP" — +10% income, VIP name tag, gold plot sign, VIP building
      skins). Paste the id into the `"key": "VIP"` entry's `"id"`.

### 4. Create the developer products (Creator Hub)

For each of the four products below: Creator Hub → your experience → **Monetization** →
**Developer Products** → **Create a Product**. Same flow — name, price, icon, save, copy the
numeric **Product ID**.

- [ ] 5. Create **`Cash30m`** ("30 Minutes of Cash"). Paste the id into `products` → the
      `"key": "Cash30m"` entry's `"id"`.
- [ ] 6. Create **`Cash2h`** ("2 Hours of Cash", priced ~2.2× `Cash30m` per the guidance above).
      Paste into `"key": "Cash2h"`'s `"id"`.
- [ ] 7. Create **`Cash8h`** ("8 Hours of Cash", priced ~4.2× `Cash30m`). Paste into
      `"key": "Cash8h"`'s `"id"`.
- [ ] 8. Create **`DoubleOffline`** ("Double it" — doubles the most recent offline grant; only
      ever offered on the welcome-back card, never in the Shop). Paste into
      `"key": "DoubleOffline"`'s `"id"`. Price this low — it's a small impulse buy tied to one
      welcome-back moment, not a bundle.
- [ ] 9. Double-check every pasted value is a **numeric id**, not `0`, and that you did not touch
      any `"key"`, `"minutes"`, or `"capFraction"` field — those are frozen contract values, not
      yours to edit.

### 5. Enable Premium payouts (optional but recommended)

- [ ] 10. Creator Hub → your experience → **Monetization** → **Premium Payouts** → confirm it's
      enabled (usually on by default for new experiences). This is what funds the 1.1× Premium
      multiplier the game already shows/applies — no config change needed on your side.

### 6. Rebuild and test in Studio

- [ ] 11. After pasting ids, rebuild: `rojo build -o build/test.rbxl` (or resync via
      `rojo serve`). Ids are read from config, not remotes — no server-side redeploy step beyond
      a normal rebuild/sync.
- [ ] 12. Run `docs/PLAYTEST.md` M4 Phase A first (all ids still `0`, i.e. before this section —
      already true if you're doing this for the first time) to confirm the baseline is silent,
      then Phase B once you've pasted at least one real id.

### 7. Testing purchases — read this before you tap "Buy" in Studio

- [ ] 13. **Developer product purchases inside Studio Play-testing are real-ish**: Studio uses
      your live Roblox account and can prompt a real Robux confirmation for a real product (game
      passes in Studio are typically mocked/free for the owner, but don't assume — the safest
      assumption is that any purchase you complete in Play mode may actually charge Robux).
      Use an account you're comfortable spending test Robux from, and don't leave a test session
      unattended near a purchase prompt. If you want to avoid any charge, create the products but
      don't tap through the purchase confirmation — just confirm the prompt appears and cancel it.

### 8. Accepted risks (recorded here per the lead's ruling — not bugs, don't report them)

- [ ] 14. **`DataService.SaveAsync` durability caveat.** `SaveAsync` wraps ProfileStore's
      `Profile:Save()`, which is non-yielding — a `true` return means "accepted into an active
      session", **not** "durably written to the DataStore yet". `ProcessReceipt` returns
      `PurchaseGranted` on that `true`, which permanently retires the receipt with Roblox (Roblox
      will never re-deliver it). If the server crashes in the few seconds between that `true` and
      the underlying write actually landing, the player keeps the Robux charge and the grant is
      lost, with no automatic retry. This is the strongest guarantee ProfileStore exposes; it's
      accepted for M4 and is an M5 hardening item (see `docs/PLAN.md` M5 carry-forward list). You
      won't be able to reproduce this in a normal playtest — it needs a server crash mid-save.
- [ ] 15. **Open `DoubleOffline` reservation.** If a player leaves with a "Double it" offer
      reserved (dialog open) but not completed, that reservation is simply dropped — a receipt
      that somehow arrives in a later session grants `0` (with a `warn` logged server-side, not
      an error). Rare in practice (Roblox retries receipts quickly and this window is small).
- [ ] 16. **Analytics events are silent in Studio by design.** `slot bought`, `level-up`,
      `offline grant`, `product grant`, and `legacy on advance/rebirth` events only actually
      appear on the Creator Hub analytics dashboards for a **published** place with analytics
      enabled. You will not see anything on a dashboard from Studio Play-testing — that's
      expected, not a bug to report.

<!-- M4 section complete. Do not delete completed sections above. -->
