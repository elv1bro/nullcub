#!/usr/bin/env python3
"""THE SCRAP (биом 1 «Свалка»), модульный кит 01 «Core Structures» — модули K01–K08, K12–K22 по листу
docs/refs/biomes/01-scrap/kit-01.png (таблица «Кит 01» в LIST.md; K09–K11 — перекрёстки вида сверху — в 2.5D не нужны).
Массивные клёпаные рамы из ржавого железа, настил из старых досок с железными полосами, квадратные узлы-соединители
с гнездом и болтами (единая «snap»-система), проушины-кольца на свободных концах, фаски на всех рамных деталях.
Настоящие меши Blender 4.5 с PBR-наборами Свалки из assets/textures/pbr (rust_metal, rust_painted_red, scrap_wood,
brass_worn — печёт tools/blender/textures.py) и общим fabric_red; корона на флагах — декаль assets/textures/decals/crown.png
(alpha clip: Math Round → в glTF alphaMode MASK), повторяет складки ткани.

Запуск (headless):
    /Applications/Blender.app/Contents/MacOS/Blender -b --python godot/tools/blender/scrap_kit.py [-- Имя … | render | norender | noexport]
        → godot/assets/models/scrap/kit/<Name>.glb   (Y вверх в Godot; ≤ 3000 треугольников на модуль, скрипт падает при превышении)
        → docs/plan-demo/img/scrap-kit-v1.png        контактный рендер (Eevee, орто спереди с наклоном 4°): три ряда модулей
                                                     на сетке 2 м (торцы платформ и оси опор — на линиях сетки), в начале
                                                     каждого ряда кукла-эталон 1.8 м, в конце — пример snap-сборки
                                                     (2 × Support_S + Platform_M на y = 3 + 1 + Railing)
        Флаги: norender — без рендера; render — только рендер (glb не пишутся); noexport — геометрия + рендер без glb.
Переменные окружения: SCRAP_KIT_TEX (1024) — размер текстур, вшиваемых в glb; SCRAP_KIT_IMG (WEBP); SCRAP_KIT_CACHE — кэш
уменьшенных карт; SCRAP_FLAT=1 — принудительно плоские материалы (если PBR-папка не испечена — нет нужных карт, — материал
с тем же именем строится плоским, скрипт печатает список «FLAT»). Отладка рендера: SCRAP_KIT_OUT — путь png,
SCRAP_KIT_FOCUS=ряд[:x0:x1] — крупный план ряда, SCRAP_KIT_VIEW=34 — вид 3/4 сверху (проверка глубины), SCRAP_KIT_ENGINE=CYCLES.

Соглашения (ASSET_PIPELINE.md, common.py): метры; Blender Z вверх, X вбок, «лицо» в −Y (в Godot +Z, к камере); 1 тайл
текстуры = 1 м; у железа развёртка along='Z' (прокатные полосы вдоль U, подтёки вниз по V), у досок — вдоль волокна,
доска настила ≤ 0.24 м попадает в одну доску текстуры scrap_wood (4 доски на тайл). Всё детерминировано: seed модуля =
crc32(имени). Каждый glb — один объект-меш с именем файла, материалы — слоты: RustIron / RustIronDark (rust_metal, тёмный
тинт — стойки, ноги, цепи), RustRed (rust_painted_red — торцевые плиты концов, бирка), ScrapWood / ScrapWoodDark (scrap_wood
с тинтами — доски, лестница), Brass (brass_worn — корона-накладка, наконечники штанг), Banner (fabric_red, двусторонний),
Crown (декаль crown.png, MASK). Металличность rust/brass — картой metallic.png. Геометрия собирается прямо в bmesh
(фаски — bmesh.ops.bevel, 1 сегмент; рёбра острее 32° помечены sharp → в glTF раздельные нормали); невидимые с камеры
грани задних деталей (+Y) и низы досок удалены.

СЕТКА И SNAP (размеры ниже — Ш × В × Г в осях Godot, м, габарит с кольцами/цепями; «верх» = Godot +Y):
    Глубина настила по Z — 2.0 (−1 … +1): кукла на z = 0 стоит посередине. Рама платформы: продольные балки-швеллеры
    0.14 × 0.34 по краям глубины (z = ±0.93), верх балок заподлицо с настилом (y = 0), доски 0.07 лежат между балками на
    поперечинах; узлы-соединители — кубы 0.44 (верх y = +0.06, низ −0.38) на концах модуля (внешняя грань узла = торец)
    и на внутренних линиях сетки 2 м; поверх досок на линиях узлов — поперечные железные полосы, вдоль — две продольные.
    Платформы: origin — центр ВЕРХНЕЙ плоскости настила (y = 0 — поверхность, по которой ходят), модуль занимает
    x ∈ [−L/2, L/2]; ноги стоят под узлами (у концевых — в 0.22 м от торцов), подошвы на y = −1.0 (Lower −0.5, Upper −2.0).
    Опоры: origin — центр основания; верх крышки ровно 3 / 4 / 6 м; крышка 1.06 (L: 1.66) × 2.06 по глубине.
    Сборка: опора стоит на узле сетки x = 2k; платформа, у которой торец на той же линии x = 2k, ставится origin-ом на
    y = H + 1.0 (H — высота опоры; Lower: H + 0.5, Upper: H + 2.0) — её нога стоит на крышке опоры, на ту же крышку
    встаёт нога соседней платформы с другой стороны. Скаты поднимаются ровно на 1 и 2 м на пролёте 4 м: низ ската — на
    уровне пола/настила, верх — на уровне настила обычной (1.0) и высокой (2.0) платформы.

Файлы и модули (assets/models/scrap/kit/<Name>.glb; в скобках — треугольники на момент v1):
    K01 Platform_S      (1406)  2 × 1.06 × 2.3   9 досок, балки с рядами заклёпок, 2 узла, 2 ноги (подошвы, косынки),
                                                 нижняя стяжка, кольца-проушины на обоих торцах, короткая цепь под балкой
    K02 Platform_M      (2132)  4 × 1.06 × 2.3   узлы на концах и на x = 0, 3 ноги, 2 обрывка цепи (один с крюком)
    K03 Platform_L      (2732)  6 × 1.06 × 2.3   узлы на концах и на x = ±1, 4 ноги, 3 обрывка цепи
    K04 Platform_End_L  (1724)  2 × 1.06 × 2.3   конец пролёта слева: свободный торец x = −1 — узел с гнездом на торце,
                                                 красная крашеная торцевая плита на болтах, кольцо, цепь с крюком; скошенная
                                                 (разведённая наружу до x = −1.06) нога и раскос от подошвы стыковой ноги
                                                 к свободному узлу; стыковой конец x = +1 как у S
    K05 Platform_End_R  (1724)  2 × 1.06 × 2.3   зеркально: свободный торец x = +1
    K06 Platform_Gap    (2260)  4 × 1.06 × 2.3   две половины 1.4 м (x ∈ [−2, −0.6] и [0.6, 2]) с разрывом 1.2 м: внешние
                                                 концы — узлы и ноги, у обломков — рваные доски разной длины, повисшая доска,
                                                 балка со срезом наискось, нога без узла, свисающие цепи
    K07 Platform_Lower  (1056)  2 × 0.56 × 2.3   низкая: концевые узлы вытянуты до земли (ступы на подошвах), без ног
    K08 Platform_Upper  (1590)  2 × 2.06 × 2.3   высокая: ноги 1.6 м, крест-раскос с накладкой спереди и сзади, стяжка
    K12 Slope_15        (1286)  4 × 1.06 × 2.3   скат: подъём 1.0 м на пролёте 4 м (фактически 14.0°); origin — центр
                                                 пролёта на уровне НИЖНЕГО края настила (поверхность от (−2, 0) до (2, 1);
                                                 доска у носка уходит на 7 см под пол); боковые балки срезаны по земле,
                                                 железный носок, узел на x = 0 (в наклоне), вертикальный узел и ноги у x = 1.8
    K13 Slope_30        (1620)  4 × 2.06 × 2.3   скат: подъём 2.0 м на 4 м (фактически 26.6°) + ноги под средним узлом, раскос
    K14 Support_S       (1532)  1.06 × 3 × 2.16  опора-башня: 4 стойки-швеллера, в каждом пролёте крест спереди и сзади,
                                                 стяжки, цоколь и узлы под крышкой, крышка (по ней ходят), кольцо и цепь;
                                                 origin — центр основания; 2 пролёта
    K15 Support_M       (1798)  1.06 × 4 × 2.16  то же, 2 пролёта, цепь с крюком
    K16 Support_L       (2244)  1.66 × 6 × 2.16  то же шире, 3 пролёта
    K17 Support_Diagonal (940)  2.3 × 3 × 0.6    стойка 0.36 с узлами (верх 3.0) + подкос-швеллер от башмака на земле
                                                 (x = −1.9) к накладке на стойке (y ≈ 2.3); origin — центр основания стойки;
                                                 подкос справа — scale.x = −1 у экземпляра
    K18 Wall_Frame      (2952)  4.4 × 3 × 0.6    рама-ворота: две решётчатые стойки 0.5 (x = ±1.75) с крестами, верхняя
                                                 балка с узлами и кольцами, латунная корона-накладка, под балкой на штанге
                                                 красный флаг 1.3 × ~1.9 с рваным низом и декалью короны, две цепи; origin —
                                                 центр основания
    K19 Banner_Frame    (2586)  2.4 × 4.6 × 0.5  высокая рама 2 × 4 (стойки 0.4 на x = ±0.8) с флагом 1.1 × ~2.9, рым-болт
                                                 с цепью над балкой (до y ≈ 4.6), кольца по торцам
    K19b Railing        (2062)  2 × 1.14 × 0.3   перила: брус-основание, две стойки с узлами-шапками и воротниками,
                                                 поручень-труба, провисшая цепь между стойками и две вертикальные цепи;
                                                 origin — центр основания (ставить на настил: z = ±0.9 — край, z = 0 — барьер)
    K20 Chain_Hook      (1372)  0.4 × 2.9 × 0.3  цепь с крюком: крепёжная плита на 4 болтах с проушиной и серьгой, цепь
                                                 2.2 м, красная крашеная бирка, J-крюк; origin — верхняя плоскость плиты
                                                 (точка подвеса), всё висит вниз до y ≈ −2.9
    K21 Hanging_Beam    (2572)  4 × 2.9 × 0.44   балка 4.0 × 0.34 с узлами на концах, серьги и две цепи вверх от x = ±1.7 до
                                                 колец-анкеров под плитами на y = +2.0, под концами короткие цепи с крюками;
                                                 origin — центр ВЕРХА балки (y = 0 — по ней ходят). В этой волне — статика
                                                 (StaticBody3D); маятник на цепях — позже (волна 2, M)
    K22 Ladder          (972)   0.76 × 3.2 × 0.3 лестница 3.0 м: тетивы из тёмных досок с железными бандажами, 9 перекладин
                                                 через 0.3 м на болтах, крюки-зацепы сверху (загнуты назад, −z), башмаки;
                                                 origin — центр основания

Сцены (StaticBody3D + упрощённые коллизии, пересекающие z = 0; Chain_Hook — Node3D без коллизии) собирает
tools/build_scrap_kit_scenes.gd → scenes/props/scrap/kit_<name>.tscn; проба tests/scrap_kit_probe.tscn.
"""
import math
import os
import random
import sys
import tempfile
import zlib

import bpy
import bmesh
from mathutils import Matrix, Vector, Euler, Quaternion

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import common as C  # noqa: E402

GODOT = os.path.abspath(os.path.join(HERE, "..", ".."))
REPO = os.path.abspath(os.path.join(GODOT, ".."))
OUT = os.path.join(GODOT, "assets", "models", "scrap", "kit")
CROWN_PNG = os.path.join(GODOT, "assets", "textures", "decals", "crown.png")
RENDER_PNG = os.path.join(REPO, "docs", "plan-demo", "img", "scrap-kit-v1.png")
TRI_BUDGET = 3000
TEX_SIZE = int(os.environ.get("SCRAP_KIT_TEX", "1024"))
IMG_FORMAT = os.environ.get("SCRAP_KIT_IMG", "WEBP")
CACHE = os.environ.get("SCRAP_KIT_CACHE") or os.path.join(tempfile.gettempdir(), "ragdoll_scrap_kit_pbr")
FORCE_FLAT = os.environ.get("SCRAP_FLAT") == "1"
TAU = 2.0 * math.pi
RNG = random.Random(1)

# ----------------------------------------------------------------------------------------------------------------------
# размеры snap-системы (Blender: X вбок, Y глубина (−Y к камере), Z вверх)
# ----------------------------------------------------------------------------------------------------------------------
PLANK_T = 0.07                    # толщина досок настила
BEAM_Y = 0.93                     # центр продольных балок по глубине (±)
BEAM_D = 0.14                     # толщина балки по глубине
BEAM_H = 0.34                     # высота балки
BEAM_TOP = 0.0                    # верх балок заподлицо с настилом (доски лежат между балками на поперечинах)
BEAM_BOT = BEAM_TOP - BEAM_H      # −0.34
PLANK_Y = BEAM_Y - BEAM_D / 2 - 0.006   # доски по глубине ±0.854
NODE = 0.44                       # узел-соединитель (куб)
NODE_TOP = 0.06                   # верх узла выше настила
NODE_BOT = NODE_TOP - NODE        # −0.38
LEG = 0.22                        # сечение ноги
FOOT = 0.38                       # подошва
FOOT_T = 0.06
CHAIN_R, CHAIN_r = 0.042, 0.013   # звено цепи по умолчанию (радиус оси, радиус прутка)
LINK_PITCH = 2.0 * (1.45 * CHAIN_R - CHAIN_r)   # шаг сцепленных звеньев ≈ 0.096


# ----------------------------------------------------------------------------------------------------------------------
# материалы
# ----------------------------------------------------------------------------------------------------------------------
# имя → (папка PBR, kwargs textured_material, плоский запасной (base RGBA, roughness, metallic))
MAT_DEFS = {
    "RustIron": ("rust_metal", {}, ((0.22, 0.12, 0.07, 1.0), 0.78, 0.45)),
    "RustIronDark": ("rust_metal", {"tint": (0.66, 0.62, 0.62, 1.0), "roughness_scale": 1.05},
                     ((0.13, 0.08, 0.055, 1.0), 0.85, 0.4)),
    "RustRed": ("rust_painted_red", {}, ((0.40, 0.07, 0.05, 1.0), 0.62, 0.1)),
    "ScrapWood": ("scrap_wood", {"tint": (0.82, 0.76, 0.72, 1.0)}, ((0.29, 0.23, 0.18, 1.0), 0.86, 0.0)),
    "ScrapWoodDark": ("scrap_wood", {"tint": (0.56, 0.50, 0.48, 1.0)}, ((0.20, 0.16, 0.13, 1.0), 0.9, 0.0)),
    "Brass": ("brass_worn", {}, ((0.55, 0.40, 0.17, 1.0), 0.42, 0.9)),
    "Banner": ("fabric_red", {"tint": (0.70, 0.54, 0.52, 1.0)}, ((0.50, 0.05, 0.04, 1.0), 0.9, 0.0)),
}
# карты, без которых набор считается «ещё не испечённым»
REQUIRED = {
    "rust_metal": ("albedo", "roughness", "normal", "metallic"),
    "rust_painted_red": ("albedo", "roughness", "normal", "metallic"),
    "scrap_wood": ("albedo", "roughness", "normal"),
    "brass_worn": ("albedo", "roughness", "normal", "metallic"),
    "fabric_red": ("albedo", "roughness", "normal"),
}
_MATS = {}
FLAT_USED = set()


def pbr_ready(folder):
    src = os.path.join(C.PBR_DIR, folder)
    return all(os.path.exists(os.path.join(src, ch + ".png")) for ch in REQUIRED.get(folder, ("albedo",)))


def pbr_folder(name):
    """Папка PBR-набора: исходная (2048²) или уменьшенная копия в кэше (TEX_SIZE) — как в workshop_props.py."""
    src = os.path.join(C.PBR_DIR, name)
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
    if name in _MATS:
        return _MATS[name]
    if name == "Crown":
        m = crown_material()
    else:
        folder, kw, flat = MAT_DEFS[name]
        if not FORCE_FLAT and pbr_ready(folder):
            m = C.textured_material(name, pbr_folder(folder), **kw)
        else:
            FLAT_USED.add(name + " (" + folder + ")")
            base, rough, metal = flat
            m = C.material(name, base, rough, metal)
        m.use_backface_culling = name != "Banner"
    _MATS[name] = m
    return m


def crown_material():
    """Декаль короны: crown.png → Base Color, альфа через Math Round (glTF alphaMode MASK, cutoff 0.5)."""
    mat = bpy.data.materials.new("Crown")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    tex = nt.nodes.new('ShaderNodeTexImage')
    tex.image = C._load_packed(CROWN_PNG)
    tex.extension = 'CLIP'
    rnd = nt.nodes.new('ShaderNodeMath')
    rnd.operation = 'ROUND'
    mix = nt.nodes.new('ShaderNodeMix')                   # кремово-золотой тон (→ baseColorFactor)
    mix.data_type = 'RGBA'
    mix.blend_type = 'MULTIPLY'
    mix.inputs[0].default_value = 1.0
    mix.inputs[7].default_value = (1.0, 0.80, 0.52, 1.0)
    nt.links.new(tex.outputs['Color'], mix.inputs[6])
    nt.links.new(mix.outputs[2], bsdf.inputs['Base Color'])
    nt.links.new(tex.outputs['Alpha'], rnd.inputs[0])
    nt.links.new(rnd.outputs[0], bsdf.inputs['Alpha'])
    bsdf.inputs['Roughness'].default_value = 0.85
    bsdf.inputs['Metallic'].default_value = 0.0
    for attr, val in (('surface_render_method', 'DITHERED'), ('blend_method', 'CLIP')):
        try:
            setattr(mat, attr, val)
        except Exception:
            pass
    mat.use_backface_culling = True
    return mat


# ----------------------------------------------------------------------------------------------------------------------
# геометрия: временные bmesh-детали в локальных координатах → Kit.add() впекает трансформ и материал
# ----------------------------------------------------------------------------------------------------------------------
AXV = {'+X': Vector((1, 0, 0)), '-X': Vector((-1, 0, 0)), '+Y': Vector((0, 1, 0)), '-Y': Vector((0, -1, 0)),
       '+Z': Vector((0, 0, 1)), '-Z': Vector((0, 0, -1))}
FRONT = Vector((0, -1, 0))


def _rot4(rot):
    if rot is None:
        return Matrix.Identity(4)
    if isinstance(rot, Matrix):
        return rot.to_4x4() if len(rot) == 3 else rot
    if isinstance(rot, Quaternion):
        return rot.to_matrix().to_4x4()
    return Euler(rot, 'XYZ').to_matrix().to_4x4()


def align_z(n):
    """Поворот, переводящий +Z в направление n."""
    return Vector((0, 0, 1)).rotation_difference(Vector(n).normalized()).to_matrix().to_4x4()


def frame_x(d, face=FRONT):
    """Поворот: локальная X → d, локальная Z (нормаль плоскости детали) → как можно ближе к `face`."""
    d = Vector(d).normalized()
    n = Vector(face) - Vector(face).dot(d) * d
    if n.length < 1e-4:
        n = Vector((0, 0, 1)) - d.z * d
    n.normalize()
    y = n.cross(d)
    m = Matrix.Identity(3)
    m.col[0] = d
    m.col[1] = y
    m.col[2] = n
    return m.to_4x4()


def uv_box_bm(bm, along='Z', du=0.0, dv=0.0, scale=1.0):
    """Кубическая проекция в локальных метрах (как common.uv_box): ось `along` → V (волокна/подтёки)."""
    uvl = bm.loops.layers.uv.verify()
    ai = 'XYZ'.index(along)
    bm.normal_update()
    for f in bm.faces:
        n = f.normal
        ax = max(range(3), key=lambda k: abs(n[k]))
        rest = [k for k in range(3) if k != ax]
        if ai in rest:
            vax = ai
            uax = rest[0] if rest[1] == ai else rest[1]
        else:
            uax, vax = rest
        for lo in f.loops:
            co = lo.vert.co
            lo[uvl].uv = (co[uax] * scale + du, co[vax] * scale + dv)


def _face_toward(bm, axis):
    n = AXV[axis]
    bm.normal_update()
    cand = [f for f in bm.faces if f.normal.dot(n) > 0.999]
    return max(cand, key=lambda f: f.calc_area()) if cand else None


def _bevel(bm, width):
    bmesh.ops.bevel(bm, geom=list(bm.verts) + list(bm.edges), offset=width, offset_type='OFFSET', segments=1,
                    profile=0.5, affect='EDGES', clamp_overlap=True)


def g_box(sx, sy, sz, bevel=0.0, inset=(), border=0.04, depth=0.015, drop=()):
    """Брус sx × sy × sz с центром в нуле; bevel — фаска; inset — грани ('-Y', '+X', …), утопленные на depth с бортиком
    border (гнездо узла, полка швеллера); drop — убрать невидимые грани (снизу доски и т. п.)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * sx, v.co.y * sy, v.co.z * sz))
    if bevel > 0.0:
        _bevel(bm, bevel)
    for ax in inset:
        f = _face_toward(bm, ax)
        if f is not None:
            bmesh.ops.inset_individual(bm, faces=[f], thickness=border, depth=-depth, use_even_offset=True)
    for ax in drop:
        f = _face_toward(bm, ax)
        if f is not None:
            bmesh.ops.delete(bm, geom=[f], context='FACES_ONLY')
    return bm


def g_prism(pts, t, bevel=0.0):
    """Плоская деталь: многоугольник [(x, z), …] в плоскости XZ толщиной t по Y (центр по Y в нуле)."""
    bm = bmesh.new()
    fr = [bm.verts.new((x, -t / 2, z)) for x, z in pts]
    bk = [bm.verts.new((x, t / 2, z)) for x, z in pts]
    bm.faces.new(fr)
    bm.faces.new(list(reversed(bk)))
    n = len(pts)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((fr[j], fr[i], bk[i], bk[j]))
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    if bevel > 0.0:
        _bevel(bm, bevel)
    return bm


def g_lathe(profile, segs=8, phase=0.0):
    """Тело вращения вокруг Z из профиля [(r, z), …]; r = 0 — полюс."""
    bm = bmesh.new()
    rings = []
    for r, z in profile:
        if r < 1e-6:
            rings.append([bm.verts.new((0.0, 0.0, z))])
        else:
            rings.append([bm.verts.new((r * math.cos(TAU * i / segs + phase), r * math.sin(TAU * i / segs + phase), z))
                          for i in range(segs)])
    for a, b in zip(rings, rings[1:]):
        for i in range(segs):
            j = (i + 1) % segs
            if len(a) == 1 and len(b) == 1:
                continue
            if len(a) == 1:
                bm.faces.new((a[0], b[i], b[j]))
            elif len(b) == 1:
                bm.faces.new((a[i], a[j], b[0]))
            else:
                bm.faces.new((a[i], a[j], b[j], b[i]))
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return bm


def g_cyl(r, length, segs=8, caps=True):
    """Цилиндр вдоль X (трубы, штанги, поручни), центр в нуле."""
    h = length / 2
    prof = [(0.0, -h), (r, -h), (r, h), (0.0, h)] if caps else [(r, -h), (r, h)]
    bm = g_lathe(prof, segs, phase=math.pi / segs)
    bmesh.ops.transform(bm, matrix=Matrix.Rotation(math.pi / 2, 4, 'Y'), verts=list(bm.verts))
    return bm


def g_torus(R, r, segs=10, ring=4, stretch=1.0):
    """Тор в плоскости XY (нормаль +Z), вытянут вдоль X в stretch раз (звено цепи)."""
    bm = bmesh.new()
    grid = []
    for i in range(segs):
        th = TAU * i / segs
        row = []
        for j in range(ring):
            ph = TAU * j / ring + math.pi / ring
            rr = R + r * math.cos(ph)
            x = rr * math.cos(th)
            y = rr * math.sin(th)
            if stretch != 1.0:
                x += math.copysign((stretch - 1.0) * R, x) if abs(x) > 1e-6 else 0.0
            row.append(bm.verts.new((x, y, r * math.sin(ph))))
        grid.append(row)
    for i in range(segs):
        i2 = (i + 1) % segs
        for j in range(ring):
            j2 = (j + 1) % ring
            bm.faces.new((grid[i][j], grid[i2][j], grid[i2][j2], grid[i][j2]))
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return bm


def g_tube(pts, radii, sides=6, cap0=True, tip=True):
    """Труба вдоль ломаной pts (Vector) с радиусами radii; параллельный перенос рамки; tip — конец сходится в точку."""
    bm = bmesh.new()
    pts = [Vector(p) for p in pts]
    n = len(pts)
    tans = []
    for i in range(n):
        a = pts[max(0, i - 1)]
        b = pts[min(n - 1, i + 1)]
        tans.append((b - a).normalized())
    ref = Vector((0, -1, 0)) if abs(tans[0].y) < 0.9 else Vector((1, 0, 0))
    u = (ref - ref.dot(tans[0]) * tans[0]).normalized()
    rings = []
    for i in range(n):
        if i > 0:
            u = (u - u.dot(tans[i]) * tans[i]).normalized()
        v = tans[i].cross(u)
        if tip and i == n - 1:
            rings.append([bm.verts.new(pts[i])])
            continue
        rings.append([bm.verts.new(pts[i] + radii[i] * (math.cos(TAU * k / sides) * u + math.sin(TAU * k / sides) * v))
                      for k in range(sides)])
    for a, b in zip(rings, rings[1:]):
        for k in range(sides):
            k2 = (k + 1) % sides
            if len(b) == 1:
                bm.faces.new((a[k], a[k2], b[0]))
            else:
                bm.faces.new((a[k], a[k2], b[k2], b[k]))
    if cap0:
        bm.faces.new(list(reversed(rings[0])))
    if not tip:
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return bm


class Kit:
    """Накопитель геометрии одного модуля: все детали — в один bmesh, материалы — слотами."""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.mats = []
        self.xf = Matrix.Identity(4)

    def slot(self, mat):
        if mat not in self.mats:
            self.mats.append(mat)
        return self.mats.index(mat)

    def add(self, g, mat, loc=(0, 0, 0), rot=None, along='Z', du=None, dv=None, uv=True, xf=None):
        if uv:
            uv_box_bm(g, along, RNG.random() if du is None else du, RNG.random() if dv is None else dv)
        m = (self.xf if xf is None else xf) @ Matrix.Translation(Vector(loc)) @ _rot4(rot)
        bmesh.ops.transform(g, matrix=m, verts=list(g.verts))
        if m.to_3x3().determinant() < 0.0:
            bmesh.ops.reverse_faces(g, faces=list(g.faces))
        idx = self.slot(mat)
        src_uv = g.loops.layers.uv.active
        vmap = {v: self.bm.verts.new(v.co) for v in g.verts}
        for f in g.faces:
            try:
                nf = self.bm.faces.new([vmap[v] for v in f.verts])
            except ValueError:
                continue
            nf.material_index = idx
            nf.smooth = True
            if src_uv is not None:
                for a, b in zip(nf.loops, f.loops):
                    a[self.uv].uv = b[src_uv].uv
        g.free()

    def finish(self, sharp_deg=32.0):
        bm = self.bm
        bm.normal_update()
        lim = math.radians(sharp_deg)
        for e in bm.edges:
            if len(e.link_faces) == 2:
                try:
                    e.smooth = e.calc_face_angle() < lim
                except ValueError:
                    e.smooth = False
        me = bpy.data.meshes.new(self.name)
        bm.to_mesh(me)
        bm.free()
        for n in self.mats:
            me.materials.append(M(n))
        o = bpy.data.objects.new(self.name, me)
        bpy.context.scene.collection.objects.link(o)
        return o


# ----------------------------------------------------------------------------------------------------------------------
# мелкие детали
# ----------------------------------------------------------------------------------------------------------------------
def rivet(K, loc, n=FRONT, r=0.024, h=0.015, mat="RustIron"):
    """Заклёпка: шестигранная полукруглая головка без дна (16 треугольников)."""
    g = g_lathe([(r, 0.0), (r * 0.62, h), (0.0, h * 1.12)], segs=6)
    K.add(g, mat, loc=loc, rot=align_z(n))


def bolt(K, loc, n=FRONT, s=0.034, h=0.018, mat="RustIron"):
    """Квадратная головка болта (10 треугольников)."""
    g = g_lathe([(s * 0.71, 0.0), (s * 0.55, h), (0.0, h)], segs=4, phase=math.pi / 4)
    K.add(g, mat, loc=loc, rot=align_z(n) @ Matrix.Rotation(RNG.uniform(-0.2, 0.2), 4, 'Z'))


def chain(K, pts, mat="RustIronDark", R=CHAIN_R, r=CHAIN_r, segs=6, ring=4, pitch=None, face=FRONT, twist0=0):
    """Цепь вдоль ломаной pts: овальные звенья (торы, вытянутые в 1.45 раза), сцеплены — шаг 2·(1.45R − r); чётные —
    плоскостью к камере (видна дырка), нечётные — ребром. Возвращает точку конца последнего звена."""
    if pitch is None:
        pitch = 2.0 * (1.45 * R - r)
    pts = [Vector(p) for p in pts]
    segl = [(b - a).length for a, b in zip(pts, pts[1:])]
    total = sum(segl)
    n = max(1, int(total / pitch))
    end = pts[0]
    for k in range(n):
        s = (k + 0.5) * total / n
        acc = 0.0
        for i, L in enumerate(segl):
            if acc + L >= s or i == len(segl) - 1:
                t = (s - acc) / L if L > 1e-9 else 0.0
                p = pts[i].lerp(pts[i + 1], t)
                d = (pts[i + 1] - pts[i]).normalized()
                break
            acc += L
        m = frame_x(d, face)
        if (k + twist0) % 2:
            m = m @ Matrix.Rotation(math.pi / 2, 4, 'X')
        m = m @ Matrix.Rotation(RNG.uniform(-0.12, 0.12), 4, 'X')
        g = g_torus(R, r, segs, ring, stretch=1.45)
        K.add(g, mat, loc=p, rot=m)
        end = p + d * (total / n) * 0.5
    return end


def catenary(p0, p1, sag, n=16):
    """Точки провисшей цепи между p0 и p1 (парабола, провис sag в середине)."""
    p0, p1 = Vector(p0), Vector(p1)
    return [p0.lerp(p1, i / n) - Vector((0, 0, 4.0 * sag * (i / n) * (1 - i / n))) for i in range(n + 1)]


def hook(K, top, scale=1.0, mat="RustIron", flip=1.0):
    """Крюк-«J» в плоскости XZ (виден силуэтом с камеры): ушко, стержень, дуга 234°, заострённый носик; flip = −1 —
    зев влево. top — точка подвеса (верх ушка); возвращает нижнюю точку дуги."""
    top = Vector(top)
    s = scale
    eye = g_torus(0.034 * s, 0.011 * s, 8, 4)
    K.add(eye, mat, loc=top + Vector((0, 0, -0.034 * s)), rot=(math.pi / 2, 0, 0))
    z0 = -0.066 * s
    R = 0.085 * s
    pts = [Vector((0, 0, z0 - 0.09 * s * i)) for i in range(3)]
    rad = [0.019 * s] * 3
    cz = z0 - 0.18 * s
    n = 9
    for i in range(1, n + 1):
        a = math.pi + 1.3 * math.pi * i / n
        pts.append(Vector((flip * (R + R * math.cos(a)), 0, cz + R * math.sin(a))))
        rad.append(0.019 * s * (1.0 - 0.55 * i / n))
    K.add(g_tube([top + p for p in pts], rad, sides=6, cap0=True, tip=True), mat)
    return top + Vector((0, 0, cz - R))


def lug_ring(K, x_face, sgn, y, z, mat="RustIron", ring_mat="RustIron"):
    """Проушина на торце узла: язычок и кольцо, развёрнутое на ~35° к камере."""
    K.add(g_box(0.11, 0.05, 0.11, bevel=0.01), mat, loc=(x_face + sgn * 0.05, y, z))
    rg = g_torus(0.074, 0.018, 12, 4)
    K.add(rg, ring_mat, loc=(x_face + sgn * 0.115, y, z - 0.062), rot=(math.pi / 2, 0, sgn * 0.62))


def gusset(K, x, y, z, sgn, size=0.18, t=0.03, mat="RustIronDark"):
    """Косынка-треугольник под балкой у ноги (вершина прямого угла в (x, z))."""
    K.add(g_prism([(0, 0), (sgn * size, 0), (0, -size)], t), mat, loc=(x, y, z))


def flat_bar(K, p0, p1, w=0.09, t=0.04, y=0.0, mat="RustIron", bevel=0.008, bolts=True):
    """Плоская полоса (раскос, стяжка) в плоскости XZ от p0 до p1 = (x, z), по центру y; болты на концах."""
    a = Vector((p0[0], y, p0[1]))
    b = Vector((p1[0], y, p1[1]))
    d = b - a
    L = d.length
    g = g_box(L, t, w, bevel=bevel)
    ang = math.atan2(d.z, d.x)
    K.add(g, mat, loc=(a + b) / 2, rot=(0, -ang, 0), along='X')
    if bolts:
        for p in (a + d.normalized() * 0.06, b - d.normalized() * 0.06):
            bolt(K, p + Vector((0, -t / 2, 0)), s=0.028, h=0.014)


# ----------------------------------------------------------------------------------------------------------------------
# типовые узлы платформ
# ----------------------------------------------------------------------------------------------------------------------
def plank_deck(K, x0, x1, top=0.0, y0=-PLANK_Y, y1=PLANK_Y, lengths=None):
    """Настил: доски поперёк глубины (вдоль Y), ширина ≤ 0.24 (одна доска текстуры), щели 12 мм, разнобой по длине,
    высоте (−1 см) и наклону; 30 % досок темнее. lengths(i, cx) → (y0, y1) — свои концы (рваные края)."""
    span = x1 - x0
    n = max(1, int(math.ceil(span / 0.22)))
    ws = [RNG.uniform(0.86, 1.14) for _ in range(n)]
    s = sum(ws)
    ws = [w * span / s for w in ws]
    x = x0
    for i, w in enumerate(ws):
        cx = x + w / 2
        a, b = (y0, y1) if lengths is None else lengths(i, cx)
        a += RNG.uniform(-0.02, 0.03)
        b += RNG.uniform(-0.03, 0.02)
        g = g_box(w - 0.012, b - a, PLANK_T, drop=('-Z',))
        mat = "ScrapWoodDark" if RNG.random() < 0.3 else "ScrapWood"
        k = RNG.randrange(4)
        K.add(g, mat, loc=(cx, (a + b) / 2, top - PLANK_T / 2 - RNG.uniform(0.0, 0.01)),
              rot=(RNG.uniform(-0.008, 0.008), RNG.uniform(-0.02, 0.02), RNG.uniform(-0.008, 0.008)),
              along='Y', du=(k + 0.5) / 4.0, dv=RNG.random())
        x += w


def deck_straps(K, x0, x1, ys=(-0.6, 0.6), top=0.0):
    """Железные полосы поверх досок вдоль X с заклёпками через ~1 м."""
    L = x1 - x0 - 0.12
    for y in ys:
        K.add(g_box(L, 0.07, 0.012, drop=('-Z',)), "RustIronDark", loc=((x0 + x1) / 2, y + RNG.uniform(-0.02, 0.02), top + 0.004),
              rot=(0, 0, RNG.uniform(-0.006, 0.006)), along='X')
        n = max(1, int(round(L / 1.0)))
        for i in range(n + 1):
            bolt(K, (x0 + 0.06 + L * i / n, y, top + 0.01), (0, 0, 1), s=0.022, h=0.01)


def cross_strap(K, x, top=0.0):
    """Поперечная железная полоса поверх досок на линии узла (делит настил на панели, как на листе) + 3 болта."""
    K.add(g_box(0.085, 2 * PLANK_Y, 0.012, drop=('-Z',)), "RustIronDark", loc=(x + RNG.uniform(-0.01, 0.01), 0, top + 0.004),
          rot=(0, 0, RNG.uniform(-0.01, 0.01)), along='Y')
    for y in (-0.55, 0.0, 0.55):
        bolt(K, (x, y, top + 0.01), (0, 0, 1), s=0.024, h=0.01)


def beam_x(K, x0, x1, y, front, z_top=BEAM_TOP, h=BEAM_H, d=BEAM_D, skip=(), mat="RustIron"):
    """Продольная балка-швеллер: передняя — с фаской, утопленной стенкой и двумя рядами заклёпок по полкам;
    задняя — простой брус без невидимых граней."""
    L = x1 - x0
    if front:
        K.add(g_box(L, d, h, bevel=0.012, inset=('-Y',), border=0.045, depth=0.018), mat,
              loc=((x0 + x1) / 2, y, z_top - h / 2), along='Z')
        n = max(1, int(round(L / 0.5)))
        for i in range(n):
            x = x0 + (i + 0.5) * L / n
            if any(abs(x - s) < 0.30 for s in skip):
                continue
            for zz in (z_top - 0.022, z_top - h + 0.022):
                rivet(K, (x, y - d / 2, zz))
    else:
        K.add(g_box(L, d, h, drop=('+Y',)), mat, loc=((x0 + x1) / 2, y, z_top - h / 2))


def node(K, x, y, z_top=NODE_TOP, s=NODE, h=None, front=True, mat="RustIron", sides=()):
    """Узел-соединитель: куб с фаской, гнездо на лицевой грани (и на торцах sides), два болта по диагонали."""
    h = h or s
    zc = z_top - h / 2
    if front:
        K.add(g_box(s, s, h, bevel=0.02, inset=('-Y',) + tuple(sides), border=0.07, depth=0.03), mat, loc=(x, y, zc))
        for dx, dz in ((-1, 1), (1, -1)):
            bolt(K, (x + dx * (s / 2 - 0.038), y - s / 2, zc + dz * (h / 2 - 0.038)))
    else:
        K.add(g_box(s, s, h, drop=('+Y',)), mat, loc=(x, y, zc))


def leg(K, x, y, z_top, z_bot, front=True, mat="RustIronDark", gussets=True):
    """Нога: стойка-швеллер, подошва с болтами, косынки под балкой; z_bot — низ подошвы."""
    ph = z_top - (z_bot + FOOT_T)
    zc = z_bot + FOOT_T + ph / 2
    if front:
        K.add(g_box(LEG, LEG, ph, bevel=0.012, inset=('-Y',), border=0.04, depth=0.015), mat, loc=(x, y, zc))
        K.add(g_box(FOOT, FOOT, FOOT_T, bevel=0.012), "RustIron", loc=(x, y, z_bot + FOOT_T / 2))
        for dx in (-1, 1):
            bolt(K, (x + dx * 0.135, y - 0.12, z_bot + FOOT_T), (0, 0, 1), s=0.03, h=0.016)
        if gussets:
            for sg in (-1, 1):
                gusset(K, x + sg * LEG / 2, y - 0.03, z_top, sg)
    else:
        K.add(g_box(LEG, LEG, ph, drop=('+Z', '-Z', '+Y')), mat, loc=(x, y, zc))
        K.add(g_box(FOOT, FOOT, FOOT_T, drop=('-Z',)), "RustIron", loc=(x, y, z_bot + FOOT_T / 2))


def cross_beam(K, x, z_top=-PLANK_T):
    K.add(g_box(0.12, 2 * BEAM_Y - BEAM_D, 0.14, drop=('+Z',)), "RustIronDark", loc=(x, 0, z_top - 0.07))


def frame_span(K, x0, x1, nodes, legs, foot_z, leg_front=True, skip_back_nodes=False):
    """Балки спереди/сзади, узлы, поперечины и ноги пролёта x0..x1."""
    for yy, fr in ((-BEAM_Y, True), (BEAM_Y, False)):
        beam_x(K, x0 + 0.01, x1 - 0.01, yy, fr, skip=nodes)
        for x in nodes:
            if fr or not skip_back_nodes:
                node(K, x, yy, front=fr)
    for x in nodes:
        cross_beam(K, x)
        cross_strap(K, x)
    for x in legs:
        leg(K, x, -BEAM_Y, NODE_BOT, foot_z, True)
        leg(K, x, BEAM_Y, NODE_BOT, foot_z, False)


def dangle(K, x, z, n, y=-BEAM_Y - BEAM_D / 2 - 0.02, with_hook=False, ring=4):
    """Обрывок цепи под балкой (n звеньев), опционально с крюком."""
    top = Vector((x, y, z))
    end = chain(K, [top, top + Vector((RNG.uniform(-0.03, 0.03), 0, -n * LINK_PITCH))], ring=ring)
    if with_hook:
        hook(K, end, 0.8)


# ----------------------------------------------------------------------------------------------------------------------
# K01–K03, K07: прямые платформы
# ----------------------------------------------------------------------------------------------------------------------
def platform(name, L=2.0):
    K = Kit(name)
    x0, x1 = -L / 2, L / 2
    ends = [x0 + NODE / 2, x1 - NODE / 2]
    inner = [x0 + 2.0 * k for k in range(1, int(round(L / 2)))]
    nodes = ends + inner
    plank_deck(K, x0, x1)
    deck_straps(K, x0, x1)
    frame_span(K, x0, x1, nodes, nodes, -1.0)
    for sg, x in ((-1, x0), (1, x1)):
        lug_ring(K, x, sg, -BEAM_Y, -0.14)
    if L <= 2.0:
        flat_bar(K, (ends[0], -0.72), (ends[1], -0.72), w=0.08, t=0.035, y=-BEAM_Y - LEG / 2 - 0.02)
        dangle(K, 0.25, BEAM_BOT, 3)
    else:
        spots = [x0 + 1.0 + 2.0 * k for k in range(int(round(L / 2)))]
        for i, x in enumerate(spots):
            dangle(K, x + RNG.uniform(-0.3, 0.3), BEAM_BOT, 2 + (i % 2), with_hook=(i == 1))
    return K.finish()


def platform_lower(name, L=2.0, H=0.5):
    K = Kit(name)
    x0, x1 = -L / 2, L / 2
    ends = [x0 + NODE / 2, x1 - NODE / 2]
    plank_deck(K, x0, x1)
    deck_straps(K, x0, x1)
    for yy, fr in ((-BEAM_Y, True), (BEAM_Y, False)):
        beam_x(K, x0 + NODE - 0.02, x1 - NODE + 0.02, yy, fr, skip=ends)
        for x in ends:
            node(K, x, yy, z_top=NODE_TOP, h=NODE_TOP + H - FOOT_T, front=fr)
            if fr:
                K.add(g_box(FOOT + 0.04, FOOT + 0.04, FOOT_T, bevel=0.012), "RustIronDark", loc=(x, yy, -H + FOOT_T / 2))
                for dx in (-1, 1):
                    bolt(K, (x + dx * 0.15, yy - 0.14, -H + FOOT_T), (0, 0, 1), s=0.03, h=0.016)
            else:
                K.add(g_box(FOOT + 0.04, FOOT + 0.04, FOOT_T, drop=('-Z',)), "RustIronDark", loc=(x, yy, -H + FOOT_T / 2))
    for x in ends:
        cross_beam(K, x)
        cross_strap(K, x)
    cross_beam(K, 0.0)
    for sg, x in ((-1, x0), (1, x1)):
        lug_ring(K, x, sg, -BEAM_Y, -0.14)
    return K.finish()


# ----------------------------------------------------------------------------------------------------------------------
# K08: высокая платформа на раме с крестом
# ----------------------------------------------------------------------------------------------------------------------
def platform_upper(name, L=2.0, H=2.0):
    K = Kit(name)
    x0, x1 = -L / 2, L / 2
    ends = [x0 + NODE / 2, x1 - NODE / 2]
    plank_deck(K, x0, x1)
    deck_straps(K, x0, x1)
    frame_span(K, x0, x1, ends, ends, -H)
    xa, xb = ends
    for yy, fr in ((-BEAM_Y, True), (BEAM_Y, False)):
        yb = yy - (LEG / 2 + 0.025) * (1 if fr else -1)
        if fr:
            flat_bar(K, (xa + 0.02, -H + 0.3), (xb - 0.02, NODE_BOT - 0.08), w=0.11, t=0.04, y=yb)
            flat_bar(K, (xa + 0.02, NODE_BOT - 0.08), (xb - 0.02, -H + 0.3), w=0.11, t=0.04, y=yb - 0.02)
            flat_bar(K, (xa - 0.05, -H + 0.26), (xb + 0.05, -H + 0.26), w=0.10, t=0.04, y=yb - 0.01)
            mz = (-H + 0.3 + NODE_BOT - 0.08) / 2
            K.add(g_box(0.12, 0.03, 0.12, bevel=0.01), "RustIron", loc=(0, yb - 0.045, mz), rot=(0, math.pi / 4, 0))
            bolt(K, (0, yb - 0.06, mz), s=0.04, h=0.02)
        else:
            for p0, p1 in (((xa, -H + 0.3), (xb, NODE_BOT - 0.08)), ((xa, NODE_BOT - 0.08), (xb, -H + 0.3))):
                d = Vector((p1[0] - p0[0], 0, p1[1] - p0[1]))
                K.add(g_box(d.length, 0.04, 0.11, drop=('+Y',)), "RustIron", loc=((p0[0] + p1[0]) / 2, yb, (p0[1] + p1[1]) / 2),
                      rot=(0, -math.atan2(d.z, d.x), 0))
    # стяжки по глубине у земли
    for x in ends:
        K.add(g_box(0.08, 2 * BEAM_Y - LEG, 0.10, drop=('-Z',)), "RustIronDark", loc=(x, 0, -H + 0.3))
    for sg, x in ((-1, x0), (1, x1)):
        lug_ring(K, x, sg, -BEAM_Y, -0.14)
    dangle(K, -0.3, BEAM_BOT, 2)
    return K.finish()


# ----------------------------------------------------------------------------------------------------------------------
# K04 / K05: концы пролёта
# ----------------------------------------------------------------------------------------------------------------------
def platform_end(name, side=-1, L=2.0):
    """side = −1: свободный торец слева (Platform_End_L), +1 — справа (Platform_End_R)."""
    K = Kit(name)
    x0, x1 = -L / 2, L / 2
    xf = side * (L / 2 - NODE / 2)          # узел свободного торца
    xj = -xf                                # узел стыкового торца
    plank_deck(K, x0, x1)
    deck_straps(K, x0, x1)
    nodes = [xf, xj]
    for yy, fr in ((-BEAM_Y, True), (BEAM_Y, False)):
        beam_x(K, x0 + 0.01, x1 - 0.01, yy, fr, skip=nodes)
        for x in nodes:
            node(K, x, yy, front=fr, sides=(('-X',) if side < 0 else ('+X',)) if (fr and x == xf) else ())
    for x in nodes:
        cross_beam(K, x)
        cross_strap(K, x)
    # стыковой конец: обычная нога
    leg(K, xj, -BEAM_Y, NODE_BOT, -1.0, True)
    leg(K, xj, BEAM_Y, NODE_BOT, -1.0, False)
    # свободный конец: скошенная нога (подошва разведена наружу)
    top = Vector((xf - side * 0.02, 0, NODE_BOT))
    foot = Vector((side * (L / 2 + 0.06), 0, -1.0 + FOOT_T))
    d = top - foot
    ang = math.atan2(d.z, d.x)
    for yy, fr in ((-BEAM_Y, True), (BEAM_Y, False)):
        g = g_box(d.length + 0.02, LEG, LEG * 0.95, bevel=0.012 if fr else 0.0, inset=('-Y',) if fr else (), border=0.04, depth=0.015)
        K.add(g, "RustIronDark", loc=Vector((0, yy, 0)) + (top + foot) / 2, rot=(0, -ang, 0), along='X')
        if fr:
            K.add(g_box(FOOT, FOOT, FOOT_T, bevel=0.012), "RustIron", loc=(foot.x, yy, -1.0 + FOOT_T / 2))
            for dx in (-1, 1):
                bolt(K, (foot.x + dx * 0.135, yy - 0.12, -1.0 + FOOT_T), (0, 0, 1), s=0.03, h=0.016)
        else:
            K.add(g_box(FOOT, FOOT, FOOT_T, drop=('-Z',)), "RustIron", loc=(foot.x, yy, -1.0 + FOOT_T / 2))
    # раскос: от подошвы стыковой ноги к свободному узлу
    yb = -BEAM_Y - LEG / 2 - 0.03
    flat_bar(K, (xj - side * 0.05, -0.86), (xf + side * 0.05, NODE_BOT - 0.03), w=0.10, t=0.04, y=yb)
    K.add(g_box(0.09, 2 * BEAM_Y - LEG, 0.10, drop=('-Z',)), "RustIronDark", loc=(xj, 0, -0.72))
    # торцевая плита (красная краска по ржавчине) и проушина с цепью и крюком
    xe = side * (L / 2 + 0.03)
    K.add(g_box(0.06, 2.0, NODE_TOP - BEAM_BOT, bevel=0.012), "RustRed", loc=(xe, 0, (NODE_TOP + BEAM_BOT) / 2), along='Y')
    for yy in (-0.6, 0.0, 0.6):
        for zz in (-0.0, -0.26):
            bolt(K, (xe + side * 0.03, yy, zz), (side, 0, 0), s=0.03, h=0.016)
    lug_ring(K, xe + side * 0.03, side, -BEAM_Y, -0.14)
    ring_c = Vector((xe + side * (0.03 + 0.115), -BEAM_Y, -0.14 - 0.062 - 0.074 + 0.01))
    end = chain(K, [ring_c, ring_c + Vector((side * 0.02, 0, -0.30))])
    hook(K, end, 0.85, flip=1.0)
    # стыковой конец — кольцо-проушина
    lug_ring(K, -side * L / 2, -side, -BEAM_Y, -0.14)
    return K.finish()


# ----------------------------------------------------------------------------------------------------------------------
# K06: платформа с разрывом
# ----------------------------------------------------------------------------------------------------------------------
def platform_gap(name, half=1.4, gap=1.2):
    K = Kit(name)
    for sg in (-1, 1):
        xo = sg * (gap / 2 + half)              # внешний торец
        xi = sg * gap / 2                       # обломанный торец
        a, b = sorted((xo, xi))
        xn = xo - sg * NODE / 2                 # внешний узел
        xl = xi + sg * 0.22                     # нога у обломка

        def lengths(i, cx, xi=xi):
            # у обломка доски короче и рванее
            dist = abs(cx - xi)
            if dist < 0.5:
                cut = RNG.uniform(0.0, 0.65) * (0.5 - dist) / 0.5
                return (-PLANK_Y + (cut if RNG.random() < 0.5 else 0.0), PLANK_Y - (cut if RNG.random() >= 0.5 else 0.0))
            return (-PLANK_Y, PLANK_Y)
        # настил: у обломка доски торчат на разную длину
        plank_deck(K, a, b, lengths=lengths)
        # повисшая доска: зацепилась за край обломка и свисает в разрыв почти отвесно (~72°), только у правой половины
        if sg > 0:
            ang = math.radians(72)
            d = Vector((-sg * math.cos(ang), 0, -math.sin(ang)))
            top_end = Vector((xi - sg * 0.04, -0.4, -0.02))
            K.add(g_box(0.6, 0.2, PLANK_T), "ScrapWoodDark", loc=top_end + d * 0.3,
                  rot=(0.1, math.radians(90 + sg * 18), 0.06), along='X', du=0.625)
        deck_straps(K, a, b, ys=(-0.6,))
        for yy, fr in ((-BEAM_Y, True), (BEAM_Y, False)):
            # балка с косым срезом у обломка
            xe = xi + sg * 0.12 * (1 if fr else -0.5)
            pts = [(xo - sg * 0.01, BEAM_TOP), (xe, BEAM_TOP), (xe - sg * 0.22, BEAM_BOT), (xo - sg * 0.01, BEAM_BOT)]
            if sg < 0:
                pts = list(reversed(pts))
            K.add(g_prism(pts, BEAM_D, bevel=0.01 if fr else 0.0), "RustIron", loc=(0, yy, 0))
            if fr:
                for x in (xo - sg * 0.55, xo - sg * 0.95):
                    for zz in (BEAM_TOP - 0.022, BEAM_BOT + 0.022):
                        rivet(K, (x, yy - BEAM_D / 2, zz))
            node(K, xn, yy, front=fr)
        cross_beam(K, xn)
        cross_beam(K, xl)
        cross_strap(K, xn)
        for x in (xn, xl):
            leg(K, x, -BEAM_Y, NODE_BOT if x == xn else BEAM_BOT, -1.0, True, gussets=(x == xn))
            leg(K, x, BEAM_Y, NODE_BOT if x == xn else BEAM_BOT, -1.0, False)
        lug_ring(K, xo, sg, -BEAM_Y, -0.14)
        # свисающие цепи у обломка
        chain(K, [(xi - sg * 0.05, -BEAM_Y - BEAM_D / 2 - 0.02, BEAM_TOP - 0.06),
                  (xi + sg * 0.02, -BEAM_Y - BEAM_D / 2 - 0.02, BEAM_TOP - 0.06 - 5 * LINK_PITCH)])
        if sg > 0:
            chain(K, [(xi - sg * 0.35, -BEAM_Y - BEAM_D / 2 - 0.02, BEAM_BOT),
                      (xi - sg * 0.33, -BEAM_Y - BEAM_D / 2 - 0.02, BEAM_BOT - 3 * LINK_PITCH)], twist0=1)
    return K.finish()


# ----------------------------------------------------------------------------------------------------------------------
# K12 / K13: скаты
# ----------------------------------------------------------------------------------------------------------------------
def slope(name, rise, run=4.0):
    K = Kit(name)
    th = math.atan2(rise, run)
    tn = math.tan(th)
    Ls = math.hypot(run, rise)
    ramp = Matrix.Translation((-run / 2, 0, 0)) @ Matrix.Rotation(-th, 4, 'Y')
    xm = (run / 2) / math.cos(th)              # средний узел на линии сетки x = 0
    xh = run / 2 - NODE / 2                    # верхний (вертикальный) узел
    K.xf = ramp
    plank_deck(K, 0.02, Ls - 0.05)
    deck_straps(K, 0.02, Ls - 0.05)
    for yy, fr in ((-BEAM_Y, True), (BEAM_Y, False)):
        node(K, xm, yy, front=fr)
    cross_beam(K, xm)
    cross_beam(K, 0.6)
    cross_strap(K, xm)
    cross_strap(K, 0.25)
    K.xf = Matrix.Identity(4)

    def z_top(x):
        return (x + run / 2) * tn
    hv = BEAM_H / math.cos(th)
    xa = -run / 2 + 0.01
    xd = -run / 2 + hv / tn
    xe = run / 2 - 0.02
    for yy, fr in ((-BEAM_Y, True), (BEAM_Y, False)):
        pts = [(xa, z_top(xa)), (xd, 0.0), (xe, z_top(xe) - hv), (xe, z_top(xe))]
        K.add(g_prism(pts, BEAM_D, bevel=0.012 if fr else 0.0), "RustIron", loc=(0, yy, 0), along='X')
        if fr:
            x = xa + 0.35
            while x < xe - 0.3:
                if abs(x) > 0.3 and abs(x - xh) > 0.28:
                    rivet(K, (x, yy - BEAM_D / 2, z_top(x) - 0.03), r=0.02)
                    if z_top(x) - hv + 0.03 > 0.03:
                        rivet(K, (x, yy - BEAM_D / 2, z_top(x) - hv + 0.03), r=0.02)
                x += 0.45
        node(K, xh, yy, z_top=rise + NODE_TOP, front=fr)
        leg(K, xh, yy, rise + NODE_BOT, 0.0, fr)
    cross_beam(K, xh, z_top=rise - PLANK_T)
    # носок у нижнего края: железная полоса на земле под первыми досками
    K.add(g_box(0.36, 2.02, 0.03, bevel=0.008), "RustIron", loc=(-run / 2 + 0.2, 0, 0.015), along='Y')
    for yy in (-0.8, -0.3, 0.3, 0.8):
        bolt(K, (-run / 2 + 0.08, yy, 0.03), (0, 0, 1), s=0.026, h=0.014)
    yb = -BEAM_Y - LEG / 2 - 0.03
    if rise >= 1.5:
        zm = (xm * math.sin(th)) + NODE_BOT
        leg(K, 0.0, -BEAM_Y, zm, 0.0, True)
        leg(K, 0.0, BEAM_Y, zm, 0.0, False)
        flat_bar(K, (0.12, 0.12), (xh - 0.12, rise + NODE_BOT - 0.12), w=0.10, t=0.04, y=yb)
        K.add(g_box(0.08, 2 * BEAM_Y - LEG, 0.10, drop=('-Z',)), "RustIronDark", loc=(xh, 0, 0.35))
        dangle(K, -0.9, z_top(-0.9) - hv, 3)
    else:
        dangle(K, 0.9, z_top(0.9) - hv, 2)
    lug_ring(K, run / 2, 1, -BEAM_Y, rise - 0.14)
    return K.finish()


# ----------------------------------------------------------------------------------------------------------------------
# K14–K16: опоры-башни
# ----------------------------------------------------------------------------------------------------------------------
def support(name, H=3.0, W=1.0, bays=2):
    K = Kit(name)
    P = 0.22
    PY = 1.0 - P / 2 - 0.04                     # стойки по глубине
    xs = (-(W / 2 - P / 2), W / 2 - P / 2)
    base_h, cap_t, capn = 0.30, 0.10, 0.34
    z0 = base_h
    z1 = H - cap_t - capn
    yf = -PY - P / 2                             # лицевая плоскость стоек
    for yy, fr in ((-PY, True), (PY, False)):
        for x in xs:
            if fr:
                K.add(g_box(P, P, z1 - z0, bevel=0.012, inset=('-Y',), border=0.045, depth=0.016), "RustIronDark",
                      loc=(x, yy, (z0 + z1) / 2))
                z = z0 + 0.35
                while z < z1 - 0.2:
                    rivet(K, (x, yy - P / 2, z), r=0.019)
                    z += 0.62
            else:
                K.add(g_box(P, P, z1 - z0, drop=('+Z', '-Z', '+Y')), "RustIronDark", loc=(x, yy, (z0 + z1) / 2))
            # цоколь и узел под крышкой
            node(K, x, yy, z_top=base_h, s=0.36, h=base_h - FOOT_T, front=fr)
            node(K, x, yy, z_top=H - cap_t, s=capn, front=fr)
            if fr:
                K.add(g_box(0.46, 0.46, FOOT_T, bevel=0.012), "RustIron", loc=(x, yy, FOOT_T / 2))
            else:
                K.add(g_box(0.46, 0.46, FOOT_T, drop=('-Z',)), "RustIron", loc=(x, yy, FOOT_T / 2))
    # крышка — по ней ходят
    K.add(g_box(W + 0.06, 2.06, cap_t, bevel=0.015), "RustIron", loc=(0, 0, H - cap_t / 2), along='Y')
    for x in (-(W / 2 - 0.1), 0.0, W / 2 - 0.1):
        rivet(K, (x, -1.03, H - cap_t / 2), r=0.02)
    # стяжки и кресты по пролётам (спереди — с фасками и болтами, сзади — простые)
    zs = [z0 + (z1 - z0) * k / bays for k in range(bays + 1)]
    for k, z in enumerate(zs):
        if 0 < k < bays:
            K.add(g_box(W - 0.02, 0.05, 0.12, bevel=0.01), "RustIron", loc=(0, yf - 0.025, z))
            for x in xs:
                bolt(K, (x, yf - 0.05, z))
            K.add(g_box(W - 0.02, 0.05, 0.12, drop=('+Y',)), "RustIron", loc=(0, -yf + 0.025, z))
        for yy in (-1, 1):
            K.add(g_box(0.08, 2 * PY - P, 0.1, drop=('-Z',)), "RustIronDark", loc=(yy * (W / 2 - P / 2), 0, z + 0.06))
    for k in range(bays):
        za, zb = zs[k] + 0.08, zs[k + 1] - 0.08
        xa, xb = xs[0] + 0.02, xs[1] - 0.02
        flat_bar(K, (xa, za), (xb, zb), w=0.09, t=0.035, y=yf - 0.02, mat="RustIron")
        flat_bar(K, (xa, zb), (xb, za), w=0.09, t=0.035, y=yf - 0.045, mat="RustIron", bolts=False)
        bolt(K, (0, yf - 0.065, (za + zb) / 2), s=0.04, h=0.02)
        for p0, p1 in (((xa, za), (xb, zb)), ((xa, zb), (xb, za))):
            d = Vector((p1[0] - p0[0], 0, p1[1] - p0[1]))
            K.add(g_box(d.length, 0.035, 0.09, drop=('+Y',)), "RustIron", loc=((p0[0] + p1[0]) / 2, -yf + 0.02, (p0[1] + p1[1]) / 2),
                  rot=(0, -math.atan2(d.z, d.x), 0))
    # кольцо на узле под крышкой и цепь с другой стороны
    lug_ring(K, xs[1] + capn / 2, 1, -PY, H - cap_t - 0.14)
    dangle(K, xs[0] - 0.05, H - cap_t - capn, 4 if H < 5 else 6, y=yf - 0.06, with_hook=H >= 4)
    return K.finish()


# ----------------------------------------------------------------------------------------------------------------------
# K17: подкос
# ----------------------------------------------------------------------------------------------------------------------
def support_diagonal(name, H=3.0):
    K = Kit(name)
    S = 0.36
    base_h, top_h = 0.30, 0.38
    K.add(g_box(S, S, H - base_h - top_h, bevel=0.012, inset=('-Y',), border=0.05, depth=0.018), "RustIronDark",
          loc=(0, 0, (H - top_h + base_h) / 2))
    z = base_h + 0.3
    while z < H - top_h - 0.2:
        rivet(K, (0, -S / 2, z), r=0.019)
        z += 0.55
    node(K, 0, 0, z_top=base_h, s=S + 0.1, h=base_h - FOOT_T)
    K.add(g_box(0.58, 0.58, FOOT_T, bevel=0.012), "RustIron", loc=(0, 0, FOOT_T / 2))
    node(K, 0, 0, z_top=H - 0.06, s=S + 0.08, h=top_h - 0.06, sides=('+X',))
    K.add(g_box(0.56, 0.56, 0.06, bevel=0.012), "RustIron", loc=(0, 0, H - 0.03))
    # подкос-швеллер
    foot = Vector((-1.9, 0, 0.16))
    top = Vector((-S / 2 - 0.02, 0, H - 0.72))
    d = top - foot
    ang = math.atan2(d.z, d.x)
    K.add(g_box(d.length, 0.18, 0.2, bevel=0.014, inset=('-Y',), border=0.045, depth=0.02), "RustIron",
          loc=(foot + top) / 2, rot=(0, -ang, 0), along='X')
    dn = d.normalized()
    nz = Vector((-dn.z, 0, dn.x))
    for i in range(1, 6):
        p = foot + dn * (d.length * i / 6)
        for s in (-1, 1):
            rivet(K, p + nz * (s * 0.077) + Vector((0, -0.09, 0)), r=0.018)
    # башмак на земле и накладка у стойки
    K.add(g_prism([(-2.12, 0.0), (-1.62, 0.0), (-1.62, 0.1), (-1.92, 0.36), (-2.12, 0.2)], 0.28, bevel=0.012), "RustIron", along='X')
    K.add(g_box(0.62, 0.42, 0.04, bevel=0.01), "RustIronDark", loc=(-1.87, 0, 0.02))
    for x in (-2.08, -1.66):
        bolt(K, (x, -0.16, 0.04), (0, 0, 1), s=0.03)
    bolt(K, (-1.84, -0.14, 0.18), s=0.04, h=0.02)
    K.add(g_prism([(-S / 2 - 0.02, H - 0.45), (-S / 2 - 0.02, H - 1.15), (-S / 2 - 0.4, H - 1.05)], 0.22, bevel=0.01),
          "RustIron", along='Z')
    for zz in (H - 0.62, H - 0.92):
        bolt(K, (-S / 2 - 0.1, -0.11, zz), s=0.03)
    dangle(K, 0.12, H - top_h, 3, y=-S / 2 - 0.06)
    return K.finish()


# ----------------------------------------------------------------------------------------------------------------------
# K18 / K19: рамы с флагами
# ----------------------------------------------------------------------------------------------------------------------
def lattice_post(K, x, H, w=0.5, beam_h=0.36, ties=4, crosses=(1,)):
    """Решётчатая стойка рамы: две стойки 0.14, стяжки-полосы спереди и сзади, крест в выбранных пролётах, цоколь."""
    u = 0.14
    xs = (x - w / 2 + u / 2, x + w / 2 - u / 2)
    base_h = 0.32
    z0, z1 = base_h, H - beam_h
    for xx in xs:
        K.add(g_box(u, u, z1 - z0, bevel=0.01, inset=('-Y',), border=0.03, depth=0.012), "RustIronDark", loc=(xx, 0, (z0 + z1) / 2))
    zs = [z0 + (z1 - z0) * k / ties for k in range(ties + 1)]
    for k, z in enumerate(zs[1:-1], 1):
        K.add(g_box(w, 0.04, 0.09, bevel=0.008), "RustIron", loc=(x, -u / 2 - 0.02, z))
        K.add(g_box(w, 0.04, 0.09, drop=('+Y',)), "RustIron", loc=(x, u / 2 + 0.02, z))
        if k % 2 == 1:
            for xx in xs:
                bolt(K, (xx, -u / 2 - 0.04, z), s=0.026, h=0.013)
    for k in crosses:
        za, zb = zs[k] + 0.06, zs[k + 1] - 0.06
        flat_bar(K, (xs[0], za), (xs[1], zb), w=0.07, t=0.03, y=-u / 2 - 0.02, bolts=False, bevel=0.0)
        flat_bar(K, (xs[0], zb), (xs[1], za), w=0.07, t=0.03, y=-u / 2 - 0.045, bolts=False, bevel=0.0)
    node(K, x, 0, z_top=base_h, s=w + 0.08, h=base_h - FOOT_T)
    K.add(g_box(w + 0.2, w + 0.1, FOOT_T, bevel=0.01), "RustIron", loc=(x, 0, FOOT_T / 2))


def top_beam(K, x0, x1, H, h=0.36, d=0.30, ring_ends=True):
    L = x1 - x0
    K.add(g_box(L - 0.6, d, h - 0.04, bevel=0.012, inset=('-Y',), border=0.05, depth=0.02), "RustIron",
          loc=((x0 + x1) / 2, 0, H - h / 2), along='Z')
    n = int(round((L - 0.9) / 0.6))
    for i in range(n + 1):
        x = x0 + 0.45 + (L - 0.9) * i / max(1, n)
        rivet(K, (x, -d / 2, H - 0.045), r=0.019)
        if i % 2 == 0:
            rivet(K, (x, -d / 2, H - h + 0.05), r=0.019)
    for sg, xe in ((-1, x0), (1, x1)):
        node(K, xe - sg * 0.21, 0, z_top=H + 0.02, s=0.42, h=h + 0.06, sides=('-X' if sg < 0 else '+X',))
        if ring_ends:
            lug_ring(K, xe, sg, -0.1, H - 0.2)


def crown_plate(K, x, z, w=0.36, y=-0.17, t=0.03):
    """Латунная корона-накладка (силуэт с тремя зубцами и шариками)."""
    h = w * 0.78
    pts = [(-0.5, 0.0), (0.5, 0.0), (0.5, 0.2), (0.56, 0.72), (0.3, 0.42), (0.0, 0.92), (-0.3, 0.42), (-0.56, 0.72), (-0.5, 0.2)]
    K.add(g_prism([(px * w, pz * h) for px, pz in pts], t, bevel=0.004), "Brass", loc=(x, y, z), along='Z')
    for px, pz in ((0.56, 0.72), (0.0, 0.92), (-0.56, 0.72)):
        K.add(g_lathe([(0.0, -0.028), (0.028, -0.014), (0.028, 0.014), (0.0, 0.028)], segs=6), "Brass",
              loc=(x + px * w, y - 0.005, z + pz * h + 0.02), rot=(math.pi / 2, 0, 0))


def banner(K, cx, top, w, h, seed_tails=0.2, crown=True, folds=3.2, amp=0.045):
    """Флаг: сетка ткани со складками (y = f(x, z)), рваный низ «языками», штанга с латунными наконечниками,
    два кольца к балке; декаль короны — отдельная сетка, повторяющая складки (+12 мм к камере)."""
    nx, nz = 12, 13
    phase = RNG.uniform(0, TAU)

    def fy(x, z):
        t = (top - z) / h                                  # 0 у штанги → 1 внизу
        return (amp * (0.35 + 0.65 * t) * math.sin(TAU * folds * (x - cx) / w + phase)
                + 0.02 * math.sin(TAU * 1.3 * (x - cx) / w + 1.7 * t + phase * 0.5) - 0.03 * t)
    # длины колонок (рваный низ): чередование «языков» и вырезов
    lens = []
    for i in range(nx + 1):
        base = 1.0 - (0.18 if i % 2 else 0.0) - RNG.uniform(0.0, seed_tails)
        if i in (0, nx):
            base = min(base, 0.9)
        lens.append(h * base)
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.verify()
    grid = []
    for j in range(nz + 1):
        row = []
        for i in range(nx + 1):
            x = cx - w / 2 + w * i / nx
            z = top - lens[i] * j / nz
            row.append(bm.verts.new((x, fy(x, z), z)))
        grid.append(row)
    for j in range(nz):
        for i in range(nx):
            f = bm.faces.new((grid[j][i], grid[j + 1][i], grid[j + 1][i + 1], grid[j][i + 1]))
            for lo in f.loops:
                lo[uvl].uv = (lo.vert.co.x, lo.vert.co.z)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.normal_update()
    if sum(f.normal.y for f in bm.faces) > 0:              # лицом к камере (−Y)
        bmesh.ops.reverse_faces(bm, faces=list(bm.faces))
    K.add(bm, "Banner", uv=False)
    if crown:
        cw = w * 0.62
        x0, z1 = cx - cw / 2, top - 0.2 * h
        z0 = z1 - cw
        n = 8
        bm = bmesh.new()
        uvl = bm.loops.layers.uv.verify()
        g = [[bm.verts.new((x0 + cw * i / n, fy(x0 + cw * i / n, z0 + cw * j / n) - 0.012, z0 + cw * j / n))
              for i in range(n + 1)] for j in range(n + 1)]
        for j in range(n):
            for i in range(n):
                f = bm.faces.new((g[j][i], g[j][i + 1], g[j + 1][i + 1], g[j + 1][i]))
                for lo in f.loops:
                    lo[uvl].uv = ((lo.vert.co.x - x0) / cw, (lo.vert.co.z - z0) / cw)
        bm.normal_update()
        if sum(f.normal.y for f in bm.faces) > 0:
            bmesh.ops.reverse_faces(bm, faces=list(bm.faces))
        K.add(bm, "Crown", uv=False)
    # штанга и кольца
    K.add(g_cyl(0.022, w + 0.16, segs=6), "RustIronDark", loc=(cx, fy(cx, top), top + 0.01))
    for sg in (-1, 1):
        K.add(g_lathe([(0.0, -0.035), (0.03, -0.02), (0.032, 0.012), (0.0, 0.04)], segs=6), "Brass",
              loc=(cx + sg * (w / 2 + 0.1), fy(cx, top), top + 0.01), rot=(0, sg * math.pi / 2, 0))


def wall_frame(name, W=4.0, H=3.0):
    K = Kit(name)
    for x in (-(W / 2 - 0.25), W / 2 - 0.25):
        lattice_post(K, x, H, w=0.5, ties=4, crosses=(1, 2))
    top_beam(K, -W / 2, W / 2, H)
    crown_plate(K, 0.0, H - 0.31, w=0.30, y=-0.165)
    bw, btop = 1.3, H - 0.52
    banner(K, 0.0, btop, bw, 1.95)
    for sg in (-1, 1):
        chain(K, [(sg * (bw / 2 - 0.05), -0.02, H - 0.36), (sg * (bw / 2 - 0.05), -0.02, btop + 0.02)], R=0.03, r=0.009)
        dangle(K, sg * 1.12, H - 0.36, 4 if sg < 0 else 3, y=-0.05, with_hook=sg > 0, ring=3)
    return K.finish()


def banner_frame(name, W=2.0, H=4.0):
    K = Kit(name)
    for x in (-(W / 2 - 0.2), W / 2 - 0.2):
        lattice_post(K, x, H, w=0.4, ties=5, crosses=(1, 3))
    top_beam(K, -W / 2, W / 2, H, ring_ends=False)
    # рым-болт сверху и короткая цепь вверх
    K.add(g_box(0.2, 0.2, 0.05, bevel=0.01), "RustIron", loc=(0, 0, H + 0.025))
    eye = g_torus(0.07, 0.02, 10, 4)
    K.add(eye, "RustIron", loc=(0, 0, H + 0.11), rot=(math.pi / 2, 0, 0))
    chain(K, [(0, 0, H + 0.2), (0.0, 0, H + 0.2 + 4 * LINK_PITCH)], twist0=1)
    bw, btop = 1.1, H - 0.5
    banner(K, 0.0, btop, bw, 2.95, seed_tails=0.14, folds=2.6, amp=0.05)
    for sg in (-1, 1):
        chain(K, [(sg * (bw / 2 - 0.05), -0.02, H - 0.36), (sg * (bw / 2 - 0.05), -0.02, btop + 0.02)], R=0.03, r=0.009)
    for sg in (-1, 1):
        lug_ring(K, sg * W / 2, sg, -0.1, H - 0.2)
    return K.finish()


# ----------------------------------------------------------------------------------------------------------------------
# K19b: перила
# ----------------------------------------------------------------------------------------------------------------------
def railing(name, L=2.0, H=1.14):
    K = Kit(name)
    K.add(g_box(L, 0.24, 0.16, bevel=0.012, inset=('-Y',), border=0.035, depth=0.015), "RustIron", loc=(0, 0, 0.08), along='Z')
    for i in range(7):
        x = -L / 2 + 0.2 + (L - 0.4) * i / 6
        if abs(abs(x) - (L / 2 - 0.15)) > 0.12:
            rivet(K, (x, -0.12, 0.08), r=0.019)
    xp = L / 2 - 0.15
    for sg in (-1, 1):
        x = sg * xp
        K.add(g_box(0.16, 0.16, H - 0.16 - 0.14, bevel=0.01, inset=('-Y',), border=0.035, depth=0.012), "RustIronDark",
              loc=(x, 0, 0.16 + (H - 0.3) / 2))
        node(K, x, 0, z_top=H, s=0.22, h=0.14)
        node(K, x, 0, z_top=0.26, s=0.22, h=0.10)
    K.add(g_cyl(0.035, 2 * xp - 0.2, segs=8), "RustIron", loc=(0, 0, H - 0.13))
    for sg in (-1, 1):
        K.add(g_box(0.08, 0.1, 0.1, bevel=0.008), "RustIron", loc=(sg * (xp - 0.12), 0, H - 0.13))
    # провисшая цепь между стойками и две вертикальные
    chain(K, catenary((-xp + 0.1, -0.02, 0.62), (xp - 0.1, -0.02, 0.62), 0.16), R=0.038, r=0.012)
    for x in (-0.33, 0.33):
        zc = 0.62 - 4.0 * 0.16 * (0.5 + x / (2 * xp - 0.2)) * (0.5 - x / (2 * xp - 0.2))
        chain(K, [(x, -0.02, H - 0.17), (x, -0.02, zc + 0.03)], R=0.032, r=0.01, twist0=1)
    return K.finish()


# ----------------------------------------------------------------------------------------------------------------------
# K20: цепь с крюком
# ----------------------------------------------------------------------------------------------------------------------
def chain_hook(name, length=2.2):
    K = Kit(name)
    K.add(g_box(0.30, 0.30, 0.06, bevel=0.012), "RustIron", loc=(0, 0, -0.03))
    for dx in (-1, 1):
        for dy in (-1, 1):
            bolt(K, (dx * 0.11, dy * 0.11, -0.06), (0, 0, -1), s=0.03)
    K.add(g_prism([(-0.06, 0.0), (0.06, 0.0), (0.045, -0.1), (-0.045, -0.1)], 0.05, bevel=0.008), "RustIron", loc=(0, 0, -0.06))
    ring = g_torus(0.045, 0.014, 10, 4)
    K.add(ring, "RustIron", loc=(0, 0, -0.17), rot=(0, math.pi / 2, 0))
    end = chain(K, [(0, 0, -0.22), (0.0, 0, -0.22 - length)], R=0.052, r=0.016)
    # бирка (красная краска по ржавчине) на проволоке у середины цепи
    zt = -0.22 - length * 0.66
    K.add(g_box(0.13, 0.025, 0.2, bevel=0.01), "RustRed", loc=(0.06, -0.05, zt), rot=(0, 0.12, 0), along='Z')
    rivet(K, (0.06, -0.063, zt + 0.07), r=0.012)
    K.add(g_torus(0.02, 0.004, 6, 3), "RustIronDark", loc=(0.04, -0.04, zt + 0.1), rot=(math.pi / 2, 0, 0.3))
    # крюк
    hook(K, end, 1.35)
    return K.finish()


# ----------------------------------------------------------------------------------------------------------------------
# K21: балка на цепях
# ----------------------------------------------------------------------------------------------------------------------
def hanging_beam(name, L=4.0, up=2.0):
    K = Kit(name)
    bh, bd = 0.34, 0.34
    K.add(g_box(L - 0.8, bd, bh, bevel=0.012, inset=('-Y',), border=0.05, depth=0.02), "RustIron",
          loc=(0, 0, -bh / 2), along='Z')
    for i in range(9):
        x = -L / 2 + 0.6 + (L - 1.2) * i / 8
        for zz in (-0.05, -bh + 0.05):
            rivet(K, (x, -bd / 2, zz), r=0.019)
    for sg in (-1, 1):
        node(K, sg * (L / 2 - 0.21), 0, z_top=0.03, s=0.42, h=bh + 0.06, sides=('-X' if sg < 0 else '+X',))
    xc = L / 2 - 0.3
    for sg in (-1, 1):
        x = sg * xc
        # серьга на верхней грани узла и цепь вверх к анкеру
        K.add(g_prism([(-0.07, 0.0), (0.07, 0.0), (0.05, 0.12), (-0.05, 0.12)], 0.05, bevel=0.008), "RustIron", loc=(x, 0, 0.03))
        K.add(g_torus(0.035, 0.012, 8, 4), "RustIron", loc=(x, 0, 0.16), rot=(0, math.pi / 2, 0))
        chain(K, [(x, 0, 0.2), (x, 0, up - 0.16)], R=0.048, r=0.015, ring=3, twist0=1)
        K.add(g_torus(0.06, 0.016, 10, 4), "RustIron", loc=(x, 0, up - 0.06), rot=(math.pi / 2, 0, 0))
        K.add(g_box(0.24, 0.2, 0.05, bevel=0.01), "RustIronDark", loc=(x, 0, up + 0.025))
        # короткая цепь с крюком под концом
        end = chain(K, [(sg * (L / 2 - 0.55), -0.08, -bh - 0.02), (sg * (L / 2 - 0.55), -0.08, -bh - 0.02 - 2 * LINK_PITCH)])
        hook(K, end, 0.9)
    return K.finish()


# ----------------------------------------------------------------------------------------------------------------------
# K22: лестница
# ----------------------------------------------------------------------------------------------------------------------
def ladder(name, H=3.0, W=0.6):
    K = Kit(name)
    for sg in (-1, 1):
        x = sg * W / 2
        K.add(g_box(0.11, 0.085, H - 0.06, bevel=0.014), "ScrapWoodDark", loc=(x, 0, 0.03 + (H - 0.06) / 2),
              rot=(0, sg * 0.01, 0), along='Z', du=0.125 + 0.25 * RNG.randrange(4))
        for z in (0.45, 1.35, 2.25):
            K.add(g_box(0.13, 0.105, 0.06, drop=()), "RustIronDark", loc=(x, 0, z))
        K.add(g_box(0.15, 0.12, 0.1, bevel=0.01), "RustIron", loc=(x, 0, 0.05))
        # крюк-зацеп сверху: загнут назад (+Y), чтобы вешать на край настила
        pts = [Vector((x, 0, H - 0.05)), Vector((x, 0, H + 0.1)), Vector((x, 0.07, H + 0.2)), Vector((x, 0.17, H + 0.18)),
               Vector((x, 0.2, H + 0.06))]
        K.add(g_tube(pts, [0.024, 0.024, 0.022, 0.02, 0.016], sides=6, cap0=True, tip=False), "RustIron", uv=True)
    n = 9
    for i in range(n):
        z = 0.3 + 0.3 * i
        K.add(g_box(W - 0.04, 0.06, 0.065, bevel=0.012), "ScrapWood" if i % 3 == 1 else "ScrapWoodDark",
              loc=(0, -0.01, z + RNG.uniform(-0.01, 0.01)), rot=(0, RNG.uniform(-0.03, 0.03), 0), along='X',
              du=0.125 + 0.25 * RNG.randrange(4))
        for sg in (-1, 1):
            bolt(K, (sg * W / 2, -0.038, z), s=0.024, h=0.012)
    return K.finish()


# ----------------------------------------------------------------------------------------------------------------------
MODULES = [
    ("Platform_S", lambda n: platform(n, 2.0)),
    ("Platform_M", lambda n: platform(n, 4.0)),
    ("Platform_L", lambda n: platform(n, 6.0)),
    ("Platform_End_L", lambda n: platform_end(n, -1)),
    ("Platform_End_R", lambda n: platform_end(n, 1)),
    ("Platform_Gap", platform_gap),
    ("Platform_Lower", platform_lower),
    ("Platform_Upper", platform_upper),
    ("Slope_15", lambda n: slope(n, 1.0)),
    ("Slope_30", lambda n: slope(n, 2.0)),
    ("Support_S", lambda n: support(n, 3.0, 1.0, 2)),
    ("Support_M", lambda n: support(n, 4.0, 1.0, 2)),
    ("Support_L", lambda n: support(n, 6.0, 1.6, 3)),
    ("Support_Diagonal", support_diagonal),
    ("Wall_Frame", wall_frame),
    ("Banner_Frame", banner_frame),
    ("Railing", railing),
    ("Chain_Hook", chain_hook),
    ("Hanging_Beam", hanging_beam),
    ("Ladder", ladder),
]


def tri_count(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def bbox_godot(obj):
    """Габарит в осях Godot: x = X, y = Z, z = −Y."""
    xs = [v.co.x for v in obj.data.vertices]
    ys = [v.co.y for v in obj.data.vertices]
    zs = [v.co.z for v in obj.data.vertices]
    return (min(xs), max(xs)), (min(zs), max(zs)), (-max(ys), -min(ys))


def export(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    kw = dict(filepath=path, export_format='GLB', use_selection=True, export_apply=True, export_yup=True,
              export_materials='EXPORT', export_normals=True, export_texcoords=True, export_animations=False,
              export_skins=False, export_cameras=False, export_lights=False, export_image_format=IMG_FORMAT)
    if IMG_FORMAT in ('WEBP', 'JPEG'):
        kw['export_image_quality'] = 88
    bpy.ops.export_scene.gltf(**kw)


# ----------------------------------------------------------------------------------------------------------------------
# контактный рендер
# ----------------------------------------------------------------------------------------------------------------------
def _emit_mat(name, col, strength=1.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    em = nt.nodes.new('ShaderNodeEmission')
    em.inputs['Color'].default_value = col
    em.inputs['Strength'].default_value = strength
    nt.links.new(em.outputs[0], out.inputs[0])
    return m


def make_doll(x, z0):
    """Эталон куклы 1.8 м (манекен из капсул) — только для рендера."""
    mat = C.material("DollRef", (0.78, 0.60, 0.40, 1.0), 0.55, 0.0)
    parts = []

    def cap(name, a, b, r):
        a, b = Vector(a), Vector(b)
        d = b - a
        o = C.add_cylinder(name, r, d.length, loc=(a + b) / 2, verts=12)
        o.rotation_euler = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_euler()
        parts.append(o)
        for p in (a, b):
            s = C.add_sphere(name + "_j", r, loc=p, segments=12, rings=6)
            parts.append(s)
    cap("Torso", (x, 0, z0 + 1.02), (x, 0, z0 + 1.42), 0.15)
    cap("Neck", (x, 0, z0 + 1.46), (x, 0, z0 + 1.54), 0.045)
    head = C.add_sphere("Head", 0.12, loc=(x, 0, z0 + 1.66), segments=16, rings=8, scale=(0.9, 0.9, 1.1))
    parts.append(head)
    for s in (-1, 1):
        cap("Thigh", (x + s * 0.09, 0, z0 + 0.92), (x + s * 0.1, 0, z0 + 0.5), 0.065)
        cap("Shin", (x + s * 0.1, 0, z0 + 0.5), (x + s * 0.1, 0, z0 + 0.08), 0.05)
        foot = C.add_cube("Foot", (0.1, 0.22, 0.07), (x + s * 0.1, -0.05, z0 + 0.035))
        parts.append(foot)
        cap("UpperArm", (x + s * 0.21, 0, z0 + 1.42), (x + s * 0.25, 0, z0 + 1.1), 0.045)
        cap("ForeArm", (x + s * 0.25, 0, z0 + 1.1), (x + s * 0.27, 0, z0 + 0.82), 0.04)
    o = C.join(parts, "DollRef")
    C.assign(o, mat)
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def label(text, x, z, size=0.26, mat=None):
    cu = bpy.data.curves.new("Lbl_" + text, 'FONT')
    cu.body = text
    cu.size = size
    cu.align_x = 'CENTER'
    o = bpy.data.objects.new("Lbl_" + text, cu)
    bpy.context.scene.collection.objects.link(o)
    o.location = (x, -2.2, z)
    o.rotation_euler = (math.pi / 2, 0, 0)
    if mat:
        cu.materials.append(mat)
    return o


def render_contact(objs, path=RENDER_PNG):
    scn = bpy.context.scene
    txt = _emit_mat("LabelMat", (0.85, 0.80, 0.72, 1.0), 1.0)
    grid_m = _emit_mat("GridMat", (0.16, 0.19, 0.24, 1.0), 1.0)
    ground_m = C.material("GroundRef", (0.035, 0.032, 0.034, 1.0), 0.95, 0.0)
    # ряды: (имя, y-origin над полом ряда); первая колонка ряда — кукла
    rows = [
        [("Platform_S", 1.0), ("Platform_M", 1.0), ("Platform_L", 1.0), ("Platform_End_L", 1.0), ("Platform_End_R", 1.0),
         ("Platform_Gap", 1.0)],
        [("Platform_Lower", 0.5), ("Platform_Upper", 2.0), ("Slope_15", 0.0), ("Slope_30", 0.0), ("Support_S", 0.0),
         ("Support_M", 0.0), ("Support_L", 0.0), ("Support_Diagonal", 0.0)],
        [("Wall_Frame", 0.0), ("Banner_Frame", 0.0), ("Railing", 0.0), ("Ladder", 0.0), ("Chain_Hook", 3.4),
         ("Hanging_Beam", 1.4)],
    ]
    row_h = [2.6, 7.4, 6.2]
    # номинальный левый край (м от origin), который ставится на линию сетки 2 м: у платформ/скатов/рам — торец модуля,
    # у опор, лестницы и цепи — сам origin (опора стоит на узле сетки)
    nominal = {"Platform_S": -1, "Platform_M": -2, "Platform_L": -3, "Platform_End_L": -1, "Platform_End_R": -1,
               "Platform_Gap": -2, "Platform_Lower": -1, "Platform_Upper": -1, "Slope_15": -2, "Slope_30": -2,
               "Wall_Frame": -2, "Banner_Frame": -1, "Railing": -1, "Hanging_Beam": -2}
    z_base = 0.0
    bases = {}
    for r in range(len(rows) - 1, -1, -1):
        bases[r] = z_base
        z_base += row_h[r]
    total_h = z_base
    width = 0.0

    def put(o, cursor, oy, zb, margin=0.45):
        (bx0, bx1), _, _ = bbox_godot(o)
        nl = nominal.get(o.data.name, 0.0)
        xg = 2.0 * math.ceil((cursor + margin - bx0 + nl) / 2.0 - 1e-6)
        ox = xg - nl
        o.location = (ox, 0.0, zb + oy)
        return ox, ox + bx0, ox + bx1

    for r, row in enumerate(rows):
        zb = bases[r]
        make_doll(0.35, zb)
        label("doll 1.8 m", 0.35, zb - 0.45, 0.2, txt)
        cursor = 0.8
        for name, oy in row:
            o = objs.get(name)
            if o is None:
                continue
            ox, x0, x1 = put(o, cursor, oy, zb)
            label(name, (x0 + x1) / 2, zb - 0.45, 0.24, txt)
            cursor = x1
        if r == 2 and all(n in objs for n in ("Support_S", "Platform_M", "Railing")):
            # пример сборки по snap-правилу: две опоры 3 м на узлах сетки, на них Platform_M (origin y = 3 + 1),
            # перила на заднем крае настила
            xs0 = 2.0 * math.ceil((cursor + 1.2) / 2.0)
            for k, nm in enumerate(("Support_S", "Support_S")):
                d = objs[nm].copy()
                bpy.context.scene.collection.objects.link(d)
                d.location = (xs0 + 4.0 * k, 0.0, zb)
            pm = objs["Platform_M"].copy()
            bpy.context.scene.collection.objects.link(pm)
            pm.location = (xs0 + 2.0, 0.0, zb + 4.0)
            rl = objs["Railing"].copy()
            bpy.context.scene.collection.objects.link(rl)
            rl.location = (xs0 + 2.0, 0.75, zb + 4.0)
            label("snap: Support_S x2 + Platform_M (y = H + 1)", xs0 + 2.0, zb - 0.45, 0.24, txt)
            cursor = xs0 + 4.75
        width = max(width, cursor + 0.6)
    for r in range(len(rows)):
        g = C.add_cube("GroundRow%d" % r, (width + 1.0, 3.0, 0.04), (width / 2, 0.5, bases[r] - 0.02))
        C.assign(g, ground_m)
    # сетка 2 м за модулями (сдвинута вниз на y·tan(tilt), чтобы совпасть с плоскостью y = 0)
    tilt = math.radians(4.0)
    yg = 4.0
    dz = -yg * math.tan(tilt)
    xg = 0.0
    while xg <= width + 0.01:
        o = C.add_cube("GridV", (0.02, 0.01, total_h + 0.6), (xg, yg, total_h / 2 - 0.3 + dz))
        C.assign(o, grid_m)
        xg += 2.0
    for r in range(len(rows)):
        zb = bases[r]
        zz = zb
        while zz < zb + row_h[r] - 0.55:
            o = C.add_cube("GridH", (width + 1.0, 0.01, 0.02), (width / 2, yg, zz + dz))
            C.assign(o, grid_m)
            zz += 2.0
    back = C.add_cube("Backdrop", (width + 40, 0.05, total_h + 40), (width / 2, yg + 0.2, total_h / 2))
    C.assign(back, _emit_mat("BackRef", (0.030, 0.033, 0.042, 1.0), 1.0))
    back.visible_shadow = False
    if os.environ.get("SCRAP_KIT_VIEW") == "34":
        for o in list(scn.objects):
            if o.name.startswith(("Backdrop", "Grid", "GroundRow")):
                o.hide_render = True
    # камера: орто спереди с лёгким наклоном
    cam_d = bpy.data.cameras.new("Cam")
    cam_d.type = 'ORTHO'
    aspect = 3200 / 1800
    cam_d.ortho_scale = max(width + 1.0, (total_h + 1.2) * aspect)
    cam = bpy.data.objects.new("Cam", cam_d)
    scn.collection.objects.link(cam)
    cz = total_h / 2 - 0.55
    cx = width / 2 - 0.3
    focus = os.environ.get("SCRAP_KIT_FOCUS")     # отладка: крупный план одного ряда (индекс ряда[:x0:x1])
    if focus:
        parts = focus.split(":")
        r = int(parts[0])
        fx0 = float(parts[1]) if len(parts) > 1 else -0.5
        fx1 = float(parts[2]) if len(parts) > 2 else width
        cam_d.ortho_scale = max(fx1 - fx0, (row_h[r] + 0.6) * aspect)
        cx = (fx0 + fx1) / 2
        cz = bases[r] + row_h[r] / 2 - 0.5
    cam.location = (cx, -60.0, cz + 60.0 * math.tan(tilt))
    cam.rotation_euler = (math.pi / 2 - tilt, 0, 0)
    if os.environ.get("SCRAP_KIT_VIEW") == "34":        # отладка: вид 3/4 сверху-слева (проверка глубины)
        cam.rotation_euler = (math.radians(62), 0, math.radians(-32))
        fwd = cam.rotation_euler.to_matrix() @ Vector((0, 0, -1))
        cam.location = Vector((cx, 0.0, cz)) - fwd * 60.0
    scn.camera = cam
    # свет: тёплый ключ слева-сверху, холодный контровой, мягкий заполняющий
    def sun(name, rot, col, e, ang=3.0):
        ld = bpy.data.lights.new(name, 'SUN')
        ld.color = col
        ld.energy = e
        ld.angle = math.radians(ang)
        lo = bpy.data.objects.new(name, ld)
        scn.collection.objects.link(lo)
        lo.rotation_euler = rot
    sun("Key", (math.radians(52), 0, math.radians(-38)), (1.0, 0.80, 0.62), 3.6)
    sun("Rim", (math.radians(-60), 0, math.radians(160)), (0.55, 0.62, 1.0), 2.0)
    sun("Fill", (math.radians(80), 0, math.radians(20)), (0.9, 0.85, 0.8), 0.7, 20.0)
    world = bpy.data.worlds.new("World")
    scn.world = world
    world.use_nodes = True
    world.node_tree.nodes['Background'].inputs['Color'].default_value = (0.05, 0.05, 0.065, 1.0)
    world.node_tree.nodes['Background'].inputs['Strength'].default_value = 1.0
    scn.render.resolution_x = 3200
    scn.render.resolution_y = 1800
    scn.render.image_settings.file_format = 'PNG'
    try:
        scn.view_settings.view_transform = 'AgX'
    except TypeError:
        scn.view_settings.view_transform = 'Filmic'
    engine = os.environ.get("SCRAP_KIT_ENGINE", "EEVEE")
    ok = False
    if engine.startswith("EEVEE"):
        for eng in ('BLENDER_EEVEE_NEXT', 'BLENDER_EEVEE'):
            try:
                scn.render.engine = eng
                ok = True
                break
            except Exception:
                pass
        if ok:
            try:
                scn.eevee.taa_render_samples = 32
                scn.eevee.use_shadows = True
            except Exception:
                pass
    if not ok:
        scn.render.engine = 'CYCLES'
        scn.cycles.samples = int(os.environ.get("SCRAP_KIT_SAMPLES", "24"))
        scn.cycles.use_denoising = True
        scn.cycles.device = 'CPU'
    path = os.environ.get("SCRAP_KIT_OUT", path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    scn.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("render", scn.render.engine, path)


# ----------------------------------------------------------------------------------------------------------------------
def main():
    argv = C.args_after_dashdash()
    flags = {"render", "norender", "noexport"}
    only = [a for a in argv if a not in flags]
    do_export = "noexport" not in argv and "render" not in argv
    do_render = "norender" not in argv and not only
    C.reset_scene()
    report = []
    objs = {}
    for name, build in MODULES:
        if only and name not in only:
            continue
        RNG.seed(zlib.crc32(name.encode()))
        o = build(name)
        o.name = name
        objs[name] = o
        tris = tri_count(o)
        size = 0
        if do_export:
            path = os.path.join(OUT, name + ".glb")
            export(path, o)
            size = os.path.getsize(path)
        report.append((name, tris, size, bbox_godot(o)))
    print("MODULE               TRIS      BYTES   X-range        Y-range        Z-range (Godot)")
    for name, tris, size, (bx, by, bz) in report:
        print("%-18s %6d %10d   [%5.2f %5.2f]  [%5.2f %5.2f]  [%5.2f %5.2f]%s" % (
            name, tris, size, bx[0], bx[1], by[0], by[1], bz[0], bz[1], "  OVER BUDGET" if tris > TRI_BUDGET else ""))
    if FLAT_USED:
        print("FLAT (временные плоские материалы):", ", ".join(sorted(FLAT_USED)))
    else:
        print("materials: all PBR")
    bad = [r[0] for r in report if r[1] > TRI_BUDGET]
    if bad:
        print("ERROR: over budget:", bad)
        sys.exit(1)
    if do_render:
        render_contact(objs)


main()
