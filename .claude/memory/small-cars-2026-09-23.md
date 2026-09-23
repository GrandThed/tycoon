---
name: small-cars-2026-09-23
description: Wave 2d - runtime Model:ScaleTo for cars (no re-upload), lane-hold traffic rule, merge_stages flips winding for mirrored kit nodes
metadata:
  type: project
---

Signed off by Ben 2026-09-23 ("looks good!"). Contract: `docs/INTERFACES.md` "Wave 2d".

- **Resize props at runtime, not in the pipeline.** `vehicles.scale` / `parked.scale` /
  `pedestrians.scale` apply `Model:ScaleTo` in `PropFactory.Spawn` while the Base is PrimaryPart
  (pivot at the ground). No re-merge, re-upload or harvest paste. Scale 1 never calls ScaleTo.
  Boomtown + Metropolis cars are 0.5; walkers stay 1 (Ben accepted them at car height).
- **Dense traffic fuses without spacing.** Cars share a speed per plot, so at 24-32 per plot two
  cars reaching a node together rode one lane overlapped. `Traffic` now holds each lane busy for
  `(length + vehicles.followGap) / speed` after entry; a car takes a free branch or waits a frame.
- **Mirrored kit nodes bake inside out.** `city-kit-industrial/detail-tank` and `city-kit-roads/dumpster`
  (`lid-right`) carry scale [-1,1,1]; Blender's `Mesh.transform` keeps winding, Roblox culls back
  faces, so the camera side vanished. `merge_stages.instance_mesh` flips normals when the
  determinant is negative (41ace24). Check with signed volume (> 0 = outward) after any re-merge.
- Parked bays: `parked.perBay` 2 packed along `parked.bayLength` (7.5 / 6.0) with `parked.gap`;
  `perTier` still counts bays.

**Why:** a fresh session would otherwise re-scale blueprints and re-upload for a size change, or
re-diagnose an inside-out kit piece.

**How to apply:** any "make X bigger/smaller" request on a dressing prop is a config scale first.
See [[living-city-2026-09-23]] and [[assets-direction-2026-09-15]].
