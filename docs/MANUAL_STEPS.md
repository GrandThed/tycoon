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

## M4 — Monetization & analytics (placeholder — filled in once M4 ships)

Future: create game passes and developer products on Creator Hub, paste their numeric IDs into
`src/shared/Config/Monetization.json`, and enable Premium payouts. Nothing to do here yet.

<!-- M4 section replaced with real content once M4 ships. Do not delete completed sections above. -->
