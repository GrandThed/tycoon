---
name: l4-real-forest-review
description: L4 reviews (the real forest; W3 slice 2 combat server 0C/1M/4m/4s: Reset re-opens the auto-start, so a failed trip home (rejoin re-reads GetJoinData, 2 h ticket) auto-starts a solo level after a run, and the resetOpened pin enforces it; run-list arrival cancels the start at zero; party raiders count != kills; P's era multiplies real saves; W3 slice 3 clients 0C/0M/3m/5s: hub modals under the TouchGui jump button at DisplayOrder 0, a star derived from firstClear lines misses Normal, client logic ungated; W2 fix diff 0C/0M/3m/4s: predicates under pinned calls and K3's client half ungated, a 15-degree sector gate hides a 10-degree hole, relative-ulp guard misses 0-vs-tiny; W2 slice 1 server 0C/0M/3m/3s: Transparency-hidden Parts let Roblox's default camera through in the 10 s summary, Accept's malformed guards untested and no pcall at dressOf, dress conditions unpinned = slice 4 m2; W2 slice 2 scenery client 0C/0M/4m/4s: undo wraps one step, client-fail keeps invisible walls, lookup before game.Loaded; W1b deletes the C1 mission code, proves dashes by the ring, sends RunState cells once per floor set) - W1b slice 2 run + client 2026-10-21 0C/0M/2m/3s (client half of a send-once protocol and the send branch unpinned, 7 probes survive; one-shot cells applied after the throw-prone new-level branch); CombatUIController has no harness pin at all; old CombatArena group really was registered; W1b slice 1 server + shared 0C/0M/4m/2s (dash proof's verdict condition unpinned; proof in WeaponService's Heartbeat vs decision in VitalsService's: order unspecified; test (a) green by phase luck; a 3.4-stud root flick proves a dash; timing-study recipe with real pure modules under luau.exe); W1b fix diff 2026-10-22 0C/1M/2m/3s (held hits released together skip the knock rules 6/18: an unproven wall dash takes 2 hits where no dash takes 1; folding Vitals' Heartbeat into WeaponService's loses the implicit connect pin and couples errors); W1b fix2 diff 2026-10-22 0C/0M/3m/2s (M1 fixed; sim G1 mirror's one gate line blind to 7 of 8 moment mutants though a 600-course Luau/sim cross-check agrees; boss-room clear drops held blows; stepFailed unpinned; walks not throw-safe)
metadata:
  type: project
---

L4 W1b is on branch `l4-w1b` in worktree `tycoon-p5b` (no `tools/bin/luau.exe` there: use the main checkout's). Brief:
`docs/prompts/l4-w1b-review.md` (three slices). Findings go to `docs/prompts/l4-w1b-review/<slice>.md`. Contract:
`docs/prompts/l4-w1b-contract.md` (rulings L4B-1..9).

**Several slice reviewers may share this file. Re-read it and Edit only your own section. Never Write it whole.**

**Why:** later L4 waves (W2 raider models, W3 the city map that deletes `Config/Missions` and Overdrive, the publish)
build on the send-once RunState floors and the dash proof.

**How to apply:** for any "send once, keep on the client" change, run the probes below on both ends before trusting
the pins.

## W3 fix diff (2026-10-23, 36b54c0..3503134, rulings F1-F19): 0 Critical, 0 Major, 4 Minor, 2 Suggestions

Findings: `docs/prompts/l4-w3-review/5-fix-diff.md`. Baseline `HARNESS: PASS (5,402 checks)` in 70 s on a `git archive`
copy; `mutate.py` 2,382 entries, 0 stale.

**Patterns (recheck these):**
- **A "once per server" flag also fires on a session that ended before anything started.** F1 (`departOpened` kept
  across Reset) closes M1. But a party whose first-admitted member drops while the depart is `waiting` resets the
  session, and the departing host then lands with no auto-start AND no pick: the map opens on FirstPick, not the chosen
  difficulty. At the base commit the host got `picked` after 30 s. For any "spent" flag, walk the Reset-while-waiting
  case, not only Reset-after-done.
- **New code written inside a "pin the conditions" round still arrives with unpinned inputs.** These all passed:
  - F2's gather: `userId = member.userId` and the `GetMembers()` loop in `lateAtZero`;
  - F9's dungeon call-site argument `sitesOf,` (the hub's twin call is pinned whole);
  - two lines of the client's pick branch: `st.mapSeeded = true` and `armoryScreen.Close()`.

  Probe every new helper's field lines and every argument line of a re-pointed call.
- **A "drop" rule that exists only as a server warning while the client applies its own rule.** F6's note drop on the
  server is a warn that says "the map shows no note". `MapScreen` reads the level file itself and keeps any non-empty
  string at any length. Check the client reader whenever a server "drops" display data.
- **A strict reader adopted by every host must pass every card the server builds, degraded fallbacks included.**
  ReturnService's zero card takes `title = ""` when `Config/Expeditions` is missing, and `RunLines.ReadSummary` (1-48
  bytes) drops it. ArenaService's session card has a `DEFAULT_SESSION_NAME` fallback; ReturnService does not.

**Verified, safe to reuse:**
- `TallyRules.Depart` matches the old CombatUIController branch for branch. `mapScreen` is built before the RunState
  listener connects.
- TouchHold and ArmoryScreen's R9 toggle are kept apart by close order (the map's open closes the Armory first; the
  Armory's open goes only through `togglePanel`, which closes the map; the report closes both). The hub passes
  `padToggle = false`.
- **`Montserrat-Bold.ttf` (GothamBold's face) has U+25C6 ◆.** Recipe: scratch `l4-w3-rev5/py/cmap.py <fontsDir>`
  parses cmap formats 4 and 12 with no fontTools.
- ProfileStore 1.0.3 sets `ProfileStore.DataStoreState` together with its local (`:2101-2109`), so
  `DataService.IsMockMode()` is exact once settled.
- `Format.Cash` and `Format.Duration` terminate on any finite number (the suffix letters stay under byte 255 up to
  1e308).

**Recipes (scratch `l4-w3-rev5/py/`):**
- `probe.py <tree> <luau> <probes.json>` runs the harness per source edit, about 70 s a probe at 5,402 checks.
- `probe_print.py` takes the same JSON. It inserts a `L4W3R.group(...)` that prints `PROBE` lines into a tests file
  before an anchor comment, which gives a behaviour probe on the real pure modules.
- `stale.py <tree>`: the `mutate.py` stale check without a run.
- The static gates go on a second archive (`tree2`): copy `rokit.toml` in for stylua and selene, and `luau-compile` and
  `luau.exe` into `tools/bin`.

## W3 slice 1, the hub server and shared code (2026-10-23, `l4-w3` 93eb8e9 in `tycoon-p5`): 0 Critical, 0 Major, 3 Minor, 2 Suggestions

The findings are in `docs/prompts/l4-w3-review/1-hub.md`. The brief is `docs/prompts/l4-w3-review.md`, which defines four
slices. The contract is `l4-w3-contract.md`, and its §14 (L4W3-12..18) is the lead's.

**Patterns (recheck these):**
- **A rule moved into one pure shared module is gated only on the module side.**
  - L4W3-1 put `MapRules.Startable` behind both the hub's Depart and the dungeon's start.
  - `tests_l4w3` and `mutate.py` cover the pure rule.
  - The hub call site and its arguments are unpinned: the leader's stars, `file.difficulties`, and the
    `verdict ~= "ok"` branch. So are SendMap's leader rule, StudioBridge `readSummary`'s `RunLines.Read`, the
    `ReadArrival` caps and the HubRemotes validators.
  - All 7 probes PASS 4,994.
  - Ask for pins on the call's arguments at each call site, not only on the rule.
- **"Every bad field drops its line" with one bad value per field proves half the rules.**
  - Each field has two rules: finite and >= 0, or string and <= 48 bytes.
  - One bad value tests only one of them, so 6 of 10 halves survive.
- **Validate the whole teleport-data record, not only the new part.**
  - `readSummary` routes `lines` through RunLines.Read.
  - `title` has no length cap, and the totals are only typeof-number (NaN, inf and negative values pass). The client's
    `readRunSummary` is the same.
  - The effect is self-only display, so the finding is Minor.
- **A "shared" map path is still half copied.** The hub's SendMap repeats WaveService's `sitesOf` / `secretRows` line
  for line.

**Verified, safe to reuse:**
- MapRules matches the old code verbatim: StageFlow `:2863-2982` and SecretFlow `:62-145`, `:345-360` at dce50da. To
  check, normalise the names and diff.
- On the shipped data, hub ok ⇔ dungeon ok. The dungeon adds `resolveLevel` (Validate, `WeaponService.IsActive`) and
  `busy` states, which are config or runtime faults that degrade to `picked`.
- `Unlocks.StarsOf` creates `combat.stars = {}` when it is missing, also on a hub read of the leader's profile. This is
  harmless.
- `stampDeparture` runs inside `handOff` before the bridge branch, and Depart and Join both go through `handOff`. The
  pins `stampThenBridge` / `stampOnce` / `okInHandOff` / `departHandsOff` cover it, with 3 mutants.
- `Combat.EraCashMult`:
  - an empty list indexes 0 and returns 1;
  - an era under 1 takes the first entry, one past the list the last;
  - a hole in the JSON list makes `#list` ambiguous, but the result still degrades and never errors.
- Baseline at 93eb8e9: `HARNESS: PASS (4,994 checks)` in about 25 s on a `git archive` copy.
  `check_compile` covers 187 files.

**Recipe:**
- `scratchpad/l4-w3-rev1/scripts/probe.py` works like W1b's.
- `git archive` also brings in `Packages/` and `ServerPackages/` stubs. `rojo sourcemap` fails in that copy, so write the
  sourcemaps from the worktree with `-o <scratch>` and run luau-lsp from the worktree.
- For `check_compile` in a copy, copy `luau-compile.exe` from the main checkout's `tools/bin`.

## W3 slice 2, the combat server (2026-10-23, 93eb8e9): 0 Critical, 1 Major, 4 Minor, 4 Suggestions

Findings: `docs/prompts/l4-w3-review/2-combat.md`. The code under review: the auto-start (StageFlow.Depart*, WaveService
tickDepart/openDepart, ArenaService Pick/ExpectedIn/HostIn), RunCredit (card lines, pay era), the R and P levers, and the
MapRules re-pointing.

**Patterns:**
- **"Once per session" on a reserved server is not "once per departure".**
  - Reset clears `departOpened`. The last member's Return then fails, and `abortReturn` → `rejoin` → `runJoinSequence`
    re-reads `GetJoinData()`.
  - The hub's `codes` ticket lives 2 h, and `RunRegistry.Clear` removes only `runs`. So the fresh session verifies again
    and the solo level auto-starts after a run (M1).
  - The pin `resetOpened` (count 1) enforces the bug.
  - Studio cannot show it: the handoff record is consumed at the first arrival.
  - For any per-session state, walk resetSession's "a rejoin after a failed trip home opens a fresh lobby".
- **A rule that excludes someone from a hold must exclude them at the action too.** Deviation 3 left non-expected members
  out of the countdown's body check, but `startLevel` still checks `AllHaveBodies(members)` at zero, so they cancel the
  start instead.
- **"One per credit" is not "kills" in a party.** The raiders count is the bodies a member damaged, while the city card's
  subtitle prints `summary.kills`.
- **A lever that "saves nothing" can multiply what later runs save.** P only sets `boot.cashEra`, but credit writes
  `state.cash` at it, into the real save with API access on.
- The pins-hold-calls family again: 19 of 20 condition probes pass 4,994. Among them are the `departOpened` guard,
  ExpectedIn's `return false`, the refusal branch and `depart` in pushRunFields/BuildRunState.

**Verified, safe to reuse:**
- `ReturnService.SendHomeGroup` is uncalled. Only `SendHome` (Return) leaves, and it is personal.
- `startLevel` never yields (LevelService Build/Clear never yield), so starting it from the Heartbeat is safe.
- The combat place leaves `CharacterAutoLoads` on, so a body usually exists before the profile-load admit.
- The client ignores a `picked` level with no map node (`DepartLine.NodeOf` nil guard).
- The hub's `STUDIO_ACCESS_CODE` and RunRegistry's `STUDIO_PRIVATE_SERVER_ID` are both "studio".
- `check_stage_mirror.py` PASSes on the archive with StageFlow's `NEEDED` unchanged.

**Recipe:** scratch `l4-w3-rev2/py/probe.py` (each probe about 25 s; `mk1.py` and `mk2.py` write the JSON). As slice 1
found, the archive's Packages are stubs, so run luau-lsp from the worktree with `rojo sourcemap ... -o <scratch>`.

## W3 slice 4, data, sims and gates (2026-10-23, 93eb8e9): 0 Critical, 0 Major, 2 Minor, 4 Suggestions

The findings are in `docs/prompts/l4-w3-review/4-data.md`. Era cash = Ben's (c) at M = 3, `[1, 670, 34000, 1400000]`,
in `Combat.CombatCashMult`. The new sim_combat assertions are 24 "never faster" (back to back via `simulate_era(pause=)`)
and 25 "a few minutes".

**Patterns (recheck these):**
- **A "never faster than X" gate plays one interleaving.**
  - 24 runs from the era's first second to its end.
  - "k runs, then build every second" (min over k) beats the greedy city in every era: Hard Boomtown -2.4%, Metropolis
    -1.4% (k=8), Orbital -0.5% (k=12), Village -6.8% at today's pay.
  - Cause: a free player's wallet is empty right after an Advance, so a run costs almost no purchases. No multiplier
    of at least 1 avoids it.
  - Ben's click text "No way of running beats building" and BALANCE.md were false. MISSIONS_DESIGN §30's
    "back-to-back runs never finish sooner" is what passes.
  - The (a)-vs-(c) ranking held on the mixed course: (a) -2.5 / -2.1%.
  - For any pacing claim, probe the start-then-stop and the one-run families, not only the gate's course.
- **A new Validate line with no Python twin.**
  - StageFlow's `note` rule refuses the whole level, and `sim_range.level_problems` lacks it.
  - So `check_levels.py` PASSes a 27-byte note that the game makes `unavailable`.
  - check_stage_mirror DIFFs, but in 5 families and as a mirror fault.
  - Every Validate line needs its twin and a broken-once case.
- **A comparison where one side delegates to the other is a tautology.** "HeldFamily is LoadoutOf's slot" compares
  HeldFamily with itself once SavedPower's half went.
- **A shipped-data check that loops over `x or {}` passes when the data is deleted** (tests_l4w3 upcoming).

**Verified, safe to reuse:**
- `sim_economy.py`'s default output is byte-identical to `econ_base.txt` under 3.12 and 3.14.
- The `pause` hook lands the cash first, then `skip` blocks that second's purchases.
- Luau SplitCarry and Python split_carry use the same operand order, so the era-scale proof transfers.
- The harness label diff base -> head (4,713 -> 4,994): 37 labels left, all Gear Power or reworded or dynamic.
- `mutate.py`: 2,224 entries, 0 stale. 22 dropped (Gear Power), 21 changed, 117 new. B's 75 match `luau-b-mutants.py`
  verbatim.
- Timings:
  - `sim_combat --check`: 5 min 12 s (3.12);
  - `check_stage_mirror`: 9.5 s;
  - `mirror_mutants --only L4W3-7`: 1 min 42 s, 9/9;
  - `check_levels`: 29 s, identical to dce50da.

**Recipes (scratch `l4-w3-rev4/probes/`):**
- `never_faster.py <tree>` has three families: the gate's runner, stop-after-k and one-run.
  - `never_faster2.py` takes the env vars `MULTS=a,b,c,d` and `ONLY=Era,...`.
  - About 6 min on 3.12.
- `labels.py base.txt head.txt [added]` diffs the harness's `ok`/`FAIL` label multisets.
- `stale.py <tree>` execs mutate.py up to "# Before anything runs" and dumps `mutations_*.json`. `mdiff.py` compares two
  dumps.
- To bite: copy `src`+`tools`, sed the config, then run `py -B tools/sim_combat.py --check` in the copy.

## W1b slice 2, the run and the client (2026-10-21, 1ae8bfb): 0 Critical, 0 Major, 2 Minor, 3 Suggestions

Findings: `docs/prompts/l4-w1b-review/2-run-client.md`.

**Patterns:**
- **A send-once field loses the self-healing a whole-state send had.**
  - Before, every RunState carried the cells, so a handler throw on one message cost 0.25 s.
  - Now the cells-bearing RunState is the same one that changes `levelId`. `onRunState` runs the new-level branch
    first: `rewardedKinds`, `SecretFx.SetLevel`, `faceFrom` → `routeForward` over the layout JSON, `Prewarm`.
  - So one throw there loses the cells for the whole run.
  - Ask for one-shot fields to be applied first in the handler. Recheck every future delta or "once per seq" payload.
- **The pins on a send path count the call lines, not the branch that decides whether the payload goes.**
  - `if cellsWent then` → `if false then` survives (no client ever gets a cell), and so does `or true` (the
    bandwidth win undone).
  - This is the same family as "a text check pins a call, not its inputs" ([[l3-armory-review]]). Pin the condition
    line with its indentation.
- **The client half of a protocol can sit under no gate while the server half is pinned.**
  - `run_harness.py` and `mutate.py` name `CombatUIController` nowhere.
  - Four client mutants on `applyFloors` / `onRunState` survive: no Merge, the seq never written, the seq read as 0,
    merging against the incoming list.
  - `tests_l4b_run.luau` proves `RunFloors` through a hand copy (`L4R.Server`, `L4R.receive`).

**Verified, safe to reuse:**
- RunState is a reliable RemoteEvent with ONE client listener (`CombatUIController` bootMission). The only senders are
  `ArenaService.sendRunState` and ReturnService's leave card, which has the same seq and no cells.
- `WaveService.setFloors` is the only writer of `run.floors` and `boot.floorsSeq`. Every `run = freshRun()` is
  followed by it with no yield. `pushRunFields` hands floors and seq over in one table.
- `CrowdRenderer.ReadCells(nil)` returns nil, not `{}`. Cells feed only `laneReach`, the drawn bound of a brute's
  charge, so losing them is a WYSIWYG drift and not an exploit.
- **The old `EnemyService.ArenaCollisionGroup()` DID register `CombatArena` and `CombatRagdoll`**: `newPart` called it
  for every range part. luau-b's report says otherwise, but the outcome is harmless: a fresh group collides with every
  group, and BarrierGroups copies Default's rule.
- The crowd's client folder is `CrowdBodies`, with CanQuery false. `Workspace.Enemies` was only EnemyService's.
- `Theme.MIN_SCALE`'s `math.min` list holds no combat size. A Python scan of Theme keys against `src` and `tools`
  takes a few seconds (996 keys, 0 unread at 1ae8bfb).

**Recipes:**
- `scratchpad/probe.py <tree> <luau> <probes.json>`. Each probe is `[label, [[file, old, new], ...]]`. It runs the
  tree's own harness and restores the files.
  - The tree is `git archive HEAD src tools combat.project.json default.project.json`.
  - Each probe takes about 18 s.
  - `mkprobes.py` builds the JSON, which avoids hand-escaping tabs.
- luau-lsp per tree with `rojo sourcemap <project> -o <scratch>`, run from the worktree. Both trees came back clean in
  about a minute.

## W1b slice 1, server and shared (2026-10-21, 1ae8bfb): 0 Critical, 0 Major, 4 Minor, 2 Suggestions

Findings: `docs/prompts/l4-w1b-review/1-server.md`. The code under review: DashProof (L4B-7), the RunFloors module
(L4B-8), and the deletions in WeaponService, VitalsService, StageFlow, LevelGeometry, Combat, Armory, Catalog and Types.

**Patterns:**
- **Moving a state change from a remote handler into a Heartbeat creates a handler-order dependency.**
  - L4B-7 moved the dash window's opening from `OnDash` into WeaponService's `trackAir`.
  - VitalsService decides hits on its own Heartbeat. `VitalsService.Start` connects it first, inside
    `WeaponService.Start`.
  - A proof made in the decision frame counts only if WeaponService runs first, and Roblox does not specify the order.
  - Under bunched 20 Hz replication a proof only lands on an arrival frame, so losing that frame loses a whole update
    cycle (the mean late edge moves 15-18 ms, up to 64 ms).
  - List every other per-frame reader of the moved state, and the order the code assumes. The harness's fixtures
    usually run the favourable order.
- **The pins held the calls, not the condition between them (the same family as slice 2's).** Each of these survives
  `HARNESS: PASS 4,075`:
  - `if verdict == "proven"` → `~= "lapsed"`, which undoes L4B-7;
  - `if claimAt ~= nil` → `== nil`, which throws in every Heartbeat;
  - the lapse clear dropped.

  Ask for the per-frame decision as a pure function in the tested module.
- **A timing bound asserted at hand-picked phases.** Test (a) checked "proven within 0.05 s of the first moving
  sample" at leads 0 and 0.02 only. A lead sweep over one update cycle gives 0.100 s at 20 Hz bunched. Sweep the
  phase of any sampled-timing test.
- **A "proof" built from a client-owned root's replicated position is not anti-cheat.** These all prove a claim:
  - one replicated flick of 3.4 studs out and back (net 0): 40 of 40 phases;
  - an ability flight in the 0.3 s lookback;
  - a catch-up after a stall.

  Say what the rule buys: it stops a request-only forger and a dash into a wall.
- **A contract's feel claim can contradict its own model.** "A dash pressed at T still dodges" cannot hold when the
  decision's server copy shows the client at T. At ping 0.1 the late edge moves 28 ms (60 Hz), 45 ms (20 Hz) and
  88 ms (bunched) on average. Studio, with ping 0, understates it.

**Verified, safe to reuse:**
- `DashProof.Open(from = now)` is the old `openIframes` branch for branch, because every window's `From` is at or
  before now.
- Server body moves call `ForgetMotion`, which clears the ring: MoveMember through the moved hook, the GateNudge, and
  the rescue.
- `rootOf` returns nil when `Health <= 0`, so death clears the claim.
- The cooldown 0.8 × tolerance 0.8 = 0.64 s is longer than the lapse of 0.45 s, so two claims never meet.
- Leap Smash and Impale Dash grant i-frames on the cast request (`AbilityService:444, 461`); contract §4.4 allows it.
- `check_compile --counts`: WeaponService 100 (FeedbackController is the largest at 163), 176 files.

**Recipes (scratch `l4w1b-s1/`):**
- `probe.py` runs the same way as slice 2's, about 17 s a probe, on a full `git archive HEAD` copy.
- **Timing study with the real pure modules.**
  - `mksim.py <repo> sim.luau` concatenates a Vector3 stub (`new`, `zero`, `__sub/__add/__div/__mul`, `Magnitude`
    through `__index`), `PositionRing.luau` and `DashProof.luau`. It strips the requires and `Types.*`, then appends
    `study.luau`.
  - Run the result under `tools/bin/luau.exe`.
  - The model: the remote and the motion arrive `u` later; a 60 Hz Heartbeat records then judges; the decision is at
    `T + min(2u + 0.05, 0.3)`; sweep the phases and the press time.
  - A full sweep takes about 30 s.

## W1b slice 3, data, sims and gates (2026-10-21, 1ae8bfb): 0 Critical, 0 Major, 3 Minor, 4 Suggestions

Findings: `docs/prompts/l4-w1b-review/3-data.md`. Its verdict-branch item overlaps slice 1's Minor 1: count it once.

**Patterns:**
- **A simulator mirror of a proof can match the formula and still miss when the proof arrives.**
  - sim_range's `dash_proof` judges the covered distance at the dash's start, and the window counts at once, even for a
    hit decided in that frame.
  - Probe (hits voided only by a dash window, Forest Road): 33 of 85 had their dash begin in the decision's own frame,
    and 66 within 0.05 s.
  - Modelled (2 Heartbeats or 0.05 s, in `shielded` and `plan_shielded`): no gate flips, still the same FAIL (1).
  - But the R8 row moves x1.60 -> x1.65, 69 of the 145 forest lines print other numbers, and the human takes 1-2 more
    hits per Hard or Brutal run.
  - So "0 unproven, no run moved, byte-identical" was an artifact of the mirror.
  - Rated Minor because no gate flips. Had a gate gone red under the faithful mirror, it would be Major, as in the L3 W1
    slice 2 per-family scale case.
- **A pin on "no X in OnDash" counted one spelling.** `dashNoOpen` counts the literal `openIframes(`, so an OnDash that
  calls `WeaponService.GrantIframes` (or `DashProof.Open`) opens on the request with `PASS 4,075`. Count every route to
  the guarded state, not one name.
- **"The only guard" on a rule can be a hand copy.**
  - sim_combat 12 and 13 test `mentor_pay` (Python), and nothing ties it to `WaveService.payMentors` or to the Luau
    `Combat.MentorBonus`.
  - Three Luau mutants survive, and check_stage_mirror has no MentorBonus comparison. The gap predates C2.

**Verified, safe to reuse:**
- **The hand-written field fixtures do exercise their rules.** These are `L1.fieldLevel` / `L1W.field`, and
  check_stage_mirror's `FIELD_LEVEL` / `FIELD_LAYOUT`, three copies that agree.
  - The harness catches mutants of merge, merge-into-boss, the director's breather and the gateless locking barrier.
  - check_stage_mirror alone catches the StageFlow three (FAIL 9 each).
  - FIELD drops the old arena's `guard` price.
- **`mutate.py`'s stale check without a run:** exec its source up to `# The unmutated bundle first.` with a fake argv
  (`stale.py`). At 1ae8bfb: 1,693 entries, 0 stale.
- **A full Forest Road clear counts 2 waves on the hub card.** Only the locking boss room emits StageFlow `clear`; open
  camps emit `campClear`. The hub stub says `waves` 3.
- **`check_stage_mirror.py` PASSes under both 3.12 and 3.14.** `sim_range --check --levels-only --level forest` takes
  about 20 min.

**Recipes (scratch `l4w1b3/`):**
- `probe.py <tree> <luau> <probes.json> [stage|stageonly|levels]`. "stageonly" runs check_stage_mirror alone, about
  10 s.
- `dash_late.py <repo> levels` takes about 13 min.
- `dash_delay.py <repo> <delay> --check` is sim_range with the proof latency modelled, about 25 min. Its outputs are the
  same at 0.0334 and 0.05.
- Never `import` the tools from the worktree's `tools/`: it writes `__pycache__` there. Point `sys.path` at the copy.

## W1b fix diff (2026-10-22, a098eaf..f16515a): 0 Critical, 1 Major, 2 Minor, 3 Suggestions

Findings: `docs/prompts/l4-w1b-review/4-fix-diff.md`. F1 is the hold: VitalsService keeps a decision that a pending
dash claim would cover until the claim is proven (voided) or lapses (it lands). `VitalsService.Step` is now run from
WeaponService's one Heartbeat.

**Patterns:**
- **A hold that releases several decisions in one frame skips every rule that orders them.**
  - The knock exemption (`other.hold == nil`) was written for "held earlier, then a later knock".
  - Two held hits release together at the lapse: the first knocks, the second is held, so neither ruling 18 nor the
    knock's own i-frames void it. Both land.
  - Measured: a claim that never proves loses 16 where no claim loses 8, in three orders. The sim mirrors it.
  - Ask for held decisions judged at their own moments, and a player's later decisions queued behind a held one.
  - The harness pinned the opposite direction (the mutant "a knock voids a held hit" is caught), so the gap was
    invisible.
- **Folding one module's Heartbeat into another's handler loses an implicit pin and couples errors.**
  - The old `vitalsBeat = beats[#beats]` caught "Vitals connects nothing". I proved it on the a098eaf archive.
  - Now `RunService.Heartbeat:Connect(step)` in WeaponService gates every enemy hit, and no gate pins it: `Connect(function() end)`
    survives.
  - A throw in either half now stops the other (no pcall, no task.spawn). Suggest `task.spawn` per half (it runs
    synchronously, keeps the order, and reports the error) or `xpcall`.

**Verified, safe to reuse:**
- A hold never outlives its claim's lapse. A newer claim cannot extend it: decideAt is at most claim + 0.55, under the
  cooldown of 0.64.
- `ClearThreats` takes held entries, `onGone` keeps them, and a respawn drops them through `hold.humanoid`.
- The MentorBonus mirror is real. `rate <= threshold` gives FAIL (7), `return 0` gives FAIL (16).
- Count-0 regex pins share their body with count-1 pins, and `l4b_reading` reports missing bodies, so they are not
  vacuous.

**Recipes (scratch `l4w1b-fix/`):**
- **A behaviour probe in the real VitalsService:**
  1. Copy the tree.
  2. Append a `L4B.group(...)` inside `L4B.vitalsTests` in the copy's `tests_l4b.luau`, using `L4B.fresh`,
     `L4B.claimNow` and `L4B.play`.
  3. Print the `PROBE` lines (`knock_probe.luau`). About 16 s.
- **A sim probe:**
  - `simprobe/knock_sim.py <tree>` under `py -3.12 -I`. Set `sys.dont_write_bytecode = True` and put the tree's
    `tools` first on `sys.path`.
  - Use `ThreatRun` plus `pending.append([...11 fields...])` plus `resolve` per FRAME, as `dash_hold_probe` does.
- **luau-lsp is live but fast** (about 4 s on the changed files). To prove it, plant a type error before
  `return Module`, not after it: appending after the return gives a SyntaxError instead.

## W1b second fix diff (2026-10-22, 0489eef..c01348a, worktree `tycoon-p5c`): 0 Critical, 0 Major, 3 Minor, 2 Suggestions

Findings: `docs/prompts/l4-w1b-review/5-fix2-diff.md`.

What changed:
- G1: a held decision keeps `hold.at` (its moment). Every later decision of that player waits behind it in the per-player
  `vitals.waiting` list. `release` judges each one as of its moment, and `rule(at, now)` dates the knock, regen and
  down from it.
- G2: `xpcall` around each third of `step`.

M1 is fixed: the three probes lose 8 each.

**Patterns:**
- **A mirror's only gate can be blind to the rule it guards.**
  - The fence line's three queues release in one frame, inside one knock window.
  - So 7 of the 8 "from the release instead of the moment" mutants of sim_range's G1 code survive it.
  - The mirror was still right: a 600-course Luau-versus-sim cross-check (same random queues) agreed on every course.
  - When a mirror gets one probe line, ask for a queue whose answer differs between the old rule and the new one.
- **"Effects leave late" reaches the run's state machine.**
  - A held blow is dropped by the boss room's `clear` (ClearThreats empties `waiting`, while onGone keeps it).
  - So an unproven dash or a request-only forger can win a boss race that no dash loses.
  - Check every state reader between a decision's moment and its release: clears, the run verdict, the player's own
    attacks.
- **Containment between parts is not containment within one.**
  - The walks compact after the loop. A persistent throw at entry k re-lands entries 1 to k-1 every frame, and sends
    no effect. Measured: 13 frames, 104 HP, 0 hurts sent.
  - A whole-loop `xpcall` in trackAir starves the shooters after the one that throws.
- **A new handler with no pin** (`stepFailed`): flooding, silence and swallowing each pass 4,185.

**Recipes (scratch `l4w1b-fix2/`):**
- `runprobe.py <tree> <luau> <probe.luau>` indents a probe group into `L4B.vitalsTests` before its regen restore,
  prints the `PROBE` lines, and restores the file.
- `runmut.py` does the same with one source mutation applied.
- `probe_fuzz2.luau` is a fuzz with its own frame loop. It covers rings (`threat.step` every 4th frame), forged and
  honest claims, a pre-L4 window, and a knockIframes sweep.
- `xmirror/`:
  - `gen.py` writes the same queues as JSON and as a Luau table.
  - `sim_x.py` runs ThreatRun with `pending.append` (12 fields since G1, the last being queued) and `resolve` per frame.
  - `cmp.py` compares the two runs.
  - Notes on keeping them aligned:
    - Put impacts on quarter frames, the claim on a half frame, and set knockIframes to 0.41, so no tie lands on a
      frame.
    - The sim keeps hp on a down while Luau sets it to 1, so compare the counts, not the loss.
- `fence_gate.py` / `fencemut.py`: the sim gate line's condition, run alone (seconds) under mutants.

## W2 slice 2, the scenery client (2026-10-22, afdce67, `tycoon-p5` branch `l4-w2`): 0 Critical, 0 Major, 4 Minor, 4 Suggestions

Findings: `docs/prompts/l4-w2-review/2-scenery.md`. Covers LevelScenery (the client builds the forest on
`Workspace.Level`'s `Dress` and `DressHash`, undoes on failure, mood B, levers Y and O), DrawClock, the Frame/Draw perf
line, the Castle Key's card row and map glyph.

**Patterns:**
- **An "undo on failure" that wraps one step leaves the safety rule open to every other throw.**
  - The undo shows the hidden Parts again, but only a mesh clone's pcall reaches it.
  - These throw bare in the build thread: `jobsOf` iterating `props`/`effects` (which the server's Accept never
    checks), `spawnFire`, and `syncMood`/`applyView` in `evaluate`.
  - Any of them leaves solid Parts invisible on every client.
  - Ask for the whole thread under one pcall that calls `fail`, and for server validation of every list the client
    iterates.
- **A client-only fallback is not the server's fallback.**
  - When the server accepts and the client fails, the dress walls still stand, invisible, with no trees to explain
    them.
  - Compare the two fallbacks piece by piece.
- **A Wait guarding one read but not its sibling.**
  - `build` waits for `game.Loaded` before reading the templates.
  - `evaluate` reads `Catalog.GetLevelDress` (a FindFirstChild) at once and stores the key, so an early nil is
    permanent for that run.
  - Check every once-per-key lookup against replication timing.
- **"Applied while dressed" vs "never in the lobby".**
  - Lighting is global per client, and members wait in the lobby camp during a run.
  - Any per-level client effect needs a "where does this player stand" rule, or a ruling that accepts it.

**Verified, safe to reuse:**
- `Workspace.Level` is ONE persistent Folder. Build and Clear change only its children and attributes.
- A Clear followed by a Build of the same key in one frame keeps the client's scenery, which is correct: the scenery
  depends on no server Part.
- `Skinned` is set before the Part is parented, so `ChildAdded` sees it.
- The fire and tent pieces under props are `collide = false` markers. The bramble block is in `hide.keep`.
- The combat camera's `Spherecast` (Exclude characters, Default group) hits invisible blocks: transparency does not
  matter to it.
- `StreamingEnabled` is false in the combat place.
- **Roblox's local fonts hold no GothamSSm: `GothamBold` renders as Montserrat Bold.**
  - The file is `%LOCALAPPDATA%\Roblox\Versions\version-*\content\fonts\Montserrat-Bold.ttf`.
  - Measure it with Pillow (`py`, 3.14): `font.getlength(text) * size / 100` at size 100.
  - Ascent plus descent is 1.23 em. Whether TextSize is the em or the line height is unproven offline, so give both
    numbers.

**Recipes:** scratch `l4w2-s2/measure.py <fontsDir>` measures card and map words.

## W2 slice 3, the raiders and the pose (2026-10-22, afdce67): 0 Critical, 1 Major, 3 Minor, 4 Suggestions

Findings: `docs/prompts/l4-w2-review/3-raiders.md`. Covers Raiders/Figures (pools per kind, the model clone, the
invisible `Head` anchor, the paint, the plate role, the Chief's Warhammer), Raiders/RaiderPose (pure, mirrored against
`tools/testfit/raiderpose.py` by `check_raider_mirror.py`), the threatPose split in CrowdRenderer, Cues' lit piece, the
seated drop in ForEach and InputController, and the X lever.

**Patterns:**
- **A rig rule that removes a whole-body motion removes the tell it carried.**
  - Models take the lunge as a foot step plus an arm key, never a slide. The placeholder's slide was the only spatial
    cue a lunge had (only an arc gets a ground wedge).
  - Drawn reach at the blow: 3.4 (placeholder) -> 2.24 (model). The server's capsule reaches 5.
  - `--check`'s weapon rule is an upper bound only. Ask for a lower bound on any shape with no ground tell.
- **A head rule measured against the config's own head point is blind to the point.**
  - raiderpose's rule compares the drawn head with `anchor`, which is built from `points.head`. Nothing compares
    `points.head` with the scored head (`height - headRadius`).
  - Probe: a fodder head at 4.6 (scored 4.3) passes `raiderpose --check` and `raider_frames --check --require-harvest`.
- **A prewarm paced N a frame cannot beat a batched spawn one server step later.**
  - The RunState and the batched `CrowdSpawn` arrive at most 67 ms apart. 4 a frame builds about 16 of about 110, and
    the rest are built synchronously in the spawn handler.
  - Check the arrival gap against the pace before trusting a prewarm.
- **The mirror covers the pure module; the glue that feeds it is unpinned.** No tool reads Figures, CrowdRenderer or
  Cues: the lean split, the anchor height and ForEach's `drop` all go ungated. This is the same family as W1b slice 2's
  client half.

**Verified, safe to reuse:**
- The shared `threatIn`/`threatOut` scratch is fresh whenever Figures.Pose reads it: threatPose always runs when the
  threat is not "none", and `stepRush` never sets a threat.
- The client seeds the seat at 1 on a body's first sample at rest (`CrowdRenderer:1682`), as the server does at spawn
  (`CrowdService:2335`).
- WeaponModels.json's Warhammer grip is [0, 0, 0], so Figures' "Base = grip" holds for it.
- `check_raider_mirror` worst difference is 3.1e-8: an `asin` near ±1 in `placeLeg`, not drift.
- `raider_frames.py --source X --out Y` writes and checks a scratch copy, so config mutants need no worktree write.

**Recipes:**
- Scratch `worst.py` imports `check_raider_mirror` with `sys.dont_write_bytecode = True`. It prints the worst case's
  label.
- Head-point probe: `json` edit -> `raider_frames.py --source copy --out out` -> `--check --require-harvest` on both
  -> `raiderpose.py --check --no-extent --models copy`.

## W2 slice 4, data, sims and gates (2026-10-22, afdce67): 0 Critical, 1 Major, 4 Minor, 3 Suggestions

Findings: `docs/prompts/l4-w2-review/4-data.md`. Covers the Chief's config, R8 over whole runs (`sim_range --r8`), the
seat in sim_range and check_stage_mirror, check_levels' dress walls and drawn bodies, raider_frames, check_raider_mirror
and the harness pins.

**Patterns:**
- **A gate whose reference changed while the subject's other half did not measures the gap between the halves.**
  - R8: the reference became the pair player (sword and bow), but the sniper's fight half stayed sword-only
    (`R8_FIGHT`). The gated ratio is about sword / pair (0.61 at bow T4) plus the spot.
  - The tell: spots that never shoot read the weapon gap (x0.574-0.595 against 0.613).
  - Measure the faithful reading (both runs alike but the thing judged) and state its margin: 1.3-1.8% here, against
    the gate's 19-61%.
  - Clock mutants (x7, x18) do not prove sensitivity. Ask for one sized to the faithful margin.
  - Rated Major, as L3 W1's "pair gates pass for the wrong reason".
- **A reach reconciled from the max over a whole motion can come from outside the hit shape.**
  - The Chief's hammer peaks at 17.10 behind his shoulder (105-180 degrees), and `range` 17 was set from it.
  - Inside the +-75 degree wedge it reaches 14.4-16.35, and never the left 45-75.
  - Tabulate the reach per sector of the shape.
- **The pins-hold-calls family again.** All 6 condition probes on LevelService and WeaponService pass 4,412. The worst
  hides the pieces and arms the walls but never announces `Dress`.
- **A per-post max by one key, then a second key read from the kept entry.** `walled_bodies` keeps the widest radius,
  then reads that kind's drawn reach. The two orders differ for slinger/fodder and armoured/brute.

**Verified, safe to reuse:**
- `raider_frames`' turn proof is real:
  - each MeshPart's box, placed by `template_placement`, fills its piece's bounds;
  - the sidecar corners come back;
  - 35 of 35 stages fail unturned.
- `check_raider_mirror` runs the real `RaiderPose.luau`: 14 of 14 mutants red in 44 s.
- Every route, sneak and shortcut leg runs on ground. So the walls' "can" checks are implied by the ground rule, except
  the gap leg and the lookout's flight.
- The mountain yard's walls stand on its edges (top 280).
- The faithful R8 (`--r8-fight pair`) passes on all four tables at afdce67:
  - Hard T1/T1: Road3 x0.987, Road2 x0.985;
  - Hard bow T4 (D1's run): Road3 x0.982;
  - Normal T1/T1: CaveExit x0.968;
  - Normal bow T4: Road4 x0.943;
  - the open tunnel at Hard bow T4 (out of the gate's scope): CaveMouth x0.964.
  The table timings with 6 jobs: Hard 16 min, Normal 6.5 min, Normal bow 4 min.

**Recipes (scratch `l4w2s4/`):**
- **R8 probe:** `py -3.12 -B tools/sim_range.py --r8 --check --r8-table <t> [--r8-spot <key>] --r8-fight pair --jobs 6`
  in a `git archive` copy.
  - Use `-B`, not `-I`: sim_range imports `check_levels` from `tools`.
  - One table takes about 16 min.
- **`hammer_sector.py <tree>`:** raiderpose's `model_points`, `hold_frame` and `rig` over the strike, giving the
  farthest flat reach per sector.
  - The copy needs `assets`: `cmd //c "mklink /J <tree>\assets C:\Users\benja\Desktop\tycoon\assets"`.
- **`probe.py <tree> <luau> <probes.json>`:** the harness, 27 s for the base run. `mk1.py` writes the JSON.

## W2 slice 1, server and shared (2026-10-22, afdce67): 0 Critical, 0 Major, 3 Minor, 3 Suggestions

Findings: `docs/prompts/l4-w2-review/1-server.md`. Covers LevelDress.Accept (all-or-nothing grey), LevelService (walls
armed, `Skinned` pieces, `Dress`/`DressHash` last), the seat (CrowdService, HitShapes, WeaponService.gather),
`Plan.kinds` and `prewarm`, the Castle Key (SecretFlow, Unlocks), and the Z lever.

Overlaps, count once:
- My m1 (unpinned conditions) is slice 4's m2.
- My s1 (invisible walls on a failed client) is slice 2's m2.

**Patterns:**
- **Hiding a Part by Transparency while keeping its collision changes what Roblox's DEFAULT camera does.**
  - Poppercam needs total transparency < 0.25 to treat a part as an occluder. Source:
    `%LOCALAPPDATA%\Roblox\Versions\version-*\ExtraContent\scripts\PlayerScripts\StarterPlayerScripts\PlayerModule.module\CameraModule\ZoomController\Popper.lua:197`.
  - Our shoulder camera spherecasts, so it still stops at the hidden part.
  - But CameraController hands back to `Custom` in `summary` and `ended`, and in a level the summary lasts
    `coop.returnGroupSeconds` (10 s). The default camera then passes through every skinned wall.
  - Check every camera the place can show, not only the one used in play.
- **A pure "never throws" function called bare from a step that runs after a Clear.**
  - Three of Accept's malformed-shape guards had no case: `hide.blocks`, `hide.camps`, and a camp's list.
  - `dressOf` has no pcall, so a throw would make the level unstartable instead of grey.
  - Ask for a case per guard, or a pcall at the caller that turns a throw into a refusal.
- **JSON object keys are always strings.** A guard against non-string ids in a JSON-sourced dict is unreachable: do not
  file it.

**Verified, safe to reuse:**
- Walls in `ArenaBarrier` pass every server ray: WeaponService's and AbilityService's `worldParams`, ThreatField, the
  floor probes, `aimAllowed`, and `dashEnd`. None of them sets `RaycastParams.CollisionGroup`.
- There is no `OverlapParams` or `GetPartBoundsInBox` anywhere in `src`.
- The summary card is 320 wide, so the world stays visible behind it.
- Main boots an explicit service list, so a pure module in `Services/` is never `Init`ed.

**Recipe:** scratch `l4w2-s1/probe.py <tree> <luau> <probes.json>` (`mkprobes*.py` write the JSON). Each probe takes
about 24 s on a `git archive` copy.

## W2 fix diff (2026-10-22, afdce67..46fd98f, rulings K1-K10): 0 Critical, 0 Major, 3 Minor, 4 Suggestions

Findings: `docs/prompts/l4-w2-review/5-fix-diff.md`.

**Patterns:**
- **Pins hold the call sites, but the predicates one level down are not pinned.**
  - `showChild(...)` is pinned, but `isSkinned` / `isWall` → `return false` both pass.
  - K3's whole client half (`Figures.Build()` in step, `Take` building, the split, the budget, `wants`, `wear`) passes.
  - 11 of 11 probes pass `PASS 4,656`.
  - Probe the bodies of the helpers a pinned line calls. The pure-module route (ScenePlan) is the fix that sticks.
- **A sector gate binned at N degrees passes a hole of up to N at the wedge's ends.**
  - The Chief's hammer never enters −65..−75°. A vertex at −60.6° "sweeps" the whole −75..−60 slot.
  - Bin at 5°, or test that the swept span reaches each edge.
- **An ulp guard relative to the value misses the case where one Python gets 0 and the other a tiny value.**
  - That is how the normals hash broke.
  - Float32 stores 6e-18 exactly, and 721 shipped kit corners are that small. −0.0 also packs to different bytes.
  - Snap tiny values to 0 before hashing.

**Verified, safe to reuse:**
- K1's slide is continuous at the snap start, the impact and the strike's end: about 0.36 studs per frame at most.
  - The only one-frame jumps are the placeholder's inherited ones: a cancel, a stagger, a late sighting.
  - `raiderpose --check` with `slideShare` 0 → "2.43 >= 3.44 FAIL".
- `RunFloors.Attach`'s `cellsWent` is true per new floor set even with no cells, so the lobby RunState carries `prewarm`.
- `StageFlow.kindsOf` counts tent stock and boss summons.
- Level templates hold only `MeshContent`; `MeshPart.MeshId` mirroring it is unproven offline.
  - The hub's `PlotVisualsController` reads MeshId too, but it treats "" as fetched, so it proves nothing.
- The crosshair is visible whenever `CameraController.IsActive()`, so K9's summary camera keeps it up (behind the card).

**Recipes (scratch `l4w2-fix/py/`):**
- `trace.py <tree> <kind> <shape>`: frame by frame through windup, strike and recover, showing the slide, the
  weapon's farthest point and its angle.
- `sweep.py`: an arc's jumps at the impact and at the recover, and the swept span against the tell's leading edge.
- `sector5.py <tree> <kind> 5`: per-sector reach at any bin size.
- `tiny.py`: counts the tiny and negative-zero kit corners.
- `probe.py`: harness probes, as in slice 1.
- **Junction rule:** add `assets` as a junction for raiderpose, and remove it with `cmd //c rmdir` before anything
  else touches the scratch tree.
- **Shebang note:** `py -0p` lists `-V:3.14-32` and `-V:3.12`. `forest.py` has no shebang, so `py` gives 3.14 and
  `py -3.14-32` is explicit.

## W3 slice 3, the clients (2026-10-23, 93eb8e9, `tycoon-p5` branch `l4-w3`): 0 Critical, 0 Major, 3 Minor, 5 Suggestions

Findings: `docs/prompts/l4-w3-review/3-clients.md`. The slice covers:
- HubMap, the shared MapScreen in the city;
- RunTally, the shared tally card, with its hosts TallyHost (combat) and UIController (hub);
- DepartLine and CombatHud's depart line;
- the slimmed ExpeditionPanel ("Party & runs");
- ArmoryAbilityPage's upcoming rows.

**Patterns:**
- **A modal moved from the combat place into the hub inherits the TouchGui tie.**
  - The hub's `EraCityHUD` is DisplayOrder 0, the same as TouchGui. The combat place's `ExpeditionHUD` is 1.
  - The classic jump button (70 px at w-95, h-90) covers the right 36% of the map's Depart and Party & runs, and the full
    height of the two-column report's Dismiss, at 640×360 and at 667×375.
  - Recheck every hub modal for the R9 pattern (`TouchControlsEnabled = false`).
- **A "derived" flag can rest on a converse that is false.**
  - The hub card's star is read from a firstClear line. Lines exist only when a difficulty has a firstClear reward, and
    Normal has none.
  - So the commonest new star shows on the dungeon card and not in the city.
  - Check the config for every case the derivation assumes.
- **The client half is still ungated** (W1b slice 2's pattern). Six review probes all passed `HARNESS 4,994`: the picked
  rule, the holding rule, FirstPick, the forced public flag, `lowEndDevice` → `reducedMotion`, and the hub wallet.

**Verified, safe to reuse:**
- TouchGui uses `ScreenInsets = DeviceSafeInsets`, so the jump button's offsets are measured against the full viewport
  (`ControlModule/init.lua:897-905`).
- The old hub ExpeditionSummaryCard was DIALOG_WIDTH wide and centred. Its button sat at roughly x 183-457 at 640×360.
- `Format.Cash(math.huge)` loops forever (`while value >= 1000`). `Format.Cash(NaN)` returns "nan`v" and does not throw.
- ForestRoad's `firstClear` by difficulty: normal none, hard `{family = warhammer}`, brutal `{valor = 25}`.
- MapScreen's card stack is 316 design px for an open node on touch, against a 313.5 card at 640×360. The difficulty
  buttons are 66.7 wide. "Castle gear" measures 62.7 px at 11 px Montserrat Medium.

**Recipes (scratch `l4-w3-rev3/`):**
- `tally_layout.py` ports `RunTally.relayout`. It covers both hosts at six viewports, with two line-height guesses for the
  note.
- `themescan.py` / `themescan2.py`:
  - all Theme keys against `src` + `tools`;
  - a strict pass, with comments stripped, over the keys that the deleted or changed files read.
- `measure.py <fontsDir>` measures text widths with Montserrat Bold or Medium (Pillow, `py` 3.14).
- `probe.py <tree> <luau> <probes.json>` runs the harness under each mutation, about 26 s per probe.

See [[l3-armory-review]], [[l1b-living-road-review]] and [[review-workflow]].
