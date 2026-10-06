#!/usr/bin/env python3
"""Гараж бойца для главного меню «Гараж + эфир» (docs/plan-demo/MENU_GARAGE.md). Референсы автора 02.10.2026:
docs/refs/menu-garage/G01-garage-keyframe.png (кадр стиля), G02/G03 (листы предметов).

Запуск (headless, Blender 4.5 LTS):
    blender -b --python godot/tools/blender/garage_kit.py [-- Имя …]
    → godot/assets/models/garage/Garage_<Имя>.glb, сводка «=== garage kit === {json}», код 1 при превышении бюджета.

Соглашения (ASSET_PIPELINE.md, common.py): метры; Blender Z вверх, X вбок, фронт предмета смотрит в −Y (в Godot +Z, к камере).
Origin каждого предмета — центр основания на полу (z = 0), если в таблице MODULES не сказано иначе (настенное — центр
задней плоскости у стены, подвесное — точка подвеса).

Материалы в glb ПЛОСКИЕ, имя материала = роль (Wood, Iron, PaintNavy, Hazard, Screen…). Настоящие материалы (текстуры
assets/textures/garage + kit/tex) ставит Godot по роли: scripts/menu/garage_materials.gd. Развёртка — коробкой в метрах
(1 тайл = 1 м), у каждой детали своя ось волокна и случайный сдвиг, чтобы доски не повторялись.
"""
import bpy
import bmesh
import json
import math
import os
import random
import sys
from mathutils import Euler, Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import common as C  # noqa: E402

OUT = os.path.abspath(os.path.join(HERE, "..", "..", "assets", "models", "garage"))
TRI_BUDGET = 12000          # на предмет; комнатные модули (пол, стены) — TRI_BUDGET_BIG
TRI_BUDGET_BIG = 30000

# Роль → цвет для превью в Blender (в игре роль заменяется материалом Godot).
ROLES = {
    "Wood": (0.55, 0.32, 0.17), "WoodDark": (0.30, 0.19, 0.12), "WoodWall": (0.26, 0.17, 0.11),
    "Iron": (0.16, 0.17, 0.19), "Steel": (0.45, 0.47, 0.50), "Brass": (0.62, 0.42, 0.18), "Bronze": (0.55, 0.32, 0.18),
    "PaintNavy": (0.16, 0.23, 0.36), "PaintOlive": (0.33, 0.36, 0.20), "PaintRed": (0.62, 0.12, 0.09),
    "PaintCream": (0.84, 0.78, 0.64), "PaintGreen": (0.17, 0.32, 0.24), "PaintGrey": (0.32, 0.34, 0.36),
    "Hazard": (0.85, 0.65, 0.10), "Tread": (0.30, 0.31, 0.33), "Floor": (0.18, 0.18, 0.19), "Rubber": (0.05, 0.05, 0.05),
    "Screen": (0.05, 0.08, 0.12), "NullGlow": (0.6, 0.4, 1.0), "Bulb": (1.0, 0.8, 0.5), "LampRed": (1.0, 0.1, 0.05),
    "LampAmber": (1.0, 0.6, 0.2), "LampGreen": (0.2, 1.0, 0.3), "Glass": (0.6, 0.7, 0.8), "Enamel": (0.9, 0.88, 0.8),
    "Ceramic": (0.88, 0.86, 0.80), "Coffee": (0.12, 0.06, 0.03), "Leaves": (0.20, 0.38, 0.14), "Pot": (0.62, 0.32, 0.20),
    "ClothRed": (0.55, 0.10, 0.10), "Paper": (0.85, 0.80, 0.70), "Grille": (0.10, 0.10, 0.11), "Rope": (0.6, 0.45, 0.28),
    # картинки (UV 0..1): чертёж, фото, афиши, ковёр, флаг — текстуры assets/textures/garage/*.png
    "Blueprint": (0.15, 0.3, 0.5), "Rug": (0.45, 0.1, 0.08), "BannerCloth": (0.5, 0.1, 0.1),
    "Photo_A": (0.7, 0.6, 0.5), "Photo_B": (0.7, 0.6, 0.5), "Photo_C": (0.7, 0.6, 0.5), "Photo_D": (0.7, 0.6, 0.5),
    "Photo_E": (0.7, 0.6, 0.5), "Photo_F": (0.7, 0.6, 0.5), "Poster_A": (0.6, 0.4, 0.3), "Poster_B": (0.4, 0.5, 0.6),
    "Poster_C": (0.5, 0.4, 0.6),
    # пилотское место и стенд экранов (06.10): нейрошлем, кресло, консоль связи, мониторы
    "PlasticDark": (0.07, 0.075, 0.085), "PlasticLight": (0.78, 0.76, 0.72), "Visor": (0.02, 0.03, 0.05),
    "LinkGlow": (0.25, 0.9, 1.0), "Leather": (0.09, 0.07, 0.065), "Fabric": (0.16, 0.17, 0.2),
}

_rng = random.Random(7)


# ----------------------------------------------------------------------------------------------------------------------
# материалы и детали
# ----------------------------------------------------------------------------------------------------------------------
def mat(role):
    m = bpy.data.materials.get(role)
    if m is None:
        c = ROLES[role]
        m = C.material(role, base=(c[0], c[1], c[2], 1.0), rough=0.6)
    return m


def _bevel_sharp(bm, offset, seg=1, angle=30.0):
    if offset <= 0:
        return
    edges = [e for e in bm.edges if len(e.link_faces) == 2 and e.calc_face_angle(0.0) > math.radians(angle)]
    edges += [e for e in bm.edges if len(e.link_faces) == 1]
    if edges:
        bmesh.ops.bevel(bm, geom=edges, offset=offset, segments=seg, profile=0.5, affect='EDGES', clamp_overlap=True)


def _xform(bm, loc=(0, 0, 0), rot=(0, 0, 0), scale=None):
    if scale is not None:
        bmesh.ops.scale(bm, vec=Vector(scale), verts=bm.verts)
    if any(rot):
        m = Euler([math.radians(a) for a in rot], 'XYZ').to_matrix()
        bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=m, verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(loc), verts=bm.verts)


def bm_box(size, loc=(0, 0, 0), rot=(0, 0, 0), bevel=0.0, seg=1):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    _bevel_sharp(bm, min(bevel, min(size) * 0.45), seg)
    _xform(bm, loc, rot)
    return bm


def bm_cyl(r, depth, loc=(0, 0, 0), rot=(0, 0, 0), segs=16, r2=None, bevel=0.0, seg=1, caps=True):
    """Цилиндр (конус при r2) вдоль Z, центр в loc; rot поворачивает (90,0,0) → вдоль Y, (0,90,0) → вдоль X."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=caps, cap_tris=False, segments=segs, radius1=r, radius2=r if r2 is None else r2, depth=depth)
    _bevel_sharp(bm, bevel, seg, angle=40.0)
    _xform(bm, loc, rot)
    return bm


def bm_sphere(r, loc=(0, 0, 0), segs=12, rings=8, scale=(1, 1, 1)):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=r)
    bmesh.ops.scale(bm, vec=Vector(scale), verts=bm.verts)
    _xform(bm, loc)
    return bm


def bm_lathe(profile, segs=24, loc=(0, 0, 0), rot=(0, 0, 0), cap_bottom=True, cap_top=False):
    """Тело вращения вокруг Z: profile — [(r, z), …] снизу вверх (r=0 — точка на оси)."""
    bm = bmesh.new()
    rings = []
    for r, z in profile:
        ring = []
        for i in range(segs):
            a = 2 * math.pi * i / segs
            ring.append(bm.verts.new((r * math.cos(a), r * math.sin(a), z)))
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        for i in range(segs):
            j = (i + 1) % segs
            try:
                bm.faces.new((a[i], a[j], b[j], b[i]))
            except ValueError:
                pass
    if cap_bottom and profile[0][0] > 1e-4:
        bm.faces.new(list(reversed(rings[0])))
    if cap_top and profile[-1][0] > 1e-4:
        bm.faces.new(rings[-1])
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    _xform(bm, loc, rot)
    return bm


def bm_prism(pts, depth, loc=(0, 0, 0), rot=(0, 0, 0), bevel=0.0):
    """Плоская фигура pts [(x, z), …] в плоскости XZ, выдавлена на depth по +Y (лицо в −Y)."""
    bm = bmesh.new()
    vs = [bm.verts.new((x, -depth * 0.5, z)) for x, z in pts]
    f = bm.faces.new(vs)
    ext = bmesh.ops.extrude_face_region(bm, geom=[f])
    nv = [g for g in ext["geom"] if isinstance(g, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=(0, depth, 0), verts=nv)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    _bevel_sharp(bm, bevel, 1, angle=40.0)
    _xform(bm, loc, rot)
    return bm


def bm_torus(R, r, loc=(0, 0, 0), rot=(0, 0, 0), segs=16, rsegs=8, arc=1.0):
    bm = bmesh.new()
    rings = []
    n = segs if arc >= 1.0 else segs + 1
    for i in range(n):
        a = 2 * math.pi * arc * i / segs
        ca, sa = math.cos(a), math.sin(a)
        ring = []
        for k in range(rsegs):
            b = 2 * math.pi * k / rsegs
            rr = R + r * math.cos(b)
            ring.append(bm.verts.new((rr * ca, rr * sa, r * math.sin(b))))
        rings.append(ring)
    pairs = list(zip(rings, rings[1:])) + ([(rings[-1], rings[0])] if arc >= 1.0 else [])
    for a, b in pairs:
        for k in range(rsegs):
            m = (k + 1) % rsegs
            bm.faces.new((a[k], b[k], b[m], a[m]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    _xform(bm, loc, rot)
    return bm


def _rrect(w, h, r, n):
    """Точки скруглённого прямоугольника (против часовой, от правого нижнего угла), n точек на угол."""
    r = min(r, w * 0.5 - 1e-4, h * 0.5 - 1e-4)
    cs = [(w / 2 - r, -h / 2 + r, -90), (w / 2 - r, h / 2 - r, 0), (-w / 2 + r, h / 2 - r, 90), (-w / 2 + r, -h / 2 + r, 180)]
    pts = []
    for cx, cz, a0 in cs:
        for i in range(n):
            a = math.radians(a0 + 90.0 * i / max(n - 1, 1))
            pts.append((cx + r * math.cos(a), cz + r * math.sin(a)))
    return pts


def bm_rframe(ow, oh, orad, iw, ih, irad, depth, loc=(0, 0, 0), rot=(0, 0, 0), n=6, bevel=0.0):
    """Рамка: внешний и внутренний скруглённые прямоугольники в плоскости XZ, толщина depth по +Y."""
    bm = bmesh.new()
    outer = _rrect(ow, oh, orad, n)
    inner = _rrect(iw, ih, irad, n)

    def ring(pts, y):
        return [bm.verts.new((x, y, z)) for x, z in pts]
    o0, i0 = ring(outer, -depth / 2), ring(inner, -depth / 2)
    o1, i1 = ring(outer, depth / 2), ring(inner, depth / 2)
    N = len(outer)
    for k in range(N):
        m = (k + 1) % N
        bm.faces.new((o0[k], o0[m], i0[m], i0[k]))        # перед
        bm.faces.new((o1[m], o1[k], i1[k], i1[m]))        # зад
        bm.faces.new((o0[m], o0[k], o1[k], o1[m]))        # внешняя кромка
        bm.faces.new((i0[k], i0[m], i1[m], i1[k]))        # внутренняя кромка
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    _bevel_sharp(bm, bevel, 1, angle=40.0)
    _xform(bm, loc, rot)
    return bm


def bm_rslab(w, h, r, depth, loc=(0, 0, 0), rot=(0, 0, 0), n=6, bevel=0.0):
    """Скруглённая пластина в плоскости XZ толщиной depth по Y."""
    return bm_prism(_rrect(w, h, r, n), depth, loc, rot, bevel)


def bm_grid(w, h, nx, nz, bulge=0.0, loc=(0, 0, 0)):
    """Экран: сетка w×h в плоскости XZ лицом в −Y, выпуклость bulge к зрителю; UV 0..1 (для картинки эфира)."""
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    vs = []
    for j in range(nz + 1):
        row = []
        for i in range(nx + 1):
            u, v = i / nx, j / nz
            x, z = (u - 0.5) * w, (v - 0.5) * h
            d = bulge * (1.0 - (2 * u - 1) ** 2) * (1.0 - (2 * v - 1) ** 2)
            row.append(bm.verts.new((x, -d, z)))
        vs.append(row)
    for j in range(nz):
        for i in range(nx):
            f = bm.faces.new((vs[j][i], vs[j][i + 1], vs[j + 1][i + 1], vs[j + 1][i]))
            for lp, (ii, jj) in zip(f.loops, ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1))):
                lp[uv].uv = (ii / nx, jj / nz)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:            # лицом в −Y
        if f.normal.y > 0:
            f.normal_flip()
    _xform(bm, loc)
    return bm


class Asset:
    """Набор деталей одного предмета; finish() склеивает в один объект с слотами материалов."""

    def __init__(self, name):
        self.name = name
        self.parts = []

    def add(self, bm, role, along='Z', smooth=False, keep_uv=False):
        me = bpy.data.meshes.new(self.name + "_p")
        bm.to_mesh(me)
        bm.free()
        ob = bpy.data.objects.new(self.name + "_p", me)
        bpy.context.collection.objects.link(ob)
        me.materials.append(mat(role))
        if not keep_uv:
            _uv_box(me, along)
        if smooth:
            for p in me.polygons:
                p.use_smooth = True
        self.parts.append(ob)
        return ob

    def finish(self):
        root = C.join(self.parts, self.name) if len(self.parts) > 1 else self.parts[0]
        root.name = self.name          # join сам сводит одинаковые материалы в один слот
        return root


def _uv_box(me, along='Z'):
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    uv = me.uv_layers[0].data
    ai = 'XYZ'.index(along)
    ou, ov = _rng.random(), _rng.random()
    for poly in me.polygons:
        n = poly.normal
        ax = max(range(3), key=lambda k: abs(n[k]))
        rest = [k for k in range(3) if k != ax]
        if ai in rest:
            vax, uax = ai, [k for k in rest if k != ai][0]
        else:
            uax, vax = rest
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            uv[li].uv = (co[uax] + ou, co[vax] + ov)


def rivets(a, pts, r=0.012, axis='Y', role="Iron"):
    """Заклёпки-полусферы: pts — центры на поверхности, головка смотрит вдоль −axis (по умолчанию к зрителю)."""
    rot = {'Y': (90, 0, 0), '-Y': (-90, 0, 0), 'X': (0, 90, 0), '-X': (0, -90, 0), 'Z': (0, 0, 0), '-Z': (180, 0, 0)}[axis]
    for p in pts:
        a.add(bm_cyl(r, r * 0.8, p, rot, segs=6, r2=r * 0.55), role)


# ----------------------------------------------------------------------------------------------------------------------
# телевизор, тумба, ящики, кружка (ИСТОРИЯ)
# ----------------------------------------------------------------------------------------------------------------------
def build_TV(name):
    """Ламповый телевизор 1.5 × 0.95 × 0.72 (корпус дерево, экран слева, справа панель: 2 ручки, кнопки, решётка).
    Экран — отдельная деталь с ролью Screen и UV 0..1 (Godot кладёт туда эфир). Origin — центр низа."""
    a = Asset(name)
    W, H, D = 1.50, 0.95, 0.72
    a.add(bm_rslab(W, H, 0.08, D, loc=(0, 0, H / 2 + 0.06), bevel=0.012), "Wood", along='X')
    # передняя рамка-обвод чуть темнее
    a.add(bm_rframe(W + 0.012, H + 0.012, 0.085, W - 0.08, H - 0.08, 0.05, 0.05, loc=(0, -D / 2 - 0.005, H / 2 + 0.06), bevel=0.006), "WoodDark", along='X')
    # ниша экрана: рамка-кинескоп
    sx, sw, sh = -0.18, 1.0, 0.76
    a.add(bm_rframe(sw + 0.09, sh + 0.09, 0.09, sw - 0.02, sh - 0.02, 0.11, 0.06, loc=(sx, -D / 2 - 0.02, H / 2 + 0.06), bevel=0.008), "Iron")
    scr = bm_grid(sw + 0.02, sh + 0.02, 16, 12, bulge=0.035, loc=(sx, -D / 2 + 0.0, H / 2 + 0.06))
    a.add(scr, "Screen", keep_uv=True, smooth=True)
    # правая панель
    px = 0.56
    a.add(bm_box((0.26, 0.03, 0.80), loc=(px, -D / 2 - 0.01, H / 2 + 0.06), bevel=0.008), "Iron")
    for z in (0.78, 0.56):
        a.add(bm_cyl(0.075, 0.03, (px, -D / 2 - 0.035, z), (90, 0, 0), segs=20, bevel=0.006), "Steel")
        a.add(bm_cyl(0.05, 0.07, (px, -D / 2 - 0.07, z), (90, 0, 0), segs=16, r2=0.045, bevel=0.005), "Iron")
        a.add(bm_box((0.012, 0.012, 0.05), loc=(px, -D / 2 - 0.107, z + 0.02)), "Steel")
    for i in range(4):
        a.add(bm_cyl(0.014, 0.02, (px - 0.075 + i * 0.05, -D / 2 - 0.03, 0.43), (90, 0, 0), segs=8), "Steel")
    for i in range(7):
        a.add(bm_box((0.18, 0.02, 0.012), loc=(px, -D / 2 - 0.028, 0.37 - i * 0.026)), "Grille")
    a.add(bm_sphere(0.012, (px + 0.09, -D / 2 - 0.03, 0.43), segs=8, rings=6), "LampRed")
    # ножки и вентиляция сзади
    for x in (-0.6, 0.6):
        a.add(bm_cyl(0.035, 0.07, (x, -0.2, 0.035), segs=10, r2=0.03), "Iron")
        a.add(bm_cyl(0.035, 0.07, (x, 0.2, 0.035), segs=10, r2=0.03), "Iron")
    for i in range(5):
        a.add(bm_box((0.9, 0.012, 0.02), loc=(0, D / 2 + 0.002, 0.35 + i * 0.08)), "Grille")
    return a.finish()


def build_Sideboard(name):
    """Тумба под телевизор 1.9 × 0.62 × 0.6: дощатый корпус, столешница с напуском, 4 ящика (2 × 2) с железными
    ручками, железные уголки с заклёпками, цоколь. Origin — центр низа."""
    a = Asset(name)
    W, H, D = 1.9, 0.62, 0.6
    a.add(bm_box((W, D, H - 0.1), loc=(0, 0, 0.07 + (H - 0.1) / 2), bevel=0.01), "Wood", along='X')
    a.add(bm_box((W + 0.06, D + 0.05, 0.05), loc=(0, -0.01, H - 0.01), bevel=0.012), "WoodDark", along='X')
    a.add(bm_box((W - 0.06, D - 0.06, 0.07), loc=(0, 0, 0.035), bevel=0.005), "WoodDark", along='X')
    dw, dh = (W - 0.12) / 2, (H - 0.22) / 2
    for i in range(2):
        for j in range(2):
            x = -dw / 2 - 0.015 + i * (dw + 0.03)
            z = 0.12 + dh / 2 + j * (dh + 0.02)
            a.add(bm_box((dw - 0.02, 0.03, dh - 0.02), loc=(x, -D / 2 - 0.012, z), bevel=0.008), "Wood", along='X')
            a.add(bm_box((0.18, 0.025, 0.025), loc=(x, -D / 2 - 0.05, z), bevel=0.006), "Iron")
            for s in (-1, 1):
                a.add(bm_box((0.02, 0.03, 0.04), loc=(x + s * 0.09, -D / 2 - 0.035, z), bevel=0.004), "Iron")
    for sx in (-1, 1):
        for sz in (0.12, H - 0.07):
            x = sx * (W / 2 - 0.05)
            a.add(bm_box((0.11, 0.012, 0.11), loc=(x, -D / 2 - 0.006, sz), bevel=0.004), "Iron")
            rivets(a, [(x + sx * -0.03, -D / 2 - 0.013, sz + 0.03), (x + sx * 0.03, -D / 2 - 0.013, sz - 0.03)])
    return a.finish()


def build_Crate(name, W=0.72, H=0.5, D=0.6):
    """Ящик: обвязка из досок, крест-накрест на фасаде, железные уголки с заклёпками. Origin — центр низа."""
    a = Asset(name)
    a.add(bm_box((W - 0.04, D - 0.04, H - 0.04), loc=(0, 0, H / 2), bevel=0.004), "Wood", along='X')
    t = 0.07
    for sx in (-1, 1):                    # стойки
        for sy in (-1, 1):
            a.add(bm_box((t, t, H), loc=(sx * (W / 2 - t / 2), sy * (D / 2 - t / 2), H / 2), bevel=0.01), "WoodDark", along='Z')
    for sz in (t / 2, H - t / 2):         # обвязка фасада и зада
        for sy in (-1, 1):
            a.add(bm_box((W - 2 * t, 0.03, t), loc=(0, sy * (D / 2 - 0.01), sz), bevel=0.008), "WoodDark", along='X')
        for sx in (-1, 1):
            a.add(bm_box((0.03, D - 2 * t, t), loc=(sx * (W / 2 - 0.01), 0, sz), bevel=0.008), "WoodDark", along='Y')
    ang = math.degrees(math.atan2(H - 2 * t, W - 2 * t))
    L = math.hypot(W - 2 * t, H - 2 * t)
    for s in (1, -1):                     # крест на фасаде
        a.add(bm_box((L, 0.03, t * 0.8), loc=(0, -D / 2 - 0.004, H / 2), rot=(0, s * ang, 0), bevel=0.006), "WoodDark", along='X')
    a.add(bm_box((L, 0.03, t * 0.8), loc=(0, D / 2 + 0.004, H / 2), rot=(0, ang, 0), bevel=0.006), "WoodDark", along='X')
    for sx in (-1, 1):                    # уголки: наружные грани на 6 мм за стойками, низ на полу
        for sz in (0, H):
            for sy in (-1, 1):
                x, y, z = sx * (W / 2 - 0.039), sy * (D / 2 - 0.039), (0.045 if sz == 0 else H - 0.045)
                a.add(bm_box((0.09, 0.09, 0.09), loc=(x, y, z), bevel=0.008), "Iron")
                rivets(a, [(x - sx * 0.02, y + sy * 0.046, z)], axis='Y' if sy < 0 else '-Y')
    return a.finish()


def build_Crate_Small(name):
    return build_Crate(name, 0.5, 0.4, 0.45)


def build_Mug(name):
    """Кружка: керамика, кофе внутри, ручка-полутор. Origin — центр дна."""
    a = Asset(name)
    prof = [(0.0, 0.0), (0.04, 0.0), (0.045, 0.006), (0.046, 0.1), (0.041, 0.1), (0.04, 0.012), (0.0, 0.012)]
    a.add(bm_lathe(prof, 20), "Ceramic", smooth=True)
    a.add(bm_cyl(0.041, 0.004, (0, 0, 0.082), segs=20), "Coffee")
    a.add(bm_torus(0.028, 0.008, (0.05, 0, 0.055), rot=(90, 0, 0), segs=12, rsegs=6, arc=0.55), "Ceramic", smooth=True)
    return a.finish()


# ----------------------------------------------------------------------------------------------------------------------
# дополнительные помощники
# ----------------------------------------------------------------------------------------------------------------------
def bm_quad(center, size, rot=(0, 0, 0), uvrect=(0, 0, 1, 1)):
    """Квад size=(w, h) в плоскости XZ лицом в −Y; UV — прямоугольник uvrect (u0, v0, u1, v1)."""
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    w, h = size
    vs = [bm.verts.new(p) for p in ((-w / 2, 0, -h / 2), (w / 2, 0, -h / 2), (w / 2, 0, h / 2), (-w / 2, 0, h / 2))]
    f = bm.faces.new(vs)
    u0, v0, u1, v1 = uvrect
    for lp, t in zip(f.loops, ((u0, v0), (u1, v0), (u1, v1), (u0, v1))):
        lp[uv].uv = t
    if f.normal.y > 0:
        f.normal_flip()
    _xform(bm, center, rot)
    return bm


def bm_wedge(w, d, h0, h1, loc=(0, 0, 0)):
    """Клин (рампа): ширина w по X, длина d по Y, высота h0 у −Y и h1 у +Y; низ на z=0."""
    bm = bmesh.new()
    pts = [(-d / 2, 0), (d / 2, 0), (d / 2, h1), (-d / 2, h0)]
    vs0 = [bm.verts.new((-w / 2, y, z)) for y, z in pts]
    vs1 = [bm.verts.new((w / 2, y, z)) for y, z in pts]
    bm.faces.new(vs0)
    bm.faces.new(list(reversed(vs1)))
    for k in range(4):
        m = (k + 1) % 4
        bm.faces.new((vs0[k], vs1[k], vs1[m], vs0[m]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    _xform(bm, loc)
    return bm


def text_obj(a, body, size, loc, role, depth=0.01, rot=(90, 0, 0)):
    """Объёмный текст (например «?») как деталь предмета: лицо в −Y."""
    bpy.ops.object.text_add(location=(0, 0, 0))
    t = bpy.context.active_object
    t.data.body = body
    t.data.size = size
    t.data.extrude = depth
    t.data.align_x = 'CENTER'
    t.data.align_y = 'CENTER'
    bpy.ops.object.convert(target='MESH')
    o = bpy.context.active_object
    o.rotation_euler = [math.radians(v) for v in rot]
    o.location = loc
    C.apply_transforms(o, location=True, rotation=True, scale=True)
    o.data.materials.clear()
    o.data.materials.append(mat(role))
    _uv_box(o.data, 'Z')
    a.parts.append(o)
    return o


def chain(a, top, length, link=0.05, r=0.008, role="Iron"):
    """Цепь вниз от точки top: овальные звенья через одно повёрнуты на 90°."""
    n = max(2, int(length / (link * 0.8)))
    for i in range(n):
        z = top[2] - link * 0.5 - i * link * 0.8
        bm = bm_torus(link * 0.35, r, (0, 0, 0), (90, 0, 0), segs=10, rsegs=5)
        bmesh.ops.scale(bm, vec=(1.0, 1.0, 1.6), verts=bm.verts)
        _xform(bm, (top[0], top[1], z), (0, 0, 90 if i % 2 else 0))
        a.add(bm, role)


# ----------------------------------------------------------------------------------------------------------------------
# лифт на арену (БЫСТРЫЙ БОЙ)
# ----------------------------------------------------------------------------------------------------------------------
def build_Gate(name):
    """Ворота лифта: рулонная штора из ламелей в стальной раме с полосами опасности, сквозь щели и из-под шторы светит
    поле NULL (роль NullGlow за ламелями), иллюминатор, короб вала сверху, рампа из рифлёного листа перед воротами.
    Проём 2.4 × 2.55 (верх короба ≈ 3.3 — под потолок 3.4). Origin — центр низа в плоскости стены (y=0), фронт −Y,
    рампа уходит в −Y на 0.95."""
    a = Asset(name)
    W, H = 2.4, 2.55
    a.add(bm_box((W + 0.1, 0.02, H + 0.1), loc=(0, 0.16, H / 2)), "NullGlow")
    nsl = 19
    z0 = 0.16
    step = (H - z0) / nsl
    for i in range(nsl):
        a.add(bm_box((W - 0.04, 0.04, step - 0.007), loc=(0, 0.06, z0 + step * (i + 0.5)), bevel=0.012), "PaintGrey", along='X')
    a.add(bm_box((W - 0.04, 0.07, 0.1), loc=(0, 0.06, z0 + 0.02), bevel=0.012), "Iron", along='X')
    for sx in (-1, 1):
        a.add(bm_box((0.06, 0.04, 0.12), loc=(sx * 0.45, 0.02, z0 + 0.02), bevel=0.01), "Iron")
    # иллюминатор
    px, pz = -0.5, 1.65
    a.add(bm_cyl(0.28, 0.05, (px, 0.02, pz), (90, 0, 0), segs=24, bevel=0.01), "Iron")
    a.add(bm_torus(0.21, 0.035, (px, -0.01, pz), (90, 0, 0), segs=24, rsegs=8), "Steel", smooth=True)
    a.add(bm_cyl(0.19, 0.03, (px, -0.0, pz), (90, 0, 0), segs=24), "NullGlow")
    rivets(a, [(px + 0.245 * math.cos(t), -0.006, pz + 0.245 * math.sin(t)) for t in [k * math.pi / 4 for k in range(8)]], 0.01)
    # рама с полосами опасности
    for sx in (-1, 1):
        x = sx * (W / 2 + 0.13)
        a.add(bm_box((0.26, 0.3, H + 0.4), loc=(x, 0.05, (H + 0.4) / 2), bevel=0.015), "Iron", along='Z')
        a.add(bm_box((0.22, 0.012, H + 0.32), loc=(x, -0.106, (H + 0.32) / 2 + 0.02)), "Hazard")
        a.add(bm_box((0.05, 0.1, H), loc=(sx * (W / 2 - 0.02), 0.06, H / 2)), "Iron")
        rivets(a, [(x + dx, -0.113, z) for z in (0.2, 0.95, 1.7, 2.45) for dx in (-0.08, 0.08)], 0.011)
    a.add(bm_box((W + 0.52, 0.36, 0.42), loc=(0, 0.08, H + 0.4), bevel=0.02), "Iron", along='X')
    a.add(bm_box((W + 0.44, 0.012, 0.3), loc=(0, -0.106, H + 0.4)), "Hazard")
    a.add(bm_cyl(0.05, W + 0.7, (0, -0.02, H + 0.66), (0, 90, 0), segs=12), "Steel")
    # полоса света у пола и рампа
    a.add(bm_box((W - 0.1, 0.04, 0.03), loc=(0, 0.04, 0.03)), "NullGlow")
    ramp = bm_wedge(W + 0.3, 0.95, 0.01, 0.13, loc=(0, -0.5, 0))
    a.add(ramp, "Tread", along='Y')
    a.add(bm_box((W + 0.3, 0.06, 0.012), loc=(0, -0.95, 0.012)), "Hazard")
    for sx in (-1, 1):
        a.add(bm_box((0.06, 0.95, 0.04), loc=(sx * (W / 2 + 0.18), -0.5, 0.06), bevel=0.01), "Iron", along='Y')
    return a.finish()


def build_ControlBox(name):
    """Пульт лифта на стене: короб с дверцей, красная лампа-колпак, два тумблера, рычаг, кабель-канал вверх.
    Origin — низ задней плоскости (у стены), предмет выступает в −Y."""
    a = Asset(name)
    w, h, d = 0.34, 0.5, 0.16
    a.add(bm_box((w, d, h), loc=(0, -d / 2, h / 2), bevel=0.015), "PaintGrey")
    a.add(bm_box((w - 0.06, 0.012, h - 0.12), loc=(0, -d - 0.005, h / 2 - 0.03), bevel=0.006), "PaintGrey")
    a.add(bm_cyl(0.065, 0.03, (0, -d - 0.02, h - 0.07), (90, 0, 0), segs=16), "Iron")
    a.add(bm_lathe([(0.05, 0), (0.05, 0.02), (0.035, 0.05), (0.0, 0.06)], 16, loc=(0, -d - 0.035, h - 0.07), rot=(90, 0, 0)), "LampRed", smooth=True)
    for i, x in enumerate((-0.08, 0.0)):
        a.add(bm_box((0.04, 0.02, 0.05), loc=(x, -d - 0.015, 0.2)), "Iron")
        a.add(bm_cyl(0.008, 0.05, (x, -d - 0.04, 0.21), (70 if i else 110, 0, 0), segs=6), "Steel")
    a.add(bm_box((0.04, 0.03, 0.12), loc=(0.1, -d - 0.02, 0.17)), "Iron")
    a.add(bm_cyl(0.014, 0.12, (0.1, -d - 0.07, 0.24), (60, 0, 0), segs=8), "Steel")
    a.add(bm_sphere(0.022, (0.1, -d - 0.12, 0.275), segs=8, rings=6), "PaintRed")
    a.add(bm_box((0.06, 0.05, 1.4), loc=(-0.1, -0.025, h + 0.7)), "Iron", along='Z')
    rivets(a, [(sx * (w / 2 - 0.025), -d - 0.002, z) for sx in (-1, 1) for z in (0.03, h - 0.03)], 0.009)
    return a.finish()


# ----------------------------------------------------------------------------------------------------------------------
# верстак, перфопанель, табурет, лампа (МАСТЕРСКАЯ)
# ----------------------------------------------------------------------------------------------------------------------
def build_Workbench(name):
    """Верстак 2.4 × 0.92 × 0.7: столешница из трёх плах с железной кромкой, две тумбы с ящиками (крашеный металл),
    нижняя полка, тиски на левом углу, на столе банки и ящичек. Origin — центр низа, фронт −Y (к комнате)."""
    a = Asset(name)
    W, H, D = 2.4, 0.92, 0.7
    for i in range(3):
        a.add(bm_box((W, D / 3 - 0.006, 0.07), loc=(0, -D / 2 + D / 6 + i * D / 3, H - 0.035), bevel=0.01), "Wood", along='X')
    a.add(bm_box((W + 0.01, 0.012, 0.075), loc=(0, -D / 2 - 0.006, H - 0.037)), "Iron", along='X')
    for sx in (-1, 1):
        cx = sx * 0.85
        a.add(bm_box((0.62, D - 0.06, H - 0.1), loc=(cx, 0, (H - 0.1) / 2 + 0.02), bevel=0.012), "PaintNavy")
        for k in range(4):
            z = 0.12 + k * 0.19
            a.add(bm_box((0.56, 0.02, 0.17), loc=(cx, -D / 2 + 0.02, z + 0.085), bevel=0.008), "PaintNavy")
            a.add(bm_box((0.16, 0.025, 0.02), loc=(cx, -D / 2 - 0.0, z + 0.13), bevel=0.005), "Steel")
        rivets(a, [(cx + dx, -D / 2 + 0.03 - 0.012, z) for dx in (-0.29, 0.29) for z in (0.05, H - 0.12)], 0.009)
        a.add(bm_box((0.64, D - 0.04, 0.03), loc=(cx, 0, 0.015)), "Iron")
    a.add(bm_box((1.06, D - 0.1, 0.035), loc=(0, 0, 0.2), bevel=0.006), "WoodDark", along='X')
    a.add(bm_box((1.06, 0.03, 0.12), loc=(0, D / 2 - 0.05, H - 0.13)), "WoodDark", along='X')
    # тиски
    vx = -W / 2 + 0.25
    a.add(bm_box((0.14, 0.2, 0.1), loc=(vx, -D / 2 + 0.06, H + 0.05), bevel=0.012), "PaintGreen")
    a.add(bm_box((0.16, 0.05, 0.12), loc=(vx, -D / 2 - 0.06, H + 0.06), bevel=0.01), "PaintGreen")
    a.add(bm_cyl(0.015, 0.3, (vx, -D / 2 - 0.12, H + 0.05), (90, 0, 0), segs=8), "Steel")
    a.add(bm_cyl(0.01, 0.24, (vx, -D / 2 - 0.25, H + 0.05), (0, 90, 0), segs=6), "Steel")
    # банки, ящичек, молоток на столе
    for i, (x, r, hh, role) in enumerate([(0.1, 0.06, 0.12, "PaintRed"), (0.25, 0.05, 0.1, "PaintOlive"), (0.38, 0.045, 0.14, "PaintCream")]):
        a.add(bm_cyl(r, hh, (x, 0.12, H + hh / 2), segs=14, bevel=0.004), role)
        a.add(bm_cyl(r * 0.95, 0.01, (x, 0.12, H + hh + 0.005), segs=14), "Steel")
    a.add(bm_box((0.36, 0.2, 0.14), loc=(0.75, 0.1, H + 0.07), bevel=0.01), "PaintRed")
    a.add(bm_box((0.2, 0.04, 0.03), loc=(0.75, 0.1, H + 0.16)), "Iron")
    a.add(bm_cyl(0.014, 0.3, (-0.4, -0.12, H + 0.015), (0, 90, 15), segs=8), "Wood")
    a.add(bm_box((0.04, 0.1, 0.035), loc=(-0.26, -0.08, H + 0.02), rot=(0, 0, 15), bevel=0.005), "Iron")
    return a.finish()


def _wrench(a, x, z, L, role="Steel"):
    a.add(bm_box((0.022, 0.012, L), loc=(x, -0.03, z - L / 2), bevel=0.004), role)
    a.add(bm_torus(0.022, 0.009, (x, -0.03, z - L - 0.01), (90, 0, 0), segs=10, rsegs=4, arc=0.75), role)
    a.add(bm_torus(0.018, 0.008, (x, -0.03, z + 0.01), (90, 0, 0), segs=10, rsegs=4), role)


def build_Pegboard(name):
    """Перфопанель 2.2 × 0.95 на стене: тёмные доски в железной рамке, гвозди-крючки, ключи, молотки, отвёртки,
    клещи; снизу полочка с банками. Origin — низ задней плоскости, панель выступает в −Y."""
    a = Asset(name)
    W, H = 2.2, 0.95
    a.add(bm_box((W, 0.025, H), loc=(0, -0.0125, H / 2), bevel=0.005), "WoodDark", along='Z')
    for sx in (-1, 1):
        a.add(bm_box((0.04, 0.035, H + 0.04), loc=(sx * (W / 2 + 0.02), -0.018, H / 2)), "Iron")
    for sz in (0, H):
        a.add(bm_box((W + 0.08, 0.035, 0.04), loc=(0, -0.018, sz)), "Iron", along='X')
    x = -W / 2 + 0.16
    rng = random.Random(3)
    kinds = ["wrench", "wrench", "hammer", "screw", "wrench", "pliers", "screw", "screw", "wrench", "hammer", "wrench", "screw", "wrench", "pliers", "wrench"]
    for k in kinds:
        top = H - 0.18 - rng.random() * 0.06
        a.add(bm_cyl(0.005, 0.04, (x, -0.04, top + 0.03), (90, 0, 0), segs=5), "Steel")
        if k == "wrench":
            _wrench(a, x, top, 0.18 + rng.random() * 0.14)
            x += 0.11
        elif k == "hammer":
            a.add(bm_cyl(0.014, 0.32, (x, -0.035, top - 0.16), segs=8), "Wood")
            a.add(bm_box((0.14, 0.035, 0.04), loc=(x, -0.035, top - 0.32), bevel=0.006), "Iron")
            x += 0.16
        elif k == "screw":
            col = rng.choice(["PaintRed", "PaintOlive", "PaintCream"])
            a.add(bm_cyl(0.017, 0.1, (x, -0.035, top - 0.05), segs=8, bevel=0.004), col)
            a.add(bm_cyl(0.005, 0.14, (x, -0.035, top - 0.17), segs=6), "Steel")
            x += 0.08
        else:
            for s in (-1, 1):
                a.add(bm_box((0.016, 0.012, 0.2), loc=(x + s * 0.012, -0.035, top - 0.1), rot=(0, s * 6, 0), bevel=0.004), "PaintRed")
            a.add(bm_box((0.03, 0.014, 0.06), loc=(x, -0.035, top - 0.22)), "Steel")
            x += 0.1
    # полочка с банками
    a.add(bm_box((1.2, 0.14, 0.025), loc=(0.3, -0.07, 0.12)), "Wood", along='X')
    for i in range(6):
        a.add(bm_cyl(0.035, 0.08, (-0.18 + i * 0.17, -0.07, 0.172), segs=10), ["Glass", "PaintRed", "PaintNavy", "Glass", "PaintOlive", "PaintCream"][i])
    return a.finish()


def build_Stool(name):
    """Табурет 0.62: круглое сиденье, три расставленные ножки, железное кольцо-проножка. Origin — центр низа."""
    a = Asset(name)
    a.add(bm_cyl(0.19, 0.05, (0, 0, 0.6), segs=24, bevel=0.012), "Wood", along='X')
    for k in range(3):
        t = 2 * math.pi * k / 3
        top = Vector((math.cos(t) * 0.11, math.sin(t) * 0.11, 0.58))
        bot = Vector((math.cos(t) * 0.2, math.sin(t) * 0.2, 0.0))
        d = top - bot
        bm = bm_cyl(0.022, d.length, segs=8, r2=0.018)
        q = Vector((0, 0, 1)).rotation_difference(d.normalized())
        bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=q.to_matrix(), verts=bm.verts)
        _xform(bm, (top + bot) * 0.5)
        a.add(bm, "WoodDark")
    a.add(bm_torus(0.16, 0.01, (0, 0, 0.22), segs=18, rsegs=5), "Iron")
    return a.finish()


def build_Lamp(name, length=1.1):
    """Подвесная лампа: цепь length вниз от точки подвеса, патрон, эмалированный абажур ⌀0.52 (снаружи зелёный, внутри
    белый), лампочка. Origin — точка подвеса (верх цепи), всё висит в −Z; низ абажура на z = −length − 0.28."""
    a = Asset(name)
    a.add(bm_cyl(0.05, 0.02, (0, 0, -0.01), segs=12), "Iron")
    chain(a, (0, 0, -0.02), length - 0.02)
    z = -length
    a.add(bm_cyl(0.035, 0.09, (0, 0, z - 0.03), segs=12), "Iron")
    outer = [(0.26, z - 0.27), (0.25, z - 0.255), (0.2, z - 0.16), (0.1, z - 0.07), (0.045, z - 0.06)]
    inner = [(0.245, z - 0.262), (0.19, z - 0.17), (0.095, z - 0.085), (0.04, z - 0.075)]
    a.add(bm_lathe(outer, 28, cap_bottom=False), "PaintGreen", smooth=True)
    bm = bm_lathe(inner, 28, cap_bottom=False)
    for f in bm.faces:
        f.normal_flip()
    a.add(bm, "Enamel", smooth=True)
    a.add(bm_torus(0.255, 0.008, (0, 0, z - 0.268), segs=28, rsegs=5), "PaintGreen")
    a.add(bm_sphere(0.05, (0, 0, z - 0.15), segs=12, rings=8, scale=(1, 1, 1.2)), "Bulb", smooth=True)
    return a.finish()


# ----------------------------------------------------------------------------------------------------------------------
# полки, трофеи, магнитола, шлем, книги, растение (ТРОФЕИ)
# ----------------------------------------------------------------------------------------------------------------------
def build_Shelf_Wall(name, W=2.6):
    """Настенная полка: доска W × 0.32 на трёх железных кронштейнах с заклёпками. Origin — задняя кромка ВЕРХНЕЙ
    плоскости доски (z=0 — где стоят вещи), полка уходит в −Y."""
    a = Asset(name)
    a.add(bm_box((W, 0.32, 0.05), loc=(0, -0.16, -0.025), bevel=0.01), "Wood", along='X')
    a.add(bm_box((W, 0.015, 0.05), loc=(0, -0.325, -0.025)), "WoodDark", along='X')
    for x in (-W / 2 + 0.2, 0, W / 2 - 0.2):
        a.add(bm_box((0.04, 0.03, 0.3), loc=(x, -0.015, -0.2)), "Iron")
        a.add(bm_box((0.04, 0.28, 0.03), loc=(x, -0.15, -0.065)), "Iron", along='Y')
        bm = bm_box((0.035, 0.34, 0.025), loc=(0, 0, 0))
        _xform(bm, (x, -0.13, -0.17), (45, 0, 0))
        a.add(bm, "Iron", along='Y')
        rivets(a, [(x, -0.032, -0.08), (x, -0.032, -0.3)], 0.009)
    return a.finish()


def build_Shelf_Short(name):
    return build_Shelf_Wall(name, 1.3)


def _cup(a, s=1.0):
    prof = [(0.07, 0.0), (0.07, 0.03), (0.05, 0.035), (0.022, 0.06), (0.018, 0.12), (0.03, 0.15), (0.075, 0.2), (0.105, 0.27),
            (0.11, 0.3), (0.1, 0.3), (0.09, 0.27), (0.0, 0.2)]
    prof = [(r * s, z * s + 0.05 * s) for r, z in prof]
    a.add(bm_lathe(prof, 28, cap_bottom=True), "Bronze", smooth=True)
    for sx in (-1, 1):
        a.add(bm_torus(0.055 * s, 0.01 * s, (sx * 0.11 * s, 0, 0.27 * s), (90, 0, 0), segs=14, rsegs=6, arc=0.6), "Bronze", smooth=True)
    a.add(bm_box((0.16 * s, 0.16 * s, 0.05 * s), loc=(0, 0, 0.025 * s), bevel=0.006), "WoodDark")
    a.add(bm_box((0.1 * s, 0.006, 0.025 * s), loc=(0, -0.081 * s, 0.025 * s)), "Brass")


def build_Cup_A(name):
    """Большой кубок 0.4 с ручками на деревянном цоколе. Origin — центр низа."""
    a = Asset(name)
    _cup(a, 1.15)
    return a.finish()


def build_Cup_B(name):
    a = Asset(name)
    _cup(a, 0.85)
    return a.finish()


def build_Boombox(name):
    """Магнитола 0.52 × 0.3 × 0.15: два динамика, кассетник, кнопки, ручка, антенна. Origin — центр низа."""
    a = Asset(name)
    W, H, D = 0.52, 0.26, 0.15
    a.add(bm_box((W, D, H), loc=(0, 0, H / 2), bevel=0.02, seg=2), "PaintGrey")
    for sx in (-1, 1):
        a.add(bm_cyl(0.085, 0.02, (sx * 0.16, -D / 2 - 0.005, 0.12), (90, 0, 0), segs=20), "Iron")
        a.add(bm_cyl(0.07, 0.022, (sx * 0.16, -D / 2 - 0.008, 0.12), (90, 0, 0), segs=20), "Grille")
        a.add(bm_cyl(0.025, 0.026, (sx * 0.16, -D / 2 - 0.01, 0.12), (90, 0, 0), segs=12), "Iron")
    a.add(bm_box((0.12, 0.012, 0.08), loc=(0, -D / 2 - 0.004, 0.12)), "Glass")
    for i in range(5):
        a.add(bm_box((0.018, 0.02, 0.012), loc=(-0.05 + i * 0.025, -0.02, H + 0.004)), "Steel")
    a.add(bm_box((0.22, 0.012, 0.025), loc=(0, -D / 2 - 0.004, 0.225)), "LampAmber")
    for sx in (-1, 1):
        a.add(bm_box((0.025, 0.025, 0.07), loc=(sx * 0.17, 0, H + 0.035)), "Iron")
    a.add(bm_cyl(0.014, 0.38, (0, 0, H + 0.075), (0, 90, 0), segs=8), "Steel")
    a.add(bm_cyl(0.004, 0.4, (0.22, 0.03, H + 0.18), (0, -25, 0), segs=5), "Steel")
    return a.finish()


def build_Helmet(name):
    """Шлем бойца лиги: белая каска, тёмный визор, ремешок. Origin — центр низа (лежит на полке)."""
    a = Asset(name)
    prof = [(0.15 * math.cos(t), 0.17 * math.sin(t) + 0.02) for t in [k * math.pi / 2 / 9 for k in range(10)]]
    prof[-1] = (0.0, prof[-1][1])
    a.add(bm_lathe(prof, 28, cap_bottom=False), "PaintCream", smooth=True)
    a.add(bm_torus(0.15, 0.012, (0, 0, 0.02), segs=28, rsegs=6), "Rubber")
    a.add(bm_sphere(0.13, (0, -0.06, 0.08), segs=20, rings=10, scale=(1.0, 0.75, 0.5)), "Grille", smooth=True)
    a.add(bm_box((0.04, 0.3, 0.02), loc=(0, -0.0, 0.18), bevel=0.008), "PaintRed")
    return a.finish()


def build_Books(name):
    """Стопка книг и журналов: 4 штуки со смещением. Origin — центр низа."""
    a = Asset(name)
    z = 0.0
    for i, (w, d, h, role, rz) in enumerate([(0.3, 0.22, 0.05, "PaintRed", 4), (0.28, 0.2, 0.04, "PaintNavy", -6),
                                             (0.26, 0.19, 0.06, "PaintOlive", 9), (0.22, 0.16, 0.035, "PaintCream", -3)]):
        a.add(bm_box((w, d, h), loc=(0.01 * i, 0, z + h / 2), rot=(0, 0, rz), bevel=0.004), role)
        a.add(bm_box((w - 0.01, d + 0.004, h - 0.012), loc=(0.01 * i + 0.006, 0.0, z + h / 2), rot=(0, 0, rz)), "Paper")
        z += h
    return a.finish()


def build_Plant(name):
    """Плющ в горшке: горшок, ком листьев сверху и 5 свисающих плетей из квадов с альфой (роль Leaves, UV в leaves.png).
    Origin — центр низа горшка; плети свисают ниже (для края полки)."""
    a = Asset(name)
    a.add(bm_lathe([(0.0, 0.0), (0.07, 0.0), (0.095, 0.15), (0.105, 0.16), (0.1, 0.175), (0.0, 0.17)], 18), "Pot", smooth=True)
    rng = random.Random(11)
    for k in range(7):
        c = (rng.uniform(-0.06, 0.06), rng.uniform(-0.06, 0.06), 0.2 + rng.uniform(0, 0.08))
        u = rng.choice([0.0, 0.5])
        v = rng.choice([0.0, 0.5])
        a.add(bm_quad(c, (0.24, 0.24), (rng.uniform(-30, 30), 0, k * 52), (u, v, u + 0.5, v + 0.5)), "Leaves", keep_uv=True)
    for s in range(5):
        ang = rng.uniform(0, 2 * math.pi)
        x, y, z = math.cos(ang) * 0.09, math.sin(ang) * 0.09, 0.17
        out = Vector((math.cos(ang), math.sin(ang), 0))
        for i in range(rng.randint(4, 8)):
            x += out.x * 0.035 + rng.uniform(-0.02, 0.02)
            y += out.y * 0.035 + rng.uniform(-0.02, 0.02)
            z -= 0.08
            u = rng.choice([0.0, 0.5])
            v = rng.choice([0.0, 0.5])
            a.add(bm_quad((x, y, z), (0.16, 0.16), (rng.uniform(-40, 40), 0, rng.uniform(0, 360)), (u, v, u + 0.5, v + 0.5)), "Leaves", keep_uv=True)
    return a.finish()


# ----------------------------------------------------------------------------------------------------------------------
# хранение: шкафчики, тумба, кейсы, ящик инструментов, стеллаж, «?»
# ----------------------------------------------------------------------------------------------------------------------
def build_Lockers(name):
    """Два шкафчика 1.0 × 1.85 × 0.5 (крашеный металл): двери с жалюзи, ручки, таблички, цоколь. Origin — центр низа."""
    a = Asset(name)
    for i, sx in enumerate((-0.25, 0.25)):
        a.add(bm_box((0.49, 0.5, 1.8), loc=(sx, 0, 0.95), bevel=0.012), "PaintNavy")
        a.add(bm_box((0.43, 0.02, 1.62), loc=(sx, -0.255, 0.98), bevel=0.008), "PaintNavy")
        for k in range(6):
            a.add(bm_box((0.26, 0.012, 0.014), loc=(sx, -0.268, 1.62 - k * 0.035)), "Grille")
            a.add(bm_box((0.26, 0.012, 0.014), loc=(sx, -0.268, 0.42 - k * 0.035)), "Grille")
        a.add(bm_box((0.03, 0.03, 0.14), loc=(sx + 0.16, -0.28, 1.05), bevel=0.006), "Steel")
        a.add(bm_box((0.1, 0.006, 0.05), loc=(sx, -0.267, 1.32)), "PaintCream")
    a.add(bm_box((1.0, 0.48, 0.05), loc=(0, 0, 0.025)), "Iron")
    return a.finish()


def build_Cabinet(name):
    """Тумба с пятью ящиками 0.6 × 0.9 × 0.5 (крашеный металл). Origin — центр низа."""
    a = Asset(name)
    a.add(bm_box((0.6, 0.5, 0.86), loc=(0, 0, 0.45), bevel=0.012), "PaintNavy")
    for k in range(5):
        z = 0.1 + k * 0.16
        a.add(bm_box((0.54, 0.02, 0.145), loc=(0, -0.255, z + 0.07), bevel=0.006), "PaintNavy")
        a.add(bm_box((0.14, 0.02, 0.018), loc=(0, -0.272, z + 0.11), bevel=0.004), "Steel")
    a.add(bm_box((0.6, 0.46, 0.04), loc=(0, 0, 0.02)), "Iron")
    rivets(a, [(sx * 0.28, -0.258, z) for sx in (-1, 1) for z in (0.06, 0.84)], 0.009)
    return a.finish()


def _case(a, w, d, h, role):
    a.add(bm_box((w, d, h), loc=(0, 0, h / 2), bevel=0.025, seg=2), role)
    a.add(bm_box((w + 0.012, d + 0.012, 0.035), loc=(0, 0, h * 0.7), bevel=0.008), "Iron")
    for sx in (-1, 1):
        a.add(bm_box((0.05, 0.02, 0.07), loc=(sx * w * 0.3, -d / 2 - 0.008, h * 0.7), bevel=0.006), "Steel")
    for sx in (-1, 1):
        a.add(bm_box((0.03, 0.03, 0.05), loc=(sx * 0.09, 0, h + 0.02)), "Iron")
    a.add(bm_box((0.2, 0.03, 0.025), loc=(0, 0, h + 0.05), bevel=0.008), "Rubber")


def build_Case_Olive(name):
    """Кейс-ящик оливковый 0.5 × 0.42 × 0.36 (защёлки, ручка). Origin — центр низа."""
    a = Asset(name)
    _case(a, 0.5, 0.36, 0.42, "PaintOlive")
    return a.finish()


def build_Case_Navy(name):
    a = Asset(name)
    _case(a, 0.62, 0.42, 0.32, "PaintNavy")
    return a.finish()


def build_Toolbox(name):
    """Красный ящик инструментов 0.56 × 0.26 × 0.24: крышка-трапеция, ручка, защёлки. Origin — центр низа."""
    a = Asset(name)
    a.add(bm_box((0.56, 0.24, 0.17), loc=(0, 0, 0.085), bevel=0.012), "PaintRed")
    lid = bm_wedge(0.56, 0.24, 0.07, 0.07, loc=(0, 0, 0.17))
    a.add(lid, "PaintRed")
    a.add(bm_box((0.5, 0.12, 0.025), loc=(0, 0, 0.255), bevel=0.006), "PaintRed")
    for sx in (-1, 1):
        a.add(bm_box((0.03, 0.03, 0.06), loc=(sx * 0.12, 0, 0.29)), "Iron")
        a.add(bm_box((0.05, 0.015, 0.05), loc=(sx * 0.2, -0.125, 0.17), bevel=0.004), "Steel")
    a.add(bm_cyl(0.015, 0.28, (0, 0, 0.32), (0, 90, 0), segs=8), "Rubber")
    return a.finish()


def build_Storage(name):
    """Стеллаж 1.6 × 1.9 × 0.45: железные уголки, 4 деревянные полки, раскосы сзади. Origin — центр низа."""
    a = Asset(name)
    W, H, D = 1.6, 1.9, 0.45
    for sx in (-1, 1):
        for sy in (-1, 1):
            a.add(bm_box((0.045, 0.045, H), loc=(sx * (W / 2 - 0.022), sy * (D / 2 - 0.022), H / 2)), "Iron", along='Z')
    for z in (0.12, 0.62, 1.12, 1.62):
        a.add(bm_box((W - 0.02, D - 0.02, 0.035), loc=(0, 0, z), bevel=0.006), "Wood", along='X')
        for sy in (-1, 1):
            a.add(bm_box((W, 0.03, 0.05), loc=(0, sy * (D / 2 - 0.015), z - 0.035)), "Iron", along='X')
    L = math.hypot(W - 0.1, 0.5)
    for k in range(3):
        bm = bm_box((L, 0.012, 0.03))
        _xform(bm, (0, D / 2 - 0.01, 0.37 + k * 0.5), (0, math.degrees(math.atan2(0.5, W - 0.1)) * (1 if k % 2 else -1), 0))
        a.add(bm, "Iron", along='X')
    return a.finish()


def build_QBox(name):
    """Ящик «?» 0.36 — место для следующего трофея. Origin — центр низа."""
    a = Asset(name)
    s = 0.36
    a.add(bm_box((s, s, s), loc=(0, 0, s / 2), bevel=0.012), "Wood", along='X')
    for sx in (-1, 1):
        for sz in (0.025, s - 0.025):
            a.add(bm_box((0.05, s + 0.01, 0.05), loc=(sx * (s / 2 - 0.02), 0, sz), bevel=0.006), "WoodDark", along='Y')
    text_obj(a, "?", 0.26, (0, -s / 2 - 0.008, s / 2), "PaintCream", depth=0.008)
    return a.finish()


# ----------------------------------------------------------------------------------------------------------------------
# радио и щиток (НАСТРОЙКИ / ВЫХОД)
# ----------------------------------------------------------------------------------------------------------------------
def build_Radio(name):
    """Ламповый радиоприёмник 0.5 × 0.34 × 0.24: кремовый корпус с аркой сверху, тканевая решётка, янтарная шкала,
    две ручки. Origin — центр низа."""
    a = Asset(name)
    pts = [(-0.25, 0.0), (0.25, 0.0), (0.25, 0.22)]
    for k in range(1, 12):
        t = math.pi * k / 12
        pts.append((0.25 * math.cos(t), 0.22 + 0.12 * math.sin(t)))
    pts.append((-0.25, 0.22))
    a.add(bm_prism(pts, 0.24, loc=(0, 0, 0), bevel=0.01), "PaintCream", along='X')
    a.add(bm_box((0.3, 0.012, 0.16), loc=(-0.06, -0.125, 0.2)), "Grille")
    a.add(bm_box((0.2, 0.012, 0.05), loc=(0.0, -0.125, 0.06)), "LampAmber")
    for sx in (0.15, 0.2):
        a.add(bm_cyl(0.025, 0.03, (sx, -0.13, 0.2 - (sx - 0.15) * 2.0), (90, 0, 0), segs=12), "PaintRed")
    a.add(bm_box((0.5, 0.24, 0.02), loc=(0, 0, 0.01)), "WoodDark", along='X')
    return a.finish()


def build_Breaker(name):
    """Щиток с рубильником 0.46 × 0.62 × 0.14: рычаг-нож с красной ручкой, три лампы (зелёная, янтарная, красная),
    кабель вверх. Origin — низ задней плоскости, щиток выступает в −Y."""
    a = Asset(name)
    w, h, d = 0.46, 0.62, 0.14
    a.add(bm_box((w, d, h), loc=(0, -d / 2, h / 2), bevel=0.015), "PaintGrey")
    a.add(bm_box((w - 0.06, 0.012, h - 0.08), loc=(0, -d - 0.004, h / 2), bevel=0.006), "PaintGrey")
    a.add(bm_box((0.12, 0.04, 0.22), loc=(0.09, -d - 0.02, 0.3), bevel=0.008), "Iron")
    bm = bm_box((0.03, 0.03, 0.26), bevel=0.004)
    _xform(bm, (0.09, -d - 0.1, 0.4), (-40, 0, 0))
    a.add(bm, "Steel")
    a.add(bm_box((0.12, 0.04, 0.04), loc=(0.09, -d - 0.19, 0.5), bevel=0.012), "PaintRed")
    for i, role in enumerate(("LampGreen", "LampAmber", "LampRed")):
        a.add(bm_cyl(0.022, 0.02, (-0.12, -d - 0.012, 0.48 - i * 0.09), (90, 0, 0), segs=10), "Iron")
        a.add(bm_sphere(0.018, (-0.12, -d - 0.025, 0.48 - i * 0.09), segs=10, rings=6), role)
    a.add(bm_cyl(0.025, 1.2, (-0.15, -0.03, h + 0.6), segs=8), "Rubber")
    rivets(a, [(sx * (w / 2 - 0.02), -d - 0.002, z) for sx in (-1, 1) for z in (0.025, h - 0.025)], 0.009)
    return a.finish()


# ----------------------------------------------------------------------------------------------------------------------
# флаг, трубы, мелочь
# ----------------------------------------------------------------------------------------------------------------------
def build_Banner(name):
    """Флаг лиги 0.62 × 1.0 с вырезом снизу, на железной перекладине; ткань чуть волнистая, UV 0..1 (эмблему кладёт
    Godot декалью). Origin — центр перекладины (точка крепления), флаг висит в −Z."""
    a = Asset(name)
    a.add(bm_cyl(0.015, 0.78, (0, -0.02, 0), (0, 90, 0), segs=10), "Iron")
    for sx in (-1, 1):
        a.add(bm_sphere(0.025, (sx * 0.4, -0.02, 0), segs=8, rings=6), "Brass")
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    nx, nz = 8, 12
    W, H, notch = 0.62, 1.0, 0.16
    grid = []
    for j in range(nz + 1):
        row = []
        v = j / nz
        for i in range(nx + 1):
            u = i / nx
            z = -H * (1 - v) - 0.02
            if j == 0:
                z += notch * (1 - abs(2 * u - 1))
            y = -0.02 + 0.015 * math.sin(u * 6.0 + v * 2.0) + 0.02 * (1 - v) ** 2
            row.append(bm.verts.new(((u - 0.5) * W, y, z)))
        grid.append(row)
    for j in range(nz):
        for i in range(nx):
            f = bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
            for lp, (ii, jj) in zip(f.loops, ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1))):
                lp[uv].uv = (ii / nx, jj / nz)
            if f.normal.y > 0:
                f.normal_flip()
    bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=0.006)
    a.add(bm, "BannerCloth", keep_uv=True, smooth=True)
    return a.finish()


def build_Pipe(name, L=3.0):
    """Труба ⌀0.12 длиной L вдоль X с фланцами и болтами на концах. Origin — центр."""
    a = Asset(name)
    a.add(bm_cyl(0.06, L, rot=(0, 90, 0), segs=16), "Steel", along='X', smooth=True)
    for sx in (-1, 1):
        x = sx * (L / 2 - 0.03)
        a.add(bm_cyl(0.095, 0.04, (x, 0, 0), (0, 90, 0), segs=16, bevel=0.006), "Iron")
        for k in range(6):
            t = 2 * math.pi * k / 6
            a.add(bm_cyl(0.012, 0.06, (x, math.cos(t) * 0.075, math.sin(t) * 0.075), (0, 90, 0), segs=6), "Steel")
    return a.finish()


def build_Pipe_Elbow(name):
    """Колено 90°: дуга R 0.22 из плоскости XY вниз (от +X к −Z), фланцы. Origin — центр дуги."""
    a = Asset(name)
    a.add(bm_torus(0.22, 0.06, (0, 0, 0), (90, 0, 0), segs=16, rsegs=12, arc=0.25), "Steel", smooth=True)
    a.add(bm_cyl(0.095, 0.04, (0.22, 0, 0.0), segs=16, bevel=0.006), "Iron")
    a.add(bm_cyl(0.095, 0.04, (0.0, 0, 0.22), (0, 90, 0), segs=16, bevel=0.006), "Iron")
    return a.finish()


def build_Valve(name):
    """Вентиль-штурвал на трубе: корпус, шток, колесо со спицами (красное). Origin — центр корпуса."""
    a = Asset(name)
    a.add(bm_sphere(0.08, segs=12, rings=8), "Iron", smooth=True)
    a.add(bm_cyl(0.015, 0.16, (0, -0.1, 0), (90, 0, 0), segs=8), "Steel")
    a.add(bm_torus(0.1, 0.014, (0, -0.18, 0), (90, 0, 0), segs=20, rsegs=6), "PaintRed")
    for k in range(4):
        bm = bm_box((0.2, 0.012, 0.012))
        _xform(bm, (0, -0.18, 0), (0, k * 45, 0))
        a.add(bm, "PaintRed")
    return a.finish()


def build_Tire(name):
    """Покрышка ⌀0.62 лёжа. Origin — центр низа."""
    a = Asset(name)
    a.add(bm_torus(0.22, 0.09, (0, 0, 0.09), segs=28, rsegs=10), "Rubber", smooth=True)
    for k in range(28):
        t = 2 * math.pi * k / 28
        a.add(bm_box((0.03, 0.06, 0.12), loc=(math.cos(t) * 0.305, math.sin(t) * 0.305, 0.09), rot=(0, 0, math.degrees(t))), "Rubber")
    return a.finish()


def build_Cone(name):
    """Дорожный конус 0.5: основание-квадрат, конус с двумя светлыми полосами. Origin — центр низа."""
    a = Asset(name)
    a.add(bm_box((0.34, 0.34, 0.035), loc=(0, 0, 0.0175), bevel=0.01), "PaintRed")
    a.add(bm_cyl(0.13, 0.46, (0, 0, 0.26), segs=20, r2=0.025), "PaintRed", smooth=True)
    for z, r in ((0.22, 0.106), (0.34, 0.075)):
        a.add(bm_cyl(r + 0.004, 0.05, (0, 0, z), segs=20, r2=r - 0.008), "PaintCream", smooth=True)
    return a.finish()


def build_Jerrycan(name):
    """Канистра 0.35 × 0.47 × 0.17 с тройной ручкой и горлом. Origin — центр низа."""
    a = Asset(name)
    a.add(bm_box((0.35, 0.17, 0.42), loc=(0, 0, 0.21), bevel=0.02, seg=2), "PaintOlive")
    a.add(bm_box((0.3, 0.172, 0.012), loc=(0, 0, 0.21)), "PaintOlive")
    for x in (-0.08, 0.0, 0.08):
        a.add(bm_box((0.025, 0.04, 0.06), loc=(x, 0, 0.45)), "PaintOlive")
    a.add(bm_box((0.2, 0.04, 0.025), loc=(0, 0, 0.48), bevel=0.008), "PaintOlive")
    a.add(bm_cyl(0.03, 0.06, (0.13, 0, 0.44), (0, 30, 0), segs=10), "Iron")
    return a.finish()


# ----------------------------------------------------------------------------------------------------------------------
# модули комнаты
# ----------------------------------------------------------------------------------------------------------------------
def build_Wall(name, W=2.0, H=3.4):
    """Стеновой модуль W × H: вертикальные доски 0.2 м со щелями, поперечина на 1.15 м, чёрная подложка. Origin — центр
    низа ВНУТРЕННЕЙ плоскости (y=0), толщина уходит в +Y (0.12)."""
    a = Asset(name)
    a.add(bm_box((W, 0.04, H), loc=(0, 0.1, H / 2)), "Rubber")
    n = int(round(W / 0.2))
    rng = random.Random(int(W * 100 + H))
    for i in range(n):
        x = -W / 2 + 0.1 + i * 0.2
        dz = rng.uniform(-0.02, 0.0)
        a.add(bm_box((0.192, 0.035, H + dz), loc=(x, 0.02 + rng.uniform(-0.004, 0.004), (H + dz) / 2), bevel=0.006), "WoodWall", along='Z')
    a.add(bm_box((W, 0.04, 0.12), loc=(0, -0.018, 1.15), bevel=0.008), "WoodDark", along='X')
    return a.finish()


def build_Wall_Short(name):
    return build_Wall(name, 1.0, 3.4)


def build_Post(name, hazard=False, H=3.4):
    """Деревянная стойка 0.24 × 0.24 × H с железными обоймами и заклёпками; вариант Post_Hazard — с полосами опасности
    на лицевой грани. Origin — центр низа."""
    a = Asset(name)
    a.add(bm_box((0.24, 0.24, H), loc=(0, 0, H / 2), bevel=0.015), "WoodDark", along='Z')
    for z in (0.18, H - 0.25):
        a.add(bm_box((0.26, 0.26, 0.1), loc=(0, 0, z), bevel=0.006), "Iron")
        rivets(a, [(dx, -0.131, z) for dx in (-0.07, 0.07)], 0.01)
    if hazard:
        a.add(bm_box((0.2, 0.012, H - 0.6), loc=(0, -0.124, H / 2)), "Hazard", along='Z')
    return a.finish()


def build_Post_Hazard(name):
    return build_Post(name, True)


def build_Beam(name, L=9.0):
    """Потолочная балка L × 0.26 × 0.32 с железными хомутами через 1.5 м. Origin — центр низа."""
    a = Asset(name)
    a.add(bm_box((L, 0.26, 0.32), loc=(0, 0, 0.16), bevel=0.015), "WoodDark", along='X')
    for k in range(int(L / 1.5)):
        x = -L / 2 + 0.75 + k * 1.5
        a.add(bm_box((0.08, 0.28, 0.34), loc=(x, 0, 0.16)), "Iron")
    return a.finish()


def build_Ceiling(name, W=9.4, D=7.0):
    """Дощатый потолок W × D: доски 0.3 вдоль X. Origin — центр низа (z=0 — нижняя плоскость)."""
    a = Asset(name)
    n = int(D / 0.3)
    for i in range(n):
        a.add(bm_box((W, 0.29, 0.04), loc=(0, -D / 2 + 0.15 + i * 0.3, 0.02)), "WoodWall", along='X')
    return a.finish()


def build_Floor(name, W=9.4, D=7.0, tile=1.2):
    """Пол из плит tile × tile с фасками (роль Floor), высота плит гуляет на 3 мм. Origin — центр верхней плоскости."""
    a = Asset(name)
    rng = random.Random(5)
    nx, ny = int(math.ceil(W / tile)), int(math.ceil(D / tile))
    for i in range(nx):
        for j in range(ny):
            x0, y0 = -W / 2 + i * tile, -D / 2 + j * tile
            w, d = min(tile, W / 2 - x0), min(tile, D / 2 - y0)
            dz = rng.uniform(-0.003, 0.0)
            a.add(bm_box((w - 0.012, d - 0.012, 0.08), loc=(x0 + w / 2, y0 + d / 2, -0.04 + dz), bevel=0.01), "Floor", along='Y')
    a.add(bm_box((W, D, 0.02), loc=(0, 0, -0.07)), "Rubber")
    return a.finish()


def build_HazardSquare(name, s=1.9, t=0.08):
    """Разметка-квадрат s × s из ленты t (полосы опасности) вокруг стенда. Origin — центр, лента лежит на z=0..0.004."""
    a = Asset(name)
    for sx in (-1, 1):
        a.add(bm_box((t, s, 0.004), loc=(sx * (s / 2 - t / 2), 0, 0.002)), "Hazard", along='Y')
        a.add(bm_box((s - 2 * t, t, 0.004), loc=(0, sx * (s / 2 - t / 2), 0.002)), "Hazard", along='X')
    return a.finish()


def build_Stand(name):
    """Стенд для сборки бойца (как на листе G02): круглая плита на болтах, стойка, муфта, Т-образная перекладина
    с набалдашниками. Высота 1.25. Origin — центр низа."""
    a = Asset(name)
    a.add(bm_cyl(0.5, 0.07, (0, 0, 0.035), segs=40, bevel=0.012), "Iron")
    a.add(bm_cyl(0.42, 0.03, (0, 0, 0.085), segs=40, bevel=0.006), "Steel")
    a.add(bm_torus(0.46, 0.012, (0, 0, 0.07), segs=40, rsegs=5), "Steel")
    for k in range(12):
        t = 2 * math.pi * k / 12
        a.add(bm_cyl(0.022, 0.03, (math.cos(t) * 0.46, math.sin(t) * 0.46, 0.08), segs=6), "Steel")
    a.add(bm_cyl(0.12, 0.12, (0, 0, 0.16), segs=20, r2=0.08, bevel=0.01), "Iron")
    a.add(bm_cyl(0.055, 0.95, (0, 0, 0.66), segs=20), "Steel", smooth=True)
    a.add(bm_cyl(0.085, 0.14, (0, 0, 0.62), segs=20, bevel=0.012), "Iron")
    a.add(bm_cyl(0.012, 0.16, (0.09, 0, 0.62), (0, 90, 0), segs=6), "Brass")
    a.add(bm_cyl(0.08, 0.12, (0, 0, 1.15), segs=20, bevel=0.012), "Iron")
    a.add(bm_cyl(0.035, 0.9, (0, 0, 1.18), (0, 90, 0), segs=14), "Steel", smooth=True)
    for sx in (-1, 1):
        a.add(bm_sphere(0.05, (sx * 0.46, 0, 1.18), segs=12, rings=8), "Iron", smooth=True)
    return a.finish()


def build_Card(name, w, h, role, pins=2):
    """Лист бумаги на стене (чертёж, фото, афиша): квад w × h лицом в −Y с UV 0..1 под картинку роли, чуть отстоит от
    стены; кнопки-гвоздики сверху. Origin — центр листа в плоскости стены."""
    a = Asset(name)
    a.add(bm_quad((0, -0.006, 0), (w, h)), role, keep_uv=True)
    back = bm_quad((0, -0.005, 0), (w, h))
    for f in back.faces:
        f.normal_flip()
    a.add(back, "Paper")
    xs = [0.0] if pins == 1 else [-w / 2 + 0.03, w / 2 - 0.03]
    for x in xs:
        a.add(bm_sphere(0.009, (x, -0.012, h / 2 - 0.025), segs=8, rings=5), "PaintRed")
    return a.finish()


def build_Rug(name):
    """Ковёр 3.0 × 2.0 (тонкая плита, верх с UV 0..1 под rug.png). Origin — центр низа."""
    a = Asset(name)
    bm = bm_quad((0, 0, 0), (3.0, 2.0))
    _xform(bm, (0, 0, 0.006), (-90, 0, 0))
    for f in bm.faces:
        if f.normal.z < 0:
            f.normal_flip()
    a.add(bm, "Rug", keep_uv=True)
    a.add(bm_box((3.0, 2.0, 0.005), loc=(0, 0, 0.0025)), "Rubber")
    return a.finish()


# ----------------------------------------------------------------------------------------------------------------------
# пилотское место (06.10, лор LORE_V2 §2а п. 3: «нейро-шлем + очки/визор, быт, не киберпанк»; через шлем механик управляет
# куклой на стенде) и стенд экранов с показателями бойца
# ----------------------------------------------------------------------------------------------------------------------
def bm_rod(p0, p1, r, segs=10, r2=None):
    """Цилиндр от точки p0 до p1 (радиус r, у p1 — r2)."""
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    bm = bm_cyl(r, d.length, segs=segs, r2=r2)
    q = Vector((0, 0, 1)).rotation_difference(d.normalized())
    bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=q.to_matrix(), verts=bm.verts)
    _xform(bm, (p0 + p1) * 0.5)
    return bm


def build_NeuroHeadset(name):
    """Нейрошлем механика: обод вокруг головы, дуга через макушку, визор-очки спереди (тёмное стекло, голубая полоса связи),
    чашки у висков с кольцами-индикаторами, модуль NULL-интерфейса на затылке с антенной. Беспроводной.
    Origin — центр обода (на голове — середина головы на уровне лба), визор смотрит в −Y (в Godot +Z)."""
    a = Asset(name)
    # обод — эллипс 0.105 × 0.125 (голова длиннее, чем шире)
    band = bm_torus(0.108, 0.014, segs=36, rsegs=8)
    bmesh.ops.scale(band, vec=Vector((1.0, 1.16, 1.0)), verts=band.verts)
    a.add(band, "PlasticDark", smooth=True)
    pad = bm_torus(0.1, 0.009, (0, 0, -0.012), segs=36, rsegs=6)
    bmesh.ops.scale(pad, vec=Vector((1.0, 1.16, 1.0)), verts=pad.verts)
    a.add(pad, "Rubber", smooth=True)
    # дуга через макушку (от виска к виску) и вторая — от лба к затылку
    a.add(bm_torus(0.108, 0.011, rot=(90, 0, 0), segs=24, rsegs=6, arc=0.5), "PlasticLight", smooth=True)
    arc2 = bm_torus(0.118, 0.008, rot=(90, 0, 90), segs=24, rsegs=6, arc=0.5)
    a.add(arc2, "PlasticDark", smooth=True)
    # визор: скруглённая коробка-очки, стекло чуть выпуклое, полоса связи над стеклом
    vy = -0.128
    a.add(bm_rslab(0.2, 0.072, 0.03, 0.05, loc=(0, vy + 0.012, -0.018), bevel=0.006), "PlasticDark", smooth=True)
    glass = bm_grid(0.172, 0.05, 8, 3, bulge=0.008, loc=(0, vy - 0.014, -0.02))
    a.add(glass, "Visor", keep_uv=True, smooth=True)
    a.add(bm_box((0.15, 0.006, 0.006), loc=(0, vy - 0.016, 0.012)), "LinkGlow")
    a.add(bm_box((0.2, 0.03, 0.012), loc=(0, vy + 0.01, -0.058), bevel=0.004), "Rubber")
    # чашки у висков с кольцами
    for sx in (-1, 1):
        x = sx * 0.112
        a.add(bm_cyl(0.034, 0.03, (x, -0.01, -0.02), (0, 90, 0), segs=20, bevel=0.006), "PlasticLight", smooth=True)
        a.add(bm_torus(0.024, 0.0035, (x + sx * 0.016, -0.01, -0.02), (0, 90, 0), segs=20, rsegs=4), "LinkGlow")
        a.add(bm_cyl(0.012, 0.012, (x + sx * 0.018, -0.01, -0.02), (0, 90, 0), segs=10), "PlasticDark")
    # модуль на затылке и короткая антенна
    a.add(bm_box((0.07, 0.04, 0.05), loc=(0, 0.14, 0.0), bevel=0.01, seg=2), "PlasticLight")
    a.add(bm_box((0.045, 0.006, 0.006), loc=(0, 0.161, 0.012)), "LinkGlow")
    a.add(bm_rod((0.02, 0.15, 0.025), (0.035, 0.17, 0.09), 0.004, segs=6), "PlasticDark")
    a.add(bm_sphere(0.007, (0.035, 0.17, 0.092), segs=8, rings=5), "LampRed")
    return a.finish()


def build_LinkConsole(name):
    """Консоль связи на верстаке: корпус 0.46 × 0.3 × 0.12 с наклонной панелью (экран состояния, кнопки, кольцо связи) и
    подставкой-«головой» для нейрошлема справа. Подставка — купол на стойке, обод шлема ложится на высоту 0.33 над низом
    консоли (точка HEADSET_REST = (0.13, 0.0, 0.33) в кадре модели). Origin — центр низа консоли."""
    a = Asset(name)
    # корпус слева, низкий, с наклонной верхней панелью
    pts = [(-0.23, 0.0), (0.04, 0.0), (0.04, 0.08), (-0.23, 0.13)]
    a.add(bm_prism(pts, 0.28, loc=(0, 0.0, 0), rot=(0, 0, 0), bevel=0.008), "PlasticDark", along='X')
    scr = bm_grid(0.14, 0.075, 6, 3, bulge=0.0, loc=(0, 0, 0))
    bmesh.ops.rotate(scr, cent=(0, 0, 0), matrix=Euler((math.radians(-79), 0, 0), 'XYZ').to_matrix(), verts=scr.verts)
    _xform(scr, (-0.13, -0.02, 0.112))
    a.add(scr, "Screen", keep_uv=True)
    for i in range(4):
        bm = bm_box((0.026, 0.02, 0.012), bevel=0.003)
        _xform(bm, (-0.19 + i * 0.034, 0.085, 0.112 - 0.017 * 1.0 - i * 0.0), (11, 0, 0))
        a.add(bm, ("LampAmber", "PlasticLight", "PlasticLight", "LampGreen")[i])
    ring = bm_torus(0.045, 0.006, segs=28, rsegs=5)
    bmesh.ops.rotate(ring, cent=(0, 0, 0), matrix=Euler((math.radians(-11), 0, 0), 'XYZ').to_matrix(), verts=ring.verts)
    _xform(ring, (-0.02, 0.05, 0.1))
    a.add(ring, "LinkGlow")
    # подставка для шлема
    hx = 0.13
    a.add(bm_cyl(0.085, 0.022, (hx, 0, 0.011), segs=24, bevel=0.006), "Iron")
    a.add(bm_cyl(0.016, 0.22, (hx, 0, 0.13), segs=12), "Steel", smooth=True)
    dome = bm_sphere(0.085, (hx, 0, 0.3), segs=20, rings=10, scale=(1.0, 1.15, 0.95))
    a.add(dome, "PlasticDark", smooth=True)
    a.add(bm_torus(0.07, 0.004, (hx, 0, 0.245), segs=24, rsegs=4), "LinkGlow")
    # кабель питания уходит за верстак
    a.add(bm_rod((-0.2, 0.12, 0.03), (-0.26, 0.32, 0.01), 0.008, segs=6), "Rubber")
    return a.finish()


def build_PilotChair(name):
    """Кресло пилота: сиденье и высокая спинка с подголовником (кожа, прошивка полосами), подлокотники, газлифт,
    пятилучевая крестовина на колёсиках, голубая полоса связи по краю спинки. Сиденье 0.5 м. Origin — центр низа,
    сидящий смотрит в −Y."""
    a = Asset(name)
    # крестовина и колёса
    for k in range(5):
        t = 2 * math.pi * k / 5 + math.pi / 2
        tip = (math.cos(t) * 0.3, math.sin(t) * 0.3, 0.075)
        a.add(bm_rod((0, 0, 0.1), tip, 0.022, segs=8, r2=0.016), "Iron")
        a.add(bm_cyl(0.028, 0.03, (tip[0], tip[1], 0.03), (0, 90, math.degrees(t)), segs=12), "Rubber")
    a.add(bm_cyl(0.05, 0.08, (0, 0, 0.11), segs=16), "Iron")
    a.add(bm_cyl(0.025, 0.28, (0, 0, 0.29), segs=12), "Steel", smooth=True)
    a.add(bm_cyl(0.035, 0.12, (0, 0, 0.21), segs=12), "Rubber")
    # сиденье
    a.add(bm_box((0.5, 0.48, 0.05), loc=(0, 0, 0.44), bevel=0.01), "Iron")
    a.add(bm_rslab(0.52, 0.5, 0.06, 0.09, loc=(0, 0, 0.5), rot=(90, 0, 0), bevel=0.02), "Leather", smooth=True)
    for i in range(3):
        a.add(bm_box((0.008, 0.46, 0.006), loc=(-0.12 + i * 0.12, 0, 0.547)), "Rubber")
    # спинка (наклон назад 12°), подголовник
    back = bm_rslab(0.48, 0.62, 0.08, 0.085, loc=(0, 0, 0), bevel=0.02)
    _xform(back, (0, 0.27, 0.86), (-12, 0, 0))
    a.add(back, "Leather", smooth=True)
    head = bm_rslab(0.3, 0.16, 0.06, 0.08, loc=(0, 0, 0), bevel=0.02)
    _xform(head, (0, 0.35, 1.25), (-12, 0, 0))
    a.add(head, "Leather", smooth=True)
    for sx in (-1, 1):
        strip = bm_box((0.012, 0.012, 0.6))
        _xform(strip, (sx * 0.245, 0.225, 0.86), (-12, 0, 0))
        a.add(strip, "LinkGlow")
        a.add(bm_rod((sx * 0.12, 0.29, 0.5), (sx * 0.12, 0.34, 1.16), 0.012, segs=6), "Steel")
    a.add(bm_rod((0, 0.24, 0.46), (0, 0.3, 0.6), 0.03, segs=10), "Iron")
    # подлокотники
    for sx in (-1, 1):
        a.add(bm_rod((sx * 0.27, 0.12, 0.47), (sx * 0.27, 0.06, 0.68), 0.014, segs=8), "Iron")
        a.add(bm_box((0.07, 0.3, 0.035), loc=(sx * 0.27, 0.04, 0.7), bevel=0.012), "Rubber")
    return a.finish()


def _monitor(a, w, h, d=0.045, bezel=0.022, mount=True, glow=None):
    """Плоский монитор w × h: корпус-рамка, экран Screen (UV 0..1), крепление сзади. Origin — центр задней плоскости."""
    a.add(bm_rslab(w + 2 * bezel, h + 2 * bezel, 0.012, d, loc=(0, -d / 2, 0), bevel=0.004), "PlasticDark")
    a.add(bm_grid(w, h, 4, 3, loc=(0, -d - 0.001, 0)), "Screen", keep_uv=True)
    if glow:
        a.add(bm_box((w * 0.35, 0.004, 0.004), loc=(0, -d - 0.002, -h / 2 - bezel * 0.5)), glow)
    if mount:
        a.add(bm_box((0.1, 0.03, 0.1), loc=(0, 0.012, 0)), "Iron")


def build_Monitor_Flat(name):
    """Монитор 0.6 × 0.36. Origin — центр задней плоскости (крепление к стойке), экран смотрит в −Y."""
    a = Asset(name)
    _monitor(a, 0.6, 0.36, glow="LinkGlow")
    return a.finish()


def build_Monitor_Wide(name):
    """Широкий монитор 1.04 × 0.44 — главный экран стенда. Origin — центр задней плоскости."""
    a = Asset(name)
    _monitor(a, 1.04, 0.44, d=0.05, bezel=0.026, glow="LinkGlow")
    for sx in (-1, 1):
        a.add(bm_box((0.016, 0.006, 0.016), loc=(sx * 0.5, -0.054, -0.248)), "LampAmber")
    return a.finish()


def build_Monitor_Small(name):
    """Маленький монитор 0.34 × 0.24. Origin — центр задней плоскости."""
    a = Asset(name)
    _monitor(a, 0.34, 0.24, d=0.035, bezel=0.016)
    return a.finish()


def build_Monitor_CRT(name):
    """Старый монитор-кинескоп 0.44 × 0.36 × 0.38 (кремовый корпус, выпуклый экран, кнопки). Origin — центр задней плоскости
    рамки (стоит на полке стойки — низ корпуса на −0.21 от origin)."""
    a = Asset(name)
    W, H, D = 0.46, 0.4, 0.36
    a.add(bm_rslab(W, H, 0.03, 0.06, loc=(0, -0.03, 0), bevel=0.008), "PaintCream")
    a.add(bm_box((W - 0.06, D - 0.06, H - 0.06), loc=(0, D / 2 - 0.03, -0.01), bevel=0.04, seg=2), "PaintCream")
    a.add(bm_rframe(0.37, 0.29, 0.03, 0.34, 0.26, 0.04, 0.012, loc=(0, -0.064, 0.02)), "Iron")
    a.add(bm_grid(0.35, 0.27, 8, 6, bulge=0.02, loc=(0, -0.062, 0.02)), "Screen", keep_uv=True, smooth=True)
    for i in range(3):
        a.add(bm_cyl(0.009, 0.01, (0.12 + i * 0.03, -0.064, -0.165), (90, 0, 0), segs=8), "Iron")
    a.add(bm_sphere(0.007, (-0.17, -0.066, -0.165), segs=8, rings=5), "LampGreen")
    return a.finish()


# раскладка экранов стенда (в кадре стойки, x вбок, z вверх; экраны на y = −0.07): имя модели, центр, роль на стенде
RACK_SCREENS = [
    ("Wide", (0.0, 1.62), "main"),
    ("Flat", (-0.71, 2.2), "energy"), ("Flat", (0.71, 2.2), "parts"),
    ("Small", (-0.36, 2.28), "pulse"), ("Small", (0.36, 2.28), "link"),
    ("Flat", (-0.71, 1.0), "mass"), ("Flat", (0.71, 1.0), "joints"),
    ("Small", (0.0, 1.06), "hp"),
]


def build_ScreenRack(name, W=2.1, H=2.62):
    """Стенд экранов — ферма у стены: две стойки-фермы, поперечины на трёх уровнях, полка снизу (с ней — мелочь: кофр,
    кружка), пучки кабелей, сигнальные лампы сверху, табличка BAY 07. Ширина W, высота H. Экраны ставит сборщик сцены по
    RACK_SCREENS (godot/tools/build_garage_menu.gd). Origin — центр низа, лицом в −Y."""
    a = Asset(name)
    for sx in (-1, 1):
        x = sx * (W / 2 - 0.05)
        for dy in (-0.04, 0.04):
            a.add(bm_box((0.035, 0.035, H), loc=(x - sx * 0.035, dy, H / 2)), "Iron")
            a.add(bm_box((0.035, 0.035, H), loc=(x + sx * 0.035, dy, H / 2)), "Iron")
        for k in range(int(H / 0.3)):          # раскосы фермы
            z0 = 0.1 + k * 0.3
            a.add(bm_rod((x - 0.035, -0.045, z0), (x + 0.035, -0.045, z0 + 0.3), 0.006, segs=5), "Steel")
        a.add(bm_box((0.32, 0.4, 0.04), loc=(x, 0.05, 0.02), bevel=0.008), "Iron")
        a.add(bm_sphere(0.03, (x, -0.02, H + 0.03), segs=10, rings=6), "LampAmber" if sx < 0 else "LampRed")
    for z in (0.66, 1.34, 1.94, 2.5):
        a.add(bm_box((W - 0.1, 0.05, 0.05), loc=(0, 0.02, z), bevel=0.006), "Iron")
    # полка внизу
    a.add(bm_box((W - 0.2, 0.42, 0.035), loc=(0, -0.12, 0.44), bevel=0.006), "WoodDark", along='X')
    for sx in (-1, 1):
        a.add(bm_rod((sx * (W / 2 - 0.12), 0.0, 0.42), (sx * (W / 2 - 0.12), -0.3, 0.42), 0.012, segs=6), "Iron")
    # кабели: пучок по поперечине и вниз к полу
    for i in range(4):
        y = 0.07 + i * 0.012
        a.add(bm_rod((-W / 2 + 0.2, y, 2.45 - i * 0.02), (W / 2 - 0.25, y, 2.42 - i * 0.025), 0.009, segs=6), "Rubber")
        a.add(bm_rod((W / 2 - 0.25 + i * 0.02, y, 2.42), (W / 2 - 0.3 + i * 0.03, y + 0.05, 0.02), 0.009, segs=6), "Rubber")
    # табличка BAY 07
    a.add(bm_box((0.36, 0.012, 0.1), loc=(0, -0.01, 2.72), bevel=0.004), "PaintCream")
    a.add(bm_box((0.32, 0.004, 0.012), loc=(0, -0.018, 2.705)), "PaintRed")
    return a.finish()


CARDS = [("Card_Blueprint", 1.2, 0.825, "Blueprint", 2)] + \
    [("Card_Photo_%s" % k, 0.22, 0.24, "Photo_%s" % k, 1) for k in "ABCDEF"] + \
    [("Card_Poster_%s" % k, 0.42, 0.62, "Poster_%s" % k, 2) for k in "ABC"]


MODULES = [
    ("TV", build_TV), ("Sideboard", build_Sideboard), ("Crate", build_Crate), ("Crate_Small", build_Crate_Small),
    ("Mug", build_Mug), ("Stand", build_Stand),
    ("Gate", build_Gate), ("ControlBox", build_ControlBox),
    ("Workbench", build_Workbench), ("Pegboard", build_Pegboard), ("Stool", build_Stool), ("Lamp", build_Lamp),
    ("Shelf_Wall", build_Shelf_Wall), ("Shelf_Short", build_Shelf_Short), ("Cup_A", build_Cup_A), ("Cup_B", build_Cup_B),
    ("Boombox", build_Boombox), ("Helmet", build_Helmet), ("Books", build_Books), ("Plant", build_Plant),
    ("Lockers", build_Lockers), ("Cabinet", build_Cabinet), ("Case_Olive", build_Case_Olive), ("Case_Navy", build_Case_Navy),
    ("Toolbox", build_Toolbox), ("Storage", build_Storage), ("QBox", build_QBox),
    ("Radio", build_Radio), ("Breaker", build_Breaker),
    ("Banner", build_Banner), ("Pipe", build_Pipe), ("Pipe_Elbow", build_Pipe_Elbow), ("Valve", build_Valve),
    ("Tire", build_Tire), ("Cone", build_Cone), ("Jerrycan", build_Jerrycan),
    ("Wall", build_Wall), ("Wall_Short", build_Wall_Short), ("Post", build_Post), ("Post_Hazard", build_Post_Hazard),
    ("Beam", build_Beam), ("Ceiling", build_Ceiling), ("Floor", build_Floor), ("HazardSquare", build_HazardSquare),
    ("Rug", build_Rug),
    ("NeuroHeadset", build_NeuroHeadset), ("LinkConsole", build_LinkConsole), ("PilotChair", build_PilotChair),
    ("Monitor_Flat", build_Monitor_Flat), ("Monitor_Wide", build_Monitor_Wide), ("Monitor_Small", build_Monitor_Small),
    ("Monitor_CRT", build_Monitor_CRT), ("ScreenRack", build_ScreenRack),
] + [(n, (lambda nm, w=w, h=h, r=r, p=p: build_Card(nm, w, h, r, p))) for n, w, h, r, p in CARDS]


def tri_count(obj):
    dg = bpy.context.evaluated_depsgraph_get()
    tris = 0
    for o in [obj] + list(obj.children_recursive):
        if o.type == 'MESH':
            me = o.evaluated_get(dg).to_mesh()
            tris += sum(len(p.vertices) - 2 for p in me.polygons)
            o.evaluated_get(dg).to_mesh_clear()
    return tris


def main():
    argv = C.args_after_dashdash()
    C.reset_scene()
    os.makedirs(OUT, exist_ok=True)
    report = {}
    bad = []
    for name, build in MODULES:
        if argv and name not in argv:
            continue
        full = "Garage_" + name
        root = build(full)
        root.name = full
        tris = tri_count(root)
        budget = TRI_BUDGET_BIG if name.startswith(("Floor", "Wall", "Ceiling")) else TRI_BUDGET
        C.export_glb(os.path.join(OUT, full + ".glb"), [root])
        dims = [round(v, 2) for v in root.dimensions]
        report[name] = {"tris": tris, "size_m": dims, "materials": [m.name for m in root.data.materials]}
        if tris > budget:
            bad.append(name)
        bpy.data.objects.remove(root, do_unlink=True)
    print("=== garage kit ===", json.dumps(report, ensure_ascii=False))
    if bad:
        print("ERROR: over budget:", bad)
        sys.exit(1)


main()
