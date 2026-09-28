#!/usr/bin/env python3
"""Модульный набор арены «Руины» (референс docs/refs/R15-a-arena-ruins-concept.jpg) — настоящие меши Blender.

Запуск моделей (Blender 4.5 LTS, headless):
    /Applications/Blender.app/Contents/MacOS/Blender -b --python godot/tools/blender/arena_kit.py
    → godot/assets/models/arena/<Module>.glb (один модуль = один glb, origin в центре основания, Y вверх в Godot)
    → godot/assets/textures/kit/kit_stone.jpg, kit_wood.jpg (запечённые бесшовные альбедо, они же вшиты в glb)

Запуск фона (системный python3 + Pillow, без Blender):
    python3 godot/tools/blender/arena_kit.py --crop-backdrop
    → godot/assets/textures/bg_ruins.jpg (R15 без текстовых плашек: срезаны верх 215 px и нижняя чёрная полоса)

Соглашения (docs/plan-demo/ASSET_PIPELINE.md, common.py): метры; Blender Z вверх, X вбок, «лицо» модуля в −Y
(после экспорта — +Z в Godot, к камере); материалы Principled BSDF, цвет = запечённая текстура × тинт
(экспортируется как baseColorFactor); фаски Bevel, сглаживание по углу; бюджет ≤ 2000 треугольников на модуль.

Модули (размеры Ш×Г×В в метрах, origin — центр основания):
    Stone_Block_A/B/C   0.5×0.5×0.5, грубые блоки, 3 варианта тинта камня
    Stone_Slab_2m/4m/5m 2/4/5 × 2 × 0.4, плиты-«flagstone» (верх разбит на плитки со швами)
    Stone_Wall_2x3      2×0.8×3, стена с рядами блоков (перевязка, случайная глубина блока, тёмный раствор)
    Stone_Wall_1x3      1×0.8×3, Stone_Wall_2x1 2×0.8×1 — доборные
    Stone_Top_2m        2×0.8×0.5, разрушенный верхний ряд (зубцы)
    Arch_3m             проём 3 м, всего 5×0.8×3.2, клинчатая арка + пилоны + заполнение пазух (верх плоский)
    Arch_1_5m           проём 1.5 м, всего 3×0.8×2.4
    Plank_2m/3m         0.25×0.05, доски вдоль X;  Beam_3m/4m 0.2×0.2 балки;  Post_2m столб 0.2 с раскосами
    Banner              древко 3 м + перекладина + полотнище 1.2×1.8 (волна в меше, рваный низ, корона = вставка
                        из граней с материалом Emblem); полотнище — дочерний объект Banner_Cloth, origin у перекладины
    Torch               кронштейн (плита у стены в +Y на 0.3 м) + факел + пламя (Flame, эмиссия); пламя на z≈1.1
    Cage                клетка ⌀0.8×1.4 из прутьев, обручи, купол, крюк (верх крюка z≈1.75)
    Barrel              бочка ⌀0.62×0.8 с двумя обручами;  Crate ящик 0.7 (рама + доски);  Chain_Link звено 0.24
    Stone_Cliff_2x3     как Stone_Wall_2x3, но тёмный камень (фундамент под землёй)
    Bush, Grass_Tuft    низкополигональные куст (icosphere-ы) и пучок травы (12 изогнутых лент) — «заросшие руины»
Материалы: Stone_A/B/C/Dark, Mortar, Wood, WoodDark, Iron, Cloth, Emblem, Flame, Char, Leaf, LeafDark.
Фон: bg_ruins.jpg = R15 без плашек + сверху продлённое небо (растянутая размытая верхняя полоса → SKY_TOP).
"""
import math
import os
import random
import sys

try:
    import bpy
    import bmesh
    from mathutils import Vector
except ImportError:  # системный python: только обрезка фона
    bpy = None

HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(GODOT, "assets", "models", "arena")
TEX = os.path.join(GODOT, "assets", "textures")
REF = os.path.abspath(os.path.join(GODOT, "..", "docs", "refs", "R15-a-arena-ruins-concept.jpg"))
TRI_BUDGET = 2000

# Обрезка R15: верх 215 px (плашка названия слева и слоган справа), низ 53 px (чёрная полоса с подписями).
CROP_TOP = 215
CROP_BOTTOM = 53
GROUND_PX = 595          # линия земли на исходной картинке (px от верха), 1915 px = 30 м


SKY_EXT_PX = 215         # продление неба сверху: растянутая размытая верхняя полоса, уходящая в SKY_TOP
SKY_TOP = (102, 135, 194)  # = builder SKY_TOP (0.40, 0.53, 0.76)


def crop_backdrop():
    from PIL import Image
    im = Image.open(REF).convert("RGB")
    w, h = im.size
    body = im.crop((0, CROP_TOP, w, h - CROP_BOTTOM))
    # продление: градиент от дымки у горизонта (средний цвет чистого неба верхних рядов) к SKY_TOP;
    # верхние FOG_PX рядов самой картинки растворяются в дымке (как далёкий туман) — шва нет
    px = body.load()
    sky_cols = [x for x in range(w) if sum(px[x, 1]) > 3 * 150]     # светлые (небо/облака), не башни
    haze = tuple(int(sum(px[x, 1][i] for x in sky_cols) / max(1, len(sky_cols))) for i in range(3))
    ext = Image.new("RGB", (w, SKY_EXT_PX))
    ep = ext.load()
    for y in range(SKY_EXT_PX):
        t = y / (SKY_EXT_PX - 1)          # 0 сверху → 1 у картинки
        col = tuple(int(SKY_TOP[i] * (1 - t) + haze[i] * t) for i in range(3))
        for x in range(w):
            ep[x, y] = col
    fog_px = 90
    for y in range(fog_px):
        t = y / fog_px                    # 0 у верхнего края → 1 внизу зоны
        a = 0.12 + 0.88 * t * t           # доля картинки
        for x in range(w):
            c = px[x, y]
            px[x, y] = tuple(int(c[i] * a + haze[i] * (1 - a)) for i in range(3))
    out = Image.new("RGB", (w, SKY_EXT_PX + body.size[1]))
    out.paste(ext, (0, 0))
    out.paste(body, (0, SKY_EXT_PX))
    os.makedirs(TEX, exist_ok=True)
    path = os.path.join(TEX, "bg_ruins.jpg")
    out.save(path, quality=92)
    print("bg_ruins.jpg", out.size, "aspect", round(out.size[0] / out.size[1], 4),
          "ground_v", round((GROUND_PX - CROP_TOP + SKY_EXT_PX) / out.size[1], 4))


if bpy is None:
    crop_backdrop()
    sys.exit(0)

sys.path.insert(0, HERE)
import common as C  # noqa: E402

RNG = random.Random(15)
MAT = {}


# ----------------------------------------------------------------------------- textures (Cycles bake)
def _link(nt, a, b):
    nt.links.new(a, b)


def _math(nt, op, a, b=None, value=None):
    n = nt.nodes.new("ShaderNodeMath")
    n.operation = op
    _link(nt, a, n.inputs[0])
    if b is not None:
        _link(nt, b, n.inputs[1])
    elif value is not None:
        n.inputs[1].default_value = value
    return n.outputs[0]


def _seamless(nt, ru=1.0, rv=1.0):
    """UV → точка на торе в 4D (cos u, sin u, cos v | sin v): любой 4D-шум становится бесшовным по UV.
    ru/rv — радиусы: чем меньше радиус, тем крупнее детали вдоль этой оси (растяжка волокон дерева)."""
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    _link(nt, tc.outputs["UV"], sep.inputs[0])

    def circle(sock, radius):
        ang = _math(nt, 'MULTIPLY', sock, value=2.0 * math.pi)
        c = _math(nt, 'MULTIPLY', _math(nt, 'COSINE', ang), value=radius)
        s = _math(nt, 'MULTIPLY', _math(nt, 'SINE', ang), value=radius)
        return c, s

    cu, su = circle(sep.outputs[0], ru)
    cv, sv = circle(sep.outputs[1], rv)
    comb = nt.nodes.new("ShaderNodeCombineXYZ")
    _link(nt, cu, comb.inputs[0])
    _link(nt, su, comb.inputs[1])
    _link(nt, cv, comb.inputs[2])
    return comb.outputs[0], sv


def _noise4(nt, vec, w, scale, detail, rough):
    n = nt.nodes.new("ShaderNodeTexNoise")
    n.noise_dimensions = '4D'
    n.inputs["Scale"].default_value = scale
    n.inputs["Detail"].default_value = detail
    n.inputs["Roughness"].default_value = rough
    _link(nt, vec, n.inputs["Vector"])
    _link(nt, w, n.inputs["W"])
    return n.outputs["Fac"]


def _ramp(nt, fac, c0, c1, p0=0.0, p1=1.0):
    r = nt.nodes.new("ShaderNodeValToRGB")
    r.color_ramp.elements[0].position = p0
    r.color_ramp.elements[0].color = c0
    r.color_ramp.elements[1].position = p1
    r.color_ramp.elements[1].color = c1
    _link(nt, fac, r.inputs["Fac"])
    return r.outputs["Color"]


def _mul_rgb(nt, a, b):
    m = nt.nodes.new("ShaderNodeMix")
    m.data_type = 'RGBA'
    m.blend_type = 'MULTIPLY'
    m.inputs[0].default_value = 1.0
    _link(nt, a, m.inputs[6])
    _link(nt, b, m.inputs[7])
    return m.outputs[2]


def stone_nodes(nt):
    bsdf = nt.nodes["Principled BSDF"]
    vec, w = _seamless(nt)
    mottle = _ramp(nt, _noise4(nt, vec, w, 1.1, 4.0, 0.55), (0.50, 0.46, 0.40, 1), (0.97, 0.94, 0.88, 1), 0.32, 0.68)
    grain = _ramp(nt, _noise4(nt, vec, w, 9.0, 8.0, 0.75), (0.72, 0.72, 0.72, 1), (1.05, 1.05, 1.05, 1), 0.35, 0.65)
    # трещинки: 4D-Voronoi «расстояние до ребра»
    vor = nt.nodes.new("ShaderNodeTexVoronoi")
    vor.voronoi_dimensions = '4D'
    vor.feature = 'DISTANCE_TO_EDGE'
    vor.inputs["Scale"].default_value = 1.0
    _link(nt, vec, vor.inputs["Vector"])
    _link(nt, w, vor.inputs["W"])
    cracks = _ramp(nt, vor.outputs["Distance"], (0.78, 0.76, 0.74, 1), (1, 1, 1, 1), 0.0, 0.025)
    _link(nt, _mul_rgb(nt, _mul_rgb(nt, mottle, grain), cracks), bsdf.inputs["Base Color"])


def wood_nodes(nt):
    bsdf = nt.nodes["Principled BSDF"]
    vec, w = _seamless(nt, 0.35, 2.2)      # волокна вдоль U
    rings = _ramp(nt, _noise4(nt, vec, w, 1.6, 5.0, 0.6), (0.42, 0.27, 0.13, 1), (0.80, 0.58, 0.34, 1), 0.3, 0.7)
    fine = _ramp(nt, _noise4(nt, vec, w, 12.0, 6.0, 0.7), (0.80, 0.80, 0.80, 1), (1.08, 1.08, 1.08, 1), 0.35, 0.65)
    _link(nt, _mul_rgb(nt, rings, fine), bsdf.inputs["Base Color"])


def bake_texture(name, build, size=512):
    """Запекает Base Color процедурного материала (Cycles, DIFFUSE color) в JPEG и возвращает загруженный Image."""
    scn = bpy.context.scene
    bpy.ops.mesh.primitive_plane_add(size=1.0)
    plane = bpy.context.active_object
    plane.name = "Bake_" + name
    mat = bpy.data.materials.new("Bake_" + name)
    mat.use_nodes = True
    build(mat.node_tree)
    plane.data.materials.append(mat)
    img = bpy.data.images.new(name, size, size)
    tex = mat.node_tree.nodes.new('ShaderNodeTexImage')
    tex.image = img
    mat.node_tree.nodes.active = tex
    scn.render.engine = 'CYCLES'
    scn.cycles.device = 'CPU'
    scn.cycles.samples = 8
    scn.render.bake.use_pass_direct = False
    scn.render.bake.use_pass_indirect = False
    scn.render.bake.use_pass_color = True
    scn.render.bake.margin = 4
    bpy.ops.object.select_all(action='DESELECT')
    plane.select_set(True)
    bpy.context.view_layer.objects.active = plane
    bpy.ops.object.bake(type='DIFFUSE')
    os.makedirs(os.path.join(TEX, "kit"), exist_ok=True)
    path = os.path.join(TEX, "kit", name + ".jpg")
    img.file_format = 'JPEG'
    img.save(filepath=path, quality=88)
    bpy.data.objects.remove(plane, do_unlink=True)
    bpy.data.materials.remove(mat)
    bpy.data.images.remove(img)
    loaded = bpy.data.images.load(path)
    loaded.name = name
    print("baked", path)
    return loaded


def mat_tex(name, image, tint, rough, metal=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = image
    tex.extension = 'REPEAT'
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = 'RGBA'
    mix.blend_type = 'MULTIPLY'
    mix.inputs[0].default_value = 1.0
    mix.inputs[7].default_value = tint
    _link(nt, tex.outputs["Color"], mix.inputs[6])
    _link(nt, mix.outputs[2], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    MAT[name] = m
    return m


def make_materials():
    stone_img = bake_texture("kit_stone", stone_nodes)
    wood_img = bake_texture("kit_wood", wood_nodes)
    mat_tex("Stone_A", stone_img, (0.70, 0.64, 0.54, 1), 0.88)
    mat_tex("Stone_B", stone_img, (0.60, 0.58, 0.53, 1), 0.90)
    mat_tex("Stone_C", stone_img, (0.56, 0.48, 0.38, 1), 0.86)
    mat_tex("Stone_Dark", stone_img, (0.38, 0.35, 0.31, 1), 0.92)
    mat_tex("Wood", wood_img, (1.0, 0.88, 0.72, 1), 0.80)
    mat_tex("WoodDark", wood_img, (0.62, 0.50, 0.38, 1), 0.82)
    MAT["Mortar"] = C.material("Mortar", (0.22, 0.19, 0.16, 1), 0.95)
    MAT["Iron"] = C.material("Iron", (0.17, 0.17, 0.18, 1), 0.48, 0.85)
    MAT["Cloth"] = C.material("Cloth", (0.70, 0.10, 0.08, 1), 0.92)
    MAT["Emblem"] = C.material("Emblem", (0.95, 0.78, 0.30, 1), 0.55, 0.25)
    MAT["Flame"] = C.material("Flame", (1.0, 0.55, 0.12, 1), 0.6, 0.0, emission=(1.0, 0.45, 0.08, 1), emission_strength=5.0)
    MAT["Char"] = C.material("Char", (0.12, 0.09, 0.07, 1), 0.95)
    MAT["Leaf"] = C.material("Leaf", (0.15, 0.32, 0.09, 1), 0.85)
    MAT["LeafDark"] = C.material("LeafDark", (0.08, 0.20, 0.05, 1), 0.88)


DARK_STONE = False


def stone_variant():
    if DARK_STONE:
        return MAT[RNG.choice(["Stone_Dark", "Stone_Dark", "Stone_C"])]
    return MAT[RNG.choice(["Stone_A", "Stone_A", "Stone_B", "Stone_C"])]


# ----------------------------------------------------------------------------- geometry helpers
def box(name, size, loc, rot=(0, 0, 0), mat=None, jitter=0.0):
    """Куб size в loc (origin = loc, геометрия локальная), поворот применён к геометрии."""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
    o = bpy.context.active_object
    o.name = name
    o.scale = size
    C.apply_transforms(o, scale=True)
    if jitter > 0.0:
        for v in o.data.vertices:
            v.co += Vector((RNG.uniform(-jitter, jitter), RNG.uniform(-jitter, jitter), RNG.uniform(-jitter, jitter)))
    if any(abs(r) > 1e-9 for r in rot):
        o.rotation_euler = rot
        C.apply_transforms(o, rotation=True, scale=True)
    o.location = loc
    if mat is not None:
        o.data.materials.append(mat)
    return o


def lathe(name, profile, segs=24, mat=None, close_bottom=True, close_top=True):
    """Тело вращения вокруг Z из профиля [(r, z), ...]; r=0 — полюс."""
    bm = bmesh.new()
    rings = []
    for r, z in profile:
        if r < 1e-6:
            rings.append([bm.verts.new((0.0, 0.0, z))])
        else:
            rings.append([bm.verts.new((r * math.cos(2 * math.pi * i / segs), r * math.sin(2 * math.pi * i / segs), z)) for i in range(segs)])
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
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    if mat is not None:
        me.materials.append(mat)
    return o


def ring(name, r_in, r_out, z0, z1, segs=24, mat=None):
    """Плоское кольцо/обруч квадратного сечения (замкнутый профиль)."""
    return lathe(name, [(r_in, z0), (r_out, z0), (r_out, z1), (r_in, z1), (r_in, z0)], segs, mat, False, False)


def uv_box(obj, scale=1.0):
    """Кубическая проекция UV в масштабе 1 текстура = 1/scale м (мировая шкала, стыкуется между модулями)."""
    me = obj.data
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    uv = me.uv_layers[0].data
    for poly in me.polygons:
        n = poly.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            if ax == 0:
                u, v = co.y, co.z
            elif ax == 1:
                u, v = co.x, co.z
            else:
                u, v = co.x, co.y
            uv[li].uv = (u * scale, v * scale)


def finish(obj, bevel=0.02, segments=1, angle=30.0, uv_scale=1.0):
    """Фаска + плавное затенение по углу + UV; origin в мировой (0,0,0)."""
    C.set_origin(obj, (0.0, 0.0, 0.0))
    if bevel > 0.0:
        m = C.bevel(obj, bevel, segments, 30.0)
        m.harden_normals = True
    if uv_scale > 0.0:
        uv_box(obj, uv_scale)
    C.smooth(obj, angle)
    return obj


def merge(objs, name):
    if len(objs) == 1:
        objs[0].name = name
        return objs[0]
    return C.join(objs, name)


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


# ----------------------------------------------------------------------------- masonry
def course_blocks(prefix, x0, x1, z0, height, depth, gap=0.03, unit=1.0, odd=False, jitter=0.01, inset_max=0.03, y=0.0):
    """Ряд блоков между x0..x1 (перевязка: нечётный ряд начинается с половинки)."""
    objs = []
    xs = [x0]
    x = x0 + (unit * 0.5 if odd else unit)
    while x < x1 - 0.2:
        xs.append(x)
        x += unit
    xs.append(x1)
    for i in range(len(xs) - 1):
        a, b = xs[i], xs[i + 1]
        inset = RNG.uniform(0.0, inset_max)
        size = (b - a - gap, depth - 2.0 * inset, height - gap)
        objs.append(box("%s_%d" % (prefix, i), size, ((a + b) * 0.5, y, z0 + height * 0.5), mat=stone_variant(), jitter=jitter))
    return objs


def stone_block(name, variant):
    o = box(name, (0.5, 0.5, 0.5), (0, 0, 0.25), mat=MAT[variant], jitter=0.012)
    return finish(o, bevel=0.03, segments=2)


def stone_slab(name, length):
    depth = 2.0
    base = box(name + "_base", (length, depth, 0.34), (0, 0, 0.17), mat=MAT["Stone_B"])
    core = box(name + "_core", (length - 0.02, depth - 0.02, 0.06), (0, 0, 0.36), mat=MAT["Mortar"])
    objs = [base, core]
    nx = max(2, round(length / 1.0))
    xs = [-length * 0.5 + length * i / nx + (RNG.uniform(-0.08, 0.08) if 0 < i < nx else 0.0) for i in range(nx + 1)]
    ys = [-1.0, RNG.uniform(-0.1, 0.1), 1.0]
    k = 0
    for i in range(nx):
        for j in range(2):
            w = xs[i + 1] - xs[i] - 0.04
            d = ys[j + 1] - ys[j] - 0.04
            h = 0.08 + RNG.uniform(-0.012, 0.012)
            objs.append(box("%s_t%d" % (name, k), (w, d, h), ((xs[i] + xs[i + 1]) * 0.5, (ys[j] + ys[j + 1]) * 0.5, 0.34 + h * 0.5), mat=stone_variant(), jitter=0.006))
            k += 1
    return finish(merge(objs, name), bevel=0.02, segments=1)


def stone_wall(name, width, height, depth=0.8, dark=False):
    global DARK_STONE
    DARK_STONE = dark
    n = int(round(height / 0.5))
    objs = [box(name + "_core", (width - 0.06, depth - 0.08, height), (0, 0, height * 0.5), mat=MAT["Mortar"])]
    for i in range(n):
        objs += course_blocks("%s_r%d" % (name, i), -width * 0.5, width * 0.5, i * 0.5, 0.5, depth, odd=(i % 2 == 1))
    DARK_STONE = False
    return finish(merge(objs, name), bevel=0.02, segments=1)


def stone_top(name, width=2.0, depth=0.8):
    """Разрушенный верхний ряд: зубцы разной высоты с провалом."""
    objs = []
    xs = [-1.0, -0.5, 0.0, 0.5, 1.0]
    heights = [0.5, 0.0, 0.42, 0.5]
    for i in range(4):
        if heights[i] <= 0.0:
            continue
        objs.append(box("%s_%d" % (name, i), (0.47, depth - RNG.uniform(0.0, 0.05), heights[i]), ((xs[i] + xs[i + 1]) * 0.5, 0, heights[i] * 0.5), mat=stone_variant(), jitter=0.012))
    return finish(merge(objs, name), bevel=0.025, segments=1)


def arch(name, opening, height, pier, thick, depth=0.8, voussoirs=11):
    r_in = opening * 0.5
    spring = height - r_in - thick
    half = r_in + pier
    objs = []
    # пилоны (ряды блоков) до пяты арки
    z = 0.0
    i = 0
    while z < spring - 1e-6:
        h = min(0.5, spring - z)
        for s in (-1, 1):
            a, b = (-half, -r_in) if s < 0 else (r_in, half)
            objs += course_blocks("%s_p%d%d" % (name, s + 1, i), a, b, z, h, depth, unit=pier * 0.6 if i % 2 else pier, odd=False)
        z += h
        i += 1
    # клинья по полуокружности (выступают на 0.02 вперёд/назад относительно заполнения)
    rm = r_in + thick * 0.5
    for k in range(voussoirs):
        t0 = math.pi * k / voussoirs
        t1 = math.pi * (k + 1) / voussoirs
        tm = (t0 + t1) * 0.5
        arc = (r_in + thick) * (t1 - t0) * 1.02 - 0.02
        key = (k == voussoirs // 2)
        size = (arc + (0.08 if key else 0.0), depth + (0.06 if key else 0.0), thick + (0.08 if key else 0.0))
        loc = (rm * math.cos(tm), 0.0, spring + rm * math.sin(tm))
        objs.append(box("%s_v%d" % (name, k), size, loc, rot=(0.0, -(tm - math.pi * 0.5), 0.0), mat=stone_variant(), jitter=0.006))
    # пазухи над пилонами и верхний ряд-перемычка (глубина −0.04, чтобы клинья читались)
    z = spring
    i = 0
    while z < height - 1e-6:
        h = min(0.5, height - z)
        for s in (-1, 1):
            a, b = (-half, -r_in) if s < 0 else (r_in, half)
            objs += course_blocks("%s_s%d%d" % (name, s + 1, i), a, b, z, h, depth - 0.04, unit=pier * 0.6 if i % 2 else pier, inset_max=0.01)
        z += h
        i += 1
    top_h = min(thick - 0.02, 0.45)
    objs += course_blocks(name + "_top", -r_in, r_in, height - top_h, top_h, depth - 0.04, unit=1.0, odd=True, inset_max=0.01)
    return finish(merge(objs, name), bevel=0.02, segments=1)


# ----------------------------------------------------------------------------- wood
def plank(name, length):
    o = box(name, (length, 0.25, 0.05), (0, 0, 0.025), mat=MAT["Wood"], jitter=0.003)
    return finish(o, bevel=0.008, segments=1)


def beam(name, length):
    o = box(name, (length, 0.2, 0.2), (0, 0, 0.1), mat=MAT["WoodDark"], jitter=0.004)
    return finish(o, bevel=0.015, segments=1)


def post(name, height=2.0):
    objs = [box(name + "_post", (0.2, 0.2, height), (0, 0, height * 0.5), mat=MAT["WoodDark"], jitter=0.004)]
    for s in (-1, 1):
        dx, dz = 0.62 * s, height - 1.25
        L = math.hypot(dx, dz)
        objs.append(box("%s_brace%d" % (name, s + 1), (L + 0.1, 0.12, 0.12), (dx * 0.5, 0.0, 1.25 + dz * 0.5), rot=(0.0, -math.atan2(dz, dx), 0.0), mat=MAT["WoodDark"]))
    objs.append(box(name + "_cap", (0.3, 0.3, 0.06), (0, 0, height + 0.03), mat=MAT["WoodDark"]))
    return finish(merge(objs, name), bevel=0.012, segments=1)


def crate(name, size=0.7):
    e = 0.08
    h = size * 0.5
    c = h - e * 0.5
    objs = []
    k = 0
    for (sx, sy, sz), pos_list in [
        ((size, e, e), [(0, y, z) for y in (-c, c) for z in (-c, c)]),
        ((e, size, e), [(x, 0, z) for x in (-c, c) for z in (-c, c)]),
        ((e, e, size), [(x, y, 0) for x in (-c, c) for y in (-c, c)]),
    ]:
        for p in pos_list:
            objs.append(box("%s_f%d" % (name, k), (sx, sy, sz), (p[0], p[1], p[2] + h), mat=MAT["WoodDark"], jitter=0.003))
            k += 1
    inner = size - 2 * e
    pw = inner / 3.0
    for axis in range(3):
        for s in (-1, 1):
            for i in range(3):
                off = -inner * 0.5 + pw * (i + 0.5)
                sz = [inner + 0.02, inner + 0.02, inner + 0.02]
                sz[axis] = 0.035
                sz[(axis + 1) % 3] = pw - 0.02
                pos = [0.0, 0.0, 0.0]
                pos[axis] = s * (h - 0.035)
                pos[(axis + 1) % 3] = off
                objs.append(box("%s_p%d" % (name, k), tuple(sz), (pos[0], pos[1], pos[2] + h), mat=MAT["Wood"], jitter=0.003))
                k += 1
    return finish(merge(objs, name), bevel=0.01, segments=1)


def barrel(name):
    body = lathe(name + "_body", [(0, 0.03), (0.22, 0.03), (0.26, 0.0), (0.285, 0.1), (0.31, 0.4), (0.285, 0.7), (0.26, 0.8), (0.22, 0.77), (0, 0.77)], 18, MAT["WoodDark"])
    b1 = ring(name + "_b1", 0.27, 0.305, 0.11, 0.18, 36, MAT["Iron"])
    b2 = ring(name + "_b2", 0.27, 0.305, 0.62, 0.69, 36, MAT["Iron"])
    o = merge([body, b1, b2], name)
    return finish(o, bevel=0.0, angle=14.0, uv_scale=1.0)


def cage(name):
    r = 0.4
    h = 1.4
    objs = [lathe(name + "_floor", [(0, 0), (r, 0), (r, 0.05), (0, 0.05)], 24, MAT["Iron"])]
    for i, (z0, z1) in enumerate([(0.05, 0.10), (h * 0.5 - 0.025, h * 0.5 + 0.025), (h - 0.05, h)]):
        objs.append(ring("%s_ring%d" % (name, i), r - 0.035, r + 0.005, z0, z1, 28, MAT["Iron"]))
    for i in range(12):
        a = 2 * math.pi * i / 12
        objs.append(lathe("%s_bar%d" % (name, i), [(0.018, 0.05), (0.018, h)], 6, MAT["Iron"]))
        objs[-1].location = (math.cos(a) * (r - 0.02), math.sin(a) * (r - 0.02), 0.0)
        C.apply_transforms(objs[-1], location=True)
    objs.append(lathe(name + "_dome", [(r, h), (r * 0.8, h + 0.1), (r * 0.5, h + 0.2), (0.06, h + 0.27), (0.06, h + 0.31), (0, h + 0.31)], 24, MAT["Iron"], close_bottom=False))
    objs.append(lathe(name + "_stem", [(0.02, h + 0.3), (0.02, h + 0.36)], 8, MAT["Iron"]))
    hook = C.add_torus(name + "_hook", 0.05, 0.014, loc=(0, 0, h + 0.36 + 0.05), rot=(math.pi * 0.5, 0, 0), segs=20, ring=8)
    hook.data.materials.append(MAT["Iron"])
    o = merge(objs + [hook], name)
    return finish(o, bevel=0.0, angle=40.0)


def torch(name):
    objs = [
        box(name + "_plate", (0.14, 0.03, 0.26), (0, 0.285, 0.30), mat=MAT["Iron"]),
        box(name + "_arm", (0.04, 0.27, 0.04), (0, 0.15, 0.30), mat=MAT["Iron"]),
        lathe(name + "_stick", [(0.028, 0.0), (0.028, 0.05), (0.03, 0.75), (0.035, 0.85)], 10, MAT["WoodDark"]),
        lathe(name + "_head", [(0.03, 0.78), (0.062, 0.86), (0.058, 0.98), (0.03, 1.02)], 12, MAT["Char"]),
        lathe(name + "_flame", [(0, 0.94), (0.09, 1.02), (0.11, 1.12), (0.06, 1.30), (0, 1.46)], 12, MAT["Flame"]),
    ]
    holder = C.add_torus(name + "_holder", 0.05, 0.012, loc=(0, 0, 0.30), segs=20, ring=8)
    holder.data.materials.append(MAT["Iron"])
    o = merge(objs + [holder], name)
    return finish(o, bevel=0.0, angle=40.0)


def chain_link(name):
    t = C.add_torus(name, 0.05, 0.022, segs=16, ring=8)
    t.data.materials.append(MAT["Iron"])
    C.apply_transforms(t)
    for v in t.data.vertices:
        v.co.y += 0.05 if v.co.y > 0.0 else -0.05
    t.rotation_euler = (math.pi * 0.5, 0, 0)
    C.apply_transforms(t, rotation=True)
    for v in t.data.vertices:
        v.co.z += 0.122
    return finish(t, bevel=0.0, angle=40.0)


def banner(name):
    pole = lathe(name + "_pole", [(0.035, 0.0), (0.035, 3.0)], 12, MAT["WoodDark"])
    knob = lathe(name + "_knob", [(0, 3.0), (0.05, 3.03), (0.06, 3.08), (0.04, 3.14), (0, 3.17)], 12, MAT["Emblem"])
    bar = box(name + "_bar", (1.45, 0.06, 0.06), (0, -0.04, 2.86), mat=MAT["WoodDark"], jitter=0.003)
    pole_obj = merge([pole, knob, bar], name)
    finish(pole_obj, bevel=0.0, angle=40.0)
    # полотнище: сетка 12×18 клеток по 0.1 м, волна по Y, рваный низ, корона из граней
    w, h, nx, nz = 1.2, 1.8, 20, 30
    crown = ["X....X....X", "X....X....X", "XX...X...XX", "XXX.XXX.XXX", "XXXXXXXXXXX", "XXXXXXXXXXX", ".XXXXXXXXX.", ".XXXXXXXXX."]
    cx0, cz0 = 5, 10
    bm = bmesh.new()
    grid = []
    for j in range(nz + 1):
        row = []
        for i in range(nx + 1):
            x = -w * 0.5 + w * i / nx
            z = -h * j / nz
            amp = 0.05 * (j / nz) ** 0.7
            y = amp * math.sin(2 * math.pi * z / 1.1 + x * 2.5) - 0.07
            if j == nz and i % 2 == 1:
                z += 0.14
            row.append(bm.verts.new((x, y, z)))
        grid.append(row)
    emblem = []
    for j in range(nz):
        for i in range(nx):
            f = bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
            f.material_index = 0
            cj, ci = j - cz0, i - cx0
            if 0 <= cj < len(crown) and 0 <= ci < len(crown[0]) and crown[cj][ci] == "X":
                f.material_index = 1
                emblem.append(f)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    if sum(f.normal.y for f in bm.faces) > 0.0:
        bmesh.ops.reverse_faces(bm, faces=bm.faces)
    bmesh.ops.inset_region(bm, faces=emblem, thickness=0.008, depth=0.006)
    me = bpy.data.meshes.new(name + "_Cloth")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(MAT["Cloth"])
    me.materials.append(MAT["Emblem"])
    cloth = bpy.data.objects.new("Banner_Cloth", me)
    bpy.context.scene.collection.objects.link(cloth)
    cloth.location = (0.0, 0.0, 2.86)
    for p in me.polygons:
        p.use_smooth = True
    C.parent(cloth, pole_obj)
    return pole_obj


# ----------------------------------------------------------------------------- foliage (low-poly)
def bush(name):
    objs = []
    for i, (dx, dy, dz, r, m) in enumerate([(0, 0, 0, 0.36, "Leaf"), (0.28, -0.1, -0.05, 0.27, "LeafDark"), (-0.25, 0.08, -0.02, 0.29, "Leaf"), (0.05, -0.22, 0.12, 0.22, "LeafDark")]):
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=r, location=(dx, dy, r * 0.75 + dz))
        o = bpy.context.active_object
        o.name = "%s_%d" % (name, i)
        o.scale = (1.0, 1.0, 0.78)
        C.apply_transforms(o, scale=True)
        for v in o.data.vertices:
            v.co += Vector((RNG.uniform(-0.05, 0.05), RNG.uniform(-0.05, 0.05), RNG.uniform(-0.04, 0.04)))
        o.data.materials.append(MAT[m])
        objs.append(o)
    o = merge(objs, name)
    C.set_origin(o, (0.0, 0.0, 0.0))
    uv_box(o, 1.0)
    return o


def grass_tuft(name, blades=12):
    bm = bmesh.new()
    for b in range(blades):
        a = RNG.uniform(0, 2 * math.pi)
        lean = RNG.uniform(0.15, 0.45)
        hgt = RNG.uniform(0.22, 0.42)
        wid = RNG.uniform(0.025, 0.04)
        base = Vector((RNG.uniform(-0.12, 0.12), RNG.uniform(-0.12, 0.12), 0.0))
        side = Vector((-math.sin(a), math.cos(a), 0.0)) * wid
        prev = None
        for k in range(4):
            t = k / 3.0
            p = base + Vector((math.cos(a), math.sin(a), 0.0)) * (lean * t * t) + Vector((0, 0, hgt * t))
            wk = (1.0 - t * 0.85)
            cur = (bm.verts.new(p - side * wk), bm.verts.new(p + side * wk))
            if prev:
                bm.faces.new((prev[0], prev[1], cur[1], cur[0]))
            prev = cur
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(MAT["Leaf"])
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    for p in me.polygons:
        p.use_smooth = True
    uv_box(o, 1.0)
    return o


# ----------------------------------------------------------------------------- build all
MODULES = [
    ("Stone_Block_A", lambda n: stone_block(n, "Stone_A")),
    ("Stone_Block_B", lambda n: stone_block(n, "Stone_B")),
    ("Stone_Block_C", lambda n: stone_block(n, "Stone_C")),
    ("Stone_Slab_2m", lambda n: stone_slab(n, 2.0)),
    ("Stone_Slab_4m", lambda n: stone_slab(n, 4.0)),
    ("Stone_Slab_5m", lambda n: stone_slab(n, 5.0)),
    ("Stone_Wall_2x3", lambda n: stone_wall(n, 2.0, 3.0)),
    ("Stone_Wall_1x3", lambda n: stone_wall(n, 1.0, 3.0)),
    ("Stone_Wall_2x1", lambda n: stone_wall(n, 2.0, 1.0)),
    ("Stone_Top_2m", lambda n: stone_top(n)),
    ("Stone_Cliff_2x3", lambda n: stone_wall(n, 2.0, 3.0, dark=True)),
    ("Arch_3m", lambda n: arch(n, 3.0, 3.2, 1.0, 0.4, voussoirs=11)),
    ("Arch_1_5m", lambda n: arch(n, 1.5, 2.4, 0.75, 0.35, voussoirs=9)),
    ("Plank_2m", lambda n: plank(n, 2.0)),
    ("Plank_3m", lambda n: plank(n, 3.0)),
    ("Beam_3m", lambda n: beam(n, 3.0)),
    ("Beam_4m", lambda n: beam(n, 4.0)),
    ("Post_2m", lambda n: post(n, 2.0)),
    ("Banner", banner),
    ("Torch", torch),
    ("Cage", cage),
    ("Barrel", barrel),
    ("Crate", crate),
    ("Chain_Link", chain_link),
    ("Bush", bush),
    ("Grass_Tuft", grass_tuft),
]


def main():
    C.reset_scene()
    make_materials()
    os.makedirs(OUT, exist_ok=True)
    only = C.args_after_dashdash()
    report = []
    for name, build in MODULES:
        if only and name not in only:
            continue
        obj = build(name)
        obj.name = name
        tris = tri_count(obj)
        path = os.path.join(OUT, name + ".glb")
        C.export_glb(path, objects=[obj])
        report.append((name, tris, os.path.getsize(path)))
        for o in [obj] + list(obj.children_recursive):
            o.hide_set(True)
    bad = [r for r in report if r[1] > TRI_BUDGET]
    print("MODULE                 TRIS    BYTES")
    for name, tris, size in report:
        print("%-22s %5d %8d%s" % (name, tris, size, "  OVER BUDGET" if tris > TRI_BUDGET else ""))
    if bad:
        print("ERROR: over budget:", [b[0] for b in bad])
        sys.exit(1)


main()
