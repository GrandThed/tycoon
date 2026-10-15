# L1b Wave 3, the bow: review (2026-10-15)

Diff `main...l1b-wave3` (3844527..1f1a589). One reviewer, read-only.

**Verdict: SHIP. 0 Critical, 0 Major, 5 Minor.**

## Verified

- **The heavy comparison is `>=` everywhere, so B at 40 counts as heavy.**
  - `CrowdService.luau:1926` blocks on the plate only when `amount < crowd.heavyHit`.
  - `CrowdBrain.luau:1006` interrupts when `amount >= heavyHit`.
  - The sim mirrors both: `sim_range.py:1962` and `:2027` for those two, `:2184` and `:3518/3526/3711`
    for the rest.
  - A full draw reaches exactly 40.0:
    - `WeaponService.resolveCharge` (`:1164-1165`) gives `0.5 + 0.5 * 1 = 1.0`, exact in IEEE, so
      `projectile.damage = 40 * 1.0` (`:1209`).
    - The tier scale stays out of `amount` (P5 ruling 9).
  - No client-side code compares a damage with `heavyHit`.
- **The in-play step moves no `--check` band.**
  - `LevelRun.wanted` returns early for melee.
  - `self.melee` is set once, from the policy's weapon (`:2157-2158`).
  - Every band-bearing LevelRun policy uses the default melee loadout.
  - The only ranged level runs are:
    - `forest_report`'s `row["ranged"]`, printed and read by no `expect`;
    - `--bow`.
  - Full `py tools/sim_range.py --check` on the branch (`py` = 3.14, 32-bit): `CHECK: PASS`, 0 FAIL.
    - arrowRain burst 4.6 s in [3.0, 5.0].
    - Thinning: Longbow 4.8/s.
- **The step uses the game's rounded rectangle.** `hs_flat_to_rect` is `HitShapes.FlatToRect`, and
  the zone rect is the same floor rect that CampBrain's group defs carry (`:5171`, `:5493`).
  - It does not oscillate: `ThreatRun` only closes when `gap > want` (`:2449`), it never retreats.
  - It converges: `want` is recomputed each swing, and bodies are clamped to their floor.
- **Nothing else reads the Longbow's shot damage in a way that breaks.**
  - Arrow Rain has its own `damage` 8.
  - `Armory.json`'s "Longbow" tier row (damage 22) is the old armory ladder, unrelated.
  - The harness `FIXTURES` are generated from the config at run time: `bundle.luau` and `mutant/`
    are gitignored.
  - The only test that reads `longbow.variants.A` (`tests_l1b_w2_crowd.luau:32`) uses
    width/pad/range, not damage.
- **The diff stays inside the contract.**
  - `src/` changes only the two Longbow `damage` values.
  - Layouts, Missions and Levels are untouched.
  - No TODO.
  - The new sim constants are tool-side, which the sim has always had.
- **BALANCE arithmetic checks.**
  - Every per-camp split sums to its "to the boss" time within 0.1.
  - Every mean and ratio is right: x1.034, x1.037, x1.084, x1.128, x1.093, x1.141, x1.137, x1.245.
  - DPS ×0.9 / ×0.909 are right, and the boss "11–16% longer" holds.
  - "C" is the locked boss room (ForestRoad.json), so "start to the Colossus's rise" is the right
    reading of ruling 2.
- **Cross-Python check.** On `py` (3.14, 32-bit) the head-aim ratio reads x1.092, not x1.084: sword
  seed 23 is 354.8 not 357.7, head-aim seed 23 is 373.6 not 368.8. Body aim reads x1.131. Both are in
  band. Known drift (PLAN:2266).

## Minor

1. **`tools/sim_range.py:6637-6649`, `:333`: the step goes further than the game's rule, and the
   docstring misstates the rule.**
   - **The rule:** CampBrain puts a player in play within `camps.chaseMargin` (2.5) OUTSIDE the floor
     rect, or within a living keepAway member's reach. The sim player walks to 1 stud INSIDE.
   - **The docstring:** it says a hit "from outside its fence" is blocked. With `fenceThickness` 1,
     a bow standing 1–2.5 studs outside the floor is in play and its hits land.
   - **Effect:** the simulated bow stands up to 3.5 studs closer than a real player needs to, so it
     is slightly less safe. The ratio bias is small.
   - **Fix:**
     - Stop at `cb_rect_distance(...) <= chaseMargin - spare`, reading `self.camp_rules`, the way
       `near()` and `EDGE_SPARE` already do.
     - Or keep 1 inside as a stated course choice, and correct the docstring and the comment on
       `IN_PLAY_STEP`.
   - **Also:** no gate pins the fix. The only ranged level row is camp A, and it is information. A
     regression to "stands off camp B forever" passes `--check`. Cheap pin: the `ranged` info row
     runs through camp B (`stop_zone` = the second open zone), plus one `expect` that it clears on
     every seed.

2. **`ProvingGrounds.json:142`, `WeaponService.luau:1164-1165`: "every arrow stays heavy" is true
   only for a FULL draw.**
   - **Mechanism:** damage scales `minChargeFraction + (1 - min) * charge`.
   - **B:** at exactly 40, any B release short of full charge is now light. That covers a mouse
     release at 0.39 s of the 0.4 s draw, and touch auto-fire releasing early when the target leaves
     the cone. Before the cut, B was heavy from charge 0.82.
   - **A:** the default now needs charge ≥ 0.78 (was 0.6).
   - **Why the sim misses it:** the sim fires only full or minimum charge (`:1050-1051`), so it
     cannot see this.
   - **Failure scenario:** a player who releases on feel, just before the glow (`FULL_CHARGE`
     0.999), sees B arrows bounce off plates and fail to interrupt.
   - **Fix:** none needed in code if the lead accepts it. State it in BALANCE's flags and in the
     PLAYTEST note: "B is heavy only at full draw; A from 78% draw". If B should keep a margin, B
     needs a factor above 0.909, which ruling 1's same-factor rule forbids. That is a lead call.

3. **`tools/sim_range.py:147-149`, `:8447`: `BURST_SECONDS_BY_ABILITY = {}` is an empty override
   table with a lookup.**
   - **Problem:** at 45/40 nothing uses it, which is dead structure under the "no dead code" rule.
   - **Fix:** drop it and the `.get(...)`, and re-add it in the wave whose ruling needs it. Or keep
     it as a deliberate ruling-5 hook and say so in INTERFACES.

4. **`tools/sim_range.py:7638-7750`: small hygiene items in the new `--bow` mode.**
   - `print_bow(cfg, rep)` never reads `cfg`.
   - `bow_report` returns `"arena": arena`, which nothing reads. It also runs the whole
     `mission_report` (stand, bosses, three mission runs) only to obtain the arena's view, plan and
     level, which accounts for much of the 2.5 minutes.
   - `no_boss(s)` returns the time to the boss's rise, so the name says the opposite.
   - `aimed()` adds `_slay_body` / `_slay_head` to the global `THREAT_POLICIES` and never removes
     them. `bow_rows` pops its `_bow` in a `finally`.
   - **Fix:** drop the parameter and the key, rename to `to_rise`, and pop the aimed keys after use.
     Optionally, build the arena view with `level_view`/`plan_level` directly instead of
     `mission_report`.

5. **`docs/BALANCE.md:4605`, `:4527`: two small doc errors.**
   - "the bosses took the bow 22–67% longer" for the rejected ×0.78 cut: the Raider Arena Warlord's
     head row is 105.0 → 125.8 s = +19.8%, so the range is 20–67%.
   - The contract line cites "rulings L1b-W3-1…6", but amendment rulings 7–9 govern (band x1.05–1.15,
     ×0.9). Cite "1–9 (7–9 win over 1–2)".
   - **Also worth a line:** the sweep is not monotonic (43 → x1.062, 45 → x1.084, 40–42 → x1.066) and
     the ratio drifts about 0.01 between Python 3.12 and 3.14. The PASS sits inside seed noise. That
     is fine for a reported band, but it should not be quoted as a measured 8.4%.
