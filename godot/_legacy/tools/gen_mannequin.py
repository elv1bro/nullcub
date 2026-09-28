#!/usr/bin/env python3
"""Mannequin hero model after R14 (docs/refs/R14-a-character-base.jpg).

Writes godot/assets/models/heroes/mannequin.glb (14 parts + FacePlate under Head, rest pose,
origins at the proximal joints, same rest translations as gen_models.doll_parts so DollSkin attaches
without offsets) and one glb per part in godot/assets/models/heroes/mannequin_parts/.

Conventions: metres, Y up, the doll faces the camera (+Z), X sideways, left side = +X.
Look (R14): light warm-grey painted segments, slightly tapered (wider at the proximal joint) with a cuff ring
where they meet the dark gunmetal ball joints; oval head with a FacePlate cap on +Z; chest block + pelvis block
inside the Torso part with the player-coloured "Shirt" as a painted band on the chest; hands with palm,
4 fingers and a thumb (low poly); rounded shoe-like feet pointing +Z.

Uses only the glTF writer / material table / helpers from gen_models.py. The lathe / rounded-box primitives
are local (gen_models' sphere & cylinder are wound clockwise, see fix_winding()).
"""
import math, os, sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_models as gm
from gen_models import hexc, merge, translate, rotate_z, rotate_y

ROOT = gm.ROOT
OUT = os.path.join(ROOT, "assets", "models", "heroes")
PARTS_OUT = os.path.join(OUT, "mannequin_parts")

# ---------------- materials (merged into gen_models.MATERIALS; "Shirt", "Face", "Joint" keep their names) ----------------
LOCAL_MATERIALS = {
    "Paint": hexc("b7b1a7"),       # light warm-grey painted segments
    "PaintDark": hexc("a49d93"),   # cuffs / collar
    "Seam": hexc("6f6a66"),        # thin seam between cuff and segment body
    "Joint": hexc("3a3e45"),       # gunmetal ball joints (overrides the wooden doll's dark brown)
    "Sole": hexc("46423e"),
}
MAT_PBR = {
    "Joint": {"metallicFactor": 0.7, "roughnessFactor": 0.4},
    "Paint": {"metallicFactor": 0.0, "roughnessFactor": 0.7},
    "PaintDark": {"metallicFactor": 0.0, "roughnessFactor": 0.75},
    "Sole": {"metallicFactor": 0.0, "roughnessFactor": 0.9},
    "Seam": {"metallicFactor": 0.2, "roughnessFactor": 0.7},
    "Face": {"metallicFactor": 0.0, "roughnessFactor": 0.6},
}
gm.MATERIALS.update(LOCAL_MATERIALS)
gm.MAT_INDEX = {k: i for i, k in enumerate(gm.MATERIALS)}


def make_glb():
    g = gm.GLB()
    for m in g.materials:
        if m["name"] in MAT_PBR:
            m["pbrMetallicRoughness"].update(MAT_PBR[m["name"]])
    return g


# ---------------- mesh helpers ----------------
def fix_winding(mesh):
    """Drop degenerate triangles and flip those whose geometric normal disagrees with the vertex normals."""
    p, n, i = mesh
    t = i.reshape(-1, 3).copy()
    v0, v1, v2 = p[t[:, 0]], p[t[:, 1]], p[t[:, 2]]
    fn = np.cross(v1 - v0, v2 - v0)
    keep = np.linalg.norm(fn, axis=1) > 1e-12
    t, fn = t[keep], fn[keep]
    vn = n[t[:, 0]] + n[t[:, 1]] + n[t[:, 2]]
    flip = (fn * vn).sum(axis=1) < 0
    t[flip] = t[flip][:, [0, 2, 1]]
    return p, n, t.ravel().astype(np.uint32)


def smooth_normals(mesh, weld=1e-5):
    """Area-weighted vertex normals, welding coincident vertices (use on meshes without hard edges)."""
    p, n, i = mesh
    t = i.reshape(-1, 3)
    fn = np.cross(p[t[:, 1]] - p[t[:, 0]], p[t[:, 2]] - p[t[:, 0]])
    key = np.round(p / weld).astype(np.int64)
    _, inv = np.unique(key, axis=0, return_inverse=True)
    inv = inv.ravel()
    acc = np.zeros((int(inv.max()) + 1, 3))
    for c in range(3):
        np.add.at(acc, inv[t[:, c]], fn)
    nn = acc[inv]
    L = np.linalg.norm(nn, axis=1, keepdims=True)
    L[L == 0] = 1.0
    return p, (nn / L).astype(np.float32), i


def scale_about(mesh, s, centre=(0, 0, 0)):
    p, n, i = mesh
    c = np.array(centre, np.float32)
    return (p - c) * np.array(s, np.float32) + c, n, i


def taper_y(mesh, y0, y1, s0, s1, renormal=True):
    """Scale X and Z by lerp(s0, s1) over y in [y0, y1] (clamped); normals recomputed unless renormal=False."""
    p, n, i = mesh
    t = np.clip((p[:, 1] - y0) / (y1 - y0), 0.0, 1.0)
    s = s0 + (s1 - s0) * t
    p2 = p.copy()
    p2[:, 0] *= s
    p2[:, 2] *= s
    out = (p2.astype(np.float32), n, i)
    return smooth_normals(out) if renormal else out


def m_rounded_rect_prism(w, d, r, y0, y1, seg=3):
    """Vertical extrusion of a rounded rectangle (XZ cross-section like m_rounded_box's middle) with flat caps."""
    r = min(r, w / 2, d / 2)
    ex, ez = w / 2 - r, d / 2 - r
    ring = []
    for q in range(4):
        mid = (q + 0.5) * math.pi / 2
        xs, zs = (1.0 if math.cos(mid) > 0 else -1.0), (1.0 if math.sin(mid) > 0 else -1.0)
        for j in range(seg + 1):
            th = q * math.pi / 2 + math.pi / 2 * j / seg
            ring.append((xs * ex + r * math.cos(th), zs * ez + r * math.sin(th), math.cos(th), math.sin(th)))
    pos, nrm, idx = [], [], []
    n = len(ring)
    for x, z, nx, nz in ring:
        pos += [(x, y0, z), (x, y1, z)]
        nrm += [(nx, 0.0, nz), (nx, 0.0, nz)]
    for i in range(n):
        a, b = 2 * i, 2 * ((i + 1) % n)
        idx += [a, a + 1, b, a + 1, b + 1, b]
    for y, ny in ((y1, 1.0), (y0, -1.0)):
        c = len(pos)
        pos.append((0.0, y, 0.0))
        nrm.append((0.0, ny, 0.0))
        base = len(pos)
        for x, z, _, _ in ring:
            pos.append((x, y, z))
            nrm.append((0.0, ny, 0.0))
        for i in range(n):
            idx += [c, base + i, base + (i + 1) % n]
    return fix_winding(gm._mesh(pos, nrm, idx))


def taper_z(mesh, z0, z1, s0, s1):
    """Scale X by lerp(s0, s1) over z in [z0, z1] (clamped); normals recomputed."""
    p, n, i = mesh
    t = np.clip((p[:, 2] - z0) / (z1 - z0), 0.0, 1.0)
    s = s0 + (s1 - s0) * t
    p2 = p.copy()
    p2[:, 0] *= s
    return smooth_normals((p2.astype(np.float32), n, i))


def m_lathe(profile, seg=16):
    """Surface of revolution around Y. profile = [(r, y[, 'h']), ...] in either vertical order;
    'h' marks a hard edge (vertex duplicated), r == 0 is a pole. Smooth normals from the profile tangent."""
    pts = [(float(p[0]), float(p[1]), len(p) > 2 and p[2] == "h") for p in profile]
    if pts[0][1] > pts[-1][1]:
        pts = pts[::-1]
    strips, cur = [], []
    for r, y, hard in pts:
        cur.append((r, y))
        if hard:
            strips.append(cur)
            cur = [(r, y)]
    strips.append(cur)
    pos, nrm, idx = [], [], []
    for strip in strips:
        if len(strip) < 2:
            continue
        n = len(strip)
        base = len(pos)
        for i, (r, y) in enumerate(strip):
            r0, y0 = strip[max(i - 1, 0)]
            r1, y1 = strip[min(i + 1, n - 1)]
            dr, dy = r1 - r0, y1 - y0
            L = math.hypot(dr, dy) or 1.0
            nr, ny = dy / L, -dr / L
            if r < 1e-9:
                nr, ny = 0.0, (1.0 if ny >= 0 else -1.0)
            for j in range(seg + 1):
                th = 2 * math.pi * j / seg
                c, s = math.cos(th), math.sin(th)
                pos.append((r * c, y, r * s))
                nrm.append((nr * c, ny, nr * s))
        for i in range(n - 1):
            for j in range(seg):
                a = base + i * (seg + 1) + j
                b = a + seg + 1
                idx += [a, a + 1, b, a + 1, b + 1, b]
    return fix_winding(gm._mesh(pos, nrm, idx))


def m_ball(r, centre=(0, 0, 0), seg=14, rings=7):
    return fix_winding(gm.m_sphere(r, centre, seg, rings))


def m_rounded_box(w, h, d, r, centre=(0, 0, 0), n=3, m=3):
    """Box with all edges rounded by radius r (a sphere swept over the inner box); smooth normals."""
    r = min(r, w / 2, h / 2, d / 2)
    ex, ey, ez = w / 2 - r, h / 2 - r, d / 2 - r
    cx, cy, cz = centre
    rows = [(math.pi / 2 * i / n, 1.0) for i in range(n + 1)] + [(math.pi / 2 + math.pi / 2 * i / n, -1.0) for i in range(n + 1)]
    cols = []
    for q in range(4):
        mid = (q + 0.5) * math.pi / 2
        xs, zs = (1.0 if math.cos(mid) > 0 else -1.0), (1.0 if math.sin(mid) > 0 else -1.0)
        cols += [(q * math.pi / 2 + math.pi / 2 * j / m, xs, zs) for j in range(m + 1)]
    pos, nrm, idx = [], [], []
    for phi, ys in rows:
        for th, xs, zs in cols:
            nx, ny, nz = math.sin(phi) * math.cos(th), math.cos(phi), math.sin(phi) * math.sin(th)
            pos.append((cx + r * nx + xs * ex, cy + r * ny + ys * ey, cz + r * nz + zs * ez))
            nrm.append((nx, ny, nz))
    R, C = len(rows), len(cols)
    for i in range(R - 1):
        for c in range(C):
            c2 = (c + 1) % C
            a, b, a2, b2 = i * C + c, (i + 1) * C + c, i * C + c2, (i + 1) * C + c2
            idx += [a, a2, b, a2, b2, b]
    top = [q * (m + 1) for q in range(4)]
    bot = [(R - 1) * C + q * (m + 1) for q in range(4)]
    idx += [top[0], top[1], top[2], top[0], top[2], top[3], bot[0], bot[2], bot[1], bot[0], bot[3], bot[2]]
    return fix_winding(gm._mesh(pos, nrm, idx))


def m_tube(points, normals, rho, seg=6, closed=True):
    """Tube of radius rho along a closed polyline; normals = surface normals at the points (frame reference)."""
    P = np.asarray(points, np.float64)
    N = np.asarray(normals, np.float64)
    k = len(P)
    pos, nrm, idx = [], [], []
    for a in range(k):
        t = P[(a + 1) % k] - P[(a - 1) % k]
        t /= np.linalg.norm(t) or 1.0
        nn = N[a] - t * np.dot(N[a], t)
        nn /= np.linalg.norm(nn) or 1.0
        b = np.cross(t, nn)
        for j in range(seg + 1):
            u = 2 * math.pi * j / seg
            dirn = math.cos(u) * nn + math.sin(u) * b
            pos.append(P[a] + rho * dirn)
            nrm.append(dirn)
    for a in range(k if closed else k - 1):
        a2 = (a + 1) % k
        for j in range(seg):
            i0, i1 = a * (seg + 1) + j, a2 * (seg + 1) + j
            idx += [i0, i0 + 1, i1, i0 + 1, i1 + 1, i1]
    return fix_winding(gm._mesh(pos, nrm, idx))


def tri_count(prims):
    return sum(len(m[2]) // 3 for m, _ in prims)


# ---------------- rig numbers (must equal gen_models.doll_parts / doll.gd) ----------------
D = gm.D
HIP_Y = D["ul"] + D["ll"] + D["foot_h"]          # 0.91
SHOULDER_Y = HIP_Y + D["torso_h"]                # 1.41
ELBOW_Y = SHOULDER_Y - D["ua"]                   # 1.09
WRIST_Y = ELBOW_Y - D["la"]                      # 0.79
KNEE_Y = HIP_Y - D["ul"]                         # 0.49
ANKLE_Y = D["foot_h"]                            # 0.09
SX, HX = D["shoulder_x"], D["hip_x"]             # 0.24, 0.10

JR = {"neck": 0.05, "shoulder": 0.062, "elbow": 0.052, "wrist": 0.04, "hip": 0.068, "knee": 0.058, "ankle": 0.045}

HEAD_W, HEAD_H, HEAD_K = 0.43, 0.48, -0.17      # oval head (egg, wide end up, narrows to the neck like R14), height limited by DollSkin auto-scale (±2 % of 1.89 m)
HEAD_BOTTOM = 1.435                              # world y of the egg's bottom pole (neck ball visible below it)


def egg_radius_fn(W, H, cy, k):
    R, Hh = W / 2, H / 2
    ts = np.linspace(-1, 1, 2001)
    raw = np.sqrt(np.clip(1 - ts * ts, 0, None)) * (1 - k * ts)
    mx = raw.max()

    def rad(y):
        t = (y - cy) / Hh
        if abs(t) >= 1.0:
            return 0.0
        return R * math.sqrt(1 - t * t) * (1 - k * t) / mx
    return rad


def egg_profile(W, H, cy, k, n=20):
    rad = egg_radius_fn(W, H, cy, k)
    Hh = H / 2
    pts = []
    for i in range(n + 1):
        t = -math.cos(math.pi * i / n)
        y = cy + t * Hh
        pts.append((rad(y) if 0 < i < n else 0.0, y))
    return pts


def m_egg_cap(W, H, cy, k, c, scale=1.0, rows=14, cols=14):
    """Front cap of the egg (points with z >= c) as a clean-boundary (y, theta) grid, scaled about the egg centre.
    Returns (mesh, boundary_points, boundary_normals)."""
    rad = egg_radius_fn(W, H, cy, k)
    Hh = H / 2
    lo, hi = cy - Hh, cy + Hh
    ys = np.linspace(lo, hi, 4001)
    rs = np.array([rad(y) for y in ys])
    inside = np.where(rs >= c)[0]
    y_lo, y_hi = ys[inside[0]], ys[inside[-1]]

    def normal_at(y):
        e = 1e-4
        dr = rad(min(y + e, hi)) - rad(max(y - e, lo))
        dy = min(y + e, hi) - max(y - e, lo)
        L = math.hypot(dr, dy) or 1.0
        return dy / L, -dr / L
    pos, nrm, idx = [], [], []
    right, left = [], []
    for i in range(rows + 1):
        y = y_lo + (y_hi - y_lo) * (1 - math.cos(math.pi * i / rows)) / 2
        r = max(rad(y), c)
        a = math.asin(min(c / r, 1.0))
        nr, ny = normal_at(y)
        for j in range(cols + 1):
            th = a + (math.pi - 2 * a) * j / cols
            p = (r * math.cos(th), y, r * math.sin(th))
            n = (nr * math.cos(th), ny, nr * math.sin(th))
            pos.append((p[0] * scale, cy + (p[1] - cy) * scale, p[2] * scale))
            nrm.append(n)
        right.append((pos[-(cols + 1)], nrm[-(cols + 1)]))
        left.append((pos[-1], nrm[-1]))
    for i in range(rows):
        for j in range(cols):
            a0 = i * (cols + 1) + j
            b0 = a0 + cols + 1
            idx += [a0, a0 + 1, b0, a0 + 1, b0 + 1, b0]
    loop = right + left[-2:0:-1]   # closed loop: right edge up, left edge down
    return fix_winding(gm._mesh(pos, nrm, idx)), [p for p, _ in loop], [n for _, n in loop]


# ---------------- part builders (local coordinates, origin = proximal joint) ----------------
def segment_prims(L, r0, r1, jr, seg=12):
    """Painted tapered segment hanging from the ball at the origin down to the distal joint at y = -L."""
    yc = -jr * 0.52                                   # cuff top wraps the lower part of the ball
    cuff = m_lathe([(jr * 0.7, yc), (r0 * 1.07, yc - 0.008, "h"), (r0 * 1.07, yc - 0.030, "h"), (r0 * 1.02, yc - 0.035)], seg)
    seam = m_lathe([(r0 * 1.0, yc - 0.033), (r0 * 1.0, yc - 0.041)], seg)
    body = m_lathe([(r0, yc - 0.040, "h"), (r1, -(L - 0.052)), (r1 * 1.04, -(L - 0.040), "h"),
                    (r1 * 0.92, -(L - 0.020)), (r1 * 0.6, -(L - 0.009)), (0.0, -(L - 0.006))], seg)
    return [(m_ball(jr, (0, 0, 0), 12, 6), "Joint"), (cuff, "PaintDark"), (seam, "Seam"), (body, "Paint")]


def head_prims():
    cy = HEAD_BOTTOM - SHOULDER_Y + HEAD_H / 2         # local (origin = neck joint)
    egg = m_lathe(egg_profile(HEAD_W, HEAD_H, cy, HEAD_K, 18), 20)
    ball = m_ball(JR["neck"], (0, 0, 0), 12, 6)
    return [(egg, "Paint"), (ball, "Joint")], cy


def faceplate_prims(cy):
    c = HEAD_W * 0.5 * 0.2                                # plate covers the front where z >= c
    cap, loop_p, loop_n = m_egg_cap(HEAD_W, HEAD_H, cy, HEAD_K, c, scale=1.012, rows=12, cols=12)
    rim = m_tube(loop_p, loop_n, 0.007, 5)
    return [(cap, "Face"), (rim, "Joint")]


def torso_prims():
    """Origin at hip centre. Pelvis block + dark waist ring + tapered chest block + shirt band + collar."""
    pel_y0, pel_y1 = 0.02, 0.205
    pelvis = m_rounded_box(0.31, pel_y1 - pel_y0, 0.21, 0.07, (0, (pel_y0 + pel_y1) / 2, 0))
    pelvis = taper_y(pelvis, pel_y0, pel_y1, 0.82, 1.0)
    waist = m_lathe([(0.085, 0.195), (0.097, 0.202, "h"), (0.097, 0.238, "h"), (0.085, 0.245)], 20)
    ch_y0, ch_y1 = 0.235, 0.48
    s0, s1 = 0.66, 1.0                                   # V-shaped chest: as wide as the shoulder balls on top, narrow waist
    chest = m_rounded_box(0.46, ch_y1 - ch_y0, 0.25, 0.09, (0, (ch_y0 + ch_y1) / 2, 0))
    chest = taper_y(chest, ch_y0, ch_y1, s0, s1)
    cups = merge([m_ball(0.082, (k * 0.185, 0.452, 0), 14, 7) for k in (1.0, -1.0)])  # rounded shoulder corners wrapping the balls
    band = m_rounded_rect_prism(0.46 * 1.015, 0.25 * 1.015, 0.09 * 1.015, 0.30, 0.385, 3)   # painted band, same section as the chest
    band = taper_y(band, ch_y0, ch_y1, s0, s1, renormal=False)
    collar = m_lathe([(0.06, ch_y1 - 0.004), (0.078, ch_y1 + 0.004, "h"), (0.078, ch_y1 + 0.02, "h"), (0.06, ch_y1 + 0.027)], 20)
    return [(pelvis, "Paint"), (waist, "Joint"), (chest, "Paint"), (cups, "Paint"), (band, "Shirt"), (collar, "PaintDark")]


def hand_prims(k):
    """Origin at wrist; palm faces the camera, fingers down, thumb outward (k = +1 left / -1 right)."""
    jr = JR["wrist"]
    ball = m_ball(jr, (0, 0, 0), 8, 4)
    cuff = m_lathe([(jr * 0.7, -jr * 0.45), (0.046, -jr * 0.45 - 0.006, "h"), (0.046, -0.036, "h"), (0.038, -0.042)], 10)
    palm = m_rounded_box(0.088, 0.088, 0.046, 0.018, (0, -0.078, 0), 1, 2)
    palm = taper_y(palm, -0.122, -0.034, 1.1, 0.9)

    def finger(r, length, seg=5):
        return m_lathe([(0.0, 0.004), (r * 0.8, 0.0, "h"), (r, -r * 0.6), (r, -(length - r)), (r * 0.72, -(length - r * 0.35)), (0.0, -length)], seg)
    fingers = []
    for x, length in ((0.036, 0.05), (0.012, 0.056), (-0.012, 0.053), (-0.036, 0.045)):
        f = rotate_z(finger(0.0125, length), 4.0 * (x / 0.036) * k)
        fingers.append(translate(f, (k * x, -0.118, 0.0)))
    thumb = translate(rotate_z(finger(0.013, 0.05), 60.0 * k), (k * 0.047, -0.07, 0.0))
    return [(ball, "Joint"), (cuff, "PaintDark"), (palm, "Paint"), (merge(fingers), "Paint"), (thumb, "Paint")]


def foot_prims():
    """Origin at ankle; shoe points +Z (towards the camera), sole on y = -ANKLE_Y (ground)."""
    jr = JR["ankle"]
    ball = m_ball(jr, (0, 0, 0), 10, 5)
    cuff = m_lathe([(jr * 0.7, -jr * 0.4), (0.06, -jr * 0.4 - 0.008, "h"), (0.06, -0.04, "h"), (0.052, -0.05)], 12)
    shoe = m_rounded_box(0.13, 0.078, 0.25, 0.038, (0, -0.05, 0.045), 2, 3)
    shoe = taper_z(shoe, 0.02, 0.17, 1.0, 0.9)
    sole = m_rounded_box(0.136, 0.02, 0.256, 0.009, (0, -0.08, 0.045), 1, 2)
    sole = taper_z(sole, 0.02, 0.17, 1.0, 0.9)
    return [(ball, "Joint"), (cuff, "PaintDark"), (shoe, "Paint"), (sole, "Sole")]


def mannequin_parts():
    """{part_name: (prims, rest_translation)} — same translations as gen_models.doll_parts."""
    P = {}
    P["Torso"] = (torso_prims(), (0, HIP_Y, 0))
    head, cy = head_prims()
    P["Head"] = (head, (0, SHOULDER_Y, 0))
    P["FacePlate"] = (faceplate_prims(cy), (0, 0, 0))
    for side, k in (("L", 1.0), ("R", -1.0)):
        P[f"UpperArm_{side}"] = (segment_prims(D["ua"], 0.060, 0.050, JR["shoulder"]), (SX * k, SHOULDER_Y, 0))
        P[f"LowerArm_{side}"] = (segment_prims(D["la"], 0.052, 0.044, JR["elbow"]), (SX * k, ELBOW_Y, 0))
        P[f"Hand_{side}"] = (hand_prims(k), (SX * k, WRIST_Y, 0))
        P[f"UpperLeg_{side}"] = (segment_prims(D["ul"], 0.075, 0.064, JR["hip"]), (HX * k, HIP_Y, 0))
        P[f"LowerLeg_{side}"] = (segment_prims(D["ll"], 0.066, 0.054, JR["knee"]), (HX * k, KNEE_Y, 0))
        P[f"Foot_{side}"] = (foot_prims(), (HX * k, ANKLE_Y, 0))
    return P


def write_part(path, name, prims):
    g = make_glb()
    root = g.node(name, g.mesh(name, prims))
    g.write(path, [root])


def build():
    os.makedirs(PARTS_OUT, exist_ok=True)
    parts = mannequin_parts()
    g = make_glb()
    ids = {name: g.mesh(name, prims) for name, (prims, _) in parts.items()}
    face = g.node("FacePlate", ids["FacePlate"])
    roots = [g.node(name, ids[name], tr, children=[face] if name == "Head" else None)
             for name, (_, tr) in parts.items() if name != "FacePlate"]
    g.write(os.path.join(OUT, "mannequin.glb"), roots)
    for name, (prims, _) in parts.items():
        write_part(os.path.join(PARTS_OUT, f"mannequin_{name}.glb"), name, prims)
    # report
    total = 0
    top = 0.0
    for name, (prims, tr) in parts.items():
        n = tri_count(prims)
        total += n
        ys = max(float(m[0][:, 1].max()) for m, _ in prims) + (tr[1] if name != "FacePlate" else SHOULDER_Y)
        top = max(top, ys)
        print(f"{name:12s} {n:5d} tris")
    hand = tri_count(parts["Hand_L"][0])
    print(f"total {total} tris; hand {hand} tris (limit 400); height {top:.3f} m (rig 1.89, auto-scale if off by >2 %)")
    assert hand <= 400, "hand over budget"
    assert abs(1.89 / top - 1.0) <= 0.02, "DollSkin would auto-scale the model"
    return parts


if __name__ == "__main__":
    build()
