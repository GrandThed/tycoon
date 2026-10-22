# L4 W1b fix round 3 — luau-engineer A (H1's HasWaiting, H2)

Worktree `tycoon-p5c`, branch `l4-w1b-fix2`, nothing committed. Rulings: `docs/prompts/l4-w1b-fix3.md`. Findings:
`docs/prompts/l4-w1b-review/5-fix2-diff.md` (m3, s1, s2).

## Files changed

- `src/combat/server/Services/VitalsService.luau`:
  - H1: new `HasWaiting`.
  - H2: `release` and `settle` take each entry out before deciding it.
  - The header gets an H1/H2 paragraph.
- `src/combat/server/Services/WeaponService.luau`:
  - H2: each shooter in `trackAir` runs under its own `xpcall`.
  - `stepFailed` moves above `trackAir`. Its body is unchanged; only the comment above it gained "(H2: or one shooter's
    air tracking)".
- `tools/crowd_harness/tests_l4b.luau`:
  - two new groups, "(g) a throw while deciding (H2)" (3 checks) and "(g) the boss room's clear waits (H1)" (3 checks);
  - the i-frame hook now goes through `L4B.window` (default `L4B.claimWindow`; `fresh()` resets it).
  - It is not run through stylua: the harness test files are not stylua-formatted in the repo (HEAD's
    `tests_l4b.luau` already fails `stylua --check`), and QA runs `stylua --check src`.

## Contracts (signatures)

```lua
-- VitalsService, public (new)
function VitalsService.HasWaiting(player: Player?): boolean
```

- `HasWaiting(player)` is true while that player's G1 `waiting` list is not empty. That means a decision whose
  moment has come still waits: either for a dash claim, or behind one that does. It is false for a player with no
  record.
- `HasWaiting()` (nil) answers for anyone in VitalsService's records. In a mission that is the server's one party.
- It is a pure query. It reads `#vitals.waiting`, writes nothing and never yields.
- It turns false inside the `VitalsService.Step` that releases the list:
  - on the frame the claim is proven, when the held entries are voided ("dodged");
  - or on the first frame past the claim's lapse, when they land. A down among them is applied in that Step, and
    `onDown` runs after that Step's batch has left.
- It is therefore true at most `lapse` (0.45 s shipped) plus one frame after the claim. That holds even if the claim
  is never resolved, because `awaitsDash` checks `now <= lapseAt` itself.
- `ClearThreats` is unchanged: it still empties every `waiting` list. It is the real clear, which B now defers.

Internal, unchanged signatures:

- `release(config, vitals, now)`
- `settle(config, now)`
- `trackAir(now, deltaTime)`

New nested local:

- `trackOne(player: Player, shooter: Shooter): ()` inside `trackAir`. It closes over the frame's `now`, `deltaTime` and
  `params`.

## H2 as built

**release** walks the front of `vitals.waiting`:

- `table.remove(list, 1)` comes first.
- Then the refresh of `covered`, then `decide`.
- If `decide` says the entry still waits, `table.insert(list, 1, entry)` and `return`.
- A throw anywhere in the refresh or the decision therefore drops that entry alone. The entries before it are already
  out of the list and are never decided again; the entries behind it stay, in order.

**settle**'s queue walk no longer compacts at the end:

- An entry whose moment has come (`due = now >= entry.decideAt`) is taken out with `table.remove(pending, index)`
  before its i-frames are asked and before it is decided.
- An entry not yet due stays, and `index` moves on.
- After any throw the queue is still contiguous and in order: the kept entries in front, the unvisited ones behind,
  with no hole and no duplicate.
- Rule 18's knock loop reads `pending` during a decision as before. It now sees exactly the live entries (kept and
  unvisited), without stale copies.

**trackAir** builds the loop body as a nested `trackOne`, and the loop becomes
`for player, shooter in state.shooters do xpcall(trackOne, stepFailed, player, shooter) end`.

- The no-root branch's `continue` became `return`.
- The body keeps its indentation (two tabs). Every existing `TRACK_AIR_BODY` pin (trackRecordThenProve,
  trackNoRootClears, trackOrder, trackStood, trackFall, fallCleared) and every mutate.py entry on trackAir still match
  unchanged. That is why it is nested rather than a module-level function.
- The cost is one closure per frame while anyone is in the place.

Throws still propagate out of VitalsService.Step to WeaponService's `xpcall(VitalsService.Step, stepFailed, ...)`, as
the ruling has it, so "warns once" is `stepFailed`'s.

## Verification

**Harness on this worktree:** `HARNESS: PASS (4,213 checks)`. That count includes B's in-progress
`tests_l4b_run.luau`; mine adds 6. Before my edits it was 4,185.

**The reviewer's s1 probe** (`...\scratchpad\l4w1b-fix2\probe_throw.luau`, run with the reviewer's own
`runprobe.py` on a copy of this tree):

- Before: 13 frames threw, health 130 -> 26, 0 hurt effects sent.
- Now: `PROBE ... 1 frames threw, 2 hurts landed, health 130 -> 114`.

**No change when nothing throws:**

- The reviewer's `probe_fuzz2.luau` (400 seeded queues with rings, repeated claims and honest dashes) and
  `probe_g1.luau` give identical PROBE lines on `git archive HEAD` and on this tree.
- Every G1, F1 and study check is unchanged.

**New checks (tests_l4b.luau):**

- H2:
  - The release throw (the review's probe as a check): 1 throw, `landed landed` in one batch the frame after it,
    health -16, nothing left waiting.
  - A queue throw (A, B, D due together, C kept): B dropped; A once, D the next frame, C at 0.6; health -24.
  - An i-frame-hook throw on a due entry: it is out before it is asked; 1 landed, 1 dropped.
- H1:
  - No claim: the clear goes at the kill and finds them down.
  - A claim that never proves, the boss dead at 0.3: HasWaiting is true at the kill (and false for a player with no
    record). The slam downs them at 0.467 and the clear goes at 0.483, after it.
  - An honest claim proven after the kill: the slam is dodged at 0.200 and the clear goes right after it, at 0.217.

**Mutants:** 16, on a scratch copy with the proposed pins below. All 16 are caught:

- the two re-aims;
- 5 release/settle;
- 4 HasWaiting;
- 5 trackAir, caught by the proposed pins.

Paste-ready entries are below and in
`C:\Users\benja\AppData\Local\Temp\claude\c--Users-benja-Desktop-tycoon\3f855f00-eb33-4bab-adb5-c937f685030c\scratchpad\a3\entries.py.txt`;
the runner is `...\scratchpad\a3\muts.py` with `base.json` and `mutants.json`.

**mutate.py stale check:** 1,795 entries, 2 stale, both mine (listed below). B's WaveService edits may add others.

**Static checks:**

- `stylua --check` and selene on both service files: clean.
- `py tools/check_compile.py`: PASS, 176 files.
- luau-lsp with the combat sourcemap (written to scratch): 0 diagnostics. A planted type error was reported, so the run
  was live.
- The hub sourcemap does not contain these combat-server files. It reports only unresolved-require consequences
  ("Unknown require: unsupported path" and the unknown types that follow), none at a changed line.

## Known limits (for the lead)

1. **A throw that leaves VitalsService.Step still ends that frame's Step.** The other players' releases, the rest of
   the queue and the flush run one frame late, and that frame's effects leave with the next frame's batch.
   - Each throw consumes the entry that threw, so this cannot repeat on the same entry.
   - An `xpcall` per entry would avoid even the one-frame delay, but it needs a warn handler inside VitalsService. The
     ruling did not ask for it.
2. **A throw in the i-frame question of an entry that is not yet due** leaves it in place, so each frame stops there.
   That lasts until the entry falls due; it is then out before it is asked, and dropped. The bound is its decideAt:
   the lag (at most 0.3 s), or a lob's flight.
3. **A dropped entry lands nothing and sends no effect.** For a travelling contact, ThreatField had already been told
   "dodged".
4. **A throw inside `trackOne` leaves that shooter's state as far as it got that frame.** For example, the ring sample
   is recorded but the proof is not run. Its claim still ends by its own lapse (`awaitsDash`), and the other shooters
   are unaffected.
5. **HasWaiting reads the lists as the last VitalsService.Step left them.** Two Heartbeat handlers run in no set
   order, so a list released in this frame's Step may be seen as released one frame later. The clear then goes at
   most one frame after the release.

## For the other owners

### luau-engineer B (WaveService)

Use `VitalsService.HasWaiting()` (any fighter) or `HasWaiting(member.player)` per fighter; the signature and
semantics are above.

- In my test the deferred clear is asked before the frame's Step. It goes through on the first frame that finds
  HasWaiting false, which is the frame after the release.
- Nothing else changed in VitalsService's public surface.

### Designer: mutate.py

**Re-aims (the same labels, new texts).** Both are verified caught.

- `l4b f1: settle drops a held entry`
  - Old: `'\t\telseif decide(config, entry, now) then\n\t\t\ttable.insert(entry.vitals.waiting, entry)\n'`
  - New old-text: `'\t\tif due and decide(config, entry, now) then\n\t\t\ttable.insert(entry.vitals.waiting, entry)\n'`
  - New mutation: `'\t\tif due then\n\t\t\tdecide(config, entry, now)\n'`
- `l4b g1: the release drops one that still waits`
  - Old: `'\t\tif decide(config, entry, now) then\n\t\t\tbreak\n\t\tend\n\t\treleased += 1'`
  - New old-text: `'\t\tif decide(config, entry, now) then\n\t\t\ttable.insert(list, 1, entry)\n\t\t\treturn\n\t\tend\n'`
  - New mutation: `'\t\tdecide(config, entry, now)\n'`

**New entries.** Each is verified caught; the WEAPON ones are caught with the pins in the next subsection.

```python
    'l4b h2: the release takes an entry out only once it is decided': (VITALS, '\t\ttable.remove(list, 1)\n\t\tif not entry.covered then\n\t\t\t-- Its whole span is past; asked again now, the windows a proof or a released knock\n\t\t\t-- opened from earlier moments count.\n\t\t\tentry.covered = shielded(vitals.player, entry.strike.at, entry.decideAt)\n\t\tend\n\t\tif decide(config, entry, now) then\n\t\t\ttable.insert(list, 1, entry)\n\t\t\treturn\n\t\tend\n\t\tentry = list[1]\n', '\t\tif not entry.covered then\n\t\t\t-- Its whole span is past; asked again now, the windows a proof or a released knock\n\t\t\t-- opened from earlier moments count.\n\t\t\tentry.covered = shielded(vitals.player, entry.strike.at, entry.decideAt)\n\t\tend\n\t\tif decide(config, entry, now) then\n\t\t\treturn\n\t\tend\n\t\ttable.remove(list, 1)\n\t\tentry = list[1]\n'),
    'l4b h2: the release puts a held entry back behind the others': (VITALS, '\t\t\ttable.insert(list, 1, entry)\n', '\t\t\ttable.insert(list, entry)\n'),
    'l4b h2: the queue takes an entry out only once it is decided': (VITALS, '\t\tif due then\n\t\t\ttable.remove(pending, index)\n\t\telse\n\t\t\tindex += 1\n\t\tend\n\t\tif not entry.covered then\n\t\t\t-- Asked every frame, not only at the decision, and of the window before the current\n\t\t\t-- one as well: a dash that covered the impact may have lapsed and been replaced by\n\t\t\t-- then, or even before the step that raised the strike.\n\t\t\tentry.covered =\n\t\t\t\tshielded(entry.vitals.player, entry.strike.at, math.min(now, entry.decideAt))\n\t\tend\n\t\tif due and decide(config, entry, now) then\n\t\t\ttable.insert(entry.vitals.waiting, entry)\n\t\tend\n', '\t\tif not entry.covered then\n\t\t\t-- Asked every frame, not only at the decision, and of the window before the current\n\t\t\t-- one as well: a dash that covered the impact may have lapsed and been replaced by\n\t\t\t-- then, or even before the step that raised the strike.\n\t\t\tentry.covered =\n\t\t\t\tshielded(entry.vitals.player, entry.strike.at, math.min(now, entry.decideAt))\n\t\tend\n\t\tif due and decide(config, entry, now) then\n\t\t\ttable.insert(entry.vitals.waiting, entry)\n\t\tend\n\t\tif due then\n\t\t\ttable.remove(pending, index)\n\t\telse\n\t\t\tindex += 1\n\t\tend\n'),
    "l4b h2: the queue asks a due entry's i-frames before taking it out": (VITALS, '\t\tif due then\n\t\t\ttable.remove(pending, index)\n\t\telse\n\t\t\tindex += 1\n\t\tend\n\t\tif not entry.covered then\n\t\t\t-- Asked every frame, not only at the decision, and of the window before the current\n\t\t\t-- one as well: a dash that covered the impact may have lapsed and been replaced by\n\t\t\t-- then, or even before the step that raised the strike.\n\t\t\tentry.covered =\n\t\t\t\tshielded(entry.vitals.player, entry.strike.at, math.min(now, entry.decideAt))\n\t\tend\n', '\t\tif not entry.covered then\n\t\t\t-- Asked every frame, not only at the decision, and of the window before the current\n\t\t\t-- one as well: a dash that covered the impact may have lapsed and been replaced by\n\t\t\t-- then, or even before the step that raised the strike.\n\t\t\tentry.covered =\n\t\t\t\tshielded(entry.vitals.player, entry.strike.at, math.min(now, entry.decideAt))\n\t\tend\n\t\tif due then\n\t\t\ttable.remove(pending, index)\n\t\telse\n\t\t\tindex += 1\n\t\tend\n'),
    'l4b h2: the queue never takes a due entry out': (VITALS, '\t\tif due then\n\t\t\ttable.remove(pending, index)\n\t\telse\n\t\t\tindex += 1\n\t\tend\n', '\t\tindex += 1\n'),
    'l4b h1: HasWaiting(player) never true': (VITALS, '\t\treturn vitals ~= nil and #vitals.waiting > 0\n', '\t\treturn false\n'),
    'l4b h1: HasWaiting() never true': (VITALS, '\t\tif #vitals.waiting > 0 then\n\t\t\treturn true\n', '\t\tif false then\n\t\t\treturn true\n'),
    'l4b h1: HasWaiting(player) answers for anyone': (VITALS, '\tif player ~= nil then\n\t\tlocal vitals = vitalsByPlayer[player]\n\t\treturn vitals', '\tif false then\n\t\tlocal vitals = vitalsByPlayer[player]\n\t\treturn vitals'),
    'l4b h1: HasWaiting reads the queue, not the waiting': (VITALS, '\t\treturn vitals ~= nil and #vitals.waiting > 0\n', '\t\treturn vitals ~= nil and #pending > 0\n'),
    "l4b h2: one shooter's throw stops the rest": (WEAPON, '\tfor player, shooter in state.shooters do\n\t\txpcall(trackOne, stepFailed, player, shooter)\n\tend\n', '\tfor player, shooter in state.shooters do\n\t\ttrackOne(player, shooter)\n\tend\n'),
    "l4b h2: a shooter's throw ends the loop": (WEAPON, '\tfor player, shooter in state.shooters do\n\t\txpcall(trackOne, stepFailed, player, shooter)\n\tend\n', '\tfor player, shooter in state.shooters do\n\t\tif not xpcall(trackOne, stepFailed, player, shooter) then\n\t\t\tbreak\n\t\tend\n\tend\n'),
    'l4b h2: no shooter is tracked': (WEAPON, '\tfor player, shooter in state.shooters do\n\t\txpcall(trackOne, stepFailed, player, shooter)\n\tend\n', ''),
    "l4b h2: a shooter's throw is swallowed": (WEAPON, '\tfor player, shooter in state.shooters do\n\t\txpcall(trackOne, stepFailed, player, shooter)\n\tend\n', '\tfor player, shooter in state.shooters do\n\t\txpcall(trackOne, function() end, player, shooter)\n\tend\n'),
    'l4b h2: trackOne holds nothing (the body back in the loop, unprotected)': (WEAPON, '\tlocal function trackOne(player: Player, shooter: Shooter): ()\n', '\tlocal function trackOne(_player: Player, _shooter: Shooter): () end\n\tlocal function trackTwo(player: Player, shooter: Shooter): ()\n'),
```

### Designer: run_harness.py L4B_LINES and tests_l3_w2.luau L4BP (H2's deciding lines in WeaponService)

Verified on a scratch copy (BASE PASS, 4,216 there with B's tests). Add these after `"trackNoRootClears"`:

```python
    "trackEach": (WEAPON_SERVICE, TRACK_AIR_BODY, "text",
                  "\tfor player, shooter in state.shooters do\n\t\txpcall(trackOne, stepFailed, player, shooter)\n\tend\n"),
    "trackOneDefined": (WEAPON_SERVICE, TRACK_AIR_BODY, "lines", "\tlocal function trackOne(player: Player, shooter: Shooter): ()"),
    "trackOneNames": (WEAPON_SERVICE, None, "text", "trackOne"),
```

```lua
		trackEach = { 1, "trackAir runs each shooter under its own xpcall, the loop holding nothing else (H2)" },
		trackOneDefined = { 1, "one shooter's air tracking (trackOne) lives inside trackAir (H2)" },
		trackOneNames = { 2, "trackOne is named twice: its definition and the xpcall (H2)" },
```

- Every existing L4BP count stays as it is. In particular, `claimWrites` stays at 3: trackOne's no-root clear is still
  one write.
- **m2 (`stepFailed`'s body pin) is yours.** The function now sits above `trackAir`. Its body is byte-for-byte the same,
  so `^local function stepFailed\(.*?^end$` finds it and the reviewer's three mutants apply as written.

### Designer: VitalsService deciding lines, if you want text pins

The harness loads VitalsService, so the behaviour checks above already hold all of these. Text pins are optional.

- release:
  - `\t\ttable.remove(list, 1)` comes before `\t\tif not entry.covered then`;
  - `\t\t\ttable.insert(list, 1, entry)` is followed by `\t\t\treturn`.
- settle:
  - the block `\t\tif due then\n\t\t\ttable.remove(pending, index)\n\t\telse\n\t\t\tindex += 1\n\t\tend\n` comes before
    the `covered` refresh;
  - `\t\tif due and decide(config, entry, now) then`.
- HasWaiting:
  - `\t\treturn vitals ~= nil and #vitals.waiting > 0`;
  - `\t\tif #vitals.waiting > 0 then\n\t\t\treturn true`.

### Designer: sim_range.py

No change from me. My H2 changes nothing when nothing throws; the reviewer's fuzz and G1 probes give identical lines.
H1's deferral is B's.

## What to check in Studio

- **No `[WeaponService] Heartbeat:` warning in a normal run** (unchanged).
- **One warning only if something throws.** If a part of the frame or one player's air tracking throws, exactly one
  warning appears per message. The other players' dashes still prove: a dash still reads DODGED for them.
- **The boss race** (with B's deferral). Solo, Colossus at a sliver:
  - Dash into the boss room's wall as its slam lands, then kill it within half a second. With the dash unproven, you go
    down and the run is lost; the boss's death does not save you.
  - With a clean dash, the slam reads DODGED and the room clears at once.
