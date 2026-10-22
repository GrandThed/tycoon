# L4 W1b — lead's routing

- **luau-engineer A owns `VitalsService.luau` for this wave** (§6 named no owner): its `member.bot` / nil-`player`
  reads at :885, :903 (from the ui report), plus the server side of the `feel` / `feedback` keys the client stopped
  reading.
- **Designer, on top of the luau-a, luau-b and ui relays:** `Sounds.json` joins the designer's files for this wave; its
  15 keys no code plays any more go (`swing`, `finisher`, `bowFire`, `laser`, `gunFire`, `bowDraw`, `abilityCast`,
  `enemyHit`, `enemyDeath`, `playerHit`, `playerDown`, `partyRally`, `partyWarcry`, `lowHp`, `waveClear`), after a grep
  of `src/` and `tools/` (`upload_audio.py`, `audio_map.json`) confirms no reader. `Combat.json` `camera.touchAimAssistDegrees`
  and the `feel` / `feedback` keys A lists go too.
- **ui deviation accepted:** the low-HP vignette is removed (its only caller was C1 `boot`; it never showed in a run).
