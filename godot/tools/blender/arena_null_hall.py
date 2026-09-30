"""Арена 01 «Old NULL Hall» — модульный кит по листу автора (30.09.2026; описание — docs/plan-demo/ART_NULL.md, лист 5).

Запуск (Blender 4.5 LTS):
  blender -b --python arena_null_hall.py -- --export                  → assets/models/arena/null_hall/<Модуль>.glb
  blender -b --python arena_null_hall.py -- --sheet out.png            → лист-каталог модулей (Cycles + подписи PIL)
  blender -b --python arena_null_hall.py -- --preview out.png Stand_Segment Catwalk …

Координаты Godot (craft_parts.G2B): X вбок, Y вверх, +Z к камере. Бой идёт в плоскости z = 0, кит стоит позади и вокруг неё,
«лицо» модулей смотрит в +Z. Origin модуля — центр основания (y = 0), если в описании модуля не сказано иначе.
Размеры — метры; кукла ~1.8 м, по листу камеры боец занимает 8–12 % высоты кадра, значит в кадре ~15–22 м по вертикали.

Материалы по ролям (в glb плоские, имя = роль; настоящие ставит Godot, tools/build_null_hall.gd):
  Hall_Steel (крашеная сталь конструкций), Hall_SteelDark (фермы, рамы), Hall_Plate (настил, бетон), Hall_Yellow (перила,
  предупреждающая краска), Hall_Seat (сиденья), Hall_Crowd (зрители; цвет — у экземпляра MultiMesh), Hall_ClothRed,
  Hall_ClothBlue (баннеры), Hall_PrintWhite, Hall_PrintDark (печать и надписи), Hall_LightWarm (оранжевые световые полосы),
  Hall_LightCool (прожекторы), Hall_Screen (экраны; UV 0..1 на всю поверхность — Godot кладёт туда ViewportTexture),
  Hall_NullGlow (поле NULL: кольца эмиттеров), Hall_Rubber (кабели, шины), Hall_Glass (объективы).
"""
import json
import math
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
try:
    import bmesh
    import bpy
    from mathutils import Matrix, Vector
except ImportError:   # системный python3: только --compose (Pillow)
    bpy = None
if bpy is not None:
    import common as C  # noqa: E402
    import craft_parts as K  # noqa: E402
    from craft_parts import G2B, T, Rz, Rx, S, align_y, revolve, sphere, sweep, extrude2d, box, fin  # noqa: E402,F401

GODOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(GODOT, "assets", "models", "arena", "null_hall")
TRI_BUDGET = 3000
TRI_BUDGET_BIG = {"Stand_Segment": 4000, "Fighter_Gate": 4000, "Null_Emitter": 4000, "Light_Rig": 4000}
TRI_BUDGET_CROWD = 300
RNG = random.Random(101)

GLOW_NULL = (0.25, 0.62, 1.0)
WARM = (1.0, 0.52, 0.16)


# ----------------------------------------------------------------------------------------------------------------------
# материалы
# ----------------------------------------------------------------------------------------------------------------------
def setup_materials(export=False):
    K.MAT_DEFS.update({
        "Hall_Steel": ("paint_marks", {"tint": (0.085, 0.09, 0.105, 1.0), "roughness_scale": 0.75, "metallic": 0.35},
                       ((0.07, 0.074, 0.085, 1.0), 0.55), 1.0),
        "Hall_Plate": ("stone", {"tint": (0.42, 0.42, 0.45, 1.0)}, ((0.12, 0.12, 0.13, 1.0), 0.85), 0.5),
        "Hall_Yellow": ("paint_marks", {"tint": (1.0, 0.52, 0.02, 1.0), "roughness_scale": 0.8}, ((0.82, 0.42, 0.02, 1.0), 0.5), 2.0),
        "Hall_ClothRed": ("fabric_red", {}, ((0.42, 0.03, 0.03, 1.0), 0.85), 1.0),
        "Hall_ClothBlue": ("fabric_blue", {}, ((0.03, 0.08, 0.3, 1.0), 0.85), 1.0),
    })
    K.FLAT.update({
        "Hall_SteelDark": ((0.028, 0.029, 0.033, 1.0), 0.45, 0.6),
        "Hall_Seat": ((0.05, 0.07, 0.12, 1.0), 0.6, 0.0),
        "Hall_Crowd": ((0.30, 0.26, 0.22, 1.0), 0.7, 0.0),
        "Hall_PrintWhite": ((0.80, 0.80, 0.78, 1.0), 0.6, 0.0),
        "Hall_PrintDark": ((0.035, 0.036, 0.04, 1.0), 0.7, 0.0),
        "Hall_Rubber": ((0.02, 0.02, 0.02, 1.0), 0.8, 0.0),
        "Hall_Membrane": ((0.2, 0.45, 0.9, 1.0), 0.2, 0.0),
    })
    K.FORCE_FLAT = export
    k = 0.0 if export else 1.0
    K._MATS["Hall_LightWarm"] = C.material("Hall_LightWarm", (0.9, 0.5, 0.2, 1.0), 0.3, 0.0, emission=WARM + (1.0,),
                                           emission_strength=1.0 + 7.0 * k)
    K._MATS["Hall_LightCool"] = C.material("Hall_LightCool", (0.9, 0.92, 1.0, 1.0), 0.2, 0.0, emission=(1.0, 0.95, 0.88, 1.0),
                                           emission_strength=1.0 + 9.0 * k)
    K._MATS["Hall_Screen"] = C.material("Hall_Screen", (0.01, 0.02, 0.05, 1.0), 0.15, 0.0, emission=(0.05, 0.25, 0.8, 1.0),
                                        emission_strength=0.2 + 1.5 * k)
    K._MATS["Hall_NullGlow"] = C.material("Hall_NullGlow", (0.1, 0.3, 0.6, 1.0), 0.2, 0.0, emission=GLOW_NULL + (1.0,),
                                          emission_strength=1.0 + 3.0 * k)
    K._MATS["Hall_Glass"] = C.material("Hall_Glass", (0.02, 0.03, 0.05, 1.0), 0.05, 0.0)


# ----------------------------------------------------------------------------------------------------------------------
# хелперы
# ----------------------------------------------------------------------------------------------------------------------
def tube(name, a, b, r, mat, sides=8):
    return sweep(name, [Vector(a), Vector(b)], r, mat, sides=sides)


def truss(name, a, b, w, mat, bays, chord=0.04, diag=0.022, up=(0.0, 1.0, 0.0), faces=(0, 1, 2, 3), sides=6):
    """Квадратная ферма от a до b шириной w: 4 пояса и зигзаг раскосов на гранях faces (0 верх, 1 перед, 2 низ, 3 зад)."""
    a, b = Vector(a), Vector(b)
    d = (b - a).normalized()
    u = Vector(up)
    if abs(d.dot(u)) > 0.9:
        u = Vector((0.0, 0.0, 1.0))
    s = d.cross(u).normalized()
    u = s.cross(d).normalized()
    h = w * 0.5
    corners = [u * h + s * h, u * h - s * h, -u * h - s * h, -u * h + s * h]
    objs = [tube("%s_C%d" % (name, i), a + c, b + c, chord, mat, sides) for i, c in enumerate(corners)]
    pairs = {0: (0, 1), 1: (1, 2), 2: (2, 3), 3: (3, 0)}
    for f in faces:
        c0, c1 = corners[pairs[f][0]], corners[pairs[f][1]]
        for k in range(bays):
            p0 = a.lerp(b, k / bays)
            p1 = a.lerp(b, (k + 1) / bays)
            if k % 2 == 0:
                objs.append(tube("%s_D%d_%d" % (name, f, k), p0 + c0, p1 + c1, diag, mat, 4))
            else:
                objs.append(tube("%s_D%d_%d" % (name, f, k), p0 + c1, p1 + c0, diag, mat, 4))
    return objs


def railing(name, x0, x1, y, z, mat="Hall_Yellow", h=1.05, post_step=1.0, r=0.028):
    """Перила вдоль X: стойки, поручень, средний пояс."""
    objs = []
    n = max(1, int(round((x1 - x0) / post_step)))
    for i in range(n + 1):
        x = x0 + (x1 - x0) * i / n
        objs.append(tube("%s_P%d" % (name, i), (x, y, z), (x, y + h, z), r, mat))
    objs.append(tube(name + "_Top", (x0, y + h, z), (x1, y + h, z), r * 1.15, mat))
    objs.append(tube(name + "_Mid", (x0, y + h * 0.5, z), (x1, y + h * 0.5, z), r * 0.8, mat))
    return objs


def text_bm(body, size, depth=0.01):
    """Текст шрифтом Blender по умолчанию → bmesh в плоскости XY (по центру), толщина по Z, лицо +Z."""
    cu = bpy.data.curves.new("txt", 'FONT')
    cu.body = body
    cu.size = size
    cu.extrude = depth * 0.5
    cu.resolution_u = 3
    cu.align_x = 'CENTER'
    cu.align_y = 'CENTER'
    ob = bpy.data.objects.new("txt", cu)
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.update()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    bpy.data.objects.remove(ob, do_unlink=True)
    bm = bmesh.new()
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)
    return bm


def text_obj(name, body, size, mat, xf, depth=0.01, bold=0.0):
    bm = text_bm(body, size, depth)
    if bold > 0:
        bmesh.ops.scale(bm, vec=Vector((1.0 + bold, 1.0, 1.0)), verts=bm.verts)
    return K._obj(name, bm, mat, xf)


def poly_obj(name, pts, depth, mat, xf):
    return extrude2d(name, pts, -depth * 0.5, depth * 0.5, mat, xf=xf)


def ngon(cx, cy, r, n, phase=0.0):
    return [(cx + r * math.cos(phase + 2 * math.pi * i / n), cy + r * math.sin(phase + 2 * math.pi * i / n)) for i in range(n)]


def light_strip(name, a, b, w, t, mat="Hall_LightWarm", normal=(0, 0, 1)):
    """Световая полоса: тонкий брусок от a до b шириной w (по нормали — толщина t)."""
    a, b = Vector(a), Vector(b)
    d = b - a
    n = Vector(normal).normalized()
    s = d.normalized().cross(n)
    m = Matrix.Identity(4)
    m.col[0][:3] = s * w
    m.col[1][:3] = d
    m.col[2][:3] = n * t
    m.translation = (a + b) * 0.5
    return box(name, (1.0, 1.0, 1.0), mat, xf=m)


def done(objs, bevel=0.0):
    """Отделка списка: фаска на брусках и гладкость; возвращает список."""
    out = []
    for o in objs:
        out.append(fin(o, bevel, 1, angle=40.0) if bevel > 0 else fin(o, 0.0, angle=40.0))
    return out


# ----------------------------------------------------------------------------------------------------------------------
# модули (каждая функция → список объектов; имя модуля = имя glb)
# ----------------------------------------------------------------------------------------------------------------------
def build_Stand_Segment():
    """Секция трибуны 6 м: 5 рядов ступенями назад (−Z) и вверх, сиденья, борт с перилами и световой полосой.
    Передний край — z = 0, задний — z = −4.5; зрителей ставит Godot (MultiMesh по Marker'ам рядов: Row_<i>)."""
    W, rows, step_d, step_h = 6.0, 5, 0.9, 0.5
    objs = []
    seats = []
    for i in range(rows):
        z0 = -i * step_d
        y0 = 0.9 + i * step_h
        objs.append(box("Step_%d" % i, (W, 0.12, step_d), "Hall_Plate", (0.0, y0 - 0.06, z0 - step_d * 0.5)))
        objs.append(box("Riser_%d" % i, (W, step_h, 0.08), "Hall_Steel", (0.0, y0 - step_h * 0.5 - 0.12, z0 - 0.04)))
        for s in range(10):
            x = -W * 0.5 + 0.3 + s * 0.6
            seats.append(box("Seat_%d_%d" % (i, s), (0.46, 0.1, 0.4), "Hall_Seat", (x, y0 + 0.36, z0 - step_d * 0.55)))
            seats.append(box("Back_%d_%d" % (i, s), (0.46, 0.42, 0.06), "Hall_Seat", (x, y0 + 0.6, z0 - step_d * 0.82)))
    top = 0.9 + rows * step_h
    # боковые стенки-балки и задняя стенка
    for sx in (-1, 1):
        pts = [(0.0, 0.0), (-rows * step_d, 0.0), (-rows * step_d, top + 0.3), (-0.2, 1.0), (0.0, 1.0)]
        objs.append(extrude2d("Side_%d" % sx, pts, -0.08, 0.08, "Hall_Steel",
                              xf=T((sx * W * 0.5, 0.0, 0.0)) @ Matrix.Rotation(math.radians(-90), 4, 'Y')))
    objs.append(box("BackWall", (W, top + 0.3, 0.12), "Hall_Steel", (0.0, (top + 0.3) * 0.5, -rows * step_d - 0.06)))
    # борт: панель, световая полоса и перила
    objs.append(box("Parapet", (W, 1.0, 0.14), "Hall_SteelDark", (0.0, 0.5, 0.05)))
    objs.append(light_strip("Parapet_Light", (-W * 0.5 + 0.05, 0.86, 0.125), (W * 0.5 - 0.05, 0.86, 0.125), 0.06, 0.02))
    objs += railing("Rail", -W * 0.5 + 0.1, W * 0.5 - 0.1, 1.0, 0.05, h=0.55, post_step=1.5)
    # опорные балки под рядами
    for sx in (-2.0, 0.0, 2.0):
        objs.append(tube("Strut_%d" % int(sx), (sx, 0.0, -0.3), (sx, top - 0.4, -rows * step_d + 0.2), 0.05, "Hall_SteelDark", 6))
    markers = [("Row_%d" % i, (0.0, 0.9 + i * step_h + 0.42, -i * step_d - step_d * 0.55)) for i in range(rows)]
    return done(objs, 0.01) + done(seats), markers


def spectator(name, cheer=False):
    """Зритель — модульное существо (людей в мире нет): голова-шар, корпус-бочонок, руки-трубки. Сидит; origin — сиденье."""
    objs = [revolve(name + "_Body", [(0.0, 0.0), (0.17, 0.02), (0.2, 0.25), (0.16, 0.5), (0.1, 0.56), (0.0, 0.57)], "Hall_Crowd", 7),
            sphere(name + "_Head", 0.13, (0.0, 0.72, 0.02), "Hall_Crowd", 7, 4)]
    for sx in (-1, 1):
        if cheer:
            pts = [(sx * 0.17, 0.46, 0.0), (sx * 0.3, 0.72, 0.05), (sx * 0.34, 0.98, 0.08)]
        else:
            pts = [(sx * 0.17, 0.46, 0.0), (sx * 0.24, 0.26, 0.12), (sx * 0.16, 0.22, 0.26)]
        objs.append(sweep("%s_Arm%d" % (name, sx), pts, 0.045, "Hall_Crowd", sides=4))
    for sx in (-1, 1):   # бёдра вперёд (сидит)
        objs.append(sweep("%s_Leg%d" % (name, sx), [(sx * 0.08, 0.06, 0.0), (sx * 0.09, 0.06, 0.32), (sx * 0.09, -0.3, 0.36)],
                          0.055, "Hall_Crowd", sides=4))
    return objs


def build_Spectator_A():
    return done(spectator("SpA", False)), []


def build_Spectator_B():
    return done(spectator("SpB", True)), []


def build_Catwalk():
    """Мостик 6 м вдоль X: настил, боковые швеллеры, жёлтые перила сзади, светящийся передний край, подвесы. Origin — центр
    низа настила; ширина 1.4 м (z от −1.4 до 0)."""
    L, D = 6.0, 1.4
    objs = [box("Deck", (L, 0.08, D), "Hall_Plate", (0.0, 0.1, -D * 0.5)),
            box("Beam_F", (L, 0.22, 0.1), "Hall_Steel", (0.0, 0.03, -0.05)),
            box("Beam_B", (L, 0.22, 0.1), "Hall_Steel", (0.0, 0.03, -D + 0.05))]
    objs.append(light_strip("EdgeLight", (-L * 0.5, 0.06, 0.005), (L * 0.5, 0.06, 0.005), 0.05, 0.02))
    objs += railing("RailB", -L * 0.5, L * 0.5, 0.14, -D + 0.05, h=1.05, post_step=1.5)
    objs += railing("RailF", -L * 0.5, L * 0.5, 0.14, -0.06, h=1.05, post_step=1.5)
    for x in (-L * 0.5 + 0.2, L * 0.5 - 0.2):   # поперечины и подвесы вверх
        objs.append(box("Cross_%d" % int(x), (0.1, 0.18, D), "Hall_SteelDark", (x, -0.04, -D * 0.5)))
        objs.append(tube("Hanger_%d" % int(x), (x, 0.0, -D * 0.5), (x, 3.0, -D * 0.5), 0.025, "Hall_SteelDark", 6))
    for k in range(7):   # ребра настила
        x = -L * 0.5 + 0.5 + k * (L - 1.0) / 6
        objs.append(box("Rib_%d" % k, (0.06, 0.1, D - 0.2), "Hall_SteelDark", (x, 0.0, -D * 0.5)))
    return done(objs, 0.008), []


def build_Support_Column():
    """Колонна-ферма 12 м, сечение 0.9 м, спереди две вертикальные оранжевые полосы с разрывами, база и оголовок."""
    H, w = 12.0, 0.9
    objs = truss("Truss", (0.0, 0.3, 0.0), (0.0, H - 0.3, 0.0), w, "Hall_SteelDark", 10, chord=0.06, diag=0.03)
    objs.append(box("Base", (1.3, 0.3, 1.3), "Hall_Steel", (0.0, 0.15, 0.0)))
    objs.append(box("Cap", (1.2, 0.3, 1.2), "Hall_Steel", (0.0, H - 0.15, 0.0)))
    # лицевая панель с полосами
    objs.append(box("FacePanel", (0.7, H - 1.2, 0.06), "Hall_Steel", (0.0, H * 0.5, w * 0.5 + 0.04)))
    for sx in (-0.2, 0.2):
        for k in range(5):
            y0 = 1.0 + k * (H - 2.0) / 5
            objs.append(light_strip("Strip_%d_%d" % (int(sx * 10), k), (sx, y0 + 0.15, w * 0.5 + 0.075),
                                    (sx, y0 + (H - 2.0) / 5 - 0.15, w * 0.5 + 0.075), 0.07, 0.02))
    for k in range(4):
        y = 2.0 + k * 2.8
        for sx in (-1, 1):
            K.stud("Bolt_%d_%d" % (k, sx), Vector((sx * 0.3, y, w * 0.5 + 0.07)), (0, 0, 1), "Hall_Steel", r=0.03, h=0.02, sides=6)
    return done(objs, 0.01), []


def build_Stairs():
    """Лестница: подъём 3 м вверх и назад (−Z) на 4 м, 12 ступеней-решёток, косоуры, жёлтые поручни с обеих сторон."""
    rise, run, n, W = 3.0, 4.0, 12, 1.2
    objs = []
    for i in range(n):
        y = rise * (i + 1) / (n + 1)
        z = -run * (i + 0.5) / n
        objs.append(box("Tread_%d" % i, (W, 0.05, run / n + 0.04), "Hall_Plate", (0.0, y, z)))
        objs.append(light_strip("Nose_%d" % i, (-W * 0.5 + 0.05, y + 0.03, z + run / n * 0.5 + 0.015),
                                (W * 0.5 - 0.05, y + 0.03, z + run / n * 0.5 + 0.015), 0.02, 0.01, "Hall_Yellow", (0, 1, 0)))
    for sx in (-1, 1):
        x = sx * (W * 0.5 + 0.05)
        objs.append(tube("Stringer_%d" % sx, (x, -0.05, 0.1), (x, rise, -run), 0.08, "Hall_Steel", 4))
        posts = []
        for k in range(4):
            t = (k + 0.5) / 4
            p = Vector((x, rise * t, -run * t))
            posts.append(p)
            objs.append(tube("Post_%d_%d" % (sx, k), p, p + Vector((0, 1.0, 0)), 0.025, "Hall_Yellow"))
        objs.append(tube("Hand_%d" % sx, posts[0] + Vector((0, 1.0, 0.3)), posts[-1] + Vector((0, 1.0, -0.3)), 0.03, "Hall_Yellow"))
        objs.append(tube("HandMid_%d" % sx, posts[0] + Vector((0, 0.5, 0)), posts[-1] + Vector((0, 0.5, 0)), 0.022, "Hall_Yellow"))
    return done(objs, 0.005), []


def build_Railing():
    """Секция перил 3 м: стойки через 1 м, поручень, средний пояс, бортик."""
    objs = railing("Rail", -1.5, 1.5, 0.0, 0.0, h=1.05, post_step=1.0)
    objs.append(box("Kick", (3.0, 0.12, 0.02), "Hall_Yellow", (0.0, 0.06, 0.0)))
    objs.append(box("Foot", (3.0, 0.03, 0.1), "Hall_Steel", (0.0, 0.015, 0.0)))
    return done(objs, 0.004), []


def lamp(name, pos, aim):
    """Прожектор: корпус-стакан на лире, светящееся стекло смотрит по aim."""
    xf = align_y(aim, pos)
    objs = [fin(revolve(name + "_Body", [(0.13, -0.22), (0.17, -0.12), (0.19, 0.12), (0.2, 0.16), (0.17, 0.17)], "Hall_SteelDark", 14,
                        xf), 0.01),
            revolve(name + "_Lens", [(0.17, 0.165), (0.0, 0.175)], "Hall_LightCool", 14, xf)]
    return objs


def build_Light_Rig():
    """Световая ферма 6 м вдоль X (треугольник 0.45 м) с 4 прожекторами вниз-вперёд и двумя подвесами. Origin — центр фермы."""
    L = 6.0
    objs = truss("Truss", (-L * 0.5, 0.0, 0.0), (L * 0.5, 0.0, 0.0), 0.45, "Hall_SteelDark", 12, chord=0.035, diag=0.018,
                 faces=(0, 1, 2, 3))
    for i in range(4):
        x = -L * 0.5 + 0.9 + i * (L - 1.8) / 3
        objs.append(tube("Clamp_%d" % i, (x, -0.22, 0.0), (x, -0.42, 0.0), 0.03, "Hall_Steel"))
        objs.append(box("Yoke_%d" % i, (0.5, 0.05, 0.06), "Hall_Steel", (x, -0.44, 0.0)))
        objs += lamp("Lamp_%d" % i, Vector((x, -0.66, 0.05)), Vector((0.0, -0.8, 0.6)).normalized())
    for x in (-L * 0.5 + 0.4, L * 0.5 - 0.4):
        objs.append(tube("Cable_%d" % int(x), (x, 0.22, 0.0), (x, 3.0, 0.0), 0.012, "Hall_Rubber", 6))
    return done(objs), []


def screen_quad(name, w, h, center, mat="Hall_Screen"):
    """Экран: квадрат в плоскости XY, лицо +Z, UV 0..1 (u вправо, v вверх в Blender = v вниз в Godot)."""
    bm = bmesh.new()
    cx, cy, cz = center
    vs = [bm.verts.new((cx - w / 2, cy - h / 2, cz)), bm.verts.new((cx + w / 2, cy - h / 2, cz)),
          bm.verts.new((cx + w / 2, cy + h / 2, cz)), bm.verts.new((cx - w / 2, cy + h / 2, cz))]
    bm.faces.new(vs)
    o = K._obj(name, bm, mat)
    uvl = o.data.uv_layers.new(name="UVMap")
    for loop in o.data.loops:
        co = o.data.vertices[loop.vertex_index].co   # Blender: X = Godot X, Z = Godot Y
        uvl.data[loop.index].uv = ((co.x - (cx - w / 2)) / w, (co.z - (cy - h / 2)) / h)
    return o


def build_Big_Screen():
    """Большой экран 8 × 4.5 м в раме, сзади ферма и подвесы, по углам рамы огни. Origin — низ рамы по центру."""
    W, H = 8.0, 4.5
    objs = [box("Frame_T", (W + 0.5, 0.3, 0.35), "Hall_SteelDark", (0.0, H + 0.4, 0.0)),
            box("Frame_B", (W + 0.5, 0.3, 0.35), "Hall_SteelDark", (0.0, 0.1, 0.0)),
            box("Frame_L", (0.3, H + 0.6, 0.35), "Hall_SteelDark", (-W * 0.5 - 0.1, H * 0.5 + 0.25, 0.0)),
            box("Frame_R", (0.3, H + 0.6, 0.35), "Hall_SteelDark", (W * 0.5 + 0.1, H * 0.5 + 0.25, 0.0)),
            box("Backplate", (W, H, 0.1), "Hall_Steel", (0.0, H * 0.5 + 0.25, -0.12))]
    objs.append(screen_quad("Screen", W, H, (0.0, H * 0.5 + 0.25, 0.0)))
    objs += truss("RearTruss", (-W * 0.5, H + 0.4, -0.5), (W * 0.5, H + 0.4, -0.5), 0.4, "Hall_SteelDark", 10, chord=0.03, diag=0.016)
    for sx in (-1, 1):
        objs.append(tube("Hang_%d" % sx, (sx * W * 0.35, H + 0.55, -0.3), (sx * W * 0.35, H + 3.0, -0.3), 0.02, "Hall_Rubber", 6))
        for sy in (0.1, H + 0.4):
            objs.append(box("Corner_%d_%d" % (sx, int(sy)), (0.22, 0.12, 0.05), "Hall_LightWarm", (sx * (W * 0.5 + 0.1), sy, 0.19)))
    return done(objs, 0.015), []


def build_Small_Scoreboard():
    """Табло 3.2 × 1.8 м (GRAVITY ↘ 0.35G рисует Godot): рама со скосами, экран, два кронштейна сверху. Origin — низ по центру."""
    W, H = 3.2, 1.8
    outer = [(-W / 2 - 0.12, 0.0), (W / 2 + 0.12, 0.0), (W / 2 + 0.12, H + 0.1), (W / 2 - 0.1, H + 0.3), (-W / 2 + 0.1, H + 0.3),
             (-W / 2 - 0.12, H + 0.1)]
    objs = [poly_obj("Frame", outer, 0.22, "Hall_SteelDark", T((0.0, 0.0, -0.06)))]
    objs.append(screen_quad("Screen", W, H, (0.0, H * 0.5 + 0.12, 0.06)))
    objs.append(light_strip("TopLight", (-W / 2 + 0.2, H + 0.22, 0.06), (W / 2 - 0.2, H + 0.22, 0.06), 0.05, 0.02))
    for sx in (-1, 1):
        objs.append(tube("Arm_%d" % sx, (sx * W * 0.35, H + 0.3, -0.06), (sx * W * 0.35, H + 1.3, -0.06), 0.035, "Hall_Steel"))
    return done(objs, 0.01), []


def banner(cloth, name):
    """Баннер 2 × 5 м: труба-перекладина, ткань с волной и вырезом снизу, печать: эмблема (кольцо поля с куполом) и
    «NULL / HALL 01». Origin — центр перекладины."""
    W, H = 2.0, 5.0
    cols, rows = 8, 20
    bm = bmesh.new()
    grid = []
    def wave(x, y):
        return 0.05 * math.sin(x * 2.8 + y * 0.6) + 0.03 * math.sin(y * 1.7)
    for j in range(rows + 1):
        y = -0.1 - H * j / rows
        row = []
        for i in range(cols + 1):
            x = -W / 2 + W * i / cols
            if j == rows:   # вырез «ласточкин хвост»: середина выше
                y2 = y + 0.5 * (1.0 - abs(x) / (W / 2))
            else:
                y2 = y
            row.append(bm.verts.new((x, y2, wave(x, y2))))
        grid.append(row)
    for j in range(rows):
        for i in range(cols):
            bm.faces.new((grid[j][i], grid[j + 1][i], grid[j + 1][i + 1], grid[j][i + 1]))
    bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=0.012)
    o = K._obj(name + "_Cloth", bm, cloth)
    C.uv_box(o, 1.0, along='Z')
    objs = [o, tube(name + "_Bar", (-W / 2 - 0.15, 0.0, 0.0), (W / 2 + 0.15, 0.0, 0.0), 0.04, "Hall_SteelDark")]
    for sx in (-1, 1):
        objs.append(sphere(name + "_Cap%d" % sx, 0.06, (sx * (W / 2 + 0.17), 0.0, 0.0), "Hall_Yellow", 8, 4))
        objs.append(tube(name + "_Rope%d" % sx, (sx * W * 0.4, 0.0, 0.0), (0.0, 0.8, 0.0), 0.01, "Hall_Rubber", 4))
    # печать: кольцо поля, купол внутри, три звезды-«уровня», надписи; всё следует волне ткани
    prints = []
    ring = ngon(0, 0, 0.62, 36)
    ring_in = list(reversed(ngon(0, 0, 0.52, 36)))
    prints.append(("Ring", ring, ring_in))
    dome = [(0.42, -0.18)] + [(0.42 * math.cos(math.pi * k / 12), -0.18 + 0.42 * math.sin(math.pi * k / 12)) for k in range(1, 12)] \
        + [(-0.42, -0.18)]
    base = [(-0.46, -0.3), (0.46, -0.3), (0.46, -0.22), (-0.46, -0.22)]
    shapes = [("Dome", dome), ("Base", base)]
    for nm, pts in shapes:
        prints.append((nm, pts, None))
    cy = -1.55
    for nm, pts, hole in prints:
        if hole is None:
            p = poly_obj("%s_%s" % (name, nm), pts, 0.006, "Hall_PrintWhite", T((0.0, cy, 0.0)))
        else:   # кольцо: две полуплоскости как дуги-полосы
            p = sweep("%s_%s" % (name, nm), [Vector((0.57 * math.cos(2 * math.pi * k / 36), cy + 0.57 * math.sin(2 * math.pi * k / 36), 0))
                                             for k in range(36)], 0.05, "Hall_PrintWhite", sides=4, closed=True)
        objs.append(p)
    objs.append(text_obj(name + "_T1", "NULL", 0.62, "Hall_PrintWhite", T((0.0, -2.75, 0.0)), depth=0.006, bold=0.15))
    objs.append(text_obj(name + "_T2", "HALL 01", 0.42, "Hall_PrintWhite", T((0.0, -3.35, 0.0)), depth=0.006))
    # печать повторяет волну ткани (сдвиг по z) и чуть над ней
    for p in objs[len(objs) - len(prints) - 2:]:
        for v in p.data.vertices:
            gx, gy = v.co.x, v.co.z   # Blender (x, −z, y): Godot x = x, Godot y = Blender z
            v.co.y -= wave(gx, gy) + 0.012   # Godot +z = Blender −y
    return objs


def build_Banner_Red():
    return done(banner("Hall_ClothRed", "BR")), []


def build_Banner_Blue():
    return done(banner("Hall_ClothBlue", "BB")), []


def emitter_body(name, R, L, fins=12, ring_glow=True):
    """Барабан поля NULL вдоль +Z (лицом к мембране): ступенчатый корпус, светящееся кольцо и линза на торце, рёбра, болты."""
    xf = align_y((0, 0, 1), (0.0, 0.0, 0.0))
    objs = [fin(revolve(name + "_Drum", [(R * 0.7, -L * 0.5), (R * 0.95, -L * 0.45), (R, -L * 0.3), (R, L * 0.25), (R * 1.08, L * 0.3),
                                        (R * 1.08, L * 0.42), (R * 0.92, L * 0.5), (R * 0.72, L * 0.5)], "Hall_Steel", 32, xf), 0.02)]
    if ring_glow:
        objs.append(K.torus(name + "_Glow", (0.0, 0.0, L * 0.5 + 0.01), R * 0.82, R * 0.07, "Hall_NullGlow", plane='XY', segs=40, sides=8))
    objs.append(revolve(name + "_Lens", [(R * 0.7, L * 0.5), (R * 0.55, L * 0.52), (R * 0.3, L * 0.56), (0.0, L * 0.57)], "Hall_Glass",
                        28, xf))
    objs.append(K.torus(name + "_GlowIn", (0.0, 0.0, L * 0.555), R * 0.32, R * 0.035, "Hall_NullGlow", plane='XY', segs=28, sides=6))
    objs.append(revolve(name + "_Core", [(R * 0.12, L * 0.565), (0.0, L * 0.575)], "Hall_NullGlow", 16, xf))
    objs.append(revolve(name + "_Iris", [(R * 0.74, L * 0.5 + 0.005), (R * 0.72, L * 0.53), (R * 0.6, L * 0.54), (R * 0.58, L * 0.5 + 0.005)],
                        "Hall_SteelDark", 28, xf, closed=True))
    for k in range(fins):
        a = 2 * math.pi * k / fins
        objs.append(box("%s_Fin%d" % (name, k), (0.05, R * 0.25, L * 0.5), "Hall_SteelDark",
                        xf=T((0.0, 0.0, -L * 0.1)) @ Rz(math.degrees(a)) @ T((0.0, R + R * 0.1, 0.0))))
        objs.append(K.stud("%s_Bolt%d" % (name, k), Vector((math.cos(a + 0.26) * R, math.sin(a + 0.26) * R, L * 0.2)),
                           (math.cos(a + 0.26), math.sin(a + 0.26), 0), "Hall_SteelDark", r=0.035, h=0.02, sides=6))
    return objs


def build_Null_Emitter():
    """Эмиттер поля (якорь NULL) Ø1.4 × 1.6 м на U-опоре: лицо (светящийся торец) смотрит в +Z, в мембрану. Origin — низ опоры."""
    R, L, cy = 0.7, 1.6, 1.25
    objs = [o for o in emitter_body("Em", R, L)]
    for o in objs:
        pass
    body = objs
    for o in body:   # поднять барабан на ось опоры
        for v in o.data.vertices:
            v.co.z += cy     # Blender Z = Godot Y
    objs = body
    objs.append(box("Base", (1.8, 0.2, 1.6), "Hall_Steel", (0.0, 0.1, 0.0)))
    for sx in (-1, 1):
        objs.append(box("Yoke_%d" % sx, (0.14, cy, 0.4), "Hall_SteelDark", (sx * (R + 0.2), cy * 0.5 + 0.1, 0.0)))
        objs.append(fin(revolve("Pivot_%d" % sx, [(0.14, 0.0), (0.14, 0.1), (0.1, 0.14), (0.0, 0.14)], "Hall_Steel", 16,
                                align_y((sx, 0, 0), (sx * (R + 0.26), cy, 0.0))), 0.01))
    for k in range(3):   # кабели от основания назад
        objs.append(sweep("Cable_%d" % k, [(-0.3 + k * 0.3, 0.2, -0.7), (-0.3 + k * 0.3, 0.12, -1.2), (-0.35 + k * 0.35, 0.05, -2.0)],
                          0.05, "Hall_Rubber", sides=6))
    return done(objs), []


def build_Membrane_Anchor_A():
    """Якорь мембраны A: барабан Ø0.9 со светящимся кольцом на плите-креплении к стене (плита в z < 0). Origin — центр плиты."""
    objs = emitter_body("MA", 0.45, 0.8, fins=8)
    for o in objs:
        for v in o.data.vertices:
            v.co.y -= 0.55    # Godot +z = Blender −y: барабан вперёд от плиты
    objs.append(box("Plate", (1.1, 1.1, 0.12), "Hall_SteelDark", (0.0, 0.0, 0.06)))
    for sx in (-1, 1):
        for sy in (-1, 1):
            objs.append(K.stud("PlateBolt_%d_%d" % (sx, sy), Vector((sx * 0.45, sy * 0.45, 0.12)), (0, 0, 1), "Hall_Steel", r=0.04,
                               h=0.025, sides=6))
    return done(objs), []


def build_Membrane_Anchor_B():
    """Якорь мембраны B: сдвоенное кольцо на короткой штанге с хомутами, светится зазор между кольцами. Origin — центр плиты."""
    xf = align_y((0, 0, 1))
    objs = [box("Plate", (0.9, 0.9, 0.1), "Hall_SteelDark", (0.0, 0.0, 0.05)),
            fin(revolve("Post", [(0.16, 0.1), (0.14, 0.35), (0.14, 0.6), (0.18, 0.62)], "Hall_Steel", 20, xf), 0.01)]
    for k, z in enumerate((0.62, 0.9)):
        objs.append(fin(revolve("Ring_%d" % k, [(0.28, z), (0.44, z), (0.46, z + 0.04), (0.46, z + 0.14), (0.44, z + 0.18), (0.28, z + 0.18)],
                                "Hall_Steel", 32, xf, closed=True), 0.01))
    objs.append(revolve("GlowGap", [(0.43, 0.8), (0.43, 0.9), (0.0, 0.9)], "Hall_NullGlow", 32, xf))
    objs.append(revolve("Cap", [(0.26, 1.08), (0.2, 1.14), (0.0, 1.16)], "Hall_NullGlow", 24, xf))
    for k in range(6):
        a = 2 * math.pi * k / 6
        objs.append(box("Clamp_%d" % k, (0.06, 0.12, 0.5), "Hall_SteelDark",
                        xf=Rz(math.degrees(a)) @ T((0.0, 0.47, 0.85))))
    return done(objs), []


def build_Fighter_Gate():
    """Ворота бойца 5 × 5 м: рама с оранжевыми полосами на стойках, притолока с табличкой, две створки (отдельные узлы
    Gate_Door_L / Gate_Door_R, origin — петли). Origin рамы — низ по центру."""
    W, H, D = 5.0, 5.0, 0.6
    frame = [box("Jamb_L", (0.6, H + 0.6, D), "Hall_SteelDark", (-W / 2 - 0.3, (H + 0.6) / 2, 0.0)),
             box("Jamb_R", (0.6, H + 0.6, D), "Hall_SteelDark", (W / 2 + 0.3, (H + 0.6) / 2, 0.0)),
             box("Header", (W + 1.2, 0.9, D + 0.1), "Hall_Steel", (0.0, H + 0.45, 0.0)),
             box("Sill", (W + 1.2, 0.12, D), "Hall_Steel", (0.0, 0.06, 0.0))]
    for sx in (-1, 1):
        for k in range(3):
            y0 = 0.3 + k * (H - 0.4) / 3
            frame.append(light_strip("Strip_%d_%d" % (sx, k), (sx * (W / 2 + 0.3), y0 + 0.1, D / 2 + 0.01),
                                     (sx * (W / 2 + 0.3), y0 + (H - 0.4) / 3 - 0.1, D / 2 + 0.01), 0.12, 0.03))
    frame.append(box("Sign", (1.8, 0.5, 0.06), "Hall_SteelDark", (0.0, H + 0.45, D / 2 + 0.08)))
    frame.append(text_obj("SignText", "GATE A", 0.3, "Hall_PrintWhite", T((0.0, H + 0.43, D / 2 + 0.115)), depth=0.01))
    for k in range(10):   # предупреждающие полосы по порогу
        x0 = -W / 2 - 0.6 + k * (W + 1.2) / 10
        frame.append(poly_obj("Haz_%d" % k, [(x0, 0.0), (x0 + 0.25, 0.0), (x0 + 0.45, 0.12), (x0 + 0.2, 0.12)], 0.01, "Hall_Yellow",
                              T((0.0, 0.0, D / 2 + 0.005))))
    frame = done(frame, 0.02)
    f = C.join(frame, "Gate_Frame")
    doors = []
    for side, sx in (("L", -1), ("R", 1)):
        parts = [box("Leaf_%s" % side, (W / 2 - 0.04, H - 0.05, 0.14), "Hall_Steel", (sx * (W / 4), H / 2, 0.0))]
        for k in range(6):
            y = 0.5 + k * (H - 1.0) / 5
            parts.append(box("Rib_%s_%d" % (side, k), (W / 2 - 0.3, 0.1, 0.06), "Hall_SteelDark", (sx * (W / 4), y, 0.09)))
        parts.append(light_strip("DoorLight_%s" % side, (sx * 0.08, 0.4, 0.075), (sx * 0.08, H - 0.4, 0.075), 0.05, 0.02))
        d = C.join(done(parts, 0.01), "Gate_Door_" + side)
        C.set_origin(d, G2B @ Vector((sx * (W / 2 - 0.02), 0.0, 0.0)))
        doors.append(d)
    return [f] + doors, []


def build_Camera_Broadcast():
    """Телекамера на настенном кронштейне: плита, рычаг, панорамная голова, корпус, объектив с блендой, видоискатель, ручка.
    Смотрит в −X (на арену, если стоит справа). Origin — центр плиты крепления."""
    objs = [box("WallPlate", (0.1, 0.5, 0.4), "Hall_SteelDark", (0.05, 0.0, 0.0)),
            tube("Arm", (0.1, 0.0, 0.0), (-0.6, 0.25, 0.0), 0.05, "Hall_Steel"),
            fin(revolve("PanHead", [(0.12, 0.0), (0.12, 0.12), (0.08, 0.16), (0.0, 0.16)], "Hall_SteelDark", 16, T((-0.62, 0.22, 0.0))), 0.01),
            box("Body", (0.55, 0.32, 0.3), "Hall_Steel", (-0.7, 0.55, 0.0)),
            box("Side", (0.4, 0.25, 0.05), "Hall_SteelDark", (-0.7, 0.55, 0.17))]
    lens_xf = align_y((-1, 0, 0), (-0.98, 0.55, 0.0))
    objs.append(fin(revolve("Lens", [(0.1, 0.0), (0.11, 0.05), (0.11, 0.35), (0.14, 0.38), (0.16, 0.5), (0.13, 0.5)], "Hall_SteelDark", 20,
                            lens_xf), 0.005))
    objs.append(revolve("Glass", [(0.11, 0.49), (0.0, 0.5)], "Hall_Glass", 20, lens_xf))
    objs.append(box("Viewfinder", (0.2, 0.14, 0.14), "Hall_SteelDark", (-0.62, 0.78, 0.1)))
    objs.append(tube("Handle", (-0.9, 0.78, 0.0), (-0.5, 0.78, 0.0), 0.025, "Hall_Rubber"))
    objs.append(box("Tally", (0.06, 0.04, 0.04), "Hall_LightWarm", (-0.95, 0.73, 0.0)))
    return done(objs, 0.01), []


def build_Speaker():
    """Подвесной динамик: трапециевидный корпус, два конуса, решётка-рамка, скоба и цепи вверх. Origin — центр верха."""
    top = [(-0.45, 0.0), (0.45, 0.0), (0.4, -1.5), (-0.4, -1.5)]
    objs = [poly_obj("Cab", top, 0.7, "Hall_SteelDark", T((0.0, 0.0, -0.2)))]
    for k, y in enumerate((-0.45, -1.1)):
        xf = align_y((0, 0, 1), (0.0, y, 0.15))
        objs.append(revolve("Cone_%d" % k, [(0.3, 0.0), (0.28, 0.02), (0.1, -0.1), (0.05, -0.1), (0.0, -0.06)], "Hall_Rubber", 20, xf))
        objs.append(K.torus("Surround_%d" % k, (0.0, y, 0.16), 0.3, 0.025, "Hall_Steel", plane='XY', segs=24, sides=6))
    objs.append(box("Grille_T", (0.85, 0.05, 0.04), "Hall_Steel", (0.0, -0.05, 0.17)))
    objs.append(box("Grille_B", (0.78, 0.05, 0.04), "Hall_Steel", (0.0, -1.45, 0.17)))
    objs.append(box("Bracket", (1.05, 0.08, 0.1), "Hall_Steel", (0.0, 0.1, -0.2)))
    for sx in (-1, 1):
        objs.append(tube("Chain_%d" % sx, (sx * 0.4, 0.12, -0.2), (sx * 0.25, 1.2, -0.2), 0.015, "Hall_SteelDark", 4))
    return done(objs, 0.015), []


def build_Tech_Box():
    """Подвесной техшкаф: корпус, дверца с жалюзи, лампа, кабельные вводы снизу, наклейка-предупреждение. Origin — центр верха."""
    W, H, D = 0.9, 1.4, 0.45
    objs = [box("Cab", (W, H, D), "Hall_Steel", (0.0, -H / 2, 0.0)),
            box("Door", (W - 0.1, H - 0.12, 0.03), "Hall_SteelDark", (0.0, -H / 2, D / 2 + 0.015))]
    for k in range(6):
        objs.append(box("Louver_%d" % k, (W - 0.3, 0.03, 0.03), "Hall_Steel", (0.0, -0.3 - k * 0.07, D / 2 + 0.04)))
    objs.append(box("Handle", (0.04, 0.2, 0.04), "Hall_Rubber", (W / 2 - 0.12, -H / 2 - 0.1, D / 2 + 0.05)))
    objs.append(revolve("Lamp", [(0.05, 0.0), (0.05, 0.04), (0.0, 0.06)], "Hall_LightWarm", 12, align_y((0, 1, 0), (0.25, 0.0, 0.1))))
    tri = [(-0.12, -0.9), (0.12, -0.9), (0.0, -0.69)]
    objs.append(poly_obj("Warn", tri, 0.01, "Hall_Yellow", T((0.0, 0.0, D / 2 + 0.035))))
    objs.append(poly_obj("WarnMark", [(-0.012, -0.86), (0.012, -0.86), (0.012, -0.76), (-0.012, -0.76)], 0.012, "Hall_PrintDark",
                         T((0.0, 0.0, D / 2 + 0.04))))
    for k in range(3):
        x = -0.25 + k * 0.25
        objs.append(sweep("Cable_%d" % k, [(x, -H, 0.0), (x, -H - 0.3, 0.05), (x + 0.1, -H - 0.8, 0.0)], 0.03, "Hall_Rubber", sides=6))
    objs.append(box("Mount", (W + 0.2, 0.08, 0.1), "Hall_SteelDark", (0.0, 0.04, -D / 2 + 0.05)))
    return done(objs, 0.01), []


def build_Crate():
    """Ящик 1.2 м: рама из уголка, филёнки, угловые накладки, знак опасности (жёлтый треугольник) спереди."""
    s = 1.2
    objs = []
    h = s / 2
    edges = [((-h, 0, -h), (h, 0, -h)), ((-h, 0, h), (h, 0, h)), ((-h, s, -h), (h, s, -h)), ((-h, s, h), (h, s, h)),
             ((-h, 0, -h), (-h, 0, h)), ((h, 0, -h), (h, 0, h)), ((-h, s, -h), (-h, s, h)), ((h, s, -h), (h, s, h)),
             ((-h, 0, -h), (-h, s, -h)), ((h, 0, -h), (h, s, -h)), ((-h, 0, h), (-h, s, h)), ((h, 0, h), (h, s, h))]
    for i, (a, b) in enumerate(edges):
        objs.append(sweep("Edge_%d" % i, [Vector(a), Vector(b)], 0.05, "Hall_SteelDark", sides=4, phase=math.pi / 4))
    objs.append(box("Panel", (s - 0.06, s - 0.06, s - 0.06), "Hall_Steel", (0.0, s / 2, 0.0)))
    for sx in (-1, 1):
        for sy in (0, 1):
            for sz in (-1, 1):
                objs.append(box("Corner_%d_%d_%d" % (sx, sy, sz), (0.14, 0.14, 0.14), "Hall_Yellow", (sx * h, sy * s, sz * h)))
    tri = [(-0.3, 0.3), (0.3, 0.3), (0.0, 0.82)]
    objs.append(poly_obj("Warn", tri, 0.01, "Hall_Yellow", T((0.0, 0.0, h - 0.02))))
    objs.append(poly_obj("WarnIn", [(-0.2, 0.36), (0.2, 0.36), (0.0, 0.71)], 0.012, "Hall_PrintDark", T((0.0, 0.0, h - 0.015))))
    objs.append(poly_obj("WarnBolt", [(0.02, 0.66), (-0.05, 0.52), (0.0, 0.52), (-0.03, 0.40), (0.05, 0.56), (0.0, 0.56)], 0.014,
                         "Hall_Yellow", T((0.0, 0.0, h - 0.01))))
    return done(objs, 0.01), []


def build_Cables_Pipes():
    """Связка 6 м вдоль X: 3 трубы и 4 кабеля с провисом, хомуты-кронштейны каждые 2 м. Origin — центр связки."""
    L = 6.0
    objs = []
    for k in range(3):
        y = 0.18 * k
        objs.append(tube("Pipe_%d" % k, (-L / 2, y, 0.0), (L / 2, y, 0.0), 0.075, "Hall_Steel", 10))
    for k in range(4):
        pts = [Vector((-L / 2 + L * i / 12, -0.2 - 0.05 * k - 0.25 * math.sin(math.pi * (i % 6) / 6), 0.1 - 0.06 * k)) for i in range(13)]
        objs.append(sweep("Cable_%d" % k, pts, 0.028, "Hall_Rubber", sides=6))
    for i in range(4):
        x = -L / 2 + 0.3 + i * (L - 0.6) / 3
        objs.append(box("Clamp_%d" % i, (0.08, 0.6, 0.28), "Hall_SteelDark", (x, 0.18, 0.0)))
    return done(objs, 0.005), []


def build_Debris():
    """4 обломка металла (декор, объекты Debris_A..D): гнутый лист, кусок фермы, обломок балки, помятый короб."""
    out = []
    pts = [(-0.5, 0.0), (0.4, -0.05), (0.55, 0.3), (0.2, 0.45), (-0.3, 0.38), (-0.55, 0.2)]
    a = extrude2d("Debris_A", pts, -0.02, 0.02, "Hall_Steel", bend=0.6, xf=T((0.0, 0.3, 0.0)) @ Rx(70))
    out.append(a)
    b = truss("DebB", (-0.6, 0.2, 0.0), (0.5, 0.35, 0.1), 0.3, "Hall_SteelDark", 3, chord=0.03, diag=0.016)
    out.append(C.join(b, "Debris_B"))
    c = box("Debris_C", (1.0, 0.22, 0.14), "Hall_SteelDark", (0.0, 0.11, 0.0), jitter=0.03)
    out.append(c)
    d = box("Debris_D", (0.5, 0.35, 0.45), "Hall_Steel", (0.0, 0.17, 0.0), jitter=0.06)
    out.append(d)
    for i, o in enumerate(out):
        for v in o.data.vertices:
            v.co.x += (i - 1.5) * 1.3
    return done(out, 0.0), []


def build_Floor_Platform():
    """Платформа 6 × 6 × 0.6: плита настила с разметкой, рама с жёлтой кромкой, угловые стойки со светом, боковые панели."""
    S6, H = 6.0, 0.6
    objs = [box("Top", (S6, 0.1, S6), "Hall_Plate", (0.0, H - 0.05, 0.0)),
            box("Body", (S6 - 0.2, H - 0.1, S6 - 0.2), "Hall_SteelDark", (0.0, (H - 0.1) / 2, 0.0))]
    for sx, sz, w, d in ((0, 1, S6, 0.12), (0, -1, S6, 0.12), (1, 0, 0.12, S6), (-1, 0, 0.12, S6)):
        objs.append(box("Edge_%d_%d" % (sx, sz), (w, 0.06, d), "Hall_Yellow", (sx * (S6 / 2 - 0.06), H + 0.03, sz * (S6 / 2 - 0.06))))
    for k in range(1, 3):   # разметка-сетка
        t = -S6 / 2 + k * S6 / 3
        objs.append(box("GridX_%d" % k, (S6 - 0.4, 0.012, 0.04), "Hall_PrintWhite", (0.0, H + 0.006, t)))
        objs.append(box("GridZ_%d" % k, (0.04, 0.012, S6 - 0.4), "Hall_PrintWhite", (t, H + 0.006, 0.0)))
    for sx in (-1, 1):
        for sz in (-1, 1):
            objs.append(box("Post_%d_%d" % (sx, sz), (0.2, 0.3, 0.2), "Hall_Steel", (sx * (S6 / 2 - 0.1), H + 0.15, sz * (S6 / 2 - 0.1))))
            objs.append(box("PostLight_%d_%d" % (sx, sz), (0.16, 0.05, 0.16), "Hall_LightWarm", (sx * (S6 / 2 - 0.1), H + 0.32, sz * (S6 / 2 - 0.1))))
    for k in range(5):   # рёбра на передней панели
        x = -S6 / 2 + 0.6 + k * (S6 - 1.2) / 4
        objs.append(box("FrontRib_%d" % k, (0.1, H - 0.2, 0.05), "Hall_Steel", (x, (H - 0.1) / 2, S6 / 2 - 0.08)))
    return done(objs, 0.01), []


def build_Membrane_Strip():
    """Лента мембраны поля: полуокружность радиуса 1 в плоскости XY (от +X через верх к −X), глубина z = −1..1.
    В Godot узел растягивается до полуосей купола и глубины ленты, вид и прогиб — шейдер null_membrane.gdshader.
    UV: u — доля дуги 0..1, v — поперёк ленты 0..1. Origin — центр (середина пола купола)."""
    seg, rows = 160, 6
    bm = bmesh.new()
    grid = []
    for j in range(rows + 1):
        z = -1.0 + 2.0 * j / rows
        grid.append([bm.verts.new((math.cos(math.pi * i / seg), math.sin(math.pi * i / seg), z)) for i in range(seg + 1)])
    faces = []
    for j in range(rows):
        for i in range(seg):
            faces.append(bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i])))
    o = K._obj("Membrane_Strip", bm, "Hall_Membrane")
    uvl = o.data.uv_layers.new(name="UVMap")
    for loop in o.data.loops:
        co = o.data.vertices[loop.vertex_index].co          # Blender (x, −z_g, y_g)
        ang = math.atan2(co.z, co.x)
        uvl.data[loop.index].uv = (ang / math.pi, (-co.y + 1.0) * 0.5)
    for p in o.data.polygons:
        p.use_smooth = True
    return [o], []


def build_Wall_Panel_01():
    """Панель стены зала 6 × 8 м (не с листа ассетов, а с главного кадра): вертикальные рёбра, горизонтальные пояса, крупное
    «01» тёмной краской. Лицо +Z. Origin — низ по центру. Вариант без номера — Wall_Panel."""
    return wall_panel(True), []


def build_Wall_Panel():
    return wall_panel(False), []


def wall_panel(number):
    W, H = 6.0, 8.0
    objs = [box("Sheet", (W, H, 0.1), "Hall_Steel", (0.0, H / 2, -0.05))]
    for k in range(7):
        x = -W / 2 + k * W / 6
        objs.append(box("Rib_%d" % k, (0.14, H, 0.16), "Hall_SteelDark", (x, H / 2, 0.06)))
    for y in (0.4, H / 2, H - 0.4):
        objs.append(box("Belt_%d" % int(y), (W, 0.2, 0.12), "Hall_SteelDark", (0.0, y, 0.05)))
    if number:
        objs.append(text_obj("Num", "01", 3.4, "Hall_PrintDark", T((0.0, 5.2, 0.005)), depth=0.01, bold=0.1))
    return done(objs, 0.01)


MODULES = ["Stand_Segment", "Spectator_A", "Spectator_B", "Catwalk", "Support_Column", "Stairs", "Railing", "Light_Rig",
           "Big_Screen", "Small_Scoreboard", "Banner_Red", "Banner_Blue", "Null_Emitter", "Membrane_Anchor_A", "Membrane_Anchor_B",
           "Fighter_Gate", "Camera_Broadcast", "Speaker", "Tech_Box", "Crate", "Cables_Pipes", "Debris", "Floor_Platform",
           "Wall_Panel_01", "Wall_Panel", "Membrane_Strip"]
MULTI = {"Fighter_Gate", "Debris"}   # несколько узлов в одном glb (створки ворот, 4 обломка)


def build(name):
    """→ (объекты для экспорта, маркеры [(имя, позиция Godot)])."""
    objs, markers = globals()["build_" + name]()
    if name not in MULTI:
        o = C.join(objs, name)
        objs = [o]
    empties = []
    for mname, pos in markers:
        e = K.empty(mname, T(pos), 'PLAIN_AXES', 0.2)
        e.parent = objs[0]
        empties.append(e)
    return objs, empties


def tris_of(objs):
    return sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objs if o.type == 'MESH')


def export_all(names):
    rp = os.path.join(OUT, "kit_report.json")
    report = {}
    if os.path.exists(rp):   # экспорт части модулей не стирает остальные строки отчёта
        with open(rp) as f:
            report = json.load(f)
    bad = []
    for name in names:
        C.reset_scene()
        K._MATS.clear()
        setup_materials(export=True)
        objs, empties = build(name)
        tris = tris_of(objs)
        budget = TRI_BUDGET_CROWD if name.startswith("Spectator") else TRI_BUDGET_BIG.get(name, TRI_BUDGET)
        path = os.path.join(OUT, name + ".glb")
        C.export_glb(path, objs + empties)
        mats = sorted({m.name for o in objs for m in o.data.materials if m is not None})
        report[name] = {"tris": tris, "budget": budget, "bytes": os.path.getsize(path), "materials": mats,
                        "nodes": [o.name for o in objs], "markers": [e.name for e in empties]}
        print("%-20s %5d / %5d tris  %s" % (name, tris, budget, ", ".join(mats)))
        if tris > budget:
            bad.append(name)
    with open(rp, "w") as f:
        json.dump(dict(sorted(report.items())), f, ensure_ascii=False, indent=1)
    if bad:
        print("ERROR: over budget:", bad)
        sys.exit(1)


# ----------------------------------------------------------------------------------------------------------------------
# превью: миниатюры модулей (3/4 сверху) → лист с подписями
# ----------------------------------------------------------------------------------------------------------------------
def render_thumb(name, out_png, res=(520, 420), samples=16):
    C.reset_scene()
    K._MATS.clear()
    setup_materials(export=False)
    objs, _ = build(name)
    scn = bpy.context.scene
    scn.render.engine = 'CYCLES'
    scn.cycles.samples = samples
    scn.cycles.use_denoising = True
    scn.render.resolution_x, scn.render.resolution_y = res
    scn.view_settings.view_transform = 'AgX'
    scn.view_settings.look = 'AgX - Medium High Contrast'
    world = bpy.data.worlds.new("W")
    scn.world = world
    world.use_nodes = True
    world.node_tree.nodes['Background'].inputs['Color'].default_value = (0.09, 0.09, 0.1, 1.0)
    for nm, col, energy, rot in (("Key", (1.0, 0.86, 0.7), 3.0, (math.radians(50), 0, math.radians(-35))),
                                 ("Rim", (0.5, 0.65, 1.0), 1.5, (math.radians(70), 0, math.radians(150)))):
        ld = bpy.data.lights.new(nm, 'SUN')
        ld.color = col
        ld.energy = energy
        lo = bpy.data.objects.new(nm, ld)
        scn.collection.objects.link(lo)
        lo.rotation_euler = rot
    cam_d = bpy.data.cameras.new("Cam")
    cam_d.type = 'ORTHO'
    cam = bpy.data.objects.new("Cam", cam_d)
    scn.collection.objects.link(cam)
    cam.rotation_euler = (math.radians(72), 0.0, math.radians(-28))
    scn.camera = cam
    corners = [o.matrix_world @ Vector(c) for o in objs for c in o.bound_box]
    rot = cam.rotation_euler.to_matrix()
    right, up, fwd = rot.col[0], rot.col[1], -rot.col[2]
    us = [c.dot(right) for c in corners]
    vs = [c.dot(up) for c in corners]
    aspect = res[0] / res[1]
    cam_d.ortho_scale = max((max(us) - min(us)) * 1.12, (max(vs) - min(vs)) * 1.12 * aspect)
    center = sum(corners, Vector()) / len(corners)
    cam.location = center - fwd * 60.0
    cam_d.clip_end = 200.0
    scn.render.filepath = out_png
    bpy.ops.render.render(write_still=True)
    return tris_of(objs)


def sheet(out_png, names):
    tmp = os.path.join(os.path.dirname(out_png), "_hall_thumbs")
    os.makedirs(tmp, exist_ok=True)
    meta = []
    for n in names:
        p = os.path.join(tmp, n + ".png")
        t = render_thumb(n, p)
        meta.append({"name": n, "file": p, "tris": t})
    with open(os.path.join(tmp, "meta.json"), "w") as f:
        json.dump({"out": out_png, "items": meta}, f)
    print("thumbs →", tmp, "(собрать лист: python3 arena_null_hall.py --compose", os.path.join(tmp, "meta.json") + ")")


def compose(meta_path):
    """Системный python3 + PIL: миниатюры в сетку 5 колонок с подписями."""
    from PIL import Image, ImageDraw, ImageFont
    with open(meta_path) as f:
        meta = json.load(f)
    items = meta["items"]
    ims = [Image.open(it["file"]).convert("RGB") for it in items]
    cw, ch = ims[0].size
    cols = 5
    rows = (len(ims) + cols - 1) // cols
    head, lab = 70, 40
    sheet_im = Image.new("RGB", (cols * cw, head + rows * (ch + lab)), (20, 20, 24))
    d = ImageDraw.Draw(sheet_im)
    fp = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
    if not os.path.exists(fp):
        fp = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
    big, small = ImageFont.truetype(fp, 30), ImageFont.truetype(fp, 19)
    d.text((20, 18), "ARENA 01 — OLD NULL HALL: модульный кит (tools/blender/arena_null_hall.py)", font=big, fill=(240, 236, 228))
    for i, (it, im) in enumerate(zip(items, ims)):
        x, y = (i % cols) * cw, head + (i // cols) * (ch + lab)
        sheet_im.paste(im, (x, y))
        d.text((x + 12, y + ch + 8), "%s  ·  %d tris" % (it["name"], it["tris"]), font=small, fill=(255, 196, 120))
    sheet_im.save(meta["out"], optimize=True)
    print("sheet →", meta["out"], sheet_im.size)


if __name__ == "__main__":
    if bpy is None or "--compose" in sys.argv:
        compose(sys.argv[sys.argv.index("--compose") + 1])
    else:
        args = C.args_after_dashdash()
        names = [a for a in args if a in MODULES] or MODULES
        if "--export" in args:
            export_all(names)
        elif "--sheet" in args:
            sheet(args[args.index("--sheet") + 1], names)
        elif "--preview" in args:
            sheet(args[args.index("--preview") + 1], names)
