#!/usr/bin/env python3
"""Библиотека пропсов арены «Руины» по листу R17 (docs/refs/R17-a-props-library.jpg) — настоящие меши Blender
с PBR-текстурами из assets/textures/pbr (печёт tools/blender/textures.py по листу R21).

Запуск (Blender 4.5 LTS, headless):
    /Applications/Blender.app/Contents/MacOS/Blender -b --python godot/tools/blender/props.py [-- Имя …]
    → godot/assets/models/props/<Name>.glb   (один glb = один пропс или семья состояний; Y вверх в Godot)
Переменные окружения:
    PROPS_TEX_SIZE=1024  текстуры уменьшаются до этого размера перед вшиванием (2048 — как есть);
    PROPS_IMG=WEBP|PNG   формат картинок внутри glb (WEBP читает Godot 4.7, набор 2048² ≈ 0.3 МБ вместо ~8 МБ PNG);
    PROPS_CACHE=<папка>  кэш уменьшенных текстур (по умолчанию <tmp>/ragdoll_props_pbr).

Соглашения (docs/plan-demo/ASSET_PIPELINE.md, common.py): метры; Blender Z вверх, X вбок, «лицо» в −Y (после
экспорта +Z в Godot, к камере); origin — центр основания (у дверей ворот — линия петли, у обломков — их собственное
основание); материалы Principled BSDF с текстурами (textured_material), 1 тайл = 1 м; бюджет ≤ 3000 треугольников
на объект (скрипт печатает таблицу и падает при превышении).

Файлы и объекты внутри (имена узлов в Godot совпадают):
    Barrel.glb          Intact | Damaged | Destroyed/{Piece_0..5}   бочка ⌀0.62×0.8: 16 клёпок, 2 обруча с заклёпками
    Crate.glb           Intact | Damaged | Destroyed/{Piece_0..5}   ящик 0.7: рама, доски, X-раскосы, железные уголки
    Post.glb            столб моста ⌀0.3×1.6 с двумя намотками каната и железным колпаком
    Post_2m.glb         столб палубы ⌀0.3×2.0 (намотка вверху)
    Plank.glb           доска моста 0.25×0.9×0.05 с двумя сквозными отверстиями под канат (вдоль X, y=±0.38)
    Rope_Segment.glb    отрезок каната ⌀0.04 длиной 0.3 вдоль +X, origin в начале (скрипт моста тянет его между досками)
    Beam_3m.glb         балка 0.2×0.2×3 вдоль X (виселица клетки)
    Deck_3m.glb, Deck_4m.glb  настил палубы: 2 балки вдоль X + доски поперёк (1.8 м), верх на z=0.25
    Banner.glb          Banner (древко 3 м + навершие + перекладина) с детьми Cloth_Red / Cloth_Blue / Cloth_White
                        (полотнище 1.2×1.8 с рваным низом и короной-декалью; origin полотнища — у перекладины, z=2.86)
    Gate_Arch.glb       арка ворот: проём 3 м, пилоны 1 м, высота 3.2, глубина 0.8, клинчатый свод, плющ; origin низ-центр
    Gate_Door_L.glb, Gate_Door_R.glb  створки 1.5×2.9: доски, 3 железные полосы с заклёпками, кольцо на правой;
                        origin — нижняя точка петли (L: створка уходит в +X, R: в −X)
    Wall_Segment.glb    стена 2×3×0.8 с рельефной кладкой спереди (блоки 50×25 с фаской, каждый = блок текстуры)
    Stone_Platform_2m/4m/5m.glb  плиты L×2×0.4, сверху плитняк с фасками
    Stone_Block.glb     блок 0.5³
    Torch.glb           Torch (кронштейн у стены в +Y, рукоять, обмотка) с ребёнком Flame (пламя, эмиссия)
    Cage.glb            клетка ⌀0.8×1.4 из прутьев, купол, крюк (верх крюка z≈1.86)
    Chain_Link.glb      звено цепи 0.24 (origin низ)
"""
import math
import os
import random
import sys
import tempfile

import bpy
import bmesh
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import common as C  # noqa: E402

GODOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(GODOT, "assets", "models", "props")
CROWN = os.path.join(GODOT, "assets", "textures", "decals", "crown.png")
TRI_BUDGET = 3000
TEX_SIZE = int(os.environ.get("PROPS_TEX_SIZE", "1024"))
IMG_FORMAT = os.environ.get("PROPS_IMG", "WEBP")
CACHE = os.environ.get("PROPS_CACHE") or os.path.join(tempfile.gettempdir(), "ragdoll_props_pbr")
TAU = 2.0 * math.pi
RNG = random.Random(17)


# ----------------------------------------------------------------------------------------------------------------------
# материалы
# ----------------------------------------------------------------------------------------------------------------------
_MATS = {}


def pbr_folder(name):
    """Папка PBR-набора: исходная (2048²) или уменьшенная копия в кэше (PROPS_TEX_SIZE)."""
    src = os.path.join(C.PBR_DIR, name)
    if TEX_SIZE >= 2048:
        return src
    dst = os.path.join(CACHE, str(TEX_SIZE), name)
    os.makedirs(dst, exist_ok=True)
    for ch in ("albedo", "roughness", "normal", "metallic"):
        s = os.path.join(src, ch + ".png")
        d = os.path.join(dst, ch + ".png")
        if not os.path.exists(s):
            continue
        if os.path.exists(d) and os.path.getmtime(d) >= os.path.getmtime(s):
            continue
        img = bpy.data.images.load(s)
        if ch != "albedo":
            img.colorspace_settings.name = 'Non-Color'
        if img.size[0] > TEX_SIZE:
            img.scale(TEX_SIZE, TEX_SIZE)
        img.filepath_raw = d
        img.file_format = 'PNG'
        img.save()
        bpy.data.images.remove(img)
    return dst


def M(name):
    """Материал по имени (лениво): текстурные наборы R21 и несколько плоских."""
    if name in _MATS:
        return _MATS[name]
    tex = {
        "Wood": ("wood", {}),
        "WoodDark": ("wood_dark", {}),
        "Iron": ("iron", {}),
        "Stone": ("stone", {"tint": (0.86, 0.80, 0.70, 1.0)}),
        "Stone_Grey": ("stone", {"tint": (0.68, 0.66, 0.62, 1.0)}),
        "Rope": ("rope", {}),
        "Cloth_Red": ("fabric_red", {}),
        "Cloth_Blue": ("fabric_blue", {}),
        "Cloth_White": ("fabric", {}),
    }
    flat = {
        "Mortar": ((0.16, 0.14, 0.12, 1.0), 0.95, 0.0),
        "Leaf": ((0.11, 0.26, 0.07, 1.0), 0.85, 0.0),
        "LeafDark": ((0.05, 0.15, 0.04, 1.0), 0.90, 0.0),
        "Char": ((0.09, 0.07, 0.06, 1.0), 0.95, 0.0),
        "Gold": ((0.85, 0.66, 0.26, 1.0), 0.40, 0.90),
        "Flame": ((1.0, 0.55, 0.12, 1.0), 0.60, 0.0),
    }
    if name in tex:
        folder, kw = tex[name]
        m = C.textured_material(name, pbr_folder(folder), **kw)
        m.use_backface_culling = not name.startswith("Cloth")
    else:
        base, rough, metal = flat[name]
        if name == "Flame":
            m = C.material(name, base, rough, metal, emission=(1.0, 0.42, 0.08, 1.0), emission_strength=6.0)
        else:
            m = C.material(name, base, rough, metal)
        m.use_backface_culling = name not in ("Leaf", "LeafDark", "Flame")
    _MATS[name] = m
    return m


def decal_material(name, tint=None):
    """Материал короны-декали (как в common.decal_plane), опционально с тинтом (тёмная корона на белом полотне)."""
    q = C.decal_plane(name + "_tmp", CROWN, (0.1, 0.1), (0, 0, -100))
    mat = q.data.materials[0]
    mat.name = name
    bpy.data.objects.remove(q, do_unlink=True)
    if tint is not None:
        nt = mat.node_tree
        bsdf = nt.nodes.get("Principled BSDF")
        tex = [n for n in nt.nodes if n.type == 'TEX_IMAGE'][0]
        mix = nt.nodes.new('ShaderNodeMix')
        mix.data_type = 'RGBA'
        mix.blend_type = 'MULTIPLY'
        mix.inputs[0].default_value = 1.0
        mix.inputs[7].default_value = tint
        nt.links.new(tex.outputs['Color'], mix.inputs[6])
        nt.links.new(mix.outputs[2], bsdf.inputs['Base Color'])
    return mat


# ----------------------------------------------------------------------------------------------------------------------
# геометрия
# ----------------------------------------------------------------------------------------------------------------------
def mesh_obj(name, bm, mats=()):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    for m in mats:
        me.materials.append(m)
    return o


def empty(name):
    o = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(o)
    return o


def box(name, size, mat=None, jitter=0.0):
    """Куб size, центр в нуле (геометрия локальная, origin в нуле)."""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
    o = bpy.context.active_object
    o.name = name
    o.scale = size
    C.apply_transforms(o, scale=True)
    if jitter > 0.0:
        for v in o.data.vertices:
            v.co += Vector((RNG.uniform(-jitter, jitter), RNG.uniform(-jitter, jitter), RNG.uniform(-jitter, jitter)))
    if mat is not None:
        o.data.materials.append(mat)
    return o


def board(name, size, mat, jitter=0.002, broken=None):
    """Доска; broken=(ось, знак, глубина) — рваный торец: вершины этого конца утоплены на случайную долю глубины."""
    o = box(name, size, mat, jitter)
    if broken:
        ax, sgn, depth = broken
        for v in o.data.vertices:
            if v.co[ax] * sgn > 0.0:
                v.co[ax] -= sgn * RNG.uniform(0.15, 1.0) * depth
    return o


def place(o, loc=(0, 0, 0), rot=(0, 0, 0)):
    """Впекает поворот и позицию в геометрию; origin остаётся в мировом нуле."""
    if any(abs(r) > 1e-9 for r in rot):
        o.rotation_euler = rot
        C.apply_transforms(o, rotation=True)
    o.location = loc
    C.apply_transforms(o, location=True)
    return o


def lathe(name, profile, segs=24, mat=None, close_bottom=True, close_top=True):
    """Тело вращения вокруг Z из профиля [(r, z), ...]; r=0 — полюс."""
    bm = bmesh.new()
    rings = []
    for r, z in profile:
        if r < 1e-6:
            rings.append([bm.verts.new((0.0, 0.0, z))])
        else:
            rings.append([bm.verts.new((r * math.cos(TAU * i / segs), r * math.sin(TAU * i / segs), z)) for i in range(segs)])
    for a, b in zip(rings, rings[1:]):
        if len(a) == 1 and len(b) == 1:
            continue
        for i in range(segs):
            j = (i + 1) % segs
            if len(a) == 1:
                bm.faces.new((a[0], b[i], b[j]))
            elif len(b) == 1:
                bm.faces.new((a[i], a[j], b[0]))
            else:
                bm.faces.new((a[i], a[j], b[j], b[i]))
    if close_bottom and len(rings[0]) > 1:
        bm.faces.new(list(reversed(rings[0])))
    if close_top and len(rings[-1]) > 1:
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return mesh_obj(name, bm, [mat] if mat else [])


def ring(name, r_in, r_out, z0, z1, segs=24, mat=None):
    """Обруч квадратного сечения."""
    return lathe(name, [(r_in, z0), (r_out, z0), (r_out, z1), (r_in, z1), (r_in, z0)], segs, mat, False, False)


def rivet(name, loc, direction, r=0.01, h=0.012, mat=None):
    """Заклёпка: 6-гранный цилиндр вдоль direction (единичный вектор), центр в loc."""
    d = Vector(direction).normalized()
    rot = d.to_track_quat('Z', 'Y').to_euler()
    bpy.ops.mesh.primitive_cylinder_add(vertices=6, radius=r, depth=h, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    C.apply_transforms(o, location=True, rotation=True)
    o.data.materials.append(mat or M("Iron"))
    C.uv_box(o, 1.0)
    return o


def spike(name, base, tip, width, mat):
    """Щепка: тонкий тетраэдр от base к tip."""
    base = Vector(base)
    tip = Vector(tip)
    d = tip - base
    p1 = d.orthogonal().normalized() * width
    p2 = d.cross(p1).normalized() * width
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    v0 = bm.verts.new(base + p1)
    v1 = bm.verts.new(base - p1 * 0.5 + p2 * 0.87)
    v2 = bm.verts.new(base - p1 * 0.5 - p2 * 0.87)
    vt = bm.verts.new(tip)
    for f in ((v0, v1, v2), (v0, vt, v1), (v1, vt, v2), (v2, vt, v0)):
        face = bm.faces.new(f)
        for l in face.loops:
            l[uvl].uv = (0.12 + l.vert.co.x * 0.3, l.vert.co.z)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return mesh_obj(name, bm, [mat])


def bevel_apply(o, width, segments=1, angle=30.0):
    m = C.bevel(o, width, segments, angle)
    m.harden_normals = True
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier=m.name)


def smooth(o, angle=30.0):
    for p in o.data.polygons:
        p.use_smooth = True
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    try:
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(angle))
    except Exception:
        pass


def merge(objs, name):
    if len(objs) == 1:
        objs[0].name = name
        return objs[0]
    return C.join(objs, name)


def finish(o, angle=30.0, origin=(0.0, 0.0, 0.0)):
    C.set_origin(o, origin)
    smooth(o, angle)
    return o


def tri_count(obj):
    dg = bpy.context.evaluated_depsgraph_get()
    total = 0
    for o in [obj] + list(obj.children_recursive):
        if o.type != 'MESH':
            continue
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
        total += sum(len(p.vertices) - 2 for p in me.polygons)
        ev.to_mesh_clear()
    return total


# --- развёртки -------------------------------------------------------------------------------------------------------
def uv_offset(o, du=0.0, dv=0.0):
    for d in o.data.uv_layers[0].data:
        d.uv = (d.uv[0] + du, d.uv[1] + dv)


def uv_board(o, along='X', scale=1.0):
    """Доска: кубическая проекция + сдвиг U на 0.125, чтобы доска шириной ≤ 0.25 попала внутрь одной доски текстуры."""
    C.uv_box(o, scale, along)
    uv_offset(o, 0.125, 0.0)


def uv_fit(o, scale=1.0):
    """Каждая грань → внутрь одного блока текстуры камня (0.5×0.25 на тайл: чётные ряды со швами на U=0/0.5,
    нечётные — на 0.25/0.75). Длинная сторона грани идёт в U; масштаб урезается так, чтобы грань не пересекла шов."""
    uv = C._ensure_uv(o)
    me = o.data
    for poly in me.polygons:
        n = poly.normal
        ax = max(range(3), key=lambda k: abs(n[k]))
        uax, vax = [k for k in range(3) if k != ax]
        cos_ = [me.vertices[me.loops[li].vertex_index].co for li in poly.loop_indices]
        eu = max(c[uax] for c in cos_) - min(c[uax] for c in cos_)
        ev = max(c[vax] for c in cos_) - min(c[vax] for c in cos_)
        if ev > eu:
            uax, vax = vax, uax
            eu, ev = ev, eu
        s = min(scale, 0.47 / max(eu, 1e-6), 0.225 / max(ev, 1e-6))
        r = RNG.randrange(4)
        c = RNG.randrange(2)
        bu = 0.25 + 0.5 * c + (0.25 if r % 2 else 0.0)
        bv = 0.125 + 0.25 * r
        cen = poly.center
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            uv[li].uv = (bu + s * (co[uax] - cen[uax]), bv + s * (co[vax] - cen[vax]))


def relief_tile(name, u0, u1, v0, v1, base, top, orient, chamfer, mat, jitter=0.004):
    """Выступающая плитка с фаской без задней грани. orient='-Y': (u,v)=(x,z), глубина по −Y (стена);
    orient='+Z': (u,v)=(x,y), глубина по +Z (пол). base — глубина основания, top — глубина лицевой грани.
    UV: вся плитка вписана в один блок текстуры камня."""
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")

    def P(u, v, d):
        j = lambda: RNG.uniform(-jitter, jitter)  # noqa: E731
        if orient == '-Y':
            return Vector((u + j(), d, v + j()))
        return Vector((u + j(), v + j(), d))

    rim_b = [bm.verts.new(P(u0, v0, base)), bm.verts.new(P(u1, v0, base)), bm.verts.new(P(u1, v1, base)), bm.verts.new(P(u0, v1, base))]
    sgn = -1.0 if orient == '-Y' else 1.0
    mid = top - sgn * chamfer
    rim_t = [bm.verts.new(P(u0, v0, mid)), bm.verts.new(P(u1, v0, mid)), bm.verts.new(P(u1, v1, mid)), bm.verts.new(P(u0, v1, mid))]
    c = chamfer
    inner = [bm.verts.new(P(u0 + c, v0 + c, top)), bm.verts.new(P(u1 - c, v0 + c, top)), bm.verts.new(P(u1 - c, v1 - c, top)), bm.verts.new(P(u0 + c, v1 - c, top))]
    for i in range(4):
        k = (i + 1) % 4
        bm.faces.new((rim_b[i], rim_b[k], rim_t[k], rim_t[i]))
        bm.faces.new((rim_t[i], rim_t[k], inner[k], inner[i]))
    bm.faces.new(inner)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    eu, ev = u1 - u0, v1 - v0
    swap = ev > eu
    s = min(1.0, 0.47 / max(eu, ev), 0.225 / min(eu, ev))
    r = RNG.randrange(4)
    cc = RNG.randrange(2)
    bu = 0.25 + 0.5 * cc + (0.25 if r % 2 else 0.0)
    bv = 0.125 + 0.25 * r
    cu, cv = (u0 + u1) * 0.5, (v0 + v1) * 0.5
    for f in bm.faces:
        for l in f.loops:
            co = l.vert.co
            u, v = (co.x, co.z) if orient == '-Y' else (co.x, co.y)
            du, dv = (v - cv, u - cu) if swap else (u - cu, v - cv)
            l[uvl].uv = (bu + s * du, bv + s * dv)
    return mesh_obj(name, bm, [mat])


def helix_tube(name, radius, tube_r, z0, turns, pitch, mat, seg_per_turn=16, sides=6, uv_scale=4.0):
    """Спиральная намотка каната (труба по винтовой линии), UV: U — обхват, V — длина × uv_scale."""
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    n = int(round(turns * seg_per_turn)) + 1
    step = math.hypot(TAU * radius, pitch) / seg_per_turn
    rings = []
    for i in range(n):
        t = i / seg_per_turn
        a = TAU * t
        centre = Vector((radius * math.cos(a), radius * math.sin(a), z0 + pitch * t))
        tang = Vector((-math.sin(a) * TAU * radius, math.cos(a) * TAU * radius, pitch)).normalized()
        nrm = Vector((math.cos(a), math.sin(a), 0.0))
        binrm = tang.cross(nrm).normalized()
        nrm = binrm.cross(tang).normalized()
        rings.append([bm.verts.new(centre + (nrm * math.cos(TAU * k / sides) + binrm * math.sin(TAU * k / sides)) * tube_r) for k in range(sides)])
    for i in range(n - 1):
        for k in range(sides):
            k2 = (k + 1) % sides
            f = bm.faces.new((rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]))
            us = [k / sides, (k + 1) / sides, (k + 1) / sides, k / sides]
            vs = [i * step * uv_scale, i * step * uv_scale, (i + 1) * step * uv_scale, (i + 1) * step * uv_scale]
            for l, u, v in zip(f.loops, us, vs):
                l[uvl].uv = (u, v)
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return mesh_obj(name, bm, [mat])


# ----------------------------------------------------------------------------------------------------------------------
# бочка
# ----------------------------------------------------------------------------------------------------------------------
BR_R0, BR_R1, BR_H, NS = 0.26, 0.31, 0.8, 16


def barrel_r(z):
    t = (z - BR_H * 0.5) / (BR_H * 0.5)
    return BR_R1 - (BR_R1 - BR_R0) * t * t


def stave_set(name, indices, thick=0.02, gap=0.007, tops=None, tilt=None):
    """Клёпки бочки с индексами indices (0..15). tops={i:(z_обл, размах)} — обломанные сверху; tilt={i:k} — отогнуты
    наружу (смещение k·z). UV: U = угол/2π × 4 → ровно одна доска текстуры на клёпку, V = z."""
    tops = tops or {}
    tilt = tilt or {}
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    ZS = [0.0, 0.1, 0.25, 0.4, 0.55, 0.7, BR_H]
    g = gap / (2.0 * BR_R1)
    for i in indices:
        a0, a1 = TAU * i / NS, TAU * (i + 1) / NS
        angs = [a0 + g, 0.5 * (a0 + a1), a1 - g]
        cut = tops.get(i)
        zl = [z for z in ZS if cut is None or z < cut[0] - 0.03]
        if cut:
            zl.append(cut[0])
        out_r, in_r = [], []
        for z in zl:
            r = barrel_r(z)
            push = tilt.get(i, 0.0) * z
            ro, ri = [], []
            for a in angs:
                zz = z + (RNG.uniform(-cut[1], cut[1]) if (cut and z == cut[0]) else 0.0)
                ro.append(bm.verts.new(((r + push) * math.cos(a), (r + push) * math.sin(a), zz)))
                ri.append(bm.verts.new(((r - thick + push) * math.cos(a), (r - thick + push) * math.sin(a), zz)))
            out_r.append(ro)
            in_r.append(ri)
        for j in range(len(zl) - 1):
            for k in range(2):
                bm.faces.new((out_r[j][k], out_r[j][k + 1], out_r[j + 1][k + 1], out_r[j + 1][k]))
                bm.faces.new((in_r[j][k + 1], in_r[j][k], in_r[j + 1][k], in_r[j + 1][k + 1]))
            bm.faces.new((in_r[j][0], out_r[j][0], out_r[j + 1][0], in_r[j + 1][0]))
            bm.faces.new((out_r[j][2], in_r[j][2], in_r[j + 1][2], out_r[j + 1][2]))
        for k in range(2):
            bm.faces.new((out_r[0][k + 1], out_r[0][k], in_r[0][k], in_r[0][k + 1]))
            bm.faces.new((out_r[-1][k], out_r[-1][k + 1], in_r[-1][k + 1], in_r[-1][k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        cap = abs(f.normal.z) > 0.7
        for l in f.loops:
            co = l.vert.co
            a = math.atan2(co.y, co.x) % TAU
            l[uvl].uv = (a / TAU * 4.0, math.hypot(co.x, co.y) if cap else co.z)
    return mesh_obj(name, bm, [M("WoodDark")])


def barrel_lid(name, z0, z1, r):
    o = lathe(name, [(0, z0), (r, z0), (r, z1), (0, z1)], NS, M("Wood"))
    C.uv_box(o, 1.0, 'Y')
    return o


def barrel_band(name, z, width=0.05, thick=0.012, extra=0.006, tilt=0.0, rivets=8):
    r = barrel_r(z) + extra
    parts = [ring(name, r, r + thick, -width * 0.5, width * 0.5, 32, M("Iron"))]
    C.uv_cylinder_along(parts[0], 'Z', 1.0)
    for k in range(rivets):
        a = TAU * (k + 0.5) / rivets
        parts.append(rivet("%s_riv%d" % (name, k), ((r + thick) * math.cos(a), (r + thick) * math.sin(a), 0.0), (math.cos(a), math.sin(a), 0.0)))
    o = merge(parts, name)
    place(o, (0, 0, z), (tilt, 0, 0))
    return o


def barrel_intact(name):
    parts = [stave_set(name + "_staves", range(NS)),
             barrel_lid(name + "_lid0", 0.03, 0.06, barrel_r(0.045) - 0.022),
             barrel_lid(name + "_lid1", BR_H - 0.06, BR_H - 0.03, barrel_r(BR_H - 0.045) - 0.022),
             barrel_band(name + "_b0", 0.13), barrel_band(name + "_b1", BR_H - 0.13)]
    return finish(merge(parts, name), 30.0)


def barrel_damaged(name):
    idx = [i for i in range(NS) if i not in (3, 4)]
    parts = [stave_set(name + "_staves", idx, tops={2: (0.62, 0.05), 9: (0.46, 0.05), 10: (0.66, 0.04), 5: (0.74, 0.03)}, tilt={5: 0.05, 11: 0.03}),
             barrel_lid(name + "_lid0", 0.03, 0.06, barrel_r(0.045) - 0.022),
             barrel_band(name + "_b0", 0.13),
             barrel_band(name + "_b1", BR_H - 0.09, extra=0.02, tilt=math.radians(12))]
    return finish(merge(parts, name), 30.0)


def barrel_debris(name):
    holder = empty(name)
    pieces = []
    for q in range(4):
        idx = list(range(4 * q, 4 * q + 4))
        tops = {idx[1]: (0.6, 0.05)} if q % 2 == 0 else {idx[2]: (0.5, 0.06), idx[0]: (0.7, 0.04)}
        o = stave_set("Piece_%d" % q, idx, tops=tops)
        ac = TAU * (4 * q + 2) / NS
        finish(o, 30.0, (BR_R0 * 0.8 * math.cos(ac), BR_R0 * 0.8 * math.sin(ac), 0.0))
        pieces.append(o)
    for k, z in enumerate((0.13, BR_H - 0.13)):
        o = barrel_band("Piece_%d" % (4 + k), z, extra=0.006)
        finish(o, 30.0, (0.0, 0.0, z - 0.025))
        pieces.append(o)
    for p in pieces:
        C.parent(p, holder)
    return holder


# ----------------------------------------------------------------------------------------------------------------------
# ящик
# ----------------------------------------------------------------------------------------------------------------------
CR_S, CR_E, CR_T = 0.7, 0.08, 0.035


def crate_boards(name, damaged=False):
    """Список объектов ящика (рама, доски, раскосы, уголки, гвозди). damaged — сломан верхний передний левый угол
    (x<0, y<0 = лицо, z>0)."""
    S, e, t = CR_S, CR_E, CR_T
    h = S * 0.5
    c = h - e * 0.5
    inner = S - 2 * e
    pw = inner / 3.0
    parts = []
    k = [0]

    def add(size, loc, rot=(0, 0, 0), mat=None, broken=None, bev=0.006, grain=None):
        k[0] += 1
        o = board("%s_%d" % (name, k[0]), size, mat or M("WoodDark"), broken=broken)
        if bev:
            bevel_apply(o, bev)
        uv_board(o, grain or 'XYZ'[max(range(3), key=lambda i: size[i])])
        place(o, loc, rot)
        parts.append(o)
        return o

    def corner_broken(px, py, pz):
        return damaged and px < 0 and py < 0 and pz > 0

    # рама
    for y in (-c, c):
        for z in (-c, c):
            if corner_broken(-1, y, z):
                add((S - 0.2, e, e), (0.1, y, z + h), broken=(0, -1, 0.08))
            else:
                add((S, e, e), (0, y, z + h))
    for x in (-c, c):
        for z in (-c, c):
            if corner_broken(x, -1, z):
                add((e, S - 0.2, e), (x, 0.1, z + h), broken=(1, -1, 0.08))
            else:
                add((e, S, e), (x, 0, z + h))
    for x in (-c, c):
        for y in (-c, c):
            if corner_broken(x, y, 1):
                add((e, e, S - 0.22), (x, y, h - 0.11), broken=(2, 1, 0.08))
            else:
                add((e, e, S), (x, y, h))
    # доски граней (утоплены на 1.75 см внутрь рамы)
    for axis in range(3):
        for s in (-1, 1):
            lay = (axis + 1) % 3
            span = (axis + 2) % 3
            for i in range(3):
                off = -inner * 0.5 + pw * (i + 0.5)
                size = [0.0, 0.0, 0.0]
                size[axis] = t
                size[lay] = pw - 0.02
                size[span] = inner + 0.02
                pos = [0.0, 0.0, 0.0]
                pos[axis] = s * (h - t)
                pos[lay] = off
                pos[2] += h
                broken = None
                if damaged:
                    # верх (axis 2, s +1): доски лежат вдоль y, разложены по x; передняя-левая убрана, средняя сломана спереди
                    if axis == 2 and s > 0 and i == 0:
                        continue
                    if axis == 2 and s > 0 and i == 1:
                        size[span] -= 0.22
                        pos[span] += 0.11
                        broken = (span, -1, 0.07)
                    # лицо (axis 1, s −1): доски вдоль x, разложены по z; верхняя сломана слева
                    if axis == 1 and s < 0 and i == 2:
                        size[span] -= 0.24
                        pos[span] += 0.12
                        broken = (span, -1, 0.07)
                    # левая грань (axis 0, s −1): доски вдоль z, разложены по y; передняя сломана сверху
                    if axis == 0 and s < 0 and i == 0:
                        size[span] -= 0.2
                        pos[span] -= 0.1
                        broken = (span, 1, 0.07)
                add(tuple(size), tuple(pos), mat=M("Wood"), broken=broken, grain='XYZ'[span])
    # X-раскосы на 4 боковых гранях и сверху (0.02 толщиной поверх досок, вровень с рамой)
    L = inner * math.sqrt(2.0) - 0.06
    for axis, s, rot_axis in ((1, -1, 1), (1, 1, 1), (0, -1, 0), (0, 1, 0), (2, 1, 2)):
        for sgn in (-1, 1):
            size = [0.0, 0.0, 0.0]
            size[axis] = 0.02
            if axis == 1:
                size[0], size[2] = L, 0.065
                rot = (0, sgn * math.pi / 4, 0)
                grain = 'X'
            elif axis == 0:
                size[1], size[2] = L, 0.065
                rot = (sgn * math.pi / 4, 0, 0)
                grain = 'Y'
            else:
                size[0], size[1] = L, 0.065
                rot = (0, 0, sgn * math.pi / 4)
                grain = 'X'
            pos = [0.0, 0.0, h]
            pos[axis] += s * (h - 0.0075)
            broken = None
            if damaged and axis == 1 and s < 0 and sgn > 0:
                size[0] = L * 0.62
                broken = (0, -1, 0.06)
                shift = (L - size[0]) * 0.5
                pos[0] += shift * math.cos(math.pi / 4)
                pos[2] += shift * math.sin(math.pi / 4)
            add(tuple(size), tuple(pos), rot, mat=M("Wood"), broken=broken, bev=0.0, grain=grain)
            # гвозди на концах раскоса
            if broken is None:
                for end in (-1, 1):
                    d = (L * 0.5 - 0.05) * end
                    p = [0.0, 0.0, h]
                    if axis == 1:
                        p[0] += d * math.cos(sgn * math.pi / 4)
                        p[2] += -d * math.sin(sgn * math.pi / 4)
                        p[1] += s * (h + 0.004)
                        n = (0, s, 0)
                    elif axis == 0:
                        p[1] += d * math.cos(sgn * math.pi / 4)
                        p[2] += d * math.sin(sgn * math.pi / 4)
                        p[0] += s * (h + 0.004)
                        n = (s, 0, 0)
                    else:
                        p[0] += d * math.cos(sgn * math.pi / 4)
                        p[1] += d * math.sin(sgn * math.pi / 4)
                        p[2] += h + 0.004
                        n = (0, 0, 1)
                    parts.append(rivet("%s_nail%d" % (name, k[0] * 10 + end + 1), tuple(p), n, r=0.013, h=0.01))
    # железные уголки на 8 углах (3 пластины на угол)
    pl, th = 0.13, 0.008
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                if corner_broken(sx, sy, sz):
                    continue
                cx, cy, cz = sx * (h - pl * 0.5), sy * (h - pl * 0.5), sz * (h - pl * 0.5) + h
                add((th, pl, pl), (sx * (h + th * 0.5), cy, cz), mat=M("Iron"), bev=0.0)
                add((pl, th, pl), (cx, sy * (h + th * 0.5), cz), mat=M("Iron"), bev=0.0)
                add((pl, pl, th), (cx, cy, sz * (h + th * 0.5) + h), mat=M("Iron"), bev=0.0)
    if damaged:
        # тёмное нутро и щепки у пролома
        o = box(name + "_inner", (S - 0.1, S - 0.1, S - 0.1), M("Char"))
        place(o, (0, 0, h))
        parts.append(o)
        for i in range(4):
            b = Vector((-h + 0.16 + RNG.uniform(-0.03, 0.03), -h + 0.05 + RNG.uniform(0, 0.15), S - 0.03 - RNG.uniform(0, 0.12)))
            tip = b + Vector((-RNG.uniform(0.06, 0.13), -RNG.uniform(0.02, 0.08), RNG.uniform(0.03, 0.1)))
            parts.append(spike("%s_spike%d" % (name, i), b, tip, 0.012, M("Wood")))
    return parts


def crate_intact(name):
    return finish(merge(crate_boards(name), name), 30.0)


def crate_damaged(name):
    return finish(merge(crate_boards(name, damaged=True), name), 30.0)


def crate_debris(name):
    holder = empty(name)
    S, e, t = CR_S, CR_E, CR_T
    h = S * 0.5
    specs = [
        ((S, e, e), (0, -h + e * 0.5, S - e * 0.5), (0, 0, 0), (0, 1, 0.07)),
        ((e, e, S * 0.8), (h - e * 0.5, h - e * 0.5, S * 0.4), (0, 0, 0.3), None),
        ((0.56, 0.16, t), (0.0, -0.12, S - t * 0.5 - 0.02), (0, 0, 0), None),
        ((0.5, 0.16, t), (-0.18, 0.08, h), (0.0, 0.0, 0.5), (0, -1, 0.06)),
        ((t, 0.16, 0.56), (-h + t * 0.5 + 0.02, 0.1, h), (0, 0, 0), (2, 1, 0.06)),
        ((0.56, t, 0.16), (0.1, h - t * 0.5 - 0.02, 0.5), (0, 0.2, 0), None),
    ]
    for i, (size, loc, rot, broken) in enumerate(specs):
        mat = M("WoodDark") if max(size) == S else M("Wood")
        o = board("Piece_%d" % i, size, mat, broken=broken)
        bevel_apply(o, 0.006)
        uv_board(o, 'XYZ'[max(range(3), key=lambda k: size[k])])
        place(o, loc, rot)
        finish(o, 30.0, (loc[0], loc[1], loc[2] - min(size) * 0.5))
        C.parent(o, holder)
    return holder


# ----------------------------------------------------------------------------------------------------------------------
# мост и палубы
# ----------------------------------------------------------------------------------------------------------------------
def post(name, height, windings):
    parts = [lathe(name + "_shaft", [(0, 0), (0.15, 0), (0.15, height - 0.03), (0.12, height), (0, height)], 16, M("WoodDark"))]
    C.uv_cylinder_along(parts[0], 'Z', 1.0, around=3.0)
    for z0, turns in windings:
        parts.append(helix_tube("%s_rope%d" % (name, int(z0 * 100)), 0.15 + 0.017, 0.02, z0, turns, 0.043, M("Rope")))
    cap = ring(name + "_cap", 0.148, 0.165, height - 0.16, height - 0.09, 16, M("Iron"))
    C.uv_cylinder_along(cap, 'Z', 1.0)
    parts.append(cap)
    top = lathe(name + "_top", [(0, height - 0.005), (0.16, height - 0.005), (0.16, height + 0.012), (0, height + 0.012)], 16, M("Iron"))
    C.uv_box(top, 1.0)
    parts.append(top)
    for k in range(6):
        a = TAU * (k + 0.5) / 6
        parts.append(rivet("%s_riv%d" % (name, k), (0.165 * math.cos(a), 0.165 * math.sin(a), height - 0.125), (math.cos(a), math.sin(a), 0)))
    return finish(merge(parts, name), 35.0)


def plank(name):
    o = board(name, (0.25, 0.9, 0.05), M("Wood"), jitter=0.002)
    bevel_apply(o, 0.006)
    uv_board(o, 'Y')
    place(o, (0, 0, 0.025))
    for i, y in enumerate((-0.38, 0.38)):
        bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=0.022, depth=0.4, location=(0, y, 0.025), rotation=(0, math.pi / 2, 0))
        cutter = bpy.context.active_object
        m = o.modifiers.new("Hole%d" % i, 'BOOLEAN')
        m.operation = 'DIFFERENCE'
        m.object = cutter
        bpy.ops.object.select_all(action='DESELECT')
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.modifier_apply(modifier=m.name)
        bpy.data.objects.remove(cutter, do_unlink=True)
    return finish(o, 30.0)


def rope_segment(name, length=0.3):
    bpy.ops.mesh.primitive_cylinder_add(vertices=10, radius=0.02, depth=length, location=(length * 0.5, 0, 0), rotation=(0, math.pi / 2, 0))
    o = bpy.context.active_object
    o.name = name
    C.apply_transforms(o, location=True, rotation=True)
    C.uv_cylinder_along(o, 'X', 4.0, around=1.0)
    o.data.materials.append(M("Rope"))
    return finish(o, 40.0)


def beam(name, length):
    o = board(name, (length, 0.2, 0.2), M("WoodDark"), jitter=0.003)
    bevel_apply(o, 0.012)
    C.uv_box(o, 1.0, 'X')
    place(o, (0, 0, 0.1))
    return finish(o, 30.0)


def deck(name, length, depth=1.8):
    parts = []
    for y in (-0.65, 0.65):
        b = board("%s_beam%d" % (name, int(y > 0)), (length, 0.2, 0.2), M("WoodDark"), jitter=0.003)
        bevel_apply(b, 0.012)
        C.uv_box(b, 1.0, 'X')
        place(b, (0, y, 0.1))
        parts.append(b)
    n = int(round(length / 0.25))
    for i in range(n):
        x = -length * 0.5 + 0.25 * (i + 0.5)
        p = board("%s_p%d" % (name, i), (0.238, depth + RNG.uniform(-0.03, 0.03), 0.05), M("Wood"), jitter=0.002)
        bevel_apply(p, 0.006)
        uv_board(p, 'Y')
        uv_offset(p, 0.25 * RNG.randrange(4), RNG.uniform(0, 1))
        place(p, (x, RNG.uniform(-0.01, 0.01), 0.225))
        parts.append(p)
    return finish(merge(parts, name), 30.0)


# ----------------------------------------------------------------------------------------------------------------------
# знамя
# ----------------------------------------------------------------------------------------------------------------------
def banner_cloth(name, mat_name, decal_tint, phase):
    w, h, nx, nz = 1.2, 1.8, 12, 18
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    grid = []
    holes = {(1, 17), (6, 17), (9, 17), (3, 15)}
    for j in range(nz + 1):
        row = []
        for i in range(nx + 1):
            x = -w * 0.5 + w * i / nx
            z = -h * j / nz
            amp = 0.045 * (j / nz) ** 0.8
            y = -0.085 + amp * math.sin(TAU * z / 1.25 + x * 2.4 + phase) + 0.012 * (j / nz) * math.sin(x * 9.0 + phase)
            if j == nz:
                z += (0.11 if i % 2 == 1 else 0.0) + RNG.uniform(-0.03, 0.03)
            elif j > 0 and (i == 0 or i == nx):
                z += RNG.uniform(-0.01, 0.01)
            row.append(bm.verts.new((x, y, z)))
        grid.append(row)
    faces = {}
    for j in range(nz):
        for i in range(nx):
            if (i, j) in holes:
                continue
            f = bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
            f.material_index = 0
            faces[(i, j)] = f
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    if sum(f.normal.y for f in bm.faces) > 0.0:
        bmesh.ops.reverse_faces(bm, faces=list(bm.faces))
    bm.normal_update()
    for f in bm.faces:
        for l in f.loops:
            l[uvl].uv = (l.vert.co.x + 0.6, -l.vert.co.z)
    # декаль-корона: копия граней центрального квадрата 0.6×0.6 (i 3..8, j 5..10), вынесена на 6 мм по нормали
    dec = []
    vmap = {}
    for j in range(5, 11):
        for i in range(3, 9):
            f = faces.get((i, j))
            if f is None:
                continue
            vs = []
            for v in f.verts:
                if v not in vmap:
                    vmap[v] = bm.verts.new(v.co + v.normal * 0.006)
                vs.append(vmap[v])
            nf = bm.faces.new(vs)
            nf.material_index = 1
            dec.append(nf)
    for f in dec:
        for l in f.loops:
            co = l.vert.co
            l[uvl].uv = ((co.x + 0.3) / 0.6, (co.z + 1.1) / 0.6)
    o = mesh_obj(name, bm, [M(mat_name), decal_material(name + "_Crown", decal_tint)])
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def banner(name):
    pole = lathe(name + "_pole", [(0.035, 0.0), (0.035, 3.0)], 12, M("WoodDark"))
    C.uv_cylinder_along(pole, 'Z', 1.0, around=1.0)
    finial = lathe(name + "_finial", [(0, 3.0), (0.055, 3.03), (0.065, 3.09), (0.045, 3.15), (0.02, 3.17), (0.02, 3.22), (0, 3.28)], 12, M("Gold"))
    C.uv_box(finial, 1.0)
    bar = board(name + "_bar", (1.45, 0.06, 0.06), M("WoodDark"), jitter=0.002)
    bevel_apply(bar, 0.006)
    C.uv_box(bar, 1.0, 'X')
    place(bar, (0, -0.045, 2.86))
    knot = ring(name + "_knot", 0.03, 0.05, 2.80, 2.92, 12, M("Rope"))
    C.uv_cylinder_along(knot, 'Z', 4.0, around=1.0)
    root = finish(merge([pole, finial, bar, knot], name), 35.0)
    for idx, (cname, mat, tint) in enumerate((("Cloth_Red", "Cloth_Red", None), ("Cloth_Blue", "Cloth_Blue", None), ("Cloth_White", "Cloth_White", (0.30, 0.26, 0.24, 1.0)))):
        cloth = banner_cloth(cname, mat, tint, idx * 1.7)
        cloth.location = (0, 0, 2.86)
        C.parent(cloth, root)
    return root


# ----------------------------------------------------------------------------------------------------------------------
# ворота
# ----------------------------------------------------------------------------------------------------------------------
G_OPEN, G_PIER, G_DEPTH, G_H, G_THICK, G_SPRING = 3.0, 1.0, 0.8, 3.2, 0.3, 1.4


def stone_courses(name, x0, x1, z0, z1, depth, rows, skip=None, mat="Stone", gap=0.02):
    """Ряды блоков 0.5×0.25 (перевязка полублоками), каждый блок вписан в блок текстуры. skip(a,b,zb,zt) → True — пропуск."""
    parts = []
    z = z0
    r = 0
    while z < z1 - 1e-6:
        hgt = min(rows[min(r, len(rows) - 1)], z1 - z)
        xs = [x0]
        x = x0 + (0.25 if r % 2 else 0.5)
        while x < x1 - 0.12:
            xs.append(x)
            x += 0.5
        xs.append(x1)
        for i in range(len(xs) - 1):
            a, b = xs[i], xs[i + 1]
            if skip and skip(a, b, z, z + hgt):
                continue
            inset = RNG.uniform(0.0, 0.03)
            o = box("%s_%d_%d" % (name, r, i), (b - a - gap, depth - inset, hgt - gap), M(mat), jitter=0.005)
            uv_fit(o, 1.0)
            place(o, ((a + b) * 0.5, 0.0, z + hgt * 0.5))
            parts.append(o)
        z += hgt
        r += 1
    return parts


def gate_arch(name):
    r_in = G_OPEN * 0.5
    r_out = r_in + G_THICK
    half = r_in + G_PIER
    parts = []
    rows = [0.25]

    def into_opening(a, b, zb, zt):
        px = min(max(0.0, a), b)
        pz = min(max(G_SPRING, zb), zt)
        return math.hypot(px, pz - G_SPRING) < r_in + 0.08

    for s in (-1, 1):
        a, b = (-half, -r_in) if s < 0 else (r_in, half)
        parts += stone_courses("%s_p%d" % (name, s + 1), a, b, 0.0, G_SPRING, G_DEPTH, rows)
        core = box("%s_core%d" % (name, s + 1), (G_PIER - 0.04, G_DEPTH - 0.12, G_SPRING + 0.2), M("Mortar"))
        place(core, ((a + b) * 0.5, 0, (G_SPRING + 0.2) * 0.5))
        parts.append(core)
    # над пятой — кладка на всю ширину (за клиньями), без блоков, лезущих в проём
    parts += stone_courses(name + "_s", -half, half, G_SPRING, G_H, G_DEPTH - 0.06, [0.25, 0.25, 0.25, 0.25, 0.25, 0.25, 0.25, 0.3], skip=into_opening)
    # клинья свода (ширина по внешней дуге: у пяты клинья перекрываются, снаружи щелей нет)
    nv = 13
    rm = r_in + G_THICK * 0.5
    for k in range(nv):
        t0, t1 = math.pi * k / nv, math.pi * (k + 1) / nv
        tm = 0.5 * (t0 + t1)
        arc = r_out * (t1 - t0) * 1.02 - 0.012
        key = k == nv // 2
        size = (arc + (0.04 if key else 0.0), G_DEPTH + 0.05, G_THICK + (0.12 if key else 0.0))
        o = box("%s_v%d" % (name, k), size, M("Stone"), jitter=0.004)
        uv_fit(o, 1.0)
        place(o, (rm * math.cos(tm), 0.0, G_SPRING + rm * math.sin(tm) + (0.03 if key else 0.0)), (0.0, -(tm - math.pi * 0.5), 0.0))
        parts.append(o)
    # тёмная подложка за клиньями (видна только в щелях)
    bm = bmesh.new()
    segs = 20
    ri, ro = r_in + 0.03, r_out + 0.9

    def clampv(x, z):
        return (max(-half + 0.03, min(half - 0.03, x)), min(z, G_H - 0.03))

    inner = [bm.verts.new((*clampv(ri * math.cos(math.pi * i / segs), G_SPRING + ri * math.sin(math.pi * i / segs))[:1], y, clampv(0.0, G_SPRING + ri * math.sin(math.pi * i / segs))[1])) for i in range(segs + 1) for y in (-0.33, 0.33)]
    outer = [bm.verts.new((*clampv(ro * math.cos(math.pi * i / segs), G_SPRING + ro * math.sin(math.pi * i / segs))[:1], y, clampv(0.0, G_SPRING + ro * math.sin(math.pi * i / segs))[1])) for i in range(segs + 1) for y in (-0.33, 0.33)]
    for i in range(segs):
        for side in range(2):
            a, b = inner[2 * i + side], inner[2 * (i + 1) + side]
            c_, d = outer[2 * (i + 1) + side], outer[2 * i + side]
            bm.faces.new((a, b, c_, d))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    parts.append(mesh_obj(name + "_back", bm, [M("Mortar")]))
    # разрушенный верх: россыпь блоков
    for (x, z, sx, sz, rz) in ((-2.05, G_H, 0.5, 0.3, 0.1), (-1.35, G_H, 0.45, 0.22, -0.15), (1.7, G_H, 0.55, 0.28, 0.08), (2.3, G_H, 0.35, 0.2, 0.3), (0.55, G_H + 0.05, 0.4, 0.22, -0.2)):
        o = box("%s_top%d" % (name, int(x * 10)), (sx, 0.5 + RNG.uniform(-0.1, 0.1), sz), M("Stone"), jitter=0.01)
        uv_fit(o, 1.0)
        place(o, (x, RNG.uniform(-0.1, 0.1), z + sz * 0.5), (0, 0, rz))
        parts.append(o)
    # плющ: пряди с листьями по лицевой стороне
    for (x, z0, length, drift) in ((-2.25, G_H + 0.2, 1.7, 0.15), (-0.95, G_H + 0.1, 1.1, -0.2), (1.35, G_H + 0.15, 2.0, 0.2), (2.35, G_H + 0.2, 1.3, -0.1), (2.45, 0.0, -1.4, -0.15), (-1.65, G_SPRING + 1.3, 1.3, 0.25)):
        parts.append(ivy_strand("%s_ivy%d" % (name, int(x * 100) + int(z0 * 10)), x, z0, length, drift, -G_DEPTH * 0.5 - 0.06))
    return finish(merge(parts, name), 30.0)


def ivy_strand(name, x, z0, length, drift, y, step=0.085):
    """Прядь плюща: стебель (лента) + листья-ромбы, вниз (length>0) или вверх (length<0) вдоль лицевой плоскости y."""
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    n = int(abs(length) / step)
    sgn = -1.0 if length > 0 else 1.0
    pts = []
    for i in range(n + 1):
        t = i / max(n, 1)
        pts.append(Vector((x + drift * math.sin(t * 3.1) + 0.05 * math.sin(t * 17.0), y - 0.004 * (i % 3), z0 + sgn * step * i)))
    for a, b in zip(pts, pts[1:]):
        side = Vector((0.01, 0, 0))
        f = bm.faces.new((bm.verts.new(a - side), bm.verts.new(a + side), bm.verts.new(b + side), bm.verts.new(b - side)))
        f.material_index = 1
    for i, p in enumerate(pts[1:], 1):
        ang = RNG.uniform(-0.6, 0.6) + (0.9 if i % 2 else -0.9)
        sz = RNG.uniform(0.06, 0.1)
        c = p + Vector((math.cos(ang) * sz * 0.7, -0.01, math.sin(ang) * sz * 0.7))
        d1 = Vector((math.cos(ang), 0, math.sin(ang))) * sz
        d2 = Vector((-math.sin(ang), 0, math.cos(ang))) * sz * 0.55
        f = bm.faces.new((bm.verts.new(c - d1), bm.verts.new(c - d2 + Vector((0, -0.015, 0))), bm.verts.new(c + d1), bm.verts.new(c + d2 + Vector((0, -0.015, 0)))))
        f.material_index = 0 if i % 3 else 1
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        for l in f.loops:
            l[uvl].uv = (l.vert.co.x, l.vert.co.z)
    return mesh_obj(name, bm, [M("Leaf"), M("LeafDark")])


def gate_door(name, side):
    """Створка: side=−1 левая (петля в x=0, полотно в +X), side=+1 правая (полотно в −X). Верх по дуге свода."""
    r_in = G_OPEN * 0.5
    n = 7
    pitch = r_in / n
    w = pitch - 0.012
    t = 0.08
    parts = []

    def ztop(x_arch):
        return G_SPRING + math.sqrt(max(r_in * r_in - x_arch * x_arch, 0.0)) - 0.03

    for i in range(n):
        xa = i * pitch + 0.006
        xb = xa + w
        xl0, xl1 = (xa, xb) if side < 0 else (-xb, -xa)
        za, zb = ztop(-r_in + xa) if side < 0 else ztop(r_in - xa), ztop(-r_in + xb) if side < 0 else ztop(r_in - xb)
        bm = bmesh.new()
        uvl = bm.loops.layers.uv.new("UVMap")
        z0 = 0.03
        vs = {}
        for xi, xx in ((0, xl0), (1, xl1)):
            zt = (za if xi == 0 else zb) if side < 0 else (zb if xi == 0 else za)
            for yi, yy in ((0, -t * 0.5), (1, t * 0.5)):
                vs[(xi, yi, 0)] = bm.verts.new((xx, yy, z0))
                vs[(xi, yi, 1)] = bm.verts.new((xx, yy, zt))
        quads = [((0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1)), ((1, 1, 0), (0, 1, 0), (0, 1, 1), (1, 1, 1)),
                 ((0, 1, 0), (0, 0, 0), (0, 0, 1), (0, 1, 1)), ((1, 0, 0), (1, 1, 0), (1, 1, 1), (1, 0, 1)),
                 ((0, 0, 0), (0, 1, 0), (1, 1, 0), (1, 0, 0)), ((0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1))]
        for q in quads:
            bm.faces.new([vs[k] for k in q])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        s = 0.25 / pitch
        for f in bm.faces:
            for l in f.loops:
                co = l.vert.co
                if abs(f.normal.y) > 0.5:
                    l[uvl].uv = (co.x * s, co.z)
                elif abs(f.normal.x) > 0.5:
                    l[uvl].uv = (0.1 + co.y * s, co.z)
                else:
                    l[uvl].uv = (co.x * s, 0.1 + co.y)
        o = mesh_obj("%s_pl%d" % (name, i), bm, [M("WoodDark")])
        bevel_apply(o, 0.006)
        parts.append(o)
    # тёмная подкладка за досками (щели не просвечивают)
    back = box(name + "_back", (r_in - 0.02, 0.02, ztop(0.0) - 0.06), M("Char"))
    C.uv_box(back, 1.0)
    place(back, (-side * (r_in * 0.5 - 0.005), t * 0.5 + 0.005, ztop(0.0) * 0.5))
    parts.append(back)
    # железные полосы с заклёпками (лицевая сторона −Y)
    for bi, z in enumerate((0.45, 1.35, 2.2)):
        xmax = r_in if z <= G_SPRING else math.sqrt(max(r_in * r_in - (z - G_SPRING) ** 2, 0.0)) - 0.02
        L = xmax - 0.04
        b = box("%s_band%d" % (name, bi), (L, 0.025, 0.14), M("Iron"), jitter=0.002)
        C.uv_box(b, 1.0, 'X')
        place(b, (-side * (L * 0.5 + 0.02), -t * 0.5 - 0.0125, z))
        parts.append(b)
        nr = max(3, int(L / 0.22))
        for k in range(nr):
            xk = -side * (0.06 + (L - 0.12) * k / max(nr - 1, 1))
            parts.append(rivet("%s_riv%d_%d" % (name, bi, k), (xk, -t * 0.5 - 0.025 - 0.005, z), (0, -1, 0), r=0.016, h=0.012))
    if side > 0:
        plate = box(name + "_plate", (0.14, 0.02, 0.16), M("Iron"))
        C.uv_box(plate, 1.0)
        place(plate, (-1.2, -t * 0.5 - 0.01, 1.62))
        pin = rivet(name + "_pin", (-1.2, -t * 0.5 - 0.03, 1.62), (0, -1, 0), r=0.02, h=0.03)
        knocker = C.add_torus(name + "_ring", 0.095, 0.015, loc=(-1.2, -t * 0.5 - 0.045, 1.62 - 0.1), rot=(math.pi * 0.5, 0, 0), segs=20, ring=8)
        knocker.data.materials.append(M("Iron"))
        C.apply_transforms(knocker, location=True, rotation=True)
        C.uv_box(knocker, 1.0)
        parts += [plate, pin, knocker]
    return finish(merge(parts, name), 30.0)


# ----------------------------------------------------------------------------------------------------------------------
# камень
# ----------------------------------------------------------------------------------------------------------------------
def wall_segment(name, width=2.0, height=3.0, depth=0.8):
    skin = box(name + "_skin", (width, depth - 0.04, height), M("Stone"), jitter=0.0)
    skin.data.materials.append(M("Mortar"))
    for p in skin.data.polygons:
        if p.normal.y < -0.5:
            p.material_index = 1
    C.uv_box(skin, 1.0, 'Z')
    place(skin, (0, 0, height * 0.5))
    parts = [skin]
    face = -depth * 0.5
    r = 0
    z = 0.0
    while z < height - 1e-6:
        xs = [-width * 0.5]
        x = -width * 0.5 + (0.25 if r % 2 else 0.5)
        while x < width * 0.5 - 0.12:
            xs.append(x)
            x += 0.5
        xs.append(width * 0.5)
        for i in range(len(xs) - 1):
            a, b = xs[i] + 0.01, xs[i + 1] - 0.01
            d = RNG.uniform(0.0, 0.03)
            parts.append(relief_tile("%s_t%d_%d" % (name, r, i), a, b, z + 0.01, z + 0.24, face + 0.03, face - d, '-Y', 0.014, M("Stone")))
        z += 0.25
        r += 1
    return finish(merge(parts, name), 30.0)


def stone_platform(name, length, depth=2.0):
    base = box(name + "_base", (length, depth, 0.34), M("Stone_Grey"))
    base.data.materials.append(M("Mortar"))
    for p in base.data.polygons:
        if p.normal.z > 0.5:
            p.material_index = 1
    C.uv_box(base, 1.0, 'Z')
    place(base, (0, 0, 0.17))
    parts = [base]
    ys = [-depth * 0.5, -0.32 + RNG.uniform(-0.06, 0.06), 0.34 + RNG.uniform(-0.06, 0.06), depth * 0.5]
    nx = max(2, int(round(length / 0.62)))
    xs = [-length * 0.5 + length * i / nx + (RNG.uniform(-0.06, 0.06) if 0 < i < nx else 0.0) for i in range(nx + 1)]
    for i in range(nx):
        for j in range(3):
            if RNG.random() < 0.08 and 0 < i < nx - 1:
                continue
            h = RNG.uniform(0.05, 0.075)
            parts.append(relief_tile("%s_t%d_%d" % (name, i, j), xs[i] + 0.015, xs[i + 1] - 0.015, ys[j] + 0.015, ys[j + 1] - 0.015, 0.33, 0.34 + h, '+Z', 0.016, M("Stone_Grey")))
    return finish(merge(parts, name), 30.0)


def stone_block(name):
    o = box(name, (0.5, 0.5, 0.5), M("Stone"), jitter=0.012)
    uv_fit(o, 1.0)
    bevel_apply(o, 0.025, 2)
    place(o, (0, 0, 0.25))
    return finish(o, 30.0)


# ----------------------------------------------------------------------------------------------------------------------
# факел, клетка, цепь
# ----------------------------------------------------------------------------------------------------------------------
def torch(name):
    plate = box(name + "_plate", (0.14, 0.03, 0.26), M("Iron"))
    C.uv_box(plate, 1.0)
    place(plate, (0, 0.285, 0.30))
    arm = box(name + "_arm", (0.04, 0.27, 0.04), M("Iron"))
    C.uv_box(arm, 1.0)
    place(arm, (0, 0.15, 0.30))
    holder = C.add_torus(name + "_holder", 0.05, 0.012, loc=(0, 0, 0.30), segs=20, ring=8)
    holder.data.materials.append(M("Iron"))
    C.apply_transforms(holder, location=True)
    C.uv_box(holder, 1.0)
    stick = lathe(name + "_stick", [(0.028, 0.0), (0.028, 0.05), (0.03, 0.75), (0.035, 0.85)], 10, M("WoodDark"))
    C.uv_cylinder_along(stick, 'Z', 1.0, around=1.0)
    head = lathe(name + "_head", [(0.03, 0.78), (0.062, 0.86), (0.06, 0.98), (0.03, 1.02)], 12, M("Char"))
    C.uv_box(head, 1.0)
    wrap = helix_tube(name + "_wrap", 0.058, 0.012, 0.87, 3, 0.03, M("Rope"), 12, 5)
    root = finish(merge([plate, arm, holder, stick, head, wrap], name), 40.0)
    flame = lathe("Flame", [(0, 0.0), (0.085, 0.08), (0.105, 0.18), (0.06, 0.36), (0, 0.52)], 12, M("Flame"))
    C.uv_box(flame, 1.0)
    smooth(flame, 60.0)
    flame.location = (0, 0, 0.95)
    C.parent(flame, root)
    return root


def cage(name):
    r, h = 0.4, 1.4
    parts = [lathe(name + "_floor", [(0, 0), (r, 0), (r, 0.05), (0, 0.05)], 24, M("Iron"))]
    for i, (z0, z1) in enumerate([(0.05, 0.10), (h * 0.5 - 0.025, h * 0.5 + 0.025), (h - 0.05, h)]):
        parts.append(ring("%s_ring%d" % (name, i), r - 0.035, r + 0.005, z0, z1, 28, M("Iron")))
    for i in range(12):
        a = TAU * i / 12
        b = lathe("%s_bar%d" % (name, i), [(0.018, 0.05), (0.018, h)], 6, M("Iron"))
        place(b, (math.cos(a) * (r - 0.02), math.sin(a) * (r - 0.02), 0.0))
        parts.append(b)
    parts.append(lathe(name + "_dome", [(r, h), (r * 0.8, h + 0.1), (r * 0.5, h + 0.2), (0.06, h + 0.27), (0.06, h + 0.31), (0, h + 0.31)], 24, M("Iron"), close_bottom=False))
    parts.append(lathe(name + "_stem", [(0.02, h + 0.3), (0.02, h + 0.36)], 8, M("Iron")))
    hook = C.add_torus(name + "_hook", 0.05, 0.014, loc=(0, 0, h + 0.36 + 0.05), rot=(math.pi * 0.5, 0, 0), segs=20, ring=8)
    hook.data.materials.append(M("Iron"))
    C.apply_transforms(hook, location=True, rotation=True)
    for p in parts + [hook]:
        C.uv_box(p, 1.0)
    return finish(merge(parts + [hook], name), 40.0)


def chain_link(name):
    t = C.add_torus(name, 0.05, 0.022, segs=16, ring=8)
    t.data.materials.append(M("Iron"))
    C.apply_transforms(t)
    for v in t.data.vertices:
        v.co.y += 0.05 if v.co.y > 0.0 else -0.05
    t.rotation_euler = (math.pi * 0.5, 0, 0)
    C.apply_transforms(t, rotation=True)
    for v in t.data.vertices:
        v.co.z += 0.122
    C.uv_box(t, 1.0)
    return finish(t, 40.0)


# ----------------------------------------------------------------------------------------------------------------------
# сборка
# ----------------------------------------------------------------------------------------------------------------------
def family(builders):
    """Несколько корневых объектов в одном glb: [(имя, builder)]."""
    def build(_name):
        return [b(n) for n, b in builders]
    return build


MODULES = [
    ("Barrel", family([("Intact", barrel_intact), ("Damaged", barrel_damaged), ("Destroyed", barrel_debris)])),
    ("Crate", family([("Intact", crate_intact), ("Damaged", crate_damaged), ("Destroyed", crate_debris)])),
    ("Post", lambda n: post(n, 1.6, ((0.32, 3), (1.18, 5)))),
    ("Post_2m", lambda n: post(n, 2.0, ((1.55, 5),))),
    ("Plank", plank),
    ("Rope_Segment", rope_segment),
    ("Beam_3m", lambda n: beam(n, 3.0)),
    ("Deck_3m", lambda n: deck(n, 3.0)),
    ("Deck_4m", lambda n: deck(n, 4.0)),
    ("Banner", banner),
    ("Gate_Arch", gate_arch),
    ("Gate_Door_L", lambda n: gate_door(n, -1)),
    ("Gate_Door_R", lambda n: gate_door(n, 1)),
    ("Wall_Segment", wall_segment),
    ("Stone_Platform_2m", lambda n: stone_platform(n, 2.0)),
    ("Stone_Platform_4m", lambda n: stone_platform(n, 4.0)),
    ("Stone_Platform_5m", lambda n: stone_platform(n, 5.0)),
    ("Stone_Block", stone_block),
    ("Torch", torch),
    ("Cage", cage),
    ("Chain_Link", chain_link),
]


def export(path, objects):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:
        o.select_set(True)
        for c in o.children_recursive:
            c.select_set(True)
    kw = dict(filepath=path, export_format='GLB', use_selection=True, export_apply=True, export_yup=True,
              export_materials='EXPORT', export_normals=True, export_texcoords=True, export_animations=False,
              export_skins=False, export_cameras=False, export_lights=False, export_image_format=IMG_FORMAT)
    if IMG_FORMAT in ('WEBP', 'JPEG'):
        kw['export_image_quality'] = 88
    bpy.ops.export_scene.gltf(**kw)


def main():
    C.reset_scene()
    os.makedirs(OUT, exist_ok=True)
    only = C.args_after_dashdash()
    report = []
    for name, build in MODULES:
        if only and name not in only:
            continue
        roots = build(name)
        if not isinstance(roots, list):
            roots = [roots]
        if len(roots) == 1:
            roots[0].name = name
        worst = 0
        for r in roots:
            worst = max(worst, tri_count(r) if r.type == 'MESH' else max(tri_count(c) for c in r.children))
        path = os.path.join(OUT, name + ".glb")
        export(path, roots)
        report.append((name, worst, os.path.getsize(path)))
        for r in roots:
            for c in list(r.children_recursive):
                bpy.data.objects.remove(c, do_unlink=True)
            bpy.data.objects.remove(r, do_unlink=True)
    bad = [r for r in report if r[1] > TRI_BUDGET]
    print("MODULE                 TRIS(max obj)   BYTES")
    for name, tris, size in report:
        print("%-22s %8d %10d%s" % (name, tris, size, "  OVER BUDGET" if tris > TRI_BUDGET else ""))
    if bad:
        print("ERROR: over budget:", [b[0] for b in bad])
        sys.exit(1)


main()
