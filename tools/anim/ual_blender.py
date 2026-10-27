# Blender 5.2 side of tools/anim/animate.py. Never run directly: the launcher writes a job JSON and calls
#   blender -b --python tools/anim/ual_blender.py -- <job.json>
#
# Two modes:
#   catalogue  measure every clip of the Universal Animation Library (length, contact moment, drift)
#   build      retarget chosen clips onto a Tripo character with a Mixamo skeleton, retime each attack
#              so its contact lands on the game's windup, self-check, export and render previews
#
# Retargeting rule: both rigs rest in a T-pose facing -Y, so each target bone takes its source bone's
# WORLD rotation change from rest (independent of bone roll), and the hips' travel is scaled by the
# ratio of hip heights. The asserts in check_rest() protect that assumption.
import bpy, sys, os, json, math
from mathutils import Vector, Matrix

JOB = json.load(open(sys.argv[sys.argv.index("--") + 1], encoding="utf-8"))
SRC_FPS = 24  # the UAL GLB imports at Blender's 24 fps; its actions are keyed in those frames

MAP = {
    "Hips": "pelvis", "Spine": "spine_01", "Spine1": "spine_02", "Spine2": "spine_03", "Neck": "neck_01", "Head": "Head",
    "LeftShoulder": "clavicle_l", "LeftArm": "upperarm_l", "LeftForeArm": "lowerarm_l", "LeftHand": "hand_l",
    "RightShoulder": "clavicle_r", "RightArm": "upperarm_r", "RightForeArm": "lowerarm_r", "RightHand": "hand_r",
    "LeftUpLeg": "thigh_l", "LeftLeg": "calf_l", "LeftFoot": "foot_l", "LeftToeBase": "ball_l",
    "RightUpLeg": "thigh_r", "RightLeg": "calf_r", "RightFoot": "foot_r", "RightToeBase": "ball_r",
}
FINGERS = ("Thumb", "Index", "Middle", "Ring", "Pinky")


def fail(msg):
    print("ANIM-FAIL", msg)
    sys.exit(2)


def import_glb(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    for o in list(new):
        # the glTF importer leaves a parentless default mesh in an empty scene
        if o.type == "MESH" and o.parent is None:
            bpy.data.objects.remove(o)
            new.remove(o)
    arm = [o for o in new if o.type == "ARMATURE"]
    meshes = [o for o in new if o.type == "MESH"]
    if len(arm) != 1 or not meshes:
        fail(f"{path}: expected one armature and a skinned mesh, found {len(arm)} armatures, {len(meshes)} meshes")
    return arm[0], meshes


def wrot(obj, m):
    return (obj.matrix_world @ m).to_quaternion().normalized()


bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
src, _src_meshes = import_glb(JOB["library"])
SRC_ACTIONS = {a.name: a for a in bpy.data.actions}
src.animation_data_create()


def action_frames(act):
    return int(act.frame_range[0]), int(round(act.frame_range[1]))


def src_pose_at(act, seconds):
    f0, _ = action_frames(act)
    f = f0 + seconds * SRC_FPS
    scene.frame_set(int(math.floor(f)), subframe=f - math.floor(f))


# ---------------------------------------------------------------- catalogue
def measure(act):
    """Contact = peak hand speed relative to the pelvis (a swing, punch, throw or shot peaks at release)."""
    src.animation_data.action = act
    f0, f1 = action_frames(act)
    pelvis0 = None
    rows = []
    for f in range(f0, f1 + 1):
        scene.frame_set(f)
        mw = src.matrix_world
        p = mw @ src.pose.bones["pelvis"].head
        hands = [mw @ src.pose.bones[h].head - p for h in ("hand_l", "hand_r")]
        feet = min((mw @ src.pose.bones[b].head).z for b in ("ball_l", "ball_r", "foot_l", "foot_r"))
        pelvis0 = pelvis0 or p.copy()
        rows.append((f, hands, p, feet))
    best = (0.0, f0, "-")
    for i in range(1, len(rows)):
        for k, side in ((0, "L"), (1, "R")):
            v = (rows[i][1][k] - rows[i - 1][1][k]).length * SRC_FPS
            if v > best[0]:
                best = (v, rows[i][0], side)
    travel = max(((r[2] - pelvis0) * Vector((1, 1, 0))).length for r in rows)
    return {
        "clip": act.name, "frames": f1 - f0 + 1, "seconds": round((f1 - f0) / SRC_FPS, 3),
        "contact": round((best[1] - f0) / SRC_FPS, 3), "hand": best[2], "handSpeed": round(best[0], 2),
        "pelvisTravel": round(travel, 3), "minFoot": round(min(r[3] for r in rows), 3),
    }


if JOB["mode"] == "catalogue":
    out = [measure(a) for a in sorted(SRC_ACTIONS.values(), key=lambda a: a.name)]
    json.dump(out, open(JOB["out"], "w", encoding="utf-8"), indent=1)
    print("ANIM-DONE catalogue", len(out))
    sys.exit(0)

# ---------------------------------------------------------------- build: load and check the character
arm, meshes = import_glb(JOB["character"])
body = max(meshes, key=lambda o: len(o.data.polygons))
for a in list(bpy.data.actions):
    if a.name not in SRC_ACTIONS:
        bpy.data.actions.remove(a)

names = {b.name.replace("mixamorig:", "") for b in arm.data.bones}
missing = sorted(set(MAP) - names)
if missing:
    fail(f"character skeleton is not Mixamo (missing {missing}); regenerate in Tripo with the Mixamo preset")
tris = sum(len(p.vertices) - 2 for m in meshes for p in m.data.polygons)


def check_rest():
    bones = arm.data.bones
    for side, sign in (("Left", 1), ("Right", -1)):
        b = bones.get(f"mixamorig:{side}Arm") or bones[f"{side}Arm"]
        d = (b.tail_local - b.head_local).normalized()
        if d.x * sign < 0.85:
            fail(f"{side}Arm rests at {tuple(round(c, 2) for c in d)}: the character must rest in a T-pose")
    toe = bones.get("mixamorig:LeftToeBase") or bones["LeftToeBase"]
    if (toe.tail_local - toe.head_local).y > 0:
        fail("the feet point +Y: the character must face -Y (glTF +Z), like the library")


check_rest()

# --- slim to 22 bones: fingers fold into the hands, end bones go (nothing animates them in game) ---
for g in list(body.vertex_groups):
    if any(f in g.name for f in FINGERS):
        side = "Left" if "Left" in g.name else "Right"
        hand = body.vertex_groups.get(f"mixamorig:{side}Hand") or body.vertex_groups[f"{side}Hand"]
        for v in body.data.vertices:
            for e in v.groups:
                if e.group == g.index and e.weight > 0:
                    hand.add([v.index], e.weight, "ADD")
        body.vertex_groups.remove(g)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="EDIT")
for eb in list(arm.data.edit_bones):
    if any(f in eb.name for f in FINGERS) or eb.name.endswith("_End"):
        arm.data.edit_bones.remove(eb)
bpy.ops.object.mode_set(mode="OBJECT")
for b in arm.data.bones:
    b.name = b.name.replace("mixamorig:", "")
ORDER = [b.name for b in arm.data.bones]
extra = sorted(set(ORDER) - set(MAP))
if extra:
    fail(f"unexpected bones after slimming: {extra}")
for pb in arm.pose.bones:
    pb.rotation_mode = "QUATERNION"

bbox = [body.matrix_world @ Vector(c) for c in body.bound_box]
HEIGHT = max(v.z for v in bbox) - min(v.z for v in bbox)
SRC_REST = {s: wrot(src, src.data.bones[s].matrix_local) for s in MAP.values()}
TGT_REST = {t: wrot(arm, arm.data.bones[t].matrix_local) for t in MAP}
SRC_HIP0 = src.matrix_world @ src.data.bones["pelvis"].head_local
TGT_HIP0 = arm.data.bones["Hips"].head_local.copy()
HIP_SCALE = TGT_HIP0.z / SRC_HIP0.z
FOOT_REST = min(arm.data.bones[b].head_local.z for b in ("LeftToeBase", "RightToeBase", "LeftFoot", "RightFoot"))


def clip_seconds(act):
    f0, f1 = action_frames(act)
    return (f1 - f0) / SRC_FPS


def time_map(entry):
    """Map output seconds to (source action, source seconds) and give the output length.

    Retimed attacks pin the source contact to the game's windup: the source's [0, contact] plays over
    the windup and the rest at its own speed. Clips that start at their release (a throw, a shot) name
    a `lead` clip, which is stretched over the whole windup before the release clip plays from contact.
    """
    act = SRC_ACTIONS[entry["clip"]]
    seconds = clip_seconds(act)
    w, c = entry.get("windup"), entry.get("contact") or 0.0
    if w is None:
        return (lambda t: (act, min(t, seconds))), seconds
    lead = SRC_ACTIONS[entry["lead"]] if entry.get("lead") else None
    if lead is not None:
        ls = clip_seconds(lead)
        return (lambda t: (lead, t * ls / w) if t < w else (act, min(c + t - w, seconds))), w + seconds - c
    if c <= 0:
        fail(f"{entry['slot']}: {entry['clip']} has no wind-up before its contact; give it a lead clip")
    return (lambda t: (act, t * c / w) if t <= w else (act, min(c + t - w, seconds))), w + seconds - c


def pose_target():
    for t in ORDER:
        s = MAP[t]
        d = wrot(src, src.pose.bones[s].matrix) @ SRC_REST[s].inverted()
        m = (arm.matrix_world.to_quaternion().inverted() @ d @ TGT_REST[t]).to_matrix().to_4x4()
        pb = arm.pose.bones[t]
        if t == "Hips":
            hip = src.matrix_world @ src.pose.bones["pelvis"].head
            m.translation = TGT_HIP0 + (hip - SRC_HIP0) * HIP_SCALE
        else:
            m.translation = pb.head
        pb.matrix = m
        bpy.context.view_layer.update()


FPS = JOB.get("fps", 30)
scene.render.fps = FPS
arm.animation_data_create()
actions, report = {}, []
for entry in JOB["clips"]:
    for k in ("clip", "lead"):
        if entry.get(k) and entry[k] not in SRC_ACTIONS:
            fail(f"clip {entry[k]} is not in the library")
    tmap, out_seconds = time_map(entry)
    n = max(1, round(out_seconds * FPS))
    ta = bpy.data.actions.new(entry["slot"])
    ta.use_fake_user = True
    arm.animation_data.action = ta
    prev, lowest, drift = {}, 1e9, 0.0
    for i in range(n + 1):
        sa, st = tmap(i / FPS)
        src.animation_data.action = sa
        src_pose_at(sa, st)
        pose_target()
        for t in ORDER:
            pb = arm.pose.bones[t]
            q = pb.rotation_quaternion.copy()
            if t in prev and q.dot(prev[t]) < 0:  # one hemisphere per bone, or playback spins between keys
                q.negate()
                pb.rotation_quaternion = q
            prev[t] = q
            pb.keyframe_insert("rotation_quaternion", frame=i)
        arm.pose.bones["Hips"].keyframe_insert("location", frame=i)
        feet = min(arm.pose.bones[b].head.z for b in ("LeftToeBase", "RightToeBase", "LeftFoot", "RightFoot"))
        lowest = min(lowest, feet - FOOT_REST)
        hip = arm.pose.bones["Hips"].head
        drift = max(drift, math.hypot(hip.x - TGT_HIP0.x, hip.y - TGT_HIP0.y))
    ta.frame_range = (0, n)
    ta.use_frame_range = True
    ta.use_cyclic = bool(entry.get("loop"))
    actions[entry["slot"]] = ta
    row = {"slot": entry["slot"], "clip": entry["clip"], "frames": n + 1, "seconds": round(n / FPS, 3),
           "sinkStuds": round(-lowest / HEIGHT, 3) if lowest < 0 else 0.0, "drift": round(drift / HEIGHT, 3),
           "loop": bool(entry.get("loop"))}
    if entry.get("windup") is not None:
        row["windup"] = entry["windup"]
        row["lead"] = entry.get("lead")
    report.append(row)
    print("ANIM-CLIP", json.dumps(row))

OUT = JOB["out"]
os.makedirs(OUT, exist_ok=True)
stem = JOB["name"]


def select(objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)


# the rig alone (Studio imports it once), every clip in one GLB for any viewer, one FBX per clip for
# Studio's "Import From FBX Animation"; weapons are never baked in: the game hangs them from the hand
arm.animation_data.action = None
for pb in arm.pose.bones:
    pb.rotation_quaternion = (1, 0, 0, 0)
    pb.location = (0, 0, 0)
select([arm, *meshes])
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, f"{stem}_rig.glb"), use_selection=True, export_animations=False)
# one NLA track per slot: ACTIONS mode would also export every library clip, sampled as the rest pose
tracks = []
for slot, act in actions.items():
    track = arm.animation_data.nla_tracks.new()
    track.name = slot
    track.strips.new(slot, int(act.frame_range[0]), act)
    tracks.append(track)
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, f"{stem}_all.glb"), use_selection=True,
                          export_animation_mode="NLA_TRACKS")
for track in tracks:
    arm.animation_data.nla_tracks.remove(track)
for slot, act in actions.items():
    arm.animation_data.action = act
    scene.frame_start, scene.frame_end = 0, int(act.frame_range[1])
    select([arm, *meshes])
    bpy.ops.export_scene.fbx(filepath=os.path.join(OUT, f"{stem}_{slot}.fbx"), use_selection=True,
                             bake_anim=True, bake_anim_use_all_actions=False, bake_anim_use_nla_strips=False,
                             add_leaf_bones=False)

json.dump({"character": JOB["character"], "role": JOB.get("role"), "bones": len(ORDER), "triangles": tris,
           "height": round(HEIGHT, 3), "fps": FPS, "clips": report},
          open(os.path.join(OUT, "report.json"), "w", encoding="utf-8"), indent=1)

if not JOB.get("render"):
    print("ANIM-DONE build")
    sys.exit(0)


# ---------------------------------------------------------------- previews
def mat(name, rgb):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*rgb, 1)
    bsdf.inputs["Roughness"].default_value = 0.9
    return m


if JOB.get("placeholder") == "hammer":
    # grey stand-in, handle leaving the thumb side; only in the previews
    rh = arm.data.bones["RightHand"]
    a0 = (rh.tail_local - rh.head_local).normalized()
    h0 = (Vector((0, -1, 0)) - Vector((0, -1, 0)).dot(a0) * a0).normalized()
    frame = Matrix((a0, h0, a0.cross(h0))).transposed()
    k = HEIGHT / 0.93  # sized on the first test character (0.93 tall)
    for name, size, along, rgb in (("Handle", (0.025, 0.5, 0.025), 0.17, (0.25, 0.13, 0.06)),
                                   ("Head", (0.11, 0.11, 0.2), 0.42, (0.45, 0.45, 0.43))):
        bpy.ops.mesh.primitive_cube_add(size=1)
        o = bpy.context.active_object
        o.scale = [s * k for s in size]
        o.location = rh.tail_local + h0 * along * k
        o.rotation_euler = frame.to_euler()
        o.data.materials.append(mat(name, rgb))
        arm.animation_data.action = None
        for pb in arm.pose.bones:
            pb.rotation_quaternion = (1, 0, 0, 0)
            pb.location = (0, 0, 0)
        bpy.context.view_layer.update()
        mw = o.matrix_world.copy()
        o.parent, o.parent_type, o.parent_bone = arm, "BONE", "RightHand"
        bpy.context.view_layer.update()
        o.matrix_world = mw

# the library's mannequin plays the source clip beside the character, scaled to its height: the
# reviewer's check that the retarget is faithful
src_h = (src.matrix_world @ src.data.bones["Head"].tail_local).z
src.scale = [HEIGHT / src_h] * 3
src.location = (HEIGHT * 1.2, 0, 0)
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x, scene.render.resolution_y = 560, 360
world = bpy.data.worlds.new("w")
scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.2, 0.21, 0.24, 1)
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
scene.collection.objects.link(sun)
sun.rotation_euler = (0.9, 0.3, -0.5)
sun.data.energy = 3.5
g = HEIGHT * 4
floor = bpy.data.meshes.new("floor")
floor.from_pydata([(-g, -g, 0), (g, -g, 0), (g, g, 0), (-g, g, 0)], [], [(0, 1, 2, 3)])
fo = bpy.data.objects.new("floor", floor)
scene.collection.objects.link(fo)
fo.data.materials.append(mat("ground", (0.32, 0.4, 0.25)))
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
scene.collection.objects.link(cam)
scene.camera = cam
cam.data.type = "ORTHO"
cam.data.ortho_scale = HEIGHT * 3.1
mid = HEIGHT * 0.6
tgt = bpy.data.objects.new("tgt", None)
scene.collection.objects.link(tgt)
tgt.location = (mid, 0, HEIGHT * 0.54)
cam.location = (mid - HEIGHT * 2.4, -HEIGHT * 3.2, HEIGHT * 1.6)
c = cam.constraints.new("TRACK_TO")
c.target, c.track_axis, c.up_axis = tgt, "TRACK_NEGATIVE_Z", "UP_Y"

for entry, row in zip(JOB["clips"], report):
    act = actions[row["slot"]]
    tmap, _ = time_map(entry)
    arm.animation_data.action = act
    for i in range(0, int(act.frame_range[1]) + 1, 2):
        # one scene clock drives both rigs, so the mannequin is posed at its mapped source time, frozen,
        # and then the clock moves to the character's frame
        sa, st = tmap(i / FPS)
        src.animation_data.action = sa
        src_pose_at(sa, st)
        snap = [(pb, pb.rotation_quaternion.copy(), pb.location.copy()) for pb in src.pose.bones]
        src.animation_data.action = None
        for pb, q, loc in snap:
            pb.rotation_quaternion, pb.location = q, loc
        scene.frame_set(i)
        scene.render.filepath = os.path.join(OUT, "frames", row["slot"], f"{i:03d}.png")
        bpy.ops.render.render(write_still=True)
print("ANIM-DONE build")
