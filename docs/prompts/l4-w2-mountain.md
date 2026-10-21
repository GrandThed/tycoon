# L4 W2, track M — the mountain climb and the Castle Key (brief for the economy-designer)

Work in `C:\Users\benja\Desktop\tycoon-p5`, branch `l4-real-forest`. Bash with Git Bash syntax; `py` only (judge
`check_levels*` on `py -3.12`, say which Python gave each number); rokit tools need `export PATH="$HOME/.rokit/bin:$PATH"`;
the Luau CLI is `C:\Users\benja\Desktop\tycoon\tools\bin\luau.exe`. Convert files you create to LF. Do not commit. Kill
only your own PIDs, never by image name.

**Who else is here:** a rock builder is redoing the forest's rocks (`tools/levels/`, `tools/assets/forest_*`,
`tools/testfit/levelrender.py`, `src/shared/Config/LevelDress/`) and runs `forest.py build/check` against the layout; a
raider builder owns the raider files. Another designer works in the second worktree `tycoon-p5b` on `check_levels.py`,
`sim_range.py` and the harness (removing the old mission code). So: **design on an in-memory copy of the layout** (the
pattern of `docs/prompts/l4-w1-reports/perch_v3_study.py`: patch `sim_range.load_level_layout` and run check_levels' own
gates) and **write `src/shared/Layouts/Levels/ForestRoad.json` only when `docs/prompts/l4-w2-reports/mountain-go.md`
exists** (the lead writes it when the rock builder is done). Keep edits to `check_levels.py` and `check_levels_mutants.py`
to the smallest hunks (pinned lists, one hook call, new cases at the end): another designer is editing both in the other
worktree and the lead merges them. Do not edit `sim_range.py` or the harness.

## Ben's request and rulings (MISSIONS_DESIGN §28, written by the lead; read §22, §26, §27 too)

*"can we create a new parkour in the forest that uses the double jump in multiple times around a mountain that gives you a
key to unlock a secret room in the castle?"* Asked with sketches, he chose: **behind the trailhead** (north-west of the
start, past the creek: the corner of the lookout and the pond shrine, far from every camp), **one lap of about 8 double
jumps, 1-2 minutes, wide ledges, a miss drops you to the ledge below**, and **built now with the forest** (baked in the
same upload, so still one harvest paste).

Lead's rulings: the summit chest is a fourth secret, `mountain`, `needs` `doubleJump`; its reward adds `key: "castle"`
(the Castle Key) to a small pay like the lookout's; the key is the opened secret itself (already saved per player in
`combat.secrets`, no profile change); the Castle's plan will have a room this key opens; no enemies on the climb; the
summit and every ledge must never be a sniper spot; a fall never leaves the level; phone-friendly ledges.

## The job

1. **Design the climb** in the layout's own terms (`blocks`, `secrets`, a sign, `route` if the climb's foot needs a path):
   a foot yard reached from the trailhead or the creek bank on foot (no ability), a mountain core that is unclimbable
   (no standable top a player can reach except the ledges and the summit), **about 8 ledges spiralling one lap**, the
   summit with the chest. Every hop needs Double Jump: one jump plus a dash must fall short, and so must every lifting
   ability's arc that exists today (Leap Smash, Impale Dash, the knock-ups: L2-18's lift model), with a margin you state.
   Ledges wide enough for a phone (propose a minimum; the lookout ledge is 24 × 14). From any ledge, a fall lands on a
   lower ledge or the yard, never the void and never the road's far side of the creek. Look at the trailhead, creek and
   lookout geometry in `ForestRoad.json` and `assets/testfit/out/Levels/ForestRoad/plan_top.png` and keep the lookout's
   double-jump gap (x -458..-434 over Road1) untouched.
2. **A new gate `tools/check_parkour.py`** (new file, yours): for this climb and any later one, with check_levels'
   movement numbers (jump, double jump, dash, gravity, walk speed, the lift model): every hop is possible with Double
   Jump and impossible without it; no shortcut skips more than one ledge; every fall lands safely; the summit is reachable
   in order; a rough climb time; the climb never sees a region cell within the longest bow range (110) without a wall
   between. Its mutants (each must fail it): a ledge lowered to one-jump reach, a gap widened past double-jump reach, a
   ledge moved so a fall reaches the void, the core given a standable top. Hook it into `check_levels.py` with one call,
   or keep it a separate gate line, your call.
3. **The data:** the `mountain` secret in the layout (chest block, sign text like the others, e.g. "MOUNTAIN - needs DOUBLE
   JUMP") and in `src/shared/Config/Levels/1_ForestRoad.json` `secrets.mountain` (`name`, `valor`, `materials`, `key`).
   Propose the pay with a reason (the lookout pays 3 Valor + 50 Timber and also the Flamethrower).
4. **check_levels:** the existing gates must pass with the new blocks (route, sneak, the sniper spots and pinned lists,
   L2-18 for the new secret, part count under 600, the walled-camp rules untouched). `py -3.12 tools/check_levels.py` and
   `py -3.12 tools/check_levels_mutants.py` PASS on the final layout.
5. **For the forest generator** (the rock builder dresses the mountain after you): write in your report what it needs:
   the yard's outer edge for invisible walls, **no invisible walls on ledge edges** (falls are designed), which faces are
   core (rock cliff in Ben's clustered-block style) and which are ledge tops (flat cap stones matching the block tops
   exactly), the summit's dressing.
6. **For the game code** (W2): what the server and client must do for `key` (a toast "Castle Key found", the map
   showing keys, the end screen row), so the lead can amend the W2 contract.

## Report (end your turn with it even if everything passed)

`docs/prompts/l4-w2-reports/mountain.md`: an ASCII plan and side view of the climb; every block with its coordinates;
the hop table (each hop's gap and rise, single-jump-plus-dash reach, double-jump reach, the best lifting ability's reach,
the margins); the fall table; the climb time; the pay and why; every gate's verdict line; the forest generator's and the
game code's needs. Write it as you go.
