---
name: review-workflow
description: How to run read-only reviews in this repo (git since 2026-09-08, rokit toolchain, scratchpad build trick, py not python), milestone baselines M0–M3, and recurring bug patterns to recheck
metadata:
  type: project
---

Repo became a **git repository on 2026-09-08** (one init commit; lead commits, agents never do).
`git diff HEAD` now works for tracked files, but each milestone also adds *untracked* new
files — always run `git status --short` and read the `??` entries in full; the diff alone
misses them. Before 2026-09-08 there was no git and reviews worked from lead-supplied file lists.

**Why:** INTERFACES.md env notes govern the environment; the lead sends per-milestone file
lists with disjoint agent ownership (luau-engineer: src/server + src/shared/*.luau + root
configs; ui-engineer: src/client; economy-designer: src/shared/Config + Layouts + tools/*.py).

**How to apply (read-only verification that catches real signal every milestone):**
- Bash needs `export PATH="$HOME/.rokit/bin:$PATH"` for rojo/wally/stylua/selene/luau-lsp.
- Python is `py` (3.14); `python`/`python3` are Windows Store stubs — never invoke them.
- Validate without touching the repo: `rojo build -o <scratchpad>/test.rbxl`.
- `selene src`, `stylua --check src`, `luau-lsp analyze --sourcemap sourcemap.json
  --definitions=tools/types/globalTypes.d.luau --ignore "Packages/**" --ignore
  "ServerPackages/**" src` are all safe and all green as of M3 — run all four plus
  `py tools/sim_economy.py --check` and `py tools/gen_asset_manifest.py --check` in one call.
- Large `git diff` output gets persisted to a tool-results file; read it back with `sed -n`
  ranges rather than re-running the diff.
- `wally.lock` saying `registry = "test"` is a known wally quirk, not a finding.

**Recurring patterns to recheck every milestone (found at M1):**
- **Cross-service signal-order dependency:** services each connect `Players.PlayerAdded`
  independently and one assumes another ran first. Roblox invokes connections in *reverse*
  connection order (officially unspecified). Whenever join/leave logic changes, re-verify no
  handler depends on a sibling handler having already run; safe shape is an explicit
  EnsureState/orchestrator call (Main.server.luau is that orchestrator since M2).
- **Studio masks join-order bugs:** in Play Solo the player exists before `Start()`.
  "Works in Studio" is not evidence for live-join correctness.
- **Portrait design canvas vs landscape phones:** Theme designs at 375×667; Roblox mobile
  defaults to landscape. Recheck every UI milestone at 667×375 AND 640×360 (common Android
  dp viewport): at 640×360 the M3 right-docked side panel (340 design px) overlaps the
  top-left TopBar (352 design px) by ~9 px at MIN_SCALE. Flagged as Suggestion at M3.

**Recurring pattern (found at M2):**
- **Discontinuous state mutations must restamp derived persisted fields.** Any handler that
  resets state mid-session must call `EconomyService.RefreshPersistedRate(player)` inline,
  not "on the next tick" — otherwise a scripted disconnect farms offline grants at the old
  rate. Verified still honored at M3 (tryAdvanceEra/tryRebirth both call it before FxEvent
  and SendSnapshot).

**M0 baseline (2026-09-02, SHIP).** **M1 baseline (2026-09-02, SHIP after fix round)**: load-
bearing shapes — `DataService.EnsureState(player)` is the SOLE state-creation path;
`RemoteService.TryConsumeToken(player, remoteName)` shares a remote's bucket with prompt
paths; `Theme.MIN_SCALE` is *derived* as TAP_TARGET_MIN / min(all interactive heights) so
adding any new interactive element size to that `math.min` list is mandatory (M3 did this
correctly for bottom bar / level buttons / toggles).

**M2 baseline (2026-09-03, SHIP after fix round):** EconomyService has THREE named rates
(live / reported / persisted); `state.incomeAtSave` is assigned ONLY via
`computePersistedIncomePerSecond`. Main.server.luau is the SOLE per-player orchestrator
(load → offline grant → claim → snapshot, no yields between LoadAsync return and
SendSnapshot). Sim/BALANCE.md reproducible via `py tools/sim_economy.py --check`.

**M3 baseline (2026-09-08, SHIP first pass — no Criticals):** Presentation milestone.
Load-bearing shapes to watch in M4+:
- `RequestSetSetting` handler is wired in **Main.server.luau** (sanctioned deviation from the
  contract's "DataService.Start": EconomyService requires DataService, so DataService can't
  require EconomyService to MarkDirty). `DataService.SetSetting` returns false on nil state;
  its `else` branch writes `sfx` for ANY non-"music" key — safe only because
  RemoteService's validator whitelists the two keys. Any future direct caller must re-check.
- `FxEvent` (server→client, owner only) fires from tryBuy/tryLevelUp/tryAdvanceEra/tryRebirth
  after mutation; `rebuildPlotForEra`/`ClaimPlot` stay silent. Two client listeners on the
  one RemoteEvent (PlotVisualsController: reveal/levelUp, keyed on `slotId` string;
  UIController: eraAdvance/rebirth, keyed on `toEra` number) — adding a new kind must keep
  the discriminators disjoint.
- VIP template lookup `findTemplate(eraName, modelName, vipSkins)` reads `state.passes.VIP
  == true`; M4 must set passes.VIP AND call `refreshSign` (sign colour only refreshes on
  claim/advance/rebirth).
- Client: `Motion.Info` is the single reduce-motion choke point for tweens; particle gating
  is per-caller (`Theme.reducedMotion`). `PanelDock.Compute` is the single docking rule;
  landscape ignores `designHeight` (full column). `SoundController.Init` is synchronous;
  `Catalog.GetSoundsConfig` returns an uncached empty fallback when Sounds.json is absent.
- Panel.luau carries M1's inline `+ 2` / `- 16` header insets and BuildPanel's `40` /
  `ScrollBarThickness = 4` — pre-existing, flagged as Suggestion at M3, not new debt.
