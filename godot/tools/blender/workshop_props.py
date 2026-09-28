#!/usr/bin/env python3
"""Пропсы столярной мастерской для look-dev по R22 (docs/refs/R22-a-hero-workshop-fight.jpg, ART_DIRECTION.md v3 §5)
и текстуры ударных эффектов. Настоящие меши Blender 4.5 с PBR-наборами из assets/textures/pbr (wood / wood_dark / iron,
печёт tools/blender/textures.py). Заготовка второй арены «workshop».

Запуск (headless):
    /Applications/Blender.app/Contents/MacOS/Blender -b --python godot/tools/blender/workshop_props.py [-- Имя … | textures]
    → godot/assets/models/workshop/<Name>.glb       (Y вверх в Godot; ≤ 3000 треугольников на объект, скрипт падает при превышении)
    → godot/assets/textures/fx/{mote,puff,wood_chip,shavings_decal}.png   (аргумент `textures` или всегда, если файлов нет)
Переменные окружения как у props.py: PROPS_TEX_SIZE (1024), PROPS_IMG (WEBP), PROPS_CACHE.

Соглашения (ASSET_PIPELINE.md, common.py): метры; Blender Z вверх, X вбок, «лицо» в −Y (в Godot +Z, к камере);
1 тайл текстуры = 1 м. Origin каждого объекта — документирован ниже, так его и ставит scenes/lookdev/workshop_lookdev.tscn.

Файлы и объекты:
    Workbench.glb      верстак 2.4 × 0.9 × 0.85: толстая столешница из трёх плах со стальными накладками, ноги 12 см,
                       проножки, полка, слева спереди тиски (подвижная губка, две направляющие, винт с рукояткой).
                       Origin — центр основания (z=0 пол), фронт −Y.
    Tool_Board.glb     щит 1.8 × 1.2 из пяти вертикальных досок с двумя рейками и 10 силуэтами инструментов
                       (молоток, киянка, ножовка, 2 стамески, рубанок, клещи, угольник, коловорот, рашпиль, шерхебель, бурав).
                       Origin — низ-центр, лицом −Y; вешать на стену за +Y.
    Window.glb         оконная рама 1.2 × 2.6 × 0.12 (косяки, импосты 2 × 4 → 15 стёкол, подоконник) + дочерний объект
                       Glass (прозрачное стекло, alpha 0.14 — в Godot BLEND). Origin низ-центр; рама занимает y ∈ [0, 0.12],
                       подоконник выступает в −Y (внутрь комнаты). Godot: MeshInstance3D «Glass» должен быть с cast_shadow OFF,
                       иначе стекло перекроет солнечные лучи (объёмный туман считается по shadow map).
    Wall_Window.glb    стеновой сегмент 1.6 × 5.0 с проёмом 1.2 × 2.6 (z 1.3..3.9 — окно ставить на y=1.3) под Window; вертикальные доски изнутри,
                       балки обвязки проёма. Origin низ-центр, ВНУТРЕННЯЯ плоскость досок y=0, толщина уходит в +Y (0.29).
    Wall_Plank.glb     глухой стеновой сегмент 4.0 × 5.0 (та же система: доски y ∈ [0, 0.04], сердечник до 0.29).
    Floor_Planks.glb   настил 12 × 6 м: ~90 досок 0.242 м вдоль X случайной длины со сдвигом швов, щели 6 мм, подложка Char.
                       Origin — центр верхней плоскости (z=0 — поверхность пола).
    Edge_Beam.glb      брус 12 × 0.45 × 0.45 (край сцены, как в R22 на переднем плане) с 5 стальными хомутами. Origin центр верха.
    Ceiling_Beams.glb  потолок 12 × 6: 4 стропильные балки вдоль X, 2 прогона вдоль Y, дощатый настил сверху. Origin низ балок.
    Shavings.glb       куча стружки: 16 завитков-лент (спирали) + 12 плоских щепок + дочерняя декаль Shavings_Decal 1.4 × 1.0
                       (опилки и мелкие завитки, alpha, лежит на полу). Origin центр основания.
    Lathe.glb          токарный станок 2.2 м: станина на двух козлах, передняя бабка с большим маховиком и спицами, шпиндель,
                       заготовка-балясина между центрами, задняя бабка с винтом и штурвалом, подручник, педаль. Origin центр
                       основания, ось станка вдоль X, маховик слева (−X).
    Turned_Post.glb    точёная стойка-балясина 1.8 м на квадратном основании 0.3. Origin центр основания.
    Foliage.glb        листва за окном: две скрещённые плоскости 2.2 × 3.2 с alpha-текстурой foliage.png (тёмно-зелёные
                       силуэты листьев) — даёт пятнистые лучи и зелень в проёмах. Origin низ-центр.

Компоненты арены «Мастерская» (scenes/props/workshop_*.tscn, собирает tools/build_workshop_props_scenes.gd):
    Floor_Tile.glb     плитка пола 12 × 2 м: 8 рядов досок 0.25 м случайной длины со сдвигом швов, щели 6 мм, подложка Char.
                       Мелкое волокно: набор pbr/wood_plank, если он есть на момент сборки, иначе maple_light с тинтом дуба
                       (1 тайл = 1 м, ~36 годовых колец на метр). Origin — центр верхней плоскости (z=0 — поверхность пола).
    Plank_Stack.glb    штабель досок 1.6 × 0.6 × 0.5: 6 слоёв по 3 доски на прокладках, доски разной длины и породы.
                       Origin — центр основания; верх ровный (площадка).
    Sawhorse.glb       козлы 0.9 × 0.5 × 0.6: брус, четыре расставленные ноги, проножки, косынки. Origin — центр основания.
    Shelf.glb          настенная полка 2.0 × 0.6 на двух кронштейнах; на ней банки, жестянка, ящичек, бухта верёвки, киянка.
                       Origin — середина ВЕРХНЕЙ плоскости у стены (задняя кромка), полка уходит в −Y (в комнату, Godot +Z).
    Lamp.glb           подвесная лампа: кольцо-крюк, цепь 3.6 м из овальных звеньев, патрон, эмалированный абажур ⌀0.65
                       (снаружи тёмно-зелёный, внутри кремовый), лампочка (эмиссия). Origin — точка подвеса (верх цепи),
                       всё висит в −Z; абажур z ∈ [−3.93, −3.68].
    Wall_Window_4m.glb стеновой сегмент 4.0 × 5.0 с ВЫСОКИМ проёмом 2.0 × 3.6 (z 0.9..4.5), рама 3 × 6 стёкол, внутренний
                       подоконник + дочерний объект Glass (alpha 0.14, BLEND; в Godot cast_shadow OFF). Система координат
                       как у Wall_Plank: внутренняя плоскость досок y=0, толщина в +Y. Origin низ-центр.
    Shavings_Wide.glb  широкая россыпь стружки: декаль 2.4 × 1.6 (assets/textures/workshop/shavings_wide.png) + 10 завитков
                       и 8 щепок. Origin центр основания.
    Foliage_Soft.glb   листва 2.8 × 3.6 почти без эмиссии (тёмные силуэты против яркого задника у высоких окон арены).

Задник за окнами (без Blender, системный python3 + Pillow):
    python3 godot/tools/blender/workshop_props.py --backdrop
    → godot/assets/textures/workshop/exterior_backdrop.png  (768 × 1536: тёплое небо с солнечным ореолом, дымка холмов,
      силуэты деревьев в нижней трети; квад 5.4 × 12.4 м ставит build_workshop_props_scenes.gd за проём окна)
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
except ImportError:  # системный python3: только --backdrop (Pillow)
    bpy = None
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
if bpy is not None:
    import common as C  # noqa: E402
    import textures as T  # noqa: E402  (save_rgba8, _vnoise, _poly_mask, _erode, _blur3)

GODOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(GODOT, "assets", "models", "workshop")
FX_TEX = os.path.join(GODOT, "assets", "textures", "fx")
WS_TEX = os.path.join(GODOT, "assets", "textures", "workshop")
BACKDROP_PNG = os.path.join(WS_TEX, "exterior_backdrop.png")
SHAVINGS_WIDE_PNG = os.path.join(WS_TEX, "shavings_wide.png")
TRI_BUDGET = 3000
TEX_SIZE = int(os.environ.get("PROPS_TEX_SIZE", "1024"))
IMG_FORMAT = os.environ.get("PROPS_IMG", "WEBP")
CACHE = os.environ.get("PROPS_CACHE") or os.path.join(tempfile.gettempdir(), "ragdoll_props_pbr")
TAU = 2.0 * math.pi
RNG = random.Random(22)


# ----------------------------------------------------------------------------------------------------------------------
# материалы
# ----------------------------------------------------------------------------------------------------------------------
_MATS = {}
# Пол арены: набор мелкого волокна wood_plank, если другой агент его уже испёк; иначе maple_light (прямое мелкое волокно).
FLOOR_FOLDER = "wood_plank" if (bpy is not None and os.path.isdir(os.path.join(C.PBR_DIR, "wood_plank"))) else "maple_light"


def pbr_folder(name):
    """Папка PBR-набора: исходная (2048²) или уменьшенная копия в кэше (PROPS_TEX_SIZE) — как в props.py."""
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
    """Материал по имени (лениво). Текстурные — wood / wood_dark / iron с тинтами под палитру R22."""
    if name in _MATS:
        return _MATS[name]
    tex = {
        "Wood": ("wood", {}),                                                       # тёплый дуб: стойка
        "WoodFloor": ("wood", {"tint": (0.78, 0.74, 0.68, 1.0), "roughness_scale": 1.1}),   # пол: приглушённый, серо-бурый
        "WoodBench": ("wood", {"tint": (0.82, 0.74, 0.62, 1.0), "roughness_scale": 1.1}),   # столешница, посеревшая
        "WoodPale": ("wood", {"tint": (1.0, 0.97, 0.90, 1.0)}),                     # свежий клён: заготовка
        "Shaving": ("wood", {"tint": (1.0, 0.94, 0.80, 1.0)}),                      # стружка (двусторонний)
        "WoodDark": ("wood_dark", {}),                                              # балки, ноги, станина
        "WoodGrey": ("wood_dark", {"tint": (0.44, 0.50, 0.55, 1.0), "roughness_scale": 1.15}),  # выветренные стены и рамы
        "Iron": ("iron", {}),
        "IronDark": ("iron", {"tint": (0.62, 0.62, 0.66, 1.0)}),
        "WoodFloorFine": (FLOOR_FOLDER, {"tint": (0.60, 0.45, 0.31, 1.0) if FLOOR_FOLDER == "maple_light" else (0.86, 0.80, 0.72, 1.0),
                                         "roughness_scale": 1.1, "normal_strength": 0.8}),   # пол арены: мелкое волокно, тёмный дуб
        "WoodFloorFineDark": (FLOOR_FOLDER, {"tint": (0.46, 0.34, 0.23, 1.0) if FLOOR_FOLDER == "maple_light" else (0.70, 0.64, 0.56, 1.0),
                                             "roughness_scale": 1.15, "normal_strength": 0.8}),   # ~1/3 досок темнее: разнобой
        "Rope": ("rope", {}),
    }
    flat = {
        "Char": ((0.045, 0.036, 0.030, 1.0), 0.95, 0.0),
        "Clay": ((0.36, 0.22, 0.15, 1.0), 0.72, 0.0),                    # глиняные банки на полке
        "Enamel": ((0.055, 0.14, 0.11, 1.0), 0.28, 0.0),                 # абажур снаружи, тёмно-зелёная эмаль
        "EnamelIn": ((0.92, 0.86, 0.72, 1.0), 0.45, 0.0),                # абажур изнутри, кремовый
    }
    if name in tex:
        folder, kw = tex[name]
        m = C.textured_material(name, pbr_folder(folder), **kw)
        m.use_backface_culling = name != "Shaving"
    elif name == "Glass":
        m = bpy.data.materials.new("Glass")
        m.use_nodes = True
        bsdf = m.node_tree.nodes.get("Principled BSDF")
        bsdf.inputs["Base Color"].default_value = (0.78, 0.86, 0.92, 1.0)
        bsdf.inputs["Alpha"].default_value = 0.14
        bsdf.inputs["Roughness"].default_value = 0.06
        bsdf.inputs["Metallic"].default_value = 0.0
        for attr, val in (('surface_render_method', 'BLENDED'), ('blend_method', 'BLEND')):
            try:
                setattr(m, attr, val)
            except Exception:
                pass
        m.use_backface_culling = False
    elif name == "Bulb":
        m = C.material("Bulb", (1.0, 0.94, 0.80, 1.0), 0.3, 0.0, emission=(1.0, 0.82, 0.52, 1.0), emission_strength=6.0)
    else:
        base, rough, metal = flat[name]
        m = C.material(name, base, rough, metal)
    _MATS[name] = m
    return m


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


DARK_MATS = ("WoodDark", "WoodGrey")   # wood_dark: 3 доски на тайл (швы на 0, 1/3, 2/3); wood: 4 доски (швы на k/4)


def box(name, size, mat, jitter=0.0, along='X', du=None, dv=None, scale=1.0):
    """Куб size с центром в нуле, кубическая UV в метрах × scale (волокна вдоль `along`); du/dv — сдвиг развёртки
    (по умолчанию центр случайной доски текстуры: доска ≤ 0.25 м (wood) / ≤ 0.33 м (wood_dark) не пересекает шов)."""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
    o = bpy.context.active_object
    o.name = name
    o.scale = size
    C.apply_transforms(o, scale=True)
    if jitter > 0.0:
        for v in o.data.vertices:
            v.co += Vector((RNG.uniform(-jitter, jitter), RNG.uniform(-jitter, jitter), RNG.uniform(-jitter, jitter)))
    C.uv_box(o, scale, along)
    if du is None:
        cols = 3 if mat.name in DARK_MATS else 4
        du = (0.5 + RNG.randrange(cols)) / cols
    if dv is None:
        dv = RNG.uniform(0.0, 1.0)
    for d in o.data.uv_layers[0].data:
        d.uv = (d.uv[0] + du, d.uv[1] + dv)
    o.data.materials.append(mat)
    return o


def place(o, loc=(0, 0, 0), rot=(0, 0, 0)):
    """Впекает поворот и позицию в геометрию; origin остаётся в мировом нуле."""
    if any(abs(r) > 1e-9 for r in rot):
        o.rotation_euler = rot
        C.apply_transforms(o, rotation=True)
    o.location = loc
    C.apply_transforms(o, location=True)
    return o


AXIS_ROT = {'Z': Matrix.Identity(4), 'Y': Matrix.Rotation(-math.pi / 2, 4, 'X'), 'X': Matrix.Rotation(math.pi / 2, 4, 'Y')} if bpy is not None else {}


def lathe(name, profile, segs=16, mat=None, axis='Z', uv_scale=1.0):
    """Тело вращения из профиля [(r, z), …] (r=0 — полюс), ось `axis`; UV цилиндрические, волокна вдоль оси."""
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
    if len(rings[0]) > 1:
        bm.faces.new(list(reversed(rings[0])))
    if len(rings[-1]) > 1:
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = mesh_obj(name, bm, [mat] if mat else [])
    C.uv_cylinder_along(o, 'Z', uv_scale, centre=(0.0, 0.0))
    o.data.transform(AXIS_ROT[axis])
    return o


def cyl(name, r, length, axis, mat, segs=12):
    return lathe(name, [(0.0, -length / 2), (r, -length / 2), (r, length / 2), (0.0, length / 2)], segs, mat, axis)


def tube(name, r_in, r_out, length, axis, mat, segs=16):
    """Кольцо/труба прямоугольного сечения вдоль оси."""
    h = length / 2
    o = lathe(name, [(r_in, -h), (r_out, -h), (r_out, h), (r_in, h), (r_in, -h)], segs, mat, axis)
    return o


def sphere(name, r, mat, segs=10, rings=6):
    o = C.add_sphere(name, r, loc=(0, 0, 0), segments=segs, rings=rings)
    C.uv_box(o, 1.0)
    o.data.materials.append(mat)
    return o


def rivet(name, loc, direction, r=0.009, h=0.010, mat=None):
    d = Vector(direction).normalized()
    rot = d.to_track_quat('Z', 'Y').to_euler()
    bpy.ops.mesh.primitive_cylinder_add(vertices=6, radius=r, depth=h, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    C.apply_transforms(o, location=True, rotation=True)
    o.data.materials.append(mat or M("Iron"))
    C.uv_box(o, 1.0)
    return o


def plate(name, pts_xz, thickness, mat, y=0.0):
    """Плоская деталь: выпуклый многоугольник в плоскости XZ [(x, z), …] толщиной вдоль Y."""
    bm = bmesh.new()
    front = [bm.verts.new((x, y - thickness / 2, z)) for x, z in pts_xz]
    back = [bm.verts.new((x, y + thickness / 2, z)) for x, z in pts_xz]
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    n = len(front)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((front[j], front[i], back[i], back[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = mesh_obj(name, bm, [mat])
    C.uv_box(o, 1.0, 'Z')
    return o


def bevel_apply(o, width, segments=1, angle=30.0):
    m = C.bevel(o, width, segments, angle)
    m.harden_normals = True
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


# ----------------------------------------------------------------------------------------------------------------------
# Workbench
# ----------------------------------------------------------------------------------------------------------------------
def workbench(name):
    L, W, H, top_t = 2.4, 0.9, 0.85, 0.10
    parts = []
    for i, y in enumerate((-0.30, 0.0, 0.30)):
        s = box("top%d" % i, (L, 0.29, top_t), M("WoodBench"), jitter=0.004)
        place(s, (0, y, H - top_t / 2 + RNG.uniform(-0.004, 0.004)))
        parts.append(bevel_apply(s, 0.014))
    for x in (-1.05, 1.05):
        for y in (-0.33, 0.33):
            leg = box("leg", (0.12, 0.12, H - top_t), M("WoodDark"), along='Z')
            place(leg, (x, y, (H - top_t) / 2))
            parts.append(bevel_apply(leg, 0.008))
        s = box("strY", (0.08, 0.66, 0.12), M("WoodDark"), along='Y')
        place(s, (x, 0, 0.20))
        parts.append(s)
    for y in (-0.33, 0.33):
        s = box("strX", (2.1, 0.08, 0.12), M("WoodDark"))
        place(s, (0, y, 0.20))
        parts.append(s)
    for i, y in enumerate((-0.22, 0.0, 0.22)):
        s = box("shelf%d" % i, (2.05, 0.20, 0.03), M("WoodDark"), jitter=0.002)
        place(s, (0, y, 0.275))
        parts.append(s)
    for y in (-0.40, 0.40):
        a = box("apron", (2.3, 0.04, 0.14), M("WoodDark"))
        place(a, (0, y, H - top_t - 0.07))
        parts.append(a)
    for x in (-1.12, 1.12):                                   # стальные накладки на торцах столешницы
        st = box("strap", (0.06, 0.92, 0.006), M("Iron"))
        place(st, (x, 0, H + 0.003))
        parts.append(st)
        for y in (-0.36, -0.12, 0.12, 0.36):
            parts.append(rivet("rv", (x, y, H + 0.006), (0, 0, 1)))
    # тиски слева спереди
    vx = -0.70
    jy = -W / 2 - 0.13                                        # центр подвижной губки
    jaw = box("jaw", (0.32, 0.08, 0.24), M("WoodDark"), along='Z')
    place(jaw, (vx, jy, H - 0.12))
    parts.append(bevel_apply(jaw, 0.008))
    p1 = box("jawplate", (0.30, 0.012, 0.09), M("Iron"))
    place(p1, (vx, jy + 0.046, H - 0.045))
    parts.append(p1)
    p2 = box("fixedplate", (0.30, 0.012, 0.09), M("Iron"))
    place(p2, (vx, -W / 2 - 0.006, H - 0.045))
    parts.append(p2)
    for dx in (-0.11, 0.11):
        g = cyl("guide", 0.014, 0.62, 'Y', M("IronDark"), segs=10)
        place(g, (vx + dx, -W / 2 - 0.02, H - 0.135))
        parts.append(g)
    screw = cyl("screw", 0.020, 0.66, 'Y', M("Iron"), segs=12)
    place(screw, (vx, -W / 2 - 0.12, H - 0.195))
    parts.append(screw)
    for k in range(5):                                        # витки резьбы
        th = tube("thread", 0.020, 0.027, 0.012, 'Y', M("Iron"), segs=12)
        place(th, (vx, jy - 0.08 - k * 0.036, H - 0.195))
        parts.append(th)
    collar = tube("collar", 0.02, 0.04, 0.05, 'Y', M("Iron"), segs=12)
    place(collar, (vx, jy - 0.06, H - 0.195))
    parts.append(collar)
    hy = -W / 2 - 0.44
    hb = cyl("handle", 0.011, 0.36, 'X', M("IronDark"), segs=10)
    place(hb, (vx + 0.06, hy, H - 0.195))
    parts.append(hb)
    for dx in (-0.12, 0.24):
        k = sphere("knob", 0.022, M("Iron"))
        place(k, (vx + dx, hy, H - 0.195))
        parts.append(k)
    o = merge(parts, name)
    return finish(o, 30.0)


# ----------------------------------------------------------------------------------------------------------------------
# Tool_Board
# ----------------------------------------------------------------------------------------------------------------------
TOOL_Y = -0.075   # средняя плоскость инструментов перед досками (доски y∈[-0.02,0.02], рейки до -0.05)


def _tool_box(parts, name, size, mat, x, z, y=TOOL_Y, rot_y=0.0, along='Z'):
    o = box(name, size, mat, along=along)
    place(o, (x, y, z), (0, rot_y, 0))
    parts.append(o)
    return o


def _peg(parts, x, z):
    p = cyl("peg", 0.008, 0.07, 'Y', M("WoodDark"), segs=6)
    place(p, (x, -0.045, z))
    parts.append(p)


def tool_board(name):
    bw, bh, bt = 1.8, 1.2, 0.04
    parts = []
    n = 5
    pw = (bw - 0.0125 * (n - 1)) / n
    for i in range(n):
        x = -bw / 2 + pw / 2 + i * (pw + 0.0125)
        p = box("plank%d" % i, (pw, bt, bh), M("WoodGrey"), jitter=0.002, along='Z')
        place(p, (x, 0, bh / 2))
        parts.append(p)
    for z in (0.12, 1.08):
        b = box("batten", (bw, 0.03, 0.08), M("WoodDark"))
        place(b, (0, -bt / 2 - 0.015, z))
        parts.append(b)
    ir, wd, wg = M("Iron"), M("Wood"), M("WoodDark")
    # 1 молоток
    x, z = -0.78, 1.0
    _tool_box(parts, "hammer_h", (0.03, 0.012, 0.30), wd, x, z - 0.15)
    _tool_box(parts, "hammer_head", (0.11, 0.026, 0.045), ir, x, z)
    _peg(parts, x - 0.035, z + 0.01)
    _peg(parts, x + 0.035, z + 0.01)
    # 2 киянка
    x, z = -0.60, 0.98
    _tool_box(parts, "mallet_h", (0.028, 0.012, 0.26), wd, x, z - 0.14)
    mh = cyl("mallet_head", 0.045, 0.12, 'X', wg, segs=10)
    place(mh, (x, TOOL_Y, z))
    parts.append(mh)
    _peg(parts, x, z + 0.06)
    # 3 ножовка (лезвие вниз)
    x, z = -0.40, 1.02
    saw = plate("saw_blade", [(-0.055, 0.0), (0.055, 0.0), (0.022, -0.44), (-0.022, -0.44)], 0.004, ir, TOOL_Y)
    place(saw, (x, 0, z - 0.08))
    parts.append(saw)
    _tool_box(parts, "saw_handle", (0.10, 0.016, 0.10), wd, x, z - 0.03)
    _peg(parts, x, z + 0.03)
    # 4-5 стамески
    for k, (x, z) in enumerate(((-0.22, 0.95), (-0.13, 0.93))):
        _tool_box(parts, "chisel_b%d" % k, (0.02, 0.006, 0.15), ir, x, z - 0.075)
        ch = cyl("chisel_h%d" % k, 0.014, 0.11, 'Z', wd, segs=8)
        place(ch, (x, TOOL_Y, z + 0.055))
        parts.append(ch)
        fe = tube("ferrule%d" % k, 0.012, 0.016, 0.014, 'Z', ir, segs=8)
        place(fe, (x, TOOL_Y, z + 0.004))
        parts.append(fe)
        _peg(parts, x, z + 0.12)
    # 6 рубанок
    x, z = 0.05, 0.92
    _tool_box(parts, "plane_body", (0.24, 0.06, 0.05), wd, x, z, y=TOOL_Y - 0.01, along='X')
    knob = sphere("plane_knob", 0.02, wg)
    place(knob, (x - 0.09, TOOL_Y - 0.01, z + 0.04))
    parts.append(knob)
    _tool_box(parts, "plane_blade", (0.032, 0.05, 0.005), ir, x + 0.03, z + 0.035, y=TOOL_Y - 0.01, rot_y=math.radians(-45))
    _tool_box(parts, "plane_tote", (0.026, 0.05, 0.06), wd, x + 0.085, z + 0.045, y=TOOL_Y - 0.01)
    _peg(parts, x - 0.09, z - 0.035)
    _peg(parts, x + 0.09, z - 0.035)
    # 7 клещи
    x, z = 0.26, 0.98
    for s in (-1, 1):
        _tool_box(parts, "pliers", (0.02, 0.008, 0.21), ir, x, z - 0.105, rot_y=s * math.radians(9))
    _tool_box(parts, "pliers_jaw", (0.05, 0.012, 0.03), ir, x, z + 0.005)
    _peg(parts, x, z + 0.03)
    # 8 угольник
    x, z = 0.44, 0.98
    _tool_box(parts, "square_a", (0.22, 0.006, 0.026), ir, x + 0.09, z, along='X')
    _tool_box(parts, "square_b", (0.032, 0.012, 0.20), wd, x - 0.01, z - 0.10)
    _peg(parts, x + 0.16, z + 0.02)
    # 9 коловорот
    x, z = 0.66, 1.0
    knob = sphere("brace_knob", 0.026, wd)
    place(knob, (x, TOOL_Y, z))
    parts.append(knob)
    _tool_box(parts, "brace_a", (0.024, 0.018, 0.10), ir, x, z - 0.07)
    _tool_box(parts, "brace_b", (0.14, 0.018, 0.024), ir, x + 0.06, z - 0.13, along='X')
    _tool_box(parts, "brace_c", (0.024, 0.018, 0.12), ir, x + 0.12, z - 0.20)
    grip = cyl("brace_grip", 0.016, 0.07, 'Z', wd, segs=8)
    place(grip, (x + 0.12, TOOL_Y, z - 0.20))
    parts.append(grip)
    _tool_box(parts, "brace_d", (0.14, 0.018, 0.024), ir, x + 0.06, z - 0.27, along='X')
    _tool_box(parts, "brace_e", (0.024, 0.018, 0.10), ir, x, z - 0.33)
    bit = cyl("brace_bit", 0.008, 0.10, 'Z', ir, segs=6)
    place(bit, (x, TOOL_Y, z - 0.42))
    parts.append(bit)
    _peg(parts, x - 0.03, z + 0.01)
    # 10 рашпиль
    x, z = 0.84, 0.95
    _tool_box(parts, "rasp", (0.026, 0.006, 0.24), ir, x, z - 0.12)
    rh = cyl("rasp_h", 0.015, 0.09, 'Z', wd, segs=8)
    place(rh, (x, TOOL_Y, z + 0.045))
    parts.append(rh)
    _peg(parts, x, z + 0.10)
    # 11 шерхебель-скобель (горизонтально, нижний ряд)
    x, z = -0.55, 0.45
    _tool_box(parts, "shave_bar", (0.24, 0.012, 0.03), ir, x, z, along='X')
    for s in (-1, 1):
        hd = cyl("shave_h", 0.014, 0.08, 'X', wd, segs=8)
        place(hd, (x + s * 0.15, TOOL_Y, z))
        parts.append(hd)
    _peg(parts, x - 0.09, z + 0.025)
    _peg(parts, x + 0.09, z + 0.025)
    # 12 бурав с Т-ручкой (нижний ряд)
    x, z = 0.15, 0.55
    ag = cyl("auger", 0.011, 0.36, 'Z', ir, segs=8)
    place(ag, (x, TOOL_Y, z - 0.18))
    parts.append(ag)
    _tool_box(parts, "auger_t", (0.18, 0.022, 0.022), wd, x, z + 0.01, along='X')
    _peg(parts, x - 0.05, z + 0.03)
    _peg(parts, x + 0.05, z + 0.03)
    # 13 второй молоток-кувалдочка (нижний ряд справа)
    x, z = 0.62, 0.52
    _tool_box(parts, "sledge_h", (0.03, 0.012, 0.30), wd, x, z - 0.15)
    _tool_box(parts, "sledge_head", (0.09, 0.05, 0.05), ir, x, z)
    _peg(parts, x - 0.035, z + 0.02)
    _peg(parts, x + 0.035, z + 0.02)
    o = merge(parts, name)
    return finish(o, 30.0)


# ----------------------------------------------------------------------------------------------------------------------
# Window, Wall_Window, Wall_Plank
# ----------------------------------------------------------------------------------------------------------------------
WIN_W, WIN_H, WIN_D, FR = 1.2, 2.6, 0.12, 0.08
WIN_SILL = 1.3      # низ проёма в Wall_Window
WALL_T = 0.25        # сердечник
PLANK_T = 0.04       # внутренняя обшивка


def window(name):
    parts = []
    yc = WIN_D / 2
    for x in (-WIN_W / 2 + FR / 2, WIN_W / 2 - FR / 2):
        j = box("jamb", (FR, WIN_D, WIN_H), M("WoodGrey"), along='Z')
        place(j, (x, yc, WIN_H / 2))
        parts.append(j)
    head = box("head", (WIN_W - 2 * FR, WIN_D, FR), M("WoodGrey"))
    place(head, (0, yc, WIN_H - FR / 2))
    parts.append(head)
    bottom = box("bottom", (WIN_W - 2 * FR, WIN_D, FR), M("WoodGrey"))
    place(bottom, (0, yc, FR / 2))
    parts.append(bottom)
    sill = box("sill", (WIN_W + 0.16, 0.24, 0.05), M("WoodGrey"))
    place(sill, (0, WIN_D / 2 - 0.08, 0.025))
    parts.append(bevel_apply(sill, 0.01))
    inner_h = WIN_H - 2 * FR
    for x in (-0.19, 0.19):
        m = box("mull_v", (0.036, 0.06, inner_h), M("WoodGrey"), along='Z')
        place(m, (x, yc, WIN_H / 2))
        parts.append(m)
    for k in range(1, 5):
        z = FR + inner_h * k / 5
        m = box("mull_h", (WIN_W - 2 * FR, 0.06, 0.036), M("WoodGrey"))
        place(m, (0, yc, z))
        parts.append(m)
    frame = finish(merge(parts, name), 30.0)
    bpy.ops.mesh.primitive_plane_add(size=1.0, location=(0, 0, 0))
    g = bpy.context.active_object
    g.name = "Glass"
    g.data.transform(Matrix.Diagonal((WIN_W - 2 * FR, WIN_H - 2 * FR, 1.0, 1.0)))
    g.data.transform(Matrix.Rotation(math.pi / 2.0, 4, 'X'))     # нормаль → −Y (внутрь комнаты)
    g.data.materials.append(M("Glass"))
    place(g, (0, yc, WIN_H / 2))
    C.set_origin(g, (0, 0, 0))
    C.parent(g, frame)
    return frame


def _wall_core(parts, width, height, opening=None):
    """Сердечник стены y ∈ [PLANK_T, PLANK_T + WALL_T]; opening = (x0, x1, z0, z1)."""
    yc = PLANK_T + WALL_T / 2
    if opening is None:
        c = box("core", (width, WALL_T, height), M("WoodDark"), along='Z')
        place(c, (0, yc, height / 2))
        parts.append(c)
        return
    x0, x1, z0, z1 = opening
    hw = width / 2
    for nm, sx, sz, cx, cz in (("core_b", width, z0, 0, z0 / 2), ("core_t", width, height - z1, 0, (height + z1) / 2),
                               ("core_l", x0 + hw, z1 - z0, (x0 - hw) / 2, (z0 + z1) / 2), ("core_r", hw - x1, z1 - z0, (x1 + hw) / 2, (z0 + z1) / 2)):
        if sx <= 1e-6 or sz <= 1e-6:
            continue
        c = box(nm, (sx, WALL_T, sz), M("WoodDark"), along='Z')
        place(c, (cx, yc, cz))
        parts.append(c)


def _wall_planks(parts, width, height, opening=None, pw=0.2, gap=0.006):
    n = int(round(width / pw))
    pw_eff = (width - gap * (n - 1)) / n
    for i in range(n):
        x = -width / 2 + pw_eff / 2 + i * (pw_eff + gap)
        spans = [(0.0, height)]
        if opening is not None:
            x0, x1, z0, z1 = opening
            if x + pw_eff / 2 > x0 + 1e-6 and x - pw_eff / 2 < x1 - 1e-6:
                spans = [(0.0, z0), (z1, height)]
        for a, b in spans:
            if b - a < 0.02:
                continue
            p = box("plank", (pw_eff, PLANK_T, b - a), M("WoodGrey"), jitter=0.0015, along='Z', scale=1.5)
            place(p, (x, PLANK_T / 2, (a + b) / 2))
            parts.append(p)


def wall_plank(name, width=4.0, height=5.0):
    parts = []
    _wall_core(parts, width, height)
    _wall_planks(parts, width, height)
    rail = box("rail", (width, 0.05, 0.10), M("WoodDark"))
    place(rail, (0, -0.025, 1.05))
    parts.append(rail)
    return finish(merge(parts, name), 30.0)


def wall_window(name, width=1.6, height=5.0):
    parts = []
    op = (-WIN_W / 2, WIN_W / 2, WIN_SILL, WIN_SILL + WIN_H)
    _wall_core(parts, width, height, op)
    _wall_planks(parts, width, height, op)
    z0, z1 = op[2], op[3]
    for x in (-WIN_W / 2 - 0.05, WIN_W / 2 + 0.05):
        post = box("post", (0.10, PLANK_T + WALL_T, z1 - z0 + 0.2), M("WoodDark"), along='Z')
        place(post, (x, (PLANK_T + WALL_T) / 2 - 0.01, (z0 + z1) / 2))
        parts.append(bevel_apply(post, 0.008))
    lintel = box("lintel", (WIN_W + 0.36, PLANK_T + WALL_T + 0.02, 0.14), M("WoodDark"))
    place(lintel, (0, (PLANK_T + WALL_T) / 2 - 0.02, z1 + 0.17))
    parts.append(bevel_apply(lintel, 0.01))
    sillb = box("sillbeam", (WIN_W + 0.36, PLANK_T + WALL_T + 0.02, 0.10), M("WoodDark"))
    place(sillb, (0, (PLANK_T + WALL_T) / 2 - 0.02, z0 - 0.15))
    parts.append(bevel_apply(sillb, 0.01))
    return finish(merge(parts, name), 30.0)


# ----------------------------------------------------------------------------------------------------------------------
# Floor_Planks, Edge_Beam, Ceiling_Beams
# ----------------------------------------------------------------------------------------------------------------------
def floor_planks(name, length=12.0, depth=6.0, pw=0.25, gap=0.006, t=0.05):
    parts = []
    rows = int(round(depth / pw))
    for r in range(rows):
        y = -depth / 2 + pw / 2 + r * pw
        x = -length / 2
        while x < length / 2 - 0.05:
            L = min(RNG.uniform(2.2, 4.6), length / 2 - x)
            if length / 2 - (x + L) < 0.9:
                L = length / 2 - x
            p = box("plank", (L - gap, pw - gap, t), M("WoodFloor"), jitter=0.0)
            place(p, (x + L / 2, y, -t / 2 + RNG.uniform(-0.003, 0.002)))
            parts.append(p)
            x += L
    under = box("under", (length, depth, 0.02), M("Char"))
    place(under, (0, 0, -t - 0.005))
    parts.append(under)
    return finish(merge(parts, name), 30.0)


def edge_beam(name, length=12.0, s=0.45):
    parts = []
    b = box("beam", (length, s, s), M("WoodDark"), jitter=0.003)
    place(b, (0, 0, -s / 2))
    parts.append(bevel_apply(b, 0.02))
    for x in (-5.4, -2.7, 0.0, 2.7, 5.4):
        st = box("strap", (0.10, s + 0.012, s + 0.012), M("Iron"))
        place(st, (x, 0, -s / 2))
        parts.append(st)
        for (dy, dz, d) in ((-s / 2 - 0.006, -0.10, (0, -1, 0)), (-s / 2 - 0.006, -s + 0.10, (0, -1, 0)), (-0.10, 0.006, (0, 0, 1)), (0.10, 0.006, (0, 0, 1))):
            parts.append(rivet("rv", (x, dy, dz), d, r=0.012, h=0.012))
    return finish(merge(parts, name), 30.0)


def ceiling_beams(name, length=12.0, depth=6.0):
    parts = []
    for y in (-2.4, -0.8, 0.8, 2.4):
        b = box("rafter", (length, 0.26, 0.32), M("WoodDark"), jitter=0.003)
        place(b, (0, y, 0.16))
        parts.append(bevel_apply(b, 0.015))
    for x in (-3.0, 3.0):
        b = box("purlin", (0.22, depth, 0.26), M("WoodDark"), along='Y')
        place(b, (x, 0, 0.32 + 0.13))
        parts.append(b)
    deck = box("deck", (length, depth, 0.03), M("WoodGrey"), along='Y')
    place(deck, (0, 0, 0.32 + 0.26 + 0.015))
    parts.append(deck)
    return finish(merge(parts, name), 30.0)


# ----------------------------------------------------------------------------------------------------------------------
# Shavings
# ----------------------------------------------------------------------------------------------------------------------
def curl(name, r, turns, width, pitch, seg_per_turn=12):
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    n = max(3, int(turns * seg_per_turn))
    rows = []
    arc = 0.0
    prev = None
    for i in range(n + 1):
        a = TAU * i / seg_per_turn
        rr = r * (1.0 + 0.10 * math.sin(a * 0.7 + 1.0)) * (1.0 - 0.12 * i / n)
        z = pitch * a / TAU
        p = Vector((rr * math.cos(a), rr * math.sin(a), z))
        if prev is not None:
            arc += (p - prev).length
        prev = p
        rows.append((bm.verts.new(p), bm.verts.new(p + Vector((0, 0, width))), arc))
    for i in range(n):
        f = bm.faces.new((rows[i][0], rows[i + 1][0], rows[i + 1][1], rows[i][1]))
        for l in f.loops:
            top = 1.0 if l.vert in (rows[i][1], rows[i + 1][1]) else 0.0
            a_ = rows[i + 1][2] if l.vert in (rows[i + 1][0], rows[i + 1][1]) else rows[i][2]
            l[uv].uv = (0.06 + top * width * 2.0, a_ * 2.0)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return mesh_obj(name, bm, [M("Shaving")])


def shavings(name):
    parts = []
    for i in range(16):
        r = RNG.uniform(0.012, 0.030)
        o = curl("curl%d" % i, r, RNG.uniform(1.4, 3.0), RNG.uniform(0.012, 0.022), RNG.uniform(0.004, 0.010))
        rot = Matrix.Rotation(RNG.uniform(0, TAU), 4, 'Z') @ Matrix.Rotation(RNG.choice((0.0, 0.0, math.pi / 2, RNG.uniform(0.3, 1.2))), 4, 'X') @ Matrix.Rotation(RNG.uniform(0, TAU), 4, 'Z')
        o.data.transform(rot)
        zmin = min(v.co.z for v in o.data.vertices)
        ang = RNG.uniform(0, TAU)
        rad = abs(RNG.gauss(0.0, 0.22))
        place(o, (rad * math.cos(ang), rad * math.sin(ang) * 0.7, -zmin + 0.002))
        parts.append(o)
    for i in range(12):
        L, W = RNG.uniform(0.03, 0.07), RNG.uniform(0.008, 0.02)
        ch = plate("chip%d" % i, [(-L / 2, -W / 2), (L / 2 * 0.8, -W / 2 * 0.6), (L / 2, W / 2 * 0.3), (-L / 2 * 0.7, W / 2)], 0.003, M("Shaving"))
        ch.data.transform(Matrix.Rotation(math.pi / 2, 4, 'X'))   # в плоскость XY
        ang = RNG.uniform(0, TAU)
        rad = abs(RNG.gauss(0.0, 0.3))
        place(ch, (rad * math.cos(ang), rad * math.sin(ang) * 0.7, 0.0025), (0, 0, RNG.uniform(0, TAU)))
        parts.append(ch)
    pile = finish(merge(parts, name), 40.0)
    dec = C.decal_plane("Shavings_Decal", os.path.join(FX_TEX, "shavings_decal.png"), (1.4, 1.0), (0, 0, 0))
    dec.data.transform(Matrix.Rotation(-math.pi / 2.0, 4, 'X'))   # обратно в плоскость пола, нормаль +Z
    place(dec, (0, 0, 0.003))
    C.set_origin(dec, (0, 0, 0))
    C.parent(dec, pile)
    return pile


# ----------------------------------------------------------------------------------------------------------------------
# Lathe, Turned_Post
# ----------------------------------------------------------------------------------------------------------------------
BALUSTER = [(0.0, 0.0), (0.06, 0.0), (0.06, 0.05), (0.085, 0.09), (0.09, 0.14), (0.07, 0.19), (0.055, 0.24), (0.05, 0.42),
            (0.065, 0.48), (0.085, 0.52), (0.06, 0.57), (0.05, 0.62), (0.05, 0.78), (0.075, 0.84), (0.085, 0.88), (0.06, 0.93),
            (0.055, 0.98), (0.0, 0.98)]


def lathe_machine(name):
    parts = []
    bed_z = 0.80
    for y in (-0.13, 0.13):
        b = box("bed", (2.2, 0.12, 0.14), M("WoodDark"))
        place(b, (0, y, bed_z + 0.07))
        parts.append(bevel_apply(b, 0.008))
    for x in (-0.75, 0.75):                                   # козлы: две наклонные ноги + башмак + поперечина
        for s in (-1, 1):
            leg = box("leg", (0.10, 0.10, 0.84), M("WoodDark"), along='Z')
            place(leg, (x, s * 0.19, 0.42), (s * math.radians(-14), 0, 0))
            parts.append(leg)
        foot = box("foot", (0.14, 0.74, 0.08), M("WoodDark"), along='Y')
        place(foot, (x, 0, 0.04))
        parts.append(foot)
        cross = box("cross", (0.08, 0.5, 0.08), M("WoodDark"), along='Y')
        place(cross, (x, 0, 0.45))
        parts.append(cross)
    tie = box("tie", (1.5, 0.08, 0.10), M("WoodDark"))
    place(tie, (0, 0, 0.45))
    parts.append(tie)
    # передняя бабка
    hs = box("headstock", (0.30, 0.36, 0.40), M("WoodDark"), along='Z')
    place(hs, (-0.75, 0, bed_z + 0.14 + 0.20))
    parts.append(bevel_apply(hs, 0.01))
    axis_z = bed_z + 0.14 + 0.26
    spindle = cyl("spindle", 0.02, 0.62, 'X', M("Iron"), segs=10)
    place(spindle, (-0.86, 0, axis_z))
    parts.append(spindle)
    wheel = tube("wheel", 0.40, 0.46, 0.05, 'X', M("WoodDark"), segs=28)
    place(wheel, (-1.05, 0, axis_z))
    parts.append(wheel)
    rim = tube("rim", 0.46, 0.475, 0.056, 'X', M("Iron"), segs=28)
    place(rim, (-1.05, 0, axis_z))
    parts.append(rim)
    hub = cyl("hub", 0.07, 0.10, 'X', M("WoodDark"), segs=12)
    place(hub, (-1.05, 0, axis_z))
    parts.append(hub)
    for k in range(6):
        sp = box("spoke", (0.035, 0.035, 0.36), M("WoodDark"), along='Z')
        place(sp, (-1.05, 0, 0), (0, 0, 0))
        sp.data.transform(Matrix.Translation((0, 0, 0.22)))
        sp.data.transform(Matrix.Rotation(TAU * k / 6, 4, 'X'))
        sp.data.transform(Matrix.Translation((0, 0, axis_z)))
        parts.append(sp)
    crank = cyl("crank", 0.012, 0.16, 'X', M("Iron"), segs=8)
    place(crank, (-1.16, 0, axis_z + 0.30))
    parts.append(crank)
    # заготовка между центрами
    work = lathe("work", BALUSTER, segs=16, mat=M("WoodPale"), axis='X', uv_scale=1.0)
    place(work, (-0.55, 0, axis_z))
    parts.append(work)
    # задняя бабка
    ts = box("tailstock", (0.22, 0.30, 0.34), M("WoodDark"), along='Z')
    place(ts, (0.62, 0, bed_z + 0.14 + 0.17))
    parts.append(bevel_apply(ts, 0.01))
    tsc = cyl("tail_screw", 0.018, 0.50, 'X', M("Iron"), segs=10)
    place(tsc, (0.62, 0, axis_z))
    parts.append(tsc)
    hw = tube("handwheel", 0.07, 0.09, 0.02, 'X', M("Iron"), segs=14)
    place(hw, (0.92, 0, axis_z))
    parts.append(hw)
    for k in range(4):
        sp = box("hw_spoke", (0.012, 0.012, 0.14), M("Iron"), along='Z')
        sp.data.transform(Matrix.Rotation(TAU * k / 4 + 0.4, 4, 'X'))
        place(sp, (0.92, 0, axis_z))
        parts.append(sp)
    # подручник
    post = box("rest_post", (0.04, 0.04, 0.26), M("Iron"), along='Z')
    place(post, (0.0, -0.22, bed_z + 0.14 + 0.13))
    parts.append(post)
    bar = box("rest_bar", (0.55, 0.03, 0.03), M("Iron"))
    place(bar, (0.0, -0.22, axis_z - 0.02))
    parts.append(bar)
    # педаль и тяга
    ped = box("treadle", (1.0, 0.20, 0.03), M("WoodDark"))
    place(ped, (-0.6, -0.05, 0.06), (math.radians(-8), 0, 0))
    parts.append(ped)
    rod = cyl("rod", 0.008, 1.5, 'Z', M("Iron"), segs=6)
    place(rod, (-1.16, 0, 0.8))
    parts.append(rod)
    return finish(merge(parts, name), 30.0)


def turned_post(name):
    parts = []
    base = box("base", (0.30, 0.30, 0.22), M("Wood"), along='Z')
    place(base, (0, 0, 0.11))
    parts.append(bevel_apply(base, 0.015))
    prof = [(0.0, 0.22), (0.12, 0.22), (0.14, 0.25), (0.15, 0.30), (0.11, 0.36), (0.10, 0.62), (0.135, 0.70), (0.16, 0.76),
            (0.12, 0.83), (0.105, 0.90), (0.10, 1.18), (0.13, 1.26), (0.15, 1.31), (0.115, 1.38), (0.10, 1.55), (0.13, 1.62),
            (0.12, 1.68), (0.09, 1.74), (0.05, 1.80), (0.0, 1.80)]
    p = lathe("post", prof, segs=20, mat=M("Wood"), axis='Z', uv_scale=1.0)
    parts.append(p)
    cap = box("cap", (0.24, 0.24, 0.05), M("Wood"), along='Z')
    place(cap, (0, 0, 1.825))
    parts.append(bevel_apply(cap, 0.01))
    return finish(merge(parts, name), 30.0)


def foliage(name, w=2.2, h=3.2, emission=1.4, mat_name="Foliage"):
    """Листва: две скрещённые alpha-плоскости. Foliage — светящаяся (look-dev, маленькие окна);
    Foliage_Soft — почти без эмиссии, крупнее: тёмные силуэты против яркого задника у высоких окон арены."""
    planes = []
    for k, yaw in enumerate((math.radians(25), math.radians(-65))):
        q = C.decal_plane("leaf%d" % k, os.path.join(FX_TEX, "foliage.png"), (w, h), (0, 0, 0))
        q.data.transform(Matrix.Translation((0, 0, h / 2)))
        q.data.transform(Matrix.Rotation(yaw, 4, 'Z'))
        mat = q.data.materials[0]
        mat.use_backface_culling = False
        mat.name = mat_name
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        bsdf.inputs["Emission Color"].default_value = (0.30, 0.52, 0.10, 1.0)   # просвет листвы против неба
        bsdf.inputs["Emission Strength"].default_value = emission
        planes.append(q)
    o = merge(planes, name)
    C.set_origin(o, (0, 0, 0))
    return o


# ----------------------------------------------------------------------------------------------------------------------
# Компоненты арены «Мастерская»: Floor_Tile, Plank_Stack, Sawhorse, Shelf, Lamp, Wall_Window_4m, Shavings_Wide
# ----------------------------------------------------------------------------------------------------------------------
def floor_tile(name, length=12.0, depth=2.0, pw=0.25, gap=0.006, t=0.05):
    """Плитка пола 12 × 2: 8 рядов досок случайной длины, швы сдвинуты по рядам. Волокно вдоль X, 1 тайл = 1 м."""
    parts = []
    rows = int(round(depth / pw))
    for r in range(rows):
        y = -depth / 2 + pw / 2 + r * pw
        x = -length / 2
        first = True
        while x < length / 2 - 0.05:
            L = RNG.uniform(0.7, 2.2) if first else RNG.uniform(1.6, 3.4)
            L = min(L, length / 2 - x)
            if length / 2 - (x + L) < 0.6:
                L = length / 2 - x
            mat = M("WoodFloorFineDark") if RNG.random() < 0.32 else M("WoodFloorFine")
            p = box("plank", (L - gap, pw - gap, t), mat, du=RNG.uniform(0.0, 1.0), dv=RNG.uniform(0.0, 1.0))
            place(p, (x + L / 2, y, -t / 2 + RNG.uniform(-0.003, 0.002)))
            parts.append(p)
            x += L
            first = False
    under = box("under", (length, depth, 0.02), M("Char"))
    place(under, (0, 0, -t - 0.005))
    parts.append(under)
    return finish(merge(parts, name), 30.0)


def plank_stack(name, L=1.6, W=0.6, H=0.5, layers=6):
    """Штабель 1.6 × 0.6 × 0.5: слои по 3 доски (0.18 × 0.05) на прокладках 0.04; верх ровный."""
    parts = []
    pt, st = 0.05, (H - layers * 0.05) / (layers - 1)
    pw = 0.18
    for k in range(layers):
        z = k * (pt + st) + pt / 2
        for i, y in enumerate((-0.21, 0.0, 0.21)):
            Lk = RNG.uniform(1.30, L)
            mat = M("WoodPale") if (k + i) % 3 else M("WoodBench")
            pl = box("plank", (Lk, pw, pt), mat, jitter=0.0015)
            place(pl, (RNG.uniform(-(L - Lk) / 2, (L - Lk) / 2) * 0.6, y + RNG.uniform(-0.01, 0.01), z))
            parts.append(bevel_apply(pl, 0.004))
        if k < layers - 1:
            for x in (-0.55, 0.55):
                sk = box("sticker", (0.04, W + 0.02, st), M("WoodDark"), along='Y')
                place(sk, (x, 0, k * (pt + st) + pt + st / 2))
                parts.append(sk)
    return finish(merge(parts, name), 30.0)


def sawhorse(name, L=0.9, H=0.6):
    """Козлы: брус 9 × 9 см, четыре ноги с развалом 18°, две проножки, косынки под брусом. Origin — центр основания."""
    parts = []
    beam = box("beam", (L, 0.09, 0.09), M("WoodBench"), jitter=0.002)
    place(beam, (0, 0, H - 0.045))
    parts.append(bevel_apply(beam, 0.008))
    a = math.radians(18.0)
    lh = (H - 0.05) / math.cos(a)
    for x in (-0.33, 0.33):
        for sgn in (-1, 1):
            leg = box("leg", (0.045, 0.07, lh), M("WoodDark"), along='Z')
            place(leg, (x, sgn * 0.14, (H - 0.05) / 2), (sgn * a, 0, 0))
            parts.append(leg)
        gus = box("gusset", (0.10, 0.22, 0.05), M("WoodDark"), along='Y')
        place(gus, (x, 0, H - 0.09 - 0.025))
        parts.append(gus)
    for sgn in (-1, 1):
        br = box("brace", (0.70, 0.03, 0.08), M("WoodDark"))
        place(br, (0, sgn * 0.21, 0.20))
        parts.append(br)
    return finish(merge(parts, name), 30.0)


def shelf(name, W=2.0, D=0.6, t=0.05):
    """Полка на кронштейнах; origin — середина верхней плоскости у стены; полка уходит в −Y. Декор в глубине (y < −0.1)."""
    parts = []
    board = box("board", (W, D, t), M("WoodBench"), jitter=0.002)
    place(board, (0, -D / 2, -t / 2))
    parts.append(bevel_apply(board, 0.006))
    rail = box("rail", (W, 0.03, 0.10), M("WoodDark"))
    place(rail, (0, 0.015, -t - 0.05))
    parts.append(rail)
    for x in (-W / 2 + 0.18, W / 2 - 0.18):
        br = plate("bracket", [(0.0, -t), (-(D - 0.08), -t), (0.0, -(D - 0.08) - 0.06)], 0.04, M("WoodDark"))
        br.data.transform(Matrix.Rotation(math.pi / 2, 4, 'Z'))     # горизонтальная кромка косынки → −Y (от стены)
        place(br, (x, 0, 0))
        parts.append(br)
    jar = lathe("jar", [(0.0, 0.0), (0.075, 0.0), (0.10, 0.05), (0.105, 0.15), (0.075, 0.21), (0.05, 0.225), (0.055, 0.255), (0.0, 0.255)],
                segs=14, mat=M("Clay"))
    place(jar, (-0.72, -0.30, 0.0))
    parts.append(jar)
    jar2 = lathe("jar2", [(0.0, 0.0), (0.06, 0.0), (0.08, 0.04), (0.08, 0.12), (0.055, 0.16), (0.04, 0.17), (0.042, 0.19), (0.0, 0.19)],
                 segs=12, mat=M("Clay"))
    place(jar2, (-0.50, -0.24, 0.0))
    parts.append(jar2)
    can = cyl("can", 0.06, 0.15, 'Z', M("Iron"), segs=12)
    place(can, (-0.28, -0.30, 0.075))
    parts.append(can)
    bx = box("box", (0.28, 0.20, 0.14), M("WoodPale"), jitter=0.001, along='Z')
    place(bx, (0.08, -0.30, 0.07), (0, 0, math.radians(7)))
    parts.append(bevel_apply(bx, 0.004))
    for k, (dz, rot) in enumerate(((0.03, 0.0), (0.085, 0.35))):
        coil = C.add_torus("coil%d" % k, 0.10, 0.028, loc=(0, 0, 0), rot=(0, 0, rot), segs=16, ring=8)
        C.uv_box(coil, 4.0)
        C.assign(coil, M("Rope"))
        place(coil, (0.52, -0.30, dz))
        parts.append(coil)
    head = cyl("mallet_head", 0.05, 0.13, 'Y', M("WoodDark"), segs=10)
    place(head, (0.86, -0.22, 0.05))
    parts.append(head)
    handle = cyl("mallet_handle", 0.013, 0.30, 'X', M("Wood"), segs=8)
    place(handle, (0.70, -0.22, 0.05))
    parts.append(handle)
    return finish(merge(parts, name), 30.0)


def lamp(name, chain_len=3.6):
    """Подвесная лампа на цепи: origin — точка подвеса; звенья овальные (торы 8 × 4), абажур — тело вращения с внутренней
    поверхностью (материал EnamelIn по знаку нормали), лампочка эмиссионная."""
    parts = []
    ring = C.add_torus("hook", 0.035, 0.008, loc=(0, 0, 0), rot=(math.pi / 2, 0, 0), segs=10, ring=5)
    C.uv_box(ring, 1.0)
    C.assign(ring, M("IronDark"))
    place(ring, (0, 0, -0.03))
    parts.append(ring)
    pitch = 0.13
    n = int(round((chain_len - 0.12) / pitch))
    for k in range(n):
        link = C.add_torus("link%d" % k, 0.042, 0.009, loc=(0, 0, 0), rot=(0, 0, 0), segs=8, ring=4)
        link.data.transform(Matrix.Diagonal((1.0, 1.55, 1.0, 1.0)))
        link.data.transform(Matrix.Rotation(math.pi / 2, 4, 'X'))
        if k % 2:
            link.data.transform(Matrix.Rotation(math.pi / 2, 4, 'Z'))
        C.uv_box(link, 1.0)
        C.assign(link, M("IronDark"))
        place(link, (0, 0, -0.06 - pitch * (k + 0.5)))
        parts.append(link)
    ztop = -chain_len
    sock = cyl("socket", 0.03, 0.10, 'Z', M("IronDark"), segs=10)
    place(sock, (0, 0, ztop - 0.04))
    parts.append(sock)
    s0 = ztop - 0.08
    prof = [(0.0, s0), (0.045, s0), (0.06, s0 - 0.01), (0.14, s0 - 0.09), (0.26, s0 - 0.19), (0.32, s0 - 0.235), (0.325, s0 - 0.25),
            (0.305, s0 - 0.25), (0.30, s0 - 0.235), (0.245, s0 - 0.195), (0.13, s0 - 0.10), (0.052, s0 - 0.022), (0.0, s0 - 0.022)]
    shade = lathe("shade", prof, segs=20, mat=M("Enamel"))
    shade.data.materials.append(M("EnamelIn"))
    for poly in shade.data.polygons:
        c = poly.center
        rdir = Vector((c.x, c.y, 0.0))
        if rdir.length > 1e-6 and poly.normal.dot(rdir.normalized()) < -0.05:
            poly.material_index = 1
    parts.append(shade)
    bulb = sphere("bulb", 0.05, M("Bulb"), segs=10, rings=6)
    place(bulb, (0, 0, s0 - 0.19))
    parts.append(bulb)
    return finish(merge(parts, name), 30.0)


def wall_window_4m(name, width=4.0, height=5.0, ww=2.0, wh=3.6, sill=0.9):
    """Стеновой сегмент 4 × 5 с высоким проёмом 2.0 × 3.6 и рамой 3 × 6; дочерний Glass. Система координат Wall_Plank."""
    parts = []
    op = (-ww / 2, ww / 2, sill, sill + wh)
    _wall_core(parts, width, height, op)
    _wall_planks(parts, width, height, op)
    z0, z1 = op[2], op[3]
    for x in (-ww / 2 - 0.05, ww / 2 + 0.05):
        post = box("post", (0.10, PLANK_T + WALL_T, z1 - z0 + 0.2), M("WoodDark"), along='Z')
        place(post, (x, (PLANK_T + WALL_T) / 2 - 0.01, (z0 + z1) / 2))
        parts.append(bevel_apply(post, 0.008))
    lintel = box("lintel", (ww + 0.36, PLANK_T + WALL_T + 0.02, 0.14), M("WoodDark"))
    place(lintel, (0, (PLANK_T + WALL_T) / 2 - 0.02, z1 + 0.17))
    parts.append(bevel_apply(lintel, 0.01))
    sillb = box("sillbeam", (ww + 0.36, PLANK_T + WALL_T + 0.02, 0.10), M("WoodDark"))
    place(sillb, (0, (PLANK_T + WALL_T) / 2 - 0.02, z0 - 0.15))
    parts.append(bevel_apply(sillb, 0.01))
    fr, fd, yc = 0.07, 0.12, 0.10
    for x in (-ww / 2 + fr / 2, ww / 2 - fr / 2):
        j = box("jamb", (fr, fd, wh), M("WoodGrey"), along='Z')
        place(j, (x, yc, z0 + wh / 2))
        parts.append(j)
    for zz in (z1 - fr / 2, z0 + fr / 2):
        h = box("head", (ww - 2 * fr, fd, fr), M("WoodGrey"))
        place(h, (0, yc, zz))
        parts.append(h)
    isill = box("sill", (ww + 0.24, 0.24, 0.05), M("WoodGrey"))
    place(isill, (0, -0.06, z0 + 0.025))
    parts.append(bevel_apply(isill, 0.008))
    inner_h = wh - 2 * fr
    for x in (-ww / 6, ww / 6):
        m = box("mull_v", (0.036, 0.06, inner_h), M("WoodGrey"), along='Z')
        place(m, (x, yc, z0 + wh / 2))
        parts.append(m)
    for k in range(1, 6):
        m = box("mull_h", (ww - 2 * fr, 0.06, 0.036), M("WoodGrey"))
        place(m, (0, yc, z0 + fr + inner_h * k / 6))
        parts.append(m)
    wall = finish(merge(parts, name), 30.0)
    bpy.ops.mesh.primitive_plane_add(size=1.0, location=(0, 0, 0))
    g = bpy.context.active_object
    g.name = "Glass"
    g.data.transform(Matrix.Diagonal((ww - 2 * fr, wh - 2 * fr, 1.0, 1.0)))
    g.data.transform(Matrix.Rotation(math.pi / 2.0, 4, 'X'))     # нормаль → −Y (внутрь комнаты)
    g.data.materials.append(M("Glass"))
    place(g, (0, yc, z0 + wh / 2))
    C.set_origin(g, (0, 0, 0))
    C.parent(g, wall)
    return wall


def shavings_wide(name):
    """Широкая россыпь: декаль 2.4 × 1.6 (shavings_wide.png, генерируется здесь же) + 10 завитков + 8 щепок."""
    if not os.path.exists(SHAVINGS_WIDE_PNG):
        tex_shavings(SHAVINGS_WIDE_PNG, w=1024, h=683, n_curls=170, seed=11)
    parts = []
    for i in range(10):
        r = RNG.uniform(0.012, 0.030)
        o = curl("curl%d" % i, r, RNG.uniform(1.4, 3.0), RNG.uniform(0.012, 0.022), RNG.uniform(0.004, 0.010))
        rot = Matrix.Rotation(RNG.uniform(0, TAU), 4, 'Z') @ Matrix.Rotation(RNG.choice((0.0, 0.0, math.pi / 2, RNG.uniform(0.3, 1.2))), 4, 'X') @ Matrix.Rotation(RNG.uniform(0, TAU), 4, 'Z')
        o.data.transform(rot)
        zmin = min(v.co.z for v in o.data.vertices)
        ang = RNG.uniform(0, TAU)
        rad = abs(RNG.gauss(0.0, 0.45))
        place(o, (rad * math.cos(ang), rad * math.sin(ang) * 0.6, -zmin + 0.002))
        parts.append(o)
    for i in range(8):
        L, W = RNG.uniform(0.03, 0.08), RNG.uniform(0.008, 0.022)
        ch = plate("chip%d" % i, [(-L / 2, -W / 2), (L / 2 * 0.8, -W / 2 * 0.6), (L / 2, W / 2 * 0.3), (-L / 2 * 0.7, W / 2)], 0.003, M("Shaving"))
        ch.data.transform(Matrix.Rotation(math.pi / 2, 4, 'X'))
        ang = RNG.uniform(0, TAU)
        rad = abs(RNG.gauss(0.0, 0.5))
        place(ch, (rad * math.cos(ang), rad * math.sin(ang) * 0.6, 0.0025), (0, 0, RNG.uniform(0, TAU)))
        parts.append(ch)
    pile = finish(merge(parts, name), 40.0)
    dec = C.decal_plane("Shavings_Decal", SHAVINGS_WIDE_PNG, (2.4, 1.6), (0, 0, 0))
    dec.data.transform(Matrix.Rotation(-math.pi / 2.0, 4, 'X'))
    place(dec, (0, 0, 0.003))
    C.set_origin(dec, (0, 0, 0))
    C.parent(dec, pile)
    return pile


# ----------------------------------------------------------------------------------------------------------------------
# Задник за окнами (Pillow, системный python3): тёплое небо, солнечный ореол, дымка холмов, силуэты деревьев
# ----------------------------------------------------------------------------------------------------------------------
def backdrop_png(path=BACKDROP_PNG, w=768, h=1536, seed=4):
    from PIL import Image, ImageDraw, ImageFilter, ImageChops
    rng = random.Random(seed)
    img = Image.new("RGB", (w, h))
    draw = ImageDraw.Draw(img)
    stops = [(1.00, (150, 184, 220)), (0.72, (212, 222, 226)), (0.50, (252, 240, 210)), (0.34, (255, 244, 212)),
             (0.22, (252, 236, 196)), (0.00, (226, 206, 156))]
    for row in range(h):
        v = 1.0 - row / (h - 1)
        for (v1, c1), (v0, c0) in zip(stops, stops[1:]):
            if v0 <= v <= v1:
                t = (v - v0) / max(1e-6, v1 - v0)
                c = tuple(int(c0[i] + (c1[i] - c0[i]) * t) for i in range(3))
                break
        draw.line([(0, row), (w, row)], fill=c)
    # солнечный ореол слева вверху (за верхней частью окна) — аддитивно
    glow = Image.new("RGB", (w, h), (0, 0, 0))
    gd = ImageDraw.Draw(glow)
    cx, cy = int(w * 0.30), int(h * 0.42)
    for k in range(18, 0, -1):
        r = int(w * 0.07 * k)
        a = int(9 * (1.0 - k / 19.0) ** 0.8) + 2
        gd.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(a * 6, a * 5, a * 3))
    glow = glow.filter(ImageFilter.GaussianBlur(w * 0.03))
    img = ImageChops.add(img, glow)
    draw = ImageDraw.Draw(img)
    # дымка холмов
    for band, (vy, col) in enumerate(((0.36, (214, 210, 176)), (0.31, (186, 186, 140)))):
        pts = [(0, h)]
        x = 0
        while x <= w:
            y = int(h * (1.0 - vy) + math.sin(x / w * 6.3 + band * 2.0) * h * 0.012 + rng.uniform(-3, 3))
            pts.append((x, y))
            x += 24
        pts.append((w, h))
        draw.polygon(pts, fill=col)
    # деревья: дальние светлее, ближние темнее и крупнее
    trees = []
    for i in range(34):
        far = rng.random()
        x = rng.uniform(-0.05, 1.05) * w
        base_v = 0.06 + far * 0.24
        ht = (0.08 + (1.0 - far) * 0.16) * h
        trees.append((far, x, base_v, ht))
    trees.sort(key=lambda t_: -t_[0])
    for far, x, base_v, ht in trees:
        base_y = h * (1.0 - base_v)
        # освещённая контровым солнцем листва: дальние — светло-оливковые в дымке, ближние — темнее и насыщеннее
        shade = int(70 + far * 90)
        col = (shade + 30, shade + 36, int(shade * 0.55) + 10)
        trunk_w = max(3, int(ht * 0.045))
        draw.rectangle([x - trunk_w / 2, base_y - ht * 0.55, x + trunk_w / 2, base_y], fill=(shade - 10, shade - 14, int(shade * 0.5)))
        n = rng.randint(4, 7)
        for k in range(n):
            t = k / max(1, n - 1)
            ry = ht * (0.16 - 0.08 * t) * rng.uniform(0.85, 1.15)
            rx = ry * rng.uniform(1.3, 1.9)
            cy_ = base_y - ht * (0.30 + 0.62 * t)
            cx_ = x + rng.uniform(-1, 1) * ht * 0.12 * (1.0 - t)
            draw.ellipse([cx_ - rx, cy_ - ry, cx_ + rx, cy_ + ry], fill=col)
    # трава/земля внизу
    pts = [(0, h)]
    x = 0
    while x <= w:
        pts.append((x, int(h * 0.95 + rng.uniform(-6, 6))))
        x += 20
    pts.append((w, h))
    draw.polygon(pts, fill=(118, 124, 62))
    img = img.filter(ImageFilter.GaussianBlur(1.6))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, optimize=True)
    print("backdrop", path, img.size)


# ----------------------------------------------------------------------------------------------------------------------
# FX-текстуры (numpy → PNG через Blender): мошка, клуб пыли, атлас щепок 2×2, декаль стружки
# ----------------------------------------------------------------------------------------------------------------------
def _save(path, arr8):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    T.save_rgba8(path, arr8[::-1], alpha=True)
    print("fx texture", path, arr8.shape[1], "x", arr8.shape[0])


def _radial(size):
    yy, xx = np.mgrid[0:size, 0:size]
    x = (xx + 0.5) / size * 2.0 - 1.0
    y = (yy + 0.5) / size * 2.0 - 1.0
    return np.sqrt(x * x + y * y), x, y


def tex_mote(path, size=64):
    r, _, _ = _radial(size)
    a = np.clip(1.0 - r, 0.0, 1.0) ** 2.4
    out = np.zeros((size, size, 4), np.uint8)
    out[..., :3] = 255
    out[..., 3] = np.rint(a * 255).astype(np.uint8)
    _save(path, out)


def tex_puff(path, size=128):
    r, _, _ = _radial(size)
    n = T._vnoise(size, 3, 11, octaves=3)
    a = np.clip(1.0 - r * (0.8 + 0.45 * n), 0.0, 1.0) ** 1.7 * (0.65 + 0.35 * n)
    out = np.zeros((size, size, 4), np.uint8)
    out[..., 0] = 255
    out[..., 1] = 246
    out[..., 2] = 232
    out[..., 3] = np.rint(np.clip(a, 0, 1) * 255).astype(np.uint8)
    _save(path, out)


def tex_wood_chip(path, size=256):
    cell = size // 2
    out = np.zeros((size, size, 4), np.uint8)
    rng = np.random.default_rng(3)
    base = np.array([0.88, 0.70, 0.42])
    for k in range(4):
        cy, cx = divmod(k, 2)
        _, x, y = _radial(cell)
        npts = 10
        ang = np.linspace(0, TAU, npts, endpoint=False) + rng.uniform(0, 0.4)
        ex = 0.82 * (1.0 + rng.uniform(-0.12, 0.12, npts))
        ey = 0.36 * (1.0 + rng.uniform(-0.40, 0.40, npts))
        px = np.cos(ang) * ex
        py = np.sin(ang) * ey
        tip = int(np.argmax(np.cos(ang)))                     # острый расщеплённый конец
        px[tip] *= 1.12
        py[tip] *= 0.2
        mask = T._poly_mask(x, y, list(zip(px, py)))
        dist = np.zeros(mask.shape, np.float32)
        m = mask.copy()
        for _ in range(6):
            m = T._erode(m, 1)
            dist += m
        dist /= 6.0
        grain = 0.5 + 0.5 * np.sin((y * 5.0 + T._vnoise(cell, 3, k + 10, 2) * 1.6) * 3.2 + x * 1.5)
        noise = T._vnoise(cell, 6, k + 20, 3)
        t = np.clip(0.55 * grain + 0.45 * noise, 0, 1)
        rgb = base[None, None, :] * (0.72 + 0.40 * t)[..., None]
        rgb *= (0.62 + 0.38 * dist)[..., None]
        rgb = np.clip(rgb, 0, 1)
        a = T._blur3(mask.astype(np.float32))
        tile = np.zeros((cell, cell, 4), np.float32)
        tile[..., :3] = rgb
        tile[..., 3] = a
        out[cy * cell:(cy + 1) * cell, cx * cell:(cx + 1) * cell] = np.rint(tile * 255).astype(np.uint8)
    _save(path, out)


def _over(rgb, a, src_rgb, sa):
    """Композит «over» для straight alpha на срезах массивов (in place)."""
    out_a = sa + a * (1.0 - sa)
    num = src_rgb * sa[..., None] + rgb * (a * (1.0 - sa))[..., None]
    safe = np.where(out_a > 1e-6, out_a, 1.0)
    rgb[:] = np.where(out_a[..., None] > 1e-6, num / safe[..., None], rgb)
    a[:] = out_a


def tex_shavings(path, w=1024, h=768, n_curls=120, seed=5):
    rng = np.random.default_rng(seed)
    rgb = np.zeros((h, w, 3), np.float32)
    a = np.zeros((h, w), np.float32)
    yy, xx = np.mgrid[0:h, 0:w]
    cx, cy = w / 2.0, h / 2.0
    g = np.exp(-(((xx - cx) / (w * 0.30)) ** 2 + ((yy - cy) / (h * 0.30)) ** 2))
    big = max(w, h)
    speck = T._vnoise(big, 128, seed + 1, 2)[:h, :w]
    dust_a = np.clip((speck - 0.52) * 3.5, 0, 1) * g * 0.9
    dust_rgb = np.array([0.84, 0.68, 0.44])[None, None, :] * (0.8 + 0.35 * speck)[..., None]
    _over(rgb, a, dust_rgb, dust_a)
    dark = np.array([0.18, 0.12, 0.07])
    for i in range(n_curls):
        px = cx + rng.normal(0, w * 0.20)
        py = cy + rng.normal(0, h * 0.19)
        wdt = rng.uniform(2.2, 4.5)
        rot = rng.uniform(0, math.pi)
        if rng.uniform() < 0.35:                                # прямая волнистая стружка
            L = rng.uniform(14, 44)
            tt = np.linspace(0, 1, 22)
            ex = (tt - 0.5) * L
            ey = np.sin(tt * TAU * rng.uniform(0.5, 1.5) + rng.uniform(0, TAU)) * rng.uniform(1.5, 4.0)
        else:                                                   # раскручивающаяся спираль
            r0 = rng.uniform(4, 12)
            turns = rng.uniform(0.5, 1.9)
            phase = rng.uniform(0, TAU)
            tt = np.linspace(0, turns * TAU, int(turns * 26) + 2)
            rr = r0 * (1.0 + rng.uniform(0.35, 0.9) * tt / max(1e-6, turns * TAU))
            sq = rng.uniform(0.4, 1.0)
            ex = rr * np.cos(tt + phase)
            ey = rr * np.sin(tt + phase) * sq
        xs = px + ex * math.cos(rot) - ey * math.sin(rot)
        ys = py + ex * math.sin(rot) + ey * math.cos(rot)
        x0 = int(max(0, xs.min() - wdt - 4))
        x1 = int(min(w, xs.max() + wdt + 5))
        y0 = int(max(0, ys.min() - wdt - 4))
        y1 = int(min(h, ys.max() + wdt + 5))
        if x1 <= x0 + 2 or y1 <= y0 + 2:
            continue
        gx = xx[y0:y1, x0:x1].astype(np.float32)
        gy = yy[y0:y1, x0:x1].astype(np.float32)
        d = np.full(gx.shape, 1e9, np.float32)
        for j in range(len(xs) - 1):
            ax, ay, bx, by = xs[j], ys[j], xs[j + 1], ys[j + 1]
            vx, vy = bx - ax, by - ay
            L2 = vx * vx + vy * vy + 1e-9
            t = np.clip(((gx - ax) * vx + (gy - ay) * vy) / L2, 0, 1)
            dd = (gx - (ax + t * vx)) ** 2 + (gy - (ay + t * vy)) ** 2
            d = np.minimum(d, dd)
        d = np.sqrt(d)
        cov = np.clip(wdt / 2 + 0.5 - d, 0, 1)
        sh = np.roll(np.roll(cov, 2, 0), 2, 1) * 0.45
        shade = 0.72 + 0.38 * np.clip(1.0 - d / (wdt / 2), 0, 1)
        col = np.array([0.90, 0.74, 0.47]) * rng.uniform(0.82, 1.08)
        sub_rgb = rgb[y0:y1, x0:x1]
        sub_a = a[y0:y1, x0:x1]
        _over(sub_rgb, sub_a, np.broadcast_to(dark, sub_rgb.shape), sh)
        _over(sub_rgb, sub_a, np.clip(col[None, None, :] * shade[..., None], 0, 1), cov)
    out = np.zeros((h, w, 4), np.uint8)
    out[..., :3] = np.rint(np.clip(rgb, 0, 1) * 255).astype(np.uint8)
    out[..., 3] = np.rint(np.clip(a, 0, 1) * 255).astype(np.uint8)
    _save(path, out)


def tex_foliage(path, size=512, seed=9):
    """Кластеры листьев (эллипсы вдоль изогнутых веток) — RGBA, зелёные с вариацией, прозрачный фон."""
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:size, 0:size]
    a = np.zeros((size, size), np.float32)
    shade = np.zeros((size, size), np.float32)
    for b in range(9):
        x0, y0 = rng.uniform(0.15, 0.85) * size, rng.uniform(0.1, 0.95) * size
        ang = rng.uniform(0, TAU)
        curve = rng.uniform(-1.2, 1.2)
        L = rng.uniform(0.25, 0.5) * size
        for k in range(26):
            t = k / 25.0
            aa = ang + curve * t
            px = x0 + math.cos(aa) * L * t + rng.normal(0, 7)
            py = y0 + math.sin(aa) * L * t + rng.normal(0, 7)
            r1 = rng.uniform(9, 20) * (1.0 - 0.3 * t)
            r2 = r1 * rng.uniform(0.45, 0.7)
            la = rng.uniform(0, math.pi)
            dx, dy = xx - px, yy - py
            u = dx * math.cos(la) + dy * math.sin(la)
            v = -dx * math.sin(la) + dy * math.cos(la)
            leaf = np.clip(1.5 - ((u / r1) ** 2 + (v / r2) ** 2), 0, 1)
            m = leaf > 0.5
            a[m] = np.maximum(a[m], np.clip(leaf[m] * 2.0 - 1.0, 0, 1))
            shade[m] = rng.uniform(0.35, 1.0)
    a = T._blur3(a)
    n = T._vnoise(size, 8, seed + 3, 3)
    g = np.stack([0.18 + 0.30 * shade, 0.36 + 0.42 * shade, 0.10 + 0.12 * shade], -1) * (0.75 + 0.5 * n)[..., None]
    out = np.zeros((size, size, 4), np.uint8)
    out[..., :3] = np.rint(np.clip(g, 0, 1) * 255).astype(np.uint8)
    out[..., 3] = np.rint(np.clip(a, 0, 1) * 255).astype(np.uint8)
    _save(path, out)


def fx_textures(force=False):
    jobs = (("mote.png", tex_mote), ("puff.png", tex_puff), ("wood_chip.png", tex_wood_chip), ("shavings_decal.png", tex_shavings),
            ("foliage.png", tex_foliage))
    for fname, fn in jobs:
        p = os.path.join(FX_TEX, fname)
        if force or not os.path.exists(p):
            fn(p)


# ----------------------------------------------------------------------------------------------------------------------
# сборка
# ----------------------------------------------------------------------------------------------------------------------
MODULES = [
    ("Workbench", workbench),
    ("Tool_Board", tool_board),
    ("Window", window),
    ("Wall_Window", wall_window),
    ("Wall_Plank", wall_plank),
    ("Floor_Planks", floor_planks),
    ("Edge_Beam", edge_beam),
    ("Ceiling_Beams", ceiling_beams),
    ("Shavings", shavings),
    ("Lathe", lathe_machine),
    ("Turned_Post", turned_post),
    ("Foliage", foliage),
    ("Floor_Tile", floor_tile),
    ("Plank_Stack", plank_stack),
    ("Sawhorse", sawhorse),
    ("Shelf", shelf),
    ("Lamp", lamp),
    ("Wall_Window_4m", wall_window_4m),
    ("Shavings_Wide", shavings_wide),
    ("Foliage_Soft", lambda n: foliage(n, w=2.8, h=3.6, emission=0.12, mat_name="FoliageSoft")),
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
    if bpy is None:
        if "--backdrop" in sys.argv:
            backdrop_png()
            return
        print("нужен Blender (или --backdrop для задника через Pillow)")
        sys.exit(1)
    argv = C.args_after_dashdash()
    C.reset_scene()
    only = [a for a in argv if a != "textures"]
    fx_textures(force="textures" in argv)
    if "textures" in argv and not only:
        return
    os.makedirs(OUT, exist_ok=True)
    report = []
    for name, build in MODULES:
        if only and name not in only:
            continue
        root = build(name)
        root.name = name
        tris = tri_count(root)
        path = os.path.join(OUT, name + ".glb")
        export(path, [root])
        report.append((name, tris, os.path.getsize(path)))
        for c in list(root.children_recursive):
            bpy.data.objects.remove(c, do_unlink=True)
        bpy.data.objects.remove(root, do_unlink=True)
    bad = [r for r in report if r[1] > TRI_BUDGET]
    print("MODULE                 TRIS      BYTES")
    for name, tris, size in report:
        print("%-22s %6d %10d%s" % (name, tris, size, "  OVER BUDGET" if tris > TRI_BUDGET else ""))
    if bad:
        print("ERROR: over budget:", [b[0] for b in bad])
        sys.exit(1)


main()
