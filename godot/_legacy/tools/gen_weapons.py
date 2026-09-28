#!/usr/bin/env python3
"""Weapons after R16 (docs/refs/R16-a-weapons-concept.jpg) for the Ragdoll Master demo.

Writes godot/assets/models/weapons/{hammer,mace,sword,axe,pan}.glb using the pure-Python glTF writer
from gen_models.py (GLB, m_box, m_sphere, materials).

Conventions: metres, origin = GRIP point, the weapon extends along +X (head/blade away from the hand),
thin in Z (weapons live in the XY plane, the camera looks along -Z so the +Z face is the "front").
Every glb has top-level mesh nodes named "Handle" and "Head" (optionally "Guard"/"Pommel"); weapon.gd builds
one BoxShape3D per top-level node from its AABB.  Low poly: <= 1500 triangles per weapon.

Run:  python3 godot/tools/gen_weapons.py
"""
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_models as gm  # noqa: E402

OUT = os.path.join(gm.OUT, "weapons")
os.makedirs(OUT, exist_ok=True)

# Extra materials on top of gen_models.MATERIALS; rebuild the index so gm.GLB/gm.mesh see them.
EXTRA = {
    "Steel": "cdd2d9", "SteelDark": "858c96", "Leather": "4a2f1c", "LeatherDark": "33200f",
    "Brass": "b58a37", "PanIron": "3b3b40", "PanInside": "5a4c42", "WoodMid": "c58f55", "Rust": "7d4b2a",
}
for k, v in EXTRA.items():
    gm.MATERIALS.setdefault(k, gm.hexc(v))
gm.MAT_INDEX = {k: i for i, k in enumerate(gm.MATERIALS)}
# (metallic, roughness) overrides; everything else stays 0 / 0.85 like the grey-box models.
PBR = {
    "Steel": (0.45, 0.4), "SteelDark": (0.45, 0.5), "Iron": (0.4, 0.55), "IronDark": (0.4, 0.6),
    "Gold": (0.5, 0.45), "Brass": (0.5, 0.45), "PanIron": (0.35, 0.65), "Rust": (0.2, 0.8),
}


# ---------------- flat-shaded triangle-soup helpers ----------------
def tri_mesh(tris):
    """[(p0, p1, p2), ...] -> (pos, nrm, idx) with one flat normal per triangle."""
    pos, nrm, idx = [], [], []
    for a, b, c in tris:
        a, b, c = (np.asarray(v, np.float64) for v in (a, b, c))
        n = np.cross(b - a, c - a)
        ln = np.linalg.norm(n)
        if ln < 1e-12:
            continue
        n = n / ln
        base = len(pos)
        pos += [a, b, c]
        nrm += [n, n, n]
        idx += [base, base + 1, base + 2]
    return gm._mesh(pos, nrm, idx)


def signed_volume(tris):
    v = 0.0
    for a, b, c in tris:
        a, b, c = (np.asarray(p, np.float64) for p in (a, b, c))
        v += float(np.dot(a, np.cross(b, c))) / 6.0
    return v


def orient(tris):
    """Flip a closed triangle soup so that its normals point outwards (positive signed volume)."""
    if signed_volume(tris) < 0:
        return [(a, c, b) for a, b, c in tris]
    return tris


def loft(rings):
    """Connect consecutive closed rings (equal point count) with quads; returns (tris, segment index per tri)."""
    tris, seg = [], []
    n = len(rings[0])
    for a, b in zip(rings[:-1], rings[1:]):
        for j in range(n):
            k = (j + 1) % n
            tris += [(a[j], b[j], b[k]), (a[j], b[k], a[k])]
            seg += [j, j]
    return tris, seg


def _ring(r, h, seg, axis):
    out = []
    for j in range(seg):
        th = 2 * math.pi * j / seg
        c, s = r * math.cos(th), r * math.sin(th)
        if axis == "y":
            out.append((c, h, s))
        elif axis == "x":
            out.append((h, c, s))
        else:
            out.append((c, s, h))
    return out


def revolve(profile, seg=16, axis="y", center=(0, 0, 0), closed=False, split=None):
    """Lathe: profile = [(radius, height), ...] from axis to axis (or a closed loop with closed=True).
    split(j) -> material key: returns {key: mesh} instead of a single mesh (planks etc.)."""
    pts = list(profile) + ([profile[0]] if closed else [])
    rings = [_ring(r, h, seg, axis) for r, h in pts]
    tris, segs = loft(rings)
    if signed_volume(tris) < 0:
        tris = [(a, c, b) for a, b, c in tris]
    c = np.array(center, np.float64)
    tris = [tuple(np.asarray(p) + c for p in t) for t in tris]
    if split is None:
        return tri_mesh(tris)
    groups = {}
    for t, j in zip(tris, segs):
        groups.setdefault(split(j), []).append(t)
    return {k: tri_mesh(v) for k, v in groups.items()}


def cyl(r, h, center=(0, 0, 0), seg=12, axis="y", r_top=None):
    rt = r if r_top is None else r_top
    return revolve([(0, -h / 2), (r, -h / 2), (rt, h / 2), (0, h / 2)], seg, axis, center)


def torus(R, r, center=(0, 0, 0), seg=20, rings=8, axis="z"):
    """Ring of tube radius r around the axis; the ring lies in the plane perpendicular to axis."""
    loops = []
    for i in range(seg + 1):
        ph = 2 * math.pi * i / seg
        ring = []
        for j in range(rings):
            ps = 2 * math.pi * j / rings
            rad = R + r * math.cos(ps)
            h = r * math.sin(ps)
            ring.append(_pt(rad, h, ph, axis))
        loops.append(ring)
    tris, _ = loft(loops)
    tris = orient(tris)
    c = np.array(center, np.float64)
    return tri_mesh([tuple(np.asarray(p) + c for p in t) for t in tris])


def _pt(rad, h, ph, axis):
    c, s = rad * math.cos(ph), rad * math.sin(ph)
    if axis == "y":
        return (c, h, s)
    if axis == "x":
        return (h, c, s)
    return (c, s, h)


def triangulate(poly):
    """Ear clipping for a simple polygon [(x, y), ...]; returns index triples (CCW)."""
    n = len(poly)
    area2 = sum(poly[i][0] * poly[(i + 1) % n][1] - poly[(i + 1) % n][0] * poly[i][1] for i in range(n))
    idx = list(range(n))
    if area2 < 0:
        idx.reverse()

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    def inside(p, a, b, c):
        return cross(a, b, p) >= 0 and cross(b, c, p) >= 0 and cross(c, a, p) >= 0

    tris = []
    guard = 0
    while len(idx) > 3 and guard < 20 * n:
        guard += 1
        for i in range(len(idx)):
            i0, i1, i2 = idx[i - 1], idx[i], idx[(i + 1) % len(idx)]
            a, b, c = poly[i0], poly[i1], poly[i2]
            if cross(a, b, c) <= 1e-12:
                continue
            if any(inside(poly[k], a, b, c) for k in idx if k not in (i0, i1, i2)):
                continue
            tris.append((i0, i1, i2))
            idx.pop(i)
            break
        else:
            break
    if len(idx) == 3:
        tris.append(tuple(idx))
    return tris


def extrude(poly, z0, z1):
    """Flat polygon in XY extruded along Z from z0 to z1 (closed solid, flat shading)."""
    n = len(poly)
    area2 = sum(poly[i][0] * poly[(i + 1) % n][1] - poly[(i + 1) % n][0] * poly[i][1] for i in range(n))
    if area2 < 0:
        poly = list(reversed(poly))
    tris = []
    for i in range(n):
        a, b = poly[i], poly[(i + 1) % n]
        p0, p1, p2, p3 = (a[0], a[1], z0), (b[0], b[1], z0), (b[0], b[1], z1), (a[0], a[1], z1)
        tris += [(p0, p1, p2), (p0, p2, p3)]
    for i0, i1, i2 in triangulate(poly):
        A, B, C = poly[i0], poly[i1], poly[i2]
        tris.append(((A[0], A[1], z1), (B[0], B[1], z1), (C[0], C[1], z1)))
        tris.append(((A[0], A[1], z0), (C[0], C[1], z0), (B[0], B[1], z0)))
    return tri_mesh(orient(tris))


def rot_to(mesh, d):
    """Rotate a mesh built along +Y so that +Y maps onto direction d."""
    d = np.asarray(d, np.float64)
    d = d / np.linalg.norm(d)
    y = np.array([0.0, 1.0, 0.0])
    v = np.cross(y, d)
    s = np.linalg.norm(v)
    c = float(np.dot(y, d))
    if s < 1e-9:
        R = np.eye(3) if c > 0 else np.diag([1.0, -1.0, -1.0])
    else:
        vx = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
        R = np.eye(3) + vx + vx @ vx * ((1 - c) / (s * s))
    p, n, i = mesh
    R = R.astype(np.float32)
    return p @ R.T, n @ R.T, i


def spike(base_r, length, pos, direction, mat="Iron", seg=6):
    """Cone with its base at pos pointing along direction."""
    cone = revolve([(0, 0), (base_r, 0), (0, length)], seg, "y")
    return (gm.translate(rot_to(cone, direction), pos), mat)


def wrap(r, x0, x1, pitch, mat="Leather", seg=10, axis="x"):
    """Leather wrap: short rings slightly proud of the handle, along X from x0 to x1."""
    out = []
    n = max(1, int(round((x1 - x0) / pitch)))
    for i in range(n):
        x = x0 + (i + 0.5) * (x1 - x0) / n
        w = (x1 - x0) / n * 0.72
        out.append((cyl(r + 0.006, w, (x, 0, 0), seg, axis), mat if i % 2 == 0 else "LeatherDark"))
    return out


def crown_poly(w=0.17, h=0.12):
    """Crown silhouette centred at (0,0): base band + three peaks."""
    x, y = w / 2, h / 2
    return [(-x, -y), (x, -y), (x, -y * 0.35), (x * 0.95, y * 0.9), (x * 0.5, y * 0.05), (0.0, y),
            (-x * 0.5, y * 0.05), (-x * 0.95, y * 0.9), (-x, -y * 0.35)]


def tri_count(prims):
    return sum(len(i) // 3 for (_, _, i), _ in prims)


# ---------------- 01 wooden hammer: barrel head with two iron bands + red crown, wrapped handle ----------------
def hammer():
    hr = 0.033
    handle = [(cyl(hr, 0.80, (0.28, 0, 0), 10, "x"), "WoodDark"),
              (cyl(hr + 0.012, 0.03, (-0.125, 0, 0), 10, "x"), "IronDark"),        # pommel cap
              (cyl(0.052, 0.05, (0.545, 0, 0), 10, "x", r_top=0.06), "Iron")]      # collar under the head
    handle += wrap(hr, -0.10, 0.15, 0.032)
    cx = 0.75
    prof = [(0, -0.24), (0.15, -0.24), (0.183, -0.13), (0.197, 0.0), (0.183, 0.13), (0.15, 0.24), (0, 0.24)]
    planks = revolve(prof, 14, "y", (cx, 0, 0), split=lambda j: "Wood" if j % 2 == 0 else "WoodMid")
    head = [(m, mat) for mat, m in planks.items()]
    for y in (-0.165, 0.165):
        head.append((cyl(0.186, 0.045, (cx, y, 0), 14, "y"), "IronDark"))          # iron bands
        for k in range(3):                                                          # studs on the front of each band
            a = -0.55 + k * 0.55
            head.append((gm.m_sphere(0.012, (cx + 0.19 * math.sin(a), y, 0.19 * math.cos(a)), 6, 3), "Iron"))
    for y in (-0.25, 0.25):
        head.append((cyl(0.155, 0.02, (cx, y, 0), 14, "y"), "Iron"))                # end rims
    head.append((gm.translate(extrude(crown_poly(), 0.165, 0.207), (cx, 0.0, 0)), "Red"))
    return [("Handle", handle), ("Head", head)]


# ---------------- 02 iron mace: spiked sphere, wrapped handle, ring pommel ----------------
def mace():
    hr = 0.027
    handle = [(cyl(hr, 0.62, (0.20, 0, 0), 10, "x"), "WoodDark"),
              (cyl(hr + 0.008, 0.035, (-0.105, 0, 0), 10, "x"), "Iron"),           # pommel cap
              (cyl(0.042, 0.05, (0.50, 0, 0), 10, "x"), "Iron"),                    # collar
              (cyl(0.03, 0.07, (0.55, 0, 0), 10, "x", r_top=0.06), "IronDark")]     # flare into the head
    handle += wrap(hr, -0.07, 0.30, 0.03)
    pommel = [(torus(0.046, 0.011, (-0.165, 0, 0), 16, 6, "z"), "Iron")]
    hx, R = 0.70, 0.135
    head = [(gm.m_sphere(R, (hx, 0, 0), 16, 8), "Iron")]
    dirs = []
    for a in (0, 45, 90, 135, 225, 270, 315):
        dirs.append((math.cos(math.radians(a)), math.sin(math.radians(a)), 0.0))
    for a in (20, 110, 200, 290):
        dirs.append((0.62 * math.cos(math.radians(a)), 0.62 * math.sin(math.radians(a)), 0.78))
        dirs.append((0.62 * math.cos(math.radians(a + 45)), 0.62 * math.sin(math.radians(a + 45)), -0.78))
    dirs += [(0, 0, 1.0), (0, 0, -1.0)]
    for d in dirs:
        d = np.asarray(d) / np.linalg.norm(d)
        head.append(spike(0.03, 0.09, (hx + d[0] * (R - 0.012), d[1] * (R - 0.012), d[2] * (R - 0.012)), d, "IronDark"))
    return [("Handle", handle), ("Pommel", pommel), ("Head", head)]


# ---------------- 03 sword: double-edged blade, cross-guard, pommel ----------------
def sword():
    gr = 0.021
    handle = [(cyl(gr, 0.24, (-0.005, 0, 0), 10, "x"), "LeatherDark")]
    handle += wrap(gr, -0.10, 0.10, 0.024)
    pommel = [(gm.m_sphere(0.036, (-0.15, 0, 0), 12, 6), "Brass"),
              (cyl(0.03, 0.02, (-0.115, 0, 0), 10, "x"), "Brass")]
    guard = [(gm.m_box(0.04, 0.30, 0.045, (0.13, 0, 0)), "Brass"),
             (gm.m_sphere(0.026, (0.13, 0.155, 0), 8, 4), "Brass"), (gm.m_sphere(0.026, (0.13, -0.155, 0), 8, 4), "Brass")]

    def diamond(x, w, t):
        return [(x, w / 2, 0), (x, 0, t / 2), (x, -w / 2, 0), (x, 0, -t / 2)]

    rings = [[(0.15, 0, 0)] * 4, diamond(0.15, 0.115, 0.02), diamond(0.34, 0.115, 0.02), diamond(0.74, 0.09, 0.016), [(0.92, 0, 0)] * 4]
    tris, _ = loft(rings)
    blade = [(tri_mesh(orient(tris)), "Steel"),
             (gm.m_box(0.22, 0.03, 0.026, (0.28, 0, 0)), "SteelDark")]     # fuller/ridge accent near the guard
    return [("Handle", handle), ("Pommel", pommel), ("Guard", guard), ("Head", blade)]


# ---------------- 04 axe: wooden haft, broad bearded single-bit iron head ----------------
def axe():
    hr = 0.031
    handle = [(cyl(hr, 0.97, (0.375, 0, 0), 10, "x"), "WoodDark"),
              (cyl(hr + 0.006, 0.025, (-0.10, 0, 0), 10, "x"), "WoodDark")]
    handle += wrap(hr, -0.08, 0.17, 0.032)
    # bearded bit: narrow neck at the socket, top horn swept forward (+X), beard hooking back toward the haft,
    # cutting edge = the long arc between the horns (far +Y side)
    bit = [(0.66, 0.05), (0.79, 0.05), (0.815, 0.13), (0.87, 0.24), (0.935, 0.34), (0.965, 0.44), (0.90, 0.51),
           (0.78, 0.545), (0.65, 0.535), (0.545, 0.485), (0.59, 0.40), (0.665, 0.32), (0.69, 0.22), (0.68, 0.13)]
    edge = [(0.965, 0.44), (0.90, 0.51), (0.78, 0.545), (0.65, 0.535), (0.545, 0.485),
            (0.59, 0.455), (0.66, 0.495), (0.78, 0.505), (0.885, 0.475), (0.93, 0.425)]
    splash = [(0.72, 0.33), (0.765, 0.30), (0.815, 0.325), (0.835, 0.375), (0.81, 0.43), (0.76, 0.44), (0.72, 0.41), (0.70, 0.365)]
    head = [(gm.m_box(0.17, 0.115, 0.082, (0.7225, 0, 0)), "Iron"),                    # socket around the haft
            (extrude(bit, -0.015, 0.015), "SteelDark"),
            (extrude(edge, -0.017, 0.017), "Steel"),
            (extrude(splash, 0.014, 0.019), "Red"),
            (cyl(0.014, 0.10, (0.7225, 0, 0), 6, "z"), "IronDark")]                     # rivet through the socket
    return [("Handle", handle), ("Head", head)]


# ---------------- 05 frying pan: round iron pan, flat handle with a hanging hole ----------------
def pan():
    px, R = 0.47, 0.215
    handle = [(gm.m_box(0.36, 0.046, 0.014, (0.115, 0, 0)), "PanIron"),
              (torus(0.024, 0.010, (-0.085, 0, 0), 14, 6, "z"), "PanIron"),             # hanging hole
              (cyl(0.011, 0.024, (0.24, 0, 0.007), 6, "z"), "Rust"),                    # rivets
              (cyl(0.011, 0.024, (0.205, 0, 0.007), 6, "z"), "Rust")]
    prof = [(0, -0.04), (R - 0.05, -0.04), (R, 0.045), (R - 0.02, 0.045), (R - 0.05, -0.02), (0, -0.02)]
    head = [(revolve(prof, 24, "z", (px, 0, 0)), "PanIron"),
            (cyl(R - 0.052, 0.006, (px, 0, -0.017), 24, "z"), "PanInside"),             # inside floor (seen from the front)
            (torus(R - 0.01, 0.011, (px, 0, 0.045), 24, 6, "z"), "Rust")]               # worn rim
    return [("Handle", handle), ("Head", head)]


def write(name, nodes):
    g = gm.GLB()
    for m in g.materials:
        if m["name"] in PBR:
            m["pbrMetallicRoughness"]["metallicFactor"], m["pbrMetallicRoughness"]["roughnessFactor"] = PBR[m["name"]]
    roots = [g.node(nn, g.mesh(nn, prims)) for nn, prims in nodes]
    g.write(os.path.join(OUT, name + ".glb"), roots)
    tris = sum(tri_count(prims) for _, prims in nodes)
    xs = np.concatenate([p[:, 0] for _, prims in nodes for (p, _, _), _ in prims])
    ys = np.concatenate([p[:, 1] for _, prims in nodes for (p, _, _), _ in prims])
    print(f"{name:7s} tris={tris:5d}  x=[{xs.min():+.2f},{xs.max():+.2f}]  y=[{ys.min():+.2f},{ys.max():+.2f}]  len={xs.max() - xs.min():.2f} m")
    assert tris <= 1500, f"{name}: {tris} tris > 1500"


WEAPONS = {"hammer": hammer, "mace": mace, "sword": sword, "axe": axe, "pan": pan}

if __name__ == "__main__":
    for name, fn in WEAPONS.items():
        write(name, fn())
    print("written to", OUT)
