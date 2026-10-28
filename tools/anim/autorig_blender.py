# Blender 5.2 side of `animate.py rig`. Never run directly: the launcher writes a job JSON and calls
#   blender -b --python tools/anim/autorig_blender.py -- <job.json>
#
# Rigs an unrigged Tripo character (T-pose, empty hands) with the 22-bone Mixamo skeleton that
# ual_blender.py retargets onto, so a model generated without Tripo's paid rigging can still be
# animated. Written for Ben's 2026-10-27 batch, where only the Chief came rigged.
#
# Joints are measured, never assumed: the mesh is sampled by area (its few large faces leave vertex
# slices patchy) and read slice by slice (arm line, armpits, the gap between the legs, the ankles
# where the foot's length ends). Proportions fill in only what a slice cannot see (elbow and wrist
# along the measured arm, the knee between the measured hip and ankle).
#
# Weights: Tripo bodies are hundreds of open shells, on which Blender's heat weighting fails. A
# closed proxy (solidify, then voxel remesh) takes the heat weights, and the body copies them from
# its nearest proxy face. Four influences per vertex at most, as Roblox skins.
import bpy, bmesh, sys, os, json, math, random
from mathutils import Vector, Matrix

JOB = json.load(open(sys.argv[sys.argv.index("--") + 1], encoding="utf-8"))
SAMPLES = 200000
# Proxy attempts (shell thickness, voxel size) as shares of the height, thinnest first: thicker
# shells close more gaps but start to weld the arms to the torso.
PROXY_TRIES = ((0.02, 0.008), (0.03, 0.008), (0.03, 0.01), (0.04, 0.012))
# A proxy island under this share of the vertices is a scrap no bone's heat reaches; the body
# vertices near it take their weights from the main island instead.
SCRAP = 0.02
# Shares along the measured arm (shoulder joint to fingertip), from the fodder fitted by hand.
ELBOW, WRIST, HAND_END = 0.38, 0.69, 0.89
KNEE = 0.47  # share of the way from ankle up to hip
SPINE = (0.2, 0.43, 0.66)  # Spine, Spine1, Spine2 heads between the hips and the neck


def fail(msg):
    print("RIG-FAIL", msg)
    sys.exit(2)


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=JOB["character"])
for o in list(bpy.data.objects):
    # the importer's parentless default sphere, and any light or camera the file carried
    if o.type not in ("MESH", "ARMATURE") or (o.type == "MESH" and o.name.startswith("Icosphere")
                                               and not o.data.materials):
        bpy.data.objects.remove(o)
meshes = [o for o in bpy.data.objects if o.type == "MESH"]
if not meshes:
    fail("no mesh in the file")
rigs = [o for o in bpy.data.objects if o.type == "ARMATURE"]
if rigs:
    # Tripo's own Mixamo rig (the Chief, 2026-10-27) can arrive facing +X: only turn it to face -Y
    # like the library, keeping Tripo's skeleton and weights
    rig = rigs[0]
    left = next((b for b in rig.data.bones if b.name.replace("mixamorig:", "") == "LeftArm"), None)
    if not left:
        fail("rigged, but not with a Mixamo skeleton (no LeftArm)")
    d = rig.matrix_world.to_3x3() @ (left.tail_local - left.head_local)
    turn = -math.atan2(d.y, d.x)  # brings the left arm onto +X, so the front faces -Y
    for o in bpy.data.objects:
        o.select_set(o.type in ("ARMATURE", "MESH"))
    bpy.context.view_layer.objects.active = rig
    for o in [o for o in bpy.data.objects if o.parent is None]:
        o.matrix_world = Matrix.Rotation(turn, 4, "Z") @ o.matrix_world
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    os.makedirs(os.path.dirname(JOB["out"]), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=JOB["out"], export_format="GLB", use_selection=True,
                              export_animations=False, export_skins=True, export_yup=True)
    print("RIG-REPORT " + json.dumps({"alreadyRigged": True, "turnDegrees": round(math.degrees(turn))}))
    print("RIG-DONE")
    sys.exit(0)
for o in bpy.context.view_layer.objects:
    o.select_set(o in meshes)
bpy.context.view_layer.objects.active = meshes[0]
if len(meshes) > 1:
    bpy.ops.object.join()
body = bpy.context.view_layer.objects.active
body.name = body.data.name = JOB["name"]
body.data.transform(body.matrix_world)
body.matrix_world = Matrix.Identity(4)


def bounds(vs):
    return (Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs))),
            Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs))))


def ground():
    lo, hi = bounds([v.co for v in body.data.vertices])
    body.data.transform(Matrix.Translation((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -lo.z)))


# ---------------------------------------------------------------- face -Y with the arms along X
ground()
lo, hi = bounds([v.co for v in body.data.vertices])
if hi.y - lo.y > hi.x - lo.x:
    body.data.transform(Matrix.Rotation(math.radians(-90), 4, "Z"))
    ground()
H = max(v.co.z for v in body.data.vertices)
vs = [v.co for v in body.data.vertices]
shin = [v.y for v in vs if 0.15 * H < v.z < 0.2 * H]
sole = [v.y for v in vs if v.z < 0.03 * H]
yc = (min(shin) + max(shin)) / 2
if max(sole) - yc > yc - min(sole):  # toes point +Y
    body.data.transform(Matrix.Rotation(math.pi, 4, "Z"))
    ground()
body.data.update()

# ---------------------------------------------------------------- sample the surface
me = body.data
me.calc_loop_triangles()
random.seed(1)
tri = [(me.vertices[t.vertices[0]].co.copy(), me.vertices[t.vertices[1]].co.copy(),
        me.vertices[t.vertices[2]].co.copy(), t.area) for t in me.loop_triangles]
total = sum(t[3] for t in tri)
pts = []
for a, b, c, area in tri:
    for _ in range(max(1, int(SAMPLES * area / total))):
        r1, r2 = random.random(), random.random()
        if r1 + r2 > 1:
            r1, r2 = 1 - r1, 1 - r2
        pts.append(a + (b - a) * r1 + (c - a) * r2)


def band(z0, z1, side=0, xmin=0.0, xmax=1e9):
    """Points with z in [z0, z1); side +1 / -1 keeps that half, at |x| within [xmin, xmax)."""
    return [p for p in pts if z0 <= p.z < z1 and (side == 0 or p.x * side > 0)
            and xmin <= abs(p.x) < xmax]


def centre(ps):
    a, b = bounds(ps)
    return (a + b) / 2


def legs_apart(z, gap):
    """True when the slice at z has a clear gap at x = 0 with a leg on each side."""
    s = band(z, z + 0.01 * H, xmax=0.25 * H)
    return (not any(abs(p.x) < gap for p in s) and any(p.x > gap for p in s)
            and any(p.x < -gap for p in s))


J = {}  # bone -> (head, tail)
report = {"height": round(H, 4)}
for side, prefix in ((1, "Left"), (-1, "Right")):
    arm = [p for p in pts if p.x * side > 0]
    tip = max(abs(p.x) for p in arm)
    # the upper arm, clear of both the torso and the hand (a resting hand droops below the line)
    upper = [p for p in arm if 0.45 * tip < abs(p.x) < 0.65 * tip]
    # gear beside the arm (a pack strap, a sack over the shoulder) is cut off around the median,
    # which the arm's own points dominate
    mid_y = sorted(p.y for p in upper)[len(upper) // 2]
    upper = [p for p in upper if abs(p.y - mid_y) < 0.06 * H]
    mid_z = sorted(p.z for p in upper)[len(upper) // 2]
    upper = [p for p in upper if abs(p.z - mid_z) < 0.08 * H]
    armz = (min(p.z for p in upper) + max(p.z for p in upper)) / 2
    # walking in from the tip, the armpit is where the underside drops from the arm onto the torso;
    # measured from the arm's own underside, so a thick brute's arm or a sleeve is not the torso
    under = min(p.z for p in upper)
    near = [p for p in arm if armz - 0.25 * H < p.z < armz + 0.1 * H]
    pit = 0.0
    x = 0.65 * tip
    while x > 0.05 * H:
        col = [p.z for p in near if x - 0.005 * H <= abs(p.x) < x]
        if col and min(col) < under - 0.04 * H:
            pit = x
            break
        x -= 0.005 * H
    if not pit:
        fail(f"{prefix} armpit not found: the arm never meets the torso below its line")
    sx = pit - 0.02 * H
    length = tip - sx

    def arm_at(x):
        s = [p for p in arm if abs(abs(p.x) - x) < 0.01 * H and abs(p.z - armz) < 0.08 * H
             and abs(p.y - mid_y) < 0.06 * H]
        c = centre(s)
        return Vector((side * x, c.y, c.z))

    elbow, wrist, hand = (arm_at(sx + f * length) for f in (ELBOW, WRIST, HAND_END))
    # at the shoulder the torso and anything on it surround the joint, so it stays on the arm's line
    shoulder = Vector((side * sx, elbow.y, armz))
    J[prefix + "Shoulder"] = (Vector((side * 0.2 * sx, shoulder.y, shoulder.z + 0.003 * H)), shoulder)
    J[prefix + "Arm"] = (shoulder, elbow)
    J[prefix + "ForeArm"] = (elbow, wrist)
    J[prefix + "Hand"] = (wrist, hand)
    report[prefix] = {"armZ": round(armz / H, 3), "armpit": round(pit / H, 3), "tip": round(tip / H, 3)}

# the crotch: the highest slice below the arms where the legs stand apart
gap_top = 0.0
z = 0.1 * H
while z < 0.6 * H:
    if legs_apart(z, 0.012 * H):
        gap_top = z
    z += 0.01 * H
armz = (report["Left"]["armZ"] + report["Right"]["armZ"]) / 2 * H
hip_z = max(gap_top + 0.04 * H, 0.5 * armz)
neck_z = armz + 0.03 * H
report["crotch"] = round(gap_top / H, 3)
report["hip"] = round(hip_z / H, 3)
thigh_z = min(hip_z - 0.08 * H, gap_top - 0.02 * H)
hip_ys = []
for side, prefix in ((1, "Left"), (-1, "Right")):
    leg = [p for p in pts if p.x * side > 0.012 * H and p.z < hip_z]
    sole = [p for p in leg if p.z < 0.01 * H]
    foot_len = max(p.y for p in sole) - min(p.y for p in sole)
    ankle_z = 0.12 * H
    z = 0.04 * H
    while z < 0.12 * H:
        s = [p for p in leg if z <= p.z < z + 0.01 * H]
        if s and max(p.y for p in s) - min(p.y for p in s) < 0.55 * foot_len:
            ankle_z = z
            break
        z += 0.005 * H
    ankle = centre([p for p in leg if ankle_z <= p.z < ankle_z + 0.01 * H])
    ankle.z = ankle_z
    thigh = centre([p for p in leg if thigh_z <= p.z < thigh_z + 0.02 * H])
    hip = Vector((thigh.x, thigh.y, hip_z))
    hip_ys.append(hip.y)
    knee_z = ankle_z + KNEE * (hip_z - ankle_z)
    knee = centre([p for p in leg if knee_z <= p.z < knee_z + 0.01 * H])
    knee = Vector((knee.x, knee.y - 0.005 * H, knee_z))
    toe_y = min(p.y for p in sole)
    sole_x = centre(sole).x
    ball = Vector((sole_x, ankle.y + 0.6 * (toe_y - ankle.y), 0.018 * H))
    J[prefix + "UpLeg"] = (hip, knee)
    J[prefix + "Leg"] = (knee, ankle)
    J[prefix + "Foot"] = (ankle, ball)
    J[prefix + "ToeBase"] = (ball, Vector((sole_x, toe_y + 0.005 * H, 0.015 * H)))
    report[prefix]["ankle"] = round(ankle_z / H, 3)
    report[prefix]["knee"] = round(knee_z / H, 3)

# the spine runs from the hips' depth to the head's (a pack on the back would drag a torso centre)
head_c = centre(band(neck_z + 0.08 * H, neck_z + 0.12 * H, xmax=0.08 * H))
hy = sum(hip_ys) / 2
h0 = hip_z + 0.03 * H


def spine_at(z):
    t = (z - h0) / (neck_z - h0)
    return Vector((0, hy + t * (head_c.y - hy), z))


chain = [spine_at(z) for z in [h0] + [h0 + f * (neck_z - h0) for f in SPINE] + [neck_z]]
for n, a, b in zip(("Hips", "Spine", "Spine1", "Spine2"), chain, chain[1:]):
    J[n] = (a, b)
skull = Vector((0, head_c.y, neck_z + 0.055 * H))
J["Neck"] = (chain[-1], skull)
J["Head"] = (skull, Vector((0, head_c.y, H)))

PARENT = {"Spine": "Hips", "Spine1": "Spine", "Spine2": "Spine1", "Neck": "Spine2", "Head": "Neck"}
for p in ("Left", "Right"):
    PARENT.update({p + "Shoulder": "Spine2", p + "Arm": p + "Shoulder", p + "ForeArm": p + "Arm",
                   p + "Hand": p + "ForeArm", p + "UpLeg": "Hips", p + "Leg": p + "UpLeg",
                   p + "Foot": p + "Leg", p + "ToeBase": p + "Foot"})

ad = bpy.data.armatures.new(JOB["name"] + "_rig")
rig = bpy.data.objects.new(JOB["name"] + "_rig", ad)
bpy.context.scene.collection.objects.link(rig)
for o in bpy.context.view_layer.objects:
    o.select_set(o == rig)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="EDIT")
eb = {}
for n, (h, t) in J.items():
    b = ad.edit_bones.new("mixamorig:" + n)
    b.head, b.tail = h, t
    eb[n] = b
for n, p in PARENT.items():
    eb[n].parent = eb[p]
    eb[n].use_connect = (eb[p].tail - eb[n].head).length < 1e-6
bpy.ops.object.mode_set(mode="OBJECT")


# ---------------------------------------------------------------- weights through a closed proxy
def islands(m):
    bm = bmesh.new()
    bm.from_mesh(m)
    bm.verts.ensure_lookup_table()
    seen, out = set(), []
    for v in bm.verts:
        if v.index in seen:
            continue
        stack, comp = [v], []
        seen.add(v.index)
        while stack:
            x = stack.pop()
            comp.append(x.index)
            for e in x.link_edges:
                y = e.other_vert(x)
                if y.index not in seen:
                    seen.add(y.index)
                    stack.append(y)
        out.append(comp)
    bm.free()
    return out


proxy = None
for thick, vox in PROXY_TRIES:
    if proxy:
        bpy.data.objects.remove(proxy)
    proxy = body.copy()
    proxy.data = body.data.copy()
    proxy.name = "proxy"
    bpy.context.scene.collection.objects.link(proxy)
    sol = proxy.modifiers.new("solid", "SOLIDIFY")
    sol.thickness, sol.offset = thick * H, 0
    rem = proxy.modifiers.new("remesh", "REMESH")
    rem.mode, rem.voxel_size = "VOXEL", vox * H
    for o in bpy.context.view_layer.objects:
        o.select_set(o == proxy)
    bpy.context.view_layer.objects.active = proxy
    bpy.ops.object.modifier_apply(modifier="solid")
    bpy.ops.object.modifier_apply(modifier="remesh")
    parts = islands(proxy.data)
    big = max(len(c) for c in parts)
    if sum(len(c) for c in parts if len(c) >= SCRAP * len(proxy.data.vertices)) == big:
        break
report["proxy"] = {"thickness": thick, "voxel": vox, "islands": len(parts)}
scrap = [i for c in parts if len(c) < SCRAP * len(proxy.data.vertices) for i in c]
if scrap:
    bm = bmesh.new()
    bm.from_mesh(proxy.data)
    bm.verts.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[bm.verts[i] for i in scrap], context="VERTS")
    bm.to_mesh(proxy.data)
    bm.free()
if len(islands(proxy.data)) != 1:
    fail(f"the proxy stays in {len(islands(proxy.data))} large pieces: the body has a big loose part "
         "(a pack, a cape) the shell cannot reach; weight it by hand")
proxy.data.materials.clear()
for o in bpy.context.view_layer.objects:
    o.select_set(o in (proxy, rig))
bpy.context.view_layer.objects.active = rig
bpy.ops.object.parent_set(type="ARMATURE_AUTO")
dry = sum(1 for v in proxy.data.vertices if not any(g.weight > 1e-4 for g in v.groups))
if dry:
    fail(f"heat weighting left {dry} proxy vertices without a bone")

for g in proxy.vertex_groups:
    body.vertex_groups.new(name=g.name)
dt = body.modifiers.new("weights", "DATA_TRANSFER")
dt.object, dt.use_vert_data, dt.data_types_verts = proxy, True, {"VGROUP_WEIGHTS"}
dt.vert_mapping = "POLYINTERP_NEAREST"
dt.layers_vgroup_select_src, dt.layers_vgroup_select_dst = "ALL", "NAME"
for o in bpy.context.view_layer.objects:
    o.select_set(o == body)
bpy.context.view_layer.objects.active = body
bpy.ops.object.modifier_apply(modifier="weights")
bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
bpy.ops.object.vertex_group_normalize_all(group_select_mode="ALL", lock_active=False)
dry = sum(1 for v in body.data.vertices if not any(g.weight > 1e-4 for g in v.groups))
if dry:
    fail(f"{dry} body vertices took no weight")
bpy.data.objects.remove(proxy)
body.parent = rig
body.modifiers.new("Armature", "ARMATURE").object = rig

for o in bpy.context.view_layer.objects:
    o.select_set(o in (rig, body))
bpy.context.view_layer.objects.active = rig
os.makedirs(os.path.dirname(JOB["out"]), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=JOB["out"], export_format="GLB", use_selection=True,
                          export_animations=False, export_skins=True, export_yup=True)
report["triangles"] = len(me.loop_triangles)
print("RIG-REPORT " + json.dumps(report))
print("RIG-DONE")
