"""The Valley's ground: the ring, the river, the roads, the flat basin overlay and the terrain
outside the wall (M13 wave 2). Props (trees, bridges, water, aprons...) are in valleyprops.py.

Map frame throughout (see wgeom.py): x, y on the ground, h = studs above the GROUND TOP. Plot k
here is 0-based and sits at map angle -k * step, which is Roblox plot k + 1 at angle +k * step
(Roblox Z = -y). The formulas are the mock's (assets/research/2026-10-01-worldmock/wm_land.py and
wm_valley2.py), changed where the contract says the game differs: the walkable basin is flat, the
river is colour plus a water sheet, and nothing reaches past the terrain's outer radius.
"""

from __future__ import annotations

import math
import random

import wgeom as G
from wgeom import lin, mix, polar, smoothstep

TAU = math.tau
MESH_AIM = 17500  # split a mesh above this many triangles (the hard limit is 20,000)
CROWN = 0.005  # a hair of height so no flat sheet has a zero-height bounding box


class Land:
    def __init__(self, ring, plot_size, hub_radius, world, plan):
        self.ring_data, self.world, self.plan = ring, world, plan
        self.count = ring["plotCount"]
        self.step = TAU / self.count
        self.radius = ring["radius"]
        self.inner = ring["frontRadius"]
        self.outer = ring["backRadius"]
        self.plot_x, self.plot_y, self.plot_z = plot_size
        self.hub_radius = hub_radius
        self.corner = math.hypot(self.outer, self.plot_x / 2)
        self.r0 = self.corner + plan["foothillStart"]
        terrain = plan["terrain"]
        self.r_out = min(terrain["outerRadiusMax"], self.r0 + terrain["outerRadiusFromR0"])
        self.lift = plan["overlayLift"]
        self.rise = terrain["outsideRise"]
        wall = (world.get("valley") or {}).get("wall") or {}
        segments = int(wall.get("segments", 36))
        # The wall's flat segments are tangent to wallRadius, so their corners stand further out:
        # those corners must still be on the flat basin, wallInset inside r0.
        self.wall_radius = round((self.r0 - plan["wallInset"]) * math.cos(math.pi / segments), 1)
        self.noise = G.Noise(plan["seed"])
        self.P = {k: lin(v) for k, v in plan["palette"].items() if k != "flowers"}
        self.P["flowers"] = [lin(c) for c in plan["palette"]["flowers"]]
        self.P["dirt"] = lin(world["roads"]["color"])
        self.P["earth"] = lin(world["hub"]["surround"]["color"])
        self.P["hubstone"] = lin(world["hub"]["color"])
        self.meadow_tones = [lin(c) for c in plan["meadow"]["tones"]]
        self.road_width = float(world["roads"]["width"])
        self.earth_radius = float(world["hub"]["surround"]["radius"])
        self.notes = []
        self.setup()

    # ------------------------------------------------------------ the ring

    def angle(self, k):
        return -k * self.step

    def gap_angle(self, k):
        """The gap between plot k and plot k + 1 (0-based)."""
        return -(k + 0.5) * self.step

    def centre(self, k):
        return polar(self.radius, self.angle(k))

    def to_local(self, k, x, y):
        """Map point -> plot-local (lx across the plot, ly toward the hub)."""
        a = self.angle(k)
        cx, cy = self.centre(k)
        dx, dy = x - cx, y - cy
        return (-dx * math.sin(a) + dy * math.cos(a), -dx * math.cos(a) - dy * math.sin(a))

    def to_map(self, k, lx, ly):
        a = self.angle(k)
        cx, cy = self.centre(k)
        return (cx - lx * math.sin(a) - ly * math.cos(a), cy + lx * math.cos(a) - ly * math.sin(a))

    def rect_distance(self, k, x, y):
        lx, ly = self.to_local(k, x, y)
        qx, qy = abs(lx) - self.plot_x / 2, abs(ly) - self.plot_z / 2
        return math.hypot(max(qx, 0.0), max(qy, 0.0)) + min(max(qx, qy), 0.0)

    def plot_distances(self, x, y):
        bearing = math.atan2(y, x)
        k = (-bearing / TAU * self.count) % self.count
        lo = int(math.floor(k)) % self.count
        hi = (lo + 1) % self.count
        if lo == hi:
            return [(self.rect_distance(lo, x, y), lo)]
        return [(self.rect_distance(lo, x, y), lo), (self.rect_distance(hi, x, y), hi)]

    def plot_distance(self, x, y):
        return min(self.plot_distances(x, y))[0]

    # ------------------------------------------------------------ layout

    def plan_radius(self, base, offset):
        if base == "inner>mid":  # `offset` is the fraction of the way from the plots' fronts to mid
            return self.inner + (self.mid_r - self.inner) * offset
        return {
            "r0": self.r0,
            "outer": self.outer,
            "radius": self.radius,
            "inner": self.inner,
            "pass": self.pass_r,
            "mid": self.mid_r,
        }[base] + offset

    def plan_angle(self, base, value):
        a_in, a_mid, a_out = self.a_in, self.a_mid, self.a_out
        if base == "in":
            return a_in + value
        if base == "mid":
            return a_mid + value
        if base == "out":
            return a_out + value
        if base == "in>mid":
            return a_in + (a_mid - a_in) * value
        if base == "mid>out":
            return a_mid + (a_out - a_mid) * value
        raise SystemExit(f"Valley.plan.json: unknown angle base {base!r}")

    def setup(self):
        plan = self.plan
        r0 = self.r0
        # The river enters through the gap between the last plot and the first and leaves through
        # the gap after plot round(N / 2) (0-based), bending round the hub between them.
        self.a_in = self.gap_angle(self.count - 1) % TAU
        self.a_out = self.gap_angle(round(self.count / 2)) % TAU
        self.a_mid = (self.a_in + self.a_out) / 2
        self.pass_r = self.hub_radius + plan["pond"]["offset"]
        self.mid_r = self.pass_r + (self.inner - self.pass_r) * plan["river"]["midFraction"]
        river = plan["river"]
        ctrl = []
        for r_base, r_off, a_base, a_value, width in river["control"]:
            ctrl.append((*polar(self.plan_radius(r_base, r_off), self.plan_angle(a_base, a_value)), width))
        samples = G.catmull(ctrl, river["step"])
        self.river_samples = samples
        self.river = G.Line(samples, reach=175.0)
        self.river_near = G.Line(samples, reach=max(s[2] for s in samples) / 2 + river["softOutset"] + 12.0)
        self.source = samples[0][:2]
        self.axis = (math.cos(self.a_in + 0.015), math.sin(self.a_in + 0.015))
        self.core_in, self.water_out = river["coreInset"], river["waterOutset"]
        self.bank_out, self.soft_out = river["bankOutset"], river["softOutset"]
        self.bed = river["bedBelowGround"]
        self.water_lift = plan["water"]["lift"]
        self.lake = polar(r0 + plan["lake"]["r"], self.a_out)
        self.lake_r = float(plan["lake"]["radius"])
        # peaks, in the order and from the generators the mock used
        terrain = plan["terrain"]
        peaks = []
        for hero in terrain["heroPeaks"]:
            a = hero["angle"]
            a = self.plan_angle(a[0], a[1]) if isinstance(a, list) else a
            peaks.append((*polar(r0 + hero["r"], a), hero["height"], hero["radius"]))
        for group in terrain["rings"]:
            rng = random.Random(group["seed"])
            for i in range(group["count"]):
                a = (i + rng.uniform(-0.28, 0.28)) / group["count"] * TAU
                rr = r0 + rng.uniform(*group["band"])
                h = rng.uniform(*group["heights"])
                radius = h * rng.uniform(1.5, 1.95) + 55
                peaks.append((rr * math.cos(a), rr * math.sin(a), h, radius))
        self.peaks = peaks
        self.heroes = len(terrain["heroPeaks"])
        self.snowline, self.rockline, self.treeline = terrain["snowline"], terrain["rockline"], terrain["treeline"]
        # roads: hub -> the centre of each plot's front edge; footpaths: hub -> pond -> the grove
        self.roads = [self.make_road(k) for k in range(self.count)]
        ux, uy = math.cos(self.a_mid), math.sin(self.a_mid)
        pond_w = max(s[2] for s in samples if math.hypot(s[0], s[1]) < self.pass_r + 20)
        self.pond_width = pond_w
        bank = pond_w / 2 + self.bank_out
        self.stones = [(ux * (self.pass_r + off), uy * (self.pass_r + off)) for off in plan["pond"]["stoneOffsets"]]
        self.picnic = (ux * (self.pass_r + plan["pond"]["picnicOffset"]), uy * (self.pass_r + plan["pond"]["picnicOffset"]))
        path_w = plan["roads"]["pathWidth"]
        self.paths = [
            self.make_strip([(ux * (self.earth_radius - 2), uy * (self.earth_radius - 2)), (ux * (self.pass_r - bank - 0.5), uy * (self.pass_r - bank - 0.5))], path_w, 50.0),
            self.make_strip([(ux * (self.pass_r + bank + 0.5), uy * (self.pass_r + bank + 0.5)), self.picnic], path_w, 51.0),
        ]
        self.strips = self.roads + self.paths
        self.groves = self.plan_groves()
        self.bridges = self.plan_bridges()

    def make_strip(self, ctrl, width, seed):
        """A dirt strip: centreline samples plus its wobbled fill and rim widths."""
        step = self.plan["roads"]["step"]
        rim = self.plan["roads"]["rim"]
        samples = G.catmull([(x, y, width) for x, y in ctrl], step)
        fill_w = G.wobble_widths(samples, 0.45, 23.0, seed + 1.7)
        rim_w = G.wobble_widths([(x, y, width + 2 * rim) for x, y, _ in samples], 0.5, 19.0, seed)
        rim_w = [max(r, f + 0.5) for r, f in zip(rim_w, fill_w)]
        pts = [(x, y) for x, y, _ in samples]
        return {
            "pts": pts,
            "width": width,
            "fill": G.Line([(x, y, w) for (x, y), w in zip(pts, fill_w)], reach=14.0),
            "rim": G.Line([(x, y, w) for (x, y), w in zip(pts, rim_w)], reach=14.0),
        }

    def make_road(self, k):
        a = self.angle(k)
        ux, uy = math.cos(a), math.sin(a)
        nx, ny = -uy, ux
        start, end = self.hub_radius, self.inner
        length = end - start
        sign = 1 if k % 2 else -1
        ctrl = [(ux * start, uy * start)]
        for t, amp in self.plan["roads"]["bends"]:
            kk = amp * sign * (0.6 + 0.4 * G.hash01(k, t)) * min(1.0, length / 150.0)
            ctrl.append((ux * (start + length * t) + nx * kk, uy * (start + length * t) + ny * kk))
        far, near = self.plan["roads"]["straight"]
        for back in (min(far, length * 0.3), min(near, length * 0.15)):
            ctrl.append((ux * (end - back), uy * (end - back)))
        ctrl.append((ux * end, uy * end))
        return self.make_strip(ctrl, self.road_width, k * 3.1)

    def strip_class(self, x, y):
        """0 = not on a strip, 1 = its rim, 2 = its fill."""
        best = 0
        for strip in self.strips:
            d, w, _ = strip["rim"].query(x, y)
            if d < w / 2:
                d2, w2, _ = strip["fill"].query(x, y)
                if d2 < w2 / 2:
                    return 2
                best = 1
        return best

    def strip_blocked(self, x, y, margin):
        for strip in self.strips:
            d, w, _ = strip["rim"].query(x, y)
            if d < w / 2 + margin:
                return True
        return False

    def river_near_d(self, x, y):
        """(distance to the river's centreline, half width there)."""
        d, w, _ = self.river_near.query(x, y)
        return d, w / 2

    def in_channel(self, x, y, margin=0.0):
        d, hw = self.river_near_d(x, y)
        return d < hw + margin

    def lake_distance(self, x, y):
        return math.hypot(x - self.lake[0], y - self.lake[1]) + 9 * self.noise.fbm(x / 55, y / 55, 15.0)

    def wet(self, x, y, margin=0.0):
        return self.in_channel(x, y, margin) or self.lake_distance(x, y) < self.lake_r + margin

    def earth_edge(self, a):
        return self.earth_radius + self.plan["hub"]["earthWobble"] * self.noise.fbm(4.75 * math.cos(a), 4.75 * math.sin(a), 3.0)

    def plan_groves(self):
        """Stands of trees in the wedges between the roads: (x, y, radius, trees)."""
        cfg = self.plan["groves"]
        rng = random.Random(cfg["seed"])
        groves = [(self.picnic[0], self.picnic[1], 13.0, 9)]
        lo, hi = self.hub_radius + 42, self.inner - 34
        for k in range(self.count):
            a = self.gap_angle(k)
            for band in ((0.18, 0.42), (0.6, 0.95)):
                if hi - lo < 60 and band[0] > 0.5:
                    continue
                t = rng.uniform(*band)
                r = lo + (hi - lo) * t
                spread = self.step * 0.22
                aa = a + rng.uniform(-spread, spread)
                x, y = polar(r, aa)
                radius = rng.uniform(*cfg["radius"]) * (0.8 + 0.5 * t)
                trees = rng.randint(*cfg["trees"]) + (3 if t > 0.5 else 0)
                if self.in_channel(x, y, radius + 9.0 + self.bank_out) or self.strip_blocked(x, y, radius * 0.6 + 4.0):
                    continue
                groves.append((x, y, radius, trees))
        return groves

    def plan_bridges(self):
        """One plank bridge where each road crosses the river: the deck runs between the road's last
        sample outside the bank on one side and the first on the other."""
        cfg = self.plan["bridge"]
        margin = self.bank_out + cfg["bankMargin"]
        out = []
        for k, road in enumerate(self.roads):
            before = None
            inside = False
            for x, y in road["pts"]:
                if self.in_channel(x, y, margin):
                    inside = True
                    continue
                if inside and before is not None:
                    length = math.dist(before, (x, y))
                    out.append(
                        {
                            "plot": k,
                            "p0": before,
                            "p1": (x, y),
                            "centre": ((before[0] + x) / 2, (before[1] + y) / 2),
                            "length": length,
                            "dir": ((x - before[0]) / length, (y - before[1]) / length),
                            "width": self.road_width + cfg["extraWidth"],
                        }
                    )
                inside = False
                before = (x, y)
        return out

    # ------------------------------------------------------------ heights

    def mountains(self, x, y, r):
        r0 = self.r0
        if r < r0:
            return 0.0
        n = self.noise
        wx = x + 40 * n.n2(x / 170, y / 170, 3.1)
        wy = y + 40 * n.n2(x / 170, y / 170, 9.4)
        best = second = 0.0
        crown = 0.0
        for index, (px, py, h, radius) in enumerate(self.peaks):
            dx, dy = wx - px, wy - py
            if dx > radius or dx < -radius or dy > radius or dy < -radius:
                continue
            d = math.hypot(dx, dy)
            if d < radius:
                v = h * (1 - d / radius) ** 1.35
                if v > best:
                    best, second = v, best
                    # a hero peak keeps its full height at its top whatever the ridge noise says there
                    crown = smoothstep(0.5, 0.12, d / radius) if index < self.heroes else 0.0
                elif v > second:
                    second = v
        crest = max(n.ridge(x / 210, y / 210, 5.0), crown)
        peaks = (best + 0.4 * second) * (0.74 + 0.34 * crest) * smoothstep(r0, r0 + 140, r)
        foothill = smoothstep(r0, r0 + 150, r) * (13 + 11 * n.fbm(x / 120, y / 120, 2.0))
        wall = smoothstep(r0 + 90, r0 + 340, r) * (20 + 14 * n.fbm(x / 260, y / 260, 4.0))
        return foothill + wall + peaks

    def cliff(self, x, y):
        dx, dy = x - self.source[0], y - self.source[1]
        along = dx * self.axis[0] + dy * self.axis[1]
        if along < 4 or along > 280:
            return 0.0
        lateral = abs(-dx * self.axis[1] + dy * self.axis[0])
        if lateral > 120:
            return 0.0
        height = self.plan["terrain"]["cliffHeight"]
        return height * smoothstep(5, 17, along) * (1 - smoothstep(42, 120, lateral)) * (1 - smoothstep(130, 280, along))

    def relief(self, x, y, r):
        r0 = self.r0
        mask = 1.0
        d = self.river.dist(x, y)
        if d < 130:
            mask *= smoothstep(24, 128, d)
        raw = math.hypot(x - self.lake[0], y - self.lake[1])
        mask *= smoothstep(self.lake_r + 25, self.lake_r + 200, raw)
        out = self.mountains(x, y, r) * mask + self.cliff(x, y)
        if r < r0 + 30:
            dp = self.plot_distance(x, y)
            w = smoothstep(34, 62, dp) * (1 - smoothstep(r0 - 10, r0 + 30, r)) * smoothstep(r0, r0 + 12, r)
            if w > 0:
                w *= smoothstep(20, 70, d)
                out += 6.5 * w * max(0.0, 0.25 + self.noise.fbm(x / 55, y / 55, 8.0))
        return out

    def height(self, x, y):
        """Studs above the ground top. Flat at the overlay everywhere inside r0."""
        r = math.hypot(x, y)
        r0 = self.r0
        if r <= r0:
            return self.lift
        base = self.lift + self.rise * smoothstep(r0, r0 + 25, r)
        h = base + self.relief(x, y, r)
        d, hw = self.river_near_d(x, y)
        if d < hw + self.bank_out:
            k = 1 - smoothstep(hw - self.core_in, hw + self.bank_out, d)
            h -= smoothstep(r0, r0 + 18, r) * k * (base + self.bed)
        dl = self.lake_distance(x, y)
        if dl < self.lake_r + 2:
            h += (-self.bed - h) * smoothstep(self.lake_r + 2, self.lake_r - 14, dl)
        return h

    # ------------------------------------------------------------ points

    def spacing_at(self, x, y, r):
        s = self.plan["terrain"]["spacing"]
        if r < self.inner - 25:
            return s["centre"]
        if r < self.r0:
            return s["band"]
        if math.dist((x, y), self.source) < 95:
            return s["fine"]
        if abs(self.lake_distance(x, y) - self.lake_r) < 15:
            return s["fine"]
        if r < self.r0 + self.plan["terrain"]["foothillsWidth"]:
            return s["foothills"]
        if r < self.r0 + self.plan["terrain"]["mountainsWidth"]:
            return s["mountains"]
        return s["far"]

    def lattice_skip(self, x, y, r):
        r0 = self.r0
        if r > self.r_out - 20:
            return True
        if abs(r - r0) < 3.2:
            return True
        if r < self.earth_radius + 6.0 and r < self.earth_edge(math.atan2(y, x)) + 2.5:
            return True
        if self.inner - 4 < r < self.corner + 4 and self.plot_distance(x, y) < 2.5:
            return True
        d, hw = self.river_near_d(x, y)
        if d < hw + self.soft_out + 2.5:
            return True
        if r < self.inner + 1 and self.strip_blocked(x, y, 2.2):
            return True
        return False

    def build_points(self):
        """Every vertex of the ground, and the chains of them that must come out as edges."""
        pts, index, segments = [], {}, []

        def add(x, y):
            key = (round(x, 3), round(y, 3))
            i = index.get(key)
            if i is None:
                i = len(pts)
                index[key] = i
                pts.append((x, y))
            return i

        def chain(points, closed=False):
            ids = [None if p is None else add(*p) for p in points]
            if closed and ids:
                ids.append(ids[0])
            for a, b in zip(ids, ids[1:]):
                if a is not None and b is not None and a != b:
                    segments.append((a, b))

        s = self.plan["terrain"]["spacing"]
        r0 = self.r0
        levels = sorted(
            {
                (s["centre"], self.inner),
                (s["band"], r0 + 1),
                (s["fine"], r0 + 300.0),
                (s["foothills"], r0 + self.plan["terrain"]["foothillsWidth"] + 5.0),
                (s["mountains"], r0 + self.plan["terrain"]["mountainsWidth"] + 5.0),
                (s["far"], self.r_out),
            }
        )
        merged = {}
        for spacing, bound in levels:
            merged[spacing] = max(bound, merged.get(spacing, 0.0))
        rng = random.Random(1234)
        for spacing in sorted(merged):
            bound = merged[spacing]
            rows = int(bound / (spacing * 0.866)) + 1
            cols = int(bound / spacing) + 1
            for j in range(-rows, rows + 1):
                y0 = j * spacing * 0.866
                for i in range(-cols, cols + 1):
                    x = (i + 0.5 * (j & 1)) * spacing + rng.uniform(-0.27, 0.27) * spacing
                    y = y0 + rng.uniform(-0.27, 0.27) * spacing
                    r = math.hypot(x, y)
                    if r > self.r_out or self.spacing_at(x, y, r) != spacing or self.lattice_skip(x, y, r):
                        continue
                    add(x, y)

        # the hub: its wall, one ring inside the earth, and the earth's irregular edge
        hub = self.hub_radius
        chain([polar(hub, k / 44 * TAU) for k in range(44)], closed=True)
        for k in range(44):
            add(*polar(hub + 4.0, (k + 0.5) / 44 * TAU))
        edge = []
        n = 72
        for k in range(n):
            a = k / n * TAU
            p = polar(self.earth_edge(a), a)
            edge.append(None if self.strip_blocked(p[0], p[1], 0.9) else p)
        chain(edge, closed=True)
        # the plots: their outlines (what lies inside is dropped)
        hx, hy = self.plot_x / 2, self.plot_z / 2
        per_side = max(4, int(round(self.plot_x / 6.0)))
        for k in range(self.count):
            outline = []
            for lx0, ly0, lx1, ly1 in ((-hx, -hy, hx, -hy), (hx, -hy, hx, hy), (hx, hy, -hx, hy), (-hx, hy, -hx, -hy)):
                for i in range(per_side):
                    t = i / per_side
                    outline.append(self.to_map(k, lx0 + (lx1 - lx0) * t, ly0 + (ly1 - ly0) * t))
            chain(outline, closed=True)
            add(*self.centre(k))
        # the wall line and the terrain's outer rim
        ring = []
        n = max(24, int(round(TAU * r0 / s["band"])))
        for k in range(n):
            p = polar(r0, k / n * TAU)
            ring.append(None if self.in_channel(p[0], p[1], self.soft_out + 1.5) else p)
        chain(ring, closed=True)
        n = max(24, int(round(TAU * self.r_out / s["far"])))
        chain([polar(self.r_out, k / n * TAU) for k in range(n)], closed=True)
        # the river: its bed core, water edge, bank and soft bank, both sides
        river = self.river_near
        offsets = (-self.core_in, self.water_out, self.bank_out, self.soft_out)
        rows = {(side, off): [] for side in (-1, 1) for off in offsets}
        for i, (x, y) in enumerate(river.pts):
            tx, ty = river.tangent(i)
            nx, ny = -ty, tx
            hw = river.w[i] / 2
            r = math.hypot(x, y)
            add(x, y)
            if hw > 10:
                add(x + nx * hw / 2, y + ny * hw / 2)
                add(x - nx * hw / 2, y - ny * hw / 2)
            for side in (-1, 1):
                for off in offsets:
                    reach = hw + off
                    p = (x + nx * side * reach, y + ny * side * reach)
                    pr = math.hypot(p[0], p[1])
                    keep = reach > 0.8 and pr < self.r_out - 8
                    if keep and self.inner - 4 < pr < self.corner + 4 and self.plot_distance(p[0], p[1]) < 2.5:
                        keep = False
                    if keep and r > r0 + 20 and self.lake_distance(p[0], p[1]) < self.lake_r - 18:
                        keep = False
                    rows[(side, off)].append(p if keep else None)
        for key in sorted(rows):
            chain(rows[key])
        # roads and footpaths: fill and rim edges, both sides, clear of the hub, the plots and the river
        for strip in self.strips:
            fill, rim = strip["fill"], strip["rim"]
            rows = {(side, which): [] for side in (-1, 1) for which in (0, 1)}
            for i, (x, y) in enumerate(strip["pts"]):
                tx, ty = fill.tangent(i)
                nx, ny = -ty, tx
                r = math.hypot(x, y)
                ok = hub + 0.6 < r < self.inner - 0.8 and not self.in_channel(x, y, self.soft_out + 4.5)
                for side in (-1, 1):
                    for which, line in ((0, fill), (1, rim)):
                        reach = line.w[i] / 2
                        rows[(side, which)].append((x + nx * side * reach, y + ny * side * reach) if ok else None)
            for key in sorted(rows):
                chain(rows[key])
        return pts, segments

    # ------------------------------------------------------------ colour

    def grove_shade(self, x, y):
        shade = 0.0
        for gx, gy, radius, _ in self.groves:
            if abs(x - gx) > radius + 6 or abs(y - gy) > radius + 6:
                continue
            d = math.hypot(x - gx, y - gy)
            shade = max(shade, 1 - smoothstep(radius * 0.5, radius + 6, d))
        return shade

    def flower_patch(self, x, y):
        return smoothstep(0.22, 0.5, self.noise.fbm(x / 46, y / 46, 131.0))

    def meadow(self, x, y, rnd):
        """The two-tone mosaic, with dry, darker and wildflower patches."""
        P, n, m = self.P, self.noise, self.plan["meadow"]
        # Two tones close to the Ground Part's own colour, chosen by a coarse noise so neighbouring
        # facets usually share one: a soft texture, not a pattern. The patches are gentle, continuous
        # shifts over large areas, never a per-facet choice.
        tone = 0.5 + 0.5 * n.fbm(x / 110, y / 110, 11.0) + (rnd - 0.5) * m["toneDither"]
        c = self.meadow_tones[1] if tone > 0.5 else self.meadow_tones[0]
        c = mix(c, P["dry"], m["dry"] * smoothstep(0.2, 0.6, n.fbm(x / 170, y / 170, 23.0)))
        scale = m["darkScale"]
        c = mix(c, P["darkgrass"], m["dark"] * smoothstep(0.18, 0.5, n.fbm(x / scale, y / scale, 101.0)))
        c = mix(c, P["flowergrass"], m["flower"] * self.flower_patch(x, y))
        return mix(c, P["forest"], m["groveShade"] * self.grove_shade(x, y))

    def basin_colour(self, x, y, r, rnd):
        P = self.P
        d, hw = self.river_near_d(x, y)
        if d < hw + self.soft_out:
            if d < hw - self.core_in:
                return P["bedcore"]
            if d < hw + self.water_out:
                return P["bededge"]
            if d < hw + self.bank_out:
                return P["bank"]
            return mix(P["bank"], self.meadow(x, y, rnd), 0.55)
        kind = self.strip_class(x, y)
        if kind == 2:
            return mix(P["dirt"], P["dirtrim"], 0.18 * rnd)
        if kind == 1:
            return P["dirtrim"]
        if r < self.earth_radius + 6.0 and r < self.earth_edge(math.atan2(y, x)):
            return P["earth"]
        return self.meadow(x, y, rnd)

    def forest_density(self, x, y, r):
        r0 = self.r0
        f = self.plan["forest"]
        band = smoothstep(r0 + f["bandIn"], r0 + f["bandFull"], r) * (1 - smoothstep(r0 + f["bandFade"][0], r0 + f["bandFade"][1], r))
        if band <= 0:
            return 0.0
        patch = 0.5 + 0.5 * self.noise.fbm(x / 130, y / 130, 21.0)
        return band * (0.12 + 0.88 * smoothstep(0.28, 0.62, patch))

    def rock_colour(self, x, y, normal):
        P = self.P
        facing = 0.5 + 1.1 * (normal[0] * 0.55 + normal[1] * 0.83)
        rock = mix(P["rock2"], P["rock"], facing)
        return mix(rock, P["rockwarm"], 0.55 * smoothstep(0.0, 0.5, self.noise.fbm(x / 140, y / 140, 9.0)))

    def terrain_colour(self, x, y, h, normal, rnd):
        P, n = self.P, self.noise
        r = math.hypot(x, y)
        rel = h - self.lift
        nz = normal[2]
        if rel < -0.25:
            # under the water sheet: sand in the shallows, the bed's blue where it is deep
            shore = mix(P["bank"], P["sand"], smoothstep(-0.25, -0.5, rel))
            return mix(shore, P["bedcore"], smoothstep(-0.55, -0.88, rel))
        dl = self.lake_distance(x, y)
        patch = n.fbm(x / 110, y / 110, 11.0)
        c = mix(P["grass"], P["grass2"], 0.5 + 0.5 * patch)
        c = mix(c, P["dry"], 0.4 * smoothstep(0.2, 0.6, n.fbm(x / 170, y / 170, 23.0)))
        if dl < self.lake_r + 11:
            return mix(P["sand"], c, smoothstep(self.lake_r + 3, self.lake_r + 11, dl))
        d, hw = self.river_near_d(x, y)
        if d < hw + self.bank_out + 2.5 and rel < 1.5:
            return mix(P["bank"], c, smoothstep(hw + self.bank_out - 0.5, hw + self.bank_out + 2.5, d))
        if rel > 1.5:
            f = self.forest_density(x, y, r)
            far = smoothstep(self.r0 + 380, self.r0 + 620, r)
            c = mix(c, P["forest"], smoothstep(2, 14, rel) * (0.3 + 0.6 * f))
            if far > 0:
                hill = mix(P["farhill"], P["forest"], 0.5 + 0.5 * n.fbm(x / 260, y / 260, 33.0))
                c = mix(c, hill, far)
            alt = rel + 20 * n.fbm(x / 90, y / 90, 41.0)
            c = mix(c, P["alpine"], smoothstep(self.treeline - 25, self.treeline + 15, alt))
            steep = 1 - nz
            c = mix(c, self.rock_colour(x, y, normal), max(smoothstep(0.36, 0.54, steep), smoothstep(self.rockline - 18, self.rockline + 10, alt)))
            snow = smoothstep(self.snowline - 10, self.snowline + 14, alt) * (1 - 0.55 * smoothstep(0.45, 0.7, steep))
            c = mix(c, P["snow"], snow)
        k = 1 + (rnd - 0.5) * 0.07
        return (c[0] * k, c[1] * k, c[2] * k)

    # ------------------------------------------------------------ the ground meshes

    def build_ground(self):
        """Triangulates the whole ground once, then deals its faces to the basin overlay (flat,
        inside r0, not under the hub or a plot) and to the terrain quadrants outside it.

        Returns {mesh name: Builder}; also keeps the terrain for the tree planter."""
        pts2, segments = self.build_points()
        pts2, tris, missing = G.triangulate(pts2, segments)
        self.notes.append(f"ground: {len(pts2)} points, {len(tris)} triangles, {len(segments)} constrained edges, {missing} not honoured")
        r0 = self.r0
        verts = []
        for i, (x, y) in enumerate(pts2):
            r = math.hypot(x, y)
            if r <= r0 + 1e-6:
                # the overlay is flat; a hair under it on some vertices keeps its bounding box 3D
                verts.append((x, y, self.lift - CROWN * G.hash01(x, y)))
            else:
                verts.append((x, y, self.height(x, y)))
        basin, terrain = [], [[] for _ in range(4)]
        terrain_tris = []
        summit = None
        hub2 = (self.hub_radius - 0.01) ** 2
        for a, b, c in tris:
            va, vb, vc = verts[a], verts[b], verts[c]
            cx, cy = (va[0] + vb[0] + vc[0]) / 3, (va[1] + vb[1] + vc[1]) / 3
            r = math.hypot(cx, cy)
            rnd = G.hash01(cx, cy)
            if r < r0:
                if cx * cx + cy * cy < hub2 or (r > self.inner - 1 and self.plot_distance(cx, cy) < 0.0):
                    continue
                k = 1 + (rnd - 0.5) * self.plan["meadow"]["facetJitter"]
                col = self.basin_colour(cx, cy, r, rnd)
                basin.append((math.atan2(cy, cx), va, vb, vc, (col[0] * k, col[1] * k, col[2] * k)))
            else:
                ch = (va[2] + vb[2] + vc[2]) / 3
                ux, uy, uz = vb[0] - va[0], vb[1] - va[1], vb[2] - va[2]
                vx, vy, vz = vc[0] - va[0], vc[1] - va[1], vc[2] - va[2]
                nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
                length = math.sqrt(nx * nx + ny * ny + nz * nz) or 1.0
                if nz < 0:
                    nx, ny, nz = -nx, -ny, -nz
                col = self.terrain_colour(cx, cy, ch, (nx / length, ny / length, nz / length), rnd)
                # quadrants in the ROBLOX frame: X >= 0 / Z >= 0, i.e. map x and -y
                quadrant = (0 if cx >= 0 else 1) + (0 if -cy >= 0 else 2)
                terrain[quadrant].append((va, vb, vc, col))
                terrain_tris.append((a, b, c))
                for v in (va, vb, vc):
                    if summit is None or v[2] > summit[2]:
                        summit = v
        self.summit = summit
        self.locator = G.Locator(verts, terrain_tris)
        out = {}
        basin.sort(key=lambda f: f[0])
        parts = max(1, math.ceil(len(basin) / MESH_AIM))
        size = math.ceil(len(basin) / parts)
        for part in range(parts):
            builder = G.Builder()
            for _, va, vb, vc, col in basin[part * size : (part + 1) * size]:
                builder.up(va, vb, vc, col)
            out[f"Basin_{part + 1}"] = builder
        for q in range(4):
            builder = G.Builder()
            for va, vb, vc, col in terrain[q]:
                builder.up(va, vb, vc, col)
            out[f"Mountains_{q + 1}"] = builder
        return out

    def ground_at(self, x, y):
        """(h, nz) of the visible ground under a map point."""
        if math.hypot(x, y) < self.r0:
            return self.lift, 1.0
        hit = self.locator.sample(x, y)
        if hit is None:
            return self.height(x, y), 1.0
        return hit
