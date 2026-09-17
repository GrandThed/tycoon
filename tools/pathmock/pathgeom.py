"""Path-ribbon geometry for the Village path look-dev mock (M9 wave 1b follow-up).

Builds the full-ownership Village road network with tools/streetplan.py's own logic, turns every
visible chain (a contiguous run of one street polyline, or a slot spur) into a smooth ribbon and
writes a JSON mesh for tools/pathmock/render.py. Plain math on (x, z) tuples so every function
ports 1:1 to pure Luau.

Usage:  py tools/pathmock/pathgeom.py <out.json> [--grow <slotId>] [--frames N]
"""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import streetplan  # noqa: E402

ERA = "Village"

# Look parameters (would live in CityDressing.json in game).
SAMPLE_STEP = 0.6  # arc-length resample spacing
CAP_STEP = 0.25  # denser spacing inside rounded caps so the tip outline stays round
FILLET_RADIUS_WIDTHS = 2.0  # corner radius = this * road width
FILLET_MIN_DEG = 4.0
ARC_STEP_DEG = 12.0
CR_ALPHA = 0.5  # centripetal Catmull-Rom
MEANDER_TAPER_WIDTHS = 2.0  # meander fades to 0 over this many widths from ends and junctions
EDGE_SCALE = 1.4  # mesh is this much wider than the nominal width; texture alpha 0.5 sits at the nominal edge
CAP_LENGTH = 2.4  # rounded tip length at free ends and growth tips
MIN_LEG_WIDTHS = 1.0  # control legs shorter than this many widths are merged away
FLARE_LENGTH = 3.0  # a joiner widens over this distance before the join
FLARE_GAIN = 0.4  # +40% width at the join point
TIP_FADE = 3.0  # the tip fades over this many fade widths along the path
EXTEND_WIDTHS = 0.45  # a joiner runs this many host widths past the host centreline, capped round
ROUND_END_WIDTHS = 0.8  # a lane dead end that hosts a join runs on this far, capped round
TEXTURE_LENGTH = 8.0  # studs of path per texture repeat (1024 px along u)
FADE_V = 0.265  # texture rows 0..FADE_V (and 1-FADE_V..1) hold the whole alpha fade; see texture.py
COLUMNS = 4
Y_BASE = 0.04
Y_STEP = 0.012  # per layer: main lane 0, side lanes 1, spurs 2


# ---------------------------------------------------------------- small vector helpers


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1])


def add(a, b):
    return (a[0] + b[0], a[1] + b[1])


def mul(a, k):
    return (a[0] * k, a[1] * k)


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1]


def length(a):
    return math.hypot(a[0], a[1])


def norm(a):
    d = length(a)
    return (0.0, 0.0) if d < 1e-9 else (a[0] / d, a[1] / d)


def smoothstep(x):
    x = max(0.0, min(1.0, x))
    return x * x * (3 - 2 * x)


# ---------------------------------------------------------------- 1. control points


def dedupe(points, eps=0.05):
    out = []
    for p in points:
        if not out or length(sub(p, out[-1])) > eps:
            out.append(p)
    return out


def drop_collinear(points):
    if len(points) < 3:
        return points
    out = [points[0]]
    for i in range(1, len(points) - 1):
        d0 = norm(sub(points[i], out[-1]))
        d1 = norm(sub(points[i + 1], points[i]))
        if dot(d0, d1) < 0.9995:
            out.append(points[i])
    out.append(points[-1])
    return out


def merge_short_legs(points, min_leg):
    """A leg shorter than min_leg cannot hold a bend (the ribbon would fold over itself): merge its
    two points into their midpoint, or drop the interior one when the leg touches an end."""
    pts = list(points)
    changed = True
    while changed and len(pts) > 2:
        changed = False
        for i in range(len(pts) - 1):
            if length(sub(pts[i + 1], pts[i])) >= min_leg:
                continue
            if i == 0:
                del pts[1]
            elif i + 1 == len(pts) - 1:
                del pts[i]
            else:
                pts[i : i + 2] = [mul(add(pts[i], pts[i + 1]), 0.5)]
            changed = True
            break
    return pts


def fillet(points, radius):
    """Replace each corner by a circular arc of `radius` (shrunk when a leg is short), sampled every
    ARC_STEP_DEG, so a 90-degree corner becomes a round bend instead of a kink."""
    if len(points) < 3:
        return list(points)
    out = [points[0]]
    for i in range(1, len(points) - 1):
        p0, p1, p2 = out[-1], points[i], points[i + 1]
        d_in, d_out = norm(sub(p1, p0)), norm(sub(p2, p1))
        turn = math.acos(max(-1.0, min(1.0, dot(d_in, d_out))))
        if math.degrees(turn) < FILLET_MIN_DEG:
            out.append(p1)
            continue
        half = math.tan(turn / 2)
        # the leg before may already be shortened by the previous arc
        limit = min(0.95 * length(sub(p1, p0)), 0.48 * length(sub(p2, p1)))
        tangent = min(radius * half, limit)
        r = tangent / half
        a = sub(p1, mul(d_in, tangent))
        side = 1.0 if (d_in[0] * d_out[1] - d_in[1] * d_out[0]) > 0 else -1.0
        n_in = (-d_in[1] * side, d_in[0] * side)
        centre = add(a, mul(n_in, r))
        start = math.atan2(a[1] - centre[1], a[0] - centre[0])
        steps = max(2, math.ceil(math.degrees(turn) / ARC_STEP_DEG))
        for k in range(steps + 1):
            ang = start + side * turn * k / steps
            out.append((centre[0] + r * math.cos(ang), centre[1] + r * math.sin(ang)))
    out.append(points[-1])
    return dedupe(out)


# ---------------------------------------------------------------- 2. centripetal Catmull-Rom


def catmull_rom(points, per_stud=8):
    """Dense polyline through `points` (centripetal CR, Barry-Goldman form); phantom end points
    are mirrored so the curve leaves each end along its first/last leg."""
    if len(points) < 2:
        return list(points)
    pts = [sub(mul(points[0], 2), points[1])] + list(points) + [sub(mul(points[-1], 2), points[-2])]
    out = [points[0]]
    for i in range(1, len(pts) - 2):
        p0, p1, p2, p3 = pts[i - 1], pts[i], pts[i + 1], pts[i + 2]
        t0 = 0.0
        t1 = t0 + max(length(sub(p1, p0)), 1e-4) ** CR_ALPHA
        t2 = t1 + max(length(sub(p2, p1)), 1e-4) ** CR_ALPHA
        t3 = t2 + max(length(sub(p3, p2)), 1e-4) ** CR_ALPHA
        n = max(2, math.ceil(length(sub(p2, p1)) * per_stud))
        for k in range(1, n + 1):
            t = t1 + (t2 - t1) * k / n
            a1 = add(mul(p0, (t1 - t) / (t1 - t0)), mul(p1, (t - t0) / (t1 - t0)))
            a2 = add(mul(p1, (t2 - t) / (t2 - t1)), mul(p2, (t - t1) / (t2 - t1)))
            a3 = add(mul(p2, (t3 - t) / (t3 - t2)), mul(p3, (t - t2) / (t3 - t2)))
            b1 = add(mul(a1, (t2 - t) / (t2 - t0)), mul(a2, (t - t0) / (t2 - t0)))
            b2 = add(mul(a2, (t3 - t) / (t3 - t1)), mul(a3, (t - t1) / (t3 - t1)))
            out.append(add(mul(b1, (t2 - t) / (t2 - t1)), mul(b2, (t - t1) / (t2 - t1))))
    return dedupe(out, 1e-3)


class Curve:
    """Arc-length parameterised dense polyline with optional straight extensions at both ends."""

    def __init__(self, dense, extend_start=0.0, extend_end=0.0):
        if extend_start > 0:
            d = norm(sub(dense[0], dense[min(3, len(dense) - 1)]))
            dense = [add(dense[0], mul(d, extend_start))] + dense
        if extend_end > 0:
            d = norm(sub(dense[-1], dense[max(-4, -len(dense))]))
            dense = dense + [add(dense[-1], mul(d, extend_end))]
        self.p = dense
        self.s = [0.0]
        for i in range(1, len(dense)):
            self.s.append(self.s[-1] + length(sub(dense[i], dense[i - 1])))
        self.total = self.s[-1]

    def locate(self, s):
        s = max(0.0, min(self.total, s))
        lo, hi = 0, len(self.s) - 1
        while hi - lo > 1:
            mid = (lo + hi) // 2
            if self.s[mid] <= s:
                lo = mid
            else:
                hi = mid
        seg = self.s[hi] - self.s[lo]
        t = 0.0 if seg < 1e-9 else (s - self.s[lo]) / seg
        return lo, hi, t

    def point(self, s):
        lo, hi, t = self.locate(s)
        return add(self.p[lo], mul(sub(self.p[hi], self.p[lo]), t))

    def tangent(self, s, h=0.35):
        return norm(sub(self.point(s + h), self.point(s - h)))

    def project(self, q):
        best = (1e18, 0.0)
        for i in range(1, len(self.p)):
            a, b = self.p[i - 1], self.p[i]
            ab = sub(b, a)
            ll = dot(ab, ab)
            t = 0.0 if ll < 1e-12 else max(0.0, min(1.0, dot(sub(q, a), ab) / ll))
            c = add(a, mul(ab, t))
            d = length(sub(q, c))
            if d < best[0]:
                best = (d, self.s[i - 1] + t * math.sqrt(ll))
        return best  # (distance, arc length)


# ---------------------------------------------------------------- 3. meander + width noise


def wave(s, phase, wavelength):
    """Two sines, in [-1, 1]; a pure function of arc length and a per-chain phase."""
    k = 2 * math.pi / wavelength
    return 0.62 * math.sin(k * s + phase) + 0.38 * math.sin(k * 2.13 * s + phase * 1.71 + 0.9)


def meander_taper(s, nodes, taper_len):
    d = min(abs(s - n) for n in nodes)
    return smoothstep(d / taper_len)


# ---------------------------------------------------------------- 4. network -> chains


def build_chains():
    city = json.loads(streetplan.CITY_CONFIG_PATH.read_text(encoding="utf-8"))
    era = streetplan.Era(ERA, city)
    net = streetplan.Network(era)
    visible = set()
    for slot_id in net.spur_ids:
        ids = net.path_stretches(net.junction_nodes.get(slot_id))
        if ids:
            visible.update(ids)
    chains = []
    by_line = {}
    for sid in sorted(visible):
        st = net.stretches[sid]
        if st["segment"] is None:
            chains.append({"kind": "connector", "id": f"conn{sid}", "layer": 1, "points": [st["a"], st["b"]], "phase_key": 97 + sid, "arc0": 0.0})
            continue
        by_line.setdefault(st["polyline"], []).append(st)
    for line, sts in sorted(by_line.items()):
        sts.sort(key=lambda st: (st["segment"], st["t0"]))
        runs = [[sts[0]]]
        for st in sts[1:]:
            if length(sub(st["a"], runs[-1][-1]["b"])) < 0.05:
                runs[-1].append(st)
            else:
                runs.append([st])
        for k, run in enumerate(runs):
            pts = [run[0]["a"]] + [st["b"] for st in run]
            chains.append(
                {
                    "kind": "lane",
                    "id": f"lane{line + 1}" + (f"_{k}" if len(runs) > 1 else ""),
                    "layer": 0 if line == 0 else 1,
                    "points": drop_collinear(dedupe(pts)),
                    "phase_key": line + 1,
                    "arc0": run[0]["arc_start"],
                }
            )
    for slot_id in net.spur_ids:
        spur = era.spurs[slot_id]
        if len(spur["points"]) < 2:
            continue
        chains.append(
            {
                "kind": "spur",
                "id": slot_id,
                "layer": 2,
                "points": drop_collinear(dedupe(spur["points"])),
                "phase_key": sum(map(ord, slot_id)),
                "arc0": 0.0,
            }
        )
    return era, chains


def smooth_curve(points, radius):
    return Curve(catmull_rom(fillet(merge_short_legs(points, MIN_LEG_WIDTHS * radius / FILLET_RADIUS_WIDTHS), radius)))


def prepare(era, chains):
    width = era.width
    radius = FILLET_RADIUS_WIDTHS * width
    meander = era.meander
    for c in chains:
        c["curve"] = smooth_curve(c["points"], radius)
        c["junctions"] = []
        c["join_start"] = c["join_end"] = False
        c["round_start"] = c["round_end"] = False
    reach = width / 2 + 0.1
    for c in chains:
        c["raw"] = Curve(list(c["points"]))  # the unsmoothed centreline, for host tests

    def host_for(c, q):
        """The nearest lower-layer lane whose *unsmoothed* centreline passes within width/2 of q
        (streetplan's attach rule), then the nearest point on its smoothed curve."""
        best = None
        for h in chains:
            if h["kind"] == "spur" or h["layer"] >= c["layer"]:
                continue
            d, _ = h["raw"].project(q)
            if d <= reach and (best is None or d < best[0]):
                best = (d, h["curve"].project(q)[1], h)
        return best

    # Joiners (side lanes onto the main lane, spurs onto any lane): the joining end's control point
    # moves to its projection on the host's smoothed centreline, so the approach bends onto where
    # the host really is after filleting (a lane corner moves inward by up to R(sqrt2 - 1)).
    for c in sorted(chains, key=lambda c: c["layer"]):
        if c["layer"] == 0:
            continue
        for end in ("start", "end"):
            if c["kind"] == "spur" and end == "start":
                continue  # a spur starts at its slot anchor, under the building
            q = c["points"][0] if end == "start" else c["points"][-1]
            hit = host_for(c, q)
            if hit is None:
                continue
            _, s, h = hit
            target = h["curve"].point(s)
            pts = list(c["points"])
            if end == "start":
                pts[0] = target
            else:
                pts[-1] = target
            c["points"] = dedupe(pts)
            c["curve"] = smooth_curve(c["points"], radius)
            c["join_" + end] = True
            h["junctions"].append(s)
            # a join at a lane's dead end: round that end off past the join like a tiny turning circle
            if s < 1.5:
                h["round_start"] = True
            if s > h["curve"].total - 1.5:
                h["round_end"] = True

    amp = meander["amplitude"] if meander else 0.0
    wl = meander["wavelength"] if meander else 18.0
    jitter = meander["widthJitter"] if meander else 0.0
    for c in chains:
        cur = c["curve"]
        total = cur.total
        phase = (c["phase_key"] * 2.399963) % (2 * math.pi)
        c["phase"] = phase
        nodes = [0.0, total] + c["junctions"]
        taper_len = MEANDER_TAPER_WIDTHS * width
        ext_s = EXTEND_WIDTHS * width if c["join_start"] else (ROUND_END_WIDTHS * width if c["round_start"] else 0.0)
        ext_e = EXTEND_WIDTHS * width if c["join_end"] else (ROUND_END_WIDTHS * width if c["round_end"] else 0.0)
        n = max(8, math.ceil(total / 0.1))
        disp = []
        for k in range(n + 1):
            s = total * k / n
            t = cur.tangent(s)
            off = amp * meander_taper(s, nodes, taper_len) * wave(s + c["arc0"], phase, wl)
            disp.append(add(cur.point(s), mul((-t[1], t[0]), off)))
        c["final"] = Curve(dedupe(disp, 1e-3), ext_s, ext_e)
        c["ext"] = (ext_s, ext_e)
        c["width_at"] = lambda s, c=c: width + jitter * wave(s * 1.37 + c["arc0"], c["phase"] + 2.1, wl * 0.8) * 0.5
    return chains


# ---------------------------------------------------------------- 5. ribbon


def sample_positions(s0, s1, caps):
    xs = set()
    n = max(1, math.ceil((s1 - s0) / SAMPLE_STEP))
    for k in range(n + 1):
        xs.add(round(s0 + (s1 - s0) * k / n, 5))
    for a, b in caps:
        m = max(1, math.ceil((b - a) / CAP_STEP))
        for k in range(m + 1):
            xs.add(round(a + (b - a) * k / m, 5))
    return sorted(x for x in xs if s0 - 1e-6 <= x <= s1 + 1e-6)


def ribbon(c, s_from=None, s_to=None):
    """Triangle strip for chain c over arc lengths [s_from, s_to] of its final curve.

    half-width = EDGE_SCALE * width(s)/2 * flare(s) * cap(s); cap is the elliptical profile
    sqrt(1 - (1 - x)^2) over the extension (joined end), CAP_LENGTH (free end) or the growth tip.
    u = arc / TEXTURE_LENGTH + per-chain offset, v = 0 (left edge) .. 1 (right edge)."""
    cur = c["final"]
    total = cur.total
    ext_s, ext_e = c["ext"]
    lo = 0.0 if s_from is None else s_from
    hi = total if s_to is None else s_to
    join_lo_s = ext_s
    join_hi_s = total - ext_e
    start_cap = ext_s if (ext_s > 0 and lo <= 1e-6) else CAP_LENGTH
    end_cap = ext_e if (ext_e > 0 and hi >= total - 1e-6) else CAP_LENGTH
    xs = sample_positions(lo, hi, [(lo, lo + start_cap), (hi - end_cap, hi)])

    verts, uvs, tris = [], [], []
    for s in xs:
        p = cur.point(s)
        t = cur.tangent(s, 0.2)
        nrm = (-t[1], t[0])
        hw = EDGE_SCALE * c["width_at"](s - ext_s) / 2
        flare = 1.0
        if c["join_start"]:
            flare = max(flare, 1 + FLARE_GAIN * smoothstep(1 - (s - join_lo_s) / FLARE_LENGTH))
        if c["join_end"]:
            flare = max(flare, 1 + FLARE_GAIN * smoothstep(1 - (join_hi_s - s) / FLARE_LENGTH))
        cap = 1.0
        x0 = (s - lo) / start_cap
        if x0 < 1:
            cap = min(cap, math.sqrt(max(0.0, 1 - (1 - x0) ** 2)))
        x1 = (hi - s) / end_cap
        if x1 < 1:
            cap = min(cap, math.sqrt(max(0.0, 1 - (1 - x1) ** 2)))
        h = hw * flare * max(cap, 0.01)
        # Four columns: the texture's fade band (v 0..FADE_V) is pinned to a constant world width
        # inside each edge, so flares keep the same soft edge and a narrowing cap fades out
        # instead of squeezing the band into a hard outline.
        fade = FADE_V * 2 * hw
        # k < 1 within one fade width of the outline *or of the tip*: the inner columns slide to the
        # centreline and their v slides into the fade band, so the whole cross-section turns
        # transparent toward the tip instead of ending on a crisp outline.
        k = min(1.0, h / fade, (s - lo) / (TIP_FADE * fade), (hi - s) / (TIP_FADE * fade))
        inner = max(0.0, h - fade) * k
        u = s / TEXTURE_LENGTH + c["u_offset"]
        for offset, v in ((h, 0.0), (inner, FADE_V * k), (-inner, 1 - FADE_V * k), (-h, 1.0)):
            verts.append(add(p, mul(nrm, offset)))
            uvs.append((u, v))
    for i in range(len(xs) - 1):
        for j in range(COLUMNS - 1):
            l0, r0 = COLUMNS * i + j, COLUMNS * i + j + 1
            l1, r1 = l0 + COLUMNS, r0 + COLUMNS
            tris.append((l0, l1, r0))
            tris.append((r0, l1, r1))
    y = Y_BASE + Y_STEP * c["layer"]
    return {
        "name": c["id"],
        "kind": c["kind"],
        "layer": c["layer"],
        "verts": [(round(v[0], 4), y, round(v[1], 4)) for v in verts],
        "uvs": [(round(a, 5), round(b, 5)) for a, b in uvs],
        "tris": tris,
        "length": round(total, 2),
    }


def main():
    out = Path(sys.argv[1])
    grow = sys.argv[sys.argv.index("--grow") + 1] if "--grow" in sys.argv else None
    frames = int(sys.argv[sys.argv.index("--frames") + 1]) if "--frames" in sys.argv else 5
    era, chains = build_chains()
    prepare(era, chains)
    for c in chains:
        c["u_offset"] = (c["phase_key"] * 0.618034) % 1.0
    meshes = [ribbon(c) for c in chains]
    data = {
        "era": ERA,
        "textureLength": TEXTURE_LENGTH,
        "meshes": meshes,
        "chains": [
            {
                "id": c["id"],
                "kind": c["kind"],
                "layer": c["layer"],
                "length": round(c["final"].total, 2),
                "joinStart": c["join_start"],
                "joinEnd": c["join_end"],
                "junctions": [round(s, 2) for s in c["junctions"]],
                "controls": [(round(p[0], 2), round(p[1], 2)) for p in c["points"]],
            }
            for c in chains
        ],
        "slots": [{"id": s["id"], "position": s["position"], "rotation": s["rotation"]} for s in era.slots],
    }
    if grow:
        c = next(c for c in chains if c["id"] == grow)
        total = c["final"].total
        grown = []
        for k in range(1, frames + 1):
            g = total * k / frames
            m = ribbon(c, s_from=total - g, s_to=total)
            m["grown"] = round(g, 2)
            grown.append(m)
        data["growth"] = {"slot": grow, "frames": grown}
    folds = {}
    for m in meshes + (data.get("growth", {}).get("frames", [])):
        v = m["verts"]
        n = sum(1 for a, b, cc in m["tris"] if (v[b][0] - v[a][0]) * (v[cc][2] - v[a][2]) - (v[b][2] - v[a][2]) * (v[cc][0] - v[a][0]) > 1e-6)
        if n:
            folds[m["name"]] = n
    print("folded triangles:", folds or "none")
    longest = max(meshes, key=lambda m: len(m["tris"]))
    data["stats"] = {
        "triangles": sum(len(m["tris"]) for m in meshes),
        "vertices": sum(len(m["verts"]) for m in meshes),
        "meshes": len(meshes),
        "longest": {"name": longest["name"], "tris": len(longest["tris"]), "length": longest["length"]},
    }
    out.write_text(json.dumps(data), encoding="utf-8")
    print(json.dumps(data["stats"]))
    for ch in data["chains"]:
        print(ch["id"], ch["kind"], ch["layer"], ch["length"], ch["joinStart"], ch["joinEnd"], ch["junctions"])


if __name__ == "__main__":
    main()
