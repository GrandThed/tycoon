# L3 study — the Armory (brief)

Two groundwork study agents run in parallel for milestone L3 of a Roblox project. Work in the worktree
`C:\Users\benja\Desktop\tycoon-p5`, branch `l3-armory`. **Write no code and edit no file except your own report.**
Kill only your own PIDs. Tools: `py` (never `python`); rokit tools need
`export PATH="$HOME/.rokit/bin:$PATH"`; the Luau CLI is `C:\Users\benja\Desktop\tycoon\tools\bin\luau.exe`.

- **Part A (systems)** writes `docs/prompts/l3-study-report-systems.md`.
- **Part B (screen and models)** writes `docs/prompts/l3-study-report-screen.md`.

Each report: under about 300 lines, plain words, file:line evidence for every claim about the code. End your
reply with a ten-line summary and the report path.

## What L3 is

`docs/MISSIONS_DESIGN.md` §10 (the Armory), §11 (open questions), §14 ("L3. The Armory: per-weapon tiers, the
upgrade loop with Forest drops, the new screen, weapon models"), §22–§23 (L2, closed 2026-10-20). Read
`CLAUDE.md` (rules), `docs/WEAPONS.md` (families), `docs/COMBAT_DESIGN.md` only where it touches tiers, and the
INTERFACES sections you need (grep `^# ` for headings: C0 has the Armory, P5 has the tier choke point, L2 W1–W3
have the lobby Armory panel, the profile v7 step, the Flamethrower and the Frost Hammer).

Ben's standing rulings that bind L3 (do not re-open them):
- **One ladder of 20 tiers for every weapon, and each weapon has its own window on it: its own start tier
  and its own top tier** (2026-10-13; Ben restated it 2026-10-20: "we are not starting every weapon with tier 1
  nor ending every weapon to tier 20"). An early weapon might run 1–6, a late one 9–16, a relic start and stay
  at 20. MISSIONS_DESIGN §10's "can be upgraded to 20" is wrong; propose the windows. It replaces "the tier
  belongs to the slot" (2026-09-28).
- **The Armory is a screen, in both places** (the city hub and the dungeon place's lobby camp).
- **Free variant styles** (2026-10-12): every owned family offers all its styles; switching only outside fights.
- The L2 lobby loadout is kept **for the visit only**; L3 designs the saved one.
- The Frost Hammer stays locked until the Castle ("Found in the Castle"); the Flamethrower is found in the
  Forest Road lookout chest. 15 families.
- **Detailed weapon models** (2026-09-23, over chunky low-poly). No Kenney weapon kit exists: generated geometry.
- No sound in combat. Phones must work. Ben's Studio is in Spanish: prefer baked-in switches and keys.
- Publish freeze: the Expeditions place is not published from `main` until L4. The hub is live.

## Part A — systems: tiers, economy, profile, loadout

1. **The Armory today, end to end, in both places:** `Config/Armory.json` (ladder, bands, materials, the income
   gate, Ascension), `src/shared/Armory.luau`, `ArmoryService`, `Catalog`, the remotes (`RequestBuyGear`,
   `RequestAscend`, `RequestSetFamily`, ...), how a tier reaches damage (the P5 choke point), max HP
   (`Armory.MaxHp`), `heavyHit` judged unscaled, the Studio gear presets (G, 2/2), and any lever that grants gear.
2. **Per-weapon tier windows on a ladder of 20:** what changes in each file; a proposed window (start, top) for
   each of the 15 families with the reasoning (where it is found, its role, what a window means for switching
   weapons); today's multiplier curve and a 20-tier curve that keeps tier 1–2 numbers where the bosses are
   tuned; what a weapon at its top tier is worth against a later weapon's start; every simulator, gate and boss that reads tier
   numbers (`sim_range.py`, `sim_combat.py`, `check_stage_mirror.py`, `tools/crowd_harness/`, `check_levels.py`
   `fielded_lifts`, the Colossus and Warlord tuning, the R8 sniper gates); how §6's recommended tiers (first, +2,
   +4) map onto 20.
3. **Economy:** what Forest Road pays today per difficulty (per kill, camp bonus, boss, the three chests, Valor,
   Timber, cash) and what a first clear and a replay pay. Under §10's proposal (tiers 1–4 paid in the Forest's
   material, the band's last tier also needs the boss trophy from Hard), how many runs one weapon needs from tier
   1 to 4 at a few cost curves. Hard's and Brutal's rewards are placeholders: propose. The city income gate:
   where it is checked, what dropping it changes (§11.1); what the city still gets from a level.
4. **The profile:** v7's shape today and the whole shape L3 should settle once (per-family tier, owned families,
   saved loadout, abilities, secrets, shortcuts, and whether level stars leave session memory); a v7 → v8 step
   that converts today's slot tiers (§11.3: players who own tiers in the live game; find what the live hub and
   the frozen live Expeditions place run and what they would do with a v8 profile); a conversion rule.
5. **The saved loadout:** where and when it can change (lobby, hub, between waves), what the hub's Armory does
   (view, upgrade, equip?), what happens to the lobby's visit-only choice.
6. **Carried items that name L3** in `docs/PLAN.md` and INTERFACES (grep `L3`): e.g. the ability-arc hops at the
   U-bends once a lifting family can be owned without a lever; a longer-range weapon reaching Forest Road. Say
   what each needs.
7. **Decisions for Ben** (only what truly needs him; 2–4 options each, the lead-style recommendation, the cost of
   each), **risks** in plain words, a **wave split** (each wave playable on its own in Studio) with owners
   (`luau-engineer`, `ui-engineer`, `economy-designer`).

## Part B — the screen and the weapon models

1. **The Armory UI today:** the hub `src/client/UI/ArmoryPanel.luau` and the lobby
   `src/combat/client/UI/Armory*.luau`: sizes, top-level local counts against the 180 compile gate
   (`py tools/check_compile.py`), how hub client files are shared into the combat place (`combat.project.json`),
   phone layout (375×667 portrait and 667×375 landscape), input (K, gamepad Y, LB/RB), what each screen shows.
2. **The L0 picture:** the Armory section of
   `assets/research/2026-10-13-missions/expeditions-mockups.html` (Ben saw it; his answer was "a screen in both
   experiences"). What it shows, what of it is cheap and what is not.
3. **The weapon shown large, in 3D, turning:** a ViewportFrame approach, its cost on phones, lighting in a
   ViewportFrame, what shows before models exist, the shelf of 15 (owned, dark outlines for unowned, a hint of
   where each is found), the tier track and what the next tier gives. Two or three layout options drawn as ASCII
   sketches small enough for a click-question preview (about 40 columns × 16 rows).
4. **Weapons in hand today:** what a player holds (nothing, a placeholder?), how `WeaponController`,
   `CombatFxController` and `InputController.ShotRay` draw shots and swings, where a model would attach (R15
   hands, both slots shown or one held and one holstered), the procedural poses, whether other players must see
   the model (server-side, or client-side from an attribute), and what must not move (the shot origin rule, the
   melee hitbox drawing).
5. **A generated weapon kit:** the asset route for client-cloneable models (`templates/_props/` →
   `ReplicatedStorage/Assets/Props` or a new route), the generator pattern (`tools/assets/*_kit.py`, colour-only
   materials through `palette.py`, the testfit strips Ben approves before upload), scale against an R15 body,
   a triangle budget per weapon, one model per family versus a new look per band of tiers (15 × 5 = 75), the
   number of uploads and harvest pastes. Read `docs/ASSET_RESEARCH.md` §2 and §7 and the build-assets skill
   (`.claude/skills/build-assets/`) for how buildings were done.
6. **Decisions for Ben** (options, recommendation, cost; the screen layouts and the model look as ASCII previews),
   **risks**, a **wave split** with owners (including who builds the models and when Ben's strip approval comes).
