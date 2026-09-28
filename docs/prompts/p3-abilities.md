# Session prompt: combat P3 (abilities + remaining families)

Paste this into a new Claude Code session opened in `C:\Users\benja\Desktop\tycoon`. Run the lead on
Opus; every subagent on Opus (`model: "opus"`).

---

You are the lead engineer on Era City Tycoon (see `CLAUDE.md`). We are continuing the combat
rework. Read `CLAUDE.md` and every memory file it imports, especially
`.claude/memory/feel-pass-2026-09-23.md`. Then read, in this order:

1. `docs/COMBAT_DESIGN.md`: the plan of record (pillars, controls, feedback, Proving Grounds,
   build order in §10).
2. `docs/WEAPONS.md`: the approved roster, tier scaling and DPS targets, including each family's
   ability.
3. `docs/INTERFACES.md`: the last two sections, "P1 contracts" and "P2 contracts". The code
   follows them.
4. `docs/PLAN.md`: sections "P1 — Proving Grounds" and "P2 — Weapon families + bows" (what
   shipped, known limits, carry-overs).
5. `docs/BALANCE.md`: "P1" and "P2" sections.

## Where things stand (2026-09-28)

- P1 (Proving Grounds, crowd enemies, movement, Fortnite-style shooting, phone auto-fire,
  feedback layers, tuning panel) and P2 (10 weapon families, loadout slots, real arrows with charge,
  pierce, burst and split, spear thrust, shot fx for all players) are built, reviewed and committed.
- Ben loved P1 ("really love all the alternatives, the combo melee is great"). Check with him
  whether he has played P2 before you start, and ask for his P2 verdict (best bow and melee
  variants, spear strength, rifle strength).
- The range opens with `build/proving.rbxl` (DebugProving baked in via
  `tools/proving_project.py`; Ctrl+Shift+B "Build all"). **Ben's Studio is in Spanish and menu
  steps are hard for him**: prefer baked-in switches and key shortcuts. In the range, P = panel,
  Alt = cursor, 1/2 = slot.
- **No sound**, by Ben's ruling. Don't propose audio.
- **No on-screen attack button on phones** ("criminal"). Attacks auto-fire or auto-swing; only
  choices (jump, dash, abilities, slot switch) get buttons.

## P3 scope (COMBAT_DESIGN §10 step 4)

1. **Abilities for every family** listed in `docs/WEAPONS.md` §2: Whirlwind, Earthquake, Blade
   Storm, Leap Smash, Impale Dash, Arrow Rain, Volley, Slug Burst, Overcharged Shot, Mag Dump,
   Cluster Shell, Overload Sweep, Storm Coil. Each is on a cooldown, and kills shorten it. All of
   them are crowd-first (pillar 1) with a hitbox effect that matches the server shape (pillar 2),
   and all are tunable in the range. Studio keys Q/E; phone buttons.
2. **Phone slot switch button**: the P2 known limit. On a real phone only 1/2 and gamepad Y switch
   melee and ranged today.
3. **Remaining families**: Beam, Chain Gun, SMG (the Orbital/Metropolis ones in WEAPONS.md), as
   A/B variants in the range.
4. Anything Ben's P2 verdict asks for.

## How to work (unchanged from P1/P2; it worked)

- Contracts first, in `docs/INTERFACES.md` ("P3 contracts"), plus the Types and config keys
  yourself. Then fan out with disjoint ownership. Resuming the same agent by SendMessage is
  cheaper than a fresh one, but a new session starts with fresh agents, so hand them the P1/P2
  contracts.
- Owners that worked:
  - luau-engineer **Range**: `RangeService`, `HitShapes`, `Tuning`, `CombatRemotes`.
  - ui-engineer **Motion**: `InputController`, `MovementController`, `CameraController`.
  - ui-engineer **Feedback**: `FeedbackController`, `Crosshair`, `RangePanel`, `CombatUIController`,
    and the combat blocks of `Theme`.
  - luau-engineer **Crowd**: `CrowdService`, `CrowdCodec`.
  - ui-engineer **Render**: `CrowdRenderer`.
  - economy-designer: values in `ProvingGrounds.json`.
- **The lead owns `src/combat/server/Main.server.luau` wiring.** New intents need a handler there;
  P2 missed this once.
- Then roblox-reviewer → qa-runner → docs-keeper. Keep the playtest list to at most 15–20 steps.
- **Another Claude session may share this checkout.** Never `git add -A`; stage only your own
  files. `docs/CITY_GROWTH.md` and `docs/SOUND_AUDITION.md` are not ours. Give each agent its own
  scratch folder.
- Every delegation prompt says: never kill processes by image name; LF endings; Python is `py`;
  `export PATH="$HOME/.rokit/bin:$PATH"`.
- Stop after P3 for Ben's playtest. Missions stay untouched until P5.
