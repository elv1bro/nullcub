#!/usr/bin/env python3
"""THE SCRAP (биом 1 «Свалка»), лист 01 «Scrap & Bodies» — ассеты №001–020 (docs/refs/biomes/01-scrap/sheet-01.jpg,
таблица «Лист 01» в LIST.md) и библиотека низкополигональных кусков хлама. Настоящие меши Blender 4.5 с PBR-наборами
Свалки из assets/textures/pbr (rust_metal, rust_painted_red, scrap_wood, scrap_dirt, brass_worn — печёт
tools/blender/textures.py) и общими (iron, wood, wood_dark, walnut_dark, maple_light, rope, fabric_red, fabric_blue,
cloth_wrap, painted_red); корона — декаль assets/textures/decals/crown.png (alpha clip → в glTF alphaMode MASK).

Запуск (headless):
    /Applications/Blender.app/Contents/MacOS/Blender -b --python godot/tools/blender/scrap_bodies.py [-- bits | bodies | Имя …]
        → godot/assets/models/scrap/bits/<Name>.glb      куски (≤ 600 треугольников; скрипт падает при превышении)
        → godot/assets/models/scrap/bodies/<Name>.glb    ассеты №001–020 (≤ 3000; Scrap_Heap_Medium ≤ 5000, Massive ≤ 12000)
        → godot/assets/models/scrap/bits/physics.json, …/bodies/physics.json   выпуклые оболочки и срезы коллизии (см. ниже)
    … -- render           контактные рендеры ячеек (читает экспортированные glb + physics.json) → <tmp>/scrap_sheet01/
    python3 godot/tools/blender/scrap_bodies.py --compose   (системный python3 + Pillow) → docs/plan-demo/img/
                          scrap-sheet01-v1.png (сетка 5 × 4 как на листе, рядом кукла-манекен 1.8 м) и scrap-bits-v1.png
Переменные окружения: SCRAP_TEX_BITS (512) / SCRAP_TEX_BODIES (1024) — размер текстур, вшиваемых в glb кусков / ассетов;
PROPS_IMG (WEBP), PROPS_CACHE — как в props.py; SCRAP_RENDER_DIR — папка ячеек рендера; SCRAP_FLAT=1 — принудительно плоские
материалы. Если PBR-папки Свалки ещё не испечены, материалы с теми же именами строятся плоскими (скрипт печатает список).

Соглашения (ASSET_PIPELINE.md, common.py): метры; Blender Z вверх, X вбок, «лицо» в −Y (в Godot +Z, к камере); 1 тайл
текстуры = 1 м. Всё детерминировано: у каждого ассета свой seed (random.Random), повторный запуск даёт те же меши.
Origin: у ассетов №001–020 — центр основания (z = 0 — пол, x/y — центр габарита); у кусков bits — центр габарита (удобно
спавнить «дождь из хлама»). Каждый glb — один объект-меш с именем файла (материалы — слоты).

Куски (bits/<Name>.glb, габарит Ш × В × Г в Godot-осях, м):
    Doll_Head_Sad / Doll_Head_Scared / Doll_Head_Cracked   ⌀0.24 голова старой куклы: шар с ВЫРЕЗАННЫМИ (boolean)
                          глазницами и ртом — грустное / испуганное / треснувшее с отколом лица; колышек шеи, пятна краски
    Doll_Limb_Upper       0.11 × 0.46 × 0.11 сегмент конечности (цилиндр с фасками, тёмный шаровой сустав, железная обойма,
                          тёмный торец); ось вдоль Blender Z (в Godot — вертикально)
    Doll_Limb_Lower       0.09 × 0.42 × 0.09 то же тоньше
    Doll_Hand, Doll_Foot  кисть-варежка с большим пальцем и шаром запястья; стопа-клин с шаром щиколотки
    Doll_Torso_Shell      0.42 × 0.55 × 0.27 клёпаный торс-бочонок: 2 железных пояса, заклёпки, тёмные гнёзда плеч и шеи
    Scrap_Board           0.9 × 0.03 × 0.15 старая доска с рваным концом и гвоздями (лежит плашмя)
    Rivet_Plate           0.5 × 0.04 × 0.36 ржавая гнутая пластина с 6 заклёпками и срезанным углом
    Gear_Small/Medium/Large   ⌀0.24 / ⌀0.5 / ⌀0.9 шестерни (10 / 14 / 18 зубьев; у большой обод, ступица и 4 спицы);
                          диск в плоскости экрана (ось вдоль Godot Z) — катится в плоскости XY
    Chain_Link            0.16 × 0.1 овальное звено; Chain_Segment — отрезок из 7 звеньев 0.8 м вдоль X
    Bolt, Nut, Nail       болт M20 × 0.16 с шестигранной головкой и шайбой, гайка, гнутый гвоздь 0.1
    Pipe_Piece            обломок трубы ⌀0.1 × 0.45 с фланцем и рваным концом (вдоль X)
    Sword_Broken          обломок меча 0.62: клинок ромбом с рваным концом, гарда, обмотка, навершие
    Helmet                шлем ⌀0.27: полый купол с полями, прорезями визора и заклёпками
    Shield_Crown          щит 0.55 × 0.7: красное поле по ржавчине, ржавый обод с заклёпками, корона-декаль
    Hammer_Old, Axe_Old, Mace_Old   старые молот / топор / булава (для №017 и «дождя»)

Ассеты (bodies/<Name>.glb; Ш × В × Г; физика — LIST.md, собирает tools/build_scrap_bodies_scenes.gd):
    001 Scrap_Heap_Small      1.6 × 0.7 × 1.2   S   холм scrap_dirt + доски, пластины, обломок ящика, длинная доска-«мачта»
    002 Scrap_Heap_Medium     3.0 × 1.4 × 2.0   S   то же крупнее: балки, ящик, колесо, шестерни, трубы
    003 Scrap_Heap_Massive    10 × 5 × 4        S   гора из двух вершин (часть геометрии арены): балки 2–3 м, щиты, колёса,
                                                    большие шестерни, шесты с рваным флагом-короной
    004 Puppet_Limb_Pile      2.0 × 0.8 × 1.5   S+R  куча рук и ног (сегменты с шаровыми суставами), несколько голов, кисти
    005 Puppet_Head_Pile      1.8 × 1.0 × 1.4   S+R  гора голов разных пород дерева и лиц, пятна краски
    006 Broken_Puppet         1.8 длина         S   почти целая кукла лежит на спине, красная рваная тряпка на груди
    007 Crushed_Puppet        1.6 × 0.6         S   кукла под ржавой плитой пресса, торчат голова и конечности
    008 Half_Puppet           1.2               S   торс с головой и одной рукой, привален к обломкам; рядом оторванные ноги
    009 Empty_Torso           0.6 × 0.7 × 0.4   R   полый торс с вырванной грудью (нет Core), пояса, заклёпки, скоба шеи
    010 Dead_Core_Shell       ⌀0.5              R   разбитая сферическая оболочка Core с латунными поясами, внутри мёртвое ядро
    011 Wooden_Limb_Bundle    1.4 × 0.5 × 0.6   R   связка из 10 конечностей, три витка верёвки с узлом и концами
    012 Metal_Parts_Heap      2.0 × 0.9 × 1.5   S   уголки, блоки, цилиндры, трубы, пластины, болты
    013 Gear_Heap             2.0 × 1.0 × 1.5   S+R  шестерни стоят «лицом» к камере и лежат; ржавый холм
    014 Chain_Heap            1.8 × 0.7 × 1.4   S   ржавый бугристый холм, обвитый цепями, концы свисают вперёд
    015 Nail_Bucket           ⌀0.5 × 0.55       R   деревянное ведро (клёпки, 2 обруча, дужка), полное гвоздей
    016 Bolt_Nut_Box          0.8 × 0.45 × 0.5  R   ящик из досок с железными уголками, полный болтов и гаек
    017 Broken_Weapons_Pile   2.0 × 0.8 × 1.2   S   мечи (целые и обломки), молоты, булава, топоры, древко копья
    018 Broken_Armor_Heap     2.0 × 1.0 × 1.4   S   шлемы, большой щит с короной, наплечники, клёпаные пластины
    019 Cloth_Scrap_Heap      2.0 × 0.9 × 1.4   S   хлам под драпированными флагами: красный с короной, синий, серая ветошь
    020 Mystery_Scrap_Heap    2.2 × 1.4 × 1.6   S+L  куча-пещера: доски сводом, внутри сундучок с латунью и короной и тёплое
                                                    свечение (эмиссия; OmniLight3D ставит builder)

physics.json (Godot-оси: x, y — вверх, z — к камере; Blender (x, y, z) → Godot (x, z, −y)):
    bits/physics.json    {Name: {"hull": [[x, y, z], …] (≤ 24 точек оболочки, зазор ≥ 1.5 см; тоньше 5 см по z — растянута
                          до 5 см, см. MIN_HULL_DEPTH), "size": [w, h, d]}}
    bodies/physics.json  {Name: {"kind": "S"|"R"|"SR"|"SL", "size": […],
                           "slices": [[[x, y, z] × 8], …]  — S: выпуклые призмы по верху кучи (профиль высоты по лучам на
                                     z ∈ [−0.15, 0.15], медиана, сглаживание), глубина ±COL_HALF_DEPTH, низ y = −0.05;
                           "hull": […]                     — R: выпуклая оболочка (≤ 32 точек);
                           "loose": [{"bit": Name, "pos": [x, y, z], "quat": [x, y, z, w]}, …] — свободные R-куски сверху;
                           "light": [x, y, z] и "loot": [x, y, z] — у Mystery_Scrap_Heap}
"""
import json
import math
import os
import random
import sys
import tempfile

try:
    import bpy
    import bmesh
    from mathutils import Matrix, Vector, Euler, Quaternion
    from mathutils.bvhtree import BVHTree
except ImportError:  # системный python3: только --compose (Pillow)
    bpy = None

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
if bpy is not None:
    import common as C  # noqa: E402

GODOT = os.path.abspath(os.path.join(HERE, "..", ".."))
REPO = os.path.abspath(os.path.join(GODOT, ".."))
OUT_BITS = os.path.join(GODOT, "assets", "models", "scrap", "bits")
OUT_BODIES = os.path.join(GODOT, "assets", "models", "scrap", "bodies")
CROWN = os.path.join(GODOT, "assets", "textures", "decals", "crown.png")
MANNEQUIN = os.path.join(GODOT, "assets", "models", "heroes", "mannequin", "mannequin.glb")
DOCS_IMG = os.path.join(REPO, "docs", "plan-demo", "img")
RENDER_DIR = os.environ.get("SCRAP_RENDER_DIR") or os.path.join(tempfile.gettempdir(), "scrap_sheet01")
TEX_BITS = int(os.environ.get("SCRAP_TEX_BITS", "512"))
TEX_BODIES = int(os.environ.get("SCRAP_TEX_BODIES", "1024"))
IMG_FORMAT = os.environ.get("PROPS_IMG", "WEBP")
CACHE = os.environ.get("PROPS_CACHE") or os.path.join(tempfile.gettempdir(), "ragdoll_props_pbr")
FORCE_FLAT = os.environ.get("SCRAP_FLAT", "0") == "1"
TRI_BIT = 600
TRI_BODY = 3000
TRI_BUDGET = {"Scrap_Heap_Medium": 5000, "Scrap_Heap_Massive": 12000}
COL_HALF_DEPTH = 0.6          # коллизия S-ассетов: z ∈ [−0.6, 0.6] в Godot (кукла живёт на z = 0)
MIN_HULL_DEPTH = 0.05         # оболочки кусков тоньше 5 см по Godot Z (звено, гвоздь, шестерни, гайка) растягиваются по Z:
                              # Jolt 4.7 с заблокированными осями сажает такие «плоские» оболочки в пол на 2–3.5 см; по Z
                              # тела всё равно не двигаются (axis_lock_linear_z), кукла живёт в той же плоскости
TAU = 2.0 * math.pi
RNG = random.Random(1)


def seed(s):
    """Каждый ассет/кусок строится со своим seed — результат не зависит от порядка сборки."""
    global RNG
    RNG = random.Random(s)
    return RNG


# ----------------------------------------------------------------------------------------------------------------------
# материалы
# ----------------------------------------------------------------------------------------------------------------------
def _lin(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _rgba(t):
    return (_lin(t[0]), _lin(t[1]), _lin(t[2]), 1.0)


# имя → (папка PBR, kwargs textured_material, плоский запасной цвет sRGB, шероховатость, металличность)
MAT_DEF = {
    "Rust": ("rust_metal", {}, (122, 58, 26), 0.80, 0.55),
    "RustDark": ("rust_metal", {"tint": (0.58, 0.54, 0.52, 1.0)}, (70, 38, 22), 0.85, 0.5),
    "RustRed": ("rust_painted_red", {}, (146, 36, 28), 0.60, 0.1),
    "ScrapWood": ("scrap_wood", {}, (112, 82, 54), 0.85, 0.0),
    "ScrapWoodDark": ("scrap_wood", {"tint": (0.60, 0.56, 0.54, 1.0)}, (70, 52, 38), 0.90, 0.0),
    "Dirt": ("scrap_dirt", {"tint": (0.78, 0.72, 0.68, 1.0)}, (48, 40, 35), 0.95, 0.0),
    "RustBlack": ("rust_metal", {"tint": (0.34, 0.31, 0.30, 1.0)}, (40, 24, 16), 0.9, 0.4),
    "Brass": ("brass_worn", {}, (176, 134, 62), 0.40, 0.9),
    "Iron": ("iron", {}, (92, 90, 88), 0.50, 0.9),
    "IronDark": ("iron", {"tint": (0.50, 0.48, 0.47, 1.0)}, (52, 50, 49), 0.60, 0.85),
    "DollWood": ("maple_light", {"tint": (0.80, 0.56, 0.36, 1.0), "roughness_scale": 1.15}, (168, 112, 64), 0.70, 0.0),
    "DollPale": ("maple_light", {"tint": (0.92, 0.78, 0.60, 1.0), "roughness_scale": 1.15}, (186, 146, 98), 0.70, 0.0),
    "DollDark": ("walnut_dark", {"tint": (1.0, 0.9, 0.82, 1.0)}, (96, 58, 34), 0.65, 0.0),
    "JointDark": ("walnut_dark", {"tint": (0.36, 0.30, 0.27, 1.0)}, (38, 26, 19), 0.50, 0.0),
    "WoodDark": ("wood_dark", {}, (78, 54, 36), 0.75, 0.0),
    "Rope": ("rope", {}, (178, 138, 86), 0.90, 0.0),
    "ClothRed": ("fabric_red", {"tint": (0.86, 0.80, 0.78, 1.0)}, (150, 30, 26), 0.95, 0.0),
    "ClothBlue": ("fabric_blue", {"tint": (0.82, 0.86, 0.92, 1.0)}, (70, 88, 118), 0.95, 0.0),
    "ClothWrap": ("cloth_wrap", {"tint": (0.78, 0.72, 0.66, 1.0)}, (160, 142, 116), 0.95, 0.0),
    "PaintRed": ("painted_red", {"tint": (0.82, 0.74, 0.72, 1.0)}, (150, 36, 30), 0.60, 0.0),
}
FLAT = {
    "Char": ((14, 11, 9), 0.95, 0.0),            # глазницы, торцы, внутренность полостей
    "CoreDead": ((12, 12, 16), 0.28, 0.4),       # мёртвое ядро: тёмное стекло
}
EMIT = {
    "Glow": ((255, 170, 90), (1.0, 0.52, 0.16, 1.0), 9.0),     # тёплое свечение внутри Mystery_Scrap_Heap
    "Ember": ((255, 120, 40), (1.0, 0.36, 0.08, 1.0), 5.0),    # угольки
}
METAL_SETS = ("rust_metal", "rust_painted_red", "brass_worn")
DOUBLE_SIDED = ("ClothRed", "ClothBlue", "ClothWrap")
_MATS = {}
_TEX_SIZE = [TEX_BITS]
USED_PBR = set()
USED_FLAT = set()


def pbr_ready(folder):
    if FORCE_FLAT:
        return False
    need = ["albedo", "roughness", "normal"] + (["metallic"] if folder in METAL_SETS else [])
    return all(os.path.exists(os.path.join(C.PBR_DIR, folder, ch + ".png")) for ch in need)


def pbr_folder(name, size):
    """Папка PBR-набора: исходная (2048²) или уменьшенная копия в кэше (как в props.py / workshop_props.py)."""
    src = os.path.join(C.PBR_DIR, name)
    if size >= 2048:
        return src
    dst = os.path.join(CACHE, str(size), name)
    os.makedirs(dst, exist_ok=True)
    for ch in ("albedo", "roughness", "normal", "metallic"):
        s = os.path.join(src, ch + ".png")
        d = os.path.join(dst, ch + ".png")
        if not os.path.exists(s):
            if os.path.exists(d):
                os.remove(d)
            continue
        if os.path.exists(d) and os.path.getmtime(d) >= os.path.getmtime(s):
            continue
        img = bpy.data.images.load(s)
        if ch != "albedo":
            img.colorspace_settings.name = 'Non-Color'
        if img.size[0] > size:
            img.scale(size, size)
        img.filepath_raw = d
        img.file_format = 'PNG'
        img.save()
        bpy.data.images.remove(img)
    return dst


def _build_mat(name):
    if name in MAT_DEF:
        folder, kw, flat, rough, metal = MAT_DEF[name]
        if pbr_ready(folder):
            m = C.textured_material(name, pbr_folder(folder, _TEX_SIZE[0]), **kw)
            USED_PBR.add("%s←%s" % (name, folder))
        else:
            m = C.material(name, _rgba(flat), rough, metal)
            USED_FLAT.add("%s(%s)" % (name, folder))
        m.use_backface_culling = name not in DOUBLE_SIDED
        return m
    if name in FLAT:
        base, rough, metal = FLAT[name]
        m = C.material(name, _rgba(base), rough, metal)
    elif name in EMIT:
        base, ecol, es = EMIT[name]
        m = C.material(name, _rgba(base), 0.6, 0.0, emission=ecol, emission_strength=es)
    elif name.startswith("Crown"):
        m = crown_material(name)
    else:
        raise KeyError(name)
    m.use_backface_culling = True
    return m


def M(name):
    if name not in _MATS:
        _MATS[name] = _build_mat(name)
    return _MATS[name]


def set_tex_size(size):
    """Перенастраивает все уже созданные текстурные материалы на другой размер текстур (куски 512, ассеты 1024)."""
    if _TEX_SIZE[0] == size:
        return
    _TEX_SIZE[0] = size
    for name in list(_MATS):
        if name in MAT_DEF and pbr_ready(MAT_DEF[name][0]):
            _MATS[name] = _build_mat(name)


CROWN_TINT = {"Crown": (1.0, 0.95, 0.86, 1.0), "CrownGold": (1.0, 0.80, 0.42, 1.0), "CrownDark": (0.32, 0.27, 0.24, 1.0)}


def crown_material(name):
    """Декаль короны: Image → Base Color (× тинт) и Alpha через Greater Than 0.5 → экспортёр glTF пишет alphaMode MASK
    (alpha clip: без сортировки прозрачности и с тенью, в отличие от BLEND у common.decal_plane)."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    tex = nt.nodes.new('ShaderNodeTexImage')
    tex.image = C._load_packed(CROWN)
    tex.extension = 'CLIP'
    mix = nt.nodes.new('ShaderNodeMix')
    mix.data_type = 'RGBA'
    mix.blend_type = 'MULTIPLY'
    mix.inputs[0].default_value = 1.0
    mix.inputs[7].default_value = CROWN_TINT.get(name, CROWN_TINT["Crown"])
    nt.links.new(tex.outputs['Color'], mix.inputs[6])
    nt.links.new(mix.outputs[2], bsdf.inputs['Base Color'])
    gt = nt.nodes.new('ShaderNodeMath')
    gt.operation = 'GREATER_THAN'
    gt.inputs[1].default_value = 0.5
    nt.links.new(tex.outputs['Alpha'], gt.inputs[0])
    nt.links.new(gt.outputs[0], bsdf.inputs['Alpha'])
    bsdf.inputs['Roughness'].default_value = 0.6
    if name == "CrownGold":
        bsdf.inputs['Metallic'].default_value = 0.6
        bsdf.inputs['Roughness'].default_value = 0.45
    for attr, val in (('surface_render_method', 'DITHERED'), ('blend_method', 'CLIP')):
        try:
            setattr(mat, attr, val)
        except Exception:
            pass
    return mat


# ----------------------------------------------------------------------------------------------------------------------
# геометрия: всё строится bmesh-ом в локальных координатах, трансформ впекается в меш (xf / put), origin — мировой ноль
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


def rot_m(rot):
    if isinstance(rot, Matrix):
        return rot.to_4x4() if len(rot) == 3 else rot
    if isinstance(rot, Quaternion):
        return rot.to_matrix().to_4x4()
    return Euler(rot).to_matrix().to_4x4()


def xf(o, loc=(0.0, 0.0, 0.0), rot=(0.0, 0.0, 0.0), scale=None):
    """Впекает масштаб → поворот → перенос в меш (origin остаётся в мировом нуле)."""
    m = Matrix.Translation(Vector(loc)) @ rot_m(rot)
    if scale is not None:
        s = scale if isinstance(scale, (tuple, list)) else (scale, scale, scale)
        m = m @ Matrix.Diagonal((s[0], s[1], s[2], 1.0))
    o.data.transform(m)
    o.data.update()
    return o


def bbox(o):
    vs = [v.co for v in o.data.vertices]
    mn = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    mx = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    return mn, mx


def center(o):
    """Сдвигает меш так, чтобы центр габарита попал в ноль."""
    mn, mx = bbox(o)
    return xf(o, -(mn + mx) * 0.5)


def base_center(o):
    """Сдвигает меш: центр основания (низ габарита, центр по x/y) → ноль."""
    mn, mx = bbox(o)
    c = (mn + mx) * 0.5
    return xf(o, (-c.x, -c.y, -mn.z))


def uv_shift(o, du, dv):
    if o.data.uv_layers:
        for d in o.data.uv_layers[0].data:
            d.uv = (d.uv[0] + du, d.uv[1] + dv)
    return o


def box(name, size, mat, jitter=0.0, along='X', du=None, dv=None, scale=1.0, taper=None):
    """Куб size с центром в нуле, кубическая UV в метрах (волокна вдоль `along`), сдвиг развёртки — центр случайной
    доски тайла (4 доски на тайл, как у wood / scrap_wood). taper=(sx, sy) — сужение верхней грани (клин)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Diagonal((size[0], size[1], size[2], 1.0)))
    if taper is not None:
        for v in bm.verts:
            if v.co.z > 0:
                v.co.x *= taper[0]
                v.co.y *= taper[1]
    if jitter > 0.0:
        for v in bm.verts:
            v.co += Vector((RNG.uniform(-jitter, jitter), RNG.uniform(-jitter, jitter), RNG.uniform(-jitter, jitter)))
    o = mesh_obj(name, bm, [mat])
    C.uv_box(o, scale, along)
    uv_shift(o, (0.5 + RNG.randrange(4)) / 4.0 if du is None else du, RNG.uniform(0.0, 1.0) if dv is None else dv)
    return o


AXIS_ROT = {'Z': Matrix.Identity(4), 'Y': Matrix.Rotation(-math.pi / 2, 4, 'X'), 'X': Matrix.Rotation(math.pi / 2, 4, 'Y')} if bpy is not None else {}


def lathe(name, profile, segs=12, mats=(), axis='Z', uv_scale=1.0, loop=False, band_mat=None, sy=1.0, phase=0.0, rfun=None):
    """Тело вращения из профиля [(r, z), …] (r=0 — полюс) вокруг локальной Z, затем ось → `axis`.
    loop=True — профиль замкнут (последняя точка соединяется с первой, без крышек: полые стенки, кольца).
    band_mat — индекс материала на каждый пояс профиля. sy — сплющивание по Y (эллиптическое сечение).
    rfun(i, k, r) → r — модуляция радиуса (клёпки ведра, рваные края). UV цилиндрические, V вдоль оси."""
    bm = bmesh.new()
    rings = []
    for k, (r, z) in enumerate(profile):
        if r < 1e-6:
            rings.append([bm.verts.new((0.0, 0.0, z))])
        else:
            ring = []
            for i in range(segs):
                a = TAU * i / segs + phase
                rr = rfun(i, k, r) if rfun else r
                ring.append(bm.verts.new((rr * math.cos(a), rr * math.sin(a) * sy, z)))
            rings.append(ring)
    pairs = list(zip(rings, rings[1:]))
    if loop:
        pairs.append((rings[-1], rings[0]))
    for bi, (a, b) in enumerate(pairs):
        if len(a) == 1 and len(b) == 1:
            continue
        mi = band_mat[bi] if band_mat else 0
        for i in range(segs):
            j = (i + 1) % segs
            if len(a) == 1:
                f = bm.faces.new((a[0], b[i], b[j]))
            elif len(b) == 1:
                f = bm.faces.new((a[i], a[j], b[0]))
            else:
                f = bm.faces.new((a[i], a[j], b[j], b[i]))
            f.material_index = mi
    if not loop:
        if len(rings[0]) > 1:
            f = bm.faces.new(list(reversed(rings[0])))
            f.material_index = band_mat[0] if band_mat else 0
        if len(rings[-1]) > 1:
            f = bm.faces.new(rings[-1])
            f.material_index = band_mat[-1] if band_mat else 0
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = mesh_obj(name, bm, list(mats))
    C.uv_cylinder_along(o, 'Z', uv_scale, centre=(0.0, 0.0))
    uv_shift(o, RNG.uniform(0, 1), RNG.uniform(0, 1))
    o.data.transform(AXIS_ROT[axis])
    return o


def cyl(name, r, length, axis, mat, segs=10, r2=None):
    r2 = r if r2 is None else r2
    return lathe(name, [(0.0, -length / 2), (r, -length / 2), (r2, length / 2), (0.0, length / 2)], segs, [mat], axis)


def tube(name, r_in, r_out, length, axis, mat, segs=12, sy=1.0):
    h = length / 2
    return lathe(name, [(r_in, -h), (r_out, -h), (r_out, h), (r_in, h)], segs, [mat], axis, loop=True, sy=sy)


def sphere(name, r, mat, segs=10, rings=6, scale=(1.0, 1.0, 1.0)):
    prof = [(0.0, -r)] + [(r * math.sin(math.pi * k / rings), -r * math.cos(math.pi * k / rings)) for k in range(1, rings)] + [(0.0, r)]
    o = lathe(name, prof, segs, [mat])
    if scale != (1.0, 1.0, 1.0):
        xf(o, scale=scale)
    return o


def plate(name, pts_xz, thickness, mat, y=0.0, mat_back=None):
    """Плоская деталь: многоугольник в плоскости XZ [(x, z), …] толщиной вдоль Y (лицевая сторона −Y)."""
    bm = bmesh.new()
    front = [bm.verts.new((x, y - thickness / 2, z)) for x, z in pts_xz]
    back = [bm.verts.new((x, y + thickness / 2, z)) for x, z in pts_xz]
    ff = bm.faces.new(front)
    fb = bm.faces.new(list(reversed(back)))
    n = len(front)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((front[j], front[i], back[i], back[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    if mat_back is not None:
        fb.material_index = 1
    o = mesh_obj(name, bm, [mat] + ([mat_back] if mat_back is not None else []))
    C.uv_box(o, 1.0, 'Z')
    uv_shift(o, RNG.uniform(0, 1), RNG.uniform(0, 1))
    return o


def ngon_disc(name, rx, rz, sides, mat, rot=0.0):
    """Плоский многоугольник-эллипс в плоскости XZ лицом в −Y (наклейка: глазница, торец)."""
    bm = bmesh.new()
    vs = [bm.verts.new((rx * math.cos(TAU * i / sides + rot), 0.0, rz * math.sin(TAU * i / sides + rot))) for i in range(sides)]
    f = bm.faces.new(vs)
    f.normal_update()
    if f.normal.y > 0:
        f.normal_flip()
    o = mesh_obj(name, bm, [mat])
    C.uv_box(o, 1.0)
    return o


def link_mesh(name, length, width, wire, mat, segs=12, sides=6):
    """Овальное звено цепи в плоскости XZ (длина вдоль X): тор, растянутый прямыми участками."""
    bm = bmesh.new()
    R = (width - 2 * wire) / 2 + wire / 2          # радиус средней линии на закруглениях
    straight = max(0.0, length - width) / 2
    rings = []
    for i in range(segs):
        a = TAU * i / segs
        cx = math.cos(a) * R + (straight if math.cos(a) > 1e-6 else (-straight if math.cos(a) < -1e-6 else 0.0))
        cz = math.sin(a) * R
        nx, nz = math.cos(a), math.sin(a)
        ring = []
        for k in range(sides):
            b = TAU * k / sides
            rr = wire / 2
            ring.append(bm.verts.new((cx + nx * rr * math.cos(b), rr * math.sin(b), cz + nz * rr * math.cos(b))))
        rings.append(ring)
    for i in range(segs):
        a, b2 = rings[i], rings[(i + 1) % segs]
        for k in range(sides):
            kk = (k + 1) % sides
            bm.faces.new((a[k], b2[k], b2[kk], a[kk]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = mesh_obj(name, bm, [mat])
    C.uv_box(o, 1.0)
    uv_shift(o, RNG.uniform(0, 1), RNG.uniform(0, 1))
    return o


def rivet(name, loc, direction, r=0.010, h=0.010, mat=None, segs=6):
    o = cyl(name, r, h, 'Z', mat or M("IronDark"), segs=segs, r2=r * 0.7)
    d = Vector(direction).normalized()
    return xf(o, loc, d.to_track_quat('Z', 'Y'))


def bevel_apply(o, width, segments=1, angle=30.0):
    m = C.bevel(o, width, segments, angle)
    m.harden_normals = False
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier=m.name)
    return o


def boolean(o, cutters, op='DIFFERENCE'):
    """Точный boolean с переносом материалов резца (стенки глазниц получают его материал); резцы удаляются."""
    bpy.ops.object.select_all(action='DESELECT')
    bpy.context.view_layer.objects.active = o
    o.select_set(True)
    for cut in cutters:
        m = o.modifiers.new("Bool", 'BOOLEAN')
        m.operation = op
        m.solver = 'EXACT'
        m.object = cut
        try:
            m.material_mode = 'TRANSFER'
        except Exception:
            pass
        bpy.ops.object.modifier_apply(modifier=m.name)
    for cut in cutters:
        bpy.data.objects.remove(cut, do_unlink=True)
    return o


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
    return o


def merge(objs, name):
    objs = [o for o in objs if o is not None]
    if len(objs) == 1:
        objs[0].name = name
        return objs[0]
    return C.join(objs, name)


def dup(o, name=None):
    c = o.copy()
    c.data = o.data.copy()
    c.name = name or o.name
    bpy.context.scene.collection.objects.link(c)
    return c


def remove(o):
    if o is not None:
        me = o.data
        bpy.data.objects.remove(o, do_unlink=True)
        if me is not None and me.users == 0:
            bpy.data.meshes.remove(me)


def paint(o, mat, n=3, radius=0.05, centres=None, p=1.0):
    """Пятна краски: грани с центром ближе radius к случайным точкам поверхности получают материал `mat` (добавляется
    слотом). Треугольников не добавляет."""
    me = o.data
    if not me.polygons:
        return o
    idx = None
    for i, m in enumerate(me.materials):
        if m == mat:
            idx = i
    if idx is None:
        me.materials.append(mat)
        idx = len(me.materials) - 1
    polys = list(me.polygons)
    if centres is None:
        centres = [polys[RNG.randrange(len(polys))].center.copy() for _ in range(n)]
    for poly in polys:
        c = poly.center
        for q in centres:
            rr = radius * (0.7 + 0.6 * ((hash((round(c.x, 3), round(c.y, 3))) % 100) / 100.0))
            if (c - q).length < rr and RNG.random() < p:
                poly.material_index = idx
                break
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


def align_z(direction, roll=0.0):
    """Поворот, переводящий локальную +Z в direction (с креном roll вокруг неё)."""
    d = Vector(direction).normalized()
    q = Vector((0.0, 0.0, 1.0)).rotation_difference(d)
    return q.to_matrix().to_4x4() @ Matrix.Rotation(roll, 4, 'Z')


def rand_rot(rng=None):
    rng = rng or RNG
    return Euler((rng.uniform(0, TAU), rng.uniform(0, TAU), rng.uniform(0, TAU))).to_matrix().to_4x4()


# ----------------------------------------------------------------------------------------------------------------------
# библиотека кусков. lod: 0 — отдельный кусок (bits, ≤ 600 треугольников), 1 — в куче (дешевле), 2 — в глубине кучи.
# Все функции возвращают объект с origin в мировом нуле; «длинные» детали — вдоль +Z (конечности) или X (доски, трубы).
# ----------------------------------------------------------------------------------------------------------------------
HEAD_R = 0.12
DOLL_WOODS = ("DollWood", "DollPale", "DollDark")


def _face_cutters(kind, R, depth, sides_eye, sides_mouth, name):
    """Резцы черт лица (призмы вдоль Y, материал Char): глазницы и рот на передней (−Y) стороне шара радиуса R."""
    feats = []   # (points_xz, centre_xz)

    def ell(cx, cz, rx, rz, rot, n):
        return [(cx + rx * math.cos(TAU * i / n) * math.cos(rot) - rz * math.sin(TAU * i / n) * math.sin(rot),
                 cz + rx * math.cos(TAU * i / n) * math.sin(rot) + rz * math.sin(TAU * i / n) * math.cos(rot)) for i in range(n)]

    def arc(cx, cz, w, bend, thick, n, tilt=0.0):
        top, bot = [], []
        for i in range(n + 1):
            t = -1.0 + 2.0 * i / n
            x = cx + w * t
            z = cz + bend * (1.0 - t * t) + tilt * t
            top.append((x, z + thick / 2))
            bot.append((x, z - thick / 2))
        return top + list(reversed(bot))

    ex, ez = 0.36 * R, 0.10 * R
    if kind == "Sad":
        feats.append(ell(-ex, ez, 0.17 * R, 0.11 * R, math.radians(-20), sides_eye))
        feats.append(ell(ex, ez, 0.17 * R, 0.11 * R, math.radians(20), sides_eye))
        feats.append(arc(0.0, -0.46 * R, 0.26 * R, 0.10 * R, 0.07 * R, sides_mouth))           # уголки вниз
    elif kind == "Scared":
        feats.append(ell(-ex, ez + 0.03 * R, 0.19 * R, 0.21 * R, 0.0, sides_eye))
        feats.append(ell(ex, ez + 0.03 * R, 0.19 * R, 0.21 * R, 0.0, sides_eye))
        feats.append(ell(0.0, -0.44 * R, 0.12 * R, 0.17 * R, 0.0, sides_eye))                   # рот «О»
    else:  # Cracked
        feats.append(ell(-ex, ez, 0.18 * R, 0.17 * R, 0.0, sides_eye))
        feats.append(ell(ex, ez - 0.02 * R, 0.21 * R, 0.07 * R, math.radians(24), sides_eye))
        feats.append(arc(0.02 * R, -0.44 * R, 0.25 * R, -0.02 * R, 0.06 * R, max(2, sides_mouth - 1), tilt=-0.07 * R))
    cutters = []
    for k, pts in enumerate(feats):
        cx = sum(p[0] for p in pts) / len(pts)
        cz = sum(p[1] for p in pts) / len(pts)
        ys = -math.sqrt(max(1e-6, R * R - cx * cx - cz * cz))                                    # поверхность шара
        y0, y1 = -R - 0.04, ys + depth
        cutters.append(plate("%s_cut%d" % (name, k), pts, y1 - y0, M("Char"), y=(y0 + y1) / 2))
    return cutters


def doll_head(name, kind="Sad", mat="DollWood", lod=0, paint_n=2):
    R = HEAD_R
    segs, rings = ((16, 10), (10, 6), (8, 5))[lod]
    head = sphere(name, R, M(mat), segs, rings, scale=(1.0, 1.0, 1.06))
    xf(head, rot=(0, 0, math.pi / segs))                   # шов сетки не по центру лица
    cut = _face_cutters(kind, R, (0.026, 0.02, 0.018)[lod], (8, 5, 5)[lod], (4, 3, 2)[lod], name)
    if kind == "Cracked" and lod == 0:
        # скол: неправильный клин сверху справа + трещина-паз вниз по лицу
        chip = plate(name + "_chip", [(0.0, 0.0), (0.07, -0.01), (0.09, 0.05), (0.05, 0.09), (-0.01, 0.06)], 0.16, M("Char"))
        xf(chip, (0.055, -0.04, 0.075), (math.radians(-25), math.radians(20), math.radians(10)))
        crack = plate(name + "_crack", [(0.0, 0.0), (0.012, -0.03), (0.004, -0.05), (0.016, -0.085), (0.010, -0.085),
                                        (-0.002, -0.05), (0.006, -0.03), (-0.006, 0.0)], 0.10, M("Char"))
        xf(crack, (0.052, -0.09, 0.07))
        cut += [chip, crack]
    boolean(head, cut)
    if lod == 0:
        peg = cyl(name + "_neck", 0.032, 0.05, 'Z', M("JointDark"), segs=8)
        xf(peg, (0, 0, -R * 1.06 - 0.012))
        head = merge([head, peg], name)
    if paint_n:
        paint(head, M("PaintRed"), n=paint_n, radius=0.055)
    return head


def limb(name, length=0.42, r=0.05, mat="DollWood", lod=0, ball=True, ferrule=True, paint_n=0):
    """Сегмент конечности вдоль +Z от 0 до length: тело с фасками (торец z=0 — тёмный, «полый»), тёмный шаровой сустав
    над верхним концом, железная обойма у торца (lod 0)."""
    segs = (12, 8, 6)[lod]
    ch = r * 0.3
    if lod == 0:
        prof = [(0.0, 0.0), (r * 0.78, 0.0), (r, ch), (r * 0.93, length - ch), (r * 0.78, length), (0.0, length)]
        bands = [1, 0, 0, 0, 0]
    elif lod == 1:
        prof = [(0.0, 0.0), (r * 0.8, 0.0), (r, ch), (r * 0.9, length), (0.0, length)]
        bands = [1, 0, 0, 0]
    else:
        prof = [(0.0, 0.0), (r, 0.0), (r * 0.92, length), (0.0, length)]
        bands = [1, 0, 0]
    body = lathe(name, prof, segs, [M(mat), M("Char")], 'Z', band_mat=bands)
    parts = [body]
    if ball:
        rb = r * 1.12
        b = sphere(name + "_ball", rb, M("JointDark"), (10, 6, 6)[lod], (6, 4, 4)[lod])
        xf(b, (0, 0, length + rb * 0.55))
        parts.append(b)
    if ferrule and lod == 0:
        f = tube(name + "_fer", r * 0.98, r * 1.08, 0.03, 'Z', M("Rust"), segs=segs)
        xf(f, (0, 0, 0.045))
        parts.append(f)
    o = merge(parts, name)
    if paint_n:
        paint(o, M("PaintRed"), n=paint_n, radius=r * 1.6)
    return o


def hand(name, mat="DollWood", lod=0):
    parts = []
    palm = box(name, (0.085, 0.038, 0.10), M(mat), along='Z')
    if lod == 0:
        bevel_apply(palm, 0.012, 1)
    xf(palm, (0, 0, -0.06))
    parts.append(palm)
    fing = box(name + "_f", (0.08, 0.032, 0.075), M(mat), along='Z', taper=(1.0, 1.0))
    if lod == 0:
        bevel_apply(fing, 0.012, 1)
    xf(fing, (0, 0, -0.0375))
    xf(fing, (0, -0.004, -0.105), (math.radians(24), 0, 0))       # пальцы подогнуты от линии костяшек
    parts.append(fing)
    th = cyl(name + "_th", 0.014, 0.06, 'Z', M(mat), segs=(6, 5, 4)[lod])
    xf(th, (-0.045, -0.02, -0.075), align_z((-0.5, -0.5, -0.7)))
    parts.append(th)
    w = sphere(name + "_w", 0.028, M("JointDark"), (8, 6, 6)[lod], (5, 4, 4)[lod])
    xf(w, (0, 0, 0.0))
    parts.append(w)
    return merge(parts, name)


def foot(name, mat="DollWood", lod=0):
    prof = [(0.07, 0.0), (-0.17, 0.0), (-0.175, 0.025), (-0.12, 0.05), (-0.03, 0.075), (0.07, 0.075)]
    f = plate(name, prof, 0.09, M(mat))            # профиль (y→x) в плоскости XZ, толщина по Y
    xf(f, rot=(0, 0, math.pi / 2))                 # носок → −Y
    C.uv_box(f, 1.0, 'Y')
    if lod == 0:
        bevel_apply(f, 0.012, 1)
    a = sphere(name + "_a", 0.032, M("JointDark"), (8, 6, 6)[lod], (5, 4, 4)[lod])
    xf(a, (0, 0.02, 0.095))
    return merge([f, a], name)


TORSO_PROF = [(0.0, 0.0), (0.13, 0.0), (0.15, 0.03), (0.17, 0.12), (0.20, 0.28), (0.205, 0.38), (0.18, 0.46), (0.12, 0.50), (0.0, 0.50)]
TORSO_SY = 0.64


def _torso_r(z):
    for (r0, z0), (r1, z1) in zip(TORSO_PROF[1:], TORSO_PROF[2:]):
        if z0 <= z <= z1:
            return r0 + (r1 - r0) * (z - z0) / max(1e-6, z1 - z0)
    return 0.15


def torso(name, mat="DollWood", lod=0, rivets=True):
    segs = (12, 10, 8)[lod]
    body = lathe(name, TORSO_PROF, segs, [M(mat), M("JointDark")], 'Z', sy=TORSO_SY,
                 band_mat=[0] * (len(TORSO_PROF) - 2) + [1], phase=math.pi / segs)
    parts = [body]
    for z in (0.10, 0.40):
        r = _torso_r(z)
        b = tube(name + "_band", r - 0.004, r + 0.008, 0.034, 'Z', M("Rust"), segs=segs, sy=TORSO_SY * (r + 0.002) / r)
        xf(b, (0, 0, z))
        parts.append(b)
        if rivets and lod == 0:
            for a in (-0.35, 0.0, 0.35):
                ang = -math.pi / 2 + a
                p = Vector(((r + 0.008) * math.cos(ang), (r + 0.008) * math.sin(ang) * TORSO_SY, z))
                parts.append(rivet(name + "_rv", p, (math.cos(ang), math.sin(ang) / TORSO_SY, 0), r=0.009, h=0.008, segs=5))
    for s in (-1, 1):
        sh = sphere(name + "_sh", 0.052, M("JointDark"), (6, 6, 5)[lod], (4, 4, 3)[lod])
        xf(sh, (s * 0.19, 0, 0.43))
        parts.append(sh)
    return merge(parts, name)


def board(name, L=0.9, W=0.15, T=0.03, mat="ScrapWood", jag=(False, True), nails=0):
    """Доска плашмя: длина вдоль X, ширина вдоль Y, толщина Z; рваные концы jag=(левый, правый); гвозди торчат вверх."""
    pts = []
    def end(x0, sgn, jagged):
        if not jagged:
            return [(x0, -W / 2), (x0, W / 2)] if sgn > 0 else [(x0, W / 2), (x0, -W / 2)]
        n = 4
        zs = [-W / 2 + W * i / (n - 1) for i in range(n)]
        if sgn < 0:
            zs = list(reversed(zs))
        return [(x0 - sgn * RNG.uniform(0.0, 0.09), z) for z in zs]
    pts += end(L / 2, 1, jag[1])
    pts += end(-L / 2, -1, jag[0])
    o = plate(name, pts, T, M(mat))
    xf(o, rot=(math.pi / 2, 0, 0))
    C.uv_box(o, 1.0, 'X')
    uv_shift(o, (0.5 + RNG.randrange(4)) / 4.0, RNG.uniform(0, 1))
    if nails:
        parts = [o]
        for k in range(nails):
            x = RNG.choice((-1, 1)) * (L / 2 - 0.05)
            nl = cyl(name + "_nl", 0.004, 0.05, 'Z', M("Rust"), segs=4)
            xf(nl, (x, RNG.uniform(-W / 3, W / 3), T / 2 + 0.02), (RNG.uniform(-0.4, 0.4), RNG.uniform(-0.4, 0.4), 0))
            parts.append(nl)
        o = merge(parts, name)
    return o


def rivet_plate(name, w=0.5, h=0.36, t=0.012, mat="Rust", lod=0, bend=0.03, cut=True):
    """Ржавая пластина плашмя (w вдоль X, h вдоль Y), гнутая вдоль X, со срезанным углом и заклёпками по краю."""
    n = 4 if lod == 0 else 2
    xs = [-w / 2 + w * i / n for i in range(n + 1)]
    top = [(x, h / 2) for x in xs]
    bot = [(x, -h / 2) for x in reversed(xs)]
    if cut:
        top[-1] = (w / 2 - 0.08, h / 2)
        top.append((w / 2, h / 2 - 0.07))
    o = plate(name, top + bot, t, M(mat))
    xf(o, rot=(math.pi / 2, 0, 0))
    for v in o.data.vertices:
        v.co.z += bend * (2.0 * v.co.x / w) ** 2
    C.uv_box(o, 1.0)
    uv_shift(o, RNG.uniform(0, 1), RNG.uniform(0, 1))
    parts = [o]
    if lod == 0:
        for (x, y) in ((-w / 2 + 0.04, -h / 2 + 0.04), (0, -h / 2 + 0.04), (w / 2 - 0.04, -h / 2 + 0.04),
                       (-w / 2 + 0.04, h / 2 - 0.04), (0, h / 2 - 0.04), (w / 2 - 0.12, h / 2 - 0.04)):
            z = bend * (2.0 * x / w) ** 2 + t / 2 + 0.003
            parts.append(rivet(name + "_rv", (x, y, z), (0, 0, 1), r=0.011, h=0.009, segs=6))
    return merge(parts, name)


def gear(name, teeth=14, r_out=0.25, t=0.04, mat="Rust", hole=0.3, spokes=0, tooth_h=None):
    """Шестерня в плоскости XZ (лицом к камере, ось вдоль Y). hole — радиус отверстия / обода (доля r_out);
    spokes > 0 — обод + ступица + спицы (большая шестерня). Грань зуба — один n-угольник: 20 треугольников на зуб."""
    th = tooth_h if tooth_h is not None else min(0.06, r_out * 0.2)
    r_root = r_out - th
    r_in = r_out * hole if spokes == 0 else r_root - max(0.035, r_out * 0.12)
    p = TAU / teeth
    bm = bmesh.new()
    F, B = [], []
    for side, y in ((F, -t / 2), (B, t / 2)):
        outer, inner = [], []
        for i in range(teeth):
            a0 = i * p
            for f, r in ((0.0, r_root), (0.18, r_out), (0.44, r_out), (0.62, r_root)):
                a = a0 + f * p
                outer.append(bm.verts.new((r * math.cos(a), y, r * math.sin(a))))
            inner.append(bm.verts.new((r_in * math.cos(a0), y, r_in * math.sin(a0))))
        side.extend([outer, inner])
    for (outer, inner) in (F, B):
        for i in range(teeth):
            j = (i + 1) % teeth
            q = outer[4 * i:4 * i + 4]
            bm.faces.new([inner[i]] + q + [outer[4 * j], inner[j]])
    (of, inf), (ob, inb) = F, B
    n = len(of)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((of[i], of[j], ob[j], ob[i]))
    for i in range(teeth):
        j = (i + 1) % teeth
        bm.faces.new((inf[i], inb[i], inb[j], inf[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = mesh_obj(name, bm, [M(mat)])
    C.uv_box(o, 1.0)
    uv_shift(o, RNG.uniform(0, 1), RNG.uniform(0, 1))
    parts = [o]
    if spokes:
        hub = tube(name + "_hub", r_out * 0.08, r_out * 0.2, t * 1.4, 'Y', M(mat), segs=10)
        parts.append(hub)
        for k in range(spokes):
            a = TAU * k / spokes + p * 0.3
            ln = r_in - r_out * 0.18
            sp = box(name + "_sp", (0.05 * r_out / 0.45, t * 0.8, ln + 0.02), M(mat), along='Z')
            xf(sp, rot=(0, -(a - math.pi / 2), 0))
            xf(sp, (math.cos(a) * (r_out * 0.19 + ln / 2), 0, math.sin(a) * (r_out * 0.19 + ln / 2)))
            parts.append(sp)
    return merge(parts, name)


def chain(name, n=7, length=0.16, width=0.10, wire=0.02, mat="RustDark", segs=12, sides=6, path=None):
    """Цепь из n звеньев вдоль X (или по ломаной path — список точек): соседние звенья повёрнуты на 90° вокруг оси."""
    parts = []
    pitch = length - 2.0 * wire
    if path is None:
        path = [Vector((i * pitch - (n - 1) * pitch / 2, 0.0, 0.0)) for i in range(n)]
    for i, pnt in enumerate(path):
        l = link_mesh("%s_l%d" % (name, i), length, width, wire, M(mat), segs, sides)
        if i + 1 < len(path):
            d = (path[i + 1] - pnt)
        else:
            d = (pnt - path[i - 1]) if i > 0 else Vector((1, 0, 0))
        d = d.normalized() if d.length > 1e-6 else Vector((1, 0, 0))
        q = Vector((1, 0, 0)).rotation_difference(d)
        roll = (math.pi / 2 if i % 2 else 0.0) + RNG.uniform(-0.25, 0.25)
        xf(l, pnt, q.to_matrix().to_4x4() @ Matrix.Rotation(roll, 4, 'X'))
        parts.append(l)
    return merge(parts, name)


def bolt(name, L=0.16, r=0.011, mat="IronDark", lod=0):
    parts = [cyl(name, r, L, 'Z', M(mat), segs=(8, 6, 5)[lod])]
    xf(parts[0], (0, 0, L / 2))
    hd = cyl(name + "_h", r * 1.9, r * 1.2, 'Z', M(mat), segs=6)
    xf(hd, (0, 0, L + r * 0.6))
    parts.append(hd)
    if lod == 0:
        w = tube(name + "_w", r * 1.05, r * 2.3, 0.004, 'Z', M("Rust"), segs=10)
        xf(w, (0, 0, L - 0.002))
        parts.append(w)
        for k in range(3):                                      # витки резьбы у конца
            tr = tube(name + "_t", r * 0.9, r * 1.1, 0.004, 'Z', M(mat), segs=8)
            xf(tr, (0, 0, 0.012 + k * 0.012))
            parts.append(tr)
    return merge(parts, name)


def nut(name, r_out=0.022, r_in=0.011, h=0.018, mat="IronDark"):
    return tube(name, r_in, r_out, h, 'Z', M(mat), segs=6)


def nail(name, L=0.1, mat="Rust", lod=0, bent=0.5):
    a = cyl(name, 0.0035, L * 0.6, 'Z', M(mat), segs=4)
    xf(a, (0, 0, L * 0.3))
    b = cyl(name + "_b", 0.0035, L * 0.42, 'Z', M(mat), segs=4)
    xf(b, (0, 0, L * 0.21))
    xf(b, rot=(bent, 0, 0))
    xf(b, (0, 0, L * 0.6))
    hd = cyl(name + "_h", 0.008, 0.003, 'Z', M(mat), segs=6)
    xf(hd, (0, 0, 0))
    return merge([a, b, hd], name)


def pipe_piece(name, L=0.45, r=0.05, mat="Rust", lod=0):
    segs = (10, 8, 6)[lod]
    p = tube(name, r * 0.84, r, L, 'X', M(mat), segs=segs)
    for v in p.data.vertices:
        if v.co.x > L / 2 - 1e-4:
            v.co.x -= RNG.uniform(0.0, 0.06)                   # рваный конец
    parts = [p]
    fl = tube(name + "_fl", r * 0.84, r * 1.5, 0.022, 'X', M("RustDark"), segs=segs)
    xf(fl, (-L / 2 + 0.011, 0, 0))
    parts.append(fl)
    if lod == 0:
        for k in range(4):
            a = TAU * k / 4 + 0.4
            parts.append(rivet(name + "_b", (-L / 2 + 0.026, r * 1.25 * math.cos(a), r * 1.25 * math.sin(a)), (1, 0, 0),
                               r=0.008, h=0.012, segs=6))
    return merge(parts, name)


def sword(name, blade=0.42, broken=True, mat="Rust", grip="ClothWrap", lod=0):
    """Меч вдоль +X: клинок ромбом (сломан — рваный конец), гарда, обмотка рукояти, навершие. Хват в нуле."""
    w, t = 0.05, 0.012
    bm = bmesh.new()
    rings = []
    zs = [0.0, blade * 0.55, blade]
    for k, z in enumerate(zs):
        ww = w * (1.0 - 0.18 * z / blade)
        ring = [bm.verts.new((z, -t / 2 if i == 1 else (t / 2 if i == 3 else 0.0), (ww / 2 if i == 0 else (-ww / 2 if i == 2 else 0.0))))
                for i in range(4)]
        rings.append(ring)
    if broken:
        for i, v in enumerate(rings[-1]):
            v.co.x -= RNG.uniform(0.0, 0.07) if i != 0 else RNG.uniform(0.04, 0.09)
    else:
        tip = bm.verts.new((blade + 0.12, 0.0, 0.0))
    for a, b in zip(rings, rings[1:]):
        for i in range(4):
            j = (i + 1) % 4
            bm.faces.new((a[i], a[j], b[j], b[i]))
    bm.faces.new(list(reversed(rings[0])))
    if broken:
        bm.faces.new(rings[-1])
    else:
        for i in range(4):
            bm.faces.new((rings[-1][i], rings[-1][(i + 1) % 4], tip))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bl = mesh_obj(name, bm, [M(mat)])
    C.uv_box(bl, 1.0, 'X')
    uv_shift(bl, RNG.uniform(0, 1), RNG.uniform(0, 1))
    parts = [bl]
    gd = box(name + "_g", (0.03, 0.035, 0.19), M("RustDark" if mat == "Rust" else "Rust"), along='Z')
    if lod == 0:
        bevel_apply(gd, 0.006, 1)
    parts.append(gd)
    gr = cyl(name + "_gr", 0.016, 0.13, 'X', M(grip), segs=(8, 6, 5)[lod])
    xf(gr, (-0.08, 0, 0))
    parts.append(gr)
    pm = sphere(name + "_p", 0.024, M("Brass" if lod == 0 else "RustDark"), (8, 6, 5)[lod], (5, 4, 4)[lod])
    xf(pm, (-0.16, 0, 0))
    parts.append(pm)
    return merge(parts, name)


def helmet(name, mat="Rust", lod=0):
    """Шлем-шапель: полый купол (стенка 8 мм, внутри тёмный), поля, налобный пояс, навершие; lod 0 — прорезь визора."""
    segs = (12, 9, 8)[lod]
    if lod == 0:
        outer = [(0.16, 0.0), (0.137, 0.02), (0.137, 0.09), (0.124, 0.16), (0.088, 0.21), (0.03, 0.232)]
        inner = [(0.03, 0.224), (0.1, 0.185), (0.129, 0.09), (0.129, 0.024), (0.15, 0.0)]
    else:
        outer = [(0.155, 0.0), (0.137, 0.022), (0.132, 0.12), (0.09, 0.2), (0.03, 0.23)]
        inner = [(0.03, 0.222), (0.12, 0.12), (0.148, 0.004)]
    bands = [0] * (len(outer) - 1) + [0] + [1] * (len(inner) - 1) + [0]
    h = lathe(name, outer + inner, segs, [M(mat), M("Char")], 'Z', loop=True, band_mat=bands)
    parts = [h]
    top = sphere(name + "_top", 0.036, M("RustDark"), (6, 6, 5)[lod], (4, 4, 3)[lod])
    xf(top, (0, 0, 0.228), scale=(1, 1, 0.6))
    parts.append(top)
    if lod == 0:
        slit = box(name + "_slit", (0.15, 0.2, 0.02), M("Char"))
        xf(slit, (0, -0.12, 0.105))
        boolean(h, [slit])
        bd = tube(name + "_bd", 0.136, 0.143, 0.03, 'Z', M("RustDark"), segs=segs)
        xf(bd, (0, 0, 0.05))
        parts.append(bd)
        for k in range(5):
            a = -math.pi / 2 + (k - 2) * 0.55
            parts.append(rivet(name + "_rv", (0.144 * math.cos(a), 0.144 * math.sin(a), 0.05), (math.cos(a), math.sin(a), 0),
                               r=0.008, h=0.008, segs=5))
    else:
        s = ngon_disc(name + "_slit", 0.07, 0.01, 4, M("Char"))
        xf(s, (0, -0.139, 0.105))
        parts.append(s)
    return merge(parts, name)


def crown_quad(name, size, loc, mat="CrownGold", normal=(0, -1, 0)):
    """Квад с декалью короны (UV 0..1), лицом в normal."""
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    w, h = size
    vs = [bm.verts.new((-w / 2, 0, -h / 2)), bm.verts.new((w / 2, 0, -h / 2)), bm.verts.new((w / 2, 0, h / 2)), bm.verts.new((-w / 2, 0, h / 2))]
    f = bm.faces.new(vs)
    for l, uv in zip(f.loops, ((0, 0), (1, 0), (1, 1), (0, 1))):
        l[uvl].uv = uv
    f.normal_update()
    if f.normal.y > 0:
        f.normal_flip()
    o = mesh_obj(name, bm, [M(mat)])
    q = Vector((0, -1, 0)).rotation_difference(Vector(normal))
    return xf(o, loc, q)


def shield(name, w=0.55, h=0.7, lod=0, face="RustRed", crown="CrownGold"):
    """Щит-«утюг» лицом к камере (плоскость XZ, выпуклость к −Y), низ-остриё в z=0: красное поле, ржавый обод, корона."""
    out = []
    for i in range(5):
        out.append((-w / 2 + w * i / 4, h))
    for (fx, fz) in ((0.5, 0.56), (0.44, 0.34), (0.3, 0.14), (0.0, 0.0), (-0.3, 0.14), (-0.44, 0.34), (-0.5, 0.56)):
        out.append((fx * w, fz * h))
    out = list(reversed(out))
    rim = plate(name + "_rim", [(x * 1.07, (z - h * 0.5) * 1.06 + h * 0.5) for x, z in out], 0.03, M("Rust"))
    xf(rim, (0, 0.006, 0))
    fc = plate(name, out, 0.02, M(face))
    parts = [fc, rim]
    for o in parts:
        for v in o.data.vertices:
            v.co.y += 0.09 * (v.co.x / (w / 2)) ** 2          # выпуклость
    cq = crown_quad(name + "_crown", (0.32, 0.32), (0, -0.018, h * 0.6), crown)
    parts.append(cq)
    if lod == 0:
        for k in range(8):
            x, z = out[(k * len(out)) // 8]
            x, z = x * 1.035, (z - h * 0.5) * 1.03 + h * 0.5
            parts.append(rivet(name + "_rv", (x, -0.012 + 0.09 * (x / (w / 2)) ** 2, z), (0, -1, 0), r=0.012, h=0.01, segs=6))
    return merge(parts, name)


def hammer(name, lod=0, haft=0.78, mat_head="Rust", mat_haft="ScrapWoodDark"):
    """Молот вдоль +X: рукоять от 0, боёк на конце (поперёк, вдоль Z)."""
    hf = cyl(name, 0.02, haft, 'X', M(mat_haft), segs=(8, 6, 5)[lod])
    xf(hf, (haft / 2, 0, 0))
    hd = box(name + "_hd", (0.1, 0.1, 0.22), M(mat_head), along='Z', taper=(0.9, 0.9))
    if lod == 0:
        bevel_apply(hd, 0.01, 1)
    xf(hd, (haft - 0.03, 0, 0.02))
    parts = [hf, hd]
    for dz in (-0.06, 0.1):
        b = box(name + "_b", (0.108, 0.108, 0.02), M("IronDark"), along='Z')
        xf(b, (haft - 0.03, 0, dz))
        parts.append(b)
    wr = cyl(name + "_wr", 0.023, 0.16, 'X', M("ClothWrap" if lod == 0 else mat_haft), segs=(8, 6, 5)[lod])
    xf(wr, (0.1, 0, 0))
    parts.append(wr)
    return merge(parts, name)


def axe(name, lod=0, haft=0.72, double=False, mat="Rust"):
    hf = cyl(name, 0.018, haft, 'X', M("ScrapWood"), segs=(8, 6, 5)[lod])
    xf(hf, (haft / 2, 0, 0))
    parts = [hf]
    sides = (1, -1) if double else (1,)
    for s in sides:
        bl = plate(name + "_bl", [(-0.045, 0.0), (0.045, 0.0), (0.09, 0.2), (0.0, 0.23), (-0.09, 0.2)], 0.012, M(mat))
        if s < 0:
            xf(bl, rot=(0, math.pi, 0))                        # второе лезвие вниз (двуручный топор)
        xf(bl, (haft - 0.07, 0, 0.02 * s))
        parts.append(bl)
    ey = box(name + "_eye", (0.08, 0.05, 0.07), M("RustDark"), along='Z')
    xf(ey, (haft - 0.07, 0, 0))
    parts.append(ey)
    if not double:
        pl = box(name + "_poll", (0.05, 0.045, 0.06), M("RustDark"))
        xf(pl, (haft - 0.07, 0, -0.06))
        parts.append(pl)
    return merge(parts, name)


def mace(name, lod=0, haft=0.6):
    hf = cyl(name, 0.018, haft, 'X', M("WoodDark"), segs=(8, 6, 5)[lod])
    xf(hf, (haft / 2, 0, 0))
    hd = sphere(name + "_hd", 0.065, M("Rust"), (8, 7, 6)[lod], (6, 5, 4)[lod])
    xf(hd, (haft + 0.04, 0, 0))
    parts = [hf, hd]
    dirs = [(0, 0, 1), (0, 0, -1), (0, 1, 0), (0, -1, 0), (1, 0, 0), (0.6, 0.6, 0.5), (0.6, -0.6, -0.5), (0.6, 0.6, -0.5), (0.6, -0.6, 0.5)]
    for d in dirs[:(9 if lod == 0 else 6)]:
        sp = lathe(name + "_sp", [(0.0, 0.0), (0.022, 0.0), (0.0, 0.06)], 4, [M("RustDark")])
        d = Vector(d).normalized()
        xf(sp, Vector((haft + 0.04, 0, 0)) + d * 0.055, align_z(d))
        parts.append(sp)
    wr = cyl(name + "_wr", 0.021, 0.15, 'X', M("RustRed" if lod else "ClothRed"), segs=(8, 6, 5)[lod])
    xf(wr, (0.1, 0, 0))
    parts.append(wr)
    return merge(parts, name)


# ----------------------------------------------------------------------------------------------------------------------
# куски bits: имя → (функция, seed, масса-подсказка для отчёта — сами массы живут в builder-е Godot)
# ----------------------------------------------------------------------------------------------------------------------
BITS = [
    ("Doll_Head_Sad", lambda n: doll_head(n, "Sad", "DollWood", 0), 101),
    ("Doll_Head_Scared", lambda n: doll_head(n, "Scared", "DollPale", 0), 102),
    ("Doll_Head_Cracked", lambda n: doll_head(n, "Cracked", "DollDark", 0), 103),
    ("Doll_Limb_Upper", lambda n: limb(n, 0.40, 0.052, "DollWood", 0, paint_n=1), 104),
    ("Doll_Limb_Lower", lambda n: limb(n, 0.36, 0.043, "DollPale", 0), 105),
    ("Doll_Hand", lambda n: hand(n, "DollWood", 0), 106),
    ("Doll_Foot", lambda n: foot(n, "DollWood", 0), 107),
    ("Doll_Torso_Shell", lambda n: torso(n, "DollWood", 0), 108),
    ("Scrap_Board", lambda n: board(n, 0.9, 0.15, 0.03, "ScrapWood", (False, True), nails=2), 109),
    ("Rivet_Plate", lambda n: rivet_plate(n, 0.5, 0.36, 0.012, "Rust", 0), 110),
    ("Gear_Small", lambda n: gear(n, 10, 0.12, 0.03, "Rust", hole=0.28), 111),
    ("Gear_Medium", lambda n: gear(n, 14, 0.25, 0.04, "Rust", hole=0.22), 112),
    ("Gear_Large", lambda n: gear(n, 18, 0.45, 0.05, "Rust", spokes=4), 113),
    ("Chain_Link", lambda n: link_mesh(n, 0.16, 0.10, 0.02, M("RustDark"), 12, 6), 114),
    ("Chain_Segment", lambda n: chain(n, 7, 0.16, 0.10, 0.02, "RustDark", 10, 4), 115),
    ("Bolt", lambda n: bolt(n, 0.16, 0.011, "IronDark", 0), 116),
    ("Nut", lambda n: nut(n), 117),
    ("Nail", lambda n: nail(n, 0.1, "Rust", 0), 118),
    ("Pipe_Piece", lambda n: pipe_piece(n, 0.45, 0.05, "Rust", 0), 119),
    ("Sword_Broken", lambda n: sword(n, 0.42, True, "Rust", "ClothWrap", 0), 120),
    ("Helmet", lambda n: helmet(n, "Rust", 0), 121),
    ("Shield_Crown", lambda n: shield(n, 0.55, 0.7, 0), 122),
    ("Hammer_Old", lambda n: hammer(n, 0), 123),
    ("Axe_Old", lambda n: axe(n, 0), 124),
    ("Mace_Old", lambda n: mace(n, 0), 125),
]


# ----------------------------------------------------------------------------------------------------------------------
# кучи: холм-основание (scrap_dirt / ржавчина) + куски, утопленные в него (детерминированно по seed)
# ----------------------------------------------------------------------------------------------------------------------
def _smooth01(t):
    t = min(1.0, max(0.0, t))
    return t * t * (3.0 - 2.0 * t)


class Mound:
    """Холм в эллипсе a × b (полуоси по X и Y): максимум «колоколов» peaks [(px, py, h, ra, rb)] ∙ (1 − r²)^power,
    плавное затухание к краю эллипса, value-noise (амплитуда noise, масштаб nscale м); за краем — base (под полом)."""

    def __init__(self, a, b, peaks, noise=0.05, nscale=0.35, power=1.3, base=-0.03, salt=0):
        self.a, self.b, self.peaks, self.noise, self.nscale, self.power, self.base = a, b, peaks, noise, nscale, power, base
        self.salt = salt + RNG.randrange(1 << 20)

    def _lat(self, i, j):
        return random.Random((i * 73856093) ^ (j * 19349663) ^ (self.salt * 83492791)).random()

    def vnoise(self, x, y):
        i, j = math.floor(x), math.floor(y)
        fx, fy = _smooth01(x - i), _smooth01(y - j)
        a = self._lat(i, j) + (self._lat(i + 1, j) - self._lat(i, j)) * fx
        b = self._lat(i, j + 1) + (self._lat(i + 1, j + 1) - self._lat(i, j + 1)) * fx
        return a + (b - a) * fy

    def body(self, x, y):
        v = 0.0
        for px, py, ph, ra, rb in self.peaks:
            r2 = ((x - px) / ra) ** 2 + ((y - py) / rb) ** 2
            if r2 < 1.0:
                v = max(v, ph * (1.0 - r2) ** self.power)
        return v

    def h(self, x, y):
        e = (x / self.a) ** 2 + (y / self.b) ** 2
        if e >= 1.0:
            return self.base
        v = self.body(x, y) * _smooth01((1.0 - e) / 0.3)
        n = (self.vnoise(x / self.nscale, y / self.nscale) - 0.5) * 2.0 * self.noise
        n += (self.vnoise(x / self.nscale * 2.7 + 17.0, y / self.nscale * 2.7 + 5.0) - 0.5) * self.noise
        return max(self.base, v + n * min(1.0, v * 5.0))

    def normal(self, x, y, d=0.03):
        dx = (self.h(x + d, y) - self.h(x - d, y)) / (2 * d)
        dy = (self.h(x, y + d) - self.h(x, y - d)) / (2 * d)
        return Vector((-dx, -dy, 1.0)).normalized()

    def sample(self, rmax=0.92, front=0.6, rmin=0.0, xr=None):
        """Точка в эллипсе (равномерно по площади), с вероятностью front — на передней (−Y) половине."""
        for _ in range(64):
            r = math.sqrt(RNG.uniform(rmin * rmin, rmax * rmax))
            t = RNG.uniform(0, TAU)
            x, y = self.a * r * math.cos(t), self.b * r * math.sin(t)
            if y > 0 and RNG.random() < front:
                y = -y
            if xr is None or xr[0] <= x <= xr[1]:
                return x, y
        return x, y


def rest(o, z=0.0):
    """Поднимает меш так, чтобы низ габарита был не ниже z (кусок не уходит под пол)."""
    mn, mx = bbox(o)
    if mn.z < z:
        xf(o, (0, 0, z - mn.z))
    return o


def uv_rotate(o, ang, scale=1.0):
    """Поворот и масштаб развёртки (у больших холмов тайл scrap_dirt 1 м иначе заметно повторяется)."""
    ca, sa = math.cos(ang), math.sin(ang)
    for d in o.data.uv_layers[0].data:
        u, v = d.uv
        d.uv = ((u * ca - v * sa) * scale, (u * sa + v * ca) * scale)
    return o


def mound_mesh(name, md, rings=7, segs=20, mat="Dirt"):
    bm = bmesh.new()
    c = bm.verts.new((0.0, 0.0, md.h(0.0, 0.0)))
    prev = None
    radii = [((k + 1) / rings) ** 0.85 for k in range(rings)] + [1.04]
    for k, r in enumerate(radii):
        off = (0.5 if k % 2 else 0.0) * TAU / segs
        ring = []
        for i in range(segs):
            t = TAU * i / segs + off + RNG.uniform(-0.25, 0.25) * TAU / segs * (1 if r < 1.0 else 0)
            x, y = md.a * r * math.cos(t), md.b * r * math.sin(t)
            z = md.h(x, y) if r < 1.0 else md.base - 0.02
            ring.append(bm.verts.new((x, y, z)))
        if prev is None:
            for i in range(segs):
                bm.faces.new((c, ring[i], ring[(i + 1) % segs]))
        else:
            for i in range(segs):
                j = (i + 1) % segs
                bm.faces.new((prev[i], ring[i], ring[j], prev[j]))
        prev = ring
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        if f.normal.z < 0:
            f.normal_flip()
    o = mesh_obj(name, bm, [M(mat)])
    C.uv_box(o, 1.0)
    big = max(md.a, md.b)
    uv_rotate(o, RNG.uniform(0, TAU), 1.0 if big < 1.2 else 0.7)
    uv_shift(o, RNG.uniform(0, 1), RNG.uniform(0, 1))
    return o


def put_on(o, md, x, y, sink=0.3, yaw=None, tilt=0.0, lift=0.0, up=None):
    """Кладёт кусок (центр габарита в нуле, «толщина» по локальной Z) на поверхность холма в (x, y): Z куска → нормаль
    холма (или up), поворот yaw вокруг неё, наклон tilt в случайную сторону; sink 0 — лежит сверху, 0.5 — утоплен
    наполовину, 1 — целиком."""
    center(o)
    mn, mx = bbox(o)
    hz = (mx.z - mn.z) / 2
    n = up if up is not None else md.normal(x, y)
    yaw = RNG.uniform(0, TAU) if yaw is None else yaw
    td = RNG.uniform(0, TAU)
    R = align_z(n) @ Matrix.Rotation(tilt, 4, Vector((math.cos(td), math.sin(td), 0.0))) @ Matrix.Rotation(yaw, 4, 'Z')
    z = md.h(x, y)
    loc = Vector((x, y, z)) + Vector(n) * (hz * (1.0 - 2.0 * sink)) + Vector((0, 0, lift))
    return xf(o, loc, R)


def stick(o, md, x, y, pitch, yaw, bury=0.35):
    """Длинный кусок (вдоль локальной X) торчит из холма: поднят на pitch (рад) к +X, повёрнут yaw вокруг Z; нижний
    конец утоплен на долю bury длины."""
    center(o)
    mn, mx = bbox(o)
    L = mx.x - mn.x
    R = Matrix.Rotation(yaw, 4, 'Z') @ Matrix.Rotation(-pitch, 4, 'Y')
    d = R @ Vector((1.0, 0.0, 0.0))
    base = Vector((x, y, md.h(x, y)))
    loc = base + d * (L * (0.5 - bury))
    return xf(o, loc, R)


def uv_jitter(o):
    return uv_shift(o, RNG.uniform(0, 1), RNG.uniform(0, 1))


def block(name, size, mat):
    o = box(name, size, M(mat), jitter=min(size) * 0.06, along='Z')
    return o


def bracket(name, L=0.3, w=0.08, t=0.012, mat="Rust"):
    a = box(name, (L, w, t), M(mat))
    b = box(name + "_b", (t, w, L * 0.6), M(mat), along='Z')
    xf(b, (L / 2 - t / 2, 0, L * 0.3 - t / 2))
    return merge([a, b], name)


def piston(name, r=0.07, L=0.3, mat="IronDark", lod=1):
    segs = 10 if lod <= 1 else 8
    c = cyl(name, r, L, 'X', M(mat), segs=segs)
    f = tube(name + "_f", r * 0.9, r * 1.35, 0.03, 'X', M("Rust"), segs=segs)
    xf(f, (-L / 2 + 0.02, 0, 0))
    rod = cyl(name + "_r", r * 0.35, L * 0.6, 'X', M("Iron"), segs=6)
    xf(rod, (L / 2 + L * 0.28, 0, 0))
    return merge([c, f, rod], name)


def hoop(name, r=0.3, w=0.04, mat="Rust", squash=0.85):
    o = tube(name, r - 0.008, r, w, 'Y', M(mat), segs=14)
    for v in o.data.vertices:
        v.co.z *= squash
    return o


def wheel(name, r=0.4, mat="ScrapWood", spokes=6, broken=2, lod=1):
    """Тележное колесо в плоскости XZ: деревянный обод, железная шина, ступица, спицы (broken штук выломано)."""
    segs = 14 if lod <= 1 else 10
    rim = tube(name, r - 0.06, r - 0.012, 0.06, 'Y', M(mat), segs=segs)
    tire = tube(name + "_t", r - 0.013, r, 0.064, 'Y', M("Rust"), segs=segs)
    hub = cyl(name + "_h", 0.07, 0.16, 'Y', M("WoodDark"), segs=8)
    parts = [rim, tire, hub]
    gone = set(RNG.sample(range(spokes), broken)) if broken else set()
    for k in range(spokes):
        a = TAU * k / spokes
        ln = r - 0.06 - 0.06 if k not in gone else (r - 0.12) * RNG.uniform(0.3, 0.5)
        sp = box(name + "_s", (0.035, 0.035, ln), M(mat), along='Z')
        xf(sp, (0, 0, 0.06 + ln / 2))
        xf(sp, rot=(0, a, 0))
        parts.append(sp)
    return merge(parts, name)


def crate_frag(name, s=0.5, mat="ScrapWood", lod=1):
    """Обломок ящика: угол из двух стенок (по 2–3 доски, часть сломана короче), днище, железный уголок."""
    parts = []
    t = 0.022
    n = 3
    h = s / n
    for wall in range(2):
        for k in range(n):
            L = s * (RNG.uniform(0.45, 0.95) if RNG.random() < 0.45 else 1.0)
            b = board(name + "_w", L, h - 0.01, t, mat, (False, L < s * 0.97))
            xf(b, rot=(math.pi / 2, 0, 0))                           # доска стоит ребром: ширина по Z
            if wall == 0:
                xf(b, (L / 2 - s / 2, -s / 2, h * (k + 0.5)))
            else:
                xf(b, rot=(0, 0, math.pi / 2))
                xf(b, (-s / 2, L / 2 - s / 2, h * (k + 0.5)))
            parts.append(b)
    for k in range(2):
        L = s * RNG.uniform(0.6, 1.0)
        b = board(name + "_d", L, s / 2 - 0.01, t, mat, (False, True))
        xf(b, (L / 2 - s / 2, -s / 2 + s / 4 + k * s / 2, t / 2))
        parts.append(b)
    br = box(name + "_br", (0.06, 0.06, s * 0.9), M("Rust"), along='Z')
    xf(br, (-s / 2 + 0.01, -s / 2 + 0.01, s * 0.45))
    parts.append(br)
    o = merge(parts, name)
    return center(o)


def curved_plate(name, w=0.4, h=0.3, rad=0.35, t=0.01, mat="Rust", nx=4):
    """Изогнутая пластина (кусок цилиндра радиуса rad), лицом к +Z: наплечник, нагрудник."""
    bm = bmesh.new()
    top, bot = [], []
    for i in range(nx + 1):
        a = (i / nx - 0.5) * (w / rad)
        x = rad * math.sin(a)
        z = rad * math.cos(a) - rad
        top.append([bm.verts.new((x, y, z + t / 2)) for y in (-h / 2, h / 2)])
        bot.append([bm.verts.new((x, y, z - t / 2)) for y in (-h / 2, h / 2)])
    for i in range(nx):
        bm.faces.new((top[i][0], top[i + 1][0], top[i + 1][1], top[i][1]))
        bm.faces.new((bot[i][1], bot[i + 1][1], bot[i + 1][0], bot[i][0]))
        bm.faces.new((top[i][0], bot[i][0], bot[i + 1][0], top[i + 1][0]))
        bm.faces.new((top[i + 1][1], bot[i + 1][1], bot[i][1], top[i][1]))
    bm.faces.new((top[0][0], top[0][1], bot[0][1], bot[0][0]))
    bm.faces.new((bot[nx][0], bot[nx][1], top[nx][1], top[nx][0]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = mesh_obj(name, bm, [M(mat)])
    C.uv_box(o, 1.0)
    uv_jitter(o)
    return center(o)


def wire_path(name, pts, r, mat, sides=5):
    """Трубка радиуса r по ломаной pts (дужка ведра, концы верёвки, провода)."""
    bm = bmesh.new()
    rings = []
    for i, p in enumerate(pts):
        d = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        q = Vector((0, 0, 1)).rotation_difference(d)
        ring = [bm.verts.new(p + q @ Vector((r * math.cos(TAU * k / sides), r * math.sin(TAU * k / sides), 0))) for k in range(sides)]
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        for k in range(sides):
            kk = (k + 1) % sides
            bm.faces.new((a[k], a[kk], b[kk], b[k]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = mesh_obj(name, bm, [M(mat)])
    C.uv_cylinder_along(o, 'Z', 4.0)
    return o


def rubble(name, s, mat):
    o = box(name, (s * RNG.uniform(0.7, 1.3), s * RNG.uniform(0.7, 1.3), s * RNG.uniform(0.4, 0.8)), M(mat), jitter=s * 0.2)
    return o


def junk_piece(i, scale=1.0, lod=1, weights=None):
    """Случайный кусок хлама для куч: доска / пластина / блок / уголок / труба / болт — по весам."""
    kinds = weights or {"board": 6, "plate": 3, "block": 1.2, "bracket": 0.8, "pipe": 0.6, "bolt": 0.5}
    tot = sum(kinds.values())
    r = RNG.uniform(0, tot)
    for k, w in kinds.items():
        r -= w
        if r <= 0:
            break
    n = "junk%d" % i
    if k == "board":
        L = RNG.uniform(0.25, 0.7) * scale
        return board(n, L, RNG.uniform(0.07, 0.15) * min(1.6, scale), 0.025 * min(2.0, scale),
                     RNG.choice(("ScrapWood", "ScrapWood", "ScrapWoodDark", "WoodDark")), (RNG.random() < 0.4, RNG.random() < 0.7))
    if k == "plate":
        m = RNG.choice(("Rust", "Rust", "RustDark", "RustRed"))
        return rivet_plate(n, RNG.uniform(0.2, 0.42) * scale, RNG.uniform(0.14, 0.3) * scale, 0.012 * min(2.0, scale), m, 1,
                           bend=RNG.uniform(-0.03, 0.04) * scale, cut=RNG.random() < 0.5)
    if k == "block":
        return block(n, tuple(RNG.uniform(0.08, 0.2) * scale for _ in range(3)), RNG.choice(("RustDark", "IronDark", "Rust")))
    if k == "bracket":
        return center(bracket(n, RNG.uniform(0.18, 0.32) * scale, 0.07 * scale, 0.012 * scale, RNG.choice(("Rust", "RustDark"))))
    if k == "pipe":
        return pipe_piece(n, RNG.uniform(0.3, 0.55) * scale, RNG.uniform(0.035, 0.06) * scale, RNG.choice(("Rust", "RustDark")), 1)
    return center(bolt(n, 0.14 * scale, 0.013 * scale, "IronDark", 2))


def scatter(parts, md, count, maker, rmax=0.92, front=0.6, sink=(0.15, 0.55), tilt=(0.0, 0.6), rmin=0.0, xr=None):
    for i in range(count):
        o = maker(i)
        x, y = md.sample(rmax, front, rmin, xr)
        put_on(o, md, x, y, RNG.uniform(*sink), None, RNG.uniform(*tilt))
        parts.append(o)


def bvh_of(objs):
    verts, polys = [], []
    for o in objs:
        base = len(verts)
        verts += [v.co.copy() for v in o.data.vertices]
        polys += [[base + i for i in p.vertices] for p in o.data.polygons]
    return BVHTree.FromPolygons(verts, polys)


def drape(name, under, cx, cy, w, d, nx, ny, mat, yaw=0.0, lift=0.012, smooth_it=4, tatter=0.18, holes=0,
          crown=None, crown_mat="Crown", ripple=0.02, bvh=None):
    """Ткань: подразделённая плоскость w × d (nx × ny квадов), опущенная лучами сверху на геометрию `under` (холм + куски)
    и пол, сглаженная (ткань натягивается шатром над острыми кусками), с рваным краем (tatter — доля краевых квадов
    удаляется, края дрожат) и дырами. crown=(u0, u1, v0, v1) — область декали короны (копия граней на 5 мм над тканью)."""
    bvh = bvh or bvh_of(under)
    ca, sa = math.cos(yaw), math.sin(yaw)
    grid, base = [], []
    for j in range(ny + 1):
        row, brow = [], []
        for i in range(nx + 1):
            lx, ly = (i / nx - 0.5) * w, (j / ny - 0.5) * d
            x, y = cx + lx * ca - ly * sa, cy + lx * sa + ly * ca
            hit = bvh.ray_cast(Vector((x, y, 6.0)), Vector((0, 0, -1)))
            hz = hit[0].z if hit[0] is not None else 0.0
            hz = max(hz, 0.0)
            row.append([x, y, hz + lift])
            brow.append(hz + lift * 0.5)
        grid.append(row)
        base.append(brow)
    for _ in range(smooth_it):
        new = [[p[2] for p in r] for r in grid]
        for j in range(ny + 1):
            for i in range(nx + 1):
                nb = [grid[jj][ii][2] for jj, ii in ((j - 1, i), (j + 1, i), (j, i - 1), (j, i + 1)) if 0 <= jj <= ny and 0 <= ii <= nx]
                new[j][i] = max(base[j][i], 0.5 * grid[j][i][2] + 0.5 * sum(nb) / len(nb))
        for j in range(ny + 1):
            for i in range(nx + 1):
                grid[j][i][2] = new[j][i]
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    V = []
    for j in range(ny + 1):
        vr = []
        for i in range(nx + 1):
            x, y, z = grid[j][i]
            z += ripple * math.sin(i * 1.7 + j * 0.6) * math.sin(j * 1.3) * (1.0 if z > 0.05 else 0.3)
            edge = i in (0, nx) or j in (0, ny)
            if edge:
                x += RNG.uniform(-0.03, 0.03)
                y += RNG.uniform(-0.03, 0.03)
            vr.append(bm.verts.new((x, y, max(z, 0.004))))
        V.append(vr)
    skip = set()
    for j in range(ny):
        for i in range(nx):
            border = i in (0, nx - 1) or j in (0, ny - 1)
            if border and RNG.random() < tatter:
                skip.add((i, j))
    for _ in range(holes):
        skip.add((RNG.randrange(1, nx - 1), RNG.randrange(1, ny - 1)))
    faces = {}
    for j in range(ny):
        for i in range(nx):
            if (i, j) in skip:
                continue
            f = bm.faces.new((V[j][i], V[j][i + 1], V[j + 1][i + 1], V[j + 1][i]))
            faces[(i, j)] = f
            for l in f.loops:
                ii = i + (1 if l.vert in (V[j][i + 1], V[j + 1][i + 1]) else 0)
                jj = j + (1 if l.vert in (V[j + 1][i], V[j + 1][i + 1]) else 0)
                l[uvl].uv = (ii / nx * w, jj / ny * d)
    for f in bm.faces:
        f.normal_update()
        if f.normal.z < 0:
            f.normal_flip()
    bm.normal_update()
    if crown:
        u0, u1, v0, v1 = crown
        vmap = {}
        for j in range(int(v0 * ny), int(math.ceil(v1 * ny))):
            for i in range(int(u0 * nx), int(math.ceil(u1 * nx))):
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
                for l, lo in zip(nf.loops, f.loops):
                    ii = round(lo[uvl].uv[0] / w * nx)
                    jj = round(lo[uvl].uv[1] / d * ny)
                    l[uvl].uv = ((ii / nx - u0) / (u1 - u0), (jj / ny - v0) / (v1 - v0))
    o = mesh_obj(name, bm, [M(mat)] + ([M(crown_mat)] if crown else []))
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def basis(up, front):
    """Матрица поворота: локальная +Z → up, локальная −Y (лицо) → front (ортогонализуется к up)."""
    z = Vector(up).normalized()
    f = Vector(front)
    f = (f - z * f.dot(z)).normalized()
    y = -f
    x = y.cross(z)
    return Matrix((x, y, z)).transposed().to_4x4()


def seg_to(parts, name, start, end, r, mat, lod=1, ball=True, ferrule=False, segs=None, paint_n=0):
    """Сегмент конечности от сустава start к end: шар — у start, тёмный торец — у end."""
    start, end = Vector(start), Vector(end)
    d = end - start
    o = limb(name, d.length, r, mat, lod, ball=ball, ferrule=ferrule, paint_n=paint_n)
    xf(o, end, align_z(-d, RNG.uniform(0, TAU)))
    parts.append(o)
    return o


def reach(start, L, hdir, z_end):
    """Конец сегмента длины L из start в горизонтальном направлении hdir, на высоте z_end (ограничено длиной)."""
    start = Vector(start)
    dz = max(-L * 0.98, min(L * 0.98, z_end - start.z))
    hl = math.sqrt(max(0.0, L * L - dz * dz))
    h = Vector((hdir[0], hdir[1], 0.0)).normalized()
    return start + h * hl + Vector((0, 0, dz))


def pelvis(name, mat):
    return lathe(name, [(0.0, 0.0), (0.11, 0.0), (0.145, 0.06), (0.13, 0.14), (0.0, 0.16)], 10, [M(mat)], sy=0.7)


def flag(name, w=0.7, h=1.0, nx=6, ny=8, mat="ClothRed"):
    """Рваный флаг, висит вниз от z=0 в плоскости XZ (лицом −Y), с короной-декалью."""
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    V = []
    for j in range(ny + 1):
        row = []
        for i in range(nx + 1):
            x = (i / nx - 0.5) * w
            z = -h * j / ny
            y = 0.05 * math.sin(i * 1.3 + j * 0.8) * (j / ny)
            if j == ny:
                z += RNG.uniform(0.0, 0.2)
            row.append(bm.verts.new((x, y, z)))
        V.append(row)
    for j in range(ny):
        for i in range(nx):
            if j >= ny - 2 and RNG.random() < 0.3:
                continue
            f = bm.faces.new((V[j][i], V[j][i + 1], V[j + 1][i + 1], V[j + 1][i]))
            for l in f.loops:
                l[uvl].uv = (l.vert.co.x + w / 2, -l.vert.co.z)
    o = mesh_obj(name, bm, [M(mat)])
    for p in o.data.polygons:
        p.use_smooth = True
    c = crown_quad(name + "_crown", (w * 0.55, w * 0.55), (0, -0.03, -h * 0.35), "Crown")
    return merge([o, c], name)


def cut_below(o, z=0.0):
    """Срезает всё ниже z (boolean с большим боксом) — чтобы кусок стоял ровно на полу."""
    b = box(o.name + "_cut", (20.0, 20.0, 10.0), M("Char"))
    xf(b, (0, 0, z - 5.0))
    return boolean(o, [b])


# ----------------------------------------------------------------------------------------------------------------------
# ассеты №001–020. LOOSE_SPEC[name] = [(bit, x, roll_deg, rot)] — свободные R-куски сверху (S+R): высоту ставит профиль
# коллизии при экспорте; rot — поворот Blender куска до крена вокруг оси камеры.
# ----------------------------------------------------------------------------------------------------------------------
LOOSE_SPEC = {}
EXTRA = {}


def scrap_heap_small(name):
    md = Mound(0.8, 0.58, [(-0.08, 0.02, 0.45, 0.72, 0.52), (0.34, -0.05, 0.34, 0.42, 0.36)], noise=0.04, nscale=0.25, power=1.0)
    parts = [mound_mesh(name, md, 6, 18, "Dirt")]
    mast = board("mast", 1.05, 0.13, 0.035, "ScrapWood", (True, True), nails=1)
    stick(mast, md, -0.22, -0.02, math.radians(31), math.radians(12), bury=0.34)
    parts.append(mast)
    for k, (x, pitch, yaw, L) in enumerate(((0.45, 28, 160, 0.6), (-0.5, 22, -15, 0.55))):
        b = board("stk%d" % k, L, 0.1, 0.03, "ScrapWoodDark", (False, True))
        stick(b, md, x, RNG.uniform(-0.2, 0.1), math.radians(pitch), math.radians(yaw), 0.35)
        parts.append(b)
    cf = crate_frag("crate", 0.34, "ScrapWood")
    put_on(cf, md, 0.42, -0.3, 0.35, math.radians(20), 0.2)
    parts.append(cf)
    red = rivet_plate("red", 0.32, 0.2, 0.014, "RustRed", 1, bend=0.02)
    put_on(red, md, 0.25, -0.38, 0.1, math.radians(-10), 0.5)
    parts.append(red)
    g = gear("gear", 9, 0.11, 0.03, "Rust", hole=0.3)
    put_on(g, md, -0.35, -0.25, 0.4, 0.3, 0.3, up=Vector((0.1, -0.9, 0.4)))
    parts.append(g)
    scatter(parts, md, 46, lambda i: junk_piece(i, 1.0, 1, {"board": 7, "plate": 3, "block": 1, "bracket": 0.8, "pipe": 0.5, "bolt": 0.6}),
            sink=(0.1, 0.5), tilt=(0.1, 0.9))
    return parts


def scrap_heap_medium(name):
    md = Mound(1.45, 0.95, [(0.1, 0.05, 0.98, 1.25, 0.82), (-0.8, -0.1, 0.62, 0.6, 0.5), (0.85, 0.0, 0.66, 0.55, 0.5)],
               noise=0.07, nscale=0.4, power=1.1)
    parts = [mound_mesh(name, md, 8, 26, "Dirt")]
    for k, (x, y, pitch, yaw, L) in enumerate(((-0.25, 0.0, 36, 20, 1.3), (0.35, 0.1, 44, 170, 1.05), (0.9, -0.2, 30, 150, 0.9))):
        b = board("mast%d" % k, L, 0.14, 0.04, RNG.choice(("ScrapWood", "WoodDark")), (True, True), nails=1)
        stick(b, md, x, y, math.radians(pitch), math.radians(yaw), 0.3)
        parts.append(b)
    beam = board("beam", 1.7, 0.16, 0.16, "WoodDark", (False, True))
    put_on(beam, md, -0.3, -0.35, 0.45, math.radians(-8), 0.15)
    parts.append(beam)
    for k, (x, y, s) in enumerate(((0.75, -0.45, 0.5), (-0.95, -0.2, 0.42))):
        cf = crate_frag("crate%d" % k, s, RNG.choice(("ScrapWood", "ScrapWoodDark")))
        put_on(cf, md, x, y, 0.3, RNG.uniform(0, TAU), 0.25)
        parts.append(cf)
    wh = wheel("wheel", 0.38, "ScrapWood", 6, 2)
    put_on(wh, md, 0.25, 0.25, 0.4, 0.2, 0.2, up=Vector((0.2, -0.6, 0.8)))
    parts.append(wh)
    for k, (t, r, m) in enumerate(((12, 0.2, "Rust"), (9, 0.12, "RustDark"))):
        g = gear("gear%d" % k, t, r, 0.035, m, hole=0.25)
        put_on(g, md, *md.sample(0.6, 0.8), sink=0.45, tilt=0.5, up=Vector((RNG.uniform(-0.3, 0.3), -0.7, 0.6)))
        parts.append(g)
    hp = hoop("hoop", 0.28, 0.04, "Rust")
    put_on(hp, md, -0.55, -0.45, 0.4, 0.1, 0.3, up=Vector((0.2, -0.8, 0.5)))
    parts.append(hp)
    scatter(parts, md, 80, lambda i: junk_piece(i, 1.3, 1), sink=(0.1, 0.5), tilt=(0.1, 0.9))
    return parts


def scrap_heap_massive(name):
    md = Mound(4.95, 1.95, [(0.9, 0.2, 3.9, 3.9, 1.75), (-2.7, 0.0, 2.55, 2.3, 1.55), (3.5, -0.2, 1.5, 1.5, 1.2),
                            (-4.1, 0.1, 0.95, 1.0, 1.0)], noise=0.16, nscale=0.9, power=1.15)
    parts = [mound_mesh(name, md, 13, 46, "Dirt")]
    # шесты и балки, торчащие из горы (силуэт), на одном — рваный флаг с короной
    for k, (x, y, pitch, yaw, L) in enumerate(((0.7, 0.3, 82, 10, 1.9), (-2.9, 0.2, 70, 170, 2.0), (2.2, -0.4, 38, 170, 2.6),
                                               (-1.1, -0.6, 32, 10, 2.8), (3.8, -0.4, 45, 190, 1.8), (-3.9, -0.3, 40, -20, 1.6))):
        b = board("pole%d" % k, L, 0.2, 0.2, RNG.choice(("WoodDark", "ScrapWoodDark")), (True, True))
        stick(b, md, x, y, math.radians(pitch), math.radians(yaw), 0.3 if k else 0.22)
        parts.append(b)
        if k == 0:
            top = Vector((x, y, md.h(x, y))) + (Matrix.Rotation(math.radians(yaw), 4, 'Z') @ Matrix.Rotation(-math.radians(pitch), 4, 'Y')) @ Vector((L * 0.7, 0, 0))
            bar = board("bar", 0.9, 0.08, 0.08, "WoodDark", (False, False))
            xf(bar, top + Vector((0.05, -0.12, -0.12)))
            parts.append(bar)
            fl = flag("flag", 0.75, 1.1, 6, 8, "ClothRed")
            xf(fl, top + Vector((0.05, -0.18, -0.16)))
            parts.append(fl)
    for k in range(3):
        wh = wheel("wheel%d" % k, RNG.uniform(0.4, 0.55), "ScrapWood", 6, RNG.randrange(1, 3), 2)
        x, y = md.sample(0.8, 0.85)
        put_on(wh, md, x, y, 0.45, 0.0, 0.3, up=Vector((RNG.uniform(-0.3, 0.3), -0.6, 0.7)))
        parts.append(wh)
    for k, (t, r, sp) in enumerate(((16, 0.55, 4), (12, 0.35, 0), (10, 0.25, 0), (14, 0.4, 0))):
        g = gear("gear%d" % k, t, r, 0.06, RNG.choice(("Rust", "RustDark")), hole=0.25, spokes=sp)
        x, y = md.sample(0.75, 0.9)
        put_on(g, md, x, y, 0.4, 0.0, 0.4, up=Vector((RNG.uniform(-0.3, 0.3), -0.7, 0.6)))
        parts.append(g)
    for k in range(7):
        cf = crate_frag("crate%d" % k, RNG.uniform(0.6, 0.95), RNG.choice(("ScrapWood", "ScrapWoodDark")))
        x, y = md.sample(0.85, 0.8)
        put_on(cf, md, x, y, 0.3, None, 0.3)
        parts.append(cf)
    for k in range(4):
        hp = hoop("hoop%d" % k, RNG.uniform(0.3, 0.45), 0.05, "Rust")
        x, y = md.sample(0.85, 0.8)
        put_on(hp, md, x, y, 0.4, None, 0.5)
        parts.append(hp)
    for k in range(5):                                            # тема листа: головы и конечности в горе
        o = HEAD_PROTOS[k % len(HEAD_PROTOS)]
        h = dup(o, "head%d" % k)
        xf(h, scale=1.6)
        x, y = md.sample(0.8, 0.9)
        put_on(h, md, x, y, 0.35, RNG.uniform(-0.6, 0.6), 0.3, up=Vector((0, -0.5, 1)))
        parts.append(h)
    scatter(parts, md, 26, lambda i: limb("limb%d" % i, RNG.uniform(0.5, 0.7), RNG.uniform(0.06, 0.08),
                                          RNG.choice(DOLL_WOODS), 2), rmax=0.85, sink=(0.2, 0.5))
    scatter(parts, md, 150, lambda i: junk_piece(i, 2.7, 1, {"board": 6, "plate": 4, "block": 1.2, "bracket": 0.7, "pipe": 0.7}),
            rmax=0.95, front=0.7, sink=(0.1, 0.5), tilt=(0.1, 0.9))
    return parts


HEAD_PROTOS = []


def head_protos():
    """Прототипы голов для куч (lod 1, вырезанные лица): 3 лица × 3 породы; копии в кучах перекрашиваются."""
    if HEAD_PROTOS:
        return HEAD_PROTOS
    k = 0
    for kind in ("Sad", "Scared", "Cracked"):
        for mat in DOLL_WOODS:
            seed(900 + k)
            h = doll_head("proto_%s_%s" % (kind, mat), kind, mat, 1, paint_n=0)
            h.hide_render = True
            HEAD_PROTOS.append(h)
            k += 1
    return HEAD_PROTOS


def head_copy(name, i, lod=1, painted=None, scale=1.0):
    protos = HEAD_PROTOS if lod == 1 else HEAD_PROTOS_2
    h = dup(protos[i % len(protos)], name)
    h.hide_render = False
    if scale != 1.0:
        xf(h, scale=scale)
    uv_jitter(h)
    if painted is None:
        painted = RNG.random() < 0.55
    if painted == "full":
        for i2 in range(len(h.data.materials)):
            if h.data.materials[i2].name in DOLL_WOODS:
                h.data.materials[i2] = M("PaintRed")
    elif painted:
        paint(h, M("PaintRed"), n=RNG.randrange(1, 3), radius=0.06)
    return h


HEAD_PROTOS_2 = []


def head_protos2():
    if HEAD_PROTOS_2:
        return HEAD_PROTOS_2
    k = 0
    for kind in ("Sad", "Scared", "Cracked"):
        for mat in DOLL_WOODS:
            seed(950 + k)
            h = doll_head("proto2_%s_%s" % (kind, mat), kind, mat, 2, paint_n=0)
            h.hide_render = True
            HEAD_PROTOS_2.append(h)
            k += 1
    return HEAD_PROTOS_2


def puppet_limb_pile(name):
    md = Mound(0.95, 0.7, [(0.0, 0.05, 0.46, 0.85, 0.62)], noise=0.03, nscale=0.25, power=1.1)
    parts = [mound_mesh(name, md, 5, 16, "Dirt")]
    for k in range(3):
        h = head_copy("head%d" % k, [0, 4, 8][k], 1 if k < 2 else 2)
        x, y = [(-0.55, -0.35), (0.62, -0.25), (0.05, 0.1)][k]
        put_on(h, md, x, y, 0.3, RNG.uniform(-0.5, 0.5), 0.3, up=Vector((0, -0.6, 1)))
        parts.append(h)

    def mk(i):
        L = RNG.uniform(0.32, 0.46)
        r = RNG.uniform(0.042, 0.056)
        o = limb("limb%d" % i, L, r, RNG.choice(DOLL_WOODS + ("DollWood",)), 1 if i < 18 else 2, ferrule=False,
                 paint_n=1 if RNG.random() < 0.35 else 0)
        if RNG.random() < 0.15:
            for i2 in range(len(o.data.materials)):
                if o.data.materials[i2].name in DOLL_WOODS:
                    o.data.materials[i2] = M("PaintRed")
        xf(o, rot=(0, math.pi / 2, 0))                   # вдоль X, «толщина» — по Z
        return center(o)
    scatter(parts, md, 24, mk, rmax=0.9, front=0.65, sink=(0.05, 0.4), tilt=(0.0, 0.7))
    for k in range(2):
        hd = center(hand("hand%d" % k, RNG.choice(DOLL_WOODS), 1))
        put_on(hd, md, *md.sample(0.85, 0.7), sink=0.2, tilt=0.8)
        parts.append(hd)
    ft = center(foot("foot", "DollWood", 1))
    put_on(ft, md, 0.7, -0.45, 0.1, 0.4, 0.2)
    parts.append(ft)
    LOOSE_SPEC[name] = [("Doll_Limb_Upper", -0.3, 88, (0, 0, 0)), ("Doll_Limb_Lower", 0.25, 95, (0, 0, 0)),
                        ("Doll_Hand", 0.05, 30, (0, 0, 0))]
    return parts


def puppet_head_pile(name):
    md = Mound(0.86, 0.64, [(0.0, 0.08, 0.62, 0.78, 0.58)], noise=0.02, nscale=0.25, power=0.55)    # плоская макушка
    parts = [mound_mesh(name, md, 5, 16, "Dirt")]
    spots = []
    for ring, (rr, n, lod) in enumerate(((0.86, 7, 1), (0.6, 5, 1), (0.3, 4, 2))):
        for k in range(n):
            t = TAU * (k + 0.5 * ring) / n + RNG.uniform(-0.15, 0.15) - math.pi / 2
            x, y = md.a * rr * math.cos(t), md.b * rr * math.sin(t)
            lod_k = lod if y < 0.1 else 2
            spots.append((x, y, lod_k, ring))
    for k, (x, y, lod, ring) in enumerate(spots):
        painted = "full" if k in (3, 11) else None
        h = head_copy("head%d" % k, RNG.randrange(9), lod, painted, RNG.uniform(1.05, 1.3))
        put_on(h, md, x, y, 0.32 if ring < 2 else 0.45, RNG.uniform(-0.4, 0.4), 0.0, up=Vector((RNG.uniform(-0.25, 0.25), -0.25, 1.0)))
        parts.append(h)
    # макушка — «плато» из голов внутреннего кольца: на нём лежат свободные R-головы (LOOSE_SPEC), кукла может приземлиться
    for k in range(3):
        o = limb("limb%d" % k, RNG.uniform(0.3, 0.4), 0.045, RNG.choice(DOLL_WOODS), 2, ferrule=False)
        xf(o, rot=(0, math.pi / 2, 0))
        center(o)
        put_on(o, md, *md.sample(0.95, 0.9, 0.8), sink=0.3, tilt=0.3)
        parts.append(o)
    LOOSE_SPEC[name] = [("Doll_Head_Sad", -0.2, 0, (0, 0, 0)), ("Doll_Head_Scared", 0.3, 15, (0, 0, 0)),
                        ("Doll_Head_Cracked", 0.05, -10, (0, 0, 0))]
    return parts


def _doll_parts(parts, T, lod_limbs=1, mat="DollWood", head_kind="Sad", head_lod=0, head_up=None, head_face=None,
                head_pos=None, rivets=True):
    """Торс в трансформе T (origin торса — низ), голова; возвращает мировые точки суставов плеч и низа торса."""
    t = torso("torso", mat, 0 if rivets else 1, rivets=rivets)
    paint(t, M("PaintRed"), n=2, radius=0.09)
    t.data.transform(T)
    parts.append(t)
    J = {"sh_l": T @ Vector((-0.2, 0, 0.42)), "sh_r": T @ Vector((0.2, 0, 0.42)), "neck": T @ Vector((0, 0, 0.53)),
         "base": T @ Vector((0, 0, 0.0))}
    if head_kind:
        h = doll_head("head", head_kind, mat, head_lod, paint_n=1)
        up = Vector(head_up) if head_up else (T.to_3x3() @ Vector((0, 0, 1)))
        fr = Vector(head_face) if head_face else (T.to_3x3() @ Vector((0, -1, 0)))
        pos = Vector(head_pos) if head_pos else J["neck"] + up.normalized() * (HEAD_R * 1.06 + 0.04)
        xf(h, pos, basis(up, fr))
        parts.append(h)
    return J


def broken_puppet(name):
    parts = []
    up = Vector((-1.0, 0.0, 0.12))
    T = Matrix.Translation((0.2, 0.0, 0.125)) @ basis(up, (0.0, -0.55, 1.0))
    J = _doll_parts(parts, T, head_up=(-1.0, 0.1, 0.25), head_face=(0.25, -0.75, 0.75), head_pos=(-0.52, -0.02, HEAD_R + 0.005))
    pv = pelvis("pelvis", "DollWood")
    xf(pv, T @ Vector((0, 0, -0.17)), T.to_3x3() @ Matrix.Identity(3))
    parts.append(pv)
    hip_l, hip_r = T @ Vector((-0.08, 0.02, -0.14)), T @ Vector((0.08, 0.02, -0.14))
    # руки: левая раскинута к камере, правая назад
    e = reach(J["sh_l"], 0.30, (-0.25, -1.0), 0.05)
    seg_to(parts, "uarm_l", J["sh_l"], e, 0.045, "DollWood")
    w = reach(e, 0.28, (0.35, -1.0), 0.04)
    seg_to(parts, "larm_l", e, w, 0.04, "DollWood")
    hd = hand("hand_l", "DollWood", 1)
    xf(hd, w, align_z(-(w - e)))
    parts.append(hd)
    e = reach(J["sh_r"], 0.30, (-0.4, 1.0), 0.05)
    seg_to(parts, "uarm_r", J["sh_r"], e, 0.045, "DollWood")
    w = reach(e, 0.28, (-0.9, 0.4), 0.04)
    seg_to(parts, "larm_r", e, w, 0.04, "DollDark", paint_n=1)
    # ноги: левая согнута коленом вверх, правая вытянута
    k = reach(hip_l, 0.42, (0.8, -0.35), 0.36)
    seg_to(parts, "uleg_l", hip_l, k, 0.06, "DollWood")
    a = reach(k, 0.40, (1.0, -0.2), 0.06)
    seg_to(parts, "lleg_l", k, a, 0.052, "DollWood")
    ft = foot("foot_l", "DollWood", 1)
    xf(ft, (0, -0.02, -0.095))
    xf(ft, a, (math.radians(-80), 0, math.radians(-100)))
    rest(ft)
    parts.append(ft)
    k = reach(hip_r, 0.42, (1.0, 0.25), 0.06)
    seg_to(parts, "uleg_r", hip_r, k, 0.06, "DollWood", paint_n=1)
    a = reach(k, 0.40, (1.0, 0.05), 0.055)
    seg_to(parts, "lleg_r", k, a, 0.052, "DollWood")
    # рваная красная тряпка поперёк груди и обломки вокруг
    under = [o for o in parts]
    cloth = drape("cloth", under, 0.0, -0.02, 0.5, 0.42, 8, 6, "ClothRed", yaw=math.radians(-25), lift=0.01, smooth_it=2,
                  tatter=0.3, holes=1, ripple=0.012)
    parts.append(cloth)
    md = Mound(0.95, 0.5, [(0.0, 0.0, 0.03, 0.9, 0.5)], noise=0.0)
    for i in range(7):
        o = junk_piece(i, 0.6, 1, {"board": 4, "plate": 1.5, "block": 1, "bolt": 1})
        x, y = md.sample(0.95, 0.5, 0.45)
        put_on(o, md, x, y, 0.1, None, 0.1, up=Vector((0, 0, 1)))
        parts.append(o)
    return parts


def crushed_puppet(name):
    parts = []
    md = Mound(0.72, 0.38, [(0.05, 0.0, 0.16, 0.7, 0.36)], noise=0.03, nscale=0.15)
    parts.append(mound_mesh(name, md, 4, 14, "Dirt"))
    T = Matrix.Translation((0.32, 0.02, 0.12)) @ basis((-1.0, 0.05, 0.05), (0.0, 0.3, -1.0))   # лицом вниз, под плитой
    J = _doll_parts(parts, T, head_kind=None, rivets=False)
    h = doll_head("head", "Cracked", "DollWood", 0, paint_n=1)
    xf(h, scale=(1.0, 1.0, 0.82))
    xf(h, (-0.52, -0.08, HEAD_R * 0.82 + 0.005), basis((-0.35, 0.0, 1.0), (0.3, -1.0, 0.1)))
    parts.append(h)
    e = reach(J["sh_l"], 0.30, (-0.3, -1.0), 0.05)
    seg_to(parts, "uarm_l", J["sh_l"], e, 0.045, "DollWood")
    w = reach(e, 0.28, (-0.8, -0.6), 0.04)
    seg_to(parts, "larm_l", e, w, 0.04, "DollWood")
    hd = hand("hand", "DollWood", 1)
    xf(hd, w, align_z(-(w - e)))
    parts.append(hd)
    e = reach(J["sh_r"], 0.30, (0.1, 1.0), 0.06)
    seg_to(parts, "uarm_r", J["sh_r"], e, 0.045, "DollDark")
    hip = T @ Vector((0.06, 0.0, -0.05))
    k = reach(hip, 0.42, (1.0, -0.35), 0.07)
    seg_to(parts, "uleg_l", hip, k, 0.06, "DollWood", paint_n=1)
    a = reach(k, 0.40, (1.0, -0.6), 0.055)
    seg_to(parts, "lleg_l", k, a, 0.052, "DollWood")
    hip2 = T @ Vector((-0.06, 0.0, -0.05))
    k2 = reach(hip2, 0.42, (1.0, 0.45), 0.07)
    seg_to(parts, "uleg_r", hip2, k2, 0.06, "DollWood")
    # плита пресса: тяжёлый клёпаный брус наискось поверх торса
    slab = box("slab", (0.95, 0.62, 0.22), M("RustDark"), jitter=0.01)
    bevel_apply(slab, 0.015, 1)
    rv = [slab]
    for x in (-0.38, -0.13, 0.13, 0.38):
        rv.append(rivet("srv", (x, -0.31, 0.06), (0, -1, 0), r=0.018, h=0.014, segs=6))
        rv.append(rivet("srv", (x, -0.31, -0.06), (0, -1, 0), r=0.018, h=0.014, segs=6))
    st = box("strap", (0.08, 0.64, 0.232), M("Rust"))
    xf(st, (0.3, 0, 0))
    rv.append(st)
    slab = merge(rv, "slab")
    xf(slab, (0.12, 0.0, 0.36), (0, math.radians(-9), math.radians(6)))
    parts.append(slab)
    for i in range(16):
        o = rubble("rb%d" % i, RNG.uniform(0.05, 0.12), RNG.choice(("RustDark", "ScrapWoodDark", "Dirt", "Rust")))
        x, y = md.sample(0.95, 0.6, 0.3)
        put_on(o, md, x, y, 0.3, None, 0.5)
        parts.append(o)
    for i in range(5):
        o = junk_piece(i, 0.7, 1, {"board": 3, "plate": 1})
        x, y = md.sample(0.95, 0.6, 0.4)
        put_on(o, md, x, y, 0.3, None, 0.4)
        parts.append(o)
    return parts


def half_puppet(name):
    parts = []
    md = Mound(0.62, 0.42, [(0.22, 0.12, 0.26, 0.5, 0.36)], noise=0.03, nscale=0.15)
    parts.append(mound_mesh(name, md, 4, 14, "Dirt"))
    up = Vector((0.55, 0.25, 1.0))
    T = Matrix.Translation((0.02, 0.02, 0.1)) @ basis(up, (-0.35, -1.0, 0.25))
    J = _doll_parts(parts, T, head_kind="Sad", head_face=(-0.35, -1.0, -0.05))
    e = reach(J["sh_l"], 0.30, (-1.0, -0.25), 0.18)
    seg_to(parts, "uarm", J["sh_l"], e, 0.045, "DollWood")
    w = reach(e, 0.28, (-1.0, -0.4), 0.04)
    seg_to(parts, "larm", e, w, 0.04, "DollWood", paint_n=1)
    hd = hand("hand", "DollWood", 1)
    xf(hd, w, align_z(-(w - e)))
    parts.append(hd)
    stub = cyl("stub", 0.055, 0.06, 'Z', M("Char"), segs=8)   # обломанный низ торса
    xf(stub, T @ Vector((0, 0, -0.01)), T.to_3x3().to_4x4())
    parts.append(stub)
    bd = board("lean", 0.7, 0.14, 0.03, "ScrapWoodDark", (True, True))
    xf(bd, rot=(0, math.radians(-55), 0))
    xf(bd, (0.36, 0.22, 0.28))
    parts.append(bd)
    for k, (x, y, L, r, mat) in enumerate(((0.5, -0.25, 0.42, 0.06, "DollWood"), (0.42, -0.02, 0.40, 0.052, "DollDark"),
                                            (-0.05, -0.34, 0.3, 0.045, "DollWood"))):
        o = limb("loose%d" % k, L, r, mat, 1, paint_n=k % 2)
        xf(o, rot=(0, math.pi / 2, 0))
        center(o)
        xf(o, (x, y, r + 0.005), (0, 0, RNG.uniform(-0.8, 0.8)))
        parts.append(o)
    ft = foot("foot", "DollWood", 1)
    xf(ft, (0.12, -0.35, 0.0), (0, 0, math.radians(70)))
    parts.append(ft)
    for i in range(9):
        o = junk_piece(i, 0.6, 1, {"board": 3, "plate": 1, "block": 1, "bolt": 1})
        x, y = md.sample(0.95, 0.4, 0.2)
        put_on(o, md, x, y, 0.35, None, 0.4)
        parts.append(o)
    return parts


def empty_torso(name):
    """Полый торс ×1.4 (0.57 × 0.73 × 0.37): стенка 22 мм, вырванная грудь, пустое гнездо Core с оборванными проводами."""
    segs = 22
    outer = [(0.13, 0.0), (0.15, 0.03), (0.17, 0.12), (0.20, 0.28), (0.205, 0.38), (0.18, 0.46), (0.12, 0.50), (0.07, 0.52)]
    inner = [(0.052, 0.50), (0.105, 0.475), (0.16, 0.44), (0.184, 0.38), (0.179, 0.28), (0.149, 0.12), (0.13, 0.035), (0.11, 0.0)]
    bands = [0] * len(outer) + [1] * (len(inner) - 1) + [0]
    shell = lathe(name, outer + inner, segs, [M("DollWood"), M("JointDark")], 'Z', loop=True, band_mat=bands, sy=TORSO_SY,
                  phase=math.pi / segs)
    cut_pts = [(-0.11, 0.15), (-0.06, 0.12), (0.0, 0.14), (0.05, 0.11), (0.12, 0.16), (0.13, 0.25), (0.11, 0.33),
               (0.13, 0.41), (0.05, 0.43), (-0.02, 0.40), (-0.08, 0.44), (-0.13, 0.36), (-0.11, 0.27), (-0.14, 0.2)]
    def cutter(n):
        return plate(n, cut_pts, 0.3, M("JointDark"), y=-0.15)
    boolean(shell, [cutter("cut")])
    parts = [shell]
    for z in (0.10, 0.40):
        r = _torso_r(z)
        b = tube("band", r - 0.004, r + 0.01, 0.036, 'Z', M("Rust"), segs=segs, sy=TORSO_SY * (r + 0.003) / r)
        xf(b, (0, 0, z))
        boolean(b, [cutter("cutb")])
        parts.append(b)
        for k in range(12):
            ang = TAU * k / 12 + 0.13
            if math.sin(ang) < -0.55:
                continue                                    # не в вырванной груди
            p = Vector(((r + 0.01) * math.cos(ang), (r + 0.01) * math.sin(ang) * TORSO_SY, z))
            parts.append(rivet("rv", p, (math.cos(ang), math.sin(ang) / TORSO_SY, 0), r=0.009, h=0.009, segs=6))
    strap = box("strap", (0.04, 0.012, 0.44), M("Rust"), along='Z')
    xf(strap, (0, 0.2 * TORSO_SY + 0.004, 0.25))
    parts.append(strap)
    for s in (-1, 1):
        sh = sphere("sock", 0.056, M("JointDark"), 10, 6)
        xf(sh, (s * 0.19, 0, 0.43))
        parts.append(sh)
    # скоба шеи: гнутая полоса
    for (loc, size, rot) in (((0.0, 0.03, 0.54), (0.03, 0.012, 0.06), (0, 0, 0)), ((0.03, 0.03, 0.575), (0.08, 0.012, 0.022), (0, math.radians(-20), 0)),
                             ((0.07, 0.03, 0.56), (0.022, 0.012, 0.04), (0, 0, 0))):
        b = box("neck", size, M("Rust"), along='Z')
        xf(b, loc, rot)
        parts.append(b)
    # пустое гнездо Core внутри и оборванные провода
    ring = tube("socket", 0.055, 0.075, 0.03, 'Y', M("Brass"), segs=12)
    xf(ring, (0, 0.03, 0.3))
    parts.append(ring)
    for k in range(3):
        a = TAU * k / 3 + 0.5
        p0 = Vector((0.065 * math.cos(a), 0.03, 0.3 + 0.065 * math.sin(a)))
        pts = [p0, p0 + Vector((0.02 * math.cos(a), -0.04, 0.02 * math.sin(a) - 0.02)), p0 + Vector((0.03 * math.cos(a), -0.08, -0.06))]
        parts.append(wire_path("wire", pts, 0.005, "IronDark", 4))
    o = merge(parts, name)
    xf(o, scale=1.3)
    paint(o, M("PaintRed"), n=3, radius=0.1)
    return [o]


def dead_core_shell(name):
    R, t = 0.25, 0.018
    n = 9
    outer = [(max(0.02, R * math.sin(math.pi * k / n)), -R * math.cos(math.pi * k / n)) for k in range(n + 1)]
    inner = [(max(0.018, (R - t) * math.sin(math.pi * k / n)), (R - t) * math.cos(math.pi * k / n)) for k in range(n + 1)]
    outer[0] = (0.02, -R + 0.001)
    outer[-1] = (0.02, R - 0.001)
    bands = [0] * n + [0] + [1] * n + [0]
    shell = lathe(name, outer + inner, 18, [M("Rust"), M("RustBlack")], 'Z', loop=True, band_mat=bands, phase=0.17)
    hole = [(-0.13, 0.02), (-0.07, -0.03), (-0.02, 0.01), (0.05, -0.04), (0.12, 0.0), (0.16, 0.08), (0.12, 0.13),
            (0.14, 0.2), (0.06, 0.24), (0.0, 0.19), (-0.07, 0.24), (-0.14, 0.17), (-0.11, 0.1), (-0.16, 0.06)]
    def cutter(nm):
        c = plate(nm, hole, 0.3, M("RustDark"), y=-0.2)
        return c
    boolean(shell, [cutter("hole")])
    parts = [shell]
    rings = []
    eq = tube("eq", R - 0.004, R + 0.012, 0.04, 'Z', M("Brass"), segs=22)
    rings.append(eq)
    for k, rot in enumerate(((0, 0, 0), (0, 0, math.radians(60)))):
        m = tube("mer%d" % k, R - 0.004, R + 0.011, 0.035, 'Y', M("Brass"), segs=22)
        xf(m, rot=(0, 0, math.radians(90)) if k == 1 else (0, 0, 0))
        rings.append(m)
    for rg in rings:
        boolean(rg, [cutter("hc")])
        parts.append(rg)
    for k in range(10):
        a = TAU * k / 10 + 0.2
        p = Vector(((R + 0.012) * math.cos(a), (R + 0.012) * math.sin(a), 0.0))
        if p.y < -0.12 and abs(p.x) < 0.14:
            continue
        parts.append(rivet("rv", p, p, r=0.01, h=0.01, segs=6))
    for pt in (shell, rings[0], rings[1], rings[2]):
        cut_below(pt, -R + 0.03)                              # плоское дно (по частям: boolean требует замкнутых мешей)
    core = sphere("core", 0.15, M("CoreDead"), 12, 8)
    parts.append(core)
    cage = tube("cage", 0.15, 0.162, 0.02, 'X', M("RustDark"), segs=14)
    parts.append(cage)
    o = merge(parts, name)
    return [o]


def wooden_limb_bundle(name):
    parts = []
    r0 = 0.072
    pos = [(0.0, 0.0, r0)] + [(2 * r0 * math.cos(TAU * k / 6), 2 * r0 * math.sin(TAU * k / 6), r0) for k in range(6)]
    pos += [(2.7 * r0 * math.cos(a), 2.7 * r0 * math.sin(a), 0.045) for a in (math.radians(30), math.radians(150), math.radians(270))]
    for k, (py, pz, r) in enumerate(pos):
        L1 = RNG.uniform(0.55, 0.66)
        L2 = RNG.uniform(0.5, 0.6)
        sgn = 1 if k % 2 else -1
        x0 = -sgn * (L1 + L2) / 2 + RNG.uniform(-0.06, 0.06)
        mat = RNG.choice(DOLL_WOODS)
        a = Vector((x0, py, pz))
        b = a + Vector((sgn * L1, 0, 0))
        c = b + Vector((sgn * L2, 0, 0))
        seg_to(parts, "u%d" % k, a, b, r, mat, 1, paint_n=1 if RNG.random() < 0.3 else 0)
        if RNG.random() < 0.8:
            seg_to(parts, "l%d" % k, b, c, r * 0.86, mat, 1, ball=True)
    R = 0.245
    for k, x in enumerate((-0.05, 0.0, 0.05)):
        rp = tube("rope%d" % k, R, R + 0.03, 0.03, 'X', M("Rope"), segs=12)
        xf(rp, (x + RNG.uniform(-0.005, 0.005), 0, 0), (RNG.uniform(-0.06, 0.06), 0, 0))
        parts.append(rp)
    kn = sphere("knot", 0.036, M("Rope"), 8, 5, scale=(1.3, 1.0, 1.0))
    xf(kn, (0.0, -R - 0.02, 0.03))
    parts.append(kn)
    for s in (-1, 1):
        p0 = Vector((0.012 * s, -R - 0.03, 0.0))
        pts = [p0, p0 + Vector((0.03 * s, -0.02, -0.07)), p0 + Vector((0.045 * s, -0.01, -0.15)), p0 + Vector((0.05 * s, 0.01, -0.21))]
        parts.append(wire_path("end", pts, 0.012, "Rope", 5))
    o = merge(parts, name)
    return [o]


def metal_parts_heap(name):
    md = Mound(0.95, 0.7, [(0.0, 0.05, 0.55, 0.85, 0.62), (0.45, -0.1, 0.42, 0.4, 0.35)], noise=0.04, nscale=0.22)
    parts = [mound_mesh(name, md, 5, 16, "RustDark")]
    hs = box("housing", (0.34, 0.24, 0.2), M("RustRed"), jitter=0.004)
    put_on(hs, md, 0.05, -0.1, 0.25, math.radians(15), 0.25)
    parts.append(hs)
    g = gear("gear", 12, 0.2, 0.035, "Rust", hole=0.25)
    put_on(g, md, -0.4, -0.2, 0.45, 0.2, 0.4, up=Vector((0.3, -0.7, 0.6)))
    parts.append(g)
    scatter(parts, md, 5, lambda i: center(piston("pst%d" % i, RNG.uniform(0.05, 0.085), RNG.uniform(0.22, 0.34),
                                                   RNG.choice(("IronDark", "RustDark")))), sink=(0.2, 0.5))
    scatter(parts, md, 4, lambda i: pipe_piece("pp%d" % i, RNG.uniform(0.35, 0.6), RNG.uniform(0.04, 0.06), "Rust", 1))
    scatter(parts, md, 7, lambda i: center(bracket("br%d" % i, RNG.uniform(0.18, 0.3), 0.07, 0.014, RNG.choice(("Rust", "RustDark")))))
    scatter(parts, md, 12, lambda i: block("bl%d" % i, tuple(RNG.uniform(0.08, 0.2) for _ in range(3)), RNG.choice(("RustDark", "IronDark", "Rust"))))
    scatter(parts, md, 9, lambda i: rivet_plate("pl%d" % i, RNG.uniform(0.2, 0.36), RNG.uniform(0.14, 0.26), 0.014,
                                                RNG.choice(("Rust", "RustDark", "RustRed")), 1, bend=RNG.uniform(-0.02, 0.03)))
    scatter(parts, md, 7, lambda i: center(bolt("bo%d" % i, 0.15, 0.015, "IronDark", 2)), sink=(0.1, 0.4))
    scatter(parts, md, 5, lambda i: nut("nu%d" % i, 0.028, 0.014, 0.022), sink=(0.1, 0.4))
    return parts


def gear_heap(name):
    md = Mound(0.95, 0.7, [(0.0, 0.08, 0.42, 0.85, 0.6)], noise=0.04, nscale=0.2)
    parts = [mound_mesh(name, md, 5, 16, "RustDark")]
    big = gear("big", 16, 0.46, 0.05, "Rust", spokes=4)
    xf(big, (0.05, 0.22, 0.5), (math.radians(-18), math.radians(8), math.radians(4)))
    parts.append(big)
    spec = [(-0.55, -0.12, 13, 0.27, "Rust", 22), (0.58, -0.08, 12, 0.25, "RustDark", -15), (-0.1, -0.3, 11, 0.2, "Brass", 8),
            (0.32, -0.42, 9, 0.14, "Rust", -5), (-0.62, -0.46, 8, 0.12, "IronDark", 12), (0.72, -0.44, 9, 0.13, "Rust", 0),
            (-0.28, 0.12, 12, 0.22, "RustDark", 30)]
    for k, (x, y, t, r, m, yaw) in enumerate(spec):
        g = gear("g%d" % k, t, r, 0.035 if r < 0.2 else 0.045, m, hole=0.26)
        z = md.h(x, y)
        lean = math.radians(RNG.uniform(10, 30))
        xf(g, (x, y, z + r * 0.72), (-lean, 0, math.radians(yaw)))
        parts.append(g)
    for k in range(2):
        g = gear("flat%d" % k, 10, 0.16, 0.035, "Rust", hole=0.28)
        xf(g, rot=(math.pi / 2, 0, 0))
        x, y = md.sample(0.7, 0.5)
        put_on(g, md, x, y, 0.3, None, 0.3)
        parts.append(g)
    flat = (math.pi / 2, 0, 0)                               # лёжа: ось шестерни вертикальна — не катится
    LOOSE_SPEC[name] = [("Gear_Small", -0.35, 0, flat), ("Gear_Medium", 0.15, 0, flat), ("Gear_Small", 0.5, 0, flat)]
    return parts


def chain_heap(name):
    md = Mound(0.88, 0.66, [(0.0, 0.04, 0.5, 0.82, 0.62)], noise=0.035, nscale=0.1, power=1.1)
    parts = [mound_mesh(name, md, 6, 20, "RustBlack")]
    pitch = 0.21 - 2 * 0.03

    def strand(nm, x0, y0, heading, turn, n, drop=True):
        pts = []
        x, y = x0, y0
        hd = heading
        for i in range(n):
            if (x / md.a) ** 2 + (y / md.b) ** 2 > 1.25 and len(pts) >= 3:
                break                                           # конец нити упал на пол у края кучи
            z = md.h(x, y)
            if z <= 0.0 and drop:
                z = 0.0
            pts.append(Vector((x, y, max(z, 0.0) + 0.04)))
            hd += turn + RNG.uniform(-0.25, 0.25)
            x += pitch * math.cos(hd)
            y += pitch * math.sin(hd) * 0.8
        return chain(nm, len(pts), 0.21, 0.135, 0.03, RNG.choice(("Rust", "Rust", "RustDark")), 8, 3, path=pts)
    # звенья 8 × 3 (48 треугольников): ~52 звена в 7 нитях — спираль по верху, свисающие концы спереди
    parts.append(strand("chA", -0.05, 0.05, math.radians(200), 0.16, 12))
    parts.append(strand("chB", 0.1, 0.0, math.radians(-40), -0.12, 11))
    parts.append(strand("chC", -0.3, -0.25, math.radians(-100), 0.05, 7))
    parts.append(strand("chD", 0.35, 0.25, math.radians(20), -0.2, 7))
    parts.append(strand("chE", 0.45, -0.3, math.radians(-80), 0.0, 6))
    parts.append(strand("chF", -0.55, 0.0, math.radians(-60), 0.1, 5))
    parts.append(strand("chG", 0.0, -0.45, math.radians(170), -0.05, 5))
    parts.append(strand("chH", 0.05, 0.1, math.radians(-100), 0.1, 8))
    parts.append(strand("chI", -0.15, -0.05, math.radians(-120), -0.08, 9))
    hook = wire_path("hook", [Vector((-0.12, -0.2, 0.55)), Vector((-0.2, -0.26, 0.58)), Vector((-0.26, -0.3, 0.52)),
                              Vector((-0.24, -0.33, 0.44)), Vector((-0.18, -0.33, 0.43))], 0.018, "RustDark", 6)
    parts.append(hook)
    return parts


def nail_bucket(name):
    H, rb, rt = 0.46, 0.2, 0.245
    segs = 24

    def rf(i, k, r):
        return r - (0.004 if i % 3 == 0 else 0.0)            # пазы между клёпками
    wall = lathe(name, [(rb, 0.0), (rt, H), (rt - 0.018, H), (rb - 0.018, 0.02)], segs, [M("ScrapWood")], 'Z', loop=True, rfun=rf)
    parts = [wall]
    fl = cyl("floor", rb - 0.012, 0.03, 'Z', M("ScrapWoodDark"), segs=segs)
    xf(fl, (0, 0, 0.03))
    parts.append(fl)
    for z in (0.07, 0.38):
        r = rb + (rt - rb) * z / H
        hp = tube("hoop", r - 0.004, r + 0.008, 0.035, 'Z', M("Rust"), segs=segs)
        xf(hp, (0, 0, z))
        parts.append(hp)
    for s in (-1, 1):
        ear = box("ear", (0.02, 0.05, 0.06), M("Rust"))
        xf(ear, (s * (rt - 0.002), 0, H - 0.07))
        parts.append(ear)
    bail = [Vector((-(rt + 0.012) * math.cos(a), 0.0, H - 0.07 + (rt + 0.012) * math.sin(a))) for a in [math.pi * k / 10 for k in range(11)]]
    bail = [Matrix.Rotation(math.radians(-50), 3, 'X') @ (p - Vector((0, 0, H - 0.07))) + Vector((0, 0, H - 0.07)) for p in bail]
    parts.append(wire_path("bail", bail, 0.007, "IronDark", 5))
    fill = Mound(rt - 0.02, rt - 0.02, [(0, 0, 0.05, rt, rt)], noise=0.01, nscale=0.05, base=0.0)
    fm = mound_mesh("fill", fill, 2, 14, "RustDark")
    xf(fm, (0, 0, H - 0.05))
    parts.append(fm)
    for i in range(30):
        a, r = RNG.uniform(0, TAU), math.sqrt(RNG.random()) * (rt - 0.04)
        nl = nail("n%d" % i, RNG.uniform(0.09, 0.13), "Rust", 1, bent=RNG.uniform(0, 0.6))
        xf(nl, rot=(math.pi, 0, 0))
        xf(nl, (r * math.cos(a), r * math.sin(a), H + RNG.uniform(0.0, 0.07)), (RNG.uniform(-0.7, 0.7), RNG.uniform(-0.7, 0.7), RNG.uniform(0, TAU)))
        parts.append(nl)
    o = merge(parts, name)
    return [o]


def bolt_nut_box(name):
    Wx, Dy, H, t = 0.8, 0.5, 0.36, 0.024
    parts = []
    for k in range(3):
        z = 0.02 + H / 3 * (k + 0.5)
        for s in (-1, 1):
            b = board("fb", Wx - 0.01, H / 3 - 0.008, t, "ScrapWood", (False, False))
            xf(b, rot=(math.pi / 2, 0, 0))
            xf(b, (0, s * (Dy / 2 - t / 2), z))
            parts.append(b)
            b = board("sb", Dy - 2 * t, H / 3 - 0.008, t, "ScrapWood", (False, False))
            xf(b, rot=(math.pi / 2, 0, math.pi / 2))
            xf(b, (s * (Wx / 2 - t / 2), 0, z))
            parts.append(b)
    bt = board("bottom", Wx, Dy, 0.02, "ScrapWoodDark", (False, False))
    xf(bt, (0, 0, 0.01))
    parts.append(bt)
    for sx in (-1, 1):
        for sy in (-1, 1):
            for z in (0.06, H - 0.02):
                a = box("ca", (0.12, 0.006, 0.05), M("Rust"))
                xf(a, (sx * (Wx / 2 - 0.06), sy * (Dy / 2 + 0.003), z))
                b = box("cb", (0.006, 0.12, 0.05), M("Rust"))
                xf(b, (sx * (Wx / 2 + 0.003), sy * (Dy / 2 - 0.06), z))
                parts += [a, b]
                if sy < 0:
                    parts.append(rivet("rv", (sx * (Wx / 2 - 0.05), -Dy / 2 - 0.006, z), (0, -1, 0), r=0.008, h=0.008, segs=5))
    fill = Mound(Wx / 2 - 0.03, Dy / 2 - 0.03, [(0, 0, 0.06, Wx / 2, Dy / 2)], noise=0.01, nscale=0.06, power=0.6, base=0.0)
    fm = mound_mesh("fill", fill, 2, 14, "IronDark")
    xf(fm, (0, 0, H - 0.05))
    parts.append(fm)
    for i in range(30):
        if i % 2:
            o = bolt("b%d" % i, RNG.uniform(0.12, 0.17), 0.016, RNG.choice(("IronDark", "Iron", "RustDark")), 1)
            center(o)
        else:
            o = nut("n%d" % i, 0.032, 0.016, 0.026, RNG.choice(("IronDark", "Iron", "RustDark")))
        x, y = RNG.uniform(-Wx / 2 + 0.08, Wx / 2 - 0.08), RNG.uniform(-Dy / 2 + 0.07, Dy / 2 - 0.07)
        xf(o, (x, y, H + 0.01 + RNG.uniform(-0.01, 0.04)), rand_rot())
        parts.append(o)
    o = merge(parts, name)
    return [o]


def broken_weapons_pile(name):
    md = Mound(0.95, 0.55, [(0.0, 0.05, 0.32, 0.85, 0.5)], noise=0.03, nscale=0.2)
    parts = [mound_mesh(name, md, 5, 16, "Dirt")]
    for (nm, fn, x, y, pitch, yaw, bury) in (("swE", lambda n: sword(n, 0.5, True, "RustDark", "Rope", 1), 0.6, 0.15, 58, 200, 0.2),
                                             ("hmC", lambda n: hammer(n, 1, 0.75, "RustDark", "WoodDark"), -0.62, 0.1, 40, -20, 0.2),
                                             ("axD", lambda n: axe(n, 1, 0.62, False, "Rust"), -0.05, 0.1, 62, 95, 0.2)):
        o = fn(nm)
        stick(o, md, x, y, math.radians(pitch), math.radians(yaw), bury)
        parts.append(o)
    s1 = sword("swA", 0.55, True, "Rust", "ClothWrap", 1)
    stick(s1, md, 0.22, 0.02, math.radians(52), math.radians(170), 0.18)
    parts.append(s1)
    s2 = sword("swB", 0.62, False, "Iron", "ClothRed", 1)
    stick(s2, md, -0.35, 0.05, math.radians(55), math.radians(15), 0.2)
    parts.append(s2)
    h1 = hammer("hmA", 1, 0.8, "Rust", "ScrapWoodDark")
    stick(h1, md, 0.5, 0.1, math.radians(35), math.radians(200), 0.2)
    parts.append(h1)
    for (nm, fn, x, y, yaw) in (("swC", lambda n: sword(n, 0.3, True, "Rust", "Rope", 1), -0.55, -0.32, 20),
                                ("swD", lambda n: sword(n, 0.45, True, "RustDark", "ClothWrap", 1), 0.3, -0.35, 160),
                                ("hmB", lambda n: hammer(n, 1, 0.7, "RustDark", "WoodDark"), -0.1, -0.12, -25),
                                ("mace", lambda n: mace(n, 1, 0.55), 0.55, -0.3, 200),
                                ("axA", lambda n: axe(n, 1, 0.66, False, "Rust"), -0.6, -0.1, -60),
                                ("axB", lambda n: axe(n, 1, 0.6, True, "RustDark"), 0.7, 0.0, 120),
                                ("axC", lambda n: axe(n, 1, 0.5, False, "Rust"), 0.05, 0.25, 70)):
        o = center(fn(nm))
        put_on(o, md, x, y, 0.3, math.radians(yaw), 0.15)
        parts.append(o)
    sp = cyl("spear", 0.02, 1.1, 'X', M("ScrapWoodDark"), segs=6)
    put_on(sp, md, -0.1, 0.2, 0.3, math.radians(-15), 0.1)
    parts.append(sp)
    scatter(parts, md, 20, lambda i: junk_piece(i, 0.9, 1, {"board": 3, "plate": 2, "bolt": 1, "bracket": 0.5}), sink=(0.3, 0.6))
    for k in range(3):
        o = sword("swX%d" % k, RNG.uniform(0.25, 0.45), True, RNG.choice(("Rust", "RustDark")), RNG.choice(("ClothWrap", "Rope", "ClothRed")), 1)
        x, y = md.sample(0.8, 0.8)
        put_on(o, md, x, y, 0.3, None, 0.3)
        parts.append(o)
    return parts


def broken_armor_heap(name):
    md = Mound(0.95, 0.65, [(-0.1, 0.06, 0.46, 0.85, 0.6)], noise=0.04, nscale=0.2)
    parts = [mound_mesh(name, md, 5, 16, "Dirt")]
    sh = shield("shield", 0.6, 0.78, 1)
    xf(sh, (0.42, 0.08, md.h(0.42, 0.08) - 0.12), (math.radians(-14), 0, math.radians(-12)))
    parts.append(sh)
    spots = [(-0.55, -0.3), (-0.2, -0.38), (0.12, -0.42), (-0.7, 0.05), (-0.3, 0.05), (0.05, -0.08), (0.72, -0.35), (-0.05, 0.3), (0.35, -0.25)]
    for k, (x, y) in enumerate(spots):
        hm = helmet("helm%d" % k, RNG.choice(("Rust", "RustDark", "Rust", "IronDark")), 1)
        center(hm)
        flip = RNG.random() < 0.3
        up = Vector((RNG.uniform(-0.4, 0.4), RNG.uniform(-0.6, 0.0), -1.0 if flip else 1.0))
        put_on(hm, md, x, y, 0.3, RNG.uniform(-0.6, 0.6), 0.0, up=(md.normal(x, y) + up * 0.8).normalized())
        parts.append(hm)
    fp = rivet_plate("front", 0.42, 0.5, 0.014, "RustRed", 0, bend=0.02)
    xf(fp, rot=(math.radians(72), 0, math.radians(8)))
    xf(fp, (-0.45, -0.52, 0.22))
    parts.append(fp)
    for k in range(5):
        cp = curved_plate("cp%d" % k, RNG.uniform(0.25, 0.4), RNG.uniform(0.18, 0.3), RNG.uniform(0.18, 0.3), 0.012,
                          RNG.choice(("Rust", "RustDark", "RustRed")))
        x, y = md.sample(0.8, 0.7)
        put_on(cp, md, x, y, 0.2, None, 0.4)
        parts.append(cp)
    scatter(parts, md, 10, lambda i: junk_piece(i, 1.0, 1, {"plate": 4, "board": 1, "bracket": 1}), sink=(0.3, 0.6))
    s = sword("hilt", 0.2, True, "Rust", "ClothWrap", 1)
    center(s)
    put_on(s, md, 0.2, -0.5, 0.2, 0.3, 0.1)
    parts.append(s)
    return parts


def cloth_scrap_heap(name):
    md = Mound(0.95, 0.65, [(-0.1, 0.05, 0.55, 0.8, 0.6), (0.48, 0.0, 0.46, 0.42, 0.42)], noise=0.04, nscale=0.25)
    parts = [mound_mesh(name, md, 5, 16, "Dirt")]
    under = list(parts)
    scatter(under, md, 12, lambda i: junk_piece(i, 1.0, 1, {"board": 4, "plate": 2, "block": 1}), sink=(0.3, 0.6))
    cf = crate_frag("crate", 0.4, "ScrapWood")
    put_on(cf, md, 0.15, -0.1, 0.3, 0.3, 0.2)
    under.append(cf)
    for k in range(2):
        o = limb("limb%d" % k, 0.4, 0.05, "DollWood", 1)
        xf(o, rot=(0, math.pi / 2, 0))
        center(o)
        put_on(o, md, *md.sample(0.8, 0.9, 0.5), sink=0.3, tilt=0.3)
        under.append(o)
    bvh = bvh_of(under)
    red = drape("red", None, -0.42, -0.12, 1.15, 1.0, 14, 12, "ClothRed", yaw=math.radians(8), lift=0.012, smooth_it=4, tatter=0.25,
                holes=2, crown=(0.3, 0.72, 0.42, 0.85), crown_mat="Crown", bvh=bvh)
    blue = drape("blue", None, 0.45, -0.1, 0.95, 0.95, 12, 12, "ClothBlue", yaw=math.radians(-12), lift=0.016, smooth_it=4,
                 tatter=0.3, holes=3, bvh=bvh)
    rag = drape("rag", None, 0.05, 0.3, 0.7, 0.5, 8, 6, "ClothWrap", yaw=math.radians(25), lift=0.02, smooth_it=3, tatter=0.3, bvh=bvh)
    parts = under + [red, blue, rag]
    scatter(parts, md, 10, lambda i: junk_piece(100 + i, 0.9, 1, {"board": 4, "plate": 2, "block": 1}), rmin=0.72, rmax=0.98,
            front=0.7, sink=(0.2, 0.5))
    for k, (x, y, m) in enumerate(((-0.55, -0.62, "ClothRed"), (0.3, -0.6, "ClothRed"), (0.75, -0.45, "ClothBlue"))):
        sc = drape("scrap%d" % k, None, x, y, 0.28, 0.2, 3, 2, m, yaw=RNG.uniform(0, TAU), lift=0.006, smooth_it=0, tatter=0.2, bvh=bvh)
        parts.append(sc)
    return parts


def mystery_scrap_heap(name):
    md = Mound(1.08, 0.78, [(-0.66, 0.05, 1.02, 0.56, 0.7), (0.66, 0.05, 0.98, 0.56, 0.7), (0.0, 0.5, 0.9, 0.75, 0.32)],
               noise=0.05, nscale=0.25, power=1.0)
    parts = [mound_mesh(name, md, 7, 22, "Dirt")]
    # пещера: задняя стенка — тёплое свечение, угольки, сундучок
    bm = bmesh.new()
    gv = []
    for kz, z in enumerate((0.0, 0.4, 0.8)):
        gv.append([bm.verts.new((0.38 * math.cos(math.pi * i / 8), 0.2 * math.sin(math.pi * i / 8) + 0.12, z)) for i in range(9)])
    for a_, b_ in zip(gv, gv[1:]):
        for i in range(8):
            f = bm.faces.new((a_[i], a_[i + 1], b_[i + 1], b_[i]))
            f.normal_update()
            if f.normal.y > 0:
                f.normal_flip()
    glow = mesh_obj("glow", bm, [M("Glow")])
    C.uv_box(glow, 1.0)
    parts.append(glow)
    for i in range(9):
        e = box("ember%d" % i, (RNG.uniform(0.03, 0.06), RNG.uniform(0.03, 0.06), 0.02), M("Ember"), jitter=0.006)
        xf(e, (RNG.uniform(-0.3, 0.3), RNG.uniform(-0.05, 0.25), 0.01), (0, 0, RNG.uniform(0, TAU)))
        parts.append(e)
    # сундучок 0.44 × 0.3 × 0.3
    cw, cd, ch = 0.44, 0.28, 0.2
    body = box("chest", (cw, cd, ch), M("ScrapWood"), along='X')
    bevel_apply(body, 0.008, 1)
    xf(body, (0, 0, ch / 2))
    lid = lathe("lid", [(0.0, -cw / 2), (cd / 2, -cw / 2), (cd / 2, cw / 2), (0.0, cw / 2)], 10, [M("ScrapWoodDark")], 'X')
    bm = bmesh.new()
    bm.from_mesh(lid.data)
    for v in bm.verts:
        if v.co.z < 0:
            v.co.z = 0.0
        v.co.z *= 0.7
    bm.to_mesh(lid.data)
    bm.free()
    xf(lid, (0, 0, ch))
    ch_parts = [body, lid]
    for x in (-0.14, 0.14):
        b = box("band", (0.035, cd + 0.01, ch + 0.004), M("Brass"))
        xf(b, (x, 0, ch / 2))
        ch_parts.append(b)
        bl = lathe("lband", [(0.0, -0.018), (cd / 2 + 0.006, -0.018), (cd / 2 + 0.006, 0.018), (0.0, 0.018)], 10, [M("Brass")], 'X')
        for v in bl.data.vertices:
            v.co.z = max(0.0, v.co.z) * 0.72
        xf(bl, (x, 0, ch))
        ch_parts.append(bl)
    lock = box("lock", (0.06, 0.012, 0.07), M("Brass"))
    xf(lock, (0, -cd / 2 - 0.006, ch - 0.02))
    ch_parts.append(lock)
    ch_parts.append(crown_quad("crown", (0.16, 0.16), (0, -cd / 2 - 0.004, ch * 0.45), "CrownGold"))
    chest = merge(ch_parts, "chest")
    xf(chest, (0.0, -0.08, 0.0), (0, 0, math.radians(-6)))
    parts.append(chest)
    # свод и косяки: доски над проёмом
    for k in range(7):
        y = -0.42 + k * 0.13
        b = board("roof%d" % k, RNG.uniform(1.1, 1.35), RNG.uniform(0.1, 0.15), 0.035, RNG.choice(("ScrapWood", "ScrapWoodDark", "WoodDark")),
                  (RNG.random() < 0.5, True))
        xf(b, (RNG.uniform(-0.08, 0.08), y, 0.88 + RNG.uniform(-0.04, 0.06) + (0.05 if k % 2 else 0.0)),
           (RNG.uniform(-0.1, 0.1), RNG.uniform(-0.12, 0.12), RNG.uniform(-0.25, 0.25)))
        parts.append(b)
    for s in (-1, 1):
        post = board("post", 0.95, 0.12, 0.05, "WoodDark", (False, True))
        xf(post, rot=(0, math.radians(-90 + s * 12), 0))
        xf(post, (s * 0.4, -0.38, 0.45))
        parts.append(post)
    lintel = board("lintel", 1.0, 0.14, 0.06, "WoodDark", (True, True), nails=2)
    xf(lintel, rot=(math.pi / 2, 0, math.radians(4)))
    xf(lintel, (0.0, -0.44, 0.84))
    parts.append(lintel)
    cave = lambda x, y: abs(x) < 0.42 and y < 0.2
    def mk(i):
        return junk_piece(i, 1.1, 1, {"board": 6, "plate": 3, "block": 1, "bracket": 0.6, "pipe": 0.5})
    for i in range(34):
        o = mk(i)
        for _ in range(20):
            x, y = md.sample(0.95, 0.6)
            if not cave(x, y):
                break
        put_on(o, md, x, y, RNG.uniform(0.2, 0.55), None, RNG.uniform(0, 0.6))
        parts.append(o)
    for k, (x, y, pitch, yaw, L) in enumerate(((-0.75, 0.0, 55, 20, 0.95), (0.7, 0.1, 60, 160, 0.9), (0.3, 0.35, 70, 100, 0.8))):
        b = board("spike%d" % k, L, 0.1, 0.03, "ScrapWoodDark", (True, True))
        stick(b, md, x, y, math.radians(pitch), math.radians(yaw), 0.35)
        parts.append(b)
    g = gear("gear", 11, 0.18, 0.035, "Rust", hole=0.26)
    put_on(g, md, -0.7, -0.35, 0.4, 0.2, 0.3, up=Vector((0.2, -0.8, 0.5)))
    parts.append(g)
    h = head_copy("head", 2, 1, True)
    put_on(h, md, 0.78, -0.3, 0.35, 0.3, 0.2, up=Vector((0.2, -0.6, 1.0)))
    parts.append(h)
    EXTRA[name] = {"light": (0.0, 0.02, 0.38), "loot": (0.0, -0.08, 0.16)}
    return parts


BODIES = [
    ("Scrap_Heap_Small", scrap_heap_small, "S", 1),
    ("Scrap_Heap_Medium", scrap_heap_medium, "S", 2),
    ("Scrap_Heap_Massive", scrap_heap_massive, "S", 3),
    ("Puppet_Limb_Pile", puppet_limb_pile, "SR", 4),
    ("Puppet_Head_Pile", puppet_head_pile, "SR", 5),
    ("Broken_Puppet", broken_puppet, "S", 6),
    ("Crushed_Puppet", crushed_puppet, "S", 7),
    ("Half_Puppet", half_puppet, "S", 8),
    ("Empty_Torso", empty_torso, "R", 9),
    ("Dead_Core_Shell", dead_core_shell, "R", 10),
    ("Wooden_Limb_Bundle", wooden_limb_bundle, "R", 11),
    ("Metal_Parts_Heap", metal_parts_heap, "S", 12),
    ("Gear_Heap", gear_heap, "SR", 13),
    ("Chain_Heap", chain_heap, "S", 14),
    ("Nail_Bucket", nail_bucket, "R", 15),
    ("Bolt_Nut_Box", bolt_nut_box, "R", 16),
    ("Broken_Weapons_Pile", broken_weapons_pile, "S", 17),
    ("Broken_Armor_Heap", broken_armor_heap, "S", 18),
    ("Cloth_Scrap_Heap", cloth_scrap_heap, "S", 19),
    ("Mystery_Scrap_Heap", mystery_scrap_heap, "SL", 20),
]


# ----------------------------------------------------------------------------------------------------------------------
# физика для builder-а Godot: выпуклые оболочки (R) и срезы-призмы по профилю верха (S); Blender (x, y, z) → Godot (x, z, −y)
# ----------------------------------------------------------------------------------------------------------------------
P_BG = Matrix(((1, 0, 0), (0, 0, 1), (0, -1, 0))) if bpy is not None else None


def to_godot(v):
    return [round(v[0], 4), round(v[2], 4), round(-v[1], 4)]


def quat_godot(R):
    """Поворот Blender (Matrix 3×3/4×4) → кватернион Godot [x, y, z, w]."""
    m = P_BG @ R.to_3x3() @ P_BG.transposed()
    q = m.to_quaternion()
    return [round(q.x, 5), round(q.y, 5), round(q.z, 5), round(q.w, 5)]


def hull_points(o, max_pts=24, min_gap=0.015):
    """Вершины выпуклой оболочки меша, прореженные дальней точкой (≤ max_pts и не ближе min_gap друг к другу), в осях
    Godot. Проверено на Jolt 4.7: оболочки из 40–60 точек с почти совпадающими вершинами (острые концы звеньев цепи)
    строятся с дефектом — тело в плоскости XY (оси заблокированы) «качается» и уходит в пол на 20+ см; 24 точки с зазором
    ≥ 1.5 см ведут себя как бокс."""
    import numpy as np
    bm = bmesh.new()
    bm.from_mesh(o.data)
    res = bmesh.ops.convex_hull(bm, input=bm.verts[:], use_existing_faces=False)
    hv = set()
    for g in res["geom"]:
        if isinstance(g, bmesh.types.BMFace):
            hv.update(g.verts)
    pts = np.array([list(v.co) for v in hv], dtype=np.float64)
    bm.free()
    if len(pts) > 4:
        c = pts.mean(axis=0)
        sel = [int(np.argmax(((pts - c) ** 2).sum(1)))]
        d = ((pts - pts[sel[0]]) ** 2).sum(1)
        while len(sel) < max_pts:
            i = int(np.argmax(d))
            if d[i] < min_gap * min_gap:
                break
            sel.append(i)
            d = np.minimum(d, ((pts - pts[i]) ** 2).sum(1))
        pts = pts[sel]
    return [to_godot(p) for p in pts]


def profile(o, step, ys=(-0.15, -0.075, 0.0, 0.075, 0.15), q=0.6):
    """Профиль высоты верха по X в плоскости боя: лучи сверху на y ∈ ys, квантиль q, сглаживание [¼ ½ ¼]."""
    bvh = bvh_of([o])
    mn, mx = bbox(o)
    n = max(4, int(math.ceil((mx.x - mn.x) / step)))
    xs = [mn.x + (mx.x - mn.x) * i / n for i in range(n + 1)]
    hs = []
    for x in xs:
        vals = []
        for y in ys:
            hit = bvh.ray_cast(Vector((x, y, mx.z + 1.0)), Vector((0, 0, -1)))
            vals.append(max(0.0, hit[0].z) if hit[0] is not None else 0.0)
        vals.sort()
        hs.append(vals[int(round(q * (len(vals) - 1)))])
    sm = [hs[0]] + [0.25 * hs[i - 1] + 0.5 * hs[i] + 0.25 * hs[i + 1] for i in range(1, n)] + [hs[-1]]
    return xs, sm


def slices_from(xs, hs, half_depth=COL_HALF_DEPTH):
    out = []
    for i in range(len(xs) - 1):
        a, b, ha, hb = xs[i], xs[i + 1], hs[i], hs[i + 1]
        if max(ha, hb) < 0.03:
            continue
        ha, hb = max(ha, 0.02), max(hb, 0.02)
        pts = []
        for x, h in ((a, ha), (b, hb)):
            for y in (-0.05, h):
                for z in (-half_depth, half_depth):
                    pts.append([round(x, 4), round(y, 4), z])
        out.append(pts)
    return out


def interp(xs, hs, x):
    if x <= xs[0]:
        return hs[0]
    for i in range(len(xs) - 1):
        if xs[i] <= x <= xs[i + 1]:
            t = (x - xs[i]) / max(1e-9, xs[i + 1] - xs[i])
            return hs[i] + (hs[i + 1] - hs[i]) * t
    return hs[-1]


def _load_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return {}


def _save_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(data, f, indent=1, sort_keys=True)
        f.write("\n")


def export(path, objects):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:
        o.select_set(True)
    kw = dict(filepath=path, export_format='GLB', use_selection=True, export_apply=True, export_yup=True,
              export_materials='EXPORT', export_normals=True, export_texcoords=True, export_animations=False,
              export_skins=False, export_cameras=False, export_lights=False, export_image_format=IMG_FORMAT)
    if IMG_FORMAT in ('WEBP', 'JPEG'):
        kw['export_image_quality'] = 88
    bpy.ops.export_scene.gltf(**kw)


def _cleanup(o):
    me = o.data
    bpy.data.objects.remove(o, do_unlink=True)
    if me.users == 0:
        bpy.data.meshes.remove(me)


# q (квантиль профиля) и шаг срезов по ассетам: лежащие куклы тонкие — берём верхний квантиль
PROFILE_Q = {"Broken_Puppet": 0.75, "Crushed_Puppet": 0.7, "Half_Puppet": 0.75, "Broken_Weapons_Pile": 0.6, "Chain_Heap": 0.5}
PROFILE_STEP = {"Scrap_Heap_Massive": 0.45, "Scrap_Heap_Medium": 0.25}


def build_bits(only):
    set_tex_size(TEX_BITS)
    phys = _load_json(os.path.join(OUT_BITS, "physics.json"))
    report = []
    for name, fn, sd in BITS:
        if only and name not in only:
            continue
        seed(sd)
        o = fn(name)
        o.name = name
        center(o)
        smooth(o, 35.0)
        tris = tri_count(o)
        mn, mx = bbox(o)
        hull = hull_points(o, 24)
        zs = [p[2] for p in hull]
        dz = max(zs) - min(zs)
        if dz < MIN_HULL_DEPTH:
            k = MIN_HULL_DEPTH / max(dz, 1e-4)
            hull = [[p[0], p[1], round(p[2] * k, 4)] for p in hull]
        phys[name] = {"hull": hull, "size": [round(mx.x - mn.x, 3), round(mx.z - mn.z, 3), round(mx.y - mn.y, 3)]}
        path = os.path.join(OUT_BITS, name + ".glb")
        export(path, [o])
        report.append((name, tris, os.path.getsize(path), phys[name]["size"]))
        _cleanup(o)
    _save_json(os.path.join(OUT_BITS, "physics.json"), phys)
    return report


def _loose(name, xs, hs, bit_phys, dx0=0.0):
    out = []
    for bit, x, roll, rot in LOOSE_SPEC.get(name, []):
        x -= dx0                                                  # в осях ассета после центрирования габарита
        R = Matrix.Rotation(-math.radians(roll), 4, 'Y') @ rot_m(rot)
        w, h, d = bit_phys.get(bit, {}).get("size", [0.3, 0.3, 0.3])
        corners = [Vector((sx * w / 2, sy * d / 2, sz * h / 2)) for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
        hz = max((R.to_3x3() @ c).z for c in corners)
        z = max(interp(xs, hs, x + dx) for dx in (-w / 2, 0.0, w / 2)) + hz + 0.015
        out.append({"bit": bit, "pos": to_godot((x, 0.0, z)), "quat": quat_godot(R)})
    return out


def build_bodies(only):
    set_tex_size(TEX_BODIES)
    head_protos()
    head_protos2()
    phys = _load_json(os.path.join(OUT_BODIES, "physics.json"))
    bit_phys = _load_json(os.path.join(OUT_BITS, "physics.json"))
    report = []
    for name, fn, kind, sd in BODIES:
        if only and name not in only:
            continue
        LOOSE_SPEC.pop(name, None)
        EXTRA.pop(name, None)
        seed(sd)
        parts = fn(name)
        o = merge(parts, name)
        mn, mx = bbox(o)
        c = (mn + mx) * 0.5
        dz = -mn.z if kind == "R" else 0.0
        xf(o, (-c.x, -c.y, dz))
        smooth(o, 35.0)
        tris = tri_count(o)
        mn, mx = bbox(o)
        entry = {"kind": kind, "size": [round(mx.x - mn.x, 3), round(mx.z - mn.z, 3), round(mx.y - mn.y, 3)], "tris": tris}
        if kind == "R":
            entry["hull"] = hull_points(o, 32)
        else:
            xs, hs = profile(o, PROFILE_STEP.get(name, 0.15), q=PROFILE_Q.get(name, 0.6))
            entry["slices"] = slices_from(xs, hs)
            entry["profile"] = [[round(x, 3), round(h, 3)] for x, h in zip(xs, hs)]
            loose = _loose(name, xs, hs, bit_phys, c.x)
            if loose:
                entry["loose"] = loose
            if name in EXTRA:
                for k, v in EXTRA[name].items():
                    entry[k] = to_godot(Vector(v) - Vector((c.x, c.y, 0.0)))
        phys[name] = entry
        path = os.path.join(OUT_BODIES, name + ".glb")
        export(path, [o])
        budget = TRI_BUDGET.get(name, TRI_BODY)
        report.append((name, tris, os.path.getsize(path), entry["size"], budget, kind))
        _cleanup(o)
    _save_json(os.path.join(OUT_BODIES, "physics.json"), phys)
    return report


# ----------------------------------------------------------------------------------------------------------------------
# контактный рендер: ячейки (Blender, читает экспортированные glb) → --compose (системный python3 + Pillow)
# ----------------------------------------------------------------------------------------------------------------------
def _import_glb(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    return [o for o in bpy.data.objects if o not in before]


def _scene_bbox(objs):
    mn = Vector((1e9, 1e9, 1e9))
    mx = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        if o.type != 'MESH':
            continue
        for cr in o.bound_box:
            w = o.matrix_world @ Vector(cr)
            mn = Vector((min(mn[i], w[i]) for i in range(3)))
            mx = Vector((max(mx[i], w[i]) for i in range(3)))
    return mn, mx


def _render_setup(res):
    scn = bpy.context.scene
    ok = False
    for eng in ('BLENDER_EEVEE_NEXT', 'BLENDER_EEVEE'):
        try:
            scn.render.engine = eng
            ok = True
            break
        except Exception:
            pass
    if not ok:
        scn.render.engine = 'CYCLES'
    try:
        scn.eevee.taa_render_samples = 48
        scn.eevee.use_shadows = True
    except Exception:
        pass
    scn.render.resolution_x, scn.render.resolution_y = res
    scn.render.film_transparent = False
    scn.view_settings.view_transform = 'AgX' if 'AgX' in [v.identifier for v in type(scn.view_settings).bl_rna.properties['view_transform'].enum_items] else 'Filmic'
    scn.view_settings.look = 'None'
    scn.render.image_settings.file_format = 'PNG'
    world = bpy.data.worlds.new('W')
    scn.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes['Background']
    bg.inputs['Color'].default_value = (0.035, 0.028, 0.03, 1.0)
    bg.inputs['Strength'].default_value = 0.6
    # тёплый закатный ключ слева-спереди, холодный лиловый заполняющий справа, контровой сзади (как на листе)
    for nm, col, energy, rot in (("Key", (1.0, 0.62, 0.36), 4.2, (math.radians(52), 0, math.radians(-38))),
                                 ("Fill", (0.55, 0.52, 0.8), 1.1, (math.radians(60), 0, math.radians(55))),
                                 ("Rim", (1.0, 0.7, 0.45), 2.6, (math.radians(-60), 0, math.radians(20)))):
        ld = bpy.data.lights.new(nm, 'SUN')
        ld.color = col
        ld.energy = energy
        ld.angle = math.radians(6)
        lo = bpy.data.objects.new(nm, ld)
        lo.rotation_euler = rot
        scn.collection.objects.link(lo)
    fl = bpy.data.materials.new("Floor")
    fl.use_nodes = True
    b = fl.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0.012, 0.010, 0.009, 1.0)
    b.inputs["Roughness"].default_value = 0.95
    bpy.ops.mesh.primitive_plane_add(size=200.0, location=(0, 0, -0.001))
    bpy.context.active_object.data.materials.append(fl)
    return scn


def _frame(scn, objs, res, elev=17.0, azim=-14.0, lens=40.0, margin=1.08):
    bpy.context.view_layer.update()
    mn, mx = _scene_bbox(objs)
    ctr = (mn + mx) * 0.5
    cam_d = bpy.data.cameras.new("Cam")
    cam_d.lens = lens
    cam_d.sensor_fit = 'HORIZONTAL'
    cam = bpy.data.objects.new("Cam", cam_d)
    scn.collection.objects.link(cam)
    scn.camera = cam
    e, a = math.radians(elev), math.radians(azim)
    fwd = Vector((math.sin(a) * math.cos(e), math.cos(a) * math.cos(e), -math.sin(e)))   # взгляд: спереди (из −Y) и сверху
    rot = fwd.to_track_quat('-Z', 'Y')
    cam.rotation_euler = rot.to_euler()
    corners = [Vector((x, y, z)) for x in (mn.x, mx.x) for y in (mn.y, mx.y) for z in (mn.z, mx.z)]
    tan_h = (cam_d.sensor_width / 2) / lens
    tan_v = tan_h * res[1] / res[0]
    Rinv = rot.to_matrix().inverted()
    lo, hi = 0.1, 400.0
    for _ in range(60):
        d = (lo + hi) / 2
        pos = ctr - fwd * d
        ok = True
        for c in corners:
            p = Rinv @ (c - pos)
            if -p.z <= 0.05 or abs(p.x) / -p.z > tan_h / margin or abs(p.y) / -p.z > tan_v / margin:
                ok = False
                break
        if ok:
            hi = d
        else:
            lo = d
    cam.location = ctr - fwd * hi
    cam_d.clip_start = max(0.002, hi * 0.02)
    cam_d.clip_end = 1000.0
    return cam


def render_cells(names=None):
    os.makedirs(RENDER_DIR, exist_ok=True)
    bphys = _load_json(os.path.join(OUT_BODIES, "physics.json"))
    tphys = _load_json(os.path.join(OUT_BITS, "physics.json"))
    info = {"bodies": [], "bits": []}
    res = (720, 470)
    for i, (name, _fn, kind, _sd) in enumerate(BODIES):
        if names and name not in names:
            continue
        C.reset_scene()
        scn = _render_setup(res)
        objs = _import_glb(os.path.join(OUT_BODIES, name + ".glb"))
        for L in bphys.get(name, {}).get("loose", []):
            lo = _import_glb(os.path.join(OUT_BITS, L["bit"] + ".glb"))
            gx, gy, gz = L["pos"]
            qx, qy, qz, qw = L["quat"]
            Rg = Quaternion((qw, qx, qy, qz)).to_matrix()
            Rb = P_BG.transposed() @ Rg @ P_BG
            for o in lo:
                if o.parent is None:
                    o.matrix_world = Matrix.Translation((gx, -gz, gy)) @ Rb.to_4x4() @ o.matrix_world
            objs += lo
        bpy.context.view_layer.update()
        mn, mx = _scene_bbox(objs)
        doll = _import_glb(MANNEQUIN)
        sil = bpy.data.materials.new("Silhouette")                  # кукла 1.8 м — тёмный силуэт для масштаба
        sil.use_nodes = True
        sb = sil.node_tree.nodes["Principled BSDF"]
        sb.inputs["Base Color"].default_value = (0.05, 0.055, 0.07, 1.0)
        sb.inputs["Roughness"].default_value = 0.6
        for o in doll:
            if o.type == 'MESH':
                for k in range(len(o.data.materials)):
                    o.data.materials[k] = sil
            if o.parent is None:
                o.matrix_world = Matrix.Translation((mx.x + 0.3, 0.1, 0.0)) @ Matrix.Diagonal((1.8 / 1.96,) * 3 + (1.0,)) @ o.matrix_world
        light = bphys.get(name, {}).get("light")
        if light:
            ld = bpy.data.lights.new("Glow", 'POINT')
            ld.color = (1.0, 0.62, 0.3)
            ld.energy = 60.0
            ld.shadow_soft_size = 0.2
            lo = bpy.data.objects.new("Glow", ld)
            lo.location = (light[0], -light[2], light[1])
            scn.collection.objects.link(lo)
        _frame(scn, objs + doll, res, margin=1.03)
        scn.render.filepath = os.path.join(RENDER_DIR, "body_%02d.png" % (i + 1))
        bpy.ops.render.render(write_still=True)
        info["bodies"].append({"n": i + 1, "name": name, "kind": kind, "tris": bphys.get(name, {}).get("tris"),
                               "size": bphys.get(name, {}).get("size"), "png": scn.render.filepath})
    res = (440, 330)
    for i, (name, _fn, _sd) in enumerate(BITS):
        if names and name not in names:
            continue
        C.reset_scene()
        scn = _render_setup(res)
        objs = _import_glb(os.path.join(OUT_BITS, name + ".glb"))
        mn, mx = _scene_bbox(objs)
        for o in objs:
            if o.parent is None:
                o.location.z += -mn.z
        _frame(scn, objs, res, elev=24.0, azim=-22.0, margin=1.15)
        scn.render.filepath = os.path.join(RENDER_DIR, "bit_%02d.png" % (i + 1))
        bpy.ops.render.render(write_still=True)
        tris = None
        info["bits"].append({"n": i + 1, "name": name, "size": tphys.get(name, {}).get("size"), "png": scn.render.filepath})
    old = _load_json(os.path.join(RENDER_DIR, "cells.json"))
    for key in ("bodies", "bits"):
        have = {c["name"]: c for c in old.get(key, [])}
        for c in info[key]:
            have[c["name"]] = c
        info[key] = sorted(have.values(), key=lambda c: c["n"])
    _save_json(os.path.join(RENDER_DIR, "cells.json"), info)


def compose(version="v1", out_dir=None):
    """Системный python3 + Pillow: сетка 5 × 4 ячеек №001–020 (подписи как на листе) и лист кусков → out_dir
    (по умолчанию docs/plan-demo/img; SCRAP_SHEET_DIR — для черновиков)."""
    out_dir = out_dir or os.environ.get("SCRAP_SHEET_DIR") or DOCS_IMG
    from PIL import Image, ImageDraw, ImageFont
    info = _load_json(os.path.join(RENDER_DIR, "cells.json"))

    def font(sz):
        for p in ("/System/Library/Fonts/Supplemental/Georgia.ttf", "/System/Library/Fonts/Supplemental/Times New Roman.ttf",
                  "/System/Library/Fonts/Helvetica.ttc"):
            if os.path.exists(p):
                return ImageFont.truetype(p, sz)
        return ImageFont.load_default()

    def sheet(cells, cols, cw, chh, title, sub, out, label):
        rows = (len(cells) + cols - 1) // cols
        W, H = cols * cw + (cols + 1) * 6, rows * chh + (rows + 1) * 6 + 90
        img = Image.new("RGB", (W, H), (16, 14, 15))
        d = ImageDraw.Draw(img)
        d.text((20, 14), title, fill=(236, 226, 210), font=font(40))
        d.text((22, 62), sub, fill=(170, 160, 150), font=font(18))
        for k, c in enumerate(cells):
            r, q = divmod(k, cols)
            x, y = 6 + q * (cw + 6), 90 + 6 + r * (chh + 6)
            if os.path.exists(c["png"]):
                im = Image.open(c["png"]).convert("RGB").resize((cw, chh), Image.LANCZOS)
                img.paste(im, (x, y))
            l1, l2, l3 = label(c)
            d.text((x + 10, y + 6), l1, fill=(245, 238, 225), font=font(24))
            d.text((x + 10, y + 34), l2, fill=(235, 228, 215), font=font(19))
            d.text((x + 10, y + chh - 26), l3, fill=(190, 180, 168), font=font(15))
        os.makedirs(os.path.dirname(out), exist_ok=True)
        img.save(out)
        print("saved", out, img.size)

    bodies = info.get("bodies", [])
    sheet(bodies, 5, 480, 314, "THE SCRAP — лист 01 «Scrap & Bodies» (001–020), Blender %s" % version,
          "tools/blender/scrap_bodies.py · справа в каждой ячейке — кукла-манекен 1.8 м для масштаба · S статика, R тело, SR куча + свободные куски, SL куча + лут",
          os.path.join(out_dir, "scrap-sheet01-%s.png" % version),
          lambda c: ("%03d" % c["n"], c["name"].replace("_", " "),
                     "%s · %s tris · %s м" % (c["kind"], c["tris"], " × ".join("%.2f" % v for v in (c["size"] or [])))))
    bits = info.get("bits", [])
    sheet(bits, 5, 400, 300, "THE SCRAP — библиотека кусков (bits), Blender %s" % version,
          "assets/models/scrap/bits/*.glb · ≤ 600 tris · RigidBody3D-сцены scenes/props/scrap/bit_*.tscn · для «дождя из хлама» и деталей тел",
          os.path.join(out_dir, "scrap-bits-%s.png" % version),
          lambda c: ("", c["name"].replace("_", " "), "%s м" % " × ".join("%.2f" % v for v in (c["size"] or []))))


def main():
    if bpy is None:
        if "--compose" in sys.argv:
            i = sys.argv.index("--compose")
            compose(sys.argv[i + 1] if len(sys.argv) > i + 1 else "v1")
            return
        print("нужен Blender (или --compose для сборки листа через Pillow)")
        sys.exit(1)
    argv = C.args_after_dashdash()
    C.reset_scene()
    if argv and argv[0] == "render":
        render_cells(argv[1:] or None)
        return
    names = [a for a in argv if a not in ("bits", "bodies")]
    bit_names = {b[0] for b in BITS}
    body_names = {b[0] for b in BODIES}
    do_bits = ("bits" in argv) or (not argv) or any(n in bit_names for n in names)
    do_bodies = ("bodies" in argv) or (not argv) or any(n in body_names for n in names)
    rb = build_bits([n for n in names if n in bit_names]) if do_bits else []
    rd = build_bodies([n for n in names if n in body_names]) if do_bodies else []
    bad = []
    if rb:
        print("BIT                    TRIS      BYTES   SIZE (Godot Ш×В×Г)")
        for name, tris, size, dims in rb:
            flag_ = "  OVER BUDGET" if tris > TRI_BIT else ""
            print("%-22s %6d %10d   %s%s" % (name, tris, size, " × ".join("%.3f" % v for v in dims), flag_))
            if flag_:
                bad.append(name)
    if rd:
        print("BODY                   TRIS BUDGET      BYTES KIND  SIZE (Godot Ш×В×Г)")
        for name, tris, size, dims, budget, kind in rd:
            flag_ = "  OVER BUDGET" if tris > budget else ""
            print("%-22s %6d %6d %10d %-4s  %s%s" % (name, tris, budget, size, kind, " × ".join("%.3f" % v for v in dims), flag_))
            if flag_:
                bad.append(name)
    print("PBR:", ", ".join(sorted(USED_PBR)) or "—")
    print("FLAT (нет PBR-папки):", ", ".join(sorted(USED_FLAT)) or "—")
    if bad:
        print("ERROR: over budget:", bad)
        sys.exit(1)


main()
