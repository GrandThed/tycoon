---
name: l2-secrets-review
description: L2 W1 review (bought Double Jump, lookout chest, v7) - server slice 2026-10-17 0C/0M/4m (v7 forward-compat recipe, trigger-from-centre vs a big solid, unharnessed verdict-acting lines); client slice 0C/0M/7m (HUD-row overlap across ScreenGuis, proving hides Return, lost walk-off forgiveness, unmirrored client copy); fix diff 0C/1M/3m (AbsolutePosition origin trap undoes c1; shared call with copied args)
metadata:
  type: project
---

L2 W1 lives on branch `l2-secrets` in worktree `tycoon-p5`. It covers:
- the bought double jump, keyed on the Player attribute `Ability_doubleJump`;
- the Abilities panel (K, or a HUD button);
- SecretFx chests;
- the map secrets row;
- the leap fixes F1 and F2 (`WallClip.CasterFloor` and `LeapApex`).

Brief: `docs/prompts/l2-w1-review.md`. Findings go to `docs/prompts/l2-w1-review/<slice>.md`.

**Several slice reviewers share this file. Re-read it and Edit only your own section. Never Write it
whole.** On 2026-10-17 the client reviewer overwrote the server section with Write. The section below was
rebuilt from `server.md` and the index line.

**Why:** later L2 waves add Glide, the Jetpack, more HUD buttons and more chests. These patterns recur.

**How to apply:** for any new HUD button, element or movement rule, run the probes below before trusting the
engineer's "layouts checked mentally".

## Server slice (rebuilt; 2026-10-17, e39215b): 0 Critical, 0 Major, 4 Minor

**v7 forward-compat recipe (reusable for any schema bump):**
- ProfileStore 1.0.3 `ReconcileTable` only fills nil keys with deep copies and never deletes.
- `DataService.runMigrations` has an ahead guard (`version > SCHEMA_VERSION` warns and leaves the profile
  untouched), present since d166a9a (`git log -S`).
- So a hub publish adds empty maps, and a frozen older place loads them, warns, plays and saves them back. No
  loss either way.

**Minors (patterns):**
- **Trigger measured from a chest's centre against a big collidable chest.** The cache is 12×12×10 with reach 5
  and above 9, so no root ever triggers it. The gate (L2-18a) ran only for sold keys.
- **A duplicated constant** (`MAX_FAMILY_LENGTH` 24 in both StageFlow and CombatRemotes).
- **The service lines that act on a tested verdict are unharnessed** (`UnlockService.OnBuyAbility` debit/own,
  `OpenSecret`'s write). Proposed fix: a pure `Unlocks.Apply`.
- **Two rules for a repeated config id:** Init skips a malformed entry, while `Find` returns the first entry.

## Client slice (2026-10-17, 6feb088): 0 Critical, 0 Major, 7 Minor

**Patterns:**
- **Widening a HUD row: check it against every bottom element in EVERY ScreenGui, not only its own.**
  - The mission HUD (ExpeditionHUD) sits under the inset with DisplayOrder 1.
  - The health bar sits bottom centre in the inset-free `rangeGui`, shown in the lobby.
  - MovementController's Dash button lives in `RangeMovement`, DisplayOrder 0, always shown on touch.
  - At 667x375 the 280-px row's Return covered the HP bar's left 22 px. In portrait it covered the Dash
    button's left 48 px, so a dash tap fires `RequestLeave` with no confirm.
  - Probe numbers:
    - scale = clamp(min(w/375, (h − inset)/667), MIN_SCALE 0.9167, 1.8);
    - row bottom = h − 12·scale;
    - jump button (small, ≤ 500 axis) 70 px at (w − 95, h − 90);
    - Dash 56 px, its centre 8.4 + 28 left of the jump button;
    - the vitals bar is 200·scale wide, its bottom h − 10·scale.
- **`proving.rbxl` hides Return** (`runButtons = not proving`), so Ben's emulator look cannot show any overlap
  that involves Return. Say so whenever a layout claim depends on it.
- **Removing a forgiving mechanic removes its side effect.** The always-on air jump was the accidental coyote
  time.
  - `airJumpDelay` 0.12 already dropped presses under 0.12 s.
  - Without the air jump, a late press at Forest Road's first gap (Road1 → Road2, void below) is lost, and the
    once-per-session "buy Double Jump" hint fires there, on the main path.
- **A client copy of a pure server rule is ungated** even when every helper inside it is tested
  (groundPoint against GroundPoint step 4). Ask for one pure function both sides call.
- **Enemy launches are a vertical "means".** `MovementController.ApplyKnock` sets
  `vel.Y = max(vel.Y, jumpSpeed(3))`, so two launches at an apex reach 27, over the ledge's 26. check_levels
  models jumps, dash and abilities only.

**Verified, safe to reuse:**
- `onJumpRequest` is the only air-jump path. No other client file writes Jump, JumpHeight or the Jumping state.
- `Workspace.Level` is one folder that lives all session. `Secret_*` Parts are its direct children.
- RunFx batches arrive on `CombatFx`. `CombatFxController.applyFx` ignores unknown kinds.

## Data-tools slice (2026-10-17, 6feb088): 0 Critical, 0 Major, 4 Minor

Findings: `docs/prompts/l2-w1-review/data-tools.md`.

**Patterns:**
- **Players collide with players in the dungeon place.** `BarrierGroups` copies Default/Default, which is
  true. So any "needs X" ledge is reachable by standing on a partner's head: feet + 5 to 6, then one jump.
  The lookout falls to it by check_levels' own rule (34 − 13 − 3 = 18). Rewards stay safe (the key is read
  from the profile), but "out of reach by every means" and the "owners only" sniper labels are false in a
  party.
- **Enemy launches cannot lift a body to a ledge.** This corrects the client section above.
  - Every launching shape (arc 6, lob 4, lane 5) is a ground shape with a height band, so a body at a jump's
    apex is never hit by one.
  - `knockIframes` 0.4 outlasts the 0.175 s peak of a 3-stud launch, so launches cannot stack.
  - The best case is 21 + 3 step = 24.
- **A gate that counts inside a guarded function can be vacuous.** The sim's `airAsked` is incremented only
  where the planner's `can_jump` already forbids it. The mutation `can_jump = True` still gives 0 and the
  same 4.23 min.
- **Solo lookout margin:** camp A's NW fence corner (top 12, 6–7 studs from the ledge) is 1 stud short with
  `STEP_UP` 3.

**Recipes:**
- `sim_range.py` must run WITHOUT `-I`, because it imports `sim_combat` from its own folder:
  `py -3.12 tools/sim_range.py --check --levels-only --level forest` takes about 3 minutes.
- `check_stage_mirror.py` in a snapshot needs `--luau <main>\tools\bin\luau.exe`.
- To prove a refusal-alike set is not vacuous, early-return the rule on BOTH sides (StageFlow plus the py
  mirror). Every case must flip to "accepted on both sides".
- To count jumps in level runs, monkeypatch `S.ThreatRun.take_off` from a probe script, then run
  `S.LevelRun(view, hp, ctx, level, layout, "normal", S.THREAT_POLICIES["human"], seed).run()`.
  Each run takes about 3 s.
- The session scratchpad is shared with the parallel slice reviewers: put snapshots in a subfolder with a
  unique name.

## Fix-diff review (2026-10-17, a21f153..d6b3777): 0 Critical, 1 Major, 3 Minor

Findings: `docs/prompts/l2-w1-review/fix-diff.md`.

**Patterns:**
- **The `screenGui.AbsolutePosition` origin trap.**
  - `GuiObject.AbsolutePosition` is measured from below the top bar, so a default ScreenGui reads (0, 0). An
    IgnoreGuiInset one reads (0, −inset).
  - The c1 rows converted viewport-px obstacles (the vitals bar, the touch cluster) by subtracting
    AbsolutePosition. Two lines later the same function used `viewport − inset` for the crosshair.
  - With an origin of 0, the landscape HP-bar overlap comes back unchanged. The agent's table only
    matches an origin of 58.
  - For any viewport↔HUD conversion, demand ONE convention (`GetGuiInset()`).
- **Port the layout to prove it.** A Python port of a pure row packer plus the real cluster formulas
  (MovementController JumpButtonRect/SatelliteRect/ClusterRect, VitalsHud.BarPlace) reproduced the
  engineer's table to the tenth. Flipping one assumption then showed the failure. Probe: scratch
  `fixdiff_probe/rows.py`.
- **"One shared function" still leaves the call-site arguments as copies.** A source check that counts
  `GroundFloor(` calls passed with the client arg changed to `GetAttribute(...) ~= false` and the server's
  movement table swapped. Mutate the ARGUMENTS of a shared call, not only the call's name.
- **A walk-off detector keyed on take-off speed is passed by enemy launches.** A 3-stud launch is
  34.3 studs/s, under half of an 18-stud jump's 84.
- **A fixed-height `TextWrapped` label hides a second line from any height model.** The lookout card's
  family note (57 characters) always wraps.

**Verified, safe to reuse:**
- WeaponService.worldParams excludes every Player character, so overlapping bodies never read each other
  as a floor.
- The hop policy is in no level row that the L2-20 airAsked gate sums.
- c3's grace apex is bounded by a surface the Humanoid stood on: it needs FloorMaterial ≠ Air, then Air.

See [[l1c-chief-clearing-review]] and [[l1b-living-road-review]].
