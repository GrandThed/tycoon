# L2 W2 third fix round: report (2026-10-19)

Brief: `docs/prompts/l2-w2-fix3.md` (m1, s1 of `l2-w2-review/fix2-diff.md`; s2 is docs only and not done here).
One agent, branch `l2-w2-fix2` in `tycoon-p5b`. Nothing is committed.

## Files changed

- `src/combat/server/Services/PositionRing.luau`: `Speed` is replaced by `Motion(history, now, position, window,
  span): (number, Vector3)`, the same walk returning the fastest stretch's speed and the unit vector of that
  stretch's displacement (`Vector3.zero` when nothing moved). `Speed` had no other caller, so it is gone rather than
  kept as a wrapper; every text the old ring mutants replace is unchanged.
- `src/shared/WorldReact.luau`: `LeadHead` takes the ring's way; the `AimClear` comment no longer claims "however the
  velocity was claimed".
- `src/combat/server/Services/WeaponService.luau`: `claimSlack` reads `PositionRing.Motion` and also returns the
  way; `aimAllowed` passes it to `LeadHead`.
- `tools/crowd_harness/tests_p5.luau`: `ringTests` read the speed through `Motion` (`speedOf`), plus three cases on
  the way (10, 10b, 10c).
- `tools/crowd_harness/tests_l2w2.luau`: `leadTests` rewritten for the new signature, with the reviewer's probe and
  the honest gatehouse case; `wiringTests` gains a `claimSlack` check.
- `tools/crowd_harness/run_harness.py`: the aim source check reads the new `aimAllowed` lines and `claimSlack`'s body
  (`claimFound`, `claimLines`, `claimMotion`).
- `tools/crowd_harness/mutate.py`: four `fix2 m2` entries re-aimed; 11 new entries in `L2W2_FIX3_MUTATIONS`.

## m1: the lead goes where the server saw the body go

The lead expression, before and after (`src/shared/WorldReact.luau`, `LeadHead`):

```lua
-- before (second fix round): along the client-replicated velocity, its length capped at the ring speed
return head + velocity * (math.min(magnitude, length(speed)) / magnitude * length(lag))

-- after: along the ring's own way; the velocity's part along it (floored at 0) may only shorten it
local way = motion / magnitude
local along = math.max(velocity:Dot(way), 0)
return head + way * (math.min(along, length(speed)) * length(lag))
```

- Signature: `WorldReact.LeadHead(head: Vector3, motion: Vector3, velocity: Vector3, speed: number, lag: number):
  Vector3`. `motion` is `PositionRing.Motion`'s way, normalised again inside (any length). A head, way or velocity
  that is not finite, a way of length 0, or a speed or lag that is not a finite number above 0 leads nowhere.
- Call site: `local slack, speed, lag, motion = claimSlack(...)`, then
  `WorldReact.LeadHead(anchor, motion, root.AssemblyLinearVelocity, speed, lag)`.
- The way is that of the **same stretch the speed was read on** (the fastest one in the window, `originSpeedSeconds`
  long). So direction and length come from one server measurement. The newest stretch was the reviewer's other
  option. I did not take it because a replication stall would then zero the way while the speed still held.
- The reviewer's probe, as a harness case: a free-standing wall 20 × 76 × 2.5, the head 1.5 off its middle, the
  origin beyond it near the east end inside the slack, the ring reading 74 straight up, a claimed velocity of
  (74, 0, 0) at lag 0.3.
  - The head's own line is refused.
  - Led along the claimed velocity (the old rule), the case is allowed. This check keeps the case from being vacuous.
  - Led along the ring's way it is refused. That holds going up, and going down with 10 of the velocity along the
    way.
- The hopping forger now gets a vertical lead only, because that is what the ring saw. A real hop next to a wall
  whose top is within `speed × lag` (22 studs at 74) could still be led over that top. That is real motion, which
  the ruling accepts. Forest Road has no tall wall that low beside a fight floor.

## s1: the honest gatehouse case

This case runs on Forest Road's own four `GatehouseWall*` boxes, as `Pieces` builds them, not on copied numbers.
- The head is at (299, 16.5, −37), dashing east: way (1, 0, 0), velocity 133, speed 133, lag 0.3. The origin is at
  (306.7, 17, −33).
- The head's line is refused.
- The lead runs 39.9. It meets WallE at 22.5 and is carried to x 321. The line from there is clear, and `AimClear`
  allows the shot.
- Both scratch mutants from the review are now `mutate.py` entries (`fix3 s1: ...`). With either, this case is
  refused again.

## Mutations

- Re-aimed (same labels, new text): `fix2 m2: the aim leads nowhere`, `... the lead runs at the root's full speed`,
  `... the lead ignores the lag`, `... an endless velocity leads`.
- New (`L2W2_FIX3_MUTATIONS`):
  - the lead goes along the client's velocity (the "put the velocity back" mutant the brief asks for);
  - aimAllowed leads along the root's velocity;
  - claimSlack hands back the root's velocity;
  - the velocity does not shorten the lead;
  - a velocity against the way is not floored;
  - the way is taken at its length;
  - a way that is not finite leads;
  - the ring's way is the first stretch's;
  - the ring's way is not a unit;
  - a lead that meets a wall counts for nothing (`then head`);
  - `LEAD_STANDOFF = 50`.

## Gates

| Gate | Result |
|---|---|
| harness | PASS, 2,849 checks (was 2,835) |
| `mutate.py` "l2w2" | 93 run, 0 not caught |
| `mutate.py` "fix2 m" | 22 run, 0 not caught |
| `mutate.py` "fix3" | 16 run, 0 not caught (the 11 new ones each caught by 1 to 3 checks) |
| `mutate.py` "l2 fix c4" | 6 run, 0 not caught |
| stale-text count, all entries | 996 entries, 0 stale |
| `check_stage_mirror.py` | PASS |
| `check_compile.py` | PASS, 172 files |
| stylua `--check`, selene (the three changed sources) | clean / 0 errors, 0 warnings |
| luau-lsp analyze (the three changed sources, combat sourcemap built in the scratchpad) | exit 0, no errors |

- Coverage: the four filters together cover all 68 entries on `WorldReact.luau` (57) and `WeaponService.luau` (11),
  plus the PositionRing entries labelled `fix3`.
- The harness test files were not stylua-formatted at HEAD either (long-line convention), so I left them as they are.

## Not done here

- s2 (Beam B loses its moving bloom) is a PLAYTEST line, for docs-keeper.
- `docs/INTERFACES.md` ruling 7 (P5) and the L2 W2 contract text say nothing about the lead's direction. If the lead
  wants this recorded, add one line under the L2 W2 rulings: "the aim rule's lead goes along
  `PositionRing.Motion`'s way; the replicated velocity only shortens it (fix3 m1)".
