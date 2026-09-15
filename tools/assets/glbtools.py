"""GLB (glTF 2.0 binary) helpers shared by the asset pipeline. Stdlib only, so the same module
runs under Blender's Python (merge_stages.py) and the system `py` (upload_models.py,
vip_palette.py).

Lifted from the 2026-09-15 pipeline trial (assets/research/2026-09-15/glb-trial/glb_trial.py):
parse/write, image embedding, validation, bounds, plus the Roblox import constraints that trial
established (section 3 of docs/ASSET_RESEARCH.md).
"""

from __future__ import annotations

import io
import json
import math
import struct

GLB_MAGIC = 0x46546C67
CHUNK_JSON = 0x4E4F534A
CHUNK_BIN = 0x004E4942
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
# Open Cloud rejects model files above this size.
ROBLOX_MAX_BYTES = 20 * 1024 * 1024

FLOAT = 5126
UNSIGNED_INT = 5125
UNSIGNED_SHORT = 5123


class GlbError(ValueError):
    pass


# ---------------------------------------------------------------- read / write


def parse_glb(data: bytes) -> tuple[dict, bytes]:
    if len(data) < 12:
        raise GlbError("file shorter than a GLB header")
    magic, version, length = struct.unpack_from("<III", data, 0)
    if magic != GLB_MAGIC:
        raise GlbError("not a GLB (bad magic)")
    if version != 2:
        raise GlbError(f"GLB version {version}, expected 2")
    if length != len(data):
        raise GlbError(f"header length {length} != file length {len(data)}")
    offset = 12
    doc = None
    binary = b""
    while offset < length:
        clen, ctype = struct.unpack_from("<II", data, offset)
        body = data[offset + 8 : offset + 8 + clen]
        if len(body) != clen:
            raise GlbError("truncated chunk")
        if clen % 4:
            raise GlbError(f"chunk 0x{ctype:08x} is not 4-byte aligned ({clen})")
        if ctype == CHUNK_JSON:
            doc = json.loads(body.decode("utf-8"))
        elif ctype == CHUNK_BIN:
            binary = body
        offset += 8 + clen
    if doc is None:
        raise GlbError("no JSON chunk")
    return doc, binary


def pad4(buf: bytes, fill: bytes) -> bytes:
    return buf + fill * ((4 - len(buf) % 4) % 4)


def write_glb(doc: dict, binary: bytes) -> bytes:
    json_bytes = pad4(json.dumps(doc, separators=(",", ":")).encode("utf-8"), b" ")
    bin_bytes = pad4(binary, b"\x00")
    total = 12 + 8 + len(json_bytes) + (8 + len(bin_bytes) if bin_bytes else 0)
    out = io.BytesIO()
    out.write(struct.pack("<III", GLB_MAGIC, 2, total))
    out.write(struct.pack("<II", len(json_bytes), CHUNK_JSON))
    out.write(json_bytes)
    if bin_bytes:
        out.write(struct.pack("<II", len(bin_bytes), CHUNK_BIN))
        out.write(bin_bytes)
    return out.getvalue()


def embed_images(data: bytes, resolve: "callable") -> tuple[bytes, list[str]]:
    """Move every external image (a `uri` on images[]) into the BIN chunk.

    `resolve(uri) -> bytes` supplies the PNG for a uri, so a caller can substitute a recoloured
    colormap for the kit's own file (the VIP swatch does exactly that).
    """
    doc, binary = parse_glb(data)
    images = doc.get("images") or []
    external = [i for i, img in enumerate(images) if "uri" in img]
    if not external:
        return data, []
    binary = bytearray(pad4(bytes(binary), b"\x00"))
    notes: list[str] = []
    for i in external:
        img = images[i]
        uri = img.pop("uri")
        if uri.startswith("data:"):
            raise GlbError("data: image URIs are not handled")
        png = resolve(uri)
        if png[:8] != PNG_SIGNATURE:
            raise GlbError(f"{uri} is not a PNG")
        while len(binary) % 4:
            binary.append(0)
        view_index = len(doc.setdefault("bufferViews", []))
        doc["bufferViews"].append({"buffer": 0, "byteOffset": len(binary), "byteLength": len(png)})
        binary.extend(png)
        img["bufferView"] = view_index
        img["mimeType"] = "image/png"
        notes.append(f"image[{i}] {uri} ({len(png)} B) -> bufferView {view_index}")
    while len(binary) % 4:
        binary.append(0)
    doc["buffers"][0]["byteLength"] = len(binary)
    return write_glb(doc, bytes(binary)), notes


# ---------------------------------------------------------------- validation


def validate(data: bytes) -> dict:
    """Structural checks; raises GlbError on the first problem, returns the JSON document."""
    doc, binary = parse_glb(data)
    buffers = doc.get("buffers") or []
    if len(buffers) != 1 or "uri" in buffers[0]:
        raise GlbError("expected exactly one internal buffer")
    if buffers[0]["byteLength"] > len(binary):
        raise GlbError("buffer byteLength exceeds the BIN chunk")
    for bv in doc.get("bufferViews", []):
        end = bv.get("byteOffset", 0) + bv["byteLength"]
        if end > len(binary):
            raise GlbError(f"bufferView overruns BIN ({end} > {len(binary)})")
    for img in doc.get("images") or []:
        if "uri" in img:
            raise GlbError(f"external image left: {img['uri']}")
        bv = doc["bufferViews"][img["bufferView"]]
        start = bv.get("byteOffset", 0)
        if binary[start : start + 8] != PNG_SIGNATURE:
            raise GlbError("embedded image is not a PNG")
    return doc


def reachable_nodes(doc: dict) -> set[int]:
    scene = doc["scenes"][doc.get("scene", 0)]
    seen: set[int] = set()
    stack = list(scene.get("nodes", []))
    while stack:
        n = stack.pop()
        if n in seen:
            continue
        seen.add(n)
        stack.extend(doc["nodes"][n].get("children", []))
    return seen


def roblox_problems(data: bytes) -> list[str]:
    """Everything the 2026-09-15 trial showed Roblox's importer rejects or mangles.

    Returns one line per problem (empty = importable): size cap, external images, scene roots
    that are also somebody's child (the space-kit `tmpParent` defect, "Failed to parse"), nodes
    outside the scene, unused meshes, and material colours without a texture (Roblox drops them).
    """
    problems: list[str] = []
    if len(data) > ROBLOX_MAX_BYTES:
        problems.append(f"{len(data)} bytes exceeds the {ROBLOX_MAX_BYTES} byte Open Cloud limit")
    try:
        doc = validate(data)
    except GlbError as exc:
        return problems + [str(exc)]
    scene = doc["scenes"][doc.get("scene", 0)]
    children = {c for n in doc["nodes"] for c in n.get("children", [])}
    for root in scene.get("nodes", []):
        if root in children:
            problems.append(f"scene root node {root} {doc['nodes'][root].get('name')!r} is also a child node")
    reach = reachable_nodes(doc)
    for i, node in enumerate(doc["nodes"]):
        if i not in reach:
            problems.append(f"node {i} {node.get('name')!r} is not reachable from the scene")
    used_meshes = {n["mesh"] for n in doc["nodes"] if "mesh" in n}
    for i in range(len(doc.get("meshes", []))):
        if i not in used_meshes:
            problems.append(f"mesh {i} is unused")
    for i, mat in enumerate(doc.get("materials", [])):
        pbr = mat.get("pbrMetallicRoughness") or {}
        if "baseColorTexture" not in pbr:
            problems.append(f"material {i} {mat.get('name')!r} has no baseColorTexture (Roblox drops colour factors)")
    return problems


# ---------------------------------------------------------------- bounds


def mat_mul(a: list[float], b: list[float]) -> list[float]:
    r = [0.0] * 16
    for c in range(4):
        for row in range(4):
            r[c * 4 + row] = sum(a[k * 4 + row] * b[c * 4 + k] for k in range(4))
    return r


def trs_matrix(node: dict) -> list[float]:
    if "matrix" in node:
        return list(node["matrix"])
    tx, ty, tz = node.get("translation", [0, 0, 0])
    qx, qy, qz, qw = node.get("rotation", [0, 0, 0, 1])
    sx, sy, sz = node.get("scale", [1, 1, 1])
    r00 = 1 - 2 * (qy * qy + qz * qz)
    r01 = 2 * (qx * qy - qz * qw)
    r02 = 2 * (qx * qz + qy * qw)
    r10 = 2 * (qx * qy + qz * qw)
    r11 = 1 - 2 * (qx * qx + qz * qz)
    r12 = 2 * (qy * qz - qx * qw)
    r20 = 2 * (qx * qz - qy * qw)
    r21 = 2 * (qy * qz + qx * qw)
    r22 = 1 - 2 * (qx * qx + qy * qy)
    return [r00 * sx, r10 * sx, r20 * sx, 0, r01 * sy, r11 * sy, r21 * sy, 0, r02 * sz, r12 * sz, r22 * sz, 0, tx, ty, tz, 1]


def apply(m: list[float], p: tuple[float, float, float]) -> tuple[float, float, float]:
    x, y, z = p
    return (
        m[0] * x + m[4] * y + m[8] * z + m[12],
        m[1] * x + m[5] * y + m[9] * z + m[13],
        m[2] * x + m[6] * y + m[10] * z + m[14],
    )


def read_positions(doc: dict, binary: bytes, accessor_index: int) -> list[tuple[float, float, float]]:
    acc = doc["accessors"][accessor_index]
    if acc["componentType"] != FLOAT or acc["type"] != "VEC3":
        raise GlbError("POSITION accessor is not float VEC3")
    bv = doc["bufferViews"][acc["bufferView"]]
    stride = bv.get("byteStride", 12)
    base = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    return [struct.unpack_from("<fff", binary, base + i * stride) for i in range(acc["count"])]


def node_bounds(data: bytes) -> dict[str, dict]:
    """Per scene-root node: vertex bounds (glTF units, Y up), triangle and primitive counts."""
    doc, binary = parse_glb(data)
    scene = doc["scenes"][doc.get("scene", 0)]
    out: dict[str, dict] = {}

    def visit(index: int, parent: list[float], acc: dict) -> None:
        node = doc["nodes"][index]
        world = mat_mul(parent, trs_matrix(node))
        if "mesh" in node:
            for prim in doc["meshes"][node["mesh"]]["primitives"]:
                acc["primitives"] += 1
                if "indices" in prim:
                    acc["triangles"] += doc["accessors"][prim["indices"]]["count"] // 3
                for p in read_positions(doc, binary, prim["attributes"]["POSITION"]):
                    w = apply(world, p)
                    for i in range(3):
                        acc["min"][i] = min(acc["min"][i], w[i])
                        acc["max"][i] = max(acc["max"][i], w[i])
        for child in node.get("children", []):
            visit(child, world, acc)

    for root in scene.get("nodes", []):
        acc = {"min": [math.inf] * 3, "max": [-math.inf] * 3, "triangles": 0, "primitives": 0}
        visit(root, trs_matrix({}), acc)
        name = doc["nodes"][root].get("name", f"node{root}")
        if acc["primitives"] == 0:
            continue
        out[name] = {
            "min": [round(v, 4) for v in acc["min"]],
            "max": [round(v, 4) for v in acc["max"]],
            "size": [round(acc["max"][i] - acc["min"][i], 4) for i in range(3)],
            "triangles": acc["triangles"],
            "primitives": acc["primitives"],
        }
    return out


# ---------------------------------------------------------------- tiny writer


def make_textured_quad_glb(png: bytes, name: str, size: float = 1.0) -> bytes:
    """A one-quad GLB (bottom-centre origin, facing -Z) whose whole UV square shows `png`.

    Used for the VIP swatch of palette kits: the only thing Roblox has to hand back is the Image
    asset it splits out of the texture, so the geometry just needs to be valid and visible.
    """
    h = size / 2
    positions = [(-h, 0.0, 0.0), (h, 0.0, 0.0), (h, size, 0.0), (-h, size, 0.0)]
    normals = [(0.0, 0.0, -1.0)] * 4
    uvs = [(0.0, 1.0), (1.0, 1.0), (1.0, 0.0), (0.0, 0.0)]
    indices = [0, 2, 1, 0, 3, 2]
    binary = bytearray()
    views = []

    def add_view(blob: bytes, target: int | None, stride: int | None = None) -> int:
        while len(binary) % 4:
            binary.append(0)
        view = {"buffer": 0, "byteOffset": len(binary), "byteLength": len(blob)}
        if target is not None:
            view["target"] = target
        if stride is not None:
            view["byteStride"] = stride
        views.append(view)
        binary.extend(blob)
        return len(views) - 1

    pos_view = add_view(b"".join(struct.pack("<fff", *p) for p in positions), 34962, 12)
    nrm_view = add_view(b"".join(struct.pack("<fff", *n) for n in normals), 34962, 12)
    uv_view = add_view(b"".join(struct.pack("<ff", *t) for t in uvs), 34962, 8)
    idx_view = add_view(b"".join(struct.pack("<H", i) for i in indices), 34963)
    img_view = add_view(png, None)
    accessors = [
        {"bufferView": pos_view, "componentType": FLOAT, "count": 4, "type": "VEC3", "min": [-h, 0.0, 0.0], "max": [h, size, 0.0]},
        {"bufferView": nrm_view, "componentType": FLOAT, "count": 4, "type": "VEC3"},
        {"bufferView": uv_view, "componentType": FLOAT, "count": 4, "type": "VEC2"},
        {"bufferView": idx_view, "componentType": UNSIGNED_SHORT, "count": 6, "type": "SCALAR"},
    ]
    doc = {
        "asset": {"version": "2.0", "generator": "EraCityTycoon glbtools"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"name": name, "mesh": 0}],
        "meshes": [{"name": name, "primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2}, "indices": 3, "material": 0}]}],
        "materials": [
            {
                "name": name,
                "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "metallicFactor": 0.0, "roughnessFactor": 1.0},
                "doubleSided": True,
            }
        ],
        "textures": [{"source": 0, "sampler": 0}],
        "samplers": [{"magFilter": 9728, "minFilter": 9728, "wrapS": 33071, "wrapT": 33071}],
        "images": [{"name": name, "mimeType": "image/png", "bufferView": img_view}],
        "bufferViews": views,
        "accessors": accessors,
        "buffers": [{"byteLength": len(pad4(bytes(binary), b"\x00"))}],
    }
    return write_glb(doc, bytes(binary))
