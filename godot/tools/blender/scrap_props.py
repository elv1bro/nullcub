#!/usr/bin/env python3
"""THE SCRAP (биом 1 «Свалка»), лист 02 «Physical Props», ассеты №021–040 (docs/refs/biomes/01-scrap/sheet-02.png,
LIST.md) — настоящие меши Blender 4.5 с PBR-наборами Свалки из assets/textures/pbr (печёт tools/blender/textures.py:
rust_metal, rust_painted_red, scrap_wood, scrap_dirt, brass_worn) и старыми наборами (iron, wood_dark, rope).
Физические пропсы: их пинают, ломают и швыряют; сцены собирает tools/build_scrap_props_scenes.gd.

Запуск (Blender 4.5 LTS, headless):
    /Applications/Blender.app/Contents/MacOS/Blender -b --python godot/tools/blender/scrap_props.py [-- Имя …]
    → godot/assets/models/scrap/props/<Name>.glb
    … -- --render [Имя …]       контактные рендеры ячеек (Cycles) из уже экспортированных glb → $SCRAP_RENDER_TMP
                                 (по умолчанию <tmp>/scrap_props_render), затем лист собирает системный python3:
    python3 godot/tools/blender/scrap_props.py --sheet
                                 → docs/plan-demo/img/scrap-sheet02-v1.png (сетка 021–040 как на листе, силуэт куклы 1.8 м)
Переменные окружения: PROPS_TEX_SIZE (1024) — размер текстур внутри glb, PROPS_IMG (WEBP), SCRAP_PROPS_CACHE (кэш
уменьшенных текстур, по умолчанию <tmp>/ragdoll_scrap_props_pbr), SCRAP_FLAT=1 — все материалы плоские (быстрый прогон).
Если набора PBR ещё нет (albedo + roughness + normal), материал с тем же именем строится плоским (цвет ≈ среднему альбедо
набора) и скрипт печатает это в таблице материалов — перезапуск после выпечки заменит его текстурным.

Соглашения (docs/plan-demo/ASSET_PIPELINE.md, common.py): метры; Blender Z вверх, X вбок, «лицо» в −Y (после экспорта
+Z в Godot, к камере). Origin каждого объекта — ЦЕНТР ОСНОВАНИЯ (x=0, y=0 — центр пятна опоры, z=0 — пол), кроме
обломков Destroyed/Piece_*: их origin — центр их собственного bbox (breakable.gd спавнит тело в этой точке, выпуклая
оболочка строится вокруг неё). Бюджет: ≤ 3000 треугольников на объект и ≤ 4500 на весь glb (скрипт печатает таблицу
и падает при превышении). 1 тайл текстуры = 1 м (доски 0.2–0.25 м попадают в одну доску текстуры scrap_wood).

Файлы (Ш × В × Г — X × Z × Y в Blender; «B/R/S» — физика по LIST.md):
  021 Wooden_Crate.glb          B  1.0³: каркас из брусьев 0.11, вертикальные доски спереди/сзади/с боков, крышка из досок,
                                  железные накладки на 8 углах с заклёпками, тёмная корона-декаль спереди.
                                  Intact | Damaged («open»: сорвана передняя доска крышки, сломаны правая доска фасада и
                                  верхний брус, щепки) | Destroyed/{Piece_0..7} (стойки с брусьями, пары досок фасада,
                                  крышки, задние стенки)
  022 Reinforced_Crate.glb      B  1.0³: тёмные доски (горизонтальные спереди), железные рёбра по всем 12 кромкам и две
                                  вертикальные полосы с болтами, латунная корона-рельеф (brass_worn).
                                  Intact | Damaged (сломана верхняя доска, отогнута правая полоса, нет доски крышки) |
                                  Destroyed/{Piece_0..7}
  023 Broken_Crate_A.glb, Broken_Crate_B.glb   R (лёгкие)  1.0 × 0.6 × 1.0: развалившийся ящик — обломанные стойки,
                                  остатки досок, раскос поперёк фасада; две разные поломки
      Broken_Crate_Debris.glb   S  1.2 × 0.25 × 1.0: плоская куча досок, обломков стоек и щепок (декор-статика)
  024 Large_Shipping_Crate.glb  R  2.4 × 1.4 × 1.4: железная рама из уголка с заклёпками, три секции с красными крашеными
                                  досками (rust_painted_red), X-раскосы в крайних секциях, корона-декаль в средней,
                                  кольцо-ручка на левом торце
  025 Wooden_Barrel.glb         B  ⌀0.7 × 1.0: 16 клёпок (scrap_wood, пузо ⌀0.7, торцы ⌀0.58), 4 железных обруча с
                                  заклёпками, крышка. Intact | Damaged (выбиты 2 клёпки фасада, обломаны верхушки,
                                  верхний обруч съехал) | Destroyed/{Piece_0..5} (4 группы клёпок + 2 обруча)
  026 Metal_Barrel.glb          R  ⌀0.6 × 0.9: стальная бочка (rust_painted_red): закатанные кромки, два гофра, крышка с
                                  пробкой, бледная корона-декаль по цилиндру
      Metal_Barrel_Dented.glb   R  та же бочка с вмятинами и перекошенной верхней кромкой (состояние «dented»)
  027 Broken_Barrel_A.glb       R (лёгкая) лежащий остов бочки, ось вдоль Y (к камере): 11 клёпок, 3 обруча, один
                                  погнут; ⌀0.7 × длина 1.0. Origin — центр пятна опоры (z=0 — низ обода)
      Broken_Barrel_B.glb       R (лёгкая) стоящая нижняя половина бочки: клёпки обломаны на 0.25–0.6, обруч внизу
                                  и второй, сползший и перекошенный; ⌀0.7 × 0.62
      Broken_Barrel_Debris.glb  S  1.3 × 0.12 × 1.0: россыпь клёпок и сплющенный обруч (декор-статика)
  028 Scrap_Basket.glb          R  1.0 × 0.8 × 0.7: рама из уголка, ромбическая сетка из прутка на 4 гранях, дно-лист,
                                  4 поворотных колёсика (часть корпуса)
      Scrap_Basket_Full.glb     R  та же корзина с кучей металлолома (шестерни, трубы, пластины) выше борта
  029 Junk_Cart.glb             R  1.8 × 0.9 × 1.1: дощатый кузов 1.6 × 0.9 со стойками и железными уголками, 4 колеса
                                  ⌀0.6 со спицами (часть корпуса, катание — позже), дышло влево
      Junk_Cart_Loaded.glb      R  та же тележка с горой хлама до 1.1 м
  030 Overturned_Junk_Cart.glb  S  1.8 × 1.1: тележка вверх дном, наклонена, одного колеса нет, из-под неё высыпался хлам
  031 Rail_Scrap_Wagon.glb      R  2.2 × 1.2 × 1.2: клёпаная трапециевидная вагонетка (rust_metal), рёбра, латунная
                                  корона-рельеф, 4 колеса с ребордами на осях, буфера (без рельсов)
      Rail_Scrap_Wagon_Full.glb R  та же, гружёная хламом до 1.4 м
  032 Broken_Wheelbarrow.glb    R  1.5 × 0.7 × 0.6: ржавая красная тачка — корыто, колесо со спицами спереди (−X),
                                  трубчатые ручки (правая погнута), ноги; вмятины
  033 Wooden_Pallet.glb         R  1.2 × 0.15 × 1.0: поддон — 5 досок настила, 3 поперечины, 9 шашек, 3 нижние доски
  034 Metal_Plate.glb           R  1.5 × 0.03 × 1.0: клёпаный лист с накладкой-полосой, слегка покороблен
      Metal_Plate_B.glb         R  тот же лист с отрезанным углом и отогнутой кромкой
      Metal_Plate_Stack.glb     S  стопка из 6 листов 1.6 × 0.24 × 1.1 (декор)
  035 Corrugated_Sheet.glb      R  2.0 × 0.05 × 1.0: профлист (волна 0.125 м поперёк X, видна спереди), погнутый угол,
                                  заклёпки по торцам (rust_metal)
      Corrugated_Sheet_B.glb    R  крашеный красный профлист (rust_painted_red) с другим изгибом
      Corrugated_Sheet_Stack.glb S стопка из 5 листов 2.1 × 0.3 × 1.1 (декор)
  036 Wooden_Beam.glb           R  3.0 × 0.3 × 0.3: брус с трещинами и сколами, 2 железных хомута с болтами
      Wooden_Beam_Stack.glb     S  штабель 3 + 2 бруса на прокладках, 3.0 × 0.62 × 1.0 (декор)
  037 Broken_Beam.glb           R  2.5 × 0.4 × 0.4: пакет из 4 расколотых брусьев разной длины, щепа на левом торце,
                                  железная скоба с болтами, два погнутых гвоздя
  038 Pipe_Bundle.glb           R  2.0 × 0.6 × 0.6: три полые трубы ⌀0.3 пирамидой (вдоль X), бандажи на торцах, два
                                  стальных хомута с болтами
  039 Rope_Coil.glb             R  ⌀0.9 × 0.3: бухта верёвки — два концентрических витка по 3 оборота + свободный конец
  040 Cable_Coil.glb            R  ⌀1.0 × 0.35: бухта стального троса — три плотных витка по ~4.8 оборота вокруг тёмного
                                  сердечника, 3 железные скобы с заклёпками, свободный конец
Не сделаны (есть на листе, для игры не нужны в этой волне): «open» 024, «broken/debris» 026/029/031/032, «variant»
033, «variant B» 037, «small/broken» 038, «loose» 039/040.
"""
import math
import os
import random
import sys
import tempfile

try:
    import bpy
    import bmesh
    from mathutils import Matrix, Vector
except ImportError:  # системный python3: только --sheet (Pillow)
    bpy = None

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
if bpy is not None:
    import common as C  # noqa: E402

GODOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(GODOT, "assets", "models", "scrap", "props")
CROWN = os.path.join(GODOT, "assets", "textures", "decals", "crown.png")
PBR_DIR = os.path.join(GODOT, "assets", "textures", "pbr")
SHEET_PNG = os.path.abspath(os.path.join(GODOT, "..", "docs", "plan-demo", "img", "scrap-sheet02-v1.png"))
REF_SHEET = os.path.abspath(os.path.join(GODOT, "..", "docs", "refs", "biomes", "01-scrap", "sheet-02.png"))
RENDER_TMP = os.environ.get("SCRAP_RENDER_TMP") or os.path.join(tempfile.gettempdir(), "scrap_props_render")
TRI_BUDGET = 3000
GLB_BUDGET = 4500
TEX_SIZE = int(os.environ.get("PROPS_TEX_SIZE", "1024"))
IMG_FORMAT = os.environ.get("PROPS_IMG", "WEBP")
CACHE = os.environ.get("SCRAP_PROPS_CACHE") or os.path.join(tempfile.gettempdir(), "ragdoll_scrap_props_pbr")
FORCE_FLAT = os.environ.get("SCRAP_FLAT", "0") == "1"
TAU = 2.0 * math.pi
RNG = random.Random(2102)


# ----------------------------------------------------------------------------------------------------------------------
# материалы
# ----------------------------------------------------------------------------------------------------------------------
_MATS = {}
MAT_STATUS = {}     # имя материала → "pbr <папка>" | "FLAT (нет набора <папка>)"

# имя → (папка PBR, kwargs textured_material, плоский запасной вариант (цвет, шероховатость, металличность))
MAT_DEFS = {
    "ScrapWood": ("scrap_wood", {}, ((0.30, 0.20, 0.12, 1.0), 0.86, 0.0)),                       # доски ящиков, бочка
    "ScrapWoodDark": ("scrap_wood", {"tint": (0.50, 0.44, 0.40, 1.0)}, ((0.13, 0.09, 0.07, 1.0), 0.88, 0.0)),  # 022
    "ScrapWoodPale": ("scrap_wood", {"tint": (1.08, 1.02, 0.94, 1.0)}, ((0.36, 0.26, 0.17, 1.0), 0.86, 0.0)),  # поддон, брус
    "Rust": ("rust_metal", {}, ((0.20, 0.11, 0.06, 1.0), 0.78, 0.35)),                            # ржавое железо
    "RustDark": ("rust_metal", {"tint": (0.55, 0.50, 0.48, 1.0)}, ((0.08, 0.06, 0.05, 1.0), 0.72, 0.5)),  # рёбра 022, хлам
    "RustRed": ("rust_painted_red", {}, ((0.30, 0.05, 0.03, 1.0), 0.62, 0.1)),                    # 024, 026, 032, 035B
    "Iron": ("iron", {}, ((0.10, 0.10, 0.10, 1.0), 0.5, 0.85)),                                  # обручи, болты, колёса
    "Steel": ("iron", {"tint": (0.95, 0.82, 0.68, 1.0), "roughness_scale": 0.9}, ((0.09, 0.07, 0.05, 1.0), 0.45, 0.9)),  # трос
    "Brass": ("brass_worn", {}, ((0.50, 0.36, 0.14, 1.0), 0.38, 0.9)),                           # короны-рельефы
    "Dirt": ("scrap_dirt", {"tint": (0.42, 0.38, 0.36, 1.0)}, ((0.03, 0.026, 0.023, 1.0), 0.95, 0.0)),  # насыпь под хламом (тёмная)
    "Rope": ("rope", {}, ((0.36, 0.25, 0.13, 1.0), 0.9, 0.0)),
}
FLAT_ONLY = {
    "Char": ((0.045, 0.036, 0.030, 1.0), 0.95, 0.0),
    "Rubber": ((0.035, 0.033, 0.032, 1.0), 0.8, 0.0),
}
CROWN_TINTS = {
    "Crown_Dark": (0.06, 0.045, 0.035, 1.0),    # выжженная тёмная корона на досках 021 (линейный множитель)
    "Crown_Gold": (1.0, 0.80, 0.42, 1.0),       # жёлтая краска на красных досках 024
    "Crown_Pale": (1.0, 0.90, 0.66, 1.0),       # бледная краска на красной бочке 026
}


def pbr_ready(folder):
    d = os.path.join(PBR_DIR, folder)
    return all(os.path.exists(os.path.join(d, f)) for f in ("albedo.png", "roughness.png", "normal.png"))


def pbr_folder(name):
    """Папка PBR-набора: исходная (2048²) или уменьшенная копия в кэше (PROPS_TEX_SIZE) — как в props.py."""
    src = os.path.join(PBR_DIR, name)
    if TEX_SIZE >= 2048:
        return src
    dst = os.path.join(CACHE, str(TEX_SIZE), name)
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
        if img.size[0] > TEX_SIZE:
            img.scale(TEX_SIZE, TEX_SIZE)
        img.filepath_raw = d
        img.file_format = 'PNG'
        img.save()
        bpy.data.images.remove(img)
    return dst


def M(name):
    """Материал по имени (лениво): PBR-набор, если он уже испечён, иначе плоский с тем же именем."""
    if name in _MATS:
        return _MATS[name]
    if name in CROWN_TINTS:
        m = decal_material(name, CROWN_TINTS[name])
        MAT_STATUS[name] = "decal crown.png × tint"
    elif name in FLAT_ONLY:
        base, rough, metal = FLAT_ONLY[name]
        m = C.material(name, base, rough, metal)
        MAT_STATUS[name] = "flat"
    else:
        folder, kw, flat = MAT_DEFS[name]
        if pbr_ready(folder) and not FORCE_FLAT:
            m = C.textured_material(name, pbr_folder(folder), **kw)
            MAT_STATUS[name] = "pbr " + folder
        else:
            base, rough, metal = flat
            m = C.material(name, base, rough, metal)
            MAT_STATUS[name] = "FLAT (нет набора %s)" % folder if not FORCE_FLAT else "FLAT (SCRAP_FLAT=1)"
    m.use_backface_culling = True
    _MATS[name] = m
    return m


def decal_material(name, tint):
    """Материал короны-декали (как common.decal_plane: Image → Base Color + Alpha, BLEND) с тинтом Multiply."""
    q = C.decal_plane(name + "_tmp", CROWN, (0.1, 0.1), (0, 0, -100))
    mat = q.data.materials[0]
    mat.name = name
    bpy.data.objects.remove(q, do_unlink=True)
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
    bsdf.inputs['Roughness'].default_value = 0.8
    return mat


# ----------------------------------------------------------------------------------------------------------------------
# геометрия (локальные координаты, origin в нуле; place() впекает трансформ)
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


WOOD_MATS = ("ScrapWood", "ScrapWoodDark", "ScrapWoodPale")   # scrap_wood: 4 доски на тайл, волокно вдоль V


def box(name, size, mat, along='X', jitter=0.0, scale=1.0, du=None, dv=None, broken=None, cuts=0):
    """Куб size с центром в нуле, кубическая UV в метрах × scale (волокна/подтёки вдоль `along`); du/dv — сдвиг развёртки
    (по умолчанию для досок — центр случайной доски текстуры, чтобы доска ≤ 0.25 м не пересекала шов).
    broken=(ось, знак, глубина) — рваный торец: вершины этого конца утоплены на случайную долю глубины.
    cuts — число поперечных разрезов вдоль самой длинной оси (для рваных торцов и коробления)."""
    if mat.name not in WOOD_MATS:
        along = 'Z'    # металл: V = мировой верх, подтёки ржавчины идут вниз (textures.py, THE SCRAP)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
    o = bpy.context.active_object
    o.name = name
    o.scale = size
    C.apply_transforms(o, scale=True)
    if cuts > 0:
        ax = max(range(3), key=lambda k: size[k])
        bm = bmesh.new()
        bm.from_mesh(o.data)
        for i in range(cuts):
            c = -size[ax] / 2 + size[ax] * (i + 1) / (cuts + 1)
            no = [0.0, 0.0, 0.0]
            no[ax] = 1.0
            geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
            bmesh.ops.bisect_plane(bm, geom=geom, plane_co=[c if k == ax else 0.0 for k in range(3)], plane_no=no)
        bm.to_mesh(o.data)
        bm.free()
    if jitter > 0.0:
        for v in o.data.vertices:
            v.co += Vector((RNG.uniform(-jitter, jitter), RNG.uniform(-jitter, jitter), RNG.uniform(-jitter, jitter)))
    if broken:
        ax, sgn, depth = broken
        lim = max(v.co[ax] * sgn for v in o.data.vertices) - 1e-5
        for v in o.data.vertices:
            if v.co[ax] * sgn > lim:
                v.co[ax] -= sgn * RNG.uniform(0.1, 1.0) * depth
    C.uv_box(o, scale, along)
    if du is None:
        du = (0.5 + RNG.randrange(4)) / 4.0 if mat.name in WOOD_MATS else RNG.uniform(0.0, 1.0)
    if dv is None:
        dv = RNG.uniform(0.0, 1.0)
    for d in o.data.uv_layers[0].data:
        d.uv = (d.uv[0] + du, d.uv[1] + dv)
    o.data.materials.append(mat)
    return o


def place(o, loc=(0, 0, 0), rot=(0, 0, 0)):
    """Впекает поворот (Эйлер XYZ) и позицию в геометрию; origin остаётся в мировом нуле."""
    if any(abs(r) > 1e-9 for r in rot):
        o.rotation_euler = rot
        C.apply_transforms(o, rotation=True)
    o.location = loc
    C.apply_transforms(o, location=True)
    return o


def xform(o, mat4):
    o.data.transform(mat4)
    o.data.update()
    return o


AXIS_ROT = {'Z': Matrix.Identity(4), 'Y': Matrix.Rotation(-math.pi / 2, 4, 'X'), 'X': Matrix.Rotation(math.pi / 2, 4, 'Y')} if bpy else {}


def lathe(name, profile, segs=16, mat=None, axis='Z', uv_scale=1.0, caps=True, around=None, phase=0.0):
    """Тело вращения из профиля [(r, z), …] (r=0 — полюс) вокруг оси `axis`; UV цилиндрические, V вдоль оси.
    caps=False — без торцевых крышек (обручи, кольца с замкнутым профилем)."""
    bm = bmesh.new()
    rings = []
    for r, z in profile:
        if r < 1e-6:
            rings.append([bm.verts.new((0.0, 0.0, z))])
        else:
            rings.append([bm.verts.new((r * math.cos(TAU * i / segs + phase), r * math.sin(TAU * i / segs + phase), z)) for i in range(segs)])
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
    if caps:
        if len(rings[0]) > 1:
            bm.faces.new(list(reversed(rings[0])))
        if len(rings[-1]) > 1:
            bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = mesh_obj(name, bm, [mat] if mat else [])
    C.uv_cylinder_along(o, 'Z', uv_scale, centre=(0.0, 0.0), around=around)
    xform(o, AXIS_ROT[axis])
    return o


def cyl(name, r, length, axis, mat, segs=12, caps=True):
    return lathe(name, [(0.0, -length / 2), (r, -length / 2), (r, length / 2), (0.0, length / 2)] if caps else
                 [(r, -length / 2), (r, length / 2)], segs, mat, axis, caps=False)


def ring(name, r_in, r_out, width, axis, mat, segs=16, outer_only=False):
    """Обруч/кольцо прямоугольного сечения вдоль оси; outer_only — без внутренней стенки (прилегает к телу)."""
    h = width / 2
    if outer_only:
        prof = [(r_in, -h), (r_out, -h), (r_out, h), (r_in, h)]
    else:
        prof = [(r_in, -h), (r_out, -h), (r_out, h), (r_in, h), (r_in, -h)]
    return lathe(name, prof, segs, mat, axis, caps=False)


def stud(name, loc, normal, r=0.012, h=0.009, mat=None):
    """Заклёпка/шляпка болта: низкая шестигранная пирамида без дна (6 треугольников), основание на поверхности."""
    n = Vector(normal).normalized()
    t1 = n.orthogonal().normalized()
    t2 = n.cross(t1)
    bm = bmesh.new()
    base = [bm.verts.new(Vector(loc) + (t1 * math.cos(TAU * k / 6) + t2 * math.sin(TAU * k / 6)) * r) for k in range(6)]
    top = bm.verts.new(Vector(loc) + n * h)
    for k in range(6):
        bm.faces.new((base[k], base[(k + 1) % 6], top))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        if f.normal.dot(n) < 0:
            f.normal_flip()
    o = mesh_obj(name, bm, [mat or M("Iron")])
    C.uv_box(o, 1.0)
    return o


def between(name, p0, p1, w, t, mat, up=(0, 0, 1), along='X', jitter=0.0, broken=None):
    """Брусок от p0 до p1: длина вдоль отрезка, ширина w (поперёк, ⊥ up), толщина t (вдоль up)."""
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    L = d.length
    x = d.normalized()
    z = Vector(up)
    z = (z - x * z.dot(x))
    if z.length < 1e-6:
        z = x.orthogonal()
    z.normalize()
    y = z.cross(x)
    o = box(name, (L, w, t), mat, along=along, jitter=jitter, broken=broken)
    m = Matrix((x, y, z)).transposed().to_4x4()
    m.translation = (p0 + p1) * 0.5
    return xform(o, m)


def plate_xz(name, pts, thickness, mat, y=0.0, along='Z'):
    """Плоская деталь: многоугольник в плоскости XZ [(x, z), …] толщиной вдоль Y (лицо в −Y)."""
    bm = bmesh.new()
    front = [bm.verts.new((x, y - thickness / 2, z)) for x, z in pts]
    back = [bm.verts.new((x, y + thickness / 2, z)) for x, z in pts]
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    n = len(front)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((front[j], front[i], back[i], back[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = mesh_obj(name, bm, [mat])
    C.uv_box(o, 1.0, along)
    return o


def spike(name, base, tip, width, mat):
    """Щепка: тонкий тетраэдр от base к tip."""
    base, tip = Vector(base), Vector(tip)
    d = tip - base
    p1 = d.orthogonal().normalized() * width
    p2 = d.cross(p1).normalized() * width
    bm = bmesh.new()
    v0 = bm.verts.new(base + p1)
    v1 = bm.verts.new(base - p1 * 0.5 + p2 * 0.87)
    v2 = bm.verts.new(base - p1 * 0.5 - p2 * 0.87)
    vt = bm.verts.new(tip)
    for f in ((v0, v1, v2), (v0, vt, v1), (v1, vt, v2), (v2, vt, v0)):
        bm.faces.new(f)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = mesh_obj(name, bm, [mat])
    C.uv_box(o, 1.0, 'X')
    return o


def splinters(name, centre, direction, n, length, width, mat, spread=0.5):
    """Пучок щепок из точки centre в сторону direction (рваный торец доски/бруса)."""
    c = Vector(centre)
    d = Vector(direction).normalized()
    t1 = d.orthogonal().normalized()
    t2 = d.cross(t1)
    out = []
    for i in range(n):
        off = (t1 * RNG.uniform(-1, 1) + t2 * RNG.uniform(-1, 1)) * width * 1.5
        tip = c + off + (d + t1 * RNG.uniform(-spread, spread) + t2 * RNG.uniform(-spread, spread)).normalized() * length * RNG.uniform(0.5, 1.0)
        out.append(spike("%s_%d" % (name, i), c + off, tip, width * RNG.uniform(0.6, 1.0), mat))
    return out


def tube_path(name, pts, r, mat, sides=6, uv_scale=4.0, caps=True, closed=False, around=1.0):
    """Труба по ломаной pts (параллельный перенос рамок): верёвка, трос, ручки. UV: U — обхват (0..around),
    V — длина × uv_scale."""
    pts = [Vector(p) for p in pts]
    n = len(pts)
    tangents = []
    for i in range(n):
        if closed:
            t = pts[(i + 1) % n] - pts[i - 1]
        else:
            t = pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]
        tangents.append(t.normalized())
    nrm = tangents[0].orthogonal().normalized()
    frames = []
    for i in range(n):
        if i > 0:
            axis = tangents[i - 1].cross(tangents[i])
            if axis.length > 1e-8:
                ang = tangents[i - 1].angle(tangents[i])
                nrm = (Matrix.Rotation(ang, 3, axis.normalized()) @ nrm).normalized()
        b = tangents[i].cross(nrm).normalized()
        frames.append((nrm.copy(), b))
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    rings = []
    for i in range(n):
        nn, bb = frames[i]
        rings.append([bm.verts.new(pts[i] + (nn * math.cos(TAU * k / sides) + bb * math.sin(TAU * k / sides)) * r) for k in range(sides)])
    acc = [0.0]
    for i in range(1, n):
        acc.append(acc[-1] + (pts[i] - pts[i - 1]).length)
    if closed:
        acc.append(acc[-1] + (pts[0] - pts[-1]).length)
    seg = range(n) if closed else range(n - 1)
    for i in seg:
        i2 = (i + 1) % n
        for k in range(sides):
            k2 = (k + 1) % sides
            f = bm.faces.new((rings[i][k], rings[i][k2], rings[i2][k2], rings[i2][k]))
            us = [k / sides * around, (k + 1) / sides * around, (k + 1) / sides * around, k / sides * around]
            v0, v1 = acc[i] * uv_scale, acc[i + 1] * uv_scale
            for l, u, v in zip(f.loops, us, (v0, v0, v1, v1)):
                l[uvl].uv = (u, v)
    if caps and not closed:
        f0 = bm.faces.new(list(reversed(rings[0])))
        f1 = bm.faces.new(rings[-1])
        for f in (f0, f1):
            for l in f.loops:
                l[uvl].uv = (0.5, 0.5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return mesh_obj(name, bm, [mat])


def gear(name, r, teeth, thick, mat, hole=0.0):
    """Шестерня в плоскости XZ (толщина вдоль Y): зубья-трапеции, опционально квадратное окно-ступица не делаем —
    вместо отверстия тёмная втулка (hole > 0 — радиус втулки)."""
    pts = []
    for i in range(teeth):
        a = TAU * i / teeth
        da = TAU / teeth
        for k, (fa, rr) in enumerate(((0.0, r * 0.8), (0.18, r), (0.5, r), (0.68, r * 0.8))):
            aa = a + fa * da
            pts.append((rr * math.cos(aa), rr * math.sin(aa)))
    o = plate_xz(name, pts, thick, mat)
    if hole > 0.0:
        hub = cyl(name + "_hub", hole, thick * 1.6, 'Y', M("Iron"), segs=8)
        o = C.join([o, hub], name)
    return o


def bevel_apply(o, width, segments=1, angle=30.0):
    m = C.bevel(o, width, segments, angle)
    m.harden_normals = True
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier=m.name)
    return o


def solidify_apply(o, thickness, offset=0.0):
    m = o.modifiers.new("Solid", 'SOLIDIFY')
    m.thickness = thickness
    m.offset = offset
    m.use_even_offset = True
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier=m.name)
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


def merge(objs, name):
    objs = [o for o in objs if o is not None]
    if len(objs) == 1:
        objs[0].name = name
        return objs[0]
    return C.join(objs, name)


def finish(o, angle=30.0, origin=(0.0, 0.0, 0.0)):
    C.set_origin(o, origin)
    smooth(o, angle)
    return o


def ground(o, sink=0.0):
    """Сдвигает геометрию так, чтобы нижняя точка была на z = −sink (origin остаётся центром основания)."""
    zmin = min(v.co.z for v in o.data.vertices)
    xform(o, Matrix.Translation((0.0, 0.0, -zmin - sink)))
    return o


def bbox_centre(o):
    xs = [v.co.x for v in o.data.vertices]
    ys = [v.co.y for v in o.data.vertices]
    zs = [v.co.z for v in o.data.vertices]
    return ((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, (min(zs) + max(zs)) / 2)


def piece(objs, name, holder, angle=30.0):
    """Обломок Destroyed/Piece_*: объединяет части, origin — центр bbox, родитель — пустышка Destroyed."""
    o = merge(objs, name)
    finish(o, angle, bbox_centre(o))
    C.parent(o, holder)
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


def decal_quad(name, w, h, loc, mat_name, y_dir=-1.0):
    """Квад декали лицом в −Y (к камере), UV 0..1; loc — центр."""
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    x0, z0 = loc[0] - w / 2, loc[2] - h / 2
    vs = [bm.verts.new((x0, loc[1], z0)), bm.verts.new((x0 + w, loc[1], z0)), bm.verts.new((x0 + w, loc[1], z0 + h)), bm.verts.new((x0, loc[1], z0 + h))]
    f = bm.faces.new(vs)
    f.normal_update()
    if f.normal.y * y_dir < 0:
        f.normal_flip()
    for l in f.loops:
        l[uvl].uv = ((l.vert.co.x - x0) / w, (l.vert.co.z - z0) / h)
    return mesh_obj(name, bm, [M(mat_name)])


def decal_cyl(name, r, zc, w, h, mat_name, segs=8, centre_angle=-math.pi / 2):
    """Декаль по цилиндру радиуса r (ось Z): полоса шириной w по дуге с центром в направлении centre_angle (−Y)."""
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    span = w / r
    cols = []
    for i in range(segs + 1):
        a = centre_angle - span / 2 + span * i / segs
        cols.append((bm.verts.new((r * math.cos(a), r * math.sin(a), zc - h / 2)), bm.verts.new((r * math.cos(a), r * math.sin(a), zc + h / 2)), i / segs))
    for i in range(segs):
        (b0, t0, u0), (b1, t1, u1) = cols[i], cols[i + 1]
        f = bm.faces.new((b0, b1, t1, t0))
        for l in f.loops:
            u = u0 if l.vert in (b0, t0) else u1
            v = 0.0 if l.vert in (b0, b1) else 1.0
            l[uvl].uv = (u, v)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        c = f.calc_center_median()
        if f.normal.dot(Vector((c.x, c.y, 0.0))) < 0:
            f.normal_flip()
    return mesh_obj(name, bm, [M(mat_name)])


def crown_relief(name, w, h, t, mat, loc):
    """Рельефная корона (латунь) лицом в −Y: пояс, тело с тремя зубцами и ромбом, шарики на зубцах. loc — центр пояса
    снизу по X, передняя плоскость основания на loc.y (рельеф выступает в −Y на t)."""
    x0, y0, z0 = loc
    band = box(name + "_band", (w * 0.74, t, h * 0.15), mat, along='X')
    place(band, (x0, y0 - t / 2, z0 + h * 0.075))
    body_pts = [(-0.36, 0.19), (0.36, 0.19), (0.42, 0.66), (0.22, 0.45), (0.0, 0.86), (-0.22, 0.45), (-0.42, 0.66)]
    body = plate_xz(name + "_body", [(x0 + px * w, z0 + pz * h) for px, pz in body_pts], t * 0.8, mat, y0 - t * 0.4)
    parts = [band, body]
    for px, pz in ((-0.42, 0.70), (0.0, 0.90), (0.42, 0.70)):
        s = C.add_sphere(name + "_ball", w * 0.05, loc=(x0 + px * w, y0 - t * 0.4, z0 + pz * h), segments=6, rings=4)
        s.data.materials.append(mat)
        C.uv_box(s, 1.0)
        parts.append(s)
    for k in (-1, 0, 1):
        parts.append(stud(name + "_gem", (x0 + k * w * 0.2, y0 - t, z0 + h * 0.075), (0, -1, 0), r=w * 0.035, h=w * 0.02, mat=mat))
    return parts


# ----------------------------------------------------------------------------------------------------------------------
# ящики 021 / 022 / 023: спецификация деталей → целый / повреждённый / обломки
# ----------------------------------------------------------------------------------------------------------------------
class Part:
    __slots__ = ("key", "size", "loc", "rot", "mat", "along", "bev", "grp")

    def __init__(self, key, size, loc, mat, along, bev=0.0, rot=(0, 0, 0), grp=""):
        self.key, self.size, self.loc, self.mat, self.along, self.bev, self.rot, self.grp = key, list(size), list(loc), mat, along, bev, rot, grp


def build_part(p, name, cut=0.0, side=1, jag=0.06):
    """Строит деталь; cut > 0 — укоротить с конца `side` (+1/−1) по длинной оси на cut, торец рваный."""
    size, loc = list(p.size), list(p.loc)
    broken = None
    if cut > 0.0:
        ax = max(range(3), key=lambda k: size[k])
        size[ax] -= cut
        loc[ax] -= side * cut / 2
        broken = (ax, side, jag)
    o = box(name, tuple(size), M(p.mat), along=p.along, jitter=0.002, broken=broken, cuts=2 if broken else 0)
    if p.bev > 0.0:
        bevel_apply(o, p.bev)
    return place(o, tuple(loc), p.rot)


def crate_spec(S=1.0, e=0.11, t=0.04, frame="ScrapWood", plank="ScrapWood", front_h=False, plate_mat="Iron", n_front=4,
               iron_frame=False):
    """Детали ящика со стороной S: стойки (post), брусья (rx/ry), доски фасада (pf, вертикальные или горизонтальные при
    front_h), задней стенки (pb), боков (pl/pr), крышки (pt), угловые накладки (cp_*). Доски утоплены на 2.5 см."""
    h = S / 2
    parts = []
    er = e * 0.9
    bev_f = 0.008 if iron_frame else 0.012
    for sx in (-1, 1):
        for sy in (-1, 1):
            parts.append(Part("post_%d%d" % (sx, sy), (e, e, S), (sx * (h - e / 2), sy * (h - e / 2), h), frame, 'Z', bev_f))
    for sy in (-1, 1):
        for sz, z in ((-1, er / 2), (1, S - er / 2)):
            parts.append(Part("rx_%d%d" % (sy, sz), (S - 2 * e, er, er), (0, sy * (h - er / 2), z), frame, 'X', bev_f))
    for sx in (-1, 1):
        for sz, z in ((-1, er / 2), (1, S - er / 2)):
            parts.append(Part("ry_%d%d" % (sx, sz), (er, S - 2 * e, er), (sx * (h - er / 2), 0, z), frame, 'Y', bev_f))
    inner = S - 2 * e
    ih = S - 2 * er
    face = h - 0.025 - t / 2
    # фасад и задняя стенка
    for sy, key, bev in ((-1, "pf", 0.006), (1, "pb", 0.0)):
        if front_h and sy < 0:
            n = 3
            pw = ih / n
            for i in range(n):
                parts.append(Part("%s_%d" % (key, i), (inner + 0.01, t, pw - 0.008), (0, sy * face, er + pw * (n - 1 - i + 0.5)), plank, 'X', bev))
        else:
            n = n_front
            pw = inner / n
            for i in range(n):
                parts.append(Part("%s_%d" % (key, i), (pw - 0.006, t, ih + 0.01), (-inner / 2 + pw * (i + 0.5), sy * face, h), plank, 'Z', bev))
    # бока
    for sx, key in ((-1, "pl"), (1, "pr")):
        n = 4
        pw = inner / n
        for i in range(n):
            parts.append(Part("%s_%d" % (key, i), (t, pw - 0.006, ih + 0.01), (sx * face, -inner / 2 + pw * (i + 0.5), h), plank, 'Z'))
    # крышка: доски вдоль X, по Y от фасада (i=0) назад
    n = 4
    pw = inner / n
    for i in range(n):
        parts.append(Part("pt_%d" % i, (inner + 0.01, pw - 0.006, t), (0, -inner / 2 + pw * (i + 0.5), S - 0.025 - t / 2), plank, 'X', 0.006))
    # угловые накладки (3 пластины на угол)
    if not iron_frame:
        pl, th = 0.15, 0.008
        for sx in (-1, 1):
            for sy in (-1, 1):
                for sz in (-1, 1):
                    cx, cy = sx * (h - pl / 2), sy * (h - pl / 2)
                    cz = h + sz * (h - pl / 2)
                    k = "cp_%d%d%d" % (sx, sy, sz)
                    parts.append(Part(k + "_x", (th, pl, pl), (sx * (h + th / 2), cy, cz), plate_mat, 'Z'))
                    parts.append(Part(k + "_y", (pl, th, pl), (cx, sy * (h + th / 2), cz), plate_mat, 'Z'))
                    if sz > 0:   # снизу накладку не видно, и она ушла бы под пол
                        parts.append(Part(k + "_z", (pl, pl, th), (cx, cy, h + sz * (h + th / 2)), plate_mat, 'Z'))
    return parts


def crate_studs(name, S, skip_corner=None, e=0.11):
    """Гвозди/заклёпки фасада 021: по 2 на угловой накладке, по 2 на концах досок фасада."""
    h = S / 2
    out = []
    for sx in (-1, 1):
        for sz in (-1, 1):
            if skip_corner == (sx, sz):
                continue
            for (dx, dz) in ((0.035, 0.1), (0.1, 0.035)):
                out.append(stud(name + "_cs", (sx * (h - dx), -h - 0.008, h + sz * (h - dz)), (0, -1, 0)))
    return out


def crate_021(kind):
    """Деревянный ящик 021: kind = intact | damaged | destroyed."""
    RNG.seed(21)
    S = 1.0
    h = S / 2
    spec = {p.key: p for p in crate_spec(S)}
    if kind == "destroyed":
        holder = empty("Destroyed")
        groups = [
            (["post_-1-1", "ry_-1-1"], {"ry_-1-1": 0.3}),
            (["post_1-1", "rx_-1-1"], {"rx_-1-1": 0.25}),
            (["pf_0", "pf_1"], {"pf_1": 0.3}),
            (["pf_2", "pf_3"], {"pf_3": 0.45}),
            (["pt_0", "pt_1"], {"pt_1": 0.35}),
            (["rx_-11", "cp_-1-11_y"], {"rx_-11": 0.3}),
            (["post_-11", "pb_0", "pb_1"], {"pb_1": 0.2}),
            (["post_11", "pb_2", "pb_3", "pr_3"], {"pb_2": 0.3}),
        ]
        for gi, (keys, cuts) in enumerate(groups):
            objs = []
            for k in keys:
                side = RNG.choice((-1, 1))
                objs.append(build_part(spec[k], "%s_%d" % (k, gi), cuts.get(k, 0.0), side))
            piece(objs, "Piece_%d" % gi, holder)
        return holder
    removed, cuts = set(), {}
    if kind == "damaged":
        removed = {"pt_0", "cp_1-11_x", "cp_1-11_y", "cp_1-11_z"}
        cuts = {"pt_1": (0.42, -1), "pf_3": (0.46, 1), "rx_-11": (0.26, 1), "pl_0": (0.3, 1)}
    parts = []
    for p in spec.values():
        if p.key in removed:
            continue
        c, sd = cuts.get(p.key, (0.0, 1))
        parts.append(build_part(p, "%s_%s" % (kind, p.key), c, sd))
    parts += crate_studs(kind, S, skip_corner=(1, 1) if kind == "damaged" else None)
    for i in range(4):   # гвозди на концах досок фасада
        x = -0.39 + 0.195 * (i + 0.5)
        for z in (0.16, 0.84):
            if kind == "damaged" and i == 3 and z > 0.5:
                continue
            parts.append(stud("%s_nail" % kind, (x, -h + 0.025 - 0.001, z), (0, -1, 0), r=0.009, h=0.006))
    parts.append(decal_quad(kind + "_crown", 0.44, 0.44, (0.0, -h + 0.025 - 0.006, 0.5), "Crown_Dark"))
    if kind == "damaged":
        parts += splinters("sp_a", (0.29, -h + 0.045, 0.55), (0.1, -0.2, 1.0), 4, 0.1, 0.012, M("ScrapWood"))
        parts += splinters("sp_b", (0.2, -h + 0.05, S - 0.05), (1.0, -0.3, 0.3), 3, 0.1, 0.012, M("ScrapWood"))
        parts += splinters("sp_c", (-0.1, -0.12, S - 0.02), (-1.0, -0.2, 0.6), 3, 0.08, 0.01, M("ScrapWood"))
    return finish(merge(parts, kind.capitalize()), 30.0)


def crate_022(kind):
    """Усиленный ящик 022: тёмные доски, железные рёбра по кромкам, полосы с болтами, латунная корона-рельеф."""
    RNG.seed(22)
    S, e = 1.0, 0.1
    h = S / 2
    spec = {p.key: p for p in crate_spec(S, e=e, frame="RustDark", plank="ScrapWoodDark", front_h=True, iron_frame=True)}
    # вертикальные полосы фасада и крышки
    for sx in (-1, 1):
        spec["st_%d" % sx] = Part("st_%d" % sx, (0.07, 0.014, S - 2 * e * 0.9 + 0.02), (sx * 0.27, -h + 0.003, h), "RustDark", 'Z', 0.0)
        spec["stt_%d" % sx] = Part("stt_%d" % sx, (0.07, S - 2 * e * 0.9 + 0.02, 0.014), (sx * 0.27, 0.0, S - 0.003), "RustDark", 'Y', 0.0)
    if kind == "destroyed":
        holder = empty("Destroyed")
        groups = [
            (["post_-1-1", "rx_-1-1"], {}),
            (["post_1-1", "ry_1-1"], {"ry_1-1": 0.35}),
            (["pf_0", "st_-1"], {"pf_0": 0.3}),
            (["pf_1", "pf_2", "st_1"], {"pf_1": 0.2}),
            (["rx_-11", "pt_0"], {"pt_0": 0.3}),
            (["pt_1", "pt_2", "stt_-1"], {}),
            (["post_-11", "pb_0", "pb_1"], {}),
            (["post_11", "pb_2", "pb_3", "pr_2", "pr_3"], {"pr_2": 0.3}),
        ]
        for gi, (keys, cuts) in enumerate(groups):
            objs = [build_part(spec[k], "%s_%d" % (k, gi), cuts.get(k, 0.0), RNG.choice((-1, 1))) for k in keys]
            if gi == 3:
                objs += crown_relief("crw%d" % gi, 0.42, 0.4, 0.02, M("Brass"), (0.0, -h + 0.025 - 0.001, 0.3))
            piece(objs, "Piece_%d" % gi, holder)
        return holder
    removed, cuts, rots = set(), {}, {}
    if kind == "damaged":
        removed = {"pt_0", "stt_1"}
        cuts = {"pf_0": (0.38, 1), "pt_1": (0.3, 1), "st_1": (0.3, 1), "pl_0": (0.35, 1)}
        rots = {"st_1": (0.0, math.radians(-10), 0.0)}
    parts = []
    for p in spec.values():
        if p.key in removed:
            continue
        c, sd = cuts.get(p.key, (0.0, 1))
        if p.key in rots:
            p.rot = rots[p.key]
            p.loc = [p.loc[0] + 0.03, p.loc[1] - 0.02, p.loc[2]]
        parts.append(build_part(p, "%s_%s" % (kind, p.key), c, sd))
    # болты: рёбра фасада и полосы
    for sz in (-1, 1):
        z = h + sz * (h - e * 0.45)
        for i in range(5):
            x = -0.34 + 0.17 * i
            parts.append(stud(kind + "_b", (x, -h - 0.001, z), (0, -1, 0), r=0.016, h=0.012))
    for sx in (-1, 1):
        for i in range(4):
            parts.append(stud(kind + "_b", (sx * (h - e / 2), -h - 0.001, 0.2 + 0.2 * i), (0, -1, 0), r=0.016, h=0.012))
        for i in range(4):
            if kind == "damaged" and sx > 0 and i == 3:
                continue
            parts.append(stud(kind + "_b", (sx * 0.27, -h - 0.012, 0.19 + 0.2 * i), (0, -1, 0), r=0.013, h=0.01))
    parts += crown_relief(kind + "_crown", 0.42, 0.4, 0.02, M("Brass"), (0.0, -h + 0.025 - 0.001, 0.3))
    if kind == "damaged":
        parts += splinters("sp_a", (0.1, -h + 0.045, S - 0.18), (1.0, -0.3, 0.2), 4, 0.1, 0.012, M("ScrapWoodDark"))
        parts += splinters("sp_b", (-0.1, -0.2, S - 0.02), (-1.0, 0.2, 0.5), 3, 0.08, 0.01, M("ScrapWoodDark"))
    return finish(merge(parts, kind.capitalize()), 30.0)


def broken_crate(name, variant):
    """023: развалившийся ящик 1.0 × 0.6 × 1.0 (A/B) или плоская куча обломков (debris)."""
    RNG.seed({"A": 231, "B": 232, "debris": 233}[variant])
    S = 1.0
    h = S / 2
    spec = {p.key: p for p in crate_spec(S)}
    parts = []
    if variant in ("A", "B"):
        if variant == "A":
            posts = {"post_-1-1": 0.42, "post_1-1": 0.55, "post_-11": 0.38, "post_11": 0.7}   # сколько срезать сверху
            keep = {"rx_-1-1": 0.0, "rx_1-1": 0.25, "ry_-1-1": 0.0, "ry_1-1": 0.3,
                    "pf_0": 0.55, "pf_1": 0.62, "pb_1": 0.5, "pb_2": 0.58, "pl_1": 0.55, "pl_2": 0.6, "pr_0": 0.66, "pr_3": 0.7}
            brace = ((-0.42, -0.47, 0.08), (0.42, -0.47, 0.56))
        else:
            posts = {"post_-1-1": 0.38, "post_1-1": 0.8, "post_-11": 0.42, "post_11": 0.5}
            keep = {"rx_-1-1": 0.0, "rx_1-1": 0.2, "ry_-1-1": 0.25, "ry_1-1": 0.0,
                    "pf_2": 0.58, "pf_3": 0.62, "pb_0": 0.52, "pb_3": 0.66, "pl_0": 0.5, "pl_3": 0.6, "pr_1": 0.62, "pr_2": 0.75}
            brace = ((0.42, -0.47, 0.08), (-0.38, -0.47, 0.5))
        for k, cut in posts.items():
            parts.append(build_part(spec[k], name + k, cut, 1, 0.08))
        for k, cut in keep.items():
            parts.append(build_part(spec[k], name + k, cut, 1 if spec[k].along == 'Z' else RNG.choice((-1, 1)), 0.07))
        parts.append(between(name + "_brace", brace[0], brace[1], 0.12, 0.035, M("ScrapWood"), up=(0, -1, 0), jitter=0.002))
        # доска, провалившаяся внутрь, и доска у фасада на полу
        parts.append(between(name + "_fall", (-0.35, -0.1, 0.12), (0.3, 0.25, 0.42), 0.19, 0.04, M("ScrapWood"), up=(0, -0.3, 1), broken=(0, 1, 0.06)))
        parts.append(between(name + "_floor", (-0.46, -0.52, 0.02), (0.2, -0.43, 0.03), 0.18, 0.035, M("ScrapWood"), up=(0, 0, 1), broken=(0, 1, 0.07)))
        for i in range(3):
            x = RNG.uniform(-0.3, 0.3)
            parts += splinters(name + "_sp%d" % i, (x, -0.47, RNG.uniform(0.35, 0.5)), (RNG.uniform(-0.3, 0.3), -0.2, 1.0), 3, 0.09, 0.012, M("ScrapWood"))
        for sx in (-1, 1):   # уцелевшие нижние накладки
            parts.append(build_part(spec["cp_%d-1-1_y" % sx], name + "cp%d" % sx))
            parts.append(stud(name + "_cs", (sx * 0.4, -h - 0.008, 0.035), (0, -1, 0)))
    else:
        # куча: доски вповалку, обломки стоек, щепки — низко, до 0.25 м
        boards = [((-0.5, -0.3), (0.45, -0.1), 0.02, 0.2, 0.0), ((-0.3, 0.3), (0.55, -0.35), 0.06, 0.19, 0.15),
                  ((-0.55, 0.1), (0.1, 0.42), 0.035, 0.18, -0.1), ((0.0, -0.45), (0.5, 0.35), 0.1, 0.19, 0.2),
                  ((-0.45, -0.45), (-0.05, 0.25), 0.13, 0.17, -0.25), ((0.15, 0.4), (0.6, 0.05), 0.03, 0.16, 0.05)]
        for i, ((x0, y0), (x1, y1), z, w, tilt) in enumerate(boards):
            parts.append(between("%s_b%d" % (name, i), (x0, y0, z), (x1, y1, z + 0.02 + tilt * 0.3), w, 0.035, M("ScrapWood"), up=(tilt, 0.1, 1), jitter=0.002, broken=(0, RNG.choice((-1, 1)), 0.07)))
        for i, ((x0, y0, z0), (x1, y1, z1)) in enumerate((((-0.2, -0.2, 0.06), (0.35, 0.1, 0.2)), ((0.3, -0.3, 0.055), (0.55, 0.3, 0.07)))):
            parts.append(between("%s_p%d" % (name, i), (x0, y0, z0), (x1, y1, z1), 0.11, 0.11, M("ScrapWood"), up=(0, 0, 1), jitter=0.003, broken=(0, 1, 0.08)))
        parts.append(between(name + "_cp", (-0.1, -0.35, 0.16), (0.05, -0.33, 0.2), 0.15, 0.008, M("Iron"), up=(0.2, 0, 1)))
        for i in range(5):
            parts += splinters(name + "_sp%d" % i, (RNG.uniform(-0.5, 0.5), RNG.uniform(-0.4, 0.3), 0.02), (RNG.uniform(-1, 1), RNG.uniform(-1, 1), 0.15), 2, 0.12, 0.013, M("ScrapWood"))
    return finish(ground(merge(parts, name), 0.004 if variant == "debris" else 0.0), 30.0)


# ----------------------------------------------------------------------------------------------------------------------
# бочки 025 / 027
# ----------------------------------------------------------------------------------------------------------------------
BR_R0, BR_R1, BR_H, NS = 0.29, 0.35, 1.0, 16
BR_ZS = [0.0, 0.25, 0.5, 0.75, 1.0]


def barrel_r(z):
    """Радиус наружной поверхности клёпок: кусочно-линейный по уровням BR_ZS (как строится меш) — обручи не режутся."""
    def rr(zz):
        t = (zz - BR_H / 2) / (BR_H / 2)
        return BR_R1 - (BR_R1 - BR_R0) * t * t
    z = min(max(z, 0.0), BR_H)
    for a, b in zip(BR_ZS, BR_ZS[1:]):
        if a <= z <= b:
            f = (z - a) / (b - a)
            return rr(a) * (1 - f) + rr(b) * f
    return rr(z)


def stave_set(name, indices, thick=0.025, gap=0.006, tops=None, tilt=None, mat="ScrapWood"):
    """Клёпки бочки с индексами indices (0..NS−1, угол 0 = +X, против часовой; фасад −Y = индексы 11–12).
    tops={i: (z_обл, размах)} — обломаны сверху; tilt={i: k} — отогнуты наружу (k·z). Плоские клёпки (4 грани на
    уровень). UV: U = угол/2π × 4 → одна доска текстуры на клёпку, V = z."""
    tops = tops or {}
    tilt = tilt or {}
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    g = gap / (2.0 * BR_R1)
    for i in indices:
        a0, a1 = TAU * i / NS + g, TAU * (i + 1) / NS - g
        cut = tops.get(i)
        zl = [z for z in BR_ZS if cut is None or z < cut[0] - 0.04]
        if cut:
            zl.append(cut[0])
        out_r, in_r = [], []
        for z in zl:
            r = barrel_r(z)
            push = tilt.get(i, 0.0) * z
            ro, ri = [], []
            for k, a in enumerate((a0, a1)):
                zz = z + (RNG.uniform(-cut[1], cut[1]) if (cut and z == cut[0]) else 0.0)
                ro.append(bm.verts.new(((r + push) * math.cos(a), (r + push) * math.sin(a), zz)))
                ri.append(bm.verts.new(((r - thick + push) * math.cos(a), (r - thick + push) * math.sin(a), zz)))
            out_r.append(ro)
            in_r.append(ri)
        for j in range(len(zl) - 1):
            bm.faces.new((out_r[j][0], out_r[j][1], out_r[j + 1][1], out_r[j + 1][0]))
            bm.faces.new((in_r[j][1], in_r[j][0], in_r[j + 1][0], in_r[j + 1][1]))
            bm.faces.new((in_r[j][0], out_r[j][0], out_r[j + 1][0], in_r[j + 1][0]))
            bm.faces.new((out_r[j][1], in_r[j][1], in_r[j + 1][1], out_r[j + 1][1]))
        bm.faces.new((out_r[0][1], out_r[0][0], in_r[0][0], in_r[0][1]))
        bm.faces.new((out_r[-1][0], out_r[-1][1], in_r[-1][1], in_r[-1][0]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        cap = abs(f.normal.z) > 0.7
        for l in f.loops:
            co = l.vert.co
            a = math.atan2(co.y, co.x) % TAU
            l[uvl].uv = (a / TAU * 4.0, math.hypot(co.x, co.y) if cap else co.z)
    return mesh_obj(name, bm, [M(mat)])


def barrel_hoop(name, z, width=0.045, thick=0.01, extra=0.004, tilt=0.0, rivets=(), segs=16):
    """Обруч на высоте z (по наружному радиусу клёпок) без внутренней стенки; rivets — углы заклёпок (рад)."""
    r = barrel_r(z) + extra
    parts = [ring(name, r - 0.004, r + thick, width, 'Z', M("Iron"), segs, outer_only=True)]
    for k, a in enumerate(rivets):
        parts.append(stud("%s_r%d" % (name, k), ((r + thick) * math.cos(a), (r + thick) * math.sin(a), 0.0), (math.cos(a), math.sin(a), 0.0), r=0.011, h=0.008))
    o = merge(parts, name)
    return place(o, (0, 0, z), (tilt, 0, 0))


FRONT_RIVETS = (math.radians(-90 - 35), math.radians(-90), math.radians(-90 + 35), math.radians(90))
HOOP_Z = (0.07, 0.3, 0.7, 0.93)


def barrel_lid(name, z):
    r = barrel_r(z) - 0.022
    o = lathe(name, [(0.0, -0.015), (r, -0.015), (r, 0.015), (0.0, 0.015)], NS, M("ScrapWood"), caps=False)
    C.uv_box(o, 1.0, 'Y')
    return place(o, (0, 0, z))


def barrel_025(kind):
    RNG.seed(25)
    if kind == "intact":
        parts = [stave_set("st", range(NS)), barrel_lid("lid", BR_H - 0.05)]
        parts += [barrel_hoop("h%d" % i, z, rivets=FRONT_RIVETS) for i, z in enumerate(HOOP_Z)]
        return finish(merge(parts, "Intact"), 30.0)
    if kind == "damaged":
        idx = [i for i in range(NS) if i not in (11, 12)]
        parts = [stave_set("st", idx, tops={10: (0.62, 0.05), 13: (0.74, 0.05), 3: (0.8, 0.04), 14: (0.88, 0.03)}, tilt={13: 0.05, 10: 0.03}),
                 barrel_lid("lid", BR_H - 0.12)]
        parts += [barrel_hoop("h%d" % i, z, rivets=FRONT_RIVETS) for i, z in enumerate(HOOP_Z[:2])]
        parts.append(barrel_hoop("h2", 0.72, rivets=FRONT_RIVETS[:1] + FRONT_RIVETS[2:]))
        parts.append(barrel_hoop("h3", BR_H - 0.12, extra=0.02, tilt=math.radians(10), rivets=(FRONT_RIVETS[3],)))
        parts += splinters("sp", (0.0, -0.33, 0.62), (0, -0.3, 1), 4, 0.1, 0.012, M("ScrapWood"))
        return finish(merge(parts, "Damaged"), 30.0)
    holder = empty("Destroyed")
    for q in range(4):
        idx = list(range(4 * q, 4 * q + 4))
        tops = {idx[1]: (0.6, 0.05)} if q % 2 == 0 else {idx[2]: (0.5, 0.06), idx[0]: (0.7, 0.04)}
        o = stave_set("Piece_%d" % q, idx, tops=tops)
        o = finish(o, 30.0, bbox_centre(o))
        C.parent(o, holder)
    for k, z in enumerate((HOOP_Z[1], HOOP_Z[2])):
        o = barrel_hoop("Piece_%d" % (4 + k), z, rivets=FRONT_RIVETS[:2])
        o = finish(o, 30.0, bbox_centre(o))
        C.parent(o, holder)
    return holder


def broken_barrel(name, variant):
    """027: A — лежащий остов (ось вдоль Y, к камере), B — стоящая нижняя половина, debris — россыпь."""
    RNG.seed({"A": 271, "B": 272, "debris": 273}[variant])
    parts = []
    if variant == "A":
        idx = [i for i in range(NS) if i not in (2, 3, 4, 5, 6)]
        parts.append(stave_set("st", idx, tops={1: (0.55, 0.06), 7: (0.7, 0.05), 12: (0.86, 0.04)}))
        parts += [barrel_hoop("h0", HOOP_Z[0], rivets=FRONT_RIVETS), barrel_hoop("h1", HOOP_Z[1], rivets=FRONT_RIVETS)]
        parts.append(barrel_hoop("h2", 0.62, extra=0.03, tilt=math.radians(9), rivets=FRONT_RIVETS[:2]))
        parts += splinters("sp", (0.0, 0.3, 0.6), (0.2, 0.5, 1), 3, 0.1, 0.012, M("ScrapWood"))
        o = merge(parts, name)
        # положить на бок: ось Z → −Y? Нет: ось бочки вдоль Y (открытый конец к камере −Y), пролом вверх
        o = place(o, (0, 0, 0), (math.radians(90), 0, 0))
        # после поворота: z_бочки → −y... сдвигаем так, чтобы центр по Y был 0, а низ обода на z = 0
        zs = [v.co.z for v in o.data.vertices]
        ys = [v.co.y for v in o.data.vertices]
        place(o, (0, -(min(ys) + max(ys)) / 2, -min(zs)))
        return finish(o, 30.0)
    if variant == "B":
        tops = {i: (RNG.uniform(0.28, 0.6), 0.06) for i in range(NS)}
        tops[11] = (0.22, 0.05)
        tops[4] = (0.62, 0.04)
        idx = [i for i in range(NS) if i not in (12, 13)]
        parts.append(stave_set("st", idx, tops=tops, tilt={11: 0.12, 14: 0.08, 5: 0.06}))
        parts.append(barrel_hoop("h0", HOOP_Z[0], rivets=FRONT_RIVETS))
        parts.append(barrel_hoop("h1", 0.26, extra=0.035, tilt=math.radians(-8), rivets=FRONT_RIVETS[:3]))
        parts += splinters("sp", (-0.1, -0.3, 0.35), (0, -0.2, 1), 4, 0.1, 0.012, M("ScrapWood"))
        return finish(merge(parts, name), 30.0)
    # debris: клёпки лёжа веером + сплющенный обруч
    for k in range(6):
        i = [0, 3, 5, 8, 10, 13][k]
        s = stave_set("s%d" % k, [i], tops={i: (RNG.uniform(0.45, 0.9), 0.05)})
        a = TAU * (i + 0.5) / NS
        # клёпку — на угол 0 (наружу +X), к нулю, затем Ry(−90°): наружная сторона вверх, длина вдоль −X
        s = place(s, (-BR_R1, 0, 0), (0, 0, -a))
        s = place(s, (0.5, 0, 0), (0, math.radians(-90), 0))
        yaw = RNG.uniform(-0.6, 0.6) + (0.0 if k % 2 else math.pi)
        s = place(s, (RNG.uniform(-0.45, 0.4), RNG.uniform(-0.3, 0.3), 0.0), (0, 0, yaw))
        zs = [v.co.z for v in s.data.vertices]
        place(s, (0, 0, -min(zs) + RNG.uniform(0.0, 0.04)))
        parts.append(s)
    hp = barrel_hoop("hp", 0.0, rivets=FRONT_RIVETS[:2])
    xform(hp, Matrix.Diagonal((1.25, 0.7, 1.0, 1.0)))
    place(hp, (0.1, 0.05, 0.03), (math.radians(8), 0, 0.4))
    parts.append(hp)
    return finish(ground(merge(parts, name), 0.004), 30.0)


# ----------------------------------------------------------------------------------------------------------------------
# хлам для гружёных вариантов (028 full, 029 loaded, 031 full, 030)
# ----------------------------------------------------------------------------------------------------------------------
def junk_heap(name, cx, hx, hy, z0, z1, n=12, seed=1, clip=None, cy=0.0):
    """Куча металлолома над прямоугольником (cx ± hx, ± hy): насыпь-купол (тёмная земля/окалина) до z1 − 0.08 и n деталей
    сверху (шестерни, трубы, пластины, бруски, кольца). clip(x, y) → True — точку не использовать."""
    rng = random.Random(seed)

    def mound(x, y):
        u, v = (x - cx) / hx, (y - cy) / hy
        f = max(0.0, (1.0 - u ** 4) * (1.0 - v ** 4))
        return z0 + (z1 - z0 - 0.09) * f * (0.82 + 0.18 * math.sin(3.1 * u + 1.3) * math.cos(2.3 * v))

    nx, ny = 8, 5
    bm = bmesh.new()
    grid = []
    for j in range(ny + 1):
        row = []
        for i in range(nx + 1):
            x = cx - hx + 2 * hx * i / nx
            y = cy - hy + 2 * hy * j / ny
            row.append(bm.verts.new((x, y, mound(x, y))))
        grid.append(row)
    for j in range(ny):
        for i in range(nx):
            bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        if f.normal.z < 0:
            f.normal_flip()
    base = mesh_obj(name + "_mound", bm, [M("Dirt")])
    C.uv_box(base, 1.0)
    parts = [base]
    kinds = ["gear", "block", "plate", "pipe", "block", "plate", "gear", "block", "ring", "plate", "block", "pipe", "block", "plate", "gear", "block"]
    for k in range(n):
        for _ in range(20):
            x = cx + rng.uniform(-0.8, 0.8) * hx
            y = cy + rng.uniform(-0.75, 0.75) * hy
            if clip is None or not clip(x, y):
                break
        z = mound(x, y)
        kind = kinds[k % len(kinds)]
        r = 0.0
        mat = M(rng.choice(("RustDark", "RustDark", "Rust", "Iron")))
        if kind == "gear":
            r = rng.uniform(0.11, 0.18)
            o = gear("%s_g%d" % (name, k), r, rng.choice((7, 8)), 0.04, mat, hole=r * 0.35)
            lift = r * 0.5
        elif kind == "pipe":
            L = rng.uniform(0.3, 0.55)
            r = rng.uniform(0.04, 0.065)
            o = ring("%s_p%d" % (name, k), r * 0.7, r, L, 'X', mat, 6)
            lift = r
        elif kind == "plate":
            o = box("%s_pl%d" % (name, k), (rng.uniform(0.26, 0.42), rng.uniform(0.16, 0.28), 0.014), mat, along='Z')
            lift = 0.03
        elif kind == "ring":
            o = ring("%s_r%d" % (name, k), 0.06, 0.085, 0.03, 'Y', mat, 12)
            lift = 0.05
        else:
            o = box("%s_bl%d" % (name, k), (rng.uniform(0.16, 0.3), rng.uniform(0.1, 0.18), rng.uniform(0.08, 0.14)), mat, along='Z', jitter=0.01)
            lift = 0.04
        place(o, (x, y, z + lift * rng.uniform(0.3, 0.8)), (rng.uniform(-1.2, 1.2), rng.uniform(-1.2, 1.2), rng.uniform(0, TAU)))
        parts.append(o)
    return parts


# ----------------------------------------------------------------------------------------------------------------------
# 024 большой транспортный ящик
# ----------------------------------------------------------------------------------------------------------------------
def shipping_crate(name):
    RNG.seed(24)
    W, H, D, e = 2.4, 1.4, 1.4, 0.12
    hx, hy = W / 2, D / 2
    parts = []

    def frame(key, size, loc, along):
        o = box(name + key, size, M("Rust"), along=along, jitter=0.001)
        bevel_apply(o, 0.01)
        parts.append(place(o, loc))

    for sx in (-1, 1):
        for sy in (-1, 1):
            frame("post%d%d" % (sx, sy), (e, e, H), (sx * (hx - e / 2), sy * (hy - e / 2), H / 2), 'Z')
    for sy in (-1, 1):
        for z in (e / 2, H - e / 2):
            frame("rx%d%d" % (sy, int(z * 10)), (W - 2 * e, e * 0.92, e * 0.92), (0, sy * (hy - e * 0.46), z), 'X')
    for sx in (-1, 1):
        for z in (e / 2, H - e / 2):
            frame("ry%d%d" % (sx, int(z * 10)), (e * 0.92, D - 2 * e, e * 0.92), (sx * (hx - e * 0.46), 0, z), 'Y')
    # стойки секций спереди и сзади
    bays = [(-hx + e, -0.4), (-0.4, 0.4), (0.4, hx - e)]
    for sy in (-1, 1):
        for x in (-0.4, 0.4):
            o = box(name + "mid", (0.1, 0.05, H - 2 * e * 0.92), M("Rust"), along='Z')
            parts.append(place(o, (x, sy * (hy - 0.025), H / 2)))
    # доски секций (горизонтальные, крашеные) спереди/сзади, на торцах и крышка
    t = 0.04
    ih = H - 2 * e * 0.92
    nb = 4
    for sy in (-1, 1):
        for bi, (x0, x1) in enumerate(bays):
            xa, xb = (x0 + 0.05 if bi > 0 else x0), (x1 - 0.05 if bi < 2 else x1)
            for i in range(nb):
                pw = ih / nb
                o = box(name + "pl", (xb - xa - 0.004, t, pw - 0.008), M("RustRed"), along='X', jitter=0.0015)
                if sy < 0:
                    bevel_apply(o, 0.005)
                parts.append(place(o, ((xa + xb) / 2, sy * (hy - 0.03 - t / 2), e * 0.92 + pw * (i + 0.5))))
    for sx in (-1, 1):
        for i in range(nb):
            pw = ih / nb
            o = box(name + "pe", (t, D - 2 * e, pw - 0.008), M("RustRed"), along='Y')
            parts.append(place(o, (sx * (hx - 0.03 - t / 2), 0, e * 0.92 + pw * (i + 0.5))))
    for i in range(5):
        pw = (D - 2 * e) / 5
        o = box(name + "pt", (W - 2 * e, pw - 0.008, t), M("RustRed"), along='X')
        parts.append(place(o, (0, -(D - 2 * e) / 2 + pw * (i + 0.5), H - 0.03 - t / 2)))
    # X-раскосы в крайних секциях фасада и на торцах
    for (x0, x1) in (bays[0], bays[2]):
        xa, xb = x0 + 0.02, x1 - 0.02
        for s in (-1, 1):
            p0 = (xa if s > 0 else xb, -hy + 0.012, e * 0.92 + 0.03)
            p1 = (xb if s > 0 else xa, -hy + 0.012, H - e * 0.92 - 0.03)
            parts.append(between(name + "xb", p0, p1, 0.055, 0.014, M("Rust"), up=(0, -1, 0), along='Z'))
    for sx in (-1, 1):
        for s in (-1, 1):
            p0 = (sx * (hx - 0.012), -hy + e if s > 0 else hy - e, e * 0.92 + 0.03)
            p1 = (sx * (hx - 0.012), hy - e if s > 0 else -hy + e, H - e * 0.92 - 0.03)
            parts.append(between(name + "xe", p0, p1, 0.055, 0.014, M("Rust"), up=(sx, 0, 0), along='Z'))
    # заклёпки по раме фасада
    for z in (e / 2, H - e / 2):
        for i in range(9):
            x = -hx + e + 0.12 + (W - 2 * e - 0.24) * i / 8
            parts.append(stud(name + "rv", (x, -hy - 0.001, z), (0, -1, 0), r=0.015, h=0.011))
    for sx in (-1, 1):
        for i in range(5):
            parts.append(stud(name + "rv", (sx * (hx - e / 2), -hy - 0.001, 0.2 + 0.25 * i), (0, -1, 0), r=0.015, h=0.011))
    for x in (-0.4, 0.4):
        for i in range(4):
            parts.append(stud(name + "rv", (x, -hy - 0.001, 0.3 + 0.27 * i), (0, -1, 0), r=0.013, h=0.01))
    parts.append(decal_quad(name + "_crown", 0.56, 0.56, (0.0, -hy + 0.03 - 0.006, 0.72), "Crown_Gold"))
    # кольцо-ручка на левом торце и скоба
    handle = C.add_torus(name + "_handle", 0.13, 0.018, loc=(0, 0, 0), rot=(0, math.pi / 2, 0), segs=14, ring=6)
    C.apply_transforms(handle, rotation=True)
    handle.data.materials.append(M("Iron"))
    C.uv_box(handle, 1.0)
    parts.append(place(handle, (-hx - 0.05, 0.0, 0.62), (0.0, math.radians(-25), 0.0)))
    br = box(name + "_hb", (0.03, 0.16, 0.08), M("Iron"), along='Z')
    parts.append(place(br, (-hx - 0.012, 0.0, 0.76)))
    return finish(merge(parts, name), 30.0)


# ----------------------------------------------------------------------------------------------------------------------
# 026 железная бочка
# ----------------------------------------------------------------------------------------------------------------------
MB_R, MB_H = 0.29, 0.9
MB_PROFILE = [(0.0, 0.012), (0.268, 0.012), (0.268, 0.0), (0.285, 0.0), (0.3, 0.018), (0.3, 0.035), (MB_R, 0.05),
              (MB_R, 0.15), (MB_R, 0.285), (0.302, 0.295), (0.302, 0.315), (MB_R, 0.325), (MB_R, 0.45), (MB_R, 0.575),
              (0.302, 0.585), (0.302, 0.605), (MB_R, 0.615), (MB_R, 0.75), (MB_R, 0.85), (0.3, 0.865), (0.3, 0.885),
              (0.285, 0.9), (0.268, 0.9), (0.268, 0.885), (0.0, 0.885)]


def metal_barrel(name, dented=False):
    RNG.seed(26 if not dented else 261)
    segs = 28 if dented else 20
    prof = MB_PROFILE
    if dented:   # гуще по высоте на прямых участках, чтобы вмятины были плавными
        prof = []
        for (r0, z0), (r1, z1) in zip(MB_PROFILE, MB_PROFILE[1:]):
            prof.append((r0, z0))
            if abs(r0 - MB_R) < 1e-6 and abs(r1 - MB_R) < 1e-6 and z1 - z0 > 0.08:
                k = int((z1 - z0) / 0.05)
                prof += [(MB_R, z0 + (z1 - z0) * i / (k + 1)) for i in range(1, k + 1)]
        prof.append(MB_PROFILE[-1])
    body = lathe(name + "_body", prof, segs, M("RustRed"), uv_scale=1.0)
    parts = [body]
    bung = cyl(name + "_bung", 0.035, 0.03, 'Z', M("Iron"), segs=8)
    parts.append(place(bung, (0.15, 0.07, 0.895)))
    bung2 = cyl(name + "_bung2", 0.02, 0.02, 'Z', M("Iron"), segs=6)
    parts.append(place(bung2, (-0.16, 0.05, 0.89)))
    decal = decal_cyl(name + "_crown", MB_R + 0.004, 0.45, 0.3, 0.22, "Crown_Pale")
    parts.append(decal)
    if dented:
        dents = [((-0.2, -0.22, 0.52), 0.13, 0.06), ((0.27, -0.05, 0.2), 0.11, 0.045), ((-0.05, 0.28, 0.7), 0.14, 0.05), ((0.12, -0.26, 0.78), 0.1, 0.035)]
        for o in (body, decal):
            for v in o.data.vertices:
                p = v.co
                for (c, rad, depth) in dents:
                    d = (p - Vector(c)).length
                    if d < rad:
                        f = 0.5 + 0.5 * math.cos(math.pi * d / rad)
                        radial = Vector((p.x, p.y, 0.0))
                        if radial.length > 1e-6:
                            p -= radial.normalized() * depth * f
                # перекошенная верхняя кромка
                if o is body and p.z > 0.84:
                    p.z -= 0.035 * max(0.0, p.x / MB_R) + 0.012 * max(0.0, -p.y / MB_R)
    o = merge(parts, name)
    return finish(o, 35.0)


# ----------------------------------------------------------------------------------------------------------------------
# колёса, тележки, корзина, вагонетка, тачка
# ----------------------------------------------------------------------------------------------------------------------
def spoked_wheel(name, r, width, spokes, mat_rim, mat_spoke, segs=16, hub_r=None, rim_t=None, studs=True):
    """Колесо со спицами, ось вдоль Y, центр в нуле: обод, ступица, спицы; studs — болты ступицы (−Y)."""
    rim_t = rim_t or r * 0.12
    hub_r = hub_r or r * 0.2
    parts = [ring(name + "_rim", r - rim_t, r, width, 'Y', mat_rim, segs)]
    parts.append(cyl(name + "_hub", hub_r, width * 1.5, 'Y', mat_rim, segs=8))
    for k in range(spokes):
        a = TAU * k / spokes + 0.2
        p0 = (hub_r * 0.8 * math.cos(a), 0.0, hub_r * 0.8 * math.sin(a))
        p1 = ((r - rim_t * 0.6) * math.cos(a), 0.0, (r - rim_t * 0.6) * math.sin(a))
        parts.append(between(name + "_sp%d" % k, p0, p1, width * 0.45, width * 0.45, mat_spoke, up=(0, 1, 0), along='X'))
    for k in range(6 if studs else 0):
        a = TAU * k / 6
        parts.append(stud(name + "_rv", (hub_r * 0.6 * math.cos(a), -width * 0.75, hub_r * 0.6 * math.sin(a)), (0, -1, 0), r=0.008, h=0.006))
    return merge(parts, name)


CART_L, CART_D, CART_BED, CART_SIDE, CART_WR = 1.6, 0.9, 0.42, 0.42, 0.3
CART_AX = CART_WR + 0.012   # ось: железная шина r+0.012 касается пола


def junk_cart_parts(name, missing_wheel=None):
    """Тележка 029: кузов 1.6 × 0.9 (днище на 0.42, борта 0.42), 4 колеса r=0.3 на осях z=0.3 при x=±0.5, дышло в −X."""
    RNG.seed(29)
    L, D, zb, hs = CART_L, CART_D, CART_BED, CART_SIDE
    hx, hy = L / 2, D / 2
    parts = []
    # днище и подрамник
    for i in range(5):
        pw = D / 5
        o = box(name + "fl", (L - 0.04, pw - 0.006, 0.035), M("ScrapWood"), along='X')
        parts.append(place(o, (0, -hy + pw * (i + 0.5), zb + 0.0175)))
    for y in (-0.32, 0.32):
        o = box(name + "sill", (L + 0.05, 0.08, 0.09), M("ScrapWood"), along='X')
        bevel_apply(o, 0.01)
        parts.append(place(o, (0, y, zb - 0.045)))
    # борта: 3 доски по высоте
    pw = hs / 3
    for sy in (-1, 1):
        for i in range(3):
            o = box(name + "sd", (L, 0.035, pw - 0.008), M("ScrapWood"), along='X', jitter=0.002)
            if sy < 0:
                bevel_apply(o, 0.005)
            parts.append(place(o, (0, sy * (hy - 0.0175), zb + 0.035 + pw * (i + 0.5))))
    for sx in (-1, 1):
        for i in range(3):
            o = box(name + "en", (0.035, D - 0.07, pw - 0.008), M("ScrapWood"), along='Y')
            parts.append(place(o, (sx * (hx - 0.0175), 0, zb + 0.035 + pw * (i + 0.5))))
    # стойки (выше бортов на 4 см) и верхняя обвязка
    for sy in (-1, 1):
        for x in (-hx + 0.04, -0.27, 0.27, hx - 0.04):
            o = box(name + "po", (0.07, 0.06, hs + 0.12), M("ScrapWood"), along='Z')
            if sy < 0:
                bevel_apply(o, 0.008)
            parts.append(place(o, (x, sy * (hy + 0.03), zb - 0.04 + (hs + 0.12) / 2)))
        o = box(name + "cap", (L + 0.04, 0.09, 0.05), M("ScrapWood"), along='X')
        if sy < 0:
            bevel_apply(o, 0.008)
        parts.append(place(o, (0, sy * (hy + 0.01), zb + 0.035 + hs + 0.02)))
    # железные уголки на фасаде с заклёпками
    for x in (-hx + 0.04, hx - 0.04):
        for z in (zb + 0.12, zb + hs - 0.05):
            o = box(name + "ir", (0.16, 0.008, 0.08), M("Iron"), along='Z')
            parts.append(place(o, (x - math.copysign(0.03, x), -hy - 0.066, z)))
            for dx in (-0.05, 0.05):
                parts.append(stud(name + "rv", (x - math.copysign(0.03, x) + dx, -hy - 0.07, z), (0, -1, 0)))
    for x in (-0.27, 0.27):
        for z in (zb + 0.1, zb + 0.3):
            parts.append(stud(name + "nl", (x, -hy - 0.061, z), (0, -1, 0), r=0.01, h=0.007))
    # оси, колёса
    wheels = []
    for wi, x in enumerate((-0.5, 0.5)):
        ax = cyl(name + "ax", 0.03, D + 0.3, 'Y', M("Iron"), segs=8)
        parts.append(place(ax, (x, 0, CART_AX)))
        for sy in (-1, 1):
            if missing_wheel == (wi, sy):
                continue
            front = sy < 0            # задние колёса почти не видны из-за кузова — проще
            w = spoked_wheel(name + "wh", CART_WR, 0.06, 8 if front else 6, M("ScrapWood"), M("ScrapWood"), segs=14 if front else 10, studs=front)
            iron = ring(name + "tyre", CART_WR, CART_WR + 0.012, 0.065, 'Y', M("Iron"), 14 if front else 10, outer_only=True)
            w = merge([w, iron], name + "wheel")
            wheels.append(place(w, (x, sy * (hy + 0.1), CART_AX)))
    parts += wheels
    # дышло влево
    parts.append(between(name + "shaft", (-hx + 0.05, 0, zb - 0.06), (-0.92, 0.0, zb - 0.02), 0.07, 0.06, M("ScrapWood"), up=(0, 0, 1)))
    for y in (-0.12, 0.12):
        parts.append(between(name + "fork", (-hx + 0.15, y * 2.4, zb - 0.07), (-0.8, y * 0.3, zb - 0.04), 0.05, 0.05, M("ScrapWood"), up=(0, 0, 1)))
    ring_h = C.add_torus(name + "_eye", 0.05, 0.012, loc=(0, 0, 0), rot=(math.pi / 2, 0, 0), segs=10, ring=5)
    C.apply_transforms(ring_h, rotation=True)
    ring_h.data.materials.append(M("Iron"))
    C.uv_box(ring_h, 1.0)
    parts.append(place(ring_h, (-0.95, 0, zb - 0.02)))
    return parts


def junk_cart(name, loaded=False):
    parts = junk_cart_parts(name)
    if loaded:
        parts += junk_heap(name + "_junk", 0.0, CART_L / 2 - 0.08, CART_D / 2 - 0.08, CART_BED + 0.2, 1.1, n=12, seed=291)
    return finish(merge(parts, name), 30.0)


def overturned_cart(name):
    """030: тележка вверх дном, наклонена на 12° (правый конец приподнят на хламе), без одного колеса; высыпанный хлам."""
    parts = junk_cart_parts(name + "_c", missing_wheel=(1, -1))
    cart = merge(parts, name + "_cart")
    top = CART_BED + 0.035 + CART_SIDE + 0.045
    # переворот вокруг X (верх бортов → пол), затем крен по Y
    xform(cart, Matrix.Translation((0, 0, -top)))
    xform(cart, Matrix.Rotation(math.pi, 4, 'Y'))   # вверх дном; фасад остаётся в −Y
    xform(cart, Matrix.Rotation(math.radians(-8), 4, 'Y'))
    zs = [v.co.z for v in cart.data.vertices]
    xform(cart, Matrix.Translation((0, 0, -min(zs) - 0.02)))
    out = [cart]
    out += junk_heap(name + "_spill", 0.3, 0.55, 0.3, 0.0, 0.3, n=6, seed=301, cy=-0.62)
    loose = spoked_wheel(name + "lw", CART_WR, 0.06, 6, M("ScrapWood"), M("ScrapWood"), segs=12, studs=False)
    out.append(place(loose, (0.62, -0.62, 0.035), (math.radians(84), 0, math.radians(15))))
    return finish(merge(out, name), 30.0)


def scrap_basket(name, full=False):
    """028: сетчатая корзина 1.0 × 0.7 (глубина) × 0.8 на 4 колёсиках."""
    RNG.seed(28)
    W, D, H, zb = 1.0, 0.7, 0.8, 0.17
    hx, hy = W / 2, D / 2
    parts = []
    a = 0.03  # уголок
    # рама: 4 стойки, верхний и нижний пояса
    for sx in (-1, 1):
        for sy in (-1, 1):
            o = box(name + "po", (a, a, H - zb), M("Rust"), along='Z')
            parts.append(place(o, (sx * (hx - a / 2), sy * (hy - a / 2), zb + (H - zb) / 2)))
    for z, t in ((zb + a / 2, a), (H - 0.02, 0.04)):
        for sy in (-1, 1):
            o = box(name + "rx", (W, a, t), M("Rust"), along='X')
            parts.append(place(o, (0, sy * (hy - a / 2), z)))
        for sx in (-1, 1):
            o = box(name + "ry", (a, D - 2 * a, t), M("Rust"), along='Y')
            parts.append(place(o, (sx * (hx - a / 2), 0, z)))
    # средний пояс спереди/сзади
    for sy in (-1, 1):
        o = box(name + "mid", (W - 2 * a, 0.02, 0.025), M("Rust"), along='X')
        parts.append(place(o, (0, sy * (hy - 0.01), zb + (H - zb) * 0.5)))
    # дно
    o = box(name + "bot", (W - 0.02, D - 0.02, 0.012), M("Rust"), along='Z')
    parts.append(place(o, (0, 0, zb + 0.006)))
    # ромбическая сетка: грань в плоскости (u, z), u вдоль X (фасад/зад) или Y (бока)
    step = 0.13
    z0, z1 = zb + a, H - 0.04
    wire = 0.009

    def lattice(u0, u1, plane_pos, axis):
        """Две серии диагоналей u = c ± (z − z0) в прямоугольнике [u0, u1] × [z0, z1], отсечённые по u."""
        out = []
        hz = z1 - z0
        for s in (1, -1):
            c = (u0 - hz if s > 0 else u0) + step * 0.5
            c_end = u1 if s > 0 else u1 + hz
            while c < c_end:
                ua, ub = c, c + s * hz
                t0, t1 = 0.0, 1.0
                for bound, sign in ((u0, 1), (u1, -1)):
                    fa, fb = sign * (ua - bound), sign * (ub - bound)
                    if fa < 0 and fb < 0:
                        t0, t1 = 1.0, 0.0
                        break
                    if fa < 0:
                        t0 = max(t0, fa / (fa - fb))
                    elif fb < 0:
                        t1 = min(t1, fa / (fa - fb))
                if t1 - t0 > 0.05:
                    pa, pb = ua + (ub - ua) * t0, ua + (ub - ua) * t1
                    qa, qb = z0 + hz * t0, z0 + hz * t1
                    if axis == 'X':
                        p0, p1, upv = (pa, plane_pos, qa), (pb, plane_pos, qb), (0, 1, 0)
                    else:
                        p0, p1, upv = (plane_pos, pa, qa), (plane_pos, pb, qb), (1, 0, 0)
                    out.append(between(name + "w", p0, p1, wire, wire, M("Rust"), up=upv, along='X'))
                c += step
        return out

    for sy in (-1, 1):
        parts += lattice(-hx + a, hx - a, sy * (hy - 0.012), 'X')
    for sx in (-1, 1):
        parts += lattice(-hy + a, hy - a, sx * (hx - 0.012), 'Y')
    # колёсики
    for sx in (-1, 1):
        for sy in (-1, 1):
            cx, cy = sx * (hx - 0.08), sy * (hy - 0.09)
            wh = cyl(name + "wh", 0.065, 0.035, 'Y', M("Rubber"), segs=12)
            parts.append(place(wh, (cx, cy, 0.065)))
            hubc = cyl(name + "hb", 0.025, 0.045, 'Y', M("Iron"), segs=6)
            parts.append(place(hubc, (cx, cy, 0.065)))
            for dy in (-1, 1):
                f = box(name + "fk", (0.03, 0.008, 0.1), M("Iron"), along='Z')
                parts.append(place(f, (cx, cy + dy * 0.026, 0.1)))
            pl = box(name + "fp", (0.07, 0.07, 0.012), M("Iron"), along='Z')
            parts.append(place(pl, (cx, cy, 0.155)))
            st = cyl(name + "stem", 0.012, 0.03, 'Z', M("Iron"), segs=6)
            parts.append(place(st, (cx, cy, 0.165)))
    for sx in (-1, 1):
        for z in (zb + a / 2, H - 0.02):
            parts.append(stud(name + "rv", (sx * (hx - a / 2), -hy - 0.001, z), (0, -1, 0), r=0.01, h=0.007))
    if full:
        parts += junk_heap(name + "_junk", 0.0, hx - 0.06, hy - 0.06, zb + 0.15, H + 0.3, n=15, seed=281)
    return finish(merge(parts, name), 30.0)


def rail_wagon(name, full=False):
    """031: вагонетка — трапециевидный кузов (низ 1.8 × 0.9 на z=0.42, верх 2.2 × 1.1 на z=1.12), рёбра, обвязка,
    латунная корона, 4 колеса ⌀0.36 с ребордами, буфера."""
    RNG.seed(31)
    b_hx, b_hy, t_hx, t_hy, zb, zt = 0.9, 0.45, 1.1, 0.55, 0.42, 1.12
    parts = []
    bm = bmesh.new()
    bot = [bm.verts.new(p) for p in ((-b_hx, -b_hy, zb), (b_hx, -b_hy, zb), (b_hx, b_hy, zb), (-b_hx, b_hy, zb))]
    top = [bm.verts.new(p) for p in ((-t_hx, -t_hy, zt), (t_hx, -t_hy, zt), (t_hx, t_hy, zt), (-t_hx, t_hy, zt))]
    bm.faces.new(list(reversed(bot)))
    for i in range(4):
        j = (i + 1) % 4
        bm.faces.new((bot[i], bot[j], top[j], top[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    tub = mesh_obj(name + "_tub", bm, [M("RustDark")])
    solidify_apply(tub, 0.03, -1.0)
    C.uv_box(tub, 1.0, 'Z')
    parts.append(tub)
    # верхняя обвязка
    for sy in (-1, 1):
        o = box(name + "rim", (2 * t_hx + 0.08, 0.07, 0.07), M("RustDark"), along='X')
        bevel_apply(o, 0.008)
        parts.append(place(o, (0, sy * (t_hy + 0.005), zt)))
    for sx in (-1, 1):
        o = box(name + "rim", (0.07, 2 * t_hy + 0.08, 0.07), M("RustDark"), along='Y')
        bevel_apply(o, 0.008)
        parts.append(place(o, (sx * (t_hx + 0.005), 0, zt)))
    # нижний пояс
    for sy in (-1, 1):
        o = box(name + "brim", (2 * b_hx + 0.06, 0.06, 0.06), M("RustDark"), along='X')
        parts.append(place(o, (0, sy * (b_hy + 0.01), zb + 0.03)))
    # рёбра фасада/зада (по наклонной стенке)
    for sy in (-1, 1):
        for x in (-0.85, -0.42, 0.42, 0.85):
            xt = x * t_hx / b_hx if abs(x) > 0.8 else x
            p0 = (x, sy * (b_hy + 0.02), zb + 0.05)
            p1 = (xt, sy * (t_hy + 0.02), zt - 0.04)
            parts.append(between(name + "rib", p0, p1, 0.07, 0.022, M("RustDark"), up=(0, sy, 0.0), along='Z'))
            if sy < 0:
                for f in (0.2, 0.5, 0.8):
                    p = Vector(p0).lerp(Vector(p1), f)
                    parts.append(stud(name + "rv", (p.x, p.y - 0.012, p.z), (0, -1, 0.14), r=0.013, h=0.01))
    for x in [(-1.0 + 0.2 * i) for i in range(11)]:
        parts.append(stud(name + "rv", (x, -t_hy - 0.04, zt), (0, -1, 0), r=0.012, h=0.009))
    # корона на наклонной передней стенке: строим в нуле, наклоняем как стенку, ставим на её плоскость
    slope = math.atan2(t_hy - b_hy, zt - zb)
    crown = merge(crown_relief(name + "_crown", 0.46, 0.42, 0.022, M("Brass"), (0.0, 0.0, 0.0)), name + "_crown")
    xform(crown, Matrix.Rotation(slope, 4, 'X'))
    zc = 0.56
    xform(crown, Matrix.Translation((0.0, -(b_hy + (t_hy - b_hy) * (zc - zb) / (zt - zb)) - 0.002, zc)))
    parts.append(crown)
    # рама и колёса
    for sy in (-1, 1):
        o = box(name + "fr", (1.9, 0.08, 0.1), M("RustDark"), along='X')
        parts.append(place(o, (0, sy * 0.36, zb - 0.05)))
    for x in (-0.6, 0.6):
        ax = cyl(name + "ax", 0.03, 1.04, 'Y', M("Iron"), segs=8)
        parts.append(place(ax, (x, 0, 0.2)))
        for sy in (-1, 1):
            wprof = [(0.0, -0.05), (0.2, -0.05), (0.2, -0.03), (0.18, -0.02), (0.18, 0.035), (0.0, 0.035)]
            w = lathe(name + "wh", wprof, 12, M("Iron"), axis='Y')
            if sy < 0:   # реборда (−Y в профиле) — внутрь, к середине оси
                xform(w, Matrix.Diagonal((1, -1, 1, 1)))
                for p in w.data.polygons:
                    p.flip()
            parts.append(place(w, (x, sy * 0.44, 0.2)))
            bb = box(name + "bb", (0.14, 0.05, 0.14), M("RustDark"), along='Z')
            parts.append(place(bb, (x, sy * 0.36, 0.27)))
    for sx in (-1, 1):
        bf = cyl(name + "buf", 0.06, 0.12, 'X', M("Iron"), segs=10)
        parts.append(place(bf, (sx * 1.03, 0, zb - 0.02)))
        bp = cyl(name + "bufp", 0.085, 0.02, 'X', M("Iron"), segs=10)
        parts.append(place(bp, (sx * 1.1, 0, zb - 0.02)))
    if full:
        parts += junk_heap(name + "_junk", 0.0, t_hx - 0.1, t_hy - 0.08, zt - 0.3, 1.42, n=18, seed=311)
    return finish(merge(parts, name), 30.0)


def wheelbarrow(name):
    """032: ржавая тачка; колесо спереди (−X), ручки назад (+X)."""
    RNG.seed(32)
    parts = []
    # корыто: низ 0.5 × 0.36 на z=0.3, верх 0.86 × 0.62 на z=0.62; перед (−X) сильнее наклонён
    bmx0, bmx1, bhy = -0.2, 0.28, 0.18
    tmx0, tmx1, thy, zb, zt = -0.48, 0.38, 0.31, 0.3, 0.62
    bm = bmesh.new()
    rows = []
    for k in range(4):
        f = k / 3
        z = zb + (zt - zb) * f
        x0 = bmx0 + (tmx0 - bmx0) * f ** 0.8
        x1 = bmx1 + (tmx1 - bmx1) * f
        hy = bhy + (thy - bhy) * f ** 0.9
        rows.append([bm.verts.new(p) for p in ((x0, -hy, z), (x0 * 0.3 + x1 * 0.7, -hy, z), (x1, -hy, z), (x1, hy, z), (x0 * 0.3 + x1 * 0.7, hy, z), (x0, hy, z))])
    bm.faces.new(list(reversed(rows[0])))
    for a_, b_ in zip(rows, rows[1:]):
        for i in range(6):
            j = (i + 1) % 6
            bm.faces.new((a_[i], a_[j], b_[j], b_[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    tray = mesh_obj(name + "_tray", bm, [M("RustRed")])
    # вмятины и коробление
    for v in tray.data.vertices:
        if v.co.z > zb + 0.01:
            v.co.x += RNG.uniform(-0.012, 0.012)
            v.co.y += RNG.uniform(-0.012, 0.012)
            v.co.z += RNG.uniform(-0.01, 0.01)
    solidify_apply(tray, 0.012, -1.0)
    C.uv_box(tray, 1.0, 'Z')
    parts.append(tray)
    rim_pts = [(tmx0, -thy, zt), (tmx1, -thy, zt), (tmx1, thy, zt), (tmx0, thy, zt)]
    parts.append(tube_path(name + "_rim", rim_pts, 0.014, M("RustRed"), sides=6, closed=True))
    # ручки: от оси колеса под корытом назад и вверх; правая (y>0) погнута
    for sy in (-1, 1):
        pts = [(-0.55, sy * 0.1, 0.18), (-0.3, sy * 0.2, 0.26), (0.1, sy * 0.24, 0.27), (0.45, sy * 0.26, 0.36), (0.72, sy * 0.28, 0.5)]
        if sy > 0:
            pts[-1] = (0.66, 0.36, 0.56)
            pts[-2] = (0.44, 0.28, 0.38)
        parts.append(tube_path(name + "_hd%d" % sy, pts, 0.018, M("Rust"), sides=8))
        grip = cyl(name + "_grip", 0.024, 0.13, 'X', M("Rubber"), segs=8)
        g = Vector(pts[-1]) - Vector(pts[-2])
        rot_y = -math.atan2(g.z, g.x)
        rot_z = math.atan2(g.y, math.hypot(g.x, g.z))
        parts.append(place(grip, tuple(Vector(pts[-1]) + g.normalized() * 0.04), (0, rot_y, rot_z)))
        # нога
        parts.append(tube_path(name + "_leg%d" % sy, [(0.22, sy * 0.25, 0.3), (0.26, sy * 0.25, 0.14), (0.3, sy * 0.27, 0.0)], 0.015, M("Rust"), sides=6))
        # подкос к корыту
        parts.append(tube_path(name + "_br%d" % sy, [(-0.2, sy * 0.21, 0.26), (-0.36, sy * 0.24, 0.5)], 0.01, M("Rust"), sides=5))
    # колесо
    w = spoked_wheel(name + "_wheel", 0.18, 0.05, 6, M("Rust"), M("Rust"), segs=14)
    tyre = ring(name + "_tyre", 0.18, 0.2, 0.06, 'Y', M("Rubber"), 14)
    parts.append(place(merge([w, tyre], name + "_w"), (-0.55, 0, 0.2)))
    ax = cyl(name + "_ax", 0.012, 0.24, 'Y', M("Iron"), segs=6)
    parts.append(place(ax, (-0.55, 0, 0.2)))
    return finish(ground(merge(parts, name)), 30.0)


# ----------------------------------------------------------------------------------------------------------------------
# 033 поддон, 034 лист, 035 профлист, 036/037 брусья, 038 трубы, 039/040 бухты
# ----------------------------------------------------------------------------------------------------------------------
def pallet(name):
    RNG.seed(33)
    parts = []
    tb = 0.022
    for y in (-0.44, 0.0, 0.44):          # нижние доски вдоль X
        o = box(name + "bb", (1.2, 0.12, tb), M("ScrapWoodPale"), along='X', jitter=0.0015)
        bevel_apply(o, 0.004)
        parts.append(place(o, (0, y, tb / 2)))
    for x in (-0.54, 0.0, 0.54):
        for y in (-0.44, 0.0, 0.44):      # шашки
            o = box(name + "blk", (0.12, 0.12, 0.078), M("ScrapWoodPale"), along='Z', jitter=0.002)
            bevel_apply(o, 0.006)
            parts.append(place(o, (x, y, tb + 0.039)))
        o = box(name + "st", (0.12, 1.0, tb), M("ScrapWoodPale"), along='Y', jitter=0.0015)   # поперечины
        bevel_apply(o, 0.004)
        parts.append(place(o, (x, 0, tb + 0.078 + tb / 2)))
    for i, y in enumerate((-0.44, -0.22, 0.0, 0.22, 0.44)):    # настил вдоль X
        o = box(name + "top%d" % i, (1.2, 0.12 if i % 2 == 0 else 0.1, tb), M("ScrapWoodPale"), along='X', jitter=0.0015,
                broken=(0, 1, 0.06) if i == 3 else None, cuts=2 if i == 3 else 0)
        bevel_apply(o, 0.004)
        parts.append(place(o, (0, y, 2 * tb + 0.078 + tb / 2)))
        for x in (-0.54, 0.0, 0.54):
            if i == 3 and x > 0.3:
                continue
            for dy in (-0.03, 0.03):
                parts.append(stud(name + "n", (x + RNG.uniform(-0.02, 0.02), y + dy, 3 * tb + 0.078 + 0.0005), (0, 0, 1), r=0.007, h=0.004))
    return finish(merge(parts, name), 30.0)


def metal_plate(name, variant="A", mat="Rust", T=0.03, W=1.5, D=1.0, z0=0.0, seed=34):
    """034: клёпаный лист W × T × D, лёгкое коробление; A — накладка-полоса поперёк, B — срезанный угол и отогнутая
    кромка. Лист лежит z ∈ [z0, z0+T] (центр основания в нуле)."""
    RNG.seed(seed)
    nx, ny = 6, 4
    bm = bmesh.new()
    pts = []
    for j in range(ny + 1):
        for i in range(nx + 1):
            x = -W / 2 + W * i / nx
            y = -D / 2 + D * j / ny
            pts.append((x, y))
    if variant == "B":
        # срезанный угол (+X, −Y) — выпуклый многоугольник по контуру
        poly = [(-W / 2, -D / 2), (W / 2 - 0.35, -D / 2), (W / 2, -D / 2 + 0.28), (W / 2, D / 2), (-W / 2, D / 2)]
    else:
        poly = [(-W / 2, -D / 2), (W / 2, -D / 2), (W / 2, D / 2), (-W / 2, D / 2)]
    # сетка через bisect: делаем плиту-многоугольник и режем её плоскостями
    top = [bm.verts.new((x, y, T)) for x, y in poly]
    bot = [bm.verts.new((x, y, 0.0)) for x, y in poly]
    bm.faces.new(top)
    bm.faces.new(list(reversed(bot)))
    n = len(poly)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((bot[i], bot[j], top[j], top[i]))
    for i in range(1, nx):
        geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
        bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(-W / 2 + W * i / nx, 0, 0), plane_no=(1, 0, 0))
    for j in range(1, ny):
        geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
        bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(0, -D / 2 + D * j / ny, 0), plane_no=(0, 1, 0))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = mesh_obj(name + "_plate", bm, [M(mat)])
    # коробление: пологие волны + у B отогнутая кромка (−X) вверх
    for v in o.data.vertices:
        x, y = v.co.x, v.co.y
        v.co.z += 0.006 * math.sin(2.1 * x + 0.7) * math.cos(2.7 * y + 0.3)
        if variant == "B" and x < -W / 2 + 0.25:
            f = (-W / 2 + 0.25 - x) / 0.25
            v.co.z += 0.06 * f * f
    bevel_apply(o, 0.004)
    C.uv_box(o, 1.0, 'Y')
    parts = [o]

    def surf_z(x, y):
        z = T + 0.006 * math.sin(2.1 * x + 0.7) * math.cos(2.7 * y + 0.3)
        if variant == "B" and x < -W / 2 + 0.25:
            f = (-W / 2 + 0.25 - x) / 0.25
            z += 0.06 * f * f
        return z

    inset = 0.05
    edge_pts = []
    for i in range(9):
        x = -W / 2 + inset + (W - 2 * inset) * i / 8
        edge_pts += [(x, -D / 2 + inset), (x, D / 2 - inset)]
    for j in range(1, 5):
        y = -D / 2 + inset + (D - 2 * inset) * j / 5
        edge_pts += [(-W / 2 + inset, y), (W / 2 - inset, y)]
    for (x, y) in edge_pts:
        if variant == "B" and x > W / 2 - 0.4 and y < -D / 2 + 0.33:
            continue
        parts.append(stud(name + "rv", (x, y, surf_z(x, y)), (0, 0, 1), r=0.014, h=0.008))
    if variant == "A":
        st = box(name + "_strap", (0.14, D - 0.02, 0.008), M(mat), along='Y')
        for v in st.data.vertices:
            v.co.z += 0.006 * math.sin(2.1 * 0.25 + 0.7) * math.cos(2.7 * v.co.y + 0.3)
        parts.append(place(st, (0.25, 0, T + 0.004)))
        for j in range(6):
            y = -D / 2 + 0.08 + (D - 0.16) * j / 5
            for dx in (-0.04, 0.04):
                parts.append(stud(name + "rs", (0.25 + dx, y, surf_z(0.25, y) + 0.008), (0, 0, 1), r=0.012, h=0.007))
    o = merge(parts, name)
    if z0:
        place(o, (0, 0, z0))
    return o


def metal_plate_stack(name):
    """034 stack: 6 листов (верхний — B с отогнутой кромкой) со сдвигами и поворотами."""
    RNG.seed(342)
    parts = []
    for k in range(6):
        p = metal_plate(name + "_%d" % k, "B" if k == 5 else "A", "RustDark" if k % 2 else "Rust", seed=340 + k)
        place(p, (RNG.uniform(-0.05, 0.05), RNG.uniform(-0.04, 0.04), 0.0), (0, 0, RNG.uniform(-0.08, 0.08)))
        place(p, (0, 0, 0.04 * k))
        parts.append(p)
    return finish(merge(parts, name), 30.0)


def corrugated(name, mat="Rust", bend=0.0, seed=35, W=2.0, D=1.0, per_wave=6, rows=2, thick=0.004, rivets=True):
    """035: профлист W × D, волна 0.125 м вдоль X (гребни идут вдоль Y — профиль виден спереди), амплитуда 0.02;
    bend — подъём угла (+X, −Y) в метрах (погнутый край)."""
    RNG.seed(seed)
    period, amp = 0.125, 0.02
    nx = int(round(W / period)) * per_wave
    bm = bmesh.new()
    grid = []
    for j in range(rows + 1):
        y = -D / 2 + D * j / rows
        row = []
        for i in range(nx + 1):
            x = -W / 2 + W * i / nx
            z = amp + amp * math.sin(TAU * (x + W / 2) / period)
            # изгиб угла и лёгкая волна листа
            u, v = (x + W / 2) / W, (y + D / 2) / D
            z += bend * max(0.0, u - 0.55) ** 2 / 0.2025 * (1.0 - v) ** 1.5
            z += 0.008 * math.sin(3.0 * u + 1.0) * math.sin(2.0 * v + 0.4)
            row.append(bm.verts.new((x, y, z)))
        grid.append(row)
    for j in range(rows):
        for i in range(nx):
            bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        if f.normal.z < 0:
            f.normal_flip()
    o = mesh_obj(name + "_sheet", bm, [M(mat)])
    C.uv_box(o, 1.0, 'Y')
    solidify_apply(o, thick, -1.0)
    parts = [o]
    if rivets:
        for y in (-D / 2 + 0.04, D / 2 - 0.04):
            for k in range(int(W / period)):
                x = -W / 2 + period * (k + 0.25)    # на гребнях: sin = 1 при (x + W/2)/period = k + 0.25
                u, v = (x + W / 2) / W, (y + D / 2) / D
                z = 2 * amp + bend * max(0.0, u - 0.55) ** 2 / 0.2025 * (1.0 - v) ** 1.5 + 0.008 * math.sin(3.0 * u + 1.0) * math.sin(2.0 * v + 0.4)
                if k % 2 == 0:
                    parts.append(stud(name + "rv", (x, y, z), (0, 0, 1), r=0.011, h=0.007))
    return merge(parts, name)


def corrugated_stack(name):
    parts = []
    z = 0.0
    for k in range(5):
        s = corrugated(name + "_%d" % k, "RustRed" if k in (1, 3) else "Rust", bend=0.0, seed=350 + k, per_wave=4, rows=1, thick=0.004, rivets=False)
        place(s, (RNG.uniform(-0.06, 0.06), RNG.uniform(-0.05, 0.05), z), (0, 0, RNG.uniform(-0.06, 0.06)))
        parts.append(s)
        z += 0.045
    return finish(merge(parts, name), 30.0)


def wooden_beam(name, L=3.0, s=0.3, seed=36, straps=True):
    """036: брус L × s × s: сколы на рёбрах, трещины-пропилы, 2 хомута с болтами."""
    RNG.seed(seed)
    o = box(name + "_b", (L, s, s), M("ScrapWood"), along='X', jitter=0.004, scale=0.8, cuts=7)
    # сколы: несколько вершин на верхних рёбрах утопить
    for v in o.data.vertices:
        if v.co.z > s / 2 - 0.006 and abs(v.co.y) > s / 2 - 0.006 and RNG.random() < 0.35:
            v.co.z -= RNG.uniform(0.01, 0.035)
            v.co.y -= math.copysign(RNG.uniform(0.005, 0.02), v.co.y)
    # торцы чуть скошены
    for v in o.data.vertices:
        if abs(v.co.x) > L / 2 - 0.006:
            v.co.x += RNG.uniform(-0.02, 0.01) * math.copysign(1, v.co.x)
    bevel_apply(o, 0.014)
    place(o, (0, 0, s / 2))
    parts = [o]
    # трещины: тёмные тонкие вставки на фасаде
    for (x0, x1, z) in ((-1.1, -0.55, 0.19), (0.2, 0.95, 0.12), (0.6, 1.25, 0.22)):
        c = box(name + "_cr", (x1 - x0, 0.01, 0.012), M("Char"), along='X')
        parts.append(place(c, ((x0 + x1) / 2, -s / 2 + 0.002, z), (math.radians(RNG.uniform(-3, 3)), 0, 0)))
    if straps:
        for x in (-0.95, 0.95):
            for (sz, loc) in (((0.08, s + 0.02, 0.012), (x, 0, s + 0.006)), ((0.08, s + 0.02, 0.012), (x, 0, -0.006)),
                              ((0.08, 0.012, s + 0.02), (x, -s / 2 - 0.006, s / 2)), ((0.08, 0.012, s + 0.02), (x, s / 2 + 0.006, s / 2))):
                b = box(name + "_st", sz, M("Rust"), along='Z')
                parts.append(place(b, loc))
            for z in (0.08, 0.22):
                parts.append(stud(name + "_bt", (x, -s / 2 - 0.012, z), (0, -1, 0), r=0.018, h=0.012))
            parts.append(stud(name + "_bt", (x, 0, s + 0.012), (0, 0, 1), r=0.018, h=0.012))
        for x in (-0.3, 0.45):
            parts.append(stud(name + "_nl", (x, -s / 2 - 0.001, 0.15 + RNG.uniform(-0.05, 0.05)), (0, -1, 0), r=0.011, h=0.008))
    return finish(ground(merge(parts, name)), 30.0)


def beam_stack(name):
    """036 stack: 3 бруса внизу, 2 сверху на прокладках, 3.0 × 0.62 × 1.0."""
    parts = []
    for i, y in enumerate((-0.34, 0.0, 0.34)):
        b = wooden_beam(name + "_b%d" % i, L=3.0 - 0.06 * i, s=0.3, seed=360 + i, straps=(i == 0))
        parts.append(place(b, (0.04 * i - 0.04, y, 0)))
    for i, y in enumerate((-0.17, 0.2)):
        b = wooden_beam(name + "_t%d" % i, L=2.8 + 0.1 * i, s=0.28, seed=365 + i, straps=(i == 0))
        parts.append(place(b, (0.08 - 0.12 * i, y, 0.315), (0, 0, math.radians(1.5 - 3 * i))))
    for x in (-1.1, 1.1):
        sp = box(name + "_sp", (0.08, 0.95, 0.015), M("ScrapWood"), along='Y')
        parts.append(place(sp, (x, 0, 0.3075)))
    return finish(merge(parts, name), 30.0)


def broken_beam(name):
    """037: пакет 2 × 2 брусьев 0.2, длины 2.1–2.5, левый торец расщеплён, железная скоба справа, погнутые гвозди."""
    RNG.seed(37)
    parts = []
    s = 0.19
    specs = [((-1, -1), 2.5, 0.0), ((1, -1), 2.2, 0.18), ((-1, 1), 2.35, 0.08), ((1, 1), 2.05, 0.3)]
    for (sy, sz), L, dx in specs:
        # sy: −1 фасад / +1 зад; sz: −1 низ / +1 верх
        o = box(name + "_t", (L, s, s), M("ScrapWood"), along='X', jitter=0.005, scale=0.8, cuts=5, broken=(0, -1, 0.14))
        for v in o.data.vertices:
            if RNG.random() < 0.3 and abs(v.co.x) < L / 2 - 0.1:
                v.co.z += math.copysign(RNG.uniform(0.0, 0.02), -v.co.z) if abs(v.co.z) > s / 2 - 0.007 else 0.0
        bevel_apply(o, 0.01)
        x_c = 1.25 - L / 2
        parts.append(place(o, (x_c, sy * (s / 2 + 0.005), 0.2 + sz * (s / 2 + 0.005))))
        # щепа на левом торце
        parts += splinters(name + "_sp", (x_c - L / 2 + 0.05, sy * (s / 2 + 0.005), 0.2 + sz * (s / 2 + 0.005)), (-1, 0, 0.1 * sz), 5, 0.22, 0.02, M("ScrapWood"), spread=0.35)
    # выбоины: тёмные сколы на фасаде
    for x in (-0.6, -0.1, 0.35):
        c = box(name + "_ch", (0.18, 0.012, 0.05), M("Char"), along='X')
        parts.append(place(c, (x, -s - 0.012, 0.2 + RNG.uniform(-0.12, 0.12))))
    # скоба: хомут вокруг пакета + болты
    x = 0.85
    for (sz, loc) in (((0.12, 0.42, 0.016), (x, 0, 0.405)), ((0.12, 0.42, 0.016), (x, 0, -0.003)),
                      ((0.12, 0.016, 0.42), (x, -0.205, 0.2)), ((0.12, 0.016, 0.42), (x, 0.205, 0.2))):
        b = box(name + "_cl", sz, M("Rust"), along='Z')
        bevel_apply(b, 0.003)
        parts.append(place(b, loc))
    for z in (0.08, 0.2, 0.32):
        parts.append(stud(name + "_bt", (x, -0.215, z), (0, -1, 0), r=0.02, h=0.014))
    # погнутые гвозди сверху
    for (gx, gy) in ((-0.35, -0.05), (-0.15, 0.06)):
        parts.append(tube_path(name + "_nail", [(gx, gy, 0.395), (gx, gy, 0.5), (gx + 0.06, gy, 0.55)], 0.007, M("Iron"), sides=5))
    return finish(ground(merge(parts, name)), 30.0)


def pipe_bundle(name):
    """038: три полые трубы r=0.15 вдоль X (две внизу, одна сверху), бандажи на торцах, 2 хомута с болтами."""
    RNG.seed(38)
    L, r, wall = 2.0, 0.15, 0.016
    pos = [(-0.152, r), (0.152, r), (0.0, r + 0.263)]
    parts = []
    for i, (y, z) in enumerate(pos):
        p = ring(name + "_p%d" % i, r - wall, r, L - 0.06 * i, 'X', M("Rust"), 16)
        parts.append(place(p, (0.03 * (i - 1), y, z)))
        for sx in (-1, 1):
            e = ring(name + "_e%d" % i, r - wall, r + 0.012, 0.06, 'X', M("Rust"), 16)
            parts.append(place(e, (0.03 * (i - 1) + sx * ((L - 0.06 * i) / 2 - 0.03), y, z)))
    # хомут: полоса по выпуклой оболочке трёх кругов
    for x in (-0.55, 0.6):
        hull = []
        centres = [Vector((0, y, z)) for y, z in pos]
        rr = r + 0.012
        for k in range(24):
            a = TAU * k / 24
            d = Vector((0, math.cos(a), math.sin(a)))
            best = max(centres, key=lambda c: c.dot(d))
            hull.append(best + d * rr)
        cen = sum(centres, Vector()) / 3.0
        for k in range(len(hull)):
            a_, b_ = hull[k], hull[(k + 1) % len(hull)]
            if (b_ - a_).length < 1e-4:
                continue
            mid = (a_ + b_) * 0.5
            upv = (mid - cen).normalized()
            parts.append(between(name + "_band", (x, a_.y, a_.z), (x, b_.y, b_.z), 0.07, 0.012, M("Iron"), up=tuple(upv), along='X'))
        for d in (Vector((0, -1, 0)), Vector((0, -0.6, 0.8)), Vector((0, 0, 1))):   # болты на лицевой стороне и сверху
            best = max(centres, key=lambda c: c.dot(d))
            parts.append(stud(name + "_bt", tuple(best + d * (rr + 0.006) + Vector((x, 0, 0))), tuple(d), r=0.018, h=0.012))
    return finish(ground(merge(parts, name)), 35.0)


def helix_pts(radius, z0, turns, pitch, seg_per_turn, phase=0.0, r_drift=0.0):
    n = int(round(turns * seg_per_turn)) + 1
    out = []
    for i in range(n):
        t = i / seg_per_turn
        a = TAU * t + phase
        rr = radius + r_drift * math.sin(a * 1.7)
        out.append((rr * math.cos(a), rr * math.sin(a), z0 + pitch * t))
    return out


def rope_coil(name):
    """039: бухта верёвки ⌀0.9 × 0.3 — два концентрических витка (r 0.4 и 0.31) по 3 оборота, свободный конец."""
    RNG.seed(39)
    tr = 0.045
    parts = []
    outer = helix_pts(0.4, tr, 3.0, 0.07, 18, 0.0, 0.006)
    inner = helix_pts(0.31, tr + 0.02, 2.8, 0.07, 16, 1.3, 0.006)
    parts.append(tube_path(name + "_o", outer, tr, M("Rope"), sides=8, uv_scale=3.0))
    parts.append(tube_path(name + "_i", inner, tr, M("Rope"), sides=8, uv_scale=3.0))
    # свободный конец: сходит с нижнего витка вперёд-влево по полу
    a0 = outer[0]
    tail = [a0, (a0[0] + 0.05, a0[1] - 0.12, tr), (0.3, -0.5, tr), (0.05, -0.56, tr), (-0.25, -0.52, tr), (-0.42, -0.4, tr)]
    parts.append(tube_path(name + "_t", tail, tr * 0.95, M("Rope"), sides=8, uv_scale=3.0))
    return finish(merge(parts, name), 50.0)


def cable_coil(name):
    """040: бухта стального троса ⌀1.0 × 0.35 — три плотных витка (r 0.455 / 0.39 / 0.325, трос ⌀0.066) по ~4.8 оборота
    вокруг тёмного сердечника (не просвечивает), 3 железные скобы с заклёпками, свободный конец."""
    RNG.seed(40)
    tr = 0.033
    parts = []
    for k, rad in enumerate((0.455, 0.39, 0.325)):
        pts = helix_pts(rad, tr + 0.004 * k, 4.8 if k < 2 else 4.5, 0.064, 12, 0.7 * k, 0.004)
        parts.append(tube_path(name + "_c%d" % k, pts, tr, M("Steel"), sides=5, uv_scale=6.0))
    core = ring(name + "_core", 0.3, 0.46, 0.3, 'Z', M("Steel"), 16)
    parts.append(place(core, (0, 0, 0.17)))
    # скобы: П-образная полоса вокруг сечения бухты (r 0.28..0.505, z 0..0.385)
    for k in range(3):
        a = TAU * (k + 0.1) / 3
        ca, sa = math.cos(a), math.sin(a)
        r0, r1, zt = 0.275, 0.505, 0.385
        corners = [(r0, 0.0), (r0, zt), (r1, zt), (r1, 0.0)]
        for (ra, za), (rb, zb) in zip(corners, corners[1:]):
            parts.append(between(name + "_cl", (ra * ca, ra * sa, za), (rb * ca, rb * sa, zb), 0.06, 0.012, M("Rust"), up=(ca if ra == rb else 0, sa if ra == rb else 0, 0 if ra == rb else 1)))
        parts.append(stud(name + "_rv", ((r1 + 0.006) * ca, (r1 + 0.006) * sa, zt * 0.5), (ca, sa, 0), r=0.014, h=0.01))
        parts.append(stud(name + "_rv", ((r0 + r1) / 2 * ca, (r0 + r1) / 2 * sa, zt + 0.006), (0, 0, 1), r=0.014, h=0.01))
    first = helix_pts(0.455, tr, 0.01, 0.064, 12)[0]
    tail = [first, (first[0] + 0.02, first[1] - 0.15, tr), (0.3, -0.58, tr), (0.0, -0.64, tr), (-0.35, -0.6, tr), (-0.55, -0.45, tr)]
    parts.append(tube_path(name + "_t", tail, tr, M("Steel"), sides=5, uv_scale=6.0))
    return finish(merge(parts, name), 50.0)


# ----------------------------------------------------------------------------------------------------------------------
# сборка
# ----------------------------------------------------------------------------------------------------------------------
def states(builders):
    """Несколько корневых объектов в одном glb: [(имя, builder)] — Intact / Damaged / Destroyed."""
    def build(_name):
        return [b(n) for n, b in builders]
    return build


MODULES = [
    ("Wooden_Crate", states([("Intact", lambda n: crate_021("intact")), ("Damaged", lambda n: crate_021("damaged")), ("Destroyed", lambda n: crate_021("destroyed"))])),
    ("Reinforced_Crate", states([("Intact", lambda n: crate_022("intact")), ("Damaged", lambda n: crate_022("damaged")), ("Destroyed", lambda n: crate_022("destroyed"))])),
    ("Broken_Crate_A", lambda n: broken_crate(n, "A")),
    ("Broken_Crate_B", lambda n: broken_crate(n, "B")),
    ("Broken_Crate_Debris", lambda n: broken_crate(n, "debris")),
    ("Large_Shipping_Crate", shipping_crate),
    ("Wooden_Barrel", states([("Intact", lambda n: barrel_025("intact")), ("Damaged", lambda n: barrel_025("damaged")), ("Destroyed", lambda n: barrel_025("destroyed"))])),
    ("Metal_Barrel", lambda n: metal_barrel(n)),
    ("Metal_Barrel_Dented", lambda n: metal_barrel(n, dented=True)),
    ("Broken_Barrel_A", lambda n: broken_barrel(n, "A")),
    ("Broken_Barrel_B", lambda n: broken_barrel(n, "B")),
    ("Broken_Barrel_Debris", lambda n: broken_barrel(n, "debris")),
    ("Scrap_Basket", lambda n: scrap_basket(n)),
    ("Scrap_Basket_Full", lambda n: scrap_basket(n, full=True)),
    ("Junk_Cart", lambda n: junk_cart(n)),
    ("Junk_Cart_Loaded", lambda n: junk_cart(n, loaded=True)),
    ("Overturned_Junk_Cart", overturned_cart),
    ("Rail_Scrap_Wagon", lambda n: rail_wagon(n)),
    ("Rail_Scrap_Wagon_Full", lambda n: rail_wagon(n, full=True)),
    ("Broken_Wheelbarrow", wheelbarrow),
    ("Wooden_Pallet", pallet),
    ("Metal_Plate", lambda n: finish(metal_plate(n, "A"), 30.0)),
    ("Metal_Plate_B", lambda n: finish(metal_plate(n, "B", "RustDark", seed=341), 30.0)),
    ("Metal_Plate_Stack", metal_plate_stack),
    ("Corrugated_Sheet", lambda n: finish(corrugated(n, "Rust", bend=0.03), 30.0)),
    ("Corrugated_Sheet_B", lambda n: finish(corrugated(n, "RustRed", bend=-0.0, seed=351), 30.0)),
    ("Corrugated_Sheet_Stack", corrugated_stack),
    ("Wooden_Beam", lambda n: wooden_beam(n)),
    ("Wooden_Beam_Stack", beam_stack),
    ("Broken_Beam", broken_beam),
    ("Pipe_Bundle", pipe_bundle),
    ("Rope_Coil", rope_coil),
    ("Cable_Coil", cable_coil),
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


def bounds(roots):
    """Габариты всех мешей (мир): (min, max) по X, Y, Z."""
    lo = [1e9, 1e9, 1e9]
    hi = [-1e9, -1e9, -1e9]
    for r in roots:
        for o in [r] + list(r.children_recursive):
            if o.type != 'MESH':
                continue
            for v in o.data.vertices:
                w = o.matrix_world @ v.co
                for k in range(3):
                    lo[k] = min(lo[k], w[k])
                    hi[k] = max(hi[k], w[k])
    return lo, hi


def build_models(only):
    C.reset_scene()
    os.makedirs(OUT, exist_ok=True)
    report = []
    for name, build in MODULES:
        if only and name not in only:
            continue
        roots = build(name)
        if not isinstance(roots, list):
            roots = [roots]
        if len(roots) == 1:
            roots[0].name = name
        per = []
        for r in roots:
            per.append((r.name, tri_count(r)))
        lo, hi = bounds(roots[:1])
        path = os.path.join(OUT, name + ".glb")
        export(path, roots)
        report.append((name, per, os.path.getsize(path), lo, hi))
        for r in roots:
            for c in list(r.children_recursive):
                bpy.data.objects.remove(c, do_unlink=True)
            bpy.data.objects.remove(r, do_unlink=True)
    print("\nMATERIALS")
    for k in sorted(MAT_STATUS):
        print("  %-16s %s" % (k, MAT_STATUS[k]))
    print("\nMODULE                   TRIS (max obj / glb)   BYTES     SIZE X×Z×Y (Ш×В×Г), м      objects")
    bad = []
    for name, per, size, lo, hi in report:
        mx = max(t for _, t in per)
        tot = sum(t for _, t in per)
        over = mx > TRI_BUDGET or tot > GLB_BUDGET
        if over:
            bad.append(name)
        dims = "%.2f × %.2f × %.2f" % (hi[0] - lo[0], hi[2] - lo[2], hi[1] - lo[1])
        print("%-24s %6d / %6d %10d   %-22s %s%s" % (name, mx, tot, size, dims, ", ".join("%s %d" % p for p in per) if len(per) > 1 else "",
                                                    "  OVER BUDGET" if over else ""))
        print("    z %.3f..%.3f  x %.3f..%.3f  y %.3f..%.3f" % (lo[2], hi[2], lo[0], hi[0], lo[1], hi[1]))
    if bad:
        print("ERROR: over budget:", bad)
        sys.exit(1)


def main():
    if bpy is None:
        if "--sheet" in sys.argv:
            contact_sheet()
            return
        print("нужен Blender (или --sheet для сборки листа через Pillow)")
        sys.exit(1)
    argv = C.args_after_dashdash()
    if "--render" in argv:
        render_cells([a for a in argv if a != "--render"])
        return
    build_models(argv)


# ----------------------------------------------------------------------------------------------------------------------
# контактный рендер (Blender, Cycles) и лист (системный python3 + Pillow)
# ----------------------------------------------------------------------------------------------------------------------
# ячейка листа: (№, заголовок, физика, [(glb, корневой объект или None, подпись)])
CELLS = [
    ("021", "Wooden Crate", "B", [("Wooden_Crate", "Intact", "intact"), ("Wooden_Crate", "Damaged", "damaged"), ("Wooden_Crate", "Destroyed", "destroyed")]),
    ("022", "Reinforced Crate", "B", [("Reinforced_Crate", "Intact", "intact"), ("Reinforced_Crate", "Damaged", "damaged"), ("Reinforced_Crate", "Destroyed", "destroyed")]),
    ("023", "Broken Crate", "R / S", [("Broken_Crate_A", None, "A (R)"), ("Broken_Crate_B", None, "B (R)"), ("Broken_Crate_Debris", None, "debris (S)")]),
    ("024", "Large Shipping Crate", "R", [("Large_Shipping_Crate", None, "intact")]),
    ("025", "Wooden Barrel", "B", [("Wooden_Barrel", "Intact", "intact"), ("Wooden_Barrel", "Damaged", "damaged"), ("Wooden_Barrel", "Destroyed", "destroyed")]),
    ("026", "Metal Barrel", "R", [("Metal_Barrel", None, "intact"), ("Metal_Barrel_Dented", None, "dented")]),
    ("027", "Broken Barrel", "R / S", [("Broken_Barrel_A", None, "A (R)"), ("Broken_Barrel_B", None, "B (R)"), ("Broken_Barrel_Debris", None, "debris (S)")]),
    ("028", "Scrap Basket", "R", [("Scrap_Basket", None, "empty"), ("Scrap_Basket_Full", None, "full")]),
    ("029", "Junk Cart", "R", [("Junk_Cart", None, "intact"), ("Junk_Cart_Loaded", None, "loaded")]),
    ("030", "Overturned Junk Cart", "S", [("Overturned_Junk_Cart", None, "")]),
    ("031", "Rail Scrap Wagon", "R", [("Rail_Scrap_Wagon", None, "empty"), ("Rail_Scrap_Wagon_Full", None, "full")]),
    ("032", "Broken Wheelbarrow", "R", [("Broken_Wheelbarrow", None, "")]),
    ("033", "Wooden Pallet", "R", [("Wooden_Pallet", None, "")]),
    ("034", "Metal Plate", "R / S", [("Metal_Plate", None, "A (R)"), ("Metal_Plate_B", None, "B (R)"), ("Metal_Plate_Stack", None, "stack (S)")]),
    ("035", "Corrugated Sheet", "R / S", [("Corrugated_Sheet", None, "A (R)"), ("Corrugated_Sheet_B", None, "B (R)"), ("Corrugated_Sheet_Stack", None, "stack (S)")]),
    ("036", "Wooden Beam", "R / S", [("Wooden_Beam", None, "intact (R)"), ("Wooden_Beam_Stack", None, "stack (S)")]),
    ("037", "Broken Beam", "R", [("Broken_Beam", None, "")]),
    ("038", "Pipe Bundle", "R", [("Pipe_Bundle", None, "")]),
    ("039", "Rope Coil", "R", [("Rope_Coil", None, "")]),
    ("040", "Cable Coil", "R", [("Cable_Coil", None, "")]),
]
CELL_RES = (960, 600)
CAM_YAW, CAM_PITCH = math.radians(22.0), math.radians(15.0)


def _doll_silhouette(mat):
    """Силуэт куклы 1.8 м (капсулы, руки вдоль тела), стоит на z=0, лицом −Y."""
    parts = []
    head = C.add_sphere("doll_head", 0.115, loc=(0, 0, 1.685), segments=16, rings=10)
    parts.append(head)

    def capsule(nm, a, b, r):
        a, b = Vector(a), Vector(b)
        d = b - a
        o = cyl(nm, r, d.length, 'Z', mat, segs=12)
        rot = d.to_track_quat('Z', 'Y').to_matrix().to_4x4()
        xform(o, rot)
        xform(o, Matrix.Translation((a + b) / 2))
        s0 = C.add_sphere(nm + "a", r, loc=tuple(a), segments=12, rings=6)
        s1 = C.add_sphere(nm + "b", r, loc=tuple(b), segments=12, rings=6)
        return [o, s0, s1]

    parts += capsule("neck", (0, 0, 1.5), (0, 0, 1.6), 0.05)
    parts += capsule("chest", (0, 0, 1.2), (0, 0, 1.42), 0.17)
    parts += capsule("belly", (0, 0, 0.98), (0, 0, 1.18), 0.13)
    for sx in (-1, 1):
        parts += capsule("uarm", (sx * 0.21, 0, 1.44), (sx * 0.25, 0, 1.16), 0.05)
        parts += capsule("farm", (sx * 0.25, 0, 1.13), (sx * 0.27, 0, 0.88), 0.045)
        parts += capsule("thigh", (sx * 0.1, 0, 0.93), (sx * 0.11, 0, 0.52), 0.07)
        parts += capsule("shin", (sx * 0.11, 0, 0.48), (sx * 0.12, 0, 0.09), 0.055)
        parts.append(place(box("foot%d" % sx, (0.1, 0.22, 0.07), mat), (sx * 0.12, -0.05, 0.035)))
    for o in parts:
        o.data.materials.clear()
        o.data.materials.append(mat)
    d = merge(parts, "Doll_1_8m")
    zs = [v.co.z for v in d.data.vertices]
    xform(d, Matrix.Diagonal((1.0, 1.0, 1.8 / (max(zs) - min(zs)), 1.0)))
    smooth(d, 60.0)
    return d


def _import_glb(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    return [o for o in bpy.data.objects if o not in before]


def _world_bbox(objs):
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        if o.type != 'MESH':
            continue
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            lo = Vector((min(lo[k], w[k]) for k in range(3)))
            hi = Vector((max(hi[k], w[k]) for k in range(3)))
    return lo, hi


def _setup_render_scene():
    C.reset_scene()
    scn = bpy.context.scene
    scn.render.engine = 'CYCLES'
    scn.cycles.samples = int(os.environ.get("SCRAP_RENDER_SAMPLES", "48"))
    scn.cycles.use_denoising = True
    scn.cycles.device = 'CPU'
    try:
        prefs = bpy.context.preferences.addons['cycles'].preferences
        prefs.compute_device_type = 'METAL'
        prefs.get_devices()
        for dev in prefs.devices:
            dev.use = dev.type != 'CPU'
        scn.cycles.device = 'GPU'
    except Exception as exc:  # noqa: BLE001
        print("GPU unavailable, CPU:", exc)
    scn.render.resolution_x, scn.render.resolution_y = CELL_RES
    scn.render.resolution_percentage = 100
    scn.render.image_settings.file_format = 'PNG'
    scn.render.image_settings.color_mode = 'RGB'
    scn.view_settings.view_transform = 'AgX'
    scn.view_settings.look = 'AgX - Medium High Contrast'
    world = bpy.data.worlds.new("World")
    scn.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes['Background']
    bg.inputs['Color'].default_value = (0.030, 0.028, 0.034, 1.0)
    bg.inputs['Strength'].default_value = 1.0
    floor = C.add_cube("Floor", (60.0, 60.0, 0.02), (0, 0, -0.01))
    C.assign(floor, C.material("FloorMat", (0.028, 0.024, 0.022, 1.0), 0.95, 0.0))
    for nm, col, energy, rot in (("Key", (1.0, 0.72, 0.50), 3.6, (math.radians(52), 0, math.radians(-28))),
                                 ("Fill", (0.55, 0.62, 1.0), 0.9, (math.radians(65), 0, math.radians(150))),
                                 ("Top", (1.0, 0.95, 0.9), 0.6, (math.radians(10), 0, 0))):
        ld = bpy.data.lights.new(nm, 'SUN')
        ld.color = col
        ld.energy = energy
        ld.angle = math.radians(6.0)
        lo = bpy.data.objects.new(nm, ld)
        scn.collection.objects.link(lo)
        lo.rotation_euler = rot
    cam_d = bpy.data.cameras.new("Cam")
    cam_d.type = 'ORTHO'
    cam = bpy.data.objects.new("Cam", cam_d)
    scn.collection.objects.link(cam)
    cam.rotation_euler = (math.pi / 2 - CAM_PITCH, 0.0, CAM_YAW)
    scn.camera = cam
    return scn, cam


def render_cells(only):
    """Импортирует экспортированные glb, раскладывает состояния ячейки в ряд рядом с силуэтом куклы 1.8 м,
    рендерит ортокамерой (рыскание 22°, наклон 15°, видно фасад и правый бок) → RENDER_TMP/cell_<№>.png + meta.json."""
    import json
    from bpy_extras.object_utils import world_to_camera_view
    os.makedirs(RENDER_TMP, exist_ok=True)
    meta_path = os.path.join(RENDER_TMP, "meta.json")
    meta = {}
    if os.path.exists(meta_path):
        with open(meta_path) as f:
            meta = json.load(f)
    for num, title, phys, items in CELLS:
        if only and num not in only and not any(i[0] in only for i in items):
            continue
        scn, cam = _setup_render_scene()
        doll_mat = C.material("DollSil", (0.16, 0.17, 0.19, 1.0), 0.6, 0.0)
        doll = _doll_silhouette(doll_mat)
        x_cursor = 0.0
        placed = []
        tris_info = []
        for glb, root_name, label in items:
            objs = _import_glb(os.path.join(OUT, glb + ".glb"))
            roots = [o for o in objs if o.parent is None]
            keep = [o for o in roots if root_name is None or o.name.split(".")[0] == root_name]
            for o in roots:
                if o not in keep:
                    for c in list(o.children_recursive):
                        bpy.data.objects.remove(c, do_unlink=True)
                    bpy.data.objects.remove(o, do_unlink=True)
            group = []
            for o in keep:
                group += [o] + list(o.children_recursive)
            if root_name == "Destroyed":
                # обломки: раздвинуть от центра, высокие положить вдоль X, опустить на пол (как после разлёта)
                lo, hi = _world_bbox(group)
                cen = (lo + hi) * 0.5
                pieces = [o for o in group if o.parent is not None and o.type == 'MESH']
                for k, o in enumerate(pieces):
                    plo, phi = _world_bbox([o])
                    ext = phi - plo
                    if ext.z > max(ext.x, ext.y) * 1.2:
                        o.rotation_mode = 'XYZ'    # импорт glTF ставит QUATERNION
                        o.rotation_euler = (o.rotation_euler.x, o.rotation_euler.y + math.radians(90 if k % 2 else -90), o.rotation_euler.z)
                    d = o.matrix_world.translation - cen
                    o.location = o.location + Vector((d.x * 0.9 + (k % 3 - 1) * 0.12, d.y * 0.6, 0.0))
                    bpy.context.view_layer.update()
                    plo, phi = _world_bbox([o])
                    o.location.z -= plo.z
                bpy.context.view_layer.update()
            tris = sum(len(o.data.polygons) for o in group if o.type == 'MESH')
            tris_info.append(tris)
            lo, hi = _world_bbox(group)
            dx = x_cursor - lo.x
            for o in keep:
                o.location.x += dx
            bpy.context.view_layer.update()
            lo, hi = _world_bbox(group)
            placed.append((label, lo, hi, tris))
            x_cursor = hi.x + max(0.35, 0.12 * (hi.x - lo.x))
        # кукла слева от первого предмета
        dlo, dhi = _world_bbox([doll])
        doll.location.x = placed[0][1].x - 0.3 - dhi.x
        bpy.context.view_layer.update()
        allo, alhi = _world_bbox([doll] + [o for o in bpy.data.objects if o.type == 'MESH' and o.name not in ("Floor",)])
        # вписать в кадр: углы bbox → система камеры
        cam_rot = cam.rotation_euler.to_matrix()
        right, up, fwd = cam_rot.col[0], cam_rot.col[1], -cam_rot.col[2]
        corners = [Vector((x, y, z)) for x in (allo.x, alhi.x) for y in (allo.y, alhi.y) for z in (max(allo.z, 0.0), alhi.z)]
        us = [c.dot(right) for c in corners]
        vs = [c.dot(up) for c in corners]
        cu, cv = (min(us) + max(us)) / 2, (min(vs) + max(vs)) / 2
        aspect = CELL_RES[0] / CELL_RES[1]
        span = max((max(us) - min(us)) * 1.08, (max(vs) - min(vs)) * 1.18 * aspect)
        cam.data.ortho_scale = span
        centre = right * cu + up * (cv + (max(vs) - min(vs)) * 0.04)
        cam.location = centre - fwd * 40.0
        cam.data.clip_end = 200.0
        bpy.context.view_layer.update()
        labels = []
        for label, lo, hi, tris in placed:
            p = world_to_camera_view(scn, cam, Vector(((lo.x + hi.x) / 2, lo.y, 0.0)))
            labels.append((label, round(p.x * CELL_RES[0]), round((1.0 - p.y) * CELL_RES[1]), tris, [round(hi.x - lo.x, 2), round(hi.z - lo.z, 2), round(hi.y - lo.y, 2)]))
        dp = world_to_camera_view(scn, cam, Vector((doll.location.x, 0.0, 1.8)))
        out = os.path.join(RENDER_TMP, "cell_%s.png" % num)
        scn.render.filepath = out
        bpy.ops.render.render(write_still=True)
        meta[num] = {"title": title, "phys": phys, "file": out, "labels": labels,
                     "doll_top": [round(dp.x * CELL_RES[0]), round((1.0 - dp.y) * CELL_RES[1])]}
        print("rendered", num, title, out)
        with open(meta_path, "w") as f:
            json.dump(meta, f, ensure_ascii=False, indent=1)


# координаты ячеек на sheet-02.png (1536 × 1024) для врезки-референса
REF_BOXES = {
    "021": (8, 148, 257, 378), "022": (259, 148, 508, 378), "023": (512, 148, 763, 378), "024": (767, 148, 1027, 378),
    "025": (1031, 148, 1287, 378), "026": (1290, 148, 1532, 378),
    "027": (8, 380, 257, 609), "028": (259, 380, 508, 609), "029": (512, 380, 763, 609), "030": (767, 380, 1027, 609),
    "031": (1031, 380, 1287, 609), "032": (1290, 380, 1532, 609),
    "033": (8, 612, 257, 829), "034": (259, 612, 508, 829), "035": (512, 612, 763, 829), "036": (767, 612, 1027, 829),
    "037": (1031, 612, 1287, 829), "038": (1290, 612, 1532, 829),
    "039": (8, 832, 508, 1005), "040": (512, 832, 1027, 1005),
}


def contact_sheet():
    """Pillow: сетка 6 × 4 как на sheet-02 — рендер ячейки (кукла 1.8 м слева), подписи состояний с треугольниками,
    врезка-референс из листа в углу → docs/plan-demo/img/scrap-sheet02-v1.png."""
    import json
    from PIL import Image, ImageDraw, ImageFont
    with open(os.path.join(RENDER_TMP, "meta.json")) as f:
        meta = json.load(f)
    font = small = big = None
    for fp in ('/System/Library/Fonts/Supplemental/Arial.ttf', '/Library/Fonts/Arial.ttf'):
        if os.path.exists(fp):
            font, small, big = ImageFont.truetype(fp, 17), ImageFont.truetype(fp, 13), ImageFont.truetype(fp, 28)
            break
    if font is None:
        font = small = big = ImageFont.load_default()
    ref = Image.open(REF_SHEET).convert("RGB")
    cw, ch, head = 560, 350, 34
    cols = 6
    pad = 8
    W = pad + cols * (cw + pad)
    rows = 4
    top = 56
    H = top + rows * (ch + head + pad) + pad
    sheet = Image.new("RGB", (W, H), (18, 17, 20))
    d = ImageDraw.Draw(sheet)
    d.text((pad + 4, 12), "THE SCRAP — лист 02 «Physical Props» 021–040, Blender-модели v1 (силуэт слева — кукла 1.8 м; "
           "в углу ячейки — референс sheet-02)", fill=(232, 226, 214), font=big)
    order = [c[0] for c in CELLS]
    for idx, num in enumerate(order):
        if num not in meta:
            continue
        m = meta[num]
        r, c = divmod(idx, cols)
        x0 = pad + c * (cw + pad)
        y0 = top + r * (ch + head + pad)
        d.rectangle((x0, y0, x0 + cw, y0 + head + ch), fill=(28, 26, 30), outline=(58, 54, 60))
        d.text((x0 + 8, y0 + 7), "%s  %s" % (num, m["title"]), fill=(238, 232, 220), font=font)
        tw = d.textlength(m["phys"], font=font)
        d.text((x0 + cw - tw - 10, y0 + 7), m["phys"], fill=(250, 196, 120), font=font)
        im = Image.open(m["file"]).convert("RGB")
        sc = cw / im.width
        im = im.resize((cw, int(im.height * sc)), Image.LANCZOS)
        sheet.paste(im, (x0, y0 + head))
        for label, px, py, tris, dims in m["labels"]:
            txt = ("%s · " % label if label else "") + "%d tris" % tris
            sub = "%.2f×%.2f×%.2f" % tuple(dims)
            tx = x0 + px * sc
            ty = y0 + head + min(py * sc + 4, ch - 34)
            for t_, f_, dy, col in ((txt, small, 0, (236, 228, 212)), (sub, small, 15, (150, 146, 140))):
                w_ = d.textlength(t_, font=f_)
                xx = min(max(tx - w_ / 2, x0 + 4), x0 + cw - w_ - 4)
                d.text((xx, ty + dy), t_, fill=col, font=f_)
        rb = REF_BOXES.get(num)
        if rb:
            crop = ref.crop(rb)
            crop.thumbnail((150, 110), Image.LANCZOS)
            ix, iy = x0 + cw - crop.width - 4, y0 + head + 4
            sheet.paste(crop, (ix, iy))
            d.rectangle((ix - 1, iy - 1, ix + crop.width, iy + crop.height), outline=(90, 84, 92))
    # легенда в свободных ячейках последнего ряда
    lx = pad + 2 * (cw + pad) + 10
    ly = top + 3 * (ch + head + pad) + 10
    lines = ["B — разрушаемый (breakable.gd): Intact / Damaged / Destroyed/Piece_*",
             "R — RigidBody3D в плоскости XY (CCD, упрощённая коллизия); S — статика/декор",
             "Подпись: состояние · треугольники; Ш × В × Г, м (X × Z × Y Blender)",
             "Камера: орто, рыскание 22°, наклон 15° (видно фасад −Y и правый бок)",
             "Свет: тёплое солнце + холодный заполняющий; Cycles, AgX",
             "Модели: godot/assets/models/scrap/props/*.glb (tools/blender/scrap_props.py)"]
    for i, t_ in enumerate(lines):
        d.text((lx, ly + i * 24), t_, fill=(200, 194, 184), font=font)
    os.makedirs(os.path.dirname(SHEET_PNG), exist_ok=True)
    sheet.save(SHEET_PNG)
    print("contact sheet", SHEET_PNG, sheet.size)


if __name__ == "__main__":
    main()
