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

<!-- M3 section appended here once M3 ships. Do not delete completed sections above. -->
