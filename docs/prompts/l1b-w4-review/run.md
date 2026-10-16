# L1b Wave 4 review: slice 2, the run

Reviewed: `git diff main l1b-wave4` at 2ec9da9, covering `StageFlow.luau`, `WaveService.luau`,
`tests_l1b_w4.luau`, `tests_l1b_w2.luau`, `tests_l1.luau`, `run_harness.py` and `mutate.py`
(B's tables, the ui-engineer's tables, and the replaced and retired entries). The contract is the
INTERFACES section "L1b Wave 4" through "Lead's rulings on the build reports".

Checked, with nothing found:
- **The harness passes on a scratch snapshot:** `HARNESS: PASS (2,252 checks)`.
- **B's mutations are all caught:** `mutate.py "l1b w4:"` gives 21 run, 0 not caught.
- **`mutate.py` has no stale entry:** all 691 entries have texts that occur exactly once.
- **Gates 17 and 18 find nothing.**
- **The compile gate passes.** StageFlow and WaveService are under 99 top-level locals.
- **`check_stage_mirror.py` passes.**

Against the contract:
- **The clear:** `progress` clears on `aliveByFloor == 0` and nothing else.
- **The tent:** `tickTents` runs `TentClock`, then `Ahead`, then the three-argument
  `TentActive`. It needs a living resident, so no tent sends after its camp's residents are dead.
  It never yields.
- **The bonus:** `campClear` prices the bonus with `Fielded` on the zone's own plan tent and
  `run.tents[t].sent`, in the same kind order `tickTents` sends in.
- **The close:** it calls `ForgetOthers` beside `WakeFloor`.
- **N:** `approach` moves the fighters and does nothing else. `nextApproach` follows the lead's
  amended L1b-W4-31: it starts past the furthest reached checkpoint and never moves the party
  backwards.
- **Plan:** it shares one graph and one cells list across the region's zones and defs. Its door
  and clearance reach are taken at the level's top difficulty.
- **Validate:** every line asked for is present, and the shipped files are clean.

## Minor

1. **The safe point's "busy floor" rule broke now that the chase leaves the floor.** The places
   are `StageFlow.luau:2270` (`busy[index]` in `SafePoint`) and `WaveService.luau:995-1010`
   (`threats()` lists only rise/fight groups).
   - **The old assumption.** `SafePoint` treats "a group of zone i is in rise or fight" as "there
     is a fight at zone i's checkpoint". It also treats a homeward group as harmless. That was
     true while groups stayed on their own floor and `home` evaded. Wave 4 breaks it both ways.
     The contract kept the rule unchanged, which was correct only for the old chase.
   - **(a) It refuses a checkpoint where there is no fight.** In checklist step 3, Ben wakes a
     Pickets group and runs out of the east gate along RoadAB1. That road is 16 wide with void on
     both sides down to `killY` −13. Say he falls off at the U-bend or is knocked off by a
     brute's lane, so he is rescued.
     - A's checkpoint (−150, −44) was reached as he ran past it. It is refused because `busy[1]`
       is true: A's group is chasing him 60+ studs east of it.
     - No other checkpoint is reached and no camp is cleared, so the rescue puts him at
       `plan.start` (−470, 0, 0). That is about 320 studs back, on the far side of the camp he
       just fled.
   - **(b) It accepts a checkpoint the camp's homeward group is walking over.** Same run, a few
     seconds later: the group has lost him at about x −89 and is walking home along RoadAB1,
     through x −150.
     - A fall now gives `busy[1]` false and no threats, because `home` is in neither list. So he
       is placed at (−150, −44) among the homeward raiders.
     - Under L1b-W4-24, home now turns straight back to `fight` when a member `Sees` a reachable
       player. The fight he escaped restarts on the spot.
     - He gets the rescue i-frames, because `Engaged` reads only rise/fight groups.
   - **Fix:** judge region floors by position only.
     - Build `threats()` from every living member of a group in rise, fight **or home** (home
       turns back now). For home groups, read the crowd's group states rather than
       `run.awakeGroups`.
     - In `SafePoint`, apply the `busy[index]` clause only to zones without a `region`.

2. **No case or mutation pins `regionReach` counting tent units** (`StageFlow.luau:729-731`).
   - **Proof:** deleting `if type(config.tent) == "table" then take(config.tent.units) end`
     leaves `HARNESS: PASS (2,252 checks)` on a scratch copy.
   - **Why nothing catches it:**
     - The fixture's widest body (the brute, 2.2) and longest reach (the armoured's 48) are
       both residents (B's).
     - On the shipped Forest Road, A's tent fields brutes, but B's residents include one, so
       the door is the same.
   - **When it would bite:** a later region whose widest kind or longest reach comes only from a
       tent would get doors too narrow for its tent bodies (jammed at a door, the brief's "rusher
       frozen at a door"). It would also get a lock clearance short by the tent kind's reach.
   - **Fix:** add a Validate case where only A's tent fields the widest kind (or the longest
     reach), and a mutation that drops the tent clause.

3. **No case or mutation pins N's "before the armed locking camp" bound**
   (`StageFlow.luau:2021`).
   - **Proof:** changing `for index = from + 1, lock.floor - 1 do` to
     `for index = from + 1, #plan.zones do` leaves the harness green (2,252 checks).
     `check_stage_mirror` cannot see it either: on the fixture and on Forest Road the locking
     camp is the last zone.
   - **When it would bite:** a level with an open camp after a boss room (L2 or later). There,
     N on the road before the first lock would carry the party past the boss room to the later
     camp's approach, which breaks the contract's clause in L1b-W4-31.
   - **Fix:** a fixture with a fourth zone, an open camp with an approach after C. N from the
     road must answer `move gate` to C. Add the mutation above to `L1B_W4_RUN_MUTATIONS`.

## For other slices

None found.

Critical 0, Major 0, Minor 3
