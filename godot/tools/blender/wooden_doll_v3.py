"""Художественный манекен v3 по R22 (docs/refs/R22-a-hero-workshop-fight.jpg, ART_DIRECTION.md «v3») — hero-качество,
headless Blender 4.5. Заменяет wooden_doll.py (R19, игрушка с обручами).

Запуск:
    /Applications/Blender.app/Contents/MacOS/Blender -b --python godot/tools/blender/wooden_doll_v3.py -- [tone=light|dark]
        [bake=1|0] [size=1024] [render=0|1] [parts=Head,Torso,…] [out=<dir>]
    tone   — порода дерева: light = клён (assets/textures/pbr/maple_light), dark = орех (walnut_dark);
    bake   — запекать износ на каждую деталь (AO, потёртости кромок, царапины, пыль → albedo/roughness/normal детали);
             bake=0 — быстрый черновик с тайлом дерева напрямую (для итераций по форме);
    size   — размер карт детали (Torso/Head — size, остальные — size/2… см. BAKE_SIZE);
    render — дополнительно рендер Workbench (спереди и крупно 3/4) в <out>/_preview_<tone>_*.png;
    parts  — собрать только перечисленные части (остальные не экспортируются; для итераций).

Пишет:
    godot/assets/models/heroes/mannequin_v3/<tone>/<Part>.glb — одна часть, узел в нуле, вершины относительно
                                                              проксимального сустава (origin части = сустав; Torso — центр y 1.17);
    godot/assets/models/heroes/mannequin_v3/full/<tone>.glb — все 14 частей в позе покоя (папка с .gdignore, только просмотр).

v3.1 (28.09, доводка по отзыву автора): грудь круглее (шельф 0.42 → талия 0.24, глубина 0.22 в середине, выпуклая шапка плеч),
ноги толще (бедро 0.154×0.130 → 0.114×0.102, голень 0.114×0.102 → 0.094×0.084, шары/гнёзда колена и лодыжки крупнее),
плечи 0.105×0.085 → 0.085×0.070; коллизии в build_doll_scene.gd: UpperLeg 0.070, LowerLeg 0.056, UpperArm 0.052, LowerArm 0.044.

Риг v3 (метры, координаты Godot; = scenes/doll/doll.gd и tools/build_doll_scene.gd): рост 1.80; шея 1.47, плечи y 1.43
x ±0.22, локти 1.13, запястья 0.86, бёдра y 0.91 x ±0.10, колени 0.49, лодыжки 0.09; центр Torso 1.17.

Геометрия: каждая деталь — лофт по кольцам-сечениям (суперэллипсы с шириной/глубиной на кольцо, bmesh bridge) +
Subdivision 2 + булевы ЧАШКИ суставов (сфера r шара + 3 мм вырезана из дистального конца родителя, так что шар ребёнка
виден «в гнезде») + фаска кромок чашек. Шар сустава принадлежит ДИСТАЛЬНОЙ части и стоит в её origin (дочерний объект
<Part>_Ball, материал Joint), стальные штифты (Pin) — сквозь чашку родителя вдоль оси сустава (Godot Z).
Голова — яйцо с двумя сверлёными глазами, шея-шар; торс = грудь (плечевой шельф, грудная выпуклость, желобок позвоночника)
+ брюшной шар + таз в одном объекте; конечности — эллиптические сужающиеся лофты с расширением-гнездом на дистальном конце;
кисти — ладонь + 5 пальцев по 3 фаланги (большой — 2) с шариками суставов, слегка согнуты; стопы — подошва со скруглённым
носком и пяткой, носком к камере.

Материалы: Wood_<Part> (запечённые на деталь albedo/roughness/normal из тайла клёна/ореха × AO × износ кромок ×
царапины × пыль; при bake=0 — общий Wood с тайлом), Joint (тёмная сталь шаров), Pin (сталь), Shirt (обмотки: cloth_wrap ×
красный baseColorFactor — Godot подменяет фактор цветом игрока), Shirt_Paint (оболочки-декали 1.5 мм над деревом:
маска мазков paint_marks в alpha, BLEND; тоже перекрашивается), Face (FacePlate: колпак яйца под фото, UV 0..1,
по умолчанию то же дерево — без фото невидим).

Оси: описание в координатах Godot (X вбок, +X = левая сторона куклы, Y вверх, +Z к камере), перевод в Blender через
B(): (x, -z, y). Лицо в -Y Blender → +Z Godot после экспорта с Y вверх.
"""
import math
import os
import sys
import tempfile
import time

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import common  # noqa: E402
import textures as T  # noqa: E402  (save_rgba8, _read_float, _linear_to_srgb8, _setup_cycles)

GODOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT_ROOT = os.path.join(GODOT, "assets", "models", "heroes", "mannequin_v3")
TRI_BUDGET = 90000
TAU = 2.0 * math.pi

# --- риг v3 (метры, координаты Godot) -------------------------------------------------------------
NECK_Y = 1.47
HEAD_C = 1.63
SHOULDER_Y, SX = 1.43, 0.22
ELBOW_Y, WRIST_Y = 1.13, 0.86
HIP_Y, HX = 0.91, 0.10
KNEE_Y, ANKLE_Y = 0.49, 0.09
TORSO_C = 1.17

# радиусы шаров суставов (у дистальной части) и наружные радиусы гнёзд (у родителя)
BALL = {"neck": 0.050, "shoulder": 0.058, "elbow": 0.045, "wrist": 0.036, "hip": 0.060, "knee": 0.057, "ankle": 0.045}
HOUSING = {"elbow": 0.056, "wrist": 0.047, "knee": 0.067, "ankle": 0.057}
CUP_GAP = 0.003          # зазор чашки вокруг шара
PIN_R = 0.004
WOOD_UV = 2.0            # 1 тайл дерева = 0.5 м
SMOOTH_DEG = 60.0

BAKE_SIZE = {"Torso": 1.0, "Head": 1.0, "UpperLeg": 0.75, "LowerLeg": 0.75, "UpperArm": 0.75, "LowerArm": 0.75,
             "Hand": 0.75, "Foot": 0.5, "FacePlate": 0.5}

ARGS = {"tone": "light", "bake": 1, "size": 1024, "render": 0, "parts": "", "out": ""}
for _a in common.args_after_dashdash():
    if "=" in _a:
        _k, _v = _a.split("=", 1)
        if _k in ARGS:
            ARGS[_k] = type(ARGS[_k])(_v)
TONE = ARGS["tone"]
WOOD_FOLDER = {"light": "maple_light", "dark": "walnut_dark"}[TONE]
OUT_DIR = ARGS["out"] or os.path.join(OUT_ROOT, TONE)
ONLY = [p for p in ARGS["parts"].split(",") if p]


def B(x, y, z):
    """Godot (x, y_up, z_front) → Blender (x, -z, y)."""
    return Vector((x, -z, y))


# ------------------------------------------------------------------------------------------------
# материалы
# ------------------------------------------------------------------------------------------------
MAT = {}


def shrink_textures(folder, size):
    """Уменьшает набор PBR до size перед упаковкой (common._load_packed возьмёт те же datablock-и — check_existing)."""
    for fname in ("albedo.png", "roughness.png", "normal.png"):
        p = os.path.join(common.PBR_DIR, folder, fname)
        if not os.path.exists(p):
            continue
        img = bpy.data.images.load(p, check_existing=True)
        if fname != "albedo.png":
            img.colorspace_settings.name = 'Non-Color'
        if img.size[0] > size:
            img.scale(size, size)
            img.pack()


def make_materials():
    shrink_textures("cloth_wrap", 512)          # обмотки маленькие: 1024² × 4 части избыточны (по 3 МБ на glb)
    wood_tint = {"light": (1.0, 0.97, 0.92, 1.0), "dark": (1.0, 0.98, 0.96, 1.0)}[TONE]
    MAT["Wood"] = common.textured_material("Wood", WOOD_FOLDER, tint=wood_tint)
    MAT["Joint"] = common.material("Joint", (0.11, 0.105, 0.11, 1.0), rough=0.42, metal=0.85)
    MAT["Pin"] = common.material("Pin", (0.62, 0.62, 0.64, 1.0), rough=0.30, metal=1.0)
    # обмотки: нейтральная светлая ткань × красный фактор (Godot заменяет фактор цветом игрока)
    MAT["Shirt"] = common.textured_material("Shirt", "cloth_wrap", tint=(0.80, 0.12, 0.10, 1.0))
    MAT["Shirt_Paint"] = paint_material()
    MAT["Face"] = common.textured_material("Face", WOOD_FOLDER, tint=wood_tint)


def paint_material():
    """Мазки краски: paint_marks/albedo.png (RGBA) → Base Color × tint и Alpha, BLEND, без теней."""
    folder = os.path.join(common.PBR_DIR, "paint_marks")
    mat = bpy.data.materials.get("Shirt_Paint") or bpy.data.materials.new("Shirt_Paint")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    bsdf = nt.nodes.new('ShaderNodeBsdfPrincipled')
    nt.links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
    tex = nt.nodes.new('ShaderNodeTexImage')
    tex.image = common._load_packed(os.path.join(folder, "albedo.png"))
    tex.extension = 'REPEAT'
    mix = nt.nodes.new('ShaderNodeMix')
    mix.data_type = 'RGBA'
    mix.blend_type = 'MULTIPLY'
    mix.inputs[0].default_value = 1.0
    mix.inputs[7].default_value = (0.80, 0.12, 0.10, 1.0)
    nt.links.new(tex.outputs['Color'], mix.inputs[6])
    nt.links.new(mix.outputs[2], bsdf.inputs['Base Color'])
    nt.links.new(tex.outputs['Alpha'], bsdf.inputs['Alpha'])
    rough = nt.nodes.new('ShaderNodeTexImage')
    rough.image = common._load_packed(os.path.join(folder, "roughness.png"), non_color=True)
    nt.links.new(rough.outputs['Color'], bsdf.inputs['Roughness'])
    for attr, val in (('surface_render_method', 'BLENDED'), ('blend_method', 'BLEND'), ('shadow_method', 'NONE')):
        try:
            setattr(mat, attr, val)
        except Exception:
            pass
    mat.use_backface_culling = True
    return mat


# ------------------------------------------------------------------------------------------------
# геометрические хелперы (координаты Blender: Z вверх, лицо −Y)
# ------------------------------------------------------------------------------------------------
def select_only(obj):
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def apply_mods(obj):
    select_only(obj)
    for m in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)
    return obj


def mesh_object(name, bm, loc=(0, 0, 0)):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    o.location = loc
    return o


def cc_of(n):
    """Компенсация усадки Catmull-Clark для кольца из n точек: предел кубического B-сплайна по окружности R·(2+cos θ)/3."""
    return 3.0 / (2.0 + math.cos(TAU / n))


def sring(z, w, d, n=16, exp=2.0, cx=0.0, cy=0.0, shape=None, cc=None):
    """Кольцо-суперэллипс в горизонтальной плоскости на высоте z: ширина w (X), глубина d (Y), показатель exp
    (2 — эллипс, 3–4 — скруглённый прямоугольник). shape(a, x, y, z) → (x, y) — модуляция (выпуклости, желобки).
    cc — компенсация усадки Catmull-Clark (None = по числу точек)."""
    if cc is None:
        cc = cc_of(n)
    pts = []
    for i in range(n):
        a = TAU * i / n
        c, s = math.cos(a), math.sin(a)
        x = 0.5 * w * cc * math.copysign(abs(c) ** (2.0 / exp), c)
        y = 0.5 * d * cc * math.copysign(abs(s) ** (2.0 / exp), s)
        if shape is not None:
            x, y = shape(a, x, y, z)
        pts.append(Vector((cx + x, cy + y, z)))
    return pts


def loft(name, rings, cap0=True, cap1=True):
    """Соединяет кольца квадами (bridge), крышки — n-угольники (Catmull-Clark скругляет их в купол)."""
    bm = bmesh.new()
    vr = [[bm.verts.new(p) for p in r] for r in rings]
    n = len(rings[0])
    for a, b in zip(vr, vr[1:]):
        for i in range(n):
            bm.faces.new((a[i], a[(i + 1) % n], b[(i + 1) % n], b[i]))
    if cap0:
        bm.faces.new(list(reversed(vr[0])))
    if cap1:
        bm.faces.new(vr[-1])
    return mesh_object(name, bm)


def transform_rings(rings, mat):
    return [[mat @ p for p in r] for r in rings]


def cut_sphere(obj, centre, r, segs=24):
    """Булево вычитание сферы (EXACT): чашка сустава / глаз."""
    s = common.add_sphere("_cut", r, loc=centre, segments=segs, rings=segs // 2)
    m = obj.modifiers.new("Cup", 'BOOLEAN')
    m.operation = 'DIFFERENCE'
    m.solver = 'EXACT'
    m.object = s
    apply_mods(obj)
    bpy.data.objects.remove(s, do_unlink=True)


def finish_wood(obj, sub=2, cuts=(), bevel_w=0.0025, mat="Wood", smooth_deg=SMOOTH_DEG):
    """Subsurf → чашки → фаска кромок чашек → сглаживание. UV назначается отдельно (uv_grain)."""
    common.assign(obj, MAT[mat])
    if sub > 0:
        common.subsurf(obj, sub)
        apply_mods(obj)
    for centre, r in cuts:
        cut_sphere(obj, centre, r)
    if cuts and bevel_w > 0.0:
        common.bevel(obj, bevel_w, 2, 35.0)
        apply_mods(obj)
    common.smooth(obj, smooth_deg)
    return obj


def uv_grain(obj, axis='Z', centre=None, scale=WOOD_UV, box=False):
    """UV-слой Grain: волокна вдоль оси детали (цилиндрическая развёртка) или кубическая для блоков."""
    me = obj.data
    while me.uv_layers:
        me.uv_layers.remove(me.uv_layers[0])
    me.uv_layers.new(name="Grain")
    if box:
        common.uv_box(obj, scale, along=axis)
    else:
        common.uv_cylinder_along(obj, axis, scale, centre=centre)
    return obj


def join_into(name, objs):
    j = common.join(objs, name)
    return j


def pin(name, centre, length, axis='Y'):
    """Стальной штифт вдоль оси сустава (Blender Y = Godot Z), торчит на 3 мм с каждой стороны гнезда."""
    rot = (math.pi / 2.0, 0.0, 0.0) if axis == 'Y' else (0.0, math.pi / 2.0, 0.0)
    o = common.add_cylinder(name, radius=PIN_R, depth=length, loc=centre, verts=10, rot=rot)
    common.apply_transforms(o, rotation=True)
    common.bevel(o, 0.001, 1)
    apply_mods(o)
    common.smooth(o, 50.0)
    uv_grain(o, 'Y', box=True, scale=1.0)
    common.assign(o, MAT["Pin"])
    return o


def ball(name, centre, r):
    o = common.add_sphere(name, r, loc=centre, segments=20, rings=10)
    common.smooth(o, 70.0)
    uv_grain(o, 'Z', box=True, scale=1.0)
    common.assign(o, MAT["Joint"])
    return o


def wrap_bands(name, x, z_list, w_of_z, d_of_z, cord_r=0.0065, tilt=0.0):
    """Обмотка: стопка торов-витков вокруг эллиптического сечения (ширина/глубина от высоты) с зазором 1 мм."""
    out = []
    for i, z in enumerate(z_list):
        w, d = w_of_z(z), d_of_z(z)
        major = 0.5 * w + cord_r + 0.001
        o = common.add_torus("%s_%d" % (name, i), major, cord_r, loc=(x, 0.0, z),
                             rot=(math.radians(tilt * (1 if i % 2 else -1)), 0.0, TAU * 0.13 * i), segs=20, ring=6)
        o.scale = (1.0, (0.5 * d + cord_r + 0.001) / major, 1.0)
        common.apply_transforms(o, rotation=True, scale=True)
        common.smooth(o, 70.0)
        out.append(o)
    j = join_into(name, out)
    uv_grain(j, 'Z', centre=(x, 0.0), scale=8.0)
    common.assign(j, MAT["Shirt"])
    return j


def shell_decal(name, src, regions, offset=0.0015, uv_scale=WOOD_UV, feather=0.35):
    """Оболочка-декаль: копия граней src, центры которых попадают в regions [(centre, r)], сдвинутая по нормалям;
    UV = Grain-развёртка источника (штрихи вдоль волокна), цвет вершин: alpha = плавное затухание к краю области."""
    me = src.data
    me.calc_loop_triangles()
    keep = []
    for p in me.polygons:
        c = src.matrix_world @ p.center
        for rc, rr in regions:
            if (c - rc).length < rr:
                keep.append(p.index)
                break
    if not keep:
        return None
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    keep_set = set(keep)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.index not in keep_set], context='FACES')
    for v in bm.verts:
        v.co += v.normal * offset
    col = bm.loops.layers.color.new("Col")
    for f in bm.faces:
        for l in f.loops:
            wc = src.matrix_world @ l.vert.co
            a = 0.0
            for rc, rr in regions:
                dd = (wc - rc).length / rr
                a = max(a, min(1.0, max(0.0, (1.0 - dd) / feather)))
            l[col] = (1.0, 1.0, 1.0, a)
    o = mesh_object(name, bm)
    o.matrix_world = src.matrix_world.copy()
    common.smooth(o, SMOOTH_DEG)
    # UV Grain источника уже скопирована bmesh-ом (слой с тем же именем); оставляем только её
    me2 = o.data
    for lay in list(me2.uv_layers):
        if lay.name != "Grain":
            me2.uv_layers.remove(lay)
    if not me2.uv_layers:
        me2.uv_layers.new(name="Grain")
    common.assign(o, MAT["Shirt_Paint"])
    return o


# ------------------------------------------------------------------------------------------------
# конечность: шар (дочерний) + лофт «под шаром → стержень → гнездо» с чашкой для шара следующей части
# ------------------------------------------------------------------------------------------------
def limb(name, x, z_top, z_bot, ball_top, ball_bot, w0, d0, w1, d1, swell=0.0, swell_pos=0.5, n=10, sub=2,
         wraps=None, paint=None):
    r_t = BALL[ball_top]
    r_b = BALL[ball_bot]
    R = HOUSING[ball_bot]
    rings = []
    for k, f in ((0.40, 0.60), (0.75, 0.88), (1.12, 1.0)):
        rings.append(sring(z_top - k * r_t, w0 * f, d0 * f, n))
    zs0 = z_top - 1.12 * r_t
    zs1 = z_bot + 1.25 * R
    steps = 4
    for i in range(1, steps + 1):
        t = i / steps
        z = zs0 + (zs1 - zs0) * t
        w = w0 + (w1 - w0) * t
        d = d0 + (d1 - d0) * t
        sw = 1.0 + swell * math.exp(-((t - swell_pos) / 0.28) ** 2)
        rings.append(sring(z, w * sw, d * sw, n))
    for th in (46.0, 66.0, 86.0, 106.0):
        tr = math.radians(th)
        rings.append(sring(z_bot + R * math.cos(tr), 2.0 * R * math.sin(tr), 2.0 * R * 0.94 * math.sin(tr), n))
    o = loft(name, [[Vector((p.x + x, p.y, p.z)) for p in r] for r in rings])
    finish_wood(o, sub=sub, cuts=[((x, 0.0, z_bot), r_b + CUP_GAP)])
    uv_grain(o, 'Z', centre=(x, 0.0))
    children = [ball(name + "_Ball", (x, 0.0, z_top), r_t), pin(name + "_Pin", (x, 0.0, z_bot), 2.0 * R * 0.94 + 0.006)]
    if wraps:
        zl, cord = wraps
        def w_of(z, zs0=zs0, zs1=zs1):
            t = min(1.0, max(0.0, (z - zs0) / (zs1 - zs0)))
            return (w0 + (w1 - w0) * t) * (1.0 + swell * math.exp(-((t - swell_pos) / 0.28) ** 2))
        def d_of(z, zs0=zs0, zs1=zs1):
            t = min(1.0, max(0.0, (z - zs0) / (zs1 - zs0)))
            return (d0 + (d1 - d0) * t) * (1.0 + swell * math.exp(-((t - swell_pos) / 0.28) ** 2))
        children.append(wrap_bands(name + "_Wrap", x, zl, w_of, d_of, cord_r=cord, tilt=3.0))
    if paint:
        dec = shell_decal(name + "_Paint", o, paint)
        if dec:
            children.append(dec)
    return o, children


# ------------------------------------------------------------------------------------------------
# кисть: шар запястья + ладонь (лофт) + 4 пальца × 3 фаланги + большой × 2, шарики суставов, лёгкий сгиб
# ------------------------------------------------------------------------------------------------
def phalanx(name, base, direction, length, w, d, n=6):
    """Капсула-фаланга от base вдоль direction (мир Blender): ширина w (поперёк, вдоль Blender −Y локально),
    толщина d (вдоль X). Скруглённые оба конца."""
    rings = []
    prof = [(0.0, 0.62), (0.08, 0.92), (0.5, 1.0), (0.92, 0.86), (1.0, 0.55)]
    for t, f in prof:
        rings.append(sring(t * length, d * f, w * f, n, cc=cc_of(n) * 1.03))
    dz = direction.normalized()
    dx = Vector((1.0, 0.0, 0.0))
    dy = dz.cross(dx).normalized()
    dx = dy.cross(dz).normalized()
    m = Matrix((dx, dy, dz)).transposed().to_4x4()
    m.translation = base
    o = loft(name, transform_rings(rings, m))
    return o


def hand(name, k):
    """k = +1 левая (x > 0), −1 правая. Ладонь висит вниз, ладонь к телу, большой палец к камере (−Y Blender)."""
    x = SX * k
    wz = WRIST_Y
    origin = Vector((x, 0.0, wz))
    # ладонь: кольца в плоскости XY (X — толщина ладони, Y — ширина поперёк пальцев), лофт вниз по Z
    rings = []
    for z_off, thick, width, exp in ((-0.026, 0.024, 0.052, 2.0), (-0.040, 0.030, 0.068, 2.4), (-0.062, 0.032, 0.084, 2.8),
                                     (-0.085, 0.032, 0.090, 3.0), (-0.105, 0.030, 0.088, 3.0), (-0.116, 0.024, 0.078, 2.6),
                                     (-0.121, 0.014, 0.060, 2.0)):
        rings.append(sring(wz + z_off, thick, width, 16, exp, cx=x - k * 0.002 * (1.0 + z_off * 20.0)))
    palm = loft(name + "_Palm", rings)
    fingers = []
    balls = []
    # 4 пальца: Blender y = −Godot z; указательный к камере (y < 0), мизинец назад
    fdefs = [(-0.034, 0.062, 0.0175), (-0.0115, 0.079, 0.019), (0.0115, 0.074, 0.019), (0.034, 0.058, 0.017)]
    fdefs = [(-y, L, w) for y, L, w in fdefs]
    for fi, (fy, L, w) in enumerate(fdefs):
        base = Vector((x - k * 0.003, fy, wz - 0.118))
        angle = 0.0
        for pi_, frac in enumerate((0.44, 0.31, 0.25)):
            angle += (14.0, 19.0, 17.0)[pi_] * (1.0 + 0.08 * fi)
            a = math.radians(angle)
            # сгиб к ладони (к телу: −k по X) вокруг Blender Y
            direction = Vector((-k * math.sin(a), 0.0, -math.cos(a)))
            pl = L * frac
            ph = phalanx("%s_F%d_%d" % (name, fi, pi_), base, direction, pl - 0.001, w * (1.0 - 0.08 * pi_), 0.016 * (1.0 - 0.07 * pi_))
            fingers.append(ph)
            base = base + direction * pl
            if pi_ < 2:
                balls.append(common.add_sphere("%s_j%d_%d" % (name, fi, pi_), 0.0052 * (1.0 - 0.1 * pi_), loc=base, segments=10, rings=5))
        balls.append(common.add_sphere("%s_k%d" % (name, fi), 0.0064, loc=Vector((x - k * 0.003, fy, wz - 0.119)), segments=10, rings=5))
    # большой палец: от передней кромки ладони (−Y), вперёд-вниз и к ладони
    tb = Vector((x + k * 0.004, -0.046, wz - 0.058))
    tdir = Vector((-k * 0.35, -0.75, -0.55)).normalized()
    t1 = phalanx(name + "_T0", tb, tdir, 0.031, 0.021, 0.018)
    tb2 = tb + tdir * 0.032
    tdir2 = Vector((-k * 0.75, -0.45, -0.50)).normalized()
    t2 = phalanx(name + "_T1", tb2, tdir2, 0.027, 0.019, 0.016)
    fingers += [t1, t2]
    balls.append(common.add_sphere(name + "_tj", 0.0064, loc=tb2, segments=10, rings=5))
    balls.append(common.add_sphere(name + "_tk", 0.0078, loc=tb, segments=10, rings=5))
    for f in fingers:
        common.subsurf(f, 1)
        apply_mods(f)
    common.subsurf(palm, 1)
    apply_mods(palm)
    # костяшки — тоже дерево (как у настоящего манекена), в одном объекте с ладонью → запекаются вместе
    h = join_into(name, [palm] + fingers + balls)
    # разворот кисти вокруг вертикали запястья: ладонь назад-внутрь (расслабленная рука), пальцы видны с камеры
    rot = Matrix.Rotation(math.radians(-k * 40.0), 4, 'Z')
    h.data.transform(Matrix.Translation(origin) @ rot @ Matrix.Translation(-origin))
    common.assign(h, MAT["Wood"])
    common.smooth(h, SMOOTH_DEG)
    uv_grain(h, 'Z', box=True)
    children = [ball(name + "_Ball", origin, BALL["wrist"])]
    return h, children


# ------------------------------------------------------------------------------------------------
# стопа: лофт вдоль −Y Blender (к камере): пятка → подъём → скруглённый носок; шар лодыжки сверху сзади
# ------------------------------------------------------------------------------------------------
def foot(name, k):
    x = HX * k
    origin = Vector((x, 0.0, ANKLE_Y))
    # кольца в плоскости XZ на позиции y (вдоль стопы): (y, width, height, centre z, exp)
    spec = [(0.072, 0.050, 0.044, 0.040, 2.0), (0.066, 0.074, 0.064, 0.036, 2.6), (0.045, 0.092, 0.076, 0.039, 3.0),
            (0.015, 0.100, 0.080, 0.040, 3.2), (-0.025, 0.102, 0.078, 0.039, 3.2), (-0.070, 0.100, 0.070, 0.035, 3.0),
            (-0.115, 0.096, 0.058, 0.029, 2.8), (-0.150, 0.090, 0.046, 0.024, 2.4), (-0.170, 0.070, 0.030, 0.017, 2.0),
            (-0.178, 0.040, 0.014, 0.012, 2.0)]
    rings = []
    for y, w, h, cz, exp in spec:
        r = sring(0.0, w, h, 12, exp)
        rings.append([Vector((x + p.x, y, cz + p.y)) for p in r])
    o = loft(name, rings)
    common.assign(o, MAT["Wood"])
    common.subsurf(o, 2)
    apply_mods(o)
    common.smooth(o, SMOOTH_DEG)
    uv_grain(o, 'Y', centre=(x, 0.04))
    children = [ball(name + "_Ball", origin, BALL["ankle"])]
    return o, children


# ------------------------------------------------------------------------------------------------
# торс: грудь (лофт с плечевым шельфом, грудной выпуклостью и желобком позвоночника) + брюшной шар + таз;
# чашки: шея, плечи ×2, брюшной шар (сверху и снизу), бёдра ×2; штифты плеч и бёдер; ремень наискось; мазки краски
# ------------------------------------------------------------------------------------------------
# v3.1 (28.09): грудь круглее — меньше отношение ширин шельф/талия (0.42/0.24 = 1.75 вместо 0.47/0.215 = 2.2), полнее
# глубина в средних кольцах (0.22 вместо 0.20), плечевой «шельф» — выпуклая шапка из 6 колец вместо плоской полки с углом.
# Ширина в зоне висящей руки (z 1.30–1.40) ограничена: рука x ±0.22 шириной ≤0.105 → грудь ≤ ~0.33–0.35, иначе клип в позе покоя.
# Итерация 3: показатели суперэллипса средних колец ниже (2.25–2.5 вместо 2.4–2.7) — сечение круглее, «угол» перед/бок мягче;
# крайние ширина/глубина не меняются (чашки плеч и зазор до руки те же).
CHEST_SPEC = [(1.140, 0.240, 0.140, 2.1), (1.156, 0.278, 0.166, 2.15), (1.190, 0.300, 0.190, 2.2), (1.235, 0.314, 0.208, 2.25),
              (1.290, 0.326, 0.220, 2.3), (1.340, 0.328, 0.220, 2.3), (1.375, 0.346, 0.214, 2.35), (1.400, 0.376, 0.204, 2.45),
              (1.418, 0.408, 0.192, 2.5), (1.432, 0.418, 0.176, 2.45), (1.443, 0.392, 0.150, 2.3), (1.452, 0.320, 0.115, 2.2),
              (1.458, 0.210, 0.080, 2.0), (1.461, 0.120, 0.055, 2.0)]
ABD_C, ABD_R = 1.085, 0.080
PELVIS_SPEC = [(0.876, 0.220, 0.130, 2.6), (0.892, 0.270, 0.160, 2.8), (0.920, 0.300, 0.180, 3.0), (0.960, 0.300, 0.180, 3.0),
               (0.995, 0.286, 0.170, 2.8), (1.020, 0.250, 0.150, 2.6), (1.031, 0.180, 0.100, 2.0)]


def chest_shape(a, x, y, z):
    if y < 0.0:   # перед: две грудные выпуклости + желобок грудины
        hb = math.exp(-((z - 1.325) / 0.055) ** 2)
        bump = 0.011 * hb * (math.exp(-((x - 0.078) / 0.05) ** 2) + math.exp(-((x + 0.078) / 0.05) ** 2))
        groove = 0.005 * hb * math.exp(-(x / 0.022) ** 2)
        y -= (bump - groove) * min(1.0, -y / 0.05)
    else:         # спина: желобок позвоночника
        hs = math.exp(-((z - 1.29) / 0.10) ** 2)
        y -= 0.005 * hs * math.exp(-(x / 0.024) ** 2) * min(1.0, y / 0.05)
    return x, y


def _interp_spec(spec, z):
    for (z0, w0, d0, e0), (z1, w1, d1, e1) in zip(spec, spec[1:]):
        if z0 <= z <= z1:
            t = (z - z0) / (z1 - z0)
            return w0 + (w1 - w0) * t, d0 + (d1 - d0) * t, e0 + (e1 - e0) * t
    z0, w0, d0, e0 = spec[0] if z < spec[0][0] else spec[-1]
    return w0, d0, e0


def chest_surface(a, z, off=0.0):
    """Точка на поверхности груди (с выпуклостями) под азимутом a на высоте z, сдвинутая наружу на off."""
    w, d, e = _interp_spec(CHEST_SPEC, z)
    c, s = math.cos(a), math.sin(a)
    x = 0.5 * w * math.copysign(abs(c) ** (2.0 / e), c)
    y = 0.5 * d * math.copysign(abs(s) ** (2.0 / e), s)
    x, y = chest_shape(a, x, y, z)
    nrm = Vector((x / max(1e-6, (0.5 * w) ** 2), y / max(1e-6, (0.5 * d) ** 2))).normalized()
    return Vector((x + nrm.x * off, y + nrm.y * off, z))


def chest_strap(name):
    """Ремень наискось: замкнутая полоса по поверхности груди, высота меняется по косинусу азимута
    (высоко у левого плеча спереди, низко справа сзади)."""
    segs = 48
    width, thick = 0.040, 0.006
    z_mid, amp, a0 = 1.285, 0.105, math.radians(125.0)   # максимум высоты при a = a0 (перед-слева: x>0, y<0)
    bm = bmesh.new()
    rings = []
    for i in range(segs):
        a = TAU * i / segs
        z = z_mid + amp * math.cos(a - a0)
        z = min(1.40, max(1.17, z))
        p0 = chest_surface(a, z, 0.0025)
        p1 = chest_surface(a, z, 0.0025 + thick)
        # локальный «верх» полосы: вдоль поверхности, перпендикулярно направлению пути → приближённо по Z
        up = Vector((0.0, 0.0, 1.0))
        # наклон полосы к поверхности: касательная пути
        a2 = TAU * (i + 1) / segs
        z2 = min(1.40, max(1.17, z_mid + amp * math.cos(a2 - a0)))
        tng = (chest_surface(a2, z2, 0.0025) - p0).normalized()
        nrm = (p1 - p0).normalized()
        up = nrm.cross(tng).normalized()
        if up.z < 0:
            up = -up
        hw = 0.5 * width
        rings.append([bm.verts.new(p0 - up * hw), bm.verts.new(p1 - up * hw), bm.verts.new(p1 + up * hw), bm.verts.new(p0 + up * hw)])
    for i in range(segs):
        a, b = rings[i], rings[(i + 1) % segs]
        for j in range(4):
            bm.faces.new((a[j], b[j], b[(j + 1) % 4], a[(j + 1) % 4]))
    o = mesh_object(name, bm)
    common.smooth(o, 50.0)
    uv_grain(o, 'Z', centre=(0.0, 0.0), scale=8.0)
    common.assign(o, MAT["Shirt"])
    return o


def torso():
    origin = B(0, TORSO_C, 0)
    chest = loft("Torso_Chest", [sring(z, w, d, 20, e, shape=chest_shape) for z, w, d, e in CHEST_SPEC])
    finish_wood(chest, sub=2, cuts=[((0.0, 0.0, NECK_Y), BALL["neck"] + CUP_GAP),
                                    ((SX, 0.0, SHOULDER_Y), BALL["shoulder"] + CUP_GAP),
                                    ((-SX, 0.0, SHOULDER_Y), BALL["shoulder"] + CUP_GAP),
                                    ((0.0, 0.0, ABD_C), ABD_R + CUP_GAP)])
    pelvis = loft("Torso_Pelvis", [sring(z, w, d, 14, e) for z, w, d, e in PELVIS_SPEC])
    finish_wood(pelvis, sub=2, cuts=[((HX, 0.0, HIP_Y), BALL["hip"] + CUP_GAP),
                                     ((-HX, 0.0, HIP_Y), BALL["hip"] + CUP_GAP),
                                     ((0.0, 0.0, ABD_C), ABD_R + CUP_GAP)])
    abd = common.add_sphere("Torso_Abdomen", ABD_R, loc=(0.0, 0.0, ABD_C), segments=20, rings=10)
    common.assign(abd, MAT["Wood"])
    common.smooth(abd, 70.0)
    t = join_into("Torso", [chest, abd, pelvis])
    uv_grain(t, 'Z', centre=(0.0, 0.0))
    children = [pin("Torso_PinS_L", (SX, 0.0, SHOULDER_Y), 2.0 * BALL["shoulder"] + 0.010),
                pin("Torso_PinS_R", (-SX, 0.0, SHOULDER_Y), 2.0 * BALL["shoulder"] + 0.010),
                pin("Torso_PinH_L", (HX, 0.0, HIP_Y), 0.180 + 0.008),
                pin("Torso_PinH_R", (-HX, 0.0, HIP_Y), 0.180 + 0.008),
                chest_strap("Torso_Strap")]
    dec = shell_decal("Torso_Paint", t, [(Vector((-0.06, -0.09, 1.31)), 0.125), (Vector((0.09, -0.08, 0.95)), 0.075)])
    if dec:
        children.append(dec)
    return t, children, origin


# ------------------------------------------------------------------------------------------------
# голова: яйцо (лофт по профилю), два сверлёных глаза, шейка, шар шеи; FacePlate — колпак поверхности яйца
# ------------------------------------------------------------------------------------------------
HEAD_H = 0.300          # высота яйца
HEAD_ZC = HEAD_C - 0.005   # центр яйца (Blender z = Godot y): низ 1.475 — накрывает шар шеи
HEAD_R0 = 0.134
FACE_AXIS = Vector((0.0, -1.0, -0.06)).normalized()
EYE_Z = 1.665
EYE_X = 0.036
EYE_R = 0.0085


def egg_r(z):
    t = (z - HEAD_ZC) / (0.5 * HEAD_H)
    t = max(-1.0, min(1.0, t))
    return HEAD_R0 * math.sqrt(max(0.0, 1.0 - t * t)) * (1.0 + 0.14 * t) * 0.92


def egg_point(d):
    """Пересечение луча из центра яйца по направлению d с поверхностью яйца (бисекция по длине)."""
    lo, hi = 0.0, 0.2
    c = Vector((0.0, 0.0, HEAD_ZC))
    for _ in range(40):
        mid = 0.5 * (lo + hi)
        p = c + d * mid
        inside = math.hypot(p.x, p.y) < egg_r(p.z) and abs(p.z - HEAD_ZC) < 0.5 * HEAD_H
        if inside:
            lo = mid
        else:
            hi = mid
    return c + d * lo


def eye_centres():
    out = []
    for sx in (EYE_X, -EYE_X):
        r = egg_r(EYE_Z)
        y = -math.sqrt(max(0.0, r * r - sx * sx))
        out.append(Vector((sx, y + 0.0035, EYE_Z)))
    return out


def face_plate():
    """Сетка 10×10 по поверхности яйца вокруг FACE_AXIS (до ~36°), на 0.6 мм над деревом, толщина 1 мм;
    UV Bake — планарные 0..1 (под фото), UV Grain — как у головы; глаза просверлены и в плашке."""
    ax = FACE_AXIS
    right = Vector((1.0, 0.0, 0.0))
    up = right.cross(ax).normalized()
    right = ax.cross(up).normalized()
    n = 12
    ang = math.radians(36.0)
    bm = bmesh.new()
    grid = []
    for j in range(n + 1):
        row = []
        for i in range(n + 1):
            u = (i / n) * 2.0 - 1.0
            v = (j / n) * 2.0 - 1.0
            # круглый контур: сжимаем квадрат к диску
            rr = math.hypot(u, v)
            if rr > 1.0:
                u, v = u / rr, v / rr
            d = (ax * math.cos(ang * rr) + (right * u + up * v).normalized() * math.sin(ang * rr)) if rr > 1e-6 else ax
            p = egg_point(d.normalized())
            p = p + d.normalized() * 0.0010
            row.append(bm.verts.new(p))
        grid.append(row)
    for j in range(n):
        for i in range(n):
            q = (grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i])
            if len({v.co.to_tuple(6) for v in q}) >= 3:
                bm.faces.new(q)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-6)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.normal_update()
    if sum(f.normal.dot(ax) for f in bm.faces) < 0.0:
        bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
    uvb = bm.loops.layers.uv.new("Bake")
    xs = [v.co.x for v in bm.verts]
    zs = [v.co.z for v in bm.verts]
    x0, x1, z0, z1 = min(xs), max(xs), min(zs), max(zs)
    for f in bm.faces:
        for l in f.loops:
            l[uvb].uv = ((l.vert.co.x - x0) / (x1 - x0), (l.vert.co.z - z0) / (z1 - z0))
    fp = mesh_object("FacePlate", bm)
    common.assign(fp, MAT["Face"])
    MAT["Face"].use_backface_culling = True       # односторонняя плашка над яйцом (тыл не виден; запекается только лицо)
    for c in eye_centres():
        cut_sphere(fp, c, EYE_R, segs=20)
    common.smooth(fp, SMOOTH_DEG)
    # Grain — вторым слоем, цилиндрическая как у головы
    me = fp.data
    me.uv_layers.new(name="Grain")
    me.uv_layers.active = me.uv_layers["Grain"]
    _uv_cyl_into_layer(fp, "Grain", 'Z', (0.0, 0.0), WOOD_UV)
    return fp


def _uv_cyl_into_layer(obj, layer, axis, centre, scale):
    """uv_cylinder_along пишет в uv_layers[0]; временно переставляем нужный слой первым через копирование."""
    me = obj.data
    src = me.uv_layers[0]
    common.uv_cylinder_along(obj, axis, scale, centre=centre)   # пишет в слой 0
    if src.name != layer:
        dst = me.uv_layers[layer]
        tmp = [(l.uv.x, l.uv.y) for l in src.data]
        # слой 0 содержал старые данные? — uv_cylinder_along только что перезаписал слой 0 новыми; меняем местами
        old = [(l.uv.x, l.uv.y) for l in dst.data]
        for l, uv in zip(dst.data, tmp):
            l.uv = uv
        for l, uv in zip(src.data, old):
            l.uv = uv


def head():
    origin = B(0, NECK_Y, 0)
    zb, zt = HEAD_ZC - 0.5 * HEAD_H, HEAD_ZC + 0.5 * HEAD_H
    rings = []
    ts = [-0.98, -0.90, -0.76, -0.56, -0.32, -0.06, 0.20, 0.44, 0.66, 0.84, 0.95, 0.99]
    for t in ts:
        z = HEAD_ZC + 0.5 * HEAD_H * t
        r = egg_r(z)
        rings.append(sring(z, 2.0 * r, 2.0 * r * 1.04, 14, 2.0))   # чуть глубже, чем шире (затылок)
    egg = loft("Head_Egg", rings)
    neck = common.add_cylinder("Head_Neck", radius=0.026, depth=0.06, loc=(0.0, 0.0, NECK_Y + 0.03), verts=16)
    common.assign(neck, MAT["Wood"])
    common.smooth(neck, 50.0)
    finish_wood(egg, sub=2, cuts=[(c, EYE_R) for c in eye_centres()], bevel_w=0.0012)
    h = join_into("Head", [egg, neck])
    uv_grain(h, 'Z', centre=(0.0, 0.0))
    fp = face_plate()
    children = [ball("Head_Ball", (0.0, 0.0, NECK_Y), BALL["neck"]), fp]
    return h, children, origin


# ------------------------------------------------------------------------------------------------
# запекание износа на деталь
# ------------------------------------------------------------------------------------------------
BAKE_DIR = os.path.join(tempfile.gettempdir(), "ragdoll_doll_bake", TONE)


def _smart_uv(obj, layer="Bake"):
    me = obj.data
    if layer not in me.uv_layers:
        me.uv_layers.new(name=layer)
    me.uv_layers.active = me.uv_layers[layer]
    me.uv_layers[layer].active_render = True
    select_only(obj)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(66.0), island_margin=0.006, area_weight=0.0, correct_aspect=True, scale_to_bounds=False)
    bpy.ops.object.mode_set(mode='OBJECT')


class _N:
    def __init__(self, nt):
        self.nt = nt
        self.i = 0

    def new(self, typ, **props):
        n = self.nt.nodes.new(typ)
        for k, v in props.items():
            setattr(n, k, v)
        self.i += 1
        n.location = ((self.i % 12) * 220, -(self.i // 12) * 300)
        return n

    def link(self, a, b):
        self.nt.links.new(a, b)

    def math(self, op, a, b=None, c=None, clamp=False):
        n = self.new('ShaderNodeMath', operation=op, use_clamp=bool(clamp))
        self._plug(n.inputs[0], a)
        self._plug(n.inputs[1], b)
        self._plug(n.inputs[2], c)
        return n.outputs[0]

    def _plug(self, sock, v):
        if v is None:
            return
        if isinstance(v, bpy.types.NodeSocket):
            self.link(v, sock)
        elif sock.type == 'RGBA':
            sock.default_value = tuple(v) if not isinstance(v, (int, float)) else (v, v, v, 1.0)
        elif sock.type == 'VECTOR':
            sock.default_value = tuple(v)[:3] if not isinstance(v, (int, float)) else (v, v, v)
        else:
            sock.default_value = float(v)

    def mixc(self, a, b, t, blend='MIX'):
        n = self.new('ShaderNodeMix', data_type='RGBA', blend_type=blend, clamp_factor=True)
        self._plug(n.inputs[0], t)
        self._plug(n.inputs[6], a)
        self._plug(n.inputs[7], b)
        return n.outputs[2]

    def sstep(self, x, e0, e1):
        n = self.new('ShaderNodeMapRange', data_type='FLOAT', interpolation_type='SMOOTHSTEP', clamp=True)
        self._plug(n.inputs['Value'], x)
        n.inputs['From Min'].default_value = e0
        n.inputs['From Max'].default_value = e1
        return n.outputs['Result']

    def noise(self, vec, scale, detail=2.0, rough=0.5):
        n = self.new('ShaderNodeTexNoise', noise_dimensions='3D')
        n.inputs['Scale'].default_value = scale
        n.inputs['Detail'].default_value = detail
        n.inputs['Roughness'].default_value = rough
        self.link(vec, n.inputs['Vector'])
        return n.outputs['Fac']

    def mapping(self, vec, scale=(1, 1, 1), loc=(0, 0, 0)):
        n = self.new('ShaderNodeMapping', vector_type='POINT')
        n.inputs['Scale'].default_value = scale
        n.inputs['Location'].default_value = loc
        self.link(vec, n.inputs['Vector'])
        return n.outputs['Vector']


def _new_float_img(name, size):
    img = bpy.data.images.new(name, size, size, alpha=False, float_buffer=True)
    img.colorspace_settings.name = 'Non-Color'
    return img


def bake_part(obj, part_name, seed, size, has_bake_uv=False, mat_name=None):
    """AO → composite (тайл × AO × износ кромок × царапины × пыль) → EMIT albedo, ROUGHNESS, NORMAL в UV Bake.
    Возвращает новый материал с запечёнными картами; UV Grain удаляется."""
    t0 = time.time()
    scn = bpy.context.scene
    if not has_bake_uv:
        _smart_uv(obj, "Bake")
    else:
        me = obj.data
        me.uv_layers.active = me.uv_layers["Bake"]
        me.uv_layers["Bake"].active_render = True
    tile = os.path.join(common.PBR_DIR, WOOD_FOLDER)
    mat = bpy.data.materials.new("_bake_" + part_name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    N = _N(nt)
    out = N.new('ShaderNodeOutputMaterial')
    bsdf = N.new('ShaderNodeBsdfPrincipled')
    emit = N.new('ShaderNodeEmission')
    uv_g = N.new('ShaderNodeUVMap', uv_map="Grain")
    uv_b = N.new('ShaderNodeUVMap', uv_map="Bake")

    def tex(fname, non_color, uv):
        n = N.new('ShaderNodeTexImage')
        n.image = common._load_packed(os.path.join(tile, fname), non_color)
        n.extension = 'REPEAT'
        N.link(uv.outputs['UV'], n.inputs['Vector'])
        return n

    alb = tex('albedo.png', False, uv_g)
    rgh = tex('roughness.png', True, uv_g)
    nrm = tex('normal.png', True, uv_g)
    ao_img = _new_float_img("_ao_" + part_name, size)
    ao_n = N.new('ShaderNodeTexImage')
    ao_n.image = ao_img
    N.link(uv_b.outputs['UV'], ao_n.inputs['Vector'])
    target = N.new('ShaderNodeTexImage')
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    select_only(obj)
    scn.render.bake.margin = 6
    scn.render.bake.use_clear = True
    scn.render.bake.use_selected_to_active = False
    scn.render.bake.normal_space = 'TANGENT'

    # 1) AO
    nt.nodes.active = target
    target.image = ao_img
    N.link(bsdf.outputs['BSDF'], out.inputs['Surface'])
    scn.cycles.samples = 24
    bpy.ops.object.bake(type='AO')
    # 2) composite
    geo = N.new('ShaderNodeNewGeometry')
    tc = N.new('ShaderNodeTexCoord')
    ao = ao_n.outputs['Color']
    ao_f = N.math('POWER', ao, 1.4)
    edge = N.sstep(geo.outputs['Pointiness'], 0.505, 0.60)
    crev = N.sstep(geo.outputs['Pointiness'], 0.485, 0.42)
    obj_v = N.mapping(tc.outputs['Object'], scale=(1, 1, 1), loc=(seed * 0.37, seed * 0.11, seed * 0.23))
    var = N.noise(N.mapping(obj_v, scale=(3, 3, 3)), 1.0, detail=2.0)
    fine = N.noise(N.mapping(obj_v, scale=(40, 40, 40)), 1.0, detail=2.0)
    scr_n = N.noise(N.mapping(obj_v, scale=(110, 110, 9)), 1.0, detail=1.0)
    gate_lo = 0.53 if TONE == "light" else 0.56          # на тёмном орехе светлые царапины заметнее — их меньше
    scr_gate = N.sstep(N.noise(N.mapping(obj_v, scale=(5, 5, 2.5)), 1.0, detail=1.0), gate_lo, gate_lo + 0.08)
    scratch = N.math('MULTIPLY', N.sstep(scr_n, 0.636, 0.648), scr_gate)
    chip_n = N.noise(N.mapping(obj_v, scale=(45, 45, 45)), 1.0, detail=3.0, rough=0.6)
    chip = N.math('MULTIPLY', N.sstep(chip_n, 0.755 if TONE == "light" else 0.775, 0.80), N.sstep(edge, 0.15, 0.5))
    col = N.mixc(alb.outputs['Color'], N.mixc(alb.outputs['Color'], (0.5, 0.5, 0.5, 1.0), 0.5, 'MULTIPLY'), 0.0)
    col = N.mixc(col, N.mixc(col, (1.0, 1.0, 1.0, 1.0), 0.0), 0.0)
    # тональная вариация детали ±7 %
    tone_f = N.math('MULTIPLY_ADD', var, 0.16, 0.92)
    col = N.mixc(col, (0.0, 0.0, 0.0, 1.0), N.math('SUBTRACT', 1.0, tone_f), 'MIX')
    # AO: затемнение полостей
    ao_dark = N.math('MULTIPLY_ADD', ao_f, 0.62, 0.38)
    col = N.mixc(col, (0.0, 0.0, 0.0, 1.0), N.math('SUBTRACT', 1.0, ao_dark), 'MIX')
    # пыль в углублениях
    dust_m = N.math('MULTIPLY', N.math('POWER', N.math('SUBTRACT', 1.0, ao), 2.0), 0.55)
    dust_m = N.math('ADD', dust_m, N.math('MULTIPLY', crev, 0.25), clamp=True)
    dust_c = (0.60, 0.55, 0.48, 1.0) if TONE == "light" else (0.42, 0.37, 0.31, 1.0)
    col = N.mixc(col, dust_c, dust_m)
    # потёртости кромок: светлее (сколота грязь/патина), на орехе — заметно светлее
    wear_c = N.mixc(col, (1.0, 0.98, 0.94, 1.0), 0.28 if TONE == "light" else 0.42, 'MIX')
    col = N.mixc(col, wear_c, N.math('MULTIPLY', edge, N.math('MULTIPLY_ADD', fine, 0.5, 0.6)))
    # царапины и сколы
    scr_c = N.mixc(col, (0.35, 0.30, 0.25, 1.0) if TONE == "light" else (0.80, 0.66, 0.50, 1.0), 0.55 if TONE == "light" else 0.45, 'MIX')
    col = N.mixc(col, scr_c, N.math('ADD', N.math('MULTIPLY', scratch, 0.85), N.math('MULTIPLY', chip, 0.7), clamp=True))
    # шероховатость
    rough = N.math('MULTIPLY', rgh.outputs['Color'], N.math('SUBTRACT', 0.95, N.math('MULTIPLY', edge, 0.40)))
    rough = N.math('ADD', rough, N.math('MULTIPLY', dust_m, 0.30))
    rough = N.math('ADD', rough, N.math('MULTIPLY', scratch, 0.15), clamp=True)
    # нормаль: тайл + bump царапин
    nm = N.new('ShaderNodeNormalMap', space='TANGENT')
    nm.inputs['Strength'].default_value = 1.0
    N.link(nrm.outputs['Color'], nm.inputs['Color'])
    bump = N.new('ShaderNodeBump')
    bump.inputs['Strength'].default_value = 0.6
    bump.inputs['Distance'].default_value = 0.0012
    bump.invert = True
    N.link(N.math('ADD', scratch, N.math('MULTIPLY', chip, 0.8)), bump.inputs['Height'])
    N.link(nm.outputs['Normal'], bump.inputs['Normal'])
    N.link(bump.outputs['Normal'], bsdf.inputs['Normal'])
    N.link(rough, bsdf.inputs['Roughness'])
    N.link(col, bsdf.inputs['Base Color'])

    def bake_to(kind, img_name, samples, use_emit=None):
        img = _new_float_img(img_name, size)
        target.image = img
        nt.nodes.active = target
        for l in list(out.inputs['Surface'].links):
            nt.links.remove(l)
        if use_emit is not None:
            for l in list(emit.inputs['Color'].links):
                nt.links.remove(l)
            N.link(use_emit, emit.inputs['Color'])
            N.link(emit.outputs['Emission'], out.inputs['Surface'])
        else:
            N.link(bsdf.outputs['BSDF'], out.inputs['Surface'])
        scn.cycles.samples = samples
        bpy.ops.object.bake(type=kind)
        arr = T._read_float(img)
        bpy.data.images.remove(img)
        return arr

    os.makedirs(BAKE_DIR, exist_ok=True)
    a = bake_to('EMIT', "_alb", 4, use_emit=col)
    a8 = T._linear_to_srgb8(a)
    a8[..., 3] = 255
    p_alb = os.path.join(BAKE_DIR, part_name + "_albedo.png")
    T.save_rgba8(p_alb, a8)
    r = bake_to('ROUGHNESS', "_rgh", 1)
    import numpy as np
    r8 = np.clip(np.rint(np.clip(r, 0, 1) * 255.0), 0, 255).astype(np.uint8)
    r8[..., 1] = r8[..., 0]
    r8[..., 2] = r8[..., 0]
    r8[..., 3] = 255
    p_rgh = os.path.join(BAKE_DIR, part_name + "_roughness.png")
    T.save_rgba8(p_rgh, r8)
    nn = bake_to('NORMAL', "_nrm", 1)
    n8 = np.clip(np.rint(np.clip(nn, 0, 1) * 255.0), 0, 255).astype(np.uint8)
    n8[..., 3] = 255
    p_nrm = os.path.join(BAKE_DIR, part_name + "_normal.png")
    T.save_rgba8(p_nrm, n8)
    bpy.data.images.remove(ao_img)
    bpy.data.materials.remove(mat)
    # финальный материал
    fm = bpy.data.materials.new(mat_name or ("Wood_" + part_name))
    fm.use_nodes = True
    nt = fm.node_tree
    nt.nodes.clear()
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    bsdf = nt.nodes.new('ShaderNodeBsdfPrincipled')
    nt.links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
    ta = nt.nodes.new('ShaderNodeTexImage')
    ta.image = common._load_packed(p_alb)
    nt.links.new(ta.outputs['Color'], bsdf.inputs['Base Color'])
    tr = nt.nodes.new('ShaderNodeTexImage')
    tr.image = common._load_packed(p_rgh, True)
    nt.links.new(tr.outputs['Color'], bsdf.inputs['Roughness'])
    tn = nt.nodes.new('ShaderNodeTexImage')
    tn.image = common._load_packed(p_nrm, True)
    nmn = nt.nodes.new('ShaderNodeNormalMap')
    nmn.space = 'TANGENT'
    nt.links.new(tn.outputs['Color'], nmn.inputs['Color'])
    nt.links.new(nmn.outputs['Normal'], bsdf.inputs['Normal'])
    obj.data.materials.clear()
    obj.data.materials.append(fm)
    me = obj.data
    if "Grain" in me.uv_layers:
        me.uv_layers.remove(me.uv_layers["Grain"])
    me.uv_layers["Bake"].name = "UVMap"
    print("  baked %-12s %4d² in %5.1fs  albedo mean %s" % (part_name, size, time.time() - t0, a8[..., :3].reshape(-1, 3).mean(0).round(1)))
    return fm


def setup_bake_scene():
    scn = T._setup_cycles(4)
    if scn.world is None:
        scn.world = bpy.data.worlds.new("World")
    scn.world.light_settings.distance = 0.22
    return scn


# ------------------------------------------------------------------------------------------------
# сборка
# ------------------------------------------------------------------------------------------------
def build():
    common.reset_scene()
    make_materials()
    parts = {}    # name -> (wood_obj, children, origin)
    want = lambda n: (not ONLY) or (n in ONLY)
    if want("Head"):
        parts["Head"] = head()
    if want("Torso"):
        parts["Torso"] = torso()
    for s, k in (("L", 1.0), ("R", -1.0)):
        sx, hx = SX * k, HX * k
        if want("UpperArm_" + s):
            o, ch = limb("UpperArm_" + s, sx, SHOULDER_Y, ELBOW_Y, "shoulder", "elbow", 0.105, 0.085, 0.085, 0.070, swell=0.04, swell_pos=0.50,
                         paint=[(Vector((sx + k * 0.05, -0.01, 1.30)), 0.075)])
            parts["UpperArm_" + s] = (o, ch, B(sx, SHOULDER_Y, 0))
        if want("LowerArm_" + s):
            o, ch = limb("LowerArm_" + s, sx, ELBOW_Y, WRIST_Y, "elbow", "wrist", 0.088, 0.074, 0.072, 0.062, swell=0.06, swell_pos=0.3,
                         wraps=([WRIST_Y + 0.060 + 0.0145 * i for i in range(5)], 0.0072))
            parts["LowerArm_" + s] = (o, ch, B(sx, ELBOW_Y, 0))
        if want("Hand_" + s):
            o, ch = hand("Hand_" + s, k)
            parts["Hand_" + s] = (o, ch, B(sx, WRIST_Y, 0))
        if want("UpperLeg_" + s):
            o, ch = limb("UpperLeg_" + s, hx, HIP_Y, KNEE_Y, "hip", "knee", 0.154, 0.130, 0.114, 0.102, swell=0.05, swell_pos=0.45,
                         paint=[(Vector((hx, -0.05, 0.70)), 0.085)] if s == "R" else None)
            parts["UpperLeg_" + s] = (o, ch, B(hx, HIP_Y, 0))
        if want("LowerLeg_" + s):
            o, ch = limb("LowerLeg_" + s, hx, KNEE_Y, ANKLE_Y, "knee", "ankle", 0.114, 0.102, 0.094, 0.084, swell=0.11, swell_pos=0.28,
                         wraps=([ANKLE_Y + 0.070 + 0.0145 * i for i in range(4)], 0.0072))
            parts["LowerLeg_" + s] = (o, ch, B(hx, KNEE_Y, 0))
        if want("Foot_" + s):
            o, ch = foot("Foot_" + s, k)
            parts["Foot_" + s] = (o, ch, B(hx, ANKLE_Y, 0))
    return parts


def bake_all(parts):
    setup_bake_scene()
    base = ARGS["size"]
    seed = 1.0
    for name, (wood, children, origin) in parts.items():
        key = name.split("_")[0]
        size = int(base * BAKE_SIZE.get(key, 0.5))
        bake_part(wood, name, seed, size)
        seed += 1.0
        for c in children:
            if c.name == "FacePlate":
                bake_part(c, "FacePlate", seed, int(base * BAKE_SIZE["FacePlate"]), has_bake_uv=True, mat_name="Face")
                seed += 1.0


def assemble(parts):
    """origin частей и детей в сустав, дети — под деревянный объект."""
    for name, (wood, children, origin) in parts.items():
        common.set_origin(wood, origin)
        for c in children:
            common.set_origin(c, origin)
            common.parent(c, wood)


def tri_count(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


def export_all(parts):
    os.makedirs(OUT_DIR, exist_ok=True)
    roots = [w for (w, c, o) in parts.values()]
    rest = {p.name: p.location.copy() for p in roots}
    for p in roots:
        p.location = (0.0, 0.0, 0.0)
        common.export_glb(os.path.join(OUT_DIR, p.name + ".glb"), [p])
        p.location = rest[p.name]
    if not ONLY:
        # полная кукла (все 14 частей в позе покоя) — только для просмотра; в full/ лежит .gdignore, Godot её не импортирует
        full_dir = OUT_DIR if ARGS["out"] else os.path.join(OUT_ROOT, "full")
        os.makedirs(full_dir, exist_ok=True)
        if not ARGS["out"]:
            open(os.path.join(full_dir, ".gdignore"), "a").close()
        common.export_glb(os.path.join(full_dir, TONE + ".glb"), roots)


def preview_render(tag):
    scn = bpy.context.scene
    scn.render.engine = 'BLENDER_WORKBENCH'
    scn.display.shading.light = 'STUDIO'
    scn.display.shading.color_type = 'TEXTURE'
    scn.display.shading.show_cavity = True
    scn.display.shading.cavity_type = 'BOTH'
    scn.display.shading.show_shadows = True
    scn.display.shading.show_specular_highlight = True
    scn.render.resolution_x, scn.render.resolution_y = 1100, 900
    scn.render.film_transparent = False
    cam_data = bpy.data.cameras.new("Cam")
    cam = bpy.data.objects.new("Cam", cam_data)
    scn.collection.objects.link(cam)
    scn.camera = cam
    out_dir = ARGS["out"] or os.path.join(tempfile.gettempdir(), "ragdoll_doll_bake")   # не в assets: Godot импортирует всё под res://
    os.makedirs(out_dir, exist_ok=True)
    views = [("front", Vector((0.0, -4.6, 1.0)), Vector((0.0, 0.0, 0.92)), 32.0),
             ("closeup", Vector((-0.75, -1.35, 1.55)), Vector((0.0, 0.0, 1.30)), 38.0),
             ("hand", Vector((0.45, -0.55, 0.85)), Vector((0.22, 0.0, 0.78)), 30.0),
             ("handfront", Vector((0.22, -0.9, 0.78)), Vector((0.22, 0.0, 0.78)), 22.0),
             ("side", Vector((3.6, -1.2, 1.0)), Vector((0.0, 0.0, 0.92)), 34.0)]
    for vname, pos, tgt, fov in views:
        cam.location = pos
        d = (tgt - pos).normalized()
        cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
        cam_data.lens_unit = 'FOV'
        cam_data.angle = math.radians(fov)
        scn.render.filepath = os.path.join(out_dir, "_preview_%s_%s.png" % (tag, vname))
        bpy.ops.render.render(write_still=True)
        print("preview", scn.render.filepath)


if __name__ == "__main__":
    t_start = time.time()
    parts = build()
    print("built %d parts in %.1fs" % (len(parts), time.time() - t_start))
    if ARGS["bake"]:
        bake_all(parts)
    assemble(parts)
    per = {}
    for name, (wood, children, origin) in parts.items():
        per[name] = tri_count(wood) + sum(tri_count(c) for c in children)
    total = sum(per.values())
    print("TRIS per part:", per)
    print("TRIS total:", total, "(budget %d)" % TRI_BUDGET)
    if ARGS["render"]:
        preview_render(TONE)
    if total > TRI_BUDGET and not ONLY:
        print("ERROR: over budget")
        sys.exit(2)
    export_all(parts)
    print("PARTS:", sorted(parts), "children:", {n: [c.name for c in ch] for n, (w, ch, o) in parts.items()})
    print("DONE in %.1fs" % (time.time() - t_start))
