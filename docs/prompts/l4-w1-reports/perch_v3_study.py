"""Scratch (L4 study, Part A): run tools/check_levels.py's gates on a VARIANT of ForestRoad.json, in
memory only. Nothing in the repo is written. Variant V1 moves the lookout ledge, its chest and its sign
west of the cave mouth's west wall (CaveWallMouthW), so the wall stands between the ledge and every
region cell, and drops LookoutSignPad (block and region cell).

    py -3.12 perch_variant.py <repo> [V0|V1]
"""
import copy
import io
import sys
from contextlib import redirect_stdout

repo = sys.argv[1]
which = sys.argv[2] if len(sys.argv) > 2 else "V1"
sys.path.insert(0, repo + "/tools")
import check_levels as cl  # noqa: E402

sr = cl.sr
real = sr.load_level_layout


def variant(layout):
    lay = copy.deepcopy(layout)
    if which == "V0":
        return lay
    blocks = []
    for b in lay["blocks"]:
        if b["name"] == "LookoutSignPad":
            continue
        if b["name"] == "LookoutLedge":
            b = dict(b, x=-446, y=11, z=-33, sx=24, sy=30, sz=14)
        blocks.append(b)
    lay["blocks"] = blocks
    for s in lay["secrets"]:
        if s["id"] == "lookout":
            s.update(x=-446, y=28, z=-33)
            s["sign"] = dict(s["sign"], x=-447, y=0, z=-2)
    for r in lay["regions"]:
        r["cells"] = [c for c in r["cells"] if c["id"] != "LookoutSignPad"]
    return lay


def patched(name, below):
    out = real(name, below)
    return variant(out) if name == "ForestRoad" else out


sr.load_level_layout = patched
buf = io.StringIO()
sys.argv = ["check_levels.py", "--no-plan"]
try:
    with redirect_stdout(buf):
        cl.main()
except SystemExit:
    pass
text = buf.getvalue()
for line in text.splitlines():
    if "FAIL" in line or "sniper" in line.lower() or "high ground" in line or "lookout" in line.lower():
        print(line[:700])
