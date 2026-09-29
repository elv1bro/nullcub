#!/usr/bin/env python3
"""Детали крафта (docs/plan-demo/BODY_CRAFT.md §1, §4; замысел — CONCEPT_V2.md §6–10): оружейные детали (рукояти, головки,
лезвия, моды, цепь, крюк) и тяжёлые детали тела (железное предплечье, шар-кулак, доп. сустав, голова-ведро, щит). Стиль —
деревянная кукла v3 (клён, тёмные стальные шары суставов, штифты) + ржавое железо Свалки (rust_metal, rust_painted_red,
brass_worn, iron, rope из assets/textures/pbr; металличность — из карты набора, metallic= не передаём).

Запуск (Blender 4.5 LTS, headless):
    /Applications/Blender.app/Contents/MacOS/Blender -b --python godot/tools/blender/craft_parts.py [-- Имя …]
        → godot/assets/models/body/parts/<Name>.glb (печатает таблицу треугольников, падает при > 3000)
    … -- --render <layout.json>   контактные рендеры (Cycles) из уже экспортированных glb → $CRAFT_RENDER_TMP
                                   (по умолчанию <tmp>/craft_parts_render): ряд оружейных деталей, ряд деталей тела (и они же
                                   на силуэте куклы), ряд собранных пресетов (раскладка и числа — из tests/craft_probe.gd layout=…)
    python3 godot/tools/blender/craft_parts.py --sheet
                                 → docs/plan-demo/img/craft-parts-v1.png (три ряда + подписи; системный python3 + Pillow)
Переменные окружения: CRAFT_TEX_SIZE (512) — размер текстур внутри glb (детали мелкие), CRAFT_IMG (WEBP),
CRAFT_FLAT=1 — плоские материалы (быстрый прогон), CRAFT_RENDER_SAMPLES (48).

Соглашения (BODY_CRAFT.md §1). Геометрия описывается в координатах Godot (x вбок, y вверх, z к камере) и переводится в
Blender функцией G2B (x, y, z) → (x, −z, y); после экспорта с Y вверх в Godot получается ровно то, что написано здесь.
    • origin детали = её Socket (точка крепления к родителю, проксимальный сустав); деталь «растёт» от Socket в −Y
      (рукоять — от хвата к головке, предплечье — от локтя к запястью). Исключение — Metal_Head: растёт вверх, у её
      Socket базис повёрнут на 180° вокруг Z (−Y смотрит вверх, как у головы куклы).
    • пустышки glb (станут Marker3D в tools/build_craft_parts.gd):
        Socket               — точка и базис крепления к родителю;
        Anchor_<имя>         — куда крепятся дети: позиция = точка сустава, −Y = куда вырастет ребёнок;
        Shape_<Тип>_<имя>    — коллизия: Box (масштаб = половины размеров), Sphere (масштаб.x = радиус),
                               Cyl / Capsule (масштаб = (r, h/2, r), ось — локальная Y; у капсулы h — полная высота).
      Коллизии идут через z = 0 с глубиной ≥ 0.06 м (всё в плоскости боя XY); метаданные якорей (accepts, joint_group,
      rest_deg, mirror) — в таблице PARTS билдера.
    • бюджет ≤ 3000 треугольников на деталь; фаски (Bevel) применяются до экспорта, счёт точный.
    • головки/лезвия/крюк: Socket в центре проушины (рукоять входит на 3.5 см глубже якоря — торец спрятан в проушине);
      Face_L / Face_R — торцы бойка (L = +X, R = −X, как стороны куклы); на рукояти головка встаёт так, что −X детали
      смотрит в −Y оружия — это передний боёк при махе по часовой стрелке (tests/craft_probe.gd).
    • у всего, что можно повесить на цепь (шар булавы, крюк), над Socket есть стальная проушина: на рукояти её прячет торец
      древка, на цепи в неё продето последнее звено.

Детали (Ш × В × Г по габариту, масса — в PartDef, см. tools/build_craft_parts.gd):
  Handle_Short     рукоять 0.55: клён, стальной шар-навершие, ржавые обоймы у торца и под головкой, верёвочная обмотка хвата
  Handle_Long      рукоять 1.10: то же + вторая обмотка посередине
  Head_Mallet      деревянная киянка ⌀0.17 × 0.30 (орех) с двумя ржавыми обручами и клином
  Head_Hammer      железная головка 0.30 × 0.12 (восьмигранник с перехватом, выпуклые бойки), болты, клин
  Head_Mace_Ball   шар ⌀0.19 с 12 шипами, сварной шов, втулка и проушина
  Blade_Sword      клинок 0.75 (сталь, ромбическое сечение), гарда из гнутого прутка, втулка с заклёпками
  Blade_Axe        бородатая голова топора 0.39 × 0.34 со спуском к кромке, ржавая проушина-обух (Anchor_Back — мод на обух)
  Hook             крюк 0.38: втулка, стержень, загиб с остриём
  Mod_Nails        шайба ⌀0.16 с кольцом из 6 гвоздей-шипов (торчат на 8 см, разведены на 14°), сварные наплывы
  Mod_Iron_Plate   накладка 0.17 × 0.17 × 0.04 на боёк, 4 болта, сварной шов; Anchor_Out — сверху можно гвозди
  Chain_Segment    сегмент цепи 0.35: штифт + серьга на Socket, 3 звена (через одно — ребром к камере), Anchor_End
  Metal_Forearm    железное предплечье 0.27 (локоть → запястье): стальной шар локтя, клёпаные бандажи, шов, чашка запястья
  Iron_Ball_Fist   шар-кулак ⌀0.16 на шее со стальным шаром запястья, два сварных шва, болты
  Extra_Joint      доп. сустав 0.13: стальной шар, кленовая вставка с чашкой и штифтом, верёвочная обмотка
  Metal_Head       голова-ведро ⌀0.28 × 0.32: закатанный край, два гофра, прорезь с деревянной FacePlate (материал Face, UV 0..1 —
                   под фото лица), вмятины, ушки и дужка, стальной шар шеи
  Shield_Plate     щиток 0.24 × 0.36 на предплечье (крашеный ржавый лист, выгнут, окантовка, заклёпки, умбон, ремни)
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
    from mathutils import Matrix, Vector
except ImportError:  # системный python3: только --sheet (Pillow)
    bpy = None

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
if bpy is not None:
    import common as C  # noqa: E402

GODOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(GODOT, "assets", "models", "body", "parts")
PBR_DIR = os.path.join(GODOT, "assets", "textures", "pbr")
SHEET_PNG = os.path.abspath(os.path.join(GODOT, "..", "docs", "plan-demo", "img", "craft-parts-v1.png"))
RENDER_TMP = os.environ.get("CRAFT_RENDER_TMP") or os.path.join(tempfile.gettempdir(), "craft_parts_render")
TRI_BUDGET = 3000
TEX_SIZE = int(os.environ.get("CRAFT_TEX_SIZE", "512"))
IMG_FORMAT = os.environ.get("CRAFT_IMG", "WEBP")
CACHE = os.path.join(tempfile.gettempdir(), "ragdoll_craft_parts_pbr")
FORCE_FLAT = os.environ.get("CRAFT_FLAT", "0") == "1"
TAU = 2.0 * math.pi
RNG = random.Random(4207)

WEAPON_PARTS = ["Handle_Short", "Handle_Long", "Head_Mallet", "Head_Hammer", "Head_Mace_Ball", "Blade_Sword", "Blade_Axe",
                "Hook", "Mod_Nails", "Mod_Iron_Plate", "Chain_Segment"]
BODY_PARTS = ["Metal_Forearm", "Iron_Ball_Fist", "Extra_Joint", "Metal_Head", "Shield_Plate"]

if bpy is not None:
    G2B = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))   # Godot (x, y, z) → Blender (x, −z, y)
    B2G = G2B.inverted()


# ----------------------------------------------------------------------------------------------------------------------
# матрицы в координатах Godot
# ----------------------------------------------------------------------------------------------------------------------
def T(p):
    return Matrix.Translation(Vector(p))


def Rz(deg):
    return Matrix.Rotation(math.radians(deg), 4, 'Z')


def Rx(deg):
    return Matrix.Rotation(math.radians(deg), 4, 'X')


def S(s):
    return Matrix.Diagonal((s[0], s[1], s[2], 1.0))


def align_y(direction, origin=(0.0, 0.0, 0.0)):
    """Матрица, переводящая локальную ось +Y в direction, с началом в origin."""
    d = Vector(direction).normalized()
    m = Vector((0.0, 1.0, 0.0)).rotation_difference(d).to_matrix().to_4x4()
    m.translation = Vector(origin)
    return m


# ----------------------------------------------------------------------------------------------------------------------
# материалы: имя → (папка PBR, kwargs textured_material, плоский запасной (цвет, шероховатость), тайлов на метр)
# ----------------------------------------------------------------------------------------------------------------------
MAT_DEFS = {
    "Wood": ("maple_light", {"tint": (1.0, 0.97, 0.92, 1.0)}, ((0.52, 0.36, 0.20, 1.0), 0.62), 2.0),      # клён куклы v3
    "WoodDark": ("walnut_dark", {"tint": (1.0, 0.98, 0.96, 1.0)}, ((0.20, 0.11, 0.06, 1.0), 0.66), 2.0),  # орех: киянка
    "Face": ("maple_light", {"tint": (1.0, 0.97, 0.92, 1.0)}, ((0.52, 0.36, 0.20, 1.0), 0.62), 2.0),      # под фото лица
    "Rust": ("rust_metal", {}, ((0.20, 0.11, 0.06, 1.0), 0.78), 1.5),                                   # ржавое железо Свалки
    "RustDark": ("rust_metal", {"tint": (0.55, 0.50, 0.48, 1.0)}, ((0.08, 0.06, 0.05, 1.0), 0.72), 1.5),  # звенья, швы, бандажи
    "RustRed": ("rust_painted_red", {}, ((0.30, 0.05, 0.03, 1.0), 0.62), 1.5),                         # крашеный лист щита
    "Steel": ("iron", {}, ((0.12, 0.12, 0.12, 1.0), 0.45), 2.0),                                       # клинок, гвозди, штифты
    "Brass": ("brass_worn", {}, ((0.50, 0.36, 0.14, 1.0), 0.38), 2.0),                                 # заклёпки ведра
    "Rope": ("rope", {}, ((0.36, 0.25, 0.13, 1.0), 0.9), 8.0),                                         # обмотки хвата, ремни
}
# стальные шары и штифты суставов — как у куклы v3 (wooden_doll_v3.make_materials)
FLAT = {"Joint": ((0.11, 0.105, 0.11, 1.0), 0.42, 0.85), "Pin": ((0.62, 0.62, 0.64, 1.0), 0.30, 1.0)}
_MATS = {}
MAT_STATUS = {}


def pbr_ready(folder):
    d = os.path.join(PBR_DIR, folder)
    return all(os.path.exists(os.path.join(d, f)) for f in ("albedo.png", "roughness.png", "normal.png"))


def pbr_folder(name):
    """Уменьшенная копия набора PBR в кэше (TEX_SIZE): детали мелкие, 2048² на каждую — лишние мегабайты в glb."""
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
    """Материал по имени (лениво): PBR-набор (плоский, если набора нет или CRAFT_FLAT=1)."""
    if name in _MATS:
        return _MATS[name]
    if name in FLAT:
        base, rough, metal = FLAT[name]
        m = C.material(name, base, rough, metal)
        MAT_STATUS[name] = "flat"
    else:
        folder, kw, flat, _uv = MAT_DEFS[name]
        if pbr_ready(folder) and not FORCE_FLAT:
            m = C.textured_material(name, pbr_folder(folder), **kw)
            MAT_STATUS[name] = "pbr " + folder
        else:
            m = C.material(name, flat[0], flat[1], 0.0)
            MAT_STATUS[name] = "FLAT"
    m.use_backface_culling = True
    _MATS[name] = m
    return m


def uv_scale_of(mat):
    return MAT_DEFS[mat][3] if mat in MAT_DEFS else 2.0


# ----------------------------------------------------------------------------------------------------------------------
# примитивы: строятся в координатах Godot, в меш уходят через G2B
# ----------------------------------------------------------------------------------------------------------------------
def _obj(name, bm, mat, xf=None):
    if xf is not None:
        bmesh.ops.transform(bm, matrix=xf, verts=bm.verts)
    bmesh.ops.transform(bm, matrix=G2B, verts=bm.verts)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    me.materials.append(M(mat))
    o["mat"] = mat
    return o


def revolve(name, prof, mat, segs=20, xf=None, closed=False, phase=0.0):
    """Тело вращения вокруг локальной оси Y: prof [(r, y), …]; r = 0 — полюс, иначе торец закрывается n-гоном.
    closed=True — профиль замкнут (кольцо, шайба), торцов нет."""
    bm = bmesh.new()
    rings = []
    for r, y in prof:
        if r < 1e-6:
            rings.append([bm.verts.new((0.0, y, 0.0))])
        else:
            rings.append([bm.verts.new((r * math.cos(TAU * i / segs + phase), y, r * math.sin(TAU * i / segs + phase)))
                          for i in range(segs)])
    pairs = list(zip(rings, rings[1:]))
    if closed:
        pairs.append((rings[-1], rings[0]))
    for a, b in pairs:
        if len(a) == 1 and len(b) == 1:
            continue
        for i in range(segs):
            j = (i + 1) % segs
            if len(a) == 1:
                bm.faces.new((a[0], b[j], b[i]))
            elif len(b) == 1:
                bm.faces.new((a[i], a[j], b[0]))
            else:
                bm.faces.new((a[i], a[j], b[j], b[i]))
    if not closed:
        if len(rings[0]) > 1:
            bm.faces.new(list(reversed(rings[0])))
        if len(rings[-1]) > 1:
            bm.faces.new(rings[-1])
    return _obj(name, bm, mat, xf)


def sphere(name, r, center, mat, segs=16, rings=8):
    prof = [(0.0, -r)] + [(r * math.sin(math.pi * k / rings), -r * math.cos(math.pi * k / rings)) for k in range(1, rings)] + [(0.0, r)]
    return revolve(name, prof, mat, segs, T(center))


def box(name, size, mat, center=(0.0, 0.0, 0.0), xf=None, jitter=0.0):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    if jitter > 0.0:
        for v in bm.verts:
            v.co += Vector((RNG.uniform(-jitter, jitter), RNG.uniform(-jitter, jitter), RNG.uniform(-jitter, jitter)))
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    return _obj(name, bm, mat, xf)


def loft(name, rings, mat, caps=True, xf=None, pole0=None, pole1=None):
    """Лофт колец одинаковой длины (точки Godot); caps — n-гоны на концах, pole0/pole1 — вершина-полюс вместо n-гона."""
    bm = bmesh.new()
    vr = [[bm.verts.new(Vector(p)) for p in r] for r in rings]
    n = len(rings[0])
    for a, b in zip(vr, vr[1:]):
        for i in range(n):
            bm.faces.new((a[i], a[(i + 1) % n], b[(i + 1) % n], b[i]))
    if pole0 is not None:
        c = bm.verts.new(Vector(pole0))
        for i in range(n):
            bm.faces.new((vr[0][(i + 1) % n], vr[0][i], c))
    elif caps:
        bm.faces.new(list(reversed(vr[0])))
    if pole1 is not None:
        c = bm.verts.new(Vector(pole1))
        for i in range(n):
            bm.faces.new((vr[-1][i], vr[-1][(i + 1) % n], c))
    elif caps:
        bm.faces.new(vr[-1])
    return _obj(name, bm, mat, xf)


def sweep(name, pts, radii, mat, sides=8, closed=False, caps=True, phase=0.0):
    """Труба по ломаной (параллельный перенос рамок): звенья, прутья, гвозди (sides=4 — квадратный стержень), обмотки.
    radii — число или список по точкам (сужение к острию)."""
    pts = [Vector(p) for p in pts]
    n = len(pts)
    if not isinstance(radii, (list, tuple)):
        radii = [radii] * n
    tang = []
    for i in range(n):
        if closed:
            t = pts[(i + 1) % n] - pts[i - 1]
        else:
            t = pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]
        tang.append(t.normalized())
    nrm = tang[0].orthogonal().normalized()
    frames = []
    for i in range(n):
        if i > 0:
            ax = tang[i - 1].cross(tang[i])
            if ax.length > 1e-9:
                nrm = (Matrix.Rotation(tang[i - 1].angle(tang[i]), 3, ax.normalized()) @ nrm).normalized()
        frames.append((nrm.copy(), tang[i].cross(nrm).normalized()))
    bm = bmesh.new()
    rings = []
    for i in range(n):
        a, b = frames[i]
        rings.append([bm.verts.new(pts[i] + (a * math.cos(TAU * k / sides + phase) + b * math.sin(TAU * k / sides + phase)) * radii[i])
                      for k in range(sides)])
    for i in (range(n) if closed else range(n - 1)):
        i2 = (i + 1) % n
        for k in range(sides):
            k2 = (k + 1) % sides
            bm.faces.new((rings[i][k], rings[i][k2], rings[i2][k2], rings[i2][k]))
    if caps and not closed:
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
    return _obj(name, bm, mat)


def circle(center, radius, plane='XY', n=16, phase=0.0):
    c = Vector(center)
    out = []
    for i in range(n):
        a = phase + TAU * i / n
        u, v = radius * math.cos(a), radius * math.sin(a)
        if plane == 'XY':
            out.append(c + Vector((u, v, 0.0)))
        elif plane == 'XZ':
            out.append(c + Vector((u, 0.0, v)))
        else:
            out.append(c + Vector((0.0, u, v)))
    return out


def torus(name, center, radius, minor, mat, plane='XY', segs=16, sides=6):
    return sweep(name, circle(center, radius, plane, segs), minor, mat, sides=sides, closed=True)


def stadium(center, half_len, half_w, plane='XY', n=16):
    """Осевая линия звена цепи: два полукруга (вдоль Y) + прямые, в плоскости XY или YZ."""
    c = Vector(center)
    k = half_len - half_w
    pts = []
    half = n // 2
    for s, yc in ((1, k), (-1, -k)):
        for i in range(half):
            a = math.pi * i / (half - 1)
            u = half_w * math.cos(a) * s
            v = yc + half_w * math.sin(a) * s
            pts.append(c + (Vector((u, v, 0.0)) if plane == 'XY' else Vector((0.0, v, u))))
    return pts


def earclip(pts):
    """Триангуляция простого 2D-многоугольника (как weapons.earclip): надёжные крышки вогнутых контуров."""
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


def extrude2d(name, pts, z0, z1, mat, bend=0.0, xf=None):
    """Плоская деталь: контур [(x, y)] в плоскости XY (Godot), толщина по Z от z0 до z1 (лицо в +Z, к камере).
    bend — изгиб листа: z −= bend·x² (щиток, обнимающий руку)."""
    bm = bmesh.new()
    front = [bm.verts.new((x, y, z1 - bend * x * x)) for x, y in pts]
    back = [bm.verts.new((x, y, z0 - bend * x * x)) for x, y in pts]
    for (i, j, k) in earclip(pts):
        bm.faces.new((front[i], front[j], front[k]))
        bm.faces.new((back[k], back[j], back[i]))
    n = len(pts)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((front[j], front[i], back[i], back[j]))
    return _obj(name, bm, mat, xf)


def stud(name, loc, normal, mat="Rust", r=0.008, h=0.005, sides=8):
    """Заклёпка/шляпка болта: низкий купол на поверхности (sides=6 — шестигранный болт)."""
    return revolve(name, [(r, -0.002), (r, 0.0), (r * 0.75, h * 0.7), (0.0, h)], mat, sides, align_y(normal, loc))


def spike(name, base, direction, length, r0, mat, sides=8):
    return revolve(name, [(r0, -0.004), (r0 * 0.92, length * 0.12), (r0 * 0.18, length * 0.95), (0.0, length)], mat, sides,
                   align_y(direction, base))


# ----------------------------------------------------------------------------------------------------------------------
# отделка: фаска → сглаживание → развёртка в метрах
# ----------------------------------------------------------------------------------------------------------------------
def select_only(o):
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o


def bevel_apply(o, width, segments=1, angle=35.0):
    m = o.modifiers.new("Bevel", 'BEVEL')
    m.width = width
    m.segments = segments
    m.limit_method = 'ANGLE'
    m.angle_limit = math.radians(angle)
    m.use_clamp_overlap = True
    select_only(o)
    bpy.ops.object.modifier_apply(modifier=m.name)


def cut_sphere(o, center_g, r, segs=20):
    """Булева чашка сустава (как wooden_doll_v3.cut_sphere): сфера r вычитается из o, центр — в координатах Godot."""
    cutter = sphere("_cut", r, center_g, o["mat"], segs, segs // 2)
    m = o.modifiers.new("Cup", 'BOOLEAN')
    m.operation = 'DIFFERENCE'
    m.solver = 'EXACT'
    m.object = cutter
    select_only(o)
    bpy.ops.object.modifier_apply(modifier=m.name)
    bpy.data.objects.remove(cutter, do_unlink=True)


def cut_box(o, center_g, size_g):
    cutter = box("_cutbox", size_g, o["mat"], center_g)
    m = o.modifiers.new("Cut", 'BOOLEAN')
    m.operation = 'DIFFERENCE'
    m.solver = 'EXACT'
    m.object = cutter
    select_only(o)
    bpy.ops.object.modifier_apply(modifier=m.name)
    bpy.data.objects.remove(cutter, do_unlink=True)


def fin(o, bevel=0.0, segs=1, angle=40.0, uv="box", axis='Y', bevel_angle=35.0):
    """Фаска (применяется) → гладкость по углу → UV в метрах (box / cyl вдоль оси детали; axis — ось Godot)."""
    if bevel > 0.0:
        bevel_apply(o, bevel, segs, bevel_angle)
    for p in o.data.polygons:
        p.use_smooth = True
    select_only(o)
    try:
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(angle), keep_sharp_edges=True)
    except Exception:
        pass
    b_axis = {'X': 'X', 'Y': 'Z', 'Z': 'Y'}[axis]   # ось Godot → ось Blender
    sc = uv_scale_of(o["mat"])
    if uv == "cyl":
        C.uv_cylinder_along(o, b_axis, sc)
    else:
        C.uv_box(o, sc, along=b_axis)
    # случайный сдвиг развёртки: одинаковые детали не повторяют один и тот же кусок текстуры
    du, dv = RNG.uniform(0.0, 1.0), RNG.uniform(0.0, 1.0)
    for d in o.data.uv_layers[0].data:
        d.uv = (d.uv[0] + du, d.uv[1] + dv)
    return o


def empty(name, xf_g, display='ARROWS', size=0.04):
    e = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(e)
    e.empty_display_type = display
    e.empty_display_size = size
    e.matrix_world = G2B @ xf_g @ B2G
    return e


def socket(pos=(0.0, 0.0, 0.0), rot_z=0.0):
    return empty("Socket", T(pos) @ Rz(rot_z))


def anchor(name, pos, rot_z=0.0):
    return empty("Anchor_" + name, T(pos) @ Rz(rot_z))


def shape_box(name, center, size, rot_z=0.0):
    return empty("Shape_Box_" + name, T(center) @ Rz(rot_z) @ S((size[0] / 2, size[1] / 2, size[2] / 2)), 'CUBE', 1.0)


def shape_sphere(name, center, r):
    return empty("Shape_Sphere_" + name, T(center) @ S((r, r, r)), 'SPHERE', 1.0)


def shape_cyl(name, center, r, h, rot_z=0.0):
    return empty("Shape_Cyl_" + name, T(center) @ Rz(rot_z) @ S((r, h / 2, r)), 'CUBE', 1.0)


def shape_capsule(name, center, r, h, rot_z=0.0):
    return empty("Shape_Capsule_" + name, T(center) @ Rz(rot_z) @ S((r, h / 2, r)), 'CUBE', 1.0)


# ----------------------------------------------------------------------------------------------------------------------
# общие узлы
# ----------------------------------------------------------------------------------------------------------------------
def collar_with_eye(prefix, y_top, y_bot, r):
    """Втулка под торец рукояти (Rust) + стальная проушина над Socket для цепи (на рукояти её прячет древко)."""
    body = revolve(prefix + "_Collar", [(0.0, y_top), (r - 0.005, y_top), (r, y_top - 0.006), (r, y_bot + 0.012),
                                        (r + 0.006, y_bot + 0.006), (r + 0.006, y_bot), (r - 0.006, y_bot - 0.008), (0.0, y_bot - 0.008)],
                   "Rust", 16)
    eye = torus(prefix + "_Eye", (0.0, 0.004, 0.0), 0.016, 0.0055, "Steel", 'XY', 12, 6)
    return [fin(body, 0.003, 1, uv="cyl"), fin(eye, angle=80)]


def wrap_rings(prefix, y0, y1, count, radius, minor=0.0065, tilt=12.0):
    """Верёвочная обмотка хвата: наклонённые кольца (чередуя наклон — читается как намотка), как wrap_bands куклы v3."""
    out = []
    for i in range(count):
        y = y0 + (y1 - y0) * i / max(count - 1, 1)
        ring = [Vector(p) for p in circle((0.0, 0.0, 0.0), radius, 'XZ', 12, phase=0.3 * i)]
        m = T((0.0, y, 0.0)) @ Rx(tilt if i % 2 else -tilt)
        ring = [m @ p for p in ring]
        out.append(fin(sweep("%s_%d" % (prefix, i), ring, minor, "Rope", sides=5, closed=True), angle=80, uv="cyl"))
    return out


def ball_joint(name, r, center=(0.0, 0.0, 0.0), segs=20):
    """Тёмный стальной шар сустава, как у куклы v3 (принадлежит дистальной детали и стоит в её Socket)."""
    return fin(sphere(name, r, center, "Joint", segs, segs // 2), angle=80)


# ----------------------------------------------------------------------------------------------------------------------
# оружейные детали
# ----------------------------------------------------------------------------------------------------------------------
def handle(name, butt, tip, anchor_y, r, wraps):
    """Рукоять: хват (Socket) в нуле, древко вниз до tip; Anchor_Head на anchor_y (торец уходит на 3.5 см в проушину головки),
    Anchor_Butt — навершие (дети растут назад, +Y)."""
    objs = []
    shaft = [(0.0, butt), (r * 0.9, butt), (r, butt - 0.03), (r * 0.97, 0.0), (r * 1.02, tip * 0.5), (r * 1.1, tip + 0.12),
             (r * 1.1, tip + 0.03), (r * 0.9, tip + 0.004), (0.0, tip)]
    objs.append(fin(revolve(name + "_Shaft", shaft, "Wood", 16), uv="cyl"))
    objs.append(fin(revolve(name + "_ButtCap", [(0.0, butt + 0.006), (r + 0.002, butt + 0.006), (r + 0.006, butt), (r + 0.006, butt - 0.034),
                                                (r + 0.002, butt - 0.04), (0.0, butt - 0.04)], "Rust", 16), 0.003, 1, uv="cyl"))
    objs.append(ball_joint(name + "_Pommel", 0.021, (0.0, butt + 0.02, 0.0)))
    ft, fb = anchor_y + 0.13, anchor_y + 0.09
    objs.append(fin(revolve(name + "_Ferrule", [(0.0, ft), (r * 1.1 + 0.004, ft), (r * 1.1 + 0.006, ft - 0.005), (r * 1.1 + 0.006, fb + 0.005),
                                                (r * 1.1 + 0.004, fb), (0.0, fb)], "Rust", 16), 0.002, 1, uv="cyl"))
    for sx in (-1, 1):
        objs.append(fin(stud(name + "_FerRivet", (sx * 0.012, (ft + fb) / 2, r * 1.1 + 0.006), (0, 0, 1), "RustDark", 0.005, 0.003, 6)))
    objs.append(fin(revolve(name + "_TipCap", [(0.0, anchor_y + 0.02), (r * 1.1 + 0.003, anchor_y + 0.02), (r * 1.1 + 0.003, tip + 0.006),
                                               (r * 0.8, tip - 0.002), (0.0, tip - 0.002)], "Rust", 16), 0.002, 1, uv="cyl"))
    for (y0, y1, n) in wraps:
        objs += wrap_rings(name + "_Wrap%d" % int(y0 * 100), y0, y1, n, r + 0.006)
    empties = [socket(), anchor("Head", (0.0, anchor_y, 0.0)), anchor("Butt", (0.0, butt + 0.04, 0.0), 180.0),
               shape_box("Shaft", (0.0, (butt + 0.04 + tip) / 2, 0.0), (2 * r + 0.014, butt + 0.04 - tip, 0.066))]
    return objs, empties


def build_Handle_Short():
    return handle("Handle_Short", 0.075, -0.475, -0.44, 0.026, [(0.035, -0.165, 8)])


def build_Handle_Long():
    return handle("Handle_Long", 0.10, -1.0, -0.965, 0.028, [(0.06, -0.16, 8), (-0.42, -0.54, 5)])


def face_anchors(half):
    """Бойки: L = +X, R = −X (зеркальная сторона), −Y якоря смотрит наружу из торца."""
    return [anchor("Face_L", (half, 0.0, 0.0), 90.0), anchor("Face_R", (-half, 0.0, 0.0), -90.0)]


def build_Head_Mallet():
    """Деревянная киянка: бочонок из ореха вдоль X с выпуклыми торцами, два ржавых обруча с заклёпками, стальной клин."""
    h = 0.15
    prof = [(0.0, -h - 0.004), (0.05, -h - 0.002), (0.072, -h + 0.004), (0.081, -h + 0.018), (0.084, -0.06), (0.086, 0.0),
            (0.084, 0.06), (0.081, h - 0.018), (0.072, h - 0.004), (0.05, h + 0.002), (0.0, h + 0.004)]
    objs = [fin(revolve("Mallet_Barrel", prof, "WoodDark", 24, Rz(-90.0)), uv="cyl", axis='X')]
    for s in (-1, 1):
        t = s * 0.112
        hoop = revolve("Mallet_Hoop", [(0.083, t - 0.012), (0.090, t - 0.010), (0.090, t + 0.010), (0.083, t + 0.012)], "Rust", 24, Rz(-90.0), closed=True)
        objs.append(fin(hoop, 0.0015, 1, uv="cyl", axis='X'))
        for k in range(4):
            a = TAU * k / 4 + math.pi / 4
            n = Vector((0.0, math.cos(a), math.sin(a)))
            objs.append(fin(stud("Mallet_HoopRivet", Vector((t, 0.0, 0.0)) + n * 0.09, n, "RustDark", 0.006, 0.004, 6)))
    objs.append(fin(box("Mallet_Wedge", (0.012, 0.01, 0.05), "Steel", (0.0, -0.083, 0.0)), 0.002, 1))
    empties = [socket()] + face_anchors(h) + [shape_cyl("Barrel", (0.0, 0.0, 0.0), 0.086, 2 * h, -90.0)]
    return objs, empties


def octagon(h, x, dome=0.0):
    k = h * 0.55
    pts = [(h, -k), (h, k), (k, h), (-k, h), (-h, k), (-h, -k), (-k, -h), (k, -h)]
    return [(x, y, z) for (y, z) in pts]


def build_Head_Hammer():
    """Железная головка: восьмигранник вдоль X с перехватом у проушины и расплющенными бойками, выпуклые торцы,
    болты на щеках, стальной клин сверху (со стороны, противоположной хвату)."""
    h = 0.15
    stations = [(-h, 0.057), (-0.142, 0.062), (-0.128, 0.064), (-0.108, 0.059), (-0.07, 0.052), (-0.032, 0.058), (0.032, 0.058),
                (0.07, 0.052), (0.108, 0.059), (0.128, 0.064), (0.142, 0.062), (h, 0.057)]
    rings = [octagon(hh, x) for x, hh in stations]
    body = loft("Hammer_Head", rings, "Rust", pole0=(-h - 0.006, 0.0, 0.0), pole1=(h + 0.006, 0.0, 0.0))
    objs = [fin(body, 0.004, 2, angle=35.0, uv="box", axis='X')]
    for sx in (-1, 1):   # отполированные ударами бойки — светлая сталь на торцах, читается, где у головки «лицо»
        face = loft("Hammer_Face", [octagon(0.0535, sx * 0.146), octagon(0.0525, sx * (h + 0.004))], "Steel", caps=False,
                    pole1=(sx * (h + 0.009), 0.0, 0.0))
        objs.append(fin(face, 0.0015, 1, angle=35.0, axis='X'))
    objs.append(fin(box("Hammer_Wedge", (0.014, 0.008, 0.06), "Steel", (0.0, -0.057, 0.0)), 0.002, 1))
    for z in (-1, 1):
        for x in (-0.09, 0.09):
            objs.append(fin(stud("Hammer_Bolt", (x, 0.0, z * 0.058), (0, 0, z), "RustDark", 0.011, 0.006, 6)))
    empties = [socket()] + face_anchors(h) + [shape_box("Head", (0.0, 0.0, 0.0), (2 * h, 0.12, 0.12))]
    return objs, empties


def build_Head_Mace_Ball():
    """Шар булавы с 12 шипами, сварным швом по «экватору» в плоскости экрана, втулкой и проушиной."""
    c = Vector((0.0, -0.165, 0.0))
    r = 0.095
    objs = collar_with_eye("Mace", 0.012, -0.075, 0.034)
    objs.append(fin(sphere("Mace_Ball", r, c, "Rust", 22, 11), angle=60.0))
    objs.append(fin(torus("Mace_Seam", c, r + 0.001, 0.005, "RustDark", 'XY', 24, 5), angle=80))
    dirs = []
    for k in range(8):
        a = TAU * k / 8
        d = Vector((math.cos(a), math.sin(a), 0.0))
        if d.y > 0.9:
            continue            # вверх — втулка
        dirs.append(d)
    dirs += [Vector(v).normalized() for v in ((0.6, -0.3, 0.74), (-0.6, -0.3, 0.74), (0.0, 0.35, 0.94), (0.5, -0.4, -0.77), (-0.5, -0.4, -0.77))]
    for i, d in enumerate(dirs):
        objs.append(fin(spike("Mace_Spike_%d" % i, c + d * (r - 0.012), d, 0.075, 0.021, "Rust"), angle=50.0))
    empties = [socket(), shape_sphere("Ball", c, 0.135), shape_box("Collar", (0.0, -0.03, 0.0), (0.084, 0.09, 0.084))]
    return objs, empties


def build_Blade_Sword():
    """Клинок 0.75 м ромбического сечения (сталь), гарда из гнутого прутка с заклёпками, втулка под торец рукояти."""
    objs = [fin(revolve("Sword_Collar", [(0.0, 0.02), (0.029, 0.02), (0.034, 0.014), (0.034, -0.03), (0.0, -0.03)], "Rust", 16), 0.003, 1, uv="cyl")]
    guard = [(-0.135, -0.026, 0.0), (-0.105, -0.041, 0.0), (-0.05, -0.046, 0.0), (0.0, -0.047, 0.0), (0.05, -0.046, 0.0), (0.105, -0.041, 0.0), (0.135, -0.026, 0.0)]
    objs.append(fin(sweep("Sword_Guard", guard, [0.011, 0.013, 0.014, 0.015, 0.014, 0.013, 0.011], "Rust", sides=8), angle=60.0, axis='X'))
    for sx in (-1, 1):
        objs.append(fin(sphere("Sword_GuardKnob", 0.014, (sx * 0.138, -0.024, 0.0), "Rust", 10, 5), angle=80))

    def section(y, hw, t):
        return [(hw, y, 0.0), (0.45 * hw, y, t), (-0.45 * hw, y, t), (-hw, y, 0.0), (-0.45 * hw, y, -t), (0.45 * hw, y, -t)]

    st = [(-0.045, 0.033, 0.0075), (-0.07, 0.038, 0.0072), (-0.30, 0.036, 0.0066), (-0.55, 0.032, 0.0058), (-0.68, 0.026, 0.005),
          (-0.745, 0.015, 0.0035), (-0.785, 0.004, 0.0015)]
    blade = loft("Sword_Blade", [section(y, hw, t) for y, hw, t in st], "Steel", pole1=(0.0, -0.80, 0.0))
    objs.append(fin(blade, angle=28.0, axis='Y'))
    for y in (-0.062, -0.088):
        objs.append(fin(stud("Sword_Rivet", (0.0, y, 0.0072), (0, 0, 1), "RustDark", 0.006, 0.003, 6)))
    empties = [socket(), shape_box("Guard", (0.0, -0.036, 0.0), (0.29, 0.04, 0.06)), shape_box("Collar", (0.0, -0.005, 0.0), (0.07, 0.05, 0.07)),
               shape_box("Blade", (0.0, -0.425, 0.0), (0.11, 0.75, 0.06))]   # шире клинка (0.076) по ходу маха: иначе на 60 Гц
    # остриё (8–10 м/с при махе) проходит голову насквозь за шаг, контакт выходит боковым и нормальная скорость < порога урона
    return objs, empties


# контур топора weapons.build_axe в координатах детали: x_p = −s (кромка в −X), y_p = 0.705 − x_w (−Y — от хвата)
AXE_OUTLINE = [(0.05, -0.085), (-0.05, -0.085), (-0.13, -0.095), (-0.23, -0.105), (-0.275, -0.085), (-0.31, -0.035),
               (-0.325, 0.045), (-0.31, 0.125), (-0.28, 0.185), (-0.245, 0.235), (-0.205, 0.215), (-0.155, 0.165),
               (-0.105, 0.115), (-0.065, 0.09), (-0.045, 0.085), (0.05, 0.085), (0.062, 0.0)]
AXE_GRIND = {2: 0.01, 3: 0.04, 4: 0.06, 5: 0.07, 6: 0.075, 7: 0.07, 8: 0.06, 9: 0.04, 10: 0.01}


def build_Blade_Axe():
    """Бородатая голова топора (как weapons.build_axe, но ржавая, из листа Свалки): щека ±14 мм, спуск к кромке ±1.5 мм,
    проушина-обух; Anchor_Back — мод на обух (гвозди → клевец)."""
    pts = AXE_OUTLINE
    n = len(pts)
    area = sum(pts[i - 1][0] * pts[i][1] - pts[i][0] * pts[i - 1][1] for i in range(n))
    sgn = 1.0 if area > 0 else -1.0

    def inward(i):
        px, py = pts[i - 1]
        vx, vy = pts[i]
        nx, ny = pts[(i + 1) % n]
        e1 = (vx - px, vy - py)
        e2 = (nx - vx, ny - vy)
        l1 = math.hypot(*e1) or 1.0
        l2 = math.hypot(*e2) or 1.0
        n1 = (-e1[1] / l1 * sgn, e1[0] / l1 * sgn)
        n2 = (-e2[1] / l2 * sgn, e2[0] / l2 * sgn)
        bx, by = n1[0] + n2[0], n1[1] + n2[1]
        lb = math.hypot(bx, by) or 1.0
        bx, by = bx / lb, by / lb
        return bx, by, max(bx * n1[0] + by * n1[1], 0.6)

    inner = {}
    for i, w in AXE_GRIND.items():
        bx, by, c = inward(i)
        inner[i] = (pts[i][0] + bx * w / c, pts[i][1] + by * w / c)
    plate = [inner.get(i, p) for i, p in enumerate(pts)]
    ht, et = 0.013, 0.0015
    objs = [fin(extrude2d("Axe_Plate", plate, -ht, ht, "Rust"), 0.004, 1)]
    secs = []
    for i in sorted(AXE_GRIND):
        gi, o = inner[i], pts[i]
        secs.append([(gi[0], gi[1], -ht + 0.0005), (gi[0], gi[1], ht - 0.0005), (o[0], o[1], et), (o[0], o[1], -et)])
    objs.append(fin(loft("Axe_Grind", secs, "Steel", caps=True), angle=30.0))
    objs.append(fin(box("Axe_Eye", (0.115, 0.17, 0.05), "RustDark", (0.0, 0.0, 0.0)), 0.009, 2))
    for y in (-0.05, 0.05):
        objs.append(fin(stud("Axe_Rivet", (-0.1, y * 0.8, ht), (0, 0, 1), "RustDark", 0.008, 0.004, 6)))
    objs.append(fin(box("Axe_Wedge", (0.012, 0.008, 0.052), "Steel", (0.0, -0.087, 0.0)), 0.002, 1))
    empties = [socket(), anchor("Back", (0.0625, 0.0, 0.0), 90.0),
               shape_box("Eye", (0.0, 0.0, 0.0), (0.125, 0.17, 0.06)),
               shape_box("Blade", (-0.185, 0.0075, 0.0), (0.28, 0.225, 0.06)),
               shape_box("Beard", (-0.25, 0.1775, 0.0), (0.12, 0.115, 0.06))]
    return objs, empties


def build_Hook():
    """Крюк: втулка с проушиной, стержень, загиб радиусом 7.5 см и заострённый кончик, верёвочная обмотка под втулкой."""
    objs = collar_with_eye("Hook", 0.02, -0.06, 0.032)
    path = [(0.0, -0.058, 0.0), (0.0, -0.16, 0.0), (0.0, -0.26, 0.0)]
    cx, cy, rr = -0.075, -0.26, 0.075
    for a in range(-20, -181, -20):
        path.append((cx + rr * math.cos(math.radians(a)), cy + rr * math.sin(math.radians(a)), 0.0))
    path += [(-0.15, -0.22, 0.0), (-0.146, -0.185, 0.0), (-0.138, -0.162, 0.0)]
    n = len(path)
    radii = [0.016] * (n - 4) + [0.013, 0.010, 0.006, 0.0012]
    objs.append(fin(sweep("Hook_Rod", path, radii, "Rust", sides=7), angle=55.0))
    objs += wrap_rings("Hook_Wrap", -0.085, -0.13, 4, 0.021, 0.006, 10.0)
    empties = [socket(), shape_box("Collar", (0.0, -0.03, 0.0), (0.07, 0.09, 0.07)), shape_box("Shank", (0.0, -0.17, 0.0), (0.04, 0.2, 0.06)),
               shape_box("Bend", (-0.075, -0.305, 0.0), (0.19, 0.08, 0.06)), shape_box("Tip", (-0.148, -0.225, 0.0), (0.035, 0.08, 0.06))]
    return objs, empties


def build_Mod_Nails():
    """Мод «6 гвоздей»: ржавая шайба на торец бойка (Socket — центр торца, −Y — наружу) и кольцо из 6 гвоздей-шипов,
    разведённых на 14°, с наплывами сварки. Стальные квадратные стержни, острия чуть кривые (гвозди со Свалки)."""
    objs = [fin(revolve("Nails_Washer", [(0.028, 0.0), (0.074, 0.0), (0.078, -0.004), (0.078, -0.010), (0.074, -0.014), (0.028, -0.014)],
                        "Rust", 24, closed=True), 0.0015, 1)]
    splay = math.radians(14.0)
    for k in range(6):
        a = TAU * k / 6 + math.radians(15.0)
        radial = Vector((math.cos(a), 0.0, math.sin(a)))
        base = radial * 0.054 + Vector((0.0, 0.008, 0.0))
        d = (Vector((0.0, -1.0, 0.0)) * math.cos(splay) + radial * math.sin(splay)).normalized()
        L = 0.095
        bend = Vector((RNG.uniform(-0.004, 0.004), 0.0, RNG.uniform(-0.004, 0.004)))
        pts = [base, base + d * (L * 0.4), base + d * (L * 0.8) + bend * 0.5, base + d * L + bend]
        objs.append(fin(sweep("Nail_%d" % k, pts, [0.0052, 0.0048, 0.0036, 0.0006], "Steel", sides=4, phase=math.pi / 4), angle=50.0))
        bead_c = base + d * (0.022 / math.cos(splay))
        bead = [bead_c + (radial.cross(d).normalized() * math.cos(TAU * i / 8) + radial * math.sin(TAU * i / 8)) * 0.0085 for i in range(8)]
        objs.append(fin(sweep("Nail_Bead_%d" % k, bead, 0.003, "RustDark", sides=4, closed=True), angle=80))
    for k in range(3):
        a = TAU * k / 3 + math.radians(45.0)
        objs.append(fin(stud("Nails_Bolt", (0.034 * math.cos(a), -0.014, 0.034 * math.sin(a)), (0, -1, 0), "RustDark", 0.007, 0.004, 6)))
    empties = [socket(), shape_cyl("Ring", (0.0, -0.0425, 0.0), 0.078, 0.085)]
    return objs, empties


def build_Mod_Iron_Plate():
    """Мод «железная накладка»: толстая пластина на боёк (+1.5 кг), 4 болта, сварной шов по краю; Anchor_Out — поверх неё
    можно поставить гвозди (WOODEN HAMMER + IRON PLATE + NAILS из CONCEPT_V2 §9)."""
    objs = [fin(box("Plate_Slab", (0.17, 0.04, 0.17), "Rust", (0.0, -0.02, 0.0), jitter=0.0015), 0.007, 2)]
    for sx in (-1, 1):
        for sz in (-1, 1):
            objs.append(fin(stud("Plate_Bolt", (sx * 0.058, -0.04, sz * 0.058), (0, -1, 0), "RustDark", 0.012, 0.007, 6)))
    rect = []
    for (x0, z0, x1, z1) in ((-0.087, -0.087, 0.087, -0.087), (0.087, -0.087, 0.087, 0.087), (0.087, 0.087, -0.087, 0.087), (-0.087, 0.087, -0.087, -0.087)):
        for i in range(6):
            t = i / 6
            rect.append((x0 + (x1 - x0) * t, -0.003 + RNG.uniform(-0.001, 0.001), z0 + (z1 - z0) * t))
    objs.append(fin(sweep("Plate_Weld", rect, 0.0045, "RustDark", sides=5, closed=True), angle=70))
    empties = [socket(), anchor("Out", (0.0, -0.04, 0.0)), shape_box("Plate", (0.0, -0.02, 0.0), (0.17, 0.04, 0.17))]
    return objs, empties


def build_Chain_Segment():
    """Сегмент цепи 0.35 м: стальной штифт (ось шарнира, вдоль Z) и серьга в Socket, три звена по 0.125 (1-е и 3-е — ребром
    к камере, 2-е — плашмя), нижнее звено захватывает серьгу следующего сегмента / проушину головки на Anchor_End."""
    objs = [fin(revolve("Chain_Pin", [(0.0, -0.036), (0.011, -0.036), (0.011, -0.03), (0.0065, -0.028), (0.0065, 0.028), (0.011, 0.03),
                                      (0.011, 0.036), (0.0, 0.036)], "Steel", 10, Rx(90.0)), 0.0015, 1, uv="cyl", axis='Z')]
    objs.append(fin(torus("Chain_Shackle", (0.0, 0.0, 0.0), 0.02, 0.0072, "RustDark", 'XY', 14, 6), angle=80))
    for i, (cy, plane) in enumerate(((-0.07, 'YZ'), (-0.175, 'XY'), (-0.28, 'YZ'))):
        objs.append(fin(sweep("Chain_Link_%d" % i, stadium((0.0, cy, 0.0), 0.052, 0.022, plane, 16), 0.0085, "RustDark", sides=6, closed=True),
                        angle=80))
    empties = [socket(), anchor("End", (0.0, -0.35, 0.0)), shape_capsule("Links", (0.0, -0.17, 0.0), 0.03, 0.40)]
    return objs, empties


# ----------------------------------------------------------------------------------------------------------------------
# детали тела
# ----------------------------------------------------------------------------------------------------------------------
def build_Metal_Forearm():
    """Тяжёлое железное предплечье (локоть → запястье 0.27, как у куклы v3): стальной шар локтя, клёпаная ржавая труба
    с двумя бандажами и сварным швом спереди, гнездо запястья с чашкой и штифтом (шар кисти садится на Anchor_Wrist)."""
    prof = [(0.0, -0.028), (0.03, -0.028), (0.042, -0.045), (0.056, -0.075), (0.060, -0.10), (0.058, -0.15), (0.052, -0.20),
            (0.049, -0.228), (0.054, -0.243), (0.057, -0.262), (0.055, -0.284), (0.047, -0.30), (0.0, -0.303)]
    body = revolve("Forearm_Body", prof, "Rust", 20)
    cut_sphere(body, (0.0, -0.27, 0.0), 0.039)
    objs = [ball_joint("Forearm_Ball", 0.045), fin(body, 0.002, 1, angle=45.0, uv="cyl")]
    for y, r in ((-0.09, 0.0605), (-0.175, 0.0565)):
        objs.append(fin(revolve("Forearm_Band", [(r - 0.003, y - 0.011), (r + 0.004, y - 0.009), (r + 0.004, y + 0.009), (r - 0.003, y + 0.011)],
                                "RustDark", 20, closed=True), 0.0015, 1, uv="cyl"))
        for k in range(6):
            a = TAU * k / 6 + math.pi / 2
            nrm = Vector((math.cos(a), 0.0, math.sin(a)))
            objs.append(fin(stud("Forearm_Rivet", Vector((0.0, y, 0.0)) + nrm * (r + 0.004), nrm, "Rust", 0.0065, 0.004, 6)))
    seam = []
    for i in range(9):
        y = -0.105 - 0.06 * i / 8
        seam.append((RNG.uniform(-0.001, 0.001), y, 0.0595 - 0.1 * (0.0 if y > -0.15 else (-0.15 - y))))
    objs.append(fin(sweep("Forearm_Seam", seam, 0.0035, "RustDark", sides=5), angle=70))
    objs.append(fin(revolve("Forearm_Pin", [(0.0, -0.064), (0.0045, -0.064), (0.0045, 0.064), (0.0, 0.064)], "Pin", 10,
                            T((0.0, -0.27, 0.0)) @ Rx(90.0)), 0.001, 1, uv="cyl", axis='Z'))
    empties = [socket(), anchor("Wrist", (0.0, -0.27, 0.0)), anchor("Plate", (0.0, -0.02, 0.0)),
               shape_capsule("Arm", (0.0, -0.135, 0.0), 0.058, 0.36)]
    return objs, empties


def build_Iron_Ball_Fist():
    """Шар вместо кисти (CONCEPT_V2 §8: «рука является булавой»): стальной шар запястья, ржавая шея с болтами, литой шар
    ⌀0.16 с двумя сварными швами."""
    c = Vector((0.0, -0.125, 0.0))
    objs = [ball_joint("Fist_Wrist", 0.036)]
    objs.append(fin(revolve("Fist_Neck", [(0.0, -0.018), (0.022, -0.018), (0.026, -0.03), (0.034, -0.046), (0.042, -0.052), (0.042, -0.058),
                                          (0.0, -0.06)], "Rust", 16), 0.002, 1, uv="cyl"))
    objs.append(fin(sphere("Fist_Ball", 0.078, c, "Rust", 24, 12), angle=60.0))
    objs.append(fin(torus("Fist_SeamH", c, 0.0785, 0.0045, "RustDark", 'XZ', 24, 5), angle=80))
    objs.append(fin(torus("Fist_SeamV", c, 0.0785, 0.004, "RustDark", 'XY', 24, 5), angle=80))
    for k in range(4):
        a = TAU * k / 4 + math.pi / 4
        nrm = Vector((math.cos(a) * 0.5, 0.86, math.sin(a) * 0.5)).normalized()
        objs.append(fin(stud("Fist_Bolt", c + nrm * 0.078, nrm, "RustDark", 0.008, 0.005, 6)))
    empties = [socket(), shape_sphere("Ball", c, 0.08)]
    return objs, empties


def build_Extra_Joint():
    """Доп. сустав (CONCEPT_V2 §6, 5 энергии): стальной шар, короткая кленовая вставка с гнездом и штифтом, как локоть куклы v3,
    верёвочная обмотка; следующая деталь садится шаром в чашку на Anchor_End."""
    prof = [(0.0, -0.026), (0.028, -0.026), (0.034, -0.045), (0.036, -0.07), (0.044, -0.09), (0.054, -0.108), (0.057, -0.128),
            (0.055, -0.15), (0.046, -0.166), (0.0, -0.17)]
    body = revolve("Joint_Body", prof, "Wood", 20)
    body["mat"] = "Wood"
    cut_sphere(body, (0.0, -0.13, 0.0), 0.048)
    objs = [ball_joint("Joint_Ball", 0.045), fin(body, 0.002, 1, angle=45.0, uv="cyl")]
    objs.append(fin(revolve("Joint_Pin", [(0.0, -0.063), (0.0045, -0.063), (0.0045, 0.063), (0.0, 0.063)], "Pin", 10,
                            T((0.0, -0.13, 0.0)) @ Rx(90.0)), 0.001, 1, uv="cyl", axis='Z'))
    objs += wrap_rings("Joint_Wrap", -0.05, -0.068, 3, 0.041, 0.0055, 8.0)
    empties = [socket(), anchor("End", (0.0, -0.13, 0.0)), shape_capsule("Joint", (0.0, -0.065, 0.0), 0.05, 0.23)]
    return objs, empties


def build_Metal_Head():
    """Голова-ведро (CONCEPT_V2 §6, 20 энергии): перевёрнутое ржавое ведро с закатанным краем и двумя гофрами, прорезь
    для лица спереди и за ней кленовая FacePlate (материал Face, UV 0..1 — сюда ляжет фото), вмятины, латунные заклёпки,
    ушки и дужка, откинутая назад; стальной шар шеи в Socket. Socket повёрнут на 180°: голова растёт вверх."""
    outer = [(0.0, 0.338), (0.100, 0.338), (0.112, 0.334), (0.117, 0.322), (0.121, 0.27), (0.126, 0.246), (0.122, 0.238),
             (0.125, 0.22), (0.131, 0.13), (0.136, 0.118), (0.131, 0.108), (0.134, 0.09), (0.138, 0.04), (0.140, 0.03)]
    inner = [(0.134, 0.03), (0.13, 0.05), (0.118, 0.30), (0.0, 0.31)]
    shell = revolve("Bucket_Shell", outer + inner, "Rust", 28, phase=0.1)
    # вмятины: вершины внутрь с плавным спадом (вне прорези)
    me = shell.data
    for cen, rad, depth in (((0.10, 0.07, 0.12), 0.06, 0.012), ((-0.12, 0.26, 0.04), 0.05, 0.009), ((0.05, 0.30, -0.1), 0.05, 0.008)):
        cb = G2B @ Vector(cen)
        for v in me.vertices:
            d = (v.co - cb).length
            if d < rad:
                radial = Vector((v.co.x, v.co.y, 0.0))
                if radial.length > 1e-6:
                    v.co -= radial.normalized() * depth * (1.0 - d / rad) ** 2
    cut_box(shell, (0.0, 0.19, 0.12), (0.15, 0.115, 0.12))
    objs = [fin(shell, 0.0015, 1, angle=40.0, uv="cyl")]
    objs.append(fin(torus("Bucket_Rim", (0.0, 0.03, 0.0), 0.139, 0.0075, "RustDark", 'XZ', 24, 5), angle=80, uv="cyl"))
    for k in range(8):
        a = TAU * k / 8 + 0.3
        nrm = Vector((math.sin(a), 0.0, math.cos(a)))
        objs.append(fin(stud("Bucket_Rivet", Vector((0.0, 0.068, 0.0)) + nrm * 0.1365, nrm, "Brass", 0.0065, 0.004, 6)))
    for sx in (-1, 1):
        lug = box("Bucket_Lug", (0.012, 0.045, 0.03), "RustDark", (sx * 0.128, 0.235, 0.0))
        objs.append(fin(lug, 0.003, 1))
        objs.append(fin(stud("Bucket_LugRivet", (sx * 0.134, 0.24, 0.0), (sx, 0, 0), "Brass", 0.006, 0.004, 6)))
    bail = []
    for i in range(15):
        t = i / 14
        a = math.pi * t
        bail.append((-0.135 * math.cos(a), 0.24 + 0.13 * math.sin(a), -0.10 * math.sin(a)))
    objs.append(fin(sweep("Bucket_Bail", bail, 0.0045, "Steel", sides=6), angle=70))
    objs.append(fin(revolve("Bucket_Neck", [(0.0, 0.02), (0.034, 0.02), (0.036, 0.1), (0.05, 0.14), (0.0, 0.14)], "Wood", 16), uv="cyl"))
    objs.append(ball_joint("Bucket_NeckBall", 0.05, segs=16))
    # FacePlate: кусок цилиндра за прорезью, UV 0..1 на всю пластину
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    cols, rows = 8, 4
    grid = []
    for j in range(rows + 1):
        y = 0.12 + 0.14 * j / rows
        row = []
        for i in range(cols + 1):
            a = math.radians(-42.0 + 84.0 * i / cols)
            row.append(bm.verts.new((0.112 * math.sin(a), y, 0.112 * math.cos(a))))
        grid.append(row)
    for j in range(rows):
        for i in range(cols):
            f = bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
            for l, (ii, jj) in zip(f.loops, ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1))):
                l[uvl].uv = (ii / cols, jj / rows)
    bmesh.ops.transform(bm, matrix=G2B, verts=bm.verts)
    me = bpy.data.meshes.new("FacePlate")
    bm.to_mesh(me)
    bm.free()
    face = bpy.data.objects.new("FacePlate", me)
    bpy.context.scene.collection.objects.link(face)
    me.materials.append(M("Face"))
    for p in me.polygons:
        p.use_smooth = True
    empties = [socket(rot_z=180.0), anchor("Top", (0.0, 0.345, 0.0), 180.0),
               shape_cyl("Bucket", (0.0, 0.18, 0.0), 0.14, 0.32), shape_sphere("Neck", (0.0, 0.0, 0.0), 0.05)]
    return objs, empties, [face]


def superellipse(cx, cy, hw, hh, n=32, e=4.0):
    pts = []
    for i in range(n):
        a = TAU * i / n
        c, s = math.cos(a), math.sin(a)
        pts.append((cx + hw * math.copysign(abs(c) ** (2.0 / e), c), cy + hh * math.copysign(abs(s) ** (2.0 / e), s)))
    return pts


def build_Shield_Plate():
    """Щиток на предплечье (CONCEPT_V2 §6, 12 энергии): крашеный ржавый лист 0.24 × 0.36, выгнутый вокруг руки, перед рукой
    (к камере), окантовка из прутка, заклёпки, умбон, два верёвочных ремня вокруг руки. Socket — верхняя точка на оси руки."""
    bend = 1.2
    out = superellipse(0.0, -0.16, 0.12, 0.18, 32, 4.0)
    objs = [fin(extrude2d("Shield_Sheet", out, 0.064, 0.086, "RustRed", bend=bend), 0.003, 1)]
    rim = [(x, y, 0.087 - bend * x * x) for x, y in superellipse(0.0, -0.16, 0.117, 0.177, 28, 4.0)]
    objs.append(fin(sweep("Shield_Rim", rim, 0.0065, "Rust", sides=5, closed=True), angle=70))
    for x, y in superellipse(0.0, -0.16, 0.095, 0.152, 10, 4.0):
        objs.append(fin(stud("Shield_Rivet", (x, y, 0.086 - bend * x * x), (0, 0, 1), "Rust", 0.0075, 0.005, 6)))
    objs.append(fin(revolve("Shield_Boss", [(0.045, 0.0), (0.043, 0.008), (0.03, 0.02), (0.0, 0.026)], "Rust", 20,
                            T((0.0, -0.16, 0.084)) @ Rx(90.0)), 0.002, 1))
    for y in (-0.06, -0.255):
        objs.append(fin(torus("Shield_Strap", (0.0, y, 0.0), 0.066, 0.008, "Rope", 'XZ', 16, 5), angle=80, uv="cyl"))
    empties = [socket(), shape_box("Plate", (0.0, -0.16, 0.0), (0.24, 0.36, 0.14))]
    return objs, empties


BUILDERS = {n: globals()["build_" + n] for n in WEAPON_PARTS + BODY_PARTS} if bpy is not None else {}


# ----------------------------------------------------------------------------------------------------------------------
# сборка и экспорт
# ----------------------------------------------------------------------------------------------------------------------
def tri_count(objs):
    total = 0
    for o in objs:
        if o.type == 'MESH':
            total += sum(len(p.vertices) - 2 for p in o.data.polygons)
    return total


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


def build_models(only):
    report = []
    for name in WEAPON_PARTS + BODY_PARTS:
        if only and name not in only:
            continue
        C.reset_scene()
        _MATS.clear()
        res = BUILDERS[name]()
        objs, empties = res[0], res[1]
        extra = res[2] if len(res) > 2 else []
        main = C.join(objs, name) if len(objs) > 1 else objs[0]
        main.name = name
        tris = tri_count([main] + extra)
        path = os.path.join(OUT, name + ".glb")
        export(path, [main] + extra + empties)
        xs, ys, zs = [], [], []
        for o in [main] + extra:
            for v in o.data.vertices:
                g = B2G @ (o.matrix_world @ v.co)
                xs.append(g.x)
                ys.append(g.y)
                zs.append(g.z)
        report.append((name, tris, os.path.getsize(path), (min(xs), max(xs)), (min(ys), max(ys)), (min(zs), max(zs)),
                       [e.name for e in empties]))
    print("\nMATERIALS")
    for k in sorted(MAT_STATUS):
        print("  %-10s %s" % (k, MAT_STATUS[k]))
    print("\nPART              TRIS   BYTES     X (Godot)          Y (Godot)          Z          EMPTIES")
    bad = []
    for name, tris, size, x, y, z, em in report:
        if tris > TRI_BUDGET:
            bad.append(name)
        print("%-16s %5d %8d   %6.3f..%-6.3f   %6.3f..%-6.3f   %6.3f..%-6.3f  %s%s" % (name, tris, size, x[0], x[1], y[0], y[1], z[0], z[1],
                                                                                   ", ".join(em), "  OVER BUDGET" if tris > TRI_BUDGET else ""))
    print("=== craft parts tris === " + json.dumps({r[0]: r[1] for r in report}))
    if bad:
        print("ERROR: over budget:", bad)
        sys.exit(1)


# ----------------------------------------------------------------------------------------------------------------------
# контактный рендер (Cycles) и лист (Pillow)
# ----------------------------------------------------------------------------------------------------------------------
ROW_RES = (2600, 980)
CAM_YAW, CAM_PITCH = math.radians(10.0), math.radians(9.0)


def _doll_silhouette(mat, name="Doll_1_8m", skip=()):
    """Силуэт куклы 1.8 м по ригу v3 (шея 1.47, плечи 1.43 ±0.22, локти 1.13, запястья 0.86, бёдра 0.91, колени 0.49), руки
    чуть в стороны; координаты Godot. skip — части, которые не строить (их место займут детали)."""
    parts = []

    def cap(nm, a, b, r):
        a, b = Vector(a), Vector(b)
        d = b - a
        o = revolve(nm, [(0.0, -r), (r * 0.7, -r * 0.7), (r, 0.0), (r, d.length), (r * 0.7, d.length + r * 0.7), (0.0, d.length + r)],
                    "Joint", 14, align_y(d, a))
        parts.append(o)

    if "head" not in skip:
        parts.append(sphere("sil_head", 0.13, (0.0, 1.63, 0.0), "Joint", 16, 10))
        cap("sil_neck", (0.0, 1.45, 0.0), (0.0, 1.52, 0.0), 0.045)
    cap("sil_chest", (0.0, 1.22, 0.0), (0.0, 1.40, 0.0), 0.16)
    cap("sil_belly", (0.0, 0.98, 0.0), (0.0, 1.16, 0.0), 0.13)
    for sx in (-1, 1):
        side = "L" if sx > 0 else "R"
        cap("sil_uarm", (sx * 0.22, 1.43, 0.0), (sx * 0.26, 1.14, 0.0), 0.05)
        if "farm_" + side not in skip:
            cap("sil_farm", (sx * 0.26, 1.13, 0.0), (sx * 0.28, 0.88, 0.0), 0.044)
            parts.append(sphere("sil_hand", 0.05, (sx * 0.285, 0.8, 0.0), "Joint", 12, 6))
        cap("sil_thigh", (sx * 0.1, 0.91, 0.0), (sx * 0.11, 0.51, 0.0), 0.07)
        cap("sil_shin", (sx * 0.11, 0.49, 0.0), (sx * 0.12, 0.1, 0.0), 0.055)
        parts.append(box("sil_foot", (0.1, 0.07, 0.22), "Joint", (sx * 0.12, 0.035, 0.05)))
    for o in parts:
        o.data.materials.clear()
        o.data.materials.append(mat)
        for p in o.data.polygons:
            p.use_smooth = True
    return C.join(parts, name)


def _import_glb(name):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(OUT, name + ".glb"))
    objs = [o for o in bpy.data.objects if o not in before]
    holder = bpy.data.objects.new("H_" + name, None)
    bpy.context.scene.collection.objects.link(holder)
    bpy.context.view_layer.update()
    for o in objs:
        if o.parent is None:
            mw = o.matrix_world.copy()
            o.parent = holder
            o.matrix_world = mw
    holder["part"] = name
    return holder, objs


def _find(objs, base):
    for o in objs:
        if o.name.split(".")[0] == base:
            return o
    return None


def _place_g(holder, xf_g):
    holder.matrix_world = G2B @ xf_g @ B2G
    bpy.context.view_layer.update()


def _bbox_g(objs):
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        if o.type != 'MESH':
            continue
        for c in o.bound_box:
            g = B2G @ (o.matrix_world @ Vector(c))
            lo = Vector((min(lo[k], g[k]) for k in range(3)))
            hi = Vector((max(hi[k], g[k]) for k in range(3)))
    return lo, hi


def _setup_render_scene():
    C.reset_scene()
    _MATS.clear()
    scn = bpy.context.scene
    scn.render.engine = 'CYCLES'
    scn.cycles.samples = int(os.environ.get("CRAFT_RENDER_SAMPLES", "48"))
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
    scn.render.resolution_x, scn.render.resolution_y = ROW_RES
    scn.render.resolution_percentage = 100
    scn.render.image_settings.file_format = 'PNG'
    scn.render.image_settings.color_mode = 'RGB'
    scn.view_settings.view_transform = 'AgX'
    scn.view_settings.look = 'AgX - Medium High Contrast'
    world = bpy.data.worlds.new("World")
    scn.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes['Background']
    bg.inputs['Color'].default_value = (0.30, 0.29, 0.28, 1.0)   # светлый мир: металлу (шар, умбон) есть что отражать
    bg.inputs['Strength'].default_value = 0.55
    floor = C.add_cube("Floor", (80.0, 80.0, 0.02), (0, 0, -0.01))
    C.assign(floor, C.material("FloorMat", (0.03, 0.026, 0.024, 1.0), 0.95, 0.0))
    for nm, col, energy, rot in (("Key", (1.0, 0.76, 0.56), 4.6, (math.radians(50), 0, math.radians(-24))),
                                 ("Fill", (0.55, 0.62, 1.0), 1.5, (math.radians(65), 0, math.radians(150))),
                                 ("Top", (1.0, 0.95, 0.9), 0.7, (math.radians(8), 0, 0))):
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


def _frame_and_render(scn, cam, items, out_png, doll_objs):
    """items: [(label, sub, [объекты])] — вписать всё в кадр, отрендерить, вернуть подписи в пикселях."""
    from bpy_extras.object_utils import world_to_camera_view
    every = list(doll_objs)
    for _l, _s, objs in items:
        every += objs
    corners = []
    for o in every:
        if o.type != 'MESH':
            continue
        for c in o.bound_box:
            corners.append(o.matrix_world @ Vector(c))
    rot = cam.rotation_euler.to_matrix()
    right, up, fwd = rot.col[0], rot.col[1], -rot.col[2]
    us = [c.dot(right) for c in corners]
    vs = [c.dot(up) for c in corners]
    aspect = ROW_RES[0] / ROW_RES[1]
    span = max((max(us) - min(us)) * 1.04, (max(vs) - min(vs)) * 1.30 * aspect)
    cam.data.ortho_scale = span
    cu, cv = (min(us) + max(us)) / 2, (min(vs) + max(vs)) / 2
    cam.location = right * cu + up * (cv - (max(vs) - min(vs)) * 0.10) - fwd * 40.0
    cam.data.clip_end = 200.0
    bpy.context.view_layer.update()
    labels = []
    for label, sub, objs in items:
        lo, hi = _bbox_g(objs)
        p = world_to_camera_view(scn, cam, G2B @ Vector(((lo.x + hi.x) / 2, lo.y, 0.0)))
        labels.append([label, sub, round(p.x * ROW_RES[0]), round((1.0 - p.y) * ROW_RES[1])])
    scn.render.filepath = out_png
    bpy.ops.render.render(write_still=True)
    return labels


def _xf_from(a):
    """12 чисел Transform3D Godot (столбцы базиса x, y, z, затем origin) → Matrix 4x4."""
    m = Matrix.Identity(4)
    for c in range(3):
        for r in range(3):
            m[r][c] = a[c * 3 + r]
    m[0][3], m[1][3], m[2][3] = a[9], a[10], a[11]
    return m


def _assemble(parent_holder, parent_objs, anchor_name, child):
    """Посадка ребёнка по контракту: child = anchor * socket⁻¹ (в Blender; holder ребёнка стоит в нуле при импорте)."""
    holder, objs = child
    anc = _find(parent_objs, "Anchor_" + anchor_name)
    sock = _find(objs, "Socket")
    bpy.context.view_layer.update()
    holder.matrix_world = anc.matrix_world @ (holder.matrix_world.inverted() @ sock.matrix_world).inverted()
    bpy.context.view_layer.update()


def render_rows(layout_path):
    """Три ряда: оружейные детали, детали тела (по отдельности и на силуэте), собранные пресеты (раскладка из пробы)."""
    os.makedirs(RENDER_TMP, exist_ok=True)
    with open(layout_path) as f:
        layout = json.load(f)
    info = {p["glb"]: p for p in layout.get("parts", [])}
    meta = {"rows": []}

    def label_of(name):
        p = info.get(name, {})
        t = p.get("title", name)
        sub = "%.1f кг · E%d · %s%s" % (p.get("mass", 0.0), p.get("energy", 0), p.get("attach", "?"),
                                          (" · ×%.2f" % p["weapon_mult"]) if p.get("weapon_mult", 1.0) != 1.0 else "")
        return t, sub

    # --- ряд 1: оружейные детали, стоят на полу ---
    scn, cam = _setup_render_scene()
    doll = _doll_silhouette(C.material("DollSil", (0.16, 0.17, 0.19, 1.0), 0.6, 0.0))
    x = 0.55
    items = []
    for name in WEAPON_PARTS:
        holder, objs = _import_glb(name)
        rot = Rz(-90.0) if name.startswith("Mod_") else Matrix.Identity(4)   # моды — торцом вбок, чтобы видно было шипы
        _place_g(holder, rot)
        lo, hi = _bbox_g(objs)
        _place_g(holder, T((x - lo.x, -lo.y, 0.0)) @ rot)
        lo, hi = _bbox_g(objs)
        t, sub = label_of(name)
        items.append((t, sub, objs))
        x = hi.x + 0.22
    labels = _frame_and_render(scn, cam, items, os.path.join(RENDER_TMP, "row_weapon.png"), [doll])
    meta["rows"].append({"title": "Оружейные детали (tools/blender/craft_parts.py → assets/models/body/parts/*.glb)",
                         "file": os.path.join(RENDER_TMP, "row_weapon.png"), "labels": labels})

    # --- ряд 2: детали тела отдельно + на силуэте (голова-ведро на шее, левая рука: железо + щит + шар) ---
    scn, cam = _setup_render_scene()
    sil_mat = C.material("DollSil", (0.16, 0.17, 0.19, 1.0), 0.6, 0.0)
    doll = _doll_silhouette(sil_mat)
    doll2 = _doll_silhouette(sil_mat, "Doll_Craft", skip=("head", "farm_L"))
    x = 0.55
    items = []
    for name in BODY_PARTS:
        holder, objs = _import_glb(name)
        lo, hi = _bbox_g(objs)
        _place_g(holder, T((x - lo.x, -lo.y, 0.0)))
        lo, hi = _bbox_g(objs)
        t, sub = label_of(name)
        items.append((t, sub, objs))
        x = hi.x + 0.3
    x2 = x + 0.45
    doll2.location = G2B @ Vector((x2, 0.0, 0.0))
    bpy.context.view_layer.update()
    head = _import_glb("Metal_Head")
    _place_g(head[0], T((x2, 1.47, 0.0)))                      # якорь шеи (Rz 180) · Socket⁻¹ (Rz 180) = только сдвиг
    arm = _import_glb("Metal_Forearm")
    _place_g(arm[0], T((x2 + 0.26, 1.13, 0.0)) @ Rz(8.0))       # локоть левой руки (+X), чуть в сторону
    fist = _import_glb("Iron_Ball_Fist")
    _assemble(arm[0], arm[1], "Wrist", fist)
    shield = _import_glb("Shield_Plate")
    _assemble(arm[0], arm[1], "Plate", shield)
    items.append(("Кукла: ведро + железная рука + щит + шар", "посадка по Socket/Anchor_*", head[1] + arm[1] + fist[1] + shield[1] + [doll2]))
    labels = _frame_and_render(scn, cam, items, os.path.join(RENDER_TMP, "row_body.png"), [doll])
    meta["rows"].append({"title": "Детали тела (справа — они же на кукле: посадка child = anchor · socket.inverse, как в ModularDoll)",
                         "file": os.path.join(RENDER_TMP, "row_body.png"), "labels": labels})

    # --- ряд 3: пресеты оружия (CraftedWeapon, раскладка из tests/craft_probe.gd): боёк вверх; кистень — ещё и лёжа ---
    scn, cam = _setup_render_scene()
    doll = _doll_silhouette(C.material("DollSil", (0.16, 0.17, 0.19, 1.0), 0.6, 0.0))
    x = 0.6
    items = []
    for pr in layout.get("presets", []):
        for pose in ("rest", "lying") if pr["id"] == "flail" else ("rest",):
            objs_all = []
            holders = []
            for e in pr[pose]:
                holder, objs = _import_glb(e["glb"])
                holders.append((holder, _xf_from(e["xf"])))
                objs_all += objs
            up = Rz(90.0) if pose == "rest" else Matrix.Identity(4)   # оружие вдоль +X → вертикально, боёк вверх
            for holder, xf in holders:
                _place_g(holder, up @ xf)
            lo, hi = _bbox_g(objs_all)
            shift = T((x - lo.x, -lo.y, 0.0))
            for holder, xf in holders:
                _place_g(holder, shift @ up @ xf)
            lo, hi = _bbox_g(objs_all)
            st = pr["stats"]
            if pose == "rest":
                sub = "%.1f кг · ЦМ %.2f м · I %.2f · ×%.2f" % (st["mass"], st["com_from_grip"], st["inertia_grip"], st["damage_mult"])
                items.append((pr["title"], sub, objs_all))
            else:
                items.append((pr["title"] + " (лёжа, 4 с физики)", "цепь на свободных шарнирах", objs_all))
            x = hi.x + 0.28
    labels = _frame_and_render(scn, cam, items, os.path.join(RENDER_TMP, "row_presets.png"), [doll])
    meta["rows"].append({"title": "Крафтовое оружие — пресеты data/body/weapons/*.tres, собранные CraftedWeapon (масса, ЦМ и I — от хвата)",
                         "file": os.path.join(RENDER_TMP, "row_presets.png"), "labels": labels})
    with open(os.path.join(RENDER_TMP, "meta.json"), "w") as f:
        json.dump(meta, f, ensure_ascii=False, indent=1)
    print("rendered rows →", RENDER_TMP)


def contact_sheet():
    """Pillow: три ряда рендера друг под другом, заголовки рядов, подписи под деталями → docs/plan-demo/img/craft-parts-v1.png."""
    from PIL import Image, ImageDraw, ImageFont
    with open(os.path.join(RENDER_TMP, "meta.json")) as f:
        meta = json.load(f)
    font = small = big = None
    for fp in ('/System/Library/Fonts/Supplemental/Arial.ttf', '/Library/Fonts/Arial.ttf'):
        if os.path.exists(fp):
            font, small, big = ImageFont.truetype(fp, 20), ImageFont.truetype(fp, 16), ImageFont.truetype(fp, 30)
            break
    if font is None:
        font = small = big = ImageFont.load_default()
    W = ROW_RES[0]
    head_h = 44
    rows = meta["rows"]
    H = 64 + sum(ROW_RES[1] + head_h for _ in rows)
    sheet = Image.new("RGB", (W, H), (18, 17, 20))
    d = ImageDraw.Draw(sheet)
    d.text((16, 16), "Детали крафта v1 — BODY_CRAFT.md §1/§4 (силуэт слева — кукла 1.8 м; подписи: масса · энергия тела · крепление · множитель урона)",
           fill=(232, 226, 214), font=big)
    y = 64
    for row in rows:
        d.rectangle((0, y, W, y + head_h), fill=(30, 28, 32))
        d.text((16, y + 10), row["title"], fill=(250, 196, 120), font=font)
        im = Image.open(row["file"]).convert("RGB")
        sheet.paste(im, (0, y + head_h))
        # подписи лесенкой: соседние узкие детали иначе налезают друг на друга
        ends = []   # правый край последней подписи на каждом уровне
        for label, sub, px, py in sorted(row["labels"], key=lambda e: e[2]):
            wmax = max(d.textlength(label, font=small), d.textlength(sub, font=small))
            x0 = min(max(px - wmax / 2, 4), W - wmax - 4)
            level = 0
            while level < len(ends) and ends[level] > x0 - 14:
                level += 1
            if level == len(ends):
                ends.append(0)
            ends[level] = x0 + wmax
            ty = y + head_h + min(py + 6 + 42 * level, ROW_RES[1] - 46)
            if level > 0:
                d.line((px, y + head_h + py + 2, px, ty - 2), fill=(90, 86, 92), width=1)
            for txt, f_, dy, col in ((label, small, 0, (238, 232, 220)), (sub, small, 19, (160, 156, 150))):
                w_ = d.textlength(txt, font=f_)
                d.text((x0 + (wmax - w_) / 2, ty + dy), txt, fill=col, font=f_)
        y += head_h + ROW_RES[1]
    os.makedirs(os.path.dirname(SHEET_PNG), exist_ok=True)
    sheet.save(SHEET_PNG)
    print("contact sheet", SHEET_PNG, sheet.size)


def main():
    if bpy is None:
        if "--sheet" in sys.argv:
            contact_sheet()
            return
        print("нужен Blender (или --sheet для сборки листа через Pillow)")
        sys.exit(1)
    argv = C.args_after_dashdash()
    if "--render" in argv:
        i = argv.index("--render")
        render_rows(argv[i + 1])
        return
    build_models(argv)


if __name__ == "__main__":
    main()
