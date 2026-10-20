# L3 Wave 1 brief — tiers per weapon, and the Armory screen in grey (for the contract drafter)

You draft the contract for L3 Wave 1 of a Roblox project. Work in `C:\Users\benja\Desktop\tycoon-p5`, branch
`l3-armory`. **Write no code.** Your output is one file, `docs/prompts/l3-w1-contract.md`, in the shape of
`docs/prompts/l2-w1-contract.md` (read it first for form): "What today's code gives us (checked)", numbered rulings
**L3-n**, owners with disjoint files, Studio levers, balance, risks, what needs Ben. Every claim about the code with
file:line, checked by you against the code (the study reports were right before; still check). LF line endings
(`sed -i 's/\r$//'`). Do not commit. Kill only your own PIDs. Tools: `py`; `export PATH="$HOME/.rokit/bin:$PATH"`.

## Read

- `docs/MISSIONS_DESIGN.md` §10 (with the 2026-10-20 restatement), §11, §24 (Ben's L3 decisions: they win over any
  study wherever the two differ).
- `docs/prompts/l3-study-report-systems.md` (all of it) and `docs/prompts/l3-study-report-screen.md` §1, §3, §6, §8.
- `CLAUDE.md` (code rules), `docs/INTERFACES.md` only in slices (grep `^# `: C0 for the Armory, P5 for the tier choke
  point, the L2 W1–W3 headings and the contract files they point to).

## What Wave 1 delivers (playable alone in Studio)

Per-weapon tiers on the ladder of 20 with Ben's windows, the upgrade loop paid with Forest drops, the saved loadout,
stars saved, profile v8 with the conversion, and **the new Armory screen in grey in both places** (the dungeon lobby
and the city hub). No models: the stage shows a placeholder. Ben's test: boot `proving.rbxl` into the lobby, open the
Armory, clear Forest Road on Normal, buy T2 for both starters, feel it on the next run; see the same screen in the hub.

## Lead's rulings to write into the contract (do not re-open; flag a real conflict with the code)

1. **The ladder:** T1 = today's 2/2 (×1.5 of the range numbers), then ×1.65 per tier (report §2.1). HP ladder pinned so
   MaxHp(T1,T1) = 155, (T3,T3) = 230, (T5,T5) = 380, melee keeping the larger share. The range keeps damage scale 1 and
   pins its own 130 HP. Every number lives in `Config/Armory.json`, never in code.
2. **Windows as drawn** (MISSIONS_DESIGN §24, report §2.3) as data; `Armory.TierOf` clamps to the window, so a later
   window change never strands a profile. Five bands of four, one per level; only the Forest band (1–4, Timber) is paid
   by anything in L3. **A band's top tier needs that level's Hard star.** A weapon whose window starts mid-band pays only
   from its start.
3. **Costs:** Timber 100 / 250 / 500 for T2 / T3 / T4 (by position in the band; later bands are placeholders in the same
   shape). **No city income gate** (`unlockRate` no longer read).
4. **Forest remap:** recommended tiers 1 / 3 / 5; Hard's `hpScale` re-measured so Hard at T3 keeps today's clock;
   Brutal unchanged (it waits for Castle gear). Hard rewards: materials and Valor ×2.5, cash ×2. **The first Hard clear
   gives the Hard star (the trophy, opening T4 for Forest weapons) and the Warhammer at T3.** Brutal's first clear gives
   25 Valor (its map mark waits for L4).
5. **Profile v8, add-only:** `combat.tiers`, `combat.loadout`, `combat.stars` (report §4.3); `gear` frozen;
   `Migrations[7]` refunds Timber for every slot tier bought in `gear` at frozen legacy prices and starts the starters at
   their window start (lead ruling told to Ben). Stars leave session memory.
6. **The saved loadout** changes in the lobby and the hub, never inside a live fight; `AddPlayer` reads it; unknown or
   unowned falls back to the slot's starter, an unknown style to the family's default.
7. **Remotes:** `RequestUpgradeWeapon(family)` in both places, `RequestSetFamily` in the hub too; validated (type,
   owned, next tier inside the window, the band top's Hard star, materials) and rate-limited. The client sends intents,
   never amounts or tiers.
8. **The screen (Ben: layout A "Showcase", full-ladder track with the window lit):** one shared module set under
   `src/client/UI` with names new to `src/combat/client/UI`, mapped as explicit children in `combat.project.json`
   (report B §1); the shelf of 15 (owned; dark cards for unowned with a "found" hint, so every non-starter family gets a
   `found` entry); next tier "T5: 45 → 58 dmg · +HP", its cost and the level that drops it; styles A/B; Equip; Upgrade;
   the Abilities tab moved in. Placeholder stage until models (family name large, element chip). Opens on K, gamepad Y
   and the HUD button in the lobby; K and the bottom-bar Armory in the hub. The client colours buttons from one pure
   shared function and never decides. Fits 682 × 313 design px (a 640 × 360 phone) and portrait 375 × 667. Gamepad A
   is sunk while it is open.
9. **Hub:** `ArmoryService` swaps slot-tier buying for the upgrade and equip handlers (Ascension stays, unreachable);
   `EconomyService.copyCombatProfile` carries the new maps; the hub `ArmoryPanel` is retired. If the hub makes the wave
   too big for one ui-engineer, propose a split (two ui-engineers with disjoint files, or the hub screen moved to
   Wave 2) and say why.
10. **Carried into W1:** `check_levels` `ownedFamilies` counts every family source, the Hard-clear Warhammer included;
    the sniper reach follows the longest ownable ranged family; R8 sniper gates also rate bow T4 with sword T1; every
    mirror in report §2.5 moves in the same commit as what it mirrors.
11. **Levers (Studio only, both entry points, inert in the live game):** Timber in the lobby, set a family's tier, grant
    the Forest Hard star, reset the Armory; G steps T1 / T3 / T5; `provingGear` becomes T1. Keys must be free in both
    places (check the taken lists).
12. **Not in W1:** models, the ViewportFrame stage, weapons in hand, attributes for other players, shelf icons
    (Wave 2, after Ben approves the kit strips and pastes one harvest).

## Owners

`luau-engineer` (server and shared, maybe split A/B if the files allow), `ui-engineer` (client), `economy-designer`
(`Config/*.json`, `Layouts/Levels/*.json`, every simulator and gate, `docs/BALANCE.md`), the lead (remotes,
`Main.server.luau` wiring in both places, project files). Disjoint files per agent; list every file with its owner, and
the "for the other owner" hand-offs. Respect the compile gate (`py tools/check_compile.py`, 180 top-level locals): new
behaviour goes in new modules where a file is near the limit (WeaponService is ~3,000 lines; FeedbackController 162,
InputController 158).

End your reply with a ten-line summary, the rulings count, and anything you think needs Ben.
