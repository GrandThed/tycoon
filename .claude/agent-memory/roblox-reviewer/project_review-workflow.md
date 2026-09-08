---
name: review-workflow
description: How to run read-only reviews in this repo (no git, rokit toolchain, scratchpad build trick), milestone baselines, and recurring bug patterns to recheck
metadata:
  type: project
---

This repo is **not a git repository** — `git diff` is impossible. Review the explicit file
list the lead provides, cross-checked against the frozen contract in `docs/INTERFACES.md`.

**Why:** INTERFACES.md env notes forbid `git init`; the lead sends per-milestone file lists
with disjoint agent ownership (luau-engineer: src/server + src/shared/*.luau + root configs;
ui-engineer: src/client; economy-designer: src/shared/Config + Layouts).

**How to apply (read-only verification that caught real signal at M0/M1):**
- Bash needs `export PATH="$HOME/.rokit/bin:$PATH"` for rojo/wally/stylua/selene shims.
- Validate the project without touching the repo: `rojo build -o <scratchpad>/test.rbxl`.
- `selene src` and `stylua --check src` are read-only and safe to run.
- `luau-lsp analyze` has no repo `.luaurc`/globalTypes — leave it to qa-runner.
- `wally.lock` saying `registry = "test"` is a known wally quirk, not a finding.

**Recurring patterns to recheck every milestone (found at M1):**
- **Cross-service signal-order dependency:** services each connect `Players.PlayerAdded`
  independently and one assumes another ran first (DataService comment claims FIFO).
  Roblox invokes connections in *reverse* connection order (officially unspecified), so
  PlotService.claimPlot saw nil state → no pads, no proactive snapshot on live joins.
  Whenever join/leave logic changes, re-verify no handler depends on a sibling handler
  having already run; the safe shape is an explicit EnsureState/orchestrator call.
- **Studio masks join-order bugs:** in Play Solo the player exists before `Start()`, so the
  `GetPlayers()` sweeps (DataService.Start before PlotService.Start) hide PlayerAdded races.
  "Works in Studio" is not evidence for live-join correctness.
- **Portrait design canvas vs landscape phones:** Theme designs at 375×667 but Roblox mobile
  defaults to landscape (667×375 → scale clamps to MIN 0.7 → tap targets shrink below the
  44 px contract, panel overlaps TopBar). Recheck every UI milestone at 667×375.

**M0 baseline (2026-09-02, SHIP):** scaffold conformed to INTERFACES.md exactly. ProfileStore
deliberately absent from wally.toml; plan of record is `[server-dependencies]` + ServerPackages
mapping at M2 — expect wally.toml and default.project.json to legitimately change shape then.

**Recurring pattern (found at M2):**
- **Discontinuous state mutations must restamp derived persisted fields.** The 1 Hz tick
  keeps `incomeAtSave`/`lastSeen` fresh, but any handler that resets state mid-session
  (advance era, rebirth — later: legacy shop, admin resets) leaves the OLD rate persisted
  for up to one tick; a scripted disconnect inside that window farms offline grants at the
  completed era's rate. Whenever a new state-reset path lands, verify it restamps the
  persistence-facing derived fields inline, not "on the next tick".

**M1 baseline (2026-09-02, SHIP after fix round):** first pass FIX-FIRST — one Critical
(PlayerAdded ordering above), one Major (landscape scaling), minors (bucket recreated post-
PlayerRemoving; unthrottled ProximityPrompt path). All five fixed and re-verified same day.
Load-bearing shapes now in the codebase (regressions here = red flag in later milestones):
`DataService.EnsureState(player)` is the SOLE state-creation path and claimPlot calls it
inline; `RemoteService.TryConsumeToken(player, remoteName)` lets server-side interaction
paths (prompts) share a remote's token bucket; `Theme.MIN_SCALE` is *derived* as
TAP_TARGET_MIN/min(interactive sizes) ≈ 0.917 (close button 48, header 48) and
`BuildPanel.SetLayout(scale, viewportSize)` derives panel height from AbsoluteSize
(aspect-ratio constraint deliberately removed; M3 may revisit landscape layout).

**M2 baseline (2026-09-03, SHIP after fix round):** first pass FIX-FIRST — one Critical:
prestige handlers left stale `incomeAtSave` (pattern above). Fixed same day; re-verified.
Deferred with PLAN lines: sim --rebirth flag + DataService busy-wait → M5, displayName
schema field → M3, Cash8h pack capping → M4.
Load-bearing shapes to watch for regressions in M3+:
- EconomyService has THREE named rates: live (legacy+neighbors, grants), reported (live +
  Studio debug, HUD/snapshot), persisted (legacy only, neighbors=1, never debug — lead
  ruling: neighbors is a live-social bonus, not an away bonus). Single-writer discipline:
  `state.incomeAtSave` is assigned ONLY via `computePersistedIncomePerSecond` (tick,
  ApplyOfflineGrant, RefreshPersistedRate). Any new writer or a rate-helper mix-up
  (e.g. M4 wiring pass/premium into the wrong helper) is a red flag.
- `EconomyService.RefreshPersistedRate(player)` must be called by every state-reset path
  (currently tryAdvanceEra/tryRebirth, after mutation, before SendSnapshot).
- `Main.server.luau` is the SOLE per-player orchestrator (load → offline grant → claim →
  snapshot in one atomic resumption — no yields between LoadAsync return and SendSnapshot;
  the RequestSnapshot handler relies on that atomicity to never see half-initialized state).
- DataService: `loadingPlayers` dedupe + `Cancel = player.Parent == nil` in
  StartSessionAsync; `profiles[player]` cleared BEFORE EndSession so the OnSessionEnd
  handler only kicks on external session steal. ProfileStore auto-mocks in Studio without
  API access (verified in vendor, line ~2072).
- Sim/BALANCE.md verified reproducible: `python tools/sim_economy.py --check` output matched
  BALANCE.md tables exactly; rerun on any config/Economy change.
- Era JSON invariants held at M2 (recheck if eras are edited): 24 slots, first slot cost 0,
  monument last, explicit `requires` always point backward, implicit chain never runs
  through a decor slot, layout keys 1:1, plotSize identical across all layouts.
