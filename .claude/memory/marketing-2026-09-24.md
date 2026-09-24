M10 icons and thumbnails, decided by Ben 2026-09-23/24. Contract: `docs/INTERFACES.md` "M10 contracts".

- **Icon = era stack** (Windmill → ClockTower → SkyscraperA → LaunchTower rising on one island,
  sky sunrise → space). The first cut failed at 64 px; what fixed it was packing the buildings,
  filling the frame height and a **dark navy outline** per building (a white glow merged the white
  skyscraper and rocket). Judge every icon at 64 px on (24,24,28), not at 512.
- **Store icons = the A set** (full-square sun-ray backgrounds, glossy gold, one colour per item;
  cash tiers pile < bag < chest from one fixed camera). Ben: "love the icons and store".
- **Rendered thumbnails rejected** ("we are not using those thumbs"): thumbnails are real Studio
  screenshots with real avatars, captioned by `tools/marketing/caption.py` from `shots.json`.
  Don't re-propose Blender-rendered thumbnails or walker figures posing as players.
- Font for all marketing text is Titan One (OFL) in `assets/marketing/fonts/`; Luckiest Guy is
  Apache, not OFL. Social caption is "PLAY WITH FRIENDS" — plots are per player, so "build with
  friends" would misstate a mechanic.
- Monuments (SkyscraperA, LaunchTower) look the same at every stage, so they can't sell growth.

**Why:** a fresh session would re-render thumbnails or re-open the icon pick.

**How to apply:** final art under gitignored `assets/marketing/final/`; the scripts in
`tools/marketing/` regenerate it. See [[era-kits-2026-09-16]] and [[audience-reach-2026-09-18]].
