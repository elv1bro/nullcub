#!/usr/bin/env python3
"""Grey-box glTF models for the Ragdoll Master demo (stage 02).

Pure Python + numpy: writes .glb files into godot/assets/models/.
Conventions (docs/plan-demo/02-models.md): metres, Y up, character faces +X,
each doll part has its origin at the joint that attaches it to its parent.
Left side = +Z, right side = -Z.
"""
import json, math, os, struct, sys
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "models")
os.makedirs(OUT, exist_ok=True)
os.makedirs(os.path.join(OUT, "parts"), exist_ok=True)

def hexc(h, a=1.0):
    h = h.lstrip("#")
    return [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)] + [a]

MATERIALS = {
    "Wood": hexc("d9a86c"), "WoodDark": hexc("a9713a"), "Shirt": hexc("2f6fde"), "Face": hexc("f1d9c0"),
    "Joint": hexc("3b2a1a"), "Iron": hexc("6b7280"), "IronDark": hexc("374151"), "Gold": hexc("e8b820"),
    "Red": hexc("d9342b"), "Yellow": hexc("f2c200"), "Orange": hexc("f28c28"), "Stone": hexc("b8ab96"),
    "StoneDark": hexc("7a6a58"), "Cloth": hexc("c9b9a2"), "Rope": hexc("b08a5a"), "Blue": hexc("2f6fde"),
    "Bone": hexc("f1e6cf"), "Dark": hexc("2b2118"), "Collision": hexc("f28c28", 0.5),
}
MAT_INDEX = {k: i for i, k in enumerate(MATERIALS)}

# ---------------- primitive meshes (positions, normals, indices) ----------------
def _mesh(pos, nrm, idx):
    return (np.asarray(pos, np.float32).reshape(-1, 3), np.asarray(nrm, np.float32).reshape(-1, 3), np.asarray(idx, np.uint32).ravel())

def m_box(w, h, d, center=(0, 0, 0)):
    cx, cy, cz = center
    x, y, z = w / 2, h / 2, d / 2
    faces = [  # normal, 4 corners
        ((1, 0, 0), [(x, -y, -z), (x, y, -z), (x, y, z), (x, -y, z)]),
        ((-1, 0, 0), [(-x, -y, z), (-x, y, z), (-x, y, -z), (-x, -y, -z)]),
        ((0, 1, 0), [(-x, y, -z), (-x, y, z), (x, y, z), (x, y, -z)]),
        ((0, -1, 0), [(-x, -y, z), (-x, -y, -z), (x, -y, -z), (x, -y, z)]),
        ((0, 0, 1), [(-x, -y, z), (x, -y, z), (x, y, z), (-x, y, z)]),
        ((0, 0, -1), [(x, -y, -z), (-x, -y, -z), (-x, y, -z), (x, y, -z)]),
    ]
    pos, nrm, idx = [], [], []
    for n, quad in faces:
        b = len(pos)
        for p in quad:
            pos.append((p[0] + cx, p[1] + cy, p[2] + cz))
            nrm.append(n)
        idx += [b, b + 1, b + 2, b, b + 2, b + 3]
    return _mesh(pos, nrm, idx)

def m_sphere(r, center=(0, 0, 0), seg=24, rings=12, keep=None):
    """UV sphere; keep(x,y,z)->bool filters triangles (all 3 vertices must pass) for caps."""
    cx, cy, cz = center
    pos, nrm, idx = [], [], []
    for i in range(rings + 1):
        phi = math.pi * i / rings
        for j in range(seg + 1):
            th = 2 * math.pi * j / seg
            n = (math.sin(phi) * math.cos(th), math.cos(phi), math.sin(phi) * math.sin(th))
            pos.append((cx + r * n[0], cy + r * n[1], cz + r * n[2]))
            nrm.append(n)
    def ok(a, b, c):
        if keep is None:
            return True
        return all(keep(*[pos[k][0] - cx, pos[k][1] - cy, pos[k][2] - cz]) for k in (a, b, c))
    for i in range(rings):
        for j in range(seg):
            a = i * (seg + 1) + j
            b = a + seg + 1
            if ok(a, b, a + 1):
                idx += [a, b, a + 1]
            if ok(a + 1, b, b + 1):
                idx += [a + 1, b, b + 1]
    return _mesh(pos, nrm, idx)

def m_cylinder(r, h, center=(0, 0, 0), seg=24, axis="y", a0=0.0, a1=2 * math.pi, r_top=None):
    """Cylinder (or sector) along an axis, centred at center; r_top for cones/frustums."""
    rt = r if r_top is None else r_top
    pos, nrm, idx = [], [], []
    def to_axis(p):
        x, y, z = p
        if axis == "y":
            return (x, y, z)
        if axis == "x":
            return (y, x, z)
        return (x, z, y)
    def push(p, n):
        p2 = to_axis(p)
        n2 = to_axis(n)
        pos.append((p2[0] + center[0], p2[1] + center[1], p2[2] + center[2]))
        nrm.append(n2)
        return len(pos) - 1
    full = abs((a1 - a0) - 2 * math.pi) < 1e-6
    n_ang = seg if full else seg
    # side
    for j in range(n_ang + 1):
        th = a0 + (a1 - a0) * j / n_ang
        c, s = math.cos(th), math.sin(th)
        push((r * c, -h / 2, r * s), (c, 0, s))
        push((rt * c, h / 2, rt * s), (c, 0, s))
    for j in range(n_ang):
        a = 2 * j
        idx += [a, a + 2, a + 1, a + 1, a + 2, a + 3]
    # caps
    for sign, rr in ((-1, r), (1, rt)):
        cidx = push((0, sign * h / 2, 0), (0, sign, 0))
        ring = []
        for j in range(n_ang + 1):
            th = a0 + (a1 - a0) * j / n_ang
            ring.append(push((rr * math.cos(th), sign * h / 2, rr * math.sin(th)), (0, sign, 0)))
        for j in range(n_ang):
            if sign > 0:
                idx += [cidx, ring[j], ring[j + 1]]
            else:
                idx += [cidx, ring[j + 1], ring[j]]
    if not full:  # sector side walls (flat, unlit-correct enough for grey-box)
        for th, sgn in ((a0, -1), (a1, 1)):
            c, s = math.cos(th), math.sin(th)
            nn = (-s * sgn, 0, c * sgn)
            q = [push((0, -h / 2, 0), nn), push((r * c, -h / 2, r * s), nn), push((rt * c, h / 2, rt * s), nn), push((0, h / 2, 0), nn)]
            idx += [q[0], q[1], q[2], q[0], q[2], q[3]] if sgn > 0 else [q[0], q[2], q[1], q[0], q[3], q[2]]
    return _mesh(pos, nrm, idx)

def m_capsule(r, length, center=(0, 0, 0), axis="y", seg=16, rings=8):
    """Capsule of total length `length` along axis (cylinder + two hemispheres)."""
    cyl = max(length - 2 * r, 0.0)
    parts = [m_cylinder(r, cyl, (0, 0, 0), seg)]
    parts.append(m_sphere(r, (0, cyl / 2, 0), seg, rings, keep=lambda x, y, z: y >= -1e-6))
    parts.append(m_sphere(r, (0, -cyl / 2, 0), seg, rings, keep=lambda x, y, z: y <= 1e-6))
    pos, nrm, idx = merge(parts)
    if axis == "x":
        pos = pos[:, [1, 0, 2]] * np.array([1, 1, 1], np.float32)
        nrm = nrm[:, [1, 0, 2]]
        idx = idx.reshape(-1, 3)[:, ::-1].ravel()
    elif axis == "z":
        pos = pos[:, [0, 2, 1]]
        nrm = nrm[:, [0, 2, 1]]
        idx = idx.reshape(-1, 3)[:, ::-1].ravel()
    pos = pos + np.array(center, np.float32)
    return pos, nrm, idx

def merge(meshes):
    pos, nrm, idx, off = [], [], [], 0
    for p, n, i in meshes:
        pos.append(p); nrm.append(n); idx.append(i + off); off += len(p)
    return np.concatenate(pos), np.concatenate(nrm), np.concatenate(idx)

def translate(mesh, d):
    p, n, i = mesh
    return p + np.array(d, np.float32), n, i

def rotate_z(mesh, deg):
    p, n, i = mesh
    a = math.radians(deg)
    R = np.array([[math.cos(a), -math.sin(a), 0], [math.sin(a), math.cos(a), 0], [0, 0, 1]], np.float32)
    return p @ R.T, n @ R.T, i

def rotate_y(mesh, deg):
    p, n, i = mesh
    a = math.radians(deg)
    R = np.array([[math.cos(a), 0, math.sin(a)], [0, 1, 0], [-math.sin(a), 0, math.cos(a)]], np.float32)
    return p @ R.T, n @ R.T, i

# ---------------- glTF writer ----------------
class GLB:
    def __init__(self):
        self.bin = bytearray()
        self.views, self.accessors, self.meshes, self.nodes = [], [], [], []
        self.materials = [{"name": k, "pbrMetallicRoughness": {"baseColorFactor": v, "metallicFactor": 0.0, "roughnessFactor": 0.85},
                           **({"alphaMode": "BLEND"} if v[3] < 1 else {})} for k, v in MATERIALS.items()]
    def _acc(self, arr, ctype, atype, target, minmax=False):
        while len(self.bin) % 4:
            self.bin.append(0)
        data = arr.tobytes()
        self.views.append({"buffer": 0, "byteOffset": len(self.bin), "byteLength": len(data), "target": target})
        self.bin += data
        acc = {"bufferView": len(self.views) - 1, "componentType": ctype, "count": len(arr) if arr.ndim == 1 else arr.shape[0], "type": atype}
        if minmax:
            acc["min"] = [float(v) for v in arr.min(axis=0)]
            acc["max"] = [float(v) for v in arr.max(axis=0)]
        self.accessors.append(acc)
        return len(self.accessors) - 1
    def mesh(self, name, prims):
        """prims: list of (mesh_tuple, material_name)"""
        out = {"name": name, "primitives": []}
        for (pos, nrm, idx), mat in prims:
            if len(idx) == 0:
                continue
            out["primitives"].append({
                "attributes": {"POSITION": self._acc(pos, 5126, "VEC3", 34962, True), "NORMAL": self._acc(nrm, 5126, "VEC3", 34962)},
                "indices": self._acc(idx.astype(np.uint32), 5125, "SCALAR", 34963), "material": MAT_INDEX[mat], "mode": 4})
        self.meshes.append(out)
        return len(self.meshes) - 1
    def node(self, name, mesh=None, translation=(0, 0, 0), children=None, rotation=None):
        n = {"name": name}
        if mesh is not None:
            n["mesh"] = mesh
        if any(abs(t) > 1e-9 for t in translation):
            n["translation"] = [float(t) for t in translation]
        if rotation is not None:
            n["rotation"] = [float(q) for q in rotation]
        if children:
            n["children"] = children
        self.nodes.append(n)
        return len(self.nodes) - 1
    def write(self, path, roots):
        while len(self.bin) % 4:
            self.bin.append(0)
        gltf = {"asset": {"version": "2.0", "generator": "ragdoll-faces gen_models.py"}, "scene": 0, "scenes": [{"name": "Scene", "nodes": roots}],
                "nodes": self.nodes, "meshes": self.meshes, "materials": self.materials, "accessors": self.accessors,
                "bufferViews": self.views, "buffers": [{"byteLength": len(self.bin)}]}
        js = json.dumps(gltf, separators=(",", ":")).encode()
        while len(js) % 4:
            js += b" "
        total = 12 + 8 + len(js) + 8 + len(self.bin)
        with open(path, "wb") as f:
            f.write(struct.pack("<4sII", b"glTF", 2, total))
            f.write(struct.pack("<II", len(js), 0x4E4F534A)); f.write(js)
            f.write(struct.pack("<II", len(self.bin), 0x004E4942)); f.write(bytes(self.bin))

def write_single(path, name, prims, translation=(0, 0, 0)):
    g = GLB()
    m = g.mesh(name, prims)
    root = g.node(name, m, translation)
    g.write(path, [root])

# ---------------- doll ----------------
D = dict(head_r=0.225, torso_h=0.50, torso_w=0.36, torso_d=0.22, ua=0.32, la=0.30, ul=0.42, ll=0.40, foot=0.26, foot_h=0.09,
         arm_r=0.055, leg_r=0.07, jr=0.05, neck=0.03, shoulder_x=0.24, hip_x=0.10)
JOINT_R = D["jr"]

def doll_parts():
    """Returns {part_name: (prims, rest_translation)}; rest pose = standing, arms hanging at the sides,
    FACING THE CAMERA (+Z): shoulders/hips spread along X. Each part is modelled with its origin at its proximal joint."""
    P = {}
    hip_y = D["ul"] + D["ll"] + D["foot_h"]
    sx, hx = D["shoulder_x"], D["hip_x"]
    # Torso: origin at hip centre, extends up; box (width X, height Y, depth Z)
    torso = [(m_box(D["torso_w"], D["torso_h"], D["torso_d"], (0, D["torso_h"] / 2, 0)), "Shirt"),
             (m_box(D["torso_w"] * 1.02, D["torso_h"] * 0.12, D["torso_d"] * 1.02, (0, D["torso_h"] * 0.94, 0)), "Wood"),
             (m_sphere(JOINT_R, (0, D["torso_h"], 0)), "Joint")]
    P["Torso"] = (torso, (0, hip_y, 0))
    hc = (0, D["neck"] + D["head_r"], 0)
    P["Head"] = ([(m_sphere(D["head_r"], hc, 32, 16), "Wood")], (0, hip_y + D["torso_h"], 0))
    # FacePlate: front hemisphere cap facing +Z (camera)
    cap = m_sphere(D["head_r"] * 1.012, hc, 32, 16, keep=lambda x, y, z: z >= D["head_r"] * 0.12)
    rim = m_cylinder(D["head_r"] * 0.995, 0.02, (hc[0], hc[1], hc[2] + D["head_r"] * 0.12), 32, axis="z")
    P["FacePlate"] = ([(cap, "Face"), (rim, "WoodDark")], (0, 0, 0))
    def limb(L, r):
        return [(m_capsule(r, L + r, (0, -(L + r) / 2 + r / 2, 0)), "Wood"), (m_sphere(JOINT_R, (0, 0, 0)), "Joint")]
    sy = hip_y + D["torso_h"]
    wrist_y = sy - D["ua"] - D["la"]
    for side, k in (("L", 1.0), ("R", -1.0)):
        P[f"UpperArm_{side}"] = (limb(D["ua"], D["arm_r"]), (sx * k, sy, 0))
        P[f"LowerArm_{side}"] = (limb(D["la"], D["arm_r"] * 0.9), (sx * k, sy - D["ua"], 0))
        P[f"Hand_{side}"] = ([(m_box(0.09, 0.14, 0.05, (0, -0.07, 0)), "WoodDark"), (m_sphere(JOINT_R * 0.8, (0, 0, 0)), "Joint")], (sx * k, wrist_y, 0))
        P[f"UpperLeg_{side}"] = (limb(D["ul"], D["leg_r"]), (hx * k, hip_y, 0))
        P[f"LowerLeg_{side}"] = (limb(D["ll"], D["leg_r"] * 0.9), (hx * k, hip_y - D["ul"], 0))
        foot = [(m_box(D["leg_r"] * 2.2, D["foot_h"], D["foot"], (0, -D["foot_h"] / 2, D["foot"] * 0.3)), "WoodDark"), (m_sphere(JOINT_R * 0.8, (0, 0, 0)), "Joint")]
        P[f"Foot_{side}"] = (foot, (hx * k, D["foot_h"], 0))
    return P

def build_doll():
    parts = doll_parts()
    g = GLB()
    ids = {}
    for name, (prims, tr) in parts.items():
        ids[name] = (g.mesh(name, prims), tr)
    face = g.node("FacePlate", ids["FacePlate"][0])
    roots = []
    for name, (m, tr) in ids.items():
        if name == "FacePlate":
            continue
        roots.append(g.node(name, m, tr, children=[face] if name == "Head" else None))
    g.write(os.path.join(OUT, "doll.glb"), roots)
    # per-part files for physics rig (each at its own origin)
    for name, (prims, tr) in parts.items():
        write_single(os.path.join(OUT, "parts", f"doll_{name}.glb"), name, prims)
    return parts

# ---------------- hats (origin = crown point of head, +Y up) ----------------
def build_hats():
    hr = D["head_r"]
    hats = {}
    hats["hat_crown"] = [(m_cylinder(hr * 0.75, 0.10, (0, 0.05, 0), 12), "Gold")] + [(m_cylinder(0.02, 0.06, (hr * 0.72 * math.cos(a), 0.12, hr * 0.72 * math.sin(a)), 6, r_top=0.0), "Gold") for a in np.linspace(0, 2 * math.pi, 8, endpoint=False)]
    hats["hat_cowboy"] = [(m_cylinder(hr * 1.6, 0.02, (0, 0.0, 0), 24), "WoodDark"), (m_sphere(hr * 0.72, (0, 0.0, 0), 20, 10, keep=lambda x, y, z: y >= 0), "WoodDark")]
    hats["hat_helmet"] = [(m_sphere(hr * 1.08, (0, -hr * 0.55, 0), 24, 12, keep=lambda x, y, z: y >= -hr * 0.4), "Iron"), (m_box(0.03, 0.18, 0.02, (-0.02, 0.15, 0)), "Red")]
    horn = lambda s: (m_cylinder(0.045, 0.28, (0, 0.14, 0), 8, r_top=0.005), "Bone")
    hats["hat_viking"] = [(m_sphere(hr * 1.05, (0, -hr * 0.5, 0), 24, 12, keep=lambda x, y, z: y >= -hr * 0.3), "Iron"),
                          (translate(rotate_z(horn(1)[0], 0)[0:3] if False else translate(horn(1)[0], (0, -0.02, hr * 0.85)), (0, 0, 0)), "Bone"),
                          (translate(horn(1)[0], (0, -0.02, -hr * 0.85)), "Bone")]
    hats["hat_chicken"] = [(m_sphere(0.16, (0.0, 0.08, 0), 16, 8), "Yellow"), (m_sphere(0.08, (0.17, 0.16, 0), 12, 6), "Yellow"), (m_cylinder(0.03, 0.08, (0.27, 0.15, 0), 6, axis="x", r_top=0.0), "Orange")]
    hats["hat_pot"] = [(m_cylinder(hr * 0.9, 0.22, (0, 0.11, 0), 24), "IronDark"), (m_cylinder(hr * 0.98, 0.02, (0, 0.22, 0), 24), "Iron"),
                       (m_box(0.05, 0.05, 0.08, (0, 0.12, hr * 0.98)), "IronDark"), (m_box(0.05, 0.05, 0.08, (0, 0.12, -hr * 0.98)), "IronDark")]
    hats["hat_cap"] = [(m_sphere(hr * 1.02, (0, -hr * 0.45, 0), 24, 12, keep=lambda x, y, z: y >= -hr * 0.2), "Blue"), (m_box(0.22, 0.015, 0.22, (hr * 0.9, -hr * 0.25, 0)), "Blue")]
    hats["hat_bucket"] = [(m_cylinder(hr * 0.9, 0.30, (0, 0.15, 0), 20, r_top=hr * 1.05), "Iron"), (m_cylinder(hr * 1.1, 0.02, (0, 0.30, 0), 20), "IronDark")]
    for name, prims in hats.items():
        write_single(os.path.join(OUT, f"{name}.glb"), name, prims)
    return list(hats)

# ---------------- weapons (origin = grip, extends along +X) ----------------
def build_weapons():
    W = {}
    W["weapon_hammer"] = [(m_cylinder(0.03, 1.1, (0.40, 0, 0), 12, axis="x"), "WoodDark"), (m_box(0.24, 0.44, 0.18, (0.83, 0, 0)), "Iron")]
    W["weapon_mace"] = [(m_cylinder(0.025, 0.55, (0.15, 0, 0), 12, axis="x"), "WoodDark")]
    for k in range(4):  # chain links as small tori-ish cylinders
        W["weapon_mace"].append((m_cylinder(0.05, 0.02, (0.43 + k * 0.12, 0, 0), 12, axis="z"), "IronDark"))
    bx = 0.43 + 4 * 0.12 + 0.1
    W["weapon_mace"].append((m_sphere(0.13, (bx, 0, 0), 16, 8), "Iron"))
    for a in np.linspace(0, 2 * math.pi, 8, endpoint=False):
        W["weapon_mace"].append((translate(rotate_z(m_cylinder(0.02, 0.12, (0, 0.13, 0), 6, r_top=0.0), math.degrees(a)), (bx, 0, 0)), "Iron"))
    W["weapon_plank"] = [(m_box(0.9, 0.1, 0.04, (0.35, 0, 0)), "Wood"), (m_cylinder(0.006, 0.15, (0.6, 0.1, 0), 6), "Iron")]
    W["weapon_pan"] = [(m_box(0.4, 0.03, 0.04, (0.1, 0, 0)), "Dark"), (m_cylinder(0.22, 0.05, (0.5, 0, 0), 24), "IronDark"), (m_cylinder(0.17, 0.02, (0.5, 0.03, 0), 24), "Iron")]
    W["weapon_torch"] = [(m_cylinder(0.03, 0.45, (0.125, 0, 0), 10, axis="x"), "WoodDark"), (m_box(0.1, 0.1, 0.1, (0.35, 0, 0)), "StoneDark"), (m_sphere(0.09, (0.47, 0.03, 0), 12, 6), "Orange")]
    for name, prims in W.items():
        write_single(os.path.join(OUT, f"{name}.glb"), name, prims)
    return list(W)

# ---------------- props ----------------
def build_props():
    g = GLB()
    barrel = g.mesh("Barrel", [(m_cylinder(0.3, 0.8, (0, 0.4, 0), 20), "WoodDark"), (m_cylinder(0.31, 0.06, (0, 0.18, 0), 20), "IronDark"), (m_cylinder(0.31, 0.06, (0, 0.62, 0), 20), "IronDark")])
    roots = [g.node("Barrel", barrel)]
    for k in range(4):
        a = k * math.pi / 2
        stave = rotate_y(m_box(0.02, 0.8, 0.30, (0.29, 0.4, 0)), math.degrees(a))
        roots.append(g.node(f"Debris_{k + 1}", g.mesh(f"Debris_{k + 1}", [(stave, "WoodDark")]), (0, 0, 0)))
    g.write(os.path.join(OUT, "prop_barrel.glb"), roots)
    g = GLB()
    crate = g.mesh("Crate", [(m_box(0.7, 0.7, 0.7, (0, 0.35, 0)), "Wood"), (m_box(0.72, 0.06, 0.72, (0, 0.05, 0)), "WoodDark"), (m_box(0.72, 0.06, 0.72, (0, 0.65, 0)), "WoodDark")])
    roots = [g.node("Crate", crate)]
    for k in range(6):
        sx, sy, sz = 0.35, 0.35, 0.7 if k < 4 else 0.35
        offs = [(-0.175, 0.175, 0), (0.175, 0.175, 0), (-0.175, 0.525, 0), (0.175, 0.525, 0), (0, 0.35, -0.175), (0, 0.35, 0.175)][k]
        roots.append(g.node(f"Debris_{k + 1}", g.mesh(f"Debris_{k + 1}", [(m_box(0.34, 0.34, 0.68 if k < 4 else 0.34, offs), "Wood")])))
    g.write(os.path.join(OUT, "prop_crate.glb"), roots)
    bridge = []
    for k in range(9):
        t = k / 8
        y = -0.3 * 4 * t * (1 - t)
        bridge.append((m_box(0.18, 0.04, 0.9, (k * 0.25, y, 0)), "Wood"))
    for z in (0.45, -0.45):
        for k in range(8):
            t0, t1 = k / 8, (k + 1) / 8
            y0, y1 = -0.3 * 4 * t0 * (1 - t0), -0.3 * 4 * t1 * (1 - t1)
            L = math.hypot(0.25, y1 - y0)
            ang = math.degrees(math.atan2(y1 - y0, 0.25))
            bridge.append((translate(rotate_z(m_cylinder(0.02, L, (0, 0, 0), 6, axis="x"), ang), (k * 0.25 + 0.125, (y0 + y1) / 2, z)), "Rope"))
    write_single(os.path.join(OUT, "prop_bridge.glb"), "Bridge", bridge)
    banner = [(m_cylinder(0.04, 3.0, (0, 1.5, 0), 10), "WoodDark"), (m_box(0.03, 1.8, 1.2, (0.0, 2.1, 0.62)), "Red")]
    write_single(os.path.join(OUT, "prop_banner.glb"), "Banner", banner)
    winch = [(m_box(0.5, 0.5, 0.5, (0, 0.25, 0)), "WoodDark"), (m_cylinder(0.12, 0.6, (0, 0.25, 0), 16, axis="z"), "Dark"), (m_cylinder(0.01, 1.2, (0, -0.35, 0), 6), "Rope"), (m_box(0.4, 0.4, 0.4, (0, -1.15, 0)), "StoneDark")]
    write_single(os.path.join(OUT, "prop_winch.glb"), "Winch", winch)

# ---------------- arena (from R6/R7: metres, origin bottom-left of collision grid) ----------------
def build_arena():
    g = GLB()
    roots = []
    def coll(name, x0, x1, y0, y1, mat="Stone", z=0.0, depth=2.0):
        m = g.mesh(name, [(m_box(x1 - x0, y1 - y0, depth, ((x0 + x1) / 2, (y0 + y1) / 2, z)), mat)])
        roots.append(g.node(name, m))
    coll("Collision_Tier0_A", 4, 13, 0, 1); coll("Collision_Tier0_B", 15, 26, 0, 1)
    coll("Collision_Bridge", 13, 15, 0.72, 0.92, "Wood", 0, 1.0)
    coll("Collision_Tier1_A", 6, 10, 2.9, 3.2, "Wood"); coll("Collision_Tier1_B", 16, 20, 2.9, 3.4)
    coll("Collision_Tier2_A", 9, 14, 5.4, 5.8); coll("Collision_Tier2_B", 19, 22, 5.4, 5.7, "Wood")
    coll("Collision_Tower", 22.5, 26, 1, 6.7); coll("Collision_TowerLedge", 22.5, 24, 6.7, 7.0)
    coll("Collision_TowerTop", 24, 26, 6.7, 7.6)
    coll("Collision_WallL", -0.5, 0, -0.5, 10.5, "Collision"); coll("Collision_WallR", 26, 26.5, -0.5, 10.5, "Collision"); coll("Collision_Ceiling", -0.5, 26.5, 10.5, 11, "Collision")
    # decor (no collision)
    deco = [("Deco_ArchWall", m_box(4.6, 4.4, 1.2, (11.5, 3.2, -1.2)), "StoneDark"),
            ("Deco_Cliff_A", m_box(9, 1.5, 3, (8.6, -0.75, 0)), "StoneDark"), ("Deco_Cliff_B", m_box(11, 1.5, 3, (20.5, -0.75, 0)), "StoneDark"),
            ("Deco_Support_1", rotate_z(m_cylinder(0.06, 2.0, (0, 0, 0), 8), 20), "WoodDark")]
    for name, mesh, mat in deco:
        roots.append(g.node(name, g.mesh(name, [(mesh, mat)])))
    g.write(os.path.join(OUT, "arena_ruins.glb"), roots)

if __name__ == "__main__":
    parts = build_doll()
    hats = build_hats()
    weapons = build_weapons()
    build_props()
    build_arena()
    files = sorted(os.listdir(OUT)) + ["parts/" + f for f in sorted(os.listdir(os.path.join(OUT, "parts")))]
    print("doll parts:", ", ".join(parts))
    print("files:", len([f for f in files if f.endswith(".glb")]))
