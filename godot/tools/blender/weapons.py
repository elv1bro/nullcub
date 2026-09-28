"""Оружие по референсу R16 (docs/refs/R16-a-weapons-concept.jpg): молот, булава, меч, топор, сковородка.

Запуск:
  /Applications/Blender.app/Contents/MacOS/Blender -b --python godot/tools/blender/weapons.py [-- hammer mace ...]
Пишет godot/assets/models/weapons/<id>.glb (id: hammer, mace, sword, axe, pan) и печатает треугольники.

Соглашения (docs/plan-demo/ASSET_PIPELINE.md):
- метры; origin = точка ХВАТА (там, где центр кисти); оружие вытянуто вдоль +X (голова/лезвие от руки);
  сзади хвата (−X) остаётся навершие/торец рукояти;
- предмет лежит в плоскости X–Z Blender (тонкий по Y), «лицо» в −Y → после экспорта (Y вверх) в Godot
  предмет лежит в плоскости X–Y, лицо смотрит в +Z (в камеру);
- каждое оружие — 2–4 объекта с именами Handle / Head (+ Guard, Pommel), Godot импортирует их как MeshInstance3D;
- материалы Principled без текстур: Wood, WoodDark, Leather, Iron, IronDark, Steel, Brass, RedPaint;
- бюджет ≤ 4000 треугольников на оружие; фаски (Bevel) применяются до экспорта, статистика точная.

Габариты, которые использует godot/tools/build_weapon_scenes.gd (коллизии), — в таблице DIMS внизу
(печатается после сборки; при изменении геометрии обновить и билдер).
"""
import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "models", "weapons"))
BUDGET = 4000
TAU = math.tau
IDS = ["hammer", "mace", "sword", "axe", "pan"]


# ----------------------------------------------------------------------------- материалы
def srgb(h):
    """'#rrggbb' → линейный RGBA (glTF хранит base color линейно)."""
    h = h.lstrip("#")
    out = []
    for i in (0, 2, 4):
        c = int(h[i:i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return (out[0], out[1], out[2], 1.0)


def materials():
    return {
        "Wood": common.material("Wood", srgb("bb8a52"), rough=0.75),
        "WoodMid": common.material("WoodMid", srgb("a8763f"), rough=0.75),
        "WoodDark": common.material("WoodDark", srgb("7c4b27"), rough=0.8),
        "Leather": common.material("Leather", srgb("3f2416"), rough=0.7),
        "Iron": common.material("Iron", (0.35, 0.35, 0.37, 1.0), rough=0.4, metal=0.85),
        "IronDark": common.material("IronDark", (0.13, 0.115, 0.105, 1.0), rough=0.55, metal=0.75),
        "Steel": common.material("Steel", (0.62, 0.64, 0.68, 1.0), rough=0.3, metal=0.95),
        "Brass": common.material("Brass", srgb("c8963a"), rough=0.35, metal=0.9),
        "RedPaint": common.material("RedPaint", srgb("b8231c"), rough=0.55),
    }


# ----------------------------------------------------------------------------- геометрические хелперы
def select_only(obj):
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def new_mesh_obj(name, bm):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    return o


def earclip(pts):
    """Триангуляция простого 2D-многоугольника (ear clipping); возвращает тройки индексов. Для вогнутых контуров
    (корона, топор, клякса) — n-gon-крышки Blender на изогнутых/вогнутых контурах триангулируются неверно."""
    n = len(pts)
    idx = list(range(n))
    area = sum(pts[i - 1][0] * pts[i][1] - pts[i][0] * pts[i - 1][1] for i in range(n))
    if area < 0:
        idx.reverse()

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    def inside(p, a, b, c):
        return cross(a, b, p) >= 0 and cross(b, c, p) >= 0 and cross(c, a, p) >= 0

    tris = []
    guard = 0
    while len(idx) > 3 and guard < 10 * n:
        guard += 1
        m = len(idx)
        for k in range(m):
            i0, i1, i2 = idx[k - 1], idx[k], idx[(k + 1) % m]
            a, b, c = pts[i0], pts[i1], pts[i2]
            if cross(a, b, c) <= 1e-12:
                continue
            if any(inside(pts[j], a, b, c) for j in idx if j not in (i0, i1, i2)):
                continue
            tris.append((i0, i1, i2))
            del idx[k]
            break
        else:
            break
    if len(idx) == 3:
        tris.append(tuple(idx))
    return tris


def loft(name, rings, caps=True, closed=False, sharp_idx=(), tri_caps=False, cap2d=None):
    """Лофт: кольца одинаковой длины → боковые квады (+ n-gon крышки или замыкание последнего с первым).
    sharp_idx — индексы точек профиля, продольные рёбра которых помечаются острыми (для кромок клинка).
    cap2d — 2D-точки профиля (тот же порядок, что кольца) для надёжной триангуляции вогнутых крышек."""
    bm = bmesh.new()
    vr = [[bm.verts.new(Vector(p)) for p in ring] for ring in rings]
    n = len(rings[0])
    pairs = list(zip(vr[:-1], vr[1:]))
    if closed:
        pairs.append((vr[-1], vr[0]))
    for a, b in pairs:
        for j in range(n):
            k = (j + 1) % n
            bm.faces.new((a[j], a[k], b[k], b[j]))
        for j in sharp_idx:
            e = bm.edges.get((a[j], b[j]))
            if e is not None:
                e.smooth = False
    if caps and not closed and cap2d is not None:
        for (i, j, k) in earclip(cap2d):
            bm.faces.new((vr[0][k], vr[0][j], vr[0][i]))
            bm.faces.new((vr[-1][i], vr[-1][j], vr[-1][k]))
    elif caps and not closed:
        f0 = bm.faces.new(vr[0][::-1])
        f1 = bm.faces.new(vr[-1])
        if tri_caps:
            bmesh.ops.triangulate(bm, faces=[f0, f1], quad_method='BEAUTY', ngon_method='EAR_CLIP')
    return new_mesh_obj(name, bm)


def circle_pts(n, r, c, axis, phase=0.0):
    """n точек окружности радиуса r вокруг оси axis ('x'|'y'|'z') через центр c."""
    pts = []
    for i in range(n):
        a = phase + TAU * i / n
        u, v = r * math.cos(a), r * math.sin(a)
        if axis == 'x':
            pts.append((c[0], c[1] + u, c[2] + v))
        elif axis == 'y':
            pts.append((c[0] + u, c[1], c[2] + v))
        else:
            pts.append((c[0] + u, c[1] + v, c[2]))
    return pts


def rod_x(name, x0, x1, r0, r1=None, n=16, mids=()):
    """Стержень вдоль X: кольцо на x0 (r0), промежуточные mids=[(x, r)], кольцо на x1 (r1)."""
    r1 = r0 if r1 is None else r1
    rings = [circle_pts(n, r0, (x0, 0, 0), 'x')]
    for x, r in mids:
        rings.append(circle_pts(n, r, (x, 0, 0), 'x'))
    rings.append(circle_pts(n, r1, (x1, 0, 0), 'x'))
    return loft(name, rings)


def disc_z(name, r, z0, z1, c, n=24):
    """Диск/обруч с осью Z (ось бочки молота)."""
    return loft(name, [circle_pts(n, r, (c[0], c[1], z0), 'z'), circle_pts(n, r, (c[0], c[1], z1), 'z')])


def lathe_y(name, prof_ry, c, steps=36):
    """Тело вращения вокруг оси Y через c: профиль [(r, y), ...] (r от оси, y вдоль оси)."""
    bm = bmesh.new()
    verts = [bm.verts.new(Vector((c[0] + r, c[1] + y, c[2]))) for (r, y) in prof_ry]
    edges = [bm.edges.new((verts[i], verts[i + 1])) for i in range(len(verts) - 1)]
    bmesh.ops.spin(bm, geom=verts + edges, cent=Vector(c), axis=Vector((0, 1, 0)), dvec=Vector((0, 0, 0)),
                   angle=TAU, steps=steps, use_merge=True)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    return new_mesh_obj(name, bm)


def annulus_y(name, c, r_out, r_in, half_t, n=20):
    """Плоское кольцо (шайба) в плоскости X–Z, ось Y, толщина 2*half_t."""
    lo, hi = c[1] - half_t, c[1] + half_t
    rings = [circle_pts(n, r_out, (c[0], lo, c[2]), 'y'), circle_pts(n, r_out, (c[0], hi, c[2]), 'y'),
             circle_pts(n, r_in, (c[0], hi, c[2]), 'y'), circle_pts(n, r_in, (c[0], lo, c[2]), 'y')]
    return loft(name, rings, caps=False, closed=True)


def bevel_apply(obj, width, segments=2, angle=30.0, profile=0.5):
    m = obj.modifiers.new("Bevel", 'BEVEL')
    m.width = width
    m.segments = segments
    m.limit_method = 'ANGLE'
    m.angle_limit = math.radians(angle)
    m.profile = profile
    m.use_clamp_overlap = True
    select_only(obj)
    bpy.ops.object.modifier_apply(modifier=m.name)


def smooth(obj, angle=None):
    """Гладкое затенение; angle=None — всё гладко (торы/сферы), иначе острые рёбра по углу."""
    for p in obj.data.polygons:
        p.use_smooth = True
    if angle is not None:
        select_only(obj)
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(angle), keep_sharp_edges=True)


def finish(obj, mat, bevel=0.0, segs=2, angle=55.0):
    """Материал → фаска (применяется) → гладкость. angle 55°: две секции фаски (45°) остаются гладкими,
    настоящие рёбра (90°) — острыми."""
    common.assign(obj, mat)
    if bevel > 0.0:
        bevel_apply(obj, bevel, segs)
    smooth(obj, angle)
    return obj


def apply_all(obj):
    common.apply_transforms(obj, location=True, rotation=True, scale=True)


def sphere(name, r, loc, seg=12, ring=6):
    o = common.add_sphere(name, r, loc, segments=seg, rings=ring)
    apply_all(o)
    return o


def torus(name, major, minor, loc, rot, segs=12, ring=5):
    o = common.add_torus(name, major, minor, loc, rot, segs, ring)
    apply_all(o)
    return o


def wrap(prefix, x0, x1, count, major, minor, mat, tilt_deg=14.0, segs=12, ring=5):
    """Кожаная обмотка рукояти: наклонённые кольца вдоль X (ось кольца лежит в плоскости XZ, наклон tilt),
    читается как спиральная намотка."""
    objs = []
    for i in range(count):
        x = x0 + (x1 - x0) * i / max(count - 1, 1)
        o = torus("%s_%d" % (prefix, i), major, minor, (x, 0, 0), (0, math.pi / 2 + math.radians(tilt_deg), 0), segs, ring)
        objs.append(finish(o, mat))
    return objs


def cube(name, size, loc):
    o = common.add_cube(name, size, loc)
    apply_all(o)
    return o


def cone_dir(name, base_r, tip_r, length, origin, direction, verts=8):
    """Конус (шип) с основанием в origin, вершиной вдоль direction."""
    d = Vector(direction).normalized()
    o = common.add_cylinder(name, radius=base_r, depth=length, loc=(0, 0, 0), verts=verts, radius_top=tip_r)
    o.rotation_euler = d.to_track_quat('Z', 'Y').to_euler()
    o.location = Vector(origin) + d * (length / 2.0)
    apply_all(o)
    return o


def dist_to_polyline(p, poly):
    best = float("inf")
    px, py = p
    for (ax, ay), (bx, by) in zip(poly[:-1], poly[1:]):
        dx, dy = bx - ax, by - ay
        ll = dx * dx + dy * dy
        t = 0.0 if ll == 0 else max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / ll))
        qx, qy = ax + t * dx, ay + t * dy
        best = min(best, math.hypot(px - qx, py - qy))
    return best


# ----------------------------------------------------------------------------- 01 молот
def build_hammer(M):
    """Бочка-голова Ø0.32×0.40 из 12 клёпок с пузом, два обруча с заклёпками, красная корона,
    рукоять 0.75 м с кожаной обмоткой, железные торец и втулка. Ось бочки — Z (вертикаль экрана)."""
    cx = 0.80                        # центр бочки по X
    r_mid, r_end, hz = 0.16, 0.145, 0.20
    depth, n_st, gap = 0.03, 12, 0.006

    def R(z):
        return r_mid - (r_mid - r_end) * (z / hz) ** 2

    head = []
    for i in range(n_st):
        th = TAU * i / n_st
        rings = []
        for z in (-hz, 0.0, hz):
            ro = R(z)
            ri = ro - depth
            hw = (TAU * ro / n_st - gap) / 2.0
            pts = []
            for t, rho in ((-hw, ri), (hw, ri), (hw, ro), (-hw, ro)):
                x, y = t, -rho          # клёпка спереди (−Y), потом поворот вокруг оси бочки
                pts.append((cx + x * math.cos(th) - y * math.sin(th), x * math.sin(th) + y * math.cos(th), z))
            rings.append(pts)
        head.append(finish(loft("Stave_%d" % i, rings), M["Wood"] if i % 2 == 0 else M["WoodMid"], bevel=0.006, segs=2))
    for s in (-1, 1):
        head.append(finish(disc_z("Lid_%d" % (s + 1), 0.135, s * 0.176, s * 0.197, (cx, 0), n=20), M["WoodDark"], bevel=0.004, segs=1))
        zb = s * 0.14
        rb = R(zb) + 0.007
        head.append(finish(disc_z("Band_%d" % (s + 1), rb, zb - 0.018, zb + 0.018, (cx, 0), n=24), M["Iron"], bevel=0.004, segs=1))
        for k in range(6):
            th = TAU * k / 6
            riv = sphere("Rivet_%d_%d" % (s + 1, k), 0.0095, (cx + (rb + 0.002) * math.sin(th), -(rb + 0.002) * math.cos(th), zb), 8, 3)
            head.append(finish(riv, M["Iron"]))
    # эмблема-корона, обёрнутая по пузу бочки (u — вдоль окружности, v — вдоль оси)
    # u — ширина короны (вдоль оси бочки Z), v — высота (зубцы к +X, т.е. «вверх», когда молот стоит головой вверх)
    crown = [(-0.068, -0.052), (0.068, -0.052), (0.068, -0.024), (0.059, 0.062), (0.03, 0.0), (0.0, 0.074),
             (-0.03, 0.0), (-0.059, 0.062), (-0.068, -0.024)]

    def bend(u, v, w):
        a = v / r_mid                    # высота короны идёт по окружности бочки
        rad = R(u) + w
        return (cx + rad * math.sin(a), -rad * math.cos(a), u)

    emblem = loft("Emblem", [[bend(u, v, -0.008) for (u, v) in crown], [bend(u, v, 0.0035) for (u, v) in crown]], cap2d=crown)
    head.append(finish(emblem, M["RedPaint"], bevel=0.0015, segs=1))

    handle = [finish(rod_x("Shaft", -0.065, 0.66, 0.028), M["Wood"])]
    handle.append(finish(rod_x("Butt", -0.085, -0.06, 0.034), M["Iron"], bevel=0.004, segs=2))
    handle.append(finish(rod_x("Ferrule", 0.585, 0.65, 0.037), M["Iron"], bevel=0.004, segs=2))
    handle += wrap("Wrap", -0.045, 0.215, 6, 0.030, 0.007, M["Leather"])
    return [common.join(handle, "Handle"), common.join(head, "Head")]


# ----------------------------------------------------------------------------- 02 булава
def build_mace(M):
    """Шипастый железный шар Ø0.24 (14 конусов), железная рукоять с кожаной обмоткой, втулка,
    кольцо-навершие в плоскости экрана."""
    c = Vector((0.62, 0.0, 0.0))
    r = 0.12
    head = [finish(sphere("Ball", r, c, 24, 12), M["Iron"])]
    dirs = []
    for k in range(8):                       # кольцо в плоскости экрана X–Z, кроме направления рукояти
        a = TAU * k / 8
        d = Vector((math.cos(a), 0.0, math.sin(a)))
        if d.x < -0.9:
            continue
        dirs.append(d)
    el = math.radians(50)
    for a_deg in (30, 150, 270):             # три к камере (−Y) и три назад
        a = math.radians(a_deg)
        base = Vector((math.cos(a), 0.0, math.sin(a))) * math.cos(el)
        dirs.append(Vector((base.x, -math.sin(el), base.z)))
        dirs.append(Vector((base.x, math.sin(el), base.z)))
    dirs.append(Vector((0.0, -1.0, 0.0)))
    assert len(dirs) == 14
    for i, d in enumerate(dirs):
        head.append(finish(cone_dir("Spike_%d" % i, 0.028, 0.004, 0.095, c + d.normalized() * (r - 0.012), d), M["Iron"]))
    head.append(finish(rod_x("Collar", 0.45, 0.515, 0.034), M["Iron"], bevel=0.005, segs=2))
    head.append(finish(torus("CollarRing", 0.036, 0.006, (0.46, 0, 0), (0, math.pi / 2, 0), 20, 6), M["Iron"]))

    handle = [finish(rod_x("Shaft", -0.07, 0.46, 0.022), M["IronDark"])]
    handle += wrap("Wrap", -0.03, 0.25, 8, 0.024, 0.006, M["Leather"])
    knob = finish(sphere("Knob", 0.022, (-0.07, 0, 0), 12, 6), M["Iron"])
    ring = finish(torus("Ring", 0.028, 0.007, (-0.115, 0, 0), (math.pi / 2, 0, 0), 20, 8), M["Iron"])
    return [common.join(handle, "Handle"), common.join(head, "Head"), common.join([knob, ring], "Pommel")]


# ----------------------------------------------------------------------------- 03 меч
def build_sword(M):
    """Обоюдоострый клинок 0.72 м с долом, латунная гарда, обмотанная рукоять, круглое навершие.
    Origin — середина рукояти."""
    xb0, xb1 = 0.092, 0.81

    def prof(x):
        if x < 0.62:
            hw = 0.038 - (0.038 - 0.031) * (x - xb0) / (0.62 - xb0)
        else:
            hw = 0.031 - (0.031 - 0.003) * (x - 0.62) / (xb1 - 0.62)
        ht = 0.006 - 0.0045 * (x - xb0) / (xb1 - xb0)
        # дол: полная глубина 0.13..0.50, плавно сходит на нет к 0.10 и 0.56
        if x <= 0.10 or x >= 0.60:
            fd = 0.0
        elif x < 0.13:
            fd = 0.0035 * (x - 0.10) / 0.03
        elif x > 0.48:
            fd = 0.0035 * (0.60 - x) / 0.12
        else:
            fd = 0.0035
        fw = min(0.013, 0.4 * hw)
        return hw, ht, fd, fw

    def ring(x):
        hw, ht, fd, fw = prof(x)
        zy = [(hw, 0), (0.45 * hw, ht), (fw, ht), (0.6 * fw, ht - fd), (-0.6 * fw, ht - fd), (-fw, ht), (-0.45 * hw, ht),
              (-hw, 0), (-0.45 * hw, -ht), (-fw, -ht), (-0.6 * fw, -ht + fd), (0.6 * fw, -ht + fd), (fw, -ht), (0.45 * hw, -ht)]
        return [(x, y, z) for (z, y) in zy]

    xs = [xb0, 0.10, 0.13, 0.48, 0.54, 0.60, 0.66, 0.74, xb1]
    blade = finish(loft("Blade", [ring(x) for x in xs], sharp_idx=(0, 7, 2, 5, 9, 12)), M["Steel"], angle=30)
    guard = finish(cube("Guard", (0.03, 0.02, 0.235), (0.077, 0, 0)), M["Brass"], bevel=0.007, segs=3)
    handle = [finish(rod_x("GripCore", -0.06, 0.062, 0.016, n=12), M["Leather"])]
    handle += wrap("Wrap", -0.05, 0.05, 6, 0.017, 0.0055, M["Leather"], tilt_deg=16)
    pommel = finish(sphere("Pommel", 0.028, (-0.088, 0, 0), 16, 8), M["Brass"])
    return [common.join(handle, "Handle"), _rename(blade, "Head"), _rename(guard, "Guard"), _rename(pommel, "Pommel")]


def _rename(obj, name):
    obj.name = name
    return obj


# ----------------------------------------------------------------------------- 04 топор
def build_axe(M):
    """Топорище 0.9 м, широкая бородатая железная голова (кромка в −Z), красная краска-эмблема на щеке,
    железный обух-проушина, кожаные обмотки у хвата и под головой.
    Голова — лофт [передняя щека (внутренний контур), контур спереди, контур сзади, задняя щека]:
    у кромки внутренний контур отступает на 7.5 см и толщина 3 мм (длинный спуск), у обуха — маленькая фаска."""
    haft = finish(rod_x("Haft", -0.10, 0.80, 0.021, 0.027, mids=[(0.35, 0.024)]), M["WoodDark"], bevel=0.005, segs=2)
    # контур в (x, s): x вдоль топорища, s — к кромке (в сцене s → −Z). Против часовой стрелки.
    outline = [(0.79, -0.05), (0.79, 0.05), (0.80, 0.13), (0.81, 0.23),                       # обух, верх щеки, верхний рог
               (0.79, 0.275), (0.74, 0.31), (0.66, 0.325), (0.58, 0.31), (0.52, 0.28), (0.47, 0.245),   # кромка
               (0.49, 0.205), (0.54, 0.155), (0.59, 0.105), (0.615, 0.065), (0.62, 0.045),     # борода
               (0.62, -0.05), (0.705, -0.062)]                                                 # низ обуха
    # спуск к кромке: ширина по индексам контура (сходит на нет к соседям рогов, чтобы не было «ступенек»)
    grind_w = {2: 0.01, 3: 0.04, 4: 0.06, 5: 0.07, 6: 0.075, 7: 0.07, 8: 0.06, 9: 0.04, 10: 0.01}
    arc_idx = sorted(grind_w)
    ht, edge_t = 0.014, 0.0015

    def inward(i):
        """Внутренняя биссектриса контура в вершине i (контур против часовой стрелки)."""
        n = len(outline)
        px, py = outline[i - 1]
        vx, vy = outline[i]
        nx, ny = outline[(i + 1) % n]
        e1 = (vx - px, vy - py)
        e2 = (nx - vx, ny - vy)
        l1 = math.hypot(*e1) or 1.0
        l2 = math.hypot(*e2) or 1.0
        n1 = (-e1[1] / l1, e1[0] / l1)
        n2 = (-e2[1] / l2, e2[0] / l2)
        bx, by = n1[0] + n2[0], n1[1] + n2[1]
        lb = math.hypot(bx, by) or 1.0
        bx, by = bx / lb, by / lb
        return bx, by, max(bx * n1[0] + by * n1[1], 0.6)

    area = sum(outline[i - 1][0] * outline[i][1] - outline[i][0] * outline[i - 1][1] for i in range(len(outline)))
    assert area > 0, "outline must be CCW"
    grind_inner = {}
    for i in arc_idx:
        bx, by, c = inward(i)
        grind_inner[i] = (outline[i][0] + bx * grind_w[i] / c, outline[i][1] + by * grind_w[i] / c)
    plate = [grind_inner.get(i, p) for i, p in enumerate(outline)]

    def segs_cross(a, b, c, d):
        def orient(p, q, r):
            return (q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0])
        return (orient(a, b, c) * orient(a, b, d) < 0) and (orient(c, d, a) * orient(c, d, b) < 0)

    n = len(plate)
    for i in range(n):
        for j in range(i + 2, n):
            if i == 0 and j == n - 1:
                continue
            assert not segs_cross(plate[i], plate[(i + 1) % n], plate[j], plate[(j + 1) % n]), "axe plate self-intersects %d/%d" % (i, j)

    def to3(p, y):
        return (p[0], y, -p[1])

    body = loft("Plate", [[to3(p, -ht) for p in plate], [to3(p, ht) for p in plate]], cap2d=plate)
    finish(body, M["Iron"], bevel=0.005, segs=2)
    # спуск к кромке: лофт сечений вдоль дуги (трапеция: внутри ±ht, на кромке ±edge_t)
    sections = []
    for i in arc_idx:
        gi = grind_inner[i]
        o = outline[i]
        sections.append([to3(gi, -ht + 0.0005), to3(gi, ht - 0.0005), to3(o, edge_t), to3(o, -edge_t)])
    grind = loft("Grind", sections, sharp_idx=(2, 3))
    finish(grind, M["Iron"], angle=40)
    blade = common.join([body, grind], "Head")
    eye = finish(cube("Eye", (0.17, 0.05, 0.115), (0.705, 0, 0)), M["Iron"], bevel=0.009, segs=2)
    splash = [(0, 0.05), (0.018, 0.02), (0.05, 0.03), (0.033, 0.0), (0.05, -0.03), (0.015, -0.02), (0, -0.05),
              (-0.02, -0.02), (-0.045, -0.035), (-0.03, 0.0), (-0.05, 0.03), (-0.02, 0.02)]
    ec = (0.66, 0.15)
    pts = [(ec[0] + u * 0.9, ec[1] + v * 0.9) for (u, v) in splash]
    emblem = loft("Emblem", [[to3(p, -ht - 0.0015) for p in pts], [to3(p, -ht + 0.004) for p in pts]], cap2d=pts)
    finish(emblem, M["RedPaint"], bevel=0.0012, segs=1)
    handle = [haft]
    handle += wrap("Wrap", -0.06, 0.10, 5, 0.023, 0.006, M["Leather"])
    handle += wrap("WrapTop", 0.49, 0.56, 3, 0.027, 0.006, M["Leather"], tilt_deg=10)
    return [common.join(handle, "Handle"), common.join([blade, eye, emblem], "Head")]


# ----------------------------------------------------------------------------- 05 сковородка
def build_pan(M):
    """Сковорода Ø0.36 (тело вращения, дно назад, открыта к камере), валик по кромке, плоская рукоять 0.35 м
    с проушиной для подвеса и двумя заклёпками. Тёмное железо."""
    cx, R = 0.53, 0.18
    prof = [(0.0, 0.03), (0.15, 0.03), (0.163, 0.024), (0.176, -0.024), (R, -0.03), (0.172, -0.03), (0.169, -0.022),
            (0.152, 0.02), (0.142, 0.024), (0.0, 0.024)]
    pan = finish(lathe_y("Pan", prof, (cx, 0, 0), steps=36), M["IronDark"], angle=55)
    rim = finish(torus("Rim", 0.176, 0.006, (cx, -0.03, 0), (math.pi / 2, 0, 0), 36, 6), M["IronDark"])
    head = [pan, rim]

    def rect(x, hy, hz):
        return [(x, -hy, -hz), (x, hy, -hz), (x, hy, hz), (x, -hy, hz)]

    bar = finish(loft("Bar", [rect(-0.035, 0.004, 0.013), rect(0.20, 0.004, 0.015), rect(0.36, 0.004, 0.019)]), M["IronDark"], bevel=0.0025, segs=2)
    eye = finish(annulus_y("Eye", (-0.06, 0, 0), 0.032, 0.012, 0.004, n=20), M["IronDark"], bevel=0.002, segs=1)
    handle = [bar, eye]
    for i, x in enumerate((0.30, 0.335)):
        handle.append(finish(sphere("Rivet_%d" % i, 0.007, (x, -0.005, 0), 8, 4), M["IronDark"]))
    return [common.join(handle, "Handle"), common.join(head, "Head")]


# ----------------------------------------------------------------------------- габариты для коллизий
# Blender-координаты (x вдоль, y — толщина, z — поперёк экрана). Godot: x→x, z→y, −y→z.
DIMS = {
    "hammer": {"handle_x": (-0.085, 0.66), "handle_r": 0.034, "head_center_x": 0.80, "head_r": 0.16, "head_len_z": 0.40, "length": 1.045},
    "mace": {"handle_x": (-0.143, 0.46), "handle_r": 0.03, "head_center_x": 0.62, "head_r": 0.12, "spike_reach": 0.203, "length": 0.965},
    "sword": {"handle_x": (-0.116, 0.062), "handle_r": 0.028, "guard_x": (0.062, 0.092), "guard_z": 0.1175, "guard_y": 0.01,
              "blade_x": (0.092, 0.81), "blade_z": 0.038, "blade_y": 0.006, "length": 0.926},
    "axe": {"handle_x": (-0.10, 0.80), "handle_r": 0.027, "head_x": (0.47, 0.81), "head_z": (-0.325, 0.062), "head_y": 0.025, "length": 0.91},
    "pan": {"handle_x": (-0.092, 0.36), "handle_z": 0.019, "handle_y": 0.004, "pan_center_x": 0.53, "pan_r": 0.18, "pan_y": (-0.036, 0.03), "length": 0.802},
}

BUILDERS = {"hammer": build_hammer, "mace": build_mace, "sword": build_sword, "axe": build_axe, "pan": build_pan}


def main():
    ids = [a for a in common.args_after_dashdash() if a in BUILDERS] or IDS
    report = {}
    for wid in ids:
        common.reset_scene()
        objs = BUILDERS[wid](materials())
        for o in objs:
            o.location = (0, 0, 0)          # origin = хват (вся геометрия строится в мировых координатах)
        st = common.stats()
        report[wid] = st["tris"]
        flag = "" if st["tris"] <= BUDGET else "  !!! OVER BUDGET %d" % BUDGET
        print("weapon %-6s objects=%s tris=%d%s" % (wid, [o.name for o in objs], st["tris"], flag))
        common.export_glb(os.path.join(OUT, wid + ".glb"), objs)
    print("=== weapons tris === " + json.dumps(report))
    print("=== dims === " + json.dumps(DIMS))


if __name__ == "__main__":
    main()
