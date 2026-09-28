"""Манекен героя по R14 (docs/refs/R14-a-character-base.jpg) — настоящие меши, headless Blender 4.5.

Запуск:
    /Applications/Blender.app/Contents/MacOS/Blender -b --python godot/tools/blender/mannequin.py

Пишет:
    godot/assets/models/heroes/mannequin/<Part>.glb   — одна часть, узел в нуле, вершины относительно
                                                        проксимального сустава (origin части = сустав);
    godot/assets/models/heroes/mannequin/mannequin.glb — все 14 частей + FacePlate в позе покоя.

Числа рига — те же, что в scenes/doll/doll.gd (D, HIP_Y, SHOULDER_Y) и tools/build_doll_scene.gd:
рост 1.9 м, бёдра y=0.91, плечи y=1.41, плечи x=±0.24, бёдра x=±0.10. Origin части — её проксимальный
сустав (Head → шея, UpperArm → плечо, LowerArm → локоть, Hand → запястье, UpperLeg → бедро,
LowerLeg → колено, Foot → лодыжка); у Torso (нет родительского сустава) origin — центр торса
(0, HIP_Y + torso_h/2, 0). Шарик сустава (материал Joint) принадлежит ДИСТАЛЬНОЙ части, сидит в её origin.

Оси: описываем всё в координатах Godot (X вбок, +X = левая сторона куклы, Y вверх, +Z к камере) и
переводим в Blender (X, -Z, Y): лицо в -Y Blender → +Z Godot после экспорта с Y вверх.

Материалы (Principled, без текстур): Paint — тёплый светло-серый корпус, Trim — манжеты/воротники,
Joint — тёмный металл шарниров, Shirt — полоса на груди (перекрашивается в цвет игрока в Godot),
Face — передняя плашка головы (под фото игрока, планарные UV 0..1), Sole — подошва.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import common  # noqa: E402

GODOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT_DIR = os.path.join(GODOT, "assets", "models", "heroes", "mannequin")

# --- риг (метры, координаты Godot) = scenes/doll/doll.gd -----------------------------------------
HEAD_R = 0.225
TORSO_H, TORSO_W, TORSO_D = 0.50, 0.36, 0.22
UA, LA, HAND = 0.32, 0.30, 0.14
UL, LL, FOOT, FOOT_H = 0.42, 0.40, 0.26, 0.09
ARM_R, LEG_R, NECK = 0.055, 0.07, 0.03
SX, HX = 0.24, 0.10
HIP_Y = UL + LL + FOOT_H              # 0.91
SHOULDER_Y = HIP_Y + TORSO_H          # 1.41
ELBOW_Y = SHOULDER_Y - UA             # 1.09
WRIST_Y = ELBOW_Y - LA                # 0.79
KNEE_Y = HIP_Y - UL                   # 0.49
ANKLE_Y = FOOT_H                      # 0.09
HEAD_C = SHOULDER_Y + NECK + HEAD_R   # 1.665 — центр коллизии; визуальный овал чуть выше
TORSO_C = HIP_Y + TORSO_H / 2.0       # 1.16

# радиусы шариков суставов
BALL = {"neck": 0.060, "shoulder": 0.075, "elbow": 0.060, "wrist": 0.045,
        "hip": 0.085, "knee": 0.070, "ankle": 0.058}

SMOOTH_DEG = 55.0   # фаски 3 сегмента дают шаги 30°, порог выше — всё гладкое, кроме реальных углов


def B(x, y, z):
    """Godot (x, y_up, z_front) → Blender (x, -z, y)."""
    return Vector((x, -z, y))


# ------------------------------------------------------------------------------------------------
# материалы
# ------------------------------------------------------------------------------------------------
def srgb(r, g, b):
    """Цвет задан как на экране (sRGB, как пипеткой с R14); Principled/glTF хранят линейный."""
    return tuple(((c + 0.055) / 1.055) ** 2.4 if c > 0.04045 else c / 12.92 for c in (r, g, b)) + (1.0,)


def make_materials():
    return {
        "Paint": common.material("Paint", srgb(0.83, 0.80, 0.76), rough=0.55, metal=0.0),   # тёплый светло-серый корпус
        "Trim": common.material("Trim", srgb(0.56, 0.53, 0.50), rough=0.60, metal=0.10),    # манжеты/воротники
        "Joint": common.material("Joint", (0.12, 0.12, 0.13, 1.0), rough=0.35, metal=0.8),  # тёмный металл шарниров
        "Shirt": common.material("Shirt", (0.18, 0.44, 0.87, 1.0), rough=0.60, metal=0.0),  # перекрашивается в Godot
        "Face": common.material("Face", srgb(0.90, 0.82, 0.74), rough=0.50, metal=0.0),     # плашка под фото
        "Sole": common.material("Sole", srgb(0.30, 0.28, 0.26), rough=0.90, metal=0.0),
    }


MAT = {}


# ------------------------------------------------------------------------------------------------
# геометрические хелперы (всё в мировых координатах Blender)
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


def finish(obj, mat, bevel_w=0.0, seg=3, sub=0):
    """Материал + фаска + subsurf, модификаторы применяются сразу (join их не сохраняет)."""
    common.assign(obj, MAT[mat])
    if bevel_w > 0.0:
        common.bevel(obj, bevel_w, seg)
    if sub > 0:
        common.subsurf(obj, sub)
    apply_mods(obj)
    return obj


def ball(name, pos, r, mat="Joint"):
    o = common.add_sphere(name, r, loc=pos, segments=20, rings=10)
    common.assign(o, MAT[mat])
    return o


def cyl_between(name, p0, p1, r0, r1=None, verts=24):
    """Цилиндр/усечённый конус от p0 (радиус r0) к p1 (радиус r1); ось Z объекта смотрит вдоль p0→p1."""
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    if r1 is None:
        r1 = r0
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r0, radius2=r1, depth=d.length,
                                    location=(p0 + p1) / 2.0)
    o = bpy.context.active_object
    o.name = name
    o.rotation_euler = d.to_track_quat('Z', 'Y').to_euler()
    common.apply_transforms(o, rotation=True, scale=True)
    return o


def box(name, center, size):
    return common.add_cube(name, size=size, loc=center)


def tapered_box(name, z_top, w_top, d_top, z_bot, w_bot, d_bot, x=0.0, y=0.0):
    """Блок по Z: сверху (w_top × d_top), снизу (w_bot × d_bot); центр по X/Y в (x, y)."""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x, y, (z_top + z_bot) / 2.0))
    o = bpy.context.active_object
    o.name = name
    for v in o.data.vertices:
        top = v.co.z > 0.0
        w = w_top if top else w_bot
        d = d_top if top else d_bot
        v.co = Vector((math.copysign(w / 2.0, v.co.x), math.copysign(d / 2.0, v.co.y),
                       (z_top if top else z_bot) - (z_top + z_bot) / 2.0))
    return o


def cuff(name, center, axis, r, h=0.028):
    """Кольцо-манжета вокруг конца сегмента: короткий цилиндр чуть шире сегмента."""
    a = Vector(axis).normalized()
    c = Vector(center)
    o = cyl_between(name, c - a * (h / 2.0), c + a * (h / 2.0), r, r)
    return finish(o, "Trim", bevel_w=0.006, seg=2)


def assemble(name, objs, origin, smooth_deg=SMOOTH_DEG):
    j = common.join(objs, name)
    common.smooth(j, smooth_deg)
    common.set_origin(j, origin)
    return j


# ------------------------------------------------------------------------------------------------
# сегмент конечности: конус (шире у проксимального конца) + манжеты + шарик проксимального сустава
# ------------------------------------------------------------------------------------------------
def limb(name, x, y_top, y_bot, r_top, r_bot, ball_top, ball_bot):
    gap_t = ball_top * 0.42          # верх сегмента прячется в шарике сустава
    gap_b = ball_bot * 0.42          # низ — в шарике следующего сустава (принадлежит следующей части)
    top = B(x, y_top - gap_t, 0.0)
    bot = B(x, y_bot + gap_b, 0.0)
    seg = cyl_between(name + "_seg", top, bot, r_top, r_bot)
    seg = finish(seg, "Paint", bevel_w=0.010, seg=3)
    axis = (top - bot).normalized()
    c_top = cuff(name + "_cuffT", top - axis * 0.018, axis, r_top + 0.009)
    c_bot = cuff(name + "_cuffB", bot + axis * 0.018, axis, r_bot + 0.009)
    b = ball(name + "_ball", B(x, y_top, 0.0), ball_top)
    return assemble(name, [seg, c_top, c_bot, b], B(x, y_top, 0.0))


# ------------------------------------------------------------------------------------------------
# кисть: шарик запястья + шейка + ладонь + 4 пальца + большой палец; ладонь смотрит в камеру
# ------------------------------------------------------------------------------------------------
def hand(name, k):
    x = SX * k
    wr = WRIST_Y
    parts = [ball(name + "_ball", B(x, wr, 0.0), BALL["wrist"])]
    neck = cyl_between(name + "_neck", B(x, wr - 0.02, 0.0), B(x, wr - 0.052, 0.0), 0.030, 0.030)
    parts.append(finish(neck, "Trim", bevel_w=0.004, seg=2))
    palm_top = wr - 0.045
    palm_h = 0.084
    palm_w = 0.090
    palm = tapered_box(name + "_palm", palm_top, palm_w * 0.90, 0.036, palm_top - palm_h, palm_w, 0.038, x=x)
    parts.append(finish(palm, "Paint", bevel_w=0.012, seg=3, sub=1))
    base_y = palm_top - palm_h + 0.006
    curl = math.radians(14.0)        # пальцы слегка согнуты к ладони (к камере)
    lengths = [0.050, 0.056, 0.052, 0.042]
    offsets = [-0.0335, -0.0112, 0.0112, 0.0335]
    for i, (L, dx) in enumerate(zip(lengths, offsets)):
        p0 = B(x + dx, base_y, 0.0)
        d = Vector((0.0, -math.sin(curl), -math.cos(curl)))   # вниз и чуть к камере (-Y Blender)
        f = cyl_between("%s_f%d" % (name, i), p0, p0 + d * L, 0.0106, 0.0088, verts=12)
        parts.append(finish(f, "Paint", bevel_w=0.003, seg=2))
        kn = common.add_sphere("%s_k%d" % (name, i), 0.011, loc=p0 + d * 0.004, segments=12, rings=6)
        common.assign(kn, MAT["Paint"])
        parts.append(kn)
    # большой палец с внешней стороны ладони (ладонь к камере → большой палец латерально = +X·k)
    t0 = B(x + k * (palm_w / 2.0 - 0.004), palm_top - 0.028, 0.006)
    td = Vector((k * math.sin(math.radians(38.0)), -0.25, -math.cos(math.radians(38.0)))).normalized()
    th = cyl_between(name + "_thumb", t0, t0 + td * 0.048, 0.0122, 0.0098, verts=12)
    parts.append(finish(th, "Paint", bevel_w=0.003, seg=2))
    tk = common.add_sphere(name + "_tk", 0.012, loc=t0 + td * 0.004, segments=12, rings=6)
    common.assign(tk, MAT["Paint"])
    parts.append(tk)
    return assemble(name, parts, B(x, wr, 0.0))


# ------------------------------------------------------------------------------------------------
# стопа: ботинок (скруглённый клин носком к камере) + подошва + воротник + шарик лодыжки
# ------------------------------------------------------------------------------------------------
def foot(name, k):
    x = HX * k
    ankle = B(x, ANKLE_Y, 0.0)
    w = LEG_R * 2.2                 # 0.154
    # центр как у коллизии: (x, FOOT_H/2, FOOT*0.15); в Blender y = -z_godot
    cz = FOOT * 0.15
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x, -cz, FOOT_H / 2.0))
    shoe = bpy.context.active_object
    shoe.name = name + "_shoe"
    for v in shoe.data.vertices:
        front = v.co.y < 0.0        # -Y Blender = к камере = носок
        top = v.co.z > 0.0
        vx = math.copysign(w / 2.0, v.co.x)
        vy = -FOOT / 2.0 if front else FOOT / 2.0
        vz = FOOT_H / 2.0 if top else -FOOT_H / 2.0
        if front:
            vx *= 0.86              # носок уже
            if top:
                vz -= 0.026         # и ниже — клин ботинка
        else:
            vy -= 0.02              # пятка чуть длиннее
        v.co = Vector((vx, vy, vz))
    shoe = finish(shoe, "Paint", bevel_w=0.028, seg=3, sub=1)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x, -cz, 0.007))
    sole = bpy.context.active_object
    sole.name = name + "_sole"
    for v in sole.data.vertices:
        front = v.co.y < 0.0
        vx = math.copysign(w / 2.0 + 0.003, v.co.x) * (0.88 if front else 1.0)
        vy = (-FOOT / 2.0 - 0.004) if front else (FOOT / 2.0 + 0.024)
        vz = 0.007 if v.co.z > 0.0 else -0.007
        v.co = Vector((vx, vy, vz))
    sole = finish(sole, "Sole", bevel_w=0.005, seg=2)
    collar = cyl_between(name + "_collar", ankle + Vector((0, 0, -0.03)), ankle + Vector((0, 0, 0.006)),
                         BALL["ankle"] - 0.006, BALL["ankle"] - 0.004)
    collar = finish(collar, "Trim", bevel_w=0.005, seg=2)
    b = ball(name + "_ball", ankle, BALL["ankle"])
    return assemble(name, [shoe, sole, collar, b], ankle)


# ------------------------------------------------------------------------------------------------
# торс: грудной блок (шире в плечах) + полоса Shirt + тёмная талия + тазовый блок
# ------------------------------------------------------------------------------------------------
def torso():
    chest_top, chest_bot = SHOULDER_Y, TORSO_C - 0.02          # 1.41 .. 1.14
    cw_top, cd_top, cw_bot, cd_bot = 0.40, TORSO_D, 0.30, 0.19
    chest = tapered_box("Torso_chest", chest_top, cw_top, cd_top, chest_bot, cw_bot, cd_bot)
    chest = finish(chest, "Paint", bevel_w=0.035, seg=3, sub=1)

    def lerp_w(z, a, b):
        t = (z - chest_bot) / (chest_top - chest_bot)
        return a + (b - a) * t

    bz_top, bz_bot = chest_bot + 0.13, chest_bot + 0.008
    band = tapered_box("Torso_band", bz_top, lerp_w(bz_top, cw_bot, cw_top) * 1.045, lerp_w(bz_top, cd_bot, cd_top) * 1.045,
                       bz_bot, lerp_w(bz_bot, cw_bot, cw_top) * 1.045, lerp_w(bz_bot, cd_bot, cd_top) * 1.045)
    band = finish(band, "Shirt", bevel_w=0.018, seg=3, sub=1)

    waist = cyl_between("Torso_waist", B(0, chest_bot - 0.065, 0), B(0, chest_bot + 0.015, 0), 0.088, 0.088)
    waist = finish(waist, "Joint", bevel_w=0.008, seg=2)

    pel_top, pel_bot = chest_bot - 0.045, HIP_Y - 0.005        # 1.095 .. 0.905
    pelvis = tapered_box("Torso_pelvis", pel_top, 0.31, 0.20, pel_bot, 0.30, 0.185)
    pelvis = finish(pelvis, "Paint", bevel_w=0.03, seg=3, sub=1)
    return assemble("Torso", [chest, band, waist, pelvis], B(0, TORSO_C, 0))


# ------------------------------------------------------------------------------------------------
# голова: шарик шеи + шейка + овал-яйцо (0.45 × 0.52) + FacePlate (отдельный объект, дочерний)
# ------------------------------------------------------------------------------------------------
def egg_point(n, rx, rz):
    """Точка овала головы по единичному направлению n: сфера (rx, rx, rz), сужение к подбородку."""
    p = Vector((n.x * rx, n.y * rx, n.z * rz))
    t = (p.z / rz + 1.0) / 2.0              # 0 подбородок .. 1 макушка
    f = 1.0 - 0.24 * (1.0 - t) ** 2         # яйцо: уже к подбородку
    return Vector((p.x * f, p.y * f, p.z))


def face_plate(hc, rx, rz):
    """Колпак-плашка на передней (−Y) части головы: ровная круглая граница, чуть выпуклее овала, с ободком.
    UV — планарные 0..1 (X → U, Z → V) под фото игрока."""
    axis = Vector((0.0, -1.0, -0.10)).normalized()       # чуть ниже центра — где лицо
    u = Vector((1.0, 0.0, 0.0))
    w = axis.cross(u).normalized()
    u = w.cross(axis).normalized()
    rings_n, segs = 7, 40
    th_max = math.radians(36.0)
    bm = bmesh.new()
    rings = [[bm.verts.new(egg_point(axis, rx, rz) * 1.022)]]
    for i in range(1, rings_n + 1):
        th = th_max * i / rings_n
        ring = []
        for j in range(segs):
            ph = 2.0 * math.pi * j / segs
            n = math.cos(th) * axis + math.sin(th) * (math.cos(ph) * u + math.sin(ph) * w)
            ring.append(bm.verts.new(egg_point(n, rx, rz) * 1.022))
        rings.append(ring)
    c = rings[0][0]
    for j in range(segs):
        bm.faces.new((c, rings[1][j], rings[1][(j + 1) % segs]))
    for i in range(1, rings_n):
        for j in range(segs):
            bm.faces.new((rings[i][j], rings[i][(j + 1) % segs], rings[i + 1][(j + 1) % segs], rings[i + 1][j]))
    # согласованная обмотка (веер у полюса и квады строятся в разном порядке) и нормали наружу вдоль axis
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.normal_update()
    if sum(f.normal.dot(axis) for f in bm.faces) < 0.0:
        bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
        bm.normal_update()
    uv = bm.loops.layers.uv.verify()
    xs = [v.co.x for v in bm.verts]
    zs = [v.co.z for v in bm.verts]
    x0, x1, z0, z1 = min(xs), max(xs), min(zs), max(zs)
    for f in bm.faces:
        for l in f.loops:
            l[uv].uv = ((l.vert.co.x - x0) / (x1 - x0), (l.vert.co.z - z0) / (z1 - z0))
    mesh = bpy.data.meshes.new("FacePlate")
    bm.to_mesh(mesh)
    bm.free()
    fp = bpy.data.objects.new("FacePlate", mesh)
    bpy.context.scene.collection.objects.link(fp)
    fp.location = hc
    common.assign(fp, MAT["Face"])
    sol = fp.modifiers.new("Solidify", 'SOLIDIFY')
    sol.thickness = 0.009
    sol.offset = -1.0
    sol.use_rim = True
    apply_mods(fp)
    common.smooth(fp, SMOOTH_DEG)
    return fp


def head():
    neck = B(0, SHOULDER_Y, 0)
    b = ball("Head_ball", neck, BALL["neck"])
    stub = cyl_between("Head_neck", neck + Vector((0, 0, 0.012)), neck + Vector((0, 0, 0.075)), 0.046, 0.042)
    stub = finish(stub, "Paint", bevel_w=0.006, seg=2)
    rx, rz = HEAD_R, 0.26                      # 0.45 в ширину, 0.52 в высоту
    hc = B(0, SHOULDER_Y + 0.03 + rz, 0)       # низ овала на 0.03 выше шеи → виден шарик и шейка
    egg = common.add_sphere("Head_egg", 1.0, loc=hc, segments=32, rings=16, scale=(rx, rx, rz))
    for v in egg.data.vertices:
        n = Vector((v.co.x / rx, v.co.y / rx, v.co.z / rz))
        v.co = egg_point(n, rx, rz)
    common.assign(egg, MAT["Paint"])
    fp = face_plate(hc, rx, rz)
    common.set_origin(fp, neck)
    h = assemble("Head", [b, stub, egg], neck)
    common.parent(fp, h)
    return h, fp


# ------------------------------------------------------------------------------------------------
def build():
    common.reset_scene()
    MAT.update(make_materials())
    parts = []
    h, fp = head()
    parts += [h, torso()]
    for s, k in (("L", 1.0), ("R", -1.0)):
        sx, hx = SX * k, HX * k
        parts.append(limb("UpperArm_" + s, sx, SHOULDER_Y, ELBOW_Y, ARM_R + 0.008, ARM_R - 0.004,
                          BALL["shoulder"], BALL["elbow"]))
        parts.append(limb("LowerArm_" + s, sx, ELBOW_Y, WRIST_Y, ARM_R - 0.002, ARM_R - 0.012,
                          BALL["elbow"], BALL["wrist"]))
        parts.append(hand("Hand_" + s, k))
        parts.append(limb("UpperLeg_" + s, hx, HIP_Y, KNEE_Y, LEG_R + 0.010, LEG_R - 0.004,
                          BALL["hip"], BALL["knee"]))
        parts.append(limb("LowerLeg_" + s, hx, KNEE_Y, ANKLE_Y, LEG_R - 0.003, LEG_R - 0.014,
                          BALL["knee"], BALL["ankle"]))
        parts.append(foot("Foot_" + s, k))
    return parts, fp


def export_all(parts):
    os.makedirs(OUT_DIR, exist_ok=True)
    rest = {p.name: p.location.copy() for p in parts}
    for p in parts:
        p.location = (0.0, 0.0, 0.0)          # узел в нуле, меш относительно сустава; дети (FacePlate) едут следом
        common.export_glb(os.path.join(OUT_DIR, p.name + ".glb"), [p])
        p.location = rest[p.name]
    common.export_glb(os.path.join(OUT_DIR, "mannequin.glb"), parts)


if __name__ == "__main__":
    parts, fp = build()
    st = common.stats()
    per = {o.name: sum(len(pg.vertices) - 2 for pg in o.data.polygons) for o in bpy.context.scene.objects if o.type == 'MESH'}
    print("TRIS per part:", per)
    print("STATS:", st)
    if st["tris"] > 25000:
        print("ERROR: over budget (25k tris)")
        sys.exit(2)
    export_all(parts)
    names = sorted(p.name for p in parts)
    print("PARTS:", names, "child of Head:", [c.name for c in parts[0].children])
    print("DONE")
