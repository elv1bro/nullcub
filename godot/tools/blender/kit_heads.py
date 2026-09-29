"""Головы кита: origin = шея, растут вверх (Socket повёрнут на 180°); FacePlate под фото, Anchor_Top под декор."""
import math
import random

from mathutils import Matrix, Vector  # noqa: F401

from kit_common import *  # noqa: F401,F403 — примитивы craft_parts, материалы и узлы кита


def build_Head_Round(base="Wood"):
    """Круглая голова-игрушка: брус со скруглением почти в шар, утопленная рамка под фото, уши-болты."""
    c = (0.0, 0.2, 0.0)
    shell = box("HR_Shell", (0.30, 0.29, 0.27), "Base_" + base, c)
    K.bevel_apply(shell, 0.085, 4, 30.0)          # фаска ДО выреза: иначе кромки выреза зажимают её (clamp overlap)
    cut_box(shell, (0.0, 0.195, 0.145), (0.21, 0.175, 0.05))
    objs = [fin(shell, 0.0, angle=50.0)]
    objs.append(rounded_frame("HR_Frame", (0.0, 0.195), 0.106, 0.09, 0.009, "Brass", 0.126))
    for sx in (-1, 1):
        objs.append(fin(revolve("HR_Ear", [(0.0, 0.0), (0.042, 0.0), (0.045, 0.012), (0.036, 0.024), (0.0, 0.024)], "Iron", 20,
                                align_y((sx, 0, 0), (sx * 0.142, 0.2, 0.0))), 0.003, 1, uv="cyl", axis='X'))
        objs.append(fin(stud("HR_EarBolt", (sx * 0.166, 0.2, 0.0), (sx, 0, 0), "Steel", 0.018, 0.012, 6)))
    objs += neck_stub("HR")
    face = face_plate("FacePlate", (0.0, 0.195, 0.121), 0.2, 0.165)
    empties = [socket(rot_z=180.0), anchor("Top", (0.0, 0.345, 0.0), 180.0), shape_sphere("Head", c, 0.15)]
    return objs, empties, [face]


def build_Head_Crate(base="Planks"):
    """Голова-ящик: доски с пазами, железные уголки на гвоздях, окно под фото. Пазы режут ящик насквозь — внутри вкладыш из
    ореха (дно пазов, сквозь щели не видно фона); плашка лица скруглена по рамке (углы фото не торчат из-под неё)."""
    c = (0.0, 0.2, 0.0)
    shell = box("HC_Shell", (0.31, 0.29, 0.29), "Base_" + base, c)
    for y in (0.13, 0.27):
        cut_box(shell, (0.0, y, 0.0), (0.4, 0.007, 0.4))
    cut_box(shell, (0.0, 0.2, 0.155), (0.2, 0.15, 0.05))
    objs = [fin(shell, 0.012, 2, angle=40.0)]
    # вкладыш: на 6 мм внутри граней, спереди — за дном окна под фото (z 0.13), чтобы не закрыть плашку
    objs.append(fin(box("HC_Filler", (0.298, 0.278, 0.263), "WoodDark", (0.0, 0.2, -0.0065))))
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                p = Vector((sx * 0.142, 0.2 + sy * 0.132, sz * 0.132))
                objs.append(rbox("HC_Corner", (0.04, 0.04, 0.04), "Iron", p, 0.008, 2))
                objs.append(fin(stud("HC_Nail", p + Vector((0, 0, sz * 0.021)), (0, 0, sz), "Steel", 0.006, 0.004, 6)))
    objs.append(rounded_frame("HC_Frame", (0.0, 0.2), 0.1, 0.075, 0.008, "Iron", 0.146))
    objs += neck_stub("HC")
    # плашка = внутренний контур рамки (суперэллипс 5, как rounded_frame): край фото уходит под трубку рамки, углов нет
    face = face_plate("FacePlate", (0.0, 0.2, 0.131), 0.2, 0.15, cols=12, rows=10, round_n=5.0)
    empties = [socket(rot_z=180.0), anchor("Top", (0.0, 0.345, 0.0), 180.0), shape_box("Head", c, (0.31, 0.29, 0.29))]
    return objs, empties, [face]


def build_Head_Bot(base="PaintYellow"):
    """Голова-робот: крашеный короб, экран в резиновой рамке (фото — «на экране»), антенна с шаром цвета игрока, уши-диски."""
    c = (0.0, 0.19, 0.0)
    shell = box("HB_Shell", (0.33, 0.27, 0.27), "Base_" + base, c)
    K.bevel_apply(shell, 0.05, 3, 30.0)
    cut_box(shell, (0.0, 0.19, 0.15), (0.25, 0.18, 0.06))
    objs = [fin(shell, 0.0, angle=50.0)]
    objs.append(rounded_frame("HB_Bezel", (0.0, 0.19), 0.128, 0.093, 0.014, "Rubber", 0.128))
    for sx in (-1, 1):
        objs.append(fin(revolve("HB_Ear", [(0.0, 0.0), (0.055, 0.0), (0.058, 0.02), (0.03, 0.04), (0.0, 0.04)], "Iron", 24,
                                align_y((sx, 0, 0), (sx * 0.158, 0.19, 0.0))), 0.003, 1, uv="cyl", axis='X'))
        for k in range(6):
            a = TAU * k / 6
            p = (sx * 0.176, 0.19 + math.sin(a) * 0.04, math.cos(a) * 0.04)
            objs.append(fin(stud("HB_EarBolt", p, (sx, 0, 0), "Steel", 0.006, 0.004, 6)))
    for x in (-0.06, 0.0, 0.06):
        objs.append(rbox("HB_Vent", (0.035, 0.012, 0.15), "Rubber", (x, 0.325, -0.01), 0.005, 1))
    objs.append(fin(sweep("HB_Antenna", [(0.07, 0.32, -0.04), (0.075, 0.4, -0.04), (0.085, 0.46, -0.04)], 0.007, "Steel", sides=8), angle=70))
    objs.append(fin(sphere("HB_AntennaBall", 0.024, (0.085, 0.475, -0.04), "Shirt_Kit", 16, 8), angle=80))
    objs += neck_stub("HB")
    face = face_plate("FacePlate", (0.0, 0.19, 0.124), 0.23, 0.165)
    empties = [socket(rot_z=180.0), anchor("Top", (0.0, 0.325, 0.0), 180.0), shape_box("Head", c, (0.33, 0.27, 0.27))]
    return objs, empties, [face]


def build_Head_Horned(base="Iron"):
    """Рогатый шлем: железный купол с гребнем и заклёпками, прорезь-забрало с фото, костяные рога."""
    prof = [(0.0, 0.36), (0.07, 0.352), (0.12, 0.32), (0.148, 0.27), (0.158, 0.2), (0.156, 0.1), (0.15, 0.06), (0.162, 0.05),
            (0.162, 0.035), (0.14, 0.03), (0.0, 0.03)]
    shell = revolve("HH_Shell", prof, "Base_" + base, 28)
    cut_box(shell, (0.0, 0.17, 0.14), (0.2, 0.1, 0.12))
    objs = [fin(shell, 0.002, 1, angle=40.0, uv="cyl")]
    crest = []
    for i in range(13):
        a = math.pi * (0.1 + 0.8 * i / 12)
        crest.append((0.0, 0.2 + 0.165 * math.sin(a), 0.165 * math.cos(a)))
    objs.append(fin(sweep("HH_Crest", crest, 0.014, "Iron", sides=6), angle=70))
    objs += ring_rivets("HH_Rivet", 0.075, 0.158, 12, "Brass", 0.0075)
    for sx in (-1, 1):
        pts, radii = [], []
        for i in range(14):
            t = i / 13
            pts.append((sx * (0.13 + 0.16 * math.sin(t * math.pi * 0.55)), 0.24 + 0.2 * t ** 1.4 - 0.05 * math.sin(t * math.pi), 0.0))
            radii.append(0.042 * (1.0 - t) ** 0.8 + 0.003)
        objs.append(fin(sweep("HH_Horn", pts, radii, "Bone", sides=10), angle=60))
        objs.append(fin(torus("HH_HornRing", (sx * 0.15, 0.25, 0.0), 0.043, 0.008, "Iron", 'YZ', 20, 6), angle=80))
    objs += neck_stub("HH")
    face = face_plate("FacePlate", (0.0, 0.17, 0.118), 0.2, 0.1, bend=0.9)
    empties = [socket(rot_z=180.0), anchor("Top", (0.0, 0.365, 0.0), 180.0), shape_sphere("Head", (0.0, 0.2, 0.0), 0.16)]
    return objs, empties, [face]


# ----------------------------------------------------------------------------------------------------------------------
# служебное: булевы операции, запекание трансформа, пятна, рожки
# ----------------------------------------------------------------------------------------------------------------------
def _bool(o, other, op):
    """Булева операция EXACT над o ('UNION' / 'INTERSECT' / 'DIFFERENCE'); other удаляется, материал — из слотов o."""
    m = o.modifiers.new("Bool", 'BOOLEAN')
    m.operation = op
    m.solver = 'EXACT'
    m.object = other
    K.select_only(o)
    bpy.ops.object.modifier_apply(modifier=m.name)
    bpy.data.objects.remove(other, do_unlink=True)
    return o


def _xf(o, m):
    """Трансформ в координатах Godot, запечённый в меш (matrix_world у деталей кита — единица)."""
    o.data.transform(G2B @ m @ B2G)
    return o


def _basis(d, p):
    """Кадр на поверхности: локальная Z = d (наружу), Y — «вверх» вдоль поверхности, начало в p."""
    z = Vector(d).normalized()
    up = Vector((0.0, 1.0, 0.0)) if abs(z.y) < 0.95 else Vector((0.0, 0.0, -1.0))
    y = (up - z * up.dot(z)).normalized()
    x = y.cross(z)
    m = Matrix.Identity(4)
    for r in range(3):
        m[r][0], m[r][1], m[r][2] = x[r], y[r], z[r]
    m.translation = Vector(p)
    return m


def _blob(rx, ry, seed, n=18):
    """Контур пятна: эллипс rx × ry, радиус промодулирован двумя синусами (seed → фазы); звёздный, без самопересечений."""
    rnd = random.Random(seed)
    p1, p2 = rnd.uniform(0.0, TAU), rnd.uniform(0.0, TAU)
    pts = []
    for i in range(n):
        a = TAU * i / n
        k = 1.0 + 0.16 * math.sin(2 * a + p1) + 0.1 * math.sin(3 * a + p2)
        pts.append((math.cos(a) * rx * k, math.sin(a) * ry * k))
    return pts


def _ring_on(name, pts, k, r, minor, mat, segs=16, sides=6):
    """Кольцо-обойма на трубке sweep: в точке pts[k], плоскость ⟂ касательной."""
    p = Vector(pts[k])
    t = Vector(pts[k + 1]) - Vector(pts[k - 1])
    o = torus(name, (0.0, 0.0, 0.0), r, minor, mat, 'XZ', segs, sides)
    return fin(_xf(o, align_y(t, p)), angle=80)


def _frame(name, center, hw, hh, minor, mat, z, n=24, sides=5):
    """Облегчённая rounded_frame (24 × 5 вместо 32 × 6): для голов, где треугольники на счету."""
    return fin(sweep(name, [(x, y, z) for x, y in superellipse(center[0], center[1], hw, hh, n, 5.0)], minor, mat, sides=sides,
                     closed=True), angle=70)


def _cow_shell(name, mat, grow=0.0):
    """Брус коровьей головы. grow > 0 — раздутая копия с окном шире рамки: пятно = раздутая оболочка ∩ призма,
    так оно ложится по фаскам и обрывается у рамки фото."""
    shell = box(name, (0.30 + 2 * grow, 0.29 + 2 * grow, 0.27 + 2 * grow), mat, (0.0, 0.2, 0.0))
    K.bevel_apply(shell, 0.06 + grow, 4, 30.0)
    if grow > 0.0:
        cut_box(shell, (0.0, 0.23, 0.17), (0.23, 0.19, 0.1))
    else:
        cut_box(shell, (0.0, 0.23, 0.145), (0.21, 0.17, 0.05))
    return shell


def build_Head_Cow(base="PaintWhite"):
    """Корова: белый брус в чёрных пятнах-накладках, морда с ноздрями и латунным кольцом, костяные рожки в обоймах,
    чёрные уши, бирка цвета игрока в левом ухе."""
    objs = [fin(_cow_shell("HW_Shell", "Base_" + base), 0.0, angle=50.0)]
    # пятна: (точка на поверхности, нормаль, rx, ry, seed); друг на друга не заходят
    spots = [((0.135, 0.24, 0.112), (0.6, 0.0, 0.8), 0.055, 0.08, 11),           # левая передняя кромка
             ((-0.125, 0.32, 0.11), (-1.0, 1.0, 1.0), 0.07, 0.055, 23),          # правый верхний угол у рамки
             ((-0.125, 0.085, 0.11), (-1.0, -0.6, 1.0), 0.045, 0.04, 67),        # правый нижний угол у морды
             ((0.15, 0.12, -0.06), (1.0, 0.0, 0.0), 0.07, 0.05, 37),             # левый бок внизу
             ((-0.132, 0.327, -0.07), (-0.707, 0.707, 0.0), 0.06, 0.06, 41),     # правый бок → макушка
             ((0.03, 0.24, -0.135), (0.0, 0.0, -1.0), 0.08, 0.065, 53)]          # затылок
    for p, d, rx, ry, seed in spots:
        prism = extrude2d("HW_Spot", _blob(rx, ry, seed, 14), -0.07, 0.05, "Rubber", xf=_basis(d, p))
        objs.append(fin(_bool(prism, _cow_shell("_grow", "Rubber", 0.004), 'INTERSECT'), 0.0, angle=35.0))
    muzzle = box("HW_Muzzle", (0.21, 0.075, 0.09), "Bone", (0.0, 0.095, 0.12))
    K.bevel_apply(muzzle, 0.03, 2, 30.0)
    for sx in (-1, 1):
        cut_sphere(muzzle, (sx * 0.048, 0.1, 0.17), 0.016, 10)
    objs.append(fin(muzzle, 0.0, angle=50.0))
    for sx in (-1, 1):
        objs.append(fin(sphere("HW_Nostril", 0.013, (sx * 0.048, 0.1, 0.146), "Rubber", 8, 4), angle=80))
    objs.append(fin(torus("HW_NoseRing", (0.0, 0.07, 0.163), 0.026, 0.0055, "Brass", 'XY', 16, 5), angle=80))
    for sx in (-1, 1):
        pts, radii = [], []
        for i in range(10):
            t = i / 9
            pts.append((sx * (0.105 + 0.075 * math.sin(t * math.pi / 2)), 0.3 + 0.085 * t * t, -0.02 + 0.015 * t))
            radii.append(0.024 * (1.0 - t) ** 0.8 + 0.004)
        objs.append(fin(sweep("HW_Horn", pts, radii, "Bone", sides=7), angle=60))
        objs.append(_ring_on("HW_HornRing", pts, 4, 0.021, 0.006, "Iron", 12, 5))
        d = Vector((sx * 1.0, -0.55, 0.12)).normalized()
        ear = [(0.0, 0.0), (0.028, 0.0), (0.04, 0.022), (0.038, 0.045), (0.024, 0.07), (0.0, 0.082)]
        objs.append(fin(revolve("HW_Ear", ear, "Rubber", 12, align_y(d, (sx * 0.135, 0.255, -0.035)) @ S((1.0, 1.0, 0.42))),
                        angle=60.0))
    objs.append(rbox("HW_EarTag", (0.03, 0.036, 0.008), "Shirt_Kit", (0.182, 0.212, -0.012), 0.003, 1))
    objs.append(_frame("HW_Frame", (0.0, 0.23), 0.106, 0.086, 0.009, "Iron", 0.127))
    objs += neck_stub("HW")
    face = face_plate("FacePlate", (0.0, 0.23, 0.121), 0.2, 0.155)
    empties = [socket(rot_z=180.0), anchor("Top", (0.0, 0.345, 0.0), 180.0), shape_box("Head", (0.0, 0.2, 0.0), (0.30, 0.29, 0.27))]
    return objs, empties, [face]


def build_Head_Devil(base="PaintRed"):
    """Чёртик: крашеный брус клином к подбородку, чёрные рожки в кольцах цвета игрока, острые уши, бородка-клинышек."""
    c = (0.0, 0.195, 0.0)
    shell = box("HD_Shell", (0.30, 0.28, 0.27), "Base_" + base, c)
    for v in shell.data.vertices:          # клин: низ уже верха (в меше Blender z = y Godot)
        if v.co.z < c[1]:
            v.co.x *= 0.8
    K.bevel_apply(shell, 0.07, 4, 30.0)
    cut_box(shell, (0.0, 0.2, 0.145), (0.21, 0.17, 0.05))
    objs = [fin(shell, 0.0, angle=50.0)]
    objs.append(rounded_frame("HD_Frame", (0.0, 0.2), 0.106, 0.086, 0.009, "Iron", 0.127))
    for sx in (-1, 1):
        pts, radii = [], []
        for i in range(11):
            t = i / 10
            pts.append((sx * (0.075 + 0.05 * math.sin(t * math.pi)), 0.3 + 0.13 * t, -0.01 - 0.02 * t))
            radii.append(0.028 * (1.0 - t) ** 0.85 + 0.003)
        objs.append(fin(sweep("HD_Horn", pts, radii, "Iron", sides=8), angle=60))
        objs.append(_ring_on("HD_HornRing", pts, 2, 0.027, 0.0065, "Shirt_Kit"))
        d = Vector((sx * 0.78, 0.55, -0.3)).normalized()
        ear = [(0.0, 0.0), (0.04, 0.0), (0.043, 0.02), (0.032, 0.05), (0.016, 0.08), (0.0, 0.1)]
        objs.append(fin(revolve("HD_Ear", ear, "Base_" + base, 16, align_y(d, (sx * 0.125, 0.225, -0.01)) @ S((1.0, 1.0, 0.35))),
                        angle=60.0))
    objs.append(fin(spike("HD_Goatee", (0.0, 0.08, 0.095), (0.0, -1.0, 0.5), 0.08, 0.026, "Rubber", 8), angle=60))
    objs += neck_stub("HD")
    face = face_plate("FacePlate", (0.0, 0.2, 0.121), 0.2, 0.16)
    empties = [socket(rot_z=180.0), anchor("Top", (0.0, 0.335, 0.0), 180.0), shape_box("Head", c, (0.28, 0.28, 0.27))]
    return objs, empties, [face]


def build_Head_Skull(base="Bone"):
    """Череп: круглый лоб, скулы, глазницы с угольками Ядра, нос-сердечко, зубы, челюсть на болтах. Фото — карточкой
    на лбу, приколото кнопкой цвета игрока (лор: Башня заводит на каждого карточку с фото)."""
    b = "Base_" + base
    rb = 0.065                              # фаска лба: по ней загибается карточка
    shell = box("HS_Cranium", (0.28, 0.24, 0.27), b, (0.0, 0.24, -0.01))
    K.bevel_apply(shell, rb, 3, 30.0)
    for nm, size, cen, bev in (("HS_Cheeks", (0.23, 0.08, 0.13), (0.0, 0.16, 0.058), 0.03),
                               ("HS_Maxilla", (0.16, 0.07, 0.11), (0.0, 0.115, 0.065), 0.025)):
        part = box(nm, size, b, cen)
        K.bevel_apply(part, bev, 2, 30.0)
        _bool(shell, part, 'UNION')
    for sx in (-1, 1):
        cut_sphere(shell, (sx * 0.058, 0.16, 0.136), 0.041, 16)
        cut_sphere(shell, (sx * 0.012, 0.115, 0.128), 0.019, 10)
    objs = [fin(shell, 0.0, angle=50.0)]
    objs.append(rbox("HS_Base", (0.15, 0.08, 0.15), b, (0.0, 0.095, -0.045), 0.03, 2))      # затылок над шеей
    objs.append(rbox("HS_Jaw", (0.16, 0.04, 0.11), b, (0.0, 0.035, 0.055), 0.016, 2))
    objs.append(rbox("HS_Mouth", (0.14, 0.03, 0.02), "Rubber", (0.0, 0.07, 0.1), 0.006, 1))
    for i in range(6):
        objs.append(rbox("HS_Tooth", (0.022, 0.028, 0.022), "Bone", (-0.065 + 0.026 * i, 0.084, 0.112), 0.006, 1))
    for i in range(5):
        objs.append(rbox("HS_Tooth", (0.02, 0.02, 0.018), "Bone", (-0.052 + 0.026 * i, 0.058, 0.1), 0.005, 1))
    for sx in (-1, 1):
        objs.append(rbox("HS_Ramus", (0.026, 0.11, 0.06), b, (sx * 0.087, 0.075, 0.0), 0.01, 2))
        objs.append(fin(stud("HS_Hinge", (sx * 0.1, 0.1, 0.0), (sx, 0, 0), "Iron", 0.017, 0.008, 10)))
        objs.append(fin(stud("HS_HingeBolt", (sx * 0.106, 0.1, 0.0), (sx, 0, 0), "Steel", 0.008, 0.006, 6)))
        # тёмная чашка по стенкам глазницы (концентрична вырезу, срезана на 5 мм ниже края) и уголёк Ядра на дне
        cup = sphere("HS_Socket", 0.038, (sx * 0.058, 0.16, 0.136), "Rubber", 12, 6)
        cut_box(cup, (sx * 0.058, 0.16, 0.168), (0.1, 0.1, 0.1))
        objs.append(fin(cup, angle=80))
        objs.append(fin(sphere("HS_Ember", 0.007, (sx * 0.058, 0.155, 0.112), "CoreGlow", 8, 4), angle=80))
    objs += neck_stub("HS")

    def drop(x, y):
        """Насколько поверхность лба уходит назад от плоскости z = 0.125 (скруглённые кромки бруса, r = rb)."""
        dx, dy = max(0.0, abs(x) - (0.14 - rb)), max(0.0, y - (0.36 - rb))
        return rb - math.sqrt(max(0.0, rb * rb - dx * dx - dy * dy))

    # карточка: чуть наискось, в 3 мм над лбом, загнута по фаске
    face = face_plate("FacePlate", (0.0, 0.272, 0.0), 0.19, 0.15, rows=10)
    _xf(face, T((0.0, 0.272, 0.0)) @ Rz(-3.0) @ T((0.0, -0.272, 0.0)))
    for v in face.data.vertices:           # Blender (x, −z, y) ← Godot (x, y, z)
        v.co.y = -(0.128 - drop(v.co.x, v.co.z))
    dy = 0.33 - (0.36 - rb)
    n = Vector((0.0, dy, math.sqrt(rb * rb - dy * dy)))
    pin = [(0.0, -0.004), (0.004, -0.004), (0.004, 0.003), (0.016, 0.003), (0.016, 0.008), (0.009, 0.011), (0.009, 0.02),
           (0.013, 0.022), (0.013, 0.027), (0.0, 0.029)]
    objs.append(fin(revolve("HS_Pin", pin, "Shirt_Kit", 10, align_y(n, (0.0, 0.33, 0.128 - drop(0.0, 0.33)))), angle=50.0))
    empties = [socket(rot_z=180.0), anchor("Top", (0.0, 0.36, -0.01), 180.0), shape_box("Head", (0.0, 0.2, -0.01), (0.28, 0.3, 0.27))]
    return objs, empties, [face]


def build_Head_Can(base="Iron"):
    """Консервная банка: жесть с рифлями и закатками, бумажная этикетка с фото и полосками цвета игрока,
    крышка с кольцом-ключом на заклёпке."""
    R = 0.14
    prof = [(0.0, 0.059), (R - 0.012, 0.059), (R - 0.007, 0.055), (R + 0.004, 0.056), (R + 0.007, 0.062), (R + 0.002, 0.068)]
    for y in (0.084, 0.106):               # рифли под этикеткой и над ней
        prof += [(R, y - 0.008), (R + 0.005, y), (R, y + 0.008)]
    prof += [(R, 0.311), (R + 0.005, 0.318), (R, 0.325), (R + 0.002, 0.331), (R + 0.007, 0.337), (R + 0.005, 0.344),
             (R - 0.003, 0.345), (R - 0.009, 0.339), (R - 0.012, 0.336), (R - 0.03, 0.336), (R - 0.034, 0.339), (R - 0.038, 0.336),
             (0.0, 0.336)]
    objs = [fin(revolve("HN_Body", prof, "Base_" + base, 28), angle=40.0, uv="cyl")]
    objs.append(fin(revolve("HN_Label", [(R - 0.001, 0.125), (R + 0.003, 0.125), (R + 0.003, 0.305), (R - 0.001, 0.305)], "Bone", 28,
                            closed=True), angle=40.0, uv="cyl"))
    for y in (0.131, 0.299):
        objs.append(fin(revolve("HN_Stripe", [(R + 0.002, y - 0.006), (R + 0.005, y - 0.006), (R + 0.005, y + 0.006),
                                              (R + 0.002, y + 0.006)], "Shirt_Kit", 28, closed=True), angle=40.0, uv="cyl"))
    tab = sweep("HN_Tab", K.stadium((0.0, 0.0, 0.0), 0.028, 0.014, 'XY', 16), 0.0045, "Steel", sides=6, closed=True)
    objs.append(fin(_xf(tab, T((0.0, 0.345, 0.06)) @ Rx(70.0)), angle=70))
    objs.append(fin(stud("HN_TabRivet", (0.0, 0.336, 0.03), (0, 1, 0), "Steel", 0.01, 0.005, 8)))
    objs += neck_stub("HN")
    face = face_plate("FacePlate", (0.0, 0.215, R + 0.006), 0.2, 0.15, bend=4.1)
    empties = [socket(rot_z=180.0), anchor("Top", (0.0, 0.345, 0.0), 180.0), shape_cyl("Head", (0.0, 0.2, 0.0), 0.147, 0.29)]
    return objs, empties, [face]


def build_Head_Lantern(base="Brass"):
    """Фонарь: латунный каркас на заклёпках, закопчённые стёкла по бокам и сзади (роль Glass — янтарное полупрозрачное: сбоку
    и сзади виден огарок), спереди решётка, за ней фото на латунной подложке; огарок с огоньком Ядра, крыша-пирамида, шарик цвета
    игрока и кольцо-ручка."""
    b = "Base_" + base
    q = math.pi / 4                         # revolve на 4 сегмента с фазой 45° — квадрат с гранями вдоль осей
    objs = [fin(revolve("HL_Plinth", [(0.0, 0.05), (0.168, 0.05), (0.18, 0.058), (0.18, 0.072), (0.165, 0.086), (0.0, 0.086)], b, 4,
                        phase=q), 0.003, 1, angle=40.0)]
    for y0, y1 in ((0.086, 0.104), (0.284, 0.302)):
        objs.append(fin(revolve("HL_Frame", [(0.148, y0), (0.172, y0), (0.172, y1), (0.148, y1)], b, 4, closed=True, phase=q),
                        0.003, 1, angle=40.0))
    for sx in (-1, 1):
        for sz in (-1, 1):
            objs.append(rbox("HL_Post", (0.026, 0.2, 0.026), b, (sx * 0.113, 0.193, sz * 0.113), 0.006, 1))
        objs.append(fin(box("HL_Glass", (0.006, 0.18, 0.2), "Glass", (sx * 0.113, 0.194, 0.0)), angle=40.0))
        objs.append(fin(sweep("HL_Bar", [(sx * 0.062, 0.1, 0.113), (sx * 0.062, 0.29, 0.113)], 0.0065, "Iron", sides=8), angle=70))
        for y in (0.095, 0.293):
            objs.append(fin(stud("HL_Rivet", (sx * 0.113, y, 0.123), (0, 0, 1), "Steel", 0.007, 0.004, 6)))
    objs.append(fin(box("HL_Glass", (0.2, 0.18, 0.006), "Glass", (0.0, 0.194, -0.113)), angle=40.0))
    objs.append(fin(revolve("HL_Roof", [(0.0, 0.3), (0.19, 0.3), (0.19, 0.312), (0.13, 0.335), (0.05, 0.352), (0.035, 0.356),
                                        (0.0, 0.356)], b, 4, phase=q), 0.003, 1, angle=40.0))
    objs.append(fin(revolve("HL_Finial", [(0.0, 0.35), (0.014, 0.35), (0.014, 0.372), (0.0, 0.372)], b, 10), uv="cyl"))
    objs.append(fin(sphere("HL_Knob", 0.02, (0.0, 0.378, 0.0), "Shirt_Kit", 14, 7), angle=80))
    objs.append(fin(torus("HL_Handle", (0.0, 0.418, 0.0), 0.032, 0.007, "Iron", 'XY', 20, 6), angle=80))
    cz = 0.095
    objs.append(fin(revolve("HL_Dish", [(0.0, 0.086), (0.028, 0.086), (0.031, 0.093), (0.026, 0.095), (0.0, 0.095)], "Brass", 14,
                            T((0.0, 0.0, cz))), uv="cyl"))
    objs.append(fin(revolve("HL_Candle", [(0.0, 0.094), (0.015, 0.094), (0.015, 0.118), (0.011, 0.122), (0.0, 0.122)], "Bone", 12,
                            T((0.0, 0.0, cz))), uv="cyl"))
    objs.append(fin(revolve("HL_Flame", [(0.0, 0.121), (0.008, 0.127), (0.009, 0.133), (0.005, 0.142), (0.0, 0.151)], "CoreGlow", 10,
                            T((0.0, 0.0, cz))), angle=80.0))
    # подложка карточки: сквозь заднее стекло видна латунная пластина, а не пустота за односторонней плашкой лица
    objs.append(fin(box("HL_CardBack", (0.196, 0.156, 0.004), b, (0.0, 0.21, 0.066)), angle=40.0))
    objs += neck_stub("HL")
    face = face_plate("FacePlate", (0.0, 0.21, 0.07), 0.19, 0.15)
    empties = [socket(rot_z=180.0), anchor("Top", (0.0, 0.356, 0.0), 180.0), shape_box("Head", (0.0, 0.2, 0.0), (0.26, 0.3, 0.26))]
    return objs, empties, [face]


# Метаданные для kit_catalog.json (BODY_KIT.md §3.3): масса, энергия. Множитель удара головой — Tuning.BODY_MULT["Head"] × материал
# (builder пишет таблицу в PartDef по name_prefix) × hit_mult — множитель удара ЭТОЙ формой (PartDef.hit_mult): рогатый шлем 1.3,
# рожки чёртика 1.15, коровы 1.1; своего body_mult у головы нет
META = {
    "Head_Round": {"kind": "head", "title": "Голова-игрушка", "mass": 4.0, "energy": 8},
    "Head_Crate": {"kind": "head", "title": "Голова-ящик", "mass": 3.5, "energy": 7},
    "Head_Bot": {"kind": "head", "title": "Голова-экран", "mass": 4.5, "energy": 9},
    "Head_Horned": {"kind": "head", "title": "Рогатый шлем", "mass": 6.0, "energy": 12, "hit_mult": 1.3},
    "Head_Cow": {"kind": "head", "title": "Голова-корова", "mass": 4.3, "energy": 9, "hit_mult": 1.1},
    "Head_Devil": {"kind": "head", "title": "Голова-чёртик", "mass": 4.0, "energy": 9, "hit_mult": 1.15},
    "Head_Skull": {"kind": "head", "title": "Череп с карточкой", "mass": 3.2, "energy": 7},
    "Head_Can": {"kind": "head", "title": "Голова-банка", "mass": 3.5, "energy": 8},
    "Head_Lantern": {"kind": "head", "title": "Голова-фонарь", "mass": 5.0, "energy": 10},
}
