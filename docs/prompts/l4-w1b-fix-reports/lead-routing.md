# L4 W1b fix round — lead's routing

**luau-engineer A finished F1/F2 but could not write its report file** (its tools refused the path). Its relay lives in
scratch files, which the designer reads directly:
`C:\Users\benja\AppData\Local\Temp\claude\c--Users-benja-Desktop-tycoon\3f855f00-eb33-4bab-adb5-c937f685030c\scratchpad\l4w1b-fix-a\tools\`
(`fixture_change.py`, `pins_lines.py.txt`, `pins_expected.luau.txt`, `draft_pins.py`, `mutate_entries.py.txt`, `mut.py`,
`m1.json`-`m7.json`, `mall.json`). In the lead's words, what A changed:

- `DashProof.Step` (the per-frame decision, pure) and `DashProof.Pending` (the window a pending claim would open, and its
  lapse); type `DashProof.Claimant`; F5's scope sentence in the header.
- `VitalsService`: the hold (a decision due while a covering claim is pending keeps the commit verdict in `entry.hold`;
  proven voids, lapsed lands, never past the lapse); travelling attacks held the same way; **`VitalsService.Step` is
  public and `Start` connects no Heartbeat** (new required hook `dashClaim`).
- `WeaponService`: `openIframes` gone; `proveDash` = one `Step` plus `showIframes`; `step` runs `trackAir`, then
  `VitalsService.Step(deltaTime)`, then `tickIframes` (the one fixed order); `GrantIframes` = `DashProof.Open(now)`.
- `tests_l4b.luau` rewritten: 88 checks (60 Hz, 20 Hz, 20 Hz bunched; ping 0 and 0.1; a 4,680-course timing study).
- **The harness is red until the designer applies `fixture_change.py`** (`tests.luau`: `vitalsBeat = Vitals.Step` and a
  `dashClaim` hook returning 0, 0, 0), the new pins (`run_harness.py`, `tests_l3_w2.luau`: remove `OPEN_IFRAMES_BODY`,
  add `PENDING_DASH_BODY`, `WEAPON_STEP_BODY`, `WEAPON_START_BODY`, `GRANT_IFRAMES_BODY`, 21 WeaponService keys,
  `trackOrder` and a new `frameOrder`), and 51 `mutate.py` entries (6 re-aimed, 45 new). With those, a copy reads
  `FAIL (2 of 4,133)`: B's two re-indented pins (`sendFloors`, `sendNote`), also the designer's.
- **The simulator:** with the hold, a proven dash's outcome equals pre-W1b whatever the latency, so the W1b mirror
  ("window at the dash's first frame if the path proves") is right again and slice 3 m1's delay model does not apply;
  only an unproven dash's covered hits change (they land at request + 0.45 s). Re-check "byte-identical" and the R8 row.

**A's rulings, accepted by the lead:** the knock rule (ruling 18) is judged at the decision's own moment; a held hit
outlives its striker's death and is dropped if the body was replaced; a held travelling contact answers "dodged" (the shot
flies on; on a lapse the hit lands from the queue); an aimed miss of a travelling attack is never held; the edge where two
server grants between a claim and its late proof push the dash window out (a held hit lands) is a known limit.

B's and ui's relays are in `luau-b.md` and `ui.md` in this folder.
