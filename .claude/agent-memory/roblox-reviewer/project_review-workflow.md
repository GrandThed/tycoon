---
name: review-workflow
description: How to run read-only reviews in this repo (git since 2026-09-08, rokit toolchain, two-project rojo/luau-lsp passes since C0, py not python), milestone baselines M0–M9 + C0 + ProfileStore facts, and recurring bug patterns to recheck (new yields in Main.onPlayerAdded, TeleportInitFailed, in-flight guards on yielding remotes)
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

**M9 wave 1d (2026-09-18, baked path meshes, SHIP with 3 Majors — client-only).** EditableMesh/Beam
renderers deleted cleanly (grep for `ribbon|beam|Editable` in src is clean). `PathRenderer` = `baked`|`parts`;
templates `ReplicatedStorage/Assets/Paths/<Era>/<pieceId>` (Rojo `globIgnorePaths` now lists `templates/_paths`
too — verified in a built `.rbxlx`: 91 pieces, all under ReplicatedStorage, none under ServerStorage).
Templates bake in heights + the importer's 180° Y turn and have **no PrimaryPart** (WorldPivot identity), so
`clone.WorldPivot = CFrame.identity; clone:PivotTo(plotFrame)` and `showRim`'s `plotFrame * source.CFrame`
agree — re-verify both if a template ever gains a PrimaryPart.
- **Read-only verification that found everything here:** import `tools/streetplan.py` + `tools/paths/network.py`
  as modules from a scratch script and re-derive the client's allocator and arcs. `py tools/paths/bake.py --era
  <Era> --list` writes nothing and prints the exact piece table (Village 58 = 34 stretch + 24 spur, Boomtown
  33 = 15 + 18; matches `templates/_paths/` exactly). Luau connector phase key `96 + 1-based id` == python
  `97 + 0-based sid` — equal only because the two stretch orderings match line for line; re-check together.
- **Recurring pattern (wave 1d, new):** when geometry moves from the client to an offline bake, every arc /
  index the client computes must be re-derived from the *tool*, not just self-consistent. `RoadGraph.chainArc`
  forces a polyline's own end points to the chain's FullSpan ends; `network.py` `arc_at` just projects. Village
  L3_1 differs by 1.86 studs (L4_1 by 0.08) → dust start and one vehicle-lane endpoint sit off the baked mesh.
- **Recurring pattern (wave 1d):** a piece id the client can ask for but the bake never emits drops the WHOLE
  plot to the fallback renderer (`addPiece` false → `fallback`). `pathPieceIds` emits `SP_<slotId>` without
  checking `network.spurChains[slotId] ~= nil`, while `buildLanes` does check — a derived 1-point spur route
  (slot anchor already on the spine) would trip it. Village/Boomtown dodge it via explicit 1-point `spur`
  overrides (P2). Check the guard symmetry whenever a new era gets `road.paths`.
- Wave-1b's "py mirror the allocator" Major recurred: `budget.pathPieces` (120) has no `streetplan.py` check
  (it only checks roadPieces/roadPiecesNear). Reserved today: Village 58, Boomtown 33 — headroom, not a breach.
  Spurs are allocated *after* every stretch, so an overrun drops paths to buildings first.

**M9 wave 1e (2026-09-18, street upgrades: surface variants + row lamps + crossing signals, SHIP
with 2 Majors — client-only).** `RoadGraph.SetSurface(state, owned, animate)` resolves one plot-wide
variant (last owned `paths.surface.upgrades` entry, else `base`; unuploaded ids ⇒ `"default"` for
BOTH renderers) → `PathRenderer.SetSurface` writes `MeshPart.TextureID` on every live Fill/Rim and
`addPiece`/`showRim` paint later clones. `setVariant(NO_SLOTS_OWNED, initial=true)` runs inside
`RoadGraph.new` so Boomtown never flashes asphalt. Row lamps (`Scatter.lampPosts`) draw **no** rng,
so the vehicle/tree stream is unchanged; `RoadGraph.StreetLines` (runs of planned spine pieces +
all spurs) and `SignalSpots` (nodes with ≥3 **spine** stretches; spurs are not stretches) are both
ownership- and LOD-independent.
- **Read-only verification that found the Majors:** `py tools/paths/bake.py --era <E> --list` prints
  every piece's node coords and chain arcs — enough to hand-count row-lamp steps (`floor(runArc /
  spacing)`) and to count how many nodes have 3+ spine arms. Village polyline 1 is 201 studs / 23
  stretches (L1_1..L1_23, so **string sorting scrambles ordinals ≥ 10**); Boomtown is 3 polylines
  × 5 stretches meeting at exactly ONE node (0,-54.5) ⇒ one traffic light per plot.
- **Recurring pattern (wave 1e, new):** a per-plot cap applied to a **string-sorted** plan silently
  decides *which* features survive. `"L1_10:4" < "L1_1:1"`, and `"L1_*" < "L2_*"`, so the whole
  `budget.lampPosts` 12 goes to the longest polyline and every side street is permanently unlit.
  Any capped plan must sort by numeric (polyline, ordinal, step) or allocate the cap per run.
- **Recurring pattern (wave 1e):** a purchase that both reveals a piece and changes the surface
  loses the surface effect — `applyBaked`'s `startBurst(revealed)` removes the handle's existing
  burst. Only slots with a **one-point (P2) spur** (Boomtown `paveMainStreet`) keep it; Village
  `dirtRoad` has `SP_dirtRoad`, so it does not.
- Wave-1b/1d "py mirror the allocator" recurred a third time: `budget.pathPieces` IS now checked by
  `streetplan.py` (fixed), `budget.lampPosts` is not.
- `templates/_props/*/{Lantern,TrafficLight}.rbxmx` and all `paths.*.variants.*ImageId` are absent/0
  until a Studio harvest, so a playtest before that shows none of this wave. `gen_templates.py
  --check` prints "uploaded but not harvested" and still PASSes — not a failure signal.
- Verified fact: templates store the texture as `TextureContent` (rbxmx), yet reading/writing the
  legacy `MeshPart.TextureID` works (`PlotVisualsController:171` already reads it), so the
  "restore the template's own texture" path is sound.

**C0 baseline (2026-09-17, Expeditions foundation — SHIP with 1 Critical + Majors).** Second place
(`combat.project.json`, `src/combat/**`) shares `src/shared` AND `src/server/Services` (hub-only
services inert); `ProfileSchema.luau` is the single schema source (v5, `combat` profile) required by
DataService in both trees; `RemoteService.Configure(defs)` must precede `Init` (HubRemotes /
CombatRemotes own the tables; Init without Configure creates nothing and warns). Verification that
worked: `rojo build` + `rojo sourcemap` for BOTH project files, then `luau-lsp analyze` **once per
tree** (`src/server src/client src/shared` with the hub map, `src/combat src/shared` with the combat
map — pointing the hub map at src/combat yields bogus "Unknown require" noise), plus
`py tools/sim_combat.py --check` (six assertions, prints a verdict line each).
- **Recurring pattern (C0, highest-value here):** a teleport handoff that releases the profile
  before `TeleportAsync` must handle **`TeleportService.TeleportInitFailed`**, not just a pcall
  around the call. TeleportAsync only throws on argument/validation errors; the common runtime
  failures arrive on that event, so the pcall-only path leaves the player in the source place with
  no profile, no plot and only a "Departing…" toast. Recheck every place-to-place hop.
- **Recurring pattern (C0):** any remote whose handler yields for seconds (reserve + teleport,
  MemoryStore, friend checks) needs a per-player in-flight guard, not just a token bucket — a
  1/s bucket still admits a second thread while the first is mid-yield (double ReserveServer,
  double release, and a `rejoin` that re-locks the ProfileStore key mid-teleport).
- **Recurring pattern (C0):** a fan-out remote must cap its per-call web calls. `RequestRunList`
  walks up to `REGISTRY_PAGE_SIZE` (50) registry entries and calls `IsFriendsWithAsync` on each;
  its `Players:GetPlayerByUserId(host)` fast path can never hit (the host is in the other place).
- Reserved-server fact: `game.PrivateServerId` is NOT a `ReservedServerAccessCode`, and teleport
  data is client-readable (`TeleportService:GetLocalPlayerTeleportData`), so the access code can
  travel in neither. Any join-in-progress design has to route it server-side.
- `src/combat/client` holds verbatim copies of Create/Theme/Toast/Motion/LoadScreen/SoundController
  (only SoundController was sanctioned by the contract); both project files mount `src/shared`, so
  `src/shared/UI` is the dedupe. Combat place has no settings surface, so it must call
  `SoundController.ApplySettings(snapshot.state.settings)` or the player's mute is ignored.

**M9 wave 2a (2026-09-22, Metropolis tile streets + ring highway + subway, SHIP with 1 Critical
(pipeline) + 2 Majors — client-only).** `TileRenderer` rasterises the *visible* stretches onto the
`tiles.tileStuds` lattice and picks each cell's prop from a 16-entry `PIECE_BY_MASK` table;
`Highway` builds a 64-cell ring from `layout.highway` and reuses `TileRenderer.PieceForMask`/
`ArmBit`; `Dust` is PathRenderer's burst extracted verbatim and now shared. `RoadGraph` gained
`tiles`/`tileStretchAllowed`/`tilesDirty` (Flush → `TileRenderer.Update`), `LoopLanes` (standalone
closed lane loop at a height, for the deck) and `EntrancePoint`. Deck cars are a second Traffic
"plot" keyed `-plotIndex`, charged to `budget.vehiclesPerPlot`.
- **Read-only verification that paid off here:** the Kenney kits ARE checked out at
  `assets/kenney3d/<kit>/Models/GLB format/`, so a ~40-line GLB parser (chunks → accessors →
  node translate/scale) settles "which way does this tile face" without Studio. Raised
  (y = 0.02) sidewalk vertices are the tell: `road-straight` kerbs at z = ±0.45 spanning all x
  ⇒ runs along **X**; `road-end` has an extra kerb at x ∈ [-0.5,-0.4] ⇒ open to **+X**;
  `road-intersection` has a full strip at z ∈ [-0.5,-0.4] + two corner blocks at +Z ⇒ tee closed
  **-Z**. All four canonical orientations in the contract verified true, and the whole 16-mask
  rotation table checks out as `rotl(canonicalMask, quarters)` in 4 bits.
- Also worked: `py tools/streetplan.py` (now covers Metropolis; 0 violations) and diffing its
  Village/Boomtown output against `git show HEAD:tools/streetplan.py` run from a scratch copy —
  proved "pixel-for-pixel unchanged" cheaply.
- **Recurring pattern (wave 2a, new):** a refactor that *snapshots* a value another wave made
  mutable. Wave 1e's `SetSurface` mutates `state.material`/`state.color`; wave 2a added
  `state.spurMaterial`/`spurColor` computed once in `RoadGraph.new` from the era base, so
  Village/Boomtown spurs drawn in the Parts **fallback** are painted the base look while the
  spine wears the variant (Boomtown = asphalt spurs on a gravel spine). `TileRenderer.Options`
  copies `roadMaterial`/`roadColor` the same way where `PathRenderer` deliberately takes a
  `colorOf()` closure. Whenever a wave introduces a mutable piece of State, grep later waves for
  fields initialised from the same source in a constructor.
- **Recurring pattern (wave 2a):** stacked render heights are a contract nobody writes down.
  Spur slab top = `thickness` (0.2), tile prop top = 0.14, pavement top = `thickness/2` (0.1),
  lane Y = `thickness`. The spur runs to the spine *centreline* + `spurWidth/2`, so in a tiles
  era it is a 3-stud concrete tongue **on top of** the asphalt at every building. Tabulate the Y
  of every renderer in an era before judging "do these overlap".
- Numbers for next time: Metropolis = 4 polylines / 7 spine groups / 38 tile cells of
  `budget.tileCells` 180; ring 56 = half 8 = 64 cells + ramp + sign = 66 of `highwayCells` 72
  (streetplan's mirror says 67 — it counts `RAMP_CELLS` 3 where the client places one prop);
  ~220 pieces on a full near plot, well under the 640 estimate.
- At review time **no wave-2a template existed** (`templates/_props/Metropolis/` absent,
  `templates/Metropolis/CityHall.rbxmx` absent, every `meshId`/`imageId` 0): uploaded but the
  Studio harvest paste + `gen_templates.py --props` had not run. `gen_templates --check` still
  PASSes and prints "uploaded but not harvested" — always check that line before calling a
  wave playtestable, because here it means the *entire* wave is invisible.

**M9 wave 2a FIX ROUND (2026-09-22, paved blocks + street trees + per-cell pavement + the 180°
template turn; FIX — 3 Criticals).** Durable lessons:
- **Assets.json `offset` changes sign meaning with pipeline state.** `assets_config.py` writes the
  merged-GLB (blueprint) centre when a stage is *uploaded*; `harvest.py` overwrites it with the
  Studio-measured centre, which carries the importer's 180° turn (blueprint +7.0 → harvested
  −6.965). So `meshId == 0` with a plausible `offset` is **not** a harvest. After commit b17718e
  `gen_templates.harvested_cframe` places every mesh at `−offset` with R00=R22=−1, but
  `Scatter.modelExtents` (`src/client/City/Scatter.luau`) still builds its footprint box from
  `+offset` — so every clearance derived from harvested extents (zone trees, lots, plazas, lamp
  rows, kiosks, street trees, the highway sign's `Scatter.Solids`) is **mirrored about the anchor**
  by up to ~5.6 studs. Recurring pattern: *when a pipeline flips a coordinate convention, grep every
  reader of the raw field, not just the writer.*
- **Simulate the client's geometry in Python to test "no coplanar overlaps".** A ~60-line mirror of
  `TileRenderer.cellSlabs` + `overlapsTile` over the Metropolis street lattice found 10 exact
  `width × width` overlaps — one in each quadrant of every junction, where cell A's side strip and
  the diagonally adjacent cell B's perpendicular strip both claim the corner. Brute-forcing 300
  random growth states showed partial ownership is no worse. Cheap, decisive, no Studio.
- Street-tree count mirror: 15 street + 24 zone = 39 of `budget.trees` 40 on Metropolis. Worth
  re-running (import `tools/streetplan.py` as a module and reuse `Era`) whenever `blocks` change.
- **`tools/testfit/plotrender.py` is now a SECOND py mirror** of the same contracts (Blender render
  Ben uses as the Studio reference). It disagreed with `Scatter` on edge order, spot positions,
  the faces-a-street test, the thinning formula and the cap source. Always diff the two mirrors.
- `docs/INTERFACES.md` lagged the code again: the "Pavement: per visible stretch" bullet still
  describes the renderer this round replaced. Check the contract text, not just the new section.
- Diffing a tool against HEAD's copy needs the old script inside a tree that has `src/` — it
  resolves paths from `Path(__file__).parents[1]`, so a bare scratchpad copy just tracebacks.
- Another session edits the working tree mid-review (`docs/`, `.claude/memory/`). Snapshot
  `git status` at the start and re-check at the end before attributing a change to the diff.

**C1 baseline (2026-09-22, Studio bridge + Village expedition — SHIP AFTER FIXES, 1 Critical +
4 Majors).** The combat place gained its whole gameplay stack (`EnemyService` AI → `CombatService`
hits → `WaveService` run loop → `DebugService` levers) plus `StudioBridge` (a DataStore handoff
record + a delayed Kick standing in for `TeleportAsync` in Studio). Load-bearing shapes:
- Boot order in `src/combat/server/Main.server.luau` is data → remotes → registry → arena →
  enemies → hits → waves → debug → return, wired by **hooks, not requires** (`EnemyService.SetHooks`,
  `CombatService.SetKillHandler`, `ArenaService.SetSnapshotSender`, `ReturnService.Init{rejoin}`),
  because a service may never require the one above it. `Types.RunMember` lives in `Types.luau`
  for exactly that reason.
- `WaveService.flushPool` is the ONLY profile write under `src/combat`; it runs at wave clear and
  once more in `EndRun` when `wave > clearedThrough` (so cleared / cap / wipe each flush exactly
  once, merged pairs as one flush of count 2). `ReturnService` removes the member from the roster
  BEFORE `DataService.Release`, which is what keeps a flush from racing a release.
- **Recurring pattern (C1, the Critical):** a *yielding* infrastructure call placed directly in a
  Heartbeat run loop makes the loop re-entrant. `WaveService.tick` → `ArenaService.PublishRun` →
  `RunRegistry` MemoryStore `SetAsync` (+ 1/2/4 s retry backoff) sits between "wave cleared" and
  `setPhase("breather")`, so every frame inside that yield re-enters the same branch; with the C1
  `ForceRegistryFailure` lever on, one wave clear starts ~180 concurrent retry chains. Any
  registry/DataStore call reached from a per-frame loop needs `task.spawn` + a single in-flight
  guard, or a 1 Hz service tick of its own.
- **Recurring pattern (C1):** a remote that repaints shared state must send the TRUE phase.
  `ArenaService.SetReady` broadcasts `Broadcast("lobby")` unconditionally, so a modified client can
  push phase `lobby` to the whole party at 10/s and (client-side) disable everyone's attack input.
  `Admit`/`Remove` get it right (`if runFields.inRun then "wave" else "lobby"`).
- Exploit surface that checked out: `CombatRemotes` validators reject NaN/inf vectors, cap
  `targetIds` at `director.maxAlive` and demand positive integer ids; `swingSeq`/`seq` are
  replay-drop counters only; melee/ranged cadence is re-gated on `os.clock()` against
  `windows`/`cooldown × comboTimingTolerance`; `charge` is re-clamped to `elapsed / chargeSeconds`;
  abilities cooldown per slot server-side; every id is re-resolved and re-checked for range+arc.
  Rewards never come from a payload. `DebugService.OnRequest` and every `StudioBridge` function
  return immediately outside `RunService:IsStudio()`.
- Verification that paid off: both `rojo build`s + `luau-lsp analyze` per tree were green and found
  nothing; the findings came from reading the run loop for yields and from arithmetic against the
  JSON (`enemy.aggroRange` 80 vs the arena's 155-stud diagonal ⇒ enemies idle and the wave stalls;
  `Theme.COMBAT_DEBUG_ROW_HEIGHT` 30 × MIN_SCALE 0.9167 = 27.5 px vs the 44 px rule).
  `py tools/sim_combat.py --check` was red 4/10 at review time — the economy-designer was still
  tuning `Combat.json`/`Missions/1_Village.json` in a concurrent session (status snapshot at the
  end of the review showed both files newly modified; my memory's "another session edits the tree
  mid-review" rule applied again).
- Hub side: `sendExpeditionSummary` is correctly placed AFTER `EconomyService.SendSnapshot` (it
  yields on a DataStore read in Studio), so the M4 "no yields before the offline grant" invariant
  still holds. New trap instead: the `ExpeditionSummaryCard` is a full-screen scrim at
  `ZINDEX_CARD`, created after `WelcomeBackCard` (same ZIndex), so on a return join it covers the
  welcome-back card and its DoubleOffline offer. Whenever a new card fires on the join sequence,
  check what else fires on that same join.

**M9 wave 2a PARK STRIPS + highway/garage kits (2026-09-22, commit 4a91a9f + untracked generators —
FIX, 1 Critical + 2 Majors).** The park-strip geometry itself is clean: a 120-line audit that imports
`tools/testfit/plotrender.py` as a module, builds `PlotScene` for 48 Metropolis ownership states and
checks every ground box for coplanar overlap found **zero** strip/planter faults (the 1817 hits are all
`Pavement` vs `Spur` at y = 0.1, identical Concrete 176,180,196, so invisible — the footpath spur's
`centreY` is 0 since the fix round, exactly the pavement top). Reusable: `PlotScene(era, network,
owned, tier).build()` runs without Blender and exposes `boxes`, `models`, `tile_cells`,
`planned_cells`, `pavement_rects`, `block_rects`, `strip_cells`.
- **Recurring pattern (new, highest-value here): a walk the contract describes "along the run" that
  is implemented per *piece* duplicates a spot at every shared node.** `Scatter.parkStripTrees`
  resets `walked`/`step` inside `for _, piece in run.pieces`, where the sibling `lampPosts`
  deliberately stitches a run into one curve first ("so the spacing carries across the pieces of a
  street"). Result on Metropolis: 24 planned planters contain two exact duplicates — (0, −28) and
  (−28, −28), the two central crossings — spawned as two overlapping TreeGrowing models with
  different hashed yaws, plus one lost mark on the polyline with 5- and 9-stud pieces. Whenever a
  new feature walks `RoadGraph.StreetLines`, diff its loop against `lampPosts` line by line.
- **`tools/testfit/plotrender.py` can disagree with the client ON PURPOSE.** Its module docstring
  says "Where the two differ the CONTRACT wins" and it places the highway ramp half a cell further
  in than `Highway.placeRamp` does. So the render Ben uses as the Studio reference cannot show a
  placement bug in the client. Read that docstring before treating a plotrender PNG as evidence.
- **Polyline numbering differs by one between the trees:** client `for polylineIndex, points in
  polylines` is 1-based, `streetplan.Network` / plotrender use `enumerate` (0-based). Harmless for
  ordering, but any `Noise.Hash` key built from it (`{polyline}:{stretch}:{step}`) yields different
  values in the tool than in the game — planter yaws diverge.
- **Measure a generated kit without Blender:** stub `bpy` (`sys.modules["bpy"] = ModuleType(...)`)
  and import `tools/assets/<kit>_kit.py` — the `Part`/`sweep`/`pier` classes are pure Python, so
  `part.bounds()` and `part.tris` verify contract numbers (highway: surface 7.07, soffit 6.10,
  parapet 7.87, deck z ±3.58, ramp x −3.5…17.5 falling 7.07→0.07). A ~110-line GLB reader (chunks →
  accessors → node TRS) then composes a whole blueprint's bbox from `assets/kenney3d/<kit>/Models/
  GLB format/*.glb`: ParkingGarage 8.98², CityHall 8.97 × 7.68 front at −4.50.
- **The harvest batch is a gate nobody checks.** `tools/assets/harvest.luau`'s `ASSETS` list must
  name every model whose `modelAssetId` changed. This round it listed only the four Highway props
  while `CityHall` and `ParkingGarage` had also been re-uploaded (commit a0763f9), so
  `py tools/assets/gen_templates.py --check` FAILs with 6 problems and calls all six committed
  `.rbxmx` **strays** — regenerating deletes them and those slots spawn placeholders. Always run
  that check and read the "stray" lines, not just the "uploaded but not harvested" ones.
- `Highway.placeRamp` puts the ramp prop origin at `junction + direction * tileStuds/2`, but the
  prop's own origin is its first cell's CENTRE, so the ramp's 7.07 high end lands on the junction
  cell centre and dives under the junction deck: a ~1.32-stud step at the mouth. Same convention as
  the old kit blueprint, so it predates the new geometry; it is only now legible.
- Minor but recurring: `CityDressingController` reads `parkStrips.treeStage` with a bare
  `math.floor` while every sibling uses `RoadGraph.BudgetValue`/`numberOr`; `TileRenderer.syncStrips`
  builds its `laid` cut list by iterating two hash tables (`pavementRects`, `paved`), so the *piece*
  decomposition — and therefore which strips survive the shared `budget.tileCells` — is not provably
  equal on two clients (never binds at 38 cells of 180).

**M9 wave 2b (2026-09-23, Orbital dressing + cityDetail, SHIP with 2 Majors).** Server side is tiny
and clean: schema v6 migration `[5]` (if-nil, runs after `Reconcile` in both places), validator
whitelist + `DataService.SetSetting` branch + delta field; Main.server's RequestSetSetting only
rebuilds for `vipSkins`, so cityDetail costs the server one bool write. Client: `detailPolicy` in
CityDressingController is the one policy function; thinning reuses the `(i*cap)//total` rule;
`Highway` loop mode = `hasRamp` flag (Metropolis path byte-identical). Missing tile templates draw
`placeholderCell` slabs (so an unharvested tiles era is still playable).
- Verification that worked: `streetplan.py` Village/Boomtown/Metropolis text AND PNG md5 identical
  between HEAD tools and working tools (both run in scratch trees with the working `src/`); stub-bpy
  import of `tools/assets/{tube,monorail}_kit.py` gives tris/bounds/open arms + determinism in 30 lines.
- **Recurring pattern (new): a lane graph through ring-corner CELL CENTRES is fine for cars on a
  7-wide deck but not for a vehicle that must sit on a narrow beam.** `RoadGraph.LoopLanes` goes
  corner-centre to corner-centre and Traffic pivots there; MonorailCorner's beam is a 3.5-radius arc
  about the inner cell corner, so the train leaves the 1.6 beam by up to 1.45 studs at each corner.
  Whenever a vehicle rides a prop, compare its lane polyline with the prop's own centreline.
- **Recurring pattern: layout comments lie about containment.** Orbital's comment says "rock fields
  on the open regolith" while every one of the six zone centres lies inside a decking `blocks` rect
  that runs to the plot edge. Check zone centres against block rects numerically; streetplan does not.
- Git Bash trap: `grep -c $'\r' file` matched every line here (reported CRLF on LF files). Count CRs
  with `tr -cd '\r' < f | wc -c` instead.
- `docs/ASSET_MANIFEST.md` goes stale on any era-JSON rename (slot name column); gen_asset_manifest
  run from a scratch copy without `assets/` prints "n/a" columns, so diff only the changed rows.

**M9 wave 2c (2026-09-23, living city, worktree `tycoon-wave2c`, SHIP AFTER FIXES: 0 Critical, 4
Majors).** Client-only confirmed (server reads only tier thresholds + buildingLift). New modules
Walkers/Ambient copy Traffic's shape (connect Heartbeat only while live, BulkMoveTo, prune on pcall
fail) and are clean; every prop goes through `PropFactory.Spawn` → `sealPart`, smoke is an Attachment.
- **Recurring pattern (new): a new lateral LINE (walker lane, lamp row) must be checked against every
  existing solid on that line, not just the new category.** Boomtown walkers at `pedestrians.offset`
  4.8 = row-lamp reach (4 + 0.8) exactly, and 0.2 inside the front of 6 existing house lots (front
  4.6 from centreline); Metropolis walkers at 5.5 run through all 5 subway kiosks (kiosk from 3.6).
  streetplan checked only bays vs walk lanes. Probe: import `tools/streetplan.py` as a module
  (`sp.Era`, `sp.Network`, `sp.visible_network`) from a scratch script and measure lines vs polys.
- **Recurring pattern: "expected yield = count × plantable share" ignores the pieces' own spacing.**
  A Monte Carlo of the client rule (count draws, no redraw, mutual clearance) gave median zone yields
  21/17/12 vs perTier max 24/28/16 → tiers 4–5 add no zone greenery though streetplan is green.
- **Degradation trap:** `tier < cfg.firstTier` and `tierForRank(nil, ...)` evaluated before a cap
  check turn a removed config key into a runtime error inside deferred `sync` / `Scatter.Plan`.
  Grep every new `cfg.x` compare/iterate for a `numberOr`/type guard when a contract says "missing key
  → feature absent".
- The lead committed into the worktree mid-review (HEAD moved to f97499a); re-run `git log` before
  reporting and name the commit reviewed.

**M9 wave 2d (2026-09-23, half-size cars ×4 traffic, 2 parked per bay; + merge_stages mirrored-node
winding fix; SHIP w/ 1 Major).** Client+config only; `PropFactory.Spawn(..., scale)` ScaleTo's about
the Base PrimaryPart before PivotTo, factor 1 never calls it; Traffic/Walkers read part offsets after.
- **Blender is installed** (`C:/Program Files/Blender Foundation/Blender 5.2/blender.exe`). A 30-line
  `-b --factory-startup --python` script settles mesh-API questions empirically: on 5.2.1,
  `Mesh.transform(det<0)` leaves winding AND custom corner normals inward, and `Mesh.flip_normals()`
  flips both (corner normals follow). Measure "outward faces / corners vs centroid" before/after.
- **Recurring pattern (new): density ×N on a no-headway Traffic loop.** Every car shares one speed and
  there is no spacing rule, so two cars merging at a junction within ~length/speed stay fused until a
  branch splits them; overlap frequency scales ~N². Ask for headway or entry-occupancy on hop.
- Parked packing pattern: extra draws appended after the first-pick loop on the salted stream keeps
  the old plan; greenery keeps full-size bay solids via `bayPosition` + one solid per bay.
- plotrender.py ignores `vehicles.scale` and renders no parked cars — the Studio reference drifts.
