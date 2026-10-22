# L4 W1b review, slice 1: server and shared

Reviewer: roblox-reviewer (slice 1). Commit reviewed: `l4-w1b` at 1ae8bfb (HEAD d5635a2 adds only the brief).
Diff: `git diff l4-real-forest...l4-w1b` restricted to `src/combat/server/Services/`, `src/combat/server/Main.server`,
`src/shared/{Combat,Armory,Catalog,Types,RunFloors}.luau` and `tools/crowd_harness/tests_l4b.luau`.

**Result: 0 Critical, 0 Major, 4 Minor, 2 Suggestions.** The code does what L4B-7 and L4B-8 say. The findings are
about a gate that cannot see the core of L4B-7, a frame-order dependency the ruling introduced, and the size of the
feel cost, which is larger than the contract states and which test (a) hides.

Evidence was gathered on a `git archive HEAD` copy in the reviewer's scratch folder (never the worktree):
- review-only mutants run through that copy's own `run_harness.py` (baseline `HARNESS: PASS (4,075 checks)`);
- a timing study that runs the real `PositionRing.luau` and `DashProof.luau` under `tools/bin/luau.exe` with a
  Vector3 stub. Model, in server time:
  - the client's root replicates at 60 Hz, 20 Hz, or 20 Hz bunched (every other update waits for the next one);
  - the remote and the motion both arrive `u` after the client acts;
  - the server Heartbeat runs at 60 Hz and records then judges the claim, as `trackAir` does;
  - VitalsService's `settle` decides at `T + lag`, with `lag = min(2u + 0.05, 0.3)`;
  - the study sweeps 40 phase combinations and a press time grid at 2 ms.

## Findings

### Minor 1: no gate sees the line that makes L4B-7 hold

`src/combat/server/Services/WeaponService.luau:1995` (`if verdict == "proven" then`), `:1998-1999` (the lapse
clear) and `:2028` (`if claimAt ~= nil then`).

The `source.l4b` pins count the calls `DashProof.Verdict(...)`, `openIframes(shooter, now, claimAt, ...)` and
`proveDash(...)`. They do not pin the condition that decides whether the call opens a window. The same holds for the
`mutate.py` "l4b:" WEAPON entries. Each probe below was applied alone to the archive copy:

| Probe | What it does in the game | Harness |
|---|---|---|
| `if verdict == "proven"` → `if verdict ~= "lapsed"` | The window opens from the request on the first Heartbeat after it, whatever the ring saw. This is the old 39% uptime for a client that never moves, so L4B-7 is undone. | **PASS 4,075** |
| `if claimAt ~= nil` → `if claimAt == nil` | `proveDash(..., nil)` reaches `now - claimAt` in `DashProof.Verdict` and throws on every frame. `WeaponService.step` then dies before `tickIframes` and `stepProjectiles`: arrows freeze and the RangeIframes attribute never clears. | **PASS 4,075** |
| The lapse branch's `shooter.dashClaimAt = nil` dropped | A claim never ends. Each frame then pays a `Rule` allocation and a full-window ring scan per player, and any later fast motion proves a stale claim. | **PASS 4,075** |
| `DashProof.Rule(config.movement, config.shooting)` given a 1e6 lookback | Any motion in the 2 s ring proves a forged claim. | **PASS 4,075** |
| The no-root branch's `shooter.dashClaimAt = nil` dropped | Minor on its own: the claim is not cleared at death. | **PASS 4,075** |
| Contrast: `OnDash`'s `shooter.dashClaimAt = now` changed | | caught |

**Failure scenario.** A later edit "simplifies" `proveDash`, for example to "open unless lapsed" so dodges feel like
before. Every gate stays green and the forged-dash uptime returns.

**Fix.** Move the per-frame decision into the pure module so the harness runs it. For example,
`DashProof.Step(claimAt, history, now, position, rule): (openFrom: number?, keep: boolean)`, with cases (a)-(g)
driven through it. `proveDash` is then one pinned call. As a minimum:
- pin the three lines whole, with their indentation, in their bodies (`PROVE_DASH_BODY`, `TRACK_AIR_BODY`);
- add the first three probes as `mutate.py` entries.

### Minor 2: whether a proof counts in the decision frame depends on Heartbeat handler order

The order is set at `src/combat/server/Services/WeaponService.luau:3150-3154`:
- `VitalsService.Start` connects VitalsService's Heartbeat first (`VitalsService.luau:729`);
- WeaponService then connects its own `step`.

`settle` (`VitalsService.luau:431-455`) decides an entry in the first frame with `now >= decideAt`. If VitalsService
runs before WeaponService in that frame, a proof that `trackAir` would make in the same frame comes too late, and the
hit lands. Roblox does not specify the order of handlers on one signal. The place leaves `Workspace.SignalBehavior`
at Default.

Before this wave the order did not matter, because the window opened in the remote handler. With 20 Hz bunched
replication a proof can only land on an arrival frame, so losing that frame can cost a whole update cycle, not
1/60 s.

**Study.** The table gives the latest press, relative to the impact, that still dodges, across 40 phases:

| One-way `u` | 20 Hz bunched, WeaponService first | 20 Hz bunched, VitalsService first |
|---|---|---|
| 0.05 s | −0.026 .. +0.084, mean +0.012 | −0.026 .. +0.020, mean −0.003 |
| 0.10 s | +0.074 .. +0.120, mean +0.097 | +0.010 .. +0.110, mean +0.079 |
| 0 (Studio-like ping) | −0.026 .. +0.020 | −0.090 .. +0.020 |

The same order question applies to ThreatField's travelling verdicts, which are judged from CrowdService's step.

Test (g) always runs the proof before `vitalsBeat`, which is the favourable order, so it cannot see this.

**Fix.** Make the order explicit, using one of these:
- one Heartbeat drives both: WeaponService's `step` calls a `VitalsService.Step` after `trackAir`, and VitalsService
  stops connecting its own;
- `settle` calls a hook that judges pending claims before it decides;
- the contract's own follow-up (§4.5): a decision that only a pending claim could cover waits until the claim
  resolves, at most `lapse` (0.45 s).

### Minor 3: the feel cost is larger than §4.5 says, and test (a) passes only at favourable phases

`tools/crowd_harness/tests_l4b.luau:115-127`; `docs/prompts/l4-w1b-contract.md` §4.5.

**Test (a).** It asserts "proven within 0.05 s of the first moving sample" for 20 Hz bunched, at leads 0 and 0.02
only. A sweep of the lead from 0 to 0.1 s, using the test's own `samples()` and `judge()` with the real modules,
gives these worst cases:

| Replication | Worst lead | Proof after the first moving sample |
|---|---|---|
| 60 Hz | 0.009 | 0.033 s |
| 20 Hz | 0.026 | 0.050 s, right at the bound |
| **20 Hz bunched** | **0.051** | **0.100 s** |

At 20 Hz bunched the bound fails: the first arrival shows only 1.3 studs, and the next one is 0.1 s later. The
check is green by phase luck.

**§4.5.** It says that "a dash pressed on screen at T or earlier still dodges". In the contract's own model, the
server's copy at the decision (T + lag) shows the client at T, so a press at T has shown no motion and is never
proven.

**Study.** The late edge (the latest press that still dodges) moves earlier under the new rule. At `u` 0.05 (ping 0.1) with
WeaponService first, the old edge is +0.100 and the new one moves earlier by:
- about 28 ms on average at 60 Hz (mean +0.072);
- about 45 ms at 20 Hz (mean +0.055);
- about 88 ms at 20 Hz bunched (mean +0.012), and 126 ms in its worst phase (−0.026).

The early edge is unchanged. Studio Play Solo (`u` ≈ 0, per-frame replication) shows the smallest shift. So Ben's
"does dodging feel the same" look in Studio will understate what a live player on 20 Hz replication feels.

**Fix:**
- Correct §4.5 and the PLAYTEST question to name the real cost: a dash must start about one replication update
  before the old latest moment.
- Make (a) sweep its lead over a whole update cycle and assert the true bound: 0.1 s bunched, or "within one
  update period of the first moving sample".
- If 0.05 s is the requirement, it needs the hold of Minor 2's last option, not a looser proof.

### Minor 4: the proof is not proof against a client that moves its own root; say what L4B-7 buys

`src/combat/server/Services/DashProof.luau:80-99`, against the brief's "a still or walking client never is".

`Verdict` asks whether the fastest flat 0.05 s stretch since `claimAt - lookback` reached 66.7 studs/s. Probes
with the real modules show three ways to meet that without a dash:
- **A flick.** A client that writes its root 3.4 studs out for one replicated update and then back (net
  displacement 0) is proven in 40 of 40 phases, at both 20 Hz and 60 Hz updates. The return trip alone also
  counts.
- **Other fast motion.** Any flat motion over 66.7 studs/s in the 0.3 s lookback proves a forged claim. That
  includes an Impale Dash or Leap Smash flight just before the request.
- **A stall.** A walking body whose replication stalls for about 0.17 s and then catches up in one update proves
  one too, if the server applies updates without smoothing.

An honest client never sends a dash without dashing. So the ruling stops a request-only forger and a dash into a
wall. It does not stop a modified client, which by the "no movement anti-cheat" ruling can already step out of every
shape.

**Failure scenario.** Someone later reads L4B-7 as anti-cheat and builds on it, or Ben is told it closes forged
dodges.

**Fix.** State the scope in the contract and PLAN. If more is wanted, require the displacement to persist: for
example, the root is still at least `share × dashDistance` flat from the pre-claim anchor `dashProofSeconds` after
the proving stretch. That turns a flick into a real relocation, which costs the forger their position.

## Suggestions

- **S1. Two abilities still grant i-frames on the request alone.** `src/combat/server/Services/AbilityService.luau:444,
  461`: Leap Smash and Impale Dash grant `delaySeconds` of i-frames when the cast is accepted, with no motion check.
  This is sanctioned by contract §4.4 ("server-granted, unchanged"). After L4B-7 they are the only request-only
  windows left, so tell Ben. If the reasoning of L4B-7 applies, the same claim and proof could gate them later.
- **S2. Pin the behaviour the docstrings promise.** `src/combat/server/Services/DashProof.luau:95` "a proof wins over
  a lapse judged in the same frame" and `src/shared/RunFloors.luau:41` "every floor in it is new" both survive a
  mutant: the lapse checked first, and `table.clone(floor)` replaced by `floor`. Neither can be seen today, because
  nothing mutates Attach's floors and the overlap frame is narrow. Either pin them with a case each, or drop the
  promise from the comment.

## Checked and clean

- The §8 `git grep` is empty in `src` and `tools` for every pattern. `RemoveBot`, `RespawnBot`, `BotCount`,
  `ARENA_ZONE` and `ARENA_CAMP_ID` are also gone. A case-insensitive "raiderarena" finds only a comment.
- No server code sends a removed CombatFx kind (`hit`, `telegraph`, `kill`, `playerHit`, `ability`, `playerDown`,
  `swing`, `partyEffect`, `refused`).
- No `src` reader remains for a removed Types field or config key. Grepped: the Armory slot ladder, every
  `CombatPlayerConfig`, `debug` and bot key, `director.maxAlive` (every other `maxAlive` is the crowd's),
  `LevelFile.recommendedTier`, `.mission`, `layout.arena`.
- Toolchain on the worktree:
  - luau-lsp on both sourcemaps (generated into scratch): 0 diagnostics;
  - stylua and selene on `src/combat/server` and `src/shared`: clean;
  - `check_compile.py` on the copy: PASS, 176 files, with WeaponService at 100 top-level locals;
  - `rojo build` of `combat.project.json` and `default.project.json` into scratch: OK.
- `OnDash` keeps its refusals (active, shooter, root, down, mayAct, cooldown x tolerance) and stamps `lastDashAt`. It
  holds no `openIframes(`. The claim is cleared in three places:
  - by `resetAir` (PrepareCharacter);
  - on a frame with no living root (`rootOf` requires Health > 0, so this covers death);
  - with the shooter itself on `RemovePlayer`.

  "A newer dash replaces an unproven claim" is unreachable with the shipped numbers (lapse 0.45 < cooldown 0.64).
- Nothing in `step`, `trackAir` or `proveDash` yields. `Tuning.Get` is cached, `Rule` is pure, and the warn fires
  once.
- `GrantIframes` through `DashProof.Open(from = now)` is branch for branch the old `openIframes`, because every
  window's `From` is at or before now. The window opens from `claimAt` (the request), and the attribute shows only
  while the window is still open.
- Server moves call `ForgetMotion`, which clears the ring: `ArenaService.MoveMember` through the moved hook,
  `WaveService` GateNudge at `:1223`, and the rescue. A pending claim survives a move and is proven only by motion
  after it. Falls cannot prove a claim (`flat`, case (d)).
- `PositionRing.Motion` gains `flat`. Its one other caller, the claim slack at `WeaponService.luau:527`, passes five
  arguments and is unchanged.
- VitalsService `RunLost` and `AllHaveBodies` behave as before now that there are no bots. `AllHaveBodies` never
  skipped waiting members before either. Probe V1 (a waiting member counted) is caught.
- `StageFlow.Resolve(file, cap)` is the old no-mission branch less `mission = nil`. Its callers are `WaveService:1587`,
  `stage_mirror.luau:186` and the tests. LevelGeometry, LevelService and Catalog: the arena refusal, `FromArena` and
  `GetArenaLayout` are gone. `Layouts/Arenas/ProvingGrounds` is still read directly by `ArenaService:250` and
  `CrowdRenderer:2724`.
- `Armory.CanAscend` is equivalent to the old `cfg.slots[slot] == nil or current == nil`, because `slots` held
  exactly melee and ranged. The hub forge is unaffected. `Combat.MissionUnlocked` and `RecommendedPower` read only
  stub keys plus `overdrive` (L4B-1, L4B-2).
- `CombatRemotes`: the five intents and two buckets are gone and nothing referenced them. The `rangeAttack` and
  `rangeAbility` buckets are unchanged. `BarrierGroups`: no code sets a C1 collision group by name.
- `RunFloors` is pure and returns fresh lists. Merge by index is safe, because a seq's floors are built once and in
  order:
  - probe F1, every floor read from `held[1]`, is caught (8 checks);
  - the 8 `mutate.py` RunFloors entries cover Attach and Merge.
- DashProof probes D2 (Open's earlier slot) and D3 (merge never lengthens) are caught. So is R1, a `flat` that keeps
  half the fall, by case (d).
- `tests_l4b` cases (b)-(h) match contract §4. In (h) the shipped rule is 66.7 studs/s, inside [40, 106.7]; its span
  is 0.05 and its lapse 0.45.
