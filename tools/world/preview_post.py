#!/usr/bin/env python
"""Second half of the Valley preview (system `py`, Pillow): the mock's distance haze on the raw
renders tools/world/preview.py made, and the A2 | V comparison sheets.

    py tools/world/preview_post.py

Writes, in assets/research/2026-10-01-worldmock/out/: V_<camera>.png, V_collision_<camera>.png,
V6_aerial.png (whichever raw renders exist) and sheetV_<camera>.png, two panels each: the mock's
A2 on the left, the baked Valley on the right.
"""

from __future__ import annotations

import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
MOCK = HERE.parents[1] / "assets" / "research" / "2026-10-01-worldmock"
sys.path.insert(0, str(MOCK))

from wm_common import OUT  # noqa: E402
from wm_post import RAW, finish  # noqa: E402
from wm_post2 import grid  # noqa: E402

CAMERAS = ("aerial", "plot", "hub", "back", "apron", "apron2", "pond")


def main():
    done = []
    for raw in sorted(RAW.glob("V*_*.png")):
        stem = raw.stem
        if stem.endswith("_dist"):
            continue
        head = stem.split("_")[0]
        if head not in ("V", "Vc", "V6"):
            continue
        out = finish(stem)
        if head == "Vc":  # the collision renders, under the name the gate asks for
            target = OUT / f"V_collision_{stem[len('Vc_'):]}.png"
            shutil.move(str(out), str(target))
            out = target
        done.append(out)
        print(f"wrote {out}")
    for camera in CAMERAS:
        if (OUT / f"V_{camera}.png").exists() and (OUT / f"A2_{camera}.png").exists():
            out = grid(f"sheetV_{camera}", [(f"A2_{camera}", "A2  (mock)"), (f"V_{camera}", "V  (baked)")], 2)
            print(f"wrote {out}")
    return 0 if done else 1


if __name__ == "__main__":
    sys.exit(main())
