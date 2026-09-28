"""Деревянная кукла-игрушка по R19 (docs/refs/R19-a-wooden-doll-poses.jpg, ART_DIRECTION.md §1) — настоящие меши,
headless Blender 4.5. Заменяет серый манекен (mannequin.py).

Запуск:
    /Applications/Blender.app/Contents/MacOS/Blender -b --python godot/tools/blender/wooden_doll.py

Пишет:
    godot/assets/models/heroes/wooden/<Part>.glb   — одна часть, узел в нуле, вершины относительно проксимального
                                                     сустава (origin части = сустав; Torso — центр торса);
    godot/assets/models/heroes/wooden/wooden.glb   — все 14 частей в позе покоя (шарики суставов — у дистальной части).

Риг (метры, координаты Godot) = scenes/doll/doll.gd (D, HIP_Y, SHOULDER_Y) и tools/build_doll_scene.gd:
рост 1.64, бедро y=0.67, плечо y=1.13, центр головы 1.40; плечи x=±0.29, бёдра x=±0.11.

Сборка (ART_DIRECTION §1): сегмент = токарный цилиндр дерева со скруглёнными торцами (волокна вдоль сегмента,
uv_cylinder_along, around=0.5 → две «доски» текстуры на обхват, шов текстуры совпадает с самим собой); на концах
железные обручи с заклёпками, перекрывающие шар сустава; шар сустава (материал Joint, тёмное железо) — у дистальной
части в её origin. Торс — бочка из 12 клёпок с обручами по плечам и талии, крышка сверху, короткий тазовый блок
с железной «юбкой». Кисти — варежки-блоки, стопы — башмаки-блоки носком к камере (+Z Godot). Голова — деревянный
шар, бандана-колпак с узлом и хвостами сзади-справа (меш Bandana) и шарф-петля с треугольным хвостом на груди
(меш Scarf в объекте Torso); FacePlate — плашка спереди (лип 5 мм, UV 0..1 под фото) с резным лицом (две щели глаз и линия рта —
булево вычитание из плашки, снизу тёмные вставки Carve на 4 мм ниже поверхности).

Материалы (PBR-наборы из assets/textures/pbr, common.textured_material):
    Wood / WoodWarm / WoodPale — wood с лёгкими оттенками по частям;  Iron — обручи;  Rivet — головки заклёпок (плоский
    светлый металл, иначе на тёмном железе не читаются);  Joint — шары суставов;
    Shirt — ткань (нейтральная fabric × красный baseColorFactor): Godot заменяет factor на цвет игрока (doll.gd/_recolor),
            поэтому база нейтральная, а не fabric_red (иначе красный × синий = чёрный);
    Face — плоский светлый тон дерева под фото игрока (UV плашки планарные 0..1);  Carve — тёмное дно резьбы.
Текстуры перед упаковкой уменьшаются (дерево 1024², железо/ткань 512²): каждая часть — отдельный glb со своими
копиями картинок, 2048² на конечность ⌀15 см избыточны.

Оси: описываем всё в координатах Godot (X вбок, +X = левая сторона куклы, Y вверх, +Z к камере) и переводим в
Blender через B(): (x, -z, y); лицо в -Y Blender → +Z Godot после экспорта с Y вверх.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import common  # noqa: E402

GODOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT_DIR = os.path.join(GODOT, "assets", "models", "heroes", "wooden")
TRI_BUDGET = 30000

# --- риг (метры, координаты Godot) = scenes/doll/doll.gd -----------------------------------------
HEAD_R = 0.24
TORSO_W, TORSO_H, TORSO_D = 0.42, 0.46, 0.28
UA, LA, HAND = 0.26, 0.24, 0.12
UL, LL, FOOT, FOOT_H, FOOT_W = 0.30, 0.28, 0.24, 0.09, 0.16
ARM_R, LEG_R, NECK = 0.075, 0.085, 0.03
SX, HX = 0.29, 0.11
HIP_Y = UL + LL + FOOT_H              # 0.67
SHOULDER_Y = HIP_Y + TORSO_H          # 1.13
ELBOW_Y = SHOULDER_Y - UA             # 0.87
WRIST_Y = ELBOW_Y - LA                # 0.63
KNEE_Y = HIP_Y - UL                   # 0.37
ANKLE_Y = FOOT_H                      # 0.09
HEAD_C = SHOULDER_Y + NECK + HEAD_R   # 1.40
TORSO_C = HIP_Y + TORSO_H / 2.0       # 0.90

# радиусы шаров суставов (у дистальной части)
BALL = {"neck": 0.070, "shoulder": 0.085, "elbow": 0.080, "wrist": 0.065,
        "hip": 0.095, "knee": 0.090, "ankle": 0.078}
BAND_T = 0.012      # выступ обруча над деревом
BAND_H = 0.032      # высота обруча
GAP = 0.45          # дерево начинается на GAP·r_шара от центра сустава (шар перекрывает стык)

SMOOTH_DEG = 55.0
TAU = 2.0 * math.pi


def B(x, y, z):
    """Godot (x, y_up, z_front) → Blender (x, -z, y)."""
    return Vector((x, -z, y))


# ------------------------------------------------------------------------------------------------
# материалы
# ------------------------------------------------------------------------------------------------
def srgb(r, g, b):
    return tuple(((c + 0.055) / 1.055) ** 2.4 if c > 0.04045 else c / 12.92 for c in (r, g, b)) + (1.0,)


TEX_SIZE = {"wood": 1024, "iron": 512, "fabric": 512}


def shrink_textures():
    """Загружает и уменьшает наборы PBR до размеров TEX_SIZE, упаковывает — common._load_packed возьмёт эти же
    datablock-и (check_existing), и в glb уйдут уменьшенные картинки."""
    for folder, size in TEX_SIZE.items():
        for fname in ("albedo.png", "roughness.png", "normal.png", "metallic.png"):
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
    shrink_textures()
    return {
        "Wood": common.textured_material("Wood", "wood", tint=(0.97, 0.94, 0.88, 1.0)),
        "WoodWarm": common.textured_material("WoodWarm", "wood", tint=(1.0, 0.91, 0.80, 1.0)),
        "WoodPale": common.textured_material("WoodPale", "wood", tint=(1.0, 0.98, 0.94, 1.0), roughness_scale=1.05),
        "Iron": common.textured_material("Iron", "iron", tint=(1.0, 0.90, 0.80, 1.0), roughness_scale=0.75),
        "Rivet": common.material("Rivet", srgb(0.46, 0.43, 0.39), rough=0.42, metal=0.9),   # светлые головки заклёпок
        "Joint": common.textured_material("Joint", "iron", tint=(0.55, 0.55, 0.58, 1.0), roughness_scale=0.8),
        # база — нейтральная мешковина; красный = baseColorFactor, который Godot подменяет цветом игрока
        "Shirt": common.textured_material("Shirt", "fabric", tint=(0.86, 0.14, 0.11, 1.0)),
        # плашка лица: то же дерево, но UV 0..1 (под фото) ужаты Mapping-нодой (→ KHR_texture_transform) в одну доску
        "Face": add_uv_transform(common.textured_material("Face", "wood", tint=(1.0, 0.97, 0.90, 1.0)), (0.22, 0.25), (0.015, 0.30)),
        "Carve": common.material("Carve", srgb(0.16, 0.10, 0.06), rough=0.95, metal=0.0),
    }


def add_uv_transform(mat, scale, loc):
    """UV Map → Mapping(POINT) → все Image Texture: экспортёр glTF пишет KHR_texture_transform, Godot читает его
    в uv1_scale/uv1_offset. Код подмены фото должен сбросить их в (1,1)/(0,0)."""
    nt = mat.node_tree
    uvn = nt.nodes.new('ShaderNodeUVMap')
    mp = nt.nodes.new('ShaderNodeMapping')
    mp.vector_type = 'POINT'
    mp.inputs['Location'].default_value = (loc[0], loc[1], 0.0)
    mp.inputs['Scale'].default_value = (scale[0], scale[1], 1.0)
    nt.links.new(uvn.outputs['UV'], mp.inputs['Vector'])
    for n in nt.nodes:
        if n.type == 'TEX_IMAGE':
            nt.links.new(mp.outputs['Vector'], n.inputs['Vector'])
    return mat


MAT = {}


# ------------------------------------------------------------------------------------------------
# геометрические хелперы (мировые координаты Blender)
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


def finish(obj, mat, bevel_w=0.0, seg=2, sub=0):
    common.assign(obj, MAT[mat])
    if bevel_w > 0.0:
        common.bevel(obj, bevel_w, seg)
    if sub > 0:
        common.subsurf(obj, sub)
    apply_mods(obj)
    return obj


def mesh_object(name, bm, loc=(0, 0, 0)):
    """bmesh → объект сцены в позиции loc (вершины bm — локальные)."""
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    o.location = loc
    return o


def lathe(name, profile, verts=24, loc=(0, 0, 0)):
    """Тело вращения вокруг локальной Z: profile = [(r, z), …] снизу вверх, крайние точки r=0 закрывают торцы."""
    bm = bmesh.new()
    vs = [bm.verts.new((max(r, 0.0), 0.0, z)) for r, z in profile]
    edges = [bm.edges.new((vs[i], vs[i + 1])) for i in range(len(vs) - 1)]
    bmesh.ops.spin(bm, geom=vs + edges, cent=(0, 0, 0), axis=(0, 0, 1), dvec=(0, 0, 0),
                   angle=TAU, steps=verts, use_merge=True)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-6)
    return mesh_object(name, bm, loc)


def rounded_profile(r0, r1, z0, z1, fillet, steps=3, swell=0.0):
    """Профиль токарного сегмента: скруглённые торцы (четверть окружности fillet), лёгкая бочка swell в середине."""
    f0 = min(fillet, r0 * 0.9)
    f1 = min(fillet, r1 * 0.9)
    pts = [(0.0, z0)]
    for i in range(steps + 1):
        a = -math.pi / 2 + (math.pi / 2) * i / steps
        pts.append((r0 - f0 + f0 * math.cos(a), z0 + f0 + f0 * math.sin(a)))
    mid_n = 3
    for i in range(1, mid_n):
        t = i / mid_n
        z = (z0 + f0) + ((z1 - f1) - (z0 + f0)) * t
        r = r0 + (r1 - r0) * t
        pts.append((r * (1.0 + swell * math.sin(math.pi * t)), z))
    for i in range(steps + 1):
        a = (math.pi / 2) * i / steps
        pts.append((r1 - f1 + f1 * math.cos(a), z1 - f1 + f1 * math.sin(a)))
    pts.append((0.0, z1))
    return pts


def wood_segment(name, centre_xy, z0, z1, r0, r1, mat="Wood", verts=20, swell=0.03):
    """Деревянный сегмент вдоль Z от z0 до z1 (мировые), ось в (x, y); UV — волокна вдоль Z, 2 доски на обхват."""
    prof = rounded_profile(r0, r1, z0 - (z0 + z1) / 2.0, z1 - (z0 + z1) / 2.0, min(r0, r1) * 0.55, swell=swell)
    o = lathe(name, prof, verts, loc=(centre_xy[0], centre_xy[1], (z0 + z1) / 2.0))
    common.uv_cylinder_along(o, 'Z', 0.5, around=0.25, centre=(0.0, 0.0))
    common.assign(o, MAT[mat])
    return o


def iron_band(name, centre_xy, z, r, h=BAND_H, rivets=6, rivet_r=0.011, verts=20, phase=0.0):
    """Обруч: короткий цилиндр радиуса r с фаской + заклёпки по окружности; возвращает список объектов."""
    o = common.add_cylinder(name, radius=r, depth=h, loc=(centre_xy[0], centre_xy[1], z), verts=verts)
    common.uv_cylinder_along(o, 'Z', 1.0, centre=(0.0, 0.0))
    out = [finish(o, "Iron", bevel_w=0.004, seg=1)]
    out += rivet_ring(name, centre_xy, z, lambda a: ((r + 0.003) * math.cos(a), (r + 0.003) * math.sin(a)), rivets, rivet_r, phase)
    return out


def rivet_ring(name, centre_xy, z, curve, n, rr, phase=0.0):
    out = []
    for i in range(n):
        a = phase + TAU * i / n
        px, py = curve(a)
        s = common.add_sphere("%s_rv%d" % (name, i), rr, loc=(centre_xy[0] + px, centre_xy[1] + py, z), segments=6, rings=3)
        common.uv_box(s, 1.0)
        common.assign(s, MAT["Rivet"])
        out.append(s)
    return out


def ball(name, pos, r):
    o = common.add_sphere(name, r, loc=pos, segments=20, rings=10)
    common.uv_box(o, 1.0)
    common.assign(o, MAT["Joint"])
    return o


def sweep_ring(name, curve, section, segs=48, loc=(0, 0, 0)):
    """Замкнутая труба: curve(t∈[0,1)) → (x, y, nx, ny) — точка контура и внешняя нормаль в плоскости XY;
    section = [(d, z), …] — замкнутый многоугольник сечения (d — вдоль нормали, z — высота)."""
    bm = bmesh.new()
    rings = []
    for i in range(segs):
        x, y, nx, ny = curve(i / segs)
        rings.append([bm.verts.new((x + nx * d, y + ny * d, z)) for d, z in section])
    m = len(section)
    for i in range(segs):
        a, b = rings[i], rings[(i + 1) % segs]
        for j in range(m):
            bm.faces.new((a[j], b[j], b[(j + 1) % m], a[(j + 1) % m]))
    return mesh_object(name, bm, loc)


def ellipse_curve(rx, ry, phase=0.0):
    def f(t):
        a = TAU * t + phase
        x, y = rx * math.cos(a), ry * math.sin(a)
        n = Vector((ry * math.cos(a), rx * math.sin(a))).normalized()
        return x, y, n.x, n.y
    return f


def superellipse_curve(rx, ry, n=4.0):
    """Скруглённый прямоугольник |x/rx|^n + |y/ry|^n = 1."""
    def f(t):
        a = TAU * t
        c, s = math.cos(a), math.sin(a)
        x = rx * math.copysign(abs(c) ** (2.0 / n), c)
        y = ry * math.copysign(abs(s) ** (2.0 / n), s)
        # градиент как нормаль
        gx = math.copysign(abs(x / rx) ** (n - 1), x) / rx
        gy = math.copysign(abs(y / ry) ** (n - 1), y) / ry
        nv = Vector((gx, gy)).normalized()
        return x, y, nv.x, nv.y
    return f


def rect_section(d_out, d_in, z0, z1, ch=0.004):
    """Сечение обруча с фасками: наружу d_out, внутрь d_in (отрицательное значение = внутрь)."""
    return [(d_in, z0), (d_out - ch, z0), (d_out, z0 + ch), (d_out, z1 - ch), (d_out - ch, z1), (d_in, z1)]


def rounded_block(name, centre, size, bevel_w, sub=1, mat="Wood", along='Z', uv_scale=0.5, seg=2):
    o = common.add_cube(name, size=size, loc=centre)
    common.uv_box(o, uv_scale, along=along)
    return finish(o, mat, bevel_w=bevel_w, seg=seg, sub=sub)


def assemble(name, objs, origin, smooth_deg=SMOOTH_DEG):
    j = common.join(objs, name)
    common.smooth(j, smooth_deg)
    common.set_origin(j, origin)
    return j


# ------------------------------------------------------------------------------------------------
# сегмент конечности: токарное дерево + два обруча + шар проксимального сустава (origin = проксимальный сустав)
# ------------------------------------------------------------------------------------------------
def limb(name, x, y_top, y_bot, r_top, r_bot, ball_top, ball_bot, mat="Wood"):
    g_t = GAP * BALL[ball_top]
    g_b = GAP * BALL[ball_bot]
    z0, z1 = y_bot + g_b, y_top - g_t            # Blender z = Godot y (плоскость z_godot = 0 → y_blender = 0)
    parts = [wood_segment(name + "_seg", (x, 0.0), z0, z1, r_bot, r_top, mat)]
    parts += iron_band(name + "_bandT", (x, 0.0), z1 - BAND_H / 2.0 + 0.004, r_top + BAND_T, phase=-math.pi / 2)
    parts += iron_band(name + "_bandB", (x, 0.0), z0 + BAND_H / 2.0 - 0.004, r_bot + BAND_T, phase=-math.pi / 2)
    parts.append(ball(name + "_ball", B(x, y_top, 0.0), BALL[ball_top]))
    return assemble(name, parts, B(x, y_top, 0.0))


# ------------------------------------------------------------------------------------------------
# кисть: шар запястья + обруч + варежка-блок (скруглённый) + бугорок большого пальца сбоку
# ------------------------------------------------------------------------------------------------
def hand(name, k):
    x = SX * k
    wr = WRIST_Y
    parts = [ball(name + "_ball", B(x, wr, 0.0), BALL["wrist"])]
    band_z = wr - GAP * BALL["wrist"] - 0.002                       # ≈0.60
    parts += iron_band(name + "_band", (x, 0.0), band_z, 0.052 + BAND_T, h=0.03, rivets=5, rivet_r=0.008, phase=-math.pi / 2)
    top, bot = band_z - 0.006, wr - HAND                            # 0.594 .. 0.51
    hh = (top - bot) / 2.0
    mitt = lathe(name + "_mitt", rounded_profile(0.046, 0.051, -hh, hh, 0.032, swell=0.0), verts=20, loc=(x, 0.0, (top + bot) / 2.0))
    mitt.scale = (1.0, 0.72, 1.0)
    common.apply_transforms(mitt, scale=True)
    common.uv_cylinder_along(mitt, 'Z', 0.5, around=0.25, centre=(0.0, 0.0))
    common.assign(mitt, MAT["WoodWarm"])
    parts.append(mitt)
    thumb = rounded_block(name + "_thumb", (x + k * 0.056, -0.012, top - 0.032), (0.034, 0.032, 0.046), 0.012, sub=1, mat="WoodWarm", seg=1)
    parts.append(thumb)
    return assemble(name, parts, B(x, wr, 0.0))


# ------------------------------------------------------------------------------------------------
# стопа: шар лодыжки + башмак-блок носком к камере (−Y Blender) + железная полоса поперёк подъёма
# ------------------------------------------------------------------------------------------------
def foot(name, k):
    x = HX * k
    ankle = B(x, ANKLE_Y, 0.0)
    # башмак: Godot z ∈ [−0.09, 0.15] → Blender y ∈ [−0.15, 0.09]; носок чуть уже и ниже
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x, -0.03, FOOT_H / 2.0 + 0.001))
    shoe = bpy.context.active_object
    shoe.name = name + "_shoe"
    for v in shoe.data.vertices:
        front = v.co.y < 0.0
        top = v.co.z > 0.0
        vx = math.copysign(FOOT_W / 2.0, v.co.x) * (0.9 if front else 1.0)
        vy = -FOOT / 2.0 if front else FOOT / 2.0
        vz = (FOOT_H / 2.0 - 0.001) if top else -(FOOT_H / 2.0 - 0.001)
        if front and top:
            vz -= 0.018
        v.co = Vector((vx, vy, vz))
    common.uv_box(shoe, 0.5, along='Y')
    shoe = finish(shoe, "WoodWarm", bevel_w=0.03, seg=2, sub=1)
    parts = [shoe]
    # полоса вокруг сечения башмака (скруглённый прямоугольник), ось вдоль стопы (Y)
    rx, ry = FOOT_W / 2.0 + 0.003, FOOT_H / 2.0 + 0.003
    curve = superellipse_curve(rx, ry, 4.0)
    band = sweep_ring(name + "_strap", curve, rect_section(0.008, -0.006, -0.015, 0.015), segs=32)
    band.rotation_euler = (math.pi / 2.0, 0.0, 0.0)
    band.location = (x, -0.012, FOOT_H / 2.0)
    common.apply_transforms(band, rotation=True)
    common.uv_box(band, 1.0)
    parts.append(finish(band, "Iron"))
    for t in (0.0, 0.14, 0.36, 0.5):
        cx, cy, nx, ny = curve(t)
        s = common.add_sphere("%s_rv%.2f" % (name, t), 0.008, loc=(x + cx + nx * 0.008, -0.012, FOOT_H / 2.0 + cy + ny * 0.008), segments=6, rings=3)
        common.uv_box(s, 1.0)
        common.assign(s, MAT["Rivet"])
        parts.append(s)
    parts.append(ball(name + "_ball", ankle, BALL["ankle"]))
    return assemble(name, parts, ankle)


# ------------------------------------------------------------------------------------------------
# торс: бочка из 12 клёпок (эллипс 0.40 × 0.27, лёгкий бочонок) + обручи по плечам и талии + крышка +
# тазовый блок с железной «юбкой» + шарф (дочерний объект Scarf). Origin — центр торса (0, TORSO_C).
# ------------------------------------------------------------------------------------------------
BARREL_Z0, BARREL_Z1 = 0.72, 1.06
BARREL_RX, BARREL_RY = 0.20, 0.135
STAVES = 12


def bulge(z):
    """Множитель радиуса бочки по высоте: 1.0 в середине, 0.90 на концах."""
    zm = (BARREL_Z0 + BARREL_Z1) / 2.0
    zh = (BARREL_Z1 - BARREL_Z0) / 2.0
    return 1.0 - 0.10 * ((z - zm) / zh) ** 2


def barrel_point(a, z, extra=0.0):
    f = bulge(z)
    return Vector(((BARREL_RX * f + extra) * math.cos(a), (BARREL_RY * f + extra) * math.sin(a), z))


def stave(i):
    """Одна клёпка: наружная сетка 3 × 7 по эллипсу с бочонком, Solidify внутрь, фаска по рёбрам."""
    gap = math.radians(1.6)
    a0 = TAU * i / STAVES + gap
    a1 = TAU * (i + 1) / STAVES - gap
    na, nz = 2, 4
    bm = bmesh.new()
    grid = []
    for iz in range(nz + 1):
        z = BARREL_Z0 + (BARREL_Z1 - BARREL_Z0) * iz / nz
        grid.append([bm.verts.new(barrel_point(a0 + (a1 - a0) * ia / na, z)) for ia in range(na + 1)])
    for iz in range(nz):
        for ia in range(na):
            bm.faces.new((grid[iz][ia], grid[iz][ia + 1], grid[iz + 1][ia + 1], grid[iz + 1][ia]))
    o = mesh_object("Torso_stave%d" % i, bm)
    common.uv_cylinder_along(o, 'Z', 0.35, around=0.75, centre=(0.0, 0.0))   # 12 клёпок = 3 доски текстуры: крупные волокна, швы досок на стыках клёпок
    sol = o.modifiers.new("Solidify", 'SOLIDIFY')
    sol.thickness = 0.022
    sol.offset = -1.0
    sol.use_even_offset = True
    mat = "Wood" if i % 3 else "WoodWarm"
    return finish(o, mat, bevel_w=0.007, seg=1)


def torso_band(name, z, h=0.034, rivets=8):
    f = bulge(z)
    curve = ellipse_curve(BARREL_RX * f, BARREL_RY * f)
    o = sweep_ring(name, curve, rect_section(BAND_T, -0.012, -h / 2.0, h / 2.0), segs=40, loc=(0, 0, z))
    common.uv_cylinder_along(o, 'Z', 1.0, centre=(0.0, 0.0))
    out = [finish(o, "Iron")]
    for i in range(rivets):
        x, y, nx, ny = curve(i / rivets)
        s = common.add_sphere("%s_rv%d" % (name, i), 0.013, loc=(x + nx * (BAND_T + 0.004), y + ny * (BAND_T + 0.004), z), segments=6, rings=3)
        common.uv_box(s, 1.0)
        common.assign(s, MAT["Rivet"])
        out.append(s)
    return out


def torso_lid():
    """Эллиптическая крышка-купол от верха бочки до плеча (z 1.055 .. SHOULDER_Y) с воротником под шар шеи."""
    f = bulge(BARREL_Z1)
    prof = [(0.0, 1.052), (1.0, 1.052), (1.0, 1.072), (0.975, 1.092), (0.90, 1.108), (0.76, 1.120), (0.55, 1.127), (0.0, SHOULDER_Y)]
    o = lathe("Torso_lid", prof, verts=32)
    o.scale = (BARREL_RX * f - 0.004, BARREL_RY * f - 0.004, 1.0)
    common.apply_transforms(o, scale=True)
    common.uv_cylinder_along(o, 'Z', 0.5, centre=(0.0, 0.0))
    lid = finish(o, "WoodPale")
    collar = lathe("Torso_collar", rounded_profile(0.082, 0.078, -0.02, 0.02, 0.012, swell=0.0), verts=20,
                   loc=(0.0, 0.0, SHOULDER_Y - 0.005))
    common.uv_cylinder_along(collar, 'Z', 0.5, around=0.25, centre=(0.0, 0.0))
    common.assign(collar, MAT["WoodWarm"])
    return [lid, collar]


def pelvis():
    zc = 0.665
    block = lathe("Torso_pelvis", rounded_profile(1.0, 1.0, -0.055, 0.055, 0.28, swell=0.02), verts=32, loc=(0.0, 0.0, zc))
    block.scale = (0.155, 0.105, 1.0)
    common.apply_transforms(block, scale=True)
    common.uv_cylinder_along(block, 'Z', 0.5, around=0.75, centre=(0.0, 0.0))
    common.assign(block, MAT["WoodWarm"])
    curve = ellipse_curve(0.155, 0.105)
    skirt = sweep_ring("Torso_skirt", curve, rect_section(0.010, -0.008, -0.017, 0.017), segs=40, loc=(0, 0, zc - 0.01))
    common.uv_cylinder_along(skirt, 'Z', 1.0, centre=(0.0, 0.0))
    out = [block, finish(skirt, "Iron")]
    for t in (0.62, 0.75, 0.88, 0.12, 0.25, 0.38, 0.0, 0.5):
        x, y, nx, ny = curve(t)
        s = common.add_sphere("Torso_skirt_rv%.2f" % t, 0.010, loc=(x + nx * 0.012, y + ny * 0.012, zc - 0.01), segments=6, rings=3)
        common.uv_box(s, 1.0)
        common.assign(s, MAT["Rivet"])
        out.append(s)
    return out


def cloth_strip(name, point_fn, nu, nv, thickness=0.006):
    """Полоска ткани: сетка nu × nv по point_fn(u, v) → Vector, Solidify по толщине (обе стороны)."""
    bm = bmesh.new()
    grid = [[bm.verts.new(point_fn(iu / nu, iv / nv)) for iu in range(nu + 1)] for iv in range(nv + 1)]
    for iv in range(nv):
        for iu in range(nu):
            q = (grid[iv][iu], grid[iv][iu + 1], grid[iv + 1][iu + 1], grid[iv + 1][iu])
            if len({v.co.to_tuple(5) for v in q}) >= 3:
                bm.faces.new(q)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-5)
    o = mesh_object(name, bm)
    common.uv_box(o, 4.0, along='Z')
    sol = o.modifiers.new("Solidify", 'SOLIDIFY')
    sol.thickness = thickness
    sol.offset = 0.0
    common.assign(o, MAT["Shirt"])
    return apply_mods(o)


def scarf():
    """Петля вокруг шеи (сплюснутый тор r 0.105) + треугольный хвост на груди + узелок спереди-слева."""
    zc = SHOULDER_Y + 0.02
    sec = [(0.030 * math.cos(a), 0.020 * math.sin(a)) for a in [TAU * i / 8 for i in range(8)]]
    loop = sweep_ring("Scarf_loop", ellipse_curve(0.105, 0.100), sec, segs=32, loc=(0, 0, zc))
    common.uv_cylinder_along(loop, 'Z', 4.0, centre=(0.0, 0.0))
    common.assign(loop, MAT["Shirt"])

    def flap(u, v):
        w = 0.20 * (1.0 - v) ** 0.85
        x = (u - 0.5) * w + 0.025 * v
        z = zc - 0.005 - 0.20 * v
        f = bulge(min(max(z, BARREL_Z0), BARREL_Z1))
        surf = BARREL_RY * f + BAND_T + 0.006
        y = -min(surf, 0.118 + 0.30 * v) - 0.004 * math.sin(6.0 * u + 4.0 * v)
        return Vector((x, y, z))
    tail = cloth_strip("Scarf_tail", flap, 6, 8)
    knot = common.add_sphere("Scarf_knot", 0.03, loc=(0.075, -0.108, zc + 0.005), segments=12, rings=6, scale=(1.0, 0.8, 0.85))
    common.uv_box(knot, 4.0)
    common.assign(knot, MAT["Shirt"])
    s = common.join([loop, tail, knot], "Scarf")
    common.smooth(s, SMOOTH_DEG)
    return s


def torso():
    parts = [stave(i) for i in range(STAVES)]
    parts += torso_band("Torso_bandW", 0.79)
    parts += torso_band("Torso_bandS", 1.045)
    parts += torso_lid()
    parts += pelvis()
    origin = B(0, TORSO_C, 0)
    t = assemble("Torso", parts, origin)
    sc = scarf()
    common.set_origin(sc, origin)
    common.parent(sc, t)
    return t, sc


# ------------------------------------------------------------------------------------------------
# голова: шар шеи + шейка + деревянный шар (волокна вертикально, 6 досок на обхват) + FacePlate с резьбой +
# Bandana (дочерний объект: колпак, валик по краю, узел и два хвоста сзади-справа)
# ------------------------------------------------------------------------------------------------
HEAD_CB = B(0, HEAD_C, 0)
FACE_AXIS = Vector((0.0, -1.0, -0.10)).normalized()


def sph(r, th, ph):
    """Точка сферы: th — от +Z (макушка), ph — азимут от +X против часовой; −Y (лицо) при ph = −90°."""
    return Vector((r * math.sin(th) * math.cos(ph), r * math.sin(th) * math.sin(ph), r * math.cos(th)))


def face_plate():
    """Сферический колпак вокруг FACE_AXIS (θ ≤ 38°) толщиной 10 мм над шаром головы; UV планарные 0..1
    (X → U, Z → V) под фото игрока. Резьба: две вертикальные щели глаз и линия рта — булево вычитание
    из плашки, снизу тёмные вставки (Carve) на 5 мм ниже поверхности."""
    axis = FACE_AXIS
    u = Vector((1.0, 0.0, 0.0))
    w = axis.cross(u).normalized()
    u = w.cross(axis).normalized()
    r_in = HEAD_R + 0.001
    rings_n, segs = 6, 32
    th_max = math.radians(32.0)
    bm = bmesh.new()
    rings = [[bm.verts.new(axis * r_in)]]
    for i in range(1, rings_n + 1):
        th = th_max * i / rings_n
        rings.append([bm.verts.new((math.cos(th) * axis + math.sin(th) * (math.cos(TAU * j / segs) * u + math.sin(TAU * j / segs) * w)) * r_in)
                      for j in range(segs)])
    c = rings[0][0]
    for j in range(segs):
        bm.faces.new((c, rings[1][j], rings[1][(j + 1) % segs]))
    for i in range(1, rings_n):
        for j in range(segs):
            bm.faces.new((rings[i][j], rings[i][(j + 1) % segs], rings[i + 1][(j + 1) % segs], rings[i + 1][j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.normal_update()
    if sum(f.normal.dot(axis) for f in bm.faces) < 0.0:
        bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
    uv = bm.loops.layers.uv.verify()
    xs = [v.co.x for v in bm.verts]
    zs = [v.co.z for v in bm.verts]
    x0, x1, z0, z1 = min(xs), max(xs), min(zs), max(zs)
    for f in bm.faces:
        for l in f.loops:
            l[uv].uv = ((l.vert.co.x - x0) / (x1 - x0), (l.vert.co.z - z0) / (z1 - z0))
    fp = mesh_object("FacePlate", bm, loc=HEAD_CB)
    common.assign(fp, MAT["Face"])
    sol = fp.modifiers.new("Solidify", 'SOLIDIFY')
    sol.thickness = 0.004
    sol.offset = 1.0
    sol.use_rim = True
    apply_mods(fp)

    def radial_box(name, dx, dz, size, depth_c, mat=None):
        """Блок, ориентированный по радиусу головы в точке (dx, dz) относительно центра лица: локальная −Y = наружу."""
        d = (axis * r_in + u * dx + w * dz).normalized()
        o = common.add_cube(name, size=size, loc=(0, 0, 0))
        o.rotation_euler = d.to_track_quat('-Y', 'Z').to_euler()
        o.location = HEAD_CB + d * depth_c
        common.apply_transforms(o, rotation=True, location=True)
        if mat:
            common.uv_box(o, 1.0)
            common.assign(o, MAT[mat])
        return o

    r_out = r_in + 0.004
    feats = [(-0.050, 0.030, (0.014, 0.05, 0.056)), (0.050, 0.030, (0.014, 0.05, 0.056)), (0.0, -0.065, (0.056, 0.05, 0.011))]
    cutters = [radial_box("cut%d" % i, dx, dz, sz, r_out) for i, (dx, dz, sz) in enumerate(feats)]
    for cnode in cutters:
        m = fp.modifiers.new("Bool", 'BOOLEAN')
        m.operation = 'DIFFERENCE'
        m.solver = 'EXACT'
        m.object = cnode
    apply_mods(fp)
    for cnode in cutters:
        bpy.data.objects.remove(cnode, do_unlink=True)
    inserts = [radial_box("carve%d" % i, dx, dz, (sz[0], 0.03, sz[2]), r_out - 0.004 - 0.015, mat="Carve") for i, (dx, dz, sz) in enumerate(feats)]
    fp = common.join([fp] + inserts, "FacePlate")
    common.smooth(fp, SMOOTH_DEG)
    return fp


def bandana():
    R = HEAD_R + 0.010
    ph_front = -math.pi / 2

    def th_max(ph):
        brim = max(0.0, math.cos(ph - ph_front)) ** 2
        return math.radians(70.0 + 3.0 * math.sin(3.0 * ph + 0.7) + 6.0 * brim)

    rings_n, segs = 7, 32
    bm = bmesh.new()
    rings = [[bm.verts.new(Vector((0, 0, R)))]]
    for i in range(1, rings_n + 1):
        ring = []
        for j in range(segs):
            ph = TAU * j / segs
            ring.append(bm.verts.new(sph(R, th_max(ph) * i / rings_n, ph)))
        rings.append(ring)
    c = rings[0][0]
    for j in range(segs):
        bm.faces.new((c, rings[1][j], rings[1][(j + 1) % segs]))
    for i in range(1, rings_n):
        for j in range(segs):
            bm.faces.new((rings[i][j], rings[i][(j + 1) % segs], rings[i + 1][(j + 1) % segs], rings[i + 1][j]))
    cap = mesh_object("Bandana_cap", bm, loc=HEAD_CB)
    common.uv_box(cap, 4.0)
    common.assign(cap, MAT["Shirt"])
    sol = cap.modifiers.new("Solidify", 'SOLIDIFY')
    sol.thickness = 0.008
    sol.offset = 1.0
    apply_mods(cap)
    # валик по краю — труба вдоль границы колпака
    tube_r, tube_n = 0.018, 6
    bm = bmesh.new()
    loops = []
    for j in range(segs):
        ph = TAU * j / segs
        c0 = sph(R + 0.003, th_max(ph), ph)
        c1 = sph(R + 0.003, th_max(ph + 0.01), ph + 0.01)
        tng = (c1 - c0).normalized()
        nrm = c0.normalized()
        bin_ = tng.cross(nrm).normalized()
        loops.append([bm.verts.new(c0 + (nrm * math.cos(TAU * k / tube_n) + bin_ * math.sin(TAU * k / tube_n)) * tube_r) for k in range(tube_n)])
    for j in range(segs):
        a, b = loops[j], loops[(j + 1) % segs]
        for k in range(tube_n):
            bm.faces.new((a[k], b[k], b[(k + 1) % tube_n], a[(k + 1) % tube_n]))
    rim = mesh_object("Bandana_rim", bm, loc=HEAD_CB)
    common.uv_box(rim, 4.0)
    common.assign(rim, MAT["Shirt"])
    # узел сзади-справа (−X, +Y Blender) и два хвоста
    kd = Vector((-0.55, 0.72, 0.42)).normalized()
    kpos = HEAD_CB + kd * (R + 0.014)
    knot = common.add_sphere("Bandana_knot", 0.032, loc=kpos, segments=12, rings=6, scale=(1.0, 0.85, 0.8))
    common.uv_box(knot, 4.0)
    common.assign(knot, MAT["Shirt"])
    tails = []
    for i, (L, side) in enumerate(((0.26, -1.0), (0.20, 1.0))):
        def tail(u, v, L=L, side=side):
            wdt = 0.06 * (1.0 - 0.7 * v)
            along = Vector((-0.25 + 0.15 * side, 0.45, -1.0)).normalized()
            across = Vector((0.75, 0.55 * side, 0.0)).normalized()
            p = kpos + along * (L * v) + across * ((u - 0.5) * wdt + 0.03 * side)
            p += Vector((0.02 * math.sin(7.0 * v + i), 0.03 * math.sin(5.0 * v), 0.0)) * v
            return p
        tails.append(cloth_strip("Bandana_tail%d" % i, tail, 2, 8, thickness=0.005))
    b = common.join([cap, rim, knot] + tails, "Bandana")
    common.smooth(b, SMOOTH_DEG)
    return b


def head():
    neck = B(0, SHOULDER_Y, 0)
    parts = [ball("Head_ball", neck, BALL["neck"])]
    stub = lathe("Head_neck", rounded_profile(0.056, 0.060, -0.04, 0.04, 0.008, swell=0.0), verts=20, loc=neck + Vector((0, 0, 0.05)))
    common.uv_cylinder_along(stub, 'Z', 0.5, around=0.25, centre=(0.0, 0.0))
    common.assign(stub, MAT["WoodWarm"])
    parts.append(stub)
    sphere = common.add_sphere("Head_sphere", HEAD_R, loc=HEAD_CB, segments=32, rings=16)
    common.uv_cylinder_along(sphere, 'Z', 0.35, around=0.5, centre=(0.0, 0.0))
    common.assign(sphere, MAT["Wood"])
    parts.append(sphere)
    fp = face_plate()
    bd = bandana()
    h = assemble("Head", parts, neck)
    for child in (fp, bd):
        common.set_origin(child, neck)
        common.parent(child, h)
    return h, fp, bd


# ------------------------------------------------------------------------------------------------
def build():
    common.reset_scene()
    MAT.update(make_materials())
    h, fp, bd = head()
    t, sc = torso()
    parts = [h, t]
    for s, k in (("L", 1.0), ("R", -1.0)):
        sx, hx = SX * k, HX * k
        parts.append(limb("UpperArm_" + s, sx, SHOULDER_Y, ELBOW_Y, ARM_R, ARM_R - 0.005, "shoulder", "elbow", "Wood"))
        parts.append(limb("LowerArm_" + s, sx, ELBOW_Y, WRIST_Y, ARM_R - 0.004, ARM_R - 0.010, "elbow", "wrist", "WoodWarm"))
        parts.append(hand("Hand_" + s, k))
        parts.append(limb("UpperLeg_" + s, hx, HIP_Y, KNEE_Y, LEG_R, LEG_R - 0.006, "hip", "knee", "Wood"))
        parts.append(limb("LowerLeg_" + s, hx, KNEE_Y, ANKLE_Y, LEG_R - 0.005, LEG_R - 0.012, "knee", "ankle", "WoodWarm"))
        parts.append(foot("Foot_" + s, k))
    return parts, [fp, bd, sc]


def export_all(parts):
    os.makedirs(OUT_DIR, exist_ok=True)
    rest = {p.name: p.location.copy() for p in parts}
    for p in parts:
        p.location = (0.0, 0.0, 0.0)          # узел в нуле, меш относительно сустава; дети (FacePlate, Bandana, Scarf) едут следом
        common.export_glb(os.path.join(OUT_DIR, p.name + ".glb"), [p])
        p.location = rest[p.name]
    common.export_glb(os.path.join(OUT_DIR, "wooden.glb"), parts)


if __name__ == "__main__":
    parts, children = build()
    st = common.stats()
    per = {o.name: sum(len(pg.vertices) - 2 for pg in o.data.polygons) for o in bpy.context.scene.objects if o.type == 'MESH'}
    print("TRIS per part:", per)
    print("STATS:", st)
    if st["tris"] > TRI_BUDGET:
        print("ERROR: over budget (%d tris)" % TRI_BUDGET)
        sys.exit(2)
    export_all(parts)
    print("PARTS:", sorted(p.name for p in parts), "children:", [(c.name, c.parent.name) for c in children])
    print("DONE")
