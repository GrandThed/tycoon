# Discovery checklist — Creator Hub metadata

Everything set outside Studio that decides whether Era City Tycoon is shown to players.
Work top to bottom; the order is the order of impact. Tick each box when it is done in
Creator Hub (Experience → Configure). Source links are at the bottom.

Metadata only wins the click. Distribution comes from per-player engagement over 28 days
(see "What ranking rewards"), so the code-side items at the end matter as much as the fields.

## 0. Audience reach gate (blocker — read first)

Roblox decides who can see the experience from the **creator's account**, not from the maturity
label. Verified 2026-09-18 against `create.roblox.com/docs/production/publishing/kids-and-select`.

| Reach | What the owner needs |
|---|---|
| Limited (playtesters, friends, group) | same as 16+ below; never discoverable |
| Public, **16+ and trusted friends** | account in good standing and 2+ days old; age check by **facial age estimation or government ID**; maturity questionnaire |
| Public, **all ages** (under-16 "Kids" and "Select" accounts) | all of the above, plus: verification by facial estimation if the owner is under 18, **government ID if 18+**; 2-step verification on; Roblox Plus/Premium for 2 consecutive months **or** a one-time refundable fee; then an evaluation: **250 unique plays by highly engaged, age-checked 16+ users within 60 days**, or a refundable 50,000 Robux expedited review per game |

- [x] Account reach: "Publicar para todas las edades" (identity, age check and 2-step all done, 2026-09-18).
- [ ] Experience reach: open the experience's Audience Reach page; pay the refundable fee or hold
      Plus/Premium, then satisfy the highly-engaged-players card. Until then the page says "Edades 16+".
- [ ] Audience set to **Público** in Configurar → Configuración (Limitado shows "No disponible" to
      everyone who is not a friend or playtester). The Beta Mode checkbox only exists under Público.
- [ ] Do not leave Beta Mode on while chasing the 250 plays: Beta removes the game from Recommended
      For You, and creators report the highly-engaged counter does not move in Beta. Test under
      Limitado instead, then go Público without Beta.
- [ ] Track progress on the **Audience Reach** dashboard in Creator Hub.

## 1. Icon

- [ ] 512×512 PNG, square, one clear subject (one top-tier landmark building on a saturated sky).
- [ ] Readable at 64 px: no text under a quarter of the icon height, strong silhouette, contrasts with dark tiles.
- [ ] Upload at least a day early; icons wait for moderation.
- [ ] One icon per locale only; leave the localized icons empty unless the art has text.

## 2. Thumbnails (2–5 active so personalization runs)

- [ ] 16:9, 1920×1080, under 3 MB each, up to 10 total.
- [ ] Bottom ~15% kept empty (tile overlay covers it).
- [ ] Five different hooks, not five angles of one scene:
  - [ ] Growth: the same building at stage 1 and stage 5 side by side.
  - [ ] Eras: Village left, Metropolis right, the four era names on top.
  - [ ] Scale: a full Metropolis plot with roads, vehicles and lamps.
  - [ ] Combat: an Expedition fight (after C0 ships).
  - [ ] Social: two avatars on one plot (co-play is a ranking signal).
- [ ] Thumbnail personalization enabled (needs 2–5 thumbnails; Roblox reports +8.5% qualified play-through on average).
- [ ] Re-check Acquisition analytics after two weeks and replace the worst performer.

## 3. Video thumbnail (optional, 3 free uploads per month)

- [ ] 10–20 s of real gameplay: one building growing through every stage.
- [ ] No voice-over, narration, lyrics, external footage, fake mechanics or claims. Roblox catalog music only.
- [ ] Never the only thumbnail; consoles and VR do not show video.

## 4. Name

- [ ] `Era City Tycoon` (optionally one emoji: `Era City Tycoon 🏙️`). Keep it identical everywhere from now on; name changes reset recognition.
- [ ] No repeated words, no more than one decoration, no "Free", "Robux", "Rewards", "Giveaway", "Play now".
- [ ] Fits a phone tile without truncation.

## 5. Description

- [ ] First sentence states the genre. Every keyword appears once, in a real sentence (search is semantic).
- [ ] Draft to paste:

```
Era City Tycoon is a city building tycoon where you grow a village into a futuristic metropolis.
Buy plots, upgrade every building from a shack to a landmark, and unlock four eras: Village,
Boomtown, Metropolis and Orbital Colony. Earn cash while you are offline, rebirth for permanent
bonuses, and team up with friends on Expeditions to fight for rare materials.

Features
• Buildings that grow as you level them
• Idle income and offline earnings
• Four eras with their own look and economy
• Co-op Expeditions with friends
• Works on phone, tablet, PC and console

Updates every week. Like and favorite to support the game!
```

- [ ] Under ~1000 characters. Update notes go at the bottom, never above the first paragraph.
- [ ] Nothing that implies money or rewards, no keyword lists, no keywords the game does not deliver.

## 6. Genre

- [ ] Genre: **Simulation**. Subgenre: **Tycoon**.
- [ ] Set it once; it can only change every three months and Roblox audits it. Charts pick it up after a few days.

## 7. Content maturity questionnaire

- [ ] Completed on publish day. Incomplete or inaccurate answers restrict playability for everyone.
- [ ] Answer the violence question honestly for Expeditions: intensity Mild, frequency **Repeated** (wave combat). That gives a Mild label.
- [ ] The label alone does not open the game to under-16 accounts; §0 does.
- [ ] Re-answer whenever a milestone adds new content types (C0 combat, any chat or trading feature).

## 8. Devices

- [ ] Computer, Phone, Tablet and Console all enabled. VR off.
- [ ] Console enabled only after a gamepad pass on the UI (PLAYTEST has the check).

## 9. Ownership and servers

- [ ] Published under a **group**, not the personal account (store, funds, transferable, group page for links).
- [ ] Max players 6–8 so servers read as full and friends land together.
- [ ] "Friends can join" on. Hub never uses reserved servers (kills the co-play signal); only Expeditions do.
- [ ] Private servers on, free or cheap, so groups of friends can play together.

## 10. Localization

- [ ] Automatic translation on for experience name and description (18 languages).
- [ ] Hand-translate the first sentence of the description for Spanish, Portuguese and Indonesian.

## 11. Social links

- [ ] Roblox group link.
- [ ] YouTube channel (hosts the growth clip; also the main external traffic source).
- [ ] Discord only if you will moderate it; it is hidden from under-13 accounts anyway.

## 12. Publish state and cadence

- [ ] Test under Limitado until the M10 icon and thumbnails exist. Beta Mode is optional and hides the game from Recommended For You; see §0 before using it.
- [ ] After going public: one visible update every 1–2 weeks (Updated sort and search weight recency).
- [ ] Every update: bump the "What's new" line at the bottom of the description, not the top.

## What ranking rewards (code-side items)

Home "Recommended For You" ranks on per-player signals over D1, D2–7 and D8–28: play-through
rate after click, first-play bounce, play days, playtime (capped at 60 min/day), intentional
co-play days, spend days and Robux spent. Analytics → Acquisition → Home Recommendations shows
the game's score on each.

- [ ] First 60 seconds: fast join, first affordable slot visible at spawn (first-play bounce).
- [ ] Daily streak and offline earnings tuned so a second-day visit is worth it (play days beat session length).
- [ ] Party join and join-a-friend for Expeditions shipped (co-play signal) — C0.
- [ ] Like/favorite prompt fired once at the first Advance Era, never on join — M10.
- [ ] Check the Acquisition page two weeks after publish and fix the lowest signal first.

## Penalties to avoid

- Metadata that does not match the game (demoted in search and Home).
- Names, icons or place files that closely resemble an existing game (no longer prioritized).
- Repeated or irrelevant keywords in name or description (stated demotion).
- Monetary language anywhere in the metadata (not prioritized for recommendations).

## Sources

- https://create.roblox.com/docs/discovery
- https://create.roblox.com/docs/production/publishing/experience-genres
- https://create.roblox.com/docs/production/publishing/thumbnails
- https://create.roblox.com/docs/production/publishing/experience-icons
- https://create.roblox.com/docs/production/publishing/publish-games-and-places
- https://create.roblox.com/docs/production/promotion/content-maturity
- https://create.roblox.com/docs/production/localization/automatic-translations
- https://devforum.roblox.com/t/recommended-for-you-algorithm-improvements-that-better-value-long-term-retention/4684575
- https://about.roblox.com/newsroom/2026/06/optimizing-discovery-great-games-reach-millions-players-roblox
- https://devforum.roblox.com/t/get-your-thumbnails-ready-for-thumbnail-personalization/3226599
