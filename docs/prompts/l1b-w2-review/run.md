# L1b Wave 2 review — slice "run"

Diff `main..f40509a` (branch `l1b-wave2`). Files: `StageFlow.luau`, `WaveService.luau`,
`LevelGeometry.luau`, `src/shared/Combat.luau`, `tests_l1b_w2.luau`, `tests_l1b.luau`,
`tests_l1.luau`, `run_harness.py`, `mutate.py`. Read in full: the Wave 2 contract (rulings 1–29,
"Flow", "B —" sections, the lead's answers), `lead-routing.md`, `build-B.md`.

## What was run (read-only, on a `git archive f40509a` copy in the scratchpad)

- `run_harness.py`: `HARNESS: PASS (1,896 checks)`.
- Every one of `mutate.py`'s 572 texts occurs exactly once in its file (the module was executed up to
  `def harness(` and each `old` counted).
- `mutate.py ... "l1b w2:"` (B's 24): `MUTATIONS: 24 run, 0 not caught`.

## Checked and held

- **Tents (L1b-W2-6/7/8).** `tentsOf` filters by `minDifficulty`, never by `countMult`, expands in file
  order, and skips locking camps. Plan and Validate share it. `placeTents` runs after
  `placeResidents`, so the group indices are `#groups + t`; a mismatch only warns. `tickTents`
  computes `residentsAlive = AliveOn − GroupAlive(tent)`, sends at most one body per tick, and
  counts a refusal as sent. `SpawnResident` raises `aliveOn` synchronously, so the `advance` in the
  same tick never sees the last body sent as an empty floor with the stock spent. The pause keeps
  `nextAt`.
- **No self-sustaining tent.** A tent group roused with nobody in play goes rise (0 s), fight, then
  home after `leashSeconds` 3. That is under `every` 6, so a lone tent does not keep itself busy.
- **The clear and the bonus (L1b-W2-8, -21).** `progress` holds `campClear` while
  `tentLeft[i] ~= 0`. `state.done` stops it paying twice. `campClear` prices `zone.stock`
  (residents plus the tent's stock). `open` prices `zone.stock` plus `run.waveStock`, which `close`
  empties and `queueWave` fills through `Combat.WaveStock` (the elite only when it was taken, never
  the boss or its calls). A skipped `open` returns before paying. `ClearBonus` prices each kill
  as `KillReward` does and rounds once.
- **The population rule (L1b-W2-5)** is sound for Forest Road:
  - The bursts stop at `stage.maxAlive` on the boss room's own floor.
  - The only bodies outside it are the boss and its summons. The Colossus tops up to 12, and no
    other kind on the level summons, so `BossReserve` 13 bounds it.
  - Residents and tent stocks do not scale with the party.
  - `populationReserve` is gone from `src` and `tools`.
- **DeadFraction (L1b-W2-26).** WaveService subtracts `GroupedOn(live.floor)` from the live floor's
  `alive`, matching the contract. The pure function's clamps are pinned.
- **The tent marker (L1b-W2-9).** One `collide = false` piece per block. LevelService already turns
  non-colliding pieces `CanQuery = false`.
- **No yield** in `tickTents` or the new `advance` lines. `Busy()` is called once per tick, as the
  contract says.

## Minor

1. `src/combat/server/Services/WaveService.luau:811` (with `threats()` at :989) — **tent bodies
   that join a group already in rise or fight are never threats for SafePoint.**
   - `run.awakeGroups[group]` is the id list at the group's last state change. A tent body sent
     while its group fights changes no state, because `Rouse` is a no-op off `rest`.
   - So the bodies a tent sends after its first never enter `threats()`. A's stock is expanded in
     file order (fodder ×4, slinger ×2, brute ×2), so both tent slingers miss it.
   - The fix round made that list exist for exactly one case: a shooter on one floor reaching
     another floor's checkpoint.
   - Harmless on today's Forest Road. A checkpoint's nearest other floor is 80 studs away, and the
     longest tent reach is 32. A tent body's own floor is `busy`, which already rules out its own
     checkpoint.
   - It becomes real on any layout where a checkpoint is within slinger reach of a neighbour camp
     that has a tent.
   - Fix: in `tickTents`, after a successful `SpawnResident`, append `id` to
     `run.awakeGroups[tent.group]` when that entry exists. Alternatively, have `threats()` read the
     group's living members from CrowdService rather than the snapshot.
2. `src/combat/server/Services/StageFlow.luau:856` — **a tent's ring is checked against its floor
   only at the highest difficulty.**
   - `CampBrain.Posts(def, n)` spaces n posts evenly round the circle. A tent whose units carry a
     `minDifficulty` therefore stands its Normal bodies at other angles than its Brutal ones.
   - Validate tests only the top difficulty's n points. Example:
     - A radius-10 tent has two Brutal-only units, so Brutal stands 6 bodies on it. Their posts are
       at 0°, 60°, … 300°, so their furthest east or west is 8.66 from the centre.
     - Put that ring against an east or west edge: it passes Validate.
     - Normal stands 4 bodies, with posts at 90° and 270°, 10 from the centre. They sit 1.34 studs
       past what Validate certified. That is over the floor less the widest radius, where the crowd
       clamps a body, and more than `homeTolerance` 1.
   - Those bodies then never count as `AtPost`, so the group stays in `home`, evading and `Awake`,
     for the rest of the run.
   - Not reachable today: Forest Road's tent units carry no `minDifficulty`. Wave 1's fire rings
     share the gap.
   - Fix: run the ring check inside the per-difficulty loop that already calls `tentsOf` at each
     rank (and do the same for resident fires), or check the whole circle:
     `onFloor(camp, cx, cz, radius + widest)`. A top n that is a multiple of 4 already samples the
     circle's extremes, which is why Forest Road's 8 are exact.

## For other slices (one line each)

- crowd: a body a tent sends while its group is in `home` gets no rouse (it is dropped off
  `rest`, and `camp.rouse` is cleared every step). It stands at its post until sight wakes it,
  even while the rest of its camp fights. This is reachable when the only player in play is in
  range only of another group's keepAway reach. Check whether that is acceptable.

Critical 0, Major 0, Minor 2
