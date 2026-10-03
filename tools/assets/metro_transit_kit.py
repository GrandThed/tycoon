"""Metropolis bus-line pieces (a city-changer candidate for `busStop`, M12 wave 3.1), generated as a
Kenney-style kit: a modern bus shelter for the pavement and a city bus for the traffic.

Runs inside Blender (headless):

    blender -b -P tools/assets/metro_transit_kit.py [-- --out <dir>] [--only name,name]

Writes one GLB per piece into assets/kenney3d/metro-transit-kit/Models/GLB format/, the folder
convention every Kenney kit uses, so tools/testfit/testfit.py and tools/assets/merge_stages.py
discover the kit with no registration step. assets/ is gitignored, so this script is the committed
artifact and the GLBs regenerate from it. The mesh helpers, the palette and the two Studio rules
come from oldtown_kit.py.

Why a custom kit: city-kit-commercial and city-kit-roads have no shelter and car-kit has no bus,
and Boomtown's bus and shelter (boomtown-street-kit) are Boomtown's: each kit belongs to one era.
The bus line's colour is the kit's mint, worn by the shelter's canopy and the bus's belt, so the
line reads as one thing beside the metro's blue kiosks.

**Units: 1 glTF unit = 1 stud**, blueprints at `"scale": 1.0`. The two pieces follow two size
conventions:
- `bus-shelter` stands at full size at the lot line, in a gap one narrow lot wide, like the other
  street props. Its rules are oldtown_kit's MIN_GAP (0.05) and MIN_MEMBER (0.1).
- `city-bus` is built at blueprint size like the Metropolis VehicleA-D (car-kit at blueprint scale
  1.8: 2.7 wide, 2.3 to 3.0 tall, 4.95 to 5.85 long), because the client shrinks every vehicle by
  `vehicles.scale` 0.5. So its rules are doubled here, BUS_GAP 0.1 and BUS_MEMBER 0.2, which come
  out at 0.05 and 0.1 on the street. It is about twice a car's length and a stud taller.

Front -Z and origin at bottom-centre for both. The shelter's open side faces -Z, the kerb. The
bus's doors are on +X, its right-hand side, because the traffic keeps right.
"""

from __future__ import annotations

import argparse
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from garden_kit import REPO_ROOT, Part, build_object, export  # noqa: E402
from oldtown_kit import (  # noqa: E402
    BLUE_PALE,
    CREAM,
    DARK,
    GLASS,
    GREY,
    IRON,
    MIN_GAP,
    MIN_MEMBER,
    MINT,
    MINT_DARK,
    PALE,
    RED,
    SLATE,
    STONE,
    STONE_LIGHT,
    TAN,
    WHITE,
    YELLOW,
    block,
    on_wall,
    signed_volume,
)
from village_extras_kit import face_out  # noqa: E402

import bpy  # noqa: E402

KIT = "metro-transit-kit"
DEFAULT_OUT = os.path.join(REPO_ROOT, "assets", "kenney3d", KIT, "Models", "GLB format")

Rgb = tuple[int, int, int]

BUS_SCALE = 0.5  # CityDressing.json eras.Metropolis.vehicles.scale, applied by the client
BUS_GAP = MIN_GAP / BUS_SCALE
BUS_MEMBER = MIN_MEMBER / BUS_SCALE


# --- the shelter ---------------------------------------------------------------------------------


def make_bus_shelter() -> Part:
    """A modern bus shelter, 3.0 studs long, 1.36 deep and 2.95 tall at its route sign, open toward
    -Z (the street): a glass back wall and two half-depth glass end screens in slim steel frames, a
    flat canopy in the line's mint with a white fascia, a bench along the back, and a route flag
    standing on the canopy's -X front corner, across the pavement as a bus-stop flag hangs (a mint
    band over yellow and red route squares on white, both faces, no lettering). The +X end screen
    carries an advert panel of colour blocks on its outer face. It is 3.0 long because it stands in
    a gap one narrow lot wide (4.1) with 0.55 clear each side (lead, 2026-10-03); nothing reaches
    past the canopy's ends."""
    p = Part("bus-shelter")
    m = MIN_MEMBER
    half = 1.5  # the canopy's ends: the shelter's whole length
    hx, zb, zf = 1.3, 0.5, -0.15  # frame half-length, back wall line, end screens' front
    top = 2.45
    # steel posts: three along the back, one at the front of each end screen
    for x in (-hx, 0.0, hx):
        block(p, x - 0.06, x + 0.06, 0.0, top, zb - 0.06, zb + 0.06, GREY, skip=("bottom", "top"))
    for x in (-hx, hx):
        block(p, x - 0.06, x + 0.06, 0.0, top, zf - 0.06, zf + 0.06, GREY, skip=("bottom", "top"))
    # glass: the back wall in two panes between the posts, and the end screens; a steel rail low on
    # the back wall
    for x0, x1 in ((-hx + 0.06, -0.06), (0.06, hx - 0.06)):
        block(p, x0, x1, 0.12, top, zb - m / 2, zb + m / 2, BLUE_PALE, skip=("bottom", "top"))
        block(p, x0, x1, 0.02, 0.12, zb - 0.06, zb + 0.06, GREY, skip=("bottom",))
    for x in (-hx, hx):
        block(p, x - m / 2, x + m / 2, 0.12, top, zf + 0.06, zb - 0.06, BLUE_PALE, skip=("bottom", "top"))
    # the advert on the +X screen's outer face: a cream ground, a red block and a tan band
    side = ("x", hx + m / 2, 1)
    on_wall(p, side, zf + 0.12, zb - 0.12, 0.4, 2.2, MIN_GAP, CREAM)
    on_wall(p, side, zf + 0.22, zb - 0.22, 1.2, 1.95, 2 * MIN_GAP, RED)
    on_wall(p, side, zf + 0.22, zb - 0.22, 0.6, 0.85, 2 * MIN_GAP, TAN)
    assert hx + m / 2 + 2 * MIN_GAP <= half, "the advert would reach past the canopy's end"
    # the canopy: a mint slab over the whole shelter, reaching toward the street, white fascia
    canopy = top + 0.15
    block(p, -half, half, top, canopy, -0.68, 0.68, WHITE, skip=(), top=MINT_DARK, bottom=STONE_LIGHT)
    # bench along the back on two legs
    block(p, -0.95, 0.7, 0.42, 0.52, 0.12, 0.42, STONE, top=STONE_LIGHT)
    for x in (-0.8, 0.55):
        block(p, x - 0.05, x + 0.05, 0.0, 0.42, 0.22, 0.32, IRON, skip=("bottom", "top"))
    # the route flag on the canopy, over the -X front post: a white head with a mint band and two
    # route squares on each face
    fx = -hx
    block(p, fx - 0.07, fx + 0.07, canopy, 2.95, -0.64, -0.16, WHITE, top=MINT_DARK)
    assert fx - 0.07 - MIN_GAP >= -half, "the flag would reach past the canopy's end"
    for facing in (-1, 1):
        wall = ("x", fx + facing * 0.07, facing)
        on_wall(p, wall, -0.61, -0.19, 2.81, 2.93, MIN_GAP, MINT)
        for z0, colour in ((-0.57, YELLOW), (-0.36, RED)):
            on_wall(p, wall, z0, z0 + 0.13, 2.64, 2.77, MIN_GAP, colour)
    return p


# --- the bus ---------------------------------------------------------------------------------------


def chamfered(hx: float, z0: float, z1: float, cf: float, cb: float):
    """A bus's plan: a rectangle with its four corners cut, `cf` at the front (-Z), `cb` at the back,
    counter-clockwise seen from above."""
    return [(-hx + cf, z0), (hx - cf, z0), (hx, z0 + cf), (hx, z1 - cb), (hx - cb, z1), (-hx + cb, z1),
            (-hx, z1 - cb), (-hx, z0 + cf)]


def bands(p: Part, outline, layers, top: Rgb) -> None:
    """Stacked colour bands of one vertical prism over a convex outline [(x, z)]: `layers` lists
    (y0, y1, colour) bottom to top, touching, so one band's side faces continue the next and no face
    lies over another; only the top is closed (a vehicle body's underside is never seen)."""
    cx = sum(x for x, _ in outline) / len(outline)
    cz = sum(z for _, z in outline) / len(outline)
    n = len(outline)
    for y0, y1, colour in layers:
        for i in range(n):
            (xa, za), (xb, zb) = outline[i], outline[(i + 1) % n]
            face_out(p, [(xa, y0, za), (xb, y0, zb), (xb, y1, zb), (xa, y1, za)], colour,
                     ((xa + xb) / 2 - cx, 0.0, (za + zb) / 2 - cz))
    face_out(p, [(x, layers[-1][1], z) for x, z in outline], top, (0.0, 1.0, 0.0))


def make_city_bus() -> Part:
    """A modern low-floor city bus at blueprint size, front -Z: 2.9 studs wide, 10.6 long and 3.7
    tall at its roof pod, so 1.45 x 5.3 x 1.85 on the street, twice a car's length. White body, a
    mint belt and skirt, a dark glass band all round with the windscreen deeper still, a destination
    display in amber on dark, headlights, dark bumpers, two doors on the right (+X), four wheels and
    an air-conditioning pod on the roof. No brands or lettering."""
    p = Part("city-bus")
    hx, z0, z1 = 1.45, -5.3, 5.3
    floor, roof = 0.45, 3.35
    plan = chamfered(hx, z0, z1, 0.45, 0.3)
    layers = [
        (floor, 0.75, MINT_DARK),
        (0.75, 1.25, WHITE),
        (1.25, 1.5, MINT),
        (1.5, 1.7, WHITE),
        (1.7, 2.8, SLATE),
        (2.8, roof, WHITE),
    ]
    assert all(y1 - y0 >= BUS_MEMBER - 1e-9 for y0, y1, _ in layers), "a livery band would shimmer on the street"
    bands(p, plan, layers, PALE)
    g = BUS_GAP
    front = ("z", z0, -1)
    back = ("z", z1, 1)
    kerb = ("x", hx, 1)
    # windscreen deeper than the side glass, the destination display over it, lamps and bumpers
    on_wall(p, front, -hx + 0.5, hx - 0.5, 1.05, 2.8, g, DARK, edge=SLATE)
    on_wall(p, front, -0.75, 0.75, 2.86, 3.22, g, DARK, edge=SLATE)
    on_wall(p, front, -0.6, 0.6, 2.94, 3.14, 2 * g, YELLOW)
    for sx in (-1, 1):
        x0, x1 = sorted((sx * 0.62, sx * 0.92))
        on_wall(p, front, x0, x1, 0.7, 0.92, g, CREAM)
    on_wall(p, front, -hx + 0.45, hx - 0.45, floor, 0.65, g, IRON)
    on_wall(p, back, -hx + 0.3, hx - 0.3, floor, 0.65, g, IRON)
    for sx in (-1, 1):
        x0, x1 = sorted((sx * 0.7, sx * 1.0))
        on_wall(p, back, x0, x1, 0.7, 0.92, g, RED)
    # two doors on the kerb side: dark glass leaves in a slate frame, from the floor to the roof band
    for zc in (-4.0, 0.2):
        on_wall(p, kerb, zc - 0.55, zc + 0.55, floor + 0.05, 2.8, g, DARK, edge=SLATE)
    # wheels under the body, set BUS_GAP and more in from its sides; a dark plinth between them
    for z in (-3.35, 3.1):
        for sx in (-1, 1):
            x0, x1 = sorted((sx * 0.95, sx * (hx - 0.15)))
            block(p, x0, x1, 0.0, 0.95, z - 0.48, z + 0.48, IRON, skip=("bottom", "top"))
    block(p, -0.9, 0.9, 0.18, floor, -4.6, 4.6, DARK, skip=("bottom", "top"))
    # roof pod
    block(p, -0.85, 0.85, roof, roof + 0.35, -1.6, 1.4, STONE, top=GLASS)
    return p


PIECES = {
    "bus-shelter": make_bus_shelter,
    "city-bus": make_city_bus,
}


def generate(out_dir: str, only: set[str] | None) -> int:
    os.makedirs(out_dir, exist_ok=True)
    total = 0
    for name, make in PIECES.items():
        if only and name not in only:
            continue
        bpy.ops.wm.read_factory_settings(use_empty=True)
        part = make()
        assert part.name == name, f"{name}: Part is named {part.name!r}"
        export(build_object(part, {}), out_dir)
        total += part.tris
        lo, hi = part.bounds()
        print(
            f"[{KIT}] {name}.glb: {part.tris} tris, "
            f"{hi[0] - lo[0]:.2f} x {hi[1] - lo[1]:.2f} x {hi[2] - lo[2]:.2f} studs, "
            f"x[{lo[0]:.2f}, {hi[0]:.2f}] y[{lo[1]:.2f}, {hi[1]:.2f}] z[{lo[2]:.2f}, {hi[2]:.2f}], "
            f"volume {signed_volume(part):.2f}",
            flush=True,
        )
    print(f"[{KIT}] {total} tris total -> {os.path.relpath(out_dir, REPO_ROOT)}", flush=True)
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Generate the metro-transit-kit GLBs.")
    parser.add_argument("--out", default=DEFAULT_OUT, help="target Models/GLB format directory")
    parser.add_argument("--only", default="", help="comma list of pieces to build (default: all)")
    args = parser.parse_args(argv)
    only = {name for name in args.only.split(",") if name} or None
    return generate(args.out, only)


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    sys.exit(main(argv))
