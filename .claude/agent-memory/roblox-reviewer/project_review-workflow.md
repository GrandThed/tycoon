---
name: review-workflow
description: How to run read-only reviews in this repo (git since 2026-09-08, rokit toolchain, scratchpad build trick, py not python), milestone baselines M0–M7 + ProfileStore facts, and recurring bug patterns to recheck (esp. new yields in Main.onPlayerAdded)
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

**Recurring pattern (found at M4, 2026-09-09) — the highest-value check in this repo:**
- **Any new yield inserted into `Main.server.luau`'s join coroutine silently destroys the
  offline grant.** `EconomyService.grantIncome` runs at 1 Hz over *every* player with a loaded
  profile and unconditionally does `state.lastSeen = os.time()`. The M2 invariant "no yields
  between `LoadAsync` returning and `SendSnapshot`" is what protects `ApplyOfflineGrant`'s
  `elapsed = now - state.lastSeen`. M4 inserted `MonetizationService.RefreshPassesAsync`
  (a yielding `UserOwnsGamePassAsync` loop) between them → a tick landing in that window zeroes
  `elapsed`, losing the whole grant, the welcome-back card and the `DoubleOffline` offer.
  **How to apply:** every milestone, diff `Main.server.luau`'s `onPlayerAdded` and ask of each
  new call "does this yield?". If yes it is a Critical unless the join path is gated out of the
  income tick or `lastSeen`/`incomeAtSave` are snapshotted before the yield. Bonus trap: the
  bug is invisible in the shipping all-ids-0 default (no ids ⇒ no Marketplace call ⇒ no yield),
  so a green playtest is not evidence.
- **Preview-vs-authoritative rate mismatch on paid items.** Client shop previews use the
  snapshot's *reported* rate (Studio debug ×, neighbors ×1.27); the server prices packs off the
  *persisted* rate (no debug, neighbors 1). The 3-rate discipline means any client preview of a
  server-computed number must state which rate it used. Recheck whenever a UI previews cash.

**M4 baseline (2026-09-09, SHIP after one fix round — Monetization & analytics).** Load-bearing
shapes to watch in M5+:
- `EconomyService.joinComplete[player]` gates `grantIncome`; set ONLY at the end of
  `ApplyOfflineGrant`, cleared ONLY in `Cleanup`. Anything new in the join path must sit before
  that assignment, and nothing else may set the flag.
- **Four rates now, not three:** live / reported / persisted / *published* persisted.
  `Types.Snapshot.persistedIncomePerSecond` (always) and `Types.Delta.persistedIncomePerSecond`
  (whenever the `income` dirty flag flushes) carry `state.incomeAtSave` to the client so the shop
  preview prices exactly as a receipt does. Any new client preview of a server-computed cash
  number must say which rate it used.
- `DoubleOffline` is a reserve → (release | consume) state machine in `EconomyService`
  (`{amount, reserved, used}`). `ReleaseDoubleOfflineGrant` resets BOTH flags, which is what makes
  the receipt-rollback path re-grantable — do not "simplify" it to clearing `reserved` only.
- Receipt handler order: grant in memory → append id → `SaveAsync` → on false, pop id + roll back
  + `NotProcessedYet`; analytics and the `purchase` FxEvent fire only after a successful save.
- `Game.json` `remotes.promptCallsPerSecond` (v1.4) is `RequestPrompt`'s own bucket in
  `RemoteService.bucketCallsPerSecond`; every other remote still shares `callsPerSecond`.
- Known residual risks deliberately deferred to M5 (do not re-file as new): `SaveAsync` true means
  "accepted into an active session", not durable; a reservation open across a disconnect hits the
  "granting 0" warn path; `RefreshPassesAsync` serializes up to 3 retrying Marketplace calls in
  front of the join snapshot.

**M5 baseline (2026-09-09, SHIP with 2 Warnings — Hardening, full-codebase audit).** Load-bearing
shapes and ProfileStore facts verified from `ServerPackages/_Index/.../ProfileStore.luau` (v1.0.3):
- `SaveProfileAsync(is_ending=true)` fires `OnSessionEnd` synchronously (stravant-style Signal,
  `task.spawn` per listener) BEFORE its `UpdateAsync`, so `DataService.saveAndConfirm`'s
  session-end settle → receipt rollback runs before the final write reads `profile.Data`. Both
  orderings are consistent anyway (cash and receipt id always travel together).
- Mock-mode saves go through the same `UpdateAsync` wrapper and DO fire `OnAfterSave`.
- ProfileStore registers its own `BindToClose` at require time that ends EVERY active session
  itself → `OnSessionEnd` fires for all players at shutdown. Any handler that treats
  `OnSessionEnd` as "stolen session" must gate on `ProfileStore.IsClosing` (flagged M5 Warning).
- `DataService.LoadAsync` dedupes via a per-player waiter list (`coroutine.yield` +
  `task.spawn(waiter, state)`); `RetryLoadAsync` is refused (nil, silent) while loaded / in
  flight / inside `LOAD_RETRY_COOLDOWN_SECONDS`. Safe mode = no profile ⇒ no writes structurally.
- `EconomyService` DoubleOffline now has THREE sources (`"session" | "persisted" | "none"`);
  `RestoreDoubleOfflineGrant(player, source, amount)` is the rollback, `Release` is for
  declines only. Recheck: `Reserve` overwrites a non-zero persisted pending (M5 Warning).
- Rate buckets: calls 10/s (all gameplay + RetryLoad + SetSetting), prompt 1/s, snapshot 2/s;
  pad `Touched` = debounce + RequestBuy bucket; ProximityPrompt = RequestLevelUp bucket.
- Client: `LoadScreen` scrim is a non-Active Frame (never sinks input); bottom bar hidden until
  first snapshot; TopBar boots with dashes. `Theme.ZINDEX_LOAD = 22` sits between dialogs and
  ceremony.

**M6 baseline (2026-09-09, SHIP with Warnings — Legacy shop).** Load-bearing shapes to watch in M7+:
- `LegacyShopService.tryBuyPerk` is the ONLY Legacy sink; `state.legacy` never decreases anywhere
  (`spent` is the ledger, `Economy.LegacySpendable = legacy - spent`). Softcap lives in
  `Economy.LegacyMult` (`s + s*ln(L/s)`, continuous at s); SPEC §4 line 57 still prints the linear
  formula — docs deviation, not code.
- Every perk helper takes the shop config explicitly; `Economy.PerkValue` clamps a profile tier
  beyond a shrunk config to the last tier, while `NextPerkTier` returns "maxed" — consistent.
- Master Builders discount is applied ONLY inside `Economy.LevelUpCost`; Extra Milestone reaches
  income only via `IncomePerSecond`'s trailing `milestoneLevels` (server `computeIncomeWithMults`,
  client BuildPanel `previewGame` clone, PlotVisualsController `legacyShopState`). Any new caller
  of `SlotIncome`/`MilestoneMult` must thread the owner's list or milestones silently diverge.
- `PlotService.RefreshCosmetics` = full plot rebuild (VIP path reused) — silent, no FX; called
  after EVERY perk buy. `PlotService.Start` now owns a `CharacterAdded` map for `TitleTag`
  (disconnected on PlayerRemoving). Fireworks part lives in `record.folder` (NOT cleared by
  `clearPlotContents`) and self-destroys after 4 s.
- Studio-only levers on Workspace: `ForceLoadFailure` (DataService) and `GrantLegacy`
  (EconomyService, consumed in the 1 Hz tick, gated on the module-level `isStudio`). Neither
  rejects NaN/inf.
- Client: ceremony `onClosed` auto-opens the Legacy panel via `openPanel` (togglePanel wrapper)
  when `hasAffordableTier`; that is the only automatic panel open in the game — keep it the only one.

**M7 baseline (2026-09-16, SHIP with Warnings — growing Kenney buildings).** Load-bearing shapes to
watch in M8+ (other eras reuse every one of these):
- `ServerStorage.Assets` is `{"$path": {"optional": "templates"}}`; templates are generated
  `.rbxmx` (gen_templates.py, `--check` in the suite). Template = Model{Base PrimaryPart at identity,
  Stage0..4 Models with one MeshPart per kit named after the kit}. Rojo-built MeshContent/
  TextureContent/InitialSize verified in Studio by Ben (post-proof amendment).
- Stage rule is `PlotService.stageForLevel(level, Game.milestoneLevels)` — BASE list only; the
  owner's list (Extra Milestone perk) is a superset, so `levelUp.milestone == true` whenever a
  `stageUp` fires. Client dedupes the shared fanfare with a 0.25 s per-slot window
  (`lastMilestoneFx`); fragile but sound given the superset property — re-verify if either list changes.
- `attachStage` pivot math `building:GetPivot() * template:GetPivot():ToObjectSpace(stagePivot)` is
  invariant to how a PrimaryPart-less Stage model resolves its pivot (Clone preserves it). Safe.
- `swapStage` returns nil (no stageUp) on: placeholder, same stage, missing template, missing
  Stage<n> with no lower fallback, or live already showing the fallback stage. `RefreshCosmetics`
  = full rebuild, silent. `LevelUpPrompt` parent is `Base` (ground level) — prompt UI sits at the feet.
- Client scale animations (`newScaleDriver`) were fixed post-M7 to snapshot per-part Size/offset
  relative to `model:GetPivot()` (no ScaleTo); restore at scale 1 is exact whatever the pivot.
- **Pivot fix (2026-09-16):** template PrimaryPart ref arrived nil in a live Studio session (the
  .rbxmx DOES serialize `<Ref name="PrimaryPart">`; likely a rojo-serve ref gap), so bbox-centre
  pivots sank buildings. Now `templateBase(model)` finds `Base` by name; spawnBuilding sets
  PrimaryPart before the stage loop/PivotTo; attachStage uses Base.CFrame on both sides. Never
  trust a template PrimaryPart ref again; the client still uses GetPivot/PrimaryPart (Nit).

**Recurring pattern (found 2026-09-16, VIP skins toggle):** any cheap remote whose handler calls
`PlotService.RefreshCosmetics` (full plot rebuild, replicated to every client) turns the shared
10/s bucket into a server-wide lag vector. Require a server-side gate (e.g. VIP owned) plus a
trailing coalesce (Config constant), not a token bucket that drops the last optimistic write.
- Studio levers on Workspace: `ForceLoadFailure`, `GrantLegacy`, `GrantCash` (all gated on the
  module-level `isStudio`, consumed in the 1 Hz tick; GrantCash rejects NaN/inf/<=0).
- Tools: `upload_models.py` idempotent (skips non-zero ids, saves Assets.json after every upload,
  error text = response body, never the key); `gen_templates.py` DELETES any stray `.rbxmx` under
  `templates/` that Assets.json does not produce — never hand-place files there.
- Pre-existing, not M7: selene shadowing warning in `LegacyPanel.luau:200`; SPEC §8 says
  "CanCollide only on the base" while INTERFACES/templates set MeshPart CanCollide true.

**Asset preload gate (2026-09-16, SHIP with Warnings, client-only).** Load-bearing shapes:
- `AssetPreloader` (utility, not booted by Main.client): `PreloadEra` fire-and-forget over
  content strings; `AwaitInstance` = coroutine.yield + `task.defer` resume (defer is required:
  PreloadAsync may not yield) + `task.delay` timeout cancelled on completion. Sound.
- PlotVisualsController hides via `LocalTransparencyModifier` (nothing else in src writes it) on
  ALL plots; `watches`/`gated` are weak-keyed on Instances; waiters released by task.spawn when
  `pending` hits 0 (before parts un-hide, so reveal/pop set start scale first) and on unwatch.
- Recheck: the gate hides unconditionally, so every `RefreshCosmetics` rebuild can blank the plot
  for the PreloadAsync round-trip even with warm cache — any future gate should skip parts whose
  `ContentProvider:GetAssetFetchStatus` is already Success. Buildings folder persists across
  rebuilds (`ClearAllChildren`), so one ChildAdded per plot is the correct lifetime.

**M9 baseline (2026-09-16, city dressing, SHIP with Majors — client-only cosmetics).** Load-bearing:
- Server side is ONLY `PlotService.publishCityAttributes` (buy, levelUp, `rebuildPlotForEra` wrapper =
  claim/RefreshCosmetics/advance/rebirth) + `publishLobbyAttributes` (buildWorld before parenting, Release).
  Any new slot/level mutator must call it. `setAttributeIfChanged` avoids per-buy writes.
- Client: `CityDressingController` deferred per-plot `sync`; `PropFactory.Seal` is the single collision
  choke point (roadPart + Spawn); `Traffic` one Heartbeat, BulkMoveTo in pcall, disconnects at 0 vehicles.
  Budgets allocated up front from layout (RoadGraph.allocate, Scatter.Plan), so growth order never matters.
- `globIgnorePaths: ["templates/_props"]` verified empirically (scratch copy + fake prop): props appear
  only under ReplicatedStorage.Assets.Props; ignore filters children of dir walks, not a `$path` root.
- **Recurring pattern (M9):** client code that reconciles against replicated server children must not
  treat a *transient* missing child as a teardown signal — server full rebuilds (RefreshCosmetics) replicate
  in chunks across frames. Recheck any "child gone → clear everything" logic.

**M9 wave 1b (2026-09-17, "natural paths", SHIP with 2 Majors — client-only).** Roads now grow with
buildings: `RoadGraph` builds one network from all spine polylines, splits every segment at every
*potential* join point (owned or not), runs an O(N^2) Dijkstra from the entrance (polyline 1 point 1;
ties keep the lower node index, relaxation keeps the first parent — deterministic), and `allocate`
fixes both budgets (`roadPieces` straight, `roadPiecesNear` meandered) from the whole layout before
any ownership is known. That is what makes "A then B" == "B then A" and "nothing already drawn moves";
never let a budget or a route depend on the owned set. `Noise.luau` (Hash/Phases/Wave) is the shared
pure hash — Scatter.Hash now delegates to it.
- **Recurring pattern (wave 1b):** a render budget that can legitimately produce *zero* parts must not
  double as the "is this drawn?" flag. `RoadGraph.SetNear` redraws only groups with `#parts > 0`, so a
  group whose meandered draw was cut by the near budget is never redrawn straight (and disappears
  permanently after near->far->near). Keep an explicit revealed set instead of counting Instances.
- **Recurring pattern (wave 1b):** a Python mirror must mirror the *allocation* function, not the
  rendered result. `streetplan.py road_pieces` merges contiguous stretches into runs before
  `round(L/segmentLength)` while the client meanders per stretch and budgets every stretch/bend node in
  the network (Village: tool 146, client 153, of 160). Whenever a budget moves into code, re-derive the
  tool's counter from the Luau allocator line by line.
- Read-only verification for this area: `py tools/streetplan.py` (0 violations = the plan's clearance,
  reachability and budget rules) and a scratch script that imports `tools/streetplan.py` as a module
  (`importlib.util.spec_from_file_location`) to re-count pieces the way the client does — that is how
  both Majors were quantified without Studio.

**M9 wave 1c (2026-09-17, ribbon paths, SHIP with Majors — client-only).** `PathRibbon` (pure port of
`tools/pathmock/pathgeom.py`) + `PathRenderer` (ribbon EditableMesh per layer 0/1/2 → Beam → RoadGraph Parts via
`onParts`). Network smoothed once per layout in `RoadGraph.ribbonCache`; drawn pieces are arc ranges of fixed
curves, so ownership never moves geometry. Failure handling verified sound: every create in pcall, late
`CreateMeshPartAsync` result destroyed when `handle.destroyed`/mode changed/layer replaced, growth Heartbeat is
module-level and disconnects at 0 jobs, beam tweens cancelled in `destroyBeams`.
- Read-only quantification: `py tools/pathmock/pathgeom.py <scratch>/x.json` prints full-network stats
  (Village: 9750 tris / 6612 verts / 28 meshes, lane1 2184 tris, 1 folded triangle) — use it to check
  `budget.ribbonTriangles` headroom instead of guessing.
- **Recurring pattern (wave 1c):** a renderer that takes the *whole visible set* per call must not be called
  once per item inside a per-slot loop. `RoadGraph.AddSpur` → `PathRenderer.Update` runs N times on a plot's
  first sync, and each run that extends a lane run removes and re-adds that whole piece's vertices (O(N²)
  EditableMesh churn on join) and cancels the previous call's growth job. Recheck any "full-set" API for a
  single flush per sync.
- Studio-only unknowns to keep listing until Ben confirms: MeshPart.TextureContent alpha really blends (vs
  showing part Color) on an EditableMesh-backed MeshPart; live add/remove faces after CreateMeshPartAsync
  render; CCW-from-+Y is front face; flat Beam orientation (attachment Y = face normal) and CurveSize1 sign.
