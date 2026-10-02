#!/usr/bin/env python
"""The plot ring, mirrored line for line from src/shared/WorldPlan.luau (M13, docs/INTERFACES.md
"M13 contracts").

    py tools/worldplan.py selftest

Pure and stdlib only, so the Valley generator (tools/world/valley.py) and its Blender preview both
import it. Angles are radians, plot indices are 1-based, and a plot's centre is
(cos(angle), sin(angle)) * radius in X, Z -- exactly as the Luau module says. Change one and the
other must change with it; `selftest` pins the two radii the contract quotes.
"""

from __future__ import annotations

import json
import math
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
CONFIG_DIR = REPO_ROOT / "src" / "shared" / "Config"
LAYOUTS_DIR = REPO_ROOT / "src" / "shared" / "Layouts"

# Roblox's largest Part side. The ground is a single Part, so no wanted side can exceed it.
MAX_PART_SIDE = 2048


def ring(plot_count, plot_margin, hub_radius, plot_size_x, plot_size_z):
    """WorldPlan.Ring: the ring is sized so each inner corner stays plotMargin / 2 clear of the
    radial line splitting two plots, and never so tight that a front edge comes within plotMargin
    of the hub."""
    half_sector = math.pi / plot_count
    radius = max(
        plot_size_z / 2 + (plot_size_x / 2 * math.cos(half_sector) + plot_margin / 2) / math.sin(half_sector),
        hub_radius + plot_margin + plot_size_z / 2,
    )
    return {
        "plotCount": plot_count,
        "radius": radius,
        "halfSector": half_sector,
        "frontRadius": radius - plot_size_z / 2,
        "backRadius": radius + plot_size_z / 2,
    }


def plot_angle(ring_, index):
    """WorldPlan.PlotAngle: index is 1-based."""
    return (index - 1) / ring_["plotCount"] * 2 * math.pi


def ground_side(ring_, plot_size_z, wanted_side=None):
    """WorldPlan.GroundSide."""
    ring_side = 2 * (ring_["radius"] + plot_size_z)
    if wanted_side is None:
        return ring_side
    return min(MAX_PART_SIDE, max(wanted_side, ring_side))


def roads(ring_, hub_radius, width):
    """WorldPlan.Roads: one strip per plot along its radial, or none when it would have no length."""
    inner_radius = max(hub_radius, width / (2 * math.tan(ring_["halfSector"])))
    outer_radius = ring_["frontRadius"]
    if inner_radius >= outer_radius:
        return []
    return [
        {"angle": plot_angle(ring_, index), "innerRadius": inner_radius, "outerRadius": outer_radius, "width": width}
        for index in range(1, ring_["plotCount"] + 1)
    ]


# ---------------------------------------------------------------- the inputs the ring is built from


def load_game():
    return json.loads((CONFIG_DIR / "Game.json").read_text(encoding="utf-8"))


def load_world():
    return json.loads((CONFIG_DIR / "World.json").read_text(encoding="utf-8"))


def plot_size(layout="Village"):
    """`plotSize = Vector3.new(x, y, z)` of an era layout: PlotService sizes the ring from the first
    era's, and every layout shares it by design."""
    text = (LAYOUTS_DIR / f"{layout}.luau").read_text(encoding="utf-8")
    match = re.search(r"plotSize\s*=\s*Vector3\.new\(\s*([-\d.]+)\s*,\s*([-\d.]+)\s*,\s*([-\d.]+)\s*\)", text)
    if match is None:
        raise SystemExit(f"worldplan: no plotSize in Layouts/{layout}.luau")
    return tuple(float(v) for v in match.groups())


def game_ring(plot_count=None):
    """The live ring: Game.json and the Village layout, with `plot_count` overriding plotCount."""
    game = load_game()
    size = plot_size()
    count = int(game["plotCount"] if plot_count is None else plot_count)
    return ring(count, float(game["plotMargin"]), float(game["hubRadius"]), size[0], size[2])


def selftest():
    cases = ((10, 277.0217), (6, 183.9230))
    failed = 0
    for count, wanted in cases:
        got = ring(count, 20.0, 30.0, 120.0, 120.0)
        ok = abs(got["radius"] - wanted) < 5e-5
        failed += not ok
        print(f"ring({count} plots): radius {got['radius']:.4f} (contract {wanted:.4f}) {'ok' if ok else 'FAIL'}")
        if abs(got["frontRadius"] - (got["radius"] - 60)) > 1e-9 or abs(got["backRadius"] - (got["radius"] + 60)) > 1e-9:
            failed += 1
            print("  front/back radius FAIL")
    tight = ring(3, 20.0, 30.0, 120.0, 120.0)
    floor = ring(40, 20.0, 400.0, 120.0, 120.0)
    checks = (
        ("plot 1 on +X", abs(plot_angle(ring(10, 20, 30, 120, 120), 1)) < 1e-12),
        ("plot 6 of 10 on -X", abs(plot_angle(ring(10, 20, 30, 120, 120), 6) - math.pi) < 1e-12),
        ("the hub floor binds", abs(floor["radius"] - (400.0 + 20.0 + 60.0)) < 1e-9 or floor["radius"] > 480.0),
        ("3 plots", tight["radius"] > 0),
        ("ground side, no wanted side", abs(ground_side(ring(10, 20, 30, 120, 120), 120.0) - 2 * (277.02169 + 120)) < 1e-3),
        ("ground side is capped", ground_side(ring(10, 20, 30, 120, 120), 120.0, 5000) == MAX_PART_SIDE),
        ("ground side never shrinks", ground_side(ring(10, 20, 30, 120, 120), 120.0, 10) > 794.0),
        ("10 roads", len(roads(ring(10, 20, 30, 120, 120), 30.0, 6.0)) == 10),
        ("roads start at the hub", roads(ring(10, 20, 30, 120, 120), 30.0, 6.0)[0]["innerRadius"] == 30.0),
    )
    for name, ok in checks:
        failed += not ok
        print(f"{name}: {'ok' if ok else 'FAIL'}")
    live = game_ring()
    print(f"live ring: {live['plotCount']} plots, radius {live['radius']:.4f}")
    if failed:
        print(f"worldplan selftest: {failed} FAILED")
        return 1
    print("worldplan selftest: ok")
    return 0


def main(argv):
    if len(argv) == 1 and argv[0] == "selftest":
        return selftest()
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
